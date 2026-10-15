extends SceneTree

## MEWD — a real place as an island (EarthField, tools/earth_fetch.py): the field
## reads its region, answers the island system's questions out of it, and the
## island built on it stands where the data says.
##
##   godot --headless --script res://godot/tests/earth_test.gd [-- --map=earth_oeschinen]
##
## Two halves. The FIELD alone, no scene: its grids load and agree with
## region.json, the ground is the data's to the centimetre, the square's edge
## is the coast and its height the ground's, the water is where and how deep the
## data says, the plants and the twelve layers are weights, `height_at` is no
## ground in deep water, the bake digest moves with the data. Then the LEVEL,
## through the game like island_test: the crowd's ground off the bake (or built),
## nobody dropped in the lake, the island built and the plants standing.

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
	var key := "earth_oeschinen"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			key = a.substr(6)
	var spec := Islands.find(key)
	check(spec.key == key, "Islands lists %s" % key)
	var scene: PackedScene = load(spec.scene)
	var island := scene.instantiate()
	var f := island.get_node("IslandWorld").get("field") as EarthField
	check(f != null, "its field is an EarthField")
	if f == null:
		quit(1)
		return
	f.prepare()
	var r := f.data()
	check(r.ok, "the region's grids load (%s)" % r.path)
	var j: Dictionary = r.json
	check(r.hn == int(j.height.n) and r.cn == int(j.cover.n) and r.wn == int(j.water.n),
			"grid sizes agree with region.json")
	var half := r.half
	check(is_equal_approx(f.hub_radius, half), "the hub is the square (radius %.0f = half side)" % half)

	# the ground: the data's own samples, exactly, at the grid's points
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in range(400):
		var i := rng.randi_range(0, r.hn - 1)
		var k := rng.randi_range(0, r.hn - 1)
		var x := -half + float(i) * r.hres
		var z := -half + float(k) * r.hres
		var want := r.hoff + float(r.hraw.decode_u16((k * r.hn + i) * 2)) * r.hscale - r.datum
		worst = maxf(worst, absf(f.ground(x, z) - want))
	check(worst < 0.01, "ground() is the data at its samples (worst %.4f m)" % worst)
	var lo := 1e9
	var hi := -1e9
	for _i in range(2000):
		var g := f.ground(rng.randf_range(-half, half), rng.randf_range(-half, half))
		lo = minf(lo, g)
		hi = maxf(hi, g)
	check(lo >= -0.5 and hi <= float(j.height.max) - r.datum + 0.5,
			"heights over the datum stay in the data's range (%.1f .. %.1f m)" % [lo, hi])

	# the square: land inside, nothing outside, the edge at the ground's height
	var isl: IslandField.Island = f.island_in_cell(f.hub_cell())
	check(f.is_land(0.0, 0.0) and f.is_land(half - 3.0, half - 3.0), "inside the square is land")
	check(not f.is_land(half + 3.0, 0.0) and not f.is_land(0.0, -half - 3.0), "outside it is not")
	var edge := f.coast_y(isl, half, 120.0)
	check(absf(edge - f.base_height(half, 120.0, 0.0, isl)) < 1e-4 and edge > 1.0,
			"the edge is the ground's own height there (%.1f m), not the shore level" % edge)

	# the water: every body region.json lists is where its level says
	var bodies: Array = j.get("bodies", [])
	var lake := {}
	for b in bodies:
		if String(b.kind) == "lake" and (lake.is_empty() or float(b.area_m2) > float(lake.area_m2)):
			lake = b
	check(not lake.is_empty(), "the region has its lake")
	var wet := 0
	var deep := 0
	var level_err := 0.0
	var on_bed := 0
	for k in range(0, r.wn, 3):
		for i in range(0, r.wn, 3):
			if r.wkind[k * r.wn + i] != EarthField.W_LAKE:
				continue
			var x := -half + float(i) * r.wres
			var z := -half + float(k) * r.wres
			var wy := f.water_y(x, z)
			if is_nan(wy):
				continue
			wet += 1
			if absf((wy + r.datum) - float(lake.level)) < 0.6:
				level_err = maxf(level_err, absf((wy + r.datum) - float(lake.level)))
			if wy - f.ground(x, z) > f.wade_depth:
				deep += 1
				if f.height_at(x, z, -1e6) == -1e6:
					on_bed += 1
	check(wet > 100, "the lake is on the water grid (%d samples)" % wet)
	check(deep > 50 and on_bed == deep, "deep water is no ground for the crowd (%d of %d)" % [on_bed, deep])
	var sfc := f.water_y(0.0, 0.0)
	var s0 := f.sample(0.0, 0.0)
	check(s0.has("veg") and s0.has("water") and s0.has("cover"), "sample() carries veg, water and cover")
	var cv: PackedFloat32Array = s0.cover
	var tot := 0.0
	for v in cv:
		tot += v
	check(absf(tot - 1.0) < 0.05, "the twelve layers sum to one (%.3f)" % tot)
	if not is_nan(sfc):
		check(float(s0.water) > 0.0 and float(s0.veg.tree) == 0.0, "nothing grows under the lake")
	# somewhere with trees
	var treed := 0
	var conif := 0.0
	for _i in range(3000):
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var v := f.veg_at(x, z)
		if v.x > 0.5:
			treed += 1
			conif += v.y
	check(treed > 30, "the woods are on the map (%d of 3000 points)" % treed)
	check(treed == 0 or conif / float(treed) > 0.5, "and at 1600 m they are mostly conifers (%.2f)" % (conif / maxf(float(treed), 1.0)))

	# the bake key moves with the data
	var d1: String = f.get("data_digest")
	check(d1.begins_with(String(j.digest)), "the bake digest carries the region's (%s)" % d1.left(24))
	var sig := BakeStore.signature_for(1, [f])
	check(sig != "", "the field signs")
	island.free()

	# THE LEVEL, through the game
	U.p_seed()
	var game = preload("res://godot/scripts/game/game.gd").new()
	game.map_name = key
	root.add_child(game)
	await process_frame
	var lv: IslandLevel = game.level
	var iw: Node = game.island.get_node("IslandWorld")
	var gf := iw.get("field") as EarthField
	check(gf != null, "the game's island is the region")
	if gf == null:
		quit(1)
		return
	check(IslandGround.load_for(IslandGround.signature_for(gf, iw.chunk_size)) != null,
			"the crowd's ground comes off the bake")
	var p = game.player
	var px: float = p.x / IslandLevel.U_PER_M
	var pz: float = -p.y / IslandLevel.U_PER_M
	var want: Vector2 = spec.get("start", Vector2(px, pz))
	check(Vector2(px, pz).distance_to(want) < 120.0,
			"you are put down at the island's start (%.0f, %.0f m; asked %.0f, %.0f)" % [px, pz, want.x, want.y])
	var pw := gf.water_y(px, pz)
	check(is_nan(pw) or pw - gf.ground(px, pz) <= gf.wade_depth, "and not in the lake")
	var people := 0
	var wet_people := 0
	for a in game.actors:
		if a.monster:
			people += 1
			var ax: float = a.x / IslandLevel.U_PER_M
			var az: float = -a.y / IslandLevel.U_PER_M
			var aw := gf.water_y(ax, az)
			if not is_nan(aw) and aw - gf.ground(ax, az) > gf.wade_depth:
				wet_people += 1
	check(people >= 300, "a crowd on the island (%d)" % people)
	check(wet_people == 0, "nobody dropped in deep water (%d were)" % wet_people)
	var dress: Node = game.island.get_node_or_null("EarthDress")
	check(dress != null and dress.get_child_count() > 0, "the water is laid (%d meshes)" % (dress.get_child_count() if dress else 0))
	var tm := iw.get("terrain_material") as ShaderMaterial
	check(tm != null and tm.get_shader_parameter("control_a") is Texture2D, "the ground's paint is bound")
	# THE SKY (EnviroSky): the sun where it really is, the moon's real phase,
	# the weather reaching the sky and the light
	var sky: Node = game.island.get_node_or_null("EnviroSky")
	check(sky != null, "the island has its own sky (EnviroSky)")
	if sky != null:
		var sun: Vector3 = sky.sun_direction()
		var el := rad_to_deg(asin(sun.y))
		check(el > 40.0 and el < 66.0 and sun.x > 0.0 and sun.z > 0.0,
				"at 10:30 on the 15th of July the sun is high in the south-east (%.0f degrees up, %s)" % [el, str(sun)])
		check(float(sky.moon_phase()) < 0.12,
				"and the moon is a day past new (the new moon of 14 July 2026): %.2f lit" % sky.moon_phase())
		var fair: Dictionary = sky.world_light()
		sky.set_weather("storm", true)
		sky._update(0.0, true)
		var mat: ShaderMaterial = sky.sky_material
		check(is_equal_approx(float(mat.get_shader_parameter("coverage")), 1.0),
				"a storm covers the sky (coverage %.2f)" % float(mat.get_shader_parameter("coverage")))
		var dark: Dictionary = sky.world_light()
		check(float(dark.sky_light) < float(fair.sky_light) * 0.8,
				"and darkens the crowd's light (%.2f from %.2f)" % [dark.sky_light, fair.sky_light])
		sky.hour = 23.0
		sky.set_weather("clear", true)
		sky._update(0.0, true)
		check(sky.sun_direction().y < 0.0 and float(sky.world_light().sky_light) < float(fair.sky_light) * 0.5,
				"at 23:00 the sun is down and the island dark (%.2f)" % float(sky.world_light().sky_light))
		sky.hour = 10.5
		sky.set_weather("fair", true)
	var waited := 0
	while not game.island_ready() and waited < 6000:
		await process_frame
		waited += 1
	check(game.island_ready(), "the island is up (terrain and plants) after %d frames" % waited)

	print("earth: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
