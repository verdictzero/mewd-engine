## MEWD — THE UNICORNS FIGHT BACK, headless (RainbowBeams, rainbow.gd;
## Actor.rouse and the UNI_ states): a grown unicorn hurt by the player
## turns on them, and the grown ones of her herd with her (a foal still
## does not); she faces the player in her firing picture, draws the charge
## in, throws the beam, and it hurts them, the line swinging after them,
## going on THROUGH them, and their screen swims; where it lands it
## leaves its marks; she CHARGES them, rams them, and goes again;
## out of sight she gallops after them; dead, her beam is gone; and when
## the fury is out she grazes again.
##   godot --headless --script res://godot/tests/unicorn_test.gd -- --map=candyland
extends SceneTree

var game
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _tics(n: int) -> void:
	for i in n:
		game.tic()

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	var p = game.player
	p.invincible = false
	# the unicorn nearest the start, and the player 20 m in front of her
	var u = null
	for a in game.actors:
		if a.type == "UNICORN" and not a.dead and (u == null or U.dist2(a.x, a.y, p.x, p.y) < U.dist2(u.x, u.y, p.x, p.y)):
			u = a
	check(u != null, "a unicorn to try it on")
	if u == null:
		quit(1)
		return
	var um := IslandLevel.U_PER_M
	var away := 20.0 * um
	var px: float = u.x + away
	var py: float = u.y
	p.x = px
	p.y = py
	p.z = game.level.floor_at(px, py)
	check(u.can_see(p), "she can see the player")
	var herd := []
	var foals := []
	for a in game.blockmap.near_radius(u.x, u.y, Actor.ROUSE_R):
		if a == u or a.dead or a.removed:
			continue
		if a.type == "UNICORN":
			herd.append(a)
		elif a.type == "FOAL":
			foals.append(a)
	# ---- hurt her ------------------------------------------------------
	var h0: int = p.health + p.armour1 + p.armour2
	u.damage(1.0, p, {"shot": true})
	check(u.fury > 0, "hurt by the player, she is in a fury (%d tics)" % u.fury)
	check(u.state.name == "UNI_AIM", "and turns on them (%s)" % u.state.name)
	check(u.state.sprite == "UNIF", "in her firing picture")
	var roused := herd.filter(func(o): return o.fury > 0).size()
	check(herd.is_empty() or roused == herd.size(), "her herd with her (%d of %d)" % [roused, herd.size()])
	check(foals.all(func(o): return o.fury == 0), "a foal does not (%d)" % foals.size())
	# (the others stood down, so the beam on the player is hers alone)
	for o in herd:
		o.fury = 1
	_tics(2)
	var to_p := atan2(p.y - u.y, p.x - u.x)
	check(absf(U.angle_norm(u.angle - to_p)) < 0.05, "facing the player")
	var sd: Array = game.standees._cell_of(u, Vector2(p.x, p.y)) if game.get("standees") != null else ["UNIF"]
	check(sd[0] == "UNIF", "drawn from her firing picture (%s)" % sd[0])
	# ---- the charge, then the beam --------------------------------------
	var rb: RainbowBeams = game.rainbow
	var f0 := rb.fired
	var t := 0
	while rb.fired == f0 and t < 60:
		game.tic()
		t += 1
	check(rb.fired > f0, "she fires after drawing the charge in (%.1f s)" % (t / 35.0))
	check(t >= RainbowBeams.UNI.charge_tics - 4, "not at once: the charge first")
	check(u.state.name == "UNI_BEAM", "the beam (%s)" % u.state.name)
	_tics(12)
	check(rb.beams.size() >= 1, "a beam in the air")
	var b: Dictionary = rb.beams[0] if rb.beams.size() > 0 else {}
	if not b.is_empty():
		var m: Vector3 = b.from
		check(m.z > u.z + u.height * 0.5, "from her mouth, high on her (%.0f over her feet)" % (m.z - u.z))
		check(b.to.distance_to(m) > away * 0.5, "reaching the player's way (%.0f units)" % b.to.distance_to(m))
	var h1: int = p.health + p.armour1 + p.armour2
	check(h1 < h0, "and it hurts them (%d to %d, health and armour)" % [h0, h1])
	if not b.is_empty():
		check(b.to.distance_to(b.from) > Vector2(p.x - u.x, p.y - u.y).length() + 100.0,
			"and goes on through them (%.0f units, they are %.0f off)" % [b.to.distance_to(b.from), Vector2(p.x - u.x, p.y - u.y).length()])
		var g: Vector2 = b.get("gap", Vector2(-1, -1))
		check(g.y > 0.0 and g.y < b.to.distance_to(b.from), "drawn on past their eye (gap %.0f..%.0f)" % [g.x, g.y])
	check(p.wobble > 0, "their screen swims (%d tics)" % p.wobble)
	check(rb.hits > 0, "they were in it %d tics" % rb.hits)
	check(rb.sparks.count > 0, "sparks off it (%d)" % rb.sparks.count)
	# ---- the line swings after the player: step out of it --------------
	var hits0 := rb.hits
	p.x = u.x + cos(0.9) * away
	p.y = u.y + sin(0.9) * away
	p.z = game.level.floor_at(p.x, p.y)
	game.tic()
	var swung := rb.hits == hits0
	_tics(20)
	check(swung, "a sidestep takes them out of it, for a moment")
	# ---- where it lands -------------------------------------------------
	p.health = 100
	p.x = px
	p.y = py
	p.z = game.level.floor_at(px, py)
	# (the player crouched out of the way, the beam into the ground behind)
	var marks0 := rb.marks
	b = rb.beams[0] if rb.beams.size() > 0 else {}
	# ---- the charge, the ram, and again -----------------------------------
	t = 0
	while u.state.name != "UNI_CHARGE" and t < 80:
		game.tic()
		t += 1
	check(u.state.name == "UNI_CHARGE", "after the beam, she charges them")
	var d0c := Vector2(u.x - p.x, u.y - p.y).length()
	var r0: int = u.rams
	var hr: int = p.health + p.armour1 + p.armour2
	var f1 := rb.fired
	t = 0
	while u.rams == r0 and t < RainbowBeams.UNI.run_tics + 2:
		game.tic()
		t += 1
	check(u.rams > r0, "and reaches them, and rams them (%.1f s from %.0f units)" % [t / 35.0, d0c])
	check(p.health + p.armour1 + p.armour2 <= hr - int(RainbowBeams.UNI.ram_damage), "the ram hurts (%d to %d)" % [hr, p.health + p.armour1 + p.armour2])
	_tics(RainbowBeams.UNI.charge_tics + 4)
	check(rb.fired > f1, "and she goes again")
	# a beam aimed into the ground: scorches where it lands
	u.uni_t = 0
	var g := Vector3(u.x + 300.0, u.y, game.level.floor_at(u.x + 300.0, u.y))
	var bb := rb.fire(u, p)
	bb.dir = (g - RainbowBeams.mouth(u)).normalized()
	p.x = u.x - away
	p.y = u.y
	var mk := rb.marks
	for k in 12:
		bb.dir = (g - RainbowBeams.mouth(u)).normalized()
		rb.tic()
	check(rb.marks > mk, "where it lands, scorched (%d marks)" % (rb.marks - mk))
	# ---- out of sight: after them -----------------------------------------
	u.set_state("UNI_CHARGE")
	u.uni_t = RainbowBeams.UNI.run_tics - 1
	p.x = u.x + RainbowBeams.UNI.range * 1.5
	p.y = u.y
	_tics(2)
	check(u.state.name.begins_with("UNI_HUNT"), "out of reach, she gallops after them (%s)" % u.state.name)
	var d0 := Vector2(u.x - p.x, u.y - p.y).length()
	_tics(35)
	check(Vector2(u.x - p.x, u.y - p.y).length() < d0 - 100.0, "closing (%.0f to %.0f)" % [d0, Vector2(u.x - p.x, u.y - p.y).length()])
	# ---- the fury out: back to grazing -------------------------------------
	u.fury = 1
	_tics(2)
	var fighting: bool = ["UNI_AIM", "UNI_BEAM", "UNI_CHARGE", "UNI_HUNT1", "UNI_HUNT2"].has(u.state.name)
	check(u.fury == 0 and not fighting, "the fury out, she grazes again (%s)" % u.state.name)
	# ---- dead, her beam is gone ---------------------------------------------
	u.damage(1.0, p, {"shot": true})
	p.x = px
	p.y = py
	t = 0
	while not rb.firing(u) and t < 80:
		game.tic()
		t += 1
	check(rb.firing(u), "roused again, firing again")
	u.damage(100000.0, p, {})
	game.tic()
	check(not rb.firing(u), "killed, her beam is gone")
	# ---- A DEATH ROUSES THE REST: another herd, calm, one of them killed
	# outright by nobody in particular — and every grown one near her turns
	var v = null
	for a in game.actors:
		if a.type == "UNICORN" and not a.dead and Vector2(a.x - u.x, a.y - u.y).length() > Actor.DEATH_ROUSE_R * 1.5:
			v = a
			break
	check(v != null, "another herd, calm")
	if v != null:
		var near := []
		for a in game.actors:
			if a != v and a.type == "UNICORN" and not a.dead and Vector2(a.x - v.x, a.y - v.y).length() < Actor.DEATH_ROUSE_R:
				a.fury = 0
				near.append(a)
		v.fury = 0
		v.damage(1.0e7, null, {})
		var turned := near.filter(func(o): return o.fury > 0 and o.target == p).size()
		check(v.dead and not near.is_empty() and turned == near.size(), "a unicorn killed outright: every grown one near her turns on you (%d of %d)" % [turned, near.size()])
	print("unicorn: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
