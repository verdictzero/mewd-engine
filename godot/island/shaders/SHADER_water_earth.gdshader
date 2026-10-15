shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// THE WATER OF A REAL PLACE: its sea, its lakes and its rivers, at the level the
// open data puts them (tools/earth_fetch.py), laid by SCRIPT_earth_dress.gd over
// the bed the field carved under it. DOUBLE-SIDED (at the user's request: "a
// really pretty double sided water shader too with fake caustics"):
//
// FROM ABOVE
//   * THROUGH IT, the bed: the picture behind the water (the screen), bent by
//     the waves (refraction), and dimmed by how far the light goes through the
//     water to it — the true thickness, off the depth buffer — red first, so
//     the shallows are clear, a lake turns turquoise and the deep goes to its
//     own colour (absorption and in-scattering, per channel).
//   * ON IT, the world: screen-space reflections — the reflected ray marched
//     through the depth buffer, so the cliffs and the woods stand upside down
//     in a still lake — and where the ray leaves the picture, the sky (the
//     picture's own sky where it can be found, else the sky's light), by
//     Fresnel (Schlick, water's 2 per cent head-on).
//   * The sun's glint, broad and pin-sharp, only where the sun reaches
//     (SHADERINC_earth_sun); foam where it thins over the shore; the edge
//     faded into the bank; the island's fog.
// FROM BELOW (the eye under the surface)
//   * SNELL'S WINDOW: straight up, a circle of the world above, bent and
//     tinted; past 48.6 degrees from the vertical, total internal reflection —
//     the water's own colour mirrored back down — with a bright rim between.
//     (SHADER_underwater.gdshader fogs everything under the surface.)
// THE CAUSTICS are on the bed itself (SHADER_terrain_earth.gdshader), so they
// shimmer whether the bed is seen through the surface or from under it.
//
// The mesh carries: COLOR.r which water (1/3 sea, 2/3 lake, 1 river), COLOR.a
// how deep it is there (metres / 32), UV a river's flow (metres a second).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;

group_uniforms body;
// per metre of water, how much of each channel is taken (red most)
uniform vec3 absorb = vec3(0.42, 0.115, 0.085);
// the colour the water itself glows, lit, where the light is taken
uniform vec3 scatter_color = vec3(0.05, 0.27, 0.31);
uniform vec3 sea_tint = vec3(0.8, 0.95, 1.12);
// how far the waves bend what is seen through them
uniform float refraction : hint_range(0.0, 0.2) = 0.045;

group_uniforms surface;
uniform float wave_scale = 9.0;
uniform float wave_scale_2 = 3.1;
uniform float wave_speed = 0.35;
uniform float wave_strength : hint_range(0.0, 2.0) = 0.3;
uniform float reflect_strength : hint_range(0.0, 1.0) = 1.0;
// how much of the waves the reflections take: a lake at evening is near a
// mirror, the cliffs in it barely broken (1: all of the waves)
uniform float reflect_waves : hint_range(0.0, 1.0) = 0.3;
// the screen-space reflections: steps, and how far (metres)
uniform int ssr_steps : hint_range(0, 64) = 26;
uniform float ssr_reach = 1800.0;
uniform float glint : hint_range(0.0, 16.0) = 3.0;
uniform float glint_power = 900.0;
uniform float foam_depth = 0.45;
uniform vec3 foam_color = vec3(0.86, 0.9, 0.9);

group_uniforms fog;
uniform bool fog_enabled = true;
uniform vec3 fog_color = vec3(0.62, 0.72, 0.84);
uniform float fog_distance_start = 1800.0;
uniform float fog_distance_density = 0.0004;
uniform float fog_distance_power = 2.0;

group_uniforms;

global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
#include "res://godot/island/shaders/SHADERINC_earth_sun.gdshaderinc"
global uniform vec4 tod_sky_color;
global uniform vec4 tod_ground_color;
global uniform vec4 tod_haze_tint;
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

// the view-space point drawn at `uv` (the depth buffer, either renderer's)
vec3 scene_at(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

bool sky_at(vec2 uv) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	return d <= 0.0000001 || d >= 0.9999999;
}

vec2 to_screen(vec3 vp, mat4 proj) {
	vec4 c = proj * vec4(vp, 1.0);
	return c.xy / max(c.w, 1e-5) * 0.5 + 0.5;
}

void fragment() {
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 geo_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float dist = length(VERTEX);
	vec3 sky = tod_sky_color.rgb;
	vec3 horizon = fog_color * tod_haze_tint.rgb;
	float sun_open = earth_sun_open(v_world);
	float sun_up = smoothstep(-0.03, 0.08, tod_sun_dir.y);
	// the light the water's own body glows with
	vec3 body_light = sky * 0.9 + tod_sun_color.rgb * 0.45 * max(tod_sun_dir.y, 0.0) * sun_open;
	vec3 scat = scatter_color * (v_kind < 0.5 ? sea_tint : vec3(1.0)) * body_light;
	vec3 col;
	float alpha = 1.0;

	if (abs(geo_n.y) < 0.5) {
		// THE WATER'S CUT FACE at the square's edge: its body, seen side-on
		col = scat * 0.8;
	} else {
		// the waves: a river's run downstream, still water's drift across
		float t = TIME * wave_speed;
		vec2 drift = v_flow * TIME;
		vec2 p = v_world.xz;
		vec2 w1 = water_wave((p - drift) / wave_scale + vec2(t * 0.05, t * 0.031));
		vec2 w2 = water_wave((p - drift * 1.3) / wave_scale_2 + vec2(-t * 0.043, t * 0.067));
		vec2 w3 = water_wave((p - drift * 1.7) / (wave_scale_2 * 0.37) + vec2(t * 0.09, -t * 0.071));
		float calm = 1.0 - smoothstep(60.0, 700.0, dist) * 0.75;
		vec2 wv = (w1 * 0.5 + w2 * 0.35 + w3 * 0.15) * wave_strength * calm;
		vec3 n = normalize(vec3(wv.x, 1.0, wv.y));
		// (the bend, in the screen: the waves' slope, less far off)
		vec2 bend = wv * refraction / max(dist * 0.02, 1.0);

		if (FRONT_FACING) {
			// ---- FROM ABOVE ----------------------------------------------
			float ndv = clamp(dot(n, world_v), 0.0, 1.0);
			float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
			// through it: the bed, bent, and how much water lies between
			vec2 ruv = clamp(SCREEN_UV + bend, vec2(0.001), vec2(0.999));
			vec3 bed_vp = scene_at(ruv, INV_PROJECTION_MATRIX);
			if (-bed_vp.z < -VERTEX.z) {
				// (bent onto something in front of the water: not bent)
				ruv = SCREEN_UV;
				bed_vp = scene_at(ruv, INV_PROJECTION_MATRIX);
			}
			float thick = sky_at(ruv) ? 200.0 : max(length(bed_vp) - dist, 0.0);
			vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;
			vec3 tr = exp(-absorb * thick);
			vec3 under = bed * tr + scat * (vec3(1.0) - tr);

			// on it: the world mirrored (screen-space), else the sky — off a
			// calmer surface than the one the light goes through
			vec3 nr = normalize(vec3(wv.x * reflect_waves, 1.0, wv.y * reflect_waves));
			vec3 rw = reflect(-world_v, nr);
			rw.y = abs(rw.y);
			vec3 rv = (VIEW_MATRIX * vec4(rw, 0.0)).xyz;
			vec3 refl = mix(mix(horizon, sky * 1.4, 0.45), sky * 1.6 + horizon * 0.2, smoothstep(0.0, 0.5, rw.y));
			bool hit = false;
			if (ssr_steps > 0 && reflect_strength > 0.0) {
				float st = 1.5;
				vec3 q = VERTEX;
				for (int i = 0; i < 64; i++) {
					if (i >= ssr_steps || st > ssr_reach) {
						break;
					}
					q = VERTEX + rv * st;
					vec2 suv = to_screen(q, PROJECTION_MATRIX);
					if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0 || q.z > -0.05) {
						break;
					}
					if (!sky_at(suv)) {
						float sd = -scene_at(suv, INV_PROJECTION_MATRIX).z;
						float qd = -q.z;
						if (qd > sd && qd - sd < st * 0.35 + 2.0) {
							// (a little search back for the edge)
							float lo = st / 1.32;
							float hi = st;
							for (int k = 0; k < 4; k++) {
								float mid = (lo + hi) * 0.5;
								vec3 m = VERTEX + rv * mid;
								vec2 muv = to_screen(m, PROJECTION_MATRIX);
								if (-m.z > -scene_at(muv, INV_PROJECTION_MATRIX).z) {
									hi = mid;
								} else {
									lo = mid;
								}
							}
							vec2 huv = to_screen(VERTEX + rv * hi, PROJECTION_MATRIX);
							vec2 edge = min(huv, 1.0 - huv);
							float keep = smoothstep(0.0, 0.08, min(edge.x, edge.y));
							refl = mix(refl, textureLod(screen_tex, huv, 0.0).rgb, keep);
							hit = true;
							break;
						}
					}
					st *= 1.32;
				}
				if (!hit) {
					// the sky the picture already has, where the ray goes into it
					vec2 fuv = to_screen(VERTEX + rv * 4000.0, PROJECTION_MATRIX);
					if (fuv.x > 0.0 && fuv.x < 1.0 && fuv.y > 0.0 && fuv.y < 1.0 && sky_at(fuv)) {
						vec2 edge = min(fuv, 1.0 - fuv);
						refl = mix(refl, textureLod(screen_tex, fuv, 0.0).rgb, smoothstep(0.0, 0.08, min(edge.x, edge.y)));
					}
				}
			}
			col = mix(under, refl, clamp(fres * reflect_strength, 0.0, 1.0));
			// the sun's glint: pin-sharp, and a broader sheen
			float rs = max(dot(reflect(-world_v, n), tod_sun_dir), 0.0);
			col += tod_sun_color.rgb * (pow(rs, glint_power) * glint + pow(rs, 60.0) * 0.08)
					* sun_open * sun_up;
			// foam where it thins over the shore, broken by the waves
			float foam = (1.0 - smoothstep(0.0, foam_depth, thick))
					* smoothstep(0.15, 0.75, w1.x * 0.5 + 0.5 + w2.y * 0.3 + w3.x * 0.2);
			col = mix(col, foam_color * (sky + tod_sun_color.rgb * 0.8 * sun_open), foam * 0.55);
			// and into the bank without a line
			alpha = smoothstep(0.0, 0.1, thick);
		} else {
			// ---- FROM BELOW ----------------------------------------------
			vec3 nd = -n;
			float c = clamp(dot(world_v, nd), 0.0, 1.0);
			// inside the window (48.6 degrees from straight up), the world above
			float window = smoothstep(0.63, 0.69, c);
			vec2 auv = clamp(SCREEN_UV + bend * 2.5, vec2(0.001), vec2(0.999));
			vec3 above = textureLod(screen_tex, auv, 0.0).rgb * vec3(0.85, 0.95, 1.0);
			// outside it, the water's own colour mirrored back
			vec3 tir = scat * 1.5;
			col = mix(tir, above, window);
			// the window's bright rim
			col += body_light * exp(-pow((c - 0.66) / 0.02, 2.0)) * 0.25;
		}
	}

	if (fog_enabled && FRONT_FACING) {
		float d = max(dist - fog_distance_start * tod_fog_near, 0.0) * fog_distance_density * tod_fog_density;
		float fog = 1.0 - exp(-pow(d, fog_distance_power));
		col = mix(col, horizon, fog);
	}
	ALBEDO = col;
	ALPHA = alpha;
}
