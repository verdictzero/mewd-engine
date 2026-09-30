## MEWD — the editor as a person uses it: real input events into the
## views and the keyboard, the inspector's own fields, the 3D view's
## picking, visual mode, and the round trip to the game and back.
##
##   godot --headless --script res://godot/tests/editor_ui_test.gd -- --edit
##
## The main scene is started as the game starts (--edit opens the
## editor), the plan is driven with mouse events — a drag on the ground
## draws a room, a click selects it, a drag moves it, Draw mode clicks a
## triangle, the wheel zooms, Ctrl+wheel lights — the keys switch modes,
## snap, grid and layout, the inspector's Floor field is typed into, a
## texture is picked, the 3D view picks a floor under its crosshair and
## the wheel raises it, Q is visual mode; then PLAY builds the map in the
## game, and F2 comes back to the editor on the same map.
extends SceneTree

var fails := 0
var checks := 0
var main: Node

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL ", what)
	elif OS.get_cmdline_user_args().has("--verbose"):
		print("ok   ", what)

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func mb(v: Control, at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, mods := {}) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = mods.get("shift", false)
	e.ctrl_pressed = mods.get("ctrl", false)
	e.alt_pressed = mods.get("alt", false)
	e.double_click = mods.get("double", false)
	e.factor = 1.0
	v._gui_input(e)

func mm(v: Control, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	v._gui_input(e)

func drag(v: Control, a: Vector2, b: Vector2, button := MOUSE_BUTTON_LEFT, mods := {}) -> void:
	mm(v, a)
	mb(v, a, true, button, mods)
	for i in range(1, 5):
		mm(v, a.lerp(b, i / 4.0))
	mb(v, b, false, button, mods)

func click(v: Control, at: Vector2, mods := {}) -> void:
	mm(v, at)
	mb(v, at, true, MOUSE_BUTTON_LEFT, mods)
	mb(v, at, false, MOUSE_BUTTON_LEFT, mods)

func key(ed: MewdEditor, k: Key, mods := {}) -> bool:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	e.shift_pressed = mods.get("shift", false)
	e.ctrl_pressed = mods.get("ctrl", false)
	e.alt_pressed = mods.get("alt", false)
	return ed._key(e)

func find_field(box: Node, label: String) -> Control:
	for c in box.get_children():
		if c is HBoxContainer and c.get_child_count() > 1 and c.get_child(0) is Label and c.get_child(0).text == label:
			return c.get_child(1)
		var f := find_field(c, label)
		if f != null:
			return f
	return null

## the editor's own files, put back as they were when the test is done
var _kept := {}

func _keep() -> void:
	for f in [MewdEditor.AUTOSAVE, MewdEditor.PREFS]:
		_kept[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else null

func _restore() -> void:
	for f in _kept:
		if _kept[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var h := FileAccess.open(f, FileAccess.WRITE)
			h.store_string(_kept[f])

func _initialize() -> void:
	_keep()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MewdEditor.AUTOSAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MewdEditor.PREFS))
	main = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	run()

func run() -> void:
	await frames(5)
	var ed: MewdEditor = main.editor
	ok(ed != null and ed.ui != null, "--edit opens the editor")
	if ed == null:
		_restore()
		quit(1)
		return
	ed.file_new(false)
	ed.set_layout("only2d")
	await frames(3)
	var v: EdView2D = ed.view2d
	v.frame()
	ok(v.size.x > 100 and v.size.y > 100, "the plan has a size (%s)" % v.size)
	var P := func(x: float, y: float) -> Vector2: return v.sp(Vector2(x, y))

	# A DRAG ON THE GROUND DRAWS A ROOM
	drag(v, P.call(512, 512), P.call(1024, 1024))
	ok(ed.doc.sectors.size() == 2, "a drag on the ground draws a sector (%d)" % ed.doc.sectors.size())
	var room = ed.sector_at(700, 700)
	ok(room != null and room.id != 1, "the new room is under the mouse")
	ok(ed.sel_kind == "sector" and room != null and ed.sel_ids.has(room.id), "and it is selected")
	# A CLICK ON NOTHING LETS GO, A CLICK SELECTS
	ed.clear_sel()
	click(v, P.call(768, 768))
	ok(room != null and ed.is_sel("sector", room.id), "a click selects the room")
	# A DRAG MOVES IT, ONE UNDO
	var before: Vector2 = EdDoc.bbox(EdDoc.ring_of(ed.doc, room)).position
	drag(v, P.call(768, 768), P.call(768 + 128, 768))
	room = ed.sector_by_id(room.id)
	var after: Vector2 = EdDoc.bbox(EdDoc.ring_of(ed.doc, room)).position
	ok(after.x - before.x == 128 and after.y == before.y, "a drag moves it 128 (%s → %s)" % [before, after])
	ed.undo()
	room = ed.sector_by_id(room.id)
	ok(EdDoc.bbox(EdDoc.ring_of(ed.doc, room)).position == before, "and one undo puts it back")
	ed.redo()

	# LOOP SELECT (the room is at 640..1152 x 512..1024 now): Alt+click a
	# line, every wall of the room on that side
	ok(key(ed, KEY_L) and ed.mode == "lines", "L is Lines")
	click(v, P.call(642, 768), {"alt": true})
	ok(ed.sel_kind == "line" and ed.sel_ids.size() == 4 and ed.sel_face == room.id,
		"Alt+click inside the room's wall: its four walls, facing it (%d, face %s)" % [ed.sel_ids.size(), str(ed.sel_face)])
	var ground = ed.sector_at(100, 100)
	click(v, P.call(636, 768), {"alt": true})
	ok(ed.sel_ids.size() == 8 and ed.sel_face == ground.id,
		"and outside it: the ground's four, and the room's four facing the ground (%d)" % ed.sel_ids.size())
	click(v, P.call(896, 514), {"double": true})
	ok(ed.sel_ids.size() == 4 and ed.sel_face == room.id, "a double-click on a line does the same")
	ed.ui.panels.pick_texture("CONC_1")
	var painted := 0
	for k in ed.sel_ids:
		var sd = ed.doc.lines.get(k, {}).get("sides", {}).get(str(room.id), {})
		if sd.get("tex") == "CONC_1" and sd.get("midTex") == null:
			painted += 1
	ok(painted == 4 and ed.loop_tex_of("skin") == "CONC_1", "a texture clicked skins all four, on the room's side (%d)" % painted)
	ed.ui.panels.picking = {"field": "@loop.mid", "label": "Fill", "allow_none": true}
	ed.ui.panels.pick_texture("CONC_2")
	ok(ed.loop_tex_of("mid") == "CONC_2" and ed.loop_tex_of("skin") == "CONC_1", "and the loop's fill field sets what stands in the openings alone")
	ed.undo()
	ed.undo()
	ok(ed.doc.lines.is_empty(), "two undos, and no line has an override (%d)" % ed.doc.lines.size())
	click(v, P.call(642, 768))
	ok(ed.sel_ids.size() == 1 and ed.sel_face == null, "a plain click picks one line again")
	ed.clear_sel()

	# THE DOOR TOOL (O): a click on a wall, a door in it
	ok(key(ed, KEY_O) and ed.mode == "doors", "O is Doors")
	var doors_in := func() -> Array:
		var out := []
		for k in ed.doc.lines:
			var o = ed.doc.lines[k]
			if o is Dictionary and o.get("door") is Dictionary:
				out.append(k)
		return out
	click(v, P.call(900, 514))
	var dk: Array = doors_in.call()
	var dlen := 0.0
	if dk.size() == 1:
		var ab := EdDoc.key_verts(dk[0])
		dlen = ed.doc.vertices[ab.x].distance_to(ed.doc.vertices[ab.y])
	ok(dk.size() == 1 and dlen == 64.0 and ed.doc.lines[dk[0]].get("opening", false), "a click on the room's wall: a door, 64 wide (%s, %.0f)" % [dk, dlen])
	ok(ed.sel_kind == "line" and dk.size() == 1 and ed.sel_ids.has(dk[0]), "and it is selected, for the inspector")
	click(v, P.call(1150, 700))
	ok(doors_in.call().size() == 2, "another click, another door (%d)" % doors_in.call().size())
	ed.compile_now()
	ok(ed.compiled.level.doors.size() == 2, "and the build has both (%d)" % ed.compiled.level.doors.size())
	click(v, P.call(900, 514), {"shift": true})
	ok(doors_in.call().size() == 1, "Shift+click takes one out (%d)" % doors_in.call().size())
	ed.undo()
	ed.undo()
	ed.undo()
	ok(doors_in.call().is_empty(), "three undos, and no doors")
	ed.clear_sel()
	key(ed, KEY_S)
	# DRAW MODE: three clicks and the first again
	ok(key(ed, KEY_D), "D is Draw")
	ok(ed.mode == "draw", "the mode is draw")
	var n0: int = ed.doc.sectors.size()
	for p in [Vector2(2048, 2048), Vector2(2560, 2048), Vector2(2304, 2560), Vector2(2048, 2048)]:
		click(v, P.call(p.x, p.y))
	ok(ed.doc.sectors.size() == n0 + 1, "a triangle clicked out is a sector")
	ok(ed.mode == "sectors", "and Draw goes back to the mode it came from")
	# THE SHAPE TOOL
	ed.set_shape("circle", 16)
	drag(v, P.call(3000, 512), P.call(3512, 1024))
	var circ = ed.sector_at(3256, 768)
	ok(circ != null and circ.verts.size() == 16, "the shape tool draws a 16-sided circle")
	ed.set_shape("rect")
	ed.set_mode("sectors")
	# BOX SELECT, in vertices mode
	ok(key(ed, KEY_V) and ed.mode == "vertices", "V is Vertices")
	drag(v, P.call(400, 400), P.call(1300, 1100))
	ok(ed.sel_kind == "vertex" and ed.sel_ids.size() == 4, "a box on nothing selects the room's four corners (%d)" % ed.sel_ids.size())
	# ARROWS NUDGE
	var vid: int = ed.sel_ids.keys()[0]
	var vp: Vector2 = ed.doc.vertices[vid]
	var e := InputEventKey.new()
	e.keycode = KEY_RIGHT
	e.pressed = true
	ok(v.key(e), "an arrow nudges the selection")
	ok(ed.doc.vertices.find(vp + Vector2(64, 0)) >= 0, "a grid step to the right")
	ed.undo()
	ed.set_mode("sectors")
	# THE WHEEL ZOOMS, CTRL+WHEEL LIGHTS
	var s0 := v.scale_
	mb(v, P.call(768, 768), true, MOUSE_BUTTON_WHEEL_UP)
	ok(v.scale_ > s0, "the wheel zooms in")
	room = ed.sector_at(768, 768)
	var b0 := MewdEditor.bright_of(room)
	mb(v, P.call(768, 768), true, MOUSE_BUTTON_WHEEL_DOWN, {"ctrl": true})
	room = ed.sector_at(768, 768)
	ok(MewdEditor.bright_of(room) == b0 - 16, "Ctrl+wheel darkens the sector 16 (%d → %d)" % [b0, MewdEditor.bright_of(room)])
	# FINGERS: two pinch the plan, and the pad of keys a tablet has not got
	var st0 := v.scale_
	var t1 := InputEventScreenTouch.new()
	t1.index = 0
	t1.position = Vector2(300, 300)
	t1.pressed = true
	v._gui_input(t1)
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.position = Vector2(400, 300)
	t2.pressed = true
	v._gui_input(t2)
	var sd := InputEventScreenDrag.new()
	sd.index = 1
	sd.position = Vector2(500, 300)
	v._gui_input(sd)
	ok(absf(v.scale_ / st0 - 2.0) < 0.01, "two fingers spread twice as far zoom in twice (%.3f)" % (v.scale_ / st0))
	t1.pressed = false
	t2.pressed = false
	v._gui_input(t1)
	v._gui_input(t2)
	ok(v.gesture == null and ed.ui.pad.visible, "the gesture ends, and the pad is up")
	v.scale_ = st0
	# THE KEYS
	var g0 := ed.grid
	key(ed, KEY_BRACKETLEFT)
	ok(ed.grid == g0 / 2, "[ halves the grid")
	key(ed, KEY_BRACKETRIGHT)
	var sn := ed.snap
	key(ed, KEY_G)
	ok(ed.snap != sn, "G switches snap")
	key(ed, KEY_G)
	key(ed, KEY_K)
	ok(ed.plan_view == "light", "K shows the plan by brightness")
	key(ed, KEY_K); key(ed, KEY_K); key(ed, KEY_K)
	key(ed, KEY_TAB)
	ok(ed.layout == "only3d", "Tab flips the plan for the 3D view")
	key(ed, KEY_TAB)
	# THE INSPECTOR: the Floor field, typed into
	click(v, P.call(768, 768))
	await frames(4)
	var floor_f := find_field(ed.ui.panels.insp, "Floor")
	ok(floor_f is SpinBox, "the inspector has a Floor field")
	if floor_f is SpinBox:
		floor_f.value = 32
		room = ed.sector_at(768, 768)
		ok(EdDoc.num(room.floor) == 32, "typing 32 in it raises the floor (%s)" % room.floor)
	# A TEXTURE, PICKED FOR A FIELD
	ed.ui.panels.picking = {"field": "floorTex", "label": "Floor", "allow_none": false}
	ed.ui.panels.pick_texture("CONC_1")
	room = ed.sector_at(768, 768)
	ok(room.floorTex == "CONC_1", "a texture picked for the floor goes on the floor")
	# DELETE
	var ns: int = ed.doc.sectors.size()
	key(ed, KEY_DELETE)
	ok(ed.doc.sectors.size() == ns - 1, "Delete removes the selected sector")
	ed.undo()
	# COPY AND PASTE
	click(v, P.call(768, 768))
	key(ed, KEY_C, {"ctrl": true})
	ed.set_cursor(Vector2(1536, 2560))
	key(ed, KEY_V, {"ctrl": true})
	ok(ed.doc.sectors.size() == ns + 1, "Ctrl+C, Ctrl+V pastes the room")

	# THE TEXTURE EDITOR: a new texture from CONC_1, a second layer, saved
	ed.ui.open_texture_editor(null, "CONC_1")
	await frames(3)
	var te: EdTexEditor = ed.ui._dialog
	ok(te != null and te.visible and te.def.name == "CONC_1_1", "the texture editor opens on a new CONC_1_1")
	te.def.layers.append(EdTex.new_layer("GRIDWALL"))
	te.def.layers[1].blend = "multiply"
	te.save()
	await frames(3)
	ok(ed.doc.textures.size() == 1 and ed.doc.textures[0].layers.size() == 2, "saving puts it in the map, both layers")
	ok(ed.map_texture_names.has("CONC_1_1") and TexBank.map_own.has("CONC_1_1"), "and in the browser and the bank")
	ed.ui.open_texture_editor("CONC_1_1")
	await frames(2)
	te = ed.ui._dialog
	te.def.name = "MYWALL"
	te.save()
	await frames(2)
	ok(ed.doc.textures[0].name == "MYWALL" and ed.map_texture_names.has("MYWALL"), "renamed, it is MYWALL")
	# THE 3D VIEW: the floor under the crosshair, the wheel raises it
	ed.set_layout("only3d")
	await frames(4)
	var v3: EdView3D = ed.view3d
	ok(v3.size.x > 100, "the 3D view has a size (%s)" % v3.size)
	room = ed.sector_at(768, 768)
	v3.cam = {"x": 768.0, "y": 300.0, "z": 400.0, "yaw": PI / 2.0, "pitch": -0.9}
	v3.mouse = v3.size / 2.0
	v3._hover_dirty = true
	await frames(3)
	ok(v3.hover != null and v3.hover.kind == "surface" and v3.hover.part == "floor", "the 3D view picks the floor it looks at (%s)" % [v3.hover])
	if v3.hover != null and v3.hover.kind == "surface":
		var hs: Dictionary = ed.doc.sectors[v3.hover.sector]
		var f0 := EdDoc.num(hs.get("floor"), 0)
		mb(v3, v3.size / 2.0, true, MOUSE_BUTTON_WHEEL_UP)
		hs = ed.doc.sectors[v3.hover.sector]
		ok(EdDoc.num(hs.get("floor"), 0) == f0 + 8, "the wheel raises it 8 (%s → %s)" % [f0, hs.get("floor")])
		mb(v3, v3.size / 2.0, true, MOUSE_BUTTON_LEFT)
		mb(v3, v3.size / 2.0, false, MOUSE_BUTTON_LEFT)
		ok(ed.surf != null and ed.surf.part == "floor", "a click picks the surface")
		var e2 := InputEventKey.new()
		e2.keycode = KEY_C
		e2.ctrl_pressed = true
		e2.pressed = true
		ok(v3.key(e2) and v3.clip != null, "Ctrl+C copies its texture (%s)" % v3.clip)
	key(ed, KEY_Q)
	ok(v3.visual, "Q is visual mode")
	var e3 := InputEventKey.new()
	e3.keycode = KEY_ESCAPE
	e3.pressed = true
	ok(v3.key(e3) and not v3.visual, "Escape leaves it")
	ok(v3.level_node != null and v3.level_node.get_child_count() > 0, "the 3D view built the level (%d meshes)" % (v3.level_node.get_child_count() if v3.level_node else 0))

	# PLAY, AND BACK — from where the 3D camera stands, looking its way
	var sectors: int = ed.doc.sectors.size()
	var start_was = null
	for t in ed.doc.things:
		if t.type == "START":
			start_was = Vector2(t.x, t.y)
	v3.cam = {"x": 900.0, "y": 770.0, "z": 41.0, "yaw": 1.0, "pitch": -0.2}
	ed.play()
	await frames(10)
	ok(main.game != null and main.editor == null, "PLAY starts the game on the map")
	if main.game != null:
		ok(main.game.level.sectors.size() >= sectors, "the game built the edited map (%d sectors)" % main.game.level.sectors.size())
		var pl = main.game.player
		ok(absf(pl.x - 900.0) < 1.0 and absf(pl.y - 770.0) < 1.0 and absf(pl.angle - 1.0) < 1e-3 and absf(pl.pitch + 0.2) < 1e-3,
			"and from where the 3D camera stood, looking its way (%.0f, %.0f, %.2f, %.2f)" % [pl.x, pl.y, pl.angle, pl.pitch])

	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	main._unhandled_input(f2)
	await frames(10)
	main = current_scene
	ok(main != null and main.editor != null, "F2 comes back to the editor")
	if main != null and main.editor != null:
		var start_now = null
		for t in main.editor.doc.things:
			if t.type == "START":
				start_now = Vector2(t.x, t.y)
		ok(start_now == start_was, "and the map's own START is where it was (the game got a copy)")
	if main != null and main.editor != null:
		ok(main.editor.doc.sectors.size() == sectors, "on the same map (%d sectors)" % main.editor.doc.sectors.size())
	# BACK TO THE TITLE (the MEWD main menu), and MAP EDITOR again
	if main != null and main.editor != null:
		main.editor.quit_requested.emit()
		await frames(3)
		ok(main.editor == null and main.title != null, "File > Back to the title goes back to the main menu")
		if main.title != null:
			main.title.take(Title.ITEMS.map(func(it): return it[1]).find("editor"))
		var until := Time.get_ticks_msec() + 8000
		while main.editor == null and Time.get_ticks_msec() < until:
			await frames(1)
		ok(main.editor != null, "and MAP EDITOR on it opens the editor")
	print("editor ui: %d checks, %s" % [checks, "OK" if fails == 0 else "%d FAIL" % fails])
	_restore()
	quit(1 if fails else 0)
