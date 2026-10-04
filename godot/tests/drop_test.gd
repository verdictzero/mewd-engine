## MEWD — THE DROP, headless (godot/scripts/game/drop_pod.gd): the pod
## read from its file at half its size (its nozzles found, the markers
## gone), the ride down with nobody's hands on it — in fast, in the
## reentry fire, the fire out before the ground, the autopilot's suicide
## burn bringing it in under the landing speed, level, on land — nothing
## left growing through the hull, the deck a floor; the hold, the eye
## inside, the door blown (and the candy girl in its way blown apart), the
## posts round the hull, the player standing on the deck and walking out
## of the door down onto the ground; and with a hand on the stick the pod
## tilts, its RCS firing blue cones pointed out along the jet, FIRE
## lighting the orange retros. And the exhaust's and the door's own work
## on plants (VegDamage downwash, jet, sweep, clear), plant by plant.
##
##   godot --headless --script res://godot/tests/drop_test.gd -- --map=candyland
extends SceneTree

var game
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _map() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			return a.substr(6)
	return "candyland"

func _start():
	var g = preload("res://godot/scripts/game/game.gd").new()
	g.map_name = _map()
	g.drop_in = true
	root.add_child(g)
	while g.player == null or not g.island_ready():
		await process_frame
	return g

func _init() -> void:
	call_deferred("_run")

## a still cmd, with what is asked
func _cmd(o := {}) -> Dictionary:
	var c := {"fwd": 0.0, "side": 0.0, "run": false, "jump": false, "look": Vector2(), "attack": false,
		"slot": 0, "cycle": 0, "use": false}
	c.merge(o, true)
	return c

func _run() -> void:
	game = await _start()
	var um := IslandLevel.U_PER_M
	var d: DropPod = game.drop
	check(d != null and d.active and d.phase == "drop", "the game begins in the pod, dropping")
	var across: float = d.hull.get_aabb().size.x * d.model.scale.x
	check(absf(across - 3.9) < 0.2, "the pod drawn at half its size: %.1f m across" % across)
	check(d.nozzles.size() == 20, "twenty nozzles read off the model (%d)" % d.nozzles.size())
	var retros := d.nozzles.filter(func(n): return n.kind == "retro").size()
	check(retros == 8, "eight of them retros, pointing down (%d)" % retros)
	var down := true
	var low := true
	for n in d.nozzles:
		if n.kind == "retro" and n.dir.y > -0.5:
			down = false
		if n.pos.y > DropPod.TALL:
			low = false
	check(down, "and down they point")
	check(low, "every nozzle on the smaller hull")
	await process_frame
	var tiny := 0
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		if is_instance_valid(mi) and not mi.is_queued_for_deletion() and (mi as MeshInstance3D).get_aabb().size.length() < 0.5:
			tiny += 1
	check(tiny == 0, "the marker spheres are gone from the picture (%d left)" % tiny)
	check(d.altitude() > 1500.0, "the pod comes in high over the island (%.0f m)" % d.altitude())
	check(-d.vel.y > 250.0, "and fast, out of orbit (%.0f m/s)" % -d.vel.y)
	check(d.heat > 0.9, "in the reentry fire (%.2f)" % d.heat)
	var p = game.player
	check(absf(p.z - (d.pos + d.att * Vector3(0, DropPod.DECK, 0)).y * um) < 1.0, "the player rides in it, on its deck")
	# ---- the ride down, hands off ---------------------------------------
	# (in frames, the game ticking itself in its own time: the plants'
	# tiles load round the eye as it comes down, as they do in play)
	var t0: int = game.tics
	var fastest := 0.0
	var burned_at := -1.0
	var last_heat := 1.0
	var fire_out_at := -1.0
	while d.phase == "drop" and game.tics - t0 < 60 * 35:
		last_heat = d.heat
		await process_frame
		fastest = maxf(fastest, -d.vel.y)
		if d.auto_burn and burned_at < 0.0:
			burned_at = d.altitude()
		if d.phase == "drop" and d.heat <= 0.0 and fire_out_at < 0.0:
			fire_out_at = d.altitude()
	var t: int = game.tics - t0
	check(d.phase != "drop", "it comes down")
	check(t < 16 * 35, "in %.1f s (it was forty)" % (t / 35.0))
	check(fastest > 250.0 and fastest < 330.0, "falling at up to %.0f m/s" % fastest)
	check(d.max_heat > 0.9 and fire_out_at > 0.0 and last_heat <= 0.0,
		"the reentry fire burned, and was out by %.0f m, before the ground" % fire_out_at)
	check(burned_at > 0.0, "the autopilot lit the retros at %.0f m" % burned_at)
	check(d.touchdown_speed <= DropPod.DROP.land_speed + 1.0, "and landed at %.1f m/s" % d.touchdown_speed)
	check(rad_to_deg(d.tilt()) < 20.0, "near enough level (%.0f degrees)" % rad_to_deg(d.tilt()))
	check(d._ground() > IslandLevel.NO_FLOOR, "on land")
	print("  (the exhaust and the landing hurt %d plants on the way down)" % d.plants_hit)
	var vd = game.veg_damage
	if vd != null and vd.veg != null:
		var under: Array = vd.near(d.pos.x, d.pos.z, DropPod.HULL_R)
		check(under.is_empty(), "nothing left growing through the hull (%d)" % under.size())
	# THE DECK: the inside floor a floor, the ground outside the door lower
	var gx: float = d.pos.x * um
	var gy: float = -d.pos.z * um
	var deck_z: float = (d.pos.y + DropPod.DECK) * um
	check(absf(game.level.floor_at(gx, gy) - deck_z) < 1.0, "the pod's inside floor is a floor (%.0f, deck %.0f)" % [game.level.floor_at(gx, gy), deck_z])
	# ---- the hold, the eye inside, the door ----------------------------
	while d.phase == "landed":
		game.tic()
	game.tic()
	check(d.phase == "inside" and not d.third_person(), "then the eye is inside the pod, first person")
	check(d.holds_player(), "and you cannot walk yet")
	check(absf(p.z - deck_z) < 1.0 and absf(p.view_z - (deck_z + U.PLAYER_EYE)) < 1.0,
		"standing on the deck, the eye %.1f m over it (not in the floor)" % ((p.view_z - deck_z) / um))
	var dd := d.door_dir()
	var dv := Vector2(dd.x, -dd.z).normalized()
	var outside: Vector2 = Vector2(gx, gy) + dv * (DropPod.HULL_R + 0.6) * um
	var ground_there: float = game.level.ground.height(outside.x / um, -outside.y / um) * um
	check(absf(game.level.floor_at(outside.x, outside.y) - ground_there) < 0.5, "and outside the door the floor is the ground again")
	check(d.door_posts.size() == 3, "the doorway shut by posts until the door is off")
	# somebody standing in the door's way, just before it goes
	while d.phase == "inside" and d.phase_tics < DropPod.DROP.door_tics - 1:
		game.tic()
	var girl_at: Vector2 = Vector2(gx, gy) + dv * (DropPod.HULL_R + 1.4) * um
	var girl = game.spawn("CANDYGIRL", girl_at.x, girl_at.y, 0.0)
	var pz: float = p.z
	for k in 6:
		game.tic()
	check(d.phase == "out", "the door blows off")
	check(not d.holds_player(), "and you are free")
	check(absf(p.z - pz) < 2.0 and absf(p.z - deck_z) < 2.0, "standing on the pod's floor")
	check(d.blockers.size() >= 16 and d.blockers.size() < DropPod.BLOCKERS, "a ring of posts round the hull with a gap for the door (%d)" % d.blockers.size())
	check(d.door_posts.is_empty(), "the doorway open")
	for k in 40:
		game.tic()
	check(girl.dead or girl.removed, "the candy girl in its way blown apart (%d hit)" % d.door_kills)
	for k in 50:
		game.tic()
	check(d.door_down, "the door is down on the ground")
	check(not p.dead and p.health > 0, "and you are alive")
	# OUT OF THE DOOR: turned to it and walking, down off the deck
	p.angle = d.door_angle()
	for k in 50:
		p.tic(_cmd({"fwd": 1.0}))
	var out_r := Vector2(p.x - gx, p.y - gy).length() / um
	var f_here: float = game.level.floor_at(p.x, p.y)
	check(out_r > DropPod.HULL_R + 0.3, "you walk out of the door (%.1f m from the middle)" % out_r)
	check(absf(p.z - f_here) < 2.0 and absf(f_here - game.level.ground.height(p.x / um, -p.y / um) * um) < 0.5,
		"and stand on the ground there, off the deck")
	# ---- the exhaust and the door against plants, plant by plant -------
	if vd != null and vd.veg != null:
		# four plants well apart, and away from the pod (what one is done
		# to must not reach the next)
		var pool: Array = []
		for q in vd.near(d.pos.x, d.pos.z, 400.0):
			if q.h <= 1.5 or Vector2(q.pos.x - d.pos.x, q.pos.z - d.pos.z).length() < 30.0:
				continue
			var apart := true
			for o in pool:
				if Vector2(q.pos.x - o.pos.x, q.pos.z - o.pos.z).length() < 60.0:
					apart = false
			if apart:
				pool.append(q)
			if pool.size() == 4:
				break
		check(pool.size() >= 4, "plants to try them on, well apart (%d)" % pool.size())
		if pool.size() >= 4:
			# the downwash from three metres over its top, hard
			var q0: Dictionary = pool[0]
			var over := VegDamage.to_game(q0.pos + Vector3(0.0, q0.h + 3.0, 0.0))
			var n0: int = vd.downwash(over, 2.0 * um, 0.45, 30.0 * um, 30.0)
			check(n0 >= 1 and _hurt(vd, q0), "the retros' downwash into a plant's top shreds it (%d touched)" % n0)
			# an RCS jet aimed down through a plant's middle from four metres
			# off and two up (level, on a slope, it can start in the ground)
			var q1: Dictionary = pool[1]
			var mid := VegDamage.to_game(q1.pos + Vector3(0.0, q1.h * 0.5, 0.0))
			var from := mid + Vector3(4.0 * um, 0.0, 2.0 * um)
			var n1: int = vd.jet(from, (mid - from).normalized(), 7.0 * um, 2.0 * um, 30.0)
			check(n1 >= 1 and _hurt(vd, q1), "an RCS jet through a plant hurts it (%d touched)" % n1)
			# the door through one
			var q2: Dictionary = pool[2]
			var n2: int = vd.sweep(VegDamage.to_game(q2.pos + Vector3(0.0, q2.h * 0.4, 0.0)), DropPod.DOOR_HIT_R * um, mid)
			check(n2 >= 1 and _gone(vd, q2), "the door through a plant shreds it")
			# and where a pod comes down, everything
			var q3: Dictionary = pool[3]
			var n3: int = vd.clear(VegDamage.to_game(q3.pos), DropPod.HULL_R * um)
			check(n3 >= 1 and _gone(vd, q3), "where a pod comes down, nothing left standing")
	# ---- hands on: the pod tilts, the RCS fires ------------------------
	game.queue_free()
	await process_frame
	game = await _start()
	d = game.drop
	var f0: int = d.fires
	var tilt0: float = d.tilt()
	for k in 50:
		d.tic({"fwd": 1.0, "side": 0.0, "look": Vector2(), "attack": false})
	check(d.fires > f0, "a hand on the stick fires the RCS (%d firings)" % (d.fires - f0))
	check(rad_to_deg(d.tilt()) > rad_to_deg(tilt0) + 5.0, "and the pod tilts (%.0f degrees)" % rad_to_deg(d.tilt()))
	var rcs_only := true
	for i in d.nozzles.size():
		if d.fired[i] > 0.0 and d.nozzles[i].kind != "rcs":
			rcs_only = false
	check(rcs_only, "with the RCS nozzles, not the retros")
	# the RCS flames: blue, wide at the nozzle, pointed out along the jet
	# (the transform and colour the MultiMesh is given: a headless run has
	# no renderer to read them back from)
	var out_ok := true
	var blue := true
	var lit := 0
	for i in d.nozzles.size():
		if d.fired[i] <= 0.01 or d.nozzles[i].kind != "rcs":
			continue
		lit += 1
		var tf: Transform3D = d.flame_transform(i, d.fired[i])
		if tf.basis.y.normalized().dot(d.nozzles[i].dir) < 0.95:
			out_ok = false
		if (tf.origin - d.nozzles[i].pos).dot(d.nozzles[i].dir) <= 0.0:
			out_ok = false
		var c: Color = DropPod._flame_color(d.nozzles[i].kind)
		if not (c.b > c.r and c.a < 0.5):
			blue = false
	check(lit > 0 and out_ok, "the RCS cones' points out along the jet, their bases at the nozzles (%d lit)" % lit)
	check(lit > 0 and blue, "and blue")
	var v0: float = d.vel.y
	for k in 20:
		d.tic({"fwd": 0.0, "side": 0.0, "look": Vector2(), "attack": true})
	check(d.retro_level > 0.9 and d.vel.y > v0, "FIRE lights the retros and the fall slows")
	var back_ok := true
	for i in d.nozzles.size():
		if d.nozzles[i].kind != "retro":
			continue
		var tf: Transform3D = d.flame_transform(i, 1.0)
		var c: Color = DropPod._flame_color("retro")
		if tf.basis.y.normalized().dot(d.nozzles[i].dir) > -0.95 or not (c.r > c.b and c.a > 0.5):
			back_ok = false
	check(back_ok, "the retros orange plumes spreading from the nozzle, as they were")
	print("drop: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)

## the plant `q` as it stands now: hurt (its count up) or gone
func _hurt(vd, q: Dictionary) -> bool:
	var now: Dictionary = vd._plant(q.tile, q.sprite, q.row)
	return now.gone or now.custom.y > q.custom.y

func _gone(vd, q: Dictionary) -> bool:
	var now: Dictionary = vd._plant(q.tile, q.sprite, q.row)
	return now.gone
