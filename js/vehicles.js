/* =====================================================================
   MEWD — the car park, and what happens to it
   =====================================================================

   js/car.js reads a GLB off the disk and hands back its triangles. This
   is what those triangles DO: stand in a bay, catch, go up, leave the
   ground, come down on the roof, go up again, and lie there burning
   while the pieces of it smoulder on the tarmac around it.

   ONE MESH UNTIL SOMETHING MOVES. There are seventy-seven bays and
   every one of them is filled, and seventy-seven meshes is seventy-seven
   draw calls for a row of things that never move. So a parked car is not
   a mesh: it is a slab of vertices baked into world space and
   concatenated into ONE geometry, the same bargain js/mapgeo.js makes
   with the walls. A car only gets a mesh of its own for the second and a
   half it is in the air; when it lands it is baked into a second slab
   with the other wrecks, and so is every piece of debris that has come
   to rest. Rebuilds happen once at the end of whichever tic dirtied
   them, so a chain reaction that takes out six cars rebuilds once, and
   nothing is ever drawn twice in one frame.

   THE TUMBLE IS NOT A PHYSICS ENGINE and does not want to be. It is
   Doom's own arithmetic — a velocity, a gravity of 0.85 units per tic
   per tic, which is the same fall the sparks off a broken light take,
   and which happens to be very close to a real g at this world's scale.
   Three spin rates are integrated separately as Euler angles in the
   order the mesh is built for (see carMesh): yaw, then roll about the
   car's own length, then pitch nose over tail. That is not rigid-body
   dynamics and for a car in the air for forty tics nobody can tell.

   IT LANDS ON ITS ROOF BECAUSE THE ROLL RATE IS CHOSEN SO IT WILL. The
   flight is ballistic, so the time it will be in the air is known the
   moment it leaves the ground — a box turned half a turn about its long
   axis is exactly as tall as it was, so the centre comes back to the
   height it started at, and the flight lasts 2v/g. Divide half a turn by
   that and the car completes its roll as it arrives. It is aimed, not
   simulated, and it is the difference between a car that lands upside
   down and a car that lands upside down SOMETIMES.

   HOW HIGH A CAR ON ITS ROOF SITS is not a number anybody types in. The
   eight corners of its own box get turned by whatever orientation it has
   at that moment, and the lowest one is put on the tarmac. Which means
   it works at any angle, so the settle — the ten tics where it rocks
   from however it hit onto its roof — is just the same test run every
   tic while the orientation eases to its resting one.
   ===================================================================== */

import * as THREE from 'three';
import { TICRATE, pRandom, angleDiff, angleNorm, dist2 } from './util.js';
import {
  carGeometry, chunkGeometry, carMesh, carGeom,
  carCorners, carBlockers, carBlockRadius, carHeight, carWidth,
  wheelGeometry, wheelAt, lampGeometry, cannonGeometry, meshAt,
} from './car.js';
import { BLOOM_LAYER, lamps, lampMaterial, lampDarkMaterial } from './bloom.js';
import { aimPitch, hoseReach } from './water.js';

/* ---------------------------------------------------------------------
   The numbers
   --------------------------------------------------------------------- */
const GRAVITY = 0.85;        // units per tic per tic — the sparks' own fall

const HEALTH = 150;          // a few seconds of being on fire
/* HOW MANY ROUNDS IT TAKES, at the user's request: a vehicle should
   take a lot of the minigun and show every hit before it goes. The
   minigun does twenty-four to forty-eight a round and a car has a
   hundred and fifty of health, so without this a hatchback was gone in
   a tic and a half. What a round does to a vehicle is divided by this
   — twenty for a car in the lot, which is eighty-odd rounds, about
   two thirds of a second of the trigger; the police van and the APC
   set their own, much higher, below. The holes go on regardless (see
   js/decals.js, vehicleHole), which is the point: you watch it fill
   with them and then it chars and goes up the way a burnt one does. */
const SHOT_ARMOUR = 20;
const BURN_EVERY = 10;       // tics between a burning car taking it
const BURN_DAMAGE = 12;
const FUEL = 520;            // what a tank is worth to the tarmac under it
const CATCH_TICS = 40 * TICRATE;

const LIFT = [13, 19];       // how hard it leaves the ground
const DRIFT = 1.7;           // and how far sideways
const YAW_SPIN = 0.055;      // slew, in radians a tic
const PITCH_SPIN = 0.030;    // nose over tail
const CANT = 0.22;           // how far past half a turn it may land
const TILT = 0.12;           // and how crooked it is left lying, nose to tail
const ROLL_CANT = 0.08;      // and side to side
const SETTLE = 10;           // tics spent rocking onto the roof

const WRECK_LIT = 0.42;      // a burnt car is a dark car
const WRECK_CHAR = 1;        // and js/material.js puts the coals on it
const CHUNK_CHAR = 0.85;

/* IT CHARS FIRST, at the user's request. A car used to go from parked
   to airborne in the tic its health ran out; now the tank going is the
   END of something you can watch — the paint blackening, the coals
   coming up through it, embers and smoke off the roof — and how long
   that takes is rolled per car so a row of them lit together does not go
   off like a firework display on one fuse. */
const CHAR_TICS = [4.5 * TICRATE, 7.5 * TICRATE];
const CHAR_DARK = 0.62;      // how much of its light a charred car has lost at the end

const BLAST_R = 210;         // what the launch bang used to reach
const BLAST_DMG = 90;
/* AND THE BANG AT THE END OF THE CHAR IS FOUR OF THE OLD ONE, also at
   the user's request. Four is spent where four can be seen: four times
   the fireballs, the embers, the smoke and the light, the heat of the
   floor pinned to its maximum, and the sound made the loudest thing in
   the game. The RADIUS is doubled rather than quadrupled — a doubled
   radius is a quadrupled area, which is what "four times the blast"
   means on a floor plan — and the damage is doubled, which with the
   area is eight times what the old bang put into the car park. */
const FINAL = 4;
const FINAL_R = BLAST_R * 2;
const FINAL_DMG = BLAST_DMG * 2;
const FINAL_FLASH = 26;      // tics the light of it hangs about
const CRASH_R = 170;         // and the second, which is the smaller bang
const CRASH_DMG = 55;
const SCARE_R = 1400;        // and how far away somebody stops shopping

const SHED_LAUNCH = 8;       // pieces thrown as it leaves — twice what it was, see FINAL
const SHED_CRASH = 11;       // and as it arrives
const CHUNK_LIFT = [3.5, 11];
const CHUNK_OUT = [1.2, 5.0];
const CHUNK_SPIN = 0.34;
const CHUNK_BOUNCE = 0.32;
const SMOULDER = 22 * TICRATE;

const MAX_FLYING_CHUNKS = 64;
const MAX_RESTING_CHUNKS = 200;

const rnd = () => pRandom() / 255;
const between = ([a, b]) => a + rnd() * (b - a);

/* ---------------------------------------------------------------------
   Turning things

   three.js reads rotation.order 'YXZ' as R = Ry·Rx·Rz, which applied to
   a point means Rz first, then Rx, then Ry — so in the object's own
   frame it yaws, then rolls about its length, then tips nose over tail.
   This is that product, written out, because the smoke test has no
   three.js to ask and a matrix class for one multiply is not worth it.
   --------------------------------------------------------------------- */
function turn(p, yaw, rx, rz) {
  const cz = Math.cos(rz), sz = Math.sin(rz);
  const x1 = p[0] * cz - p[1] * sz, y1 = p[0] * sz + p[1] * cz, z1 = p[2];
  const cx = Math.cos(rx), sx = Math.sin(rx);
  const y2 = y1 * cx - z1 * sx, z2 = y1 * sx + z1 * cx;
  const cy = Math.cos(yaw), sy = Math.sin(yaw);
  return [x1 * cy + z2 * sy, y2, -x1 * sy + z2 * cy];
}

/** How far the lowest and highest corners of a turned box are from its
 *  middle. Yaw is not in it: turning about the up axis cannot change a
 *  height. The low one puts the thing on the ground; the high one is how
 *  tall it has ended up, which for something lying on its roof at an
 *  angle is not a number anybody can write down in advance. */
function extentOf(corners, rx, rz) {
  const cz = Math.cos(rz), sz = Math.sin(rz), cx = Math.cos(rx), sx = Math.sin(rx);
  let lo = Infinity, hi = -Infinity;
  for (const p of corners) {
    const y = (p[0] * sz + p[1] * cz) * cx - p[2] * sx;
    if (y < lo) lo = y;
    if (y > hi) hi = y;
  }
  return { lo, hi };
}
const lowestOf = (c, rx, rz) => extentOf(c, rx, rz).lo;

/** Model coordinates to the renderer's, about a model-space origin. */
const toMesh = (p, o, L) => [(p[0] - o[0]) * L, (p[2] - o[2]) * L, -(p[1] - o[1]) * L];

/** Copy vertices into world space. A parked car never moves, so it is
 *  cheaper to bake its heading and its bay into its vertices once than
 *  to give it a transform of its own for ever. */
function bake(a, yaw, rx, rz, x, y, z) {
  const out = a.position.slice();
  for (let i = 0; i < out.length; i += 3) {
    const p = turn([out[i], out[i + 1], out[i + 2]], yaw, rx, rz);
    out[i] = p[0] + x; out[i + 1] = p[1] + z; out[i + 2] = p[2] - y;
  }
  return { ...a, position: out };
}

/** Everything in `list` as one geometry, or nothing if the list is bare.
 *  Typed arrays sized up front and filled with set(), because seventy
 *  cars is a third of a million floats and pushing those one at a time
 *  is the difference between a rebuild you cannot see and a hitch. */
const SLAB_KEYS = ['position', 'uv', 'light', 'sky', 'charred', 'ink'];
function mergeInto(mesh, texture, scene, list) {
  if (mesh) { scene.remove(mesh); mesh.geometry.dispose(); mesh.material.dispose(); }
  if (!list.length) return null;
  const a = {};
  for (const k of SLAB_KEYS) {
    let n = 0;
    for (const s of list) n += s[k].length;
    const buf = new Float32Array(n);
    let at = 0;
    for (const s of list) { buf.set(s[k], at); at += s[k].length; }
    a[k] = buf;
  }
  const m = carMesh(texture, a);
  m.name = 'cars';
  scene.add(m);
  return m;
}

/* =====================================================================
   THE PAINT

   ONE MODEL, ONE SHEET, ONE DRAW CALL, AND A CAR PARK THAT IS NOT ALL
   THE SAME COLOUR. The whole lot is a single mesh — seventy-seven
   vehicles in one geometry, which is the thing worth keeping — so a red
   van cannot be a different file or a different texture. It is the same
   texel multiplied by a colour that rides in the vertices, in the ink
   channel that was already there and was saying nothing (see the INK
   block in js/material.js, which is where the white paint is isolated
   and where this is spent).

   WHAT THE COLOURS ARE. A supermarket car park in a town where half the
   population has already left, so: the white the model came in, a
   couple of dirty near-whites and silvers, and then the browns, tans,
   greens, maroons and blues that a fifteen-year-old panel van is
   actually painted. Nothing bright — a lot full of primary colours
   reads as a toy box, and this one has to read as somewhere people
   parked to go and buy bread. The saturated ones are the exceptions
   they are in a real car park: one red, one blue, one yellow.

   AND THEY ARE ALL BRIGHTER THAN THEY LOOK ON PAPER, because this
   multiplies TWICE. The sheet's own shading is in the texel already,
   and then the car park's light — which is dusk, in a town where the
   power is going — is on top of that. The first cut of this palette was
   picked at the values a van is actually painted, 0.24 to 0.6, and the
   lot came out as two whites and ten grey shapes with wheels. Nothing
   under about 0.4 in its strongest channel survives to the screen.
   ===================================================================== */
/* AND THE QUIET ONES ARE IN IT TWICE, which is the whole of the
   weighting: a real car park is mostly white, silver and beige with a
   few colours in it, and a list of twelve sampled evenly puts a
   turquoise van in every eighth bay. Repeating an entry is the cheapest
   weight there is and it reads off the page. */
export const PAINT = [
  [1.00, 1.00, 1.00],   // white, which is the model as its author painted it
  [1.00, 1.00, 1.00],
  [0.94, 0.92, 0.84],   // cream, a van that has been outside a while
  [0.94, 0.92, 0.84],
  [0.78, 0.80, 0.84],   // silver
  [0.92, 0.68, 0.30],   // ochre
  [0.76, 0.50, 0.28],   // rust brown
  [0.46, 0.72, 0.44],   // green
  [0.40, 0.66, 0.82],   // sky blue
  [0.80, 0.34, 0.30],   // maroon
  [0.95, 0.26, 0.20],   // and the loud ones, which are the exceptions
  [0.30, 0.46, 0.92],   // they are in a real car park: one red, one
  [0.96, 0.80, 0.24],   // blue, one yellow
  [0.36, 0.74, 0.70],   // and one turquoise, because it is 1987
];

/** Which paint a bay gets, off its own position.
 *
 *  NOT A FRESH RANDOM, for two reasons. The lot is laid out by the map
 *  with its own seeded stream and drawing from it here would move every
 *  number after it, which is most of the level. And a fleet that is the
 *  same fleet every time the level is built is a fleet you can take a
 *  screenshot of twice. `variant` is in the hash as well, so a map that
 *  later wants to steer the colours has a handle on them without this
 *  needing to know anything about bays.
 */
export function paintOf(slot, n = PAINT.length) {
  let h = ((slot.x | 0) * 374761393 + (slot.y | 0) * 668265263 + (slot.variant | 0) * 2246822519) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return PAINT[((h ^ (h >>> 16)) >>> 0) % n];
}

/* =====================================================================
   ONE VEHICLE
   ===================================================================== */
class Vehicle {
  constructor(fleet, def, opts) {
    this.fleet = fleet;
    this.def = def;
    this.x = opts.x; this.y = opts.y;
    this.ground = opts.z;
    this.yaw = opts.angle;
    this.rx = 0; this.rz = 0;                 // roll about its length, pitch nose over tail
    this.light = opts.light; this.sky = opts.sky;
    /* what the white bodywork in the sheet is multiplied by — see PAINT */
    this.paint = opts.paint || [1, 1, 1];
    /* ITS OWN SHEET, if it has one. The lot is one model on one sheet
       and the slab is built on that; a vehicle that arrives with a
       different sheet — the police van — can never go into the slab and
       is drawn as its own mesh from the day it arrives to the day it is
       a wreck. `own` says so. */
    this.texture = opts.texture || fleet.texture;
    this.own = !!opts.own;
    /* HOW WELL IT TAKES A FIRE, in two numbers, both 1 for a car in the
       lot and both much larger for anything the police arrive in.

       The responders' vehicles used to be FIREPROOF — one flag, asked
       in damage, ignite, startChar and blowUp, and for a vehicle that
       is invulnerable, since fire is the only thing that ends one. At
       the user's request they are not any more: they catch, they char
       and they go up exactly like the customers' vans, MUCH more slowly.
       Which is the better answer, because "you cannot" and "you can, at
       a price" are different games and this one was always the second.

         fireArmour   what fire's damage is divided by on the way in.
                      Eight for a squad van: a hundred and fifty of
                      health at a point and a half every ten tics is
                      most of a minute of standing in flame

         charFuse     what the blackening is multiplied by once the
                      health is gone. Four for a squad van, so the part
                      you watch — the coals crawling over it, the paint
                      going, the light coming off the bay — is twenty
                      seconds rather than five

       Nine seconds for a hatchback against most of a minute for a van
       with a crest on it. The TROOPERS are still fireproof and that has
       not moved: the flamethrower is not the answer to a man in armour,
       and it is now a slow answer to the thing he arrived in. */
    this.fireArmour = Math.max(1, opts.fireArmour || 1);
    this.charFuse = Math.max(1, opts.charFuse || 1);
    this.shotArmour = Math.max(1, opts.shotArmour || SHOT_ARMOUR);
    /* HOW HIGH IT RIDES OFF THE TARMAC, and zero for everything with
       wheels. The army's APC is a hover carrier and floats (see ArmyApc),
       which in here is one number and three consequences: the mesh is
       drawn that much higher, the thing you cannot walk through is that
       much taller — it still stands ON the ground, because the skirts
       are in the way whether they touch or not — and a wreck loses it,
       since nothing that has stopped working hovers. */
    this.hover = opts.hover || 0;

    this.state = opts.state || 'parked';
    this.health = HEALTH;
    this.burning = 0;
    this.burnTick = 0;
    this.flames = [];
    this.mesh = null;
    /* charring — see startChar */
    this.char = 0;
    this.charTics = 0;
    this.charTick = 0;
    this.flash = 0;

    const L = def.length, h = def.box.height;
    this.mid = [0, 0, h / 2];                 // it turns about its middle, not its wheels
    this.cz = this.ridingHeight;              // where that middle is
    this.vx = 0; this.vy = 0; this.vz = 0;
    this.corners = carCorners(def).map(p => toMesh(p, this.mid, L));

    /* Parked: no mesh, no transform — just vertices in the slab. Unless
       it is its own thing, in which case it is a mesh from the start. */
    this.local = null;
    this.slab = null;
    if (this.own) {
      this.local = carGeometry(def, {
        angle: this.yaw, light: this.light, sky: this.sky, origin: this.mid, paint: this.paint,
      });
      this.mesh = carMesh(this.texture, this.local);
      this.mesh.name = 'car:' + def.id;
      this.fitParts();
      fleet.game.scene.add(this.mesh);
      this.place();
    } else {
      this.slab = bake(carGeometry(def, {
        angle: this.yaw, light: this.light, sky: this.sky, origin: this.mid,
        paint: this.paint,
      }), this.yaw, 0, 0, this.x, this.y, this.cz);
    }

    /* and the part you cannot walk through, which for a hovering one is
       the gap under it as well: you do not get to walk beneath an APC */
    this.blockers = [];
    this.block(this.hover + carHeight(def));
  }

  /** Where the middle of it sits when it is standing or driving: on the
   *  tarmac, plus whatever it hovers. One place, because three things
   *  used to work it out and the hover had to reach all three. */
  get ridingHeight() { return this.ground + this.hover + this.def.box.height / 2 * this.def.length; }
  /** Where the bottom of the body is: the tarmac, plus the hover. */
  get bodyZ() { return this.ground + this.hover; }

  /** Doom's cylinders, three in a row. They carry a pointer back here,
   *  which is what makes a shot at any third of a van damage the van. */
  block(height) {
    this.unblock();
    const g = this.fleet.game, d = this.def;
    for (const b of carBlockers(d, this.x, this.y, this.yaw)) {
      const a = g.spawn('CARBODY', b.x, b.y, this.ground, {
        radius: carBlockRadius(d), height: Math.max(16, Math.round(height)),
      });
      a.vehicle = this;
      this.blockers.push(a);
    }
  }

  unblock() {
    for (const a of this.blockers) a.remove();
    this.blockers.length = 0;
  }

  /** Anybody standing where the cylinders just landed is put outside
   *  them. A van that pulls up on top of you is the commonest way to end
   *  up inside one; you can walk out of a thing you are inside now (see
   *  Player.thingInWay), and this is so that you do not have to. Out of
   *  the SIDE of it, which is the short way and the way the door is. */
  shoveClear() {
    const g = this.fleet.game, p = g.player;
    if (!p || p.dead || !this.blockers.length) return;
    const r = carBlockRadius(this.def) + p.radius + 4;
    let inside = false;
    for (const b of this.blockers) if (dist2(p.x, p.y, b.x, b.y) < r * r) { inside = true; break; }
    if (!inside) return;
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    const dx = p.x - this.x, dy = p.y - this.y;
    const lon = dx * c + dy * s, lat = dx * -s + dy * c;
    const side = lat >= 0 ? 1 : -1;
    const tx = this.x + c * lon - s * side * r, ty = this.y + s * lon + c * side * r;
    /* through the level's own collision, so a van parked against a wall
       does not put you into the wall instead */
    const [nx, ny] = g.level.slideMove(p.x, p.y, tx - p.x, ty - p.y, p.radius, p.z, p.height, false);
    p.x = nx; p.y = ny;
    const sec = g.level.sectorAt(p.x, p.y, p.sector);
    if (sec) p.sector = sec.above === null ? sec : g.level.spanIn(sec, p.z, p.x, p.y);
  }

  /* ------------------------------------------------------------------
     Being shot at, and catching
     ------------------------------------------------------------------ */
  /** Whether anything can still happen to it: standing in a bay, on
   *  the road, or already charring. In the air and afterwards it is
   *  past hurting. */
  get whole() { return this.state === 'parked' || this.state === 'driving' || this.state === 'charring'; }

  /** `source` and `opts` are what Actor.damage hands a vehicle through
   *  its blockers, and were thrown away here until the armour needed to
   *  know whether what arrived was fire. */
  damage(n, source = null, opts = {}) {
    if (!this.whole) return;
    /* THE STREAM LIGHTS IT AND THAT IS ALL IT DOES, at the user's
       request. The flamethrower's particles used to land on the
       blockers as damage, six a tic at five to nine each, and a held
       stream took a hatchback apart in a couple of seconds without it
       ever really burning. A car the flame reaches now CATCHES —
       ignite(), the same thing a blast or a burning neighbour does to
       it — and then burns on its own clock: forty seconds alight,
       twelve off its health every ten tics through whatever fire
       armour it has, the char, the launch. Holding the stream on it
       longer changes nothing, which is what "stays alight like normal"
       means. A blast still hurts (it carries `fire`, not `stream`). */
    if (opts.stream) { this.ignite(); return; }
    /* THE ARMOUR IS AGAINST FIRE, AND SEPARATELY AGAINST ROUNDS. A bang
       and a van are the same to a squad van as to a hatchback; what it
       is built to stand in is the burning, and what it is built to
       take a lot of is the minigun — see SHOT_ARMOUR. */
    if (opts.fire) n /= this.fireArmour;
    if (opts.shot) n /= this.shotArmour;
    /* MORE DAMAGE TO ONE ALREADY CHARRING HURRIES IT: two tics off the
       fuse per point, so a car that has just started to blacken and is
       then hit by the bang next door goes early, and a chain reaction
       across a full row is a ripple rather than a metronome. */
    if (this.state === 'charring') { this.charTics = Math.max(1, this.charTics - n * 2); return; }
    this.health -= n;
    if (this.health <= 0) this.startChar();
  }

  ignite(tics = CATCH_TICS) {
    if (!this.whole) return;
    /* nothing in this world catches — see Actor.ignite */
    if (this.fleet.game.level.noBurn) return;
    const first = this.burning <= 0;
    this.burning = Math.max(this.burning, tics);
    if (first) this.catch();
  }

  /** The moment it is alight: the noise, the pool under it and the
   *  flames on it. Called once by ignite, and by startChar for a car
   *  that was shot to death without ever having been lit. */
  catch() {
    const g = this.fleet.game;
    g.sound?.play('ignite', this);
    /* A TANK OF FUEL GOES INTO THE TARMAC. Bare tarmac does not burn,
       but js/fire.js treats what you pour on a floor as accelerant, so
       what you get is a car standing in a pool of fire — which is what
       is meant to happen, and it is also how the fire reaches the next
       bay along. */
    g.fire?.ignite(this.x, this.y, FUEL, 70);
    /* and two columns of it standing on the car, because the fire under
       it is on the ground and a car alight is alight all over */
    if (this.flames.length) return;
    const L = this.def.length;
    for (const t of [-0.22, 0.2]) {
      const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
      const f = g.spawn('BLAZE', this.x + c * t * L, this.y + s * t * L,
        this.ground + carHeight(this.def) * 0.55);
      this.flames.push(f);
    }
  }

  burnTic() {
    if (--this.burning <= 0) { this.burning = 0; this.douse(); return; }
    if (++this.burnTick < BURN_EVERY) return;
    this.burnTick = 0;
    this.fleet.game.fire?.ignite(this.x, this.y, 40);
    this.damage(BURN_DAMAGE, null, { fire: true });
  }

  /* ------------------------------------------------------------------
     CHARRING

     What happens between the tank being done for and the tank going.
     The car leaves the slab and becomes its own mesh — the only way to
     change one vehicle's vertices without rebuilding thirty-six — and
     for the next five to seven seconds two of its attributes are wound
     by hand: `charred`, which js/material.js scatters live coals over
     in proportion, and `light`, which comes down to a third so the
     paint goes black under them. The soot is the same coals and the
     same dark that a wreck ends up with; a charring car is a wreck
     arriving gradually, and when it reaches the end it goes up on the
     geometry it has, so what is in the air is the black thing you
     watched turn black.

     Off it the whole time: sparks, more of them as it goes; smoke,
     thicker; and the one fire light pulled toward it, harder as it
     goes, so the bay around a car about to go is lit like a hearth.
     ------------------------------------------------------------------ */
  startChar() {
    if (this.state === 'charring' || !this.whole) return;
    const g = this.fleet.game;
    this.state = 'charring';
    this.char = 0;
    this.charTick = 0;
    /* AND IT TAKES `charFuse` TIMES AS LONG on anything armoured, which
       is the half of the slowness you actually watch: five seconds of a
       hatchback going black, twenty of a squad van. */
    this.charTics = Math.round(between(CHAR_TICS) * this.charFuse);
    if (this.burning <= 0) { this.burning = this.charTics + 40; this.catch(); }
    /* out of the slab and into a mesh of its own */
    if (this.slab) { this.slab = null; this.fleet.dirty = true; }
    if (!this.local) this.local = carGeometry(this.def, {
      angle: this.yaw, light: this.light, sky: this.sky, origin: this.mid, paint: this.paint,
    });
    if (!this.mesh) {
      this.mesh = carMesh(this.texture, this.local);
      this.mesh.name = 'car:' + this.def.id;
      g.scene.add(this.mesh);
    }
    this.light0 = Float32Array.from(this.local.light);
    for (const q of this.parts || []) q.light0 = Float32Array.from(q.mesh.geometry.getAttribute('light').array);
    this.place();
    g.sound?.play('burn', this);
  }

  charTic() {
    const g = this.fleet.game;
    this.char = Math.min(1, this.char + 1 / Math.max(1, this.charTics));
    const k = this.char;
    /* the vertices, every third tic: the coals and the dark */
    if ((++this.charTick % 3) === 0 && this.mesh) {
      const geo = this.mesh.geometry;
      const ch = geo.getAttribute('charred'), lt = geo.getAttribute('light');
      ch.array.fill(k * WRECK_CHAR);
      for (let i = 0; i < lt.array.length; i++) lt.array[i] = this.light0[i] * (1 - CHAR_DARK * k);
      ch.needsUpdate = true; lt.needsUpdate = true;
      /* and the arrays the wreck will be baked from, so what lands is
         what left */
      this.local.charred.fill(k * WRECK_CHAR);
      for (let i = 0; i < lt.array.length; i++) this.local.light[i] = lt.array[i];
      /* and the wheels and the cannon, which are the same van */
      for (const q of this.parts || []) {
        const wc = q.mesh.geometry.getAttribute('charred'), wl = q.mesh.geometry.getAttribute('light');
        wc.array.fill(k * WRECK_CHAR);
        for (let i = 0; i < wl.array.length; i++) wl.array[i] = q.light0[i] * (1 - CHAR_DARK * k);
        wc.needsUpdate = true; wl.needsUpdate = true;
      }
    }
    const h = carHeight(this.def);
    g.fx?.ember(this.x, this.y, this.cz + h * 0.3, 1 + ((k * 2.5) | 0), 0.5 + k);
    if ((this.charTick % 3) === 1) g.fx?.puff(this.x, this.y, this.cz + h * 0.5, 22 + 18 * k, 160);
    g.fx?.glowAt(this.x, this.y, 0.8 + 1.6 * k);
    if ((this.charTick % 10) === 0) g.fire?.ignite(this.x, this.y, 40);
    if ((this.charTick % 24) === 0) g.sound?.play('burn', this);
    if (k >= 1) this.blowUp();
  }

  douse() {
    for (const f of this.flames) f.remove();
    this.flames.length = 0;
  }

  /** PUT OUT, by the fire brigade's water (js/water.js): the burning
   *  stops and the flames come off. Not once it is charring — the tank
   *  has gone by then and nothing saves it, the same as a burnt aisle. */
  putOut() {
    if (this.state === 'charring' || this.burning <= 0) return false;
    this.burning = 0;
    this.douse();
    return true;
  }

  /* ------------------------------------------------------------------
     UP

     The first bang, and then it leaves. The roll rate is worked out from
     how long it is going to be in the air, so that half a turn finishes
     as it arrives; see the note at the top of the file.
     ------------------------------------------------------------------ */
  blowUp() {
    if (!this.whole) return;
    const g = this.fleet.game, d = this.def;
    this.state = 'air';
    this.burning = 0;
    this.douse();
    this.lightsOut();
    this.unblock();
    if (this.slab) { this.fleet.dirty = true; this.slab = null; }

    this.bigBoom();
    g.scare?.(this.x, this.y, SCARE_R);

    this.vz = between(LIFT);
    const ang = rnd() * Math.PI * 2;
    this.vx = Math.cos(ang) * rnd() * DRIFT;
    this.vy = Math.sin(ang) * rnd() * DRIFT;

    const flight = 2 * this.vz / GRAVITY;
    const over = (rnd() - 0.5) * 2 * CANT;              // it does not land square
    this.rollRate = (Math.PI + over) / flight;
    this.pitchRate = (rnd() - 0.5) * 2 * PITCH_SPIN;
    this.yawRate = (rnd() - 0.5) * 2 * YAW_SPIN;

    /* its own mesh now, for as long as it is off the ground — unless it
       already has one, charred, in which case that is what flies */
    if (!this.mesh) {
      this.local = carGeometry(d, {
        angle: this.yaw, light: this.light, sky: this.sky, origin: this.mid,
        paint: this.paint,
      });
      this.mesh = carMesh(this.texture, this.local);
      this.mesh.name = 'car:' + d.id;
      g.scene.add(this.mesh);
    }
    this.place();

    this.shed(SHED_LAUNCH);
  }

  /** A bang, centred on wherever the car is standing. `scale` is how
   *  many of the old bang this is — see FINAL. */
  boom(radius, damage, blasts, scale = 1, opts = {}) {
    const g = this.fleet.game;
    const at = { x: this.x, y: this.y, z: this.ground };
    /* A CAR AGAINST A SHOPFRONT TAKES THE SHOPFRONT, and not much more.
       A third of a region's integrity a bang, so one car is a scorch and
       a hole in the glazing, a car park going up in sequence is a wall
       coming down, and the fire does the rest — which is the right order
       for a place where the cars are the fuse and the building is what
       burns. Scaled with the bang, because FINAL is four of these. */
    g.explode(at, { radius, damage, heat: Math.min(255, 260 * scale), heatRadius: 96 * Math.sqrt(scale),
                    ignite: 340, sound: opts.sound,
                    structure: 0.34 * scale, structureRadius: radius * 1.25 });
    const L = this.def.length, W = carWidth(this.def);
    /* the fireballs, spread over the car's own footprint — and a big one
       spreads them past it, because a bang four times the size is not
       four times the fireballs in the same square */
    const n = (blasts + 2) * scale, wide = 0.7 + 0.25 * (scale - 1);
    for (let k = 0; k < n; k++) {
      const t = (rnd() - 0.5) * wide * L, u = (rnd() - 0.5) * (0.5 + 0.4 * (scale - 1)) * L;
      const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
      g.spawn('BLAST', this.x + c * t - s * u, this.y + s * t + c * u, this.ground);
    }
    g.fx?.ember(this.x, this.y, this.ground + 20, 26 * scale, 1);
    for (let k = 0; k < 7 * scale; k++)
      g.fx?.puff(this.x + (rnd() - 0.5) * W * scale, this.y + (rnd() - 0.5) * W * scale,
                 this.ground + 24 + (k % 7) * 6, 34, 200);
  }

  /** THE BANG AT THE END OF THE CHAR — four of the old launch bang, on
   *  the terms set out at FINAL. What a bang this size adds that a
   *  smaller one did not need is a FLASH: the fire light thrown at the
   *  car for the next second, decaying, so the whole car park is lit
   *  from the bay for a moment and then is not. */
  bigBoom() {
    this.boom(FINAL_R, FINAL_DMG, 1, FINAL, { sound: 'bigboom' });
    this.flash = FINAL_FLASH;
  }

  /* ------------------------------------------------------------------
     Flying, and arriving
     ------------------------------------------------------------------ */
  tic() {
    /* the light of the bang, hanging about and going */
    if (this.flash > 0) {
      this.fleet.game.fx?.glowAt(this.x, this.y, 6 * (this.flash / FINAL_FLASH));
      this.flash--;
    }
    if (this.state === 'charring') { this.charTic(); return; }
    if (this.burning > 0) this.burnTic();
    /* AND IF THAT WAS THE TIC IT TIPPED OVER, stop here: burnTic can
       start the char, and a car that has just started charring must not
       fall through to the settle below, which is written for a car that
       has landed and would integrate a car that has not off numbers it
       does not have yet. It chars from the next tic. */
    if (this.state === 'charring') return;
    if (this.state === 'wreck') { this.smoulderTic(); return; }
    if (this.state === 'parked' || this.state === 'driving') return;

    if (this.state === 'air') {
      this.vz -= GRAVITY;
      this.cz += this.vz;
      this.x += this.vx; this.y += this.vy;
      this.rx += this.rollRate; this.rz += this.pitchRate; this.yaw += this.yawRate;
      /* it is on fire the whole way down */
      const g = this.fleet.game;
      g.fx?.ember(this.x, this.y, this.cz, 2, 1);
      if ((pRandom() & 1) === 0) g.fx?.puff(this.x, this.y, this.cz, 26, 150);
      const low = lowestOf(this.corners, this.rx, this.rz);
      if (this.vz < 0 && this.cz + low <= this.ground) this.crash(low);
      else this.place();
      return;
    }

    /* settling: ease onto the roof, and let its own corners say how high
       that leaves it. It rocks, because the height follows the angle. */
    this.settle--;
    const k = 1 - this.settle / SETTLE;
    this.rx = this.rx0 + (this.rxTo - this.rx0) * k;
    this.rz = this.rz0 + (this.rzTo - this.rz0) * k;
    this.cz = this.ground - lowestOf(this.corners, this.rx, this.rz);
    this.place();
    if (this.settle <= 0) this.rest();
  }

  /** Lying there going out: forty seconds of smoke and sparks off it,
   *  and then only the coals `charred` keeps alight in the shader — the
   *  same ones burning in the gutted aisles indoors, on the same clock. */
  smoulderTic() {
    if (this.smoulder <= 0) return;
    this.smoulder--;
    const g = this.fleet.game, k = this.smoulder / (SMOULDER * 2);
    if ((++this.tick % 5) === 0) g.fx?.ember(this.x, this.y, this.cz, 1, 0.4 + 0.6 * k);
    if ((this.tick % 11) === 0) g.fx?.puff(this.x, this.y, this.cz + 10, 26 + 16 * k, 190);
    if ((this.tick % 70) === 0 && k > 0.35) g.fire?.ignite(this.x, this.y, 90, 40);
  }

  /* ------------------------------------------------------------------
     THE PARTS THAT MOVE ON THEIR OWN — see js/car.js. The police van's
     wheels, each hung off the body about its own axle and drawn with
     the body's own material, so they warm and char with it; and its
     light bar, flashing, on the bloom layer, until the van goes up.
     A vehicle whose model has neither gets neither.
     ------------------------------------------------------------------ */
  fitParts() {
    const d = this.def, L = d.length;
    const lit = { angle: this.yaw, light: this.light, sky: this.sky, paint: this.paint };
    this.wheels = [];
    /* every part drawn off the body's sheet, with how to draw it again:
       the char and the wreck repaint all of them (see refitParts) */
    this.parts = [];
    for (const w of d.model.wheels || []) {
      const make = o => wheelGeometry(d, w, o);
      const m = new THREE.Mesh(carGeom(make(lit)), this.mesh.material);
      m.name = 'wheel:' + w.name;
      m.position.set(...wheelAt(d, w, this.mid, L));
      this.mesh.add(m);
      this.wheels.push({ mesh: m, def: w, radius: w.radius * L });
      this.parts.push({ mesh: m, make });
    }
    /* THE WATER CANNON: a turret that turns about its mount (`gunYaw`)
       and inside it the barrel's elevation (`gunPitch`), both about the
       pivot, so aiming it is two numbers — see FireTruck */
    this.gun = null;
    if (d.model.cannon) {
      const c = d.model.cannon;
      const make = o => cannonGeometry(d, o);
      const m = new THREE.Mesh(carGeom(make(lit)), this.mesh.material);
      m.name = 'cannon';
      const yaw = new THREE.Group(), pitch = new THREE.Group();
      yaw.position.set(...meshAt(d, c.pivot, this.mid, L));
      yaw.add(pitch); pitch.add(m);
      this.mesh.add(yaw);
      this.gun = { yaw, pitch, mesh: m, def: c };
      this.parts.push({ mesh: m, make });
    }
    this.lamp = null;
    if (d.model.lamps?.length) {
      /* out of step with every other van, off where it came on rather
         than off the game's random table, which it is not worth a roll of */
      const phase = ((this.x * 0.0131 + this.y * 0.0077) % 1 + 1) % 1;
      const a = lampGeometry(d, { origin: this.mid, phase });
      const kind = d.lamp || 'police';
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(a.position, 3));
      geo.setAttribute('side', new THREE.Float32BufferAttribute(a.side, 1));
      geo.setAttribute('phase', new THREE.Float32BufferAttribute(a.phase, 1));
      geo.computeBoundingSphere();
      this.lamp = new THREE.Mesh(geo, lampMaterial(kind));
      this.lamp.name = 'lightbar';
      this.lamp.layers.enable(BLOOM_LAYER);
      this.mesh.add(this.lamp);
      lamps.set.add(this.lamp);
    }
  }

  /** The parts' geometry again, at a new light and char — see crash. */
  refitParts(opts) {
    for (const q of this.parts || []) {
      q.mesh.geometry.dispose();
      q.mesh.geometry = carGeom(q.make({ angle: this.yaw, sky: this.sky, paint: this.paint, ...opts }));
    }
  }

  /** The light bar goes dark and stops glowing, for good. */
  lightsOut() {
    if (!this.lamp || !lamps.set.has(this.lamp)) return;
    lamps.set.delete(this.lamp);
    this.lamp.material = lampDarkMaterial();
    this.lamp.layers.disable(BLOOM_LAYER);
  }

  /** The wheels, turned through as far as the van has just rolled. */
  roll(step) {
    for (const w of this.wheels || []) w.mesh.rotation.z -= step / w.radius;
  }

  place() {
    this.mesh.position.set(this.x, this.cz, -this.y);
    this.mesh.rotation.set(this.rx, this.yaw, this.rz);
  }

  /** It has hit the tarmac. The second bang, and the pieces. */
  crash(low) {
    const g = this.fleet.game;
    this.state = 'settle';
    this.hover = 0;                   // whatever held it up has stopped
    this.updateSector();
    this.cz = this.ground - low;
    g.sound?.play('bodyfall', this);
    this.boom(CRASH_R, CRASH_DMG, 2);
    this.shed(SHED_CRASH);

    /* Onto its roof: half a turn, plus the crookedness it happens to
       have arrived with, kept small enough that it still reads as upside
       down rather than as on its side. */
    this.rx0 = this.rx; this.rz0 = this.rz;
    this.rxTo = Math.round((this.rx - Math.PI) / (2 * Math.PI)) * 2 * Math.PI + Math.PI
              + (rnd() - 0.5) * 2 * ROLL_CANT;
    this.rzTo = Math.max(-TILT, Math.min(TILT, this.rz % (2 * Math.PI)));
    this.settle = SETTLE;

    /* burnt, from here on */
    /* AND A BURNT RED VAN IS STILL A RED VAN. The char darkens what is
       left of the paint rather than replacing it, which is the right
       answer: a wreck you can still tell the colour of is a wreck you
       remember parking next to. */
    this.local = carGeometry(this.def, {
      angle: this.yaw, light: this.light * WRECK_LIT, sky: this.sky,
      origin: this.mid, charred: WRECK_CHAR, paint: this.paint,
    });
    this.mesh.geometry.dispose();
    this.mesh.geometry = carGeom(this.local);
    this.refitParts({ light: this.light * WRECK_LIT, charred: WRECK_CHAR });
    g.fire?.ignite(this.x, this.y, FUEL, 80);
  }

  updateSector() {
    const s = this.fleet.game.level.sectorAt(this.x, this.y);
    if (s) { this.ground = s.floor; this.sky = s.sky ?? (s.outdoor ? 1 : 0); }
  }

  /** Done moving: back into the slab with the other wrecks, and it is in
   *  the way again — lower than it was, because it is on its roof. */
  rest() {
    const g = this.fleet.game;
    this.state = 'wreck';
    /* into the slab with the other wrecks — unless it is on a sheet of
       its own, in which case the mesh it has is the mesh it keeps */
    if (!this.own) {
      g.scene.remove(this.mesh);
      this.mesh.geometry.dispose(); this.mesh.material.dispose();
      this.mesh = null;
      this.fleet.restOf(bake(this.local, this.yaw, this.rx, this.rz, this.x, this.y, this.cz));
      this.local = null;
    }
    /* Still in the way, and still about as tall: a box turned over is
       exactly as tall as it was, and the tilt it came to rest at adds a
       little. Its own corners know, so they are asked rather than told. */
    this.block(this.cz + extentOf(this.corners, this.rx, this.rz).hi - this.ground);
    this.shoveClear();
    this.smoulder = SMOULDER * 2;
    this.tick = 0;
  }

  /* ------------------------------------------------------------------
     Pieces

     A chunk is the model's own surface inside a small box of this
     vehicle's own model space — so a piece off the tail is painted with
     the tail because it IS the tail, and nobody had to decide what a
     torn piece of van looks like.
     ------------------------------------------------------------------ */
  shed(n) {
    const d = this.def, L = d.length;
    const tris = d.model.tris;
    for (let k = 0; k < n; k++) {
      if (this.fleet.flying.length >= MAX_FLYING_CHUNKS) return;
      /* A PIECE OFF THE OUTSIDE, and the model says where the outside
         is: pick one of its triangles and cut a box in around that
         triangle's middle. A chunk is then the model's own triangles
         inside that box (see chunkGeometry), so a piece off the tail is
         the tail — the same geometry, the same paint, torn out.

         This used to sample the hull's two silhouette curves for a point
         on the skin, because the body was BUILT from those curves and
         there were no triangles to ask. There are now. */
      /* THE LAST INDEX IS ONE PAST THE END once in every 256 pieces,
         which is not a rounding worry, it is a crash. rnd() is
         pRandom() / 255 and pRandom() rolls 0 to 255 INCLUSIVE, so it
         returns 1.0 about once in 256 calls and (1.0 * n) | 0 is n.
         Every chunk shed off every car in the lot draws one of these,
         and a chain reaction across the car park sheds hundreds — so
         this was not a rare crash, it was a matter of how long the
         player stood there. Clamped rather than made exclusive because
         the other nine uses of rnd() in this file are ranges, where
         reaching the top of one is correct. */
      const pick = tris[Math.min(tris.length - 1, (rnd() * tris.length) | 0)];
      const px = (pick.a[0] + pick.b[0] + pick.c[0]) / 3;
      const py = (pick.a[1] + pick.b[1] + pick.c[1]) / 3;
      const pz = (pick.a[2] + pick.b[2] + pick.c[2]) / 3;
      const w = 0.07 + rnd() * 0.10, dp = 0.05 + rnd() * 0.09, t = 0.04 + rnd() * 0.07;
      const cut = {
        x0: px - w / 2, x1: px + w / 2,
        y0: py - dp / 2, y1: py + dp / 2,
        z0: Math.max(0, pz - t / 2),
      };
      cut.z1 = cut.z0 + t;

      /* where that box is in the world right now, tumble and all */
      const mid = [(cut.x0 + cut.x1) / 2, (cut.y0 + cut.y1) / 2, (cut.z0 + cut.z1) / 2];
      const off = turn(toMesh(mid, this.mid, L), this.yaw, this.rx, this.rz);
      const wx = this.x + off[0], wy = this.y - off[2], wz = this.cz + off[1];

      /* thrown outward from the middle, and upward */
      const a = Math.atan2(wy - this.y, wx - this.x) + (rnd() - 0.5) * 1.4;
      const sp = between(CHUNK_OUT);
      this.fleet.addChunk(new Chunk(this.fleet, d, cut, {
        x: wx, y: wy, z: wz, ground: this.ground,
        vx: Math.cos(a) * sp + this.vx, vy: Math.sin(a) * sp + this.vy,
        vz: between(CHUNK_LIFT) + Math.max(0, this.vz) * 0.4,
        light: this.light, sky: this.sky, paint: this.paint,
        /* a piece of a vehicle on its own sheet is painted with that
           sheet — see Chunk; it used to be handed the lot's */
        texture: this.own ? this.texture : null,
      }));
    }
  }
}

/* =====================================================================
   ONE PIECE OF IT
   ===================================================================== */
class Chunk {
  constructor(fleet, def, cut, o) {
    this.fleet = fleet;
    this.x = o.x; this.y = o.y; this.z = o.z; this.ground = o.ground;
    this.vx = o.vx; this.vy = o.vy; this.vz = o.vz;
    this.yaw = rnd() * Math.PI * 2;
    this.rx = rnd() * Math.PI * 2; this.rz = rnd() * Math.PI * 2;
    this.rollRate = (rnd() - 0.5) * 2 * CHUNK_SPIN;
    this.pitchRate = (rnd() - 0.5) * 2 * CHUNK_SPIN;
    this.yawRate = (rnd() - 0.5) * 2 * CHUNK_SPIN;
    this.resting = false;
    this.glow = SMOULDER;
    this.tick = 0;

    const L = def.length;
    this.local = chunkGeometry(def, cut, {
      angle: 0, light: o.light * 0.7, sky: o.sky, charred: CHUNK_CHAR,
      paint: o.paint,                    // a piece off a green van is green
    });
    const mid = [(cut.x0 + cut.x1) / 2, (cut.y0 + cut.y1) / 2, (cut.z0 + cut.z1) / 2];
    this.corners = [];
    for (const x of [cut.x0, cut.x1]) for (const y of [cut.y0, cut.y1]) for (const z of [cut.z0, cut.z1])
      this.corners.push(toMesh([x, y, z], mid, L));

    /* ITS OWN SHEET, if the thing it came off had one. A piece of the
       police van, the APC or the gunship is painted with that model's
       own texture — the UVs are that model's — and so it can never go
       into the wrecks' slab, which is built on the lot's sheet: it
       keeps its mesh when it lands. Pieces of the lot's vans go into
       the slab as they always have. */
    this.texture = o.texture || null;
    this.mesh = carMesh(this.texture || fleet.texture, this.local);
    this.mesh.name = 'debris';
    fleet.game.scene.add(this.mesh);
    this.place();
  }

  /** Whether it stays a mesh of its own on the ground. */
  get own() { return !!this.texture; }

  place() {
    this.mesh.position.set(this.x, this.z, -this.y);
    this.mesh.rotation.set(this.rx, this.yaw, this.rz);
  }

  tic() {
    const g = this.fleet.game;
    this.vz -= GRAVITY;
    this.z += this.vz;
    this.x += this.vx; this.y += this.vy;
    this.rx += this.rollRate; this.rz += this.pitchRate; this.yaw += this.yawRate;

    if ((++this.tick & 3) === 0) g.fx?.ember(this.x, this.y, this.z, 1, 0.8);

    const low = lowestOf(this.corners, this.rx, this.rz);
    if (this.vz < 0 && this.z + low <= this.ground) {
      const s = g.level.sectorAt(this.x, this.y);
      if (s) this.ground = s.floor;
      /* One bounce if it came down hard, and then it is scrap on the
         tarmac: the spin bleeds off with it, or a piece lying still goes
         on spinning for ever. */
      if (this.vz < -6 && !this.bounced) {
        this.bounced = true;
        this.z = this.ground - low;
        this.vz *= -CHUNK_BOUNCE;
        this.vx *= 0.5; this.vy *= 0.5;
        this.rollRate *= 0.4; this.pitchRate *= 0.4; this.yawRate *= 0.4;
      } else {
        this.land();
        return;
      }
    }
    this.place();
  }

  land() {
    const g = this.fleet.game;
    this.resting = true;
    /* it comes to rest FLAT, not balanced on a corner: roll and pitch go
       to the nearest half turn, which is the face it was nearest */
    const snap = a => Math.round(a / Math.PI) * Math.PI;
    this.rx = snap(this.rx); this.rz = snap(this.rz);
    this.z = this.ground - lowestOf(this.corners, this.rx, this.rz);
    g.fire?.ignite(this.x, this.y, 70, 26);
    if (this.own) { this.place(); this.slab = null; return; }
    g.scene.remove(this.mesh);
    this.mesh.geometry.dispose(); this.mesh.material.dispose();
    this.mesh = null;
    this.slab = bake(this.local, this.yaw, this.rx, this.rz, this.x, this.y, this.z);
    this.local = null;
  }

  /** Off the ground and out of the scene, for a piece with its own
   *  mesh that the lot has no more room for. */
  discard() {
    if (!this.mesh) return;
    this.fleet.game.scene.remove(this.mesh);
    this.mesh.geometry.dispose(); this.mesh.material.dispose();
    this.mesh = null;
  }

  /** Lying there going out. The particles stop after twenty seconds; the
   *  coals do not, because `charred` is baked into the vertices and
   *  js/material.js keeps them alight on the same clock as the burnt
   *  aisles indoors. */
  smoulderTic() {
    if (this.glow <= 0) return;
    this.glow--;
    const g = this.fleet.game, k = this.glow / SMOULDER;
    if ((++this.tick % 14) === 0 && rnd() < k) g.fx?.ember(this.x, this.y, this.z + 4, 1, 0.5 * k);
    if ((this.tick % 47) === 0 && rnd() < k) g.fx?.puff(this.x, this.y, this.z + 8, 16, 120);
  }
}

/* =====================================================================
   ONE THAT DRIVES

   The police van, which is the first vehicle in the game with somewhere
   to go. It is an ordinary Vehicle in the ways that matter — three
   cylinders, its own mesh, the same box — with one state in front of
   `parked` that nothing else has: DRIVING, along a list of points the
   map hands out (see level.swatRoutes), at a speed, with its three
   blockers carried along under it.

   AND IT BURNS, at the user's request, which it did not for a while:
   it was FIREPROOF, which for a vehicle is invulnerable, and the reason
   was that going up was what used to stop it unloading. It is now
   ARMOURED instead — fireArmour and charFuse in Vehicle — so the stream
   ends one in most of a minute where it ends a hatchback in nine
   seconds. Hold it on one and you get the bay back; wave it past and
   you have wasted your tank. The crew that is already out does not care
   either way, and the troopers themselves are still fireproof.

   AND IT IS A LITTLE BIT OF A CAR PHYSICS NOW, at the user's request.
   The position still rides the polyline exactly — there is no grip, no
   slip and no mass — but the SPEED along it is integrated rather than
   assumed, and the body is hung off it:

     it builds up to speed from a standing start, and it brakes for the
     END of the route rather than for the next corner, on the oldest
     trick in the book: the fastest it may be going is the speed from
     which it could still stop in the distance it has left. So it comes
     off the road already slowing and rolls the last two lengths into
     its place rather than arriving at speed and switching off

     and the body DIPS when it does that. A damped spring on the pitch,
     driven by the acceleration, so the nose goes down under braking,
     the tail squats under power, and when it stops the whole thing
     rocks back once and settles. A second spring on the roll, driven by
     how hard it is turning, leans it out of a corner. Neither of them
     is simulated from a suspension: they are the acceleration, read
     twice, through a spring that overshoots. It costs four numbers and
     it is the difference between a model sliding along a line and a van
     pulling up.

   It stops where the route ends, squares up along the front, and is a
   parked van from then on — the responders decide what comes out of it.

   AND IT DOES NOT STOP FOR ANYBODY. The lot is full of people running
   from a fire, and a squad van coming up the frontage lane at speed
   goes through them: anything solid in front of it is hit hard enough
   to come apart, and the player is shoved and hurt, which is the one
   thing other than a rifle that gets through their fireproofing.
   ===================================================================== */
/* AT THE USER'S REQUEST THEY SPEED IN, and this is the third number it
   has been. Fifteen units a tic — twice a running shopper — put the
   first van in front of you half a minute after it was called, which is
   an interval rather than a response. Thirty was a van with its lights
   on at two in the morning, and took fourteen seconds, and the user
   said it was still too slow.

   SIXTY IS NOT A VAN ANY MORE and is not meant to be: it is two
   thousand units a second, which against a running shopper's four is
   something arriving rather than something driving. What the number
   actually buys is the OUTSIDE case — see `runIn` and `stop` in
   js/responders.js, which are the other two thirds of the same request:
   step out of the building and the first convoy is at the junction
   within a second, across the lot in three, and stopped a van's nose
   from you rather than a van's length.

   AND THE HEADING KEEPS UP, which is the one thing the speed can break.
   The POSITION rides the polyline exactly whatever the speed is; it is
   the drawn yaw that eases, and at thirty units a tic 0.09 a tic was
   enough to be square through a corner.

   AND THEN THE USER SAID SLOWER, which is the fourth number and this
   one: THIRTY-SIX, and it is a top speed now rather than a constant, so
   the average over an approach is well under it. What pays for the
   slowness is the distance — they come into being just out of sight
   rather than at the junction (see `runIn` in js/responders.js) — so
   the clock from the trigger barely moves and what you see is a vehicle
   driving rather than a vehicle teleporting.
   -------------------------------------------------------------------- */
/* exported for the test, which holds the drive it measures against the
   numbers rather than against a remembered figure */
export const DRIVE_SPEED = 36;   // the fastest it will go, units a tic
export const DRIVE_ACCEL = 0.75; // and how quickly it gets there
export const DRIVE_BRAKE = 0.85; // and how hard it can stop, units a tic a tic
const DRIVE_TURN = 0.12;         // radians a tic the heading may change
const RUNOVER_DMG = 220;         // what the front of a van does to a person
const RUNOVER_PLAYER = 40;       // and to you, once per hit now that a hit throws you clear
const SIREN_EVERY = 19;          // tics between the two notes

/* THE BODY ON TWO SPRINGS, which is the whole of the weight shift and
   is not a suspension: it is the acceleration, read twice, through
   something that overshoots.

   `pitchPerG` turns acceleration into a target angle — negative when
   braking, which is nose down, because the mesh's own +Z rotation
   raises the nose (see carMesh, which orders the Euler YXZ so that
   pitch and roll are in the vehicle's own frame). `rollPerG` does the
   same for how hard it is turning, and leans the body OUT of the bend
   the way a real one does, because it is the outside springs that
   compress.

   BOTH ARE ON THE INSTANCE AND BOTH CAN BE NEGATIVE, which is the whole
   of what makes a hover carrier a different vehicle rather than a
   recoloured one. A thing on springs leans out of a bend and dips its
   nose to stop; a thing on thrust does the opposite of both, because
   what it is doing is pointing its lift somewhere else. The APC takes
   the same two lines of code with the signs turned over. See ArmyApc.

   SPRING and DAMP are what make it read as weight rather than as a
   tilt. Undamped it wobbles for ever; critically damped it slides into
   place with no character at all; at these numbers it overshoots once
   and settles in about a second, which is what a van on its springs
   does when it stops. */
const PITCH_PER_G = 0.085;       // radians per unit-a-tic-a-tic
const ROLL_PER_G = 0.020;
const PITCH_MAX = 0.11;          // and the most it will ever lean, either way
const ROLL_MAX = 0.09;
const SPRING = 0.075;
const DAMP = 0.21;
const ASLEEP = 1e-4;             // below this it has stopped moving and is left alone

export class SwatVan extends Vehicle {
  /**
   * @param fleet
   * @param def      the police van, from modelVehicle
   * @param texture  its own sheet
   * @param route    points to drive through, in order; the last is where
   *                 it stops. `x`, `y`, and on the last one `angle`,
   *                 which it squares up to once it is there
   */
  constructor(fleet, def, texture, route) {
    const start = route[0], next = route[1] || route[0];
    const sec = fleet.game.level.sectorAt(start.x, start.y);
    super(fleet, def, {
      x: start.x, y: start.y, z: sec ? sec.floor : 0,
      angle: Math.atan2(next.y - start.y, next.x - start.x),
      light: sec ? sec.light : 0.74, sky: sec ? (sec.sky ?? (sec.outdoor ? 1 : 0)) : 1,
      paint: [1, 1, 1], texture, own: true, state: 'driving',
      /* IT BURNS, JUST SLOWLY — see fireArmour in Vehicle. Eight times
         the fire to get through it and four times as long turning
         black: most of a minute against a hatchback's nine seconds. */
      fireArmour: 8, charFuse: 4,
      /* AND ROUNDS: fifty, which is two hundred-odd of the minigun's,
         a second and a half of the trigger held on one van — see
         SHOT_ARMOUR — and every one of them a hole in the bodywork */
      shotArmour: 50,
    });
    this.route = route.slice(1);
    /* HOW FAR IT STILL HAS TO GO FROM EACH POINT ON, worked out once so
       the braking can aim at the END of the route rather than at the
       next corner — which is the difference between a van that slows
       into its place and a van that slows at every bend. */
    this.tail = [];
    let acc = 0;
    for (let i = this.route.length - 1; i >= 0; i--) {
      this.tail[i] = acc;
      if (i > 0) acc += Math.hypot(this.route[i].x - this.route[i - 1].x, this.route[i].y - this.route[i - 1].y);
    }
    this.driven = 0;
    this.speed = 0;                  // units a tic, integrated
    this.pitchV = 0; this.rollV = 0; // and the two springs the body hangs on
    this.sirenTick = 0;
    this.sirenNote = 0;
    this.arrivedTic = -1;
    /* WHAT IT SOUNDS LIKE COMING, how fast it goes and how hard it hits,
       all on the instance rather than in a constant, because the APC
       behind it is the same drive with a turbine instead of a siren and
       half a ton more of it. See ArmyApc. */
    this.notes = ['siren', 'siren2'];
    this.noteEvery = SIREN_EVERY;
    this.topSpeed = DRIVE_SPEED;
    this.accel = DRIVE_ACCEL;
    this.brake = DRIVE_BRAKE;
    /* and how the body answers the two of them — see suspension, and
       see ArmyApc for a vehicle that answers them the other way round */
    this.pitchPerG = PITCH_PER_G;
    this.rollPerG = ROLL_PER_G;
    this.pitchMax = PITCH_MAX;
    this.rollMax = ROLL_MAX;
    this.runoverDmg = RUNOVER_DMG;
    this.runoverPlayer = RUNOVER_PLAYER;
  }

  tic() {
    if (this.state === 'driving') { this.drive(); return; }
    super.tic();
    /* AND THE BODY GOES ON ROCKING after it has stopped, because that is
       where the whole thing is spent: a van brakes, the nose goes down,
       it stands still and the springs push it back. Runs until the
       spring is asleep and then never again — and for a hover carrier
       that is never, because its resting angles are moving. */
    if (this.whole && !this.asleep) { this.suspension(0, 0); this.place(); }
  }

  /** How far it is, in whole units, from the next point on its route. */
  get toNext() {
    const p = this.route[0];
    return p ? Math.hypot(p.x - this.x, p.y - this.y) : 0;
  }

  /** And how far from the end of it, which is what it brakes for. */
  get toEnd() { return this.toNext + (this.tail[0] || 0); }

  /**
   * THE BODY, off two numbers and two springs. `accel` is what it did to
   * its speed this tic and `turn` is what it did to its heading; between
   * them they are every force a vehicle on a polyline can be said to
   * feel. The target angles come straight off them and the springs are
   * what make arriving at those angles look like weight.
   */
  suspension(accel, turn) {
    const wantPitch = this.restPitch +
      Math.max(-this.pitchMax, Math.min(this.pitchMax, accel * this.pitchPerG));
    const wantRoll = this.restRoll +
      Math.max(-this.rollMax, Math.min(this.rollMax, turn * this.speed * this.rollPerG));
    this.pitchV += (wantPitch - this.rz) * SPRING - this.pitchV * DAMP;
    this.rollV += (wantRoll - this.rx) * SPRING - this.rollV * DAMP;
    this.rz += this.pitchV;
    this.rx += this.rollV;
  }

  /** WHERE THE BODY SITS WHEN NOTHING IS HAPPENING TO IT, which for
   *  anything on wheels is level. A hovering one is never quite level
   *  and never quite still — see ArmyApc. */
  get restPitch() { return 0; }
  get restRoll() { return 0; }

  /** Nothing left to move: the springs have settled onto their resting
   *  angles and nothing is driving them. Checked so a parked van costs
   *  nothing for the rest of the night; a hovering one is never asleep. */
  get asleep() {
    return Math.abs(this.pitchV) < ASLEEP && Math.abs(this.rollV) < ASLEEP &&
           Math.abs(this.rz - this.restPitch) < ASLEEP && Math.abs(this.rx - this.restRoll) < ASLEEP;
  }

  drive() {
    const g = this.fleet.game;
    const p = this.route[0];
    if (!p) { this.park(); return; }
    /* the heading, eased; the position, exact */
    const want = Math.atan2(p.y - this.y, p.x - this.x);
    const d = angleDiff(want, this.yaw);
    const turn = Math.max(-DRIVE_TURN, Math.min(DRIVE_TURN, d));
    this.yaw = angleNorm(this.yaw + turn);
    /* THE SPEED, AND WHAT IT IS ALLOWED TO BE. The fastest it may go is
       whichever is smaller: its own top speed, or the speed it could
       still stop from in the distance it has left to the END of the
       route. That second one is the whole of the braking — v = sqrt(2 a
       s), the oldest trick there is — and it means the van comes off the
       ring already slowing and rolls the last two lengths into its
       place. Below a crawl it is held at a crawl, or the last unit of
       the approach takes a second and a half. */
    const was = this.speed;
    const stopping = Math.sqrt(2 * this.brake * Math.max(0, this.toEnd));
    this.speed = Math.min(this.topSpeed, stopping, this.speed + this.accel);
    this.speed = Math.max(this.speed, Math.min(1.2, this.toEnd));
    const left = this.toNext;
    const step = Math.min(this.speed, left);
    this.x += Math.cos(want) * step; this.y += Math.sin(want) * step;
    this.driven += step;
    this.roll(step);
    if (left - step < 0.5) { this.route.shift(); this.tail.shift(); }
    this.suspension(this.speed - was, turn);
    if ((g.tics & 3) === 0) { this.updateSector(); this.cz = this.ridingHeight; }
    this.place();
    this.carryBlockers();
    this.runOver();
    /* the siren: two notes, alternating, for as long as it is moving */
    if (++this.sirenTick >= this.noteEvery) {
      this.sirenTick = 0;
      g.sound?.play(this.notes[this.sirenNote], this);
      this.sirenNote ^= 1;
    }
    /* and it burns while it drives, which it could not while it was
       fireproof: a van lit in the fire lane and sent on its way arrives
       alight and goes up where it stands */
    if (this.burning > 0) this.burnTic();
  }

  /** The three cylinders, moved to under the van rather than remade:
   *  spawning three actors a tic is garbage the blockmap can do without,
   *  and a moved actor is one hash. */
  carryBlockers() {
    const bl = carBlockers(this.def, this.x, this.y, this.yaw);
    for (let i = 0; i < this.blockers.length && i < bl.length; i++) {
      const a = this.blockers[i];
      a.x = bl[i].x; a.y = bl[i].y; a.z = this.ground;
      this.fleet.game.blockmap?.moved(a);
    }
  }

  /** Anybody in front of it. Checked at the nose, against the crowd
   *  near it, and against the player. */
  runOver() {
    const g = this.fleet.game;
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    const L = this.def.length, r = carBlockRadius(this.def);
    const nx = this.x + c * 0.42 * L, ny = this.y + s * 0.42 * L;
    const near = g.blockmap ? g.blockmap.near(nx, ny, this._near || (this._near = [])) : g.actors;
    for (let i = 0; i < near.length; i++) {
      const a = near[i];
      if (a.removed || a.dead || !a.solid || a.vehicle || !a.shootable) continue;
      const rr = r + a.radius;
      if (dist2(nx, ny, a.x, a.y) > rr * rr) continue;
      a.damage(this.runoverDmg, null, { impact: true, dx: c, dy: s, force: 2.5 });
    }
    /* AND YOU, at the user's request, are LAUNCHED rather than shoved:
       the hit is one hit, hard, and carries a velocity — along the
       vehicle's heading blended with the line from its nose to you, so
       a square hit throws you down the road and a glancing one throws
       you off it — and UP, in proportion to how fast it was going, so
       a van at speed puts you in the air. Player.damage spends it; the
       grace tics on the player are what stop the same nose finding you
       again every tic while you are still in front of it, which is
       what it used to do at a shove's worth of push. */
    const p = g.player;
    if (p && !p.dead && !(p.launched > 0)) {
      const rr = r + p.radius;
      if (dist2(nx, ny, p.x, p.y) < rr * rr) {
        const sp = Math.max(0, this.speed || 0);
        const ax = p.x - nx, ay = p.y - ny;
        const ad = Math.hypot(ax, ay) || 1;
        let lx = c * 0.65 + (ax / ad) * 0.35, ly = s * 0.65 + (ay / ad) * 0.35;
        const ld = Math.hypot(lx, ly) || 1;
        lx /= ld; ly /= ld;
        const k = Math.min(30, 10 + sp * 0.55);
        const up = Math.min(17, 8 + sp * 0.25);
        p.damage(this.runoverPlayer, this, { impact: true, launch: { x: lx * k, y: ly * k, z: up, grace: 30 } });
      }
    }
  }

  /** It has arrived: squared up along the front, in the way, and a van
   *  from here on. */
  park() {
    this.state = 'parked';
    this.speed = 0;
    if (this.parkAngle !== undefined) this.yaw = this.parkAngle;
    /* THE NOSE IS STILL DOWN when it gets here and is left that way on
       purpose: the springs in tic() take it from here, and what you see
       is a van that has stopped and then settles, rather than one that
       stopped and was level about it. */
    this.updateSector();
    this.cz = this.ridingHeight;
    this.place();
    this.block(this.hover + carHeight(this.def));
    this.shoveClear();
    this.arrivedTic = this.fleet.game.tics;
    this.fleet.game.sound?.play('doorclose', this);
  }

  /** Where somebody steps out: the flank facing `toward` (a point —
   *  the shop), a little along the length, clear of the blockers. */
  door(k = 0, toward = { x: this.x, y: this.y + 1000 }) {
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    const L = this.def.length, half = carWidth(this.def) / 2;
    /* which side is nearer the shop: the left (+y in model space, which
       is -s, c in the world) or the right */
    const lx = -s, ly = c;
    const side = (toward.x - this.x) * lx + (toward.y - this.y) * ly >= 0 ? 1 : -1;
    const out = half + 26;
    const t = [0, -0.22, 0.22, -0.4, 0.4][k % 5] * L;
    return { x: this.x + c * t + lx * side * out, y: this.y + s * t + ly * side * out,
             angle: Math.atan2(ly * side, lx * side) };
  }
}

/* =====================================================================
   AND ONE THAT DOES NOT TOUCH THE ROAD

   The army's APC, which is the second thing that drives up the road and
   the first that does not drive on it. It is a SwatVan in every way
   that is about GETTING somewhere — the same polyline, the same eased
   heading, the same nose that goes through whatever is in front of it,
   the same doors — because a hover carrier coming up a frontage lane
   takes the same corners a van does, and every one of those corners is
   already measured against this map. What is different is everything
   about what it IS.

   IT FLOATS, AND IT NEVER HOLDS STILL. `hover` holds the whole vehicle
   off the tarmac and the BOB breathes it up and down, which is the
   entire trick: nothing else in this game moves when it is standing
   still, so a thing that does reads as held up by something rather than
   parked. The gap under it is not a gap you can use — the blockers are
   as tall as the hover plus the hull and they still stand ON the ground
   (see Vehicle.block), because an APC's skirts are in the way whether
   they are touching or not.

   THE BOB IS TWO SINES, not one, on periods that do not divide into one
   another: a four-second breath with a ten-second swell under it. One
   sine on its own is a metronome and the eye finds it in about three
   cycles; two is a thing being held up by something that is not quite
   managing it. And it is BIGGER WHEN IT IS PARKED — a little over half
   as much while it is moving — because a hovercraft at speed is held
   steadier by the ground under it and one standing still wallows, and
   because what the user asked for was the bob you see when it has
   stopped.

   AND IT IS NEVER LEVEL. Two more slow sines, on two more periods, put
   a degree or so of pitch and a degree and a half of roll into it and
   take them out again — see restPitch and restRoll, which is where the
   springs in SwatVan are told what "at rest" means. A parked van's
   springs settle and then cost nothing for the rest of the night; a
   parked APC's are never asleep, because what they are settling onto
   keeps moving.

   AND IT BANKS INTO ITS TURNS, AND PITCHES UP TO STOP. Which is the
   same two lines of SwatVan's suspension with both signs turned over,
   and it is turned over for a reason rather than for the look. A thing
   on springs leans OUT of a bend because the outside springs compress,
   and dips its nose to brake because the weight goes forward. A thing
   on THRUST has no springs and no weight to move: to turn it points its
   lift into the bend, and to stop it points its lift forward, so it
   banks in and it pitches nose-up. Twice the van's lean at nearly three
   times the coefficient, because a carrier heeling over into the
   frontage lane is the whole reason anybody draws one of these.

   The angles are capped where they are because of the ground: at seven
   degrees of pitch the nose drops fifteen units and at ten degrees of
   bank the low flank drops eleven, against thirty-four of hover with
   seven of bob in it. It leans as far as it can lean without putting a
   corner through the tarmac, and no further.

   AND IT BLOWS THE CAR PARK ABOUT. Whatever holds it up throws grit
   down, so there is a puff under the middle of it every few tics — hard
   and low while it is moving, an idle while it stands. This is the one
   piece of it that is not free and it is worth what it costs: it is
   what makes the hover read at a distance, where five units of bob is
   nothing.

   AND IT WEIGHS MORE. Twice the van's damage to anybody in front of it
   and half again to you, which for a vehicle this wide is most of the
   fire lane at once.

   IT DOES NOT HAVE A SIREN. Two notes still, on the same clock, but
   they are the turbine: a low sawtooth that rises and falls instead of
   a square wave that wails. See `hover` and `hover2` in js/audio.js.
   ===================================================================== */
const HOVER = 34;                // how high the skirts ride, in game units
const BOB = 7;                   // and how far it breathes, either way, parked
const BOB_DRIVING = 0.45;        // and how much of that while it is moving
const BOB_RATE = Math.PI * 2 / 140;   // one whole breath in four seconds
const SWELL_RATE = BOB_RATE * 0.41;   // and the slow one under it, in ten
const SWELL = 0.30;              // which is this much of the whole
/* the two it is never quite level on: about a degree of pitch and a
   degree and a half of roll, on two more periods that do not line up */
const IDLE_PITCH = 0.019, IDLE_PITCH_RATE = Math.PI * 2 / 191;
const IDLE_ROLL = 0.027, IDLE_ROLL_RATE = Math.PI * 2 / 233;
/* AND THE SIGNS TURNED OVER, which is what makes it a hover vehicle:
   into the bend rather than out of it, nose up to stop rather than
   down. See the note above, and suspension in SwatVan. */
const HOVER_PITCH_PER_G = -0.100;
const HOVER_ROLL_PER_G = -0.055;
const HOVER_PITCH_MAX = 0.12;    // seven degrees: the nose drops fifteen units
const HOVER_ROLL_MAX = 0.17;     // ten: the low flank drops eleven
const WASH_MOVING = 3;           // tics between downwash puffs, driving
const WASH_STANDING = 13;        // and standing
const APC_RUNOVER = 440;         // what the front of one does to a person
const APC_RUNOVER_PLAYER = 42;   // and to you
const TURBINE_EVERY = 26;        // tics between the two notes

export class ArmyApc extends SwatVan {
  constructor(fleet, def, texture, route) {
    super(fleet, def, texture, route);
    this.notes = ['hover', 'hover2'];
    this.noteEvery = TURBINE_EVERY;
    this.runoverDmg = APC_RUNOVER;
    this.runoverPlayer = APC_RUNOVER_PLAYER;
    this.bobT = pRandom();          // no two of them breathe together
    this.hover = HOVER;
    /* ARMOUR, AND MORE OF IT THAN THE VAN. Fourteen times the fire to
       get through it and six times as long going black, which against a
       hatchback's nine seconds is nearly two minutes of holding the
       stream on one. It is still not fireproof — at the user's request
       nothing on wheels or skirts is any more — it is simply the last
       thing in the lot you would choose to spend a tank on. */
    this.fireArmour = 14;
    this.charFuse = 6;
    /* and ninety against rounds: nearly four hundred of them, three
       seconds of the trigger, which is a carrier and not a van */
    this.shotArmour = 90;
    /* AND IT IS HEAVIER TO DRIVE. Slower to wind up, slower to shed it,
       and a lower top speed: a carrier is not a squad car, and the
       weight shift reads harder for it because the springs are being
       driven by a longer, flatter acceleration. */
    this.topSpeed = DRIVE_SPEED * 0.82;
    this.accel = DRIVE_ACCEL * 0.62;
    this.brake = DRIVE_BRAKE * 0.70;
    /* AND THE BODY ANSWERS THEM THE OTHER WAY ROUND. Both signs turned
       over: into the bend rather than out of it, nose up to stop rather
       than nose down, because there are no springs and no weight to
       move — there is lift, and it gets pointed somewhere. */
    this.pitchPerG = HOVER_PITCH_PER_G;
    this.rollPerG = HOVER_ROLL_PER_G;
    this.pitchMax = HOVER_PITCH_MAX;
    this.rollMax = HOVER_ROLL_MAX;
    this.cz = this.ridingHeight;
    /* it was built standing on the tarmac; stand it up and make the
       thing you cannot walk through as tall as it now is */
    this.place();
    this.block(this.hover + carHeight(this.def));
  }

  /** The height it rides at with the breath taken out, for anyone
   *  outside measuring the hover against what it is meant to be. */
  static get HOVER() { return HOVER; }
  /** And the most the breath ever takes it either side of that. */
  static get BOB() { return BOB; }

  /** THE BREATH: two sines on periods that do not divide into one
   *  another, so it never visibly repeats, and rather more of it when it
   *  is standing than when it is moving. */
  get bob() {
    const t = this.bobT;
    const k = (Math.sin(t * BOB_RATE) * (1 - SWELL) + Math.sin(t * SWELL_RATE + 2.3) * SWELL);
    return k * BOB * (this.state === 'driving' ? BOB_DRIVING : 1);
  }

  /* AND IT IS NEVER LEVEL. What the springs in SwatVan settle ONTO,
     rather than what drives them: two more slow sines, so a parked
     carrier drifts a degree one way and a degree and a half the other
     and never quite arrives anywhere. */
  get restPitch() { return Math.sin(this.bobT * IDLE_PITCH_RATE) * IDLE_PITCH; }
  get restRoll() { return Math.sin(this.bobT * IDLE_ROLL_RATE + 1.7) * IDLE_ROLL; }
  /** And so it is never asleep: what it is settling onto keeps moving. */
  get asleep() { return false; }

  tic() {
    /* the breath first, so whatever super does with cz does it at the
       height this tic is actually at */
    if (this.whole) { this.bobT += 1; this.hover = HOVER + this.bob; }
    super.tic();
    if (!this.whole) return;
    /* super recomputes cz on its own clock — every fourth tic while it
       is driving, once on arrival, never while parked — which is fine
       for a van that only moves when it is driving and is not enough
       for one that is never still. So it is set here, every tic. */
    this.cz = this.ridingHeight;
    this.place();
    this.wash();
  }

  /** The grit under it. Low and wide where the skirts are, on a clock
   *  that is four times faster while it is moving. */
  wash() {
    const g = this.fleet.game;
    const every = this.state === 'driving' ? WASH_MOVING : WASH_STANDING;
    if ((g.tics + (this.bobT | 0)) % every) return;
    const c = Math.cos(this.yaw), s = Math.sin(this.yaw);
    const L = this.def.length, W = carWidth(this.def);
    const t = ((pRandom() / 255) - 0.5) * 0.7 * L, u = ((pRandom() / 255) - 0.5) * W;
    g.fx?.puff(this.x + c * t - s * u, this.y + s * t + c * u, this.ground + 6, 30, 120);
  }
}

/* =====================================================================
   THE LOT
   ===================================================================== */
/* =====================================================================
   AND ONE THAT COMES FOR THE FIRE

   The fire brigade's truck, at the user's request: the police van
   repainted red with a water cannon on its roof, and the first thing in
   the game that is on the side of the building. It is a SwatVan in
   everything about getting somewhere — the same road, the same ring, the
   same stands (see js/brigade.js for where it is sent) — and a different
   vehicle once it has stopped: nobody gets out of it (yet), and the
   cannon goes to work.

   THE CANNON LOOKS, TURNS, AND POURS. Every CANNON_LOOK tics it picks the
   fire it will play on — a burning vehicle first, because those go up;
   then a person alight; then the nearest part of the store's fire or the
   wood's it can see from the nozzle and reach — and the turret slews
   toward it at CANNON_TURN a tic, the barrel lifting to the angle that
   lands a jet there (aimPitch in js/water.js integrates the jet's own
   flight). Once it is on, it pours, and it walks the jet a little either
   side while it does, the way a crew plays a monitor over a fire rather
   than drilling one point of it. With nothing left to put out the turret
   comes back to face the front.

   IT STANDS IN THE FIRE and takes a long time about burning: three times
   the squad van's fire armour and half again its fuse. A fire truck that
   can be lit by the fire it came to is fair; one that goes up the moment
   it parks is not a fire truck.
   ===================================================================== */
const CANNON_LOOK = 12;          // tics between choosing what to play on
const CANNON_BEST = 560;         // the distance it would rather work at
const CANNON_NEAR = 200;         // and closer than this it will not aim
/* how high over the nozzle the jet's shoulder is, which is the line
   that decides whether it can reach a fire — see findFire */
const CANNON_ARC = 160;
const CANNON_TURN = 0.045;       // radians a tic the turret slews
const CANNON_LIFT = 0.03;        // and the barrel
const CANNON_ON = 0.09;          // how close to on target before it pours
const CANNON_SWEEP = 0.07;       // how far either side it walks the jet
const HOSE_NOTE_EVERY = 9;       // tics between the hiss
const FIREHORN_EVERY = 24;       // tics between the two notes

export class FireTruck extends SwatVan {
  constructor(fleet, def, texture, route) {
    super(fleet, def, texture, route);
    this.notes = ['firehorn', 'firehorn2'];
    this.noteEvery = FIREHORN_EVERY;
    this.fireArmour = 24;
    this.charFuse = 6;
    this.gunYaw = 0;                 // the turret, against the body
    this.gunPitch = 0.12;            // the barrel
    this.target = null;              // { x, y, z, kind, ref }
    this.lookTick = 0;
    this.pouring = 0;                // tics poured, ever
    this.hoseTick = 0;
    this.reach = hoseReach() * 0.94;
    this.aimGun();
  }

  tic() {
    super.tic();
    if (this.state === 'parked' && this.gun) this.fight();
  }

  /** Where the pivot of the cannon is in the world, now. */
  pivotWorld() {
    const o = turn(toMesh(this.gun.def.pivot, this.mid, this.def.length), this.yaw, this.rx, this.rz);
    return { x: this.x + o[0], y: this.y - o[2], z: this.cz + o[1] };
  }

  /** And the muzzle, at the cannon's present yaw and elevation. */
  nozzle() {
    const L = this.def.length, c = this.gun.def, pv = this.pivotWorld();
    const dx = (c.tip[0] - c.pivot[0]) * L, dy = (c.tip[1] - c.pivot[1]) * L, dz = (c.tip[2] - c.pivot[2]) * L;
    const cp = Math.cos(this.gunPitch), sp = Math.sin(this.gunPitch);
    const fx = dx * cp - dz * sp, fz = dx * sp + dz * cp;
    const Y = this.yaw + this.gunYaw, cy = Math.cos(Y), sy = Math.sin(Y);
    return { x: pv.x + fx * cy - dy * sy, y: pv.y + fx * sy + dy * cy, z: pv.z + fz };
  }

  /** The turret and the barrel onto the mesh. */
  aimGun() {
    if (!this.gun) return;
    this.gun.yaw.rotation.y = this.gunYaw;
    this.gun.pitch.rotation.z = this.gunPitch;
  }

  /** Is this target still worth pouring on? */
  stillAlight(t) {
    const g = this.fleet.game;
    if (!t) return false;
    if (t.kind === 'box') return !!t.ref.burning;
    if (t.kind === 'car') return t.ref.whole && t.ref.burning > 0 && t.ref.state !== 'charring';
    if (t.kind === 'person') return !t.ref.dead && !t.ref.removed && t.ref.burning > 0;
    if (t.kind === 'cell') return (g.fire?.heat[t.ref] || 0) > 0;
    if (t.kind === 'tree') return g.forest?.burningCells > 0;
    return false;
  }

  /** The fire it will play on next, or null: see the note above. */
  findFire() {
    const g = this.fleet.game, lv = g.level;
    const from = this.pivotWorld();
    const R2 = this.reach * this.reach;
    const cands = [];
    /* SCORED BY HOW WELL IT CAN BE WORKED, not by how near it is: the
       nearest patch of a fire is usually the one lapping at the truck's
       own wheels, and a monitor on a roof plays on the fire in front of
       it, at a working distance, rather than on its own feet */
    const add = (x, y, z, kind, ref, bias) => {
      const d2 = dist2(from.x, from.y, x, y);
      if (d2 > R2 || d2 < CANNON_NEAR * CANNON_NEAR) return;
      cands.push({ x, y, z, kind, ref, score: Math.abs(Math.sqrt(d2) - CANNON_BEST) - bias });
    };
    for (const v of this.fleet.all) {
      if (v === this || !v.whole || !(v.burning > 0) || v.state === 'charring') continue;
      add(v.x, v.y, v.ground + 20, 'car', v, 700);
    }
    for (const a of g.actors) {
      if (a.dead || a.removed || !(a.burning > 0) || a.vehicle) continue;
      add(a.x, a.y, a.z + 20, 'person', a, 350);
    }
    /* AND THE GRID WORLD'S BOXES, which are the whole of the fire
       there. Aimed at the FRONT — the height the decay has reached,
       which comes down the box as it goes — rather than at the middle
       of it, so the jet lands on what is actually alight. */
    for (const b of g.boxes?.burningList(this._lit || (this._lit = [])) || []) {
      /* at the face rather than the middle: the middle of a box is
         inside a solid and nothing can see it — see Box.aimPoint */
      const a = b.box.aimPoint(from.x, from.y);
      add(a.x, a.y, a.z + 16, 'box', b.box, 600);
    }
    const F = g.fire;
    if (F && F.hotCells > 0) {
      const act = F.active, n = act.length, step = Math.max(1, Math.floor(n / 160));
      for (let k = 0; k < n; k += step) {
        const i = act[k];
        if (F.heat[i] < 40) continue;
        const j = i % F.plane;
        const x = F.worldX(j % F.cols), y = F.worldY((j / F.cols) | 0);
        const sec = lv.sectorAt(x, y);
        /* and the hottest of it first, by up to half a working distance */
        add(x, y, (sec ? sec.floor : 0) + 12, 'cell', i, F.heat[i]);
      }
    }
    const W = g.forest;
    if (W && W.burningCells > 0) {
      const out = this._emit || (this._emit = []);
      W.emitters(from.x, from.y, this.reach, 12, out);
      for (const e of out) add(e.x, e.y, (lv.sectorAt(e.x, e.y)?.floor || 0) + Math.min(60, e.h * 0.5), 'tree', null, 100);
    }
    cands.sort((a, b) => a.score - b.score);
    /* THE ONES THE JET CAN ACTUALLY GET TO. A monitor LOBS — the water
       leaves at a few degrees up and comes down on the fire (aimPitch in
       js/water.js integrates the flight) — so the line that matters is
       not the flat one from the nozzle. Sight is taken from the arc's
       shoulder instead, a hundred and sixty units over the nozzle,
       which clears a low thing in the way and is still stopped by a
       tall one. A wall is a wall; a garden box is not. */
    for (let k = 0; k < cands.length && k < 12; k++) {
      const c = cands[k];
      if (!lv.sightBlocked(from.x, from.y, from.z + CANNON_ARC, c.x, c.y, c.z + 10)) return c;
    }
    return null;
  }

  /** One tic of the cannon at work. */
  fight() {
    const g = this.fleet.game;
    /* a burning car or person is held until it is out; a patch of the
       store or the wood is looked at again every time, because the fire
       moves and the nearest of it moves with it */
    const due = ++this.lookTick >= CANNON_LOOK;
    if (due) this.lookTick = 0;
    const alight = this.stillAlight(this.target);
    if (!alight) this.target = null;
    if (due && (!alight || this.target.kind === 'cell' || this.target.kind === 'tree')) this.target = this.findFire();
    const t = this.target;
    let wantYaw = 0, wantPitch = 0.12, pour = false;
    if (t) {
      const pv = this.pivotWorld();
      const sweep = Math.sin(g.tics * 0.11) * CANNON_SWEEP;
      wantYaw = angleDiff(Math.atan2(t.y - pv.y, t.x - pv.x) + sweep, this.yaw);
      const d = Math.hypot(t.x - pv.x, t.y - pv.y);
      const p = aimPitch(d, pv.z - t.z);
      if (p !== null) { wantPitch = p; pour = true; }
    }
    const dy = angleDiff(wantYaw, this.gunYaw);
    this.gunYaw = angleNorm(this.gunYaw + Math.max(-CANNON_TURN, Math.min(CANNON_TURN, dy)));
    const dp = wantPitch - this.gunPitch;
    this.gunPitch += Math.max(-CANNON_LIFT, Math.min(CANNON_LIFT, dp));
    this.aimGun();
    if (pour && Math.abs(dy) < CANNON_ON + CANNON_SWEEP && Math.abs(dp) < 0.12 && g.water) {
      g.water.fire(this.nozzle(), this.yaw + this.gunYaw, this.gunPitch);
      this.pouring++;
      if (++this.hoseTick >= HOSE_NOTE_EVERY) { this.hoseTick = 0; g.sound?.play('hose', this); }
    }
  }
}

export class Vehicles {
  /**
   * @param game
   * @param texture  the fleet's one texture
   * @param def      the vehicle every bay gets. Null means an empty lot,
   *                 which is what a missing model file costs — the same
   *                 bargain every other asset in this game makes.
   */
  constructor(game, texture, def = null) {
    this.game = game;
    this.texture = texture || null;
    this.def = def;
    this.all = [];
    this.flying = [];            // chunks still in the air
    this.resting = [];           // and chunks that are not
    this.restSlabs = [];         // every settled wreck and piece, as vertices
    this.liveMesh = null;        // every parked car, in one geometry
    this.wreckMesh = null;       // and everything that has stopped moving
    this.dirty = false;
    this.restDirty = false;
  }

  /**
   * Fill the bays.
   *
   * `level.carSlots` has held a position, a heading and a variant for
   * every bay since the day the lot was laid out, off the same
   * arithmetic that drew the bay lines — so a car put at one of these is
   * genuinely in a bay rather than near one. The lot is only about
   * two-fifths full and thins towards the road, because half the town
   * has already left; that is the map's decision and this just fills
   * what it was given.
   *
   * ONE VAN, SEVENTY-SEVEN TIMES, at the user's request. It used to be
   * five civilian bodies picked off the slot's own `variant`, built out
   * of boxes and painted by projecting four drawings onto them; it is
   * now assets/models/van.glb in every bay, drawn as its author exported
   * it. What that costs is variety, and what it buys is a car park full
   * of the user's own model — and, read a certain way, a delivery fleet
   * parked outside a store called SellWrong is not the wrong joke.
   *
   * `variant` is still on every slot and is still what would pick
   * between vehicles if there were more than one; it is simply not read
   * while there is one. The drawn fleet's riot van and APC are still
   * measured and still packed in their atlas, waiting for
   * js/responders.js to drive them up the road.
   *
   * BUT THEY ARE NOT ALL THE SAME COLOUR ANY MORE, at the user's
   * request. One model in seventy-seven bays is a delivery fleet, which
   * was a joke worth one look; a car park is what this is meant to be,
   * and a car park is twelve colours of the same shape. The paint rides
   * in the vertices and the white in the sheet is isolated in the
   * shader — see PAINT above, and the INK block in js/material.js — so
   * it is still one texture and still one draw call.
   */
  place(slots) {
    if (!this.texture || !slots) return this;
    for (const slot of slots) {
      const def = this.def;
      const sec = this.game.level.sectorAt(slot.x, slot.y);
      this.all.push(new Vehicle(this, def, {
        x: slot.x, y: slot.y, z: sec ? sec.floor : 0, angle: slot.angle,
        light: sec ? sec.light : 0.74,
        sky: sec ? (sec.sky ?? (sec.outdoor ? 1 : 0)) : 1,
        paint: paintOf(slot),
      }));
    }
    this.dirty = true;
    this.rebuild();
    return this;
  }

  /** A vehicle that is not one of the lot's — a van that has driven in.
   *  It is ticked, counted and cleaned up with the rest; it is never in
   *  the slab, because it has a sheet of its own. */
  addVehicle(v) { this.all.push(v); return v; }

  /** One piece of wreckage that has stopped moving, into the slab. */
  restOf(slab) {
    this.restSlabs.push(slab);
    this.restDirty = true;
  }

  addChunk(c) { this.flying.push(c); }

  tic() {
    for (const v of this.all) v.tic();

    for (let i = this.flying.length - 1; i >= 0; i--) {
      const c = this.flying[i];
      c.tic();
      if (!c.resting) continue;
      this.flying.splice(i, 1);
      this.resting.push(c);
      if (c.slab) this.restOf(c.slab);
      /* and if the tarmac is knee deep in it, the oldest piece goes */
      if (this.resting.length > MAX_RESTING_CHUNKS) {
        const old = this.resting.shift();
        if (old.slab) {
          const at = this.restSlabs.indexOf(old.slab);
          if (at >= 0) { this.restSlabs.splice(at, 1); this.restDirty = true; }
        } else old.discard();
      }
    }
    for (const c of this.resting) c.smoulderTic();

    if (this.dirty) this.rebuild();
    if (this.restDirty) this.rebuildWrecks();
  }

  /* Both rebuilds happen at the END of the tic that dirtied them, never
     inside it: a chain reaction that takes six cars in the same tic
     rebuilds once, and a car that has just left the ground is never both
     in the slab and flying in the same frame. */
  rebuild() {
    this.dirty = false;
    this.liveMesh = mergeInto(this.liveMesh, this.texture, this.game.scene,
      this.all.filter(v => v.slab).map(v => v.slab));
  }

  rebuildWrecks() {
    this.restDirty = false;
    this.wreckMesh = mergeInto(this.wreckMesh, this.texture, this.game.scene, this.restSlabs);
  }

  /* What the HUD would say, if it said anything about the car park. */
  get wrecked() { return this.all.reduce((n, v) => n + (v.state === 'parked' ? 0 : 1), 0); }
  get count() { return this.all.length; }
}

export { GRAVITY, extentOf, lowestOf, turn, Chunk };
