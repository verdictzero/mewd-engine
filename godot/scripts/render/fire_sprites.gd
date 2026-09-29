## MEWD — the fire, drawn over the grid (js/fire.js render).
##
## A fixed pool of flames parked on the hottest cells near the eye each
## frame. There is no per-cell node and nothing is created or destroyed
## while the store burns: one MultiMesh per flame set (ember, fire,
## blaze), its buffer refilled every frame as standees.gd does.
##
## ADDITIVE, because light adds (flame.gdshader).
##
## A CLUMP, NOT A FLAME: one sprite per cell puts one flame every
## thirty-two units on a grid, and a grid is exactly what you saw. Each
## flame stands a little off its cell's middle at an offset hashed off
## the cell and the slot — RANDOM but the SAME random every frame, so the
## fire does not boil; everything that moves in it moves because the
## flame art is animating.
##
## BIG IN THE MIDDLE, SMALL AT THE EDGE: `core` is the mean of a cell's
## four neighbours' heat, so a cell in the middle of a burning gondola
## gets big flames off the top of the ladder and one on the advancing
## front gets a single small one.
##
## TODO(smoke): the JS parks a second pool of 36 alpha-blended SMOK puffs
## over the most buried cells (kept on their cell between frames so they
## drift rather than teleport), lit by the room. Not drawn here yet.
## TODO(visibility): the JS skips near flames in regions the portal flood
## says the eye cannot see into (Level.isVisible); the depth test does
## that job here, at the cost of drawing them.
class_name FireSprites
extends Node3D

const POOL := 192
## HOW FAR A FIRE IS DRAWN, and as what: every cell to FLAME_NEAR, about
## half of them; fewer and bigger to FLAME_MID; one flame per clump of
## CLUMP cells on a side from there to FLAME_FAR.
const FLAME_NEAR := 700.0
const FLAME_MID := 1500.0
const FLAME_FAR := 6000.0
const CLUMP := 8
const NEAR_ODDS := 0.55
const MID_ODDS := 0.28
## Nothing is drawn within arm's reach: a flame at 20 units is a wall of
## orange with nothing behind it.
const NEAR2 := 46.0 * 46.0
## Embers only nearby — a cold glow a thousand units off is one pixel.
const EMBER_RANGE2 := 760.0 * 760.0

## The three sizes of flame, smallest first, so a clump can pick the rung
## below its own for the little ones round the edge — with the cell size,
## frames, seed, taper and sprite scale js/sprites.js bakes them with.
const SETS := [
	{"key": "EMBR", "w": 20, "h": 28, "frames": FireArt.EMBER_FRAMES, "seed": 31, "taper": 0.62, "scale": 0.92},
	{"key": "FIRE", "w": 32, "h": 48, "frames": FireArt.FIRE_FRAMES, "seed": 7, "taper": 0.55, "scale": 1.0},
	{"key": "BLAZ", "w": 48, "h": 64, "frames": FireArt.BLAZE_FRAMES, "seed": 19, "taper": 0.8, "scale": 1.65},
]
## baked strips are kept here between runs: the bake is a second of
## GDScript noise, and the art is a pure function of these numbers
const CACHE := "user://fire_art_v1_%s.png"

class Batch:
	var mm: MultiMesh
	var buf := PackedFloat32Array()
	var n := 0

var batches: Array[Batch] = []
var _clumps := {}

func _ready() -> void:
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	for set in SETS:
		var img := _strip(set)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://godot/shaders/flame.gdshader")
		mat.set_shader_parameter("strip", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("cells", float(set.frames))
		mat.render_priority = 10          # over the world, under the HUD
		var mesh := quad.duplicate() as ArrayMesh
		mesh.surface_set_material(0, mat)
		var b := Batch.new()
		b.mm = MultiMesh.new()
		b.mm.transform_format = MultiMesh.TRANSFORM_3D
		b.mm.use_custom_data = true
		b.mm.mesh = mesh
		b.mm.instance_count = POOL
		b.mm.visible_instance_count = 0
		b.buf.resize(POOL * 16)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = b.mm
		mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		batches.append(b)

func _strip(set: Dictionary) -> Image:
	var path := CACHE % set.key
	if FileAccess.file_exists(path):
		var cached := Image.load_from_file(path)
		if cached and cached.get_width() == int(set.w) * int(set.frames) and cached.get_height() == int(set.h):
			return cached
	var img := FireArt.fire_frames(set.w, set.h, set.frames, set.seed, {"taper": set.taper})
	img.save_png(path)
	return img

## A stable random per (cell, slot) — never off the clock: jitter that is
## re-rolled per frame is a fire that boils. Knuth's mix twice.
static func hash2(a: int, b: int) -> float:
	var n := ((a * 374761393) & 0xFFFFFFFF) ^ (((b + 1) * 668265263) & 0xFFFFFFFF)
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((n ^ (n >> 16)) & 0xFFFFFFFF) / 4294967296.0

## HOW MUCH SMALLER A FLAME GETS FOR BEING CLOSE: down to two fifths at
## the near cull, full size from about eight metres out — so you can
## still find the door.
static func near_taper(d2: float) -> float:
	var t := sqrt(d2) / 280.0
	return 1.0 if t > 1.0 else (0.40 if t < 0.40 else t)

## How buried in the fire a cell is, 0 at the front and 1 in the middle
## of a blaze: the mean of the four neighbours' heat, guarded at the edges.
static func core(F: FireSystem, i: int) -> float:
	var n := F.heat.size()
	var c := F.cols
	var e := F.heat[i + 1] if i + 1 < n else 0
	var w := F.heat[i - 1] if i > 0 else 0
	var s := F.heat[i + c] if i + c < n else 0
	var t := F.heat[i - c] if i >= c else 0
	return (e + w + s + t) / 1020.0

## Park the pool on the fire. `cam` is the eye in Godot space; `t` the
## tic clock with its fraction (the same clock the art animates on);
## `effects` the quality share of the pool (js game.quality.effects).
func draw(F: FireSystem, cam: Vector3, t: float, effects := 1.0) -> void:
	for b in batches:
		b.n = 0
	if F == null or F.off or F.active.is_empty():
		_flush()
		return
	var cam_x := cam.x
	var cam_y := -cam.z
	var sectors: Array = F.game.level.sectors
	var cand := []
	var far2 := FLAME_FAR * 0.96 * FLAME_FAR * 0.96
	var nearf2 := FLAME_NEAR * FLAME_NEAR
	var mid2 := FLAME_MID * FLAME_MID
	_clumps.clear()
	var shift := roundi(log(float(CLUMP)) / log(2.0))
	for k in F.active.size():
		var i := F.active[k]
		var h := F.heat[i]
		if h < 6:
			continue
		var c := i % F.plane
		var cx := c % F.cols
		var cy := c / F.cols
		var x := F.world_x(cx)
		var y := F.world_y(cy)
		var d2 := U.dist2(x, y, cam_x, cam_y)
		if d2 > far2 or d2 < NEAR2:
			continue
		if d2 <= mid2:
			if h < FireSystem.SPREAD_AT and d2 > EMBER_RANGE2:
				continue
			var near := d2 <= nearf2
			if hash2(i, 4242) > (NEAR_ODDS if near else MID_ODDS):
				continue
			# nearest first, but weighted by heat so a big fire further off
			# still gets drawn ahead of an ember at your feet
			cand.append({"i": i, "x": x, "y": y, "h": h, "d2": d2, "core": core(F, i),
				"boost": 1.35 if near else 1.9, "big": false, "key": d2 / (0.35 + h / 255.0)})
		else:
			if h < FireSystem.SPREAD_AT:
				continue
			var key := ((i / F.plane) * 8192 + (cy >> shift)) * 8192 + (cx >> shift)
			var g: Dictionary = _clumps.get(key, {})
			if g.is_empty():
				g = {"i": i, "sx": 0.0, "sy": 0.0, "w": 0.0, "n": 0, "h": 0}
				_clumps[key] = g
			var wt := h / 255.0
			g.sx += x * wt
			g.sy += y * wt
			g.w += wt
			g.n += 1
			if h > g.h:
				g.h = h
	for g in _clumps.values():
		var x: float = g.sx / g.w
		var y: float = g.sy / g.w
		var d2 := U.dist2(x, y, cam_x, cam_y)
		# first in the queue whatever the distance: each one stands for a
		# great deal of fire
		cand.append({"i": g.i, "x": x, "y": y, "h": g.h, "d2": d2, "core": minf(1.0, g.n / 24.0),
			"boost": 2.4 + minf(4.6, g.w * 0.14), "big": true, "key": -1e12 + d2})
	cand.sort_custom(func(a, b): return a.key < b.key)

	# HOW MUCH OF THE POOL TO SPEND: sorted nearest and hottest first, so
	# spending less drops the far, cold end
	var pool := maxi(16, roundi(POOL * effects))
	var s := 0
	for cd in cand:
		if s >= pool:
			break
		var ci: int = cd.i
		var ch: int = cd.h
		var big: bool = cd.big
		var cc: float = cd.core
		var cd2: float = cd.d2
		# which flame: an ember, a fire, or a proper blaze
		var rung := 2 if big else (2 if ch > 200 else (1 if ch > 90 else 0))
		# HOW MANY: one, and two where the fire has closed over a cell
		# within a few metres of you
		var n := 2 if (not big and rung > 0 and cc > 0.5 and cd2 < 300.0 * 300.0) else 1
		var si := F.sector_of[ci]
		var floor_z: float = sectors[si].floor if si >= 0 else 0.0
		for j in n:
			if s >= POOL:
				break
			var r_set := maxi(0, rung - (1 if j > 0 else 0))
			var set: Dictionary = SETS[r_set]
			var letters: int = set.frames
			# offset by the cell AND the slot, so neighbouring flames are out
			# of step — in phase, a wall of fire pulses like a heart
			var frame := (floori(t * 0.5) + ci * 3 + j * 7) % letters
			var a := hash2(ci, j) * TAU
			var r := 0.0 if big else (hash2(ci, 77) * CELL_F * 0.4 if j == 0 else (0.30 + hash2(ci, j + 64) * 0.75) * CELL_F * 0.9)
			var grow := 1.0 if j == 0 else 0.52 + hash2(ci, j + 128) * 0.30
			var sc: float = float(set.scale) * (0.7 + (ch / 255.0) * 0.75) * (0.95 + cc * 0.45) * grow * float(cd.boost) * near_taper(cd2)
			_put(batches[r_set], float(cd.x) + cos(a) * r, float(cd.y) + sin(a) * r, floor_z, frame, float(set.w) * sc, float(set.h) * sc)
			s += 1
	_flush()

const CELL_F := float(FireSystem.CELL)

func _put(b: Batch, x: float, y: float, z: float, frame: int, w: float, h: float) -> void:
	var i := b.n * 16
	b.buf[i] = 1.0; b.buf[i + 1] = 0.0; b.buf[i + 2] = 0.0; b.buf[i + 3] = x
	b.buf[i + 4] = 0.0; b.buf[i + 5] = 1.0; b.buf[i + 6] = 0.0; b.buf[i + 7] = z
	b.buf[i + 8] = 0.0; b.buf[i + 9] = 0.0; b.buf[i + 10] = 1.0; b.buf[i + 11] = -y
	b.buf[i + 12] = float(frame); b.buf[i + 13] = w; b.buf[i + 14] = h; b.buf[i + 15] = 0.0
	b.n += 1

func _flush() -> void:
	for b in batches:
		if b.n > 0:
			b.mm.buffer = b.buf
		b.mm.visible_instance_count = b.n
