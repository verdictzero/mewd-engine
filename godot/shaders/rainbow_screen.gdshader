// MEWD — the potato cannon's little screen (weapon3d.gd, "rainbow"): its
// own picture under bands of every colour rolling up it, brighter as the
// hopper fills (`charge`, 0..1) — lit by nothing but itself.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D map : source_color, filter_nearest_mipmap;
uniform bool has_map = false;
uniform float charge = 1.0;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec3 pic = has_map ? texture(map, UV).rgb : vec3(0.2);
	vec3 band = hue(fract(UV.y * 1.5 - TIME * 0.6 + UV.x * 0.3));
	float scan = 0.85 + 0.15 * step(0.5, fract(UV.y * 90.0));
	ALBEDO = mix(pic, band, 0.55) * (0.5 + 0.7 * charge) * scan;
}
