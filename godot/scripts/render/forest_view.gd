## MEWD — the wood, drawn (js/forest.js build / render / _placeFlames).
##
## Instanced billboards: every plant is one row of a MultiMesh buffer
## (plant.gdshader turns it to face the eye and bends it in the wind),
## and it reads the Forest and nothing else.
##
## ONE MATERIAL FOR THE WHOLE WOOD. The JS is one draw a kind a chunk;
## here every kind the map uses is a LAYER of one Texture2DArray (each
## tile upscaled nearest to 256 square — the art is 64 to 256 on a side
## and the shader only asks 0..1), so a chunk of ground is one draw
## whatever grows on it. Only the kinds a
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
## (The wood no longer burns: the fire that spread is gone, at the
## user's request, and with it the flames and the burn maps.)
class_name ForestView
extends Node3D

const CHUNK := 2048.0
const TILE := 256
## how bright the wood is where it stands in no region
const WOOD_LIGHT := 0.56

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
var layers := {}                     # kind index -> texture layer
var ground: MeshInstance3D
var _ground_mat: ShaderMaterial

func _init(f: Forest) -> void:
	forest = f
	name = "Forest"
	if f.cols == 0:
		return
	_build_plants()
	if not f.rects.is_empty():
		_build_ground()

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
	for p in total:
		var ki: int = F.trees.kind[p] if p < n_t else F.covers.kind[p - n_t]
		if layers.has(ki):
			continue
		var kname: String = Forest.KINDS[ki].name
		var a := _tile("res://assets/forest/%s.png" % kname, true)
		if a == null:
			push_warning("plant art: no %s" % kname)
			layers[ki] = -1
			continue
		layers[ki] = albedo.size()
		albedo.append(a)
	if albedo.is_empty():
		return
	var ta := Texture2DArray.new()
	ta.create_from_images(albedo)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/plant.gdshader")
	mat.set_shader_parameter("albedo", ta)
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
			var c := Color(float(layers[S.kind[i]]), 0.0, S.seed[i], float(S.flip[i]))
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
## The albedo is decoded to linear, as the web build's SRGBColorSpace
## fetch is (TexBank.decoded).
static func _tile(path: String, colour := false) -> Image:
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
	if colour:
		img.srgb_to_linear()
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
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://godot/shaders/forest_ground.gdshader")
	_ground_mat.set_shader_parameter("ground_map", TexBank.decoded(load("res://assets/forest/ground.png")))
	_ground_mat.set_shader_parameter("light", WOOD_LIGHT)
	mesh.surface_set_material(0, _ground_mat)
	ground = MeshInstance3D.new()
	ground.name = "ForestGround"
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

# ------------------------------------------------------------------
# Every frame
# ------------------------------------------------------------------
## cam is the eye in Godot space; time in seconds (the wind's clock).
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
