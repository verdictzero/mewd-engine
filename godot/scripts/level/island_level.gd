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
func can_move(_fx: float, _fy: float, tx: float, ty: float, radius: float, z: float, _height: float, monster: bool) -> bool:
	var f := floor_at(tx, ty)
	if f <= NO_FLOOR or not on_land(tx, ty, radius):
		return false
	if f - z > U.MAX_STEP:
		return false
	if monster and z - f > 96.0:
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
	return false

## No walls on an island: the ground is a floor, and ray_hit_flat finds it.
func ray_hit_wall(_ax: float, _ay: float, _az: float, _bx: float, _by: float, _bz: float) -> Dictionary:
	return {}

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
func populate(seed: int, people: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	things = []
	var start := _find_ground(rng, Vector2.ZERO, 6000.0, 0.35)
	things.append({"type": "START", "x": start.x, "y": start.y, "angle": rng.randf() * TAU})
	# GROUPS: a few places on the island, a crowd round each
	var groups := []
	groups.append(start)
	var e := ground.half * U_PER_M
	for i in 7:
		groups.append(_find_ground(rng, Vector2.ZERO, e * 0.7, 0.45))
	var types := ["SHOPPER", "SHOPPER", "TOWNIE"]
	for i in people:
		var c: Vector2 = groups[i % groups.size()]
		var spread := 1400.0 if i % groups.size() == 0 else 2400.0
		var p := _find_ground(rng, c, spread, 0.6)
		things.append({"type": types[rng.randi() % types.size()], "x": p.x, "y": p.y, "angle": rng.randf() * TAU})
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
		if not on_land(p.x, p.y, 128.0):
			continue
		var n := normal_at(p.x, p.y)
		var slope := sqrt(n.x * n.x + n.y * n.y) / maxf(0.05, n.z)
		if slope <= max_slope:
			return p
		if slope < best_slope:
			best_slope = slope
			best = p
	return best
