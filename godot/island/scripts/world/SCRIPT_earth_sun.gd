class_name EarthSun
extends Node

## THE SUN ON A REAL PLACE, and what stands in its way (at the user's
## request: "make it look fucking cinematic as hell"): the shadows its
## mountains throw across it, baked off the region's own heights for where
## the sun is (SHADER_earth_sun_bake.gdshader, on the GPU, a 4 m grid over
## the square) and baked again whenever it has moved a quarter of a degree;
## and the clouds' shadows, which EnviroSky's clouds throw as they cross
## (SHADERINC_earth_sun.gdshaderinc reads both). The ground, the water and
## the plants take the sun off them, so at evening one side of the valley is
## in the gold and the other in the blue, and the shafts of the god rays
## (CinemaPost) come over real ridges.
##
## Its picture and where it lies are global shader parameters
## (tod_sun_shadow, tod_sun_shadow_rect), switched on by tod_sun_shadow_on
## while it is in the tree and off when it leaves, so every other island is
## as it was.

@export var island_world_path: NodePath = ^"../IslandWorld"
@export var sky_path: NodePath = ^"../EnviroSky"
## How far round the sun moves, degrees, before the shadows are baked again.
@export var rebake_degrees := 0.25
## The penumbra's spread (a tangent; the sun's own half-width is 0.0046).
@export var softness := 0.014

var _vp: SubViewport = null
var _mat: ShaderMaterial = null
var _sky: Node = null
var _last := Vector3.ZERO
## how many times it has baked, for the tests
var bakes := 0


func _ready() -> void:
	var iw := get_node_or_null(island_world_path)
	if iw == null:
		return
	var field := iw.get("field") as EarthField
	if field == null:
		return
	if not field.get("_ready"):
		field.prepare()
	var r := field.data()
	if not r.ok or r.hn < 2 or r.cn < 2:
		return
	var isl: IslandField.Island = field.island_in_cell(field.hub_cell())
	var himg := Image.create_from_data(r.hn, r.hn, false, Image.FORMAT_RG8, r.hraw)
	var water := r.water
	if water.size() != r.wn * r.wn:
		water = PackedFloat32Array()
		water.resize(maxi(r.wn, 1) * maxi(r.wn, 1))
		water.fill(NAN)
	var wimg := Image.create_from_data(maxi(r.wn, 1), maxi(r.wn, 1), false, Image.FORMAT_RF,
			water.to_byte_array())
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://godot/island/shaders/SHADER_earth_sun_bake.gdshader")
	_mat.set_shader_parameter("heights", ImageTexture.create_from_image(himg))
	_mat.set_shader_parameter("water", ImageTexture.create_from_image(wimg))
	_mat.set_shader_parameter("hn", float(r.hn))
	_mat.set_shader_parameter("hres", r.hres)
	_mat.set_shader_parameter("hoff", r.hoff)
	_mat.set_shader_parameter("hscale", r.hscale)
	_mat.set_shader_parameter("datum", r.datum)
	_mat.set_shader_parameter("wn", float(r.wn))
	_mat.set_shader_parameter("out_n", float(r.cn))
	_mat.set_shader_parameter("out_res", r.cres)
	_mat.set_shader_parameter("soft", softness)
	_vp = SubViewport.new()
	_vp.name = "SunShadow"
	_vp.size = Vector2i(r.cn, r.cn)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var rect := ColorRect.new()
	rect.size = Vector2(r.cn, r.cn)
	rect.material = _mat
	_vp.add_child(rect)
	add_child(_vp)
	_sky = get_node_or_null(sky_path)
	var origin := isl.center - Vector2(r.half, r.half)
	U.gset("tod_sun_shadow", _vp.get_texture())
	U.gset("tod_sun_shadow_rect", Vector4(origin.x, origin.y, r.cres, float(r.cn)))
	U.gset("tod_sun_shadow_on", 1.0)
	_rebake()


func _exit_tree() -> void:
	if _vp != null:
		U.gset("tod_sun_shadow_on", 0.0)


func _process(_dt: float) -> void:
	if _vp == null:
		return
	var l := _light()
	if l.angle_to(_last) > deg_to_rad(rebake_degrees):
		_rebake()


func _light() -> Vector3:
	if _sky != null and _sky.has_method("light_direction"):
		return _sky.call("light_direction")
	return U.G.get("tod_sun_dir", Vector3(0.0, 0.8, 0.6))


func _rebake() -> void:
	_last = _light()
	_mat.set_shader_parameter("light_dir", _last)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1
