/* =====================================================================
   MEWD — a hole through a wall
   =====================================================================

   AT THE USER'S REQUEST: "any structure in the path of the beam has a
   hole blown through it, the hole will then decay into debris and
   burning". This file is the hole.

   AND THE BEAM NO LONGER CALLS IT, at the user's later request: "still
   shooting holes through stuff, i just want massive interesting decals,
   no geometry changes". The positron lance stops at the first wall and
   leaves a SEAR there instead (js/beam.js, js/decals.js), so nothing in
   the game cuts a hole today. The machinery below is kept, whole and
   tested, because everything that READS a hole — the renderer, the
   collision, the bullets, the sight line — still does, and the next
   thing that wants to open a wall should not have to rebuild it.

   ---------------------------------------------------------------------
   WHY IT IS NOT A DECAL

   The game already has a decal system, and a very big scorch on a wall
   would have been half an hour's work. It would also have been a
   PICTURE of a hole: you could not see through it, shoot through it or
   walk through it, and the first thing a player does after firing a
   two-hundred-unit column of plasma through the front of a house is
   walk into the house through the front of it. A hole that is only a
   picture is a lie that is found out immediately.

   So it is geometry. A wall in this game is a LINE (js/level.js), drawn
   as a quad spanning the line's length and some interval of height. A
   hole is the statement that a RECTANGLE of that quad is no longer
   there — and everything else in this file is the arithmetic of saying
   that, once, in a form that the renderer, the collision, the bullets
   and the sight line can all read.

   ---------------------------------------------------------------------
   THE COORDINATES, AND WHY THEY ARE THESE

   A breach is { t0, t1, z0, z1 }:

     t   how far along the line, as a FRACTION of its length, because
         that is what js/mapgeo.js's addQuad already takes as `span` —
         it was built for the two pieces of wall either side of a
         gable's ridge, and a hole is the same question asked twice
     z   world height, in the game's own units, because that is what
         every other height in the engine is and a hole has to be
         comparable with a floor, a ceiling and a player's eye

   ---------------------------------------------------------------------
   PUNCHING MERGES RATHER THAN APPENDS

   The beam is out for three to five seconds and punches on its
   structural clock, which is a dozen times a second: a wall the column
   is sitting on would collect sixty rectangles, all of them nearly the
   same rectangle. So a punch that OVERLAPS what is already gone grows
   that hole to the union instead of adding to the list, which is both
   cheaper and truer — a wall does not get two holes where one beam
   crossed it, it gets a bigger hole.

   And the list is capped. Past MAX_PER_LINE a new punch grows the
   NEAREST existing hole rather than being dropped: a wall that has been
   shot at all day ends up with a few large holes rather than a hundred
   small ones, which is what a wall that has been shot at all day looks
   like, and it keeps the split below bounded.

   ---------------------------------------------------------------------
   AND THE SPLIT IS A GRID, WHICH IS THE WHOLE TRICK

   "Draw this rectangle except for those rectangles" is, in general, an
   awkward problem. It stops being awkward the moment you stop trying to
   be clever about it: take every hole edge that falls inside the wall,
   cut the wall along all of them in both axes, and you have a grid of
   cells each of which is ENTIRELY inside a hole or entirely outside
   one. Test each cell's middle, keep the ones that survive, and then
   merge each row of survivors back into runs so a wall with one hole in
   it comes out as four quads rather than eight.

   With MAX_PER_LINE at four that is at most a ten-by-ten grid, tested
   once per wall per rebuild, and a rebuild happens when a block's
   geometry changes and not otherwise.
   ===================================================================== */

/* How many holes one wall may carry before new ones start growing old
   ones instead. Four, because the split is quadratic in this and
   because five holes in one wall is a wall that should have fallen
   down. */
export const MAX_PER_LINE = 4;

/* THE SMALLEST PIECE OF WALL WORTH DRAWING, in WORLD UNITS in both
   axes — and it is a hair, not a plank.

   The first cut of this wrote the horizontal one as a fraction of the
   line, 0.004, which is one and a half units on a garden wall and
   SIXTEEN on a shopfront. On the shopfront the scorched strips down the
   sides of a hole are three and a half thousandths of the line wide;
   they fell under the limit, were dropped, and what was left was a slot
   from the floor to the ceiling either side of the opening that you
   could see daylight through. The area arithmetic caught it — the
   pieces and the holes no longer came to the wall — which is why that
   sum is checked and not merely computed.

   So both are in units, both are a twentieth of one, and dropping a
   piece is not how coincident cut lines are dealt with any more: they
   are DEDUPLICATED before the grid is walked, so no cell is ever
   degenerate and no kept cell is ever thrown away. A dropped piece is a
   hole nobody asked for. */
const MIN_UNITS = 0.05;

/* HOW MUCH WIDER A HOLE GETS AS IT CRUMBLES, and in how many steps.
   Discrete steps rather than a smooth grow, because every change to a
   hole is a geometry rebuild of the block it is in — see
   js/game.js — and a smooth grow is a rebuild every frame. Three steps
   over DECAY_TICS: the bright cut the beam made, and then a ragged
   opening a quarter again as wide. */
export const DECAY_STEPS = 3;
export const DECAY_GROW = 0.26;

/** Do two rectangles overlap at all? Touching is not overlapping. */
function hits(a, t0, t1, z0, z1) {
  return a.t0 < t1 && a.t1 > t0 && a.z0 < z1 && a.z1 > z0;
}

/**
 * Take a rectangle out of a wall.
 *
 * @param line  the line, which gains a `breach` array the first time
 * @returns the breach that now covers it — a new one, or the one it was
 *          merged into, so the caller can hang a decay clock on it
 */
export function punch(line, t0, t1, z0, z1) {
  if (!(t1 > t0) || !(z1 > z0)) return null;
  t0 = Math.max(0, t0); t1 = Math.min(1, t1);
  if (!(t1 > t0)) return null;
  const list = line.breach || (line.breach = []);

  /* MERGED INTO WHATEVER IT ALREADY OVERLAPS, and then into whatever
     THAT now overlaps: growing one hole can bring it into contact with
     another, and two holes that touch are one hole. Without the second
     pass a wall crossed twice keeps two rectangles that share an edge,
     and the grid below then cuts a zero-width column between them. */
  let into = null;
  for (const b of list) {
    if (!hits(b, t0, t1, z0, z1)) continue;
    b.t0 = Math.min(b.t0, t0); b.t1 = Math.max(b.t1, t1);
    b.z0 = Math.min(b.z0, z0); b.z1 = Math.max(b.z1, z1);
    into = b;
    break;
  }
  if (!into) {
    if (list.length < MAX_PER_LINE) {
      into = { t0, t1, z0, z1, step: 0, tics: 0 };
      list.push(into);
    } else {
      /* at the cap: the nearest one grows to take it in */
      let best = list[0], bd = Infinity;
      const ct = (t0 + t1) / 2, cz = (z0 + z1) / 2;
      for (const b of list) {
        const d = Math.abs((b.t0 + b.t1) / 2 - ct) * 4000 + Math.abs((b.z0 + b.z1) / 2 - cz);
        if (d < bd) { bd = d; best = b; }
      }
      best.t0 = Math.min(best.t0, t0); best.t1 = Math.max(best.t1, t1);
      best.z0 = Math.min(best.z0, z0); best.z1 = Math.max(best.z1, z1);
      into = best;
    }
  }
  /* and the second pass: absorb anything the grown hole now touches */
  for (let i = list.length - 1; i >= 0; i--) {
    const b = list[i];
    if (b === into || !hits(b, into.t0, into.t1, into.z0, into.z1)) continue;
    into.t0 = Math.min(into.t0, b.t0); into.t1 = Math.max(into.t1, b.t1);
    into.z0 = Math.min(into.z0, b.z0); into.z1 = Math.max(into.z1, b.z1);
    list.splice(i, 1);
  }
  return into;
}

/** Is the whole span [z0, z1] at fraction `t` of this line missing?
 *
 *  ALL of it, not any of it, and that is the question collision wants:
 *  a mover gets through a wall when the hole is bigger than they are,
 *  and a hole across their knees is a wall. */
export function openAt(line, t, z0, z1) {
  const list = line.breach;
  if (!list) return false;
  for (const b of list)
    if (t >= b.t0 && t <= b.t1 && z0 >= b.z0 && z1 <= b.z1) return true;
  return false;
}

/** Is any of the span at `t` missing? What a bullet and a sight line
 *  ask, because both are a line and not a body. */
export function anyOpenAt(line, t, z) {
  const list = line.breach;
  if (!list) return false;
  for (const b of list)
    if (t >= b.t0 && t <= b.t1 && z >= b.z0 && z <= b.z1) return true;
  return false;
}

/* HOW WIDE THE SCORCHED BORDER ROUND A HOLE IS, in WORLD UNITS in both
   axes — which is the point, because one of the two axes is a fraction.
   A rim written as a fraction of the line is thirty-five centimetres on
   a shopfront and four on a garden wall; written in units and divided
   by the line's own length it is thirty-five centimetres on both, which
   is what a scorch mark is. */
const RIM_UNITS = 14;
const RIM_Z = 14;

/**
 * The pieces of a wall that are still there.
 *
 * @param line          the line, whose `breach` list this reads
 * @param zBot, zTop    the band of height being drawn
 * @param s0, s1        the piece of the line being drawn, as fractions —
 *                      addQuad's own `span`, so a gable's two halves
 *                      each ask for their own
 * @param out           reused array of [t0, t1, z0, z1, rim]
 * @returns `out`, or null when nothing is missing and the caller should
 *          simply draw the whole thing — which is the case for every
 *          wall in the game that has not been shot
 *
 * THE FIFTH NUMBER IS WHETHER THIS PIECE IS THE HOLE'S EDGE, and it is
 * the reason the runs below merge on more than "is it still there".
 *
 * The first cut of this charred every surviving piece of a breached
 * band, on the argument that brick which now ends at a hole ends at a
 * burnt edge. It does — but a piece can be forty metres of shopfront
 * whose far end has never been near the beam, and charring all of it
 * because the near end was is a building that goes black because
 * somebody shot a window. So the grid cell is asked instead: a cell
 * TOUCHING a hole is its edge and is burnt, a cell further out is not,
 * and a row merges only while the answer stays the same. What comes out
 * is a scorched border a foot or so wide round the opening and clean
 * brick beyond it, which is what a hole in a wall looks like.
 */
export function pieces(line, zBot, zTop, s0 = 0, s1 = 1, out = []) {
  const list = line.breach;
  out.length = 0;
  if (!list || !list.length) return null;

  /* only the holes that actually land in this band and this span */
  const live = [];
  for (const b of list) if (hits(b, s0, s1, zBot, zTop)) live.push(b);
  if (!live.length) return null;

  /* THE CUT LINES, in both axes: the holes' own edges, and a second set
     a rim's width outside them so the scorched border is a strip of its
     own rather than the whole of whatever piece happens to touch the
     hole. Clipped to the piece being drawn, and pushed only where they
     actually fall inside it — a hole at the end of a wall has no rim on
     that side because there is no wall there to scorch. */
  const RIM_T = RIM_UNITS / Math.max(1, line.len || 1);
  const ts = [s0, s1], zs = [zBot, zTop];
  const putT = v => { if (v > s0 && v < s1) ts.push(v); };
  const putZ = v => { if (v > zBot && v < zTop) zs.push(v); };
  for (const b of live) {
    putT(b.t0); putT(b.t1); putT(b.t0 - RIM_T); putT(b.t1 + RIM_T);
    putZ(b.z0); putZ(b.z1); putZ(b.z0 - RIM_Z); putZ(b.z1 + RIM_Z);
  }
  /* sorted and deduplicated, so a cut line that lands on another — a
     hole whose rim reaches exactly to the edge of the band, or two
     holes that share an edge — makes one cut and not a zero-width cell */
  const eps = MIN_UNITS / Math.max(1, line.len || 1);
  const tidy = (a, e) => {
    a.sort((x, y) => x - y);
    let n = 1;
    for (let i = 1; i < a.length; i++) if (a[i] - a[n - 1] > e) a[n++] = a[i];
    a.length = n;
    return a;
  };
  tidy(ts, eps);
  tidy(zs, MIN_UNITS);

  /* every cell is wholly in a hole or wholly out of one, so its middle
     decides for all of it */
  for (let j = 0; j + 1 < zs.length; j++) {
    const za = zs[j], zb = zs[j + 1];
    const zm = (za + zb) / 2;
    /* MERGED BACK INTO RUNS along the row, while the answer stays the
       same: a wall with one hole in it is twelve quads this way and
       thirty without, and the seam between two quads that share an edge
       and a colour is a seam whether or not it is needed. */
    let runFrom = -1, runRim = 0;
    const flush = to => { if (runFrom >= 0) out.push([runFrom, to, za, zb, runRim]); runFrom = -1; };
    for (let i = 0; i + 1 < ts.length; i++) {
      const ta = ts[i], tb = ts[i + 1];
      const tm = (ta + tb) / 2;
      let gone = false, rim = 0;
      for (const b of live) {
        if (tm > b.t0 && tm < b.t1 && zm > b.z0 && zm < b.z1) { gone = true; break; }
        /* the cell's own box against the hole's, grown by the rim, and
           HALF-OPEN with no tolerance. The tolerance is why: the cut
           lines above are put at exactly b.z1 + RIM_Z, so the cell
           beginning there is the FIRST cell outside the rim. A
           forgiving comparison makes it the last cell inside it, the
           run-merge then joins it to everything beyond, and the whole
           wall is scorched again — which is the bug this rim was put
           in to fix. */
        if (ta < b.t1 + RIM_T && tb > b.t0 - RIM_T &&
            za < b.z1 + RIM_Z && zb > b.z0 - RIM_Z) rim = 1;
      }
      if (gone) { flush(ta); continue; }
      if (runFrom >= 0 && rim !== runRim) flush(ta);
      if (runFrom < 0) { runFrom = ta; runRim = rim; }
    }
    flush(ts[ts.length - 1]);
  }
  return out;
}

/** Where a hole is, in the world: its middle, and how big it is. What
 *  the debris and the fire are hung off. */
export function worldOf(line, b) {
  const t = (b.t0 + b.t1) / 2;
  return {
    x: line.x1 + (line.x2 - line.x1) * t,
    y: line.y1 + (line.y2 - line.y1) * t,
    z: (b.z0 + b.z1) / 2,
    w: (b.t1 - b.t0) * line.len,
    h: b.z1 - b.z0,
    foot: b.z0,
  };
}

/* =====================================================================
   AND THE SYSTEM THAT PUNCHES THEM AND THEN LETS THEM GO
   =====================================================================

   The arithmetic above is pure and knows nothing about the game. This
   part knows about the game and nothing about the arithmetic: which
   walls a column crosses, what falls out of them, and what a hole looks
   like a few seconds after it was made.

   ---------------------------------------------------------------------
   FINDING THE WALLS

   The obvious way is Level.rayHitWall, and it is wrong twice over: it
   returns the FIRST wall and stops, and the whole point of this weapon
   is that it does not stop. So the segment is marched through the
   blockmap instead — a small box at each step, deduplicated — and every
   line that actually crosses the column is punched. Sixty-four queries
   for the longest shot in the game, and the blockmap was built for
   exactly this kind of question.

   HOW WIDE THE HOLE IS is not the column's diameter. A cylinder of
   radius R crossing a plane at an angle cuts a chord of 2R/sin(angle),
   and a beam that grazes a wall at ten degrees cuts a hole six times
   its own width — which is right, and is also why it is capped: at one
   degree the chord is the whole street, and a shot fired ALONG a
   terrace should not delete the terrace.

   ---------------------------------------------------------------------
   AND THEN IT DECAYS

   At the user's request, and it is the half that makes it a hole in a
   building rather than a hole in a picture. A fresh breach is a clean
   cut through brick. Over DECAY_TICS it does three things:

     it crumbles    the opening grows in DECAY_STEPS discrete jumps —
                    discrete because every change to a hole rebuilds the
                    block it is in, and a smooth grow is a rebuild every
                    frame
     it sheds       debris falls out of the widening edge and the dust
                    of it hangs at the foot
     it burns       the fire grid is lit at the hole, so the opening
                    goes on burning by itself and the region around it
                    chars on the fire's own clock

   The clock stops after that. A hole that grew for ever would eat the
   building, and the building coming down is the structural damage's job
   (see FireSystem.damageLine), which is a different question with its
   own answer.
   ===================================================================== */

/* how long a fresh hole spends crumbling, in tics */
export const DECAY_TICS = 3 * 35;
/* and how far apart the column is sampled while looking for walls: the
   blockmap's own cell, so no cell is stepped over */
const WALK = 128;
/* the widest a graze may cut, as a multiple of the column's diameter */
const MAX_CHORD = 3.5;

export class BreachSystem {
  constructor(game) {
    this.game = game;
    this.live = [];            // lines with holes that are still crumbling
    this.punched = 0;          // how many have been made, for the tests
    this._seen = new Set();
    this._lines = [];
  }

  /**
   * Punch a hole through every wall the column crosses.
   *
   * @param from    { x, y, z } the muzzle
   * @param angle   which way, and `slope` the rise per unit travelled
   * @param range   how far to walk
   * @param radius  the column's own radius
   * @returns how many walls were newly holed
   */
  cut(from, angle, slope, range, radius) {
    const lv = this.game.level;
    if (!lv) return 0;
    const ux = Math.cos(angle), uy = Math.sin(angle);
    const seen = this._seen;
    seen.clear();
    let made = 0;
    for (let s = 0; s <= range; s += WALK) {
      const px = from.x + ux * s, py = from.y + uy * s;
      const found = lv.linesInBox(px - radius - WALK, py - radius - WALK,
                                  px + radius + WALK, py + radius + WALK, this._lines);
      for (let i = 0; i < found.length; i++) {
        const l = found[i];
        if (seen.has(l)) continue;
        seen.add(l);
        if (this._cutLine(l, from, ux, uy, slope, range, radius)) made++;
      }
    }
    return made;
  }

  /** One wall. Returns true if anything was taken out of it. */
  _cutLine(l, from, ux, uy, slope, range, radius) {
    const ex = l.x2 - l.x1, ey = l.y2 - l.y1;
    const len = l.len || Math.hypot(ex, ey);
    if (len <= 0) return false;
    const nx = ex / len, ny = ey / len;

    /* ONLY WALLS. A two-sided line between two patches of street draws
       nothing and is not a structure; giving it a breach list would put
       one more property read into the collision, the bullet ray and the
       sight line for every query, for ever, in exchange for a hole in
       nothing. */
    const solid = l.front === null || l.back === null;
    if (!solid && !(l.bands && l.bands.length) && !(l.middle && l.middle !== 'NONE')) return false;

    /* where the column's axis crosses the line. Solving
       from + s*u = l.x1 + d*n for s and d, by Cramer's rule on
       [[ux, -nx], [uy, -ny]], whose determinant is -(ux*ny - uy*nx). */
    const cross = ux * ny - uy * nx;
    /* PARALLEL IS NOT A CROSSING. A column running along a wall never
       meets its plane, and the chord below would be infinite. */
    if (Math.abs(cross) < 1e-4) return false;
    const wx = l.x1 - from.x, wy = l.y1 - from.y;
    const s = (wx * ny - wy * nx) / cross;         // along the column
    if (s < 0 || s > range) return false;
    const d = (wx * uy - wy * ux) / cross;         // along the line, in units
    const t = d / len;

    /* the chord the cylinder cuts through this wall, capped — see the
       note on MAX_CHORD */
    const chord = Math.min(radius * 2 * MAX_CHORD, radius * 2 / Math.abs(cross));
    const half = chord / 2 / len;
    if (t + half < 0 || t - half > 1) return false;

    const bz = from.z + slope * s;
    const b = punch(l, t - half, t + half, bz - radius, bz + radius);
    if (!b) return false;
    if (!b.tics) {
      b.tics = DECAY_TICS;
      b.line = l;
      this.live.push(b);
      this.punched++;
      this._blew(l, b);
      this._weaken(l, Math.min(1, (b.t1 - b.t0) * 2));
    }
    this.game.markBreached?.(l);
    return true;
  }

  /** A WALL THAT IS GONE WAS HOLDING SOMETHING UP.
   *
   *  The structural damage in FireSystem.damageLine is a question about
   *  REGIONS and the hole is a question about the brick, and for a
   *  while those two were not connected at all — which showed. A beam
   *  raked along a terrace took the ground floor out of the whole row
   *  and left the upper storeys and the roofs hanging in the air over
   *  nothing, because no cell of the column had been near enough to the
   *  middle of any of those regions to spend their integrity.
   *
   *  So taking a wall out costs the regions it belonged to, in
   *  proportion to how much of it went: a graze that opens a tenth of a
   *  shopfront is a hole in a shopfront, and a column that takes a
   *  whole wall takes most of a region's integrity with it. Through a
   *  building is two walls, which is a building coming down; along one
   *  is a hole.
   *
   *  ONCE PER WALL, on the first punch, because cut() runs a dozen
   *  times a second for the length of a discharge and a bite per pass
   *  would flatten the town. */
  _weaken(l, share) {
    const F = this.game.fire;
    const sectors = this.game.level?.sectors;
    if (!F || !sectors || !F.structural) return;
    const bite = 0.55 * share;
    for (const col of [l.frontCol, l.backCol]) {
      if (!col) continue;
      for (let i = 0; i < col.length; i++) {
        const si = col[i];
        const sec = sectors[si];
        if (!sec || !F.structural[si] || sec.collapsed) continue;
        sec.integrity = (sec.integrity ?? 1) - bite;
        if (sec.integrity <= 0) F.bringDown(si);
      }
    }
  }

  /** The moment a wall opens: what comes out of it. */
  _blew(l, b) {
    const g = this.game;
    const w = worldOf(l, b);
    const n = Math.min(14, 4 + Math.round(w.w / 24));
    for (let i = 0; i < n; i++) {
      const jx = (Math.random() - 0.5) * w.w, jz = (Math.random() - 0.5) * w.h;
      g.fx?.puff(w.x + jx * 0.5, w.y + jx * 0.5, w.z + jz, 26 + Math.random() * 30, 130);
      g.fx?.ember?.(w.x, w.y, w.z + jz, 1, 1);
    }
    g.spawnSparks?.(w.x, w.y, w.z, 6);
    /* AND IT IS ALIGHT. The beam lights the cells it passes through
       anyway, but a hole through a wall is a hole with a burning edge,
       and the fire grid is what makes that go on being true after the
       beam has stopped. */
    g.fire?.ignite(w.x, w.y, 150, Math.max(32, w.w * 0.6));
  }

  /** One tic of crumbling, for every hole still doing it. */
  tic() {
    if (!this.live.length) return;
    const g = this.game;
    for (let i = this.live.length - 1; i >= 0; i--) {
      const b = this.live[i];
      if (--b.tics <= 0) { this.live.splice(i, 1); continue; }
      /* the step it should be on by now, and nothing happens on a tic
         that does not cross one — see DECAY_STEPS */
      const want = Math.min(DECAY_STEPS, Math.floor((1 - b.tics / DECAY_TICS) * (DECAY_STEPS + 1)));
      if (want <= b.step) continue;
      b.step = want;
      const grow = DECAY_GROW / DECAY_STEPS;
      const dt = (b.t1 - b.t0) * grow * 0.5, dz = (b.z1 - b.z0) * grow * 0.5;
      b.t0 = Math.max(0, b.t0 - dt); b.t1 = Math.min(1, b.t1 + dt);
      b.z0 -= dz; b.z1 += dz;
      /* AND A BITE OUT OF THE EDGE, which is what stops it being a
         rectangle. A hole that only grows stays a rectangle however far
         it grows, and a rectangle is a window. A chip is a small rect
         that shares an edge with the hole and sticks out past it: it
         does not overlap, so punch keeps it separate, and the grid
         below turns the pair into a stepped opening. Up to the cap, so
         a hole ends up as two or three rectangles making one ragged
         one. */
      if (b.line.breach.length < MAX_PER_LINE) {
        /* SIDEWAYS, always, and not up or down. The column is usually
           taller than the wall it crosses — a stage-three beam is eight
           metres across and a storey is three — so a hole has already
           taken the full height of the band and a chip above or below
           it lands in the sky. The SIDES are where the brick still is,
           and a step cut into one of them at some height that is not
           the middle is what turns a window back into a hole. */
        const wide = b.t1 - b.t0, tall = b.z1 - b.z0;
        const f = 0.30 + Math.random() * 0.40;
        const c0 = b.z0 + tall * Math.random() * (1 - f);
        const right = Math.random() < 0.5;
        punch(b.line, right ? b.t1 : b.t0 - wide * 0.30,
                      right ? b.t1 + wide * 0.30 : b.t0,
              c0, c0 + tall * f);
      }
      const w = worldOf(b.line, b);
      /* what fell out of the edge, and where it landed */
      for (let k = 0; k < 4; k++) {
        const jx = (Math.random() - 0.5) * w.w;
        g.fx?.puff(w.x + jx * 0.5, w.y + jx * 0.5, w.z + (Math.random() - 0.5) * w.h, 22 + Math.random() * 26, 110);
      }
      g.fx?.ember?.(w.x, w.y, w.foot, 2, 0.8);
      g.fire?.ignite(w.x, w.y, 110, Math.max(32, w.w * 0.5));
      g.markBreached?.(b.line);
    }
  }
}
