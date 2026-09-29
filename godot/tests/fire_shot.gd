## MEWD — a picture of the fire, for looking at without the game.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/fire_shot.gd -- out.png [tics]
##
## The maze with its paths made of stock, a bottle's worth of fire at the
## START and another down the path, run for `tics` (default 600) and
## drawn by FireSprites from just behind the start.
extends SceneTree

class StubGame:
	var level: Level
	var actors: Array = []
	var player = null
	var tics := 0

var out := "fire_shot.png"
var fire: FireSystem
var sprites: FireSprites
var cam: Camera3D
var frames := 0
var tic_count := 600

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		tic_count = int(args[1])
	var doc := MazeMap.build(7)
	for s in doc.sectors:
		if s.get("name", "") == "path":
			s["fuel"] = 300
	var g := StubGame.new()
	g.level = DocCompile.compile(doc)
	var root3 := Node3D.new()
	root.add_child(root3)
	root3.add_child(MapGeo.new(TexBank.new()).build(g.level))
	var start = null
	for t in g.level.things:
		if t.type == "START":
			start = t
	var sx := float(start.x)
	var sy := float(start.y)
	U.p_seed()
	fire = FireSystem.new(g)
	var t0 := Time.get_ticks_msec()
	fire.ignite(sx + 60, sy + 60, 190, 68)
	fire.ignite(sx + 200, sy + 30, 190, 68)
	for t in tic_count:
		fire.tic()
	print("fire: %d tics in %d ms, %d hot, %d live" % [tic_count, Time.get_ticks_msec() - t0, fire.hot_cells, fire.active.size()])
	t0 = Time.get_ticks_msec()
	sprites = FireSprites.new()
	root3.add_child(sprites)
	print("flame art ready in %d ms" % (Time.get_ticks_msec() - t0))
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 2.0
	cam.far = 16000.0
	root3.add_child(cam)
	cam.position = U.v3(sx - 40, sy - 40, 49)
	cam.rotation = Vector3(-0.05, PI / 4 - PI / 2, 0.0)
	cam.make_current()

func _process(_dt: float) -> bool:
	frames += 1
	sprites.draw(fire, cam.position, float(tic_count + frames))
	if frames == 1:
		var n := 0
		for b in sprites.batches:
			n += b.n
		print("flames drawn: %d" % n)
	if frames == 8:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
