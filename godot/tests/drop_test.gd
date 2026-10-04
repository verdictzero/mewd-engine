## MEWD — THE DROP, headless (godot/scripts/game/drop_pod.gd): the pod
## read from its file (its nozzles found, the markers gone), the ride down
## with nobody's hands on it — the autopilot brings it in under the landing
## speed, level, on land — the hold, the eye inside, the door blown, the
## blockers round the hull, the player free on the ground; and with a
## hand on the stick the pod tilts, its RCS firing.
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

func _run() -> void:
	game = await _start()
	var d: DropPod = game.drop
	check(d != null and d.active and d.phase == "drop", "the game begins in the pod, dropping")
	check(d.nozzles.size() == 20, "twenty nozzles read off the model (%d)" % d.nozzles.size())
	var retros := d.nozzles.filter(func(n): return n.kind == "retro").size()
	check(retros == 8, "eight of them retros, pointing down (%d)" % retros)
	var down := true
	for n in d.nozzles:
		if n.kind == "retro" and n.dir.y > -0.5:
			down = false
	check(down, "and down they point")
	await process_frame
	var tiny := 0
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		if is_instance_valid(mi) and not mi.is_queued_for_deletion() and (mi as MeshInstance3D).get_aabb().size.length() < 0.5:
			tiny += 1
	check(tiny == 0, "the marker spheres are gone from the picture (%d left)" % tiny)
	check(d.altitude() > 1000.0, "the pod begins high over the island (%.0f m)" % d.altitude())
	var p = game.player
	check(absf(p.z - d.pos.y * 32.0) < 1.0, "the player rides in it")
	# ---- the ride down, hands off ---------------------------------------
	var t := 0
	var fastest := 0.0
	var burned_at := -1.0
	while d.phase == "drop" and t < 70 * 35:
		game.tic()
		t += 1
		fastest = maxf(fastest, -d.vel.y)
		if d.auto_burn and burned_at < 0.0:
			burned_at = d.altitude()
	check(d.phase != "drop", "it comes down (%d tics, %.1f s)" % [t, t / 35.0])
	check(fastest > 40.0 and fastest < 90.0, "falling at up to %.0f m/s" % fastest)
	check(burned_at > 0.0, "the autopilot lit the retros at %.0f m" % burned_at)
	check(d.touchdown_speed <= DropPod.DROP.land_speed + 1.0, "and landed at %.1f m/s" % d.touchdown_speed)
	check(rad_to_deg(d.tilt()) < 20.0 or d.phase != "drop", "near enough level (%.0f degrees)" % rad_to_deg(d.tilt()))
	check(d._ground() > IslandLevel.NO_FLOOR, "on land")
	# ---- the hold, the eye inside, the door ----------------------------
	for k in DropPod.DROP.hold_tics + 2:
		game.tic()
	check(d.phase == "inside" and not d.third_person(), "then the eye is inside the pod, first person")
	check(d.holds_player(), "and you cannot walk yet")
	var pz: float = p.z
	for k in DropPod.DROP.door_tics + 2:
		game.tic()
	check(d.phase == "out", "the door blows off")
	check(not d.holds_player(), "and you are free")
	check(absf(p.z - pz) < 2.0 and absf(p.z - d.pos.y * 32.0) < 2.0, "standing on the pod's floor")
	check(d.blockers.size() >= 8 and d.blockers.size() < DropPod.BLOCKERS, "a ring of blockers round the hull with a gap for the door (%d)" % d.blockers.size())
	for k in 90:
		game.tic()
	check(d.door_down, "the door is down on the ground")
	check(not p.dead and p.health > 0, "and you are alive")
	# ---- hands on: the pod tilts, the RCS fires ------------------------
	game.queue_free()
	await process_frame
	game = await _start()
	d = game.drop
	var f0: int = d.fires
	var tilt0: float = d.tilt()
	for k in 70:
		d.tic({"fwd": 1.0, "side": 0.0, "look": Vector2(), "attack": false})
	check(d.fires > f0, "a hand on the stick fires the RCS (%d firings)" % (d.fires - f0))
	check(rad_to_deg(d.tilt()) > rad_to_deg(tilt0) + 5.0, "and the pod tilts (%.0f degrees)" % rad_to_deg(d.tilt()))
	var rcs_only := true
	for i in d.nozzles.size():
		if d.fired[i] > 0.0 and d.nozzles[i].kind != "rcs":
			rcs_only = false
	check(rcs_only, "with the RCS nozzles, not the retros")
	var v0: float = d.vel.y
	for k in 20:
		d.tic({"fwd": 0.0, "side": 0.0, "look": Vector2(), "attack": true})
	check(d.retro_level > 0.9 and d.vel.y > v0, "FIRE lights the retros and the fall slows")
	print("drop: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
