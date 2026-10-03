shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded,
		shadows_disabled, specular_disabled, fog_disabled;

#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// RAYMARCHED VOLUMETRIC CLOUD SEA. A bounded horizontal slab of cloud the islands
// float in — the thing the flat height fog was standing in for. One enormous quad
// sits at the slab's TOP (`sea_top`); for every pixel that looks at it, fragment()
// marches the view ray through the slab [sea_top - thickness .. sea_top], samples a
// world-anchored density field, and integrates Beer-Lambert transmittance to a
// colour + alpha. The quad is only a trigger surface — the volume is reconstructed
// from the camera ray, so the clouds have real depth and parallax, not a painted
// plane.
//
// WHY A SINGLE QUAD AND A FRAGMENT MARCH. The Compatibility renderer has no
// volumetric fog and no compute shaders, so a fragment raymarch is the whole
// toolbox. Cost is bounded three ways: the slab is thin so the marched segment is
// short, `steps` is a hard low budget (dial it down on weak GPUs), and rays that
// never cross the slab (looking up into clear sky) do zero work. `depth_draw_never`
// + the default depth TEST means terrain in front of the sea occludes it for free,
// and terrain BELOW the surface is hidden by the sea drawing over it — exactly how
// a sea should behave.
//
// PALETTE DISCIPLINE (shared with cloud_plane / sky_void_gradient): every colour
// here is an EXACT NEUTRAL (r == g == b). SHADER_post_dither.gdshader snaps each pixel to
// the nearest palette entry -- ps1-soft in every scene that uses this shader, NOT
// the allstars-void this comment used to name -- and the smallest hue bias lets a
// tinted entry win and paints a stripe.
//
// WHICH palette matters, because ps1-soft does not return a neutral for a neutral
// everywhere. Measured straight out of `palette/LUT_ps1-soft.png`: a grey
// input comes back TINTED in the dark cells (0.07 -> (16,16,24) blue, 0.13 ->
// (32,32,40) blue, 0.20 -> (48,56,48) GREEN) and warm in the bright ones (0.73 and
// up). Only cells 4..10, about 0.28..0.66 of the output range, return a true
// neutral. Anything large and flat has to be pitched into that middle band or the
// LUT tints it for you -- which is what used to paint a blue-green stripe along
// this scene's horizon.
//
// WORLD-ANCHORED, ORIGIN-STABLE. Density UVs come from WORLD xz + `world_offset`
// (the accumulated floating-origin rebase, pushed by SCRIPT_cloud_sea.gd), so sliding the
// camera-following quad moves no cloud and an origin snap does not reshuffle the
// sky. No custom varyings — world position is rebuilt from VERTEX and
// INV_VIEW_MATRIX, keeping varying pressure at zero for the Broadcom V3D cap.

const int MAX_STEPS = 48;

group_uniforms slab;
// World Y of the sea surface and how far down the cloud volume extends.
uniform float sea_top = -8.0;
uniform float thickness : hint_range(10.0, 800.0) = 170.0;
// Cheap safety cap on the marched distance so a near-horizontal ray inside the slab
// cannot march to the horizon at full step density.
uniform float max_march = 6000.0;
// THE performance dial. Fewer steps = cheaper and chunkier; the start jitter keeps
// even a low count from banding. Hard-capped at MAX_STEPS by the compiled loop.
uniform int steps : hint_range(4, 48) = 22;

group_uniforms field;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 world_offset = vec2(0.0);
// Two world-scale layers combined by DIFFERENCE (as in SHADER_cloud_plane.gdshader):
// subtracting B from A opens holes and frays edges instead of unioning into soup.
uniform float scale_a : hint_range(200.0, 6000.0) = 1400.0;
uniform vec2 wind_a = vec2(6.0, 2.0);
uniform float scale_b : hint_range(80.0, 3000.0) = 560.0;
uniform vec2 wind_b = vec2(-9.0, 5.0);
uniform float detail_weight : hint_range(0.0, 1.0) = 0.5;

group_uniforms shape;
// A SOLID sea, no holes. The noise does NOT punch coverage gaps; it only sculpts
// the height of the billowing TOP SURFACE. Everything from that surface down to the
// floor is filled cloud, so no ray can ever see through the mass to the void — only
// the top undulates. `bump_amp` is how tall those billows are, in metres.
uniform float bump_amp : hint_range(0.0, 400.0) = 70.0;
// Soft skin just under the surface and a soft fade to the floor, both in metres, so
// the solid body still reads as cloud rather than a poured slab.
uniform float top_round : hint_range(0.0, 160.0) = 26.0;
uniform float bottom_round : hint_range(0.0, 200.0) = 90.0;
// Optical density -> how fast the march goes opaque. Higher = denser, whiter sea.
uniform float density_gain : hint_range(0.1, 8.0) = 3.2;

group_uniforms colour;
// UNLIT vertical tonal gradient. No sun term and no self-shadow — the only shading
// is a function of a sample's HEIGHT in the slab, so it stays sun-independent while
// giving the billows form: `cloud_color` at the tops fading down to
// `cloud_bottom_color` at the base. Exact neutrals for the palette LUT.
//
// `cloud_bottom_color` IS NOT PART OF THE HAZE FAMILY, whatever this comment used
// to say. It is the BASE of the sea's own internal gradient -- the dark in the
// troughs between billows, which is the only thing giving the sea any form at all
// -- and it is deliberately left at 0.089 while `fog_color` and every other haze
// colour in the scene sits at 0.30. Raising it to match would flatten the gradient
// to nothing AND move the sea's mean tone, which is the quantity the whole haze
// family is tuned against: every fog colour in the scene would have to be
// re-derived from it. Leave it alone.
uniform vec3 cloud_color : source_color = vec3(0.34, 0.34, 0.34);
uniform vec3 cloud_bottom_color : source_color = vec3(0.089, 0.089, 0.089);

group_uniforms fog;
// THE SEA IS IN THE WEATHER, not in front of it. Every marched sample is faded
// toward `fog_color` by ITS OWN distance from the camera, so the far side of the
// sea dissolves into the same haze a distant island does, and the boundary
// between "cloud" and "fog" stops existing. Without this the sea was the one
// surface in the scene with no atmospheric attenuation at all: it held full
// contrast to the quad's rim and then stopped.
//
// PER SAMPLE, NOT PER FRAGMENT, and that is the whole reason this is done in the
// shader rather than by dropping `fog_disabled` and letting the engine do it.
// The engine fogs a fragment at ONE depth -- for this shader that is where the
// view ray crosses the trigger quad at `sea_top`, which for a grazing ray is
// kilometres from the cloud actually being looked at. A volume has to be fogged
// where its mass is.
//
// THE MODEL IS THE TERRAIN'S, not the Environment's, and deliberately so: what
// has to blend here is the sea against the islands sitting in it, and
// `SHADER_terrain_splat_w2.gdshader` / `SHADER_cliff_wall.gdshader` roll their own
// `1 - exp(-(max(d - start, 0) * density)^power)`. Matching the Environment
// instead would leave the sea and the cliff converging at different rates on the
// same screen. Keep these three numbers equal to the terrain's.
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

// The two scene buses, both multipliers and both white by default: `tod_haze_tint`
// on the fog above (canonical note in `SHADER_terrain_splat_w2.gdshader`) and
// `tod_art_tint` on the two colour uniforms above that (canonical note in
// `SHADER_veg_billboard.gdshader`). Applied in fragment() where they are hoisted out of
// the march; the "keep these three numbers equal to the terrain's" rule the fog
// block states now holds for the tint too, and holds automatically.
global uniform vec4 tod_haze_tint;
global uniform vec4 tod_art_tint;

group_uniforms fades;
// XZ-RADIAL from the camera (not 3D distance), so the ring does not shrink as you
// climb. rim_fade_end must stay under the quad's half-size.
//
// This used to converge the colour to a `horizon_color` as well. It no longer
// needs to: at `horizon_fade_start` the fog above is already saturated (at 3800 m
// the exponent is 12.5, i.e. transmittance 4e-6), so the colour mix had nothing
// left to do. What remains is the ALPHA half, which is a different job and still
// load-bearing -- going fully OPAQUE at the horizon rather than to zero means the
// far sea occludes whatever is behind it, the other deck's rim or an island the
// streamer has not dropped yet. Fading to zero would put those back on screen.
uniform float horizon_fade_start = 3800.0;
uniform float horizon_fade_end = 5200.0;
uniform float rim_fade_start = 5600.0;
uniform float rim_fade_end = 5960.0;

group_uniforms;


// Cloud density at a world point, 0..~1. The mass is SOLID: the noise only sets the
// height of the billowing top surface; from that surface down to the floor the slab
// is filled, so no ray can punch a hole through to the void. Density is 0 above the
// local surface and below the floor, and ramps to ~1 through the body (soft skin
// under the surface, soft fade at the floor) so it still reads as cloud.
// `clock` is the golf wall's, not TIME — see `SHADERINC_golf_wall.gdshaderinc`.
// PASSED IN rather than resolved here because this runs once per MARCH STEP: the
// mask is worth one evaluation per fragment, not `MAX_STEPS` of them, and a ray
// crossing the boundary mid-march would make the slab partly frozen along its own
// length, which is not a thing a cloud can look like.
float density_at(vec3 wp, float clock) {
	float sea_bottom = sea_top - thickness;
	if (wp.y < sea_bottom) {
		return 0.0;
	}
	vec2 p = wp.xz + world_offset;
	float ta = texture(cloud_noise, (p + wind_a * clock) / max(scale_a, 1e-3)).r;
	float tb = texture(cloud_noise, (p + wind_b * clock) / max(scale_b, 1e-3)).r;
	float f = clamp((ta - tb * detail_weight) * 1.6 + 0.2, 0.0, 1.0);

	// f == 1 peaks reach sea_top; f == 0 valleys sit bump_amp lower. The surface is
	// single-valued in xz, so the top undulates but never opens.
	float surface_y = sea_top - (1.0 - f) * bump_amp;
	if (wp.y > surface_y) {
		return 0.0;
	}
	float below = surface_y - wp.y;       // depth under the local top surface
	float above_floor = wp.y - sea_bottom;
	return smoothstep(0.0, max(top_round, 1e-3), below)
			* smoothstep(0.0, max(bottom_round, 1e-3), above_floor);
}


void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wp - ro);

	// ONE MASK EVALUATION FOR THE WHOLE RAY, off this fragment's own world point.
	// `wp.xz` and NOT `wp.xz + world_offset`: the wall is published in render space
	// and `world_offset` is what takes a point to the LOGICAL frame, which is the
	// frame the noise wants and the mask does not.
	float wall_clock = golf_wall_time(TIME, wp.xz);

	// Ray vs slab [sea_bottom, sea_top]. Guard the near-horizontal ray (rd.y ~ 0):
	// it is inside the slab only if the camera itself is, and then it runs the full
	// capped distance.
	float sea_bottom = sea_top - thickness;
	float t_enter;
	float t_exit;
	if (abs(rd.y) < 1e-4) {
		if (ro.y < sea_bottom || ro.y > sea_top) {
			discard;
		}
		t_enter = 0.0;
		t_exit = max_march;
	} else {
		float t_top = (sea_top - ro.y) / rd.y;
		float t_bot = (sea_bottom - ro.y) / rd.y;
		t_enter = max(min(t_top, t_bot), 0.0);
		t_exit = min(max(t_top, t_bot), max_march);
	}
	if (t_exit <= t_enter) {
		discard;
	}

	int nsteps = clamp(steps, 1, MAX_STEPS);
	float seg = t_exit - t_enter;
	float dt = seg / float(nsteps);
	// Jitter the start a fraction of a step by screen position, so the low step
	// count does not band the sea into visible shells; the palette LUT would lock
	// those bands to the screen otherwise.
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);

	// THE TWO BUSES, RESOLVED ONCE AND HOISTED OUT OF THE MARCH. Each is one
	// multiply and the loop below runs 22 of everything inside it; there is no
	// reason for either to be paid per sample when neither varies along the ray.
	//
	// The sea is the largest unlit surface in SCENE_test_zone_W2 -- a 12 km deck
	// under an island that is 2.5 km across -- so `tod_art_tint` reaching it is
	// most of what "the light is filtering through blood" means in that scene: the
	// gradient below keeps its whole internal shape and the tops and troughs are
	// recoloured together. `tod_haze_tint` is the same multiplier the terrain, the
	// cliff and the sky's own bottom edge take, which is what keeps this sea and
	// the islands sitting in it converging on one colour at range.
	vec3 art_top = cloud_color * tod_art_tint.rgb;
	vec3 art_bottom = cloud_bottom_color * tod_art_tint.rgb;
	vec3 haze_col = fog_color * tod_haze_tint.rgb;

	// Unlit tonal gradient: colour each sample by its HEIGHT in the slab (tops =
	// cloud_color, base = cloud_bottom_color) and accumulate front-to-back weighted by
	// how much it absorbs, so the visible tone follows the billow surface. No sun.
	float transmittance = 1.0;
	vec3 col_accum = vec3(0.0);
	for (int i = 0; i < MAX_STEPS; i++) {
		if (i >= nsteps) {
			break;
		}
		float t = t_enter + (float(i) + jitter) * dt;
		vec3 sp = ro + rd * t;
		float dens = density_at(sp, wall_clock) * density_gain;
		if (dens > 0.001) {
			float hfrac = clamp((sp.y - sea_bottom) / max(thickness, 1e-3), 0.0, 1.0);
			vec3 sample_col = mix(art_bottom, art_top, hfrac);
			// `t` is already the Euclidean distance from the camera to this
			// sample, because `rd` is normalised -- the same quantity the terrain
			// shader fogs on as `length(VERTEX)`.
			if (fog_enabled) {
				float fd = max(t - fog_distance_start, 0.0) * fog_distance_density;
				sample_col = mix(sample_col, haze_col,
						1.0 - exp(-pow(fd, fog_distance_power)));
			}
			float d_trans = exp(-dens * dt);
			float absorbed = (1.0 - d_trans) * transmittance;
			col_accum += absorbed * sample_col;
			transmittance *= d_trans;
			if (transmittance < 0.02) {
				break;
			}
		}
	}

	float alpha = 1.0 - transmittance;
	// The no-hit fallback has to be the FOG colour, not `cloud_color`. It is only
	// ever seen where `horizon_fade` below forces alpha to 1 on a ray that found
	// no cloud at all, and that is at 3800 m and beyond, where the fog is
	// saturated -- so `cloud_color` there would paint an unfogged patch of the
	// sea's brightest tone into the middle of the haze.
	vec3 col = alpha > 1e-4 ? col_accum / alpha
			: (fog_enabled ? haze_col : art_top);

	// Close the sheet up at the horizon, then drop alpha entirely inside a zone the
	// fog has already made indistinguishable from the sky, so the quad edge can
	// never show. The colour is the fog's job now; see the `fog` group.
	float d = distance(wp.xz, CAMERA_POSITION_WORLD.xz);
	float hz = smoothstep(horizon_fade_start, horizon_fade_end, d);
	alpha = mix(alpha, 1.0, hz);
	alpha *= 1.0 - smoothstep(rim_fade_start, rim_fade_end, d);

	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = golf_wall_drain(col, wp.xz, SCREEN_UV, TIME);
	ALPHA = alpha;
}
