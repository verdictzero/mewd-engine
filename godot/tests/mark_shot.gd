## MEWD — a picture of every mark the game lays, on the island's ground:
## a row of holes, hot holes and a scorch, blood and gore, a hot spot, a
## sear and its slag, a rocket's crater and a potato's glass, laid on the
## slope ahead of you and looked down on — to see the projected decals
## lie on the ground as it lies.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
##   --resolution 1280x720 --script res://godot/tests/mark_shot.gd -- out.png [pitch] [distance] [--nograss] [--under]
extends SceneTree

var lofi: Lofi
var game
var out := "mark_shot.png"
var look := -0.6
var dist := 200.0
var _start := -1

func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		look = float(pos[1])
	if pos.size() > 2:
		dist = float(pos[2])
	lofi = Lofi.new()
	root.add_child(lofi)
	game = preload("res://godot/scripts/game/game.gd").new()
	lofi.world.add_child(game)
	process_frame.connect(_frame)

## a point `d` ahead of you and `side` across, on the ground
func _on(p, d: float, side: float) -> Vector3:
	var x: float = p.x + cos(p.angle) * d - sin(p.angle) * side
	var y: float = p.y + sin(p.angle) * d + cos(p.angle) * side
	return Vector3(x, y, game.level.floor_at(x, y))

func _frame() -> void:
	if game.player == null or not game.island_ready():
		return
	var p = game.player
	p.pitch = look
	if _start < 0:
		_start = game.tics
		p.health = 100000
		# (--nograss: the grass and the plants off, to see the marks under it)
		if "--nograss" in OS.get_cmdline_user_args():
			game.island.get_node("GrassScatter").visible = false
			game.island.get_node("VegScatter").visible = false
		# down the longest level stretch out of the start
		p.angle = game.level.flat_run(p.x, p.y).x
		for a in game.actors:
			if a.monster:
				a.remove()
		var d: Decals = game.decals
		var g = game.gore_decals
		var up := Vector3(0, 0, 1)
		# near row: holes, hot holes, blood
		for k in 6:
			d.hole(_on(p, dist - 50.0, (k - 2.5) * 22.0), up, k % 2 == 1)
		for k in 3:
			g.blood(_on(p, dist - 20.0, (k - 1) * 60.0), up, Vector3(cos(p.angle), sin(p.angle), 0), 30.0)
		g.pool(_on(p, dist + 10.0, -90.0).x, _on(p, dist + 10.0, -90.0).y, _on(p, dist + 10.0, -90.0).z, 50.0)
		# middle: heat into a scorch, a sear and its slag
		for k in 30:
			d.heat(_on(p, dist + 20.0, 0.0), up)
		d.sear(_on(p, dist + 20.0, 90.0), up, 70.0, Vector3(cos(p.angle), sin(p.angle), 0))
		d.slag(_on(p, dist + 20.0, 150.0), up, 40.0)
		# far: a rocket's crater and a potato's glass
		d.blast(_on(p, dist + 160.0, -120.0), up)
		d.nuke(_on(p, dist + 220.0, 160.0), up, 220.0)
		# (--under: a crater at your feet too, the eye inside its box)
		if "--under" in OS.get_cmdline_user_args():
			d.blast(_on(p, 40.0, 0.0), up)
	if game.tics - _start >= 20:
		root.get_texture().get_image().save_png(out)
		print("mark_shot: %s, looking %.2f" % [out, look])
		quit()
	if game.tics - _start > 4000:
		quit(1)
