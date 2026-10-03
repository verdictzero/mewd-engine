## MEWD — THE HOUSES DRAWN (at the user's request: CANDY LAND's gingerbread
## house round the town squares). Every house the level placed
## (IslandLevel.place_houses) as one instance of the model in a MultiMesh:
## one draw per surface for the lot. It hangs under the island, so it is in
## the island's metres and axes: the game's (x, y, z) is the island's
## (x, z, -y) over 32, and the model's door is on its +Z. Its materials are
## the model's own, redrawn by SHADER_house so the thermal sight sees a
## house as cold (only people are hot).
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
	multimesh = mm
	scene.free()

const SHADER := preload("res://godot/island/shaders/SHADER_house.gdshader")

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
		m.surface_set_material(i, sm)
	return m
