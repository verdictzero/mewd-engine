## MEWD — the title (index.html #title, css/style.css, js/main.js).
## (MEWD: Made Entirely Without Doom.)
##
## IN GOLF'S HOUSE STYLE (at the user's request: "port the UI design
## language from verdictzero/golf over to MEWD"; UiStyle): the menu a
## column of rows, each row a box of the glass with its top right and
## bottom left cut, the words in Zalando Sans Condensed. The one you are on
## is white and bold, its box brighter and its keyline white, and slides in
## from the right; the others rest in thin grey; one not ready yet is dim
## and shakes its head when tried. No hue.
##
## THE LOGO AND THE MENU, ONE GROUP IN THE MIDDLE (at the user's request:
## "have the MEWD logo and the menu vertically centered and horizontally
## centered as a group ... since we only support wide screens ... make
## that the way it is permanently"): the logo over the menu, both centred
## across, the two together centred down — on the longest column (the main
## menu), so the logo never moves as the pages change and every column
## hangs from the same line under it. One layout, every screen.
##
## THE LOGO KEEPS ITS SIZE (at the user's request: "make sure the MEWD
## logo on the title retains a constant size regardless of menu
## configuration"), and a SMALLER one ("make the MEWD logo smaller on the
## title screen"): its size is the screen's alone — LOGO_H of the height,
## or 60% of the width if that is less — and the menu takes what is under
## it, its rows made shorter (never the logo smaller) when the screen is
## short.
##
## NEW GAME opens the LEVELS — the islands (Islands.LIST), at the user's
## request — in the same column, and one of those starts the game.
##
## THE LAYERS, at the user's request, top to bottom: this menu; MEWD and
## its SHADOWS, softer than they were, in front of the dither (`shade`, a
## Control under the logo on the title's own layer); the darkening grey,
## over the finished frame; the dither; the film grain, under it; the
## forest, in black and white (TitleForest: TINT, GRAIN).
class_name Title
extends Control

## the island chosen (Islands.LIST's key)
signal new_game(map: String)
signal pad_setup
## DEBUG: the logs and the last failure (ui/debug_menu.gd)
signal debug_menu
## MULTIPLAYER: host a match on this island (Main.host_game), every player
## for themselves or in two teams, or join one
signal host_game(map: String, teams: bool)
signal join_game

const ITEMS := [["NEW GAME", "new", true], ["CONTINUE", "continue", false], ["LOAD GAME", "load", false],
	["SET UP PAD", "pad", true], ["MULTIPLAYER", "multi", true], ["DEBUG", "debug", true],
	["QUIT GAME", "quit", false]]
## (DOWNLOAD ZIP, GitHub's archive of the repository, is gone: at the
## user's request, "remove download zip")
## THE LEVELS, under NEW GAME: every island, then BACK
static var LEVELS: Array = _levels()
static func _levels() -> Array:
	var out := []
	for i in Islands.LIST:
		out.append([i.title, "map:" + i.key, true])
	out.append(["BACK", "back", true])
	return out
## MULTIPLAYER (at the user's request: sixteen players, dropped in by pod,
## a deathmatch): host a match here — on which island — or join one
const MULTI := [["HOST GAME", "hosts", true], ["JOIN GAME", "join", true], ["BACK", "back", true]]
static var HOSTS: Array = _hosts()
static func _hosts() -> Array:
	var out := []
	for i in Islands.LIST:
		out.append([i.title, "host:" + i.key, true])
	out.append(["BACK", "multi", true])
	return out
## HOW THE HOSTED MATCH IS PLAYED, once its island is chosen (at the
## user's request: teams): every player for themselves, or two sides
const MODES := [["DEATHMATCH", "mode:dm", true], ["TEAM DEATHMATCH", "mode:tdm", true], ["BACK", "hosts", true]]
## the island HOST GAME chose, waiting on MODES
var _host_map := ""
## THE ROWS (golf's title menu: SCRIPT_main_menu.gd): their height, the
## words' size, the gap between them, and how far the one you are on
## slides in
const ROW_H := 38.0
const ROW_FONT := 22
const ROW_GAP := 6.0
const INDENT_SEL := 26.0
const ROW_W := 372.0
## the logo's height, a share of the screen's (it was 0.46)
const LOGO_H := 0.30
## every column the title shows, for the longest
static var PAGES: Array = [ITEMS, LEVELS, MULTI, HOSTS, MODES]

var logo: TextureRect
## the column of rows (a VBox; each row a MarginContainer round its Button,
## the margin the slide)
var panel: VBoxContainer
var buttons: Array[Button] = []
var rows: Array[MarginContainer] = []
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
	theme = UiStyle.theme()
	font = UiStyle.words("ExtraLight")
	logo = TextureRect.new()
	logo.texture = load("res://assets/logo/mewd-1440.webp")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	panel = VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_theme_constant_override("separation", int(ROW_GAP))
	add_child(panel)
	col = panel
	_build_buttons()
	var ver := Label.new()
	ver.text = U.VERSION
	ver.add_theme_font_override("font", UiStyle.numbers())
	ver.add_theme_font_size_override("font_size", 16)
	ver.add_theme_color_override("font_color", UiStyle.TAG)
	ver.add_theme_constant_override("outline_size", 3)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position += Vector2(24, -30)
	add_child(ver)
	mark(0)
	resized.connect(_layout)
	_layout()

func _build_buttons() -> void:
	for r in rows:
		col.remove_child(r)
		r.queue_free()
	buttons = []
	rows = []
	for i in items.size():
		var r := MarginContainer.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := Button.new()
		b.text = items[i][0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_constant_override("outline_size", 4)
		b.mouse_entered.connect(func(): mark(i))
		b.pressed.connect(func(): take(i))
		r.add_child(b)
		col.add_child(r)
		buttons.append(b)
		rows.append(r)

## The column on show: the main menu, or the levels under NEW GAME.
func show_page(levels: bool) -> void:
	show_items(LEVELS if levels else ITEMS)

## any column: the main menu, the levels, multiplayer's
func show_items(list: Array) -> void:
	items = list
	_shake = {}
	_build_buttons()
	mark(0)
	_layout()

## back a page: the match's modes to the islands, the hosts' islands to
## multiplayer, anything to the menu
func _back() -> void:
	if items == HOSTS:
		show_items(MULTI)
	elif items == MODES:
		show_items(HOSTS)
	elif items != ITEMS:
		show_page(false)

## A LINE UNDER THE MENU for a few seconds (why a join came to nothing):
## golf's flash — BRIGHT, held, then faded
var _note: Label
func notice(text: String) -> void:
	if _note == null:
		_note = UiStyle.label("", "bright", 20, "Medium", 4)
		_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
		add_child(_note)
	_note.text = text
	_note.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(_note, "modulate:a", 0.0, 1.0)

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
	if W <= 0 or H <= 0 or logo == null:
		return
	var ts := logo.texture.get_size()
	var tex_aspect := ts.x / maxf(ts.y, 1.0)
	var n := maxi(items.size(), 1)
	var most := 1
	for p in PAGES:
		most = maxi(most, p.size())
	var margin := clampf(minf(W, H) * 0.055, 16.0, 48.0)
	# THE LOGO: the screen's size alone, never the menu's
	var lh := minf(H * LOGO_H, W * 0.6 / tex_aspect)
	var lw := lh * tex_aspect
	var gap := clampf(H * 0.04, 12.0, 32.0)
	# THE ROWS: as golf's, made shorter only if the longest column would not
	# fit under the logo
	var room := H - margin * 2.0 - lh - gap
	var rh := clampf(minf(ROW_H, (room - ROW_GAP * (most - 1)) / most), 22.0, ROW_H)
	var fs := int(clampf(rh * ROW_FONT / ROW_H, 13.0, ROW_FONT))
	var rw := minf(ROW_W, W - margin * 2.0)
	for j in rows.size():
		buttons[j].add_theme_font_size_override("font_size", fs)
	# (and never shorter than a row's words and frame need: the true height,
	# measured with the last layout's minimum let go)
	for r in rows:
		r.custom_minimum_size = Vector2.ZERO
	for r in rows:
		rh = maxf(rh, r.get_combined_minimum_size().y)
	for r in rows:
		r.custom_minimum_size = Vector2(rw, rh)
	var sep := int(ROW_GAP if rh >= ROW_H - 0.5 else maxf(2.0, ROW_GAP * rh / ROW_H))
	panel.add_theme_constant_override("separation", sep)
	var ph := n * rh + (n - 1) * sep
	# THE GROUP: the logo and the longest column, centred down; each centred
	# across
	var tall := lh + gap + most * rh + (most - 1) * sep
	var top := maxf(margin * 0.5, (H - tall) / 2.0)
	logo.position = Vector2((W - lw) / 2.0, top)
	logo.size = Vector2(lw, lh)
	panel.position = Vector2((W - rw) / 2.0, top + lh + gap)
	panel.size = Vector2(rw, ph)
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
		var on := j == at
		var live: bool = items[j][2]
		UiStyle.dress_row(buttons[j], on, not live, buttons[j].get_theme_font_size("font_size"))
		# (golf's title rows: thin at rest, bold where you are)
		buttons[j].add_theme_font_override("font", UiStyle.words("Bold" if on and live else "ExtraLight"))
		buttons[j].add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		# the one you are on slides in from the right
		rows[j].add_theme_constant_override("margin_left", int(0.0 if on else INDENT_SEL))
		rows[j].add_theme_constant_override("margin_right", int(INDENT_SEL if on else 0.0))
		buttons[j].text = items[j][0]

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
	elif what == "multi":
		show_items(MULTI)
	elif what == "hosts":
		show_items(HOSTS)
	elif what.begins_with("host:"):
		_host_map = what.substr(5)
		show_items(MODES)
	elif what.begins_with("mode:"):
		host_game.emit(_host_map, what == "mode:tdm")
	elif what == "join":
		join_game.emit()
	elif what.begins_with("map:"):
		new_game.emit(what.substr(4))
	elif what == "pad":
		pad_setup.emit()
	elif what == "debug":
		debug_menu.emit()

func _process(dt: float) -> void:
	for j in _shake.keys():
		_shake[j] -= dt
		var t: float = 0.32 - _shake[j]
		var home := float(rows[j].get_theme_constant("margin_left"))
		buttons[j].position.x = home + (sin(t / 0.32 * TAU * 2.0) * 5.0 if _shake[j] > 0 else 0.0)
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
			_back()
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
					_back()
				_:
					return
	get_viewport().set_input_as_handled()
