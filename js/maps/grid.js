/* =====================================================================
   MEWD — THE GRID
   =====================================================================

   A TEST AREA, and that is all it is: a large walled-off green grid
   with a crowd standing on it and every gun in the rack in your hands.
   At the user's request it holds nothing else — nothing to burn,
   nothing to burn it with, nobody coming up a road.

   WHAT IS ARCHIVED RATHER THAN GONE, because all of it comes back:

     the superstore and the town   js/maps/sellwrong.js, js/maps/town.js
     the fire simulation           js/fire.js, and `noCellFire` below
     the burning boxes             js/boxes.js, and `boxes` below
     the responders                js/responders.js, js/brigade.js, and
                                   `noSquads` below
     the lo-fi picture             js/lofi.js and js/palette.js, turned
                                   down to a pass-through in js/main.js

   Every one of those is still in the repository, still exported and
   still tested. Nothing here deletes them; this map simply does not ask
   for them, and js/main.js does not build them. Putting the world back
   is turning these switches over.

   THE MEASUREMENTS. One CELL is 64 units, which is Doom's grid and the
   ruler the rest of the game is already cut to — a shopper is 62 tall,
   a door is 128 high. The field is 10,240 units square, which you can
   see across on a clear night (airFar is 14,000) and cannot walk out
   of.

   IT IS ONE RECTANGLE. The floor used to be cut into hundreds of strips
   because there were boxes standing in it and a sector in this engine
   is one ring of points and cannot have an island in the middle. With
   nothing standing on it the whole field is a single sector and four
   one-sided lines: about ten triangles for the entire world, which is
   what a test area for guns and crowds ought to cost.
   ===================================================================== */

import { MapBuilder } from '../level.js';
import { RectMap } from './rectmap.js';

/* one cell of the grid, and it is Doom's 64 */
export const CELL = 64;
/* how big the field is, each way — a hundred and sixty cells */
export const FIELD = 160 * CELL;                    // 10240
/* how tall the lattice wall round it stands, and therefore the ceiling */
export const WALL_H = 1024;
/* how many people are standing in it. Two hundred over the middle of a
   field this big is a crowd you can walk into and shoot at; a hundred
   spread over the whole ten thousand units was one person every
   million square units, which is not a crowd, it is dust. */
export const CROWD = 200;
/* and the part of the field they stand in — the middle two thirds, so
   there is somebody about wherever you are without the far corners
   being as busy as the middle */
export const CROWD_SPAN = 0.66;
/* and how far apart they are put */
const APART = 130;

/* The floor's own light. The field is `outdoor` so the rain falls on it
   and a vehicle could drive on it, but its `sky` is 0: an outdoor
   surface is otherwise lit by skyLight, which at two in the morning is
   0.08, and this world is not about the hour. It is the brightness it
   says it is. */
const FLOOR_LIGHT = 0.72;

/* A deterministic roll, so the crowd stands in the same places every
   boot and the smoke test can say where somebody is. */
function roller(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

/**
 * THE GRID.
 *
 * @param opts.seed   the roll the crowd is placed from
 * @param opts.crowd  how many people, for a test that wants none
 */
export function buildGrid(opts = {}) {
  const rnd = roller(opts.seed ?? 20250924);
  const mb = new MapBuilder('GRID');
  const rm = new RectMap(mb);

  const X0 = 0, Y0 = 0, X1 = FIELD, Y1 = FIELD;
  const MID = FIELD / 2;

  /* THE WHOLE FIELD, in one rectangle. `floorAnchor` is what puts a line
     of the GRID texture on every cell edge measured from the field's own
     corner rather than from wherever the world origin happens to be —
     see floorAnchor in js/level.js. */
  rm.add(X0, Y0, X1, Y1, {
    floor: 0, ceil: WALL_H, light: FLOOR_LIGHT, ambient: FLOOR_LIGHT,
    floorTex: 'GRID', floorAnchor: [X0, Y0], ceilTex: 'SKY',
    wallTex: 'GRIDWALL', upperTex: 'GRIDWALL', lowerTex: 'GRIDWALL',
    outdoor: true, sky: 0, fuel: 0, name: 'field',
  });
  rm.build();

  /* ------------------------------------------------------------------
     WHO IS IN IT: one START in the middle, and a crowd on the floor.
     ------------------------------------------------------------------ */
  mb.thing('START', MID, MID - 8 * CELL, Math.PI / 2);

  const want = opts.crowd ?? CROWD;
  const span = FIELD * CROWD_SPAN, edge = (FIELD - span) / 2;
  const taken = [];
  const standable = (x, y) => {
    if (x < X0 + 96 || x > X1 - 96 || y < Y0 + 96 || y > Y1 - 96) return false;
    for (const t of taken) if ((t[0] - x) ** 2 + (t[1] - y) ** 2 < APART * APART) return false;
    return true;
  };
  for (let k = 0, tries = 0; k < want && tries < want * 200; tries++) {
    const x = X0 + edge + rnd() * span, y = Y0 + edge + rnd() * span;
    if (!standable(x, y)) continue;
    taken.push([x, y]);
    mb.thing('SHOPPER', Math.round(x), Math.round(y), rnd() * Math.PI * 2, { variant: (rnd() * 17) | 0 });
    k++;
  }

  const level = mb.build();

  /* ------------------------------------------------------------------
     AND WHAT THIS WORLD DOES NOT HAVE

     Three switches, all read elsewhere, none of them deleting anything.
     ------------------------------------------------------------------ */
  /* THE CELL FIRE IS OFF. Running a grid of fuel and heat over ten
     thousand units of field so that every cell of it can report nothing
     is the cost the user asked to stop paying — see FireSystem, which
     reads this and does not seed, link or step. */
  level.noCellFire = true;
  /* AND NOTHING CATCHES, at the user's request. The flamethrower still
     throws flame and the extinguisher still freezes people solid,
     because those are GUNS and this is a place to try guns; what is
     gone is anything in the world actually going up as a result. See
     Actor.ignite and Vehicle.ignite, which both read this. */
  level.noBurn = true;
  /* AND NOBODY IS SENT: no SWAT, no army, and with the army never
     called no gunship either — see squadTic in js/responders.js. The
     fire brigade needs a fire and there are none. */
  level.noSquads = true;

  level.carSlots = [];
  level.slideDoors = [];
  level.props = [];
  level.roofs = [];
  level.plants = [];
  level.forestRects = [];
  level.forestBounds = [X0, Y0, X1, Y1];
  level.clearing = level.fireBounds;
  level.town = null;
  level.exits = [];
  /* no road, so no ring, no routes and no bays: every one of those is
     optional and guarded, and a world with nobody coming needs none of
     them (see WHAT ELSE READS THE LEVEL — they are all-or-nothing, and
     this is the nothing) */
  level.roadEnds = [];
  level.boxes = [];
  level.viewpoint = { x: MID, y: MID - 8 * CELL, angle: Math.PI / 2 };
  level.salesFloor = { x0: X0, y0: Y0, x1: X1, y1: Y1 };
  level.road = { y0: MID - CELL, y1: MID + CELL };
  level.title = 'THE GRID';
  level.field = { x0: X0, y0: Y0, x1: X1, y1: Y1, cell: CELL, floor: 0, ceil: WALL_H };

  return level;
}
