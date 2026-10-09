## MEWD — EVERY CORE (Cores; at the user's request: "this runs like crap on
## my old xeon 2.4ghz box because cpu events are only using 1 core, can we
## have it use all available processors in parallel? can we also put the
## debug data in the lower left corner").
##
##   godot --headless --script res://godot/tests/cores_test.gd -- --map=candyland --perf-log
##
## RENDERING ON A THREAD OF ITS OWN: project.godot puts it there on the
## desktop and not on Android or the server; this run has it; the DEBUG
## page's RENDER THREAD writes the file Godot reads before it starts, and
## a fresh copy of the game started on it (this script again, --report)
## really does run where it says — its own, the game's, and back to
## project.godot's — and the readout says where, and where next time; the
## performance log does not stop the renderer every frame to ask its
## times (PerfLog).
## THE CROWD'S STEPS, CHEAPEST QUESTION FIRST (Actor.can_stand_at): the
## same answer as the old order everywhere it is asked — beside bodies,
## trees, players and open ground — and A_Watch still takes fright at
## somebody alight or somebody running past, and at nothing else.
## THE READOUT IN THE LOWER LEFT CORNER (PerfOverlay): its bottom on the
## edge, or on what has the corner (the title's version); the gun's
## notices stacked above it while it shows (Hud.toasts_bottom).
## Prints OK or fails.
extends SceneTree

var fails := 0
var game

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	# (the copy of the game this one starts: where is its renderer?)
	if OS.get_cmdline_user_args().has("--report"):
		print("RENDER_THREAD " + ("own" if Cores.render_own() else "main"))
		quit(0)
		return
	# (a script error in an awaiting _init would leave the process running
	# for ever, and the suite with it)
	create_timer(600.0).timeout.connect(func(): print("cores: TIMED OUT"); quit(2))
	await process_frame
	var kept := FileAccess.get_file_as_string(Cores.RENDER_CFG) if FileAccess.file_exists(Cores.RENDER_CFG) else ""
	_render()
	_restore(kept)
	await _crowd()
	_readout()
	print("cores: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)

# ---- rendering on a thread of its own ------------------------------------

func _render() -> void:
	var proj := FileAccess.get_file_as_string("res://project.godot")
	check(proj.contains("\ndriver/threads/thread_model=2\n") and proj.contains("\ndriver/threads/thread_model.android=1\n")
		and proj.contains("\ndriver/threads/thread_model.server=1\n"),
		"project.godot: the renderer on its own thread on the desktop, not on Android or the server")
	check(str(ProjectSettings.get_setting("application/config/project_settings_override")) == Cores.RENDER_CFG,
		"and Godot reads the DEBUG page's file before it starts (%s)" % Cores.RENDER_CFG)
	Cores.want_render("auto")
	check(not FileAccess.file_exists(Cores.RENDER_CFG) and Cores.render_wanted() == "auto" and Cores.render_next() == "own",
		"AUTO: no file, and the desktop's way next time (its own)")
	check(_child() == "own", "a fresh copy of the game on AUTO renders on a thread of its own")
	Cores.want_render("main")
	var text := FileAccess.get_file_as_string(Cores.RENDER_CFG)
	check(text.contains("thread_model=1\n") and text.contains("thread_model.android=1\n") and Cores.render_wanted() == "main",
		"GAME'S CORE writes the file, Android's override with it")
	check(_child() == "main", "and a fresh copy of the game renders on the game's thread")
	check(Cores.state().contains("next launch: the game's") == Cores.render_own(),
		"the readout says where it is now, and where next launch (%s)" % Cores.state())
	Cores.want_render("own")
	text = FileAccess.get_file_as_string(Cores.RENDER_CFG)
	check(text.contains("thread_model=2\n") and text.contains("thread_model.android=2\n") and _child() == "own",
		"OWN CORE: the file says so, and a fresh copy renders on its own thread")
	Cores.want_render("sideways")
	check(not FileAccess.file_exists(Cores.RENDER_CFG), "a way it does not know (a settings file edited by hand) is AUTO")
	var d: Dictionary = PauseMenu.DEFAULTS
	var dial: Array = PauseMenu.DIALS.filter(func(x): return x[0] == "render_thread")
	check(d.get("render_thread") == "auto" and dial.size() == 1 and dial[0][2] == 6
		and dial[0][3].map(func(v): return v[0]) == Cores.RENDER_WAYS,
		"the DEBUG page has RENDER THREAD: AUTO, OWN CORE, GAME'S CORE; AUTO the default")
	check(FileAccess.get_file_as_string("res://godot/scripts/main.gd").contains("Cores.want_render(str(p.get(\"render_thread\""),
		"and the menu's choice is written when the settings are applied (Main.apply_prefs)")

func _child() -> String:
	var out := []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://godot/tests/cores_test.gd", "--", "--report"], out, true)
	for line in str("\n".join(out)).split("\n"):
		if line.begins_with("RENDER_THREAD "):
			return line.substr(14).strip_edges()
	return "?"

func _restore(kept: String) -> void:
	if kept == "":
		Cores.want_render("auto")
	else:
		var f := FileAccess.open(Cores.RENDER_CFG, FileAccess.WRITE)
		f.store_string(kept)
		f.close()

# ---- the crowd's steps -----------------------------------------------------

func _crowd() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	for k in 10:
		await process_frame
	var p = game.player
	p.invincible = true
	check(PerfLog.inst != null and PerfLog.inst._render_times == not Cores.render_own(),
		"the performance log asks the renderer its times only on the game's thread (asking its own thread would stall it every frame)")
	# a knot of them in front of the player, packed, so steps fail on bodies
	var cx: float = p.x + cos(p.angle) * 200.0
	var cy: float = p.y + sin(p.angle) * 200.0
	var knot := []
	for k in 24:
		var ang := TAU * k / 24.0
		var r := 20.0 + 14.0 * (k % 3)
		knot.append(game.spawn("CANDYGIRL", cx + cos(ang) * r, cy + sin(ang) * r, 0.0))
	var who: Array = knot.duplicate()
	for a in game.awake:
		if who.size() >= 220:
			break
		if not who.has(a):
			who.append(a)
	var asked := 0
	var same := 0
	var why := {"body": 0, "player": 0, "tree": 0, "wall": 0, "free": 0}
	for a: Actor in who:
		if a.removed or a.dead:
			continue
		for d in 8:
			for reach in [a.speed, a.speed * 3.0, 40.0]:
				var nx: float = a.x + cos(Actor.DIR_ANGLE[d]) * reach
				var ny: float = a.y + sin(Actor.DIR_ANGLE[d]) * reach
				var old := _old_can_stand(a, nx, ny)
				asked += 1
				if a.can_stand_at(nx, ny) == old[0]:
					same += 1
				why[old[1]] += 1
	# and round the trees, where the steps fail on trunks
	var f = game.forest
	if f != null and f.trees.n > 0:
		var a: Actor = who[0]
		var ox: float = a.x
		var oy: float = a.y
		for t in mini(f.trees.n, 300):
			var tx: float = f.trees.x[t]
			var ty: float = f.trees.y[t]
			for d in 8:
				a.x = tx + cos(Actor.DIR_ANGLE[d]) * 40.0
				a.y = ty + sin(Actor.DIR_ANGLE[d]) * 40.0
				var nx: float = tx + cos(Actor.DIR_ANGLE[d]) * 12.0
				var ny: float = ty + sin(Actor.DIR_ANGLE[d]) * 12.0
				var old := _old_can_stand(a, nx, ny)
				asked += 1
				if a.can_stand_at(nx, ny) == old[0]:
					same += 1
				why[old[1]] += 1
		a.x = ox
		a.y = oy
	# and up against the player
	var b: Actor = who[1]
	var bx: float = b.x
	var by: float = b.y
	for d in 8:
		b.x = p.x + cos(Actor.DIR_ANGLE[d]) * 60.0
		b.y = p.y + sin(Actor.DIR_ANGLE[d]) * 60.0
		for reach in [10.0, 30.0, 50.0]:
			var nx: float = b.x - cos(Actor.DIR_ANGLE[d]) * reach
			var ny: float = b.y - sin(Actor.DIR_ANGLE[d]) * reach
			var old := _old_can_stand(b, nx, ny)
			asked += 1
			if b.can_stand_at(nx, ny) == old[0]:
				same += 1
			why[old[1]] += 1
	b.x = bx
	b.y = by
	check(asked > 2000 and same == asked, "the crowd's steps: the same answer as the old order, every time (%d of %d)" % [same, asked])
	# (on an island the old forest is there empty — its plants are the
	# island's own, Game.start_map — so trunks are asked where there are any)
	check(why.body > 50 and why.player > 5 and why.wall > 20 and why.free > 50 and (why.tree > 20 or f == null or f.trees.n == 0),
		"asked beside bodies, the player, walls, trees where there are any, and open ground (%s)" % str(why))
	# A_Watch: frightened by somebody alight, by somebody running past, and
	# by nothing else
	var sx: float = p.x - cos(p.angle) * 600.0
	var sy: float = p.y - sin(p.angle) * 600.0
	var calm: Actor = game.spawn("SHOPPER", sx, sy, 0.0)
	var fire: Actor = game.spawn("SHOPPER", sx + 100.0, sy, 0.0)
	var runner: Actor = game.spawn("SHOPPER", sx, sy + 150.0, 0.0)
	game.tics += 1
	calm.A_Watch()
	check(calm.panic == 0, "nobody alight, nobody running: no fright")
	fire.burning = 50
	calm.A_Watch()
	check(calm.panic > 0 and calm.flee_x == fire.x and calm.flee_y == fire.y, "somebody alight close by: a fright, away from them")
	fire.burning = 0
	calm.panic = 0
	calm.wary = false
	runner.panic = 200
	runner.flee_x = sx - 777.0
	runner.flee_y = sy + 333.0
	game.tics += 1
	calm.A_Watch()
	# (200 less A_Watch's FADE, less the first step of running, which
	# takes a tic off it)
	check(calm.panic > 150 and calm.panic <= 200 - 24 and calm.flee_x == runner.flee_x and calm.flee_y == runner.flee_y,
		"somebody running past: their fright passed on, a little weaker (%d of their 200)" % calm.panic)

## Actor.can_stand_at as it was before the cheapest question went first,
## and which question said no
func _old_can_stand(a: Actor, nx: float, ny: float) -> Array:
	var g = a.game
	var r: Vector3 = g.level.slide_move(a.x, a.y, nx - a.x, ny - a.y, a.radius, a.z, a.height, true)
	if r.z > 0.0 or absf(r.x - nx) > 0.01 or absf(r.y - ny) > 0.01:
		return [false, "wall"]
	if g.forest != null and not (g.level.layered and a.sector != null and a.sector.storey > 0) and g.forest.blocks(nx, ny, a.radius):
		return [false, "tree"]
	var layered: bool = g.level.layered
	for o in g.blockmap.near(nx, ny):
		if o == a or o.removed or not o.solid or o.dead:
			continue
		if layered and (o.z >= a.z + a.height or a.z >= o.z + o.height):
			continue
		var rr: float = a.radius + o.radius
		if U.dist2(nx, ny, o.x, o.y) < rr * rr:
			return [false, "body"]
	for pl in g.players:
		if pl == null or pl.dead or (layered and (pl.z >= a.z + a.height or a.z >= pl.z + pl.height)):
			continue
		var rr: float = a.radius + pl.radius
		if U.dist2(nx, ny, pl.x, pl.y) < rr * rr:
			return [false, "player"]
	return [true, "free"]

# ---- the readout in the lower left corner -----------------------------------

func _readout() -> void:
	var ov := PerfOverlay.new()
	root.add_child(ov)
	ov.visible = true
	ov._process(1.0)
	var vr := ov.get_viewport_rect().size
	check(ov.label.text.contains(Cores.state()), "the readout says the cores and where the renderer is")
	check(is_equal_approx(ov.position.x, PerfOverlay.EDGE) and absf(ov.position.y + ov.size.y - (vr.y - PerfOverlay.EDGE)) < 0.5,
		"the readout in the lower left corner (%s, %s on %s)" % [ov.position, ov.size, vr])
	check(ov.position.y > vr.y * 0.4, "and not up at the top, over the health and armour (top at %.0f of %.0f)" % [ov.position.y, vr.y])
	var tall := ov.size.y
	ov.label.text = "one line"
	ov.place()
	check(ov.size.y < tall and absf(ov.position.y + ov.size.y - (vr.y - PerfOverlay.EDGE)) < 0.5,
		"fewer lines: shrunk back, still on the corner (%.0f from %.0f)" % [ov.size.y, tall])
	var under := Control.new()
	root.add_child(under)
	under.position = Vector2(8.0, vr.y - 38.0)
	under.size = Vector2(60.0, 30.0)
	ov.stand_on = under
	ov.place()
	check(absf(ov.position.y + ov.size.y - (vr.y - 38.0 - 4.0)) < 0.5, "on the title, standing on what has the corner (the version: stand_on)")
	ov.stand_on = null
	under.queue_free()
	ov._process(1.0)
	var hud := Hud.new()
	hud.perf = ov
	root.add_child(hud)
	hud.size = vr
	check(absf(hud.toasts_bottom(1.0) - (ov.position.y - 8.0)) < 0.5 and hud.toasts_bottom(1.0) < vr.y - 20.0,
		"the gun's notices stacked above it while it shows")
	ov.visible = false
	check(is_equal_approx(hud.toasts_bottom(1.0), vr.y - 20.0), "and down on the edge when it does not")
	hud.queue_free()
	ov.queue_free()
