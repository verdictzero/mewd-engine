## MEWD — the forest, and it burns (js/forest.js).
##
## The parade stands in the middle of a wood that runs for miles: a
## flat plain of firs and undergrowth, thousands of them, with the car
## park cut out of the middle. It exists to be set on fire. A
## supermarket burning down is a night's work; a forest burning down is
## weather, and watching a front you started walk off toward the
## horizon on its own is the other half of the game.
##
## TWO THINGS, KEPT APART. The SIMULATION — this file — is a grid of
## 64-unit cells with a byte of state each (green, alight, gone) and a
## list of the ones currently burning. It is packed arrays and nothing
## else, and runs with no renderer. The DRAWING is ForestView
## (godot/scripts/render/forest_view.gd): instanced billboards, every
## plant one entry in a buffer. It reads this; nothing here reads it.
##
## THE ART IS FROM THE GOLF PROJECT, and so is the fire. Each sprite
## comes with a BURN MAP baked from its own pixels — where the coals
## sit, how black it ends, WHEN each texel catches, how leafy it is —
## and one number per plant (its cell's progress, `prog`) swept across
## that map takes it from green through scorched, alight and charred
## without a second set of art. See godot/shaders/plant.gdshader.
##
## WHAT SPREADS. Every cell of forest is fuel — the floor is dry needle
## litter — and a cell with a tree in it burns hotter and longer and
## throws fire further. The wind is the fire's (FireSystem.wind), turned
## into the same four multipliers, so the smoke goes where the fire is
## going. That is the whole model, and it percolates: light one tree
## anywhere and, left alone, the whole wood goes, at walking pace
## downwind and a crawl into the wind.
##
## PLANTS AND NO WOOD: a map that places its own plants (PLANT things,
## the editor's and godot/scripts/maps/maze.gd's plaza trees) and has
## no forest floor gets the grid laid over the map so the plants have
## cells to stand in and collide by, and nothing else is grown. A tree
## in a yard is then a tree on fire, not a forest fire: its cell has
## fuel, its neighbours have none.
##
## NOTE ON THE PACKED ARRAYS (as in fire.gd): they are copy-on-write
## values, so every write goes through the member itself.
class_name Forest
extends RefCounted

const CELL := 64
## the store's clock, so the two fires keep time
const FIRE_INTERVAL := 9

## How each kind of plant is drawn and what it does to a fire.
##
##   h      world units tall (the sprite's foot on the ground)
##   aspect the sprite's width over its height
##   r      trunk radius you cannot walk through; 0 walks through it
##   w      how often it is planted, out of the tree weights
##   cover  ground cover, planted separately and more thinly
##   set    a vandre biome (the user's own painted plants, from
##          github.com/verdictzero/vandre): weight nought, so the wood
##          never plants one; they come from a map's own things
##
## The street trees and the vandre sets are photographs and paintings
## on 128- or 256-pixel tiles; THE ASPECT IS THE ARTWORK'S and not the
## tile's, so the tile is squashed going in and stretched coming out.
const KINDS := [
	{"name": "fir_tall_1", "h": 300, "aspect": 0.5, "r": 14, "w": 22},
	{"name": "fir_tall_2", "h": 290, "aspect": 0.5, "r": 13, "w": 22},
	{"name": "fir_medium", "h": 232, "aspect": 0.5, "r": 14, "w": 16},
	{"name": "fir_young", "h": 150, "aspect": 0.5, "r": 9, "w": 14},
	{"name": "bush_large_1", "h": 86, "aspect": 1.0, "r": 18, "w": 8},
	{"name": "bush_large_2", "h": 82, "aspect": 1.0, "r": 18, "w": 7},
	{"name": "bush_small_1", "h": 62, "aspect": 1.0, "r": 12, "w": 6},
	{"name": "bush_small_2", "h": 60, "aspect": 1.0, "r": 12, "w": 5},
	{"name": "fern", "h": 46, "aspect": 1.0, "r": 0, "w": 0, "cover": true},
	{"name": "grass", "h": 40, "aspect": 1.0, "r": 0, "w": 0, "cover": true},
	{"name": "street_round", "h": 280, "aspect": 0.683, "r": 14, "w": 0},
	{"name": "street_broad", "h": 300, "aspect": 0.660, "r": 15, "w": 0},
	{"name": "street_oval", "h": 290, "aspect": 0.666, "r": 14, "w": 0},
	{"name": "street_upright", "h": 310, "aspect": 0.610, "r": 14, "w": 0},
	{"name": "street_dense", "h": 268, "aspect": 0.670, "r": 13, "w": 0},
	{"name": "street_big", "h": 330, "aspect": 0.667, "r": 16, "w": 0},
	{"name": "desert_big_cactus_1", "h": 240, "aspect": 0.503, "r": 10, "w": 0, "set": "desert"},
	{"name": "desert_cactus_5", "h": 190, "aspect": 0.492, "r": 9, "w": 0, "set": "desert"},
	{"name": "desert_cactus_6", "h": 180, "aspect": 0.488, "r": 9, "w": 0, "set": "desert"},
	{"name": "desert_creosote_bush_5", "h": 84, "aspect": 1.421, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_creosote_bush_6", "h": 84, "aspect": 1.421, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_dead_creosote_bush_5", "h": 88, "aspect": 1.324, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_dead_creosote_bush_6", "h": 84, "aspect": 1.399, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_bush_1", "h": 92, "aspect": 1.523, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_bush_2", "h": 80, "aspect": 1.550, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_small_cactus_1", "h": 76, "aspect": 0.627, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "desert_small_cactus_2", "h": 72, "aspect": 0.464, "r": 0, "w": 0, "set": "desert", "cover": true},
	{"name": "meadow_bush_var_a", "h": 64, "aspect": 1.000, "r": 0, "w": 0, "set": "meadow", "cover": true},
	{"name": "meadow_bush_var_b", "h": 64, "aspect": 1.000, "r": 0, "w": 0, "set": "meadow", "cover": true},
	{"name": "meadow_grass_var_a", "h": 36, "aspect": 1.359, "r": 0, "w": 0, "set": "meadow", "cover": true},
	{"name": "meadow_grass_var_b", "h": 36, "aspect": 1.309, "r": 0, "w": 0, "set": "meadow", "cover": true},
	{"name": "meadow_tree_big", "h": 290, "aspect": 0.746, "r": 14, "w": 0, "set": "meadow"},
	{"name": "meadow_tree_medium", "h": 220, "aspect": 0.660, "r": 12, "w": 0, "set": "meadow"},
	{"name": "meadow_tree_really_big", "h": 340, "aspect": 1.016, "r": 18, "w": 0, "set": "meadow"},
	{"name": "new_meadow_fern_1", "h": 44, "aspect": 1.992, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_fern_2", "h": 44, "aspect": 1.968, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_fern_3", "h": 44, "aspect": 1.961, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_fern_4", "h": 44, "aspect": 2.000, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_bush_1", "h": 84, "aspect": 1.502, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_bush_2", "h": 56, "aspect": 1.554, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_bush_3", "h": 80, "aspect": 1.676, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_bush_4", "h": 84, "aspect": 1.516, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_flower_1", "h": 64, "aspect": 0.690, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_flower_2", "h": 70, "aspect": 0.624, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_grass_1", "h": 44, "aspect": 1.157, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_grass_2", "h": 36, "aspect": 1.214, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_grass_tall_1", "h": 84, "aspect": 0.488, "r": 0, "w": 0, "set": "new meadow", "cover": true},
	{"name": "new_meadow_tree_1", "h": 380, "aspect": 1.004, "r": 18, "w": 0, "set": "new meadow"},
	{"name": "new_meadow_tree_2", "h": 320, "aspect": 1.332, "r": 18, "w": 0, "set": "new meadow"},
	{"name": "new_meadow_tree_3", "h": 320, "aspect": 1.330, "r": 18, "w": 0, "set": "new meadow"},
	{"name": "pine_fern_1", "h": 44, "aspect": 1.992, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_fern_2", "h": 44, "aspect": 1.968, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_fern_3", "h": 44, "aspect": 1.961, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_fern_4", "h": 44, "aspect": 2.000, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_fir_tree_1", "h": 300, "aspect": 0.563, "r": 13, "w": 0, "set": "pine barrens"},
	{"name": "pine_fir_tree_2", "h": 310, "aspect": 0.555, "r": 13, "w": 0, "set": "pine barrens"},
	{"name": "pine_fir_tree_3", "h": 320, "aspect": 0.523, "r": 14, "w": 0, "set": "pine barrens"},
	{"name": "pine_fir_tree_4", "h": 340, "aspect": 0.497, "r": 14, "w": 0, "set": "pine barrens"},
	{"name": "pine_forest_bush_1", "h": 60, "aspect": 2.000, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_forest_bush_2", "h": 56, "aspect": 1.992, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_forest_bush_3", "h": 60, "aspect": 1.536, "r": 0, "w": 0, "set": "pine barrens", "cover": true},
	{"name": "pine_juvenile_fir_tree_1", "h": 150, "aspect": 0.843, "r": 9, "w": 0, "set": "pine barrens"},
	{"name": "pine_juvenile_fir_tree_2", "h": 160, "aspect": 0.945, "r": 9, "w": 0, "set": "pine barrens"},
	{"name": "pine_juvenile_fir_tree_4", "h": 160, "aspect": 0.965, "r": 9, "w": 0, "set": "pine barrens"},
	{"name": "pine_barrens_tree", "h": 360, "aspect": 0.496, "r": 14, "w": 0, "set": "pine barrens"},
	{"name": "savanna_grass_short_1", "h": 50, "aspect": 1.196, "r": 0, "w": 0, "set": "savanna", "cover": true},
	{"name": "savanna_grass_short_2", "h": 52, "aspect": 1.253, "r": 0, "w": 0, "set": "savanna", "cover": true},
	{"name": "savanna_grass_tall_1", "h": 116, "aspect": 0.491, "r": 0, "w": 0, "set": "savanna", "cover": true},
	{"name": "savanna_grass_tall_2", "h": 116, "aspect": 0.488, "r": 0, "w": 0, "set": "savanna", "cover": true},
	{"name": "savanna_tree_1", "h": 330, "aspect": 0.571, "r": 12, "w": 0, "set": "savanna"},
	{"name": "wasteland_bush_1", "h": 88, "aspect": 1.523, "r": 0, "w": 0, "set": "wasteland", "cover": true},
	{"name": "wasteland_small_tree_1", "h": 200, "aspect": 1.000, "r": 14, "w": 0, "set": "wasteland"},
	{"name": "wasteland_tree", "h": 260, "aspect": 0.684, "r": 14, "w": 0, "set": "wasteland"},
	{"name": "wasteland_tree_big_2", "h": 340, "aspect": 0.661, "r": 16, "w": 0, "set": "wasteland"},
	{"name": "wasteland_tree_big_3", "h": 330, "aspect": 0.559, "r": 16, "w": 0, "set": "wasteland"},
	{"name": "wasteland_tree_small_2", "h": 190, "aspect": 1.183, "r": 14, "w": 0, "set": "wasteland"},
	{"name": "farm_wheat_1", "h": 88, "aspect": 0.498, "r": 0, "w": 0, "set": "farmland", "cover": true},
	{"name": "farm_wheat_2", "h": 72, "aspect": 0.625, "r": 0, "w": 0, "set": "farmland", "cover": true},
	{"name": "farm_wheat_3", "h": 66, "aspect": 0.654, "r": 0, "w": 0, "set": "farmland", "cover": true},
	{"name": "farm_wheat_4", "h": 110, "aspect": 0.347, "r": 0, "w": 0, "set": "farmland", "cover": true},
	{"name": "tundra_bush_1", "h": 62, "aspect": 1.608, "r": 0, "w": 0, "set": "tundra", "cover": true},
	{"name": "tundra_bush_2", "h": 56, "aspect": 1.762, "r": 0, "w": 0, "set": "tundra", "cover": true},
	{"name": "tundra_bush_3", "h": 56, "aspect": 1.750, "r": 0, "w": 0, "set": "tundra", "cover": true},
	{"name": "tundra_bush_4", "h": 58, "aspect": 1.728, "r": 0, "w": 0, "set": "tundra", "cover": true},
	{"name": "tundra_bush_5", "h": 60, "aspect": 1.656, "r": 0, "w": 0, "set": "tundra", "cover": true},
]

## The fire's numbers. Durations are in fire tics (FIRE_INTERVAL game
## tics each); chances are out of 256 per fire tic per neighbour.
##
## SLOW AND SURE, and those are two different dials. The chances stay
## HIGH (a burning cell lights most of its neighbours before it is done)
## and the burn is LONG, with nothing able to spread until it is a third
## of the way through. A ground cell smoulders for ten seconds, a tree
## for eighteen, and a front walks downwind at a cell every eight
## seconds or so, creeps against the wind, and always takes the lot.
const BURN := {
	"treeTics": 110, "groundTics": 60,
	"w0": 0.30, "w1": 0.90,          # the part of a burn that can light a neighbour
	"treeToTree": 5.0, "treeToGround": 4.0, "groundToTree": 5.0, "groundToGround": 4.0,
	"diagonal": 0.6,
}

## THE PLANTING, taken from github.com/verdictzero/golf's own vegetation
## scatter. ONE CELL GROWS ONE CLASS, and the three weights are a
## PRIORITY: firs take their share first and are never squeezed, bushes
## take theirs out of what the trunks left through a THRESHOLDED clump
## noise (so scrub arrives in thickets), ground cover fills whatever is
## still empty. The understory is several plants a cell. The pairs are
## (deep in a wood, out in the open), interpolated by the wood mask.
const PLANT := {
	"treeForest": 0.46, "treeOpen": 0.02,
	"bushForest": 0.72, "bushOpen": 0.50, "bushPerCell": 2,
	"coverForest": 0.86, "coverOpen": 0.0, "coverPerCell": 3,
	"bushClumpLo": 0.46, "bushClumpHi": 0.72,
}

## One class of plants, struct of arrays: the canopy (`trees`) or the
## understory (`covers`). Filled once at planting and never written after.
class PlantSet:
	var x := PackedFloat32Array()
	var y := PackedFloat32Array()
	var kind := PackedInt32Array()
	var scale := PackedFloat32Array()
	var flip := PackedByteArray()
	var seed := PackedFloat32Array()
	var cell := PackedInt32Array()
	## the floor it stands on: the wood's is zero, a map's plant stands
	## on its sector's floor
	var z := PackedFloat32Array()
	var n := 0

	func add(px: float, py: float, k: int, s: float, f: int, sd: float, c: int, pz := 0.0) -> void:
		x.append(px); y.append(py); kind.append(k); scale.append(s)
		flip.append(f); seed.append(sd); cell.append(c); z.append(pz)
		n += 1

static var _by_name := {}
static var _tree_kinds := PackedInt32Array()
static var _bush_kinds := PackedInt32Array()
static var _cover_kinds := PackedInt32Array()
static var _tree_weight := 0.0
static var _bush_weight := 0.0

static func _tables() -> void:
	if not _by_name.is_empty():
		return
	for i in KINDS.size():
		var k: Dictionary = KINDS[i]
		_by_name[k.name] = i
		if is_canopy(k):
			_tree_kinds.append(i)
			_tree_weight += float(k.w)
		elif not k.get("cover", false):
			_bush_kinds.append(i)
			_bush_weight += float(k.w)
		else:
			_cover_kinds.append(i)

## Canopy: one to a cell, in the trees array, and it stops you. Tall
## enough, or told so — the flag is there for a plant that is short and
## still blocks.
static func is_canopy(k: Dictionary) -> bool:
	return not k.get("cover", false) and bool(k.get("canopy", float(k.h) > 120.0))

## The kind's index in KINDS by name, or -1 (js/editor/scatter.js plantKind).
static func kind_index(name: String) -> int:
	_tables()
	return _by_name.get(name, -1)

static func is_canopy_kind(name: String) -> bool:
	var i := kind_index(name)
	return i >= 0 and is_canopy(KINDS[i])

## THE PLANTS, placed (compileDoc in js/editor/doc.js): the PLANT things
## of a document as the list the forest grows from. The forest keeps ONE
## TREE TO A 64 CELL, so a second tree in a cell would never appear; it
## is left out here instead, so an editor shows what the game will.
## Cells are counted from the level's bounds, as the grid is.
static func plants_from_things(things: Array, bounds: Rect2) -> Array:
	var out := []
	var tree_cells := {}
	for t in things:
		if str(t.get("type", "")) != "PLANT":
			continue
		var kind := str(t.get("kind", ""))
		if kind_index(kind) < 0:
			continue
		var x := float(t.x)
		var y := float(t.y)
		if is_canopy_kind(kind):
			var c := Vector2i(floori((x - bounds.position.x) / CELL), floori((y - bounds.position.y) / CELL))
			if tree_cells.has(c):
				continue
			tree_cells[c] = true
		var s = t.get("scale")
		out.append({"kind": kind, "x": x, "y": y, "scale": float(s) if s != null else 1.0})
	return out

## How wide a plant is at a given height, as a fraction of its sprite's
## width. A fir is a trunk for its first tenth, widest a third of the
## way up, and a point at the top; a bush is round. This is what the
## flame tests against — getting it wrong is a stream that stops dead
## on a trunk-width of empty air beside a tree.
static func plant_radius(k: Dictionary, f: float) -> float:
	if float(k.aspect) < 1.0:
		if f < 0.10:
			return 0.07
		if f < 0.30:
			return 0.07 + (f - 0.10) / 0.20 * 0.43
		return maxf(0.03, 0.50 * (1.0 - (f - 0.30) / 0.70))
	return 0.12 if f < 0.08 or f > 0.96 else 0.42

## Per-cell randomness that does not depend on the order cells are
## visited, so the same seed plants the same wood on every machine —
## bit for bit the JS hash2 (int32 wrap, Math.imul).
static func hash2(cx: int, cy: int, k: int) -> float:
	var h := (cx * 374761393 + cy * 668265263 + k * 2246822519) & 0xFFFFFFFF
	h = h ^ (h >> 13)
	h = (h * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0

## js/util.js makeRng: xorshift32, for the value noise below.
static func _rng_step(s: int) -> int:
	s ^= (s << 13) & 0xFFFFFFFF
	s ^= s >> 17
	s ^= (s << 5) & 0xFFFFFFFF
	return s

## js/pixel.js valueNoise: a wrapping lattice, smoothstepped between.
static func value_noise(w: int, h: int, cells: int, seed: int) -> PackedFloat32Array:
	var s := seed & 0xFFFFFFFF
	if s == 0:
		s = 0x9e3779b9
	var g := PackedFloat32Array()
	g.resize(cells * cells)
	for i in g.size():
		s = _rng_step(s)
		g[i] = float(s) / 4294967296.0
	var out := PackedFloat32Array()
	out.resize(w * h)
	var sx := float(cells) / w
	var sy := float(cells) / h
	for y in h:
		var fy := y * sy
		var iy := floori(fy)
		var ty := fy - iy
		var wy := ty * ty * (3.0 - 2.0 * ty)
		var y0 := posmod(iy, cells)
		var y1 := (y0 + 1) % cells
		for x in w:
			var fx := x * sx
			var ix := floori(fx)
			var tx := fx - ix
			var wx := tx * tx * (3.0 - 2.0 * tx)
			var x0 := posmod(ix, cells)
			var x1 := (x0 + 1) % cells
			var a := g[y0 * cells + x0]
			var b := g[y0 * cells + x1]
			var c := g[y1 * cells + x0]
			var d := g[y1 * cells + x1]
			var top := a + (b - a) * wx
			out[y * w + x] = top + ((c + (d - c) * wx) - top) * wy
	return out

## js/pixel.js fbm: octaves of value noise, each twice as fine and half
## as strong.
static func fbm(w: int, h: int, base_cells: int, octaves: int, seed: int, gain := 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var amp := 1.0
	var total := 0.0
	var cells := base_cells
	for o in octaves:
		var n := value_noise(w, h, cells, seed + o * 7919)
		for i in out.size():
			out[i] += n[i] * amp
		total += amp
		amp *= gain
		cells *= 2
		if cells > w:
			break                    # finer than a texel is just noise
	for i in out.size():
		out[i] /= total
	return out

var level: Level
var seed := 5
## the wood's floor, as map-space rects (Rect2); none on an editor map
var rects: Array = []
var bounds := Rect2()
## the car park: a margin round it stays open
var clearing := Rect2()
var plants_only := false
var no_burn := false
var origin_x := 0.0
var origin_y := 0.0
var cols := 0
var rows := 0
var tics := 0

var fuel := PackedByteArray()       # 1 where there is forest floor
var tree := PackedByteArray()       # 1 where a tree stands (fire lives longer)
var state := PackedByteArray()      # 0 green, 1 alight, 2 gone
var prog := PackedByteArray()       # how far through the burn, 0..255
var cell_tree := PackedInt32Array()
## The understory is SEVERAL plants a cell, laid down contiguously, so a
## cell points at a run of them rather than at one.
var cover_start := PackedInt32Array()
var cover_count := PackedByteArray()
var active := PackedInt32Array()
var _active_set := PackedByteArray()
## WHICH CELLS CHANGED, for the drawing to repaint: ForestView takes them
var dirty := PackedInt32Array()
var _dirty_set := PackedByteArray()
var fuel_cells := 0
var burn_accum := 0              # sum of prog over every cell, for the fraction
var hot_cells := 0
var town_plants := 0

var trees := PlantSet.new()
var covers := PlantSet.new()

## the weather, as the wood feels it: FireSystem's wind (units a tic)
## and rain, which the game copies over each tic so the two fires agree
var wind := Vector2(0.28, 0.05)
var rain := 0.0

## opts: rects (Array of Rect2, the forest floor), bounds (Rect2, the
## grid's extent; the level's by default), clearing (Rect2), seed, and
## plants (the placed list; from level.things by default).
func _init(lv: Level, opts := {}) -> void:
	_tables()
	level = lv
	seed = int(opts.get("seed", 5))
	rects = opts.get("rects", [])
	bounds = opts.get("bounds", lv.bounds)
	clearing = opts.get("clearing", Rect2())
	no_burn = bool(lv.world.get("noBurn", false))
	var plants: Array = opts.get("plants", plants_from_things(lv.things, lv.bounds))
	origin_x = bounds.position.x
	origin_y = bounds.position.y
	plants_only = rects.is_empty() and not plants.is_empty()
	if not rects.is_empty() or plants_only:
		cols = ceili(bounds.size.x / CELL)
		rows = ceili(bounds.size.y / CELL)
	var n := maxi(1, cols * rows)
	for arr in ["fuel", "tree", "state", "prog", "cover_count", "_active_set", "_dirty_set"]:
		var a: PackedByteArray = get(arr)
		a.resize(n)
		a.fill(0)
		set(arr, a)
	cell_tree.resize(n)
	cell_tree.fill(-1)
	cover_start.resize(n)
	cover_start.fill(-1)
	if not rects.is_empty():
		_seed()
		_plant()
	# AND THE PLACED PLANTING, which is not a scatter: a tree in a plaza,
	# shrubs along a foundation — put there by the map, and grown here
	# because this is where plants are drawn
	if cols > 0 and not plants.is_empty():
		_plant_town(plants)

# ------------------------------------------------------------------
# The grid
# ------------------------------------------------------------------
func idx(cx: int, cy: int) -> int:
	return cy * cols + cx

func cell_x(x: float) -> int:
	return clampi(floori((x - origin_x) / CELL), 0, cols - 1)

func cell_y(y: float) -> int:
	return clampi(floori((y - origin_y) / CELL), 0, rows - 1)

func world_x(cx: int) -> float:
	return origin_x + cx * CELL + CELL / 2.0

func world_y(cy: int) -> float:
	return origin_y + cy * CELL + CELL / 2.0

func in_rects(x: float, y: float) -> bool:
	for r: Rect2 in rects:
		if x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y:
			return true
	return false

func _seed() -> void:
	for cy in rows:
		for cx in cols:
			if in_rects(world_x(cx), world_y(cy)):
				fuel[idx(cx, cy)] = 1
				fuel_cells += 1

static func _smooth(a: float, b: float, v: float) -> float:
	var t := clampf((v - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _pick(kinds: PackedInt32Array, weight: float, r: float) -> int:
	var n := r * weight
	for k in kinds:
		n -= float(KINDS[k].w)
		if n <= 0.0:
			return k
	return kinds[0]

## Planting. Density comes from a noise field so the wood has clearings
## and thickets rather than being a lattice, and every plant is jittered
## off its cell centre so no two rows line up. A margin round the
## clearing stays open, because a forest hard up against a car park kerb
## is a hedge.
func _plant() -> void:
	# THE WOOD MASK, one field thresholded, and the three classes read off
	# it together so they can never disagree about what a patch of ground
	# is; and one clumping field per class, so a thicket of scrub is not
	# thereby a stand of firs
	var field := fbm(cols, rows, 9, 3, seed * 31 + 7)
	var tree_clump_f := fbm(cols, rows, 5, 2, seed * 17 + 101)
	var bush_clump_f := fbm(cols, rows, 6, 2, seed * 13 + 211)
	var cover_clump_f := fbm(cols, rows, 4, 2, seed * 29 + 307)
	var c := clearing
	const MARGIN := 150.0
	for cy in rows:
		for cx in cols:
			var i := idx(cx, cy)
			if not fuel[i]:
				continue
			var wx := world_x(cx)
			var wy := world_y(cy)
			if c.size != Vector2.ZERO and wx > c.position.x - MARGIN and wx < c.end.x + MARGIN \
					and wy > c.position.y - MARGIN and wy < c.end.y + MARGIN:
				continue
			# how much of a wood this is, 0 in the open and 1 deep in it
			var forest := _smooth(0.34, 0.72, field[i])
			# the three weights, each through its own clump; the bushes'
			# thresholded rather than scaled — clear ground with thickets
			var tree_clump := 0.55 + tree_clump_f[i] * 0.9
			var cover_clump := 0.55 + cover_clump_f[i] * 0.9
			var bush_clump := _smooth(PLANT.bushClumpLo, PLANT.bushClumpHi, bush_clump_f[i])
			var d_tree: float = (PLANT.treeOpen + (PLANT.treeForest - PLANT.treeOpen) * forest) * tree_clump
			var d_bush: float = (PLANT.bushOpen + (PLANT.bushForest - PLANT.bushOpen) * forest) * bush_clump
			var d_cover: float = (PLANT.coverOpen + (PLANT.coverForest - PLANT.coverOpen) * forest) * cover_clump
			# and the priority clamp, which is the whole character of it
			d_tree = minf(d_tree, 1.0)
			d_bush = minf(d_bush, 1.0 - d_tree)
			d_cover = minf(d_cover, 1.0 - d_tree - d_bush)
			var keep := hash2(cx, cy, 1)
			if keep >= d_tree + d_bush + d_cover:
				continue
			if keep < d_tree:
				# A FIR. One a cell, and the only class that stops you.
				var kind := _pick(_tree_kinds, _tree_weight, hash2(cx, cy, 2))
				trees.add(wx + (hash2(cx, cy, 3) - 0.5) * CELL * 0.8, wy + (hash2(cx, cy, 4) - 0.5) * CELL * 0.8,
					kind, 0.86 + hash2(cx, cy, 5) * 0.32, 1 if hash2(cx, cy, 6) < 0.5 else 0, hash2(cx, cy, 7), i)
				cell_tree[i] = trees.n - 1
				tree[i] = 1
				continue
			# UNDERSTORY: scrub if the thicket reaches here, litter if it
			# does not. Several of them, jittered across the cell.
			var bushy := keep < d_tree + d_bush
			var n: int = PLANT.bushPerCell if bushy else PLANT.coverPerCell
			cover_start[i] = covers.n
			for k in n:
				var lane := 20 + k * 6
				var kind: int
				if bushy:
					kind = _pick(_bush_kinds, _bush_weight, hash2(cx, cy, lane + 2))
				else:
					kind = _cover_kinds[0] if hash2(cx, cy, lane + 2) < 0.45 else _cover_kinds[1]
				covers.add(wx + (hash2(cx, cy, lane) - 0.5) * CELL * 0.94, wy + (hash2(cx, cy, lane + 1) - 0.5) * CELL * 0.94,
					kind, 0.78 + hash2(cx, cy, lane + 3) * 0.55, 1 if hash2(cx, cy, lane + 4) < 0.5 else 0,
					hash2(cx, cy, lane + 5), i)
			cover_count[i] = n

## Add the placed plants to the wood's arrays. A tree takes its cell —
## one to a cell, the way the wood plants them — so it stops you and the
## fire knows it is there; a shrub goes in with the understory and you
## walk through it. The cell under a placed tree gets fuel, so the
## flamethrower can light it and it burns out on its own, but its
## neighbours have none.
func _plant_town(list: Array) -> void:
	var n := 0
	for p in list:
		var ki := kind_index(str(p.kind))
		if ki < 0:
			continue
		var x := float(p.x)
		var y := float(p.y)
		var cx := cell_x(x)
		var cy := cell_y(y)
		var i := idx(cx, cy)
		var sc := float(p.get("scale", 1.0))
		if is_canopy(KINDS[ki]):
			if cell_tree[i] >= 0:
				continue          # one tree to a cell
			trees.add(x, y, ki, sc, 1 if hash2(cx, cy, 9) < 0.5 else 0, hash2(cx, cy, 11), i, _ground(x, y))
			cell_tree[i] = trees.n - 1
			tree[i] = 1
			if not fuel[i]:
				fuel[i] = 1
				fuel_cells += 1
		else:
			covers.add(x, y, ki, sc, 1 if hash2(cx, cy, 13 + n) < 0.5 else 0, hash2(cx, cy, 17 + n), i, _ground(x, y))
		n += 1
	town_plants = n

# ------------------------------------------------------------------
# Setting it alight
# ------------------------------------------------------------------
## Light every green cell within `radius` of a point. Returns how many.
func ignite(x: float, y: float, radius := 40.0) -> int:
	# and in a world where nothing catches, no plant does either
	if cols == 0 or no_burn:
		return 0
	var lit := 0
	for cy in range(cell_y(y - radius), cell_y(y + radius) + 1):
		for cx in range(cell_x(x - radius), cell_x(x + radius) + 1):
			var i := idx(cx, cy)
			if not fuel[i] or state[i] != 0:
				continue
			_light(i)
			lit += 1
	return lit

## And putting it out: an alight cell goes back to green if it has
## hardly started and to gone if it has, because a tree that is half
## burnt is not a tree you have saved. The line is a third of the way.
func douse(x: float, y: float, radius := 40.0) -> int:
	if cols == 0:
		return 0
	var r2 := radius * radius
	var out := 0
	for cy in range(cell_y(y - radius), cell_y(y + radius) + 1):
		for cx in range(cell_x(x - radius), cell_x(x + radius) + 1):
			var i := idx(cx, cy)
			if state[i] != 1:
				continue
			if U.dist2(world_x(cx), world_y(cy), x, y) > r2:
				continue
			state[i] = 0 if prog[i] < 85 else 2
			if state[i] == 0:
				prog[i] = 0
			_active_set[i] = 0
			_mark(i)
			out += 1
	return out

func _light(i: int) -> void:
	state[i] = 1
	prog[i] = 1
	if not _active_set[i]:
		_active_set[i] = 1
		active.append(i)
	_mark(i)

func _mark(i: int) -> void:
	if _dirty_set[i]:
		return
	_dirty_set[i] = 1
	dirty.append(i)

## The changed cells since the last call, for the drawing — and cleared.
func take_dirty() -> PackedInt32Array:
	var out := dirty
	for i in out:
		_dirty_set[i] = 0
	dirty = PackedInt32Array()
	return out

func burn_fraction() -> float:
	return float(burn_accum) / (255.0 * fuel_cells) if fuel_cells else 0.0

func burning_cells() -> int:
	return hot_cells

func tree_count() -> int:
	return trees.n

func plant_count() -> int:
	return trees.n + covers.n

## Is a cell's plant (or ground) alight right now?
func is_burning(i: int) -> bool:
	return state[i] == 1

# ------------------------------------------------------------------
# One step of the fire
# ------------------------------------------------------------------
func tic() -> void:
	tics += 1
	if cols == 0 or tics % FIRE_INTERVAL:
		return
	var w0: float = BURN.w0
	var w1: float = BURN.w1
	var next := PackedInt32Array()
	var hot := 0
	var wm := FireSystem.wind_multipliers(wind.x, wind.y)
	var m_e := wm[0]
	var m_n := wm[1]
	var m_w := wm[2]
	var m_s := wm[3]
	# the rain, on a wood that is all under the sky: a burn that has
	# hardly started goes out, and nothing lights easily
	var rain_spread := 1.0 - 0.8 * rain
	# a WHILE, not a for over the size: a cell lit by this pass is pushed
	# onto `active` by _light and must be walked (and carried into
	# `next`) in this same pass, as the JS loop's live length does
	var k := -1
	while k + 1 < active.size():
		k += 1
		var i := active[k]
		var dur: int = BURN.treeTics if tree[i] else BURN.groundTics
		var step := maxi(1, roundi(255.0 / dur))
		var before := prog[i]
		var after := mini(255, before + step)
		if rain > 0.0 and before < 85 and U.p_random() < roundi(rain * 14.0):
			# put out early: back to green, the way douse does it
			state[i] = 0
			prog[i] = 0
			_active_set[i] = 0
			_mark(i)
			continue
		prog[i] = after
		burn_accum += after - before
		_mark(i)
		var t := after / 255.0
		if after >= 255:
			state[i] = 2
			_active_set[i] = 0
			continue
		next.append(i)
		if t < w0 or t > w1:
			continue
		hot += 1
		# spread, to the eight neighbours, with the wind
		var cx := i % cols
		var cy := i / cols
		var from_tree := tree[i] != 0
		for dy in range(-1, 2):
			var ny := cy + dy
			if ny < 0 or ny >= rows:
				continue
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				if nx < 0 or nx >= cols:
					continue
				var j := ny * cols + nx
				if not fuel[j] or state[j] != 0:
					continue
				var chance: float
				if from_tree:
					chance = BURN.treeToTree if tree[j] else BURN.treeToGround
				else:
					chance = BURN.groundToTree if tree[j] else BURN.groundToGround
				if dx != 0 and dy != 0:
					chance *= BURN.diagonal
				if dx > 0:
					chance *= m_e
				elif dx < 0:
					chance *= m_w
				if dy > 0:
					chance *= m_n
				elif dy < 0:
					chance *= m_s
				chance *= rain_spread
				if U.p_random() < roundi(chance):
					_light(j)
	active = next
	hot_cells = hot

# ------------------------------------------------------------------
# Questions the rest of the game asks
# ------------------------------------------------------------------
## Is a circle at (x,y) inside a trunk? Bushes count; ferns do not.
func blocks(x: float, y: float, radius: float) -> bool:
	if cols == 0 or trees.n == 0:
		return false
	var cx := cell_x(x)
	var cy := cell_y(y)
	for dy in range(-1, 2):
		var ny := cy + dy
		if ny < 0 or ny >= rows:
			continue
		for dx in range(-1, 2):
			var nx := cx + dx
			if nx < 0 or nx >= cols:
				continue
			var t := cell_tree[ny * cols + nx]
			if t < 0:
				continue
			var kr: float = float(KINDS[trees.kind[t]].r) * trees.scale[t]
			if kr <= 0.0:
				continue
			var rr := kr + radius
			if U.dist2(x, y, trees.x[t], trees.y[t]) < rr * rr:
				return true
	return false

## Does a point in the air touch a plant — the flame's question.
func hits_tree(x: float, y: float, z: float) -> bool:
	if cols == 0 or trees.n == 0:
		return false
	var cx := cell_x(x)
	var cy := cell_y(y)
	for dy in range(-1, 2):
		var ny := cy + dy
		if ny < 0 or ny >= rows:
			continue
		for dx in range(-1, 2):
			var nx := cx + dx
			if nx < 0 or nx >= cols:
				continue
			var t := cell_tree[ny * cols + nx]
			if t < 0:
				continue
			var k: Dictionary = KINDS[trees.kind[t]]
			var s := trees.scale[t]
			var h: float = float(k.h) * s
			# measured from the floor the tree stands on
			var zz := z - trees.z[t]
			if zz < 0.0 or zz > h:
				continue
			var reach: float = plant_radius(k, zz / h) * float(k.h) * float(k.aspect) * s
			if U.dist2(x, y, trees.x[t], trees.y[t]) < reach * reach:
				return true
	return false

## The floor under a placed plant (the JS wood stands at zero, and so
## does the scatter here; a map's plants stand on their sector's floor).
func _ground(x: float, y: float) -> float:
	var s := level.sector_at(x, y)
	return s.floor if s else 0.0

## Keep something inside the wood — only where there IS a wood; an
## editor map's plants are not a boundary.
func clamp_inside(o, margin := 48.0) -> void:
	if rects.is_empty():
		return
	o.x = clampf(o.x, bounds.position.x + margin, bounds.end.x - margin)
	o.y = clampf(o.y, bounds.position.y + margin, bounds.end.y - margin)

## Add what is burning near a point to a light's centre of mass:
## acc is {sx, sy, sw, n}.
func glow_into(acc: Dictionary, px: float, py: float, range := 900.0) -> void:
	if active.is_empty():
		return
	var r2 := range * range
	var step := maxi(1, active.size() >> 7)
	for k in range(0, active.size(), step):
		var i := active[k]
		var t := prog[i] / 255.0
		var q := (t - 0.5) / 0.3
		var w := exp(-q * q) * (1.3 if tree[i] else 0.45) * step
		if w < 0.01:
			continue
		var x := world_x(i % cols)
		var y := world_y(i / cols)
		if U.dist2(x, y, px, py) > r2:
			continue
		acc.sx += x * w
		acc.sy += y * w
		acc.sw += w
		acc.n += 1

## Up to `n` burning cells within range, for things to rise off. Each
## entry: x, y, z (its floor), h (how tall what is burning is), t (how
## far through), tree.
func emitters(px: float, py: float, range: float, n: int) -> Array:
	var out := []
	var len := active.size()
	if len == 0:
		return out
	var r2 := range * range
	var k := (U.p_random() * 256 + U.p_random()) % len
	var tries := mini(len, n * 6)
	for m in tries:
		if out.size() >= n:
			break
		var i := active[(k + m * 7919) % len]
		var t := prog[i] / 255.0
		if t < 0.1 or t > 0.92:
			continue
		var x := world_x(i % cols)
		var y := world_y(i / cols)
		if U.dist2(x, y, px, py) > r2:
			continue
		var ti := cell_tree[i]
		var h: float = float(KINDS[trees.kind[ti]].h) * trees.scale[ti] if ti >= 0 else 30.0
		out.append({"x": trees.x[ti] if ti >= 0 else x, "y": trees.y[ti] if ti >= 0 else y, "z": trees.z[ti] if ti >= 0 else 0.0, "h": h, "t": t, "tree": ti >= 0})
	return out
