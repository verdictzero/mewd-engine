/* =====================================================================
   MEWD Editor — the plan
   =====================================================================

   The Doom Builder half: the map from above on a grid, north up. Every
   mode edits one kind of thing — vertices, lines, sectors, things,
   props, scatters — and two draw: DRAW clicks out a sector a corner at
   a time and RECT drags one out. Drag anything to move it; drag on
   nothing to box-select; the wheel zooms about the cursor and the right
   or middle button pans. In SCATTER mode a drag paints a circle of the
   chosen mix, from its middle out.

   EVERY MODE WORKS IN THE 3D VIEW TOO (js/editor/view3d.js), and the two
   share what is half-done: the outline being drawn, the drag, the
   cursor. So a room can be started in one and finished in the other.

   A DRAG IS ONE UNDO. The first move of a drag pushes the undo step and
   every move after it shifts the same selection further, so a drag is
   cheap however long it is and Ctrl+Z puts it all back. It is tidied —
   welded — when the button comes up, which is the moment a vertex
   dropped on another becomes one vertex.
   ===================================================================== */

import { THING_TYPES, ringOf, segDist, signedArea, FEATURES } from './doc.js';
import { MODE_KIND, isInside, brightOf } from './editor.js';
import { exteriorWall } from './view3d.js';

const PICK_PX = 8;           // how near, in pixels, counts as on it

/* BLENDER'S AXIS COLOURS, as the 3D view has them (js/editor/view3d.js) */
const AXIS_X = '#ff3352', AXIS_Y = '#8bdc00', AXIS_Z = '#4aa8ff';

export class View2D {
  constructor(ed, canvas) {
    this.ed = ed;
    this.canvas = canvas;
    this.g = canvas.getContext('2d');
    this.cx = 5120; this.cy = 5120;
    this.scale = 0.08;       // pixels per unit
    this.w = 1; this.h = 1; this.dpr = 1;
    this.mouse = null;       // { x, y } in map units, snapped separately
    this.hover = null;       // { kind, id }
    this.drag = null;
    this.dirty = true;

    const ro = new ResizeObserver(() => this.resize());
    ro.observe(canvas.parentElement);
    this.resize();

    canvas.addEventListener('pointerdown', e => this.down(e));
    canvas.addEventListener('pointermove', e => this.move(e));
    canvas.addEventListener('pointerup', e => this.up(e));
    canvas.addEventListener('pointercancel', e => this.up(e));
    canvas.addEventListener('dblclick', e => this.dbl(e));
    canvas.addEventListener('wheel', e => this.wheel(e), { passive: false });
    canvas.addEventListener('contextmenu', e => e.preventDefault());
    canvas.addEventListener('pointerenter', () => { ed.pointerView = '2d'; });
    canvas.addEventListener('pointerleave', () => { this.mouse = null; this.hover = null; ed.ui.setPos(null); ed.setCursor(null); ed.setHover(null); this.dirty = true; });

    /* FINGERS AND PENS. Every finger on the glass, for pinching; the
       last pen or finger tap, for a double-tap; and the pad of buttons
       that stands in for the keys a tablet has not got */
    this.touches = new Map();
    this.gesture = null;
    this.lastTap = null;
    this.pad = buildPad(ed, canvas.parentElement);

    for (const ev of ['doc', 'sel', 'mode', 'grid', 'layout', 'compiled', 'path', 'cursor']) ed.on(ev, () => { this.dirty = true; });
    for (const ev of ['sel', 'mode', 'path', 'doc']) ed.on(ev, () => this.pad.refresh());
    ed.on('layout', () => setTimeout(() => this.resize(), 0));
    ed.on('frame', () => this.frame());
    ed.on('frameSel', () => this.frameSel());
    ed.on('camera', () => { this.dirty = true; });

    const tick = () => { if (this.dirty) this.draw(); requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
  }

  /* ------------------------------------------------------------------
     the plan's own geometry
     ------------------------------------------------------------------ */
  resize() {
    const r = this.canvas.parentElement.getBoundingClientRect();
    this.dpr = Math.min(2, devicePixelRatio || 1);
    /* THE SAME PIECE OF MAP IN VIEW when the view changes size — swapping
       the inset for the big view shows the map big, not in a corner */
    const nw = Math.max(1, r.width), nh = Math.max(1, r.height);
    if (this.framed && this.w > 1 && this.h > 1) this.scale *= Math.min(nw / this.w, nh / this.h);
    this.w = nw; this.h = nh;
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
    /* the first real size frames the map: at boot the panel may not
       have been laid out yet when the editor asked */
    if (!this.framed && r.width > 1 && this.ed.history) { this.framed = true; this.frame(); }
    this.dirty = true;
  }
  sx(x) { return (x - this.cx) * this.scale + this.w / 2; }
  sy(y) { return this.h / 2 - (y - this.cy) * this.scale; }
  mx(px) { return (px - this.w / 2) / this.scale + this.cx; }
  my(py) { return (this.h / 2 - py) / this.scale + this.cy; }
  at(e) {
    const r = this.canvas.getBoundingClientRect();
    const px = e.clientX - r.left, py = e.clientY - r.top;
    return { px, py, x: this.mx(px), y: this.my(py) };
  }

  /** Fit a box in the view, with a margin. */
  fit(x0, y0, x1, y1) {
    if (!(x1 > x0) || !(y1 > y0)) { x0 -= 256; x1 += 256; y0 -= 256; y1 += 256; }
    this.cx = (x0 + x1) / 2; this.cy = (y0 + y1) / 2;
    this.scale = Math.min(this.w / (x1 - x0), this.h / (y1 - y0)) * 0.88;
    this.dirty = true;
  }
  frame() {
    const V = this.ed.doc.vertices;
    if (!V.length) { this.fit(-512, -512, 512, 512); return; }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of V) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    this.fit(x0, y0, x1, y1);
  }
  frameSel() {
    const pts = this.selPoints();
    if (!pts.length) return this.frame();
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of pts) { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
    this.fit(x0 - 64, y0 - 64, x1 + 64, y1 + 64);
  }
  selPoints() {
    const d = this.ed.doc, { kind, ids } = this.ed.sel, out = [];
    if (kind === 'vertex') ids.forEach(i => d.vertices[i] && out.push(d.vertices[i]));
    if (kind === 'line') ids.forEach(k => k.split(',').forEach(i => d.vertices[+i] && out.push(d.vertices[+i])));
    if (kind === 'sector') d.sectors.forEach(s => ids.has(s.id) && out.push(...ringOf(d, s)));
    if (kind === 'thing') d.things.forEach(t => ids.has(t.id) && out.push([t.x, t.y]));
    if (kind === 'prop') d.props.forEach(p => ids.has(p.id) && out.push([p.x0, p.y0], [p.x1, p.y1]));
    if (kind === 'scatter') d.scatters.forEach(c => ids.has(c.id) && out.push(...scatterBox(d, c)));
    return out;
  }

  /* ------------------------------------------------------------------
     WHAT IS UNDER THE MOUSE, in the current mode
     ------------------------------------------------------------------ */
  pick(x, y, kind = modeKind(this.ed.mode)) {
    if (kind === 'scatter') { const c = scatterAt(this.ed.doc, x, y); return c ? { kind, id: c.id } : null; }
    const d = this.ed.doc;
    const r = PICK_PX / this.scale;
    if (kind === 'vertex') {
      let best = -1, bd = r * r;
      d.vertices.forEach((v, i) => { const q = (v[0] - x) ** 2 + (v[1] - y) ** 2; if (q < bd) { bd = q; best = i; } });
      return best >= 0 ? { kind, id: best } : null;
    }
    if (kind === 'line') {
      let best = null, bd = r;
      for (const l of this.lines()) {
        const a = d.vertices[l.a], b = d.vertices[l.b];
        const { d: dist } = segDist(a[0], a[1], b[0], b[1], x, y);
        if (dist < bd) { bd = dist; best = l.key; }
      }
      return best ? { kind, id: best } : null;
    }
    if (kind === 'sector') { const s = this.ed.sectorAt(x, y); return s ? { kind, id: s.id } : null; }
    if (kind === 'thing') {
      let best = null, bd = Infinity;
      for (const t of d.things) {
        if (!this.ed.onLayer(t)) continue;
        const rad = Math.max(THING_TYPES[t.type]?.radius || 16, r);
        const q = Math.hypot(t.x - x, t.y - y);
        if (q < rad && q < bd) { bd = q; best = t.id; }
      }
      return best !== null ? { kind, id: best } : null;
    }
    if (kind === 'prop') {
      let best = null, ba = Infinity;
      for (const p of d.props) {
        const x0 = Math.min(p.x0, p.x1), x1 = Math.max(p.x0, p.x1), y0 = Math.min(p.y0, p.y1), y1 = Math.max(p.y0, p.y1);
        if (x < x0 - r || x > x1 + r || y < y0 - r || y > y1 + r) continue;
        const a = (x1 - x0) * (y1 - y0);
        if (a < ba) { ba = a; best = p.id; }
      }
      return best !== null ? { kind, id: best } : null;
    }
    return null;
  }
  lines() {
    return this.ed.lines();
  }

  /** A point for drawing: an existing vertex near the cursor, a point
   *  on a line near it, or the grid (Editor.snapAt). What it snapped to
   *  is kept for the cursor to show. */
  snapPoint(x, y) {
    const s = this.ed.snapAt(x, y, PICK_PX / this.scale);
    this.snapKind = s.kind;
    return s.pt;
  }

  /* ------------------------------------------------------------------
     THE MOUSE
     ------------------------------------------------------------------ */
  down(e) {
    const ed = this.ed;
    this.canvas.focus();
    const p = this.at(e);
    try { this.canvas.setPointerCapture(e.pointerId); } catch (err) { /* a pointer the browser no longer has */ }
    if (e.pointerType === 'pen' && !ed.penSeen) { ed.penSeen = true; this.pad.refresh(); ed.say('pen: draw with the pen — one finger pans, two pinch to zoom, the side button is the right mouse button'); }
    if (e.pointerType !== 'mouse') this.pad.show();
    /* A FINGER, once a pen has been used, only moves the view — the palm
       on the glass draws nothing — and two fingers always pinch, taking
       back a corner the first of them put down a moment before */
    if (e.pointerType === 'touch') {
      this.touches.set(e.pointerId, { x: p.px, y: p.py });
      if (ed.penSeen || this.touches.size >= 2) {
        if (this.touches.size >= 2 && this.drag) {
          if (this.drag.type === 'move') ed.endMove(this.drag.mv);
          this.drag = null;
        }
        if (this.touches.size >= 2 && this._fingerCorner && performance.now() - this._fingerCorner < 400 && ed.path.length) { ed.path.pop(); ed.emit('path'); }
        this._fingerCorner = 0;
        this.startGesture();
        return;
      }
    }
    /* THE ERASER END of a pen deletes what it touches */
    if (e.pointerType === 'pen' && e.button === 5) {
      const hit = this.pick(p.x, p.y);
      if (hit) { ed.select(hit.kind, [hit.id]); ed.deleteSel(); }
      return;
    }
    const slop = e.pointerType === 'touch' ? 10 : e.pointerType === 'pen' ? 6 : 4;
    this.slop = slop;
    if (e.button === 1) {
      this.drag = { type: 'pan', px: p.px, py: p.py, cx: this.cx, cy: this.cy };
      return;
    }
    /* THE RIGHT BUTTON, Doom Builder's way: a click on something is its
       properties; a drag on something moves it; a drag on nothing pans */
    /* a pen's side button is the right button, however the browser
       reports it: as button 2, or as button 2 held down while it touches */
    const right = e.button === 2 || (e.pointerType === 'pen' && (e.buttons & 2) === 2);
    if (right && ed.mode === 'draw' && ed.path.length) { ed.closePath({ open: true }); return; }
    if (right) {
      const hit = this.pick(p.x, p.y);
      this.drag = { type: 'right', hit, px: p.px, py: p.py, x: p.x, y: p.y, cx: this.cx, cy: this.cy };
      return;
    }
    if (e.button !== 0) return;
    const mode = ed.mode;

    if (mode === 'draw') {
      /* A DOUBLE-TAP, with a pen or a finger, finishes the drawing as a
         double-click does — a tablet has no Enter */
      if (e.pointerType !== 'mouse') {
        const now = performance.now(), lt = this.lastTap;
        this.lastTap = { t: now, px: p.px, py: p.py };
        if (lt && now - lt.t < 400 && Math.hypot(p.px - lt.px, p.py - lt.py) < 16 && ed.path.length >= 2) {
          this.lastTap = null;
          ed.closePath({ open: true });
          return;
        }
        if (e.pointerType === 'touch') this._fingerCorner = now;
      }
      const pt = this.snapPoint(p.x, p.y);
      const first = ed.path[0];
      if (first && ed.path.length >= 3 && Math.hypot(first[0] - pt[0], first[1] - pt[1]) * this.scale < PICK_PX + 2) ed.closePath();
      else ed.addPathPoint(pt);
      return;
    }
    if (mode === 'rect') {
      const a = this.snapPoint(p.x, p.y);
      this.drag = { type: 'rect', a, b: a };
      return;
    }

    const kind = modeKind(mode);
    /* Alt paints a new scatter even over an old one */
    const hit = mode === 'scatter' && e.altKey ? null : this.pick(p.x, p.y, kind);
    if (!hit) {
      if (mode === 'props') { const a = [ed.snapV(p.x), ed.snapV(p.y)]; this.drag = { type: 'prop', a, b: a }; return; }
      if (mode === 'scatter') { const a = [ed.snapV(p.x), ed.snapV(p.y)]; this.drag = { type: 'brush', a, b: a }; return; }
      this.drag = { type: 'box', a: [p.x, p.y], b: [p.x, p.y], add: e.shiftKey };
      return;
    }
    if (e.shiftKey || e.ctrlKey) { ed.select(kind, [hit.id], true); return; }
    /* A DRAG ON THE GROUND DRAWS: the sector every other one is drawn in
       is not something anybody means to drag the whole of, so a drag
       that starts on it in Sectors mode draws a new rectangle, and a
       click selects it as before. Alt-drag moves it. */
    if (mode === 'sectors' && !e.altKey && ed.isGround(hit.id)) {
      const a = this.snapPoint(p.x, p.y);
      this.drag = { type: 'rect', a, b: a, ground: hit.id, px: p.px, py: p.py };
      return;
    }
    if (!ed.isSel(kind, hit.id)) ed.select(kind, [hit.id]);
    this.drag = { type: 'move', mv: ed.beginMove(ed.grabPoint([p.x, p.y]), [p.x, p.y]), px: p.px, py: p.py, moved: false };
  }

  move(e) {
    const ed = this.ed;
    const p = this.at(e);
    if (e.pointerType === 'touch' && this.touches.has(e.pointerId)) {
      this.touches.set(e.pointerId, { x: p.px, y: p.py });
      if (this.gesture) { this.moveGesture(); return; }
    }
    this.mouse = { x: p.x, y: p.y };
    this.snapKind = 'grid';
    const snapped = ['draw', 'rect', 'vertices'].includes(ed.mode) ? this.snapPoint(p.x, p.y) : [ed.snapV(p.x), ed.snapV(p.y)];
    ed.cursorKind = this.snapKind;
    ed.setCursor(snapped);
    ed.ui.setPos(snapped[0], snapped[1]);
    const dr = this.drag;
    if (!dr) {
      this.hover = ['draw', 'rect'].includes(ed.mode) ? null : this.pick(p.x, p.y);
      /* for the info bar, the sector under the mouse whatever the mode */
      const s = ed.sectorAt(p.x, p.y);
      ed.setHover(this.hover || (s ? { kind: 'sector', id: s.id } : null));
      this.dirty = true;
      return;
    }
    if (dr.type === 'right') {
      if (Math.hypot(p.px - dr.px, p.py - dr.py) < (this.slop || 4)) return;
      if (dr.hit) {
        const kind = dr.hit.kind;
        if (!ed.isSel(kind, dr.hit.id)) ed.select(kind, [dr.hit.id]);
        this.drag = { type: 'move', mv: ed.beginMove(ed.grabPoint([dr.x, dr.y]), [dr.x, dr.y]), px: dr.px, py: dr.py, moved: true };
      } else {
        this.drag = { type: 'pan', px: dr.px, py: dr.py, cx: dr.cx, cy: dr.cy };
      }
      return this.move(e);
    }
    if (dr.type === 'pan') {
      this.cx = dr.cx - (p.px - dr.px) / this.scale;
      this.cy = dr.cy + (p.py - dr.py) / this.scale;
    } else if (dr.type === 'box' || dr.type === 'rect' || dr.type === 'prop' || dr.type === 'brush') {
      dr.b = dr.type === 'box' ? [p.x, p.y] : dr.type === 'rect' ? this.snapPoint(p.x, p.y) : [ed.snapV(p.x), ed.snapV(p.y)];
    } else if (dr.type === 'move') {
      /* nothing moves until the mouse has, a little — a click is not a drag */
      if (!dr.moved && Math.hypot(p.px - dr.px, p.py - dr.py) < (this.slop || 4)) return;
      dr.moved = true;
      ed.dragMove(dr.mv, [p.x, p.y], PICK_PX / this.scale);
      /* the corner being dragged, and what it has snapped onto */
      const at = [dr.mv.ref[0] + dr.mv.done[0], dr.mv.ref[1] + dr.mv.done[1]];
      ed.cursorKind = dr.mv.onto || 'grid';
      ed.setCursor(at);
      ed.ui.setPos(at[0], at[1]);
    }
    this.dirty = true;
  }

  up(e) {
    const ed = this.ed;
    if (e.pointerType === 'touch' && this.touches.has(e.pointerId)) {
      this.touches.delete(e.pointerId);
      if (this.gesture) {
        /* one finger left: it goes on panning from where it is */
        if (this.touches.size) this.startGesture(); else this.gesture = null;
        try { this.canvas.releasePointerCapture(e.pointerId); } catch (err) { /* gone */ }
        return;
      }
    }
    const dr = this.drag;
    this.drag = null;
    try { this.canvas.releasePointerCapture(e.pointerId); } catch (err) { /* already gone */ }
    if (!dr) return;
    if (dr.type === 'right') {
      /* a right click, not a drag: the thing under it, in the inspector */
      if (dr.hit) {
        if (!ed.isSel(dr.hit.kind, dr.hit.id)) ed.select(dr.hit.kind, [dr.hit.id]);
        ed.ui.showTab('insp');
        ed.ui.flashInsp?.();
      }
      return;
    }
    if (dr.type === 'box') {
      const kind = modeKind(ed.mode);
      const [x0, x1] = [Math.min(dr.a[0], dr.b[0]), Math.max(dr.a[0], dr.b[0])];
      const [y0, y1] = [Math.min(dr.a[1], dr.b[1]), Math.max(dr.a[1], dr.b[1])];
      if ((x1 - x0) * this.scale < 3 && (y1 - y0) * this.scale < 3) { if (!dr.add) ed.clearSel(); }
      else ed.select(kind, this.inBox(kind, x0, y0, x1, y1), dr.add);
    } else if (dr.type === 'rect') {
      /* a click on the ground, not a drag: select it, as any click does */
      const p = this.at(e);
      if (dr.ground && Math.hypot(p.px - dr.px, p.py - dr.py) < (this.slop || 4)) { ed.select('sector', [dr.ground]); ed.say('the ground — drag on it to draw a new sector; Alt-drag moves it'); }
      else ed.addRect(dr.a, dr.b);
    } else if (dr.type === 'prop') {
      ed.addProp(dr.a[0], dr.a[1], dr.b[0], dr.b[1]);
    } else if (dr.type === 'brush') {
      paintBrush(ed, dr.a, dr.b);
    } else if (dr.type === 'move') {
      /* THE WELD, now the drag is over */
      ed.endMove(dr.mv);
    }
    this.dirty = true;
  }

  dbl(e) {
    if (this.ed.mode === 'draw') { this.ed.closePath({ open: true }); return; }
    /* a double-click on empty floor in things mode puts a thing there —
       as does Insert; a single click selects */
    if (this.ed.mode === 'things') {
      const p = this.at(e);
      if (!this.pick(p.x, p.y, 'thing')) { this.ed.addThing(p.x, p.y); return; }
    }
    if (this.ed.sel.kind) this.ed.ui.showTab('insp');
  }

  /** PAN AND PINCH: the fingers' middle holds the map point under it,
   *  and with two the scale follows how far apart they are. */
  startGesture() {
    const pts = [...this.touches.values()];
    const c = pts.reduce((a, q) => [a[0] + q.x / pts.length, a[1] + q.y / pts.length], [0, 0]);
    const spread = pts.length > 1 ? Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y) : 0;
    this.gesture = { n: pts.length, spread, scale: this.scale, x: this.mx(c[0]), y: this.my(c[1]) };
  }
  moveGesture() {
    const g = this.gesture, pts = [...this.touches.values()];
    if (pts.length !== g.n) { this.startGesture(); return; }
    const c = pts.reduce((a, q) => [a[0] + q.x / pts.length, a[1] + q.y / pts.length], [0, 0]);
    if (pts.length > 1 && g.spread > 10) {
      const spread = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
      this.scale = Math.max(0.005, Math.min(40, g.scale * spread / g.spread));
    }
    this.cx = g.x - (c[0] - this.w / 2) / this.scale;
    this.cy = g.y - (this.h / 2 - c[1]) / this.scale;
    this.dirty = true;
  }
  /** Zoom by `k` about the middle of the view — the pad's − and +. */
  zoomBy(k) {
    this.scale = Math.max(0.005, Math.min(40, this.scale * k));
    this.dirty = true;
  }

  wheel(e) {
    e.preventDefault();
    const p = this.at(e);
    /* CTRL AND THE WHEEL: the brightness of the sector under the mouse,
       and of every selected one with it if it is one of them, as in
       Ultimate Doom Builder — Doom's sixteen steps, Shift for one */
    if (e.ctrlKey || e.metaKey) {
      const s = this.ed.sectorAt(p.x, p.y);
      if (!s) return;
      const ed = this.ed;
      const ids = ed.sel.kind === 'sector' && ed.sel.ids.has(s.id) ? ed.sel.ids : new Set([s.id]);
      ed.nudgeLight((e.shiftKey ? 1 : 16) * (e.deltaY < 0 ? 1 : -1), ids);
      return;
    }
    const k = Math.exp(-e.deltaY * (e.deltaMode === 1 ? 0.05 : 0.0015));
    this.scale = Math.max(0.005, Math.min(40, this.scale * k));
    /* about the cursor: the point under it stays under it */
    this.cx = p.x - (p.px - this.w / 2) / this.scale;
    this.cy = p.y - (this.h / 2 - p.py) / this.scale;
    this.dirty = true;
  }

  inBox(kind, x0, y0, x1, y1) {
    const d = this.ed.doc, inB = (x, y) => x >= x0 && x <= x1 && y >= y0 && y <= y1, out = [];
    if (kind === 'vertex') d.vertices.forEach((v, i) => inB(v[0], v[1]) && out.push(i));
    if (kind === 'line') for (const l of this.lines()) { const a = d.vertices[l.a], b = d.vertices[l.b]; if (inB(a[0], a[1]) && inB(b[0], b[1])) out.push(l.key); }
    if (kind === 'sector') for (const s of d.sectors) if (ringOf(d, s).every(v => inB(v[0], v[1]))) out.push(s.id);
    if (kind === 'thing') for (const t of d.things) if (this.ed.onLayer(t) && inB(t.x, t.y)) out.push(t.id);
    if (kind === 'prop') for (const p of d.props) if (inB(p.x0, p.y0) && inB(p.x1, p.y1)) out.push(p.id);
    if (kind === 'scatter') for (const c of d.scatters) { const [a, b] = scatterBox(d, c); if (inB(a[0], a[1]) && inB(b[0], b[1])) out.push(c.id); }
    return out;
  }

  /** Keys the plan takes before the editor does. True if it took it. */
  key(e) {
    const ed = this.ed, k = e.key;
    if ((k === ',' || k === '.') && ed.sel.kind === 'thing') {
      const da = (k === ',' ? 1 : -1) * Math.PI / 4;
      ed.edit('turn', d => { for (const t of d.things) if (ed.sel.ids.has(t.id)) t.angle = ((t.angle || 0) + da + Math.PI * 2) % (Math.PI * 2); }, { tidy: false });
      return true;
    }
    const arrows = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, 1], ArrowDown: [0, -1] };
    if (arrows[k] && ed.sel.kind) {
      /* a grid step, or one unit with snap off — Shift for four */
      const step = ed.snap ? ed.grid : 1;
      const s = e.shiftKey ? step * 4 : step;
      ed.moveSel(arrows[k][0] * s, arrows[k][1] * s, 'nudge');
      return true;
    }
    return false;
  }

  /* ------------------------------------------------------------------
     DRAWING THE PLAN
     ------------------------------------------------------------------ */
  draw() {
    this.dirty = false;
    const g = this.g, ed = this.ed, d = ed.doc;
    g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    g.fillStyle = '#07090b';
    g.fillRect(0, 0, this.w, this.h);

    this.drawGrid();
    this.drawLayers();

    /* THE SECTORS, filled by floor height so the plan reads like a
       relief map, and the selection over the top */
    const heights = d.sectors.map(s => s.floor ?? 0);
    const lo = Math.min(0, ...heights), hi = Math.max(1, ...heights);
    const selS = ed.sel.kind === 'sector' ? ed.sel.ids : null;
    const hovS = this.hover?.kind === 'sector' ? this.hover.id : null;
    const order = d.sectors.map((s, i) => [s, Math.abs(signedArea(ringOf(d, s))), i]).sort((a, b) => b[1] - a[1]);
    const ceils = d.sectors.map(s => s.ceil ?? 0);
    const vr = { lo, hi, clo: Math.min(...ceils), chi: Math.max(...ceils) };
    for (const [s] of order) {
      const r = ringOf(d, s);
      if (r.length < 3) continue;
      g.beginPath();
      r.forEach(([x, y], k) => (k ? g.lineTo(this.sx(x), this.sy(y)) : g.moveTo(this.sx(x), this.sy(y))));
      g.closePath();
      const t = (((s.floor ?? 0) - lo) / (hi - lo || 1));
      const shut = (s.ceil ?? 256) <= (s.floor ?? 0);
      /* OUTSIDE is the ground's green; INSIDE is a roof, tan and hatched —
         or, in one of the plan's views, the sector's brightness, floor or
         ceiling as a shade (Doom Builder's brightness view) */
      const inside = isInside(s);
      const view = ed.planView || 'normal';
      if (view !== 'normal') {
        const v = view === 'light' ? brightOf(s) / 255 : view === 'floor' ? ((s.floor ?? 0) - vr.lo) / (vr.hi - vr.lo || 1)
          : ((s.ceil ?? 0) - vr.clo) / (vr.chi - vr.clo || 1);
        const c = view === 'light' ? [v * 255, v * 255, v * 255] : [40 + v * 215, 60 + (1 - Math.abs(v - 0.5) * 2) * 120, 255 - v * 215];
        g.fillStyle = selS?.has(s.id) ? 'rgba(255,157,61,0.55)' : `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${view === 'light' ? 0.85 : 0.6})`;
        g.fill();
        continue;
      }
      g.fillStyle = selS?.has(s.id) ? 'rgba(255,157,61,0.28)' : s.id === hovS ? 'rgba(61,220,132,0.16)'
        : shut ? 'rgba(90,90,90,0.35)' : inside ? `rgba(${120 + t * 60},${90 + t * 40},${55 + t * 20},0.32)`
        : `rgba(${30 + t * 40},${60 + t * 90},${50 + t * 40},0.22)`;
      g.fill();
      if (inside && this.scale > 0.02) {
        g.save(); g.clip();
        g.strokeStyle = 'rgba(230,190,130,0.16)'; g.lineWidth = 1;
        const xs = r.map(v => this.sx(v[0])), ys = r.map(v => this.sy(v[1]));
        const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
        g.beginPath();
        for (let q = x0 - (y1 - y0); q < x1; q += 10) { g.moveTo(q, y0); g.lineTo(q + (y1 - y0), y1); }
        g.stroke(); g.restore();
      }
      if (FEATURES.slopes && (s.floorSlope || s.ceilSlope)) {
        /* a slope is hatched, so it can be found from above */
        g.save(); g.clip();
        g.strokeStyle = 'rgba(255,180,84,0.18)'; g.lineWidth = 1;
        const [bx0, by0] = [Math.min(...r.map(v => this.sx(v[0]))), Math.min(...r.map(v => this.sy(v[1])))];
        const [bx1, by1] = [Math.max(...r.map(v => this.sx(v[0]))), Math.max(...r.map(v => this.sy(v[1])))];
        g.beginPath();
        for (let q = bx0 - (by1 - by0); q < bx1; q += 8) { g.moveTo(q, by1); g.lineTo(q + (by1 - by0), by0); }
        g.stroke(); g.restore();
      }
    }

    /* the numbers, in the plan's views, at each sector's middle */
    if ((ed.planView || 'normal') !== 'normal' && this.scale > 0.03) {
      g.font = '11px ui-monospace, monospace'; g.textAlign = 'center';
      for (const s of d.sectors) {
        const r = ringOf(d, s);
        if (r.length < 3) continue;
        const cx = r.reduce((a, p) => a + p[0], 0) / r.length, cy = r.reduce((a, p) => a + p[1], 0) / r.length;
        const v = ed.planView === 'light' ? brightOf(s) : ed.planView === 'floor' ? (s.floor ?? 0) : (s.ceil ?? 0);
        g.fillStyle = '#000a'; g.fillText(String(v), this.sx(cx) + 1, this.sy(cy) + 1);
        g.fillStyle = '#fff'; g.fillText(String(v), this.sx(cx), this.sy(cy));
      }
      g.textAlign = 'start';
    }

    /* THE LINES: one-sided white, two-sided grey, blocking red */
    const selL = ed.sel.kind === 'line' ? ed.sel.ids : null;
    const hovL = this.hover?.kind === 'line' ? this.hover.id : null;
    g.lineCap = 'round';
    for (const l of this.lines()) {
      const a = d.vertices[l.a], b = d.vertices[l.b];
      if (!a || !b) continue;
      const o = d.lines[l.key];
      const sel = selL?.has(l.key), hov = l.key === hovL;
      /* a building's outside wall is drawn like a one-sided wall, and a
         doorway in one dashed */
      const ext = exteriorWall(d, l), door = !ext && o?.opening;
      /* a linedef of its own, which stands as a wall: yellow, and thick */
      g.strokeStyle = sel ? '#ff9d3d' : hov ? '#3ddc84' : l.free ? '#ffd23d' : o?.blocking ? '#ff6b6b' : ext ? '#f0dcb4' : door ? '#c9a46a' : l.sectors.length > 1 ? '#6d7a86' : '#e6edf0';
      g.lineWidth = sel || hov ? 2.5 : l.free ? 3 : ext ? 2 : l.sectors.length > 1 ? 1 : 1.6;
      if (door) g.setLineDash([5, 4]);
      g.beginPath(); g.moveTo(this.sx(a[0]), this.sy(a[1])); g.lineTo(this.sx(b[0]), this.sy(b[1])); g.stroke();
      if (door) g.setLineDash([]);
      if (ed.mode === 'lines' && (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2 > (24 / this.scale) ** 2) {
        /* the Doom tick, on the line's front */
        const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2, L = Math.hypot(b[0] - a[0], b[1] - a[1]);
        const nx = (b[1] - a[1]) / L, ny = -(b[0] - a[0]) / L;
        g.beginPath(); g.moveTo(this.sx(mx), this.sy(my)); g.lineTo(this.sx(mx) + nx * 6, this.sy(my) - ny * 6); g.stroke();
      }
    }

    /* THE PROPS: boxes with their height written on them */
    const selP = ed.sel.kind === 'prop' ? ed.sel.ids : null;
    const hovP = this.hover?.kind === 'prop' ? this.hover.id : null;
    g.font = '10px ui-monospace, monospace';
    for (const p of d.props) {
      const x0 = this.sx(Math.min(p.x0, p.x1)), x1 = this.sx(Math.max(p.x0, p.x1));
      const y0 = this.sy(Math.max(p.y0, p.y1)), y1 = this.sy(Math.min(p.y0, p.y1));
      const sel = selP?.has(p.id), hov = p.id === hovP;
      g.fillStyle = sel ? 'rgba(255,157,61,0.3)' : 'rgba(80,190,255,0.14)';
      g.fillRect(x0, y0, x1 - x0, y1 - y0);
      g.strokeStyle = sel ? '#ff9d3d' : hov ? '#3ddc84' : '#58b9ff';
      g.lineWidth = sel || hov ? 2 : 1;
      g.setLineDash([4, 3]); g.strokeRect(x0, y0, x1 - x0, y1 - y0); g.setLineDash([]);
      if (x1 - x0 > 40 && y1 - y0 > 14) { g.fillStyle = '#9fd6ff'; g.fillText(`${p.z0}–${p.z1}`, x0 + 3, y0 + 11); }
    }

    /* THE SCATTERS: each rule's area, dashed, and what it grew, as dots
       a little dimmer than things placed by hand — they are a rule's
       output and can only be changed by changing the rule */
    const selC = ed.sel.kind === 'scatter' ? ed.sel.ids : null;
    const hovC = this.hover?.kind === 'scatter' ? this.hover.id : null;
    for (const c of d.scatters || []) {
      const sel = selC?.has(c.id), hov = c.id === hovC;
      g.strokeStyle = sel ? '#ff9d3d' : hov ? '#3ddc84' : 'rgba(200,120,255,0.7)';
      g.fillStyle = sel ? 'rgba(255,157,61,0.08)' : 'rgba(200,120,255,0.05)';
      g.lineWidth = sel || hov ? 2 : 1;
      g.setLineDash([6, 4]);
      g.beginPath();
      const a = c.area;
      if (a.kind === 'circle') g.arc(this.sx(a.x), this.sy(a.y), a.r * this.scale, 0, Math.PI * 2);
      else if (a.kind === 'rect') g.rect(this.sx(Math.min(a.x0, a.x1)), this.sy(Math.max(a.y0, a.y1)), Math.abs(a.x1 - a.x0) * this.scale, Math.abs(a.y1 - a.y0) * this.scale);
      else for (const s of d.sectors) {
        if (!(a.ids || []).includes(s.id)) continue;
        ringOf(d, s).forEach(([x, y], k) => (k ? g.lineTo(this.sx(x), this.sy(y)) : g.moveTo(this.sx(x), this.sy(y))));
        g.closePath();
      }
      g.fill(); g.stroke(); g.setLineDash([]);
      if (sel || hov || this.scale > 0.05) {
        const [b0] = scatterBox(d, c);
        g.fillStyle = sel ? '#ffcf9a' : '#d7b4ff'; g.font = '10px ui-monospace, monospace';
        const n = ed.compiled?.grown?.get(c.id);
        g.fillText(`${c.name || 'scatter'}${n ? ` · ${n.grown}` : ''}`, this.sx(b0[0]) + 3, this.sy(b0[1]) - 4);
      }
    }
    const sc = ed.compiled?.scattered || [];
    if (sc.length) {
      const r = Math.max(1.2, Math.min(4, 14 * this.scale));
      for (const t of sc) {
        const x = this.sx(t.x), y = this.sy(t.y);
        if (x < -4 || y < -4 || x > this.w + 4 || y > this.h + 4) continue;
        g.fillStyle = t.type === 'PLANT' ? plantColour(t.kind) : (THING_TYPES[t.type]?.color || '#f0f');
        g.globalAlpha = selC?.has(t.scatter) ? 1 : 0.75;
        g.fillRect(x - r, y - r, r * 2, r * 2);
      }
      g.globalAlpha = 1;
    }

    /* THE VERTICES, in vertex mode or close enough to click */
    if (ed.mode === 'vertices' || ed.mode === 'draw' || this.scale > 0.2) {
      const selV = ed.sel.kind === 'vertex' ? ed.sel.ids : null;
      const hovV = this.hover?.kind === 'vertex' ? this.hover.id : null;
      const big = ed.mode === 'vertices';
      d.vertices.forEach((v, i) => {
        const x = this.sx(v[0]), y = this.sy(v[1]);
        if (x < -8 || y < -8 || x > this.w + 8 || y > this.h + 8) return;
        const sel = selV?.has(i), hov = i === hovV;
        g.fillStyle = sel ? '#ff9d3d' : hov ? '#3ddc84' : big ? '#d8e0e4' : '#8a969e';
        const s = sel || hov ? 7 : big ? 5 : 3;
        g.fillRect(x - s / 2, y - s / 2, s, s);
      });
    }

    /* THE THINGS: a disc in the type's colour with a tick for facing */
    const selT = ed.sel.kind === 'thing' ? ed.sel.ids : null;
    const hovT = this.hover?.kind === 'thing' ? this.hover.id : null;
    for (const t of d.things) {
      const x = this.sx(t.x), y = this.sy(t.y);
      if (x < -20 || y < -20 || x > this.w + 20 || y > this.h + 20) continue;
      const def = THING_TYPES[t.type] || { color: '#f0f', radius: 16 };
      const colour = t.type === 'PLANT' ? plantColour(t.kind) : def.color;
      const r = Math.max(3, def.radius * this.scale);
      const sel = selT?.has(t.id), hov = t.id === hovT;
      g.fillStyle = colour;
      /* a thing on another layer is a ghost of itself */
      g.globalAlpha = !ed.onLayer(t) ? 0.18 : ed.mode === 'things' || sel ? 1 : 0.7;
      g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
      g.globalAlpha = 1;
      if (sel || hov) { g.strokeStyle = sel ? '#ff9d3d' : '#3ddc84'; g.lineWidth = 2; g.beginPath(); g.arc(x, y, r + 3, 0, Math.PI * 2); g.stroke(); }
      if (r > 4 || t.type === 'START') {
        const a = t.angle || 0, L = Math.max(r * 1.6, 9);
        g.strokeStyle = t.type === 'START' ? '#4af' : '#000a'; g.lineWidth = t.type === 'START' ? 2 : 1.5;
        g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * L, y - Math.sin(a) * L); g.stroke();
      }
    }

    /* THE 3D CAMERA, the way Doom Builder shows it on the plan */
    const cam = ed.view3d?.cam;
    if (cam && ed.layout !== 'only2d') {
      const x = this.sx(cam.x), y = this.sy(cam.y), a = cam.yaw, f = 0.6, L = 26;
      g.fillStyle = 'rgba(255,220,90,0.15)'; g.strokeStyle = '#ffd35a'; g.lineWidth = 1.5;
      g.beginPath(); g.moveTo(x, y);
      g.lineTo(x + Math.cos(a + f) * L, y - Math.sin(a + f) * L);
      g.lineTo(x + Math.cos(a - f) * L, y - Math.sin(a - f) * L);
      g.closePath(); g.fill(); g.stroke();
      g.fillStyle = '#ffd35a'; g.fillRect(x - 3, y - 3, 6, 6);
    }

    /* WHAT IS BEING DRAWN */
    const dr = this.drag;
    g.lineWidth = 1.5;
    if (dr?.type === 'box') {
      g.strokeStyle = '#3ddc84'; g.setLineDash([5, 4]); g.fillStyle = 'rgba(61,220,132,0.07)';
      const x = this.sx(Math.min(dr.a[0], dr.b[0])), y = this.sy(Math.max(dr.a[1], dr.b[1]));
      const w = Math.abs(dr.b[0] - dr.a[0]) * this.scale, hh = Math.abs(dr.b[1] - dr.a[1]) * this.scale;
      g.fillRect(x, y, w, hh); g.strokeRect(x, y, w, hh); g.setLineDash([]);
    }
    if (dr?.type === 'brush') {
      const r = Math.hypot(dr.b[0] - dr.a[0], dr.b[1] - dr.a[1]);
      g.strokeStyle = '#c878ff'; g.fillStyle = 'rgba(200,120,255,0.12)'; g.setLineDash([6, 4]);
      g.beginPath(); g.arc(this.sx(dr.a[0]), this.sy(dr.a[1]), r * this.scale, 0, Math.PI * 2); g.fill(); g.stroke(); g.setLineDash([]);
      g.fillStyle = '#e6ccff'; g.font = '11px ui-monospace, monospace';
      g.fillText(`r ${Math.round(r)}`, this.sx(dr.a[0]) + 6, this.sy(dr.a[1]) - 6);
    }
    if (dr?.type === 'rect' && (dr.b[0] !== dr.a[0] || dr.b[1] !== dr.a[1])) {
      /* THE SHAPE being dragged out, as it will be made */
      const pts = ed.shapePoints(dr.a, dr.b);
      g.strokeStyle = '#ffb454'; g.fillStyle = 'rgba(255,180,84,0.12)'; g.lineWidth = 1.5;
      g.beginPath();
      pts.forEach(([x, y], k) => (k ? g.lineTo(this.sx(x), this.sy(y)) : g.moveTo(this.sx(x), this.sy(y))));
      g.closePath(); g.fill(); g.stroke();
      g.fillStyle = '#ffb454';
      for (const [x, y] of pts) g.fillRect(this.sx(x) - 2, this.sy(y) - 2, 4, 4);
      g.fillStyle = '#ffd9a6'; g.font = '11px ui-monospace, monospace';
      g.fillText(`${Math.abs(dr.b[0] - dr.a[0])} × ${Math.abs(dr.b[1] - dr.a[1])}`, this.sx(Math.min(dr.a[0], dr.b[0])) + 4, this.sy(Math.max(dr.a[1], dr.b[1])) - 4);
    }
    if (dr?.type === 'prop') {
      g.strokeStyle = dr.type === 'prop' ? '#58b9ff' : '#ffb454'; g.fillStyle = dr.type === 'prop' ? 'rgba(88,185,255,0.12)' : 'rgba(255,180,84,0.12)';
      const x = this.sx(Math.min(dr.a[0], dr.b[0])), y = this.sy(Math.max(dr.a[1], dr.b[1]));
      const w = Math.abs(dr.b[0] - dr.a[0]) * this.scale, hh = Math.abs(dr.b[1] - dr.a[1]) * this.scale;
      g.fillRect(x, y, w, hh); g.strokeRect(x, y, w, hh);
      g.fillStyle = '#ffd9a6'; g.font = '11px ui-monospace, monospace';
      g.fillText(`${Math.abs(dr.b[0] - dr.a[0])} × ${Math.abs(dr.b[1] - dr.a[1])}`, x + 4, y - 4);
    }
    const path = ed.path;
    if (path.length || (ed.mode === 'draw' && ed.cursor)) {
      const pts = [...path];
      if (ed.mode === 'draw' && ed.cursor) pts.push(ed.cursor);
      g.strokeStyle = '#ffb454'; g.lineWidth = 2;
      g.beginPath();
      pts.forEach(([x, y], k) => (k ? g.lineTo(this.sx(x), this.sy(y)) : g.moveTo(this.sx(x), this.sy(y))));
      g.stroke();
      g.fillStyle = '#ffb454';
      for (const [x, y] of pts) g.fillRect(this.sx(x) - 3, this.sy(y) - 3, 6, 6);
      if (path.length >= 3) { g.strokeStyle = '#3ddc84'; g.beginPath(); g.arc(this.sx(path[0][0]), this.sy(path[0][1]), PICK_PX + 2, 0, Math.PI * 2); g.stroke(); }
      if (path.length && ed.cursor && ed.mode === 'draw') {
        /* the line being drawn: its length, and its angle, Doom's way
           (0 is east, anticlockwise) */
        const [a, b] = [path[path.length - 1], ed.cursor];
        const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
        const ang = ((Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math.PI) + 360) % 360;
        g.fillStyle = '#ffd9a6'; g.font = '11px ui-monospace, monospace';
        g.fillText(`${+len.toFixed(1)}  ${+ang.toFixed(1)}°`, this.sx((a[0] + b[0]) / 2) + 6, this.sy((a[1] + b[1]) / 2) - 6);
      }
    }
    this.drawAxes();
    /* and the snapped cursor, in the drawing modes */
    if (ed.cursor && (['draw', 'rect', 'props', 'things', 'scatter', 'vertices'].includes(ed.mode) && !dr || dr?.type === 'move' && dr.moved)) {
      const x = this.sx(ed.cursor[0]), y = this.sy(ed.cursor[1]);
      g.strokeStyle = '#ffb454'; g.lineWidth = 1;
      g.beginPath(); g.moveTo(x - 8, y); g.lineTo(x + 8, y); g.moveTo(x, y - 8); g.lineTo(x, y + 8); g.stroke();
      /* WHAT IT SNAPPED TO: a square on a vertex, a diamond on a line */
      if (ed.cursorKind === 'vertex') { g.strokeStyle = '#3ddc84'; g.lineWidth = 2; g.strokeRect(x - 6, y - 6, 12, 12); }
      if (ed.cursorKind === 'line') {
        g.strokeStyle = '#3ddc84'; g.lineWidth = 2;
        g.beginPath(); g.moveTo(x, y - 7); g.lineTo(x + 7, y); g.lineTo(x, y + 7); g.lineTo(x - 7, y); g.closePath(); g.stroke();
      }
    }
  }

  /** THE AXES AND THE ORIGIN, Blender's colours, over the map: X red
   *  along y = 0, Y green along x = 0, a ring on 0,0 — or, when 0,0 is
   *  off the screen, an arrow at the edge pointing back to it — and the
   *  two directions in the corner. */
  /** THE OTHER LAYERS, ghosted: the ones under this one as faint
   *  shapes you draw on top of, the ones over it as dashed outlines. */
  drawLayers() {
    const g = this.g, ed = this.ed, me = ed.layer;
    const others = ed.otherLayers();
    if (!others.length) return;
    for (const L of others) {
      const under = L.k < me, near = Math.abs(L.k - me) === 1;
      g.save();
      g.setLineDash(under ? [] : [6, 5]);
      g.lineWidth = 1;
      g.strokeStyle = under ? `rgba(150,170,200,${near ? 0.5 : 0.25})` : `rgba(255,200,120,${near ? 0.45 : 0.22})`;
      g.fillStyle = `rgba(120,140,170,${near ? 0.1 : 0.05})`;
      for (const s of L.sectors) {
        const r = s.verts.map(i => L.vertices[i]);
        if (r.length < 3) continue;
        g.beginPath();
        r.forEach(([x, y], k) => (k ? g.lineTo(this.sx(x), this.sy(y)) : g.moveTo(this.sx(x), this.sy(y))));
        g.closePath();
        if (under) g.fill();
        g.stroke();
      }
      g.restore();
    }
    /* which layer this is, top left of the plan */
    g.fillStyle = 'rgba(220,230,240,0.8)';
    g.font = '11px ui-monospace, monospace';
    g.textAlign = 'right';
    g.fillText(`LAYER ${me}${me === 0 ? ' · ground' : ''} · ${others.length} more`, this.w - 8, 16);
    g.textAlign = 'left';
  }

  drawAxes() {
    const g = this.g;
    const ox = Math.round(this.sx(0)) + 0.5, oy = Math.round(this.sy(0)) + 0.5;
    g.save();
    g.lineWidth = 1.5;
    g.globalAlpha = 0.8;
    if (oy >= 0 && oy <= this.h) { g.strokeStyle = AXIS_X; g.beginPath(); g.moveTo(0, oy); g.lineTo(this.w, oy); g.stroke(); }
    if (ox >= 0 && ox <= this.w) { g.strokeStyle = AXIS_Y; g.beginPath(); g.moveTo(ox, 0); g.lineTo(ox, this.h); g.stroke(); }
    g.globalAlpha = 1;
    g.font = 'bold 11px ui-monospace, monospace'; g.textBaseline = 'middle';
    const inside = ox >= 0 && ox <= this.w && oy >= 0 && oy <= this.h;
    if (inside) {
      g.strokeStyle = '#ffffff'; g.lineWidth = 1.5;
      g.beginPath(); g.arc(ox, oy, 6, 0, Math.PI * 2); g.stroke();
      g.fillStyle = '#ffffff'; g.fillRect(ox - 1.5, oy - 1.5, 3, 3);
      g.fillStyle = '#e8eef2'; g.textAlign = 'left'; g.fillText('0,0,0', ox + 9, oy - 10);
    } else {
      /* THE WAY BACK: an arrow on the edge, on the line from the middle
         of the view to the origin, and how far it is */
      const cx = this.w / 2, cy = this.h / 2, dx = ox - cx, dy = oy - cy;
      const m = 22, t = Math.min((cx - m) / Math.max(1e-6, Math.abs(dx)), (cy - m) / Math.max(1e-6, Math.abs(dy)));
      const ex = cx + dx * t, ey = cy + dy * t, a = Math.atan2(dy, dx);
      g.fillStyle = '#ffffff';
      g.beginPath();
      g.moveTo(ex + Math.cos(a) * 10, ey + Math.sin(a) * 10);
      g.lineTo(ex + Math.cos(a + 2.5) * 8, ey + Math.sin(a + 2.5) * 8);
      g.lineTo(ex + Math.cos(a - 2.5) * 8, ey + Math.sin(a - 2.5) * 8);
      g.closePath(); g.fill();
      const far = Math.round(Math.hypot(this.mx(cx), this.my(cy)));
      g.fillStyle = '#e8eef2'; g.textAlign = ex > cx ? 'right' : 'left';
      g.fillText(`0,0 · ${far}`, ex + (ex > cx ? -14 : 14), ey + (ey > cy ? -12 : 12));
    }
    /* the corner key: which way X and Y run on the plan */
    const kx = 16, ky = this.h - 34, L = 26;
    g.lineWidth = 2;
    g.strokeStyle = AXIS_X; g.beginPath(); g.moveTo(kx, ky); g.lineTo(kx + L, ky); g.stroke();
    g.strokeStyle = AXIS_Y; g.beginPath(); g.moveTo(kx, ky); g.lineTo(kx, ky - L); g.stroke();
    g.textAlign = 'center';
    g.fillStyle = AXIS_X; g.fillText('X', kx + L + 8, ky);
    g.fillStyle = AXIS_Y; g.fillText('Y', kx, ky - L - 8);
    g.fillStyle = AXIS_Z; g.beginPath(); g.arc(kx, ky, 3.5, 0, Math.PI * 2); g.fill();
    g.restore();
  }

  drawGrid() {
    const g = this.g, ed = this.ed;
    let step = ed.grid;
    while (step * this.scale < 6) step *= 2;
    this.shownStep = step;
    const x0 = this.mx(0), x1 = this.mx(this.w), y0 = this.my(this.h), y1 = this.my(0);
    const major = step * 8;
    const lineSet = (st, colour) => {
      g.strokeStyle = colour; g.lineWidth = 1;
      g.beginPath();
      for (let x = Math.floor(x0 / st) * st; x <= x1; x += st) { const px = Math.round(this.sx(x)) + 0.5; g.moveTo(px, 0); g.lineTo(px, this.h); }
      for (let y = Math.floor(y0 / st) * st; y <= y1; y += st) { const py = Math.round(this.sy(y)) + 0.5; g.moveTo(0, py); g.lineTo(this.w, py); }
      g.stroke();
    };
    /* bright enough to place a corner by, at any zoom: the step lines,
       every eighth a shade stronger */
    lineSet(step, '#18222b');
    lineSet(major, '#26343f');
    /* ZOOMED OUT PAST THE GRID: the lines drawn are coarser than the
       snap, and it says so rather than leaving you to wonder why a
       corner lands between them */
    if (step !== ed.grid && ed.snap) {
      g.fillStyle = '#6f8391'; g.font = '11px ui-monospace, monospace';
      g.fillText(`grid ${ed.grid} · lines every ${step} at this zoom — zoom in to see it`, 8, this.h - 8);
    }
  }
}

export function modeKind(mode) {
  return MODE_KIND[mode] || 'sector';
}

/** The scatter whose area a point is in — the smallest, so a small one
 *  painted inside a big one can still be picked. */
export function scatterAt(d, x, y) {
  let best = null, ba = Infinity;
  for (const c of d.scatters || []) {
    const a = c.area;
    let inside = false, size = 0;
    if (a.kind === 'circle') { inside = (x - a.x) ** 2 + (y - a.y) ** 2 <= a.r * a.r; size = a.r * a.r * Math.PI; }
    else if (a.kind === 'rect') {
      inside = x >= Math.min(a.x0, a.x1) && x <= Math.max(a.x0, a.x1) && y >= Math.min(a.y0, a.y1) && y <= Math.max(a.y0, a.y1);
      size = Math.abs((a.x1 - a.x0) * (a.y1 - a.y0));
    } else {
      for (const s of d.sectors) {
        if (!(a.ids || []).includes(s.id)) continue;
        const r = ringOf(d, s);
        if (pointIn(r, x, y)) { inside = true; }
        size += Math.abs(signedArea(r));
      }
    }
    if (inside && size < ba) { ba = size; best = c; }
  }
  return best;
}
function pointIn(r, x, y) {
  let c = false;
  for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
    const [xi, yi] = r[i], [xj, yj] = r[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}

/** The two corners of a scatter's area. */
export function scatterBox(d, c) {
  const a = c.area;
  if (a.kind === 'circle') return [[a.x - a.r, a.y - a.r], [a.x + a.r, a.y + a.r]];
  if (a.kind === 'rect') return [[Math.min(a.x0, a.x1), Math.min(a.y0, a.y1)], [Math.max(a.x0, a.x1), Math.max(a.y0, a.y1)]];
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const s of d.sectors) if ((a.ids || []).includes(s.id)) for (const [x, y] of ringOf(d, s)) {
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return x0 < Infinity ? [[x0, y0], [x1, y1]] : [[0, 0], [0, 0]];
}

/** The scatter brush let go: a circle of the current mix from where it
 *  was pressed to where it was let go — or, for a click, a circle of
 *  the brush's own size. */
export function paintBrush(ed, a, b) {
  let r = Math.hypot(b[0] - a[0], b[1] - a[1]);
  if (r < 16) r = ed.brushRadius || 512;
  ed.brushRadius = Math.round(r);
  ed.addScatter({ kind: 'circle', x: a[0], y: a[1], r: Math.round(r) });
}

/* a plant's dot: firs dark, bushes mid, cover light, street trees teal */
export function plantColour(kind = '') {
  if (kind.startsWith('fir')) return '#2f8f4a';
  if (kind.startsWith('bush')) return '#5fbf5a';
  if (kind.startsWith('street')) return '#3fb8a0';
  return '#a8e07a';
}

/**
 * THE PAD: the keys a tablet has not got, as buttons over the plan —
 * shown once a pen or a finger has touched it, or on a touch screen from
 * the start. While a shape is being drawn it offers to close it, finish
 * it as lines, take back a corner or give up; otherwise undo, redo,
 * delete, zoom and fit.
 */
export function buildPad(ed, host) {
  const doc = host?.ownerDocument;
  const pad = { show() {}, refresh() {}, el: null };
  if (!doc) return pad;
  const el = doc.createElement('div');
  el.className = 'ed-pad';
  el.hidden = true;
  const btn = (label, title, fn) => {
    const b = doc.createElement('button');
    b.className = 'ed-btn';
    b.textContent = label;
    b.title = title;
    /* on pointerdown, so a pen tap is never lost to a drag test, and not
       passed on to the plan underneath */
    b.addEventListener('pointerdown', e => { e.preventDefault(); e.stopPropagation(); fn(); pad.refresh(); });
    el.append(b);
    return b;
  };
  const b = {
    close: btn('✓ Close', 'Close the shape into a sector (click the first corner)', () => ed.closePath()),
    lines: btn('⏎ Lines', 'Finish as linedefs, or a split wall to wall (Enter)', () => ed.closePath({ open: true })),
    back: btn('⌫', 'Take back the last corner (Backspace)', () => { ed.path.pop(); ed.emit('path'); }),
    cancel: btn('✕', 'Give up the drawing (Esc)', () => { ed.cancelPath(); ed.afterDraw?.(); }),
    undo: btn('↶', 'Undo (Ctrl+Z)', () => ed.undo()),
    redo: btn('↷', 'Redo (Ctrl+Y)', () => ed.redo()),
    del: btn('🗑', 'Delete the selection (Del)', () => ed.deleteSel()),
    out: btn('−', 'Zoom out', () => ed.view2d?.zoomBy(1 / 1.5)),
    in: btn('+', 'Zoom in', () => ed.view2d?.zoomBy(1.5)),
    fit: btn('⤢', 'Frame the map (F)', () => ed.emit('frame')),
  };
  host.append(el);
  pad.el = el;
  pad.show = () => { if (el.hidden) { el.hidden = false; pad.refresh(); } };
  pad.refresh = () => {
    if (el.hidden) return;
    const n = ed.path.length, drawing = n > 0;
    b.close.hidden = n < 3;
    b.lines.hidden = n < 2;
    b.back.hidden = b.cancel.hidden = !drawing;
    b.undo.hidden = b.redo.hidden = drawing;
    b.del.hidden = drawing || !ed.sel.ids.size;
  };
  /* a touch screen shows it from the start */
  try { if (doc.defaultView?.matchMedia?.('(pointer: coarse)').matches) pad.show(); } catch (err) { /* no media queries */ }
  return pad;
}
