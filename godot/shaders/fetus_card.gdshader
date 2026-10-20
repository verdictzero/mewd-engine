// MEWD — the fetus launcher's shot (game/fetuses.gd): the user's fetus in
// its sac (assets/things/fetus.png), a card turned to the eye as a standee
// is. One MultiMesh; each instance is
//   origin       the card's middle, in the game's world (as Standees)
//   basis x.x    its width, x.y its height (units), x.z its spin (radians)
//   basis y.x    its rock: the width times this (cos of a tumble about its
//                upright, never under FLAT — FetusLauncher.FLAT — so it
//                turns and turns over as it flies but is never a line)
// Its own picture, cut out at the alpha (a picture with an edge, not a
// ragged piece: that is sprite_chunk.gdshader, which the splat's pieces
// use), lit and hazed as the world's sprites are, and a BODY to the
// thermal sight — the one thing in the air that is warm.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D picture : filter_nearest;

varying float depth;

void vertex() {
	// (the rows are under the Game, scaled by game_unit like everything in
	// it: a size comes out of the matrix in the world's units already, and
	// the spin and the rock are taken back out of it)
	vec3 mid = MODEL_MATRIX[3].xyz;
	float w = MODEL_MATRIX[0].x;
	float h = MODEL_MATRIX[0].y;
	float spin = MODEL_MATRIX[0].z / game_unit;
	float flip = MODEL_MATRIX[1].x / game_unit;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	float f = sign(flip) * max(abs(flip), 0.7);
	if (flip == 0.0) f = 1.0;
	vec2 q = vec2(VERTEX.x * w * f, (VERTEX.y - 0.5) * h);
	float c = cos(spin);
	float s = sin(spin);
	q = vec2(q.x * c - q.y * s, q.x * s + q.y * c);
	vec3 world = mid + right * q.x + up * q.y;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	depth = -VERTEX.z;
}

void fragment() {
	// (its own texels, never a mip)
	vec4 c = textureLod(picture, UV, 0.0);
	if (c.a < 0.5) discard;
	ALBEDO = world_fog(world_air(c.rgb * world_lit(world_band(1.0, depth, 1.0)), depth), depth);
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_body(c.rgb, depth));
}
