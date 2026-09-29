// MEWD — the world's light, shared by every surface and every sprite
// (js/material.js: the `world` uniforms and worldBand). Globals, so one
// assignment relights everything: the hour (sky_light), a flash
// (global_light), the air (air_near / air_far / air_color).
global uniform float sky_light;
global uniform float global_light;
global uniform float light_falloff;
global uniform float min_light;
global uniform float air_near;
global uniform float air_far;
global uniform vec4 air_color;
global uniform vec4 light_color;

// Distance diminishing, linear in depth as Doom's was, stretched and
// lifted under the sky; the sky's light lifts an outdoor surface's own;
// then the STEP, 32 levels, Doom's 32 colormaps.
float world_band(float light_in, float d, float sky) {
	float fall = light_falloff * mix(1.0, 3.4, sky);
	float mn = min(0.85, min_light + 0.32 * sky);
	float li = mix(light_in, max(light_in, sky_light), sky);
	mn = mix(mn, 1.0, clamp(sky_light, 0.0, 1.0) * sky);
	float dim = 1.0 - clamp(d / fall, 0.0, 1.0);
	float l = li * mix(mn, 1.0, dim) * global_light;
	return floor(l * 32.0 + 0.5) / 32.0;
}

// the air: toward the sky's horizon between air_near and air_far
vec3 world_air(vec3 c, float d) {
	float at = clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	return mix(c, air_color.rgb, at * at);
}
