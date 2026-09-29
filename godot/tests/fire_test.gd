## MEWD — the fire on the maze, for comparison with the web build's.
##
## godot --headless --script res://godot/tests/fire_test.gd -- [seed] [scenario]
##
## Builds MazeMap.build(seed) through DocCompile, puts a FireSystem on it
## with a stub game (no player), lights the START and prints the fire
## every 250 tics — the same as godot/tests/fire_js.mjs does against
## js/fire.js. Both seed pRandom the same and walk the cells in the same
## order, so the two columns of numbers should agree.
##
##   bare  the maze as it is: no fuel anywhere, so only a bottle's worth
##         of accelerant (ignite 190, 68) burns, and it cannot spread
##   fuel  the paths made of stock (fuel 300) and one match (ignite 60)
##   char  the paths made of stock and roofed, and the whole of the path
##         the START is in lit at once — to see it char, gut, cook and
##         come down
##   actor one shopper stood in the fire, to see _burn_things light them
extends SceneTree

class StubGame:
	var level: Level
	var actors: Array = []
	var player = null
	var fire = null
	var tics := 0
	var blockmap := ActorGrid.new()
	func play_sound(_n, _a) -> void:
		pass
	func scare(_x, _y, _r) -> void:
		pass
	func gib(a) -> void:
		a.remove()
	func on_monster_killed(_a, _s) -> void:
		pass

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 7
	var scenarios: Array = [args[1]] if args.size() > 1 else ["bare", "fuel", "char", "actor"]
	for sc in scenarios:
		_run(seed, sc)
	quit()

func _run(seed: int, sc: String) -> void:
	var doc := MazeMap.build(seed)
	if sc == "fuel" or sc == "char":
		for s in doc.sectors:
			if s.get("name", "") == "path":
				s["fuel"] = 300
				if sc == "char":
					s["ceilTex"] = "FLAT"
	var g := StubGame.new()
	g.level = DocCompile.compile(doc)
	U.p_seed()
	var t0 := Time.get_ticks_msec()
	var fire := FireSystem.new(g)
	g.fire = fire
	var build_ms := Time.get_ticks_msec() - t0
	var links := 0
	for i in fire.link.size():
		if fire.link[i]:
			links += 1
	print("GD %s: grid %dx%d, total fuel %.1f, linked cells %d (built in %d ms)" % [sc, fire.cols, fire.rows, fire.total_fuel, links, build_ms])
	var start = null
	for t in g.level.things:
		if t.type == "START":
			start = t
			break
	var sx := float(start.x)
	var sy := float(start.y)
	var who: Actor = null
	if sc == "actor":
		who = Actor.new(g, "SHOPPER", sx, sy)
		g.actors.append(who)
	var lit := 0
	if sc == "fuel":
		lit = fire.ignite(sx, sy)
	elif sc == "char":
		var home: Level.Sector = g.level.sector_at(sx, sy)
		var c := home.bbox.get_center()
		lit = fire.ignite(c.x, c.y, 60, maxf(home.bbox.size.x, home.bbox.size.y) / 2.0)
		print("  sector %d, %d cells, structural %d" % [home.index, fire.sector_cells[home.index], fire.structural[home.index]])
	else:
		lit = fire.ignite(sx, sy, 190, 68)
	print("  ignite at %d,%d: %d cells" % [sx, sy, lit])
	var total := 350 if sc == "actor" else (8000 if sc == "char" else 3500)
	t0 = Time.get_ticks_msec()
	for t in range(1, total + 1):
		g.tics = t
		fire.tic()
		if who != null:
			who.tic()
		if t % (50 if sc == "actor" else (500 if sc == "char" else 250)) == 0:
			var ch := 0
			var gu := 0
			var co := 0
			for si in fire.charred.size():
				ch += fire.charred[si]
				gu += fire.gutted[si]
				co += fire.collapsed[si]
			var extra := ""
			if who != null:
				extra = "  shopper burning %d health %d dead %s" % [who.burning, who.health, who.dead]
			print("  tic %4d  hot %4d  live %4d  burnt %.3f%%  charred %d gutted %d collapsed %d%s" % [t, fire.hot_cells, fire.active.size(), fire.burn_fraction() * 100.0, ch, gu, co, extra])
	print("  %d tics in %d ms" % [total, Time.get_ticks_msec() - t0])
