## MEWD — the title (index.html #title, css/style.css, js/main.js).
## (MEWD: Made Entirely Without Doom.)
##
## The logo over the menu, the pair centred on the glass — as wide as
## the glass allows (96% of it, or 112% of its height) and never so
## tall that the menu falls off (66% of the height); a phone on its
## side is too short for one above the other, so there the logo takes
## the left and the menu stands at its right.
##
## THE MENU, DOOM'S SHAPE IN THIS GAME'S CLOTHES: a column of words (no
## blinking marker, at the user's request). The
## one you are on is filled in red, the logo's brick, at the user's
## request. NEW GAME opens the LEVELS — the islands (Islands.LIST), at
## the user's request — in the same column, and one of those starts the
## game; the others shake their heads.
##
## THE LAYERS, at the user's request, top to bottom: this menu; MEWD and
## its SHADOWS, softer than they were, in front of the dither (`shade`, a
## Control under the logo on the title's own layer); the blue, over the
## finished frame; the dither; the forest in grey.
class_name Title
extends Control

## the island chosen (Islands.LIST's key)
signal new_game(map: String)
signal pad_setup

const ITEMS := [["NEW GAME", "new", true], ["CONTINUE", "continue", false], ["LOAD GAME", "load", false],
	["SET UP PAD", "pad", true], ["MULTIPLAYER", "multi", false], ["QUIT GAME", "quit", false],
	["DOWNLOAD ZIP", "zip", true]]
## THE WHOLE THING AS A ZIP, at the user's request: GitHub's own archive of
## the repository's main branch — the Godot project, the web build, every
## asset — so it is always the latest and costs the site nothing to host
## THE LEVELS, under NEW GAME: every island, then BACK
static var LEVELS: Array = _levels()
static func _levels() -> Array:
	var out := []
	for i in Islands.LIST:
		out.append([i.title, "map:" + i.key, true])
	out.append(["BACK", "back", true])
	return out
const ZIP_URL := "https://github.com/verdictzero/mewd-engine/archive/refs/heads/main.zip"
const RED := Color("#c8321e")
const RED_EDGE := Color("#e0442c")
const VERSION := "0.2.0"

var logo: TextureRect
var panel: PanelContainer
var buttons: Array[Button] = []
var at := 0
## the column on show: the main menu, or the levels
var items: Array = ITEMS
var col: VBoxContainer
var font: Font
## the logo's shadows, inside the picture: [TextureRect, grow, dx, dy]
var shade: Control
var shadows := []
var _shake := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono", "Liberation Mono"]))
	logo = TextureRect.new()
	logo.texture = load("res://assets/logo/mewd-1440.webp")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(11 / 255.0, 13 / 255.0, 20 / 255.0, 0.82)
	sb.border_color = Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 18
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	_build_buttons()
	var ver := Label.new()
	ver.text = "V" + VERSION
	ver.add_theme_font_override("font", font)
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.35))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position -= Vector2(64, 24)
	add_child(ver)
	mark(0)
	resized.connect(_layout)
	_layout()

func _build_buttons() -> void:
	for b in buttons:
		col.remove_child(b)
		b.queue_free()
	buttons = []
	for i in items.size():
		var b := Button.new()
		b.text = _spaced(items[i][0])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", font)
		b.mouse_entered.connect(func(): mark(i))
		b.pressed.connect(func(): take(i))
		col.add_child(b)
		buttons.append(b)

## The column on show: the main menu, or the levels under NEW GAME.
func show_page(levels: bool) -> void:
	items = LEVELS if levels else ITEMS
	_shake = {}
	_build_buttons()
	mark(0)
	_layout()

## the menu's words set wide, as the page's letter-spacing sets them
static func _spaced(s: String) -> String:
	return " ".join(s.split(""))

## The shadows go into `into`, a Control under the logo; `k` maps this
## screen's pixels to its.
func attach_shade(into: Control) -> void:
	shade = into
	var img: Image = logo.texture.get_image()
	img.decompress()
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	# a wide dark halo, and a tight drop shadow down and right — both
	# lighter than they were (at the user's request: less pronounced)
	for p in [[0.10, 0.0, 0.01, 5.0, 0.03, 0.38], [0.03, 0.012, 0.03, 3.0, 0.008, 0.45]]:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var m := ShaderMaterial.new()
		m.shader = preload("res://godot/shaders/logo_shadow.gdshader")
		m.set_shader_parameter("blur", U.col(p[3]))
		m.set_shader_parameter("spread", U.col(p[4]))
		m.set_shader_parameter("strength", U.col(p[5]))
		m.set_shader_parameter("grow", U.col(p[0]))
		r.material = m
		shade.add_child(r)
		shadows.append([r, p[0], p[1], p[2]])
	_layout()

func _layout() -> void:
	var W := size.x
	var H := size.y
	if W <= 0 or H <= 0:
		return
	var tex_aspect := 1951.0 / 954.0
	var side := H <= 520.0 and W > H
	var lw: float
	var lh: float
	var fs := int(clampf(H * 0.021, 11.0, 14.4))
	for b in buttons:
		b.add_theme_font_size_override("font_size", fs)
		b.custom_minimum_size = Vector2(0, 30 if side else 34)
	var pw := minf(320.0, W * 0.8) if not side else minf(240.0, W * 0.32)
	panel.custom_minimum_size = Vector2(pw, 0)
	panel.size = Vector2(pw, 0)
	panel.reset_size()
	var ph := panel.get_combined_minimum_size().y
	if side:
		lw = minf(W * 0.60, H * 1.5)
		lh = minf(lw / tex_aspect, H * 0.9)
		lw = lh * tex_aspect
		var gap := W * 0.03
		var total := lw + gap + pw
		logo.position = Vector2((W - total) / 2.0, (H - lh) / 2.0)
		panel.position = Vector2(logo.position.x + lw + gap, (H - ph) / 2.0)
	else:
		lw = minf(minf(W * 0.96, H * 1.12), 1951.0)
		var gap := clampf(H * 0.025, 6.0, 26.0)
		# the logo takes what the menu leaves, and the menu never falls
		# off the bottom however many things are on it
		lh = minf(lw / tex_aspect, minf(H * 0.66, H - ph - gap - H * 0.05))
		lw = lh * tex_aspect
		var total := lh + gap + ph
		logo.position = Vector2((W - lw) / 2.0, (H - total) / 2.0)
		panel.position = Vector2((W - pw) / 2.0, logo.position.y + lh + gap)
	logo.size = Vector2(lw, lh)
	panel.size = Vector2(pw, ph)
	_place_shadows()

func _place_shadows() -> void:
	if shade == null or size.x <= 0:
		return
	var k := shade.size.x / size.x
	var r := Rect2(logo.position, logo.size)
	for s in shadows:
		var grow: float = s[1]
		var t: TextureRect = s[0]
		t.position = (r.position - r.size * grow + Vector2(s[2] * r.size.x, s[3] * r.size.y)) * k
		t.size = r.size * (1.0 + 2.0 * grow) * k

func mark(i: int) -> void:
	at = (i + items.size()) % items.size()
	_style()

func _style() -> void:
	for j in buttons.size():
		var b := buttons[j]
		var on := j == at
		var live: bool = items[j][2]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		if on and live:
			sb.bg_color = RED
			sb.border_color = RED_EDGE
		elif on:
			sb.bg_color = Color(1, 1, 1, 0.05)
			sb.border_color = Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.4)
		else:
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0, 0, 0, 0)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		var ink := Color("#ffffff") if (on and live) else (Color("#e9e9ee") if live else Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.6 if on else 0.34))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, ink)
		b.text = _spaced(items[j][0])

func take(i: int) -> void:
	mark(i)
	if not items[at][2]:
		_shake[at] = 0.32     # NOT YET: the one you tried shakes its head
		return
	var what: String = items[at][1]
	if what == "new":
		show_page(true)
	elif what == "back":
		show_page(false)
	elif what.begins_with("map:"):
		new_game.emit(what.substr(4))
	elif what == "pad":
		pad_setup.emit()
	elif what == "zip":
		OS.shell_open(ZIP_URL)

func _process(dt: float) -> void:
	for j in _shake.keys():
		_shake[j] -= dt
		var t: float = 0.32 - _shake[j]
		buttons[j].position.x = sin(t / 0.32 * TAU * 2.0) * 5.0 if _shake[j] > 0 else 0.0
		if _shake[j] <= 0:
			_shake.erase(j)
	_place_shadows()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# the pad: up and down, and A or Start takes, B back (Pad.nav)
	match Pad.nav(event):
		"up": mark(at - 1)
		"down": mark(at + 1)
		"ok", "start": take(at)
		"back":
			if items == LEVELS:
				show_page(false)
		_:
			if not (event is InputEventKey) or not event.pressed:
				return
			match event.physical_keycode:
				KEY_UP, KEY_W:
					mark(at - 1)
				KEY_DOWN, KEY_S:
					mark(at + 1)
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					take(at)
				KEY_ESCAPE, KEY_BACKSPACE:
					if items == LEVELS:
						show_page(false)
				_:
					return
	get_viewport().set_input_as_handled()
