// MEWD — a standee: a sprite that turns about the vertical to face the
// eye, Doom's billboard (js/standees.js). One MultiMesh per strip; each
// instance's origin is the feet, and INSTANCE_CUSTOM carries
//   x  the cell in the strip
//   y  the light (sector light times the actor's own `lit`)
//   z  how much of that light is sky
//   w  flags: +1 mirrored, +2 fullbright
// The quad is `cell` units: a sprite is drawn one unit to the pixel.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"

uniform sampler2D strip : source_color, filter_nearest;
uniform float cells = 1.0;
uniform vec2 cell = vec2(40.0, 64.0);

varying float depth;
varying float light;
varying float sky;
varying float fullbright;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float flags = cd.w;
	float mirror = mod(flags, 2.0);
	fullbright = step(1.5, flags);
	light = cd.y;
	sky = cd.z;
	vec3 feet = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// the eye's right, flattened: the card turns about Y only
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 world = feet + right * VERTEX.x * cell.x + vec3(0.0, VERTEX.y * cell.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	depth = -VERTEX.z;
	float u = mirror > 0.5 ? 1.0 - UV.x : UV.x;
	UV = vec2((cd.x + u) / cells, UV.y);
}

void fragment() {
	vec4 c = texture(strip, UV);
	if (c.a < 0.5) discard;
	float l = mix(world_band(light, depth, sky), 1.0, fullbright);
	ALBEDO = world_air(c.rgb * l * light_color.rgb, depth);
}
