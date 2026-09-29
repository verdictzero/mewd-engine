// MEWD — the one world shader (js/material.js).
//
// The game has no lights. A sector's light is a number per vertex (in
// COLOR.r, with Doom's fake wall contrast already in it) and how much of
// it comes from the sky is COLOR.g; world_band does the rest — depth
// diminishing and the 32 steps — and then the air.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool masked = false;

varying float depth;
varying vec3 wpos;

void vertex() {
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (masked && c.a < 0.5) discard;
	float l = world_band(COLOR.r, depth, COLOR.g);
	// and the lance's column, if one is out or has just been (world_beam)
	ALBEDO = world_fog(world_air_at(c.rgb * world_lit(l) + world_beam(c.rgb, wpos), depth, wpos - CAMERA_POSITION_WORLD), depth);
	// the thermal sight's feed: how warm, not what colour (thermal.gdshaderinc)
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(c.rgb, l, depth, wpos, 0.0));
}
