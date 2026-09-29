## MEWD — the title's own level: a forest that goes by for ever
## (js/titlescene.js).
##
## FOURTEEN ROWS OF CUTOUTS AT FOURTEEN DEPTHS, at the user's request:
## seven of grass from under the eye back to the trees, and seven of
## pines behind them, each row of pines taller than the one in front,
## so the wood rises as it goes back. The depth is all of the parallax:
## the eye is a real perspective camera moving along x. FOR EVER is a
## ring per row — a cutout that falls off the left end moves a ring's
## width to the right and becomes a different plant at a different size.
##
## NO GAPS is arithmetic: every row is tall enough that the line from
## the eye over its tops lands on the next row's roots, the plants of a
## row stand closer than a third of their height, and behind the last
## pines is a dark band. Everything is GREY here; the blue is laid over
## the finished frame, over the dither (Lofi.set_tint, BLUE).
class_name TitleForest
extends Node3D

const DIR := "res://assets/forest/"
const SPEED := 0.8          # units a second: a quarter of what it was, at the user's request
const EYE_Y := 2.6
const GROUND_TILE := 4.0
const FOV := 50.0
const MAX_ASPECT := 2.6
## the logo's own green-blue — the glass in its letters, about #20584d
## — muted and dark, at the user's request: white grass comes out a
## deep slate teal, the pines darker still
const BLUE := Color(0.17, 0.36, 0.42)

const GRASS := ["meadow_grass_var_a", "meadow_grass_var_b", "new_meadow_grass_1", "new_meadow_grass_2",
	"new_meadow_grass_tall_1", "grass", "savanna_grass_short_1", "savanna_grass_short_2",
	"savanna_grass_tall_1", "savanna_grass_tall_2"]
const PINES := ["pine_fir_tree_1", "pine_fir_tree_2", "pine_fir_tree_3", "pine_fir_tree_4",
	"fir_tall_1", "fir_tall_2", "fir_medium", "pine_barrens_tree"]
const GRASS_Z := [-5.5, -8.0, -11.0, -15.0, -20.0, -26.0, -33.0]
const PINE_Z := [-40.0, -55.0, -75.0, -100.0, -130.0, -170.0, -220.0]
const PINE_H := [9.0, 12.0, 16.0, 21.0, 27.0, 34.0, 42.0]

var camera: Camera3D
var x := 0.0
var rows := []
var textures := {}
var materials := {}
var geo: ArrayMesh
var sky: MeshInstance3D
var sky_mat: ShaderMaterial
var ground: MeshInstance3D
var ground_mat: ShaderMaterial
var band: MeshInstance3D
var _s := 2037
var _time := 0.0

static func ring_for(z: float) -> float:
	return absf(z) * 2.0 * tan(deg_to_rad(FOV / 2.0)) * MAX_ASPECT * 1.25 + 8.0

## the rows, back to front
static func row_defs() -> Array:
	var out := []
	for i in range(6, -1, -1):
		out.append({"z": PINE_Z[i], "h": [PINE_H[i] * 0.85, PINE_H[i] * 1.15], "sink": 0.05,
			"tint": 0.95 - i * 0.09, "sway": 0.075 - i * 0.007, "gap": 0.26, "kinds": PINES})
	for i in range(6, -1, -1):
		out.append({"z": GRASS_Z[i], "h": [1.5 + i * 0.12, 2.3 + i * 0.16], "sink": 0.35,
			"tint": 1.25 - i * 0.05, "sway": 0.34 - i * 0.025, "gap": 0.3, "kinds": GRASS})
	for r in out:
		r.wrap = ring_for(r.z)
		r.n = ceili(r.wrap / (r.gap * (r.h[0] + r.h[1]) / 2.0))
	return out

## a small seeded generator, so the forest is the same forest each time
func rand() -> float:
	_s ^= (_s << 13) & 0xFFFFFFFF
	_s ^= _s >> 17
	_s ^= (_s << 5) & 0xFFFFFFFF
	_s &= 0xFFFFFFFF
	return float(_s) / 4294967296.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.5
	camera.far = 600.0
	camera.position = Vector3(0, EYE_Y, 0)
	add_child(camera)
	camera.make_current()
	geo = _plane(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.12, 0.12)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_build()

## a plane standing on its bottom edge, six strips tall for the wind
func _plane(strips: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in strips + 1:
		var t := float(j) / strips
		v.append(Vector3(-0.5, t, 0)); uv.append(Vector2(0, 1.0 - t))
		v.append(Vector3(0.5, t, 0)); uv.append(Vector2(1, 1.0 - t))
	for j in strips:
		var a := j * 2
		idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _tex(kind: String) -> Texture2D:
	if not textures.has(kind):
		textures[kind] = load(DIR + kind + ".png")
	return textures[kind]

func _material(kind: String, tint: float, sway := 0.0) -> ShaderMaterial:
	var key := "%s|%f|%f" % [kind, tint, sway]
	if not materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://godot/shaders/title_plant.gdshader")
		m.set_shader_parameter("map", _tex(kind))
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("sway", sway)
		materials[key] = m
	return materials[key]

## a flat picture: the sky, or the ground — which hides nothing (it
## writes no depth and is drawn first), so the grass sunk into it keeps
## its roots
func _flat(tex: Texture2D, tint: float, cut := false, behind := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if behind:
		var sh := Shader.new()
		sh.code = preload("res://godot/shaders/title_plant.gdshader").code.replace("depth_draw_opaque", "depth_draw_never")
		m.shader = sh
	else:
		m.shader = preload("res://godot/shaders/title_plant.gdshader")
	m.set_shader_parameter("map", tex)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("cutout", cut)
	return m

func _build() -> void:
	# THE SKY: the top half of BSKY1 on a plane that rides with the eye,
	# drifting at a crawl
	var sky_tex: Texture2D = load("res://assets/skies/BSKY1.png")
	sky = MeshInstance3D.new()
	var sq := QuadMesh.new()
	sky.mesh = sq
	sky_mat = _flat(sky_tex, 1.1, false, true)
	sky_mat.render_priority = -2
	sky_mat.set_shader_parameter("uv_scale", Vector2(0.5, 0.5))
	sky.material_override = sky_mat
	add_child(sky)
	# THE GROUND: GRASS5, a strip that rides with the eye and slides its picture
	ground = MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(600, 300)
	ground.mesh = gp
	ground_mat = _flat(load("res://assets/textures/GRASS5.png"), 0.55, false, true)
	ground_mat.set_shader_parameter("uv_scale", Vector2(600.0 / GROUND_TILE, 300.0 / GROUND_TILE))
	ground_mat.render_priority = -1
	ground.material_override = ground_mat
	ground.position = Vector3(0, 0, -150)
	add_child(ground)
	# NO GAPS AT THE BACK: a dark band behind the last row of trees
	band = MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(1400, 30)
	band.mesh = bq
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	bm.albedo_color = Color(0.11, 0.11, 0.11)
	band.material_override = bm
	band.position = Vector3(0, 15 - 0.5, -240)
	add_child(band)
	for def in row_defs():
		var row := {"def": def, "items": []}
		var step: float = def.wrap / def.n
		for i in def.n:
			var mi := MeshInstance3D.new()
			mi.mesh = geo
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			var it := {"mesh": mi, "x": -def.wrap / 2.0 + (i + rand()) * step, "y": 0.0, "z": 0.0}
			_dress(def, it)
			row.items.append(it)
		rows.append(row)

## Make a cutout a plant: which one, how big, a little in or out, flipped or not.
func _dress(d: Dictionary, it: Dictionary) -> void:
	var kind: String = d.kinds[int(rand() * d.kinds.size())]
	var t := _tex(kind)
	var aspect := float(t.get_width()) / t.get_height()
	var h: float = d.h[0] + rand() * (d.h[1] - d.h[0])
	var mi: MeshInstance3D = it.mesh
	mi.material_override = _material(kind, d.tint, d.sway)
	mi.scale = Vector3(h * aspect * (-1.0 if rand() < 0.5 else 1.0), h, 1)
	it.z = d.z + (rand() - 0.5) * absf(d.z) * 0.12
	it.y = -d.sink * (0.5 + rand())

## One frame: the eye moves on, and what has gone by comes round.
func _process(dt: float) -> void:
	x += SPEED * minf(dt, 0.1)
	_time += dt
	camera.position.x = x
	for m in materials.values():
		m.set_shader_parameter("wind_time", _time)
	for row in rows:
		var w: float = row.def.wrap
		var lo := x - w / 2.0
		for it in row.items:
			if it.x < lo:
				it.x += w
				_dress(row.def, it)
			it.mesh.position = Vector3(it.x, it.y, it.z)
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	var d := 400.0
	var hh := d * tan(deg_to_rad(FOV / 2.0))
	sky.position = Vector3(x, EYE_Y + hh * 0.35, -d)
	sky.scale = Vector3(hh * 2.0 * aspect * 1.05, hh * 2.0 * 0.95, 1)
	sky_mat.set_shader_parameter("uv_offset", Vector2(fmod(x * 0.0006, 1.0), 0.0))
	ground.position.x = x
	band.position.x = x
	ground_mat.set_shader_parameter("uv_offset", Vector2(fmod(x / GROUND_TILE, 1.0), 0.0))
