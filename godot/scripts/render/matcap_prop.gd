## MEWD — a PBR model's materials under MATCAPS (SHADER_matcap_prop, at the
## user's request: "give the maze sections and the drop pod a matcap so
## their PBRness looks nice"): each surface's colour, normal map and
## metal-roughness map kept, its light the clay and the pearl. MazeView's
## walls and posts, DropPod's hull and door.
class_name MatcapProp
extends RefCounted

const SHADER := preload("res://godot/island/shaders/SHADER_matcap_prop.gdshader")
const MATTE := preload("res://assets/matcaps/clay.png")
const SHEEN := preload("res://assets/matcaps/pearl.png")

## the matcap material for a surface that had `std` (none: plain grey)
static func material(std: Material, extra := {}) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	sm.set_shader_parameter("matte", MATTE)
	sm.set_shader_parameter("sheen", SHEEN)
	var bm := std as BaseMaterial3D
	if bm != null:
		sm.set_shader_parameter("color", bm.albedo_color)
		if bm.albedo_texture != null:
			sm.set_shader_parameter("tex", bm.albedo_texture)
			sm.set_shader_parameter("textured", true)
		if bm.normal_enabled and bm.normal_texture != null:
			sm.set_shader_parameter("normal_map", bm.normal_texture)
			sm.set_shader_parameter("has_normal", true)
		sm.set_shader_parameter("metallic", bm.metallic)
		sm.set_shader_parameter("roughness", bm.roughness)
		# (glTF puts metal and roughness in one picture, the importer hands
		# it to both slots)
		var mr: Texture2D = bm.metallic_texture if bm.metallic_texture != null else bm.roughness_texture
		if mr != null:
			sm.set_shader_parameter("mr_map", mr)
			sm.set_shader_parameter("has_mr", true)
	for k in extra:
		sm.set_shader_parameter(k, extra[k])
	return sm

## a copy of `src` with every surface under the matcaps
static func mesh(src: Mesh, extra := {}) -> Mesh:
	var m: Mesh = src.duplicate()
	for i in m.get_surface_count():
		m.surface_set_material(i, material(m.surface_get_material(i), extra))
	return m
