## MEWD — THE ANNEXE: a map in storeys, for the engine's room over room
## (--map=layers; godot/tests/layers_test.gd plays it).
##
## THE FIRST MAP IN BLOCKS (BlockCompile): a yard, which is the ground
## plane itself, and a building on it put up block by block the way the
## editor puts one up, in three layers:
##
##   LAYER 0, THE GROUND   the SHOP: a concrete floor patch (768..1152 x
##                         512..1024, no height), four wall blocks 16
##                         thick round it, 128 high, the west wall cut
##                         for a door (the piece over the doorway a
##                         LINTEL block floating at 96); and a flight of
##                         seven STAIRS east of it (1216..1472 x 1024..
##                         1344), a strip of block for each step, 16
##                         higher than the last, the terrace one more
##   LAYER 1, UPSTAIRS     the OFFICE's floor, a slab over the whole shop
##                         (its walls included, so it stands on them at
##                         112, 16 thick to 128, its underside the shop's
##                         ceiling); the office's walls on the slab, up
##                         to 320, the east wall cut for a sliding door;
##                         and the TERRACE beside it (1168..1536 x 496..
##                         1040), a slab floating at 112 over open yard,
##                         its top at 128, the office floor's height
##   LAYER 2, THE ROOF     a slab over the office's walls
##
## So the yard runs on under the terrace (its ceiling there the
## terrace's underside), the office's walls stand on its floor on the
## shop's walls, and one point of the plan can be in the yard, under the
## deck, or up on it. A shopper downstairs under the terrace, one on the
## terrace, a townie in the office.
class_name LayersMap

const WALL_H := 112.0
const SLAB := 16.0
const OFFICE_H := 192.0
const DOOR_H := 96.0
## the office's floor: the shop's walls, and the slab on them
const DECK := WALL_H + SLAB

class Layer:
	var V: Array = []
	var blocks: Array = []
	var lines := {}
	var next_id: int
	func _init(first_id: int) -> void:
		next_id = first_id
	func vert(p: Vector2) -> int:
		for i in V.size():
			if V[i].distance_to(p) < 0.49:
				return i
		V.append(p)
		return V.size() - 1
	## a block over the rectangle x0..x1, y0..y1; p: its fields
	func rect(x0: float, y0: float, x1: float, y1: float, p: Dictionary) -> Dictionary:
		var b := {"id": next_id, "verts": [vert(Vector2(x0, y0)), vert(Vector2(x1, y0)), vert(Vector2(x1, y1)), vert(Vector2(x0, y1))],
			"h": 128.0, "base": null, "top": "CONC_1", "side": "GRIDWALL", "under": null, "light": 0.72, "name": ""}
		b.merge(p, true)
		next_id += 1
		blocks.append(b)
		return b
	func line_key(a: Vector2, b: Vector2) -> String:
		return "%d,%d" % [mini(vert(a), vert(b)), maxi(vert(a), vert(b))]
	func out() -> Dictionary:
		return {"vertices": V, "blocks": blocks, "lines": lines}

static func build() -> Dictionary:
	var wall := {"h": WALL_H, "side": "CITYMET1", "top": "CITYMET1", "name": "wall"}
	# THE GROUND: the shop and the stairs
	var g0 := Layer.new(1)
	g0.rect(768, 512, 1152, 1024, {"h": 0.0, "top": "CONC_2", "name": "shop"})
	g0.rect(752, 496, 768, 704, wall)
	g0.rect(752, 704, 768, 832, {"h": WALL_H - DOOR_H, "base": DOOR_H, "side": "CITYMET1", "top": "CITYMET1", "under": "CITYMET1", "name": "lintel"})
	g0.rect(752, 832, 768, 1040, wall)
	g0.rect(1152, 496, 1168, 1040, wall)
	g0.rect(768, 496, 1152, 512, wall)
	g0.rect(768, 1024, 1152, 1040, wall)
	# the shop's door: on the lintel's inner edge, swinging into the shop
	g0.lines[g0.line_key(Vector2(768, 704), Vector2(768, 832))] = {"door": {"h": DOOR_H}}
	# THE STAIRS: seven steps up from the yard, the terrace's edge the eighth
	for k in 7:
		var y1 := 1344.0 - roundf(320.0 * k / 7.0)
		var y0 := 1344.0 - roundf(320.0 * (k + 1) / 7.0)
		g0.rect(1216, y0, 1472, y1, {"h": 16.0 * (k + 1), "top": "CONC_1", "side": "CITYCON1", "name": "step %d" % (k + 1)})
	# UPSTAIRS: the office's floor on the shop's walls, its walls on that,
	# and the terrace beside it
	var g1 := Layer.new(100)
	g1.rect(752, 496, 1168, 1040, {"h": SLAB, "top": "OFCCARP1", "under": "OFCCEIL1", "side": "CITYMET1", "light": 0.7, "name": "office floor"})
	var owall := {"h": OFFICE_H, "side": "CITYMET2", "top": "CITYMET2", "name": "office wall"}
	g1.rect(752, 496, 768, 1040, owall)
	g1.rect(1152, 496, 1168, 704, owall)
	g1.rect(1152, 704, 1168, 832, {"h": OFFICE_H - DOOR_H, "base": DECK + DOOR_H, "side": "CITYMET2", "top": "CITYMET2", "under": "CITYMET2", "name": "office lintel"})
	g1.rect(1152, 832, 1168, 1040, owall)
	g1.rect(768, 496, 1152, 512, owall)
	g1.rect(768, 1024, 1152, 1040, owall)
	g1.rect(1168, 496, 1536, 1040, {"h": SLAB, "base": WALL_H, "top": "CONC_3", "under": "CONC_3", "side": "CITYCON1", "light": 0.8, "name": "terrace"})
	# the office's door: on the lintel's inner edge, sliding, into the office
	g1.lines[g1.line_key(Vector2(1152, 704), Vector2(1152, 832))] = {"door": {"h": DOOR_H, "style": "slide"}}
	# THE ROOF
	var g2 := Layer.new(200)
	g2.rect(752, 496, 1168, 1040, {"h": SLAB, "top": "CONC_3", "under": "OFCCEIL1", "side": "CITYMET2", "light": 0.75, "name": "roof"})
	var doc := {
		"format": BlockCompile.FORMAT, "version": BlockCompile.VERSION, "name": "THE ANNEXE",
		"ground": {"tex": "LAWN2", "light": 0.9},
		"vertices": g0.V, "blocks": g0.blocks, "lines": g0.lines,
		"layers": {"1": g1.out(), "2": g2.out()},
		"things": [
			{"id": 20, "type": "START", "x": 320.0, "y": 768.0, "angle": 0.0},
			{"id": 21, "type": "SHOPPER", "x": 1344.0, "y": 640.0, "angle": PI},
			{"id": 22, "type": "SHOPPER", "x": 1344.0, "y": 640.0, "angle": PI, "layer": 1},
			{"id": 23, "type": "TOWNIE", "x": 960.0, "y": 900.0, "angle": 0.0, "layer": 1},
		],
		"textures": [], "scatters": [],
		"world": DocCompile.default_world(),
		"nextId": 300,
	}
	return doc
