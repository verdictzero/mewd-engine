## MEWD — THE SPRAWL (and THE GRID), dumped for comparison with the web
## build's.
##
## godot --headless --script res://godot/tests/sprawl_dump.gd -- <doc.json> [level.json]
## writes the document (vertices, sectors, things, props, scatters, line
## overrides, world) in the shape a node dump of sprawlDoc writes, so the
## two diff; and, with a second path, the compiled level's things,
## plants, props, lines and sectors, in the shape of the node dump of
## compileDoc(sprawlDoc()). Prints a summary of the build either way,
## and holds the counts to the web build's (tools/godot-test.sh runs it).
extends SceneTree

static func _plain(v):
	if v is Vector2:
		return [v.x, v.y]
	if v is Color:
		return [v.r, v.g, v.b, v.a]
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = _plain(v[k])
		return o
	if v is Array:
		return v.map(func(x): return _plain(x))
	return v

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var d := SprawlMap.build()
	var t1 := Time.get_ticks_msec()
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(_plain({"vertices": d.vertices, "sectors": d.sectors.map(func(s):
			var o: Dictionary = s.duplicate()
			o.erase("jambs")
			return o), "things": d.things, "props": d.props, "scatters": d.scatters, "lines": d.lines, "world": d.world}), "", false, true))
		f.close()
	# the web build's walls are thin: its build, to hold the two together
	DocCompile.thick = false
	var lv := DocCompile.compile(d)
	DocCompile.thick = true
	var web_problems := DocCompile.problems.size()
	var t2 := Time.get_ticks_msec()
	var two := 0
	for l in lv.lines:
		if l.back != -1:
			two += 1
	var counts := {}
	for t in lv.things:
		counts[t.type] = counts.get(t.type, 0) + 1
	print("SPRAWL: %d vertices, %d doc sectors -> %d sectors, %d lines (%d two-sided), %d things %s, %d plants, %d props, %d problems; doc %d ms, compile %d ms" % [
		d.vertices.size(), d.sectors.size(), lv.sectors.size(), lv.lines.size(), two, lv.things.size(), str(counts),
		lv.plants.size(), lv.props.size(), DocCompile.problems.size(), t1 - t0, t2 - t1])
	for p in DocCompile.problems.slice(0, 10):
		print("  problem: ", p.msg)
	if args.size() > 1:
		var r6 := func(x: float) -> float: return snappedf(x, 0.000001)
		var things := []
		for t in lv.things:
			if t.type == "PLANT":
				continue
			var v = t.get("variant")
			things.append([t.type, r6.call(float(t.x)), r6.call(float(t.y)), r6.call(float(t.get("angle", 0.0))), v])
		var plants := []
		for p in lv.plants:
			plants.append([p.kind, r6.call(p.x), r6.call(p.y), r6.call(p.scale)])
		var props := []
		for p in lv.props:
			props.append([p.x0, p.y0, p.x1, p.y1, p.z0, p.z1, p.tex, p.topTex, r6.call(p.light), _plain(p.tint), _plain(p.fog)])
		var lines := []
		for l in lv.lines:
			var bands := []
			if l.back != -1:
				var f := lv.sectors[l.front]
				var b := lv.sectors[l.back]
				if absf(f.floor - b.floor) > 1e-6:
					bands.append([minf(f.floor, b.floor), maxf(f.floor, b.floor), "lower", l.lower])
				if absf(f.ceil - b.ceil) > 1e-6:
					bands.append([minf(f.ceil, b.ceil), maxf(f.ceil, b.ceil), "upper", l.upper])
			lines.append([r6.call(l.x1), r6.call(l.y1), r6.call(l.x2), r6.call(l.y2), l.front, l.back if l.back != -1 else null,
				l.middle, l.blocking, l.block_sight, l.mid_once, bands, l.sides.size()])
		var secs := []
		for s in lv.sectors:
			secs.append([s.poly.size(), s.floor, s.ceil, s.floor_tex, s.ceil_tex, s.roof_tex if s.roof_tex != "" else null,
				r6.call(s.light), _plain(s.tint), _plain(s.fog), s.doc_id, s.flat_holes.size()])
		var f := FileAccess.open(args[1], FileAccess.WRITE)
		f.store_string(JSON.stringify({"things": things, "plants": plants, "props": props, "lines": lines, "sectors": secs,
			"nsec": lv.sectors.size(), "nlines": lv.lines.size()}, "", false, true))
		f.close()
	# and the Godot build's own, its buildings' walls 16 thick
	var lt := DocCompile.compile(d)
	var walls := 0
	var doors := 0
	for sc in lt.sectors:
		walls += 1 if sc.name == "wall" else 0
		doors += 1 if sc.name == "doorway" else 0
	var thick_problems := DocCompile.problems.size()
	print("SPRAWL, walls 16 thick: %d sectors (%d of wall, %d doorways), %d lines, %d problems" % [
		lt.sectors.size(), walls, doors, lt.lines.size(), thick_problems])
	for p in DocCompile.problems.slice(0, 10):
		print("  problem: ", p.msg)
	var g := DocCompile.compile(TheGrid.build())
	var shoppers := 0
	for t in g.things:
		if t.type == "SHOPPER":
			shoppers += 1
	print("GRID: %d sectors, %d lines, %d shoppers" % [g.sectors.size(), g.lines.size(), shoppers])
	# what the web build's compileDoc(sprawlDoc()) and buildGrid() make
	# (node, 2026-09): the counts hold the two builds together between
	# full diffs
	var fails := 0
	var roofs := 0
	var holed := 0
	var tinted := 0
	for s in lv.sectors:
		roofs += 1 if s.roof_tex != "" else 0
		holed += 1 if not s.flat_holes.is_empty() else 0
		tinted += 1 if s.tint != null else 0
	for c in [["sectors", lv.sectors.size(), 440], ["lines", lv.lines.size(), 2297], ["townsfolk", counts.get("TOWNIE", 0), 142],
			["shoppers", counts.get("SHOPPER", 0), 137], ["headstones", counts.get("GRAVESTONE", 0), 103],
			["lamps", counts.get("STREETLAMP", 0), 256], ["plants", lv.plants.size(), 2387], ["props", lv.props.size(), 520],
			["problems", web_problems, 0], ["grid shoppers", shoppers, 200]]:
		var ok: bool = c[1] == c[2]
		print("  %s   sprawl %s: %d (the web build's %d)" % ["ok" if ok else "FAIL", c[0], c[1], c[2]])
		fails += 0 if ok else 1
	print("  ok   %d roofs, %d floors round holes, %d coloured sectors" % [roofs, holed, tinted])
	var thick_ok := thick_problems == 0 and walls > 0 and doors > 0
	print("  %s   the thick walls build with no problems (%d walls, %d doorways, %d problems)" % [
		"ok" if thick_ok else "FAIL", walls, doors, thick_problems])
	fails += 0 if thick_ok else 1
	print("sprawl: " + ("OK" if fails == 0 else "FAIL"))
	quit(1 if fails else 0)
