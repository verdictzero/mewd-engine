@tool
class_name SkyCyclePreset
extends Resource

# A WHOLE SKY, SAVED — every value `SkyCycleController` blends across the day, in
# one resource, so a look can be carried between scenes instead of copy-pasted
# between .tscn files.
#
# WHY THIS IS NOT A SKY MATERIAL, which is the obvious place to have put it. W2's
# blood night is thirty-odd numbers and only three of them live on the sky: the
# sun, ambient and bounce colours at three phases, the two tint multipliers at
# three phases, the phase boundaries, and the dome's colour at each. A
# `MAT_sky_blood.tres` would capture the dome and nothing else — and only at ONE
# phase, statically, since the whole point is that these move. The sky materials in
# `materials/` stay what they are: the shader's own parameters, authored per scene.
# This is the thing on top of them that changes with the hour.
#
# ---------------------------------------------------------------------------
# WHAT IS IN HERE AND WHAT DELIBERATELY IS NOT.
#
# IN: everything the cycle BLENDS. If `_apply` mixes it by the phase weights, it
# belongs to the look and it is here.
#
# OUT: the scene's own contract with itself — `sky_haze_base`, `sky_glow_base`,
# `sky_sun_glow_base`, `sky_vortex_base`, `fog_light_base`. Those stay exports on
# the controller node, and that split is the entire reason a preset can travel.
# SCENE_test_zone_W2 hazes to the exact neutral 0.30 and SCENE_test_zone_W hazes to
# 0.089; both are correct, each is a property of the scene's own sky and fog, and
# neither is a property of the weather. The tints in here are MULTIPLIERS on
# whichever of those a scene holds, so the same night lands correctly on both
# without knowing which it is standing in.
#
# ALSO OUT: `advance_with_time`, `day_length_seconds`, `manual_time_of_day`,
# `drive_void_sky`, `drive_sun_transform`. Those are how a scene RUNS the cycle,
# not what the cycle looks like — pacing and wiring, and a preset that carried them
# would silently start clocks in scenes that wanted to stay parked.
#
# ---------------------------------------------------------------------------
# HOW IT IS APPLIED. `SkyCycleController._apply` does
#
#     var src: Variant = preset if preset != null else self
#
# and then reads every field below off `src`. So the preset is a DROP-IN STAND-IN
# for the node's own exports rather than a second code path, which is what keeps
# the two from drifting: there is one blend, and it does not know where its inputs
# came from. The names here are therefore not cosmetic — they have to match the
# controller's exports exactly, and `tests/TEST_w2_cycle.gd` asserts that the two
# field sets agree rather than leaving it to a runtime error on the one frame
# somebody assigns a preset.
#
# TO MAKE A NEW ONE: duplicate the nearest `data/SKYCYCLE_*.tres`, change the
# numbers, point a controller at it. To take a scene BACK off presets, clear the
# `preset` export — the node's own exports are still there and still authoritative.

@export_group("Phase Boundaries")
## Where the four bands sit on the 0..1 clock. In the preset because "how much of
## the day is night" is a property of the weather being described, not of the scene
## describing it — W2's blood night runs a 26% night band and a short, hard sunset,
## and a preset that carried the colours without the timing would be a different
## night wherever it landed.
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

@export_group("Haze")
## Multipliers on whatever haze and unlit-art colours the scene already holds. See
# the controller's own Haze group for the whole argument; the short version is that
## these are the only two fields in this file that can be portable at all, because
## a multiplier does not have to know what it is multiplying.
##
## WHITE IS THE IDENTITY and is the default at every phase, so a half-written
## preset degrades to "no tint" rather than to a colour nobody chose.
@export var day_haze_tint: Color = Color(1.0, 1.0, 1.0)
@export var trans_haze_tint: Color = Color(1.0, 1.0, 1.0)
@export var night_haze_tint: Color = Color(1.0, 1.0, 1.0)
@export var day_art_tint: Color = Color(1.0, 1.0, 1.0)
@export var trans_art_tint: Color = Color(1.0, 1.0, 1.0)
@export var night_art_tint: Color = Color(1.0, 1.0, 1.0)

@export_group("Void Sky")
## The dome overhead per phase — the one colour in the family that is ABSOLUTE
## rather than a tint, because it is the one that has to leave the family. A blood
## night takes it to near-black while the horizon under it stays lit, and no single
## multiplier on a grey dome produces both.
##
## IT IS IN THE PRESET AND `sky_haze_base` IS NOT, which looks inconsistent and is
## not: the dome is what the weather does to the sky, the haze base is what THIS
## scene's sky and fog were authored at. A scene whose daylight dome is not 0.666
## overrides `day_sky_top` by making its own preset — that is what presets are for
## — but it must never have to restate its haze value to borrow a night.
@export var day_sky_top: Color = Color(0.666, 0.666, 0.666)
@export var trans_sky_top: Color = Color(0.666, 0.666, 0.666)
@export var night_sky_top: Color = Color(0.666, 0.666, 0.666)
