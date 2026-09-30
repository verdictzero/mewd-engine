## MEWD — the escalation, on the maze: a shot fired, the SWAT sent, the
## vans driving in, parking, and their crews stepping out.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/responders_test.gd -- out.png [mode] [tics]
##
## The maze says world.noSquads, as the JS maze does, and has no road —
## so this turns the one off and lays the other: a perimeter "ring"
## inset round one of the plazas, and a way in from each side of it
## (world.swatRing, world.swatRoutes, the map's own keys). The player
## stands in the plaza, fires once, and the night is ticked.
##
## Modes:
##   swat    (default, 330 tics) asserts a van arrived and parked and
##           troops unloaded, and draws the vans from beside the player
##   boom    a van shot through its armour and then charred to the end:
##           asserts the blockers took the rounds, that it went up,
##           tumbled and came down a wreck, and draws it in the air
##   army    the SWAT pressure pushed to the army's threshold: asserts an
##           APC came, hovering, and draws it
extends SceneTree

var out := "responders.png"
var mode := "swat"
var tic_count := 330
var game
var esc: Escalation
var frames := 0
var look_at := Vector3()
var cam_from := Vector3()
var plaza: Rect2

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		mode = args[1]
	if args.size() > 2:
		tic_count = int(args[2])
	elif mode == "boom":
		tic_count = 0
	elif mode == "army":
		tic_count = 260
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	game.name = "Game"
	root.add_child(game)

## after the game's own _ready has built the maze
func _setup() -> void:
	game.set_process(false)
	var lv: Level = game.level
	# ---- THE SQUADS ARE ON, for the test
	lv.world["noSquads"] = false
	# ---- the biggest plaza, and a ring inset round it
	var best: Level.Sector = null
	for s in lv.sectors:
		if s.name == "plaza" and (best == null or s.bbox.get_area() > best.bbox.get_area()):
			best = s
	assert(best != null, "the maze has a plaza")
	plaza = best.bbox
	var r := plaza.grow(-90.0)
	var cx := plaza.get_center().x
	var cy := plaza.get_center().y
	lv.world["swatRing"] = [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
	lv.world["swatRoutes"] = {
		"west": [{"x": plaza.position.x + 40.0, "y": cy + 60.0}, {"x": r.position.x, "y": cy + 60.0}],
		"east": [{"x": plaza.end.x - 40.0, "y": cy - 60.0}, {"x": r.end.x, "y": cy - 60.0}],
	}
	# ---- the player in the plaza, a little off its middle (the tree)
	var p = game.player
	p.x = cx - 150.0
	p.y = cy - 120.0
	p.sector = lv.sector_at(p.x, p.y)
	p.z = p.sector.floor
	p.view_z = p.z + U.PLAYER_EYE
	p.angle = 0.0
	# and not killed by the crews while the test runs
	p.health = 1000000
	# everybody else out of the plaza, so the picture is the vans
	for a in game.actors:
		if plaza.grow(64).has_point(Vector2(a.x, a.y)):
			a.remove()
	game.blockmap = ActorGrid.new()
	for a in game.actors:
		if not a.removed and a.solid:
			game.blockmap.add(a)
	esc = Escalation.new(game)
	game.add_child(esc)
	print("responders: plaza %s, ring %s, player at (%d, %d)" % [plaza, r, p.x, p.y])
	match mode:
		"boom": _boom()
		"army": _army()
		_: _swat()

func _tic() -> void:
	game.tic()
	esc.tic()

func _swat() -> void:
	var t0 := Time.get_ticks_msec()
	var R := esc.responders
	game.player.shots_fired += 1
	var first_park := -1
	var first_troop := -1
	for t in tic_count:
		_tic()
		if first_park < 0:
			for v in R.vans:
				if v.state == "parked":
					first_park = R.tics
		if first_troop < 0 and R.troopers() > 0:
			first_troop = R.tics
	var parked := R.vans.filter(func(v): return v.state == "parked")
	print("responders: %d tics in %d ms — called %s at %d, pressure %.2f, %d vans (%d parked, first at tic %d), %d troopers on their feet (first at tic %d), %d spawned" % [
		tic_count, Time.get_ticks_msec() - t0, R.called(), R.swat.calledAt, R.pressure(), R.vans.size(), parked.size(),
		first_park, R.troopers(), first_troop, R.spawned()])
	for v in R.vans:
		print("  van %s at (%d, %d) yaw %.2f, driven %d, blockers %d" % [v.state, v.x, v.y, v.yaw, v.driven, v.blockers.size()])
	assert(R.called(), "one shot calls the SWAT")
	assert(R.vans.size() >= 1, "a van was sent")
	assert(parked.size() >= 1, "a van arrived and parked")
	assert(R.troopers() >= 1, "troops unloaded")
	var v = parked[0]
	_frame_on(Vector3(v.x, v.y, v.ground + 40.0))

func _army() -> void:
	var R := esc.responders
	# the SWAT stay home for this one (no van to come in), so the ring is
	# the army's: the plaza's ring is too small for both
	esc._models["police"] = null
	game.player.shots_fired += 1
	_tic()
	# push the SWAT's curve to the army's threshold: called one doubling ago
	R.swat.calledAt -= int(Responders.SWAT.doubling)
	for t in tic_count:
		_tic()
	var apcs := R.vans.filter(func(v): return v is ArmyApc)
	print("responders: army called %s, %d APCs, %d soldiers" % [R.army.called, apcs.size(), R.troopers_of(R.army)])
	assert(R.army.called, "the army is called at twice the pressure")
	assert(apcs.size() >= 1, "an APC was sent")
	var a = apcs[0]
	print("  apc %s at (%d, %d), hover %.1f, cz %.1f over ground %.1f" % [a.state, a.x, a.y, a.hover, a.cz, a.ground])
	assert(a.cz - a.ground > a.def.car_height() / 2.0 + 20.0, "it floats")
	_frame_on(Vector3(a.x, a.y, a.ground + 50.0))

func _boom() -> void:
	var R := esc.responders
	game.player.shots_fired += 1
	var v = null
	for t in 400:
		_tic()
		for w in R.vans:
			if w.state == "parked":
				v = w
				break
		if v != null:
			break
	assert(v != null, "a van parked")
	# a round into the middle third of it: the CARBODY hands it on
	var h0: float = v.health
	var b: Actor = v.blockers[1]
	b.damage(500.0, game.player, {"shot": true})
	print("responders: 500 of rounds took %.1f off the van (armour %d)" % [h0 - v.health, v.shot_armour])
	assert(absf((h0 - v.health) - 500.0 / v.shot_armour) < 0.01, "a shot at a blocker is a shot at the van")
	# and then through its health, and the char run to its end
	v.damage(10000.0, null, {})
	assert(v.state == "charring")
	var went_up := false
	var peak := 0.0
	var air_tic := -1
	for t in 2000:
		_tic()
		if v.state == "air":
			went_up = true
			peak = maxf(peak, v.cz - v.ground)
			if air_tic < 0:
				air_tic = t
		if went_up and air_tic >= 0 and t == air_tic + 14:
			break
	print("responders: went up %s, %.1f over the ground at tic %d of the air, rx %.2f, %d chunks flying" % [went_up, peak, 14, v.rx, esc.vehicles.flying.size()])
	assert(went_up, "a charred van goes up")
	# from across the plaza, toward its middle, looking up at it
	var toward := (plaza.get_center() - Vector2(v.x, v.y)).normalized()
	cam_from = Vector3(v.x + toward.x * 620.0, v.y + toward.y * 620.0, v.ground + 70.0)
	_frame_on(Vector3(v.x, v.y, v.cz - 40.0))

## the camera: from beside the player unless told otherwise, at what matters
func _frame_on(at: Vector3) -> void:
	look_at = at
	if cam_from == Vector3():
		var p = game.player
		var d := Vector2(at.x - p.x, at.y - p.y)
		var back := d.normalized() * -120.0
		cam_from = Vector3(p.x + back.x - d.normalized().y * 60.0, p.y + back.y + d.normalized().x * 60.0, p.z + 70.0)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 1:
		_setup()
		return false
	game._process(0.0)
	esc.draw()
	var cam: Camera3D = game.camera
	cam.position = U.v3(cam_from.x, cam_from.y, cam_from.z)
	cam.look_at(U.v3(look_at.x, look_at.y, look_at.z), Vector3.UP)
	if frames == 8:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false
