class_name CinemaPost
extends MeshInstance3D

## THE CINEMA's light (at the user's request: "make it look fucking cinematic
## as hell — colorgrading, sun flare, god rays"): god rays, the sun's lens
## flare, bloom and the air lit from behind, as one full-screen pass over
## whatever camera draws this world (SHADER_cinema_post.gdshader). The grade
## is the picture filter's, set by an island's Islands "grade".
##
## A 2 x 2 quad the shader puts over the whole screen, with a box round it
## that no camera can leave, so it is never culled. Put one in a scene; its
## material's numbers are the look.

@export var post_material: ShaderMaterial


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)
	mesh = q
	if post_material == null:
		post_material = ShaderMaterial.new()
		post_material.shader = preload("res://godot/island/shaders/SHADER_cinema_post.gdshader")
	material_override = post_material
	custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (last of everything see-through, the water included)
	post_material.render_priority = 127
