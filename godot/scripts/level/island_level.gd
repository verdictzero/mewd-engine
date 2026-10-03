## MEWD — THE LEVEL ON AN ISLAND, at the user's request: golf's
## procedural island (godot/island/) for the ground, and everything the
## game asks a level — where the floor is, whether a body may move, what
## an eye can see, where a round stops — answered off its height grid
## (IslandGround) instead of off sectors and lines.
##
## The game never knew it was asking sectors anything but "how high is
## the floor here", so this IS a Level: every point on the island is a
## sector of its own, open to the sky, its floor the ground under it and
## its ceiling far overhead. There are no lines and no walls. What stops
## a mover is the ground itself — a rise of more than a step (a cliff, a
## crag) or the coast, past which there is nothing but cloud — and what
## stops a ray or an eye is a hill in the way.
##
## UNITS: the game counts 32 to the metre (U), the island counts metres,
## and the game's (x, y) is the island's (x, -z): see `floor_at`.
class_name IslandLevel
extends Level

const U_PER_M := 32.0
## where there is no floor (off the coast), in the game's units
const NO_FLOOR := -1.0e9
## the sky over every point: far over anything that flies
const SKY_OVER := 1.0e6
## how far apart an eye's look is checked against the ground (3 m): a
## hill hides what is behind it, a hummock does not
const SIGHT_STEP := 96.0
## and a round's flight (1 m), then halved down to a few centimetres
const RAY_STEP := 32.0
## how far inland of the coast a body keeps (the cliff's lip, 2 m)
const COAST_MARGIN := 64.0

var ground: IslandGround
## the sector every point is a copy of
var _proto: Sector
## THE HOUSES (CANDY LAND's gingerbread houses, Islands "houses";
## place_houses): {i, x, y, angle, z, scale, hw, back, front, top, rad,
## lines} in the game's units, the door on the side `angle` faces. They
## are walls where there are none else: they stop a body, an eye and a
## round (can_move, sight_blocked, ray_hit_wall).
var houses: Array = []
## each house under every HOUSE_CELL square its circle (and a body's
## reach round it) touches, so a short look asks only the ones near
var _house_cells := {}
const HOUSE_CELL := 1024.0

func _init(g: IslandGround, title := "ISLAND") -> void:
	ground = g
	name = title
	# room over room's questions, asked of the ground: rays, eyes and
	# blasts all stop at it (Level.layered)
	layered = true
	_proto = Sector.new()
	_proto.index = 0
	_proto.col_base = 0
	_proto.outdoor = true
	_proto.sky = 1.0
	_proto.light = 1.0
	_proto.floor_tex = "GRASS"
	_proto.ceil_tex = "SKY"
	_proto.name = "the island"
	sectors.append(_proto)
	var e := g.half * U_PER_M
	bounds = Rect2(-e, -e, 2.0 * e, 2.0 * e)
	bounds_hint = bounds
	world = {"noSquads": true}
	map_light = {}

## THE GROUND under the game's (x, y), in the game's units, or NO_FLOOR
## off the island.
func floor_at(x: float, y: float) -> float:
	var m := ground.height(x / U_PER_M, -y / U_PER_M)
	return NO_FLOOR if m <= IslandGround.VOID else m * U_PER_M

## Whether a body of this radius can stand here: on the island, with its
## whole circle clear of the coast.
func on_land(x: float, y: float, radius := 0.0) -> bool:
	var r := radius + COAST_MARGIN
	return floor_at(x, y) > NO_FLOOR and floor_at(x + r, y) > NO_FLOOR and floor_at(x - r, y) > NO_FLOOR \
		and floor_at(x, y + r) > NO_FLOOR and floor_at(x, y - r) > NO_FLOOR

## The ground's normal under (x, y), in the game's axes (z up).
func normal_at(x: float, y: float) -> Vector3:
	var n := ground.normal(x / U_PER_M, -y / U_PER_M)
	return Vector3(n.x, -n.z, n.y)

# ------------------------------------------------------------------
# THE SECTOR QUESTIONS: every point its own sector
# ------------------------------------------------------------------

func sector_at(x: float, y: float, _hint: Sector = null) -> Sector:
	var f := floor_at(x, y)
	if f <= NO_FLOOR:
		return null
	var s := Sector.new()
	s.floor = f
	s.ceil = f + SKY_OVER
	s.outdoor = true
	s.sky = 1.0
	s.light = _proto.light
	s.floor_tex = _proto.floor_tex
	s.ceil_tex = "SKY"
	s.name = _proto.name
	return s

func span_at(x: float, y: float, _z: float, hint: Sector = null) -> Sector:
	return sector_at(x, y, hint)

func span_in(s: Sector, _z: float) -> Sector:
	return s

func stand_in(s: Sector, _z: float) -> Sector:
	return s

func storey_of(s: Sector, _z: float) -> Sector:
	return s

func top_of(s: Sector) -> Sector:
	return s

func column_at(x: float, y: float) -> Array:
	var s := sector_at(x, y)
	return [] if s == null else [s]

## no lines: nothing to walk the blockmap for
func lines_in_box(_minx: float, _miny: float, _maxx: float, _maxy: float) -> Array:
	return []

# ------------------------------------------------------------------
# MOVING: the ground stops a body where Doom's lines did
# ------------------------------------------------------------------

## The landing point must be on the island (the whole body inland of the
## coast), no more than a step above the feet (a crag is a wall), and —
## for the crowd — no further down than Doom lets a monster drop.
## (Level.slide_move does the sliding and the substeps, asking this.)
func can_move(fx: float, fy: float, tx: float, ty: float, radius: float, z: float, height: float, monster: bool) -> bool:
	var f := floor_at(tx, ty)
	if f <= NO_FLOOR or not on_land(tx, ty, radius):
		return false
	if f - z > U.MAX_STEP:
		return false
	if monster and z - f > 96.0:
		return false
	# A HOUSE in the way: no step further into one (and a body somehow
	# inside one can always step out of it)
	if not houses.is_empty():
		for h in _houses_at(tx, ty):
			if z >= h.z + h.top or z + height <= h.z:
				continue
			var d := _house_depth(h, tx, ty, radius)
			if d > 0.0 and d >= _house_depth(h, fx, fy, radius) - 0.01:
				return false
	return true

# ------------------------------------------------------------------
# SEEING AND SHOOTING: the ground in the way
# ------------------------------------------------------------------

## A hill between the eye at a and the point at b.
func sight_blocked(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> bool:
	var dx := bx - ax
	var dy := by - ay
	var steps := int(sqrt(dx * dx + dy * dy) / SIGHT_STEP)
	for i in range(1, steps):
		var t := float(i) / steps
		if floor_at(ax + dx * t, ay + dy * t) > az + (bz - az) * t:
			return true
	return not houses.is_empty() and not ray_hit_wall(ax, ay, az, bx, by, bz).is_empty()

## THE WALLS ON AN ISLAND are the houses' (the ground is a floor, and
## ray_hit_flat finds it): the first house wall the ray from a to b goes
## into, {line, t, x, y, z} as Level's, or {}. A ray from inside a house
## goes out through it; one over the eaves goes over.
func ray_hit_wall(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> Dictionary:
	if houses.is_empty():
		return {}
	var best := {}
	var best_t := INF
	for h in _houses_along(ax, ay, bx, by):
		var hit := _house_hit(h, ax, ay, az, bx, by, bz)
		if not hit.is_empty() and hit.t < best_t:
			best_t = hit.t
			best = hit
	if best.is_empty():
		return {}
	return {"line": best.line, "t": best_t, "x": ax + (bx - ax) * best_t, "y": ay + (by - ay) * best_t, "z": az + (bz - az) * best_t}

## WHERE A RAY FROM a TO b GOES INTO THE GROUND: walked a metre at a time,
## then halved to the crossing. {t, z, up: false}, or {} if it never does
## (into the sky, or out over the void).
func ray_hit_flat(ax: float, ay: float, az: float, bx: float, by: float, bz: float, _skies := false) -> Dictionary:
	var dx := bx - ax
	var dy := by - ay
	var dz := bz - az
	var steps := maxi(1, ceili(sqrt(dx * dx + dy * dy + dz * dz) / RAY_STEP))
	var t0 := 0.0
	for i in range(1, steps + 1):
		var t1 := float(i) / steps
		var f := floor_at(ax + dx * t1, ay + dy * t1)
		if f > NO_FLOOR and az + dz * t1 < f:
			# under the ground at t1, over it at t0: halve to the crossing
			for k in 6:
				var tm := (t0 + t1) * 0.5
				var fm := floor_at(ax + dx * tm, ay + dy * tm)
				if fm > NO_FLOOR and az + dz * tm < fm:
					t1 = tm
				else:
					t0 = tm
			var fz := floor_at(ax + dx * t1, ay + dy * t1)
			return {"t": t1, "z": fz if fz > NO_FLOOR else az + dz * t1, "up": false}
		t0 = t1
	return {}

## THE LONGEST STRETCH OF LEVEL GROUND out of (x, y), up to `most`: the
## bearing and how far, walked a metre at a time while the ground stays
## within a step of where it started and nothing rises into the line
## between. Vector2(angle, length). (For the tests, which want a place
## to shoot along; the old maps had corridors.)
func flat_run(x: float, y: float, most := 2000.0, bearings := 32) -> Vector2:
	var f0 := floor_at(x, y)
	var best := Vector2()
	for k in bearings:
		var a := k * TAU / bearings
		var l := 0.0
		while l < most:
			var nx := x + cos(a) * (l + 32.0)
			var ny := y + sin(a) * (l + 32.0)
			var f := floor_at(nx, ny)
			if f <= NO_FLOOR or not on_land(nx, ny, 16.0) or absf(f - f0) > U.MAX_STEP:
				break
			l += 32.0
		if l > best.y and not sight_blocked(x, y, f0 + 41.0, x + cos(a) * l, y + sin(a) * l, f0 + 41.0):
			best = Vector2(a, l)
	return best

# ------------------------------------------------------------------
# WHO IS ON IT
# ------------------------------------------------------------------

## THE START AND THE CROWD (Level.things), from the seed: the player on
## open, gentle ground near the middle, and `people` townsfolk — most of
## them in groups round the island, a share of them near the start so
## there is somebody to meet. Everything on land, nothing on a crag.
## `crowd`, the actor types they are (Islands.LIST's "crowd"; shoppers and
## townsfolk if empty), each in one of its drawings. On an island with
## ROADS (`roads`, Game._roads_of) the groups are the town squares — you
## start in one — and a street lamp stands every `lamps` metres along
## each side of every road, staggered.
## THE HOUSES (`house_spec`, Islands "houses") go round the squares
## (place_houses) before anybody is put down, so nobody starts in one.
func populate(seed: int, people: int, crowd: Array = [], roads := {}, lamps := 0.0, herds := {}, meadow = null,
		house_spec := {}, clear = null) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	things = []
	var squares: Array = roads.get("squares", [])
	var start: Vector2
	if squares.is_empty():
		start = _find_ground(rng, Vector2.ZERO, 6000.0, 0.35)
	else:
		# the square nearest the middle, somewhere inside it
		var sq: Array = squares[0]
		for s in squares:
			if (s[0] as Vector2).length() < (sq[0] as Vector2).length():
				sq = s
		start = _find_ground(rng, sq[0], float(sq[1]) * 0.5, 0.35)
	things.append({"type": "START", "x": start.x, "y": start.y, "angle": rng.randf() * TAU})
	if not house_spec.is_empty():
		place_houses(seed, squares, roads.get("paths", []), house_spec, clear, start)
	# GROUPS: a few places on the island, a crowd round each (on a roaded
	# island, every square, and a few places out in the country)
	var groups := []
	var spreads := []
	groups.append(start)
	spreads.append(1400.0)
	for s in squares:
		groups.append(s[0])
		spreads.append(maxf(1200.0, float(s[1]) * 1.2))
	var e := ground.half * U_PER_M
	for i in (7 if squares.is_empty() else 3):
		groups.append(_find_ground(rng, Vector2.ZERO, e * 0.7, 0.45))
		spreads.append(2400.0)
	var types: Array = crowd if not crowd.is_empty() else ["SHOPPER", "SHOPPER", "TOWNIE"]
	for i in people:
		var g := i % groups.size()
		var p := _find_ground(rng, groups[g], float(spreads[g]), 0.6)
		var type: String = types[rng.randi() % types.size()]
		var n := int(States.actor(type).get("variants", 1))
		things.append({"type": type, "x": p.x, "y": p.y, "angle": rng.randf() * TAU, "variant": rng.randi() % maxi(1, n)})
	# and you start facing the nearest of them, so there is somebody to see
	var near := []
	for t in things:
		if t.type != "START":
			near.append(Vector2(t.x, t.y))
	near.sort_custom(func(a, b): return a.distance_squared_to(start) < b.distance_squared_to(start))
	if not near.is_empty():
		var c := Vector2()
		for q in near.slice(0, 6):
			c += q
		c /= minf(6.0, near.size())
		things[0].angle = (c - start).angle()
	# THE HERDS (CANDY LAND's unicorns, Islands "herds"): `count` herds,
	# each in a MEADOW — open grass, no wood, no road or square, gentle
	# ground (`meadow`, Game._meadow_of) — well apart and away from your
	# start, a few grown unicorns round the herd's middle and a foal or
	# two each beside one of them, her mother
	if not herds.is_empty():
		var centres: Array[Vector2] = []
		var reach := e * 0.85
		for h in int(herds.get("count", 0)):
			var c := Vector2.INF
			for k in 300:
				var a := rng.randf() * TAU
				var q := Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * reach
				if not on_land(q.x, q.y, 400.0) or q.distance_to(start) < 1600.0:
					continue
				if centres.any(func(o): return o.distance_to(q) < 2400.0):
					continue
				if meadow != null and not meadow.call(q.x, q.y):
					continue
				c = q
				break
			if c == Vector2.INF:
				continue
			centres.append(c)
			var ad: Array = herds.get("adults", [3, 5])
			var fo: Array = herds.get("foals", [1, 3])
			var mothers := []
			for i in rng.randi_range(int(ad[0]), int(ad[1])):
				var p := _find_ground(rng, c, 320.0, 0.4)
				mothers.append(things.size())
				things.append({"type": "UNICORN", "x": p.x, "y": p.y, "angle": rng.randf() * TAU, "home": c})
			for i in rng.randi_range(int(fo[0]), int(fo[1])):
				var m: int = mothers[rng.randi() % mothers.size()]
				var mp := Vector2(things[m].x, things[m].y)
				var p := _find_ground(rng, mp, 90.0, 0.5)
				things.append({"type": "FOAL", "x": p.x, "y": p.y, "angle": rng.randf() * TAU, "home": c, "mother": m})
	# THE STREET LAMPS, along both kerbs, half a step out of phase
	if lamps > 0.0:
		var step := lamps * U_PER_M
		for r in roads.get("paths", []):
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var len := a.distance_to(b)
			if len < step * 0.5:
				continue
			var dir := (b - a) / len
			var side := Vector2(-dir.y, dir.x) * (float(r[2]) + 40.0)
			for k in range(1, int(len / step) + 1):
				for s in [1.0, -1.0]:
					var q: Vector2 = a + dir * (k * step - (step * 0.5 if s < 0.0 else 0.0)) + side * s
					if on_land(q.x, q.y, 32.0) and not in_house(q.x, q.y, 32.0):
						things.append({"type": "LAMP", "x": q.x, "y": q.y, "angle": 0.0})

## A point on land within `r` of `c`, whose ground rises no more than
## `max_slope` (rise over run) — the first of a few hundred tries that is,
## else the best of them.
func _find_ground(rng: RandomNumberGenerator, c: Vector2, r: float, max_slope: float) -> Vector2:
	var best := c
	var best_slope := INF
	for k in 400:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var p := c + Vector2(cos(a), sin(a)) * d
		if not on_land(p.x, p.y, 128.0) or in_house(p.x, p.y, 48.0):
			continue
		var n := normal_at(p.x, p.y)
		var slope := sqrt(n.x * n.x + n.y * n.y) / maxf(0.05, n.z)
		if slope <= max_slope:
			return p
		if slope < best_slope:
			best_slope = slope
			best = p
	return best

# ------------------------------------------------------------------
# THE HOUSES
# ------------------------------------------------------------------

## HOUSES ROUND THE TOWN SQUARES (at the user's request: CANDY LAND's
## gingerbread house, scattered round the "town" areas). Each square has
## two rings of plots, every one facing the middle: one just inside its
## rim, on the flat the square is cut into, and one just outside it,
## staggered into the gaps of the first, on the square's bank. A plot is
## built on, at `spec.inner` / `spec.outer` odds, where it is
##   - clear of every road (its kerb and a metre more), so the streets
##     still run into the square,
##   - clear of every other house, and of your start,
##   - on ground level to within `spec.level` metres across its corners,
##   - and clear of the wood (`clear`, Game._clear_of), so no tree grows
##     through a roof.
## The footprint is the model's (`spec.footprint`, metres: half its width,
## its back and front from its middle, the height a round goes over), at
## each house's own scale. Off its own seed, so the crowd and the herds
## are where they were before there were houses.
func place_houses(seed: int, squares: Array, paths: Array, spec: Dictionary, clear, start: Vector2) -> void:
	houses = []
	_house_cells = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x6801
	var fp: Dictionary = spec.get("footprint", {})
	var sc: Array = spec.get("scale", [1.0, 1.0])
	var gap := float(spec.get("gap", 4.0)) * U_PER_M
	var width := float(fp.get("hw", 3.4)) * 2.0 * U_PER_M
	for sq in squares:
		var c: Vector2 = sq[0]
		var r: float = sq[1]
		var a0 := rng.randf() * TAU
		for ring in [[r - float(spec.get("inset", 4.5)) * U_PER_M, float(spec.get("inner", 0.85)), 0.0],
				[r + float(spec.get("outset", 6.5)) * U_PER_M, float(spec.get("outer", 0.6)), 0.5]]:
			var d: float = ring[0]
			var slots := int(TAU * d / (width + gap))
			if slots < 3:
				continue
			for k in slots:
				# (drawn every time, so a plot left empty leaves the rest as they were)
				var odds := rng.randf()
				var th := a0 + (k + float(ring[2]) + rng.randf_range(-0.1, 0.1)) * TAU / slots
				var face := th + PI + rng.randf_range(-0.12, 0.12)
				var s := rng.randf_range(float(sc[0]), float(sc[1]))
				if odds > float(ring[1]):
					continue
				_try_house(c + Vector2(cos(th), sin(th)) * d, face, s, fp, paths, spec, clear, start)

## A house at p, its door toward `angle`, if the plot will take it.
func _try_house(p: Vector2, angle: float, s: float, fp: Dictionary, paths: Array, spec: Dictionary, clear, start: Vector2) -> bool:
	var h := {"i": houses.size(), "x": p.x, "y": p.y, "angle": angle, "scale": s,
		"hw": float(fp.get("hw", 3.4)) * U_PER_M * s, "back": float(fp.get("back", 3.1)) * U_PER_M * s,
		"front": float(fp.get("front", 3.7)) * U_PER_M * s, "top": float(fp.get("top", 5.7)) * U_PER_M * s}
	h.rad = Vector2(h.hw, maxf(h.back, h.front)).length()
	if not on_land(p.x, p.y, h.rad) or p.distance_to(start) < h.rad + 96.0:
		return false
	for r in paths:
		var q := Geometry2D.get_closest_point_to_segment(p, r[0], r[1])
		if q.distance_to(p) < float(r[2]) + h.rad + U_PER_M:
			return false
	for o in houses:
		if p.distance_to(Vector2(o.x, o.y)) < h.rad + o.rad + U_PER_M:
			return false
	var lo := INF
	var hi := -INF
	for q in _house_corners(h) + [p]:
		var f := floor_at(q.x, q.y)
		if f <= NO_FLOOR or (clear != null and not clear.call(q.x, q.y)):
			return false
		lo = minf(lo, f)
		hi = maxf(hi, f)
	if hi - lo > float(spec.get("level", 0.8)) * U_PER_M:
		return false
	# sat on its lowest corner, a hand's breadth down, so it stands IN the
	# ground on a slight slope and never on stilts
	h.z = lo - 0.1 * U_PER_M
	# its four walls, as lines: back, right, front, left
	var cs := _house_corners(h)
	h.lines = []
	for k in 4:
		var l := Line.new()
		l.index = -1 - h.i * 4 - k
		l.front = 0
		l.back = -1
		l.x1 = cs[k].x
		l.y1 = cs[k].y
		l.x2 = cs[(k + 1) % 4].x
		l.y2 = cs[(k + 1) % 4].y
		l.dx = l.x2 - l.x1
		l.dy = l.y2 - l.y1
		l.len = sqrt(l.dx * l.dx + l.dy * l.dy)
		l.blocking = true
		l.block_sight = true
		h.lines.append(l)
	houses.append(h)
	var reach: float = h.rad + 64.0
	for cx in range(floori((p.x - reach) / HOUSE_CELL), floori((p.x + reach) / HOUSE_CELL) + 1):
		for cy in range(floori((p.y - reach) / HOUSE_CELL), floori((p.y + reach) / HOUSE_CELL) + 1):
			var key := Vector2i(cx, cy)
			if not _house_cells.has(key):
				_house_cells[key] = []
			_house_cells[key].append(h)
	return true

## The house's corners on the ground: back-left, back-right, front-right,
## front-left (left and right as you face its door from inside).
func _house_corners(h: Dictionary) -> Array:
	var f := Vector2(cos(h.angle), sin(h.angle))
	var r := Vector2(-f.y, f.x)
	var c := Vector2(h.x, h.y)
	return [c - f * h.back - r * h.hw, c - f * h.back + r * h.hw, c + f * h.front + r * h.hw, c + f * h.front - r * h.hw]

## How far a body of `radius` at (x, y) is into the house (> 0 inside it,
## its whole width counted), its height not asked.
func _house_depth(h: Dictionary, x: float, y: float, radius: float) -> float:
	var f := Vector2(cos(h.angle), sin(h.angle))
	var d := Vector2(x - h.x, y - h.y)
	var v := d.dot(f)
	var u := d.dot(Vector2(-f.y, f.x))
	return minf(h.hw + radius - absf(u), minf(h.front + radius - v, v + h.back + radius))

## Whether a body of `radius` at (x, y) would stand in a house.
func in_house(x: float, y: float, radius := 0.0) -> bool:
	for h in _houses_at(x, y):
		if _house_depth(h, x, y, radius) > 0.0:
			return true
	return false

func _houses_at(x: float, y: float) -> Array:
	return _house_cells.get(Vector2i(floori(x / HOUSE_CELL), floori(y / HOUSE_CELL)), [])

## Every house a segment's box crosses the cells of (all of them, for a
## long one).
func _houses_along(ax: float, ay: float, bx: float, by: float) -> Array:
	var x0 := floori(minf(ax, bx) / HOUSE_CELL)
	var x1 := floori(maxf(ax, bx) / HOUSE_CELL)
	var y0 := floori(minf(ay, by) / HOUSE_CELL)
	var y1 := floori(maxf(ay, by) / HOUSE_CELL)
	if x0 == x1 and y0 == y1:
		return _houses_at(ax, ay)
	if (x1 - x0 + 1) * (y1 - y0 + 1) > 48:
		return houses
	var seen := {}
	var out := []
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			for h in _house_cells.get(Vector2i(cx, cy), []):
				if not seen.has(h.i):
					seen[h.i] = true
					out.append(h)
	return out

## Where the segment from a to b goes into the house's walls, {t, line},
## or {}: the box in the house's own frame, and the height where it goes
## in under the eaves (its `top`). From inside, nothing.
func _house_hit(h: Dictionary, ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> Dictionary:
	var f := Vector2(cos(h.angle), sin(h.angle))
	var r := Vector2(-f.y, f.x)
	var a := Vector2(ax - h.x, ay - h.y)
	var d := Vector2(bx - ax, by - ay)
	# (u across, v along the door's way), and the slabs
	var p := [a.dot(r), a.dot(f)]
	var q := [d.dot(r), d.dot(f)]
	var lo := [-h.hw, -h.back]
	var hi := [h.hw, h.front]
	var t0 := 0.0
	var t1 := 1.0
	var side := -1
	for k in 2:
		if absf(q[k]) < 1e-6:
			if p[k] < lo[k] or p[k] > hi[k]:
				return {}
			continue
		var ta: float = (lo[k] - p[k]) / q[k]
		var tb: float = (hi[k] - p[k]) / q[k]
		# which wall it comes in through: lines are back 0, right 1, front 2, left 3
		var wall_a := (3 if k == 0 else 0)
		var wall_b := (1 if k == 0 else 2)
		if ta > tb:
			var tt := ta
			ta = tb
			tb = tt
			var ww := wall_a
			wall_a = wall_b
			wall_b = ww
		if ta > t0:
			t0 = ta
			side = wall_a
		t1 = minf(t1, tb)
		if t0 > t1:
			return {}
	if side < 0:
		return {}
	var z := az + (bz - az) * t0
	if z < h.z or z > h.z + h.top:
		return {}
	return {"t": t0, "line": h.lines[side]}
