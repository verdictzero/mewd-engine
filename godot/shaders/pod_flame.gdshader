// MEWD — THE DROP POD'S THRUSTER FLAMES (DropPod `flames`): a cone per
// nozzle, all in one MultiMesh. The cone is CylinderMesh's, its point at
// local +y; the instance colour is the flame's colour (rgb) and, in its
// alpha, which end of the cone the nozzle is at:
//   0  the cone's BASE — the RCS, at the user's request ("rcs thruster
//      cones need to be reversed / blue shifted"): wide at the nozzle,
//      narrowing to a point out along the jet, and blue
//   1  the cone's POINT — the retros, as they were: a plume spreading out
//      from the nozzle, orange
// Pale at the nozzle, the flame's own colour deepening further out, gone
// at the far end; soft at the cone's sides (thickest seen through its
// middle). MIXED, NOT ADDED, so it keeps its colour against the bright sky
// (added, a blue jet over the sky is white). Unlit, no depth written.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

varying float along;
varying vec4 tint;

void vertex() {
	// the cone runs -0.5 (its base) to +0.5 (its point) in local y
	along = VERTEX.y + 0.5;
	tint = COLOR;
}

void fragment() {
	// how far out from the nozzle, 0 at it, 1 at the flame's far end
	float out_k = tint.a > 0.5 ? 1.0 - along : along;
	// a pale core at the nozzle, the flame's own colour deepening out along
	// it: a blue jet has to be darker than the sky it is seen against, and
	// its core lighter, to be seen at all
	float core = 1.0 - smoothstep(0.0, 0.3, out_k);
	vec3 pale = mix(tint.rgb, vec3(1.0), 0.5);
	vec3 deep = tint.rgb * mix(1.0, 0.6, smoothstep(0.3, 1.0, out_k));
	vec3 col = mix(deep, pale, core);
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = pow(1.0 - out_k, 0.6) * (0.55 + 0.45 * face);
	ALBEDO = col;
	ALPHA = clamp(a * 1.4, 0.0, 0.97);
	// the thermal sight sees only people
	if (thermal_on(VIEWPORT_SIZE)) ALPHA = 0.0;
}
