// MEWD — a gun shaded by a MATCAP picture (weapon3d `matcap`), at the
// user's request: the arc maw under assets/matcaps/pearl.png ("use this
// mat cap for the arc maw"). The light is the picture of a lit ball,
// looked up by which way the surface faces on the screen — its normal in
// view space, bent by the model's own normal map — and the model's own
// colour laid under it. No light in the gun's world is needed; the
// muzzle's kick and the room's light (`dim`) are kept as on every gun.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform sampler2D matcap_tex : source_color, filter_linear;
// how much of the model's own colour comes through the matcap's (0: the
// matcap alone, 1: multiplied by the colour in full), and the lift that
// puts the product back up to the matcap's own brightness
uniform float paint = 0.35;
uniform float lift = 1.8;
uniform float dim = 1.0;
uniform float glow = 0.0;
uniform vec3 tint = vec3(1.0);

void fragment() {
	// ITS OWN DEPTH (the very value the GPU would write: nothing looks
	// different): a draw that writes its depth is never culled by an
	// Adreno's LRZ, the 8x8 blocks of black on the gun (Lofi.gun_depth)
#ifndef MEWD_FIXED_DEPTH
	DEPTH = FRAGCOORD.z;
#endif
	vec3 n = NORMAL;
	if (has_normal) {
		vec3 t = texture(normal_map, UV).xyz * 2.0 - 1.0;
		n = normalize(TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z);
	}
	float l = dot(n, n);
	n = l > 1e-8 ? n * inversesqrt(l) : vec3(0.0, 0.0, 1.0);
	// (the matcap's ball, seen from straight on: x right, y up)
	vec2 m = n.xy * 0.49 + 0.5;
	vec3 cap = texture(matcap_tex, vec2(m.x, 1.0 - m.y)).rgb;
	vec3 base = texture(map, UV).rgb;
	vec3 col = cap * mix(vec3(1.0), base * lift, paint) * (0.45 + 0.55 * dim);
	col += base * vec3(1.0, 0.55, 0.2) * tint * glow * 0.3;
	if (any(isnan(col)) || any(isinf(col))) col = base * 0.5;
	ALBEDO = clamp(col, vec3(0.0), vec3(4.0));
}
