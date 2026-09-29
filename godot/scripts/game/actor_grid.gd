## MEWD — where the actors are, in 128-unit cells (js/actor.js
## ActorGrid), so "who is near me" is nine cells and not the whole cast.
## Asked several times per actor per tic; a crowd of five hundred behind
## every question is a scan the player can feel.
class_name ActorGrid
extends RefCounted

const CELL := 128.0

var cells := {}

func _key(x: float, y: float) -> int:
	return (floori(x / CELL) + 32768) * 65536 + (floori(y / CELL) + 32768)

func add(a) -> void:
	a.bm_key = _key(a.x, a.y)
	if not cells.has(a.bm_key):
		cells[a.bm_key] = []
	cells[a.bm_key].append(a)

func remove(a) -> void:
	if a.bm_key < 0:
		return
	var c: Array = cells.get(a.bm_key, [])
	c.erase(a)
	a.bm_key = -1

func moved(a) -> void:
	if a.bm_key < 0:
		return
	var k := _key(a.x, a.y)
	if k == a.bm_key:
		return
	remove(a)
	add(a)

## everything in the nine cells round (x, y)
func near(x: float, y: float) -> Array:
	var out := []
	var cx := floori(x / CELL)
	var cy := floori(y / CELL)
	for i in range(-1, 2):
		for j in range(-1, 2):
			var c = cells.get((cx + i + 32768) * 65536 + (cy + j + 32768))
			if c != null:
				out.append_array(c)
	return out

## everything within r of (x, y), by cell (the caller checks the distance)
func near_radius(x: float, y: float, r: float) -> Array:
	var out := []
	var c0 := floori((x - r) / CELL)
	var c1 := floori((x + r) / CELL)
	var r0 := floori((y - r) / CELL)
	var r1 := floori((y + r) / CELL)
	for i in range(c0, c1 + 1):
		for j in range(r0, r1 + 1):
			var c = cells.get((i + 32768) * 65536 + (j + 32768))
			if c != null:
				out.append_array(c)
	return out
