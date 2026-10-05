## MEWD — pictures of the DEBUG menu over the title, and of the PIXEL
## GRID at a low PIXELS setting (ui/debug_menu.gd, render/lofi.gd).
##   godot47 --script res://godot/tests/debug_shot.gd -- --out=/tmp/d
extends SceneTree

var main: Node
var n := 0
var out := "/tmp/debug"

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	root.size = Vector2i(1280, 720)
	main = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	process_frame.connect(_frame)

func _frame() -> void:
	n += 1
	if n == 60:
		main.open_debug()
	elif n == 90:
		root.get_texture().get_image().save_png(out + "-menu.png")
		print("debug_shot: menu, view %s, %d chars" % [main.debug_menu.view, main.debug_menu.text.text.length()])
		main.debug_menu.show_view("failure")
	elif n == 110:
		root.get_texture().get_image().save_png(out + "-failure.png")
		main.debug_menu.closed.emit()
		main.lofi.pixel_rows = 80
		main.lofi.grid_mode = "lcd"
		main.lofi._resize()
	elif n == 140:
		root.get_texture().get_image().save_png(out + "-grid80.png")
		print("debug_shot: grid at 80 rows: %.2f" % main.lofi.grid_strength)
		main.lofi.grid_mode = "lines"
		main.lofi._resize()
	elif n == 160:
		root.get_texture().get_image().save_png(out + "-lines80.png")
		print("debug_shot: grid lines at 80 rows: %.2f" % main.lofi.grid_strength)
		main.lofi.grid_mode = "off"
		main.lofi._resize()
		print("debug_shot: grid off at 80 rows: %.2f" % main.lofi.grid_strength)
		main.lofi.grid_mode = "lcd"
		main.lofi.pixel_rows = 480
		main.lofi._resize()
		print("debug_shot: grid at 480 rows: %.2f" % main.lofi.grid_strength)
		quit(0)
