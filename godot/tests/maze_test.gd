## MEWD — MAZE LAND (at the user's request: Debug Land at 1024 m a side, a
## maze of the user's parts in sections 2, 4, 5, 6 and 8, just grass and
## only by the walls), headless:
##
##   godot --headless --script res://godot/tests/maze_test.gd -- --map=mazeland
##
## THE MAZE: in the plus of five sections and nowhere else, one piece (every
## cell reached from the middle), loops in it, doors in every stretch of
## its outside. ITS WALLS: a body cannot step through one, a round goes into
## one and over its top goes over, an eye cannot see through one, an open
## edge lets all three through. THE GRASS: none under a wall, extra thick
## in the maze, as usual in the open; plants in the open and none in the
## maze. THE REST: every wall and post drawn; you, the crowd and the pickups out of the walls,
## you in the open corner. Prints OK or fails.
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	U.p_seed()
	var game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	check(game.map_name == "mazeland", "the island is MAZE LAND")
	var lv: IslandLevel = game.level
	var m: Maze = lv.maze
	check(m != null, "it has a maze")
	# (the coast: land 500 m out from the middle each way, none at 530)
	var k := IslandLevel.U_PER_M
	var sides := true
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		sides = sides and lv.on_land(d.x * 500.0 * k, d.y * 500.0 * k) and not lv.on_land(d.x * 530.0 * k, d.y * 530.0 * k)
	check(sides, "1024 m a side")
	# ---- the maze ---------------------------------------------------------
	var third := m.n / 3
	var want := 5 * third * third
	check(m.size() == want, "the maze fills five of the nine sections (%d cells of %d)" % [m.size(), want])
	var per_sec := []
	for s in 9:
		per_sec.append(m.cell(third / 2 + third * (s / 3), third / 2 + third * (s % 3)))
	check(per_sec == [false, true, false, true, true, true, false, true, false], "sections 2, 4, 5, 6 and 8, the plus (%s)" % str(per_sec))
	check(m.reachable(m.n / 2, m.n / 2) == m.size(), "one maze: every cell reached from the middle")
	# a tree has exactly cells - 1 open inside edges; loops make more
	var open_inside := 0
	var doors := 0
	for r in m.n:
		for c in m.n:
			if not m.cell(r, c):
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var other := m.cell(r + d.y, c + d.x)
				var wall := m._wall(r, c, d)
				if other and not wall and (d.x > 0 or d.y > 0):
					open_inside += 1
				if not other and not wall:
					doors += 1
	check(open_inside > m.size() - 1 + m.size() / 20, "interconnected: %d open inside edges, a tree would have %d" % [open_inside, m.size() - 1])
	check(doors >= 24, "doors through its outside wall (%d)" % doors)
	check(m.walls().size() > 5000 and m.posts().size() > 5000, "%d walls, %d posts" % [m.walls().size(), m.posts().size()])
	# ---- its walls ----------------------------------------------------------
	# a cell with a wall to its east and one with its east open
	var wr := -1
	var wc := -1
	var orr := -1
	var oc := -1
	for r in range(m.n / 2 - 10, m.n / 2 + 10):
		for c in range(m.n / 2 - 10, m.n / 2 + 10):
			if m.cell(r, c) and m.cell(r, c + 1):
				if m._wall(r, c, Vector2i(1, 0)) and wr < 0:
					wr = r
					wc = c
				elif not m._wall(r, c, Vector2i(1, 0)) and orr < 0:
					orr = r
					oc = c
	var a := m.centre(wr, wc)
	var b := m.centre(wr, wc + 1)
	var z := m.floor_z
	check(not lv.can_move(a.x, a.y, a.x + m.pitch * 0.5 - 16.0, a.y, 16.0, z, 56.0, false), "a body cannot step into a wall")
	check(lv.can_move(a.x, a.y, a.x + m.pitch * 0.25, a.y, 16.0, z, 56.0, false), "it can walk up to one")
	var hit := lv.ray_hit_wall(a.x, a.y, z + 41.0, b.x, b.y, z + 41.0)
	var face := m.x0 + (wc + 1) * m.pitch - m.half
	check(not hit.is_empty() and absf(hit.x - face) < 1.0, "a round goes into it, at its face (%s)" % str(hit.get("x", "none")))
	check(lv.ray_hit_wall(a.x, a.y, z + m.tall + 32.0, b.x, b.y, z + m.tall + 32.0).is_empty(), "over its top is over it")
	check(lv.sight_blocked(a.x, a.y, z + 41.0, b.x, b.y, z + 41.0), "an eye cannot see through it")
	var oa := m.centre(orr, oc)
	var ob := m.centre(orr, oc + 1)
	check(lv.can_move(oa.x, oa.y, oa.x + m.pitch * 0.6, oa.y, 16.0, z, 56.0, false), "an open edge lets a body through")
	check(lv.ray_hit_wall(oa.x, oa.y, z + 41.0, ob.x, ob.y, z + 41.0).is_empty() and not lv.sight_blocked(oa.x, oa.y, z + 41.0, ob.x, ob.y, z + 41.0),
		"and a round and an eye")
	var mid := m.centre(m.n / 2, m.n / 2)
	var far := Vector2(mid.x + 9000.0, mid.y + 7000.0)
	var t0 := Time.get_ticks_usec()
	for i in 200:
		lv.ray_hit_wall(mid.x, mid.y, z + 41.0, far.x, far.y, z + 41.0)
	check((Time.get_ticks_usec() - t0) / 200.0 < 2000.0, "a long ray across the maze is cheap (%.0f us)" % ((Time.get_ticks_usec() - t0) / 200.0))
	# ---- the grass and the plants ------------------------------------------------
	var g = game.island.get_node("GrassScatter")
	check(g.mask.is_valid(), "the grass has the maze's mask")
	var f = g._take_field()
	var under := 0
	var inside := 0
	var tried := 0
	var grid: float = g.grass_grid
	for r in range(m.n / 2 - 4, m.n / 2 + 4):
		for c in range(m.n / 2 - 4, m.n / 2 + 4):
			var q := m.centre(r, c)
			var cx := floori((q.x / 32.0) / grid)
			var cz := floori((-q.y / 32.0) / grid)
			for i in range(-6, 7):
				for j in range(-6, 7):
					var e: Dictionary = g._evaluate_cell(Vector2i(cx + i, cz + j), f)
					tried += 1
					if not e.valid:
						continue
					if m.near_m(e.pos.x, e.pos.z) <= 0.0:
						under += 1
					else:
						inside += 1
	# and out in the open corner, away from it: the same number of cells
	var corner := m.centre(m.n - 10, 10)
	var open := 0
	var otried := 0
	var side := int(sqrt(float(tried)))
	for i in side:
		for j in side:
			otried += 1
			var e2: Dictionary = g._evaluate_cell(Vector2i(floori(corner.x / 32.0 / grid) + i - side / 2, floori(-corner.y / 32.0 / grid) + j - side / 2), f)
			if e2.valid:
				open += 1
	g._release_field(f)
	check(under == 0, "no grass under a wall (%d of %d cells tried)" % [under, tried])
	var thick := float(inside) / tried
	var usual := float(open) / otried
	check(usual > 0.05, "grass out in the open, as usual (%.0f%% of cells)" % (usual * 100.0))
	check(thick > usual * 2.2, "and extra thick in the maze (%.0f%% of cells, %.1fx)" % [thick * 100.0, thick / maxf(usual, 1e-6)])
	var veg = game.island.get_node_or_null("VegScatter")
	check(veg != null, "the rest of the island has its trees, bushes and ferns")
	if veg != null:
		var vf = veg._take_field()
		var in_maze := 0
		var out := 0
		var vg: float = veg.veg_grid
		# (the middle section, 44 cells of 4 m each way: well inside the plus)
		for i in range(-44, 44):
			for j in range(-44, 44):
				var cell := Vector2i(i, j)
				var e3: Dictionary = veg._evaluate_cell(cell, vf)
				if e3.get("valid", false):
					in_maze += 1
				var e4: Dictionary = veg._evaluate_cell(Vector2i(floori((corner.x / 32.0) / vg) + i / 4, floori((-corner.y / 32.0) / vg) + j / 4), vf)
				if e4.get("valid", false):
					out += 1
		veg._release_field(vf)
		check(in_maze == 0, "no plant in the maze or round it (%d)" % in_maze)
		check(out > 0, "plants in the open corner (%d)" % out)
	# ---- the rest --------------------------------------------------------------------
	var view = game.island.get_node_or_null("Maze")
	check(view != null and view.walls == m.walls().size() and view.posts == m.posts().size(),
		"every wall and post drawn (%s walls)" % (str(view.walls) if view != null else "no view"))
	var st = null
	for t in lv.things:
		if t.type == "START":
			st = t
	var sc := m.cell_of(st.x, st.y)
	check(not m.blocked(st.x, st.y, 16.0) and not m.cell(sc.y, sc.x), "you start out of the walls, in the open by the maze")
	var stuck := 0
	for a2 in game.actors:
		if m.blocked(a2.x, a2.y, a2.radius * 0.5):
			stuck += 1
	check(stuck == 0, "nobody of the crowd in a wall (%d of %d)" % [stuck, game.actors.size()])
	var buried := 0
	if game.get("pickups") != null:
		for it in game.pickups.items:
			if m.blocked(it.x, it.y, 8.0):
				buried += 1
	check(buried == 0, "no pickup in a wall")
	print("maze: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
