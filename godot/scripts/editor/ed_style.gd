## MEWD Editor — the look (css/editor.css): a dark workspace, the map in
## the middle, panels either side, a status line along the bottom — the
## web build's colours, as a Godot Theme and a few builders the panels
## share.
class_name EdStyle

const BG := Color("#0d1013")
const PANEL := Color("#151a1f")
const PANEL2 := Color("#1b2128")
const LINE := Color("#2a323b")
const TEXT := Color("#cfd8dc")
const DIM := Color("#7d8a93")
const ACCENT := Color("#3ddc84")
const ACCENT2 := Color("#ffb454")
const DANGER := Color("#ff5c5c")
const SEL := Color("#ff9d3d")
const FIELD := Color("#0f1317")
const VIEW_BG := Color("#07090b")

static var _mono: Font = null
static var _sans: Font = null
static var _theme: Theme = null

const MONO_NAMES := ["Cascadia Mono", "DejaVu Sans Mono", "Liberation Mono", "Menlo", "Consolas", "monospace"]
const SANS_NAMES := ["Segoe UI", "DejaVu Sans", "Liberation Sans", "Roboto", "Helvetica", "Arial", "sans-serif"]

static func mono() -> Font:
	if _mono == null:
		_mono = U.ui_font(MONO_NAMES, true)
	return _mono

static func sans() -> Font:
	if _sans == null:
		_sans = U.ui_font(SANS_NAMES, false)
	return _sans

static var _bold := {}

## The face at a weight (the web build's 600 headings).
static func bold(is_mono := false) -> Font:
	var k := "m" if is_mono else "s"
	if not _bold.has(k):
		_bold[k] = U.ui_font(MONO_NAMES if is_mono else SANS_NAMES, is_mono, 700 if is_mono else 600)
	return _bold[k]

static func box(bg: Color, border := Color(0, 0, 0, 0), radius := 4, bw := 1, pad := Vector4(6, 2, 6, 2)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	return s

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 12
	for c in ["Label", "Button", "LineEdit", "OptionButton", "CheckBox", "PopupMenu", "SpinBox", "ItemList", "TooltipLabel", "RichTextLabel"]:
		t.set_color("font_color", c, TEXT)
	# buttons: .ed-btn
	var n := box(PANEL2, LINE, 4, 1, Vector4(9, 3, 9, 3))
	var hv := box(Color("#212831"), Color("#3c4753"), 4, 1, Vector4(9, 3, 9, 3))
	var pr := box(Color("#17301f"), ACCENT, 4, 1, Vector4(9, 3, 9, 3))
	for c in ["Button", "OptionButton"]:
		t.set_stylebox("normal", c, n)
		t.set_stylebox("hover", c, hv)
		t.set_stylebox("pressed", c, pr)
		t.set_stylebox("hover_pressed", c, pr)
		t.set_stylebox("focus", c, StyleBoxEmpty.new())
		t.set_stylebox("disabled", c, n)
		t.set_color("font_hover_color", c, Color.WHITE)
		t.set_color("font_pressed_color", c, Color.WHITE)
		t.set_color("font_hover_pressed_color", c, Color.WHITE)
		t.set_color("font_focus_color", c, TEXT)
	# fields: .ed-row input
	var fld := box(FIELD, LINE, 4, 1, Vector4(6, 2, 6, 2))
	var fldf := box(FIELD, ACCENT, 4, 1, Vector4(6, 2, 6, 2))
	t.set_stylebox("normal", "LineEdit", fld)
	t.set_stylebox("focus", "LineEdit", fldf)
	t.set_stylebox("read_only", "LineEdit", fld)
	t.set_color("caret_color", "LineEdit", Color.WHITE)
	t.set_color("selection_color", "LineEdit", Color(0.24, 0.86, 0.52, 0.35))
	t.set_stylebox("panel", "PopupMenu", box(PANEL2, LINE, 6, 1, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", box(Color("#26303a"), Color(0, 0, 0, 0), 4))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_accelerator_color", "PopupMenu", DIM)
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_stylebox("separator", "PopupMenu", box(LINE, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("panel", "TooltipPanel", box(PANEL2, LINE, 4, 1, Vector4(6, 4, 6, 4)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("panel", "Panel", box(PANEL, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_constant("separation", "HBoxContainer", 6)
	t.set_constant("separation", "VBoxContainer", 5)
	t.set_constant("h_separation", "HFlowContainer", 6)
	t.set_constant("v_separation", "HFlowContainer", 6)
	t.set_constant("h_separation", "GridContainer", 6)
	t.set_constant("v_separation", "GridContainer", 6)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true))
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_stylebox("grabber", "VScrollBar", box(Color("#2a323b"), Color(0, 0, 0, 0), 4, 0, Vector4(3, 3, 3, 3)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color("#3c4753"), Color(0, 0, 0, 0), 4, 0, Vector4(3, 3, 3, 3)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Color("#4d5a66"), Color(0, 0, 0, 0), 4, 0, Vector4(3, 3, 3, 3)))
	t.set_stylebox("slider", "HSlider", box(Color("#2a323b"), Color(0, 0, 0, 0), 2, 0, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area", "HSlider", box(Color("#ffd35a"), Color(0, 0, 0, 0), 2, 0, Vector4(0, 2, 0, 2)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color("#ffd35a"), Color(0, 0, 0, 0), 2, 0, Vector4(0, 2, 0, 2)))
	t.set_stylebox("panel", "Window", box(PANEL, Color("#3a4652"), 8, 1, Vector4(0, 0, 0, 0)))
	t.set_stylebox("embedded_border", "Window", box(PANEL, Color("#3a4652"), 8, 1, Vector4(8, 30, 8, 8)))
	t.set_color("title_color", "Window", Color.WHITE)
	_theme = t
	return t

## A checkbox as the web build's accent-coloured one: a dark square
## with a grey edge, or filled green with a tick.
static func _check_icon(on: bool) -> ImageTexture:
	var n := 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x == 0 or y == 0 or x == n - 1 or y == n - 1
			var corner := (x == 0 or x == n - 1) and (y == 0 or y == n - 1)
			if corner:
				continue
			if on:
				img.set_pixel(x, y, ACCENT)
			else:
				img.set_pixel(x, y, Color("#7d8a93") if edge else FIELD)
	if on:
		for p in [[3, 7], [4, 8], [5, 9], [6, 8], [7, 7], [8, 6], [9, 5], [10, 4], [4, 7], [5, 8], [6, 7], [7, 6], [8, 5], [9, 4], [10, 3]]:
			img.set_pixel(p[0], p[1], Color("#0b1a10"))
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------
# builders
# ---------------------------------------------------------------------

static func label(text: String, color := TEXT, size := 12, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A note: .ed-note — dim, wrapping.
static func note(text: String) -> Label:
	var l := label(text, DIM, 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 60
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## A heading: .ed-insp h4 — small capitals in the mono face.
static func h4(text: String) -> Label:
	var l := label(text.to_upper(), DIM, 10, bold(true))
	l.add_theme_constant_override("line_spacing", 0)
	var m := l
	m.custom_minimum_size.y = 22
	m.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return m

## .ed-insp h3: white, and what is selected on the right.
static func h3(text: String, small := "") -> Control:
	var hb := HBoxContainer.new()
	var a := label(text, Color.WHITE, 12, bold())
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	a.custom_minimum_size.x = 60
	hb.add_child(a)
	if small != "":
		hb.add_child(label(small, DIM, 12))
	return hb

## .ed-btn, with its key in a <kbd>.
static func button(text: String, cb: Callable = Callable(), kbd := "", tip := "") -> Button:
	var b := Button.new()
	b.text = text
	if kbd != "":
		# the key in a <kbd>: dim, small, mono, after the name
		b.text = ""
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		var t := label(text, TEXT, 12)
		t.name = "Text"
		var k := label(kbd, DIM, 10, mono())
		k.name = "Kbd"
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		t.size_flags_vertical = Control.SIZE_FILL
		k.size_flags_vertical = Control.SIZE_FILL
		hb.add_child(t)
		hb.add_child(k)
		b.add_child(hb)
		var fit := func() -> void: b.custom_minimum_size = Vector2(hb.get_combined_minimum_size().x + 18, 26)
		hb.minimum_size_changed.connect(fit)
		b.ready.connect(fit)
		b.set_meta("text_label", t)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 12)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func small_button(text: String, cb: Callable = Callable(), tip := "") -> Button:
	var b := button(text, cb, "", tip)
	b.add_theme_font_size_override("font_size", 11)
	var sb := box(PANEL2, LINE, 4, 1, Vector4(8, 2, 8, 2))
	b.add_theme_stylebox_override("normal", sb)
	return b

## A toggled look for a button (.on).
static func set_on(b: Button, on: bool) -> void:
	var t = (b.get_meta("text_label") if b.has_meta("text_label") else null)
	if on:
		b.add_theme_stylebox_override("normal", box(Color("#17301f"), ACCENT, 4, 1, Vector4(9, 3, 9, 3)))
		b.add_theme_color_override("font_color", Color.WHITE)
		if t != null:
			t.add_theme_color_override("font_color", Color.WHITE)
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_color_override("font_color")
		if t != null:
			t.add_theme_color_override("font_color", TEXT)

## A button's words, whichever way it was made.
static func set_text(b: Button, text: String) -> void:
	var t = (b.get_meta("text_label") if b.has_meta("text_label") else null)
	if t != null:
		t.text = text
		var hb: Control = t.get_parent()
		b.custom_minimum_size.x = hb.get_combined_minimum_size().x + 18
	else:
		b.text = text

## .ed-btn.play
static func play_button(text: String, cb: Callable, kbd := "") -> Button:
	var b := button(text, cb, kbd)
	var t = (b.get_meta("text_label") if b.has_meta("text_label") else null)
	if t != null:
		t.add_theme_color_override("font_color", Color("#bff5d2"))
	b.add_theme_stylebox_override("normal", box(Color("#163322"), Color("#2f7d4d"), 4, 1, Vector4(9, 3, 9, 3)))
	b.add_theme_stylebox_override("hover", box(Color("#1c4029"), Color("#2f7d4d"), 4, 1, Vector4(9, 3, 9, 3)))
	b.add_theme_color_override("font_color", Color("#bff5d2"))
	return b

## A labelled row: .ed-row — a 92-pixel label, then the field(s).
static func row(text: String, fields: Array) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := label(text, DIM, 12)
	l.custom_minimum_size.x = 92
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(l)
	for f in fields:
		if f is Control:
			f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(f)
	return hb

## A number field (input type=number): any value typed, the spinner by
## `step`; `onset` gets the new value when it is committed.
static func num(value, onset: Callable, step := 1.0, tip := "") -> SpinBox:
	var s := SpinBox.new()
	s.allow_greater = true
	s.allow_lesser = true
	s.min_value = -1e9
	s.max_value = 1e9
	s.step = 0.0001
	s.custom_arrow_step = step
	s.select_all_on_focus = true
	s.tooltip_text = tip
	s.update_on_text_changed = false
	if value == null or (value is String and value == ""):
		s.set_value_no_signal(0)
		# blank, as an empty input is: "work it out"
		s.ready.connect(func(): s.get_line_edit().text = "")
	else:
		s.set_value_no_signal(float(value))
	s.custom_minimum_size = Vector2(40, 24)
	s.get_line_edit().add_theme_font_size_override("font_size", 12)
	s.value_changed.connect(func(v): onset.call(v))
	s.get_line_edit().text_submitted.connect(func(_t): s.get_line_edit().release_focus())
	return s

static func text_field(value, onset: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text = str(value) if value != null else ""
	e.custom_minimum_size = Vector2(40, 24)
	e.text_submitted.connect(func(t): onset.call(t); e.release_focus())
	e.focus_exited.connect(func(): if e.text != (str(value) if value != null else ""): onset.call(e.text))
	return e

static func check(value, onset: Callable, text := "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(value)
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on): onset.call(on))
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return c

static func option(items: Array, selected, onset: Callable, tip := "") -> OptionButton:
	# items: [[value, label], ...]
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.tooltip_text = tip
	o.fit_to_longest_item = false
	o.clip_text = true
	o.custom_minimum_size = Vector2(40, 24)
	var vals := []
	for it in items:
		o.add_item(str(it[1]))
		vals.append(it[0])
	var i := vals.find(selected)
	o.select(i)
	o.item_selected.connect(func(k): onset.call(vals[k]))
	o.set_meta("values", vals)
	return o

static func slider(value: float, lo: float, hi: float, step: float, onset: Callable, tip := "") -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.set_value_no_signal(value)
	s.tooltip_text = tip
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(60, 20)
	s.drag_ended.connect(func(changed): if changed: onset.call(s.value))
	return s

static func color_pick(value, onset: Callable) -> ColorPickerButton:
	var c := ColorPickerButton.new()
	c.color = EdDoc.col(value, Color.WHITE)
	c.edit_alpha = false
	c.focus_mode = Control.FOCUS_NONE
	c.custom_minimum_size = Vector2(40, 24)
	c.popup_closed.connect(func(): onset.call("#" + c.color.to_html(false)))
	return c

static func hsep() -> Control:
	var c := ColorRect.new()
	c.color = LINE
	c.custom_minimum_size = Vector2(1, 20)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func flow(children: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	for c in children:
		if c != null:
			f.add_child(c)
	return f

## A dot of a colour (.ed-dot).
static func dot(c: Color, size := 8) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
