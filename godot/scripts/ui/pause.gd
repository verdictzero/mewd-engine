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
##
## IN GOLF'S HOUSE STYLE (at the user's request: "port the UI design
## language from verdictzero/golf"; UiStyle): a window of the glass with
## its top right and bottom left cut, over the game darkened in grey; the
## pages a row of plates, the tiles and the footer cut-corner rows. No
## hover of their own and no red: the one cursor (the pad's, or the
## mouse's as it moves) makes a row white and bold, its box brighter and
## its keyline white. The words Zalando Sans Condensed; a line of hints
## at the bottom in TAG.
class_name PauseMenu
extends Control

signal resumed
signal quit_to_title
## SET UP PAD, in the footer: the wizard (ui/pad_wizard.gd)
signal pad_setup
## DEBUG, in the footer: the logs and the last failure (ui/debug_menu.gd)
signal debug_menu

const PREFS := "user://prefs.cfg"
const PREF_VERSION := 20

## [key, name, page, ladder of [value, label]]
const DIALS := [
	["sens", "LOOK SPEED", 1, [[0.5, "0.5X"], [0.75, "0.75X"], [1.0, "1.0X"], [1.25, "1.25X"], [1.5, "1.5X"], [2.0, "2.0X"], [3.0, "3.0X"]]],
	["invert", "INVERT LOOK", 1, [[false, "OFF"], [true, "ON"]]],
	["music", "MUSIC", 1, [[0.0, "0%"], [0.25, "25%"], [0.5, "50%"], [0.75, "75%"], [1.0, "100%"]]],
	["detail", "RENDER", 2, [[-1, "PIXEL"], [180, "180P"], [240, "240P"], [360, "360P"], [480, "480P"], [540, "540P"], [720, "720P"], [960, "960P"], [1080, "1080P"], [1440, "1440P"], [0, "NATIVE"]]],
	["pixels", "PIXELS", 2, [[90, "90P"], [100, "100P"], [120, "120P"], [144, "144P"], [150, "150P"], [160, "160P"], [180, "180P"], [200, "200P"], [240, "240P"], [270, "270P"], [320, "320P"], [360, "360P"], [400, "400P"], [480, "480P"], [540, "540P"], [600, "600P"], [720, "720P"], [0, "OFF"]]],
	["pixar", "PIXEL ASPECT", 2, [[1.0, "SQUARE"], [0.83333, "TALL 5:6"], [0.66667, "TALL 2:3"], [1.16667, "WIDE 7:6"]]],
	["grid", "PIXEL GRID", 2, [["lcd", "LCD"], ["lines", "GRID LINES"], ["off", "OFF"]]],
	["snap", "PALETTE", 2, [[true, "RAMPS"], [false, "FULL COLOUR"]]],
	["bright", "BRIGHTNESS", 3, [[0.8, "0.80"], [1.0, "1.00"], [1.15, "1.15"], [1.35, "1.35"], [1.5, "1.50"], [1.75, "1.75"], [2.0, "2.00"]]],
	["contrast", "CONTRAST", 3, [[0.7, "0.70"], [0.85, "0.85"], [1.0, "1.00"], [1.15, "1.15"], [1.3, "1.30"]]],
	["gamma", "GAMMA", 3, [[0.7, "0.70"], [0.85, "0.85"], [1.0, "1.00"], [1.15, "1.15"], [1.3, "1.30"]]],
	["hour", "TIME", 4, [[22.0, "22:00"], [0.0, "00:00"], [2.0, "02:00"], [4.5, "04:30"], [5.17, "05:10"], [5.67, "05:40"], [6.5, "06:30"], [8.0, "08:00"]]],
	["weather", "WEATHER", 4, [["clear", "CLEAR"], ["overcast", "OVERCAST"], ["rain", "RAIN"], ["mist", "MIST"]]],
	# HOW FAR THINGS ARE DRAWN (at the user's request: "add distance culling
	# options in the options menu"; Distances)
	["dist_land", "LAND DISTANCE", 5, [[0.25, "25%"], [0.5, "50%"], [0.75, "75%"], [1.0, "100%"]]],
	["dist_trees", "TREE DISTANCE", 5, [[0.25, "25%"], [0.5, "50%"], [0.75, "75%"], [1.0, "100%"], [1.5, "150%"]]],
	["dist_grass", "GRASS DISTANCE", 5, [[0.0, "OFF"], [0.5, "50%"], [1.0, "100%"], [1.5, "150%"], [2.0, "200%"]]],
	["dist_people", "PEOPLE DISTANCE", 5, [[1600.0, "50 M"], [3200.0, "100 M"], [6400.0, "200 M"], [12800.0, "400 M"]]],
	["debug", "DEBUG: INFINITE AMMO", 6, [[false, "OFF"], [true, "ON"]]],
	["godmode", "DEBUG: INVINCIBLE", 6, [[false, "OFF"], [true, "ON"]]],
	["fps", "FRAME RATE", 6, [[false, "OFF"], [true, "ON"]]],
]
## THE SETTINGS FILE (at the user's request: "add the ability to save
## settings to a settings file"): [key, name, page] — tiles that do
## something rather than step through a ladder. SAVE writes every setting
## to SETTINGS_FILE (a plain ConfigFile, readable and editable, next to
## the logs: Download/mewd on a phone that gave the storage, the user data
## folder elsewhere), LOAD reads it back, DEFAULTS puts everything back as
## it came. (The menu still keeps its choices on its own, prefs.cfg, as
## before: the file is the copy you keep, move or edit.)
const ACTIONS := [
	["save_file", "SAVE SETTINGS TO FILE", 7],
	["load_file", "LOAD SETTINGS FROM FILE", 7],
	["defaults", "ALL SETTINGS TO DEFAULTS", 7],
]
const SETTINGS_FILE := "mewd-settings.cfg"
const DEFAULTS := {"sens": 1.0, "invert": false, "music": 0.5, "detail": 360, "pixels": 360, "pixar": 1.0, "grid": "lcd",
	"snap": true, "bright": 1.35, "contrast": 1.0, "gamma": 1.0, "hour": 2.0, "weather": "clear",
	"debug": false, "godmode": false, "fps": true,
	"dist_land": 1.0, "dist_trees": 1.0, "dist_grass": 1.0, "dist_people": 6400.0}
const PAGES := ["1 CONTROLS", "2 PICTURE", "3 LEVELS", "4 WORLD", "5 DISTANCE", "6 DEBUG", "7 FILE"]

var prefs := {}
var page := 1
var font: Font
var tabs: Array[Button] = []
var grid: GridContainer
var tiles := {}
## THE PAD'S CURSOR: which tile of the page (0..), or the footer past
## them (RESUME, QUIT TO TITLE); -1 until the pad moves. The D-pad or a
## stick moves it, A steps the tile (B steps it back on a tile), the
## bumpers turn the page, Start or B on the footer resumes.
var cursor := -1
var _foot: Array[Button] = []
## under the tiles on the FILE page: what SAVE or LOAD last did
var file_note: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	font = UiStyle.words("Medium")
	load_prefs()
	var shade := ColorRect.new()
	shade.color = UiStyle.SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.window(Vector4(28, 22, 28, 22)))
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	# the window's tag, and the build's number across from it
	var top := HBoxContainer.new()
	var h := UiStyle.label(UiStyle.spaced("paused"), "tag", 18)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(h)
	top.add_child(UiStyle.number(U.VERSION, "tag", 20))
	col.add_child(top)
	col.add_child(UiStyle.rule())
	var tabrow := HBoxContainer.new()
	tabrow.add_theme_constant_override("separation", 6)
	col.add_child(tabrow)
	for i in PAGES.size():
		var t := _button(PAGES[i], 14)
		t.pressed.connect(func(): show_page(i + 1))
		tabrow.add_child(t)
		tabs.append(t)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.custom_minimum_size = Vector2(560, 300)
	col.add_child(grid)
	for d in DIALS + ACTIONS:
		var tile := _button("", 16)
		tile.custom_minimum_size = Vector2(180, 92)
		tile.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.gui_input.connect(func(e): _tile_input(e, d[0]))
		tile.mouse_entered.connect(func(): _hover(d[0]))
		grid.add_child(tile)
		tiles[d[0]] = tile
	# (what the last SAVE or LOAD did, and where the file is)
	file_note = UiStyle.label("", "tag", 14)
	file_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	file_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	file_note.custom_minimum_size = Vector2(560, 0)
	col.add_child(file_note)
	col.add_child(UiStyle.rule())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 8)
	col.add_child(foot)
	var resume := _button("RESUME", 18)
	resume.pressed.connect(func(): resumed.emit())
	foot.add_child(resume)
	var quit := _button("QUIT TO TITLE", 18)
	quit.pressed.connect(func(): quit_to_title.emit())
	foot.add_child(quit)
	var setup := _button("SET UP PAD", 18)
	setup.pressed.connect(func(): pad_setup.emit())
	foot.add_child(setup)
	var dbg := _button("DEBUG", 18)
	dbg.pressed.connect(func(): debug_menu.emit())
	foot.add_child(dbg)
	_foot = [resume, quit, setup, dbg]
	for j in _foot.size():
		_foot[j].mouse_entered.connect(func(): _cursor_to(_stops().size() + j))
	# golf's hint line: what the keys and the pad do here
	var hint := UiStyle.label("↑↓←→  MOVE      A / CLICK  STEP      B / RIGHT-CLICK  BACK A STEP      L1 R1 / 1–7  PAGE      START  RESUME", "tag", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	show_page(1)
	visibility_changed.connect(func(): if visible: _cursor_to(-1))

func _label(t: String, size: int, c: Color) -> Label:
	var l := UiStyle.label(t, "name", size)
	l.add_theme_color_override("font_color", c)
	return l

## a row of the house's (UiStyle.dress_row), resting until the cursor
## comes to it
func _button(t: String, size: int, _primary := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("size", size)
	UiStyle.dress_row(b, false, false, size)
	return b

## the mouse moving onto a tile moves the cursor there (golf: no hover of
## its own, the one cursor follows the mouse)
func _hover(key: String) -> void:
	var stops := _stops()
	var i := stops.find(key)
	if i >= 0:
		_cursor_to(i)

func show_page(n: int) -> void:
	page = n
	for i in tabs.size():
		UiStyle.dress_row(tabs[i], i + 1 == n, false, tabs[i].get_meta("size", 14))
	for d in DIALS + ACTIONS:
		tiles[d[0]].visible = d[2] == n
	if file_note != null:
		file_note.visible = n == 7
		if file_note.text == "":
			file_note.text = "THE FILE: " + settings_path()
	_refresh()
	_cursor_to(cursor if cursor < 0 else 0)

## the page's tiles, in order, then the footer
func _stops() -> Array:
	var out := []
	for d in DIALS + ACTIONS:
		if d[2] == page:
			out.append(d[0])
	return out

func _cursor_to(i: int) -> void:
	var n := _stops().size() + _foot.size()
	cursor = -1 if i < 0 else ((i + n) % n)
	var stops := _stops()
	for j in stops.size():
		_mark(tiles[stops[j]], cursor == j)
	for j in _foot.size():
		_mark(_foot[j], cursor == stops.size() + j)

func _mark(b: Button, on: bool) -> void:
	UiStyle.dress_row(b, on, false, b.get_meta("size", 16))

## the pad (Pad.nav): moves the cursor over the page's three-wide grid
## and the footer, steps the tile under it, turns the page
func pad_nav(what: String) -> bool:
	var stops := _stops()
	var n := stops.size()
	match what:
		"prev", "next":
			show_page(((page - 1 + (1 if what == "next" else -1) + PAGES.size()) % PAGES.size()) + 1)
			return true
		"start":
			resumed.emit()
			return true
		"up", "down", "left", "right":
			if cursor < 0:
				_cursor_to(0)
				return true
			var c := cursor
			if c < n:
				match what:
					"left": c = c - 1 if c % 3 > 0 else c
					"right": c = c + 1 if c % 3 < 2 and c + 1 < n else c
					"up": c = c - 3 if c >= 3 else c
					"down": c = c + 3 if c + 3 < n else n      # the footer
			else:
				match what:
					"left": c = maxi(n, c - 1)
					"right": c = mini(n + _foot.size() - 1, c + 1)
					"up": c = n - 1
					"down": c = c
			_cursor_to(c)
			return true
		"ok", "back":
			if cursor < 0:
				if what == "back":
					resumed.emit()
				else:
					_cursor_to(0)
				return true
			if cursor < n:
				_step(stops[cursor], 1 if what == "ok" else -1)
			elif what == "back":
				resumed.emit()
			elif cursor == n:
				resumed.emit()
			elif cursor == n + 1:
				quit_to_title.emit()
			elif cursor == n + 2:
				pad_setup.emit()
			else:
				debug_menu.emit()
			return true
	return false

func _step(key: String, step: int) -> void:
	for a in ACTIONS:
		if a[0] == key:
			_act(key)
			return
	for d in DIALS:
		if d[0] == key:
			var ladder: Array = d[3]
			var i := (_index_of(d) + step + ladder.size()) % ladder.size()
			prefs[key] = ladder[i][0]
	save_prefs()
	_refresh()
	get_parent().get_parent().apply_prefs(prefs)

func _index_of(d: Array) -> int:
	var v = prefs.get(d[0], DEFAULTS[d[0]])
	var ladder: Array = d[3]
	for i in ladder.size():
		if typeof(ladder[i][0]) == typeof(v) and (ladder[i][0] == v or (v is float and absf(ladder[i][0] - v) < 1e-3)):
			return i
	return 0

func _refresh() -> void:
	for a in ACTIONS:
		tiles[a[0]].text = "%s\n\nTAP" % a[1]
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
	_step(key, step)

func load_prefs() -> void:
	prefs = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	var v := int(cf.get_value("prefs", "v", 0)) if cf.load(PREFS) == OK else 0
	if v == PREF_VERSION or v == 19 or v == 18:
		for k in DEFAULTS:
			prefs[k] = cf.get_value("prefs", k, DEFAULTS[k])
	# (18 kept everything but INFINITE AMMO, which it had on by default:
	# finite now, at the user's request, so it comes off — the rest kept)
	if v == 18:
		prefs["debug"] = false
	_first_run()

## (a fresh install, no prefs.cfg yet, starts from the settings file if
## one was left where SAVE puts it)
func _first_run() -> void:
	if not FileAccess.file_exists(PREFS) and FileAccess.file_exists(settings_path()):
		read_settings_file()

## where SAVE SETTINGS writes: beside the logs (Logs.dir — on a phone that
## gave the storage, Download/mewd), else the user data folder
static func settings_path() -> String:
	var d := Logs.dir if Logs.dir != "" else "user://"
	return d.path_join(SETTINGS_FILE)

## SAVE SETTINGS TO FILE: every setting, by name, with the build's number
func write_settings_file() -> Error:
	var cf := ConfigFile.new()
	cf.set_value("mewd", "version", U.VERSION)
	cf.set_value("mewd", "prefs_version", PREF_VERSION)
	for k in DEFAULTS:
		cf.set_value("settings", k, prefs.get(k, DEFAULTS[k]))
	return cf.save(settings_path())

## LOAD SETTINGS FROM FILE: whatever of the settings the file has (a key
## it lacks, or a value of the wrong kind, keeps what it was)
func read_settings_file() -> Error:
	var cf := ConfigFile.new()
	var err := cf.load(settings_path())
	if err != OK:
		return err
	for k in DEFAULTS:
		if cf.has_section_key("settings", k):
			var v = cf.get_value("settings", k)
			var want = DEFAULTS[k]
			if typeof(v) == typeof(want) or (want is float and v is int) or (want is int and v is float):
				prefs[k] = float(v) if want is float else (int(v) if want is int else v)
	return OK

func _act(key: String) -> void:
	var path := settings_path()
	match key:
		"save_file":
			var err := write_settings_file()
			file_note.text = ("SAVED TO " + ProjectSettings.globalize_path(path)) if err == OK else "COULD NOT SAVE TO %s (ERROR %d)" % [path, err]
		"load_file":
			var err := read_settings_file()
			file_note.text = ("LOADED FROM " + ProjectSettings.globalize_path(path)) if err == OK else "NO SETTINGS FILE AT " + ProjectSettings.globalize_path(path)
		"defaults":
			prefs = DEFAULTS.duplicate()
			file_note.text = "EVERY SETTING BACK TO ITS DEFAULT"
	save_prefs()
	_refresh()
	var m := get_parent().get_parent() if get_parent() != null else null
	if m != null and m.has_method("apply_prefs"):
		m.apply_prefs(prefs)

func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("prefs", "v", PREF_VERSION)
	for k in prefs:
		cf.set_value("prefs", k, prefs[k])
	cf.save(PREFS)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if pad_nav(Pad.nav(event)):
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_7:
		show_page(k - KEY_0)
		get_viewport().set_input_as_handled()
