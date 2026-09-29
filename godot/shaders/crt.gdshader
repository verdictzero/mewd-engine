// MEWD — the tube over the terminal (css/style.css #term::before/::after):
// scanlines two pixels on, two off, a soft band crawling down the glass
// every seven seconds, the whole of it jumping two pixels on and off, the
// corners shaded, and a flicker now and then.
shader_type canvas_item;

uniform float time = 0.0;

void fragment() {
	vec2 px = FRAGCOORD.xy;
	float roll = mod(floor(time / 0.2), 2.0) * 2.0;
	float line = mod(px.y + roll, 4.0) < 2.0 ? 0.0 : 0.34;
	float h = 1.0 / SCREEN_PIXEL_SIZE.y;
	float band_y = mod(time / 7.0, 1.0) * (h * 1.22) - h * 0.22;
	float d = (px.y - band_y) / (h * 0.22);
	float band = d >= 0.0 && d <= 1.0 ? (1.0 - abs(d * 2.0 - 1.0)) * 0.05 : 0.0;
	vec2 uv = SCREEN_UV - 0.5;
	float vig = smoothstep(0.55 * 0.5, 0.75, length(uv * vec2(1.0, 1.0))) * 0.6;
	float t = mod(time, 3.0) / 3.0;
	float flick = (t > 0.47 && t < 0.48) ? 0.1 : ((t > 0.83) ? 0.05 : 0.0);
	float dark = clamp(line + vig + flick, 0.0, 1.0);
	// black at `dark`, and the band a faint white over it
	float a = dark + band * (1.0 - dark);
	COLOR = vec4(vec3(a > 0.0 ? band * (1.0 - dark) / a : 0.0), a);
}
