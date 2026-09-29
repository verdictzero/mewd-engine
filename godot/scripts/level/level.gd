## MEWD — the built map, and everything that asks it questions
## (js/level.js: MapBuilder and Level).
##
## A Doom map in all but file format: SECTORS are polygons with a floor
## height, a ceiling height and a light; LINES are the edges between
## them, one-sided (a wall) or two-sided (an opening, with a step or a
## lintel if the heights differ). Collision, sight and hitscan are all
## asked of the lines through a 128-unit BLOCKMAP, Doom's way — there is
## no physics engine under the walls, which is what keeps the movement
## feeling like the web build's (and Doom's): slide along walls, step up
## 24 units, never rest inside geometry.
class_name Level
extends RefCounted

const BLOCK := 128.0
const WELD := 0.5

class Sector:
	var index := 0
	var floor := 0.0
	var ceil := 128.0
	var light := 0.75
	var floor_tex := "FLAT"
	var ceil_tex := "FLAT"
	var wall_tex := "WALL"
	var upper_tex := "WALL"
	var lower_tex := "WALL"
	var name := ""
	var outdoor := false
	var sky := 0.0
	var poly := PackedVector2Array()
	var vidx := PackedInt32Array()
	var bbox := Rect2()
	var is_rect := false
	var convex := false
	var lines: Array = []
	var props := {}

class Line:
	var index := 0
	var v1 := 0
	var v2 := 0
	var front := -1
	var back := -1
	var x1 := 0.0
	var y1 := 0.0
	var x2 := 0.0
	var y2 := 0.0
	var dx := 0.0
	var dy := 0.0
	var len := 0.0
	var contrast := 0.0
	var middle = null
	var upper = null
	var lower = null
	var blocking := false
	var block_sight := false
	var xoff := 0.0
	var yoff := 0.0
	var stamp := 0

var name := ""
var verts := PackedVector2Array()
var sectors: Array[Sector] = []
var lines: Array[Line] = []
var things: Array = []
var world := {}
var bounds := Rect2()

var _vkey := {}
var _edges := {}

var origin_x := 0.0
var origin_y := 0.0
var cols := 0
var rows := 0
var block_lines: Array = []
var block_sectors: Array = []
var _stamp := 0

# ------------------------------------------------------------------
# BUILDING (MapBuilder)
# ------------------------------------------------------------------

func vertex(x: float, y: float) -> int:
	var key := Vector2i(roundi(x / WELD), roundi(y / WELD))
	if _vkey.has(key):
		return _vkey[key]
	var i := verts.size()
	verts.append(Vector2(x, y))
	_vkey[key] = i
	return i

static func area2(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a

## Add a region; its ring is forced counter-clockwise, so the sector is
## on the LEFT of every edge. Returns the sector's index.
func add_sector(poly: PackedVector2Array, p: Dictionary) -> int:
	var pts := poly.duplicate()
	if area2(pts) < 0.0:
		pts.reverse()
	var s := Sector.new()
	s.index = sectors.size()
	s.floor = float(p.get("floor", 0.0))
	s.ceil = float(p.get("ceil", 128.0))
	s.light = float(p.get("light", 0.75))
	s.floor_tex = str(p.get("floorTex", "FLAT"))
	s.ceil_tex = str(p.get("ceilTex", "FLAT"))
	s.wall_tex = str(p.get("wallTex", "WALL"))
	var up = p.get("upperTex")
	var lo = p.get("lowerTex")
	s.upper_tex = str(up) if up != null else s.wall_tex
	s.lower_tex = str(lo) if lo != null else s.wall_tex
	s.name = str(p.get("name", ""))
	s.outdoor = bool(p.get("outdoor", false))
	s.sky = float(p.get("sky", 1.0 if s.outdoor else 0.0))
	s.props = p
	s.poly = pts
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for q in pts:
		s.vidx.append(vertex(q.x, q.y))
		mn = mn.min(q)
		mx = mx.max(q)
	s.bbox = Rect2(mn, mx - mn)
	sectors.append(s)
	var n := s.vidx.size()
	for i in n:
		_edge(s.vidx[i], s.vidx[(i + 1) % n], s.index)
	return s.index

## Doom's convention: a line's FRONT is on its right, so the line is
## stored b->a and the sector on the left of a->b is its front. If the
## edge exists already, this sector is its back.
func _edge(a: int, b: int, sec: int) -> void:
	if a == b:
		return
	var key := Vector2i(mini(a, b), maxi(a, b))
	var l: Line = _edges.get(key)
	if l == null:
		l = Line.new()
		l.index = lines.size()
		l.v1 = b
		l.v2 = a
		l.front = sec
		l.middle = sectors[sec].wall_tex
		lines.append(l)
		_edges[key] = l
		return
	if l.back == -1 and not (l.v1 == b and l.v2 == a):
		l.back = sec
		l.middle = null

## Every wall's skins, from the heights: a step shows the higher floor's
## lower texture, a lintel the lower ceiling's upper texture — and two
## skies meeting draw no lintel at all, Doom's sky hack.
func finish() -> void:
	for l in lines:
		var p1 := verts[l.v1]
		var p2 := verts[l.v2]
		l.x1 = p1.x; l.y1 = p1.y; l.x2 = p2.x; l.y2 = p2.y
		l.dx = l.x2 - l.x1
		l.dy = l.y2 - l.y1
		l.len = sqrt(l.dx * l.dx + l.dy * l.dy)
		# Doom's fake contrast: east-west walls a notch brighter, north-
		# south a notch darker, so a corner shows in a renderer with no
		# shading at all
		l.contrast = 0.055 if absf(l.dy) < 0.01 else (-0.055 if absf(l.dx) < 0.01 else 0.0)
		if l.back == -1:
			continue
		var f := sectors[l.front]
		var b := sectors[l.back]
		l.lower = (f if f.floor >= b.floor else b).lower_tex
		l.upper = (f if f.ceil <= b.ceil else b).upper_tex
		sectors[l.front].lines.append(l)
		sectors[l.back].lines.append(l)
	for l in lines:
		if l.back == -1:
			sectors[l.front].lines.append(l)
	for s in sectors:
		s.convex = _convex(s.poly)
		s.is_rect = s.convex
		if s.convex:
			var n := s.poly.size()
			for i in n:
				var p := s.poly[i]
				var q := s.poly[(i + 1) % n]
				if absf(p.x - q.x) > 1e-9 and absf(p.y - q.y) > 1e-9:
					s.is_rect = false
					break
	_build_bounds()
	_build_blockmap()

static func _convex(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	var sign := 0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var c := pts[(i + 2) % n]
		var cr := (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
		if absf(cr) < 1e-9:
			continue
		var sg := 1 if cr > 0 else -1
		if sign == 0:
			sign = sg
		elif sg != sign:
			return false
	return true

func _build_bounds() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	bounds = Rect2(mn, mx - mn)
	origin_x = floorf(mn.x / BLOCK) * BLOCK - BLOCK
	origin_y = floorf(mn.y / BLOCK) * BLOCK - BLOCK
	cols = ceili((mx.x - origin_x) / BLOCK) + 2
	rows = ceili((mx.y - origin_y) / BLOCK) + 2

func _build_blockmap() -> void:
	var n := cols * rows
	block_lines.resize(n)
	block_sectors.resize(n)
	for i in n:
		block_lines[i] = []
		block_sectors[i] = []
	for l in lines:
		for r in range(_row(minf(l.y1, l.y2)), _row(maxf(l.y1, l.y2)) + 1):
			for c in range(_col(minf(l.x1, l.x2)), _col(maxf(l.x1, l.x2)) + 1):
				block_lines[r * cols + c].append(l)
	for s in sectors:
		for r in range(_row(s.bbox.position.y), _row(s.bbox.end.y) + 1):
			for c in range(_col(s.bbox.position.x), _col(s.bbox.end.x) + 1):
				block_sectors[r * cols + c].append(s)

func _col(x: float) -> int:
	return clampi(floori((x - origin_x) / BLOCK), 0, cols - 1)

func _row(y: float) -> int:
	return clampi(floori((y - origin_y) / BLOCK), 0, rows - 1)

# ------------------------------------------------------------------
# QUESTIONS
# ------------------------------------------------------------------

## Every line that could touch the box, once each.
func lines_in_box(minx: float, miny: float, maxx: float, maxy: float) -> Array:
	var out := []
	_stamp += 1
	for r in range(_row(miny), _row(maxy) + 1):
		for c in range(_col(minx), _col(maxx) + 1):
			for l in block_lines[r * cols + c]:
				if l.stamp == _stamp:
					continue
				l.stamp = _stamp
				out.append(l)
	return out

## Which sector (x, y) is in, or null off the map. The hint — last
## tic's sector — answers nearly every call without the grid.
func sector_at(x: float, y: float, hint: Sector = null) -> Sector:
	if hint != null and _in_sector(hint, x, y):
		return hint
	for s in block_sectors[_row(y) * cols + _col(x)]:
		if _in_sector(s, x, y):
			return s
	return null

func _in_sector(s: Sector, x: float, y: float) -> bool:
	var b := s.bbox
	if x < b.position.x or x > b.end.x or y < b.position.y or y > b.end.y:
		return false
	if s.is_rect:
		return true
	return U.point_in_poly(s.poly, x, y)

## Doom's four reasons a line stops a mover: the map said so, the gap is
## too short, the step is too tall, the drop is too far (monsters only).
## Empty string if it may pass.
func line_blocks(l: Line, from_z: float, height: float, monster: bool) -> String:
	if l.back == -1 or l.front == -1:
		return "solid"
	if l.blocking:
		return "blocking"
	var a := sectors[l.front]
	var b := sectors[l.back]
	var open_top := minf(a.ceil, b.ceil)
	var open_bottom := maxf(a.floor, b.floor)
	if open_top - open_bottom < height:
		return "toolow"
	if open_bottom - from_z > U.MAX_STEP:
		return "toohigh"
	if monster and from_z - open_bottom > 96.0:
		return "toofar"
	return ""

## Slide a circle by (dx, dy): the whole move, else X alone, else Y
## alone — Doom's method — substepped at half the radius so a long move
## cannot tunnel through a wall. Returns Vector3(x, y, hit).
func slide_move(x: float, y: float, dx: float, dy: float, radius: float, z: float, height: float, monster := false) -> Vector3:
	var length := sqrt(dx * dx + dy * dy)
	var max_step := maxf(1.0, radius * 0.5)
	var steps := ceili(length / max_step) if length > max_step else 1
	var sx := dx / steps
	var sy := dy / steps
	var cx := x
	var cy := y
	var hit := false
	for i in steps:
		var r := _slide_once(cx, cy, sx, sy, radius, z, height, monster)
		if r.x == cx and r.y == cy and (sx != 0.0 or sy != 0.0):
			hit = true
			break
		cx = r.x
		cy = r.y
		if r.z > 0.0:
			hit = true
	return Vector3(cx, cy, 1.0 if hit else 0.0)

func _slide_once(x: float, y: float, dx: float, dy: float, radius: float, z: float, height: float, monster: bool) -> Vector3:
	if can_move(x, y, x + dx, y + dy, radius, z, height, monster):
		return Vector3(x + dx, y + dy, 0.0)
	if dx != 0.0 and can_move(x, y, x + dx, y, radius, z, height, monster):
		return Vector3(x + dx, y, 1.0)
	if dy != 0.0 and can_move(x, y, x, y + dy, radius, z, height, monster):
		return Vector3(x, y + dy, 1.0)
	return Vector3(x, y, 1.0)

## Landing circle against the line, and the path crossing it: both,
## because a long move can land clear on the far side of a wall.
func can_move(fx: float, fy: float, tx: float, ty: float, radius: float, z: float, height: float, monster: bool) -> bool:
	var r2 := radius * radius
	for l in lines_in_box(minf(fx, tx) - radius, minf(fy, ty) - radius, maxf(fx, tx) + radius, maxf(fy, ty) + radius):
		var touching := U.seg_intersect(fx, fy, tx, ty, l.x1, l.y1, l.x2, l.y2) >= 0.0
		if not touching:
			var p := U.closest_on_seg(l.x1, l.y1, l.x2, l.y2, tx, ty)
			touching = U.dist2(p.x, p.y, tx, ty) < r2
		if touching and line_blocks(l, z, height, monster) != "":
			return false
	return true

## Can an eye at a see a point at b? A two-sided line blocks only where
## the opening at the crossing has closed past the ray.
func sight_blocked(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> bool:
	for l in lines_in_box(minf(ax, bx), minf(ay, by), maxf(ax, bx), maxf(ay, by)):
		var t := U.seg_intersect(ax, ay, bx, by, l.x1, l.y1, l.x2, l.y2)
		if t < 0.0:
			continue
		if l.front == -1 or l.back == -1 or l.block_sight:
			return true
		var z := az + (bz - az) * t
		var f := sectors[l.front]
		var b := sectors[l.back]
		var top := minf(f.ceil, b.ceil)
		var bot := maxf(f.floor, b.floor)
		if top <= bot or z < bot or z > top:
			return true
	return false

## The nearest wall a ray from a to b hits: {line, t, x, y, z} or {}.
func ray_hit_wall(ax: float, ay: float, az: float, bx: float, by: float, bz: float) -> Dictionary:
	var best: Line = null
	var best_t := INF
	for l in lines_in_box(minf(ax, bx), minf(ay, by), maxf(ax, bx), maxf(ay, by)):
		var t := U.seg_intersect(ax, ay, bx, by, l.x1, l.y1, l.x2, l.y2)
		if t < 0.0 or t >= best_t:
			continue
		var solid: bool = l.front == -1 or l.back == -1 or l.blocking
		if not solid:
			var z := az + (bz - az) * t
			var f := sectors[l.front]
			var b := sectors[l.back]
			solid = z < maxf(f.floor, b.floor) or z > minf(f.ceil, b.ceil)
		if solid:
			best_t = t
			best = l
	if best == null:
		return {}
	return {"line": best, "t": best_t, "x": ax + (bx - ax) * best_t, "y": ay + (by - ay) * best_t, "z": az + (bz - az) * best_t}
