## MEWD — THE ANNEXE: a map in two storeys, for the engine's room over
## room (--map=layers; godot/tests/layers_test.gd plays it).
##
## A yard under the sky, and a building in it drawn in the editor's
## LAYERS (godot/scripts/editor/ed_doc.gd, js/editor/doc.js):
##
##   LAYER 0, THE GROUND   the yard (0..2048 x 0..1536, floor 0); a
##                         ground-floor room, the SHOP (768..1152 x
##                         512..1024, ceiling 128, roofed), with a door on
##                         its west side; and a flight of stairs (1216..
##                         1472 x 1024..1344) cut by the step generator
##                         (EdSteps.make_stairs) from the yard up to the
##                         terrace, a sixteen-unit step at a time
##   LAYER 1, UPSTAIRS     the OFFICE over the shop (floor 128, ceiling
##                         320, roofed) and the TERRACE beside it (1152..
##                         1536 x 512..1024, floor 128, open to the sky)
##                         over open yard, with a door between the two
##
## So the yard runs on under the terrace (its ceiling there the
## terrace's underside), the office's walls stand on the edge of the
## terrace deck and over the shop's, and one point of the plan can be in
## the yard, under the deck, or up on it. A shopper downstairs under the
## terrace, one on the terrace, a townie in the office.
class_name LayersMap

const DECK := 128.0

static func _sector(id: int, verts: Array, p: Dictionary) -> Dictionary:
	var s := {"id": id, "verts": verts, "light": 0.8, "name": ""}
	s.merge(p, true)
	return s

static func build() -> Dictionary:
	# THE GROUND
	var V0 := [
		Vector2(0, 0), Vector2(2048, 0), Vector2(2048, 1536), Vector2(0, 1536),                 # 0-3 the yard
		Vector2(768, 512), Vector2(1152, 512), Vector2(1152, 1024), Vector2(768, 1024),         # 4-7 the shop
		Vector2(768, 704), Vector2(768, 832),                                                    # 8-9 its door
		Vector2(1216, 1024), Vector2(1472, 1024), Vector2(1472, 1344), Vector2(1216, 1344),     # 10-13 the stairs
	]
	var yard := _sector(1, [0, 1, 2, 3], {"floor": 0, "ceil": 512, "floorTex": "LAWN2", "ceilTex": "SKY",
		"wallTex": "CITYCON1", "outdoor": true, "name": "yard", "light": 0.9})
	var shop := _sector(2, [4, 5, 6, 7, 9, 8], {"floor": 0, "ceil": DECK, "floorTex": "CONC_2", "ceilTex": "OFCCEIL1",
		"wallTex": "CITYMET1", "outdoor": false, "sky": 0, "name": "shop", "light": 0.7})
	var stairs := _sector(3, [10, 11, 12, 13], {"floor": 0, "ceil": 512, "floorTex": "CONC_1", "ceilTex": "SKY",
		"wallTex": "CITYCON1", "lowerTex": "CITYCON1", "outdoor": true, "name": "stairs", "light": 0.9})
	var doc := {
		"format": EdDoc.DOC_FORMAT, "version": EdDoc.DOC_VERSION, "name": "THE ANNEXE",
		"vertices": V0, "sectors": [yard, shop, stairs],
		"lines": {"8,9": {"opening": true, "door": {"h": 96}}},
		"linedefs": [], "textures": [], "props": [], "scatters": [],
		"things": [
			{"id": 20, "type": "START", "x": 320.0, "y": 768.0, "angle": 0.0},
			{"id": 21, "type": "SHOPPER", "x": 1344.0, "y": 640.0, "angle": PI},
			{"id": 22, "type": "SHOPPER", "x": 1344.0, "y": 640.0, "angle": PI, "layer": 1},
			{"id": 23, "type": "TOWNIE", "x": 960.0, "y": 900.0, "angle": 0.0, "layer": 1},
		],
		"world": DocCompile.default_world(),
		"nextId": 30,
	}
	# THE STAIRS, as the editor's step generator cuts them: from the yard
	# up towards the terrace's edge, the last step a step under its deck
	var st := EdSteps.make_stairs(doc, stairs, {"from": 0.0, "to": DECK, "dir": Vector2(0, -1), "headroom": false})
	assert(not st.has("error"), str(st.get("error", "")))
	# UPSTAIRS
	var V1 := [
		Vector2(768, 512), Vector2(1152, 512), Vector2(1152, 704), Vector2(1152, 832), Vector2(1152, 1024), Vector2(768, 1024),
		Vector2(1536, 512), Vector2(1536, 1024),
	]
	var office := _sector(10, [0, 1, 2, 3, 4, 5], {"floor": DECK, "ceil": 320, "floorTex": "OFCCARP1", "ceilTex": "OFCCEIL1",
		"wallTex": "CITYMET2", "outdoor": false, "sky": 0, "name": "office", "light": 0.75})
	var terrace := _sector(11, [1, 6, 7, 4, 3, 2], {"floor": DECK, "ceil": 512, "floorTex": "CONC_3", "ceilTex": "SKY",
		"wallTex": "CITYCON1", "outdoor": true, "name": "terrace", "light": 0.9})
	doc["layers"] = {"1": {"vertices": V1, "sectors": [office, terrace], "lines": {"2,3": {"opening": true, "door": {"h": 96, "style": "slide"}}}, "linedefs": []}}
	return doc
