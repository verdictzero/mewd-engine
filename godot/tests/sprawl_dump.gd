## MEWD — THE SPRAWL (and THE GRID), built and dumped.
##
## godot --headless --script res://godot/tests/sprawl_dump.gd -- [doc.json]
## writes the document in blocks (the vertices, blocks, lines, things,
## scatters, layers and world), builds it through BlockCompile and
## holds the build: no problems, the counts of what it makes, the start
## at the crossroads on the asphalt, the plateau standing CLIFF_H over
## the roads with the horizons on it, a building a room under its roof
## with its door working, a pond pushed down into the park, the hall's
## light well open to the sky, the crowds and the woods grown; and THE
## GRID walled round. Prints OK or fails (tools/godot-test.sh runs it).
extends SceneTree

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

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
		f.store_string(JSON.stringify(_plain({"ground": d.ground, "vertices": d.vertices, "blocks": d.blocks, "lines": d.lines,
			"things": d.things, "scatters": d.scatters, "layers": d.layers, "world": d.world}), "", false, true))
		f.close()
	var lv := DocCompile.compile(d)
	var t2 := Time.get_ticks_msec()
	var two := 0
	for l in lv.lines:
		if l.back != -1:
			two += 1
	var counts := {}
	for t in lv.things:
		counts[t.type] = counts.get(t.type, 0) + 1
	var up: int = d.layers["1"].blocks.size()
	print("SPRAWL: %d vertices, %d blocks (%d roofs over) -> %d sectors, %d lines (%d two-sided), %d things %s, %d plants, %d doors, %d problems; doc %d ms, compile %d ms" % [
		d.vertices.size(), d.blocks.size(), up, lv.sectors.size(), lv.lines.size(), two, lv.things.size(), str(counts),
		lv.plants.size(), lv.doors.size(), DocCompile.problems.size(), t1 - t0, t2 - t1])
	for p in DocCompile.problems.slice(0, 10):
		print("  problem: ", p.msg)
	check(DocCompile.problems.is_empty(), "built with no problems")
	check(d.blocks.size() > 900 and up >= 14 and lv.doors.size() >= 10, "a thousand blocks, fourteen roofs on the layer over, eleven doors (%d, %d, %d)" % [d.blocks.size(), up, lv.doors.size()])
	# the start at the crossroads, on the asphalt
	var st = null
	for t in lv.things:
		if t.type == "START":
			st = t
	var s0 := lv.span_at(float(st.x), float(st.y), 1.0)
	check(s0 != null and s0.floor == 0.0 and s0.floor_tex == "PARKLOT3" and st.z == 0.0, "the start on the box junction at the crossroads (%s at %s)" % [s0.floor_tex if s0 else "?", s0.floor if s0 else "?"])
	var road := lv.span_at(SprawlMap.RIM + 400, SprawlMap.SIZE / 2.0, 1.0)
	check(road != null and road.floor == 0.0 and road.floor_tex == "ASPHALT1" and road.ceil_tex == "SKY", "the roads are the ground, asphalt under the sky")
	# the plateau CLIFF_H up, its face the cliff, the horizons standing on it
	var top := lv.span_at(256, SprawlMap.SIZE / 2.0, SprawlMap.CLIFF_H + 1.0)
	check(top != null and top.floor == float(SprawlMap.CLIFF_H) and top.floor_tex == "GRASS5", "the plateau stands %d over the roads, grass on top (%s at %s)" % [SprawlMap.CLIFF_H, top.floor_tex if top else "?", top.floor if top else "?"])
	var cliff = null
	for l in lv.lines:
		if absf(l.x1 - SprawlMap.RIM) < 0.5 and absf(l.x2 - SprawlMap.RIM) < 0.5 and minf(l.y1, l.y2) <= SprawlMap.SIZE / 2.0 and maxf(l.y1, l.y2) >= SprawlMap.SIZE / 2.0:
			cliff = l
	var cliff_band = null
	if cliff != null:
		for bd in cliff.bands:
			if bd.z0 == 0.0 and bd.z1 == float(SprawlMap.CLIFF_H):
				cliff_band = bd
	check(cliff_band != null and cliff_band.tex == "CLIFF2", "its inner face one band from the road to its top, the cliff (%s)" % str(cliff_band.tex if cliff_band else null))
	var horizons := 0
	for l in lv.lines:
		if l.middle == "TREELINE" or l.middle == "MOUNTBG" or l.middle == "TREEBACK" or l.middle == "MEADOWBG" or l.middle == "RUINLINE" or l.middle == "MNTN0001":
			horizons += 1
	check(horizons >= 18, "the painted horizons stand on it (%d)" % horizons)
	# a building: the cube farm, a room under its roof, lit by it, its
	# walls in its own textures inside and out, its door working
	var i := SprawlMap.block_at(2)
	var j := SprawlMap.block_at(0)
	var cx := i + SprawlMap.BLOCK / 2.0
	var cy := j + SprawlMap.BLOCK / 2.0
	var room := lv.span_at(cx, cy, 9.0)
	check(room != null and room.name == "cube farm" and room.floor == float(SprawlMap.CURB) and room.ceil == float(SprawlMap.CURB + 256) and room.ceil_tex == "OFCCEIL1" and absf(room.light - 0.98) < 0.01,
		"the cube farm is a room, its floor to its ceiling under the roof's underside, lit by the roof (%s %s..%s %s %.2f)" % [room.name if room else "?", room.floor if room else "?", room.ceil if room else "?", room.ceil_tex if room else "?", room.light if room else 0.0])
	var roof := lv.sectors[room.above] if room != null and room.above != -1 else null
	check(roof != null and roof.floor == float(SprawlMap.CURB + 256 + 16) and roof.floor_tex == "CONC_3" and roof.ceil_tex == "SKY", "and the roof on top, 16 thick, under the sky (%s)" % str(roof.floor if roof else null))
	var x0 := i + 192 + 128
	var wall_in = null
	var wall_out = null
	for l in lv.lines:
		if absf(l.y1 - (j + 192 + 128)) < 0.5 and absf(l.y2 - l.y1) < 0.5 and minf(l.x1, l.x2) <= x0 + 300 and maxf(l.x1, l.x2) >= x0 + 300:
			wall_in = l
		if absf(l.y1 - (j + 192 + 128 - 16)) < 0.5 and absf(l.y2 - l.y1) < 0.5 and minf(l.x1, l.x2) <= x0 + 300 and maxf(l.x1, l.x2) >= x0 + 300:
			wall_out = l
	var tin: Array = wall_in.bands.filter(func(bd): return bd.tex != "NONE").map(func(bd): return bd.tex) if wall_in else []
	var tout: Array = wall_out.bands.filter(func(bd): return bd.tex != "NONE").map(func(bd): return bd.tex) if wall_out else []
	check(tin == ["OFCCUB01"] and tout.has("CONC_5"), "its south wall cubicle panels inside, concrete outside (%s / %s)" % [str(tin), str(tout)])
	var door = null
	for dr in lv.doors:
		if absf(dr.a.y - (j + 192 + 128)) < 0.5 and absf(dr.a.x + dr.b.x - 2 * cx) < 1.0:
			door = dr
	check(door != null and door.z0 == float(SprawlMap.CURB) and door.top == float(SprawlMap.CURB + SprawlMap.DOOR_H) and door.tex == "EYEDOOR0" and door.inside.y > 0.0,
		"the door in its south wall: from the floor to its head, in its texture, opening into the room (%s)" % str([door.z0, door.top, door.tex, door.inside] if door else null))
	# the park's pond, pushed down into the lawn, walled in its own sides
	var pi := SprawlMap.block_at(0) + SprawlMap.BLOCK / 2.0
	var pond := lv.span_at(pi, pi, 1.0)
	check(pond != null and pond.name == "pond" and pond.floor == -20.0 and pond.floor_tex == "WAT201", "the park's pond is pushed down to -20 (%s at %s)" % [pond.name if pond else "?", pond.floor if pond else "?"])
	var rock := 0
	for l in lv.lines:
		for bd in l.bands:
			if bd.tex == "ROCK_01" and bd.z0 == -20.0:
				rock += 1
	check(rock >= 8, "its sides rock all round (%d bands)" % rock)
	# the hall's light well open to the sky inside the roofed hall
	var hx := SprawlMap.block_at(2) + SprawlMap.BLOCK / 2.0
	var hy := SprawlMap.block_at(2) + SprawlMap.BLOCK / 2.0
	var well := lv.span_at(hx + 200, hy + 200, 9.0)
	var hall := lv.span_at(hx + 1000, hy + 1000, 9.0)
	check(well != null and well.ceil_tex == "SKY" and hall != null and hall.ceil_tex == "CONC_5" and hall.ceil == float(SprawlMap.CURB + 448),
		"the hall's light well is open to the sky, the hall round it roofed (%s / %s)" % [well.ceil_tex if well else "?", hall.ceil_tex if hall else "?"])
	# what grew
	check(counts.get("TOWNIE", 0) > 100 and counts.get("SHOPPER", 0) > 100 and lv.plants.size() > 2000 and counts.get("GRAVESTONE", 0) == 103,
		"the crowds and the woods grew: %d townies, %d shoppers, %d plants, %d headstones" % [counts.get("TOWNIE", 0), counts.get("SHOPPER", 0), lv.plants.size(), counts.get("GRAVESTONE", 0)])
	var off := 0
	for t in lv.things:
		if t.type == "PLANT":
			continue
		var s := lv.span_at(float(t.x), float(t.y), float(t.z) + 1.0)
		if s == null or absf(s.floor - float(t.z)) > 0.5:
			off += 1
	check(off == 0, "everything stands on the floor its place leaves it (%d off)" % off)
	# THE GRID
	var g := DocCompile.compile(TheGrid.build())
	var shoppers := 0
	for t in g.things:
		if t.type == "SHOPPER":
			shoppers += 1
	var walls := 0
	for s in g.sectors:
		if s.name == "wall" and s.floor == float(TheGrid.WALL_H):
			walls += 1
	var field := g.span_at(TheGrid.FIELD / 2.0, TheGrid.FIELD / 2.0, 1.0)
	print("GRID: %d sectors, %d lines, %d shoppers" % [g.sectors.size(), g.lines.size(), shoppers])
	check(shoppers == 200 and walls == 4 and field != null and field.floor_tex == "GRID" and DocCompile.problems.is_empty(),
		"the grid: 200 shoppers on the lattice, four walls %d high round it (%d, %d)" % [TheGrid.WALL_H, shoppers, walls])
	print("sprawl: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
