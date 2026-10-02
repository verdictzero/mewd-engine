## MEWD Editor — the edits a person makes, on the document itself: a
## vertex put down that splits the edge it lands on, a new block cut out
## of the one it is drawn in, a block split along a path, two merged
## across a line, a selection moved, and the shapes the Shape tool draws.
class_name EdOps

## how near a line a point is ON it
const ON_LINE := 0.5

## THE SHAPES a drag draws in Shape mode (R), fitted to the box dragged.
const SHAPES := {
	"rect": {"name": "Rectangle"},
	"ellipse": {"name": "Ellipse", "sides": 16},
	"circle": {"name": "Circle", "sides": 16},
	"polygon": {"name": "Polygon", "sides": 6},
	"triangle": {"name": "Triangle"},
	"diamond": {"name": "Diamond"},
	"star": {"name": "Star", "sides": 5},
	"lshape": {"name": "L-shape"},
	"arch": {"name": "Half-round", "sides": 12},
}
const SIDES_MIN := 3
const SIDES_MAX := 64

## The corners of shape `kind` in the box from a to b: anticlockwise, on
## whole units. A circle is the largest that fits, from the corner the
## drag started at.
static func shape_points(kind: String, a: Vector2, b: Vector2, sides = null) -> PackedVector2Array:
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y)
	if kind == "circle":
		var r := minf(x1 - x0, y1 - y0)
		x0 = a.x - r if b.x < a.x else a.x
		y0 = a.y - r if b.y < a.y else a.y
		x1 = x0 + r
		y1 = y0 + r
	var cx := (x0 + x1) / 2.0
	var cy := (y0 + y1) / 2.0
	var rx := (x1 - x0) / 2.0
	var ry := (y1 - y0) / 2.0
	var want = sides if sides != null else SHAPES.get(kind, {}).get("sides", 4)
	var n := clampi(int(EdDoc.jsround(float(want))), SIDES_MIN, SIDES_MAX)
	var pts: Array = []
	match kind:
		"ellipse", "circle":
			pts = _round(n, PI / n if n % 4 == 0 else PI / 2.0, cx, cy, rx, ry)
		"polygon":
			pts = _round(n, PI / 2.0, cx, cy, rx, ry)
		"triangle":
			pts = [Vector2(x0, y0), Vector2(x1, y0), Vector2(cx, y1)]
		"diamond":
			pts = [Vector2(cx, y0), Vector2(x1, cy), Vector2(cx, y1), Vector2(x0, cy)]
		"star":
			for i in n * 2:
				var t := PI / 2.0 + i * PI / n
				var k := 0.45 if i % 2 else 1.0
				pts.append(Vector2(cx + cos(t) * rx * k, cy + sin(t) * ry * k))
		"lshape":
			var mx := x0 + (x1 - x0) / 2.0
			var my := y0 + (y1 - y0) / 2.0
			pts = [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, my), Vector2(mx, my), Vector2(mx, y1), Vector2(x0, y1)]
		"arch":
			pts.append(Vector2(x1, y0))
			for i in n - 1:
				var t := (i + 1) * PI / n
				pts.append(Vector2(cx + cos(t) * rx, y0 + sin(t) * (y1 - y0)))
			pts.append(Vector2(x0, y0))
		_:
			pts = [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	var rounded: Array = []
	for p in pts:
		rounded.append(Vector2(EdDoc.jsround(p.x), EdDoc.jsround(p.y)))
	var out := PackedVector2Array()
	for k in rounded.size():
		var p: Vector2 = rounded[k]
		var q: Vector2 = rounded[(k + 1) % rounded.size()]
		if p != q:
			out.append(p)
	if EdDoc.signed_area(out) < 0:
		out.reverse()
	return out

static func _round(k: int, phase: float, cx: float, cy: float, fx: float, fy: float) -> Array:
	var out := []
	for i in k:
		var t := phase + i * 2.0 * PI / k
		out.append(Vector2(cx + cos(t) * fx, cy + sin(t) * fy))
	return out

# ---------------------------------------------------------------------

## The vertex at (x, y): one within a weld, one inserted into the line it
## lands on (in every sector the line belongs to), or a new one.
static func vertex_for(d: Dictionary, x: float, y: float) -> int:
	var V: Array = d.vertices
	for i in V.size():
		var v: Vector2 = V[i]
		if absf(v.x - x) <= EdDoc.WELD and absf(v.y - y) <= EdDoc.WELD:
			return i
	var i := V.size()
	V.append(Vector2(x, y))
	var p := Vector2(x, y)
	for s in d.blocks:
		var vs: Array = s.verts
		for k in vs.size():
			var a: Vector2 = V[vs[k]]
			var b: Vector2 = V[vs[(k + 1) % vs.size()]]
			var st := EdDoc.seg_dist(a, b, p)
			if st.x < ON_LINE and st.y > 0.0001 and st.y < 0.9999:
				vs.insert(k + 1, i)
				var old := EdDoc.line_key(vs[k], vs[(k + 2) % vs.size()])
				var o = d.lines.get(old)
				if o != null:
					d.lines[EdDoc.line_key(vs[k], i)] = o.duplicate(true)
					d.lines[EdDoc.line_key(i, vs[(k + 2) % vs.size()])] = o.duplicate(true)
					d.lines.erase(old)
				break
	return i

## Where the segment p-q crosses each of segs: [[t, x, y]], along it.
static func _hits(p: Vector2, q: Vector2, segs: Array) -> Array:
	var hits := []
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		if not EdDoc.seg_cross(p, q, a, b):
			continue
		var dx := q.x - p.x
		var dy := q.y - p.y
		var ex := b.x - a.x
		var ey := b.y - a.y
		var den := dx * ey - dy * ex
		if absf(den) < 1e-9:
			continue
		var t := ((a.x - p.x) * ey - (a.y - p.y) * ex) / den
		hits.append([t, _fix3(p.x + dx * t), _fix3(p.y + dy * t)])
	hits.sort_custom(func(u, v): return u[0] < v[0])
	return hits

## +v.toFixed(3)
static func _fix3(v: float) -> float:
	return float("%.3f" % v)

## A spur into a ring and straight back out of it is not an edge of it.
static func _despur(ring: Array) -> Array:
	var r := ring.duplicate()
	var again := true
	while again and r.size() > 3:
		again = false
		for k in r.size():
			var n := r.size()
			if r[(k - 1 + n) % n] == r[(k + 1) % n]:
				var drop := {k: true, (k + 1) % n: true}
				var nr := []
				for i in n:
					if not drop.has(i):
						nr.append(r[i])
				r = nr
				again = true
				break
	return r

## Vertex i, lying on an edge of a sector it is not a corner of, made a
## corner of it there.
static func split_lines_at(d: Dictionary, i: int) -> void:
	if i < 0 or i >= d.vertices.size():
		return
	var p: Vector2 = d.vertices[i]
	for s in d.blocks:
		var vs: Array = s.verts
		if vs.has(i):
			continue
		for k in vs.size():
			var a: Vector2 = d.vertices[vs[k]]
			var b: Vector2 = d.vertices[vs[(k + 1) % vs.size()]]
			var st := EdDoc.seg_dist(a, b, p)
			if st.x < ON_LINE and st.y > 0.0001 and st.y < 0.9999:
				var old := EdDoc.line_key(vs[k], vs[(k + 1) % vs.size()])
				vs.insert(k + 1, i)
				var o = d.lines.get(old)
				if o != null:
					d.lines[EdDoc.line_key(vs[k], i)] = o.duplicate(true)
					d.lines[EdDoc.line_key(i, vs[(k + 2) % vs.size()])] = o.duplicate(true)
					d.lines.erase(old)
				break

static func _area_of(d: Dictionary, vs: Array) -> float:
	var pts := PackedVector2Array()
	for i in vs:
		pts.append(d.vertices[i])
	return absf(EdDoc.signed_area(pts))

static func _pts_of(d: Dictionary, vs: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in vs:
		pts.append(d.vertices[i])
	return pts

## Take the new ring out of sector P where it runs along P's own edge and
## then cuts across it (cutFrom).
static func cut_from(d: Dictionary, P: Dictionary, ring: Array) -> bool:
	var pv: Array = P.verts
	var n := ring.size()
	var m := pv.size()
	var adj := func(x: int, y: int) -> bool:
		var i := pv.find(x)
		var j := pv.find(y)
		return i >= 0 and j >= 0 and ((i + 1) % m == j or (j + 1) % m == i)
	var along := []
	for k in n:
		along.append(adj.call(ring[k], ring[(k + 1) % n]))
	if not along.has(false) or not along.has(true):
		return false
	var k0 := -1
	for k in n:
		if not along[k] and along[(k - 1 + n) % n]:
			k0 = k
			break
	var r: Array = ring.slice(k0) + ring.slice(0, k0)
	var al: Array = along.slice(k0) + along.slice(0, k0)
	var cn := al.find(true)
	if al.slice(cn).has(false):
		return false
	var u: int = r[0]
	var w: int = r[cn]
	var inner: Array = r.slice(1, cn)
	if not pv.has(u) or not pv.has(w):
		return false
	for v in inner:
		if pv.has(v):
			return false
	var a := pv.find(u)
	var b := pv.find(w)
	var want := _area_of(d, pv) - _area_of(d, ring)
	var best = null
	var err := INF
	for dir in [1, -1]:
		var arc := []
		var i := a
		while true:
			arc.append(pv[i])
			if i == b:
				break
			i = (i + dir + m) % m
		var rev := inner.duplicate()
		rev.reverse()
		var c: Array = arc + rev
		if c.size() < 3 or EdDoc.self_crosses(_pts_of(d, c)):
			continue
		var e := absf(_area_of(d, c) - want)
		if e < err:
			err = e
			best = c
	if best == null or err > maxf(4.0, want * 1e-6):
		return false
	P.verts = best
	return true

## Split sector S along path (vertex indices, ends on S's edge): S keeps
## one side, a new sector the other.
static func split_block(d: Dictionary, S, path: Array):
	if S == null or path.size() < 2:
		return null
	var u: int = path[0]
	var w: int = path[path.size() - 1]
	var inner: Array = path.slice(1, path.size() - 1)
	var r: Array = S.verts
	var i := r.find(u)
	var j := r.find(w)
	if i < 0 or j < 0 or u == w:
		return null
	var arc := func(from: int, to: int) -> Array:
		var out := []
		var k := from
		while true:
			out.append(r[k])
			if k == to:
				break
			k = (k + 1) % r.size()
		return out
	var rev := inner.duplicate()
	rev.reverse()
	var one: Array = arc.call(i, j) + rev
	var two: Array = arc.call(j, i) + inner
	if one.size() < 3 or two.size() < 3:
		return null
	S.verts = one
	var made := EdDoc.copy_without(S, ["verts", "id"])
	made["name"] = ""
	made["id"] = EdDoc.take_id(d)
	made["verts"] = two
	d.blocks.append(made)
	return made

## A NEW BLOCK on a ring of vertex indices: wound anticlockwise, in the
## textures of the block it is drawn inside (it will stand on it), the
## rest of `props` (the tool's height, say) over that, and cut out of
## the block round it where it runs along its edge.
static func insert_block(d: Dictionary, idx: Array, props := {}):
	var ring := []
	for k in idx.size():
		if idx[k] != idx[(k + 1) % idx.size()]:
			ring.append(idx[k])
	if ring.size() < 3:
		return null
	if EdDoc.signed_area(_pts_of(d, ring)) < 0:
		ring.reverse()
	var pts := _pts_of(d, ring)
	var c := Vector2.ZERO
	for p in pts:
		c += p / pts.size()
	var parent = block_containing(d, c.x, c.y)
	var base: Dictionary = EdDoc.BLOCK_DEFAULTS.duplicate(true)
	if parent != null:
		for k in ["top", "side", "light"]:
			if parent.get(k) != null:
				base[k] = parent[k]
	base["name"] = ""
	base.merge(props, true)
	var made := base
	made["id"] = EdDoc.take_id(d)
	made["verts"] = ring
	if parent != null and not EdDoc.strictly_inside(pts, EdDoc.ring_of(d, parent)):
		cut_from(d, parent, ring)
	d.blocks.append(made)
	return made

## Does an outline properly cross any line of the map?
static func crosses_lines(d: Dictionary, points: PackedVector2Array) -> bool:
	var L := EdDoc.lines_of(d)
	for k in points.size():
		var p := points[k]
		var q := points[(k + 1) % points.size()]
		for l in L:
			if EdDoc.seg_cross(p, q, d.vertices[l.a], d.vertices[l.b]):
				return true
	return false

static func seg_dist_ring(r: PackedVector2Array, p: Vector2) -> float:
	var m := INF
	for k in r.size():
		m = minf(m, EdDoc.seg_dist(r[k], r[(k + 1) % r.size()], p).x)
	return m

## The smallest sector round a point, or null.
static func block_containing(d: Dictionary, x: float, y: float):
	var best = null
	var ba := INF
	for s in d.blocks:
		var r := EdDoc.ring_of(d, s)
		if r.size() < 3 or not EdDoc.pip(r, x, y):
			continue
		var a := absf(EdDoc.signed_area(r))
		if a < ba:
			ba = a
			best = s
	return best

## Move a selection (ids: a Dictionary used as a set). A sector or a line
## moves its corners, so what shares them stretches; things standing in
## a moved sector go with it.
static func move_things(d: Dictionary, kind: String, ids: Dictionary, dx: float, dy: float) -> void:
	if kind == "thing":
		for t in d.things:
			if ids.has(t.id):
				t.x = EdDoc.num(t.x) + dx
				t.y = EdDoc.num(t.y) + dy
	if kind == "scatter":
		for c in d.scatters:
			if not ids.has(c.id):
				continue
			var a: Dictionary = c.area
			if a.kind == "circle":
				a.x += dx
				a.y += dy
			elif a.kind == "rect":
				a.x0 += dx
				a.x1 += dx
				a.y0 += dy
				a.y1 += dy
	var verts := {}
	if kind == "vertex":
		for i in ids:
			verts[int(i)] = true
	if kind == "block":
		for s in d.blocks:
			if ids.has(s.id):
				for v in s.verts:
					verts[v] = true
	if kind == "line":
		for k in ids:
			var ab := EdDoc.key_verts(k)
			verts[ab.x] = true
			verts[ab.y] = true
	var off := Vector2(dx, dy)
	for i in verts:
		if i >= 0 and i < d.vertices.size():
			d.vertices[i] += off
	if kind == "block":
		var lay := int(d.get("layer", 0))
		for s in d.blocks:
			if not ids.has(s.id):
				continue
			var r := PackedVector2Array()
			for i in s.verts:
				r.append(d.vertices[i] - off)
			for t in d.things:
				if int(EdDoc.num(t.get("layer"), 0)) == lay and EdDoc.pip(r, EdDoc.num(t.x), EdDoc.num(t.y)):
					t.x = EdDoc.num(t.x) + dx
					t.y = EdDoc.num(t.y) + dy

## Delete a line: join the two blocks on it into one, or remove the
## block whose edge it is.
static func merge_across(d: Dictionary, key: String) -> void:
	var ab := EdDoc.key_verts(key)
	var a := ab.x
	var b := ab.y
	var on := []
	for s in d.blocks:
		var vs: Array = s.verts
		for k in vs.size():
			var v: int = vs[k]
			var w: int = vs[(k + 1) % vs.size()]
			if (v == a and w == b) or (v == b and w == a):
				on.append(s)
				break
	if on.size() == 1:
		d.blocks.erase(on[0])
		return
	if on.size() != 2:
		return
	var s1: Dictionary = on[0]
	var s2: Dictionary = on[1]
	for x in on:
		if EdDoc.signed_area(_pts_of(d, x.verts)) < 0:
			var r: Array = x.verts.duplicate()
			r.reverse()
			x.verts = r
	var i1 := -1
	for k in s1.verts.size():
		var v: int = s1.verts[k]
		var w: int = s1.verts[(k + 1) % s1.verts.size()]
		if (v == a and w == b) or (v == b and w == a):
			i1 = k
			break
	var r1: Array = s1.verts.slice(i1 + 1) + s1.verts.slice(0, i1 + 1)
	var end: int = r1[r1.size() - 1]
	var i2: int = s2.verts.find(end)
	var r2: Array = s2.verts.slice(i2) + s2.verts.slice(0, i2)
	var merged: Array = r1.slice(0, r1.size() - 1) + r2.slice(0, r2.size() - 1)
	var ring := []
	for k in merged.size():
		if merged[k] != merged[(k + 1) % merged.size()]:
			ring.append(merged[k])
	ring = _despur(ring)
	s1.verts = ring
	d.blocks.erase(s2)
	d.lines.erase(EdDoc.line_key(a, b))
