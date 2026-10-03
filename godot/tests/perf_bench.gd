## MEWD — WHERE THE TIME GOES, on a real Game (at the user's request,
## after the handheld lagged on the bore's finish, on a rocket into a
## crowd, a little on the maze and badly on THE SPRAWL).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##     --script res://godot/tests/perf_bench.gd -- --map=sprawl [--json=out.json]
##
## Not --headless: the renderer must be up (under xvfb, the Mobile
## renderer on Vulkan, real decals on — the handheld's path). Builds the
## game on the map and reports: how long it took; what the renderer is
## asked to draw looking four ways from the start (draw calls, objects,
## primitives); how many meshes the level is; then THE TWO EXPLOSIONS —
## a rocket into a ring of eight shoppers in front of the player, and the
## cerebral bore's finish on one — each timed as the call itself, and as
## the frames after it against the frames before (the script's share of
## a frame from the game's own profiler, and the frame as a whole, which
## under llvmpipe is mostly the drawing). Numbers to compare, before and
## after a change; it fails nothing.
extends SceneTree

var game
var out := {}

func _init() -> void:
	U.p_seed()
	var json := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--json="):
			json = a.substr(7)
	var t0 := Time.get_ticks_msec()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	out["map"] = game.level.name
	out["load_ms"] = Time.get_ticks_msec() - t0
	var meshes := 0
	var tris := 0
	for c in game.get_children():
		if c.name == "LevelGeometry":
			for mi in c.get_children():
				if mi is MeshInstance3D:
					meshes += 1
					tris += mi.mesh.surface_get_array_len(0) / 3 if mi.mesh.get_surface_count() > 0 else 0
	out["level_meshes"] = meshes
	out["level_vertices_over_3"] = tris
	out["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	out["people"] = game.actors.size()
	game._prof_on = true
	game._prof_print = false
	# --warm: what Main does under the loading screen (Warmup, and a real
	# mark of every kind on the floor ahead), so the first explosion is
	# measured as the game has it
	if OS.get_cmdline_user_args().has("--warm"):
		var warm := Warmup.begin([game])
		var p0 = game.player
		var ax: float = p0.x + cos(p0.angle) * 120.0
		var ay: float = p0.y + sin(p0.angle) * 120.0
		var sc: Level.Sector = game.level.span_at(ax, ay, p0.z + 1.0)
		var wat := Vector3(ax, ay, sc.floor if sc else p0.z)
		game.decals.warm_begin(wat)
		game.gore_decals.warm_begin(wat)
		for k in 4:
			await process_frame
		game.decals.warm_end()
		game.gore_decals.warm_end()
		Warmup.end(warm)
		out["warmed"] = true
	for k in 20:
		await process_frame
	# LOOKING ROUND: four ways from the start
	var looks := []
	var p = game.player
	# (the bench's own rockets go off near the player: nobody dies of them)
	p.invincible = true
	var a0: float = p.angle
	for q in 4:
		p.angle = a0 + q * PI / 2.0
		for k in 6:
			await process_frame
		var dc := 0.0
		var ob := 0.0
		var pr := 0.0
		for k in 4:
			await process_frame
			dc = maxf(dc, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			ob = maxf(ob, Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			pr = maxf(pr, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		looks.append({"deg": q * 90, "draw_calls": int(dc), "objects": int(ob), "primitives": int(pr)})
	p.angle = a0
	out["looks"] = looks
	# THE STEADY STATE: frames and the script's share of them
	out["steady"] = await _frames(40)
	# A ROCKET INTO A CROWD
	var ring := _ring(p, 8, 150.0)
	await _frames(5)
	var at := Vector3(p.x + cos(p.angle) * 150.0, p.y + sin(p.angle) * 150.0, p.z + 30.0)
	var tc := Time.get_ticks_usec()
	game.missiles.detonate(at)
	out["rocket_call_ms"] = (Time.get_ticks_usec() - tc) / 1000.0
	out["rocket_killed"] = ring.filter(func(a): return a.dead or a.removed).size()
	# the first frames one by one: the whole frame, and the script's share
	var trace := []
	var tt := Time.get_ticks_usec()
	for f in 8:
		game._prof = {}
		await process_frame
		var now := Time.get_ticks_usec()
		var sc := 0.0
		for k in game._prof:
			if not str(k).begins_with("tic."):
				sc += game._prof[k]
		trace.append([snappedf((now - tt) / 1000.0, 0.1), snappedf(sc / 1000.0, 0.1)])
		tt = now
	out["rocket_trace"] = trace
	out["rocket_after"] = await _frames(52)
	out["rocket_marks"] = _marks()
	await _frames(120)
	# AND A SECOND ONE, the other way: what the first paid once (a shader
	# compiled, a pool made) it does not pay again
	p.angle += PI
	var ring2 := _ring(p, 8, 150.0)
	await _frames(5)
	at = Vector3(p.x + cos(p.angle) * 150.0, p.y + sin(p.angle) * 150.0, p.z + 30.0)
	tc = Time.get_ticks_usec()
	game.missiles.detonate(at)
	out["rocket2_call_ms"] = (Time.get_ticks_usec() - tc) / 1000.0
	out["rocket2_after"] = await _frames(60)
	p.angle -= PI
	await _frames(120)
	# THE BORE'S FINISH on one
	# (to the side, clear of whatever the rockets left burning; and alive)
	var v = null
	for tries in 6:
		p.angle += PI / 2.0
		var one: Array = _ring(p, 1, 110.0)
		await _frames(5)
		if not one[0].dead and not one[0].removed and one[0].burning <= 0:
			v = one[0]
			break
	out["bore_victim_ok"] = v != null
	if v == null:
		v = _ring(p, 1, 110.0)[0]
	v.bored_by = p
	tc = Time.get_ticks_usec()
	v.bore_burst()
	out["bore_call_ms"] = (Time.get_ticks_usec() - tc) / 1000.0
	out["bore_after"] = await _frames(60)
	out["bore_marks"] = _marks()
	var s := JSON.stringify(out, "  ")
	print(s)
	if json != "":
		var f := FileAccess.open(json, FileAccess.WRITE)
		f.store_string(s)
		f.close()
	quit()

## n shoppers in a ring `d` ahead of the player
func _ring(p, n: int, d: float) -> Array:
	var cx: float = p.x + cos(p.angle) * d
	var cy: float = p.y + sin(p.angle) * d
	var got := []
	for k in n:
		var ang := TAU * k / maxf(1.0, n)
		var r := 0.0 if n == 1 else 40.0
		var a = game.spawn("SHOPPER", cx + cos(ang) * r, cy + sin(ang) * r, 0.0)
		got.append(a)
	return got

## `n` frames: the worst and the mean whole frame, and the script's share
## (the game's profiler: its tics and its draws)
func _frames(n: int) -> Dictionary:
	var worst := 0.0
	var sum := 0.0
	var acc := {}
	var t := Time.get_ticks_usec()
	for k in n:
		# (read and emptied every frame: the game's own profiler empties
		# itself every sixty, which would lose a window's worth)
		game._prof = {}
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - t) / 1000.0
		t = now
		worst = maxf(worst, ms)
		sum += ms
		for key in game._prof:
			acc[key] = acc.get(key, 0) + game._prof[key]
	var script := 0.0
	var parts := {}
	for key in acc:
		if not str(key).begins_with("tic."):
			script += acc[key]
		parts[key] = snappedf(acc[key] / 1000.0 / n, 0.01)
	return {"frames": n, "frame_mean_ms": snappedf(sum / n, 0.1), "frame_worst_ms": snappedf(worst, 0.1),
		"script_mean_ms": snappedf(script / 1000.0 / n, 0.1), "parts_mean_ms": parts}

func _marks() -> Dictionary:
	return {"gore_marks": game.gore_decals.mm.visible_instance_count, "gore_quads": game.gore_decals.get_child_count(), "giblets_live": game.giblets.live_count(),
		"fx_live": game.fx.live_count() if game.fx.has_method("live_count") else -1}
