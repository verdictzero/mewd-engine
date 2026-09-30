// MEWD — the forest floor (js/forest.js GROUND_VERT / GROUND_FRAG, less
// the burning: the fire that spread is gone, at the user's request).
//
// The mesh is in world space (node at the origin), the forest's rects
// at height zero; the litter tiles one texel to a unit.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D ground_map : source_color, filter_nearest_mipmap, repeat_enable;
uniform float light = 0.56;
uniform float u_time = 0.0;

varying vec3 world;
varying float depth;

void vertex() {
	world = VERTEX;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 mp = vec2(world.x, -world.z);            // back to map space
	vec2 uv = mp / 128.0;                          // one texel to a unit
	vec3 col = texture(ground_map, uv).rgb;
	float l = world_band(light, depth, 1.0);
	ALBEDO = world_fog(world_air(col * world_lit(l), depth), depth);
	// the thermal sight's feed: the ground as a surface
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, l, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0));
}
