// ============================================================================
//  SHADERINC_golf_wall.gdshaderinc  —  the boundary of an engaged golf hole
// ============================================================================
// ONE HOLE, DRAWN AS A CAPSULE, AND EVERYTHING OUTSIDE IT STOPS. While the
// player has a hole engaged, the world beyond the hole's boundary desaturates
// and its animation holds the pose it had at the instant of engagement. Inside
// the boundary nothing changes at all. The visible edge between the two is the
// feature — it reads as a wall around the hole you are playing.
//
// Three things cross that wall, and all three come through this file:
//
//   COLOUR   `golf_wall_drain()`, called on the finished colour by
//            `SHADER_terrain_splat_w2.gdshader` and `SHADER_cliff_wall.gdshader`.
//   WIND     `golf_wall_time()`, standing in for TIME in
//            `SHADER_veg_billboard.gdshader`'s sway — grass, tufts, firs and bushes.
//   CLOUD    the same `golf_wall_time()` in `SHADER_cloud_plane.gdshader`'s drift,
//            which freezes the deck's shadow pattern on the land outside.
//
// ---------------------------------------------------------------------------
// THE CAPSULE IS THE HOLE'S OWN, AND IT IS NOT WOBBLED.
//
// A golf hole in `SCRIPT_island_field.gd` IS a capsule — `Zone.a`, `Zone.b`, a
// half-width, and an elbow (`Zone.m`) when it doglegs. This file rebuilds that
// same capsule from three globals, so the wall is the hole's real shape rather
// than an approximation of it, doglegs included.
//
// What it deliberately does NOT reproduce is the wobble. `zone_signed_distance`
// perturbs the boundary with `IslandField._zone_noise`, and that is what gives
// the MOWN GRASS its irregular edge. Matching it here would mean reimplementing
// a FastNoiseLite in GLSL and keeping the two in step forever.
//
// It would also be the wrong look. A boundary that wriggles along with the grass
// reads as a property of the terrain — as an artifact. A clean capsule reads as
// something IMPOSED on the terrain, which is what this is. So the wall is smooth,
// the mown grass under it stays ragged, and `golf_wall_margin` on the publisher
// stands the wall a few metres clear of the grass so the two are not competing to
// be the same line.
//
// ---------------------------------------------------------------------------
// EVERY POSITION HERE IS RENDER SPACE, NEVER LOGICAL.
//
// W3 rebases the world under a floating origin (`SCRIPT_floating_origin.gd`), which
// leaves two frames in play: the LOGICAL one the field is defined in, and the
// RENDER one the fragment is actually being drawn at. `SCRIPT_golf_wall.gd`
// publishes the capsule in render space and re-publishes it on every shift, the
// same contract `veg_burn_front` keeps (see `SCRIPT_veg_burn.gd.apply_origin_shift`).
//
// So callers must hand these functions a RENDER-space XZ. Two of them have both
// frames sitting side by side and it is easy to grab the wrong one:
//
//   * `SHADER_veg_billboard.gdshader` — `MODEL_MATRIX[3].xyz` is already render space.
//     Correct as-is.
//   * `SHADER_cloud_plane.gdshader` — line 175 computes `wp` (render) and line 176
//     computes `p = wp.xz + world_offset` (logical, for noise continuity across a
//     rebase). THE MASK WANTS `wp.xz`. Passing `p` puts the wall wherever the
//     origin happens to have drifted to, which on an 8 km rebase is off the island
//     entirely — and it looks right until the first shift fires, which is what
//     makes it worth this paragraph.
//
// ---------------------------------------------------------------------------
// THE THREE GLOBALS, packed rather than named one-per-value because they are set
// together every frame the drain is moving and a vec4 costs one call:
//
//   golf_wall_axis   (a.x, a.z, m.x, m.z)   capsule ends A and the elbow M
//   golf_wall_shape  (b.x, b.z, width, bent)  end B, half-width, elbow flag
//   golf_wall_fx     (drain, freeze_time, edge, keep)
//   golf_wall_tint   (r, g, b, sepia strength)
//
// `drain` 0 disables every function here on its first line, so a scene with no
// publisher — every zone but W3 — pays one uniform read and nothing else.

global uniform vec4 golf_wall_axis;
global uniform vec4 golf_wall_shape;
global uniform vec4 golf_wall_fx;
//   golf_wall_tint   (r, g, b, sepia)   the tone the drained world is graded to
global uniform vec4 golf_wall_tint;
// FILM GRAIN over the graded world: (amount, cells across the screen, steps per
// second, unused). See `golf_wall_film_grain`.
global uniform vec4 golf_wall_film;


// Distance from `p` to a segment, the standard clamped projection. The capsule's
// whole shape is this plus a half-width.
float golf_wall_segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float len2 = dot(ab, ab);
	// A degenerate segment is a point, and the projection below would divide by
	// zero on it. A zero-length hole is not a thing the field generates, but an
	// un-engaged wall publishes all zeroes and every fragment in the scene would
	// take that division before `drain` had a chance to matter.
	if (len2 < 1e-6) {
		return distance(p, a);
	}
	float t = clamp(dot(p - a, ab) / len2, 0.0, 1.0);
	return distance(p, a + ab * t);
}


// Distance from a render-space XZ to the hole's axis: one segment for a straight
// hole, two for a dogleg. Mirrors `IslandField.Zone.axis_distance`.
float golf_wall_axis_distance(vec2 world_xz) {
	vec2 a = golf_wall_axis.xy;
	vec2 m = golf_wall_axis.zw;
	vec2 b = golf_wall_shape.xy;
	if (golf_wall_shape.w < 0.5) {
		return golf_wall_segment_distance(world_xz, a, b);
	}
	return min(golf_wall_segment_distance(world_xz, a, m),
			golf_wall_segment_distance(world_xz, m, b));
}


// HOW FAR OUTSIDE THE WALL A POINT IS, 0..1, already scaled by the drain.
//
// 0 anywhere inside the capsule and anywhere at all while no hole is engaged; 1
// once past the boundary by `edge` metres. This is the one function the other
// two are built on, so the colour and the two clocks cannot disagree about where
// the wall is.
float golf_wall_outside(vec2 world_xz) {
	float drain = golf_wall_fx.x;
	if (drain <= 0.0) {
		return 0.0;
	}
	float sd = golf_wall_axis_distance(world_xz) - golf_wall_shape.z;
	// `edge` is METRES, not a normalised ramp, so the wall has the same visual
	// thickness on a 14 m par 3 as on a 40 m fairway. A ramp expressed as a
	// fraction of the width would make the big holes look soft and the small ones
	// look hard, which is the opposite of a wall reading as one object.
	return smoothstep(0.0, max(golf_wall_fx.z, 1e-3), sd) * drain;
}


// ---------------------------------------------------------------------------
// FOR SURFACES WITH NO WORLD POSITION, which is the sky and only the sky.
//
// `shader_type sky` has EYEDIR and nothing else — there is no world XZ to mask
// against, and there could not be: the sky is not AT anywhere. That is not a
// limitation here, it is the answer. The sky is entirely outside every hole by
// construction, so the mask it would compute is `drain` at every pixel, and these
// two just say that directly.
//
// They are separate functions rather than a `world_xz` of zero because a zero XZ
// is a real point that happens to be near the world origin, and on an island whose
// first hole runs through (360, -480) it would be outside — right answer, wrong
// reason, and wrong the day someone builds a course over the origin.

// ---------------------------------------------------------------------------
// THE GRADE. Every drained pixel in the scene goes through this and nothing else.
//
// DESATURATE, THEN TONE, in that order and not as one matrix. A sepia matrix
// applied to the original colour keeps some of its hue, so a red roof stays a
// warmer sepia than the grass beside it — which is a photograph tinted, not a
// world with its colour taken away. Going to luma first throws the hue out
// completely and the tone is then the ONLY colour information left, which is what
// makes the outside world read as a memory of itself.
//
// `keep` (golf_wall_fx.w) is the saturation that SURVIVES out there: 0 takes it
// all the way, and anything up to 1 leaves progressively more of the original.
// `golf_wall_tint.w` is how far the grey is then pushed toward the tone, so the
// two are independent — full desaturation with no sepia is neutral grey, and
// either can be dialled without touching the other.
//
// THE TONE IS A MULTIPLY ON LUMA, deliberately un-normalised. Normalising it to
// preserve luminance would push the red channel over 1 and clip the highlights
// back toward white, losing the tone exactly where the picture is brightest. The
// small overall darkening this causes instead is welcome — the world outside is
// meant to read as diminished.
//
// It lands BEFORE `SHADER_post_dither.gdshader`, so the result is not a computed
// tone: it quantises onto whatever warm neutrals `PALETTE_ps1-soft.hex` actually
// holds. That ramp is real and it is why this works — `403028`, `584838`,
// `786058`, `c0a888`, `f0d0b8` climb one warm hue across the whole brightness
// range, so a sepia gradient has somewhere to land at every step.
//
// ONE IMPLEMENTATION, THREE ENTRY POINTS, and that is the reason this exists as
// its own function. There were three copies of the desaturation before the tone
// was added — here, in the sky's drain-only variant, and inline in
// `SHADER_veg_billboard.gdshader`, which resolves its mask per instance and so
// could not call the masked one. Adding the sepia to two of the three would have
// left every plant in the world grey while the ground under it went brown.
// A cheap per-pixel hash — Hoskins' `hash12`, promoted through a vec3 so the two
// input axes are mixed against a THIRD copy of one of them before being combined.
//
// NOT the two-line `fract(p * vec2(443.897, 441.423))` form, and not the older
// `sin(dot(...)) * 43758.5453` either. Both degenerate on this input. The sine one
// has so little precision left after the sine on some GL drivers that it bands
// into diagonal stripes; the two-line one collapses wherever an axis `fract`s to
// near zero, which for a screen UV means the top and left edges of the frame —
// solid horizontal rows and vertical columns, right where the eye is least
// forgiving. That was visible in a render before this replaced it: a patch of the
// sky's top-left corner carried the same noise AMPLITUDE as the rest of the frame
// (stdev 17.4 against 17.1) while being obviously structured, which is why it had
// to be looked at rather than measured.
//
// The offset keeps the input off the origin as well, so the first grain step of a
// fresh session is not hashing coordinates near zero.
float golf_wall_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.x, p.y, p.x) * 0.1031) + 0.371;
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


// SIGNED FILM GRAIN, -amount..+amount, in SCREEN space.
//
// GRAIN BELONGS TO THE PROJECTION, NOT TO THE WORLD, and that is the whole reason
// this runs on live `TIME` while everything it lands on is frozen. Grain is a
// property of the film stock and the projector, so a photograph held perfectly
// still still boils with it. Freezing the grain along with the world would nail it
// to the surfaces and turn it into dirt on the textures — the one reading this
// must not have.
//
// IT STEPS AT A FILM RATE rather than per frame. `golf_wall_film.z` quantises the
// clock, so at 12 the field is redrawn twelve times a second no matter what the
// renderer is doing. Per-frame grain at 60 fps reads as digital sensor noise;
// twelve reads as film, and it is the single thing that decides which of the two
// this looks like.
//
// THE SCALE IS IN SCREEN CELLS, and the number that matters is not the window's.
// `SHADER_post_dither.gdshader` resolves the frame in 2x2 chunks and point-samples
// each one, so grain finer than a chunk is not averaged — it is simply missed, at
// whatever rate the sampling happens to catch it. Setting the scale near the
// CHUNK resolution puts roughly one grain cell per chunk, which is both the most
// grain that survives and the size that matches everything else in frame.
float golf_wall_film_grain(vec2 screen_uv, float t) {
	float amount = golf_wall_film.x;
	if (amount <= 0.0) {
		return 0.0;
	}
	float stepped = floor(t * max(golf_wall_film.z, 0.001));
	float n = golf_wall_hash(screen_uv * max(golf_wall_film.y, 1.0)
			+ vec2(stepped * 17.31, stepped * 11.07));
	return (n - 0.5) * 2.0 * amount;
}


vec3 golf_wall_grade(vec3 color, float outside, vec2 screen_uv, float t) {
	float amount = outside * (1.0 - clamp(golf_wall_fx.w, 0.0, 1.0));
	if (amount <= 0.0) {
		return color;
	}
	// Rec. 709 luma. The palette is graded for perceived brightness, so a flat
	// average here would send saturated greens and reds to the wrong grey and the
	// drained world would not sit on the ramp already in the scene.
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 toned = mix(vec3(luma), luma * golf_wall_tint.rgb,
			clamp(golf_wall_tint.w, 0.0, 1.0));
	// MULTIPLIED, NOT ADDED. Film grain is a density variation in the emulsion, so
	// it scales with what is already there: blacks stay black and highlights keep
	// their shape. Added grain lifts the shadows into a uniform grey fog, which is
	// what video noise looks like and is the wrong century.
	toned *= 1.0 + golf_wall_film_grain(screen_uv, t);
	// Grain rides INSIDE the mix, so it fades up with the drain and is not sprayed
	// over a world that has not started draining yet.
	return mix(color, max(toned, vec3(0.0)), amount);
}


float golf_wall_time_all(float t) {
	return mix(t, golf_wall_fx.y, golf_wall_fx.x);
}


vec3 golf_wall_drain_all(vec3 color, vec2 screen_uv, float t) {
	return golf_wall_grade(color, golf_wall_fx.x, screen_uv, t);
}


// THE CLOCK A FRAGMENT ANIMATES ON. Inside the wall this is `t` unchanged; outside
// it is the timestamp the wall went up, so motion holds its pose rather than
// easing back to rest.
//
// FREEZING THE CLOCK, NOT THE AMPLITUDE, is the whole reason this is a mix and
// not a multiply. Damping a sway to zero returns the plant to its REST pose, so a
// forest caught mid-gust would visibly unbend as the wall came up — a settle,
// which reads as the world relaxing rather than stopping. Holding the clock
// leaves every blade exactly where the last live frame put it.
//
// `t` is passed in rather than read from TIME here because an include's function
// gets the built-in from whichever stage inlined it, and this one is called from
// vertex() in the veg shader and fragment() in the cloud shader.
float golf_wall_time(float t, vec2 world_xz) {
	return mix(t, golf_wall_fx.y, golf_wall_outside(world_xz));
}


vec3 golf_wall_drain(vec3 color, vec2 world_xz, vec2 screen_uv, float t) {
	return golf_wall_grade(color, golf_wall_outside(world_xz), screen_uv, t);
}
