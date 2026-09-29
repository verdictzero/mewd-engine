// MEWD — the lens up front of the lance (js/scope.js OPTIC_FRAG). The
// file paints it flat green; this makes it a lens — bright where it
// faces you, a ring of glare at the rim, and lit from inside while the
// weapon is charged, pulsing faster as it fills.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 base = vec3(0.34, 0.80, 0.0);
uniform float charge = 0.0;
uniform float tics = 0.0;

void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(f, 2.2);
	vec3 c = base * (0.25 + 0.55 * (1.0 - f)) + vec3(0.55, 1.0, 0.62) * rim * 0.8;
	float pulse = 0.5 + 0.5 * sin(tics * (0.10 + charge * 0.42));
	c += vec3(0.6, 1.0, 0.7) * charge * (0.35 + 0.65 * pulse);
	ALBEDO = c;
}
