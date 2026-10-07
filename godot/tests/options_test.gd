## MEWD — the build's number, the DISTANCE page, the settings file and
## the dedicated server's console, headless, on CANDY LAND:
##
##   godot --headless --script res://godot/tests/options_test.gd -- --map=candyland
##
## THE NUMBER: seven places, leading zeroes, the same in the game, the
## project and the export presets. DISTANCE (Distances): the land's
## reach, the trees' and the grass's fades and reach, the people's — set
## and set back. THE SETTINGS FILE (PauseMenu: SAVE, LOAD, DEFAULTS):
## every setting written by name and read back, a file's wrong-kinded
## value ignored. THE SERVER'S CONSOLE (NetHost.command): status,
## players, say, kick, restart on a team match. Prints OK or fails.
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	await process_frame
	# ---- the number ------------------------------------------------------
	var v := U.VERSION
	check(v.length() == 7 and v.is_valid_int() and v.begins_with("0"), "the version is seven places, leading zeroes (%s)" % v)
	check(str(ProjectSettings.get_setting("application/config/version")) == v, "project.godot says the same")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.count('version/name="%s"' % v) == 1 and presets.contains("version/code=%d" % int(v)),
		"and the Android preset (name %s, code %d)" % [v, int(v)])
	check(presets.contains('name="Linux Server"') and presets.contains('custom_features="server"'),
		"the standalone server has its preset, feature `server`")

	# ---- distances -------------------------------------------------------
	U.p_seed()
	var game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	for i in 30:
		await process_frame
	var isl = game.island
	var world = isl.get_node("IslandWorld")
	var veg = isl.get_node("VegScatter")
	var grass = isl.get_node("GrassScatter")
	var land0: float = world.view_distance
	var tree_end0: float = float(veg.material.get_shader_parameter("far_end"))
	var grass0: float = grass.view_distance
	Distances.apply(game, {"dist_land": 0.5, "dist_trees": 0.5, "dist_grass": 0.0, "dist_people": 1600.0})
	check(is_equal_approx(world.view_distance, land0 * 0.5), "LAND 50%%: the terrain's reach halved (%.0f m)" % world.view_distance)
	check(is_equal_approx(float(veg.material.get_shader_parameter("far_end")), tree_end0 * 0.5),
		"TREES 50%%: the trees fade out by half the distance (%.0f m)" % float(veg.material.get_shader_parameter("far_end")))
	var views: PackedFloat32Array = veg.get("_class_view_sq")
	check(views.size() == 3 and sqrt(views[0]) <= tree_end0 * 0.5 + 0.5, "and are dropped there (%.0f m)" % (sqrt(views[0]) if views.size() else -1.0))
	check(not grass.visible and not grass.is_processing(), "GRASS OFF: no grass, and nothing streaming it")
	check(game.standees.cull_far == 1600.0, "PEOPLE 50 M: the sprites drawn to 50 m")
	Distances.apply(game, {"dist_grass": 1.5})
	check(grass.visible and is_equal_approx(grass.view_distance, grass0 * 1.5), "GRASS 150%%: back, and further (%.0f m)" % grass.view_distance)
	Distances.apply(game, Distances.DEFAULTS)
	check(is_equal_approx(world.view_distance, land0) and is_equal_approx(float(veg.material.get_shader_parameter("far_end")), tree_end0)
		and is_equal_approx(grass.view_distance, grass0) and game.standees.cull_far == Standees.CULL_FAR,
		"and all back to the scene's own")

	# ---- the settings file ----------------------------------------------
	var path := PauseMenu.settings_path()
	var kept := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var pm := PauseMenu.new()
	root.add_child(pm)
	await process_frame
	for key in ["dist_land", "dist_trees", "dist_grass", "dist_people"]:
		check(pm.tiles.has(key) and pm.DIALS.any(func(d): return d[0] == key and d[2] == 5), "%s is on the DISTANCE page" % key)
	pm.show_page(7)
	check(pm._stops() == ["save_file", "load_file", "defaults"], "the FILE page: SAVE, LOAD, DEFAULTS (%s)" % str(pm._stops()))
	pm.prefs["dist_trees"] = 0.25
	pm.prefs["bright"] = 1.75
	pm.prefs["weather"] = "rain"
	check(pm.write_settings_file() == OK and FileAccess.file_exists(path), "SAVE writes %s" % ProjectSettings.globalize_path(path))
	var cf := ConfigFile.new()
	cf.load(path)
	check(str(cf.get_value("mewd", "version")) == U.VERSION and float(cf.get_value("settings", "dist_trees")) == 0.25
		and str(cf.get_value("settings", "weather")) == "rain", "every setting in it by name, with the build's number")
	pm.prefs = PauseMenu.DEFAULTS.duplicate()
	check(pm.read_settings_file() == OK and pm.prefs.dist_trees == 0.25 and pm.prefs.bright == 1.75 and pm.prefs.weather == "rain",
		"LOAD reads them back")
	cf.set_value("settings", "bright", "very")
	cf.erase_section_key("settings", "weather")
	cf.save(path)
	pm.prefs["weather"] = "mist"
	pm.read_settings_file()
	check(pm.prefs.bright == 1.75 and pm.prefs.weather == "mist", "a wrong-kinded or missing value keeps what it was")
	pm._act("defaults")
	check(pm.prefs == PauseMenu.DEFAULTS, "DEFAULTS puts everything back")
	if kept != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(kept)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	pm.queue_free()
	game.queue_free()
	await process_frame

	# ---- the server's console --------------------------------------------
	var h := NetHost.new()
	h.listen = true
	h.port = 7871
	root.add_child(h)
	check(h.start("candyland", 5, {"people": 0}, 4, {"teams": true}, []) == OK, "a team match is hosted")
	var st := h.command("status")
	check(st.contains("CANDY LAND") and st.contains("team deathmatch") and st.contains("SWAT 0") and st.contains("0/4 players"),
		"status: the island, the match, the sides, the players")
	check(h.command("players") == "nobody on", "players: nobody on")
	h.command("say the bar is open")
	check(h.sim.match_.events.any(func(e): return e.get("k") == "say" and e.text == "the bar is open"), "say: a line for everybody")
	check(h.command("kick 9").begins_with("no player"), "kick: nobody of that name")
	check(h.command("restart") == "round 2", "restart: round 2")
	check(h.command("dance").begins_with("no command"), "anything else: no such command")
	check(NetHost.usage().contains("--teams") and NetHost.usage().contains(U.VERSION), "the usage has the flags and the number")
	h.close()
	h.queue_free()
	await process_frame
	print("options: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
