/* =====================================================================
   MEWD — the sector grid
   =====================================================================

   At the user's request: sprites, trees and 3D objects are lit, coloured
   and fogged by the SECTOR THEY STAND IN, as a thing in Doom is. The
   walls and floors carry their sector's light, colour and fog in their
   vertices (js/mapgeo.js); nothing else does, and there is a lot of
   nothing else — a standee, a tree, a model, the editor's billboards —
   each drawn by its own code.

   So the sectors are handed to all of them at once, as two small
   pictures over the map's floor plan: a cell per `cell` units, each
   holding what the sector at its middle says. A vertex shader reads the
   cell under its object's foot (SECTOR_GRID_GLSL in js/material.js) and
   that is the whole of the plumbing: anything shaded through the world
   shader picks it up without being told.

     A  rgb  the thing colour — Doom 64's, times the sector's light colour
        a    the sector's light
     B  rgb  the sector's fog colour
        a    its density / 100, or 0 for the map's default fog
     C  rg   how high its fog reaches, as 16 bits (+32768): the ceiling
             indoors, FOG_TOP over the floor under the sky. Above it the
             fog thins away (FOG_FADE in js/material.js), so a fogged
             sector under the sky is a fog bank that fades into the sky
             rather than a column of fog up to the stars.
        b    255 under a roof: the fog STOPS at the ceiling, and the air
             over the building has none of it

   Only for a map from the editor (a level with mapLight): the game's own
   levels light their things themselves, and it is switched off for them.
   ===================================================================== */

import * as THREE from 'three';
import { world } from './material.js';

/** The most cells a side, and the finest a cell may be. A 10240-unit map
 *  is 40 units a cell: finer than a person is wide. */
export const GRID_MAX_CELLS = 256;
export const GRID_MIN_CELL = 16;
/** How high a fog under the open sky stands over its floor before it
 *  starts to thin away. Taller than a fir, so a forest is in it. */
export const FOG_TOP = 320;
/** A height, as the two bytes the shader reads it from (fogTopAt). */
export const packHeight = h => { const v = Math.max(0, Math.min(65535, Math.round(h) + 32768)); return [v >> 8, v & 255]; };

/**
 * Sample a level's sectors into the grid. Returns { cell, cols, rows,
 * x0, y0, a, b } with a and b as Uint8Arrays, or null for a level with
 * no sectors. Pure: no textures, so it can be tested.
 */
export function sampleSectorGrid(level) {
  const S = level?.sectors || [];
  if (!S.length || !level.sectorAt) return null;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const s of S) {
    const b = s.bbox;
    if (!b) continue;
    x0 = Math.min(x0, b[0]); y0 = Math.min(y0, b[1]); x1 = Math.max(x1, b[2]); y1 = Math.max(y1, b[3]);
  }
  if (!(x1 > x0 && y1 > y0)) return null;
  const cell = Math.max(GRID_MIN_CELL, Math.ceil(Math.max(x1 - x0, y1 - y0) / GRID_MAX_CELLS));
  const cols = Math.max(1, Math.ceil((x1 - x0) / cell)), rows = Math.max(1, Math.ceil((y1 - y0) / cell));
  const a = new Uint8Array(cols * rows * 4), b = new Uint8Array(cols * rows * 4), c = new Uint8Array(cols * rows * 4);
  const u8 = v => Math.max(0, Math.min(255, Math.round(v * 255)));
  for (let j = 0; j < rows; j++) {
    for (let i = 0; i < cols; i++) {
      const k = (j * cols + i) * 4;
      const s = level.sectorAt(x0 + (i + 0.5) * cell, y0 + (j + 0.5) * cell);
      /* off the map: white, full light, no fog of its own */
      const t = s?.tint?.thing || [1, 1, 1];
      a[k] = u8(t[0]); a[k + 1] = u8(t[1]); a[k + 2] = u8(t[2]);
      a[k + 3] = u8(s ? Math.min(1, s.light ?? 1) : 1);
      const f = s?.fog;
      if (f && f[3] > 0) { b[k] = u8(f[0]); b[k + 1] = u8(f[1]); b[k + 2] = u8(f[2]); b[k + 3] = Math.max(1, u8(f[3] / 100)); }
      /* how high its fog reaches; off the map, as high as there is */
      const top = !s ? 32767 : s.outdoor === false ? (s.ceil ?? 32767) : (s.floor ?? 0) + FOG_TOP;
      [c[k], c[k + 1]] = packHeight(top);
      c[k + 2] = s && s.outdoor === false ? 255 : 0;
    }
  }
  return { cell, cols, rows, x0, y0, a, b, c };
}

/** Does any cell have a fog of its own (not the map's default)? */
export function hasOwnFog(g) {
  for (let k = 3; k < g.b.length; k += 4) if (g.b[k] > 0) return true;
  return false;
}

let texA = null, texB = null, texC = null;
const dataTex = (arr, w, h) => {
  const t = new THREE.DataTexture(arr, w, h, THREE.RGBAFormat, THREE.UnsignedByteType);
  t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  t.needsUpdate = true;
  return t;
};

/**
 * Put a level's sectors on the world (world.sectorA and friends), or
 * switch the grid off for a level that does not want it (a game level,
 * or null).
 */
export function applySectorGrid(level) {
  const g = level?.mapLight ? sampleSectorGrid(level) : null;
  if (!g) { world.sectorOn.value = 0; world.fogMarch.value = 0; return null; }
  texA?.dispose(); texB?.dispose(); texC?.dispose();
  texA = dataTex(g.a, g.cols, g.rows);
  texB = dataTex(g.b, g.cols, g.rows);
  texC = dataTex(g.c, g.cols, g.rows);
  world.sectorA.value = texA;
  world.sectorB.value = texB;
  world.sectorC.value = texC;
  const r = world.sectorRect.value;
  r.x = g.x0; r.y = g.y0; r.z = 1 / (g.cols * g.cell); r.w = 1 / (g.rows * g.cell);
  world.sectorOn.value = 1;
  /* a map with any fog, a sector's own or its default: the fog is
     followed along each line of sight, so it fades from sector to sector
     and into the sky (FOG_GLSL) */
  world.fogMarch.value = hasOwnFog(g) || level.mapLight?.fog?.[3] > 0 ? 1 : 0;
  return g;
}

/* ---------------------------------------------------------------------
   A THING CROSSING INTO ANOTHER SECTOR
   ---------------------------------------------------------------------
   At the user's request, what moves does not SNAP from one sector's
   light, colour and fog to the next: it eases there, fast — a time
   constant of LOOK_TAU seconds, so it is most of the way in a tenth of
   a second and all of it in a quarter. Something that has just appeared
   takes its sector's look at once. Static things (trees, boxes) never
   cross anything and read the grid (or their own vertices) instead. */
export const LOOK_TAU = 0.06;

/** What a sector says a thing in it looks like: its light, its thing
 *  colour, and its fog — the map's default fog where it has none. */
export function sectorLook(s) {
  const t = s?.tint?.thing || [1, 1, 1];
  const d = world.fogDefault.value;
  const f = s?.fog && s.fog[3] > 0 ? s.fog : [d.x, d.y, d.z, d.w];
  return { light: s ? (s.light ?? 1) : 0.7, tint: [t[0], t[1], t[2]], fog: [f[0], f[1], f[2], f[3]] };
}

/**
 * Ease `obj`'s look toward its sector's, over `dt` seconds, and return
 * it ({ light, tint, fog }, kept on obj._look). A fog coming in from
 * none takes the new colour at once and only its density eases, so a
 * thing walking into a blue fog is not first greyed by nothing.
 */
export function tweenLook(obj, sector, dt) {
  const to = sectorLook(sector);
  const L = obj._look;
  if (!L || !(dt > 0)) { obj._look = to; return to; }
  const k = 1 - Math.exp(-Math.min(dt, 1) / LOOK_TAU);
  L.light += (to.light - L.light) * k;
  for (let i = 0; i < 3; i++) L.tint[i] += (to.tint[i] - L.tint[i]) * k;
  if (L.fog[3] <= 0) { L.fog[0] = to.fog[0]; L.fog[1] = to.fog[1]; L.fog[2] = to.fog[2]; }
  else if (to.fog[3] > 0) for (let i = 0; i < 3; i++) L.fog[i] += (to.fog[i] - L.fog[i]) * k;
  L.fog[3] += (to.fog[3] - L.fog[3]) * k;
  return L;
}
