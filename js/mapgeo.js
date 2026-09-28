/* =====================================================================
   MEWD — turning a floor plan into triangles
   =====================================================================

   A two-sided line is a hole between two sectors, and what you actually
   SEE at that hole is the bit of wall above it and the bit of wall below
   it. Above: the gap between the two ceilings. Below: the gap between the
   two floors. Doom called them the upper and lower textures and every
   piece of level architecture in this game is one of them —

     a doorway      upper only, lower zero
     a shop counter lower only, 40 tall, shoot over it
     a kerb         lower, 8 tall, walk over it without noticing
     a window       upper AND lower, with the gap between them the glass
     a door         upper on a sector whose ceiling is on the floor

   PEGGING is the part everyone forgets and then wonders why their door
   looks wrong. When a sector moves, the wall above it changes height —
   so does the texture on it slide with the sector, or stay nailed to the
   fixed ceiling above? Doom answered with a flag; this answers with two
   named fields, because "pegUpper: 'bottom'" is a sentence and
   "flags |= 0x0008" is a lookup.

   The default is 'bottom', which nails the texture to the MOVING edge, so
   a door's face slides up with the door instead of scrolling past it.
   That is the default precisely because doors are the common case, and
   the common case should need no flag at all.

   BATCHING. Everything with the same texture goes into one buffer, so a
   whole supermarket is about twenty draw calls. Lighting is per-vertex
   and baked, so no lights, no shadows, and nothing to update.
   ===================================================================== */

import * as THREE from 'three';
import { createWallMaterial } from './material.js';
import { roofFraming, breachDebris } from './ruin.js';
import { pieces as breachPieces } from './breach.js';
import { STREET_LAMP } from './textures.js';

/* THE COLOUR OF THE LIGHT on whatever is being added right now, Doom
   64's way — a function of the height, so a wall can run from its
   sector's top colour down to its bottom one, or null for white. Set by
   addFlats and addLine around each surface they add and read by
   Batch.tri for every corner; see paintWall and `tint` on a sector. */
let PAINT = null;
const WHITE = [1, 1, 1];
/* AND THE FOG of the sector it is in, alongside: [r, g, b, density],
   or null for the map's default (world.fogDefault in js/material.js).
   Set where PAINT is, from the same sector. */
let FOGV = null;
const NO_FOG = [0, 0, 0, -1];
const fogOf = s => s?.fog || null;

/** How a sector's walls are coloured: top at its ceiling, bottom at its
 *  floor, straight between — or null if the sector says nothing. UNDER
 *  THE SKY there is no ceiling to grade to, only the height the walls
 *  are allowed to reach, so each piece of wall is graded over its own
 *  height instead (`lo`, `hi`): the step round a pit runs from the top
 *  colour at its rim to the bottom one at its foot. */
function paintWall(s, lo = null, hi = null) {
  const t = s?.tint;
  if (!t || (!t.top && !t.bottom)) return null;
  const top = t.top || WHITE, bot = t.bottom || WHITE;
  const own = s.ceilTex === 'SKY' && lo !== null && hi > lo;
  const z0 = own ? lo : s.floor, z1 = own ? hi : Math.max(s.floor + 1, s.ceil);
  return h => {
    const k = Math.max(0, Math.min(1, (h - z0) / (z1 - z0)));
    return [bot[0] + (top[0] - bot[0]) * k, bot[1] + (top[1] - bot[1]) * k, bot[2] + (top[2] - bot[2]) * k];
  };
}
const paintFlat = c => (c ? () => c : null);

/* ONE SIDE OF A LINE, as the face looking into sector `s` wears it: the
   line with that side's own textures and offsets over it (MEWD Editor's
   front and back sidedefs — see SIDES in js/editor/doc.js), or the line
   itself when it has no sides. */
function sideOf(l, s) {
  const o = l.sides && s && l.sides[s.docId];
  if (!o) return { l, mid: null, upper: null, lower: null };
  const lv = (o.xoff !== undefined || o.yoff !== undefined || o.xscale !== undefined || o.yscale !== undefined)
    ? Object.assign(Object.create(l), { xoff: o.xoff ?? l.xoff, yoff: o.yoff ?? l.yoff,
                                        xscale: o.xscale ?? l.xscale, yscale: o.yscale ?? l.yscale }) : l;
  return { l: lv, mid: o.midTex || null, upper: o.upperTex || null, lower: o.lowerTex || null };
}

/* A batch collects triangles for one texture and hands back a mesh. */
class Batch {
  constructor(name) {
    this.name = name; this.pos = []; this.uv = []; this.light = []; this.sky = []; this.char = [];
    this.lamp = []; this.tint = []; this.fog = [];
    this.area = 0;
  }
  get empty() { return this.pos.length === 0; }

  /* `sk` is how much of this triangle's light comes from the sky: 0 for
     anything indoors, 1 out in the car park. The shader stretches the
     distance falloff by it, which is the whole reason a parade six
     thousand units long does not read as a black wall. */
  /* `ch` is how burnt this triangle's region is — 0 untouched, about a
     half charred, 1 gutted. The shader puts LIVE COALS on it in the same
     eight colours and on the same clock as the burning trees, so a
     charred wall and a charred fir are one fire going out. */
  /* THERE WAS AN `rg` HERE TOO: which region a triangle belonged to, so
     the shader could look its progress up in a one-texel-per-sector
     picture. It is gone. A sector's progress is one number, and the
     sectors of this map are big rectangles, so every surface in one
     sooted together and a burnt aisle met a clean cross-aisle along a
     dead-straight line. The shader reads the fire's own 32-unit cell
     grid by world position instead (burnAt in js/material.js), which
     needs nothing from the geometry at all. */
  /* `lp` is whether this triangle is lit by a STREET LAMP: 1 on the
     pool of pavement under one and on the lamp's own post, 0 on
     everything else. The shader tints such a surface's light cold after
     dark — see vLamp in js/material.js — which is how a sector, whose
     light is one number, gets a light with a colour. */
  tri(ax, ay, az, au, av, bx, by, bz, bu, bv, cx, cy, cz, cu, cv, l, sk = 0, ch = 0, lp = 0) {
    /* HOW MUCH WORLD THIS BATCH COVERS, accumulated as it is built.
       It is what decides whether the batch is worth a draw call from
       far away — see the LOD in applyVisibility — and a triangle's area
       is half the cross product of two of its edges. Counted here
       because here is the only place that sees a triangle. */
    const ux = bx - ax, uy = by - ay, uz = bz - az;
    const vx = cx - ax, vy = cy - ay, vz = cz - az;
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    this.area += Math.sqrt(nx * nx + ny * ny + nz * nz) * 0.5;
    this.pos.push(ax, ay, az, bx, by, bz, cx, cy, cz);
    this.uv.push(au, av, bu, bv, cu, cv);
    this.light.push(l, l, l);
    this.sky.push(sk, sk, sk);
    this.char.push(ch, ch, ch);
    this.lamp.push(lp, lp, lp);
    if (PAINT) {
      const a = PAINT(ay), b = PAINT(by), c = PAINT(cy);
      this.tint.push(a[0], a[1], a[2], b[0], b[1], b[2], c[0], c[1], c[2]);
    } else this.tint.push(1, 1, 1, 1, 1, 1, 1, 1, 1);
    const f = FOGV || NO_FOG;
    this.fog.push(f[0], f[1], f[2], f[3], f[0], f[1], f[2], f[3], f[0], f[1], f[2], f[3]);
  }

  /* A quad as two triangles, given four corners in winding order. */
  quad(p, u, l, sk = 0, ch = 0, lp = 0) {
    this.tri(p[0][0], p[0][1], p[0][2], u[0][0], u[0][1],
             p[1][0], p[1][1], p[1][2], u[1][0], u[1][1],
             p[2][0], p[2][1], p[2][2], u[2][0], u[2][1], l, sk, ch, lp);
    this.tri(p[0][0], p[0][1], p[0][2], u[0][0], u[0][1],
             p[2][0], p[2][1], p[2][2], u[2][0], u[2][1],
             p[3][0], p[3][1], p[3][2], u[3][0], u[3][1], l, sk, ch, lp);
  }

  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('light', new THREE.Float32BufferAttribute(this.light, 1));
    g.setAttribute('sky', new THREE.Float32BufferAttribute(this.sky, 1));
    g.setAttribute('charred', new THREE.Float32BufferAttribute(this.char, 1));
    g.setAttribute('lamp', new THREE.Float32BufferAttribute(this.lamp, 1));
    g.setAttribute('tintRGB', new THREE.Float32BufferAttribute(this.tint, 3));
    g.setAttribute('fogRGBA', new THREE.Float32BufferAttribute(this.fog, 4));
    g.computeBoundingSphere();
    return g;
  }
}

class BatchSet {
  constructor() { this.map = new Map(); }
  get(name) {
    let b = this.map.get(name);
    if (!b) { b = new Batch(name); this.map.set(name, b); }
    return b;
  }
  toGroup(bank, opts = {}) {
    const group = new THREE.Group();
    for (const [name, b] of this.map) {
      if (b.empty) continue;
      const entry = bank.get(name.split('|').pop());
      const mat = createWallMaterial(entry.texture, { alphaTest: entry.masked ? 0.5 : 0.0, tint: true, ...opts });
      const mesh = new THREE.Mesh(b.geometry(), mat);
      mesh.frustumCulled = true;
      mesh.name = name;
      /* what the LOD in applyVisibility reads: how much world this
         batch covers, so that its share of the screen can be had by
         dividing by the square of the distance to it */
      mesh.userData.area = b.area;
      group.add(mesh);
    }
    return group;
  }
}

/* --------------------------------------------------------------------
   THE BLOCK IS THE UNIT OF DRAWING

   Everything with the same texture used to go into one buffer, so a
   whole supermarket was about twenty draw calls and every one of them
   had a bounding sphere the size of the store. That is fine for a store
   and it is nothing at all for a town: a batch whose bounds are the
   entire town is never culled, so every brick wall in it is submitted
   every frame whichever way you are facing.

   So a batch is one texture IN ONE BLOCK. Twenty-five blocks by twenty
   textures is more draw calls than twenty — and it is the only way the
   frustum means anything, and it is what lets the portal flood turn a
   block off outright (see applyVisibility below, and SIGHT.txt). It is
   also what makes the char rebuild affordable: when a region finishes
   burning, the block it is in is rebuilt and the other twenty-four are
   left alone.

   The grid is the town's own block pitch, anchored at the world origin,
   which the mall already sits on — see THE GRID in TOWN.txt.
   ------------------------------------------------------------------ */
export const BATCH_BLOCK = 3648;
/* HOW MUCH OF THE AIR A BLOCK HAS TO BE INSIDE to be drawn at all, and
   from how far off the small batches in it start dropping out. See the
   note on applyVisibility for both. */
export const FAR_AIR = 0.85;
const LOD_FROM = 2400;
/* THE SMALLEST SHARE OF THE SCREEN A BATCH IS DRAWN FOR, as world area
   over distance squared — which is its solid angle, near enough, for
   anything small. Four pixels' worth, and a pixel is a different size
   on every buffer this game draws into: the pipeline's height is a
   setting and runs from sixty rows to a thousand (see js/lofi.js), so
   the threshold FOLLOWS IT rather than being written for one of them.
   At 960 rows in a 72-degree field a pixel is about 2.3e-6 of a
   steradian; at 320 it is nine times that, and nine times as much can
   go. Which is the right way round: the buffer that cannot show the
   detail is the one on the machine that cannot afford to draw it. */
const PIXELS_TO_KEEP = 4;
const REF_ROWS = 960, REF_PIXEL_SOLID = 2.3e-6;
export function minSolidFor(rows) {
  const scale = (REF_ROWS / Math.max(60, rows || REF_ROWS)) ** 2;
  return PIXELS_TO_KEEP * REF_PIXEL_SOLID * scale;
}
/* How near you have to be for a block's insides to be drawn. Two block
   pitches: far enough that you never see one arrive, near enough that
   twenty-two of the town's twenty-five blocks are outsides only. */
export const INTERIOR_DIST = BATCH_BLOCK * 2;
const blockOf = (x, y) => Math.floor(x / BATCH_BLOCK) + ',' + Math.floor(y / BATCH_BLOCK);
/** Which block a sector is drawn in: the one its middle lands in. */
export function sectorBlock(s) {
  return blockOf((s.bbox[0] + s.bbox[2]) / 2, (s.bbox[1] + s.bbox[3]) / 2);
}
function lineBlock(l) { return blockOf((l.x1 + l.x2) / 2, (l.y1 + l.y2) / 2); }

/* --------------------------------------------------------------------
   Vertical texture coordinates

   v(z) = (z - peg) / texHeight, where `peg` is the world height the TOP
   edge of the texture sits at. With repeat wrapping that one line covers
   every pegging case; all the cases below do is work out where the top
   edge goes.
   ------------------------------------------------------------------ */
const vAt = (z, peg, texH) => (z - peg) / texH;

/**
 * Build every triangle in the level.
 *
 * @param level  a built Level
 * @param bank   texture bank: .get(name) -> { texture, w, h, masked }
 * @returns { group, dynamic } — dynamic.rebuild() after a door moves
 */
export function buildLevelGeometry(level, bank) {
  /* the roofs read their texture sizes from here, being geometry rather
     than a surface any sector owns */
  for (const r of [...(level.roofs || []), ...level.sectors.map(s => s.roof).filter(Boolean)]) {
    for (const n of [r.tex || 'SHINGLE', r.gableTex || r.tex || 'SHINGLE', r.soffit].filter(Boolean)) {
      const e = bank.get(n);
      if (e) noteTextureSize(n, e.w, e.h);
    }
  }
  /* and the free boxes read theirs from the same place, for the same
     reason: nothing owns them, so nothing else would */
  for (const r of level.props || []) {
    for (const n of [r.tex, r.topTex, r.botTex].filter(Boolean)) {
      const e = bank.get(n);
      if (e) noteTextureSize(n, e.w, e.h);
    }
  }

  /* A line is dynamic if either sector it touches can move, because the
     wall above a door changes height every tic the door is opening. */
  const dynamicLines = new Set();
  for (const l of level.lines) {
    for (const i of l.frontCol) if (level.sectors[i].dynamic) dynamicLines.add(l);
    for (const i of l.backCol) if (level.sectors[i].dynamic) dynamicLines.add(l);
  }
  const staticLines = level.lines.filter(l => !dynamicLines.has(l));
  const dynamicSectors = level.sectors.filter(s => s.dynamic);
  const staticSectors = level.sectors.filter(s => !s.dynamic);

  const group = new THREE.Group();
  group.name = 'level';
  const staticGroup = new THREE.Group();
  staticGroup.name = 'level-static';
  group.add(staticGroup);

  /* Rebuilt in full when the store changes its skin — which happens when
     a region finishes burning and its textures are swapped for charred
     ones. A whole-level rebuild is a few thousand triangles and about ten
     milliseconds; it happens perhaps twenty times in a level, debounced,
     and it is far simpler than tracking which vertices belong to which
     sector so that a subset could be patched. */
  /* WHAT IS IN EACH BLOCK, worked out once. A sector is drawn in the
     block its middle lands in and a line in the block its midpoint
     lands in, so every triangle belongs to exactly one of them and a
     rebuild of one block is complete on its own. */
  const blockSectors = new Map(), blockLines = new Map();
  const push = (m, k, v) => { let a = m.get(k); if (!a) m.set(k, a = []); a.push(v); };
  for (const s of staticSectors) { s.drawBlock = sectorBlock(s); push(blockSectors, s.drawBlock, s); }
  /* AND WHO ANSWERS FOR A BLOCK, which is not the same question as what
     is drawn in it, and the difference was a real hole.

     applyVisibility asks a block whether any REGION in it is visible. A
     region is in the block its middle lands in; a line is in the block
     its MIDPOINT lands in. Those two are usually the same block and
     occasionally are not — and the case where they are not is the one
     that matters, because it is a big outdoor region owning the wall of
     the building it wraps round. The wood behind the west wing is nine
     thousand units of forest whose middle is a block and a half away
     from the supermarket's flank, and that flank is the wood's own
     one-sided wall: its geometry lands in the anchor's block, whose
     visibility is answered entirely by the anchor's aisles.

     So the whole west side of the building was drawn only because the
     portal flood leaked through the fire doors into the shop. Shut the
     doors to sight — which is what a steel leaf does — and the building
     loses its outside. Found by giving the fire exits the staff door's
     `opaque`, and it had been true since the day blocks were introduced.

     The fix is to let a line's OWNERS answer for the block its geometry
     went into, as well as the regions centred there. Nothing moves: the
     triangles stay where they are, so a block is still rebuilt on its
     own and still culled by its own corner. */
  const blockVis = new Map();
  const seen = new Map();
  const answersFor = (k, s) => {
    let set = seen.get(k); if (!set) seen.set(k, set = new Set());
    if (set.has(s)) return;
    set.add(s); push(blockVis, k, s);
  };
  for (const [k, list] of blockSectors) for (const s of list) answersFor(k, s);
  for (const l of staticLines) {
    const k = lineBlock(l); l.drawBlock = k; push(blockLines, k, l);
    for (let i = 0; i < l.frontCol.length; i++) answersFor(k, level.sectors[l.frontCol[i]]);
    for (let i = 0; i < l.backCol.length; i++) answersFor(k, level.sectors[l.backCol[i]]);
  }
  /* the roofs, which belong to no sector at all — see roofGeometry */
  const blockRoofs = new Map();
  for (const r of level.roofs || []) push(blockRoofs, blockOf((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2), r);
  /* and the boxes, which belong to no sector either — see boxGeometry */
  const blockProps = new Map();
  for (const r of level.props || []) push(blockProps, blockOf((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2), r);
  /* and the street lamps, which are things the town laid and geometry
     this file stands up — see lampGeometry */
  const blockLamps = new Map();
  for (const t of level.things || []) if (t.type === 'STREETLAMP') push(blockLamps, blockOf(t.x, t.y), t);
  const blockKeys = [...new Set([...blockSectors.keys(), ...blockLines.keys(), ...blockRoofs.keys(),
                                 ...blockProps.keys(), ...blockLamps.keys()])];

  /* AND THE INTERIORS ARE LOD. The buffer is two to four hundred rows
     tall. You cannot see through a forty-eight-unit window at forty
     metres at that resolution — there is nothing there to see. So a
     block's indoor surfaces go in a second group of their own and are
     submitted only when you are near enough to look through a door;
     the shell — the outside walls, the street, the roofs — is always
     there. It is the same trick js/forest.js plays on fifty thousand
     trees.

     A surface is indoors if every region it belongs to is. The wall
     between a hall and the street belongs to both and is shell, which
     is what keeps the house a house from the far end of the block. */
  /* A ROOF IS THE MOST SHELL THING THERE IS. It is not outdoors — you
     could not stand in one — but it is the part of a house you see from
     the far end of the street, and putting it in with the wallpaper
     meant a town whose roofs arrived two blocks away. */
  const indoor = s => !(s.outdoor || s.forest || s.outside || s.roofTex);
  const lineIndoor = l => {
    for (const i of l.frontCol) if (!indoor(level.sectors[i])) return false;
    for (const i of l.backCol) if (!indoor(level.sectors[i])) return false;
    return true;
  };

  /* one Group per block with a shell and an inner child, so a block can
     be hidden in one flag and its insides in another */
  const blockGroups = new Map(), blockMid = new Map();
  for (const k of blockKeys) {
    const g = new THREE.Group();
    g.name = 'block ' + k;
    const shell = new THREE.Group(); shell.name = 'shell';
    const inner = new THREE.Group(); inner.name = 'inner';
    g.add(shell); g.add(inner);
    /* where the block is, for the distance the insides come in at */
    const [bx, by] = k.split(',').map(Number);
    blockMid.set(k, [(bx + 0.5) * BATCH_BLOCK, (by + 0.5) * BATCH_BLOCK]);
    blockGroups.set(k, g);
    staticGroup.add(g);
  }

  function rebuildBlock(k) {
    const g = blockGroups.get(k);
    if (!g) return;
    const [shellG, innerG] = g.children;
    for (const child of [shellG, innerG])
      for (const o of child.children)
        o.traverse(m => { if (m.isMesh) { m.geometry.dispose(); m.material.dispose(); } });
    shellG.clear(); innerG.clear();
    const set = new BatchSet(), inner = new BatchSet();
    /* WHICH GROUP A SURFACE GOES IN is a question about the surface and
       not about the line it is on: one line carries a kitchen wall and
       the roof over it, and they do not come in at the same distance.
       So the pick is handed down and asked per storey and per band. */
    const pick = sec => (sec && indoor(sec) ? inner : set);
    for (const s of blockSectors.get(k) || []) addFlats(pick(s), level, s, bank);
    for (const l of blockLines.get(k) || []) addLine(lineIndoor(l) ? inner : set, level, l, bank, pick);
    /* AND THE DEBRIS ROUND WHATEVER HAS BEEN SHOT THROUGH. A wall in
       this engine has no thickness, so a hole in one is a rectangle cut
       out of a sheet of card; the ring of broken material round it is
       how a hole gets a depth, for the eighty units either side of it
       where anybody is going to look. Built here so it lands in the
       same batch as the brick and rebuilds in step with the hole as the
       hole crumbles wider. See breachDebris in js/ruin.js. */
    for (const l of blockLines.get(k) || []) {
      if (!l.breach || !l.breach.length) continue;
      /* WHERE THIS WALL ACTUALLY HAS BRICK, low and high in pairs, and
         it has to be the same answer this function just drew.

         TWO-SIDED LINES ALREADY KNOW. l.bands is every interval of z
         where exactly one of the two columns is open — the uppers and
         lowers of the loop above — so a shopfront's three bands of
         masonry with two ribbons of glass between them are five
         intervals and the ring is hung on the three that are wall.

         ONE-SIDED LINES ARE THE WHOLE STOREY, floor to ceiling, per
         sector in the column.

         IT IS NOT THE SECTORS EITHER SIDE. That was the first cut and
         it was wrong in the most visible way available: the sector on
         the OUTSIDE of a house is the street, whose ceiling is the sky
         a few thousand units up, so the band with the most overlap was
         always the open air and the ring was never clamped to anything
         — a photograph from the pavement showed an arc of masonry
         floating well above the roof. */
      let own = null;
      BANDS.length = 0;
      if (l.bands && l.bands.length) {
        for (const bd of l.bands) {
          if (!bd.tex || bd.tex === 'NONE' || bd.z1 <= bd.z0) continue;
          if (bd.kind === 'upper' && bd.open.ceilTex === 'SKY' && bd.from.ceilTex === 'SKY') continue;
          BANDS.push(bd.z0, bd.z1);
          if (!own) own = bd.open;
        }
      } else {
        for (const col of [l.frontCol, l.backCol]) {
          for (const si of col || []) {
            const s = level.sectors[si];
            if (!s || s.collapsed || s.ceil <= s.floor) continue;
            BANDS.push(s.floor, s.ceil);
            if (!own) own = s;
          }
        }
      }
      if (!BANDS.length) continue;
      breachDebris(lineIndoor(l) ? inner : set, l, own.light, BANDS);
    }
    /* AND THE STEEL, over whichever regions have lost their deck. It
       goes in the same BatchSet as everything else, so the whole ruined
       roof of a burnt-out store is one more draw call and not one per
       region — and it is rebuilt with the rest of its block, which is
       what keeps it in step with a fire that is still spreading. */
    for (const s of blockSectors.get(k) || []) if (s.ruinRoof) roofFraming(set, s);
    /* AND THE ROOFS, which no sector can hold: a sector engine cannot
       slope a ceiling and a flat-roofed house is not an American house.
       See roofGeometry. A roof is the most shell thing there is. */
    for (const s of blockSectors.get(k) || []) if (s.roof) roofGeometry(set, s);
    for (const r of blockRoofs.get(k) || []) roofGeometry(set, { roof: r, light: r.light });
    /* AND THE STREET LAMPS, in the shell: a lamp is the thing you see
       from the far end of a street after the houses have gone to boxes */
    /* AND THE BOXES: the chimney over the ridge, the porch over the
       stoop, the cornice at the top of a wall. Shell, with the roofs,
       because a chimney is most of what a house is from three streets
       away.

       UNLESS THE MAP SAYS OTHERWISE. A chimney belongs in the shell; a
       tin of beans on a conveyor does not. The checkstands put about
       four hundred small boxes inside the supermarket — the tills, the
       racks, the shopping on the belts — and the rule at the top of
       this function is that the group is a question about the SURFACE,
       so furniture in a room goes in with the room and drops out when
       the room does.

       Measured, it changes nothing today: the interior distance is
       taken from a block's NEAR CORNER, so you have to be most of two
       blocks clear of the supermarket before its inside is dropped at
       all, and by then the whole shop has gone with it. It is the right
       group rather than a saving, and it is the group that will be
       asked if that distance is ever tightened. */
    for (const r of blockProps.get(k) || []) boxGeometry(r.inner ? inner : set, r);
    for (const t of blockLamps.get(k) || []) lampGeometry(set, level, t);
    shellG.add(set.toGroup(bank));
    if (inner.map.size) innerG.add(inner.toGroup(bank));
    /* a rebuilt block's batches are all visible again, so the LOD has
       to forget what it had decided about the ones that are gone */
    g.userData.lodOff = false;
    g.userData.lodD2 = -1; g.userData.lodSolid = -1;
  }

  /**
   * Rebuild the static geometry.
   *
   * With no argument, all of it — which is what startup and a relight
   * want. With a set of block keys, only those: when a region finishes
   * burning, the block it charred in is rebuilt and the rest of the
   * town is left alone. At town scale that is the difference between a
   * hundred thousand triangles and four, twenty times over, during the
   * exact moments the game is at its best.
   */
  function rebuildStatic(blocks = null) {
    for (const k of blocks || blockKeys) rebuildBlock(k);
  }

  /** Which blocks these sectors are drawn in — what to hand rebuildStatic
   *  after a fire has changed some regions' skins. */
  function blocksOf(sectors) {
    const out = new Set();
    for (const s of sectors) if (s.drawBlock) out.add(s.drawBlock);
    return out;
  }

  /**
   * TURN OFF THE BLOCKS YOU CANNOT SEE.
   *
   * The portal flood (Level.visibleSectors, and SIGHT.txt) already says
   * which regions are visible, and this plan's unit of drawing is the
   * block those regions are in — so a block with nothing visible in it
   * is not submitted at all. It is the exact cull rather than the
   * frustum's guess, and on a street grid that is the whole difference:
   * the frustum keeps every block in front of you whether or not a
   * house is standing in the way.
   */
  /* --------------------------------------------------------------------
     TWO THINGS DECIDE WHETHER A BATCH IS DRAWN, AND BOTH ARE ABOUT SIZE

     The town is twenty-five blocks and every block is about thirty
     textures, so the frustum alone submits eight hundred draw calls
     down a street — and measured on a street, two thirds of them
     carried sixty-four triangles or fewer and half of THOSE were
     further away than seven thousand units. A two-triangle strip of
     road line, in its own draw call, five kilometres off.

     THE AIR HAS ALREADY HIDDEN THE FAR ONES. Every surface in the game
     is mixed toward a texel of the sky by its distance (worldShade in
     js/material.js), and the mix is nearly complete well before the
     air's own far limit: at eighty-five per cent of airFar a surface is
     ninety-three per cent sky. What is drawn there is the sky with a
     four per cent memory of a roof in it, and not drawing it leaves the
     sky, which is the same picture. So a block past FAR_AIR of the
     current air is not submitted. It follows the weather for free —
     rain pulls airFar in to five thousand and the town closes up with
     it, which is what a town in the rain does.

     AND A BATCH TOO SMALL TO SEE IS NOT WORTH A DRAW CALL. Each one
     knows how much WORLD it covers (see Batch.tri), so its share of the
     screen is that over the square of the distance, and below a few
     pixels of it there is nothing there to draw. Area and not triangle
     count, because a road is two triangles and an acre, and area and
     not the bounding sphere, because a batch's sphere is its whole
     block and says nothing about the thin strip inside it.

     BOTH ARE CONSERVATIVE AT THE RESOLUTION THE GAME RUNS AT. The
     threshold is set against the tallest buffer the pipeline will make,
     so a batch kept at 960 rows is kept at 320 rows too — where it
     would cover nine times fewer pixels and could have gone.
     ------------------------------------------------------------------ */
  function applyVisibility(lv, ex = null, ey = null, innerDist = INTERIOR_DIST,
                          airFar = Infinity, rows = REF_ROWS) {
    const d2 = innerDist * innerDist;
    const far = airFar === Infinity ? Infinity : airFar * FAR_AIR;
    const far2 = far === Infinity ? Infinity : far * far;
    const minSolid = minSolidFor(rows);
    /* PAST THE FLOOD'S RADIUS THERE IS NOTHING TO ASK. A block out there
       was never walked (see VIS_FAR in js/level.js), so every region in
       it would answer "visible" one at a time and six hundred of them
       would say it six hundred times. The block's own nearest corner
       answers for all of them at once, and what decides at that range is
       the frustum. */
    const vr2 = lv.visRadius2;
    for (const [k, g] of blockGroups) {
      const list = blockVis.get(k);
      let on = false;
      if (!list || !list.length) on = true;
      else if (ex !== null && vr2 !== undefined && vr2 !== Infinity && blockOutOfFlood(k, ex, ey, vr2)) on = true;
      else for (let i = 0; i < list.length; i++) if (lv.isVisible(list[i])) { on = true; break; }
      g.visible = on;
      if (!on || ex === null) continue;
      /* the block's own corner, not its middle: you are close enough to
         see into a house at the near end of a block long before you are
         close to the block */
      const mid = blockMid.get(k);
      const dx = Math.max(0, Math.abs(ex - mid[0]) - BATCH_BLOCK / 2);
      const dy = Math.max(0, Math.abs(ey - mid[1]) - BATCH_BLOCK / 2);
      const bd2 = dx * dx + dy * dy;
      g.children[1].visible = bd2 <= d2;
      /* PAST THE AIR, nothing in this block is drawn at all */
      if (bd2 > far2) { g.visible = false; continue; }
      /* and inside it, the batches that are too small to see. Measured
         from the block's NEAR corner, so a batch is never dropped for
         being in a block whose middle is far when its own end of it is
         not. */
      if (bd2 > LOD_FROM * LOD_FROM) {
        /* ONLY WHEN THE ANSWER COULD HAVE CHANGED. Walking a block's
           twenty batches every frame to decide something that depends
           on a distance which moves by a few units costs more than the
           draw calls it saves — at the default pixel size it saves six
           of five hundred. So it is redone when the block has got a
           quarter nearer or further, or when the pixel size changed,
           and skipped otherwise. */
        const u = g.userData;
        if (u.lodSolid !== minSolid || !(Math.abs(bd2 - u.lodD2) < u.lodD2 * 0.25)) {
          u.lodD2 = bd2; u.lodSolid = minSolid;
          const shell = g.children[0].children;
          for (let i = 0; i < shell.length; i++) {
            const kids = shell[i].children;
            for (let j = 0; j < kids.length; j++) {
              const m = kids[j];
              m.visible = m.userData.area >= bd2 * minSolid;
            }
          }
        }
      } else if (g.userData.lodOff) {
        /* back inside the near ring, and it was not last frame:
           everything on again, once, rather than every frame */
        const shell = g.children[0].children;
        for (let i = 0; i < shell.length; i++) {
          const kids = shell[i].children;
          for (let j = 0; j < kids.length; j++) kids[j].visible = true;
        }
      }
      g.userData.lodOff = bd2 > LOD_FROM * LOD_FROM;
    }
  }

  /** Is every part of this block further from the eye than the flood
   *  was run? Its nearest corner decides — the block pitch is the same
   *  BATCH_BLOCK the mid points were laid out on. */
  function blockOutOfFlood(k, ex, ey, vr2) {
    const mid = blockMid.get(k);
    if (!mid) return false;
    const dx = Math.max(0, Math.abs(ex - mid[0]) - BATCH_BLOCK / 2);
    const dy = Math.max(0, Math.abs(ey - mid[1]) - BATCH_BLOCK / 2);
    return dx * dx + dy * dy > vr2;
  }

  rebuildStatic();

  /* Doors and lifts get their own buffers, thrown away and rebuilt when
     they move. It is a handful of quads — cheaper than any clever
     partial-update scheme, and impossible to get subtly wrong. */
  const dynGroup = new THREE.Group();
  dynGroup.name = 'level-dynamic';
  group.add(dynGroup);

  function rebuild() {
    for (const child of dynGroup.children) {
      child.traverse(o => { if (o.isMesh) { o.geometry.dispose(); o.material.dispose(); } });
    }
    dynGroup.clear();
    const dyn = new BatchSet();
    for (const s of dynamicSectors) addFlats(dyn, level, s, bank);
    for (const l of dynamicLines) addLine(dyn, level, l, bank);
    dynGroup.add(dyn.toGroup(bank));
  }
  rebuild();

  return { group, rebuild, rebuildStatic, blocksOf, applyVisibility,
           blockGroups, dynamicSectors, dynamicLines };
}

/* --------------------------------------------------------------------
   THE ROOF IS NOT A SECTOR

   A sector engine cannot slope a ceiling, and a flat-roofed house is not
   an American house. So a pitched roof is GEOMETRY, generated from the
   building's footprint and pushed into the same BatchSet as everything
   else: two sloped planes and two gable triangles. There is precedent
   for this in the project and it is load-bearing — roofFraming in
   js/ruin.js puts a steel frame over a burnt-out region without any
   sector knowing, and the logo over the entrance is geometry for the
   same reason.

   You never get on a roof. It does not need to be walkable. It needs to
   be a SILHOUETTE, and from the far end of a street the silhouette is
   the entire difference between a town and a row of boxes.

   A sector carries the whole building's roof, not its own share of one:
   `s.roof = { x0, y0, x1, y1, base, rise, tex, gableTex, along }`, where
   `along` is the axis the RIDGE runs down.
   ------------------------------------------------------------------ */
export function roofGeometry(set, s) {
  const r = s.roof;
  if (!r) return 0;
  const { x0, y0, x1, y1, base, rise } = r;
  const tex = r.tex || 'SHINGLE', gtex = r.gableTex || tex;
  const t = bank_h(set, tex), gt = bank_h(set, gtex);
  const b = set.get(tex), gb = set.get(gtex);
  const light = r.light ?? 0.66;
  const sk = r.sky ?? 1;
  const ch = charOf(s);
  const top = base + rise;

  /* the slope length, so the shingles are not stretched up the pitch */
  const halfW = (r.along === 'x' ? (y1 - y0) : (x1 - x0)) / 2;
  const slope = Math.hypot(halfW, rise);

  if (r.along === 'x') {
    const ym = (y0 + y1) / 2;
    /* south face and north face. The map's y is the renderer's minus z. */
    b.quad([[x0, base, -y0], [x1, base, -y0], [x1, top, -ym], [x0, top, -ym]],
           [[0, 0], [(x1 - x0) / t.w, 0], [(x1 - x0) / t.w, slope / t.h], [0, slope / t.h]], light, sk, ch);
    b.quad([[x1, base, -y1], [x0, base, -y1], [x0, top, -ym], [x1, top, -ym]],
           [[0, 0], [(x1 - x0) / t.w, 0], [(x1 - x0) / t.w, slope / t.h], [0, slope / t.h]], light * 0.92, sk, ch);
    /* the gables, east and west */
    gb.tri(x0, base, -y0, 0, 0, x0, top, -ym, halfW / gt.w, rise / gt.h, x0, base, -y1, 2 * halfW / gt.w, 0, light * 0.96, sk, ch);
    gb.tri(x1, base, -y1, 0, 0, x1, top, -ym, halfW / gt.w, rise / gt.h, x1, base, -y0, 2 * halfW / gt.w, 0, light * 0.96, sk, ch);
  } else {
    const xm = (x0 + x1) / 2;
    b.quad([[x0, base, -y1], [x0, base, -y0], [xm, top, -y0], [xm, top, -y1]],
           [[0, 0], [(y1 - y0) / t.w, 0], [(y1 - y0) / t.w, slope / t.h], [0, slope / t.h]], light, sk, ch);
    b.quad([[x1, base, -y0], [x1, base, -y1], [xm, top, -y1], [xm, top, -y0]],
           [[0, 0], [(y1 - y0) / t.w, 0], [(y1 - y0) / t.w, slope / t.h], [0, slope / t.h]], light * 0.92, sk, ch);
    gb.tri(x1, base, -y0, 0, 0, xm, top, -y0, halfW / gt.w, rise / gt.h, x0, base, -y0, 2 * halfW / gt.w, 0, light * 0.96, sk, ch);
    gb.tri(x0, base, -y1, 0, 0, xm, top, -y1, halfW / gt.w, rise / gt.h, x1, base, -y1, 2 * halfW / gt.w, 0, light * 0.96, sk, ch);
  }

  /* ------------------------------------------------------------------
     AND THE UNDERSIDE, for a roof that has nothing under it.

     A roof is ONE-SIDED, like every other surface this file makes: the
     slopes face out and the gables face out, and from underneath a roof
     is not there at all. That is right for every roof over a room —
     what is under it is a ceiling, and you see the ceiling — and it is
     wrong for exactly one thing in the game, which is the CHURCH SPIRE.
     The spire stands on the tower's cornice over a storey that is SHUT,
     so there is no ceiling under it; stand in the churchyard and look up
     at the steeple and you see straight through it into the sky, which
     is what the user reported.

     So a roof may say what its underside is made of, and gets a flat
     cap at its springing, facing DOWN — a boxed soffit, which is what a
     real steeple has and is where a real one stops. Wound the other way
     round from a floor, for the reason set out in addFlats: a surface
     you can only see from the side it is not on is an hour of your
     life. Lit well under, because it never sees the sun. */
  if (r.soffit && r.soffit !== 'NONE') {
    const st = bank_h(set, r.soffit), sb = set.get(r.soffit);
    sb.quad([[x0, base, -y1], [x1, base, -y1], [x1, base, -y0], [x0, base, -y0]],
            [[x0 / st.w, -y1 / st.h], [x1 / st.w, -y1 / st.h],
             [x1 / st.w, -y0 / st.h], [x0 / st.w, -y0 / st.h]], light * 0.62, sk, ch);
  }
  return 1;
}
/* the bank is not handed to roofGeometry, so sizes come off the batch's
   own record of them — set by buildLevelGeometry before any roof is
   drawn. See ROOF_SIZES. */
const ROOF_SIZES = new Map();
export function noteTextureSize(name, w, h) { ROOF_SIZES.set(name, { w, h }); }
function bank_h(set, name) { return ROOF_SIZES.get(name) || { w: 64, h: 64 }; }

/* =====================================================================
   A BOX THAT BELONGS TO NO SECTOR

   A sector engine can do a great many things and there are three it
   cannot do at all: it cannot put anything ABOVE a roof, it cannot put
   anything in FRONT of a wall without carving the ground in front of
   that wall into pieces, and it cannot have two things at the same x,y
   unless one is above the other in the same column. Which rules out, in
   order of how much a town misses them: the chimney, the porch, the
   cornice, the dormer, the downpipe and the shed.

   A ROOF ALREADY HAD THIS PROBLEM and already has the answer — see
   roofGeometry, and `level.roofs`, which is a list of footprints drawn
   as free triangles and owned by no region. This is the same bargain
   for a box: six faces at a place, batched into the block it stands in,
   rebuilt when that block is, lit by a number the map hands over.

   WHAT IT COSTS is what a roof costs: it is not a region, so it is not
   in the portal flood, it holds no fuel, nothing walks on it and
   nothing collides with it. So a box goes ABOVE HEAD HEIGHT or it goes
   flat against a wall you could not walk through anyway, and anything
   that has to stop you is still a sector. Every one of them in this
   town obeys that: see the props in js/maps/town.js.

   THE WINDING, which is the whole of the work. The map's y is the
   renderer's minus z, so a ring that is counter-clockwise on the floor
   plan is clockwise on the screen and every face in this file is wound
   against the plan to compensate (see the long note in addQuad). For a
   box that comes out as: walk the four sides counter-clockwise on the
   plan — south, east, north, west — and wind each one the way addQuad
   winds a line's FRONT, and every face looks out. The lid is the ring
   itself, in plan order, which is what addFlats does for a floor.
   ===================================================================== */

/**
 * One free-standing box.
 *
 * `x0..y1` is its footprint and `z0..z1` its height. `tex` skins the
 * four sides and `topTex` the lid — leave the lid off and the box has
 * no top, which is right for one that goes up under something else.
 */
export function boxGeometry(set, p) {
  const { x0, y0, x1, y1, z0, z1 } = p;
  if (x1 - x0 <= 0 || y1 - y0 <= 0 || z1 - z0 <= 0) return 0;
  /* the colour and fog of the sector it stands in, if the map gave it
     them (a box from MEWD Editor — see level.props in js/editor/doc.js) */
  const was = [PAINT, FOGV];
  PAINT = paintFlat(p.tint); FOGV = p.fog || null;
  try { return boxQuads(set, p); } finally { [PAINT, FOGV] = was; }
}
function boxQuads(set, p) {
  const { x0, y0, x1, y1, z0, z1 } = p;
  const lit = Math.max(0.02, Math.min(1.4, p.light ?? 0.5));
  const sk = p.sky ?? 1, ch = p.char ?? 0;
  let quads = 0;
  if (p.tex && p.tex !== 'NONE') {
    const t = bank_h(set, p.tex), b = set.get(p.tex);
    /* v runs DOWN from the top of the box, the way every wall in this
       file does, so a course of brick starts at the cap and not at
       whatever height the ground happened to be */
    const vB = -(z1 - z0) / t.h;
    /* the four sides, counter-clockwise on the plan */
    for (const [ax, ay, bx, by] of [[x0, y0, x1, y0], [x1, y0, x1, y1],
                                    [x1, y1, x0, y1], [x0, y1, x0, y0]]) {
      const u = Math.hypot(bx - ax, by - ay) / t.w;
      b.quad([[bx, z1, -by], [ax, z1, -ay], [ax, z0, -ay], [bx, z0, -by]],
             [[u, 0], [0, 0], [0, vB], [u, vB]], lit, sk, ch);
      quads++;
    }
  }
  if (p.topTex && p.topTex !== 'NONE') {
    const t = bank_h(set, p.topTex), b = set.get(p.topTex);
    /* the lid, lit as a roof is: it is the face that looks at the sky */
    const tl = Math.max(0.02, Math.min(1.4, p.topLight ?? lit * 1.12));
    const uv = (x, y) => [x / t.w, -y / t.h];
    b.tri(x0, z1, -y0, ...uv(x0, y0), x1, z1, -y0, ...uv(x1, y0), x1, z1, -y1, ...uv(x1, y1), tl, sk, ch);
    b.tri(x0, z1, -y0, ...uv(x0, y0), x1, z1, -y1, ...uv(x1, y1), x0, z1, -y1, ...uv(x0, y1), tl, sk, ch);
    quads++;
  }
  /* AND THE UNDERSIDE, which everything that is a SHELF needs and
     nothing that stands on the ground does.

     A box with no floor to it is a box you can see the inside of from
     underneath, and every side face is wound outward so what you
     actually see is nothing at all — the thing goes transparent the
     moment you walk under it. That is fine for a chimney and wrong for
     a porch roof, a canopy over a fire door or a duct up on sleepers,
     which are the three places in this game you STAND UNDER a free box.

     Wound the other way round from the lid, triangle by triangle, and
     darker by default, because the underside of a slab in daylight is
     the one surface on it that never sees the sky. */
  if (p.botTex && p.botTex !== 'NONE') {
    const t = bank_h(set, p.botTex), b = set.get(p.botTex);
    const bl = Math.max(0.02, Math.min(1.4, p.botLight ?? lit * 0.62));
    const uv = (x, y) => [x / t.w, -y / t.h];
    b.tri(x1, z0, -y1, ...uv(x1, y1), x1, z0, -y0, ...uv(x1, y0), x0, z0, -y0, ...uv(x0, y0), bl, sk, ch);
    b.tri(x0, z0, -y1, ...uv(x0, y1), x1, z0, -y1, ...uv(x1, y1), x0, z0, -y0, ...uv(x0, y0), bl, sk, ch);
    quads++;
  }
  return quads;
}

/* --------------------------------------------------------------------
   THE STREET LAMP IS GEOMETRY

   It was a sprite: an acorn globe on a post, drawn by js/sprites.js,
   fullbright, turned to face you like every other thing in the game.
   It is a PHOTOGRAPH now — a cobra-head road light on a tapered pole,
   cut out of its chroma key by tools/bake-art.mjs — and a photograph of
   a lamp post cannot be a sprite. A sprite turns to face the camera
   plane, and this picture is a pole with a bracket arm reaching out on
   one side of it: as a sprite, the arm would swing round to point at
   you wherever you stood, and a street of them would be a street of
   lamps all pointing at the player.

   So it is a FLAT CUT-OUT, stood in the world at a fixed angle: two
   masked quads (the head tile and the post tile, see STREET_LAMP in
   js/textures.js) in the vertical plane ACROSS the street, the foot of
   the picture on the thing's own x,y and the arm reaching the way the
   thing's angle says, which the town sets toward the road. Walk down
   the street and every lamp on it shows you its profile with its head
   out over the carriageway; stand under one and look across the road
   and it is edge-on, a line, which is what a lamp post is edge-on.
   Both faces are drawn, and — unlike a fence, whose two faces each
   read left to right from their own side — both faces put the SAME u
   at the same point in the world, so the arm reaches over the road
   from whichever side you see it. Seen from behind, the picture is its
   own mirror image, and a lamp post is not chiral.

   It is not on a line. Everything else this file draws is a surface of
   a sector or the boundary between two, and a lamp standing in the
   middle of a pavement is neither; it is a thing, like a headstone,
   and the map lays it as one. The actor is still there for its radius
   (ACTORS.STREETLAMP, which has no sprite any more); this is what you
   see. It goes in the block's SHELL, with the roofs, because a lamp is
   what you read a street by from the far end of it.

   ITS LIGHT IS TWO OTHER THINGS. The pool on the pavement is a sector
   the town lays (walkRun in js/maps/town.js) and this file marks as
   lamp-lit so the shader can turn it cold after dark; the lamp's own
   post is marked the same, being lit by its own light. The flare at
   the luminaire — the point of light and the streak across it that a
   lamp actually is from across a street at night — is js/lamplight.js,
   and hangs on STREET_LAMP.lens.
   ------------------------------------------------------------------ */
export function lampGeometry(set, level, t) {
  const s = level.sectorAt(t.x, t.y);
  if (!s) return 0;
  const S = STREET_LAMP;
  const ax = Math.cos(t.angle), ay = Math.sin(t.angle);
  const z0 = level.floorAt(s, t.x, t.y);
  const lit = Math.max(0.02, Math.min(1.4, s.light)), sk = skyOf(s);
  let quads = 0;
  for (const [tex, p] of [['LAMPHEAD', S.head], ['LAMPPOST', S.post]]) {
    const b = set.get(tex);
    /* where this tile lies along the arm, measured from the foot, and
       how high it stands: the tile's box is a slice of the whole
       picture and the whole picture is `width` by `height` */
    const r0 = (p.u0 - S.foot) * S.width, r1 = (p.u1 - S.foot) * S.width;
    const x1 = t.x + ax * r0, y1 = t.y + ay * r0, x2 = t.x + ax * r1, y2 = t.y + ay * r1;
    const top = z0 + (1 - p.v0) * S.height, bot = z0 + (1 - p.v1) * S.height;
    /* one repeat of the tile is the whole slice: u from 0 at the foot
       end to 1 at the arm end, v from 0 at the top down to -1, which is
       the same way up every wall in this file is (see vAt) */
    const vT = vAt(top, top, top - bot), vB = vAt(bot, top, top - bot);
    b.quad([[x2, top, -y2], [x1, top, -y1], [x1, bot, -y1], [x2, bot, -y2]],
           [[1, vT], [0, vT], [0, vB], [1, vB]], lit, sk, 0, 1);
    b.quad([[x1, top, -y1], [x2, top, -y2], [x2, bot, -y2], [x1, bot, -y1]],
           [[0, vT], [1, vT], [1, vB], [0, vB]], lit, sk, 0, 1);
    quads += 2;
  }
  return quads;
}

/* --------------------------------------------------------------------
   Floors and ceilings

   Flats are aligned to the world grid, not to the sector, which is why
   Doom floors run continuously through a doorway instead of restarting
   at every threshold. u = x/64, v = y/64, and nothing else to decide.
   ------------------------------------------------------------------ */
/* --------------------------------------------------------------------
   A TRIANGLE CUT BY THE RIDGE

   A gable is two planes meeting along a line, and a triangle that
   straddles that line cannot be drawn as one triangle at any height:
   its three corners are on the roof and its middle is not. So it is cut
   into the pieces either side, which is one or three triangles, and
   every corner of every piece then lands on the surface exactly.

   For the rectangles this map is made of it fires twice per roof and
   the rest of the time not at all.
   ------------------------------------------------------------------ */
function splitAtRidge(tri, axis, mid) {
  const u = p => (axis === 'x' ? p[1] : p[0]);
  const side = p => (u(p) > mid ? 1 : u(p) < mid ? -1 : 0);
  const sg = tri.map(side);
  if (sg[0] * sg[1] >= 0 && sg[1] * sg[2] >= 0 && sg[0] * sg[2] >= 0) return [tri];
  /* the lone corner on its own side, and the two crossings */
  let k = 0;
  for (let i = 0; i < 3; i++) if (sg[i] !== 0 && sg[(i + 1) % 3] !== sg[i] && sg[(i + 2) % 3] !== sg[i]) k = i;
  const a = tri[k], b = tri[(k + 1) % 3], c = tri[(k + 2) % 3];
  const cut = (p, q) => {
    const t = (mid - u(p)) / (u(q) - u(p));
    return [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t];
  };
  const ab = cut(a, b), ac = cut(a, c);
  return [[a, ab, ac], [ab, b, c], [ab, c, ac]];
}

/** The triangles of a surface, cut at the ridge if it has one. */
function surfaceTris(pts, tris, slope) {
  const flat = tris.map(([a, b, c]) => [[pts[a].x, pts[a].y], [pts[b].x, pts[b].y], [pts[c].x, pts[c].y]]);
  if (!slope || slope.kind !== 'gable') return flat;
  const out = [];
  for (const t of flat) for (const piece of splitAtRidge(t, slope.axis, slope.mid)) out.push(piece);
  return out;
}

function addFlats(set, level, s, bank) {
  /* A SECTOR WITH HOLES IN IT — a room drawn inside another, in a map
     from MEWD Editor (js/editor/doc.js) — is one ring bridged out to each
     hole and back by a slit, because that is what a sector is here; but
     a triangulator handed that ring can fill the holes in, and a pit
     then has the ground drawn over the top of it. So a sector that says
     where its holes are is triangulated from its outline AND its holes,
     which is what the triangulator is for; the slit ring is still what
     everything else in the engine reads. */
  const V2 = p => new THREE.Vector2(p[0], p[1]);
  const outline = s.flatOuter ? s.flatOuter.map(V2) : s.poly.map(V2);
  const holes = (s.flatHoles || []).map(h => h.map(V2));
  const pts = holes.length ? outline.concat(...holes) : outline;
  let tris;
  try { tris = THREE.ShapeUtils.triangulateShape(outline, holes); }
  catch (e) { console.warn('sector', s.index, 'would not triangulate', e); return; }

  const sky = s.ceilTex === 'SKY';
  const lit = s.light, sk = skyOf(s), ch = charOf(s);
  /* the pool of pavement under a street lamp — see lampGeometry */
  const lp = s.lampLit ? 1 : 0;

  PAINT = paintFlat(s.tint?.floor); FOGV = fogOf(s);
  if (s.floorTex && s.floorTex !== 'NONE') {
    const t = bank.get(s.floorTex);
    const b = set.get(s.floorTex);   // one set per block, so the name is enough
    /* Floors tile from the world origin unless the sector says
       otherwise; see floorAnchor in js/level.js for the one that does. */
    const ax = s.floorAnchor ? s.floorAnchor[0] : 0;
    const ay = s.floorAnchor ? s.floorAnchor[1] : 0;
    /* and its height is a number until it is a slope, in which case it
       is a number PER CORNER — see A SLOPE in js/level.js */
    const zf = (x, y) => level.floorAt(s, x, y);
    for (const [p0, p1, p2] of surfaceTris(pts, tris, s.slopeFloor)) {
      /* Reversed relative to the map winding: the ring is
         counter-clockwise in map space, and the map's y becomes the
         renderer's MINUS z (see addQuad), which reverses it again. A
         floor you can only see from underneath is a floor you will spend
         an hour debugging. */
      b.tri(
        p0[0], zf(p0[0], p0[1]), -p0[1], (p0[0] - ax) / t.w, -(p0[1] - ay) / t.h,
        p1[0], zf(p1[0], p1[1]), -p1[1], (p1[0] - ax) / t.w, -(p1[1] - ay) / t.h,
        p2[0], zf(p2[0], p2[1]), -p2[1], (p2[0] - ax) / t.w, -(p2[1] - ay) / t.h,
        lit, sk, ch, lp);
    }
  }

  /* A sky ceiling is a hole, not a surface — nothing is drawn and the
     background shows through. */
  const zc = (x, y) => level.ceilAt(s, x, y);
  const ceilTris = surfaceTris(pts, tris, s.slopeCeil);
  PAINT = paintFlat(s.tint?.ceil); FOGV = fogOf(s);
  if (!sky && s.ceilTex && s.ceilTex !== 'NONE') {
    const t = bank.get(s.ceilTex);
    const b = set.get(s.ceilTex);
    for (const [p0, p1, p2] of ceilTris) {
      b.tri(
        p2[0], zc(p2[0], p2[1]), -p2[1], p2[0] / t.w, -p2[1] / t.h,
        p1[0], zc(p1[0], p1[1]), -p1[1], p1[0] / t.w, -p1[1] / t.h,
        p0[0], zc(p0[0], p0[1]), -p0[1], p0[0] / t.w, -p0[1] / t.h,
        lit, sk, ch);
    }
  }

  /* AND THE SAME SURFACE FROM ABOVE, which is a roof. A ceiling is
     drawn facing down and nothing in this engine ever wanted otherwise,
     because nothing else was the top of a building. One more pass over
     the same triangles wound the other way, wearing the roof's own
     skin, and the shingle you see from the street is the underside of
     the attic you would see from inside it. */
  PAINT = null; FOGV = null;
  if (s.roofTex && s.roofTex !== 'NONE') {
    const t = bank.get(s.roofTex);
    const b = set.get(s.roofTex);
    const rl = Math.min(1.2, (s.roofLight ?? s.light));
    for (const [p0, p1, p2] of ceilTris) {
      b.tri(
        p0[0], zc(p0[0], p0[1]), -p0[1], p0[0] / t.w, -p0[1] / t.h,
        p1[0], zc(p1[0], p1[1]), -p1[1], p1[0] / t.w, -p1[1] / t.h,
        p2[0], zc(p2[0], p2[1]), -p2[1], p2[0] / t.w, -p2[1] / t.h,
        rl, 1, ch);
    }
  }
}

/* --------------------------------------------------------------------
   Walls
   ------------------------------------------------------------------ */
function addLine(set, level, l, bank, pick = null) {
  const into = pick || (() => set);
  const oneSided = !l.frontCol.length || !l.backCol.length;
  if (oneSided && !l.frontCol.length && !l.backCol.length) return;

  /* One-sided: a plain wall, floor to ceiling, seen from the column that
     owns it — a storey at a time, so the outside of a three-storey house
     that happens to back onto nothing is still three bands of brick. */
  if (oneSided) {
    const col = l.frontCol.length ? l.frontCol : l.backCol;
    const facingFront = l.frontCol.length > 0;
    for (let i = 0; i < col.length; i++) {
      const s = level.sectors[col[i]];
      /* EACH STOREY IN ITS OWN SKIN. The line carries one middle
         texture, decided from the GROUND sector — which is the right
         answer for the thousand walls that are a column of one, and is
         the only answer that was ever needed. A roof is not made of
         what the kitchen under it is made of, so a storey above the
         ground wears its own; the ground keeps the line's, which is
         what a map file reaches in and sets by hand. */
      const sd = sideOf(l, s);
      const tex = sd.mid || (i === 0 ? (l.middle || 'WALL') : (s.wallTex || l.middle || 'WALL'));
      if (!tex || tex === 'NONE') continue;
      const dst = into(s);
      const L1 = sd.l;
      const peg = pegOf(L1, 'middle', s.floor, s.ceil, s, bank.get(tex).h);
      PAINT = paintWall(s); FOGV = fogOf(s);
      if (s.slopeCeil || s.slopeFloor) {
        emitWall(dst, L1, bank, tex, (x, y) => [level.floorAt(s, x, y), level.ceilAt(s, x, y)],
                 facingFront, peg, s.light + l.contrast, skyOf(s), charOf(s),
                 [s.slopeCeil, s.slopeFloor]);
      } else {
        addQuad(dst, L1, bank, tex, s.floor, s.ceil, facingFront, peg,
                s.light + l.contrast, skyOf(s), charOf(s));
      }
    }
    PAINT = null; FOGV = null;
    return;
  }

  /* TWO-SIDED: every interval of z where exactly one of the two columns
     is open, which is Doom's upper and lower for a column of one and
     three bands of brick with two ribbons of glass between them for a
     terrace. See lineBands in js/level.js — this function only draws
     what that decided. */
  const bands = l.bands || [];
  for (let i = 0; i < bands.length; i++) {
    const bd = bands[i];
    if (!bd.tex || bd.tex === 'NONE') continue;
    /* the face looking into the open side wears that side's texture */
    const sdB = sideOf(l, bd.open);
    const bandTex = (bd.kind === 'upper' ? sdB.upper : sdB.lower) || bd.tex;
    /* A step between two patches of sky draws nothing: there is no
       surface there, only two different heights of nothing. */
    if (bd.kind === 'upper' && bd.open.ceilTex === 'SKY' && bd.from.ceilTex === 'SKY') continue;
    const s = bd.open;
    /* a band between a roof and anything is the roof's, so a gable end
       is shell even where the wall under it is not */
    const dst = (bd.open.roofTex || bd.from.roofTex) ? into(bd.open.roofTex ? bd.open : bd.from) : into(s);
    const peg = pegOf(sdB.l, bd.kind, bd.z0, bd.z1, s, bank.get(bandTex).h);
    /* THE GABLE FACES THE STREET. An upper band over a sector whose
       ceiling is the sky is a wall rising above outdoor ground — the
       gable end of a roof, over the plinth at its foot, whose ceiling
       is put at the eaves so that this band exists at all. Its "open"
       side is the attic, and nobody is in the attic: the side that
       looks at it is the shut one, from under the sky. So it is wound
       to face that side and lit by it, or it is a triangle of board
       facing into the roof space at the attic's sixteenth of a light,
       and from the pavement the house has no gable — which is what it
       had until somebody stood on the pavement. Doom, with no slopes,
       drew nothing here at all; the rule above is the other half of
       that. */
    const gable = bd.kind === 'upper' && bd.from.ceilTex === 'SKY';
    const lit = gable ? bd.from : s;
    const facing = gable ? !bd.openFront : bd.openFront;
    const ch = Math.max(charOf(s), charOf(lit));
    /* WHERE A SLOPE IS IN PLAY the band is not an interval, it is an
       interval AT A POINT. Asked of the same two sectors the band was
       worked out from, so the flat case gives back the same numbers. */
    const emit = (face, light) => {
      PAINT = paintWall(face === bd.openFront ? s : lit, bd.z0, bd.z1); FOGV = fogOf(face === bd.openFront ? s : lit);
      if (edgeSlope(bd.e0) || edgeSlope(bd.e1))
        emitWall(dst, sdB.l, bank, bandTex, (x, y) => bandEdges(level, bd, x, y), face, peg,
                 light + l.contrast, skyOf(lit), ch, [edgeSlope(bd.e0), edgeSlope(bd.e1)]);
      else
        addQuad(dst, sdB.l, bank, bandTex, bd.z0, bd.z1, face, peg,
                light + l.contrast, skyOf(lit), ch);
    };
    emit(facing, lit.light);
    /* AND A ROOF SPACE YOU CAN SEE THE INSIDE OF GETS THE INSIDE OF ITS
       GABLE TOO. The rule above winds the gable to face the street
       because the other side of it is an attic and nobody is in an
       attic. A church is the one building where that is false: its nave
       is open to the rafters, so the roof storey has a ceiling you are
       looking at from a pew (see soffit in js/maps/town.js), and the
       far end of it was a triangle of sky — the gable drawn once,
       facing away from the only person who could see it. Drawn the
       other way as well when the roof space is one with a ceiling, and
       lit by that ceiling rather than by the sky outside. It costs the
       houses nothing: their attics say ceilTex NONE and never ask. */
    if (gable && bd.open.ceilTex && bd.open.ceilTex !== 'NONE') emit(!facing, bd.open.light);
  }
  PAINT = null; FOGV = null;

  /* A middle texture on a two-sided line is the thing IN the hole: a
     grating, a shop window, a wire shelf you can see through. Drawn both
     ways, masked, spanning the open gap — and once per hole, because a
     house against a street has one hole per storey and each of them is
     a window.

     UNLESS IT IS SHORTER THAN THE HOLE, which is what `midHeight` is
     for. A grating fills its opening and a shop window fills its
     opening, so the gap is the right answer for both. A FENCE is not:
     it is eight feet of chain link standing on a line between two
     patches of wood that are open to the sky, and spanning the gap
     there means stretching the mesh from the ground to the cloud base
     and tiling it five times on the way up. So a line may say how tall
     the thing standing in it is, measured up from the floor it stands
     on, and the opening stays the LIMIT rather than the answer. */
  if ((l.middle && l.middle !== 'NONE') || (l.sides && Object.values(l.sides).some(x => x.midTex))) {
    const holes = l.holes || [];
    for (let i = 0; i < holes.length; i++) {
      const h = holes[i];
      /* A HOLE BETWEEN TWO ROOFS IS THE SAME ROOF, and nothing stands
         in it. Every column in a town building ends in the roof storey,
         so a window's own line — glass in the hole between its sill
         and its head — also has the hole between its roof and the
         room's roof over it, and the pane was being hung there too: a
         sheet of coloured glass above the eaves over every window. */
      if (h.front.roofTex && h.back.roofTex && !h.front.editorRoof && !h.back.editorRoof) continue;
      /* A WALL IN SOME OF THE OPENINGS ONLY: an edited map in layers
         walls the ground floor of a house and not the open terrace over
         it (see compileCore in js/editor/doc.js) */
      if (l.midZ && !l.midZ.some(([z0, z1]) => Math.abs(z0 - h.z0) < 1 && Math.abs(z1 - h.z1) < 1)) continue;
      const bot = h.z0;
      const top = Math.min(h.z1, bot + (l.midHeight ?? Infinity));
      if (top <= bot) continue;
      /* each face its own side's middle, or the line's */
      for (const [face, sec] of [[true, h.front], [false, h.back]]) {
        const sd = sideOf(l, sec);
        const tex = sd.mid || l.middle;
        if (!tex || tex === 'NONE') continue;
        const th = bank.get(tex).h * (sd.l.yscale || 1);
        if (l.midOnce && l.midHeight == null) {
          /* DOOM'S RULE for a masked middle: drawn ONCE, its own height,
             never tiled up the opening — a 128-tall treeline is 128 tall
             and a DR1 door is a door, however high the gap. It stands
             on the floor (an open world's gaps go up to the cloud base,
             and a fence hung from there is in the sky); the y offset
             lifts it; the opening clips it */
          const peg = bot + th + sd.l.yoff;
          const b0 = Math.max(bot, peg - th), b1 = Math.min(top, peg);
          if (b1 <= b0) continue;
          PAINT = paintWall(sec, b0, b1); FOGV = fogOf(sec);
          addQuad(set, sd.l, bank, tex, b0, b1, face, peg, sec.light + l.contrast, skyOf(sec), charOf(sec));
          continue;
        }
        const peg = l.pegMiddle === 'bottom' ? bot + th : top;
        PAINT = paintWall(sec, bot, top); FOGV = fogOf(sec);
        addQuad(set, sd.l, bank, tex, bot, top, face, peg + sd.l.yoff, sec.light + l.contrast, skyOf(sec), charOf(sec));
      }
      PAINT = null; FOGV = null;
    }
  }
}

/**
 * A WALL, IN AS MANY PIECES AS THE SLOPES OVER IT NEED.
 *
 * A quad's top edge is a straight line between its two ends, and a
 * gable is not: the ridge is a crease, and a wall that runs under one —
 * the end wall of a house, which goes from eaves up over the ridge and
 * down to the other eaves — is a TRIANGLE and not a trapezium. So the
 * line is cut where the ridge crosses it and each piece is a quad
 * again. At most one cut per slope and none at all for every wall in
 * the supermarket.
 */
function emitWall(set, l, bank, tex, zAt, facingFront, peg, light, sk, ch, slopes) {
  const cuts = [];
  for (const sl of slopes) {
    if (!sl || sl.kind !== 'gable') continue;
    const a = sl.axis === 'x' ? l.y1 : l.x1;
    const b = sl.axis === 'x' ? l.y2 : l.x2;
    if ((a - sl.mid) * (b - sl.mid) >= 0 || Math.abs(b - a) < 1e-9) continue;
    const t = (sl.mid - a) / (b - a);
    if (t > 1e-4 && t < 1 - 1e-4) cuts.push(t);
  }
  cuts.sort((p, q) => p - q);
  let prev = 0;
  const at = t => {
    const x = l.x1 + (l.x2 - l.x1) * t, y = l.y1 + (l.y2 - l.y1) * t;
    return zAt(x, y);
  };
  for (const c of [...cuts, 1]) {
    const e0 = at(prev), e1 = at(c);
    addQuad(set, l, bank, tex, [e0[0], e1[0]], [e0[1], e1[1]], facingFront, peg, light, sk, ch,
            prev === 0 && c === 1 ? null : [prev, c]);
    prev = c;
  }
}

/** The bottom and top of a band at a point: each edge is the surface
 *  lineBands cut it at — some storey's floor or ceiling — asked at the
 *  point, so a sloped ceiling gives its own height there and a flat one
 *  gives the number lineBands already had. The first version worked the
 *  edges out again from the band's kind, and got the top of a lower
 *  band wrong wherever the shut storey it was named for was not the
 *  storey that actually bounded it: a window under a roof came out as
 *  brick from the sill to the eaves. */
function edgeAt(level, e, x, y) {
  return e.which === 'floor' ? level.floorAt(e.s, x, y) : level.ceilAt(e.s, x, y);
}
function edgeSlope(e) { return e.which === 'floor' ? e.s.slopeFloor : e.s.slopeCeil; }
function bandEdges(level, bd, x, y) {
  return [edgeAt(level, bd.e0, x, y), edgeAt(level, bd.e1, x, y)];
}

/* Where the top edge of the texture sits, in world height. */
function pegOf(l, which, zLow, zHigh, sector, texH) {
  texH *= l.yscale || 1;
  let peg;
  if (which === 'upper') {
    /* 'bottom' nails the texture to the lower (moving) ceiling, so a
       door's face travels with the door. This is the default because
       doors are the common case. */
    peg = (l.pegUpper === 'top') ? zHigh : zLow + texH;
  } else if (which === 'lower') {
    /* 'top' nails it to the top of the step, which is what a counter, a
       kerb and a pallet all want. Doom's own default measured down from
       the ceiling instead; that is available, but it is not the one you
       reach for. */
    peg = (l.pegLower === 'ceiling') ? sector.ceil : zHigh;
  } else {
    peg = (l.pegMiddle === 'bottom') ? zLow + texH : zHigh;
  }
  return peg + l.yoff;
}

/**
 * One wall quad.
 *
 * `facingFront` decides the winding. The front sector is on the RIGHT of
 * v1->v2, so a quad wound v1,v2 faces LEFT — the back. Getting this
 * backwards gives you a level you can see straight through from outside
 * and not at all from inside.
 */
/* How much sky a sector's surfaces see. Declared per sector so a canopy
   can be half way between a car park and a corridor, which is what a
   canopy is; falls back to the plain outdoor/indoor answer. */
function skyOf(s) { return s ? (s.sky ?? (s.outdoor ? 1 : 0)) : 0; }
/* Charred is halfway and gutted is all the way, because a gutted region
   is not a darker charred one — it is the same surface with rather more
   of it still alight. */
export function charOf(s) { return s ? (s.gutted ? 1 : s.charred ? 0.55 : 0) : 0; }

/**
 * One wall quad.
 *
 * `zBot` and `zTop` may each be a number or a PAIR — the height at v1
 * and the height at v2 — which is what a wall under a sloped ceiling
 * needs and is the whole of what a gable end is. A pair collapses to
 * the flat case the moment both of its ends agree, which for every wall
 * built before there were roofs they do.
 */
/* ---------------------------------------------------------------------
   A WALL WITH A HOLE IN IT IS SEVERAL WALLS

   addQuad already knew how to draw PART of a line — `span`, which was
   put in so that the wall under a gable could be drawn in the two
   pieces either side of the ridge, with the texture still reading as
   one length of brick across both. A hole is that same idea in two
   axes, and it needs nothing new from this file except the decision to
   ask.

   So this is the wrapper: if the line has anything missing (see
   js/breach.js), draw the pieces that survive instead of the whole
   band, each with its own span and its own height, and the u it wears
   still runs from the line's own start — so a hole punched through the
   middle of a shopfront leaves the brick either side of it lined up
   with the brick above and below.

   ONLY FLAT BANDS. A band with a sloped end is an interval that changes
   along the line, and cutting a rectangle out of a trapezoid is a
   different piece of arithmetic for the sake of the gables and the
   roof soffits — which are the highest surfaces in the game and the
   ones a beam is least often pointed at. A sloped band takes the hit
   and stays whole; everything at head height does not slope.

   AND A WALL THAT HAS NOT BEEN SHOT COSTS ONE PROPERTY READ. breachPieces
   returns null the moment it finds no list, which is every line in the
   game until something happens to one. */
const BREACH_SCRATCH = [];
/* and the standing storeys of one wall, floor and ceiling in pairs, which
   is read once per shot-through line per rebuild — see below */
const BANDS = [];
function addQuad(set, l, bank, texName, zBot, zTop, facingFront, peg, light, sk = 0, ch = 0, span = null) {
  if (l.breach && l.breach.length && !Array.isArray(zBot) && !Array.isArray(zTop)) {
    const s0 = span ? span[0] : 0, s1 = span ? span[1] : 1;
    const parts = breachPieces(l, zBot, zTop, s0, s1, BREACH_SCRATCH);
    if (parts) {
      /* THE EDGE OF A HOLE IS CHARRED AND THE REST OF THE WALL IS NOT.
         Brick that now ends at a hole ends at a burnt edge; brick forty
         metres along the same shopfront does not. The split says which
         is which — see the note on the fifth number in breachPieces —
         and `ch` is what js/material.js darkens a surface by. */
      for (let i = 0; i < parts.length; i++) {
        const q = parts[i];
        addQuadRaw(set, l, bank, texName, q[2], q[3], facingFront, peg, light, sk,
                   q[4] ? Math.max(ch, 0.72) : ch, [q[0], q[1]]);
      }
      return;
    }
  }
  addQuadRaw(set, l, bank, texName, zBot, zTop, facingFront, peg, light, sk, ch, span);
}

function addQuadRaw(set, l, bank, texName, zBot, zTop, facingFront, peg, light, sk = 0, ch = 0, span = null) {
  const b1 = Array.isArray(zBot) ? zBot[0] : zBot, b2 = Array.isArray(zBot) ? zBot[1] : zBot;
  const t1 = Array.isArray(zTop) ? zTop[0] : zTop, t2 = Array.isArray(zTop) ? zTop[1] : zTop;
  /* nothing at either end is nothing; a wall that is a triangle — the
     gable at the end of a terrace — has one end of no height at all and
     is still a wall */
  if (t1 - b1 <= 1e-6 && t2 - b2 <= 1e-6) return;
  const t = bank.get(texName);
  const b = set.get(texName);
  /* PART OF A LINE, where a ridge crosses it. See emitWall: a gable is
     two slopes and a quad is one, so the wall under one is drawn in the
     two pieces either side of the ridge. `span` is where along the line
     this piece runs, and the u it wears keeps running from the line's
     own start so the two pieces are one length of brick. */
  const s0 = span ? span[0] : 0, s1 = span ? span[1] : 1;
  const x1 = l.x1 + (l.x2 - l.x1) * s0, y1 = l.y1 + (l.y2 - l.y1) * s0;
  const x2 = l.x1 + (l.x2 - l.x1) * s1, y2 = l.y1 + (l.y2 - l.y1) * s1;
  const len = l.len;

  /* u runs from whichever end this side measures from. Doom starts the
     front side's texture at v1 and the back side's at v2, so a two-sided
     line's two faces both read left-to-right from their own viewpoint. */
  /* THE SCALE: how many units of wall one repeat of the texture covers,
     as a multiple of its own size — 2 is twice as big, half as often */
  const tw = t.w * (l.xscale || 1), th = t.h * (l.yscale || 1);
  const u0 = (l.xoff + len * s0) / tw;
  const u1 = (l.xoff + len * s1) / tw;
  const vB1 = vAt(b1, peg, th), vT1 = vAt(t1, peg, th);
  const vB2 = vAt(b2, peg, th), vT2 = vAt(t2, peg, th);
  const lit = Math.max(0.02, Math.min(1.4, light));

  /* THE MAP'S Y IS THE RENDERER'S MINUS Z, and it has to be, everywhere.
     A map with x east and y north laid onto a renderer with x east and z
     north is LEFT-handed: everything still works — movement, collision,
     the camera, sprites, all of it self-consistent — and the picture is a
     mirror image of the floor plan. Nobody notices for months, because
     nothing in a supermarket is chiral. Then you put the words TO LET on
     a shopfront and they come out backwards, and so does the fascia, and
     so does the sign at the mouth of the car park. All three of those
     signs have since come down; the logo over the entrance has not, and
     it would mirror just as happily.

     Negating y is the fix, and negating y reverses the screen winding of
     every polygon, so every winding here and in addFlats is reversed to
     match. That is why the quads below read top-to-bottom rather than
     bottom-to-top: it is not a style, it is the other half of the sign
     change. */
  if (facingFront) {
    b.quad(
      [[x2, t2, -y2], [x1, t1, -y1], [x1, b1, -y1], [x2, b2, -y2]],
      [[u1, vT2],     [u0, vT1],     [u0, vB1],     [u1, vB2]],
      lit, sk, ch);
  } else {
    b.quad(
      [[x1, t1, -y1], [x2, t2, -y2], [x2, b2, -y2], [x1, b1, -y1]],
      [[u1, vT1],     [u0, vT2],     [u0, vB2],     [u1, vB1]],
      lit, sk, ch);
  }
}
