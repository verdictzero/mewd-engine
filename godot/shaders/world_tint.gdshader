// MEWD — the world shader for an edited map's surfaces (js/material.js,
// worldShade with SECTOR_FOG): world.gdshader's light, and on top of it
// what the map compiler (DocCompile) hands each vertex —
//
//   CUSTOM0.rgb  the colour of the light on it, Doom 64's way: a sector's
//                floor, ceiling and thing colours, and its walls graded
//                from the top colour down to the bottom one
//   CUSTOM1      its sector's fog: rgb and a density 0..100, half-way in
//                at 25600/density units (GZDoom's); a < 0 for the map's
//
// and the map's ambient light (light everywhere, colour times amount)
// and default fog. The fog is the surface's own sector's, over the whole
// distance — the web build follows it from sector to sector along the
// line of sight, which this does not (yet).
//
// Faces are culled here, unlike world.gdshader: a wall between a room
// and the street wears the facade on one face and the room's own wall on
// the other, two quads in one place, each seen only from its own side.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D tex_smooth : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool use_smooth = false;
uniform bool masked = false;
uniform vec3 ambient = vec3(0.0);
uniform vec4 fog_default = vec4(0.0);
uniform float fog_ambient = 1.0;

varying float depth;
varying vec3 wpos;
varying vec3 tint;
varying vec4 fog;

void vertex() {
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tint = CUSTOM0.rgb;
	fog = CUSTOM1;
}

void fragment() {
	vec4 c = use_smooth ? texture(tex_smooth, UV) : texture(tex, UV);
	if (masked && c.a < 0.5) discard;
	vec3 albedo = c.rgb * tint;
	float l = world_band(COLOR.r, depth, COLOR.g);
	vec3 col = albedo * l * light_color.rgb + albedo * ambient + world_beam(albedo, wpos);
	col = world_air_at(col, depth, wpos - CAMERA_POSITION_WORLD);
	vec4 fg = fog.a < 0.0 ? fog_default : fog;
	if (fg.a > 0.0) {
		float ff = 1.0 - exp2(-depth * fg.a / 25600.0);
		col = mix(col, fg.rgb * light_color.rgb + ambient * fog_ambient, ff);
	}
	ALBEDO = col;
	// the thermal sight's feed: how warm, not what colour (thermal.gdshaderinc)
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(albedo, l, depth, wpos, 0.0));
}
