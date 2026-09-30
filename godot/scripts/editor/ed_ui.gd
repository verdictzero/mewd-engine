## MEWD Editor — the bars round the views (js/editor/ui.js, the frame):
## the top bar (menus, modes, the shape, the grid, the layer, the
## layouts, PLAY), the tabs down the left (textures, things, scatter,
## the map), the inspector down the right, the status line and the info
## bar along the bottom, and the file dialogs. What goes IN the panels is
## ed_panels.gd.
class_name EdUI
extends VBoxContainer

var ed: MewdEditor
var panels: EdPanels
var top: HFlowContainer
var views: Control
var wrap2d: Control
var wrap3d: Control
var side: PanelContainer
var insp_side: PanelContainer
var status_bar: HBoxContainer
var st := {}
var mode_btns := {}
var layout_btns := {}
var shape_sel: OptionButton
var sides_in: SpinBox
var grid_sel: OptionButton
var snap_btn: Button
var tabs_btn: Button
var layer_lbl: Label
var plan_sel: OptionButton
var help2d: Label
var help3d: Label
var toast: Label
var _toast_t := 0.0
var _dialog: Window = null
var cross: Control
var pad: HFlowContainer

const HELP2D := {
	"vertices": "click select · drag move · shift add · Del delete\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light · [ ] grid",
	"lines": "click select · drag move · Del joins sectors (or removes a yellow linedef) · D draws new linedefs\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light · [ ] grid",
	"sectors": "drag on the ground: new sector · drag a room: move it · Insert/D: draw any shape\nclick select · dbl-click inspect · wheel zoom · right-drag/MMB pan · [ ] grid",
	"things": "dbl-click / Insert place · drag move · , . turn\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light",
	"props": "drag empty to draw a box · drag to move\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light",
	"draw": "click corners · click the first to close a sector · Backspace undoes a corner\nEnter / right-click / dbl-click: finish as linedefs — they close into a sector, split a room wall to wall, or stand as a wall · Esc cancel",
	"rect": "drag out the shape chosen beside the Shape button (rectangle, ellipse, circle, polygon, star…)\nthe number sets a round shape's sides · Esc cancel",
	"scatter": "drag a circle out from its middle to scatter the chosen mix · click a scatter to select it\nwheel zoom · right-drag/MMB pan",
}

func _init(editor: MewdEditor) -> void:
	ed = editor
	name = "EdUI"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 0)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = EdStyle.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.show_behind_parent = true
	add_child(bg)
	_build_top()
	_build_main()
	_build_status()
	toast = EdStyle.label("", Color("#d6ffe6"), 12)
	toast.add_theme_stylebox_override("normal", EdStyle.box(Color("#1d2a22"), Color("#2f7d4d"), 6, 1, Vector4(14, 8, 14, 8)))
	toast.visible = false
	toast.top_level = true
	add_child(toast)
	panels = EdPanels.new(ed, self)
	panels.build()
	ed.mode_changed.connect(func(_m): refresh_bar())
	ed.grid_changed.connect(refresh_bar)
	ed.layout_changed.connect(func(_l): refresh_bar(); _layout_views())
	ed.layer_changed.connect(func(_k): refresh_bar())
	ed.sel_changed.connect(refresh_bar)
	ed.status_changed.connect(func(m): st.msg.text = m)
	ed.hover_changed.connect(_show_hover)
	ed.doc_changed.connect(func(): _show_hover())
	ed.compiled_ready.connect(_show_problems)
	ed.path_changed.connect(_refresh_pad)
	ed.sel_changed.connect(_refresh_pad)
	resized.connect(_layout_views)
	views.resized.connect(_layout_views)
	refresh_bar()
	_layout_views.call_deferred()
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"):
		show_pad()

func _process(dt: float) -> void:
	if _toast_t > 0:
		_toast_t -= dt
		if _toast_t <= 0:
			toast.visible = false

func dialog_open() -> bool:
	return _dialog != null and is_instance_valid(_dialog) and _dialog.visible

# ---------------------------------------------------------------------
# THE TOP BAR
# ---------------------------------------------------------------------

func _menu(label: String, items: Array) -> MenuButton:
	var m := MenuButton.new()
	m.text = label
	m.flat = false
	m.focus_mode = Control.FOCUS_NONE
	m.add_theme_stylebox_override("normal", EdStyle.box(EdStyle.PANEL2, EdStyle.LINE, 4, 1, Vector4(9, 3, 9, 3)))
	m.add_theme_stylebox_override("hover", EdStyle.box(Color("#212831"), Color("#3c4753"), 4, 1, Vector4(9, 3, 9, 3)))
	m.add_theme_stylebox_override("pressed", EdStyle.box(Color("#212831"), EdStyle.ACCENT, 4, 1, Vector4(9, 3, 9, 3)))
	var pm := m.get_popup()
	pm.add_theme_font_size_override("font_size", 12)
	var fns := []
	for it in items:
		if it is String and it == "-":
			pm.add_separator()
			fns.append(Callable())
			continue
		pm.add_item(it[0] if it[1] == "" else "%s    %s" % [it[0], it[1]])
		fns.append(it[2])
	pm.id_pressed.connect(func(id):
		var i := pm.get_item_index(id)
		if i >= 0 and i < fns.size() and fns[i].is_valid():
			fns[i].call())
	return m

func _build_top() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.PANEL, Color(0, 0, 0, 0), 0, 0, Vector4(8, 4, 8, 4)))
	add_child(bar)
	var line := ColorRect.new()
	line.color = EdStyle.LINE
	line.custom_minimum_size.y = 1
	add_child(line)
	top = HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 6)
	top.add_theme_constant_override("v_separation", 4)
	bar.add_child(top)
	var brand := EdStyle.label("MEWD Editor", EdStyle.ACCENT, 12, EdStyle.bold(true))
	brand.custom_minimum_size.y = 26
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(brand)
	top.add_child(_menu("File", [
		["New map", "", func(): _confirm_dirty("Start a new map? The current one is autosaved and can be undone back to.", func(): ed.file_new(false))],
		["New from THE GRID", "", func(): _confirm_dirty("Start a new map? The current one is autosaved and can be undone back to.", func(): ed.file_new(true))],
		["Open demo: a new MAZE", "", func(): _confirm_dirty("Open the demo level? The current map is autosaved and can be undone back to.", func(): ed.file_demo("maze"))],
		["Open THE SPRAWL", "", func(): _confirm_dirty("Open the demo level? The current map is autosaved and can be undone back to.", func(): ed.file_demo("sprawl"))],
		["Open a new JESSE (PvP maze)", "", func(): _confirm_dirty("Open the demo level? The current map is autosaved and can be undone back to.", func(): ed.file_demo("jesse"))],
		["Open THE GRID", "", func(): _confirm_dirty("Open the demo level? The current map is autosaved and can be undone back to.", func(): ed.file_demo("grid"))],
		["Open THE ANNEXE (two storeys)", "", func(): _confirm_dirty("Open the demo level? The current map is autosaved and can be undone back to.", func(): ed.file_demo("layers"))],
		"-",
		["Open…", "Ctrl+O", open_dialog],
		["Save", "Ctrl+S", ed.file_save],
		["Save as file…", "Ctrl+Shift+S", save_as_dialog],
		"-",
		["Test map", "F5", ed.play],
		["Back to the title", "", func(): ed.autosave(); ed.quit_requested.emit()],
	]))
	top.add_child(_menu("Edit", [
		["Undo", "Ctrl+Z", ed.undo],
		["Redo", "Ctrl+Y", ed.redo],
		"-",
		["Delete selection", "Del", ed.delete_sel],
		["Clear selection", "Esc", ed.clear_sel],
		"-",
		["Copy", "Ctrl+C", ed.copy_sel],
		["Paste at the cursor", "Ctrl+V", func(): ed.paste(false)],
		["Paste in place (onto another layer: a storey up)", "Ctrl+Shift+V", func(): ed.paste(true)],
		["Layer up", "Alt+PgUp", func(): ed.set_layer(ed.layer() + 1)],
		["Layer down", "Alt+PgDn", func(): ed.set_layer(ed.layer() - 1)],
		["Select all", "Ctrl+A", ed.select_all_in_mode],
		"-",
		["Snap selection to grid", "Shift+G", ed.snap_sel_to_grid],
		["Grid finer", "[", func(): ed.grid_step(-1)],
		["Grid coarser", "]", func(): ed.grid_step(1)],
		["Snap on / off", "G", func(): ed.set_snap()],
		"-",
		["Frame the map", "F", func(): ed.frame_req.emit()],
	]))
	var help := []
	for h in ["2D: drag to move, box-select on empty", "2D: middle / right drag pans, wheel zooms",
			"D: click points, click the first to close", "R: drag a rectangle into a sector",
			"X: drag a circle to scatter the chosen mix", "Every mode works in the 3D view too",
			"Q: visual mode — mouselook, WASD, crosshair", "Ctrl+wheel: sector brightness (2D and 3D)",
			"Wheel in 3D: raise/lower floor or ceiling", "Right-click: properties · right-drag: move",
			"Insert: thing / vertex at the cursor", "Ctrl+C / Ctrl+V: copy / paste selection",
			"PgUp/PgDn: floor ±8 (Shift: ceiling)", "[ ] grid size · G snap · Shift+G snap selection",
			"Alt+PgUp / Alt+PgDn: the layer up or down (storeys)", "Corners snap to vertices (□), lines (◇), then grid",
			"Arrows nudge a grid step (1 with snap off), Shift ×4", "Tab swaps the big view and the inset",
			"3D: hold right mouse to look, WASD QE fly", "3D: wheel raises the floor/ceiling under it",
			"3D: click a texture to paint the pick", "3D: Ctrl+C copies a texture, Ctrl+V pastes",
			"3D: B toggles fullbright, H the grid, F goes to start", "F5 plays the map from where you stand in 3D · F2 in the game comes back"]:
		help.append([h, "", Callable()])
	top.add_child(_menu("Help", help))
	top.add_child(EdStyle.hsep())
	for m in MewdEditor.MODES:
		var def: Dictionary = MewdEditor.MODES[m]
		var mm: String = m
		var b := EdStyle.button(def.short, func(): ed.set_mode(mm), def.key, "%s (%s)" % [def.name, def.key])
		mode_btns[m] = b
		top.add_child(b)
	var shapes := []
	for k in EdOps.SHAPES:
		shapes.append([k, EdOps.SHAPES[k].name])
	shape_sel = EdStyle.option(shapes, ed.shape, func(v): ed.set_shape(v), "The shape a drag draws in Shape mode (R)")
	shape_sel.custom_minimum_size.x = 104
	top.add_child(shape_sel)
	var on_sides := func(v):
		var n := int(round(v))
		if n >= EdOps.SIDES_MIN and n <= EdOps.SIDES_MAX:
			ed.set_shape(ed.shape, n)
		else:
			refresh_bar()
	sides_in = EdStyle.num(ed.shape_sides if ed.shape_sides != null else 4, on_sides, 1.0, "Sides of a round shape, or a star's points")
	sides_in.custom_minimum_size.x = 56
	top.add_child(sides_in)
	top.add_child(EdStyle.hsep())
	grid_sel = OptionButton.new()
	grid_sel.focus_mode = Control.FOCUS_NONE
	grid_sel.tooltip_text = "Grid size  [ ]  — Custom… for any size"
	grid_sel.item_selected.connect(_grid_picked)
	top.add_child(grid_sel)
	snap_btn = EdStyle.button("Snap on", func(): ed.set_snap(), "G", "Snap to grid (G)")
	top.add_child(snap_btn)
	top.add_child(EdStyle.hsep())
	var layers := HBoxContainer.new()
	layers.add_theme_constant_override("separation", 2)
	layers.add_child(EdStyle.button("▼", func(): ed.set_layer(ed.layer() - 1), "", "Layer down (Alt+PgDn)"))
	layer_lbl = EdStyle.label("Layer 0", Color("#cfd6e0"), 12, EdStyle.bold(true))
	layer_lbl.custom_minimum_size.x = 64
	layer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer_lbl.tooltip_text = "The layer being edited: 0 is the ground, 1 the storey on it, and so on. Alt+PgUp / Alt+PgDn"
	layer_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	layers.add_child(layer_lbl)
	layers.add_child(EdStyle.button("▲", func(): ed.set_layer(ed.layer() + 1), "", "Layer up (Alt+PgUp)"))
	top.add_child(layers)
	top.add_child(EdStyle.hsep())
	var on_tabs := func():
		ed.tabs_hidden = not ed.tabs_hidden
		ed.save_prefs()
		refresh_bar()
	tabs_btn = EdStyle.button("Tabs", on_tabs, "", "Show or hide the left panel: textures, things, scatter, map")
	top.add_child(tabs_btn)
	layout_btns = {
		"combined": EdStyle.button("Combined", func(): ed.set_layout("combined2d" if ed.layout == "combined" else "combined"), "", "Both at once: 3D with the plan inset (Tab swaps them)"),
		"split": EdStyle.button("Split", func(): ed.set_layout("split"), "", "Side by side"),
		"only2d": EdStyle.button("2D", func(): ed.set_layout("only2d"), "", "2D only (Tab)"),
		"only3d": EdStyle.button("3D", func(): ed.set_layout("only3d"), "", "3D only (Tab)"),
	}
	for k in ["combined", "split", "only2d", "only3d"]:
		top.add_child(layout_btns[k])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(EdStyle.play_button("▶ PLAY", ed.play, "F5"))

func _grid_picked(i: int) -> void:
	var v = grid_sel.get_item_metadata(i)
	if v is String and v == "custom":
		_prompt("Grid size, in map units (1–%d)" % MewdEditor.GRID_MAX, str(ed.grid), func(t: String):
			var n := int(round(float(t))) if t.is_valid_float() else 0
			if n >= 1 and n <= MewdEditor.GRID_MAX:
				ed.set_grid(n)
			else:
				ed.say("a grid is 1 to %d units" % MewdEditor.GRID_MAX)
				refresh_bar())
		refresh_bar()
		return
	ed.set_grid(int(v))

func refresh_bar() -> void:
	if top == null:
		return
	for m in mode_btns:
		EdStyle.set_on(mode_btns[m], ed.mode == m)
	grid_sel.clear()
	var custom := not MewdEditor.GRIDS.has(ed.grid)
	for g in MewdEditor.GRIDS:
		grid_sel.add_item("grid %d" % g)
		grid_sel.set_item_metadata(grid_sel.item_count - 1, g)
		if g == ed.grid:
			grid_sel.select(grid_sel.item_count - 1)
	if custom:
		grid_sel.add_item("grid %d" % ed.grid)
		grid_sel.set_item_metadata(grid_sel.item_count - 1, ed.grid)
		grid_sel.select(grid_sel.item_count - 1)
	grid_sel.add_item("Custom…")
	grid_sel.set_item_metadata(grid_sel.item_count - 1, "custom")
	var vals: Array = shape_sel.get_meta("values")
	shape_sel.select(vals.find(ed.shape))
	sides_in.visible = ed.shape_sides != null
	if ed.shape_sides != null:
		sides_in.set_value_no_signal(float(ed.shape_sides))
	EdStyle.set_on(snap_btn, ed.snap)
	EdStyle.set_text(snap_btn, "Snap on" if ed.snap else "Snap off")
	EdStyle.set_on(tabs_btn, not ed.tabs_hidden)
	if side != null:
		side.visible = not ed.tabs_hidden
	layer_lbl.text = "Layer %d" % ed.layer()
	layer_lbl.add_theme_color_override("font_color", Color("#ffc878") if ed.layer() != 0 else Color("#cfd6e0"))
	for l in layout_btns:
		EdStyle.set_on(layout_btns[l], ed.layout == l or (l == "combined" and ed.layout == "combined2d"))
	st.mode.text = "mode [b]%s[/b]" % MewdEditor.MODES[ed.mode].name
	st.grid.text = "grid [b]%d[/b]%s" % [ed.grid, "" if ed.snap else " (free)"]
	var n := ed.sel_ids.size()
	st.sel.text = ("[b]%d[/b] %s%s%s" % [n, ed.sel_kind, "s" if n > 1 else "", (" · " + ed.surf.part) if ed.surf != null else ""]) if n > 0 else ""
	help2d.text = HELP2D.get(ed.mode, "")
	if plan_sel != null:
		plan_sel.select(["normal", "light", "floor", "ceil"].find(ed.plan_view))

# ---------------------------------------------------------------------
# THE WORKSPACE
# ---------------------------------------------------------------------

func _build_main() -> void:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 0)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main)
	side = PanelContainer.new()
	side.custom_minimum_size.x = 280
	side.add_theme_stylebox_override("panel", _side_box(false))
	main.add_child(side)
	views = Control.new()
	views.name = "Views"
	views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	views.clip_contents = true
	views.mouse_filter = Control.MOUSE_FILTER_PASS
	main.add_child(views)
	var vb := ColorRect.new()
	vb.color = EdStyle.VIEW_BG
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	views.add_child(vb)
	insp_side = PanelContainer.new()
	insp_side.custom_minimum_size.x = 300
	insp_side.add_theme_stylebox_override("panel", _side_box(true))
	main.add_child(insp_side)
	# the views, each in a wrap with its tag, its help and its swap button
	wrap3d = _wrap("VISUAL  3D")
	var v3 := EdView3D.new(ed)
	wrap3d.add_child(v3)
	wrap3d.move_child(v3, 0)
	ed.view3d = v3
	help3d = _help(wrap3d, "Q visual mode · hold RMB look + WASD fly · every mode works here\nwheel height · Ctrl+wheel brightness · Ctrl+C/V texture · B fullbright · H grid")
	cross = _crosshair()
	wrap3d.add_child(cross)
	wrap2d = _wrap("MAP  2D")
	var v2 := EdView2D.new(ed)
	wrap2d.add_child(v2)
	wrap2d.move_child(v2, 0)
	ed.view2d = v2
	help2d = _help(wrap2d, "")
	var on_plan := func(v):
		ed.plan_view = v
		ed.grid_changed.emit()
	plan_sel = EdStyle.option([["normal", "Plan: normal"], ["light", "Plan: brightness"], ["floor", "Plan: floor heights"], ["ceil", "Plan: ceilings"]],
		ed.plan_view, on_plan, "What the plan shades sectors by (Doom Builder's brightness view)")
	plan_sel.position = Vector2(62, 3)
	plan_sel.add_theme_font_size_override("font_size", 10)
	plan_sel.custom_minimum_size = Vector2(112, 18)
	plan_sel.add_theme_constant_override("arrow_margin", 3)
	for st_name in ["normal", "hover", "pressed", "hover_pressed"]:
		plan_sel.add_theme_stylebox_override(st_name, EdStyle.box(Color(0.08, 0.1, 0.12, 0.8), EdStyle.ACCENT if st_name != "normal" else EdStyle.LINE, 4, 1, Vector4(6, 0, 4, 0)))
	var arrow := Image.create(7, 4, false, Image.FORMAT_RGBA8)
	arrow.fill(Color(0, 0, 0, 0))
	for yy in 4:
		for xx in range(yy, 7 - yy):
			arrow.set_pixel(xx, yy, EdStyle.DIM)
	plan_sel.add_theme_icon_override("arrow", ImageTexture.create_from_image(arrow))
	plan_sel.add_theme_color_override("font_color", EdStyle.DIM)
	plan_sel.size = Vector2(112, 18)
	plan_sel.reset_size.call_deferred()
	wrap2d.add_child(plan_sel)
	views.add_child(wrap3d)
	views.add_child(wrap2d)
	pad = HFlowContainer.new()
	pad.alignment = FlowContainer.ALIGNMENT_END
	pad.visible = false
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	views.add_child(pad)
	ed.visual_changed.connect(func(on): cross.visible = on; _layout_views())

func _side_box(left_border: bool) -> StyleBoxFlat:
	var s := EdStyle.box(EdStyle.PANEL, EdStyle.LINE, 0, 0, Vector4(0, 0, 0, 0))
	s.border_color = EdStyle.LINE
	s.border_width_left = 1 if left_border else 0
	s.border_width_right = 0 if left_border else 1
	return s

func _wrap(tag: String) -> Control:
	var w := Control.new()
	w.clip_contents = true
	w.mouse_filter = Control.MOUSE_FILTER_PASS
	var border := Panel.new()
	border.name = "Border"
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	w.add_child(border)
	var t := EdStyle.label(tag, EdStyle.DIM, 10, EdStyle.mono())
	t.name = "Tag"
	t.position = Vector2(8, 6)
	t.add_theme_color_override("font_shadow_color", Color.BLACK)
	w.add_child(t)
	var sw := EdStyle.button("⤢", func(): ed.set_layout("combined2d" if ed.layout == "combined" else "combined"), "", "Swap the big view and the inset (Tab)")
	sw.name = "Swap"
	sw.custom_minimum_size = Vector2(24, 22)
	sw.add_theme_stylebox_override("normal", EdStyle.box(Color(0.08, 0.1, 0.12, 0.8), EdStyle.LINE, 4, 1, Vector4(4, 0, 4, 0)))
	w.add_child(sw)
	return w

func _help(w: Control, text: String) -> Label:
	var l := EdStyle.label(text, Color("#6b7780"), 10, EdStyle.mono())
	l.name = "Help"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_right = -8
	l.offset_bottom = -6
	w.add_child(l)
	return l

func _crosshair() -> Control:
	var c := Control.new()
	c.name = "Cross"
	c.visible = false
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.draw.connect(func():
		c.draw_rect(Rect2(-1, -9, 2, 18), Color(1, 1, 1, 0.8))
		c.draw_rect(Rect2(-9, -1, 18, 2), Color(1, 1, 1, 0.8)))
	return c

## THE LAYOUTS: combined (3D big, the plan inset bottom left), combined2d
## (the other way), split, 2D only, 3D only.
func _layout_views() -> void:
	if views == null:
		return
	var W := views.size.x
	var H := views.size.y
	var l := ed.layout
	var inset := Rect2()
	var big: Control = null
	var small: Control = null
	wrap2d.visible = true
	wrap3d.visible = true
	if ed.view3d != null and ed.view3d.visual:
		l = "only3d"
	match l:
		"combined", "combined2d":
			big = wrap3d if l == "combined" else wrap2d
			small = wrap2d if l == "combined" else wrap3d
			var iw := maxf(240.0, W * 0.34)
			var ih := maxf(170.0, H * 0.42)
			inset = Rect2(10, H - ih - 10, iw, ih)
			big.position = Vector2.ZERO
			big.size = Vector2(W, H)
			small.position = inset.position
			small.size = inset.size
			views.move_child(small, views.get_child_count() - 1)
		"split":
			wrap2d.position = Vector2.ZERO
			wrap2d.size = Vector2(floorf(W / 2), H)
			wrap3d.position = Vector2(floorf(W / 2), 0)
			wrap3d.size = Vector2(W - floorf(W / 2), H)
		"only2d":
			wrap2d.position = Vector2.ZERO
			wrap2d.size = Vector2(W, H)
			wrap3d.visible = false
		_:
			wrap3d.position = Vector2.ZERO
			wrap3d.size = Vector2(W, H)
			wrap2d.visible = false
	for w in [wrap2d, wrap3d]:
		var is_small: bool = w == small
		var b: Panel = w.get_node("Border")
		if is_small:
			b.add_theme_stylebox_override("panel", EdStyle.box(Color(0, 0, 0, 0), Color("#3a4652"), 6, 1))
		elif l == "split" and w == wrap2d:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = EdStyle.LINE
			sb.border_width_right = 1
			b.add_theme_stylebox_override("panel", sb)
		else:
			b.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var sw: Control = w.get_node("Swap")
		sw.visible = is_small
		sw.position = Vector2(w.size.x - 30, 4)
		w.get_node("Help").visible = not is_small
		var tag: Label = w.get_node("Tag")
		if w == wrap3d:
			tag.text = "VISUAL  3D" + ("  ·  VISUAL MODE — Q or Esc to leave" if ed.view3d != null and ed.view3d.visual else "")
		if w.get_child(0) is Control:
			var v: Control = w.get_child(0)
			v.position = Vector2.ZERO
			v.size = w.size
	cross.position = wrap3d.size / 2.0
	cross.queue_redraw()
	pad.position = Vector2(10, 0)
	pad.size = Vector2(W - 20, 44)
	pad.position.y = H - 34 - pad.size.y
	if ed.view3d != null:
		ed.view3d.set_active(wrap3d.visible)

# ---------------------------------------------------------------------
# THE STATUS LINE, and the info bar in it
# ---------------------------------------------------------------------

func _rich(color := EdStyle.DIM) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", EdStyle.mono())
	r.add_theme_font_override("bold_font", EdStyle.bold(true))
	r.add_theme_font_size_override("normal_font_size", 11)
	r.add_theme_font_size_override("bold_font_size", 11)
	r.add_theme_color_override("default_color", color)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r

func _build_status() -> void:
	var line := ColorRect.new()
	line.color = EdStyle.LINE
	line.custom_minimum_size.y = 1
	add_child(line)
	var p := PanelContainer.new()
	p.custom_minimum_size.y = 24
	p.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.PANEL, Color(0, 0, 0, 0), 0, 0, Vector4(10, 0, 10, 0)))
	add_child(p)
	status_bar = HBoxContainer.new()
	status_bar.add_theme_constant_override("separation", 14)
	status_bar.clip_contents = true
	p.add_child(status_bar)
	for k in ["mode", "grid", "pos", "sel", "info", "probs"]:
		st[k] = _rich(EdStyle.TEXT if k == "info" else EdStyle.DIM)
		status_bar.add_child(st[k])
	var msg := EdStyle.label("", EdStyle.ACCENT, 11, EdStyle.mono())
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.clip_text = true
	msg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	msg.custom_minimum_size.x = 50
	st["msg"] = msg
	status_bar.add_child(msg)

static func coord(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(snappedf(v, 0.01))

func set_pos(p) -> void:
	st.pos.text = "" if p == null else "[b]%s[/b], [b]%s[/b]" % [coord(p.x), coord(p.y)]

## THE INFO BAR: what is under the mouse, and what it is.
func _show_hover() -> void:
	var hv = ed.hovered
	var d := ed.doc
	var t := ""
	if hv != null:
		match hv.kind:
			"sector":
				var x = ed.sector_by_id(hv.id)
				if x != null:
					var ins := MewdEditor.is_inside(x)
					t = "[color=#ffffff][b]Sector %d[/b][/color]%s · %s · floor [b]%s[/b] · %s [b]%s[/b] · brightness [b]%d[/b] · %s%s" % [
						x.id, (" " + str(x.name)) if str(x.get("name", "")) != "" else "", "inside" if ins else "outside",
						coord(EdDoc.num(x.get("floor"), 0)), "ceiling" if ins else "walls", coord(EdDoc.num(x.get("ceil"), 0)),
						MewdEditor.bright_of(x), EdDoc.tex(x, "floorTex"), (" / " + EdDoc.tex(x, "ceilTex")) if ins else ""]
			"line":
				var l = ed.line_info(hv.id)
				var ab := EdDoc.key_verts(str(hv.id))
				if l != null and ab.x >= 0 and ab.x < d.vertices.size() and ab.y < d.vertices.size():
					var free: bool = l.get("free", false)
					t = "[color=#ffffff][b]%s %s[/b][/color] · %d long · %s%s" % ["Linedef" if free else "Line", hv.id,
						roundi(d.vertices[ab.x].distance_to(d.vertices[ab.y])),
						"on its own (a wall)" if free else ("two-sided" if l.sectors.size() > 1 else "one-sided"),
						" · doorway" if d.lines.get(hv.id, {}).get("opening", false) else ""]
			"thing":
				for x in d.things:
					if x.id == hv.id:
						var nm: String = str(x.get("kind", "")) if x.type == "PLANT" else EdDoc.THING_TYPES.get(x.type, {}).get("name", x.type)
						t = "[color=#ffffff][b]%s[/b][/color] #%d · %d, %d · %d°" % [nm, x.id, roundi(x.x), roundi(x.y), int(fposmod(rad_to_deg(EdDoc.num(x.get("angle"), 0)), 360.0))]
						break
			"vertex":
				if hv.id >= 0 and hv.id < d.vertices.size():
					var v: Vector2 = d.vertices[hv.id]
					t = "[color=#ffffff][b]Vertex %d[/b][/color] · %s, %s" % [hv.id, coord(v.x), coord(v.y)]
			"prop":
				for x in d.props:
					if x.id == hv.id:
						t = "[color=#ffffff][b]Prop %d[/b][/color] · %s–%s · %s" % [x.id, coord(x.z0), coord(x.z1), x.get("tex", "")]
						break
			"scatter":
				for x in d.scatters:
					if x.id == hv.id:
						var g = ed.compiled.get("grown", {}).get(x.id)
						t = "[color=#ffffff][b]Scatter[/b][/color] %s · %s grown" % [x.get("name", ""), str(g.grown) if g != null else "…"]
						break
	st.info.text = t

func _show_problems() -> void:
	var n: int = ed.compiled.get("problems", []).size()
	st.probs.text = ("[color=#ff5c5c]%d problem%s[/color]" % [n, "s" if n > 1 else ""]) if n > 0 else ""

func show_toast(msg: String) -> void:
	toast.text = msg
	toast.visible = true
	toast.reset_size()
	toast.position = Vector2((get_viewport_rect().size.x - toast.size.x) / 2.0, get_viewport_rect().size.y - 40 - toast.size.y)
	_toast_t = 1.8

# ---------------------------------------------------------------------
# THE PAD: the keys a tablet has not got
# ---------------------------------------------------------------------

func show_pad() -> void:
	pad.visible = true
	_refresh_pad()

func _refresh_pad() -> void:
	if pad == null or not pad.visible:
		return
	for c in pad.get_children():
		c.queue_free()
	var n := ed.path.size()
	var mk := func(t: String, tip: String, f: Callable) -> void:
		var b := EdStyle.button(t, f, "", tip)
		b.custom_minimum_size = Vector2(44, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		pad.add_child(b)
	if n >= 3:
		mk.call("✓ Close", "Close the shape into a sector", func(): ed.close_path())
	if n >= 2:
		mk.call("⏎ Lines", "Finish as linedefs, or a split wall to wall (Enter)", func(): ed.close_path(true))
	if n > 0:
		mk.call("⌫", "Take back the last corner (Backspace)", func(): ed.path.pop_back(); ed.path_changed.emit())
		mk.call("✕", "Give up the drawing (Esc)", func(): ed.cancel_path(); ed.after_draw())
	else:
		mk.call("↶", "Undo (Ctrl+Z)", ed.undo)
		mk.call("↷", "Redo (Ctrl+Y)", ed.redo)
		if not ed.sel_ids.is_empty():
			mk.call("Del", "Delete the selection (Del)", ed.delete_sel)
	mk.call("−", "Zoom out", func(): ed.view2d.zoom_by(1.0 / 1.5))
	mk.call("+", "Zoom in", func(): ed.view2d.zoom_by(1.5))
	mk.call("⤢", "Frame the map (F)", func(): ed.frame_req.emit())

# ---------------------------------------------------------------------
# DIALOGS: files, a question, a number
# ---------------------------------------------------------------------

func _file_dialog(mode: FileDialog.FileMode, title: String, cb: Callable) -> FileDialog:
	var f := FileDialog.new()
	f.file_mode = mode
	f.title = title
	f.use_native_dialog = false
	f.access = FileDialog.ACCESS_FILESYSTEM if not OS.has_feature("web") else FileDialog.ACCESS_USERDATA
	f.filters = PackedStringArray(["*.json, *.gssmap ; MEWD maps"])
	MewdEditor._ensure_dirs()
	f.current_dir = ProjectSettings.globalize_path(MewdEditor.MAPS)
	f.size = Vector2i(760, 480)
	f.file_selected.connect(func(p): cb.call(p))
	f.close_requested.connect(func(): f.queue_free())
	f.canceled.connect(func(): f.queue_free())
	f.file_selected.connect(func(_p): f.queue_free())
	add_child(f)
	_dialog = f
	f.popup_centered()
	return f

func open_dialog() -> void:
	var go := func(): _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Open a map", func(p): ed.open_from(p))
	_confirm_dirty("Open another map? The current one is autosaved and can be undone back to.", go)

func save_as_dialog() -> void:
	var f := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save the map as", func(p):
		if not (p.ends_with(".json") or p.ends_with(".gssmap")):
			p += ".gssmap.json"
		ed.save_to(p))
	f.current_file = ed.file_name_for()

func import_image_dialog(cb: Callable) -> void:
	var f := FileDialog.new()
	f.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	f.title = "An image, as a layer"
	f.use_native_dialog = false
	f.access = FileDialog.ACCESS_FILESYSTEM
	f.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga ; Images"])
	f.size = Vector2i(760, 480)
	f.file_selected.connect(func(p): cb.call(p); f.queue_free())
	f.canceled.connect(func(): f.queue_free())
	add_child(f)
	f.popup_centered()

func _confirm_dirty(q: String, go: Callable) -> void:
	if not ed.history.dirty():
		go.call()
		return
	var c := ConfirmationDialog.new()
	c.dialog_text = q
	c.title = "MEWD Editor"
	c.confirmed.connect(func(): go.call(); c.queue_free())
	c.canceled.connect(func(): c.queue_free())
	add_child(c)
	_dialog = c
	c.popup_centered()

func _prompt(q: String, value: String, cb: Callable) -> void:
	var c := ConfirmationDialog.new()
	c.title = "MEWD Editor"
	var vb := VBoxContainer.new()
	vb.add_child(EdStyle.label(q))
	var e := LineEdit.new()
	e.text = value
	vb.add_child(e)
	c.add_child(vb)
	c.confirmed.connect(func(): cb.call(e.text); c.queue_free())
	c.canceled.connect(func(): c.queue_free())
	e.text_submitted.connect(func(_t): c.hide(); cb.call(e.text); c.queue_free())
	add_child(c)
	_dialog = c
	c.popup_centered(Vector2i(320, 100))
	e.grab_focus()
	e.select_all()

func open_texture_editor(name = null, from := "GRIDWALL") -> void:
	# a dialog over the workspace, the workspace dimmed under it
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.top_level = true
	dim.position = Vector2.ZERO
	dim.size = get_viewport_rect().size
	add_child(dim)
	var t := EdTexEditor.new(ed, self, name, from)
	add_child(t)
	t.tree_exiting.connect(func(): dim.queue_free())
	_dialog = t
	var vs := get_viewport_rect().size
	t.popup_centered(Vector2i(mini(980, int(vs.x * 0.96)), mini(640, int(vs.y * 0.92))))
