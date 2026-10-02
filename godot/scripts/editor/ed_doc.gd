## MEWD Editor — the map as a document (the Godot build's own, since the
## editor stopped working the way Doom does; the compiler is
## godot/scripts/level/block_compile.gd).
##
## THE WORLD IS AN INFINITE GROUND PLANE, and a map is what stands on it:
## BLOCKS — rings of vertex indices pulled up to a HEIGHT, each with its
## SIDES, its TOP and (where it floats) its UNDERSIDE texture, and the
## light of the space under it — THINGS standing about, LINE overrides
## keyed by the vertex pair ("a,b", smaller first), SCATTERS, the map's
## own TEXTURES, its GROUND (texture and light) and its WORLD. A vertex
## two blocks share is one vertex: drag it and both move. A block drawn
## inside another stands on it; one drawn on a higher LAYER stands on
## whatever the layers under it put there; a block with a BASE of its
## own floats at it.
##
## IN MEMORY the vertices are Vector2; ON DISK they are [x, y], and the
## file is JSON, key for key the document ("mewd-blocks"). Undo is whole
## snapshots.
##
## Also here: the tidy after every edit (compact), the problem report
## (problems_of) and the LAYERS (the map in storeys).
class_name EdDoc

const DOC_FORMAT := "mewd-blocks"
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
	"GRAVESTONE": {"name": "Gravestone", "color": "#999", "radius": 14},
	"PLANT": {"name": "Plant", "color": "#5c5", "radius": 14},
}

const DEFAULT_GROUND := "LAWN2"
const DEFAULT_SKYBOX := "BSKY2"
## A new block: a storey high, concrete on top, the grid wall round it
## (BlockCompile.BLOCK_DEFAULTS is the compiler's copy of this)
const BLOCK_DEFAULTS := {
	"h": 128.0, "base": null, "top": "CONC_1", "side": "GRIDWALL", "under": null, "light": 0.72, "name": "",
}
## the ground of a new map: lawn, in full daylight
const GROUND_DEFAULTS := {"tex": DEFAULT_GROUND, "light": 0.9}
const NEW_MAP_AMBIENT := {"color": "#ffffff", "amount": 0.35}
## how thick the Room tool's walls are, and its roof
const WALL_T := 16.0
const SLAB_T := 16.0

const EPS := 0.5
## how near two vertices are the SAME vertex
const WELD := 0.49
const LAYER_PARTS := ["vertices", "blocks", "lines"]
const LAYER_MIN := -8
const LAYER_MAX := 32

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
		if int(i) >= 0 and int(i) < V.size():
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

## A copy of a block (or anything) with some keys gone.
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

## A block's height, base (null: on what is under it) and light.
static func h_of(b: Dictionary) -> float:
	return num(b.get("h"), 128.0)

static func base_of(b: Dictionary):
	var v = b.get("base")
	return null if v == null or (v is String and v == "") else num(v)

static func light_of(b: Dictionary) -> float:
	return clampf(num(b.get("light"), 0.72), 0.0, 1.0)

static func ground_of(doc: Dictionary) -> Dictionary:
	var g := GROUND_DEFAULTS.duplicate()
	if doc.get("ground") is Dictionary:
		g.merge(doc.ground, true)
	return g

# ---------------------------------------------------------------------
# THE DOCUMENT
# ---------------------------------------------------------------------

static func default_world() -> Dictionary:
	return DocCompile.default_world()

## A blank map: the ground plane under the sky, and a start on it.
static func new_doc(name := "UNTITLED") -> Dictionary:
	var world := default_world()
	world["skybox"] = DEFAULT_SKYBOX
	world["ambient"] = NEW_MAP_AMBIENT.duplicate()
	return {
		"format": DOC_FORMAT, "version": DOC_VERSION, "name": name,
		"ground": GROUND_DEFAULTS.duplicate(),
		"vertices": [],
		"blocks": [],
		"lines": {},
		"things": [{"id": 1, "type": "START", "x": 0.0, "y": 0.0, "angle": PI / 2.0}],
		"textures": [],
		"scatters": [],
		"world": world,
		"nextId": 2,
	}

static func take_id(doc: Dictionary) -> int:
	var id := int(doc.get("nextId", 1))
	doc["nextId"] = id + 1
	return id

## Every line of the document: each vertex pair round every block, with
## the blocks on it — a nested block's edge has the block it stands in
## too.
static func lines_of(doc: Dictionary, parents = null) -> Array:
	if parents == null:
		parents = hole_parents(doc)
	var map := {}
	var order := []
	var S: Array = doc.blocks
	for si in S.size():
		var r: Array = S[si].verts
		var n := r.size()
		for i in n:
			var a := int(r[i])
			var b := int(r[(i + 1) % n])
			var k := line_key(a, b)
			var l = map.get(k)
			if l == null:
				l = {"key": k, "a": mini(a, b), "b": maxi(a, b), "blocks": []}
				map[k] = l
				order.append(l)
			if not l.blocks.has(si):
				l.blocks.append(si)
	for l in order:
		if l.blocks.size() == 1 and parents[l.blocks[0]] >= 0:
			l.blocks.append(parents[l.blocks[0]])
	return order

## For each block, the index of the block it is drawn inside (the
## smallest it lies in), or -1.
static func hole_parents(doc: Dictionary) -> PackedInt32Array:
	var S: Array = doc.blocks
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
## degenerate blocks, renumber; line overrides follow.
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
	for s in doc.blocks:
		var vs: Array = []
		for v in s.verts:
			if int(v) >= 0 and int(v) < nv:
				vs.append(to[int(v)])
		var kept: Array = []
		for k in vs.size():
			if vs[k] != vs[(k + 1) % vs.size()]:
				kept.append(vs[k])
		s.verts = kept
	var S2: Array = []
	for s in doc.blocks:
		if s.verts.size() >= 3 and absf(signed_area(ring_of(doc, s))) > 0.25:
			S2.append(s)
	doc.blocks = S2
	var used := {}
	for s in doc.blocks:
		for v in s.verts:
			used[int(v)] = true
	var remap := {}
	var nvs: Array = []
	for i in nv:
		if used.has(i) and to[i] == i:
			remap[i] = nvs.size()
			nvs.append(V[i])
	for s in doc.blocks:
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
	doc.vertices = nvs
	doc.lines = lines
	return doc

# ---------------------------------------------------------------------
# PROBLEMS: what the compiler will refuse or quietly get wrong
# ---------------------------------------------------------------------

static func problems_of(doc: Dictionary) -> Array:
	var out := []
	var S: Array = doc.blocks
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
			out.append({"kind": "block", "id": s.id, "msg": "block %d has fewer than three corners" % s.id})
		elif self_crosses(r):
			out.append({"kind": "block", "id": s.id, "msg": "block %d crosses itself" % s.id})
	# two blocks whose edges cross (one drawn inside another, sharing a
	# side or part of one, is fine: it stands on it)
	for i in S.size():
		for j in range(i + 1, S.size()):
			if not _boxes_meet(boxes[i], boxes[j]):
				continue
			var a: PackedVector2Array = rings[i]
			var b: PackedVector2Array = rings[j]
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
			if crosses:
				out.append({"kind": "block", "id": S[i].id, "msg": "blocks %d and %d overlap" % [S[i].id, S[j].id]})
	var has_start := false
	for t in doc.things:
		if t.type == "START":
			has_start = true
			break
	if not has_start:
		out.append({"kind": "map", "msg": "there is no player start"})
	return out

# ---------------------------------------------------------------------
# LAYERS: the map in storeys. The layer being edited is where the map
# always was (doc.vertices, .blocks, .lines); the others wait in
# doc.layers[k].
# ---------------------------------------------------------------------

static func _empty_layer() -> Dictionary:
	return {"vertices": [], "blocks": [], "lines": {}}

static func layer_geom(doc: Dictionary, k = null) -> Dictionary:
	var cur := int(doc.get("layer", 0))
	var kk: int = cur if k == null else int(k)
	if kk == cur:
		return {"vertices": doc.vertices, "blocks": doc.blocks, "lines": doc.get("lines", {})}
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
		if g is Dictionary and not g.get("blocks", []).is_empty():
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
		if not g.blocks.is_empty():
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
	var out := {"vertices": doc.vertices, "blocks": doc.blocks, "lines": doc.get("lines", {})}
	if not out.blocks.is_empty():
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

## A storey's height, for a layer duplicated up the stack: how much
## higher its floating blocks go.
const STOREY_H := 128.0

## A layer's name: its own (doc.layerNames), or what it is.
static func layer_name(doc: Dictionary, k: int) -> String:
	var names = doc.get("layerNames")
	if names is Dictionary and names.get(str(k)) is String and names[str(k)] != "":
		return names[str(k)]
	if k == 0:
		return "Ground"
	return ("Storey %d" % k) if k > 0 else ("Basement %d" % -k)

static func set_layer_name(doc: Dictionary, k: int, name: String) -> void:
	name = name.strip_edges()
	if not doc.get("layerNames") is Dictionary:
		doc["layerNames"] = {}
	if name == "" or name == layer_name({}, k):
		doc.layerNames.erase(str(k))
	else:
		doc.layerNames[str(k)] = name
	if doc.layerNames.is_empty():
		doc.erase("layerNames")

static func layer_filled(doc: Dictionary, k: int) -> bool:
	return not layer_geom(doc, k).blocks.is_empty()

## fn(L) on the layers put away (doc.layers), every one of `ks` among
## them; `back` is the one being edited afterwards.
static func _stored(doc: Dictionary, ks: Array, back: int, fn: Callable) -> void:
	var tmp := LAYER_MAX
	while tmp in ks:
		tmp -= 1
	set_layer(doc, tmp)
	if not doc.get("layers") is Dictionary:
		doc["layers"] = {}
	fn.call(doc.layers)
	for k in doc.layers.keys():
		var g = doc.layers[k]
		if not g is Dictionary or g.get("blocks", []).is_empty():
			doc.layers.erase(k)
	set_layer(doc, back)
	if doc.get("layers") is Dictionary and doc.layers.is_empty():
		doc.erase("layers")

## The lowest base a layer's floating blocks stand at, or null when none
## of them float (a block standing on what is under it has no height of
## its own to keep).
static func _base_of(g) -> Variant:
	if not g is Dictionary:
		return null
	var lo = null
	for b in g.get("blocks", []):
		var f = base_of(b)
		if f == null:
			continue
		lo = float(f) if lo == null else minf(lo, float(f))
	return lo

static func _raise(g, dz: float) -> void:
	if not g is Dictionary or dz == 0.0:
		return
	for b in g.get("blocks", []):
		if base_of(b) != null:
			b["base"] = float(b.base) + dz

static func _thing_layer(t: Dictionary, k: int) -> void:
	if k == 0:
		t.erase("layer")
	else:
		t["layer"] = k

## Two layers change places in the stack: each takes the other's height
## (its floating blocks' lowest base where the other's was), its things
## and its name.
static func swap_layers(doc: Dictionary, a: int, b: int) -> void:
	if a == b or a < LAYER_MIN or b < LAYER_MIN or a > LAYER_MAX or b > LAYER_MAX:
		return
	var cur := int(doc.get("layer", 0))
	var back := b if cur == a else (a if cur == b else cur)
	_stored(doc, [a, b], back, func(L: Dictionary):
		var ga = L.get(str(a))
		var gb = L.get(str(b))
		var fa = _base_of(ga)
		var fb = _base_of(gb)
		var za: float = fb if fb != null else (float(b - a) * STOREY_H + (fa if fa != null else 0.0))
		var zb: float = fa if fa != null else (float(a - b) * STOREY_H + (fb if fb != null else 0.0))
		if fa != null:
			_raise(ga, za - fa)
		if fb != null:
			_raise(gb, zb - fb)
		L.erase(str(a))
		L.erase(str(b))
		if ga != null:
			L[str(b)] = ga
		if gb != null:
			L[str(a)] = gb)
	for t in doc.things:
		var k := int(num(t.get("layer"), 0))
		if k == a:
			_thing_layer(t, b)
		elif k == b:
			_thing_layer(t, a)
	var names = doc.get("layerNames")
	if names is Dictionary:
		var na = names.get(str(a))
		var nb = names.get(str(b))
		names.erase(str(a))
		names.erase(str(b))
		if na != null:
			names[str(b)] = na
		if nb != null:
			names[str(a)] = nb

## A layer and its things gone.
static func delete_layer(doc: Dictionary, k: int) -> void:
	if k == int(doc.get("layer", 0)):
		var e := _empty_layer()
		for p in LAYER_PARTS:
			doc[p] = e[p]
	elif doc.get("layers") is Dictionary:
		doc.layers.erase(str(k))
		if doc.layers.is_empty():
			doc.erase("layers")
	doc.things = doc.things.filter(func(t): return int(num(t.get("layer"), 0)) != k)
	if doc.get("layerNames") is Dictionary:
		doc.layerNames.erase(str(k))
		if doc.layerNames.is_empty():
			doc.erase("layerNames")

## A copy of layer k and its things on the first empty layer over it, its
## floating blocks a storey up for every layer it went (the rest stand on
## what the layers under put there); its number, or null if there is no
## room.
static func duplicate_layer(doc: Dictionary, k: int):
	var dst := k + 1
	while dst <= LAYER_MAX and layer_filled(doc, dst):
		dst += 1
	if dst > LAYER_MAX:
		return null
	var src := layer_geom(doc, k)
	var g := {}
	for p in LAYER_PARTS:
		g[p] = src[p].duplicate(true) if (src[p] is Array or src[p] is Dictionary) else src[p]
	_raise(g, float(dst - k) * STOREY_H)
	for b in g.blocks:
		b["id"] = take_id(doc)
	_stored(doc, [dst], int(doc.get("layer", 0)), func(L: Dictionary): L[str(dst)] = g)
	for t in doc.things.duplicate():
		if int(num(t.get("layer"), 0)) == k:
			var c: Dictionary = t.duplicate(true)
			c["id"] = take_id(doc)
			_thing_layer(c, dst)
			if THING_TYPES.get(c.type, {}).get("one", false):
				continue
			doc.things.append(c)
	set_layer_name(doc, dst, layer_name(doc, k) + " copy")
	return dst

## The document without some layers (the ones hidden in the layers
## pane): what the 3D view is built from.
static func without_layers(doc: Dictionary, hidden: Dictionary) -> Dictionary:
	var d := doc.duplicate()
	var cur := int(doc.get("layer", 0))
	if doc.get("layers") is Dictionary:
		var L := {}
		for k in doc.layers:
			if not hidden.has(int(k)):
				L[k] = doc.layers[k]
		d["layers"] = L
	if hidden.has(cur):
		var e := _empty_layer()
		for p in LAYER_PARTS:
			d[p] = e[p]
	d["things"] = doc.things.filter(func(t): return not hidden.has(int(num(t.get("layer"), 0))))
	return d

## The smallest block of geometry g round (x, y), or null.
static func block_in(g: Dictionary, x: float, y: float):
	var best = null
	var ba := INF
	for s in g.blocks:
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

# ---------------------------------------------------------------------
# FILES
# ---------------------------------------------------------------------

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
	return f

static func _plain_doc(doc: Dictionary) -> Dictionary:
	var o: Dictionary = _plain(doc)
	# a vertex is stored to three places
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

## The document as a file: JSON with the format named.
static func to_json(doc: Dictionary, indent := " ") -> String:
	return JSON.stringify(_plain_doc(doc), indent, false, true)

## And back. Returns {doc} or {error}.
static func parse(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return {"error": "not JSON: %s (line %d)" % [j.get_error_message(), j.get_error_line()]}
	var d = j.data
	if not d is Dictionary:
		return {"error": "not a map file"}
	if d.get("format") == "gss-map":
		return {"error": "a map of the old editor (rooms with floors and ceilings) — this editor builds in blocks on the ground, and does not read those"}
	if d.get("format") != DOC_FORMAT:
		return {"error": "not a %s file" % DOC_FORMAT}
	if not d.get("vertices") is Array or not d.get("blocks") is Array:
		return {"error": "the file has no vertices or blocks"}
	return {"doc": normalise(d)}

## A document as the editor keeps it: vertices as Vector2, indices and
## ids as integers, numbers as numbers, every list there — from a file
## or from a map generator (the maps write Vector2 already).
static func normalise(d: Dictionary) -> Dictionary:
	d["vertices"] = _vecs(d.get("vertices", []))
	for k in ["lines"]:
		if not d.get(k) is Dictionary:
			d[k] = {}
	for k in ["blocks", "things", "scatters", "textures"]:
		if not d.get(k) is Array:
			d[k] = []
	d.erase("linedefs")
	d.erase("props")
	_ints_geom(d)
	d["ground"] = ground_of(d)
	d.ground["light"] = clampf(num(d.ground.get("light"), 0.9), 0.0, 1.0)
	if d.get("layers") is Dictionary:
		var L := {}
		for k in d.layers:
			var g = d.layers[k]
			if not g is Dictionary:
				continue
			var gg := {"vertices": _vecs(g.get("vertices", [])), "blocks": g.get("blocks", []) if g.get("blocks") is Array else [],
				"lines": g.get("lines", {}) if g.get("lines") is Dictionary else {}}
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
	var all: Array = d.blocks + d.things + d.scatters
	if d.get("layers") is Dictionary:
		for k in d.layers:
			all += d.layers[k].blocks
	for x in all:
		top = maxi(top, int(num(x.get("id"), 0)) + 1)
	d["nextId"] = maxi(int(num(d.get("nextId"), 0)), top)
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
	for s in g.blocks:
		var vs := []
		for v in s.get("verts", []):
			vs.append(int(num(v)))
		s["verts"] = vs
		s["id"] = int(num(s.get("id")))
		s["h"] = num(s.get("h"), 128.0)
		s["base"] = base_of(s)
		s["light"] = light_of(s)
		for k in ["floor", "ceil", "floorTex", "ceilTex", "wallTex", "upperTex", "lowerTex", "outdoor", "sky", "colors", "fog", "lightColor", "storeys", "roofTex"]:
			s.erase(k)

## A deep copy that shares nothing with the original.
static func clone(doc: Dictionary) -> Dictionary:
	return doc.duplicate(true)

# ---------------------------------------------------------------------
# UNDO: whole snapshots
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
