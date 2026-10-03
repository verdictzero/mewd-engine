@tool
class_name SkyCycleController
extends Node3D

# Single source of truth for the day/night cycle. Owns the time-of-day phase,
# pushes it into the sky_panorama_cycle shader, and interpolates lighting
# (sun color/energy/rotation + ambient color/energy) across DAY -> TRANSITION
# -> NIGHT -> TRANSITION -> DAY to match the panoramas.
#
# Wiring: assign sky_material, directional_light, world_environment in the
# inspector. The shader's own advance_with_time is forced off so this script
# stays the authoritative clock.


# =============================================================================
#  THE BROADCAST — one crossing, and everything rides it
# =============================================================================
#
# The flip is not only a sky. It is meant to be the moment the world goes wrong,
# and the sky is just the loudest thing in the frame when it does: an audio bus
# has to duck and swell with it, a HUD has to glitch, the golf rules change, and
# `scripts/world/SCRIPT_nightmare_sky_director.gd` has a four-beat piece of choreography
# to run against it. EVERY ONE OF THOSE COULD START ITS OWN THREE-SECOND TIMER on
# the frame the switch is thrown, and every one of them would then be a separate
# clock that agrees with this one only until something interrupts the flip half
# way — which `set_nightmare()` explicitly supports, and which is the first thing
# anybody does the first time they can toggle it.
#
# SO THE CROSSING IS PUBLISHED RATHER THAN RE-DERIVED. Connect to these and you
# are on the same number the sky is on, including when it turns round in the
# middle.
#
# `nightmare_stage` is the one to ride. See `nightmare_stage()` for why it is not
# simply `_flip`.
#
# THEY FIRE IN A CLOCK SCENE TOO, and that is deliberate rather than overlooked.
# The crossing is defined off the PHASE, so it is a real number in any scene — in
# SCENE_test_zone_A and A2 it simply tracks the approach of an ordinary night, and
# the beats mark thresholds on that. Nothing there connects to them, so they are
# inert. But the names are W2's, so a listener added to a clock scene will hear
# `Stage.FLASH` from a sunset that has no flash in it; connect in a scene running
# `use_nightmare_switch`, or check it first.

## The switch was thrown. `to_nightmare` is the direction it is now heading.
## Fires on the frame of the change, not when the crossing completes — this is
## the cue, not the arrival.
signal nightmare_started(to_nightmare: bool)

## How far across, 0 normal and 1 nightmare, emitted ONLY on frames where it
## actually moved. Idle at either end costs nothing; a three-second flip at 60 fps
## costs about 180 emissions, which is the price of not having a second timer.
signal nightmare_stage_changed(stage: float)

## A named beat was passed. `stage` is the `Stage` it entered, `to_nightmare` the
## direction of travel — so a listener can tell the eye opening from the eye
## closing, which are the same threshold crossed two different ways.
signal nightmare_beat(stage: Stage, to_nightmare: bool)

## The crossing settled at one end. `in_nightmare` is which end.
signal nightmare_finished(in_nightmare: bool)

## The beats, as thresholds on `nightmare_stage()`. They are named for what the
## sky is doing at each, because that is what a listener is synchronising to — a
## sting lands on FLASH, not on "0.52".
enum Stage {
	NORMAL,    ## Settled. The vortex turns, the dome is grey.
	COLLAPSE,  ## The vortex is winding up and shrinking toward a point.
	FLASH,     ## The point is gone and the world is about to be white-red.
	REVEAL,    ## The eye dome is fading in and the apex flare is lighting.
	NIGHTMARE, ## Settled at the other end.
}

## Where each `Stage` begins on the 0..1 crossing. Read by `_beat_for()` and by
## `scripts/world/SCRIPT_nightmare_sky_director.gd`, which times its curves against the
## same numbers so the signal and the picture cannot disagree.
const STAGE_STARTS := {
	Stage.COLLAPSE: 0.02,
	Stage.FLASH: 0.50,
	Stage.REVEAL: 0.58,
	Stage.NIGHTMARE: 0.995,
}


@export_group("Targets")
@export var sky_material: ShaderMaterial
@export var directional_light: DirectionalLight3D
## A sun with no light in it: any Node3D whose -Z is the direction the sun shines,
## used INSTEAD OF `directional_light` for `tod_sun_dir` when one is assigned.
##
## FOR A SCENE THAT HAS NO LIGHT TO READ. SCENE_test_zone_W2 is entirely unshaded
## — `terrain_splat_w2` and `cliff_wall` compute their own sun through
## `SHADERINC_island_light.gdshaderinc`, and everything else was never lit — so its
## DirectionalLight3D reached no pixel and its shadow pass was switched off in
## 5fbff86. What it still did was hold the sun's ORIENTATION, which made it a
## light node kept for its transform: `_apply` wrote a colour and an energy into
## it and then read the same two values straight back out to publish them. This
## export removes the round trip. Point it at a plain Node3D and the scene can
## drop the light entirely without losing its sun.
##
## `drive_sun_transform` does not apply to it — a pivot is authored by hand and
## the cycle only ever reads it. Assign one or the other, not both; if both are
## set this wins for the direction and `directional_light` is still driven, which
## is what a scene mid-migration wants.
@export var sun_pivot: Node3D
@export var world_environment: WorldEnvironment
## Whether the cycle is allowed to ROTATE the sun, or only to recolour it.
##
## OFF IN SCENE_test_zone_W2, and that is not a stylistic choice. That scene's
## DirectionalLight3D transform is the outcome of `docs/DOC_w2_shadow_light_diagnosis.md`
## — the light shipped aimed 36.7 degrees UP into the sky for a long time, three
## separate pieces of hand arithmetic agreed it pointed down because they read
## Godot's `basis.z` as a matrix ROW rather than a column, and it took rendering the
## scene to settle it. Handing that transform back to a set of euler exports typed
## into an inspector is how it gets lost again.
##
## With this off the committed transform stays authoritative and the cycle READS it
## for `tod_sun_dir` instead of writing it, so the bus still carries a correct sun
## direction and only the COLOUR half of the cycle moves. For a "fake" day/night —
## which is what this is — a sun that recolours without traversing is most of the
## effect anyway.
@export var drive_sun_transform := true

@export_group("Preset")
## A whole sky, saved — see `scripts/SCRIPT_sky_cycle_preset.gd`.
##
## WHEN THIS IS SET IT REPLACES EVERY BLENDED EXPORT BELOW: the phase boundaries,
## the three lighting blocks, the two tints and the three dome colours all come off
## the resource instead of off this node. The node keeps what is SCENE-specific and
## therefore cannot travel — `sky_haze_base` and its siblings, which are this
## scene's own authored haze, and the wiring and pacing in the two groups above.
##
## It is one binding rather than a second code path. `_apply` does
##
##     var src: Variant = preset if preset != null else self
##
## and reads every blended field off `src`, so a preset is a DROP-IN STAND-IN for
## this node's own exports and there is exactly one blend for both to go through.
## The field names therefore have to match, and `tests/TEST_w2_cycle.gd` asserts
## that the two sets agree rather than waiting for a runtime error on the frame
## somebody first assigns one.
##
## Clear it and the exports below are live again, unchanged — they are never
## written to, only read past.
@export var preset: SkyCyclePreset

@export_group("Cycle")
@export var advance_with_time := true
@export_range(1.0, 86400.0, 1.0, "or_greater") var day_length_seconds := 600.0
@export_range(0.0, 1.0) var day_phase := 0.0
@export_range(0.0, 1.0) var manual_time_of_day := 0.5
@export var smooth_transition := true


# =============================================================================
#  THE SWITCH — a state, not a clock
# =============================================================================
#
# SCENE_test_zone_W2's "night" is NOT a time of day and running it off a clock was
# the wrong model. It is the world going WRONG: normalcy, and then the ontological
# nightmare, and back. There is no dusk to sit in, nothing is meant to drift, and
# nobody should be able to catch it half way round by standing still for five
# minutes. It flips, in about three seconds, and it flips because something in the
# game made it flip — a golf quota missed, an obelisk unappeased. See `docs/DOC_notes_jogolf_mechanic.txt`.
#
# SO `nightmare` IS A BOOL AND `nightmare_seconds` IS A DURATION, and everything
# else about the cycle is unchanged: this drives exactly the same `t` the clock
# drives, so the blend, the tints, the sky writes and the tests all stay one code
# path. The flip is a lerp of `t` between two ANCHOR PHASES, which means it passes
# through the transition band on its way — and at three seconds across the whole
# span, W2's 0.12-wide sunset band is about 0.9 s of ember. That is not a leftover
# from the clock model, it is the best part of the effect: the sky warms for half a
# breath before it goes wrong, and warms again on the way back.
#
# `advance_with_time` LOSES TO THIS when both are on, and the two are meant to be
# mutually exclusive: one is a world with a sun in it and the other is a world with
# a switch. Scenes A and A2 keep the clock; W2 takes the switch.

@export_group("Nightmare Switch")
## Take the flip instead of the clock. Off by default, so every existing scene
## keeps the clock it was written against.
@export var use_nightmare_switch := false
## The state. Set it from gameplay — `set_nightmare()` is the same thing with a
## name — and the world takes `nightmare_seconds` to get there.
@export var nightmare := false:
	set(v):
		var changed := nightmare != v
		nightmare = v
		# In the editor there is no `_process` to run the blend out, so snap: the
		# inspector checkbox should show you the state it names.
		if Engine.is_editor_hint():
			_flip = 1.0 if v else 0.0
		# The CUE, and it is emitted here rather than from `_process` because this
		# is the only place that knows a decision was made — by the frame after, a
		# flip that was thrown and a flip already running look identical. Guarded on
		# the tree because @export setters also run while the scene is being built
		# from disk, before any listener could have connected.
		elif changed and is_inside_tree():
			nightmare_started.emit(v)
## How long the whole crossing takes, in seconds, in either direction. Three is the
## authored value for W2 and is deliberately at the edge of too fast — long enough
## to read as a transition rather than a cut, short enough that it is something
## happening TO you rather than weather.
@export_range(0.05, 30.0, 0.05, "or_greater") var nightmare_seconds := 3.0
## The two ends of the flip, as phases on the same 0..1 clock everything else uses.
## Defaults sit mid-day and mid-night; they exist as exports because the bands are
## authored per scene and the anchors have to land INSIDE them, not on their edges,
## or the flip starts or ends mid-blend.
@export_range(0.0, 1.0) var normal_phase := 0.45
@export_range(0.0, 1.0) var nightmare_phase := 0.85
## Let the `nightmare_flip` action (N) throw the switch by hand. See
## `_unhandled_input`, which is where the reasoning is.
@export var debug_flip_key := true

@export_group("Phase Boundaries")
@export_range(0.0, 1.0) var day_start := 0.25
@export_range(0.0, 1.0) var day_end := 0.70
@export_range(0.0, 1.0) var night_start := 0.80
@export_range(0.0, 1.0) var night_end := 0.95

@export_group("Day Lighting")
@export var day_sun_color: Color = Color(1.0, 0.97, 0.85)
@export_range(0.0, 16.0) var day_sun_energy := 1.0
@export var day_sun_rotation_degrees := Vector3(-60.0, -30.0, 0.0)
@export_range(0.0, 1.0) var day_shadow_opacity := 1.0
@export var day_ambient_color: Color = Color(0.55, 0.65, 0.78)
## The DOWN half of the unlit island's hemisphere — light bounced back up off the
## cloud sea, as distinct from `day_ambient_color` which is the dome overhead.
## Together they become `tod_sky_color` / `tod_ground_color`; see `_apply`.
@export var day_bounce_color: Color = Color(0.30, 0.28, 0.25)
@export_range(0.0, 4.0) var day_ambient_energy := 1.0
@export_range(0.0, 1.0) var day_sky_contribution := 1.0
@export_range(0.0, 4.0) var day_sky_brightness := 1.0

@export_group("Transition Lighting")
@export var trans_sun_color: Color = Color(1.0, 0.55, 0.25)
@export_range(0.0, 16.0) var trans_sun_energy := 0.7
@export var trans_sun_rotation_degrees := Vector3(-5.0, 30.0, 0.0)
@export_range(0.0, 1.0) var trans_shadow_opacity := 0.7
@export var trans_ambient_color: Color = Color(0.45, 0.32, 0.40)
@export var trans_bounce_color: Color = Color(0.34, 0.20, 0.16)
@export_range(0.0, 4.0) var trans_ambient_energy := 0.8
@export_range(0.0, 1.0) var trans_sky_contribution := 0.6
@export_range(0.0, 4.0) var trans_sky_brightness := 1.0

@export_group("Night Lighting")
@export var night_sun_color: Color = Color(0.45, 0.55, 0.85)
@export_range(0.0, 16.0) var night_sun_energy := 0.05
@export var night_sun_rotation_degrees := Vector3(60.0, 150.0, 0.0)
@export_range(0.0, 1.0) var night_shadow_opacity := 0.0
@export var night_ambient_color: Color = Color(0.08, 0.10, 0.18)
@export var night_bounce_color: Color = Color(0.05, 0.06, 0.10)
@export_range(0.0, 4.0) var night_ambient_energy := 0.4
@export_range(0.0, 1.0) var night_sky_contribution := 0.2
@export_range(0.0, 4.0) var night_sky_brightness := 0.8


# =============================================================================
#  THE HAZE FAMILY, AND THE SKY IT IS PINNED TO
# =============================================================================
#
# Everything above this line moves the LIGHT. Nothing above this line moves the
# HAZE — the flat colour that distance, altitude and the cloud deck all converge
# on — and in a scene whose horizon is most of the frame that is the half you
# actually see. SCENE_test_zone_W2 pins fourteen materials plus the Environment
# plus the sky's own `bottom_color` to ONE number (an exact neutral 0.30), on the
# argument written up at length in `MAT_sky_w2_void.tres`: fogged distance and
# empty low sky have to be the same pixel or the palette LUT finds two entries
# for them and draws a line across the world. Recolouring the sun while that
# number sat still is what made this cycle unusable in W2, and it is what the
# scene's own TimeOfDay comment meant by "the island would recolour against a sky
# that did not".
#
# SO THE HAZE IS ON THE BUS NOW, and it is a MULTIPLIER rather than a colour.
#
# `tod_haze_tint` is published as a global shader parameter and every fog,
# haze and veil colour in the scene is multiplied by it where it is used. The
# materials keep their own pinned values, which is what makes this safe: the
# tint's project.godot default is WHITE, this controller's day/transition/night
# defaults are all white, and white times anything is anything. A scene that does
# not opt in — every scene but W2 today — renders the pixels it rendered before,
# and there is no per-material enable flag to forget to set.
#
# An ABSOLUTE `tod_haze_color` was the other build and it is worse for exactly
# that reason. W2 hazes to 0.30 and SCENE_test_zone_W hazes to 0.089; an absolute
# bus value has to be one of them, so every shader would need a
# `use_bus_haze` bool and every material in both scenes would need it set
# correctly. A multiplier needs neither and cannot be half-applied.
#
# AND THE CONTRACT IS NOW ENFORCED BY CONSTRUCTION, which it never was. The sky's
# `bottom_color` is written below as `sky_haze_base * haze_tint` and every fog in
# the scene is `its own pinned 0.30 * the same haze_tint` — the same product, so
# they cannot drift apart at any phase of the cycle. Fourteen files that used to
# have to be edited together now share one number and one multiplier.

@export_group("Haze")
## Multiplier on every fog/haze/veil colour in the scene, published as the global
## `tod_haze_tint`. White is a no-op and is the default at all three phases.
@export var day_haze_tint: Color = Color(1.0, 1.0, 1.0)
@export var trans_haze_tint: Color = Color(1.0, 1.0, 1.0)
@export var night_haze_tint: Color = Color(1.0, 1.0, 1.0)

## Multiplier on the albedo of everything the lighting model never reaches,
## published as the global `tod_art_tint`. White is a no-op and is the default.
##
## THIS IS THE OTHER HALF OF THE SCENE. `SHADERINC_island_light.gdshaderinc` recolours the
## terrain and the cliff off `tod_sun_color` / `tod_sky_color` / `tod_ground_color`
## the moment those move — but the vegetation, the grass, the volumetric cloud sea,
## the horizon cloud band and the smoke were never lit by anything and have no term
## for a cycle to reach. Under a night that recoloured only the lit surfaces, W2's
## firs stayed the same green they are at noon while the ground under them went
## red, which reads as a rendering fault rather than as weather.
##
## It multiplies ALBEDO ONLY, never emission: fire, embers and molten rock are
## their own light source and are supposed to survive the tint that the things they
## are lighting do not.
@export var day_art_tint: Color = Color(1.0, 1.0, 1.0)
@export var trans_art_tint: Color = Color(1.0, 1.0, 1.0)
@export var night_art_tint: Color = Color(1.0, 1.0, 1.0)

## The Environment's own `fog_light_color` before the haze tint. Left at black,
## which disables the write — a scene whose Environment fog is not part of the
## haze family (or which has no fog) should not have this controller touching it.
@export var fog_light_base: Color = Color(0.0, 0.0, 0.0)

@export_group("Void Sky")
## Whether to drive `shaders/SHADER_sky_void_gradient.gdshader`'s colours on
## `sky_material`. OFF by default, because the other consumer of `sky_material`
## is the rotating panorama, which has none of these uniforms.
##
## THE SKY IS THE ONE THING THE CYCLE COULD NEVER MOVE. W2 draws a fixed two-tone
## gradient and is silhouetted against it along its whole coastline, so a cycle
## that recoloured the island and not the dome behind it was worse than no cycle.
## The five writes in `_apply` are what closes that, and they are all DERIVED —
## from the haze tint, from the blended sun colour, from the art tint — rather
## than being a sixth set of colours to keep in step by hand.
@export var drive_void_sky := false
## The authored neutral haze — the sky's `bottom_color`, and the value every fog in
## the scene is pinned to. Written out as `sky_haze_base * haze_tint`, which is why
## the horizon cannot come apart at any phase. See the block comment above.
@export var sky_haze_base: Color = Color(0.30, 0.30, 0.30)
## The sky's `horizon_glow` before the haze tint. It is light pooling along the
## edge of the overcast, so it belongs to the haze family and moves with it.
@export var sky_glow_base: Color = Color(0.85, 0.85, 0.85)
## The sky's `sun_glow_color` before the sun's own tint, which is taken as the
## blended sun colour DIVIDED BY the day one — so it is exactly white at day and
## this value ships through untouched. Same normalisation, and the same reason, as
## `tod_water_tint`: the authored level survives and only the hue moves.
@export var sky_sun_glow_base: Color = Color(1.0, 0.99, 0.95)
## The sky's `vortex_color` before the ART tint. The swirl over the zenith is
## unlit greyscale artwork like the clouds are, so it takes the same multiplier
## they do rather than the haze one.
@export var sky_vortex_base: Color = Color(1.0, 1.0, 1.0)
## The sky's `top_color` — the dome overhead — per phase. ABSOLUTE rather than a
## tint, because this is the one colour in the family that has to be able to leave
## it: W2's night takes the dome to near-black while the haze at the horizon stays
## a lit blood red, and no single multiplier on 0.666 produces both.
@export var day_sky_top: Color = Color(0.666, 0.666, 0.666)
@export var trans_sky_top: Color = Color(0.666, 0.666, 0.666)
@export var night_sky_top: Color = Color(0.666, 0.666, 0.666)


# The last values published to `tod_haze_tint` / `tod_art_tint`, kept because a
# SCRIPT cannot read them back. `RenderingServer.global_shader_parameter_get` is
# editor-only — outside the editor the GLES3 backend refuses it on every call — so
# the globals are a one-way channel into shaders and are no use for handing a
# number to another node. `SCRIPT_cloud_sea_veil.gd` makes the same observation about
# `sea_surface_color` and solves it the same way: read the source directly.
var _haze_tint := Color(1.0, 1.0, 1.0)
var _art_tint := Color(1.0, 1.0, 1.0)


## The current scene tint for unlit art — the script-side read of `tod_art_tint`.
##
## FOR THE ONE CONSUMER THAT IS NOT A SHADER. `SCRIPT_cloud_sea_veil.gd` fills the screen
## with the cloud deck's own interior tone once the camera drops under it, and it
## does that with a `ColorRect`'s colour rather than with a material — so the
## multiply every other unlit surface gets for free cannot reach it. Without this
## the veil would paint DAYLIGHT GREY over a blood-red night the moment you flew
## into the deck, which is a whole screen of the wrong colour at the one moment
## nothing else is on it to argue with.
func art_tint() -> Color:
	return _art_tint


## Likewise for the haze, currently unused by any script and here so the pair is
## not a puzzle when the second non-shader consumer turns up.
func haze_tint() -> Color:
	return _haze_tint


## Raw position of the SWITCH's own fader: 0 normal, 1 nightmare, linear in time.
## This is the input to the crossing rather than the crossing itself — it is zero
## in a scene running the clock, and zero in every harness in tests/, both of which
## drive the phase directly. Prefer `nightmare_stage()`.
func nightmare_blend() -> float:
	return _flip


## HOW WRONG THE WORLD IS, 0 to 1, however it got that way. This is the number to
## ride, and the reason it is not `_flip` is that `_flip` only exists under the
## switch: `advance_with_time`, a hand-set `manual_time_of_day`, and every capture
## harness in tests/ all move the world through the same states without touching
## it. Deriving the crossing from the PHASE instead means one definition covers all
## four, and a strip photographed by sweeping `manual_time_of_day` shows the same
## choreography the switch produces at the matching instant — which is what makes
## the strip evidence about the flip rather than about the harness.
##
## It is the phase's position between the two anchors, so it is 0 at
## `normal_phase` and 1 at `nightmare_phase` by construction, and the ease the
## switch applies to `_flip` arrives here already folded in.
func nightmare_stage() -> float:
	return _stage


## Start the world going wrong, or coming back. The blend runs from wherever it
## currently is, so a flip interrupted half way costs half the time to undo — which
## is the behaviour you want the first time anything toggles this twice quickly.
func set_nightmare(on: bool) -> void:
	nightmare = on


## Throw the switch from the keyboard — the `nightmare_flip` action, N by default.
##
## THE FLIP HAS NO GAMEPLAY TRIGGER YET. It is meant to fire because the game made
## it fire (a quota missed, an obelisk unappeased — see the header), and none of
## that exists, so until it does the only ways to see the crossing are the
## inspector checkbox, which does not animate outside the editor, and a capture
## harness. That is a bad loop for something whose whole design question is how it
## FEELS at three seconds, and every lighting change in this scene wants checking
## at both ends of it.
##
## Gated on the switch because it is meaningless without one: scenes A and A2 run
## the clock, and `nightmare` does nothing there but sit at false.
func _unhandled_input(event: InputEvent) -> void:
	if not debug_flip_key or not use_nightmare_switch or Engine.is_editor_hint():
		return
	if not event.is_action_pressed("nightmare_flip"):
		return
	set_nightmare(not nightmare)
	get_viewport().set_input_as_handled()


var _flip := 0.0
var _stage := 0.0
var _beat: Stage = Stage.NORMAL


func _process(delta: float) -> void:
	var t: float
	if Engine.is_editor_hint():
		# `nightmare` snaps `_flip` in its setter, so the editor shows the state the
		# checkbox names; with the switch off, the manual phase is still the preview.
		t = lerpf(normal_phase, nightmare_phase, _flip) if use_nightmare_switch \
				else manual_time_of_day
	elif use_nightmare_switch:
		# A CONSTANT-DURATION crossing rather than a constant rate: `nightmare_seconds`
		# is how long the whole span takes, so retargeting the anchors does not
		# silently retime the flip.
		var step := delta / maxf(nightmare_seconds, 0.0001)
		_flip = clampf(_flip + (step if nightmare else -step), 0.0, 1.0)
		# Smoothstepped, so the ends ease and the middle is quick. Linear over three
		# seconds reads as a fader being pulled; this reads as something arriving.
		t = lerpf(normal_phase, nightmare_phase, smoothstep(0.0, 1.0, _flip))
	elif advance_with_time:
		day_phase = fposmod(day_phase + delta / maxf(day_length_seconds, 0.0001), 1.0)
		t = day_phase
	else:
		t = manual_time_of_day
	_apply(t)
	_broadcast(t)


# THE CROSSING, PUBLISHED. Separate from `_apply` because `_apply` is a pure write
# of the current state and this is about the DIFFERENCE between two frames — and
# because a signal emitted from inside the editor's @tool pass would run listeners
# against a scene that is not playing.
func _broadcast(t: float) -> void:
	var span := nightmare_phase - normal_phase
	var s := clampf((t - normal_phase) / (span if absf(span) > 1e-5 else 1e-5), 0.0, 1.0)
	if Engine.is_editor_hint():
		_stage = s
		return
	if not is_equal_approx(s, _stage):
		var was := _stage
		_stage = s
		nightmare_stage_changed.emit(s)
		var b := _beat_for(s)
		if b != _beat:
			_beat = b
			nightmare_beat.emit(b, s > was)
			if b == Stage.NIGHTMARE:
				nightmare_finished.emit(true)
			elif b == Stage.NORMAL:
				nightmare_finished.emit(false)


func _beat_for(s: float) -> Stage:
	if s >= STAGE_STARTS[Stage.NIGHTMARE]:
		return Stage.NIGHTMARE
	if s >= STAGE_STARTS[Stage.REVEAL]:
		return Stage.REVEAL
	if s >= STAGE_STARTS[Stage.FLASH]:
		return Stage.FLASH
	if s >= STAGE_STARTS[Stage.COLLAPSE]:
		return Stage.COLLAPSE
	return Stage.NORMAL


func _apply(t: float) -> void:
	# THE PRESET, BOUND ONCE. Everything below reads its blendable values off `src`
	# — which is either the resource or this node — so assigning a preset swaps the
	# inputs to the blend without there being a second blend. See the `preset`
	# export for why it is done this way rather than by copying fields in.
	var src: Variant = preset if preset != null else self

	# THE PANORAMA'S OWN CLOCK, and it is skipped entirely for a void-gradient sky.
	#
	# `sky_panorama_cycle` blends two photographs by phase and needs to be told what
	# the phase is; `sky_void_gradient` has none of these seven uniforms. Godot does
	# not reject a `set_shader_parameter` for a name the shader has never heard of —
	# it stores it in the material — so pushing them at the void sky was harmless at
	# runtime and quietly wrong in the editor, where this @tool script would have
	# written seven dead parameters into MAT_sky_w2_void.tres the next time anybody
	# saved the scene. A material is one kind of sky or the other.
	if sky_material and not drive_void_sky:
		sky_material.set_shader_parameter("advance_with_time", false)
		sky_material.set_shader_parameter("manual_time_of_day", t)
		sky_material.set_shader_parameter("day_start", src.day_start)
		sky_material.set_shader_parameter("day_end", src.day_end)
		sky_material.set_shader_parameter("night_start", src.night_start)
		sky_material.set_shader_parameter("night_end", src.night_end)
		sky_material.set_shader_parameter("smooth_transition", smooth_transition)

	var w: Vector3 = _phase_weights(t)  # x=day, y=trans, z=night

	if directional_light:
		directional_light.light_color = _mix3_color(src.day_sun_color, src.trans_sun_color, src.night_sun_color, w)
		directional_light.light_energy = src.day_sun_energy * w.x + src.trans_sun_energy * w.y + src.night_sun_energy * w.z
		if drive_sun_transform:
			directional_light.rotation_degrees = src.day_sun_rotation_degrees * w.x \
				+ src.trans_sun_rotation_degrees * w.y \
				+ src.night_sun_rotation_degrees * w.z
		directional_light.shadow_opacity = src.day_shadow_opacity * w.x \
			+ src.trans_shadow_opacity * w.y \
			+ src.night_shadow_opacity * w.z

	if world_environment and world_environment.environment:
		var env := world_environment.environment
		env.ambient_light_color = _mix3_color(src.day_ambient_color, src.trans_ambient_color, src.night_ambient_color, w)
		env.ambient_light_energy = src.day_ambient_energy * w.x + src.trans_ambient_energy * w.y + src.night_ambient_energy * w.z
		env.ambient_light_sky_contribution = src.day_sky_contribution * w.x \
			+ src.trans_sky_contribution * w.y \
			+ src.night_sky_contribution * w.z
		env.background_energy_multiplier = src.day_sky_brightness * w.x \
			+ src.trans_sky_brightness * w.y \
			+ src.night_sky_brightness * w.z

	# Broadcast a single scene "light tint" for the unshaded water/mist shaders, which can't
	# read the sun/ambient themselves. Built from the same blended ambient+sun and normalized
	# by the DAY baseline, so midday == white (no change to the tuned look) and it shifts warm
	# at sunset / dark-blue at night automatically. See the tod_water_tint global uniform.
	var sun_col := _mix3_color(src.day_sun_color, src.trans_sun_color, src.night_sun_color, w)
	var sun_e: float = src.day_sun_energy * w.x + src.trans_sun_energy * w.y + src.night_sun_energy * w.z
	var amb_col := _mix3_color(src.day_ambient_color, src.trans_ambient_color, src.night_ambient_color, w)
	var amb_e: float = src.day_ambient_energy * w.x + src.trans_ambient_energy * w.y + src.night_ambient_energy * w.z
	var tint := _scene_tint(amb_col, amb_e, sun_col, sun_e)
	var base := _scene_tint(src.day_ambient_color, src.day_ambient_energy, src.day_sun_color, src.day_sun_energy)
	RenderingServer.global_shader_parameter_set("tod_water_tint", Color(
		tint.r / maxf(base.r, 1e-4),
		tint.g / maxf(base.g, 1e-4),
		tint.b / maxf(base.b, 1e-4), 1.0))

	# THE HAZE AND THE UNLIT ART, the two multipliers described in the Haze group
	# above. Blended across the phases exactly as everything else here is, and both
	# WHITE at every default — so a scene that has not authored them publishes
	# white, and white is what every shader that reads them already multiplies by.
	var haze := _mix3_color(src.day_haze_tint, src.trans_haze_tint, src.night_haze_tint, w)
	var art := _mix3_color(src.day_art_tint, src.trans_art_tint, src.night_art_tint, w)
	RenderingServer.global_shader_parameter_set("tod_haze_tint", haze)
	RenderingServer.global_shader_parameter_set("tod_art_tint", art)
	# WHICH ENVIRONMENT BALL THE ISLAND IS STANDING IN. `SHADERINC_island_light.gdshaderinc`
	# carries two bakes — one per end of the flip — because the sky's ANGULAR
	# profile inverts between them and a tint cannot turn one into the other. This
	# is the mix between them, and it is the night weight plus half the transition,
	# which is the same shape `tod_daylight` uses one way round.
	RenderingServer.global_shader_parameter_set("tod_env_blend", w.z + 0.5 * w.y)
	# ...and kept, for the one consumer that is not a shader. See `art_tint()`.
	_haze_tint = haze
	_art_tint = art

	# The Environment's fog is a member of the haze family like any other, and it is
	# the one member that is not a shader uniform — so it cannot read the global and
	# has to be written here. `fog_light_base` at black means "not mine to touch".
	if world_environment and world_environment.environment \
			and fog_light_base != Color(0.0, 0.0, 0.0):
		world_environment.environment.fog_light_color = _mul(fog_light_base, haze)

	# THE VOID SKY. Five writes, none of them a new colour: the horizon is the haze
	# base times the haze tint (the same product every fog in the scene is), the sun
	# glow is the authored one shifted by how far the sun has moved from its day
	# colour, the vortex is the art tint the clouds take, and only the DOME is
	# authored per phase — because it is the one value that has to leave the family,
	# going to near-black over a horizon that stays lit. See `drive_void_sky`.
	if drive_void_sky and sky_material:
		var sun_tint := Color(
			sun_col.r / maxf(src.day_sun_color.r, 1e-4),
			sun_col.g / maxf(src.day_sun_color.g, 1e-4),
			sun_col.b / maxf(src.day_sun_color.b, 1e-4), 1.0)
		sky_material.set_shader_parameter("bottom_color", _mul(sky_haze_base, haze))
		sky_material.set_shader_parameter("top_color",
			_mix3_color(src.day_sky_top, src.trans_sky_top, src.night_sky_top, w))
		sky_material.set_shader_parameter("horizon_glow", _mul(sky_glow_base, haze))
		sky_material.set_shader_parameter("sun_glow_color", _mul(sky_sun_glow_base, sun_tint))
		sky_material.set_shader_parameter("vortex_color", _mul(sky_vortex_base, art))

	# Daylight factor for sun-dependent effects (e.g. the rainbow arc): full in day, half
	# through the sunset/sunrise transition, zero at night. See the tod_daylight global.
	RenderingServer.global_shader_parameter_set("tod_daylight", w.x + 0.5 * w.y)

	# THE HEMISPHERE THE UNLIT ISLAND IS LIT BY. `SHADERINC_island_light.gdshaderinc` lerps
	# between these two by the world normal's Y, so together they are the whole
	# ambient half of the island's shading: the dome overhead and the light bounced
	# back up off the cloud sea below it.
	#
	# ABSOLUTE, NOT NORMALISED, which is what separates these from `tod_water_tint`
	# above. That one is a MULTIPLIER on art already painted with its own light, so
	# it is divided through by the day baseline to come out white at midday and
	# leave the tuned look alone. These two ARE the light — there is no engine term
	# underneath them to modulate — so they carry their absolute level with the
	# ambient energy folded in, exactly as `tod_sun_color` does with the sun's.
	RenderingServer.global_shader_parameter_set("tod_sky_color", _scaled(amb_col, amb_e))
	RenderingServer.global_shader_parameter_set("tod_ground_color", _scaled(
		_mix3_color(src.day_bounce_color, src.trans_bounce_color, src.night_bounce_color, w), amb_e))

	# Dynamic sun direction + colour for cheap unshaded lighting (the waterfall water reads
	# these for a moving diffuse shade + glint, and in SCENE_test_zone_W2 they are the
	# island's whole light). basis.z points back toward the light, i.e. the
	# surface->sun vector. Colour folds in energy so the glint dims into night.
	#
	# `sun_pivot` wins the DIRECTION when it is set, so a scene can carry a sun with
	# no DirectionalLight3D in it at all. The COLOUR comes from `sun_col`/`sun_e`
	# above either way, which is not a behaviour change: `_apply` assigns exactly
	# those two values to the light at the top of this function, so reading them
	# back off it was a round trip that could only ever return what was just put in.
	var sun_node: Node3D = sun_pivot if sun_pivot != null else directional_light
	if sun_node:
		RenderingServer.global_shader_parameter_set(
			"tod_sun_dir", sun_node.global_transform.basis.z.normalized())
		RenderingServer.global_shader_parameter_set(
			"tod_sun_color", Color(sun_col.r * sun_e, sun_col.g * sun_e, sun_col.b * sun_e, 1.0))


# THE BOUNDARIES COME OFF THE PRESET TOO when there is one, so a saved sky carries
# its own shape of day and not just its colours — "how much of the clock is night"
# is part of the weather being described. Resolved here rather than passed in
# because `_apply` is not the only caller worth having.
func _phase_weights(t: float) -> Vector3:
	var src: Variant = preset if preset != null else self
	var day_start: float = src.day_start
	var day_end: float = src.day_end
	var night_start: float = src.night_start
	var night_end: float = src.night_end

	var d_day := _cyclic_dist(day_start, t)
	var len_day := _cyclic_dist(day_start, day_end)
	if d_day <= len_day:
		return Vector3(1.0, 0.0, 0.0)

	var d_sunset := _cyclic_dist(day_end, t)
	var len_sunset := _cyclic_dist(day_end, night_start)
	if d_sunset <= len_sunset:
		var p := d_sunset / maxf(len_sunset, 1e-5)
		return _trans_weights(p, true)

	var d_night := _cyclic_dist(night_start, t)
	var len_night := _cyclic_dist(night_start, night_end)
	if d_night <= len_night:
		return Vector3(0.0, 0.0, 1.0)

	var d_sunrise := _cyclic_dist(night_end, t)
	var len_sunrise := _cyclic_dist(night_end, day_start)
	var pr := d_sunrise / maxf(len_sunrise, 1e-5)
	return _trans_weights(pr, false)


# In a transition, the TRANS color peaks at the midpoint and the endpoint
# colors fall off linearly toward each end. `to_night` = true for sunset
# (DAY -> NIGHT), false for sunrise (NIGHT -> DAY).
func _trans_weights(p: float, to_night: bool) -> Vector3:
	var sp: float = smoothstep(0.0, 1.0, p) if smooth_transition else p
	var a: float
	var b: float
	var trans: float
	if sp < 0.5:
		a = 1.0 - sp * 2.0
		trans = sp * 2.0
		b = 0.0
	else:
		a = 0.0
		trans = 1.0 - (sp - 0.5) * 2.0
		b = (sp - 0.5) * 2.0
	if to_night:
		return Vector3(a, trans, b)
	return Vector3(b, trans, a)


func _cyclic_dist(from: float, to: float) -> float:
	var d := fposmod(to, 1.0) - fposmod(from, 1.0)
	if d < 0.0:
		d += 1.0
	return d


# Ambient-dominant scene tint: ambient light plus a fraction of the directional sun.
# Used (and normalized against the day value) to drive the tod_water_tint global.
const SUN_TINT_WEIGHT := 0.4

func _scene_tint(amb: Color, amb_e: float, sun: Color, sun_e: float) -> Color:
	return Color(
		amb.r * amb_e + sun.r * sun_e * SUN_TINT_WEIGHT,
		amb.g * amb_e + sun.g * sun_e * SUN_TINT_WEIGHT,
		amb.b * amb_e + sun.b * sun_e * SUN_TINT_WEIGHT, 1.0)


# Energy folded into the colour. The unlit shaders have no separate intensity to
# multiply by, so anything on the bus that stands in for a light has to arrive
# pre-scaled.
func _scaled(c: Color, e: float) -> Color:
	return Color(c.r * e, c.g * e, c.b * e, 1.0)


# Per-channel product. The whole haze/art scheme is one of these applied to a value
# somebody already authored, which is why every default in the group is white.
func _mul(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, 1.0)


func _mix3_color(a: Color, b: Color, c: Color, w: Vector3) -> Color:
	return Color(
		a.r * w.x + b.r * w.y + c.r * w.z,
		a.g * w.x + b.g * w.y + c.g * w.z,
		a.b * w.x + b.b * w.y + c.b * w.z,
		1.0)
