/* =====================================================================
   MEWD — laying out a shop in rectangles
   =====================================================================

   MapBuilder welds two sectors into a doorway when they share an EDGE,
   and "share an edge" means share both its endpoints. So a long wall
   with a shop floor on one side and three rooms on the other has to be
   drawn as three edges, with a vertex where each room starts and stops.
   Every Doom mapper has done this by hand and every Doom mapper has got
   it wrong at least once, because the vertex you forgot produces a
   sector that is silently inside-out somewhere across the map.

   So it is done here instead. Give it rectangles; it finds, for every
   edge, which other rectangles abut part of it, and splits that edge at
   their corners. What comes out is a set of polygons whose shared edges
   agree exactly, by construction.

   WALLS ARE THE GAPS. Two rectangles that touch become an opening
   between two rooms — that is what touching MEANS here. So a wall is
   drawn by NOT putting a rectangle there: leave sixteen units between
   two rooms and the void between them is the wall, with a one-sided
   line facing into each. A doorway is a small rectangle bridging that
   gap, which is exactly what a doorway is in a real building.

   Everything below follows from that one rule, and it is the rule that
   makes the shop layout in sellwrong.js readable as a floor plan.

   AND A RECT MAY BE A COLUMN. Give it `storeys: [ground, first, second]`
   and it becomes that many sectors over one outline instead of one — the
   townhouse, the school, the choir loft over the narthex. The splitting
   below does not change by a character, because splitting is about where
   the corners are and a column has one set of corners.

   AND A SQUARE MAY BE AN ARC. Give it `arc: { centre, disc, rest }` and
   it becomes TWO sectors: the quarter circle centred on the corner
   `centre` names ('SW', 'SE', 'NE', 'NW'), with the square's side for
   its radius, wearing `disc`; and the curved triangle left over at the
   opposite corner, wearing `rest`. The two edges of the square that meet
   at the centre belong to the disc whole and the other two to the rest
   whole, so every neighbour still sees a rectangle and splits against it
   exactly as before — which is what lets a kerb go round a corner in a
   map made of rectangles. A sidewalk's corner is a square with the disc
   the sidewalk and the rest the road; the outside of a bend in the road
   is a square with the disc the road and the rest the sidewalk.
   ===================================================================== */

/* A BUCKET GRID OVER THE RECTS, because both loops below are otherwise
   every rect against every other rect. Eleven shop units and a car park
   is a thousand rects and a million comparisons, which nobody notices.
   A town is fifteen thousand rects and two hundred and twenty-five
   million, which is ten seconds of a half-second budget. Bucketing turns
   both into a scan of the few rects that are actually nearby, and it
   changes no answer — it only stops asking rects on the other side of
   the town whether they abut this doorway. */
const CELL = 512;

export class RectMap {
  constructor(mb) { this.mb = mb; this.rects = []; this._buckets = null; this._stamp = 0; }

  _index() {
    this._buckets = new Map();
    for (const r of this.rects) {
      r._stamp = 0;
      for (let cy = Math.floor(r.y0 / CELL); cy <= Math.floor((r.y1 - 1e-9) / CELL); cy++)
        for (let cx = Math.floor(r.x0 / CELL); cx <= Math.floor((r.x1 - 1e-9) / CELL); cx++) {
          const k = cx + ',' + cy;
          let b = this._buckets.get(k);
          if (!b) this._buckets.set(k, b = []);
          b.push(r);
        }
    }
  }

  /** Every rect whose bucket touches this box, each once. */
  _near(x0, y0, x1, y1, out) {
    out.length = 0;
    const st = ++this._stamp;
    for (let cy = Math.floor(y0 / CELL); cy <= Math.floor(y1 / CELL); cy++)
      for (let cx = Math.floor(x0 / CELL); cx <= Math.floor(x1 / CELL); cx++) {
        const b = this._buckets.get(cx + ',' + cy);
        if (!b) continue;
        for (let i = 0; i < b.length; i++) {
          if (b[i]._stamp === st) continue;
          b[i]._stamp = st;
          out.push(b[i]);
        }
      }
    return out;
  }

  /** x0<x1, y0<y1. Props go straight through to MapBuilder.sector. */
  add(x0, y0, x1, y1, props = {}) {
    if (x1 <= x0 || y1 <= y0) throw new Error(`degenerate rect ${x0},${y0} ${x1},${y1}`);
    const r = { x0, y0, x1, y1, props, sector: -1 };
    this.rects.push(r);
    return r;
  }

  /** Named bands, so a floor plan can be written as "x band 4 to 6". */
  static bands(list) {
    return {
      v: list,
      at: i => list[i],
      span: (a, b) => [list[a], list[b]],
    };
  }

  _overlap(a0, a1, b0, b1) { return Math.min(a1, b1) - Math.max(a0, b0) > 1e-6; }

  /** Split points along one edge of `r`, from every rect that abuts it. */
  _splits(r, side) {
    const out = new Set();
    /* a hair either side of the edge in question, and nothing else on
       the map can possibly abut it */
    const E = 1;
    const near = this._near(
      side === 'left' ? r.x0 - E : side === 'right' ? r.x1 - E : r.x0,
      side === 'bottom' ? r.y0 - E : side === 'top' ? r.y1 - E : r.y0,
      side === 'left' ? r.x0 + E : side === 'right' ? r.x1 + E : r.x1,
      side === 'bottom' ? r.y0 + E : side === 'top' ? r.y1 + E : r.y1,
      this._splitScratch || (this._splitScratch = []));
    for (const o of near) {
      if (o === r) continue;
      if (side === 'bottom') {
        if (o.y1 !== r.y0 || !this._overlap(r.x0, r.x1, o.x0, o.x1)) continue;
        if (o.x0 > r.x0 && o.x0 < r.x1) out.add(o.x0);
        if (o.x1 > r.x0 && o.x1 < r.x1) out.add(o.x1);
      } else if (side === 'top') {
        if (o.y0 !== r.y1 || !this._overlap(r.x0, r.x1, o.x0, o.x1)) continue;
        if (o.x0 > r.x0 && o.x0 < r.x1) out.add(o.x0);
        if (o.x1 > r.x0 && o.x1 < r.x1) out.add(o.x1);
      } else if (side === 'left') {
        if (o.x1 !== r.x0 || !this._overlap(r.y0, r.y1, o.y0, o.y1)) continue;
        if (o.y0 > r.y0 && o.y0 < r.y1) out.add(o.y0);
        if (o.y1 > r.y0 && o.y1 < r.y1) out.add(o.y1);
      } else {
        if (o.x0 !== r.x1 || !this._overlap(r.y0, r.y1, o.y0, o.y1)) continue;
        if (o.y0 > r.y0 && o.y0 < r.y1) out.add(o.y0);
        if (o.y1 > r.y0 && o.y1 < r.y1) out.add(o.y1);
      }
    }
    return [...out].sort((a, b) => a - b);
  }

  /** Turn every rectangle into a sector. Counter-clockwise, starting at
   *  the south-west corner and going east along the bottom. */
  build() {
    /* An overlap is always a mistake and always produces a level with a
       room you can stand in two of at once. Cheap to check, miserable to
       find later. */
    this._index();
    const hits = [];
    for (const a of this.rects) {
      for (const b of this._near(a.x0, a.y0, a.x1, a.y1, hits)) {
        if (b === a) continue;
        if (this._overlap(a.x0, a.x1, b.x0, b.x1) && this._overlap(a.y0, a.y1, b.y0, b.y1))
          throw new Error(`rects overlap: [${a.x0},${a.y0},${a.x1},${a.y1}] and [${b.x0},${b.y0},${b.x1},${b.y1}]`);
      }
    }

    for (const r of this.rects) {
      const poly = [];
      poly.push([r.x0, r.y0]);
      for (const x of this._splits(r, 'bottom')) poly.push([x, r.y0]);
      poly.push([r.x1, r.y0]);
      for (const y of this._splits(r, 'right')) poly.push([r.x1, y]);
      poly.push([r.x1, r.y1]);
      for (const x of this._splits(r, 'top').slice().reverse()) poly.push([x, r.y1]);
      poly.push([r.x0, r.y1]);
      for (const y of this._splits(r, 'left').slice().reverse()) poly.push([r.x0, y]);
      if (r.props.arc) {
        /* AN ARC: two sectors out of one square. The ring above runs
           counter-clockwise from the south-west corner; turned to start
           at the centre corner it is four edges E1..E4, E1 leaving the
           centre and E4 returning to it. The disc is E1, the arc from
           E1's far end round to E4's near end, and E4; the rest is E2,
           E3 and the same arc the other way. Both wind counter-clockwise
           because the ring did. */
        const { arc, ...common } = r.props;
        const side = Math.min(r.x1 - r.x0, r.y1 - r.y0);
        if (Math.abs((r.x1 - r.x0) - (r.y1 - r.y0)) > 1e-6) throw new Error(`an arc must be a square: ${r.x0},${r.y0} ${r.x1},${r.y1}`);
        const corners = { SW: [r.x0, r.y0], SE: [r.x1, r.y0], NE: [r.x1, r.y1], NW: [r.x0, r.y1] };
        const C = corners[arc.centre];
        if (!C) throw new Error(`an arc is centred on SW, SE, NE or NW, not ${arc.centre}`);
        /* the four edges, each as its points from start to end, with
           the splits — the same points the plain polygon has */
        const E = [
          [[r.x0, r.y0], ...this._splits(r, 'bottom').map(x => [x, r.y0]), [r.x1, r.y0]],
          [[r.x1, r.y0], ...this._splits(r, 'right').map(y => [r.x1, y]), [r.x1, r.y1]],
          [[r.x1, r.y1], ...this._splits(r, 'top').slice().reverse().map(x => [x, r.y1]), [r.x0, r.y1]],
          [[r.x0, r.y1], ...this._splits(r, 'left').slice().reverse().map(y => [r.x0, y]), [r.x0, r.y0]],
        ];
        const start = { SW: 0, SE: 1, NE: 2, NW: 3 }[arc.centre];
        const [E1, E2, E3, E4] = [0, 1, 2, 3].map(k => E[(start + k) % 4]);
        /* the arc, from E1's far corner round to E4's near corner,
           counter-clockwise about the centre; the corners themselves are
           already the ends of the edges */
        const a = E1[E1.length - 1], b = E4[0];
        const t0 = Math.atan2(a[1] - C[1], a[0] - C[0]);
        const n = arc.segments ?? Math.max(5, Math.round(side / 20));
        const bow = [];
        for (let k = 1; k < n; k++) {
          const t = t0 + (Math.PI / 2) * (k / n);
          bow.push([Math.round(C[0] + side * Math.cos(t)), Math.round(C[1] + side * Math.sin(t))]);
        }
        const disc = [...E1, ...bow, ...E4.slice(0, -1)];          // C .. a, the bow, b .. (C)
        const rest = [...E2, ...E3.slice(1), ...bow.slice().reverse()];  // a .. c, .. b, the bow back to (a)
        if (rest[rest.length - 1] !== b && (rest[rest.length - 1][0] === b[0] && rest[rest.length - 1][1] === b[1])) rest.pop();
        const si = this.mb.sector(disc, { ...common, ...arc.disc });
        const ri = this.mb.sector(rest, { ...common, ...arc.rest });
        r.sector = si;
        r.column = [si, ri];
        r.arcSectors = { disc: si, rest: ri };
      } else if (r.props.storeys) {
        /* A COLUMN: one outline, several storeys. The overlap check
           above and the edge splitting here are untouched by it,
           because both are about x and y and a column lives at one x,y.
           `sector` stays the GROUND one, so a rect reads the same to
           everything that was written before there were storeys. */
        const { storeys, ...common } = r.props;
        r.column = this.mb.column(poly, storeys.map(st => ({ ...common, ...st })));
        r.sector = r.column[0];
      } else {
        r.sector = this.mb.sector(poly, r.props);
        r.column = [r.sector];
      }
      r.props.__index = r.sector;
    }
    return this.rects;
  }
}
