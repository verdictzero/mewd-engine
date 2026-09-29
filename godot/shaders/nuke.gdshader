// MEWD — the potato's warhead (game/potatoes.gd): a fireball, a column,
// a cap and a ring of shock, each of them every colour at once and
// cycling — the rainbow boiling through it on a slow noise, white-hot at
// the core while it is young, and all of it fading as `fade` falls.
// Added, not painted over: the sky and the town show through the edges.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float fade = 1.0;
uniform float seed = 0.0;
uniform float heat = 1.0;
uniform float scroll = 1.0;

varying vec3 lp;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
// a hash with no sines in it (llvmpipe's sin is not the GPU's)
float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 q = lp * 2.4 + vec3(seed, -TIME * 1.7 * scroll, seed * 0.5);
	float n = noise(q) * 0.65 + noise(q * 2.3 + 7.0) * 0.35;
	float h = fract(TIME * 0.9 + n * 0.8 + lp.y * 0.35 + seed);
	vec3 c = hue(h);
	// the rim thins, the face towards you burns
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec3 col = mix(c, vec3(1.0, 0.97, 0.9), heat * face * face * 0.8);
	ALBEDO = col * (0.35 + 1.1 * n) * fade * (0.35 + 0.65 * face);
}
