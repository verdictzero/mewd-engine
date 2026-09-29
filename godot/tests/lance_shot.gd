## MEWD — a picture of the positron lance, for looking at without playing.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/lance_shot.gd -- out.png [mode] [--seed=N]
##
## The picture's real layers (Lofi, the gun's world, the Game with the
## lance), the maze, the player turned down the
## longest clear run with three shoppers along it, the LANCE in hand, and
## then by `mode`:
##   charge  the trigger held seven seconds and a bit: the dial red, the
##           window at the top draining, the lens lit
##   aim     the same, with the gun raised to the eye (one ZOOM press)
##   fire    let go: a few tics into the discharge, looking down the line
##   side    let go, and the head turned to see the column in profile
##   above   let go, and the eye lifted over the hedges behind the muzzle
##   sear    the discharge over, walked up to the wall it landed on
extends SceneTree

var lofi: Lofi
var game
var w3d: Weapon3D
var out := "lance_shot.png"
var mode := "fire"
var frames := 0
var run := Vector2()
var start := Vector2()

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pos := []
	for a in args:
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		mode = pos[1]
	lofi = Lofi.new()
	root.add_child(lofi)
	if OS.get_environment("LOFI_OFF") != "":
		lofi.set_filtered(false)
		lofi.pixel_rows = 0
		lofi.pixel_aspect = 1.0
	w3d = Weapon3D.new()
	lofi.gun.add_child(w3d)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.weapon3d = w3d
	lofi.world.add_child(game)
	process_frame.connect(_frame)

func _clear_run(p) -> Vector2:
	var best := Vector2()
	for k in 4:
		var ang := k * PI / 2.0
		var hit: Dictionary = game.level.ray_hit_wall(p.x, p.y, 30, p.x + cos(ang) * 2000.0, p.y + sin(ang) * 2000.0, 30)
		var l: float = 2000.0 * float(hit.t) if not hit.is_empty() else 2000.0
		if l > best.y:
			best = Vector2(ang, l)
	return best

func _tics(n: int, attack: bool) -> void:
	game._autofire = attack
	for i in n:
		game.tic()
	game._autofire = false

func _frame() -> void:
	frames += 1
	var p = game.player
	if frames == 2:
		p.weapon = "LANCE"
		run = _clear_run(p)
		start = Vector2(p.x, p.y)
		for a in game.actors:
			if a.monster:
				a.remove()
		for k in 3:
			var d := minf(260.0 + k * 170.0, run.y - 60.0)
			game.spawn("SHOPPER", p.x + cos(run.x) * d + sin(run.x) * (k - 1) * 14.0, p.y + sin(run.x) * d - cos(run.x) * (k - 1) * 14.0, run.x + PI, {"variant": k})
		p.angle = run.x
		p.pitch = float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else 0.0
	if frames == 8:
		# seven seconds and a bit of trigger
		_tics(7 * 35 + 20, true)
		if mode in ["charge", "aim"]:
			game._autofire = true     # and keep holding it
		if mode == "aim":
			game._zoom = true
	if frames == 10 and mode in ["fire", "side", "sear", "above"]:
		_tics(1, false)       # let go
		_tics(5, false)
		if mode == "side":
			p.angle = run.x - 0.7
			p.prev = Vector4(p.x, p.y, p.view_z, 0)
		if mode == "above":
			# the eye lifted over the hedges and back from the muzzle,
			# looking down the line: the column in profile
			p.x -= cos(run.x) * 60.0
			p.y -= sin(run.x) * 60.0
			p.z += 700.0
			p.view_z += 700.0
			p.on_ground = false
			p.momz = 0.0
			p.pitch = -0.72
			p.prev = Vector4(p.x, p.y, p.view_z, 0)
			game.player.dead = false
		if mode == "sear":
			# long enough for the smoke to go and the crater to cool a little
			_tics(int(OS.get_environment("SEAR_TICS")) if OS.get_environment("SEAR_TICS") != "" else 60, false)
			# walk up to the wall it landed on
			var h: Dictionary = game.beam.hit
			if not h.is_empty():
				p.x = h.at.x - cos(run.x) * 260.0
				p.y = h.at.y - sin(run.x) * 260.0
				p.sector = game.level.sector_at(p.x, p.y)
				p.prev = Vector4(p.x, p.y, p.view_z, 0)
				p.pitch = -0.1 if absf(h.n.z) < 0.5 else -0.6
				if absf(h.n.z) > 0.5:
					p.x = h.at.x - cos(run.x) * 200.0
					p.y = h.at.y - sin(run.x) * 200.0
					p.prev = Vector4(p.x, p.y, p.view_z, 0)
	var at := 40 if mode in ["charge", "aim"] else 13
	if frames == at:
		print("lance_shot: %s — charge %d stage %d, beam live %s stage %d, killed %d, sears %d slags %d, scope renders %d draws %d, aim %.2f" % [
			mode, p.charge, p.charge_stage(), game.beam.live, game.beam.stage, game.beam.killed,
			game.decals.sears, game.decals.slags, game.scope.renders, game.scope.draws, w3d.aim])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out)
		quit()
