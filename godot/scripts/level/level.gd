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
##
## ROOM OVER ROOM (js/level.js's COLUMNS). A COLUMN is a stack of sectors
## over one outline — a ground floor, a first floor over it — built by
## add_column; every other sector is a column of one, which is every
## sector of every map that is not drawn in LAYERS, and for those nothing
## below costs or answers anything different. A point is in one column
## (sector_at, which answers with the column's GROUND storey, as the web
## build's sectorAt does) and in the storey of it that its HEIGHT is in
## (span_in / span_at: the one whose floor..ceiling holds z, or the
## highest one under it). A line joins two whole columns (front_col,
## back_col, bottom-up), and what it does to a mover, a ray or an eye is
## asked of the two storeys at that height — so a hall's door is a door
## and the landing over it is a wall. Between storeys is a DECK, DECK
## thick: the ceiling of the one under is that far under the floor of
## the one over, and the slab between is solid — to a mover, a ray and
## an eye, and drawn round its edge (the web build's decks have no
## thickness). A roof is as thick, over the ceiling of the room it
## roofs.
## A two-sided line of a column is drawn as its BANDS — every interval
## of z where exactly one side is open (line_bands) — and its HOLES,
## where both are. Rays and eyes (ray_hit_flat, and sight_blocked on a
## layered level) also stop at the floors and decks of the columns they
## pass through, so nothing is seen or shot through a floor.
class_name Level
extends RefCounted

const BLOCK := 128.0
const WELD := 0.5
const ZEPS := 1e-6
## how thick every deck between two storeys, and every roof, is
const DECK := 16.0

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
	# what the map compiler (DocCompile) hangs on a sector of an edited
	# map — see compileCore in js/editor/doc.js:
	var doc_id = null                     # the document sector it is (a line's SIDES key)
	var tint = null                       # Doom 64's colours: {floor, ceil, thing, top, bottom} -> Color
	var fog = null                        # its own fog: Color(r, g, b, density 0..100), or null
	var roof_tex := ""                    # a roofed room seen from above
	var flat_outer := PackedVector2Array()   # a sector with holes: its outline...
	var flat_holes: Array = []               # ...and the holes, for its floor
	# ITS COLUMN (js/level.js): the ground storey's index (its own, for a
	# column of one), which storey of it this is, and the ones over and
	# under it (-1 for none)
	var col_base := 0
	var storey := 0
	var above := -1
	var below := -1

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
	# the line overrides of an edited map (applyLine in js/editor/doc.js)
	var xscale := 1.0
	var yscale := 1.0
	var sides := {}                       # str(doc sector id) -> {tex, midTex, xoff, yoff, xscale, yscale}
	var mid_once := false                 # a two-sided middle drawn once, its own height
	var mid_height = null
	var exterior := false                 # a building's outside wall (roofed against open air)
	# THE TWO COLUMNS it joins, bottom-up (front and back are their ground
	# storeys), and — only where either is more than one storey — the
	# bands to draw ({z0, z1, open, from, kind, open_front, tex}) and the
	# holes ({z0, z1, front, back}); mid_z: the openings a blocking middle
	# fills, [Vector2(z0, z1)], empty for all of them (a map in layers)
	var front_col := PackedInt32Array()
	var back_col := PackedInt32Array()
	var front_base := -1
	var back_base := -1
	var multi := false
	var bands: Array = []
	var holes: Array = []
	var mid_z: Array = []
	var door: Door = null                 # a door in it (Doors, DocCompile)

## A DOOR (the Godot build's own; a line override `door` in an edited
## map): a slab across the line from a to b, z0..top, that swings (on a
## hinge at a) or slides (along the line, into the wall past b) open,
## and over it a LINTEL up to lintel_top. Shut, it stops movers, rays
## and eyes on its lines; open, only the lintel does. `open` 0..1 is
## run by Doors (game/doors.gd): it opens as someone comes to it (auto)
## or on the use key, and shuts again when nobody is in it.
class Door:
	var index := 0
	var a := Vector2()
	var b := Vector2()
	var inside := Vector2()     # the normal it swings towards
	var depth := 6.0            # how thick the slab is
	var wall := 0.0             # how thick the wall it is in is, out of the room (0: a line)
	var z0 := 0.0
	var top := 96.0
	var lintel_top := 96.0
	var tex := "DOOR3"
	var lintel_tex := "GRIDWALL"
	var style := "swing"        # or "slide"
	var auto := true
	var locked := false
	var open := 0.0
	var target := 0.0
	var wait := 0
	var lines: Array = []
	## shut to something at z..z+h (anything short of wide open is shut)
	func shut_to(z: float, h: float) -> bool:
		return open < 0.95 and z < top - 0.5 and z + h > z0 + 0.5
	## the lintel over it, in the way of something z..z+h
	func lintel_to(z: float, h: float) -> bool:
		return lintel_top > top + 0.5 and z + h > top + 0.5 and z < lintel_top - 0.5
	## a point at height z on it stops a ray or an eye
	func stops(z: float) -> bool:
		return (open < 0.5 and z >= z0 and z <= top) or (lintel_top > top + 0.5 and z > top and z <= lintel_top)

var name := ""
var verts := PackedVector2Array()
var sectors: Array[Sector] = []
var lines: Array[Line] = []
var things: Array = []
var world := {}
var bounds := Rect2()
## FREE BOXES (level.props in js/editor/doc.js): {x0, y0, x1, y1, z0, z1,
## tex, topTex, light, sky, tint (Color or null), fog (Color or null)} —
## drawn by MapGeo, owned by no sector, and solid to nothing (as in the
## web build: see boxGeometry in js/mapgeo.js)
var props: Array = []
## the placed and scattered plants, {kind, x, y, scale}, for the forest
var plants: Array = []
## the DOORS (Door), each on its lines
var doors: Array = []
## the map's own light (mapLightOf in js/editor/doc.js): lightColor,
## ambient (Color, times its amount), fogAmbient, fog (Color, a = density)
var map_light := {}
## whether any surface needs the tinted world shader (colours, fog, a
## map light, two-faced walls) — MapGeo reads it
var tinted := false
## ROOM OVER ROOM: whether any column is more than one storey. False for
## every map that is not in layers, and then every question below is
## asked exactly as it always was.
var layered := false
## three columns meeting on one edge: a map error, counted (MapBuilder's)
var edge_conflicts := 0

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
	s.col_base = int(p.get("__colBase", s.index))
	s.storey = int(p.get("__storey", 0))
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

## A COLUMN: one outline, several storeys, bottom-up (MapBuilder.column).
## Each storey's floor must be at or over the ceiling of the one under
## it; returns the sectors' indices, the ground first.
func add_column(poly: PackedVector2Array, storeys: Array) -> PackedInt32Array:
	var base := sectors.size()
	var out := PackedInt32Array()
	for k in storeys.size():
		var p: Dictionary = storeys[k].duplicate()
		p["__colBase"] = base
		p["__storey"] = k
		out.append(add_sector(poly, p))
	for k in out.size():
		var s := sectors[out[k]]
		s.above = out[k + 1] if k + 1 < out.size() else -1
		s.below = out[k - 1] if k > 0 else -1
	if out.size() > 1:
		layered = true
	return out

## Doom's convention: a line's FRONT is on its right, so the line is
## stored b->a and the sector on the left of a->b is its front. If the
## edge exists already, this sector is its back. Every storey of one
## column walks the same ring the same way round, so they pile onto one
## side of the line: that is what makes a column a column down here.
func _edge(a: int, b: int, sec: int) -> void:
	if a == b:
		return
	var base := sectors[sec].col_base
	var key := Vector2i(mini(a, b), maxi(a, b))
	var l: Line = _edges.get(key)
	if l == null:
		l = Line.new()
		l.index = lines.size()
		l.v1 = b
		l.v2 = a
		l.front = sec
		l.front_col.append(sec)
		l.front_base = base
		l.middle = sectors[sec].wall_tex
		lines.append(l)
		_edges[key] = l
		return
	if l.v1 == b and l.v2 == a:
		if l.front_base != base:
			edge_conflicts += 1
			return
		l.front_col.append(sec)
		return
	if l.back_base == -1:
		l.back_base = base
		l.back = sec
	elif l.back_base != base:
		edge_conflicts += 1
		return
	l.back_col.append(sec)
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
		# every two-sided line of a map in storeys is drawn and asked as
		# its bands, as the web build draws every line
		l.multi = layered or l.front_col.size() > 1 or l.back_col.size() > 1
		if l.multi:
			assign_bands(l)
		else:
			l.lower = (f if f.floor >= b.floor else b).lower_tex
			l.upper = (f if f.ceil <= b.ceil else b).upper_tex
		# every storey of both columns: a first-floor room has its doors
		for i in l.front_col:
			sectors[i].lines.append(l)
		for i in l.back_col:
			sectors[i].lines.append(l)
	for l in lines:
		if l.back == -1:
			for i in l.front_col:
				sectors[i].lines.append(l)
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
	# THE GROUND STOREYS ONLY: the storeys over one share its outline, and
	# whoever wants them walks the column (span_in)
	for s in sectors:
		if s.col_base != s.index:
			continue
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
##
## THE GROUND STOREY of the column, always, whatever is stacked over it
## (sectorAt): the storey you are actually in is span_at's business.
func sector_at(x: float, y: float, hint: Sector = null) -> Sector:
	if hint != null:
		var g := hint if hint.col_base == hint.index else sectors[hint.col_base]
		if _in_sector(g, x, y):
			return g
	for s in block_sectors[_row(y) * cols + _col(x)]:
		if _in_sector(s, x, y):
			return s
	return null

## WHICH STOREY (spanIn): walk the column from any sector of it and
## return the one whose floor..ceiling holds z, or the highest one below
## it — never null for a real sector (in a deck, the one under it). Feet
## on the floor of a storey with a room under it stand in that storey. A column of one answers
## with itself, in one comparison.
func span_in(s: Sector, z: float) -> Sector:
	if s == null:
		return null
	var cur := sectors[s.col_base]
	if cur.above == -1:
		return cur
	var best := cur
	while cur != null:
		var up: Sector = sectors[cur.above] if cur.above != -1 else null
		if z >= cur.floor - ZEPS and z <= cur.ceil + ZEPS:
			if not (up != null and z >= cur.ceil - ZEPS and absf(up.floor - cur.ceil) <= ZEPS):
				return cur
		if cur.floor <= z:
			best = cur
		cur = up
	return best

## THE STOREY A BODY STANDING AT z IS ON: the highest of the column whose
## floor is within a step of its feet — so the top of a stair a step
## under a deck's floor steps up onto it, where span_in would say the
## room under it. (The web build asks span_in, and its stairs have to
## end AT the deck.) A column of one answers with itself.
func stand_in(s: Sector, z: float) -> Sector:
	if s == null:
		return null
	var cur := sectors[s.col_base]
	if cur.above == -1:
		return cur
	var best := cur
	while cur != null:
		if cur.floor <= z + U.MAX_STEP + ZEPS and cur.ceil - cur.floor > ZEPS:
			best = cur
		cur = sectors[cur.above] if cur.above != -1 else null
	return best

## The storey at (x, y, z) (spanAt), or null off the map.
func span_at(x: float, y: float, z: float, hint: Sector = null) -> Sector:
	var g := sector_at(x, y, hint)
	if g == null or g.above == -1:
		return g
	return span_in(g, z)

## The top storey of s's column: what the sky rains on.
func top_of(s: Sector) -> Sector:
	var c := sectors[s.col_base]
	while c.above != -1:
		c = sectors[c.above]
	return c

## Every storey over (x, y), bottom-up (columnAt).
func column_at(x: float, y: float) -> Array:
	var out := []
	var c := sector_at(x, y)
	while c != null:
		out.append(c)
		c = sectors[c.above] if c.above != -1 else null
	return out

## The storey of `s`'s column a body standing at z is in: its ground
## sector unless the column has storeys (the cheap case first).
func storey_of(s: Sector, z: float) -> Sector:
	if s == null:
		return null
	if s.above == -1 and s.below == -1:
		return s
	return span_in(s, z)

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
##
## THE OPENING IS BETWEEN THE TWO STOREYS AT THE MOVER'S OWN HEIGHT: in
## the hall you may walk through the front door; on the landing over it
## you may not, and the line is the same line.
func line_blocks(l: Line, from_z: float, height: float, monster: bool) -> String:
	if l.back == -1 or l.front == -1:
		return "solid"
	if l.door != null:
		if l.door.shut_to(from_z, height):
			return "door"
		if l.door.lintel_to(from_z, height):
			return "toolow"
	if l.blocking:
		if l.mid_z.is_empty():
			return "blocking"
		# walled in some of its openings only (a map in layers): blocks
		# at those heights and not at the others
		for m in l.mid_z:
			if from_z < m.y - 0.5 and from_z + height > m.x + 0.5:
				return "blocking"
	var a := sectors[l.front]
	var b := sectors[l.back]
	if l.multi:
		a = stand_in(a, from_z)
		b = stand_in(b, from_z)
	var open_top := minf(a.ceil, b.ceil)
	var open_bottom := maxf(a.floor, b.floor)
	if open_top - open_bottom < height:
		return "toolow"
	# a body in the air under a deck does not go through it head first
	if l.multi and from_z + height > open_top + 0.5 and from_z >= open_bottom:
		return "toolow"
	if open_bottom - from_z > U.MAX_STEP:
		return "toohigh"
	if monster and from_z - open_bottom > 96.0:
		return "toofar"
	# ON A MAP IN STOREYS the drop is to the LOWER floor: the crowd does
	# not walk off the edge of a terrace (Doom's dropoff, which the web
	# build's max-of-the-floors never trips)
	if monster and l.multi and from_z - minf(a.floor, b.floor) > 96.0:
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
		var z := az + (bz - az) * t
		if l.front == -1 or l.back == -1:
			return true
		if l.block_sight and (l.mid_z.is_empty() or _in_mid_z(l, z)):
			return true
		if l.door != null and l.door.stops(z):
			return true
		var f := sectors[l.front]
		var b := sectors[l.back]
		if l.multi:
			f = span_in(f, z)
			b = span_in(b, z)
		var top := minf(f.ceil, b.ceil)
		var bot := maxf(f.floor, b.floor)
		if top <= bot or z < bot or z > top:
			return true
	# and on a map in storeys, the floors and decks in the way: nobody is
	# seen through a floor
	if layered and ray_hit_flat(ax, ay, az, bx, by, bz, false).size() > 0:
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
		if solid and l.blocking and not l.mid_z.is_empty() and l.back != -1:
			# walled in some openings only: a round over the terrace flies on
			solid = _in_mid_z(l, az + (bz - az) * t)
		if not solid and l.door != null:
			solid = l.door.stops(az + (bz - az) * t)
		if not solid:
			var z := az + (bz - az) * t
			var f := sectors[l.front]
			var b := sectors[l.back]
			if l.multi:
				f = span_in(f, z)
				b = span_in(b, z)
			solid = z < maxf(f.floor, b.floor) or z > minf(f.ceil, b.ceil)
		if solid:
			best_t = t
			best = l
	if best == null:
		return {}
	return {"line": best, "t": best_t, "x": ax + (bx - ax) * best_t, "y": ay + (by - ay) * best_t, "z": az + (bz - az) * best_t}

static func _in_mid_z(l: Line, z: float) -> bool:
	for m in l.mid_z:
		if z >= m.x and z <= m.y:
			return true
	return false

## THE FLOORS AND CEILINGS A RAY MEETS on a map in storeys: the segment
## walked column by column through the lines it crosses, and in each
## column the first of its planes it passes through — the bottom floor,
## every deck between two storeys, the top storey's ceiling unless that
## is the sky (the open air over a roof or a terrace is air, and a ray up
## there is stopped by nothing but a roof it comes down onto). {t, z, up}
## (up: it struck the underside of something), or {} if nothing. `skies`:
## whether a sky ceiling stops it as well (a bullet into the sky does
## not; nothing wants that yet).
func ray_hit_flat(ax: float, ay: float, az: float, bx: float, by: float, bz: float, skies := false) -> Dictionary:
	var cur := sector_at(ax, ay)
	if cur == null:
		return {}
	var dz := bz - az
	var cross := []
	for l in lines_in_box(minf(ax, bx), minf(ay, by), maxf(ax, bx), maxf(ay, by)):
		if l.back == -1 or l.front == -1:
			continue
		var t := U.seg_intersect(ax, ay, bx, by, l.x1, l.y1, l.x2, l.y2)
		if t >= 0.0:
			cross.append([t, l])
	cross.sort_custom(func(p, q): return p[0] < q[0])
	cross.append([1.0, null])
	var t0 := 0.0
	var base := cur.col_base
	for c in cross:
		var t1: float = c[0]
		if t1 > t0 and dz != 0.0:
			var z0 := az + dz * t0
			var z1 := az + dz * t1
			var g := sectors[base]
			var best_t := INF
			var best_z := 0.0
			while g != null:
				for k in 2:
					var pz: float = g.floor if k == 0 else g.ceil
					if k == 1 and g.above == -1 and g.ceil_tex == "SKY" and not skies:
						continue
					if (z0 - pz) * (z1 - pz) < 0.0 or (z1 == pz and z0 != pz):
						var tp := (pz - az) / dz
						if tp < best_t:
							best_t = tp
							best_z = pz
				g = sectors[g.above] if g.above != -1 else null
			if best_t < INF:
				return {"t": clampf(best_t, 0.0, 1.0), "z": best_z, "up": dz > 0.0}
		var l: Line = c[1]
		if l == null:
			break
		base = l.back_base if base == l.front_base else l.front_base
		t0 = t1
	return {}

## THE BANDS AND HOLES OF A LINE BETWEEN TWO COLUMNS (lineBands and
## assignLineTextures in js/level.js): every interval where exactly one
## column is open is a band — the face of whatever is in the way, in the
## skin of the storey that is SHUT there (its lower where the band's top
## is its floor, its upper where the band's bottom is its ceiling) — and
## every interval where both are is a hole. l.upper and l.lower stay the
## first band of each kind, for what reads them by those names.
func assign_bands(l: Line) -> void:
	var Fall := []
	var Ball := []
	for i in l.front_col:
		Fall.append(sectors[i])
	for i in l.back_col:
		Ball.append(sectors[i])
	var F := _open_spans(Fall)
	var B := _open_spans(Ball)
	var cuts := PackedFloat64Array()
	for s in F + B:
		cuts.append(s.floor)
		cuts.append(s.ceil)
	# and every storey's own heights, the solid ones too (a building's
	# wall, floor at its ceiling): where the wall ends and the sky begins
	for s in Fall + Ball:
		cuts.append(s.floor)
		cuts.append(s.ceil)
	cuts.sort()
	l.bands = []
	l.holes = []
	for i in cuts.size() - 1:
		var z0 := cuts[i]
		var z1 := cuts[i + 1]
		if z1 - z0 <= ZEPS:
			continue
		var m := (z0 + z1) / 2.0
		var f: Sector = _covering(F, m)
		var b: Sector = _covering(B, m)
		if f != null and b != null:
			l.holes.append({"z0": z0, "z1": z1, "front": f, "back": b})
			continue
		if f == null and b == null:
			continue
		var open := f if f != null else b
		var shut := Ball if f != null else Fall
		var from: Sector = null
		var kind := "lower"
		for s in shut:
			if absf(s.floor - z1) <= ZEPS:
				from = s
				break
		if from == null:
			for s in shut:
				if absf(s.ceil - z0) <= ZEPS:
					from = s
					kind = "upper"
					break
		if from == null:
			var lowest: Sector = shut[0]
			var highest: Sector = shut[0]
			for s in shut:
				if s.floor < lowest.floor:
					lowest = s
				if s.ceil > highest.ceil:
					highest = s
			if z1 <= lowest.floor + ZEPS:
				from = lowest
			else:
				from = highest
				kind = "upper"
		# THE EDGE OF A DECK: shut between a storey's ceiling and the
		# floor of the one over it
		var deck := false
		if kind == "lower" and from.below != -1 and absf(sectors[from.below].ceil - z0) <= ZEPS:
			deck = true
		l.bands.append({"z0": z0, "z1": z1, "open": open, "from": from, "kind": kind, "open_front": f != null,
			"tex": from.upper_tex if kind == "upper" else from.lower_tex, "deck": deck})
	var fs := sectors[l.front]
	var bs := sectors[l.back]
	var up = null
	var lo = null
	for bd in l.bands:
		if up == null and bd.kind == "upper":
			up = bd.tex
		if lo == null and bd.kind == "lower":
			lo = bd.tex
	l.upper = up if up != null else (fs if fs.ceil <= bs.ceil else bs).upper_tex
	l.lower = lo if lo != null else (fs if fs.floor >= bs.floor else bs).lower_tex

## Put a line's own upper and lower on its bands (a line override).
func lock_band_textures(l: Line) -> void:
	for bd in l.bands:
		bd.tex = l.upper if bd.kind == "upper" else l.lower

static func _open_spans(col: Array) -> Array:
	var out := []
	for s in col:
		if s.ceil - s.floor > ZEPS:
			out.append(s)
	out.sort_custom(func(p, q): return p.floor < q.floor)
	return out

static func _covering(spans: Array, z: float) -> Sector:
	for s in spans:
		if z >= s.floor and z <= s.ceil:
			return s
	return null
