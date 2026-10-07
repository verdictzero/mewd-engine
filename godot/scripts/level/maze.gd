## MEWD — THE MAZE (at the user's request, MAZE LAND: "divide it
## conceptually into 9ths, in the 2nd 4th 5th 6th and 8th sections, build
## an interconnected maze using these parts" — assets/models/maze_parts.glb:
## a wall 8 m long, 1 m thick and 9 m tall, and a post 1 m square).
##
## THE GRID: square cells PITCH apart (a post's metre and a wall's eight),
## `n` to a side, centred on the island. The island is cut into a three by
## three of SECTIONS, numbered as the user did, 1 to 9 across from the
## north-west; the maze fills the cells of the sections in `sections` (by
## default the plus: 2, 4, 5, 6, 8), and every other cell is open ground.
##
## THE MAZE: a spanning tree over its cells (a depth-first carve from the
## middle, off the seed), so every cell reaches every other, and then a
## share of the walls left knocked through as well (`loops`) — more than
## one way round, an interconnected maze rather than a tree. Its outside
## wall is opened in `doors` places a side on each arm, where it faces open
## ground or the island's edge.
##
## WHAT IS A WALL: an edge of the grid with a wall on it is a slab of the
## wall's thickness along it, a post's half-metre past each end, as tall as
## the wall — a body cannot step into one (IslandLevel.can_move), an eye
## cannot see through one and a round goes into it (ray_hit). Every point a
## wall meets carries a post.
##
## All in the game's units (Doom's: x east, y north, 32 to the metre)
## except where it says metres.
class_name Maze
extends RefCounted

const U := 32.0
## a cell, post to post, in metres
const PITCH := 9.0
## the wall's half-thickness, metres
const HALF := 0.5
## how tall, metres
const TALL := 9.0

## cells to a side, and which sections hold the maze (1..9)
var n := 111
var sections: Array = [2, 4, 5, 6, 8]
## the floor the walls stand on, in the game's units (the island is flat)
var floor_z := 0.0
## (the grid's north-west corner, game units)
var x0 := 0.0
var y0 := 0.0
var pitch := PITCH * U
var half := HALF * U
var tall := TALL * U
## in_maze[r * n + c]: the cell is the maze's
var in_maze := PackedByteArray()
## THE WALLS: hwall[r * n + c], the wall along the NORTH side of cell (r, c)
## (r 0..n: row n is the south side of the last row); vwall[r * (n + 1) + c],
## along its WEST side (c 0..n)
var hwall := PackedByteArray()
var vwall := PackedByteArray()
## (a Line for each wall a round has gone into, made when it first is)
var _lines := {}

## spec: Islands "maze" {cells, sections, seed, loops, doors}
func _init(spec: Dictionary, floor_units := 0.0) -> void:
	n = int(spec.get("cells", 111))
	sections = spec.get("sections", [2, 4, 5, 6, 8])
	floor_z = floor_units
	var span := n * pitch
	x0 = -span * 0.5
	y0 = span * 0.5
	in_maze.resize(n * n)
	var third := float(n) / 3.0
	for r in n:
		for c in n:
			var sec := 1 + int(floor(c / third)) + 3 * int(floor(r / third))
			in_maze[r * n + c] = 1 if sections.has(sec) else 0
	hwall.resize((n + 1) * n)
	vwall.resize(n * (n + 1))
	_carve(int(spec.get("seed", 1)), float(spec.get("loops", 0.1)), int(spec.get("doors", 2)))

func cell(r: int, c: int) -> bool:
	return r >= 0 and c >= 0 and r < n and c < n and in_maze[r * n + c] == 1

# ---- making it ---------------------------------------------------------------

func _carve(seed: int, loops: float, doors: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# every edge touching a maze cell starts as a wall
	for r in n + 1:
		for c in n:
			hwall[r * n + c] = 1 if (cell(r - 1, c) or cell(r, c)) else 0
	for r in n:
		for c in n + 1:
			vwall[r * (n + 1) + c] = 1 if (cell(r, c - 1) or cell(r, c)) else 0
	# THE TREE: a depth-first carve from the middle (an explicit stack: a
	# few thousand cells deep would overflow a recursive one)
	var seen := PackedByteArray()
	seen.resize(n * n)
	var mid := n / 2
	var stack := PackedInt32Array([mid * n + mid])
	seen[mid * n + mid] = 1
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while not stack.is_empty():
		var at: int = stack[stack.size() - 1]
		var r := at / n
		var c := at % n
		var open := []
		for d in dirs:
			var rr: int = r + d.y
			var cc: int = c + d.x
			if cell(rr, cc) and seen[rr * n + cc] == 0:
				open.append(d)
		if open.is_empty():
			stack.remove_at(stack.size() - 1)
			continue
		var d: Vector2i = open[rng.randi() % open.size()]
		_knock(r, c, d)
		var nr: int = r + d.y
		var nc: int = c + d.x
		seen[nr * n + nc] = 1
		stack.append(nr * n + nc)
	# AND THE LOOPS: a share of the inside walls knocked through as well
	for r in n:
		for c in n:
			if not cell(r, c):
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				if cell(r + d.y, c + d.x) and _wall(r, c, d) and rng.randf() < loops:
					_knock(r, c, d)
	# THE DOORS: on every stretch of the outside wall, `doors` gaps
	var runs := {}
	for r in n:
		for c in n:
			if not cell(r, c):
				continue
			for d in dirs:
				if not cell(r + d.y, c + d.x):
					# which straight stretch of the outside this is: its side, its
					# line and its section
					var third := float(n) / 3.0
					var sec := int(floor(c / third)) + 3 * int(floor(r / third))
					var key := "%d:%d:%d" % [dirs.find(d), (r if d.y != 0 else c), sec]
					if not runs.has(key):
						runs[key] = []
					runs[key].append([r, c, d])
	for key in runs:
		var run: Array = runs[key]
		# (spread along it: one in each of `doors` equal parts)
		for k in doors:
			var lo := run.size() * k / doors
			var hi := maxi(lo + 1, run.size() * (k + 1) / doors)
			var pick: Array = run[rng.randi_range(lo, hi - 1)]
			_knock(pick[0], pick[1], pick[2])

func _wall(r: int, c: int, d: Vector2i) -> bool:
	match d:
		Vector2i(0, -1): return hwall[r * n + c] == 1
		Vector2i(0, 1): return hwall[(r + 1) * n + c] == 1
		Vector2i(-1, 0): return vwall[r * (n + 1) + c] == 1
		_: return vwall[r * (n + 1) + c + 1] == 1

func _knock(r: int, c: int, d: Vector2i) -> void:
	match d:
		Vector2i(0, -1): hwall[r * n + c] = 0
		Vector2i(0, 1): hwall[(r + 1) * n + c] = 0
		Vector2i(-1, 0): vwall[r * (n + 1) + c] = 0
		_: vwall[r * (n + 1) + c + 1] = 0

# ---- where things are ------------------------------------------------------------

## the cell (r, c) a point is in (may be off the grid)
func cell_of(x: float, y: float) -> Vector2i:
	return Vector2i(floori((x - x0) / pitch), floori((y0 - y) / pitch))

## a cell's middle, game units
func centre(r: int, c: int) -> Vector2:
	return Vector2(x0 + (c + 0.5) * pitch, y0 - (r + 0.5) * pitch)

## every wall as [ax, ay, bx, by] (game units, post centre to post centre)
func walls() -> Array:
	var out := []
	for r in n + 1:
		for c in n:
			if hwall[r * n + c] == 1:
				var y := y0 - r * pitch
				out.append([x0 + c * pitch, y, x0 + (c + 1) * pitch, y])
	for r in n:
		for c in n + 1:
			if vwall[r * (n + 1) + c] == 1:
				var x := x0 + c * pitch
				out.append([x, y0 - r * pitch, x, y0 - (r + 1) * pitch])
	return out

## every grid point a wall meets, game units
func posts() -> Array:
	var out := []
	for r in n + 1:
		for c in n + 1:
			var any := (c < n and hwall[r * n + c] == 1) or (c > 0 and hwall[r * n + c - 1] == 1) \
				or (r < n and vwall[r * (n + 1) + c] == 1) or (r > 0 and vwall[(r - 1) * (n + 1) + c] == 1)
			if any:
				out.append(Vector2(x0 + c * pitch, y0 - r * pitch))
	return out

## HOW FAR a body of `radius` at (x, y) is into the nearest wall (> 0
## inside one), its height not asked
func depth(x: float, y: float, radius := 0.0) -> float:
	var reach := half + radius
	var best := -INF
	# the grid lines within reach: horizontal ones (walls running east-west)
	var rlo := ceili((y0 - y - reach) / pitch)
	var rhi := floori((y0 - y + reach) / pitch)
	for r in range(maxi(rlo, 0), mini(rhi, n) + 1):
		var ly := y0 - r * pitch
		var cl := floori((x - x0 - reach) / pitch)
		var ch := floori((x - x0 + reach) / pitch)
		for c in range(maxi(cl, 0), mini(ch, n - 1) + 1):
			if hwall[r * n + c] == 0:
				continue
			var ax := x0 + c * pitch - half
			var bx := ax + pitch + 2.0 * half
			var dx := maxf(maxf(ax - x, x - bx), 0.0)
			var dy := absf(y - ly) - half
			best = maxf(best, radius - _box_dist(dx, dy))
	var clo := ceili((x - x0 - reach) / pitch)
	var chi := floori((x - x0 + reach) / pitch)
	for c in range(maxi(clo, 0), mini(chi, n) + 1):
		var lx := x0 + c * pitch
		var rl := floori((y0 - y - reach) / pitch)
		var rh := floori((y0 - y + reach) / pitch)
		for r in range(maxi(rl, 0), mini(rh, n - 1) + 1):
			if vwall[r * (n + 1) + c] == 0:
				continue
			var top := y0 - r * pitch + half
			var bot := top - pitch - 2.0 * half
			var dy := maxf(maxf(bot - y, y - top), 0.0)
			var dx := absf(x - lx) - half
			best = maxf(best, radius - _box_dist(dx, dy))
	return best

## (the distance from a point to a box, given how far outside it the point is
## along each axis — negative inside)
static func _box_dist(dx: float, dy: float) -> float:
	if dx <= 0.0 and dy <= 0.0:
		return maxf(dx, dy)
	return Vector2(maxf(dx, 0.0), maxf(dy, 0.0)).length()

## whether a body of `radius` at (x, y) stands in a wall
func blocked(x: float, y: float, radius := 0.0) -> bool:
	return depth(x, y, radius) > 0.0

## THE NEAREST WALL ALONG THE ROUND from a to b, {line, t, x, y, z}, or {}:
## each grid line the ray crosses, the slab of the wall's thickness round
## it entered, and the wall on that edge, if there is one there and the
## ray is under its top
func ray_hit(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> Dictionary:
	var best_t := INF
	var best := {}
	var dx := bx - ax
	var dy := by - ay
	# walls running east-west: the ray meets each one's slab in y
	if absf(dy) > 1e-6:
		var rlo := ceili((y0 - maxf(ay, by) - half) / pitch)
		var rhi := floori((y0 - minf(ay, by) + half) / pitch)
		for r in range(maxi(rlo, 0), mini(rhi, n) + 1):
			var ly := y0 - r * pitch
			var face := ly + (half if dy < 0.0 else -half)
			var t := 0.0 if absf(ay - ly) <= half else (face - ay) / dy
			if t < 0.0 or t > 1.0 or t >= best_t:
				continue
			var x := ax + dx * t
			var hit := _h_at(r, x)
			if hit < 0:
				continue
			var z := az + (bz - az) * t
			if z < floor_z or z > floor_z + tall:
				continue
			best_t = t
			best = {"line": _line(true, r, hit, dy < 0.0), "t": t, "x": x, "y": ay + dy * t, "z": z}
	if absf(dx) > 1e-6:
		var clo := ceili((minf(ax, bx) - x0 - half) / pitch)
		var chi := floori((maxf(ax, bx) - x0 + half) / pitch)
		for c in range(maxi(clo, 0), mini(chi, n) + 1):
			var lx := x0 + c * pitch
			var face := lx + (-half if dx > 0.0 else half)
			var t := 0.0 if absf(ax - lx) <= half else (face - ax) / dx
			if t < 0.0 or t > 1.0 or t >= best_t:
				continue
			var y := ay + dy * t
			var hit := _v_at(c, y)
			if hit < 0:
				continue
			var z := az + (bz - az) * t
			if z < floor_z or z > floor_z + tall:
				continue
			best_t = t
			best = {"line": _line(false, hit, c, dx > 0.0), "t": t, "x": ax + dx * t, "y": y, "z": z}
	return best

## the column of the east-west wall on line r covering x (posts' half-metres
## counted), or -1
func _h_at(r: int, x: float) -> int:
	var c := floori((x - x0) / pitch)
	for cc in [c, c - 1, c + 1]:
		if cc < 0 or cc >= n or hwall[r * n + cc] == 0:
			continue
		var a: float = x0 + cc * pitch - half
		if x >= a and x <= a + pitch + 2.0 * half:
			return cc
	return -1

## the row of the north-south wall on line c covering y, or -1
func _v_at(c: int, y: float) -> int:
	var r := floori((y0 - y) / pitch)
	for rr in [r, r - 1, r + 1]:
		if rr < 0 or rr >= n or vwall[rr * (n + 1) + c] == 0:
			continue
		var top: float = y0 - rr * pitch + half
		if y <= top and y >= top - pitch - 2.0 * half:
			return rr
	return -1

## a Line for the face of a wall a round went into (Level's shape: what
## a hit's decal and spark ask of it), one per face, kept
func _line(east_west: bool, r: int, c: int, far_side: bool) -> Level.Line:
	var key := Vector4i(1 if east_west else 0, r, c, 1 if far_side else 0)
	if _lines.has(key):
		return _lines[key]
	var l := Level.Line.new()
	l.index = -100000 - _lines.size()
	l.front = 0
	l.back = -1
	if east_west:
		var y := y0 - r * pitch + (half if far_side else -half)
		var a := x0 + c * pitch
		# (the face toward the ray's side on its right, as Doom's front)
		if far_side:
			l.x1 = a + pitch; l.x2 = a
		else:
			l.x1 = a; l.x2 = a + pitch
		l.y1 = y; l.y2 = y
	else:
		var x := x0 + c * pitch + (-half if far_side else half)
		var t := y0 - r * pitch
		if far_side:
			l.y1 = t; l.y2 = t - pitch
		else:
			l.y1 = t - pitch; l.y2 = t
		l.x1 = x; l.x2 = x
	l.dx = l.x2 - l.x1
	l.dy = l.y2 - l.y1
	l.len = sqrt(l.dx * l.dx + l.dy * l.dy)
	l.blocking = true
	l.block_sight = true
	_lines[key] = l
	return l

## HOW FAR a point (island metres, x and z) is from the nearest wall's
## side, in metres — negative under one: for the grass
## (SCRIPT_grass_scatter `mask`). Thread-safe: it only reads.
func near_m(mx: float, mz: float, reach_m := 4.0) -> float:
	# (depth with a radius finds the walls within that radius: radius less
	# depth is the distance; none within it, INF)
	var r := reach_m * U
	return (r - depth(mx * U, -mz * U, r)) / U

## Every maze cell reachable from (r, c) without going through a wall, as a
## count (the tests: one maze, all of it reachable)
func reachable(r: int, c: int) -> int:
	var seen := PackedByteArray()
	seen.resize(n * n)
	var todo := PackedInt32Array([r * n + c])
	seen[r * n + c] = 1
	var count := 0
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	while not todo.is_empty():
		var at: int = todo[todo.size() - 1]
		todo.remove_at(todo.size() - 1)
		count += 1
		var rr := at / n
		var cc := at % n
		for d in dirs:
			var nr: int = rr + d.y
			var nc: int = cc + d.x
			if cell(nr, nc) and seen[nr * n + nc] == 0 and not _wall(rr, cc, d):
				seen[nr * n + nc] = 1
				todo.append(nr * n + nc)
	return count

## how many cells are the maze's
func size() -> int:
	var k := 0
	for b in in_maze:
		k += b
	return k
