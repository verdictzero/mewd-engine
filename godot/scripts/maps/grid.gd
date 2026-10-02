## MEWD — THE GRID, a test area (js/maps/grid.js buildGrid, and gridDoc
## in js/editor/doc.js).
##
## A large walled-off green grid with a crowd standing on it and every
## gun in the rack: the ground plane in the lattice, a field 160 cells of
## 64 on a side walled round by four blocks 1024 high in the lattice too,
## the green night sky over it, and two hundred people in its middle two
## thirds. Nothing burns, nobody comes, the cell fire is off. As a map
## document in blocks (BlockDoc), for BlockCompile.
class_name TheGrid

const NAME := "THE GRID"
const CELL := 64
const FIELD := 160 * CELL             # 10240
const WALL_H := 1024
const WALL_T := 64
const CROWD := 200
const CROWD_SPAN := 0.66
const APART := 130.0
const FLOOR_LIGHT := 0.72
const SEED := 20250924

## THE GRID as the game plays it (buildGrid): the crowd placed by the
## same roll, standing apart, clear of the walls.
static func build(seed: int = SEED, crowd: int = CROWD) -> Dictionary:
	var rnd := U.Rng.new(seed)
	var b := _field(NAME)
	var span := FIELD * CROWD_SPAN
	var edge := (FIELD - span) / 2.0
	var taken := PackedVector2Array()
	var k := 0
	var tries := 0
	while k < crowd and tries < crowd * 200:
		tries += 1
		var x := edge + rnd.next() * span
		var y := edge + rnd.next() * span
		if x < 96 or x > FIELD - 96 or y < 96 or y > FIELD - 96:
			continue
		var clear := true
		for t in taken:
			if (t.x - x) * (t.x - x) + (t.y - y) * (t.y - y) < APART * APART:
				clear = false
				break
		if not clear:
			continue
		taken.append(Vector2(x, y))
		b.thing("SHOPPER", x, y, {"angle": rnd.next() * TAU, "variant": int(rnd.next() * 17)})
		k += 1
	return b.out()

## The editor's copy (gridDoc): the same field, sixty people.
static func editor_doc() -> Dictionary:
	var b := _field(NAME)
	var s := U.Rng.new(SEED)
	var span := FIELD * 0.66
	var edge := (FIELD - span) / 2.0
	for k in 60:
		var x := floori(edge + s.next() * span + 0.5)
		var y := floori(edge + s.next() * span + 0.5)
		b.thing("SHOPPER", x, y, {"angle": s.next() * TAU, "variant": int(s.next() * 17)})
	return b.out()

## The field: the ground in the lattice, four walls round it, the start
## in the middle.
static func _field(name: String) -> BlockDoc:
	var mid := FIELD / 2.0
	# the grid's world: nothing burns, nobody comes, the green sky
	var b := BlockDoc.new(name, {"tex": "GRID", "light": FLOOR_LIGHT}, DocCompile.default_world())
	var wall := {"h": WALL_H, "top": "GRIDWALL", "side": "GRIDWALL", "name": "wall"}
	var T := WALL_T
	b.rect(-T, -T, FIELD + T, 0, wall)
	b.rect(-T, FIELD, FIELD + T, FIELD + T, wall)
	b.rect(-T, 0, 0, FIELD, wall)
	b.rect(FIELD, 0, FIELD + T, FIELD, wall)
	b.thing("START", mid, mid - 8 * CELL, {"angle": PI / 2})
	return b
