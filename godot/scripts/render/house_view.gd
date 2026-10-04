## MEWD — THE HOUSES DRAWN (at the user's request: CANDY LAND's gingerbread
## house round the town squares). Every house the level placed
## (IslandLevel.place_houses) as one instance of the model in a MultiMesh:
## one draw per surface for the lot. It hangs under the island, so it is in
## the island's metres and axes: the game's (x, y, z) is the island's
## (x, z, -y) over 32, and the model's door is on its +Z. Its materials are
## the model's own, redrawn by SHADER_house: lit by the island's own
## lighting model as the ground and the cliffs are, and cold to the thermal
## sight (only people are hot).
class_name HouseView
extends MultiMeshInstance3D

func _init(level: IslandLevel, model: String) -> void:
	name = "Houses"
	var scene: Node = (load(model) as PackedScene).instantiate()
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	# (the model's own node scale goes into every house)
	var own: Transform3D = mi.transform
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _cold_mesh(mi.mesh)
	mm.instance_count = level.houses.size()
	var k := IslandLevel.U_PER_M
	for i in level.houses.size():
		var h: Dictionary = level.houses[i]
		# the door (+Z) turned to face the game's `angle`: (cos a, sin a)
		# in the game is (cos a, 0, -sin a) in the island
		var yaw := atan2(cos(h.angle), -sin(h.angle))
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(h.scale))
		mm.set_instance_transform(i, Transform3D(b, Vector3(h.x / k, h.z / k, -h.y / k)) * own)
		mm.set_instance_custom_data(i, colourway(h))
	multimesh = mm
	scene.free()

## HOW MANY COLOURWAYS (at the user's request: "hue shift house variants,
## many"): the colour wheel cut into this many turns, and every house one
## of them, with a little saturation and brightness of its own on top, so
## no two neighbours need match. The first is the painting as it is.
const COLOURWAYS := 16

## A house's colourway, off where it stands (the same house the same colour
## every time the island is built): (turn, saturation, brightness, 0) for
## SHADER_house's INSTANCE_CUSTOM.
static func colourway(h: Dictionary) -> Color:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(roundi(float(h.x)), roundi(float(h.y))))
	var k := r.randi() % COLOURWAYS
	return Color(float(k) / COLOURWAYS, r.randf_range(0.85, 1.3) if k > 0 else 1.0,
		r.randf_range(0.9, 1.08) if k > 0 else 1.0, 0.0)

const SHADER := preload("res://godot/island/shaders/SHADER_house.gdshader")
const ENV_BALL := preload("res://godot/island/textures/TEX_env_ball_w2.png")
const ENV_BALL_NIGHT := preload("res://godot/island/textures/TEX_env_ball_w2_night.png")

## The model's mesh with each of its materials as SHADER_house: the same
## sheet or colour, cold in the thermal sight.
static func _cold_mesh(src: Mesh) -> Mesh:
	var m: Mesh = src.duplicate()
	for i in m.get_surface_count():
		var std := m.surface_get_material(i) as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		if std != null:
			sm.set_shader_parameter("color", std.albedo_color)
			if std.albedo_texture != null:
				sm.set_shader_parameter("tex", std.albedo_texture)
				sm.set_shader_parameter("textured", true)
		# the island's environment ball, as the cliff's (MAT_candy_cliff)
		sm.set_shader_parameter("env_ball_enabled", true)
		sm.set_shader_parameter("env_ball", ENV_BALL)
		sm.set_shader_parameter("env_ball_night", ENV_BALL_NIGHT)
		m.surface_set_material(i, sm)
	return m
