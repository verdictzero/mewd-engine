// MEWD — a flame over a burning cell (js/fire.js render, js/fireart.js).
// One MultiMesh per flame set; each instance's origin is the foot, and
// INSTANCE_CUSTOM carries
//   x  the cell in the strip (the frame)
//   y  the width, in units
//   z  the height, in units
// ADDITIVE and writing no depth: light adds, and it is the adding that
// makes a mass of flame read as a source of light rather than as a
// picture of some flames. Fullbright; the air still takes it at range.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, skip_vertex_transform, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D strip : source_color, filter_nearest;
uniform float cells = 1.0;

varying float depth;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	vec3 feet = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// the eye's right, flattened: the card turns about Y only
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 world = feet + right * VERTEX.x * cd.y + vec3(0.0, VERTEX.y * cd.z, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	depth = -VERTEX.z;
	UV = vec2((cd.x + UV.x) / cells, UV.y);
}

void fragment() {
	vec4 c = texture(strip, UV);
	// the air: an added light fades out rather than toward a colour
	float at = clamp((depth - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	ALBEDO = c.rgb * (1.0 - at * at);
	// the thermal sight's feed: fire is the hottest thing there is
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(1.0 - at * at);
	ALPHA = c.a;
}
