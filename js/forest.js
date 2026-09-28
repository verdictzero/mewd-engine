/* =====================================================================
   MEWD — the forest, and it burns
   =====================================================================

   The parade stands in the middle of a wood that runs for miles: a
   flat plain of firs and undergrowth, thousands of them, with the car
   park cut out of the middle. It exists to be set on fire. A
   supermarket burning down is a night's work; a forest burning down is
   weather, and watching a front you started walk off toward the
   horizon on its own is the other half of the game.

   TWO THINGS, KEPT APART. The SIMULATION is a grid of 64-unit cells
   with a byte of state each — green, alight, gone — and a list of the
   ones currently burning. It is pure typed arrays and can run for an
   hour in Node with no renderer, which is how the smoke test checks
   that a spark actually takes the wood and roughly how long it takes.
   The DRAWING is instanced billboards: every plant in the forest is one
   entry in a buffer, and each kind of plant is one draw call, so fifty
   thousand trees cost about what ten do. `build()` is the only place
   the two meet.

   THE ART IS FROM THE GOLF PROJECT, and so is the fire. Each sprite
   comes with a BURN MAP baked from its own pixels — where the coals
   sit, how black it ends, WHEN each texel catches, how leafy it is —
   and one number per plant swept across that map takes it from green
   through scorched, alight and charred without a second set of art.
   The shader below is that mechanism ported: a tree is never uniformly
   on fire, it has a burning band climbing it, with green above and
   char below, and the coals it leaves cycle through the ember palette.

   THE GROUND BURNS WITH IT. One texel of the burn grid per cell,
   sampled with filtering under a ground shader that crossfades forest
   floor into charred dirt — so a burnt patch of wood is black to the
   ground and stays that way, which is what makes a fire feel like it
   happened rather than played.

   WHAT SPREADS. Every cell of forest is fuel — the floor is dry needle
   litter — and a cell with a tree in it burns hotter and longer and
   throws fire further. There is a wind, from the west, and the fire
   moves with it about three times as readily as against it. That is
   the whole model, and it percolates: light one tree anywhere and,
   left alone, the whole wood goes, at walking pace downwind and a
   crawl into the wind. The player with a flamethrower is much faster
   than waiting, which is the point of carrying one.
   ===================================================================== */

import * as THREE from 'three';
import { worldUniforms, WORLD_UNIFORMS_GLSL, WORLD_SHADE_GLSL, SECTOR_GRID_GLSL } from './material.js';
import { climate } from './weather.js';
import { windMultipliers } from './fire.js';
import { Particles } from './particles.js';
import { FLAME_FOOT } from './fireart.js';
import { pRandom, pChance, dist2, clamp } from './util.js';
import { fbm } from './pixel.js';
import { EMBER_RAMP } from './palette.js';

export const CELL = 64;
export const FIRE_INTERVAL = 9;       // the store's clock, so the two fires keep time

/* How each kind of plant is drawn and what it does to a fire.

     h      world units tall (the sprite's foot on the ground)
     aspect the sprite's width over its height
     r      trunk radius you cannot walk through; 0 walks through it
     w      how often it is planted, out of the tree weights
     cover  ground cover, planted separately and more thinly */
export const KINDS = [
  { name: 'fir_tall_1',   h: 300, aspect: 0.5, r: 14, w: 22 },
  { name: 'fir_tall_2',   h: 290, aspect: 0.5, r: 13, w: 22 },
  { name: 'fir_medium',   h: 232, aspect: 0.5, r: 14, w: 16 },
  { name: 'fir_young',    h: 150, aspect: 0.5, r: 9,  w: 14 },
  { name: 'bush_large_1', h: 86,  aspect: 1.0, r: 18, w: 8 },
  { name: 'bush_large_2', h: 82,  aspect: 1.0, r: 18, w: 7 },
  { name: 'bush_small_1', h: 62,  aspect: 1.0, r: 12, w: 6 },
  { name: 'bush_small_2', h: 60,  aspect: 1.0, r: 12, w: 5 },
  { name: 'fern',         h: 46,  aspect: 1.0, r: 0,  w: 0, cover: true },
  { name: 'grass',        h: 40,  aspect: 1.0, r: 0,  w: 0, cover: true },

  /* ---- AND WHAT THE TOWN PLANTS -----------------------------------
     Broadleaves, which the wood has none of: it is a conifer wood and
     the town is a town, and a street of firs is a town in a national
     park. These are photographs, cut out of their chroma key and given
     a burn map by tools/bake-plants.mjs, and they land in
     assets/forest/ in the same two files every fir already had.

     THE WEIGHT IS ZERO ON EVERY ONE OF THEM, which is what keeps them
     out of the wood: the scatter in _plant picks by weight and skips
     anything at nought, so not one of these is ever planted by the
     forest itself. They arrive through _plantTown, from the list
     js/maps/town.js builds, at a position somebody chose.

     THE ASPECT IS THE ARTWORK'S and not the tile's. Every tile here is
     128 by 256 because that is what the wood's are and powers of two
     are cheap; the photographs are nearer two to three, so the tile is
     squashed going in and stretched coming out, and what you see is
     the shape of the tree that was photographed. */
  { name: 'street_round',   h: 280, aspect: 0.683, r: 14, w: 0 },
  { name: 'street_broad',   h: 300, aspect: 0.660, r: 15, w: 0 },
  { name: 'street_oval',    h: 290, aspect: 0.666, r: 14, w: 0 },
  { name: 'street_upright', h: 310, aspect: 0.610, r: 14, w: 0 },
  { name: 'street_dense',   h: 268, aspect: 0.670, r: 13, w: 0 },
  { name: 'street_big',     h: 330, aspect: 0.667, r: 16, w: 0 },
  /* THE CLIPPED BOX USED TO BE HERE, one photographed block of it to a
     cell, and a hedge was a row of them. It is geometry now, at the
     user's request — a sector whose floor is the top of the hedge, laid
     by carveHedges in js/maps/town.js — and the wood no longer grows
     any. What that bought is a hedge with a CORNER, which no number of
     billboards has: a row of pictures that all turn to face you has no
     end you can walk round and no top you can see going away from you.
     The `canopy` flag below stays because it is what let a short thing
     be one to a cell, and the next short thing that needs it will. */

  /* ---- AND THE VANDRE BIOMES --------------------------------------
     The user's own painted plants from github.com/verdictzero/vandre —
     desert, meadow (the old .tga set and the new one), pine barrens,
     savanna, wasteland, farmland and tundra — made into the same pair of
     files as everything above by tools/prep-vandre.py. `set` is the
     biome: the editor shelves them by it, and a map that plants none of
     a set never downloads it (loadForestArt in js/main.js).

     THE WEIGHT IS ZERO, as the street trees' is, so the wood never plants
     one: they come from a map's own things and scatters. Anything over
     120 is a tree — one to a cell, and its trunk stops you; everything
     under is `cover`, planted in the understory and walked through,
     since none of it is the wood's undergrowth and the wood's own rules
     for that (the bush weights) should not count it. */
  { name: 'desert_big_cactus_1',         h: 240, aspect: 0.503, r: 10, w: 0, set: 'desert' },
  { name: 'desert_cactus_5',             h: 190, aspect: 0.492, r: 9,  w: 0, set: 'desert' },
  { name: 'desert_cactus_6',             h: 180, aspect: 0.488, r: 9,  w: 0, set: 'desert' },
  { name: 'desert_creosote_bush_5',      h: 84,  aspect: 1.421, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_creosote_bush_6',      h: 84,  aspect: 1.421, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_dead_creosote_bush_5', h: 88,  aspect: 1.324, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_dead_creosote_bush_6', h: 84,  aspect: 1.399, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_bush_1',               h: 92,  aspect: 1.523, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_bush_2',               h: 80,  aspect: 1.550, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_small_cactus_1',       h: 76,  aspect: 0.627, r: 0,  w: 0, set: 'desert', cover: true },
  { name: 'desert_small_cactus_2',       h: 72,  aspect: 0.464, r: 0,  w: 0, set: 'desert', cover: true },

  { name: 'meadow_bush_var_a',           h: 64,  aspect: 1.000, r: 0,  w: 0, set: 'meadow', cover: true },
  { name: 'meadow_bush_var_b',           h: 64,  aspect: 1.000, r: 0,  w: 0, set: 'meadow', cover: true },
  { name: 'meadow_grass_var_a',          h: 36,  aspect: 1.359, r: 0,  w: 0, set: 'meadow', cover: true },
  { name: 'meadow_grass_var_b',          h: 36,  aspect: 1.309, r: 0,  w: 0, set: 'meadow', cover: true },
  { name: 'meadow_tree_big',             h: 290, aspect: 0.746, r: 14, w: 0, set: 'meadow' },
  { name: 'meadow_tree_medium',          h: 220, aspect: 0.660, r: 12, w: 0, set: 'meadow' },
  { name: 'meadow_tree_really_big',      h: 340, aspect: 1.016, r: 18, w: 0, set: 'meadow' },

  { name: 'new_meadow_fern_1',           h: 44,  aspect: 1.992, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_fern_2',           h: 44,  aspect: 1.968, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_fern_3',           h: 44,  aspect: 1.961, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_fern_4',           h: 44,  aspect: 2.000, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_bush_1',           h: 84,  aspect: 1.502, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_bush_2',           h: 56,  aspect: 1.554, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_bush_3',           h: 80,  aspect: 1.676, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_bush_4',           h: 84,  aspect: 1.516, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_flower_1',         h: 64,  aspect: 0.690, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_flower_2',         h: 70,  aspect: 0.624, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_grass_1',          h: 44,  aspect: 1.157, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_grass_2',          h: 36,  aspect: 1.214, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_grass_tall_1',     h: 84,  aspect: 0.488, r: 0,  w: 0, set: 'new meadow', cover: true },
  { name: 'new_meadow_tree_1',           h: 380, aspect: 1.004, r: 18, w: 0, set: 'new meadow' },
  { name: 'new_meadow_tree_2',           h: 320, aspect: 1.332, r: 18, w: 0, set: 'new meadow' },
  { name: 'new_meadow_tree_3',           h: 320, aspect: 1.330, r: 18, w: 0, set: 'new meadow' },

  { name: 'pine_fern_1',                 h: 44,  aspect: 1.992, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_fern_2',                 h: 44,  aspect: 1.968, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_fern_3',                 h: 44,  aspect: 1.961, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_fern_4',                 h: 44,  aspect: 2.000, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_fir_tree_1',             h: 300, aspect: 0.563, r: 13, w: 0, set: 'pine barrens' },
  { name: 'pine_fir_tree_2',             h: 310, aspect: 0.555, r: 13, w: 0, set: 'pine barrens' },
  { name: 'pine_fir_tree_3',             h: 320, aspect: 0.523, r: 14, w: 0, set: 'pine barrens' },
  { name: 'pine_fir_tree_4',             h: 340, aspect: 0.497, r: 14, w: 0, set: 'pine barrens' },
  { name: 'pine_forest_bush_1',          h: 60,  aspect: 2.000, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_forest_bush_2',          h: 56,  aspect: 1.992, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_forest_bush_3',          h: 60,  aspect: 1.536, r: 0,  w: 0, set: 'pine barrens', cover: true },
  { name: 'pine_juvenile_fir_tree_1',    h: 150, aspect: 0.843, r: 9,  w: 0, set: 'pine barrens' },
  { name: 'pine_juvenile_fir_tree_2',    h: 160, aspect: 0.945, r: 9,  w: 0, set: 'pine barrens' },
  { name: 'pine_juvenile_fir_tree_4',    h: 160, aspect: 0.965, r: 9,  w: 0, set: 'pine barrens' },
  { name: 'pine_barrens_tree',           h: 360, aspect: 0.496, r: 14, w: 0, set: 'pine barrens' },

  { name: 'savanna_grass_short_1',       h: 50,  aspect: 1.196, r: 0,  w: 0, set: 'savanna', cover: true },
  { name: 'savanna_grass_short_2',       h: 52,  aspect: 1.253, r: 0,  w: 0, set: 'savanna', cover: true },
  { name: 'savanna_grass_tall_1',        h: 116, aspect: 0.491, r: 0,  w: 0, set: 'savanna', cover: true },
  { name: 'savanna_grass_tall_2',        h: 116, aspect: 0.488, r: 0,  w: 0, set: 'savanna', cover: true },
  { name: 'savanna_tree_1',              h: 330, aspect: 0.571, r: 12, w: 0, set: 'savanna' },

  { name: 'wasteland_bush_1',            h: 88,  aspect: 1.523, r: 0,  w: 0, set: 'wasteland', cover: true },
  { name: 'wasteland_small_tree_1',      h: 200, aspect: 1.000, r: 14, w: 0, set: 'wasteland' },
  { name: 'wasteland_tree',              h: 260, aspect: 0.684, r: 14, w: 0, set: 'wasteland' },
  { name: 'wasteland_tree_big_2',        h: 340, aspect: 0.661, r: 16, w: 0, set: 'wasteland' },
  { name: 'wasteland_tree_big_3',        h: 330, aspect: 0.559, r: 16, w: 0, set: 'wasteland' },
  { name: 'wasteland_tree_small_2',      h: 190, aspect: 1.183, r: 14, w: 0, set: 'wasteland' },

  { name: 'farm_wheat_1',                h: 88,  aspect: 0.498, r: 0,  w: 0, set: 'farmland', cover: true },
  { name: 'farm_wheat_2',                h: 72,  aspect: 0.625, r: 0,  w: 0, set: 'farmland', cover: true },
  { name: 'farm_wheat_3',                h: 66,  aspect: 0.654, r: 0,  w: 0, set: 'farmland', cover: true },
  { name: 'farm_wheat_4',                h: 110, aspect: 0.347, r: 0,  w: 0, set: 'farmland', cover: true },

  { name: 'tundra_bush_1',               h: 62,  aspect: 1.608, r: 0,  w: 0, set: 'tundra', cover: true },
  { name: 'tundra_bush_2',               h: 56,  aspect: 1.762, r: 0,  w: 0, set: 'tundra', cover: true },
  { name: 'tundra_bush_3',               h: 56,  aspect: 1.750, r: 0,  w: 0, set: 'tundra', cover: true },
  { name: 'tundra_bush_4',               h: 58,  aspect: 1.728, r: 0,  w: 0, set: 'tundra', cover: true },
  { name: 'tundra_bush_5',               h: 60,  aspect: 1.656, r: 0,  w: 0, set: 'tundra', cover: true },
];

/** Canopy: one to a cell, in the trees array, and it stops you. Tall
 *  enough, or told so — the flag is there for a plant that is short and
 *  still blocks. */
const isCanopy = k => !k.cover && (k.canopy ?? (k.h > 120));

/* How far a flame steps out of the thing it is burning, toward the eye:
   a fraction of the flame's own width, and a fraction of the range. See
   _placeFlames for why either is needed at all. */
const FLAME_NUDGE = 0.30;
const FLAME_NUDGE_RANGE = 0.012;
/* THREE CLASSES, NOT TWO, and they are the golf project's three: firs,
   bushes, ground cover. What changed is that bushes moved out of the
   canopy class and into the understory with the ferns.

   THAT IS WHAT MAKES THE WOOD THICKER WITHOUT MAKING IT A WALL. A bush
   in the canopy class was one per cell and it BLOCKED, so the only way
   to thicken the undergrowth was to fill the wood with obstacles. In the
   understory it is several per cell and you walk through it, which is
   what undergrowth is: the wood reads as dense at eye level and is still
   something you can run through with a fire behind you. Only trunks stop
   you, which is the rule the collision code already had — it looks at
   the canopy class and nothing else. */
const TREE_KINDS  = KINDS.map((k, i) => i).filter(i => isCanopy(KINDS[i]));
const BUSH_KINDS  = KINDS.map((k, i) => i).filter(i => !KINDS[i].cover && !isCanopy(KINDS[i]));
const COVER_KINDS = KINDS.map((k, i) => i).filter(i => KINDS[i].cover);
const TREE_WEIGHT = TREE_KINDS.reduce((a, i) => a + KINDS[i].w, 0);
const BUSH_WEIGHT = BUSH_KINDS.reduce((a, i) => a + KINDS[i].w, 0);

/* THE PLANTING, taken from github.com/verdictzero/golf's own vegetation
   scatter and its documentation of why it is shaped this way.

   ONE CELL GROWS ONE CLASS, and the three weights are a PRIORITY rather
   than three independent probabilities. Firs take their share first and
   are never squeezed — the canopy is the forest, and thickening the
   undergrowth must not thin it. Bushes take theirs out of what the
   trunks left, through a THRESHOLDED clump noise, so scrub arrives in
   thickets rather than as an even speckle over everything. Ground cover
   fills whatever is still empty, which is not a demotion: it is the
   definition of a ground layer, and it thins out on its own exactly
   where the trunks and the thickets are dense.

   AND THE UNDERSTORY IS SEVERAL PLANTS PER CELL. That is the density
   dial that is nearly free: one accepted cell, one hash, several
   jittered plants. Over there ferns are twelve to a cell and two thirds
   of every plant in the world.

   The pairs are (deep in a wood, out in the open), interpolated by the
   wood mask. Open is near zero for firs and for cover on purpose, so
   where the wood is and is not is exactly the shape of that contour;
   bushes stay high in the open because scrub in a clearing is scrub. */
const PLANT = {
  treeForest: 0.46, treeOpen: 0.02,
  bushForest: 0.72, bushOpen: 0.50, bushPerCell: 2,
  coverForest: 0.86, coverOpen: 0.0, coverPerCell: 3,
  /* the thicket threshold: below the low end no bush grows at all, above
     the high end the thicket takes every cell the trunks left */
  bushClumpLo: 0.46, bushClumpHi: 0.72,
};

/* The eight ember colours live in js/palette.js now, because the STORE
   burns in them too — a charred wall and a charred fir have to be the
   same fire going out, and that means one ramp and one clock. */
export { EMBER_RAMP } from './palette.js';

/* The fire's numbers. Durations are in fire tics (a sixth of a game
   tic, so 72 is about twelve seconds); chances are out of 256 per fire
   tic per neighbour, and are what decide the pace. */
export const BURN = {
  /* SLOW AND SURE, and those are two different dials. The first cut had
     a quarter of the wood gone in eight minutes and read as a fuse; the
     obvious fix — lower the chances — put the floor right on the line
     where a fire keeps itself going, and whether a match took depended
     on which trees happened to stand nearby. So the chances stay HIGH
     (a burning cell lights most of its neighbours before it is done)
     and the burn is LONG, with nothing able to spread until it is a
     third of the way through. A ground cell smoulders for ten seconds,
     a tree for eighteen, and a front walks downwind at a cell every
     eight seconds or so, creeps against the wind, and always takes the
     lot in the end. The headless check holds it to that. */
  treeTics: 110, groundTics: 60,
  window: [0.30, 0.90],          // the part of a burn that can light a neighbour
  treeToTree: 5, treeToGround: 4, groundToTree: 5, groundToGround: 4,
  diagonal: 0.6,
  /* THE WIND WAS A PAIR HERE — downwind (+x) 1.55 and upwind 0.55 —
     fixed, and nothing to do with the WIND_X the smoke drifted on.
     Both read js/weather.js now: the same vector, turned into the same
     four multipliers the store's fire uses (windMultipliers in
     js/fire.js), so the smoke goes where the fire is going. At the
     clear night's 0.28 that is 1.21 with it and 0.79 against, which
     is gentler than the old pair; the rain's 0.9 is 1.68 and 0.4. */
};

/* How wide a plant is at a given height, as a fraction of its sprite's
   width. A fir is a trunk for its first tenth, widest a third of the
   way up, and a point at the top; a bush is round. This is what the
   flame tests against, and getting it wrong is a stream that stops dead
   on a trunk-width of empty air beside a tree — which is exactly what
   the first version did, with the canopy's full width treated as solid
   all the way to the ground. */
export function plantRadius(kind, f) {
  if (kind.aspect < 1) {
    if (f < 0.10) return 0.07;
    if (f < 0.30) return 0.07 + (f - 0.10) / 0.20 * 0.43;
    return Math.max(0.03, 0.50 * (1 - (f - 0.30) / 0.70));
  }
  return f < 0.08 || f > 0.96 ? 0.12 : 0.42;
}

/* Per-cell randomness that does not depend on the order cells are
   visited, so the same seed plants the same wood on every machine. */
/* WHERE EACH CLASS STOPS BEING WORTH DRAWING, as [start fading, gone].
   Taken from how tall the thing is: a plant is worth drawing while it is
   still a couple of pixels, and at this game's field of view that is
   about sixty times its own height, and the band is wide so the change
   is a thinning rather than a line on the ground. Trees are the horizon
   and keep the camera's whole range.

   The first cut of these was half as far and it showed: under the
   distant treeline the ground went bare in a hard ring, because the
   forest floor is brown and the thing that makes it read as a forest
   floor is the litter on it. */
/* How big a piece of ground one draw call covers. Small enough that the
   understory's short range keeps only a handful of them, big enough that
   the whole wood is a few hundred meshes rather than thousands. */
const CHUNK = 2048;
/* THE LOD: how many chunk sizes a far-ranging kind is built at (2048,
   4096, 8192), which kinds get it (those whose range reaches LOD_FROM —
   the firs and the bushes; the understory is short-ranged and stays
   fine), and where the bands fall as fractions of the kind's range.
   See build() and _pickLevels(). */
const LOD_LEVELS = 3;
const LOD_FROM = 6000;
const LOD_BAND = [0.28, 0.56];

const FADE = k => k.cover ? [2900, 4800]
                : k.h <= 120 ? [4600, 7200]
                : [13000, 16000];

function hash2(cx, cy, k) {
  let h = (cx * 374761393 + cy * 668265263 + k * 2246822519) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

export class Forest {
  /**
   * @param level  a built Level with forestRects, forestBounds, clearing
   * @param opts   seed; spacing (the clearing kept round the map)
   */
  constructor(level, opts = {}) {
    this.level = level;
    this.seed = opts.seed ?? 5;
    const rects = level.forestRects || [];
    this.rects = rects;
    this.tics = 0;
    this.kindArrays = null;
    this.mesh = null;
    this.flames = null;

    const b = level.forestBounds || [0, 0, 0, 0];
    this.bounds = b;
    this.originX = b[0]; this.originY = b[1];
    /* PLANTS AND NO WOOD: a map that places its own plants and has no
       forest floor for a scatter to grow over — a map made in MEWD Editor
       (js/editor/), whose decorations are placed or spread there. The
       grid is laid over the map so the plants have cells to stand in
       and collide by, and nothing else is grown. */
    const plantsOnly = !rects.length && !!level.plants?.length;
    this.plantsOnly = plantsOnly;
    this.cols = rects.length || plantsOnly ? Math.ceil((b[2] - b[0]) / CELL) : 0;
    this.rows = rects.length || plantsOnly ? Math.ceil((b[3] - b[1]) / CELL) : 0;
    const n = Math.max(1, this.cols * this.rows);

    this.fuel = new Uint8Array(n);        // 1 where there is forest floor
    this.tree = new Uint8Array(n);        // 1 where a tree stands (fire lives longer)
    this.state = new Uint8Array(n);       // 0 green, 1 alight, 2 gone
    this.prog = new Uint8Array(n);        // how far through the burn, 0..255
    this.cellTree = new Int32Array(n).fill(-1);
    /* The understory is SEVERAL plants a cell, laid down contiguously,
       so a cell points at a run of them rather than at one. */
    this.coverStart = new Int32Array(n).fill(-1);
    this.coverCount = new Uint8Array(n);
    this.active = [];
    this._activeSet = new Uint8Array(n);
    this._dirty = [];
    this._dirtySet = new Uint8Array(n);
    this.fuelCells = 0;
    this.burnAccum = 0;                   // sum of prog over every cell, for the fraction
    this.hotCells = 0;

    if (rects.length) {
      this._seed(); this._plant();
      /* AND THE TOWN'S OWN PLANTING, which is not a scatter: a tree in a
         front yard, shrubs along a foundation, a row down the school
         lawn — placed by js/maps/town.js, which knows where the paths
         are, and grown here because this is where plants are drawn. */
      if (level.plants && level.plants.length) this._plantTown(level.plants);
    } else if (plantsOnly) {
      const none = () => ({ x: new Float32Array(0), y: new Float32Array(0), kind: new Uint8Array(0), scale: new Float32Array(0),
                            flip: new Uint8Array(0), seed: new Float32Array(0), cell: new Int32Array(0), n: 0 });
      this.trees = none(); this.covers = none();
      this._plantTown(level.plants);
    }
  }

  /**
   * Add the town's plants to the wood's arrays. A tree takes its cell —
   * one to a cell, the way the wood plants them — so it stops you and
   * the fire knows it is there; a shrub goes in with the understory and
   * you walk through it. The cell under a town tree gets fuel, so the
   * flamethrower can light it and it burns out on its own, but its
   * neighbours have none, so a tree in a yard is a tree on fire and not
   * a forest fire.
   */
  _plantTown(list) {
    const byName = new Map(KINDS.map((k, i) => [k.name, i]));
    const T = this.trees, C = this.covers;
    const tx = Array.from(T.x), ty = Array.from(T.y), tk = Array.from(T.kind), ts = Array.from(T.scale),
          tf = Array.from(T.flip), tseed = Array.from(T.seed), tcell = Array.from(T.cell);
    const gx = Array.from(C.x), gy = Array.from(C.y), gk = Array.from(C.kind), gs = Array.from(C.scale),
          gf = Array.from(C.flip), gseed = Array.from(C.seed), gcell = Array.from(C.cell);
    let n = 0;
    for (const p of list) {
      const ki = byName.get(p.kind);
      if (ki === undefined) continue;
      const cx = this.cellX(p.x), cy = this.cellY(p.y), i = this.idx(cx, cy);
      const k = KINDS[ki];
      const canopy = !k.cover && !BUSH_KINDS.includes(ki);
      if (canopy) {
        if (this.cellTree[i] >= 0) continue;          // one tree to a cell
        tx.push(p.x); ty.push(p.y); tk.push(ki); ts.push(p.scale ?? 1);
        tf.push(hash2(cx, cy, 9) < 0.5 ? 1 : 0); tseed.push(hash2(cx, cy, 11)); tcell.push(i);
        this.cellTree[i] = tx.length - 1;
        this.tree[i] = 1;
        if (!this.fuel[i]) { this.fuel[i] = 1; this.fuelCells++; }
      } else {
        gx.push(p.x); gy.push(p.y); gk.push(ki); gs.push(p.scale ?? 1);
        gf.push(hash2(cx, cy, 13 + n) < 0.5 ? 1 : 0); gseed.push(hash2(cx, cy, 17 + n)); gcell.push(i);
      }
      n++;
    }
    this.trees = { x: Float32Array.from(tx), y: Float32Array.from(ty), kind: Uint8Array.from(tk), scale: Float32Array.from(ts),
                   flip: Uint8Array.from(tf), seed: Float32Array.from(tseed), cell: Int32Array.from(tcell), n: tx.length };
    this.covers = { x: Float32Array.from(gx), y: Float32Array.from(gy), kind: Uint8Array.from(gk), scale: Float32Array.from(gs),
                    flip: Uint8Array.from(gf), seed: Float32Array.from(gseed), cell: Int32Array.from(gcell), n: gx.length };
    this.townPlants = n;
  }

  /* ------------------------------------------------------------------
     The grid
     ------------------------------------------------------------------ */
  idx(cx, cy) { return cy * this.cols + cx; }
  cellX(x) { return clamp(Math.floor((x - this.originX) / CELL), 0, this.cols - 1); }
  cellY(y) { return clamp(Math.floor((y - this.originY) / CELL), 0, this.rows - 1); }
  worldX(cx) { return this.originX + cx * CELL + CELL / 2; }
  worldY(cy) { return this.originY + cy * CELL + CELL / 2; }

  inRects(x, y) {
    for (const r of this.rects) if (x >= r.x0 && x < r.x1 && y >= r.y0 && y < r.y1) return true;
    return false;
  }

  _seed() {
    for (let cy = 0; cy < this.rows; cy++)
      for (let cx = 0; cx < this.cols; cx++) {
        const i = this.idx(cx, cy);
        if (this.inRects(this.worldX(cx), this.worldY(cy))) { this.fuel[i] = 1; this.fuelCells++; }
      }
  }

  /* Planting. Density comes from a noise field so the wood has
     clearings and thickets rather than being a lattice, and every
     plant is jittered off its cell centre so no two rows line up. A
     margin round the clearing stays open, because a forest hard up
     against a car park kerb is a hedge. */
  _plant() {
    const { cols, rows } = this;
    /* THE WOOD MASK. One field, thresholded, so the wood has a shape
       with clearings in it rather than being a uniform speckle — and the
       three classes are read off it together, so the canopy, the scrub
       and the litter under them can never disagree about what a patch of
       ground is. */
    const field = fbm(cols, rows, 9, 3, this.seed * 31 + 7);
    /* one clumping field per class, so a thicket of scrub is not thereby
       a stand of firs */
    const treeClumpF = fbm(cols, rows, 5, 2, this.seed * 17 + 101);
    const bushClumpF = fbm(cols, rows, 6, 2, this.seed * 13 + 211);
    const coverClumpF = fbm(cols, rows, 4, 2, this.seed * 29 + 307);
    const c = this.level.clearing || [0, 0, 0, 0];
    const MARGIN = 150;
    const tx = [], ty = [], tk = [], ts = [], tf = [], tseed = [], tcell = [];
    const gx = [], gy = [], gk = [], gs = [], gf = [], gseed = [], gcell = [];
    const smooth = (a, b, v) => { const t = clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
    const pick = (kinds, weight, r) => {
      let n = r * weight, out = kinds[0];
      for (const k of kinds) { n -= KINDS[k].w; if (n <= 0) { out = k; break; } }
      return out;
    };

    for (let cy = 0; cy < rows; cy++) {
      for (let cx = 0; cx < cols; cx++) {
        const i = this.idx(cx, cy);
        if (!this.fuel[i]) continue;
        const wx = this.worldX(cx), wy = this.worldY(cy);
        if (wx > c[0] - MARGIN && wx < c[2] + MARGIN && wy > c[1] - MARGIN && wy < c[3] + MARGIN) continue;

        /* how much of a wood this is, 0 in the open and 1 deep in it */
        const forest = smooth(0.34, 0.72, field[i]);

        /* the three weights, each through its own clump. The bushes'
           is thresholded rather than scaled — that is the difference
           between ground that is evenly speckled with scrub and ground
           that is mostly clear with thickets in it. */
        const treeClump = 0.55 + treeClumpF[i] * 0.9;
        const coverClump = 0.55 + coverClumpF[i] * 0.9;
        const bushClump = smooth(PLANT.bushClumpLo, PLANT.bushClumpHi, bushClumpF[i]);
        let dTree = (PLANT.treeOpen + (PLANT.treeForest - PLANT.treeOpen) * forest) * treeClump;
        let dBush = (PLANT.bushOpen + (PLANT.bushForest - PLANT.bushOpen) * forest) * bushClump;
        let dCover = (PLANT.coverOpen + (PLANT.coverForest - PLANT.coverOpen) * forest) * coverClump;
        /* and the priority clamp, which is the whole character of it */
        dTree = Math.min(dTree, 1);
        dBush = Math.min(dBush, 1 - dTree);
        dCover = Math.min(dCover, 1 - dTree - dBush);

        const keep = hash2(cx, cy, 1);
        if (keep >= dTree + dBush + dCover) continue;

        if (keep < dTree) {
          /* A FIR. One a cell, and the only class that stops you. */
          const kind = pick(TREE_KINDS, TREE_WEIGHT, hash2(cx, cy, 2));
          tx.push(wx + (hash2(cx, cy, 3) - 0.5) * CELL * 0.8);
          ty.push(wy + (hash2(cx, cy, 4) - 0.5) * CELL * 0.8);
          tk.push(kind);
          ts.push(0.86 + hash2(cx, cy, 5) * 0.32);
          tf.push(hash2(cx, cy, 6) < 0.5 ? 1 : 0);
          tseed.push(hash2(cx, cy, 7));
          tcell.push(i);
          this.cellTree[i] = tx.length - 1;
          this.tree[i] = 1;
          continue;
        }

        /* UNDERSTORY: scrub if the thicket reaches here, litter if it
           does not. Several of them, jittered across the cell, from one
           accepted cell — see PLANT. */
        const bushy = keep < dTree + dBush;
        const kinds = bushy ? BUSH_KINDS : COVER_KINDS;
        const weight = bushy ? BUSH_WEIGHT : 1;
        const n = bushy ? PLANT.bushPerCell : PLANT.coverPerCell;
        this.coverStart[i] = gx.length;
        for (let k = 0; k < n; k++) {
          const lane = 20 + k * 6;
          gx.push(wx + (hash2(cx, cy, lane) - 0.5) * CELL * 0.94);
          gy.push(wy + (hash2(cx, cy, lane + 1) - 0.5) * CELL * 0.94);
          gk.push(bushy ? pick(kinds, weight, hash2(cx, cy, lane + 2))
                        : (hash2(cx, cy, lane + 2) < 0.45 ? COVER_KINDS[0] : COVER_KINDS[1]));
          gs.push(0.78 + hash2(cx, cy, lane + 3) * 0.55);
          gf.push(hash2(cx, cy, lane + 4) < 0.5 ? 1 : 0);
          gseed.push(hash2(cx, cy, lane + 5));
          gcell.push(i);
        }
        this.coverCount[i] = n;
      }
    }
    this.trees = { x: Float32Array.from(tx), y: Float32Array.from(ty), kind: Uint8Array.from(tk), scale: Float32Array.from(ts),
                   flip: Uint8Array.from(tf), seed: Float32Array.from(tseed), cell: Int32Array.from(tcell), n: tx.length };
    this.covers = { x: Float32Array.from(gx), y: Float32Array.from(gy), kind: Uint8Array.from(gk), scale: Float32Array.from(gs),
                    flip: Uint8Array.from(gf), seed: Float32Array.from(gseed), cell: Int32Array.from(gcell), n: gx.length };
  }

  /* ------------------------------------------------------------------
     Setting it alight
     ------------------------------------------------------------------ */
  /** Light every green cell within `radius` of a point. Returns how many. */
  ignite(x, y, radius = 40) {
    /* and in a world where nothing catches, no plant does either */
    if (!this.cols || this.level.noBurn) return 0;
    const cx0 = this.cellX(x - radius), cx1 = this.cellX(x + radius);
    const cy0 = this.cellY(y - radius), cy1 = this.cellY(y + radius);
    let lit = 0;
    for (let cy = cy0; cy <= cy1; cy++)
      for (let cx = cx0; cx <= cx1; cx++) {
        const i = this.idx(cx, cy);
        if (!this.fuel[i] || this.state[i] !== 0) continue;
        this._light(i); lit++;
      }
    return lit;
  }

  /** And putting it out: an alight cell goes back to green if it has
   *  hardly started and to gone if it has, because a tree that is half
   *  burnt is not a tree you have saved. The line is a third of the way
   *  through, which is about where a fir stops being a fir. */
  douse(x, y, radius = 40) {
    if (!this.cols) return 0;
    const cx0 = this.cellX(x - radius), cx1 = this.cellX(x + radius);
    const cy0 = this.cellY(y - radius), cy1 = this.cellY(y + radius);
    const r2 = radius * radius;
    let out = 0;
    for (let cy = cy0; cy <= cy1; cy++)
      for (let cx = cx0; cx <= cx1; cx++) {
        const i = this.idx(cx, cy);
        if (this.state[i] !== 1) continue;
        const dx = this.worldX(cx) - x, dy = this.worldY(cy) - y;
        if (dx * dx + dy * dy > r2) continue;
        this.state[i] = this.prog[i] < 85 ? 0 : 2;
        if (this.state[i] === 0) this.prog[i] = 0;
        this._activeSet[i] = 0;
        this._mark(i);
        out++;
      }
    return out;
  }

  _light(i) {
    this.state[i] = 1;
    this.prog[i] = 1;
    if (!this._activeSet[i]) { this._activeSet[i] = 1; this.active.push(i); }
    this._mark(i);
  }

  _mark(i) {
    if (this._dirtySet[i]) return;
    this._dirtySet[i] = 1;
    this._dirty.push(i);
  }

  get burnFraction() { return this.fuelCells ? this.burnAccum / (255 * this.fuelCells) : 0; }
  get burningCells() { return this.hotCells; }
  get treeCount() { return this.trees ? this.trees.n : 0; }
  get plantCount() { return this.treeCount + (this.covers ? this.covers.n : 0); }

  /* ------------------------------------------------------------------
     One step of the fire
     ------------------------------------------------------------------ */
  tic() {
    this.tics++;
    if (!this.cols || this.tics % FIRE_INTERVAL) return;
    const { state, prog, fuel, tree, cols, rows } = this;
    const [w0, w1] = BURN.window;
    const next = [];
    let hot = 0;
    const [mE, mN, mW, mS] = windMultipliers(climate.wind.x, climate.wind.y);
    /* the rain, on a wood that is all under the sky: a burn that has
       hardly started goes out, and nothing lights easily */
    const rain = climate.rain;
    const rainSpread = 1 - 0.8 * rain;
    for (let k = 0; k < this.active.length; k++) {
      const i = this.active[k];
      const dur = tree[i] ? BURN.treeTics : BURN.groundTics;
      const step = Math.max(1, Math.round(255 / dur));
      const before = prog[i];
      const after = Math.min(255, before + step);
      if (rain > 0 && before < 85 && pChance(Math.round(rain * 14))) {
        /* put out early: back to green, the way douse does it */
        state[i] = 0; prog[i] = 0; this._activeSet[i] = 0; this._mark(i); continue;
      }
      prog[i] = after;
      this.burnAccum += after - before;
      this._mark(i);
      const t = after / 255;
      if (after >= 255) { state[i] = 2; this._activeSet[i] = 0; continue; }
      next.push(i);
      if (t < w0 || t > w1) continue;
      hot++;

      /* spread, to the eight neighbours, with the wind */
      const cx = i % cols, cy = (i / cols) | 0;
      const fromTree = tree[i];
      for (let dy = -1; dy <= 1; dy++) {
        const ny = cy + dy;
        if (ny < 0 || ny >= rows) continue;
        for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dy) continue;
          const nx = cx + dx;
          if (nx < 0 || nx >= cols) continue;
          const j = ny * cols + nx;
          if (!fuel[j] || state[j] !== 0) continue;
          let chance = fromTree ? (tree[j] ? BURN.treeToTree : BURN.treeToGround)
                                : (tree[j] ? BURN.groundToTree : BURN.groundToGround);
          if (dx && dy) chance *= BURN.diagonal;
          if (dx > 0) chance *= mE; else if (dx < 0) chance *= mW;
          if (dy > 0) chance *= mN; else if (dy < 0) chance *= mS;
          chance *= rainSpread;
          if (pChance(Math.round(chance))) this._light(j);
        }
      }
    }
    this.active = next;
    this.hotCells = hot;
  }

  /* ------------------------------------------------------------------
     Questions the rest of the game asks
     ------------------------------------------------------------------ */
  /** Is a circle at (x,y) inside a trunk? Bushes count; ferns do not. */
  blocks(x, y, radius) {
    if (!this.cols || !this.trees) return false;
    const cx = this.cellX(x), cy = this.cellY(y);
    for (let dy = -1; dy <= 1; dy++) {
      const ny = cy + dy;
      if (ny < 0 || ny >= this.rows) continue;
      for (let dx = -1; dx <= 1; dx++) {
        const nx = cx + dx;
        if (nx < 0 || nx >= this.cols) continue;
        const t = this.cellTree[ny * this.cols + nx];
        if (t < 0) continue;
        const kr = KINDS[this.trees.kind[t]].r * this.trees.scale[t];
        if (kr <= 0) continue;
        const rr = kr + radius;
        if (dist2(x, y, this.trees.x[t], this.trees.y[t]) < rr * rr) return true;
      }
    }
    return false;
  }

  /** Does a point in the air touch a plant — the flame's question. */
  hitsTree(x, y, z) {
    if (!this.cols || !this.trees) return false;
    const cx = this.cellX(x), cy = this.cellY(y);
    for (let dy = -1; dy <= 1; dy++) {
      const ny = cy + dy;
      if (ny < 0 || ny >= this.rows) continue;
      for (let dx = -1; dx <= 1; dx++) {
        const nx = cx + dx;
        if (nx < 0 || nx >= this.cols) continue;
        const t = this.cellTree[ny * this.cols + nx];
        if (t < 0) continue;
        const k = KINDS[this.trees.kind[t]], s = this.trees.scale[t];
        const h = k.h * s;
        if (z < 0 || z > h) continue;
        const reach = plantRadius(k, z / h) * k.h * k.aspect * s;
        if (dist2(x, y, this.trees.x[t], this.trees.y[t]) < reach * reach) return true;
      }
    }
    return false;
  }

  /** Keep something inside the wood. */
  clampInside(o, margin = 48) {
    if (!this.cols) return;
    const b = this.bounds;
    o.x = clamp(o.x, b[0] + margin, b[2] - margin);
    o.y = clamp(o.y, b[1] + margin, b[3] - margin);
  }

  /** Add what is burning near a point to a light's centre of mass. */
  glowInto(acc, px, py, range = 900) {
    if (!this.active.length) return;
    const r2 = range * range;
    const step = Math.max(1, this.active.length >> 7);
    for (let k = 0; k < this.active.length; k += step) {
      const i = this.active[k];
      const t = this.prog[i] / 255;
      const q = (t - 0.5) / 0.3;
      const w = Math.exp(-q * q) * (this.tree[i] ? 1.3 : 0.45) * step;
      if (w < 0.01) continue;
      const x = this.worldX(i % this.cols), y = this.worldY((i / this.cols) | 0);
      const d2 = dist2(x, y, px, py);
      if (d2 > r2) continue;
      acc.sx += x * w; acc.sy += y * w; acc.sw += w; acc.n++;
    }
  }

  /** Up to `n` burning cells within range, for things to rise off. Each
   *  entry: x, y, h (how tall what is burning is), t (how far through). */
  emitters(px, py, range, n, out) {
    out.length = 0;
    const len = this.active.length;
    if (!len) return 0;
    const r2 = range * range;
    let k = (pRandom() * 256 + pRandom()) % len;
    const tries = Math.min(len, n * 6);
    for (let m = 0; m < tries && out.length < n; m++) {
      const i = this.active[(k + m * 7919) % len];
      const t = this.prog[i] / 255;
      if (t < 0.1 || t > 0.92) continue;
      const x = this.worldX(i % this.cols), y = this.worldY((i / this.cols) | 0);
      if (dist2(x, y, px, py) > r2) continue;
      const ti = this.cellTree[i];
      const h = ti >= 0 ? KINDS[this.trees.kind[ti]].h * this.trees.scale[ti] : 30;
      out.push({ x: ti >= 0 ? this.trees.x[ti] : x, y: ti >= 0 ? this.trees.y[ti] : y, h, t, tree: ti >= 0 });
    }
    return out.length;
  }

  /* ------------------------------------------------------------------
     Drawing
     ------------------------------------------------------------------ */
  /**
   * @param scene  where the meshes go
   * @param art    { sprites: { name: { albedo, burn } }, ground, groundBurnt }
   *               — decoded images
   */
  build(scene, art) {
    if (this.mesh || !this.cols) return;
    this.mesh = new THREE.Group();
    this.mesh.name = 'forest';
    this.kindArrays = [];
    this.uTime = { value: 0 };
    this.uRot = { value: 0 };
    this.uWind = { value: new THREE.Vector3(1, 0, 0.3) };
    const ramp = EMBER_RAMP.map(c => new THREE.Vector3(c[0], c[1], c[2]));

    /* the ground */
    this.mask = new THREE.DataTexture(new Uint8Array(this.cols * this.rows), this.cols, this.rows, THREE.RedFormat, THREE.UnsignedByteType);
    this.mask.magFilter = THREE.LinearFilter;
    this.mask.minFilter = THREE.LinearFilter;
    this.mask.wrapS = this.mask.wrapT = THREE.ClampToEdgeWrapping;
    this.mask.generateMipmaps = false;
    this.mask.needsUpdate = true;
    const groundTex = img => {
      const t = new THREE.Texture(img);
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestMipmapLinearFilter;
      t.colorSpace = THREE.SRGBColorSpace;
      t.needsUpdate = true;
      return t;
    };
    const pos = [];
    for (const r of this.rects) {
      pos.push(r.x0, 0, -r.y0,  r.x1, 0, -r.y0,  r.x1, 0, -r.y1);
      pos.push(r.x0, 0, -r.y0,  r.x1, 0, -r.y1,  r.x0, 0, -r.y1);
    }
    const gg = new THREE.BufferGeometry();
    gg.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
    gg.computeBoundingSphere();
    const gm = new THREE.ShaderMaterial({
      uniforms: {
        map: { value: groundTex(art.ground) }, mapBurnt: { value: groundTex(art.groundBurnt) },
        mask: { value: this.mask },
        maskRect: { value: new THREE.Vector4(this.originX, this.originY, 1 / (this.cols * CELL), 1 / (this.rows * CELL)) },
        light: { value: 0.56 }, uTime: this.uTime, ramp: { value: ramp },
        ...worldUniforms(),
      },
      vertexShader: GROUND_VERT, fragmentShader: GROUND_FRAG, toneMapped: false, fog: false,
    });
    const ground = new THREE.Mesh(gg, gm);
    ground.name = 'forest-ground';
    ground.frustumCulled = false;
    this.mesh.add(ground);

    /* the plants, one draw call per kind */
    const base = new THREE.PlaneGeometry(1, 1);
    base.translate(0, 0.5, 0);
    const spriteTex = (img, data) => {
      const t = new THREE.Texture(img);
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestMipmapNearestFilter;
      t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
      t.colorSpace = data ? THREE.NoColorSpace : THREE.SRGBColorSpace;
      t.needsUpdate = true;
      return t;
    };
    /* ONE MESH PER KIND PER CHUNK, and that is the whole of how a much
       thicker wood costs less than a thin one did.

       The cost of this forest is LINEAR IN INSTANCES SUBMITTED and has
       nothing to do with how much of the screen they cover: measured in
       a software rasteriser, a hundred thousand plants cost a second a
       frame whether they were drawn as a wall of green or collapsed to
       nothing by the fade in the vertex shader. Collapsing the quad
       saves the fill; it does not save the vertex, and the vertex was
       the bill.

       So the plants are cut into square chunks of ground and each chunk
       is its own draw. A chunk gets a real bounding sphere, so three.js
       frustum-culls the two thirds of the wood that is behind you for
       free; and each kind hides the chunks past its own fade range, so
       the fern carpet — which is most of the plants and is invisible at
       two thousand units — is submitted for the ground you are standing
       on and nowhere else. What reaches the GPU is a few thousand of a
       hundred and seventy thousand.

       The draw calls go up, from one a kind to a few a kind, and that
       is the trade: a handful of draws against a hundred thousand
       vertices, which is not a close call. */
    /* AND THE CHUNKS HAVE THREE SIZES, WHICH IS THE LOD. A tree at a
       distance is the same four vertices as a tree up close, so there
       is nothing to make cheaper about the tree; what there is to make
       cheaper is the DRAW. With 2048-unit chunks and the firs kept to
       sixteen thousand, the wood in front of you is two or three
       hundred draws a kind — and a draw is the thing a phone runs out
       of first. So the firs and the bushes are built three times over
       into 2048, 4096 and 8192-unit chunks of the same plants, and each
       frame every patch of ground is drawn from exactly ONE of the
       three: fine near the eye, where frustum culling wants small
       pieces, coarse at range, where forty small pieces are one. The
       rule that makes it exact is in render(): a coarse chunk is drawn
       only when every fine chunk under it is far enough to be, and a
       fine chunk only when neither of its parents is. The understory
       stays fine — its range is short enough that it is a handful of
       chunks already. See LOD_LEVELS and LOD_BAND. */
    KINDS.forEach((k, ki) => {
      /* THE BUSHES ARE IN THE UNDERSTORY'S ARRAYS — several a cell,
         planted beside the ferns (see _plant) — and this read them out
         of the canopy's, where there are none, so not one bush was
         ever drawn: the art loaded, the plants were planted, the fire
         burnt them, and the wood was firs over ferns. Found while the
         LOD was being tested headless, which counts what is built. */
      const src = (k.cover || BUSH_KINDS.includes(ki)) ? this.covers : this.trees;
      const list = [];
      for (let i = 0; i < src.n; i++) if (src.kind[i] === ki) list.push(i);
      const n = list.length;
      const A = { levels: [], chunks: [], n, cover: !!k.cover, far: FADE(k)[1], lod: !k.cover && FADE(k)[1] >= LOD_FROM };
      this.kindArrays[ki] = A;
      if (!n || !art.sprites[k.name]) return;

      const albedo = spriteTex(art.sprites[k.name].albedo, false);
      const burnTex = spriteTex(art.sprites[k.name].burn, true);
      const nLevels = A.lod ? LOD_LEVELS : 1;
      for (let L = 0; L < nLevels; L++) {
        const CH = CHUNK << L;
        const level = { ch: CH, chunks: [], slot: new Int32Array(src.n).fill(-1), chunkOf: new Int32Array(src.n).fill(-1), byKey: new Map() };
        A.levels.push(level);
        /* group by chunk of ground */
        const by = new Map();
        for (const i of list) {
          const cx = Math.floor((src.x[i] - this.originX) / CH);
          const cy = Math.floor((src.y[i] - this.originY) / CH);
          const key = cy * 4096 + cx;
          let g2 = by.get(key);
          if (!g2) by.set(key, g2 = { cx, cy, list: [] });
          g2.list.push(i);
        }
        for (const c of by.values()) {
          const m2 = c.list.length;
          const pos = new Float32Array(m2 * 3), size = new Float32Array(m2 * 2);
          const flip = new Float32Array(m2), burn = new Float32Array(m2), seed = new Float32Array(m2);
          let maxH = 0;
          c.list.forEach((i, sIdx) => {
            const sc = src.scale[i], h = k.h * sc, w = h * k.aspect;
            pos[sIdx * 3] = src.x[i]; pos[sIdx * 3 + 1] = 0; pos[sIdx * 3 + 2] = -src.y[i];
            size[sIdx * 2] = w; size[sIdx * 2 + 1] = h;
            flip[sIdx] = src.flip[i]; seed[sIdx] = src.seed[i];
            burn[sIdx] = this.prog[src.cell[i]] / 255;
            if (h > maxH) maxH = h;
            level.slot[i] = sIdx;
            level.chunkOf[i] = level.chunks.length;
          });
          const g = new THREE.InstancedBufferGeometry();
          g.index = base.index;
          g.setAttribute('position', base.getAttribute('position'));
          g.setAttribute('uv', base.getAttribute('uv'));
          g.setAttribute('iPos', new THREE.InstancedBufferAttribute(pos, 3));
          g.setAttribute('iSize', new THREE.InstancedBufferAttribute(size, 2));
          g.setAttribute('iFlip', new THREE.InstancedBufferAttribute(flip, 1));
          const burnAttr = new THREE.InstancedBufferAttribute(burn, 1).setUsage(THREE.DynamicDrawUsage);
          g.setAttribute('iBurn', burnAttr);
          g.setAttribute('iSeed', new THREE.InstancedBufferAttribute(seed, 1));
          g.instanceCount = m2;
          /* The bounding sphere is the chunk of ground plus the tallest
             thing standing on it. Without one three.js has to compute it
             from `position`, which for an instanced quad is a unit square
             at the origin — every chunk would claim to be at the origin
             and the frustum cull would be wrong in both directions. */
          const wx = this.originX + (c.cx + 0.5) * CH, wy = this.originY + (c.cy + 0.5) * CH;
          g.boundingSphere = new THREE.Sphere(
            new THREE.Vector3(wx, maxH * 0.5, -wy),
            Math.hypot(CH * 0.5, CH * 0.5) + maxH);
          const mat = new THREE.ShaderMaterial({
            uniforms: {
              map: { value: albedo }, burnMap: { value: burnTex },
              billboardRot: this.uRot, uTime: this.uTime, uWind: this.uWind, ramp: { value: ramp },
              fadeBand: { value: new THREE.Vector2(...FADE(k)) },
              light: { value: 0.56 },
              ...worldUniforms(),
            },
            vertexShader: PLANT_VERT, fragmentShader: PLANT_FRAG,
            side: THREE.DoubleSide, toneMapped: false, fog: false,
          });
          const m = new THREE.Mesh(g, mat);
          m.name = `forest-${k.name}-L${L}-${c.cx}-${c.cy}`;
          m.visible = false;
          m.userData.chunk = { x: wx, y: wy, far: A.far + CH, level: L, cx: c.cx, cy: c.cy };
          const ch = { burn, burnAttr, mesh: m, cx: c.cx, cy: c.cy, x: wx, y: wy, level: L, band: 0, drawn: false,
                       /* WHICH REGIONS THE CHUNK STANDS IN, for the portal flood:
                          nine points across it. The wood's regions are
                          fourteen big rectangles, so nine is plenty, and a
                          chunk none of whose points is in a visible region is
                          not drawn — see render() */
                       sectors: this._chunkSectors(wx, wy, CH, c.list.map(i => [src.x[i], src.y[i]])) };
          level.chunks.push(ch);
          level.byKey.set(c.cy * 4096 + c.cx, ch);
          this.mesh.add(m);
        }
      }
      A.chunks = A.levels[0].chunks;
    });
    scene.add(this.mesh);
    this._flush();
  }

  /* Push every changed cell into the mask and the instance buffers. */
  _flush() {
    if (!this._dirty.length) return;
    const built = !!this.mesh;
    const touched = new Set();
    for (const i of this._dirty) {
      this._dirtySet[i] = 0;
      if (!built) continue;
      const v = this.prog[i];
      this.mask.image.data[i] = v;
      const paint = (A, idx) => {
        for (const level of A.levels) {
          const ch = level.chunks[level.chunkOf[idx]];
          const s = level.slot[idx];
          if (!ch || s < 0) continue;
          ch.burn[s] = v / 255;
          touched.add(ch);
        }
      };
      const t = this.cellTree[i];
      if (t >= 0) paint(this.kindArrays[this.trees.kind[t]], t);
      const c0 = this.coverStart[i];
      for (let c = c0; c >= 0 && c < c0 + this.coverCount[i]; c++)
        paint(this.kindArrays[this.covers.kind[c]], c);
    }
    this._dirty.length = 0;
    if (!built) return;
    this.mask.needsUpdate = true;
    for (const ch of touched) ch.burnAttr.needsUpdate = true;
  }

  /** The distinct sectors under a chunk's nine sample points. */
  _chunkSectors(wx, wy, ch, plants = null) {
    const out = [];
    for (let j = -1; j <= 1; j++)
      for (let i = -1; i <= 1; i++) {
        const s = this.level.sectorAt(wx + i * ch * 0.42, wy + j * ch * 0.42);
        if (s && !out.includes(s)) out.push(s);
      }
    /* AND THE GROUND UNDER THE PLANTS THEMSELVES. Nine points across a
       chunk are plenty in a wood of fourteen big regions and nothing
       like enough in a town, where a chunk covers forty yards and the
       nine points land in nine of them — or in the houses, which are no
       region at all. So a chunk in the town also knows the region under
       each of its plants, up to a few dozen, sampled evenly. */
    if (plants && plants.length) {
      const step = Math.max(1, Math.ceil(plants.length / 40));
      for (let k = 0; k < plants.length && out.length < 64; k += step) {
        const s = this.level.sectorAt(plants[k][0], plants[k][1]);
        if (s && !out.includes(s)) out.push(s);
      }
    }
    return out;
  }

  /** Can the eye see into any region this chunk stands in? A chunk
   *  standing in no region at all is off the map and always can. */
  _chunkSeen(ch) {
    const lv = this.level;
    if (!lv.isVisible || !ch.sectors || !ch.sectors.length) return true;
    for (let i = 0; i < ch.sectors.length; i++) if (lv.isVisible(ch.sectors[i])) return true;
    return false;
  }

  render(camX, camY, camZ, billboardRot, time, reach = 1) {
    if (!this.mesh) { if (this._dirty.length > 4096) this._flush(); return; }
    this.uRot.value = billboardRot;
    this.uTime.value = time;
    /* the wind: which way on the ground (map y is world -z), and how
       hard — a still night barely moves the leaves, a storm bends the
       firs; see the WIND IN THE LEAVES in PLANT_VERT */
    const wx = climate.wind.x, wy = climate.wind.y, wl = Math.hypot(wx, wy);
    if (wl > 1e-6) this.uWind.value.set(wx / wl, -wy / wl, Math.min(2.2, Math.max(0.15, wl / 0.4)));
    else this.uWind.value.z = 0.15;
    this._flush();
    /* Hide the chunks past their kind's range. The frustum takes care of
       the ones behind you; this takes care of the ones in front and too
       far to resolve, which for the understory is nearly all of them. */
    /* and how far in is a setting: the wood is the most expensive thing
       in the frame by a long way, so the pause menu can pull its range
       in. `reach` is game.quality.wood — see js/game.js. */
    for (const A of this.kindArrays) {
      if (!A || !A.chunks.length) continue;
      if (!A.lod) {
        for (const ch of A.chunks) {
          const dx = ch.x - camX, dy = ch.y - camY;
          const far = (A.far + CHUNK) * reach;
          ch.mesh.visible = dx * dx + dy * dy < far * far && this._chunkSeen(ch);
        }
        continue;
      }
      this._pickLevels(A, camX, camY, reach);
      /* and, whichever size was picked, not through a wall: the flood's
         answer is laid over the LOD's, so a coarse chunk behind the
         store goes the same way a fine one does */
      for (const L of A.levels) for (const ch of L.chunks) if (ch.mesh.visible && !this._chunkSeen(ch)) ch.mesh.visible = false;
    }
    if (this.flames) { this._placeFlames(camX, camY, camZ); this.flames.render(billboardRot); }
  }

  /** THE LOD, decided fine-chunk first so every plant is drawn once.
   *  Each fine chunk gets a BAND off its distance: 0 near, 1 middle,
   *  2 far (LOD_BAND, as fractions of the kind's range), or hidden
   *  past the range. A level-2 chunk is drawn when every fine chunk
   *  under it is in band 2; a level-1 chunk when every fine chunk under
   *  it is in band 1 or 2 and its level-2 parent is not drawn; a fine
   *  chunk when it is in range and neither parent is drawn. */
  _pickLevels(A, camX, camY, reach) {
    const [L0, L1, L2] = A.levels;
    const range = A.far * reach;
    const far0 = (A.far + CHUNK) * reach;
    const t1 = range * LOD_BAND[0], t2 = range * LOD_BAND[1];
    for (const ch of L0.chunks) {
      const dx = ch.x - camX, dy = ch.y - camY, d2 = dx * dx + dy * dy;
      ch.band = d2 >= far0 * far0 ? 3 : d2 >= t2 * t2 ? 2 : d2 >= t1 * t1 ? 1 : 0;
      ch.drawn = false;
    }
    /* coarsest first: a level-2 chunk holds sixteen fine ones */
    for (const ch of L2.chunks) {
      let all = true, any = false;
      for (let j = 0; j < 4 && all; j++) for (let i = 0; i < 4; i++) {
        const f = L0.byKey.get((ch.cy * 4 + j) * 4096 + ch.cx * 4 + i);
        if (!f) continue;
        if (f.band === 3) continue;          // out of range: not drawn by anybody
        any = true;
        if (f.band < 2) { all = false; break; }
      }
      ch.drawn = all && any;
      ch.mesh.visible = ch.drawn;
    }
    for (const ch of L1.chunks) {
      const parent = L2.byKey.get((ch.cy >> 1) * 4096 + (ch.cx >> 1));
      let all = !(parent && parent.drawn), any = false;
      for (let j = 0; j < 2 && all; j++) for (let i = 0; i < 2; i++) {
        const f = L0.byKey.get((ch.cy * 2 + j) * 4096 + ch.cx * 2 + i);
        if (!f) continue;
        if (f.band === 3) continue;
        any = true;
        if (f.band < 1) { all = false; break; }
      }
      ch.drawn = all && any;
      ch.mesh.visible = ch.drawn;
    }
    for (const ch of L0.chunks) {
      const p1 = L1.byKey.get((ch.cy >> 1) * 4096 + (ch.cx >> 1));
      const p2 = L2.byKey.get((ch.cy >> 2) * 4096 + (ch.cx >> 2));
      ch.drawn = ch.band < 3 && !(p1 && p1.drawn) && !(p2 && p2.drawn);
      ch.mesh.visible = ch.drawn;
    }
  }

  /* ------------------------------------------------------------------
     Actual fire

     The burn map turns a tree black and puts coals on it; this puts
     FLAMES on it. A pool of instanced flame quads (one draw call) is
     re-parked every frame on the hottest burning cells near the eye —
     the same trick the store's fire uses, done as instances. A burning
     fir carries its flame at the height the front has climbed to, so
     the fire is seen going up the tree; the ground burns at the ground.
     ------------------------------------------------------------------ */
  attachFlames(scene, atlas) {
    if (this.flames || !atlas) return;
    this.flames = new Particles({
      max: 200, texture: atlas.texture, frames: atlas.frames,
      blend: 'add', fullbright: true, name: 'wood-flames', renderOrder: 13, nearShrink: 60,
    });
    this.flames.attach(scene);
    this._flameCand = [];
  }

  _placeFlames(camX, camY, camZ) {
    const F = this.flames;
    F.killAll();
    const cand = this._flameCand;
    cand.length = 0;
    const R2 = 1700 * 1700;
    /* AND THE FAR FIRE, as a handful of very big flames. Past R2, out to
       the air's reach, the burning cells are gathered into clumps of
       eight cells on a side and each clump is ONE flame at the middle of
       its fire, sized by how much of it is alight — the same rule the
       store's fire draws by (FireSystem.render), and the reason a wood
       burning across the valley reads as a wood burning rather than as a
       glow with nothing in it. The first cut drew nothing past R2. */
    const far = Math.min(6000, (climate.airFar || 6000) * 0.96), FAR2 = far * far;
    const clumps = this._flameClumps || (this._flameClumps = new Map());
    clumps.clear();
    /* a sample of a big fire, every cell of a small one */
    const step = Math.max(1, this.active.length >> 9);
    for (let k = 0; k < this.active.length; k += step) {
      const i = this.active[k];
      const t = this.prog[i] / 255;
      if (t < 0.05 || t > 0.93) continue;
      const x = this.worldX(i % this.cols), y = this.worldY((i / this.cols) | 0);
      const d2 = dist2(x, y, camX, camY);
      if (d2 > FAR2) continue;
      const q = (t - 0.45) / 0.35;
      const heat = Math.exp(-q * q);
      if (d2 > R2) {
        const key = (((i / this.cols) | 0) >> 3) * 65536 + ((i % this.cols) >> 3);
        let g = clumps.get(key);
        if (!g) clumps.set(key, g = { i, sx: 0, sy: 0, w: 0, n: 0 });
        g.sx += x * heat; g.sy += y * heat; g.w += heat; g.n++;
        continue;
      }
      cand.push({ i, x, y, t, heat, big: 0, key: d2 / (0.3 + heat) });
    }
    for (const g of clumps.values()) {
      if (g.w < 0.05) continue;
      const x = g.sx / g.w, y = g.sy / g.w;
      /* first in the queue: there are few, and each is a great deal of
         fire. `big` is about how many cells it stands for, and is what
         sets its size. */
      cand.push({ i: g.i, x, y, t: 0.45, heat: Math.min(1, g.w / 3), big: g.n * step, key: -1e12 + dist2(x, y, camX, camY) });
    }
    cand.sort((a, b) => a.key - b.key);
    const n = Math.min(F.max, cand.length);
    const tics = this.tics;
    for (let s = 0; s < n; s++) {
      const c = cand[s];
      const ti = c.big ? -1 : this.cellTree[c.i];
      let x = c.x, y = c.y, base = 0, w;
      if (c.big) {
        /* a clump's flame is the size of the fire it stands for: a few
           cells is a bonfire, a hillside is a wall of it — and it is a
           long way off, so what looks enormous here is a few dozen
           pixels there */
        w = (420 + Math.min(760, c.big * 16)) * (0.55 + c.heat * 0.45);
      } else if (ti >= 0) {
        const k = KINDS[this.trees.kind[ti]], th = k.h * this.trees.scale[ti];
        x = this.trees.x[ti]; y = this.trees.y[ti];
        w = Math.max(44, th * (k.aspect < 1 ? 0.40 : 0.85)) * (0.6 + c.heat * 0.6);
        /* The fire climbs the trunk as the tree goes — and STOPS AT THE
           CROWN. The foot alone used to be allowed up to six sevenths of
           the height, and the flame standing on it is most of the tree
           again, so a fir well alight carried its fire in the air above
           itself like a paper lantern on a pole. Held to the top of the
           tree, the flame straddles the crown instead, which is where a
           fir burns. */
        base = Math.min(th * clamp(c.t * 1.1, 0.02, 0.86), th * 1.10 - w * (1 - FLAME_FOOT));
      } else w = 30 + c.heat * 26;
      /* the quad is centred; the art's round foot wants to sit on `base` */
      let z = base + w * (0.5 - FLAME_FOOT);

      /* TOWARD THE EYE, or the fire is inside the tree.

         A burning fir carries its flame at the tree's own x and y, and
         both of them are quads yawed to face the camera plane — which
         makes them PARALLEL SURFACES AT THE SAME DEPTH. The depth test
         cannot separate two of those: it comes out per pixel, differently
         every frame as the eye moves, and a fire in a tree turns into a
         shimmering checkerboard of fire and leaves. Drawing order does
         not fix it, because the fault is that the depths are equal, not
         the order they arrive in.

         So the flame is stepped ALONG THE LINE TO THE EYE, and shrunk by
         the same fraction as it comes. That pair is the whole trick: a
         perspective projection is a scaling about the eye, so a quad
         moved a tenth of the way in and made a tenth smaller lands on
         exactly the same pixels at exactly the same size. Nothing about
         the picture changes. The only thing that changes is the depth it
         writes, which is what was wrong.

         How far: a share of the flame's OWN SIZE, so a fire big enough to
         swallow a fir clears the whole of it and one guttering on the
         ground barely moves, plus a share of the RANGE, because a depth
         buffer's resolution falls away with the square of the distance
         and a step that separates them at fifty units is nothing at two
         thousand. Never more than halfway, so a flame you are standing
         in front of cannot arrive behind your head. */
      const ex = camX - x, ey = camY - y, ez = camZ - z;
      const range = Math.max(1, Math.sqrt(ex * ex + ey * ey + ez * ez));
      const pull = Math.min(0.5, (w * FLAME_NUDGE + range * FLAME_NUDGE_RANGE) / range);
      x += ex * pull; y += ey * pull; z += ez * pull;

      F.spawn({
        x, y, z, life: 2, size: w * (1 - pull),
        c0: [1, 1, 1], a0: 0.5 + c.heat * 0.5,
        frame: ((tics >> 1) + c.i * 7) % F.opts.frames,
      });
    }
  }
}

/* --------------------------------------------------------------------
   The shaders
   ------------------------------------------------------------------ */
const PLANT_VERT = /* glsl */`
attribute vec3  iPos;
attribute vec2  iSize;
attribute float iFlip;
attribute float iBurn;
attribute float iSeed;
uniform float billboardRot;
uniform float uTime;
/* THE WIND IN THE LEAVES, at the user's request: the weather's wind
   (climate.wind, map units a tic) as a world direction and a strength —
   see ForestSystem.render */
uniform vec3  uWind;
/* How far this KIND is worth drawing, and over how far it goes away.
   See FADE below for why the understory has a much shorter one. */
uniform vec2  fadeBand;
varying vec2  vUv;
varying float vBurn;
varying float vSeed;
varying float vDepth;
varying vec3  vWorld;
/* the sector the plant stands in, in a map from the editor: its light
   and thing colour, and its fog — see js/sectorgrid.js */
varying vec4  vSecLight;
varying vec4  vFog;
${SECTOR_GRID_GLSL}

void main() {
  vSecLight = vec4(1.0, 1.0, 1.0, -1.0);
  vFog = vec4(0.0, 0.0, 0.0, -1.0);
  if (sectorOn > 0.5) { vSecLight = sectorLightAt(iPos); vFog = sectorFogAt(iPos); }
  /* Half the plants are mirrored, chosen when they were planted: ten
     sprites over fifty thousand plants is a lot of repeat, and a flip
     doubles the apparent variety for nothing. */
  vUv = vec2(iFlip > 0.5 ? 1.0 - uv.x : uv.x, uv.y);
  vBurn = iBurn;
  vSeed = iSeed;
  /* THE UNDERSTORY STOPS. A fern is forty-six units tall, which is
     under two pixels at three thousand and a quarter of one at twelve —
     and there are a hundred and forty thousand of them. Drawn to the
     horizon they cost a full screen of overdraw for a haze you cannot
     resolve; dropped at their own range they cost nothing and look
     identical, because a wood seen from two thousand units away is
     trunks and canopy, which is the class that keeps its range.

     Done in the VERTEX SHADER rather than by re-packing the instance
     buffers: the quad collapses to a point and rasterises nothing, so
     the fill goes away, which is the cost that matters. The vertices are
     still submitted, and that is the price of not having a CPU repack
     every time the camera crosses a cell. */
  float eyeDist = distance(iPos, cameraPosition);
  float keep = 1.0 - smoothstep(fadeBand.x, fadeBand.y, eyeDist);
  vec3 p = vec3(position.x * iSize.x * keep, position.y * iSize.y * keep, 0.0);
  float c = cos(billboardRot), s = sin(billboardRot);
  p = vec3(p.x * c, p.y, -p.x * s) + iPos;
  /* VERTEX WIND. The quad's top is pushed downwind and let back, the
     root never moves, and the push goes as the square of the height up
     the plant, so it bends from the ground rather than sliding. Three
     parts: a slow lean that rolls across the wood as a WAVE (its phase
     is where the plant stands, so a gust visibly travels downwind), a
     faster flutter of each plant's own, and a gust that comes and goes
     on a period that does not divide into the other two. A plant that
     has burnt is a black stick and does not sway; four vertices a plant
     is all the budget there is (see the top of build()), so this is a
     shear and not a bend, and at forest distances that is the same
     thing. */
  float along = dot(iPos.xz, normalize(uWind.xy + vec2(1e-4)));
  float gust = 0.55 + 0.45 * sin(uTime * 0.21 + along * 0.0009);
  float wave = sin(uTime * 1.3 - along * 0.004 + iSeed * 0.8);
  float flutter = sin(uTime * 3.7 + iSeed * 17.0) * 0.35;
  float lean = uWind.z * gust * (0.6 + 0.4 * wave + flutter) * (1.0 - iBurn);
  float up = position.y * position.y;
  p.xz += uWind.xy * (lean * up * iSize.y * 0.045 * keep);
  vWorld = p;
  vec4 mv = viewMatrix * vec4(p, 1.0);
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
`;

const PLANT_FRAG = /* glsl */`
uniform sampler2D map;
uniform sampler2D burnMap;
uniform float light;
uniform float uTime;
uniform vec3  ramp[8];
${WORLD_UNIFORMS_GLSL}
varying vec2  vUv;
varying float vBurn;
varying float vSeed;
varying float vDepth;
varying vec3  vWorld;
varying vec4  vSecLight;
#define SECTOR_FOG
varying vec4  vFog;
${WORLD_SHADE_GLSL}

void main() {
  vec4 t = texture2D(map, vUv);
  if (t.a < 0.5) discard;
  /* coloured by the sector it stands in (white where there is none) */
  vec3 col = t.rgb * vSecLight.rgb;
  float ember = 0.0;
  float gone = 0.0;
  vec3 hue = vec3(1.0);

  /* THE BURN, skipped entirely on a plant the fire has not reached —
     which is every plant in the wood until something turns it on. */
  if (vBurn > 0.0) {
    /* R coals, G char, B order (when this texel catches), A foliage */
    vec4 bm = texture2D(burnMap, vUv);

    /* Sweep the order field. The remap pushes both ends out by soft,
       so burn = 1 drives even the last texel past the top of its band
       and burn = 0 leaves the first below the bottom of its own. The
       seed staggers neighbours so two plants in one cell are never in
       step. */
    float soft = 0.22;
    float a = vBurn * (1.0 + 2.0 * soft) - soft + (vSeed - 0.5) * 0.10;
    float tt = smoothstep(bm.b - soft, bm.b + soft, a);

    /* The art's own luminance carried through the char, so a burnt tree
       is still a tree with a light side rather than a flat black shape. */
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));

    /* Dry and brown, then black, then a little ash on what is left. The
       three overlap: a crown is scorching while the lower branches char. */
    col = mix(col, col * 0.55 + vec3(0.30, 0.16, 0.06), smoothstep(0.0, 0.55, tt) * 0.85);
    /* Char that is charcoal, not a hole in the night: it keeps a fair
       share of the art's own light and the ash on it goes properly pale,
       so a burnt stand reads as burnt trees rather than as nothing. */
    col = mix(col, vec3(0.15, 0.13, 0.11) * (0.7 + 2.2 * lum), smoothstep(0.30, 0.95, tt) * bm.g);
    col = mix(col, vec3(0.46, 0.44, 0.40) * (0.60 + 2.0 * lum), smoothstep(0.85, 1.0, tt) * (1.0 - bm.g) * 0.75);

    /* BURNT DOWN. From nine tenths of the burn a tree goes: what is
       left of it comes down from the crown and in from the sides until
       the foot of the trunk is all that stands — a stump, ash grey, for
       good, because the cell's progress never comes back down. A bush
       has no trunk worth the name and goes to nothing. Discarding the
       texels is what does it, so the quad, the instance buffer and the
       cell's own state are left exactly as they were. */
    gone = smoothstep(0.88, 1.0, vBurn);
    if (gone > 0.0) {
      float top = mix(1.0, 0.12, gone);
      float halfW = mix(0.5, 0.05, gone);
      if (vUv.y > top || abs(vUv.x - 0.5) > halfW) discard;
      col = mix(col, vec3(0.36, 0.34, 0.32) * (0.5 + 1.8 * lum), gone * 0.9);
    }

    /* Two sines beaten against each other so neighbouring coals on one
       plant are out of step; the seed keeps two plants apart. */
    float flick = 0.80 + 0.30
      * sin(uTime * 9.0 + vSeed * 31.4 + vUv.y * 17.0)
      * sin(uTime * 3.7 + vSeed * 12.0 + vUv.x * 23.0);
    /* The flame is a narrow band travelling with the front; the coals are
       what it leaves behind, and they cool. */
    float q = (tt - 0.5) / 0.16;
    float flame = exp(-q * q);
    float coal = bm.r * smoothstep(0.30, 0.62, tt) * (1.0 - 0.8 * smoothstep(0.70, 1.0, tt));
    ember = (flame * (0.22 + 0.78 * bm.r) + coal) * flick * 1.5 * (1.0 - 0.85 * gone);

    /* The palette cycle: where a texel sits in the eight ember colours is
       its heat plus a wave that climbs the plant, quantised to whole
       steps so it flips between real colours instead of sliding. */
    float heat = clamp(flame * 0.62 + coal * 0.45, 0.0, 1.0);
    float ph = uTime * 0.9 - bm.b * 2.0 + vSeed * 3.7 + bm.r * 1.3;
    float wave = abs(fract(ph) * 2.0 - 1.0) - 0.5;
    float swing = 0.18 * (0.35 + 0.65 * flame);
    float idx = clamp(heat + wave * 2.0 * swing, 0.0, 1.0);
    hue = ramp[int(floor(idx * 7.0 + 0.5))];
  }

  /* and lit by it: the sector's light, or the wood's own */
  float l = worldBand(vSecLight.a >= 0.0 ? vSecLight.a : light, vDepth, 1.0, 0.0);
  vec3 c = worldShade(col, l, vDepth, vWorld, 0.0);
  /* embers go on after the smoke, so a burning ridge glows through it */
  c += hue * ember;
  gl_FragColor = vec4(c, 1.0);
}
`;

const GROUND_VERT = /* glsl */`
varying vec3  vWorld;
varying float vDepth;
void main() {
  vWorld = position;
  vec4 mv = viewMatrix * vec4(position, 1.0);
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
`;

const GROUND_FRAG = /* glsl */`
uniform sampler2D map;
uniform sampler2D mapBurnt;
uniform sampler2D mask;
uniform vec4  maskRect;       // origin x, origin y, 1/width, 1/height (map space)
uniform float light;
uniform float uTime;
uniform vec3  ramp[8];
${WORLD_UNIFORMS_GLSL}
varying vec3  vWorld;
varying float vDepth;
${WORLD_SHADE_GLSL}

void main() {
  vec2 mp = vec2(vWorld.x, -vWorld.z);            // back to map space
  vec2 uv = mp / 128.0;                            // one texel to a unit
  vec3 g = texture2D(map, uv).rgb;
  vec3 b = texture2D(mapBurnt, uv * 1.37).rgb;
  float burn = texture2D(mask, (mp - maskRect.xy) * maskRect.zw).r;

  /* The char boundary is ragged by the floor's own texture, so the edge
     of a burn follows the litter rather than the grid. */
  float lum = dot(g, vec3(0.333));
  float k = smoothstep(0.06, 0.55, burn + (lum - 0.5) * 0.3);
  /* the char tile is painted for a crater at noon; lifted, and never
     the whole way, so burnt ground is dark ground and not black */
  vec3 col = mix(g, min(vec3(1.0), b * 1.9 + 0.06), k * 0.85);

  float l = worldBand(light, vDepth, 1.0, 0.0);
  vec3 c = worldShade(col, l, vDepth, vWorld, 0.0);

  /* Fresh char glows: a band in the middle of the burn, gone when cold. */
  float q = (burn - 0.5) / 0.26;
  float glow = exp(-q * q) * (0.75 + 0.25 * sin(uTime * 7.0 + mp.x * 0.09 + mp.y * 0.07));
  glow *= step(0.02, burn) * (1.0 - smoothstep(0.88, 1.0, burn));
  glow *= 0.35 + 0.65 * smoothstep(0.25, 0.7, lum);   // through the litter, not over it
  c += ramp[int(floor(clamp(glow, 0.0, 1.0) * 6.0 + 0.5))] * glow * 0.85;
  gl_FragColor = vec4(c, 1.0);
}
`;
