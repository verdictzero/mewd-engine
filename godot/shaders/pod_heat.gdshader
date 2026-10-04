// MEWD — THE DROP POD'S HEAT SHIELD GLOWING on the way in (DropPod: the
// hull's material_overlay while it burns). Added over the hull's own
// picture: orange-white at the foot of the shield, dull red up the side,
// nothing past `top` metres up; `heat` (0..1) as the reentry fire's. In
// the hull mesh's own metres (its foot at 0).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float top = 3.2;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float k = clamp(lp.y / top, 0.0, 1.0);
	float glow = pow(1.0 - k, 2.2);
	// a slow churn in it, so the metal seems to boil
	float wob = 0.85 + 0.15 * sin(lp.x * 3.1 + TIME * 5.0) * sin(lp.z * 2.7 - TIME * 4.0);
	vec3 col = mix(vec3(1.0, 0.78, 0.45), vec3(0.85, 0.16, 0.03), smoothstep(0.0, 0.7, k));
	ALBEDO = col * 1.7;
	ALPHA = clamp(glow * wob * heat, 0.0, 1.0);
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = vec3(0.0);
}
