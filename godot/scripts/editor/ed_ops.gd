## MEWD Editor — the edits a person makes, on the document itself (the
## document helpers of js/editor/editor.js): a vertex put down that
## splits the wall it lands on, a new sector cut out of the one it is
## drawn in, a sector split along a path, two merged across a line,
## linedefs closing into sectors, a selection moved, and the shapes the
## Shape tool draws.
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
	for s in d.sectors:
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
	split_linedefs_at(d, i)
	return i

## Vertex i, lying along a linedef of its own, splits it in two.
static func split_linedefs_at(d: Dictionary, i: int) -> void:
	if i < 0 or i >= d.vertices.size() or d.get("linedefs", []).is_empty():
		return
	var p: Vector2 = d.vertices[i]
	var L: Array = d.linedefs
	for k in L.size():
		var pa: int = L[k][0]
		var qb: int = L[k][1]
		if pa == i or qb == i:
			continue
		var st := EdDoc.seg_dist(d.vertices[pa], d.vertices[qb], p)
		if st.x < ON_LINE and st.y > 0.0001 and st.y < 0.9999:
			L.remove_at(k)
			L.insert(k, [i, qb])
			L.insert(k, [pa, i])
			var o = d.lines.get(EdDoc.line_key(pa, qb))
			if o != null:
				d.lines[EdDoc.line_key(pa, i)] = o.duplicate(true)
				d.lines[EdDoc.line_key(i, qb)] = o.duplicate(true)
				d.lines.erase(EdDoc.line_key(pa, qb))
			return

## A drawn path with a corner wherever it crosses a line of the map.
static func with_crossings(d: Dictionary, points: PackedVector2Array, closed := true) -> PackedVector2Array:
	var segs := []
	for l in EdDoc.lines_of(d):
		segs.append([d.vertices[l.a], d.vertices[l.b]])
	for e in d.get("linedefs", []):
		segs.append([d.vertices[e[0]], d.vertices[e[1]]])
	var out := PackedVector2Array()
	var n := points.size()
	for k in n:
		var p := points[k]
		out.append(p)
		if not closed and k == n - 1:
			break
		var q := points[(k + 1) % n]
		var hits := _hits(p, q, segs)
		for h in hits:
			out.append(Vector2(h[1], h[2]))
	return out

## Where p-q properly crosses each segment: [t, x, y] in order along it,
## the point kept to three places as the web build keeps it.
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

## CLOSING LOOPS: wherever linedefs of their own close a shape — among
## themselves or against sector walls — that shape becomes a sector.
static func close_loops(d: Dictionary) -> Array:
	if d.get("linedefs", []).is_empty():
		return []
	var free := {}
	for e in d.linedefs:
		free[EdDoc.line_key(e[0], e[1])] = true
	var adj := {}
	var link := func(a: int, b: int) -> void:
		if a == b:
			return
		if not adj.has(a):
			adj[a] = {}
		if not adj.has(b):
			adj[b] = {}
		adj[a][b] = true
		adj[b][a] = true
	for l in EdDoc.lines_of(d):
		link.call(l.a, l.b)
	for e in d.linedefs:
		link.call(e[0], e[1])
	var V: Array = d.vertices
	var order := {}
	for v in adj:
		var ns: Array = adj[v].keys()
		var pv: Vector2 = V[v]
		ns.sort_custom(func(p, q):
			var a1 := atan2(V[p].y - pv.y, V[p].x - pv.x)
			var a2 := atan2(V[q].y - pv.y, V[q].x - pv.x)
			return a1 < a2)
		order[v] = ns
	var faces := _faces(order)
	var made := []
	for ring0 in faces:
		var ring: Array = _despur(ring0)
		if ring.size() < 3 or _has_dupes(ring):
			continue
		var pts := PackedVector2Array()
		for i in ring:
			pts.append(V[i])
		if EdDoc.signed_area(pts) <= 0.25 or EdDoc.self_crosses(pts):
			continue
		var touches := false
		for k in ring.size():
			if free.has(EdDoc.line_key(ring[k], ring[(k + 1) % ring.size()])):
				touches = true
				break
		if not touches:
			continue
		var sk := _sorted_key(ring)
		var exists := false
		for s in d.sectors:
			if _sorted_key(s.verts) == sk:
				exists = true
				break
		if exists:
			continue
		var s = insert_sector(d, ring)
		if s != null:
			made.append(s.id)
	return made

## Every face of a plane graph, walked with the face on the left.
static func _faces(order: Dictionary) -> Array:
	var seen := {}
	var faces := []
	for u0 in order:
		for v0 in order[u0]:
			if seen.has("%d>%d" % [u0, v0]):
				continue
			var ring := []
			var u: int = u0
			var v: int = v0
			var guard := 0
			while not seen.has("%d>%d" % [u, v]) and guard < 100000:
				guard += 1
				seen["%d>%d" % [u, v]] = true
				ring.append(u)
				var around: Array = order[v]
				var i := around.find(u)
				var w: int = around[(i - 1 + around.size()) % around.size()]
				u = v
				v = w
			if u == u0 and v == v0:
				faces.append(ring)
	return faces

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

static func _has_dupes(a: Array) -> bool:
	var s := {}
	for v in a:
		if s.has(v):
			return true
		s[v] = true
	return false

static func _sorted_key(a: Array) -> String:
	var b := a.duplicate()
	b.sort()
	return ",".join(b.map(func(x): return str(x)))

## Vertex i, lying on an edge of a sector it is not a corner of, made a
## corner of it there.
static func split_lines_at(d: Dictionary, i: int) -> void:
	if i < 0 or i >= d.vertices.size():
		return
	var p: Vector2 = d.vertices[i]
	for s in d.sectors:
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
static func split_sector(d: Dictionary, S, path: Array):
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
	d.sectors.append(made)
	return made

## A NEW SECTOR on a ring of vertex indices: wound anticlockwise, taking
## the heights and textures of the sector it is drawn in, and cut out of
## that one where it runs along its wall.
static func insert_sector(d: Dictionary, idx: Array):
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
	var parent = sector_containing(d, c.x, c.y)
	var base: Dictionary
	if parent != null:
		base = EdDoc.copy_without(parent, ["id", "verts", "storeys"])
		base["name"] = ""
	else:
		base = EdDoc.SECTOR_DEFAULTS.duplicate(true)
		var lb = EdDoc.layer_base(d, int(d.get("layer", 0)), c.x, c.y)
		if lb != null:
			base.merge(lb, true)
	var made := base
	made["id"] = EdDoc.take_id(d)
	made["verts"] = ring
	if parent != null and not EdDoc.strictly_inside(pts, EdDoc.ring_of(d, parent)):
		cut_from(d, parent, ring)
	d.sectors.append(made)
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
static func sector_containing(d: Dictionary, x: float, y: float):
	var best = null
	var ba := INF
	for s in d.sectors:
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
	if kind == "prop":
		for p in d.props:
			if ids.has(p.id):
				p.x0 += dx
				p.x1 += dx
				p.y0 += dy
				p.y1 += dy
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
	if kind == "sector":
		for s in d.sectors:
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
	if kind == "sector":
		var lay := int(d.get("layer", 0))
		for s in d.sectors:
			if not ids.has(s.id):
				continue
			var r := PackedVector2Array()
			for i in s.verts:
				r.append(d.vertices[i] - off)
			for t in d.things:
				if int(EdDoc.num(t.get("layer"), 0)) == lay and EdDoc.pip(r, EdDoc.num(t.x), EdDoc.num(t.y)):
					t.x = EdDoc.num(t.x) + dx
					t.y = EdDoc.num(t.y) + dy

## Delete a line: join the two sectors on it into one, or remove the
## sector a one-sided line bounds.
static func merge_across(d: Dictionary, key: String) -> void:
	var ab := EdDoc.key_verts(key)
	var a := ab.x
	var b := ab.y
	var on := []
	for s in d.sectors:
		var vs: Array = s.verts
		for k in vs.size():
			var v: int = vs[k]
			var w: int = vs[(k + 1) % vs.size()]
			if (v == a and w == b) or (v == b and w == a):
				on.append(s)
				break
	if on.size() == 1:
		d.sectors.erase(on[0])
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
	d.sectors.erase(s2)
	d.lines.erase(EdDoc.line_key(a, b))
