// MEWD — what lies on the world (js/decals.js): holes, heat, blood.
// Each decal is a quad laid on a surface; INSTANCE_CUSTOM carries
//   x  the kind: 0 a bullet hole, 1 a HOT one (the minigun's), 2 blood
//   y  a seed, for the shape
//   z  age in seconds, for the heat to cool
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

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float kind = cd.x;
	float seed = cd.y;
	float a = 0.0;
	vec3 col = vec3(0.0);
	float lit = world_band(cd.w, depth, 0.0);
	if (kind < 1.5) {
		// a black core with depth in it, soot round it, torn edge
		float ang = atan(p.y, p.x);
		float edge = 0.55 + 0.12 * sin(ang * 5.0 + seed * 20.0) + 0.08 * sin(ang * 11.0 + seed * 7.0);
		float core = 1.0 - smoothstep(0.18, 0.26, r);
		float soot = (1.0 - smoothstep(edge * 0.6, edge, r)) * 0.75;
		a = max(core, soot);
		col = mix(vec3(0.06, 0.05, 0.045) * lit, vec3(0.0), core);
		if (kind > 0.5) {
			// hot: the rim glows and cools over three seconds
			float age = now - cd.z;
			float glow = clamp(1.0 - age / 3.0, 0.0, 1.0);
			float ring = smoothstep(0.1, 0.25, r) * (1.0 - smoothstep(0.25, 0.5, r));
			col += vec3(1.0, 0.45, 0.08) * ring * glow * 1.6;
			a = max(a, ring * glow);
		}
	} else {
		// blood: a splash of blobs, dark red, with drops round it
		float blobs = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			vec2 c = vec2(hash(vec2(seed, fi)) - 0.5, hash(vec2(fi, seed)) - 0.5) * (fi == 0.0 ? 0.2 : 1.3);
			float rr = (fi == 0.0 ? 0.45 : 0.08 + 0.12 * hash(vec2(seed * 3.0, fi)));
			blobs = max(blobs, 1.0 - smoothstep(rr * 0.8, rr, length(p - c)));
		}
		a = blobs;
		col = vec3(0.32, 0.02, 0.02) * lit;
	}
	if (a < 0.5) discard;
	ALBEDO = world_air(col, depth);
	// the thermal sight's feed: how warm the mark is (a hot rim is)
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, lit, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0));
}
