// MEWD — what lies on the world (js/decals.js): holes, heat, blood.
// Each decal is a box projected onto the surface it stands on
// (decal_project.gdshaderinc); INSTANCE_CUSTOM carries
//   x  the kind: 0 a bullet hole, 1 a HOT one (the minigun's), 2 blood,
//      3 a SCORCH (what a hot spot leaves), 4 HEAT (a spot the flame is
//      on: the surface itself glowing)
//   y  a seed, for the shape
//   z  age in seconds, for the heat to cool — or, for HEAT, how hot 0..1
//   w  the light of the surface under it
// Drawn procedurally, then snapped with everything else by the post pass.
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float now = 0.0;
// LOW RES, at the user's request (the big marks; a bullet hole stays as
// it is): the mark's picture drawn in this many squares across, each one
// colour, as if it were a little texture laid with no filtering. 0 off.
uniform float texels = 12.0;
// THE BAKE (RealDecals): >= 0 draws the mark itself, lit at 1, with no
// air, no depth test and no discard, for a real decal's texture (the
// sears: 0 the scar, 1 its heat, 2 its embers) — opaque, its colour
// sRGB-encoded, or with bake_alpha its cover as grey: the Mobile
// renderer keeps two bits of alpha in a 3D target, so the cover travels
// as a colour and RealDecals puts the two together
uniform float bake_part = -1.0;
uniform bool bake_alpha = false;
vec3 bake_out(vec3 c, float a) {
	if (bake_alpha) return vec3(clamp(a, 0.0, 1.0));
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
#include "res://godot/shaders/decal_project.gdshaderinc"
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
	DECAL_VERTEX
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float dfbm(vec2 p) {
	return 0.55 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 3.7) + 0.15 * vnoise(p * 4.3 + 9.1);
}
// a ragged edge: the radius the blot reaches, round `ang`
float rag(float ang, float seed, float amt) {
	return 1.0 - amt * (0.6 * sin(ang * 3.0 + seed * 20.0) + 0.4 * sin(ang * 7.0 + seed * 9.0)) * 0.5 - amt * 0.3;
}
vec3 hot_ramp(float h) {
	return h < 0.5 ? mix(vec3(0.55, 0.03, 0.0), vec3(1.0, 0.36, 0.05), h * 2.0)
		: mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.62), (h - 0.5) * 2.0);
}

void fragment() {
	DECAL_FRAGMENT
	// (a scorch and a hot spot: kinds 3 and 4; a hole and blood untouched)
	if (texels > 0.0 && cd.x > 2.5) duv = (floor(duv * texels) + 0.5) / texels;
	// (blood, kind 2: in squares at half the picture's res)
	if (bake_part < 0.0 && cd.x > 1.5 && cd.x < 2.5) duv = half_res(duv);
	vec2 p = duv * 2.0 - 1.0;
	float r = length(p);
	float kind = cd.x;
	float seed = cd.y;
	float a = 0.0;
	float glow = 0.0;
	vec3 col = vec3(0.0);
	float lit = bake_part >= 0.0 ? 1.0 : world_band(cd.w, depth, 0.0);
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
	} else if (kind > 2.5 && kind < 3.5) {
		// A SCORCH: what a hot spot leaves. Soft and dark, mottled, and
		// thinning out to a ragged edge; the darkest part is the middle.
		float ang = atan(p.y, p.x);
		float R = rag(ang, seed, 0.22);
		float rr = r / R;
		float m = dfbm(p * 4.0 + seed * 13.0);
		a = (1.0 - smoothstep(0.25, 1.0, rr)) * (0.55 + 0.45 * m) * 0.95;
		col = mix(vec3(0.035, 0.03, 0.028), vec3(0.12, 0.09, 0.07), m * rr) * lit;
	} else if (kind > 3.5) {
		// HEAT: the surface itself glowing where the stream sits, banded
		// like the fire's own ramp and swimming, its own light
		float ang = atan(p.y, p.x);
		float strength = cd.z;
		float R = rag(ang + now * 0.3, seed, 0.2);
		float rr = r / R;
		float m = dfbm(p * 5.0 + vec2(now * 0.7, -now * 0.4) + seed * 5.0);
		float h = strength * (1.0 - smoothstep(0.1, 1.0, rr)) * (0.7 + 0.5 * m);
		h = floor(h * 8.0 + 0.5) / 8.0;
		a = clamp(h * 1.6, 0.0, 1.0);
		col = hot_ramp(clamp(h, 0.0, 1.0)) * (0.6 + 0.8 * h);
		glow = h;
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
	if (bake_part >= 0.0) {
		ALBEDO = bake_out(col, (kind > 2.5 && kind < 3.5) ? a : step(0.5, a));
		ALPHA = 1.0;
	} else {
		if (a < 0.5) discard;
		// (a scorch is soft; a hot spot is its own light and takes no air)
		ALPHA = ((kind > 2.5 && kind < 3.5) ? a : 1.0) * dfade;
		ALBEDO = glow > 0.0 ? col : world_air(col, depth);
		// the thermal sight's feed: how warm the mark is (a hot rim is, a hot spot more)
		// (a glowing scorch once hot: only people are hot now)
		if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, lit, depth, wp, 0.0));
	}
}
