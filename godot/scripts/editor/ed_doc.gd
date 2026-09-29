## MEWD Editor — the map as a document (js/editor/doc.js, the parts
## that are not the compiler: the compiler is godot/scripts/level/
## doc_compile.gd).
##
## A map is VERTICES, SECTORS that are rings of vertex indices, THINGS
## standing on them, LINE overrides keyed by the vertex pair ("a,b",
## smaller first), LINEDEFS of their own, free boxes (PROPS), SCATTERS,
## the map's own TEXTURES and its WORLD. A vertex two sectors share is
## one vertex: drag it and both move.
##
## IN MEMORY the vertices are Vector2 (what DocCompile and the maps
## write); ON DISK they are [x, y], and the file is the web build's own
## JSON, key for key, so a map saved by either editor opens in the other
## (to_json / parse). Undo is whole snapshots, as the web's History is.
##
## Also here, as in doc.js: the tidy after every edit (compact), the
## problem report (problems_of), the LAYERS (the map in storeys), and
## texture alignment across many lines (faces_of, face_runs,
## align_textures).
class_name EdDoc

const DOC_FORMAT := "gss-map"
const DOC_VERSION := 1

## THING_TYPES: the things a map may place, and what each is for the
## editor's palette. The keys are the game's actor types, plus START.
const THING_TYPES := {
	"START": {"name": "Player start", "color": "#4af", "radius": 16, "one": true},
	"SHOPPER": {"name": "Shopper", "color": "#fc4", "radius": 18},
	"TOWNIE": {"name": "Townsperson", "color": "#fa6", "radius": 18},
	"TROLLEY": {"name": "Trolley", "color": "#aaa", "radius": 16},
	"BOLLARD": {"name": "Bollard", "color": "#ddd", "radius": 10},
	"FUELCAN": {"name": "Fuel can", "color": "#f44", "radius": 10},
	"CRATE": {"name": "Crate", "color": "#c93", "radius": 20},
	"LAMP": {"name": "Ceiling lamp", "color": "#ffe", "radius": 12},
	"STREETLAMP": {"name": "Street lamp", "color": "#ff8", "radius": 10},
	"GRAVESTONE": {"name": "Gravestone", "color": "#999", "radius": 14},
	"PLANT": {"name": "Plant", "color": "#5c5", "radius": 14},
}

const DEFAULT_FLOOR := "LAWN2"
const DEFAULT_SKYBOX := "BSKY2"
## An open world by default: a new sector is under the sky.
const SECTOR_DEFAULTS := {
	"floor": 0, "ceil": 1024,
	"floorTex": DEFAULT_FLOOR, "ceilTex": "SKY", "wallTex": "GRIDWALL", "upperTex": null, "lowerTex": null,   # (the two nulls: the web build's file shape; the editor no longer shows them)
	"light": 0.72, "outdoor": true, "sky": 0, "name": "",
}
## a new map's ground: full bright, walled at a height you see over
const GROUND_DEFAULTS := {"ceil": 256, "light": 1}
const NEW_MAP_AMBIENT := {"color": "#ffffff", "amount": 0.35}
const COLOR_PARTS := ["floor", "ceil", "thing", "top", "bottom"]

const EPS := 0.5
## how near two vertices are the SAME vertex
const WELD := 0.49
const LINEDEF_THICK := 8
const LINEDEF_H := 128
const LAYER_PARTS := ["vertices", "sectors", "lines", "linedefs"]
const LAYER_MIN := -8
const LAYER_MAX := 32
const STOREY_H := 256

# ---------------------------------------------------------------------
# small things
# ---------------------------------------------------------------------

## Math.round: halves go up, as JS's do (GDScript's go away from zero).
static func jsround(v: float) -> float:
	return floorf(v + 0.5)

static func num(v, d := 0.0) -> float:
	if v == null:
		return d
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String and v.is_valid_float():
		return v.to_float()
	return d

## `a ?? d` in a dictionary: the value, or the default when it is
## missing or null.
static func got(o: Dictionary, k: String, d = null):
	var v = o.get(k)
	return d if v == null else v

## A texture field's value, "" for none (null, missing or empty).
static func tex(o: Dictionary, k: String) -> String:
	var v = o.get(k)
	return "" if v == null else str(v)

static func line_key(a: int, b: int) -> String:
	return "%d,%d" % [mini(a, b), maxi(a, b)]

static func key_verts(k: String) -> Vector2i:
	var p := k.split(",")
	if p.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(p[0]), int(p[1]))

static func ring_of(doc: Dictionary, s: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var V: Array = doc.vertices
	for i in s.verts:
		out.append(V[int(i)])
	return out

static func signed_area(pts: PackedVector2Array) -> float:
	return DocCompile.signed_area(pts)

static func pip(pts: PackedVector2Array, x: float, y: float) -> bool:
	return DocCompile.pip(pts, x, y)

static func seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return DocCompile.seg_cross(a, b, c, d)

static func self_crosses(pts: PackedVector2Array) -> bool:
	return DocCompile.self_crosses(pts)

static func strictly_inside(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	return DocCompile.strictly_inside(inner, outer)

static func hole_in(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	return DocCompile.hole_in(inner, outer)

static func centroid(pts: PackedVector2Array) -> Vector2:
	return DocCompile.centroid(pts)

## How far p is from the segment a-b (x), and how far along it (y).
static func seg_dist(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var d := b - a
	var l2 := d.length_squared()
	var t := clampf((p - a).dot(d) / l2, 0.0, 1.0) if l2 > 0.0 else 0.0
	return Vector2(p.distance_to(a + d * t), t)

static func on_boundary(pts: PackedVector2Array, p: Vector2) -> bool:
	var n := pts.size()
	var j := n - 1
	for i in n:
		if seg_dist(pts[j], pts[i], p).x < EPS:
			return true
		j = i
	return false

static func bbox(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	return Rect2(mn, mx - mn)

static func _boxes_meet(a: Rect2, b: Rect2, e := 1.0) -> bool:
	return a.position.x <= b.end.x + e and b.position.x <= a.end.x + e \
		and a.position.y <= b.end.y + e and b.position.y <= a.end.y + e

## A copy of a sector (or anything) with some keys gone — JSON's round
## trip in the web build.
static func copy_without(o: Dictionary, drop: Array) -> Dictionary:
	var c: Dictionary = o.duplicate(true)
	for k in drop:
		c.erase(k)
	return c

## '#rgb' or '#rrggbb' as a Color.
static func col(h, d := Color.MAGENTA) -> Color:
	if h == null:
		return d
	var s := str(h)
	if not s.begins_with("#"):
		s = "#" + s
	if Color.html_is_valid(s):
		return Color.html(s)
	return d

# ---------------------------------------------------------------------
# THE DOCUMENT
# ---------------------------------------------------------------------

static func default_world() -> Dictionary:
	return DocCompile.default_world()

## A blank map: an open world — one square of ground under the sky, and
## a start in it.
static func new_doc(name := "UNTITLED", size := 4096.0) -> Dictionary:
	var sec := {"id": 1, "verts": [0, 1, 2, 3]}
	sec.merge(SECTOR_DEFAULTS.duplicate(true))
	sec.merge(GROUND_DEFAULTS, true)
	sec["name"] = "ground"
	var world := default_world()
	world["skybox"] = DEFAULT_SKYBOX
	world["ambient"] = NEW_MAP_AMBIENT.duplicate()
	return {
		"format": DOC_FORMAT, "version": DOC_VERSION, "name": name,
		"vertices": [Vector2(0, 0), Vector2(size, 0), Vector2(size, size), Vector2(0, size)],
		"sectors": [sec],
		"lines": {},
		"linedefs": [],
		"things": [{"id": 1, "type": "START", "x": size / 2.0, "y": size / 4.0, "angle": PI / 2.0}],
		"textures": [],
		"props": [],
		"scatters": [],
		"world": world,
		"nextId": 2,
	}

## THE GRID, as the editor opens it (gridDoc): the field, and sixty
## people placed by the same roll.
static func grid_doc() -> Dictionary:
	var F := 10240.0
	var mid := F / 2.0
	var d := new_doc("THE GRID")
	d.vertices = [Vector2(0, 0), Vector2(F, 0), Vector2(F, F), Vector2(0, F)]
	var sec := {"id": 1, "verts": [0, 1, 2, 3]}
	sec.merge(SECTOR_DEFAULTS.duplicate(true))
	sec.merge(GROUND_DEFAULTS, true)
	sec["name"] = "field"
	d.sectors = [sec]
	d.things = [{"id": 1, "type": "START", "x": mid, "y": mid - 512, "angle": PI / 2.0}]
	var rnd := U.Rng.new(20250924)
	var id := 2
	var span := F * 0.66
	var edge := (F - span) / 2.0
	for k in 60:
		var x := jsround(edge + rnd.next() * span)
		var y := jsround(edge + rnd.next() * span)
		var a := rnd.next() * PI * 2.0
		var v := int(rnd.next() * 17)
		d.things.append({"id": id, "type": "SHOPPER", "x": x, "y": y, "angle": a, "variant": v})
		id += 1
	d.nextId = id
	return d

static func take_id(doc: Dictionary) -> int:
	var id := int(doc.get("nextId", 1))
	doc["nextId"] = id + 1
	return id

## Every line of the document: each vertex pair round every sector, with
## the sectors on it — a hole's edge has the room it is cut out of too.
static func lines_of(doc: Dictionary, parents = null) -> Array:
	if parents == null:
		parents = hole_parents(doc)
	var map := {}
	var order := []
	var S: Array = doc.sectors
	for si in S.size():
		var r: Array = S[si].verts
		var n := r.size()
		for i in n:
			var a := int(r[i])
			var b := int(r[(i + 1) % n])
			var k := line_key(a, b)
			var l = map.get(k)
			if l == null:
				l = {"key": k, "a": mini(a, b), "b": maxi(a, b), "sectors": []}
				map[k] = l
				order.append(l)
			if not l.sectors.has(si):
				l.sectors.append(si)
	for l in order:
		if l.sectors.size() == 1 and parents[l.sectors[0]] >= 0:
			l.sectors.append(parents[l.sectors[0]])
	return order

## For each sector, the index of the sector it is a hole in (the smallest
## it lies inside), or -1.
static func hole_parents(doc: Dictionary) -> PackedInt32Array:
	var S: Array = doc.sectors
	var plain := []
	var boxes := []
	var areas := PackedFloat64Array()
	for s in S:
		var r := ring_of(doc, s)
		plain.append(r)
		boxes.append(bbox(r))
		areas.append(absf(signed_area(r)))
	var out := PackedInt32Array()
	out.resize(S.size())
	for i in S.size():
		out[i] = -1
		if plain[i].size() < 3:
			continue
		var bi: Rect2 = boxes[i]
		var ba := INF
		for j in S.size():
			if i == j or plain[j].size() < 3:
				continue
			var a := areas[j]
			if a >= ba:
				continue
			var bj: Rect2 = boxes[j]
			if bi.position.x < bj.position.x - EPS or bi.position.y < bj.position.y - EPS \
					or bi.end.x > bj.end.x + EPS or bi.end.y > bj.end.y + EPS:
				continue
			if hole_in(plain[i], plain[j]):
				ba = a
				out[i] = j
	return out

# ---------------------------------------------------------------------
# TIDYING: what an edit leaves behind
# ---------------------------------------------------------------------

## Weld vertices dragged onto each other, drop the ones nobody uses, drop
## degenerate sectors, renumber; line overrides and linedefs follow.
static func compact(doc: Dictionary, weld := WELD) -> Dictionary:
	var V: Array = doc.vertices
	var nv := V.size()
	var to := PackedInt32Array()
	to.resize(nv)
	for i in nv:
		to[i] = i
	# weld, through a grid of cells a unit across so it is not n²
	var cells := {}
	for i in nv:
		var p: Vector2 = V[i]
		var cx := floori(p.x)
		var cy := floori(p.y)
		var found := -1
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c = cells.get(Vector2i(cx + dx, cy + dy))
				if c == null:
					continue
				for j in c:
					var q: Vector2 = V[j]
					if absf(q.x - p.x) <= weld and absf(q.y - p.y) <= weld and (found < 0 or j < found):
						found = j
		if found >= 0:
			to[i] = found
		else:
			var key := Vector2i(cx, cy)
			if not cells.has(key):
				cells[key] = []
			cells[key].append(i)
	for s in doc.sectors:
		var vs: Array = []
		for v in s.verts:
			vs.append(to[int(v)])
		var kept: Array = []
		for k in vs.size():
			if vs[k] != vs[(k + 1) % vs.size()]:
				kept.append(vs[k])
		s.verts = kept
	var S2: Array = []
	for s in doc.sectors:
		if s.verts.size() >= 3 and absf(signed_area(ring_of(doc, s))) > 0.25:
			S2.append(s)
	doc.sectors = S2
	var used := {}
	for s in doc.sectors:
		for v in s.verts:
			used[int(v)] = true
	var lds: Array = []
	for e in doc.get("linedefs", []):
		var a := int(e[0])
		var b := int(e[1])
		if a < 0 or b < 0 or a >= nv or b >= nv:
			continue
		a = to[a]
		b = to[b]
		if a != b:
			lds.append([a, b])
	for e in lds:
		used[e[0]] = true
		used[e[1]] = true
	var remap := {}
	var nvs: Array = []
	for i in nv:
		if used.has(i) and to[i] == i:
			remap[i] = nvs.size()
			nvs.append(V[i])
	for s in doc.sectors:
		var r: Array = []
		for v in s.verts:
			r.append(remap[int(v)])
		s.verts = r
	var lines := {}
	var old: Dictionary = doc.get("lines", {})
	for k in old:
		var ab := key_verts(k)
		if ab.x < 0 or ab.x >= nv or ab.y < 0 or ab.y >= nv:
			continue
		var na = remap.get(to[ab.x])
		var nb = remap.get(to[ab.y])
		if na != null and nb != null and na != nb:
			lines[line_key(na, nb)] = old[k]
	var edges := {}
	for s in doc.sectors:
		var r: Array = s.verts
		for k in r.size():
			edges[line_key(r[k], r[(k + 1) % r.size()])] = true
	var kept_l := {}
	var out_l: Array = []
	for e in lds:
		var na = remap.get(e[0])
		var nb = remap.get(e[1])
		if na == null or nb == null or na == nb:
			continue
		var k := line_key(na, nb)
		if edges.has(k) or kept_l.has(k):
			continue
		kept_l[k] = true
		out_l.append([na, nb])
	doc.linedefs = out_l
	doc.vertices = nvs
	doc.lines = lines
	return doc

# ---------------------------------------------------------------------
# PROBLEMS: what the compiler will refuse or quietly get wrong
# ---------------------------------------------------------------------

static func problems_of(doc: Dictionary) -> Array:
	var out := []
	var S: Array = doc.sectors
	var rings := []
	var boxes := []
	for s in S:
		var r := ring_of(doc, s)
		rings.append(r)
		boxes.append(bbox(r))
	for i in S.size():
		var r: PackedVector2Array = rings[i]
		var s: Dictionary = S[i]
		if r.size() < 3:
			out.append({"kind": "sector", "id": s.id, "msg": "sector %d has fewer than three corners" % s.id})
		elif self_crosses(r):
			out.append({"kind": "sector", "id": s.id, "msg": "sector %d crosses itself" % s.id})
		if num(s.get("ceil"), 0) < num(s.get("floor"), 0):
			out.append({"kind": "sector", "id": s.id, "msg": "sector %d is inside out: its ceiling is below its floor" % s.id})
	# two sectors that overlap without one being a hole in the other
	for i in S.size():
		for j in range(i + 1, S.size()):
			if not _boxes_meet(boxes[i], boxes[j]):
				continue
			var a: PackedVector2Array = rings[i]
			var b: PackedVector2Array = rings[j]
			if hole_in(a, b) or hole_in(b, a):
				continue
			var crosses := false
			for p in a.size():
				if crosses:
					break
				var a0 := a[p]
				var a1 := a[(p + 1) % a.size()]
				for q in b.size():
					if seg_cross(a0, a1, b[q], b[(q + 1) % b.size()]):
						crosses = true
						break
			if not crosses:
				var a_in_b := _in_other(a, b)
				var b_in_a := _in_other(b, a)
				if a_in_b or b_in_a:
					var inner: Dictionary = S[i] if a_in_b else S[j]
					var outer: Dictionary = S[j] if a_in_b else S[i]
					var touching := false
					if a_in_b:
						for p in a:
							if on_boundary(b, p):
								touching = true
								break
					else:
						for p in b:
							if on_boundary(a, p):
								touching = true
								break
					if touching and not (a_in_b and b_in_a):
						out.append({"kind": "sector", "id": inner.id, "msg": "sector %d touches the edge of sector %d without sharing a whole wall — draw it clear of the edge, or along the wall" % [inner.id, outer.id]})
					else:
						out.append({"kind": "sector", "id": inner.id, "msg": "sectors %d and %d overlap" % [S[i].id, S[j].id]})
					continue
			if crosses:
				out.append({"kind": "sector", "id": S[i].id, "msg": "sectors %d and %d overlap" % [S[i].id, S[j].id]})
	var has_start := false
	for t in doc.things:
		if t.type == "START":
			has_start = true
			break
	if not has_start:
		out.append({"kind": "map", "msg": "there is no player start"})
	var lay := int(doc.get("layer", 0))
	for t in doc.things:
		if int(num(t.get("layer"), 0)) != lay:
			continue
		var inside := false
		for r in rings:
			if pip(r, num(t.x), num(t.y)):
				inside = true
				break
		if not inside:
			out.append({"kind": "thing", "id": t.id, "msg": "%s %d is outside every sector" % [t.type, t.id]})
	return out

static func _in_other(p: PackedVector2Array, q: PackedVector2Array) -> bool:
	for k in p.size():
		var u := p[k]
		var w := p[(k + 1) % p.size()]
		for pt in [u, (u + w) / 2.0]:
			if pip(q, pt.x, pt.y) and not on_boundary(q, pt):
				return true
	return false

# ---------------------------------------------------------------------
# LAYERS: the map in storeys. The layer being edited is where the map
# always was (doc.vertices, .sectors, .lines, .linedefs); the others
# wait in doc.layers[k].
# ---------------------------------------------------------------------

static func _empty_layer() -> Dictionary:
	return {"vertices": [], "sectors": [], "lines": {}, "linedefs": []}

static func layer_geom(doc: Dictionary, k = null) -> Dictionary:
	var cur := int(doc.get("layer", 0))
	var kk: int = cur if k == null else int(k)
	if kk == cur:
		return {"vertices": doc.vertices, "sectors": doc.sectors, "lines": doc.get("lines", {}), "linedefs": doc.get("linedefs", [])}
	var g := _empty_layer()
	var L: Dictionary = doc.get("layers", {})
	var have = L.get(str(kk))
	if have is Dictionary:
		for p in LAYER_PARTS:
			if have.has(p):
				g[p] = have[p]
	return g

## Every layer with something on it (and the one being edited), bottom-up.
static func layers_of(doc: Dictionary) -> Array:
	var ks := {int(doc.get("layer", 0)): true}
	var L: Dictionary = doc.get("layers", {})
	for k in L:
		var g = L[k]
		if g is Dictionary and (not g.get("sectors", []).is_empty() or not g.get("linedefs", []).is_empty()):
			ks[int(k)] = true
	var keys := ks.keys()
	keys.sort()
	var out := []
	for k in keys:
		var g := layer_geom(doc, k)
		g["k"] = k
		out.append(g)
	return out

static func is_layered(doc: Dictionary) -> bool:
	var n := 0
	for g in layers_of(doc):
		if not g.sectors.is_empty() or not g.linedefs.is_empty():
			n += 1
	return n > 1

## Make layer k the one being edited; the one that was is put away.
static func set_layer(doc: Dictionary, k: int) -> Dictionary:
	k = clampi(k, LAYER_MIN, LAYER_MAX)
	var cur := int(doc.get("layer", 0))
	if k == cur:
		return doc
	if not doc.has("layers"):
		doc["layers"] = {}
	var L: Dictionary = doc.layers
	var out := {"vertices": doc.vertices, "sectors": doc.sectors, "lines": doc.get("lines", {}), "linedefs": doc.get("linedefs", [])}
	if not out.sectors.is_empty() or not out.linedefs.is_empty():
		L[str(cur)] = out
	else:
		L.erase(str(cur))
	var g := _empty_layer()
	var have = L.get(str(k))
	if have is Dictionary:
		for p in LAYER_PARTS:
			if have.has(p):
				g[p] = have[p]
	L.erase(str(k))
	for p in LAYER_PARTS:
		doc[p] = g[p]
	doc["layer"] = k
	if L.is_empty():
		doc.erase("layers")
	if k == 0:
		doc.erase("layer")
	return doc

## The smallest sector of geometry g round (x, y), or null.
static func sector_in(g: Dictionary, x: float, y: float):
	var best = null
	var ba := INF
	for s in g.sectors:
		var r := PackedVector2Array()
		for i in s.verts:
			r.append(g.vertices[int(i)])
		if r.size() < 3 or not pip(r, x, y):
			continue
		var a := absf(signed_area(r))
		if a < ba:
			ba = a
			best = s
	return best

## What a room drawn on layer k at (x, y) starts as, with nothing of its
## own layer round it: standing on the room of the layer below.
static func layer_base(doc: Dictionary, k: int, x: float, y: float):
	if k == 0:
		return null
	var lays: Array = []
	for g in layers_of(doc):
		if g.k != k:
			lays.append(g)
	var below: Array = []
	var above: Array = []
	for g in lays:
		if g.k < k:
			below.push_front(g)
		elif g.k > k:
			above.append(g)
	if k > 0:
		for g in below:
			var s = sector_in(g, x, y)
			if s == null:
				continue
			var c := copy_without(s, ["id", "verts", "storeys"])
			c["name"] = ""
			var f := num(s.get("ceil"), STOREY_H)
			var hgt := maxf(64.0, num(s.get("ceil"), STOREY_H) - num(s.get("floor"), 0))
			c["floor"] = f
			c["ceil"] = f + hgt
			return c
		return {"floor": k * STOREY_H, "ceil": (k + 1) * STOREY_H}
	for g in above:
		var s = sector_in(g, x, y)
		if s == null:
			continue
		var c := copy_without(s, ["id", "verts", "storeys"])
		c["name"] = ""
		var cz := num(s.get("floor"), 0)
		var hgt := maxf(64.0, num(s.get("ceil"), STOREY_H) - num(s.get("floor"), 0))
		c["ceil"] = cz
		c["floor"] = cz - hgt
		c["ceilTex"] = tex(s, "floorTex") if tex(s, "floorTex") != "" else "CEILDECK"
		c["outdoor"] = false
		return c
	return {"floor": k * STOREY_H, "ceil": (k + 1) * STOREY_H, "ceilTex": "CEILDECK", "outdoor": false}

static func layer_floor_at(doc: Dictionary, k: int, x: float, y: float):
	var s = sector_in(layer_geom(doc, k), x, y)
	return null if s == null else num(s.get("floor"), 0)

## The document to compile when it is NOT in layers: the one layer with
## anything on it, whichever is open. (A map in layers is compiled whole
## — DocCompile lays the storeys over each other as columns of rooms.)
static func for_compile(doc: Dictionary) -> Dictionary:
	var lays := layers_of(doc)
	var filled: Array = []
	for g in lays:
		if not g.sectors.is_empty() or not g.linedefs.is_empty():
			filled.append(g)
	var cur := int(doc.get("layer", 0))
	var pick = null
	if filled.size() == 1:
		pick = filled[0]
	elif filled.size() > 1:
		for g in filled:
			if g.k == 0:
				pick = g
		if pick == null:
			pick = filled[0]
	if pick == null or pick.k == cur:
		return doc
	var d := doc.duplicate()
	for p in LAYER_PARTS:
		d[p] = pick[p]
	var th: Array = []
	for t in doc.things:
		if int(num(t.get("layer"), 0)) == pick.k:
			th.append(t)
	d["things"] = th
	return d

# ---------------------------------------------------------------------
# TEXTURE ALIGNMENT across many lines — Doom Builder's auto-align and fit
# ---------------------------------------------------------------------

## The faces (one side of a line each) of the given lines.
static func faces_of(doc: Dictionary, keys: Array, lines = null) -> Array:
	if lines == null:
		lines = lines_of(doc)
	var by_key := {}
	for l in lines:
		by_key[l.key] = l
	var out := []
	var S: Array = doc.sectors
	for key in keys:
		var l = by_key.get(key)
		if l == null:
			continue
		var A: Vector2 = doc.vertices[l.a]
		var B: Vector2 = doc.vertices[l.b]
		var len := A.distance_to(B)
		if not (len > 0):
			continue
		var o: Dictionary = doc.get("lines", {}).get(key, {})
		var secs: Array = []
		for i in l.sectors:
			secs.append(S[i])
		for s in secs:
			var m := (A + B) / 2.0
			var nrm := Vector2(-(B.y - A.y), B.x - A.x) / len
			var ring := ring_of(doc, s)
			var left := pip(ring, m.x + nrm.x, m.y + nrm.y)
			var right := pip(ring, m.x - nrm.x, m.y - nrm.y)
			var on_right := right and not left
			var other = null
			for x in secs:
				if x != s:
					other = x
					break
			if left == right:
				on_right = pip(ring_of(doc, other), m.x + nrm.x, m.y + nrm.y) if other != null else right
			var start: int = l.a if on_right else l.b
			var end: int = l.b if on_right else l.a
			var sides: Dictionary = o.get("sides", {})
			var sd: Dictionary = sides.get(str(s.id), {})
			var h := 0.0
			var tx := ""
			# the face's SKIN (its side's `tex`, the line's), else the room's
			# walls; a middle standing in a two-sided opening is its own
			if other == null:
				h = num(s.get("ceil"), 256) - num(s.get("floor"), 0)
				tx = _first([tex(sd, "tex"), tex(sd, "midTex"), tex(o, "tex"), tex(o, "wallTex"), tex(s, "wallTex")])
			elif _inside(s) != _inside(other) and not o.get("opening", false):
				var inn: Dictionary = s if _inside(s) else other
				h = num(inn.get("ceil"), 256) - num(inn.get("floor"), 0)
				tx = _first([tex(sd, "tex"), tex(sd, "midTex"), tex(o, "tex"), tex(o, "midTex"), tex(inn, "wallTex")])
			else:
				var lower := num(other.get("floor"), 0) - num(s.get("floor"), 0)
				var upper := num(s.get("ceil"), 256) - num(other.get("ceil"), 256)
				if tex(sd, "midTex") != "" or tex(o, "midTex") != "":
					h = minf(num(s.get("ceil"), 256), num(other.get("ceil"), 256)) - maxf(num(s.get("floor"), 0), num(other.get("floor"), 0))
					tx = _first([tex(sd, "midTex"), tex(o, "midTex")])
				elif lower >= upper:
					h = lower
					tx = _first([tex(sd, "tex"), tex(sd, "lowerTex"), tex(o, "tex"), tex(o, "lowerTex"), tex(s, "lowerTex"), tex(s, "wallTex")])
				else:
					h = upper
					tx = _first([tex(sd, "tex"), tex(sd, "upperTex"), tex(o, "tex"), tex(o, "upperTex"), tex(s, "upperTex"), tex(s, "wallTex")])
			out.append({"key": key, "sec": s.id, "start": start, "end": end, "len": len, "h": maxf(0.0, h),
				"tex": tx if tx != "" else "GRIDWALL",
				"xoff": num(got(sd, "xoff", o.get("xoff")), 0), "yoff": num(got(sd, "yoff", o.get("yoff")), 0),
				"xscale": num(got(sd, "xscale", o.get("xscale")), 1), "yscale": num(got(sd, "yscale", o.get("yscale")), 1)})
	return out

static func _first(a: Array) -> String:
	for v in a:
		if v != "":
			return v
	return ""

static func _inside(s) -> bool:
	return s != null and tex(s, "ceilTex") != "" and tex(s, "ceilTex") != "SKY"

## The faces in runs, each face's end the next one's start.
static func face_runs(faces: Array) -> Array:
	var from := {}
	for f in faces:
		if not from.has(f.start):
			from[f.start] = []
		from[f.start].append(f)
	var used := {}
	var runs := []
	var nxt := func(f: Dictionary):
		var c: Array = []
		for g in from.get(f.end, []):
			if not used.has(g) and g.key != f.key:
				c.append(g)
		for g in c:
			if g.sec == f.sec:
				return g
		return c[0] if not c.is_empty() else null
	var walk := func(f0):
		var run := []
		var f = f0
		while f != null and not used.has(f):
			used[f] = true
			run.append(f)
			f = nxt.call(f)
		runs.append(run)
	for f in faces:
		if used.has(f):
			continue
		var has_before := false
		for g in faces:
			if g != f and g.end == f.start and g.sec == f.sec:
				has_before = true
				break
		if not has_before:
			walk.call(f)
	for f in faces:
		if not used.has(f):
			walk.call(f)
	return runs

## Line the textures of these lines up, in place (inside an edit):
## x | y | match | fitX | fitY | scale | reset. `size` is a Callable
## name -> Vector2 (world size) or Vector2.ZERO. Returns faces changed.
static func align_textures(doc: Dictionary, keys: Array, how: String, size: Callable, opts := {}) -> int:
	var faces := faces_of(doc, keys)
	if faces.is_empty():
		return 0
	var put := func(f: Dictionary, fields: Dictionary) -> void:
		if not doc.lines.has(f.key):
			doc.lines[f.key] = {}
		var o: Dictionary = doc.lines[f.key]
		if not o.has("sides"):
			o["sides"] = {}
		var sk := str(f.sec)
		if not o.sides.has(sk):
			o.sides[sk] = {}
		var sd: Dictionary = o.sides[sk]
		for k in fields:
			var v = fields[k]
			var dflt := 1.0 if k.ends_with("scale") else 0.0
			if v == null or absf(float(v) - dflt) < 1e-6:
				sd.erase(k)
			else:
				sd[k] = v
			f[k] = dflt if v == null else v
		if sd.is_empty():
			o.sides.erase(sk)
		if o.sides.is_empty():
			o.erase("sides")
		for k in ["xoff", "yoff", "xscale", "yscale"]:
			o.erase(k)
		if o.is_empty():
			doc.lines.erase(f.key)
	var W := func(f: Dictionary) -> float:
		var sz: Vector2 = size.call(f.tex)
		return (sz.x if sz.x > 0 else 64.0) * (f.xscale if f.xscale else 1.0)
	var Hh := func(f: Dictionary) -> float:
		var sz: Vector2 = size.call(f.tex)
		return sz.y if sz.y > 0 else 64.0
	var rnd := func(v: float) -> float: return jsround(v * 1000.0) / 1000.0
	var align_x := func() -> void:
		for run in face_runs(faces):
			var u: float = run[0].xoff
			for f in run:
				var w: float = W.call(f)
				put.call(f, {"xoff": rnd.call(fposmod(u, w))})
				u = f.xoff + f.len
	var first: Dictionary = faces[0]
	match how:
		"x":
			align_x.call()
		"y":
			var y0: float = first.yoff
			for f in faces:
				put.call(f, {"yoff": y0})
		"match":
			var m := {"xscale": first.xscale, "yscale": first.yscale, "yoff": first.yoff}
			for f in faces:
				put.call(f, m.duplicate())
			align_x.call()
		"fitX":
			for run in face_runs(faces):
				var L := 0.0
				for f in run:
					L += f.len
				var sz: Vector2 = size.call(run[0].tex)
				var tw := sz.x if sz.x > 0 else 64.0
				var n := maxf(1.0, jsround(L / tw))
				for f in run:
					put.call(f, {"xscale": rnd.call(L / (n * tw)), "xoff": 0})
			align_x.call()
		"fitY":
			for f in faces:
				if not (f.h > 0):
					continue
				var hh: float = Hh.call(f)
				var n := maxf(1.0, jsround(f.h / hh))
				put.call(f, {"yscale": rnd.call(f.h / (n * hh)), "yoff": 0})
		"scale":
			for f in faces:
				put.call(f, {"xscale": opts.get("xscale", f.xscale), "yscale": opts.get("yscale", f.yscale)})
			align_x.call()
		"reset":
			for f in faces:
				put.call(f, {"xoff": 0, "yoff": 0, "xscale": 1, "yscale": 1})
	return faces.size()

# ---------------------------------------------------------------------
# SAVING AND LOADING — the web build's JSON, key for key
# ---------------------------------------------------------------------

## A value as JSON wants it: whole numbers as integers (so 256 is 256,
## not 256.0), vertices as [x, y] on three places at most.
static func _plain(v):
	if v is Vector2:
		return [_n(v.x), _n(v.y)]
	if v is float:
		return _n(v)
	if v is Dictionary:
		var o := {}
		for k in v:
			o[str(k)] = _plain(v[k])
		return o
	if v is Array:
		var a := []
		for x in v:
			a.append(_plain(x))
		return a
	if v is PackedVector2Array:
		var a := []
		for x in v:
			a.append(_plain(x))
		return a
	if v is Color:
		return "#" + v.to_html(false)
	return v

static func _n(f: float):
	if is_nan(f) or is_inf(f):
		return 0
	if absf(f) < 9.0e15 and f == floorf(f):
		return int(f)
	# at most as precise as a double prints, and a vertex on a diagonal
	# kept to the thousandth it was put on
	return f

static func _plain_doc(doc: Dictionary) -> Dictionary:
	var o: Dictionary = _plain(doc)
	# a vertex is stored to three places, as the web build tidies them
	o.vertices = _v3(doc.vertices)
	if doc.get("layers") is Dictionary:
		for k in doc.layers:
			var g = doc.layers[k]
			if g is Dictionary and g.has("vertices"):
				o.layers[str(k)].vertices = _v3(g.vertices)
	return o

static func _v3(vs: Array) -> Array:
	var a := []
	for v in vs:
		var p: Vector2 = v
		a.append([_n(jsround(float(p.x) * 1000.0) / 1000.0), _n(jsround(float(p.y) * 1000.0) / 1000.0)])
	return a

## The document as a file: JSON with the format named (serialise).
static func to_json(doc: Dictionary, indent := " ") -> String:
	return JSON.stringify(_plain_doc(doc), indent, false, true)

## And back (parseDoc). Returns {doc} or {error}.
static func parse(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"error": "not JSON: %s (line %d)" % [j.get_error_message(), j.get_error_line()]}
	var d = j.data
	if not d is Dictionary or d.get("format") != DOC_FORMAT:
		return {"error": "not a gss-map file"}
	if not d.get("vertices") is Array or not d.get("sectors") is Array:
		return {"error": "the file has no vertices or sectors"}
	return {"doc": normalise(d)}

## A document as the editor keeps it: vertices as Vector2, indices and
## ids as integers, every list there — from a file or from a map
## generator (the maps write Vector2 already).
static func normalise(d: Dictionary) -> Dictionary:
	d["vertices"] = _vecs(d.get("vertices", []))
	for k in ["lines"]:
		if not d.get(k) is Dictionary:
			d[k] = {}
	for k in ["linedefs", "things", "props", "scatters", "textures"]:
		if not d.get(k) is Array:
			d[k] = []
	_ints_geom(d)
	if d.get("layers") is Dictionary:
		var L := {}
		for k in d.layers:
			var g = d.layers[k]
			if not g is Dictionary:
				continue
			var gg := {"vertices": _vecs(g.get("vertices", [])), "sectors": g.get("sectors", []) if g.get("sectors") is Array else [],
				"lines": g.get("lines", {}) if g.get("lines") is Dictionary else {}, "linedefs": g.get("linedefs", []) if g.get("linedefs") is Array else []}
			_ints_geom(gg)
			L[str(int(float(k)))] = gg
		d["layers"] = L
		if L.is_empty():
			d.erase("layers")
	if d.has("layer"):
		d["layer"] = int(num(d.layer, 0))
		if d.layer == 0:
			d.erase("layer")
	for t in d.things:
		if t.has("id"):
			t["id"] = int(num(t.id))
		if t.has("layer"):
			t["layer"] = int(num(t.layer))
		if t.has("variant") and t.variant != null:
			t["variant"] = int(num(t.variant))
		t["x"] = num(t.get("x"))
		t["y"] = num(t.get("y"))
	for p in d.props:
		p["id"] = int(num(p.get("id")))
	for c in d.scatters:
		c["id"] = int(num(c.get("id")))
		if c.has("seed"):
			c["seed"] = int(num(c.seed))
		var a = c.get("area")
		if a is Dictionary and a.get("ids") is Array:
			var ids := []
			for i in a.ids:
				ids.append(int(num(i)))
			a["ids"] = ids
	var w := default_world()
	if d.get("world") is Dictionary:
		w.merge(d.world, true)
	d["world"] = w
	var top := 1
	var all: Array = d.sectors + d.things + d.props + d.scatters
	if d.get("layers") is Dictionary:
		for k in d.layers:
			all += d.layers[k].sectors
	for x in all:
		top = maxi(top, int(num(x.get("id"), 0)) + 1)
	d["nextId"] = maxi(int(num(d.get("nextId"), 0)), top)
	if not d.has("format"):
		d["format"] = DOC_FORMAT
	if not d.has("version"):
		d["version"] = DOC_VERSION
	return d

static func _vecs(a) -> Array:
	var out := []
	if not a is Array:
		return out
	for v in a:
		if v is Vector2:
			out.append(v)
		elif v is Array and v.size() >= 2:
			out.append(Vector2(num(v[0]), num(v[1])))
		else:
			out.append(Vector2.ZERO)
	return out

static func _ints_geom(g: Dictionary) -> void:
	for s in g.sectors:
		var vs := []
		for v in s.get("verts", []):
			vs.append(int(num(v)))
		s["verts"] = vs
		s["id"] = int(num(s.get("id")))
	var ld := []
	for e in g.get("linedefs", []):
		if e is Array and e.size() >= 2:
			ld.append([int(num(e[0])), int(num(e[1]))])
	g["linedefs"] = ld

## A deep copy that shares nothing with the original.
static func clone(doc: Dictionary) -> Dictionary:
	return doc.duplicate(true)

# ---------------------------------------------------------------------
# UNDO: whole snapshots, as the web build's History
# ---------------------------------------------------------------------
class History:
	var cap := 200
	var past: Array = []
	var future: Array = []
	var doc: Dictionary
	var saved := ""

	func _init(d: Dictionary, c := 200) -> void:
		doc = d
		cap = c
		saved = EdDoc.to_json(d, "")

	## Before an edit: remember the map as it is now.
	func push(label := "") -> void:
		past.append({"label": label, "doc": EdDoc.clone(doc)})
		if past.size() > cap:
			past.pop_front()
		future.clear()

	func undo():
		if past.is_empty():
			return null
		var s: Dictionary = past.pop_back()
		future.append({"label": s.label, "doc": doc})
		doc = s.doc
		return s.label if s.label != "" else "edit"

	func redo():
		if future.is_empty():
			return null
		var s: Dictionary = future.pop_back()
		past.append({"label": s.label, "doc": doc})
		doc = s.doc
		return s.label if s.label != "" else "edit"

	func dirty() -> bool:
		return EdDoc.to_json(doc, "") != saved

	func mark_saved() -> void:
		saved = EdDoc.to_json(doc, "")
