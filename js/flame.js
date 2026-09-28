/* =====================================================================
   MEWD — the flame
   =====================================================================

   What comes out of the gun. Not a cone of damage applied to a list —
   that is what it was, and it set fire to everything within four
   metres of the player the instant the trigger went down, including
   the player. It is a STREAM now: a few particles a tic leave the
   nozzle at speed, in a slight spread, and fly. They slow in the air,
   they drop, and where one lands it puts heat into the world — the
   store's fuel grid, the forest's, whatever it hit. So the flame goes
   where you point it, it reaches, and it arcs down to the floor a
   dozen metres out unless you lift the nozzle, which is the whole
   feel of a flamethrower and is why one is fun to hold.

   THE NUMBERS ARE PER TIC, like everything else in the game. Thirty
   units a tic is about a thousand a second; with the drag below a
   particle has covered four hundred units before its life runs out,
   and gravity has it on the floor a little before that when fired
   level. That is the reach, and `streamReach` computes it so the
   smoke test can hold it to a number.

   HEAT, NOT ACCELERANT. The strength put into the fuel grid stays
   under the threshold the fire system uses to lay accelerant, so the
   flame lights what is there and never makes bare lino burn — that is
   the bottle's job. What it does do is start a fire exactly where it
   lands, which in a shop full of stock is enough.
   ===================================================================== */

import { Particles } from './particles.js';
import { pRandom, dist2 } from './util.js';
import { wallNormal, UP, DOWN } from './decals.js';

export const STREAM = {
  perTic: 6,          // particles a tic while the trigger is down, staggered along the tic
  speed: 30,          // units a tic, leaving the nozzle
  jitter: 0.04,       // radians of spread either way
  life: 40,           // tics in the air at most
  drag: 0.972,        // speed kept per tic
  gravity: -0.22,     // units a tic a tic
  size0: 8,           // world units across, leaving the nozzle
  size1: 44,          // and at the end of its life
  alpha: 0.5,         // per particle; they add up where they overlap
  heat: 36,           // what it puts into the fuel grid where it lands
  heatRadius: 22,     // how far round the landing the store's grid takes it
  treeRadius: 26,     // how much forest one landing lights
};

/** How far a particle travels before its life runs out, ignoring the
 *  drop: the stream's nominal reach. */
export function streamReach(s = STREAM) {
  let d = 0, v = s.speed;
  for (let i = 0; i < s.life; i++) { d += v; v *= s.drag; }
  return d;
}

/** How far out a level shot has fallen to the floor from a given height. */
export function streamDrop(height, s = STREAM) {
  let d = 0, v = s.speed, z = height, vz = 0;
  for (let i = 0; i < s.life; i++) {
    vz += s.gravity; vz *= s.drag;
    z += vz;
    if (z <= 0) return d;
    d += v; v *= s.drag;
  }
  return d;
}

export class FlameStream {
  /**
   * @param game
   * @param atlas  { texture, frames } of flame frames, or null headless
   */
  constructor(game, atlas = null) {
    this.game = game;
    /* Additive: overlapping fire adds up toward white, so a dense enough
       stream is one unbroken tongue with a hot core and soft edges, and
       the end of it dissolves instead of popping. */
    this.particles = new Particles({
      max: 420, texture: atlas?.texture || null, frames: atlas?.frames || 8,
      blend: 'add', fullbright: true, name: 'flame', renderOrder: 11, nearShrink: 30,
    });
    this.firing = 0;
    this.glow = { x: 0, y: 0, z: 0, w: 0 };
    this._hits = 0;
  }

  attach(scene) { this.particles.attach(scene); }

  /** One tic's worth of flame from a point, in a direction. `pitch` is
   *  the player's: positive looks up. */
  fire(origin, angle, pitch) {
    this.firing = 3;
    const s = STREAM;
    for (let k = 0; k < s.perTic; k++) {
      const a = angle + (pRandom() / 255 - 0.5) * s.jitter * 2;
      const p = pitch + (pRandom() / 255 - 0.5) * s.jitter * 1.4;
      const sp = s.speed * (0.94 + (pRandom() / 255) * 0.12);
      const ch = Math.cos(p);
      const vx = Math.cos(a) * ch * sp, vy = Math.sin(a) * ch * sp, vz = Math.sin(p) * sp;
      /* STAGGERED ALONG THE TIC. Six particles born at the same point
         once a tic are six beads thirty units apart; six born along the
         first tic's travel, each a sixth of a tic older than the last,
         are five units apart — a line, not a string of beads. */
      const f = k / s.perTic;
      this.particles.spawn({
        x: origin.x + vx * f, y: origin.y + vy * f, z: origin.z + vz * f,
        vx, vy, vz, age: f,
        life: Math.round(s.life * (0.9 + (pRandom() / 255) * 0.2)),
        size0: s.size0, size1: s.size1,
        c0: [1.0, 0.92, 0.66], c1: [1.0, 0.32, 0.08],
        a0: s.alpha, a1: 0.0,
        frame: pRandom() & 7, frameRate: 0.6,
        drag: s.drag, gravity: s.gravity,
      });
    }
  }

  tic() {
    if (this.firing > 0) this.firing--;
    const g = this.game, lv = g.level, P = this.particles;
    const actors = g.actors;
    P.tic((i, nx, ny, nz) => {
      const x = P.x[i], y = P.y[i], z = P.z[i];
      /* Walls first: a flame that reaches through the frozen aisle into
         the stockroom is not a weapon, it is a cheat code. */
      const wall = lv.rayHitWall(x, y, z, nx, ny, nz);
      if (wall) { this._land(wall.x, wall.y, wall.z, wallNormal(wall.line, x, y)); return true; }
      const sec = lv.sectorAt(nx, ny);
      const floor = sec ? sec.floor : 0;
      if (nz <= floor + 4) { this._land(nx, ny, floor, UP); return true; }
      if (sec && sec.ceilTex !== 'SKY' && nz >= sec.ceil - 4) { this._land(nx, ny, sec.ceil, DOWN); return true; }
      for (let k = 0; k < actors.length; k++) {
        const a = actors[k];
        if (a.removed || a.dead || !a.shootable) continue;
        const rr = a.radius + 12;
        if (dist2(nx, ny, a.x, a.y) > rr * rr) continue;
        if (nz < a.z - 6 || nz > a.z + a.height + 10) continue;
        this._burnActor(a, nx, ny, nz);
        return true;
      }
      if (g.forest && g.forest.hitsTree(nx, ny, nz)) { this._land(nx, ny, nz); return true; }
      return false;
    });

    /* the burning end of the stream is a light: where the flame is
       going, on average, not where it left */
    let sx = 0, sy = 0, sz = 0, n = 0;
    for (let i = 0; i < P.max; i++) {
      if (!P.alive[i] || P.age[i] < 4) continue;
      sx += P.x[i]; sy += P.y[i]; sz += P.z[i]; n++;
    }
    if (n) { this.glow.x = sx / n; this.glow.y = sy / n; this.glow.z = sz / n; this.glow.w = Math.min(1, n / 20); }
    else this.glow.w = 0;
  }

  /** A particle has arrived somewhere. Heat goes into whatever fuel is
   *  there — the store's grid and the forest's both, since only one of
   *  them will have anything at that point. */
  _land(x, y, z, surface = null) {
    const g = this.game;
    this._hits++;
    g.fire?.ignite(x, y, STREAM.heat, STREAM.heatRadius);
    g.forest?.ignite(x, y, STREAM.treeRadius);
    g.fx?.splash(x, y, z);
    /* and the surface itself heats where the stream is held on it —
       see js/decals.js, SPOT HEATING. A tree is not a surface. */
    if (surface) g.decals?.heat(x, y, z, surface);
  }

  _burnActor(a, x, y, z) {
    /* LIGHT IT FIRST, THEN HURT IT, and the order is the whole of why a
       shopper now runs instead of coming apart where they stood. A
       shopper has twelve health and this does five to nine, so the
       second particle of the stream — same tic — used to finish them
       before anything had a chance to set them alight. Igniting first
       starts the countdown in Actor.ignite, and a thing with a countdown
       running ignores fire damage until it runs out. */
    if (a.flammable) a.ignite?.(300);
    /* `stream` is for the vehicles, which the stream lights rather than
       hurts — see Vehicle.damage; a person takes it as fire like before */
    a.damage(5 + (pRandom() % 5), this.game.player, { fire: true, stream: true });
    this.game.fire?.ignite(x, y, STREAM.heat, 24);
    this.game.fx?.splash(x, y, z);
  }

  glowInto(acc) {
    if (this.glow.w <= 0) return;
    const w = this.glow.w * 1.4;
    acc.sx += this.glow.x * w; acc.sy += this.glow.y * w; acc.sw += w; acc.n++;
  }

  get liveCount() { return this.particles.count; }

  render(billboardRot) { this.particles.render(billboardRot); }
}
