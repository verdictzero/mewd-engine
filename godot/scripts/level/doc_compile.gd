## MEWD — a map document to a Level (compileDoc in js/editor/doc.js).
##
## A document is what the maps and the editor write: vertices, sectors
## as rings of vertex indices, and things. The one job here the builder
## cannot do by itself is the T-JUNCTION: a long edge of one sector
## with the corner of two smaller ones part-way along it. Doom's lines
## join sectors edge to edge, so every edge is split at every vertex
## that lies on it before it is handed over — otherwise the long edge
## and the two short ones are three lines that never meet, and the
## opening between the sectors is a wall.
class_name DocCompile

const EPS := 0.5
const GRID := 256.0

static func compile(doc: Dictionary) -> Level:
	var lv := Level.new()
	lv.name = doc.get("name", "")
	lv.world = doc.get("world", {})
	var vs: Array = doc.vertices
	# a coarse grid of the vertices, so each edge asks only its own cells
	var grid := {}
	for i in vs.size():
		var p: Vector2 = vs[i]
		var key := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	for sd in doc.sectors:
		var ring: Array = sd.verts
		var poly := PackedVector2Array()
		var n := ring.size()
		for k in n:
			var a: Vector2 = vs[ring[k]]
			var b: Vector2 = vs[ring[(k + 1) % n]]
			poly.append(a)
			for m in _between(vs, grid, a, b, ring[k], ring[(k + 1) % n]):
				poly.append(m)
		lv.add_sector(poly, sd)
	lv.things = doc.get("things", [])
	lv.finish()
	return lv

## The vertices strictly inside a->b, in order along it.
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
				found.append([t, p])
	found.sort_custom(func(x, y): return x[0] < y[0])
	return found.map(func(x): return x[1])
