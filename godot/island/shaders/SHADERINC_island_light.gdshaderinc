// ============================================================================
//  SHADERINC_island_light.gdshaderinc  —  the island's one lighting model
// ============================================================================
// UNLIT SHADING FOR THE WHOLE LANDMASS. Every surface of the island — the
// walkable terrain, its shoulder, and the cliff wall under it — resolves its
// light through `island_light()` here and through nothing else. The engine's
// light loop is off (`render_mode unshaded` in both callers), so this function
// IS the lighting: what it returns is multiplied into albedo and goes to screen.
//
// ONE IMPLEMENTATION, TWO SHADERS, and that is the reason this is an include
// rather than a copied block. `SHADER_terrain_splat_w2.gdshader` draws the surface and
// the shoulder; `SHADER_cliff_wall.gdshader` draws the wall that continues it. The two
// meet mid-curve on a shared ring, some 28 m below the shore, in plain sight
// above the cloud deck. They already share the rock texture, its scale and its
// tint for exactly that reason (and `tests/TEST_island_world.gd` asserts they
// keep sharing them) — sharing the ALBEDO across that seam and then computing
// the LIGHT two different ways would put the seam straight back.
//
// ---------------------------------------------------------------------------
// WHY NOT A MATCAP, given that a matcap is the obvious way to fake this.
//
// A matcap indexes its lookup by the VIEW-SPACE normal, so its lighting is
// welded to the camera: turn, and the lit side turns with you. On a prop or a
// ball nobody can tell. On a 2.5 km landmass it is the tell, because everything
// else in this scene is world-anchored — the cloud sea, the horizon band, the
// sky panorama — so the terrain would be the only thing in frame whose lighting
// swims when the camera orbits.
//
// So the lookup is indexed by the WORLD normal instead. Same cost, same
// art-directability, no swim. The one term that IS view-dependent here is the
// rim, and that one is supposed to track the camera — a fresnel edge is a
// property of the viewing angle, so it has no swim to lose.
//
// ---------------------------------------------------------------------------
// THE THREE TERMS.
//
//   AMBIENT — `island_ambient()` below. A BAKED ENVIRONMENT BALL sampled by the
//     world normal, measured against this scene's real sky and cloud deck by
//     `scripts/SCRIPT_bake_env_ball.gd`, with the analytic sky/ground hemisphere kept as
//     the fallback for any scene that has no bake of its own. The ball's channels
//     are weights and never colours, so every colour still comes off the bus and
//     the day/night cycle drives a bake exactly as it drove the lerp — see the
//     `env_ball` uniform below for the encoding and for what the ball buys over
//     the lerp (the answer is the LEVEL term, not the hue split).
//
//     It also replaces the `slope_shade` fudge both callers used to carry — a
//     flat `1 - (1 - n.y) * k` darkening of steep ground. That was an
//     approximation of exactly this hemisphere, applied to albedo, clamped, and
//     tuned separately per shader. Both materials now ship `slope_shade = 0`.
//
//   SUN — a wrapped, BANDED lambert against `tod_sun_dir`. The bands are the
//     point rather than a saving: `SHADER_post_dither.gdshader` quantises the frame to
//     sixteen palette entries, and a smooth ramp handed to a quantiser comes
//     back as evenly spaced contour lines wherever the palette happens to fall,
//     plus crawling Bayer noise as the camera moves. Posterising deliberately,
//     to a count we choose, puts the bands where we want them and lets them read
//     as cel shading instead of as banding. This is the same lesson the terrain
//     shader already records about specular: anything that lands BETWEEN two
//     palette entries does not blend, it jumps.
//
//   RIM — fresnel against the view vector, tinted by the sky. What makes an
//     unlit landform read as having volume against a void sky, and the only
//     term here that is allowed to depend on the camera.
//
// ---------------------------------------------------------------------------
// EVERYTHING COMES OFF THE GLOBAL BUS. All four inputs are global shader
// parameters (declared in project.godot's `[shader_globals]`, published by
// `scripts/SCRIPT_sky_cycle_controller.gd`), so a day/night cycle is a property of the
// scene rather than of any material: move the four globals and the island, the
// water spray and the rainbow arc all follow, with no per-material push and no
// shader knowing a cycle exists. That is the whole architecture — this file just
// reads it.
//
// Include from a spatial shader that has already declared `unshaded`:
//     #include "res://godot/island/shaders/SHADERINC_island_light.gdshaderinc"

global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
global uniform vec4 tod_sky_color;
global uniform vec4 tod_ground_color;

// THE ENVIRONMENT BALL, baked by `scripts/SCRIPT_bake_env_ball.gd`. Sampled by the world
// normal, it replaces the analytic hemisphere with a measurement of the actual
// scene sky:
//
//     R  share of the cosine lobe that sees SKY rather than deck
//     G  share that sees the CLOUD DECK          (R + G == 1)
//     B  how much light that lobe collects, against the best-lit normal
//
//     ambient = (tod_sky_color * R + tod_ground_color * G) * B
//
// COLOURS STILL COME OFF THE BUS. The ball stores WEIGHTS, never colours, which is
// the only way a bake and a day/night cycle can coexist — a baked RGB ball would
// be a photograph of one moment and would need re-baking to survive sunset. So the
// cycle keeps full control of hue and level and the bake keeps full control of
// distribution across normals, for one fetch.
//
// WHAT IT BUYS OVER THE LERP IS THE `B` TERM. `mix(ground, sky, up)` is a convex
// combination of two colours: it can slide the ambient's hue between them but its
// magnitude can never leave the interval they span. W2's sky is about five times
// brighter in the mid-dome than at the horizon in linear terms, so a surface facing
// up really does collect several times the light of one facing sideways — the
// shipped day bake measures 1.00 at up, 0.57 at the horizon, 0.29 at straight down.
// That 3.4:1 spread is the contrast the ball is here for, and the lerp has no term
// that can express it.
//
// AND THE R/G SPLIT IS NOT THE RAMP IT LOOKS LIKE, which this comment claimed for a
// while and which the numbers do not support. Cosine-convolving a half-space by
// SOLID ANGLE is exactly `n.y * 0.5 + 0.5` — that much is a standard result and it
// is what an earlier bake measured. But `SCRIPT_bake_env_ball.gd::_weights` deliberately
// weights the shares by RADIANCE instead, because the alternative applies the
// deck's colour at the deck's share of the solid angle rather than at its share of
// the LIGHT (measured: an up-facing normal over-weighted the deck by 2.9x). Once
// they are radiance-weighted the split stops tracking `n.y` at all: the shipped day
// ball reads 0.749 sky at a HORIZONTAL normal, not 0.500, because the half of the
// sphere that is sky is about four times brighter than the half that is deck.
// `tests/TEST_env_ball.gd` asserts exactly that ("takes most of its light from the
// sky, not half").
//
// NO `source_color`. These are weights, not colour: an sRGB decode on the way in
// would bend all three channels. The import is pinned lossless, mipmap-free and
// `detect_3d/compress_to=0` for the same reason — see TEX_env_ball_w2.png.import.
//
// `hint_default_black` IS THE FAILURE MODE, chosen rather than defaulted. With
// `env_ball_enabled` on and no texture bound, Godot substitutes a fallback: white
// would give R = G = B = 1 and quietly ADD the two bus colours at full strength —
// roughly double ambient, plausible enough to ship by accident. Black gives an
// unlit island, which nobody ships by accident.
uniform bool env_ball_enabled = false;
uniform sampler2D env_ball : hint_default_black, filter_linear, repeat_disable;

// THE SECOND BALL, and the reason there are two.
//
// A ball is a measurement of ONE environment, and SCENE_test_zone_W2 has two: the
// overcast island, and the same island with the sky gone over to blood. They are
// not a tint apart — the ANGULAR PROFILE inverts. At day the dome is the bright
// thing and the deck below is dark, so an up-facing surface collects 3.4x what a
// down-facing one does. At the nightmare end the dome is authored to 0.01 sRGB and
// the light is coming from the burning cumulus ring at the horizon, the cloud sea
// underneath and the vortex overhead, so the spread flattens to 1.4:1 and the
// horizon becomes the DARKEST direction rather than a middling one. Measured, over
// the shipped pair:
//
//     normal      day level    night level
//     up             0.996        0.996
//     45 up          0.812        0.867
//     horizon        0.573        0.718
//     45 down        0.325        0.745
//     down           0.294        0.800
//
// One ball cannot say both, and a tint cannot turn one into the other — which is
// what the day-only bake was doing, and why this file used to carry a caveat
// saying the ball "keeps saying upward-facing ground is best lit".
//
// SO BOTH ARE BAKED AND MIXED, by the same phase blend everything else in the
// scene rides. `scripts/SCRIPT_bake_env_ball.gd --phase=day|night` writes them, reading
// the SAME preset the runtime blends, so the bake cannot drift from the look.
//
// THE SECOND FETCH IS SKIPPED AT DAY. `tod_env_blend` is a global, so branching on
// it is uniform control flow: every scene without a nightmare — and W2 itself for
// all of the time it is not flipping — pays exactly what it paid before. The
// texture may be left unbound, which with `hint_default_black` degrades to "the
// nightmare has no ambient" rather than to a doubled one.
uniform sampler2D env_ball_night : hint_default_black, filter_linear, repeat_disable;

// 0 at day, 1 in the nightmare, published by `scripts/SCRIPT_sky_cycle_controller.gd` off
// the same phase weights as every other `tod_*`. Zero when nothing publishes it,
// which is the day ball alone — the behaviour every other scene wants.
global uniform float tod_env_blend;


// Unit vector -> octahedral square, folded about Y because the engine is Y-up.
// EXACT INVERSE of `SCRIPT_bake_env_ball.gd::_oct_decode`, which is what the baker walks
// to decide what to write in each texel; `tests/TEST_env_ball.gd` asserts the two
// agree by sampling the shipped texture through this addressing and comparing
// against the analytic environment.
vec2 island_oct_encode(vec3 n) {
	vec3 v = n / max(abs(n.x) + abs(n.y) + abs(n.z), 1e-6);
	vec2 r = vec2(v.x, v.z);
	if (v.y < 0.0) {
		vec2 sgn = vec2(v.x >= 0.0 ? 1.0 : -1.0, v.z >= 0.0 ? 1.0 : -1.0);
		r = vec2((1.0 - abs(v.z)) * sgn.x, (1.0 - abs(v.x)) * sgn.y);
	}
	return r * 0.5 + 0.5;
}


// The ambient half of the model: the ball if one is bound, the analytic hemisphere
// otherwise. The fallback is not dead code — it is what the include does in any
// scene with no bake for its sky, and it is the thing the ball has to beat.
vec3 island_ambient(vec3 world_n) {
	if (!env_ball_enabled) {
		return mix(tod_ground_color.rgb, tod_sky_color.rgb, world_n.y * 0.5 + 0.5);
	}
	// THE GUTTER MAPPING. The image is `core + 2` square with a one-texel border
	// holding the directions across the octahedral fold, so the core has to be
	// addressed by texel index rather than by uv: oct 0 and 1 land exactly ON the
	// gutter/core boundary, where a bilinear tap averages the two sides of the fold
	// — which is the correct value there rather than a seam. Derived from
	// `textureSize` instead of a uniform so the core size cannot drift from the
	// texture the baker actually wrote.
	vec2 ts = vec2(textureSize(env_ball, 0));
	vec2 uv = (island_oct_encode(world_n) * (ts - 2.0) + 1.0) / ts;
	vec3 ball = texture(env_ball, uv).rgb;
	// Uniform control flow, so the day path costs one fetch exactly as it did.
	// Mixing the WEIGHTS rather than two finished ambients is both cheaper and more
	// correct: the two balls share an addressing and a normalisation, so a texel of
	// one is directly comparable to the same texel of the other, and one mix of a
	// vec3 replaces two colour multiplies and an add.
	if (tod_env_blend > 0.0) {
		ball = mix(ball, texture(env_ball_night, uv).rgb, clamp(tod_env_blend, 0.0, 1.0));
	}
	return (tod_sky_color.rgb * ball.r + tod_ground_color.rgb * ball.g) * ball.b;
}


// Snap to `steps` evenly spaced levels across [0,1], endpoints included. Below two
// steps it is a pass-through, so a material can switch the banding off with a
// number rather than with a branch. The clamp stops 1.0 landing in the (n+1)th
// bucket, which would otherwise be a single blown-out level on exactly-lit faces.
float island_posterize(float x, float steps) {
	if (steps < 2.0) {
		return clamp(x, 0.0, 1.0);
	}
	return floor(clamp(x, 0.0, 0.99999) * steps) / (steps - 1.0);
}


// `world_n`  unit surface normal in WORLD space, as the engine hands it over:
//            under `cull_disabled` a back face's NORMAL already arrives turned
//            toward the viewer, so a caller must not flip it again (measured —
//            see the NO BACK-FACE FLIP note in `SHADER_ruin_w2.gdshader`).
// `world_v`  unit vector from the surface TOWARD the camera, in world space.
// `sun_wrap` how far light bleeds past the terminator. 0 is a hard
//            `max(dot, 0)`; 1 is full wrap-around, lighting the back face at
//            half. Anything above 0 keeps the unlit side from going to pure
//            ambient in one step, which on banded shading is a visible ring.
vec3 island_light(vec3 world_n, vec3 world_v, float sun_bands, float sun_wrap,
		float rim_power, float rim_strength) {
	// --- ambient: environment ball, or the hemisphere it replaces ------------
	vec3 lit = island_ambient(world_n);

	// --- sun ----------------------------------------------------------------
	// `tod_sun_dir` is the surface->sun vector (sky_cycle_controller publishes the
	// light's basis.z, which points back toward the light), so a positive dot is a
	// face turned toward it.
	float ndl = dot(world_n, tod_sun_dir);
	float sun = clamp((ndl + sun_wrap) / (1.0 + sun_wrap), 0.0, 1.0);
	lit += tod_sun_color.rgb * island_posterize(sun, sun_bands);

	// --- rim ----------------------------------------------------------------
	// Not banded. The fresnel falls off over a few pixels at a silhouette, so
	// posterising it would produce a stair-stepped outline rather than a soft one,
	// and it is narrow enough that the palette does not band it either.
	if (rim_strength > 0.0) {
		float fres = pow(1.0 - clamp(dot(world_n, world_v), 0.0, 1.0), rim_power);
		lit += tod_sky_color.rgb * (fres * rim_strength);
	}

	return lit;
}


// THE FILL LIGHT: the sun again, from exactly the other side, at `strength` of its
// colour and energy. A fourth term that a caller ADDS to `island_light()`, and one
// nothing on the island uses by default: the ground, the cliff, the pod and the
// wreck do not call it, and a strength of 0 returns black.
//
// WHY IT EXISTS: THE SUN NEVER MOVES. The island's pivot is fixed and only its
// colour cycles, so a face turned away from it is turned away for good, and all
// such a face ever gets is the ambient. On the ground that never matters: ground
// faces up, and up takes two thirds of the sun all day. A tall VERTICAL face is
// different. By day the ambient gives a horizontal normal about a quarter of the
// sun's top band (0.25 against 1.0), so the far side of anything upright sits at
// a fifth of its lit side. That is enough for the island's own paint — it was a
// tenth, and black, until the day's ambient level was doubled and the ball's floor
// raised — but not for paint as dark as the ruin entrance's, whose door faces the
// pod, with the pod almost straight down-sun of it: the side every approach sees
// still drew near black. See `SHADER_ruin_w2.gdshader` and
// `docs/DOC_ruin_materials.md`.
//
// A FILL LIGHT, NOT A MEASUREMENT, and it is written down as one. The ball is a
// measurement and needs no help; this is the second light a photographer puts
// opposite the key so the shadow side reads, and its strength is a choice.
// Everything else about it follows the island's own rules:
//
//   * ITS COLOUR IS THE SUN'S, off the bus, so it rides the cycle with no second
//     number: white by day, orange at sunset, and in the blood night a fifth of
//     its daytime size, in red, under an ambient that already outweighs the sun
//     there — so it lifts the shadow side most exactly when that side is darkest.
//   * IT IS BANDED EXACTLY AS THE SUN IS, same wrap and same band count, so it
//     reads as the same cel shading rather than as a smooth ramp handed to the
//     palette quantiser.
//   * IT COMES FROM `-tod_sun_dir`, as far BELOW the horizon as the sun is above
//     it, and that is what keeps it off the ground: an up-facing normal sees it at
//     -sin(elevation), which at the island's 17.6 degrees wraps to 0.10 — under
//     the first band's edge at 0.25. So flat ground, tile tops and ledges get
//     nothing from it and stay matched to the terrain beside them, and faces that
//     look down get some, as though off the lit ground below them. (It would
//     reach the ground if the sun were ever set below 5 degrees, where
//     sin(elevation) drops under the 0.0875 the edge needs.)
vec3 island_fill_light(vec3 world_n, float strength, float sun_bands, float sun_wrap) {
	if (strength <= 0.0) {
		return vec3(0.0);
	}
	float ndl = dot(world_n, -tod_sun_dir);
	float fill = clamp((ndl + sun_wrap) / (1.0 + sun_wrap), 0.0, 1.0);
	return tod_sun_color.rgb * (strength * island_posterize(fill, sun_bands));
}
