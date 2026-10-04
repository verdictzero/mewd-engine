// MEWD — THE BIG MARKS, BAKED ONCE (at the user's request: "the more
// rocket impact decals in view, the lower the FPS" — and so it was: the
// crater's picture, four octaves of noise several times over and a
// 26-step shrapnel loop, was drawn again EVERY FRAME for EVERY PIXEL of
// every crater's box, with no depth test to skip any of it, so thirty
// craters in view ran the whole thing thirty times a pixel).
//
// Now the picture is drawn ONCE, here, into a tile of Decals' bake atlas
// when the mark is laid (a 2D viewport that is never cleared; Decals
// `_bake`), and blast_decal.gdshader samples the tile from then on. A
// tile is two 32 x 32 layers side by side — layer A on the left, B on the
// right — because a mark needs more than four numbers a pixel:
//   BLAST   A: the paint's colour and alpha
//           B: the glowing parts' masks — the crater (with the rays
//              folded in), the rim, the embers (the cracks with them),
//              the shrapnel flecks
//   STREAK  A: colour and alpha        B.r: the mask its heat glows by
//   NUKE    A: the iridescence's hue (0..1 of the wheel), the glass, the
//              petals, the flash ring
//           B: the glass's lumps, the soot, the petals' own hue
//   SHOCK   A: colour and alpha
//           B: the tree, the hot share of it, the fused spot, the halo
// What moves with time — the heat dying, the shockwave, the embers'
// flicker, the rainbow turning, the glints, the crackle — is cheap and
// stays in blast_decal.gdshader. 32 texels a side is the LOW RES the
// marks already had (its `texels`), so nothing is lost.
//
// The noise and the shapes are blast_decal.gdshader's as they were (the
// hashes with no sine in them, for the same reason).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform float kind = 10.0;
uniform float seed = 0.0;

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
float rag(float ang, float sd, float amt) {
	vec2 q = vec2(cos(ang), sin(ang)) * 2.2 + sd * 17.0;
	return 1.0 + amt * (dfbm(q) - 0.5) * 2.0;
}
float cracks(vec2 p, float sd, float n) {
	float ang = atan(p.y, p.x);
	float r = length(p);
	float k = ang * n / 6.2831853 + sd * 5.0;
	float cell = floor(k);
	float off = dh1(vec2(cell, sd)) - 0.5;
	float wob = (dnoise(vec2(r * 9.0, cell * 3.1 + sd)) - 0.5) * 0.9;
	float d = abs(fract(k) - 0.5 - off * 0.6 + wob * 0.25);
	float len = 0.55 + 0.45 * dh1(vec2(sd, cell + 7.0));
	float w = 0.09 * (1.0 - r / max(len, 0.01));
	return (r < len) ? 1.0 - smoothstep(0.0, max(w, 0.0001), d) : 0.0;
}
float branches(vec2 p, float n, float r0, float len, float w, float sd) {
	float r = length(p);
	if (r < r0) return 0.0;
	float ang = atan(p.y, p.x);
	float wan = (dfbm(vec2(r * 5.0, sd * 3.1)) - 0.5) * 1.6 + (dnoise(vec2(r * 19.0, sd * 7.7)) - 0.5) * 0.35;
	float k = ang * n / 6.2831853 + wan + sd * 4.0;
	float cell = floor(k);
	float reach = mix(r0 + 0.08, len, dh1(vec2(cell, sd * 13.0)));
	if (r > reach) return 0.0;
	float d = abs(fract(k) - 0.5) * 6.2831853 * r / n;
	float t = (r - r0) / max(reach - r0, 1e-3);
	float ww = w * (1.0 - 0.85 * t) + 0.002;
	return 1.0 - smoothstep(ww * 0.4, ww, d);
}

void fragment() {
	// the tile is two layers side by side: A left, B right, each 32 x 32
	// texels of the mark's own picture (the texel's middle, as `texels`
	// quantised it)
	float layer = step(0.5, UV.x);
	vec2 duv = vec2(fract(UV.x * 2.0), UV.y);
	duv = (floor(duv * 32.0) + 0.5) / 32.0;
	vec2 p = vec2(duv.x * 2.0 - 1.0, 1.0 - duv.y * 2.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec4 A = vec4(0.0);
	vec4 B = vec4(0.0);

	if (kind < 10.5) {
		// ---- THE BLAST ------------------------------------------------
		float R = rag(ang, seed, 0.18);
		float rr = r / R;
		float pits = dfbm(p * 14.0 + seed * 6.0);
		float crater = 1.0 - smoothstep(0.24, 0.30, rr);
		float rim = smoothstep(0.20, 0.28, rr) * (1.0 - smoothstep(0.30, 0.42, rr));
		float cr = cracks(p, seed, 15.0) * step(0.12, rr) * (1.0 - smoothstep(0.5, 0.75, rr));
		float n_ray = 26.0 + floor(dh1(vec2(seed, 2.9)) * 18.0);
		float kr = ang * n_ray / 6.2831853 + seed * 7.0;
		float cell_r = floor(kr);
		float len_r = 0.5 + 0.5 * dh1(vec2(cell_r, seed * 3.3));
		float ray = (1.0 - smoothstep(0.04, 0.22, abs(fract(kr) - 0.5) + r * 0.12))
			* (1.0 - smoothstep(len_r * 0.6, len_r, r)) * step(0.25, rr);
		float soot = (1.0 - smoothstep(0.38, 0.98, r * (0.85 + 0.3 * dfbm(p * 3.0 + seed))));
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
		vec3 col = mix(char_c, vec3(0.006, 0.005, 0.005), crater * 0.7 + pock * 0.8 + ray * 0.5);
		float a = max(crater, max(rim * 0.98, max(ray * 0.95, max(soot * 0.95, pock))));
		float embers = (1.0 - smoothstep(0.0, 0.06, abs(dfbm(p * 9.0 + seed * 5.0) - 0.5))) * soot * step(0.3, rr);
		A = vec4(col, a);
		// the crater's glow carries the pits' mottling and the rays' first
		// flash; the embers are the cracks and the mottled embers together
		B = vec4(min(1.0, crater * (0.6 + 0.6 * pits) + ray * 0.27), rim,
			min(1.0, cr + embers * 0.67), fleck);
	} else if (kind < 11.5) {
		// ---- THE BLAST ON A WALL BESIDE IT ------------------------------
		vec2 q = vec2(p.x + 1.0, p.y);
		float qa = atan(q.y, q.x);
		float qr = length(q);
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
		vec3 col = mix(vec3(0.012, 0.011, 0.01), vec3(0.06, 0.05, 0.04), mot);
		float a = clamp(max(fan * (0.7 + 0.3 * mot), max(ray * fan, pock)), 0.0, 0.97);
		A = vec4(col, a);
		B = vec4(min(1.0, (fan * (1.0 - smoothstep(0.0, 0.5, qr)) * 0.5 + pock * 1.2) / 1.7), 0.0, 0.0, 0.0);
	} else if (kind < 12.5) {
		// ---- THE POTATO'S NUKE ------------------------------------------
		float R = rag(ang, seed, 0.22);
		float rr = r / R;
		float gn = dfbm(p * 5.0 + seed * 4.0);
		float glass = 1.0 - smoothstep(0.40, 0.47, rr);
		// the hue with the time left out (blast_decal turns the wheel)
		float hue = fract(rr * 2.6 + gn * 0.9 + ang * 0.08 + seed);
		float n_pet = 10.0 + floor(dh1(vec2(seed, 8.1)) * 8.0);
		float kp = ang * n_pet / 6.2831853 + seed * 2.0;
		float cell_p = floor(kp);
		float len_p = 0.62 + 0.36 * dh1(vec2(cell_p, seed));
		float petal = (1.0 - smoothstep(0.08, 0.36, abs(fract(kp) - 0.5) + r * 0.18))
			* (1.0 - smoothstep(len_p * 0.7, len_p, r)) * step(0.36, rr);
		float ring = (1.0 - smoothstep(0.0, 0.035, abs(rr - 0.86))) * (0.6 + 0.4 * gn);
		float soot = (1.0 - smoothstep(0.45, 1.0, r)) * (0.35 + 0.4 * gn);
		A = vec4(hue, glass, petal, ring);
		B = vec4(gn, soot, fract(cell_p / n_pet), 0.0);
	} else {
		// ---- THE ARC MAW'S LICHTENBERG FIGURE ---------------------------
		float s0 = seed * 11.0;
		float n0 = 5.0 + floor(dh1(vec2(seed, 1.1)) * 4.0);
		float b1 = branches(p, n0, 0.0, 0.66, 0.085, s0);
		float b2 = branches(p, n0 * 2.3, 0.14, 0.88, 0.05, s0 + 3.7);
		float b3 = branches(p, n0 * 5.1, 0.30, 0.98, 0.028, s0 + 8.3);
		float fern = (1.0 - smoothstep(0.0, 0.07, abs(dfbm(p * 22.0 + s0) - 0.5))) * smoothstep(0.2, 0.5, r) * (1.0 - smoothstep(0.7, 1.0, r));
		float tree = max(b1, max(b2 * 0.9, b3 * 0.8));
		tree = max(tree, fern * 0.35 * max(b2, b3 * 0.7) + fern * 0.12);
		float spot = 1.0 - smoothstep(0.08, 0.16, r * (0.8 + 0.4 * dnoise(p * 9.0 + s0)));
		float halo = (1.0 - smoothstep(0.1, 0.55, r)) * 0.35;
		vec3 col = mix(vec3(0.06, 0.045, 0.04), vec3(0.015, 0.012, 0.02), tree);
		col = mix(col, vec3(0.03, 0.05, 0.09), spot);
		float halo_m = halo * (0.5 + 0.5 * dfbm(p * 6.0 + s0));
		float a = max(tree * 0.95, max(spot, halo_m));
		float hot = tree * (b1 * 1.0 + b2 * 0.7 + b3 * 0.5 + 0.2);
		A = vec4(col, a);
		B = vec4(tree, hot / 2.4, spot, halo);
	}
	COLOR = mix(A, B, layer);
}
