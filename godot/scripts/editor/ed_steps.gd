## MEWD Editor — THE STEP GENERATOR: stairs, cliffs and calderas, a
## block at a time.
##
##   STAIRS  a block between two heights is cut across into strips, each
##           a step higher than the last, from the lower neighbour's top
##           up to the higher's (or the heights given)
##   RINGS   a block is cut into rings, one inside another, each a step
##           up (a mound, a mesa) or down (a caldera, a pit) to the middle
##
## Both are ordinary blocks afterwards, drawn as a hand would draw them:
## each piece's HEIGHT is set so its top is where the step wants it,
## over the base the piece stands on (the block it is drawn inside, or
## the ground).
class_name EdSteps

const STEP_H := 16

## The blocks across a line from S, with the stretch of edge each
## shares: [{s, len, mid, top}] — and the ground, where S's edge has no
## block on the other side, as {s: null, top: 0}.
static func neighbours_of(d: Dictionary, S: Dictionary, tops: Dictionary) -> Array:
	var si: int = d.blocks.find(S)
	var out := {}
	var order := []
	for l in EdDoc.lines_of(d):
		if not l.blocks.has(si):
			continue
		var o = null
		if l.blocks.size() == 2:
			o = d.blocks[l.blocks[1] if l.blocks[0] == si else l.blocks[0]]
		var a: Vector2 = d.vertices[l.a]
		var b: Vector2 = d.vertices[l.b]
		var len := a.distance_to(b)
		var key = o.id if o != null else -1
		if not out.has(key):
			out[key] = {"s": o, "len": 0.0, "m": Vector2.ZERO, "top": top_of(d, o, tops)}
			order.append(key)
		out[key].len += len
		out[key].m += (a + b) / 2.0 * len
	var res := []
	for k in order:
		var e: Dictionary = out[k]
		res.append({"s": e.s, "len": e.len, "mid": e.m / e.len, "top": e.top})
	return res

## Where a block's top is: as the last build had it (tops: id -> {base,
## top}), else its base (or nothing) plus its height.
static func top_of(d: Dictionary, s, tops: Dictionary) -> float:
	if s == null:
		return 0.0
	var t = tops.get(s.id)
	if t is Dictionary:
		return float(t.top)
	var b = EdDoc.base_of(s)
	return (float(b) if b != null else 0.0) + EdDoc.h_of(s)

## The base a piece of S stands on: the block S is drawn inside, else
## the ground.
static func base_under(d: Dictionary, S: Dictionary, tops: Dictionary) -> float:
	var b = EdDoc.base_of(S)
	if b != null:
		return float(b)
	var par := EdDoc.hole_parents(d)
	var si: int = d.blocks.find(S)
	if si >= 0 and par[si] >= 0:
		return top_of(d, d.blocks[par[si]], tops)
	return 0.0

## STAIRS ACROSS S. opts: from, to, count, stepH, dir. Returns {ids,
## rise, steps} or {error}.
static func make_stairs(d: Dictionary, S: Dictionary, opts := {}, tops := {}) -> Dictionary:
	var ring := EdDoc.ring_of(d, S)
	if ring.size() < 3:
		return {"error": "that block has no shape"}
	var count := int(opts.get("count", 0))
	var step_h := float(opts.get("stepH", STEP_H))
	var nb := neighbours_of(d, S, tops)
	var lo = null
	var hi = null
	for n in nb:
		if lo == null or n.top < lo.top:
			lo = n
		if hi == null or n.top > hi.top:
			hi = n
	var auto: bool = lo != null and hi != null and hi.top != lo.top
	var from = opts.get("from")
	var to = opts.get("to")
	if from == null:
		from = lo.top if auto else base_under(d, S, tops)
	if to == null:
		if not auto:
			return {"error": "the block has no neighbours of different heights to bridge — give the height to climb to"}
		to = hi.top
	var dh := float(to) - float(from)
	if dh == 0:
		return {"error": "the two ends are at the same height — there is nothing to climb"}
	var u = opts.get("dir")
	if u == null and auto:
		u = hi.mid - lo.mid
	if u == null or u.length() < 1e-6:
		var bb := EdDoc.bbox(ring)
		u = Vector2(1, 0) if bb.size.x >= bb.size.y else Vector2(0, 1)
		if auto and (lo.mid - hi.mid).dot(u) > 0:
			u = -u
	u = u.normalized()
	if absf(u.x) > 0.92:
		u = Vector2(signf(u.x), 0)
	elif absf(u.y) > 0.92:
		u = Vector2(0, signf(u.y))
	var n := int(EdDoc.jsround(count)) if count > 0 else maxi(1, ceili(absf(dh) / maxf(1.0, step_h)) - 1)
	if n > 256:
		return {"error": "%d steps is too many — make the step taller" % n}
	var t0 := INF
	var t1 := -INF
	for p in ring:
		t0 = minf(t0, p.dot(u))
		t1 = maxf(t1, p.dot(u))
	var axis: bool = u.x == 0 or u.y == 0
	var under := base_under(d, S, tops)
	var pieces := [S]
	for k in range(1, n):
		var t := t0 + (t1 - t0) * k / n
		if axis:
			t = EdDoc.jsround(t)
		_cut_across(d, pieces, u, t)
	var rise := dh / (n + 1)
	for s in pieces:
		var c := EdDoc.centroid(EdDoc.ring_of(d, s))
		var i := clampi(floori((c.dot(u) - t0) / (t1 - t0) * n), 0, n - 1)
		var top := EdDoc.jsround(float(from) + rise * (i + 1))
		s.h = top - under
		if s != S:
			s.name = ""
	var ids := []
	for s in pieces:
		ids.append(s.id)
	return {"ids": ids, "rise": rise, "steps": n}

## Cut every piece that the line {p : p·u = t} crosses.
static func _cut_across(d: Dictionary, pieces: Array, u: Vector2, t: float) -> void:
	var v := Vector2(-u.y, u.x)
	for guard in 64:
		var did := false
		for P in pieces.duplicate():
			var r := EdDoc.ring_of(d, P)
			var hits := []
			for k in r.size():
				var a := r[k]
				var b := r[(k + 1) % r.size()]
				var ta := a.dot(u) - t
				var tb := b.dot(u) - t
				if (ta > 0) == (tb > 0) and ta != 0 and tb != 0:
					continue
				if ta == 0 and tb == 0:
					continue
				var f := 0.0 if ta == tb else ta / (ta - tb)
				if f < 0 or f > 1:
					continue
				var x := EdOps._fix3(a.x + (b.x - a.x) * f)
				var y := EdOps._fix3(a.y + (b.y - a.y) * f)
				hits.append([x * v.x + y * v.y, x, y])
			hits.sort_custom(func(p, q): return p[0] < q[0])
			var pts := []
			for k in hits.size():
				if k == 0 or hits[k][0] - hits[k - 1][0] > 0.5:
					pts.append(hits[k])
			for k in pts.size() - 1:
				var mx: float = (pts[k][1] + pts[k + 1][1]) / 2.0
				var my: float = (pts[k][2] + pts[k + 1][2]) / 2.0
				if not EdDoc.pip(r, mx, my):
					continue
				var a := EdOps.vertex_for(d, pts[k][1], pts[k][2])
				var b := EdOps.vertex_for(d, pts[k + 1][1], pts[k + 1][2])
				if a == b or not P.verts.has(a) or not P.verts.has(b):
					continue
				var i: int = P.verts.find(a)
				var j: int = P.verts.find(b)
				var m: int = P.verts.size()
				if (i + 1) % m == j or (j + 1) % m == i:
					continue
				var made = EdOps.split_block(d, P, [a, b])
				if made != null:
					pieces.append(made)
					did = true
					break
			if did:
				break
		if not did:
			return

## RINGS IN S. opts: to, count, stepH. Each ring stands in the one round
## it, so its height is the step; the middle's top is `to`.
static func make_rings(d: Dictionary, S: Dictionary, opts := {}, tops := {}) -> Dictionary:
	var outer := EdDoc.ring_of(d, S)
	if outer.size() < 3:
		return {"error": "that block has no shape"}
	var from := top_of(d, S, tops)
	var to = opts.get("to")
	if to == null or (to is String and to == ""):
		to = from + 128
	var dh := float(to) - from
	if dh == 0:
		return {"error": "give the middle a height different from the edge"}
	var count := int(opts.get("count", 0))
	var step_h := float(opts.get("stepH", STEP_H))
	var n := int(EdDoc.jsround(count)) if count > 0 else maxi(2, int(EdDoc.jsround(absf(dh) / maxf(1.0, step_h))) + 1)
	if n > 128:
		return {"error": "%d rings is too many — make the step taller" % n}
	var A := absf(EdDoc.signed_area(outer))
	var P := 0.0
	for k in outer.size():
		P += outer[k].distance_to(outer[(k + 1) % outer.size()])
	var reach := A / (P / 2.0) * 0.9
	var w := reach / n
	if w < 2:
		return {"error": "the block is too small for %d rings — fewer rings, or a taller step" % n}
	var ccw := outer
	if EdDoc.signed_area(outer) <= 0:
		ccw = outer.duplicate()
		ccw.reverse()
	var made := [S]
	var prev := ccw
	for i in range(1, n):
		var ring = _inset(ccw, w * i)
		if ring == null or EdDoc.self_crosses(ring) or not EdDoc.strictly_inside(ring, prev):
			var c := EdDoc.centroid(ccw)
			var f := 1.0 - float(i) / n
			ring = PackedVector2Array()
			for p in ccw:
				ring.append(Vector2(EdDoc.jsround(c.x + (p.x - c.x) * f), EdDoc.jsround(c.y + (p.y - c.y) * f)))
			if EdDoc.self_crosses(ring) or not EdDoc.strictly_inside(ring, prev):
				var ids := []
				for s in made:
					ids.append(s.id)
				return {"error": "ring %d does not fit inside ring %d — use fewer rings" % [i + 1, i], "ids": ids}
		var verts := []
		for p in ring:
			verts.append(EdOps.vertex_for(d, p.x, p.y))
		var s := EdDoc.copy_without(S, ["id", "verts"])
		s["name"] = ""
		s["base"] = null
		s["id"] = EdDoc.take_id(d)
		s["verts"] = verts
		d.blocks.append(s)
		made.append(s)
		prev = ring
	# each ring's top, and so its height over the ring it stands in
	var step := dh / (n - 1)
	for i in range(1, made.size()):
		made[i].h = EdDoc.jsround(step)
	var ids := []
	for s in made:
		ids.append(s.id)
	return {"ids": ids, "steps": n, "rise": step}

## A ring moved in by w everywhere, each corner along its bisector,
## rounded to whole units; null where a corner would pass the next.
static func _inset(ccw: PackedVector2Array, w: float):
	var n := ccw.size()
	var out := PackedVector2Array()
	for k in n:
		var p := ccw[(k - 1 + n) % n]
		var c := ccw[k]
		var q := ccw[(k + 1) % n]
		var e1 := c - p
		var e2 := q - c
		if e1.length() < 1e-9 or e2.length() < 1e-9:
			return null
		e1 = e1.normalized()
		e2 = e2.normalized()
		var n1 := Vector2(-e1.y, e1.x)
		var n2 := Vector2(-e2.y, e2.x)
		var b := n1 + n2
		if b.length() < 1e-9:
			return null
		b = b.normalized()
		var cs := b.dot(n1)
		if cs < 0.2:
			return null
		out.append(Vector2(EdDoc.jsround(c.x + b.x * w / cs), EdDoc.jsround(c.y + b.y * w / cs)))
	return out
