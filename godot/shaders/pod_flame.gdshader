// MEWD — THE DROP POD'S THRUSTER JETS (DropPod `flames`): one mesh for
// every nozzle in one MultiMesh, the mesh a chain of SHOCK DIAMONDS
// (DropPod._jet_mesh, at the user's request: "tight mach diamonds with
// appropriate color shift for all thrusters") — the silhouette is the
// mesh's; this paints it. UV.y is the way along the jet, 0 at the nozzle
// and 1 at its point; the instance colour is the exhaust's colour (rgb)
// and, in its alpha, the kind: 0 the RCS (blue), 1 the retros (orange).
// THE COLOUR SHIFT along the jet is a real exhaust's: hottest, and
// white-blue, where it leaves the nozzle; the exhaust's own colour in
// the bellies; and reddening and darkening toward the end as it cools,
// every shock (each waist, where the diamonds meet) a bright pale flash
// where the gas is compressed and hot again. The RCS, cold gas, runs
// white to blue to violet instead. Mixed, not added (against the bright
// sky an added jet is white); unlit, no depth written.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float diamonds = 5.0;

varying float along;
varying vec4 tint;

void vertex() {
	along = UV.y;
	tint = COLOR;
}

void fragment() {
	float k = along;
	// the waists: the shocks, 1 at each, 0 in the bellies
	float tri = 1.0 - abs(fract(k * diamonds) * 2.0 - 1.0);
	float shock = pow(1.0 - tri, 4.0);
	vec3 col;
	if (tint.a > 0.5) {
		// hot exhaust: white-blue at the nozzle, orange, then red and dark
		vec3 hot = vec3(0.85, 0.92, 1.0);
		vec3 cool = vec3(0.55, 0.08, 0.02);
		col = mix(hot, tint.rgb, smoothstep(0.0, 0.25, k));
		col = mix(col, cool, smoothstep(0.45, 1.0, k));
	} else {
		// cold gas: white at the nozzle, blue, then violet and dim
		vec3 hot = vec3(0.95, 0.97, 1.0);
		vec3 cool = vec3(0.35, 0.1, 0.6);
		col = mix(hot, tint.rgb, smoothstep(0.0, 0.3, k));
		col = mix(col, cool, smoothstep(0.5, 1.0, k));
	}
	// every shock a pale flash, dimmer down the jet
	col = mix(col, vec3(1.0, 0.98, 0.95), shock * (0.9 - 0.5 * k));
	// solid to the point (the mesh ends in one), a little thinner at the
	// edges seen edge on
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float a = (0.8 + 0.2 * face) * (1.0 - 0.35 * smoothstep(0.7, 1.0, k));
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.97);
	// the thermal sight sees only people
	if (thermal_on(VIEWPORT_SIZE)) ALPHA = 0.0;
}
