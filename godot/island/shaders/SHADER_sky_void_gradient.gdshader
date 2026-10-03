shader_type sky;

#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// Flat two-tone gradient sky for the island void: dark grey below, light grey
// above, with the transition sitting ABOVE the true horizon. Optionally the top
// of the dome fades out to black and a slowly turning vortex fills it — both off
// by default, both described down at *The zenith cap*.
//
// Raising the horizon is the whole point. Geometrically the horizon is at
// EYEDIR.y = 0, and putting the dark/light split up at `horizon_height` means
// that when you look level you are already looking into the dark half. The void
// under the islands reads as something you are above rather than as more sky,
// and there is no cue telling you how far down it goes.
//
// `horizon_height` is measured as a fraction of the way from the horizon to the
// zenith, so it is independent of FOV and of where the camera is pointing —
// unlike anything specified in screen space, which would slide around as you
// pitch.
//
// The terrain shader's fog colours have to be kept in step with these, or
// distant cliffs resolve against the sky instead of dissolving into it. See
// `docs/DOC_procedural_island_world.md`.

// Deliberately EXACT neutrals (r == g == b). The post-process palette LUT snaps
// every pixel to its nearest entry, and even a slight blue bias in a mid grey is
// enough for a tinted entry to win over the neutral one — which paints a stripe
// of the wrong hue across the sky.
//
// The palette every scene now loads is `palette/PALETTE_ps1-soft.hex`, not the
// `PALETTE_allstars.hex` this comment used to name, and they do not have the same grey
// ramp. ps1-soft's exact neutrals run 0.000, 0.031, and then jump straight to
// 0.282, 0.314, 0.345 and on up in even 0.031 steps — one enormous hole in the
// dark end. A value landing in that hole has to dither between two entries eight
// steps apart, and the LUT hands back a TINTED entry for neutral input on either
// side of it. `bottom_color` is 0.30 partly for that reason; the measurements are
// in `docs/DOC_horizon_parallax_clouds.md`.
uniform vec3 top_color : source_color = vec3(0.666, 0.666, 0.666);
uniform vec3 bottom_color : source_color = vec3(0.089, 0.089, 0.089);

// The time-of-day bus's sun, published by `scripts/SCRIPT_sky_cycle_controller.gd` and
// declared identically in `shaders/SHADERINC_island_light.gdshaderinc`. Read ONLY as the
// sun-glow fallback for a scene with no DirectionalLight3D in it — see the glow
// in `sky()`. Zero when nothing publishes it, which is a glow of zero.
global uniform vec3 tod_sun_dir;

// 0.0 puts the split on the true horizon; 0.25 is a quarter of the way to
// straight up.
uniform float horizon_height : hint_range(-0.5, 0.9) = 0.25;
// Width of the blend, in the same units. Small values give a hard drawn line,
// large values a haze bank with no definite edge.
uniform float horizon_softness : hint_range(0.005, 1.0) = 0.20;

// A brighter band right at the transition. Kept subtle — it reads as the light
// pooling along the edge of an overcast, which is what sells the flat grey as
// weather rather than as a missing texture.
uniform vec3 horizon_glow : source_color = vec3(0.85, 0.85, 0.85);
uniform float horizon_glow_strength : hint_range(0.0, 1.0) = 0.10;
uniform float horizon_glow_width : hint_range(0.01, 1.0) = 0.34;

// Diffuse bloom around the sun direction rather than a disc: an overcast sky
// has no visible sun, just a bright patch. Set to 0 to remove it entirely.
uniform float sun_glow_strength : hint_range(0.0, 2.0) = 0.18;
uniform float sun_glow_width : hint_range(1.0, 64.0) = 8.0;
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.99, 0.95);


// ---------------------------------------------------------------------------
// The zenith cap: a blackout, and two vortex layers turning inside it.
// ---------------------------------------------------------------------------
//
// Both are sized by a *coverage* number — the fraction of the sky dome they take
// up, 0.05 being the top twentieth of it. That reads directly off the direction
// vector with no trigonometry, because of Archimedes' hat-box theorem: the area
// of a spherical cap is proportional to its HEIGHT, not to its angle. A cap
// reaching down to `EYEDIR.y == c` covers exactly `1 - c` of the hemisphere. So
//
//     cap edge at EYEDIR.y = 1.0 - coverage
//
// and the parameter means the same thing whichever way you measure it. An angle
// would not have been interchangeable like this: half the dome's *area* is the
// top 60 degrees, not the top 45.
//
// Everything here lives in the sky shader rather than on a mesh, which is what
// makes it unreachable. A sky shader is evaluated per view DIRECTION and has no
// position at all, so the vortex is at infinity by construction — the player can
// fly at it forever without closing any distance and without it ever clipping
// the near plane. A dome mesh would have to be parented to the camera and scaled
// past the far plane to fake the same thing, and would still land in the depth
// buffer and take fog.

group_uniforms zenith_cap;

// Fraction of the sky dome, measured down from straight up, that fades out to
// black. 0.05 is the top twentieth — a cap about 18 degrees wide, which is the
// pool of dark the vortex's eye sits in. 0.0 disables it, which is the default:
// SCENE_test_zone_W shares this shader and wants the plain two-tone gradient.
uniform float zenith_black_coverage : hint_range(0.0, 0.6) = 0.0;
// How far down the fade goes at the very top. 1.0 is true black.
uniform float zenith_darkness : hint_range(0.0, 1.0) = 1.0;

group_uniforms vortex;

// TWO LAYERS, TURNING AT DIFFERENT RATES, which is the note four paragraphs down
// finally taken up. Both are alpha-masked swirls mapped as a disc centred on the
// zenith; the alpha carries the shape and falls to zero at the edge of the circle
// inscribed in the image, so each disc feathers into the sky on its own — see
// `vortex_edge_fade` for the belt-and-braces, and read its doc before scaling
// either layer up, because a scale above 1 samples INSIDE that feather and hands
// the job to the mask.
//
// Layer B defaults to nothing (transparent, and `vortex_scale*` to 1.0), so a
// material that only ever set the single-layer uniforms — MAT_sky_void.tres, for
// SCENE_test_zone_W — renders exactly what it rendered before.
uniform sampler2D vortex_texture : source_color, filter_linear_mipmap,
		repeat_disable, hint_default_transparent;
uniform sampler2D vortex_texture_b : source_color, filter_linear_mipmap,
		repeat_disable, hint_default_transparent;
// Master opacity. 0.0 costs nothing and is the default, again for W's sake.
uniform float vortex_strength : hint_range(0.0, 1.0) = 0.0;
// Keep this an EXACT neutral for the same reason as the two sky colours above:
// the palette LUT will hand back a tinted entry for a grey that is off-neutral,
// and a 35%-of-the-sky object is a large surface to discover that on.
uniform vec3 vortex_color : source_color = vec3(1.0, 1.0, 1.0);
// Fraction of the sky dome the disc spans (see the hat-box note above). 0.35
// puts its rim at EYEDIR.y = 0.65, about 50 degrees off vertical.
uniform float vortex_coverage : hint_range(0.01, 0.6) = 0.35;
// Width of an extra fade at the rim, as a fraction of the disc's radius.
//
// PROMOTED FROM BELT-AND-BRACES TO LOAD BEARING the moment either
// `vortex_scale` goes above 1. At scale 1.0 a texture's own alpha reaches zero
// at the rim and this fade has nothing left to do; at 1.15 the rim samples
// radius 0.435, which is INSIDE the texture's own feather, so the alpha arriving
// there is not zero and this mask is the only thing standing between the swirl
// and a hard circle drawn across the sky. Widen it with the scale.
uniform float vortex_edge_fade : hint_range(0.0, 0.6) = 0.12;
// Radians per second, per layer. Negative turns clockwise as seen from below,
// i.e. looking up at it. -0.04 is about one revolution every two and a half
// minutes, so with six arms one sweeps past roughly every 25 seconds.
//
// EACH LAYER IS A RIGID rotation, and that is the whole reason there are two of
// them. Spinning the middle of ONE swirl faster than its rim is the obvious way
// to sell a vortex, and it is a trap: a shear that never stops winds the arms
// tighter every second until they are below a pixel and the whole thing greys
// out. Real spiral galaxies have the same problem. Two rigid discs at different
// rates give the same read — arms sliding past arms, a shape that never repeats
// — and it is bounded, because neither layer's own geometry ever changes. The
// beat period is the only thing that grows: at a 2:1 ratio the pair returns to
// its starting configuration once per revolution of the slower one.
uniform float vortex_spin_rad_per_sec = -0.04;
uniform float vortex_spin_offset_rad = 0.0;
uniform float vortex_spin_b_rad_per_sec = -0.08;
uniform float vortex_spin_b_offset_rad = 0.0;
// Magnification of each layer's image WITHIN the disc, not the size of the disc
// itself. Above 1 samples a smaller radius of the texture across the same solid
// angle, so the arms grow while `vortex_coverage` — and with it the rim at
// EYEDIR.y = 0.65 that the fog contract and `scripts/SCRIPT_bake_env_ball.gd` are both
// written against — stays exactly where it is. That separation is the point:
// scaling the swirl is a look change, moving the coverage is a contract change.
uniform float vortex_scale : hint_range(0.2, 4.0) = 1.0;
uniform float vortex_scale_b : hint_range(0.2, 4.0) = 1.0;


// ---------------------------------------------------------------------------
// The eye dome: a second sky, cross-faded in over the first.
// ---------------------------------------------------------------------------
//
// SCENE_test_zone_W2's nightmare is not a recolouring of the sky, it is a
// DIFFERENT SKY, and this is where the second one lives. `sky/SKY_eye_hdri.hdr` is
// a 4096x2048 equirectangular panorama of eyes — bright red (peak 6.0, and every
// texel in it is exactly 10:1:1 R:G:B), black between them, and black below
// EYEDIR.y of about -0.2. `scripts/world/SCRIPT_nightmare_sky_director.gd` runs
// `eye_blend` from 0 to 1 across the flip and the dome becomes it.
//
// IT IS A CROSS-FADE INSIDE ONE MATERIAL rather than two Sky resources swapped at
// the switch, because a swap cannot be half done and the whole effect is the half.
//
// THE PANORAMA IS NOT ALLOWED TO REACH THE HORIZON, which is what `eye_fade_low`
// and `eye_fade_high` are for and is the one thing here that is load bearing
// rather than cosmetic. `bottom_color` is a CONTRACT with fourteen fog values —
// see its declaration and `MAT_sky_w2_void.tres` — and this panorama is black
// along its bottom edge. Blending it in without a fade would paint black over the
// low sky while every fog in the scene stayed lit, which draws exactly the line
// across the world that the whole haze scheme exists to prevent. The fade holds
// the eyes off the bottom of the dome so the contract survives at every value of
// `eye_blend`, including the ones only seen for half a second.
group_uniforms eye_dome;

uniform sampler2D eye_panorama : source_color, filter_linear, repeat_enable,
		hint_default_black;
// 0 is the ordinary void sky and costs one uniform branch. 1 is the eye dome.
uniform float eye_blend : hint_range(0.0, 1.0) = 0.0;
// Level. The panorama is a true HDR and its eyes sit at 6.0, which `post_dither`
// would snap to the palette's WHITE entry — white eyes on black, with the red the
// whole scene is about thrown away in the last pass. This scales it back into
// range; see the director for the measurement the shipped value comes from.
uniform float eye_energy : hint_range(0.0, 4.0) = 1.0;
// Multiplier on top of that, for a scene that wants the eyes some other colour.
// The panorama carries its own red, so this is NOT `tod_art_tint`: the art tint is
// what turns DAYTIME artwork into nightmare artwork, and this sky only exists at
// the nightmare end. Taking it as well would tint what is already tinted.
uniform vec3 eye_tint : source_color = vec3(1.0, 1.0, 1.0);
// Rotation about world Y, radians. Same convention as `sky_panorama_rotating`.
uniform float eye_yaw = 0.0;
// The fade band, in EYEDIR.y. Below `eye_fade_low` the panorama contributes
// NOTHING at any blend and the horizon is exactly the colour the fog is; above
// `eye_fade_high` it is at full. Keep the low end above
// `horizon_height - horizon_softness`, which is where `bottom_color` stops being
// pure.
uniform float eye_fade_low : hint_range(-1.0, 1.0) = 0.06;
uniform float eye_fade_high : hint_range(-1.0, 1.0) = 0.40;

group_uniforms;


void sky() {
	float y = EYEDIR.y;

	vec3 col = mix(bottom_color, top_color,
			smoothstep(horizon_height - horizon_softness,
					horizon_height + horizon_softness, y));

	// Band centred on the transition, falling off either side.
	float band = 1.0 - smoothstep(0.0, horizon_glow_width, abs(y - horizon_height));
	col = mix(col, horizon_glow, band * horizon_glow_strength);

	// THE GLOW NEEDS A SUN, AND A SCENE MAY NOT HAVE A LIGHT. SCENE_test_zone_W2
	// is entirely unshaded and dropped its DirectionalLight3D, which takes
	// LIGHT0_ENABLED with it — so fall back to the time-of-day bus, which is where
	// that scene's sun direction lives now. Same convention on both sides
	// (surface->sun), so a scene WITH a light is unaffected: SCENE_test_zone_W
	// keeps reading LIGHT0_DIRECTION and renders exactly what it did.
	//
	// With neither, `tod_sun_dir` is the zero vector, the dot is 0 and pow(0, w)
	// is 0 — the glow is simply absent. No NaN and no third branch.
	if (sun_glow_strength > 0.0) {
		vec3 sun_dir = LIGHT0_ENABLED ? LIGHT0_DIRECTION : tod_sun_dir;
		float d = max(dot(EYEDIR, sun_dir), 0.0);
		col += sun_glow_color * pow(d, sun_glow_width) * sun_glow_strength;
	}

	// Blacken the cap BEFORE the vortex goes on, so the swirl is lit against the
	// dark rather than mixed into it: its own core is near-black with the arms
	// brightening outwards, and over a black zenith that reads as an eye with
	// light spiralling into it.
	if (zenith_black_coverage > 0.0) {
		float fade = smoothstep(1.0 - zenith_black_coverage, 1.0, y);
		col *= 1.0 - fade * zenith_darkness;
	}

	// Branching on a uniform keeps this uniform control flow, which is what lets
	// the texture() call below keep its implicit mip derivatives. Do not move the
	// sample inside a test on EYEDIR.
	if (vortex_strength > 0.0) {
		float cap_cos = 1.0 - vortex_coverage;
		float polar_max = acos(clamp(cap_cos, -1.0, 1.0));
		float polar = acos(clamp(y, -1.0, 1.0));

		// Radius across the disc, 0 at the zenith and 1 at the rim. tan() is the
		// projection you get by pinning the image to a flat ceiling overhead
		// instead of painting it on the dome, which compresses the arms towards
		// the rim the way a real layer above you would foreshorten. min() pins
		// everything below the rim at exactly 1 so the UV can never leave the
		// image.
		float r = tan(min(polar, polar_max)) / tan(polar_max);

		// Bearing, as a unit vector rather than an atan() angle. Same result, but
		// atan() jumps by TAU across the meridian behind the camera, and a UV that
		// jumps drives the mip selection to its coarsest level along that seam —
		// a blurred radial scar through the swirl. A vector has no branch cut.
		vec2 bearing = vec2(EYEDIR.x, EYEDIR.z);
		float bearing_len = length(bearing);
		// Undefined looking exactly at the zenith, where r is 0 and the choice
		// cannot matter.
		bearing = bearing_len > 1e-5 ? bearing / bearing_len : vec2(0.0, 0.0);

		// Wrapped so a long session cannot lose float precision in TIME; the
		// sample is identical either way because a rotation is periodic.
		//
		// On the golf wall's clock, so the vortex stops with everything else. The
		// sky has no world position to mask against and needs none — it is outside
		// every hole by construction. See `golf_wall_time_all`.
		float sky_clock = golf_wall_time_all(TIME);
		float spin_a = mod(vortex_spin_offset_rad + vortex_spin_rad_per_sec * sky_clock, TAU);
		float spin_b = mod(vortex_spin_b_offset_rad + vortex_spin_b_rad_per_sec * sky_clock, TAU);
		float cs_a = cos(spin_a);
		float sn_a = sin(spin_a);
		float cs_b = cos(spin_b);
		float sn_b = sin(spin_b);
		vec2 spun_a = vec2(cs_a * bearing.x - sn_a * bearing.y,
				sn_a * bearing.x + cs_a * bearing.y);
		vec2 spun_b = vec2(cs_b * bearing.x - sn_b * bearing.y,
				sn_b * bearing.x + cs_b * bearing.y);

		// r * spun is the azimuthal map, and it is smooth through r == 0 — the
		// polar singularity is in the angle, not in the vector, so nothing has to
		// be special-cased at the pole. Dividing r by the scale magnifies: at 1.15
		// the disc's rim reads the texture at radius 0.435 instead of 0.5.
		vec4 swirl_a = texture(vortex_texture,
				vec2(0.5) + 0.5 * (r / max(vortex_scale, 1e-4)) * spun_a);
		vec4 swirl_b = texture(vortex_texture_b,
				vec2(0.5) + 0.5 * (r / max(vortex_scale_b, 1e-4)) * spun_b);

		float edge = max(vortex_edge_fade, 0.001);
		float mask = 1.0 - smoothstep(1.0 - edge, 1.0, r);
		float a_a = swirl_a.a * mask * vortex_strength;
		float a_b = swirl_b.a * mask * vortex_strength;

		// SCREEN, and specifically not add. These are two lit swirls over a
		// blacked-out zenith, so where their arms cross the light has to
		// ACCUMULATE — a plain mix would let whichever layer is on top simply
		// delete the other, and the arms would read as painted cards rather than
		// as depth. But screen saturates at 1.0 where add runs past it, and
		// anything past 1.0 is snapped to the palette's white entry by
		// post_dither: additive overlaps would come out as flat white blobs with
		// every arm inside them erased, on the one large moving surface in the
		// scene. Screen is also commutative, so there is no layer order to pop
		// when the two turn through each other.
		//
		// Premultiplied, then divided back out by the union of coverage, so the
		// swirl still REPLACES the sky by its own alpha instead of brightening the
		// grey dome it sits on — most of this disc is over open sky, not over the
		// blackout, and screening straight onto `col` would wash that out.
		vec3 prem = 1.0 - (1.0 - swirl_a.rgb * a_a) * (1.0 - swirl_b.rgb * a_b);
		float cov = a_a + a_b - a_a * a_b;
		col = mix(col, (prem / max(cov, 1e-4)) * vortex_color, cov);
	}

	// THE EYE DOME GOES ON LAST, over the vortex rather than under it. The two
	// only ever overlap during the flip, and by the time this has any weight the
	// director has already wound the swirl down to a point at the zenith — which
	// then disappears into the pupil of the eye that opens there. Under the eye
	// instead, that point would sit ON TOP of the new sky and read as a stuck
	// pixel rather than as the old sky closing.
	//
	// Uniform branch, so the texture() keeps its implicit derivatives — same rule
	// as the vortex above. The panorama imports with mipmaps off, so the atan()
	// branch cut behind the camera cannot select a coarse mip and draw the blurred
	// seam it would otherwise; `repeat_enable` is what makes the wrap itself
	// interpolate cleanly across u = 0.
	if (eye_blend > 0.0) {
		float ecs = cos(eye_yaw);
		float esn = sin(eye_yaw);
		vec3 edir = vec3(
			ecs * EYEDIR.x + esn * EYEDIR.z,
			EYEDIR.y,
			-esn * EYEDIR.x + ecs * EYEDIR.z);
		vec2 euv = vec2(atan(edir.x, edir.z), acos(clamp(edir.y, -1.0, 1.0)));
		if (euv.x < 0.0) { euv.x += TAU; }
		euv /= vec2(TAU, PI);
		// The fade is a multiplier on the BLEND, not on the colour: fading the
		// panorama toward black would still darken the sky under it, which is the
		// horizon it is being kept away from.
		float ew = eye_blend * smoothstep(eye_fade_low, eye_fade_high, y);
		col = mix(col, texture(eye_panorama, euv).rgb * eye_tint * eye_energy, ew);
	}

	// LAST. Without this the land goes grey under a sky that keeps its colour, which
	// on a low shot with a lot of sky in frame is most of the picture disagreeing
	// with the effect. Draining it commits the wall to being a DOME rather than a
	// fence; that is a look decision and it is this one line.
	COLOR = golf_wall_drain_all(col, SCREEN_UV, TIME);
}
