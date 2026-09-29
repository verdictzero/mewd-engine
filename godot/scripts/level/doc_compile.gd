## MEWD — a map document to a Level (compileDoc and compileCore in
## js/editor/doc.js).
##
## A document is what the maps and the editor write: vertices, sectors
## as rings of vertex indices, things, line overrides keyed by vertex
## pair ("a,b", smaller first), free boxes (props), scatters, and the
## world. The compiler does what a Doom editor does for you and the
## level builder cannot:
##
##   T-JUNCTIONS   every edge is split at every vertex lying on it, so
##                 a long edge of one sector with the corners of two
##                 smaller ones along it joins both of them
##   HOLES         a sector drawn inside another is cut out of it: the
##                 outer ring is BRIDGED to each hole by a slit of zero
##                 width (the slit welds to itself, a line with the same
##                 sector on both sides — nothing to draw, nothing in the
##                 way), and rooms that share a wall are one hole
##   LINEDEFS      lines that close no sector stand up as thin walls
##
## and then the editor's own rules: a line's overrides (blocking, its
## textures, offsets, pegging, its two SIDES), the outside wall where a
## roofed sector meets the open air, no sky walls (and a roof over each
## roofed room instead), Doom 64's sector colours and each sector's fog,
## the props, the plants, and what the scatters grow.
##
## A MAP IN LAYERS (compileLayers): each layer's linedefs stood up on
## their own, then every layer's outlines laid over each other (overlay:
## cut wherever two cross or a corner of one lands on another, and
## walked face by face), and each face built as a COLUMN of the rooms of
## every layer over it, bottom-up (Level.add_column) — each storey's
## ceiling brought down to the underside of the deck under the one over
## it (a deck is Level.DECK thick; the web build's have none). A layer's
## line overrides land on the level lines along them; a line is a
## building's outside wall only in the openings where a roofed room
## meets the open air (its mid_z); things on an upper layer stand on the
## floor of their layer's room (their `z`); the scatters spread over the
## ground layer.
##
## Not ported: the sector's own storeys and slopes (FEATURES.storeys and
## FEATURES.slopes are off in the web build too) and the editor's
## problem report beyond what the build itself runs into (EdDoc's).
class_name DocCompile

const EPS := 0.5
const GRID := 256.0
const DEFAULT_FLOOR := "LAWN2"
## THING_TYPES in js/editor/doc.js: what a map may place
const THING_TYPES := ["START", "SHOPPER", "TOWNIE", "TROLLEY", "BOLLARD", "FUELCAN", "CRATE", "LAMP",
	"STREETLAMP", "GRAVESTONE", "PLANT"]
## the five colours of a Doom 64 sector
const COLOR_PARTS := ["floor", "ceil", "thing", "top", "bottom"]
const LINEDEF_THICK := 8.0
const LINEDEF_H := 128.0

## What the world around a map is when it does not say (defaultWorld).
static func default_world() -> Dictionary:
	return {"noBurn": true, "noSquads": true, "noCellFire": true,
		"sky": {"horizon": "#1d9a48", "mid": "#06301a", "zenith": "#000000", "ground": "#05180c", "midPow": 0.95}}

## The last build's problems ({kind, msg}), for a test to read.
static var problems: Array = []
## and what the scatters grew (each thing with its `scatter` id), and
## how much of what each wanted: {id: {grown, wanted}} — for the editor
static var last_scattered: Array = []
static var last_grown: Dictionary = {}

const LAYER_PARTS := ["vertices", "sectors", "lines", "linedefs"]
## anything under this from a point is that point, laying layers over
## each other (doc.js WELD)
const WELD := 0.49

static func compile(doc: Dictionary) -> Level:
	problems = []
	last_scattered = []
	last_grown = {}
	var lays := layers_of(doc)
	if lays.size() > 1:
		return _compile_layers(doc, lays)
	# one layer with anything on it: that layer, as the map always was —
	# whichever layer happens to be open in the editor
	if lays.size() == 1 and int(lays[0].k) != int(doc.get("layer", 0)):
		doc = doc.duplicate()
		for p in LAYER_PARTS:
			doc[p] = lays[0][p]
	return _compile_core(doc, {})

## Every layer with something on it, bottom-up: [{k, vertices, sectors,
## lines, linedefs}] (layersOf, less the empty ones).
static func layers_of(doc: Dictionary) -> Array:
	var cur := int(doc.get("layer", 0))
	var ks := [cur]
	var L = doc.get("layers")
	if L is Dictionary:
		for k in L:
			if not ks.has(int(k)):
				ks.append(int(k))
	ks.sort()
	var out := []
	for k in ks:
		var g := {"k": k, "vertices": [], "sectors": [], "lines": {}, "linedefs": []}
		var src = doc if k == cur else (L.get(str(k)) if L is Dictionary else null)
		if src is Dictionary:
			for p in LAYER_PARTS:
				if src.get(p) != null:
					g[p] = src[p]
		if not g.sectors.is_empty() or not g.linedefs.is_empty():
			out.append(g)
	return out

## A MAP IN LAYERS: each layer's linedefs stood up on its own, then the
## layers laid over each other and the faces compiled as one plan, a
## column of rooms each (compileLayers).
static func _compile_layers(doc: Dictionary, lays: Array) -> Level:
	var built := []
	for li in lays.size():
		var g: Dictionary = lays[li]
		var d := doc.duplicate()
		for p in LAYER_PARTS:
			d[p] = g[p]
		d["layer"] = g.k
		var w: Dictionary = linedef_walls(d, problems, int(doc.get("nextId", 0)) + 100000 * (li + 1)) \
			if not g.linedefs.is_empty() else d
		built.append({"k": g.k, "vertices": w.vertices, "sectors": w.sectors, "lines": g.lines})
	var ov := overlay(built)
	var F := doc.duplicate()
	F["vertices"] = ov.vertices
	F["lines"] = {}
	F["linedefs"] = []
	var fs := []
	for i in ov.faces.size():
		var f: Dictionary = ov.faces[i]
		var st := []
		for e in f.stack:
			st.append({"k": built[e.li].k, "s": e.s})
		fs.append({"id": -(i + 1), "verts": f.verts, "__void": f.stack.is_empty(), "__stack": st})
	F["sectors"] = fs
	F.erase("layers")
	F.erase("layer")
	return _compile_core(F, {"layers": built})

## The rooms of one column, bottom-up, as Level.add_column wants them
## (stackProps): each storey's ceiling brought down to a deck's thickness
## (Level.DECK) under the floor of the one over it, and a storey open to
## the sky under another roofed by that one's floor. One that leaves no room for the deck over the floor
## of the one under it cannot be stacked, and is left out and said.
static func _stack_props(stack: Array) -> Array:
	var out := []
	for e in stack:
		var p := sector_props(e.s)
		if not out.is_empty():
			var lo: Dictionary = out[out.size() - 1]
			if p.floor < lo.p.floor:
				problems.append({"kind": "sector", "id": e.s.get("id"), "layer": e.k,
					"msg": "layer %d: sector %s starts at %s, under the floor of sector %s on layer %d (%s) — raise it" % [
						e.k, str(e.s.get("id")), str(p.floor), str(lo.s.get("id")), lo.k, str(lo.p.floor)]})
				continue
			# THE DECK HAS A THICKNESS (Level.DECK): the room under ends
			# that far under the floor over it, and must still be there
			if p.floor - Level.DECK < lo.p.floor:
				problems.append({"kind": "sector", "id": e.s.get("id"), "layer": e.k,
					"msg": "layer %d: sector %s's floor (%s) leaves no room for a %d-thick deck over sector %s on layer %d (floor %s) — raise it" % [
						e.k, str(e.s.get("id")), str(p.floor), int(Level.DECK), str(lo.s.get("id")), lo.k, str(lo.p.floor)]})
				continue
			# (the open air under a floor is not a room being cut)
			if p.floor < lo.p.ceil and lo.p.ceilTex != "SKY" and lo.p.ceilTex != "NONE":
				problems.append({"kind": "sector", "id": e.s.get("id"), "layer": e.k,
					"msg": "layer %d: sector %s's floor (%s) cuts into sector %s under it (ceiling %s) — the room under is cut down to it" % [
						e.k, str(e.s.get("id")), str(p.floor), str(lo.s.get("id")), str(lo.p.ceil)]})
			lo.p.ceil = p.floor - Level.DECK
			if lo.p.ceilTex == "SKY" or lo.p.ceilTex == "NONE":
				lo.p.ceilTex = p.floorTex
		out.append({"k": e.k, "s": e.s, "p": p})
	return out

static func _compile_core(doc: Dictionary, ctx: Dictionary) -> Level:
	var layered := not ctx.is_empty()
	if not layered and not doc.get("linedefs", []).is_empty():
		doc = linedef_walls(doc, problems)
	var lv := Level.new()
	lv.name = doc.get("name", "")
	lv.world = doc.get("world", {})
	var V: Array = doc.vertices
	var S: Array = doc.sectors
	var ns := S.size()

	# 1. every ring, split at every vertex lying on it (a coarse grid of
	# the vertices, so each edge asks only its own cells)
	var grid := {}
	for i in V.size():
		var p: Vector2 = V[i]
		var key := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var ring_idx := []          # split rings, vertex indices
	var rings := []             # split rings, points
	var plain := []             # the rings as drawn, for containment
	var boxes := []
	var areas := PackedFloat64Array()
	for sd in S:
		var r: Array = sd.verts
		var n := r.size()
		var idx := PackedInt32Array()
		for k in n:
			idx.append(r[k])
			for m in _between(V, grid, V[r[k]], V[r[(k + 1) % n]], r[k], r[(k + 1) % n]):
				idx.append(m)
		ring_idx.append(idx)
		rings.append(_pts(V, idx))
		var pl := _pts(V, PackedInt32Array(r))
		plain.append(pl)
		boxes.append(_bbox(pl))
		areas.append(absf(signed_area(pl)))

	# 2. which sectors are holes in which: each one's parent is the
	# smallest sector it is a hole in
	var parent_of := PackedInt32Array()
	parent_of.resize(ns)
	for i in ns:
		parent_of[i] = -1
		if plain[i].size() < 3:
			continue
		var bi: Rect2 = boxes[i]
		var ba := INF
		for j in ns:
			if i == j or plain[j].size() < 3 or areas[j] >= ba:
				continue
			var bj: Rect2 = boxes[j]
			if bi.position.x < bj.position.x - EPS or bi.position.y < bj.position.y - EPS \
					or bi.end.x > bj.end.x + EPS or bi.end.y > bj.end.y + EPS:
				continue
			if hole_in(plain[i], plain[j]):
				ba = areas[j]
				parent_of[i] = j
	var kids_of := {}
	for j in ns:
		if parent_of[j] >= 0:
			if not kids_of.has(parent_of[j]):
				kids_of[parent_of[j]] = []
			kids_of[parent_of[j]].append(j)

	# 3. every sector into the builder
	var index := PackedInt32Array()
	index.resize(ns)
	index.fill(-1)
	var pieces := []            # [doc sector, level index]
	var flat_holes := {}
	for i in ns:
		var s: Dictionary = S[i]
		if plain[i].size() < 3 or self_crosses(plain[i]) or s.get("__void", false):
			continue
		var holes := _hole_outlines(kids_of.get(i, []), ring_idx, V, s)
		var poly: PackedVector2Array = bridge(rings[i], holes) if holes.size() else rings[i]
		if s.has("__stack"):
			# A PIECE OF A MAP IN LAYERS: the room of every layer over it
			var st := _stack_props(s.__stack)
			if st.is_empty():
				continue
			var got := PackedInt32Array()
			if st.size() == 1:
				got.append(lv.add_sector(poly, st[0].p))
			else:
				got = lv.add_column(poly, st.map(func(e): return e.p))
			index[i] = got[0]
			for j in got.size():
				pieces.append([st[j].s, got[j], st[j].k])
				if holes.size():
					flat_holes[got[j]] = [rings[i], holes]
			continue
		var li := lv.add_sector(poly, sector_props(s))
		index[i] = li
		pieces.append([s, li])
		if holes.size():
			flat_holes[li] = [rings[i], holes]

	# 4. the things, and what the scatters grow — after everything
	# placed by hand, keeping clear of it, in the order they were made
	var scattered := []
	if not doc.get("scatters", []).is_empty():
		if layered:
			# on a map in layers, the scatters spread over the ground layer
			var G: Dictionary = ctx.layers[0]
			for g in ctx.layers:
				if int(g.k) == 0:
					G = g
			var gdoc := {"sectors": G.sectors, "props": doc.get("props", []), "things": doc.get("things", []),
				"scatters": doc.scatters}
			var gplain := []
			var gareas := PackedFloat64Array()
			var gboxes := []
			for sd in G.sectors:
				var pl := _pts(G.vertices, PackedInt32Array(sd.verts))
				gplain.append(pl)
				gboxes.append(_bbox(pl))
				gareas.append(absf(signed_area(pl)))
			scattered = _grow_scatters(gdoc, gplain, gareas, gboxes)
		else:
			scattered = _grow_scatters(doc, plain, areas, boxes)
		last_scattered = scattered
	var things := []
	var started := false
	for t in doc.get("things", []) + scattered:
		if t.type == "START":
			if started:
				continue
			started = true
		# A THING ON AN UPPER LAYER stands on the floor of that layer's
		# room: the game puts it in the storey at that height
		if layered and int(t.get("layer", 0) if t.get("layer") != null else 0) != 0:
			for g in ctx.layers:
				if int(g.k) != int(t.layer):
					continue
				var room = _sector_in(g, float(t.x), float(t.y))
				if room != null:
					t = t.duplicate()
					t["z"] = float(room.get("floor", 0.0) if room.get("floor") != null else 0.0)
		things.append(t)
	if not started:
		# a map with no start gets one, in the middle of its first sector
		var c := Vector2.ZERO
		for pl in plain:
			if pl.size() >= 3:
				c = centroid(pl)
				break
		things.append({"type": "START", "x": c.x, "y": c.y, "angle": 0.0})
		problems.append({"kind": "map", "msg": "there is no player start"})
	if lv.sectors.is_empty():
		var sq := PackedVector2Array([Vector2(0, 0), Vector2(512, 0), Vector2(512, 512), Vector2(0, 512)])
		lv.add_sector(sq, sector_props({"id": 0}))
		problems.append({"kind": "map", "msg": "the map has no sectors that can be built"})
	lv.things = things
	if layered:
		lv.layered = true
	lv.finish()
	for pc in pieces:
		lv.sectors[pc[1]].doc_id = pc[0].get("id")
	for li in flat_holes:
		lv.sectors[li].flat_outer = flat_holes[li][0]
		lv.sectors[li].flat_holes = flat_holes[li][1]

	# 5. the line overrides — on a map in layers, each layer's lines, in
	# its own vertices
	var dlines: Dictionary = doc.get("lines", {})
	var opened := {}
	for g in (ctx.layers if layered else [{"vertices": V, "lines": dlines}]):
		var gv: Array = g.vertices
		var gl: Dictionary = g.lines if g.lines is Dictionary else {}
		for k in gl:
			var ab := _key_verts(k)
			if ab.x < 0 or ab.x >= gv.size() or ab.y >= gv.size():
				continue
			var o: Dictionary = gl[k]
			for l in _level_lines_on(lv, gv[ab.x], gv[ab.y]):
				_apply_line(l, o)
				if o.get("opening", false):
					# a doorway ON THAT LAYER: the storeys of the others keep
					# their walls along it
					if not opened.has(l):
						opened[l] = {}
					opened[l][int(g.get("k", 0))] = true

	# 5c. INSIDE MEETS OUTSIDE: a wall. Where a roofed sector meets one
	# open to the sky the map has a building's outside wall, from the
	# floor to the roof, solid, and blind — unless the line is a doorway.
	# IN LAYERS, storey by storey: only the openings that are a room with
	# a roof on one side and the open air on the other (as the rooms were
	# drawn, not as the stacking roofed them) — a terrace over a house is
	# open air beside open air.
	if layered:
		var src_of := {}
		var layer_of := {}
		for pc in pieces:
			src_of[pc[1]] = pc[0]
			layer_of[pc[1]] = pc[2]
		for l in lv.lines:
			if l.back == -1 or l.holes.is_empty():
				continue
			var odd := []
			for h in l.holes:
				var a = src_of.get(h.front.index)
				var b = src_of.get(h.back.index)
				if a == null or b == null:
					continue
				if _roofed(a) != _roofed(b):
					var kin: int = layer_of[h.front.index] if _roofed(a) else layer_of[h.back.index]
					if opened.has(l) and opened[l].has(kin):
						continue
					odd.append([a, b, h])
			if odd.is_empty():
				continue
			var inside: Dictionary = odd[0][0] if _roofed(odd[0][0]) else odd[0][1]
			# and each storey's piece of it in that storey's own walls —
			# unless the line wears a middle of its own
			if not (l.mid_once and l.middle != null):
				for e in odd:
					var room: Dictionary = e[0] if _roofed(e[0]) else e[1]
					e[2]["wall"] = _tex_or(room.get("wallTex"), "GRIDWALL")
			if odd.size() < l.holes.size():
				l.mid_z = odd.map(func(e): return Vector2(e[2].z0, e[2].z1))
			l.middle = l.middle if l.mid_once and l.middle != null else _tex_or(inside.get("wallTex"), "GRIDWALL")
			l.mid_height = null
			l.mid_once = false
			l.blocking = true
			l.block_sight = true
			l.exterior = true
			# and the edges of the decks between its storeys are the
			# same outside wall
			for bd in l.bands:
				if bd.get("deck", false):
					bd.tex = l.middle
	for dl in ([] if layered else _doc_lines(S, parent_of)):
		if dl.sectors.size() != 2:
			continue
		var sa: Dictionary = S[dl.sectors[0]]
		var sb: Dictionary = S[dl.sectors[1]]
		var in_a := _roofed(sa)
		var in_b := _roofed(sb)
		if in_a == in_b:
			continue
		var o: Dictionary = dlines.get(dl.key, {})
		if o.get("opening", false):
			continue
		var inside := sa if in_a else sb
		for l in _level_lines_on(lv, V[dl.a], V[dl.b]):
			if l.back == -1:
				continue
			l.middle = _tex_or(o.get("midTex"), _tex_or(inside.get("wallTex"), "GRIDWALL"))
			l.mid_height = null
			l.mid_once = false
			l.blocking = true
			l.block_sight = true
			l.exterior = true

	# 5a. AN OPEN WORLD HAS NO SKY WALLS: the band between the sky over
	# the street and a room's lower roof is not drawn (unless the map
	# asks for Doom's way, world.skyWalls) — the room's ceiling is drawn
	# from above as well, a roof, instead
	var w_all := default_world()
	w_all.merge(lv.world, true)
	if not w_all.get("skyWalls", false):
		for l in lv.lines:
			if l.back == -1:
				continue
			if l.multi:
				for bd in l.bands:
					if bd.kind == "upper" and bd.open.ceil_tex == "SKY" and bd.from.ceil_tex != "SKY":
						bd.tex = "NONE"
				continue
			var f := lv.sectors[l.front]
			var b := lv.sectors[l.back]
			if absf(f.ceil - b.ceil) <= 1e-6:
				continue
			var open := f if f.ceil > b.ceil else b
			var from := b if f.ceil > b.ceil else f
			if open.ceil_tex == "SKY" and from.ceil_tex != "SKY":
				l.upper = "NONE"
		for pc in pieces:
			var L := lv.sectors[pc[1]]
			if L.ceil_tex == "SKY" or L.ceil_tex == "NONE":
				continue
			# a storey with another over it has that one's floor for a roof
			if L.above != -1:
				continue
			L.roof_tex = _tex_or(pc[0].get("roofTex"), L.ceil_tex)

	# 5b. DOOM 64'S COLOURS, and each sector's fog
	var fog_w: Dictionary = w_all.get("fog", {}) if w_all.get("fog") is Dictionary else {}
	for pc in pieces:
		var s: Dictionary = pc[0]
		var L := lv.sectors[pc[1]]
		var c: Dictionary = s.get("colors", {}) if s.get("colors") is Dictionary else {}
		var lc = null
		var lcs := str(s.get("lightColor", ""))
		if lcs != "" and lcs.to_lower() != "#ffffff":
			lc = hex_rgb(lcs)
		var t := {}
		for k in COLOR_PARTS:
			if not c.get(k) and lc == null:
				continue
			var v = hex_rgb(str(c[k])) if c.get(k) else Color.WHITE
			if v == null:
				v = Color.WHITE
			t[k] = v * lc if lc != null else v
		if not t.is_empty():
			L.tint = t
			lv.tinted = true
		var fg = s.get("fog")
		if fg is Dictionary and float(fg.get("density", 0)) > 0:
			var col = hex_rgb(str(fog_w.color) if fog_w.get("override", false) and fog_w.get("color") else str(fg.get("color", "#808080")))
			if col == null:
				col = Color(0.5, 0.5, 0.5)
			L.fog = Color(col.r, col.g, col.b, minf(100.0, float(fg.density)))
			lv.tinted = true
	lv.map_light = map_light_of(w_all)
	var ml := lv.map_light
	if ml.lightColor != Color.WHITE or ml.ambient != Color.BLACK or ml.fog.a > 0:
		lv.tinted = true
	for l in lv.lines:
		if not l.sides.is_empty() or (l.back != -1 and l.middle != null):
			lv.tinted = true
			break

	# 6. the free boxes: lit, coloured and fogged by the sector under
	# their middle, as a thing is
	for p in doc.get("props", []):
		var box := {
			"x0": minf(p.x0, p.x1), "y0": minf(p.y0, p.y1), "x1": maxf(p.x0, p.x1), "y1": maxf(p.y0, p.y1),
			"z0": minf(p.z0, p.z1), "z1": maxf(p.z0, p.z1),
			"tex": _tex_or(p.get("tex"), "GRIDWALL"), "topTex": _tex_or(p.get("topTex"), _tex_or(p.get("tex"), "GRIDWALL")),
			"sky": 0.0, "tint": null, "fog": null,
		}
		var s := lv.sector_at((box.x0 + box.x1) / 2.0, (box.y0 + box.y1) / 2.0)
		box.light = float(p.light) if p.get("light") != null else (s.light if s != null else 0.66)
		if s != null and s.tint != null and s.tint.has("thing"):
			box.tint = s.tint.thing
		if s != null and s.fog != null:
			box.fog = s.fog
		lv.props.append(box)
	# the plants, placed and spread, one tree to a forest cell
	lv.plants = Forest.plants_from_things(lv.things, lv.bounds)
	return lv

# ------------------------------------------------------------------
# SECTORS
# ------------------------------------------------------------------

static func _tex_or(v, d):
	return d if v == null or str(v) == "" else v

## A document sector's properties as the builder wants them (sectorProps).
## Its other keys ride along (fire.gd and rain.gd read `forest`, `fuel`
## and the like off Level.Sector.props). A sector that does not say how
## much sky it sees keeps the builder's own answer (all of it, outdoors):
## the maze and JESSE were tuned under that and say nothing.
static func sector_props(s: Dictionary) -> Dictionary:
	var p := s.duplicate()
	p.floor = float(s.get("floor", 0.0) if s.get("floor") != null else 0.0)
	p.ceil = float(s.get("ceil", 256.0) if s.get("ceil") != null else 256.0)
	p.light = float(s.get("light", 0.72) if s.get("light") != null else 0.72)
	p.ambient = p.light
	p.floorTex = _tex_or(s.get("floorTex"), DEFAULT_FLOOR)
	p.ceilTex = _tex_or(s.get("ceilTex"), "SKY")
	p.wallTex = _tex_or(s.get("wallTex"), "GRIDWALL")
	p.upperTex = _tex_or(s.get("upperTex"), p.wallTex)
	p.lowerTex = _tex_or(s.get("lowerTex"), p.wallTex)
	p.outdoor = not (s.get("outdoor") is bool and s.outdoor == false)
	if s.get("sky") == null:
		p.erase("sky")
	p.fuel = 0
	var nm = s.get("name")
	p.name = nm if nm != null and str(nm) != "" else "sector %s" % str(s.get("id", ""))
	return p

static func _roofed(s: Dictionary) -> bool:
	var c = s.get("ceilTex")
	return c != null and str(c) != "" and str(c) != "SKY"

static func _pts(V: Array, idx: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in idx:
		out.append(V[i])
	return out

## The vertices strictly inside a->b, in order along it (splitsOn).
static func _between(vs: Array, grid: Dictionary, a: Vector2, b: Vector2, ia: int, ib: int) -> Array:
	var d := b - a
	var len2 := d.length_squared()
	if len2 <= 0.0:
		return []
	var found := []
	var c0 := floori((minf(a.x, b.x) - EPS) / GRID)
	var c1 := floori((maxf(a.x, b.x) + EPS) / GRID)
	var r0 := floori((minf(a.y, b.y) - EPS) / GRID)
	var r1 := floori((maxf(a.y, b.y) + EPS) / GRID)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			for i in grid.get(Vector2i(c, r), []):
				if i == ia or i == ib:
					continue
				var p: Vector2 = vs[i]
				var t := (p - a).dot(d) / len2
				if t <= 1e-6 or t >= 1.0 - 1e-6:
					continue
				if (a + d * t).distance_to(p) > EPS:
					continue
				found.append([t, i])
	found.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	return found.map(func(x): return x[1])

# ------------------------------------------------------------------
# GEOMETRY (doc.js, plain)
# ------------------------------------------------------------------

static func signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	var n := pts.size()
	var j := n - 1
	for i in n:
		a += pts[j].x * pts[i].y - pts[i].x * pts[j].y
		j = i
	return a / 2.0

## Even-odd, which is what the engine's own point-in-polygon is.
static func pip(pts: PackedVector2Array, x: float, y: float) -> bool:
	var inside := false
	var n := pts.size()
	var j := n - 1
	for i in n:
		var pi := pts[i]
		var pj := pts[j]
		if (pi.y > y) != (pj.y > y) and x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x:
			inside = not inside
		j = i
	return inside

static func seg_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var d := b - a
	var l2 := d.length_squared()
	var t := clampf((p - a).dot(d) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
	return p.distance_to(a + d * t)

static func _on_boundary(pts: PackedVector2Array, p: Vector2) -> bool:
	var n := pts.size()
	var j := n - 1
	for i in n:
		if seg_dist(pts[j], pts[i], p) < EPS:
			return true
		j = i
	return false

## Proper crossing of a-b and c-d, not counting shared ends.
static func seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	var d2 := (b.x - a.x) * (d.y - a.y) - (b.y - a.y) * (d.x - a.x)
	var d3 := (d.x - c.x) * (a.y - c.y) - (d.y - c.y) * (a.x - c.x)
	var d4 := (d.x - c.x) * (b.y - c.y) - (d.y - c.y) * (b.x - c.x)
	return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))

static func self_crosses(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			if seg_cross(a, b, pts[j], pts[(j + 1) % n]):
				return true
	return false

static func _crosses_any(a: Vector2, b: Vector2, outer: PackedVector2Array) -> bool:
	var m := outer.size()
	for j in m:
		if seg_cross(a, b, outer[j], outer[(j + 1) % m]):
			return true
	return false

## Every point of `inner` inside `outer` and none on its edge: a HOLE.
static func strictly_inside(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	for p in inner:
		if _on_boundary(outer, p) or not pip(outer, p.x, p.y):
			return false
	var n := inner.size()
	for i in n:
		if _crosses_any(inner[i], inner[(i + 1) % n], outer):
			return false
	return true

## A hole that touches the outline at corners, and only there.
static func inside_touching(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	var touches := false
	for p in inner:
		if _on_boundary(outer, p):
			touches = true
			continue
		if not pip(outer, p.x, p.y):
			return false
	if not touches:
		return false
	var n := inner.size()
	for i in n:
		var a := inner[i]
		var b := inner[(i + 1) % n]
		var m := (a + b) / 2.0
		if _on_boundary(outer, m) or not pip(outer, m.x, m.y):
			return false
		if _crosses_any(a, b, outer):
			return false
	return true

static func hole_in(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	return strictly_inside(inner, outer) or inside_touching(inner, outer)

static func centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / pts.size()

static func _bbox(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)

## '#rrggbb' as a Color, or null.
static func hex_rgb(h: String):
	var s := h.trim_prefix("#")
	if s.length() != 6 or not s.is_valid_hex_number():
		return null
	var n := s.hex_to_int()
	return Color(((n >> 16) & 255) / 255.0, ((n >> 8) & 255) / 255.0, (n & 255) / 255.0)

## The map's light and fog (mapLightOf).
static func map_light_of(w: Dictionary) -> Dictionary:
	var amb: Dictionary = w.ambient if w.get("ambient") is Dictionary else {}
	var fog: Dictionary = w.fog if w.get("fog") is Dictionary else {}
	var k := clampf(float(amb.get("amount", 0.0)), 0.0, 1.0)
	var a = hex_rgb(str(amb.get("color", "#ffffff")))
	var fc = hex_rgb(str(fog.get("color", "#808080")))
	var lc = hex_rgb(str(w.get("lightColor", "#ffffff")))
	if a == null: a = Color.WHITE
	if fc == null: fc = Color(0.5, 0.5, 0.5)
	if lc == null: lc = Color.WHITE
	return {
		"lightColor": lc,
		"ambient": Color(a.r * k, a.g * k, a.b * k),
		"fogAmbient": clampf(float(w.get("fogAmbient", 1.0)), 0.0, 1.0),
		"fog": Color(fc.r, fc.g, fc.b, clampf(float(fog.get("density", 0.0)), 0.0, 100.0)),
		"override": bool(fog.get("override", false)),
	}

# ------------------------------------------------------------------
# HOLES
# ------------------------------------------------------------------

static func _line_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]

static func _key_verts(k: String) -> Vector2i:
	var parts := k.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

## THE HOLES A SECTOR HAS TO BE BRIDGED ROUND (holeOutlines): its direct
## children, and children that share a wall are one hole — their
## outlines unioned by cancelling every edge walked both ways.
static func _hole_outlines(kids: Array, ring_idx: Array, V: Array, parent: Dictionary) -> Array:
	if kids.is_empty():
		return []
	var up := range(kids.size())
	var find := func(k: int, f: Callable) -> int:
		if up[k] == k:
			return k
		up[k] = f.call(up[k], f)
		return up[k]
	var owner := {}
	for k in kids.size():
		var r: PackedInt32Array = ring_idx[kids[k]]
		for q in r.size():
			var e := _line_key(r[q], r[(q + 1) % r.size()])
			if owner.has(e):
				up[find.call(k, find)] = find.call(owner[e], find)
			else:
				owner[e] = k
	var groups := {}
	var order := []
	for k in kids.size():
		var g: int = find.call(k, find)
		if not groups.has(g):
			groups[g] = []
			order.append(g)
		groups[g].append(kids[k])
	var out := []
	for gk in order:
		var g: Array = groups[gk]
		if g.size() == 1:
			out.append(_pts(V, ring_idx[g[0]]))
			continue
		var dir := {}
		var edges := []
		for j in g:
			var r: PackedInt32Array = ring_idx[j]
			if signed_area(_pts(V, r)) < 0:
				r = r.duplicate()
				r.reverse()
			for q in r.size():
				var a := r[q]
				var b := r[(q + 1) % r.size()]
				if a != b:
					edges.append(Vector2i(a, b))
					dir[Vector2i(a, b)] = true
		var left := []
		for e in edges:
			if not dir.has(Vector2i(e.y, e.x)):
				left.append(e)
		var nxt := {}
		for e in left:
			if not nxt.has(e.x):
				nxt[e.x] = []
			nxt[e.x].append(e.y)
		var loops := []
		var used := {}
		for e0 in left:
			if used.has(e0):
				continue
			var loop := PackedInt32Array([e0.x])
			var a0: int = e0.x
			var b: int = e0.y
			used[e0] = true
			var guard := 0
			while b != a0 and guard < left.size() + 2:
				guard += 1
				loop.append(b)
				var nb := -1
				for c in nxt.get(b, []):
					if not used.has(Vector2i(b, c)):
						nb = c
						break
				if nb == -1:
					break
				used[Vector2i(b, nb)] = true
				b = nb
			if loop.size() >= 3:
				loops.append(_pts(V, loop))
		if loops.is_empty():
			for j in g:
				out.append(_pts(V, ring_idx[j]))
			continue
		var ord := range(loops.size())
		ord.sort_custom(func(x, y):
			var ax := absf(signed_area(loops[x]))
			var ay := absf(signed_area(loops[y]))
			return ax > ay or (ax == ay and x < y))
		out.append(loops[ord[0]])
		if loops.size() > 1:
			problems.append({"kind": "sector", "id": parent.get("id"),
				"msg": "rooms inside sector %s close off a courtyard of it" % str(parent.get("id"))})
	return out

## THE BRIDGE: one ring with holes in it as a single ring — each hole
## joined by a slit of zero width from its rightmost point to the
## nearest ring point it can see, or pinched in where it touches the
## outline at a corner.
static func bridge(outer: PackedVector2Array, holes: Array) -> PackedVector2Array:
	var ring: Array = Array(outer)
	if signed_area(outer) <= 0:
		ring.reverse()
	var hs := []
	for h in holes:
		var a: Array = Array(h)
		if signed_area(h) >= 0:
			a.reverse()
		hs.append(a)
	var mx := func(a: Array) -> float:
		var m := -INF
		for p in a:
			m = maxf(m, p.x)
		return m
	var ord := range(hs.size())
	var keys := ord.map(func(i): return mx.call(hs[i]))
	ord.sort_custom(func(x, y): return keys[x] > keys[y] or (keys[x] == keys[y] and x < y))
	var sorted := ord.map(func(i): return hs[i])
	for h in sorted:
		var pinch := Vector2i(-1, -1)
		for i in ring.size():
			for k in h.size():
				if absf(ring[i].x - h[k].x) < 0.5 and absf(ring[i].y - h[k].y) < 0.5:
					pinch = Vector2i(i, k)
					break
			if pinch.x >= 0:
				break
		if pinch.x >= 0:
			var round := []
			for q in range(1, h.size()):
				round.append(h[(pinch.y + q) % h.size()])
			ring = ring.slice(0, pinch.x + 1) + round + ring.slice(pinch.x)
			continue
		var hi := 0
		for i in range(1, h.size()):
			if h[i].x > h[hi].x:
				hi = i
		var hp: Vector2 = h[hi]
		# the nearest ring point it can see, nothing of the ring or of any
		# hole in the way: tried nearest first (ties to the first), which
		# is the answer the web build's loop over every point comes to
		var dist := PackedFloat64Array()
		for i in ring.size():
			var dx: float = ring[i].x - hp.x
			var dy: float = ring[i].y - hp.y
			dist.append(dx * dx + dy * dy)
		var cands := range(ring.size())
		cands.sort_custom(func(x, y): return dist[x] < dist[y] or (dist[x] == dist[y] and x < y))
		var best := -1
		for c in cands:
			var rp: Vector2 = ring[c]
			var lo := hp.min(rp)
			var hi2 := hp.max(rp)
			var blocked := false
			for w in [ring] + sorted:
				var m: int = w.size()
				for j in m:
					var a: Vector2 = w[j]
					var bq: Vector2 = w[(j + 1) % m]
					if maxf(a.x, bq.x) < lo.x or minf(a.x, bq.x) > hi2.x or maxf(a.y, bq.y) < lo.y or minf(a.y, bq.y) > hi2.y:
						continue
					if seg_cross(hp, rp, a, bq):
						blocked = true
						break
				if blocked:
					break
			if not blocked:
				best = c
				break
		if best < 0:
			best = 0
		var round := []
		for k in h.size() + 1:
			round.append(h[(hi + k) % h.size()])
		ring = ring.slice(0, best + 1) + round + [ring[best]] + ring.slice(best + 1)
	return PackedVector2Array(ring)

## Every line of the document, as drawn: each vertex pair round every
## sector with the sectors on it, a hole's edge having its parent on
## the other side (linesOf).
static func _doc_lines(S: Array, parents: PackedInt32Array) -> Array:
	var map := {}
	var order := []
	for si in S.size():
		var r: Array = S[si].verts
		for i in r.size():
			var a: int = r[i]
			var b: int = r[(i + 1) % r.size()]
			var k := _line_key(a, b)
			if not map.has(k):
				map[k] = {"key": k, "a": mini(a, b), "b": maxi(a, b), "sectors": []}
				order.append(k)
			if not map[k].sectors.has(si):
				map[k].sectors.append(si)
	var out := []
	for k in order:
		var l: Dictionary = map[k]
		if l.sectors.size() == 1 and parents[l.sectors[0]] >= 0:
			l.sectors.append(parents[l.sectors[0]])
		out.append(l)
	return out

# ------------------------------------------------------------------
# LINES
# ------------------------------------------------------------------

## The level lines along the document line a-b: the one running end to
## end, or every piece the T-junction splitting cut it into.
static func _level_lines_on(lv: Level, a: Vector2, b: Vector2) -> Array:
	var cand := lv.lines_in_box(minf(a.x, b.x) - EPS, minf(a.y, b.y) - EPS, maxf(a.x, b.x) + EPS, maxf(a.y, b.y) + EPS)
	var p1 := Vector2()
	var p2 := Vector2()
	for l in cand:
		p1 = Vector2(l.x1, l.y1)
		p2 = Vector2(l.x2, l.y2)
		if (p1 == a and p2 == b) or (p1 == b and p2 == a):
			return [l]
	var out := []
	for l in cand:
		if seg_dist(a, b, Vector2(l.x1, l.y1)) < EPS and seg_dist(a, b, Vector2(l.x2, l.y2)) < EPS:
			out.append(l)
	out.sort_custom(func(x, y): return x.index < y.index)
	return out

## A line's overrides (applyLine).
static func _apply_line(l: Level.Line, o: Dictionary) -> void:
	var two := l.back != -1
	if o.get("blocking", false):
		l.blocking = true
	if o.get("blockSight", false):
		l.block_sight = true
	if o.get("wallTex") or o.get("upperTex") or o.get("lowerTex"):
		if two:
			if o.get("upperTex"):
				l.upper = o.upperTex
			if o.get("lowerTex"):
				l.lower = o.lowerTex
			if l.multi:
				for bd in l.bands:
					bd.tex = l.upper if bd.kind == "upper" else l.lower
		elif o.get("wallTex") and l.middle != null:
			l.middle = o.wallTex
	if o.get("midTex") and two:
		l.middle = o.midTex
		if o.get("midHeight"):
			l.mid_height = float(o.midHeight)
	var sides: Dictionary = o.get("sides", {}) if o.get("sides") is Dictionary else {}
	if two:
		var any_mid := false
		for v in sides.values():
			if v is Dictionary and v.get("midTex"):
				any_mid = true
		if o.get("midTex") or any_mid:
			l.mid_once = true
	if o.get("xoff"):
		l.xoff = float(o.xoff)
	if o.get("yoff"):
		l.yoff = float(o.yoff)
	if float(o.get("xscale", 0)) > 0 and float(o.xscale) != 1.0:
		l.xscale = float(o.xscale)
	if float(o.get("yscale", 0)) > 0 and float(o.yscale) != 1.0:
		l.yscale = float(o.yscale)
	if o.get("unpegUpper", false):
		l.peg_upper = "top"
	if o.get("unpegLower", false):
		l.peg_lower = "ceiling"
		l.peg_middle = "bottom"
	if not sides.is_empty():
		l.sides = {}
		for k in sides:
			l.sides[str(k)] = sides[k]

# ------------------------------------------------------------------
# SCATTERS
# ------------------------------------------------------------------

## Grow every scatter over the document (step 4 of compileCore): a
## thing may stand in the smallest sector round it if that has 64 of
## head-room, not inside a low prop, and clear of everything before it.
static func _grow_scatters(doc: Dictionary, plain: Array, areas: PackedFloat64Array, boxes: Array) -> Array:
	var S: Array = doc.sectors
	var rings := {}
	var cand := []              # indices of sectors with a ring, in order
	for i in S.size():
		rings[S[i].get("id")] = plain[i]
		if plain[i].size() >= 3:
			cand.append(i)
	# a coarse grid of the sectors and of the low props, so each dart asks
	# only its own cell — the same answers, in the same order, as asking
	# all of them
	const CELL := 512.0
	var sgrid := {}
	for i in cand:
		var b: Rect2 = boxes[i]
		for cy in range(floori(b.position.y / CELL), floori(b.end.y / CELL) + 1):
			for cx in range(floori(b.position.x / CELL), floori(b.end.x / CELL) + 1):
				var k := Vector2i(cx, cy)
				if not sgrid.has(k):
					sgrid[k] = []
				sgrid[k].append(i)
	var standable := func(x: float, y: float):
		var best := -1
		var ba := INF
		for i in sgrid.get(Vector2i(floori(x / CELL), floori(y / CELL)), []):
			if areas[i] < ba and pip(plain[i], x, y):
				ba = areas[i]
				best = i
		if best < 0:
			return null
		var s: Dictionary = S[best]
		var c = s.get("ceil")
		var f = s.get("floor")
		return s.get("id") if (float(c) if c != null else 256.0) - (float(f) if f != null else 0.0) >= 64.0 else null
	var low := []
	var pgrid := {}
	for p in doc.get("props", []):
		if minf(p.z0, p.z1) >= 64:
			continue
		var r := Rect2(minf(p.x0, p.x1), minf(p.y0, p.y1), absf(p.x1 - p.x0), absf(p.y1 - p.y0))
		var n := low.size()
		low.append(r)
		for cy in range(floori((r.position.y - 16) / CELL), floori((r.end.y + 16) / CELL) + 1):
			for cx in range(floori((r.position.x - 16) / CELL), floori((r.end.x + 16) / CELL) + 1):
				var k := Vector2i(cx, cy)
				if not pgrid.has(k):
					pgrid[k] = []
				pgrid[k].append(n)
	var blocked := func(x: float, y: float, r: float) -> bool:
		for n in pgrid.get(Vector2i(floori(x / CELL), floori(y / CELL)), []):
			var b: Rect2 = low[n]
			if x > b.position.x - r and x < b.end.x + r and y > b.position.y - r and y < b.end.y + r:
				return true
		return false
	var taken := []
	for t in doc.get("things", []):
		taken.append(Vector2(t.x, t.y))
	var out := []
	for sc in doc.scatters:
		var g := Scatter.grow(sc, {"rings": rings, "standable": standable, "blocked": blocked, "taken": taken})
		out.append_array(g.items)
		last_grown[sc.get("id")] = {"grown": g.grown, "wanted": g.wanted}
		if g.grown < g.wanted * 0.9:
			problems.append({"kind": "scatter", "id": sc.get("id"),
				"msg": "scatter \"%s\" wanted %d and found room for %d" % [sc.get("name", sc.get("id")), g.wanted, g.grown]})
	return out

# ------------------------------------------------------------------
# LINEDEFS AS WALLS
# ------------------------------------------------------------------

## The linedefs as runs: each chain of them, broken wherever three meet
## or one touches a sector (linedefChains).
static func linedef_chains(doc: Dictionary) -> Array:
	var L: Array = doc.get("linedefs", [])
	if L.is_empty():
		return []
	var adj := {}
	var order := []
	for e in L:
		for pr in [[e[0], e[1]], [e[1], e[0]]]:
			if not adj.has(pr[0]):
				adj[pr[0]] = []
				order.append(pr[0])
			adj[pr[0]].append(pr[1])
	var on_ring := {}
	for s in doc.sectors:
		for v in s.verts:
			on_ring[v] = true
	var stop := func(v) -> bool:
		return adj.get(v, []).size() != 2 or on_ring.has(v)
	var used := {}
	var walk := func(a: int, b: int) -> Array:
		var out := [a, b]
		used[_line_key(a, b)] = true
		var prev := a
		var cur := b
		while not stop.call(cur):
			var nx := -1
			for n in adj[cur]:
				if n != prev and not used.has(_line_key(cur, n)):
					nx = n
					break
			if nx == -1:
				break
			used[_line_key(cur, nx)] = true
			out.append(nx)
			prev = cur
			cur = nx
		return out
	var chains := []
	for v in order:
		if stop.call(v):
			for n in adj[v]:
				if not used.has(_line_key(v, n)):
					chains.append(walk.call(v, n))
	for e in L:
		if not used.has(_line_key(e[0], e[1])):
			chains.append(walk.call(e[0], e[1]))
	return chains

## The outline of a wall along P, w either side, its ends pulled in.
static func wall_outline(P: Array, w: float, in_a := 0.0, in_b := 0.0) -> PackedVector2Array:
	P = P.duplicate()
	var n := P.size()
	var pull := func(i: int, j: int, by: float) -> bool:
		var d: Vector2 = P[j] - P[i]
		var L := d.length()
		if L <= by + 1:
			return false
		P[i] = P[i] + d / L * by
		return true
	if in_a != 0.0 and not pull.call(0, 1, in_a):
		return PackedVector2Array()
	if in_b != 0.0 and not pull.call(n - 1, n - 2, in_b):
		return PackedVector2Array()
	var nrm := func(a: Vector2, b: Vector2) -> Vector2:
		var d := b - a
		var L := d.length()
		if L == 0:
			L = 1
		return Vector2(-d.y / L, d.x / L)
	var left := []
	var right := []
	for i in n:
		var n1 = nrm.call(P[i - 1], P[i]) if i > 0 else null
		var n2 = nrm.call(P[i], P[i + 1]) if i < n - 1 else null
		var m: Vector2
		var k := w
		if n1 != null and n2 != null:
			m = n1 + n2
			var L := m.length()
			if L < 1e-6:
				m = n1
			else:
				m = m / L
				k = minf(w / maxf(0.2, m.dot(n1)), w * 3)
		else:
			m = n1 if n1 != null else n2
		var r := func(v: float) -> float: return snappedf(v, 0.01)
		left.append(Vector2(r.call(P[i].x + m.x * k), r.call(P[i].y + m.y * k)))
		right.append(Vector2(r.call(P[i].x - m.x * k), r.call(P[i].y - m.y * k)))
	right.reverse()
	return PackedVector2Array(left + right)

## The document with its linedefs stood up as thin walls (linedefWalls).
static func linedef_walls(doc: Dictionary, probs: Array, id_base := -1) -> Dictionary:
	var chains := linedef_chains(doc)
	if chains.is_empty():
		return doc
	var V: Array = doc.vertices
	var rings := []
	for s in doc.sectors:
		rings.append(_pts(V, PackedInt32Array(s.verts)))
	var on_ring := {}
	for s in doc.sectors:
		for v in s.verts:
			on_ring[v] = true
	var deg := {}
	for e in doc.linedefs:
		for v in e:
			deg[v] = deg.get(v, 0) + 1
	var out := doc.duplicate()
	out.vertices = V.duplicate()
	out.sectors = doc.sectors.duplicate()
	var made := []
	var id: int = id_base if id_base >= 0 else maxi(int(doc.get("nextId", 1)), 1) + 100000
	var crosses := func(A: PackedVector2Array, B: PackedVector2Array) -> bool:
		for i in A.size():
			for j in B.size():
				if seg_cross(A[i], A[(i + 1) % A.size()], B[j], B[(j + 1) % B.size()]):
					return true
		return false
	for ch in chains:
		var P := []
		for i in ch:
			P.append(V[i])
		var w := LINEDEF_THICK / 2.0
		var cut := func(v) -> float:
			return w + 1 if on_ring.has(v) or deg.get(v, 0) > 1 else 0.0
		var poly := wall_outline(P, w, cut.call(ch[0]), cut.call(ch[ch.size() - 1]))
		var key := _line_key(ch[0], ch[1])
		if poly.is_empty():
			probs.append({"kind": "line", "id": key, "msg": "linedef %s is too short to stand as a wall" % key})
			continue
		var mid: Vector2 = (P[0] + P[1]) / 2.0
		var host := -1
		var ha := INF
		for i in rings.size():
			if rings[i].size() >= 3 and pip(rings[i], mid.x, mid.y):
				var a := absf(signed_area(rings[i]))
				if a < ha:
					ha = a
					host = i
		var bad := host < 0 or self_crosses(poly) or not strictly_inside(poly, rings[host])
		if not bad:
			for i in rings.size():
				if i == host or rings[i].size() < 3:
					continue
				if crosses.call(poly, rings[i]):
					bad = true
					break
				for p in poly:
					if pip(rings[i], p.x, p.y) and not hole_in(rings[host], rings[i]):
						bad = true
						break
				if bad:
					break
		if not bad:
			for m in made:
				if crosses.call(poly, m):
					bad = true
					break
		if bad:
			probs.append({"kind": "line", "id": key, "msg": "linedef %s crosses a wall or leaves the map" % key})
			continue
		made.append(poly)
		var H: Dictionary = doc.sectors[host]
		var o: Dictionary = doc.get("lines", {}).get(key, {})
		var tex = o.get("midTex") if o.get("midTex") else (H.get("wallTex") if H.get("wallTex") else "GRIDWALL")
		var inside := _roofed(H)
		var f := float(H.get("floor", 0.0) if H.get("floor") != null else 0.0)
		var c := float(H.get("ceil", 1024.0) if H.get("ceil") != null else 1024.0)
		var h := float(o.wallH) if o.get("wallH") != null else ((c - f) if inside else LINEDEF_H)
		var verts := []
		for p in poly:
			out.vertices.append(p)
			verts.append(out.vertices.size() - 1)
		var ns := H.duplicate(true)
		ns.erase("storeys")
		ns.erase("floorSlope")
		ns.merge({"id": id, "verts": verts, "name": "linedef wall", "floor": minf(c, f + h),
			"floorTex": tex, "wallTex": tex, "lowerTex": tex, "upperTex": tex}, true)
		id += 1
		out.sectors.append(ns)
	return out

# ------------------------------------------------------------------
# LAYERS, LAID OVER EACH OTHER (overlay in js/editor/doc.js)
# ------------------------------------------------------------------

## The smallest sector of geometry g round (x, y), or null (sectorIn).
static func _sector_in(g: Dictionary, x: float, y: float):
	var best = null
	var ba := INF
	for sd in g.sectors:
		var r := _pts(g.vertices, PackedInt32Array(sd.verts))
		if r.size() < 3 or not pip(r, x, y):
			continue
		var a := absf(signed_area(r))
		if a < ba:
			ba = a
			best = sd
	return best

static func _seg_t(a: Vector2, b: Vector2, p: Vector2) -> float:
	var d := b - a
	var l2 := d.length_squared()
	return clampf((p - a).dot(d) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0

static func _weld(P: Array, cell: Dictionary, x: float, y: float) -> int:
	var fx := floori(x)
	var fy := floori(y)
	for i in range(-1, 2):
		for j in range(-1, 2):
			for k in cell.get(Vector2i(fx + i, fy + j), []):
				if absf(P[k].x - x) <= WELD and absf(P[k].y - y) <= WELD:
					return k
	P.append(Vector2(x, y))
	var key := Vector2i(fx, fy)
	if not cell.has(key):
		cell[key] = []
	cell[key].append(P.size() - 1)
	return P.size() - 1

## Every edge of every layer's sectors in one plane, cut wherever two
## cross or a corner of one lands on another, and walked face by face.
## Each face any layer covers is one piece of the built map, with the
## room of each layer over it, bottom-up; a face none covers is a hole.
## lays: [{k, vertices, sectors}] bottom-up. Returns {vertices (Vector2),
## faces: [{verts, stack: [{li, s}]}]}.
static func overlay(lays: Array) -> Dictionary:
	var rings := []
	for li in lays.size():
		var g: Dictionary = lays[li]
		for sd in g.sectors:
			var pts := _pts(g.vertices, PackedInt32Array(sd.verts))
			if pts.size() < 3 or self_crosses(pts) or absf(signed_area(pts)) < 1.0:
				continue
			rings.append({"li": li, "s": sd, "pts": pts, "area": absf(signed_area(pts)), "box": _bbox(pts)})
	var P := []
	var cell := {}
	var segs := []
	for r in rings:
		var pts: PackedVector2Array = r.pts
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if a == b:
				continue
			segs.append([a, b, Rect2(a.min(b) - Vector2.ONE, (a.max(b) - a.min(b)) + Vector2.ONE * 2.0)])
	# each segment cut at every crossing, and at every end of another that
	# lies on it
	var edges := {}
	for si in segs.size():
		var S: Array = segs[si]
		var sa: Vector2 = S[0]
		var sb: Vector2 = S[1]
		var d := sb - sa
		var cuts := [[0.0, sa.x, sa.y, 0], [1.0, sb.x, sb.y, 1]]
		for ti in segs.size():
			if ti == si:
				continue
			var T: Array = segs[ti]
			if not (T[2] as Rect2).intersects(S[2], true):
				continue
			for q in [T[0], T[1]]:
				var t := _seg_t(sa, sb, q)
				if (sa + d * t).distance_to(q) < EPS and t > 1e-6 and t < 1.0 - 1e-6:
					cuts.append([t, q.x, q.y, cuts.size()])
			if seg_cross(sa, sb, T[0], T[1]):
				var e: Vector2 = T[1] - T[0]
				var den := d.x * e.y - d.y * e.x
				if absf(den) < 1e-9:
					continue
				var t: float = ((T[0].x - sa.x) * e.y - (T[0].y - sa.y) * e.x) / den
				cuts.append([t, snappedf(sa.x + d.x * t, 0.001), snappedf(sa.y + d.y * t, 0.001), cuts.size()])
		cuts.sort_custom(func(u, v): return u[0] < v[0] or (u[0] == v[0] and u[3] < v[3]))
		var prev := -1
		for c in cuts:
			var k := _weld(P, cell, c[1], c[2])
			if prev != -1 and prev != k:
				edges[Vector2i(mini(prev, k), maxi(prev, k))] = [prev, k]
			prev = k
	# THE FACES: each point's neighbours anticlockwise, and every edge
	# walked both ways with the face on its left
	var adj := {}
	for e in edges.values():
		for pr in [[e[0], e[1]], [e[1], e[0]]]:
			if not adj.has(pr[0]):
				adj[pr[0]] = []
			if not adj[pr[0]].has(pr[1]):
				adj[pr[0]].append(pr[1])
	var order := {}
	for v in adj:
		var ns: Array = adj[v].duplicate()
		var pv: Vector2 = P[v]
		ns.sort_custom(func(p, q): return atan2(P[p].y - pv.y, P[p].x - pv.x) < atan2(P[q].y - pv.y, P[q].x - pv.x))
		order[v] = ns
	var seen := {}
	var faces := []
	for u0 in order:
		for v0 in order[u0]:
			if seen.has(Vector2i(u0, v0)):
				continue
			var ring := []
			var u: int = u0
			var v: int = v0
			var guard := 0
			while not seen.has(Vector2i(u, v)) and guard < 1000000:
				guard += 1
				seen[Vector2i(u, v)] = true
				ring.append(u)
				var around: Array = order[v]
				var i := around.find(u)
				var w: int = around[(i - 1 + around.size()) % around.size()]
				u = v
				v = w
			# spurs in and straight back out are not edges of it
			var again := true
			while again and ring.size() > 3:
				again = false
				for k in ring.size():
					var n := ring.size()
					if ring[(k - 1 + n) % n] == ring[(k + 1) % n]:
						var k2 := (k + 1) % n
						var keep := []
						for q in n:
							if q != k and q != k2:
								keep.append(ring[q])
						ring = keep
						again = true
						break
			if ring.size() < 3:
				continue
			var uniq := {}
			for q in ring:
				uniq[q] = true
			if uniq.size() != ring.size():
				continue
			var pts := PackedVector2Array()
			for q in ring:
				pts.append(P[q])
			if signed_area(pts) <= 0.25:
				continue
			faces.append(ring)
	# WHAT IS OVER EACH FACE: a point just inside it, off its longest
	# edge, and the smallest room of each layer round that point
	var out := []
	for ring in faces:
		var pts := PackedVector2Array()
		for q in ring:
			pts.append(P[q])
		var n := pts.size()
		var by_len := []
		for k in n:
			by_len.append([k, pts[k].distance_to(pts[(k + 1) % n])])
		by_len.sort_custom(func(p, q): return p[1] > q[1] or (p[1] == q[1] and p[0] < q[0]))
		var at = null
		for m in mini(6, by_len.size()):
			var k: int = by_len[m][0]
			var len: float = by_len[m][1]
			var a := pts[k]
			var b := pts[(k + 1) % n]
			var e := minf(0.05, len * 0.05)
			var x := (a.x + b.x) / 2.0 - (b.y - a.y) / len * e
			var y := (a.y + b.y) / 2.0 + (b.x - a.x) / len * e
			if pip(pts, x, y):
				at = Vector2(x, y)
				break
		if at == null:
			at = centroid(pts)
		var stack := []
		for li in lays.size():
			var best = null
			var ba := INF
			for r in rings:
				if r.li == li and r.area < ba and (r.box as Rect2).grow(0.01).has_point(at) and pip(r.pts, at.x, at.y):
					ba = r.area
					best = r.s
			if best != null:
				stack.append({"li": li, "s": best})
		out.append({"verts": ring, "stack": stack})
	return {"vertices": P, "faces": out}
