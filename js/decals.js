/* =====================================================================
   DEWM — decals: what a weapon leaves on a surface
   =====================================================================

   THREE KINDS, at the user's request, and they are one system:

     HOLES   where a round lands on a wall, a floor or a ceiling. A dark
             ragged spot a hand across, turned at random, and it stays.
             A minigun puts a hundred and forty of them a second into
             whatever it is pointed at, so a burst across the parade
             reads as a burst across the parade rather than a noise
             that happened. The troopers' rifles leave them too.

     HEAT    SPOT HEATING for the flamethrower: where the stream lands
             the surface itself starts to glow, and the longer the
             stream stays on one spot the hotter the spot — dull red,
             orange, the yellow-white of a thing about to give — and
             when the stream moves on it cools over a few seconds and
             leaves a SCORCH, a dark blot the size of the glow, for
             good. Drawn additively, its own light.

     FROST   SPOT COOLING for the extinguisher: where the jet lands the
             surface rimes over, whiter the longer the jet stays, and
             thaws away over ten seconds when it moves on. It leaves
             nothing; ice does not.

   AND THE TWO ARGUE. Gas landing near a hot spot takes the heat out of
   it, and flame landing near frost melts it, both at a distance rather
   than only on a direct hit — so the extinguisher can be used to cool
   a glowing wall, and the flamethrower to clear the rime off one,
   which is the same pair of verbs the two weapons already have for
   people and fires, here on the shop itself.

   EACH KIND IS ONE DRAW CALL: a pool of quads in a single geometry,
   positions written when a decal is placed and an intensity written
   every tic as it cools or thaws, and a slot that has faded to nothing
   is free again. EVERY POOL IS A RING, and a small one, at the user's
   request: a hundred of each kind, and when a pool is full the OLDEST
   IN IT FADE OUT, IN ORDER, rather than being cut — the ten at the
   old end of the ring lose an eighth a tic until they are gone, and
   the cursor arrives on slots that are already empty. A thousand
   rounds into one wall are the last hundred of them, the earliest
   dissolving as the latest land, which reads as a wall being shot
   rather than as a wall with a budget.

   A DECAL SITS ON ITS SURFACE: it is placed a hair off the wall along
   the wall's normal and drawn with a polygon offset, which between
   them keep it from fighting the wall for the pixel. The normal comes
   from whatever was hit — a wall's own line, turned to face the side
   the shot came from; a floor's is up; a ceiling's is down — and the
   quad is laid in the two directions across that normal.

   The arithmetic — the normals, the merging, the cooling — is plain
   data with no three in it, so it runs headless and the smoke test can
   put a stream on a wall and watch it glow and cool.
   ===================================================================== */

import * as THREE from 'three';
import { Pix } from './pixel.js';
import { WORLD_UNIFORMS_GLSL, WORLD_SHADE_GLSL, worldUniforms } from './material.js';
import { pRandom, TICRATE } from './util.js';

/* the pools, and the numbers that make each kind what it is */
export const POOLS = { hole: 100, heat: 100, frost: 100 };
/* HOW MANY HOLES, AND HOW FAR. The hole pool is the MAX COUNT: a
   hundred on the walls at once, at the user's request (it was five
   hundred and twelve, and the accumulation was a cost), which a
   minigun reaches in under a second of holding the trigger — the
   scorches share it. WHEN IT IS FULL THE OLDEST FADE, IN ORDER, and
   the order is the ring's own: the FADE_AHEAD slots at the old end
   are held to a strength that is their PLACE IN THE QUEUE — the one
   about to be overwritten at nothing, the one two dozen from it at
   nearly full, and every step between — so a hole does not fade on a
   clock of its own, it fades as the cursor comes round to it. Under
   the minigun that is a tail of dissolving holes behind the burst;
   with the trigger up it is the oldest few going out and the rest
   standing. Either way nothing is ever cut off the wall. The heat and
   the frost are rings on the same rule, on top of their own cooling
   and thaw.
   And a hole is CULLED when it cannot be seen: past DRAW_RANGE from
   the eye, or behind the plane the eye is looking along, it is not
   written into the buffer at all, so a wall you have shot to pieces
   costs nothing until you turn round and look at it. */
export const FADE_AHEAD = 24;                 // how many slots at the old end of a full ring are fading
export const FADE_RATE = 1 / 4;               // and the most one may lose in a tic: gone in four
/** How bright a decal is allowed to be, `k` slots ahead of the cursor
 *  that is going to overwrite it. SQUARED rather than straight, and
 *  that is the difference between a hole that fades and a hole that is
 *  still a third lit when it vanishes: the ring moves in JUMPS — four
 *  slots a tic under the minigun — so what matters is the value at the
 *  last slot before the cursor arrives, and a square curve puts the
 *  bottom eighth of the band inside a fiftieth of full while leaving
 *  the top of it near enough untouched to not dim a wall nobody has
 *  finished shooting. Pure, for the test. */
export const fadeTarget = k => { const t = k / FADE_AHEAD; return t * t; };
export const DRAW_RANGE = 2600;               // world units from the eye
export const HOLE_SIZE = [5, 9];              // world units across, min..max
export const SCORCH_SIZE = 46;                // the blot a hot spot leaves
export const HEAT_SIZE = 38;
export const FROST_SIZE = 44;
export const HEAT_PER_LANDING = 0.028;        // one flame particle's worth
export const FROST_PER_LANDING = 0.040;       // one puff of gas's worth
export const HEAT_COOL = 1 / (6 * TICRATE);   // a white-hot spot is cold in six seconds
export const FROST_THAW = 1 / (10 * TICRATE); // and rime is gone in ten
export const MERGE_RADIUS = 26;               // a landing this near an existing spot feeds it
export const ARGUE_RADIUS = 44;               // and this near the other kind fights it
export const ARGUE_AMOUNT = 0.10;
export const LIFT = 0.6;                      // how far off the surface a decal sits

/** The normal of a wall line, unit length, facing the side (fx, fy) is
 *  on — the side the shot came from. Pure. */
export function wallNormal(line, fx, fy) {
  const dx = line.x2 - line.x1, dy = line.y2 - line.y1;
  const len = Math.hypot(dx, dy) || 1;
  let nx = dy / len, ny = -dx / len;
  /* which side of the line the shooter is: flip if the normal points away */
  const mx = (line.x1 + line.x2) / 2, my = (line.y1 + line.y2) / 2;
  if (nx * (fx - mx) + ny * (fy - my) < 0) { nx = -nx; ny = -ny; }
  return { nx, ny, nz: 0 };
}
export const UP = Object.freeze({ nx: 0, ny: 0, nz: 1 });
export const DOWN = Object.freeze({ nx: 0, ny: 0, nz: -1 });

/** Two unit directions across a normal, for laying a quad on it: along
 *  the wall and up for a wall, x and y for a floor. Pure. */
const CORNER_U = [-1, 1, 1, -1], CORNER_V = [-1, -1, 1, 1];
/** surfaceBasis without the allocation: the same two axes, written
 *  into `out`. */
export function surfaceBasisInto(nx, ny, nz, out) {
  if (Math.abs(nz) > 0.5) { out.ux = 1; out.uy = 0; out.uz = 0; out.vx = 0; out.vy = 1; out.vz = 0; }
  else { out.ux = -ny; out.uy = nx; out.uz = 0; out.vx = 0; out.vy = 0; out.vz = 1; }
  return out;
}

export function surfaceBasis(n) {
  if (Math.abs(n.nz) > 0.5) return { ux: 1, uy: 0, uz: 0, vx: 0, vy: 1, vz: 0 };
  return { ux: -n.ny, uy: n.nx, uz: 0, vx: 0, vy: 0, vz: 1 };
}

/* ---- one pool: the data, and (once attached) the geometry ---------- */
class Pool {
  constructor(kind, max) {
    this.kind = kind;
    this.max = max;
    this.n = 0;                       // slots ever used, up to max
    this.x = new Float32Array(max); this.y = new Float32Array(max); this.z = new Float32Array(max);
    this.nx = new Float32Array(max); this.ny = new Float32Array(max); this.nz = new Float32Array(max);
    this.size = new Float32Array(max);
    this.rot = new Float32Array(max);
    this.strength = new Float32Array(max);   // 0 = free
    this.peak = new Float32Array(max);       // the most it has ever been
    this.light = new Float32Array(max);
    this.sky = new Float32Array(max);
    this.frame = new Uint8Array(max);        // which picture in the pool's strip
    /* A HOLE IN A VEHICLE RIDES WITH IT: `owner` is the vehicle and the
       l* arrays are the hole in the vehicle's own frame — x along its
       length, y across, z up off the body's floor — turned into world
       space every frame in render(). Nothing else has an owner. */
    this.owner = new Array(max).fill(null);
    this.lx = new Float32Array(max); this.ly = new Float32Array(max); this.lz = new Float32Array(max);
    this.lnx = new Float32Array(max); this.lny = new Float32Array(max); this.lnz = new Float32Array(max);
    this.owned = 0;
    this.next = 0;                           // ring cursor, for the holes
    this.count = 0;
    this.dirtyPos = true; this.dirtyStrength = true;
    this.mesh = null;
  }

  /** The next slot round the ring, which is the oldest one if it is
   *  still live — every pool is a ring now, so the cursor is the age
   *  order and the fade in Decals.tic knows where the old end is. The
   *  argument is kept for the callers that still say which they
   *  wanted; both get the same answer. */
  alloc(ring = true) {
    const i = this.next;
    this.next = (this.next + 1) % this.max;
    if (this.strength[i] <= 0) this.count++;
    else if (this.owner[i]) { this.owner[i] = null; this.owned--; }
    return i;
  }

  /** The oldest live slots, from the cursor forward: `n` of them, or
   *  as many as there are. Written into `out`, no allocation. */
  oldest(n, out) {
    out.length = 0;
    for (let k = 0; k < this.max && out.length < n; k++) {
      const i = (this.next + k) % this.max;
      if (this.strength[i] > 0) out.push(i);
    }
    return out;
  }

  /** The nearest live decal on the same surface within r, or -1. */
  nearest(x, y, z, n, r) {
    let best = -1, bd = r * r;
    for (let i = 0; i < this.max; i++) {
      if (this.strength[i] <= 0) continue;
      if (this.nx[i] * n.nx + this.ny[i] * n.ny + this.nz[i] * n.nz < 0.9) continue;
      const dx = this.x[i] - x, dy = this.y[i] - y, dz = this.z[i] - z;
      const d = dx * dx + dy * dy + dz * dz;
      if (d < bd) { bd = d; best = i; }
    }
    return best;
  }

  place(i, x, y, z, n, size, rot, strength, light, sky, frame) {
    if (this.owner[i]) { this.owner[i] = null; this.owned--; }
    this.x[i] = x; this.y[i] = y; this.z[i] = z;
    this.nx[i] = n.nx; this.ny[i] = n.ny; this.nz[i] = n.nz;
    this.size[i] = size; this.rot[i] = rot;
    this.strength[i] = strength; this.peak[i] = strength;
    this.light[i] = light; this.sky[i] = sky; this.frame[i] = frame;
    this.dirtyPos = true; this.dirtyStrength = true;
  }
}

/* ---- the pictures: drawn here, like everything else ---------------- */
function holeStrip() {
  /* two frames: the hole, and the scorch */
  const S = 32;
  const pix = new Pix(S * 2, S, 1, false);
  const cx = S / 2, cy = S / 2;
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const dx = x - cx + 0.5, dy = y - cy + 0.5;
    const d = Math.hypot(dx, dy) / (S / 2);
    const ang = Math.atan2(dy, dx);
    /* THE HOLE: a dark core inside a ragged PALE lip — the chipped
       plaster round a bullet hole, and the reason one reads at all.
       The shop is dark at night and a dark spot on a dark wall is
       nothing; the lip is what you see, and the core is what you see
       it round. */
    const rag = 0.80 + 0.16 * Math.sin(ang * 5 + 1.3) * Math.cos(ang * 3 - 0.4);
    if (d < rag) {
      const core = d < rag * 0.5;
      const f = (d - rag * 0.5) / (rag * 0.5);          // 0 at the core's edge, 1 at the rim
      const grain = ((x * 7 + y * 13) % 5) * 9;
      const a = core ? 240 : Math.round(215 * (1 - f * f));
      const v = core ? 8 : 120 + grain + Math.round(60 * (1 - f));
      pix.set(x, y, v, v - 4, v - 8, a);
    }
    /* the scorch: soft, dark, thinning to the edge, mottled */
    const rag2 = 0.86 + 0.12 * Math.sin(ang * 3 + 0.7) * Math.cos(ang * 7 + 2.1);
    if (d < rag2) {
      const f = 1 - d / rag2;
      const m = 0.75 + 0.25 * Math.sin(x * 1.7 + y * 2.3) * Math.cos(x * 0.9 - y * 1.1);
      const a = Math.round(210 * f * f * m);
      pix.set(S + x, y, 14, 12, 11, a);
    }
  }
  return pix;
}

function glowStrip() {
  /* one frame: a soft radial patch with a mottled edge, used by both
     the heat and the frost, coloured by the shader */
  const S = 32;
  const pix = new Pix(S, S, 1, false);
  const cx = S / 2, cy = S / 2;
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const dx = x - cx + 0.5, dy = y - cy + 0.5;
    const d = Math.hypot(dx, dy) / (S / 2);
    const ang = Math.atan2(dy, dx);
    const rag = 0.88 + 0.12 * Math.sin(ang * 4 + 0.3) * Math.cos(ang * 6 - 1.9);
    if (d >= rag) continue;
    const f = 1 - d / rag;
    const m = 0.8 + 0.2 * Math.sin(x * 2.1 + y * 1.3) * Math.cos(x * 1.1 - y * 2.7);
    pix.set(x, y, 255, 255, 255, Math.round(255 * Math.min(1, f * f * 1.6) * m));
  }
  return pix;
}

function makeTex(pix) {
  const t = new THREE.CanvasTexture(pix.toCanvas());
  t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false; t.colorSpace = THREE.SRGBColorSpace; t.needsUpdate = true;
  return t;
}

const VERT = /* glsl */`
attribute float aStrength;
attribute float aLight;
attribute float aSky;
varying vec2  vUv;
varying float vStrength;
varying float vLight;
varying float vSky;
varying float vDepth;
varying vec3  vWorld;
void main() {
  vUv = uv;
  vStrength = aStrength;
  vLight = aLight;
  vSky = aSky;
  vWorld = position;
  vec4 mv = viewMatrix * vec4(position, 1.0);
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
`;

/* KIND is 0 for a hole or a scorch, 1 for heat, 2 for frost. A hole is
   a dark thing that takes the wall's own light and fog, so a hole in a
   dark corner is not a black square glowing in it; heat is its own
   light and ignores both; frost is a pale thing on the surface, lit
   like the surface. */
const FRAG = /* glsl */`
uniform sampler2D map;
uniform float kind;
${WORLD_UNIFORMS_GLSL}
varying vec2  vUv;
varying float vStrength;
varying float vLight;
varying float vSky;
varying float vDepth;
varying vec3  vWorld;
${WORLD_SHADE_GLSL}
void main() {
  vec4 t = texture2D(map, vUv);
  if (t.a < 0.02) discard;
  vec3 c; float a;
  if (kind < 0.5) {
    float l = worldBand(vLight, vDepth, vSky, 0.0);
    c = worldShade(t.rgb, l, vDepth, vWorld, 0.0);
    a = t.a * vStrength;
  } else if (kind < 1.5) {
    /* heat: the same ramp the minigun's barrels use, dull red to
       orange to yellow-white, banded, and additive */
    float h = vStrength;
    vec3 hot = h < 0.5 ? mix(vec3(0.55, 0.03, 0.0), vec3(1.0, 0.36, 0.05), h * 2.0)
                       : mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.62), (h - 0.5) * 2.0);
    float g = floor(t.a * h * 8.0 + 0.5) / 8.0;
    c = hot; a = g * 0.95;
  } else {
    float l = worldBand(vLight, vDepth, vSky, 0.0);
    c = worldShade(vec3(0.80, 0.90, 1.0), l + 0.15, vDepth, vWorld, 0.0);
    a = t.a * vStrength * 0.85;
  }
  if (a < 0.01) discard;
  gl_FragColor = vec4(c, a);
}
`;

export class Decals {
  constructor(game) {
    this.game = game;
    this.pools = { hole: new Pool('hole', POOLS.hole), heat: new Pool('heat', POOLS.heat), frost: new Pool('frost', POOLS.frost) };
    this.tics = 0;
    this.holes = 0; this.scorches = 0;      // counts, for the readout and the test
    this._n = { nx: 0, ny: 0, nz: 0 };
    this._basis = { ux: 0, uy: 0, uz: 0, vx: 0, vy: 0, vz: 0 };
  }

  /* ---- placing ------------------------------------------------------ */
  _surface(x, y) {
    const sec = this.game.level?.sectorAt?.(x, y);
    return { light: sec ? (sec.light ?? 0.75) : 0.75, sky: sec && sec.outdoor ? 1 : 0 };
  }

  /** A round has landed on a surface. */
  hole(x, y, z, n) {
    const P = this.pools.hole;
    const i = P.alloc(true);
    const s = HOLE_SIZE[0] + (pRandom() / 255) * (HOLE_SIZE[1] - HOLE_SIZE[0]);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, n, s, (pRandom() / 255) * Math.PI * 2, 0.92, light, sky, 0);
    this.holes++;
  }

  /** A round has landed on a vehicle. `hx, hy, hz` is where the ray
   *  crossed its blocker and `dx, dy, dz` the way the round was going;
   *  the hole goes on whichever face of the vehicle's box the round
   *  came in through, at that point pushed out onto the face, and it
   *  rides with the vehicle from then on. Pure but for the pool. */
  vehicleHole(v, hx, hy, hz, dx, dy, dz) {
    /* ONLY A THING THAT IS A BOX. A hole rides in a vehicle's own
       frame, off the bottom of its body — `bodyZ` — and on one face of
       the box its model space describes. The gunship (js/vtol.js) is
       shot through the same blockers and is not one of those: it is a
       tree of parts that turn against each other, with no single box
       and no bodyZ, so a round into it throws its puff and its sparks
       and leaves nothing hanging in the air where a face would be. */
    if (!v.whole || v.bodyZ === undefined || !v.def?.box) return;
    const L = v.def.length, hw = v.def.box.half * L, H = v.def.box.height * L;
    const c = Math.cos(v.yaw), s = Math.sin(v.yaw);
    /* into the vehicle's own frame */
    const rx = hx - v.x, ry = hy - v.y;
    let lx = rx * c + ry * s, ly = -rx * s + ry * c, lz = hz - v.bodyZ;
    const ddx = dx * c + dy * s, ddy = -dx * s + dy * c;
    const dl = Math.hypot(ddx, ddy, dz) || 1;
    const ux = ddx / dl, uy = ddy / dl, uz = dz / dl;
    /* which face the round came in through: the one whose outward
       normal is most against the way it was going, the flanks and the
       ends weighed by the box's own shape */
    const cand = [
      [-Math.sign(ux) || 1, 0, 0, Math.abs(ux) * (hw / (L / 2))],
      [0, -Math.sign(uy) || 1, 0, Math.abs(uy)],
      [0, 0, 1, Math.max(0, -uz) * 0.8],
    ];
    cand.sort((a, b) => b[3] - a[3]);
    const [nx, ny, nz] = cand[0];
    /* onto that face, and kept a little in from the edges of it along
       the other two axes so a hole never hangs off a corner */
    const inset = 1.5;
    if (nx) lx = nx * (L / 2);
    else lx = Math.max(-L / 2 + inset, Math.min(L / 2 - inset, lx));
    if (ny) ly = ny * hw;
    else ly = Math.max(-hw + inset, Math.min(hw - inset, ly));
    if (nz) lz = H;
    else lz = Math.max(inset, Math.min(H - inset, lz));
    const P = this.pools.hole;
    const i = P.alloc(true);
    const size = HOLE_SIZE[0] + (pRandom() / 255) * (HOLE_SIZE[1] - HOLE_SIZE[0]);
    P.place(i, hx, hy, hz, { nx, ny, nz }, size, (pRandom() / 255) * Math.PI * 2, 0.92, v.light ?? 0.75, v.sky ?? 1, 0);
    P.owner[i] = v; P.owned++;
    P.lx[i] = lx; P.ly[i] = ly; P.lz[i] = lz;
    P.lnx[i] = nx; P.lny[i] = ny; P.lnz[i] = nz;
    this.holes++;
  }

  /** A flame has landed: the spot heats. Nearby frost melts. */
  heat(x, y, z, n, amount = HEAT_PER_LANDING) {
    this._feed(this.pools.heat, x, y, z, n, amount, HEAT_SIZE);
    this._argue(this.pools.frost, x, y, z, n);
  }

  /** A puff of gas has landed: the spot rimes. Nearby heat cools. */
  frost(x, y, z, n, amount = FROST_PER_LANDING) {
    this._feed(this.pools.frost, x, y, z, n, amount, FROST_SIZE);
    this._argue(this.pools.heat, x, y, z, n);
  }

  _feed(P, x, y, z, n, amount, size) {
    let i = P.nearest(x, y, z, n, MERGE_RADIUS);
    if (i < 0) {
      /* the ring's next slot: a free one, or the oldest spot if the
         pool is full — which the fade in tic() has usually already
         emptied by the time the cursor reaches it */
      i = P.alloc(true);
      /* a live spot overwritten is a spot that has ended — a hot one
         leaves its scorch — and the slot is then live again as this */
      if (P.strength[i] > 0) { this._expire(P, i); P.count++; }
      P.strength[i] = 0;
      const { light, sky } = this._surface(x, y);
      P.place(i, x, y, z, n, size, (pRandom() / 255) * Math.PI * 2, 0, light, sky, 0);
    }
    P.strength[i] = Math.min(1, P.strength[i] + amount);
    P.peak[i] = Math.max(P.peak[i], P.strength[i]);
    P.dirtyStrength = true;
  }

  /** The other kind, within reach, loses some of itself. */
  _argue(P, x, y, z, n) {
    const r2 = ARGUE_RADIUS * ARGUE_RADIUS;
    for (let i = 0; i < P.max; i++) {
      if (P.strength[i] <= 0) continue;
      if (P.nx[i] * n.nx + P.ny[i] * n.ny + P.nz[i] * n.nz < 0.9) continue;
      const dx = P.x[i] - x, dy = P.y[i] - y, dz = P.z[i] - z;
      if (dx * dx + dy * dy + dz * dz > r2) continue;
      P.strength[i] = Math.max(0, P.strength[i] - ARGUE_AMOUNT);
      P.dirtyStrength = true;
      if (P.strength[i] <= 0) this._expire(P, i);
    }
  }

  /** A heat spot that has gone cold leaves its scorch behind, sized
   *  and darkened by how hot it got; nothing else leaves anything. */
  _expire(P, i) {
    P.count--;
    if (P.owner[i]) { P.owner[i] = null; P.owned--; }
    if (P.kind === 'heat' && P.peak[i] > 0.25) {
      const H = this.pools.hole;
      const j = H.alloc(true);
      H.place(j, P.x[i], P.y[i], P.z[i], { nx: P.nx[i], ny: P.ny[i], nz: P.nz[i] },
        SCORCH_SIZE * (0.7 + 0.5 * P.peak[i]), P.rot[i], Math.min(0.9, 0.35 + 0.6 * P.peak[i]), P.light[i], P.sky[i], 1);
      this.scorches++;
    }
    P.peak[i] = 0;
  }

  /* ---- time --------------------------------------------------------- */
  tic() {
    this.tics++;
    for (const [P, rate] of [[this.pools.heat, HEAT_COOL], [this.pools.frost, FROST_THAW]]) {
      if (!P.count) continue;
      for (let i = 0; i < P.max; i++) {
        if (P.strength[i] <= 0) continue;
        P.strength[i] -= rate;
        if (P.strength[i] <= 0) { P.strength[i] = 0; this._expire(P, i); }
      }
      P.dirtyStrength = true;
    }
    /* AND THE OLD END OF A FULL RING DISSOLVES, at the user's request.
       Not on a clock of its own: each of the FADE_AHEAD oldest is held
       DOWN TO ITS PLACE IN THE QUEUE — nothing for the one the cursor
       is about to take, nearly full for the one sixteen behind it — so
       a hole fades as the ring comes round to it, however fast the
       trigger is being held. Which is the whole reason it is written
       this way: a fixed rate is either too slow for a minigun (holes
       pop off the wall at four a tic) or too fast with the trigger up.
       FADE_RATE is only a speed LIMIT on the way down, so a hole never
       jumps to its place, it slides.

       A pool that has stopped filling settles into the gradient it is
       left holding: the oldest gone, and the dozen behind it
       progressively fainter, which reads as the earliest holes
       weathering. */
    for (const P of Object.values(this.pools)) {
      if (!P.count || P.count <= P.max - FADE_AHEAD) continue;
      /* RAW SLOTS from the cursor, not live ones: a dead slot still
         takes up its place in the queue. Walking the LIVE ones instead
         slides the whole band forward every time one of them expires,
         which cascades — the first tic kills the oldest, the second
         promotes its neighbour to the front and kills that, and a pool
         nobody is adding to empties itself a slot at a time. */
      for (let k = 0; k < FADE_AHEAD; k++) {
        const i = (P.next + k) % P.max;
        if (P.strength[i] <= 0) continue;
        const want = fadeTarget(k);
        if (P.strength[i] <= want) continue;
        P.strength[i] = Math.max(want, P.strength[i] - FADE_RATE);
        if (P.strength[i] <= 0) { P.strength[i] = 0; this._expire(P, i); }
      }
      P.dirtyStrength = true;
    }
  }

  /* ---- drawing ------------------------------------------------------ */
  attach(scene) {
    const holes = makeTex(holeStrip()), glow = makeTex(glowStrip());
    const mk = (P, tex, kindNo, blend, order, frames) => {
      const N = P.max;
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 12), 3));
      g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(N * 8), 2));
      g.setAttribute('aStrength', new THREE.BufferAttribute(new Float32Array(N * 4), 1));
      g.setAttribute('aLight', new THREE.BufferAttribute(new Float32Array(N * 4), 1));
      g.setAttribute('aSky', new THREE.BufferAttribute(new Float32Array(N * 4), 1));
      const idx = new Uint32Array(N * 6);
      for (let i = 0; i < N; i++) { const v = i * 4, k = i * 6; idx[k] = v; idx[k + 1] = v + 1; idx[k + 2] = v + 2; idx[k + 3] = v; idx[k + 4] = v + 2; idx[k + 5] = v + 3; }
      g.setIndex(new THREE.BufferAttribute(idx, 1));
      g.setDrawRange(0, 0);
      const mat = new THREE.ShaderMaterial({
        uniforms: { map: { value: tex }, kind: { value: kindNo }, ...worldUniforms() },
        vertexShader: VERT, fragmentShader: FRAG,
        transparent: true, depthWrite: false, depthTest: true,
        blending: blend === 'add' ? THREE.AdditiveBlending : THREE.NormalBlending,
        polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
        side: THREE.DoubleSide, fog: false, toneMapped: false,
      });
      const mesh = new THREE.Mesh(g, mat);
      mesh.frustumCulled = false;
      mesh.renderOrder = order;
      mesh.name = 'decals-' + P.kind;
      scene.add(mesh);
      P.mesh = mesh; P.frames = frames;
      P.dirtyPos = P.dirtyStrength = true;
    };
    mk(this.pools.hole, holes, 0, 'normal', 4, 2);
    mk(this.pools.frost, glow, 2, 'normal', 5, 1);
    mk(this.pools.heat, glow, 1, 'add', 6, 1);
  }

  /** The holes that ride on vehicles: put where their vehicle is now,
   *  and dropped the moment it stops being whole — a wreck on its roof
   *  is not the box the holes were laid on. */
  _carry() {
    const P = this.pools.hole;
    if (!P.owned) return;
    for (let i = 0; i < P.max; i++) {
      const v = P.owner[i];
      if (!v) continue;
      if (!v.whole) { P.owner[i] = null; P.owned--; P.strength[i] = 0; P.count--; P.dirtyStrength = true; continue; }
      const c = Math.cos(v.yaw), s = Math.sin(v.yaw);
      P.x[i] = v.x + P.lx[i] * c - P.ly[i] * s;
      P.y[i] = v.y + P.lx[i] * s + P.ly[i] * c;
      P.z[i] = v.bodyZ + P.lz[i];
      P.nx[i] = P.lnx[i] * c - P.lny[i] * s;
      P.ny[i] = P.lnx[i] * s + P.lny[i] * c;
      P.nz[i] = P.lnz[i];
    }
    P.dirtyPos = true;
  }

  /** `ex, ey` is the eye and `vx, vy` the unit direction it looks
   *  along, in game coordinates; with none given nothing is culled.
   *  The buffers are rebuilt every frame, compacted to the decals that
   *  are live and in view, with no allocation in the loop: a thousand
   *  quads' worth of arithmetic, which is nothing next to the draw. */
  render(ex = 0, ey = 0, vx = 0, vy = 0) {
    this._carry();
    const cull = vx !== 0 || vy !== 0;
    const R2 = DRAW_RANGE * DRAW_RANGE;
    const B = this._basis;
    for (const P of Object.values(this.pools)) {
      if (!P.mesh) continue;
      const g = P.mesh.geometry;
      const pos = g.attributes.position.array, uv = g.attributes.uv.array;
      const lt = g.attributes.aLight.array, sk = g.attributes.aSky.array, st = g.attributes.aStrength.array;
      let n = 0;
      for (let i = 0; i < P.max; i++) {
        const strength = P.strength[i];
        if (strength <= 0) continue;
        const px = P.x[i], py = P.y[i], h = P.size[i] / 2;
        if (cull) {
          const dx = px - ex, dy = py - ey;
          if (dx * dx + dy * dy > R2) continue;
          if (dx * vx + dy * vy < -h) continue;
        }
        const nx = P.nx[i], ny = P.ny[i], nz = P.nz[i];
        surfaceBasisInto(nx, ny, nz, B);
        const c = Math.cos(P.rot[i]), sn = Math.sin(P.rot[i]);
        /* the quad's two axes, turned by rot about the normal */
        const ax = (B.ux * c + B.vx * sn) * h, ay = (B.uy * c + B.vy * sn) * h, az = (B.uz * c + B.vz * sn) * h;
        const bx = (B.vx * c - B.ux * sn) * h, by = (B.vy * c - B.uy * sn) * h, bz = (B.vz * c - B.uz * sn) * h;
        const cx = px + nx * LIFT, cy = py + ny * LIFT, cz = P.z[i] + nz * LIFT;
        const f0 = P.frame[i] / P.frames, f1 = (P.frame[i] + 1) / P.frames;
        const v0 = n * 4;
        for (let k = 0; k < 4; k++) {
          const u = CORNER_U[k], v = CORNER_V[k];
          const o = (v0 + k) * 3;
          /* game (x, y, z) to three (x, z, -y) */
          pos[o] = cx + ax * u + bx * v; pos[o + 1] = cz + az * u + bz * v; pos[o + 2] = -(cy + ay * u + by * v);
          uv[(v0 + k) * 2] = u < 0 ? f0 : f1; uv[(v0 + k) * 2 + 1] = v < 0 ? 0 : 1;
          lt[v0 + k] = P.light[i]; sk[v0 + k] = P.sky[i]; st[v0 + k] = strength;
        }
        n++;
      }
      P.drawn = n;
      g.setDrawRange(0, n * 6);
      g.attributes.position.needsUpdate = true; g.attributes.uv.needsUpdate = true;
      g.attributes.aLight.needsUpdate = true; g.attributes.aSky.needsUpdate = true;
      g.attributes.aStrength.needsUpdate = true;
      P.dirtyPos = false; P.dirtyStrength = false;
    }
  }

  get liveCount() { return this.pools.hole.count + this.pools.heat.count + this.pools.frost.count; }
}
