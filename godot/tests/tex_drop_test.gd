## MEWD Editor — A TEXTURE DRAGGED OUT OF THE BROWSER onto a surface
## (EdView2D/3D._drop_tex, MewdEditor.texture_onto), headless:
##
##   godot --headless --script res://godot/tests/tex_drop_test.gd -- --edit
##
## A room drawn; a texture let go over its middle in the plan is its
## floor's, over one of its walls that wall's; in the 3D view, looking
## down at it, the floor's again; over nothing, nothing; each one undo.
extends SceneTree

var fails := 0
var main: Node
var _kept := {}

func ok(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	for f in [MewdEditor.AUTOSAVE, MewdEditor.PREFS]:
		_kept[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else null
	main = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	run()

func _restore() -> void:
	for f in _kept:
		if _kept[f] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var h := FileAccess.open(f, FileAccess.WRITE)
			h.store_string(_kept[f])

func run() -> void:
	await frames(5)
	var ed: MewdEditor = main.editor
	ed.file_new(false)
	ed.set_layout("combined")
	await frames(3)
	var v: EdView2D = ed.view2d
	v.frame()
	await frames(2)
	var room = ed.add_rect(Vector2(512, 512), Vector2(1024, 1024))
	room = ed.sector_at(768, 768)
	ok(room != null, "a room to drop on")
	var si := ed.sector_index(room.id)
	var data := {"mewd_tex": "CONC_1"}
	var mid := v.sp(Vector2(768, 768))
	ok(v._can_drop_tex(mid, data), "the plan takes a texture over the room")
	ok(not v._can_drop_tex(mid, {"other": 1}), "and nothing else")
	v._drop_tex(mid, data)
	ok(ed.doc.sectors[si].get("floorTex") == "CONC_1", "let go over the room: its floor (%s)" % ed.doc.sectors[si].get("floorTex"))
	ed.undo()
	ok(ed.doc.sectors[si].get("floorTex") != "CONC_1", "one undo")
	# over a wall
	var edge := v.sp(Vector2(1024, 768))
	var t = v.tex_target(edge)
	ok(t != null and t.part == "wall", "over its edge: a wall (%s)" % [t])
	v._drop_tex(edge, {"mewd_tex": "CONC_2"})
	var o = ed.doc.lines.get(t.line) if t != null else null
	var sides = o.get("sides", {}) if o is Dictionary else {}
	var got := false
	for k in sides:
		if sides[k].get("tex") == "CONC_2" or sides[k].get("midTex") == "CONC_2":
			got = true
	ok(got, "the wall takes it (%s)" % [o])
	# over nothing
	var far := v.sp(Vector2(-20000, -20000))
	ok(not v._can_drop_tex(far, data), "over nothing: no")
	# the 3D view, looking down at the room
	var v3: EdView3D = ed.view3d
	v3.cam = {"x": 768.0, "y": 300.0, "z": 400.0, "yaw": PI / 2.0, "pitch": -0.9}
	await frames(3)
	var c3 := v3.size / 2.0
	ok(v3._can_drop_tex(c3, {"mewd_tex": "CONC_1"}), "the 3D view takes it over the floor it looks at")
	v3._drop_tex(c3, {"mewd_tex": "CONC_1"})
	ok(ed.doc.sectors[si].get("floorTex") == "CONC_1", "and the floor has it")
	print("tex drop: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	_restore()
	quit(1 if fails else 0)
