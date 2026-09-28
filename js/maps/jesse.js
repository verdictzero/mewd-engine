/* =====================================================================
   MEWD — JESSE, the PvP maze

   At the user's request: two FORTIFIABLE STAGING AREAS, one at each end,
   joined by a massive MULTITHREADED maze — dead ends, loops, turn-
   arounds, rooms — PROCEDURAL AND WILDLY DIFFERENT EVERY TIME. Typed as
   `jesse` at the terminal (js/terminal.js), or ?jesse, and ?jesse&seed=N
   plays one again.

   THE SAME FORMAT AS THE MAZE (js/maps/maze.js): a grid of tiles, a
   thin 64-unit wall line between every pair of 256-unit corridor cells,
   a wall tile raised to a hedge's height, runs of one kind merged into
   rectangles and those into a MEWD Editor document the ordinary
   compiler builds — so it opens in the editor like any other map.

   WILDLY DIFFERENT, because nothing about it is fixed but the idea:

     THE SIZE        30–41 cells long, 18–26 across.
     THE ZONES       the maze is cut into two to five bands across its
                     length, and each band is carved by its OWN
                     algorithm — the recursive backtracker's long winding
                     corridors, Prim's bushy tangle of short dead ends, a
                     growing tree anywhere between the two, a binary
                     tree's long straight runs, Kruskal's even texture —
                     with its own walls (hedge, rock, concrete), its own
                     ground, and its own share of loops.
     THE THREADS     where two bands meet, a handful of openings, so
                     there is never one way through; and braiding inside
                     each band, from a few loops to a lattice.
     THE ROOMS       open squares, pillared halls, and cloisters — a
                     ring round a block of hedge — cleared across the
                     corridors, so a room has whatever doors the maze
                     happened to give it.
     THE SYMMETRY    half the time the whole maze is point-symmetric,
                     the right half the left half turned round, which is
                     the fair map; the other half it is not.

   THE BASES are always mirror images of each other, because the game
   is decided in them. Each is a walled yard at its end of the map:
     - A FORT WALL round it, lower than the hedges, with two to four
       GATES into the maze — the chokes you hold.
     - COVER inside: low walls on the yard's wall lines, knee-to-chest
       height, too high to step over and low enough to shoot over.
     - A TOWER at the back, reached by steps, high enough to see over
       the fort wall and down the approaches to the gates.
     - STOCK CRATES to push into the gates and FUEL CANS, which are the
       fortifying — solid, shootable, flammable, and in the way.
     - SPAWN PADS, listed in world.pvp for whatever puts players there;
       the single-player START is on team A's.
   ===================================================================== */

import { SECTOR_DEFAULTS, DOC_FORMAT, DOC_VERSION, defaultWorld } from '../editor/doc.js';
import { CELL, WALL, HEDGE_H, SKY_H } from './maze.js';

export const JESSE_NAME = 'JESSE';
export const FORT_H = 120;       // the fort wall: under a hedge, over a head
export const COVER_H = 40;       // cover: over a step (24), under an eye (49)
export const TOWER_H = 96;       // the tower's deck
export const STEP = 24;          // the most a step can be
export const ALGOS = ['backtracker', 'prim', 'tree', 'binary', 'kruskal'];

/** A seed for a new one each visit. */
export const newJesseSeed = () => (Math.random() * 2 ** 31) >>> 0;

/** Build JESSE for `seed`. Pure: one seed, one map. */
export function jesseDoc(seed = 1, opts = {}) {
  let s = (seed >>> 0) || 1;
  const rnd = () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
  const ri = (a, b) => a + ((rnd() * (b - a + 1)) | 0);
  const pick = a => a[(rnd() * a.length) | 0];
  const shuffle = a => { for (let i = a.length - 1; i > 0; i--) { const j = (rnd() * (i + 1)) | 0; [a[i], a[j]] = [a[j], a[i]]; } return a; };

  const W = opts.w ?? ri(30, 41), H = opts.h ?? ri(18, 26);
  const TX = 2 * W + 1, TY = 2 * H + 1;
  const symmetric = opts.symmetric ?? rnd() < 0.5;

  /* ---- THE KINDS of tile, as sector templates ----------------------- */
  const KINDS = [];
  const kindIx = new Map();
  const kind = (name, props) => {
    if (kindIx.has(name)) return kindIx.get(name);
    KINDS.push({ name, ...props });
    kindIx.set(name, KINDS.length - 1);
    return KINDS.length - 1;
  };
  const walkable = new Set();
  const HEDGES = [
    { wall: 'IVY1', top: 'MOSS_01' }, { wall: 'IVY1', top: 'GRASS5' }, { wall: 'ROCK_01', top: 'ROCK_01' },
    { wall: 'CONC_7', top: 'CONC_7' }, { wall: 'CONC_3', top: 'MOSS_01' },
  ];
  const GROUNDS = ['DIRT_01', 'DIRT_02', 'DIRT3', 'GRASS5', 'SIDEWLK1', 'CONC_2', 'CONC_1'];
  const hedgeKind = (h, hgt) => kind(`hedge:${h.wall}:${h.top}:${hgt}`,
    { floor: hgt, floorTex: h.top, wallTex: h.wall, lowerTex: h.wall, upperTex: null });
  const pathKind = g => { const k = kind(`path:${g}`, { floor: 0, floorTex: g, wallTex: 'IVY1', lowerTex: 'IVY1', upperTex: null }); walkable.add(k); return k; };

  /* ---- THE ZONES: bands across the length, each its own maze -------- */
  const nZones = opts.zones ?? ri(2, 5);
  const cuts = [0];
  for (let z = 1; z < nZones; z++) cuts.push(Math.round((W * z) / nZones + (rnd() - 0.5) * (W / nZones) * 0.5));
  cuts.push(W);
  const zones = [];
  for (let z = 0; z < nZones; z++) {
    const hedge = pick(HEDGES);
    zones.push({
      xa: cuts[z], xb: cuts[z + 1], algo: opts.algo ?? pick(ALGOS), p: rnd(),
      hedge: hedgeKind(hedge, ri(0, 3) === 0 ? HEDGE_H + 64 : HEDGE_H), path: pathKind(pick(GROUNDS)),
      braid: [0.02, 0.08, 0.15, 0.3][ri(0, 3)],
    });
  }
  const zoneAt = x => zones.find(z => x >= z.xa && x < z.xb) || zones[zones.length - 1];

  /* the tiles, all wall to begin with, each its column's zone's wall */
  const t = new Uint8Array(TX * TY);
  for (let ty = 0; ty < TY; ty++) for (let tx = 0; tx < TX; tx++)
    t[ty * TX + tx] = zoneAt(Math.min(W - 1, Math.max(0, (tx - 1) >> 1))).hedge;
  const T = (tx, ty) => t[ty * TX + tx];
  const setT = (tx, ty, k) => { t[ty * TX + tx] = k; };
  const cellT = (x, y) => [2 * x + 1, 2 * y + 1];
  const openCell = (x, y) => setT(2 * x + 1, 2 * y + 1, zoneAt(x).path);
  const carve = (ax, ay, bx, by) => {
    openCell(ax, ay); openCell(bx, by);
    setT(ax + bx + 1, ay + by + 1, zoneAt(Math.min(ax, bx)).path);
  };

  const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  for (const z of zones) {
    const inZ = (x, y) => x >= z.xa && x < z.xb && y >= 0 && y < H;
    const zw = z.xb - z.xa;
    if (zw <= 0) continue;
    if (z.algo === 'binary') {
      /* long straight runs along two sides, every cell hung off them */
      const north = rnd() < 0.5, east = rnd() < 0.5;
      for (let y = 0; y < H; y++) for (let x = z.xa; x < z.xb; x++) {
        const opts2 = [];
        const ny = north ? y - 1 : y + 1, ex = east ? x + 1 : x - 1;
        if (inZ(x, ny)) opts2.push([x, ny]);
        if (inZ(ex, y)) opts2.push([ex, y]);
        openCell(x, y);
        if (opts2.length) { const [bx, by] = pick(opts2); carve(x, y, bx, by); }
      }
    } else if (z.algo === 'kruskal') {
      const id = new Int32Array(zw * H).map((_, i) => i);
      const find = i => { while (id[i] !== i) { id[i] = id[id[i]]; i = id[i]; } return i; };
      const edges = [];
      for (let y = 0; y < H; y++) for (let x = z.xa; x < z.xb; x++) {
        if (inZ(x + 1, y)) edges.push([x, y, x + 1, y]);
        if (inZ(x, y + 1)) edges.push([x, y, x, y + 1]);
      }
      for (const [ax, ay, bx, by] of shuffle(edges)) {
        const a = find(ay * zw + ax - z.xa), b = find(by * zw + bx - z.xa);
        if (a !== b) { id[a] = b; carve(ax, ay, bx, by); }
      }
    } else {
      /* the growing tree: always the newest is the backtracker, always
         a random one is Prim's, and anything between is between */
      const p = z.algo === 'backtracker' ? 1 : z.algo === 'prim' ? 0 : z.p;
      const seen = new Uint8Array(W * H);
      const sx = ri(z.xa, z.xb - 1), sy = ri(0, H - 1);
      seen[sy * W + sx] = 1; openCell(sx, sy);
      const list = [[sx, sy]];
      while (list.length) {
        const i = rnd() < p ? list.length - 1 : (rnd() * list.length) | 0;
        const [cx, cy] = list[i];
        const next = DIRS.map(([dx, dy]) => [cx + dx, cy + dy]).filter(([x, y]) => inZ(x, y) && !seen[y * W + x]);
        if (!next.length) { list.splice(i, 1); continue; }
        const [nx, ny] = pick(next);
        seen[ny * W + nx] = 1;
        carve(cx, cy, nx, ny);
        list.push([nx, ny]);
      }
    }
    /* BRAIDED, by the zone's own share */
    for (let y = 0; y < H; y++) for (let x = z.xa; x < z.xb; x++) {
      if (inZ(x + 1, y) && rnd() < z.braid) carve(x, y, x + 1, y);
      if (inZ(x, y + 1) && rnd() < z.braid) carve(x, y, x, y + 1);
    }
  }
  /* THE THREADS between the zones: several openings on every seam */
  for (let k = 1; k < zones.length; k++) {
    const x = zones[k].xa - 1;
    if (x < 0) continue;
    const ys = shuffle([...Array(H).keys()]).slice(0, Math.max(2, ri(H >> 3, H >> 1)));
    for (const y of ys) carve(x, y, x + 1, y);
  }

  /* ---- THE ROOMS ------------------------------------------------------ */
  const rooms = [];
  const nRooms = opts.rooms ?? ri(3, 11);
  for (let k = 0; k < nRooms * 6 && rooms.length < nRooms; k++) {
    const w = ri(2, 5), h = ri(2, 4);
    const x = ri(3, W - w - 3), y = ri(0, H - h);
    if (rooms.some(r => x < r.x + r.w + 1 && r.x < x + w + 1 && y < r.y + r.h + 1 && r.y < y + h + 1)) continue;
    const style = pick(['open', 'open', 'pillars', 'cloister']);
    rooms.push({ x, y, w, h, style });
    const floor = kind('room:' + pick(['CONC_4', 'CONC_5', 'SIDEWLK1']), {});
    const room = KINDS[floor];
    if (!room.floorTex) Object.assign(room, { floor: 0, floorTex: room.name.slice(5), wallTex: 'IVY1', lowerTex: 'IVY1', upperTex: null });
    walkable.add(floor);
    for (let ty = 2 * y + 1; ty <= 2 * (y + h - 1) + 1; ty++) for (let tx = 2 * x + 1; tx <= 2 * (x + w - 1) + 1; tx++) {
      const post = tx % 2 === 0 && ty % 2 === 0;
      if (style === 'pillars' && post) continue;               // the posts stay: a hall of pillars
      if (style === 'cloister' && w >= 3 && h >= 3 &&
          tx > 2 * x + 1 && tx < 2 * (x + w - 1) + 1 && ty > 2 * y + 1 && ty < 2 * (y + h - 1) + 1) continue;
      setT(tx, ty, floor);
    }
  }

  /* ---- POINT SYMMETRY, half the time --------------------------------- */
  if (symmetric) {
    for (let ty = 0; ty < TY; ty++) for (let tx = W + 1; tx < TX; tx++) setT(tx, ty, T(TX - 1 - tx, TY - 1 - ty));
    for (const r of rooms.slice()) if (r.x + r.w <= W / 2) rooms.push({ ...r, x: W - r.x - r.w, y: H - r.y - r.h, mirror: true });
  }

  /* ---- THE BASES: always mirror images ------------------------------- */
  const bw = opts.baseW ?? ri(5, 7), bh = Math.min(H - 2, opts.baseH ?? ri(6, 9));
  const by0 = ri(1, H - bh - 1);
  const baseFloorA = kind('base:A', { floor: 0, floorTex: 'CONC_4', wallTex: 'METALP1', lowerTex: 'METALP1', upperTex: null, light: 1 });
  const baseFloorB = kind('base:B', { floor: 0, floorTex: 'CONC_5', wallTex: 'CONC_7', lowerTex: 'CONC_7', upperTex: null, light: 1 });
  const fortA = kind('fort:A', { floor: FORT_H, floorTex: 'METALP1', wallTex: 'METALP1', lowerTex: 'METALP1', upperTex: null });
  const fortB = kind('fort:B', { floor: FORT_H, floorTex: 'CONC_7', wallTex: 'CONC_7', lowerTex: 'CONC_7', upperTex: null });
  const coverA = kind('cover:A', { floor: COVER_H, floorTex: 'CAUTSTR2', wallTex: 'CAUTSTR2', lowerTex: 'CAUTSTR2', upperTex: null });
  const coverB = kind('cover:B', { floor: COVER_H, floorTex: 'CAUTSTR2', wallTex: 'CAUTSTR2', lowerTex: 'CAUTSTR2', upperTex: null });
  const stepK = (team, h) => kind(`step:${team}:${h}`, { floor: h, floorTex: team === 'A' ? 'METALP1' : 'CONC_7', wallTex: 'CAUTSTR2', lowerTex: 'CAUTSTR2', upperTex: null });
  for (const k of [baseFloorA, baseFloorB]) walkable.add(k);

  /* the plan of base A in tile coordinates; B is it turned round */
  const X0 = 0, X1 = 2 * bw, Y0 = 2 * by0, Y1 = 2 * (by0 + bh);
  const plan = [];                                   // [tx, ty, 'floor'|'fort'|'cover'|'gate'|'step:h']
  for (let ty = Y0; ty <= Y1; ty++) for (let tx = X0; tx <= X1; tx++) {
    const edge = tx === X0 || tx === X1 || ty === Y0 || ty === Y1;
    plan.push([tx, ty, edge ? 'fort' : 'floor']);
  }
  const at = new Map(plan.map(p => [p[0] + ',' + p[1], p]));
  const mark = (tx, ty, what) => { const p = at.get(tx + ',' + ty); if (p) p[2] = what; };
  /* THE GATES: on the side facing the maze, and maybe top and bottom */
  const gates = [];
  const gateCells = shuffle([...Array(bh).keys()]).slice(0, ri(1, 2));
  for (const gy of gateCells) gates.push([X1, 2 * (by0 + gy) + 1]);
  if (by0 > 0 && rnd() < 0.7) gates.push([2 * ri(1, bw - 1) + 1, Y0]);
  if (by0 + bh < H && rnd() < 0.7) gates.push([2 * ri(1, bw - 1) + 1, Y1]);
  for (const [gx, gy] of gates) mark(gx, gy, 'gate');
  /* COVER: short low walls on the yard's inner wall lines, in front of
     the gates and scattered across the yard */
  const coverAt = [];
  for (let k = 0; k < ri(4, 8); k++) {
    const vertical = rnd() < 0.6;
    if (vertical) {
      const tx = 2 * ri(1, bw - 1), ty = Y0 + 2 * ri(0, bh - 2) + 1;
      const len = ri(1, 2);
      for (let j = 0; j < len; j++) { mark(tx, ty + 2 * j, 'cover'); mark(tx, ty + 2 * j + 1, 'cover'); coverAt.push([tx, ty + 2 * j]); }
    } else {
      const tx = 2 * ri(1, bw - 1) + 1, ty = Y0 + 2 * ri(1, bh - 1);
      mark(tx, ty, 'cover'); coverAt.push([tx, ty]);
    }
  }
  /* but never across a gate's mouth */
  for (const [gx, gy] of gates) for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
    const p = at.get((gx + dx) + ',' + (gy + dy));
    if (p && p[2] === 'cover') p[2] = 'floor';
  }
  /* THE TOWER, at the back of the yard, and the steps up to it */
  const towerY = Y0 + 2 * ri(1, bh - 2) + 1;
  const towerX = 1;
  mark(towerX, towerY, 'step:' + TOWER_H);
  const stairs = [];
  for (let k = 1, h = TOWER_H - STEP; h > 0; k++, h -= STEP) {
    mark(towerX + k, towerY, 'step:' + h);
    stairs.push([towerX + k, towerY, h]);
  }
  /* and nothing either side of the stair is cover, so it can be climbed */
  for (const [sx, sy] of stairs) for (const dy of [-1, 1]) {
    const p = at.get(sx + ',' + (sy + dy));
    if (p && p[2] === 'cover') p[2] = 'floor';
  }

  const team = (tA, tB, kA, kB) => { setT(tA[0], tA[1], kA); setT(tB[0], tB[1], kB); };
  const mirror = (tx, ty) => [TX - 1 - tx, TY - 1 - ty];
  for (const [tx, ty, what] of plan) {
    const B = mirror(tx, ty);
    if (what === 'floor') team([tx, ty], B, baseFloorA, baseFloorB);
    else if (what === 'fort') team([tx, ty], B, fortA, fortB);
    else if (what === 'cover') team([tx, ty], B, coverA, coverB);
    else if (what === 'gate') team([tx, ty], B, baseFloorA, baseFloorB);
    else if (what.startsWith('step:')) { const h = +what.slice(5); team([tx, ty], B, stepK('A', h), stepK('B', h)); }
  }
  /* a gate must open onto something: the cell outside it is cleared */
  for (const [gx, gy] of gates) {
    const out = gx === X1 ? [gx + 1, gy] : gy === Y0 ? [gx, gy - 1] : [gx, gy + 1];
    for (const [tx, ty] of [out, mirror(...out)]) {
      if (!walkable.has(T(tx, ty))) setT(tx, ty, zoneAt(Math.min(W - 1, (tx - 1) >> 1)).path);
    }
  }
  const stepKinds = new Set(KINDS.map((k, i) => (k.name.startsWith('step:') ? i : -1)).filter(i => i >= 0));
  for (const k of stepKinds) walkable.add(k);

  /* ---- EVERYWHERE REACHABLE: knock through until one flood fills it --- */
  const hedgeKinds = new Set(zones.map(z => z.hedge));
  const passable = k => walkable.has(k) || k === coverA || k === coverB;
  const [ax, ay] = cellT(1, by0 + 1);
  let knocked = 0;
  for (let round = 0; round < 400; round++) {
    const seen = new Uint8Array(TX * TY);
    const q = [ay * TX + ax];
    seen[q[0]] = 1;
    while (q.length) {
      const i = q.pop(), x = i % TX, y = (i / TX) | 0;
      for (const [dx, dy] of DIRS) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= TX || ny >= TY) continue;
        const j = ny * TX + nx;
        if (seen[j] || !passable(t[j])) continue;
        seen[j] = 1; q.push(j);
      }
    }
    /* every hedge tile between a reached cell and an unreached one is a
       candidate; open a few at random and flood again */
    const cand = [];
    for (let y = 1; y < TY - 1; y++) for (let x = 1; x < TX - 1; x++) {
      const i = y * TX + x;
      if (!hedgeKinds.has(t[i])) continue;
      const pairs = [[i - 1, i + 1], [i - TX, i + TX]];
      for (const [a, b] of pairs) {
        if (passable(t[a]) && passable(t[b]) && seen[a] !== seen[b]) { cand.push(i); break; }
      }
    }
    if (!cand.length) break;
    shuffle(cand);
    for (const i of cand.slice(0, Math.max(1, cand.length >> 3))) {
      const x = i % TX;
      t[i] = zoneAt(Math.min(W - 1, Math.max(0, (x - 1) >> 1))).path;
      knocked++;
    }
  }

  /* ---- THE DOCUMENT ------------------------------------------------- */
  const edge = i => Math.floor(i / 2) * (WALL + CELL) + (i % 2 ? WALL : 0);
  const d = {
    format: DOC_FORMAT, version: DOC_VERSION, name: JESSE_NAME,
    vertices: [], sectors: [], lines: {}, linedefs: [], things: [], textures: [], props: [], scatters: [],
    world: { ...defaultWorld(), skybox: 'BSKY2', ambient: { color: '#ffffff', amount: 0.3 }, lightColor: '#fff6ea', jesseSeed: seed >>> 0 },
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
  const runs = [];
  for (let ty = 0; ty < TY; ty++) {
    let tx = 0;
    while (tx < TX) {
      const k = T(tx, ty);
      let e = tx;
      while (e + 1 < TX && T(e + 1, ty) === k) e++;
      runs.push({ k, x0: tx, x1: e, y0: ty, y1: ty });
      tx = e + 1;
    }
  }
  const byRow = new Map();
  const rects = [];
  const row = y => byRow.get(y) || byRow.set(y, []).get(y);
  for (const r of runs) {
    const above = (byRow.get(r.y0 - 1) || []).find(q => q.k === r.k && q.x0 === r.x0 && q.x1 === r.x1);
    if (above) { above.y1 = r.y0; row(r.y0).push(above); }
    else { rects.push(r); row(r.y0).push(r); }
  }
  for (const r of rects) {
    const X0r = r.x0, X1r = r.x1 + 1, Y0r = r.y0, Y1r = r.y1 + 1;
    const ring = [];
    for (let i = X0r; i < X1r; i++) ring.push([edge(i), edge(Y0r)]);
    for (let j = Y0r; j < Y1r; j++) ring.push([edge(X1r), edge(j)]);
    for (let i = X1r; i > X0r; i--) ring.push([edge(i), edge(Y1r)]);
    for (let j = Y1r; j > Y0r; j--) ring.push([edge(X0r), edge(j)]);
    const { name, ...props } = KINDS[r.k];
    d.sectors.push({ ...SECTOR_DEFAULTS, light: 1, outdoor: true, ceilTex: 'SKY', ceil: SKY_H + 64, ...props, id: id(), verts: ring.map(([x, y]) => v(x, y)) });
  }

  /* ---- THINGS -------------------------------------------------------- */
  const mid = i => edge(i) + (i % 2 ? CELL : WALL) / 2;
  const thing = (type, x, y, extra = {}) => d.things.push({ id: id(), type, x: Math.round(x), y: Math.round(y), angle: rnd() * Math.PI * 2, ...extra });
  const bothBases = (fn) => { fn(false); fn(true); };
  const size = [edge(TX), edge(TY)];
  const place = (tx, ty, flip, dx = 0, dy = 0) => {
    const [x, y] = flip ? mirror(tx, ty) : [tx, ty];
    return [mid(x) + (flip ? -dx : dx), mid(y) + (flip ? -dy : dy)];
  };
  const spawns = [[], []];
  bothBases(flip => {
    const teamIx = flip ? 1 : 0;
    /* spawn pads down the back of the yard */
    for (let yy = 0; yy < bh; yy++) {
      const [x, y] = place(5, 2 * (by0 + yy) + 1, flip);   // clear of the tower's stair
      spawns[teamIx].push([Math.round(x), Math.round(y)]);
    }
    /* lamps in the yard's corners */
    for (const [tx, ty] of [[1, Y0 + 1], [X1 - 1, Y0 + 1], [1, Y1 - 1], [X1 - 1, Y1 - 1]]) {
      const [x, y] = place(tx, ty, flip, 0, 0);
      thing('STREETLAMP', x, y);
    }
    /* THE STOCK TO FORTIFY WITH: crates by every gate, fuel cans at
       the back */
    for (const [gx, gy] of gates) {
      const inX = gx === X1 ? gx - 1 : gx, inY = gy === Y0 ? gy + 1 : gy === Y1 ? gy - 1 : gy;
      for (let k = 0; k < 2; k++) {
        const [x, y] = place(inX, inY, flip, (rnd() - 0.5) * 120, (rnd() - 0.5) * 120);
        thing('CRATE', x, y);
      }
    }
    for (let k = 0; k < 2; k++) {
      const [x, y] = place(5, 2 * (by0 + ri(0, bh - 1)) + 1, flip, (rnd() - 0.5) * 100, (rnd() - 0.5) * 100);
      thing('FUELCAN', x, y);
    }
  });
  /* the single-player start: team A's first pad, facing the maze */
  const [sx0, sy0] = spawns[0][Math.min(spawns[0].length - 1, 1)];
  thing('START', sx0, sy0, { angle: 0 });
  /* a lamp and some stock in every room */
  for (const r of rooms) {
    const [x0, y0] = [edge(2 * r.x + 1), edge(2 * r.y + 1)];
    thing('STREETLAMP', x0 + 48, y0 + 48);
    if (rnd() < 0.5) thing('CRATE', x0 + CELL * 0.5 + rnd() * 100, y0 + CELL * 0.5 + rnd() * 100);
    if (rnd() < 0.3) thing('FUELCAN', x0 + CELL * 0.3 + rnd() * 80, y0 + CELL * 0.7);
  }

  d.world.pvp = {
    teams: [
      { name: 'A', spawns: spawns[0], gates: gates.map(([x, y]) => [mid(x), mid(y)]) },
      { name: 'B', spawns: spawns[1], gates: gates.map(([x, y]) => mirror(x, y)).map(([x, y]) => [mid(x), mid(y)]) },
    ],
  };
  /* what it is, for the picture and the test */
  d.jesse = {
    seed: seed >>> 0, W, H, TX, TY, symmetric, knocked, size,
    zones: zones.map(z => ({ xa: z.xa, xb: z.xb, algo: z.algo, braid: z.braid, hedge: KINDS[z.hedge].name, path: KINDS[z.path].name })),
    rooms, base: { bw, bh, by0, gates: gates.length, tower: [towerX, towerY] },
    tiles: t, kinds: KINDS.map(k => k.name),
  };
  return d;
}
