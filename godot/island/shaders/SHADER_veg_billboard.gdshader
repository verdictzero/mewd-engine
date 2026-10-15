shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled;

// EVERY PLANT: the firs, the broadleaves, the bushes, the ferns and the grass.
// Y-axis (cylindrical) camera-plane billboards — the quad keeps world up and
// yaws to face the camera, so a plant reads upright from any side and never
// shears against its neighbours on a slope. SCRIPT_veg_scatter.gd and
// SCRIPT_grass_scatter.gd draw through it; a class of plant is a material (the
// texture bound and where its fades lie), not another shader.
//
// AS LIGHT AS A PLANT CAN BE, AND SIMPLY LIT (at the user's request: "make
// sure veg only accepts ambient light, doesn't cast shadows, maybe even make
// it use an approximated bake so vegetation stays as lightweight as
// possible", then "maybe let's make the veg simple lit no shadows?"):
//
//   * SIMPLE LIGHT, worked out here and not by the engine (`unshaded`, as the
//     ground's is): the sky's light, and the sun's on a plant drawn as if it
//     were round — a normal out of the card, turned toward its sides across
//     it (`roundness`) and up toward its top, so the side toward the sun is
//     lit and the far side is in the sky's light alone (`sun_wrap` how far
//     round the sun reaches) — and THE SUN THROUGH THE LEAVES when the eye
//     looks toward it (`translucency`): grass against a low sun glows.
//     Off the same tod_* globals as the ground (SHADERINC_island_light).
//     ALL OF IT AT THE CARD'S FOUR CORNERS (at the user's request: "vertex
//     only?"), and blended across it by the rasteriser: the round normal
//     runs straight across the card, so its light hardly bends between
//     them, and a pixel of a plant — of which a meadow draws many deep —
//     is the picture times two colours and nothing more.
//   * NO SHADOW MAPS: none cast (the scatters switch the instances' casting
//     off, and `shadows_disabled`) and none received. Where a real place has
//     its mountains' shadows baked (EarthSun) and its clouds', the sun's share
//     at the plant is read at its corners, at its middle (SHADERINC_earth_sun),
//     so a meadow in a mountain's evening shadow stays in it; elsewhere 1.
//   * A BAKED LIGHT of its own, worked out once where the scatter places it
//     (how open the sky is over it: under a canopy, down in a hollow or on a
//     ridge) and carried in the instance's custom data (`INSTANCE_CUSTOM.x`;
//     0, unset, reads as 1). One multiply.
//
// THE FOOT ON THE SLOPE: where the scatter gives the ground's gradient under
// a plant (`INSTANCE_CUSTOM.yz`, 0.5 + a quarter of it, with .w 1 to say so:
// the grass), the card is sheared up and down with the ground across it, so
// its foot follows the slope whichever way the eye looks — not stood level
// over it, one side hanging, and not sunk by the worst case either, which
// buried the thick bottom of every tuft on a steep meadow.
//
// THE GROUND'S COLOUR (at the user's request: "make sure grass etc (not
// trees) matches the grass of the terrain splat it is on, for blending /
// visual consistencies sake"): a low plant's material sets `ground_match`,
// and its colour is taken toward the colour of the ground at its foot
// (SHADERINC_earth_ground: the splat SHADER_terrain_earth paints there, its
// layers, tints, variation and exposure): each texel takes the ground's
// colour at its own brightness against the pictures' average
// (`ground_reference`, tools/earth_pack.py `means`), so the plant keeps its
// light and shade and wears the ground's hue (scaled channel by channel
// instead, a green tuft went violet on a grey path), all the way at its
// foot and `ground_match_top` of the way at its top: a tuft grows out of the
// turf in the turf's own green, browner on soil, greyer on scree. The
// ground's colour is found at the corners with the light, a texel's in one
// dot product. The trees leave it at 0.
//
// What is left: the billboard, a sway in the wind, the RETRO picture's texel
// grid (`lofi_texels_per_m`: a plant drawn at so many texels a metre, never
// finer than its picture; 0 is the picture's own), the near and far fades
// (screen-door, so the plant stays opaque and sorted) and the island's fog.

// the plant's picture: nearest for the texel grid, and the same picture
// filtered for when it is drawn smaller than its texels (minified)
uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform sampler2D albedo_smooth : source_color, filter_linear_mipmap;
uniform float lofi_texels_per_m = 32.0;
uniform float lofi_min_texels = 64.0;
// the quad's size in the instance's metres (the scatter sets it)
uniform vec2 quad_size = vec2(1.0, 1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.4;
uniform vec3 tint : source_color = vec3(1.0);
// half the plants mirrored, by where they stand
uniform bool flip_variants = true;

group_uniforms light;
// how far round the plant the sun reaches: 0 the lit half, 1 all but its back
uniform float sun_wrap = 0.45;
uniform float sun_strength = 1.0;
uniform float sky_strength = 1.0;
// how far a card's sides turn from the eye, as if the plant were round
uniform float roundness = 0.7;
// the sun through the leaves, seen against it, and its colour (0 none)
uniform float translucency = 0.7;
uniform vec3 translucent_color : source_color = vec3(1.0, 0.92, 0.5);

group_uniforms ground;
// how far toward the ground's colour (0 not at all: the trees), at the foot
// and, of that, at the top; and how bright the ground's colour is taken (a
// lit blade is brighter than a photograph of turf from above, gaps and all)
uniform float ground_match : hint_range(0.0, 1.0) = 0.0;
uniform float ground_match_top : hint_range(0.0, 1.0) = 0.6;
uniform float ground_level = 1.0;
// the average colour of this material's pictures, linear, as numbers
// (sprites.json "means": its class's)
uniform vec3 ground_reference = vec3(0.13, 0.15, 0.03);

group_uniforms wind;
uniform float wind_strength = 0.055;
uniform float wind_speed = 0.9;
uniform float wind_scale = 11.0;

group_uniforms near_fade;
// gone this close, whole by this far (metres); 0 and 0 off
uniform float near_gone = 3.0;
uniform float near_solid = 10.0;
// by the plant's own distance rather than each texel's
uniform bool near_fade_whole_plant = false;

group_uniforms far_fade;
uniform float far_start = 900.0;
uniform float far_end = 1300.0;

group_uniforms fog;
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

group_uniforms;

// the island's light, and its air (its sky sets them)
global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
global uniform vec4 tod_sky_color;
global uniform vec4 tod_ground_color;
global uniform vec4 tod_haze_tint;
global uniform float tod_fog_density;
global uniform float tod_fog_near;

varying flat vec2 v_cells;
varying flat float v_flip;
varying flat float v_near;
// the light at this corner (times the plant's tint), and the sun shining
// through it (times the picture)
varying vec3 v_lit;
varying vec3 v_glow;
// the ground's colour over the pictures' average brightness, and how far
// toward it (SHADERINC_earth_ground; 0 none)
varying flat vec3 v_ground;
varying float v_match;

const vec3 LUMA_LIN = vec3(0.2126, 0.7152, 0.0722);

#include "res://godot/island/shaders/SHADERINC_earth_sun.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_earth_cliff.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_earth_ground.gdshaderinc"

const float BAYER[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float bayer4(vec2 fc) {
	return BAYER[int(mod(fc.x, 4.0)) + int(mod(fc.y, 4.0)) * 4] / 16.0;
}

// (off the plant's undisplaced anchor, so all four corners agree)
float flip_of(vec2 wp) {
	vec2 q = floor(wp * 10.0);
	return step(0.5, fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453));
}

void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec2 tex_size = vec2(textureSize(albedo_tex, 0));
	v_cells = tex_size;
	if (lofi_texels_per_m > 0.0) {
		vec2 world = vec2(sx * quad_size.x, sy * quad_size.y);
		v_cells = clamp(max(world * lofi_texels_per_m, vec2(lofi_min_texels)), vec2(1.0), tex_size);
	}
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(right - up * dot(up, right));
	vec3 fwd = normalize(cross(right, up));
	mat4 m;
	m[0] = vec4(right * sx, 0.0);
	m[1] = vec4(up * sy, 0.0);
	m[2] = vec4(fwd * sx, 0.0);
	m[3] = MODEL_MATRIX[3];
	vec3 anchor = MODEL_MATRIX[3].xyz;
	if (wind_strength > 0.0) {
		// the top leans, the foot stays put
		float phase = (anchor.x + anchor.z) / max(wind_scale, 1e-3) + TIME * wind_speed;
		float lean = (1.0 - UV.y) * wind_strength * sin(phase);
		m[3].xyz += right * lean + fwd * lean * 0.5;
	}
	if (INSTANCE_CUSTOM.w > 0.5) {
		vec2 grad = (INSTANCE_CUSTOM.yz - 0.5) * 4.0;
		m[3].y += dot(grad, right.xz) * sx * VERTEX.x;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	v_near = length((VIEW_MATRIX * vec4(anchor, 1.0)).xyz);
	v_flip = flip_variants ? flip_of(anchor.xz) : 0.0;
	// THE LIGHT, here at the corner (see the header): a round plant's normal
	// off the flat card, the sun on it and the sky's light, and the sun
	// through the leaves when the eye looks toward it
	float baked = INSTANCE_CUSTOM.x > 0.0 ? INSTANCE_CUSTOM.x : 1.0;
	// (the sun's share at the plant's middle, the same at all four corners)
	float open = earth_sun_open(anchor + up * (sy * quad_size.y * 0.5));
	vec3 n = normalize(right * ((UV.x * 2.0 - 1.0) * roundness)
			+ up * (0.25 + 0.5 * (1.0 - UV.y)) + fwd * (1.0 - 0.5 * roundness));
	float diffuse = clamp((dot(n, tod_sun_dir) + sun_wrap) / (1.0 + sun_wrap), 0.0, 1.0);
	vec3 corner = (m * vec4(VERTEX, 1.0)).xyz;
	vec3 eye_dir = normalize(corner - INV_VIEW_MATRIX[3].xyz);
	float through = pow(clamp(dot(eye_dir, tod_sun_dir), 0.0, 1.0), 3.0) * translucency;
	vec3 sky = mix(tod_ground_color.rgb, tod_sky_color.rgb, 0.5 + 0.5 * n.y) * sky_strength;
	vec3 sun = tod_sun_color.rgb * open * sun_strength;
	// THE GROUND'S COLOUR at the foot (see the header)
	v_ground = vec3(0.0);
	v_match = 0.0;
	if (ground_match > 0.0) {
		vec3 g = earth_ground(anchor.xz);
		if (g.x >= 0.0) {
			v_ground = g * ground_level / max(dot(ground_reference, LUMA_LIN), 1e-4);
			v_match = ground_match * mix(ground_match_top, 1.0, UV.y);
		}
	}
	v_lit = tint * baked * (sky + sun * diffuse);
	v_glow = translucent_color * sun * through * baked;
}

void fragment() {
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, v_flip), UV.y);
	vec2 duvx = dFdx(uv);
	vec2 duvy = dFdy(uv);
	// drawn smaller than its texels: the filtered picture, not the nearest
	vec2 foot = max(abs(duvx), abs(duvy)) * vec2(textureSize(albedo_tex, 0));
	float minified = clamp(log2(max(max(foot.x, foot.y), 1e-6)), 0.0, 1.0);
	uv = (floor(uv * v_cells) + 0.5) / v_cells;
	vec4 tex = mix(textureLod(albedo_tex, uv, 0.0), textureGrad(albedo_smooth, uv, duvx, duvy), minified);
	if (tex.a < alpha_scissor) {
		discard;
	}
	float d = length(VERTEX);
	float near_d = near_fade_whole_plant ? v_near : d;
	float vis = (near_solid > near_gone ? smoothstep(near_gone, near_solid, near_d) : 1.0)
			* (1.0 - smoothstep(far_start, far_end, d));
	if (bayer4(FRAGCOORD.xy) >= vis) {
		discard;
	}
	vec3 alb = tex.rgb;
	if (v_match > 0.0) {
		alb = mix(alb, v_ground * dot(alb, LUMA_LIN), v_match);
	}
	vec3 col = alb * (v_lit + v_glow);
	if (fog_enabled) {
		float fd = max(d - fog_distance_start * tod_fog_near, 0.0) * fog_distance_density * tod_fog_density;
		col = mix(col, fog_color * tod_haze_tint.rgb, 1.0 - exp(-pow(fd, fog_distance_power)));
	}
	ALBEDO = col;
}
