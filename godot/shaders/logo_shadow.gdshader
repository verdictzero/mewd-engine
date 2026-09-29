// MEWD — behind the logo, for contrast, at the user's request: its own
// outline, blurred and black (js/titlescene.js shadowOf). The blur is
// the texture's own mip chain read at a high level, spread over a ring
// of taps; drawn inside the picture, so it is dithered with the wood.
shader_type canvas_item;

uniform float blur = 4.0;      // the mip level
uniform float spread = 0.02;   // how far the taps reach, in uv
uniform float strength = 0.8;
// the rect is the logo's box grown by `grow` of its size each way; the
// picture is the logo's box and nothing outside it
uniform float grow = 0.0;

float at(sampler2D tex, vec2 uv) {
	vec2 lu = uv * (1.0 + 2.0 * grow) - grow;
	if (lu.x < 0.0 || lu.y < 0.0 || lu.x > 1.0 || lu.y > 1.0) return 0.0;
	return textureLod(tex, lu, blur).a;
}

void fragment() {
	float a = 0.0;
	float n = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = float(i) / 12.0 * 6.2831853;
		vec2 o = vec2(cos(ang), sin(ang)) * spread;
		a += at(TEXTURE, UV + o);
		n += 1.0;
	}
	a += at(TEXTURE, UV) * 4.0;
	n += 4.0;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a / n * 1.6, 0.0, 1.0) * strength);
}
