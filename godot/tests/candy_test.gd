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
	print("candy: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
