## MEWD Editor — the texture editor (js/editor/texeditor.js).
##
## SLADE's texture editor, for the map's own textures (the drawing is
## ed_texcompose.gd). A dialog over the workspace:
##
##   left    the texture, large, point sampled, and tiled three by three
##           if asked, so a seam shows where it will show on a wall
##   right   its name and size, the layers from the top of the stack
##           down, and the selected layer's every setting
##
## Every change redraws the preview. SAVE puts the texture in the map as
## one undoable edit (a renamed one takes what wore the old name with
## it); CANCEL, or Escape, leaves the map as it was.
class_name EdTexEditor
extends Window

var ed: MewdEditor
var ui: EdUI
var def: Dictionary
var original = null
var from := "GRIDWALL"
var sel := 0
var tiled := true
var preview: TextureRect
var side: VBoxContainer
var err: Label
var _started := ""
var _dirty_draw := true

func _init(editor: MewdEditor, frame: EdUI, name = null, src := "GRIDWALL") -> void:
	ed = editor
	ui = frame
	from = src
	title = "Texture editor"
	borderless = true
	exclusive = true
	transient = true
	wrap_controls = false
	size = Vector2i(980, 640)
	var existing = null
	if name != null:
		for t in ed.doc.get("textures", []):
			if t.name == name:
				existing = t
				break
	if existing != null:
		def = existing.duplicate(true)
		original = existing.name
	else:
		def = from_texture(src)
	sel = def.layers.size() - 1
	_started = JSON.stringify(def)

## A new texture from another keeps its shape and its size on a wall.
func from_texture(src: String) -> Dictionary:
	var img := EdTex.source_image(src, {})
	var w := img.get_width() if img != null else 128
	var h := img.get_height() if img != null else 128
	var k := minf(1.0, float(EdTex.TEX_MAX) / maxf(w, h))
	var d := EdTex.new_texture(unique_name(src), src, Vector2i(maxi(1, roundi(w * k)), maxi(1, roundi(h * k))))
	if k < 1:
		d.layers[0].sx = float(d.w) / w
		d.layers[0].sy = float(d.h) / h
	var ws := ed.tex_size(src)
	if ws.x > 0 and ws.y > 0:
		d.worldW = ws.x
		d.worldH = ws.y
	return d

func unique_name(src: String) -> String:
	var base := EdTex.clean_name(src).substr(0, 12)
	if base == "":
		base = "TEX"
	var i := 1
	while true:
		var n := "%s_%d" % [base, i]
		var taken: bool = ed.built_in.has(n)
		for t in ed.doc.get("textures", []):
			if t.name == n:
				taken = true
		if not taken:
			return n
		i += 1
	return base

func _ready() -> void:
	theme = EdStyle.theme()
	close_requested.connect(_ask_close)
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.PANEL, Color("#3a4652"), 0, 1))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var head := HBoxContainer.new()
	head.custom_minimum_size.y = 40
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 14)
	hm.add_child(head)
	root.add_child(hm)
	var ht := EdStyle.label("Texture editor", Color.WHITE, 12, EdStyle.bold())
	ht.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(ht)
	var hn := EdStyle.label("— layers of the game's textures and your own images, drawn into a texture of this map", EdStyle.DIM, 12)
	hn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(hn)
	var line := ColorRect.new()
	line.color = EdStyle.LINE
	line.custom_minimum_size.y = 1
	root.add_child(line)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)
	var view := Panel.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_theme_stylebox_override("panel", EdStyle.box(Color("#0c0f12"), EdStyle.LINE, 0, 1))
	view.clip_contents = true
	body.add_child(view)
	preview = TextureRect.new()
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 20
	preview.offset_top = 20
	preview.offset_right = -20
	preview.offset_bottom = -40
	view.add_child(preview)
	var tile := EdStyle.check(true, func(on): tiled = on; _dirty_draw = true, " tile 3 × 3")
	tile.position = Vector2(10, 0)
	tile.anchor_top = 1.0
	tile.anchor_bottom = 1.0
	tile.offset_top = -30
	view.add_child(tile)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size.x = 340
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 12)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(m)
	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(side)
	var foot := HBoxContainer.new()
	foot.custom_minimum_size.y = 48
	foot.alignment = BoxContainer.ALIGNMENT_END
	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_left", 14)
	fm.add_theme_constant_override("margin_right", 14)
	fm.add_child(foot)
	root.add_child(fm)
	err = EdStyle.label("", EdStyle.DANGER, 12)
	err.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(err)
	var cancel := EdStyle.button("Cancel", _ask_close)
	var ok := EdStyle.play_button("Save texture", save)
	for b in [cancel, ok]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(b)
	render_side()

func _process(_dt: float) -> void:
	if _dirty_draw:
		_dirty_draw = false
		redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_ask_close()
		set_input_as_handled()

func _ask_close() -> void:
	if JSON.stringify(def) == _started:
		_close()
		return
	var c := ConfirmationDialog.new()
	c.dialog_text = "Close the texture editor without saving?"
	c.confirmed.connect(func(): c.queue_free(); _close())
	c.canceled.connect(func(): c.queue_free())
	add_child(c)
	c.popup_centered()

func _close() -> void:
	hide()
	queue_free()

func save() -> void:
	def.name = EdTex.clean_name(def.name)
	var clash := false
	for t in ed.doc.get("textures", []):
		if t.name == def.name and t.name != original:
			clash = true
	var why := EdTex.check(def, ed.built_in)
	if why == "" and clash:
		why = "the map already has a %s" % def.name
	if why != "":
		err.text = "Not saved: %s." % why
		return
	var d := ed.edit_begin("texture %s" % def.name)
	var i := -1
	for k in d.textures.size():
		if d.textures[k].name == original:
			i = k
	if i >= 0:
		d.textures[i] = def.duplicate(true)
	else:
		d.textures.append(def.duplicate(true))
	if original != null and original != def.name:
		rename_uses(d, original, def.name)
	ed.edit_end(false)
	ed.say("saved texture %s" % def.name)
	_close()

## Every surface and layer that wore one name, wearing another.
static func rename_uses(d: Dictionary, a: String, b: String) -> void:
	var swap := func(o: Dictionary) -> void:
		for k in o.keys():
			if (str(k).ends_with("Tex") or k == "tex") and o[k] == a:
				o[k] = b
	for s in d.sectors:
		swap.call(s)
	for p in d.props:
		swap.call(p)
	for o in d.lines.values():
		swap.call(o)
		if o.get("sides") is Dictionary:
			for sd in o.sides.values():
				swap.call(sd)
	for t in d.get("textures", []):
		for L in t.get("layers", []):
			if L.get("tex") == a:
				L["tex"] = b

func redraw() -> void:
	var drawn := {}
	for t in ed.doc.get("textures", []):
		if TexBank.map_own.has(t.name) and t.name != def.name:
			var img: Image = TexBank.map_own[t.name][0].get_image()
			if img != null:
				drawn[t.name] = img
	var c := EdTex.compose(def, drawn)
	var k := 3 if tiled else 1
	var big := Image.create(c.get_width() * k, c.get_height() * k, false, Image.FORMAT_RGBA8)
	for y in k:
		for x in k:
			big.blit_rect(c, Rect2i(0, 0, c.get_width(), c.get_height()), Vector2i(x * c.get_width(), y * c.get_height()))
	if tiled:
		var w := c.get_width()
		var h := c.get_height()
		var line := Color(1, 180 / 255.0, 84 / 255.0, 0.4)
		for i in w:
			big.set_pixel(w + i, h, line)
			big.set_pixel(w + i, 2 * h - 1, line)
		for j in h:
			big.set_pixel(w, h + j, line)
			big.set_pixel(2 * w - 1, h + j, line)
	preview.texture = ImageTexture.create_from_image(big)

func _row(label: String, fields: Array) -> Control:
	return EdStyle.row(label, fields)

func _num(v, setter: Callable, step := 1.0, lo := -9999.0, hi := 9999.0) -> SpinBox:
	return EdStyle.num(v, func(x): setter.call(clampf(x, lo, hi)); _dirty_draw = true, step)

func render_side() -> void:
	for c in side.get_children():
		c.queue_free()
	var names := []
	for n in ed.texture_names:
		if n != def.name:
			names.append([n, n])
	var name_edit := LineEdit.new()
	name_edit.text = def.name
	name_edit.text_changed.connect(func(t): def.name = EdTex.clean_name(t))
	side.add_child(_row("Name", [name_edit]))
	side.add_child(_row("Pixels", [_num(def.w, func(v): def.w = int(v), 8, 1, EdTex.TEX_MAX), _num(def.h, func(v): def.h = int(v), 8, 1, EdTex.TEX_MAX)]))
	side.add_child(_row("World units", [_num(EdDoc.num(def.get("worldW"), def.w), func(v): def.worldW = v, 8, 1, 8192),
		_num(EdDoc.num(def.get("worldH"), def.h), func(v): def.worldH = v, 8, 1, 8192)]))
	side.add_child(EdStyle.h4("Layers — top first"))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	for i in range(def.layers.size() - 1, -1, -1):
		var L: Dictionary = def.layers[i]
		var ii := i
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", EdStyle.box(EdStyle.FIELD, EdStyle.SEL if i == sel else EdStyle.LINE, 4, 1, Vector4(8, 3, 8, 3)))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		var t := EdStyle.label("%s %s" % ["◌" if L.get("hidden", false) else "●", "image" if L.get("image") != null and str(L.image) != "" else str(L.get("tex", ""))], EdStyle.TEXT, 12)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(t)
		var a := EdDoc.num(L.get("alpha"), 1)
		hb.add_child(EdStyle.label("%s%s" % [L.get("blend", "normal"), (" %d%%" % roundi(a * 100)) if a < 1 else ""], EdStyle.DIM, 10, EdStyle.mono()))
		row.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				sel = ii
				render_side())
		list.add_child(row)
	side.add_child(list)
	var add_sel := EdStyle.option([["", "+ layer from a texture…"]] + names, "", func(v):
		if v == "":
			return
		def.layers.append(EdTex.new_layer(v))
		sel = def.layers.size() - 1
		render_side())
	add_sel.custom_minimum_size.x = 170
	side.add_child(EdStyle.flow([add_sel, EdStyle.small_button("+ Image…", _import, "A picture from a file, as a layer")]))
	if sel < 0 or sel >= def.layers.size():
		_dirty_draw = true
		return
	var L: Dictionary = def.layers[sel]
	var move := func(dir: int) -> void:
		var j := sel + dir
		if j < 0 or j >= def.layers.size():
			return
		var tmp = def.layers[sel]
		def.layers[sel] = def.layers[j]
		def.layers[j] = tmp
		sel = j
		render_side()
	side.add_child(EdStyle.h4("Layer %d" % (sel + 1)))
	side.add_child(EdStyle.flow([
		EdStyle.small_button("▲ Up", func(): move.call(1)),
		EdStyle.small_button("▼ Down", func(): move.call(-1)),
		EdStyle.small_button("Show" if L.get("hidden", false) else "Hide", func(): L["hidden"] = not L.get("hidden", false); render_side()),
		EdStyle.small_button("Copy", func(): def.layers.insert(sel + 1, L.duplicate(true)); sel += 1; render_side()),
		EdStyle.small_button("Delete", func(): def.layers.remove_at(sel); sel = maxi(0, sel - 1); render_side())]))
	if L.get("image") != null and str(L.image) != "":
		side.add_child(_row("Picture", [EdStyle.note("an imported image")]))
	else:
		side.add_child(_row("Texture", [EdStyle.option(names, L.get("tex"), func(v): L["tex"] = v; render_side())]))
	side.add_child(_row("Offset x / y", [_num(EdDoc.num(L.get("x"), 0), func(v): L["x"] = v), _num(EdDoc.num(L.get("y"), 0), func(v): L["y"] = v)]))
	side.add_child(_row("Scale x / y", [_num(EdDoc.num(L.get("sx"), 1), func(v): L["sx"] = v, 0.25, 0.05, 16), _num(EdDoc.num(L.get("sy"), 1), func(v): L["sy"] = v, 0.25, 0.05, 16)]))
	side.add_child(_row("Turn", [EdStyle.option([[0, "0°"], [1, "90°"], [2, "180°"], [3, "270°"]], int(EdDoc.num(L.get("rot"), 0)) % 4, func(v): L["rot"] = v; _dirty_draw = true)]))
	side.add_child(_row("Flip x / y", [EdStyle.check(L.get("flipX", false), func(v): L["flipX"] = v; _dirty_draw = true),
		EdStyle.check(L.get("flipY", false), func(v): L["flipY"] = v; _dirty_draw = true)]))
	side.add_child(_row("Tile", [EdStyle.check(L.get("tile", true), func(v): L["tile"] = v; _dirty_draw = true)]))
	var tint := ColorPickerButton.new()
	tint.color = EdDoc.col(L.get("tint", "#ffffff"), Color.WHITE)
	tint.edit_alpha = false
	tint.focus_mode = Control.FOCUS_NONE
	tint.color_changed.connect(func(c): L["tint"] = "#" + c.to_html(false); _dirty_draw = true)
	side.add_child(_row("Tint", [tint]))
	var blends := []
	for b in EdTex.BLENDS:
		blends.append([b, b])
	side.add_child(_row("Blend", [EdStyle.option(blends, L.get("blend", "normal"), func(v): L["blend"] = v; render_side())]))
	var op := HSlider.new()
	op.min_value = 0
	op.max_value = 1
	op.step = 0.05
	op.value = EdDoc.num(L.get("alpha"), 1)
	op.focus_mode = Control.FOCUS_NONE
	op.value_changed.connect(func(v): L["alpha"] = v; _dirty_draw = true)
	side.add_child(_row("Opacity", [op]))
	_dirty_draw = true

func _import() -> void:
	ui.import_image_dialog(func(p: String):
		var img := Image.load_from_file(p)
		if img == null or img.is_empty():
			err.text = "Could not read %s." % p.get_file()
			return
		img.convert(Image.FORMAT_RGBA8)
		var k := minf(1.0, float(EdTex.TEX_MAX) / maxf(img.get_width(), img.get_height()))
		if k < 1:
			img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
		var L := EdTex.new_layer(null)
		L["image"] = EdTex.image_to_url(img)
		if def.layers.size() == 1 and def.layers[0].get("tex") == from and original == null:
			def.w = img.get_width()
			def.h = img.get_height()
			def.worldW = img.get_width()
			def.worldH = img.get_height()
		def.layers.append(L)
		sel = def.layers.size() - 1
		render_side())
