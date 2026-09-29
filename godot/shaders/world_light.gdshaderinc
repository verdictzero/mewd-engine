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

// THE POSITRON LANCE'S LIGHT (js/material.js beamPos, and js/beam.js
// ticLight), and it is a SEGMENT and not a point: a column drawn from
// the muzzle to where it landed is lit along its whole length, so every
// fragment measures its distance to the nearest point ON THE LINE. A
// point light at the muzzle would light the wall beside you and leave
// the street the beam crossed in the dark, which is exactly backwards.
// DIFFERENTIAL AND RANDOMISED, at the user's request: a hash of the
// fragment's place on a coarse grid picks the rate and phase of its
// flicker, so no two surfaces agree about it. It outlives the beam (the
// level falls over js/beam.js AFTERGLOW). Globals, set by BeamSystem.
global uniform float beam_level;
global uniform vec3 beam_pos;
global uniform vec3 beam_dir;
global uniform float beam_len;
global uniform float beam_range;
global uniform float beam_seed;
global uniform vec4 beam_color;

// what the beam adds to a surface of colour `albedo` at world point `wp`
vec3 world_beam(vec3 albedo, vec3 wp) {
	if (beam_level <= 0.0) return vec3(0.0);
	vec3 rel = wp - beam_pos;
	float along = clamp(dot(rel, beam_dir), 0.0, beam_len);
	float off = distance(rel, beam_dir * along);
	float ba = clamp(1.0 - off / beam_range, 0.0, 1.0);
	ba *= ba;
	// (a sine-free hash of the cell: see sear_decal.gdshader for why)
	vec3 h3 = fract(floor(wp * 0.017) * 0.1031);
	h3 += dot(h3, h3.zyx + 31.32);
	float n = fract((h3.x + h3.y) * h3.z);
	float flick = 0.62 + 0.38 * sin(beam_seed * (4.0 + n * 9.0) + n * 31.4);
	// and a hard white core to it very close in, which is what stops a
	// wall a metre from the column reading as merely green
	return albedo * beam_color.rgb * (ba * beam_level * flick) + beam_color.rgb * ba * ba * beam_level * 0.22 * flick;
}
