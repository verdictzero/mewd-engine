// THE CLIFFS OF A REAL PLACE (at the user's request: "triplanar cliffs"): what
// a limestone wall in the Alps carries over its rock — strata, bands of
// lighter and darker beds lying near flat and bent by broad folds, and the dark
// streaks water leaves running down the face — as a tone on a colour already
// sampled. Shared by the ground's steep rock (SHADER_terrain_earth) and the cut
// face round the square (SHADER_cliff_wall, when its `strata_strength` or
// `streak_strength` is set), both in the same world coordinates, so a bed
// that runs along a cliff inside the square runs on round the cut face.

float earth_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float earth_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = earth_hash(i);
	float b = earth_hash(i + vec2(1.0, 0.0));
	float c = earth_hash(i + vec2(0.0, 1.0));
	float d = earth_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// A low variation in brightness, 0..1, off one plane.
float earth_macro(vec2 q, float scale) {
	return earth_vnoise(q / scale) * 0.65 + earth_vnoise(q / (scale * 0.31) + 17.0) * 0.35;
}

// The same, triplanar (`tw` the weights): each plane's pattern blended by its
// weight, so it neither runs down a wall in stripes nor folds where a face
// turns. Flat ground pays for one plane.
float earth_macro3(vec3 p, vec3 tw, float scale) {
	if (tw.x + tw.z <= 0.02) {
		return earth_macro(p.xz, scale);
	}
	return earth_macro(p.xz, scale) * tw.y + earth_macro(p.zy, scale) * tw.x
			+ earth_macro(p.xy, scale) * tw.z;
}

// The beds at `p`, `metres` apart: x their tone (0 dark to 1 light), y how
// much they show there (more in some stretches of a wall than others).
vec2 earth_beds(vec3 p, float metres) {
	// near flat, bent by folds a few hundred metres across
	float bed_y = p.y + earth_vnoise(p.xz / 260.0) * 26.0 + earth_vnoise(p.xz / 55.0 + 5.0) * 5.0;
	float beds = earth_vnoise(vec2(bed_y / metres, 3.7)) * 0.55
			+ earth_vnoise(vec2(bed_y / (metres * 0.37), 11.3)) * 0.3
			+ earth_vnoise(vec2(bed_y / (metres * 0.11), 23.9)) * 0.15;
	float shows = smoothstep(0.2, 0.75, earth_vnoise(p.xz / 90.0 + vec2(bed_y / 70.0, 61.0)));
	return vec2(beds, 0.35 + 0.65 * shows);
}

// Water's streaks down a face, off one side plane (q: across, up): long,
// narrow and dark, in patches.
float earth_streaks(vec2 q) {
	float run = earth_vnoise(vec2(q.x / 4.5, q.y / 50.0 + 31.0));
	float where = earth_vnoise(vec2(q.x / 34.0, q.y / 150.0 + 47.0));
	return smoothstep(0.58, 0.88, run) * smoothstep(0.35, 0.7, where);
}

// The two on `col`, `amount` of them (0 none: flat ground, 1 a cliff), `tw`
// the triplanar weights — the streaks are each side plane's own, blended by
// their weights (the patterns, never the coordinates, so nothing folds where
// a face turns from looking east to looking south).
vec3 earth_cliff(vec3 col, vec3 p, vec3 tw, float amount,
		float strata_strength, float strata_metres, float streak_strength) {
	if (amount <= 0.01) {
		return col;
	}
	vec2 b = earth_beds(p, strata_metres);
	col *= 1.0 + (b.x - 0.5) * 2.0 * strata_strength * amount * b.y;
	float side = tw.x + tw.z;
	if (side > 0.02 && streak_strength > 0.0) {
		float streak = (earth_streaks(p.zy) * tw.x + earth_streaks(p.xy) * tw.z) / side;
		col = mix(col, col * vec3(0.45, 0.45, 0.48), streak * streak_strength * amount);
	}
	return col;
}
