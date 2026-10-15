shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;
#include "res://godot/shaders/thermal_base.gdshaderinc"

// THE WATER OF A REAL PLACE: its sea, its lakes and its rivers, at the level the
// open data puts them (tools/earth_fetch.py: a lake flat at its own surface, the
// sea at sea level, a river falling with its valley), drawn by
// SCRIPT_earth_dress.gd over the bed the field carved under it.
//
// The mesh carries what this needs, so it reads no depth buffer:
//
//   COLOR.r  which water: 1/3 sea, 2/3 lake, 1 river
//   COLOR.a  how deep it is over the ground there, metres / 32
//   UV       a river's flow, metres a second, down its own slope
//
// Unshaded, and lit the way the island lights everything (the tod_* bus): the
// sky reflected by Fresnel off a normal from two drifting wave maps, the sun's
// glint off the same normal, the body's own colour through it by depth, foam
// where it thins over the shore, and the island's fog.

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.42, 0.42);
uniform vec3 deep_color : source_color = vec3(0.02, 0.10, 0.16);
uniform vec3 sea_tint : source_color = vec3(0.85, 0.95, 1.1);
// how fast the light goes, per metre of water
uniform float absorb = 0.35;
uniform float alpha_shallow : hint_range(0.0, 1.0) = 0.25;
uniform float alpha_deep : hint_range(0.0, 1.0) = 0.93;
// metres of the waves' maps and how fast they drift
uniform float wave_scale = 9.0;
uniform float wave_scale_2 = 3.1;
uniform float wave_speed = 0.35;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.3;
uniform float glint : hint_range(0.0, 8.0) = 1.2;
uniform float glint_power = 380.0;
uniform float foam_depth = 0.35;
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.6;

uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.62, 0.72, 0.84);
uniform float fog_distance_start = 1800.0;
uniform float fog_distance_density = 0.0004;
uniform float fog_distance_power = 2.0;

global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
global uniform vec4 tod_sky_color;
global uniform vec4 tod_ground_color;
global uniform vec4 tod_haze_tint;
// THE WEATHER'S FOG (EnviroSky): the density times this, the start times
// that; both 1 wherever no EnviroSky is.
global uniform float tod_fog_density;
global uniform float tod_fog_near;


varying float v_kind;
varying float v_depth;
varying vec2 v_flow;
varying vec3 v_world;

void vertex() {
	v_kind = COLOR.r;
	v_depth = COLOR.a * 32.0;
	v_flow = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 water_wave(vec2 uv) {
	return texture(wave_normal, uv).xy * 2.0 - 1.0;
}

void fragment() {
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float dist = length(VERTEX);
	float t = TIME * wave_speed;
	// a river's maps run with it; still water's drift slowly across each other
	vec2 drift = v_flow * TIME;
	vec2 p = v_world.xz;
	vec2 w1 = water_wave((p - drift) / wave_scale + vec2(t * 0.05, t * 0.031));
	vec2 w2 = water_wave((p - drift * 1.3) / wave_scale_2 + vec2(-t * 0.043, t * 0.067));
	// calmer far off, where the maps would only shimmer
	float calm = 1.0 - smoothstep(60.0, 600.0, dist) * 0.7;
	vec2 wv = (w1 * 0.6 + w2 * 0.4) * wave_strength * calm;
	vec3 n = normalize(vec3(wv.x, 1.0, wv.y));

	float depth = max(v_depth, 0.0);
	float through = exp(-depth * absorb);
	vec3 body = mix(deep_color, shallow_color, through);
	if (v_kind < 0.5) {
		body *= sea_tint;
	}
	// the water's own colour is lit by the sky and the sun like anything else
	vec3 sky = tod_sky_color.rgb;
	float ndl = clamp(dot(n, tod_sun_dir), 0.0, 1.0);
	body *= sky * 0.9 + tod_sun_color.rgb * (0.35 + 0.65 * ndl);

	// the sky in it: zenith overhead, the haze at the horizon
	vec3 r = reflect(-world_v, n);
	vec3 horizon = fog_color * tod_haze_tint.rgb;
	// (the haze toward the horizon, but bluer than the fog: what a lake
	// shows is the sky over the far shore, not the air in front of it)
	vec3 refl = mix(mix(horizon, sky * 1.4, 0.45), sky * 1.6 + horizon * 0.2, smoothstep(0.0, 0.5, r.y));
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(n, world_v), 0.0, 1.0), 5.0);
	vec3 col = mix(body, refl, clamp(fres * reflect_strength, 0.0, 1.0));
	// the sun's glint
	float sp = pow(max(dot(r, tod_sun_dir), 0.0), glint_power);
	col += tod_sun_color.rgb * sp * glint;

	float alpha = mix(alpha_deep, alpha_shallow, through);
	alpha = max(alpha, fres * reflect_strength);
	// foam where it thins out over the shore, broken by the waves
	float foam = (1.0 - smoothstep(0.0, foam_depth, depth)) * smoothstep(0.1, 0.7, w1.x * 0.5 + 0.5 + w2.y * 0.3);
	col = mix(col, foam_color * (sky + tod_sun_color.rgb * 0.8), foam * 0.6);
	alpha = max(alpha, foam * 0.7);
	// and gone at the waterline itself, so the bank meets it softly
	alpha *= smoothstep(0.0, 0.12, depth);

	if (fog_enabled) {
		float d = max(dist - fog_distance_start * tod_fog_near, 0.0) * fog_distance_density * tod_fog_density;
		float fog = 1.0 - exp(-pow(d, fog_distance_power));
		col = mix(col, horizon, fog);
	}
	ALBEDO = col;
	ALPHA = alpha;
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_cold(ALBEDO, clamp((dist - 700.0) / 2500.0, 0.0, 1.0)));
}
