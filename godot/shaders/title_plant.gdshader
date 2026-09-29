// MEWD — a cutout on the title's level (js/titlescene.js, mono()).
// Its picture, times its row's tint (the air in front of it), taken to
// GREY — the blue comes later, over the dither, in the lo-fi pass — and,
// for the plants, bent in the WIND: AGGRESSIVE, at the user's request,
// gusts that roll along the row and nearly die between, a sway, and a
// whip at the tips. The root stays put and the push goes as the square
// of the height, so a tuft curls over rather than tipping like a board.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D map : source_color, filter_nearest_mipmap, repeat_enable;
uniform float tint = 1.0;
uniform float sway = 0.0;
uniform float wind_time = 0.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool cutout = true;

void vertex() {
	if (sway > 0.0) {
		float wx = MODEL_MATRIX[3].x, sx = MODEL_MATRIX[0].x, hy = MODEL_MATRIX[1].y;
		float gust = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(wind_time * 0.45 - wx * 0.06), 2.0)
		           + 0.25 * sin(wind_time * 1.1 - wx * 0.13);
		float bend = sin(wind_time * 1.9 - wx * 0.27) + 0.45 * sin(wind_time * 4.3 + wx * 1.7)
		           + 0.2 * sin(wind_time * 9.1 + wx * 3.3) * VERTEX.y;
		float up = VERTEX.y * VERTEX.y;
		VERTEX.x += sway * hy * up * gust * (0.8 + bend) / sx;
	}
	UV = UV * uv_scale + uv_offset;
}

void fragment() {
	vec4 c = texture(map, UV);
	if (cutout && c.a < 0.5) discard;
	ALBEDO = vec3(dot(c.rgb * tint, vec3(0.299, 0.587, 0.114)));
}
