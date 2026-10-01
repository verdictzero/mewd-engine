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
//   y  a seed, for the shape
//   z  when it was laid, in seconds
//   w  the light of the surface, plus two under the sky
// Premultiplied: the paint at its alpha, the glow added on top.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float now = 0.0;
uniform bool gl_depth = false;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying vec4 cd;
varying float depth;

void vertex() {
	cd = INSTANCE_CUSTOM;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	depth = -mv.z;
	VERTEX = mv.xyz * 0.995;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// THE HASHES HAVE NO SINE IN THEM, which the web build's do: the
// sin(big) * 43758 hash is only as good as the GPU's sin a few thousand
// radians out, and a software rasterizer's is not — the noise came out
// smeared along the rows, and the sear in bars. Dave Hoskins's
// fract-and-multiply hash is the same idea on arithmetic every GPU does
// exactly.
float dh1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 dh2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
float dnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dh1(i), dh1(i + vec2(1.0, 0.0)), u.x), mix(dh1(i + vec2(0.0, 1.0)), dh1(i + vec2(1.0, 1.0)), u.x), u.y);
}
float dfbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * dnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return s;
}
// a ragged edge: the radius a round thing reaches at this angle
float rag(float ang, float seed, float amt) {
	vec2 q = vec2(cos(ang), sin(ang)) * 2.2 + seed * 17.0;
	return 1.0 + amt * (dfbm(q) - 0.5) * 2.0;
}
// cracks: thin dark lines running out from the centre
float cracks(vec2 p, float seed, float n) {
	float ang = atan(p.y, p.x);
	float r = length(p);
	float k = ang * n / 6.2831853 + seed * 5.0;
	float cell = floor(k);
	float off = dh1(vec2(cell, seed)) - 0.5;
	float wob = (dnoise(vec2(r * 9.0, cell * 3.1 + seed)) - 0.5) * 0.9;
	float d = abs(fract(k) - 0.5 - off * 0.6 + wob * 0.25);
	float len = 0.55 + 0.45 * dh1(vec2(seed, cell + 7.0));
	float w = 0.09 * (1.0 - r / max(len, 0.01));
	return (r < len) ? 1.0 - smoothstep(0.0, max(w, 0.0001), d) : 0.0;
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

// ONE GENERATION of a Lichtenberg tree: `n` branches round the centre,
// each wandering as it goes out, starting at `r0` and ending somewhere
// between r0 and `len`; how near p is to one, as a line `w` wide that
// thins to its tip
float branches(vec2 p, float n, float r0, float len, float w, float seed) {
	float r = length(p);
	if (r < r0) return 0.0;
	float ang = atan(p.y, p.x);
	float wan = (dfbm(vec2(r * 5.0, seed * 3.1)) - 0.5) * 1.6 + (dnoise(vec2(r * 19.0, seed * 7.7)) - 0.5) * 0.35;
	float k = ang * n / 6.2831853 + wan + seed * 4.0;
	float cell = floor(k);
	float reach = mix(r0 + 0.08, len, dh1(vec2(cell, seed * 13.0)));
	if (r > reach) return 0.0;
	float d = abs(fract(k) - 0.5) * 6.2831853 * r / n;
	float t = (r - r0) / max(reach - r0, 1e-3);
	float ww = w * (1.0 - 0.85 * t) + 0.002;
	return 1.0 - smoothstep(ww * 0.4, ww, d);
}

void fragment() {
	// on the surface under it, or nothing (see sear_decal.gdshader)
	float dz = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = gl_depth ? vec3(SCREEN_UV, dz) * 2.0 - 1.0 : vec3(SCREEN_UV * 2.0 - 1.0, dz);
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene = -vp.z / vp.w;
	if (abs(scene - depth) > 3.0 + depth * 0.02) discard;

	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float kind = cd.x;
	float seed = cd.y;
	float age = max(0.0, now - cd.z);
	float sky = step(1.5, cd.w);
	float lit = world_band(cd.w - sky * 2.0, depth, sky);
	vec3 col = vec3(0.0);
	float a = 0.0;
	vec3 glow = vec3(0.0);

	if (kind < 10.5) {
		// ---- THE BLAST ------------------------------------------------
		float core = exp(-age / 0.7);
		float heat = exp(-age / 6.0);
		float ember = exp(-age / 16.0);
		float R = rag(ang, seed, 0.18);
		float rr = r / R;
		// the crater: pitted, cracked, the rim thrown up and molten
		float pits = dfbm(p * 14.0 + seed * 6.0);
		float crater = 1.0 - smoothstep(0.24, 0.30, rr);
		float rim = smoothstep(0.20, 0.28, rr) * (1.0 - smoothstep(0.30, 0.42, rr));
		float cr = cracks(p, seed, 15.0) * step(0.12, rr) * (1.0 - smoothstep(0.5, 0.75, rr));
		// the rays: long thin soot spokes, many, uneven
		float n_ray = 26.0 + floor(dh1(vec2(seed, 2.9)) * 18.0);
		float kr = ang * n_ray / 6.2831853 + seed * 7.0;
		float cell_r = floor(kr);
		float len_r = 0.5 + 0.5 * dh1(vec2(cell_r, seed * 3.3));
		float ray = (1.0 - smoothstep(0.04, 0.22, abs(fract(kr) - 0.5) + r * 0.12))
			* (1.0 - smoothstep(len_r * 0.6, len_r, r)) * step(0.25, rr);
		// the soot, heaviest near the crater, with the fbm's mottling
		float soot = (1.0 - smoothstep(0.38, 0.98, r * (0.85 + 0.3 * dfbm(p * 3.0 + seed))));
		// THE SHRAPNEL: pocks flung out across the scorch, each a little
		// hole with a hot fleck in it for the first few seconds
		float pock = 0.0;
		float fleck = 0.0;
		for (int i = 0; i < 26; i++) {
			vec2 h = dh2(vec2(float(i) * 1.37, seed * 9.1));
			float th = h.x * 6.2831853;
			float dist = 0.32 + 0.62 * h.y;
			vec2 c = vec2(cos(th), sin(th)) * dist;
			float sz = mix(0.035, 0.014, h.y);
			float d = length(p - c);
			float hole = 1.0 - smoothstep(sz * 0.6, sz, d);
			pock = max(pock, hole);
			fleck = max(fleck, hole * step(0.45, dh1(h * 5.0)));
		}
		vec3 char_c = mix(vec3(0.012, 0.011, 0.01), vec3(0.07, 0.06, 0.05), pits);
		col = mix(char_c, vec3(0.006, 0.005, 0.005), crater * 0.7 + pock * 0.8 + ray * 0.5);
		a = max(crater, max(rim * 0.98, max(ray * 0.95, max(soot * 0.95, pock))));
		col = world_air(col * lit * light_color.rgb, depth);
		// THE SHOCKWAVE: a bright ring racing out from the crater in the
		// first half second, leaving the glow behind it
		float wave_r = 0.18 + age * 2.2;
		float wave = exp(-pow((r - wave_r) / 0.05, 2.0)) * exp(-age / 0.22) * step(r, 1.0);
		float flick = 0.7 + 0.3 * dnoise(p * 11.0 + vec2(now * 3.1, -now * 2.3));
		float embers = (1.0 - smoothstep(0.0, 0.06, abs(dfbm(p * 9.0 + seed * 5.0) - 0.5))) * soot * step(0.3, rr);
		glow = vec3(1.0, 0.95, 0.8) * crater * core * 3.0
			+ hot_ramp(clamp(0.4 + 0.6 * heat, 0.0, 1.0)) * rim * heat * 2.8
			+ hot_ramp(clamp(heat, 0.0, 1.0)) * crater * heat * (0.6 + 0.6 * pits)
			+ hot_ramp(clamp(ember * 0.85, 0.0, 1.0)) * cr * ember * flick * 1.8
			+ hot_ramp(0.7) * fleck * exp(-age / 3.0) * 2.2
			+ hot_ramp(clamp(ember, 0.0, 1.0)) * embers * ember * flick * 1.2
			+ vec3(1.0, 0.85, 0.55) * wave * 3.5
			+ hot_ramp(0.9) * ray * core * 0.8;
	} else if (kind < 11.5) {
		// ---- THE BLAST ON A WALL BESIDE IT: a fan of soot from the left
		// edge (where the blast was) out across the wall, pocked
		vec2 q = vec2(p.x + 1.0, p.y);
		float qa = atan(q.y, q.x);
		float qr = length(q);
		float heat = exp(-age / 3.5);
		float fan = (1.0 - smoothstep(0.2, 1.0, abs(qa) / 1.05)) * (1.0 - smoothstep(0.3, 1.8, qr)) * (0.7 + 0.5 * dfbm(p * 2.5 + seed * 2.0));
		float n_ray = 14.0 + floor(dh1(vec2(seed, 4.4)) * 10.0);
		float kr = qa * n_ray / 3.14159 + seed * 5.0;
		float len_r = 1.0 + 0.9 * dh1(vec2(floor(kr), seed * 2.0));
		float ray = (1.0 - smoothstep(0.05, 0.3, abs(fract(kr) - 0.5))) * (1.0 - smoothstep(len_r * 0.6, len_r, qr));
		float mot = dfbm(p * 4.0 + seed * 3.0);
		float pock = 0.0;
		for (int i = 0; i < 14; i++) {
			vec2 h = dh2(vec2(float(i) * 2.71, seed * 4.3));
			vec2 c = vec2(-0.6 + 1.5 * h.x, (h.y - 0.5) * 1.6 * (0.3 + h.x));
			pock = max(pock, 1.0 - smoothstep(0.012, 0.026, length(p - c)));
		}
		col = mix(vec3(0.012, 0.011, 0.01), vec3(0.06, 0.05, 0.04), mot);
		a = clamp(max(fan * (0.7 + 0.3 * mot), max(ray * fan, pock)), 0.0, 0.97);
		col = world_air(col * lit * light_color.rgb, depth);
		glow = hot_ramp(clamp(heat, 0.0, 1.0)) * (fan * (1.0 - smoothstep(0.0, 0.5, qr)) * 0.5 + pock * 1.2) * heat;
	} else if (kind < 12.5) {
		// ---- THE POTATO'S NUKE: fused RAINBOW GLASS ---------------------
		float flash = exp(-age / 0.6);
		float heat = exp(-age / 9.0);
		float R = rag(ang, seed, 0.22);
		float rr = r / R;
		float gn = dfbm(p * 5.0 + seed * 4.0);
		float glass = 1.0 - smoothstep(0.40, 0.47, rr);
		// THE IRIDESCENCE: thin-film bands round the centre, warped by the
		// glass's own lumps, sliding round the wheel for ever
		float hue = rr * 2.6 + gn * 0.9 + ang * 0.08 - now * 0.12 + seed;
		vec3 film = rainbow(hue);
		// the petals: rainbow streaks thrown out past the glass
		float n_pet = 10.0 + floor(dh1(vec2(seed, 8.1)) * 8.0);
		float kp = ang * n_pet / 6.2831853 + seed * 2.0;
		float cell_p = floor(kp);
		float len_p = 0.62 + 0.36 * dh1(vec2(cell_p, seed));
		float petal = (1.0 - smoothstep(0.08, 0.36, abs(fract(kp) - 0.5) + r * 0.18))
			* (1.0 - smoothstep(len_p * 0.7, len_p, r)) * step(0.36, rr);
		vec3 petal_c = rainbow(cell_p / n_pet + now * 0.05);
		// the white flash ring the fireball left at its edge
		float ring = (1.0 - smoothstep(0.0, 0.035, abs(rr - 0.86))) * (0.6 + 0.4 * gn);
		float soot = (1.0 - smoothstep(0.45, 1.0, r)) * (0.35 + 0.4 * gn);
		// glints in the glass, twinkling
		vec2 cell = floor(p * 46.0);
		float tw = dh1(cell + floor(now * 7.0 + dh1(cell) * 9.0));
		float glint = step(0.975, tw) * glass;
		vec3 glass_c = mix(vec3(0.03, 0.02, 0.05), film * 0.55, 0.75) * (0.7 + 0.5 * gn);
		col = mix(vec3(0.05, 0.04, 0.05), glass_c, glass);
		col = mix(col, petal_c * 0.5, petal * 0.8);
		col = mix(col, vec3(0.75, 0.72, 0.68), ring * 0.7);
		a = max(glass, max(petal * 0.85, max(ring * 0.8, soot)));
		col = world_air(col * lit * light_color.rgb, depth);
		float breathe = 0.55 + 0.45 * sin(now * 1.7 + seed * 6.0);
		glow = vec3(1.0) * glass * flash * 3.2
			+ rainbow(hue + 0.15) * glass * (0.25 + 1.6 * heat) * (0.6 + 0.4 * breathe)
			+ petal_c * petal * (0.12 + 1.2 * heat)
			+ vec3(1.0, 0.98, 0.9) * glint * 2.5
			+ vec3(1.0, 0.95, 0.85) * ring * flash * 2.0;
	} else {
		// ---- THE ARC MAW: A LICHTENBERG FIGURE --------------------------
		// three generations of branches, each splitting from the last and
		// thinner, and a fused spot where the bolt went in
		float s0 = seed * 11.0;
		float n0 = 5.0 + floor(dh1(vec2(seed, 1.1)) * 4.0);
		float b1 = branches(p, n0, 0.0, 0.66, 0.085, s0);
		float b2 = branches(p, n0 * 2.3, 0.14, 0.88, 0.05, s0 + 3.7);
		float b3 = branches(p, n0 * 5.1, 0.30, 0.98, 0.028, s0 + 8.3);
		// the finest: a fern of ridges near the branches
		float fern = (1.0 - smoothstep(0.0, 0.07, abs(dfbm(p * 22.0 + s0) - 0.5))) * smoothstep(0.2, 0.5, r) * (1.0 - smoothstep(0.7, 1.0, r));
		float tree = max(b1, max(b2 * 0.9, b3 * 0.8));
		tree = max(tree, fern * 0.35 * max(b2, b3 * 0.7) + fern * 0.12);
		float spot = 1.0 - smoothstep(0.08, 0.16, r * (0.8 + 0.4 * dnoise(p * 9.0 + s0)));
		float halo = (1.0 - smoothstep(0.1, 0.55, r)) * 0.35;
		// it CRACKLES: the whole figure flickers hard at first, then a
		// branch at a time lights again now and then as it dies
		float live = exp(-age / 0.45);
		float hum = exp(-age / 5.0);
		float tick = floor(now * 24.0);
		float flicker = 0.35 + 0.65 * step(0.4, dh1(vec2(tick, s0)));
		float crawl = step(0.93, dh1(vec2(floor(ang * 4.0 + s0), tick * 0.37 + s0))) * hum;
		float ghost = exp(-age / 20.0) * 0.35;
		col = mix(vec3(0.06, 0.045, 0.04), vec3(0.015, 0.012, 0.02), tree);
		col = mix(col, vec3(0.03, 0.05, 0.09), spot);
		a = max(tree * 0.95, max(spot, halo * (0.5 + 0.5 * dfbm(p * 6.0 + s0))));
		col = world_air(col * lit * light_color.rgb, depth);
		float hot = tree * (b1 * 1.0 + b2 * 0.7 + b3 * 0.5 + 0.2);
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
	ALBEDO = col * a + glow;
	ALPHA = a;
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, lit, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0)) * a + thermal_out(thermal_glow(glow));
}
