## MEWD — the wood, drawn (js/forest.js build / render / _placeFlames).
##
## Instanced billboards: every plant is one row of a MultiMesh buffer
## (plant.gdshader turns it to face the eye, bends it in the wind and
## burns it by its burn map), and it reads the Forest and nothing else.
##
## ONE MATERIAL FOR THE WHOLE WOOD. The JS is one draw a kind a chunk;
## here every kind the map uses is a LAYER of two Texture2DArrays (the
## albedo and the burn map, each tile upscaled nearest to 256 square —
## the art is 64 to 256 on a side and the shader only asks 0..1), so a
## chunk of ground is one draw whatever grows on it. Only the kinds a
## map plants are loaded (loadPlantSets in js/main.js).
##
## ONE MESH PER CHUNK PER RANGE, and that is how a much thicker wood
## costs less than a thin one: the plants are cut into CHUNK-square
## pieces of ground, each with a real AABB so the frustum culls the ones
## behind you, and each range class (understory, bushes, trees — FADE)
## its own MultiMeshInstance3D whose visibility range drops it past its
## band, so the fern carpet is submitted for the ground you stand on and
## nowhere else. (The JS's three-size LOD of chunks and its portal-flood
## test are not ported: Godot's own culling does the first job well
## enough at these counts, and there is no flood yet.)
##
## AND ACTUAL FIRE: a pool of flame quads re-parked every frame on the
## hottest burning cells near the eye — a burning fir carrying its flame
## at the height the front has climbed to — and far fires gathered into
## a few very big flames. See _place_flames.
class_name ForestView
extends Node3D

const CHUNK := 2048.0
const TILE := 256
## how bright the wood is where it stands in no region
const WOOD_LIGHT := 0.56
## How far a flame steps out of the thing it is burning, toward the eye:
## a fraction of the flame's own width, and a fraction of the range.
const FLAME_NUDGE := 0.30
const FLAME_NUDGE_RANGE := 0.012
const FLAME_MAX := 200
const FLAME_CACHE := "user://fire_art_wood_v1.png"
const FLAME_FRAMES := 20

## WHERE EACH CLASS STOPS BEING WORTH DRAWING, as [start fading, gone]:
## about sixty times its own height, the band wide so the change is a
## thinning rather than a line on the ground. Trees are the horizon.
static func fade(k: Dictionary) -> Vector2:
	if k.get("cover", false):
		return Vector2(2900, 4800)
	if float(k.h) <= 120.0:
		return Vector2(4600, 7200)
	return Vector2(13000, 16000)

class Chunk:
	var mm: MultiMesh
	var mi: MultiMeshInstance3D
	var n := 0

var forest: Forest
var mat: ShaderMaterial
var chunks: Array[Chunk] = []
## every plant (trees first, then covers) -> its chunk and slot, and its
## custom data (layer, burn, seed, flip) to rewrite the burn into
var _chunk_of := PackedInt32Array()
var _slot_of := PackedInt32Array()
var _custom: Array[Color] = []
var layers := {}                     # kind index -> texture layer
var flames: Particles
var ground: MeshInstance3D
var _mask_img: Image
var _mask_tex: ImageTexture
var _ground_mat: ShaderMaterial

func _init(f: Forest) -> void:
	forest = f
	name = "Forest"
	if f.cols == 0:
		return
	_build_plants()
	if not f.rects.is_empty():
		_build_ground()
	_build_flames()

# ------------------------------------------------------------------
# Building
# ------------------------------------------------------------------
func _build_plants() -> void:
	var F := forest
	var n_t := F.trees.n
	var total := n_t + F.covers.n
	if total == 0:
		return
	# the art, only for what grows here
	var albedo: Array[Image] = []
	var burns: Array[Image] = []
	for p in total:
		var ki: int = F.trees.kind[p] if p < n_t else F.covers.kind[p - n_t]
		if layers.has(ki):
			continue
		var kname: String = Forest.KINDS[ki].name
		var a := _tile("res://assets/forest/%s.png" % kname)
		var b := _tile("res://assets/forest/%s_burn.png" % kname)
		if a == null or b == null:
			push_warning("plant art: no %s" % kname)
			layers[ki] = -1
			continue
		layers[ki] = albedo.size()
		albedo.append(a)
		burns.append(b)
	if albedo.is_empty():
		return
	var ta := Texture2DArray.new()
	ta.create_from_images(albedo)
	var tb := Texture2DArray.new()
	tb.create_from_images(burns)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/plant.gdshader")
	mat.set_shader_parameter("albedo", ta)
	mat.set_shader_parameter("burn_map", tb)
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	quad.surface_set_material(0, mat)

	# group by chunk of ground and range class
	var groups := {}
	_chunk_of.resize(total)
	_chunk_of.fill(-1)
	_slot_of.resize(total)
	_custom.resize(total)
	for p in total:
		var S: Forest.PlantSet = F.trees if p < n_t else F.covers
		var i := p if p < n_t else p - n_t
		var ki := S.kind[i]
		if layers.get(ki, -1) < 0:
			continue
		var band := fade(Forest.KINDS[ki])
		var key := Vector3i(floori((S.x[i] - F.origin_x) / CHUNK), floori((S.y[i] - F.origin_y) / CHUNK), int(band.x))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(p)
	for key: Vector3i in groups:
		var list: Array = groups[key]
		var ch := Chunk.new()
		ch.n = list.size()
		ch.mm = MultiMesh.new()
		ch.mm.transform_format = MultiMesh.TRANSFORM_3D
		ch.mm.use_colors = true
		ch.mm.use_custom_data = true
		ch.mm.mesh = quad
		ch.mm.instance_count = ch.n
		var buf := PackedFloat32Array()
		buf.resize(ch.n * 20)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var band := Vector2()
		for s in ch.n:
			var p: int = list[s]
			var S: Forest.PlantSet = F.trees if p < n_t else F.covers
			var i := p if p < n_t else p - n_t
			var k: Dictionary = Forest.KINDS[S.kind[i]]
			band = fade(k)
			var h: float = float(k.h) * S.scale[i]
			var w: float = h * float(k.aspect)
			var feet := U.v3(S.x[i], S.y[i], S.z[i])
			var sec := F.level.sector_at(S.x[i], S.y[i])
			var light := sec.light if sec else WOOD_LIGHT
			var c := Color(float(layers[S.kind[i]]), F.prog[S.cell[i]] / 255.0, S.seed[i], float(S.flip[i]))
			_custom[p] = c
			_chunk_of[p] = chunks.size()
			_slot_of[p] = s
			var o := s * 20
			buf[o] = w; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = feet.x
			buf[o + 4] = 0.0; buf[o + 5] = h; buf[o + 6] = 0.0; buf[o + 7] = feet.y
			buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = 1.0; buf[o + 11] = feet.z
			buf[o + 12] = light; buf[o + 13] = 1.0; buf[o + 14] = band.x; buf[o + 15] = band.y
			buf[o + 16] = c.r; buf[o + 17] = c.g; buf[o + 18] = c.b; buf[o + 19] = c.a
			# the box is the plant's ground and its height, bent by the wind
			lo = lo.min(feet - Vector3(w, 0, w))
			hi = hi.max(feet + Vector3(w, h, w))
		ch.mm.buffer = buf
		ch.mi = MultiMeshInstance3D.new()
		ch.mi.multimesh = ch.mm
		ch.mi.custom_aabb = AABB(lo, hi - lo).grow(24.0)
		ch.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# past the class's range, not submitted at all (the JS hides the
		# chunk at its kind's far plus a chunk)
		ch.mi.visibility_range_end = band.y + CHUNK
		add_child(ch.mi)
		chunks.append(ch)

## One sprite tile as a layer: RGBA8, TILE square (nearest, so a pixel
## stays a pixel), with mipmaps (the JS's NearestMipmapNearest).
static func _tile(path: String) -> Image:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != TILE or img.get_height() != TILE:
		img.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	img.generate_mipmaps()
	return img

func _build_ground() -> void:
	var F := forest
	var v := PackedVector3Array()
	for r: Rect2 in F.rects:
		var a := U.v3(r.position.x, r.position.y, 0)
		var b := U.v3(r.end.x, r.position.y, 0)
		var c := U.v3(r.end.x, r.end.y, 0)
		var d := U.v3(r.position.x, r.end.y, 0)
		v.append_array([a, b, c, a, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mask_img = Image.create(F.cols, F.rows, false, Image.FORMAT_L8)
	_mask_img.set_data(F.cols, F.rows, false, Image.FORMAT_L8, F.prog)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://godot/shaders/forest_ground.gdshader")
	_ground_mat.set_shader_parameter("ground_map", load("res://assets/forest/ground.png"))
	_ground_mat.set_shader_parameter("burnt_map", load("res://assets/forest/ground_burnt.png"))
	_ground_mat.set_shader_parameter("mask", _mask_tex)
	_ground_mat.set_shader_parameter("mask_rect", Vector4(F.origin_x, F.origin_y, 1.0 / (F.cols * Forest.CELL), 1.0 / (F.rows * Forest.CELL)))
	_ground_mat.set_shader_parameter("light", WOOD_LIGHT)
	mesh.surface_set_material(0, _ground_mat)
	ground = MeshInstance3D.new()
	ground.name = "ForestGround"
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

func _build_flames() -> void:
	var strip: Image = null
	if FileAccess.file_exists(FLAME_CACHE):
		strip = Image.load_from_file(FLAME_CACHE)
		if strip and strip.get_width() != 64 * FLAME_FRAMES:
			strip = null
	if strip == null:
		# the body flame's art (js/main.js flameAtlas): twenty frames that loop
		strip = FireArt.fire_frames(64, 64, FLAME_FRAMES, 11, {"taper": 0.7})
		strip.save_png(FLAME_CACHE)
	flames = Particles.new({"max": FLAME_MAX, "blend": "add", "frames": FLAME_FRAMES, "near_shrink": 60.0,
		"fullbright": true, "map": ImageTexture.create_from_image(strip), "order": 13})
	flames.name = "WoodFlames"
	add_child(flames)

# ------------------------------------------------------------------
# Every frame
# ------------------------------------------------------------------
## cam is the eye in Godot space; time in seconds (the ember clock).
func draw(cam: Vector3, time: float) -> void:
	if forest.cols == 0:
		return
	if mat:
		mat.set_shader_parameter("u_time", time)
		# the wind: which way on the ground (map y is Godot -z), and how
		# hard — a still night barely moves the leaves, a storm bends the
		# firs; see THE WIND IN THE LEAVES in plant.gdshader
		var wx := forest.wind.x
		var wy := forest.wind.y
		var wl := sqrt(wx * wx + wy * wy)
		if wl > 1e-6:
			mat.set_shader_parameter("u_wind", Vector3(wx / wl, -wy / wl, clampf(wl / 0.4, 0.15, 2.2)))
		else:
			mat.set_shader_parameter("u_wind", Vector3(1, 0, 0.15))
	if _ground_mat:
		_ground_mat.set_shader_parameter("u_time", time)
	_flush()
	if flames:
		_place_flames(cam.x, -cam.z, cam.y)
		flames.draw()

## Push every changed cell into the instance data and the ground mask.
func _flush() -> void:
	var dirty := forest.take_dirty()
	if dirty.is_empty():
		return
	var F := forest
	var n_t := F.trees.n
	for i in dirty:
		var v := F.prog[i] / 255.0
		if _mask_img:
			_mask_img.set_pixel(i % F.cols, i / F.cols, Color(v, v, v))
		var t := F.cell_tree[i]
		if t >= 0:
			_paint(t, v)
		var c0 := F.cover_start[i]
		if c0 >= 0:
			for c in range(c0, c0 + F.cover_count[i]):
				_paint(n_t + c, v)
	if _mask_img:
		_mask_tex.update(_mask_img)

func _paint(p: int, v: float) -> void:
	var ci := _chunk_of[p]
	if ci < 0:
		return
	var c := _custom[p]
	c.g = v
	_custom[p] = c
	chunks[ci].mm.set_instance_custom_data(_slot_of[p], c)

## A pool of flame quads re-parked on the hottest burning cells near the
## eye (cam in map space).
func _place_flames(cam_x: float, cam_y: float, cam_z: float) -> void:
	var P := flames
	for i in P.max:
		if P.alive[i]:
			P.kill(i)
	var F := forest
	if F.active.is_empty():
		return
	var cand := []
	const R2 := 1700.0 * 1700.0
	# AND THE FAR FIRE, as a handful of very big flames. Past R2, out to
	# the air's reach, the burning cells are gathered into clumps of eight
	# cells on a side and each clump is ONE flame at the middle of its
	# fire, sized by how much of it is alight — the store's fire's rule,
	# and the reason a wood burning across the valley reads as a wood
	# burning rather than as a glow with nothing in it.
	const FAR := 6000.0 * 0.96
	var clumps := {}
	# a sample of a big fire, every cell of a small one
	var step := maxi(1, F.active.size() >> 9)
	for k in range(0, F.active.size(), step):
		var i := F.active[k]
		var t := F.prog[i] / 255.0
		if t < 0.05 or t > 0.93:
			continue
		var x := F.world_x(i % F.cols)
		var y := F.world_y(i / F.cols)
		var d2 := U.dist2(x, y, cam_x, cam_y)
		if d2 > FAR * FAR:
			continue
		var q := (t - 0.45) / 0.35
		var heat := exp(-q * q)
		if d2 > R2:
			var key := ((i / F.cols) >> 3) * 65536 + ((i % F.cols) >> 3)
			if not clumps.has(key):
				clumps[key] = {"i": i, "sx": 0.0, "sy": 0.0, "w": 0.0, "n": 0}
			var g: Dictionary = clumps[key]
			g.sx += x * heat
			g.sy += y * heat
			g.w += heat
			g.n += 1
			continue
		cand.append({"i": i, "x": x, "y": y, "t": t, "heat": heat, "big": 0, "key": d2 / (0.3 + heat)})
	for g in clumps.values():
		if g.w < 0.05:
			continue
		var x: float = g.sx / g.w
		var y: float = g.sy / g.w
		# first in the queue: there are few, and each is a great deal of fire
		cand.append({"i": g.i, "x": x, "y": y, "t": 0.45, "heat": minf(1.0, g.w / 3.0), "big": g.n * step,
			"key": -1e12 + U.dist2(x, y, cam_x, cam_y)})
	cand.sort_custom(func(a, b): return a.key < b.key)
	var n := mini(P.max, cand.size())
	for s in n:
		var c: Dictionary = cand[s]
		var ti: int = -1 if c.big else F.cell_tree[c.i]
		var x: float = c.x
		var y: float = c.y
		var heat: float = c.heat
		var base := 0.0
		var w: float
		if c.big:
			# a clump's flame is the size of the fire it stands for: a few
			# cells is a bonfire, a hillside is a wall of it
			w = (420.0 + minf(760.0, c.big * 16.0)) * (0.55 + heat * 0.45)
		elif ti >= 0:
			var k: Dictionary = Forest.KINDS[F.trees.kind[ti]]
			var th: float = float(k.h) * F.trees.scale[ti]
			x = F.trees.x[ti]
			y = F.trees.y[ti]
			w = maxf(44.0, th * (0.40 if float(k.aspect) < 1.0 else 0.85)) * (0.6 + heat * 0.6)
			# The fire climbs the trunk as the tree goes — and STOPS AT THE
			# CROWN, so the flame straddles the crown instead of riding
			# above the tree like a paper lantern on a pole.
			base = minf(th * clampf(c.t * 1.1, 0.02, 0.86), th * 1.10 - w * (1.0 - FireArt.FLAME_FOOT))
			base += F.trees.z[ti]
		else:
			w = 30.0 + heat * 26.0
		# the quad is centred; the art's round foot wants to sit on `base`
		var z := base + w * (0.5 - FireArt.FLAME_FOOT)
		# TOWARD THE EYE, or the fire is inside the tree: flame and tree
		# are parallel quads at the same depth, which the depth test
		# cannot separate. So the flame is stepped along the line to the
		# eye and shrunk by the same fraction — the same pixels at the
		# same size, and only the depth it writes changes. How far: a
		# share of its own size plus a share of the range; never more
		# than halfway.
		var ex := cam_x - x
		var ey := cam_y - y
		var ez := cam_z - z
		var range := maxf(1.0, sqrt(ex * ex + ey * ey + ez * ez))
		var pull := minf(0.5, (w * FLAME_NUDGE + range * FLAME_NUDGE_RANGE) / range)
		x += ex * pull
		y += ey * pull
		z += ez * pull
		P.spawn({"x": x, "y": y, "z": z, "life": 2.0, "size": w * (1.0 - pull),
			"c0": Color(1, 1, 1, 0.5 + heat * 0.5),
			"frame": float(((F.tics >> 1) + int(c.i) * 7) % FLAME_FRAMES)})
