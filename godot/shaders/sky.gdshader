// MEWD — the sky for the hour and the weather (js/skyart.js, SkyBaker).
//
// The web build BAKES this into an equirect texture every few seconds;
// here it is a sky shader, worked out per pixel from the same uniforms
// (Weather._push_sky), which is the same picture without the bake. Two
// or three stops from the horizon up (a map's own `mid` for the grid's
// green), the ground below, the glow on the sun's side of the horizon,
// the town's sodium low in the west, the sun and its disc, the moon and
// its halo, fbm cloud blown by the wind, a hashed starfield thickest
// along the milky way. The palette snap and the dither the bake did are
// the post pass's here, as for everything else.
shader_type sky;

uniform vec3 zenith : source_color;
uniform vec3 horizon : source_color;
uniform vec3 ground : source_color;
uniform vec3 mid : source_color;
uniform float mid_amt = 0.0;
uniform float mid_pow = 1.0;
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 sun_col : source_color;
uniform vec3 glow : source_color;
uniform float glow_amt = 0.0;
uniform float sun_up = 0.0;
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float moon_amt = 1.0;
uniform float town = 0.0;
uniform float stars = 1.0;
uniform float milky = 1.0;
uniform float daylight = 0.0;
uniform float cover = 0.0;
uniform float cloud_dark = 1.0;
uniform float flatness = 0.0;
uniform float cloud_time = 0.0;
uniform vec2 wind = vec2(0.0);


float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash_star(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i), b = hash2(i + vec2(1.0, 0.0)), c = hash2(i + vec2(0.0, 1.0)), d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, amp = 0.5;
	for (int o = 0; o < 4; o++) { v += vnoise(p) * amp; p = p * 2.03 + vec2(17.0, 9.0); amp *= 0.5; }
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float e = dir.y;
	vec3 hd = normalize(vec3(dir.x, 0.0, dir.z) + vec3(1e-5, 0.0, 0.0));
	float up = clamp(e, 0.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.55));
	if (mid_amt > 0.0) {
		float t3 = pow(up, mid_pow);
		vec3 three = t3 < 0.5 ? mix(horizon, mid, t3 * 2.0) : mix(mid, zenith, t3 * 2.0 - 1.0);
		col = mix(col, three, mid_amt);
	}
	col = mix(col, horizon, flatness);
	col = mix(col, ground, smoothstep(0.0, 0.08, -e));
	vec3 sd = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(1e-5, 0.0, 0.0));
	float toward = max(dot(hd, sd), 0.0);
	float gl = pow(toward, 3.0) * exp(-max(e, 0.0) * 7.0) * glow_amt * (1.0 - flatness * 0.5);
	col += glow * gl;
	float town_glow = pow(max(dot(hd, vec3(-1.0, 0.0, 0.0)), 0.0), 5.0) * exp(-max(e, 0.0) * 10.0) * town;
	col += vec3(0.42, 0.30, 0.12) * town_glow;
	float ca = dot(dir, sun_dir);
	col += sun_col * (pow(max(ca, 0.0), 300.0) * 0.7 + pow(max(ca, 0.0), 10.0) * 0.08) * sun_up;
	float disc = smoothstep(cos(0.016), cos(0.010), ca) * sun_up;
	col = mix(col, sun_col * 1.15, disc);
	float cm = dot(dir, moon_dir);
	float halo = pow(max(cm, 0.0), 60.0) * 0.22 * moon_amt;
	float mdisc = smoothstep(cos(0.020), cos(0.016), cm) * moon_amt;
	col += vec3(0.62, 0.66, 0.78) * halo;
	col = mix(col, vec3(0.86, 0.87, 0.90) * (1.0 - daylight * 0.4), mdisc);
	vec2 cp = dir.xz / max(e, 0.10) * 1.6 + wind * cloud_time * 0.012 + vec2(3.7, 1.9);
	float n = fbm(cp);
	float cloud = smoothstep(1.0 - cover, 1.0 - cover + 0.35, n) * smoothstep(0.0, 0.14, e);
	cloud *= 1.0 - flatness;
	vec3 cloud_col = mix(zenith * 1.5 + vec3(0.025), horizon, 0.45) * cloud_dark;
	cloud_col += glow * gl * 1.4 + sun_col * pow(max(ca, 0.0), 4.0) * 0.30 * sun_up;
	cloud_col += vec3(0.42, 0.30, 0.12) * town_glow * 1.6;
	cloud_col = mix(cloud_col, vec3(0.84, 0.86, 0.90) * cloud_dark, daylight * 0.85);
	cloud_col *= 1.0 - 0.35 * smoothstep(0.3, 1.0, cloud);
	// the stars, one hash per cell of a 2048-wide equirect grid
	vec2 uv = vec2(atan(dir.z, dir.x) / (2.0 * PI) + 0.5, asin(clamp(e, -1.0, 1.0)) / PI + 0.5);
	vec2 cell = floor(uv * vec2(2048.0, 512.0));
	float h = hash_star(cell + 0.5);
	vec3 band_n = normalize(vec3(0.30, 0.55, 0.78));
	float band = 1.0 - smoothstep(0.0, 0.24, abs(dot(dir, band_n)));
	float density = 0.0035 * max(cos((uv.y - 0.5) * PI), 0.0) * (1.0 + band * 2.5);
	float star = step(1.0 - density, h) * (0.35 + 0.65 * fract(h * 77.7));
	star *= smoothstep(0.005, 0.03, e) * stars * (1.0 - cloud) * (1.0 - disc) * (1.0 - mdisc);
	vec3 mw = vec3(0.22, 0.23, 0.32) * band * (0.5 + 0.5 * fbm(dir.xz * 5.0 + dir.y * 3.0)) * milky * smoothstep(0.0, 0.05, e);
	col += mw * (1.0 - cloud);
	col += vec3(0.80, 0.84, 1.00) * star;
	col = mix(col, cloud_col, cloud);
	vec3 s = clamp(col, 0.0, 1.0);
	// the colours are written as bytes; the sky's output is linear
	COLOR = mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s));
}
