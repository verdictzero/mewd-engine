## MEWD — JESSE, the PvP maze (js/maps/jesse.js).
##
## At the user's request: two FORTIFIABLE STAGING AREAS, one at each end,
## joined by a massive MULTITHREADED maze — dead ends, loops, turn-
## arounds, rooms — PROCEDURAL AND WILDLY DIFFERENT EVERY TIME.
##
## THE SAME FORMAT AS THE MAZE (maze.gd): a grid of tiles, a thin 64-unit
## wall line between every pair of 256-unit corridor cells, a wall tile
## raised to a hedge's height, runs of one kind merged into rectangles
## and those into a map document DocCompile builds.
##
## WILDLY DIFFERENT, because nothing about it is fixed but the idea:
##   THE SIZE      30–41 cells long, 18–26 across.
##   THE ZONES     two to five bands across its length, each carved by its
##                 OWN algorithm — the recursive backtracker, Prim's, a
##                 growing tree between the two, a binary tree, Kruskal's —
##                 with its own walls, its own ground, its own loops.
##   THE THREADS   several openings on every seam between bands, and
##                 braiding inside each band.
##   THE ROOMS     open squares, pillared halls and cloisters.
##   THE SYMMETRY  half the time point-symmetric, the fair map.
##
## THE BASES are always mirror images: a fort wall with two to four gates,
## low cover, a tower up steps, stock crates and fuel cans to fortify
## with, and SPAWN PADS listed in world.pvp.
##
## One seed is the same map as the web build's, call for call: the JS
## draws with Math.imul(s, 1664525), a 32-bit wrapped multiply, then
## >>> 0 — the low 32 bits of the true product, which is exactly what
## U.Rng's 64-bit multiply masked to 32 bits gives.
class_name JesseMap
extends RefCounted

const NAME := "JESSE"
const FORT_H := 120       # the fort wall: under a hedge, over a head
const COVER_H := 40       # cover: over a step (24), under an eye (49)
const TOWER_H := 96       # the tower's deck
const STEP := 24          # the most a step can be
const ALGOS := ["backtracker", "prim", "tree", "binary", "kruskal"]
const CELL := MazeMap.CELL
const WALL := MazeMap.WALL
const HEDGE_H := MazeMap.HEDGE_H
const SKY_H := MazeMap.SKY_H

const HEDGES := [
	{"wall": "IVY1", "top": "MOSS_01"}, {"wall": "IVY1", "top": "GRASS5"}, {"wall": "ROCK_01", "top": "ROCK_01"},
	{"wall": "CONC_7", "top": "CONC_7"}, {"wall": "CONC_3", "top": "MOSS_01"},
]
const GROUNDS := ["DIRT_01", "DIRT_02", "DIRT3", "GRASS5", "SIDEWLK1", "CONC_2", "CONC_1"]
const DIRS := [[1, 0], [-1, 0], [0, 1], [0, -1]]

## A seed for a new one each visit.
static func new_seed() -> int:
	return randi() & 0x7FFFFFFF

## Build JESSE for `seed`. Pure: one seed, one map. `opts` takes the JS's
## overrides: w, h, symmetric, zones, algo, rooms, baseW, baseH.
static func build(seed: int = 1, opts := {}) -> Dictionary:
	return JesseMap.new()._build(seed, opts)

# ---- the generator's state (the JS closure's locals) ----------------
var rng: U.Rng
var W := 0
var H := 0
var TX := 0
var TY := 0
var kinds: Array = []          # [{name, floor, floorTex, ...}]
var kind_ix := {}
var walkable := {}
var zones: Array = []
var t: Array = []              # the tiles, a kind index each

func _rnd() -> float:
	return rng.next()

func _ri(a: int, b: int) -> int:
	return a + int(rng.next() * (b - a + 1))

func _pick(a: Array):
	return a[int(rng.next() * a.size())]

func _shuffle(a: Array) -> Array:
	for i in range(a.size() - 1, 0, -1):
		var j := int(rng.next() * (i + 1))
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a

static func _opt(opts: Dictionary, key: String, fallback: Callable):
	var o = opts.get(key)
	return o if o != null else fallback.call()

# ---- THE KINDS of tile, as sector templates -------------------------
func _kind(name: String, props: Dictionary) -> int:
	if kind_ix.has(name):
		return kind_ix[name]
	var k := {"name": name}
	k.merge(props)
	kinds.append(k)
	kind_ix[name] = kinds.size() - 1
	return kinds.size() - 1

func _hedge_kind(h: Dictionary, hgt: int) -> int:
	return _kind("hedge:%s:%s:%d" % [h.wall, h.top, hgt],
		{"floor": hgt, "floorTex": h.top, "wallTex": h.wall, "lowerTex": h.wall, "upperTex": null})

func _path_kind(g: String) -> int:
	var k := _kind("path:" + g, {"floor": 0, "floorTex": g, "wallTex": "IVY1", "lowerTex": "IVY1", "upperTex": null})
	walkable[k] = true
	return k

func _zone_at(x: int) -> Dictionary:
	for z in zones:
		if x >= z.xa and x < z.xb:
			return z
	return zones[zones.size() - 1]

func _T(tx: int, ty: int) -> int:
	return t[ty * TX + tx]

func _set_t(tx: int, ty: int, k: int) -> void:
	t[ty * TX + tx] = k

func _open_cell(x: int, y: int) -> void:
	_set_t(2 * x + 1, 2 * y + 1, _zone_at(x).path)

func _carve(ax: int, ay: int, bx: int, by: int) -> void:
	_open_cell(ax, ay)
	_open_cell(bx, by)
	_set_t(ax + bx + 1, ay + by + 1, _zone_at(mini(ax, bx)).path)

func _mirror(tx: int, ty: int) -> Array:
	return [TX - 1 - tx, TY - 1 - ty]

static func _edge(i: int) -> int:
	return floori(i / 2.0) * (WALL + CELL) + (WALL if i % 2 else 0)

static func _mid(i: int) -> float:
	return _edge(i) + (CELL if i % 2 else WALL) / 2.0

## JS Math.round: halves go up, not away from zero
static func _jround(x: float) -> int:
	return floori(x + 0.5)

func _build(seed: int, opts: Dictionary) -> Dictionary:
	rng = U.Rng.new(seed)
	W = _opt(opts, "w", func(): return _ri(30, 41))
	H = _opt(opts, "h", func(): return _ri(18, 26))
	TX = 2 * W + 1
	TY = 2 * H + 1
	var symmetric: bool = _opt(opts, "symmetric", func(): return _rnd() < 0.5)

	# ---- THE ZONES: bands across the length, each its own maze -------
	var n_zones: int = _opt(opts, "zones", func(): return _ri(2, 5))
	var cuts := [0]
	for z in range(1, n_zones):
		cuts.append(_jround((W * z) / float(n_zones) + (_rnd() - 0.5) * (W / float(n_zones)) * 0.5))
	cuts.append(W)
	for z in n_zones:
		var hedge: Dictionary = _pick(HEDGES)
		var zone := {"xa": cuts[z], "xb": cuts[z + 1]}
		zone.algo = _opt(opts, "algo", func(): return _pick(ALGOS))
		zone.p = _rnd()
		zone.hedge = _hedge_kind(hedge, HEDGE_H + 64 if _ri(0, 3) == 0 else HEDGE_H)
		zone.path = _path_kind(_pick(GROUNDS))
		zone.braid = [0.02, 0.08, 0.15, 0.3][_ri(0, 3)]
		zones.append(zone)

	# the tiles, all wall to begin with, each its column's zone's wall
	t.resize(TX * TY)
	for ty in TY:
		for tx in TX:
			t[ty * TX + tx] = _zone_at(mini(W - 1, maxi(0, (tx - 1) >> 1))).hedge

	for z in zones:
		var xa: int = z.xa
		var xb: int = z.xb
		var in_z := func(x: int, y: int) -> bool: return x >= xa and x < xb and y >= 0 and y < H
		var zw := xb - xa
		if zw <= 0:
			continue
		if z.algo == "binary":
			# long straight runs along two sides, every cell hung off them
			var north := _rnd() < 0.5
			var east := _rnd() < 0.5
			for y in H:
				for x in range(xa, xb):
					var opts2 := []
					var ny := y - 1 if north else y + 1
					var ex := x + 1 if east else x - 1
					if in_z.call(x, ny):
						opts2.append([x, ny])
					if in_z.call(ex, y):
						opts2.append([ex, y])
					_open_cell(x, y)
					if opts2.size():
						var b: Array = _pick(opts2)
						_carve(x, y, b[0], b[1])
		elif z.algo == "kruskal":
			var id := PackedInt32Array()
			id.resize(zw * H)
			for i in id.size():
				id[i] = i
			var edges := []
			for y in H:
				for x in range(xa, xb):
					if in_z.call(x + 1, y):
						edges.append([x, y, x + 1, y])
					if in_z.call(x, y + 1):
						edges.append([x, y, x, y + 1])
			for e in _shuffle(edges):
				# find, with path halving (inline: a lambda would get a copy
				# of the packed array)
				var a: int = e[1] * zw + e[0] - xa
				while id[a] != a:
					id[a] = id[id[a]]
					a = id[a]
				var b: int = e[3] * zw + e[2] - xa
				while id[b] != b:
					id[b] = id[id[b]]
					b = id[b]
				if a != b:
					id[a] = b
					_carve(e[0], e[1], e[2], e[3])
		else:
			# the growing tree: always the newest is the backtracker, always
			# a random one is Prim's, and anything between is between
			var p: float = 1.0 if z.algo == "backtracker" else (0.0 if z.algo == "prim" else z.p)
			var seen := PackedByteArray()
			seen.resize(W * H)
			var sx := _ri(xa, xb - 1)
			var sy := _ri(0, H - 1)
			seen[sy * W + sx] = 1
			_open_cell(sx, sy)
			var list := [[sx, sy]]
			while list.size():
				var i: int = list.size() - 1 if _rnd() < p else int(_rnd() * list.size())
				var cx: int = list[i][0]
				var cy: int = list[i][1]
				var next := []
				for d in DIRS:
					var x: int = cx + d[0]
					var y: int = cy + d[1]
					if in_z.call(x, y) and not seen[y * W + x]:
						next.append([x, y])
				if next.is_empty():
					list.remove_at(i)
					continue
				var n: Array = _pick(next)
				seen[n[1] * W + n[0]] = 1
				_carve(cx, cy, n[0], n[1])
				list.append(n)
		# BRAIDED, by the zone's own share
		for y in H:
			for x in range(xa, xb):
				if in_z.call(x + 1, y) and _rnd() < z.braid:
					_carve(x, y, x + 1, y)
				if in_z.call(x, y + 1) and _rnd() < z.braid:
					_carve(x, y, x, y + 1)
	# THE THREADS between the zones: several openings on every seam
	for k in range(1, zones.size()):
		var x: int = zones[k].xa - 1
		if x < 0:
			continue
		var ys := _shuffle(range(H))
		ys = ys.slice(0, maxi(2, _ri(H >> 3, H >> 1)))
		for y in ys:
			_carve(x, y, x + 1, y)

	# ---- THE ROOMS ----------------------------------------------------
	var rooms := []
	var n_rooms: int = _opt(opts, "rooms", func(): return _ri(3, 11))
	var k := 0
	while k < n_rooms * 6 and rooms.size() < n_rooms:
		k += 1
		var w := _ri(2, 5)
		var h := _ri(2, 4)
		var x := _ri(3, W - w - 3)
		var y := _ri(0, H - h)
		var hit := false
		for r in rooms:
			if x < r.x + r.w + 1 and r.x < x + w + 1 and y < r.y + r.h + 1 and r.y < y + h + 1:
				hit = true
				break
		if hit:
			continue
		var style: String = _pick(["open", "open", "pillars", "cloister"])
		rooms.append({"x": x, "y": y, "w": w, "h": h, "style": style})
		var floor := _kind("room:" + str(_pick(["CONC_4", "CONC_5", "SIDEWLK1"])), {})
		var room: Dictionary = kinds[floor]
		if not room.get("floorTex"):
			room.merge({"floor": 0, "floorTex": str(room.name).substr(5), "wallTex": "IVY1", "lowerTex": "IVY1", "upperTex": null}, true)
		walkable[floor] = true
		for ty in range(2 * y + 1, 2 * (y + h - 1) + 2):
			for tx in range(2 * x + 1, 2 * (x + w - 1) + 2):
				var post := tx % 2 == 0 and ty % 2 == 0
				if style == "pillars" and post:
					continue      # the posts stay: a hall of pillars
				if style == "cloister" and w >= 3 and h >= 3 and \
						tx > 2 * x + 1 and tx < 2 * (x + w - 1) + 1 and ty > 2 * y + 1 and ty < 2 * (y + h - 1) + 1:
					continue
				_set_t(tx, ty, floor)

	# ---- POINT SYMMETRY, half the time ---------------------------------
	if symmetric:
		for ty in TY:
			for tx in range(W + 1, TX):
				_set_t(tx, ty, _T(TX - 1 - tx, TY - 1 - ty))
		for r in rooms.duplicate():
			if r.x + r.w <= W / 2.0:
				rooms.append({"x": W - r.x - r.w, "y": H - r.y - r.h, "w": r.w, "h": r.h, "style": r.style, "mirror": true})

	# ---- THE BASES: always mirror images -------------------------------
	var bw: int = _opt(opts, "baseW", func(): return _ri(5, 7))
	var bh: int = mini(H - 2, _opt(opts, "baseH", func(): return _ri(6, 9)))
	var by0 := _ri(1, H - bh - 1)
	var base_floor_a := _kind("base:A", {"floor": 0, "floorTex": "CONC_4", "wallTex": "METALP1", "lowerTex": "METALP1", "upperTex": null, "light": 1})
	var base_floor_b := _kind("base:B", {"floor": 0, "floorTex": "CONC_5", "wallTex": "CONC_7", "lowerTex": "CONC_7", "upperTex": null, "light": 1})
	var fort_a := _kind("fort:A", {"floor": FORT_H, "floorTex": "METALP1", "wallTex": "METALP1", "lowerTex": "METALP1", "upperTex": null})
	var fort_b := _kind("fort:B", {"floor": FORT_H, "floorTex": "CONC_7", "wallTex": "CONC_7", "lowerTex": "CONC_7", "upperTex": null})
	var cover_a := _kind("cover:A", {"floor": COVER_H, "floorTex": "CAUTSTR2", "wallTex": "CAUTSTR2", "lowerTex": "CAUTSTR2", "upperTex": null})
	var cover_b := _kind("cover:B", {"floor": COVER_H, "floorTex": "CAUTSTR2", "wallTex": "CAUTSTR2", "lowerTex": "CAUTSTR2", "upperTex": null})
	walkable[base_floor_a] = true
	walkable[base_floor_b] = true

	# the plan of base A in tile coordinates; B is it turned round
	var X0 := 0
	var X1 := 2 * bw
	var Y0 := 2 * by0
	var Y1 := 2 * (by0 + bh)
	var plan := []                          # [tx, ty, 'floor'|'fort'|'cover'|'gate'|'step:h']
	var at := {}
	for ty in range(Y0, Y1 + 1):
		for tx in range(X0, X1 + 1):
			var on_edge := tx == X0 or tx == X1 or ty == Y0 or ty == Y1
			var p := [tx, ty, "fort" if on_edge else "floor"]
			plan.append(p)
			at[Vector2i(tx, ty)] = p
	var mark := func(tx: int, ty: int, what: String) -> void:
		var p = at.get(Vector2i(tx, ty))
		if p != null:
			p[2] = what
	# THE GATES: on the side facing the maze, and maybe top and bottom
	var gates := []
	var gate_cells := _shuffle(range(bh))
	gate_cells = gate_cells.slice(0, _ri(1, 2))
	for gy in gate_cells:
		gates.append([X1, 2 * (by0 + gy) + 1])
	if by0 > 0 and _rnd() < 0.7:
		gates.append([2 * _ri(1, bw - 1) + 1, Y0])
	if by0 + bh < H and _rnd() < 0.7:
		gates.append([2 * _ri(1, bw - 1) + 1, Y1])
	for g in gates:
		mark.call(g[0], g[1], "gate")
	# COVER: short low walls on the yard's inner wall lines, in front of
	# the gates and scattered across the yard — the JS draws the count
	# afresh on every pass of its loop test, and so does this
	k = 0
	while k < _ri(4, 8):
		k += 1
		var vertical := _rnd() < 0.6
		if vertical:
			var tx := 2 * _ri(1, bw - 1)
			var ty := Y0 + 2 * _ri(0, bh - 2) + 1
			var run_len := _ri(1, 2)
			for j in run_len:
				mark.call(tx, ty + 2 * j, "cover")
				mark.call(tx, ty + 2 * j + 1, "cover")
		else:
			var tx := 2 * _ri(1, bw - 1) + 1
			var ty := Y0 + 2 * _ri(1, bh - 1)
			mark.call(tx, ty, "cover")
	# but never across a gate's mouth
	for g in gates:
		for dd in DIRS:
			var p = at.get(Vector2i(g[0] + dd[0], g[1] + dd[1]))
			if p != null and p[2] == "cover":
				p[2] = "floor"
	# THE TOWER, at the back of the yard, and the steps up to it
	var tower_y := Y0 + 2 * _ri(1, bh - 2) + 1
	var tower_x := 1
	mark.call(tower_x, tower_y, "step:%d" % TOWER_H)
	var stairs := []
	var sk := 1
	var sh := TOWER_H - STEP
	while sh > 0:
		mark.call(tower_x + sk, tower_y, "step:%d" % sh)
		stairs.append([tower_x + sk, tower_y, sh])
		sk += 1
		sh -= STEP
	# and nothing either side of the stair is cover, so it can be climbed
	for st in stairs:
		for dy in [-1, 1]:
			var p = at.get(Vector2i(st[0], st[1] + dy))
			if p != null and p[2] == "cover":
				p[2] = "floor"

	for p in plan:
		var A := [p[0], p[1]]
		var B := _mirror(p[0], p[1])
		var what: String = p[2]
		var ka := -1
		var kb := -1
		if what == "floor" or what == "gate":
			ka = base_floor_a
			kb = base_floor_b
		elif what == "fort":
			ka = fort_a
			kb = fort_b
		elif what == "cover":
			ka = cover_a
			kb = cover_b
		elif what.begins_with("step:"):
			var h := int(what.substr(5))
			ka = _step_kind("A", h)
			kb = _step_kind("B", h)
		_set_t(A[0], A[1], ka)
		_set_t(B[0], B[1], kb)
	# a gate must open onto something: the cell outside it is cleared
	for g in gates:
		var gx: int = g[0]
		var gy: int = g[1]
		var out := [gx + 1, gy] if gx == X1 else ([gx, gy - 1] if gy == Y0 else [gx, gy + 1])
		for o in [out, _mirror(out[0], out[1])]:
			if not walkable.has(_T(o[0], o[1])):
				_set_t(o[0], o[1], _zone_at(mini(W - 1, (o[0] - 1) >> 1)).path)
	for i in kinds.size():
		if str(kinds[i].name).begins_with("step:"):
			walkable[i] = true

	# ---- EVERYWHERE REACHABLE: knock through until one flood fills it --
	var hedge_kinds := {}
	for z in zones:
		hedge_kinds[z.hedge] = true
	var passable := func(kk: int) -> bool: return walkable.has(kk) or kk == cover_a or kk == cover_b
	var start := [2 * 1 + 1, 2 * (by0 + 1) + 1]
	var knocked := 0
	for _round in 400:
		var seen := PackedByteArray()
		seen.resize(TX * TY)
		var q := [start[1] * TX + start[0]]
		seen[q[0]] = 1
		while q.size():
			var i: int = q.pop_back()
			var x := i % TX
			var y := i / TX
			for d in DIRS:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= TX or ny >= TY:
					continue
				var j := ny * TX + nx
				if seen[j] or not passable.call(t[j]):
					continue
				seen[j] = 1
				q.append(j)
		# every hedge tile between a reached cell and an unreached one is
		# a candidate; open a few at random and flood again
		var cand := []
		for y in range(1, TY - 1):
			for x in range(1, TX - 1):
				var i := y * TX + x
				if not hedge_kinds.has(t[i]):
					continue
				for pr in [[i - 1, i + 1], [i - TX, i + TX]]:
					if passable.call(t[pr[0]]) and passable.call(t[pr[1]]) and seen[pr[0]] != seen[pr[1]]:
						cand.append(i)
						break
		if cand.is_empty():
			break
		_shuffle(cand)
		for i in cand.slice(0, maxi(1, cand.size() >> 3)):
			var x: int = i % TX
			t[i] = _zone_at(mini(W - 1, maxi(0, (x - 1) >> 1))).path
			knocked += 1

	# ---- THE DOCUMENT -------------------------------------------------
	# The JS document's every field, the ones DocCompile does not read yet
	# (lines keyed Vector2i(min, max) vertex indices, linedefs, textures,
	# props, scatters) kept in shape and empty, as the JS leaves them.
	var world := {
		"noBurn": true, "noSquads": true, "noCellFire": true,
		"sky": {"horizon": "#1d9a48", "mid": "#06301a", "zenith": "#000000", "ground": "#05180c", "midPow": 0.95},
		"skybox": "BSKY2", "ambient": {"color": "#ffffff", "amount": 0.3}, "lightColor": "#fff6ea",
		"seed": seed & 0xFFFFFFFF, "jesseSeed": seed & 0xFFFFFFFF,
	}
	var d := {
		"format": "gss-map", "version": 1, "name": NAME,
		"vertices": [], "sectors": [], "lines": {}, "linedefs": [], "things": [], "textures": [], "props": [], "scatters": [],
		"world": world, "nextId": 1,
	}
	var vmap := {}
	var verts: Array = d.vertices
	var runs := []
	for ty in TY:
		var tx := 0
		while tx < TX:
			var kk := _T(tx, ty)
			var e := tx
			while e + 1 < TX and _T(e + 1, ty) == kk:
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
		var rx0: int = r.x0
		var rx1: int = r.x1 + 1
		var ry0: int = r.y0
		var ry1: int = r.y1 + 1
		var ring := []
		for i in range(rx0, rx1):
			ring.append(_vert(verts, vmap, _edge(i), _edge(ry0)))
		for j in range(ry0, ry1):
			ring.append(_vert(verts, vmap, _edge(rx1), _edge(j)))
		for i in range(rx1, rx0, -1):
			ring.append(_vert(verts, vmap, _edge(i), _edge(ry1)))
		for j in range(ry1, ry0, -1):
			ring.append(_vert(verts, vmap, _edge(rx0), _edge(j)))
		# SECTOR_DEFAULTS, then the maze's outdoor sky, then the kind — its
		# name is the kind's, kept apart, as the JS drops it from the sector
		var sec := {
			"floor": 0, "ceil": SKY_H + 64, "floorTex": "LAWN2", "ceilTex": "SKY", "wallTex": "GRIDWALL",
			"upperTex": null, "lowerTex": null, "light": 1.0, "outdoor": true, "sky": 0, "name": "",
		}
		var kd: Dictionary = kinds[r.k]
		for key in kd:
			if key != "name":
				sec[key] = kd[key]
		sec.kind = kd.name
		sec.id = d.nextId
		d.nextId += 1
		sec.verts = ring
		d.sectors.append(sec)

	# ---- THINGS -------------------------------------------------------
	var things: Array = d.things
	var size := [_edge(TX), _edge(TY)]
	var spawns := [[], []]
	for flip in [false, true]:
		var team_ix := 1 if flip else 0
		# spawn pads down the back of the yard
		for yy in bh:
			var p := _place(5, 2 * (by0 + yy) + 1, flip)   # clear of the tower's stair
			spawns[team_ix].append([_jround(p.x), _jround(p.y)])
		# lamps in the yard's corners
		for c in [[1, Y0 + 1], [X1 - 1, Y0 + 1], [1, Y1 - 1], [X1 - 1, Y1 - 1]]:
			var p := _place(c[0], c[1], flip)
			_thing(d, "STREETLAMP", p.x, p.y)
		# THE STOCK TO FORTIFY WITH: crates by every gate, fuel cans at
		# the back
		for g in gates:
			var gx: int = g[0]
			var gy: int = g[1]
			var in_x := gx - 1 if gx == X1 else gx
			var in_y := gy + 1 if gy == Y0 else (gy - 1 if gy == Y1 else gy)
			for c in 2:
				var dx := (_rnd() - 0.5) * 120
				var dy := (_rnd() - 0.5) * 120
				var p := _place(in_x, in_y, flip, dx, dy)
				_thing(d, "CRATE", p.x, p.y)
		for c in 2:
			var ty := 2 * (by0 + _ri(0, bh - 1)) + 1
			var dx := (_rnd() - 0.5) * 100
			var dy := (_rnd() - 0.5) * 100
			var p := _place(5, ty, flip, dx, dy)
			_thing(d, "FUELCAN", p.x, p.y)
	# the single-player start: team A's first pad, facing the maze
	var sp: Array = spawns[0][mini(spawns[0].size() - 1, 1)]
	_thing(d, "START", sp[0], sp[1], {"angle": 0.0})
	# a lamp and some stock in every room
	for r in rooms:
		var x0 := _edge(2 * r.x + 1)
		var y0 := _edge(2 * r.y + 1)
		_thing(d, "STREETLAMP", x0 + 48, y0 + 48)
		if _rnd() < 0.5:
			var cx := x0 + CELL * 0.5 + _rnd() * 100
			_thing(d, "CRATE", cx, y0 + CELL * 0.5 + _rnd() * 100)
		if _rnd() < 0.3:
			_thing(d, "FUELCAN", x0 + CELL * 0.3 + _rnd() * 80, y0 + CELL * 0.7)

	var gates_a := []
	var gates_b := []
	for g in gates:
		gates_a.append([_mid(g[0]), _mid(g[1])])
		var m := _mirror(g[0], g[1])
		gates_b.append([_mid(m[0]), _mid(m[1])])
	world.pvp = {"teams": [
		{"name": "A", "spawns": spawns[0], "gates": gates_a},
		{"name": "B", "spawns": spawns[1], "gates": gates_b},
	]}
	# what it is, for the picture and the test
	var zone_info := []
	for z in zones:
		zone_info.append({"xa": z.xa, "xb": z.xb, "algo": z.algo, "braid": z.braid,
			"hedge": kinds[z.hedge].name, "path": kinds[z.path].name})
	var kind_names := []
	for kd in kinds:
		kind_names.append(kd.name)
	d.jesse = {
		"seed": seed & 0xFFFFFFFF, "W": W, "H": H, "TX": TX, "TY": TY, "symmetric": symmetric,
		"knocked": knocked, "size": size, "zones": zone_info, "rooms": rooms,
		"base": {"bw": bw, "bh": bh, "by0": by0, "gates": gates.size(), "tower": [tower_x, tower_y]},
		"tiles": PackedByteArray(t), "kinds": kind_names,
	}
	d["size"] = size
	return d

func _step_kind(team: String, h: int) -> int:
	return _kind("step:%s:%d" % [team, h], {"floor": h, "floorTex": "METALP1" if team == "A" else "CONC_7",
		"wallTex": "CAUTSTR2", "lowerTex": "CAUTSTR2", "upperTex": null})

static func _vert(verts: Array, vmap: Dictionary, x: int, y: int) -> int:
	var key := Vector2i(x, y)
	if vmap.has(key):
		return vmap[key]
	var i := verts.size()
	verts.append(Vector2(x, y))
	vmap[key] = i
	return i

## A tile of base A, or its mirror in base B, as a map point nudged by
## (dx, dy) — turned round with it for B.
func _place(tx: int, ty: int, flip: bool, dx := 0.0, dy := 0.0) -> Vector2:
	var x := tx
	var y := ty
	if flip:
		x = TX - 1 - tx
		y = TY - 1 - ty
	return Vector2(_mid(x) + (-dx if flip else dx), _mid(y) + (-dy if flip else dy))

## The angle is drawn before `extra` can replace it, as in the JS, so the
## START's fixed facing still spends its number.
func _thing(d: Dictionary, type: String, x: float, y: float, extra := {}) -> void:
	var th := {"id": d.nextId, "type": type, "x": _jround(x), "y": _jround(y), "angle": _rnd() * TAU}
	d.nextId += 1
	th.merge(extra, true)
	d.things.append(th)
