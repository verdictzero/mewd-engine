// MEWD — the screen on the back of the gun (js/scope.js SCREEN_FRAG).
//
// Two samplers — the live feed and the gauges over it — and everything
// else is what makes a lit panel look like a lit panel rather than a
// photograph glued to a gun: a phosphor tint, scan lines, a slightly
// curved glass, a soft bezel, and a burst of static while the beam is
// out. The panel's own UVs are a speck of the model's atlas, so the
// picture is laid across the mesh's LOCAL position instead — the panel
// is planar, so x and y across its own box ARE the picture's two axes —
// and u is flipped because the gun is turned half a circle to point its
// barrel away from the eye (unflipped, the feed is a mirror).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D feed : filter_nearest;
uniform sampler2D panel : filter_nearest;
uniform bool has_panel = false;
uniform vec4 box = vec4(0.0, 0.0, 1.0, 1.0);   // minX, minY, 1/width, 1/height, in the mesh's units
uniform float on = 1.0;       // 0 dead, 1 lit
uniform float noise = 0.0;    // 0..1, static
uniform float tics = 0.0;
uniform vec3 tint = vec3(0.42, 1.0, 0.36);
// how bright the whole thing is, for a screen that is a sight rather
// than a monitor (the launcher's thermal wants its own numbers)
uniform float gain = 1.0;

varying vec3 local;

// sine-free, because its argument grows with the clock (see
// sear_decal.gdshader for what a GPU's sin does a few thousand out)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	// the panel's own box, and u flipped — see the header. v runs UP the
	// panel; a texture's rows run down, so it is flipped at the sample.
	vec2 uv = vec2(1.0 - (local.x - box.x) * box.z, (local.y - box.y) * box.w);
	vec2 c = uv - 0.5;
	// THE GLASS IS SLIGHTLY CURVED, a screen's tell at this size
	vec2 fuv = uv + c * dot(c, c) * 0.16;
	vec3 col = vec3(0.0);
	if (fuv.x > 0.0 && fuv.x < 1.0 && fuv.y > 0.0 && fuv.y < 1.0) {
		vec3 f = texture(feed, vec2(fuv.x, 1.0 - fuv.y)).rgb;
		// PHOSPHOR: the feed's brightness in one colour, not the feed's
		// colours dimmed — a green multiply over a brown town is mud
		float l = dot(f, vec3(0.30, 0.59, 0.11));
		// banded, because everything in this game is
		l = floor(pow(l, 0.85) * 14.0 + 0.5) / 14.0;
		col = tint * l;
	}
	// STATIC, AND IT GOES ON THE PICTURE AND NOT ON THE GAUGES: the
	// gauges are drawn by the gun, on the gun, and at the moment it
	// matters most the static would have taken the charge ring with it
	float n = hash(floor(uv * 128.0) + floor(tics * 3.0));
	col += (n - 0.5) * noise * 0.8;
	col = mix(col, vec3(n) * tint, noise * 0.25 * step(0.86, hash(vec2(floor(uv.y * 48.0), floor(tics * 2.0)))));
	// the gauges, straight over it, already the right colour
	if (has_panel) {
		vec4 g = texture(panel, vec2(uv.x, 1.0 - uv.y));
		col = mix(col, g.rgb, g.a);
	}
	// SCAN LINES on a grid of their own, and a slow roll down the picture
	col *= 0.82 + 0.18 * step(0.5, fract(uv.y * 72.0));
	col *= 1.0 + 0.045 * sin((uv.y + tics * 0.006) * 6.2831);
	// THE BEZEL: a narrow dark rim and a lit edge, so the panel reads as
	// inset (both smoothsteps low edge first — see js/scope.js)
	float r = max(abs(c.x), abs(c.y)) * 2.0;
	col *= 1.0 - smoothstep(0.94, 1.02, r);
	col += tint * 0.30 * smoothstep(0.90, 0.97, r) * (1.0 - smoothstep(0.97, 1.02, r));
	// and a little of it always on, so a dead screen is dark glass
	ALBEDO = col * on * gain + vec3(0.012, 0.020, 0.014);
}
