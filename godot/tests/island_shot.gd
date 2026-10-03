## MEWD — a picture of the guns on the island: a row of townsfolk stood
## on the slope ahead of you, then the gun held on them (the minigun by
## default) until the picture is taken — the blood, the holes in the
## ground and the gore on it, on a hillside.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
##   --resolution 1280x720 --script res://godot/tests/island_shot.gd -- out.png [GUN] [tics held] [tics after] [pitch after]
extends SceneTree

var lofi: Lofi
var game
var out := "island_shot.png"
var gun := "MINIGUN"
var hold := 90
var frames := 0
var _start := -1
var wait := 20
## where the eye is turned when the picture is taken (pitch, radians)
var look := -0.08

func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		gun = pos[1]
	if pos.size() > 2:
		hold = int(pos[2])
	if pos.size() > 3:
		wait = int(pos[3])
	if pos.size() > 4:
		look = float(pos[4])
	lofi = Lofi.new()
	root.add_child(lofi)
	var w3d := Weapon3D.new()
	lofi.gun.add_child(w3d)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.weapon3d = w3d
	lofi.world.add_child(game)
	process_frame.connect(_frame)

func _frame() -> void:
	frames += 1
	if game.player == null or not game.island_ready():
		return
	var p = game.player
	if _start < 0:
		_start = game.tics
		p.health = 100000
		p.weapon = gun
		# the longest level stretch out of the start, and the crowd along it
		var run: Vector2 = game.level.flat_run(p.x, p.y)
		p.angle = run.x
		for a in game.actors:
			if a.monster:
				a.remove()
		for k in 7:
			var d := 260.0 + k * 40.0
			var side := (k - 3) * 36.0
			var x: float = p.x + cos(run.x) * d - sin(run.x) * side
			var y: float = p.y + sin(run.x) * d + cos(run.x) * side
			game.spawn("SHOPPER" if k % 2 else "TOWNIE", x, y, run.x + PI)
		p.pitch = -0.08
	game._autofire = game.tics - _start < hold
	if game.tics - _start >= hold:
		p.pitch = look
	if game.tics - _start >= hold + wait:
		root.get_texture().get_image().save_png(out)
		print("island_shot: %s at tic %d — %d dead, %d removed, shots %d" % [gun, game.tics, game.actors.filter(func(a): return a.dead).size(),
			game.actors.filter(func(a): return a.removed).size(), int(p.shots_fired)])
		for a in game.actors.filter(func(q): return not q.removed and sqrt(U.dist2(q.x, q.y, p.x, p.y)) < 1500.0):
			print("   %s at %.0f,%.0f z %.0f (floor %.0f) dead %s" % [a.type, a.x - p.x, a.y - p.y, a.z, game.level.floor_at(a.x, a.y), a.dead])
		quit()
	if frames > 4000:
		print("island_shot: gave up")
		quit(1)
