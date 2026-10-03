## MEWD — THE GAME ON AN ISLAND, headless (at the user's request; godot/
## scripts/level/island_level.gd): the ground off the bake and the same
## as the field's; you and the crowd stood on it; walking up and down it,
## and stopped at the coast; a hill hiding what is behind it; a round
## into the ground stopping on it; a blast; and the crowd still on the
## island after a while of wandering.
##   godot --headless --script res://godot/tests/island_test.gd
## (needs the island baked: godot --headless --script res://tools/bake_island.gd)
extends SceneTree

var game
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	var lv: IslandLevel = game.level
	var g: IslandGround = lv.ground
	var iw: Node = game.island.get_node("IslandWorld")
	var field: Resource = iw.field
	# THE GROUND: off the bake, and the field's own heights
	check(IslandGround.load_for(IslandGround.signature_for(field, iw.chunk_size)) != null, "the ground comes off the bake")
	# the island's own reach, in metres and in the game's units
	var span: float = float(field.world_max_radius()) * 0.85
	var span_u: float = span * IslandLevel.U_PER_M
	var worst := 0.0
	var on := 0
	var errs := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 400:
		# (over the island, whatever its size: ISLAND 0 or a smaller one)
		var x := rng.randf_range(-span, span)
		var z := rng.randf_range(-span, span)
		var f: float = field.height_at(x, z, -1.0e9)
		var h := g.height(x, z)
		if f > -1.0e8 and h > IslandGround.VOID:
			on += 1
			worst = maxf(worst, absf(f - h))
			errs.append(absf(f - h))
	errs.sort()
	# (an island with ROADS — CANDY LAND — has their cut banks, a crease a
	# 2 m grid rounds over: there the test is that almost all of it is
	# within the 0.75 m and a crease within 2.5 m)
	var roads := bool(field.get("path_enabled"))
	var p99: float = errs[int(errs.size() * 0.99)] if not errs.is_empty() else 0.0
	# (and an island whose towns are cut out with CLIFFS — CANDY LAND's square
	# towns, IslandField.square_pads — has a sheer step a grid cannot follow:
	# a point on one can be a cliff's height out, so there it is the 99%
	# that is held to the grid)
	if bool(field.get("square_pads")):
		check(on > 100 and p99 < 0.75 and worst < 12.0, "the grid is the field's ground between its samples (%d points, 99%% within %.2f m, worst %.2f m on a town's cliff)" % [on, p99, worst])
	elif roads:
		check(on > 100 and p99 < 0.75 and worst < 2.5, "the grid is the field's ground between its samples (%d points, 99%% within %.2f m, worst %.2f m at a road's bank)" % [on, p99, worst])
	else:
		check(on > 100 and worst < 0.75, "the grid is the field's ground between its samples (%d points, worst %.2f m)" % [on, worst])
	check(lv.sector_at(4000.0 * 32.0, 0.0) == null, "off the island there is no floor")
	var s := lv.sector_at(game.player.x, game.player.y)
	check(s != null and s.outdoor and s.ceil_tex == "SKY", "under you: open ground, open sky")
	# YOU AND THE CROWD, on the ground
	var p = game.player
	check(absf(p.z - s.floor) < 1.0, "you stand on the ground (z %.1f, floor %.1f)" % [p.z, s.floor])
	var people := 0
	var off := 0
	for a in game.actors:
		if a.monster:
			people += 1
			var f2 := lv.floor_at(a.x, a.y)
			if f2 <= IslandLevel.NO_FLOOR or absf(a.z - f2) > 1.0:
				off += 1
	check(people >= 300, "a crowd on the island (%d)" % people)
	check(off == 0, "every one of them on the ground (%d not)" % off)
	# WALKING: up and down the hills, z keeping to the ground
	var stray := 0.0
	var moved := 0.0
	var x0: float = p.x
	var y0: float = p.y
	for t in 350:
		var cmd := {"fwd": 1.0, "side": 0.0, "run": true, "jump": false, "look": Vector2(), "attack": false,
			"slot": 0, "cycle": 0, "use": false}
		p.tic(cmd)
		if t % 70 == 0:
			p.angle += 1.3
		if p.z <= lv.floor_at(p.x, p.y) + 0.5:
			stray = maxf(stray, absf(p.z - lv.floor_at(p.x, p.y)))
		moved = maxf(moved, sqrt(U.dist2(p.x, p.y, x0, y0)))
	check(moved > 400.0, "you walk (%.0f units out)" % moved)
	check(stray < 2.0, "and your feet keep to the ground (worst %.1f units)" % stray)
	# THE COAST: nobody walks off it
	var cx := 0.0
	var cy := 0.0
	var dir := Vector2(1, 0)
	while lv.on_land(cx + dir.x * 64.0, cy + dir.y * 64.0, 16.0):
		cx += dir.x * 64.0
		cy += dir.y * 64.0
	var cz := lv.floor_at(cx, cy)
	var r := lv.slide_move(cx, cy, dir.x * 400.0, dir.y * 400.0, 16.0, cz, 56.0, false)
	check(lv.on_land(r.x, r.y, 16.0) and r.z > 0.0, "the coast stops you (at %.0f, %.0f)" % [cx, cy])
	# A HILL HIDES WHAT IS BEHIND IT; open ground does not
	var hidden := false
	var seen := false
	for k in 300:
		var ax := rng.randf_range(-span_u, span_u)
		var ay := rng.randf_range(-span_u, span_u)
		var bx := ax + rng.randf_range(-span_u * 0.25, span_u * 0.25)
		var by := ay + rng.randf_range(-span_u * 0.25, span_u * 0.25)
		var fa := lv.floor_at(ax, ay)
		var fb := lv.floor_at(bx, by)
		if fa <= IslandLevel.NO_FLOOR or fb <= IslandLevel.NO_FLOOR:
			continue
		var blocked := lv.sight_blocked(ax, ay, fa + 41.0, bx, by, fb + 41.0)
		hidden = hidden or blocked
		if not blocked and sqrt(U.dist2(ax, ay, bx, by)) < 400.0:
			seen = true
	check(hidden, "a hill hides one point from another")
	check(seen, "and a near one is in sight")
	# A ROUND INTO THE GROUND stops on it
	# (nobody in the way, nor a street lamp, nor a house: it is the ground
	# being asked)
	for a in game.actors:
		if a.monster or a.shootable:
			a.remove()
	var kept_houses: Array = lv.houses
	lv.houses = []
	p.pitch = -0.6
	game.hitscan(p, p.angle, 2000.0, 1.0, {"pitch": -0.6})
	lv.houses = kept_houses
	var hit: Vector3 = game.last_hit
	var under := lv.floor_at(hit.x, hit.y)
	check(absf(hit.z - under) < 4.0 and sqrt(U.dist2(hit.x, hit.y, p.x, p.y)) < 1000.0,
		"a round fired down stops in the ground (%.1f over it)" % (hit.z - under))
	# A BLAST hurts who is near
	var v: Actor = game.spawn("SHOPPER", p.x + 64.0, p.y, 0.0)
	var h0: float = v.health
	game.explode({"x": p.x + 70.0, "y": p.y, "z": lv.floor_at(p.x + 70.0, p.y) + 8.0}, {"radius": 200.0, "damage": 80.0})
	check(v.health < h0 or v.dead, "a blast at somebody's feet hurts them")
	# THE ISLAND ITSELF: off the bake, its plants planted
	var waited := 0
	while not game.island_ready() and waited < 2000:
		await process_frame
		waited += 1
	check(game.island_ready(), "the island is up (terrain and plants) after %d frames" % waited)
	# THE CROWD AFTER A WHILE: still on the island, still on the ground
	game.level.populate(3, 120)
	for a in game.actors:
		a.remove()
	game.actors = []
	game._spawn_things()
	for t in 300:
		game.tic()
	var lost := 0
	for a in game.actors:
		if a.removed or not a.monster:
			continue
		var f3 := lv.floor_at(a.x, a.y)
		if f3 <= IslandLevel.NO_FLOOR or absf(a.z - f3) > 24.0:
			lost += 1
	check(lost == 0, "after ten seconds the crowd is still on the ground (%d lost)" % lost)
	print("island: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
