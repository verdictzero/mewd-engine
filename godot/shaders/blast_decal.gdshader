// MEWD — THE BIG MARKS, at the user's request ("more extravagant,
// interesting, epic decals for rocket explosions, potato explosions, and
// a whole different electrically themed damage type for the arc gun").
// One quad laid on the surface, as the sears are (sear_decal.gdshader,
// whose depth test, light and noise this shares); INSTANCE_CUSTOM:
//   x  the kind:
//      10 BLAST   where a rocket went off: a pitted crater with a molten
//                 rim, a SHOCKWAVE ring racing out in the first half
//                 second, long soot rays, hot shrapnel pocks, embers
//      11 STREAK  the same blast on a wall beside it: a soot fan thrown
//                 along +x (away from the blast), pocked with shrapnel
//      12 NUKE    where a potato went off: a crater of fused RAINBOW
//                 GLASS, its iridescence cycling for ever, glints that
//                 twinkle, rainbow petals, a white flash ring
//      13 SHOCK   where the arc maw struck: a LICHTENBERG figure, the
//                 branching burn lightning leaves, crackling blue-white
//                 for a second or two and then char with a ghost of
//                 blue in it that fades
//   y  the mark's slot in the bake atlas, plus a seed for the shape in
//      its fraction
//   z  when it was laid, in seconds
//   w  the light of the surface, plus two under the sky
// Premultiplied: the paint at its alpha, the glow added on top.
//
// THE PICTURE IS BAKED (at the user's request: "the more rocket impact
// decals in view, the lower the FPS"): the noise, the cracks, the rays,
// the shrapnel — all of it was drawn again every frame for every pixel
// of every crater's box, with no depth test to skip any of it. Now
// blast_bake.gdshader draws a mark's picture ONCE into a tile of
// Decals' atlas when it is laid (two 32 x 32 layers, A and B, side by
// side), and this shader samples the tile: two fetches a pixel, and what
// is left to do here is what moves — the heat dying, the shockwave, the
// embers' flicker, the rainbow turning, the glints, the crackle.
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, blend_premul_alpha, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float now = 0.0;
// the bake atlas (Decals.bake_vp): ATLAS_ACROSS tiles a row, each a tile
// of two 32 x 32 layers side by side — fetched nearest, which is the LOW
// RES the marks have always had (32 squares across, each one colour)
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float atlas_across = 16.0;
uniform float atlas_down = 10.0;
// (no bake for these: always projected)
const float bake_part = -1.0;
#include "res://godot/shaders/decal_project.gdshaderinc"
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;
	DECAL_VERTEX
}

// THE HASHES HAVE NO SINE IN THEM, which the web build's do: the
// sin(big) * 43758 hash is only as good as the GPU's sin a few thousand
// radians out, and a software rasterizer's is not — the noise came out
// smeared along the rows, and the sear in bars. Dave Hoskins's
// fract-and-multiply hash is the same idea on arithmetic every GPU does
// exactly.

// the hash and the noise the embers' flicker and the glints still need
float dh1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float dnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dh1(i), dh1(i + vec2(1.0, 0.0)), u.x), mix(dh1(i + vec2(0.0, 1.0)), dh1(i + vec2(1.0, 1.0)), u.x), u.y);
}
// the fire's own ramp, dull red to yellow-white
vec3 hot_ramp(float h) {
	return h < 0.5 ? mix(vec3(0.55, 0.03, 0.0), vec3(1.0, 0.36, 0.05), h * 2.0)
	               : mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.62), (h - 0.5) * 2.0);
}
// a rainbow, round the wheel (the potato's colours)
vec3 rainbow(float h) {
	return 0.5 + 0.5 * cos(6.2831853 * (h + vec3(0.0, 0.33, 0.67)));
}
// the electric ramp: violet at the dimmest, blue, then white-hot
vec3 volt_ramp(float h) {
	return h < 0.5 ? mix(vec3(0.25, 0.10, 0.85), vec3(0.25, 0.65, 1.0), h * 2.0)
	               : mix(vec3(0.25, 0.65, 1.0), vec3(0.92, 0.97, 1.0), (h - 0.5) * 2.0);
}

void fragment() {
	// on the surface inside its box, or nothing (decal_project.gdshaderinc)
	DECAL_FRAGMENT
	vec2 p = vec2(duv.x * 2.0 - 1.0, 1.0 - duv.y * 2.0);
	float r = length(p);
	float kind = cd.x;
	float slot = floor(cd.y);
	float seed = fract(cd.y);
	float age = max(0.0, now - cd.z);
	float sky = step(1.5, cd.w);
	float lit = world_band(cd.w - sky * 2.0, depth, sky);
	// the mark's tile: layer A in its left half, B in its right
	vec2 tile = vec2(mod(slot, atlas_across), floor(slot / atlas_across));
	vec2 tuv = (tile + vec2(duv.x * 0.5, duv.y)) / vec2(atlas_across, atlas_down);
	vec4 A = texture(atlas, tuv);
	vec4 B = texture(atlas, tuv + vec2(0.5 / atlas_across, 0.0));
	vec3 col = vec3(0.0);
	float a = 0.0;
	vec3 glow = vec3(0.0);

	if (kind < 10.5) {
		// ---- THE BLAST: the crater's heat dying, its shockwave, its embers
		float core = exp(-age / 0.7);
		float heat = exp(-age / 6.0);
		float ember = exp(-age / 16.0);
		col = world_air(A.rgb * lit * light_color.rgb, depth);
		a = A.a;
		float wave_r = 0.18 + age * 2.2;
		float wave = exp(-pow((r - wave_r) / 0.05, 2.0)) * exp(-age / 0.22) * step(r, 1.0);
		float flick = 0.7 + 0.3 * dnoise(p * 11.0 + vec2(now * 3.1, -now * 2.3));
		glow = vec3(1.0, 0.95, 0.8) * B.r * core * 3.0
			+ hot_ramp(clamp(0.4 + 0.6 * heat, 0.0, 1.0)) * B.g * heat * 2.8
			+ hot_ramp(clamp(heat, 0.0, 1.0)) * B.r * heat
			+ hot_ramp(clamp(ember * 0.85, 0.0, 1.0)) * B.b * ember * flick * 1.8
			+ hot_ramp(0.7) * B.a * exp(-age / 3.0) * 2.2
			+ vec3(1.0, 0.85, 0.55) * wave * 3.5;
	} else if (kind < 11.5) {
		// ---- THE BLAST ON A WALL BESIDE IT: the soot's heat dying
		float heat = exp(-age / 3.5);
		col = world_air(A.rgb * lit * light_color.rgb, depth);
		a = A.a;
		glow = hot_ramp(clamp(heat, 0.0, 1.0)) * B.r * 1.7 * heat;
	} else if (kind < 12.5) {
		// ---- THE POTATO'S NUKE: the rainbow turning, the glints twinkling
		float flash = exp(-age / 0.6);
		float heat = exp(-age / 9.0);
		float glass = A.g;
		float petal = A.b;
		float ring = A.a;
		float gn = B.r;
		float hue = A.r - now * 0.12;
		vec3 film = rainbow(hue);
		vec3 petal_c = rainbow(B.b + now * 0.05);
		vec2 cell = floor(p * 46.0);
		float tw = dh1(cell + floor(now * 7.0 + dh1(cell) * 9.0));
		float glint = step(0.975, tw) * glass;
		vec3 glass_c = mix(vec3(0.03, 0.02, 0.05), film * 0.55, 0.75) * (0.7 + 0.5 * gn);
		col = mix(vec3(0.05, 0.04, 0.05), glass_c, glass);
		col = mix(col, petal_c * 0.5, petal * 0.8);
		col = mix(col, vec3(0.75, 0.72, 0.68), ring * 0.7);
		a = max(glass, max(petal * 0.85, max(ring * 0.8, B.g)));
		col = world_air(col * lit * light_color.rgb, depth);
		float breathe = 0.55 + 0.45 * sin(now * 1.7 + seed * 6.0);
		glow = vec3(1.0) * glass * flash * 3.2
			+ rainbow(hue + 0.15) * glass * (0.25 + 1.6 * heat) * (0.6 + 0.4 * breathe)
			+ petal_c * petal * (0.12 + 1.2 * heat)
			+ vec3(1.0, 0.98, 0.9) * glint * 2.5
			+ vec3(1.0, 0.95, 0.85) * ring * flash * 2.0;
	} else {
		// ---- THE ARC MAW'S FIGURE: crackling, then a ghost of blue
		float s0 = seed * 11.0;
		float ang = atan(p.y, p.x);
		float tree = B.r;
		float hot = B.g * 2.4;
		float spot = B.b;
		float halo = B.a;
		float live = exp(-age / 0.45);
		float hum = exp(-age / 5.0);
		float tick = floor(now * 24.0);
		float flicker = 0.35 + 0.65 * step(0.4, dh1(vec2(tick, s0)));
		float crawl = step(0.93, dh1(vec2(floor(ang * 4.0 + s0), tick * 0.37 + s0))) * hum;
		float ghost = exp(-age / 20.0) * 0.35;
		col = world_air(A.rgb * lit * light_color.rgb, depth);
		a = A.a;
		glow = volt_ramp(clamp(0.45 + 0.4 * live, 0.0, 1.0)) * hot * (live * 1.9 * flicker + crawl * 1.4 + hum * 0.35)
			+ volt_ramp(0.32) * tree * ghost * (0.6 + 0.4 * flicker)
			+ volt_ramp(0.75) * spot * (live * 2.2 + hum * 0.5)
			+ volt_ramp(0.4) * halo * live * 0.8;
	}
	// never a hard square: everything fades out before the quad's edge
	float edge = 1.0 - smoothstep(0.84, 1.0, max(abs(p.x), abs(p.y)));
	a *= edge;
	glow *= edge;
	if (a < 0.004 && dot(glow, vec3(1.0)) < 0.004) discard;
	ALBEDO = (col * a + glow) * dfade;
	ALPHA = a * dfade;
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, lit, depth, wp, 0.0)) * a + thermal_out(thermal_glow(glow));
}
