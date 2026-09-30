## MEWD Editor — the map editor (js/editor/editor.js), in the game.
##
## An editor in the mould of SLADE and Ultimate Doom Builder, opened
## from the front-door terminal (E or EDIT), with `--edit` on the
## command line, or F2 from the game: draw sectors on a grid, drag
## vertices, flip between the plan and the 3D view, raise a floor with
## the wheel, test the map in one key.
##
##   ed_doc.gd       the map as a document, the undo stack, problems
##   ed_ops.gd       the edits on the document
##   ed_steps.gd     the step generator; ed_scatter.gd the scatters
##   ed_texcompose.gd, ed_texeditor.gd   the map's own textures
##   view2d.gd       the plan: the Doom Builder half
##   view3d.gd       the 3D view, drawn by the game's own MapGeo
##   ed_ui.gd        the bars, the inspector, the panels
##   editor.gd       this: the state all of them share, and the keyboard
##
## WHAT IT HANDS THE GAME IS THE SAME DOCUMENT: Play (F5) keeps the map
## and the game compiles it with the same compiler; F2 in the game comes
## back here, to the map as it was. Files are the web build's JSON, so a
## map goes between the two builds either way.
class_name MewdEditor
extends Control

signal doc_changed
signal sel_changed
signal mode_changed(m: String)
signal grid_changed
signal layout_changed(l: String)
signal compiled_ready
signal path_changed
signal cursor_changed
signal hover_changed
signal status_changed(msg: String)
signal textures_changed
signal layer_changed(k: int)
signal camera_changed
signal frame_req
signal frame_sel_req
signal visual_changed(on: bool)
## Play: the game, on this document
signal play_requested(doc: Dictionary)
## back to the terminal
signal quit_requested

const DIR := "user://mewd-editor/"
const AUTOSAVE := "user://mewd-editor/autosave.gssmap.json"
const PREFS := "user://mewd-editor/prefs.json"
const MAPS := "user://mewd-editor/maps/"

## the grid ladder: Doom Builder's own
const GRIDS := [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
const GRID_MAX := 4096

const MODES := {
	"vertices": {"key": "V", "name": "Vertices", "short": "Verts"},
	"lines": {"key": "L", "name": "Lines", "short": "Lines"},
	"sectors": {"key": "S", "name": "Sectors", "short": "Sectors"},
	"things": {"key": "T", "name": "Things", "short": "Things"},
	"props": {"key": "P", "name": "Props", "short": "Props"},
	"draw": {"key": "D", "name": "Draw lines and sectors", "short": "Draw"},
	"rect": {"key": "R", "name": "Draw a shape", "short": "Shape"},
	"scatter": {"key": "X", "name": "Scatter", "short": "Scatter"},
	"doors": {"key": "O", "name": "Doors", "short": "Doors"},
}
## what each mode selects
const MODE_KIND := {"vertices": "vertex", "lines": "line", "sectors": "sector", "things": "thing", "props": "prop", "scatter": "scatter",
	"doors": "line"}

## THE HAND-OVER between the editor and the game, kept across the scene
## reload that swaps one for the other (godot/scripts/main.gd).
static var play_doc = null
static var came_from_editor := false
static var open_next := false
## opened from the title's MAP EDITOR: "Back" goes to the title
var from_title := false
static var came_from_title := false

var history: EdDoc.History
var doc: Dictionary:
	get:
		return history.doc

var mode := "sectors"
var mode_before_draw := ""
var grid := 64
var snap := true
var thing_type := "SHOPPER"
var plant_kind := "fir_tall_1"
var scatter_preset := "crowd"
var brush_radius := 512
## THE SECTOR BEING DRAWN, shared by both views
var path: Array = []
var shape := "rect"
var shape_sides = null
var cursor = null
var cursor_kind := "grid"
var prop_tex := "GRIDWALL"
## THE SELECTION: one kind at a time — vertices by index, lines by key,
## the rest by id — as an ordered set
var sel_kind := ""
var sel_ids := {}
## a LOOP of lines (loop_select): the id of the sector whose walls they
## are, whose side of each a texture goes on — null for any other pick
var sel_face = null
## what is under the mouse, from whichever view: {kind, id}
var hovered = null
var _hover_key := ""
## and in the 3D view, a SURFACE: {sector (index), part, line, band}
var surf = null
var compiled := {"level": null, "problems": [], "scattered": [], "grown": {}}
var layout := "combined"
var status := ""
var plan_view := "normal"
var pointer_view := "2d"
var clipboard = null
var tabs_hidden := false

var bank: TexBank
var game_texture_names: Array = []
var map_texture_names: Array = []
var texture_names: Array = []
var built_in: Dictionary = {}

var view2d
var view3d
var ui

var _lines_cache = null
var _last_edit = null
var _compile_at := -1
var _save_at := -1
var _thread: Thread = null
var _compile_again := false
var _tex_key := ""
var _last_layer := 0
var _other_key = null
var _other_cache: Array = []
## headless tests build the editor without views and compile at once
var headless := false
## a drag is under way: the 3D view waits for it to end to rebuild
var dragging := false

func _init(start_doc = null, is_headless := false) -> void:
	headless = is_headless
	Forest.kind_index("fir_tall_1")         # the forest's tables, before any thread
	var prefs := _load_prefs()
	var g := int(prefs.get("grid", 64))
	grid = clampi(g, 1, GRID_MAX)
	snap = prefs.get("snap", true) != false
	tabs_hidden = prefs.get("tabs", "on") == "off"
	var d = start_doc
	if d == null and not headless:
		d = _read_autosave()
	var opened := d != null
	if d == null:
		d = EdDoc.grid_doc()
	history = EdDoc.History.new(d)
	bank = TexBank.new()
	built_in = EdTex.built_in()
	game_texture_names = built_in.keys()
	game_texture_names.sort()
	_tex_key = _texture_key(doc)
	_refresh_textures(false)
	status = "opened your last map" if opened else "THE GRID — D draws a sector, X scatters, every mode works in 3D; Tab swaps the views, F5 plays"

func _ready() -> void:
	theme = EdStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if headless:
		compile_now()
		return
	ui = EdUI.new(self)
	add_child(ui)
	compile_now()
	frame_req.emit()
	say(status)
	# --edit-ops=FILE: a script of edits (EdScript), for pictures and tests
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--edit-ops="):
			var ops = JSON.parse_string(FileAccess.get_file_as_string(a.substr(11)))
			if ops is Array:
				for i in 3:
					await get_tree().process_frame
				EdScript.run(self, ops)

func _exit_tree() -> void:
	if _thread != null:
		var res = _thread.wait_to_finish()
		_thread = null
		if res is Dictionary and res.get("geo") != null:
			res.geo.free()
	# work in hand is kept, however the editor is left (the web build's
	# beforeunload)
	if _save_at >= 0:
		autosave()
		_save_at = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not headless and history != null:
		autosave()

# ---------------------------------------------------------------------
# the one way the document changes
# ---------------------------------------------------------------------

func say(msg: String) -> void:
	status = msg
	status_changed.emit(msg)

## Every edit: a snapshot for undo, the change, a tidy (welding what was
## dragged together), and the recompile. `group`: a run of the same nudge
## within a moment is one undo step.
func edit(label: String, fn: Callable, tidy := true, group := "") -> void:
	edit_begin(label, group)
	fn.call(doc)
	edit_end(tidy)

func edit_begin(label: String, group := "") -> Dictionary:
	var now := Time.get_ticks_msec()
	var same: bool = group != "" and _last_edit != null and _last_edit.label == group and now - _last_edit.t < 1200
	if not same:
		history.push(label)
	_last_edit = {"label": group, "t": now} if group != "" else null
	return doc

func edit_end(tidy := true) -> void:
	if tidy:
		var before: int = doc.vertices.size()
		EdDoc.compact(doc)
		if doc.vertices.size() != before and (sel_kind == "vertex" or sel_kind == "line"):
			clear_sel()
	changed()

## The document moved: tell everybody, and recompile a moment later.
func changed(now := false, topology := true) -> void:
	# a drag moves corners and changes no line: the list of them stands
	if topology:
		_lines_cache = null
	if layer() != _last_layer:
		_last_layer = layer()
		_other_key = null
		layer_changed.emit(layer())
	doc_changed.emit()
	var tk := _texture_key(doc)
	if tk != _tex_key:
		_tex_key = tk
		_refresh_textures(true)
	if now or headless:
		compile_now()
	else:
		_compile_at = Time.get_ticks_msec() + 120
	_save_at = Time.get_ticks_msec() + 800

## Every line of the map with the sectors on it, once per change — and
## the linedefs of their own, with no sector either side.
func lines() -> Array:
	if _lines_cache == null:
		var out := EdDoc.lines_of(doc)
		for e in doc.get("linedefs", []):
			out.append({"key": EdDoc.line_key(e[0], e[1]), "a": mini(e[0], e[1]), "b": maxi(e[0], e[1]), "sectors": [], "free": true})
		_lines_cache = out
	return _lines_cache

func line_info(key: String):
	for l in lines():
		if l.key == key:
			return l
	return null

func _texture_key(d: Dictionary) -> String:
	var t: Array = d.get("textures", [])
	if t.is_empty():
		return ""
	var c := []
	for x in t:
		var y: Dictionary = x.duplicate(true)
		for L in y.get("layers", []):
			if L.get("image") is String:
				L["image"] = L.image.length()
		c.append(y)
	return JSON.stringify(c)

## Draw the map's own textures and say which names there are now.
func _refresh_textures(emit := true) -> void:
	# a compile in flight reads the bank's textures: it finishes first
	if _thread != null:
		var res = _thread.wait_to_finish()
		_thread = null
		if res is Dictionary:
			_apply_compile(res)
	var drawn := EdTex.register_all(doc)
	map_texture_names = []
	for t in doc.get("textures", []):
		var n := str(t.get("name", ""))
		if drawn.has(n):
			map_texture_names.append(n)
	texture_names = map_texture_names + game_texture_names
	bank = TexBank.new()
	if emit:
		textures_changed.emit()

## World size of a texture, for alignment and the 3D outlines.
func tex_size(name: String) -> Vector2:
	if name == "" or name == "SKY":
		return Vector2.ZERO
	return bank.size_of(name)

## The compile: in a thread, on a copy, so a big map never stops the
## mouse; the result lands in `compiled` and compiled_ready fires.
func compile_now() -> void:
	if _thread != null:
		var res = _thread.wait_to_finish()
		_thread = null
		if res is Dictionary and res.get("geo") != null:
			res.geo.free()
	_apply_compile(_compile(EdDoc.clone(doc)))

func _start_compile() -> void:
	# A BUILD WITHOUT THREADS (the web page: GitHub Pages cannot send the
	# headers a browser wants before it lends a page threads): here and now
	if not OS.has_feature("threads"):
		var g: bool = view3d != null and view3d.active
		_apply_compile(_compile_geo(EdDoc.clone(doc), bank if g else null))
		return
	if _thread != null:
		_compile_again = true
		return
	_thread = Thread.new()
	# the 3D view's meshes are built in the thread too, when it is showing
	var geo: bool = view3d != null and view3d.active
	_thread.start(_compile_geo.bind(EdDoc.clone(doc), bank if geo else null))

## The compile, and the level's meshes (MapGeo) for the 3D view, off the
## main thread: the servers take calls from any thread.
static func _compile_geo(d: Dictionary, b) -> Dictionary:
	var c := _compile(d)
	if b != null and c.level != null:
		var mg := MapGeo.new(b)
		c["geo"] = mg.build(c.level)
		# the doors, shut (the game's Doors swings them)
		for dr in c.level.doors:
			for nd in mg.door_nodes(c.level, dr):
				if nd != null:
					c.geo.add_child(nd)
		c["sprites"] = EdView3D.sprite_batches(d.things + c.scattered, c.level, 0, d)
	return c

static func _compile(d: Dictionary) -> Dictionary:
	var probs: Array = []
	var cd := d
	if EdDoc.is_layered(d):
		# A MAP IN LAYERS is built whole, every storey (compileLayers):
		# each layer's problems said with its number
		for g in EdDoc.layers_of(d):
			if g.sectors.is_empty() and g.linedefs.is_empty():
				continue
			var gd := d.duplicate()
			for part in EdDoc.LAYER_PARTS:
				gd[part] = g[part]
			gd["layer"] = g.k
			for p in EdDoc.problems_of(gd):
				if p.kind != "map":
					var q: Dictionary = p.duplicate()
					q["layer"] = g.k
					q["msg"] = "layer %d: %s" % [g.k, p.msg]
					probs.append(q)
	else:
		cd = EdDoc.for_compile(d)
		probs = EdDoc.problems_of(cd)
	var lv: Level = null
	lv = DocCompile.compile(cd)
	var seen := {}
	for p in probs:
		seen[p.msg] = true
	for p in DocCompile.problems:
		if not seen.has(p.msg):
			probs.append(p)
			seen[p.msg] = true
	return {"level": lv, "problems": probs, "scattered": DocCompile.last_scattered.duplicate(), "grown": DocCompile.last_grown.duplicate()}

func _apply_compile(c: Dictionary) -> void:
	var old = compiled.get("geo")
	if old != null and is_instance_valid(old) and not old.is_inside_tree():
		old.free()
	compiled = c
	compiled_ready.emit()

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if _thread != null and not _thread.is_alive():
		var res = _thread.wait_to_finish()
		_thread = null
		if res is Dictionary:
			if _compile_again and res.get("geo") != null:
				# already out of date: its meshes go, its level is shown
				res.geo.free()
				res.erase("geo")
			_apply_compile(res)
		if _compile_again:
			_compile_again = false
			_start_compile()
	if _compile_at >= 0 and now >= _compile_at:
		_compile_at = -1
		_start_compile()
	if _save_at >= 0 and now >= _save_at:
		_save_at = -1
		autosave()

# ---------------------------------------------------------------------
# files and prefs
# ---------------------------------------------------------------------

static func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(MAPS)

static func _load_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS):
		return {}
	var f := FileAccess.open(PREFS, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}

func save_prefs() -> void:
	if headless:
		return
	_ensure_dirs()
	var p := _load_prefs()
	p["snap"] = snap
	p["grid"] = grid
	p["tabs"] = "off" if tabs_hidden else "on"
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(p))

static func _read_autosave():
	if not FileAccess.file_exists(AUTOSAVE):
		return null
	var r := EdDoc.parse(FileAccess.get_file_as_string(AUTOSAVE))
	return r.get("doc")

func autosave() -> void:
	if headless:
		return
	_ensure_dirs()
	var f := FileAccess.open(AUTOSAVE, FileAccess.WRITE)
	if f != null:
		f.store_string(EdDoc.to_json(doc))

## A whole new document, as one undoable step.
func replace(d: Dictionary, label := "open") -> void:
	history.push(label)
	history.doc = d
	clear_sel()
	changed(true)
	frame_req.emit()

func undo() -> void:
	var l = history.undo()
	if l != null:
		clear_sel()
		changed(true)
		say("undid %s" % l)

func redo() -> void:
	var l = history.redo()
	if l != null:
		clear_sel()
		changed(true)
		say("redid %s" % l)

func file_new(from_grid := false) -> void:
	replace(EdDoc.grid_doc() if from_grid else EdDoc.new_doc(), "new from grid" if from_grid else "new map")
	reframe()
	say("new map from THE GRID" if from_grid else "new map — drag on the ground to draw a sector (or R), D to draw any shape")

## THE DEMO LEVELS: a new MAZE, THE SPRAWL, a new JESSE, THE GRID, and
## THE ANNEXE (a map in two storeys: godot/scripts/maps/layers.gd).
func file_demo(which := "maze") -> void:
	var seed := MazeMap.new_seed()
	var d: Dictionary
	match which:
		"sprawl": d = SprawlMap.build()
		"jesse": d = JesseMap.build(seed)
		"grid": d = EdDoc.grid_doc()
		"layers": d = LayersMap.build()
		_: d = MazeMap.build(seed)
	d = EdDoc.normalise(EdDoc.clone(d))
	d.erase("jesse")
	replace(d, "open demo")
	reframe()
	match which:
		"sprawl": say("opened the demo level, THE SPRAWL")
		"jesse": say("opened a new JESSE, the PvP maze (seed %d)" % seed)
		"grid": say("opened THE GRID")
		"layers": say("opened THE ANNEXE, a map in two storeys — Alt+PgUp for the upstairs")
		_: say("opened a new maze (seed %d)" % seed)

func reframe() -> void:
	frame_req.emit()
	if view3d != null:
		view3d.to_start()

func file_name_for() -> String:
	var n := str(doc.get("name", "map")).to_lower()
	var out := ""
	var dash := false
	for c in n:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			dash = false
		elif not dash:
			out += "-"
			dash = true
	out = out.strip_edges().trim_prefix("-").trim_suffix("-")
	return (out if out != "" else "map") + ".gssmap.json"

## Save to a path (user:// or anywhere the desktop allows).
func save_to(p: String) -> bool:
	var dir := p.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		say("could not save %s: %s" % [p, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(EdDoc.to_json(doc))
	f.close()
	history.mark_saved()
	say("saved %s" % p)
	return true

func open_from(p: String) -> bool:
	if not FileAccess.file_exists(p):
		say("no file %s" % p)
		return false
	var r := EdDoc.parse(FileAccess.get_file_as_string(p))
	if r.has("error"):
		say("could not open %s: %s" % [p.get_file(), r.error])
		return false
	replace(r.doc, "open")
	reframe()
	history.mark_saved()
	say("opened %s" % p.get_file())
	return true

## Quick save into the editor's own folder (Ctrl+S).
func file_save() -> void:
	_ensure_dirs()
	save_to(MAPS + file_name_for())

## TEST THE MAP: hand it to the game and go.
func play() -> void:
	autosave()
	play_doc = EdDoc.clone(doc)
	_play_from_here(play_doc)
	play_requested.emit(play_doc)

## PLAY FROM HERE, at the user's request: with the 3D view on screen,
## the game starts where its camera stands, looking the way it looks,
## on the layer being edited — in the copy handed over, so the map's
## own START is untouched. With the camera over no sector (or only the
## plan on screen), the START as drawn.
func _play_from_here(d: Dictionary) -> void:
	if view3d == null or view3d.cam == null or layout == "only2d":
		return
	var c = view3d.cam
	if sector_at(c.x, c.y) == null:
		return
	var start = null
	for t in d.things:
		if t.type == "START":
			start = t
			break
	if start == null:
		start = {"id": EdDoc.take_id(d), "type": "START", "x": 0.0, "y": 0.0, "angle": 0.0}
		d.things.append(start)
	start.x = c.x
	start.y = c.y
	start.angle = c.yaw
	start["pitch"] = c.pitch
	if layer() != 0:
		start["layer"] = layer()
	else:
		start.erase("layer")
	say("playing from here")

# ---------------------------------------------------------------------
# selection
# ---------------------------------------------------------------------

func select(kind: String, ids: Array, add := false) -> void:
	sel_face = null
	if not add or sel_kind != kind:
		sel_kind = kind
		sel_ids = {}
	for id in ids:
		if add and sel_ids.has(id):
			sel_ids.erase(id)
		else:
			sel_ids[id] = true
	if sel_ids.is_empty():
		sel_kind = ""
	if kind != "surface":
		surf = null
	sel_changed.emit()

func clear_sel() -> void:
	sel_face = null
	sel_kind = ""
	sel_ids = {}
	surf = null
	sel_changed.emit()

func is_sel(kind: String, id) -> bool:
	return sel_kind == kind and sel_ids.has(id)

## The 3D view's selection: a floor or a ceiling, or a wall.
func select_surface(s) -> void:
	sel_face = null
	surf = s
	if s != null:
		if s.part == "wall":
			sel_kind = "line"
			sel_ids = {s.line: true}
		else:
			sel_kind = "sector"
			sel_ids = {}
			if s.sector >= 0 and s.sector < doc.sectors.size():
				sel_ids[doc.sectors[s.sector].id] = true
	else:
		sel_kind = ""
		sel_ids = {}
	sel_changed.emit()

# --- DOORS (the Godot build's own; Level.Door, game/doors.gd) ------------

## THE DOOR TOOL's door: what a click in Doors mode (O) puts in a wall —
## `w` wide, the rest the line override's `door` (DocCompile.DOOR_DEFAULT)
var door_preset := {"w": 64, "h": 96, "tex": "DOOR0001", "style": "swing", "auto": true}

## A DOOR IN A WALL at `at` along line `key`: the line cut to a piece the
## preset's width round the click (its edges on the grid, with snap on,
## and never nearer a corner than 8), that piece an opening with a door
## in it — a building's outside wall gets a passage through it too. One
## undo step. A line no longer than the door is the door. Returns the
## door's line, "" if it cannot go there.
func place_door(key: String, at: Vector2) -> String:
	var info = line_info(key)
	if info == null or info.get("free", false) or info.sectors.is_empty():
		say("a door goes in a line of a sector — not a linedef on its own")
		return ""
	var o0 = doc.lines.get(key)
	if o0 is Dictionary and o0.get("door") is Dictionary:
		select("line", [key])
		say("a door already — its settings are in the inspector")
		return key
	var A: Vector2 = doc.vertices[info.a]
	var B: Vector2 = doc.vertices[info.b]
	var L := A.distance_to(B)
	var w := maxf(16.0, float(door_preset.get("w", 64)))
	var d := edit_begin("door")
	var k2 := key
	if L > w + 16.0:
		var u := (B - A) / L
		var t := clampf((at - A).dot(u), w / 2.0 + 8.0, L - w / 2.0 - 8.0)
		if snap and grid > 0:
			t = clampf(snappedf(t - w / 2.0, float(grid)) + w / 2.0, w / 2.0 + 8.0, L - w / 2.0 - 8.0)
		var p1 := A + u * (t - w / 2.0)
		var p2 := A + u * (t + w / 2.0)
		var i1 := EdOps.vertex_for(d, p1.x, p1.y)
		EdOps.split_lines_at(d, i1)
		var i2 := EdOps.vertex_for(d, p2.x, p2.y)
		EdOps.split_lines_at(d, i2)
		k2 = EdDoc.line_key(i1, i2)
	var o: Dictionary = d.lines.get(k2, {}).duplicate(true) if d.lines.get(k2) is Dictionary else {}
	o["opening"] = true
	var dp := door_preset.duplicate()
	dp.erase("w")
	o["door"] = dp
	o["__new"] = true
	d.lines[k2] = o
	edit_end(true)
	# (the tidy may number the corners afresh: find it again)
	for k in doc.lines:
		if doc.lines[k] is Dictionary and doc.lines[k].has("__new"):
			doc.lines[k].erase("__new")
			k2 = k
			break
	select("line", [k2])
	say("a door, %d wide — click another wall for another; Ctrl+Z takes it back" % roundi(minf(w, L)))
	return k2

## The door out of line `key` (it stays an opening).
func remove_door(key: String) -> void:
	var o = doc.lines.get(key)
	if not (o is Dictionary and o.get("door") is Dictionary):
		return
	var d := edit_begin("no door")
	d.lines[key].erase("door")
	edit_end(false)
	say("no door on line %s — still a way through" % key)

## LOOP SELECT: every wall of a sector — each line of its outline, and of
## the rooms drawn inside it — its side facing that sector. What is
## painted on the selection then goes on that side of each of them
## (loop_texture). `add` adds the loop to the lines already picked (and
## the walls face no one sector unless it is the same one).
func loop_select(si: int, add := false) -> int:
	if si < 0 or si >= doc.sectors.size():
		return 0
	var face = doc.sectors[si].id
	var keys := []
	for l in lines():
		if l.sectors.has(si):
			keys.append(l.key)
	var was = sel_face if add and sel_kind == "line" else face
	var ids := sel_ids.duplicate() if add and sel_kind == "line" else {}
	for k in keys:
		ids[k] = true
	surf = null
	sel_kind = "line" if not ids.is_empty() else ""
	sel_ids = ids
	sel_face = face if was == face else null
	if mode != "lines" and MODES.has("lines") and mode != "draw":
		set_mode("lines")
	sel_changed.emit()
	var nm := str(doc.sectors[si].get("name", ""))
	say("%d walls of sector %s%s — pick a texture to put it on all of them" % [keys.size(), str(face), (" (%s)" % nm) if nm != "" else ""])
	return keys.size()

## The sector (its index) whose side of line `key` the point p is on —
## the one side of a one-sided line; -1 off any sector.
func side_of(key: String, p: Vector2) -> int:
	var info = line_info(key)
	if info == null or info.sectors.is_empty():
		return -1
	if info.sectors.size() == 1:
		return info.sectors[0]
	var a: Vector2 = doc.vertices[info.a]
	var b: Vector2 = doc.vertices[info.b]
	var n := (b - a).orthogonal().normalized()
	var mid := a.lerp(b, clampf((p - a).dot(b - a) / maxf(1e-6, (b - a).length_squared()), 0.02, 0.98))
	var sgn := signf((p - a).dot(n))
	if sgn == 0.0:
		sgn = 1.0
	for step in [2.0, 8.0, 32.0]:
		var q: Vector2 = mid + n * sgn * step
		for si in info.sectors:
			if U.point_in_poly(PackedVector2Array(doc.sectors[si].verts.map(func(v): return doc.vertices[int(v)])), q.x, q.y) \
					and not _in_hole_of(si, q):
				return si
	return info.sectors[0]

func _in_hole_of(si: int, q: Vector2) -> bool:
	var s = sector_at(q.x, q.y)
	return s != null and s.id != doc.sectors[si].id

## A texture onto every wall of a loop, on the side facing sel_face
## (null clears it): the "skin" — every piece of wall on that face, a
## one-sided wall or the step and lintel of an opening — or the "mid",
## what stands in a two-sided opening (a fence, a window). (The older
## parts, "walls", "upper", "lower" and "all", are the skin.)
func loop_texture(part: String, name) -> void:
	if sel_kind != "line" or sel_face == null:
		return
	var face := str(sel_face)
	var info := {}
	for l in lines():
		if sel_ids.has(l.key):
			info[l.key] = l
	var d := edit_begin("walls %s %s" % [part, name if name != null else "cleared"])
	for k in sel_ids:
		var two: bool = info.has(k) and info[k].sectors.size() > 1
		var fields := []
		match part:
			"mid": fields = ["midTex"] if two else []
			_: fields = ["tex"]
		if fields.is_empty():
			continue
		if not d.lines.has(k):
			d.lines[k] = {}
		var o: Dictionary = d.lines[k]
		if not o.get("sides") is Dictionary:
			o["sides"] = {}
		if not o.sides.get(face) is Dictionary:
			o.sides[face] = {}
		for f in fields:
			if name != null:
				o.sides[face][f] = name
			else:
				o.sides[face].erase(f)
		if o.sides[face].is_empty():
			o.sides.erase(face)
		if o.sides.is_empty():
			o.erase("sides")
		if o.is_empty():
			d.lines.erase(k)
	edit_end(false)

## What the loop's walls wear for a part, if they all wear the same
## (null: none set on any), else "(mixed)".
func loop_tex_of(part: String):
	var face := str(sel_face)
	var seen := {}
	for l in lines():
		if not sel_ids.has(l.key):
			continue
		var two: bool = l.sectors.size() > 1
		var f := "midTex" if part == "mid" else "tex"
		if part == "mid" and not two:
			continue
		var o: Dictionary = doc.lines.get(l.key, {})
		var sd = o.get("sides", {}).get(face) if o.get("sides") is Dictionary else null
		var v = sd.get(f) if sd is Dictionary and sd.get(f) != null else o.get(f)
		seen[str(v) if v != null else ""] = true
	if seen.size() > 1:
		return "(mixed)"
	var only = seen.keys()[0] if seen.size() == 1 else ""
	return only if only != "" else null

func set_mode(m: String) -> void:
	if not MODES.has(m):
		return
	if m == "draw" and mode != "draw":
		mode_before_draw = mode
	mode = m
	var keep: String = MODE_KIND.get(m, "")
	if m != "draw":
		cancel_path()
	if keep != "" and sel_kind != "" and sel_kind != keep:
		clear_sel()
	mode_changed.emit(m)
	say("%s mode" % MODES[m].name)

func set_grid(g: int) -> void:
	if g < 1:
		return
	grid = mini(GRID_MAX, g)
	save_prefs()
	grid_changed.emit()
	say("grid %d%s" % [grid, "" if snap else " (snap is off: G)"])

func grid_step(dir: int) -> void:
	var g := grid
	var nxt := -1
	if dir > 0:
		for x in GRIDS:
			if x > g:
				nxt = x
				break
	else:
		for i in range(GRIDS.size() - 1, -1, -1):
			if GRIDS[i] < g:
				nxt = GRIDS[i]
				break
	if nxt > 0:
		set_grid(nxt)
	else:
		say("grid %d is the %s there is" % [g, "largest" if dir > 0 else "smallest"])

func snap_v(v: float) -> float:
	return EdDoc.jsround(v / grid) * grid if snap else EdDoc.jsround(v)

func snap_pt(p: Vector2) -> Vector2:
	return Vector2(snap_v(p.x), snap_v(p.y))

func set_snap(on = null) -> void:
	snap = (not snap) if on == null else bool(on)
	save_prefs()
	grid_changed.emit()
	say("snap %s%s" % ["on" if snap else "off", (" — grid %d" % grid) if snap else " — free placement, whole units"])

## A height moved by dz: with snap on it lands on a multiple of the step.
func snap_z(z: float, dz: float) -> float:
	var v := z + dz
	var q := absf(dz)
	return EdDoc.jsround(v / q) * q if snap and q > 1 else v

## WHERE A POINT GOES, Doom Builder's way: onto a vertex within r; else
## onto a line within r (where it crosses the grid, with snap on, or
## its nearest point); else onto the grid. {pt, kind, id}.
func snap_at(x: float, y: float, r: float, exclude = null, use_lines := true, use_vertices := true) -> Dictionary:
	var d := doc
	var p := Vector2(x, y)
	if use_vertices and r > 0:
		var best := -1
		var bd := r * r
		for i in d.vertices.size():
			if exclude != null and exclude.has(i):
				continue
			var q: float = (d.vertices[i] - p).length_squared()
			if q < bd:
				bd = q
				best = i
		if best >= 0:
			return {"pt": d.vertices[best], "kind": "vertex", "id": best}
		var ghost = null
		for g in other_layers():
			for v in g.vertices:
				var q: float = (v - p).length_squared()
				if q < bd:
					bd = q
					ghost = v
		if ghost != null:
			return {"pt": ghost, "kind": "vertex", "id": null}
	if use_lines and r > 0:
		var best = null
		var bd := r
		for l in lines():
			if exclude != null and (exclude.has(l.a) or exclude.has(l.b)):
				continue
			var a: Vector2 = d.vertices[l.a]
			var b: Vector2 = d.vertices[l.b]
			var st := EdDoc.seg_dist(a, b, p)
			if st.x < bd and st.y > 0 and st.y < 1:
				bd = st.x
				best = {"l": l, "a": a, "b": b}
		if best != null:
			var a: Vector2 = best.a
			var b: Vector2 = best.b
			var on := []
			if snap:
				var g := float(grid)
				var e := b - a
				var xs := []
				var ys := []
				if absf(e.x) > 1e-9:
					for k in range(floori((x - r) / g), ceili((x + r) / g) + 1):
						var v := k * g
						if v >= minf(a.x, b.x) - 1e-9 and v <= maxf(a.x, b.x) + 1e-9:
							xs.append(v)
				if absf(e.y) > 1e-9:
					for k in range(floori((y - r) / g), ceili((y + r) / g) + 1):
						var v := k * g
						if v >= minf(a.y, b.y) - 1e-9 and v <= maxf(a.y, b.y) + 1e-9:
							ys.append(v)
				for gx in xs:
					var t: float = (gx - a.x) / e.x
					if t > 1e-9 and t < 1 - 1e-9:
						on.append(Vector2(gx, a.y + e.y * t))
				for gy in ys:
					var t: float = (gy - a.y) / e.y
					if t > 1e-9 and t < 1 - 1e-9:
						on.append(Vector2(a.x + e.x * t, gy))
			var pick = null
			var pd := r
			for q in on:
				var dq: float = q.distance_to(p)
				if dq < pd:
					pd = dq
					pick = q
			if pick == null:
				var e := b - a
				var t := clampf((p - a).dot(e) / e.length_squared(), 0.0, 1.0)
				pick = a + e * t
			return {"pt": Vector2(_tidy(pick.x), _tidy(pick.y)), "kind": "line", "id": best.l.key}
	return {"pt": Vector2(snap_v(x), snap_v(y)), "kind": "grid", "id": null}

static func _tidy(v: float) -> float:
	return EdDoc.jsround(v) if absf(v - EdDoc.jsround(v)) < 1e-6 else EdOps._fix3(v)

## The vertices the selection would move.
func moving_verts() -> Dictionary:
	var out := {}
	if sel_kind == "vertex":
		for i in sel_ids:
			out[int(i)] = true
	elif sel_kind == "line":
		for k in sel_ids:
			var ab := EdDoc.key_verts(k)
			out[ab.x] = true
			out[ab.y] = true
	elif sel_kind == "sector":
		for s in doc.sectors:
			if sel_ids.has(s.id):
				for v in s.verts:
					out[v] = true
	return out

## SNAP THE SELECTION TO THE GRID (Shift+G).
func snap_sel_to_grid() -> void:
	if sel_kind == "" or sel_ids.is_empty():
		say("select something to snap to the grid")
		return
	var g := float(grid)
	var r := func(v: float) -> float: return EdDoc.jsround(v / g) * g
	var verts := moving_verts()
	var kind := sel_kind
	var ids := sel_ids
	var d := edit_begin("snap to grid %d" % grid)
	for i in verts:
		if i >= 0 and i < d.vertices.size():
			d.vertices[i] = Vector2(r.call(d.vertices[i].x), r.call(d.vertices[i].y))
	if kind == "thing":
		for t in d.things:
			if ids.has(t.id):
				t.x = r.call(t.x)
				t.y = r.call(t.y)
	if kind == "prop":
		for p in d.props:
			if ids.has(p.id):
				p.x0 = r.call(p.x0); p.y0 = r.call(p.y0); p.x1 = r.call(p.x1); p.y1 = r.call(p.y1)
	edit_end(true)
	if not verts.is_empty():
		clear_sel()
	say("snapped to grid %d" % grid)

func set_layout(l: String) -> void:
	layout = l
	layout_changed.emit(l)

# ---------------------------------------------------------------------
# THE EDITS a person makes most
# ---------------------------------------------------------------------

func delete_sel() -> void:
	var kind := sel_kind
	var ids := sel_ids
	if kind == "" or ids.is_empty():
		return
	var n := ids.size()
	var d := edit_begin("delete %d %s%s" % [n, kind, "s" if n > 1 else ""])
	if kind == "sector":
		d.sectors = d.sectors.filter(func(s): return not ids.has(s.id))
	if kind == "thing":
		d.things = d.things.filter(func(t): return not ids.has(t.id))
	if kind == "prop":
		d.props = d.props.filter(func(p): return not ids.has(p.id))
	if kind == "scatter":
		d.scatters = d.scatters.filter(func(p): return not ids.has(p.id))
	if kind == "vertex":
		for s in d.sectors:
			s.verts = s.verts.filter(func(v): return not ids.has(v))
	if kind == "line":
		var own := {}
		for e in d.linedefs:
			own[EdDoc.line_key(e[0], e[1])] = true
		d.linedefs = d.linedefs.filter(func(e): return not ids.has(EdDoc.line_key(e[0], e[1])))
		for key in ids:
			if not own.has(key):
				EdOps.merge_across(d, key)
	edit_end(true)
	clear_sel()

func move_sel(dx: float, dy: float, label := "move") -> void:
	if sel_kind == "" or (dx == 0 and dy == 0):
		return
	var kind := sel_kind
	var ids := sel_ids
	edit(label, func(d): EdOps.move_things(d, kind, ids, dx, dy))

# --- LAYERS -------------------------------------------------------------

func layer() -> int:
	return int(doc.get("layer", 0))

## The layers not being edited, with something on them, bottom-up.
func other_layers() -> Array:
	if _other_key != doc:
		_other_cache = []
		for g in EdDoc.layers_of(doc):
			if g.k != layer() and not g.sectors.is_empty():
				_other_cache.append(g)
		_other_key = doc
	return _other_cache

func set_layer(k: int) -> void:
	k = clampi(k, EdDoc.LAYER_MIN, EdDoc.LAYER_MAX)
	if k == layer():
		return
	cancel_path()
	clear_sel()
	history.push("layer %d" % k)
	EdDoc.set_layer(doc, k)
	_other_key = null
	changed(true)
	var g := EdDoc.layer_geom(doc, k)
	var n: int = g.sectors.size()
	say("layer %d%s — %s; Alt+PgUp / Alt+PgDn change layer" % [k, " (the ground)" if k == 0 else "",
		("%d sector%s" % [n, "" if n == 1 else "s"]) if n > 0 else "empty: draw on it, and rooms stand on the layer under"])

func layer_floor(x: float, y: float) -> float:
	var s = sector_at(x, y)
	if s != null:
		return EdDoc.num(s.get("floor"), 0)
	var b = EdDoc.layer_base(doc, layer(), x, y)
	return EdDoc.num(b.floor, 0) if b != null else 0.0

func on_layer(t: Dictionary) -> bool:
	return int(EdDoc.num(t.get("layer"), 0)) == layer()

# --- STEPS --------------------------------------------------------------

func make_steps(kind: String, opts := {}) -> Array:
	var ids := target_or("sector")
	if ids.is_empty():
		say("select a sector to make steps in")
		return []
	var made := []
	var errs := []
	var res := {}
	var d := edit_begin("rings" if kind == "rings" else "stairs")
	for id in ids:
		var S = null
		for x in d.sectors:
			if x.id == id:
				S = x
				break
		if S == null:
			continue
		res = EdSteps.make_rings(d, S, opts) if kind == "rings" else EdSteps.make_stairs(d, S, opts)
		if res.has("error"):
			errs.append(res.error)
		made.append_array(res.get("ids", []))
	edit_end(true)
	if not made.is_empty():
		select("sector", made)
	if not errs.is_empty() and made.is_empty():
		say(errs[0])
	else:
		var rise := ""
		if res.get("rise") != null:
			rise = ", each %s high" % _nice(absf(snappedf(res.rise, 0.1)))
		say("%d %s%s%s" % [made.size(), "rings" if kind == "rings" else "steps", rise, (" — " + errs[0]) if not errs.is_empty() else ""])
	return made

static func _nice(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(snappedf(v, 0.001))

# --- THINGS, PROPS -----------------------------------------------------

func add_thing(x: float, y: float) -> void:
	var type := thing_type
	var d := edit_begin("add %s" % type)
	if EdDoc.THING_TYPES.get(type, {}).get("one", false):
		d.things = d.things.filter(func(t): return t.type != type)
	var t := {"id": EdDoc.take_id(d), "type": type, "x": snap_v(x), "y": snap_v(y), "angle": PI / 2.0}
	if layer() != 0:
		t["layer"] = layer()
	if type == "PLANT":
		t["kind"] = plant_kind
	d.things.append(t)
	edit_end(true)
	select("thing", [t.id])

func add_prop(x0: float, y0: float, x1: float, y1: float) -> void:
	if absf(x1 - x0) < 1 or absf(y1 - y0) < 1:
		return
	var under = sector_at((x0 + x1) / 2.0, (y0 + y1) / 2.0)
	var z0 := EdDoc.num(under.get("floor"), 0) if under != null else 0.0
	var d := edit_begin("add prop")
	var p := {"id": EdDoc.take_id(d), "x0": minf(x0, x1), "y0": minf(y0, y1), "x1": maxf(x0, x1), "y1": maxf(y0, y1),
		"z0": z0, "z1": z0 + 64, "tex": prop_tex}
	d.props.append(p)
	edit_end(true)
	select("prop", [p.id])

## The smallest document sector under a point, or null.
func sector_at(x: float, y: float):
	return EdOps.sector_containing(doc, x, y)

func sector_by_id(id):
	for s in doc.sectors:
		if s.id == id:
			return s
	return null

func sector_index(id) -> int:
	for i in doc.sectors.size():
		if doc.sectors[i].id == id:
			return i
	return -1

# --- SECTORS ---------------------------------------------------------

## A NEW SECTOR from points, Doom Builder's draw: corners on vertices use
## them, corners on lines split them; drawn inside another it takes that
## one's heights and textures.
func add_sector(points: PackedVector2Array, label := "draw sector"):
	if points.size() < 3:
		return null
	if EdOps.crosses_lines(doc, points):
		return add_sector_across(points, label)
	var d := edit_begin(label)
	var idx := []
	for p in points:
		idx.append(EdOps.vertex_for(d, p.x, p.y))
	var made = EdOps.insert_sector(d, idx)
	edit_end(true)
	if made != null:
		select("sector", [made.id])
	return made

## LINEDEFS OF THEIR OWN: a path finished open that splits no sector.
func add_linedefs(points: PackedVector2Array) -> Array:
	if points.size() < 2:
		return []
	var n := 0
	var d := edit_begin("draw linedefs")
	var pts := EdOps.with_crossings(d, points, false)
	var idx := []
	for p in pts:
		idx.append(EdOps.vertex_for(d, p.x, p.y))
	for k in idx.size() - 1:
		var a: int = idx[k]
		var b: int = idx[k + 1]
		if a == b:
			continue
		d.linedefs.append([a, b])
		n += 1
	var made := EdOps.close_loops(d)
	edit_end(true)
	if not made.is_empty():
		select("sector", made)
		say("%d sector%s closed by the new line%s" % [made.size(), "s" if made.size() > 1 else "", "s" if n > 1 else ""])
	else:
		var ks := []
		var L: Array = doc.linedefs
		for i in range(maxi(0, L.size() - n), L.size()):
			ks.append(EdDoc.line_key(L[i][0], L[i][1]))
		select("line", ks)
		say("%d linedef%s — close a shape with more and it becomes a sector; left open, it stands as a wall" % [n, "s" if n > 1 else ""])
	return made

## A SECTOR DRAWN ACROSS WALLS: cut where it crosses every line, and each
## room it passes through split along the part inside it.
func add_sector_across(points: PackedVector2Array, label: String):
	var made := []
	var outside := false
	var d := edit_begin(label)
	# 1. the outline, with a corner wherever it crosses a line
	var segs := []
	for l in EdDoc.lines_of(d):
		segs.append([d.vertices[l.a], d.vertices[l.b]])
	var pts := PackedVector2Array()
	for k in points.size():
		var p := points[k]
		var q := points[(k + 1) % points.size()]
		pts.append(p)
		for h in EdOps._hits(p, q, segs):
			pts.append(Vector2(h[1], h[2]))
	# 2. every corner a vertex, splitting what it lands on
	var ring0 := []
	for p in pts:
		ring0.append(EdOps.vertex_for(d, p.x, p.y))
	var ring := []
	for k in ring0.size():
		if ring0[k] != ring0[(k + 1) % ring0.size()]:
			ring.append(ring0[k])
	if ring.size() >= 3:
		if EdDoc.signed_area(EdOps._pts_of(d, ring)) < 0:
			ring.reverse()
		# 3. the runs of the outline inside one sector, edge to edge
		var in_sector := func(i: int, j: int):
			var a: Vector2 = d.vertices[i]
			var b: Vector2 = d.vertices[j]
			var s = EdOps.sector_containing(d, (a.x + b.x) / 2.0, (a.y + b.y) / 2.0)
			if s == null:
				return null
			var r: Array = s.verts
			for k in r.size():
				if (r[k] == i and r[(k + 1) % r.size()] == j) or (r[k] == j and r[(k + 1) % r.size()] == i):
					return "edge"
			return s
		var n := ring.size()
		var owner := []
		for k in n:
			owner.append(in_sector.call(ring[k], ring[(k + 1) % n]))
		var same := func(a, b) -> bool:
			if a == null or b == null:
				return a == null and b == null
			if a is String or b is String:
				return a is String and b is String
			return is_same(a, b)
		var k0 := -1
		for k in n:
			if not same.call(owner[k], owner[(k - 1 + n) % n]):
				k0 = k
				break
		if k0 < 0:
			k0 = 0
		var runs := []
		var c := 0
		var k := k0
		while c < n:
			var s = owner[k]
			var run := [ring[k]]
			var m := k
			while true:
				run.append(ring[(m + 1) % n])
				m = (m + 1) % n
				c += 1
				if not (c < n and same.call(owner[m], s) and not (s is Dictionary and s.verts.has(ring[m]))):
					break
			if s is Dictionary:
				runs.append({"id": s.id, "path": run})
			elif s == null:
				outside = true
			k = m
		for rn in runs:
			var S = null
			for x in d.sectors:
				if x.id == rn.id:
					S = x
					break
			if S == null:
				continue
			var pth: Array = rn.path
			var u: int = pth[0]
			var w: int = pth[pth.size() - 1]
			if S.verts.has(u) and S.verts.has(w):
				EdOps.split_sector(d, S, pth)
				continue
			# the run ends on the wall of a room INSIDE S: the piece is the
			# run and the shorter stretch of that room's wall
			var H = null
			for x in d.sectors:
				if not is_same(x, S) and x.verts.has(u) and x.verts.has(w):
					H = x
					break
			if H == null:
				continue
			var r: Array = H.verts
			var i := r.find(u)
			var j := r.find(w)
			var cands := []
			for dir in [1, -1]:
				var arc := []
				var q := j
				while true:
					arc.append(r[q])
					if q == i:
						break
					q = (q + dir + r.size()) % r.size()
				var cand: Array = pth + arc.slice(1, arc.size() - 1)
				if cand.size() >= 3 and not EdDoc.self_crosses(EdOps._pts_of(d, cand)):
					cands.append(cand)
			if cands.is_empty():
				continue
			cands.sort_custom(func(a, b): return EdOps._area_of(d, a) < EdOps._area_of(d, b))
			var ns := EdDoc.copy_without(S, ["verts", "id"])
			ns["name"] = ""
			ns["id"] = EdDoc.take_id(d)
			ns["verts"] = cands[0]
			d.sectors.append(ns)
		# 4. the pieces inside the drawn shape are the new sectors
		var shape_pts := EdOps._pts_of(d, ring)
		for s in d.sectors:
			var r := EdDoc.ring_of(d, s)
			var cc := Vector2.ZERO
			for p in r:
				cc += p / r.size()
			if not EdDoc.pip(shape_pts, cc.x, cc.y):
				continue
			var all_in := true
			for p in r:
				if not (EdDoc.pip(shape_pts, p.x, p.y) or EdOps.seg_dist_ring(shape_pts, p) < 1):
					all_in = false
					break
			if all_in:
				made.append(s.id)
	edit_end(true)
	if not made.is_empty():
		select("sector", made)
	say("%d sector%s drawn across the walls%s" % [made.size(), "" if made.size() == 1 else "s",
		" — the part outside the map was not made; draw it on its own" if outside else ""])
	return sector_by_id(made[0]) if not made.is_empty() else null

## Raise or lower floors or ceilings by dz — the wheel in 3D, PgUp/PgDn.
func nudge_height(part: String, dz: float, ids = null) -> void:
	var which: Dictionary = ids if ids != null else (sel_ids if sel_kind == "sector" else {})
	if which.is_empty():
		return
	var keys := which.keys()
	keys.sort()
	var d := edit_begin("%s %s%s" % [part, "+" if dz > 0 else "", _nice(dz)], "height %s %s" % [part, ",".join(keys.map(func(x): return str(x)))])
	for s in d.sectors:
		if not which.has(s.id):
			continue
		if part == "floor":
			s["floor"] = snap_z(EdDoc.num(s.get("floor"), 0), dz)
		else:
			s["ceil"] = snap_z(EdDoc.num(s.get("ceil"), 256), dz)
	edit_end(false)

## LINE THE TEXTURES UP on the selected lines (or the one under the mouse).
func align_sel(how: String, opts := {}) -> int:
	var keys := []
	if sel_kind == "line":
		keys = sel_ids.keys()
	elif hovered != null and hovered.kind == "line":
		keys = [hovered.id]
	if keys.is_empty():
		say("select some lines first (L, then click or box them)")
		return 0
	var labels := {"x": "align x", "y": "align y", "match": "match textures", "fitX": "fit across", "fitY": "fit up", "scale": "texture scale", "reset": "reset alignment"}
	var label: String = labels.get(how, how)
	var d := edit_begin(label)
	var n := EdDoc.align_textures(d, keys, how, tex_size, opts)
	edit_end(false)
	if n > 0:
		say("%s: %d wall face%s on %d line%s" % [label, n, "" if n == 1 else "s", keys.size(), "" if keys.size() == 1 else "s"])
	else:
		say("those lines have no walls to align (a linedef of its own is a wall sector: align it by its own lines)")
	return n

## A sector's brightness, Doom's way: 0 to 255.
static func bright_of(s: Dictionary) -> int:
	return int(EdDoc.jsround(clampf(EdDoc.num(s.get("light"), 0.72), 0.0, 1.0) * 255.0))

static func is_inside(s: Dictionary) -> bool:
	return EdDoc.tex(s, "ceilTex") != "" and EdDoc.tex(s, "ceilTex") != "SKY"

## BRIGHTNESS, Ctrl and the wheel, as in Ultimate Doom Builder.
func nudge_light(delta: int, ids = null) -> void:
	var which: Dictionary = ids if ids != null else (sel_ids if sel_kind == "sector" else {})
	if which.is_empty():
		return
	var moves := false
	for s in doc.sectors:
		if which.has(s.id) and clampi(bright_of(s) + delta, 0, 255) != bright_of(s):
			moves = true
	if not moves:
		say("brightness %d is as far as it goes" % (255 if delta > 0 else 0))
		return
	var keys := which.keys()
	keys.sort()
	var now := 0
	var d := edit_begin("brightness %s%d" % ["+" if delta > 0 else "", delta], "light %s" % ",".join(keys.map(func(x): return str(x))))
	for s in d.sectors:
		if not which.has(s.id):
			continue
		var b := clampi(bright_of(s) + delta, 0, 255)
		s["light"] = snappedf(b / 255.0, 0.0001)
		now = b
	edit_end(false)
	say("brightness %d" % now)

## INSIDE OR OUTSIDE: a room with a roof, or open to the sky.
func set_inside(inside: bool, ids = null) -> void:
	var which: Dictionary = ids if ids != null else (sel_ids if sel_kind == "sector" else {})
	if which.is_empty():
		return
	var d := edit_begin("inside" if inside else "outside")
	for s in d.sectors:
		if not which.has(s.id):
			continue
		var f := EdDoc.num(s.get("floor"), 0)
		if inside:
			if EdDoc.tex(s, "ceilTex") == "SKY" or EdDoc.tex(s, "ceilTex") == "":
				var roof := EdDoc.tex(s, "roofTex")
				s["ceilTex"] = roof if roof != "" and roof != "SKY" else "GRIDBOX"
			if EdDoc.num(s.get("ceil"), 1024) - f > 512:
				s["ceil"] = f + 128
			s["outdoor"] = false
		else:
			s["ceilTex"] = "SKY"
			s["outdoor"] = true
			if EdDoc.num(s.get("ceil"), 0) < f + 128:
				s["ceil"] = f + 128
	edit_end(false)
	say("inside: roofed, walled where it meets the outside" if inside else "outside: open to the sky")

## INSERT, as in Doom Builder.
func insert_at_cursor() -> void:
	var c = cursor
	if c == null:
		return
	if mode == "vertices" and path.is_empty():
		var d := edit_begin("insert vertex")
		EdOps.vertex_for(d, c.x, c.y)
		edit_end(true)
		say("vertex at %s, %s" % [_nice(c.x), _nice(c.y)])
	elif mode == "draw":
		add_path_point(c)
	elif mode == "sectors" or mode == "lines":
		set_mode("draw")
		add_path_point(c)
		say("drawing: click the corners, click the first one (or Enter) to finish, Esc to cancel")
	else:
		add_thing(c.x, c.y)

## THE GROUND: the only sector, or the outermost with rooms in it.
func is_ground(id) -> bool:
	var i := sector_index(id)
	if i < 0:
		return false
	if doc.sectors.size() == 1:
		return true
	var par := EdDoc.hole_parents(doc)
	return par[i] == -1 and par.has(i)

## A shape dragged out, from corner a to corner b, as a new sector.
func add_rect(a: Vector2, b: Vector2):
	if a.x == b.x or a.y == b.y:
		say("too small for the %d grid: drag further, or make the grid finer with [" % grid)
		return null
	var kind := shape if EdOps.SHAPES.has(shape) else "rect"
	var pts := shape_points(a, b)
	if pts.size() < 3 or absf(EdDoc.signed_area(pts)) < 1:
		say("too small for that shape: drag further")
		return null
	var nm: String = EdOps.SHAPES[kind].name
	var s = add_sector(pts, "draw %s" % nm.to_lower())
	var bb := EdDoc.bbox(pts)
	if s != null:
		say("new sector %d, %s%s by %s" % [s.id, "" if kind == "rect" else nm.to_lower() + " ", _nice(bb.size.x), _nice(bb.size.y)])
	return s

func shape_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var kind := shape if EdOps.SHAPES.has(shape) else "rect"
	return EdOps.shape_points(kind, a, b, shape_sides if shape_sides != null else EdOps.SHAPES[kind].get("sides"))

func set_shape(kind: String, sides = null) -> void:
	if not EdOps.SHAPES.has(kind):
		return
	shape = kind
	shape_sides = sides if sides != null else EdOps.SHAPES[kind].get("sides")
	if mode != "rect":
		set_mode("rect")
	grid_changed.emit()
	say("%s%s: drag it out" % [EdOps.SHAPES[kind].name, (", %d %s" % [shape_sides, "points" if kind == "star" else "sides"]) if shape_sides != null else ""])

# --- COPY AND PASTE ----------------------------------------------------

func copy_sel() -> bool:
	var d := doc
	if sel_kind == "" or sel_ids.is_empty():
		say("nothing selected to copy")
		return false
	var clip := {"kind": sel_kind, "items": []}
	var pts := []
	match sel_kind:
		"thing":
			for t in d.things:
				if sel_ids.has(t.id):
					clip.items.append(t.duplicate(true))
					pts.append(Vector2(t.x, t.y))
		"prop":
			for p in d.props:
				if sel_ids.has(p.id):
					clip.items.append(p.duplicate(true))
					pts.append(Vector2(p.x0, p.y0))
		"scatter":
			for c in d.scatters:
				if sel_ids.has(c.id):
					clip.items.append(c.duplicate(true))
					var a: Dictionary = c.area
					pts.append(Vector2(EdDoc.num(got2(a, "x", "x0"), 0), EdDoc.num(got2(a, "y", "y0"), 0)))
		"sector":
			for s in d.sectors:
				if sel_ids.has(s.id):
					var r := EdDoc.ring_of(d, s)
					clip.items.append({"props": EdDoc.copy_without(s, ["verts", "id"]), "ring": r})
					for p in r:
						pts.append(p)
		_:
			say("%ss cannot be copied — copy the sectors or things" % sel_kind)
			return false
	var mn := Vector2(INF, INF)
	for p in pts:
		mn = mn.min(p)
	clip["anchor"] = mn
	clip["layer"] = layer()
	clipboard = clip
	say("copied %d %s%s" % [clip.items.size(), sel_kind, "s" if clip.items.size() > 1 else ""])
	return true

static func got2(a: Dictionary, k1: String, k2: String):
	return a.get(k1) if a.get(k1) != null else a.get(k2)

func paste(in_place := false) -> void:
	var clip = clipboard
	if clip == null:
		say("the clipboard is empty")
		return
	var c = clip.anchor if in_place else cursor
	if c == null:
		say("point at where to paste")
		return
	var dx := 0.0 if in_place else snap_v(c.x - clip.anchor.x)
	var dy := 0.0 if in_place else snap_v(c.y - clip.anchor.y)
	var moved: bool = int(clip.get("layer", 0)) != layer()
	var made := []
	if clip.kind == "sector":
		history.push("paste %d sectors" % clip.items.size())
		for it in clip.items:
			var d := doc
			var ring := []
			for p in it.ring:
				ring.append(EdOps.vertex_for(d, p.x + dx, p.y + dy))
			var vs := []
			for k in ring.size():
				if ring[k] != ring[(k + 1) % ring.size()]:
					vs.append(ring[k])
			var s: Dictionary = it.props.duplicate(true)
			s["id"] = EdDoc.take_id(d)
			s["verts"] = vs
			if moved and layer() != 0:
				var cc := Vector2.ZERO
				for p in it.ring:
					cc += (p + Vector2(dx, dy)) / it.ring.size()
				var b = EdDoc.layer_base(d, layer(), cc.x, cc.y)
				if b != null:
					var hgt := EdDoc.num(s.get("ceil"), 256) - EdDoc.num(s.get("floor"), 0)
					s["floor"] = b.floor
					s["ceil"] = b.floor + hgt
			if vs.size() >= 3:
				d.sectors.append(s)
				made.append(s.id)
		EdDoc.compact(doc)
		changed(true)
	else:
		var d := edit_begin("paste %d %ss" % [clip.items.size(), clip.kind])
		for it in clip.items:
			var o: Dictionary = it.duplicate(true)
			o["id"] = EdDoc.take_id(d)
			if clip.kind == "thing":
				o.x = EdDoc.num(o.x) + dx
				o.y = EdDoc.num(o.y) + dy
				if layer() != 0:
					o["layer"] = layer()
				else:
					o.erase("layer")
				d.things.append(o)
			elif clip.kind == "prop":
				o.x0 += dx; o.x1 += dx; o.y0 += dy; o.y1 += dy
				d.props.append(o)
			elif clip.kind == "scatter":
				var a: Dictionary = o.area
				if a.kind == "circle":
					a.x += dx; a.y += dy
				elif a.kind == "rect":
					a.x0 += dx; a.x1 += dx; a.y0 += dy; a.y1 += dy
				d.scatters.append(o)
			made.append(o.id)
		edit_end(false)
	select(clip.kind, made)
	say("pasted %d" % made.size())

# --- HOVER, TARGET, TEXTURE ---------------------------------------------

func set_hover(h) -> void:
	var k := ("%s:%s" % [h.kind, h.id]) if h != null else ""
	if k == _hover_key:
		return
	_hover_key = k
	hovered = h
	hover_changed.emit()

func _two_sided(key: String) -> bool:
	var l = line_info(key)
	return l != null and l.sectors.size() > 1

## The selection if there is one of this kind, or the highlighted thing.
func target_or(kind: String) -> Dictionary:
	if sel_kind == kind and not sel_ids.is_empty():
		return sel_ids
	if hovered != null and hovered.kind == kind:
		return {hovered.id: true}
	return {}

## A texture onto whatever is selected: the surface picked in 3D, or the
## field the inspector is picking for.
func apply_texture(name: String, field := "") -> void:
	var kind := sel_kind
	var ids := sel_ids
	if surf != null:
		var s: Dictionary = surf
		if s.part == "wall":
			# the face's skin — or, in a two-sided opening, what stands in it
			var f := "midTex" if s.get("band") == "middle" and _two_sided(s.line) else "tex"
			var face_id := str(doc.sectors[s.sector].id) if s.sector >= 0 and s.sector < doc.sectors.size() else ""
			var d := edit_begin("texture %s" % name)
			if not d.lines.has(s.line):
				d.lines[s.line] = {}
			var o: Dictionary = d.lines[s.line]
			if not o.has("sides"):
				o["sides"] = {}
			if not o.sides.has(face_id):
				o.sides[face_id] = {}
			o.sides[face_id][f] = name
			edit_end(false)
		else:
			var d := edit_begin("texture %s" % name)
			if s.sector >= 0 and s.sector < d.sectors.size():
				d.sectors[s.sector]["floorTex" if s.part == "floor" else "ceilTex"] = name
			edit_end(false)
		return
	if kind == "sector" and field != "":
		var d := edit_begin("%s %s" % [field, name])
		for s in d.sectors:
			if ids.has(s.id):
				s[field] = name
		edit_end(false)
	elif kind == "prop":
		var d := edit_begin("prop texture %s" % name)
		for p in d.props:
			if ids.has(p.id):
				p[field if field != "" else "tex"] = name
		edit_end(false)
	elif kind == "line" and sel_face != null:
		loop_texture("all", name)
	elif kind == "line":
		var d := edit_begin("line texture %s" % name)
		for k in ids:
			if not d.lines.has(k):
				d.lines[k] = {}
			d.lines[k]["wallTex"] = name
		edit_end(false)
	else:
		prop_tex = name
		say("%s is the texture for new props" % name)

# --- THE OUTLINE BEING DRAWN --------------------------------------------

func add_path_point(pt: Vector2) -> void:
	if path.size() >= 3 and path[0] == pt:
		close_path()
		return
	if not path.is_empty() and path[path.size() - 1] == pt:
		return
	path.append(pt)
	path_changed.emit()

## FINISH THE DRAWING: closed, a sector; finished open with both ends on
## one sector's edge, a split; otherwise linedefs.
func close_path(open := false) -> void:
	var p := PackedVector2Array(path)
	path = []
	if open and p.size() >= 2 and split_by_path(p):
		pass
	elif open and p.size() >= 2:
		add_linedefs(p)
	elif p.size() >= 3:
		add_sector(p)
	elif p.size() > 0:
		say("one corner is not a line — click another, then Enter for linedefs, or close the shape for a sector")
	path_changed.emit()
	after_draw()

func after_draw() -> void:
	if mode == "draw" and mode_before_draw != "" and mode_before_draw != "draw":
		set_mode(mode_before_draw)

func split_by_path(pts: PackedVector2Array) -> bool:
	var d0 := doc
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var on_edge := func(s: Dictionary, p: Vector2) -> bool:
		var r := EdDoc.ring_of(d0, s)
		for k in r.size():
			if EdDoc.seg_dist(r[k], r[(k + 1) % r.size()], p).x < EdOps.ON_LINE:
				return true
		return false
	var mid := pts[1] if pts.size() > 2 else (a + b) / 2.0
	var s0 = null
	for s in d0.sectors:
		if on_edge.call(s, a) and on_edge.call(s, b) and EdDoc.pip(EdDoc.ring_of(d0, s), mid.x, mid.y):
			s0 = s
			break
	if s0 == null:
		return false
	var sid = s0.id
	var d := edit_begin("split sector")
	var pth := []
	for p in pts:
		pth.append(EdOps.vertex_for(d, p.x, p.y))
	var made = EdOps.split_sector(d, sector_by_id(sid), pth)
	if made == null:
		# nothing was split: that edit is not kept
		history.undo()
		history.future.clear()
		changed()
		return false
	edit_end(true)
	select("sector", [made.id])
	say("split the sector in two")
	return true

func cancel_path() -> void:
	if not path.is_empty():
		path = []
		path_changed.emit()

func set_cursor(pt) -> void:
	cursor = pt
	cursor_changed.emit()

# --- A DRAG, from either view --------------------------------------------

func begin_move(ref: Vector2, at: Vector2) -> Dictionary:
	return {"ref": ref, "start": at, "done": Vector2.ZERO, "pushed": false, "onto": "grid"}

func drag_move(dr: Dictionary, at: Vector2, r := 0.0) -> void:
	var ref: Vector2 = dr.ref
	var st: Vector2 = dr.start
	var tx: float = snap_v(ref.x + at.x - st.x) - ref.x
	var ty: float = snap_v(ref.y + at.y - st.y) - ref.y
	if r > 0 and sel_kind in ["vertex", "line", "sector"]:
		var moving := moving_verts()
		var s := snap_at(ref.x + at.x - st.x, ref.y + at.y - st.y, r, moving, sel_kind == "vertex" and moving.size() == 1)
		if s.kind != "grid":
			tx = s.pt.x - ref.x
			ty = s.pt.y - ref.y
		dr.onto = s.kind
	var dd: Vector2 = Vector2(tx, ty) - dr.done
	if dd == Vector2.ZERO:
		return
	if not dr.pushed:
		history.push("move %s" % sel_kind)
		dr.pushed = true
	EdOps.move_things(doc, sel_kind, sel_ids, dd.x, dd.y)
	dr.done = Vector2(tx, ty)
	dragging = true
	changed(false, false)

func end_move(dr) -> void:
	dragging = false
	if dr == null or not dr.pushed:
		return
	for i in moving_verts():
		EdOps.split_lines_at(doc, i)
	var before: int = doc.vertices.size()
	EdDoc.compact(doc)
	if doc.vertices.size() != before and (sel_kind == "vertex" or sel_kind == "line"):
		clear_sel()
	changed(true)
	say("moved %s, %s" % [_nice(dr.done.x), _nice(dr.done.y)])

## Where a drag of the selection grabs it, nearest at.
func grab_point(at: Vector2) -> Vector2:
	var d := doc
	var pts := []
	match sel_kind:
		"vertex":
			for i in sel_ids:
				if i >= 0 and i < d.vertices.size():
					pts.append(d.vertices[i])
		"line":
			for k in sel_ids:
				var ab := EdDoc.key_verts(k)
				for i in [ab.x, ab.y]:
					if i >= 0 and i < d.vertices.size():
						pts.append(d.vertices[i])
		"sector":
			for s in d.sectors:
				if sel_ids.has(s.id):
					for p in EdDoc.ring_of(d, s):
						pts.append(p)
		"thing":
			for t in d.things:
				if sel_ids.has(t.id):
					pts.append(Vector2(t.x, t.y))
		"prop":
			for p in d.props:
				if sel_ids.has(p.id):
					pts.append(Vector2(p.x0, p.y0))
					pts.append(Vector2(p.x1, p.y1))
		"scatter":
			for c in d.scatters:
				if sel_ids.has(c.id) and c.area.kind == "circle":
					pts.append(Vector2(c.area.x, c.area.y))
	var best := at
	var bd := INF
	for v in pts:
		var q: float = v.distance_to(at)
		if q < bd:
			bd = q
			best = v
	return best

# --- THE SCATTERS ------------------------------------------------------

func add_scatter(area: Dictionary, preset := "") -> Dictionary:
	if preset == "":
		preset = scatter_preset
	var d := edit_begin("scatter")
	var made := EdScatter.scatter_from(preset, area, EdDoc.take_id(d), randi())
	d.scatters.append(made)
	edit_end(false)
	select("scatter", [made.id])
	changed(true)
	return made

func scatter_sectors(preset := ""):
	if sel_kind != "sector" or sel_ids.is_empty():
		say("select sectors to scatter into")
		return null
	return add_scatter({"kind": "sectors", "ids": sel_ids.keys()}, preset)

func paint_brush(a: Vector2, b: Vector2) -> void:
	var r := a.distance_to(b)
	if r < 16:
		r = brush_radius
	brush_radius = int(EdDoc.jsround(r))
	add_scatter({"kind": "circle", "x": a.x, "y": a.y, "r": EdDoc.jsround(r)})

func reseed() -> void:
	if sel_kind != "scatter":
		return
	var d := edit_begin("reseed")
	for c in d.scatters:
		if sel_ids.has(c.id):
			c["seed"] = randi()
	edit_end(false)

## BAKE: the selected scatters' things as ordinary things, the rule gone.
func bake() -> void:
	if sel_kind != "scatter":
		return
	compile_now()
	var ids := sel_ids
	var items := []
	for t in compiled.get("scattered", []):
		if ids.has(t.get("scatter")):
			items.append(t)
	var d := edit_begin("bake %d" % items.size())
	for t in items:
		var o := {"id": EdDoc.take_id(d), "type": t.type, "x": t.x, "y": t.y, "angle": snappedf(t.angle, 0.001)}
		if t.get("kind") != null:
			o["kind"] = t.kind
		if t.type != "PLANT":
			o["variant"] = t.variant
		if t.get("scale") != null and t.scale != 1:
			o["scale"] = t.scale
		d.things.append(o)
	d.scatters = d.scatters.filter(func(c): return not ids.has(c.id))
	edit_end(false)
	clear_sel()
	say("baked %d things" % items.size())

func select_all_in_mode() -> void:
	var d := doc
	match mode:
		"vertices":
			select("vertex", range(d.vertices.size()))
		"lines":
			select("line", lines().map(func(l): return l.key))
		"things":
			var ids := []
			for t in d.things:
				if on_layer(t):
					ids.append(t.id)
			select("thing", ids)
		"props":
			select("prop", d.props.map(func(p): return p.id))
		"scatter":
			select("scatter", d.scatters.map(func(p): return p.id))
		_:
			select("sector", d.sectors.map(func(s): return s.id))

# ---------------------------------------------------------------------
# THE KEYBOARD, which is most of what a Doom editor is. The view the
# mouse is over gets first refusal; nothing fires while a field has the
# keyboard (a LineEdit takes the key before it gets here).
# ---------------------------------------------------------------------

## IN A FIELD: Escape gives the keys back to the map; Enter commits
## (the fields do that themselves); and Ctrl+Z in a number field is the
## map's undo, as it always is in Doom Builder — the field commits first.
func _input(event: InputEvent) -> void:
	if headless or not visible or not event is InputEventKey or not event.pressed:
		return
	var f := get_viewport().gui_get_focus_owner()
	if not f is LineEdit:
		return
	var e: InputEventKey = event
	if e.keycode == KEY_ESCAPE:
		f.release_focus()
		get_viewport().set_input_as_handled()
	elif (e.ctrl_pressed or e.meta_pressed) and (e.keycode == KEY_Z or e.keycode == KEY_Y) and f.get_parent() is SpinBox:
		f.release_focus()
		get_viewport().set_input_as_handled()
		if e.keycode == KEY_Y or e.shift_pressed:
			redo()
		else:
			undo()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or headless:
		return
	if not event is InputEventKey or not event.pressed:
		return
	if ui != null and ui.dialog_open():
		return
	var e: InputEventKey = event
	if _key(e):
		get_viewport().set_input_as_handled()

func _key(e: InputEventKey) -> bool:
	var k := e.keycode
	var ctrl := e.ctrl_pressed or e.meta_pressed
	if ctrl and k == KEY_Z:
		if e.shift_pressed:
			redo()
		else:
			undo()
		return true
	if ctrl and k == KEY_Y:
		redo()
		return true
	if ctrl and k == KEY_S:
		if e.shift_pressed and ui != null:
			ui.save_as_dialog()
		else:
			file_save()
		return true
	if ctrl and k == KEY_O:
		if ui != null:
			ui.open_dialog()
		return true
	if ctrl and k == KEY_A:
		select_all_in_mode()
		return true
	if ctrl and pointer_view == "3d" and view3d != null and view3d.key(e):
		return true
	if ctrl and k == KEY_C:
		copy_sel()
		return true
	if ctrl and k == KEY_V:
		paste(e.shift_pressed)
		return true
	if ctrl:
		return false
	if k == KEY_Q and not e.alt_pressed and view3d != null and not view3d.looking:
		view3d.toggle_visual()
		return true
	var target = view3d if pointer_view == "3d" else view2d
	if (view3d != null and view3d.visual) and target != view3d:
		target = view3d
	if target != null and target.key(e):
		return true
	if k == KEY_F5:
		play()
		return true
	if k == KEY_TAB:
		var nxt := {"combined": "combined2d", "combined2d": "combined", "only3d": "only2d", "only2d": "only3d"}
		set_layout(nxt.get(layout, "only3d" if pointer_view == "3d" else "only2d"))
		return true
	if k == KEY_BACKSPACE and not path.is_empty():
		path.pop_back()
		path_changed.emit()
		return true
	if k == KEY_DELETE or k == KEY_BACKSPACE:
		if sel_kind == "" and k == KEY_DELETE and hovered != null and hovered.kind == MODE_KIND.get(mode, "sector"):
			select(hovered.kind, [hovered.id])
		if sel_kind != "":
			delete_sel()
		return true
	if k == KEY_INSERT:
		insert_at_cursor()
		return true
	if (k == KEY_PAGEUP or k == KEY_PAGEDOWN) and e.alt_pressed:
		set_layer(layer() + (1 if k == KEY_PAGEUP else -1))
		return true
	if k == KEY_PAGEUP or k == KEY_PAGEDOWN:
		var ids := target_or("sector")
		if not ids.is_empty():
			nudge_height("ceil" if e.shift_pressed else "floor", (1 if k == KEY_PAGEUP else -1) * 8, ids)
		return true
	if k == KEY_ESCAPE:
		if not path.is_empty():
			cancel_path()
			after_draw()
		else:
			clear_sel()
		return true
	if (k == KEY_ENTER or k == KEY_KP_ENTER) and not path.is_empty():
		close_path(true)
		return true
	if k == KEY_BRACKETLEFT:
		grid_step(-1)
		return true
	if k == KEY_BRACKETRIGHT:
		grid_step(1)
		return true
	if not e.alt_pressed:
		for m in MODES:
			if OS.get_keycode_string(k) == MODES[m].key and not (e.shift_pressed and (k == KEY_A or k == KEY_G)):
				set_mode(m)
				return true
	if k == KEY_G and e.shift_pressed:
		snap_sel_to_grid()
		return true
	if k == KEY_G:
		set_snap()
		return true
	if k == KEY_SPACE:
		set_mode("draw")
		return true
	if k == KEY_F:
		frame_req.emit()
		return true
	if k == KEY_B and view3d != null:
		view3d.set_fullbright(not view3d.fullbright)
		return true
	if k == KEY_K:
		var order := ["normal", "light", "floor", "ceil"]
		plan_view = order[(order.find(plan_view) + 1) % order.size()]
		grid_changed.emit()
		var names := {"normal": "normal", "light": "brightness", "floor": "floor heights", "ceil": "ceiling heights"}
		say("plan: %s" % names[plan_view])
		return true
	return false
