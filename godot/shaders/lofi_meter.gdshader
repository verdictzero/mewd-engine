shader_type canvas_item;
render_mode unshaded, blend_disabled;

// THE PICTURE'S METER (Lofi, at the user's request: cinematic, and a meadow
// in a mountain's evening shadow had gone to black): how bright the world's
// picture is, as a camera's meter reads it, into one pixel the filter
// (lofi.gdshader `metered`) opens or stops the exposure down by.
//
// METER (hold off): sixteen by twelve taps over the picture, the middle
// counting most, averaged as the log of their brightness (so a bright sky
// does not swamp a dark meadow), eased toward from what was read before
// (`held`, the HOLD pixel: last frame's) by `rate` a frame — the eye's
// adaptation. `rate` under 0 forgets it (the place is not up: nothing worth
// reading), 1 or more takes the reading as it is.
// HOLD (hold on): the meter's pixel copied, for the next frame to ease from.
//
// The reading is log2 of the brightness, -12 to 4, as 0..1 in two of the
// pixel's bytes (red the coarse, green the fine: the easing's small steps
// would round away in one), and alpha 1 to say there is one.

uniform bool hold = false;
uniform sampler2D world_tex : filter_linear;
uniform sampler2D held : filter_nearest;
uniform float rate = 0.04;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float decode(vec4 m) {
	return m.r + m.g / 255.0;
}

vec4 encode(float v) {
	v = clamp(v, 0.0, 1.0 - 1.0 / 65025.0);
	float hi = floor(v * 255.0) / 255.0;
	return vec4(hi, (v - hi) * 255.0, 0.0, 1.0);
}

void fragment() {
	if (hold) {
		COLOR = texelFetch(held, ivec2(0), 0);
	} else if (rate < 0.0) {
		COLOR = vec4(0.0);
	} else {
		float sum = 0.0;
		float wsum = 0.0;
		for (int j = 0; j < 12; j++) {
			for (int i = 0; i < 16; i++) {
				vec2 uv = (vec2(float(i), float(j)) + 0.5) / vec2(16.0, 12.0);
				vec3 c = textureLod(world_tex, uv, 0.0).rgb;
				float l = clamp(dot(c, LUMA), exp2(-12.0), 16.0);
				vec2 q = (uv - 0.5) * 2.0;
				float w = 1.0 - 0.6 * min(dot(q, q), 1.0);
				sum += log2(l) * w;
				wsum += w;
			}
		}
		float v = (sum / wsum + 12.0) / 16.0;
		vec4 prev = texelFetch(held, ivec2(0), 0);
		if (prev.a > 0.5 && rate < 1.0) {
			v = mix(decode(prev), v, rate);
		}
		COLOR = encode(v);
	}
}
