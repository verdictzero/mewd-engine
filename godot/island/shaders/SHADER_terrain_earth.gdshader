shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://godot/shaders/thermal_base.gdshaderinc"

#include "res://godot/island/shaders/SHADERINC_island_light.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// THE GROUND OF A REAL PLACE, in high-resolution PBR (at the user's request:
// "high res pbr textures on the map"). The terrain golf's islands are drawn with
// (SHADER_terrain_splat_w2) blends four layers off the mesher's vertex colours;
// this one blends TWELVE, off three control pictures `tools/earth_fetch.py` made
// from the open map data — WorldCover's classes, OpenStreetMap's roads, rock,
// scree and water, the slope — and that EarthField hands to the material
// (SCRIPT_earth_dress.gd). So the ground is painted at the data's own 4 m,
// whatever LOD the chunk under it is at, and the vertex colours are not read.
//
// THE LAYERS, in the order the control pictures and the two texture arrays hold
// them (tools/earth_pack.py LAYERS, EarthField L_*):
//
//    control_a  grass  forest  rock   scree
//    control_b  sand   soil    snow   mud
//    control_c  paving dry     moss   bed (under the water)
//
// Each is a CC0 photo-scanned material at 2048 px: colour and height in one
// array (`albedo_height`), the normal, roughness and occlusion in the other
// (`normal_rough_ao`). Two samples a layer.
//
// WHAT IS DONE WITH THEM:
//
//   * Only the layers with any weight are sampled (a branch per layer), so most
//     pixels pay for one to three.
//   * HEIGHT BLENDING: where two layers meet, the taller texels of each win, so
//     grass gives way to scree between the stones rather than fading through it.
//   * ON STEEP GROUND the layers are projected from the side as well as from
//     above, blended by the normal (biplanar), so a cliff is not a smear.
//   * TILING is broken by a second sample at a quarter of the frequency further
//     off, and by a low macro variation in brightness.
//   * THE LIGHT is the island's own (SHADERINC_island_light: the sky's ambient,
//     the sun, the rim), unbanded, on the normal-mapped normal, with the
//     occlusion on the ambient and a GGX highlight from the roughness.
//   * Then the island's fog, the golf wall's drain and the thermal sight, as
//     every island surface does.

// ---------------------------------------------------------------- the region
group_uniforms region;
uniform sampler2D control_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D control_b : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D control_c : hint_default_black, filter_linear, repeat_disable;
// world XZ of the control grid's first sample, its spacing and its size
uniform vec2 region_origin = vec2(-1500.0, -1500.0);
uniform float control_texel = 4.0;
uniform float control_n = 751.0;

// ---------------------------------------------------------------- the layers
group_uniforms layers;
uniform sampler2DArray albedo_height : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_rough_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// metres each layer's texture covers on the ground: tools/earth_pack.py's
// LAYERS, which writes the same numbers to textures/layers.json (constants,
// since a uniform array takes no defaults; `texture_scale` scales them all)
const float LAYER_METRES[12] = float[](3.0, 3.5, 8.0, 4.0, 4.0, 3.5, 5.0, 3.5, 4.0, 3.5, 4.0, 2.5);
uniform float texture_scale : hint_range(0.25, 4.0) = 1.0;
// three of the scans moved to sit together: the turf duller than the
// ambientCG meadow, the forest floor darker, the rock (a dark slate) lighter,
// nearer the limestone of the Alps
uniform vec3 grass_tint : source_color = vec3(0.66, 0.72, 0.52);
uniform vec3 forest_tint : source_color = vec3(0.8, 0.8, 0.72);
uniform vec3 rock_tint = vec3(1.55, 1.52, 1.48);
uniform float height_blend : hint_range(0.0, 1.0) = 0.35;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
// where the second, quarter-frequency sample takes over, metres from the eye
uniform float far_start = 25.0;
uniform float far_end = 90.0;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.22;
uniform float macro_scale = 70.0;
// how steep (1 - n.y) the ground is before it is projected from the side too
uniform float side_from : hint_range(0.0, 1.0) = 0.22;
uniform float side_full : hint_range(0.0, 1.0) = 0.5;
// steep ground the data called something else shows its rock anyway
uniform float steep_rock_lo : hint_range(0.0, 1.0) = 0.42;
uniform float steep_rock_hi : hint_range(0.0, 1.0) = 0.62;

// ---------------------------------------------------------------- the light
group_uniforms island_light;
uniform float sun_bands : hint_range(0.0, 12.0) = 0.0;
uniform float sun_wrap : hint_range(0.0, 1.0) = 0.12;
uniform float rim_power : hint_range(0.5, 8.0) = 4.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.12;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;
uniform float specular : hint_range(0.0, 2.0) = 0.5;
uniform float exposure : hint_range(0.2, 3.0) = 0.85;

group_uniforms void_fog;
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.62, 0.72, 0.84);
uniform float fog_top = -170.0;
uniform float fog_bottom = -320.0;
uniform float fog_curve : hint_range(0.25, 6.0) = 2.2;
uniform float fog_opacity_gain : hint_range(1.0, 6.0) = 1.6;
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 1800.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0004;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

global uniform vec4 tod_haze_tint;
// THE WEATHER'S FOG (EnviroSky): the density times this, the start times
// that; both 1 wherever no EnviroSky is.
global uniform float tod_fog_density;
global uniform float tod_fog_near;


group_uniforms;


float earth_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float earth_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = earth_hash(i);
	float b = earth_hash(i + vec2(1.0, 0.0));
	float c = earth_hash(i + vec2(0.0, 1.0));
	float d = earth_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One layer at one projection: colour+height and normal+rough+ao, near and far
// blended. `uv` is in tiles.
void earth_tap(int layer, vec2 uv, float far_t, out vec4 ah, out vec4 nra) {
	vec3 c = vec3(uv, float(layer));
	ah = texture(albedo_height, c);
	nra = texture(normal_rough_ao, c);
	if (far_t > 0.0) {
		// rotated a little as well as scaled, so the two tilings never line up
		vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.27;
		vec3 c2 = vec3(uv2, float(layer));
		ah = mix(ah, texture(albedo_height, c2), far_t * 0.6);
		nra = mix(nra, texture(normal_rough_ao, c2), far_t * 0.6);
	}
}

// The layer on the ground at `p`, projected from above and, where it is steep,
// from the side: its colour (rgb) and height (a), and its normal as a
// world-space offset from the surface's own, roughness and occlusion.
void earth_layer(int layer, vec3 p, vec3 n, float side_t, float far_t,
		out vec4 ah, out vec3 dn, out vec2 ra) {
	float s = 1.0 / max(LAYER_METRES[layer] * texture_scale, 0.1);
	vec4 a0;
	vec4 m0;
	earth_tap(layer, p.xz * s, far_t, a0, m0);
	vec2 t0 = m0.xy * 2.0 - 1.0;
	// the top projection's tangent space: +u east, the picture's up north
	vec3 d0 = vec3(t0.x, 0.0, -t0.y);
	ah = a0;
	dn = d0;
	ra = m0.zw;
	if (side_t > 0.0) {
		vec4 a1;
		vec4 m1;
		vec3 d1;
		if (abs(n.x) > abs(n.z)) {
			earth_tap(layer, vec2(p.z * sign(n.x), -p.y) * s, far_t, a1, m1);
			vec2 t1 = m1.xy * 2.0 - 1.0;
			d1 = vec3(0.0, t1.y, t1.x * sign(n.x));
		} else {
			earth_tap(layer, vec2(-p.x * sign(n.z), -p.y) * s, far_t, a1, m1);
			vec2 t1 = m1.xy * 2.0 - 1.0;
			d1 = vec3(-t1.x * sign(n.z), t1.y, 0.0);
		}
		ah = mix(a0, a1, side_t);
		dn = mix(d0, d1, side_t);
		ra = mix(m0.zw, m1.zw, side_t);
	}
	if (layer == 0) {
		ah.rgb *= grass_tint;
	} else if (layer == 1) {
		ah.rgb *= forest_tint;
	} else if (layer == 2) {
		ah.rgb *= rock_tint;
	}
}


void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float dist = length(VERTEX);

	vec2 cuv = ((world_pos.xz - region_origin) / control_texel + 0.5) / control_n;
	vec4 ca = texture(control_a, cuv);
	vec4 cb = texture(control_b, cuv);
	vec4 cc = texture(control_c, cuv);
	float w[12] = {ca.r, ca.g, ca.b, ca.a, cb.r, cb.g, cb.b, cb.a, cc.r, cc.g, cc.b, cc.a};

	// steep ground shows its rock whatever the data called it, but not under
	// the snow or the water, and not where it is paved
	float slope = clamp(1.0 - world_normal.y, 0.0, 1.0);
	float steep = smoothstep(steep_rock_lo, steep_rock_hi, slope)
			* (1.0 - w[6] - w[11] - w[8]);
	steep = clamp(steep, 0.0, 1.0);
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		w[i] *= 1.0 - steep;
		total += w[i];
	}
	w[2] += steep;
	total += steep;
	for (int i = 0; i < 12; i++) {
		w[i] /= max(total, 1e-4);
	}

	float side_t = smoothstep(side_from, side_full, slope);
	float far_t = smoothstep(far_start, far_end, dist);

	// every layer worth a sample, its height-blend weight from its weight
	// and its own texels' height
	vec3 col = vec3(0.0);
	vec3 dn = vec3(0.0);
	vec2 ra = vec2(0.0);
	float wsum = 0.0;
	float best = -1.0;
	vec4 ahs[12];
	vec3 dns[12];
	vec2 ras[12];
	for (int i = 0; i < 12; i++) {
		if (w[i] > 0.015) {
			earth_layer(i, world_pos, world_normal, side_t, far_t, ahs[i], dns[i], ras[i]);
			best = max(best, w[i] + ahs[i].a * height_blend);
		}
	}
	float depth = 0.12;
	for (int i = 0; i < 12; i++) {
		if (w[i] > 0.015) {
			float b = max(w[i] + ahs[i].a * height_blend - (best - depth), 0.0);
			col += ahs[i].rgb * b;
			dn += dns[i] * b;
			ra += ras[i] * b;
			wsum += b;
		}
	}
	col /= max(wsum, 1e-4);
	dn /= max(wsum, 1e-4);
	ra /= max(wsum, 1e-4);
	if (wsum <= 0.0) {
		col = vec3(0.3);
		ra = vec2(0.9, 1.0);
	}

	// low, broad variation in brightness and hue, the way a real slope is
	// never one colour
	float mac = earth_vnoise(world_pos.xz / macro_scale) * 0.65
			+ earth_vnoise(world_pos.xz / (macro_scale * 0.31) + 17.0) * 0.35;
	col *= 1.0 + (mac - 0.5) * 2.0 * macro_strength;

	vec3 n = normalize(world_normal + dn * normal_strength);
	float rough = clamp(ra.x, 0.04, 1.0);
	float ao = mix(1.0, ra.y, ao_strength);

	vec3 lit = island_light(n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);
	// the occlusion darkens what the sky lights, most of all
	vec3 amb = island_ambient(n);
	lit -= amb * (1.0 - ao);
	vec3 albedo = col * lit * exposure;

	// the sun's highlight, GGX, off the roughness the scan carries
	float ndl = max(dot(n, tod_sun_dir), 0.0);
	if (specular > 0.0 && ndl > 0.0) {
		vec3 h = normalize(tod_sun_dir + world_v);
		float a = rough * rough;
		float a2 = a * a;
		float ndh = max(dot(n, h), 0.0);
		float dd = ndh * ndh * (a2 - 1.0) + 1.0;
		float D = a2 / (3.14159 * dd * dd);
		float F = 0.04 + 0.96 * pow(1.0 - max(dot(h, world_v), 0.0), 5.0);
		albedo += tod_sun_color.rgb * (D * F * ndl * 0.25 * specular);
	}

	if (fog_enabled) {
		float t = clamp((fog_top - world_pos.y) / max(fog_top - fog_bottom, 1e-3), 0.0, 1.0);
		float depth_t = clamp(pow(t, 1.0 / max(fog_curve, 0.001)) * fog_opacity_gain, 0.0, 1.0);
		float d = max(dist - fog_distance_start * tod_fog_near, 0.0) * fog_distance_density * tod_fog_density;
		float dist_t = 1.0 - exp(-pow(d, fog_distance_power));
		float fog = 1.0 - (1.0 - depth_t) * (1.0 - dist_t);
		albedo = mix(albedo, fog_color * tod_haze_tint.rgb, fog);
	}

	albedo = golf_wall_drain(albedo, world_pos.xz, SCREEN_UV, TIME);

	ALBEDO = albedo;
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_cold(ALBEDO, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
