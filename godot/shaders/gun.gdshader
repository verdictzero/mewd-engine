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
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D map : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool has_map = true;
uniform vec4 base : source_color = vec4(0.6, 0.6, 0.6, 1.0);
uniform float dim = 1.0;
uniform float glow = 0.0;
uniform vec3 tint = vec3(1.0);
uniform float heat = 0.0;
uniform bool heats = false;
uniform float metal = 0.0;

varying vec3 n_view;
varying float reach;

void vertex() {
	n_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// how far forward along the view this part of the gun is: the glow
	// is the muzzle's, and it lights the front of the gun and not the grip
	reach = clamp(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z / 3.5, 0.0, 1.0);
}

void fragment() {
	vec4 c = has_map ? texture(map, UV) * base : base;
	if (c.a < 0.5) discard;
	vec3 key = normalize(vec3(-0.45, 0.7, 0.55));
	float l = 0.38 + 0.62 * max(dot(normalize(n_view), key), 0.0);
	vec3 col = c.rgb * l * (0.35 + 0.65 * dim);
	if (metal > 0.0) {
		vec3 n = normalize(n_view);
		vec3 r = reflect(normalize(VERTEX), n);
		vec3 sky = mix(vec3(0.16, 0.14, 0.12), vec3(0.95, 0.93, 0.88), smoothstep(-0.35, 0.45, r.y));
		float glint = pow(max(dot(r, key), 0.0), 24.0);
		vec3 shine = c.rgb * sky * 1.25 + vec3(glint * 0.7);
		col = mix(col, shine * (0.45 + 0.55 * dim), metal * 0.75);
	}
	col += c.rgb * vec3(1.0, 0.55, 0.2) * tint * glow * 0.45 * reach * reach;
	if (heats) col += vec3(1.0, 0.35, 0.05) * heat * heat * 0.8;
	ALBEDO = col;
}
