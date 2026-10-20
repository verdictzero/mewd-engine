## MEWD — pictures of the fetus launcher (game/fetuses.gd), on an island.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --resolution 1280x720 \
##   --script res://godot/tests/fetus_shot.gd -- --map=candyland out.png MODE [TICS]
##
## The launcher in hand, and by MODE:
##   hold    the gun at rest, its jar full and beating
##   empty   the gun a few tics after a shot: the jar emptied, growing back
##   flight  a fetus TICS tics out (6), seen from behind down its path
##   side    the same, from 5 m beside its path, turned to it
##   splat   into a candy girl 7 m ahead, TICS tics after it lands (4)
##   after   the same, TICS tics after (70): what is left
## --hud: the readout over it. --rocket (splat, after): a rocket's warhead
## in the candy girl instead, to compare.
##   holds   the gun at rest held each way --try= lists ("out,x,y,rx,ry,rz;
##           ..."), out_0.png, out_1.png ... (for finding its hold)
extends SceneTree

var lofi: Lofi
var game
var w3d: Weapon3D
var out := "fetus_shot.png"
var mode := "hold"
var after := -1
var _start := -1
var _fired := -1
var _landed := -1
var _done := false
var girl = null

func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		mode = pos[1]
	if pos.size() > 2:
		after = int(pos[2])
	if after < 0:
		after = {"flight": 6, "side": 7, "splat": 4, "after": 70, "empty": 8}.get(mode, 0)
	lofi = Lofi.new()
	root.add_child(lofi)
	w3d = Weapon3D.new()
	lofi.gun.add_child(w3d)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.weapon3d = w3d
	lofi.world.add_child(game)
	# --hud: the readout over it all (the gun's name, the fetuses left)
	if "--hud" in OS.get_cmdline_user_args():
		var hl := CanvasLayer.new()
		hl.layer = 1
		root.add_child(hl)
		var hud := Hud.new()
		hud.game = game
		hl.add_child(hud)
		game.hud = hud
	process_frame.connect(_frame)

func _frame() -> void:
	if _done or game.player == null or not game.island_ready():
		return
	var p = game.player
	var F: FetusLauncher = game.fetuses
	if _start < 0:
		_start = game.tics
		p.health = 100000
		p.debug = true
		p.weapon = "FETUS"
		p.pitch = 0.02
		lofi.for_island(game.island_spec, true)
		# (the crowd that greets you cleared off, to see the shot fly)
		if mode in ["flight", "side", "empty"]:
			for a in game.actors.duplicate():
				if a.type == "CANDYGIRL" and not a.removed:
					a.remove()
			p.pitch = 0.12
		if mode in ["splat", "after"]:
			girl = game.spawn("CANDYGIRL", p.x + cos(p.angle) * 7.0 * 32.0, p.y + sin(p.angle) * 7.0 * 32.0, p.angle + PI)
			if girl != null:
				girl.speed = 0.0
	# (keep the girl where she was put, facing you)
	if girl != null and not girl.dead and _fired < 0:
		girl.x = p.x + cos(p.angle) * 7.0 * 32.0
		girl.y = p.y + sin(p.angle) * 7.0 * 32.0
		girl.momx = 0.0
		girl.momy = 0.0
	var t: int = game.tics - _start
	if mode == "holds":
		_holds(t)
		return
	if t >= 30 and _fired < 0 and mode != "hold":
		if girl != null:
			# down the sight at her middle
			var dz: float = girl.z + girl.height * 0.5 - p.eye_z()
			p.pitch = atan2(dz, 7.0 * 32.0) + 0.02
		p.fire_index = -1
		if "--rocket" in OS.get_cmdline_user_args() and girl != null:
			# (the same, a rocket's warhead in her instead: to compare)
			game.missiles.detonate(Vector3(girl.x, girl.y, girl.z + 20.0), girl)
			F.splats += 1
		else:
			F.launch(p)
		_fired = game.tics
	if mode == "side" and _fired >= 0 and not F.shots.is_empty():
		var s: Dictionary = F.shots[0]
		if not has_meta("moved"):
			set_meta("moved", true)
			var a: float = p.angle + PI / 2.0
			p.x += cos(a) * 5.0 * 32.0
			p.y += sin(a) * 5.0 * 32.0
		p.angle = atan2(s.y - p.y, s.x - p.x)
		p.pitch = atan2(s.z - p.eye_z(), sqrt(U.dist2(s.x, s.y, p.x, p.y)))
	if _landed < 0 and F.splats > 0:
		_landed = game.tics
	var ready := false
	match mode:
		"hold":
			ready = t >= 40
		"flight", "side", "empty":
			ready = _fired >= 0 and game.tics - _fired >= after
		"splat", "after":
			ready = _landed >= 0 and game.tics - _landed >= after
	if ready:
		_done = true
		root.get_texture().get_image().save_png(out)
		print("fetus_shot: %s — fired %d, in the air %d, splats %d, kills %d, gore in the air %d, picture pieces %d" % [mode,
			F.fired, F.shots.size(), F.splats, F.kills, game.giblets.live_count(), game.chunks.count()])
		quit()
	if t > 900:
		print("fetus_shot: gave up (fired %d, splats %d)" % [F.fired, F.splats])
		quit(1)

var _try := -1
var _try_frame := 0

func _holds(t: int) -> void:
	if t < 30:
		return
	var spec := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--try="):
			spec = a.substr(6)
	var tries := spec.split(";", false)
	_try_frame += 1
	if _try_frame % 4 != 0:
		return
	if _try >= 0:
		root.get_texture().get_image().save_png(out.replace(".png", "_%d.png" % _try))
	_try += 1
	if _try >= tries.size():
		_done = true
		quit()
		return
	var v := tries[_try].split(",")
	var G: Dictionary = w3d.guns["FETUS"]
	var d: Dictionary = (G.def as Dictionary).duplicate(true)
	d.out = float(v[0])
	d.pos = [float(v[1]), float(v[2]), 0.0]
	d.rot = [float(v[3]), float(v[4]), float(v[5])]
	G.def = d
	print("fetus_shot: hold %d = %s" % [_try, tries[_try]])
