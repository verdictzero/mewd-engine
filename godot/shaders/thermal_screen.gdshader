// MEWD — the thermal sight's screen on the quad launcher (js/thermal.js
// SCREEN_FRAG).
//
// HEAT IN, IRONBOW OUT. The feed is the world drawn in heat — every
// surface answers how WARM it is, one number in all three channels (see
// godot/shaders/thermal.gdshaderinc) — and this runs that number up
// IRONBOW, black through indigo, magenta, red, orange, yellow to white,
// in bands. Everything after the palette is the lance's screen
// (scope_screen.gdshader) on the same terms: the panel's own box with u
// flipped, the curved glass, the gauges over it, the scan lines, the
// bezel. And THE MOTOR BLINDS IT: while a missile leaves the tube beside
// the sight the picture goes white-hot and snowy, under the gauges.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D feed : filter_nearest;
uniform sampler2D panel : filter_nearest;
uniform vec4 box = vec4(0.0, 0.0, 1.0, 1.0);   // minX, minY, 1/width, 1/height, in the mesh's units
uniform float on = 1.0;
uniform float noise = 0.0;
uniform float tics = 0.0;
// THE RENDERER: under Compatibility a SubViewport holds what the shader
// wrote, under Forward+ the tonemap pass sRGB-encodes it. The world writes
// the heat so the feed holds it either way (thermal_raw in
// thermal.gdshaderinc); this screen's own colours, written as bytes as the
// web build's are, are decoded for Forward+ and left alone for
// Compatibility. ThermalScope sets which.
uniform bool raw = false;
// the potato cannon's sight: night-vision green instead of ironbow
uniform bool green = false;
// a screen on a mirrored gun (weapon3d "mirror") reads the other way
uniform bool flip_x = false;

varying vec3 local;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// seven stops, black to white by way of every colour a hot thing is
vec3 ironbow(float h) {
	h = clamp(h, 0.0, 1.0);
	vec3 c0 = vec3(0.00, 0.00, 0.03), c1 = vec3(0.14, 0.01, 0.34), c2 = vec3(0.52, 0.03, 0.48);
	vec3 c3 = vec3(0.86, 0.18, 0.14), c4 = vec3(1.00, 0.55, 0.03), c5 = vec3(1.00, 0.88, 0.24);
	vec3 c6 = vec3(1.00, 1.00, 0.94);
	if (h < 0.18) return mix(c0, c1, h / 0.18);
	if (h < 0.36) return mix(c1, c2, (h - 0.18) / 0.18);
	if (h < 0.55) return mix(c2, c3, (h - 0.36) / 0.19);
	if (h < 0.72) return mix(c3, c4, (h - 0.55) / 0.17);
	if (h < 0.87) return mix(c4, c5, (h - 0.72) / 0.15);
	return mix(c5, c6, (h - 0.87) / 0.13);
}

// black, through the greens, to a white with green in it
vec3 greenbow(float h) {
	h = clamp(h, 0.0, 1.0);
	vec3 c0 = vec3(0.00, 0.02, 0.00), c1 = vec3(0.02, 0.16, 0.03), c2 = vec3(0.10, 0.42, 0.08);
	vec3 c3 = vec3(0.35, 0.78, 0.18), c4 = vec3(0.86, 1.00, 0.70);
	if (h < 0.25) return mix(c0, c1, h / 0.25);
	if (h < 0.50) return mix(c1, c2, (h - 0.25) / 0.25);
	if (h < 0.78) return mix(c2, c3, (h - 0.50) / 0.28);
	return mix(c3, c4, (h - 0.78) / 0.22);
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 uv = vec2(1.0 - (local.x - box.x) * box.z, (local.y - box.y) * box.w);
	if (flip_x) uv.x = 1.0 - uv.x;
	vec2 c = uv - 0.5;
	vec2 fuv = uv + c * dot(c, c) * 0.16;
	vec3 col = vec3(0.0);
	if (fuv.x > 0.0 && fuv.x < 1.0 && fuv.y > 0.0 && fuv.y < 1.0) {
		vec3 f = texture(feed, vec2(fuv.x, 1.0 - fuv.y)).rgb;
		// THE HEAT IS THE BRIGHTEST CHANNEL, not the luminance: the world
		// writes it into all three alike, and the few things drawn in their
		// own colours — a tracer, a lamp flare, the lance's beam — are
		// sources, and a source is as hot as its brightest channel
		float h = max(f.r, max(f.g, f.b));
		h = floor(h * 20.0 + 0.5) / 20.0;
		col = green ? greenbow(h) : ironbow(h);
	}
	// the motor, under the gauges
	float n = hash(floor(uv * 128.0) + floor(tics * 3.0));
	col = mix(col, vec3(1.0, 0.96, 0.86), noise * 0.55);
	col += (n - 0.5) * noise * 0.6;
	vec4 g = texture(panel, vec2(uv.x, 1.0 - uv.y));
	col = mix(col, g.rgb, g.a);
	col *= 0.84 + 0.16 * step(0.5, fract(uv.y * 64.0));
	col *= 1.0 + 0.04 * sin((uv.y + tics * 0.006) * 6.2831);
	float r = max(abs(c.x), abs(c.y)) * 2.0;
	col *= 1.0 - smoothstep(0.94, 1.02, r);
	col += (green ? vec3(0.10, 0.40, 0.08) : vec3(0.30, 0.10, 0.36)) * 0.35 * smoothstep(0.90, 0.97, r) * (1.0 - smoothstep(0.97, 1.02, r));
	col = clamp(col * on + vec3(0.014, 0.010, 0.020), 0.0, 1.0);
	ALBEDO = raw ? col : mix(col / 12.92, pow((col + 0.055) / 1.055, vec3(2.4)), step(0.04045, col));
}
