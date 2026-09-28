/* =====================================================================
   MEWD — THE MAZE, the demo's world

   At the user's request the demo opens on a PROCEDURALLY GENERATED MAZE
   with tons of people in it. A new one every time the game starts (or
   the one `?seed=N` names, to go back to a maze you liked), built as a
   MEWD Editor document and compiled by the same compiler as any map
   drawn by hand — so it opens in the editor as well (File → Open demo).

   THE MAZE is a perfect maze carved by a depth-first walk over a grid of
   cells (the recursive backtracker: long winding corridors, few short
   dead ends), then BRAIDED — a share of the walls knocked through at
   random — so there are loops and more than one way round, and then a
   few PLAZAS cleared in it: open squares paved in concrete with a lamp
   and a tree, where the corridors meet and the crowd gathers.

   THE PLAN is a grid of tiles, wall and floor alternating: a thin wall
   line, a wide corridor cell, a thin wall line, and so on across. A
   wall tile is a sector raised to a hedge's height, which nobody can
   step up onto; a floor tile is ground. Runs of the same kind along a
   row are one sector, and runs the same across two rows are joined into
   one, so a map of thousands of tiles is a few hundred rectangles that
   tile the square exactly — no sector inside another, only walls
   shared, which is what the compiler's T-junction pass is for.

   THE PEOPLE are shoppers and townspeople, several hundred of them,
   spread over the floor tiles with room between them.
   ===================================================================== */

import { SECTOR_DEFAULTS, DOC_FORMAT, DOC_VERSION, defaultWorld } from '../editor/doc.js';

export const MAZE_NAME = 'THE MAZE';
/** how many corridor cells across and down */
export const MAZE_CELLS = 18;
/** a corridor's width, and a wall's thickness */
export const CELL = 256, WALL = 64;
/** how high the hedges stand, and the sky over it all */
export const HEDGE_H = 192, SKY_H = 320;
/** how many people */
export const MAZE_PEOPLE = 520;

/** A seed for a new maze each visit. */
export const newMazeSeed = () => (Math.random() * 2 ** 31) >>> 0;

/** Build THE MAZE for `seed`. Pure: one seed, one maze. */
export function mazeDoc(seed = 1, { cells = MAZE_CELLS, people = MAZE_PEOPLE } = {}) {
  let s = (seed >>> 0) || 1;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const N = cells, T = 2 * N + 1;

  /* ---- THE CARVING: a depth-first walk ---------------------------- */
  const open = Array.from({ length: T }, () => new Uint8Array(T));   // 1 = floor
  const seen = Array.from({ length: N }, () => new Uint8Array(N));
  const stack = [[(rnd() * N) | 0, (rnd() * N) | 0]];
  seen[stack[0][1]][stack[0][0]] = 1;
  open[2 * stack[0][1] + 1][2 * stack[0][0] + 1] = 1;
  const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  while (stack.length) {
    const [cx, cy] = stack[stack.length - 1];
    const next = dirs.map(([dx, dy]) => [cx + dx, cy + dy, dx, dy])
      .filter(([x, y]) => x >= 0 && y >= 0 && x < N && y < N && !seen[y][x]);
    if (!next.length) { stack.pop(); continue; }
    const [x, y, dx, dy] = next[(rnd() * next.length) | 0];
    seen[y][x] = 1;
    open[2 * cy + 1 + dy][2 * cx + 1 + dx] = 1;
    open[2 * y + 1][2 * x + 1] = 1;
    stack.push([x, y]);
  }
  /* BRAIDED: an inside wall between two cells knocked through, one in
     eight, so there is more than one way round */
  for (let ty = 1; ty < T - 1; ty++) for (let tx = 1; tx < T - 1; tx++) {
    if (open[ty][tx]) continue;
    const horiz = ty % 2 === 1 && tx % 2 === 0, vert = ty % 2 === 0 && tx % 2 === 1;
    if ((horiz || vert) && rnd() < 0.12) open[ty][tx] = 1;
  }
  /* PLAZAS: a few squares of three cells by three cleared right out */
  const plazas = [];
  const nPlaza = Math.max(2, Math.round(N * N / 70));
  for (let k = 0; k < nPlaza * 8 && plazas.length < nPlaza; k++) {
    const px = 1 + ((rnd() * (N - 4)) | 0), py = 1 + ((rnd() * (N - 4)) | 0);
    if (plazas.some(p => Math.abs(p[0] - px) < 5 && Math.abs(p[1] - py) < 5)) continue;
    plazas.push([px, py]);
    for (let ty = 2 * py + 1; ty <= 2 * (py + 2) + 1; ty++) for (let tx = 2 * px + 1; tx <= 2 * (px + 2) + 1; tx++) open[ty][tx] = 2;
  }

  /* ---- TILE EDGES in map units: wall, cell, wall, cell … wall ------ */
  const edge = i => Math.floor(i / 2) * (WALL + CELL) + (i % 2 ? WALL : 0);   // left edge of tile i
  const size = edge(T);

  const d = {
    format: DOC_FORMAT, version: DOC_VERSION, name: MAZE_NAME,
    vertices: [], sectors: [], lines: {}, linedefs: [], things: [], textures: [], props: [], scatters: [],
    world: { ...defaultWorld(), skybox: 'BSKY2', ambient: { color: '#ffffff', amount: 0.3 }, lightColor: '#fff6ea', mazeSeed: seed >>> 0 },
    nextId: 1,
  };
  const vmap = new Map();
  const v = (x, y) => {
    const k = `${x},${y}`;
    let i = vmap.get(k);
    if (i === undefined) { i = d.vertices.length; d.vertices.push([x, y]); vmap.set(k, i); }
    return i;
  };
  const id = () => d.nextId++;
  /* every corner of every tile a vertex, so the rectangles' edges are
     split where the next row's rectangles meet them */
  const KIND = {
    0: { name: 'hedge', floor: HEDGE_H, ceil: SKY_H, floorTex: 'MOSS_01', wallTex: 'IVY1', lowerTex: 'IVY1', upperTex: null },
    1: { name: 'path', floor: 0, ceil: SKY_H, floorTex: 'DIRT_01', wallTex: 'IVY1', lowerTex: 'IVY1', upperTex: null },
    2: { name: 'plaza', floor: 0, ceil: SKY_H, floorTex: 'CONC_4', wallTex: 'IVY1', lowerTex: 'IVY1', upperTex: null },
  };
  /* runs along each row, then runs the same across rows joined */
  const runs = [];
  for (let ty = 0; ty < T; ty++) {
    let tx = 0;
    while (tx < T) {
      const k = open[ty][tx];
      let e = tx;
      while (e + 1 < T && open[ty][e + 1] === k) e++;
      runs.push({ k, x0: tx, x1: e, y0: ty, y1: ty });
      tx = e + 1;
    }
  }
  const byRow = new Map();
  const rects = [];
  for (const r of runs) {
    const above = (byRow.get(r.y0 - 1) || []).find(q => q.k === r.k && q.x0 === r.x0 && q.x1 === r.x1);
    if (above) { above.y1 = r.y0; (byRow.get(r.y0) || byRow.set(r.y0, []).get(r.y0)).push(above); }
    else { rects.push(r); (byRow.get(r.y0) || byRow.set(r.y0, []).get(r.y0)).push(r); }
  }
  /* each rectangle, its ring through every tile corner along its edges */
  for (const r of rects) {
    const X0 = r.x0, X1 = r.x1 + 1, Y0 = r.y0, Y1 = r.y1 + 1;
    const ring = [];
    for (let i = X0; i < X1; i++) ring.push([edge(i), edge(Y0)]);
    for (let j = Y0; j < Y1; j++) ring.push([edge(X1), edge(j)]);
    for (let i = X1; i > X0; i--) ring.push([edge(i), edge(Y1)]);
    for (let j = Y1; j > Y0; j--) ring.push([edge(X0), edge(j)]);
    d.sectors.push({ ...SECTOR_DEFAULTS, light: 1, outdoor: true, ceilTex: 'SKY', ...KIND[r.k], id: id(), verts: ring.map(([x, y]) => v(x, y)) });
  }

  /* ---- THINGS ------------------------------------------------------ */
  const mid = i => edge(i) + (i % 2 ? CELL : WALL) / 2;
  const thing = (type, x, y, extra = {}) => d.things.push({ id: id(), type, x: Math.round(x), y: Math.round(y), angle: rnd() * Math.PI * 2, ...extra });
  /* the start: the cell nearest a corner, facing into the maze */
  thing('START', mid(1), mid(1), { angle: Math.PI / 4 });
  /* the plazas: a lamp in each corner and a tree in the middle */
  const TREES = ['fir_tall_1', 'savanna_tree_1', 'wasteland_tree', 'pine_juvenile_fir_tree_1'];
  for (const [px, py] of plazas) {
    const x0 = edge(2 * px + 1), y0 = edge(2 * py + 1), x1 = edge(2 * (px + 2) + 2), y1 = edge(2 * (px + 2) + 2);
    for (const [x, y] of [[x0 + 48, y0 + 48], [x1 - 48, y0 + 48], [x0 + 48, y1 - 48], [x1 - 48, y1 - 48]]) thing('STREETLAMP', x, y);
    thing('PLANT', (x0 + x1) / 2, (y0 + y1) / 2, { kind: TREES[(rnd() * TREES.length) | 0], scale: 1 });
  }
  /* THE CROWD: on the floor tiles, a little apart, never on the start */
  const floor = [];
  for (let ty = 0; ty < T; ty++) for (let tx = 0; tx < T; tx++) if (open[ty][tx]) floor.push([tx, ty]);
  const taken = [[mid(1), mid(1)]];
  const clear = (x, y) => taken.every(([a, b]) => (a - x) ** 2 + (b - y) ** 2 > 40 * 40) && (x - mid(1)) ** 2 + (y - mid(1)) ** 2 > 200 * 200;
  for (let k = 0, n = 0; n < people && k < people * 20; k++) {
    const [tx, ty] = floor[(rnd() * floor.length) | 0];
    const w = tx % 2 ? CELL : WALL, h = ty % 2 ? CELL : WALL;
    const x = edge(tx) + 20 + rnd() * (w - 40), y = edge(ty) + 20 + rnd() * (h - 40);
    if (w < 40 || h < 40 || !clear(x, y)) continue;
    taken.push([x, y]);
    thing(rnd() < 0.55 ? 'TOWNIE' : 'SHOPPER', x, y, { variant: (rnd() * 17) | 0 });
    n++;
  }
  d.mazeSize = size;
  return d;
}
