## MEWD — a map document IN BLOCKS, built in code (at the user's request
## every level the game plays is on the ground plane now, the maze, JESSE,
## THE SPRAWL and THE GRID as much as THE ANNEXE: "remake the rest of the
## levels as well").
##
## The generators' helper: welded vertices, a block from a ring of points
## or a rectangle, a line override, a thing, a scatter, the storeys over
## the ground (`on(k)`), and the TILE GRID the maze and JESSE are laid out
## on turned into blocks (runs of one kind merged into rectangles that
## tile the square exactly; the tiles of the ground's own kind left to
## the ground). The document is BlockCompile's ("mewd-blocks").
class_name BlockDoc

const WALL_T := 16.0

var d: Dictionary
var k := 0                      # the layer being drawn on
var _vmaps := {0: {}}
var _layers := {}

func _init(name: String, ground := {}, world = null) -> void:
	var g := BlockCompile.GROUND_DEFAULTS.duplicate()
	g.merge(ground, true)
	d = {"format": BlockCompile.FORMAT, "version": BlockCompile.VERSION, "name": name, "ground": g,
		"vertices": [], "blocks": [], "lines": {}, "things": [], "scatters": [], "textures": [],
		"world": DocCompile.default_world() if world == null else world, "nextId": 1}

func id() -> int:
	var i: int = d.nextId
	d.nextId = i + 1
	return i

## Draw on layer `k` from here (0 the ground; a storey over it otherwise).
func on(layer: int) -> BlockDoc:
	k = layer
	if layer != 0 and not _layers.has(str(layer)):
		_layers[str(layer)] = {"vertices": [], "blocks": [], "lines": {}}
		_vmaps[layer] = {}
	return self

func _g() -> Dictionary:
	return d if k == 0 else _layers[str(k)]

## A vertex on the current layer, welded to any within half a unit.
func v(x: float, y: float) -> int:
	var key := Vector2i(roundi(x * 2.0), roundi(y * 2.0))
	var vm: Dictionary = _vmaps[k]
	if vm.has(key):
		return vm[key]
	var V: Array = _g().vertices
	V.append(Vector2(x, y))
	vm[key] = V.size() - 1
	return V.size() - 1

## A block over a ring of points (any way round; made anticlockwise),
## with `props` over BlockCompile.BLOCK_DEFAULTS: h, base, top, side,
## under, light, air, name.
func block(pts: Array, props: Dictionary) -> Dictionary:
	var a := 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	if a < 0:
		pts = pts.duplicate()
		pts.reverse()
	var b: Dictionary = BlockCompile.BLOCK_DEFAULTS.duplicate()
	b.merge(props, true)
	b.id = id()
	var vs := []
	for p in pts:
		vs.append(v(p.x, p.y))
	b.verts = vs
	_g().blocks.append(b)
	return b

func rect(x0: float, y0: float, x1: float, y1: float, props: Dictionary) -> Dictionary:
	return block([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], props)

static func rect_pts(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]

static func ngon(cx: float, cy: float, r: float, n := 8, turn = null) -> Array:
	var tn: float = PI / n if turn == null else float(turn)
	var out := []
	for q in n:
		out.append(Vector2(floori(cx + r * cos(q * 2 * PI / n + tn) + 0.5), floori(cy + r * sin(q * 2 * PI / n + tn) + 0.5)))
	return out

## An override on the edge p–q of the current layer (merged over any).
func line(p: Vector2, q: Vector2, o: Dictionary) -> void:
	var key := DocCompile._line_key(v(p.x, p.y), v(q.x, q.y))
	var L: Dictionary = _g().lines
	var cur: Dictionary = L.get(key, {})
	cur.merge(o, true)
	L[key] = cur

func thing(type: String, x: float, y: float, extra := {}) -> Dictionary:
	var t := {"id": id(), "type": type, "x": floori(x + 0.5), "y": floori(y + 0.5), "angle": 0.0}
	t.merge(extra, true)
	d.things.append(t)
	return t

func scatter(area: Dictionary, items: Array, density: float, spacing: float, clump := 0.3, extra := {}) -> void:
	d.scatters.append({"id": id(), "name": extra.get("name", "spread"), "area": area, "items": items,
		"density": density, "spacing": spacing, "clump": clump, "seed": int(extra.get("seed", 1)),
		"scaleMin": extra.get("scaleMin", 1), "scaleMax": extra.get("scaleMax", 1)})

static func in_rect(x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"kind": "rect", "x0": x0, "y0": y0, "x1": x1, "y1": y1}

static func in_blocks(bs: Array) -> Dictionary:
	return {"kind": "blocks", "ids": bs.map(func(b): return b.id)}

static func items(pairs: Array) -> Array:
	var out := []
	for i in range(0, pairs.size(), 2):
		out.append({"type": pairs[i], "w": pairs[i + 1]})
	return out

## The document, its storeys in `layers`.
func out() -> Dictionary:
	if not _layers.is_empty():
		d["layers"] = _layers
	return d

# ------------------------------------------------------------------
# TILES: a grid of tile kinds as blocks
# ------------------------------------------------------------------

## Runs of one kind along each row, and runs the same across rows
## joined: rectangles [{k, x0, x1, y0, y1}] (tile indices, inclusive)
## that tile the grid exactly.
static func merge_tiles(tile: Callable, TX: int, TY: int) -> Array:
	var runs := []
	for ty in TY:
		var tx := 0
		while tx < TX:
			var kk: int = tile.call(tx, ty)
			var e := tx
			while e + 1 < TX and tile.call(e + 1, ty) == kk:
				e += 1
			runs.append({"k": kk, "x0": tx, "x1": e, "y0": ty, "y1": ty})
			tx = e + 1
	var by_row := {}
	var rects := []
	for r in runs:
		var above = null
		for q in by_row.get(r.y0 - 1, []):
			if q.k == r.k and q.x0 == r.x0 and q.x1 == r.x1:
				above = q
				break
		if not by_row.has(r.y0):
			by_row[r.y0] = []
		if above != null:
			above.y1 = r.y0
			by_row[r.y0].append(above)
		else:
			rects.append(r)
			by_row[r.y0].append(r)
	return rects

## Every rectangle of tiles as a block on the current layer: `kind(k)`
## gives the block's fields for tile kind k (h, top, side, light, name,
## air...), or null where the tiles are the bare ground. `edge(i)` is the
## map coordinate of tile edge i. Returns the blocks made, with each
## rectangle's tile bounds in "__tiles".
func tiles(tile: Callable, TX: int, TY: int, kind: Callable, edge: Callable) -> Array:
	var out := []
	for r in merge_tiles(tile, TX, TY):
		var props = kind.call(r.k)
		if props == null:
			continue
		var x0: float = edge.call(r.x0)
		var x1: float = edge.call(r.x1 + 1)
		var y0: float = edge.call(r.y0)
		var y1: float = edge.call(r.y1 + 1)
		var b := rect(x0, y0, x1, y1, props)
		b["__tiles"] = Rect2i(r.x0, r.y0, r.x1 - r.x0 + 1, r.y1 - r.y0 + 1)
		out.append(b)
	return out

# ------------------------------------------------------------------
# NESTED HEIGHTS: blocks drawn with an absolute `floor` (the height of
# their top, as a map in rooms had it) made relative to what they are
# drawn inside — THE SPRAWL's way, every piece a ring strictly inside
# its parent
# ------------------------------------------------------------------

## Every block on the ground layer carrying "floor" gets h = its floor
## less the floor of the smallest block round it (the ground's is 0),
## and the field dropped; a block with a `base` of its own is left as
## it is.
func relative_heights() -> void:
	var B: Array = d.blocks
	var V: Array = d.vertices
	var boxes := []
	var pts := []
	var areas := []
	var probes := []
	for b in B:
		var p := PackedVector2Array()
		for i in b.verts:
			p.append(V[i])
		pts.append(p)
		boxes.append(DocCompile._bbox(p))
		areas.append(absf(DocCompile.signed_area(p)))
		probes.append(BlockCompile.probe(p))
	var grid := DocCompile.BoxGrid.new(boxes)
	var parent := PackedInt32Array()
	parent.resize(B.size())
	for i in B.size():
		parent[i] = -1
		var at: Vector2 = probes[i]
		var ba := INF
		for j in grid.at(at):
			if j == i or areas[j] <= areas[i] or areas[j] >= ba:
				continue
			if (boxes[j] as Rect2).grow(0.01).has_point(at) and DocCompile.pip(pts[j], at.x, at.y):
				ba = areas[j]
				parent[i] = j
	var floor_of := func(i: int) -> float:
		if i < 0:
			return 0.0
		var b: Dictionary = B[i]
		if b.has("floor"):
			return float(b.floor)
		return float(b.h) + (float(b.base) if b.get("base") != null else 0.0)
	var rel := []
	for i in B.size():
		var b: Dictionary = B[i]
		if not b.has("floor"):
			continue
		var under: float = floor_of.call(parent[i])
		rel.append([b, float(b.floor) - under])
	for e in rel:
		e[0].h = e[1]
		e[0].erase("floor")
