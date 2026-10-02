## MEWD Editor — A TEXTURE DRAGGED OUT OF THE BROWSER onto a surface
## (EdView2D/3D._drop_tex, MewdEditor.texture_onto), headless:
##
##   godot --headless --script res://godot/tests/tex_drop_test.gd -- --edit
##
## A block drawn; a texture let go over its middle in the plan is its
## top's, over one of its edges that side's (the line's skin); in the 3D
## view, looking down at it, the top's again; over nothing, the ground's;
## each one undo.
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
	ed.add_rect(Vector2(512, 512), Vector2(1024, 1024))
	var blk = ed.block_at(768, 768)
	ok(blk != null, "a block to drop on")
	var bi := ed.block_index(blk.id)
	var data := {"mewd_tex": "CONC_3"}
	var mid := v.sp(Vector2(768, 768))
	ok(v._can_drop_tex(mid, data), "the plan takes a texture over the block")
	ok(not v._can_drop_tex(mid, {"other": 1}), "and nothing else")
	v._drop_tex(mid, data)
	ok(ed.doc.blocks[bi].get("top") == "CONC_3", "let go over the block: its top (%s)" % ed.doc.blocks[bi].get("top"))
	ed.undo()
	ok(ed.doc.blocks[bi].get("top") != "CONC_3", "one undo")
	# over a side
	var edge := v.sp(Vector2(1024, 768))
	var t = v.tex_target(edge)
	ok(t != null and t.part == "side", "over its edge: a side (%s)" % [t])
	v._drop_tex(edge, {"mewd_tex": "CONC_2"})
	var o = ed.doc.lines.get(t.line) if t != null else null
	ok(o is Dictionary and o.get("tex") == "CONC_2", "the side takes it, as the line's skin (%s)" % [o])
	# over nothing: the ground itself
	var far := v.sp(Vector2(-20000, -20000))
	var tg = v.tex_target(far)
	ok(v._can_drop_tex(far, data) and tg != null and tg.part == "ground", "over nothing: the ground")
	# the 3D view, looking down at the block
	var v3: EdView3D = ed.view3d
	v3.cam = {"x": 768.0, "y": 300.0, "z": 400.0, "yaw": PI / 2.0, "pitch": -0.9}
	await frames(3)
	var c3 := v3.size / 2.0
	ok(v3._can_drop_tex(c3, {"mewd_tex": "CONC_3"}), "the 3D view takes it over the top it looks at")
	v3._drop_tex(c3, {"mewd_tex": "CONC_3"})
	ok(ed.doc.blocks[bi].get("top") == "CONC_3", "and the top has it")
	print("tex drop: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	_restore()
	quit(1 if fails else 0)
