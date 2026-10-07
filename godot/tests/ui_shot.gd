## MEWD — a picture of a screen of the UI (golf's house style, UiStyle),
## for looking at without playing:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --resolution 1280x720 \
##     --script res://godot/tests/ui_shot.gd -- out.png [what] [--size=WxH]
##
## `what`:
##   title     the title, its main menu (the default)
##   levels    the title with NEW GAME's islands
##   modes     the title with a hosted match's modes (a short column)
##   pause=N   the pause menu over the title, on page N, the cursor on its
##             second tile
##   debug     the debug menu over the title
##   pad       the pad wizard over the title
##   join      the join box over the title
## --size: the window that size instead (a phone on its side: 900x400).
extends SceneTree

var out := "ui_shot.png"
var what := "title"
var main: Node

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var p := a.substr(7).split("x")
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
			root.size = Vector2i(int(p[0]), int(p[1]))
		elif out == "ui_shot.png" and not a.begins_with("--"):
			out = a
		elif not a.begins_with("--"):
			what = a
	await process_frame
	main = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 60:
		await process_frame
	var title = main.get("title")
	match what.split("=")[0]:
		"levels":
			title.show_page(true)
		"modes":
			title.show_items(Title.MODES)
		"pause":
			var pm := PauseMenu.new()
			var layer := CanvasLayer.new()
			layer.layer = 50
			root.add_child(layer)
			layer.add_child(pm)
			await process_frame
			pm.show_page(int(what.split("=")[1]) if what.contains("=") else 1)
			pm._cursor_to(1)
		"debug":
			if main.has_method("open_debug"):
				main.open_debug()
		"pad":
			if main.has_method("open_pad_wizard"):
				main.open_pad_wizard()
		"join":
			if main.has_method("open_join_box"):
				main.open_join_box()
	for i in 90:
		await process_frame
	var err := root.get_viewport().get_texture().get_image().save_png(out)
	print("ui_shot: %s %s -> %s (%d)" % [what, str(root.size), out, err])
	quit()
