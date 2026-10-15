extends SceneTree

## THE TERRAIN ENGINE, every place in Islands.LIST brought up through the
## viewer (godot/scripts/main.gd), one after the other: its terrain built (off
## its bake, if tools/bake_island.gd made one), its plants planted, the eye
## over its ground, its picture's own settings taken.
##
##   godot --headless --script res://godot/tests/terrain_test.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		fails += 1
		print("  FAIL ", what)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	check(Islands.LIST.size() >= 2, "the places: %s" % ", ".join(Islands.LIST.map(func(i): return i.key)))
	var main: Node = (load("res://godot/scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	for spec in Islands.LIST:
		print("== %s" % spec.title)
		if main.spec.key != spec.key:
			main.load_place(spec.key)
		await process_frame
		await process_frame
		var tb: Node = root.get_node("TerrainBake")
		var waited := 0
		while not main.place_ready() and waited < 9000:
			await process_frame
			waited += 1
		check(main.place_ready(), "it is up (terrain and plants) after %d frames" % waited)
		var iw: Node = main.place.get_node("IslandWorld")
		check(iw.get_child_count() > 0, "its terrain is built (%d nodes)" % iw.get_child_count())
		var st: Dictionary = tb.stats()
		check(int(st.held) > 0 and int(st.hits) > 0,
				"off its bake (%d chunk meshes held, %d read)" % [int(st.held), int(st.hits)])
		var vs: Node = main.place.get_node_or_null("VegScatter")
		check(vs == null or vs.get_child_count() > 0, "its plants are planted")
		var cp: Vector3 = main.cam.global_position
		var g: float = main._ground(cp.x, cp.z)
		check(not is_nan(g) and cp.y > g, "the eye is over its ground (%.1f m)" % (cp.y - g))
		var lm: ShaderMaterial = main.lofi.mat
		check(float(lm.get_shader_parameter("exposure")) == float(spec.get("exposure", 1.0))
				and float(lm.get_shader_parameter("grade")) == (0.0 if spec.get("grade", {}).is_empty() else 1.0)
				and float(lm.get_shader_parameter("meter_on")) == (0.0 if spec.get("meter", {}).get("off", false) else 1.0),
				"the picture takes its exposure, meter and grade")
		# nothing of the game is left in it
		var stray := []
		for n in main.place.find_children("*", "", true, false):
			var sc: Script = n.get_script()
			if sc != null and (sc.resource_path.contains("/game/") or sc.resource_path.contains("veg_burn")):
				stray.append(n.name)
		check(stray.is_empty(), "no gameplay in its scene %s" % str(stray))
	print("terrain: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
