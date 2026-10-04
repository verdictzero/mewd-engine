## MEWD — THE ISLAND'S PLANTS AND GRASS CAN BE SHOT AND BLOWN UP (at the
## user's request: "vegetation hit by explosives like the rocket blows up
## in chunks and stops existing"; then, backing up: no fire, no holes shot
## in anything — plants shredded into pieces of themselves, the big ones
## into more and smaller pieces, and the grass shredded too).
##
## The plants are the island's own (SCRIPT_veg_scatter.gd): trees, bushes
## and ferns, thousands of them, drawn as MultiMesh rows packed per tile.
## This does not keep a plant list of its own and does not change how the
## scatter places anything (an edit there would invalidate every island's
## bake). It reaches into the scatter's live tile buffers, finds the rows
## near a point, and rewrites just those rows: a plant blown away has its
## row scaled to nothing. A round into a plant throws a scrap of it and
## counts against it (the row's custom .y, which nothing draws), and
## enough of them shred it. A row's place in its tile is fixed (the tile
## is built the same way every time), so every change is also kept here
## and put back if the tile is ever built again.
##
## AND IT BUILDS TO IT (at the user's request): a plant takes a number of
## rounds to come apart that grows with its size (`hits_for`: a fern four,
## a big tree fifteen or so), each one SHAKES it — harder the nearer it is
## to going — and a blast blows apart only what is close; further out it
## shakes them and counts against them, so a second rocket finishes the
## tree the first one left standing. The shake is the plant shader's
## (SHADER_veg_billboard `shake_clock`): the row's custom .z is the clock
## when it was hit and .w how hard, so it costs one write a hit.
##
## THE GRASS (SCRIPT_grass_scatter.gd `mow`): a blast clears a patch round
## it, a round into the ground the tufts it lands among, each tuft thrown
## as a few pieces of its own picture.
class_name VegDamage
extends RefCounted

## a blast blows to pieces every plant whose trunk is inside this share of
## its reach (a rocket's is 5.9 m: anything within three metres goes), and
## out to SHAKE_SHARE of it shakes them and counts against them — BLAST_HITS
## rounds' worth at the inner edge, none at the outer
const BLOW_SHARE := 0.5
const SHAKE_SHARE := 1.2
const BLAST_HITS := 10.0
## and mows the grass inside this share, when it went off near the ground
## (units above it)
const MOW_SHARE := 0.6
const MOW_LOW := 96.0
## the grass a round into the ground takes (m)
const NICK := 0.55
## how hard a plant is shaken (m, across), by its width and how near it
## is to coming apart: SHAKE_W of its width, between SHAKE_MIN and SHAKE_MAX,
## half that when first hit and half again as much on the last round
const SHAKE_W := 0.07
const SHAKE_MIN := 0.1
const SHAKE_MAX := 0.7
## at most this many tufts thrown as pieces a mowing
const TUFTS_THROWN := 24
## the index buckets over a tile (m)
const BUCKET := 8.0

var game
var veg = null
var grass = null
## plant key -> [tile key, sprite, row, Vector4 custom, gone]
var changed := {}
## tile key -> {"n": rows when indexed, "b": {Vector2i: [[sprite, row], ...]}}
var _index := {}
var _checked := 0

func _init(g, scatter, grass_scatter = null) -> void:
	game = g
	veg = scatter
	grass = grass_scatter

static func find_scatter(island: Node):
	if island == null:
		return null
	for n in island.get_children():
		if n.has_method("live_plant_count") and n.get("_meshes") != null and n.get("_class_span") != null:
			return n
	return null

## Every plant sprite's material given its picture a second time, for the
## filtered fetch where the plant is minified (SHADER_veg_billboard
## `albedo_smooth`): done here and not in the scatter, whose source is in
## every island's bake digest.
static func bind_smooth(scatter) -> void:
	if scatter == null or scatter.get("_instances") == null:
		return
	for inst in scatter._instances:
		var mat := (inst as MultiMeshInstance3D).material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("albedo_smooth", mat.get_shader_parameter("albedo_tex"))

static func find_grass(island: Node):
	if island == null:
		return null
	for n in island.get_children():
		if n.has_method("live_tuft_count") and n.has_method("mow"):
			return n
	return null

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
	PerfLog.did("veg.write")
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

## SHREDDED: its picture in pieces (SpriteChunks, from `from`, the game's
## units) — the bigger the plant, the more pieces and the smaller each —
## a puff of leaves, and its row gone.
func blow_up(p: Dictionary, from: Vector3, force := 1.0) -> void:
	if p.gone:
		return
	var tex := _picture(p)
	var at := to_game(p.pos)
	var w: float = p.w * IslandLevel.U_PER_M
	var h: float = p.h * IslandLevel.U_PER_M
	if game.chunks != null and tex != null:
		game.chunks.burst(tex, Rect2(0, 0, 1, 1), at, w, h, from, pieces_for(p.w, p.h), force, 0.0, true)
	game.fx.puff(at.x, at.y, at.z + h * 0.4, minf(60.0, w * 0.5), 70)
	_write(p, p.custom, true)

## How many pieces a plant `w` x `h` metres goes to: about a piece for
## every metre square of it (a fern a handful, a tall tree forty), so a
## big plant's pieces come out no bigger than a small one's — and none so
## small they read as glitter.
static func pieces_for(w: float, h: float) -> int:
	return clampi(int(w * h), 6, 40)

## How many rounds a plant `w` x `h` metres takes to come apart: more the
## bigger it is (a fern four, a bush five or six, a tall tree fifteen).
static func hits_for(w: float, h: float) -> int:
	return clampi(roundi(2.0 + 1.5 * sqrt(maxf(0.0, w * h))), 3, 24)

## `hits` rounds' worth against a plant: shaken, and shredded (thrown from
## `from`, the game's units) once it has had all it can take. True if it went.
func hurt(p: Dictionary, hits: float, from: Vector3, force := 0.8) -> bool:
	if p.gone:
		return false
	var c: Vector4 = p.custom
	c.y = minf(1.0, c.y + hits / float(hits_for(p.w, p.h)))
	if c.y >= 1.0:
		blow_up(p, from, force)
		return true
	c.z = game.clock
	c.w = clampf(p.w * SHAKE_W, SHAKE_MIN, SHAKE_MAX) * (0.5 + c.y)
	_write(p, c, false)
	p.custom = c
	return false

## A BLAST at `at` (the game's units) reaching `radius` (units): the plants
## close to it shredded, those further out shaken and hurt, and the grass
## under it, if it went off near the ground, mown.
func blast(at: Vector3, radius: float) -> void:
	var m := Vector2(at.x / IslandLevel.U_PER_M, -at.y / IslandLevel.U_PER_M)
	var reach := maxf(3.0, radius / IslandLevel.U_PER_M)
	if veg != null:
		var inner := reach * BLOW_SHARE
		var outer := reach * SHAKE_SHARE
		for p in near(m.x, m.y, outer):
			# (a plant's own height counts: the blast has to reach its middle)
			if at.z >= (p.pos.y + p.h * 0.8) * IslandLevel.U_PER_M:
				continue
			var d := Vector2(p.pos.x - m.x, p.pos.z - m.y).length()
			if d <= inner:
				blow_up(p, at, 1.3)
			else:
				hurt(p, BLAST_HITS * (1.0 - (d - inner) / (outer - inner)), at, 1.1)
	var f: float = game.level.floor_at(at.x, at.y)
	if at.z - f < MOW_LOW:
		mow(m.x, m.y, reach * MOW_SHARE, at, 1.2)

## A ROUND INTO THE GROUND at `at` (the game's units): the tufts round
## where it went in, shredded.
func nick(at: Vector3) -> void:
	mow(at.x / IslandLevel.U_PER_M, -at.y / IslandLevel.U_PER_M, NICK, at, 0.6)

## The grass within `r` metres of (mx, mz) gone, each tuft (up to `throw`
## of them) thrown from `from` as a few pieces of its picture.
func mow(mx: float, mz: float, r: float, from: Vector3, force: float, throw := TUFTS_THROWN) -> void:
	if grass == null:
		return
	var cut: Array = grass.mow(mx, mz, r)
	if cut.is_empty() or game.chunks == null:
		return
	cut.shuffle()
	var ts: Vector2 = grass.tuft_size * IslandLevel.U_PER_M
	for e in cut.slice(0, throw):
		var tex: Texture2D = grass.sprites[e[1]] if e[1] < grass.sprites.size() else null
		if tex == null:
			continue
		var at := to_game(e[0])
		game.chunks.burst(tex, Rect2(0, 0, 1, 1), at, ts.x, ts.y, from, 4, force * 0.6, 0.0, true)

# ------------------------------------------------------------------
# THE DROP POD (DropPod, at the user's request: "rcs thrusters, retros
# and landing should destroy vegetation", and "door popping off should
# destroy things and people it hits")
# ------------------------------------------------------------------

## A JET from `at` along `dir` (the game's units, `dir` a unit vector),
## `length` units long and `width` units round at its far end (a third of
## that at the nozzle): every plant it passes through — within reach of
## the trunk or the crown, between the foot and the top — takes up to
## `hits` rounds' worth (`hurt`: shaken, then shredded), fewer further
## out; and the grass where it runs along the ground mown, until it goes
## into the ground and stops.
## How many plants it touched.
func jet(at: Vector3, dir: Vector3, length: float, width: float, hits: float) -> int:
	var um := IslandLevel.U_PER_M
	var touched := {}
	var mowed := false
	var steps := maxi(1, ceili(length / 48.0))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var q := at + dir * length * t
		var r := width * (0.3 + 0.7 * t) / um
		var mx := q.x / um
		var mz := -q.y / um
		var my := q.z / um
		if veg != null:
			for p in near(mx, mz, r + 2.5):
				if touched.has(p.key):
					continue
				var d := Vector2(p.pos.x - mx, p.pos.z - mz).length()
				if d > r + p.w * 0.35 or my < p.pos.y - r or my > p.pos.y + p.h + r:
					continue
				touched[p.key] = true
				hurt(p, hits * (1.0 - 0.6 * t), q - dir * 40.0, 1.0)
		# along the ground it mows (once a jet), into it it stops
		var f: float = game.level.floor_at(q.x, q.y)
		if f > IslandLevel.NO_FLOOR and q.z - f < 40.0:
			if not mowed:
				mow(mx, mz, r, q - dir * 40.0, 0.9, 4)
				mowed = true
			if q.z < f:
				break
	return touched.size()

## THE DOWNWASH under a pod on its retros: the skirt's nozzles round `at`
## (the game's units, their middle), the exhaust going down from a ring
## `r0` units round and spreading `spread` units out for every unit down,
## to `reach` units under them. Every plant whose top is in it takes up to
## `hits` rounds' worth, fewer the further down; and once it reaches the
## ground the grass round under it is mown, a wider ring the nearer.
## How many plants it touched.
func downwash(at: Vector3, r0: float, spread: float, reach: float, hits: float) -> int:
	var um := IslandLevel.U_PER_M
	var mx := at.x / um
	var mz := -at.y / um
	var my := at.z / um
	var reach_m := reach / um
	var n := 0
	if veg != null:
		for p in near(mx, mz, (r0 + spread * reach) / um + 2.5):
			var down := maxf(0.0, my - (p.pos.y + p.h))
			if down > reach_m:
				continue
			var d := Vector2(p.pos.x - mx, p.pos.z - mz).length()
			if d > r0 / um + spread * down + p.w * 0.35:
				continue
			hurt(p, hits * (1.0 - 0.7 * down / reach_m), at, 1.2)
			n += 1
	var f: float = game.level.floor_at(at.x, at.y)
	if f > IslandLevel.NO_FLOOR and at.z - f < reach:
		var h := at.z - f
		mow(mx, mz, (r0 + spread * h) / um * (1.0 - 0.5 * h / reach), Vector3(at.x, at.y, f + 8.0), 1.1, 6)
	return n

## WHERE THE POD COMES DOWN: every plant standing within `r` units of
## `at` (the game's units) blown to pieces, whatever its height, and the
## grass there mown — nothing is left growing through the hull.
func clear(at: Vector3, r: float) -> int:
	var um := IslandLevel.U_PER_M
	var n := 0
	if veg != null:
		for p in near(at.x / um, -at.y / um, r / um):
			blow_up(p, at, 1.4)
			n += 1
	mow(at.x / um, -at.y / um, r / um, at, 1.3)
	return n

## WHAT A FLYING THING TAKES WITH IT (the pod's door, blown off): every
## plant within `r` units of `at` (the game's units) and at its height —
## between the foot and most of the way up — blown to pieces, thrown from
## `from`. How many.
func sweep(at: Vector3, r: float, from: Vector3) -> int:
	if veg == null:
		return 0
	var um := IslandLevel.U_PER_M
	var mx := at.x / um
	var mz := -at.y / um
	var my := at.z / um
	var rm := r / um
	var n := 0
	for p in near(mx, mz, rm + 2.5):
		var d := Vector2(p.pos.x - mx, p.pos.z - mz).length()
		if d > rm + p.w * 0.35 or my < p.pos.y - rm or my > p.pos.y + p.h * 0.9 + rm:
			continue
		blow_up(p, from, 1.3)
		n += 1
	return n

## A ROUND through the plant: a scrap of it thrown off, the plant shaken,
## and enough of them shred it (`hits_for`). (The plant's picture stays
## whole, no hole left in it.)
func shoot(p: Dictionary, at: Vector3, dir: Vector3) -> void:
	var tex := _picture(p)
	if game.chunks != null and tex != null:
		# the scrap is SpriteChunks.TEXELS to half again as many texels of
		# the picture, drawn the size it is on the plant (at the user's
		# request: no piece under 16 x 16 of the picture — a scrap drawn
		# smaller than it is was confetti)
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var du := SpriteChunks.TEXELS * randf_range(1.0, 1.5) / tw
		var dv := du * tw / th
		var u := randf() * (1.0 - du) * 0.8 + (1.0 - du) * 0.1
		var v := randf() * (1.0 - dv) * 0.8 + (1.0 - dv) * 0.1
		var w: float = p.w * IslandLevel.U_PER_M * du * 1.25
		var h: float = p.h * IslandLevel.U_PER_M * dv * 1.25
		game.chunks.spawn(tex, Rect2(u, v, du, dv), at, w, h,
			Vector3(dir.x * 0.006 + randf_range(-2, 2), dir.y * 0.006 + randf_range(-2, 2), randf_range(2.0, 6.0)), 80, 0.0, true)
	hurt(p, randf_range(0.8, 1.2), at - dir.normalized() * 30.0, 0.8)

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

func tic() -> void:
	if veg == null:
		return
	if game.tics % U.TICRATE == 0:
		_keep()
