## MEWD — THE DROP, headless (godot/scripts/game/drop_pod.gd): the pod
## read from its file at half its size (its nozzles found, the markers
## gone), the ride down with nobody's hands on it — in fast, in the
## reentry fire, the fire out before the ground, the autopilot's suicide
## burn bringing it in under the landing speed, level, on land — nothing
## left growing through the hull, the deck a floor; the hold, the eye
## inside, the door blown (and the candy girl in its way blown apart), the
## posts round the hull, the player standing on the deck and walking out
## of the door down onto the ground; and (the RCS off for now, at the
## user's request) straight down over the start, 2.5 times as fast, in the
## fire three quarters of the way, a hand on the stick doing nothing; the
## retros' jets blue shock diamonds. And the exhaust's and the door's own work
## on plants (VegDamage downwash, jet, sweep, clear), plant by plant.
##
##   godot --headless --script res://godot/tests/drop_test.gd -- --map=candyland
extends SceneTree

var game
var fails := 0

## the plants' micro-queue run down (VegDamage.BLOW_PER_TIC a tic)
func _drain(vd) -> void:
	for k in 12:
		vd.tic()

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
	check(d.altitude() > 1300.0, "the pod comes in high over the island (%.0f m)" % d.altitude())
	check(-d.vel.y > 120.0, "and fast, out of orbit (%.0f m/s)" % -d.vel.y)
	check(d.heat > 0.9, "in the reentry fire (%.2f)" % d.heat)
	var p = game.player
	check(absf(p.z - (d.pos + d.att * Vector3(0, DropPod.DECK, 0)).y * um) < 1.0, "the player rides in it, on its deck")
	# ---- the ride down, hands off ---------------------------------------
	# (in frames, the game ticking itself in its own time: the plants'
	# tiles load round the eye as it comes down, as they do in play)
	# and somebody waiting where it will come down: three candy girls and a
	# unicorn a few metres off the spot, and one girl right under it
	var waiting := []
	for k in 4:
		var a := k * TAU / 4.0 + 0.4
		var w := Vector2(d.start.x, d.start.y) + Vector2(cos(a), sin(a)) * (4.0 + k) * um
		var who = game.spawn("UNICORN" if k == 3 else "CANDYGIRL", w.x, w.y, 0.0)
		if who != null:
			waiting.append(who)
	var squash_me = game.spawn("CANDYGIRL", d.start.x + 0.5 * um, d.start.y, 0.0)
	var early := 0
	var t0: int = game.tics
	var burn_start_tic := 0
	var fastest := 0.0
	var burned_at := -1.0
	var last_heat := 1.0
	var fire_out_at := -1.0
	var fire_out_tic := -1
	var burn_tics := 0
	while d.phase == "drop" and game.tics - t0 < 150 * 35:
		last_heat = d.heat
		await process_frame
		fastest = maxf(fastest, -d.vel.y)
		if d.auto_burn and burned_at < 0.0:
			burned_at = d.altitude()
		if d.auto_burn:
			burn_tics = game.tics - t0 - burn_start_tic
		elif burned_at < 0.0:
			burn_start_tic = game.tics - t0
		if d.phase == "drop":
			early += waiting.filter(func(o): return o.dead or o.burning > 0).size()
			if squash_me != null and (squash_me.dead or squash_me.removed):
				early += 1
		if d.phase == "drop" and d.heat <= 0.0 and fire_out_at < 0.0:
			fire_out_at = d.altitude()
			fire_out_tic = d.ticks
	var t: int = game.tics - t0
	check(d.phase != "drop", "it comes down")
	# STRAIGHT DOWN, 2.5 TIMES AS FAST, THE FIRE THREE QUARTERS OF THE WAY
	check(t > 12 * 35 and t < 30 * 35, "in %.1f s: straight down, fast (it was 40 and more)" % (t / 35.0))
	check(fastest > 340.0, "falling at up to %.0f m/s at the top, then at terminal" % fastest)
	check(d.max_heat > 0.9 and fire_out_at > 0.0 and last_heat <= 0.0,
		"the reentry fire burned, and was out by %.0f m, before the ground" % fire_out_at)
	var share := 1.0 - fire_out_at / DropPod.DROP.height
	check(share > 0.75 and share < 0.85, "and it lasted %.0f%% of the way down (%.1f s)" % [share * 100.0, fire_out_tic / 35.0])
	check(burned_at > 100.0 and burned_at < fire_out_at, "the autopilot lit the retros at %.0f m, after the fire" % burned_at)
	check(burn_tics < 9 * 35, "and the burn was over in %.1f s" % (burn_tics / 35.0))
	var off := Vector2(d.pos.x * um - d.start.x, -d.pos.z * um - d.start.y).length() / um
	check(off < 3.0, "down on the start, no drift (%.1f m off)" % off)
	check(d.touchdown_speed <= DropPod.DROP.land_speed + 1.0, "and landed at %.1f m/s" % d.touchdown_speed)
	check(rad_to_deg(d.tilt()) < 20.0, "near enough level (%.0f degrees)" % rad_to_deg(d.tilt()))
	check(d._ground() > IslandLevel.NO_FLOOR, "on land")
	check(d.scorches >= 96, "the ground scorched all round it, four times over (%d marks)" % d.scorches)
	var lit := waiting.filter(func(o): return o.dead or o.removed or o.burning > 0).size()
	check(early == 0, "nobody hurt on the way down, only at the landing (%d)" % early)
	check(not waiting.is_empty() and lit == waiting.size(), "the landing set everybody round it alight (%d of %d, %d in all)" % [lit, waiting.size(), d.burned])
	check(squash_me != null and (squash_me.dead or squash_me.removed) and d.squashed >= 1, "and squashed the one under it (%d squashed)" % d.squashed)
	check(d.vents.size() >= 20, "and the burn sites smoulder (%d vents)" % d.vents.size())
	check(absf(d.fuel - DropPod.DROP.rcs_fuel) < 1e-3, "hands off, the stick's tank is full (%.1f)" % d.fuel)
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
	var out_now := Vector2(p.x - gx, p.y - gy).length() / um
	var f_out: float = game.level.floor_at(p.x, p.y)
	check(out_now > DropPod.HULL_R + 0.5 and out_now < DropPod.HULL_R + 1.6, "and set down outside the door (%.1f m from the middle)" % out_now)
	check(absf(p.z - f_out) < 1.0 and p.z < pz - 2.0, "on the ground there, off the deck")
	check(absf(Vector2(cos(p.angle), sin(p.angle)).dot(dv) - 1.0) < 0.1, "facing away from the pod")
	check(d.blockers.size() >= 16 and d.blockers.size() < DropPod.BLOCKERS, "a ring of posts round the hull with a gap for the door (%d)" % d.blockers.size())
	check(d.door_posts.is_empty(), "the doorway open")
	for k in 40:
		game.tic()
	check(girl.dead or girl.removed, "the candy girl in its way blown apart (%d hit)" % d.door_kills)
	for k in 50:
		game.tic()
	check(d.door_down, "the door is down on the ground")
	check(not p.dead and p.health > 0, "and you are alive")
	# THE BURN SITES, still smoking, for five minutes and then not
	var puffs0: int = d.vent_puffs
	for k in 35 * 5:
		game.tic()
	check(d.vent_puffs > puffs0 + 20 and d.vent_puffs < puffs0 + 450, "the burn sites smoke and steam (%d puffs in five seconds)" % (d.vent_puffs - puffs0))
	check(not d.vents.is_empty(), "still at it")
	for v in d.vents:
		v[4] = d.ticks - DropPod.SMOULDER_TICS + 2
	for k in 4:
		game.tic()
	check(d.vents.is_empty(), "and done after five minutes")
	check(not waiting.any(func(o): return not o.dead and not o.removed and o.burning <= 0), "nobody under it walked away unburnt")
	# AND AWAY: walking on from there — through the game's own tic, the
	# key held, as the user plays (the pod kept putting the player back
	# at its middle every tic: stuck in the pod; then they could not get
	# out of the door: now they are set down outside it)
	p.angle = d.door_angle()
	Input.action_press("fwd")
	for k in 50:
		game.tic()
	Input.action_release("fwd")
	var out_r := Vector2(p.x - gx, p.y - gy).length() / um
	var f_here: float = game.level.floor_at(p.x, p.y)
	check(out_r > out_now + 2.0, "you walk away from it (%.1f m from the middle)" % out_r)
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
			_drain(vd)
			check(n0 >= 1 and _hurt(vd, q0), "the retros' downwash into a plant's top shreds it (%d touched)" % n0)
			# an RCS jet aimed down through a plant's middle from four metres
			# off and two up (level, on a slope, it can start in the ground)
			var q1: Dictionary = pool[1]
			var mid := VegDamage.to_game(q1.pos + Vector3(0.0, q1.h * 0.5, 0.0))
			var from := mid + Vector3(4.0 * um, 0.0, 2.0 * um)
			var n1: int = vd.jet(from, (mid - from).normalized(), 7.0 * um, 2.0 * um, 30.0)
			_drain(vd)
			check(n1 >= 1 and _hurt(vd, q1), "an RCS jet through a plant hurts it (%d touched)" % n1)
			# the door through one
			var q2: Dictionary = pool[2]
			var n2: int = vd.sweep(VegDamage.to_game(q2.pos + Vector3(0.0, q2.h * 0.4, 0.0)), DropPod.DOOR_HIT_R * um, mid)
			_drain(vd)
			check(n2 >= 1 and _gone(vd, q2), "the door through a plant shreds it")
			# and where a pod comes down, everything
			var q3: Dictionary = pool[3]
			var n3: int = vd.clear(VegDamage.to_game(q3.pos), DropPod.HULL_R * um)
			_drain(vd)
			check(n3 >= 1 and _gone(vd, q3), "where a pod comes down, nothing left standing")
	# ---- hands on: NOTHING (the RCS off, at the user's request: "remove
	# the RCS thrusters from the pod for now ... uncontrolled") ---------
	game.queue_free()
	await process_frame
	game = await _start()
	d = game.drop
	check(not DropPod.RCS_ON, "the RCS is off")
	check(d.tilt() < 0.01, "the pod comes in upright (%.1f degrees)" % rad_to_deg(d.tilt()))
	var f0: int = d.fires
	for k in 50:
		d.tic({"fwd": 1.0, "side": 1.0, "look": Vector2(), "attack": true})
	var rcs_fired := false
	for i in d.nozzles.size():
		if d.fired[i] > 0.0 and d.nozzles[i].kind == "rcs":
			rcs_fired = true
	check(not rcs_fired and d.fires == f0, "a hand on the stick fires nothing (%d firings)" % (d.fires - f0))
	check(rad_to_deg(d.tilt()) < 1.0, "and the pod does not tilt (%.1f degrees)" % rad_to_deg(d.tilt()))
	check(d.retro_level == 0.0, "and FIRE does not light the retros")
	check(not d.readout().has("fuel"), "the readout has no RCS line")
	var back_ok := true
	for i in d.nozzles.size():
		if d.nozzles[i].kind != "retro":
			continue
		var tf: Transform3D = d.flame_transform(i, 1.0)
		var c: Color = DropPod._flame_color("retro")
		if tf.basis.y.normalized().dot(d.nozzles[i].dir) < 0.95 or not (c.b > c.r and c.a > 0.5):
			back_ok = false
	check(back_ok, "the retros' jets out along their exhaust too, bright blue")
	var jet: ArrayMesh = DropPod._jet_mesh()
	var arr: Array = jet.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var widest := 0.0
	var waists := 0
	var last_r := -1.0
	var falling := false
	for i in range(0, verts.size(), DropPod.JET_SEGS + 1):
		var r := Vector2(verts[i].x, verts[i].z).length()
		widest = maxf(widest, r)
		if last_r >= 0.0 and r > last_r + 1e-4 and falling:
			waists += 1
		falling = last_r >= 0.0 and r < last_r - 1e-4
		last_r = r
	check(waists == DropPod.DIAMONDS - 1 and verts[verts.size() - 1].y == 1.0 and Vector2(verts[verts.size() - 1].x, verts[verts.size() - 1].z).length() < 1e-4,
		"a jet is a chain of %d diamonds ending in a point (%d waists)" % [DropPod.DIAMONDS, waists])
	print("drop: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)

## the plant `q` as it stands now: hurt (its count up) or gone
func _hurt(vd, q: Dictionary) -> bool:
	var now: Dictionary = vd._plant(q.tile, q.sprite, q.row)
	return now.gone or now.custom.y > q.custom.y

func _gone(vd, q: Dictionary) -> bool:
	var now: Dictionary = vd._plant(q.tile, q.sprite, q.row)
	return now.gone
