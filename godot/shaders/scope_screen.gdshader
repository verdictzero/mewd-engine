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
// THE CHARGE AND THE WINDOW, DRAWN HERE AND NOT ON THE PANEL (at the
// user's report: the lance killing the handheld in the first seconds of
// a charge, a third time, with nothing in the log). The panel is a 2D
// SubViewport, and while charging it was rendered again a few times a
// second — the only thing on the screen that started when the charge
// did. The two rings are worked out per pixel from these numbers now,
// so a charge changes uniforms and nothing is drawn into a target.
// Geometry in the panel's own square, y down, as Scope._draw_panel had
// it: angles in turns from twelve o'clock, clockwise, the ring from
// eight o'clock round to four.
// gauge: x the charge 0..1, y the window left 0..1, z 1 to draw the
// rings at all (one vec4, set together every tic)
uniform vec4 gauge = vec4(0.0);
uniform vec4 charge_ink = vec4(0.59, 1.0, 0.54, 0.92);
uniform vec4 hold_ink = vec4(0.59, 1.0, 0.54, 0.92);
uniform vec4 track = vec4(0.59, 1.0, 0.54, 0.14);
uniform vec4 marks = vec4(0.4286, 0.7143, 1.0, 0.0);

varying vec3 local;

// sine-free, because its argument grows with the clock (see
// sear_decal.gdshader for what a GPU's sin does a few thousand out)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// One ring: its track, the lit sweep to `lit` of the way round, the glare
// at the sweep's head; `p` in the panel's square, y down.
vec4 ring(vec2 p, float R, float W, float lit, vec4 ink, vec4 trk, bool cut) {
	vec2 d = p - 0.5;
	float r = length(d);
	float turns = atan(d.x, -d.y) / 6.2831853;
	float t = (turns + 0.375) / 0.75;
	if (t < 0.0 || t > 1.0) return vec4(0.0);
	float head = min(1.0, lit);
	// the glare: the last 0.16 radians before the head, nearly twice as wide
	float glare_t = 0.16 / (0.75 * 6.2831853);
	vec4 o = vec4(0.0);
	if (abs(r - R) < W * 0.5) {
		o = trk;
		if (lit > 0.0 && t <= head) o = ink;
	}
	if (lit > 0.0 && t <= head && t >= head - glare_t && abs(r - R) < W * 0.95) {
		o = mix(o, vec4(ink.rgb, 1.0), 0.28 * (1.0 - o.a * 0.5));
		o.a = max(o.a, 0.28);
	}
	// the stage marks, cut THROUGH the ring as gaps
	if (cut && abs(r - R) < W * 0.625) {
		float tw = 0.0045;
		if (abs(t - marks.x) < tw || abs(t - marks.y) < tw || (marks.z < 1.0 && abs(t - marks.z) < tw))
			o = vec4(0.024, 0.07, 0.03, 0.95);
	}
	return o;
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	// ITS OWN DEPTH (the very value the GPU would write: nothing looks
	// different): a draw that writes its depth is never culled by an
	// Adreno's LRZ, the 8x8 blocks of black on the gun (Lofi.gun_depth)
#ifndef MEWD_FIXED_DEPTH
	DEPTH = FRAGCOORD.z;
#endif
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
	// the two rings, under the rest of the gauges
	if (gauge.z > 0.5) {
		vec2 p = vec2(uv.x, 1.0 - uv.y);
		vec4 a = ring(p, 0.372, 0.086, gauge.x, charge_ink, track, true);
		col = mix(col, a.rgb, a.a);
		if (gauge.y > 0.0) {
			vec4 b = ring(p, 0.268, 0.054, gauge.y, hold_ink, vec4(track.rgb, 0.10), false);
			col = mix(col, b.rgb, b.a);
		}
	}
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
