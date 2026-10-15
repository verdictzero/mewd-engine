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
## ground in deep water, the bake digest moves with the data. Then the PLACE,
## through the viewer: the eye at the island's start over its ground, the water
## laid, the ground painted, the sky's sun and moon and weather, the cinema, the
## mountains' shadows, the grade, the island built and the plants standing.

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

	# THE PLACE, through the viewer (godot/scripts/main.gd)
	var main: Node = (load("res://godot/scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var iw: Node = main.place.get_node("IslandWorld")
	var gf := iw.get("field") as EarthField
	check(gf != null, "the viewer's place is the region")
	if gf == null:
		quit(1)
		return
	var cp: Vector3 = main.cam.global_position
	var want: Vector2 = spec.get("start", Vector2(cp.x, cp.z))
	check(Vector2(cp.x, cp.z).distance_to(want) < 1.0,
			"the eye starts at the island's start (%.0f, %.0f m; asked %.0f, %.0f)" % [cp.x, cp.z, want.x, want.y])
	var g0: float = main._ground(cp.x, cp.z)
	check(not is_nan(g0) and cp.y > g0 and cp.y < g0 + 20.0,
			"over the ground there, not in it (%.1f m over)" % (cp.y - g0))
	var dress: Node = main.place.get_node_or_null("EarthDress")
	check(dress != null and dress.get_child_count() > 0, "the water is laid (%d meshes)" % (dress.get_child_count() if dress else 0))
	var tm := iw.get("terrain_material") as ShaderMaterial
	check(tm != null and tm.get_shader_parameter("control_a") is Texture2D, "the ground's paint is bound")
	# THE SKY (EnviroSky): the sun where it really is, the moon's real phase,
	# the weather reaching the sky and the light
	var sky: Node = main.place.get_node_or_null("EnviroSky")
	check(sky != null, "the island has its own sky (EnviroSky)")
	if sky != null:
		# (the island's own hour is its evening; these are of a morning)
		var hour0: float = sky.hour
		sky.hour = 10.5
		sky._update(0.0, true)
		var sun: Vector3 = sky.sun_direction()
		var el := rad_to_deg(asin(sun.y))
		check(el > 40.0 and el < 66.0 and sun.x > 0.0 and sun.z > 0.0,
				"at 10:30 on the 15th of July the sun is high in the south-east (%.0f degrees up, %s)" % [el, str(sun)])
		check(float(sky.moon_phase()) < 0.12,
				"and the moon is a day past new (the new moon of 14 July 2026): %.2f lit" % sky.moon_phase())
		var fair: float = sky.light_level()
		sky.set_weather("storm", true)
		sky._update(0.0, true)
		var mat: ShaderMaterial = sky.sky_material
		check(is_equal_approx(float(mat.get_shader_parameter("coverage")), 1.0),
				"a storm covers the sky (coverage %.2f)" % float(mat.get_shader_parameter("coverage")))
		var dark: float = sky.light_level()
		check(dark < fair * 0.8, "and darkens the island's light (%.2f from %.2f)" % [dark, fair])
		sky.hour = 23.0
		sky.set_weather("clear", true)
		sky._update(0.0, true)
		check(sky.sun_direction().y < 0.0 and sky.light_level() < fair * 0.5,
				"at 23:00 the sun is down and the island dark (%.2f)" % sky.light_level())
		sky.hour = 10.5
		sky.set_weather("fair", true)
		sky._update(0.0, true)
		# THE CINEMA (at the user's request: "make it look fucking cinematic as
		# hell"): the light's pass over the picture, the mountains' shadows
		# baked for where the sun is and again when it moves, the grade
		var cine := main.place.get_node_or_null("Cinema") as CinemaPost
		check(cine != null and cine.mesh != null and cine.material_override is ShaderMaterial,
				"the island has its cinema pass (god rays, flare, bloom, the lit haze)")
		var esun := main.place.get_node_or_null("EarthSun") as EarthSun
		check(esun != null and esun.bakes >= 1 and float(U.G.get("tod_sun_shadow_on", 0.0)) == 1.0,
				"the mountains' shadows are baked and on (%d bakes)" % (esun.bakes if esun else 0))
		if esun != null:
			esun._process(0.0)
			var b0 := esun.bakes
			sky.hour = hour0 - 1.0
			sky._update(0.0, true)
			esun._process(0.0)
			check(esun.bakes > b0, "and baked again when the sun moves (to %.2f h)" % (hour0 - 1.0))
			sky.hour = hour0
			sky._update(0.0, true)
		var grade: Dictionary = spec.get("grade", {})
		var lm: ShaderMaterial = main.lofi.mat
		check(not grade.is_empty() and float(lm.get_shader_parameter("grade")) == 1.0
				and float(lm.get_shader_parameter("grade_filmic")) == float(grade.get("filmic", 0.0)),
				"the island has its grade, and the picture takes it")
		main.lofi.set_grade({})
		check(float(lm.get_shader_parameter("grade")) == 0.0
				and float(lm.get_shader_parameter("grain")) == 0.0,
				"and an island without one none, its grain gone with it")
		main.lofi.for_island(spec)
	var waited := 0
	while not main.place_ready() and waited < 6000:
		await process_frame
		waited += 1
	check(main.place_ready(), "the place is up (terrain and plants) after %d frames" % waited)

	print("earth: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
