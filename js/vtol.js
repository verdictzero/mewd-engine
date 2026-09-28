/* =====================================================================
   MEWD — the gunship
   =====================================================================

   CLOSE AIR SUPPORT COMES WITH THE ARMY, at the user's request, and it
   is the user's model: a tilt-engine VTOL, a three-barrel vulcan in a
   turret under the nose, a searchlight beside the gun, two nacelles
   on the wing and a third engine in the tail. The file came with the
   answers in it — a marker sphere inside the gun for where the rounds
   leave, one inside the lamp module for where the light does, and the
   nodes NAMED for what they are: a left-right parent, an up-down
   parent, a gun that spins. tools/prep-model.mjs reads the two spheres
   into the file's extras (`markers`, in the frame of the part each
   sits in) and takes them out of the mesh; this reads the names.

   IT IS NOT A VEHICLE, in the js/vehicles.js sense, though it borrows
   the vehicles' paint, their pieces and their arithmetic. A vehicle is
   one mesh with one transform; this is a TREE of them — the turret
   yaws on the nose, the gun pitches in the turret and spins on its
   own axis, the lamp pitches with the gun, the nacelles tilt on the
   wing and the tail engine tilts with them — because everything the
   user asked it to do is a part moving against another part. Each
   part is its own mesh in the vehicles' own material (js/car.js's
   carMesh, so it is lit, fogged, charred and burnt by the same shader
   the vans are), hung off three.js groups that are turned every frame
   from numbers the simulation owns. Seven draw calls for one aircraft.

   HOW IT FLIES. Not on a route: on a CONTROLLER. Every tic it wants
   to be somewhere — a point on a slow orbit round you at a standoff,
   the fire lane in front of the doors if you are indoors, or, every
   so often, directly over a knot of people — and it accelerates
   toward that point under a cap, at an altitude it holds with a
   spring, and it faces the way it is going or faces you when it is
   not going anywhere. That is the whole of the flight, and the rest
   is what the airframe does ABOUT the flight, which is the part the
   user asked for: THE NACELLES VECTOR THE THRUST, physically. This
   thing hovers on thrust pointed DOWN and moves by pointing some of it
   backward, so the angle each tic is the angle of the thrust vector the
   controller just asked for — atan of the lift over the forward
   acceleration plus the drag it is already pushing against. Holding
   station that is a right angle, nozzles straight down; building speed
   it flattens toward the nose; braking it goes past the right angle and
   points forward. And DIFFERENTIALLY when it yaws, one pod up and one
   down, which is how a machine with no tail rotor turns.

   WHAT IS DRAWN IS A GEARED SHARE OF THAT — see `hover` and `gear` in
   VTOL below for why, which is the model's own proportions — and the
   pods are RATE LIMITED on the way there, because a nacelle is an
   actuator and not a number: a demand that jumps cannot make the
   drawing jump. The body pitches gently with the ACCELERATION, nose
   down to go and nose up to stop, and banks INTO a turn, because it is
   held up by thrust and not by springs — the same reasoning as the
   APC's, one storey higher. The tail engine takes most of the pods'
   angle and leads the pitch, doing what a tail does.

   THE JET WASH is the exhaust arriving. Each engine's exhaust is a
   ray from the nacelle along the way its thrust is not pointing, and
   where that ray meets something — the tarmac, a wall, the roof of a
   car under it — is where the grit is thrown (Effects.wash), outward
   along whatever it landed on, harder the nearer the engine. AND IT
   IS HOT. Anybody standing where an exhaust lands while the aircraft
   is low CATCHES, at the user's request — people, not cars: it is
   the person the wash reaches and the person who is ignited, through
   Actor.ignite, and never the floor under them, which is the one call
   that would light the vehicles. So it hovers over a crowd and the
   crowd starts running with the fire on it, which is what it is for.

   THE VULCAN is the minigun's own tracer (js/tracers.js) fired the
   other way: three rounds a tic through Game.hitscan, level with the
   turret, each a hitscan with its own scatter, in bursts with a pause
   between, and the streak off every one of them from the muzzle
   marker to wherever it landed. There is no muzzle flash on the
   drawing — the user did not want one on their minigun either — and
   in its place a FLARE: the searchlight's own flare, small and warm,
   flickering at the muzzle while it fires.

   THE SEARCHLIGHT IS A FLARE AND NOTHING ELSE, at the user's request.
   It was a lit cone in the world shader for an afternoon — pointed
   where the turret points, no shadows, on every surface that shades
   with worldShade — and the user has had the beam taken out. What is
   kept is the thing you actually read a searchlight by at night, which
   is the LAMP ITSELF: a massive anamorphic flare, a screen-facing quad
   whose shader draws a horizontal streak most of the screen wide,
   thin, blue-white, with a gradient sphere at the centre of it,
   brightest when the reflector is pointed at you and falling away as
   it swings off.

   AND IT IS OCCLUSION AWARE, at the user's request — which, for a
   thing drawn over the top of the frame with the depth test off, means
   the three tests are made by hand, every frame, for each flare:

     BEHIND THE EYE   a flare is sized by its own DISTANCE so that it
                      stays the same size on the screen wherever the
                      lamp is, and a lamp behind your shoulder has a
                      negative one. Left in, the corners project
                      through infinity and what lands on the screen is
                      a white bowtie across the whole frame, which is
                      exactly what the first build of it did.
     THE WORLD        one sight line from the eye to the lamp — the
                      same call a trooper uses to decide whether it can
                      see you — so a wall, a shut door or the shop
                      between you and the aircraft takes the flare
                      away.
     ITS OWN HULL     and this is the one that is actually about an
                      aircraft. The lamp hangs under the NOSE, so the
                      fuselage is between you and it from above and
                      from behind, which is most of the sky the thing
                      flies in. The hull is a box in the aircraft's own
                      frame and the sight line is walked against it, so
                      the flare goes out as it banks over the top of
                      you and comes back as it rolls out.

   None of the three is a hard switch. A flare that pops off at a wall
   edge is worse than one that is a few frames late, so what the tests
   decide is a TARGET and the flare eases onto it — see Flare.render.

   AND IT CAN BE SHOT DOWN, at the user's request. Three shootable
   cylinders ride under it at its altitude (AIRBODY in js/states.js),
   each pointing back here, so the minigun's pitched rounds land on it
   the way they land on a van. Enough of them and it GOES UP, EPICALLY:
   a bang in the air, a dozen fireballs, a cloud of sparks, pieces of
   the aircraft's own skin thrown off it (the vehicles' Chunk, cut
   from this model), and then THE TAIL SPIN — it is still flying, on
   fire, the yaw winding up, the nose going down, the nacelles thrown
   to nothing, trailing flame and smoke and popping as it falls, until
   the lowest corner of it meets the ground and it goes up again on
   the tarmac, bigger, with a pool of fire under it and more pieces,
   and lies there charred and smouldering for the rest of the night.

   WHEN IT COMES: with the army. The tic the army is called, the first
   is ordered and arrives from the far end of the road eight seconds
   later, high, and comes down over the lot; when one is lost the next
   is fifty seconds behind it; and once the army's own curve has
   doubled twice there are two of them. See Gunships at the bottom.

   Positions are GAME coordinates (x, y across the map, z up) in the
   simulation and three's (x, z, -y) in the meshes, like everything
   else. The model's own axes — glTF's +Z nose, +Y up, +X left — go
   through the same swap the vans do (see js/car.js), so a part's
   local frame here is x forward, y up, z to the RIGHT.
   ===================================================================== */

import * as THREE from 'three';
import { parseGLB, readAccessor } from './glb.js';
import { carTexture, carGeom, carMesh, modelVehicle, chunkGeometry } from './car.js';
import { turn, lowestOf, extentOf, Chunk } from './vehicles.js';
import { TICRATE, pRandom, angleDiff, clamp, dist2 } from './util.js';

/* HOW LONG IT IS, nose to tail, on the game's ruler — the one number
   about the game rather than the file, the way VAN_LENGTH is. Four
   hundred and twenty: half again the APC, with a wingspan to match,
   which over a car park of two-hundred-unit vans reads as an aircraft
   and not as a drone. */
export const VTOL_LENGTH = 420;

export const VTOL = {
  /* the airframe */
  health: 1600,
  shotArmour: 9,          // a minigun round is twenty to forty: two to four off it, six hundred rounds, four seconds of the trigger
  fireArmour: 40,         // a bang on the ground under it is nothing to it
  alt: 330,               // how high it holds over open ground, under the lot's own 480 ceiling so it can be shot
  roofAlt: 660,           // and over the building, which it clears rather than avoids
  lowAlt: 215,            // and when it comes down over people
  speed: 24,              // units a tic, flat out — a hair under the vans
  accel: 0.55,            // and how fast it gets there, units a tic a tic
  climb: 0.45,            // the most it will accelerate vertically
  turn: 0.045,            // radians a tic the heading may change
  /* ------------------------------------------------------------------
     THE THRUST VECTOR, and what the airframe shows of it

     TWO ANGLES, and the whole of the fix is that they are two. `vector`
     is where the JET is pointed, measured up from level: a right angle
     in a hover, flattening toward the nose as it builds speed, past the
     right angle when it is braking. `tilt` is where the POD is DRAWN,
     which is a geared-down share of the same angle.

     They are separate because of the model's own proportions. Each
     nacelle is two hundred and eleven units long — half the whole
     aircraft — so a pod swung to a true right angle is a plate the
     length of the fuselage standing on its edge, which is what a V-22
     looks like from the side and is not what THIS looks like from the
     side: it reads as the thing coming apart. Rendered through the
     range, it stops reading as an engine somewhere past forty degrees.

     So the pod carries part of the angle and the nozzle inside it
     carries the rest, which is a real arrangement rather than a dodge —
     a big blended pod with a vectoring nozzle in it, not a rotating
     engine. What is DRAWN is the pod, geared so it never stands on end.
     What the JET does is the true angle, which is why the wash lands
     UNDER it in a hover and streams aft when it is moving.

     `hover` is where the pods sit holding station, `gear` is how much
     of a radian of jet one radian of pod is worth, and the two limits
     are where the pod stops looking like an engine.  */
  hover: 0.62, gear: 0.61, tiltMin: -0.18, tiltMax: 1.05,
  vectorMin: 0.45, vectorMax: 2.25,
  weight: 0.85,           // what the lift is holding up, in the vehicles' units
  accelGain: 3.2,         // how much of the angle the acceleration is worth
  dragGain: 0.05,         // and how much of it the speed it is already doing is
  accelSmooth: 0.12,      // the low pass on the acceleration the angle is read off
  /* AND THE POD IS A MACHINE, which is the other half of the fix. It
     used to chase its target through a first-order lag at nearly a
     fifth a tic, so a demand that jumped — and an acceleration that is
     a controller output DOES jump, every time the thing saturates or
     comes off a corner — put a jump straight into the drawing. A
     nacelle is an actuator with a rate: this is the most of a radian it
     can travel in a tic, which is the pod's whole range in about a
     second and a half, and it is the reason a jittery demand can no
     longer make a jittery aircraft. */
  tiltRate: 0.014,
  diffGain: 4.0, diffMax: 0.18,   // one pod forward and one back, to yaw
  auxShare: 0.8,          // how much of the pods' angle the tail engine takes
  /* where it goes */
  standoff: 820,          // how far from you it orbits
  orbit: 0.0048,          // radians a tic round that orbit: one lap in about forty seconds
  arrive: 500,            // this near its first station it is on station
  torchEvery: 11 * TICRATE,   // how often it goes looking for a crowd to hover over
  torchFor: 9 * TICRATE,      // and how long it stays over them
  torchReach: 1700,           // and how far it will go to find one
  /* the gun */
  gun: {
    range: 2300, rounds: 3, damage: [2, 8], spread: 0.032,
    burst: 26, pause: 42,     // tics firing, tics between bursts
    slew: 0.055, aim: 0.07,   // radians a tic the turret turns, and how close is aimed
    yawLimit: 2.5, pitch: [-1.35, 0.30],
  },
  /* the lamp */
  /* THE LAMP, WHICH NO LONGER LIGHTS ANYTHING. It threw a lit cone into
     the world shader for an afternoon and the user has taken the beam
     out; what is kept is the FLARE, which is what you actually read a
     searchlight by at night. So these two are no longer a cone of
     light, they are how directly you have to be looking INTO the lamp
     for the flare to be at its brightest: full inside `inner`, eleven
     degrees off the reflector's axis, and down to the dim off-axis
     glint by `outer`, twenty. The same pair of angles the beam had,
     because it is the same reflector.

     `hullClear` is the other half of the occlusion test: how near the
     lamp a sight line may clip the aircraft's own box and still count
     as having arrived. The lamp hangs under the nose INSIDE that box —
     four units up from its floor — so a line coming from below enters
     the box a few units before it reaches the lamp and always would.
     Twenty-six is past that and a long way short of the seventy-odd a
     line from above has to cross. */
  lamp: { outer: 0.94, inner: 0.98, hullClear: 26 },
  /* the exhaust */
  /* THE EXHAUST. `reach` is how far down a jet is worth drawing at all,
     `radius` how wide the pool of it on the ground is — a hundred and
     ninety, so that the two wing engines' pools, a hundred and sixty
     either side of the centreline, MEET under the fuselage and anybody
     it is directly over is in one of them — and `hot` is how close the
     ground has to be before what lands on it is hot enough to light
     somebody. Three hundred sits between the two altitudes on purpose:
     cruising at three hundred and thirty it lights nothing, and the one
     thing that puts it low enough is coming down over a crowd.

     TWO HUNDRED AND FIFTY rather than the three hundred it started at,
     because the nozzle moved: the jet now leaves the aft end of a pod
     that tilts, which in a hover hangs some forty units lower than the
     point it used to leave from, and forty units is most of the margin
     between the two altitudes. Measured down the ray, a torch run is a
     hundred and seventy and a cruise is two hundred and ninety. */
  wash: { every: 2, reach: 520, radius: 190, hot: 250, ignite: [260, 420], scareEvery: 24, scare: 420 },
  /* the wing */
  firstDelay: 8 * TICRATE,    // after the army is called
  replace: 50 * TICRATE,      // after one is lost
  max: 2, secondAt: 4,        // two of them once the army's pressure is four
  /* HOW FAR OUT IT COMES INTO BEING, and the same reasoning as the
     vans' `runIn` in js/responders.js: the road leaves the world nine
     thousand units out, which at twenty-four units a tic is eighteen
     seconds of an empty sky. It flies in from `runIn` of you, along the
     line to whichever end of the road is nearer — so it comes from the
     road's own direction and is overhead in five seconds however far
     across the map you have walked. Four thousand two hundred is ten
     van-lengths past the far corner of the lot: well outside anything
     you can pick out against a night sky. */
  runIn: 4200,
  /* going down */
  gravity: 0.11,              // what is left of the lift is not nothing
  lurch: 2.5,                 // and the last of it, thrown upward as it is hit
  spin: 0.17,                 // radians a tic of tail spin, at full wind-up: a turn and a half on the way down
  smoulder: 60 * TICRATE,
};

const rnd = () => pRandom() / 255;
const between = ([a, b]) => a + rnd() * (b - a);
/** An actuator: toward `want`, by at most `rate` this tic. */
const slew = (now, want, rate) => now + clamp(want - now, -rate, rate);

/* WHAT HANGS OFF WHAT, named once: the two points the game cares about
   and the direction they both look along. Held as constants rather than
   written out at each call because the hull test takes the same chain
   the position does, and the two drifting apart would be a flare
   occluded against a turret pointing somewhere else. */
/* WHERE AN ENGINE'S JET LEAVES IT, in that engine's own frame, so the
   point swings with the pod as it tilts: the aft end of it, a little
   below the centreline. The pods run from a hundred and six units
   forward of their pivot to a hundred and six behind it. */
const POD_NOZZLE = [-86, -6, 0];
const AUX_NOZZLE = [-24, -6, 0];

const AIM_CHAIN = ['fuselage', 'turret', 'pitch'];
const MUZZLE_CHAIN = [...AIM_CHAIN, 'gun'];
const LAMP_CHAIN = [...AIM_CHAIN, 'lamp'];

/* ---------------------------------------------------------------------
   Turning things, in a part's own frame: x forward, y up, z right.
   --------------------------------------------------------------------- */
const rotY = (p, a) => { const c = Math.cos(a), s = Math.sin(a); return [p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c]; };
const rotZ = (p, a) => { const c = Math.cos(a), s = Math.sin(a); return [p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2]]; };
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];

/** `turn` from js/vehicles.js, undone: a point in the renderer's frame
 *  back into the aircraft's own. Which is what the occlusion test needs
 *  — the hull is a box in the aircraft's frame, so the EYE is what has
 *  to be moved, not the box. Each line is the matching line of `turn`
 *  solved for its input; the test holds the pair against each other. */
export function unturn(p, yaw, rx, rz) {
  const cy = Math.cos(yaw), sy = Math.sin(yaw);
  const x1 = p[0] * cy - p[2] * sy, z2 = p[0] * sy + p[2] * cy, y2 = p[1];
  const cx = Math.cos(rx), sx = Math.sin(rx);
  const y1 = y2 * cx + z2 * sx, z1 = -y2 * sx + z2 * cx;
  const cz = Math.cos(rz), sz = Math.sin(rz);
  return [x1 * cz + y1 * sz, -x1 * sz + y1 * cz, z1];
}

/**
 * Does the segment from `a` to `b` cross the box, and does it do so
 * more than `clear` from `b`? Slab test, in whatever frame all three
 * are already in. Pure, for the test.
 *
 * The clearance is not a fudge factor, it is the question being asked.
 * The lamp hangs under the nose INSIDE the fuselage's own box — a few
 * units up from its floor — so a sight line coming from below crosses
 * that floor just before it arrives, every time. What is being asked
 * is whether the hull is in the way, and a crossing that happens
 * within the lamp's own bracket is not the hull being in the way.
 */
export function boxBetween(a, b, box, clear) {
  const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  let t0 = 0, t1 = 1;
  for (let k = 0; k < 3; k++) {
    if (Math.abs(d[k]) < 1e-9) {
      if (a[k] < box.lo[k] || a[k] > box.hi[k]) return false;
      continue;
    }
    const inv = 1 / d[k];
    let lo = (box.lo[k] - a[k]) * inv, hi = (box.hi[k] - a[k]) * inv;
    if (lo > hi) { const t = lo; lo = hi; hi = t; }
    if (lo > t0) t0 = lo;
    if (hi < t1) t1 = hi;
    if (t0 > t1) return false;
  }
  const px = a[0] + d[0] * t0, py = a[1] + d[1] * t0, pz = a[2] + d[2] * t0;
  return Math.hypot(px - b[0], py - b[1], pz - b[2]) > clear;
}

/* =====================================================================
   THE MODEL, AS PARTS

   The GLB's nodes walked and kept apart, each mesh into the vehicles'
   own vertex layout (js/car.js's carGeom) in its own frame, recentred
   on the point it turns about. Nothing here is resampled: positions,
   UVs and indices are the file's, through the axis swap and the scale.
   ===================================================================== */
/* THE VANS' OWN FAKE CONTRAST, with the belly lifted. A car's
   underside is 0.40 of its light because a car's underside is a thing
   you glimpse when one is upside down; an aircraft's is the face you
   are looking at almost the whole time it is above you, and at 0.40 on
   night tarmac the user's model was a hole in the sky. Two thirds keeps
   the top and the bottom of it different — which is the only reason the
   nudge exists, there being no sun in this game — while leaving the
   thing you have to shoot down something you can see. */
const ROOF_LIT = 1.12, UNDER_LIT = 0.66, CONTRAST = 0.055, BODY_LIT = 0.82;
const NAMES = {
  fuselage: 'fuselage',
  turret: 'ClaudeThisIsThe3BarrelVulcanGunLeftRightRotationParent',
  pitch: 'ClaudeThisIsThe3BarrelVulcanGunUpDownRotationParent',
  gun: 'ClaudeSpinThisThisIsTheVulcanGun',
  lamp: 'SpotlightModule',
  nacelles: 'VTOL_engine_nacelles',
  aux: 'VTOL_aux_middle_rear_engine_exhaust',
};

/** glTF (x left, y up, z nose) to a part frame (x forward, y up, z right). */
const swap = (x, y, z, S = 1) => [z * S, y * S, -x * S];

/**
 * Fetch and decode the file: its JSON, its binary and its sheet, point
 * sampled like every model this game imports.
 */
export async function loadVtolModel(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  const { json, bin } = parseGLB(await res.arrayBuffer());
  const mat = (json.materials || []).find(m => m.pbrMetallicRoughness?.baseColorTexture);
  const tx = json.textures?.[mat?.pbrMetallicRoughness.baseColorTexture.index ?? 0];
  const im = json.images?.[tx?.source ?? 0];
  if (im?.bufferView === undefined) throw new Error(`${url}: the texture is not in the buffer`);
  const bv = json.bufferViews[im.bufferView];
  const bytes = bin.subarray(bv.byteOffset || 0, (bv.byteOffset || 0) + bv.byteLength);
  const bitmap = await createImageBitmap(new Blob([bytes], { type: im.mimeType }), { premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
  return { json, bin, texture: carTexture(bitmap, json.samplers?.[tx?.sampler]) };
}

/**
 * The aircraft out of the file: one entry per moving part, each with
 * its vertex arrays in its own frame, the offset of its pivot from its
 * parent's, and its parent. Plus the flattened vehicle definition the
 * pieces are cut from, the markers, and the scale.
 *
 * Pure — no three in it — so the smoke test can build one and hold
 * every part against the file.
 */
export function buildVtolModel(json, bin, length = VTOL_LENGTH) {
  const byName = new Map(json.nodes.map((n, i) => [n.name, i]));
  const need = name => { if (!byName.has(name)) throw new Error('the gunship has no node called ' + name); return json.nodes[byName.get(name)]; };
  for (const n of json.nodes) if (n.matrix || n.rotation || n.scale) throw new Error('gunship node ' + n.name + ' carries a rotation, scale or matrix; only translations are read');
  const markers = json.asset?.extras?.markers || {};
  if (!markers.muzzle || !markers.lamp) throw new Error('the gunship file has no muzzle and lamp markers; run tools/prep-model.mjs');

  /* ---- the flattened model, for the pieces and the box ------------- */
  const def = modelVehicle(json, bin, { length, id: 'vtol', name: 'Gunship', use: 'army' });
  /* and the box in the file's own units, walked the same way, so the
     parts and the pieces agree on where the middle is */
  const origins = new Map();        // node index -> its origin in glTF units
  const walk = (ni, at) => {
    const n = json.nodes[ni];
    const t = n.translation || [0, 0, 0];
    const here = [at[0] + t[0], at[1] + t[1], at[2] + t[2]];
    origins.set(ni, here);
    for (const c of n.children || []) walk(c, here);
  };
  for (const ni of json.scenes[json.scene ?? 0].nodes) walk(ni, [0, 0, 0]);
  const bb = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
  const primOf = ni => json.meshes[json.nodes[ni].mesh].primitives;
  const posOf = p => readAccessor(json, bin, p.attributes.POSITION).array;
  for (const [ni, at] of origins) {
    if (json.nodes[ni].mesh === undefined) continue;
    for (const p of primOf(ni)) {
      const pos = posOf(p);
      for (let i = 0; i < pos.length; i += 3) for (let k = 0; k < 3; k++) {
        const v = pos[i + k] + at[k];
        if (v < bb[k]) bb[k] = v;
        if (v > bb[3 + k]) bb[3 + k] = v;
      }
    }
  }
  const S = length / (bb[5] - bb[2]);                                   // units per glTF unit, longest along +Z
  const centre = [(bb[0] + bb[3]) / 2, (bb[1] + bb[4]) / 2, (bb[2] + bb[5]) / 2];

  /* ---- one part: a node's triangles into a frame of its own -------- */
  const tri3 = (pos, idx, i) => [idx[i], idx[i + 1], idx[i + 2]];
  const part = (name, ni, pivotG, parent, filter = null) => {
    const n = json.nodes[ni];
    const out = { name, parent, arrays: null, tris: 0, offset: null, pivot: pivotG };
    /* the pivot relative to the parent's origin, in the part frame */
    const pOrigin = parent ? parent.pivotWorld : centre;
    const here = origins.get(ni);
    const pivotWorld = [here[0] + pivotG[0], here[1] + pivotG[1], here[2] + pivotG[2]];
    out.pivotWorld = pivotWorld;
    out.offset = swap(pivotWorld[0] - pOrigin[0], pivotWorld[1] - pOrigin[1], pivotWorld[2] - pOrigin[2], S);
    const a = { position: [], uv: [], light: [], sky: [], charred: [], ink: [], normal: [] };
    if (n.mesh === undefined) { out.arrays = a; return out; }
    /* which way is out, for the light: away from the part's own middle */
    let cx = 0, cy = 0, cz = 0, cn = 0;
    for (const p of primOf(ni)) {
      const pos = posOf(p);
      for (let i = 0; i < pos.length; i += 3) { cx += pos[i]; cy += pos[i + 1]; cz += pos[i + 2]; cn++; }
    }
    cx /= cn || 1; cy /= cn || 1; cz /= cn || 1;
    for (const p of primOf(ni)) {
      if (p.mode !== undefined && p.mode !== 4) throw new Error('only triangle lists are supported');
      const pos = posOf(p);
      const idx = p.indices !== undefined ? readAccessor(json, bin, p.indices).array : Uint32Array.from({ length: pos.length / 3 }, (_, i) => i);
      const uv = p.attributes.TEXCOORD_0 !== undefined ? readAccessor(json, bin, p.attributes.TEXCOORD_0).array : null;
      for (let t = 0; t + 2 < idx.length; t += 3) {
        const [ia, ib, ic] = tri3(pos, idx, t);
        const g = i => [pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]];
        const A = g(ia), B = g(ib), C = g(ic);
        if (filter && !filter((A[0] + B[0] + C[0]) / 3)) continue;
        /* the geometric normal, in glTF axes, turned outward */
        const ux = B[0] - A[0], uy = B[1] - A[1], uz = B[2] - A[2];
        const vx = C[0] - A[0], vy = C[1] - A[1], vz = C[2] - A[2];
        let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
        const mg = Math.hypot(nx, ny, nz);
        if (mg < 1e-12) continue;
        nx /= mg; ny /= mg; nz /= mg;
        const mx = (A[0] + B[0] + C[0]) / 3 - cx, my = (A[1] + B[1] + C[1]) / 3 - cy, mz = (A[2] + B[2] + C[2]) / 3 - cz;
        if (nx * mx + ny * my + nz * mz < 0) { nx = -nx; ny = -ny; nz = -nz; }
        /* the vans' fake contrast: the top lit, the belly dark, the
           flanks a notch off the ends — in the part's own frame, since
           the thing is never on a compass bearing for long */
        let l;
        if (ny > 0.5) l = BODY_LIT * ROOF_LIT;
        else if (ny < -0.5) l = BODY_LIT * UNDER_LIT;
        else l = BODY_LIT + CONTRAST * (Math.abs(nx) - Math.abs(nz));
        for (const [i, P] of [[ia, A], [ib, B], [ic, C]]) {
          const q = swap(P[0] - pivotG[0], P[1] - pivotG[1], P[2] - pivotG[2], S);
          a.position.push(q[0], q[1], q[2]);
          a.uv.push(uv ? uv[i * 2] : 0, uv ? uv[i * 2 + 1] : 0);
          a.light.push(l); a.sky.push(1); a.charred.push(0);
          a.ink.push(1, 1, 1, 0);
          a.normal.push(nz, nx, ny);
        }
        out.tris++;
      }
    }
    out.arrays = a;
    return out;
  };

  /* ---- the tree ------------------------------------------------------ */
  const parts = {};
  const root = need(NAMES.fuselage);
  parts.fuselage = part('fuselage', byName.get(NAMES.fuselage), [0, 0, 0], null);
  parts.turret = part('turret', byName.get(NAMES.turret), [0, 0, 0], parts.fuselage);
  parts.pitch = part('pitch', byName.get(NAMES.pitch), [0, 0, 0], parts.turret);
  parts.gun = part('gun', byName.get(NAMES.gun), [0, 0, 0], parts.pitch);
  parts.lamp = part('lamp', byName.get(NAMES.lamp), [0, 0, 0], parts.pitch);
  /* THE NACELLES ARE ONE MESH IN THE FILE and two engines on the
     aircraft, so the mesh is cut down its middle — no triangle
     straddles it; the author drew two things — and each half turns
     about the middle of its own box, which is where its spar is. */
  {
    const ni = byName.get(NAMES.nacelles);
    need(NAMES.nacelles);
    const boxOf = side => {
      const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
      for (const p of primOf(ni)) {
        const pos = posOf(p), idx = p.indices !== undefined ? readAccessor(json, bin, p.indices).array : null;
        const n = idx ? idx.length : pos.length / 3;
        for (let t = 0; t + 2 < n; t += 3) {
          const ids = idx ? [idx[t], idx[t + 1], idx[t + 2]] : [t, t + 1, t + 2];
          const mx = ids.reduce((s2, i) => s2 + pos[i * 3], 0) / 3;
          if (!side(mx)) continue;
          for (const i of ids) for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], pos[i * 3 + k]); hi[k] = Math.max(hi[k], pos[i * 3 + k]); }
        }
      }
      return [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2];
    };
    const left = x => x > 0, right = x => x <= 0;           // glTF +X is the aircraft's left
    parts.nacelleL = part('nacelleL', ni, boxOf(left), parts.fuselage, left);
    parts.nacelleR = part('nacelleR', ni, boxOf(right), parts.fuselage, right);
  }
  {
    const ni = byName.get(NAMES.aux);
    need(NAMES.aux);
    /* the tail engine turns about the middle of its own box too */
    const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
    for (const p of primOf(ni)) { const a = json.accessors[p.attributes.POSITION]; for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], a.min[k]); hi[k] = Math.max(hi[k], a.max[k]); } }
    parts.aux = part('aux', ni, [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2], parts.fuselage);
  }
  if (!root) throw new Error('no fuselage');

  /* the two markers, in their parts' frames: the muzzle is on the gun
     and the lamp is in the lamp module, and the parts' pivots are their
     nodes' origins, so the marker's own point is the answer */
  const at = m => swap(m.at[0], m.at[1], m.at[2], S);
  const muzzle = at(markers.muzzle), lamp = at(markers.lamp);
  if (markers.muzzle.node !== NAMES.gun) throw new Error('the muzzle marker is in ' + markers.muzzle.node + ', not the gun');
  if (markers.lamp.node !== NAMES.lamp) throw new Error('the lamp marker is in ' + markers.lamp.node + ', not the lamp module');

  /* ------------------------------------------------------------------
     THE HULL, as one box in the aircraft's own frame

     What the flare's occlusion test is walked against: the FUSELAGE's
     own extent — not the whole aircraft's, which would include the
     turret hanging under the nose with the lamp on it, and not a
     sphere, which is the wrong shape for a thing four hundred units
     long and eighty tall and gets the case that matters (straight down
     onto the nose) exactly backwards.

     It is the fuselage part's own vertices, which are stored about its
     own pivot, put back where that pivot sits relative to the middle of
     the model — so the box is in the same frame everything else here
     is: x forward, y up, z to the right, about the point the aircraft
     turns about.
     ------------------------------------------------------------------ */
  const hull = (() => {
    const a = parts.fuselage.arrays.position, o = parts.fuselage.offset;
    const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < a.length; i += 3) for (let k = 0; k < 3; k++) {
      const v = a[i + k] + o[k];
      if (v < lo[k]) lo[k] = v;
      if (v > hi[k]) hi[k] = v;
    }
    return { lo, hi };
  })();

  /* the corners of the whole thing, about its middle, for the crash */
  const L = length, h = def.box.height, hw = def.box.half;
  const corners = [];
  for (const x of [-0.5, 0.5]) for (const y of [-hw, hw]) for (const z of [0, h]) corners.push([x * L, (z - h / 2) * L, -y * L]);

  return { parts, def, corners, hull, muzzle, lamp, S, length, centre, box: def.box };
}

/* =====================================================================
   A FLARE

   A screen-facing quad at a point in the world, sized as a fraction of
   its distance so it is the same size on the screen wherever it is.
   The shader draws two things into it: a horizontal STREAK, very wide
   and thin, the anamorphic flare a bright lamp puts across a lens, and
   a gradient SPHERE at the middle, white at the heart through the
   flare's colour to nothing. Additive, over everything, no depth —
   whoever owns it decides whether a wall is in the way.
   ===================================================================== */
const FLARE_VERT = /* glsl */`
attribute vec2 corner;
uniform vec3 centre;
uniform vec2 size;
varying vec2 vC;
void main() {
  vC = corner;
  vec4 mv = viewMatrix * vec4(centre, 1.0);
  /* BEHIND THE EYE IS NOWHERE. All four corners share one centre and
     are spread by its DISTANCE, which is what keeps the flare the same
     size on the screen wherever the lamp is — and which goes wrong the
     moment that distance is negative: the corners project through
     infinity and what lands on the screen is a white bowtie across the
     whole frame. It is culled on the way in as well (see Flare.render);
     this is the line that means a frame can never draw one anyway. */
  if (mv.z > -0.5) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
  mv.xy += corner * size * (-mv.z);
  gl_Position = projectionMatrix * mv;
}
`;
const FLARE_FRAG = /* glsl */`
uniform vec3  color;
uniform float glow;
uniform float aspect;      // width over height of the quad
uniform float ball;        // the sphere's radius, as a fraction of the height
varying vec2 vC;
void main() {
  /* the streak: sharp across, soft along, with a fainter wider band
     under it so it is a beam of light and not a line */
  float ax = abs(vC.x), ay = abs(vC.y);
  float along = pow(max(0.0, 1.0 - ax), 0.55);
  float streak = exp(-ay * 26.0) * along + exp(-ay * 6.0) * along * along * 0.16;
  /* the sphere: a radial gradient, white at the heart */
  vec2 q = vec2(vC.x * aspect, vC.y) / ball;
  float r = length(q);
  float sphere = exp(-r * r * 1.6) * 1.15 + exp(-r * 4.0) * 0.9;
  vec3 c = color * streak * 0.85 + mix(color, vec3(1.0), clamp(sphere * 0.55, 0.0, 1.0)) * sphere;
  /* and stepped, a little, because everything in this game is */
  c = floor(c * glow * 24.0 + 0.5) / 24.0;
  if (c.r + c.g + c.b < 0.02) discard;
  gl_FragColor = vec4(c, 1.0);
}
`;

/* HOW FAST A FLARE COMES AND GOES once the tests have changed their
   mind about it. Per FRAME rather than per tic, because a flare is not
   simulation — nothing downstream of it is, so nothing is made
   non-deterministic by it — and because what it is smoothing is a
   drawing artefact: a hard switch at a wall edge or as a wing crosses
   the lamp reads as the flare being broken rather than as the lamp
   going behind something. About a sixth of a second either way. */
const FLARE_EASE = 0.28;

export class Flare {
  constructor(color, size, ball) {
    this.color = color; this.size = size; this.ball = ball;
    this.glow = 0;
    this.vis = 0;               // 0 to 1, eased toward what the tests said
    this.x = 0; this.y = 0; this.z = 0;
    this.mesh = null;
  }
  attach(scene) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(12), 3));
    g.setAttribute('corner', new THREE.BufferAttribute(new Float32Array([-1, -1, 1, -1, 1, 1, -1, 1]), 2));
    g.setIndex(new THREE.BufferAttribute(new Uint16Array([0, 1, 2, 0, 2, 3]), 1));
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        centre: { value: new THREE.Vector3() }, size: { value: new THREE.Vector2(this.size[0], this.size[1]) },
        color: { value: new THREE.Vector3(this.color[0], this.color[1], this.color[2]) },
        glow: { value: 0 }, aspect: { value: this.size[0] / this.size[1] }, ball: { value: this.ball },
      },
      vertexShader: FLARE_VERT, fragmentShader: FLARE_FRAG,
      transparent: true, depthWrite: false, depthTest: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false, toneMapped: false,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 40;
    this.mesh.name = 'flare';
    this.mesh.visible = false;
    scene.add(this.mesh);
  }
  /** Put it at a game point with this much light, or take it away.
   *  `visible` is the owner's answer to "can this be seen from there at
   *  all" — a wall in the way, the aircraft's own hull in the way, the
   *  lamp behind the eye, the lamp off — and it is eased onto rather
   *  than switched to, for the reason at FLARE_EASE. */
  render(visible) {
    if (!this.mesh) return;
    const want = visible ? 1 : 0;
    this.vis += (want - this.vis) * FLARE_EASE;
    if (Math.abs(want - this.vis) < 0.01) this.vis = want;
    const glow = this.glow * this.vis;
    const on = glow > 0.01;
    this.mesh.visible = on;
    if (!on) return;
    const u = this.mesh.material.uniforms;
    u.centre.value.set(this.x, this.z, -this.y);
    u.glow.value = glow;
  }
  detach(scene) {
    if (!this.mesh) return;
    scene.remove(this.mesh);
    this.mesh.geometry.dispose(); this.mesh.material.dispose();
    this.mesh = null;
  }
}

/* =====================================================================
   ONE GUNSHIP
   ===================================================================== */
export class Gunship {
  /**
   * @param wing   the Gunships that sent it
   * @param model  from buildVtolModel
   * @param o      x, y, z, yaw to start at, and `station` to fly to
   */
  constructor(wing, model, o) {
    this.wing = wing;
    this.game = wing.game;
    this.model = model;
    this.def = model.def;
    this.texture = wing.texture;
    this.x = o.x; this.y = o.y; this.cz = o.z;
    this.vx = 0; this.vy = 0; this.vz = 0;
    this.yaw = o.yaw; this.yawV = 0;
    this.rx = 0; this.rz = 0;                 // roll about its length, pitch nose up
    this.ax = 0; this.ay = 0;                 // what it accelerated by, this tic
    this.tilt = VTOL.hover; this.tiltL = VTOL.hover; this.tiltR = VTOL.hover; this.tiltAux = VTOL.hover * VTOL.auxShare;
    this.vector = Math.PI / 2;      // where the jet is pointed: a hover
    this.aFwdS = 0; this.yawS = 0;  // the two smoothed inputs the angle is read off
    this.state = 'inbound';                   // inbound | station | dying | wreck
    this.mode = 'orbit';                      // orbit | torch, on station
    this.phase = rnd() * Math.PI * 2;         // where on the orbit
    this.torchAt = this.game.tics + VTOL.torchEvery;
    this.torchUntil = 0;
    this.torching = null;                     // the person it is over
    this.health = VTOL.health;
    this.shotArmour = VTOL.shotArmour;
    this.fireArmour = VTOL.fireArmour;
    this.hits = 0;
    /* the turret, relative to the body */
    this.tYaw = 0; this.tPitch = -0.35;
    this.spin = 0; this.spinV = 0;
    this.firing = 0; this.burstLeft = 0; this.pauseLeft = TICRATE;
    this.rounds = 0;
    this.lampOn = true;
    this.muzzleGlow = 0;
    this.loopHandle = null;
    this.noteTick = 0; this.note = 0;
    this.flash = 0;
    this.tick = 0;
    this.smoulder = 0;
    this.spinDir = 1;
    this.ground = 0;
    this.ignited = 0;                          // people the wash has lit, for the test
    this.washed = 0;
    /* scratch */
    this._near = [];
    this._muzzle = { x: 0, y: 0, z: 0 };
    this._lamp = { x: 0, y: 0, z: 0 };
    this._beam = { x: 0, y: 0, z: 0 };
    this._aim = { x: 0, y: 0, z: 0 };

    /* the thing you can shoot: three cylinders at its altitude, nose,
       middle and tail, each pointing back here */
    this.bodies = [];
    for (const [t, r] of [[0.28, 90], [0, 150], [-0.3, 90]]) {
      const a = this.game.spawn('AIRBODY', this.x, this.y, this.cz, { radius: r, height: this.def.box.height * this.def.length });
      a.vehicle = this;
      a.along = t * this.def.length;
      this.bodies.push(a);
    }
    this.blockers = [];

    /* the flares: the lamp's, massive, and the muzzle's, small */
    /* THE FLARE AT THE LAMP, and the user asked for a massive one: it
       is most of the frame across against a tenth of it high, which is
       an eight-to-one streak, with the gradient sphere at the middle of
       it. It was cut to two thirds of this for a while to stop it
       covering the sky, which turned out to be treating the symptom:
       what covered the sky was a lamp BEHIND the eye being sized by a
       negative distance, and with that fixed (see the guard in
       FLARE_VERT and the test in canBeSeen) the flare can be the size
       the user asked for. And the gun's, which is the same shader at a
       fifth the size and a warm colour — the small flare the user asked
       for in place of the muzzle flash. */
    this.lampFlare = new Flare([0.62, 0.78, 1.0], [0.88, 0.105], 0.38);
    this.muzzleFlare = new Flare([1.0, 0.72, 0.35], [0.17, 0.042], 0.55);

    this.parts = null;
    this.root = null;
    this.build();
    this.placeBodies();
  }

  /* ------------------------------------------------------------------
     The meshes
     ------------------------------------------------------------------ */
  build() {
    const g = this.game, M = this.model.parts;
    const mk = p => {
      const m = carMesh(this.texture, p.arrays);
      m.name = 'gunship:' + p.name;
      m.rotation.order = 'XYZ';
      m.position.set(p.offset[0], p.offset[1], p.offset[2]);
      return m;
    };
    const root = new THREE.Group();
    root.name = 'gunship';
    root.rotation.order = 'YXZ';
    const P = {};
    P.fuselage = mk(M.fuselage);
    P.turret = mk(M.turret);
    P.pitch = mk(M.pitch);
    P.gun = mk(M.gun);
    P.lamp = mk(M.lamp);
    P.nacelleL = mk(M.nacelleL);
    P.nacelleR = mk(M.nacelleR);
    P.aux = mk(M.aux);
    root.add(P.fuselage);
    P.fuselage.add(P.turret); P.fuselage.add(P.nacelleL); P.fuselage.add(P.nacelleR); P.fuselage.add(P.aux);
    P.turret.add(P.pitch);
    P.pitch.add(P.gun); P.pitch.add(P.lamp);
    g.scene.add(root);
    this.parts = P;
    this.root = root;
    this.lampFlare.attach(g.scene); this.muzzleFlare.attach(g.scene);
    this.place();
  }

  /** Every part's position and turn, from the numbers. */
  place() {
    const P = this.parts;
    this.root.position.set(this.x, this.cz, -this.y);
    this.root.rotation.set(this.rx, this.yaw, this.rz);
    P.turret.rotation.set(0, this.tYaw, 0);
    P.pitch.rotation.set(0, 0, this.tPitch);
    P.gun.rotation.set(this.spin, 0, 0);
    /* A POD TILTED NOSE-UP POINTS ITS NOZZLE DOWN, which is a POSITIVE
       turn about the part's z — z points right, and a positive turn
       about it takes forward toward up. It was negative, which drew the
       pods nose-DOWN as the thing accelerated and left them level in a
       hover: the two things the user saw as inverted. Level is CRUISE
       on this airframe; a hover is nose-up. */
    P.nacelleL.rotation.set(0, 0, this.tiltL);
    P.nacelleR.rotation.set(0, 0, this.tiltR);
    P.aux.rotation.set(0, 0, this.tiltAux);
  }

  /** A point in a part's frame, up the chain into the AIRCRAFT's own
   *  frame — x forward, y up, z right, about the point it turns about.
   *  `chain` is the parts from the root down to the one the point is
   *  in; each adds its offset and turns by what it is turned by. This
   *  is where the hull box lives, so the occlusion test stops here. */
  bodyOf(p, chain) {
    const M = this.model.parts;
    let q = p;
    for (let i = chain.length - 1; i >= 0; i--) {
      const name = chain[i];
      if (name === 'gun') q = add([q[0], q[1] * Math.cos(this.spin) - q[2] * Math.sin(this.spin), q[1] * Math.sin(this.spin) + q[2] * Math.cos(this.spin)], M.gun.offset);
      else if (name === 'lamp') q = add(q, M.lamp.offset);
      else if (name === 'pitch') q = add(rotZ(q, this.tPitch), M.pitch.offset);
      else if (name === 'turret') q = add(rotY(q, this.tYaw), M.turret.offset);
      else if (name === 'nacelleL') q = add(rotZ(q, this.tiltL), M.nacelleL.offset);
      else if (name === 'nacelleR') q = add(rotZ(q, this.tiltR), M.nacelleR.offset);
      else if (name === 'aux') q = add(rotZ(q, this.tiltAux), M.aux.offset);
      else if (name === 'fuselage') q = add(q, M.fuselage.offset);
    }
    return q;
  }

  /** And the rest of the way out: into the world, in GAME coordinates. */
  worldOf(p, chain) {
    const w = turn(this.bodyOf(p, chain), this.yaw, this.rx, this.rz);
    return { x: this.x + w[0], y: this.y - w[2], z: this.cz + w[1] };
  }

  /** A world point in GAME coordinates, back into the aircraft's frame.
   *  The other direction of worldOf, and what the eye goes through. */
  bodyPoint(x, y, z, out = [0, 0, 0]) {
    const w = unturn([x - this.x, z - this.cz, -(y - this.y)], this.yaw, this.rx, this.rz);
    out[0] = w[0]; out[1] = w[1]; out[2] = w[2];
    return out;
  }

  /** IS THE AIRCRAFT'S OWN BODY IN THE WAY of a point on it, seen from
   *  the eye? The lamp hangs under the nose and the muzzle sticks out
   *  in front of it, so the answer is yes for most of the sky it flies
   *  in — above it and behind it — and that is the whole reason the
   *  test exists. `chain` and `p` name the point in the model, so the
   *  turret's own yaw and pitch are in the answer.
   *
   *  A wreck has no hull worth asking about: it is lying on the tarmac
   *  in pieces and its lamp is out anyway. */
  hullHides(ex, ey, ez, p, chain) {
    const E = this.bodyPoint(ex, ey, ez, this._eyeBody || (this._eyeBody = [0, 0, 0]));
    const B = this.bodyOf(p, chain);
    return boxBetween(E, B, this.model.hull, VTOL.lamp.hullClear);
  }
  /** A direction, the same way, without the offsets. */
  dirOf(d, chain) {
    let q = d;
    for (let i = chain.length - 1; i >= 0; i--) {
      const name = chain[i];
      if (name === 'pitch') q = rotZ(q, this.tPitch);
      else if (name === 'turret') q = rotY(q, this.tYaw);
      else if (name === 'nacelleL') q = rotZ(q, this.tiltL);
      else if (name === 'nacelleR') q = rotZ(q, this.tiltR);
      else if (name === 'aux') q = rotZ(q, this.tiltAux);
    }
    const w = turn(q, this.yaw, this.rx, this.rz);
    const l = Math.hypot(w[0], w[1], w[2]) || 1;
    return { x: w[0] / l, y: -w[2] / l, z: w[1] / l };
  }

  get muzzle() { const m = this.worldOf(this.model.muzzle, MUZZLE_CHAIN); this._muzzle.x = m.x; this._muzzle.y = m.y; this._muzzle.z = m.z; return this._muzzle; }
  get lamp() { const m = this.worldOf(this.model.lamp, LAMP_CHAIN); this._lamp.x = m.x; this._lamp.y = m.y; this._lamp.z = m.z; return this._lamp; }
  /** Which way the gun and the lamp point. */
  get beam() { const d = this.dirOf([1, 0, 0], AIM_CHAIN); this._beam.x = d.x; this._beam.y = d.y; this._beam.z = d.z; return this._beam; }

  /* ------------------------------------------------------------------
     What can happen to it
     ------------------------------------------------------------------ */
  get whole() { return this.state === 'inbound' || this.state === 'station'; }
  get flying() { return this.whole || this.state === 'dying'; }
  get altitude() { return this.cz - this.ground; }

  placeBodies() {
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    const belly = this.cz - this.def.box.height * this.def.length / 2;
    for (const a of this.bodies) {
      a.x = this.x + c * a.along; a.y = this.y + s * a.along; a.z = belly;
    }
    this.bodies[1].sector = this.game.level.sectorAt(this.x, this.y);
  }

  damage(n, source = null, opts = {}) {
    if (!this.whole) return;
    if (opts.stream) return;                        // fire cannot reach it
    if (source && source.vehicle === this) return;  // its own rounds, with the turret slewed round
    if (opts.fire) n /= this.fireArmour;
    if (opts.shot) n /= this.shotArmour;
    this.health -= n;
    this.hits++;
    if (opts.shot && (this.hits & 3) === 0) this.game.fx?.ember(this.x, this.y, this.cz - 20, 2, 1);
    if (this.health <= 0) this.shotDown(source);
  }
  ignite() { /* nothing on fire reaches it while it flies; on the ground it is already burning */ }

  /* ------------------------------------------------------------------
     One tic
     ------------------------------------------------------------------ */
  tic() {
    this.tick++;
    if (this.flash > 0) { this.game.fx?.glowAt(this.x, this.y, 7 * (this.flash / 40)); this.flash--; }
    if (this.state === 'wreck') { this.smoulderTic(); return; }
    if (this.state === 'dying') { this.fallTic(); return; }
    this.fly();
    this.turretTic();
    this.gunTic();
    this.washTic();
    this.placeBodies();
    this.place();
    /* the turbines, two notes on their own clock */
    if (++this.noteTick >= 30) {
      this.noteTick = 0;
      this.game.sound?.play(this.note ? 'gunship2' : 'gunship', this);
      this.note ^= 1;
    }
  }

  /* ---- where it wants to be ------------------------------------------ */
  station() {
    const g = this.game, R = g.responders, p = g.player;
    const out = this._aim;
    /* over people, for a while, if it has found some — and it WALKS
       ACROSS A CROWD rather than following one person: the moment the
       one it is over is alight (or dead, or gone) it takes the next
       nearest, so a pass is several of them rather than a chase after a
       runner it cannot keep up with. */
    if (this.mode === 'torch' && g.tics < this.torchUntil) {
      const t = this.torching;
      if (!t || t.removed || t.dead || t.burning > 0) this.torching = this.findCrowd();
      if (this.torching) { out.x = this.torching.x; out.y = this.torching.y; out.z = -1; return out; }
    }
    if (this.mode === 'torch') { this.mode = 'orbit'; this.torching = null; this.torchAt = g.tics + VTOL.torchEvery; }
    if (this.state === 'station' && g.tics >= this.torchAt && !p?.dead) {
      const t = this.findCrowd();
      if (t) { this.mode = 'torch'; this.torching = t; this.torchUntil = g.tics + VTOL.torchFor; out.x = t.x; out.y = t.y; out.z = -1; return out; }
      this.torchAt = g.tics + VTOL.torchEvery / 2;
    }
    /* the orbit round you, outdoors; the fire lane if you are in */
    if (R?.chasing && p) {
      this.phase += VTOL.orbit;
      out.x = p.x + Math.cos(this.phase) * VTOL.standoff;
      out.y = p.y + Math.sin(this.phase) * VTOL.standoff;
    } else {
      const d = R?.doorsPoint?.() || (p ? { x: p.x, y: p.y - 700 } : { x: 0, y: 0 });
      this.phase += VTOL.orbit * 0.8;
      out.x = d.x + Math.sin(this.phase) * 620;
      out.y = d.y - 480 - Math.cos(this.phase * 2) * 140;
    }
    out.z = -1;
    return out;
  }

  /** Somebody to hover over: the nearest person in the open, within
   *  reach, whole and not already alight.
   *
   *  OFF THE BLOCKMAP rather than out of the cast list. It used to take
   *  forty of the eight hundred at random and pick the nearest of
   *  those, which is cheap and is also a coin toss — with two dozen
   *  people standing directly underneath it, a sample of forty finds
   *  one of them about half the time, so the aircraft would fly over a
   *  crowd and decide there was nobody there. The blockmap answers the
   *  question it is actually being asked, and this is asked once every
   *  few seconds rather than every tic. */
  findCrowd() {
    const g = this.game;
    if (!g.blockmap) return null;
    const near = g.blockmap.nearRadius(this.x, this.y, VTOL.torchReach, this._near);
    let best = null, bd = VTOL.torchReach * VTOL.torchReach;
    for (let i = 0; i < near.length; i++) {
      const a = near[i];
      if (a.dead || a.removed || !a.flammable || a.vehicle || a.burning > 0 || !a.monster) continue;
      const s = a.sector || g.level.sectorAt(a.x, a.y);
      if (!s || !s.outdoor) continue;
      const d = dist2(a.x, a.y, this.x, this.y);
      if (d < bd) { bd = d; best = a; }
    }
    return best;
  }

  /** Is this bit of ground somewhere it can fly low over? Open sky, and
   *  not the building. */
  openAt(x, y) {
    const s = this.game.level.sectorAt(x, y);
    return !!s && !!s.outdoor && s.ceilTex === 'SKY';
  }

  fly() {
    const g = this.game, p = g.player;
    const want = this.station();
    /* ---- the plan: a speed toward the point, capped ---------------- */
    const dx = want.x - this.x, dy = want.y - this.y;
    const dist = Math.hypot(dx, dy) || 1;
    const wantSpeed = Math.min(VTOL.speed, dist * 0.045);
    const wvx = dx / dist * wantSpeed, wvy = dy / dist * wantSpeed;
    let ax = wvx - this.vx, ay = wvy - this.vy;
    const am = Math.hypot(ax, ay);
    if (am > VTOL.accel) { ax *= VTOL.accel / am; ay *= VTOL.accel / am; }
    this.ax = ax; this.ay = ay;
    this.vx += ax; this.vy += ay;
    this.x += this.vx; this.y += this.vy;
    if (this.state === 'inbound' && dist < VTOL.arrive) this.state = 'station';

    /* ---- the height: over open ground it comes down; over the
       building, or heading for it, it clears the parapet ------------ */
    const s = g.level.sectorAt(this.x, this.y);
    this.ground = s ? s.floor : 0;
    const look = 26;
    const open = this.openAt(this.x, this.y) && this.openAt(this.x + this.vx * look, this.y + this.vy * look);
    const alt = this.mode === 'torch' ? VTOL.lowAlt : VTOL.alt;
    const wantZ = open ? this.ground + alt : VTOL.roofAlt;
    /* a spring on the height, damped just short of critical: it comes
       down onto a new altitude in a couple of seconds and settles,
       rather than sagging onto it over ten — which matters because the
       whole of the torch run is the seconds it spends low */
    let az = (wantZ - this.cz) * 0.005 - this.vz * 0.125;
    az = clamp(az, -VTOL.climb, VTOL.climb);
    this.vz += az;
    this.cz += this.vz;

    /* ---- the heading: the way it is going, or at you --------------- */
    const speed = Math.hypot(this.vx, this.vy);
    let wantYaw = this.yaw;
    if (speed > 5) wantYaw = Math.atan2(this.vy, this.vx);
    else if (p && !p.dead) wantYaw = Math.atan2(p.y - this.y, p.x - this.x);
    const err = angleDiff(wantYaw, this.yaw);
    this.yawV += (err * 0.09 - this.yawV * 0.28);
    this.yawV = clamp(this.yawV, -VTOL.turn, VTOL.turn);
    this.yaw += this.yawV;

    /* ---- and what the airframe does about all that ----------------- */
    const c = Math.cos(this.yaw), sn = Math.sin(this.yaw);
    const aFwd = ax * c + ay * sn, aLat = -ax * sn + ay * c;
    const vFwd = this.vx * c + this.vy * sn;
    /* WHERE THE JET IS POINTED. Lift holds the weight plus whatever the
       climb is asking for; the forward component is the acceleration
       plus the drag it is already pushing against at this speed. The
       angle between them is measured UP FROM LEVEL, so a hover is a
       right angle and speed flattens it — see the block at VTOL.hover
       for why that is the way round it is, and why the pod is drawn at
       a share of it rather than at it.

       THE ACCELERATION IS LOW-PASSED FIRST, and that is not tidiness.
       `aFwd` is a controller output: it saturates against VTOL.accel,
       comes off the cap the moment the error shrinks, and steps again
       at every corner. Reading an angle straight off it put every one
       of those steps into the drawing. */
    this.aFwdS += (aFwd - this.aFwdS) * VTOL.accelSmooth;
    const lift = Math.max(0.25, VTOL.weight + az);
    const fwd = this.aFwdS * VTOL.accelGain + vFwd * VTOL.dragGain;
    this.vector = clamp(Math.atan2(lift, fwd), VTOL.vectorMin, VTOL.vectorMax);
    /* and where the POD is drawn: the hover angle, moved by a geared
       share of however far the jet is from a hover */
    const wantTilt = clamp(VTOL.hover + VTOL.gear * (this.vector - Math.PI / 2),
                           VTOL.tiltMin, VTOL.tiltMax);
    /* ONE POD UP AND ONE DOWN TO YAW, off the turn rate smoothed for
       the same reason the acceleration is: the heading is a damped
       spring and it rings, and a differential read straight off it rang
       with it. */
    this.yawS += (this.yawV - this.yawS) * 0.12;
    const diff = clamp(this.yawS * VTOL.diffGain, -VTOL.diffMax, VTOL.diffMax);
    /* and the actuators, which is where the jangle went: the pods move
       at a RATE, so a demand that jumps is a pod that does not */
    this.tiltL = slew(this.tiltL, wantTilt + diff, VTOL.tiltRate);
    this.tiltR = slew(this.tiltR, wantTilt - diff, VTOL.tiltRate);
    this.tilt = (this.tiltL + this.tiltR) / 2;
    /* the tail engine: most of their angle, and it LEADS the pitch —
       what a tail does */
    this.tiltAux = slew(this.tiltAux, clamp(wantTilt * VTOL.auxShare - this.aFwdS * 0.8, VTOL.tiltMin, VTOL.tiltMax), VTOL.tiltRate);
    /* THE BODY answers the ACCELERATION rather than the pod angle, and
       that is the other half of what looked wrong: hung off the pod, it
       sat nine degrees nose-down for the whole of a hover, because a
       hovering pod is not at zero. Nose down to go, nose up to stop,
       banked INTO the turn since it is held up by thrust and not by
       springs, and never quite still, on two slow sines like the APC. */
    const idle = Math.sin(this.tick * 0.031) * 0.012;
    const idleR = Math.sin(this.tick * 0.023 + 1.3) * 0.016;
    const wantPitch = clamp(-this.aFwdS * 1.6, -0.16, 0.16) + idle;
    const wantRoll = -clamp(this.yawS * 4.5 + aLat * 0.5, -0.42, 0.42) + idleR;
    this.rz += (wantPitch - this.rz) * 0.12;
    this.rx += (wantRoll - this.rx) * 0.10;
  }

  /* ---- the turret ----------------------------------------------------- */
  /** You, if the gun can see you: the muzzle to your eye, no wall
   *  between and inside the range. */
  canSeePlayer() {
    const p = this.game.player;
    if (!p || p.dead) return false;
    const m = this.muzzle;
    if (dist2(m.x, m.y, p.x, p.y) > VTOL.gun.range * VTOL.gun.range) return false;
    return !this.game.level.sightBlocked(m.x, m.y, m.z, p.x, p.y, p.eyeZ);
  }

  turretTic() {
    const g = this.game, p = g.player, G = VTOL.gun;
    this.seen = this.canSeePlayer();
    let wantYaw, wantPitch;
    if (this.seen) {
      const m = this.muzzle;
      const dx = p.x - m.x, dy = p.y - m.y, dz = (p.eyeZ - 8) - m.z;
      wantYaw = angleDiff(Math.atan2(dy, dx), this.yaw);
      wantPitch = Math.atan2(dz, Math.hypot(dx, dy));
    } else {
      /* searching: the beam sweeps ahead and down */
      wantYaw = Math.sin(this.tick * 0.012) * 0.7;
      wantPitch = -0.55 + Math.sin(this.tick * 0.017) * 0.15;
    }
    /* the turret takes the body's own roll and pitch out as best it
       can: what it is asked for is an absolute direction */
    wantPitch -= this.rz;
    wantYaw = clamp(wantYaw, -G.yawLimit, G.yawLimit);
    wantPitch = clamp(wantPitch, G.pitch[0], G.pitch[1]);
    const ey = angleDiff(wantYaw, this.tYaw), ep = wantPitch - this.tPitch;
    this.tYaw += clamp(ey * 0.35, -G.slew, G.slew);
    this.tPitch += clamp(ep * 0.35, -G.slew, G.slew);
    this.aimed = this.seen && Math.abs(ey) < G.aim && Math.abs(ep) < G.aim;
    /* the barrels */
    this.spinV += ((this.firing ? 0.55 : 0) - this.spinV) * (this.firing ? 0.12 : 0.04);
    this.spin += this.spinV;
  }

  gunTic() {
    const g = this.game, G = VTOL.gun;
    if (this.pauseLeft > 0) this.pauseLeft--;
    if (!this.firing) {
      if (this.aimed && this.pauseLeft <= 0) {
        this.firing = 1; this.burstLeft = G.burst;
        this.loopHandle = g.sound?.loop?.('minigunloop', this) || null;
      }
    }
    if (!this.firing) { this.muzzleGlow *= 0.6; return; }
    /* stop when the burst is spent or you are gone */
    if (this.burstLeft <= 0 || !this.seen) {
      this.firing = 0; this.pauseLeft = G.pause;
      if (this.loopHandle) { this.loopHandle.stop(); this.loopHandle = null; g.sound?.play('spindown', this); }
      this.muzzleGlow *= 0.6;
      return;
    }
    this.burstLeft--;
    const m = this.muzzle;
    const from = { x: m.x, y: m.y, z: m.z };
    const shooter = this.bodies[1];
    for (let k = 0; k < G.rounds; k++) {
      const yaw = this.yaw + this.tYaw + (rnd() - 0.5) * 2 * G.spread;
      const pitch = this.tPitch + this.rz + (rnd() - 0.5) * 2 * G.spread * 0.7;
      const dmg = Math.round(between(G.damage));
      g.hitscan(shooter, yaw, G.range, dmg, { shot: true, hot: true, pitch, from });
      if (g.tracers && g.lastHit) g.tracers.spawn(from, g.lastHit);
      this.rounds++;
    }
    g.sound?.play('vulcan', this);
    this.muzzleGlow = 0.75 + rnd() * 0.5;
    g.fx?.glowAt(m.x, m.y, 1.5);
  }

  /* ---- the exhaust ---------------------------------------------------- */
  /** Where one engine's exhaust lands: down its ray to the ground, or a
   *  wall on the way, or the roof of a car under it. */
  exhaustHit(origin, dir, out) {
    const g = this.game, lv = g.level;
    if (dir.z >= -0.05) return false;
    const t = (origin.z - this.ground) / -dir.z;
    out.x = origin.x + dir.x * t; out.y = origin.y + dir.y * t; out.z = this.ground;
    out.nx = 0; out.ny = 0; out.nz = 1; out.t = t;
    const s = lv.sectorAt(out.x, out.y);
    if (s) { out.z = s.floor; }
    const wall = lv.rayHitWall(origin.x, origin.y, origin.z, out.x, out.y, out.z);
    if (wall) {
      out.x = wall.x; out.y = wall.y; out.z = wall.z;
      const ddx = wall.line.x2 - wall.line.x1, ddy = wall.line.y2 - wall.line.y1, l = Math.hypot(ddx, ddy) || 1;
      let nx = ddy / l, ny = -ddx / l;
      if (nx * (origin.x - wall.x) + ny * (origin.y - wall.y) < 0) { nx = -nx; ny = -ny; }
      out.nx = nx; out.ny = ny; out.nz = 0; out.t = t * wall.t;
      return true;
    }
    /* a car under it: the wash lands on its roof */
    const near = g.blockmap?.nearRadius(out.x, out.y, 80, this._near) || [];
    for (let i = 0; i < near.length; i++) {
      const a = near[i];
      if (!a.vehicle || a.removed || !a.solid) continue;
      if (dist2(a.x, a.y, out.x, out.y) > (a.radius + 10) * (a.radius + 10)) continue;
      out.z = Math.max(out.z, a.z + a.height);
      break;
    }
    return true;
  }

  washTic() {
    const g = this.game, W = VTOL.wash;
    if (this.tick % W.every) return;
    const M = this.model.parts;
    const hit = this._hit || (this._hit = { x: 0, y: 0, z: 0, nx: 0, ny: 0, nz: 1, t: 0 });
    const engines = [['nacelleL', this.tiltL], ['nacelleR', this.tiltR], ['aux', this.tiltAux]];
    const which = engines[(this.tick / W.every | 0) % 3];
    const [name] = which;
    /* out of the pod's own nozzle, which swings with it — and down the
       way the JET is pointed rather than the way the pod is DRAWN.
       Those are two angles on this airframe (see VTOL.hover): the pod
       shows a geared share and the nozzle inside it carries the rest,
       which is why a hover puts the wash straight underneath and speed
       streams it aft. */
    const origin = this.worldOf(name === 'aux' ? AUX_NOZZLE : POD_NOZZLE, ['fuselage', name]);
    const dir = this.dirOf([-Math.cos(this.vector), -Math.sin(this.vector), 0], ['fuselage']);
    if (!this.exhaustHit(origin, dir, hit)) return;
    /* NOTHING FROM UP THERE. An aircraft at six hundred units does not
       blow the car park about, and a puff a tic from one that is only
       passing over is the smoke pool spent on nothing. */
    if (hit.t > W.reach) return;
    const k = clamp(1 - hit.t / W.reach, 0.15, 1) * (name === 'aux' ? 0.6 : 1);
    g.fx?.wash(hit.x, hit.y, hit.z, k, hit.nx, hit.ny, hit.nz);
    if (k > 0.55) g.fx?.wash(hit.x, hit.y, hit.z, k, hit.nx, hit.ny, hit.nz);
    this.washed++;
    /* AND IT IS HOT, near the ground: the people under it catch. People
       and not vehicles, at the user's request: it is the person that is
       lit, never the floor under them, which is the call that would
       light a car. */
    if (hit.t > W.hot || hit.nz < 0.5) return;
    const near = g.blockmap?.nearRadius(hit.x, hit.y, W.radius, this._near) || [];
    const r2 = W.radius * W.radius;
    for (let i = 0; i < near.length; i++) {
      const a = near[i];
      if (a.dead || a.removed || !a.flammable || a.vehicle || a.burning > 0) continue;
      if (dist2(a.x, a.y, hit.x, hit.y) > r2) continue;
      a.ignite(Math.round(between(W.ignite)));
      this.ignited++;
    }
    if (this.tick % W.scareEvery === 0) g.scare?.(hit.x, hit.y, W.scare);
  }

  /* ------------------------------------------------------------------
     GOING DOWN
     ------------------------------------------------------------------ */
  shotDown(source = null) {
    if (!this.whole) return;
    const g = this.game;
    this.state = 'dying';
    this.mode = 'orbit';
    this.firing = 0;
    if (this.loopHandle) { this.loopHandle.stop(); this.loopHandle = null; }
    /* THE BANG IN THE AIR: the sound, a dozen fireballs over the
       airframe, a cloud of sparks, smoke, the light of it thrown over
       the whole lot for a second, pieces of the skin flung off, and
       everybody under it leaving */
    g.sound?.play('shipdie', this);
    const L = this.def.length;
    for (let k = 0; k < 14; k++) {
      const p = this.worldOf([(rnd() - 0.5) * L * 0.8, (rnd() - 0.5) * 40, (rnd() - 0.5) * L * 0.5], ['fuselage']);
      g.fx?.fireball(p.x, p.y, p.z, 70 + rnd() * 90, 20 + (pRandom() % 14));
    }
    for (let k = 0; k < 5; k++) {
      const p = this.worldOf([(rnd() - 0.5) * L * 0.6, 0, (rnd() - 0.5) * L * 0.4], ['fuselage']);
      g.spawn('BLAST', p.x, p.y, p.z - 40);
    }
    g.fx?.ember(this.x, this.y, this.cz, 60, 1.4);
    for (let k = 0; k < 12; k++) g.fx?.puff(this.x + (rnd() - 0.5) * L * 0.6, this.y + (rnd() - 0.5) * L * 0.6, this.cz + (rnd() - 0.5) * 60, 40, 220);
    this.flash = 40;
    g.scare?.(this.x, this.y, 1600);
    this.shed(10);
    /* what is left of the engines: thrown to nothing, one dead */
    this.deadEngine = pRandom() & 1;
    this.spinDir = (pRandom() & 1) ? 1 : -1;
    this.spinK = 0;
    /* THE LURCH. What is left of the lift goes into it as it is hit —
       the nose comes up, it rises for a moment and then stops rising,
       which is the half-second that makes a fall read as a thing losing
       its lift rather than as a thing being switched off. */
    this.vz = Math.max(this.vz, 0) + VTOL.lurch;
    this.pops = 0;
    this.lampFlicker = 1;
    g.onResponders?.('gunship-down', this, source);
  }

  /** THE TAIL SPIN. Still flying, in the sense that the air is still
   *  under it: the yaw winds up to a full spin, the nose goes down, it
   *  rolls with the spin, the lift is mostly gone so it falls under a
   *  third of the gravity a car does, and it trails fire and smoke and
   *  pops all the way down. */
  fallTic() {
    const g = this.game, L = this.def.length;
    this.spinK = Math.min(1, this.spinK + 1 / 40);
    this.yawV = VTOL.spin * this.spinK * this.spinDir;
    this.yaw += this.yawV;
    this.rz += (-0.62 - this.rz) * 0.03 + Math.sin(this.tick * 0.21) * 0.006;
    this.rx += (this.spinDir * 0.55 * this.spinK - this.rx) * 0.04 + Math.sin(this.tick * 0.17) * 0.01;
    this.vz -= VTOL.gravity;
    this.vx *= 0.992; this.vy *= 0.992;
    this.x += this.vx; this.y += this.vy; this.cz += this.vz;
    /* the engines: one jammed hard over, one gone slack, the tail
       stuck wherever it was when the drive went. No rate limit on the
       way there any more — nothing is driving them, they are falling
       to their stops. */
    this.tiltL += (((this.deadEngine ? VTOL.tiltMax : VTOL.tiltMin)) - this.tiltL) * 0.05;
    this.tiltR += (((this.deadEngine ? VTOL.tiltMin : VTOL.tiltMax)) - this.tiltR) * 0.05;
    this.tiltAux += (VTOL.tiltMax * 0.9 - this.tiltAux) * 0.04;
    /* the turret is nobody's now: it slews with the spin */
    this.tYaw += 0.02 * this.spinDir; this.tPitch += (-0.9 - this.tPitch) * 0.02;
    this.spin += this.spinV; this.spinV *= 0.97;
    /* the trail */
    const fx = g.fx;
    if (fx) {
      const p = this.worldOf([(rnd() - 0.5) * L * 0.7, 0, (rnd() - 0.5) * L * 0.35], ['fuselage']);
      fx.fireball(p.x, p.y, p.z, 40 + rnd() * 50, 14);
      if ((this.tick & 1) === 0) fx.puff(p.x, p.y, p.z + 10, 36, 200);
      fx.ember(p.x, p.y, p.z, 2, 1.2);
      fx.glowAt(this.x, this.y, 3);
      if ((this.tick % 12) === 0) {
        const q = this.worldOf([(rnd() - 0.5) * L * 0.5, 0, (rnd() - 0.5) * L * 0.3], ['fuselage']);
        g.spawn('BLAST', q.x, q.y, q.z - 40);
        g.sound?.play('explode', this);
        this.pops++;
      }
    }
    this.lampFlicker = rnd() < 0.25 ? rnd() : 1;
    this.muzzleGlow *= 0.7;
    const s = g.level.sectorAt(this.x, this.y);
    this.ground = s ? s.floor : 0;
    const low = lowestOf(this.model.corners, this.rx, this.rz);
    if (this.vz < 0 && this.cz + low <= this.ground) { this.crash(); return; }
    this.placeBodies();
    this.place();
  }

  /** THE GROUND. The bigger bang, on the tarmac this time — it hurts,
   *  it lights the floor, it throws pieces — and then it lies there. */
  crash() {
    const g = this.game, L = this.def.length;
    this.state = 'wreck';
    this.lampOn = false;
    /* AND IT TAKES THE BUILDING WITH IT. This is the biggest bang in
       the game by a factor of three and the only one that arrives from
       the sky, so it is the one that is allowed to flatten what it lands
       on outright: `structure` past one puts every region under it
       straight through charred, gutted and down in the same tic. See
       damageStructure in js/fire.js. */
    g.explode({ x: this.x, y: this.y, z: this.ground },
      { radius: 460, damage: 170, heat: 255, heatRadius: 190, ignite: 420, sound: 'bigboom',
        structure: 1.35, structureRadius: 560 });
    g.sound?.play('shipdie', this);
    for (let k = 0; k < 8; k++) {
      const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
      const t = (rnd() - 0.5) * L * 0.9, u = (rnd() - 0.5) * L * 0.5;
      g.spawn('BLAST', this.x + c * t - s * u, this.y + s * t + c * u, this.ground);
    }
    for (let k = 0; k < 18; k++) g.fx?.fireball(this.x + (rnd() - 0.5) * L * 0.9, this.y + (rnd() - 0.5) * L * 0.6, this.ground + 30 + rnd() * 80, 90 + rnd() * 110, 26);
    g.fx?.ember(this.x, this.y, this.ground + 20, 80, 1.4);
    for (let k = 0; k < 16; k++) g.fx?.puff(this.x + (rnd() - 0.5) * L, this.y + (rnd() - 0.5) * L * 0.7, this.ground + 24 + (k % 7) * 8, 44, 240);
    this.flash = 40;
    g.scare?.(this.x, this.y, 2000);
    g.fire?.ignite(this.x, this.y, 520, 130);
    /* it comes to rest crooked, on whatever is under it */
    this.rx = (rnd() - 0.5) * 0.5;
    this.rz = (rnd() - 0.5) * 0.36;
    this.vx = this.vy = this.vz = 0; this.yawV = 0;
    this.cz = this.ground - lowestOf(this.model.corners, this.rx, this.rz);
    this.shed(14);
    /* burnt, from here on: the coals and the dark, on every part */
    for (const m of Object.values(this.parts)) {
      const geo = m.geometry;
      const ch = geo.getAttribute('charred'), lt = geo.getAttribute('light');
      if (ch) { ch.array.fill(1); ch.needsUpdate = true; }
      if (lt) { for (let i = 0; i < lt.array.length; i++) lt.array[i] *= 0.42; lt.needsUpdate = true; }
    }
    /* the thing in the air is gone; the thing on the ground is in the way */
    for (const a of this.bodies) a.remove();
    this.bodies.length = 0;
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    for (const t of [-0.3, 0, 0.3]) {
      const a = g.spawn('CARBODY', this.x + c * t * L, this.y + s * t * L, this.ground, {
        radius: 110, height: Math.max(16, Math.round(extentOf(this.model.corners, this.rx, this.rz).hi + this.cz - this.ground)),
      });
      a.vehicle = this;
      this.blockers.push(a);
    }
    this.smoulder = VTOL.smoulder;
    this.place();
    g.onResponders?.('gunship-crashed', this);
  }

  smoulderTic() {
    if (this.smoulder <= 0) return;
    this.smoulder--;
    const g = this.game, k = this.smoulder / VTOL.smoulder, L = this.def.length;
    if ((this.tick % 4) === 0) g.fx?.ember(this.x + (rnd() - 0.5) * L * 0.6, this.y + (rnd() - 0.5) * L * 0.4, this.cz + 10, 1, 0.4 + 0.8 * k);
    if ((this.tick % 7) === 0) g.fx?.puff(this.x + (rnd() - 0.5) * L * 0.6, this.y + (rnd() - 0.5) * L * 0.4, this.cz + 20, 30 + 20 * k, 220);
    if ((this.tick % 9) === 0 && k > 0.3) g.fx?.fireball(this.x + (rnd() - 0.5) * L * 0.5, this.y + (rnd() - 0.5) * L * 0.3, this.cz + 10, 30 + 40 * k, 16);
    if ((this.tick % 70) === 0 && k > 0.3) g.fire?.ignite(this.x, this.y, 90, 60);
    g.fx?.glowAt(this.x, this.y, 0.6 + 2 * k);
  }

  /** Pieces off the skin: the vehicles' own Chunk, cut from this model,
   *  thrown from where they were on the airframe with its speed. */
  shed(n) {
    const g = this.game, fleet = g.vehicles, d = this.def, L = d.length;
    if (!fleet) return;
    const tris = d.model.tris;
    const mid = [0, 0, d.box.height / 2];
    for (let k = 0; k < n; k++) {
      if (fleet.flying.length >= 64) return;
      const pick = tris[Math.min(tris.length - 1, (rnd() * tris.length) | 0)];
      const px = (pick.a[0] + pick.b[0] + pick.c[0]) / 3, py = (pick.a[1] + pick.b[1] + pick.c[1]) / 3, pz = (pick.a[2] + pick.b[2] + pick.c[2]) / 3;
      const w = 0.05 + rnd() * 0.09, dp = 0.05 + rnd() * 0.09, t = 0.04 + rnd() * 0.08;
      const cut = { x0: px - w / 2, x1: px + w / 2, y0: py - dp / 2, y1: py + dp / 2, z0: Math.max(0, pz - t / 2) };
      cut.z1 = cut.z0 + t;
      const cm = [(cut.x0 + cut.x1) / 2, (cut.y0 + cut.y1) / 2, (cut.z0 + cut.z1) / 2];
      const off = turn([(cm[0] - mid[0]) * L, (cm[2] - mid[2]) * L, -(cm[1] - mid[1]) * L], this.yaw, this.rx, this.rz);
      const wx = this.x + off[0], wy = this.y - off[2], wz = this.cz + off[1];
      const a = Math.atan2(wy - this.y, wx - this.x) + (rnd() - 0.5) * 1.4;
      const sp = 2 + rnd() * 6;
      fleet.addChunk(new Chunk(fleet, d, cut, {
        x: wx, y: wy, z: wz, ground: this.ground,
        vx: Math.cos(a) * sp + this.vx * 0.6, vy: Math.sin(a) * sp + this.vy * 0.6,
        vz: 2 + rnd() * 9 + Math.max(0, this.vz) * 0.3,
        light: 0.74, sky: 1, paint: [1, 1, 1], texture: this.texture,
      }));
    }
  }

  /* ------------------------------------------------------------------
     Drawing: the flares, and whether the lamp is the one lighting the
     world this frame
     ------------------------------------------------------------------ */
  render(ex, ey, ez, vdx = 0, vdy = 0) {
    const g = this.game;
    if (!this.root) return;
    this.place();
    /* HOW BRIGHT THE LAMP IS FROM HERE: full looking straight into the
       reflector, a dim glint from off to the side, nothing from behind
       it. `into` is how nearly the line from the lamp to your eye runs
       back up the beam. */
    const lamp = this.lamp, beam = this.beam;
    const vx = ex - lamp.x, vy = ey - lamp.y, vz = ez - lamp.z;
    const vl = Math.hypot(vx, vy, vz) || 1;
    const into = (vx * beam.x + vy * beam.y + vz * beam.z) / vl;
    const on = this.lampOn ? (this.state === 'dying' ? this.lampFlicker : 1) : 0;
    const k = Math.max(0, into) * 0.18 + smooth(VTOL.lamp.outer - 0.06, VTOL.lamp.inner, into);
    this.lampFlare.x = lamp.x; this.lampFlare.y = lamp.y; this.lampFlare.z = lamp.z;
    this.lampFlare.glow = on * Math.min(1.25, k);
    /* AND WHETHER IT ARRIVES, which is the occlusion and is three
       questions in the order they are cheap — see the note at the top
       of this file for what each of them is for. */
    this.lampFlare.render(this.lampFlare.glow > 0.01 &&
      this.canBeSeen(ex, ey, ez, vdx, vdy, lamp, this.model.lamp, LAMP_CHAIN));
    /* the muzzle's, on the same three tests of its own: it is a
       different point on the aircraft, out past the nose, and from
       underneath there are angles where the barrels are lit and the
       lamp beside them is behind the turret. */
    const m = this.muzzle;
    this.muzzleFlare.x = m.x; this.muzzleFlare.y = m.y; this.muzzleFlare.z = m.z;
    this.muzzleFlare.glow = this.muzzleGlow * (0.35 + 0.65 * Math.max(0, into));
    this.muzzleFlare.render(this.muzzleGlow > 0.02 &&
      this.canBeSeen(ex, ey, ez, vdx, vdy, m, this.model.muzzle, MUZZLE_CHAIN));
    return on;
  }

  /**
   * CAN A POINT ON THIS AIRCRAFT BE SEEN FROM THE EYE? The three tests
   * the flares are occluded by, cheapest first.
   *
   * @param at    the point in the world, GAME coordinates
   * @param p     the same point in its part's frame, and
   * @param chain the parts it hangs off — so the hull test knows where
   *              the turret is pointing rather than assuming
   */
  canBeSeen(ex, ey, ez, vdx, vdy, at, p, chain) {
    /* in front of the eye. With no view direction given nothing is
       culled, which is what a caller that has not got one means. */
    if ((vdx || vdy) && ((at.x - ex) * vdx + (at.y - ey) * vdy) <= 0) return false;
    /* its own hull, which is the cheap one: a box and some arithmetic */
    if (this.hullHides(ex, ey, ez, p, chain)) return false;
    /* and the world, which costs a walk through the blockmap */
    return !this.game.level.sightBlocked(ex, ey, ez, at.x, at.y, at.z);
  }

  remove() {
    const g = this.game;
    if (this.root) { g.scene.remove(this.root); this.root = null; }
    for (const a of this.bodies) a.remove();
    for (const a of this.blockers) a.remove();
    this.lampFlare.detach(g.scene); this.muzzleFlare.detach(g.scene);
    if (this.loopHandle) { this.loopHandle.stop(); this.loopHandle = null; }
  }
}

const smooth = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };

/* =====================================================================
   THE WING

   Who sends them and when. Read against the army it comes with (see
   ARMY and FORCES in js/responders.js): called the tic the army is,
   the first arrives firstDelay later from the far end of the road,
   high, and comes down over the lot; each one lost is replaced
   `replace` later; and once the army's own curve has reached
   `secondAt` there are two of them up at once, which is the ceiling.
   ===================================================================== */
export class Gunships {
  /**
   * @param game
   * @param model  { json, bin, texture } from loadVtolModel, or null for
   *               a night with no air support, which is the bargain every
   *               other asset makes
   */
  constructor(game, model = null) {
    this.game = game;
    this.file = model;
    this.texture = model?.texture || null;
    this.model = null;                // built on the first send
    this.ships = [];
    this.nextAt = -1;
    this.sent = 0; this.lost = 0;
  }

  get live() { return this.ships.filter(s => s.whole); }
  get cap() {
    const R = this.game.responders;
    if (!R?.army?.called) return 0;
    return R.pressureOf(R.army) >= VTOL.secondAt ? VTOL.max : 1;
  }

  built() {
    if (!this.model && this.file) this.model = buildVtolModel(this.file.json, this.file.bin);
    return this.model;
  }

  tic() {
    const g = this.game, R = g.responders;
    for (const s of this.ships) s.tic();
    if (!this.file || !R?.army?.called) return;
    if (this.nextAt < 0) this.nextAt = g.tics + VTOL.firstDelay;
    if (g.tics >= this.nextAt && this.live.length < this.cap && !g.player?.dead) {
      this.send();
      this.nextAt = g.tics + VTOL.replace;
    }
  }

  /** One, from the end of the road further from you, at height. */
  send() {
    const g = this.game, R = g.responders, p = g.player;
    const model = this.built();
    if (!model) return null;
    /* THE NEAR END OF THE ROAD, which is the one the vans would use.
       Nine thousand units out is twenty seconds of flying as it is; the
       far end is forty, and forty seconds of an empty sky is not air
       support arriving, it is air support being talked about. */
    const ends = R?.arrivalPoints?.() || [{ x: 0, y: -9000, heading: Math.PI / 2 }];
    let from = ends[0];
    if (p && ends.length > 1) from = ends.reduce((a, b) => dist2(a.x, a.y, p.x, p.y) <= dist2(b.x, b.y, p.x, p.y) ? a : b);
    /* in along the line from that end of the road, `runIn` out */
    let ex = from.x, ey = from.y;
    if (p) {
      const dx = from.x - p.x, dy = from.y - p.y;
      const d = Math.hypot(dx, dy) || 1;
      if (d > VTOL.runIn) { ex = p.x + dx / d * VTOL.runIn; ey = p.y + dy / d * VTOL.runIn; }
    }
    const yaw = p ? Math.atan2(p.y - ey, p.x - ex) : (from.heading ?? 0);
    const ship = new Gunship(this, model, { x: ex, y: ey, z: VTOL.roofAlt, yaw });
    /* it arrives already at speed: it has been flying the road, so the
       jet is well forward of a hover and the pods are near level */
    ship.vx = Math.cos(ship.yaw) * VTOL.speed * 0.8; ship.vy = Math.sin(ship.yaw) * VTOL.speed * 0.8;
    ship.vector = 0.75;
    ship.tilt = ship.tiltL = ship.tiltR = 0.14;
    ship.tiltAux = 0.11;
    this.ships.push(ship);
    this.sent++;
    g.onResponders?.('gunship', ship);
    return ship;
  }

  /** The meshes and the flares. Nothing here touches the world's own
   *  light any more: the lamp threw a lit cone into the shader for an
   *  afternoon and the user has had the beam out, so what is left is a
   *  bright thing in the sky with a flare on it — which is also why
   *  two of them up at once is no longer a question about which one
   *  gets to be the light. */
  render(ex, ey, ez, vdx = 0, vdy = 0) {
    for (const s of this.ships) s.render(ex, ey, ez, vdx, vdy);
  }

  /** Every loss is counted here, by whoever notices it. */
  get down() { return this.ships.filter(s => !s.whole).length; }
}
