/* =====================================================================
   MEWD — the people, and what is left of them
   =====================================================================

   THE PEOPLE ARE STANDEES. One drawing each, seen from every side, and
   they do not walk. That is a decision and not a shortcut: the art is a
   set of finished single-view characters from the galvarius project, and
   the honest way to use a single-view character is as a single view.
   Eight rotations invented by mirroring would look worse from seven of
   the eight, and a walk cycle invented by sliding one drawing about
   would look worse from all of them. So they stand in the aisles, they
   SWAY a little where they stand, and that is the whole of their
   animation.

   What they are for is what happens to them. A shopper has twelve
   health, which is under one tic of the stream, so touching one with
   the flame is the same as deciding to; and there is no death animation
   because there is no body. There is a fireball, thirteen pieces of
   somebody thrown outward on fire, a trail of flame behind each, and a
   splat where each one lands. The pieces put a little heat into the
   floor where they come down, which is the part that matters: a crowd
   is not just scenery to burn, it is a way of MOVING the fire. Torch the
   queue at the tills and you have started nine small fires down the
   front end.

   THE BUDGET, because a crowd of a hundred and twenty could otherwise
   put a thousand particles in the air at once: two pools, sized so that
   nine or ten people can be coming apart simultaneously and the eleventh
   simply gets fewer pieces. Both are one draw call. The splats on the
   floor are real actors, so they are capped and the oldest is taken away
   when the cap is reached — a night of this would otherwise leave a
   thousand sprites lying about.

   THE CONTRACT WITH tools/prep-people.mjs is `CELLS` below. The tool
   crunches somebody else's art down to this game's scale and pads every
   picture into a cell of exactly these sizes; the game cuts the strips
   back apart on the same numbers. One set of numbers, imported by both,
   so there is nothing to keep in step.
   ===================================================================== */

import { Particles } from './particles.js';
import { stripFrames } from './spriteload.js';
import { pRandom, dist2 } from './util.js';
import { UP, wallNormal } from './decals.js';

/* Pixels, which in this game are world units — a sprite is drawn one
   unit to the pixel, so a 62-tall shopper is 62 units of person. */
export const CELLS = {
  shoppers: { w: 40, h: 64 },
  giblets:  { w: 16, h: 16 },
  splat:    { w: 56, h: 20 },
  /* WHAT IS LEFT WHEN THE FIRE FINISHES ONE. Wider than a splat and a
     little deeper, because a person who has burned away where they
     stood leaves a heap rather than a stain — see ASH_SPRITE. */
  ash:      { w: 40, h: 18 },
  blast:    { w: 48, h: 96 },
  /* THE PEOPLE IN THE GAME WHO TURN. A trooper is drawn from five sides
     and mirrored to eight, so a cell has to hold the widest of those — a
     side view with a rifle out — and the widest thing on the sheet,
     which is a body coming apart across the floor. Sixty-four square
     holds both, for the SWAT and for the army trooper cut the same way;
     see tools/prep-troops.mjs and TROOPS below. */
  troops:   { w: 64, h: 64 },
};

/* How tall a standing adult is drawn, which is what the shoppers are
   scaled to and what everything else is scaled beside. Under the cell,
   because one of the drawings is of somebody standing on tiptoe. */
export const ADULT = 62;

/* How many of each the strips hold. The tool fails rather than write a
   strip of a different length, and the smoke test checks the files, so
   these are safe to build tables on. */
export const SHOPPERS = 17;
export const GIBLETS  = 11;
export const SPLATS   = 3;
export const ASHES    = 3;
export const BLASTS   = 26;

/* ---------------------------------------------------------------------
   THE TROOPS: the SWAT, and the army trooper cut the same way

   The sheets are the user's and they are drawn the way Doom's own
   monsters were: five views of every pose that turns — head on, a
   quarter turn, side on, three quarters, from behind — and one view of
   everything that happens on the floor. tools/prep-troops.mjs cuts a
   sheet into one strip in THIS order, the turned frames first at five
   cells each and the flat ones after, and the two lists on each entry
   below are the whole of the contract between the tool and addTroops.

     A B C D   the walk, four frames
     E         aiming, the rifle up
     F         firing — orange, the muzzle flash on the drawing, and
               fullbright in the state table for it
     G         the rifle at the hip: standing about, and the flinch
     H I J K   dying, on the way down
     L M N     down, three frames of it, and the last one for ever
     O to W    coming apart, nine frames, the last held

   `height` is what the standing figure is scaled to. Sixty, a shade
   under the crowd's sixty-two, and the reason is the frame of somebody
   coming apart, which is taller than the somebody: at sixty-four for
   the figure that frame is sixty-eight and the cell is over the
   sixty-four-pixel rule everything drawn in this game keeps. Two
   pixels off a helmet is nothing; a rule with one exception is.

   `lift` is the tone curve the tool puts the sheet through on the way
   in — every channel raised to that power — because the sheets were
   painted for a bright ground and the game is a car park at night, and
   light is multiplied in linear: the SWAT's navy is two per cent of
   white there and came out a silhouette. The army trooper is drawn in
   tan and olive, three and a half times brighter in linear than the
   navy, and gets a quarter of the lift, enough to open the shadows in
   the olive without turning the uniform pale.

   AND THE ARMY IS IN THE GAME NOW. The sheet was cut and left sitting
   here for a while at the user's request — cut now, built later — and
   what built it was the APC arriving: a hover carrier to bring them up
   the road, which is the piece that was missing. One entry here is all
   the table knows about either of them; the states are stamped out of
   one generator (see THE TROOPS in js/states.js), the stand-ins out of
   one drawing (js/sprites.js), and the force that drives them up the
   road out of one row (FORCES in js/responders.js). The super army is a
   third entry in each of those four places and nothing else, which is
   the whole reason any of them are tables.
   ------------------------------------------------------------------- */
export const TROOPS = {
  SWAT: {
    sprite: 'SWAT', turn: 'ABCDEFG', flat: 'HIJKLMNOPQRSTUVW', views: 5, height: 60, lift: 0.62,
    sheet: 'art/people/police_assault_sheet.png', strip: 'assets/people/swat.png',
  },
  /* the same sixty, so the two stand the same height side by side; the
     two floor frames of theirs that come out wider than the cell at
     that scale are trimmed at the edge by the tool, not shrunk */
  ARMY: {
    sprite: 'ARMY', turn: 'ABCDEFG', flat: 'HIJKLMNOPQRSTUVW', views: 5, height: 60, lift: 0.85,
    sheet: 'art/people/army_sheet.png', strip: 'assets/people/army.png',
  },
};
for (const t of Object.values(TROOPS)) t.cells = t.turn.length * t.views + t.flat.length;

/* the SWAT's own, by name, for the state table and the stand-ins */
export const SWAT_SPRITE = TROOPS.SWAT.sprite;
export const SWAT_TURN   = TROOPS.SWAT.turn;
export const SWAT_FLAT   = TROOPS.SWAT.flat;
export const SWAT_VIEWS  = TROOPS.SWAT.views;
export const SWAT_HEIGHT = TROOPS.SWAT.height;
export const SWAT_CELLS  = TROOPS.SWAT.cells;

/* WHICH DRAWING EACH OF THE EIGHT ROTATIONS IS, and whether it is the
   mirror. Rotation 0 is head on and they go anticlockwise as seen from
   above, which is the direction Actor.render counts in: 1 is the
   trooper turned to face your right, showing you their left side. The
   sheets' quarter, side and three-quarter views are drawn facing LEFT —
   the rifle points left, so it is their right side you are looking at
   — which makes those three drawings rotations 7, 6 and 5 as they are,
   and 1, 2 and 3 in the mirror. Doom's sprites kept the same five and
   the same trick. Both sheets are drawn this way. */
export const TROOP_ROTATIONS = [
  { view: 0, mirror: false },   // 0: head on
  { view: 1, mirror: true },    // 1: quarter, facing your right
  { view: 2, mirror: true },    // 2: side on, facing your right
  { view: 3, mirror: true },    // 3: three quarters away, to the right
  { view: 4, mirror: false },   // 4: from behind
  { view: 3, mirror: false },   // 5: three quarters away, to the left
  { view: 2, mirror: false },   // 6: side on, facing your left
  { view: 1, mirror: false },   // 7: quarter, facing your left
];

/* Sprite set names. A shopper is its own set with one frame in it, so
   that ACTORS.SHOPPER can pick between them with the `variants` hook
   the cars will use — see Actor.render. */
export const SHOPPER_SPRITE = 'SHO';    // SHO0 .. SHO16, frame A
export const SPLAT_SPRITE   = 'BLU';    // BLU0 .. BLU2,  frame A
export const ASH_SPRITE     = 'ASH';    // ASH0 .. ASH2,  frame A
export const BLAST_SPRITE   = 'BLST';   // one set, frames A .. Z

/* --------------------------------------------------------------------
   Getting the strips into the bank
   ------------------------------------------------------------------ */
/** One cell per set, under SHO0, SHO1, ... — every side the same. */
export function addStandees(bank, img, opts = {}) {
  const frames = stripFrames(img, CELLS.shoppers.w);
  frames.forEach((p, i) => bank.addFrame(SHOPPER_SPRITE + i, 'A', new Array(8).fill(p), opts));
  return frames.length;
}

/** The same shape for the splats, which vary by actor rather than by
 *  frame for exactly the same reason. */
export function addSplats(bank, img, opts = {}) {
  const frames = stripFrames(img, CELLS.splat.w);
  frames.forEach((p, i) => bank.addFrame(SPLAT_SPRITE + i, 'A', new Array(8).fill(p), opts));
  return frames.length;
}

/** A troops strip into the bank, under the entry's own sprite name:
 *  eight views a frame for the turned ones, built from five drawings
 *  and three mirrors, and the same drawing eight times for everything
 *  that happens on the floor. `key` is SWAT or ARMY — see TROOPS. */
export function addTroops(bank, img, key, opts = {}) {
  const t = TROOPS[key];
  if (!t) throw new Error(`no troops called ${key}`);
  const cells = stripFrames(img, CELLS.troops.w);
  if (cells.length !== t.cells)
    throw new Error(`${t.strip} holds ${cells.length} cells, js/people.js expects ${t.cells}`);
  let at = 0;
  for (const L of t.turn) {
    const views = cells.slice(at, at + t.views);
    at += t.views;
    const mirrored = views.map(p => p.mirrored());
    bank.addFrame(t.sprite, L, TROOP_ROTATIONS.map(r => (r.mirror ? mirrored : views)[r.view]), opts);
  }
  for (const L of t.flat) bank.addFrame(t.sprite, L, new Array(8).fill(cells[at++]), opts);
  return cells.length;
}

/* --------------------------------------------------------------------
   Coming apart
   ------------------------------------------------------------------ */
export const GIB = {
  count: 13,          // pieces of a person
  /* Thrown HARD and wide. The first pass at these numbers dropped
     everything in a two-metre circle, which reads as a person falling
     over rather than a person going off: at eight units a tic with very
     little drag a piece clears sixty or seventy before it lands, so the
     thirteen of them end up spread across an aisle and over the shelf
     into the next one. */
  speedMin: 1.8, speedMax: 8.0,
  riseMin: 3.0,  riseMax: 8.5,
  gravity: -0.5,
  drag: 0.985,
  lifeMin: 55, lifeMax: 110,
  sizeMin: 9, sizeMax: 15,
  trailEvery: 2,      // tics between flames off a piece in the air
  splatChance: 90,    // out of 255, per piece that lands
  maxSplats: 140,     // sprites left lying about before the oldest goes
};

/* --------------------------------------------------------------------
   AND BLOWN APART, which is a different thing from coming apart

   At the user's request: "i also want people to literally explode into
   viscera and gore chunks when hit by a rocket in a more extreme way".
   The burst above is what EVERY death of a shopper is — a flame, a
   fire, a bore, a van — and it is sized for that: thirteen pieces in
   a two-aisle circle, on fire. A warhead going off in somebody is not
   that. It is the most violent thing that can happen to a person in
   this game and it should look it, so a rocket kill is the burst AND
   THEN THIS, on top of it (see Giblets.eviscerate, and MissileSystem.
   detonate in js/missiles.js, which is the only thing that calls it):

     MANY MORE PIECES, and not on fire. Viscera, not embers: the same
       gore art, a wet dark tint on some of it, sixty of them against
       thirteen, and they trail BLOOD through the air rather than flame.
     THROWN AWAY FROM THE BLAST, not in a ring. The warhead has a side
       it went off on, and the body goes the other way — a cone round the
       line from the blast through the body, wide enough that the back
       of it still gets some, and faster and higher than any burst: at
       fifteen units a tic a piece clears a shop aisle and the next one.
     A SPRAY OF BLOOD in the air, a mist and drops both (Effects.
       bloodSpray), hundreds of them for the second it takes.
     AND THE ROOM PAINTED. A great pool where they stood, a ring of
       spatters thrown out across the floor round it, and blood up every
       wall in reach in every direction — Decals.sprayWalls with a cone
       of the whole circle — the nearer the wall, the bigger the mark.
       Every piece that lands leaves its own spatter too, on the wall it
       hit if it hit one, facing the right way.

     count       pieces
     speed       units a tic, min..max, before `force`
     rise        units a tic up, min..max
     cone        radians either side of the throw
     spray       blood particles in the air
     floor       spatters thrown across the floor, and how far
     walls       rays to the walls round them, and how far
     pool        the size of the pool under them
   ------------------------------------------------------------------- */
export const GORE = {
  count: 60,
  speedMin: 4.0, speedMax: 15.0,
  riseMin: 5.0,  riseMax: 15.0,
  cone: 1.9,
  sizeMin: 7, sizeMax: 17,
  lifeMin: 70, lifeMax: 150,
  gravity: -0.55,
  drag: 0.988,
  spray: 90,
  floor: 12, floorReach: 190,
  walls: 20, wallReach: 360,
  pool: 118,
  trailEvery: 3,       // tics between blood off a piece in the air
};
/* the wet dark ones, which is the tint that says viscera rather than
   meat — multiplied onto the gore art the way the frozen one is */
const WET_GIB = [0.78, 0.55, 0.55];

/* What a piece of somebody frozen is coloured. Multiplied onto the gore
   art, so it is a lighting decision and not a repaint: red barely moves,
   green and blue lift hard, and dark red meat comes out the pale
   grey-pink of something out of a freezer. */
const FROZEN_GIB = [1.0, 1.45, 1.85];

export class Giblets {
  /**
   * @param game
   * @param art  { giblets: {texture, frames}, trail: {texture, frames} }
   *             or null, headless
   */
  constructor(game, art = null) {
    this.game = game;
    /* The pieces themselves: cut-out art, lit by the room like anything
       else, so a hand landing in a dark aisle is dark. */
    this.chunks = new Particles({
      /* seven hundred and twenty and not two hundred and sixty since
         the warhead: one kill by it is sixty pieces, and a salvo of
         four through a queue is four of those at once */
      max: 720, texture: art?.giblets?.texture || null, frames: art?.giblets?.frames || GIBLETS,
      blend: 'cutout', fullbright: false, light: 0.9, name: 'giblets', renderOrder: 13, nearShrink: 80,
    });
    /* And the fire coming off them: the same fireballs the gun fires,
       small, additive, and gone in a third of a second, which is what
       turns thirteen tumbling objects into thirteen comets. */
    this.trail = new Particles({
      max: 300, texture: art?.trail?.texture || null, frames: art?.trail?.frames || 8,
      blend: 'add', fullbright: true, name: 'gibtrail', renderOrder: 11, nearShrink: 30,
    });
    /* AND A SECOND POOL FOR THE COLD ONES, which is not tidiness — it
       is the bug that shipped for about ten minutes. A hot piece of
       somebody trails fire behind it in the air, and back when landing
       also lit the floor, shattering a frozen shopper down the middle of
       the beans aisle set the beans aisle on fire — the exact opposite
       of what the extinguisher is for. Neither pool lights anything now
       (see _land), but they are still not the same object: one comes off
       a body that went up and burns all the way down, the other is ice
       and arrives with a wet noise and a breath of vapour. Same art,
       same ballistics; what they ARE is the difference, so they are a
       different pool with a different tic. */
    this.shards = new Particles({
      max: 200, texture: art?.giblets?.texture || null, frames: art?.giblets?.frames || GIBLETS,
      blend: 'cutout', fullbright: false, light: 1.0, name: 'shards', renderOrder: 13, nearShrink: 80,
    });
    this.splats = [];
    this.pools = 0;              // how many pools of blood it has left, for the test
    this.bursts = 0;
    this.shatters = 0;
    this.ashes = 0;
    this.eviscerations = 0;
  }

  attach(scene) { this.chunks.attach(scene); this.shards.attach(scene); this.trail.attach(scene); }

  /* ------------------------------------------------------------------
     The burst
     ------------------------------------------------------------------ */
  /** Somebody is no longer a person. `a` is the actor it happened to. */
  burst(a) {
    const g = this.game;
    this.bursts++;
    g.sound?.play('gib', a);

    /* The fireball, standing on the floor where they were. It is an
       actor and not a particle because a particle is square and this is
       twice as tall as it is wide. */
    g.spawn('BLAST', a.x, a.y, a.z);

    /* A pool under them straight away, so there is something there even
       if every piece flies off somewhere else. */
    this.splat(a.x, a.y, a.z);

    /* AND EVERYBODY WHO SAW IT LEAVES. This is the loudest thing that
       happens in the game and it happens to a person, so it clears a
       much wider circle than the fire itself does: torch one at the
       tills and the whole front end is running before the pieces land. */
    g.scare?.(a.x, a.y, 900);

    for (let k = 0; k < GIB.count; k++) {
      const ang = (pRandom() / 255) * Math.PI * 2;
      const sp = GIB.speedMin + (pRandom() / 255) * (GIB.speedMax - GIB.speedMin);
      const size = GIB.sizeMin + (pRandom() / 255) * (GIB.sizeMax - GIB.sizeMin);
      this.chunks.spawn({
        x: a.x, y: a.y, z: a.z + a.height * (0.25 + (pRandom() / 255) * 0.6),
        vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
        vz: GIB.riseMin + (pRandom() / 255) * (GIB.riseMax - GIB.riseMin),
        life: GIB.lifeMin + (pRandom() % (GIB.lifeMax - GIB.lifeMin)),
        size0: size, size1: size,
        c0: [1, 1, 1], c1: [1, 1, 1], a0: 1, a1: 1,
        frame: pRandom() % GIBLETS,
        drag: GIB.drag, gravity: GIB.gravity,
      });
    }
  }

  /* ------------------------------------------------------------------
     BLOWN APART BY A WARHEAD — see GORE for what and why. `a` is who,
     `at` is where the warhead went off, and `force` scales the whole
     throw: one for a body in the blast, more for the one it went off
     IN. Nothing for a thing that does not bleed.
     ------------------------------------------------------------------ */
  eviscerate(a, at = null, force = 1) {
    const g = this.game;
    if (!a || a.vehicle || a.frozen) return 0;
    this.eviscerations++;
    g.sound?.play('gib', a);
    const mid = a.z + (a.height > 8 ? a.height : 56) * 0.5;
    /* which way the body goes: away from the blast, and up with it if
       the blast was under them */
    let dx = at ? a.x - at.x : 0, dy = at ? a.y - at.y : 0;
    const dz = at ? Math.max(0, mid - at.z) : 0;
    const dl = Math.hypot(dx, dy);
    const dir = dl > 1 ? Math.atan2(dy, dx) : null;
    if (dl > 1) { dx /= dl; dy /= dl; } else { dx = 0; dy = 0; }

    /* THE PIECES */
    for (let k = 0; k < GORE.count; k++) {
      const spin = (pRandom() / 255) * Math.PI * 2;
      const ang = dir === null ? spin : dir + ((pRandom() / 128) - 1) * GORE.cone;
      const sp = (GORE.speedMin + (pRandom() / 255) * (GORE.speedMax - GORE.speedMin)) * force;
      const size = GORE.sizeMin + (pRandom() / 255) * (GORE.sizeMax - GORE.sizeMin);
      const wet = (k & 1) === 0 ? WET_GIB : [1, 1, 1];
      this.chunks.spawn({
        x: a.x, y: a.y, z: a.z + 4 + (pRandom() / 255) * Math.max(8, a.height > 8 ? a.height : 56) * 0.9,
        vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
        vz: (GORE.riseMin + (pRandom() / 255) * (GORE.riseMax - GORE.riseMin)) * (0.8 + 0.2 * force) + dz * 0.02,
        life: GORE.lifeMin + (pRandom() % (GORE.lifeMax - GORE.lifeMin)),
        size0: size, size1: size,
        c0: wet, c1: wet, a0: 1, a1: 1,
        frame: pRandom() % GIBLETS,
        drag: GORE.drag, gravity: GORE.gravity, kind: 2,
      });
    }

    /* THE SPRAY, in the air: half of it thrown with the pieces and half
       of it every way at once */
    g.fx?.bloodSpray?.(a.x, a.y, mid, dx, dy, 0.4, GORE.spray >> 1, 1.2 * force);
    g.fx?.bloodSpray?.(a.x, a.y, mid, 0, 0, 0, GORE.spray >> 1, 0.9 * force);
    for (let k = 0; k < 6; k++) g.fx?.bloodPuff?.(a.x, a.y, mid + (k - 3) * 6);

    /* AND THE ROOM. The pool where they stood, bigger than any other in
       the game; the spatters across the floor, thrown out the way the
       pieces went; and blood up every wall round them. */
    const D = g.decals;
    let marks = 0;
    if (D) {
      const sec = g.level?.sectorAt?.(a.x, a.y);
      const floor = sec ? (a.z ?? sec.floor) : a.z;
      this.splat(a.x, a.y, floor, GORE.pool * (0.85 + 0.3 * (pRandom() / 255)));
      marks++;
      for (let k = 0; k < GORE.floor; k++) {
        const ang = dir === null || (k & 3) === 3 ? (pRandom() / 255) * Math.PI * 2
                                                  : dir + ((pRandom() / 128) - 1) * GORE.cone;
        const d = 20 + (pRandom() / 255) * GORE.floorReach;
        const c = Math.cos(ang), s = Math.sin(ang);
        /* only as far as the floor goes: a spatter on the far side of a
           wall is a spatter through it */
        const wall = g.level?.rayHitWall?.(a.x, a.y, floor + 4, a.x + c * d, a.y + s * d, floor + 4);
        const far = wall ? Math.max(0, wall.t * d - 6) : d;
        D.blood(a.x + c * far, a.y + s * far, floor, UP, c, s, 0, 34 + (pRandom() / 255) * 50);
        marks++;
      }
      marks += D.sprayWalls?.(a.x, a.y, mid, dx || 1, dy, 0.05, GORE.walls, GORE.wallReach, Math.PI, 1.5) || 0;
    }
    return marks;
  }

  /* ------------------------------------------------------------------
     AND THE COLD VERSION OF THE SAME THING

     Somebody frozen solid and then hit does not come apart the way
     somebody on fire does, and the difference is the whole reason this
     is a second method rather than a flag on the first.

     NO FIREBALL AND NO SCARE. A burst is an explosion — it lights the
     floor, it throws a column of flame up where the person was, and
     everybody within nine hundred units runs. Shattering is quiet: a
     crack and a scatter, and the shopper four feet away carries on
     looking at the beans. That is not an oversight, it is the mechanic:
     a player who wants to clear an aisle without starting a stampede
     now has a way to do it, and it is the only way there is.

     BLOODY AND FROZEN, as asked, and one tint does both. The giblet art
     is gore — dark reds — and the pieces are drawn through a colour that
     lifts the blue and green hard and the red barely: what comes out is
     meat that has gone pale and cold rather than meat with a blue light
     on it. Every piece keeps its own drawing; only the light on it is
     cold.

     THE PIECES GO FURTHER AND DROP HARDER, because they are ice rather
     than burning person: no rise to speak of, more sideways, and they
     skitter. And they leave the same pool behind them, because whatever
     the temperature, that part is unchanged.
     ------------------------------------------------------------------ */
  shatter(a, blow = {}) {
    const g = this.game;
    this.shatters++;
    g.sound?.play('shatter', a);
    this.splat(a.x, a.y, a.z);
    /* WHICH WAY IT WAS SWUNG, if anything said. A blow with a direction
       on it throws the pieces along that direction inside a cone, and
       throws them harder; a blow without one — a stray particle, a car
       going up, the tip of a boxcutter — scatters them in a ring the way
       it always did. The cone is deliberately WIDE, two thirds of the
       way to a half-circle either side: a block of ice hit with a hammer
       does not come apart into a beam of shards, it comes apart mostly
       forwards. See Actor.shatter, and Game.impact for who supplies it.

       `force` scales the throw and is the number a weapon turns up to
       make a hit feel heavier. One is a shove; three is a swing that
       puts somebody through the freezer aisle. */
    const dir = (blow.dx || blow.dy) ? Math.atan2(blow.dy ?? 0, blow.dx ?? 0) : null;
    const CONE = 1.05;                      // ± 60°, so the back of it still gets some
    const force = Math.max(0.2, blow.force ?? 1);
    for (let k = 0; k < GIB.count + 4; k++) {
      const spin = (pRandom() / 255) * Math.PI * 2;
      const ang = dir === null ? spin : dir + ((pRandom() / 128) - 1) * CONE;
      const sp = (GIB.speedMin + (pRandom() / 255) * (GIB.speedMax - GIB.speedMin) * 1.25) * force;
      const size = GIB.sizeMin * 0.7 + (pRandom() / 255) * (GIB.sizeMax - GIB.sizeMin);
      this.shards.spawn({
        x: a.x, y: a.y, z: a.z + a.height * (0.15 + (pRandom() / 255) * 0.7),
        vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
        vz: GIB.riseMin * 0.35 + (pRandom() / 255) * GIB.riseMax * 0.4,
        life: GIB.lifeMin + (pRandom() % (GIB.lifeMax - GIB.lifeMin)),
        size0: size, size1: size,
        c0: FROZEN_GIB, c1: FROZEN_GIB, a0: 1, a1: 1,
        frame: pRandom() % GIBLETS,
        drag: GIB.drag, gravity: GIB.gravity * 1.25,
      });
    }
    /* and a breath of it hanging where they stood */
    g.fx?.frostPuff?.(a.x, a.y, a.z + a.height * 0.5);
  }

  /* ------------------------------------------------------------------
     WHAT COMES OUT OF A HEAD WITH A DRILL IN IT

     A spurt: one or two small pieces off the top of the head, thrown
     up and a little out, that come down over the next second and land
     as blood does. The same pieces the burst throws — there is no
     smaller gore drawn — at half the size and a fifth of the speed, so
     they read as a fountain and not a firework. They carry `kind` 1,
     which is the one thing that tells the tic below not to put fire on
     them: a piece off a burning body trails flame, a piece off a
     drilled one does not.
     ------------------------------------------------------------------ */
  spurt(a, n = 1 + (pRandom() & 1)) {
    for (let k = 0; k < n; k++) {
      const ang = (pRandom() / 255) * Math.PI * 2;
      const sp = 0.4 + (pRandom() / 255) * 1.6;
      const size = GIB.sizeMin * 0.45 + (pRandom() / 255) * 3;
      this.chunks.spawn({
        x: a.x, y: a.y, z: a.z + a.height * 0.92,
        vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
        vz: 2.2 + (pRandom() / 255) * 3.8,
        life: 30 + (pRandom() % 30),
        size0: size, size1: size,
        c0: [1, 1, 1], c1: [1, 1, 1], a0: 1, a1: 1,
        frame: pRandom() % GIBLETS,
        drag: 0.985, gravity: GIB.gravity, kind: 1,
      });
    }
  }

  /** THE OTHER THING LEFT ON THE FLOOR, and it goes on the same shelf
   *  as the splats: one cap across both, because what a long night must
   *  not end in is a carpet of sprites, and the floor does not care
   *  which kind they are. See Actor.collapse. */
  ashPile(a) {
    this.ashes++;
    const g = this.game;
    const p = g.spawn('ASH', a.x, a.y, a.z + 1, { variant: pRandom() % ASHES });
    this.splats.push(p);
    while (this.splats.length > GIB.maxSplats) this.splats.shift()?.remove();
    return p;
  }

  /** What is left on the floor: A POOL OF BLOOD, and it is a decal now
   *  rather than a flat sprite, at the user's request — a box-projected
   *  puddle that spreads over its first seconds and dries at the rim
   *  (js/decals.js, Decals.pool). Capped by the decals' own ring, so a
   *  long night does not end in a carpet of them. */
  splat(x, y, z, size = 0) {
    this.pools++;
    return this.game.decals ? this.game.decals.pool(x, y, z, size) : -1;
  }

  /* ------------------------------------------------------------------
     One tic
     ------------------------------------------------------------------ */
  tic() {
    const g = this.game, lv = g.level, C = this.chunks;

    C.tic((i, nx, ny, nz) => {
      const x = C.x[i], y = C.y[i], z = C.z[i];
      /* A piece that goes through the frozen aisle wall and lands in the
         car park is funny exactly once. */
      const wall = lv.rayHitWall(x, y, z, nx, ny, nz);
      /* ON THE WALL IT HIT, facing the side it came from — it used to
         be laid as though every wall were a floor */
      if (wall) { this._land(wall.x, wall.y, wall.z, C.kind[i], wall.line ? wallNormal(wall.line, x, y) : UP, C.vx[i], C.vy[i]); return true; }
      const sec = lv.sectorAt(nx, ny);
      const floor = sec ? sec.floor : 0;
      if (nz <= floor + 1) { this._land(nx, ny, floor, C.kind[i], UP, C.vx[i], C.vy[i]); return true; }
      return false;
    });

    /* the flame off each piece still in the air — except the ones off
       a drilled head, which were never alight (see spurt) */
    if (C.count) {
      const phase = C.tics;
      for (let i = 0; i < C.max; i++) {
        if (!C.alive[i] || C.kind[i] === 1) continue;
        /* A PIECE OFF A WARHEAD TRAILS BLOOD, not fire: it was never
           alight, it was blown out of somebody */
        if (C.kind[i] === 2) {
          if ((phase + i) % GORE.trailEvery === 0 && (i & 1) === 0)
            g.fx?.bloodSpray?.(C.x[i], C.y[i], C.z[i], -C.vx[i], -C.vy[i], 0, 1, 0.15);
          continue;
        }
        if ((phase + i) % GIB.trailEvery) continue;
        this.trail.spawn({
          x: C.x[i], y: C.y[i], z: C.z[i],
          vx: C.vx[i] * 0.3, vy: C.vy[i] * 0.3, vz: C.vz[i] * 0.3 + 0.5,
          life: 9 + (pRandom() % 5),
          size0: 7, size1: 17,
          c0: [1.0, 0.9, 0.62], c1: [1.0, 0.3, 0.06],
          a0: 0.5, a1: 0,
          frame: pRandom() & 7, frameRate: 0.6,
          drag: 0.94, gravity: 0.06,
        });
      }
    }
    this.trail.tic();

    /* and the cold ones, which fly the same way and arrive differently:
       no trail behind them and no heat under them, just a wet noise and
       a mark on the floor */
    this.shards.tic((i, nx, ny, nz) => {
      const x = this.shards.x[i], y = this.shards.y[i], z = this.shards.z[i];
      const wall = lv.rayHitWall(x, y, z, nx, ny, nz);
      if (wall) { this._landCold(wall.x, wall.y, wall.z); return true; }
      const sec = lv.sectorAt(nx, ny);
      const floor = sec ? sec.floor : 0;
      if (nz <= floor + 1) { this._landCold(nx, ny, floor); return true; }
      return false;
    });
  }

  /** A piece has come down: a splat sometimes, a spit of sparks always,
   *  and NOTHING THAT CATCHES.
   *
   *  IT USED TO LIGHT THE FLOOR WHERE IT LANDED, and that was the single
   *  biggest reason the store burnt down without the player. Thirteen
   *  pieces thrown seventy units in every direction is thirteen new
   *  fires in a ring round the body, most of them across the aisle the
   *  person was running down — so one shopper going off in a crowd
   *  started a chain that crossed the shop through cross-aisles nobody
   *  had carried fire over. It was the best-looking mechanic in the game
   *  and it was also an automatic win. The pieces still come off alight,
   *  because a body going up is a body going up; they simply do not hand
   *  the fire on any more. Carrying it is the player's job. */
  _land(x, y, z, kind = 0, n = UP, vx = 0, vy = 0) {
    const g = this.game;
    /* A PIECE OF VISCERA off a warhead lands WET: a big spatter thrown
       the way it was flying, on whatever it hit, and a pool under it one
       time in four — not every time, or sixty pieces is sixty pools and
       the ring has eaten the room's walls by the time they are down. */
    if (kind === 2) {
      const sp = Math.hypot(vx, vy) || 1;
      g.decals?.blood(x, y, z, n, vx / sp, vy / sp, n === UP ? 0 : -0.4, 26 + Math.random() * 30);
      if (n === UP && (pRandom() & 3) === 0) this.splat(x, y, z, 28 + Math.random() * 24);
      return;
    }
    /* a piece that was never alight lands as blood, not as sparks */
    if (kind !== 1) g.decals?.blood(x, y, z, n, Math.random() - 0.5, Math.random() - 0.5, 0, 12 + Math.random() * 16);
    if (n === UP && pRandom() < GIB.splatChance) this.splat(x, y, z, 24 + Math.random() * 16);
  }

  /** And a cold one, which is the same minus every single thing that
   *  was warm about it. */
  _landCold(x, y, z) {
    /* ice does not bleed: a piece of somebody frozen solid lands as a
       piece of ice, and leaves nothing but the cold coming off it */
    if ((pRandom() & 3) === 0) this.game.fx?.frostPuff?.(x, y, z + 6, 12, 24);
  }

  render(billboardRot) {
    this.chunks.render(billboardRot);
    this.shards.render(billboardRot);
    this.trail.render(billboardRot);
  }

  get liveCount() { return this.chunks.count + this.shards.count + this.trail.count; }
}

/* --------------------------------------------------------------------
   Standing about

   Not an animation — a standee has one drawing — but not a statue
   either. Every shopper gets a phase off its own id and leans, slowly,
   about an inch and a half either way, with a smaller bob at twice the
   rate. Across a shop floor of a hundred of them that reads as a room
   with people in it rather than a room with cardboard in it, and it
   costs two sines an actor a frame.
   ------------------------------------------------------------------ */
export const SWAY = {
  lean: 1.3, bob: 0.7, rate: 0.055,
  /* AND HARDER WHEN IT IS RUNNING. There is one drawing, so a running
     shopper is a standing shopper that is moving — which on its own
     reads as a cardboard cutout being dragged along the floor. Four
     times the rate and three times the bob turns the same drawing into
     something scurrying, and it costs the two sines it already cost. */
  runRate: 4.0, runLean: 1.6, runBob: 3.0,
};

/* ONE object, reused. This is called once per shopper per frame and
   allocating a hundred and forty little vectors a frame to throw away is
   exactly the kind of garbage a fixed-tic loop does not want. The caller
   reads it before calling again; Actor.render does. */
const _sway = { dx: 0, dy: 0, dz: 0 };
export function swayOf(actor, tics) {
  /* the phase, and the DIRECTION of the lean, both come off the actor's
     own id — so no two of them lean together and no two of them lean the
     same way, which is the whole of the trick */
  const run = actor.panic > 0;
  const t = (tics + actor.id * 37) * SWAY.rate * (run ? SWAY.runRate : 1);
  const lean = Math.sin(t) * SWAY.lean * (run ? SWAY.runLean : 1);
  _sway.dx = Math.cos(actor.id) * lean;
  _sway.dy = Math.sin(actor.id) * lean;
  _sway.dz = Math.abs(Math.sin(t * 2 + actor.id)) * SWAY.bob * (run ? SWAY.runBob : 1)
           - (run ? SWAY.bob : 0);
  return _sway;
}

/** Who is near enough to notice, for whatever ends up wanting to know —
 *  the responders will. Cheap, and here rather than in game.js because
 *  it is about the crowd. */
export function crowdNear(game, x, y, radius) {
  const r2 = radius * radius, out = [];
  for (const a of game.actors)
    if ((a.type === 'SHOPPER' || a.type === 'TOWNIE') && !a.dead && !a.removed &&
        dist2(a.x, a.y, x, y) < r2) out.push(a);
  return out;
}
