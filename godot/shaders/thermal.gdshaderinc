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
// WHAT IS WARM. Everything that is not a source sits low and close
// together: a little warmer for darker paint, a little for the light
// falling on it; the fire and the lance's column warm what is near them;
// anything that is its own light is the hottest thing there is; the air
// takes the distance down to the cold of the sky. The number goes out in
// all three channels, written so the feed's texture holds exactly it (see
// thermal_raw), and the screen (thermal_screen.gdshader) runs it up IRONBOW.

// the thermal feed's size in pixels while the sight is up, else zero
global uniform vec2 thermal_view;
// the fire nearest the player, in Godot's coordinates, and its level (w),
// and its reach (js/material.js fireLightPos / fireLight / fireLightRange),
// written by ThermalScope off FireSystem
global uniform vec4 thermal_fire;
global uniform float thermal_fire_range;
// 1 under the Compatibility renderer, whose 3D goes into a SubViewport as
// the shader wrote it; 0 under Forward+, whose tonemap pass sRGB-encodes it
// on the way in — set by ThermalScope, so the feed holds the heat either way
global uniform float thermal_raw;

// VIEWPORT_SIZE is a built-in of the stage functions, so it is handed in
bool thermal_on(vec2 viewport) {
	return thermal_view.x > 0.5 && abs(viewport.x - thermal_view.x) < 0.5 && abs(viewport.y - thermal_view.y) < 0.5;
}

// a linear colour back to the byte it was painted as, for its luminance
vec3 thermal_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// how warm a surface is (thermalOf): its colour (linear, as sampled), the
// light on it, its depth and its place in the world, and whether it is its
// own light
float thermal_of(vec3 albedo, float l, float d, vec3 wp, float fullbright) {
	float lum = dot(thermal_srgb(albedo), vec3(0.2126, 0.7152, 0.0722));
	float h = 0.13 + 0.07 * (1.0 - lum) + 0.09 * lum * lum + 0.06 * clamp(l, 0.0, 1.0);
	if (thermal_fire.w > 0.0) {
		float fa = clamp(1.0 - distance(wp, thermal_fire.xyz) / max(1.0, thermal_fire_range), 0.0, 1.0);
		h += fa * fa * thermal_fire.w * 0.45;
	}
	if (beam_level > 0.0) {
		vec3 rel = wp - beam_pos;
		float along = clamp(dot(rel, beam_dir), 0.0, beam_len);
		float ba = clamp(1.0 - distance(rel, beam_dir * along) / beam_range, 0.0, 1.0);
		h += ba * ba * beam_level * 0.5;
	}
	h = mix(h, 1.0, fullbright);
	float at = clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	return mix(h, 0.06, at * at * 0.85);
}

// A BODY is warm whatever colour its coat is: the drawing's own light and
// dark only give the figure its shape (`lum`, of the picture's texel)
float thermal_body(vec3 texel, float d) {
	float lum = dot(thermal_srgb(texel), vec3(0.30, 0.59, 0.11));
	float at = clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	return mix(mix(0.66, 0.86, lum), 0.06, at * at * 0.85);
}

// what an added glow (coals, embers, a hot rim) is worth in heat
float thermal_glow(vec3 glow) {
	return dot(thermal_srgb(glow), vec3(0.30, 0.59, 0.11));
}

// the number, out: so the feed's texture holds it as written (thermal_raw)
vec3 thermal_out(float h) {
	h = clamp(h, 0.0, 1.0);
	if (thermal_raw > 0.5) return vec3(h);
	return vec3(h <= 0.04045 ? h / 12.92 : pow((h + 0.055) / 1.055, 2.4));
}
