## MEWD — YOU DIED, headless (PlayerDeath, player_death.gd): the player
## can be hurt again by default; killed, the body goes off — blood all
## round, no giant head, a gravestone rising where they fell; the eye
## circles the place from the moment of death; the body parts come up out of it wave
## after wave, landing and lying there, and do not stop; and a press asks
## for the level again only once the burst has had its say.
##   godot --headless --script res://godot/tests/you_died_test.gd -- --map=candyland
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
	check(not p.invincible, "health back: not invincible by default")
	check(not PauseMenu.DEFAULTS.godmode, "and the menu's default agrees")
	var D: PlayerDeath = game.death
	check(D != null and not D.active, "nobody dead yet")
	# ---- hurt, then killed ---------------------------------------------------
	var h0: int = p.health + p.armour
	p.damage(40.0, null, {"impact": true})
	check(p.health + p.armour < h0, "a blow takes something off (%d to %d)" % [h0, p.health + p.armour])
	var at := Vector3(p.x, p.y, p.z)
	p.damage(100000.0, null, {"impact": true})
	check(p.dead, "and enough of them kills")
	check(D.active, "YOU DIED")
	check(D.at.distance_to(at) < 1.0, "where they fell")
	check(D.marks >= 9, "a great pool and more round it (%d)" % D.marks)
	check(game.giblets.eviscerations >= 3, "the body goes off (%d eviscerations)" % game.giblets.eviscerations)
	check(game.giblets.room.size() >= PlayerDeath.FLOOR_SPATTERS, "the floor about to be painted (%d spatters waiting)" % game.giblets.room.size())
	check(D.stone != null, "a gravestone")
	# ---- the burst: the death camera at once, no restart yet ----------------
	check(D.get_children().filter(func(n): return n is MeshInstance3D and n.mesh is QuadMesh and n != D.stone).is_empty(), "no giant head")
	_tics(20)
	check(D.orbiting(), "the eye leaves the body at once, no fall over first")
	check(not D.can_restart(), "no going again yet")
	check(D.waves == 0, "no fountain yet")
	_tics(PlayerDeath.STONE_RISE)
	var sp: Vector3 = D.stone.position
	check(absf(sp.y - D.stone_floor) < 0.5, "the stone up out of the ground (%.1f over its floor)" % (sp.y - D.stone_floor))
	_tics(PlayerDeath.BURST_TICS)
	# ---- the death camera ------------------------------------------------------
	check(D.orbiting(), "still circling")
	game._process(0.0)
	var c0: Vector3 = game.camera.position
	var mid := U.v3(at.x, at.y, at.z)
	var r0 := Vector2(c0.x - mid.x, c0.z - mid.z).length()
	check(absf(r0 - PlayerDeath.ORBIT_R) < 2.0, "out round the place (%.0f units)" % r0)
	var fwd: Vector3 = -game.camera.global_transform.basis.z
	var look := fwd.dot((mid + Vector3(0, PlayerDeath.LOOK_UP, 0) - c0).normalized())
	check(look > 0.95, "looking at it (%.3f)" % look)
	_tics(70)
	game._process(0.0)
	var c1: Vector3 = game.camera.position
	var swept := Vector2(c0.x - mid.x, c0.z - mid.z).angle_to(Vector2(c1.x - mid.x, c1.z - mid.z))
	check(absf(swept) > 0.8, "and circling (%.2f rad in two seconds)" % swept)
	# ---- the fountain ---------------------------------------------------------
	check(D.waves > 10, "the parts coming up (%d waves)" % D.waves)
	check(D.parts.count > 100, "a lot of them (%d)" % D.parts.count)
	check(D.landed > 0, "and landing (%d)" % D.landed)
	var lying := 0
	var above := 0
	for i in D.parts.live:
		if D.parts.alive[i] and D.rest[i]:
			lying += 1
			if D.parts.pz[i] >= D._floor(D.parts.px[i], D.parts.py[i]) - 0.5:
				above += 1
	check(lying > 0 and above == lying, "lying on the ground, not in it (%d of %d)" % [above, lying])
	var w0 := D.waves
	var m0 := D.marks
	_tics(35 * 40)
	check(D.waves > w0 + 400, "and still coming forty seconds on (%d waves)" % (D.waves - w0))
	check(D.marks > m0, "landing in blood (%d more marks)" % (D.marks - m0))
	check(D.parts.count <= PlayerDeath.PARTS_MAX, "the oldest going as new ones come (%d)" % D.parts.count)
	# ---- again -------------------------------------------------------------------
	check(D.can_restart(), "now a press will do")
	check(not game.restart_wanted, "not asked yet")
	var s = game.session
	game.session = _Press.new()
	game.tic()
	game.session = s
	check(game.restart_wanted, "fire asks for the level again")
	print("you died: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)

class _Press:
	func cmd(_g) -> Dictionary:
		return {"fwd": 0.0, "side": 0.0, "run": false, "jump": false, "look": Vector2(), "attack": true, "slot": 0, "cycle": 0, "use": false}
