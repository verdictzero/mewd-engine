// MEWD — the goop out of the fetus launcher's muzzle (weapon3d `goop`; at
// the user's request: "can there be a goop situation coming out of the
// end of the gun on fetus extrusion"): blobs in the gun's own world, one
// MultiMesh of balls each drawn out along the way it is going, coloured
// per blob (MultiMesh colours: slime, pink, blood). Wet: the gun's own key
// light on it, a hard highlight, a rim, and the room's light (`dim`) as
// the gun has it. It writes its own depth, as everything opaque in the
// gun's world does (gun.gdshader: an Adreno's LRZ).
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform float dim = 1.0;

varying vec3 n_view;
varying vec4 goo;

vec3 safe_n(vec3 n) {
	float l = dot(n, n);
	if (!(l > 1e-8) || isinf(l)) return vec3(0.0, 0.0, 1.0);
	return n * inversesqrt(l);
}

void vertex() {
	n_view = safe_n((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	goo = COLOR;
}

void fragment() {
#ifndef MEWD_FIXED_DEPTH
	DEPTH = FRAGCOORD.z;
#endif
	vec3 n = safe_n(n_view);
	vec3 key = normalize(vec3(-0.45, 0.7, 0.55));
	float l = 0.42 + 0.58 * max(dot(n, key), 0.0);
	float spec = pow(max(dot(n, normalize(key + vec3(0.0, 0.0, 1.0))), 0.0), 36.0);
	float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 3.0);
	vec3 col = goo.rgb * l * (0.4 + 0.6 * dim) + vec3(spec * 0.85 + rim * 0.18) * (0.5 + 0.5 * dim);
	if (any(isnan(col)) || any(isinf(col))) col = goo.rgb * 0.5;
	ALBEDO = clamp(col, vec3(0.0), vec3(4.0));
}
