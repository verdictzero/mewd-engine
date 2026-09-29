## MEWD — the guns against real people, headless.
##
##   godot --headless --script res://godot/tests/weapons_test.gd -- --seed=7
##
## Builds the real Game on the maze, finds the longest clear run out of
## the START, stands a shopper down it, turns the player to face them and
## holds the trigger with each gun in turn, asserting what the web build
## does: the MINIGUN kills them (and they come apart), the FLAMER sets
## them alight and they RUN, the EXTINGUISHER freezes them solid, and the
## BORE locks, flies, drills and bursts. Prints OK or fails.
extends SceneTree

var game
var failures := 0

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	var p = game.player
	var run := _clear_run(p)
	print("weapons: clear run %d at %d deg" % [run.y, rad_to_deg(run.x)])
	# every other actor out of the way
	for a in game.actors:
		if a.monster:
			a.remove()
	_minigun(p, run)
	_flamer(p, run)
	_extinguisher(p, run)
	_bore(p, run)
	print("weapons: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

func _clear_run(p) -> Vector2:
	var best := Vector2()
	for k in 4:
		var ang := k * PI / 2.0
		var hit: Dictionary = game.level.ray_hit_wall(p.x, p.y, 30, p.x + cos(ang) * 2000.0, p.y + sin(ang) * 2000.0, 30)
		var l: float = 2000.0 * float(hit.t) if not hit.is_empty() else 2000.0
		if l > best.y:
			best = Vector2(ang, l)
	return best

func _victim(p, run: Vector2, d: float) -> Actor:
	d = minf(d, run.y - 40.0)
	var a: Actor = game.spawn("SHOPPER", p.x + cos(run.x) * d, p.y + sin(run.x) * d, 0.0, {"variant": 3})
	p.angle = run.x
	p.pitch = -0.05
	return a

func _hold(weapon: String, tics: int, stop: Callable = Callable()) -> int:
	var p = game.player
	p.weapon = weapon
	p.pending_weapon = ""
	p.spin = 0.0
	game._autofire = true
	for i in tics:
		game.tic()
		if stop.is_valid() and stop.call():
			game._autofire = false
			return i
	game._autofire = false
	return tics

func _settle(tics: int) -> void:
	for i in tics:
		game.tic()

func _minigun(p, run: Vector2) -> void:
	var v := _victim(p, run, 200.0)
	var n := _hold("MINIGUN", 90, func(): return v.removed or v.dead)
	check(v.removed or v.dead, "MINIGUN: the shopper is dead after %d tics" % n)
	check(game.giblets.bursts >= 1, "MINIGUN: and came apart (%d bursts)" % game.giblets.bursts)

func _flamer(p, run: Vector2) -> void:
	var v := _victim(p, run, 160.0)
	var x0 := v.x
	var y0 := v.y
	var n := _hold("FLAMER", 60, func(): return v.burning > 0)
	check(v.burning > 0 and v.torch > 0, "FLAMER: the shopper is alight after %d tics (torch %d)" % [n, v.torch])
	_settle(40)
	var moved := sqrt(U.dist2(v.x, v.y, x0, y0))
	check(moved > 30.0 or v.removed, "FLAMER: and ran (%d units) or already went off" % moved)
	_settle(300)
	check(v.removed, "FLAMER: and went off in the end")

func _extinguisher(p, run: Vector2) -> void:
	var v := _victim(p, run, 140.0)
	var n := _hold("EXTINGUISHER", 80, func(): return v.frozen)
	check(v.frozen, "EXTINGUISHER: the shopper froze solid after %d tics" % n)
	v.damage(10, p, {"shot": true})
	check(v.removed and game.giblets.shatters >= 1, "EXTINGUISHER: and a blow shattered them")

func _bore(p, run: Vector2) -> void:
	_settle(60)     # the last of the frost out of the air: a bore in ice shatters it
	var v := _victim(p, run, 300.0)
	p.pitch = 0.0
	p.weapon = "BORE"
	_settle(2)
	check(game.bore.lock == v, "BORE: the sight locked the shopper")
	var n := _hold("BORE", 120, func(): return v.bored > 0 or v.removed)
	print("  bore: fired %d, drilled %d, in flight %d, victim dead %s removed %s health %d" % [game.bore.fired, game.bore.drilled, game.bore.shots.size(), v.dead, v.removed, v.health])
	check(v.bored > 0, "BORE: the bore arrived and is drilling after %d tics" % n)
	_settle(90)
	check(v.removed or v.dead, "BORE: and they went off")
