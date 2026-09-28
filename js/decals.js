/* =====================================================================
   MEWD — decals: what a weapon leaves on a surface
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
   is free again. EVERY POOL IS A RING, at the user's request: a
   hundred of each kind to begin with — FOUR hundred bullet holes now,
   the user having asked for four times as many — and when a pool is
   full the OLDEST IN IT FADE OUT, IN ORDER, rather than being cut — the
   ten at the old end of the ring lose an eighth a tic until they are
   gone, and the cursor arrives on slots that are already empty. A
   thousand rounds into one wall are the last four hundred of them, the
   earliest dissolving as the latest land, which reads as a wall being
   shot rather than as a wall with a budget.

   AND TWO MORE KINDS SINCE, which are the same system again:

     SEARS   what the positron lance leaves where its column lands,
             instead of the hole it used to cut. Enormous, charred,
             glowing, splattered: see SEAR in js/beam.js for the sizes
             and Decals.sear for the picture.

     GORE    not a pool of its own but the blood one, used harder: a
             round through somebody now throws blood up EVERY wall in
             reach behind them rather than one, and a warhead that takes
             somebody apart paints the room round them — see sprayWalls
             and Giblets.eviscerate in js/people.js.

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
import { WORLD_UNIFORMS_GLSL, WORLD_SHADE_GLSL, worldUniforms } from './material.js';
import { pRandom, TICRATE } from './util.js';

/* the pools, and the numbers that make each kind what it is */
export const POOLS = { hole: 400, heat: 100, frost: 100, blood: 480, burn: 24, sear: 96 };
/* HOW MANY HOLES, AND HOW FAR. The hole pool is the MAX COUNT, and a
   hole has no clock of its own — it lasts exactly as long as it takes
   the ring to come round to it — so the count IS the lifetime. It was
   five hundred and twelve, then a hundred at the user's request (the
   accumulation was a cost), and it is FOUR HUNDRED now, at the user's
   request again: "increase bullet hole lifetime count by 4x". Four
   times the holes on the walls at once, and so four times as long
   before any one of them goes, which a minigun still reaches in a few
   seconds of holding the trigger — the scorches share it.

   AND THE BLOOD FOUR TIMES WITH IT, near enough: a hundred and twenty
   was sized for one spatter on the floor and at most one on the wall
   per round, and a round now throws blood up every wall in reach and a
   warhead through a crowd paints the room (see sprayWalls). At the old
   size the second kill in a room wiped the first one's walls clean.

   THE SEARS ARE FEW AND ENORMOUS: a crater and up to ten pieces of slag
   a shot, so ninety-six is the last dozen or so shots of the lance, and
   at three hundred units across that is already a street's worth. WHEN IT IS FULL THE OLDEST FADE, IN ORDER, and
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
export const HOLE_SIZE = [8, 13];             // world units across, min..max: the soot round it included
export const HOT_SCALE = 1.3;                 // a minigun round's hole, and its burnt ring, bigger than a rifle's
export const BLOOD_SIZE = [20, 38];           // a spatter, across
export const POOL_SIZE = [44, 70];            // the pool under somebody, once it has spread
export const BURN_SIZE = 84;                  // a warhead's burning hole
export const BLOOD_REACH = 260;               // how far behind somebody a round throws them onto a wall
/* AND HOW MUCH OF IT GOES UP THE WALL. A round through somebody used to
   throw ONE spatter at the one point straight behind them, a hundred
   and thirty units out — which in a shop aisle or a street is usually
   nothing, and when it was something it was a single blot at chest
   height. At the user's request ("i want blood spatter on walls too")
   it is a SPRAY now: WALL_SPRAY rays in a cone round the line the round
   was going, each one that reaches a wall leaving its own spatter, the
   near ones big and the far ones smaller, thrown the way the ray went
   and a little down, because blood does not go up. */
export const WALL_SPRAY = 4;                  // rays in the cone behind somebody who is hit
export const WALL_CONE = 0.42;                // and how wide it is either side, in radians
export const WALL_SPATTER = [30, 64];         // a spatter up a wall, across: near..far is big..small
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

/** Who bleeds: people, and you. Not a van, not a gunship, not somebody
 *  frozen solid — ice breaks, it does not bleed. Pure. */
export const bleeds = (a, player = null) => !!a && !a.vehicle && !a.frozen &&
  (a === player || !!a.isPlayer || !!a.monster || !!a.info?.monster);

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

/* a private stream of numbers for how decals look, apart from pRandom */
let cosmeticState = 0x9e3779b9;
const cosmetic = () => ((cosmeticState = (Math.imul(cosmeticState, 1664525) + 1013904223) >>> 0) / 4294967296);

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
    this.frame = new Uint8Array(max);        // which variety of its kind (see KIND_OF)
    this.born = new Float32Array(max);       // the tic it was put there, for what changes with age
    this.seed = new Float32Array(max);       // its own noise, so no two are alike
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
    /* its own noise, from a private counter and NOT the game's random
       numbers: what a decal looks like must never move where a trooper
       decides to run */
    this.seed[i] = cosmetic();
    this.dirtyPos = true; this.dirtyStrength = true;
  }
}

/* ---- THE PICTURES: CUBES, AND A SHADER THAT DRAWS ON WHAT IS IN THEM --

   EVERY DECAL IS A BOX NOW, at the user's request, and nothing is a
   picture any more. The old decals were flat quads with a 32-pixel
   drawing on them, laid a hair off the wall, and they had the three
   faults a flat quad always has: they hung off the edge of a wall into
   the air, they sliced through a corner instead of wrapping round it,
   and at 32 pixels a hole the size of a door was a smear.

   A BOX-PROJECTED DECAL is a cube stood across the surface — half in
   the wall, half out — drawn from the inside (its back faces, with no
   depth test, so it is drawn when the eye is inside it too). For every
   pixel it covers, the fragment shader reads the WORLD'S OWN DEPTH at
   that pixel, rebuilds the point of the world that is there, and asks
   where that point sits inside the box. Outside the box: nothing. Inside:
   the decal, drawn at that point of its own square. So a decal lies on
   whatever the world actually is — a wall, a floor, a step, the corner
   where two meet — and it stops exactly where the wall stops, because
   past the edge the point the depth rebuilds is somewhere else.

   AND THE DETAIL IS ARITHMETIC. Nothing is sampled but the depth: a
   bullet hole's ragged lip and its cracks, a burning hole's coals, the
   drops thrown off a spatter of blood, the crystals in the rime, all of
   it is noise and distance worked out per pixel from the decal's own
   seed, so it is as sharp at a hand's width as it is across the street
   and no two are the same.

   WHAT IT NEEDS is the world's depth as a texture it can read while it
   draws into the world's colour, which WebGL will not allow off the
   same framebuffer. So the depth is copied first — one full-screen pass
   at the buffer's own low resolution, packed into eight-bit RGBA — and
   the boxes read the copy. See Decals.draw, which js/lofi.js calls
   between the world and everything drawn over it.

   ONE DRAW CALL FOR ALL OF THEM. One instanced box, one instance per
   live decal of every kind, and PREMULTIPLIED blending so a dark hole
   (painted over the wall) and a glowing coal (added to it) are the same
   blend: the colour carries its own alpha, and a glow is colour with no
   alpha at all. */

/* the kinds, as the shader numbers them */
export const KIND = Object.freeze({ HOLE: 0, SCORCH: 1, HOT: 2, HEAT: 3, FROST: 4, SPATTER: 5, POOL: 6, BURN: 7,
                                   SEAR: 8, SLAG: 9 });

/* how deep each kind's box reaches either side of the surface, over its
   width: a bullet hole is a skin, blood is thrown far enough to wrap
   over a kerb, a burnt hole is a crater, and a sear is thrown across
   whatever is round it — but not so deep that one on a wall paints the
   floor a man's height below it */
const DEPTH = [0.22, 0.30, 0.22, 0.30, 0.30, 0.45, 0.18, 0.40, 0.20, 0.32];

const DECAL_VERT = /* glsl */`
attribute vec3 iC;
attribute vec3 iU;
attribute vec3 iV;
attribute vec3 iN;
attribute vec4 iP;      // kind, strength, seed, age in seconds
attribute vec2 iL;      // the surface's light, and how much is sky
varying vec3 vC;
varying vec3 vU;
varying vec3 vV;
varying vec3 vN;
varying vec4 vP;
varying vec2 vL;
void main() {
  vC = iC; vU = iU; vV = iV; vN = iN; vP = iP; vL = iL;
  vec3 w = iC + iU * (position.x * 2.0) + iV * (position.y * 2.0) + iN * (position.z * 2.0);
  gl_Position = projectionMatrix * viewMatrix * vec4(w, 1.0);
}
`;

const DECAL_FRAG = /* glsl */`
#include <packing>
uniform sampler2D tDepth;
uniform vec2 uRes;
uniform mat4 uInvProj;
uniform mat4 uCamWorld;
uniform float uTime;
${WORLD_UNIFORMS_GLSL}
varying vec3 vC;
varying vec3 vU;
varying vec3 vV;
varying vec3 vN;
varying vec4 vP;
varying vec2 vL;
${WORLD_SHADE_GLSL}

float dh1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 dh2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float dnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(dh1(i), dh1(i + vec2(1.0, 0.0)), u.x), mix(dh1(i + vec2(0.0, 1.0)), dh1(i + vec2(1.0, 1.0)), u.x), u.y);
}
float dfbm(vec2 p) {
  float a = 0.5, s = 0.0;
  for (int i = 0; i < 4; i++) { s += a * dnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
  return s;
}
/* a ragged edge: the radius a round thing reaches at this angle */
float rag(float ang, float seed, float amt) {
  vec2 q = vec2(cos(ang), sin(ang)) * 2.2 + seed * 17.0;
  return 1.0 + amt * (dfbm(q) - 0.5) * 2.0;
}
/* cracks: thin dark lines running out from the centre */
float cracks(vec2 p, float seed, float n) {
  float ang = atan(p.y, p.x);
  float r = length(p);
  float k = ang * n / 6.2831853 + seed * 5.0;
  float cell = floor(k);
  float off = dh1(vec2(cell, seed)) - 0.5;
  float wob = (dnoise(vec2(r * 9.0, cell * 3.1 + seed)) - 0.5) * 0.9;
  float d = abs(fract(k) - 0.5 - off * 0.6 + wob * 0.25);
  float len = 0.55 + 0.45 * dh1(vec2(seed, cell + 7.0));
  float w = 0.09 * (1.0 - r / max(len, 0.01));
  return (r < len) ? 1.0 - smoothstep(0.0, max(w, 0.0), d) : 0.0;
}
/* the fire's own ramp, dull red to yellow-white */
vec3 hotRamp(float h) {
  return h < 0.5 ? mix(vec3(0.55, 0.03, 0.0), vec3(1.0, 0.36, 0.05), h * 2.0)
                 : mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.62), (h - 0.5) * 2.0);
}

void main() {
  vec2 suv = gl_FragCoord.xy / uRes;
  float d = unpackRGBAToDepth(texture2D(tDepth, suv));
  if (d >= 0.99999) discard;                          // nothing there: sky
  vec4 vp = uInvProj * vec4(suv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
  vp /= vp.w;
  vec3 wp = (uCamWorld * vp).xyz;
  vec3 rel = wp - vC;
  vec3 l = vec3(dot(rel, vU) / dot(vU, vU), dot(rel, vV) / dot(vV, vV), dot(rel, vN) / dot(vN, vN));
  if (abs(l.x) > 1.0 || abs(l.y) > 1.0 || abs(l.z) > 1.0) discard;
  /* THE SURFACE'S OWN NORMAL, from how the rebuilt point moves across
     the screen. A decal stood across a corner lies on both faces of it,
     but thins out on a face that turns away from the one it was thrown
     at, so a hole does not smear itself down the side of a pillar. */
  vec3 sn = normalize(cross(dFdx(wp), dFdy(wp)));
  float facing = abs(dot(sn, normalize(vN)));
  float kind = vP.x, strength = vP.y, seed = vP.z, age = vP.w;
  float depthFade = 1.0 - smoothstep(0.55, 1.0, abs(l.z));
  float fade = smoothstep(0.18, 0.55, facing) * depthFade * strength;
  if (fade <= 0.003) discard;
  vec2 p = l.xy;
  float r = length(p);
  float ang = atan(p.y, p.x);
  float viewDepth = -vp.z;
  float lit = worldBand(vL.x, viewDepth, vL.y, 0.0);

  vec3 col = vec3(0.0);   // the paint, not yet multiplied by its alpha
  float a = 0.0;
  vec3 glow = vec3(0.0);  // light it gives off, added

  if (kind < 0.5 || (kind > 1.5 && kind < 2.5)) {
    /* A BULLET HOLE. A black core with depth in it — the bore of the
       hole lit on the side the light comes from and falling away inside
       — a ragged lip of chipped paint and plaster round it, a few hair
       cracks running off the lip, and a faint soot of the round's own
       dirt round all of it. A MINIGUN ROUND (kind 2) is hot: the lip
       glows orange where it went in and cools over a second and a half,
       and leaves a wider ring of burnt powder than a rifle's. */
    float hot = kind > 1.5 ? 1.0 : 0.0;
    float R = rag(ang, seed, 0.28);
    float rr = r / R;
    float core = 1.0 - smoothstep(0.26, 0.33, rr);
    float lip = smoothstep(0.26, 0.36, rr) * (1.0 - smoothstep(0.40, 0.55, rr * (0.9 + 0.2 * dnoise(p * 9.0 + seed * 3.0))));
    float soot = (1.0 - smoothstep(0.35, 1.0, rr)) * (0.55 + 0.45 * dfbm(p * 6.0 + seed * 9.0)) * (0.45 + 0.3 * hot);
    float cr = cracks(p, seed, 7.0) * step(0.24, rr) * (1.0 - hot * 0.3);
    /* the bore: a gradient across the core, as if lit from above */
    float bore = 0.02 + 0.07 * smoothstep(-0.3, 0.3, p.y + p.x * 0.3) * (1.0 - rr / 0.33);
    float chip = 0.30 + 0.28 * dnoise(p * 14.0 + seed * 21.0);
    col = mix(vec3(0.05, 0.045, 0.04), vec3(chip, chip * 0.96, chip * 0.9), lip);
    col = mix(col, vec3(bore), core);
    a = max(core * 0.98, max(lip * 0.6, max(soot * 0.85, cr * 0.8)));
    col = mix(col, vec3(0.05), (1.0 - lip) * (1.0 - core));
    col = worldShade(col, lit, viewDepth, wp, 0.0);
    if (hot > 0.5) {
      float h = clamp(1.0 - age / 1.5, 0.0, 1.0);
      h *= h;
      float ring = smoothstep(0.22, 0.32, rr) * (1.0 - smoothstep(0.34, 0.5, rr));
      glow = hotRamp(0.35 + 0.65 * h) * ring * h * 1.6;
    }
  } else if (kind < 1.5) {
    /* A SCORCH: what a hot spot leaves. Soft and dark, mottled, and
       thinning out to a ragged edge; the darkest part is the middle. */
    float R = rag(ang, seed, 0.22);
    float rr = r / R;
    float m = dfbm(p * 4.0 + seed * 13.0);
    a = (1.0 - smoothstep(0.25, 1.0, rr)) * (0.55 + 0.45 * m) * 0.95;
    col = worldShade(mix(vec3(0.035, 0.03, 0.028), vec3(0.12, 0.09, 0.07), m * (rr)), lit, viewDepth, wp, 0.0);
  } else if (kind < 3.5) {
    /* HEAT: the surface itself glowing where the stream sits, banded
       like the fire's own ramp and swimming, additive, its own light */
    float R = rag(ang + uTime * 0.3, seed, 0.2);
    float rr = r / R;
    float m = dfbm(p * 5.0 + vec2(uTime * 0.7, -uTime * 0.4) + seed * 5.0);
    float h = strength * (1.0 - smoothstep(0.1, 1.0, rr)) * (0.7 + 0.5 * m);
    h = floor(h * 8.0 + 0.5) / 8.0;
    glow = hotRamp(clamp(h, 0.0, 1.0)) * h * 1.2;
    fade = smoothstep(0.18, 0.55, facing) * depthFade;
  } else if (kind < 4.5) {
    /* FROST: rime, whiter the longer the jet stays, with the feathered
       crystals of it drawn in: long thin needles at a few angles, and a
       fine glitter over the top */
    float R = rag(ang, seed, 0.25);
    float rr = r / R;
    float body = (1.0 - smoothstep(0.2, 1.0, rr)) * (0.6 + 0.4 * dfbm(p * 5.0 + seed * 3.0));
    vec2 q = p * 7.0;
    float needles = 0.0;
    for (int i = 0; i < 3; i++) {
      float th = float(i) * 1.047 + seed * 2.0;
      vec2 dir = vec2(cos(th), sin(th));
      float along = dot(q, dir), across = dot(q, vec2(-dir.y, dir.x));
      needles = max(needles, (1.0 - smoothstep(0.0, 0.12, abs(fract(across + dnoise(vec2(along * 0.5, float(i))) * 0.6) - 0.5))) * step(0.5, dnoise(vec2(along * 0.8, across * 0.3 + float(i) * 7.0))));
    }
    float glit = step(0.93, dh1(floor(p * 24.0) + seed));
    a = clamp(body * (0.75 + 0.35 * needles), 0.0, 1.0) * 0.9;
    col = worldShade(mix(vec3(0.72, 0.84, 0.95), vec3(0.95, 0.98, 1.0), needles * 0.8 + glit), lit + 0.15, viewDepth, wp, 0.0);
    glow = vec3(0.35, 0.45, 0.55) * glit * body * 0.4;
  } else if (kind < 5.5) {
    /* A SPATTER OF BLOOD, thrown along +x — which the decal's turn has
       pointed the way the round was going. A body of it where it hit,
       a scatter of drops flung out ahead, the far ones smaller and
       drawn out into streaks, and a wet dark red that dries browner over
       half a minute. */
    float R = rag(ang, seed, 0.35);
    float blob = 1.0 - smoothstep(0.30, 0.36, r / (R * (0.8 + 0.2 * dh1(vec2(seed, 3.0)))));
    float drops = 0.0;
    for (int i = 0; i < 14; i++) {
      vec2 h = dh2(vec2(float(i) * 1.37, seed * 9.1));
      float dist = 0.25 + 0.7 * h.x;
      float spread = (h.y - 0.5) * 1.3 * (1.0 - dist * 0.45);
      vec2 c = vec2(dist * 0.95 - 0.1, spread * dist);
      float sz = mix(0.11, 0.025, dist) * (0.6 + 0.8 * dh1(h * 5.0));
      vec2 dq = p - c;
      dq.x /= 1.0 + dist * 2.2;                     // the far ones drawn out along the throw
      drops = max(drops, 1.0 - smoothstep(sz * 0.75, sz, length(dq)));
    }
    /* and a few very fine flecks everywhere in front */
    float fleck = step(0.965, dh1(floor(p * 30.0) + seed * 3.0)) * step(-0.1, p.x) * (1.0 - smoothstep(0.4, 1.0, r));
    float m = max(blob, max(drops, fleck));
    float dry = smoothstep(0.0, 30.0, age);
    vec3 wet = mix(vec3(0.26, 0.01, 0.012), vec3(0.13, 0.005, 0.008), dfbm(p * 8.0 + seed));
    col = mix(wet, vec3(0.10, 0.03, 0.022), dry);
    /* the wet sheen, which is what makes it read as liquid */
    float sheen = (1.0 - dry) * blob * smoothstep(0.55, 0.8, dfbm(p * 10.0 + seed * 7.0)) * 0.35;
    col = worldShade(col + sheen, lit, viewDepth, wp, 0.0);
    a = m * 0.93;
  } else if (kind < 6.5) {
    /* A POOL, under somebody: one smooth ragged puddle that spreads over
       the first few seconds, darker in the middle where it is deep, with
       a few drips round the edge, drying at its rim first */
    float grow = mix(0.35, 1.0, smoothstep(0.0, 6.0, age));
    float R = rag(ang, seed, 0.3) * grow * 0.85;
    float rr = r / R;
    float body = 1.0 - smoothstep(0.92, 1.0, rr);
    float drips = 0.0;
    for (int i = 0; i < 6; i++) {
      vec2 h = dh2(vec2(float(i) * 3.1, seed * 4.7));
      float th = h.x * 6.2831853, dd = R * (1.05 + 0.25 * h.y);
      drips = max(drips, 1.0 - smoothstep(0.03, 0.05 + 0.03 * h.y, length(p - vec2(cos(th), sin(th)) * dd)));
    }
    float dry = smoothstep(10.0, 60.0, age) * smoothstep(0.4, 1.0, rr);
    vec3 c = mix(vec3(0.10, 0.004, 0.006), vec3(0.24, 0.012, 0.014), smoothstep(0.3, 1.0, rr));
    c = mix(c, vec3(0.09, 0.028, 0.022), dry);
    float sheen = (1.0 - dry) * smoothstep(0.6, 0.85, dfbm(p * 5.0 + seed * 2.0)) * (1.0 - rr) * 0.3;
    col = worldShade(c + sheen, lit, viewDepth, wp, 0.0);
    a = max(body, drips) * 0.95;
  } else if (kind < 7.5) {
    /* A BURNING HOLE, the big one: what a warhead leaves in a wall or a
       floor. A crater of black, the edge of it torn and still molten —
       an orange line along the rim — a ring of cracked char round it
       with the coals burning in the cracks, flickering, and a soot of
       smoke-black thrown wide round all of that. It burns: over twelve
       seconds the coals go from yellow-white through orange to a dull
       red and out, and what is left is the crater and the char. */
    float heat = exp(-age / 6.0) * (0.85 + 0.15 * sin(uTime * 17.0 + seed * 40.0));
    float R = rag(ang, seed, 0.30);
    float rr = r / R;
    float hole = 1.0 - smoothstep(0.30, 0.34, rr);
    float rim = smoothstep(0.27, 0.33, rr) * (1.0 - smoothstep(0.34, 0.42, rr));
    float charZ = (1.0 - smoothstep(0.34, 0.72, rr * (0.85 + 0.3 * dfbm(p * 3.0 + seed))));
    float soot = (1.0 - smoothstep(0.5, 1.0, rr)) * (0.5 + 0.5 * dfbm(p * 5.0 + seed * 4.0));
    /* the coals: the dark places in a cracked noise, lit */
    float n = dfbm(p * 9.0 + seed * 7.0);
    float cell = abs(n - 0.5);
    float coals = (1.0 - smoothstep(0.0, 0.06, cell)) * charZ * step(0.32, rr);
    float flick = 0.7 + 0.3 * dnoise(p * 12.0 + vec2(uTime * 3.0, -uTime * 2.3));
    float cr = cracks(p, seed, 11.0) * step(0.32, rr) * (1.0 - smoothstep(0.6, 0.95, rr));
    /* the depth of the crater: black, a little lighter toward the rim
       on the lit side, so it reads as a hole and not a black disc */
    float inner = 0.015 + 0.05 * smoothstep(0.0, 0.3, rr) * smoothstep(-0.3, 0.3, p.y);
    col = mix(vec3(0.03, 0.025, 0.022), vec3(0.08, 0.065, 0.055), dfbm(p * 14.0 + seed));
    col = mix(col, vec3(inner), hole);
    a = max(hole, max(charZ * 0.96, soot * 0.9));
    col = worldShade(col, lit, viewDepth, wp, 0.0);
    glow = hotRamp(clamp(heat * 1.1, 0.0, 1.0)) * rim * heat * 2.2
         + hotRamp(clamp(heat * 0.9, 0.0, 1.0)) * max(coals, cr) * heat * flick * 1.5
         + vec3(1.0, 0.35, 0.05) * hole * heat * 0.12 * (1.0 - rr / 0.34);
  } else if (kind < 8.5) {
    /* A SEAR: where the positron column landed, and the biggest mark in
       the game by a factor of three. It is not a hole — nothing is cut,
       at the user's request — it is what a surface looks like after a
       column of plasma has sat on it for a second:

         a CRATER of vitrified black glass, with a sheen of the lance's
           own green in it, white-hot for the first second
         a RIM round that, still molten, orange for ten seconds
         CHAR thrown out of it in a STARBURST of streaks of uneven
           length, longer on the side the beam was going (+x, which the
           decal's turn points along the throw)
         cracks and veins through the char with the coals still in
           them, a dull red for half a minute
         DROPLETS of slag flung past the rim, drawn out along the way
           they flew, glowing while they are fresh
         and a soot of smoke-black under all of it, out to the edge

       Every one of those is noise off the decal's own seed, so the
       number of streaks, how long each is, how far it is stretched and
       where every drop landed is different every shot. */
    float core = exp(-age / 0.9);
    float heat = exp(-age / 5.0);
    float ember = exp(-age / 14.0);
    float stretch = 1.0 + 0.35 * dh1(vec2(seed, 1.7));
    vec2 q = vec2((p.x + 0.06) / stretch, p.y);
    float rq = length(q);
    float aq = atan(q.y, q.x);
    float R = rag(aq, seed, 0.24);
    float rr = rq / R;
    /* the starburst */
    float nStreak = 9.0 + floor(dh1(vec2(seed, 5.3)) * 10.0);
    float ks = aq * nStreak / 6.2831853 + seed * 3.0;
    float cellS = floor(ks);
    float lenS = (0.46 + 0.46 * dh1(vec2(cellS, seed * 7.0))) * (1.0 + 0.3 * max(0.0, cos(aq)));
    float wob = (dnoise(vec2(rq * 7.0, cellS * 2.3 + seed)) - 0.5) * 0.3;
    float streak = (1.0 - smoothstep(0.10, 0.34, abs(fract(ks) - 0.5 + wob) + rq * 0.22))
                 * (1.0 - smoothstep(lenS * 0.65, lenS, rq)) * step(0.2, rq);
    /* the crater, the rim, the char and the soot */
    float crater = 1.0 - smoothstep(0.23, 0.28, rr);
    float rim = smoothstep(0.19, 0.27, rr) * (1.0 - smoothstep(0.29, 0.40, rr));
    float charZ = 1.0 - smoothstep(0.28, 0.60, rr * (0.8 + 0.4 * dfbm(q * 3.0 + seed)));
    float soot = (1.0 - smoothstep(0.42, 1.0, rq)) * (0.4 + 0.6 * dfbm(q * 4.0 + seed * 3.0));
    /* the droplets, thrown out past the rim and drawn out along the
       way each one flew */
    float drops = 0.0;
    for (int i = 0; i < 18; i++) {
      vec2 h = dh2(vec2(float(i) * 2.13, seed * 5.7));
      float th = h.x * 6.2831853;
      float dist = 0.34 + 0.56 * h.y * (0.8 + 0.25 * max(0.0, cos(th)));
      vec2 dir = vec2(cos(th), sin(th));
      vec2 dq = p - dir * dist;
      float al = dot(dq, dir) / (1.0 + dist * 1.8), ac = dot(dq, vec2(-dir.y, dir.x));
      float sz = mix(0.075, 0.022, h.y) * (0.6 + 0.8 * dh1(h * 3.1));
      drops = max(drops, 1.0 - smoothstep(sz * 0.7, sz, length(vec2(al, ac))));
    }
    float glassN = dfbm(q * 7.0 + seed * 2.0);
    vec3 glass = mix(vec3(0.015, 0.025, 0.022), vec3(0.07, 0.15, 0.11), smoothstep(0.55, 0.82, glassN));
    vec3 charC = mix(vec3(0.03, 0.025, 0.02), vec3(0.10, 0.08, 0.06), dfbm(q * 12.0 + seed));
    col = mix(charC, glass, crater);
    a = max(crater, max(charZ * 0.97, max(streak * 0.9, max(soot * 0.82, drops * 0.95))));
    col = worldShade(col, lit, viewDepth, wp, 0.0);
    float cr = cracks(q, seed, 13.0) * step(0.27, rr) * (1.0 - smoothstep(0.55, 0.9, rr));
    float n2 = dfbm(q * 8.0 + seed * 9.0);
    float veins = (1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5))) * charZ * step(0.29, rr);
    float flick = 0.75 + 0.25 * dnoise(q * 10.0 + vec2(uTime * 2.7, -uTime * 2.1));
    glow = hotRamp(clamp(0.55 + 0.45 * core, 0.0, 1.0)) * crater * (core * 2.2 + heat * 0.3 * (1.0 - rr / 0.28))
         + hotRamp(clamp(heat * 1.1, 0.0, 1.0)) * rim * heat * 2.6
         + hotRamp(clamp(ember * 0.8, 0.0, 1.0)) * max(cr, veins) * ember * flick * 1.6
         + hotRamp(clamp(heat, 0.0, 1.0)) * (drops + streak * 0.35) * heat * 1.3
         + vec3(0.45, 1.0, 0.6) * rim * core * 0.9;
  } else {
    /* SLAG: a gob of what the sear threw, landed round it. A ragged
       blob with a spray of drops ahead of it along the throw, the way a
       spatter of blood is drawn but in black glass — orange from the
       edge in while it is fresh, cooling out over a few seconds. */
    float heat = exp(-age / 4.0);
    float R = rag(ang, seed, 0.4);
    float rb = r / (R * (0.8 + 0.2 * dh1(vec2(seed, 3.0))));
    float blob = 1.0 - smoothstep(0.26, 0.33, rb);
    float drops = 0.0;
    for (int i = 0; i < 10; i++) {
      vec2 h = dh2(vec2(float(i) * 1.91, seed * 6.3));
      float dist = 0.28 + 0.66 * h.x;
      vec2 c = vec2(dist * 0.95 - 0.1, (h.y - 0.5) * 1.2 * dist);
      float sz = mix(0.10, 0.03, dist) * (0.6 + 0.8 * dh1(h * 4.0));
      vec2 dq = p - c;
      dq.x /= 1.0 + dist * 2.0;
      drops = max(drops, 1.0 - smoothstep(sz * 0.75, sz, length(dq)));
    }
    float m = max(blob, drops);
    float n = dfbm(p * 6.0 + seed * 4.0);
    float soot = (1.0 - smoothstep(0.2, 0.8, rb)) * 0.6 * (0.5 + 0.5 * n);
    col = worldShade(mix(vec3(0.025, 0.022, 0.02), vec3(0.09, 0.08, 0.07), n), lit, viewDepth, wp, 0.0);
    a = max(m * 0.96, soot);
    float edge = blob * smoothstep(0.14, 0.30, rb);
    glow = hotRamp(clamp(heat * (0.6 + 0.5 * n), 0.0, 1.0)) * (m * 0.6 + edge * 1.2) * heat * 1.8;
  }
  a *= fade;
  glow *= fade;
  if (a < 0.004 && dot(glow, vec3(1.0)) < 0.004) discard;
  /* premultiplied: the paint at its alpha, and the glow added on top */
  gl_FragColor = vec4(col * a + glow, a);
}
`;

const COPY_FRAG = /* glsl */`
#include <packing>
uniform sampler2D tSrc;
varying vec2 vUv;
void main() { gl_FragColor = packDepthToRGBA(texture2D(tSrc, vUv).x); }
`;
const COPY_VERT = /* glsl */`
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }
`;

export class Decals {
  constructor(game) {
    this.game = game;
    this.pools = {
      hole: new Pool('hole', POOLS.hole), heat: new Pool('heat', POOLS.heat), frost: new Pool('frost', POOLS.frost),
      blood: new Pool('blood', POOLS.blood), burn: new Pool('burn', POOLS.burn),
      sear: new Pool('sear', POOLS.sear),
    };
    this.tics = 0;
    this.holes = 0; this.scorches = 0;      // counts, for the readout and the test
    this.bloods = 0; this.burns = 0;
    this.sears = 0; this.slags = 0;
    this._n = { nx: 0, ny: 0, nz: 0 };
    this._basis = { ux: 0, uy: 0, uz: 0, vx: 0, vy: 0, vz: 0 };
  }

  /* ---- placing ------------------------------------------------------ */
  _surface(x, y) {
    const sec = this.game.level?.sectorAt?.(x, y);
    return { light: sec ? (sec.light ?? 0.75) : 0.75, sky: sec && sec.outdoor ? 1 : 0 };
  }

  /** A round has landed on a surface. `hot` is a minigun round: a
   *  bigger hole with a burnt ring, whose lip glows and cools. */
  hole(x, y, z, n, hot = false) {
    const P = this.pools.hole;
    const i = P.alloc(true);
    const s = (HOLE_SIZE[0] + (pRandom() / 255) * (HOLE_SIZE[1] - HOLE_SIZE[0])) * (hot ? HOT_SCALE : 1);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, n, s, (pRandom() / 255) * Math.PI * 2, 0.92, light, sky, hot ? 2 : 0);
    P.born[i] = this.tics;
    this.holes++;
  }

  /** The angle, about the normal `n`, that points along (dx, dy, dz)
   *  laid flat on the surface — what turns a spatter to face the way it
   *  was thrown. Pure. */
  throwAngle(n, dx, dy, dz) {
    const B = surfaceBasisInto(n.nx, n.ny, n.nz, this._basis);
    const du = dx * B.ux + dy * B.uy + dz * B.uz, dv = dx * B.vx + dy * B.vy + dz * B.vz;
    return (du || dv) ? Math.atan2(dv, du) : cosmetic() * Math.PI * 2;
  }

  /** A SPATTER OF BLOOD on a surface, thrown along (dx, dy, dz). */
  blood(x, y, z, n, dx = 0, dy = 0, dz = 0, size = 0) {
    const P = this.pools.blood;
    const i = P.alloc(true);
    const s = size || BLOOD_SIZE[0] + cosmetic() * (BLOOD_SIZE[1] - BLOOD_SIZE[0]);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, n, s, this.throwAngle(n, dx, dy, dz), 0.95, light, sky, 0);
    P.born[i] = this.tics;
    this.bloods++;
    return i;
  }

  /** A POOL of it on the floor at (x, y), under somebody who has come
   *  apart or gone down; it spreads over its first few seconds. */
  pool(x, y, z, size = 0) {
    const P = this.pools.blood;
    const i = P.alloc(true);
    const s = size || POOL_SIZE[0] + cosmetic() * (POOL_SIZE[1] - POOL_SIZE[0]);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, UP, s, cosmetic() * Math.PI * 2, 0.95, light, sky, 1);
    P.born[i] = this.tics;
    this.bloods++;
    return i;
  }

  /** SOMEBODY HAS BEEN HIT at (hx, hy, hz) by something going along
   *  (dx, dy, dz): a spatter on the floor at their feet, thrown the way
   *  the round went, and — on every wall close enough behind them — a
   *  spray of it up the wall, at the heights the blood would have
   *  reached it. See WALL_SPRAY. Nothing at all for something that does
   *  not bleed. */
  bleed(a, hx, hy, hz, dx, dy, dz = 0) {
    if (!bleeds(a, this.game.player)) return 0;
    const len = Math.hypot(dx, dy, dz) || 1;
    const ux = dx / len, uy = dy / len, uz = dz / len;
    const lv = this.game.level;
    let n = 0;
    /* the floor, a little way past them */
    const k = 6 + cosmetic() * 18;
    const fx = hx + ux * k, fy = hy + uy * k;
    const sec = lv?.sectorAt?.(fx, fy);
    if (sec) { this.blood(fx, fy, a.z ?? sec.floor, UP, ux, uy, 0); n++; }
    /* and the walls behind them */
    n += this.sprayWalls(hx, hy, hz, ux, uy, uz, WALL_SPRAY, BLOOD_REACH, WALL_CONE);
    return n;
  }

  /** BLOOD UP THE WALLS round (hx, hy, hz): `rays` rays in a cone of
   *  `cone` radians either side of (ux, uy, uz) — the first one down
   *  the middle, so the straight-behind spatter a round always left is
   *  still there — out to `reach`, and every one that meets a wall
   *  leaves a spatter on it, facing the side the blood came from and
   *  thrown along the ray and a little down. The nearer the wall the
   *  bigger the spatter: blood that has a foot to travel arrives as a
   *  sheet, blood that has two metres arrives as drops. `scale` is for
   *  the warhead, which throws more of it than a round does. A cone of
   *  pi is every direction at once. Returns how many landed. */
  sprayWalls(hx, hy, hz, ux, uy, uz, rays, reach, cone, scale = 1) {
    const lv = this.game.level;
    if (!lv?.rayHitWall) return 0;
    const base = Math.atan2(uy, ux);
    const flat = Math.hypot(ux, uy) || 1;
    const under = lv.sectorAt?.(hx, hy);
    const fl = under ? under.floor : -Infinity;
    let n = 0;
    for (let k = 0; k < rays; k++) {
      const yaw = k === 0 ? base : base + (cosmetic() * 2 - 1) * cone;
      const rise = k === 0 ? uz / flat : uz / flat + (cosmetic() - 0.62) * 0.7;
      const c = Math.cos(yaw), s = Math.sin(yaw);
      const wall = lv.rayHitWall(hx, hy, hz, hx + c * reach, hy + s * reach, hz + rise * reach);
      if (!wall || !wall.line) continue;
      /* NOT UNDER THE FLOOR: a ray thrown down met a one-sided wall
         below the floor's own level, where nobody will ever see it, so
         it is brought up to the skirting — which is where blood thrown
         at the foot of a wall ends up anyway */
      if (wall.z < fl + 2) wall.z = fl + 2 + cosmetic() * 10;
      const near = 1 - wall.t;
      const size = (WALL_SPATTER[0] + (WALL_SPATTER[1] - WALL_SPATTER[0]) * (near * 0.75 + cosmetic() * 0.25)) * scale;
      this.blood(wall.x, wall.y, wall.z, wallNormal(wall.line, hx, hy), c, s, rise - 0.35, size);
      n++;
    }
    return n;
  }

  /** A BURNING HOLE: what a warhead or a bomb leaves where it went off.
   *  It burns for a few seconds and stays, charred, after. */
  burn(x, y, z, n, size = BURN_SIZE) {
    const P = this.pools.burn;
    const i = P.alloc(true);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, n, size * (0.85 + 0.3 * cosmetic()), cosmetic() * Math.PI * 2, 1, light, sky, 0);
    P.born[i] = this.tics;
    this.burns++;
    return i;
  }

  /** A SEAR: where the positron lance's column landed — the crater,
   *  enormous, turned so its streaks lean the way the beam was going
   *  (dx, dy, dz). It glows for as long as its age says; see the SEAR
   *  branch of the shader, and SEAR in js/beam.js for the size. */
  sear(x, y, z, n, size, dx = 0, dy = 0, dz = 0) {
    const P = this.pools.sear;
    const i = P.alloc(true);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, n, size * (0.9 + 0.2 * cosmetic()), this.throwAngle(n, dx, dy, dz), 1, light, sky, 0);
    P.born[i] = this.tics;
    this.sears++;
    return i;
  }

  /** And a gob of SLAG thrown out of it, landed at (x, y, z) on the same
   *  surface, thrown along (dx, dy, dz). */
  slag(x, y, z, n, size, dx = 0, dy = 0, dz = 0) {
    const P = this.pools.sear;
    const i = P.alloc(true);
    const { light, sky } = this._surface(x, y);
    P.place(i, x, y, z, n, size, this.throwAngle(n, dx, dy, dz), 1, light, sky, 1);
    P.born[i] = this.tics;
    this.slags++;
    return i;
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
      P.born[i] = this.tics;
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
      H.born[j] = this.tics;
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
  /** Build the one instanced box every decal is drawn with, and the
   *  depth copy it reads. `scene` is accepted and left alone: the boxes
   *  are not part of the world's scene, because they have to be drawn
   *  after it, against its depth — see draw(), which js/lofi.js calls. */
  attach(scene) {
    const N = Object.values(this.pools).reduce((n, P) => n + P.max, 0);
    const box = new THREE.BoxGeometry(1, 1, 1);
    const g = new THREE.InstancedBufferGeometry();
    g.setIndex(box.index);
    g.setAttribute('position', box.attributes.position);
    const inst = (name, k) => {
      const at = new THREE.InstancedBufferAttribute(new Float32Array(N * k), k);
      at.setUsage(THREE.DynamicDrawUsage);
      g.setAttribute(name, at);
      return at;
    };
    this._at = { iC: inst('iC', 3), iU: inst('iU', 3), iV: inst('iV', 3), iN: inst('iN', 3), iP: inst('iP', 4), iL: inst('iL', 2) };
    g.instanceCount = 0;
    this.depthCopy = new THREE.WebGLRenderTarget(4, 4, {
      minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter,
      format: THREE.RGBAFormat, type: THREE.UnsignedByteType, depthBuffer: false, stencilBuffer: false,
    });
    this.depthCopy.texture.generateMipmaps = false;
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        tDepth: { value: this.depthCopy.texture }, uRes: { value: new THREE.Vector2(1, 1) },
        uInvProj: { value: new THREE.Matrix4() }, uCamWorld: { value: new THREE.Matrix4() },
        uTime: { value: 0 }, ...worldUniforms(),
      },
      vertexShader: DECAL_VERT, fragmentShader: DECAL_FRAG,
      extensions: { derivatives: true },
      transparent: true, depthWrite: false, depthTest: false,
      side: THREE.BackSide, fog: false, toneMapped: false,
      /* PREMULTIPLIED: see the note over DECAL_VERT */
      blending: THREE.CustomBlending, blendEquation: THREE.AddEquation,
      blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor,
      blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.name = 'decals';
    this.scene = new THREE.Scene();
    this.scene.add(this.mesh);
    /* the copy: the world's depth into eight-bit RGBA, one triangle */
    const tri = new THREE.BufferGeometry();
    tri.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    tri.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
    this.copyMat = new THREE.ShaderMaterial({
      uniforms: { tSrc: { value: null } }, vertexShader: COPY_VERT, fragmentShader: COPY_FRAG,
      depthTest: false, depthWrite: false,
    });
    const q = new THREE.Mesh(tri, this.copyMat);
    q.frustumCulled = false;
    this.copyScene = new THREE.Scene();
    this.copyScene.add(q);
    this.copyCamera = new THREE.Camera();
    for (const P of Object.values(this.pools)) P.mesh = this.mesh;
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

  /** Which shader kind a slot of pool P is. */
  kindOf(P, i) {
    switch (P.kind) {
      case 'hole': return P.frame[i] === 1 ? KIND.SCORCH : P.frame[i] === 2 ? KIND.HOT : KIND.HOLE;
      case 'heat': return KIND.HEAT;
      case 'frost': return KIND.FROST;
      case 'blood': return P.frame[i] === 1 ? KIND.POOL : KIND.SPATTER;
      case 'sear': return P.frame[i] === 1 ? KIND.SLAG : KIND.SEAR;
      default: return KIND.BURN;
    }
  }

  /** `ex, ey` is the eye and `vx, vy` the unit direction it looks
   *  along, in game coordinates; with none given nothing is culled.
   *  Writes every live decal in view into the box's instance buffers,
   *  compacted, with no allocation in the loop. Drawn later, by draw(). */
  render(ex = 0, ey = 0, vx = 0, vy = 0) {
    this._carry();
    if (!this.mesh) return;
    const cull = vx !== 0 || vy !== 0;
    const R2 = DRAW_RANGE * DRAW_RANGE;
    const B = this._basis;
    const A = this._at;
    const C = A.iC.array, U = A.iU.array, V = A.iV.array, Nn = A.iN.array, Pp = A.iP.array, L = A.iL.array;
    let n = 0;
    /* in this order, which is the order they paint in: the sears under
       everything, since they are the biggest and the oldest-looking,
       then the blood and the burns under the holes, the rime over them,
       the glow on top */
    for (const key of ['sear', 'blood', 'burn', 'hole', 'frost', 'heat']) {
      const P = this.pools[key];
      let drawn = 0;
      for (let i = 0; i < P.max; i++) {
        const strength = P.strength[i];
        if (strength <= 0) continue;
        const px = P.x[i], py = P.y[i], h = P.size[i] / 2;
        if (cull) {
          const dx = px - ex, dy = py - ey;
          if (dx * dx + dy * dy > R2) continue;
          if (dx * vx + dy * vy < -h * 1.5) continue;
        }
        const nx = P.nx[i], ny = P.ny[i], nz = P.nz[i];
        surfaceBasisInto(nx, ny, nz, B);
        const c = Math.cos(P.rot[i]), sn = Math.sin(P.rot[i]);
        /* the box's two axes across the surface, turned by rot about the
           normal, half its width long; and the third along the normal */
        const ax = (B.ux * c + B.vx * sn) * h, ay = (B.uy * c + B.vy * sn) * h, az = (B.uz * c + B.vz * sn) * h;
        const bx = (B.vx * c - B.ux * sn) * h, by = (B.vy * c - B.uy * sn) * h, bz = (B.vz * c - B.uz * sn) * h;
        const kind = this.kindOf(P, i);
        const dep = Math.max(2, P.size[i] * DEPTH[kind]);
        const o = n * 3;
        /* game (x, y, z) to three (x, z, -y) */
        C[o] = px; C[o + 1] = P.z[i]; C[o + 2] = -py;
        U[o] = ax; U[o + 1] = az; U[o + 2] = -ay;
        V[o] = bx; V[o + 1] = bz; V[o + 2] = -by;
        Nn[o] = nx * dep; Nn[o + 1] = nz * dep; Nn[o + 2] = -ny * dep;
        const q = n * 4;
        Pp[q] = kind; Pp[q + 1] = strength; Pp[q + 2] = P.seed[i]; Pp[q + 3] = (this.tics - P.born[i]) / TICRATE;
        L[n * 2] = P.light[i]; L[n * 2 + 1] = P.sky[i];
        n++; drawn++;
      }
      P.drawn = drawn;
      P.dirtyPos = false; P.dirtyStrength = false;
    }
    this.drawn = n;
    this.mesh.geometry.instanceCount = n;
    for (const k in A) A[k].needsUpdate = true;
  }

  /** DRAW THEM, into `target`, against the depth the world has just
   *  left in it. js/lofi.js calls this between the world and the glow,
   *  with the world's own camera. The depth is copied first, because a
   *  texture cannot be read while the framebuffer it belongs to is being
   *  drawn into. */
  draw(renderer, camera, target) {
    if (!this.mesh || !this.drawn || !target.depthTexture) return false;
    if (this.depthCopy.width !== target.width || this.depthCopy.height !== target.height)
      this.depthCopy.setSize(target.width, target.height);
    const ac = renderer.autoClear;
    renderer.autoClear = false;
    this.copyMat.uniforms.tSrc.value = target.depthTexture;
    renderer.setRenderTarget(this.depthCopy);
    renderer.render(this.copyScene, this.copyCamera);
    this.copyMat.uniforms.tSrc.value = null;
    const u = this.mesh.material.uniforms;
    u.uRes.value.set(target.width, target.height);
    u.uInvProj.value.copy(camera.projectionMatrixInverse);
    u.uCamWorld.value.copy(camera.matrixWorld);
    u.uTime.value = this.tics / TICRATE;
    renderer.setRenderTarget(target);
    renderer.render(this.scene, camera);
    renderer.autoClear = ac;
    return true;
  }

  get liveCount() { return Object.values(this.pools).reduce((n, P) => n + P.count, 0); }
}
