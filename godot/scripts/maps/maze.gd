## MEWD — THE MAZE, the demo's world (js/maps/maze.js).
##
## A perfect maze carved by a depth-first walk, BRAIDED (an eighth of the
## inside walls knocked through) and cleared into a few PLAZAS; laid out
## as tiles, wall and cell alternating, a wall tile a hedge-high sector
## and a floor tile ground; runs of one kind merged into rectangles that
## tile the square exactly. Returned as a map document for DocCompile —
## the same shape the JS editor writes — and one seed is the same maze
## as the web build's, generator for generator.
class_name MazeMap

const NAME := "THE MAZE"
const CELLS := 18
const CELL := 256
const WALL := 64
const HEDGE_H := 192
const SKY_H := 320
const PEOPLE := 520

static func new_seed() -> int:
	return randi() & 0x7FFFFFFF

static func _edge(i: int) -> int:
	return (i / 2) * (WALL + CELL) + (WALL if i % 2 else 0)

static func build(seed: int = 1, cells: int = CELLS, people: int = PEOPLE) -> Dictionary:
	var rnd := U.Rng.new(seed)
	var N := cells
	var T := 2 * N + 1

	# ---- THE CARVING: a depth-first walk
	var open := []
	for y in T:
		var row := PackedByteArray()
		row.resize(T)
		open.append(row)
	var seen := []
	for y in N:
		var row := PackedByteArray()
		row.resize(N)
		seen.append(row)
	var stack := [[int(rnd.next() * N), int(rnd.next() * N)]]
	seen[stack[0][1]][stack[0][0]] = 1
	open[2 * stack[0][1] + 1][2 * stack[0][0] + 1] = 1
	var dirs := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	while stack.size():
		var top: Array = stack[stack.size() - 1]
		var cx: int = top[0]
		var cy: int = top[1]
		var nexts := []
		for d in dirs:
			var x: int = cx + d[0]
			var y: int = cy + d[1]
			if x >= 0 and y >= 0 and x < N and y < N and not seen[y][x]:
				nexts.append([x, y, d[0], d[1]])
		if nexts.is_empty():
			stack.pop_back()
			continue
		var n: Array = nexts[int(rnd.next() * nexts.size())]
		seen[n[1]][n[0]] = 1
		open[2 * cy + 1 + n[3]][2 * cx + 1 + n[2]] = 1
		open[2 * n[1] + 1][2 * n[0] + 1] = 1
		stack.append([n[0], n[1]])
	# BRAIDED
	for ty in range(1, T - 1):
		for tx in range(1, T - 1):
			if open[ty][tx]:
				continue
			var horiz := ty % 2 == 1 and tx % 2 == 0
			var vert := ty % 2 == 0 and tx % 2 == 1
			if (horiz or vert) and rnd.next() < 0.12:
				open[ty][tx] = 1
	# PLAZAS
	var plazas := []
	var n_plaza := maxi(2, roundi(N * N / 70.0))
	var k := 0
	while k < n_plaza * 8 and plazas.size() < n_plaza:
		k += 1
		var px := 1 + int(rnd.next() * (N - 4))
		var py := 1 + int(rnd.next() * (N - 4))
		var near := false
		for p in plazas:
			if absi(p[0] - px) < 5 and absi(p[1] - py) < 5:
				near = true
		if near:
			continue
		plazas.append([px, py])
		for ty in range(2 * py + 1, 2 * (py + 2) + 2):
			for tx in range(2 * px + 1, 2 * (px + 2) + 2):
				open[ty][tx] = 2

	var size := _edge(T)
	var d := {
		"name": NAME, "vertices": [], "sectors": [], "lines": {}, "things": [],
		# the grid's world under it (defaultWorld in js/editor/doc.js):
		# nothing burns but people, nobody comes, the cell fire is off
		"world": {"skybox": "BSKY2", "ambient": {"color": "#ffffff", "amount": 0.3}, "lightColor": "#fff6ea", "seed": seed,
			"noBurn": true, "noSquads": true, "noCellFire": true},
	}
	var vmap := {}
	var verts: Array = d.vertices
	var v := func(x: int, y: int) -> int:
		var key := Vector2i(x, y)
		if vmap.has(key):
			return vmap[key]
		var i := verts.size()
		verts.append(Vector2(x, y))
		vmap[key] = i
		return i
	var KIND := {
		0: {"name": "hedge", "floor": HEDGE_H, "floorTex": "MOSS_01"},
		1: {"name": "path", "floor": 0, "floorTex": "DIRT_01"},
		2: {"name": "plaza", "floor": 0, "floorTex": "CONC_4"},
	}
	# runs along each row, then runs the same across rows joined
	var runs := []
	for ty in T:
		var tx := 0
		while tx < T:
			var kk: int = open[ty][tx]
			var e := tx
			while e + 1 < T and open[ty][e + 1] == kk:
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
	for r in rects:
		var X0: int = r.x0
		var X1: int = r.x1 + 1
		var Y0: int = r.y0
		var Y1: int = r.y1 + 1
		var ring := []
		for i in range(X0, X1):
			ring.append(v.call(_edge(i), _edge(Y0)))
		for j in range(Y0, Y1):
			ring.append(v.call(_edge(X1), _edge(j)))
		for i in range(X1, X0, -1):
			ring.append(v.call(_edge(i), _edge(Y1)))
		for j in range(Y1, Y0, -1):
			ring.append(v.call(_edge(X0), _edge(j)))
		var kind: Dictionary = KIND[r.k]
		d.sectors.append({
			"verts": ring, "name": kind.name, "floor": kind.floor, "ceil": SKY_H,
			"floorTex": kind.floorTex, "ceilTex": "SKY", "wallTex": "IVY1", "lowerTex": "IVY1", "upperTex": null,
			"light": 1.0, "outdoor": true,
		})

	# ---- THINGS
	var mid := func(i: int) -> float:
		return _edge(i) + (CELL if i % 2 else WALL) / 2.0
	var things: Array = d.things
	var thing := func(type: String, x: float, y: float, extra := {}) -> void:
		var t := {"type": type, "x": roundi(x), "y": roundi(y), "angle": rnd.next() * TAU}
		t.merge(extra, true)
		things.append(t)
	thing.call("START", mid.call(1), mid.call(1), {"angle": PI / 4})
	var TREES := ["fir_tall_1", "savanna_tree_1", "wasteland_tree", "pine_juvenile_fir_tree_1"]
	for p in plazas:
		var x0 := _edge(2 * p[0] + 1)
		var y0 := _edge(2 * p[1] + 1)
		var x1 := _edge(2 * (p[0] + 2) + 2)
		var y1 := _edge(2 * (p[1] + 2) + 2)
		for c in [[x0 + 48, y0 + 48], [x1 - 48, y0 + 48], [x0 + 48, y1 - 48], [x1 - 48, y1 - 48]]:
			thing.call("STREETLAMP", c[0], c[1])
		thing.call("PLANT", (x0 + x1) / 2.0, (y0 + y1) / 2.0, {"kind": TREES[int(rnd.next() * TREES.size())], "scale": 1})
	# THE CROWD
	var floor_tiles := []
	for ty in T:
		for tx in T:
			if open[ty][tx]:
				floor_tiles.append(Vector2i(tx, ty))
	var sx: float = mid.call(1)
	var taken := [Vector2(sx, sx)]
	var n := 0
	k = 0
	while n < people and k < people * 20:
		k += 1
		var t: Vector2i = floor_tiles[int(rnd.next() * floor_tiles.size())]
		var w := CELL if t.x % 2 else WALL
		var h := CELL if t.y % 2 else WALL
		var x := _edge(t.x) + 20 + rnd.next() * (w - 40)
		var y := _edge(t.y) + 20 + rnd.next() * (h - 40)
		if w < 40 or h < 40:
			continue
		var clear := (x - sx) * (x - sx) + (y - sx) * (y - sx) > 200 * 200
		if clear:
			for q in taken:
				if (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y) <= 40 * 40:
					clear = false
					break
		if not clear:
			continue
		taken.append(Vector2(x, y))
		var type := "TOWNIE" if rnd.next() < 0.55 else "SHOPPER"
		thing.call(type, x, y, {"variant": int(rnd.next() * 17)})
		n += 1
	d["size"] = size
	return d
