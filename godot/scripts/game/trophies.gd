## MEWD — what the cerebral bore pulls out (the Godot build's own; at
## the user's request: "let the player collect body parts extracted
## with the cerebral bore").
##
## When a bore finishes its drilling and the head goes, the piece it was
## after drops out of it: a BRAIN, which falls to the floor and lies
## there turning a little, until a player walks over it and takes it.
## That is all it does — a trophy; the HUD keeps the count (Player.brains).
##
## One quad each out of the gore strip (the cell that reads as a brain),
## lit by the room as the giblets are; the pool is a Particles whose
## tic is never run: the brains are moved by hand here, so they neither
## age nor fall through the floor.
class_name Trophies
extends Node3D

## the cell of assets/people/giblets.png a brain is drawn with
const BRAIN_CELL := 5
const SIZE := 14.0
## how far from the floor the sprite's middle rides
const RIDE := 8.0
const GRAVITY := -0.5
## how close a player comes to take one
const REACH := 20.0
const TINT := Color(1.0, 0.82, 0.86, 1.0)

var game
var pool: Particles
## {x, y, z, vz, floor, i (the quad), t, rest}
var items: Array = []

func _init(g) -> void:
	game = g
	pool = Particles.new({"max": 64, "map": load("res://assets/people/giblets.png"), "frames": Giblets.GIBLETS,
		"blend": "mix", "fullbright": false, "near_shrink": 80.0, "order": 13})
	pool.mat.set_shader_parameter("light", 0.9)
	add_child(pool)

func count() -> int:
	return items.size()

## A brain out of a head at (x, y, z): it drops from there.
func drop(x: float, y: float, z: float) -> void:
	var sec = game.level.span_at(x, y, z)
	var fl: float = sec.floor if sec != null else 0.0
	var i := pool.spawn({"x": x, "y": y, "z": z, "age": 0.0, "life": 1e9, "size": SIZE, "c0": TINT, "c1": TINT,
		"frame": BRAIN_CELL, "frameRate": 0.0, "drag": 1.0, "gravity": 0.0})
	if i < 0:
		return
	items.append({"x": x, "y": y, "z": z, "vz": 1.5, "floor": fl, "i": i, "t": 0, "rest": false})

func tic() -> void:
	for k in range(items.size() - 1, -1, -1):
		var b: Dictionary = items[k]
		b.t += 1
		if not b.rest:
			b.vz += GRAVITY
			b.z += b.vz
			if b.z <= b.floor:
				b.z = b.floor
				b.rest = true
		# taken by whoever walks over it
		var taken = null
		for p in game.players:
			if p.dead or p.removed:
				continue
			var r: float = p.radius + REACH
			if U.dist2(p.x, p.y, b.x, b.y) < r * r and absf(p.z - b.z) < 48.0:
				taken = p
				break
		if taken != null:
			taken.brains += 1
			pool.kill(b.i)
			items.remove_at(k)
			if taken == game.player:
				game.play_sound("lock", null)
				game.toast("BRAIN  ×%d" % taken.brains)
			continue
		var i: int = b.i
		pool.px[i] = b.x
		pool.py[i] = b.y
		pool.pz[i] = b.z + RIDE + (2.0 * sin(b.t * 0.12) if b.rest else 0.0)

func draw() -> void:
	pool.draw()
