## MEWD Editor — what goes in the panels (js/editor/ui.js): the
## INSPECTOR down the right, always showing what is selected, and the
## tabs down the left — the texture browser, the things editor, the
## scatter tab and the map's own settings with its problem report.
##
## THE INSPECTOR EDITS EVERYTHING SELECTED AT ONCE: it shows the first
## and writes a changed field to all of them, one undo step each. A map
## is blocks on the ground: a block has a height, a base (or none: it
## stands on what is under it), its sides, its top, its underside, and
## the light of the space under it; the ground has a texture and the
## light of the open air.
class_name EdPanels
extends RefCounted

var ed: MewdEditor
var ui: EdUI
var insp: VBoxContainer
var insp_scroll: ScrollContainer
var insp_panel: PanelContainer
var panes := {}
var tab_btns := {}
var tab := "tex"
## the texture field the browser is picking for: {field, label, allow_none}
var picking = null
var current = null
var tex_filter := ""
var steps := {"kind": "stairs", "stepH": 16, "count": 0, "to": "", "headroom": true}
var thing_filter = null
var thing_search := ""
var _dirty := {}
var _thumbs := {}
var _tex_cells := {}
var _tex_built := false
var _tex_box: VBoxContainer
var _tex_head: VBoxContainer
var _mine_head: HBoxContainer
var _mine_grid: GridContainer
var _pack_box: VBoxContainer
var _groups := []
## the layers tab: the map's storeys, Photoshop's way (ed_layers.gd)
var layers: EdLayers

func _init(editor: MewdEditor, frame: EdUI) -> void:
	ed = editor
	ui = frame

func build() -> void:
	# THE INSPECTOR, down the right
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 0)
	ui.insp_side.add_child(iv)
	var head := EdStyle.label("INSPECTOR", EdStyle.DIM, 9, EdStyle.bold(true))
	head.custom_minimum_size.y = 22
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hb := PanelContainer.new()
	var hs := EdStyle.box(EdStyle.PANEL, Color(0, 0, 0, 0), 0, 0, Vector4(8, 0, 8, 0))
	hs.border_color = EdStyle.ACCENT
	hs.border_width_bottom = 1
	hb.add_theme_stylebox_override("panel", hs)
	hb.add_child(head)
	iv.add_child(hb)
	insp_scroll = _scroll()
	iv.add_child(insp_scroll)
	insp = _pane_box(insp_scroll)
	insp_panel = hb
	# THE TABS, down the left
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	ui.side.add_child(sv)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	sv.add_child(tabs)
	for pair in [["tex", "Textures"], ["things", "Things"], ["scatter", "Scatter"], ["layers", "Layers"], ["map", "Map"]]:
		var k: String = pair[0]
		var b := Button.new()
		b.text = pair[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 22
		b.add_theme_font_size_override("font_size", 10)
		b.pressed.connect(func(): show_tab(k))
		tab_btns[k] = b
		tabs.add_child(b)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(holder)
	for k in ["tex", "things", "scatter", "map"]:
		var sc := _scroll()
		sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(sc)
		panes[k] = {"scroll": sc, "box": _pane_box(sc)}
	# the layers: a tree, scrolled by itself, the height of the tab
	layers = EdLayers.new(ed, ui)
	var lb := layers.build(holder)
	panes["layers"] = {"scroll": lb, "box": lb}
	_tex_box = panes.tex.box
	show_tab("tex")
	ed.sel_changed.connect(func():
		if tab == "layers":
			layers.sel_changed()
		if picking == null:
			mark("insp")
		mark("tex")
		if tab == "things":
			mark("things"))
	ed.doc_changed.connect(func():
		if tab == "layers":
			mark("layers")
		mark("insp")
		if tab == "map":
			mark("map")
		if tab == "things":
			mark("things"))
	ed.compiled_ready.connect(func():
		if ed.sel_kind == "scatter":
			mark("insp")
		if tab == "scatter":
			mark("scatter")
		if tab == "map":
			mark("map"))
	ed.textures_changed.connect(func(): _tex_built = false; mark("tex"))
	ed.layer_changed.connect(func(_k): mark("insp"); mark("layers"))
	ed.layers_shown_changed.connect(func(): mark("layers"))
	var t := Timer.new()
	t.wait_time = 0.05
	t.autostart = true
	t.timeout.connect(_flush)
	ui.add_child(t)
	render_insp()

func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return sc

func _pane_box(sc: ScrollContainer) -> VBoxContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v

## a redraw is asked for, and done once, a moment later — never while
## the field being typed in would be pulled out from under the typist
func mark(what: String) -> void:
	_dirty[what] = true

func _typing() -> bool:
	var f := ui.get_viewport().gui_get_focus_owner()
	return f is LineEdit

func _flush() -> void:
	if _dirty.is_empty():
		return
	var typing := _typing()
	for k in _dirty.keys():
		if typing and k in ["insp", "map", "things"]:
			continue
		# not while a drag moves the map: once, when it is let go
		if k == "layers" and (ed.dragging or tab != "layers"):
			if tab != "layers":
				_dirty.erase(k)
			continue
		_dirty.erase(k)
		match k:
			"insp": render_insp()
			"tex": render_tex()
			"things": render_things()
			"scatter": render_scatter()
			"map": render_map()
			"layers": layers.render()

func show_tab(t: String) -> void:
	if t == "insp":
		flash_insp()
		return
	for k in panes:
		panes[k].scroll.visible = k == t
	for k in tab_btns:
		var b: Button = tab_btns[k]
		var on: bool = k == t
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = EdStyle.ACCENT if on else Color(0, 0, 0, 0)
		sb.border_width_bottom = 1
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_color_override("font_color", Color.WHITE if on else EdStyle.DIM)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	tab = t
	match t:
		"tex": render_tex()
		"map": render_map()
		"scatter": render_scatter()
		"things": render_things()
		"layers": layers.render()

func flash_insp() -> void:
	var tw := insp_panel.create_tween()
	insp_panel.modulate = Color(1.4, 1.2, 0.9)
	tw.tween_property(insp_panel, "modulate", Color.WHITE, 0.6)

static func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

static func _put(box: Container, items: Array) -> void:
	for it in items:
		if it == null:
			continue
		if it is Array:
			_put(box, it)
		else:
			box.add_child(it)

# ---------------------------------------------------------------------
# writing to the selection
# ---------------------------------------------------------------------

## Write fn(obj) into every selected object of the current kind.
func each(label: String, fn: Callable) -> void:
	var kind := ed.sel_kind
	var ids := ed.sel_ids
	var d := ed.edit_begin(label)
	match kind:
		"block":
			for s in d.blocks:
				if ids.has(s.id):
					fn.call(s)
		"ground":
			fn.call(d.ground)
		"thing":
			for t in d.things:
				if ids.has(t.id):
					fn.call(t)
		"scatter":
			for p in d.scatters:
				if ids.has(p.id):
					fn.call(p)
		"vertex":
			for i in ids:
				if i >= 0 and i < d.vertices.size():
					var box := {"v": d.vertices[i]}
					fn.call(box)
					d.vertices[i] = box.v
		"line":
			for k in ids:
				if not d.lines.has(k):
					d.lines[k] = {}
				fn.call(d.lines[k])
				if d.lines[k].is_empty():
					d.lines.erase(k)
	ed.edit_end(kind == "vertex")

## A field deeper in an object: 'sides.12.upperTex'.
static func set_path(o: Dictionary, path: String, v) -> void:
	var ks := path.split(".")
	var t := o
	for i in ks.size() - 1:
		if not t.get(ks[i]) is Dictionary:
			t[ks[i]] = {}
		t = t[ks[i]]
	t[ks[ks.size() - 1]] = v

static func del_path(o: Dictionary, path: String) -> void:
	var ks := path.split(".")
	var chain := [o]
	for i in ks.size() - 1:
		var t = chain[chain.size() - 1].get(ks[i])
		if not t is Dictionary:
			return
		chain.append(t)
	chain[chain.size() - 1].erase(ks[ks.size() - 1])
	for i in range(chain.size() - 1, 0, -1):
		if chain[i].is_empty():
			chain[i - 1].erase(ks[i - 1])
		else:
			break

# ---------------------------------------------------------------------
# swatches
# ---------------------------------------------------------------------

## A texture's picture, for a swatch (SKY is the map's own sky).
func thumb(name) -> Texture2D:
	if name == null or str(name) == "":
		return null
	var n := str(name)
	if n == "SKY":
		var sky: Dictionary = ed.doc.world.get("sky", {}) if ed.doc.world.get("sky") is Dictionary else {}
		var g := Gradient.new()
		g.set_color(0, EdDoc.col(sky.get("zenith", "#000000"), Color.BLACK))
		g.set_color(1, EdDoc.col(sky.get("horizon", "#1d9a48"), Color.GREEN))
		g.add_point(0.5, EdDoc.col(sky.get("mid", "#06301a"), Color.DARK_GREEN))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 16
		gt.height = 16
		return gt
	if TexBank.map_own.has(n):
		return TexBank.map_own[n][0]
	if _thumbs.has(n):
		return _thumbs[n]
	var path := ""
	if TexBank.OWN.has(n):
		path = TexBank.OWN[n][0]
	else:
		path = TexBank.DIR + n + ".png"
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_thumbs[n] = t
	return t

func swatch(name, size := 18) -> Control:
	var r := TextureRect.new()
	r.texture = thumb(name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A texture field (.ed-tex): click to pick it from the browser.
func tex_field(value, field: String, label: String, allow_none := false) -> Control:
	var p := PanelContainer.new()
	var picking_this: bool = picking != null and picking.field == field
	p.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.FIELD, EdStyle.ACCENT2 if picking_this else EdStyle.LINE, 3, 1, Vector4(2, 1, 2, 1)))
	p.custom_minimum_size.y = 22
	p.tooltip_text = "click to pick from the browser"
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	hb.add_child(swatch(value))
	var v := "" if value == null else str(value)
	# (empty: a fill in an opening is nothing there; a skin is the room's walls)
	var empty := "— nothing —" if field.ends_with("midTex") or field == "@loop.mid" else "— same as wall —"
	var l := EdStyle.label(v if v != "" else (empty if allow_none else "—"), EdStyle.TEXT, 10, EdStyle.mono())
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picking = {"field": field, "label": label, "allow_none": allow_none}
			if ed.tabs_hidden:
				ed.tabs_hidden = false
				ui.refresh_bar()
			show_tab("tex")
			render_insp())
	return EdStyle.row(label, [p])

func facing_buttons(onset: Callable) -> Control:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 3)
	g.add_theme_constant_override("v_separation", 3)
	for pair in [["NW", 135], ["N", 90], ["NE", 45], ["W", 180], ["", null], ["E", 0], ["SW", 225], ["S", 270], ["SE", 315]]:
		if pair[1] == null:
			g.add_child(Control.new())
			continue
		var deg: int = pair[1]
		var b := EdStyle.small_button(pair[0], func(): onset.call(snappedf(deg * PI / 180.0, 0.0001)), "%d°" % deg)
		b.custom_minimum_size = Vector2(34, 22)
		g.add_child(b)
	g.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return g

func seg(opts: Array) -> Control:
	# opts: [[label, on, callable, tip]]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)
	for o in opts:
		var b := EdStyle.button(o[0], o[2], "", o[3] if o.size() > 3 else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 20
		b.add_theme_font_size_override("font_size", 10)
		var sb := EdStyle.box(Color("#17301f") if o[1] else EdStyle.FIELD, EdStyle.ACCENT if o[1] else EdStyle.LINE, 3, 1, Vector4(4, 1, 4, 1))
		b.add_theme_stylebox_override("normal", sb)
		if o[1]:
			b.add_theme_color_override("font_color", Color.WHITE)
		hb.add_child(b)
	return hb

func bright_row(value: float, lo: float, hi: float, step: float, onset: Callable, num_step: float, tip := "") -> Control:
	var hb := HBoxContainer.new()
	var sl := EdStyle.slider(value, lo, hi, step, onset, tip)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sl)
	var n := EdStyle.num(value, onset, num_step)
	n.custom_minimum_size.x = 56
	n.size_flags_horizontal = Control.SIZE_SHRINK_END
	hb.add_child(n)
	return hb

# ---------------------------------------------------------------------
# THE INSPECTOR
# ---------------------------------------------------------------------

func render_insp() -> void:
	var p := insp
	_clear(p)
	var kind := ed.sel_kind
	var ids := ed.sel_ids
	var d := ed.doc
	# DOORS MODE: the door the tool puts in, always on top
	if ed.mode == "doors":
		_put(p, _door_preset_items())
	if kind == "" or ids.is_empty():
		if ed.mode == "doors":
			return
		var types := []
		for k in EdDoc.THING_TYPES:
			types.append([k, EdDoc.THING_TYPES[k].name])
		_put(p, [EdStyle.h3("Nothing selected"),
			EdStyle.note("Click something in the map or the 3D view. Shift adds to the selection; drag on empty space to box-select. Drag on the ground to pull up a block as high as the toolbar's Pull."),
			EdStyle.note("%d blocks · %d lines · %d vertices · %d things" % [d.blocks.size(), ed.lines().size(), d.vertices.size(), d.things.size()]),
			EdStyle.h4("New things"),
			EdStyle.row("Thing type", [EdStyle.option(types, ed.thing_type, func(v): ed.thing_type = v)]),
			EdStyle.h4("The ground"),
			EdStyle.note("The plane everything stands on, forever in every direction: its texture and the light of the open air are in the Map tab, or click the ground in 3D.")])
		return
	var n := ids.size()
	var small := ("%d selected" % n) if n > 1 else ""
	match kind:
		"block": _insp_block(p, d, ids, small)
		"ground": _insp_ground(p, d)
		"line": _insp_line(p, d, ids, small, n)
		"vertex":
			var i: int = ids.keys()[0]
			if i < 0 or i >= d.vertices.size():
				return
			var v: Vector2 = d.vertices[i]
			_put(p, [EdStyle.h3("Vertex %d" % i, small),
				EdStyle.row("X", [EdStyle.num(v.x, func(x): each("vertex x", func(w): w.v = Vector2(x, w.v.y)))]) if n == 1 else null,
				EdStyle.row("Y", [EdStyle.num(v.y, func(y): each("vertex y", func(w): w.v = Vector2(w.v.x, y)))]) if n == 1 else null,
				EdStyle.note("Drag a vertex onto another to weld them. Deleting a vertex takes it out of every block it is in.")])
		"thing": _insp_thing(p, d, ids, small, n)
		"scatter":
			for x in d.scatters:
				if ids.has(x.id):
					_insp_scatter(p, x, n)
					break

func _insp_block(p: VBoxContainer, d: Dictionary, ids: Dictionary, small: String) -> void:
	var s = null
	for x in d.blocks:
		if ids.has(x.id):
			s = x
			break
	if s == null:
		return
	var r := EdDoc.ring_of(d, s)
	var set_bright := func(v): each("brightness", func(x): x["light"] = snappedf(clampf(v, 0, 255) / 255.0, 0.0001))
	var area := absf(EdDoc.signed_area(r)) / 4096.0
	var bt := ed.top_of(s.id)
	var auto: bool = EdDoc.base_of(s) == null
	var h := EdDoc.h_of(s)
	var floats: bool = not auto
	_put(p, [EdStyle.h3("Block %d%s" % [s.id, (" · " + str(s.name)) if str(s.get("name", "")) != "" else ""], small),
		EdStyle.note("%d corners · %d cells² · stands %s to %s%s" % [s.verts.size(), roundi(area), EdUI.coord(bt.base), EdUI.coord(bt.top), (" · picked: " + ed.surf.part) if ed.surf != null else ""]),
		EdStyle.row("Name", [EdStyle.text_field(s.get("name", ""), func(v): each("rename block", func(x): x["name"] = v))]),
		EdStyle.h4("Pulled up"),
		EdStyle.row("Height", [EdStyle.num(h, func(v): each("height", func(x): x["h"] = v), 8, "How far it stands up from its base (PgUp/PgDn, the wheel over it in 3D); below zero it is pushed down into what it stands on, a pit")]),
		EdStyle.row("Base", [EdStyle.check(auto, func(v): ed.set_base(s.id, null if v else bt.base), "On what is under it: the block it is drawn inside, the layers below, or the ground"),
			EdStyle.label("on what is under" if auto else "floats at", EdStyle.DIM, 11),
			null if auto else EdStyle.num(bt.base, func(v): ed.set_base(s.id, v), 8, "The height it floats at (Shift+PgUp/PgDn); air under it is a room, its underside the ceiling")]),
		EdStyle.row("Light under it", [bright_row(MewdEditor.bright_of(s), 0, 255, 1, set_bright, 16, "The light of the space under this block — a slab lights the room it roofs. Ctrl+wheel over it")]),
		EdStyle.h4("Textures"),
		tex_field(s.get("top"), "top", "Top"),
		EdStyle.flow([EdStyle.small_button("▢ Select its sides", func(): ed.loop_select(ed.block_index(s.id)),
			"Every side of this block, to put a texture on one of them alone (in Lines mode: double-click or Alt+click a line)")]),
		tex_field(s.get("side"), "side", "Sides"),
		tex_field(s.get("under"), "under", "Underside", true) if floats else null,
		EdStyle.note("Its sides are every face it shows, from its base to its top, round every corner — textures follow the world, nothing to peg. A line's own skin (click a side in 3D) covers one face." + (" The underside is the ceiling of what is under it; empty, it wears the sides." if floats else "")),
		EdStyle.h4("Style"),
		_style_block(s),
		_steps_block(s),
		EdStyle.h4("Spread"),
		EdStyle.flow([EdStyle.small_button("Scatter %s here" % EdScatter.presets().get(ed.scatter_preset, {}).get("name", ""), func(): ed.scatter_blocks(), "Fill the tops of the selected blocks with the mix chosen in the Scatter tab")])])

## THE GROUND: the plane, and the open air's light.
func _insp_ground(p: VBoxContainer, d: Dictionary) -> void:
	var g := EdDoc.ground_of(d)
	_put(p, [EdStyle.h3("The ground"),
		EdStyle.note("The plane everything stands on, forever in every direction, under the sky%s." % ((" · picked: " + ed.surf.part) if ed.surf != null else "")),
		tex_field(g.get("tex"), "tex", "Texture"),
		EdStyle.row("Daylight", [bright_row(int(EdDoc.jsround(EdDoc.num(g.get("light"), 0.9) * 255.0)), 0, 255, 1,
			func(v): each("daylight", func(x): x["light"] = snappedf(clampf(v, 0, 255) / 255.0, 0.0001)), 16, "The light of the open air: every top under the sky, and the ground")]),
		EdStyle.note("Drag on the ground to pull up a block; a block's own light is the light under it.")])

func _steps_block(s: Dictionary) -> Array:
	var o := steps
	var rings: bool = o.kind == "rings"
	var make := func():
		var to = null
		if not (o.to is String) and o.to != null:
			to = float(o.to)
		ed.make_steps(o.kind, {"stepH": o.stepH, "count": o.count, "to": to})
	return [EdStyle.h4("Steps — stairs, cliffs, calderas"),
		EdStyle.row("Make", [seg([["▤ Stairs", not rings, func(): o.kind = "stairs"; render_insp(), "Strips across the block, from its lowest neighbour up to its highest"],
			["◎ Rings", rings, func(): o.kind = "rings"; render_insp(), "Rings inside the block, stepping to a height in the middle: a mound, a mesa, a caldera, a pit"]])]),
		EdStyle.row("Step height", [EdStyle.num(o.stepH, func(v): o.stepH = maxf(1, v), 4, "How high each step rises (the game climbs 24)")]),
		EdStyle.row("How many", [EdStyle.num(o.count if o.count else "", func(v): o.count = maxi(0, roundi(v)), 1, "Blank or 0: as many as the step height makes")]),
		EdStyle.row("Middle at" if rings else "Climb to", [EdStyle.num(o.to, func(v): o.to = v, 8,
			"The height of the middle ring's top: above this one's for a mound, below it for a caldera (blank: 128 up)" if rings else "Blank: the highest block next to it")]),
		EdStyle.flow([_primary("Make rings" if rings else "Make stairs", make),
			EdStyle.small_button("Auto height", func(): o.to = ""; render_insp(), "Back to working it out from the neighbours") if not (o.to is String) else null]),
		EdStyle.note(("Rings from this top (%s) to the middle, each standing in the last. Up for a mound or a cliff in terraces, down for a caldera." % EdUI.coord(ed.top_of(s.id).top)) if rings
			else "Draw a block between two of different heights — the ground and a terrace, a floor and the block beside it — and it is cut into strips, each a step higher, from the low one up to the high one.")]

func _primary(text: String, f: Callable) -> Button:
	var b := EdStyle.small_button(text, f, "One undo step")
	b.add_theme_stylebox_override("normal", EdStyle.box(EdStyle.PANEL2, EdStyle.ACCENT, 4, 1, Vector4(8, 2, 8, 2)))
	b.add_theme_color_override("font_color", EdStyle.ACCENT)
	return b

func _set_side(sid: String, label: String, fn: Callable) -> void:
	each(label, func(x):
		if not x.get("sides") is Dictionary:
			x["sides"] = {}
		if not x.sides.get(sid) is Dictionary:
			x.sides[sid] = {}
		fn.call(x.sides[sid])
		if x.sides[sid].is_empty():
			x.sides.erase(sid)
		if x.sides.is_empty():
			x.erase("sides"))

func _flag(x: Dictionary, k: String, on: bool) -> void:
	if on:
		x[k] = true
	else:
		x.erase(k)

## THE DOOR TOOL (Doors mode, O): the door a click puts in a wall.
func _door_preset_items() -> Array:
	var dp: Dictionary = ed.door_preset
	var styles := [["swing", "Swings open (a hinge)"], ["slide", "Slides into the wall"]]
	return [EdStyle.h3("Doors"),
		EdStyle.note("Click the side of a wall block — in the plan or in 3D — and a doorway is cut through it there, as wide as this, its middle where you clicked, with a door in it. Click another for another. Shift+click a door takes it out."),
		EdStyle.row("Width", [EdStyle.num(dp.w, func(v): dp["w"] = clampf(v, 16, 512), 8, "How wide a new door is")]),
		EdStyle.row("Height", [EdStyle.num(dp.h, func(v): dp["h"] = clampf(v, 24, 1024), 8, "How high the doorway is: the wall over it becomes a lintel block floating at that height")]),
		EdStyle.row("Opens", [EdStyle.option(styles, dp.style, func(v): dp["style"] = v)]),
		EdStyle.row("By itself", [EdStyle.check(dp.auto, func(v): dp["auto"] = v, "as anybody comes to it — else only the use key (F)")]),
		tex_field(dp.tex, "@doorTex", "Door texture")]

## A LINE'S DOOR (its override's `door`), in the line inspector.
func _door_items(o: Dictionary) -> Array:
	var dr = o.get("door")
	if not dr is Dictionary:
		return [EdStyle.flow([EdStyle.small_button("+ Door here", func(): each("door", func(x):
			var dp: Dictionary = ed.door_preset.duplicate()
			dp.erase("w")
			x["door"] = dp), "A door across this whole line, as the Doors tool (O) makes them")])]
	var styles := [["swing", "Swings open (a hinge)"], ["slide", "Slides into the wall"]]
	var set_d := func(k: String, v) -> void:
		each("door " + k, func(x):
			if x.get("door") is Dictionary:
				x.door[k] = v)
	return [EdStyle.h4("Door"),
		EdStyle.row("Height", [EdStyle.num(dr.get("h", 96), func(v): set_d.call("h", clampf(v, 24, 1024)), 8)]),
		EdStyle.row("Opens", [EdStyle.option(styles, dr.get("style", "swing"), func(v): set_d.call("style", v))]),
		EdStyle.row("By itself", [EdStyle.check(dr.get("auto", true), func(v): set_d.call("auto", v), "as anybody comes to it")]),
		EdStyle.row("Locked", [EdStyle.check(dr.get("locked", false), func(v): set_d.call("locked", v), "shut, for good")]),
		tex_field(dr.get("tex", "DOOR0001"), "door.tex", "Door texture"),
		EdStyle.flow([EdStyle.small_button("✕ No door", func(): each("no door", func(x): x.erase("door")), "Still a way through, with no door in it")])]

## A LOOP (MewdEditor.loop_select): the walls of one sector, textured on
## its side all at once.
func _insp_loop(p: VBoxContainer, d: Dictionary, ids: Dictionary) -> void:
	var si := ed.block_index(ed.sel_face)
	var sec: Dictionary = d.blocks[si] if si >= 0 else {}
	_put(p, [EdStyle.h3("Sides of block %s%s" % [str(ed.sel_face), (" · " + str(sec.name)) if str(sec.get("name", "")) != "" else ""], "%d lines" % ids.size()),
		EdStyle.note("Every side of the block. A texture clicked in the browser goes on all of them (the block's Sides; a skin set on one line alone is cleared)."),
		EdStyle.h4("All its sides"),
		tex_field(ed.loop_tex_of("skin"), "@loop.skin", "Sides", true),
		tex_field(ed.loop_tex_of("mid"), "@loop.mid", "Fill across the edges", true),
		EdStyle.note("A fill stands across an edge between two blocks' tops — a fence, a window, a grate. Cleared, nothing stands there. Click one line to pick it alone; Shift+Alt+click another block's line to add its sides.")])

func _insp_line(p: VBoxContainer, d: Dictionary, ids: Dictionary, small: String, n: int) -> void:
	if ed.sel_face != null and ed.block_index(ed.sel_face) >= 0:
		_insp_loop(p, d, ids)
		return
	var key: String = ids.keys()[0]
	var o: Dictionary = d.lines.get(key, {})
	var info = ed.line_info(key)
	var ab := EdDoc.key_verts(key)
	var len := 0.0
	if ab.x >= 0 and ab.x < d.vertices.size() and ab.y < d.vertices.size():
		len = d.vertices[ab.x].distance_to(d.vertices[ab.y])
	var two: bool = info != null and info.blocks.size() > 1
	var names := []
	if info != null:
		for bi in info.blocks:
			names.append("block %d" % d.blocks[bi].id)
	var items := [EdStyle.h3("Line %s" % key, small),
		EdStyle.note("%d units · %s" % [roundi(len), ("between %s" % " and ".join(names)) if two else (("the edge of %s, against the ground" % names[0]) if not names.is_empty() else "on no block")]),
		EdStyle.row("Blocks walking", [EdStyle.check(o.get("blocking", false), func(v): each("line blocking", func(x): _flag(x, "blocking", v)))]),
		EdStyle.row("Blocks sight", [EdStyle.check(o.get("blockSight", false), func(v): each("line sight", func(x): _flag(x, "blockSight", v)))])]
	if n == 1 and info != null:
		items += _door_items(o)
	items += [EdStyle.h4("Textures"),
		tex_field(o.get("tex"), "tex", "Skin", true),
		EdStyle.note("The skin covers every face along this line, both ways — the side of whichever block stands here — instead of the block's Sides. Empty: the block's Sides."),
		tex_field(o.get("midTex"), "midTex", "Fill across it", true)]
	if EdDoc.tex(o, "midTex") != "":
		items.append(EdStyle.row("Fill height", [EdStyle.num(o.get("midHeight", ""), func(v): each("fill height", func(x):
			if v > 0:
				x["midHeight"] = v
			else:
				x.erase("midHeight")), 8)]))
	items.append(EdStyle.row("Offset x / y", [
		EdStyle.num(EdDoc.num(o.get("xoff"), 0), func(v): each("x offset", func(x): x["xoff"] = v)),
		EdStyle.num(EdDoc.num(o.get("yoff"), 0), func(v): each("y offset", func(x): x["yoff"] = v))]))
	var set_scale := func(k: String, v: float):
		each(k.substr(0, 1) + " scale", func(x):
			if v > 0 and v != 1:
				x[k] = v
			else:
				x.erase(k))
	var srow := EdStyle.row("Scale x / y", [EdStyle.num(EdDoc.num(o.get("xscale"), 1), func(v): set_scale.call("xscale", v), 0.25),
		EdStyle.num(EdDoc.num(o.get("yscale"), 1), func(v): set_scale.call("yscale", v), 0.25)])
	srow.tooltip_text = "How big one repeat of the texture is: 2 is twice the size, half as often"
	items.append(srow)
	items += [EdStyle.note("Textures follow the world: their rows are nailed to height 0 and run round the block, so a step, the slab over it and the storey above carry one picture. In 3D, the arrow keys over a side nudge its offsets (Shift: 8 at a time). Deleting a line joins the two blocks on it into one.")]
	_put(p, items)

func _insp_thing(p: VBoxContainer, d: Dictionary, ids: Dictionary, small: String, n: int) -> void:
	var t = null
	for x in d.things:
		if ids.has(x.id):
			t = x
			break
	if t == null:
		return
	var types := []
	for k in EdDoc.THING_TYPES:
		types.append([k, EdDoc.THING_TYPES[k].name])
	var items := [EdStyle.h3(EdDoc.THING_TYPES.get(t.type, {}).get("name", t.type), small),
		EdStyle.row("Type", [EdStyle.option(types, t.type, func(v): each("thing type", func(x): x["type"] = v))]),
		EdStyle.row("X", [EdStyle.num(t.x, func(v): each("thing x", func(x): x["x"] = v))]) if n == 1 else null,
		EdStyle.row("Y", [EdStyle.num(t.y, func(v): each("thing y", func(x): x["y"] = v))]) if n == 1 else null,
		EdStyle.row("Facing °", [EdStyle.num(roundi(rad_to_deg(EdDoc.num(t.get("angle"), 0))), func(v): each("thing angle", func(x): x["angle"] = deg_to_rad(v)), 45)]),
		EdStyle.row("", [facing_buttons(func(a2): each("face", func(x): x["angle"] = a2))])]
	if t.type == "PLANT":
		var kinds := []
		for k in EdScatter.plant_kinds():
			kinds.append([k, k])
		items += [EdStyle.row("Plant", [EdStyle.option(kinds, t.get("kind"), func(v): each("plant kind", func(x): x["kind"] = v))]),
			EdStyle.row("Scale", [EdStyle.num(EdDoc.num(t.get("scale"), 1), func(v): each("plant scale", func(x): x["scale"] = clampf(v, 0.2, 4)), 0.1)])]
	else:
		items.append(EdStyle.row("Variant", [EdStyle.num(t.get("variant", ""), func(v): each("thing variant", func(x): x["variant"] = maxi(0, roundi(v))))]))
	items.append(EdStyle.note("In Things mode, double-click empty floor (or press Insert) to place the type chosen in the Things tab; , and . turn the selection."))
	_put(p, items)

## A SCATTER: the rule, every dial of it, and what it grew.
func _insp_scatter(p: VBoxContainer, c: Dictionary, n: int) -> void:
	var g = ed.compiled.get("grown", {}).get(c.id)
	var a: Dictionary = c.area
	var total := 0.0
	for it in c.items:
		total += EdDoc.num(it.get("w"), 0)
	if total == 0:
		total = 1
	var set_items := func(label: String, fn: Callable): each(label, func(x): fn.call(x.items))
	var items := [EdStyle.h3("Scatter · %s" % str(c.get("name", c.id)), ("%d selected" % n) if n > 1 else ""),
		EdStyle.note(("grew %d of %d%s" % [g.grown, g.wanted, " — no room for the rest" if g.grown < g.wanted * 0.9 else ""]) if g != null else "growing…"),
		EdStyle.note("a rule, re-grown every time it changes"),
		EdStyle.row("Name", [EdStyle.text_field(c.get("name", ""), func(v): each("rename scatter", func(x): x["name"] = v))]),
		EdStyle.h4("Where")]
	if a.kind == "circle":
		items.append(EdStyle.row("Centre / radius", [EdStyle.note("%d, %d" % [roundi(a.x), roundi(a.y)]),
			EdStyle.num(a.r, func(v): each("scatter radius", func(x): if x.area.kind == "circle": x.area.r = maxf(16, v)), 32)]))
	elif a.kind == "rect":
		items.append(EdStyle.note("a rectangle, %s × %s" % [EdUI.coord(absf(a.x1 - a.x0)), EdUI.coord(absf(a.y1 - a.y0))]))
	else:
		var k: int = a.get("ids", []).size()
		items.append(EdStyle.note("filling %d sector%s" % [k, "s" if k > 1 else ""]))
	items += [EdStyle.h4("How"),
		EdStyle.row("Density", [bright_row(EdDoc.num(c.get("density"), 0), 0, 120, 0.5, func(v): each("density", func(x): x["density"] = maxf(0, v)), 0.5, "per 1024 × 1024")]),
		EdStyle.row("Spacing", [EdStyle.num(EdDoc.num(c.get("spacing"), 64), func(v): each("spacing", func(x): x["spacing"] = maxf(0, v)), 8)]),
		EdStyle.row("Clumping", [EdStyle.slider(EdDoc.num(c.get("clump"), 0), 0, 1, 0.05, func(v): each("clumping", func(x): x["clump"] = v))]),
		EdStyle.row("Scale min / max", [EdStyle.num(EdDoc.num(c.get("scaleMin"), 1), func(v): each("scale", func(x): x["scaleMin"] = v), 0.05),
			EdStyle.num(EdDoc.num(c.get("scaleMax"), 1), func(v): each("scale", func(x): x["scaleMax"] = v), 0.05)]),
		EdStyle.note("density is things per 1024 × 1024 of floor · at most %d per scatter" % EdScatter.SCATTER_MAX),
		EdStyle.h4("What")]
	var types := []
	for t in EdScatter.scatter_types():
		types.append([t, EdScatter.type_name(t)])
	for k in c.items.size():
		var it: Dictionary = c.items[k]
		var kk: int = k
		var hb := HBoxContainer.new()
		var lab := HBoxContainer.new()
		lab.custom_minimum_size.x = 44
		lab.add_child(EdStyle.dot(EdScatter.type_colour(str(it.type))))
		lab.add_child(EdStyle.label("%d%%" % roundi(EdDoc.num(it.get("w"), 0) / total * 100), EdStyle.DIM, 11))
		hb.add_child(lab)
		var sel := EdStyle.option(types, it.type, func(v): set_items.call("scatter item", func(list): if kk < list.size(): list[kk]["type"] = v))
		sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(sel)
		var w := EdStyle.num(EdDoc.num(it.get("w"), 0), func(v): set_items.call("weight", func(list): if kk < list.size(): list[kk]["w"] = maxf(0, v)), 1, "weight")
		w.custom_minimum_size.x = 56
		hb.add_child(w)
		hb.add_child(EdStyle.small_button("×", func(): set_items.call("remove item", func(list): list.remove_at(kk)), "remove"))
		items.append(hb)
	items += [EdStyle.flow([EdStyle.small_button("+ Item", func(): set_items.call("add item", func(list): list.append({"type": "SHOPPER", "w": 1})))]),
		EdStyle.h4("Seed"),
		EdStyle.flow([EdStyle.small_button("Reseed", ed.reseed, "Roll it again: the same rule, a different spread"),
			EdStyle.small_button("Bake into things", ed.bake, "Turn what it grew into ordinary things, and drop the rule"),
			EdStyle.small_button("Frame", func(): ed.frame_sel_req.emit())])]
	_put(p, items)

# ---------------------------------------------------------------------
# THE TEXTURE BROWSER
# ---------------------------------------------------------------------

## THE RUNS THAT ANIMATE (ANIMS in js/texpack.js), first frame to last.
static var _runs := {}

static func _run_table() -> Dictionary:
	if not _runs.is_empty():
		return _runs
	var add := func(stem: String, frames: Array) -> void:
		for i in frames.size():
			_runs[frames[i]] = {"stem": stem, "run": frames, "i": i}
	var letters := func(stem: String, s: String) -> Array:
		var out := []
		for c in s:
			out.append(stem + c)
		return out
	var run := func(stem: String, n: int, from: int, pad: int) -> Array:
		var out := []
		for i in n:
			out.append(stem + str(i + from).pad_zeros(pad))
		return out
	add.call("DEVPAN1", letters.call("DEVPAN1", "ABCDEFGHIJKL"))
	add.call("DEVPAN2", letters.call("DEVPAN2", "ABCDEFGH"))
	add.call("DR1", run.call("DR1_", 12, 1, 2))
	add.call("EYEDOOR", run.call("EYEDOOR", 9, 0, 1))
	add.call("EYEDORC", run.call("EYEDORC", 5, 0, 1))
	add.call("REACTB", run.call("REACTB", 5, 0, 2))
	add.call("WFALLA", run.call("WFALLA", 4, 1, 1))
	add.call("WAT2", run.call("WAT2", 24, 1, 2))
	add.call("TESTPA", run.call("TESTPA", 75, 0, 2))
	return _runs

## The run a texture is in ({stem, run, i}), or null.
static func anim_of(name: String):
	return _run_table().get(name)

func shape_of(name: String) -> String:
	if anim_of(name) != null:
		return "Animated"
	var sz := ed.tex_size(name)
	return "Non-square" if sz.x != sz.y else "Square"

func _cell(name: String, mine: bool) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(78, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var sz := ed.tex_size(name)
	p.tooltip_text = ("%s — double-click to edit" % name) if mine else ("%s (%dx%d) — double-click to make a texture from it" % [name, sz.x, sz.y])
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var sw := swatch(name, 64)
	sw.custom_minimum_size = Vector2(64, 64)
	vb.add_child(sw)
	var an = anim_of(name)
	var l := EdStyle.label("%s ▶%d" % [name, an.run.size()] if an != null and an.i == 0 else name, EdStyle.DIM, 9, EdStyle.mono())
	l.clip_text = true
	vb.add_child(l)
	if an != null:
		p.tooltip_text = "%s, animated: %d frames — double-click to make a texture from it" % [name, an.run.size()]
	# A CLICK puts it on what is selected, when the button comes up — a
	# press that turns into a DRAG carries it to a surface in either view
	# instead (the drop is the views', EdView2D/3D._drop_tex)
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed and e.double_click:
				p.set_meta("down", false)
				if mine:
					ui.open_texture_editor(name)
				else:
					ui.open_texture_editor(null, name)
			elif e.pressed:
				p.set_meta("down", true)
			elif p.get_meta("down", false):
				p.set_meta("down", false)
				pick_texture(name))
	p.set_drag_forwarding(func(_at):
		p.set_meta("down", false)
		var pv := swatch(name, 48)
		pv.modulate = Color(1, 1, 1, 0.85)
		p.set_drag_preview(pv)
		ed.say("drop %s on a wall, a floor or a ceiling — in the plan, Shift for the ceiling" % name)
		return {"mewd_tex": name}, Callable(), Callable())
	p.set_meta("mine", mine)
	p.set_meta("anim", an != null)
	return p

func _cell_style(p: PanelContainer, on: bool) -> void:
	var mine: bool = p.get_meta("mine", false)
	var border := EdStyle.ACCENT2 if on else (Color("#5a3f7a") if mine else (Color("#3a4450") if p.get_meta("anim", false) else EdStyle.LINE))
	p.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.FIELD, border, 4, 1, Vector4(3, 3, 3, 3)))

func _build_tex() -> void:
	_clear(_tex_box)
	_tex_cells.clear()
	_groups.clear()
	_tex_head = VBoxContainer.new()
	_tex_box.add_child(_tex_head)
	var filt := LineEdit.new()
	filt.placeholder_text = "filter textures…"
	filt.text = tex_filter
	filt.custom_minimum_size.y = 26
	filt.text_changed.connect(func(t): tex_filter = t.to_upper(); render_tex())
	_tex_box.add_child(filt)
	_mine_head = HBoxContainer.new()
	_tex_box.add_child(_mine_head)
	_mine_grid = GridContainer.new()
	_mine_grid.columns = 3
	_tex_box.add_child(_mine_grid)
	for n in ed.map_texture_names:
		var c := _cell(n, true)
		_tex_cells[n] = c
		_mine_grid.add_child(c)
	if ed.map_texture_names.is_empty():
		var nn := EdStyle.note("None yet. + New starts one; double-click any game texture to start from it.")
		_tex_box.add_child(nn)
		_tex_box.move_child(nn, _mine_grid.get_index())
	_pack_box = VBoxContainer.new()
	_tex_box.add_child(_pack_box)
	for shape in ["Animated", "Square", "Non-square"]:
		var names := []
		for nm in ed.game_texture_names:
			if shape_of(nm) == shape:
				names.append(nm)
		if names.is_empty():
			continue
		var shown := 0
		for nm in names:
			if anim_of(nm) == null or _first_frame(nm):
				shown += 1
		var head := EdStyle.label("%s (%d)" % [shape.to_upper(), shown], EdStyle.DIM, 10, EdStyle.mono())
		head.custom_minimum_size.y = 24
		head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var grid := GridContainer.new()
		grid.columns = 3
		for nm in names:
			var c := _cell(nm, false)
			_tex_cells[nm] = c
			grid.add_child(c)
		_pack_box.add_child(head)
		_pack_box.add_child(grid)
		_groups.append({"head": head, "grid": grid, "names": names})
	_tex_built = true

func _first_frame(name: String) -> bool:
	var a = anim_of(name)
	return a == null or a.i == 0

func pick_texture(name: String) -> void:
	if picking != null:
		var field: String = picking.field
		if field == "@doorTex":
			ed.door_preset["tex"] = name
		elif field.begins_with("@loop."):
			ed.loop_texture(field.substr(6), name)
		elif field.begins_with("@style."):
			var parts := field.split(".")
			ed.update_style(int(parts[1]), parts[2], name)
			render_map()
		elif ed.sel_kind != "":
			each("%s %s" % [field.split(".")[-1], name], func(x):
				set_path(x, field, name)
				if ed.sel_kind == "block" and field in MewdEditor.STYLE_KEYS:
					x.erase("style"))
		picking = null
		render_insp()
		render_tex()
		ed.say(name)
		return
	ed.apply_texture(name)
	current = name
	render_tex()

func render_tex() -> void:
	if not _tex_built:
		_build_tex()
	_clear(_tex_head)
	if picking != null:
		var hb := HFlowContainer.new()
		hb.add_child(EdStyle.note("Picking the %s texture." % str(picking.label).to_lower()))
		if picking.allow_none:
			hb.add_child(EdStyle.small_button("Use none", func():
				var f: String = picking.field
				picking = null
				if f.begins_with("@loop."):
					ed.loop_texture(f.substr(6), null)
				elif ed.sel_kind != "":
					each("clear %s" % f.split(".")[-1], func(x): del_path(x, f))
				render_insp()
				render_tex()))
		hb.add_child(EdStyle.small_button("Cancel", func(): picking = null; render_insp(); render_tex()))
		_tex_head.add_child(hb)
	else:
		_tex_head.add_child(EdStyle.note(("Click a texture to paint the picked %s." % ed.surf.part) if ed.surf != null
			else "Pick a surface in the 3D view, then click a texture to paint it — or open this from an inspector field."))
	_clear(_mine_head)
	var mh := EdStyle.label("THIS MAP'S TEXTURES (%d)" % ed.map_texture_names.size(), EdStyle.DIM, 10, EdStyle.mono())
	mh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mine_head.add_child(mh)
	_mine_head.add_child(EdStyle.small_button("+ New", func(): ui.open_texture_editor(null, current if current != null and ed.texture_names.has(current) else "GRIDWALL"), "A new texture, from layers of others and your own images"))
	if current != null and ed.map_texture_names.has(current):
		var cur: String = current
		_mine_head.add_child(EdStyle.small_button("Edit", func(): ui.open_texture_editor(cur)))
		_mine_head.add_child(EdStyle.small_button("Delete", func():
			ed.edit("delete texture %s" % cur, func(d): d.textures = d.textures.filter(func(t): return t.name != cur), false)
			current = null))
	for nm in _tex_cells:
		var c: PanelContainer = _tex_cells[nm]
		var shown: bool = nm.contains(tex_filter) if tex_filter != "" else (_first_frame(nm) or nm == current)
		c.visible = shown
		_cell_style(c, nm == current)
	for g in _groups:
		var any := false
		for nm in g.names:
			if _tex_cells[nm].visible:
				any = true
				break
		g.head.visible = any
		g.grid.visible = any

# ---------------------------------------------------------------------
# THE THINGS EDITOR
# ---------------------------------------------------------------------

func render_things() -> void:
	var p: VBoxContainer = panes.things.box
	_clear(p)
	var d := ed.doc
	var count := {}
	for t in d.things:
		count[t.type] = count.get(t.type, 0) + 1
	var sel_things := []
	if ed.sel_kind == "thing":
		for t in d.things:
			if ed.sel_ids.has(t.id):
				sel_things.append(t)
	var each_sel := func(label: String, fn: Callable):
		var dd := ed.edit_begin(label)
		for t in dd.things:
			if ed.sel_ids.has(t.id):
				fn.call(t)
		ed.edit_end(false)
	p.add_child(_h4plain("Place"))
	p.add_child(EdStyle.note("Pick a type, then in Things mode (T) double-click the floor or press Insert — on the plan or in 3D."))
	var g := GridContainer.new()
	g.columns = 2
	for k in EdDoc.THING_TYPES:
		if k == "PLANT":
			continue
		var kk: String = k
		var b := _swatch_button(EdDoc.col(EdDoc.THING_TYPES[k].color), EdDoc.THING_TYPES[k].name, kk == ed.thing_type,
			func(): ed.thing_type = kk; ed.set_mode("things"); render_things())
		g.add_child(b)
	p.add_child(g)
	p.add_child(_h4plain("Plants — sprite decorations"))
	for set in EdScatter.plant_sets():
		p.add_child(EdStyle.note(set.name))
		var pg := GridContainer.new()
		pg.columns = 3
		for k in set.kinds:
			var kk: String = k
			pg.add_child(_plant_button(kk))
		p.add_child(pg)
	if not sel_things.is_empty():
		var types := [["", "…"]]
		for k in EdDoc.THING_TYPES:
			types.append([k, EdDoc.THING_TYPES[k].name])
		_put(p, [_h4plain("The selection (%d)" % sel_things.size()),
			EdStyle.row("Face", [facing_buttons(func(a2): each_sel.call("face", func(t): t["angle"] = a2))]),
			EdStyle.row("Change to", [EdStyle.option(types, "", func(v):
				if v != "":
					each_sel.call("change type", func(t):
						t["type"] = v
						if v == "PLANT" and t.get("kind") == null:
							t["kind"] = ed.plant_kind))]),
			EdStyle.flow([EdStyle.small_button("Random facing", func(): each_sel.call("random facing", func(t): t["angle"] = snappedf(randf() * TAU, 0.001))),
				EdStyle.small_button("Random variant", func(): each_sel.call("random variant", func(t): t["variant"] = randi() % 64)),
				EdStyle.small_button("Snap to grid", func(): each_sel.call("snap to grid", func(t): t["x"] = ed.snap_v(t.x); t["y"] = ed.snap_v(t.y))),
				EdStyle.small_button("Select all of this type", func():
					var types2 := {}
					for t in sel_things:
						types2[t.type] = true
					var ids := []
					for t in ed.doc.things:
						if types2.has(t.type):
							ids.append(t.id)
					ed.select("thing", ids)),
				EdStyle.small_button("Delete", ed.delete_sel)])])
	p.add_child(_h4plain("In this map (%d)" % d.things.size()))
	var chips := EdStyle.flow([])
	chips.add_child(_chip("all %d" % d.things.size(), null, thing_filter == null, func(): thing_filter = null; render_things()))
	var order: Array = count.keys()
	order.sort_custom(func(a, b): return count[a] > count[b])
	for k in order:
		var kk: String = k
		chips.add_child(_chip("%s %d" % [EdDoc.THING_TYPES.get(k, {}).get("name", k), count[k]], EdDoc.col(EdDoc.THING_TYPES.get(k, {}).get("color", "#f0f")),
			thing_filter == k, func(): thing_filter = kk; render_things()))
	p.add_child(chips)
	var find := LineEdit.new()
	find.placeholder_text = "find…"
	find.text = thing_search
	p.add_child(find)
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 2)
	p.add_child(table)
	var fill := func():
		_clear(table)
		var shown := []
		for t in d.things:
			if thing_filter != null and t.type != thing_filter:
				continue
			if thing_search != "" and not ("%s %s %d" % [t.type, t.get("kind", ""), t.id]).to_upper().contains(thing_search):
				continue
			shown.append(t)
		for i in mini(300, shown.size()):
			var t: Dictionary = shown[i]
			var nm: String = str(t.get("kind", "plant")).replace("_", " ") if t.type == "PLANT" else EdDoc.THING_TYPES.get(t.type, {}).get("name", t.type)
			var colr: Color = EdScatter.plant_colour(t.get("kind")) if t.type == "PLANT" else EdDoc.col(EdDoc.THING_TYPES.get(t.type, {}).get("color", "#f0f"))
			var tid: int = t.id
			table.add_child(_list_row(nm, "%d, %d · %d°" % [roundi(t.x), roundi(t.y), int(fposmod(rad_to_deg(EdDoc.num(t.get("angle"), 0)), 360))],
				ed.is_sel("thing", tid), colr, func(shift: bool):
					ed.set_mode("things")
					ed.select("thing", [tid], shift)
					if not shift:
						ed.frame_sel_req.emit()))
		if shown.size() > 300:
			table.add_child(EdStyle.note("and %d more — filter to find them" % (shown.size() - 300)))
	find.text_changed.connect(func(t): thing_search = t.to_upper(); fill.call())
	fill.call()
	p.add_child(EdStyle.note("Things grown by scatters are not listed: bake a scatter to list them."))

## a heading in a pane that is not an inspector: the browser's own h4
func _h4plain(text: String) -> Label:
	var l := EdStyle.label(text, Color.WHITE, 12, EdStyle.bold())
	l.custom_minimum_size.y = 24
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l

func _swatch_button(c: Color, text: String, on: bool, f: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 10:
		for x in 10:
			if (x - 4.5) * (x - 4.5) + (y - 4.5) * (y - 4.5) <= 20.25:
				img.set_pixel(x, y, c)
	b.icon = ImageTexture.create_from_image(img)
	b.add_theme_stylebox_override("normal", EdStyle.box(EdStyle.FIELD, EdStyle.ACCENT2 if on else EdStyle.LINE, 4, 1, Vector4(8, 2, 8, 2)))
	b.pressed.connect(f)
	return b

func _plant_button(k: String) -> Control:
	var on: bool = ed.thing_type == "PLANT" and ed.plant_kind == k
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.FIELD, EdStyle.ACCENT2 if on else EdStyle.LINE, 4, 1, Vector4(3, 3, 3, 3)))
	p.tooltip_text = k
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var path := "res://assets/forest/%s.png" % k
	var tr := TextureRect.new()
	if not _thumbs.has(path):
		_thumbs[path] = load(path) if ResourceLoader.exists(path) else null
	tr.texture = _thumbs[path]
	tr.custom_minimum_size = Vector2(56, 56)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tr)
	var l := EdStyle.label(k.replace("_", " "), EdStyle.DIM, 9, EdStyle.mono())
	l.clip_text = true
	vb.add_child(l)
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			ed.thing_type = "PLANT"
			ed.plant_kind = k
			ed.set_mode("things")
			render_things())
	return p

func _chip(text: String, c, on: bool, f: Callable) -> Button:
	var b := EdStyle.small_button(text, f)
	b.add_theme_stylebox_override("normal", EdStyle.box(EdStyle.FIELD, EdStyle.ACCENT2 if on else EdStyle.LINE, 11, 1, Vector4(7, 1, 7, 1)))
	if c != null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(c)
		b.icon = ImageTexture.create_from_image(img)
	return b

func _list_row(text: String, small: String, on: bool, c, f: Callable) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.FIELD, EdStyle.SEL if on else EdStyle.LINE, 4, 1, Vector4(8, 3, 8, 3)))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	if c != null:
		hb.add_child(EdStyle.dot(c))
	var l := EdStyle.label(text, EdStyle.TEXT, 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	hb.add_child(l)
	hb.add_child(EdStyle.label(small, EdStyle.DIM, 10, EdStyle.mono()))
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			f.call(e.shift_pressed))
	return p

# ---------------------------------------------------------------------
# THE SCATTER TAB
# ---------------------------------------------------------------------

func render_scatter() -> void:
	var p: VBoxContainer = panes.scatter.box
	_clear(p)
	var d := ed.doc
	p.add_child(EdStyle.h3("Scatter"))
	p.add_child(EdStyle.note("Spread sprite people and decorations procedurally. Pick a mix, then in Scatter mode (X) drag a circle out from its middle — on the plan or in 3D. Or fill selected sectors. Every scatter stays a live rule: change its dials and it re-grows."))
	p.add_child(EdStyle.h4("Mix"))
	var g := GridContainer.new()
	g.columns = 2
	var P := EdScatter.presets()
	for k in P:
		var kk: String = k
		var pr: Dictionary = P[k]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 34)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = pr.name
		b.tooltip_text = pr.name
		var on: bool = k == ed.scatter_preset
		b.add_theme_stylebox_override("normal", EdStyle.box(Color("#1d1526") if on else EdStyle.FIELD, Color("#c878ff") if on else EdStyle.LINE, 4, 1, Vector4(8, 4, 8, 4)))
		var img := Image.create(40, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for i in mini(4, pr.items.size()):
			img.fill_rect(Rect2i(i * 10, 0, 8, 8), EdScatter.type_colour(str(pr.items[i].type)))
		b.icon = ImageTexture.create_from_image(img)
		b.pressed.connect(func(): ed.scatter_preset = kk; ed.set_mode("scatter"); render_scatter(); render_insp())
		g.add_child(b)
	p.add_child(g)
	p.add_child(EdStyle.row("Brush radius", [EdStyle.num(ed.brush_radius, func(v): ed.brush_radius = int(maxf(16, v)), 64, "for a click without a drag")]))
	p.add_child(EdStyle.flow([EdStyle.small_button("Brush (X)", func(): ed.set_mode("scatter")), EdStyle.small_button("Fill selected sectors", func(): ed.scatter_blocks())]))
	p.add_child(EdStyle.h4("In this map (%d)" % d.scatters.size()))
	if d.scatters.is_empty():
		p.add_child(EdStyle.note("None yet."))
	for c in d.scatters:
		var gr = ed.compiled.get("grown", {}).get(c.id)
		var cid: int = c.id
		p.add_child(_list_row(str(c.get("name", "scatter %d" % cid)), str(gr.grown) if gr != null else "", ed.is_sel("scatter", cid), null, func(_s):
			ed.set_mode("scatter")
			ed.select("scatter", [cid])
			ed.frame_sel_req.emit()))

# ---------------------------------------------------------------------
# THE MAP: its name, the world round it, and what is wrong with it
# ---------------------------------------------------------------------

func set_world(label: String, fn: Callable) -> void:
	var d := ed.edit_begin(label)
	if not d.get("world") is Dictionary:
		d["world"] = {}
	fn.call(d.world)
	ed.edit_end(false)

## THE STYLE BLOCK in a block's inspector: which it wears, the rest to
## choose, and a way to make one from this block.
func _style_block(s: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var names := [["", "— none (custom) —"]]
	for st in ed.styles():
		names.append([str(st.name), str(st.name)])
	var worn := str(s.get("style", ""))
	box.add_child(EdStyle.row("Wears", [EdStyle.option(names, worn, func(v):
		if v == "":
			ed.unstyle()
		else:
			ed.apply_style(v)
		render_insp(), "Paint a style onto the selected blocks")]))
	var nm := EdStyle.text_field(worn if worn != "" else "", func(_v): pass)
	nm.placeholder_text = "a name"
	box.add_child(EdStyle.row("Save as", [nm, EdStyle.small_button("＋ Style", func():
		ed.style_from_block(nm.text, s.id)
		render_insp()
		render_map(), "A style from this block's top, sides, underside and light — new, or bringing one of that name up to date")]))
	if ed.styles().is_empty():
		box.add_child(EdStyle.flow([EdStyle.small_button("Starter styles", func():
			ed.add_starter_styles()
			render_insp()
			render_map(), "Five to begin with: pavement, hedge, wall, office slab, sewer")]))
	box.add_child(EdStyle.note("A block wearing a style follows it (Map tab). Set a texture or the light here and the block is off it, custom again."))
	return box

## THE LIST in the Map tab: every style, editable, and what wears it.
func _styles_list() -> Control:
	var box := VBoxContainer.new()
	var st := ed.styles()
	for i in st.size():
		var y: Dictionary = st[i]
		var name := str(y.get("name", ""))
		var used := ed.style_use(name)
		box.add_child(EdStyle.row("Name", [EdStyle.text_field(name, func(v): ed.update_style(i, "name", v); render_map(); render_insp()),
			EdStyle.small_button("✕", func(): ed.delete_style(i); render_map(); render_insp(), "Delete the style; the blocks wearing it keep its look")]))
		box.add_child(tex_field(y.get("top"), "@style.%d.top" % i, "Top"))
		box.add_child(tex_field(y.get("side"), "@style.%d.side" % i, "Sides"))
		box.add_child(tex_field(y.get("under"), "@style.%d.under" % i, "Underside", true))
		box.add_child(EdStyle.row("Light under", [EdStyle.num(roundi(EdDoc.num(y.get("light"), 0.72) * 255.0),
			func(v): ed.update_style(i, "light", snappedf(clampf(v, 0, 255) / 255.0, 0.0001)), 16)]))
		box.add_child(EdStyle.note("worn by %d block%s" % [used, "" if used == 1 else "s"]))
	box.add_child(EdStyle.flow([EdStyle.small_button("＋ New style", func(): ed.add_style(); render_map()),
		EdStyle.small_button("Starter styles", func(): ed.add_starter_styles(); render_map(), "Five to begin with: pavement, hedge, wall, office slab, sewer") if st.is_empty() else null]))
	return box

func render_map() -> void:
	var p: VBoxContainer = panes.map.box
	_clear(p)
	var d := ed.doc
	var w: Dictionary = d.get("world", {})
	var sky: Dictionary = w.get("sky", {}) if w.get("sky") is Dictionary else {}
	var amb: Dictionary = w.get("ambient", {}) if w.get("ambient") is Dictionary else {}
	var fog: Dictionary = w.get("fog", {}) if w.get("fog") is Dictionary else {}
	var colour := func(k: String, label: String) -> Control:
		return EdStyle.row(label, [EdStyle.color_pick(sky.get(k, "#000000"), func(c): set_world("sky %s" % k, func(ww):
			var s2: Dictionary = ww.get("sky", {}).duplicate() if ww.get("sky") is Dictionary else {}
			s2[k] = c
			ww["sky"] = s2))])
	var amb_of := func(ww: Dictionary, dflt: Dictionary) -> Dictionary:
		var a2 := dflt.duplicate()
		if ww.get("ambient") is Dictionary:
			a2.merge(ww.ambient, true)
		return a2
	var fog_of := func(ww: Dictionary, dflt: Dictionary) -> Dictionary:
		var f2 := dflt.duplicate()
		if ww.get("fog") is Dictionary:
			f2.merge(ww.fog, true)
		return f2
	var probs: Array = ed.compiled.get("problems", [])
	var skies := [["", "painted (the colours below)"]]
	var sd := DirAccess.open("res://assets/skies")
	if sd != null:
		var names := []
		for f in sd.get_files():
			# (an exported game lists "x.png.import", the picture itself
			# being imported away)
			var fn := f.trim_suffix(".import").trim_suffix(".remap")
			if fn.ends_with(".png") and not names.has(fn.get_basename()):
				names.append(fn.get_basename())
		names.sort()
		for n in names:
			skies.append([n, n])
	var g := EdDoc.ground_of(d)
	var items := [EdStyle.h3("Map"),
		EdStyle.row("Name", [EdStyle.text_field(d.get("name", ""), func(v): ed.edit("rename map", func(dd): dd["name"] = v, false))]),
		EdStyle.h4("The ground"),
		EdStyle.note("The plane everything stands on, forever in every direction."),
		EdStyle.row("Texture", [EdStyle.option(_tex_options(g.get("tex")), str(g.get("tex", "")), func(v): ed.edit("ground texture", func(dd): dd.ground["tex"] = v, false))]),
		EdStyle.row("Daylight", [bright_row(int(EdDoc.jsround(EdDoc.num(g.get("light"), 0.9) * 255.0)), 0, 255, 1,
			func(v): ed.edit("daylight", func(dd): dd.ground["light"] = snappedf(clampf(v, 0, 255) / 255.0, 0.0001), false), 16, "The light of the open air: every top under the sky")]),
		EdStyle.h4("Block styles"),
		EdStyle.note("A style is a top, sides, an underside and a light with a name. Paint it onto blocks from the block inspector; change it here and every block wearing it changes."),
		_styles_list(),
		EdStyle.h4("World"),
		EdStyle.row("Nothing burns", [EdStyle.check(w.get("noBurn", false), func(v): set_world("noBurn", func(ww): ww["noBurn"] = v))]),
		EdStyle.row("No responders", [EdStyle.check(w.get("noSquads", false), func(v): set_world("noSquads", func(ww): ww["noSquads"] = v))]),
		EdStyle.h4("Light and fog"),
		EdStyle.row("Light colour", [EdStyle.color_pick(w.get("lightColor", "#ffffff"), func(c): set_world("light colour", func(ww):
			if c.to_lower() == "#ffffff":
				ww.erase("lightColor")
			else:
				ww["lightColor"] = c))]),
		EdStyle.row("Ambient light", [EdStyle.color_pick(amb.get("color", "#ffffff"), func(c): set_world("ambient colour", func(ww):
			var a2: Dictionary = amb_of.call(ww, {"amount": 0.15})
			a2["color"] = c
			ww["ambient"] = a2))]),
		EdStyle.row("Ambient strength", [bright_row(roundi(EdDoc.num(amb.get("amount"), 0) * 100), 0, 100, 1, func(v): set_world("ambient strength", func(ww):
			var a2: Dictionary = amb_of.call(ww, {"color": "#ffffff"})
			a2["amount"] = clampf(v, 0, 100) / 100.0
			ww["ambient"] = a2), 5)]),
		EdStyle.row("Ambient in fog", [bright_row(roundi(EdDoc.num(w.get("fogAmbient"), 1) * 100), 0, 100, 1, func(v): set_world("ambient in fog", func(ww): ww["fogAmbient"] = clampf(v, 0, 100) / 100.0), 10, "How much of the ambient light is in every fog")]),
		EdStyle.row("Fog colour", [EdStyle.color_pick(fog.get("color", "#808080"), func(c): set_world("fog colour", func(ww):
			var f2: Dictionary = fog_of.call(ww, {"density": 0})
			f2["color"] = c
			ww["fog"] = f2))]),
		EdStyle.row("Fog density", [bright_row(EdDoc.num(fog.get("density"), 0), 0, 100, 1, func(v): set_world("fog density", func(ww):
			var f2: Dictionary = fog_of.call(ww, {"color": "#808080"})
			f2["density"] = clampf(v, 0, 100)
			ww["fog"] = f2), 5, "The fog of every sector without its own. 0 is none.")]),
		EdStyle.row("Override fog colour", [EdStyle.check(fog.get("override", false), func(v): set_world("fog override", func(ww):
			var f2: Dictionary = fog_of.call(ww, {"color": "#808080", "density": 0})
			f2["override"] = v
			ww["fog"] = f2))]),
		EdStyle.note("The map's fog is on everything. The ambient light lifts every surface and, by \"Ambient in fog\", tints the fog."),
		EdStyle.h4("Sky"),
		EdStyle.row("Skybox", [EdStyle.option(skies, str(w.get("skybox", "")) if w.get("skybox") != null else "", func(v): set_world("skybox", func(ww):
			if v != "":
				ww["skybox"] = v
			else:
				ww.erase("skybox")))]),
		EdStyle.note(("The %s skybox from the texture pack. The air far off fades to its horizon; the colours below are kept for when it is set back to painted." % w.skybox) if w.get("skybox") != null else ""),
		colour.call("horizon", "Horizon"), colour.call("mid", "Middle"), colour.call("zenith", "Overhead"), colour.call("ground", "Below"),
		EdStyle.note("The sky is re-baked in the 3D view as you change it."),
		EdStyle.h4("Problems (%d)" % probs.size())]
	if probs.is_empty():
		items.append(EdStyle.label("None. The map will build.", EdStyle.ACCENT, 12))
	for x in probs:
		var pr: Dictionary = x
		var l := EdStyle.label(pr.msg, EdStyle.DANGER, 12)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 60
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_goto_problem(pr))
		items.append(l)
	items += [EdStyle.h4("Counts"),
		EdStyle.note("%d blocks · %d lines · %d vertices · %d things" % [d.blocks.size(), ed.lines().size(), d.vertices.size(), d.things.size()])]
	_put(p, items)

## Every texture name, for a drop-down.
func _tex_options(cur) -> Array:
	var out := []
	var names: Array = ed.texture_names.duplicate()
	if cur != null and str(cur) != "" and not names.has(str(cur)):
		names.append(str(cur))
	for n in names:
		out.append([n, n])
	return out

func _goto_problem(x: Dictionary) -> void:
	if x.get("layer") != null and int(x.layer) != ed.layer():
		ed.set_layer(int(x.layer))
	if x.get("id") != null and x.kind == "block":
		var re := RegEx.new()
		re.compile("blocks (\\d+) and (\\d+)")
		var m := re.search(x.msg)
		var both := [int(m.get_string(1)), int(m.get_string(2))] if m != null else [x.id]
		ed.set_mode("blocks")
		ed.select("block", both)
		ed.frame_sel_req.emit()
	elif x.get("id") != null and x.kind == "thing":
		ed.set_mode("things")
		ed.select("thing", [x.id])
		ed.frame_sel_req.emit()
	elif x.get("id") != null and x.kind == "scatter":
		ed.set_mode("scatter")
		ed.select("scatter", [x.id])
		ed.frame_sel_req.emit()
