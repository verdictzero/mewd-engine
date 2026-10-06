// MEWD — the finished frame, filtered (js/lofi.js FILTER_FRAG + BLIT_FRAG).
//
// The world is drawn into its own SubViewport (world_tex) and this puts
// it onto the chunky PIXELS grid, 320 rows of 2:3 pixels by default —
// run ONCE PER CHUNKY PIXEL, into a grid-sized buffer that is blown up
// nearest-neighbour (render/lofi.gd). Every fetch is nearest; where the
// buffer is finer than the grid the taps average the texels a cell
// covers; then the Bayer wobble, one step of a 16x16x16
// grid, and the SNAP to the nearest of the palette's 256 colours by a
// 32x32x32 atlas (godot/data/palette_lut.png: blue picks the slice, red
// is x within it, green is y). Nearest, so the snap is a snap and never
// a blend of two palette entries. Then the tint (the title's blue).
shader_type canvas_item;

uniform sampler2D lut : filter_nearest;
// the gun, over the room and under the filter (js/lofi.js: the overlays
// are drawn into the buffer before the post pass)
uniform sampler2D world_tex : filter_nearest;
uniform sampler2D gun_tex : filter_nearest;
// under Mobile the gun is drawn onto the room already (Lofi.gun_on_room)
uniform bool gun_on_room = false;
uniform vec2 grid_size = vec2(480.0, 320.0);
uniform vec2 taps = vec2(2.0, 3.0);
uniform float dither = 1.0;
uniform float snap = 1.0;
uniform vec3 dither_levels = vec3(16.0);
uniform vec3 picture = vec3(1.0);   // brightness, contrast, gamma
uniform vec3 tint = vec3(1.0);
// THE TONEMAP, at the user's request (CANDY LAND came out overexposed):
// the island's own exposure on the picture, then a SHOULDER — above
// `knee` the brightest channel is rolled off smoothly toward white
// instead of clipping, and the other two scaled with it, so a bright
// colour keeps its hue rather than washing out. knee 0 is off (every
// island but the ones that ask: Islands "exposure", "knee").
uniform float exposure = 1.0;
uniform float knee = 0.0;
// THE BEAM IN THE EYE, at the user's request ("have a screen heat wobble /
// hue rotate (very fast very very fast) when hit"): `wobble` 0..1 — the
// picture swims like air over a fire, in rows and columns of sines, and
// every colour spins round the wheel several times a second. `now` in
// seconds.
uniform float wobble = 0.0;
uniform float now = 0.0;

vec3 hue_turn(vec3 c, float a) {
	// round the grey axis
	vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

vec3 shoulder(vec3 c) {
	float m = max(c.r, max(c.g, c.b));
	if (knee <= 0.0 || m <= knee) return c;
	float w = 1.0 - knee;
	float r = knee + w * (1.0 - exp(-(m - knee) / w));
	return c * (r / m);
}

float bayer2(float x, float y) { return mod(2.0 * x + 3.0 * y, 4.0); }
float bayer4(vec2 p) {
	vec2 f = mod(floor(p), 4.0);
	return 4.0 * bayer2(mod(f.x, 2.0), mod(f.y, 2.0)) + bayer2(floor(f.x * 0.5), floor(f.y * 0.5));
}

vec3 pal_snap(vec3 c) {
	float N = 32.0;
	c = clamp(c, 0.0, 1.0);
	float r = floor(c.r * (N - 1.0) + 0.5);
	float g = floor(c.g * (N - 1.0) + 0.5);
	float b = floor(c.b * (N - 1.0) + 0.5);
	return texture(lut, vec2((b * N + r + 0.5) / (N * N), (g + 0.5) / N)).rgb;
}

void fragment() {
	vec2 cell = floor(UV * grid_size);
	vec2 uv0 = cell / grid_size;
	if (wobble > 0.0) {
		vec2 w = vec2(sin(UV.y * 38.0 + now * 47.0) + 0.6 * sin(UV.y * 91.0 - now * 73.0),
			cos(UV.x * 31.0 - now * 53.0) + 0.6 * sin(UV.x * 77.0 + now * 61.0));
		uv0 = clamp(uv0 + w * 0.009 * wobble, vec2(0.0), vec2(1.0) - 1.0 / grid_size);
	}
	vec2 span = 1.0 / grid_size;
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			vec2 t = vec2(float(i), float(j));
			if (t.x < taps.x && t.y < taps.y) {
				vec2 at = uv0 + (t + 0.5) / taps * span;
				vec4 g = texture(gun_tex, at);
				// (a NaN or an infinity from the gun's world would come out
				// of the snap as a black block: on an Adreno it did)
				if (any(isnan(g)) || any(isinf(g))) g = vec4(0.0);
				g = clamp(g, vec4(0.0), vec4(16.0));
				sum += gun_on_room ? g.rgb : mix(texture(world_tex, at).rgb, g.rgb, g.a);
				n += 1.0;
			}
		}
	}
	vec3 c = sum / n;
	c = (c - 0.5) * picture.y + 0.5;
	c = max(c * picture.x * exposure, 0.0);
	c = pow(c, vec3(1.0 / max(picture.z, 0.05)));
	c = shoulder(c);
	if (wobble > 0.0)
		c = max(mix(c, hue_turn(c, now * 75.0), clamp(wobble * 1.5, 0.0, 1.0)), 0.0);
	if (dither > 0.0)
		c += vec3((bayer4(cell) / 15.0 - 0.5) * dither) / dither_levels;
	c = mix(c, pal_snap(c), snap);
	COLOR = vec4(c * tint, 1.0);
}
