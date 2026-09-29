## MEWD Editor — spreading things procedurally, the editor's half
## (js/editor/scatter.js; the growing itself is godot/scripts/level/
## scatter.gd, which the compiler runs). A SCATTER is a rule: an area,
## what to put in it and in what proportions, how thick, how far apart,
## how clumped, and a seed. These are the ready-made mixes, the list of
## what a scatter can put down, and the plant palette's shelves.
class_name EdScatter

const SCATTER_MAX := 4000

static func _plants(o: Dictionary) -> Array:
	var out := []
	for k in o:
		out.append({"type": "PLANT:" + k, "w": o[k]})
	return out

static var _presets := {}

## READY-MADE MIXES (PRESETS), in the web build's order.
static func presets() -> Dictionary:
	if not _presets.is_empty():
		return _presets
	var street := []
	for k in ["street_round", "street_broad", "street_oval", "street_upright", "street_dense", "street_big"]:
		street.append({"type": "PLANT:" + k, "w": 1})
	_presets = {
		"crowd": {"name": "Crowd", "density": 16, "spacing": 110, "clump": 0.35, "items": [{"type": "SHOPPER", "w": 1}]},
		"townsfolk": {"name": "Townsfolk", "density": 8, "spacing": 140, "clump": 0.2,
			"items": [{"type": "TOWNIE", "w": 3}, {"type": "SHOPPER", "w": 1}]},
		"forest": {"name": "Forest", "density": 40, "spacing": 60, "clump": 0.55,
			"items": [{"type": "PLANT:fir_tall_1", "w": 22}, {"type": "PLANT:fir_tall_2", "w": 22}, {"type": "PLANT:fir_medium", "w": 16},
				{"type": "PLANT:fir_young", "w": 14}, {"type": "PLANT:bush_large_1", "w": 8}, {"type": "PLANT:bush_small_1", "w": 6}]},
		"scrub": {"name": "Scrub & grass", "density": 60, "spacing": 26, "clump": 0.6,
			"items": [{"type": "PLANT:grass", "w": 5}, {"type": "PLANT:fern", "w": 4}, {"type": "PLANT:bush_small_1", "w": 1},
				{"type": "PLANT:bush_small_2", "w": 1}]},
		"street": {"name": "Street trees", "density": 5, "spacing": 220, "clump": 0, "items": street},
		"clutter": {"name": "Clutter", "density": 10, "spacing": 90, "clump": 0.45,
			"items": [{"type": "CRATE", "w": 4}, {"type": "TROLLEY", "w": 3}, {"type": "BOLLARD", "w": 2}, {"type": "FUELCAN", "w": 1}]},
		"graveyard": {"name": "Graveyard", "density": 10, "spacing": 120, "clump": 0.1,
			"items": [{"type": "GRAVESTONE", "w": 6}, {"type": "PLANT:bush_small_2", "w": 1}, {"type": "PLANT:fern", "w": 2}]},
		"desert": {"name": "Desert (SAND1)", "density": 14, "spacing": 90, "clump": 0.35,
			"items": _plants({"desert_big_cactus_1": 2, "desert_cactus_5": 3, "desert_cactus_6": 3, "desert_small_cactus_1": 3, "desert_small_cactus_2": 3,
				"desert_creosote_bush_5": 4, "desert_creosote_bush_6": 4, "desert_dead_creosote_bush_5": 2, "desert_dead_creosote_bush_6": 2,
				"desert_bush_1": 3, "desert_bush_2": 3})},
		"meadow": {"name": "Meadow (MEADOW1-5)", "density": 45, "spacing": 40, "clump": 0.5,
			"items": _plants({"new_meadow_tree_1": 1, "new_meadow_tree_2": 1, "new_meadow_tree_3": 1, "new_meadow_bush_1": 3, "new_meadow_bush_2": 3,
				"new_meadow_bush_3": 3, "new_meadow_bush_4": 3, "new_meadow_flower_1": 4, "new_meadow_flower_2": 4,
				"new_meadow_grass_1": 10, "new_meadow_grass_2": 10, "new_meadow_grass_tall_1": 5,
				"new_meadow_fern_1": 2, "new_meadow_fern_2": 2, "new_meadow_fern_3": 2, "new_meadow_fern_4": 2})},
		"meadowOld": {"name": "Meadow, classic (GRASCHK1/2)", "density": 40, "spacing": 40, "clump": 0.5,
			"items": _plants({"meadow_tree_big": 1, "meadow_tree_medium": 1, "meadow_tree_really_big": 1, "meadow_bush_var_a": 4, "meadow_bush_var_b": 4,
				"meadow_grass_var_a": 10, "meadow_grass_var_b": 10})},
		"pine": {"name": "Pine barrens (PINEBAR1)", "density": 40, "spacing": 52, "clump": 0.5,
			"items": _plants({"pine_fir_tree_1": 5, "pine_fir_tree_2": 5, "pine_fir_tree_3": 5, "pine_fir_tree_4": 5, "pine_barrens_tree": 3,
				"pine_juvenile_fir_tree_1": 3, "pine_juvenile_fir_tree_2": 3, "pine_juvenile_fir_tree_4": 3,
				"pine_forest_bush_1": 4, "pine_forest_bush_2": 4, "pine_forest_bush_3": 4,
				"pine_fern_1": 4, "pine_fern_2": 4, "pine_fern_3": 4, "pine_fern_4": 4})},
		"savanna": {"name": "Savanna (SAVANNA1)", "density": 30, "spacing": 48, "clump": 0.55,
			"items": _plants({"savanna_tree_1": 1, "savanna_grass_short_1": 8, "savanna_grass_short_2": 8, "savanna_grass_tall_1": 5, "savanna_grass_tall_2": 5})},
		"wasteland": {"name": "Wasteland (WASTE1)", "density": 8, "spacing": 120, "clump": 0.3,
			"items": _plants({"wasteland_tree": 2, "wasteland_tree_big_2": 1, "wasteland_tree_big_3": 1, "wasteland_small_tree_1": 2,
				"wasteland_tree_small_2": 2, "wasteland_bush_1": 5})},
		"tundra": {"name": "Tundra (TUNDRA1)", "density": 30, "spacing": 44, "clump": 0.55,
			"items": _plants({"tundra_bush_1": 3, "tundra_bush_2": 3, "tundra_bush_3": 3, "tundra_bush_4": 3, "tundra_bush_5": 1})},
		"farmland": {"name": "Wheat field (FARMLND1)", "density": 220, "spacing": 18, "clump": 0,
			"items": _plants({"farm_wheat_1": 3, "farm_wheat_2": 3, "farm_wheat_3": 3, "farm_wheat_4": 2})},
	}
	return _presets

## A new scatter from a preset, over an area (scatterFrom).
static func scatter_from(preset_key: String, area: Dictionary, id: int, seed: int) -> Dictionary:
	var P := presets()
	var p: Dictionary = P.get(preset_key, P.crowd)
	var items := []
	for i in p.items:
		items.append(i.duplicate())
	return {
		"id": id, "name": p.name, "preset": preset_key, "area": area,
		"items": items,
		"density": p.density, "spacing": p.spacing, "clump": p.clump,
		"seed": seed & 0xFFFFFFFF, "scaleMin": 0.85, "scaleMax": 1.15,
	}

static func plant_kinds() -> Array:
	var out := []
	for k in Forest.KINDS:
		out.append(k.name)
	return out

static func plant_kind(name: String):
	var i := Forest.kind_index(name)
	return Forest.KINDS[i] if i >= 0 else null

## The plants, shelved for the palette: the wood's and the town's first,
## then each vandre biome.
static func plant_sets() -> Array:
	var names := []
	var by := {}
	for k in Forest.KINDS:
		var s: String = k.get("set", "wood & town")
		if not by.has(s):
			by[s] = []
			names.append(s)
		by[s].append(k.name)
	var out := []
	for n in names:
		out.append({"name": n, "kinds": by[n]})
	return out

## Every type a scatter's list can name.
static func scatter_types() -> Array:
	var out := ["SHOPPER", "TOWNIE", "CRATE", "TROLLEY", "BOLLARD", "FUELCAN", "GRAVESTONE", "STREETLAMP"]
	for k in plant_kinds():
		out.append("PLANT:" + k)
	return out

static func type_name(t: String) -> String:
	if t.begins_with("PLANT:"):
		return "plant: " + t.substr(6).replace("_", " ")
	return EdDoc.THING_TYPES.get(t, {}).get("name", t)

## a plant's dot: firs dark, bushes mid, cover light, street trees teal
static func plant_colour(kind) -> Color:
	var k := str(kind) if kind != null else ""
	if k.begins_with("fir"):
		return Color.html("#2f8f4a")
	if k.begins_with("bush"):
		return Color.html("#5fbf5a")
	if k.begins_with("street"):
		return Color.html("#3fb8a0")
	return Color.html("#a8e07a")

static func type_colour(t: String) -> Color:
	if t.begins_with("PLANT:"):
		return plant_colour(t.substr(6))
	return EdDoc.col(EdDoc.THING_TYPES.get(t, {}).get("color", "#f0f"))

## The scatter whose area a point is in — the smallest (scatterAt).
static func scatter_at(d: Dictionary, x: float, y: float):
	var best = null
	var ba := INF
	for c in d.get("scatters", []):
		var a: Dictionary = c.area
		var inside := false
		var size := 0.0
		if a.kind == "circle":
			inside = (x - a.x) * (x - a.x) + (y - a.y) * (y - a.y) <= a.r * a.r
			size = a.r * a.r * PI
		elif a.kind == "rect":
			inside = x >= minf(a.x0, a.x1) and x <= maxf(a.x0, a.x1) and y >= minf(a.y0, a.y1) and y <= maxf(a.y0, a.y1)
			size = absf((a.x1 - a.x0) * (a.y1 - a.y0))
		else:
			var ids: Array = a.get("ids", [])
			for s in d.sectors:
				if not ids.has(s.id):
					continue
				var r := EdDoc.ring_of(d, s)
				if EdDoc.pip(r, x, y):
					inside = true
				size += absf(EdDoc.signed_area(r))
		if inside and size < ba:
			ba = size
			best = c
	return best

## The two corners of a scatter's area.
static func scatter_box(d: Dictionary, c: Dictionary) -> Rect2:
	var a: Dictionary = c.area
	if a.kind == "circle":
		return Rect2(a.x - a.r, a.y - a.r, a.r * 2, a.r * 2)
	if a.kind == "rect":
		return Rect2(minf(a.x0, a.x1), minf(a.y0, a.y1), absf(a.x1 - a.x0), absf(a.y1 - a.y0))
	var pts := PackedVector2Array()
	var ids: Array = a.get("ids", [])
	for s in d.sectors:
		if ids.has(s.id):
			pts.append_array(EdDoc.ring_of(d, s))
	return EdDoc.bbox(pts)
