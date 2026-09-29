## MEWD — the way from room to room (the Godot build's own).
##
## Doom's monsters chase on the plan: straight at you, and round what is
## in the way by trying the other seven directions. That never finds a
## stair on the far side of the room, or a door in the wall. So the level
## is a GRAPH as well: a node for each storey of each sector a trooper
## can stand up in, and a way from one to the next across each two-sided
## line the trooper can walk over — the opening between them tall enough,
## the step up no more than a step (U.MAX_STEP), the drop down no more
## than the 96 Doom lets a monster fall, not walled at that height, and a
## door in it only if it is not locked and it is tall enough. A trooper
## whose target is in another room asks path() for the way there, and
## chases the next point on it instead (Actor._chase_point); in the same
## room, it chases as Doom does.
##
## path() is A* over the rooms, each costed from the point it was entered
## at: the crossing of each line is the point of it nearest where the
## trooper will be (kept a body's width in from its ends), and the way
## point is just over it, in the next room.
class_name Nav
extends RefCounted

const H := 56.0          # a trooper's height
const R := 20.0          # a trooper's radius, and a little more
const DROP := 96.0       # the most a monster drops (Doom's)
const MAX_OPEN := 6000   # the most rooms one path looks at

var level: Level
## sector index -> [[to, p1, p2, n]] (the line's ends, and the normal
## into `to`)
var ways := {}
var links := 0

func _init(lv: Level) -> void:
	level = lv
	for l in lv.lines:
		if l.front == -1 or l.back == -1 or l.len < 2.0 * R:
			continue
		for a in l.front_col:
			for b in l.back_col:
				_link(l, a, b)
				_link(l, b, a)

func _link(l: Level.Line, ai: int, bi: int) -> void:
	var a := level.sectors[ai]
	var b := level.sectors[bi]
	if a.ceil - a.floor < H or b.ceil - b.floor < H:
		return
	var lo := maxf(a.floor, b.floor)
	var hi := minf(a.ceil, b.ceil)
	if hi - lo < H:
		return
	if b.floor - a.floor > U.MAX_STEP or a.floor - b.floor > DROP:
		return
	# walled at this height
	if l.blocking:
		if l.mid_z.is_empty():
			return
		for m in l.mid_z:
			if lo < m.y - 0.5 and lo + H > m.x + 0.5:
				return
	# a door at this height: not a locked one, nor one too low
	var d: Level.Door = l.door
	if d != null and lo < d.top and lo + H > d.z0:
		if d.locked or d.top < lo + H:
			return
	var p1 := Vector2(l.x1, l.y1)
	var p2 := Vector2(l.x2, l.y2)
	var n := (p2 - p1).normalized().orthogonal()
	var m := (p1 + p2) / 2.0 + n * 4.0
	var s := level.sector_at(m.x, m.y)
	if s == null or s.col_base != b.col_base:
		n = -n
	if not ways.has(ai):
		ways[ai] = []
	ways[ai].append([bi, p1, p2, n])
	links += 1

## Where to cross a way, from `from`: the point of its line nearest, a
## body's width in from its ends.
static func _cross(w: Array, from: Vector2) -> Vector2:
	var p1: Vector2 = w[1]
	var p2: Vector2 = w[2]
	var L := p1.distance_to(p2)
	var u := (p2 - p1) / L
	var t := clampf((from - p1).dot(u), minf(R, L / 2.0), maxf(L - R, L / 2.0))
	return p1 + u * t

## THE WAY from room `fs` (at `from`) to room `ts` (at `to`): the points
## to walk to, each just inside the next room — [{p: Vector2, into: int}],
## empty if they are the same room or there is no way.
func path(fs: int, from: Vector2, ts: int, to: Vector2) -> Array:
	if fs == ts or not ways.has(fs):
		return []
	var g := {fs: 0.0}
	var at := {fs: from}
	var came := {}
	var shut := {}
	# a binary heap of [f, sector]
	var heap := [[from.distance_to(to), fs]]
	var opened := 0
	while not heap.is_empty():
		var cur: Array = _pop(heap)
		var u: int = cur[1]
		if shut.has(u):
			continue
		if u == ts:
			break
		shut[u] = true
		opened += 1
		if opened > MAX_OPEN:
			return []
		var pu: Vector2 = at[u]
		for w in ways.get(u, []):
			var v: int = w[0]
			if shut.has(v):
				continue
			var c := _cross(w, pu)
			var nv: float = g[u] + pu.distance_to(c) + 1.0
			if not g.has(v) or nv < g[v]:
				g[v] = nv
				at[v] = c
				came[v] = [u, w]
				_push(heap, [nv + c.distance_to(to), v])
	if not came.has(ts):
		return []
	var out := []
	var v := ts
	while v != fs:
		var cw: Array = came[v]
		var w: Array = cw[1]
		out.push_front({"p": (at[v] as Vector2) + (w[3] as Vector2) * (R + 4.0), "into": v, "at": at[v]})
		v = cw[0]
	return out

static func _push(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p

static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < h.size() and h[l][0] < h[m][0]:
				m = l
			if r < h.size() and h[r][0] < h[m][0]:
				m = r
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top
