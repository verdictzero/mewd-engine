/* =====================================================================
   MEWD — the arc maw's lightning
   =====================================================================

   THE SEVENTH WEAPON, at the user's request, and the request was the
   whole design: "between the three prongs on the business end a
   lightning bolt will come out and chain-arc up to 9 people, with field
   effect damage for people nearby, lots of trailing falling particle
   effects, hit particle effects, charging is a thing too where blue
   energy particles will gather in the weapon's maw generating an ever
   growing blue energy ball, more charge = more chain hits".

   THE CHARGE is the player's (Player.arcCharge, 0..1, see arcTic) and
   the ball and the gathering are the gun's (js/weapon3d.js, `orb` in
   GUNS). What this file owns is what happens when the trigger comes up:

     THE FIRST TARGET is whoever is nearest the middle of the sight,
     inside a narrow cone, in range and in plain view. Nobody there and
     the bolt goes straight down the sight into whatever stops it.

     THE CHAIN hops from each body to the nearest one it has not hit
     yet, within CHAIN reach and in plain view of the last, until it has
     made hitsFor(charge) hits — one for a tap, nine at the top of the
     charge — or runs out of people to hop to. It is chosen whole when
     the trigger comes up and then REVEALED a hop a tic, so the eye
     can follow it across a crowd, and each hop's damage lands as it
     arrives. Each hop does a little less than the one before.

     THE FIELD is what a strike does to everybody standing next to it:
     a share of the hop's damage to anyone within FIELD of the hit who
     is not in the chain, with a short arc to each of them to say so.

   THE DAMAGE IS NOT FIRE. Lightning is not a flame, and the SWAT and the
   army are fireproof — damage that is not fire hurts them, and shatters
   anybody frozen solid, which is what a bolt through ice should do.

   WHAT YOU SEE: every link a jagged line of light, re-cut every other
   tic so it crawls, a wide blue glow under a white core, with forks off
   it; a burst at every strike; and DRIPS — hot blue sparks shaken off
   the bolt and the strikes that fall, bounce once, and leave a trail of
   fading motes behind them all the way down.

   Game coordinates throughout (x, y across the map, z up); the mesh is
   built in three's (x, z, -y) like everything else.
   ===================================================================== */

import * as THREE from 'three';
import { Particles } from './particles.js';
import { pRandom, clamp } from './util.js';
import { SMOKE_PUFFS } from './effects.js';

export const ARC = {
  chargeTics: 105,      // tics of trigger held to a full charge: three seconds
  most: 9,              // strikes in a chain at the top of the charge
  range: 2400,          // how far the first strike can reach
  cone: 0.15,           // radians off the sight the first target may be
  chain: 560,           // how far a hop can reach from the last strike
  field: 150,           // and how far the field around a strike reaches
  fieldShare: 0.4,      // the share of the hop's damage the field deals
  fieldMost: 5,         // arcs drawn to people caught in one strike's field
  damage0: 48,          // a strike's damage off a tap
  damage1: 190,         // and off a full charge
  falloff: 0.92,        // each hop does this much of the one before
  hopTics: 1,           // tics between one strike and the next being revealed
  /* SUB-BOLTS, at the user's request: thinner branches thrown off a
     strike at random, which find somebody the chain passed over — bonus
     kills — or, with nobody near enough, ground into the floor */
  subChance0: 0.35,     // the chance a strike throws one, off a tap
  subChance1: 0.8,      // and off a full charge
  subMost: 3,           // the most one strike can throw
  subReach: 430,        // how far a branch can reach for somebody
  subShare: 0.55,       // the share of the strike's damage a branch deals
  life: 16,             // tics a bolt stays lit after its last strike
};

/** How many strikes a charge buys: one for a tap, nine at the top. */
export function hitsFor(charge) { return 1 + Math.round(clamp(charge, 0, 1) * (ARC.most - 1)); }

/** What the first strike does at a charge; each hop after is less. */
export function strikeDamage(charge, hop = 0) {
  return (ARC.damage0 + (ARC.damage1 - ARC.damage0) * clamp(charge, 0, 1)) * Math.pow(ARC.falloff, hop);
}

const MAX_QUADS = 3072;
const SEG = 26;               // units of bolt per jag
const NEAR = 160;             // units from the eye inside which a bolt is drawn thinner

const VERT = /* glsl */`
attribute float aFade;
attribute float aCore;
varying float vFade;
varying float vCore;
void main() {
  vFade = aFade; vCore = aCore;
  gl_Position = projectionMatrix * viewMatrix * vec4(position, 1.0);
}
`;
const FRAG = /* glsl */`
varying float vFade;
varying float vCore;
void main() {
  /* the core white with a breath of blue, the glow a deep electric blue */
  vec3 c = mix(vec3(0.16, 0.42, 1.0) * 0.55, vec3(0.86, 0.94, 1.0), vCore);
  gl_FragColor = vec4(c * vFade, 1.0);
}
`;

export class ArcSystem {
  constructor(game) {
    this.game = game;
    this.bolts = [];            // { nodes, reveal, t, hops, seed, forks, charge }
    this.drips = [];            // falling sparks: { x, y, z, vx, vy, vz, life, bounced }
    this.fired = 0;
    this.strikes = 0;           // every strike ever, chain and field
    this.lastChain = [];        // the last discharge's chain, for the suite and the HUD
    this.subs = 0;              // sub-bolts thrown, ever
    this.bonusKills = 0;        // and the people they killed that the chain never touched
    this.shake = 0;
    this.mesh = null;
    /* the sparks — square, bright, additive: the embers' own texture —
       and the glow of a strike, the smoke's puffs drawn additively blue */
    this.sparks = new Particles({ max: 2600, texture: null, frames: 1, blend: 'add', fullbright: true,
                                  name: 'arc-sparks', renderOrder: 13, nearShrink: 120 });
    this.glows = new Particles({ max: 160, texture: null, frames: SMOKE_PUFFS, blend: 'add', fullbright: true,
                                 name: 'arc-glows', renderOrder: 13, nearShrink: 90 });
    this._dir = { x: 0, y: 0, z: 0 };
  }

  /* ------------------------------------------------------------------
     Who gets hit
     ------------------------------------------------------------------ */
  /** A body that can take a bolt. */
  canStrike(a) { return !!a && a.shootable && !a.dead && !a.removed && typeof a.damage === 'function'; }

  /** Where on a body a bolt lands: the chest. */
  chest(a, out = { x: 0, y: 0, z: 0 }) {
    out.x = a.x; out.y = a.y; out.z = (a.z || 0) + (a.height || 56) * 0.58;
    return out;
  }

  /** Nearest the middle of the sight, inside the cone, in range and in view. */
  firstTarget(p) {
    const g = this.game, cp = Math.cos(p.pitch);
    const dx = Math.cos(p.angle) * cp, dy = Math.sin(p.angle) * cp, dz = Math.sin(p.pitch);
    let best = null, score = Infinity;
    const c = { x: 0, y: 0, z: 0 };
    for (const a of g.actors) {
      if (!this.canStrike(a)) continue;
      this.chest(a, c);
      const vx = c.x - p.x, vy = c.y - p.y, vz = c.z - p.eyeZ;
      const d = Math.hypot(vx, vy, vz);
      if (d < 1 || d > ARC.range) continue;
      const off = Math.acos(clamp((vx * dx + vy * dy + vz * dz) / d, -1, 1));
      if (off > ARC.cone) continue;
      const s = off + (d / ARC.range) * 0.04;
      if (s >= score) continue;
      if (g.level.sightBlocked(p.x, p.y, p.eyeZ, c.x, c.y, c.z)) continue;
      best = a; score = s;
    }
    return best;
  }

  /** The next hop: the nearest body not already struck, in reach and in view. */
  nextTarget(from, struck) {
    const g = this.game;
    let best = null, bd = ARC.chain * ARC.chain;
    const c = { x: 0, y: 0, z: 0 };
    for (const a of g.actors) {
      if (!this.canStrike(a) || struck.has(a)) continue;
      this.chest(a, c);
      const d2 = (c.x - from.x) ** 2 + (c.y - from.y) ** 2 + (c.z - from.z) ** 2;
      if (d2 >= bd) continue;
      if (g.level.sightBlocked(from.x, from.y, from.z, c.x, c.y, c.z)) continue;
      best = a; bd = d2;
    }
    return best;
  }

  /** Straight down the sight to whatever stops it: a wall, the floor, or range. */
  sightEnd(p) {
    const g = this.game, cp = Math.cos(p.pitch);
    const bx = p.x + Math.cos(p.angle) * cp * ARC.range, by = p.y + Math.sin(p.angle) * cp * ARC.range;
    const bz = p.eyeZ + Math.sin(p.pitch) * ARC.range;
    const w = g.level.rayHitWall(p.x, p.y, p.eyeZ, bx, by, bz);
    let t = w ? w.t : 1;
    /* and the floor or the ceiling, marched, since a bolt aimed down
       ends at your feet and not at the wall behind them */
    for (let k = 1; k <= 48; k++) {
      const f = (k / 48) * t;
      const x = p.x + (bx - p.x) * f, y = p.y + (by - p.y) * f, z = p.eyeZ + (bz - p.eyeZ) * f;
      const s = g.level.sectorAt(x, y);
      if (s && (z <= s.floor + 1 || z >= s.ceil - 1)) { t = f; break; }
    }
    return { x: p.x + (bx - p.x) * t, y: p.y + (by - p.y) * t, z: p.eyeZ + (bz - p.eyeZ) * t };
  }

  /* ------------------------------------------------------------------
     The discharge
     ------------------------------------------------------------------ */
  /** The trigger has come up on a charge of `charge`, 0..1. Returns how
   *  many bodies the chain will strike (the field is on top of that). */
  fire(p, charge) {
    const g = this.game;
    this.fired++;
    const n = hitsFor(charge);
    const from = g.nozzle ? g.nozzle() : { x: p.x, y: p.y, z: p.eyeZ - 8 };
    const nodes = [{ x: from.x, y: from.y, z: from.z, who: null, muzzle: true }];
    const struck = new Set();
    let at = this.firstTarget(p);
    while (at && struck.size < n) {
      struck.add(at);
      nodes.push({ ...this.chest(at), who: at });
      at = this.nextTarget(nodes[nodes.length - 1], struck);
    }
    if (!struck.size) nodes.push({ ...this.sightEnd(p), who: null });
    this.lastChain = [...struck];
    this.bolts.push({ nodes, reveal: 0, t: 0, charge, struck, seed: (pRandom() << 8) | pRandom(), fields: [], subs: [] });
    g.sound?.play(charge > 0.6 ? 'arcbig' : 'arcfire', from);
    g.noise?.(from, 1400 + 1200 * charge);
    this.shake = Math.max(this.shake, 0.25 + 0.5 * charge);
    this.strike(this.bolts[this.bolts.length - 1], 1);
    return struck.size;
  }

  /** One strike of a bolt: the hop reaches node `i`. */
  strike(b, i) {
    const g = this.game, p = g.player;
    const node = b.nodes[i];
    if (!node) return;
    b.reveal = i;
    const a = node.who;
    if (a) this.chest(a, node);
    this.burst(node.x, node.y, node.z, 0.6 + 0.6 * b.charge);
    if (a) {
      const dmg = strikeDamage(b.charge, i - 1);
      this.strikes++;
      if (this.canStrike(a)) a.damage(this.lethal(a, dmg), p, { shock: true });
      /* THE FIELD: everybody standing next to the strike who is not in
         the chain takes a share, and an arc to say so */
      let drawn = 0;
      const c = { x: 0, y: 0, z: 0 };
      for (const o of g.actors) {
        if (o === a || b.struck.has(o) || !this.canStrike(o)) continue;
        this.chest(o, c);
        const d = Math.hypot(c.x - node.x, c.y - node.y, c.z - node.z);
        if (d > ARC.field) continue;
        this.strikes++;
        o.damage(this.lethal(o, dmg * ARC.fieldShare * (1 - 0.5 * d / ARC.field)), p, { shock: true });
        if (drawn++ < ARC.fieldMost) {
          b.fields.push({ a: { x: node.x, y: node.y, z: node.z }, who: o, t: 0 });
          this.burst(c.x, c.y, c.z, 0.35);
        }
      }
      this.branch(b, node, dmg);
      g.sound?.play('arczap', node);
    } else if (!node.muzzle) {
      /* a bolt into the scenery leaves a scorch where it grounded */
      const s = g.level.sectorAt(node.x, node.y);
      if (s && node.z <= s.floor + 2) g.decals?.heat?.(node.x, node.y, s.floor, { nx: 0, ny: 0, nz: 1 }, 0.7);
    }
    g.fx?.glowAt?.(node.x, node.y, 2.5 + 3 * b.charge);
  }

  /** SUB-BOLTS: the branches a strike throws, at random, more of them the
   *  higher the charge. Each reaches for somebody near the strike that
   *  the chain has not taken — chosen at random from everybody in reach
   *  and in view, not the nearest, so they spray — and deals a share of
   *  the strike; a kill that way is a bonus kill. A branch with nobody to
   *  reach for grounds into the floor a little way off instead. */
  branch(b, node, dmg) {
    const g = this.game, p = g.player;
    b.subs ||= [];
    const chance = ARC.subChance0 + (ARC.subChance1 - ARC.subChance0) * b.charge;
    let n = 0;
    while (n < ARC.subMost && pRandom() / 256 < chance * (n ? 0.6 : 1)) n++;
    if (!n) return;
    const near = [], c = { x: 0, y: 0, z: 0 };
    for (const o of g.actors) {
      if (!this.canStrike(o) || b.struck.has(o)) continue;
      this.chest(o, c);
      if (Math.hypot(c.x - node.x, c.y - node.y, c.z - node.z) > ARC.subReach) continue;
      if (g.level.sightBlocked(node.x, node.y, node.z, c.x, c.y, c.z)) continue;
      near.push(o);
    }
    for (let k = 0; k < n; k++) {
      const from = { x: node.x, y: node.y, z: node.z };
      this.subs++;
      if (near.length) {
        const o = near.splice(pRandom() % near.length, 1)[0];
        b.subs.push({ a: from, who: o, to: null, t: 0, seed: (pRandom() << 8) | pRandom() });
        this.strikes++;
        o.damage(this.lethal(o, dmg * ARC.subShare), p, { shock: true });
        if (o.dead) this.bonusKills++;
        this.chest(o, c);
        this.burst(c.x, c.y, c.z, 0.45);
      } else {
        /* nobody: it grounds, somewhere on the floor round the strike */
        const a = (pRandom() / 256) * Math.PI * 2, r = 50 + (pRandom() / 256) * 150;
        const x = node.x + Math.cos(a) * r, y = node.y + Math.sin(a) * r;
        const s = g.level.sectorAt(x, y);
        if (!s) continue;
        const to = { x, y, z: s.floor };
        b.subs.push({ a: from, who: null, to, t: 0, seed: (pRandom() << 8) | pRandom() });
        this.burst(x, y, s.floor + 2, 0.3);
      }
    }
  }

  /** A BOLT KILLS AND DOES NOT BURST. Damage far past what a body has
   *  left is what the game reads as a body coming apart — the gibbing
   *  death, a burst of red and fire — and a shopper has a dozen points
   *  against a strike's two hundred, so a chain of nine was nine
   *  explosions and looked like a rocket, not lightning. A strike is
   *  held to what the body has, and a little over, so it drops. */
  lethal(a, dmg) {
    const has = (a.health ?? dmg) + (a.armour1 ?? 0) + (a.armour2 ?? 0);
    return Math.min(dmg, Math.max(1, has + 4));
  }

  /** The light and the sparks of one strike. */
  burst(x, y, z, size = 1) {
    for (let k = 0; k < 3; k++)
      this.glows.spawn({
        x, y, z, vx: 0, vy: 0, vz: 0.2,
        life: 7 + k * 3, size0: (28 + k * 26) * size, size1: (70 + k * 30) * size,
        c0: [0.55, 0.78, 1.0], c1: [0.05, 0.18, 0.6], a0: 1, a1: 0,
        frame: pRandom() % SMOKE_PUFFS, frameRate: 0.3,
      });
    const n = Math.round(22 * size);
    for (let k = 0; k < n; k++) {
      const a = (pRandom() / 255) * Math.PI * 2, e = (pRandom() / 255) * 1.2 - 0.2;
      const sp = 2 + (pRandom() / 255) * 7 * size;
      this.sparks.spawn({
        x, y, z, vx: Math.cos(a) * Math.cos(e) * sp, vy: Math.sin(a) * Math.cos(e) * sp, vz: Math.sin(e) * sp + 1.5,
        life: 10 + (pRandom() % 14), size0: 3.2, size1: 1.2,
        c0: [0.85, 0.95, 1.0], c1: [0.15, 0.35, 1.0], a0: 1, a1: 0.2,
        drag: 0.93, gravity: -0.32,
      });
    }
    /* and a few that are heavier and carry a trail all the way down */
    for (let k = 0; k < Math.round(4 * size); k++) this.drip(x, y, z, 3 + 3 * size);
  }

  /** One falling spark that leaves a trail. */
  drip(x, y, z, speed = 3) {
    if (this.drips.length > 220) return;
    const a = (pRandom() / 255) * Math.PI * 2;
    const sp = (0.3 + (pRandom() / 255)) * speed;
    this.drips.push({ x, y, z, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, vz: 1 + (pRandom() / 255) * 3,
                      life: 40 + (pRandom() % 40), bounced: false });
  }

  /* ------------------------------------------------------------------
     One tic
     ------------------------------------------------------------------ */
  tic() {
    const g = this.game;
    this.sparks.tic();
    this.glows.tic();
    this.shake = Math.max(0, this.shake - 0.05);
    for (let k = this.bolts.length - 1; k >= 0; k--) {
      const b = this.bolts[k];
      b.t++;
      const want = Math.min(b.nodes.length - 1, 1 + Math.floor(b.t / ARC.hopTics));
      while (b.reveal < want) this.strike(b, b.reveal + 1);
      /* the bodies move and the bolt stays on them */
      for (const n of b.nodes) if (n.who && !n.who.removed) this.chest(n.who, n);
      for (const f of b.fields) f.t++;
      for (const sb of b.subs) {
        sb.t++;
        /* and the branches shed their own drips */
        if (sb.t < ARC.life && (pRandom() & 7) === 0) {
          const to = sb.who ? this.chest(sb.who) : sb.to, f = pRandom() / 256;
          this.drip(sb.a.x + (to.x - sb.a.x) * f, sb.a.y + (to.y - sb.a.y) * f, sb.a.z + (to.z - sb.a.z) * f, 1.6);
        }
      }
      /* shake sparks off every lit link as it burns */
      for (let i = 1; i <= b.reveal; i++) {
        if ((pRandom() & 3) !== 0) continue;
        const A = b.nodes[i - 1], B = b.nodes[i], f = pRandom() / 255;
        const x = A.x + (B.x - A.x) * f, y = A.y + (B.y - A.y) * f, z = A.z + (B.z - A.z) * f;
        this.drip(x, y, z, 2.2);
        this.sparks.spawn({ x, y, z, vx: 0, vy: 0, vz: -0.5, life: 16, size0: 2.6, size1: 1,
                            c0: [0.8, 0.92, 1.0], c1: [0.1, 0.3, 1.0], a0: 1, a1: 0, drag: 0.96, gravity: -0.28 });
      }
      if (b.reveal >= b.nodes.length - 1 && b.t > (b.nodes.length - 1) * ARC.hopTics + ARC.life) this.bolts.splice(k, 1);
    }
    /* the drips fall, leaving a mote behind them every tic */
    for (let i = this.drips.length - 1; i >= 0; i--) {
      const d = this.drips[i];
      d.vz -= 0.36; d.vx *= 0.985; d.vy *= 0.985;
      d.x += d.vx; d.y += d.vy; d.z += d.vz;
      const s = g.level.sectorAt(d.x, d.y);
      if (s && d.z <= s.floor) {
        if (d.bounced || d.vz > -2.5) { this.drips.splice(i, 1); continue; }
        d.z = s.floor; d.vz *= -0.35; d.bounced = true;
      }
      if (--d.life <= 0) { this.drips.splice(i, 1); continue; }
      this.sparks.spawn({ x: d.x, y: d.y, z: d.z, vx: 0, vy: 0, vz: 0,
                          life: 12, size0: 2.8, size1: 0.6,
                          c0: [0.75, 0.9, 1.0], c1: [0.08, 0.2, 0.85], a0: 0.95, a1: 0 });
    }
  }

  /* ------------------------------------------------------------------
     Drawing
     ------------------------------------------------------------------ */
  attach(scene) {
    if (this.mesh) return;
    const N = MAX_QUADS;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 12), 3));
    geo.setAttribute('aFade', new THREE.BufferAttribute(new Float32Array(N * 4), 1));
    geo.setAttribute('aCore', new THREE.BufferAttribute(new Float32Array(N * 4), 1));
    const idx = new Uint16Array(N * 6);
    for (let i = 0; i < N; i++) { const v = i * 4, k = i * 6; idx[k] = v; idx[k + 1] = v + 1; idx[k + 2] = v + 2; idx[k + 3] = v; idx[k + 4] = v + 2; idx[k + 5] = v + 3; }
    geo.setIndex(new THREE.BufferAttribute(idx, 1));
    geo.setDrawRange(0, 0);
    const mat = new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG, transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false, toneMapped: false,
    });
    this.mesh = new THREE.Mesh(geo, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 13;
    this.mesh.name = 'arc-bolts';
    scene.add(this.mesh);
  }

  /** A jagged line from A to B into `out` as [x, y, z, ...]: midpoint
   *  displacement off a seed, fixed at both ends, widest in the middle. */
  jag(A, B, seed, rough, out) {
    let s = seed >>> 0 || 1;
    const rnd = () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) / 4294967296) - 0.5; };
    const dx = B.x - A.x, dy = B.y - A.y, dz = B.z - A.z;
    const L = Math.hypot(dx, dy, dz) || 1;
    /* two directions across the line */
    let ux = -dy, uy = dx, uz = 0;
    let ul = Math.hypot(ux, uy, uz);
    if (ul < 1e-3) { ux = 1; uy = 0; uz = 0; ul = 1; }
    ux /= ul; uy /= ul; uz /= ul;
    const vx = (dy * uz - dz * uy) / L, vy = (dz * ux - dx * uz) / L, vz = (dx * uy - dy * ux) / L;
    const n = clamp(Math.round(L / SEG), 3, 48);
    out.length = 0;
    let ox = 0, oy = 0;
    for (let i = 0; i <= n; i++) {
      const f = i / n, taper = Math.sin(Math.PI * f);
      ox = ox * 0.55 + rnd() * rough * L * 0.16;
      oy = oy * 0.55 + rnd() * rough * L * 0.16;
      const e = (i === 0 || i === n) ? 0 : taper;
      out.push(A.x + dx * f + (ux * ox + vx * oy) * e,
               A.y + dy * f + (uy * ox + vy * oy) * e,
               A.z + dz * f + (uz * ox + vz * oy) * e);
    }
    return out;
  }

  /** `ex, ey, ez` is the eye. */
  render(billboardRot, ex, ey, ez) {
    const g = this.game;
    if (!this.mesh && g.scene) this.attach(g.scene);
    if (!this.sparks.mesh && g.fx?.embers?.opts?.texture && g.scene) {
      this.sparks.opts.texture = g.fx.embers.opts.texture;
      this.sparks.attach(g.scene);
    }
    if (!this.glows.mesh && g.fx?.smoke?.opts?.texture && g.scene) {
      this.glows.opts.texture = g.fx.smoke.opts.texture;
      this.glows.attach(g.scene);
    }
    this.sparks.render?.(billboardRot);
    this.glows.render?.(billboardRot);
    if (!this.mesh) return;
    const geo = this.mesh.geometry;
    const pos = geo.attributes.position.array, fade = geo.attributes.aFade.array, core = geo.attributes.aCore.array;
    let q = 0;
    const pts = this._pts || (this._pts = []);
    const quad = (ax, ay, az, bx, by, bz, w, f, c) => {
      if (q >= MAX_QUADS) return;
      const dx = bx - ax, dy = by - ay, dz = bz - az;
      const vx = ex - ax, vy = ey - ay, vz = ez - az;
      /* AND THIN WHERE IT LEAVES THE GUN. The first link starts a few
         units from the eye, and a ribbon ten units across that close is
         a white wall over half the picture — the tracers' problem, and
         the same answer: nearer than NEAR, it narrows with the distance */
      const near = Math.hypot(vx, vy, vz);
      if (near < NEAR) w *= Math.max(0.06, near / NEAR);
      let sx = dy * vz - dz * vy, sy = dz * vx - dx * vz, sz = dx * vy - dy * vx;
      const sl = Math.hypot(sx, sy, sz) || 1;
      sx = sx / sl * w; sy = sy / sl * w; sz = sz / sl * w;
      const o = q * 12;
      const put = (k, x, y, z) => { pos[o + k * 3] = x; pos[o + k * 3 + 1] = z; pos[o + k * 3 + 2] = -y; };
      put(0, ax - sx, ay - sy, az - sz); put(1, ax + sx, ay + sy, az + sz);
      put(2, bx + sx, by + sy, bz + sz); put(3, bx - sx, by - sy, bz - sz);
      for (let k = 0; k < 4; k++) { fade[q * 4 + k] = f; core[q * 4 + k] = c; }
      q++;
    };
    const line = (P, wGlow, wCore, f) => {
      for (let i = 3; i < P.length; i += 3) {
        quad(P[i - 3], P[i - 2], P[i - 1], P[i], P[i + 1], P[i + 2], wGlow, f * 0.55, 0);
        quad(P[i - 3], P[i - 2], P[i - 1], P[i], P[i + 1], P[i + 2], wCore, f, 1);
      }
    };
    const tick = g.tics >> 1;
    for (const b of this.bolts) {
      const end = (b.nodes.length - 1) * ARC.hopTics;
      const f = b.t <= end ? 1 : clamp(1 - (b.t - end) / ARC.life, 0, 1);
      /* and it flickers as it dies */
      const fl = f * (0.7 + 0.3 * (((tick * 7 + b.seed) % 5) / 4));
      const wide = 1 + 1.2 * b.charge;
      for (let i = 1; i <= b.reveal; i++) {
        const A = b.nodes[i - 1], B = b.nodes[i];
        const seed = b.seed * 31 + i * 977 + tick * 131;
        line(this.jag(A, B, seed, 1, pts), 7 * wide, 1.3 * wide, fl);
        /* a fork or two off every link */
        const P = pts.slice();
        for (let k = 0; k < 2; k++) {
          const j = 3 * (1 + ((seed >>> (k * 5)) % Math.max(1, P.length / 3 - 2)));
          const L = Math.hypot(B.x - A.x, B.y - A.y, B.z - A.z) * 0.28;
          const r = (x) => (((seed * (k + 3) * x) >>> 7) % 1000) / 1000 - 0.5;
          const F = { x: P[j] + r(11) * L, y: P[j + 1] + r(17) * L, z: P[j + 2] + r(23) * L - L * 0.3 };
          line(this.jag({ x: P[j], y: P[j + 1], z: P[j + 2] }, F, seed + k * 7, 1.4, pts), 3.5 * wide, 0.8 * wide, fl * 0.7);
        }
      }
      /* the sub-bolts: thinner, with a fork of their own, and gone sooner */
      for (const sb of b.subs) {
        if (sb.t > ARC.life) continue;
        const to = sb.who ? this.chest(sb.who, { x: 0, y: 0, z: 0 }) : sb.to;
        const P = this.jag(sb.a, to, sb.seed * 7 + tick * 57, 1.25, pts);
        const ff = fl * (1 - sb.t / (ARC.life + 1));
        line(P, 3.6, 0.75, ff);
        const j = 3 * Math.max(1, Math.floor(P.length / 6));
        const L = Math.hypot(to.x - sb.a.x, to.y - sb.a.y, to.z - sb.a.z) * 0.3;
        const q = (sb.seed >>> 3) % 1000 / 1000 - 0.5, r = (sb.seed >>> 9) % 1000 / 1000 - 0.5;
        line(this.jag({ x: P[j], y: P[j + 1], z: P[j + 2] }, { x: P[j] + q * L, y: P[j + 1] + r * L, z: P[j + 2] - L * 0.4 },
                      sb.seed + tick, 1.4, pts), 2.2, 0.5, ff * 0.7);
      }
      for (const fd of b.fields) {
        if (fd.t > ARC.life || !fd.who) continue;
        const c = this.chest(fd.who, { x: 0, y: 0, z: 0 });
        line(this.jag(fd.a, c, b.seed + fd.t * 13 + tick, 1.3, pts), 3.2, 0.7, fl * (1 - fd.t / ARC.life));
      }
    }
    geo.setDrawRange(0, q * 6);
    geo.attributes.position.needsUpdate = true;
    geo.attributes.aFade.needsUpdate = true;
    geo.attributes.aCore.needsUpdate = true;
  }
}
