## FENRIR — THE WORLD MAP AND THE PLACES BUILT FROM IT (WorldMap, MapView,
## RegionBuilder, Regions, GeoFetch, Cog): the sums first, then a real
## square built from the open data — a kilometre round the middle of the
## Oeschinensee — and read back the way the engine reads a place. The build
## needs the network; without it the suite says so and skips that half.
extends SceneTree

var fails := 0


func check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# ---- the sums
	var m := MapView.merc(46.4986, 7.727)
	var back := MapView.unmerc(m)
	# (a Vector2's single precision: a couple of metres at most, on a map)
	check(absf(back.x - 46.4986) < 5e-5 and absf(back.y - 7.727) < 5e-5,
			"Web Mercator there and back (%.6f, %.6f)" % [back.x, back.y])
	var mpd := RegionBuilder.metres_per_degree(46.5)
	check(absf(mpd.x - 111152.0) < 100.0 and absf(mpd.y - 76680.0) < 200.0,
			"metres a degree at 46.5 N (%.0f, %.0f)" % [mpd.x, mpd.y])
	var nm := Regions.name_for("Lac d'Oeschinen — Kandersteg!")
	check(nm.begins_with("lac_d_oeschinen_kandersteg"), "a place's name for its folder (%s)" % nm)
	var raw := PackedByteArray([1, 2, 3, 250, 0, 7])
	var path := "user://world_test.grid"
	RegionBuilder.write_grid(path, raw, 3, 2, 2, 1)
	var g: Dictionary = EarthField._grid(path)
	check(int(g.get("w", 0)) == 3 and int(g.get("h", 0)) == 2 and g.get("data") == raw,
			"a grid written here reads back as EarthField reads one")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# ---- a real square
	var probe := GeoFetch.get_url("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/2/2/1.png", -1, 0, [], true, 1)
	if not probe.ok:
		print("  skip the build: no network (%d)" % int(probe.code))
	else:
		var b := RegionBuilder.new()
		var t0 := Time.get_ticks_msec()
		var dir := b.build("zworldtest", "WORLD TEST", 46.4986, 7.727, 1000.0)
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		check(dir != "", "a kilometre round the Oeschinensee built in %.1f s %s" % [secs, b.error])
		if dir != "":
			# (read afresh: EarthField keeps a region once read)
			EarthField._lock.lock()
			EarthField._regions.erase(dir)
			EarthField._lock.unlock()
			var r: EarthField.Region = EarthField.region_for(dir)
			check(r.ok and r.hn == 501, "read back as a place (%d samples a side)" % r.hn)
			var j: Dictionary = r.json
			var hmin := float(j.height.min)
			var hmax := float(j.height.max)
			check(hmin > 1450.0 and hmin < 1600.0 and hmax > 1600.0 and hmax < 2300.0,
					"its ground where the lake's valley is (%.0f .. %.0f m)" % [hmin, hmax])
			var lakes: Array = (j.bodies as Array).filter(func(o): return o.kind == "lake")
			var big := 0.0
			for l in lakes:
				big = maxf(big, float(l.area_m2))
			check(big > 2e5, "the lake found (%.0f m2 of it in the square)" % big)
			var sums_ok := true
			for s in range(0, r.cn * r.cn, 997):
				var t := 0
				for plane in range(3):
					var o := (plane * r.cn * r.cn + s) * 4
					t += r.cover[o] + r.cover[o + 1] + r.cover[o + 2] + r.cover[o + 3]
				if absi(t - 255) > 6:
					sums_ok = false
			check(sums_ok, "its twelve layers summing to one")
			check(Regions.spec(Regions.PREFIX + "zworldtest").get("region", "") == dir,
					"listed as a place to fly (%s)" % (Regions.PREFIX + "zworldtest"))
			# (gone again)
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	print("world: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
