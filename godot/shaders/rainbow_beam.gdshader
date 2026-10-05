// MEWD — a candy unicorn's death beam (RainbowBeams, rainbow.gd): a TUBE
// of real geometry from her mouth to where it lands, rebuilt each frame.
// UV.x is the way along it (game units), UV.y the way round it, COLOR the
// shell (r: 1 the white core, 0 the rainbow sheath) and how strong (a).
// The sheath's colour runs through the whole wheel along the beam and
// streams away from her, a band of every colour round the edge where it
// is seen side-on; the core is white-hot. All additive, no depth written.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float now = 0.0;

vec3 hue(float h) {
	vec3 k = clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
	return k;
}

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float along = UV.x;
	float core = COLOR.r;
	float a = COLOR.a;
	// the wheel along the beam, streaming out of her, and shifted at the edge
	vec3 bow = hue(fract(along * 0.0035 - now * 1.6 + rim * 0.45));
	// bright bands travelling down it
	float pulse = 0.75 + 0.25 * sin(along * 0.05 - now * 40.0);
	// (saturated, and not too much of it: an additive sheath of every colour
	// at once is white, which is not a rainbow)
	vec3 sheath = bow * bow * (0.45 + 0.7 * rim) * pulse;
	vec3 white = mix(vec3(1.0), bow, 0.35) * (0.9 - 0.4 * rim);
	ALBEDO = mix(sheath, white, core) * a;
}
