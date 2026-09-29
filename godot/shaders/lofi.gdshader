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
uniform vec2 grid_size = vec2(480.0, 320.0);
uniform vec2 taps = vec2(2.0, 3.0);
uniform float dither = 1.0;
uniform float snap = 1.0;
uniform vec3 dither_levels = vec3(16.0);
uniform vec3 picture = vec3(1.0);   // brightness, contrast, gamma
uniform vec3 tint = vec3(1.0);

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
	vec2 span = 1.0 / grid_size;
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			vec2 t = vec2(float(i), float(j));
			if (t.x < taps.x && t.y < taps.y) {
				vec2 at = uv0 + (t + 0.5) / taps * span;
				vec4 g = texture(gun_tex, at);
				sum += mix(texture(world_tex, at).rgb, g.rgb, g.a);
				n += 1.0;
			}
		}
	}
	vec3 c = sum / n;
	c = (c - 0.5) * picture.y + 0.5;
	c = max(c * picture.x, 0.0);
	c = pow(c, vec3(1.0 / max(picture.z, 0.05)));
	if (dither > 0.0)
		c += vec3((bayer4(cell) / 15.0 - 0.5) * dither) / dither_levels;
	c = mix(c, pal_snap(c), snap);
	COLOR = vec4(c * tint, 1.0);
}
