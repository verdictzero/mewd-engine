// MEWD — the potato cannon's hopper glass (weapon3d "glass"): slightly
// rough, refractive. What it bends is what is behind it in the gun's own
// world — the potatoes — through a normal crinkled by a little noise and
// a few taps spread for the roughness; a fresnel rim, a faint green-grey
// body and a soft highlight. Where nothing of the gun is behind it the
// glass is a thin tint over the room (the room is drawn in another buffer
// and cannot be bent from here).
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

uniform sampler2D behind : hint_screen_texture, filter_nearest;
uniform float strength = 0.012;
uniform float rough = 0.004;
uniform vec3 body = vec3(0.78, 0.9, 0.86);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	// a slightly uneven pane: the normal nudged by two octaves of noise
	vec2 q = UV * 38.0;
	vec2 wob = vec2(noise(q) - 0.5, noise(q + 17.3) - 0.5) + 0.5 * vec2(noise(q * 2.7) - 0.5, noise(q * 2.7 + 9.1) - 0.5);
	vec2 off = (n.xy + wob * 0.9) * strength;
	vec4 acc = vec4(0.0);
	for (int k = 0; k < 5; k++) {
		float a = float(k) * 1.2566;
		vec2 o = off + vec2(cos(a), sin(a)) * rough * (k == 0 ? 0.0 : 1.0);
		acc += texture(behind, SCREEN_UV + o);
	}
	acc /= 5.0;
	float fres = pow(1.0 - clamp(abs(dot(n, normalize(VIEW))), 0.0, 1.0), 3.0);
	vec3 key = normalize(vec3(-0.45, 0.7, 0.55));
	float spec = pow(max(dot(reflect(-normalize(VIEW), n), key), 0.0), 40.0);
	vec3 col = mix(body * 0.62, acc.rgb * body * 0.92, acc.a) + vec3(0.9, 1.0, 0.95) * (fres * 0.45 + spec * 0.6);
	// over the gun: the bent picture, near opaque; over the room: a tint
	ALBEDO = col;
	// (and the pane itself always reads: frosted a little, a rim, a glint)
	float frost = 0.22 + 0.10 * noise(q * 0.6);
	ALPHA = clamp(mix(frost, 0.94, acc.a) + fres * 0.45 + spec * 0.5, 0.0, 1.0);
}
