/* =====================================================================
   MEWD — THE SPRAWL, the game's own world
   =====================================================================

   At the user's request: a sprawling level made of ALL THE ASSETS THE
   USER HAS GIVEN, AND NONE THAT WERE GENERATED. It is an editor document
   (js/editor/doc.js), built here in code, so the game plays it (MEWD at
   the terminal, or ?demo; see playedMap in js/main.js) and MEWD Editor
   opens it (File > Open demo: THE SPRAWL) to be taken apart and changed.

   WHAT IS THE USER'S, and so what is in it:

     the texture pack    every group of it — the concrete, the nature
                         set, the ops room and its animated panels and
                         doors, the cube farm, the mansion, the street
                         and the car park, the water and the waterfall,
                         the test patterns and the debug set, the
                         backdrops, the odd ones out (js/texpack.js)
     a skybox            BSKY2, the pack's low sun
     the plants          the wood's firs, bushes, ferns and grass (the
                         golf project's sprites) and the six photographed
                         street trees (assets/forest), and the vandre
                         project's biome plants, in beds of its grounds
                         down the meadow's west edge
     the photographs     the headstones, the cemetery iron (RAILING) and
                         the cobra-head street lamp
     the people          the shoppers and townsfolk (the galvarius
                         crowd, assets/people)

   WHAT IS NOT: every texture js/textures.js paints for itself (GRIDWALL,
   the brick, the drawn hedge), and the drawn things — the trolley, the
   bollard, the crate, the fuel can and the ceiling lamp. The smoke test
   holds the document to that (see THE SPRAWL there).

   THE LAYOUT. Sixteen blocks, four by four, 3200 units a side, with
   roads 768 wide between them and round them — a little over half a
   kilometre across at 32 units to the metre — on a floor sunk 686 units
   into a grass plateau. The plateau's inner face is the pack's tall
   lawn-topped cliff (LWNCLIF1/2, 686 tall, so it fits exactly), and on
   the plateau, against the open sky (the plateau has no outer wall at
   all: wallTex NONE), stand the pack's painted horizons — a tree line,
   a meadow, mountains with clouds over them. Each block is a district,
   and each district is one part of the pack (the table at the bottom of
   this file). The start is the crossroads in the middle.

   WHERE EVERY TEXTURE GOES IS DECIDED BY WHAT IT IS, at its own size:
   the pack is drawn at 2 pixels to the unit (js/texpack.js), so a
   256-pixel panel is 128 units, and the walls, doors, screens and
   consoles here are cut to those sizes so a panel is a panel and not a
   quarter of one. A door is 64 by 128 units (DR1, EYEDOOR) in a jamb of
   its own height; a monitor and a keyboard are 256 by 128 — wall
   screens and console decks, not desk things; the cubicle panel
   (OFCCUB01) is 256 tall, and the cube farm's walls are that tall; the
   mansion's panelling (MANINT1) is 512 tall in two rows, and its walls
   are one row. The coloured checkers (XTX_5..8) and the TEST and DEBUG
   sets are test cards, and they live in the test chamber and nowhere
   else. Every building wears a facade outside and its own walls inside,
   by the line's two sides.

   Every sector is a ring of points, anticlockwise, and every one sits
   strictly inside its parent — a hole in it, which the compiler deals
   with — so no two share a partial edge.
   ===================================================================== */

import { SECTOR_DEFAULTS, DOC_FORMAT, DOC_VERSION, defaultWorld, lineKey } from '../editor/doc.js';

export const SPRAWL_NAME = 'THE SPRAWL';
/** the blocks, the roads between them, and the grass rim above the cliffs */
const BLOCK = 3200, ROAD = 768, RIM = 512;
/** the cliff: the height of one LWNCLIF face, so it fits exactly */
export const CLIFF_H = 686;
const blockAt = i => RIM + ROAD + i * (BLOCK + ROAD);
/** the map, edge to edge */
export const SPRAWL_SIZE = 2 * RIM + 5 * ROAD + 4 * BLOCK;
/** the crossroads in the middle, where the start stands */
export const SPRAWL_START = [blockAt(2) - ROAD / 2, blockAt(2) - ROAD / 2];
/** the kerb: how far a pavement stands over the road */
const CURB = 8;
/** a door of the pack: 64 wide, 128 tall, in a jamb this deep */
const DOOR_W = 64, DOOR_H = 128, JAMB = 16;

/** Build THE SPRAWL. Pure, and the same every time. */
export function sprawlDoc() {
  const S = SPRAWL_SIZE;
  const d = {
    format: DOC_FORMAT, version: DOC_VERSION, name: SPRAWL_NAME,
    vertices: [], sectors: [], lines: {}, things: [], textures: [], props: [], scatters: [],
    world: {
      ...defaultWorld(), skybox: 'BSKY2',
      /* a warm low sun: the light a little gold, and a faint haze of the
         same over everything, which the earth box likes */
      lightColor: '#fff0dc',
      ambient: { color: '#302418', amount: 0.25 },
      fog: { color: '#b8a488', density: 2 },
      fogAmbient: 0.5,
    },
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
  let seed = 20260926 >>> 0;
  const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
  const pick = a => a[(rnd() * a.length) | 0];

  /* ---- the pieces -------------------------------------------------- */
  const sector = (pts, props) => {
    let a = 0;
    for (let i = 0; i < pts.length; i++) { const p = pts[i], q = pts[(i + 1) % pts.length]; a += p[0] * q[1] - q[0] * p[1]; }
    if (a < 0) pts = [...pts].reverse();
    /* no sector falls back to the editor's own GRIDWALL: an edge with no
       wall of its own wears its step's texture, or the pack's kerb */
    const own = { wallTex: props.lowerTex || 'CONC_2', upperTex: null, lowerTex: props.wallTex || 'CONC_2' };
    const s = { ...SECTOR_DEFAULTS, ...own, ...props, id: id(), verts: pts.map(([x, y]) => v(x, y)) };
    d.sectors.push(s);
    return s;
  };
  const rect = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
  const octagon = (cx, cy, r, n = 8, turn = Math.PI / n) =>
    Array.from({ length: n }, (_, k) => [Math.round(cx + r * Math.cos(k * 2 * Math.PI / n + turn)), Math.round(cy + r * Math.sin(k * 2 * Math.PI / n + turn))]);
  const line = (p, q, o) => { const k = lineKey(v(p[0], p[1]), v(q[0], q[1])); d.lines[k] = { ...(d.lines[k] || {}), ...o }; };
  const edges = pts => pts.map((p, i) => [p, pts[(i + 1) % pts.length]]);
  const thing = (type, x, y, extra = {}) => d.things.push({ id: id(), type, x: Math.round(x), y: Math.round(y), angle: 0, ...extra });
  const plant = (kind, x, y, scale = 1) => thing('PLANT', x, y, { kind, scale });
  const prop = (x0, y0, x1, y1, z0, z1, tex, topTex = tex) =>
    d.props.push({ id: id(), x0: Math.round(x0), y0: Math.round(y0), x1: Math.round(x1), y1: Math.round(y1), z0, z1, tex, topTex });
  const scatter = (area, items, density, spacing, clump = 0.3, extra = {}) =>
    d.scatters.push({ id: id(), name: extra.name || 'spread', area, items, density, spacing, clump, seed: (rnd() * 1e6) | 0,
                      scaleMin: extra.scaleMin ?? 1, scaleMax: extra.scaleMax ?? 1 });
  const inRect = (x0, y0, x1, y1) => ({ kind: 'rect', x0, y0, x1, y1 });
  const inSectors = (...ss) => ({ kind: 'sectors', ids: ss.map(s => s.id) });

  /* A BUILDING: a room under a roof, with a FACADE outside and its own
     walls inside (the two faces of each line), and DOORWAYS — each a
     notch in the footprint holding a jamb sector of the door's own
     height, the door standing in its outer line. A doorway with no
     texture is an open arch.
       doors  [{ side: 's'|'e'|'n'|'w', at, w, tex }]
       props  the room's; facade and roofTex say what it wears outside */
  const building = (x0, y0, x1, y1, props, doors = [], outside) => {
    const f = props.floor ?? CURB;
    const { facade = 'CONC_1', roofTex = 'CONC_3', doorH = DOOR_H } = props;
    const room = { outdoor: false, roofTex, upperTex: props.wallTex, ...props };
    delete room.facade;
    const on = side => doors.filter(g => g.side === side);
    const pts = [], jambs = [];
    /* along each side, notching in at each door */
    const run = (from, to, side, horiz, inward) => {
      pts.push(from);
      const ds = on(side).map(g => ({ ...g, lo: g.at - (g.w ?? DOOR_W) / 2, hi: g.at + (g.w ?? DOOR_W) / 2 }));
      const forward = horiz ? to[0] > from[0] : to[1] > from[1];
      ds.sort((p, q) => (forward ? p.lo - q.lo : q.lo - p.lo));
      for (const g of ds) {
        const [a, b] = forward ? [g.lo, g.hi] : [g.hi, g.lo];
        const P = horiz ? [a, from[1]] : [from[0], a], Q = horiz ? [b, from[1]] : [from[0], b];
        const Pi = horiz ? [a, from[1] + inward] : [from[0] + inward, a], Qi = horiz ? [b, from[1] + inward] : [from[0] + inward, b];
        pts.push(P, Pi, Qi, Q);
        jambs.push({ g, outer: [P, Q], ring: [P, Pi, Qi, Q] });
      }
    };
    run([x0, y0], [x1, y0], 's', true, JAMB);
    run([x1, y0], [x1, y1], 'e', false, -JAMB);
    run([x1, y1], [x0, y1], 'n', true, -JAMB);
    run([x0, y1], [x0, y0], 'w', false, JAMB);
    const s = sector(pts, room);
    const jambSectors = [];
    for (const j of jambs) {
      const js = sector(j.ring, { outdoor: false, floor: f, ceil: f + (j.g.h ?? doorH), floorTex: props.doorFloor || 'CONC_2', ceilTex: facade,
                                  wallTex: facade, lowerTex: facade, upperTex: facade, roofTex, light: props.light });
      line(j.outer[0], j.outer[1], j.g.tex ? { opening: true, midTex: j.g.tex, blocking: true } : { opening: true });
      /* a room open to the sky (a courtyard, a light well) meets its
         jambs as outside meets inside: those edges are openings too */
      if (room.outdoor) for (let e = 0; e < 3; e++) line(j.ring[e], j.ring[e + 1], { opening: true });
      /* THE LINTEL over the door: the wall above it, as a block of the
         facade from the door's head to the roof. Without it the notch
         over every door is a hole — the engine draws no wall band that
         rises towards the open sky, which is what keeps a room's upper
         wall from towering to the clouds, and is wrong only here */
      const head = f + (j.g.h ?? doorH), roofZ = room.outdoor ? head : (props.ceil ?? f + 256);
      if (roofZ > head) {
        const xs = j.ring.map(q => q[0]), ys = j.ring.map(q => q[1]);
        prop(Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys), head, roofZ, facade, roofTex);
      }
      jambSectors.push(js);
    }
    /* the facade: every outer edge that is not a doorway, its outside
       face the facade and its inside face the room's own wall */
    const doorKeys = new Set(jambs.map(j => lineKey(v(j.outer[0][0], j.outer[0][1]), v(j.outer[1][0], j.outer[1][1]))));
    for (const [p, q] of edges(pts)) {
      const k = lineKey(v(p[0], p[1]), v(q[0], q[1]));
      if (doorKeys.has(k)) continue;
      const inNotch = jambs.some(j => j.ring.some(r => r[0] === p[0] && r[1] === p[1]) && j.ring.some(r => r[0] === q[0] && r[1] === q[1]) &&
        !(j.outer.some(r => r[0] === p[0] && r[1] === p[1]) && j.outer.some(r => r[0] === q[0] && r[1] === q[1])));
      if (inNotch) continue;
      const sides = { [s.id]: { midTex: room.wallTex } };
      if (outside) sides[outside.id] = { midTex: facade };
      line(p, q, { midTex: facade, sides });
    }
    return Object.assign(s, { jambs: jambSectors });
  };
  /* A SIGN: a picture standing in the long edge of a slot of ground,
     masked, so the sky shows round it — the backdrops, the badge */
  const sign = (x0, y0, x1, y1, tex, floor, face = 's', props = {}) => {
    const s = sector(rect(x0, y0, x1, y1), { floor, ceil: floor + 1024, floorTex: 'CONC_2', wallTex: 'CONC_2', lowerTex: 'CONC_2', light: 0.8, ...props });
    const E = { s: [[x0, y0], [x1, y0]], n: [[x1, y1], [x0, y1]], w: [[x0, y1], [x0, y0]], e: [[x1, y0], [x1, y1]] }[face];
    line(E[0], E[1], { midTex: tex, blocking: true });
    return s;
  };
  /* A WALL PANEL: a picture of the pack hung flat on a wall as a thin
     box, one panel to a box, at the picture's own size */
  const panel = (x, y, w, z0, h, tex, along = 'x', thick = 12) =>
    along === 'x' ? prop(x, y, x + w, y + thick, z0, z0 + h, tex, tex) : prop(x, y, x + thick, y + w, z0, z0 + h, tex, tex);
  const FIRS = ['fir_tall_1', 'fir_tall_2', 'fir_medium', 'fir_young'];
  const STREET = ['street_round', 'street_broad', 'street_oval', 'street_upright', 'street_dense', 'street_big'];

  /* ---- THE PLATEAU, THE CLIFF AND THE HORIZON ------------------------ */
  /* the grass above the cliffs, with no wall of its own round the
     outside: the sky is what is past it */
  const plateau = sector(rect(0, 0, S, S), {
    name: 'the plateau', floor: CLIFF_H, ceil: CLIFF_H + 1024, floorTex: 'GRASS5', wallTex: 'NONE', lowerTex: 'LWNCLIF1', light: 0.84,
  });
  /* the floor of the world, 686 down: the roads. Its edges are ONE rock
     face all the way round, the pack's big cliff (CLIFF2, 1024 across
     and 1024 tall, hung from the top so its grass lip meets the plateau)
     — one line a side, so there is no seam anywhere along it. The roads
     are lit brighter than the blocks: ASPHALT1 is a dark picture */
  const ground = sector(rect(RIM, RIM, S - RIM, S - RIM), {
    name: 'the roads', floor: 0, ceil: CLIFF_H, floorTex: 'ASPHALT1', wallTex: 'CLIFF2', lowerTex: 'CLIFF2', upperTex: 'NONE', light: 1.0,
  });
  /* a verge of earth and grass where the cliff meets the road, as four
     strips clear of the cliff by a unit so they do not touch it */
  const VG = 160;
  for (const [a0, b0, a1, b1] of [[RIM + 1, RIM + 1, S - RIM - 1, RIM + VG], [RIM + 1, S - RIM - VG, S - RIM - 1, S - RIM - 1],
                                  [RIM + 1, RIM + VG + 1, RIM + VG, S - RIM - VG - 1], [S - RIM - VG, RIM + VG + 1, S - RIM - 1, S - RIM - VG - 1]]) {
    const vg = sector(rect(a0, b0, a1, b1), { name: 'verge', floor: 0, floorTex: 'DIRT_01', lowerTex: 'DIRT_02', light: 0.9 });
    scatter(inSectors(vg), [{ type: 'PLANT:grass', w: 5 }, { type: 'PLANT:fern', w: 3 }, { type: 'PLANT:bush_small_1', w: 1 }], 30, 40, 0.6, { name: 'verge grass' });
  }

  /* THE HORIZON, on the plateau: what stands nearer the edge is seen
     over it from the streets, and what stands back is seen over what is
     in front. Trees and the meadow (512 tall) at the edge; mountains
     (256 tall) behind, with clouds (128 tall) on a raised strip over
     them whose face is not drawn (lowerTex NONE), so they float. */
  const third = (S - 2 * RIM) / 3;
  const horizon = (side, k, near, far, cloud) => {
    /* butted end to end, so there is no slit of sky between them; the
       north and south rows run on past the corners to close them */
    const ns = side === 'n' || side === 's';
    const a = RIM + k * third - (ns && k === 0 ? 96 : 0), b = RIM + (k + 1) * third + (ns && k === 2 ? 96 : 0);
    const at = (off, w, tex, face, floor = CLIFF_H, props = {}) => {
      const P = { name: 'horizon', floorTex: 'GRASS5', wallTex: 'GRASS5', lowerTex: 'NONE', light: 0.84, ...props };
      if (side === 'n') return sign(a, S - RIM + off, b, S - RIM + off + w, tex, floor, 's', P);
      if (side === 's') return sign(a, RIM - off - w, b, RIM - off, tex, floor, 'n', P);
      if (side === 'e') return sign(S - RIM + off, a, S - RIM + off + w, b, tex, floor, 'w', P);
      return sign(RIM - off - w, a, RIM - off, b, tex, floor, 'e', P);
    };
    if (near) at(48, 24, near, side);
    /* the far layers only behind a SHORT near one (the 128-tall tree
       line and ruins): behind a 512-tall one they are never seen. The
       clouds float high and are fully lit, so the sky behind them does
       not turn them into dark hills */
    if (far) at(200, 24, far, side);
    /* (the pack's two cloud strips were here, floating over the
       mountains, and against the sky they read as dark hills however
       they were lit; they hang in the test chamber instead) */
    void cloud;
  };
  horizon('n', 0, 'TREEBACK', null, null);  horizon('n', 1, 'TREELINE', 'MOUNTBG', 'CLOUDS02'); horizon('n', 2, 'MEADOWBG', null, null);
  horizon('s', 0, 'TREELINE', 'MOUNTBG', 'CLOUDS01'); horizon('s', 1, 'RUINLINE', 'MNTN0001', 'CLOUDS02'); horizon('s', 2, 'TREELINE', 'MOUNTBG', 'CLOUDS01');
  horizon('e', 0, 'MEADOWBG', null, null);  horizon('e', 1, 'TREEBACK', null, null); horizon('e', 2, 'TREELINE', 'MNTN0001', 'CLOUDS01');
  horizon('w', 0, 'TREEBACK', null, null);  horizon('w', 1, 'TREELINE', 'MOUNTBG', 'CLOUDS02'); horizon('w', 2, 'MEADOWBG', null, null);
  /* and firs along the plateau's edge, seen against the sky */
  for (let t = RIM + 256; t < S - RIM - 256; t += 640) {
    for (const [x, y] of [[t, RIM - 96], [t, S - RIM + 96], [RIM - 96, t], [S - RIM + 96, t]]) plant(pick(FIRS), x + (rnd() - 0.5) * 120, y + (rnd() - 0.5) * 60, 1 + rnd() * 0.3);
  }

  /* ---- THE BLOCKS: a pavement each, lamps and street trees round it -- */
  const blocks = [];
  for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
    const x0 = blockAt(i), y0 = blockAt(j), x1 = x0 + BLOCK, y1 = y0 + BLOCK;
    const walk = sector(rect(x0, y0, x1, y1), {
      name: `pavement ${i},${j}`, floor: CURB, ceil: CLIFF_H, floorTex: 'SIDEWLK1', wallTex: 'CONC_2', lowerTex: 'CONC_2', light: 0.8,
    });
    blocks.push({ i, j, x0, y0, x1, y1, walk, ix0: x0 + 192, iy0: y0 + 192, ix1: x1 - 192, iy1: y1 - 192 });
    const step = 800;
    for (let t = step / 2; t < BLOCK; t += step) {
      thing('STREETLAMP', x0 + t, y0 + 48, { angle: -Math.PI / 2 });
      thing('STREETLAMP', x0 + t, y1 - 48, { angle: Math.PI / 2 });
      thing('STREETLAMP', x0 + 48, y0 + t, { angle: Math.PI });
      thing('STREETLAMP', x1 - 48, y0 + t, { angle: 0 });
      /* no tree at a side's middle: that is where the crossing and the
         district's way in are, and a tree stood square in every one */
      if (t + step / 2 < BLOCK && Math.abs(t + step / 2 - BLOCK / 2) > 200) {
        plant(pick(STREET), x0 + t + step / 2, y0 + 96);
        plant(pick(STREET), x0 + t + step / 2, y1 - 96);
        plant(pick(STREET), x0 + 96, y0 + t + step / 2);
        plant(pick(STREET), x1 - 96, y0 + t + step / 2);
      }
    }
  }
  const B = (i, j) => blocks[j * 4 + i];
  /* THE ROAD MARKINGS: a dashed centre line down every road, of the
     pale paving, stopping short of each junction and each crossing; and
     a hatched box junction where you start */
  const roadMid = k => (k === 0 ? RIM + ROAD / 2 : blockAt(k - 1) + BLOCK + ROAD / 2);
  for (let k = 0; k <= 4; k++) {
    const c = roadMid(k);
    for (let m = 0; m < 4; m++) {
      const lo = blockAt(m), hi = lo + BLOCK;
      for (let t = lo + 160; t + 192 < hi - 160; t += 448) {
        if (Math.abs(t + 96 - (lo + BLOCK / 2)) < 256) continue;
        sector(rect(c - 16, t, c + 16, t + 192), { name: 'road line', floor: 0, floorTex: 'OFCCEIL1', lowerTex: 'CONC_2', light: 1.1 });
        sector(rect(t, c - 16, t + 192, c + 16), { name: 'road line', floor: 0, floorTex: 'OFCCEIL1', lowerTex: 'CONC_2', light: 1.1 });
      }
    }
  }
  sector(rect(SPRAWL_START[0] - 256, SPRAWL_START[1] - 256, SPRAWL_START[0] + 256, SPRAWL_START[1] + 256), { name: 'box junction', floor: 0, floorTex: 'PARKLOT3', lowerTex: 'CONC_2', light: 1.0 });
  /* the crossings: a strip of pavement across each road at each block corner */
  for (let k = 0; k <= 4; k++) {
    const r = k === 0 ? RIM : blockAt(k - 1) + BLOCK;
    if (k === 0 || k === 4) continue;
    for (let m = 0; m < 4; m++) {
      const c = blockAt(m) + BLOCK / 2;
      sector(rect(c - 96, r + 16, c + 96, r + ROAD - 16), { name: 'crossing', floor: 0, floorTex: 'SIDEWLK1', lowerTex: 'CONC_2', light: 0.8 });
      sector(rect(r + 16, c - 96, r + ROAD - 16, c + 96), { name: 'crossing', floor: 0, floorTex: 'SIDEWLK1', lowerTex: 'CONC_2', light: 0.8 });
    }
  }

  /* ---- 0,0 THE PARK: a mown lawn, paths, a pond, ivy hedges ---------- */
  {
    const b = B(0, 0);
    const cx = (b.ix0 + b.ix1) / 2, cy = (b.iy0 + b.iy1) / 2;
    const lawn = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'park lawn', floor: CURB, floorTex: 'LAWNTEST', lowerTex: 'DIRT_02', wallTex: 'DIRT_02', light: 0.84 });
    /* the paths, a cross of paving slabs to the pond */
    for (const [px0, py0, px1, py1] of [[b.ix0 + 32, cy - 64, cx - 640, cy + 64], [cx + 640, cy - 64, b.ix1 - 32, cy + 64], [cx - 64, b.iy0 + 32, cx + 64, cy - 640], [cx - 64, cy + 640, cx + 64, b.iy1 - 32]]) {
      sector(rect(px0, py0, px1, py1), { name: 'path', floor: CURB, floorTex: 'XTX_1', lowerTex: 'CONC_2', light: 0.84 });
    }
    /* the pond: a paved ring, a bank, the water sunk in a rock lip */
    sector(octagon(cx, cy, 640), { name: 'pond paving', floor: CURB, floorTex: 'XTX_1', lowerTex: 'CONC_2', light: 0.84 });
    sector(octagon(cx, cy, 520), { name: 'pond bank', floor: CURB - 4, floorTex: 'DIRT_01', lowerTex: 'DIRT_02', wallTex: 'DIRT_02', light: 0.82 });
    sector(octagon(cx, cy, 440), { name: 'pond', floor: -20, floorTex: 'WAT201', lowerTex: 'ROCK_01', wallTex: 'ROCK_01', light: 0.72 });
    /* hedges: raised sectors of ivy, too tall to step onto */
    for (const [hx0, hy0, hx1, hy1] of [[b.ix0 + 256, b.iy0 + 256, b.ix0 + 1088, b.iy0 + 320], [b.ix1 - 1088, b.iy0 + 256, b.ix1 - 256, b.iy0 + 320],
                                        [b.ix0 + 256, b.iy1 - 320, b.ix0 + 1088, b.iy1 - 256], [b.ix1 - 1088, b.iy1 - 320, b.ix1 - 256, b.iy1 - 256],
                                        [b.ix0 + 256, b.iy0 + 320, b.ix0 + 320, b.iy0 + 1088], [b.ix1 - 320, b.iy0 + 320, b.ix1 - 256, b.iy0 + 1088],
                                        [b.ix0 + 256, b.iy1 - 1088, b.ix0 + 320, b.iy1 - 320], [b.ix1 - 320, b.iy1 - 1088, b.ix1 - 256, b.iy1 - 320]]) {
      sector(rect(hx0, hy0, hx1, hy1), { name: 'hedge', floor: CURB + 56, floorTex: 'IVY1', lowerTex: 'IVY1', wallTex: 'IVY1', light: 0.8 });
    }
    scatter(inSectors(lawn), [...STREET.map(k => ({ type: `PLANT:${k}`, w: 2 })), { type: 'PLANT:fir_medium', w: 2 }, { type: 'PLANT:bush_large_1', w: 3 }, { type: 'PLANT:bush_small_2', w: 2 }],
            5, 220, 0.4, { name: 'park trees', scaleMin: 0.85, scaleMax: 1.15 });
    scatter(inSectors(lawn), [{ type: 'TOWNIE', w: 3 }, { type: 'SHOPPER', w: 1 }], 3, 180, 0.2, { name: 'strollers' });
  }

  /* ---- 1,0 THE CAR PARK: bays, an entry lane, a kiosk --------------- */
  {
    const b = B(1, 0);
    const lot = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'car park', floor: CURB, floorTex: 'PARKLOT1', lowerTex: 'CONC_3', wallTex: 'CONC_3', light: 0.8 });
    /* the bays: PARKLOT2's spine runs up the picture, so a row of bays
       runs north-south, two texture widths across; the hatched lane
       between the rows is no-parking */
    for (let c = 0; c < 4; c++) {
      const x = b.ix0 + 320 + c * 640;
      sector(rect(x, b.iy0 + 192, x + 256, b.iy1 - 640), { name: 'bays', floor: CURB, floorTex: 'PARKLOT2', lowerTex: 'CONC_3', light: 0.8 });
    }
    /* one hatched no-parking strip across the top of the rows */
    sector(rect(b.ix0 + 192, b.iy0 + 64, b.ix1 - 192, b.iy0 + 160), { name: 'no parking', floor: CURB, floorTex: 'PARKLOT3', lowerTex: 'CONC_3', light: 0.8 });
    sector(rect(b.ix0 + 128, b.iy1 - 512, b.ix1 - 128, b.iy1 - 480), { name: 'hazard strip', floor: CURB + 4, floorTex: 'CAUTSTR2', lowerTex: 'CAUTSTR2', light: 0.8 });
    /* the kiosk: a roller shutter (DOOR0001) on its lane side, a door round the back */
    const kx0 = b.ix1 - 640, ky0 = b.iy1 - 384, kx1 = b.ix1 - 128, ky1 = b.iy1 - 128;
    building(kx0, ky0, kx1, ky1, { name: 'kiosk', floor: CURB, ceil: CURB + 160, floorTex: 'CONC_5', ceilTex: 'CONC_5', wallTex: 'CONC_2', facade: 'CONC_5', roofTex: 'METALP1', light: 0.7 },
             [{ side: 'n', at: kx0 + 128, tex: 'DR1_01' }], lot);
    panel(kx0 + 128, ky0 - 12, 128, CURB, 128, 'DOOR0001'); panel(kx0 + 256, ky0 - 12, 128, CURB, 128, 'DOOR0001');
    scatter(inSectors(lot), [{ type: 'SHOPPER', w: 3 }, { type: 'TOWNIE', w: 1 }], 5, 150, 0.4, { name: 'shoppers' });
  }

  /* ---- 2,0 THE CUBE FARM: an office of cubicles, panel-walled ------ */
  {
    const b = B(2, 0);
    const x0 = b.ix0 + 128, y0 = b.iy0 + 128, x1 = b.ix1 - 128, y1 = b.iy1 - 128, f = CURB;
    /* the walls are the cubicle panel, and they are its height: 256 */
    const office = building(x0, y0, x1, y1, {
      name: 'cube farm', floor: f, ceil: f + 256, floorTex: 'OFCCARP1', ceilTex: 'OFCCEIL1', wallTex: 'OFCCUB01', facade: 'CONC_5', roofTex: 'CONC_3', light: 0.98, lightColor: '#f4f8ff',
    }, [{ side: 's', at: (x0 + x1) / 2, w: 128, tex: 'EYEDOOR0' }, { side: 'n', at: (x0 + x1) / 2, w: 128, tex: 'EYEDOOR0' }, { side: 'w', at: (y0 + y1) / 2, tex: 'DR1_01' }], b.walk);
    /* windows along the facade, the pack's green glass panel */
    for (let x = x0 + 192; x + 128 < x1 - 128; x += 384) {
      if (Math.abs(x + 64 - (x0 + x1) / 2) < 200) continue;
      panel(x, y0 - 12, 128, f + 96, 128, 'OP_WIND2'); panel(x, y1, 128, f + 96, 128, 'OP_WIND2');
    }
    /* cubicles: partitions of the panel itself, 112 tall so they show
       its grey top and blue band (a box's texture hangs from its top),
       capped in the fabric, a wood desk in each, in pairs down each
       aisle */
    const cw = 256, ch = 224, aisle = 160;
    for (let cxk = x0 + 256; cxk + 2 * cw < x1 - 256; cxk += 2 * cw + aisle) {
      for (let cyk = y0 + 320; cyk + ch < y1 - 320; cyk += ch + 96) {
        if (Math.abs(cyk + ch / 2 - (y0 + y1) / 2) < 160) continue;       // the main aisle
        for (const [px, face] of [[cxk, 1], [cxk + cw, -1]]) {
          prop(px, cyk, px + cw, cyk + 8, f, f + 112, 'OFCCUB01', 'OFCCUB03');
          prop(face > 0 ? px : px + cw - 8, cyk, face > 0 ? px + 8 : px + cw, cyk + ch, f, f + 112, 'OFCCUB01', 'OFCCUB03');
          const dx = px + cw / 2;
          prop(dx - 80, cyk + 16, dx + 80, cyk + 72, f, f + 36, 'OFCCUB03', face > 0 ? 'OFCDESK2' : 'OFCDESK1');
        }
      }
    }
    /* a meeting screen on the end wall, the pack's monitor at its own size */
    panel(x1 - 12 - 256, y1 - 12, 256, f + 64, 128, 'MONITOR');
    panel(x0 + 12, y1 - 12, 256, f + 64, 128, 'TERMPAN1');
    scatter(inSectors(office), [{ type: 'SHOPPER', w: 1 }], 4, 140, 0.1, { name: 'office staff' });
    scatter(inRect(b.ix0 + 16, b.iy0 + 16, b.ix1 - 16, b.iy0 + 112), [{ type: 'PLANT:bush_small_1', w: 1 }, { type: 'PLANT:bush_small_2', w: 1 }], 20, 90, 0.2, { name: 'office planting' });
  }

  /* ---- 3,0 THE PLAZA: paving, a stage, a screen, the badge ---------- */
  {
    const b = B(3, 0);
    const plaza = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'plaza', floor: CURB, floorTex: 'CONC_1', lowerTex: 'CONC_4', wallTex: 'CONC_4', light: 0.84 });
    const cx = (b.ix0 + b.ix1) / 2;
    /* a pattern of inlaid squares down the middle, slab paving round them */
    for (let k = 0; k < 5; k++) {
      const x = b.ix0 + 256 + k * 512;
      sector(rect(x, b.iy0 + 256, x + 320, b.iy0 + 576), { name: 'inlay', floor: CURB, floorTex: k === 2 ? 'DIAG_1' : k % 2 ? 'CONC_5' : 'XTX_1', lowerTex: 'CONC_4', light: 0.84 });
      sector(rect(x, b.iy0 + 832, x + 320, b.iy0 + 1152), { name: 'paving', floor: CURB, floorTex: 'XTX_1', lowerTex: 'CONC_4', light: 0.84 });
    }
    /* the stage: two steps of concrete up, ribbed pillars either side
       of a screen running the pack's test card, a monitor each side */
    const sx0 = cx - 768, sx1 = cx + 768, sy0 = b.iy1 - 1024, sy1 = b.iy1 - 256;
    sector(rect(sx0 - 96, sy0 - 96, sx1 + 96, sy1 + 64), { name: 'stage step', floor: CURB + 20, floorTex: 'CONC_3', lowerTex: 'CAUTSTR2', wallTex: 'CAUTSTR2', light: 0.82 });
    sector(rect(sx0, sy0, sx1, sy1), { name: 'stage', floor: CURB + 40, floorTex: 'XTX_1', lowerTex: 'CONC_4', wallTex: 'CONC_4', light: 0.86 });
    prop(cx - 480, sy1 - 64, cx + 480, sy1 - 16, CURB + 40, CURB + 40 + 384, 'CONC_5', 'CONC_5');
    prop(cx - 423, sy1 - 72, cx + 423, sy1 - 64, CURB + 112, CURB + 112 + 240, 'TESTPA00', 'CONC_5');
    for (const px of [cx - 560, cx + 496]) prop(px, sy1 - 80, px + 64, sy1 - 16, CURB + 40, CURB + 40 + 448, 'CONC_7', 'CONC_3');
    panel(cx - 480 - 256 - 32, sy1 - 28, 256, CURB + 120, 128, 'MONITOR'); panel(cx + 480 + 32, sy1 - 28, 256, CURB + 120, 128, 'MONITOR');
    /* the engine's own badge, on a stand at the front */
    sign(b.ix0 + 192, b.iy0 + 700, b.ix0 + 192 + 625, b.iy0 + 724, 'GZDOOM', CURB, 's', { name: 'badge', floorTex: 'CONC_1' });
    scatter(inSectors(plaza), [{ type: 'TOWNIE', w: 2 }, { type: 'SHOPPER', w: 2 }], 7, 120, 0.5, { name: 'audience' });
  }

  /* ---- 0,1 THE CEMETERY: iron, stones in ranks, mist, a mausoleum --- */
  {
    const b = B(0, 1);
    const gx0 = b.ix0 + 64, gy0 = b.iy0 + 64, gx1 = b.ix1 - 64, gy1 = b.iy1 - 64;
    const gates = [{ side: 's', at: (gx0 + gx1) / 2, w: 192 }, { side: 'e', at: (gy0 + gy1) / 2, w: 192 }];
    /* the yard's ring, with the gates as gaps in the iron */
    const pts = [], gaps = [];
    const runG = (from, to, side, horiz) => {
      pts.push(from);
      const ds = gates.filter(g => g.side === side).map(g => [g.at - g.w / 2, g.at + g.w / 2]);
      const forward = horiz ? to[0] > from[0] : to[1] > from[1];
      for (const [lo, hi] of ds) { const [a2, b2] = forward ? [lo, hi] : [hi, lo]; const P = horiz ? [a2, from[1]] : [from[0], a2], Q = horiz ? [b2, from[1]] : [from[0], b2]; pts.push(P, Q); gaps.push([P, Q]); }
    };
    runG([gx0, gy0], [gx1, gy0], 's', true); runG([gx1, gy0], [gx1, gy1], 'e', false); runG([gx1, gy1], [gx0, gy1], 'n', true); runG([gx0, gy1], [gx0, gy0], 'w', false);
    const yard = sector(pts, { name: 'cemetery', floor: CURB, floorTex: 'MOSS_01', lowerTex: 'DIRT_02', wallTex: 'IVY1', light: 0.62,
                               fog: { color: '#9aa890', density: 18 } });
    const gapKeys = new Set(gaps.map(([p, q]) => lineKey(v(p[0], p[1]), v(q[0], q[1]))));
    for (const [p, q] of edges(pts)) if (!gapKeys.has(lineKey(v(p[0], p[1]), v(q[0], q[1])))) line(p, q, { midTex: 'RAILING', blocking: true });
    /* an earth path from the gate to the mausoleum */
    sector(rect((gx0 + gx1) / 2 - 64, gy0 + 1, (gx0 + gx1) / 2 + 64, gy1 - 900), { name: 'path', floor: CURB, floorTex: 'DIRT_01', lowerTex: 'DIRT_02', light: 0.62, fog: { color: '#9aa890', density: 18 } });
    /* the stones, in ranks, jittered, the plain ones common */
    for (let r = 0; r < 9; r++) for (let c = 0; c < 16; c++) {
      if (rnd() < 0.18) continue;
      const x = gx0 + 256 + c * 150 + (rnd() - 0.5) * 30, y = gy0 + 320 + r * 240 + (rnd() - 0.5) * 20;
      if (Math.abs(x - (gx0 + gx1) / 2) < 140) continue;
      if (x > gx1 - 900 && y > gy1 - 900) continue;
      const vr = rnd() < 0.55 ? 0 : 1 + ((rnd() * 7) | 0);
      thing('GRAVESTONE', x, y, { angle: -Math.PI / 2 + (rnd() - 0.5) * 0.2, variant: vr });
    }
    /* a mausoleum: ribbed concrete, a shut eye door, dark inside */
    const mx0 = gx1 - 800, my0 = gy1 - 800, mx1 = gx1 - 256, my1 = gy1 - 256;
    building(mx0, my0, mx1, my1, { name: 'mausoleum', floor: CURB + 16, ceil: CURB + 16 + 256, floorTex: 'CONC_4', ceilTex: 'CONC_5', wallTex: 'CONC_7', facade: 'CONC_7', roofTex: 'CONC_3', doorFloor: 'CONC_4', light: 0.35 },
             [{ side: 's', at: (mx0 + mx1) / 2, tex: 'EYEDOORC' }], yard);
    sector(rect(mx0 - 64, my0 - 64, mx1 + 64, my0), { name: 'mausoleum step', floor: CURB + 16, floorTex: 'CONC_4', lowerTex: 'CONC_4', light: 0.5, fog: { color: '#9aa890', density: 18 } });
    for (const [x, y] of [[gx0 + 96, gy0 + 96], [gx1 - 96, gy0 + 96], [gx0 + 96, gy1 - 96], [gx1 - 96, gy1 - 96], [gx0 + 96, (gy0 + gy1) / 2], [(gx0 + gx1) / 2 - 300, gy1 - 96], [(gx0 + gx1) / 2 + 300, gy1 - 96]]) plant(pick(FIRS), x, y);
    scatter(inSectors(yard), [{ type: 'TOWNIE', w: 1 }], 0.6, 160, 0.2, { name: 'mourners' });
    scatter(inSectors(yard), [{ type: 'PLANT:grass', w: 3 }, { type: 'PLANT:fern', w: 2 }], 18, 60, 0.7, { name: 'long grass' });
  }

  /* ---- 1,1 THE OPS CENTRE: panels, consoles, a red reactor room ----- */
  {
    const b = B(1, 1);
    const x0 = b.ix0 + 192, y0 = b.iy0 + 192, x1 = b.ix1 - 192, y1 = b.iy1 - 192, f = CURB + 16;
    const apron = sector(rect(b.ix0 + 64, b.iy0 + 64, b.ix1 - 64, b.iy1 - 64), { name: 'ops apron', floor: CURB, floorTex: 'CONC_3', lowerTex: 'CAUTSTR2', wallTex: 'CAUTSTR2', light: 0.8 });
    const ops = building(x0, y0, x1, y1, {
      name: 'ops centre', floor: f, ceil: f + 256, floorTex: 'METALP1', ceilTex: 'OP_BLNK2', wallTex: 'OPBLANK', facade: 'METALP1', roofTex: 'METALP1', doorFloor: 'CAUTSTR2', light: 0.82, lightColor: '#dde8ff',
    }, [{ side: 's', at: (x0 + x1) / 2, w: 128, tex: 'EYEDOOR0' }, { side: 'w', at: (y0 + y1) / 2, tex: 'DR1_01' }, { side: 'e', at: (y0 + y1) / 2, tex: 'EYEDORC0' }], apron);
    /* the walls inside, panel by panel at the panel's own size: the
       animated consoles, the terminals, vents, windows, the silent
       plaque and the blanks, in a band round the room */
    const panels = ['DEVPAN1A', 'TERMPAN1', 'DEVPAN2A', 'OP_VENT2', 'OPSILENT', 'OP_WIND2', 'DEVPAN1A', 'OP_BLNK3', 'DEVPAN2A', 'OP_BLNK2', 'REDLIGHT', 'TERMPAN1'];
    let k = 0;
    for (let x = x0 + 128; x + 128 <= x1 - 128; x += 160) {
      if (Math.abs(x + 64 - (x0 + x1) / 2) < 160) { k++; continue; }
      panel(x, y1 - 24, 128, f + 64, 128, panels[k++ % panels.length]);
      panel(x, y0 + 12, 128, f + 64, 128, panels[(k + 5) % panels.length]);
    }
    for (let y = y0 + 256; y + 128 <= y1 - 256; y += 160) {
      if (Math.abs(y + 64 - (y0 + y1) / 2) < 160) continue;
      panel(x1 - 24, y, 128, f + 64, 128, panels[k++ % panels.length], 'y');
      panel(x0 + 12, y, 128, f + 64, 128, panels[(k + 3) % panels.length], 'y');
    }
    /* the consoles: decks the size of the pack's keyboard, a monitor
       standing behind each, in rows either side of the room */
    for (let r = 0; r < 3; r++) {
      const y = y0 + 480 + r * 448;
      for (const a of [x0 + 384, x1 - 384 - 768]) {
        for (let m = 0; m < 3; m++) {
          const mx = a + m * 272;
          prop(mx, y, mx + 256, y + 128, f, f + 40, 'OPBLANK', 'KEYBOARD');
          prop(mx, y + 128, mx + 256, y + 144, f + 40, f + 168, 'MONITOR', 'OP_BLNK3');
        }
      }
    }
    /* THE REACTOR ROOM in the middle: sunk a step, under a higher
       ceiling with the glowing beam round its top, lit red and hazed,
       the animated core in it and eye pylons at its corners */
    const rx0 = (x0 + x1) / 2 - 320, rx1 = (x0 + x1) / 2 + 320, ry0 = (y0 + y1) / 2 + 160, ry1 = ry0 + 640;
    sector(rect(rx0, ry0, rx1, ry1), { name: 'reactor', outdoor: false, floor: f - 16, ceil: f + 384, floorTex: 'CAUTSTR2', ceilTex: 'OP_BLNK3', wallTex: 'OPBLANK', upperTex: 'REACTB00', lowerTex: 'CAUTSTR2',
                                        light: 0.7, lightColor: '#ff5a3c', fog: { color: '#601810', density: 30 } });
    const rc = [(rx0 + rx1) / 2, (ry0 + ry1) / 2];
    prop(rc[0] - 96, rc[1] - 96, rc[0] + 96, rc[1] + 96, f - 16, f + 384, 'REACTB00', 'REDLIGHT');
    for (const [ex, ey] of [[rx0 + 16, ry0 + 16], [rx1 - 80, ry0 + 16], [rx0 + 16, ry1 - 80], [rx1 - 80, ry1 - 80]]) {
      prop(ex, ey, ex + 64, ey + 64, f - 16, f + 112, 'EYEDORC0', 'REDLIGHT');
    }
    scatter(inSectors(ops), [{ type: 'SHOPPER', w: 1 }], 2, 200, 0.1, { name: 'operators' });
  }

  /* ---- 2,1 THE MANSION, round a courtyard --------------------------- */
  {
    const b = B(2, 1);
    const x0 = b.ix0 + 256, y0 = b.iy0 + 256, x1 = b.ix1 - 256, y1 = b.iy1 - 256, f = CURB + 24;
    sector(rect(b.ix0 + 64, b.iy0 + 64, b.ix1 - 64, b.iy1 - 64), { name: 'mansion lawn', floor: CURB, floorTex: 'LAWN2', lowerTex: 'CONC_5', wallTex: 'CONC_5', light: 0.84 });
    const terrace = sector(rect(x0 - 96, y0 - 96, x1 + 96, y1 + 96), { name: 'mansion terrace', floor: CURB + 16, floorTex: 'XTX_1', lowerTex: 'CONC_5', wallTex: 'CONC_5', light: 0.82 });
    /* the walls are one row of the pack's panelling: 256 tall */
    const house = building(x0, y0, x1, y1, {
      name: 'mansion', floor: f, ceil: f + 256, floorTex: 'OFCCARP1', ceilTex: 'MANINT1', wallTex: 'MANINT1', facade: 'CONC_1', roofTex: 'CONC_3', doorFloor: 'XTX_1', light: 0.9, lightColor: '#ffd8a8',
    }, [{ side: 's', at: (x0 + x1) / 2, w: 128, tex: 'DR1_01' }, { side: 'e', at: (y0 + y1) / 2, tex: 'DR1_01' }], terrace);
    for (let x = x0 + 160; x + 128 < x1 - 128; x += 320) {
      if (Math.abs(x + 64 - (x0 + x1) / 2) < 200) continue;
      panel(x, y0 - 12, 128, f + 80, 128, 'OP_WIND2'); panel(x, y1, 128, f + 80, 128, 'OP_WIND2');
    }
    /* the courtyard, open to the sky, an arch into it from each wing */
    const cx0 = x0 + 704, cy0 = y0 + 704, cx1 = x1 - 704, cy1 = y1 - 704;
    const court = building(cx0, cy0, cx1, cy1, { name: 'courtyard', outdoor: true, floor: f, ceil: f + 1024, floorTex: 'XTX_1', ceilTex: 'SKY', wallTex: 'CONC_1', facade: 'MANINT1', roofTex: 'CONC_3', doorFloor: 'XTX_1', light: 0.86 },
      [{ side: 's', at: (cx0 + cx1) / 2, w: 128, h: 192 }, { side: 'n', at: (cx0 + cx1) / 2, w: 128, h: 192 }, { side: 'e', at: (cy0 + cy1) / 2, w: 128, h: 192 }, { side: 'w', at: (cy0 + cy1) / 2, w: 128, h: 192 }], house);
    /* a fountain in it */
    const mx = (cx0 + cx1) / 2, my = (cy0 + cy1) / 2;
    sector(octagon(mx, my, 208), { name: 'fountain rim', floor: f + 20, floorTex: 'CONC_5', lowerTex: 'CONC_5', light: 0.86 });
    sector(octagon(mx, my, 160), { name: 'fountain', floor: f + 4, floorTex: 'WAT201', lowerTex: 'CONC_5', light: 0.86 });
    for (const [px, py] of [[cx0 + 128, cy0 + 128], [cx1 - 128, cy0 + 128], [cx0 + 128, cy1 - 128], [cx1 - 128, cy1 - 128]]) plant('bush_large_2', px, py);
    /* the rooms round it: ribbed pillars down the halls */
    for (let x = x0 + 256; x < x1 - 128; x += 384) for (const y of [y0 + 352, y1 - 352]) {
      if (Math.abs(x - (x0 + x1) / 2) < 200) continue;
      prop(x - 24, y - 24, x + 24, y + 24, f, f + 256, 'CONC_7', 'CONC_7');
    }
    scatter(inSectors(house), [{ type: 'TOWNIE', w: 1 }], 1.2, 220, 0.3, { name: 'guests' });
    scatter(inSectors(court), [{ type: 'PLANT:fern', w: 2 }, { type: 'PLANT:bush_small_1', w: 1 }], 10, 70, 0.6, { name: 'courtyard beds' });
  }

  /* ---- 3,1 THE MARKET SQUARE: stalls, a pavilion, a crowd ----------- */
  {
    const b = B(3, 1);
    const sq = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'market square', floor: CURB, floorTex: 'CONC_2', lowerTex: 'CONC_4', wallTex: 'CONC_4', light: 0.84 });
    const cx = (b.ix0 + b.ix1) / 2, cy = (b.iy0 + b.iy1) / 2;
    /* the stalls: a wood counter, two metal posts, a cloth awning */
    for (let r = 0; r < 4; r++) for (let c = 0; c < 5; c++) {
      if ((r === 1 || r === 2) && (c === 2)) continue;                      // the pavilion
      const x = b.ix0 + 320 + c * 512, y = b.iy0 + 384 + r * 640;
      prop(x, y, x + 256, y + 128, CURB, CURB + 40, 'MANINT1', 'OFCDESK2');
      prop(x, y + 112, x + 16, y + 128, CURB, CURB + 128, 'METALP1', 'METALP1');
      prop(x + 240, y + 112, x + 256, y + 128, CURB, CURB + 128, 'METALP1', 'METALP1');
      prop(x - 16, y + 64, x + 272, y + 144, CURB + 128, CURB + 144, 'OFCCUB03', 'OFCCUB01');
      if (c < 4) plant(pick(STREET), x + 384, y + 64);
    }
    /* a pavilion in the middle: four ribbed pillars and a slab of roof over a paved square */
    sector(rect(cx - 320, cy - 320, cx + 320, cy + 320), { name: 'pavilion floor', floor: CURB + 16, floorTex: 'XTX_1', lowerTex: 'CONC_4', light: 0.84 });
    for (const [px, py] of [[cx - 256, cy - 256], [cx + 208, cy - 256], [cx - 256, cy + 208], [cx + 208, cy + 208]]) prop(px, py, px + 48, py + 48, CURB + 16, CURB + 16 + 240, 'CONC_7', 'CONC_7');
    prop(cx - 300, cy - 300, cx + 300, cy + 300, CURB + 256, CURB + 288, 'CONC_5', 'CONC_3');
    scatter(inSectors(sq), [{ type: 'TOWNIE', w: 3 }, { type: 'SHOPPER', w: 2 }], 10, 110, 0.5, { name: 'market crowd' });
  }

  /* ---- 0,2 THE WOOD: firs, scrub, a dirt track, a green mist ------- */
  {
    const b = B(0, 2);
    const WF = { color: '#6a7a58', density: 22 };
    const wood = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'the wood', floor: CURB, floorTex: 'GRASS1', lowerTex: 'DIRT_02', wallTex: 'DIRT_02', light: 0.64, fog: WF });
    const mid = (b.iy0 + b.iy1) / 2;
    sector(rect(b.ix0 + 64, mid - 80, b.ix1 - 64, mid + 80), { name: 'track', floor: CURB, floorTex: 'DIRT_01', lowerTex: 'DIRT_02', light: 0.72, fog: WF });
    /* a mossy outcrop in a clearing */
    const ox = b.ix0 + 2100, oy = b.iy0 + 2200;
    sector(octagon(ox, oy, 300), { name: 'clearing', floor: CURB, floorTex: 'MOSS_01', lowerTex: 'ROCK_01', light: 0.82, fog: WF });
    sector(octagon(ox, oy, 150, 7), { name: 'outcrop', floor: CURB + 20, floorTex: 'MOSS_01', lowerTex: 'ROCK_01', wallTex: 'ROCK_01', light: 0.9, fog: WF });
    sector(octagon(ox + 20, oy - 10, 80, 5), { name: 'outcrop top', floor: CURB + 40, floorTex: 'MOSS_01', lowerTex: 'ROCK_01', wallTex: 'ROCK_01', light: 0.9, fog: WF });
    scatter(inSectors(wood), [{ type: 'PLANT:fir_tall_1', w: 22 }, { type: 'PLANT:fir_tall_2', w: 22 }, { type: 'PLANT:fir_medium', w: 16 }, { type: 'PLANT:fir_young', w: 14 },
                              { type: 'PLANT:bush_large_1', w: 8 }, { type: 'PLANT:bush_small_1', w: 6 }], 75, 48, 0.4, { name: 'firs', scaleMin: 0.9, scaleMax: 1.25 });
    scatter(inSectors(wood), [{ type: 'PLANT:grass', w: 5 }, { type: 'PLANT:fern', w: 4 }, { type: 'PLANT:bush_small_2', w: 1 }], 50, 30, 0.6, { name: 'undergrowth' });
  }

  /* ---- 1,2 THE QUARRY: an open pit, a crag in two tiers, a waterfall */
  {
    const b = B(1, 2);
    sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'quarry floor', floor: CURB, floorTex: 'DIRT3', lowerTex: 'ROCK_01', wallTex: 'ROCK_01', light: 0.8 });
    /* the pit: eight benches down, 24 each so a person can climb them,
       faced in plain rock (the cliff pictures carry a grass lip at their
       top, which on a 24-high step is all of them you see), the spoil a
       patch of the orange dirt, a pool at the bottom */
    const px0 = b.ix0 + 96, py0 = b.iy0 + 96, px1 = b.ix1 - 96, py1 = b.iy0 + 1500;
    sector(rect(b.ix1 - 520, b.iy0 + 1540, b.ix1 - 120, b.iy0 + 1740), { name: 'spoil', floor: CURB, floorTex: 'DIRT2', lowerTex: 'ROCK_01', light: 0.8 });
    const FLOORS = ['DIRT3', 'DIRT_01', 'ROCK_01', 'DIRT_02', 'ROCK_01', 'DIRT_01', 'ROCK_01', 'DIRT_02'];
    let z = CURB;
    for (let k = 0; k < 8; k++) {
      z -= 24;
      const inset = k * 64;
      sector(rect(px0 + inset, py0 + inset, px1 - inset, py1 - inset), {
        name: `bench ${k + 1}`, floor: z, floorTex: FLOORS[k], lowerTex: 'ROCK_01', wallTex: 'ROCK_01', light: 0.78 - k * 0.02,
      });
    }
    sector(rect(px0 + 8 * 64, py0 + 8 * 64, px1 - 8 * 64, py1 - 8 * 64), { name: 'quarry pool', floor: z - 20, floorTex: 'WAT201', lowerTex: 'ROCK_01', light: 0.62 });
    /* THE CRAG on the north half, in two tiers: a lower one 384 up faced
       in the pack's rock cliff, a notch cut in its front where the fall
       comes down, and a higher one set back, 256 more, over a pool on
       the lower one's top that the fall is fed from — so the water comes
       from somewhere, down the upper face into the pool and over the lip
       into the notch */
    const mx0 = b.ix0 + 96, my0 = b.iy0 + 1800, mx1 = b.ix1 - 96, my1 = b.iy1 - 96;
    const t1 = CURB + 384, t2 = t1 + 256;
    const nx0 = (mx0 + mx1) / 2 - 96, nx1 = (mx0 + mx1) / 2 + 96, ny1 = my0 + 192;
    const lower = [[mx0, my0], [nx0, my0], [nx0, ny1], [nx1, ny1], [nx1, my0], [mx1, my0], [mx1, my1], [mx0, my1]];
    sector(lower, { name: 'crag', floor: t1, floorTex: 'MOSS_01', lowerTex: 'CLIFF2A', wallTex: 'CLIFF2A', light: 0.84 });
    line([nx0, my0], [nx0, ny1], { lowerTex: 'WFALLA1' }); line([nx0, ny1], [nx1, ny1], { lowerTex: 'WFALLA1' }); line([nx1, ny1], [nx1, my0], { lowerTex: 'WFALLA1' });
    /* its sides are the lawn-topped cliff, the lip meeting the moss on
       top; its back, seen from the road to the north, the tall crag */
    line([mx1, my0], [mx1, my1], { lowerTex: 'LWNCLIF2' }); line([mx1, my1], [mx0, my1], { lowerTex: 'CLIFF1' }); line([mx0, my1], [mx0, my0], { lowerTex: 'LWNCLIF1' });
    sector(rect(nx0, my0, nx1, ny1), { name: 'plunge pool', floor: CURB - 16, floorTex: 'WAT201', lowerTex: 'ROCK_01', light: 0.7 });
    /* the upper tier, its front split where the fall comes over it */
    const ux0 = mx0 + 320, uy0 = my0 + 512, ux1 = mx1 - 320, uy1 = my1 - 192;
    sector([[ux0, uy0], [nx0, uy0], [nx1, uy0], [ux1, uy0], [ux1, uy1], [ux0, uy1]],
           { name: 'upper crag', floor: t2, floorTex: 'MOSS_01', lowerTex: 'CLIFF2C', wallTex: 'CLIFF2C', light: 0.86 });
    line([nx0, uy0], [nx1, uy0], { lowerTex: 'WFALLA1' });
    line([ux1, uy0], [ux1, uy1], { lowerTex: 'CLIFF2B' }); line([ux0, uy1], [ux0, uy0], { lowerTex: 'CLIFF2B' });
    /* and the pool on the lower tier between them, to the lip */
    sector(rect(nx0 - 64, ny1 + 32, nx1 + 64, uy0 - 32), { name: 'upper pool', floor: t1 - 12, floorTex: 'WAT201', lowerTex: 'ROCK_01', light: 0.72 });
    scatter(inRect(mx0 + 64, my0 + 64, mx1 - 64, my1 - 64), [{ type: 'PLANT:fir_young', w: 2 }, { type: 'PLANT:fir_medium', w: 1 }, { type: 'PLANT:bush_small_1', w: 2 }, { type: 'PLANT:grass', w: 4 }], 16, 70, 0.5, { name: 'on the crag' });
  }

  /* ---- 2,2 THE BRUTALIST HALL: pillars, a pit, a light well --------- */
  {
    const b = B(2, 2);
    const x0 = b.ix0 + 128, y0 = b.iy0 + 128, x1 = b.ix1 - 128, y1 = b.iy1 - 128, f = CURB;
    const hall = building(x0, y0, x1, y1, {
      name: 'brutalist hall', floor: f, ceil: f + 448, floorTex: 'CONC_4', ceilTex: 'CONC_5', wallTex: 'CONC_4', facade: 'CONC_7', roofTex: 'CONC_3', doorH: 256, doorFloor: 'CONC_4', light: 0.5,
      fog: { color: '#3c3a36', density: 14 },
    }, [{ side: 's', at: (x0 + x1) / 2, w: 256 }, { side: 'n', at: (x0 + x1) / 2, w: 256 }, { side: 'e', at: (y0 + y1) / 2, w: 192 }, { side: 'w', at: (y0 + y1) / 2, w: 192 }], b.walk);
    const mx = (x0 + x1) / 2, my = (y0 + y1) / 2;
    /* the facade's windows: two bands of the green-glass panel, set in
       the rib so the long blank walls have a storey height to them */
    for (const zz of [f + 272, f + 96]) {
      for (let x = x0 + 192; x + 128 < x1 - 128; x += 256) {
        if (Math.abs(x + 64 - mx) < 256) continue;
        panel(x, y0 - 12, 128, zz, 128, 'OP_WIND2'); panel(x, y1, 128, zz, 128, 'OP_WIND2');
      }
      for (let y = y0 + 192; y + 128 < y1 - 128; y += 256) {
        if (Math.abs(y + 64 - my) < 224) continue;
        panel(x0 - 12, y, 128, zz, 128, 'OP_WIND2', 'y'); panel(x1, y, 128, zz, 128, 'OP_WIND2', 'y');
      }
    }
    /* the pillars: sectors shut floor to ceiling, ribbed */
    for (let x = x0 + 384; x < x1 - 256; x += 512) for (let y = y0 + 384; y < y1 - 256; y += 512) {
      if (Math.abs(x - mx) < 320 && Math.abs(y - my) < 320) continue;
      sector(rect(x - 48, y - 48, x + 48, y + 48), { name: 'pillar', outdoor: false, floor: f, ceil: f, floorTex: 'CONC_4', ceilTex: 'CONC_7', wallTex: 'CONC_7', light: 0.5 });
    }
    /* a light well over the middle: a hole in the roof, open to the sky */
    const well = building(mx - 288, my - 288, mx + 288, my + 288, { name: 'light well', outdoor: true, floor: f, ceil: f + 448, floorTex: 'CONC_3', ceilTex: 'SKY', wallTex: 'CONC_4', facade: 'CONC_4', roofTex: 'CONC_3', light: 0.8 },
      [{ side: 's', at: mx, w: 384, h: 384 }, { side: 'n', at: mx, w: 384, h: 384 }, { side: 'e', at: my, w: 384, h: 384 }, { side: 'w', at: my, w: 384, h: 384 }], hall);
    /* and a pit sunk in it */
    sector(rect(mx - 160, my - 160, mx + 160, my + 160), { name: 'pit', outdoor: true, floor: f - 24, ceil: f + 448, floorTex: 'DIAG_2', ceilTex: 'SKY', wallTex: 'CONC_4', lowerTex: 'CAUTSTR2', light: 0.7 });
    scatter(inSectors(hall), [{ type: 'SHOPPER', w: 1 }, { type: 'TOWNIE', w: 1 }], 1.5, 200, 0.3, { name: 'wanderers' });
    void well;
  }

  /* ---- 3,2 THE YARD: pads, a channel, containers, a shed ------------ */
  {
    const b = B(3, 2);
    const yard = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'yard', floor: CURB, floorTex: 'CONC_3', lowerTex: 'CONC_4', wallTex: 'CONC_4', light: 0.76 });
    const mx = (b.ix0 + b.ix1) / 2;
    sector(rect(mx - 96, b.iy0 + 128, mx + 96, b.iy1 - 640), { name: 'channel', floor: CURB - 16, floorTex: 'WAT201', lowerTex: 'CONC_4', wallTex: 'CONC_4', light: 0.74 });
    for (const [px0, px1] of [[b.ix0 + 128, mx - 256], [mx + 256, b.ix1 - 128]]) {
      for (let y = b.iy0 + 192; y + 640 < b.iy1 - 640; y += 832) {
        sector(rect(px0, y, px1, y + 640), { name: 'pad', floor: CURB + 8, floorTex: 'METALP1', lowerTex: 'CAUTSTR2', light: 0.78 });
        /* containers: riveted plate, a roller shutter on the end */
        for (let x = px0 + 64; x + 480 < px1; x += 544) {
          const h = rnd() < 0.5 ? 128 : 256;
          prop(x, y + 96, x + 480, y + 288, CURB + 8, CURB + 8 + h, pick(['METALP1', 'OPBLANK', 'OP_BLNK3']), 'METALP1');
          panel(x + 32, y + 84, 128, CURB + 8, 128, 'DOOR0001'); panel(x + 320, y + 84, 128, CURB + 8, 128, 'DOOR0001');
          if (rnd() < 0.6) prop(x, y + 352, x + 480, y + 544, CURB + 8, CURB + 136, pick(['OPBLANK', 'METALP1', 'OP_BLNK2']), 'METALP1');
        }
      }
    }
    /* a shed at the north end with a roller door and a hazard-striped floor */
    const sx0 = b.ix0 + 320, sy0 = b.iy1 - 560, sx1 = b.ix1 - 320, sy1 = b.iy1 - 96;
    building(sx0, sy0, sx1, sy1, { name: 'shed', floor: CURB, ceil: CURB + 256, floorTex: 'CAUTSTR2', ceilTex: 'METALP1', wallTex: 'METALP1', facade: 'METALP1', roofTex: 'METALP1', doorH: 128, light: 0.6 },
             [{ side: 's', at: sx0 + 512, w: 128, tex: 'DOOR0001' }, { side: 's', at: sx1 - 512, w: 128 }], yard);
    scatter(inSectors(yard), [{ type: 'TOWNIE', w: 1 }], 1, 260, 0.2, { name: 'hands' });
  }

  /* ---- 0,3 THE MEADOW: grass, rocks, a scatter of trees ------------ */
  {
    const b = B(0, 3);
    const m = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'meadow', floor: CURB, floorTex: 'GRASS5', lowerTex: 'DIRT_01', wallTex: 'DIRT_01', light: 0.86 });
    for (const [px, py, w, h, tex] of [[400, 500, 900, 700, 'GRASS6'], [1500, 2300, 800, 400, 'GRASS6'], [600, 1900, 700, 600, 'LAWN1'], [1900, 300, 600, 500, 'DIRT3']]) {
      sector(rect(b.ix0 + px, b.iy0 + py, b.ix0 + px + w, b.iy0 + py + h), { name: 'meadow patch', floor: CURB, floorTex: tex, lowerTex: 'DIRT_01', light: 0.86 });
    }
    /* outcrops: low mounds of mossy rock, two steps each, as sectors so
       they are lit like the ground they rise from */
    for (const [ox, oy, r] of [[b.ix0 + 500, b.iy0 + 1500, 150], [b.ix0 + 2550, b.iy0 + 1150, 120], [b.ix0 + 2600, b.iy0 + 2300, 170], [b.ix0 + 900, b.iy0 + 350, 110]]) {
      sector(octagon(ox, oy, r, 7), { name: 'outcrop', floor: CURB + 20, floorTex: 'MOSS_01', lowerTex: 'ROCK_01', light: 0.92 });
      sector(octagon(ox + 10, oy - 10, r * 0.55, 6), { name: 'outcrop top', floor: CURB + 40, floorTex: 'ROCK_01', lowerTex: 'ROCK_01', light: 0.92 });
    }
    /* a ring of standing stones on the rise in the middle */
    const scx = b.ix0 + 1900, scy = b.iy0 + 1350;
    sector(octagon(scx, scy, 420, 12), { name: 'stone circle', floor: CURB + 16, floorTex: 'LAWN1', lowerTex: 'DIRT_01', light: 0.9 });
    for (let k = 0; k < 9; k++) {
      const a = k / 9 * Math.PI * 2, x = scx + Math.cos(a) * 300, y = scy + Math.sin(a) * 300, hgt = 112 + (k % 3) * 40;
      prop(x - 24, y - 16, x + 24, y + 16, CURB + 16, CURB + 16 + hgt, 'CONC_7', 'MOSS_01');
    }
    prop(scx - 64, scy - 32, scx + 64, scy + 32, CURB + 16, CURB + 56, 'ROCK_01', 'MOSS_01');
    scatter(inSectors(m), [{ type: 'TOWNIE', w: 1 }], 0.8, 300, 0.2, { name: 'walkers' });
    scatter(inSectors(m), [{ type: 'PLANT:fir_tall_2', w: 1 }, { type: 'PLANT:street_broad', w: 1 }, { type: 'PLANT:street_big', w: 1 }, { type: 'PLANT:bush_large_1', w: 3 }, { type: 'PLANT:bush_large_2', w: 2 }], 5, 180, 0.6, { name: 'copses' });
    scatter(inSectors(m), [{ type: 'PLANT:grass', w: 6 }, { type: 'PLANT:fern', w: 2 }, { type: 'PLANT:bush_small_1', w: 1 }], 40, 36, 0.5, { name: 'meadow grass' });
  }

  /* ---- 1,3 THE TEST CHAMBER: the test and debug sets, the checkers -- */
  {
    const b = B(1, 3);
    const x0 = b.ix0 + 256, y0 = b.iy0 + 256, x1 = b.ix1 - 256, y1 = b.iy1 - 256, f = CURB;
    sector(rect(b.ix0 + 64, b.iy0 + 64, b.ix1 - 64, b.iy1 - 64), { name: 'test apron', floor: CURB, floorTex: '64TEST', lowerTex: '64TEST', wallTex: '64TEST', light: 0.82 });
    const lab = building(x0, y0, x1, y1, {
      name: 'test chamber', floor: f, ceil: f + 384, floorTex: '256TEST', ceilTex: '512TEST', wallTex: '128TEST', facade: '128TEST', roofTex: '512TEST', doorFloor: '64TEST', light: 1.0,
    }, [{ side: 's', at: (x0 + x1) / 2, w: 192 }], b.walk);
    /* the sixteen debug panels, a gallery round the walls */
    let k = 0;
    const dbg = () => `DEBUG${String(k++).padStart(3, '0')}`;
    for (let x = x0 + 192; x + 128 < x1 - 128 && k < 16; x += 224) panel(x, y1 - 24, 128, f + 96, 128, dbg());
    for (let y = y0 + 256; y + 128 < y1 - 128 && k < 16; y += 224) panel(x1 - 24, y, 128, f + 96, 128, dbg(), 'y');
    for (let x = x1 - 320; x > x0 + 128 && k < 16; x -= 224) {
      if (Math.abs(x + 64 - (x0 + x1) / 2) < 256) continue;
      panel(x, y0 + 12, 128, f + 96, 128, dbg());
    }
    /* the odd ones out on the west wall: the squirrel, the cubicle
       chip, the test card at its own size, the badge */
    panel(x0 + 12, y0 + 512, 128, f + 96, 128, 'SQUIRREL', 'y');
    panel(x0 + 12, y0 + 768, 128, f + 96, 128, 'OFCCUB02', 'y');
    panel(x0 + 12, y0 + 960, 423, f + 64, 240, 'TESTPA00', 'y');
    panel(x0 + 12, y0 + 1500, 625, f + 96, 300, 'GZDOOM', 'y');
    /* and the pack's two cloud strips, high round the top of the room
       like a painted sky: 1024 and 512 across, their clouds at the top */
    panel(x0 + 320, y1 - 24, 1024, f + 240, 144, 'CLOUDS02');
    panel(x1 - 24, y0 + 512, 512, f + 240, 144, 'CLOUDS01', 'y');
    /* test blocks on the floor, one of each size, and the four
       coloured checkers of the XTX set on plinths */
    const T = ['64TEST', '128TEST', '256TEST', '512TEST'];
    T.forEach((t, n) => { const s = 64 << n, x = x0 + 320 + n * 520, y = (y0 + y1) / 2 - s / 2; prop(x, y, x + s, y + s, f, f + s, t, t); });
    ['XTX_5', 'XTX_6', 'XTX_7', 'XTX_8'].forEach((t, n) => prop(x0 + 320 + n * 320, y1 - 640, x0 + 448 + n * 320, y1 - 512, f, f + 128, t, t));
    scatter(inSectors(lab), [{ type: 'SHOPPER', w: 1 }], 1, 260, 0.1, { name: 'testers' });
  }

  /* ---- 2,3 THE LAKE: a shore, shallows, deep water, islands, a jetty */
  {
    const b = B(2, 3);
    const LF = { color: '#a8b8b0', density: 6 };
    const shoreS = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'shore', floor: CURB, floorTex: 'DIRT3', lowerTex: 'ROCK_01', wallTex: 'ROCK_01', light: 0.86 });
    const lx0 = b.ix0 + 320, ly0 = b.iy0 + 320, lx1 = b.ix1 - 320, ly1 = b.iy1 - 320;
    const cx = (lx0 + lx1) / 2, cy = (ly0 + ly1) / 2, rx = (lx1 - lx0) / 2, ry = (ly1 - ly0) / 2;
    const ring = (dr, n = 16) => Array.from({ length: n }, (_, k) => [Math.round(cx + (rx - dr) * Math.cos(k * 2 * Math.PI / n)), Math.round(cy + (ry - dr) * Math.sin(k * 2 * Math.PI / n))]);
    /* the water steps down so it can be waded out of: a beach, shallows,
       then the deep; the water's picture is bright, so it is lit down */
    sector(ring(0), { name: 'beach', floor: CURB - 8, floorTex: 'DIRT_01', lowerTex: 'ROCK_01', light: 0.84, fog: LF });
    sector(ring(96), { name: 'shallows', floor: -12, floorTex: 'WAT201', lowerTex: 'ROCK_01', light: 0.62, fog: LF });
    sector(ring(352), { name: 'lake', floor: -36, floorTex: 'WAT201', lowerTex: 'ROCK_01', light: 0.56, fog: LF });
    /* the islands: grass on a rock lip, a tree and a bush each */
    for (const [ix, iy, r] of [[cx - 350, cy + 200, 180], [cx + 320, cy - 240, 140]]) {
      sector(octagon(ix, iy, r, 10, 0), { name: 'island', floor: -12, floorTex: 'DIRT_01', lowerTex: 'ROCK_01', light: 0.86, fog: LF });
      sector(octagon(ix, iy, r - 40, 10, 0), { name: 'island grass', floor: CURB, floorTex: 'GRASS5', lowerTex: 'DIRT_02', light: 0.9, fog: LF });
      plant(pick(FIRS), ix, iy, 1.1);
      plant('bush_small_1', ix + r * 0.4, iy - r * 0.3);
      plant('bush_large_1', ix - r * 0.35, iy + r * 0.2);
    }
    /* a jetty of decking out over the shallows into the deep, as a
       sector, standing on the water */
    sector(rect(cx - 48, ly0 + 110, cx + 48, ly0 + 330), { name: 'jetty', floor: CURB, floorTex: 'OFCDESK2', lowerTex: 'MANINT1', light: 0.86, fog: LF });
    scatter(inRect(b.ix0 + 32, b.iy0 + 32, b.ix1 - 32, b.iy0 + 280), [{ type: 'TOWNIE', w: 1 }], 5, 150, 0.4, { name: 'bathers' });
    scatter(inSectors(shoreS), [{ type: 'PLANT:fir_medium', w: 2 }, { type: 'PLANT:fir_tall_1', w: 1 }, { type: 'PLANT:street_round', w: 1 }, { type: 'PLANT:bush_small_2', w: 2 }], 6, 110, 0.5, { name: 'shore trees' });
  }

  /* ---- 3,3 THE RUINS: roofless shells in the moss ------------------ */
  {
    const b = B(3, 3);
    const r = sector(rect(b.ix0, b.iy0, b.ix1, b.iy1), { name: 'ruins', floor: CURB, floorTex: 'MOSS_01', lowerTex: 'CONC_7', wallTex: 'CONC_7', light: 0.66,
                                                         fog: { color: '#8c8878', density: 8 } });
    for (const [sx, sy, w, h] of [[256, 256, 896, 704], [1408, 384, 1024, 896], [384, 1408, 1152, 1024], [1792, 1664, 768, 832]]) {
      const x0 = b.ix0 + sx, y0 = b.iy0 + sy, x1 = x0 + w, y1 = y0 + h, t = 32;
      sector(rect(x0 + t, y0 + t, x1 - t, y1 - t), { name: 'shell floor', floor: CURB, floorTex: pick(['CONC_5', 'DIRT1', 'MOSS_01']), lowerTex: 'CONC_7', light: 0.66, fog: { color: '#8c8878', density: 8 } });
      const TEX = ['CONC_7', 'CONC_5', 'CONC_4'];
      /* A WALL THAT HAS FALLEN: runs of different lengths, each a step
         up or down from the last, a whole stretch of one material with
         ivy taking some of it, gaps where it came down, and the rubble
         of it lying at its foot */
      const run = (ax, ay, bx, by, horiz) => {
        const len = horiz ? bx - ax : by - ay;
        let hgt = 96 + rnd() * 160;
        const tex = pick(TEX);
        for (let s = 0; s < len;) {
          const piece = 64 + Math.round(rnd() * 3) * 64;
          const e = Math.min(len, s + piece);
          hgt = Math.max(24, Math.min(288, hgt + (rnd() - 0.55) * 96));
          if (rnd() < 0.18) {
            /* the gap, and what fell out of it */
            const rx = horiz ? ax + s + 16 : ax + (rnd() < 0.5 ? -40 : t + 8), ry = horiz ? ay + (rnd() < 0.5 ? -40 : t + 8) : ay + s + 16;
            prop(rx, ry, rx + 32 + rnd() * 24, ry + 32, CURB, CURB + 12 + Math.round(rnd() * 16), tex, 'MOSS_01');
          } else {
            const T = rnd() < 0.25 ? 'IVY1' : tex;
            if (horiz) prop(ax + s, ay, ax + e, ay + t, CURB, CURB + Math.round(hgt), T, 'MOSS_01');
            else prop(ax, ay + s, ax + t, ay + e, CURB, CURB + Math.round(hgt), T, 'MOSS_01');
          }
          s = e;
        }
      };
      run(x0, y0, x1, y0, true); run(x0, y1 - t, x1, y1 - t, true);
      run(x0, y0 + t, x0, y1 - t, false); run(x1 - t, y0 + t, x1 - t, y1 - t, false);
    }
    for (let k = 0; k < 10; k++) thing('GRAVESTONE', b.ix0 + 300 + rnd() * 2200, b.iy0 + 2600 + rnd() * 200, { angle: -Math.PI / 2 + (rnd() - 0.5), variant: (rnd() * 8) | 0 });
    scatter(inSectors(r), [{ type: 'PLANT:fern', w: 4 }, { type: 'PLANT:grass', w: 3 }, { type: 'PLANT:bush_small_2', w: 1 }, { type: 'PLANT:fir_young', w: 1 }], 30, 44, 0.65, { name: 'overgrowth' });
  }

  /* ---- THE CROSSROADS, and the start ------------------------------- */
  const [sx, sy] = SPRAWL_START;
  thing('START', sx, sy, { angle: Math.PI / 2 });
  scatter(inRect(RIM + ROAD, sy - 256, S - RIM - ROAD, sy + 256), [{ type: 'TOWNIE', w: 1 }], 0.8, 320, 0.3, { name: 'road walkers e-w' });
  scatter(inRect(sx - 256, RIM + ROAD, sx + 256, S - RIM - ROAD), [{ type: 'TOWNIE', w: 1 }], 0.8, 320, 0.3, { name: 'road walkers n-s' });

  /* ---- 0,3 AGAIN: THE BIOME BEDS down the meadow's west edge --------
     The vandre project's grounds and plants (tools/prep-vandre.py): a
     bed of each ground, 256 by 112, raised a step, and on it the plants
     that grew on that ground there. Trees stand 96 apart so each has a
     cell of its own; the low plants go in a row in front of them. Built
     last, so nothing it rolls moves anything above. */
  {
    const b = B(0, 3);
    const BEDS = [
      ['SAND1',    ['desert_big_cactus_1', 'desert_cactus_5', 'desert_cactus_6'],
                   ['desert_small_cactus_1', 'desert_creosote_bush_5', 'desert_bush_1', 'desert_small_cactus_2']],
      ['WASTE1',   ['wasteland_tree', 'wasteland_tree_big_2', 'wasteland_tree_big_3'],
                   ['desert_dead_creosote_bush_5', 'wasteland_bush_1', 'desert_dead_creosote_bush_6']],
      ['MOLTEN1',  ['wasteland_small_tree_1', 'wasteland_tree_small_2'], []],
      ['SAVANNA1', ['savanna_tree_1'], ['savanna_grass_short_1', 'savanna_grass_tall_1', 'savanna_grass_short_2', 'savanna_grass_tall_2', 'desert_creosote_bush_6', 'desert_bush_2']],
      ['FARMLND1', [], ['farm_wheat_1', 'farm_wheat_2', 'farm_wheat_3', 'farm_wheat_4', 'farm_wheat_2', 'farm_wheat_1', 'farm_wheat_4', 'farm_wheat_3']],
      ['TUNDRA1',  [], ['tundra_bush_1', 'tundra_bush_2', 'tundra_bush_3', 'tundra_bush_4', 'tundra_bush_5']],
      ['FROZEN1',  ['pine_juvenile_fir_tree_1', 'pine_juvenile_fir_tree_2', 'pine_juvenile_fir_tree_4'], []],
      ['ARCTIC1',  ['pine_fir_tree_4', 'pine_barrens_tree'], []],
      ['PINEBAR1', ['pine_fir_tree_1', 'pine_fir_tree_2', 'pine_fir_tree_3'],
                   ['pine_fern_1', 'pine_forest_bush_1', 'pine_fern_2', 'pine_forest_bush_2', 'pine_fern_3', 'pine_forest_bush_3', 'pine_fern_4']],
      ['MEADOW1',  ['new_meadow_tree_1'], ['new_meadow_bush_1', 'new_meadow_bush_2', 'new_meadow_bush_3', 'new_meadow_bush_4']],
      ['MEADOW2',  ['new_meadow_tree_2'], ['new_meadow_flower_1', 'new_meadow_grass_1', 'new_meadow_flower_2', 'new_meadow_grass_2']],
      ['MEADOW3',  ['new_meadow_tree_3'], ['new_meadow_fern_1', 'new_meadow_fern_2', 'new_meadow_grass_tall_1', 'new_meadow_fern_3', 'new_meadow_fern_4']],
      ['MEADOW4',  [], ['new_meadow_flower_1', 'new_meadow_grass_tall_1', 'new_meadow_flower_2', 'new_meadow_grass_1']],
      ['MEADOW5',  [], ['new_meadow_grass_2', 'new_meadow_bush_2', 'new_meadow_grass_1']],
      ['GRASCHK1', ['meadow_tree_big', 'meadow_tree_medium'], ['meadow_bush_var_a', 'meadow_grass_var_a', 'meadow_bush_var_b']],
      ['GRASCHK2', ['meadow_tree_really_big'], ['meadow_grass_var_b', 'meadow_grass_var_a', 'meadow_grass_var_b']],
      ['CANDY1', [], []], ['CITYCON1', [], []], ['CITYMET1', [], []], ['CITYMET2', [], []], ['CITYSKRT', [], []],
    ];
    BEDS.forEach(([tex, trees, low], n) => {
      const x0 = b.ix0 + 48, y0 = b.iy0 + 48 + n * 128;
      sector(rect(x0, y0, x0 + 256, y0 + 112), { name: 'biome bed', floor: CURB + 8, floorTex: tex, lowerTex: tex, light: 0.86 });
      trees.forEach((k, i) => plant(k, x0 + 32 + i * 96, y0 + 40));
      low.forEach((k, i) => plant(k, x0 + 16 + (i + 0.5) * (224 / low.length), y0 + 88));
    });
  }
  void ground; void plateau;
  return d;
}

/** The textures the map may wear that are not the pack's: the user's
 *  photographs baked into the texture bank, the sky, and the word for no
 *  texture at all (the plateau's outer edge, the clouds' step). See THE
 *  SPRAWL in tools/smoke-test.mjs, which holds the map to this. */
export const SPRAWL_OWN_TEXTURES = ['RAILING', 'SKY', 'NONE'];
/** And the things it may place: the user's people, photographed stones
 *  and lamps, the plants, and the start. */
export const SPRAWL_THINGS = ['START', 'SHOPPER', 'TOWNIE', 'GRAVESTONE', 'STREETLAMP', 'PLANT'];
