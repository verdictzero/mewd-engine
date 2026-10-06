## MEWD — pictures of the rocket and the cerebral bore in flight
## (render/projectile_models.gd).
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
##   --resolution 1280x720 --script res://godot/tests/projectile_shot.gd -- out.png [mode]
##
## THE ANNEXE's yard, a shopper far out in front, and by `mode`:
##   rocket  four missiles locked on them, seen from beside their path
##   bore    a bore after their head, seen from beside its path
##   drill   the same, in the head
extends SceneTree

var lofi: Lofi
var game
var w3d: Weapon3D
var out := "projectile_shot.png"
var mode := "rocket"
var frames := 0
var fired_tic := -1
var shopper = null

func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		mode = pos[1]
	lofi = Lofi.new()
	root.add_child(lofi)
	w3d = Weapon3D.new()
	lofi.gun.add_child(w3d)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.weapon3d = w3d
	lofi.world.add_child(game)
	process_frame.connect(_frame)

func _frame() -> void:
	frames += 1
	if game.player == null:
		return
	var p = game.player
	if frames == 5:
		p.weapon = "LAUNCHER" if mode == "rocket" else "BORE"
		# (tanks kept full: they run dry now, at the user's request)
		p.debug = true
		p.x = 200.0
		p.y = 520.0
		p.angle = 0.0
		p.pitch = 0.0
		p.health = 100000
		p.ammo.rockets = 99
		shopper = game.spawn("SHOPPER", 680.0, 520.0, PI)
		shopper.speed = 0.0
	if frames == 30:
		# slowed right down, so a frame here is a fraction of a tic and the
		# eye keeps up with what it is following
		Engine.time_scale = 0.12
		fired_tic = game.tics
		if mode == "rocket":
			for tube in 4:
				game.missiles.launch(p, shopper, tube)
		else:
			game.bore.lock = shopper
			game.bore.fire(p)
	if fired_tic < 0:
		return
	# from beside the path, a little ahead of where the shots are
	var lead = game.missiles.shots[0] if mode == "rocket" and not game.missiles.shots.is_empty() else null
	if mode != "rocket" and not game.bore.shots.is_empty():
		lead = game.bore.shots[0]
	if mode == "drill":
		lead = {"x": shopper.x - 30.0, "y": shopper.y - 20.0}
	if lead != null:
		p.x = lead.x + 10.0
		p.y = lead.y + (60.0 if mode != "rocket" else 90.0)
		p.angle = -PI / 2.0 - 0.25
		p.pitch = -0.05
	var ready: bool
	match mode:
		"rocket":
			ready = game.tics >= fired_tic + 9
		"bore":
			ready = game.tics >= fired_tic + 12
		_:
			ready = game.bore.drilling.size() > 0 and game.bore.drilling[0].spin > 30
	if ready:
		root.get_texture().get_image().save_png(out)
		print("projectile_shot: %s at frame %d — missiles %d, bores %d, drilling %d" % [mode, frames, game.missiles.shots.size(), game.bore.shots.size(), game.bore.drilling.size()])
		quit()
	if frames > 900:
		print("projectile_shot: gave up")
		quit(1)
