## MEWD — polygon triangulation with holes: mapbox's earcut, which is
## what THREE.ShapeUtils.triangulateShape runs under js/mapgeo.js addFlats.
##
## A sector with holes in it — a room drawn inside another — is one ring
## bridged out to each hole and back by a slit, which is what the level
## reads; but a floor has to be triangulated from its outline AND its
## holes, or a triangulator handed the slit ring can fill a hole in (or,
## Godot's, give up). The linked list is held as parallel arrays of
## indices rather than as nodes, so there are no reference cycles.
class_name Earcut

var X := PackedFloat64Array()
var Y := PackedFloat64Array()
var I := PackedInt32Array()       # the vertex each node is
var P := PackedInt32Array()       # prev
var N := PackedInt32Array()       # next
var Z := PackedInt32Array()       # z-order
var PZ := PackedInt32Array()
var NZ := PackedInt32Array()
var ST := PackedByteArray()       # steiner
var tris := PackedInt32Array()
var min_x := 0.0
var min_y := 0.0
var inv := 0.0

## Triangles (vertex indices into outline + holes, concatenated) of the
## outline with the holes cut out of it; each triangle wound the same
## way as a counter-clockwise ring.
static func triangulate(outline: PackedVector2Array, holes: Array) -> PackedInt32Array:
	var e := Earcut.new()
	var pts := outline.duplicate()
	var starts := []
	for h in holes:
		starts.append(pts.size())
		pts.append_array(h)
	e._run(pts, outline.size(), starts)
	var out := e.tris
	for t in range(0, out.size(), 3):
		var a := pts[out[t]]
		var b := pts[out[t + 1]]
		var c := pts[out[t + 2]]
		if (b - a).cross(c - a) < 0:
			var k := out[t + 1]
			out[t + 1] = out[t + 2]
			out[t + 2] = k
	return out

func _node(i: int, x: float, y: float) -> int:
	var n := X.size()
	X.append(x); Y.append(y); I.append(i)
	P.append(-1); N.append(-1); Z.append(0); PZ.append(-1); NZ.append(-1); ST.append(0)
	return n

func _insert(i: int, x: float, y: float, last: int) -> int:
	var p := _node(i, x, y)
	if last == -1:
		P[p] = p
		N[p] = p
	else:
		N[p] = N[last]
		P[p] = last
		P[N[last]] = p
		N[last] = p
	return p

func _remove(p: int) -> void:
	P[N[p]] = P[p]
	N[P[p]] = N[p]
	if PZ[p] != -1:
		NZ[PZ[p]] = NZ[p]
	if NZ[p] != -1:
		PZ[NZ[p]] = PZ[p]

func _area(p: int, q: int, r: int) -> float:
	return (Y[q] - Y[p]) * (X[r] - X[q]) - (X[q] - X[p]) * (Y[r] - Y[q])

func _eq(a: int, b: int) -> bool:
	return X[a] == X[b] and Y[a] == Y[b]

static func _signed(pts: PackedVector2Array, s: int, e: int) -> float:
	var sum := 0.0
	var j := e - 1
	for i in range(s, e):
		sum += (pts[j].x - pts[i].x) * (pts[i].y + pts[j].y)
		j = i
	return sum

func _linked(pts: PackedVector2Array, s: int, e: int, clockwise: bool) -> int:
	var last := -1
	if clockwise == (_signed(pts, s, e) > 0):
		for i in range(s, e):
			last = _insert(i, pts[i].x, pts[i].y, last)
	else:
		for i in range(e - 1, s - 1, -1):
			last = _insert(i, pts[i].x, pts[i].y, last)
	if last != -1 and _eq(last, N[last]):
		var nx := N[last]
		_remove(last)
		last = nx
	return last

func _run(pts: PackedVector2Array, outer_len: int, starts: Array) -> void:
	var outer := _linked(pts, 0, outer_len, true)
	if outer == -1 or N[outer] == P[outer]:
		return
	if not starts.is_empty():
		outer = _eliminate_holes(pts, starts, outer)
	if pts.size() > 80:
		var mnx := pts[0].x
		var mny := pts[0].y
		var mxx := mnx
		var mxy := mny
		for i in range(1, outer_len):
			mnx = minf(mnx, pts[i].x); mny = minf(mny, pts[i].y)
			mxx = maxf(mxx, pts[i].x); mxy = maxf(mxy, pts[i].y)
		min_x = mnx
		min_y = mny
		inv = maxf(mxx - mnx, mxy - mny)
		inv = 32767.0 / inv if inv != 0 else 0.0
	_earcut_linked(outer, 0)

func _filter(start: int, end := -1) -> int:
	if start == -1:
		return start
	if end == -1:
		end = start
	var p := start
	while true:
		var again := false
		if not ST[p] and (_eq(p, N[p]) or _area(P[p], p, N[p]) == 0):
			_remove(p)
			p = P[p]
			end = p
			if p == N[p]:
				break
			again = true
		else:
			p = N[p]
		if not again and p == end:
			break
	return end

func _earcut_linked(ear: int, pas: int) -> void:
	if ear == -1:
		return
	if pas == 0 and inv != 0.0:
		_index_curve(ear)
	var stop := ear
	while P[ear] != N[ear]:
		var prev := P[ear]
		var next := N[ear]
		if _is_ear_hashed(ear) if inv != 0.0 else _is_ear(ear):
			tris.append(I[prev]); tris.append(I[ear]); tris.append(I[next])
			_remove(ear)
			ear = N[next]
			stop = N[next]
			continue
		ear = next
		if ear == stop:
			if pas == 0:
				_earcut_linked(_filter(ear), 1)
			elif pas == 1:
				ear = _cure(_filter(ear))
				_earcut_linked(ear, 2)
			elif pas == 2:
				_split(ear)
			break

func _pit(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, px: float, py: float) -> bool:
	return (cx - px) * (ay - py) >= (ax - px) * (cy - py) and (ax - px) * (by - py) >= (bx - px) * (ay - py) \
		and (bx - px) * (cy - py) >= (cx - px) * (by - py)

func _is_ear(ear: int) -> bool:
	var a := P[ear]
	var c := N[ear]
	if _area(a, ear, c) >= 0:
		return false
	var ax := X[a]; var bx := X[ear]; var cx := X[c]
	var ay := Y[a]; var by := Y[ear]; var cy := Y[c]
	var x0 := minf(ax, minf(bx, cx)); var y0 := minf(ay, minf(by, cy))
	var x1 := maxf(ax, maxf(bx, cx)); var y1 := maxf(ay, maxf(by, cy))
	var p := N[c]
	while p != a:
		if X[p] >= x0 and X[p] <= x1 and Y[p] >= y0 and Y[p] <= y1 and _pit(ax, ay, bx, by, cx, cy, X[p], Y[p]) \
				and _area(P[p], p, N[p]) >= 0:
			return false
		p = N[p]
	return true

func _is_ear_hashed(ear: int) -> bool:
	var a := P[ear]
	var c := N[ear]
	if _area(a, ear, c) >= 0:
		return false
	var ax := X[a]; var bx := X[ear]; var cx := X[c]
	var ay := Y[a]; var by := Y[ear]; var cy := Y[c]
	var x0 := minf(ax, minf(bx, cx)); var y0 := minf(ay, minf(by, cy))
	var x1 := maxf(ax, maxf(bx, cx)); var y1 := maxf(ay, maxf(by, cy))
	var min_z := _zorder(x0, y0)
	var max_z := _zorder(x1, y1)
	var p := PZ[ear]
	var n := NZ[ear]
	while p != -1 and Z[p] >= min_z and n != -1 and Z[n] <= max_z:
		if _blocks(p, a, c, x0, y0, x1, y1, ax, ay, bx, by, cx, cy):
			return false
		p = PZ[p]
		if _blocks(n, a, c, x0, y0, x1, y1, ax, ay, bx, by, cx, cy):
			return false
		n = NZ[n]
	while p != -1 and Z[p] >= min_z:
		if _blocks(p, a, c, x0, y0, x1, y1, ax, ay, bx, by, cx, cy):
			return false
		p = PZ[p]
	while n != -1 and Z[n] <= max_z:
		if _blocks(n, a, c, x0, y0, x1, y1, ax, ay, bx, by, cx, cy):
			return false
		n = NZ[n]
	return true

func _blocks(p: int, a: int, c: int, x0: float, y0: float, x1: float, y1: float, ax: float, ay: float, bx: float, by: float, cx: float, cy: float) -> bool:
	return X[p] >= x0 and X[p] <= x1 and Y[p] >= y0 and Y[p] <= y1 and p != a and p != c \
		and _pit(ax, ay, bx, by, cx, cy, X[p], Y[p]) and _area(P[p], p, N[p]) >= 0

func _cure(start: int) -> int:
	var p := start
	while true:
		var a := P[p]
		var b := N[N[p]]
		if not _eq(a, b) and _intersects(a, p, N[p], b) and _locally_inside(a, b) and _locally_inside(b, a):
			tris.append(I[a]); tris.append(I[p]); tris.append(I[b])
			_remove(p)
			_remove(N[p])
			p = b
			start = b
		p = N[p]
		if p == start:
			break
	return _filter(p)

func _split(start: int) -> void:
	var a := start
	while true:
		var b := N[N[a]]
		while b != P[a]:
			if I[a] != I[b] and _valid_diagonal(a, b):
				var c := _split_polygon(a, b)
				a = _filter(a, N[a])
				c = _filter(c, N[c])
				_earcut_linked(a, 0)
				_earcut_linked(c, 0)
				return
			b = N[b]
		a = N[a]
		if a == start:
			break

func _eliminate_holes(pts: PackedVector2Array, starts: Array, outer: int) -> int:
	var queue := []
	for k in starts.size():
		var s: int = starts[k]
		var e: int = starts[k + 1] if k < starts.size() - 1 else pts.size()
		var list := _linked(pts, s, e, false)
		if list == -1:
			continue
		if list == N[list]:
			ST[list] = 1
		queue.append(_leftmost(list))
	queue.sort_custom(func(a, b): return X[a] < X[b])
	for h in queue:
		outer = _eliminate_hole(h, outer)
	return outer

func _eliminate_hole(hole: int, outer: int) -> int:
	var br := _find_bridge(hole, outer)
	if br == -1:
		return outer
	var rev := _split_polygon(br, hole)
	_filter(rev, N[rev])
	return _filter(br, N[br])

func _find_bridge(hole: int, outer: int) -> int:
	var p := outer
	var hx := X[hole]
	var hy := Y[hole]
	var qx := -INF
	var m := -1
	while true:
		var n := N[p]
		if hy <= Y[p] and hy >= Y[n] and Y[n] != Y[p]:
			var x := X[p] + (hy - Y[p]) * (X[n] - X[p]) / (Y[n] - Y[p])
			if x <= hx and x > qx:
				qx = x
				m = p if X[p] < X[n] else n
				if x == hx:
					return m
		p = n
		if p == outer:
			break
	if m == -1:
		return -1
	var stop := m
	var mx := X[m]
	var my := Y[m]
	var tan_min := INF
	p = m
	while true:
		if hx >= X[p] and X[p] >= mx and hx != X[p] and \
				_pit(hx if hy < my else qx, hy, mx, my, qx if hy < my else hx, hy, X[p], Y[p]):
			var tan := absf(hy - Y[p]) / (hx - X[p])
			if _locally_inside(p, hole) and (tan < tan_min or (tan == tan_min and (X[p] > X[m] or (X[p] == X[m] and _sector_contains(m, p))))):
				m = p
				tan_min = tan
		p = N[p]
		if p == stop:
			break
	return m

func _sector_contains(m: int, p: int) -> bool:
	return _area(P[m], m, P[p]) < 0 and _area(N[p], m, N[m]) < 0

func _index_curve(start: int) -> void:
	var p := start
	while true:
		if Z[p] == 0:
			Z[p] = _zorder(X[p], Y[p])
		PZ[p] = P[p]
		NZ[p] = N[p]
		p = N[p]
		if p == start:
			break
	NZ[PZ[p]] = -1
	PZ[p] = -1
	_sort_linked(p)

func _sort_linked(list: int) -> int:
	var in_size := 1
	while true:
		var p := list
		list = -1
		var tail := -1
		var merges := 0
		while p != -1:
			merges += 1
			var q := p
			var p_size := 0
			for i in in_size:
				p_size += 1
				q = NZ[q]
				if q == -1:
					break
			var q_size := in_size
			while p_size > 0 or (q_size > 0 and q != -1):
				var e: int
				if p_size != 0 and (q_size == 0 or q == -1 or Z[p] <= Z[q]):
					e = p
					p = NZ[p]
					p_size -= 1
				else:
					e = q
					q = NZ[q]
					q_size -= 1
				if tail != -1:
					NZ[tail] = e
				else:
					list = e
				PZ[e] = tail
				tail = e
			p = q
		NZ[tail] = -1
		in_size *= 2
		if merges <= 1:
			break
	return list

func _zorder(x: float, y: float) -> int:
	var xi := int((x - min_x) * inv) & 0xFFFFFFFF
	var yi := int((y - min_y) * inv) & 0xFFFFFFFF
	xi = (xi | (xi << 8)) & 0x00FF00FF
	xi = (xi | (xi << 4)) & 0x0F0F0F0F
	xi = (xi | (xi << 2)) & 0x33333333
	xi = (xi | (xi << 1)) & 0x55555555
	yi = (yi | (yi << 8)) & 0x00FF00FF
	yi = (yi | (yi << 4)) & 0x0F0F0F0F
	yi = (yi | (yi << 2)) & 0x33333333
	yi = (yi | (yi << 1)) & 0x55555555
	return xi | (yi << 1)

func _leftmost(start: int) -> int:
	var p := start
	var left := start
	while true:
		if X[p] < X[left] or (X[p] == X[left] and Y[p] < Y[left]):
			left = p
		p = N[p]
		if p == start:
			break
	return left

func _valid_diagonal(a: int, b: int) -> bool:
	return I[N[a]] != I[b] and I[P[a]] != I[b] and not _intersects_polygon(a, b) and \
		((_locally_inside(a, b) and _locally_inside(b, a) and _middle_inside(a, b) and \
			(_area(P[a], a, P[b]) != 0 or _area(a, P[b], b) != 0)) or \
		(_eq(a, b) and _area(P[a], a, N[a]) > 0 and _area(P[b], b, N[b]) > 0))

static func _sgn(v: float) -> int:
	return 1 if v > 0 else (-1 if v < 0 else 0)

func _on_seg(p: int, q: int, r: int) -> bool:
	return X[q] <= maxf(X[p], X[r]) and X[q] >= minf(X[p], X[r]) and Y[q] <= maxf(Y[p], Y[r]) and Y[q] >= minf(Y[p], Y[r])

func _intersects(p1: int, q1: int, p2: int, q2: int) -> bool:
	var o1 := _sgn(_area(p1, q1, p2))
	var o2 := _sgn(_area(p1, q1, q2))
	var o3 := _sgn(_area(p2, q2, p1))
	var o4 := _sgn(_area(p2, q2, q1))
	if o1 != o2 and o3 != o4:
		return true
	if o1 == 0 and _on_seg(p1, p2, q1):
		return true
	if o2 == 0 and _on_seg(p1, q2, q1):
		return true
	if o3 == 0 and _on_seg(p2, p1, q2):
		return true
	if o4 == 0 and _on_seg(p2, q1, q2):
		return true
	return false

func _intersects_polygon(a: int, b: int) -> bool:
	var p := a
	while true:
		if I[p] != I[a] and I[N[p]] != I[a] and I[p] != I[b] and I[N[p]] != I[b] and _intersects(p, N[p], a, b):
			return true
		p = N[p]
		if p == a:
			break
	return false

func _locally_inside(a: int, b: int) -> bool:
	if _area(P[a], a, N[a]) < 0:
		return _area(a, b, N[a]) >= 0 and _area(a, P[a], b) >= 0
	return _area(a, b, P[a]) < 0 or _area(a, N[a], b) < 0

func _middle_inside(a: int, b: int) -> bool:
	var p := a
	var inside := false
	var px := (X[a] + X[b]) / 2.0
	var py := (Y[a] + Y[b]) / 2.0
	while true:
		var n := N[p]
		if ((Y[p] > py) != (Y[n] > py)) and Y[n] != Y[p] and (px < (X[n] - X[p]) * (py - Y[p]) / (Y[n] - Y[p]) + X[p]):
			inside = not inside
		p = n
		if p == a:
			break
	return inside

func _split_polygon(a: int, b: int) -> int:
	var a2 := _node(I[a], X[a], Y[a])
	var b2 := _node(I[b], X[b], Y[b])
	var an := N[a]
	var bp := P[b]
	N[a] = b; P[b] = a
	N[a2] = an; P[an] = a2
	N[b2] = a2; P[a2] = b2
	N[bp] = b2; P[b2] = bp
	return b2
