// MEWD — blood on the world (js/decals.js, kinds SPATTER and POOL).
// A quad laid on a surface, turned about its normal so that +x is the
// way the blood was thrown. INSTANCE_CUSTOM carries
//   x  the kind: 5 a spatter, 6 a pool (the JS's KIND numbers)
//   y  a seed, for the shape
//   z  the time it landed, in seconds, for the pool to spread and dry
//   w  the light of the surface under it
// Drawn procedurally, then snapped with everything else by the post pass.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float now = 0.0;
varying vec4 cd;
varying float depth;

void vertex() {
	cd = INSTANCE_CUSTOM;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

float dh1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 dh2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float dnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dh1(i), dh1(i + vec2(1.0, 0.0)), u.x), mix(dh1(i + vec2(0.0, 1.0)), dh1(i + vec2(1.0, 1.0)), u.x), u.y);
}
float dfbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * dnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return s;
}
// a ragged edge: the radius a round thing reaches at this angle
float rag(float ang, float seed, float amt) {
	vec2 q = vec2(cos(ang), sin(ang)) * 2.2 + seed * 17.0;
	return 1.0 + amt * (dfbm(q) - 0.5) * 2.0;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float kind = cd.x;
	float seed = cd.y * 7.31;
	float age = now - cd.z;
	float lit = world_band(cd.w, depth, 0.0);
	vec3 col;
	float a;
	if (kind < 5.5) {
		// A SPATTER OF BLOOD, thrown along +x. A body of it where it hit,
		// a scatter of drops flung out ahead, the far ones smaller and
		// drawn out into streaks, and a wet dark red that dries browner
		// over half a minute.
		float R = rag(ang, seed, 0.35);
		float blob = 1.0 - smoothstep(0.30, 0.36, r / (R * (0.8 + 0.2 * dh1(vec2(seed, 3.0)))));
		float drops = 0.0;
		for (int i = 0; i < 14; i++) {
			vec2 h = dh2(vec2(float(i) * 1.37, seed * 9.1));
			float dist = 0.25 + 0.7 * h.x;
			float spread = (h.y - 0.5) * 1.3 * (1.0 - dist * 0.45);
			vec2 c = vec2(dist * 0.95 - 0.1, spread * dist);
			float sz = mix(0.11, 0.025, dist) * (0.6 + 0.8 * dh1(h * 5.0));
			vec2 dq = p - c;
			dq.x /= 1.0 + dist * 2.2;   // the far ones drawn out along the throw
			drops = max(drops, 1.0 - smoothstep(sz * 0.75, sz, length(dq)));
		}
		// and a few very fine flecks everywhere in front
		float fleck = step(0.965, dh1(floor(p * 30.0) + seed * 3.0)) * step(-0.1, p.x) * (1.0 - smoothstep(0.4, 1.0, r));
		float m = max(blob, max(drops, fleck));
		float dry = smoothstep(0.0, 30.0, age);
		vec3 wet = mix(vec3(0.26, 0.01, 0.012), vec3(0.13, 0.005, 0.008), dfbm(p * 8.0 + seed));
		col = mix(wet, vec3(0.10, 0.03, 0.022), dry);
		// the wet sheen, which is what makes it read as liquid
		float sheen = (1.0 - dry) * blob * smoothstep(0.55, 0.8, dfbm(p * 10.0 + seed * 7.0)) * 0.35;
		col = (col + sheen) * lit;
		a = m * 0.93;
	} else {
		// A POOL, under somebody: one smooth ragged puddle that spreads over
		// the first few seconds, darker in the middle where it is deep, with
		// a few drips round the edge, drying at its rim first
		float grow = mix(0.35, 1.0, smoothstep(0.0, 6.0, age));
		float R = rag(ang, seed, 0.3) * grow * 0.85;
		float rr = r / R;
		float body = 1.0 - smoothstep(0.92, 1.0, rr);
		float drips = 0.0;
		for (int i = 0; i < 6; i++) {
			vec2 h = dh2(vec2(float(i) * 3.1, seed * 4.7));
			float th = h.x * 6.2831853, dd = R * (1.05 + 0.25 * h.y);
			drips = max(drips, 1.0 - smoothstep(0.03, 0.05 + 0.03 * h.y, length(p - vec2(cos(th), sin(th)) * dd)));
		}
		float dry = smoothstep(10.0, 60.0, age) * smoothstep(0.4, 1.0, rr);
		vec3 c = mix(vec3(0.10, 0.004, 0.006), vec3(0.24, 0.012, 0.014), smoothstep(0.3, 1.0, rr));
		c = mix(c, vec3(0.09, 0.028, 0.022), dry);
		float sheen = (1.0 - dry) * smoothstep(0.6, 0.85, dfbm(p * 5.0 + seed * 2.0)) * (1.0 - min(rr, 1.0)) * 0.3;
		col = (c + sheen) * lit;
		a = max(body, drips) * 0.95;
	}
	if (a < 0.5) discard;
	ALBEDO = world_air(col, depth);
	// the thermal sight's feed (thermal.gdshaderinc)
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, lit, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0));
}
