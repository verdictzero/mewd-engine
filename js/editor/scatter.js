/* =====================================================================
   MEWD Editor — spreading things procedurally
   =====================================================================

   At the user's request: a way to spread sprite decorations and sprite
   NPCs over a map procedurally, and to go on changing how they are
   spread after they are down. A SCATTER is not a pile of things. It is
   a RULE that the compiler runs every time: an area, what to put in it
   and in what proportions, how thick, how far apart, how clumped, and
   a seed. Change any of them and the whole spread is re-grown at once,
   in the 2D plan, in the 3D view and in the game. Bake one and it
   becomes ordinary things you can move by hand.

   WHAT CAN BE SPREAD is anything the game draws as a sprite standing on
   the floor:

     the people        SHOPPER, TOWNIE — the crowd, each one a random
                       variant, facing a random way
     the furniture     CRATE, TROLLEY, BOLLARD, FUELCAN, GRAVESTONE,
                       STREETLAMP — the game's own sprite actors
     the plants        every kind js/forest.js draws — firs, bushes,
                       ferns, grass, the town's street trees and the
                       vandre biomes' cacti, meadows, pines, savanna,
                       wasteland, wheat and tundra scrub — as
                       `PLANT:<kind>`, which the compiler hands to the
                       game as level.plants, the list js/forest.js
                       grows a town's gardens from

   HOW IT GROWS, and it is the same every time for the same seed:

     1. Darts are thrown at the area, one at a time, from the seed.
     2. A dart that lands off the map, in a sector nobody could stand in,
        inside a prop, or nearer than `spacing` to one already down is
        thrown away. That is a Poisson-disc spread by rejection, and it
        is what keeps a crowd from standing in itself.
     3. A CLUMP field — smooth value noise, from the same seed — decides
        how likely a dart is to be kept where it landed. At 0 the spread
        is even; at 1 things gather in drifts with clear ground between
        them, the way the wood's thickets do.
     4. What lands is picked by weight from the scatter's list.

   It stops at the count, or when darts stop finding room. A scatter
   that asks for more than fits says so in the problems list.
   ===================================================================== */

import { KINDS } from '../forest.js';

/* the plant kinds, by name, for the palette and for the checks */
export const PLANT_KINDS = KINDS.map(k => k.name);
export const plantKind = name => KINDS.find(k => k.name === name) || null;
/* and shelved for the palette: the wood's and the town's first, then
   each vandre biome (a kind's `set`) in the order KINDS has them */
export const PLANT_SETS = [...new Set(KINDS.map(k => k.set || 'wood & town'))]
  .map(name => ({ name, kinds: KINDS.filter(k => (k.set || 'wood & town') === name).map(k => k.name) }));
/* whether the forest counts a kind as a TREE — one to a cell, and it
   stops you — by js/forest.js's own rule */
export const isCanopyKind = name => { const k = plantKind(name); return !!k && !k.cover && (k.canopy ?? (k.h > 120)); };

/* the most one scatter will ever grow, so a slip of the density slider
   cannot hang the page */
export const SCATTER_MAX = 4000;
/* the density unit: things per 1024 x 1024 of floor, which is sixteen
   cells on a side on the grid */
export const DENSITY_AREA = 1024 * 1024;

/* READY-MADE MIXES, for the palette and for the brush. Every one of
   them is only a starting list: the inspector edits the list after. */
export const PRESETS = {
  crowd:     { name: 'Crowd',        density: 16,  spacing: 110, clump: 0.35,
               items: [{ type: 'SHOPPER', w: 1 }] },
  townsfolk: { name: 'Townsfolk',    density: 8,   spacing: 140, clump: 0.2,
               items: [{ type: 'TOWNIE', w: 3 }, { type: 'SHOPPER', w: 1 }] },
  forest:    { name: 'Forest',       density: 40, spacing: 60,  clump: 0.55,
               items: [{ type: 'PLANT:fir_tall_1', w: 22 }, { type: 'PLANT:fir_tall_2', w: 22 }, { type: 'PLANT:fir_medium', w: 16 },
                       { type: 'PLANT:fir_young', w: 14 }, { type: 'PLANT:bush_large_1', w: 8 }, { type: 'PLANT:bush_small_1', w: 6 }] },
  scrub:     { name: 'Scrub & grass', density: 60, spacing: 26, clump: 0.6,
               items: [{ type: 'PLANT:grass', w: 5 }, { type: 'PLANT:fern', w: 4 }, { type: 'PLANT:bush_small_1', w: 1 },
                       { type: 'PLANT:bush_small_2', w: 1 }] },
  street:    { name: 'Street trees', density: 5,  spacing: 220, clump: 0,
               items: ['street_round', 'street_broad', 'street_oval', 'street_upright', 'street_dense', 'street_big']
                 .map(k => ({ type: `PLANT:${k}`, w: 1 })) },
  clutter:   { name: 'Clutter',      density: 10, spacing: 90,  clump: 0.45,
               items: [{ type: 'CRATE', w: 4 }, { type: 'TROLLEY', w: 3 }, { type: 'BOLLARD', w: 2 }, { type: 'FUELCAN', w: 1 }] },
  graveyard: { name: 'Graveyard',    density: 10, spacing: 120, clump: 0.1,
               items: [{ type: 'GRAVESTONE', w: 6 }, { type: 'PLANT:bush_small_2', w: 1 }, { type: 'PLANT:fern', w: 2 }] },
  /* THE VANDRE BIOMES, one mix each, out of the plants that came with
     them (the `set` of a kind in js/forest.js). Each goes with its
     ground in the texture pack, noted by the name. */
  desert:    { name: 'Desert (SAND1)',  density: 14, spacing: 90, clump: 0.35,
               items: plants({ desert_big_cactus_1: 2, desert_cactus_5: 3, desert_cactus_6: 3, desert_small_cactus_1: 3, desert_small_cactus_2: 3,
                               desert_creosote_bush_5: 4, desert_creosote_bush_6: 4, desert_dead_creosote_bush_5: 2, desert_dead_creosote_bush_6: 2,
                               desert_bush_1: 3, desert_bush_2: 3 }) },
  meadow:    { name: 'Meadow (MEADOW1-5)', density: 45, spacing: 40, clump: 0.5,
               items: plants({ new_meadow_tree_1: 1, new_meadow_tree_2: 1, new_meadow_tree_3: 1, new_meadow_bush_1: 3, new_meadow_bush_2: 3,
                               new_meadow_bush_3: 3, new_meadow_bush_4: 3, new_meadow_flower_1: 4, new_meadow_flower_2: 4,
                               new_meadow_grass_1: 10, new_meadow_grass_2: 10, new_meadow_grass_tall_1: 5,
                               new_meadow_fern_1: 2, new_meadow_fern_2: 2, new_meadow_fern_3: 2, new_meadow_fern_4: 2 }) },
  meadowOld: { name: 'Meadow, classic (GRASCHK1/2)', density: 40, spacing: 40, clump: 0.5,
               items: plants({ meadow_tree_big: 1, meadow_tree_medium: 1, meadow_tree_really_big: 1, meadow_bush_var_a: 4, meadow_bush_var_b: 4,
                               meadow_grass_var_a: 10, meadow_grass_var_b: 10 }) },
  pine:      { name: 'Pine barrens (PINEBAR1)', density: 40, spacing: 52, clump: 0.5,
               items: plants({ pine_fir_tree_1: 5, pine_fir_tree_2: 5, pine_fir_tree_3: 5, pine_fir_tree_4: 5, pine_barrens_tree: 3,
                               pine_juvenile_fir_tree_1: 3, pine_juvenile_fir_tree_2: 3, pine_juvenile_fir_tree_4: 3,
                               pine_forest_bush_1: 4, pine_forest_bush_2: 4, pine_forest_bush_3: 4,
                               pine_fern_1: 4, pine_fern_2: 4, pine_fern_3: 4, pine_fern_4: 4 }) },
  savanna:   { name: 'Savanna (SAVANNA1)', density: 30, spacing: 48, clump: 0.55,
               items: plants({ savanna_tree_1: 1, savanna_grass_short_1: 8, savanna_grass_short_2: 8, savanna_grass_tall_1: 5, savanna_grass_tall_2: 5 }) },
  wasteland: { name: 'Wasteland (WASTE1)', density: 8, spacing: 120, clump: 0.3,
               items: plants({ wasteland_tree: 2, wasteland_tree_big_2: 1, wasteland_tree_big_3: 1, wasteland_small_tree_1: 2,
                               wasteland_tree_small_2: 2, wasteland_bush_1: 5 }) },
  tundra:    { name: 'Tundra (TUNDRA1)', density: 30, spacing: 44, clump: 0.55,
               items: plants({ tundra_bush_1: 3, tundra_bush_2: 3, tundra_bush_3: 3, tundra_bush_4: 3, tundra_bush_5: 1 }) },
  farmland:  { name: 'Wheat field (FARMLND1)', density: 220, spacing: 18, clump: 0,
               items: plants({ farm_wheat_1: 3, farm_wheat_2: 3, farm_wheat_3: 3, farm_wheat_4: 2 }) },
};
/* a preset's list out of { kind: weight } */
function plants(o) { return Object.entries(o).map(([k, w]) => ({ type: `PLANT:${k}`, w })); }

/** A new scatter from a preset, over an area. */
export function scatterFrom(presetKey, area, id, seed) {
  const p = PRESETS[presetKey] || PRESETS.crowd;
  return {
    id, name: p.name, preset: presetKey, area,
    items: p.items.map(i => ({ ...i })),
    density: p.density, spacing: p.spacing, clump: p.clump,
    seed: seed >>> 0, scaleMin: 0.85, scaleMax: 1.15,
  };
}

/* ---------------------------------------------------------------------
   the area
   --------------------------------------------------------------------- */

/** The area's bounding box, and whether a point is in it. `rings` is
 *  the document's sectors as rings, by id, for an area made of them. */
export function areaShape(area, rings) {
  if (area.kind === 'circle') {
    const { x, y, r } = area;
    return { box: [x - r, y - r, x + r, y + r], size: Math.PI * r * r,
             has: (px, py) => (px - x) ** 2 + (py - y) ** 2 <= r * r };
  }
  if (area.kind === 'rect') {
    const x0 = Math.min(area.x0, area.x1), x1 = Math.max(area.x0, area.x1);
    const y0 = Math.min(area.y0, area.y1), y1 = Math.max(area.y0, area.y1);
    return { box: [x0, y0, x1, y1], size: (x1 - x0) * (y1 - y0),
             has: (px, py) => px >= x0 && px <= x1 && py >= y0 && py <= y1 };
  }
  /* sectors: the union of the ones named, holes and all — whether a
     point is IN one of them is the compiled level's question, asked by
     the caller through `inSectors` */
  const rs = (area.ids || []).map(id => rings.get(id)).filter(r => r && r.length >= 3);
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, size = 0;
  for (const r of rs) {
    let a = 0;
    for (let i = 0; i < r.length; i++) {
      const p = r[i], q = r[(i + 1) % r.length];
      x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]);
      a += p[0] * q[1] - q[0] * p[1];
    }
    size += Math.abs(a) / 2;
  }
  return { box: rs.length ? [x0, y0, x1, y1] : [0, 0, 0, 0], size, sectors: new Set(area.ids || []), has: () => true };
}

/* ---------------------------------------------------------------------
   the noise and the dice
   --------------------------------------------------------------------- */
export function roller(seed) {
  let s = (seed >>> 0) || 1;
  return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
}
function hash2(x, y, seed) {
  let h = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(seed | 0, 2246822519);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}
/** Smooth value noise, two octaves, 0..1. The first octave is 512
 *  units across, which is the size of a thicket or a knot of people. */
export function clumpAt(x, y, seed) {
  let v = 0, amp = 0.65, f = 1 / 512;
  for (let o = 0; o < 2; o++) {
    const gx = x * f, gy = y * f, ix = Math.floor(gx), iy = Math.floor(gy);
    const tx = gx - ix, ty = gy - iy;
    const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
    const s = seed + o * 101;
    const a = hash2(ix, iy, s), b = hash2(ix + 1, iy, s), c = hash2(ix, iy + 1, s), d = hash2(ix + 1, iy + 1, s);
    v += amp * (a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy);
    amp *= 0.35 / 0.65; f *= 2.3;
  }
  return v;
}

/* ---------------------------------------------------------------------
   THE SPREAD
   --------------------------------------------------------------------- */

/**
 * Grow one scatter.
 *
 * @param sc       the scatter
 * @param ctx      { rings: Map(id -> ring), standable(x, y) -> the id
 *                 of the document sector a thing could stand at there,
 *                 or null; blocked(x, y, r) -> true inside a prop;
 *                 taken: [[x, y, r]] already down, which it adds to }
 * @returns { items: [{ type, kind?, x, y, angle, variant?, scale }], wanted, grown }
 */
export function growScatter(sc, ctx) {
  const shape = areaShape(sc.area || { kind: 'circle', x: 0, y: 0, r: 0 }, ctx.rings);
  const items = (sc.items || []).filter(i => i.w > 0 && validType(i.type));
  const total = items.reduce((a, i) => a + i.w, 0);
  const wanted = Math.min(SCATTER_MAX, Math.max(0, Math.round((sc.density || 0) * shape.size / DENSITY_AREA)));
  const out = [];
  if (!total || !wanted || !(shape.size > 0)) return { items: out, wanted, grown: 0 };
  const rnd = roller(((sc.seed ?? 1) ^ Math.imul(sc.id | 0, 2654435761)) >>> 0);
  const spacing = Math.max(0, sc.spacing ?? 64), sp2 = spacing * spacing;
  const clump = Math.max(0, Math.min(1, sc.clump ?? 0));
  const [bx0, by0, bx1, by1] = shape.box;
  const bw = bx1 - bx0, bh = by1 - by0;

  /* a coarse bucket grid for the spacing test, so a crowd of thousands
     is not a crowd of millions of distance checks */
  const cell = Math.max(32, spacing);
  const buckets = new Map();
  const bkey = (x, y) => `${Math.floor(x / cell)},${Math.floor(y / cell)}`;
  const put = (x, y) => { const k = bkey(x, y); (buckets.get(k) || buckets.set(k, []).get(k)).push([x, y]); };
  const near = (x, y) => {
    const cx = Math.floor(x / cell), cy = Math.floor(y / cell);
    for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
      const b = buckets.get(`${cx + i},${cy + j}`);
      if (b) for (const p of b) if ((p[0] - x) ** 2 + (p[1] - y) ** 2 < sp2) return true;
    }
    return false;
  };
  /* what is already standing — things placed by hand and earlier
     scatters — keeps its ground too */
  for (const [x, y] of ctx.taken || []) if (x >= bx0 - spacing && x <= bx1 + spacing && y >= by0 - spacing && y <= by1 + spacing) put(x, y);

  const tries = wanted * 40 + 200;
  for (let t = 0; t < tries && out.length < wanted; t++) {
    const x = bx0 + rnd() * bw, y = by0 + rnd() * bh;
    const keep = rnd(), pickR = rnd(), angR = rnd(), varR = rnd(), scR = rnd();
    if (!shape.has(x, y)) continue;
    const at = ctx.standable ? ctx.standable(x, y) : 0;
    if (at === null || at === undefined) continue;
    if (shape.sectors && !shape.sectors.has(at)) continue;
    if (ctx.blocked && ctx.blocked(x, y, 12)) continue;
    /* the clump: at 0 every dart is kept, at 1 only those where the
       noise is high, with a soft edge so a drift thins out */
    if (clump > 0) {
      const n = clumpAt(x, y, (sc.seed ?? 1) + 7);
      const lo = 0.25 + clump * 0.3, hi = lo + 0.12 + (1 - clump) * 0.4;
      const p = Math.max(0, Math.min(1, (n - lo) / (hi - lo)));
      if (keep > p * p * (3 - 2 * p) + (1 - clump) * 0.15) continue;
    }
    if (spacing && near(x, y)) continue;
    let r = pickR * total, it = items[0];
    for (const i of items) { r -= i.w; if (r <= 0) { it = i; break; } }
    const lo = sc.scaleMin ?? 1, hi = sc.scaleMax ?? 1;
    const thing = { type: it.type, x: Math.round(x), y: Math.round(y), angle: angR * Math.PI * 2, variant: (varR * 64) | 0,
                    scale: +(lo + (hi - lo) * scR).toFixed(3), scatter: sc.id };
    if (it.type.startsWith('PLANT:')) { thing.type = 'PLANT'; thing.kind = it.type.slice(6); }
    out.push(thing);
    put(x, y);
    if (ctx.taken) ctx.taken.push([x, y]);
  }
  return { items: out, wanted, grown: out.length };
}

/** Is `type` something a scatter can put down? */
export function validType(type, thingTypes = null) {
  if (typeof type !== 'string') return false;
  if (type.startsWith('PLANT:')) return !!plantKind(type.slice(6));
  const ok = ['SHOPPER', 'TOWNIE', 'TROLLEY', 'BOLLARD', 'FUELCAN', 'CRATE', 'STREETLAMP', 'GRAVESTONE'];
  return ok.includes(type) || !!thingTypes?.[type];
}

/** Every type a scatter's list can name, for the inspector's picker. */
export const SCATTER_TYPES = [
  'SHOPPER', 'TOWNIE', 'CRATE', 'TROLLEY', 'BOLLARD', 'FUELCAN', 'GRAVESTONE', 'STREETLAMP',
  ...PLANT_KINDS.map(k => `PLANT:${k}`),
];
