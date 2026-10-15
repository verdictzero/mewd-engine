// THE PICTURE, filtered (render/lofi.gd). The world is drawn into its own
// SubViewport (world_tex) and this puts it on the screen: in the RETRO
// picture once per chunky pixel, into a grid-sized buffer blown up
// nearest-neighbour, the taps averaging the texels a cell covers, then the
// Bayer dither and the SNAP to the nearest of the earth palette's 256
// colours (godot/data/palette_lut.png: blue picks the slice, red is x within
// it, green is y); in the NATIVE picture once a pixel, neither. Both take
// the island's exposure, its tonemap shoulder, its grade and its grain.
shader_type canvas_item;

uniform sampler2D lut : filter_nearest;
uniform sampler2D world_tex : filter_nearest;
uniform vec2 grid_size = vec2(480.0, 320.0);
uniform vec2 taps = vec2(2.0, 3.0);
uniform float dither = 1.0;
uniform float snap = 1.0;
uniform vec3 dither_levels = vec3(16.0);
uniform vec3 picture = vec3(1.0);   // brightness, contrast, gamma
// THE TONEMAP, at the user's request (CANDY LAND came out overexposed):
// the island's own exposure on the picture, then a SHOULDER — above
// `knee` the brightest channel is rolled off smoothly toward white
// instead of clipping, and the other two scaled with it, so a bright
// colour keeps its hue rather than washing out. knee 0 is off (every
// island but the ones that ask: Islands "exposure", "knee").
uniform float exposure = 1.0;
uniform float knee = 0.0;
// FILM GRAIN, how strong: a fresh speck in every pixel 24 times a second,
// near-gaussian, strongest in the middle tones as film's is, before the
// dither and the snap.
uniform float grain = 0.0;
// THE GRADE, at the user's request ("make it look fucking cinematic as hell —
// colorgrading"): an island's own colour grade (Islands "grade", Lofi.
// for_island), on the picture before the dither and the snap, the way a
// colourist grades a film. `grade` 0 is none (every island that asks
// nothing). In order:
//   FILMIC     a film's shoulder (`filmic` 0..1 of it) on the light tones:
//              the highlights rolled off to white, not clipped, so a sky
//              round the sun keeps its gradient
//   BALANCE    the white balance, `warmth` (+ amber, - blue) and `tint`
//              (+ magenta, - green)
//   CONTRAST   an S-curve round the middle grey
//   SATURATION and VIBRANCE (more on the duller colours than the rich)
//   SPLIT      split toning: the shadows tinted toward `shadows` and the
//              highlights toward `highlights` (the blockbuster's teal and
//              orange), `split` of it — a tint, so it never crushes a black
//   LIFT       the blacks raised toward grey a little, as film's are
//   VIGNETTE   the corners darkened, as a lens does
// THE METER (lofi_meter.gdshader, Lofi): the picture's eased brightness in one
// pixel, and how the exposure follows it
uniform sampler2D meter_tex : filter_nearest;
uniform float meter_on = 0.0;
uniform float meter_key = 0.4;
uniform float meter_strength = 0.6;
uniform vec2 meter_range = vec2(0.7, 2.5);

uniform float grade = 0.0;
uniform float grade_filmic = 0.0;
uniform float grade_warmth = 0.0;
uniform float grade_tint = 0.0;
uniform float grade_contrast = 0.0;
uniform float grade_saturation = 1.0;
uniform float grade_vibrance = 0.0;
uniform vec3 grade_shadows = vec3(0.0, 0.5, 0.55);
uniform vec3 grade_highlights = vec3(1.0, 0.62, 0.3);
uniform float grade_split = 0.0;
uniform float grade_lift = 0.0;
uniform float grade_vignette = 0.0;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// a speck of grain, -1..1, about gaussian (four uniform draws summed)
float speck(vec2 cell, float frame) {
	// (each frame somewhere else in the noise, by an offset kept under a
	// thousand cells, so the hash keeps its precision however long it runs)
	vec2 q = cell + vec2(fract(frame * 0.6180339), fract(frame * 0.7548776)) * 1000.0;
	float s = hash12(q) + hash12(q + 17.31) + hash12(q + 43.7) + hash12(q + 71.13);
	return (s - 2.0) * 0.866;
}

// what the meter says to do to the exposure: toward the key from the
// picture's brightness as exposed, by the meter's strength, within its range
float metered(float exposed) {
	vec4 m = texelFetch(meter_tex, ivec2(0), 0);
	if (meter_on <= 0.0 || m.a < 0.5) return 1.0;
	float avg = exp2((m.r + m.g / 255.0) * 16.0 - 12.0) * exposed;
	return clamp(pow(meter_key / max(avg, 1e-4), meter_strength), meter_range.x, meter_range.y);
}

vec3 shoulder(vec3 c) {
	float m = max(c.r, max(c.g, c.b));
	if (knee <= 0.0 || m <= knee) return c;
	float w = 1.0 - knee;
	float r = knee + w * (1.0 - exp(-(m - knee) / w));
	return c * (r / m);
}

// a film's response, normalised so 1 still comes out as 1 (Hable's curve)
vec3 hable(vec3 x) {
	const float HA = 0.22, HB = 0.30, HC = 0.10, HD = 0.20, HE = 0.01, HF = 0.30;
	return ((x * (HA * x + HC * HB) + HD * HE) / (x * (HA * x + HB) + HD * HF)) - HE / HF;
}

vec3 graded(vec3 c, vec2 uv) {
	float l;
	if (grade_filmic > 0.0) {
		// (the picture is already the display's; brought back toward light,
		// through the film, and out again — for the light tones only: the
		// film's toe would sink a dark meadow at evening into black)
		vec3 lin = pow(max(c, 0.0), vec3(2.2)) * 2.2;
		vec3 f = hable(lin) / hable(vec3(11.2 * 0.45));
		float bright = smoothstep(0.3, 0.8, dot(c, LUMA));
		c = mix(c, pow(max(f, 0.0), vec3(1.0 / 2.2)), grade_filmic * bright);
	}
	c *= vec3(1.0 + grade_warmth * 0.12, 1.0 - grade_tint * 0.06, 1.0 - grade_warmth * 0.12);
	if (grade_contrast != 0.0) {
		vec3 k = clamp(c, 0.0, 1.0);
		c += (k * k * (3.0 - 2.0 * k) - k) * grade_contrast;
	}
	l = dot(c, LUMA);
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	c = mix(vec3(l), c, grade_saturation + grade_vibrance * (1.0 - clamp(sat * 2.0, 0.0, 1.0)));
	if (grade_split > 0.0) {
		l = clamp(dot(c, LUMA), 0.0, 1.0);
		// (each colour as a tint of its own brightness, so it moves the hue and
		// not the level, and a black stays a black)
		vec3 sh = grade_shadows / max(dot(grade_shadows, LUMA), 1e-3) - 1.0;
		vec3 hi = grade_highlights / max(dot(grade_highlights, LUMA), 1e-3) - 1.0;
		c *= vec3(1.0) + (sh * (1.0 - smoothstep(0.0, 0.55, l)) + hi * smoothstep(0.35, 1.0, l))
				* grade_split * 0.3;
	}
	c = c + grade_lift * (1.0 - c);
	if (grade_vignette > 0.0) {
		vec2 q = (uv - 0.5) * vec2(grid_size.x / max(grid_size.y, 1.0), 1.0);
		float v = smoothstep(0.35, 1.05, length(q));
		c *= 1.0 - v * grade_vignette;
	}
	return max(c, 0.0);
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
	vec2 span = 1.0 / grid_size;
	vec3 sum = vec3(0.0);
	float n = 0.0;
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			vec2 t = vec2(float(i), float(j));
			if (t.x < taps.x && t.y < taps.y) {
				vec2 at = uv0 + (t + 0.5) / taps * span;
				// (a NaN some driver makes of a fragment's sum would come out
				// as a lone black or white pixel)
				vec3 w = texture(world_tex, at).rgb;
				if (any(isnan(w)) || any(isinf(w))) w = vec3(0.0);
				sum += clamp(w, vec3(0.0), vec3(16.0));
				n += 1.0;
			}
		}
	}
	vec3 c = sum / n;
	c = (c - 0.5) * picture.y + 0.5;
	c = max(c * picture.x * exposure * metered(picture.x * exposure), 0.0);
	c = pow(c, vec3(1.0 / max(picture.z, 0.05)));
	c = shoulder(c);
	if (grade > 0.0)
		c = mix(c, graded(c, UV), grade);
	if (grain > 0.0) {
		float l = clamp(dot(c, LUMA), 0.0, 1.0);
		float g = speck(cell, floor(TIME * 24.0)) * grain * (0.5 + 1.2 * l * (1.0 - l) + 0.2 * l);
		c = max(c + vec3(g), 0.0);
	}
	if (dither > 0.0)
		c += vec3((bayer4(cell) / 15.0 - 0.5) * dither) / dither_levels;
	c = mix(c, pal_snap(c), snap);
	COLOR = vec4(c, 1.0);
}
