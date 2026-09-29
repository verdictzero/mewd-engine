## MEWD Editor — the plan (js/editor/view2d.js).
##
## The Doom Builder half: the map from above on a grid, north up. Every
## mode edits one kind of thing — vertices, lines, sectors, things,
## props, scatters — and two draw: DRAW clicks out a sector a corner at a
## time and SHAPE drags one out. Drag anything to move it; drag on
## nothing to box-select; the wheel zooms about the cursor and the right
## or middle button pans; Ctrl and the wheel is a sector's brightness. A
## drag is ONE undo, welded when it is let go. Fingers: one draws (or,
## once a pen has been used, pans), two pinch and pan.
class_name EdView2D
extends Control

const PICK_PX := 8.0
const AXIS_X := Color("#ff3352")
const AXIS_Y := Color("#8bdc00")
const AXIS_Z := Color("#4aa8ff")

var ed: MewdEditor
var cx := 5120.0
var cy := 5120.0
var scale_ := 0.08
var mouse = null
var hover = null
var drag = null
var snap_kind := "grid"
var framed := false
var shown_step := 64
var slop := 4.0
var touches := {}
var gesture = null
var pen_seen := false
var _tri_cache := {}
var _tri_key = null
var _hatch: ImageTexture
var font: Font

func _init(editor: MewdEditor) -> void:
	ed = editor
	name = "View2D"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func _ready() -> void:
	font = EdStyle.mono()
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 10:
		img.set_pixel(i, 9 - i, Color(230 / 255.0, 190 / 255.0, 130 / 255.0, 0.16))
	_hatch = ImageTexture.create_from_image(img)
	for s in [ed.doc_changed, ed.sel_changed, ed.grid_changed, ed.layout_changed, ed.compiled_ready, ed.path_changed, ed.cursor_changed, ed.camera_changed]:
		s.connect(_dirty0)
	ed.mode_changed.connect(func(_m): queue_redraw())
	ed.doc_changed.connect(func(): _tri_cache.clear())
	ed.frame_req.connect(frame)
	ed.frame_sel_req.connect(frame_sel)
	resized.connect(_on_resize)
	mouse_entered.connect(func(): ed.pointer_view = "2d")
	mouse_exited.connect(func():
		if drag == null:
			mouse = null
			hover = null
			if ed.ui != null:
				ed.ui.set_pos(null)
			ed.set_cursor(null)
			ed.set_hover(null)
			queue_redraw())

func _dirty0(_a = null) -> void:
	queue_redraw()

var _last_size := Vector2.ZERO

func _on_resize() -> void:
	# the same piece of map in view when the view changes size
	if framed and _last_size.x > 1 and _last_size.y > 1:
		scale_ *= minf(size.x / _last_size.x, size.y / _last_size.y)
	_last_size = size
	if not framed and size.x > 1:
		framed = true
		frame()
	queue_redraw()

func sx(x: float) -> float:
	return (x - cx) * scale_ + size.x / 2.0

func sy(y: float) -> float:
	return size.y / 2.0 - (y - cy) * scale_

func sp(p: Vector2) -> Vector2:
	return Vector2(sx(p.x), sy(p.y))

func mx(px: float) -> float:
	return (px - size.x / 2.0) / scale_ + cx

func my(py: float) -> float:
	return (size.y / 2.0 - py) / scale_ + cy

func to_map(pos: Vector2) -> Vector2:
	return Vector2(mx(pos.x), my(pos.y))

func fit(x0: float, y0: float, x1: float, y1: float) -> void:
	if not (x1 > x0) or not (y1 > y0):
		x0 -= 256; x1 += 256; y0 -= 256; y1 += 256
	cx = (x0 + x1) / 2.0
	cy = (y0 + y1) / 2.0
	scale_ = minf(maxf(1.0, size.x) / (x1 - x0), maxf(1.0, size.y) / (y1 - y0)) * 0.88
	queue_redraw()

func frame() -> void:
	var V: Array = ed.doc.vertices
	if V.is_empty():
		fit(-512, -512, 512, 512)
		return
	var b := EdDoc.bbox(PackedVector2Array(V))
	fit(b.position.x, b.position.y, b.end.x, b.end.y)

func frame_sel() -> void:
	var pts := sel_points()
	if pts.is_empty():
		frame()
		return
	var b := EdDoc.bbox(pts)
	fit(b.position.x - 64, b.position.y - 64, b.end.x + 64, b.end.y + 64)

func sel_points() -> PackedVector2Array:
	var d := ed.doc
	var out := PackedVector2Array()
	match ed.sel_kind:
		"vertex":
			for i in ed.sel_ids:
				if i < d.vertices.size():
					out.append(d.vertices[i])
		"line":
			for k in ed.sel_ids:
				var ab := EdDoc.key_verts(k)
				for i in [ab.x, ab.y]:
					if i >= 0 and i < d.vertices.size():
						out.append(d.vertices[i])
		"sector":
			for s in d.sectors:
				if ed.sel_ids.has(s.id):
					out.append_array(EdDoc.ring_of(d, s))
		"thing":
			for t in d.things:
				if ed.sel_ids.has(t.id):
					out.append(Vector2(t.x, t.y))
		"prop":
			for p in d.props:
				if ed.sel_ids.has(p.id):
					out.append(Vector2(p.x0, p.y0))
					out.append(Vector2(p.x1, p.y1))
		"scatter":
			for c in d.scatters:
				if ed.sel_ids.has(c.id):
					var r := EdScatter.scatter_box(d, c)
					out.append(r.position)
					out.append(r.end)
	return out

static func mode_kind(mode: String) -> String:
	return MewdEditor.MODE_KIND.get(mode, "sector")

# ---------------------------------------------------------------------
# WHAT IS UNDER THE MOUSE, in the current mode
# ---------------------------------------------------------------------

func pick(x: float, y: float, kind := ""):
	if kind == "":
		kind = mode_kind(ed.mode)
	var d := ed.doc
	var p := Vector2(x, y)
	var r := PICK_PX / scale_
	match kind:
		"scatter":
			var c = EdScatter.scatter_at(d, x, y)
			return {"kind": kind, "id": c.id} if c != null else null
		"vertex":
			var best := -1
			var bd := r * r
			for i in d.vertices.size():
				var q: float = (d.vertices[i] - p).length_squared()
				if q < bd:
					bd = q
					best = i
			return {"kind": kind, "id": best} if best >= 0 else null
		"line":
			var best = null
			var bd := r
			for l in ed.lines():
				var dist := EdDoc.seg_dist(d.vertices[l.a], d.vertices[l.b], p).x
				if dist < bd:
					bd = dist
					best = l.key
			return {"kind": kind, "id": best} if best != null else null
		"sector":
			var s = ed.sector_at(x, y)
			return {"kind": kind, "id": s.id} if s != null else null
		"thing":
			var best = null
			var bd := INF
			for t in d.things:
				if not ed.on_layer(t):
					continue
				var rad := maxf(float(EdDoc.THING_TYPES.get(t.type, {}).get("radius", 16)), r)
				var q := Vector2(t.x, t.y).distance_to(p)
				if q < rad and q < bd:
					bd = q
					best = t.id
			return {"kind": kind, "id": best} if best != null else null
		"prop":
			var best = null
			var ba := INF
			for pr in d.props:
				var x0 := minf(pr.x0, pr.x1)
				var x1 := maxf(pr.x0, pr.x1)
				var y0 := minf(pr.y0, pr.y1)
				var y1 := maxf(pr.y0, pr.y1)
				if x < x0 - r or x > x1 + r or y < y0 - r or y > y1 + r:
					continue
				var a := (x1 - x0) * (y1 - y0)
				if a < ba:
					ba = a
					best = pr.id
			return {"kind": kind, "id": best} if best != null else null
	return null

func snap_point(x: float, y: float) -> Vector2:
	var s := ed.snap_at(x, y, PICK_PX / scale_)
	snap_kind = s.kind
	return s.pt

# ---------------------------------------------------------------------
# THE MOUSE, AND FINGERS
# ---------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event)
		return
	if event is InputEventScreenDrag:
		if touches.has(event.index):
			touches[event.index] = event.position
			if gesture != null:
				_move_gesture()
				accept_event()
		return
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_wheel(e)
			accept_event()
			return
		if e.pressed:
			if e.double_click:
				_dbl(e)
			else:
				_down(e)
		else:
			_up(e)
		accept_event()
	elif event is InputEventMouseMotion:
		if gesture != null:
			return
		_move(event)
		accept_event()

func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		touches[e.index] = e.position
		if ed.ui != null:
			ed.ui.show_pad()
		if pen_seen or touches.size() >= 2:
			if touches.size() >= 2 and drag != null:
				if drag.type == "move":
					ed.end_move(drag.mv)
				drag = null
			_start_gesture()
		if e.double_tap and ed.mode == "draw" and ed.path.size() >= 2:
			ed.close_path(true)
	else:
		touches.erase(e.index)
		if gesture != null:
			if touches.is_empty():
				gesture = null
			else:
				_start_gesture()

func _start_gesture() -> void:
	var pts: Array = touches.values()
	var c := Vector2.ZERO
	for q in pts:
		c += q / pts.size()
	var spread: float = pts[0].distance_to(pts[1]) if pts.size() > 1 else 0.0
	gesture = {"n": pts.size(), "spread": spread, "scale": scale_, "x": mx(c.x), "y": my(c.y)}

func _move_gesture() -> void:
	var g: Dictionary = gesture
	var pts: Array = touches.values()
	if pts.size() != g.n:
		_start_gesture()
		return
	var c := Vector2.ZERO
	for q in pts:
		c += q / pts.size()
	if pts.size() > 1 and g.spread > 10:
		scale_ = clampf(g.scale * pts[0].distance_to(pts[1]) / g.spread, 0.005, 40.0)
	cx = g.x - (c.x - size.x / 2.0) / scale_
	cy = g.y - (size.y / 2.0 - c.y) / scale_
	queue_redraw()

func zoom_by(k: float) -> void:
	scale_ = clampf(scale_ * k, 0.005, 40.0)
	queue_redraw()

func _down(e: InputEventMouseButton) -> void:
	grab_focus()
	ed.pointer_view = "2d"
	if gesture != null:
		return
	var p := e.position
	var m := to_map(p)
	slop = 4.0
	if e.button_index == MOUSE_BUTTON_MIDDLE:
		drag = {"type": "pan", "px": p, "cx": cx, "cy": cy}
		return
	if e.button_index == MOUSE_BUTTON_RIGHT:
		if ed.mode == "draw" and not ed.path.is_empty():
			ed.close_path(true)
			return
		drag = {"type": "right", "hit": pick(m.x, m.y), "px": p, "at": m, "cx": cx, "cy": cy}
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	var mode := ed.mode
	if mode == "draw":
		var pt := snap_point(m.x, m.y)
		if ed.path.size() >= 3 and ed.path[0].distance_to(pt) * scale_ < PICK_PX + 2:
			ed.close_path()
		else:
			ed.add_path_point(pt)
		return
	if mode == "rect":
		var a := snap_point(m.x, m.y)
		drag = {"type": "rect", "a": a, "b": a}
		return
	var kind := mode_kind(mode)
	var hit = null if (mode == "scatter" and e.alt_pressed) else pick(m.x, m.y, kind)
	if hit == null:
		if mode == "props":
			var a := ed.snap_pt(m)
			drag = {"type": "prop", "a": a, "b": a}
			return
		if mode == "scatter":
			var a := ed.snap_pt(m)
			drag = {"type": "brush", "a": a, "b": a}
			return
		drag = {"type": "box", "a": m, "b": m, "add": e.shift_pressed}
		return
	if e.shift_pressed or e.ctrl_pressed:
		ed.select(kind, [hit.id], true)
		return
	# A DRAG ON THE GROUND DRAWS; Alt-drag moves it
	if mode == "sectors" and not e.alt_pressed and ed.is_ground(hit.id):
		var a := snap_point(m.x, m.y)
		drag = {"type": "rect", "a": a, "b": a, "ground": hit.id, "px": p}
		return
	if not ed.is_sel(kind, hit.id):
		ed.select(kind, [hit.id])
	drag = {"type": "move", "mv": ed.begin_move(ed.grab_point(m), m), "px": p, "moved": false}

func _move(e: InputEventMouseMotion) -> void:
	var p := e.position
	var m := to_map(p)
	mouse = m
	snap_kind = "grid"
	var snapped: Vector2 = snap_point(m.x, m.y) if ed.mode in ["draw", "rect", "vertices"] else ed.snap_pt(m)
	ed.cursor_kind = snap_kind
	ed.set_cursor(snapped)
	if ed.ui != null:
		ed.ui.set_pos(snapped)
	var dr = drag
	if dr == null:
		hover = null if ed.mode in ["draw", "rect"] else pick(m.x, m.y)
		var s = ed.sector_at(m.x, m.y)
		ed.set_hover(hover if hover != null else ({"kind": "sector", "id": s.id} if s != null else null))
		queue_redraw()
		return
	match dr.type:
		"right":
			if p.distance_to(dr.px) < slop:
				return
			if dr.hit != null:
				var kind: String = dr.hit.kind
				if not ed.is_sel(kind, dr.hit.id):
					ed.select(kind, [dr.hit.id])
				drag = {"type": "move", "mv": ed.begin_move(ed.grab_point(dr.at), dr.at), "px": dr.px, "moved": true}
			else:
				drag = {"type": "pan", "px": dr.px, "cx": dr.cx, "cy": dr.cy}
			_move(e)
			return
		"pan":
			cx = dr.cx - (p.x - dr.px.x) / scale_
			cy = dr.cy + (p.y - dr.px.y) / scale_
		"box":
			dr.b = m
		"rect":
			dr.b = snap_point(m.x, m.y)
		"prop", "brush":
			dr.b = ed.snap_pt(m)
		"move":
			if not dr.moved and p.distance_to(dr.px) < slop:
				return
			dr.moved = true
			ed.drag_move(dr.mv, m, PICK_PX / scale_)
			var at: Vector2 = dr.mv.ref + dr.mv.done
			ed.cursor_kind = dr.mv.onto
			ed.set_cursor(at)
			if ed.ui != null:
				ed.ui.set_pos(at)
	queue_redraw()

func _up(e: InputEventMouseButton) -> void:
	var dr = drag
	drag = null
	if dr == null:
		return
	match dr.type:
		"right":
			if dr.hit != null:
				if not ed.is_sel(dr.hit.kind, dr.hit.id):
					ed.select(dr.hit.kind, [dr.hit.id])
				if ed.ui != null:
					ed.ui.panels.show_tab("insp")
		"box":
			var kind := mode_kind(ed.mode)
			var x0 := minf(dr.a.x, dr.b.x)
			var x1 := maxf(dr.a.x, dr.b.x)
			var y0 := minf(dr.a.y, dr.b.y)
			var y1 := maxf(dr.a.y, dr.b.y)
			if (x1 - x0) * scale_ < 3 and (y1 - y0) * scale_ < 3:
				if not dr.add:
					ed.clear_sel()
			else:
				ed.select(kind, in_box(kind, x0, y0, x1, y1), dr.add)
		"rect":
			if dr.get("ground") != null and e.position.distance_to(dr.px) < slop:
				ed.select("sector", [dr.ground])
				ed.say("the ground — drag on it to draw a new sector; Alt-drag moves it")
			else:
				ed.add_rect(dr.a, dr.b)
		"prop":
			ed.add_prop(dr.a.x, dr.a.y, dr.b.x, dr.b.y)
		"brush":
			ed.paint_brush(dr.a, dr.b)
		"move":
			ed.end_move(dr.mv)
	queue_redraw()

func _dbl(e: InputEventMouseButton) -> void:
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	if ed.mode == "draw":
		ed.close_path(true)
		return
	if ed.mode == "things":
		var m := to_map(e.position)
		if pick(m.x, m.y, "thing") == null:
			ed.add_thing(m.x, m.y)
			return
	if ed.sel_kind != "" and ed.ui != null:
		ed.ui.panels.show_tab("insp")

func _wheel(e: InputEventMouseButton) -> void:
	var p := e.position
	var m := to_map(p)
	var up := e.button_index == MOUSE_BUTTON_WHEEL_UP
	if e.ctrl_pressed or e.meta_pressed:
		var s = ed.sector_at(m.x, m.y)
		if s == null:
			return
		var ids: Dictionary = ed.sel_ids if ed.sel_kind == "sector" and ed.sel_ids.has(s.id) else {s.id: true}
		ed.nudge_light((1 if e.shift_pressed else 16) * (1 if up else -1), ids)
		return
	var k := exp((1.0 if up else -1.0) * 100.0 * 0.0015 * maxf(1.0, e.factor))
	scale_ = clampf(scale_ * k, 0.005, 40.0)
	cx = m.x - (p.x - size.x / 2.0) / scale_
	cy = m.y - (size.y / 2.0 - p.y) / scale_
	queue_redraw()

func in_box(kind: String, x0: float, y0: float, x1: float, y1: float) -> Array:
	var d := ed.doc
	var inb := func(p: Vector2) -> bool: return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1
	var out := []
	match kind:
		"vertex":
			for i in d.vertices.size():
				if inb.call(d.vertices[i]):
					out.append(i)
		"line":
			for l in ed.lines():
				if inb.call(d.vertices[l.a]) and inb.call(d.vertices[l.b]):
					out.append(l.key)
		"sector":
			for s in d.sectors:
				var all := true
				for v in EdDoc.ring_of(d, s):
					if not inb.call(v):
						all = false
						break
				if all:
					out.append(s.id)
		"thing":
			for t in d.things:
				if ed.on_layer(t) and inb.call(Vector2(t.x, t.y)):
					out.append(t.id)
		"prop":
			for p in d.props:
				if inb.call(Vector2(p.x0, p.y0)) and inb.call(Vector2(p.x1, p.y1)):
					out.append(p.id)
		"scatter":
			for c in d.scatters:
				var r := EdScatter.scatter_box(d, c)
				if inb.call(r.position) and inb.call(r.end):
					out.append(c.id)
	return out

## Keys the plan takes before the editor does.
func key(e: InputEventKey) -> bool:
	var k := e.keycode
	if (k == KEY_COMMA or k == KEY_PERIOD) and ed.sel_kind == "thing":
		var da := (1.0 if k == KEY_COMMA else -1.0) * PI / 4.0
		var ids := ed.sel_ids
		var d := ed.edit_begin("turn")
		for t in d.things:
			if ids.has(t.id):
				t["angle"] = fposmod(EdDoc.num(t.get("angle"), 0) + da + TAU, TAU)
		ed.edit_end(false)
		return true
	var arrows := {KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_UP: Vector2(0, 1), KEY_DOWN: Vector2(0, -1)}
	if arrows.has(k) and ed.sel_kind != "":
		var step := float(ed.grid) if ed.snap else 1.0
		var s := step * 4 if e.shift_pressed else step
		ed.move_sel(arrows[k].x * s, arrows[k].y * s, "nudge")
		return true
	return false

# ---------------------------------------------------------------------
# DRAWING THE PLAN
# ---------------------------------------------------------------------

func _tris(d: Dictionary, s: Dictionary, r: PackedVector2Array) -> PackedInt32Array:
	if _tri_key != d:
		_tri_cache.clear()
		_tri_key = d
	var key := "%s:%d" % [s.id, r.size()]
	if not _tri_cache.has(key):
		_tri_cache[key] = Geometry2D.triangulate_polygon(r)
	return _tri_cache[key]

func _fill(pts: PackedVector2Array, tris: PackedInt32Array, c: Color, tex: Texture2D = null) -> void:
	if tris.is_empty():
		return
	var scr := PackedVector2Array()
	for p in pts:
		scr.append(sp(p))
	var P := PackedVector2Array()
	var U := PackedVector2Array()
	var C := PackedColorArray()
	for i in tris:
		P.append(scr[i])
		U.append(scr[i] / 10.0)
		C.append(c)
	if tex != null:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(range(P.size())), P, C, U, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())
	else:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(range(P.size())), P, C)

func _poly_line(pts: PackedVector2Array, c: Color, w: float, closed := true, dash := 0.0) -> void:
	var n := pts.size()
	if n < 2:
		return
	var m := n if closed else n - 1
	for k in m:
		var a := sp(pts[k])
		var b := sp(pts[(k + 1) % n])
		if dash > 0:
			draw_dashed_line(a, b, c, w, dash)
		else:
			draw_line(a, b, c, w, true)

func _text(pos: Vector2, s: String, c: Color, size_ := 11, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var w := -1.0
	var at := pos
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		w = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x
		at.x -= w if align == HORIZONTAL_ALIGNMENT_RIGHT else w / 2.0
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, c)

func _draw() -> void:
	var d := ed.doc
	draw_rect(Rect2(Vector2.ZERO, size), Color("#07090b"))
	_draw_grid()
	_draw_layers()
	# THE SECTORS, filled by floor height, the selection over the top
	var lo := 0.0
	var hi := 1.0
	var clo := INF
	var chi := -INF
	for s in d.sectors:
		lo = minf(lo, EdDoc.num(s.get("floor"), 0))
		hi = maxf(hi, EdDoc.num(s.get("floor"), 0))
		clo = minf(clo, EdDoc.num(s.get("ceil"), 0))
		chi = maxf(chi, EdDoc.num(s.get("ceil"), 0))
	var sel_s: bool = ed.sel_kind == "sector"
	var hov_s = hover.id if hover != null and hover.kind == "sector" else null
	var order := []
	for s in d.sectors:
		var r := EdDoc.ring_of(d, s)
		order.append([s, absf(EdDoc.signed_area(r)), r])
	order.sort_custom(func(a, b): return a[1] > b[1])
	var view := ed.plan_view
	for o in order:
		var s: Dictionary = o[0]
		var r: PackedVector2Array = o[2]
		if r.size() < 3:
			continue
		var tris := _tris(d, s, r)
		var is_sel: bool = sel_s and ed.sel_ids.has(s.id)
		var f := EdDoc.num(s.get("floor"), 0)
		var t := (f - lo) / (hi - lo if hi - lo != 0 else 1.0)
		var shut := EdDoc.num(s.get("ceil"), 256) <= f
		var inside := MewdEditor.is_inside(s)
		if view != "normal":
			var v := 0.0
			if view == "light":
				v = MewdEditor.bright_of(s) / 255.0
			elif view == "floor":
				v = (f - lo) / (hi - lo if hi - lo != 0 else 1.0)
			else:
				v = (EdDoc.num(s.get("ceil"), 0) - clo) / (chi - clo if chi - clo != 0 else 1.0)
			var c := Color(v, v, v, 0.85) if view == "light" else Color((40 + v * 215) / 255.0, (60 + (1 - absf(v - 0.5) * 2) * 120) / 255.0, (255 - v * 215) / 255.0, 0.6)
			_fill(r, tris, Color(1, 157 / 255.0, 61 / 255.0, 0.55) if is_sel else c)
			continue
		var fc: Color
		if is_sel:
			fc = Color(1, 157 / 255.0, 61 / 255.0, 0.28)
		elif hov_s != null and s.id == hov_s:
			fc = Color(61 / 255.0, 220 / 255.0, 132 / 255.0, 0.16)
		elif shut:
			fc = Color(90 / 255.0, 90 / 255.0, 90 / 255.0, 0.35)
		elif inside:
			fc = Color((120 + t * 60) / 255.0, (90 + t * 40) / 255.0, (55 + t * 20) / 255.0, 0.32)
		else:
			fc = Color((30 + t * 40) / 255.0, (60 + t * 90) / 255.0, (50 + t * 40) / 255.0, 0.22)
		_fill(r, tris, fc)
		if inside and scale_ > 0.02:
			_fill(r, tris, Color.WHITE, _hatch)
	# the numbers, in the plan's views
	if view != "normal" and scale_ > 0.03:
		for s in d.sectors:
			var r := EdDoc.ring_of(d, s)
			if r.size() < 3:
				continue
			var c := sp(EdDoc.centroid(r))
			var v := MewdEditor.bright_of(s) if view == "light" else int(EdDoc.num(s.get("floor") if view == "floor" else s.get("ceil"), 0))
			_text(c + Vector2(1, 1), str(v), Color(0, 0, 0, 0.66), 11, HORIZONTAL_ALIGNMENT_CENTER)
			_text(c, str(v), Color.WHITE, 11, HORIZONTAL_ALIGNMENT_CENTER)
	# THE LINES: one-sided white, two-sided grey, blocking red
	var sel_l: bool = ed.sel_kind == "line"
	var hov_l = hover.id if hover != null and hover.kind == "line" else null
	for l in ed.lines():
		if l.a >= d.vertices.size() or l.b >= d.vertices.size():
			continue
		var a: Vector2 = d.vertices[l.a]
		var b: Vector2 = d.vertices[l.b]
		var o = d.lines.get(l.key)
		var is_sel: bool = sel_l and ed.sel_ids.has(l.key)
		var hov: bool = hov_l != null and l.key == hov_l
		var free: bool = l.get("free", false)
		var ext := EdView3D.exterior_wall(d, l)
		var door: bool = not ext and o != null and o.get("opening", false)
		var c: Color
		if is_sel: c = Color("#ff9d3d")
		elif hov: c = Color("#3ddc84")
		elif free: c = Color("#ffd23d")
		elif o != null and o.get("blocking", false): c = Color("#ff6b6b")
		elif ext: c = Color("#f0dcb4")
		elif door: c = Color("#c9a46a")
		elif l.sectors.size() > 1: c = Color("#6d7a86")
		else: c = Color("#e6edf0")
		var w := 2.5 if (is_sel or hov) else (3.0 if free else (2.0 if ext else (1.0 if l.sectors.size() > 1 else 1.6)))
		if door:
			draw_dashed_line(sp(a), sp(b), c, w, 5)
		else:
			draw_line(sp(a), sp(b), c, w, true)
		if ed.mode == "lines" and a.distance_to(b) > 24 / scale_:
			var m := (a + b) / 2.0
			var L := a.distance_to(b)
			var n := Vector2((b.y - a.y) / L, -(b.x - a.x) / L)
			draw_line(sp(m), sp(m) + Vector2(n.x * 6, -n.y * 6), c, w)
	# THE PROPS: boxes with their height on them
	var sel_p: bool = ed.sel_kind == "prop"
	var hov_p = hover.id if hover != null and hover.kind == "prop" else null
	for p in d.props:
		var x0 := sx(minf(p.x0, p.x1))
		var x1 := sx(maxf(p.x0, p.x1))
		var y0 := sy(maxf(p.y0, p.y1))
		var y1 := sy(minf(p.y0, p.y1))
		var is_sel: bool = sel_p and ed.sel_ids.has(p.id)
		var hov: bool = hov_p != null and p.id == hov_p
		draw_rect(Rect2(x0, y0, x1 - x0, y1 - y0), Color(1, 157 / 255.0, 61 / 255.0, 0.3) if is_sel else Color(80 / 255.0, 190 / 255.0, 1, 0.14))
		var c := Color("#ff9d3d") if is_sel else (Color("#3ddc84") if hov else Color("#58b9ff"))
		_dash_rect(Rect2(x0, y0, x1 - x0, y1 - y0), c, 2.0 if (is_sel or hov) else 1.0, 4)
		if x1 - x0 > 40 and y1 - y0 > 14:
			_text(Vector2(x0 + 3, y0 + 11), "%s–%s" % [EdUI.coord(p.z0), EdUI.coord(p.z1)], Color("#9fd6ff"), 10)
	# THE SCATTERS: each rule's area, dashed, and what it grew
	var sel_c: bool = ed.sel_kind == "scatter"
	var hov_c = hover.id if hover != null and hover.kind == "scatter" else null
	for c in d.get("scatters", []):
		var is_sel: bool = sel_c and ed.sel_ids.has(c.id)
		var hov: bool = hov_c != null and c.id == hov_c
		var sc := Color("#ff9d3d") if is_sel else (Color("#3ddc84") if hov else Color(200 / 255.0, 120 / 255.0, 1, 0.7))
		var fc := Color(1, 157 / 255.0, 61 / 255.0, 0.08) if is_sel else Color(200 / 255.0, 120 / 255.0, 1, 0.05)
		var w := 2.0 if (is_sel or hov) else 1.0
		var a: Dictionary = c.area
		if a.kind == "circle":
			var ctr := sp(Vector2(a.x, a.y))
			draw_circle(ctr, a.r * scale_, fc)
			_dash_circle(ctr, a.r * scale_, sc, w)
		elif a.kind == "rect":
			var rr := Rect2(sx(minf(a.x0, a.x1)), sy(maxf(a.y0, a.y1)), absf(a.x1 - a.x0) * scale_, absf(a.y1 - a.y0) * scale_)
			draw_rect(rr, fc)
			_dash_rect(rr, sc, w, 6)
		else:
			for s in d.sectors:
				if a.get("ids", []).has(s.id):
					var r := EdDoc.ring_of(d, s)
					_fill(r, _tris(d, s, r), fc)
					_poly_line(r, sc, w, true, 6)
		if is_sel or hov or scale_ > 0.05:
			var b0 := EdScatter.scatter_box(d, c)
			var g = ed.compiled.get("grown", {}).get(c.id)
			_text(sp(b0.position) + Vector2(3, -4), "%s%s" % [c.get("name", "scatter"), (" · %d" % g.grown) if g != null and g.grown else ""],
				Color("#ffcf9a") if is_sel else Color("#d7b4ff"), 10)
	var scattered: Array = ed.compiled.get("scattered", [])
	if not scattered.is_empty():
		var r := clampf(14 * scale_, 1.2, 4.0)
		for t in scattered:
			var q := sp(Vector2(t.x, t.y))
			if q.x < -4 or q.y < -4 or q.x > size.x + 4 or q.y > size.y + 4:
				continue
			var cc: Color = EdScatter.plant_colour(t.get("kind")) if t.type == "PLANT" else EdDoc.col(EdDoc.THING_TYPES.get(t.type, {}).get("color", "#f0f"))
			cc.a = 1.0 if (sel_c and ed.sel_ids.has(t.get("scatter"))) else 0.75
			draw_rect(Rect2(q.x - r, q.y - r, r * 2, r * 2), cc)
	# THE VERTICES, in vertex mode or close enough to click
	if ed.mode == "vertices" or ed.mode == "draw" or scale_ > 0.2:
		var sel_v: bool = ed.sel_kind == "vertex"
		var hov_v = hover.id if hover != null and hover.kind == "vertex" else null
		var big := ed.mode == "vertices"
		for i in d.vertices.size():
			var q := sp(d.vertices[i])
			if q.x < -8 or q.y < -8 or q.x > size.x + 8 or q.y > size.y + 8:
				continue
			var is_sel: bool = sel_v and ed.sel_ids.has(i)
			var hov: bool = hov_v != null and i == hov_v
			var c := Color("#ff9d3d") if is_sel else (Color("#3ddc84") if hov else (Color("#d8e0e4") if big else Color("#8a969e")))
			var s := 7.0 if (is_sel or hov) else (5.0 if big else 3.0)
			draw_rect(Rect2(q.x - s / 2, q.y - s / 2, s, s), c)
	# THE THINGS: a disc in the type's colour with a tick for facing
	var sel_t: bool = ed.sel_kind == "thing"
	var hov_t = hover.id if hover != null and hover.kind == "thing" else null
	for t in d.things:
		var q := sp(Vector2(t.x, t.y))
		if q.x < -20 or q.y < -20 or q.x > size.x + 20 or q.y > size.y + 20:
			continue
		var def: Dictionary = EdDoc.THING_TYPES.get(t.type, {"color": "#f0f", "radius": 16})
		var colour: Color = EdScatter.plant_colour(t.get("kind")) if t.type == "PLANT" else EdDoc.col(def.color)
		var r := maxf(3.0, def.radius * scale_)
		var is_sel: bool = sel_t and ed.sel_ids.has(t.id)
		var hov: bool = hov_t != null and t.id == hov_t
		colour.a = 0.18 if not ed.on_layer(t) else (1.0 if (ed.mode == "things" or is_sel) else 0.7)
		draw_circle(q, r, colour)
		if is_sel or hov:
			draw_arc(q, r + 3, 0, TAU, 32, Color("#ff9d3d") if is_sel else Color("#3ddc84"), 2.0, true)
		if r > 4 or t.type == "START":
			var a := EdDoc.num(t.get("angle"), 0)
			var L := maxf(r * 1.6, 9.0)
			draw_line(q, q + Vector2(cos(a) * L, -sin(a) * L), Color("#44aaff") if t.type == "START" else Color(0, 0, 0, 0.66), 2.0 if t.type == "START" else 1.5, true)
	# THE 3D CAMERA, as Doom Builder shows it on the plan
	if ed.view3d != null and ed.view3d.cam != null and ed.layout != "only2d":
		var cam: Dictionary = ed.view3d.cam
		var q := sp(Vector2(cam.x, cam.y))
		var a: float = cam.yaw
		var f := 0.6
		var L := 26.0
		var tri := PackedVector2Array([q, q + Vector2(cos(a + f) * L, -sin(a + f) * L), q + Vector2(cos(a - f) * L, -sin(a - f) * L)])
		draw_colored_polygon(tri, Color(1, 220 / 255.0, 90 / 255.0, 0.15))
		tri.append(q)
		draw_polyline(tri, Color("#ffd35a"), 1.5, true)
		draw_rect(Rect2(q.x - 3, q.y - 3, 6, 6), Color("#ffd35a"))
	# WHAT IS BEING DRAWN
	var dr = drag
	if dr != null and dr.type == "box":
		var rr := Rect2(sx(minf(dr.a.x, dr.b.x)), sy(maxf(dr.a.y, dr.b.y)), absf(dr.b.x - dr.a.x) * scale_, absf(dr.b.y - dr.a.y) * scale_)
		draw_rect(rr, Color(61 / 255.0, 220 / 255.0, 132 / 255.0, 0.07))
		_dash_rect(rr, Color("#3ddc84"), 1.5, 5)
	if dr != null and dr.type == "brush":
		var r: float = dr.a.distance_to(dr.b)
		var ctr := sp(dr.a)
		draw_circle(ctr, r * scale_, Color(200 / 255.0, 120 / 255.0, 1, 0.12))
		_dash_circle(ctr, r * scale_, Color("#c878ff"), 1.5)
		_text(ctr + Vector2(6, -6), "r %d" % roundi(r), Color("#e6ccff"))
	if dr != null and dr.type == "rect" and dr.b != dr.a:
		var pts := ed.shape_points(dr.a, dr.b)
		var tris := Geometry2D.triangulate_polygon(pts)
		_fill(pts, tris, Color(1, 180 / 255.0, 84 / 255.0, 0.12))
		_poly_line(pts, Color("#ffb454"), 1.5)
		for q in pts:
			var s := sp(q)
			draw_rect(Rect2(s.x - 2, s.y - 2, 4, 4), Color("#ffb454"))
		_text(Vector2(sx(minf(dr.a.x, dr.b.x)) + 4, sy(maxf(dr.a.y, dr.b.y)) - 4), "%s × %s" % [EdUI.coord(absf(dr.b.x - dr.a.x)), EdUI.coord(absf(dr.b.y - dr.a.y))], Color("#ffd9a6"))
	if dr != null and dr.type == "prop":
		var rr := Rect2(sx(minf(dr.a.x, dr.b.x)), sy(maxf(dr.a.y, dr.b.y)), absf(dr.b.x - dr.a.x) * scale_, absf(dr.b.y - dr.a.y) * scale_)
		draw_rect(rr, Color(88 / 255.0, 185 / 255.0, 1, 0.12))
		draw_rect(rr, Color("#58b9ff"), false, 1.5)
		_text(rr.position + Vector2(4, -4), "%s × %s" % [EdUI.coord(absf(dr.b.x - dr.a.x)), EdUI.coord(absf(dr.b.y - dr.a.y))], Color("#ffd9a6"))
	var path := ed.path
	if not path.is_empty() or (ed.mode == "draw" and ed.cursor != null):
		var pts := PackedVector2Array(path)
		if ed.mode == "draw" and ed.cursor != null:
			pts.append(ed.cursor)
		_poly_line(pts, Color("#ffb454"), 2.0, false)
		for q in pts:
			var s := sp(q)
			draw_rect(Rect2(s.x - 3, s.y - 3, 6, 6), Color("#ffb454"))
		if path.size() >= 3:
			draw_arc(sp(path[0]), PICK_PX + 2, 0, TAU, 24, Color("#3ddc84"), 2.0, true)
		if not path.is_empty() and ed.cursor != null and ed.mode == "draw":
			var a: Vector2 = path[path.size() - 1]
			var b: Vector2 = ed.cursor
			var len := a.distance_to(b)
			var ang := fposmod(rad_to_deg(atan2(b.y - a.y, b.x - a.x)), 360.0)
			_text(sp((a + b) / 2.0) + Vector2(6, -6), "%s  %s°" % [str(snappedf(len, 0.1)), str(snappedf(ang, 0.1))], Color("#ffd9a6"))
	_draw_axes()
	# the snapped cursor, in the drawing modes
	var moving: bool = dr != null and dr.type == "move" and dr.moved
	if ed.cursor != null and ((ed.mode in ["draw", "rect", "props", "things", "scatter", "vertices"] and dr == null) or moving):
		var q := sp(ed.cursor)
		draw_line(q - Vector2(8, 0), q + Vector2(8, 0), Color("#ffb454"), 1.0)
		draw_line(q - Vector2(0, 8), q + Vector2(0, 8), Color("#ffb454"), 1.0)
		if ed.cursor_kind == "vertex":
			draw_rect(Rect2(q.x - 6, q.y - 6, 12, 12), Color("#3ddc84"), false, 2.0)
		if ed.cursor_kind == "line":
			draw_polyline(PackedVector2Array([q + Vector2(0, -7), q + Vector2(7, 0), q + Vector2(0, 7), q + Vector2(-7, 0), q + Vector2(0, -7)]), Color("#3ddc84"), 2.0)

func _dash_rect(r: Rect2, c: Color, w: float, dash: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var cc := r.end
	var dd := Vector2(r.position.x, r.end.y)
	draw_dashed_line(a, b, c, w, dash)
	draw_dashed_line(b, cc, c, w, dash)
	draw_dashed_line(cc, dd, c, w, dash)
	draw_dashed_line(dd, a, c, w, dash)

func _dash_circle(ctr: Vector2, r: float, c: Color, w: float) -> void:
	var n := clampi(int(r * TAU / 10.0), 12, 256)
	for i in n:
		if i % 2:
			continue
		var a0 := i * TAU / n
		var a1 := (i + 1) * TAU / n
		draw_line(ctr + Vector2(cos(a0), sin(a0)) * r, ctr + Vector2(cos(a1), sin(a1)) * r, c, w)

## THE OTHER LAYERS, ghosted: under this one faint, over it dashed.
func _draw_layers() -> void:
	var me := ed.layer()
	var others := ed.other_layers()
	if others.is_empty():
		return
	for L in others:
		var under: bool = L.k < me
		var near: bool = absi(L.k - me) == 1
		var sc := Color(150 / 255.0, 170 / 255.0, 200 / 255.0, 0.5 if near else 0.25) if under else Color(1, 200 / 255.0, 120 / 255.0, 0.45 if near else 0.22)
		var fc := Color(120 / 255.0, 140 / 255.0, 170 / 255.0, 0.1 if near else 0.05)
		for s in L.sectors:
			var r := PackedVector2Array()
			for i in s.verts:
				r.append(L.vertices[i])
			if r.size() < 3:
				continue
			if under:
				_fill(r, Geometry2D.triangulate_polygon(r), fc)
			_poly_line(r, sc, 1.0, true, 0.0 if under else 6.0)
	_text(Vector2(size.x - 8, 16), "LAYER %d%s · %d more" % [me, " · ground" if me == 0 else "", others.size()], Color(220 / 255.0, 230 / 255.0, 240 / 255.0, 0.8), 11, HORIZONTAL_ALIGNMENT_RIGHT)

## THE AXES AND THE ORIGIN, Blender's colours.
func _draw_axes() -> void:
	var ox := roundf(sx(0)) + 0.5
	var oy := roundf(sy(0)) + 0.5
	if oy >= 0 and oy <= size.y:
		draw_line(Vector2(0, oy), Vector2(size.x, oy), Color(AXIS_X, 0.8), 1.5)
	if ox >= 0 and ox <= size.x:
		draw_line(Vector2(ox, 0), Vector2(ox, size.y), Color(AXIS_Y, 0.8), 1.5)
	var inside := ox >= 0 and ox <= size.x and oy >= 0 and oy <= size.y
	if inside:
		draw_arc(Vector2(ox, oy), 6, 0, TAU, 20, Color.WHITE, 1.5, true)
		draw_rect(Rect2(ox - 1.5, oy - 1.5, 3, 3), Color.WHITE)
		_text(Vector2(ox + 9, oy - 6), "0,0,0", Color("#e8eef2"), 11)
	else:
		var c := size / 2.0
		var dv := Vector2(ox, oy) - c
		var m := 22.0
		var t := minf((c.x - m) / maxf(1e-6, absf(dv.x)), (c.y - m) / maxf(1e-6, absf(dv.y)))
		var e := c + dv * t
		var a := atan2(dv.y, dv.x)
		draw_colored_polygon(PackedVector2Array([e + Vector2(cos(a), sin(a)) * 10, e + Vector2(cos(a + 2.5), sin(a + 2.5)) * 8, e + Vector2(cos(a - 2.5), sin(a - 2.5)) * 8]), Color.WHITE)
		var far := roundi(Vector2(mx(c.x), my(c.y)).length())
		_text(e + Vector2(-14 if e.x > c.x else 14, -12 if e.y > c.y else 16), "0,0 · %d" % far, Color("#e8eef2"), 11,
			HORIZONTAL_ALIGNMENT_RIGHT if e.x > c.x else HORIZONTAL_ALIGNMENT_LEFT)
	# the corner key: which way X and Y run on the plan
	var k := Vector2(16, size.y - 34)
	var L := 26.0
	draw_line(k, k + Vector2(L, 0), AXIS_X, 2.0)
	draw_line(k, k + Vector2(0, -L), AXIS_Y, 2.0)
	_text(k + Vector2(L + 8, 4), "X", AXIS_X, 11, HORIZONTAL_ALIGNMENT_CENTER)
	_text(k + Vector2(0, -L - 4), "Y", AXIS_Y, 11, HORIZONTAL_ALIGNMENT_CENTER)
	draw_circle(k, 3.5, AXIS_Z)

func _draw_grid() -> void:
	var step := ed.grid
	while step * scale_ < 6:
		step *= 2
	shown_step = step
	var x0 := mx(0)
	var x1 := mx(size.x)
	var y0 := my(size.y)
	var y1 := my(0)
	var line_set := func(st: float, colour: Color) -> void:
		var pts := PackedVector2Array()
		var x := floorf(x0 / st) * st
		while x <= x1:
			var px := roundf(sx(x)) + 0.5
			pts.append(Vector2(px, 0))
			pts.append(Vector2(px, size.y))
			x += st
		var y := floorf(y0 / st) * st
		while y <= y1:
			var py := roundf(sy(y)) + 0.5
			pts.append(Vector2(0, py))
			pts.append(Vector2(size.x, py))
			y += st
		if not pts.is_empty():
			draw_multiline(pts, colour, 1.0)
	line_set.call(float(step), Color("#18222b"))
	line_set.call(float(step * 8), Color("#26343f"))
	if step != ed.grid and ed.snap:
		_text(Vector2(8, size.y - 8), "grid %d · lines every %d at this zoom — zoom in to see it" % [ed.grid, step], Color("#6f8391"), 11)
