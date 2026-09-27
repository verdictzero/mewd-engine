/* =====================================================================
   GROCERY STORE SIMULATOR — THE EDITOR'S MAP, AS A DOCUMENT
   =====================================================================

   What the editor edits, and what it hands the game. At the user's
   request the game has an editor now — SLADE and Ultimate Doom Builder
   are the workflow it is modelled on — and this file is the part of it
   that has no screen: the map as plain JSON, the undo stack over it,
   and the COMPILER that turns it into a Level the engine runs exactly as
   it runs the grid and the superstore.

   THE MODEL IS DOOM'S, WHERE DOOM'S IS RIGHT. A map is VERTICES, and
   SECTORS that are rings of vertex indices, and THINGS standing on
   them. A vertex two sectors share is ONE vertex: drag it and both
   sectors move, which is the whole of what makes vertex editing in a
   Doom editor feel like editing a building rather than a pile of
   polygons. Lines are not stored — a line is two consecutive vertices
   of a sector, and two sectors that run the same pair in opposite
   directions share it, which is what MapBuilder calls a doorway. What
   a line CAN carry (blocking, its own textures) is kept in `lines`,
   keyed by the pair.

   AND IT IS NOT DOOM'S WHERE THIS ENGINE IS MORE. Doom had one floor
   and one ceiling a sector, flat, and no objects that were not
   sprites. This engine has:

     STOREYS   a sector may have rooms stacked over it — a column, in
               js/level.js — so a building can have an upstairs
     SLOPES    a floor or a ceiling may TILT, as a plane through the
               middle of the sector
               (both of these are SWITCHED OFF for now, at the user's
               request — see FEATURES below; the compiler still knows
               how, and ignores them while the switch is off)
     PROPS     free boxes anywhere in 3D, with a bottom and a top that
               have nothing to do with any floor — the engine's
               `level.props`, the same thing the superstore's shelving
               details were drawn with

   so the document has those too, and the 3D view edits them.

   THE COMPILER does the two things a Doom editor does for you that
   this engine's MapBuilder does not:

     T-JUNCTIONS   MapBuilder welds two sectors into a doorway only
                   where they share BOTH ends of an edge. A room drawn
                   against half of a long wall shares a piece of that
                   wall and neither end of it, and would silently not be
                   joined. So every edge is split at every vertex that
                   lies on it, before MapBuilder sees it — which is what
                   js/maps/rectmap.js does for rectangles, done for any
                   shape.

     HOLES         a sector drawn entirely inside another — a pillar, a
                   pit, a raised platform — is, in Doom, simply a
                   sector with lines round it. Here a sector is one
                   ring of points and cannot have an island in it. So
                   the outer ring is BRIDGED to each inner one by a slit
                   of zero width: out along the bridge, round the
                   inside the other way, and back. The slit's two sides
                   weld to each other as a line with the same sector on
                   both sides — no wall, nothing to draw, nothing in the
                   way — and the point-in-polygon test the engine uses
                   is even-odd, so the hole is outside the outer sector
                   exactly as it should be.

   Nothing here touches the DOM, so tools/smoke-test.mjs compiles maps
   headless and holds them against the engine.
   ===================================================================== */

import { MapBuilder, planeSlope } from '../level.js';
import { growScatter, plantKind, isCanopyKind } from './scatter.js';

/* WHAT THE EDITOR OFFERS, and what it is holding back. Slopes and
   storeys were in the first cut of the editor and, at the user's
   request, are out of it for now: the inspector does not show them and
   the compiler ignores them, so a map that has some from before is
   drawn flat and single-storey — exactly as it can be edited. Turning
   either back on is this line. */
export const FEATURES = { slopes: false, storeys: false };

export const DOC_FORMAT = 'gss-map';
export const DOC_VERSION = 1;

/* The things a map may place, and what each one is for the editor's
   palette. The keys are THING_TO_ACTOR in js/game.js, plus START. */
export const THING_TYPES = {
  START:      { name: 'Player start', color: '#4af', radius: 16, one: true },
  SHOPPER:    { name: 'Shopper', color: '#fc4', radius: 18 },
  TOWNIE:     { name: 'Townsperson', color: '#fa6', radius: 18 },
  TROLLEY:    { name: 'Trolley', color: '#aaa', radius: 16 },
  BOLLARD:    { name: 'Bollard', color: '#ddd', radius: 10 },
  FUELCAN:    { name: 'Fuel can', color: '#f44', radius: 10 },
  CRATE:      { name: 'Crate', color: '#c93', radius: 20 },
  LAMP:       { name: 'Ceiling lamp', color: '#ffe', radius: 12 },
  STREETLAMP: { name: 'Street lamp', color: '#ff8', radius: 10 },
  GRAVESTONE: { name: 'Gravestone', color: '#999', radius: 14 },
  /* A SPRITE PLANT — a fir, a bush, a fern, a street tree: one of the
     pictures js/forest.js draws, placed by hand. `kind` says which. The
     game gets these as level.plants, not as actors. */
  PLANT:      { name: 'Plant', color: '#5c5', radius: 14 },
};

/* What a new sector is, until somebody says otherwise. */
/* AN OPEN WORLD BY DEFAULT, at the user's request: a new sector is
   under the sky, with no ceiling drawn — SKY as a ceiling is a hole the
   sky shows through, see addFlats in js/mapgeo.js — and its height is
   only how tall the walls round it stand. A room with a roof is one you
   turn the sky off for. */
/** THE DEFAULTS a new map starts from, at the user's request: checkered
 *  grass underfoot (LAWN2, from the texture pack) and a day sky with
 *  scattered cloud (BSKY2, the pack's too) — see js/texpack.js. */
export const DEFAULT_FLOOR = 'LAWN2';
export const DEFAULT_SKYBOX = 'BSKY2';
export const SECTOR_DEFAULTS = {
  floor: 0, ceil: 1024,
  floorTex: DEFAULT_FLOOR, ceilTex: 'SKY', wallTex: 'GRIDWALL', upperTex: null, lowerTex: null,
  light: 0.72, outdoor: true, sky: 0, name: '',
};

/* ---------------------------------------------------------------------
   GEOMETRY, all of it plain and all of it in map units
   --------------------------------------------------------------------- */
const EPS = 0.5;                 // what counts as ON a line, in units

export function signedArea(pts) {
  let a = 0;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) a += pts[j][0] * pts[i][1] - pts[i][0] * pts[j][1];
  return a / 2;
}

/** Even-odd, which is what the engine's own pointInPoly is. */
export function pointInPoly(pts, x, y) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** How far (x, y) is from the segment a-b, and how far along it. */
export function segDist(ax, ay, bx, by, x, y) {
  const dx = bx - ax, dy = by - ay, L2 = dx * dx + dy * dy;
  const t = L2 ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2)) : 0;
  const px = ax + dx * t, py = ay + dy * t;
  return { d: Math.hypot(x - px, y - py), t };
}

function onBoundary(pts, x, y) {
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    if (segDist(pts[j][0], pts[j][1], pts[i][0], pts[i][1], x, y).d < EPS) return true;
  }
  return false;
}

/** Proper crossing of a-b and c-d, not counting shared ends. */
export function segCross(ax, ay, bx, by, cx, cy, dx, dy) {
  const d1 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  const d2 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
  const d3 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
  const d4 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/** Does this ring cross itself anywhere? A sector that does is a map
 *  error the engine would draw as something nobody meant. */
export function selfCrosses(pts) {
  const n = pts.length;
  for (let i = 0; i < n; i++) {
    const a = pts[i], b = pts[(i + 1) % n];
    for (let j = i + 2; j < n; j++) {
      if (i === 0 && j === n - 1) continue;             // neighbours round the end
      const c = pts[j], d = pts[(j + 1) % n];
      if (segCross(a[0], a[1], b[0], b[1], c[0], c[1], d[0], d[1])) return true;
    }
  }
  return false;
}

/** Is ring `inner` strictly inside ring `outer` — every point of it
 *  inside and not one of them on the edge? That is a HOLE. A ring that
 *  touches the outer's edge is not; it has to be drawn round. */
export function strictlyInside(inner, outer) {
  for (const [x, y] of inner) {
    if (onBoundary(outer, x, y)) return false;
    if (!pointInPoly(outer, x, y)) return false;
  }
  /* and no edge of it leaves and comes back */
  for (let i = 0; i < inner.length; i++) {
    const a = inner[i], b = inner[(i + 1) % inner.length];
    for (let j = 0; j < outer.length; j++) {
      const c = outer[j], d = outer[(j + 1) % outer.length];
      if (segCross(a[0], a[1], b[0], b[1], c[0], c[1], d[0], d[1])) return false;
    }
  }
  return true;
}

/**
 * Is `inner` a hole in `outer` that TOUCHES it — every corner inside or
 * on its edge, no edge of it running along the edge, nothing crossing?
 * A room drawn in a field with one corner on the field's wall is that:
 * it can be neither cut out of the field (it shares no wall) nor a
 * plain hole (it is not clear of the edge), so it is a hole pinched to
 * the outline at the corner it touches — see bridge.
 */
export function insideTouching(inner, outer) {
  let touches = false;
  for (const [x, y] of inner) {
    if (onBoundary(outer, x, y)) { touches = true; continue; }
    if (!pointInPoly(outer, x, y)) return false;
  }
  if (!touches) return false;
  for (let i = 0; i < inner.length; i++) {
    const a = inner[i], b = inner[(i + 1) % inner.length];
    const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
    if (onBoundary(outer, mx, my) || !pointInPoly(outer, mx, my)) return false;
    for (let j = 0; j < outer.length; j++) {
      const c = outer[j], d = outer[(j + 1) % outer.length];
      if (segCross(a[0], a[1], b[0], b[1], c[0], c[1], d[0], d[1])) return false;
    }
  }
  return true;
}
/** A hole in `outer`: clear of its edge, or touching it at corners. */
export const holeIn = (inner, outer) => strictlyInside(inner, outer) || insideTouching(inner, outer);

export function centroid(pts) {
  let x = 0, y = 0;
  for (const p of pts) { x += p[0]; y += p[1]; }
  return [x / pts.length, y / pts.length];
}

export function bboxOf(pts) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const [x, y] of pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  return [x0, y0, x1, y1];
}

/* THE FIVE COLOURS OF A DOOM 64 SECTOR: the floor, the ceiling, the
   things standing in it, and its walls from top to bottom */
export const COLOR_PARTS = ['floor', 'ceil', 'thing', 'top', 'bottom'];
/** '#rrggbb' as three numbers 0..1, or null. */
export function hexRGB(h) {
  const m = /^#?([0-9a-f]{6})$/i.exec(h || '');
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

/**
 * THE HOLES A SECTOR HAS TO BE BRIDGED ROUND. Rooms drawn side by side
 * in the open are each a hole in the ground — but bridged into the
 * ground one at a time, the ground's ring ran along the wall the two
 * rooms share, twice, and MapBuilder welded that into ground on both
 * sides: no wall between the rooms at all. So rooms that share a wall
 * are one hole: their outlines UNIONED, by laying every edge of every
 * one of them the same way round and cancelling each edge that is
 * walked both ways (a shared wall), then following what is left.
 */
function holeOutlines(kids, ringIdx, V, problems, parent) {
  if (!kids.length) return [];
  const ccw = r => (signedArea(r.map(i => V[i])) >= 0 ? r : [...r].reverse());
  const edgesOf = j => { const r = ringIdx[j]; return r.map((a, k) => lineKey(a, r[(k + 1) % r.length])); };
  /* which of them share a wall: union-find over the edges */
  const up = kids.map((_, k) => k);
  const find = k => (up[k] === k ? k : (up[k] = find(up[k])));
  const owner = new Map();
  kids.forEach((j, k) => {
    for (const e of edgesOf(j)) {
      if (owner.has(e)) up[find(k)] = find(owner.get(e)); else owner.set(e, k);
    }
  });
  const groups = new Map();
  kids.forEach((j, k) => { const g = find(k); (groups.get(g) || groups.set(g, []).get(g)).push(j); });
  const out = [];
  for (const g of groups.values()) {
    if (g.length === 1) { out.push(ringIdx[g[0]].map(i => V[i])); continue; }
    const dir = new Set(), edges = [];
    for (const j of g) {
      const r = ccw(ringIdx[j]);
      r.forEach((a, k) => { const b = r[(k + 1) % r.length]; if (a !== b) { edges.push([a, b]); dir.add(`${a}>${b}`); } });
    }
    const left = edges.filter(([a, b]) => !dir.has(`${b}>${a}`));
    const next = new Map();
    for (const [a, b] of left) (next.get(a) || next.set(a, []).get(a)).push(b);
    const loops = [];
    const used = new Set();
    for (const [a0, b0] of left) {
      if (used.has(`${a0}>${b0}`)) continue;
      const loop = [a0];
      let a = a0, b = b0;
      used.add(`${a}>${b}`);
      for (let guard = 0; b !== a0 && guard < left.length + 2; guard++) {
        loop.push(b);
        const nb = (next.get(b) || []).find(c => !used.has(`${b}>${c}`));
        if (nb === undefined) break;
        used.add(`${b}>${nb}`);
        a = b; b = nb;
      }
      if (loop.length >= 3) loops.push(loop.map(i => V[i]));
    }
    if (!loops.length) { for (const j of g) out.push(ringIdx[j].map(i => V[i])); continue; }
    loops.sort((x, y) => Math.abs(signedArea(y)) - Math.abs(signedArea(x)));
    out.push(loops[0]);
    if (loops.length > 1) {
      problems.push({ kind: 'sector', id: parent.id,
        msg: `rooms inside sector ${parent.id} close off a courtyard of it — draw the courtyard as its own sector` });
    }
  }
  return out;
}

/* ---------------------------------------------------------------------
   THE DOCUMENT
   --------------------------------------------------------------------- */

/** A blank map: one room, a start in it, the grid's floor and walls. */
/** A blank map: an OPEN WORLD — one square of ground `size` across under
 *  an open sky with no ceiling, and a start in it. */
/* A NEW MAP'S GROUND: full bright, and walled round at a height you can
   see over the top of from a step up — not the 1024 of sky it was, which
   stood round the field like the inside of a gasometer. What is drawn in
   it takes these too (insertSector copies the sector it is drawn in). */
export const GROUND_DEFAULTS = { ceil: 256, light: 1 };
/* and a little light everywhere, so nothing on a new map is black */
export const NEW_MAP_AMBIENT = { color: '#ffffff', amount: 0.35 };

export function newDoc(name = 'UNTITLED', size = 4096) {
  const d = {
    format: DOC_FORMAT, version: DOC_VERSION, name,
    vertices: [[0, 0], [size, 0], [size, size], [0, size]],
    sectors: [{ id: 1, verts: [0, 1, 2, 3], ...SECTOR_DEFAULTS, ...GROUND_DEFAULTS, name: 'ground' }],
    lines: {},
    /* LINEDEFS OF THEIR OWN: lines drawn in Draw mode that close no
       sector, as pairs of vertex indices. Where they close a loop they
       become a sector (Editor.closeLoops); what is left stands as a wall
       (linedefWalls, below). Their textures are line overrides, keyed by
       lineKey like any other line's. */
    linedefs: [],
    things: [{ id: 1, type: 'START', x: size / 2, y: size / 4, angle: Math.PI / 2 }],
    /* THE MAP'S OWN TEXTURES, made in the texture editor — see
       js/editor/texcompose.js */
    textures: [],
    props: [],
    /* THE PROCEDURAL SPREADS: rules, not things — see js/editor/scatter.js */
    scatters: [],
    /* a NEW map has the pack's day sky; one saved without a skybox
       keeps the painted sky it was made under (defaultWorld has none) */
    world: { ...defaultWorld(), skybox: DEFAULT_SKYBOX, ambient: { ...NEW_MAP_AMBIENT } },
    nextId: 2,
  };
  return d;
}

/**
 * A map's light and fog, as the renderer wants them (applyMapLight in
 * js/material.js), from its world settings — all of it doing nothing
 * at the defaults:
 *   lightColor  '#rrggbb'                     every light's colour
 *   ambient     { color, amount 0..1 }        light that is everywhere
 *   fog         { color, density 0..100, override }
 *                                             the default fog; override
 *                                             puts its colour on every
 *                                             sector's fog and the haze
 *   fogAmbient  0..1                          how much ambient is in fog
 */
export function mapLightOf(w = {}) {
  const amb = w.ambient || {};
  const fog = w.fog || {};
  const k = Math.max(0, Math.min(1, +amb.amount || 0));
  const a = hexRGB(amb.color || '#ffffff');
  const fc = hexRGB(fog.color || '#808080');
  return {
    lightColor: hexRGB(w.lightColor || '#ffffff'),
    ambient: [a[0] * k, a[1] * k, a[2] * k],
    fogAmbient: Math.max(0, Math.min(1, w.fogAmbient ?? 1)),
    fog: [fc[0], fc[1], fc[2], Math.max(0, Math.min(100, +fog.density || 0))],
    override: !!fog.override,
  };
}

/** What the world around a map is, when it does not say. The grid's
 *  own: nothing burns, nobody comes, the green sky. */
export function defaultWorld() {
  return {
    noBurn: true, noSquads: true, noCellFire: true,
    sky: { horizon: '#1d9a48', mid: '#06301a', zenith: '#000000', ground: '#05180c', midPow: 0.95 },
  };
}

/** THE GRID TEST AREA, as a document — the game's own current world,
 *  so opening the editor starts from what you have just been playing. */
export function gridDoc() {
  const F = 10240, mid = F / 2;
  const d = newDoc('THE GRID');
  d.vertices = [[0, 0], [F, 0], [F, F], [0, F]];
  d.sectors = [{ id: 1, verts: [0, 1, 2, 3], ...SECTOR_DEFAULTS, ...GROUND_DEFAULTS, name: 'field' }];
  d.things = [{ id: 1, type: 'START', x: mid, y: mid - 512, angle: Math.PI / 2 }];
  /* a crowd, placed the same way js/maps/grid.js places it, in fewer
     numbers so the editor opens on a map that is quick to draw */
  let s = 20250924 >>> 0, id = 2;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const span = F * 0.66, edge = (F - span) / 2;
  for (let k = 0; k < 60; k++) {
    d.things.push({ id: id++, type: 'SHOPPER', x: Math.round(edge + rnd() * span), y: Math.round(edge + rnd() * span),
                    angle: rnd() * Math.PI * 2, variant: (rnd() * 17) | 0 });
  }
  d.nextId = id;
  return d;
}

/** A fresh id, unique within the document. */
export function takeId(doc) { return doc.nextId++; }

/** The key a line is kept under: its two vertices, smaller first. */
export const lineKey = (a, b) => (a < b ? `${a},${b}` : `${b},${a}`);

/** A sector's ring, as points. */
export function ringOf(doc, s) { return s.verts.map(i => doc.vertices[i]); }

/** Every line in the document: each distinct vertex pair round every
 *  sector, with the one or two sectors on it. */
export function linesOf(doc, parents = holeParents(doc)) {
  const map = new Map();
  doc.sectors.forEach((s, si) => {
    for (let i = 0; i < s.verts.length; i++) {
      const a = s.verts[i], b = s.verts[(i + 1) % s.verts.length];
      const k = lineKey(a, b);
      let l = map.get(k);
      if (!l) map.set(k, l = { key: k, a: Math.min(a, b), b: Math.max(a, b), sectors: [] });
      if (!l.sectors.includes(si)) l.sectors.push(si);
    }
  });
  /* A HOLE'S EDGE IS TWO-SIDED: the room it is cut out of is on the
     other side of it, although that room's own ring never runs along it */
  for (const l of map.values()) {
    if (l.sectors.length === 1 && parents[l.sectors[0]] >= 0) l.sectors.push(parents[l.sectors[0]]);
  }
  return [...map.values()];
}

/** For each sector, the index of the sector it is a hole in (the
 *  smallest one it is strictly inside), or -1. */
export function holeParents(doc) {
  const plain = doc.sectors.map(s => ringOf(doc, s));
  return plain.map((r, i) => {
    if (r.length < 3) return -1;
    let best = -1, ba = Infinity;
    plain.forEach((o, j) => {
      if (i === j || o.length < 3) return;
      const a = Math.abs(signedArea(o));
      if (a < ba && holeIn(r, o)) { ba = a; best = j; }
    });
    return best;
  });
}

/* ---------------------------------------------------------------------
   TIDYING: what an edit leaves behind
   --------------------------------------------------------------------- */

/** Weld vertices that have been dragged on top of each other, drop
 *  vertices nobody uses, drop degenerate sectors, and renumber. Returns
 *  the document it was given. Called after every edit that moves or
 *  deletes, which is what makes dragging one vertex onto another JOIN
 *  them, the way it does in a Doom editor. */
/** How near two vertices are the SAME vertex, in units. Under half a
 *  unit: vertices sit on whole units (or exactly on a line, see
 *  Editor.snapAt), so this welds a corner dragged onto another and
 *  never two corners one unit apart, which at grid 1 is detail. */
export const WELD = 0.49;
export function compact(doc, weld = WELD) {
  const V = doc.vertices;
  /* weld: every vertex to the first one within `weld` of it */
  const to = V.map((_, i) => i);
  for (let i = 0; i < V.length; i++) {
    if (to[i] !== i) continue;
    for (let j = i + 1; j < V.length; j++) {
      if (to[j] !== j) continue;
      if (Math.abs(V[i][0] - V[j][0]) <= weld && Math.abs(V[i][1] - V[j][1]) <= weld) to[j] = i;
    }
  }
  for (const s of doc.sectors) {
    s.verts = s.verts.map(i => to[i]);
    /* two neighbours the same is a zero-length edge */
    s.verts = s.verts.filter((v, k, a) => v !== a[(k + 1) % a.length]);
  }
  /* a sector with no area is gone; a one-unit square is detail */
  doc.sectors = doc.sectors.filter(s => s.verts.length >= 3 &&
    Math.abs(signedArea(s.verts.map(i => V[i]))) > 0.25);
  /* keep only the vertices somebody uses, in order — a sector, or a
     linedef of its own */
  const used = new Set();
  for (const s of doc.sectors) for (const v of s.verts) used.add(v);
  const lds = (doc.linedefs || []).map(([a, b]) => [to[a], to[b]]).filter(([a, b]) => a !== b && a !== undefined && b !== undefined);
  for (const [a, b] of lds) { used.add(a); used.add(b); }
  const remap = new Map();
  const nv = [];
  V.forEach((p, i) => { if (used.has(i) && to[i] === i) { remap.set(i, nv.length); nv.push([p[0], p[1]]); } });
  for (const s of doc.sectors) s.verts = s.verts.map(i => remap.get(i));
  /* line overrides follow their vertices, and go with them */
  const lines = {};
  for (const [k, v] of Object.entries(doc.lines || {})) {
    const [a, b] = k.split(',').map(Number);
    const na = remap.get(to[a]), nb = remap.get(to[b]);
    if (na !== undefined && nb !== undefined && na !== nb) lines[lineKey(na, nb)] = v;
  }
  /* a linedef once: not twice, and not where a sector's edge already is */
  const edges = new Set();
  for (const s of doc.sectors) s.verts.forEach((v, k, r) => edges.add(lineKey(v, r[(k + 1) % r.length])));
  const kept = new Set();
  doc.linedefs = [];
  for (const [a, b] of lds) {
    const na = remap.get(a), nb = remap.get(b), k = lineKey(na, nb);
    if (na === undefined || nb === undefined || na === nb || edges.has(k) || kept.has(k)) continue;
    kept.add(k);
    doc.linedefs.push([na, nb]);
  }
  doc.vertices = nv;
  doc.lines = lines;
  return doc;
}

/* ---------------------------------------------------------------------
   PROBLEMS: what the compiler will refuse or quietly get wrong, said
   out loud before it does
   --------------------------------------------------------------------- */
export function problemsOf(doc) {
  const out = [];
  const rings = doc.sectors.map(s => ringOf(doc, s));
  rings.forEach((r, i) => {
    const s = doc.sectors[i];
    if (r.length < 3) out.push({ kind: 'sector', id: s.id, msg: `sector ${s.id} has fewer than three corners` });
    else if (selfCrosses(r)) out.push({ kind: 'sector', id: s.id, msg: `sector ${s.id} crosses itself` });
    /* a ceiling AT the floor is not a mistake — it is how this engine
       makes a solid pillar (see MapBuilder.column's shut storeys); one
       BELOW the floor is */
    if (s.ceil < s.floor) out.push({ kind: 'sector', id: s.id, msg: `sector ${s.id} is inside out: its ceiling is below its floor` });
  });
  /* two sectors that overlap without one being inside the other: a room
     you could stand in two of at once */
  for (let i = 0; i < rings.length; i++) {
    for (let j = i + 1; j < rings.length; j++) {
      const a = rings[i], b = rings[j];
      if (holeIn(a, b) || holeIn(b, a)) continue;
      let crosses = false;
      for (let p = 0; p < a.length && !crosses; p++) {
        const a0 = a[p], a1 = a[(p + 1) % a.length];
        for (let q = 0; q < b.length; q++) {
          const b0 = b[q], b1 = b[(q + 1) % b.length];
          if (segCross(a0[0], a0[1], a1[0], a1[1], b0[0], b0[1], b1[0], b1[1])) { crosses = true; break; }
        }
      }
      /* and overlaps that cross nothing: a corner or an edge midpoint of
         one strictly inside the other — rooms drawn over each other along
         a shared line, or a room that only touches its surroundings at
         a corner, which can be neither a hole in them nor cut out of them */
      if (!crosses) {
        const inOther = (p, q) => {
          for (let k = 0; k < p.length; k++) {
            const u = p[k], w = p[(k + 1) % p.length];
            for (const [x, y] of [u, [(u[0] + w[0]) / 2, (u[1] + w[1]) / 2]]) {
              if (pointInPoly(q, x, y) && !onBoundary(q, x, y)) return true;
            }
          }
          return false;
        };
        const aInB = inOther(a, b), bInA = inOther(b, a);
        if (aInB || bInA) {
          const [inner, outer] = aInB ? [doc.sectors[i], doc.sectors[j]] : [doc.sectors[j], doc.sectors[i]];
          const touching = aInB ? a.some(([x, y]) => onBoundary(b, x, y)) : b.some(([x, y]) => onBoundary(a, x, y));
          out.push({ kind: 'sector', id: inner.id, msg: touching && !(aInB && bInA)
            ? `sector ${inner.id} touches the edge of sector ${outer.id} without sharing a whole wall — draw it clear of the edge, or along the wall`
            : `sectors ${doc.sectors[i].id} and ${doc.sectors[j].id} overlap` });
          continue;
        }
      }
      if (crosses) out.push({ kind: 'sector', id: doc.sectors[i].id, msg: `sectors ${doc.sectors[i].id} and ${doc.sectors[j].id} overlap` });
    }
  }
  if (!doc.things.some(t => t.type === 'START')) out.push({ kind: 'map', msg: 'there is no player start' });
  for (const t of doc.things) {
    if (!rings.some(r => pointInPoly(r, t.x, t.y))) out.push({ kind: 'thing', id: t.id, msg: `${t.type} ${t.id} is outside every sector` });
  }
  return out;
}

/* ---------------------------------------------------------------------
   LINEDEFS AS WALLS
   --------------------------------------------------------------------- */

/** How thick a linedef of its own stands, and how tall outdoors (in a
 *  room it goes floor to ceiling). A line override's `wallH` sets it. */
export const LINEDEF_THICK = 8;
export const LINEDEF_H = 128;

/** The linedefs of a document as runs: the vertices of each chain of
 *  them, broken wherever three meet or one touches a sector. */
export function linedefChains(doc) {
  const L = doc.linedefs || [];
  if (!L.length) return [];
  const adj = new Map();
  const add = (a, b) => { if (!adj.has(a)) adj.set(a, []); adj.get(a).push(b); };
  for (const [a, b] of L) { add(a, b); add(b, a); }
  const onRing = new Set();
  for (const s of doc.sectors) for (const v of s.verts) onRing.add(v);
  const stop = v => (adj.get(v)?.length ?? 0) !== 2 || onRing.has(v);
  const used = new Set();
  const chains = [];
  const walk = (a, b) => {
    const out = [a, b];
    used.add(lineKey(a, b));
    let prev = a, cur = b;
    while (!stop(cur)) {
      const next = adj.get(cur).find(n => n !== prev && !used.has(lineKey(cur, n)));
      if (next === undefined) break;
      used.add(lineKey(cur, next));
      out.push(next);
      prev = cur; cur = next;
    }
    return out;
  };
  for (const v of adj.keys()) if (stop(v)) for (const n of adj.get(v)) if (!used.has(lineKey(v, n))) chains.push(walk(v, n));
  /* what is left is loops with nothing touching them */
  for (const [a, b] of L) if (!used.has(lineKey(a, b))) chains.push(walk(a, b));
  return chains;
}

/** The outline of a wall along the points `P`, `w` either side, its
 *  ends pulled in by `inA`/`inB` so it stops short of what it meets. */
export function wallOutline(P, w, inA = 0, inB = 0) {
  P = P.map(p => [...p]);
  const n = P.length;
  const pull = (i, j, by) => {
    const dx = P[j][0] - P[i][0], dy = P[j][1] - P[i][1], L = Math.hypot(dx, dy);
    if (L <= by + 1) return false;
    P[i] = [P[i][0] + dx / L * by, P[i][1] + dy / L * by];
    return true;
  };
  if (inA && !pull(0, 1, inA)) return null;
  if (inB && !pull(n - 1, n - 2, inB)) return null;
  const nrm = (a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy) || 1; return [-dy / L, dx / L]; };
  const left = [], right = [];
  for (let i = 0; i < n; i++) {
    const n1 = i > 0 ? nrm(P[i - 1], P[i]) : null, n2 = i < n - 1 ? nrm(P[i], P[i + 1]) : null;
    let m, k = w;
    if (n1 && n2) {
      m = [n1[0] + n2[0], n1[1] + n2[1]];
      const L = Math.hypot(m[0], m[1]);
      if (L < 1e-6) m = n1; else { m = [m[0] / L, m[1] / L]; k = Math.min(w / Math.max(0.2, m[0] * n1[0] + m[1] * n1[1]), w * 3); }
    } else m = n1 || n2;
    const r = v => +v.toFixed(2);
    left.push([r(P[i][0] + m[0] * k), r(P[i][1] + m[1] * k)]);
    right.push([r(P[i][0] - m[0] * k), r(P[i][1] - m[1] * k)]);
  }
  return [...left, ...right.reverse()];
}

/**
 * THE DOCUMENT WITH ITS LINEDEFS STOOD UP AS WALLS: each run of them a
 * thin sector (a hole in the one it stands in) raised LINEDEF_H, or to
 * the ceiling in a room, faced in the line's middle texture or the
 * room's walls. The document is not changed; a copy with the walls in
 * it is returned. Anything that would cross a wall is left out and
 * said in `problems`.
 */
export function linedefWalls(doc, problems = []) {
  const chains = linedefChains(doc);
  if (!chains.length) return doc;
  const V = doc.vertices;
  const rings = doc.sectors.map(s => ringOf(doc, s));
  const onRing = new Set();
  for (const s of doc.sectors) for (const v of s.verts) onRing.add(v);
  const deg = new Map();
  for (const [a, b] of doc.linedefs) for (const v of [a, b]) deg.set(v, (deg.get(v) || 0) + 1);
  const out = { ...doc, vertices: V.map(p => [...p]), sectors: [...doc.sectors] };
  const made = [];
  let id = Math.max(doc.nextId | 0, 1) + 100000;
  for (const ch of chains) {
    const P = ch.map(i => V[i]);
    const w = LINEDEF_THICK / 2;
    const cut = v => (onRing.has(v) || (deg.get(v) || 0) > 1 ? w + 1 : 0);
    const poly = wallOutline(P, w, cut(ch[0]), cut(ch[ch.length - 1]));
    const key = lineKey(ch[0], ch[1]);
    if (!poly) { problems.push({ kind: 'line', id: key, msg: `linedef ${key} is too short to stand as a wall` }); continue; }
    /* the sector it stands in: the smallest one round its middle */
    const mx = (P[0][0] + P[1][0]) / 2, my = (P[0][1] + P[1][1]) / 2;
    let host = -1, ha = Infinity;
    rings.forEach((r, i) => { if (r.length >= 3 && pointInPoly(r, mx, my)) { const a = Math.abs(signedArea(r)); if (a < ha) { ha = a; host = i; } } });
    const crosses = (A, B) => A.some((p, i) => { const q = A[(i + 1) % A.length]; return B.some((u, j) => { const v = B[(j + 1) % B.length]; return segCross(p[0], p[1], q[0], q[1], u[0], u[1], v[0], v[1]); }); });
    const bad = host < 0 || selfCrosses(poly) || !strictlyInside(poly, rings[host]) ||
      rings.some((r, i) => i !== host && r.length >= 3 && (crosses(poly, r) || poly.some(([x, y]) => pointInPoly(r, x, y) && !holeIn(rings[host], r)))) ||
      made.some(m => crosses(poly, m));
    if (bad) { problems.push({ kind: 'line', id: key, msg: `linedef ${key} crosses a wall or leaves the map, so it does not stand — split it where it meets them` }); continue; }
    made.push(poly);
    const H = doc.sectors[host];
    const o = (doc.lines || {})[key] || {};
    const tex = o.midTex || H.wallTex || 'GRIDWALL';
    const inside = H.ceilTex && H.ceilTex !== 'SKY';
    const f = H.floor ?? 0, c = H.ceil ?? 1024;
    const h = o.wallH ?? (inside ? c - f : LINEDEF_H);
    const verts = poly.map(p => { out.vertices.push(p); return out.vertices.length - 1; });
    out.sectors.push({ ...JSON.parse(JSON.stringify({ ...H, verts: undefined, storeys: undefined, floorSlope: undefined })),
      id: id++, verts, name: 'linedef wall', floor: Math.min(c, f + h), floorTex: tex, wallTex: tex, lowerTex: tex, upperTex: tex });
  }
  return out;
}

/* ---------------------------------------------------------------------
   THE COMPILER
   --------------------------------------------------------------------- */

/** Every vertex of the document that lies on the open segment a-b, in
 *  order along it — where a T-junction has to be split. */
function splitsOn(V, ai, bi) {
  const [ax, ay] = V[ai], [bx, by] = V[bi];
  const out = [];
  for (let k = 0; k < V.length; k++) {
    if (k === ai || k === bi) continue;
    const [x, y] = V[k];
    const { d, t } = segDist(ax, ay, bx, by, x, y);
    if (d < EPS && t > 1e-6 && t < 1 - 1e-6) out.push({ k, t });
  }
  return out.sort((p, q) => p.t - q.t).map(p => p.k);
}

/**
 * THE BRIDGE: one ring with holes in it, as a single ring the engine can
 * take. Each hole is joined to the ring by a slit of zero width from its
 * rightmost point to the nearest point of the ring it can see; the hole
 * goes round the OTHER way from the ring, so the area it takes out is
 * taken out. The earcut method, done once, in the open.
 */
export function bridge(outer, holes) {
  let ring = signedArea(outer) > 0 ? outer.slice() : outer.slice().reverse();     // counter-clockwise
  /* rightmost holes first, so a later bridge never has to cross an
     earlier one */
  const hs = holes.map(h => (signedArea(h) < 0 ? h.slice() : h.slice().reverse()))  // clockwise
    .sort((a, b) => Math.max(...b.map(p => p[0])) - Math.max(...a.map(p => p[0])));
  for (const h of hs) {
    /* A HOLE THAT TOUCHES THE OUTLINE at a corner is pinched in there —
       out of the corner, round the hole, back to the same corner — with
       no slit and no line of no length for the builder to trip on */
    let pinch = null;
    for (let i = 0; i < ring.length && !pinch; i++) {
      for (let k = 0; k < h.length; k++) {
        if (Math.abs(ring[i][0] - h[k][0]) < 0.5 && Math.abs(ring[i][1] - h[k][1]) < 0.5) { pinch = [i, k]; break; }
      }
    }
    if (pinch) {
      const [i, k] = pinch;
      const round = [];
      for (let q = 1; q < h.length; q++) round.push(h[(k + q) % h.length]);
      ring = [...ring.slice(0, i + 1), ...round, ...ring.slice(i)];
      continue;
    }
    let hi = 0;
    for (let i = 1; i < h.length; i++) if (h[i][0] > h[hi][0]) hi = i;
    const [hx, hy] = h[hi];
    /* the nearest ring point it can see: nothing of the ring or of any
       hole in the way */
    let best = -1, bd = Infinity;
    for (let i = 0; i < ring.length; i++) {
      const [rx, ry] = ring[i];
      const d = (rx - hx) ** 2 + (ry - hy) ** 2;
      if (d >= bd) continue;
      let blocked = false;
      const walls = [ring, ...hs];
      for (const w of walls) {
        for (let j = 0; j < w.length && !blocked; j++) {
          const a = w[j], b = w[(j + 1) % w.length];
          if (segCross(hx, hy, rx, ry, a[0], a[1], b[0], b[1])) blocked = true;
        }
        if (blocked) break;
      }
      if (!blocked) { bd = d; best = i; }
    }
    if (best < 0) best = 0;
    /* out along the slit, round the hole, and back */
    const round = [];
    for (let k = 0; k <= h.length; k++) round.push(h[(hi + k) % h.length]);
    ring = [...ring.slice(0, best + 1), ...round, ring[best], ...ring.slice(best + 1)];
  }
  return ring;
}

const texOr = (v, d) => (v === undefined || v === null || v === '' ? d : v);

/** A sector's properties, as MapBuilder wants them. */
function sectorProps(s, poly) {
  const [cx, cy] = centroid(poly);
  const p = {
    floor: s.floor ?? 0, ceil: s.ceil ?? 256,
    light: s.light ?? 0.72, ambient: s.light ?? 0.72,
    floorTex: texOr(s.floorTex, DEFAULT_FLOOR), ceilTex: texOr(s.ceilTex, 'SKY'),
    wallTex: texOr(s.wallTex, 'GRIDWALL'),
    upperTex: texOr(s.upperTex, texOr(s.wallTex, 'GRIDWALL')),
    lowerTex: texOr(s.lowerTex, texOr(s.wallTex, 'GRIDWALL')),
    outdoor: s.outdoor !== false, sky: s.sky ?? 0, fuel: 0, name: s.name || `sector ${s.id}`,
  };
  /* THE FLOOR OR CEILING MAY TILT: a plane through the middle of the
     sector at its own height, rising dzdx a unit east and dzdy a unit
     north. The simplest slope a person can type and the one a Doom
     editor's "slope" dialog asks for. */
  if (FEATURES.slopes && s.floorSlope && (s.floorSlope.dzdx || s.floorSlope.dzdy))
    p.slopeFloor = planeSlope(cx, cy, p.floor, s.floorSlope.dzdx || 0, s.floorSlope.dzdy || 0);
  if (FEATURES.slopes && s.ceilSlope && (s.ceilSlope.dzdx || s.ceilSlope.dzdy))
    p.slopeCeil = planeSlope(cx, cy, p.ceil, s.ceilSlope.dzdx || 0, s.ceilSlope.dzdy || 0);
  /* the floor's grid lines land on the map's own origin, so two sectors
     side by side run one grid across the seam */
  p.floorAnchor = [0, 0];
  return p;
}

/**
 * THE DOCUMENT, AS A LEVEL — the same Level js/maps/grid.js returns, so
 * the game runs it without knowing where it came from.
 *
 * @returns { level, problems, index } — `index[k]` is the Level sector
 *   index of document sector k (its ground storey), for the 3D view's
 *   picking to find its way back
 */
/* ---------------------------------------------------------------------
   TEXTURE ALIGNMENT across many lines at once — Doom Builder's
   auto-align, and its fit

   A face is one side of a line: the line as the sector `sec` sees it.
   Its texture runs left to right from `start` to `end` as you stand in
   that sector looking at it (js/mapgeo.js starts the front face's u at
   v1 and the back's at v2, and the front sector is on the right of
   v1→v2), so a run of faces reads as one length of brick when each
   face's x offset is the last one's plus the last one's length.
   --------------------------------------------------------------------- */

/** The faces of the given lines: { key, sec, start, end, len, h, tex }.
 *  Linedefs of their own have no faces here (their wall is a sector of
 *  its own when the map is built). */
export function facesOf(doc, keys, lines = linesOf(doc)) {
  const byKey = new Map(lines.map(l => [l.key, l]));
  const out = [];
  for (const key of keys) {
    const l = byKey.get(key);
    if (!l) continue;
    const A = doc.vertices[l.a], B = doc.vertices[l.b];
    const len = Math.hypot(B[0] - A[0], B[1] - A[1]);
    if (!(len > 0)) continue;
    const o = doc.lines?.[key] || {};
    const secs = l.sectors.map(i => doc.sectors[i]);
    for (const s of secs) {
      /* which side of a→b the sector is on: a step off the middle */
      const mx = (A[0] + B[0]) / 2, my = (A[1] + B[1]) / 2;
      const nx = -(B[1] - A[1]) / len, ny = (B[0] - A[0]) / len;       // left of a→b
      const ring = ringOf(doc, s);
      const left = pointInPoly(ring, mx + nx, my + ny), right = pointInPoly(ring, mx - nx, my - ny);
      /* a hole's parent holds both sides in its ring; the side the hole
         is not on is the parent's */
      let onRight = right && !left;
      if (left === right) {
        const other = secs.find(x => x !== s);
        onRight = other ? pointInPoly(ringOf(doc, other), mx + nx, my + ny) : right;
      }
      const [start, end] = onRight ? [l.a, l.b] : [l.b, l.a];
      const other = secs.find(x => x !== s);
      const sd = o.sides?.[s.id] || {};
      const inside = x => !!x?.ceilTex && x.ceilTex !== 'SKY';
      let h, tex;
      if (!other) {
        h = (s.ceil ?? 256) - (s.floor ?? 0);
        tex = sd.midTex || o.wallTex || s.wallTex;
      } else if (inside(s) !== inside(other) && !o.opening) {
        const inn = inside(s) ? s : other;
        h = (inn.ceil ?? 256) - (inn.floor ?? 0);
        tex = sd.midTex || o.midTex || inn.wallTex;
      } else {
        const lower = (other.floor ?? 0) - (s.floor ?? 0), upper = (s.ceil ?? 256) - (other.ceil ?? 256);
        if (sd.midTex || o.midTex) {
          h = Math.min(s.ceil ?? 256, other.ceil ?? 256) - Math.max(s.floor ?? 0, other.floor ?? 0);
          tex = sd.midTex || o.midTex;
        } else if (lower >= upper) { h = lower; tex = sd.lowerTex || o.lowerTex || s.lowerTex || s.wallTex; }
        else { h = upper; tex = sd.upperTex || o.upperTex || s.upperTex || s.wallTex; }
      }
      out.push({ key, sec: s.id, start, end, len, h: Math.max(0, h), tex: tex || 'GRIDWALL',
                 xoff: sd.xoff ?? o.xoff ?? 0, yoff: sd.yoff ?? o.yoff ?? 0,
                 xscale: sd.xscale ?? o.xscale ?? 1, yscale: sd.yscale ?? o.yscale ?? 1 });
    }
  }
  return out;
}

/** The faces in runs: each run end to end, each face's end the next
 *  one's start, in the order the lines were given; a closed room is one
 *  run that comes back to where it began. */
export function faceRuns(faces) {
  const from = new Map();
  for (const f of faces) { if (!from.has(f.start)) from.set(f.start, []); from.get(f.start).push(f); }
  const next = f => {
    /* never round the end of a line onto its own other side */
    const c = (from.get(f.end) || []).filter(g => !used.has(g) && g.key !== f.key);
    return c.find(g => g.sec === f.sec) || c[0] || null;
  };
  const used = new Set(), runs = [];
  const walk = f => { const run = []; while (f && !used.has(f)) { used.add(f); run.push(f); f = next(f); } runs.push(run); };
  /* the runs that have a beginning first, then the loops */
  for (const f of faces) if (!used.has(f) && !faces.some(g => g !== f && g.end === f.start && g.sec === f.sec)) walk(f);
  for (const f of faces) if (!used.has(f)) walk(f);
  return runs;
}

/**
 * Line the textures of these lines up, in place on `doc` (inside an
 * edit). What it does, by `how`:
 *   x      each run's x offsets carry on from face to face
 *   y      every face takes the first face's y offset
 *   match  every face takes the first face's scale and y offset
 *   fitX   each run is scaled across so its texture repeats a whole
 *          number of times along it, then aligned (x)
 *   fitY   each face is scaled up the wall so its texture fits a whole
 *          number of times between its floor and its top
 *   scale  every face gets `opts.xscale` / `opts.yscale` (either may be
 *          left out), then aligned (x)
 *   reset  offsets and scales back to nothing
 * `size(name)` is a texture's { w, h } in units, or null.
 * @returns how many faces it changed.
 */
export function alignTextures(doc, keys, how, size = () => null, opts = {}) {
  const faces = facesOf(doc, keys);
  if (!faces.length) return 0;
  const put = (f, fields) => {
    const o = doc.lines[f.key] = doc.lines[f.key] || {};
    o.sides = o.sides || {};
    const sd = o.sides[f.sec] = o.sides[f.sec] || {};
    for (const [k, v] of Object.entries(fields)) {
      const dflt = k.endsWith('scale') ? 1 : 0;
      if (v === undefined || Math.abs(v - dflt) < 1e-6) delete sd[k]; else sd[k] = v;
      f[k] = v ?? dflt;
    }
    if (!Object.keys(sd).length) delete o.sides[f.sec];
    if (!Object.keys(o.sides).length) delete o.sides;
    /* the line's own offsets would show through a side that has none */
    delete o.xoff; delete o.yoff; delete o.xscale; delete o.yscale;
    if (!Object.keys(o).length) delete doc.lines[f.key];
  };
  const W = f => (size(f.tex)?.w || 64) * (f.xscale || 1);
  const Hh = f => size(f.tex)?.h || 64;
  const round = v => Math.round(v * 1000) / 1000;
  const alignX = () => {
    for (const run of faceRuns(faces)) {
      let u = run[0].xoff;
      for (const f of run) {
        const w = W(f);
        put(f, { xoff: round(((u % w) + w) % w) });
        u = f.xoff + f.len;
      }
    }
  };
  const first = faces[0];
  if (how === 'x') alignX();
  else if (how === 'y') for (const f of faces) put(f, { yoff: first.yoff });
  else if (how === 'match') { for (const f of faces) put(f, { xscale: first.xscale, yscale: first.yscale, yoff: first.yoff }); alignX(); }
  else if (how === 'fitX') {
    for (const run of faceRuns(faces)) {
      const L = run.reduce((a, f) => a + f.len, 0);
      const tw = size(run[0].tex)?.w || 64;
      const n = Math.max(1, Math.round(L / tw));
      for (const f of run) put(f, { xscale: round(L / (n * tw)), xoff: 0 });
    }
    alignX();
  } else if (how === 'fitY') {
    for (const f of faces) {
      if (!(f.h > 0)) continue;
      const n = Math.max(1, Math.round(f.h / Hh(f)));
      put(f, { yscale: round(f.h / (n * Hh(f))), yoff: 0 });
    }
  } else if (how === 'scale') {
    for (const f of faces) put(f, { xscale: opts.xscale ?? f.xscale, yscale: opts.yscale ?? f.yscale });
    alignX();
  } else if (how === 'reset') for (const f of faces) put(f, { xoff: 0, yoff: 0, xscale: 1, yscale: 1 });
  return faces.length;
}

export function compileDoc(doc) {
  const wallProblems = [];
  doc = linedefWalls(doc, wallProblems);
  const problems = [...problemsOf(doc), ...wallProblems];
  const mb = new MapBuilder((doc.name || 'EDIT').slice(0, 16).toUpperCase());
  const V = doc.vertices;

  /* 1. every ring, split at every vertex lying on it */
  const ringIdx = doc.sectors.map(s => {
    const out = [];
    for (let i = 0; i < s.verts.length; i++) {
      const a = s.verts[i], b = s.verts[(i + 1) % s.verts.length];
      out.push(a);
      for (const k of splitsOn(V, a, b)) out.push(k);
    }
    return out;
  });
  const rings = ringIdx.map(r => r.map(i => V[i]));
  /* the plain rings, for containment */
  const plain = doc.sectors.map(s => ringOf(doc, s));

  /* 2. which sectors are holes in which: a sector's DIRECT children are
     the ones strictly inside it and not strictly inside anything else
     that is strictly inside it */
  const inside = plain.map((r, i) => plain.map((o, j) => i !== j && holeIn(r, o)));
  const parentOf = plain.map((_, i) => {
    let best = -1, ba = Infinity;
    plain.forEach((o, j) => {
      if (!inside[i][j]) return;
      const a = Math.abs(signedArea(o));
      if (a < ba) { ba = a; best = j; }
    });
    return best;
  });

  /* 3. and every sector into the builder */
  const flatHoles = new Map();
  const index = new Array(doc.sectors.length).fill(-1);
  doc.sectors.forEach((s, i) => {
    if (plain[i].length < 3 || selfCrosses(plain[i])) return;
    const kids = [];
    parentOf.forEach((p, j) => { if (p === i) kids.push(j); });
    const holes = holeOutlines(kids, ringIdx, V, problems, s);
    const poly = holes.length ? bridge(rings[i], holes) : rings[i];
    const base = sectorProps(s, plain[i]);
    try {
      if (FEATURES.storeys && s.storeys?.length) {
        /* ROOM OVER ROOM: the ground storey and every one above it, one
           outline — see MapBuilder.column, which throws if they do not
           stack, and that is a problem worth reporting rather than a
           crash */
        const stack = [base, ...s.storeys.map(st => sectorProps({ ...s, ...st, floorSlope: st.floorSlope, ceilSlope: st.ceilSlope }, plain[i]))];
        index[i] = mb.column(poly, stack)[0];
      } else {
        index[i] = mb.sector(poly, base);
        /* and where the holes are, for drawing the floor round them —
           see addFlats in js/mapgeo.js */
        if (holes.length) flatHoles.set(index[i], { outer: rings[i], holes });
      }
    } catch (e) {
      problems.push({ kind: 'sector', id: s.id, msg: `sector ${s.id}: ${e.message}` });
    }
  });

  /* 4. the things, and what the scatters grow. The scatters go down
     after everything placed by hand and keep clear of it, in the order
     they were made, each keeping clear of the ones before. */
  const scattered = [];
  const grown = new Map();
  if (doc.scatters?.length) {
    const ringById = new Map(doc.sectors.map(s => [s.id, ringOf(doc, s)]));
    const areas = doc.sectors.map((s, i) => [s, plain[i], Math.abs(signedArea(plain[i]))]).filter(e => e[1].length >= 3);
    /* where a thing can stand: the smallest sector the point is in, if
       that sector is a room with head-room rather than a pillar */
    const standable = (x, y) => {
      let best = null, ba = Infinity;
      for (const [s, r, a] of areas) if (a < ba && pointInPoly(r, x, y)) { ba = a; best = s; }
      return best && (best.ceil ?? 256) - (best.floor ?? 0) >= 64 ? best.id : null;
    };
    const blocked = (x, y, r) => (doc.props || []).some(p =>
      x > Math.min(p.x0, p.x1) - r && x < Math.max(p.x0, p.x1) + r && y > Math.min(p.y0, p.y1) - r && y < Math.max(p.y0, p.y1) + r &&
      Math.min(p.z0, p.z1) < 64);
    const taken = doc.things.map(t => [t.x, t.y]);
    for (const sc of doc.scatters) {
      const g = growScatter(sc, { rings: ringById, standable, blocked, taken });
      grown.set(sc.id, g);
      scattered.push(...g.items);
      if (g.grown < g.wanted * 0.9) {
        problems.push({ kind: 'scatter', id: sc.id,
          msg: `scatter "${sc.name || sc.id}" wanted ${g.wanted} and found room for ${g.grown} — lower the density or the spacing` });
      }
    }
  }
  let started = false;
  for (const t of [...doc.things, ...scattered]) {
    if (!THING_TYPES[t.type] || t.type === 'PLANT') continue;
    if (t.type === 'START') { if (started) continue; started = true; }
    mb.thing(t.type, t.x, t.y, t.angle || 0, t.variant !== undefined ? { variant: t.variant } : {});
  }
  if (!started) {
    /* a map with no start is a map the game throws on — so it gets one,
       in the middle of the first sector, and the problem is reported */
    const r = plain.find(p => p.length >= 3);
    const [cx, cy] = r ? centroid(r) : [0, 0];
    mb.thing('START', cx, cy, 0);
  }

  if (!mb.sectors.length) {
    /* nothing drawable at all: a room, so the game has somewhere to be */
    mb.sector([[0, 0], [512, 0], [512, 512], [0, 512]], sectorProps({ id: 0 }, [[0, 0], [512, 0], [512, 512], [0, 512]]));
    problems.push({ kind: 'map', msg: 'the map has no sectors that can be built' });
  }

  const level = mb.build();
  /* which document sector each level sector is, for a line's two sides
     (see SIDES below) */
  doc.sectors.forEach((s, i) => { if (index[i] >= 0 && level.sectors[index[i]]) level.sectors[index[i]].docId = s.id; });
  for (const [k, f] of flatHoles) {
    const L = level.sectors[k];
    if (L) { L.flatOuter = f.outer; L.flatHoles = f.holes; }
  }

  /* 5. the line overrides: blocking, and a line's own textures */
  const byPair = new Map();
  for (const l of level.lines) {
    const a = level.verts[l.v1], b = level.verts[l.v2];
    byPair.set(`${a[0]},${a[1]}|${b[0]},${b[1]}`, l);
    byPair.set(`${b[0]},${b[1]}|${a[0]},${a[1]}`, l);
  }
  /* A DOCUMENT LINE CAN BE SEVERAL LEVEL LINES: the compiler splits an
     edge at every vertex that lies on it (step 1), so a line is found as
     every level line along it, not only the one that runs end to end */
  const levelLinesOn = (a, b) => {
    const whole = byPair.get(`${a[0]},${a[1]}|${b[0]},${b[1]}`);
    if (whole) return [whole];
    return level.lines.filter(l => {
      const p = level.verts[l.v1], q = level.verts[l.v2];
      return segDist(a[0], a[1], b[0], b[1], p[0], p[1]).d < 0.5 && segDist(a[0], a[1], b[0], b[1], q[0], q[1]).d < 0.5;
    });
  };
  for (const [k, o] of Object.entries(doc.lines || {})) {
    const [ai, bi] = k.split(',').map(Number);
    const a = V[ai], b = V[bi];
    if (!a || !b) continue;
    for (const l of levelLinesOn(a, b)) applyLine(l, o);
  }
  function applyLine(l, o) {
    if (o.blocking) l.blocking = true;
    if (o.blockSight) l.blockSight = true;
    /* A LINE'S OWN TEXTURES, locked so the level's own reassignment
       (assignLineTextures, run again whenever a sector changes) keeps
       them: the middle of a one-sided wall, or the upper and lower
       steps of a two-sided one */
    if (o.wallTex || o.upperTex || o.lowerTex) {
      if (l.bands) {
        if (o.upperTex) l.upper = o.upperTex;
        if (o.lowerTex) l.lower = o.lowerTex;
        for (const bd of l.bands) bd.tex = bd.kind === 'upper' ? l.upper : l.lower;
        l.texLocked = true;
      } else if (o.wallTex && l.middle) {
        l.middle = o.wallTex;
        l.texLocked = true;
      }
    }
    /* THE MIDDLE OF A TWO-SIDED LINE: what stands IN the opening — a
       grating, a fence, a window — Doom's masked middle texture */
    if (o.midTex && l.bands) { l.middle = o.midTex; if (o.midHeight) l.midHeight = o.midHeight; }
    /* and it is drawn ONCE, its own height, as Doom draws one, unless
       the line gives it a height of its own (see midOnce in
       js/mapgeo.js). The game's own levels fill their openings with
       glass; a map from here puts a thing in one. */
    if (l.bands && (o.midTex || Object.values(o.sides || {}).some(x => x.midTex))) l.midOnce = true;
    /* THE OFFSETS AND THE PEGGING, Doom's sidedef x and y offsets and its
       two unpegged flags, in this engine's terms (see pegOf in
       js/mapgeo.js): upper unpegged hangs the upper texture from the
       ceiling; lower unpegged measures the lower from the ceiling too,
       and sits a one-sided middle on the floor, as it does in Doom */
    if (o.xoff) l.xoff = o.xoff;
    if (o.yoff) l.yoff = o.yoff;
    if (o.xscale > 0 && o.xscale !== 1) l.xscale = o.xscale;
    if (o.yscale > 0 && o.yscale !== 1) l.yscale = o.yscale;
    if (o.unpegUpper) l.pegUpper = 'top';
    if (o.unpegLower) { l.pegLower = 'ceiling'; l.pegMiddle = 'bottom'; }
    /* THE TWO SIDES, Doom's front and back sidedefs: what each face of
       the line wears, kept by the sector that face looks into, so a
       building's wall can be brick outside and plaster in. Read face by
       face by js/mapgeo.js (sideOf); a side that says nothing wears the
       line's own, as above */
    if (o.sides && Object.keys(o.sides).length) {
      l.sides = o.sides;
      l.texLocked = true;
    }
  }

  /* 5c. INSIDE MEETS OUTSIDE: A WALL. A sector is inside if it has a
     roof (a ceiling that is not the sky) and outside if it is open to
     the sky; where the two meet the map has the outside wall of a
     building, from the inside floor up to its roof — a middle texture
     standing in the opening, solid, blocking walking and sight — unless
     the line says it is a doorway. Its texture is the line's middle if
     it has one, or the inside sector's walls. */
  for (const dl of linesOf(doc)) {
    if (dl.sectors.length !== 2) continue;
    const [sa, sb] = dl.sectors.map(i => doc.sectors[i]);
    const inA = sa.ceilTex && sa.ceilTex !== 'SKY', inB = sb.ceilTex && sb.ceilTex !== 'SKY';
    if (inA === inB) continue;
    const o = doc.lines[dl.key] || {};
    if (o.opening) continue;
    const inside = inA ? sa : sb;
    for (const l of levelLinesOn(V[dl.a], V[dl.b])) {
      if (!l.bands) continue;
      l.middle = o.midTex || inside.wallTex || 'GRIDWALL';
      l.midHeight = undefined;
      /* a wall fills the opening; it is not a thing standing in it */
      l.midOnce = false;
      l.blocking = true;
      l.blockSight = true;
      l.exterior = true;
    }
  }

  /* 5a. AN OPEN WORLD HAS NO SKY WALLS. Doom draws the upper texture
     between an outdoor sector's sky and the lower roof of a room beside
     it, which is how its buildings go up to the clouds; with the sky as
     the default everywhere that is a tower over every room. So, unless
     the map asks for Doom's way (world.skyWalls), that band is not
     drawn, and the room's ceiling is drawn from above as well — a roof,
     in the room's own ceiling texture unless it names another. */
  const wAll = { ...defaultWorld(), ...(doc.world || {}) };
  if (!wAll.skyWalls) {
    for (const l of level.lines) for (const bd of l.bands || []) {
      if (bd.kind === 'upper' && bd.open?.ceilTex === 'SKY' && bd.from && bd.from.ceilTex !== 'SKY') bd.tex = 'NONE';
    }
    doc.sectors.forEach((s, i) => {
      const L = level.sectors[index[i]];
      if (!L || L.ceilTex === 'SKY' || L.ceilTex === 'NONE') return;
      L.roofTex = s.roofTex || L.ceilTex;
      L.editorRoof = true;
    });
  }

  /* 5b. DOOM 64'S COLOURS: each sector's floor, ceiling and things, and
     its walls from the top colour down to the bottom one */
  const wL = { ...defaultWorld(), ...(doc.world || {}) };
  const fogW = wL.fog || {};
  doc.sectors.forEach((s, i) => {
    const L = index[i] >= 0 ? level.sectors[index[i]] : null;
    if (!L) return;
    const c = s.colors || {};
    /* A SECTOR'S LIGHT COLOUR: one colour for all the light in it,
       multiplied into each of the five above (white where one is not
       set), so a room can be lit red without five pickers */
    const lc = s.lightColor && s.lightColor.toLowerCase() !== '#ffffff' ? hexRGB(s.lightColor) : null;
    const t = {};
    for (const k of COLOR_PARTS) {
      if (!c[k] && !lc) continue;
      const v = c[k] ? hexRGB(c[k]) : [1, 1, 1];
      t[k] = lc ? [v[0] * lc[0], v[1] * lc[1], v[2] * lc[2]] : v;
    }
    if (Object.keys(t).length) L.tint = t;
    /* ITS FOG: a colour and a density (0 to 100; see SECTOR FOG in
       js/material.js), or the map's default fog if it has none. The
       map's fog colour OVERRIDES the sector's when the map says so. */
    const own = s.fog && s.fog.density > 0 ? s.fog : null;
    if (own) {
      const rgb = hexRGB(fogW.override && fogW.color ? fogW.color : (own.color || '#808080'));
      L.fog = [rgb[0], rgb[1], rgb[2], Math.min(100, own.density)];
    }
  });
  /* AND THE MAP'S OWN LIGHT, for the renderer (applyMapLight in
     js/material.js): its light colour, its ambient light, its default
     fog, and whether that fog's colour overrides every other */
  level.mapLight = mapLightOf(wL);

  /* 6. and the world around it */
  const w = { ...defaultWorld(), ...(doc.world || {}) };
  level.noBurn = !!w.noBurn;
  level.noSquads = !!w.noSquads;
  level.noCellFire = !!w.noCellFire;
  level.sky = w.sky;
  /* a skybox from the texture pack (js/texpack.js), by name, or none */
  level.skybox = w.skybox || null;
  level.carSlots = [];
  level.slideDoors = [];
  level.props = (doc.props || []).map(p => {
    const box = {
      x0: Math.min(p.x0, p.x1), y0: Math.min(p.y0, p.y1), x1: Math.max(p.x0, p.x1), y1: Math.max(p.y0, p.y1),
      z0: Math.min(p.z0, p.z1), z1: Math.max(p.z0, p.z1),
      tex: p.tex || 'GRIDWALL', topTex: p.topTex || p.tex || 'GRIDWALL', sky: 0,
    };
    /* A 3D OBJECT IN A SECTOR is lit, coloured and fogged by it, as a
       thing is: the sector under its middle, its light (unless the box
       has its own), its thing colour, its fog */
    const s = level.sectorAt?.((box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2);
    box.light = p.light ?? s?.light ?? 0.66;
    if (s?.tint?.thing) box.tint = s.tint.thing;
    if (s?.fog) box.fog = s.fog;
    return box;
  });
  level.roofs = [];
  /* THE PLANTS, placed and spread: the list js/forest.js grows a town's
     gardens from, and — with no wood on this map — the only thing it
     grows (see plantsOnly there). The forest keeps ONE TREE TO A 64
     CELL, so a second tree in a cell would never appear; it is left out
     here instead, so the editor shows what the game will. */
  level.plants = [];
  const treeCells = new Set(), dropped = new Set();
  const [ox, oy] = level.bounds;
  for (const t of [...doc.things, ...scattered]) {
    if (t.type !== 'PLANT' || !plantKind(t.kind)) continue;
    if (isCanopyKind(t.kind)) {
      const c = `${Math.floor((t.x - ox) / 64)},${Math.floor((t.y - oy) / 64)}`;
      if (treeCells.has(c)) { dropped.add(t); continue; }
      treeCells.add(c);
    }
    level.plants.push({ kind: t.kind, x: t.x, y: t.y, scale: t.scale ?? 1 });
  }
  level.forestRects = [];
  level.forestBounds = level.bounds;
  level.clearing = level.fireBounds;
  level.town = null;
  level.exits = [];
  level.roadEnds = [];
  level.boxes = [];
  const st = level.things.find(t => t.type === 'START');
  level.viewpoint = { x: st.x, y: st.y, angle: st.angle };
  const b = level.bounds;
  level.salesFloor = { x0: b[0], y0: b[1], x1: b[2], y1: b[3] };
  level.road = { y0: 0, y1: 0 };
  level.title = (doc.name || 'EDITED MAP').toUpperCase();
  level.field = { x0: b[0], y0: b[1], x1: b[2], y1: b[3], cell: 64, floor: 0, ceil: 1024 };
  level.fromEditor = true;

  return { level, problems, index, scattered: scattered.filter(t => !dropped.has(t)), dropped: dropped.size, grown };
}

/* ---------------------------------------------------------------------
   SAVING AND LOADING
   --------------------------------------------------------------------- */

/** The document as a file: JSON, with the format named so a file that
 *  is not one of ours is refused rather than half-loaded. */
export function serialise(doc) { return JSON.stringify(doc, null, 1); }

/** And back. Throws on anything that is not a map this editor wrote. */
export function parseDoc(text) {
  const d = JSON.parse(text);
  if (d.format !== DOC_FORMAT) throw new Error('not a gss-map file');
  if (!Array.isArray(d.vertices) || !Array.isArray(d.sectors)) throw new Error('the file has no vertices or sectors');
  d.lines = d.lines || {};
  d.linedefs = d.linedefs || [];
  d.things = d.things || [];
  d.props = d.props || [];
  d.scatters = d.scatters || [];
  d.textures = d.textures || [];
  d.world = { ...defaultWorld(), ...(d.world || {}) };
  let top = 1;
  for (const x of [...d.sectors, ...d.things, ...d.props, ...d.scatters]) top = Math.max(top, (x.id | 0) + 1);
  d.nextId = Math.max(d.nextId | 0, top);
  return d;
}

/* ---------------------------------------------------------------------
   UNDO

   Whole snapshots, which is the honest answer at this size: a map a
   person is drawing by hand is a few hundred vertices, a snapshot is a
   few kilobytes of JSON, and a stack of two hundred of them is nothing.
   Diffing would be cleverer and every clever undo is one edit away from
   restoring a map that never existed.
   --------------------------------------------------------------------- */
export class History {
  constructor(doc, cap = 200) {
    this.cap = cap;
    this.past = [];
    this.future = [];
    this.doc = doc;
    this.saved = serialise(doc);
  }

  /** Before an edit: remember the map as it is now. */
  push(label = '') {
    this.past.push({ label, text: serialise(this.doc) });
    if (this.past.length > this.cap) this.past.shift();
    this.future.length = 0;
  }

  undo() {
    const s = this.past.pop();
    if (!s) return null;
    this.future.push({ label: s.label, text: serialise(this.doc) });
    this.doc = parseDoc(s.text);
    return s.label || 'edit';
  }

  redo() {
    const s = this.future.pop();
    if (!s) return null;
    this.past.push({ label: s.label, text: serialise(this.doc) });
    this.doc = parseDoc(s.text);
    return s.label || 'edit';
  }

  get dirty() { return serialise(this.doc) !== this.saved; }
  markSaved() { this.saved = serialise(this.doc); }
}
