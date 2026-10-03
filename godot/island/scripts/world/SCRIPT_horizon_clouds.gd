@tool
extends Node3D

# The horizon cloud band: a camera-centred open cylinder running
# `shaders/SHADER_horizon_clouds.gdshader`. Drop it at the root of any 3D scene, hand it
# `materials/MAT_horizon_clouds.tres`, and a two-layer parallax cloud backdrop
# appears over the sky and behind the world.
#
# THIS NODE OWNS NO PART OF THE LOOK. The shader samples the VIEW DIRECTION, not
# the mesh, so the cylinder's radius and height change nothing about the picture.
# All the mesh has to do is
#
#   * cover the screen wherever the band has coverage, and
#   * sit far enough out that real geometry depth-tests in front of it,
#
# and everything below is in service of exactly those two jobs.
#
# WHY A SHELL AND NOT A FULL-SCREEN QUAD. The band has to be OCCLUDABLE. A quad
# on a CanvasLayer, or a spatial quad with `depth_test_disabled`, paints over the
# terrain -- an island on the skyline would be covered by clouds that are
# supposed to be behind it. Ordinary transparent geometry at 9 km gets the
# occlusion for free from the depth buffer, and costs one draw call.
#
# WHY IT CHASES THE CAMERA IN ALL THREE AXES, unlike `SCRIPT_cloud_planes.gd` which
# refuses to follow in Y. There, altitude is the point: a deck at ONE height is
# what makes the sea a floor. Here the opposite is the point -- the band is
# supposed to be at the horizon from any altitude, so the shell must stay centred
# on the eye or its rim would swing into view the moment you climbed. The shader
# would still draw the band in the right place; there would just be no geometry
# left under part of it.
#
# ONE FRAME OF LAG IS FINE. If the camera moves after this node's `_process`, the
# shell is off-centre by (speed / fps) metres against a 9 km radius -- 50 m at the
# fly camera's boosted 3000 m/s, which slides the rim by 0.006 in tan(elevation).
# The cover margins below are two orders larger than that.

## MAT_horizon_clouds.tres.
@export var material: ShaderMaterial:
	set(v):
		material = v
		_refresh()

@export_group("Shell")
## Radius of the cylinder in metres. Has to be CLOSER than the camera's `far`, or
## the band is clipped away entirely, and FURTHER than anything that should be
## able to stand in front of it (terrain view distance, the cloud decks' rim).
## With `auto_fit` on this is recomputed from the live camera and the value here
## is only the fallback used before one is found.
@export_range(500.0, 100000.0, 10.0, "or_greater") var shell_radius := 9000.0:
	set(v):
		shell_radius = v
		_rebuild_mesh()
## Track the active camera's `far` instead of trusting `shell_radius`. Cheap
## insurance: every scene sets its own far plane, and a shell outside it vanishes
## with no warning and no obvious cause.
@export var auto_fit := true
## Fraction of `far` to sit at. Slack matters -- the far plane clips at exactly
## `far`, and the shell's rim is further from the camera than its waist.
@export_range(0.2, 0.95, 0.01) var far_fraction := 0.75

@export_group("Cover")
## How far above the horizon the shell reaches, in tan(elevation). Must clear the
## TALLER layer's `*_base + *_height` or its cloud tops are cut off by the rim.
@export_range(0.05, 4.0, 0.01) var cover_up := 0.55:
	set(v):
		cover_up = v
		_rebuild_mesh()
## ...and how far below. Must clear the shader's `fade_end`, i.e. reach past the
## point where the band has finished fading out.
@export_range(0.05, 4.0, 0.01) var cover_down := 0.25:
	set(v):
		cover_down = v
		_rebuild_mesh()
## Sides of the cylinder. The wrap is seamless and the shader is per-fragment, so
## this only has to be fine enough that the wall stays outside the near geometry;
## it is not a quality knob.
@export_range(8, 256, 1) var radial_segments := 64:
	set(v):
		radial_segments = v
		_rebuild_mesh()

@export_group("Behaviour")
## Keep the shell centred on the camera. Turn off to inspect it as fixed geometry.
@export var follow_camera := true

var _mi: MeshInstance3D = null
var _mesh: CylinderMesh = null
# Mirrors SCRIPT_island_world.gd and SCRIPT_cloud_planes.gd: logical = render + _origin_offset.
var _origin_offset := Vector3.ZERO
var _fitted_radius := 0.0


func _ready() -> void:
	# Joins for the same two reasons SCRIPT_cloud_planes.gd does: to opt OUT of
	# SCRIPT_floating_origin.gd's blanket shift of every scene-root Node3D (which would
	# fight the camera-following below), and to opt IN to `apply_origin_shift`,
	# which is what keeps the parallax anchored across a rebase.
	add_to_group("origin_shiftable")
	# Run after the camera's own `_process` so the shell is centred on where the
	# eye ENDED this frame rather than where it started.
	process_priority = 100
	_refresh()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if auto_fit:
		# Only rebuild on a real change: the mesh is a shared resource and
		# rewriting it every frame keeps it permanently dirty in the editor.
		var want := cam.far * far_fraction
		if absf(want - _fitted_radius) > 1.0:
			_fitted_radius = want
			_rebuild_mesh()
	if follow_camera:
		global_position = cam.global_position


## The rendered world has been rebased. The shell itself needs no moving -- it is
## re-derived from the camera next frame -- but the shader's parallax reads an
## ABSOLUTE camera position, so it has to be told where the logical origin went or
## the entire horizon slews sideways in the frame the origin snaps.
func apply_origin_shift(shift: Vector3) -> void:
	_origin_offset -= shift
	if material != null:
		material.set_shader_parameter("world_offset",
				Vector2(_origin_offset.x, _origin_offset.z))


# ------------------------------------------------------------------ internals

func _radius() -> float:
	return _fitted_radius if (auto_fit and _fitted_radius > 0.0) else shell_radius


func _rebuild_mesh() -> void:
	if _mesh == null:
		_mesh = CylinderMesh.new()
		# Open tube. The caps would be a horizontal disc directly overhead and
		# another underfoot, both fully transparent after the shader's early-out
		# but both still rasterised over the whole screen when you look up.
		_mesh.cap_top = false
		_mesh.cap_bottom = false
		_mesh.rings = 0
	var r := _radius()
	_mesh.top_radius = r
	_mesh.bottom_radius = r
	_mesh.radial_segments = radial_segments
	# The band is lopsided -- far more of it above the horizon than below -- and a
	# CylinderMesh is symmetric about its own centre, so the extra height is
	# pushed back out by offsetting the instance. Sizing it symmetrically to the
	# taller side instead would rasterise the difference every frame for nothing.
	_mesh.height = r * (cover_up + cover_down)
	if _mi != null:
		_mi.position.y = r * (cover_up - cover_down) * 0.5
		_mi.custom_aabb = AABB(
				Vector3(-r, -_mesh.height * 0.5, -r),
				Vector3(r * 2.0, _mesh.height, r * 2.0))
	update_configuration_warnings()


func _refresh() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_rebuild_mesh()
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "Shell"
		# A 9 km cylinder in the directional shadow pass would blow the fit of
		# every cascade and take the world's terrain shadows with it. The shader
		# already declares `shadows_disabled` and is `blend_mix`, which the shadow
		# pass skips; this is the belt to those braces, exactly as SCRIPT_cloud_sea.gd
		# and SCRIPT_veg_scatter.gd do it.
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(_mi)
	_mi.mesh = _mesh
	_mi.material_override = material
	_mi.visible = material != null
	_rebuild_mesh()
	if material != null:
		material.set_shader_parameter("world_offset",
				Vector2(_origin_offset.x, _origin_offset.z))


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if material == null:
		w.append("material is unset — the horizon clouds will not draw.")
		return w

	# The invariants that couple this node's geometry to the shader's band, and
	# the one that couples the two layers to the fade. Each fails as a picture,
	# not as an error: a clipped rim, or a vertical smear where the clamp ran off
	# the bottom of the artwork.
	var top := maxf(
			_param("back_base", -0.09) + _param("back_height", 0.45),
			_param("front_base", -0.1) + _param("front_height", 0.26))
	if cover_up < top:
		w.append("cover_up (%.2f) is under the tallest band top (%.2f): the shell's rim cuts the cloud tops off."
				% [cover_up, top])
	var fade_end := _param("fade_end", -0.065)
	if cover_down < -fade_end:
		w.append("cover_down (%.2f) does not reach fade_end (%.2f): the band is cut off before it has faded out."
				% [cover_down, fade_end])
	for layer: String in ["back", "front"]:
		var base := _param(layer + "_base", -0.1)
		if base > fade_end:
			w.append("%s_base (%.3f) is above fade_end (%.3f): below the band the vertical clamp smears the artwork's solid bottom row downward, and it is still visible when it does."
					% [layer, base, fade_end])
	if _param("fade_start", 0.045) <= fade_end:
		w.append("fade_start must be above fade_end.")
	# THE FOLD. The band's parallax is a small-angle model whose azimuth map stops
	# being monotonic once the camera's LOGICAL offset reaches a layer's own
	# `*_distance` -- 4.5 km of travel on the front layer, 16 km on the back.
	# `parallax_limit` is what holds that ratio below 1; at 1 or above the band draws
	# two mirrored copies of itself meeting at a moving seam, with the artwork
	# stretched without bound along one bearing. Fails as a picture, and only once
	# you have flown away from the origin, which is why it is worth a warning here as
	# well as an assertion in tests/TEST_horizon_clouds.gd.
	var limit := _param("parallax_limit", 0.5)
	if limit >= 1.0:
		w.append("parallax_limit (%.2f) is at or above 1.0: past a layer's own *_distance the azimuth map folds, and the band tears into two mirrored copies meeting at a seam."
				% limit)
	elif limit > 0.8:
		w.append("parallax_limit (%.2f) stretches the artwork up to %.1fx along one bearing (1 / (1 - limit)); 0.5 is the shipped budget."
				% [limit, 1.0 / maxf(1.0 - limit, 1e-3)])
	if not auto_fit and is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null and shell_radius >= cam.far:
			w.append("shell_radius (%.0f) is at or past the camera's far plane (%.0f): the band is clipped away entirely."
					% [shell_radius, cam.far])
	return w


func _param(name: String, fallback: float) -> float:
	var v = material.get_shader_parameter(name)
	return fallback if v == null else float(v)
