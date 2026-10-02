## MEWD — THE MAZE, the demo's world (js/maps/maze.js).
##
## A perfect maze carved by a depth-first walk, BRAIDED (an eighth of the
## inside walls knocked through) and cleared into a few PLAZAS; laid out
## as tiles, wall and cell alternating, a wall tile a hedge-high BLOCK
## on the ground and a floor tile the ground itself; runs of one kind
## merged into rectangles that tile the square exactly. Returned as a
## map document in blocks (BlockDoc, for BlockCompile), and one seed is
## the same maze as the web build's, generator for generator.
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
	# ---- THE DOCUMENT, IN BLOCKS: the ground is the path, every run of
	# hedge a block a hedge high (its top moss, its sides ivy), every
	# plaza a patch of concrete on the ground; the grid's world under it
	# (defaultWorld in js/editor/doc.js): nothing burns but people, nobody
	# comes, the cell fire is off
	var world := {"skybox": "BSKY2", "ambient": {"color": "#ffffff", "amount": 0.3}, "lightColor": "#fff6ea", "seed": seed,
		"noBurn": true, "noSquads": true, "noCellFire": true}
	var b := BlockDoc.new(NAME, {"tex": "DIRT_01", "light": 1.0}, world)
	var KIND := {
		0: {"h": HEDGE_H, "top": "MOSS_01", "side": "IVY1", "name": "hedge"},
		1: null,
		2: {"h": 0.0, "top": "CONC_4", "side": "CONC_4", "name": "plaza"},
	}
	b.tiles(func(tx: int, ty: int) -> int: return open[ty][tx], T, T, func(kk: int): return KIND[kk], MazeMap._edge)
	var d := b.out()

	# ---- THINGS
	var mid := func(i: int) -> float:
		return _edge(i) + (CELL if i % 2 else WALL) / 2.0
	var thing := func(type: String, x: float, y: float, extra := {}) -> void:
		var t := {"angle": rnd.next() * TAU}
		t.merge(extra, true)
		b.thing(type, x, y, t)
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
