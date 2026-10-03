## MEWD — CANDY LAND, headless (at the user's request; godot/scripts/
## level/islands.gd "candyland"): the roads and the squares off the field,
## lamps along the roads, you in a square, the crowd all candy girls in
## their nine flavours; the girls walking up to you and saying hello; a
## fright sending them running, for good; and a girl drawn from the front
## facing the eye and from the back facing away.
##   godot --headless --script res://godot/tests/candy_test.gd -- --map=candyland
## (needs the island baked: godot --headless --script res://tools/bake_island.gd -- --map=candyland)
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
	check(game.map_name == "candyland", "the island is CANDY LAND")
	var lv: IslandLevel = game.level
	var roads: Dictionary = game._roads_of(game.island.get_node("IslandWorld").field)
	check(roads.paths.size() >= 4 and roads.squares.size() >= 3,
		"roads and squares on the field (%d road legs, %d squares)" % [roads.paths.size(), roads.squares.size()])
	# a road is flat across and paved: the ground either side of its middle
	# within a step
	var flat := 0
	for r in roads.paths:
		var m: Vector2 = (r[0] + r[1]) * 0.5
		var d: Vector2 = (r[1] - r[0]).normalized()
		var n := Vector2(-d.y, d.x) * float(r[2]) * 0.6
		if absf(lv.floor_at(m.x + n.x, m.y + n.y) - lv.floor_at(m.x - n.x, m.y - n.y)) < U.MAX_STEP:
			flat += 1
	check(flat == roads.paths.size(), "every road is level across (%d of %d)" % [flat, roads.paths.size()])
	var p = game.player
	var in_square := false
	for sq in roads.squares:
		if Vector2(p.x, p.y).distance_to(sq[0]) < float(sq[1]):
			in_square = true
	check(in_square, "you start in a town square")
	var lamps := 0
	var girls := []
	var flavours := {}
	var others := 0
	for a in game.actors:
		if a.type == "LAMP":
			lamps += 1
		elif a.type == "CANDYGIRL":
			girls.append(a)
			flavours[a.variant] = true
		elif a.monster and not (a.type == "UNICORN" or a.type == "FOAL"):
			others += 1
	check(lamps > 20, "street lamps along the roads (%d)" % lamps)
	# THE HOUSES round the squares: a good many, each by a square and off
	# every road, none inside another, nobody stood in one
	var hs: Array = lv.houses
	var by_square := 0
	var on_road := 0
	for h in hs:
		var c := Vector2(h.x, h.y)
		for sq in roads.squares:
			if c.distance_to(sq[0]) < float(sq[1]) + 12.0 * 32.0:
				by_square += 1
				break
		for r in roads.paths:
			if Geometry2D.get_closest_point_to_segment(c, r[0], r[1]).distance_to(c) < float(r[2]) + float(h.hw):
				on_road += 1
	check(hs.size() >= 3 * roads.squares.size() and by_square == hs.size() and on_road == 0,
		"gingerbread houses round the squares (%d houses, %d by a square, %d on a road)" % [hs.size(), by_square, on_road])
	# THE TOWNS ARE SQUARES: streets through them, level from corner to
	# corner, a crossroads to start at, four houses to a quadrant
	var towns := 0
	var level := 0
	var full := 0
	for sq in roads.squares:
		if sq.size() < 4 or float(sq[3]) <= 0.0:
			continue
		towns += 1
		var c: Vector2 = sq[0]
		# (in from the corners by more than the ground's grid, which is what
		# this reads, so the cliff round the edge is not counted)
		var half: float = float(sq[1]) * 0.85
		var f0 := lv.floor_at(c.x, c.y)
		var flat_here := true
		for k in 4:
			var q := c + Vector2(half, half).rotated(float(sq[2]) + k * PI * 0.5)
			if absf(lv.floor_at(q.x, q.y) - f0) > 8.0:
				flat_here = false
		if flat_here:
			level += 1
		var mine := hs.filter(func(h): return Vector2(h.x, h.y).distance_to(c) < float(sq[1]) * 1.42)
		if mine.size() >= 12 and mine.size() <= 16:
			full += 1
	check(towns == roads.squares.size() and towns >= 3, "every town a square with streets (%d)" % towns)
	check(level == towns, "level from corner to corner (%d of %d)" % [level, towns])
	check(full >= towns - 1, "four houses or nearly to a quadrant (%d of %d towns with 12 to 16)" % [full, towns])
	var inside := 0
	for a in game.actors:
		if lv.in_house(a.x, a.y, 0.0):
			inside += 1
	check(inside == 0 and not lv.in_house(p.x, p.y, p.radius), "nobody starts inside a house (%d)" % inside)
	check(game.island.get_node("Houses").multimesh.instance_count == hs.size(), "and every one drawn")
	# A HOUSE IS SOLID: you cannot walk into one, an eye cannot see through
	# one, a round stops on its wall — and one over its roof flies on
	var hh: Dictionary = hs[0]
	var door := Vector2(cos(hh.angle), sin(hh.angle))
	var out := Vector2(hh.x, hh.y) + door * (float(hh.front) + 120.0)
	var mid := Vector2(hh.x, hh.y)
	var z0: float = lv.floor_at(out.x, out.y)
	var step := out + (mid - out).normalized() * 130.0
	check(not lv.can_move(out.x, out.y, step.x, step.y, 16.0, z0, 56.0, false), "a house stops you walking into it")
	var far := mid - door * (float(hh.back) + 120.0)
	var w: Dictionary = lv.ray_hit_wall(out.x, out.y, z0 + 41.0, far.x, far.y, z0 + 41.0)
	check(not w.is_empty() and w.line == hh.lines[2], "a round stops on its front wall")
	check(lv.sight_blocked(out.x, out.y, z0 + 41.0, far.x, far.y, z0 + 41.0), "and an eye cannot see through it")
	var up: float = hh.z + hh.top + 64.0
	check(lv.ray_hit_wall(out.x, out.y, up, far.x, far.y, up).is_empty(), "a round over its roof flies on")
	check(girls.size() == 360 and others == 0, "the crowd is all candy girls (%d, %d others)" % [girls.size(), others])
	check(flavours.size() == States.CANDY_FLAVOURS.size(), "in every flavour (%d of %d)" % [flavours.size(), States.CANDY_FLAVOURS.size()])
	# THE HERDS: unicorns and foals in the meadows, the foal a little over
	# half her mother's size and beside her
	var unis := []
	var foals := []
	for a in game.actors:
		if a.type == "UNICORN":
			unis.append(a)
		elif a.type == "FOAL":
			foals.append(a)
	var homes := {}
	for a in unis:
		homes[a.home] = true
	check(homes.size() >= 6 and unis.size() >= homes.size() * 3, "herds of unicorns (%d herds, %d unicorns, %d foals)" % [homes.size(), unis.size(), foals.size()])
	var meadow: Callable = game._meadow_of(game.island.get_node("IslandWorld").field)
	check(homes.keys().all(func(h): return meadow.call(h.x, h.y)), "every herd's ground is a meadow")
	var fa: Actor = foals[0]
	check(fa.height < unis[0].height * 0.6 and fa.radius < unis[0].radius * 0.6 and fa.mother != null and fa.mother.type == "UNICORN",
		"a foal is a little over half her mother's size (%d against %d), and has one" % [fa.height, unis[0].height])
	# THEY COME TO SAY HELLO
	var near0 := 0
	for a in girls:
		if U.dist2(a.x, a.y, p.x, p.y) < 300.0 * 300.0:
			near0 += 1
	_tics(35 * 12)
	var near1 := 0
	var hello := 0
	var facing := 0
	for a in girls:
		if U.dist2(a.x, a.y, p.x, p.y) < 300.0 * 300.0:
			near1 += 1
		if a.hello > 0:
			hello += 1
			if cos(a.angle) * (p.x - a.x) + sin(a.angle) * (p.y - a.y) > 0.0:
				facing += 1
	check(near1 > near0 + 5, "they walk up to you (%d within 9 m, from %d)" % [near1, near0])
	check(hello >= 5 and facing == hello, "and stand saying hello, facing you (%d, %d facing)" % [hello, facing])
	check(game._hello_tic > 0, "and one says so, in the toasts")
	# the herds graze about their ground; the foals keep by their mothers
	var strays := 0
	for a in unis:
		if Vector2(a.x, a.y).distance_to(a.home) > Actor.HERD_RANGE + 400.0:
			strays += 1
	var lost := 0
	for a in foals:
		if a.mother != null and Vector2(a.x, a.y).distance_to(Vector2(a.mother.x, a.mother.y)) > Actor.FOAL_RANGE * 3.0:
			lost += 1
	var moved := unis.filter(func(a): return a.state.get("name", "").begins_with("UNI_WALK")).size()
	check(strays == 0 and lost == 0, "after 12 s the herds are on their ground (%d strays) and the foals by their mothers (%d lost)" % [strays, lost])
	# the drawing: front head on, back going away, the side across, turned for the other flank
	var u: Actor = unis[0]
	var eye := Vector2(u.x + 300.0, u.y)
	var views := []
	for ang in [0.0, PI, PI / 2.0, -PI / 2.0]:
		u.angle = ang
		views.append(game.standees._cell_of(u, eye))
	check(views[0][1] == 0 and views[1][1] == 2 and views[2][1] == 1 and views[3][1] == 1 and views[2][2] != views[3][2],
		"a unicorn drawn from the front, the back and either side (%s)" % [views])
	# FRONT AND BACK: the cell for the way she faces against the eye
	var st: Standees = game.standees
	var g = girls[0]
	var cam := Vector2(g.x + 200.0, g.y)
	g.angle = 0.0
	var front: Array = st._cell_of(g, cam)
	g.angle = PI
	var back: Array = st._cell_of(g, cam)
	check(front[0] == "CANDY" and front[1] == (g.variant % 9) * 2 and back[1] == front[1] + 1,
		"drawn from the front facing you, from the back facing away (cells %d, %d)" % [front[1], back[1]])
	# A FRIGHT: they run, and once they have, they do not come back
	game.scare(p.x, p.y, 1200.0)
	_tics(5)
	var running := 0
	var greeters := []
	for a in girls:
		if not a.removed and U.dist2(a.x, a.y, p.x, p.y) < 1200.0 * 1200.0:
			greeters.append(a)
			if a.panic > 0:
				running += 1
	check(running == greeters.size() and running > 5, "a fright and they run (%d of %d)" % [running, greeters.size()])
	var d0 := 0.0
	for a in greeters:
		d0 += sqrt(U.dist2(a.x, a.y, p.x, p.y))
	_tics(35 * 20)
	var d1 := 0.0
	var wary := 0
	var again := 0
	for a in greeters:
		d1 += sqrt(U.dist2(a.x, a.y, p.x, p.y))
		if a.wary:
			wary += 1
		if a.hello > 0 or a.state.get("name", "").begins_with("CANDY_WALK"):
			again += 1
	check(d1 > d0 * 1.5, "away from you (%.0f to %.0f units on average)" % [d0 / greeters.size(), d1 / greeters.size()])
	check(wary == greeters.size() and again == 0, "and they do not come back (%d wary, %d coming)" % [wary, again])
	# A FRIGHTENED HERD GALLOPS
	var h: Vector2 = unis[0].home
	var herd := unis.filter(func(a): return a.home == h)
	var d0h := 0.0
	for a in herd:
		d0h += Vector2(a.x, a.y).distance_to(h)
	game.scare(h.x, h.y, 1500.0)
	_tics(35 * 3)
	var d1h := 0.0
	var fast := 0
	for a in herd:
		d1h += Vector2(a.x, a.y).distance_to(h)
		if a.panic > 0 and a.speed > float(a.info.speed):
			fast += 1
	check(fast == herd.size() and d1h > d0h + herd.size() * 300.0, "a frightened herd gallops off (%d of %d, %.0f units further on average)" % [fast, herd.size(), (d1h - d0h) / herd.size()])
	# A STAMPEDE TRAMPLES: a girl stood in a galloping unicorn's way comes apart
	var runner: Actor = herd[0]
	var g2: Actor = game.spawn("CANDYGIRL", runner.x + cos(runner.angle) * 40.0, runner.y + sin(runner.angle) * 40.0, 0.0)
	runner.panic = 200
	runner.speed = float(runner.info.runSpeed)
	runner.flee_x = runner.x - cos(runner.angle) * 300.0
	runner.flee_y = runner.y - sin(runner.angle) * 300.0
	runner.A_Flee()
	check(g2.dead or g2.removed, "a galloping unicorn tramples a girl in her way to pieces")
	# AND A UNICORN CAN BE KILLED: shot to pieces like anybody
	var victim: Actor = unis[unis.size() - 1]
	var foal_v: Actor = foals[foals.size() - 1]
	# (a round a bite now: enough of them, and they come apart)
	var rounds := 0
	while rounds < 40 and not ((victim.dead or victim.removed) and (foal_v.dead or foal_v.removed)):
		victim.damage(1000.0, game.player, {"shot": true})
		foal_v.damage(1000.0, game.player, {"shot": true})
		rounds += 1
	_tics(3)
	check((victim.dead or victim.removed) and (foal_v.dead or foal_v.removed) and rounds > 1,
		"a unicorn and a foal shot down come apart (%d rounds)" % rounds)
	print("candy: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
