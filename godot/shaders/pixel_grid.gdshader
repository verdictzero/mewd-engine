// MEWD — THE PIXEL GRID, AN LCD (at the user's request: "a pixel grid
// filter to lower value pixel options", then "pixel grid = looks like
// LCD"). The finished chunky frame, blown up nearest to the screen
// (render/lofi.gd `rect`), drawn as a handheld's panel would show it:
//   - a dark GAP down the left and along the top of every chunky pixel,
//     whole screen pixels wide, the panel's black matrix;
//   - inside it, where a chunky pixel is six screen pixels or more
//     across, three SUBPIXEL STRIPES, red, green and blue, each lit by
//     its own channel of the pixel (and a little of the others, so a
//     grey stays grey), the whole brightened back up to what it was.
// `cell_px` is how many SCREEN pixels one chunky pixel is; `mode` 0 is
// off, 1 the gaps alone (LINES), 2 the panel (LCD). Lofi turns it off
// where a chunky pixel is under three screen pixels.
shader_type canvas_item;

uniform vec2 cells = vec2(480.0, 270.0);
uniform vec2 cell_px = vec2(4.0, 4.0);
uniform int mode = 0;
// how dark the gaps are (0 none, 1 black)
uniform float gap = 0.5;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (mode > 0) {
		vec2 f = fract(UV * cells);
		vec2 px = f * cell_px;
		float line = max(1.0, floor(min(cell_px.x, cell_px.y) / 6.0));
		float edge = (px.x < line || px.y < line) ? 1.0 : 0.0;
		vec3 rgb = c.rgb;
		if (mode == 2 && cell_px.x >= 6.0) {
			// the stripes across what is left of the cell after the gap
			float u = clamp((px.x - line) / max(cell_px.x - line, 1.0), 0.0, 0.999);
			float k = floor(u * 3.0);
			vec3 mask = vec3(k == 0.0 ? 1.0 : 0.0, k == 1.0 ? 1.0 : 0.0, k == 2.0 ? 1.0 : 0.0);
			mask = mix(vec3(0.5), vec3(1.0), mask);
			rgb = min(rgb * mask * 1.5, vec3(1.0));
		} else if (mode == 2) {
			rgb *= 1.12;
		}
		c.rgb = rgb * (1.0 - gap * edge);
	}
	COLOR = c;
}
