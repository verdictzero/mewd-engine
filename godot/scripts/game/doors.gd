## MEWD — the doors (the Godot build's own; Level.Door, built by
## DocCompile from a line override `door`).
##
## A door opens as anybody walking comes up to it (unless it is not
## `auto`), or on the use key (F, the touch USE) from a player looking at
## it within reach; it stays open while anybody is in the doorway, and
## shuts again three seconds after the last of them has gone. A locked
## door does neither. Opening and shutting take a third of a second.
## Everything here is in the tic, so every machine in a match runs the
## doors the same from the same people.
##
## The picture: each door's slab under a Node3D at its hinge (MapGeo.
## door_nodes) — turned about it, a quarter turn into the room, for a
## swinging door; moved along the line, into the wall past its far side,
## for a sliding one — and its lintel, which stays where it is.
class_name Doors
extends Node3D

const REACH := 72.0        # how near somebody comes before it opens
const USE_REACH := 96.0    # how near a player must be to use it
const HOLD := 105          # tics it stays open after the last one leaves
const STEP := 1.0 / 12.0   # of the way open, a tic

var game
var level: Level
var slabs := []
var _held := {}            # player -> the use key was down last tic

func _init(g) -> void:
	game = g
	level = g.level
	name = "Doors"
	var mg := MapGeo.new(g.bank)
	for d in level.doors:
		var got: Array = mg.door_nodes(level, d)
		add_child(got[0])
		slabs.append(got[0])
		if got[1] != null:
			add_child(got[1])

## Anybody walking, or a player, within `r` of the door's middle and at
## its height.
func _near(d: Level.Door, r: float, doorway := false) -> bool:
	var m := (d.a + d.b) / 2.0
	var half := d.a.distance_to(d.b) / 2.0
	var u := (d.b - d.a).normalized()
	for list in [game.players, game.actors]:
		for a in list:
			if a.removed or a.dead:
				continue
			if list == game.actors and not (a.monster or a.speed > 0.0):
				continue
			if a.z + a.height < d.z0 or a.z > d.top:
				continue
			var p := Vector2(a.x, a.y) - m
			if doorway:
				# in the way of it: in its swing, into the room — or, for a
				# sliding one, in the doorway itself
				var across: float = p.dot(d.inside)
				var lo: float = -a.radius if d.style == "swing" else -d.wall - a.radius
				var hi: float = half + a.radius if d.style == "swing" else a.radius
				if absf(p.dot(u)) <= half + a.radius and across >= lo and across <= hi:
					return true
			elif p.length() <= r + a.radius:
				return true
	return false

## A player's command this tic (Game.tic): the use key, as it goes down.
func command(p, cmd: Dictionary) -> void:
	var down: bool = cmd.get("use", false)
	if down and not _held.get(p, false):
		use(p)
	_held[p] = down

func tic() -> void:
	for d in level.doors:
		if d.locked:
			d.target = 0.0
		elif d.auto and _near(d, REACH + d.a.distance_to(d.b) / 2.0):
			d.target = 1.0
			d.wait = HOLD
		if d.target > 0.0 and d.wait > 0:
			d.wait -= 1
			if d.wait == 0:
				if _near(d, 0.0, true):
					d.wait = 10
				else:
					d.target = 0.0
		# shutting on somebody: open again (Doom's door does)
		if d.target == 0.0 and d.open > 0.0 and _near(d, 0.0, true):
			d.target = 1.0
			d.wait = HOLD
		d.open = move_toward(d.open, d.target, STEP)

## THE USE KEY: the nearest door in front of the player, within reach —
## opened, or shut if it is open.
func use(p) -> bool:
	var best: Level.Door = null
	var bd := USE_REACH
	var f := Vector2(cos(p.angle), sin(p.angle))
	for d in level.doors:
		if p.z + p.height < d.z0 or p.z > d.top:
			continue
		var c := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.y), d.a, d.b)
		var to := c - Vector2(p.x, p.y)
		var dist := to.length()
		if dist < bd and (dist < 8.0 or to.normalized().dot(f) > 0.5):
			bd = dist
			best = d
	if best == null or best.locked:
		return false
	best.target = 0.0 if best.target > 0.5 else 1.0
	best.wait = HOLD * 2 if best.target > 0.0 else 0
	return true

func _process(_dt: float) -> void:
	for i in slabs.size():
		var d: Level.Door = level.doors[i]
		var s: Node3D = slabs[i]
		var e := d.open * d.open * (3.0 - 2.0 * d.open)
		if d.style == "slide":
			var off: Vector2 = d.a + (d.b - d.a) * e
			s.position = U.v3(off.x, off.y, 0.0)
		else:
			# a quarter turn about the hinge, into the room
			var u := (d.b - d.a).normalized()
			var sgn := 1.0 if u.cross(d.inside) > 0.0 else -1.0
			s.rotation.y = sgn * e * PI / 2.0
