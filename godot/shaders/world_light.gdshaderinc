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

// the air: toward the sky's horizon between air_near and air_far, on a
// smooth ramp, so it starts gently (worldShade's `at`)
vec3 world_air(vec3 c, float d) {
	float at = clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	return mix(c, air_color.rgb, at * at * (3.0 - 2.0 * at));
}

// THE AIR IN THE FRAGMENT'S OWN AZIMUTH, for a map with a skybox: what a
// surface fades to is the skybox's texel on the row just over the horizon
// in the direction it lies from the eye (worldShade: atan2(z, x) over a
// full turn, the sphere's own u — godot/shaders/skybox.gdshader), decoded
// to linear as the web build's fetch is. `to` is the fragment less the
// eye. air_sky_on 0 (no skybox) is world_air, toward air_color.
global uniform sampler2D air_sky : filter_nearest, repeat_enable;
global uniform float air_sky_on;
vec3 world_air_at(vec3 c, float d, vec3 to) {
	if (air_sky_on < 0.5) return world_air(c, d);
	float at = clamp((d - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	vec2 sz = vec2(textureSize(air_sky, 0));
	vec3 s = texture(air_sky, vec2(fract(atan(to.z, to.x) * 0.15915494), 0.5 - 0.5 / sz.y)).rgb;
	vec3 air = mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s));
	return mix(c, air, at * at * (3.0 - 2.0 * at));
}

// A MAP'S OWN AMBIENT LIGHT AND DEFAULT FOG (js/material.js applyMapLight:
// ambientColor, fogDefault, fogAmbient), for the surfaces that are not
// the level's own — a sprite, a plant, a car; the tinted level shader
// has its own. Nothing at their defaults (MapGeo sets them).
global uniform vec4 ambient_light;
global uniform vec4 map_fog;
global uniform float map_fog_ambient;

// the light on a surface: its banded light in the map's light colour,
// and the ambient light on top however dark it is (worldShade)
vec3 world_lit(float l) {
	return l * light_color.rgb + ambient_light.rgb;
}

// the map's fog, GZDoom's: half-way in at 25600/density units
vec3 world_fog(vec3 c, float d) {
	if (map_fog.a <= 0.0) return c;
	float ff = 1.0 - exp2(-d * map_fog.a / 25600.0);
	return mix(c, map_fog.rgb * light_color.rgb + ambient_light.rgb * map_fog_ambient, ff);
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
