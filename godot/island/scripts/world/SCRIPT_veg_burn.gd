@tool
class_name VegBurn
extends Node3D

# THE FIRE BUS. Publishes the two global shader parameters that decide how far
# through a burn every plant in the world is, and resolves the burn map that goes
# with each sprite for the two scatters that draw them.
#
# THE SAME SHAPE AS THE `tod_*` BUS NEXT TO IT IN SCENE_test_zone_W2, and for the
# same reason. Every plant in the scene is drawn by a DUPLICATE of one of four
# materials — `SCRIPT_veg_scatter.gd` and `SCRIPT_grass_scatter.gd` make one copy per sprite so
# each can carry its own albedo — so a property of the WORLD rather than of a
# sprite has nowhere else to live. Writing it onto the materials would mean
# reaching into ten duplicates every frame and would still miss any scatter that
# rebuilt itself; `SHADER_veg_billboard.gdshader` reads it as a `global uniform` instead
# and one write covers the island.
#
#   veg_burn        0..1 — how far through the fire the island is
#   veg_burn_front  xyz origin, w radius in metres; w <= 0 disables the front
#   veg_stump       0..1 — how much of what burnt has since come down
#
# WIRED AND IDLE, exactly as the TimeOfDay node beside it is. `burn` ships at 0 and
# `advance` is off, so a scene with this node in it renders the same green island
# it always did — the plants are burn-CAPABLE, not burnt. Move `burn` (or turn
# `advance` on, or give the front a radius) and the island goes up. That is the
# whole interface.
#
# TWO WAYS TO BURN IT, and they compose:
#
#   EVERYWHERE AT ONCE. Leave `front_radius` at 0 and move `burn`. The whole
#   island passes through the fire together, spread out by the shader's
#   per-instance variance so it still reads as thousands of plants catching
#   separately rather than as a wipe. This is the one to use for a burnt WORLD —
#   set `burn` to 1 and never touch it again.
#
#   A SPREADING FRONT. Give `front_radius` a value (or a `front_speed`) and the
#   fire is a disc growing from `front_origin`: burnt ground behind it, a band of
#   flame at the edge whose depth is the shader's `burn_front_depth`, untouched
#   forest ahead. `burn` still gates it, so taking the bus back to 0 puts the fire
#   out wherever it had reached.
#
# THE FRONT ORIGIN IS IN RENDER SPACE, which is why this node is in
# `origin_shiftable`: SCENE_test_zone_W2 rebases the world every 8 km
# (`scripts/SCRIPT_floating_origin.gd`) and the shader compares the front against
# `MODEL_MATRIX[3]`, a render-space position. A front left in world space would
# jump a whole island's width the first time the player flew far enough out.
#
# STATIC HELPERS AT THE BOTTOM. `map_for` and `bind_map` are what the two scatters
# call while they build their per-sprite materials. They live here rather than
# being copied into both because there is exactly one naming convention and it
# should exist in exactly one place.

## How far through the fire the island is. 0 is untouched, 1 is through and cold.
##
## The interesting range is narrower than it looks: a plant is visibly ALIGHT
## across most of 0.25..0.8 and settles into char after that.
@export_range(0.0, 1.0, 0.001) var burn := 0.0:
	set(v):
		burn = clampf(v, 0.0, 1.0)
		_publish()

## Run the burn forward on its own, at `burn_rate` per second.
@export var advance := false

## Units of `burn` per second while `advance` is on. 0.02 takes about a minute to
## take the island from green to cold, which is roughly how long a stand of firs
## takes to go in a real crown fire.
@export_range(0.0, 1.0, 0.001, "or_greater") var burn_rate := 0.02

## How far the burnt vegetation has COLLAPSED to stumps. 0 is fresh char with the
## whole silhouette still standing; 1 is a burn scar a year later — broken trunks,
## charred root crowns, and a black smear where the ferns were.
##
## A SEPARATE AXIS FROM `burn`, and deliberately so: a dead crown comes down about a
## year after the fire that killed it, not on the same clock as the flame. The two
## compose, and the shader MULTIPLIES this by each plant's own burn, so moving it on
## a green forest does nothing — a plant cannot collapse from a fire that never
## reached it.
@export_range(0.0, 1.0, 0.001) var stump := 0.0:
	set(v):
		stump = clampf(v, 0.0, 1.0)
		_publish()

## Units of `stump` per second while `advance` is on, and it should be a fraction of
## `burn_rate`: the collapse is the slow half of the story. 0 leaves the stumps to
## be set by hand.
@export_range(0.0, 1.0, 0.0001, "or_greater") var stump_rate := 0.0

@export_group("Front")

## Centre of the spreading disc, in the same space the plants are placed in.
## `front_origin_path`, if set, overrides it every frame.
@export var front_origin := Vector3.ZERO:
	set(v):
		front_origin = v
		_publish()

## Follow a node instead — a torched building, the player, wherever the fire
## started. Read every frame, so it may move.
@export var front_origin_path: NodePath

## Radius of burnt ground, in metres. 0 or less means NO front: `burn` applies to
## the whole island at once, which is the shipped behaviour.
##
## The band of actual flame sits just inside this, and its depth is the shader's
## `burn_front_depth` (120 m on the shipped materials) rather than a number here —
## it is a property of how a fire eats a canopy, not of one scene's fire.
@export_range(0.0, 4000.0, 1.0, "or_greater") var front_radius := 0.0:
	set(v):
		front_radius = maxf(v, 0.0)
		_publish()

## Metres per second the front spreads while `advance` is on. Only does anything
## once `front_radius` is above 0 — a front with no radius is not a front.
@export_range(0.0, 500.0, 0.1, "or_greater") var front_speed := 0.0

## Stop the front here. 0 means never — it keeps going until it has left the
## island, which for W2's 1,525 m hub is about 900 m from the middle.
@export_range(0.0, 8000.0, 1.0, "or_greater") var front_limit := 0.0


func _ready() -> void:
	add_to_group("origin_shiftable")
	_publish()
	set_process(true)


func _process(delta: float) -> void:
	if not front_origin_path.is_empty():
		var n := get_node_or_null(front_origin_path) as Node3D
		if n != null:
			# Straight off the node, with no rebase arithmetic: `SCRIPT_floating_origin.gd`
			# shifts every scene-root Node3D that is NOT `origin_shiftable`, so a
			# followed node is already in the space the shader compares against.
			# The correction below is for a front pinned to a literal coordinate,
			# which is the only kind nothing else moves.
			front_origin = n.global_position

	# `@tool` is here so the burn can be dialled in against the actual island in
	# the editor, not so the island quietly burns down while the scene sits open.
	if not advance or Engine.is_editor_hint():
		return
	if burn < 1.0:
		burn = burn + burn_rate * delta
	if stump_rate > 0.0 and stump < 1.0:
		stump = stump + stump_rate * delta
	if front_radius > 0.0 and front_speed > 0.0:
		var r := front_radius + front_speed * delta
		if front_limit > 0.0:
			r = minf(r, front_limit)
		front_radius = r
	# Both setters publish, but a frame where neither moved (burn pinned at 1, no
	# front) would otherwise stop publishing entirely — which is fine, the globals
	# are sticky, and is why there is no unconditional write here.


# The world jumped. The front is a RENDER-space position, so it has to jump with
# it — see the header. Same sign as the shift `SCRIPT_floating_origin.gd` applies to every
# other scene-root Node3D, which is what keeps the fire over the same GROUND. A
# front that follows a node re-reads it next frame and does not need this.
func apply_origin_shift(shift: Vector3) -> void:
	front_origin += shift


func _publish() -> void:
	RenderingServer.global_shader_parameter_set("veg_burn", burn)
	RenderingServer.global_shader_parameter_set("veg_burn_front", Vector4(
			front_origin.x, front_origin.y, front_origin.z, front_radius))
	RenderingServer.global_shader_parameter_set("veg_stump", stump)


# ------------------------------------------------------------------ burn maps

## The burn map that belongs to a sprite, or null if it has none.
##
## BY NAME, in the same directory: `SPRITE_fern_1_128.png` -> `SPRITE_fern_1_128_burn.png`. The
## alternative is a parallel `Array[Texture2D]` export on each scatter, wired in
## the scene beside the sprite list — which is one more thing to keep in the right
## ORDER, and gets it silently wrong (a fir burning like a fern) rather than
## loudly. A convention cannot be misordered.
##
## `tools/TOOL_gen_burn_maps.py` bakes these, writes their `.import` sidecars, and
## takes its own list of sprites from the same convention.
static func map_for(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var p := tex.resource_path
	if p.is_empty():
		return null
	var path := "%s/%s_burn.%s" % [p.get_base_dir(), p.get_file().get_basename(),
			p.get_extension()]
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## Bind a sprite's burn map onto the material that draws it. Returns false when
## the sprite has none.
##
## A MISSING MAP PINS `burn` TO 0 on that material, which is the whole point of
## doing this here rather than leaving the shader to cope. The shader's fallback
## for an unbound sampler is a transparent texel — order 0, no char, no loss — and
## a plant whose every texel burns at once, first, is a worse picture than a plant
## that does not burn at all. Pinning opts the sprite out until someone re-runs
## the baker, and the warning says which one.
static func bind_map(mat: ShaderMaterial, tex: Texture2D) -> bool:
	bind_ember_ramp(mat)
	var map := map_for(tex)
	if map == null:
		mat.set_shader_parameter("burn", 0.0)
		push_warning("VegBurn: no burn map for %s — it will not burn. Run "
				% (tex.resource_path if tex != null else "<null>")
				+ "tools/TOOL_gen_burn_maps.py.")
		return false
	mat.set_shader_parameter("burn_map", map)
	return true


## The palette the embers cycle through, bound on a material that does not already
## carry one. Called by `bind_map`, so every material either scatter draws with gets
## it without anything in the scene wiring it.
##
## HERE AND NOT IN EIGHT .tres FILES. The ramp is a property of the WORLD's palette,
## not of a size of plant: all eight vegetation materials would carry the identical
## line, and the failure mode of getting it wrong in one of them is a single class
## of plant burning a different colour than the rest, which reads as a bug in the
## fire rather than as a missing binding. Same argument as the burn maps above, and
## the same place to keep it.
##
## AN EXPLICIT ASSIGNMENT ON THE MATERIAL STILL WINS — the check below is what
## makes this a default rather than an override, so a scatter that wants its own
## fire palette can say so in its material and be left alone.
const EMBER_RAMP := "res://godot/island/data/palettes/TEX_ember_ramp_ps1-soft.png"


static func bind_ember_ramp(mat: ShaderMaterial) -> bool:
	if mat.get_shader_parameter("ember_ramp") != null:
		return true
	if not ResourceLoader.exists(EMBER_RAMP):
		# The shader falls back to white, which is loud on purpose — see its
		# `ember_ramp` uniform. Say why, once, rather than leaving white fire
		# to be diagnosed from a screenshot.
		push_warning("VegBurn: %s is missing, so the embers will be WHITE. "
				% EMBER_RAMP + "Run tools/TOOL_gen_burn_maps.py.")
		return false
	mat.set_shader_parameter("ember_ramp", ResourceLoader.load(EMBER_RAMP))
	return true
