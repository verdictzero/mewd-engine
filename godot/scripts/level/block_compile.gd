## MEWD — a map in BLOCKS to a Level (the Godot build's own; at the
## user's request, the editor stopped working the way Doom does).
##
## THE WORLD IS AN INFINITE GROUND PLANE, and everything on it is a block
## pulled up out of the plan: a ring of vertices, a HEIGHT, and three
## textures — its SIDES, its TOP (what you walk on) and, where it floats
## with air under it, its UNDERSIDE (a ceiling). Nothing is carved, no
## room has a floor and a ceiling of its own, there is no void: a
## building is wall blocks and a slab block over them, a step is a low
## block, a pit is a block pushed DOWN (a negative height) into what it
## stands on. The document:
##
##   ground    {tex, light}: the plane, and the light of the open air
##   vertices  [x, y], shared and welded (as the editor's always were)
##   blocks    {id, verts, h, base, top, side, under, light, name}
##             base: null to stand on whatever is under it (the ground,
##             the block it is drawn inside on its own layer, the blocks
##             of the layers below), or a height to float at
##             light: the light of the space UNDER it (a slab lights the
##             room it roofs); the open air has the ground's — or the
##             block's `air`, where a map sets one over its top
##   lines     the overrides on an edge, keyed "a,b": tex (a skin on
##             every face of the edge), midTex (a fill across an open
##             edge: a fence, a window), xoff yoff xscale yscale,
##             blocking, blockSight, door {h, tex, style, auto, locked}
##   layers    {"1": {vertices, blocks, lines}}: the storeys. A block on
##             layer k stands on the top of what the layers under it put
##             there, so the office's walls stand on the office's floor,
##             which stands on the shop's walls
##   things, scatters, textures, world, name, nextId  as before
##
## HOW IT IS BUILT. Every layer's rings — and the ground, a square
## GROUND_EXTENT each way, as the outermost ring of layer 0 — are laid
## over each other (DocCompile.overlay: cut where they cross, walked
## face by face). Over each face the blocks round it, bottom-up (layer
## by layer, and on one layer the outermost first), raise the floor:
## each one's solid runs from its base to its top, with an open STOREY
## left wherever a base is over the floor it had (a slab floating), and
## one more over the last top, under the sky (SKY_H). Those storeys are
## Level.add_column's, and Level does the rest exactly as for a map in
## layers: the solid between two storeys is a deck of whatever thickness
## the block has, its edge drawn in the block's sides (assign_bands:
## the band's texture is the storey over it's lower texture, which is
## the block's side), the underside of a floating block the ceiling of
## the storey under it, the top of a block the floor of the one over.
## A block's auto base is the highest floor under its footprint, so a
## slab over uneven ground floats over the low parts.
##
## Not here: Doom's upper and lower textures (a face is one texture from
## the block's base to its top), roofed rooms grown walls (draw the
## walls), free props and linedefs (a block does both), a sector's
## colours and fog (a block has a light; the map keeps its light colour
## and fog).
class_name BlockCompile

const FORMAT := "mewd-blocks"
const VERSION := 1
## the ground plane runs this far each way from the origin
const GROUND_EXTENT := 65536.0
## every storey open to the sky ends here
const SKY_H := 8192.0
const EPS := 0.5
const ZEPS := 1e-6
const LAYER_PARTS := ["vertices", "blocks", "lines"]
const BLOCK_DEFAULTS := {"h": 128.0, "base": null, "top": "CONC_1", "side": "GRIDWALL", "under": null, "light": 0.72, "name": ""}
const GROUND_DEFAULTS := {"tex": "LAWN2", "light": 0.9}
const DOOR_DEFAULT := {"h": 96, "tex": "DR1_01", "style": "swing", "auto": true, "locked": false}
## what the last build worked out for every block: {"k": {id: {base,
## top}}} by layer — for the editor
static var last_blocks := {}

static func is_block_doc(doc) -> bool:
	return doc is Dictionary and str(doc.get("format", "")) == FORMAT

static func num(v, d := 0.0) -> float:
	if v == null:
		return d
	if v is float or v is int:
		return float(v)
	if v is String and v.is_valid_float():
		return v.to_float()
	return d

static func tex(o: Dictionary, k: String, d := "") -> String:
	var v = o.get(k)
	return d if v == null or str(v) == "" else str(v)

static func ground_of(doc: Dictionary) -> Dictionary:
	var g := GROUND_DEFAULTS.duplicate()
	if doc.get("ground") is Dictionary:
		g.merge(doc.ground, true)
	return g

## Every layer, bottom-up, the ground layer always among them:
## [{k, vertices, blocks, lines}].
static func layers_of(doc: Dictionary) -> Array:
	var cur := int(doc.get("layer", 0))
	var ks := [cur]
	if cur != 0:
		ks.append(0)
	var L = doc.get("layers")
	if L is Dictionary:
		for k in L:
			if not ks.has(int(k)):
				ks.append(int(k))
	ks.sort()
	var out := []
	for k in ks:
		var g := {"k": k, "vertices": [], "blocks": [], "lines": {}}
		var src = doc if k == cur else (L.get(str(k)) if L is Dictionary else null)
		if src is Dictionary:
			for p in LAYER_PARTS:
				if src.get(p) != null:
					g[p] = src[p]
		out.append(g)
	return out

static func _pts(V: Array, idx) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in idx:
		var p = V[int(i)]
		out.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	return out

## A point just inside a ring, off its longest edge (the overlay's own).
static func probe(pts: PackedVector2Array) -> Vector2:
	var n := pts.size()
	var by_len := []
	for k in n:
		by_len.append([k, pts[k].distance_to(pts[(k + 1) % n])])
	by_len.sort_custom(func(p, q): return p[1] > q[1] or (p[1] == q[1] and p[0] < q[0]))
	for m in mini(6, by_len.size()):
		var k: int = by_len[m][0]
		var len: float = by_len[m][1]
		if len <= 0.0:
			continue
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var e := minf(0.05, len * 0.05)
		var x := (a.x + b.x) / 2.0 - (b.y - a.y) / len * e
		var y := (a.y + b.y) / 2.0 + (b.x - a.x) / len * e
		if DocCompile.pip(pts, x, y):
			return Vector2(x, y)
	return DocCompile.centroid(pts)

# ------------------------------------------------------------------
# THE BUILD
# ------------------------------------------------------------------

## The blocks of every layer, each with its ring, its area and its box,
## numbers made numbers — and the ground as the first block of layer 0.
static func _prepare(doc: Dictionary, lays: Array) -> Array:
	var ground := ground_of(doc)
	var built := []
	for li in lays.size():
		var g: Dictionary = lays[li]
		var V: Array = []
		for p in g.vertices:
			V.append(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
		var blocks := []
		if int(g.k) == 0:
			var e := GROUND_EXTENT
			var n := V.size()
			V.append_array([Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)])
			blocks.append({"id": 0, "verts": [n, n + 1, n + 2, n + 3], "h": 0.0, "base": 0.0, "top": tex(ground, "tex", "LAWN2"),
				"side": tex(ground, "tex", "LAWN2"), "under": null, "light": num(ground.get("light"), 0.9), "name": "ground",
				"__ground": true})
		for b in g.blocks:
			var c: Dictionary = BLOCK_DEFAULTS.duplicate()
			c.merge(b, true)
			c["h"] = num(b.get("h"), 128.0)
			c["base"] = null if b.get("base") == null else num(b.get("base"))
			c["light"] = clampf(num(b.get("light"), 0.72), 0.0, 1.0)
			blocks.append(c)
		for b in blocks:
			var pts := _pts(V, b.verts)
			b["__pts"] = pts
			b["__area"] = absf(DocCompile.signed_area(pts))
			b["__box"] = DocCompile._bbox(pts)
			b["__k"] = int(g.k)
			b["__ok"] = pts.size() >= 3 and not DocCompile.self_crosses(pts) and b.__area >= 1.0
		# a pit (a block pushed down) draws its walls in its own sides: a
		# skin on each of its edges, unless the edge wears one already
		var lines: Dictionary = (g.lines as Dictionary).duplicate() if g.lines is Dictionary else {}
		for b in blocks:
			if b.h >= 0.0 or not b.__ok:
				continue
			var vs: Array = b.verts
			for j in vs.size():
				var key := "%d,%d" % [mini(int(vs[j]), int(vs[(j + 1) % vs.size()])), maxi(int(vs[j]), int(vs[(j + 1) % vs.size()]))]
				var o = lines.get(key)
				if o is Dictionary and str(o.get("tex", "")) != "":
					continue
				var oo: Dictionary = o.duplicate() if o is Dictionary else {}
				oo["tex"] = tex(b, "side", "GRIDWALL")
				lines[key] = oo
		# and a grid of the blocks, so a point asks only its own cell's
		var grid := DocCompile.BoxGrid.new(blocks.map(func(b): return b.__box if b.__ok else Rect2()))
		built.append({"k": int(g.k), "vertices": V, "blocks": blocks, "sectors": blocks, "lines": lines, "grid": grid})
	return built

## The blocks of layer `g` round a point, outermost first.
static func _chain(g: Dictionary, at: Vector2) -> Array:
	var out := []
	for i in (g.grid as DocCompile.BoxGrid).at(at):
		var b: Dictionary = g.blocks[i]
		if b.__ok and (b.__box as Rect2).grow(0.01).has_point(at) and DocCompile.pip(b.__pts, at.x, at.y):
			out.append(b)
	out.sort_custom(func(p, q): return p.__area > q.__area)
	return out

## WHERE SOMETHING ON LAYER k STANDS at (x, y), once the level is built:
## the open storey there with the highest floor among those a block of
## layer k or under left (Sector.layer) — on the terrace for layer 1,
## under it for layer 0 — or the lowest open storey, or null off the map.
static func stand_in(lv: Level, x: float, y: float, k: int) -> Level.Sector:
	var g := lv.sector_at(x, y)
	if g == null:
		return null
	var best: Level.Sector = null
	var lowest: Level.Sector = null
	var c := g
	while c != null:
		if c.ceil - c.floor > ZEPS:
			if lowest == null:
				lowest = c
			if c.layer <= k and (best == null or c.floor > best.floor):
				best = c
		c = lv.sectors[c.above] if c.above != -1 else null
	return best if best != null else lowest

static func stand_z(lv: Level, x: float, y: float, k: int) -> float:
	var s := stand_in(lv, x, y, k)
	return s.floor if s != null else 0.0

## The floor after block b has been put on it.
static func _raise(fl: float, b: Dictionary) -> float:
	var top: float = b.__top
	if b.h >= 0.0:
		return maxf(fl, top)
	return top

static func compile(doc: Dictionary) -> Level:
	var probs: Array = DocCompile.problems
	last_blocks = {}
	var lays := layers_of(doc)
	var built := _prepare(doc, lays)
	var ground := ground_of(doc)
	# 1. the plan, cut face by face
	var ov := DocCompile.overlay(built)
	var P: Array = ov.vertices
	var faces := []
	for f in ov.faces:
		var pts := _pts(P, f.verts)
		faces.append({"verts": f.verts, "pts": pts, "at": probe(pts), "floor": 0.0, "ev": []})
	# 2. the blocks raise each face's floor, bottom-up: a layer at a
	# time, and on one layer the outermost first (a block drawn inside
	# another stands on it); a block with no base of its own stands on
	# the highest floor under its footprint
	for g in built:
		var chains := []
		for f in faces:
			chains.append(_chain(g, f.at))
		# the blocks standing on what is under them, the outermost first;
		# then the ones floating at a base of their own, bottom-up (a
		# panel over a panel, a roof on its posts)
		var order: Array = g.blocks.filter(func(b): return b.__ok)
		order.sort_custom(func(p, q):
			if (p.base == null) != (q.base == null):
				return p.base == null
			if p.base != null and float(p.base) != float(q.base):
				return float(p.base) < float(q.base)
			return p.__area > q.__area)
		for b in order:
			var mine := []
			for fi in faces.size():
				if chains[fi].has(b):
					mine.append(fi)
			var base: float
			if b.base != null:
				base = float(b.base)
			else:
				base = 0.0
				for fi in mine:
					base = maxf(base, faces[fi].floor)
			b["__base"] = base
			b["__top"] = base + b.h
			if b.get("__ground", false):
				continue
			var buried := false
			for fi in mine:
				var f: Dictionary = faces[fi]
				if b.h >= 0.0 and b.__top < f.floor - EPS:
					# under what it stands on: nothing of it shows there (a
					# block floating at its own base may well be inside
					# another; one standing on the ground is a mistake)
					buried = b.base == null
					continue
				f.ev.append({"b": b, "fb": f.floor})
				f.floor = _raise(f.floor, b)
			if buried:
				probs.append({"kind": "block", "id": b.get("id"), "layer": b.__k,
					"msg": "block %s (layer %d) is buried: its top (%s) is under what it stands on — raise it" % [str(b.get("id")), b.__k, str(b.__top)]})
		# what the layer leaves, for the things and the doors
		var lb := {}
		for b in g.blocks:
			b["floor"] = b.get("__top", 0.0)
			b["ceil"] = b.get("__top", 0.0) + (SKY_H if b.get("__ground", false) else 256.0)
			if not b.get("__ground", false):
				lb[b.get("id")] = {"base": b.get("__base", 0.0), "top": b.get("__top", 0.0)}
		last_blocks[str(g.k)] = lb
	# 3. each face's storeys: the air under every floating block, and
	# the open sky over the last
	var F := doc.duplicate()
	F["vertices"] = P
	F["lines"] = {}
	F["linedefs"] = []
	F["props"] = []
	F.erase("layers")
	F.erase("layer")
	var fs := []
	var gb: Dictionary = built[0].blocks[0]
	for i in faces.size():
		var f: Dictionary = faces[i]
		var st := []
		var fl := 0.0
		var ftex: String = tex(gb, "top", "LAWN2")
		var side: String = tex(gb, "side", ftex)
		var stand: Dictionary = gb
		for e in f.ev:
			var b: Dictionary = e.b
			var bside := tex(b, "side", "GRIDWALL")
			if b.h >= 0.0 and b.__base > e.fb + EPS:
				# AIR UNDER IT: a storey, the block's underside its ceiling
				st.append({"k": stand.__k, "s": stand, "p": _storey(e.fb, b.__base, ftex, side, tex(b, "under", bside), bside,
					b.light, false, stand, b)})
			elif b.h > 0.0:
				# SOLID ON SOLID: a storey of no height at the join, so the
				# edge of each block is a band of its own, in its own sides
				# (Level.assign_bands cuts at every storey's heights)
				var z: float = maxf(e.fb, b.__base)
				var p := _storey(z, z, "NONE", side, "NONE", bside, b.light, false, stand, b)
				p["name"] = "join"
				st.append({"k": stand.__k, "s": stand, "p": p})
			fl = _raise(e.fb, b)
			if b.h < 0.0:
				# A PIT: the joins it cuts through go, the air over it
				# comes down to its floor
				var kept := []
				for q in st:
					var p: Dictionary = q.p
					if p.ceil - p.floor <= ZEPS and p.floor >= fl - EPS:
						continue
					if p.floor > fl:
						p.floor = fl
					kept.append(q)
				st = kept
			ftex = tex(b, "top", "CONC_1")
			side = bside
			stand = b
		# the open air over the last top: the ground's light, or the
		# block's own `air` where a map sets one (a dim district)
		var air := num(stand.get("air"), num(ground.get("light"), 0.9))
		st.append({"k": stand.__k, "s": stand, "p": _storey(fl, SKY_H, ftex, side, "SKY", side, air, true, stand, null)})
		fs.append({"id": -(i + 1), "verts": f.verts, "__storeys": st})
	F["sectors"] = fs
	# 4. the things (where each stands is asked of the level, below)
	var things := []
	for t in doc.get("things", []):
		things.append(t.duplicate())
	F["things"] = things
	# the built area: the blockmap, the forest and the start's fallback
	# want a finite map; the ground runs on past it
	var bb := Rect2()
	var first := true
	for g in built:
		for b in g.blocks:
			if b.get("__ground", false) or not b.__ok:
				continue
			bb = b.__box if first else bb.merge(b.__box)
			first = false
	for t in things:
		var r := Rect2(Vector2(t.x, t.y), Vector2.ZERO)
		bb = r if first else bb.merge(r)
		first = false
	if first:
		bb = Rect2(-512, -512, 1024, 1024)
	F["__bounds"] = bb.grow(512.0)
	# the scatters spread over the ground layer, inside the built area
	var G: Dictionary = built[0]
	var gs := []
	for b in G.blocks:
		if b.get("__ground", false):
			var e: Rect2 = bb.grow(1024.0)
			var n: int = G.vertices.size()
			G.vertices.append_array([e.position, Vector2(e.end.x, e.position.y), e.end, Vector2(e.position.x, e.end.y)])
			var gc: Dictionary = b.duplicate()
			gc["verts"] = [n, n + 1, n + 2, n + 3]
			gs.append(gc)
		else:
			gs.append(b)
	var lv := DocCompile._compile_core(F, {"layers": built, "blocks": true, "ground_blocks": gs, "built": built})
	# where things stand: on the floor their layer leaves them (a thing
	# on layer 1 on the terrace, one on layer 0 under it)
	for t in lv.things:
		var k := int(t.get("layer", 0) if t.get("layer") != null else 0)
		t["z"] = stand_z(lv, float(t.x), float(t.y), k)
	return lv

static func _storey(z0: float, z1: float, ftex: String, lower: String, ctex: String, upper: String, light: float, outdoor: bool, stand: Dictionary, over) -> Dictionary:
	var nm: String = str(stand.get("name", ""))
	return {"floor": z0, "ceil": z1, "light": light, "ambient": light,
		"floorTex": ftex, "ceilTex": ctex, "wallTex": lower, "upperTex": upper, "lowerTex": lower,
		"outdoor": outdoor, "sky": 1.0 if outdoor else 0.0, "fuel": 0,
		"name": nm if nm != "" else ("block %s" % str(stand.get("id", ""))),
		"__block": stand.get("id"), "__over": null if over == null else over.get("id"), "__layer": stand.get("__k", 0)}

# ------------------------------------------------------------------
# DOORS: a line override `door` on an edge, the slab across it between
# the floor and the ceiling of the storeys either side on its layer —
# under a lintel block, up to its underside (DocCompile._build_doors
# for a map in rooms)
# ------------------------------------------------------------------

static func build_doors(lv: Level, built: Array) -> void:
	var probs: Array = DocCompile.problems
	for g in built:
		var L: Dictionary = g.lines
		var V: Array = g.vertices
		for k in L:
			var o = L[k]
			if not (o is Dictionary and o.get("door") is Dictionary):
				continue
			var ab := str(k).split(",")
			if ab.size() != 2:
				continue
			var ia := int(ab[0])
			var ib := int(ab[1])
			if ia < 0 or ib < 0 or ia >= V.size() or ib >= V.size():
				continue
			var a: Vector2 = V[ia]
			var b: Vector2 = V[ib]
			var ls := DocCompile._level_lines_on(lv, a, b)
			if ls.is_empty() or a.distance_to(b) < 8.0:
				probs.append({"kind": "line", "id": k, "layer": g.k, "msg": "the door on line %s is on no edge of the map" % k})
				continue
			var dd: Dictionary = DOOR_DEFAULT.duplicate()
			dd.merge(o.door, true)
			var n := (b - a).normalized().orthogonal()
			var m := (a + b) / 2.0
			# THE LINTEL: the floating block the line is an edge of
			var lintel = null
			for bl in g.blocks:
				if bl.get("__ground", false) or not bl.__ok or bl.base == null:
					continue
				var vs: Array = bl.verts
				for j in vs.size():
					var p := int(vs[j])
					var q := int(vs[(j + 1) % vs.size()])
					if (p == ia and q == ib) or (p == ib and q == ia):
						lintel = bl
						break
				if lintel != null:
					break
			# the storeys either side, on the door's layer: the door stands
			# on the higher floor, under the lower ceiling, and swings into
			# the side that is a room (not the passage under the lintel)
			var z0 := -INF
			var lt := INF
			var into := n
			var into_ceil := INF
			var over_id = null
			for sgn in [1.0, -1.0]:
				var q: Vector2 = m + n * (4.0 * sgn)
				var st := stand_in(lv, q.x, q.y, int(g.k))
				if st == null:
					continue
				z0 = maxf(z0, st.floor)
				lt = minf(lt, st.ceil)
				var passage: bool = lintel != null and st.over == lintel.get("id")
				if passage:
					over_id = st.over
				elif st.ceil < into_ceil:
					into_ceil = st.ceil
					into = n * sgn
			if z0 == -INF:
				z0 = 0.0
			var dr := Level.Door.new()
			dr.index = lv.doors.size()
			dr.a = a
			dr.b = b
			dr.inside = into
			dr.z0 = z0
			var h := maxf(24.0, num(dd.get("h"), 96.0))
			var roofed: bool = lt < SKY_H - 1.0
			dr.top = minf(lt, z0 + h) if roofed else z0 + h
			dr.lintel_top = lt if roofed else dr.top
			dr.tex = str(dd.get("tex", "DR1_01"))
			var lintel_tex := "GRIDWALL"
			dr.wall = 0.0
			if over_id != null:
				for bl in g.blocks:
					if bl.get("id") == over_id:
						lintel_tex = tex(bl, "side", "GRIDWALL")
						# how far the lintel block reaches across the line
						var lo := INF
						var hi := -INF
						for p in bl.__pts:
							var d: float = (p - m).dot(n)
							lo = minf(lo, d)
							hi = maxf(hi, d)
						dr.wall = maxf(0.0, minf(absf(lo), absf(hi)) if lo < -EPS and hi > EPS else maxf(absf(lo), absf(hi)))
						if dr.wall < 4.0:
							dr.wall = 0.0
			dr.lintel_tex = str(dd.get("lintelTex", lintel_tex))
			dr.style = "slide" if str(dd.get("style", "swing")) == "slide" else "swing"
			dr.auto = bool(dd.get("auto", true))
			dr.locked = bool(dd.get("locked", false))
			dr.lines = ls
			for l in ls:
				l.door = dr
			lv.doors.append(dr)
