// MEWD — the forest floor, and what the fire leaves of it (js/forest.js
// GROUND_VERT / GROUND_FRAG).
//
// THE GROUND BURNS WITH THE WOOD. One texel of `mask` per 64-unit cell —
// the cell's burn progress — sampled with filtering, crossfading needle
// litter into charred dirt; so a burnt patch of wood is black to the
// ground and stays that way. The mesh is in world space (node at the
// origin), the forest's rects at height zero.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D ground_map : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D burnt_map : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D mask : filter_linear, repeat_disable;
// origin x, origin y, 1/width, 1/height (map space)
uniform vec4 mask_rect;
uniform float light = 0.56;
uniform float u_time = 0.0;

const vec3 RAMP[8] = {
	vec3(0.094, 0.063, 0.031), vec3(0.188, 0.125, 0.0), vec3(0.314, 0.188, 0.0), vec3(0.439, 0.251, 0.0),
	vec3(0.596, 0.345, 0.0), vec3(0.753, 0.471, 0.125), vec3(0.910, 0.596, 0.345), vec3(0.973, 0.816, 0.627)
};

varying vec3 world;
varying float depth;

void vertex() {
	world = VERTEX;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 mp = vec2(world.x, -world.z);            // back to map space
	vec2 uv = mp / 128.0;                          // one texel to a unit
	vec3 g = texture(ground_map, uv).rgb;
	vec3 b = texture(burnt_map, uv * 1.37).rgb;
	float burn = texture(mask, (mp - mask_rect.xy) * mask_rect.zw).r;
	/* The char boundary is ragged by the floor's own texture, so the edge
	   of a burn follows the litter rather than the grid. */
	float lum = dot(g, vec3(0.333));
	float k = smoothstep(0.06, 0.55, burn + (lum - 0.5) * 0.3);
	/* the char tile is painted for a crater at noon; lifted, and never
	   the whole way, so burnt ground is dark ground and not black */
	vec3 col = mix(g, min(vec3(1.0), b * 1.9 + 0.06), k * 0.85);
	float l = world_band(light, depth, 1.0);
	vec3 c = world_fog(world_air(col * world_lit(l), depth), depth);
	/* Fresh char glows: a band in the middle of the burn, gone when cold. */
	float q = (burn - 0.5) / 0.26;
	float glow = exp(-q * q) * (0.75 + 0.25 * sin(u_time * 7.0 + mp.x * 0.09 + mp.y * 0.07));
	glow *= step(0.02, burn) * (1.0 - smoothstep(0.88, 1.0, burn));
	glow *= 0.35 + 0.65 * smoothstep(0.25, 0.7, lum);   // through the litter, not over it
	c += RAMP[int(floor(clamp(glow, 0.0, 1.0) * 6.0 + 0.5))] * glow * 0.85;
	ALBEDO = c;
	// the thermal sight's feed: the ground, and the fresh char warm
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, l, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0) + thermal_glow(RAMP[int(floor(clamp(glow, 0.0, 1.0) * 6.0 + 0.5))] * glow * 0.85));
}
