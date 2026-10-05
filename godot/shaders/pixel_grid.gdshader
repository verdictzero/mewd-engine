// MEWD — THE PIXEL GRID (at the user's request: "a pixel grid filter to
// lower value pixel options"). The finished chunky frame, blown up
// nearest to the screen (render/lofi.gd `rect`), with a dark line down
// the left and along the top of every chunky pixel, as an LCD's gaps.
// `cell_px` is how many SCREEN pixels one chunky pixel is, so the line
// is whole screen pixels wide (one, or more on very big pixels) and
// never blurs; `strength` 0 is off. Lofi turns it off where a chunky
// pixel is under three screen pixels: there a line would eat a third
// of every pixel.
shader_type canvas_item;

uniform vec2 cells = vec2(480.0, 270.0);
uniform vec2 cell_px = vec2(4.0, 4.0);
uniform float strength = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (strength > 0.0) {
		vec2 f = fract(UV * cells) * cell_px;
		float line = max(1.0, floor(min(cell_px.x, cell_px.y) / 6.0));
		float edge = (f.x < line || f.y < line) ? 1.0 : 0.0;
		c.rgb *= 1.0 - strength * edge;
	}
	COLOR = c;
}
