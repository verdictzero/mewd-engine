// MEWD — the positron column (js/beam.js VERT/FRAG).
//
// FRESNEL IS THE WHOLE DIFFERENCE between a rod and a glow. UV.x (the
// rim) at 0 is a surface lit through its face — a solid bar of light;
// at 1 a mild Fresnel; at 2 lit ONLY where it turns away from the eye,
// a shell bright at its own outline and transparent through the middle.
// All additive, so the four shells together are a white centre inside
// a yellow body inside a green corona. UV.y is the fade; COLOR the
// shell's colour.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

varying float rim;
varying float fade;

void vertex() {
	rim = UV.x;
	fade = UV.y;
}

void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// three lightings, picked by the rim — the innermost must not be a
	// Fresnel at all, or seen down the bore it is a bullseye
	float mild = 1.0 - f * 0.30;
	float shell = pow(f, 1.7) * 1.9;
	float lit = rim < 0.5 ? 1.0 : (rim < 1.5 ? mild : shell);
	// banded, like everything else that is drawn in this game
	lit = floor(lit * 10.0 + 0.5) / 10.0;
	ALBEDO = COLOR.rgb * lit * fade;
	ALPHA = 1.0;
}
