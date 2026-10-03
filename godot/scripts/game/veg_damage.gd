## MEWD — THE ISLAND'S PLANTS CAN BE SHOT, BLOWN UP AND BURNT (at the
## user's request: "vegetation hit by explosives like the rocket blows up
## in chunks, stops existing, and the surrounding vegetation goes alight,
## and spreads, to a point, and eventually self-extinguishes; the minigun
## blows holes in sprites before destroying them").
##
## The plants are the island's own (SCRIPT_veg_scatter.gd): trees, bushes
## and ferns, thousands of them, drawn as MultiMesh rows packed per tile.
## This does not keep a plant list of its own and does not change how the
## scatter places anything (an edit there would invalidate every island's
## bake). It reaches into the scatter's live tile buffers, finds the rows
## near a point, and rewrites just those rows. Each row's custom vec4 is
## shared with SHADER_veg_billboard.gdshader:
##   x  the crash-site burn the scatter baked in (left alone)
##   y  DAMAGE, 0..1: how shot through it is (the shader cuts holes)
##   z  when it CAUGHT, on the `veg_clock` (s), 0 never
##   w  how long it BURNS (s)
## and a plant blown away has its row scaled to nothing. A row's place in
## its tile is fixed (the tile is built the same way every time), so every
## change is also kept here and put back if the tile is ever built again.
##
## THE FIRE IS THE SHADER'S TO DRAW and this file's to spread. When a
## plant catches, its row is written once (z, w) and the GPU runs it
## through green, scorched, alight and charred on the clock. What is
## done here, every SPREAD_EVERY tics, is a burning plant setting fire to
## its neighbours within SPREAD_REACH, at SPREAD_CHANCE each. Every fire
## has a BUDGET of plants and a most generations from the blast, so it
## spreads "to a point", then burns out. Smoke and embers come off the
## burning plants nearest you, a few a tic, and a body stood in a fire
## catches.
class_name VegDamage
extends RefCounted

## (metres, as the island counts)
const SPREAD_REACH := 5.5
const SPREAD_EVERY := 18
const SPREAD_CHANCE := 0.3
## how many plants one fire may take, and how many hops out from the blast
const BUDGET := 70
const GENERATIONS := 6
## a blast blows to pieces what is inside this share of its reach, and
## sets alight what is inside this share
const BLOW_SHARE := 0.45
const LIGHT_SHARE := 1.25
## of the plants round a blast, this share catch, and no more than this
## many, so the fire has its budget left to SPREAD with
const LIGHT_CHANCE := 0.4
const LIGHT_MOST := 15
## how much a round shoots through a plant (1 and it is gone)
const SHOT_DAMAGE := 0.11
## the index buckets over a tile (m)
const BUCKET := 8.0

var game
var veg = null
## plant key -> [tile key, sprite, row, Vector4 custom, gone]
var changed := {}
## the plants alight: [{key, tile, sprite, row, pos (m), h, until (tic), next (tic), gen, fire}]
var burning: Array = []
## caught since the list was last walked (joined to `burning` after)
var _caught: Array = []
## per fire, how many plants it has left to take
var _budget := {}
var _next_fire := 1
## tile key -> {"n": rows when indexed, "b": {Vector2i: [[sprite, row], ...]}}
var _index := {}
var _checked := 0

func _init(g, scatter) -> void:
	game = g
	veg = scatter

static func find_scatter(island: Node):
	if island == null:
		return null
	for n in island.get_children():
		if n.has_method("live_plant_count") and n.get("_meshes") != null and n.get("_class_span") != null:
			return n
	return null

## The island's clock for the shader, in seconds (`veg_clock`).
func clock() -> float:
	return float(game.tics) / U.TICRATE

func _key(tile: Vector2i, sprite: int, row: int) -> int:
	return ((tile.x & 0xfff) << 40) | ((tile.y & 0xfff) << 28) | ((sprite & 0xff) << 20) | row

# ------------------------------------------------------------------
# FINDING PLANTS
# ------------------------------------------------------------------

func _tile_of(m: Vector2) -> Vector2i:
	var ts: float = veg._tile_size
	return Vector2i(floori(m.x / ts), floori(m.y / ts))

## Every row in the tile, bucketed by BUCKET metres (built once a tile).
func _buckets(key: Vector2i) -> Dictionary:
	var rec: Dictionary = veg._tiles.get(key, {})
	if not rec.has("bufs"):
		return {}
	var bufs: Array = rec.bufs
	var n := 0
	for b in bufs:
		n += (b as PackedFloat32Array).size()
	var ix: Dictionary = _index.get(key, {})
	if not ix.is_empty() and int(ix.n) == n:
		return ix.b
	var off: Vector3 = veg._origin_offset
	var b := {}
	for i in bufs.size():
		var buf: PackedFloat32Array = bufs[i]
		for r in buf.size() / 16:
			var k := r * 16
			var q := Vector2i(floori((buf[k + 3] + off.x) / BUCKET), floori((buf[k + 11] + off.z) / BUCKET))
			if not b.has(q):
				b[q] = []
			b[q].append([i, r])
	_index[key] = {"n": n, "b": b}
	return b

## A plant row's facts: {key, tile, sprite, row, pos (m, the island's
## x y z), h (m), w (m), cls (0 tree, 1 bush, 2 fern), custom, gone}.
func _plant(tile: Vector2i, sprite: int, row: int) -> Dictionary:
	var buf: PackedFloat32Array = veg._tiles[tile].bufs[sprite]
	var k := row * 16
	var off: Vector3 = veg._origin_offset
	var h := buf[k + 5]
	var aspect: float = veg._sprite_aspect[sprite] if sprite < veg._sprite_aspect.size() else 1.0
	var cls := 0
	for c in veg._class_span.size():
		var sp: Vector2i = veg._class_span[c]
		if sprite >= sp.x and sprite < sp.x + sp.y:
			cls = c
	return {"key": _key(tile, sprite, row), "tile": tile, "sprite": sprite, "row": row,
		"pos": Vector3(buf[k + 3] + off.x, buf[k + 7] + off.y, buf[k + 11] + off.z),
		"h": h, "w": buf[k] * aspect, "cls": cls,
		"custom": Vector4(buf[k + 12], buf[k + 13], buf[k + 14], buf[k + 15]), "gone": h <= 0.0}

## The standing plants within `r` metres of (mx, mz), the island's metres.
func near(mx: float, mz: float, r: float) -> Array:
	var out := []
	if veg == null:
		return out
	var lo := _tile_of(Vector2(mx - r, mz - r))
	var hi := _tile_of(Vector2(mx + r, mz + r))
	var r2 := r * r
	for tx in range(lo.x, hi.x + 1):
		for tz in range(lo.y, hi.y + 1):
			var key := Vector2i(tx, tz)
			var b := _buckets(key)
			if b.is_empty():
				continue
			var bufs: Array = veg._tiles[key].bufs
			var off: Vector3 = veg._origin_offset
			for bx in range(floori((mx - r) / BUCKET), floori((mx + r) / BUCKET) + 1):
				for bz in range(floori((mz - r) / BUCKET), floori((mz + r) / BUCKET) + 1):
					for e in b.get(Vector2i(bx, bz), []):
						var buf: PackedFloat32Array = bufs[e[0]]
						var k: int = e[1] * 16
						if buf[k + 5] <= 0.0:
							continue
						var dx := buf[k + 3] + off.x - mx
						var dz := buf[k + 11] + off.z - mz
						if dx * dx + dz * dz <= r2:
							out.append(_plant(key, e[0], e[1]))
	return out

# ------------------------------------------------------------------
# CHANGING THEM
# ------------------------------------------------------------------

## Rewrite a plant's row: its custom vec4, and `gone` to scale it away.
func _write(p: Dictionary, custom: Vector4, gone: bool) -> void:
	var tile: Vector2i = p.tile
	var rec: Dictionary = veg._tiles.get(tile, {})
	if not rec.has("bufs"):
		return
	var bufs: Array = rec.bufs
	var i: int = p.sprite
	var buf: PackedFloat32Array = bufs[i]
	var k: int = p.row * 16
	if k + 15 >= buf.size():
		return
	buf[k + 12] = custom.x
	buf[k + 13] = custom.y
	buf[k + 14] = custom.z
	buf[k + 15] = custom.w
	if gone:
		for j in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
			buf[k + j] = 0.0
	bufs[i] = buf
	changed[p.key] = [tile, i, p.row, custom, gone or bool(changed.get(p.key, [0, 0, 0, 0, false])[4])]
	# owed a re-pack, and soon (SCRIPT_veg_scatter.gd `_fill`)
	veg._fill_owed[i] = 1
	veg._force_rescan = true

## Put back what a rebuilt tile has lost (every second, a few at a time).
func _keep() -> void:
	if changed.is_empty():
		return
	var keys := changed.keys()
	for n in mini(40, keys.size()):
		_checked = (_checked + 1) % keys.size()
		var c: Array = changed[keys[_checked]]
		var rec: Dictionary = veg._tiles.get(c[0], {})
		if not rec.has("bufs"):
			continue
		var buf: PackedFloat32Array = rec.bufs[c[1]]
		var k: int = int(c[2]) * 16
		if k + 15 >= buf.size():
			continue
		var want: Vector4 = c[3]
		var stands := buf[k + 5] > 0.0
		if Vector4(buf[k + 12], buf[k + 13], buf[k + 14], buf[k + 15]) != want or (c[4] and stands):
			_write({"tile": c[0], "sprite": c[1], "row": c[2], "key": keys[_checked]}, want, c[4])

## The plant's picture, for its pieces: {tex, w, h}.
func _picture(p: Dictionary) -> Texture2D:
	var inst: MultiMeshInstance3D = veg._instances[p.sprite]
	var mat := inst.material_override as ShaderMaterial
	return mat.get_shader_parameter("albedo_tex") if mat != null else null

## Island metres to the game's units, and back.
static func to_game(m: Vector3) -> Vector3:
	return Vector3(m.x * IslandLevel.U_PER_M, -m.z * IslandLevel.U_PER_M, m.y * IslandLevel.U_PER_M)

## BLOWN TO PIECES: its picture in pieces (SpriteChunks, from `from`, the
## game's units), a puff of leaves, and its row gone.
func blow_up(p: Dictionary, from: Vector3, force := 1.0) -> void:
	if p.gone:
		return
	var tex := _picture(p)
	var at := to_game(p.pos)
	var w: float = p.w * IslandLevel.U_PER_M
	var h: float = p.h * IslandLevel.U_PER_M
	if game.chunks != null and tex != null:
		var pieces := 20 if p.cls == 0 else (10 if p.cls == 1 else 6)
		game.chunks.burst(tex, Rect2(0, 0, 1, 1), at, w, h, from, pieces, force, 0.0, true)
	game.fx.puff(at.x, at.y, at.z + h * 0.4, minf(60.0, w * 0.5), 70)
	_write(p, p.custom, true)
	burning = burning.filter(func(b): return b.key != p.key)
	_caught = _caught.filter(func(b): return b.key != p.key)

## SET ALIGHT: the shader's clock started on it, and it is on the list of
## the burning (as part of fire `fire`, `gen` hops from where it started).
func ignite(p: Dictionary, fire: int, gen: int) -> bool:
	if p.gone or p.custom.z > 0.0:
		return false
	if int(_budget.get(fire, 0)) <= 0:
		return false
	_budget[fire] = int(_budget[fire]) - 1
	# a tree burns longer than a bush, a bush than a fern
	var secs: float = [randf_range(16.0, 24.0), randf_range(9.0, 13.0), randf_range(5.0, 8.0)][int(p.cls)]
	var c: Vector4 = p.custom
	c.z = clock() + 0.01
	c.w = secs
	_write(p, c, false)
	p.custom = c
	_caught.append({"key": p.key, "tile": p.tile, "sprite": p.sprite, "row": p.row, "pos": p.pos, "h": p.h,
		"until": game.tics + int(secs * U.TICRATE), "next": game.tics + SPREAD_EVERY + randi() % SPREAD_EVERY,
		"gen": gen, "fire": fire, "spread_until": game.tics + int(secs * 0.65 * U.TICRATE)})
	return true

func _new_fire() -> int:
	var f := _next_fire
	_next_fire += 1
	_budget[f] = BUDGET
	return f

## A BLAST at `at` (the game's units) reaching `radius` (units): what is
## close goes to pieces, what is round it catches — one new fire.
func blast(at: Vector3, radius: float) -> void:
	if veg == null:
		return
	var m := Vector2(at.x / IslandLevel.U_PER_M, -at.y / IslandLevel.U_PER_M)
	var reach := maxf(3.0, radius / IslandLevel.U_PER_M)
	var fire := _new_fire()
	var lit := 0
	for p in near(m.x, m.y, reach * LIGHT_SHARE):
		var d := Vector2(p.pos.x - m.x, p.pos.z - m.y).length()
		# (a plant's own height counts: the blast has to reach its middle)
		if d < reach * BLOW_SHARE and at.z < (p.pos.y + p.h * 0.8) * IslandLevel.U_PER_M:
			blow_up(p, at, 1.3)
		elif lit < LIGHT_MOST and randf() < LIGHT_CHANCE:
			if ignite(p, fire, 0):
				lit += 1

## A ROUND through the plant: shot through a little more (the shader's
## holes), a scrap of it thrown off, and past 1 it is blown to pieces.
func shoot(p: Dictionary, at: Vector3, dir: Vector3) -> void:
	var c: Vector4 = p.custom
	c.y = minf(1.0, c.y + SHOT_DAMAGE * randf_range(0.7, 1.3))
	var tex := _picture(p)
	if game.chunks != null and tex != null:
		var s := randf_range(5.0, 9.0)
		var u := randf() * 0.6 + 0.2
		var v := randf() * 0.7 + 0.1
		game.chunks.spawn(tex, Rect2(u - 0.08, v - 0.06, 0.16, 0.12), at, s, s,
			Vector3(dir.x * 0.006 + randf_range(-2, 2), dir.y * 0.006 + randf_range(-2, 2), randf_range(2.0, 6.0)), 80, 0.0, true)
	if c.y >= 1.0:
		blow_up(p, at - dir.normalized() * 30.0, 0.8)
		return
	_write(p, c, false)
	p.custom = c

## THE NEAREST PLANT A ROUND FROM a TO b GOES INTO before `max_t`, as
## {t, plant}, or {} — the plants as upright cylinders a third of their
## width round, up to most of their height. Walked over the index
## buckets along the line, so a long shot asks a few dozen plants.
func ray(a: Vector3, b: Vector3, max_t: float) -> Dictionary:
	if veg == null:
		return {}
	var am := Vector3(a.x, a.z, -a.y) / IslandLevel.U_PER_M
	var bm := Vector3(b.x, b.z, -b.y) / IslandLevel.U_PER_M
	var d := bm - am
	var len2 := Vector2(d.x, d.z).length_squared()
	if len2 < 1e-6:
		return {}
	var length := sqrt(len2) * max_t
	var best := {}
	var best_t := max_t
	var seen := {}
	# along the line a bucket at a time
	var steps := int(length / (BUCKET * 0.5)) + 1
	for s in steps + 1:
		var t := minf(max_t, float(s) / steps * max_t)
		var q := am + d * t
		var bx := floori(q.x / BUCKET)
		var bz := floori(q.z / BUCKET)
		for ox in [-1, 0, 1]:
			for oz in [-1, 0, 1]:
				var bk := Vector2i(bx + ox, bz + oz)
				if seen.has(bk):
					continue
				seen[bk] = true
				var tile := _tile_of(Vector2((bk.x + 0.5) * BUCKET, (bk.y + 0.5) * BUCKET))
				var bb := _buckets(tile)
				if bb.is_empty():
					continue
				var bufs: Array = veg._tiles[tile].bufs
				var off: Vector3 = veg._origin_offset
				for e in bb.get(bk, []):
					var buf: PackedFloat32Array = bufs[e[0]]
					var k: int = e[1] * 16
					var h := buf[k + 5]
					if h <= 1.0:
						continue
					var px := buf[k + 3] + off.x
					var py := buf[k + 7] + off.y
					var pz := buf[k + 11] + off.z
					var tt := ((px - am.x) * d.x + (pz - am.z) * d.z) / len2
					if tt <= 0.0 or tt >= best_t:
						continue
					var cx := am.x + d.x * tt - px
					var cz := am.z + d.z * tt - pz
					var aspect: float = veg._sprite_aspect[e[0]]
					var rr := buf[k] * aspect * 0.18
					if cx * cx + cz * cz > rr * rr:
						continue
					var y := am.y + d.y * tt
					if y < py or y > py + h * 0.85:
						continue
					best_t = tt
					best = {"t": tt, "plant": _plant(tile, e[0], e[1])}
	return best

# ------------------------------------------------------------------
# THE FIRE, a tic
# ------------------------------------------------------------------

func tic() -> void:
	if veg == null:
		return
	U.gset("veg_clock", clock())
	if game.tics % U.TICRATE == 0:
		_keep()
	burning.append_array(_caught)
	_caught = []
	if burning.is_empty():
		return
	var now: int = game.tics
	var cam := Vector3(game.player.x, game.player.y, 0.0) if game.player != null else Vector3()
	var still := []
	var smoked := 0
	for f in burning:
		if now >= int(f.until):
			continue
		still.append(f)
		var at := to_game(f.pos)
		var h: float = f.h * IslandLevel.U_PER_M
		# THE SMOKE AND THE EMBERS, off the ones nearest you, a few a tic
		if smoked < 10 and (now + int(f.key)) % 7 == 0 and Vector2(at.x - cam.x, at.y - cam.y).length() < 2400.0:
			smoked += 1
			game.fx.puff(at.x, at.y, at.z + h * 0.8, minf(70.0, h * 0.3), 120)
			game.fx.ember(at.x, at.y, at.z + h * 0.5, 2, 1.0)
		# SPREADING, while it is properly alight
		if now >= int(f.next) and now < int(f.spread_until):
			f.next = now + SPREAD_EVERY
			if int(f.gen) < GENERATIONS and int(_budget.get(f.fire, 0)) > 0:
				for p in near(f.pos.x, f.pos.z, SPREAD_REACH):
					if randf() < SPREAD_CHANCE:
						ignite(p, f.fire, int(f.gen) + 1)
			# and anybody stood in it catches
			for a in game.actors_in_cone_around(at, maxf(48.0, f.h * 8.0)):
				if a.has_method("ignite"):
					a.ignite(160)
	burning = still
	# a fire with nothing left burning is over
	if burning.is_empty() and _caught.is_empty():
		_budget.clear()
