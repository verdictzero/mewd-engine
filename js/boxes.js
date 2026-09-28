/* =====================================================================
   MEWD — THE BOXES, AND HOW THEY BURN
   =====================================================================

   The things standing on the grid (js/maps/grid.js): cubes two cells to
   seven cells a side, green, solid, and the only fuel in the world. All
   of them are ONE MESH and ONE DRAW CALL, and each one burns on its own
   clock.

   WHY THIS EXISTS, which is the whole of the design. The fire in this
   game was a simulation: a grid of fuel and heat over the entire world,
   32 units a cell, stepped every other tic, spreading between
   neighbours, cooking the structure over it and swapping the world's
   textures for charred ones when a region was done (js/fire.js, and THE
   THIRD STAGE in js/textures.js). It is honest and it is expensive, and
   at the user's request it is not what this world uses. What you
   actually WATCH when a thing burns is a front crossing it, coals
   behind the front, and a husk after — and that is a shader over one
   number, not a grid over the world.

   So a box carries ONE number, `front`, which is how far the decay has
   swept down it, and everything you see follows from that number and
   the height of the fragment in the box's OWN space:

     above the front   burnt: the paint gone, soot, and coals that cool
                       the further above the front they are, because
                       further above means it burnt longer ago
     at the front      the fire itself, a narrow band off EMBER_RAMP,
                       torn by a hash of the face's own uv so it is a
                       burn line and not a ruler
     below the front   untouched, and lit like everything else

   TOP TO BOTTOM, at the user's request, and it is the one thing here
   that is a choice rather than a consequence: the front starts at the
   cap and descends. Turning it over is the sign of `front` in the
   fragment shader and nothing else.

   WHAT IT COSTS. One vertex attribute the CPU writes, `burn`, thirty
   floats a box, and only for the boxes that are actually alight. No
   grid, no cells, no texture swap, no geometry rebuild. A hundred and
   fifty boxes is 4,500 vertices in one buffer.

   HOW THE FIRE MOVES BETWEEN THEM, since there is no grid to carry it:
   a box that is properly alight lights its neighbours. SPREAD_R is off
   the FOOTPRINT rather than the centre, so a seven-cell box reaches as
   far past its own wall as a two-cell one does, and a box that has
   nearly finished stops recruiting — a husk does not light anything.

   AND WHAT PUTS IT OUT is water (js/water.js) and CO2 (js/frost.js),
   through douse(). Neither unburns anything: `front` only ever goes up,
   the same promise FireSystem.douse makes about a charred aisle. What
   they save is the bottom of the box the fire has not reached yet.
   ===================================================================== */

import * as THREE from 'three';
import { WORLD_UNIFORMS_GLSL, WORLD_SHADE_GLSL, worldUniforms } from './material.js';
import { pRandom } from './util.js';

/* ---------------------------------------------------------------------
   The numbers, all per tic
   --------------------------------------------------------------------- */
/* how long a box takes to burn from cap to floor, per cell of its side:
   a two-cell box is gone in seven seconds and a seven-cell box takes
   twenty-four, which is the size of it being worth something */
export const BURN_TICS_PER_CELL = 120;
/* heat it takes to catch, and what one tic of flame on it is worth */
export const CATCH_AT = 100;
/* how fast heat bleeds off something that is not catching */
export const HEAT_BLEED = 1.4;
/* how far past its own wall a burning box throws fire */
export const SPREAD_R = 300;
/* and the window it does it in: not before the front has got going,
   not once it is nearly out */
export const SPREAD_FROM = 0.16, SPREAD_TO = 0.88;
/* the chance, per tic, that a burning box lights one particular
   neighbour that is in reach */
export const SPREAD_CHANCE = 0.022;
/* how much water it takes to put one out, in douse strength */
export const SOAK_OUT = 260;
/* how near the player a box has to be to be worth throwing particles
   off, and how many may do it in one tic */
const FX_NEAR = 3000, FX_MOST = 10;

/* ---------------------------------------------------------------------
   THE SWEEP, in the box's own height, and the two numbers the shader
   and the collision BOTH have to agree about.

   SOFT is how blurred the front is. DISS is how far above the front the
   burnt stuff takes to crumble away to nothing, at the user's request:
   the box does not leave a husk, it GOES. Which means the front has to
   travel further than the box is tall — its own height, plus the
   crumble — or the last handful of texels at the foot would never get
   far enough above the front to disappear, and a burnt-out box would be
   a doormat that stood there for the rest of the night.
   --------------------------------------------------------------------- */
export const SOFT = 0.085;
export const DISS = 0.62;
/* what the front covers over a whole burn: the box, and then the
   crumble past the bottom of it */
export const SWEEP = 1 + 2 * SOFT + DISS;

/**
 * How much of a box is left STANDING, 0..1 of its height, at burn `t`.
 * The collision reads this; the shader draws the same box.
 *
 * It is not the front. Below the front the box is whole; from the front
 * to a crumble above it the box is flecks with more and more missing;
 * above that there is nothing. Putting the collision at the front would
 * let you walk through something plainly still there, and putting it at
 * the top of the flecks would have the last few specks of ash holding a
 * fire engine up. It sits most of the way through the crumble.
 */
export function standing(t) {
  return Math.max(0, Math.min(1, 1 + SOFT - t * SWEEP + DISS * 0.7));
}

/* ---------------------------------------------------------------------
   THE SHADER

   Its own material rather than createWallMaterial's, which is the shape
   js/particles.js and js/forest.js already use: the lighting is two
   GLSL strings any shader may splice in (see the top of js/material.js)
   so that a thing with its own vertex path still stands in the same
   light as the walls. Splicing them also brings `emberTime` and
   `emberRamp` — the one clock and the one eight colours every burning
   thing in this game is drawn with, so a burning box and a burning fir
   are the same fire going out.
   --------------------------------------------------------------------- */
const BOX_VERT = /* glsl */`
attribute float light;
attribute float localH;     // 0 at the foot of this box, 1 at its cap
attribute float seed;       // this box's own, so no two burn in step
attribute float burn;       // and how far its front has come down, 0..1
varying vec2  vUv;
varying float vLight, vLocalH, vSeed, vBurn, vDepth;
varying vec3  vWorld;
void main() {
  vUv = uv; vLight = light; vLocalH = localH; vSeed = seed; vBurn = burn;
  vec4 wp = modelMatrix * vec4(position, 1.0);
  vWorld = wp.xyz;
  vec4 mv = viewMatrix * wp;
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
`;

const BOX_FRAG = /* glsl */`
precision highp float;
uniform sampler2D map;
uniform float uSky;
${WORLD_UNIFORMS_GLSL}
varying vec2  vUv;
varying float vLight, vLocalH, vSeed, vBurn, vDepth;
varying vec3  vWorld;
${WORLD_SHADE_GLSL}

/* a hash of a face's own uv, at two scales, because one scale at this
   resolution is a repeating pattern rather than a torn edge — the same
   trick the ash in js/material.js uses */
float tearAt(vec2 uv) {
  return emberHash(vec3(floor(uv * vec2(11.0, 17.0)), 0.0)) * 0.62
       + emberHash(vec3(floor(uv * vec2(27.0, 39.0)), 7.0)) * 0.38;
}

void main() {
  vec4 t = texture2D(map, vUv);

  /* WHERE THE FRONT IS. It starts a hair above the cap at burn 0 and
     ends a hair below the foot at burn 1, so that neither end of the
     sweep leaves a band that never quite goes. */
  float soft = ${SOFT.toFixed(3)};
  float tear = (tearAt(vUv) - 0.5) * 0.13;
  /* THE FRONT GOES PAST THE FOOT — see SWEEP. By the time the burn is 1
     the front is a whole crumble-length below the bottom of the box, so
     there is nothing anywhere on it that has not had time to go. */
  float front = 1.0 + soft + tear - vBurn * ${SWEEP.toFixed(4)};
  /* how far ABOVE the front this fragment is: positive is burnt, and
     the bigger it is the longer ago it burnt, because the front came
     down past it first */
  float above = vLocalH - front;
  float swept = smoothstep(-soft, soft, above);

  /* THE PAINT, going. It loses its colour first and then its light,
     which is the order soot goes on in js/material.js, and it keeps a
     little of itself for ever — a burnt green box is still a box. */
  float age = clamp(above / 0.55, 0.0, 1.0);

  /* AND IT DISINTEGRATES, at the user's request. How much of this
     fragment has gone: none of it at the front, all of it a crumble
     above. Speckled by the same hash that tore the front, at a finer
     pitch, so the box comes apart in FLECKS — a wall of ash eaten from
     the top rather than a clean line retreating down it. The last of
     them fade rather than popping, which is what the alpha is for. */
  float gone = smoothstep(0.06, ${DISS.toFixed(3)}, above);
  float grain = tearAt(vUv * 2.7 + 4.0);
  if (grain < gone + 0.002) discard;
  float alpha = smoothstep(gone, gone + 0.20, grain);

  vec3 albedo = t.rgb;
  float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
  albedo = mix(albedo, vec3(lum), swept * 0.75);
  /* AND IT KEEPS A QUARTER OF ITSELF. Taken all the way down, the part
     of the box above the front is black on a black sky, so a burning
     box reads as a box being DELETED from the top rather than one
     turning to charcoal — and the thing is still standing there, still
     solid, still in the way. A husk you can see is the honest picture
     and it is also the one that tells you how much of it is left. */
  albedo *= 1.0 - swept * (0.42 + 0.30 * age);

  float l = worldBand(vLight, vDepth, uSky, 0.0);
  vec3 c = worldShade(albedo, l, vDepth, vWorld, 0.0);

  /* THE FIRE ON IT, and it is two things. The FRONT is a narrow band
     travelling with the sweep and is the brightest thing on the box;
     the COALS are what is left above it, going out with age. Both are
     quantised to EMBER_RAMP, which is the one ramp every burning thing
     in this game uses. */
  float q = above / 0.075;
  float flame = exp(-q * q) * step(0.001, vBurn) * (1.0 - step(0.999, vBurn));
  float coal = swept * (1.0 - smoothstep(0.15, 0.85, age));
  float flick = 0.72 + 0.34
    * sin(emberTime * 8.0 + vSeed * 31.4 + vWorld.y * 0.15)
    * sin(emberTime * 3.3 + vSeed * 12.0 + vWorld.x * 0.11);
  float ember = (flame * 1.15 + coal * 0.42) * flick;
  float heat = clamp(flame * 0.72 + coal * 0.40, 0.0, 1.0);
  float ph = emberTime * 0.9 + vSeed * 6.28 + above * 1.7;
  float wave = abs(fract(ph) * 2.0 - 1.0) - 0.5;
  float idx = clamp(heat * 0.62 + wave * 0.44, 0.0, 1.0);
  vec3 hue = emberRamp[int(floor(idx * 7.0 + 0.5))];

  /* the far end of the field is a green haze and a coal at that
     distance is one bright pixel, which is aliasing rather than fire */
  ember *= 1.0 - smoothstep(2600.0, 5200.0, vDepth);

  if (thermal > 0.5) {
    /* what the scope sees: the front is the hottest thing in the world
       and the husk above it is still warm */
    gl_FragColor = vec4(vec3(max(c.r, clamp(flame * 0.95 + coal * 0.45, 0.0, 1.0))), alpha);
    return;
  }
  gl_FragColor = vec4(c + hue * ember, alpha);
}
`;

/* ---------------------------------------------------------------------
   ONE BOX
   --------------------------------------------------------------------- */
class Box {
  constructor(def, i) {
    this.def = def;
    this.index = i;
    this.x = (def.x0 + def.x1) / 2;
    this.y = (def.y0 + def.y1) / 2;
    this.z = 0;
    this.height = def.height;
    this.cells = def.cells;
    this.heat = 0;
    this.burning = false;
    this.front = 0;                 // 0 untouched, 1 gone
    this.rate = 1 / (BURN_TICS_PER_CELL * def.cells);
    this.tick = 0;
    /* where its vertices are in the one buffer — filled by build() */
    this.at = 0; this.count = 0;
  }

  get spent() { return this.front >= 1; }
  /* still worth lighting a neighbour with */
  get catching() { return this.burning && this.front > SPREAD_FROM && this.front < SPREAD_TO; }
  /**
   * WHERE TO AIM AT IT FROM (fx, fy): a point just outside its nearest
   * face, at the height the front has come down to.
   *
   * The middle of a box is INSIDE a solid, and a solid blocks sight —
   * so anything that asked "can I see the fire" about a box's centre
   * was told no, always, by the box itself. What a hose is aimed at is
   * the face that is alight, and that is out here.
   */
  aimPoint(fx, fy, out = 16) {
    const d = this.def;
    const px = Math.max(d.x0, Math.min(d.x1, fx));
    const py = Math.max(d.y0, Math.min(d.y1, fy));
    const dx = fx - px, dy = fy - py;
    const L = Math.hypot(dx, dy) || 1;
    return { x: px + (dx / L) * out, y: py + (dy / L) * out, z: this.height * (1 - this.front) };
  }

  /* how near a point is to its FOOTPRINT rather than to its middle, so
     a seven-cell box is not harder to light than a two-cell one */
  near2(x, y) {
    const d = this.def;
    const dx = x < d.x0 ? d.x0 - x : x > d.x1 ? x - d.x1 : 0;
    const dy = y < d.y0 ? d.y0 - y : y > d.y1 ? y - d.y1 : 0;
    return dx * dx + dy * dy;
  }
}

/* ---------------------------------------------------------------------
   ALL OF THEM
   --------------------------------------------------------------------- */
export class Boxes {
  /**
   * @param game
   * @param texture  the GRIDBOX sheet, or null headless
   */
  constructor(game, texture = null) {
    this.game = game;
    this.texture = texture;
    this.list = (game.level.boxes || []).map((d, i) => new Box(d, i));
    this.mesh = null;
    this.burnAttr = null;
    this.lit = 0;              // how many have ever caught
    this.spentCount = 0;
    this.tics = 0;
    this._fxAt = 0;
  }

  get count() { return this.list.length; }
  get burningCount() { let n = 0; for (const b of this.list) if (b.burning) n++; return n; }
  /** Everything still standing, which is what the brigade is for. A box
   *  the fire has taken all of is not one, whether it finished burning
   *  or was put out with nothing left. */
  get standingCount() { let n = 0; for (const b of this.list) if (!b.gone) n++; return n; }

  /* ------------------------------------------------------------------
     THE MESH: five faces a box — four sides and a cap, and no
     underside, because nothing ever sees the bottom of a box standing
     on the floor. Every face carries the height of its corners in the
     box's own space, which is the whole of what the shader needs.
     ------------------------------------------------------------------ */
  build(scene) {
    if (!this.texture || !this.list.length) return null;
    const n = this.list.length;
    const VERTS = 5 * 6;                       // five quads, two triangles each
    const pos = new Float32Array(n * VERTS * 3);
    const uv = new Float32Array(n * VERTS * 2);
    const light = new Float32Array(n * VERTS);
    const localH = new Float32Array(n * VERTS);
    const seed = new Float32Array(n * VERTS);
    const burn = new Float32Array(n * VERTS);
    let p = 0, q = 0, k = 0;

    /* Doom's fake contrast, the same notch js/car.js and js/level.js
       take: a face looking north or south reads a step brighter than one
       looking east or west, so the corner between two faces of one solid
       green box is visible at all. The cap gets the lift. */
    const FACE = [0.94, 1.06, 0.94, 1.06];     // south, east, north, west
    const CAP = 1.16;

    for (const b of this.list) {
      const d = b.def;
      const sd = (b.index * 0.6180339887) % 1;
      b.at = k; b.count = VERTS;
      const H = d.height;
      /* the four walls, counter-clockwise on the plan so every one of
         them looks out — the same walk boxGeometry in js/mapgeo.js
         makes, and for the same reason */
      const walls = [
        [d.x0, d.y0, d.x1, d.y0],
        [d.x1, d.y0, d.x1, d.y1],
        [d.x1, d.y1, d.x0, d.y1],
        [d.x0, d.y1, d.x0, d.y0],
      ];
      const push = (x, y, z, u, v, lit, h) => {
        pos[p++] = x; pos[p++] = z; pos[p++] = -y;      // map y is the renderer's -z
        uv[q++] = u; uv[q++] = v;
        light[k] = lit; localH[k] = h; seed[k] = sd; burn[k] = 0; k++;
      };
      walls.forEach(([ax, ay, bx, by], f) => {
        const w = Math.hypot(bx - ax, by - ay) / 64;    // one repeat is one cell
        const hh = H / 64;
        const lit = Math.min(1.4, (d.light ?? 0.58) * FACE[f]);
        /* two triangles, wound so the face looks outward */
        push(bx, by, H, w, 0, lit, 1); push(ax, ay, H, 0, 0, lit, 1); push(ax, ay, 0, 0, hh, lit, 0);
        push(bx, by, H, w, 0, lit, 1); push(ax, ay, 0, 0, hh, lit, 0); push(bx, by, 0, w, hh, lit, 0);
      });
      /* and the cap, planar */
      const uw = (d.x1 - d.x0) / 64, vh = (d.y1 - d.y0) / 64;
      const capLit = Math.min(1.4, (d.light ?? 0.58) * CAP);
      push(d.x0, d.y0, H, 0, 0, capLit, 1); push(d.x1, d.y0, H, uw, 0, capLit, 1); push(d.x1, d.y1, H, uw, vh, capLit, 1);
      push(d.x0, d.y0, H, 0, 0, capLit, 1); push(d.x1, d.y1, H, uw, vh, capLit, 1); push(d.x0, d.y1, H, 0, vh, capLit, 1);
    }

    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
    g.setAttribute('light', new THREE.Float32BufferAttribute(light, 1));
    g.setAttribute('localH', new THREE.Float32BufferAttribute(localH, 1));
    g.setAttribute('seed', new THREE.Float32BufferAttribute(seed, 1));
    const ba = new THREE.Float32BufferAttribute(burn, 1);
    /* the one buffer that is rewritten while the game runs */
    ba.setUsage?.(THREE.DynamicDrawUsage);
    g.setAttribute('burn', ba);
    g.computeBoundingSphere();
    this.burnAttr = ba;

    const mat = new THREE.ShaderMaterial({
      uniforms: { map: { value: this.texture }, uSky: { value: 0 }, ...worldUniforms() },
      vertexShader: BOX_VERT,
      fragmentShader: BOX_FRAG,
      side: THREE.FrontSide,
      /* IT HAS AN ALPHA CHANNEL because it disintegrates — see the
         fragment shader. Depth is still written: what is left of a box
         is solid and has to occlude what is behind it, and the flecks
         that are on their way out are a texel or two wide. */
      transparent: true,
      depthWrite: true,
      toneMapped: false,
      fog: false,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.name = 'boxes';
    this.mesh.frustumCulled = false;      // one mesh over the whole field
    scene?.add(this.mesh);
    return this.mesh;
  }

  attach(scene) { return this.build(scene); }

  /** One box's front into the buffer. */
  _write(b) {
    if (!this.burnAttr) return;
    this.burnAttr.array.fill(b.front, b.at, b.at + b.count);
    this.burnAttr.needsUpdate = true;
  }

  /* ------------------------------------------------------------------
     CATCHING, BURNING AND GOING OUT
     ------------------------------------------------------------------ */
  /** Heat into whatever is near a point — the same shape of call
   *  FireSystem.ignite takes, and it is routed here from there so that
   *  every weapon in the game lights a box without knowing boxes
   *  exist. Returns how many caught. */
  ignite(x, y, strength = 60, radius = 64) {
    let lit = 0;
    const r = radius + 40;
    for (const b of this.list) {
      if (b.spent || b.burning) continue;
      const d2 = b.near2(x, y);
      if (d2 > r * r) continue;
      /* nearer is hotter, and a big bang lights a whole row */
      const fall = 1 - Math.sqrt(d2) / r;
      b.heat += strength * (0.35 + 0.65 * fall);
      if (b.heat >= CATCH_AT) { this.light(b); lit++; }
    }
    return lit;
  }

  /** This one is alight now. */
  light(b) {
    if (b.burning || b.spent) return false;
    b.burning = true;
    b.heat = CATCH_AT;
    this.lit++;
    this.game.sound?.play('burn', b);
    return true;
  }

  /** Water or gas on it: the heat comes off, and enough of it stops the
   *  front where it stands. What has burnt has burnt. */
  douse(x, y, strength = 90, radius = 64) {
    let hit = 0;
    const r = radius + 40;
    for (const b of this.list) {
      const d2 = b.near2(x, y);
      if (d2 > r * r) continue;
      const fall = 1 - Math.sqrt(d2) / r;
      const take = strength * (0.35 + 0.65 * fall);
      b.heat = Math.max(0, b.heat - take);
      hit++;
      if (b.burning) {
        b.soaked = (b.soaked || 0) + take;
        if (b.soaked >= SOAK_OUT) { b.burning = false; b.soaked = 0; b.heat = 0; }
      }
    }
    return hit;
  }

  /** Every box that is alight, or near one that is. */
  tic() {
    this.tics++;
    const g = this.game, p = g.player;
    let fx = 0;
    for (const b of this.list) {
      if (!b.burning) {
        if (b.heat > 0) b.heat = Math.max(0, b.heat - HEAT_BLEED);
        continue;
      }
      b.front = Math.min(1, b.front + b.rate);
      this._write(b);
      /* AND IT IS IN THE WAY ONLY AS LONG AS IT IS THERE. The sector
         under a box is a floor at the height of it (js/maps/grid.js);
         as the box goes, that floor comes down with it, so a thing
         burnt to a stub is a stub you can see over and then step on.
         `spent` is front >= 1 and is asked rather than set — the front
         is the one number a box has and everything else reads off it. */
      this._stand(b);
      if (b.spent) { b.burning = false; this.spentCount++; this._vanish(b); }

      /* IT LIGHTS ITS NEIGHBOURS, which is the only way fire crosses
         this field: there is no grid under it to carry one. */
      if (b.catching) {
        for (const o of this.list) {
          if (o === b || o.burning || o.spent) continue;
          if (o.near2(b.x, b.y) > (SPREAD_R + b.def.side) ** 2) continue;
          const dx = Math.max(0, Math.max(b.def.x0 - o.def.x1, o.def.x0 - b.def.x1));
          const dy = Math.max(0, Math.max(b.def.y0 - o.def.y1, o.def.y0 - b.def.y1));
          if (dx * dx + dy * dy > SPREAD_R * SPREAD_R) continue;
          if (pRandom() / 255 < SPREAD_CHANCE) this.light(o);
        }
      }

      /* AND WHAT COMES OFF IT, budgeted: the sparks and the smoke leave
         the FRONT, which is a height up the box and comes down it, so
         the smoke walks down with the fire. Only near the player, and
         only a few a tic — a field of a hundred burning boxes is a
         hundred emitters and the particle pool is four hundred. */
      if (!p || fx >= FX_MOST) continue;
      const d2 = (b.x - p.x) ** 2 + (b.y - p.y) ** 2;
      if (d2 > FX_NEAR * FX_NEAR) continue;
      fx++;
      const zf = b.height * (1 - b.front);
      if ((++b.tick & 1) === 0) g.fx?.ember(b.x, b.y, zf, 1, 0.7 + 0.5 * (1 - b.front));
      if ((b.tick % 7) === 0) g.fx?.puff(b.x, b.y, zf + 10, 20 + b.cells * 3, 150);
      g.fx?.glowAt(b.x, b.y, 0.5 + 1.3 * (1 - Math.abs(b.front - 0.5) * 2) * 0.8 + 0.4);
      /* a burning box is a thing that hurts to stand next to */
      if ((b.tick % 9) === 0) this._scorch(b);
    }
  }

  /** The sector under a box, or null for a world that never said. */
  _sector(b) {
    const i = b.def.sector;
    return i === undefined ? null : (this.game.level.sectors[i] || null);
  }

  /** What is left of it, as a floor you cannot step over. */
  _stand(b) {
    const sec = this._sector(b);
    if (!sec) return;
    const h = Math.round(b.height * standing(b.front));
    if (h !== sec.floor) { sec.floor = h; sec.baseFloor = h; }
    /* AND WHEN THERE IS NOTHING LEFT it stops being a box, whether it
       burnt all the way or the brigade caught it a hair short: what
       decides is what is STANDING, not whether the front reached the
       bottom. A box put out with nothing left of it is still nothing
       left of it, and a fire engine may drive over the ash. */
    if (h === 0) this._vanish(b);
  }

  /** NOTHING IS LEFT OF IT. The floor goes back to the field's, so you
   *  may walk over where it stood and see across it — and a fire engine
   *  may drive over the ash, which it could not over the box. */
  _vanish(b) {
    const sec = this._sector(b);
    if (!sec || b.gone) return;
    const f = this.game.level.field || {};
    sec.floor = sec.baseFloor = f.floor ?? 0;
    sec.outdoor = true;
    sec.sky = 0;
    b.gone = true;
  }

  /** What a burning box does to whoever is beside it. */
  _scorch(b) {
    const g = this.game;
    const reach = b.def.side / 2 + 70;
    const p = g.player;
    if (p && !p.dead && b.near2(p.x, p.y) < reach * reach) p.damage?.(2, null, { fire: true });
    const near = g.blockmap ? g.blockmap.near(b.x, b.y, this._near || (this._near = [])) : g.actors;
    for (let i = 0; i < near.length; i++) {
      const a = near[i];
      if (a.removed || a.dead || a.vehicle || !a.info?.flammable) continue;
      if (b.near2(a.x, a.y) > reach * reach) continue;
      a.ignite?.();
    }
  }

  /** What the thermal sight and the brigade want to know: where the
   *  fire in this world actually is. Each entry { x, y, z, box }. */
  burningList(out = []) {
    out.length = 0;
    for (const b of this.list) if (b.burning) out.push({ x: b.x, y: b.y, z: b.height * (1 - b.front), box: b });
    return out;
  }

  /** The nearest burning box to a point, or null. */
  nearestBurning(x, y, within = Infinity) {
    let best = null, bd = within * within;
    for (const b of this.list) {
      if (!b.burning) continue;
      const d2 = b.near2(x, y);
      if (d2 < bd) { bd = d2; best = b; }
    }
    return best;
  }
}
