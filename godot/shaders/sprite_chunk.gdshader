// MEWD — a piece torn out of a sprite (render/sprite_chunks.gd): a little
// card cut from a sprite's own picture, flying and tumbling, turned to the
// eye as a standee is. One MultiMesh per picture; each instance is
//   origin       the piece's middle, in the game's world (as Standees)
//   basis x.x    its width, x.y its height (units), x.z its spin (radians)
//   basis y.x    how far gone, 0 whole .. 1 faded away
//   basis y.y    how wet: 0 its own colours .. 1 run red (a body's piece)
//   custom       the rectangle of the picture it was cut from (u0, v0, du, dv)
// and the piece is cut ROUND, ragged at the edge, so it reads as torn and
// not as a square of picture. It goes the way a plant goes (at the user's
// request, SHADER_veg_billboard's screen door): fading away and, a plant's
// piece, close to the eye, it dithers out through the same ordered 4x4
// Bayer matrix the plants' near fade does, not a speckle.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D picture : filter_nearest;
// 1: the picture is sRGB as loaded (a plant's); 0: decoded already (a strip's)
uniform bool srgb = false;
// A PLANT'S PIECE fades out close to the eye as the plants do (metres: gone
// inside `near_gone`, whole past `near_solid`); a body's piece does not
uniform bool near_fade = false;
uniform float near_gone = 1.5;
uniform float near_solid = 4.0;

// SHADER_veg_billboard.gdshader's Bayer matrix, entry for entry
const float bayer[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float bayer4(vec2 fragcoord) {
	int x = int(mod(fragcoord.x, 4.0));
	int y = int(mod(fragcoord.y, 4.0));
	return bayer[x + y * 4] / 16.0;
}

varying float depth;
varying float gone;
varying float wet;
varying vec2 local;
varying float seed;

void vertex() {
	// (the rows are under the Game, scaled by game_unit like everything in
	// it: a size comes out of the matrix in the world's units already, and
	// the spin and the two fractions are taken back out of it)
	vec3 mid = MODEL_MATRIX[3].xyz;
	float w = MODEL_MATRIX[0].x;
	float h = MODEL_MATRIX[0].y;
	float spin = MODEL_MATRIX[0].z / game_unit;
	gone = MODEL_MATRIX[1].x / game_unit;
	wet = MODEL_MATRIX[1].y / game_unit;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 q = vec2(VERTEX.x * w, (VERTEX.y - 0.5) * h);
	float c = cos(spin);
	float s = sin(spin);
	q = vec2(q.x * c - q.y * s, q.x * s + q.y * c);
	vec3 world = mid + right * q.x + up * q.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	depth = -VERTEX.z;
	// A PIECE TOO SMALL TO SEE IS NOT DRAWN (at the user's request: far off,
	// a cloud of pieces a pixel or two across read as coloured glitter):
	// under about three pixels on screen it collapses to nothing
	vec4 mid_v = VIEW_MATRIX * vec4(mid, 1.0);
	float px = max(w, h) * PROJECTION_MATRIX[1][1] * 0.5 * VIEWPORT_SIZE.y / max(-mid_v.z, 1e-3);
	if (px < 3.0 || mid_v.z > 0.0) VERTEX = vec3(0.0, 0.0, 1.0);
	local = UV * 2.0 - 1.0;
	seed = fract(sin(dot(mid.xz, vec2(12.9898, 78.233))) * 43758.5453);
	vec4 r = INSTANCE_CUSTOM;
	UV = r.xy + UV * r.zw;
}

void fragment() {
	// ragged and round: the edge wanders with the angle round the middle
	float a = atan(local.y, local.x);
	float edge = 0.78 + 0.16 * sin(a * 5.0 + seed * 20.0) + 0.08 * sin(a * 11.0 + seed * 7.0);
	if (length(local) > edge) discard;
	// (its own texels, never a mip: a picture's mips run the colours of its
	// clear texels into the leaf, which is the glitter again)
	vec4 c = textureLod(picture, UV, 0.0);
	if (srgb) c.rgb = mix(c.rgb / 12.92, pow((c.rgb + 0.055) / 1.055, vec3(2.4)), step(0.04045, c.rgb));
	if (c.a < 0.5) discard;
	// fading away, and a plant's piece near the eye: the screen door
	float vis = 1.0 - gone;
	if (near_fade) {
		// (the depth in metres whichever world it is: the island is drawn
		// in metres, a map in the game's units, 32 to the metre)
		float m = game_unit < 0.5 ? depth : depth / 32.0;
		vis *= smoothstep(near_gone, near_solid, m);
	}
	if (bayer4(FRAGCOORD.xy) >= vis) discard;
	// a body's piece runs red, darkest at its torn edge
	float rim = smoothstep(edge - 0.3, edge, length(local));
	c.rgb = mix(c.rgb, mix(vec3(0.32, 0.0, 0.0), vec3(0.12, 0.0, 0.0), rim), wet * (0.35 + 0.6 * rim));
	ALBEDO = world_fog(world_air(c.rgb * world_lit(world_band(1.0, depth, 1.0)), depth), depth);
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(c.rgb, 1.0, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0));
}
