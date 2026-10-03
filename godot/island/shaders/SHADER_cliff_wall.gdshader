shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://godot/shaders/thermal_base.gdshaderinc"

#include "res://godot/island/shaders/SHADERINC_island_light.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// The sheer wall under an island's shoulder — the bands `chunk_mesher._build_rim`
// sweeps from the handoff ring down to the tip.
//
// IT IS THE TERRAIN'S ROCK LAYER, LIFTED, and here that is a requirement rather
// than a nicety. The shoulder above this is part of the WALKABLE SURFACE mesh and
// is therefore drawn by `SHADER_terrain_splat_w2.gdshader` — the profile hands over from
// one mesh to the other partway down a single continuous curve, some 28 m below
// the shore and well above the cloud deck, in plain view. Two materials meeting
// mid-curve is only invisible if they are the same rock: the same texture, the
// same `rock_scale`, the same tint, sampled at the same world coordinates. So
// this is a verbatim port of that shader's rock channel, and
// `MAT_cliff_wall.tres` carries the same seven numbers `MAT_terrain_splat_w2.tres`
// does. `tests/TEST_island_world.gd` asserts they agree.
//
// WHAT THIS REPLACES. `SHADER_cliff_gradient.gdshader` painted the old bare cone: an
// OBJECT-SPACE side projection over a vertical grey ramp. Object space was the
// right call for what it was — a texture pinned to the landform survives a
// floating-origin rebase — but it cannot be reconciled with a shoulder that
// samples in world space, and the shoulder is the half you actually look at. So
// the whole rim maps in world space now and slides together on a rebase, which
// is what the ground above it has always done.
//
// DITHER, NOT ALPHA, and this fixed a defect rather than changing a style. The
// old cone was `cull_disabled` AND alpha-blended, so it tested depth without
// writing it — meaning the near wall never occluded the far one. Its fade band
// had to be kept short (70..240 m) not to show more wall but to stop showing the
// FAR wall through the near, which read as pale vertical curtains hanging under
// the island; the material's own notes record two failed attempts to lengthen it.
// A screen-door discard keeps the material opaque and depth-writing, so the far
// side is properly hidden, and the fade is then free to run as deep as the
// geometry does.

group_uniforms rock;
// `dark_rock_02`. THE SAME TEXTURE THE TERRAIN'S ROCK CHANNEL USES — see above.
// Nearest filtering with mipmaps on, matching the ground: the 128 px bakes out of
// `scripts/SCRIPT_crunch_art.gd` are quantised, and sampling them bilinearly smears them
// back into the photograph they came from.
uniform sampler2D rock_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
/// Metres per tile. Matches `MAT_terrain_splat_w2.tres`'s `rock_scale`, and has
/// to: the texture runs continuously from the shoulder into the wall under it,
/// and two different scales make that join a visible seam.
uniform float rock_scale = 12.0;
/// LINEAR per-channel multiplier, not a colour — `dark_rock_02` averages 0.043
/// 0.034 0.025 and the grade that puts it where the palette wants it is well
/// above 1.0.
uniform vec3 rock_tint = vec3(1.0);
/// How hard the `pow(abs(n), sharpness)` blend commits to one projection plane.
///
/// THIS IS ALSO WHAT MAKES THE MESH NORMAL A TEXTURE INPUT rather than only a
/// lighting one, which is worth knowing before blaming the rock for a smear. At
/// 4 the blend has effectively picked an axis by the time the normal is 45
/// degrees off it, so a normal that disagrees with the face it sits on by more
/// than that selects a plane lying ALONG the wall instead of across it — and
/// world position barely moves within that plane as you travel round the island,
/// so the rock stretches into horizontal streaks. The rim's normals did exactly
/// that until `chunk_mesher._coast_out`; see there for the whole story.
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
/// The sampled rock's own MEAN, per channel, in the linear space the sampler
/// returns — 0.043 0.034 0.025 for the shipped 128 px `dark_rock_02` bake.
uniform vec3 rock_mean = vec3(1.0);
/// How much of the texture's own range reaches the surface, as a mix toward
/// `rock_mean`. 1.0 is the raw sample, i.e. exactly what the terrain draws.
///
/// Under 1 here for the palette's sake rather than the rock's. A mix toward the
/// mean leaves the mean untouched, so the wall still averages to the terrain's
/// rock exactly; what it bounds is the BOTTOM of the range. On the ground rock is
/// one channel of a splat and is nearly always mixed with something; on a wall it
/// is the whole surface, and it then goes through depth darkening and slope
/// shading before `SHADER_post_dither.gdshader` snaps the result to an RGB332 palette
/// whose darkest step is 36/255.
uniform float rock_contrast : hint_range(0.0, 1.5) = 0.70;

group_uniforms turf;
// THE GRASS OVER THE EDGE (at the user's request, CANDY LAND: "take the grass
// texture to the edge of the island, beyond the edge, then the rock cliff
// texture for the island's sides"): the top `turf_depth` metres of the wall
// are the ground's own grass, hanging over the lip with a scalloped hem
// (`turf_wobble` metres of it either way, along the wall), and rock below.
// 0 (the default) leaves the wall rock to its top, as every other island's.
uniform sampler2D turf_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float turf_scale = 4.0;
uniform vec3 turf_tint = vec3(1.0);
uniform float turf_depth = 0.0;
uniform float turf_wobble = 0.8;

group_uniforms lighting;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
/// Cheap ambient-occlusion-ish darkening on steep ground, carried over from the
/// terrain so relief reads the same on the wall as on the scree above it.
///
/// SHIPPED AT ZERO now the island is unlit. `1 - (1 - n.y) * k` is a hand-rolled
/// approximation of the hemisphere term in `SHADERINC_island_light.gdshaderinc`, which does
/// the same job properly, continuously, and in colour rather than in level — so
/// leaving both on double-counts the one axis they share. Kept as a knob because
/// it is still the cheapest way to push relief around if the ball needs help.
uniform float slope_shade : hint_range(0.0, 1.0) = 0.0;
// The unlit response curve. HAS TO MATCH `MAT_terrain_splat_w2.tres`: the shoulder
// above this wall is drawn by the terrain shader and the two meet mid-curve on a
// shared ring in plain sight, so a different curve either side of it is a seam in
// the shading exactly where the albedo was made seamless. Colours are not here —
// they are the `tod_*` globals, shared by construction.
uniform float sun_bands : hint_range(0.0, 12.0) = 4.0;
uniform float sun_wrap : hint_range(0.0, 1.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.25;
/// Match the terrain's shading model. OFF, in step with the surface: the wall's
/// normals are taken analytically from the sweep profile in
/// `chunk_mesher._emit_column` — never averaged from faces, precisely so
/// neighbouring columns agree — which makes them smooth and band-free all the way
/// down. On, the geometric face normal is used instead, for a faceted look.
uniform bool flat_shading = false;

group_uniforms sea;
// THE WALL DISSOLVES INTO THE CLOUD SEA, and it is anchored to the sea's own
// altitude in WORLD Y rather than to a depth below the shore.
//
// WHAT THIS REPLACES, and why depth-below-shore was the wrong axis. The wall used
// to multiply its albedo down to `deep_level` (0.72) over a linear ramp running
// `dark_start`..`dark_start + dark_depth` — 20 to 66 m under the shore. Three
// things made that read as a hard BLACK BAND across the middle of every cliff
// rather than as depth:
//
//   * IT WAS LINEAR, so the derivative jumped at both ends. The onset landed
//     exactly on the shoulder handoff ring, where the material changes too, and
//     matching the LEVEL there (which it did) does not help when the SLOPE steps
//     from 0 to -0.28/46 per metre. The eye reads a derivative break as an edge —
//     that is a Mach band, and it was the crease.
//   * `post_dither` QUANTISES TO SIXTEEN LEVELS, and a linear ramp is the worst
//     possible input to a quantiser: it comes out as four evenly spaced contour
//     lines following the coastline all the way round the island.
//   * IT DARKENED ALBEDO, driving the wall into the bottom two or three palette
//     entries where each step is proportionally enormous. `deep_level` had already
//     been walked 0.55 -> 0.72 once because 0.55 quantised parts of the wall UNDER
//     the palette's darkest step and punched holes in it.
//
// And it never finished on screen. The ramp ran to 66 m below the shore while the
// cloud deck covers everything under y = -45, so the bottom third of it was always
// hidden — the wall started darkening, then got cut off mid-ramp by cloud.
//
// So: no depth term at all now. The wall leaves the shoulder identical to the
// terrain drawing it — continuous by construction, which is the same argument the
// header makes for sharing the rock texture — and the only thing that happens to
// it further down is that it fades into the deck it is entering, on a smoothstep,
// toward the deck's own colour.
//
// ANCHORED IN WORLD Y, WHICH IS SAFE HERE. `FloatingOrigin.horizontal_only` is on
// in SCENE_test_zone_W2 (`SCRIPT_floating_origin.gd:63` shifts x and z only), so render-
// space Y is logical Y and a fixed altitude stays fixed across a rebase. The two
// globals below come from `SCRIPT_cloud_sea.gd`, which is the declared single source of
// truth for the altitude and reads the colour off the cloud material itself.
global uniform float sea_surface_y;
global uniform vec4 sea_surface_color;
/// Metres ABOVE the sea surface at which the fade begins. Some lead-in is wanted:
/// the deck's billows rise to meet the wall (`bump_amp` 75 m of relief on a
/// surface whose peaks reach `sea_top`), so rock that is technically still in
/// clear air is already up against cloud.
uniform float sea_fade_above = 14.0;
/// Metres BELOW the surface by which the wall has become the deck exactly. Kept
/// short — the deck is opaque a little way in, so anything longer is spent
/// somewhere nobody can see, which is the mistake the old ramp made.
uniform float sea_fade_below = 26.0;

group_uniforms dissolve;
/// Fade band, in metres below the shore. Free to be long now the material is
/// opaque — see the header on why the old one could not be.
uniform float fade_start = 150.0;
uniform float fade_end = 330.0;

group_uniforms fog;
// HAS TO MATCH `MAT_terrain_splat_w2.tres` exactly — the wall and the ground
// above it are in the same picture at the same range, and the last time the two
// disagreed the result was a band of crisp rock hanging under a hazed-out island.
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.089, 0.089, 0.089);
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

// The haze bus -- a multiplier on `fog_color`, white by default. The canonical
// note is in `SHADER_terrain_splat_w2.gdshader`, and the "has to match" above is why this
// shader cannot opt out of it: the wall and the ground are one picture.
global uniform vec4 tod_haze_tint;

// The art bus -- a multiplier on the albedo of everything the lighting model never
// reaches. This shader IS lit (through SHADERINC_island_light.gdshaderinc), so it is not the
// wall that wants it: it is `sea_surface_color`, the cloud deck's tone, which the
// wall fades into on its way under the deck. Canonical note in
// `SHADER_veg_billboard.gdshader`.
global uniform vec4 tod_art_tint;

// Height below the coastline, in metres, exactly. `chunk_mesher` emits every rim
// vertex relative to the island's centre-axis pivot and `island_world` parents
// the band under a holder sitting at that pivot with no local transform — so a
// vertex's model-space Y IS its height below the shore, whatever the floating
// origin has done to the render world.
varying float v_depth;

// 4x4 ordered Bayer, as thresholds in (0,1). Ordered rather than hashed on
// purpose: the whole scene is already an ordered-dither look, and a noise
// threshold would crawl under the palette LUT.
const float BAYER[16] = float[16](
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0);

float bayer4(vec2 fc) {
	int i = int(mod(fc.y, 4.0)) * 4 + int(mod(fc.x, 4.0));
	return (BAYER[i] + 0.5) * 0.0625;
}

void vertex() {
	v_depth = max(-VERTEX.y, 0.0);
}

void fragment() {
	// Render-space world position, exactly as `SHADER_terrain_splat_w2.gdshader` derives
	// it, so the two sample the same texture at the same coordinates.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 smooth_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_normal;
	if (flat_shading) {
		// Face normal from world-position derivatives, oriented into the mesh
		// normal's hemisphere (the raw cross-product sign is not dependable).
		vec3 fn = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
		world_normal = dot(fn, smooth_n) < 0.0 ? -fn : fn;
	} else {
		world_normal = smooth_n;
	}
	// No FRONT_FACING flip: under `cull_disabled` NORMAL already arrives turned
	// toward the viewer on a back face, so a flip here turned it away again. See
	// `SHADER_terrain_splat_w2.gdshader`.

	// ---- rock: full triplanar, verbatim from the terrain's rock channel -----
	vec3 bw = pow(abs(world_normal), vec3(triplanar_sharpness));
	bw /= max(bw.x + bw.y + bw.z, 1e-5);
	float rs = max(rock_scale, 1e-4);
	vec3 rock = texture(rock_albedo, world_pos.zy / rs).rgb * bw.x
			+ texture(rock_albedo, world_pos.xz / rs).rgb * bw.y
			+ texture(rock_albedo, world_pos.xy / rs).rgb * bw.z;
	vec3 albedo = mix(rock_mean, rock, rock_contrast) * rock_tint;

	// ---- the turf over the lip: grass down to a scalloped hem ---------------
	if (turf_depth > 0.0) {
		float ts = max(turf_scale, 1e-4);
		vec3 turf = texture(turf_albedo, world_pos.zy / ts).rgb * bw.x
				+ texture(turf_albedo, world_pos.xz / ts).rgb * bw.y
				+ texture(turf_albedo, world_pos.xy / ts).rgb * bw.z;
		// the hem: two waves along the wall (in whichever of x and z it runs)
		// and a finer third, so it hangs in tufts and not in a ruled line
		float a = world_pos.x + world_pos.z;
		float hem = turf_depth + turf_wobble * (0.55 * sin(a * 0.73) + 0.3 * sin(a * 1.91 + 1.3)
				+ 0.15 * sin(a * 4.7 + 0.4));
		albedo = v_depth < hem ? turf * turf_tint : albedo;
	}

	// UDN-style perturbation: each projection's tangent xy drives the two world
	// axes that projection spans.
	vec3 rnx = texture(rock_normal, world_pos.zy / rs).xyz * 2.0 - 1.0;
	vec3 rny = texture(rock_normal, world_pos.xz / rs).xyz * 2.0 - 1.0;
	vec3 rnz = texture(rock_normal, world_pos.xy / rs).xyz * 2.0 - 1.0;
	vec3 npert = vec3(0.0, rnx.y, rnx.x) * bw.x
			+ vec3(rny.x, 0.0, rny.y) * bw.y
			+ vec3(rnz.x, rnz.y, 0.0) * bw.z;
	vec3 shaded_n = normalize(world_normal + npert * normal_strength);

	float slope = clamp(1.0 - world_normal.y, 0.0, 1.0);
	albedo *= 1.0 - slope * slope_shade;

	// UNLIT: this multiply IS the lighting, and it is the SAME function the terrain
	// above the handoff ring calls with the same four numbers. See
	// `SHADERINC_island_light.gdshaderinc`.
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	albedo *= island_light(shaded_n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);

	// ---- dissolve, never blend (see the header) -----------------------------
	if (1.0 - smoothstep(fade_start, fade_end, v_depth) < bayer4(FRAGCOORD.xy)) {
		discard;
	}

	// ---- the two veils, composited once --------------------------------------
	// ORDER MATTERS AND IS PHYSICAL. The sea fade happens AT the wall; the distance
	// haze happens in the air between the wall and the eye. So the sea's colour is
	// attenuated by the fog and the fog's is not, which is ordinary front-to-back
	// compositing:
	//
	//     coverage = 1 - (1 - sea)(1 - fog)
	//     colour   = sea_col * sea * (1 - fog) + fog_col * fog
	//
	// Both go on AFTER the light term, for the same reason: neither is a property
	// of the surface's own shading. With `sea` at 0 this is exactly the distance
	// fog the shader has always had.
	//
	// A STRAIGHT MIX, because the surface is unlit. This used to drain ALBEDO to
	// black and put the target colour in EMISSION, with SPECULAR dragged down
	// alongside — the whole dance existed because zeroing ALBEDO does not make a
	// LIT fragment unlit, and the 4% f0 that SPECULAR's 0.5 default implies is
	// several times the palette's headroom over the void sky, so a fully hazed wall
	// still silhouetted against it. With no light term there is nothing to survive.
	float sea = 1.0 - smoothstep(sea_surface_y - sea_fade_below,
			sea_surface_y + sea_fade_above, world_pos.y);
	float fog = 0.0;
	if (fog_enabled) {
		// VERTEX is view-space here, so its length is the true camera distance —
		// the same quantity the terrain shader fogs on.
		float fd = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
		fog = 1.0 - exp(-pow(fd, fog_distance_power));
	}
	float veil = 1.0 - (1.0 - sea) * (1.0 - fog);
	// BOTH HALVES TAKE A TINT AND THEY ARE NOT THE SAME TINT. `fog_color` is haze,
	// so it takes `tod_haze_tint`. `sea_surface_color` is the cloud deck's own
	// surface tone, republished off MAT_cloud_sea_volumetric by `SCRIPT_cloud_sea.gd` --
	// unlit artwork, exactly like the cloud sea it was read from -- so it takes
	// `tod_art_tint`, which is the same multiplier `SHADER_cloud_volumetric.gdshader`
	// applies to that colour where it paints it. The wall has to dissolve into the
	// deck as the deck actually looks, not as it looked at noon.
	vec3 veil_col = sea_surface_color.rgb * tod_art_tint.rgb * sea * (1.0 - fog)
			+ fog_color * tod_haze_tint.rgb * fog;
	// `veil_col` is already premultiplied by coverage (the two terms sum to `veil`
	// when the colours are equal), so it is added rather than mixed in.
	albedo = mix(albedo, vec3(0.0), veil) + veil_col;

	// AFTER THE VEIL, for the same reason the terrain drains after its fog: the
	// wall grades the finished picture. The cliff is always outside any hole —
	// a course sits on the tableland, the wall hangs off its edge — so in practice
	// this drains wholesale, and it has to, or the island would keep a coloured
	// skirt under a grey top.
	albedo = golf_wall_drain(albedo, world_pos.xz, SCREEN_UV, TIME);

	ALBEDO = albedo;
	// THE THERMAL SIGHT's feed (godot/shaders/thermal_base.gdshaderinc):
	// only people are hot, and this is not one
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_cold(ALBEDO, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
