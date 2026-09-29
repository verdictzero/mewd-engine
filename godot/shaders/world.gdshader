// MEWD — the one world shader (js/material.js, worldBand).
//
// The game has no lights. A sector's light is a number per vertex (in
// COLOR.r, with Doom's fake wall contrast already in it) and how much of
// it comes from the sky is COLOR.g. This diminishes it with depth —
// linearly, as Doom did, stretched under the sky — and steps it into
// 32 levels, Doom's 32 colormaps: the line that makes it look right.
// Then the air: a surface fades toward the sky's horizon colour between
// air_near and air_far, which is also the draw distance.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool masked = false;
uniform float light_falloff = 1400.0;
uniform float min_light = 0.12;
uniform float sky_light = 0.85;
uniform float global_light = 1.0;
uniform float air_near = 1200.0;
uniform float air_far = 14000.0;
uniform vec3 air_color : source_color = vec3(0.55, 0.62, 0.72);
uniform vec3 light_color : source_color = vec3(1.0);

varying float depth;

void vertex() {
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

float world_band(float light_in, float d, float sky) {
	float fall = light_falloff * mix(1.0, 3.4, sky);
	float mn = min(0.85, min_light + 0.32 * sky);
	float li = mix(light_in, max(light_in, sky_light), sky);
	mn = mix(mn, 1.0, clamp(sky_light, 0.0, 1.0) * sky);
	float dim = 1.0 - clamp(d / fall, 0.0, 1.0);
	float l = li * mix(mn, 1.0, dim) * global_light;
	return floor(l * 32.0 + 0.5) / 32.0;
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (masked && c.a < 0.5) discard;
	float l = world_band(COLOR.r, depth, COLOR.g);
	vec3 col = c.rgb * l * light_color;
	float at = clamp((depth - air_near) / max(1.0, air_far - air_near), 0.0, 1.0);
	ALBEDO = mix(col, air_color, at * at);
}
