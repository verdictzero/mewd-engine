// MEWD — THE DROP POD'S HULL GLOWING with the heat it has soaked up
// (DropPod.soak: the hull's material_overlay while it holds any). Added
// over the hull's own picture: hottest at the foot of the shield, less up
// the side, the glow reaching higher the hotter it is; white-orange when
// hot, cooling through orange to a dull red, and falling as heat squared,
// as the minigun's barrel does (gun.gdshader). `boil` (the reentry fire's
// own heat) churns it while the fire is on. In the hull mesh's own metres
// (its foot at 0).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float boil : hint_range(0.0, 1.0) = 0.0;
uniform float top = 3.2;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	// (the hotter, the higher up the hull the glow reaches)
	float k = clamp(lp.y / (top * (0.45 + 0.55 * heat)), 0.0, 1.0);
	float glow = pow(1.0 - k, 2.2);
	// a slow churn in it while the fire is on, so the metal seems to boil
	float wob = 1.0 - 0.15 * boil + 0.15 * boil * sin(lp.x * 3.1 + TIME * 5.0) * sin(lp.z * 2.7 - TIME * 4.0);
	vec3 hot = mix(vec3(1.0, 0.78, 0.45), vec3(0.85, 0.16, 0.03), smoothstep(0.0, 0.7, k));
	// cooling: white-orange, orange, then a dull red
	vec3 cool = mix(vec3(0.55, 0.05, 0.01), vec3(1.0, 0.35, 0.05), smoothstep(0.0, 0.6, heat));
	vec3 col = mix(cool, hot, smoothstep(0.5, 0.95, heat));
	ALBEDO = col * 1.7;
	ALPHA = clamp(glow * wob * heat * heat * 1.4, 0.0, 1.0);
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = vec3(0.0);
}
