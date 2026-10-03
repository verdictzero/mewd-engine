shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded,
		shadows_disabled, specular_disabled, fog_disabled;
#include "res://godot/shaders/thermal_base.gdshaderinc"

#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// A TWO-LAYER PARALLAX CLOUD BAND PAINTED ONTO THE HORIZON, in front of the sky
// and behind everything else. `textures/TEX_clouds_parallax_background.png` (512 x
// 256: a bank of cumulus with a transparent top half) tiled around the compass,
// twice, at two different sizes and two different speeds.
//
// `scripts/world/SCRIPT_horizon_clouds.gd` owns the geometry it draws on. This file
// owns the entire look.
//
// WHY THIS IS NOT A SKY SHADER. Godot allows exactly one sky material per
// Environment, so folding the band into `SHADER_sky_void_gradient.gdshader` would fork
// that shader per sky it is wanted over, and the band would then be UNOCCLUDABLE
// -- the sky pass runs before transparents and has no depth, so a mountain in
// front of a cloud would lose. Drawn instead as ordinary transparent geometry,
// the band composites over whatever sky is behind it and is correctly hidden by
// any terrain nearer than the shell. It is a drop-in for every scene.
//
// WHY IT IS NOT A SCREEN-SPACE OVERLAY EITHER: the same occlusion argument, plus
// a screen-space band would have to be re-derived from the camera basis to stay
// level, and would shear wrongly under roll.
//
// ---------------------------------------------------------------- the geometry
//
// The band is sampled from the VIEW DIRECTION, never from the mesh. The mesh --
// a camera-centred open cylinder -- exists only to (a) put fragments on screen
// where the band is and (b) sit far enough out that terrain depth-tests in front
// of it. Move it, resize it, swap it for a sphere: the picture does not change.
// That is what makes "always at the horizon" true rather than approximately
// true. Elevation zero is elevation zero at any altitude.
//
// The two coordinates:
//
//   u  azimuth. Wraps at 360 deg, so `repeat_enable` on the X axis IS the
//      horizontal tiling and there is no seam to hide. `*_tiles` is how many
//      copies of the 512 px image fit around the compass -- FEWER TILES MEANS
//      BIGGER CLOUDS.
//   v  tan(elevation), remapped into the band. NOT wrapped: the artwork has a
//      definite top (transparent) and a definite bottom (solid), and repeating
//      it vertically would stack cloud banks up the sky. Clamped instead, and
//      the clamp is then never reached in practice -- see `fade_end` below.
//
// tan(elevation) rather than the angle itself, because that is what a cylinder
// gives for free and it is the projection the artwork wants: a band painted on a
// cylinder compresses toward the top exactly as a real cloud bank does. It also
// costs nothing -- `dir.y / length(dir.xz)` against an `atan`.
//
// ------------------------------------------------------------- WHERE PARALLAX
//                                                                 COMES FROM
//
// Not from turning your head. Rotating a camera in place moves everything by the
// same angle no matter how far away it is -- rotation yields ZERO parallax, and
// two layers that differ only in scale would slide together and read as one flat
// wallpaper. Parallax is a TRANSLATION effect, and this is where it is bought:
//
//   an object at horizontal distance R, when the camera moves by d, shifts in
//   apparent azimuth by -(d . t_hat) / R, where t_hat is the horizontal unit
//   vector across the line of sight.
//
// Inverting that for a fragment shader -- given the azimuth `phi` a pixel looks
// along, which part of the pattern is there? -- gives
//
//   theta = phi + (C . t_hat) / R
//
// with C the camera's LOGICAL horizontal position. Small R (near layer) means a
// large shift per metre travelled, i.e. the front layer moves faster. That is
// the whole mechanism, and it is one dot product.
//
// It is a small-angle model: it holds the layer at a constant distance instead
// of letting it approach, which is precisely what "always at the horizon" asks
// for. Clouds are supposed to slide past, never to be reached.
//
// ------------------------------------------------------- AND IT HAS A HORIZON
//                                                          OF ITS OWN
//
// "Small-angle" is not decoration. Write the camera's logical offset as
// C = E * (sin a, cos a) and the view direction as p = (sin phi, cos phi); then
// C . t_hat = E sin(a - phi), so
//
//   theta(phi) = phi + (E / R) sin(a - phi)
//   dtheta/dphi = 1 - (E / R) cos(a - phi)
//
// which is NOT MONOTONIC once E exceeds R. At E = R the derivative touches zero
// at phi = a and the artwork is stretched infinitely wide along that one bearing;
// past it the derivative goes negative over an arc and the azimuth map FOLDS BACK
// ON ITSELF -- the same texture is drawn twice, mirrored, meeting at a seam. That
// is the tear this band was reported for: absent at the origin, and appearing
// after 4.5 km of travel on the front layer (R = 4500) and 16 km on the back
// (R = 16000). `SCRIPT_floating_origin.gd` does not save it, and cannot: the logical
// offset it hands over in `world_offset` is exactly the E above, and it grows
// without bound by design.
//
// NO MODEL CAN AVOID THIS. Requiring both dtheta/dphi = 1 (no warp) and
// dtheta/d(C . t_hat) = 1/R (parallax at the layer's distance) forces
// dtheta/dphi = 1 - (C . p_hat)/R, because t_hat turns with phi. Sustained
// constant-rate parallax on a constant-distance azimuthal band is not available;
// the offset that drives it has to saturate somewhere. `parallax_limit` is where.
//
// NO ALTITUDE PARALLAX, deliberately. Real cloud 4 km out would drop 7 deg if
// you climbed 500 m, and the band would leave the horizon -- so climbing is not
// wired to the vertical coordinate at all. Only horizontal travel moves it.
//
// Wind is on top of that, as a constant azimuthal drift, and is also faster on
// the front layer.
//
// --------------------------------------------------------- the floating origin
//
// C is the logical camera position, `CAMERA_POSITION_WORLD + world_offset`,
// exactly as `SHADER_cloud_plane.gdshader` anchors its noise field. A rebase moves the
// render frame by kilometres; without the accumulated offset the parallax term
// would jump by radians in the frame the origin snapped and the whole horizon
// would visibly slew.
//
// ------------------------------------------------------------ mips and the seam
//
// `filter_linear_mipmap`, and the mips are NOT inert. This comment used to claim
// they were, on the grounds that 12 tiles x 512 texels is ~1800 across a 2560 px
// supersampled frame -- but that averages over the full 107 degree horizontal
// FOV, and the tangent projection makes the screen CENTRE much denser than the
// average. Measured there: at a 2560x1440 3D buffer the front layer is at LOD
// 0.52 and the back at 0.00; at 1280x720 the front is at LOD 1.11. So the front
// layer crosses into mip 1 as soon as the render scale drops, which this project
// does on weak hardware. That has a specific and nasty consequence at the
// vertical clamp -- see sample_layer(). Raising `*_tiles` past ~12.5 or
// shrinking `*_height` below ~0.25 pushes it further.
//
// The mips are wanted regardless: `SHADER_post_dither.gdshader` snaps every pixel to a
// palette entry, which turns ordinary minification shimmer into crawling
// confetti. Same argument `SHADER_cloud_plane.gdshader` makes for its own filter mode.
//
// Mips are also why the fetches are `textureGrad` and not `texture`. `atan` has
// a branch cut, so `u` jumps by a full turn along one column of pixels; the
// hardware derivative there is enormous and selects the coarsest mip, painting a
// permanent blurred vertical stripe down the sky at world azimuth 180 deg. The
// cut is in `phi` alone and `phi`'s derivative has a closed form, so it is
// computed analytically and handed to the sampler. Everything else the fragment
// needs is continuous and can use `dFdx` directly.

group_uniforms art;
// The cloud bank. Transparent above, opaque below; the tiles wrap horizontally.
// `source_color`: this is a picture, not a data map, and it wants the sRGB decode.
//
// USE `TEX_clouds_parallax_band.png`, NOT `TEX_clouds_parallax_background.png`.
// `tools/TOOL_fix_cloud_band_alpha.py` derives the former from the latter, and the
// reason is `repeat_enable` two lines down.
//
// The original is palettized with one transparent index, so 82% of its
// transparent region is the raw key colour, teal (0, 92, 94).
// `process/fix_alpha_border` cleans a border and stops: measured on the imported
// .ctex, it rewrites 4067 texels, exactly four deep, which is enough that the
// texels bilinear can reach AT MIP 0 are 100% clean. That is where the story used
// to end, and it is wrong, because THE SAMPLER DOES NOT ALWAYS RUN AT MIP 0 --
// see the note on the vertical clamp in sample_layer(). Everything five texels or
// more inside the transparent region is still teal at every mip, and the wrap
// described there reaches straight into it.
//
// The derived file inpaints the WHOLE transparent region with cloud colour, so
// there is no key colour left anywhere for any sampler at any LOD to find, and it
// reconstructs a soft edge from the one-bit mask. The soft edge is the smaller
// half of the change and largely does not survive the palette snap; the inpaint
// is the part that matters.
uniform sampler2D cloud_band : source_color, filter_linear_mipmap, repeat_enable;
// Accumulated floating-origin rebase in metres, pushed by SCRIPT_horizon_clouds.gd.
uniform vec2 world_offset = vec2(0.0);
// Pull toward grey, and pull hard. The artwork is a blue-and-pink photographic
// cumulus, and this project's palette LUT will happily find tinted entries for
// every one of those pixels -- under a neutral overcast sky that reads as a
// colour cast rather than as weather. Applied to the COMPOSITE rather than
// per-layer, so the tints below still separate the two before it lands.
uniform float saturation : hint_range(0.0, 2.0) = 0.28;

group_uniforms parallax;
// THE CEILING ON THE PARALLAX OFFSET, as a fraction of each layer's own
// `*_distance`. Per layer rather than in metres, because what has to stay bounded
// is the ratio E/R that the fold derivation above is written in: at this value the
// azimuth map's derivative is confined to `1 +/- parallax_limit`, so it can never
// reach zero and the band can never fold.
//
// The cost is that translation parallax SATURATES. The offset is soft-limited, not
// clipped -- `|C| / sqrt(1 + (|C| / (R * parallax_limit))^2)` -- so it is exact to
// second order near the origin, rolls off smoothly, and asymptotes; there is no
// kink to see as you cross it and nothing pops. Measured against the shipped
// layers at the default 0.5: 2400 m of travel slides the back layer 8.2 degrees
// against the unlimited model's 8.6, and the front layer 20.9 against 30.6.
// Far out, both are pinned and the band's motion is the wind drift plus a slow
// swing as the bearing from the logical origin turns.
//
// 0.5 IS A COMPRESSION BUDGET, and that is the way to retune it. The worst
// azimuthal stretch anywhere in the frame is 1 / (1 - parallax_limit): 2x here,
// 3.3x at 0.7, 5x at 0.8. Since the camera spends essentially all of its time
// saturated, the saturated picture is the one to protect -- 2x is invisible on
// this artwork, and buying near-origin fidelity above ~0.6 starts to smear.
// MUST STAY UNDER 1.0. At 1.0 the fold is back. `SCRIPT_horizon_clouds.gd` warns and
// `tests/TEST_horizon_clouds.gd` asserts monotonicity out to 10,000 km.
uniform float parallax_limit : hint_range(0.05, 0.95) = 0.5;

group_uniforms back_layer;
// BIGGER AND SLOWER. Fewer tiles around the compass = each cloud spans more
// degrees; a taller band = it towers higher over the horizon. That is backwards
// from real perspective and entirely deliberate -- it is the parallax-backdrop
// convention, and it is what makes the far layer read as a distant weather front
// rather than as the same clouds again.
uniform float back_tiles : hint_range(1.0, 48.0) = 7.0;
// Band height in tan(elevation). The artwork is 2:1, so `height = PI / tiles`
// reproduces it undistorted (0.449 at 7 tiles); below that it is squashed, which
// is usually what you want for something meant to sit far away.
uniform float back_height : hint_range(0.02, 2.0) = 0.45;
// tan(elevation) of the band's BOTTOM edge. Keep it under `fade_end` -- see there.
uniform float back_base : hint_range(-1.0, 1.0) = -0.09;
// Parallax distance in metres. Larger = moves less as you fly. This is the knob
// that separates the layers; nothing else creates depth between them.
uniform float back_distance : hint_range(200.0, 60000.0) = 16000.0;
// Wind, radians of azimuth per second.
uniform float back_drift : hint_range(-0.2, 0.2) = 0.002244;
// Tile-widths of azimuthal offset, so the two layers' seams and their cloud
// masses do not start out stacked.
uniform float back_phase : hint_range(0.0, 1.0) = 0.0;
uniform float back_opacity : hint_range(0.0, 1.0) = 0.8;
// THE FAR LAYER IS THE LIGHTER OF THE TWO -- see front_tint. Its residual blue is
// what survives `saturation` as a faint cool cast, which is the other half of the
// same depth cue: distance is colder as well as paler.
uniform vec3 back_tint : source_color = vec3(0.5, 0.53, 0.58);

group_uniforms front_layer;
// SMALLER AND FASTER. More tiles, shorter band, much nearer.
uniform float front_tiles : hint_range(1.0, 48.0) = 12.0;
uniform float front_height : hint_range(0.02, 2.0) = 0.26;
uniform float front_base : hint_range(-1.0, 1.0) = -0.1;
uniform float front_distance : hint_range(200.0, 60000.0) = 4500.0;
uniform float front_drift : hint_range(-0.2, 0.2) = 0.0058178;
uniform float front_phase : hint_range(0.0, 1.0) = 0.37;
uniform float front_opacity : hint_range(0.0, 1.0) = 1.0;
// THE NEAR LAYER IS THE DARKER OF THE TWO, and that ordering is load-bearing.
// Atmospheric perspective washes distance out toward the sky, so a near cloud
// reads as a darker silhouette against a paler far one; run it the other way --
// which is where this started, with the front layer at full white -- and the
// small near puffs become the brightest thing on screen, the depth cue inverts,
// and the band flattens into one sheet.
//
// Both tints are also pitched against the CLOUD SEA below them
// (MAT_cloud_sea_volumetric's `cloud_color`, 0.34): the band has to look like the
// same weather as the deck it sits on. At full white the front layer was roughly
// three times the sea's brightest tone and glared over it.
uniform vec3 front_tint : source_color = vec3(0.38, 0.38, 0.38);

group_uniforms art_window;
// THE ARTWORK IS A PHOTOGRAPH OF A CLOUD BANK, and it is only usable over part
// of its own height. Two ends have to be dealt with, and both are dealt with
// HERE, in the artwork's own `v` -- not in elevation -- so that each layer
// windows itself wherever it happens to sit in the sky. A window in `t` would
// have to be tuned twice and would drift the moment a `*_base` or `*_height`
// moved.
//
// THE BOTTOM. Row 123 of 256 is the first row that is 100% opaque across the
// full width, and every row below it is too: the bottom 52% of the image is a
// solid wall of cloud, because in the source photograph that part is meant to be
// below the horizon. Drawn as-is each layer paints a flat opaque rectangle with
// a hard top edge, and two layers paint two of them, one above the other. That
// is the "banding" this band was reported for. Measured on the shipped setup:
// the back layer's alpha sat pinned at exactly 0.800 for every t below 0.144 and
// the front layer's at 1.000 below 0.035, with the composite over 0.99 from
// t = 0.04 all the way down.
//
// THE TOP. The band simply STOPPED at `*_base + *_height` -- there was a fade at
// its foot and nothing at all at its crown, so the top edge was a cut. Across
// the shipped band that cut measured a 4.85/255 step in a frame whose sky is
// otherwise smooth, drawn as a curved arc (a constant-elevation locus is a conic
// under a rectilinear projection, not a straight line).
//
// So alpha is windowed at both ends: in over `fade_in`, out from `solid_start`
// to `solid_end`. The clamp on `v` then costs nothing -- above the band v clamps
// to ~0 where the window is 0, below it clamps to ~1 where the window is 0 --
// which is what used to require every `*_base` to sit under `fade_end`.
uniform float art_fade_in : hint_range(0.0, 0.5) = 0.06;
// Where the artwork stops having structure worth drawing. Per-row opaque
// fraction runs 40% at v=0.125, 59% at 0.19, 77% at 0.25, 97% at 0.375: past
// about a third of the way down it is already a wall in all but name.
uniform float art_solid_start : hint_range(0.0, 1.0) = 0.30;
uniform float art_solid_end : hint_range(0.0, 1.5) = 0.78;

group_uniforms horizon_fade;
// THE FADE OUT TOWARD THE BOTTOM, in tan(elevation): opaque above `fade_start`,
// gone at `fade_end`. The band has to die INTO something rather than stop, or
// the artwork's solid bottom row draws a hard horizontal edge across the world.
//
// `fade_end` is also what keeps the vertical clamp honest. Below a layer's
// `*_base` the clamp would smear the bottom row of the image downward forever;
// with every `*_base` UNDER `fade_end`, alpha has already reached zero before v
// can reach 1, so the smear is never drawn. SCRIPT_horizon_clouds.gd asserts that
// ordering as a configuration warning and tests/TEST_horizon_clouds.gd asserts
// it against the shipped material.
uniform float fade_start : hint_range(-1.0, 1.0) = 0.045;
uniform float fade_end : hint_range(-1.0, 1.0) = -0.065;
// What it dies into. MUST be the colour the sky actually is a couple of degrees
// above the horizon -- for this project's void gradient that is the exact
// neutral 0.089 every fog in the scene is tuned to. Off by an entry and the
// band's foot draws a coloured line through the palette LUT.
uniform vec3 haze_color : source_color = vec3(0.089, 0.089, 0.089);
uniform float haze_strength : hint_range(0.0, 1.0) = 1.0;

// The two scene buses, both multipliers and both white by default: `tod_haze_tint`
// on `haze_color` (canonical note in `SHADER_terrain_splat_w2.gdshader`) and
// `tod_art_tint` on the band's own colour (canonical note in
// `SHADER_veg_billboard.gdshader`).
//
// THIS BAND IS THE SKYLINE, so between them they are most of what a day/night
// cycle looks like from anywhere on the island: the cumulus ring is what the
// horizon IS in SCENE_test_zone_W2, standing in front of a dome that is otherwise
// a flat gradient. The requirement written up in that scene's notes -- that the
// night is not dark but blood-lit, with the open sky beyond the ring going nearly
// black -- is these two multipliers pulling in opposite directions: the ring keeps
// its level and loses its green and blue, while the dome behind it (driven
// separately, on `sky_void_gradient`'s `top_color`) drops to near zero.
//
// `haze_color` STILL HAS TO BE THE COLOUR THE SKY ACTUALLY IS a couple of degrees
// above the horizon -- that requirement is untouched and is the reason the band's
// foot does not draw a line. What has changed is that both sides of it are now the
// same product: the sky's `bottom_color` is written by the cycle as its own base
// times this same haze tint. They were kept equal by hand before and are kept
// equal by construction now.
global uniform vec4 tod_haze_tint;
global uniform vec4 tod_art_tint;

group_uniforms;


// One layer. `phi`/`t`/`p` are the shared per-pixel geometry and `d_*`/`dpx`/`dpy`
// are their screen derivatives; all of them are computed once in fragment() and
// passed in, because `dFdx` must not sit behind the early-out `discard` below.
vec4 sample_layer(float tiles, float height, float base, float dist, float drift,
		float phase, float opacity, vec3 tint,
		float phi, float t, vec2 p, vec2 eye, float eye_len,
		vec2 d_phi, vec2 dpx, vec2 dpy, vec2 d_t, float v_inset,
		float clock) {
	// Tile-widths per radian of azimuth.
	float k = tiles / TAU;
	// max() rather than the hint_range floor: a hint only constrains the editor
	// slider, and a .tres written by hand can still land a zero here.
	float d_safe = max(dist, 1.0);
	float inv_d = 1.0 / d_safe;

	// THE PARALLAX OFFSET, SOFT-LIMITED AGAINST THIS LAYER'S OWN DISTANCE. `off` is
	// the logical camera offset with its magnitude taken through
	// x / sqrt(1 + (x/lim)^2): equal to `eye` to second order while |eye| is small
	// against `lim`, asymptotic to `lim`, and smooth throughout. The whole point is
	// the line after it -- `cross_c * inv_d` is now bounded by `parallax_limit`, so
	// `du/dphi = k * (1 - (off . p_hat) / dist)` cannot reach zero and the azimuth
	// map cannot fold. See the fold derivation in the header.
	//
	// The floor of 1.0 on `lim` is what stops a hand-written zero in either uniform
	// turning into 0/0; the same reason `d_safe` exists.
	float lim = max(d_safe * parallax_limit, 1.0);
	float e = eye_len / lim;
	vec2 off = eye * inversesqrt(1.0 + e * e);
	float cross_c = off.x * p.y - off.y * p.x;

	// `clock`, not TIME: the golf wall stops the backdrop with everything else. `t`
	// is this function's vertical coordinate and was here first, which is why the
	// clock has the longer name.
	float u = (phi + cross_c * inv_d + drift * clock) * k + phase;
	// `off` is uniform across the whole draw, so d(cross_c) has the same closed form
	// the cross product itself does and needs no `dFdx` of its own. That is not only
	// cheaper: differencing `cross_c` directly meant differencing a quantity that
	// grew with the distance from the logical origin, to recover a per-pixel step
	// several orders smaller than it.
	vec2 d_cross = vec2(off.x * dpx.y - off.y * dpx.x, off.x * dpy.y - off.y * dpy.x);
	vec2 du = (d_phi + d_cross * inv_d) * k;

	// v = 0 at the band's top edge, 1 at its bottom -- which is the image's own
	// orientation: row 0 is empty sky, row 255 is solid cloud.
	float inv_h = 1.0 / max(height, 1e-3);
	float v = (base + height - t) * inv_h;
	vec2 dv = -d_t * inv_h;

	// THE VERTICAL CLAMP, AND WHY THE INSET IS NOT ENOUGH ON ITS OWN.
	//
	// `repeat_enable` is both axes -- it has to be, for `u` -- so this clamp is
	// the only thing stopping the artwork wrapping vertically. The inset is half
	// a MIP-0 texel, which is exactly right at mip 0 and wrong at every other
	// level: at LOD L the clamped coordinate lands 0.5/2^L of a texel from the
	// edge, so bilinear takes texel -1 with weight 0.5 - 0.5/2^L. That is 0.000
	// at LOD 0 but 0.250 at LOD 1, and texel -1 wraps to the artwork's LAST row,
	// which is 100% opaque at every mip.
	//
	// The band is not reliably at mip 0. Measured at a 1280x720 3D buffer the
	// front layer sits at LOD 1.11 (it is 2.08 texels per pixel), and this
	// project lowers `scaling_3d/scale` on weak hardware, so that is a shipped
	// configuration and not a corner case. The result was a flat, IDENTICAL-AT-
	// EVERY-AZIMUTH veil of alpha ~0.26 painted over the whole 47% of the band
	// above the front layer's top, in the teal of the artwork's mip row 0, cut
	// off at its foot by a hard horizontal line -- measured 8.86/255, the largest
	// step anywhere in the frame, and the single thing that made the band read as
	// two stacked cloud banks.
	//
	// What actually fixes it is the art window below, which is evaluated on the
	// UNCLAMPED `v` and is therefore exactly zero wherever the clamp binds. The
	// inset stays because it is still correct at mip 0 and costs nothing. Note
	// this makes `art_solid_end <= 1.0` load-bearing, not cosmetic: push it past
	// 1 and there is a live region where the window is open and the clamp binds
	// at the same time. `tests/TEST_horizon_clouds.gd` asserts it.
	vec2 uv = vec2(u, clamp(v, v_inset, 1.0 - v_inset));
	vec4 c = textureGrad(cloud_band, uv, vec2(du.x, dv.x), vec2(du.y, dv.y));
	c.rgb *= tint;
	// The window is evaluated on the UNCLAMPED v, so that everything outside the
	// band is zero rather than whatever the clamped edge row happens to hold.
	c.a *= opacity * smoothstep(0.0, max(art_fade_in, 1e-4), v)
			* (1.0 - smoothstep(art_solid_start,
					max(art_solid_end, art_solid_start + 1e-4), v));
	return c;
}


void fragment() {
	// World position and the view ray, recovered the way terrain_splat and
	// cloud_plane do it -- from VERTEX and INV_VIEW_MATRIX, both scene-data
	// uniforms rather than varyings. This shader adds ZERO varying pressure,
	// which is the constraint that matters on the Broadcom V3D's 16-varying cap.
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 dir = wp - CAMERA_POSITION_WORLD;

	// Horizontal direction, normalised. Normalising BEFORE the cross product in
	// sample_layer keeps that product's operands at camera-position scale instead
	// of (camera x shell radius), which at a 9 km shell is a factor of 9000 of
	// needless cancellation in a float32 subtraction.
	float l = max(length(vec2(dir.x, dir.z)), 1e-6);
	vec2 p = vec2(dir.x, dir.z) / l;
	float phi = atan(p.x, p.y);
	float t = dir.y / l;   // tan(elevation)

	// The camera's LOGICAL horizontal position, which is the C of the parallax
	// derivation. Only its component ACROSS the line of sight produces parallax;
	// that cross product, and the soft limit that keeps it from folding the band,
	// are per-layer and live in sample_layer.
	vec2 eye = CAMERA_POSITION_WORLD.xz + world_offset;
	// Hoisted: `eye` is the same for both layers and this shader is inlined twice,
	// so the square root is paid once instead of per layer.
	float eye_len = length(eye);

	// Derivatives, all of them before any discard so the 2x2 quads are intact.
	// `phi` gets the closed form -- for a unit p, d(atan2) reduces to exactly
	// this cross product -- because the hardware derivative of `phi` is garbage
	// on the branch cut. `t` is continuous everywhere and can be differenced
	// directly; `p`'s own derivatives go through so each layer can build its
	// parallax term's derivative in closed form too.
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	vec2 d_phi = vec2(p.y * dpx.x - p.x * dpx.y, p.y * dpy.x - p.x * dpy.y);
	vec2 d_t = vec2(dFdx(t), dFdy(t));

	// Early out above the taller band's top and below the fade. Both regions are
	// provably alpha 0, and the shell is sized with margin around the band, so
	// this is where most of its fragments leave. Safe here and nowhere earlier:
	// every derivative above is already resolved, and the fetches below are
	// textureGrad, which does not need any more.
	if (t > max(back_base + back_height, front_base + front_height) || t < fade_end) {
		discard;
	}

	float v_inset = 0.5 / float(textureSize(cloud_band, 0).y);

	// THE SHELL IS ALWAYS OUTSIDE. It hangs at 9 km and chases the camera, so every
	// fragment of it is far beyond any hole's capsule and the mask returns the drain
	// unmodified — no special case needed, and none wanted: routing it through the
	// same call as everything else is what keeps the backdrop stopping in step with
	// the land rather than on a rule of its own.
	float wall_clock = golf_wall_time(TIME, wp.xz);

	vec4 b = sample_layer(back_tiles, back_height, back_base, back_distance,
			back_drift, back_phase, back_opacity, back_tint,
			phi, t, p, eye, eye_len, d_phi, dpx, dpy, d_t, v_inset, wall_clock);
	vec4 f = sample_layer(front_tiles, front_height, front_base, front_distance,
			front_drift, front_phase, front_opacity, front_tint,
			phi, t, p, eye, eye_len, d_phi, dpx, dpy, d_t, v_inset, wall_clock);

	// Front over back, un-premultiplied. Written out rather than as two mixes
	// because the colour has to be divided back out by the combined alpha; skip
	// that and every partly-transparent edge darkens toward black.
	float a = f.a + b.a * (1.0 - f.a);
	vec3 col = (f.rgb * f.a + b.rgb * b.a * (1.0 - f.a)) / max(a, 1e-4);

	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, saturation);

	// AFTER the desaturation and BEFORE the haze, and both halves of that matter.
	//
	// After, because `saturation` is aimed at the ARTWORK -- blue-and-pink
	// photographic cumulus that the palette LUT would otherwise find tinted entries
	// for all over -- and it is pulled down to 0.28 for that reason. Tint first and
	// the scene's own colour is most of what that 0.28 throws away, so a blood-red
	// night would arrive at the screen as a grey one.
	//
	// Before, because the haze carries its own multiplier and is a different
	// quantity: this is the light on the cloud, that is the air in front of it.
	col *= tod_art_tint.rgb;

	// Converge on the haze colour BEFORE the alpha goes, so the band's foot is
	// already indistinguishable from the sky by the time it stops being drawn --
	// the same ordering, and for the same reason, as cloud_plane's horizon ring.
	float fade = smoothstep(fade_end, fade_start, t);
	col = mix(haze_color * tod_haze_tint.rgb, col, mix(1.0, fade, haze_strength));
	a *= fade;

	if (a < 0.004) {
		discard;
	}

	ALBEDO = golf_wall_drain(col, wp.xz, SCREEN_UV, TIME);
	ALPHA = a;
	// THE THERMAL SIGHT's feed (godot/shaders/thermal_base.gdshaderinc):
	// only people are hot, and this is not one
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_cold(ALBEDO, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
