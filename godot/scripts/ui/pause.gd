## MEWD — paused (index.html #pause, and the settings in js/main.js).
##
## Five pages of square tiles, tabbed rather than scrolled, at the user's
## request (a phone held sideways is wide and short). A tile says what it
## is, what it is set to, and — as a bar — where that sits among what it
## could be. CLICKING ONE CYCLES IT; right-click goes back a step. The
## choices are kept (user://prefs.cfg), and the defaults are the web
## build's (but the world drawn at the chunky grid's own size, for speed): 320 rows of 2:3 pixels, brightness 1.35, the
## clock at two, clear, and BOTH DEBUG SWITCHES ON — infinite ammo and
## invincibility — at the user's request.
class_name PauseMenu
extends Control

signal resumed
signal quit_to_title

const PREFS := "user://prefs.cfg"
const PREF_VERSION := 13

## [key, name, page, ladder of [value, label]]
const DIALS := [
	["sens", "LOOK SPEED", 1, [[0.5, "0.5X"], [0.75, "0.75X"], [1.0, "1.0X"], [1.25, "1.25X"], [1.5, "1.5X"], [2.0, "2.0X"], [3.0, "3.0X"]]],
	["invert", "INVERT LOOK", 1, [[false, "OFF"], [true, "ON"]]],
	["music", "MUSIC", 1, [[0.0, "0%"], [0.25, "25%"], [0.5, "50%"], [0.75, "75%"], [1.0, "100%"]]],
	["detail", "RENDER", 2, [[-1, "PIXEL"], [240, "240P"], [480, "480P"], [720, "720P"], [960, "960P"], [0, "NATIVE"]]],
	["pixels", "PIXELS", 2, [[120, "120P"], [150, "150P"], [200, "200P"], [240, "240P"], [320, "320P"], [400, "400P"], [480, "480P"], [600, "600P"], [0, "OFF"]]],
	["pixar", "PIXEL ASPECT", 2, [[1.0, "SQUARE"], [0.83333, "TALL 5:6"], [0.66667, "TALL 2:3"], [1.16667, "WIDE 7:6"]]],
	["snap", "PALETTE", 2, [[true, "RAMPS"], [false, "FULL COLOUR"]]],
	["bright", "BRIGHTNESS", 3, [[0.8, "0.80"], [1.0, "1.00"], [1.15, "1.15"], [1.35, "1.35"], [1.5, "1.50"], [1.75, "1.75"], [2.0, "2.00"]]],
	["contrast", "CONTRAST", 3, [[0.7, "0.70"], [0.85, "0.85"], [1.0, "1.00"], [1.15, "1.15"], [1.3, "1.30"]]],
	["gamma", "GAMMA", 3, [[0.7, "0.70"], [0.85, "0.85"], [1.0, "1.00"], [1.15, "1.15"], [1.3, "1.30"]]],
	["hour", "TIME", 4, [[22.0, "22:00"], [0.0, "00:00"], [2.0, "02:00"], [4.5, "04:30"], [5.17, "05:10"], [5.67, "05:40"], [6.5, "06:30"], [8.0, "08:00"]]],
	["weather", "WEATHER", 4, [["clear", "CLEAR"], ["overcast", "OVERCAST"], ["rain", "RAIN"], ["mist", "MIST"]]],
	["debug", "DEBUG: INFINITE AMMO", 5, [[false, "OFF"], [true, "ON"]]],
	["godmode", "DEBUG: INVINCIBLE", 5, [[false, "OFF"], [true, "ON"]]],
	["fps", "FRAME RATE", 5, [[false, "OFF"], [true, "ON"]]],
]
const DEFAULTS := {"sens": 1.0, "invert": false, "music": 0.5, "detail": -1, "pixels": 320, "pixar": 0.66667,
	"snap": true, "bright": 1.35, "contrast": 1.0, "gamma": 1.0, "hour": 2.0, "weather": "clear",
	"debug": true, "godmode": true, "fps": false}
const PAGES := ["1 CONTROLS", "2 PICTURE", "3 LEVELS", "4 WORLD", "5 DEBUG"]

var prefs := {}
var page := 1
var font: Font
var tabs: Array[Button] = []
var grid: GridContainer
var tiles := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono"]))
	load_prefs()
	var shade := ColorRect.new()
	shade.color = Color(4 / 255.0, 5 / 255.0, 9 / 255.0, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(11 / 255.0, 13 / 255.0, 20 / 255.0, 0.92)
	sb.border_color = Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var h := _label("P A U S E D", 20, Color("#e9e9ee"))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 6)
	col.add_child(tabrow)
	for i in PAGES.size():
		var t := _button(PAGES[i], 12)
		t.pressed.connect(func(): show_page(i + 1))
		tabrow.add_child(t)
		tabs.append(t)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.custom_minimum_size = Vector2(560, 300)
	col.add_child(grid)
	for d in DIALS:
		var tile := _button("", 12)
		tile.custom_minimum_size = Vector2(180, 92)
		tile.gui_input.connect(func(e): _tile_input(e, d[0]))
		grid.add_child(tile)
		tiles[d[0]] = tile
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	var resume := _button("RESUME", 14, true)
	resume.pressed.connect(func(): resumed.emit())
	foot.add_child(resume)
	var quit := _button("QUIT TO TITLE", 14)
	quit.pressed.connect(func(): quit_to_title.emit())
	foot.add_child(quit)
	show_page(1)

func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l

func _button(t: String, size: int, primary := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#c8321e") if primary else Color(1, 1, 1, 0.04)
	sb.border_color = Color("#e0442c") if primary else Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	var hov := sb.duplicate()
	hov.bg_color = Color("#d8432e") if primary else Color(1, 1, 1, 0.1)
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed"]:
		b.add_theme_stylebox_override(st, hov)
	return b

func show_page(n: int) -> void:
	page = n
	for i in tabs.size():
		tabs[i].modulate = Color(1, 1, 1, 1.0 if i + 1 == n else 0.5)
	for d in DIALS:
		tiles[d[0]].visible = d[2] == n
	_refresh()

func _index_of(d: Array) -> int:
	var v = prefs.get(d[0], DEFAULTS[d[0]])
	var ladder: Array = d[3]
	for i in ladder.size():
		if typeof(ladder[i][0]) == typeof(v) and (ladder[i][0] == v or (v is float and absf(ladder[i][0] - v) < 1e-3)):
			return i
	return 0

func _refresh() -> void:
	for d in DIALS:
		var i := _index_of(d)
		var ladder: Array = d[3]
		var bar := "▮".repeat(i + 1) + "▯".repeat(ladder.size() - i - 1) if ladder.size() > 2 else ""
		tiles[d[0]].text = "%s\n\n%s\n%s" % [d[1], ladder[i][1], bar]

func _tile_input(e: InputEvent, key: String) -> void:
	if not (e is InputEventMouseButton) or not e.pressed:
		return
	var step := 1 if e.button_index == MOUSE_BUTTON_LEFT else (-1 if e.button_index == MOUSE_BUTTON_RIGHT else 0)
	if step == 0:
		return
	for d in DIALS:
		if d[0] == key:
			var ladder: Array = d[3]
			var i := (_index_of(d) + step + ladder.size()) % ladder.size()
			prefs[key] = ladder[i][0]
	save_prefs()
	_refresh()
	get_parent().get_parent().apply_prefs(prefs)

func load_prefs() -> void:
	prefs = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PREFS) == OK and int(cf.get_value("prefs", "v", 0)) == PREF_VERSION:
		for k in DEFAULTS:
			prefs[k] = cf.get_value("prefs", k, DEFAULTS[k])

func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("prefs", "v", PREF_VERSION)
	for k in prefs:
		cf.set_value("prefs", k, prefs[k])
	cf.save(PREFS)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_5:
		show_page(k - KEY_0)
		get_viewport().set_input_as_handled()
