extends CanvasLayer

# THE SCREEN GOING OUT AS YOU SINK INTO THE CLOUD SEA. One full-rect ColorRect
# whose alpha tracks the camera's altitude against the deck: clear above the
# surface, solid `sea_interior_color` a few metres under.
#
# WHAT IT IS FOR, in order of how much it matters:
#
#   * IT HIDES THE UNDERSIDE OF THE WORLD. The islands are hollow sweeps that stop
#     being drawn at `IslandWorld.cliff_visible_depth`, the cloud deck is a single
#     quad with nothing on its far side, and the sky below the horizon is void. A
#     camera under the deck sees all three. Rather than build a convincing
#     underside, the deck is made opaque from the inside — which is also what it
#     looks like from the inside.
#   * IT IS THE FEEDBACK FOR FALLING OUT OF THE WORLD. Descending past the deck is
#     currently survivable and silent. This makes it read as being consumed, which
#     is the shape a death penalty would later hang off — see `veil()`.
#
# WHY A CANVAS RECT AND NOT VOLUMETRICS. The honest version is a density march
# from the camera, which is what `SHADER_cloud_volumetric.gdshader` already does for
# everything OUTSIDE the deck. Inside it there is nothing to resolve — the answer
# is "opaque" everywhere — so a march would spend twenty-two samples per pixel to
# return a constant. This is one alpha-blended quad, and it stops being drawn at
# all the moment it is clear (see `_apply`).
#
# ON TOP OF THE PALETTE PASS, deliberately. `PostFX` is layer 128 and quantises the
# frame to sixteen palette entries; this sits above it so "solid" means solid
# rather than solid-then-dithered. The colour it lands on is the deck's own
# interior tone, so the two agree anyway — the ordering only matters during the
# second or so of transition, and for the guarantee that fully-veiled is fully
# opaque with nothing showing through.
#
# THE LINE IS THE NOMINAL SURFACE, NOT THE BILLOWS. `SHADER_cloud_volumetric.gdshader`
# undulates its top surface down to `bump_amp` (75 m) below `sea_top`, so a camera
# dropping through a valley is veiled while still technically in clear air. Doing
# better means evaluating the deck's noise field on the CPU every frame to find the
# local surface, which is a lot of machinery to correct a case you are falling
# through in under a second. If it ever reads wrong, that is the fix.

## Off switch. The veil exists to HIDE the underside of the world, so anything
## whose job is to look at that underside has to be able to turn it off —
## `tests/RENDER_w2_ground.gd`'s `cliff_under` viewpoint stands 70 m down and
## rendered as a flat filled frame until this existed.
@export var enabled := true
## The CloudSea node this veil belongs to. Its `sea_altitude` and its material's
## `cloud_bottom_color` are read straight off it, so the veil engages exactly where
## the deck is and lands on exactly the tone the deck's own raymarch converges to.
##
## NOT read from the `sea_surface_y` / `sea_interior_color` global shader
## parameters, even though `SCRIPT_cloud_sea.gd` publishes both and a shader would read
## them that way. `RenderingServer.global_shader_parameter_get` is editor-only —
## outside the editor GLES3 rejects the call outright, once per invocation — so
## globals are a one-way channel into SHADERS and cannot carry a value back to a
## script. This is a direct read of the same source those globals are built from.
@export var cloud_sea_path: NodePath = NodePath("../CloudSea")
## Metres ABOVE the sea surface at which the veil starts to come in. Small: the
## deck closing over the camera should lead the fade slightly, not precede it.
@export var veil_above := 2.0
## Metres BELOW the surface at which the veil is fully opaque. The whole band is
## `veil_above + veil_below` metres of travel, so keep it short — this is meant to
## read as being swallowed, not as a slow dip to black.
@export var veil_below := 10.0
## Used when `cloud_sea_path` resolves to nothing, so this node is harmless in a
## scene with no deck in it rather than a crash.
@export var fallback_surface_y := -45.0
## Likewise.
@export var fallback_color := Color(0.089, 0.089, 0.089, 1.0)
## The SkyCycleController whose `art_tint()` recolours the veil, found the same way
## and for the same reason `cloud_sea_path` above finds the deck.
##
## THE VEIL IS THE ONE UNLIT SURFACE THE SCENE TINT CANNOT REACH BY ITSELF. Every
## other one — the vegetation, the grass, the deck, the horizon band, the smoke —
## takes `tod_art_tint` as a multiply inside its own shader. This is a ColorRect
## with a colour, not a material, so there is no shader to put the multiply in, and
## without this the veil would paint DAYLIGHT GREY over SCENE_test_zone_W2's
## blood-red night the instant the camera dropped into the deck. A whole screen of
## the wrong colour, at the one moment there is nothing else on it to argue with.
##
## Read off the node rather than out of the global, because
## `RenderingServer.global_shader_parameter_get` is editor-only — the same
## observation `cloud_sea_path` records two doc comments up, and the same fix.
## Unresolved means white, which is what every scene without a cycle wants.
@export var sky_cycle_path: NodePath = NodePath("../TimeOfDay")

var _rect: ColorRect
var _sea: Node
var _cycle: Node


func _ready() -> void:
	# Above PostFX (128), so the solid is solid. See the header.
	layer = 200

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never eat input: this is scenery, and the camera is still being flown while
	# it is on screen.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(fallback_color, 0.0)
	_rect.visible = false
	add_child(_rect)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _rect == null:
		return
	_apply(veil(cam.global_position.y) if enabled else 0.0,
			_tinted(_interior_color()))


## How veiled the screen should be at world altitude `y`: 0 in clear air above the
## deck, 1 inside it. Smoothstepped rather than linear for the same reason the
## cliff's own fade is — a linear ramp through the sixteen-level palette comes out
## as banding, and a screen-filling one would band across the whole frame.
##
## Public and pure so a death penalty can later ask "is the player consumed yet?"
## off the same curve the picture is using, instead of re-deriving the altitude
## test and drifting from it.
func veil(y: float) -> float:
	var top := _surface_y()
	return 1.0 - smoothstep(top - veil_below, top + veil_above, y)


func _apply(a: float, col: Color) -> void:
	# Clear means NOT DRAWN. A full-rect alpha-blended quad is cheap but it is not
	# free, and on V3D a screen's worth of blended fill every frame to composite
	# nothing is exactly the sort of thing that shows up as a few dropped frames on
	# the Pi and nowhere else.
	_rect.visible = a > 0.001
	if _rect.visible:
		_rect.color = Color(col.r, col.g, col.b, minf(a, 1.0))


# Resolved lazily rather than in `_ready`: sibling ready-order is an implementation
# detail of the scene file, and a veil that silently used its fallback altitude
# because it woke up first would be a very quiet bug.
func _sea_node() -> Node:
	if _sea == null or not is_instance_valid(_sea):
		_sea = get_node_or_null(cloud_sea_path)
	return _sea


func _surface_y() -> float:
	var s := _sea_node()
	return s.surface_y() if s != null and s.has_method("surface_y") else fallback_surface_y


func _interior_color() -> Color:
	var s := _sea_node()
	return s.interior_color() if s != null and s.has_method("interior_color") else fallback_color


# The deck's interior tone under the scene's current light. See `sky_cycle_path`.
#
# Resolved lazily, like `_sea_node`, and for the identical reason: sibling ready
# order is a property of the scene file, and a veil that silently ran white because
# it woke up first would be a very quiet bug.
func _tinted(col: Color) -> Color:
	if _cycle == null or not is_instance_valid(_cycle):
		_cycle = get_node_or_null(sky_cycle_path)
	if _cycle == null or not _cycle.has_method("art_tint"):
		return col
	var t: Color = _cycle.call("art_tint")
	return Color(col.r * t.r, col.g * t.g, col.b * t.b, col.a)
