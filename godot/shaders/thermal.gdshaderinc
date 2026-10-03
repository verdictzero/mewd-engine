// MEWD — the world IN HEAT, for the launcher's thermal sight (js/material.js
// world.thermal, thermalOf and the THERMAL block of COMMON_FRAG; js/sky.js).
// Include AFTER world_light.gdshaderinc: it reads the air and the beam.
//
// WHICH PICTURE IS THE THERMAL ONE. The web build turns world.thermal on
// for exactly one render call a frame — the feed — and off again. A
// global uniform cannot do that here: Godot uploads the globals once a
// frame, before any viewport is drawn, so the main view and the feed see
// the same value. What tells them apart instead is the one thing that
// differs per viewport inside a shader: VIEWPORT_SIZE. The thermal feed's
// SubViewport is a size nothing else in the game is (172 x 176, see
// ThermalScope), and ThermalScope sets `thermal_view` to that size while
// the sight is held (zero otherwise), so `thermal_on(VIEWPORT_SIZE)` is
// true in the feed and nowhere else.
//
// WHAT IS WARM: PEOPLE, AND NOTHING ELSE (at the user's request). A body
// is warm whatever it wears (thermal_body); everything else — ground,
// walls, plants, lamps, engines, fire — sits in one narrow cold band
// (thermal_base.gdshaderinc's thermal_cold), and the air takes the
// distance down to the cold of the sky. The number goes out in
// all three channels, written so the feed's texture holds exactly it (see
// thermal_raw), and the screen (thermal_screen.gdshader) runs it up IRONBOW.

#include "res://godot/shaders/thermal_base.gdshaderinc"

// the fire nearest the player, in Godot's coordinates, and its level (w),
// and its reach (js/material.js fireLightPos / fireLight / fireLightRange),
// written by ThermalScope off FireSystem — no longer warming anything (only
// people are hot), kept so ThermalScope's writes have somewhere to go
global uniform vec4 thermal_fire;
global uniform float thermal_fire_range;

// how warm a surface is (thermalOf): its colour (linear, as sampled), the
// light on it, its depth and its place in the world, and whether it is its
// own light
float thermal_of(vec3 albedo, float l, float d, vec3 wp, float fullbright) {
	// (once: darker paint and the light a little warmer, the fire and the
	// lance's column warming what was near, a light of its own white —
	// now ONLY PEOPLE ARE HOT, and everything else is the cold band)
	return thermal_cold(albedo, clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0));
}

// A BODY is warm whatever colour its coat is: the drawing's own light and
// dark only give the figure its shape (`lum`, of the picture's texel)
float thermal_body(vec3 texel, float d) {
	float lum = dot(thermal_srgb(texel), vec3(0.30, 0.59, 0.11));
	float at = clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	return mix(mix(0.66, 0.86, lum), 0.06, at * at * 0.85);
}

// what an added glow (coals, embers, a hot rim) is worth in heat: nothing,
// now only people are hot
float thermal_glow(vec3 glow) {
	return 0.0;
}
