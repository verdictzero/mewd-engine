// MEWD — the arc maw's charge (js/weapon3d.js orbSprite): a soft round
// glow, always facing the eye, added onto what is behind it and never
// hidden by the gun — the ball, its halo, the flash and every mote is
// one of these, coloured and faded by its own `tint`.
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

instance uniform vec4 tint = vec4(1.0);

void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = a * a * tint.a;
}
