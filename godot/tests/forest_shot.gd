## MEWD — a picture of the wood and the street lamps, for looking at
## without the game.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/forest_shot.gd -- out.png [mode] [seed]
##
## The maze (MazeMap.build(seed), default 7) with its plaza trees and
## lamps, seen from a plaza's corner. Modes:
##   green  as built (the default)
##   burn   the plaza tree lit (the maze's noBurn lifted) and run to
##          half way — scorched, coals, the flame on it
##   night  the sky's light pulled down so the lamps' flares come on
##   wood   a forest floor laid over the level's south-west quarter and
##          planted by the scatter, one cell of it lit and run a while
extends SceneTree

var out := "forest_shot.png"
var mode := "green"
var forest: Forest
var view: ForestView
var lamps: Lamps
var cam: Camera3D
var frames := 0
var look := Vector2(1, 0)
var sky := 0.85

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		mode = args[1]
	var seed := int(args[2]) if args.size() > 2 else 7
	var doc := MazeMap.build(seed)
	if mode == "burn" or mode == "wood":
		doc.world["noBurn"] = false
	var lv := DocCompile.compile(doc)
	var root3 := Node3D.new()
	root.add_child(root3)
	root3.add_child(MapGeo.new(TexBank.new()).build(lv))
	U.p_seed()
	var opts := {}
	if mode == "wood":
		opts = {"rects": [Rect2(lv.bounds.position, lv.bounds.size * 0.5)], "seed": 5}
	forest = Forest.new(lv, opts)
	var t0 := Time.get_ticks_msec()
	view = ForestView.new(forest)
	root3.add_child(view)
	lamps = Lamps.new(lv)
	root3.add_child(lamps)
	print("wood: %d trees, %d plants, %d layers, %d chunks; %d lamps; drawn in %d ms" % [
		forest.tree_count(), forest.plant_count(), view.layers.size(), view.chunks.size(), lamps.count, Time.get_ticks_msec() - t0])
	# the plaza tree and where to stand: back from it toward the plaza's
	# corner, between two lamps
	var tx := forest.trees.x[0]
	var ty := forest.trees.y[0]
	var ex := tx - 330.0
	var ey := ty - 250.0
	var ez := 56.0
	if mode == "burn":
		forest.ignite(tx, ty, 20.0)
		while forest.prog[forest.trees.cell[0]] < 120:
			forest.tic()
	elif mode == "wood":
		var c := lv.bounds.get_center()
		# from above the middle of the level, looking down over the wood
		ex = c.x + 200.0
		ey = c.y + 200.0
		ez = 1100.0
		tx = c.x - 600.0
		ty = c.y - 600.0
		forest.ignite(tx, ty, 60.0)
		for i in 2400:
			forest.tic()
		print("wood burning: %d alight, %.1f%% gone" % [forest.active.size(), forest.burn_fraction() * 100.0])
	elif mode == "night":
		sky = 0.12
		RenderingServer.global_shader_parameter_set("sky_light", sky)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 2.0
	cam.far = 16000.0
	root3.add_child(cam)
	cam.position = U.v3(ex, ey, ez)
	var ang := atan2(ty - ey, tx - ex)
	look = Vector2(cos(ang), sin(ang))
	cam.rotation = Vector3(0.22 if mode != "wood" else -0.62, ang - PI / 2.0, 0.0)
	cam.make_current()

func _process(_dt: float) -> bool:
	frames += 1
	view.draw(cam.position, frames / 60.0 + 3.0)
	var n := lamps.draw(cam.position, look, sky)
	if frames == 1:
		print("flames: %d, flares: %d" % [view.flames.count if view.flames else 0, n])
	if frames == 10:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
