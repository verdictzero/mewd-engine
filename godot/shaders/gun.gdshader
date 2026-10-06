// MEWD — the gun in your hands (js/weapon3d.js GUN_FRAG, in spirit).
//
// No world lighting reaches the gun: a held object is lit by whatever
// is nearest, and what is nearest is its own flame. So: its texture, a
// fixed key light from over the shoulder so the metal has a shape, the
// room's own light on it (`dim`, the sector the player stands in), and
// a warm glow from the muzzle while it fires, tinted per gun. The
// minigun's barrels glow with HEAT along their run. And METAL (a gun in
// its own colours: the potato cannon's chrome and gold) shines in a
// made-up sky — a gradient looked up by the reflected view, and a glint
// off the fixed key — so it reads as metal with no light in the world.
//
// AND A LIGHT MATCAP over all of it, at the user's request ("add a 'light
// matcap' to all weapons so they look pseudo lit"): the colour looked up
// by the surface's facing on the screen, as a sculptor's matcap ball is
// — a soft warm key up and to the left with a tight highlight in it, a
// cool fill coming round from below, a bright rim — drawn here as sums
// of falloffs rather than read off a texture. `matcap` how much of it.
//
// NO BLACK SQUARES, at the user's request ("weird weapon artifacting on
// Qualcomm GPU"): on an Adreno a normal that came out of the vertex
// stage zero or broken made a NaN here, and a NaN pixel came out of the
// filter as a black block. The normal is normalized safely (a dead one
// faces the eye) and what is written is scrubbed of NaN and infinity.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D map : filter_nearest_mipmap, repeat_enable;
uniform bool has_map = true;
uniform vec4 base = vec4(0.6, 0.6, 0.6, 1.0);
uniform float dim = 1.0;
uniform float glow = 0.0;
uniform vec3 tint = vec3(1.0);
uniform float heat = 0.0;
uniform bool heats = false;
uniform float metal = 0.0;
uniform float matcap = 0.85;

varying vec3 n_view;

vec3 safe_n(vec3 n) {
	float l = dot(n, n);
	if (!(l > 1e-8) || isinf(l)) return vec3(0.0, 0.0, 1.0);
	return n * inversesqrt(l);
}

// the matcap ball, by the view-space normal: light (x) and the highlight
// in it apart, so the highlight can sit on top of the paint
vec4 cap(vec3 n) {
	vec2 m = n.xy;
	vec2 dk = m - vec2(-0.42, 0.52);
	float key = exp(-dot(dk, dk) * 2.2);
	vec2 ds = m - vec2(-0.36, 0.48);
	float spec = exp(-dot(ds, ds) * 38.0);
	float fill = smoothstep(-1.0, 0.2, -m.y) * smoothstep(-0.6, 1.0, m.x);
	float rim = smoothstep(0.62, 0.98, length(m));
	vec3 l = vec3(0.26, 0.26, 0.29)
		+ vec3(1.00, 0.95, 0.86) * key * 0.95
		+ vec3(0.36, 0.46, 0.62) * fill * 0.45
		+ vec3(0.80, 0.86, 1.00) * rim * 0.55;
	return vec4(l, spec);
}
varying float reach;

void vertex() {
	n_view = safe_n((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// how far forward along the view this part of the gun is: the glow
	// is the muzzle's, and it lights the front of the gun and not the grip
	reach = clamp(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z / 3.5, 0.0, 1.0);
}

void fragment() {
	vec4 c = has_map ? texture(map, UV) * base : base;
	if (c.a < 0.5) discard;
	vec3 key = normalize(vec3(-0.45, 0.7, 0.55));
	vec3 nv = safe_n(n_view);
	float l = 0.38 + 0.62 * max(dot(nv, key), 0.0);
	vec3 col = c.rgb * l * (0.35 + 0.65 * dim);
	if (matcap > 0.0) {
		vec4 mc = cap(nv);
		vec3 lit = (c.rgb * mc.rgb * 1.15 + vec3(mc.a * 0.55)) * (0.35 + 0.65 * dim);
		col = mix(col, lit, matcap);
	}
	if (metal > 0.0) {
		vec3 r = reflect(safe_n(VERTEX), nv);
		vec3 sky = mix(vec3(0.16, 0.14, 0.12), vec3(0.95, 0.93, 0.88), smoothstep(-0.35, 0.45, r.y));
		float glint = pow(max(dot(r, key), 0.0), 24.0);
		vec3 shine = c.rgb * sky * 1.25 + vec3(glint * 0.7);
		col = mix(col, shine * (0.45 + 0.55 * dim), metal * 0.75);
	}
	col += c.rgb * vec3(1.0, 0.55, 0.2) * tint * glow * 0.45 * reach * reach;
	if (heats) col += vec3(1.0, 0.35, 0.05) * heat * heat * 0.8;
	if (any(isnan(col)) || any(isinf(col))) col = c.rgb * 0.5;
	ALBEDO = clamp(col, vec3(0.0), vec3(8.0));
}
