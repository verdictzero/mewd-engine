## MEWD — THE GRID, a test area (js/maps/grid.js buildGrid, and gridDoc
## in js/editor/doc.js).
##
## A large walled-off green grid with a crowd standing on it and every
## gun in the rack: one rectangle 160 cells of 64 on a side, walled
## round in the lattice to 1024, the green night sky over it, and two
## hundred people in its middle two thirds. Nothing burns, nobody comes,
## the cell fire is off. As a map document, for DocCompile.
class_name TheGrid

const NAME := "THE GRID"
const CELL := 64
const FIELD := 160 * CELL             # 10240
const WALL_H := 1024
const CROWD := 200
const CROWD_SPAN := 0.66
const APART := 130.0
const FLOOR_LIGHT := 0.72
const SEED := 20250924

## THE GRID as the game plays it (buildGrid): the crowd placed by the
## same roll, standing apart, clear of the walls.
static func build(seed: int = SEED, crowd: int = CROWD) -> Dictionary:
	var rnd := U.Rng.new(seed)
	var d := _field(NAME)
	var mid := FIELD / 2.0
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
		d.things.append({"id": d.nextId, "type": "SHOPPER", "x": floori(x + 0.5), "y": floori(y + 0.5),
			"angle": rnd.next() * TAU, "variant": int(rnd.next() * 17)})
		d.nextId += 1
		k += 1
	return d

## The editor's copy (gridDoc): the same field, sixty people.
static func editor_doc() -> Dictionary:
	var d := _field(NAME)
	var s := U.Rng.new(SEED)
	var span := FIELD * 0.66
	var edge := (FIELD - span) / 2.0
	for k in 60:
		var x := floori(edge + s.next() * span + 0.5)
		var y := floori(edge + s.next() * span + 0.5)
		d.things.append({"id": d.nextId, "type": "SHOPPER", "x": x, "y": y, "angle": s.next() * TAU, "variant": int(s.next() * 17)})
		d.nextId += 1
	return d

static func _field(name: String) -> Dictionary:
	var mid := FIELD / 2.0
	return {
		"format": "gss-map", "version": 1, "name": name,
		"vertices": [Vector2(0, 0), Vector2(FIELD, 0), Vector2(FIELD, FIELD), Vector2(0, FIELD)],
		"sectors": [{"id": 1, "verts": [0, 1, 2, 3], "name": "field", "floor": 0, "ceil": WALL_H,
			"light": FLOOR_LIGHT, "floorTex": "GRID", "ceilTex": "SKY", "wallTex": "GRIDWALL",
			"upperTex": "GRIDWALL", "lowerTex": "GRIDWALL", "outdoor": true, "sky": 0}],
		"lines": {}, "linedefs": [], "props": [], "scatters": [], "textures": [],
		"things": [{"id": 1, "type": "START", "x": mid, "y": mid - 8 * CELL, "angle": PI / 2}],
		# the grid's world: nothing burns, nobody comes, the green sky
		"world": DocCompile.default_world(),
		"nextId": 2,
	}
