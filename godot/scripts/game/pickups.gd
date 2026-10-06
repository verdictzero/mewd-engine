## MEWD — THE PICKUPS, at the user's request ("implement these pickups
## and the mechanics / ui elements to utilize them, health ammo armor
## etc, scatter them around, make finite ammo and health a thing, as
## well as armor on top of health").
##
## Twelve kinds, the user's own pictures (assets/things/pickups.png, cut
## from their green screens by tools/pickups-strip.py): a medkit and a
## big one, light and heavy armour, a box of rounds and a crate, a
## battery and a crate of cells, a case of rockets, a mini nuke, the
## bio vats and the alien pod. Each stands on the ground as a card
## turned to the eye, Doom's way (the standee shader: one draw for all
## of them), bobbing a little, lit by itself so it reads on a dark
## field; and a player who walks over one TAKES it — unless it would do
## nothing for them (full health, a full tank), and then it is left for
## later, as Doom leaves it.
##
## WHERE THEY LIE (place): off the map's own seed, through an RNG of
## their own, so the crowd, the herds and the houses are where they were
## and every machine in a match lays the same list — a cache by your
## start, a few down each street of every town, along the country roads,
## in the country round the crowd's gathering places, and the big ones
## out in the meadows by the unicorns (worth the risk). Then the list is
## the HOST'S: a match's welcome carries it, and its snapshots say which
## are taken (`serial`, down_list), so a client draws what the host
## says and never decides a take of its own.
##
## A TAKEN ONE COMES BACK: in a match on a fixed clock (`back`, Quake's
## item timers — knowing when the armour is up is a skill); alone, after
## `sp_back` and only once nobody is near enough to see it appear.
class_name Pickups
extends Node3D

const STRIP := "res://assets/things/pickups.png"
## how close a player comes to take one (Trophies.REACH), and how far
## above or below
const REACH := 20.0
const REACH_Z := 48.0
## how high its foot rides over the ground, and the bob
const RIDE := 3.0
const BOB := 3.0
## alone, a taken one comes back only once no player is this near (50 m)
const UNSEEN := 1600.0

## THE KINDS, in the strip's order. `size` is the card's width in units
## (the drawing sits on the floor of a square cell); `say` the toast's
## name. What it gives: `health` [amount, as far as], `armour` [amount,
## class (1 light, 2 heavy), as far as], `ammo` {tank: amount}, `weapon`.
## `back`: tics before a taken one returns in a match (0: never there);
## `sp_back` alone (0: never). `mp`: laid in a match at all.
## (THE BALANCE, at the user's request — "balance the hell out of
## everything so multiplayer and single player feel balanced and nice and
## playable, a challenge but not one that stop enjoyment" — worked out by
## three designs and a judge over them: GODOT.txt, PICKUPS)
const KINDS := [
	{"key": "health", "say": "MEDKIT", "size": 28.0, "health": [25, 100], "back": 700, "sp_back": 4200, "mp": true},
	{"key": "health_big", "say": "TRAUMA KIT", "size": 40.0, "health": [50, 150], "back": 1400, "sp_back": 0, "mp": true},
	{"key": "armor", "say": "LIGHT ARMOUR", "size": 30.0, "armour": [50, 1, 100], "back": 875, "sp_back": 6300, "mp": true},
	{"key": "armor_big", "say": "HEAVY ARMOUR", "size": 40.0, "armour": [100, 2, 200], "back": 2100, "sp_back": 0, "mp": true},
	{"key": "small_ammo", "say": "BOX OF ROUNDS", "size": 28.0, "ammo": {"rounds": 160}, "back": 525, "sp_back": 4200, "mp": true},
	{"key": "large_ammo", "say": "CRATE OF ROUNDS", "size": 40.0, "ammo": {"rounds": 600}, "back": 1050, "sp_back": 0, "mp": true},
	{"key": "energy_ammo", "say": "PLASMA BATTERY", "size": 28.0, "ammo": {"plasma": 10, "cells": 1}, "back": 700, "sp_back": 4200, "mp": true},
	{"key": "large_energy_ammo", "say": "CELL CRATE", "size": 40.0, "ammo": {"plasma": 25, "cells": 2}, "back": 1400, "sp_back": 0, "mp": true},
	{"key": "rocket_ammo", "say": "ROCKETS", "size": 40.0, "ammo": {"rockets": 4}, "back": 0, "sp_back": 6300, "mp": false},
	{"key": "mini_nuke_ammo", "say": "MINI NUKE", "size": 44.0, "ammo": {"potatoes": 2}, "weapon": "POTATO", "back": 0, "sp_back": 0, "mp": false},
	{"key": "bio_gun_ammo", "say": "BIO VATS", "size": 34.0, "ammo": {"bores": 2}, "back": 0, "sp_back": 6300, "mp": false},
	{"key": "arc_maw_ammo", "say": "ALIEN POD", "size": 32.0, "ammo": {"volts": 2}, "back": 0, "sp_back": 6300, "mp": false},
]

## a kind's index by its key
static func kind_of(key: String) -> int:
	for i in KINDS.size():
		if KINDS[i].key == key:
			return i
	return -1

## what the HUD calls a tank
const TANK_SAY := {"fuel": "FUEL", "co2": "CO2", "bores": "BORES", "rounds": "ROUNDS", "cells": "CELLS",
	"rockets": "ROCKETS", "volts": "VOLTS", "potatoes": "NUKES", "plasma": "PLASMA"}

static func tank_say(tank: String) -> String:
	return TANK_SAY.get(tank, "AMMO")

## the pickup that is drawn for a tank on the HUD (its cell in the strip)
const TANK_ICON := {"fuel": -1, "co2": -1, "bores": 10, "rounds": 4, "cells": 7, "rockets": 8, "volts": 11,
	"potatoes": 9, "plasma": 6}

## WHAT GOES WHERE alone (place). Each site draws its kinds by weight (a
## hundred to a table). SAFE is the country's on an island where nothing
## fights back (no herds): mostly ammunition, as health is little use
## there. The mini nukes are in none of them — laid by rule, a few.
const SITES := {
	"start": [["health", 1], ["armor", 1], ["small_ammo", 1], ["energy_ammo", 1]],
	"street": [["small_ammo", 30], ["health", 22], ["energy_ammo", 14], ["armor", 10], ["rocket_ammo", 8], ["bio_gun_ammo", 8], ["arc_maw_ammo", 8]],
	"square": [["large_ammo", 30], ["health_big", 25], ["large_energy_ammo", 25], ["armor_big", 20]],
	"road": [["small_ammo", 34], ["health", 24], ["energy_ammo", 14], ["armor", 10], ["rocket_ammo", 6], ["bio_gun_ammo", 6], ["arc_maw_ammo", 6]],
	"country": [["small_ammo", 30], ["health", 22], ["energy_ammo", 14], ["armor", 12], ["rocket_ammo", 8], ["bio_gun_ammo", 7], ["arc_maw_ammo", 7]],
	"safe": [["small_ammo", 36], ["energy_ammo", 16], ["rocket_ammo", 12], ["bio_gun_ammo", 12], ["arc_maw_ammo", 10], ["large_ammo", 6], ["health", 4], ["armor", 4]],
	"meadow": [["health_big", 25], ["armor_big", 25], ["large_ammo", 20], ["large_energy_ammo", 15], ["arc_maw_ammo", 15]],
}
## how many of each site, and how far apart (units)
const STREET_EACH := 2          # down each arm of a town's cross
const ROAD_EVERY := 2560.0      # one along a country road every 80 m
const COUNTRY_EACH := 6         # round each of the crowd's gathering places (Islands "pickups" country)
const MEADOW_EVERY := 3         # one by every third herd
const APART := 96.0
const FROM_START := 192.0
const SLOPE := 0.15
## A MATCH'S LAYOUT: rings round the start, the same on every island —
## six caches at RING1 (each a box, a medkit, and one of the specials),
## eight at RING2 (a box, a medkit, light armour or a battery), and a
## cache in the middle; the two heavy armours and the two trauma kits
## each opposite the other, as Quake's are
const RING1 := 4800.0
const RING2 := 9600.0
const RING1_X := ["armor_big", "health_big", "large_energy_ammo", "armor_big", "health_big", "large_ammo"]

var game
## {k (kind), x, y, z, up, back (tic it comes back, -1 not coming), ph (bob phase)}
var items: Array = []
## bumped on every take, return and load: a match sends the down list
## to a client whose last one is older (server.gd)
var serial := 0
var mm: MultiMesh
var mi: MultiMeshInstance3D
var _dirty := true
## the bob: rows written again while any item is near enough to see it
const BOB_NEAR := 1600.0

func _init(g) -> void:
	game = g
	name = "Pickups"

func _ready() -> void:
	if game == null or not game.draw_world:
		return
	var tex: Texture2D = TexBank.decoded(load(STRIP), true)
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/standee.gdshader")
	mat.set_shader_parameter("strip", tex)
	mat.set_shader_parameter("strip_smooth", tex)
	mat.set_shader_parameter("cells", float(KINDS.size()))
	# (one unit a pixel across a 32-unit cell at a scale of one: each card
	# is scaled to its kind's size, Pickups.KINDS)
	mat.set_shader_parameter("cell", Vector2(32.0, 32.0))
	quad.surface_set_material(0, mat)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mi = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Whether this machine decides who takes what: alone, or the host.
func authority() -> bool:
	return game.net == null

# ------------------------------------------------------------------
# WHERE THEY LIE
# ------------------------------------------------------------------

## Lay them on `game.level` off the map's seed. `roads` is the island's
## (Game._roads_of: squares and paths); `mp` lays a match's instead.
func place(seed: int, roads: Dictionary, mp := false) -> void:
	items = []
	var lv = game.level
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x51C4
	var start := Vector2.ZERO
	var facing := 0.0
	for t in lv.things:
		if t.type == "START":
			start = Vector2(t.x, t.y)
			facing = float(t.get("angle", 0.0))
			break
	if mp:
		_place_match(rng, start)
	else:
		_place_alone(rng, start, facing, roads)
	serial += 1
	_dirty = true
	_mow()

func _put(k: int, p: Vector2) -> void:
	items.append({"k": k, "x": p.x, "y": p.y, "z": game.level.floor_at(p.x, p.y), "up": true, "back": -1,
		"ph": float(items.size()) * 1.7})

func _lay(rng: RandomNumberGenerator, key: String, c: Vector2, r: float, start: Vector2) -> Vector2:
	var p := _spot(rng, c, r, start)
	if p != Vector2.INF:
		_put(kind_of(key), p)
	return p

## THE ISLAND ALONE: a cache by your start, a few down each street of
## every town and a big one by its middle, along the country roads, round
## the crowd's gathering places, the big ones in the meadows by the herds
## (worth the risk), and the mini nukes by rule
func _place_alone(rng: RandomNumberGenerator, start: Vector2, facing: float, roads: Dictionary) -> void:
	var lv = game.level
	var spec: Dictionary = game.island_spec.get("pickups", {}) if game.get("island_spec") != null else {}
	var squares: Array = roads.get("squares", [])
	var paths: Array = roads.get("paths", [])
	var homes := []
	for t in lv.things:
		if t.has("home") and not homes.has(t.home):
			homes.append(t.home)
	var herds: bool = lv.things.any(func(t): return t.type == "UNICORN")
	var lay := func(site: String, c: Vector2, r: float) -> void:
		_lay(rng, _draw(rng, site), c, r, start)
	# (DEBUG LAND's showroom first, so the rest keep clear of it)
	if spec.get("showroom", false):
		_showroom(start, facing)
	# 1. A CACHE BY YOUR START: one of each, close
	for e in SITES.start:
		_lay(rng, e[0], start, 480.0, start)
	# 2. THE TOWNS: down each arm of the cross, and a big one by the middle
	for sq in squares:
		var c: Vector2 = sq[0]
		var half: float = sq[1]
		if IslandLevel._is_town(sq):
			var rot: float = sq[2]
			for arm in 4:
				var dir := Vector2.RIGHT.rotated(rot + arm * PI * 0.5)
				for i in STREET_EACH:
					var u := rng.randf_range(256.0, maxf(300.0, half - 160.0))
					lay.call("street", c + dir * u, 48.0)
		else:
			for i in STREET_EACH * 2:
				lay.call("street", c, half * 0.8)
		lay.call("square", c, minf(half * 0.5, 480.0))
	# 3. ALONG THE COUNTRY ROADS (not the streets in a town)
	for r in paths:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var len := a.distance_to(b)
		if len < ROAD_EVERY * 0.5:
			continue
		var dir := (b - a) / len
		var side := Vector2(-dir.y, dir.x) * float(r[2]) * 0.5
		var n := int(len / ROAD_EVERY)
		for k in range(1, n + 1):
			var q: Vector2 = a + dir * (k * len / (n + 1)) + side * (1.0 if k % 2 == 0 else -1.0)
			if squares.any(func(sq): return (sq[0] as Vector2).distance_to(q) < float(sq[1]) * 1.1):
				continue
			lay.call("road", q, 64.0)
	# 4. THE COUNTRY, round where the crowd gathers (on an island where
	# nothing fights back, the SAFE table: mostly ammunition)
	var gathers := _gathers(lv, start, squares)
	var each := int(spec.get("country", COUNTRY_EACH))
	for g in gathers:
		for i in each:
			lay.call("country" if herds else "safe", g, 2000.0)
	# 5. THE MEADOWS: by every third herd, the big ones
	for i in homes.size():
		if i % MEADOW_EVERY == 0:
			lay.call("meadow", homes[i], 640.0)
	# 6. THE MINI NUKES, by rule: by the two herds furthest from your start
	# (CANDY LAND), or at the furthest of the gathering places (an island
	# with no herds); and DEBUG LAND's in its showroom
	if spec.get("showroom", false):
		pass
	elif not homes.is_empty():
		homes.sort_custom(func(x, y): return (x as Vector2).distance_to(start) > (y as Vector2).distance_to(start))
		for i in mini(2, homes.size()):
			_lay(rng, "mini_nuke_ammo", homes[i], 640.0, start)
	elif not gathers.is_empty():
		var far: Vector2 = gathers[0]
		for g in gathers:
			if (g as Vector2).distance_to(start) > far.distance_to(start):
				far = g
		_lay(rng, "mini_nuke_ammo", far, 2000.0, start)

## DEBUG LAND's SHOWROOM: one of each kind, in order, in a zigzag out
## ahead of where you land
func _showroom(start: Vector2, facing: float) -> void:
	var fwd := Vector2(cos(facing), sin(facing))
	var side := Vector2(-fwd.y, fwd.x)
	for i in KINDS.size():
		var q := start + fwd * (320.0 + 112.0 * i) + side * (64.0 if i % 2 == 0 else -64.0)
		if game.level.on_land(q.x, q.y, 0.0):
			_put(i, q)

## A MATCH: the rings round the start (RING1, RING2, scaled down on an
## island smaller than they are), and only what a match's guns use
func _place_match(rng: RandomNumberGenerator, start: Vector2) -> void:
	var b: Rect2 = game.level.bounds
	var half := minf(b.size.x, b.size.y) * 0.5
	var r1 := minf(RING1, 0.4 * half)
	var r2 := minf(RING2, 0.8 * half)
	var t0 := rng.randf() * TAU
	for key in ["small_ammo", "small_ammo", "health", "armor"]:
		for tries in 8:
			var p := _spot(rng, start, 640.0, start)
			if p != Vector2.INF and p.distance_to(start) >= 256.0:
				_put(kind_of(key), p)
				break
	for k in 6:
		var c := _spot(rng, start + Vector2.RIGHT.rotated(t0 + k * TAU / 6.0) * r1, 640.0, start)
		if c == Vector2.INF:
			continue
		for key in ["small_ammo", "health", RING1_X[k]]:
			_lay(rng, key, c, 192.0, start)
	for k in 8:
		var c := _spot(rng, start + Vector2.RIGHT.rotated(t0 + PI / 8.0 + k * TAU / 8.0) * r2, 640.0, start)
		if c == Vector2.INF:
			continue
		for key in ["small_ammo", "health", "armor" if k % 2 == 0 else "energy_ammo"]:
			_lay(rng, key, c, 192.0, start)

## the crowd's gathering places: a few points the people stand round
## (every 37th of them — a prime, as the crowd is dealt round its groups
## in turn, and a stride that shared a factor with their number would
## find one group over and over), away from the towns, which have theirs;
## and on an island with fewer than three, a ring round the start
func _gathers(lv, start: Vector2, squares: Array) -> Array:
	var out := []
	var n := 0
	for t in lv.things:
		if t.type in ["START", "LAMP", "UNICORN", "FOAL"]:
			continue
		n += 1
		if n % 37 == 0:
			var q := Vector2(t.x, t.y)
			if squares.any(func(sq): return (sq[0] as Vector2).distance_to(q) < 3200.0):
				continue
			if not out.any(func(o): return o.distance_to(q) < 3200.0):
				out.append(q)
	if out.size() < 3:
		for i in 6:
			var q := start + Vector2.RIGHT.rotated(i * TAU / 6.0) * 4000.0
			if lv.on_land(q.x, q.y, 64.0) and not out.any(func(o): return o.distance_to(q) < 3200.0):
				out.append(q)
	return out

## a kind off a site's table, by weight
func _draw(rng: RandomNumberGenerator, site: String) -> String:
	var table: Array = SITES.get(site, SITES.country)
	var total := 0
	for e in table:
		total += int(e[1])
	var r := rng.randi() % maxi(1, total)
	for e in table:
		r -= int(e[1])
		if r < 0:
			return e[0]
	return table[0][0]

## a good spot within `r` of `c`: on land, out of the houses, on gentle
## ground, off your start's pod and clear of the others; or INF
func _spot(rng: RandomNumberGenerator, c: Vector2, r: float, start: Vector2) -> Vector2:
	var lv = game.level
	for k in 60:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var p := c + Vector2(cos(a), sin(a)) * d
		if p.distance_to(start) < FROM_START:
			continue
		if not lv.on_land(p.x, p.y, 64.0) or lv.in_house(p.x, p.y, 40.0):
			continue
		if 1.0 - lv.normal_at(p.x, p.y).z > SLOPE:
			continue
		var clear := true
		for it in items:
			if absf(it.x - p.x) < APART and absf(it.y - p.y) < APART:
				clear = false
				break
		if clear:
			return p
	return Vector2.INF

## the grass cut short under every one, or a tuft would hide it
## (and again whenever the grass has let them go: its list of cut circles
## is a few thousand long and every round into the ground adds one, so
## the oldest — these — are the first forgotten, and a stretch of grass
## built again would grow back under the cards: _remow, every 5 s)
var _mow_probe = null

func _mow() -> void:
	if game.veg_damage == null or game.veg_damage.grass == null or items.is_empty():
		return
	for it in items:
		game.veg_damage.grass.mow(float(it.x) / 32.0, -float(it.y) / 32.0, 0.9)
	_mow_probe = Vector3(float(items[0].x) / 32.0, -float(items[0].y) / 32.0, 0.9)

func _remow() -> void:
	if _mow_probe == null or game.veg_damage == null or game.veg_damage.grass == null:
		return
	var mown = game.veg_damage.grass.get("_mown")
	if mown is Array and not mown.has(_mow_probe):
		_mow()

# ------------------------------------------------------------------
# THE WIRE (a match): the list in the welcome, the taken in the snapshots
# ------------------------------------------------------------------

## [[kind, x, y, z], ...], in order: an item's name is its index
func wire_list() -> Array:
	var out := []
	for it in items:
		out.append([it.k, roundi(it.x), roundi(it.y), roundi(it.z)])
	return out

func load_list(list: Array) -> void:
	items = []
	for e in list:
		items.append({"k": int(e[0]), "x": float(e[1]), "y": float(e[2]), "z": float(e[3]), "up": true, "back": -1,
			"ph": float(items.size()) * 1.7})
	serial += 1
	_dirty = true
	_mow()

## the indices of the ones taken and not back
func down_list() -> Array:
	var out := []
	for i in items.size():
		if not items[i].up:
			out.append(i)
	return out

func apply_down(list: Array) -> void:
	var down := {}
	for i in list:
		down[int(i)] = true
	for i in items.size():
		var up := not down.has(i)
		if items[i].up != up:
			items[i].up = up
			_dirty = true

## every one back (a match's next round)
func reset() -> void:
	for it in items:
		it.up = true
		it.back = -1
	serial += 1
	_dirty = true

# ------------------------------------------------------------------
# TAKING
# ------------------------------------------------------------------

func tic() -> void:
	if game.tics % 175 == 0:
		_remow()
	if not authority():
		return
	var tics: int = game.tics
	for p in game.players:
		p.world_tic(tics)
	# (DEBUG LAND, for trying things: everything back after a while, seen
	# or not — Islands "pickups" respawn)
	var test_back := int(game.island_spec.get("pickups", {}).get("respawn", 0)) if game.rules == null else 0
	for i in items.size():
		var it: Dictionary = items[i]
		if not it.up:
			if it.back >= 0 and tics >= it.back:
				if game.rules == null and test_back <= 0 and _seen(it):
					it.back = tics + 35
					continue
				it.up = true
				it.back = -1
				serial += 1
				_dirty = true
			continue
		for p in game.players:
			if p.dead or p.removed:
				continue
			if p.pod != null and p.pod.active and p.pod.holds_player():
				continue
			# (the whole way they came this tic, not only where they stand: in
			# slow motion a body takes four steps to the world's one, and could
			# step over a medkit between two looks)
			var r: float = p.radius + REACH
			if _swept2(p, it) >= r * r or absf(p.z - it.z) >= REACH_Z:
				continue
			if give(p, it.k):
				it.up = false
				var wait: int = int(KINDS[it.k].back if game.rules != null else (test_back if test_back > 0 else KINDS[it.k].sp_back))
				it.back = tics + wait if wait > 0 else -1
				serial += 1
				_dirty = true
				break

## how near (squared) `p` came to `it` over this world tic: the nearest
## point of the line from where they stood at its start (Player.prev)
static func _swept2(p, it: Dictionary) -> float:
	var a := Vector2(p.prev.x, p.prev.y)
	var b := Vector2(p.x, p.y)
	var c := Vector2(it.x, it.y)
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6 or l2 > 256.0 * 256.0:
		return b.distance_squared_to(c)
	var t := clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(c)

## whether any player could see it come back
func _seen(it: Dictionary) -> bool:
	for p in game.players:
		if not p.dead and U.dist2(p.x, p.y, it.x, it.y) < UNSEEN * UNSEEN:
			return true
	return false

## What a kind does for a player — and whether it did anything (if not,
## it stays where it lies). The one who took it hears it, and sees it
## said and a flash of gold (alone; a match's client off its snapshot).
func give(p, k: int) -> bool:
	var kind: Dictionary = KINDS[k]
	var said := []
	var h0: int = p.health
	var a0: int = p.armour
	var took := false
	if kind.has("weapon") and p.give_weapon(kind.weapon):
		took = true
		said.append(Weapons.WEAPONS[kind.weapon].name)
	if kind.has("health") and p.give_health(int(kind.health[0]), int(kind.health[1])):
		took = true
		said.append("+%d HEALTH" % (p.health - h0))
	if kind.has("armour") and p.give_armour(int(kind.armour[0]), int(kind.armour[1]), int(kind.armour[2])):
		took = true
		said.append("+%d ARMOUR" % (p.armour - a0) if p.armour > a0 else "ARMOUR UP")
	if kind.has("ammo"):
		for tank in kind.ammo:
			# (only for a gun you carry: a battery with the rifle full is not
			# taken for the cell of a lance nobody in a match owns)
			if not _feeds_owned(p, tank):
				continue
			var n: int = p.give_ammo(tank, int(kind.ammo[tank]))
			if n > 0:
				took = true
				said.append("+%d %s" % [n, tank_say(tank)])
	if not took:
		return false
	p.got.append(k)
	p.bonus_flash = 6
	if p == game.player and game.net == null:
		feedback(k, said)
	return true

## whether a gun in `p`'s hands' list runs off `tank`
static func _feeds_owned(p, tank: String) -> bool:
	for w in Weapons.ORDER:
		if p.owned.get(w, false) and Weapons.WEAPONS[w].get("ammo", "") == tank:
			return true
	return false

## the toast and the sound of a take (and a match's client, off `got`)
func feedback(k: int, said: Array) -> void:
	var kind: Dictionary = KINDS[k]
	game.toast(kind.say + ("  " + "  ".join(said) if not said.is_empty() else ""))
	var big: bool = kind.has("weapon") or kind.key.ends_with("_big") or kind.key.begins_with("large")
	game.play_sound("powerup" if big else "pickup", null)

# ------------------------------------------------------------------
# DRAWN
# ------------------------------------------------------------------

func draw() -> void:
	if mm == null:
		return
	var n := items.size()
	var t: float = float(game.tics) + game._acc / U.SEC
	var eye := Vector2(game.player.x, game.player.y) if game.player != null else Vector2.ZERO
	# THE WHOLE LIST only when something changed (a take, a return, a load);
	# the cards near enough to see bob every frame, one row each — and which
	# those are is looked at again every half second
	if _dirty or game.tics - _near_at >= 17:
		_near_at = game.tics
		_near.clear()
		for i in n:
			var it: Dictionary = items[i]
			if it.up and absf(it.x - eye.x) < BOB_NEAR and absf(it.y - eye.y) < BOB_NEAR:
				_near.append(i)
	if _dirty:
		_dirty = false
		var rows := PackedFloat32Array()
		rows.resize(n * 16)
		for i in n:
			var it: Dictionary = items[i]
			var j := i * 16
			var s: float = float(KINDS[it.k].size) / 32.0 if it.up else 0.0
			rows[j] = s; rows[j + 1] = 0.0; rows[j + 2] = 0.0; rows[j + 3] = it.x
			rows[j + 4] = 0.0; rows[j + 5] = s; rows[j + 6] = 0.0; rows[j + 7] = _bob_z(it, t)
			rows[j + 8] = 0.0; rows[j + 9] = 0.0; rows[j + 10] = s; rows[j + 11] = -it.y
			# the cell; lit by itself (fullbright, +2), and cold to the thermal sight
			rows[j + 12] = float(it.k); rows[j + 13] = 1.0; rows[j + 14] = 1.0; rows[j + 15] = 2.0
		if mm.instance_count != n:
			mm.instance_count = n
		if n > 0:
			mm.buffer = rows
		return
	for i in _near:
		var it: Dictionary = items[i]
		if not it.up:
			continue
		var s: float = float(KINDS[it.k].size) / 32.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(it.x, _bob_z(it, t), -it.y)))

var _near: Array[int] = []
var _near_at := -1000

func _bob_z(it: Dictionary, t: float) -> float:
	return it.z + RIDE + BOB * (0.5 + 0.5 * sin(t * 0.09 + it.ph))
