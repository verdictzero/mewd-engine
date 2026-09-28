/* =====================================================================
   MEWD Editor — THE STEP GENERATOR

   At the user's request: something that makes STAIRS, CLIFFS and
   CALDERAS, bridging sectors of different heights a step at a time.

     STAIRS    a sector between two of different heights — a corridor
               from the street to a terrace, a gap between a floor and
               the next layer's — is cut across into strips, each a step
               higher than the last, from the low side to the high side.
               Which side is which comes from the neighbours; the rise
               of each step is what is left over split evenly.

     RINGS     a sector is cut into rings, one inside another, each a
               step up (a mound, a mesa, a cliff face in terraces) or a
               step down (a caldera, a pit, an amphitheatre) towards the
               middle.

   Both are ordinary sectors afterwards, drawn in the document the way
   a hand would have drawn them: a cut across a room splits its walls
   and so the rooms beside it get the new corners too (vertexFor), and
   a ring inside a ring is a hole in it, as any room drawn inside
   another is. So everything else in the editor — undo, the inspector,
   texture alignment, moving things — works on them unchanged.
   ===================================================================== */

import { linesOf, ringOf, signedArea, pointInPoly, selfCrosses, strictlyInside, centroid, takeId } from './doc.js';
import { vertexFor, splitSector } from './editor.js';

/** Doom's step: the player walks up 24, and 16 reads as a stair. */
export const STEP_H = 16;

/** The sectors across a line from `S`, with the stretch of wall each
 *  one shares with it: [{ s, len, mid: [x, y] }]. */
export function neighboursOf(d, S) {
  const si = d.sectors.indexOf(S);
  const out = new Map();
  for (const l of linesOf(d)) {
    if (l.sectors.length !== 2 || !l.sectors.includes(si)) continue;
    const o = d.sectors[l.sectors[0] === si ? l.sectors[1] : l.sectors[0]];
    const a = d.vertices[l.a], b = d.vertices[l.b];
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const e = out.get(o) || { s: o, len: 0, mx: 0, my: 0 };
    e.len += len; e.mx += (a[0] + b[0]) / 2 * len; e.my += (a[1] + b[1]) / 2 * len;
    out.set(o, e);
  }
  return [...out.values()].map(e => ({ s: e.s, len: e.len, mid: [e.mx / e.len, e.my / e.len] }));
}

/**
 * STAIRS ACROSS `S`: cut into strips square to `dir`, rising from
 * `from` to `to`. With nothing said, the lowest neighbour is the foot,
 * the highest the head, and the stair runs from one to the other; each
 * strip is one step, and there are as many as make each rise no more
 * than `stepH` — the first a step up off the foot and the last a step
 * below the head, so the head is the last step.
 *
 * @returns { ids, rise } or { error }
 */
export function makeStairs(d, S, { from, to, count = 0, stepH = STEP_H, dir = null, headroom = true } = {}) {
  const ring = ringOf(d, S);
  if (ring.length < 3) return { error: 'that sector has no shape' };
  const nb = neighboursOf(d, S).filter(n => (n.s.floor ?? 0) !== undefined);
  const lo = nb.reduce((m, n) => (!m || (n.s.floor ?? 0) < (m.s.floor ?? 0) ? n : m), null);
  const hi = nb.reduce((m, n) => (!m || (n.s.floor ?? 0) > (m.s.floor ?? 0) ? n : m), null);
  const auto = lo && hi && (hi.s.floor ?? 0) !== (lo.s.floor ?? 0);
  if (from === undefined || from === null) from = auto ? lo.s.floor ?? 0 : S.floor ?? 0;
  if (to === undefined || to === null) {
    if (!auto) return { error: 'the sector has no neighbours of different heights to bridge — give the height to climb to' };
    to = hi.s.floor ?? 0;
  }
  const dh = to - from;
  if (!dh) return { error: 'the two ends are at the same height — there is nothing to climb' };
  /* WHICH WAY: from the foot's wall to the head's, or as asked, or along
     the sector's long side */
  let u = dir;
  if (!u && auto) u = [hi.mid[0] - lo.mid[0], hi.mid[1] - lo.mid[1]];
  if (!u || Math.hypot(u[0], u[1]) < 1e-6) {
    const xs = ring.map(p => p[0]), ys = ring.map(p => p[1]);
    u = Math.max(...xs) - Math.min(...xs) >= Math.max(...ys) - Math.min(...ys) ? [1, 0] : [0, 1];
    if (auto && ((lo.mid[0] - hi.mid[0]) * u[0] + (lo.mid[1] - hi.mid[1]) * u[1]) > 0) u = [-u[0], -u[1]];
  }
  /* a stair across a room that is square to the map runs square to it */
  const L = Math.hypot(u[0], u[1]);
  u = [u[0] / L, u[1] / L];
  if (Math.abs(u[0]) > 0.92) u = [Math.sign(u[0]), 0];
  else if (Math.abs(u[1]) > 0.92) u = [0, Math.sign(u[1])];
  const n = count > 0 ? Math.round(count) : Math.max(1, Math.ceil(Math.abs(dh) / Math.max(1, stepH)) - 1);
  if (n > 256) return { error: `${n} steps is too many — make the step taller` };
  const proj = p => p[0] * u[0] + p[1] * u[1];
  const ts = ring.map(proj);
  const t0 = Math.min(...ts), t1 = Math.max(...ts);
  const axis = u[0] === 0 || u[1] === 0;
  const pieces = new Set([S]);
  const headH = (S.ceil ?? 256) - (S.floor ?? 0);
  /* THE CUTS: each a line square to the stair, across every piece of
     the sector it passes through */
  for (let k = 1; k < n; k++) {
    let t = t0 + (t1 - t0) * k / n;
    if (axis) t = Math.round(t);
    cutAcross(d, pieces, u, t);
  }
  /* AND THE HEIGHTS: each piece by where it is along the stair */
  const rise = dh / (n + 1);
  for (const s of pieces) {
    const c = centroid(ringOf(d, s));
    const i = Math.max(0, Math.min(n - 1, Math.floor((proj(c) - t0) / (t1 - t0) * n)));
    s.floor = Math.round(from + rise * (i + 1));
    if (headroom) s.ceil = s.floor + headH;
    if (s !== S) s.name = '';
  }
  return { ids: [...pieces].map(s => s.id), rise, steps: n };
}

/** Cut every piece in `pieces` that the line { p : p·u = t } crosses,
 *  adding the new pieces to the set. */
function cutAcross(d, pieces, u, t) {
  const v = [-u[1], u[0]];
  /* where the line crosses each piece's edges, along the line */
  for (let guard = 0; guard < 64; guard++) {
    let did = false;
    for (const P of [...pieces]) {
      const r = ringOf(d, P);
      const hits = [];
      for (let k = 0; k < r.length; k++) {
        const a = r[k], b = r[(k + 1) % r.length];
        const ta = a[0] * u[0] + a[1] * u[1] - t, tb = b[0] * u[0] + b[1] * u[1] - t;
        if ((ta > 0) === (tb > 0) && ta !== 0 && tb !== 0) continue;
        if (ta === 0 && tb === 0) continue;               // an edge along the cut
        const f = ta === tb ? 0 : ta / (ta - tb);
        if (f < 0 || f > 1) continue;
        const x = +(a[0] + (b[0] - a[0]) * f).toFixed(3), y = +(a[1] + (b[1] - a[1]) * f).toFixed(3);
        hits.push([x * v[0] + y * v[1], x, y]);
      }
      hits.sort((p, q) => p[0] - q[0]);
      const pts = hits.filter((h, k) => !k || h[0] - hits[k - 1][0] > 0.5);
      /* the first stretch of the line that is inside this piece */
      for (let k = 0; k + 1 < pts.length; k++) {
        const mx = (pts[k][1] + pts[k + 1][1]) / 2, my = (pts[k][2] + pts[k + 1][2]) / 2;
        if (!pointInPoly(r, mx, my)) continue;
        const a = vertexFor(d, pts[k][1], pts[k][2]), b = vertexFor(d, pts[k + 1][1], pts[k + 1][2]);
        if (a === b || !P.verts.includes(a) || !P.verts.includes(b)) continue;
        const i = P.verts.indexOf(a), j = P.verts.indexOf(b), m = P.verts.length;
        if ((i + 1) % m === j || (j + 1) % m === i) continue;   // already an edge
        const made = splitSector(d, P, [a, b]);
        if (made) { pieces.add(made); did = true; break; }
      }
      if (did) break;
    }
    if (!did) return;
  }
}

/**
 * RINGS IN `S`: `count` rings, each inset from the last, stepping from
 * the sector's own floor (the outer ring) to `to` (the middle) — up for
 * a mound or a mesa, down for a caldera or a pit.
 *
 * @returns { ids } or { error }
 */
export function makeRings(d, S, { to, count = 0, stepH = STEP_H, headroom = true } = {}) {
  const outer = ringOf(d, S);
  if (outer.length < 3) return { error: 'that sector has no shape' };
  const from = S.floor ?? 0;
  if (to === undefined || to === null || to === '') to = from + 128;
  const dh = to - from;
  if (!dh) return { error: 'give the middle a height different from the edge' };
  const n = count > 0 ? Math.round(count) : Math.max(2, Math.round(Math.abs(dh) / Math.max(1, stepH)) + 1);
  if (n > 128) return { error: `${n} rings is too many — make the step taller` };
  const A = Math.abs(signedArea(outer));
  let P = 0;
  for (let k = 0; k < outer.length; k++) { const a = outer[k], b = outer[(k + 1) % outer.length]; P += Math.hypot(b[0] - a[0], b[1] - a[1]); }
  const reach = A / (P / 2) * 0.9;                   // about as far in as the middle is
  const w = reach / n;
  if (w < 2) return { error: `the sector is too small for ${n} rings — fewer rings, or a taller step` };
  const headH = (S.ceil ?? 256) - (S.floor ?? 0);
  const ccw = signedArea(outer) > 0 ? outer : [...outer].reverse();
  const made = [S];
  let prev = ccw;
  for (let i = 1; i < n; i++) {
    let ring = inset(ccw, w * i);
    if (!ring || selfCrosses(ring) || !strictlyInside(ring, prev)) {
      /* a shape an inset folds: shrink it to its middle instead */
      const [cx, cy] = centroid(ccw), f = 1 - i / n;
      ring = ccw.map(([x, y]) => [Math.round(cx + (x - cx) * f), Math.round(cy + (y - cy) * f)]);
      if (selfCrosses(ring) || !strictlyInside(ring, prev)) return { error: `ring ${i + 1} does not fit inside ring ${i} — use fewer rings`, ids: made.map(s => s.id) };
    }
    const verts = ring.map(([x, y]) => vertexFor(d, x, y));
    const s = { ...JSON.parse(JSON.stringify({ ...S, id: undefined, verts: undefined, name: '' })), id: takeId(d), verts };
    d.sectors.push(s);
    made.push(s);
    prev = ring;
  }
  made.forEach((s, i) => {
    s.floor = Math.round(from + dh * i / (n - 1));
    if (headroom) s.ceil = s.floor + headH;
  });
  return { ids: made.map(s => s.id), steps: n };
}

/** A ring moved in by `w` everywhere — each corner along its bisector —
 *  rounded to whole units. Null where a corner would go past the next. */
function inset(ccw, w) {
  const n = ccw.length, out = [];
  for (let k = 0; k < n; k++) {
    const p = ccw[(k - 1 + n) % n], c = ccw[k], q = ccw[(k + 1) % n];
    const e1 = norm([c[0] - p[0], c[1] - p[1]]), e2 = norm([q[0] - c[0], q[1] - c[1]]);
    if (!e1 || !e2) return null;
    /* inward normals of an anticlockwise ring are to the left */
    const n1 = [-e1[1], e1[0]], n2 = [-e2[1], e2[0]];
    const b = norm([n1[0] + n2[0], n1[1] + n2[1]]);
    if (!b) return null;
    const cos = b[0] * n1[0] + b[1] * n1[1];
    if (cos < 0.2) return null;                      // a spike: no clean inset
    out.push([Math.round(c[0] + b[0] * w / cos), Math.round(c[1] + b[1] * w / cos)]);
  }
  return out;
}
function norm(v) { const L = Math.hypot(v[0], v[1]); return L < 1e-9 ? null : [v[0] / L, v[1] / L]; }
