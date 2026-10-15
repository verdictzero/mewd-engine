shader_type sky;
render_mode use_quarter_res_pass;

// THE SKY OVER A REAL PLACE, after Enviro 3 (at the user's request: "make a
// cloud sky etc system reminiscent of the enviro 3 unity plugin"). Driven every
// frame by SCRIPT_enviro_sky.gd (EnviroSky), which owns the clock, the sun and
// the moon, the weather and its transitions; this draws what it is told.
//
//   THE AIR: single scattering through a spherical atmosphere, Rayleigh and Mie
//     (the usual model: Nishita, by way of wwwtyro's glsl-atmosphere), so the
//     blue overhead, the pale horizon, the sunset's reds and the twilight come
//     out of the physics rather than out of a gradient. EnviroSky evaluates the
//     same model on the CPU for the colours it hands the rest of the island.
//   THE CLOUDS: a layer of cumulus raymarched through a shell of the sky
//     (`cloud_bottom` to `cloud_top` metres over sea level, on the planet's
//     curve so they fall away to the horizon): shaped by a Perlin-Worley 3D
//     noise, eroded by Worley detail, spread by a weather map whose threshold is
//     the coverage, its profile from flat stratus to towering cumulus by
//     `cloud_type`. Lit by a short march toward the sun (Beer-Lambert, the
//     powder darkening, a two-lobed Henyey-Greenstein), the sky's own colour
//     for ambient, and faded into the air with distance. Above them a sheet of
//     cirrus. All of it in the QUARTER-RESOLUTION pass, which on the lo-fi
//     picture is a few thousand pixels; where the renderer has no such pass
//     (the GL compatibility renderer) `clouds_in_main` does them at full.
//   THE NIGHT: stars that twinkle, a moon whose phase is the real one (its face
//     lit from the sun's true direction), a little blue from the moonlit air.
//   THE WEATHER'S EXTRAS: lightning (a flash of the whole sky, and the bolt), and
//   rain's grey, which is the clouds' darkness plus `gloom`.

#define PI 3.14159265

group_uniforms bodies;
uniform vec3 sun_dir = vec3(0.3, 0.6, 0.5);
uniform vec3 moon_dir = vec3(-0.3, 0.4, -0.5);
// the sun's light at the top of the air, and how bright the sky is made of it
uniform float sun_intensity = 22.0;
uniform float sun_size = 0.9995;
uniform float moon_size = 0.9994;
uniform float moon_light = 0.0;
uniform sampler2D moon_tex : filter_linear_mipmap, source_color;
// the moonlit air at night, added to whatever the sun leaves
uniform vec3 night_air : source_color = vec3(0.02, 0.03, 0.065);
uniform float stars = 1.0;
uniform float exposure = 1.0;

group_uniforms air;
uniform vec3 beta_rayleigh = vec3(5.5e-6, 13.0e-6, 22.4e-6);
uniform float beta_mie = 21e-6;
uniform float height_rayleigh = 8000.0;
uniform float height_mie = 1200.0;
uniform float mie_g = 0.76;
// metres over sea level of the island's y = 0 (EarthField's datum)
uniform float ground_altitude = 1500.0;
// the haze a weather lays over the low sky (fog, rain), and its colour
uniform float haze = 0.0;
uniform vec3 haze_color : source_color = vec3(0.6, 0.65, 0.7);

group_uniforms clouds;
uniform sampler3D cloud_shape : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_weather : filter_linear, repeat_enable;
uniform sampler2D cirrus_tex : filter_linear_mipmap, repeat_enable;
uniform float coverage : hint_range(0.0, 1.0) = 0.4;
uniform float density = 0.035;
uniform float cloud_type : hint_range(0.0, 1.0) = 0.7;
uniform float cloud_bottom = 2600.0;
uniform float cloud_top = 5200.0;
uniform float shape_scale = 14000.0;
uniform float detail_scale = 1800.0;
uniform float weather_scale = 26000.0;
uniform float erosion = 0.35;
// how far the wind has carried them, metres (EnviroSky accumulates it)
uniform vec2 wind_offset = vec2(0.0);
uniform float cirrus = 0.3;
uniform vec2 cirrus_offset = vec2(0.0);
uniform int steps = 40;
uniform int light_steps = 5;
uniform float cloud_far = 60000.0;
// sunlight reaching the clouds (the CPU's transmittance), the sky lighting them
uniform vec3 cloud_sun : source_color = vec3(1.0);
uniform vec3 cloud_ambient_top : source_color = vec3(0.4, 0.5, 0.7);
uniform vec3 cloud_ambient_bottom : source_color = vec3(0.3, 0.32, 0.36);
// rain's clouds are grey all through
uniform float gloom : hint_range(0.0, 1.0) = 0.0;
uniform bool clouds_in_main = false;

group_uniforms lightning;
uniform float flash = 0.0;
uniform vec3 bolt_dir = vec3(1.0, 0.3, 0.0);
uniform float bolt = 0.0;
uniform float bolt_seed = 0.0;

group_uniforms;

const float R_PLANET = 6371000.0;
const float R_AIR = 6471000.0;


vec2 shell(vec3 r0, vec3 rd, float r) {
	float b = dot(rd, r0);
	float c = dot(r0, r0) - r * r;
	float d = b * b - c;
	if (d < 0.0) {
		return vec2(1e9, -1e9);
	}
	d = sqrt(d);
	return vec2(-b - d, -b + d);
}

// The air's light along `rd` from `r0`, lit from `ps`, as the model gives it.
vec3 atmosphere(vec3 rd, vec3 r0, vec3 ps, float isun, int isteps, int jsteps) {
	vec2 p = shell(r0, rd, R_AIR);
	if (p.x > p.y) {
		return vec3(0.0);
	}
	p.x = max(p.x, 0.0);
	vec2 g = shell(r0, rd, R_PLANET);
	if (g.x > 0.0) {
		p.y = min(p.y, g.x);
	}
	float ist = (p.y - p.x) / float(isteps);
	float it = p.x;
	vec3 trl = vec3(0.0);
	vec3 tmi = vec3(0.0);
	float odr = 0.0;
	float odm = 0.0;
	float mu = dot(rd, ps);
	float mumu = mu * mu;
	float gg = mie_g * mie_g;
	float prl = 3.0 / (16.0 * PI) * (1.0 + mumu);
	float pmi = 3.0 / (8.0 * PI) * ((1.0 - gg) * (mumu + 1.0))
			/ (pow(1.0 + gg - 2.0 * mu * mie_g, 1.5) * (2.0 + gg));
	for (int i = 0; i < isteps; i++) {
		vec3 ip = r0 + rd * (it + ist * 0.5);
		float ih = length(ip) - R_PLANET;
		float sr = exp(-ih / height_rayleigh) * ist;
		float sm = exp(-ih / height_mie) * ist;
		odr += sr;
		odm += sm;
		float jst = shell(ip, ps, R_AIR).y / float(jsteps);
		float jt = 0.0;
		float jr = 0.0;
		float jm = 0.0;
		for (int j = 0; j < jsteps; j++) {
			vec3 jp = ip + ps * (jt + jst * 0.5);
			float jh = length(jp) - R_PLANET;
			jr += exp(-jh / height_rayleigh) * jst;
			jm += exp(-jh / height_mie) * jst;
			jt += jst;
		}
		vec3 att = exp(-(beta_mie * (odm + jm) + beta_rayleigh * (odr + jr)));
		trl += sr * att;
		tmi += sm * att;
		it += ist;
	}
	return isun * (prl * beta_rayleigh * trl + pmi * beta_mie * tmi);
}

vec3 sky_air(vec3 rd, vec3 cam, int isteps, int jsteps) {
	// below the horizon the air goes on as at the horizon: the island floats
	// over a void, and there is no ground out there to darken it
	vec3 d = normalize(vec3(rd.x, max(rd.y, 0.012), rd.z));
	vec3 r0 = vec3(0.0, R_PLANET + ground_altitude + max(cam.y, 0.0), 0.0);
	vec3 col = atmosphere(d, r0, sun_dir, sun_intensity, isteps, jsteps);
	col += night_air * (0.4 + 0.6 * d.y);
	// a weather's haze, thickest low down
	float hz = haze * (1.0 - smoothstep(-0.05, 0.6, rd.y) * 0.6);
	return mix(col, haze_color, clamp(hz, 0.0, 1.0));
}

float remap(float v, float lo, float hi, float nlo, float nhi) {
	return nlo + (v - lo) / max(hi - lo, 1e-5) * (nhi - nlo);
}

// Cloud density at a point (metres, world), and its height in the layer.
float cloud_density(vec3 p, float alt, bool fine) {
	float h = clamp((alt - cloud_bottom) / (cloud_top - cloud_bottom), 0.0, 1.0);
	vec2 wuv = (p.xz + wind_offset) / weather_scale;
	vec2 wm = texture(cloud_weather, wuv).rg;
	// the type: stratus sits in the bottom of the layer, cumulus fills it
	float t = clamp(cloud_type + (wm.g - 0.5) * 0.4, 0.0, 1.0);
	float top = mix(0.25, 1.0, t);
	float profile = smoothstep(0.0, 0.08 + 0.1 * t, h) * (1.0 - smoothstep(top * 0.55, top, h));
	// where the weather map lets cloud form: about `coverage` of the sky, the
	// rest of it clear, the edge between soft (and all of it at full cover).
	// The map's values sit at 0.32, 0.52 and 0.77 at its 10th, 50th and 90th
	// percentiles (tools/earth/make_sky_noise.py), so the threshold is that
	// spread read backwards
	float mid = 0.52 + 0.5625 * (0.5 - coverage * 0.9);
	float cov = smoothstep(mid - 0.15, mid + 0.15, wm.r);
	cov = max(cov, smoothstep(0.85, 1.0, coverage));
	if (cov * profile <= 0.001) {
		return 0.0;
	}
	vec3 sp = vec3(p.x + wind_offset.x, alt, p.z + wind_offset.y) / shape_scale;
	vec4 s = texture(cloud_shape, sp);
	float fb = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
	float base = remap(s.r, -(1.0 - fb), 1.0, 0.0, 1.0) * profile;
	// and inside it, the billows: the shape noise (most of it between 0.64
	// and 0.92) cut lower the more cover there is
	base = clamp(remap(base, mix(0.9, 0.58, cov), 1.0, 0.0, 1.0), 0.0, 1.0) * cov;
	if (base <= 0.0) {
		return 0.0;
	}
	if (fine) {
		vec3 dp = vec3(p.x + wind_offset.x * 1.4, alt, p.z + wind_offset.y * 1.4) / detail_scale;
		vec3 d = texture(cloud_detail, dp).rgb;
		float df = d.r * 0.625 + d.g * 0.25 + d.b * 0.125;
		float m = mix(df, 1.0 - df, clamp(h * 6.0, 0.0, 1.0));
		base = clamp(remap(base, m * erosion, 1.0, 0.0, 1.0), 0.0, 1.0);
	}
	return base;
}

float hg(float c, float g) {
	float gg = g * g;
	return (1.0 - gg) / (4.0 * PI * pow(max(1.0 + gg - 2.0 * g * c, 1e-4), 1.5));
}

// The clouds along `rd` from `cam`: the light they send (rgb) and how much of
// what is behind them gets through (a).
vec4 clouds(vec3 rd, vec3 cam, vec3 airc) {
	if (coverage <= 0.001 && cirrus <= 0.001) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	vec3 r0 = vec3(0.0, R_PLANET + ground_altitude + cam.y, 0.0);
	vec3 light = sun_dir.y > -0.08 ? sun_dir : moon_dir;
	float light_k = sun_dir.y > -0.08 ? 1.0 : moon_light;
	vec3 col = vec3(0.0);
	float trans = 1.0;
	if (coverage > 0.001 && rd.y > -0.02) {
		vec2 a = shell(r0, rd, R_PLANET + cloud_bottom);
		vec2 b = shell(r0, rd, R_PLANET + cloud_top);
		float t0 = max(a.y, 0.0);
		float t1 = min(b.y, cloud_far);
		if (t1 > t0) {
			float len = t1 - t0;
			float st = len / float(steps);
			float cphase = dot(rd, light);
			float phase = mix(hg(cphase, 0.6), hg(cphase, -0.25), 0.3);
			float jitter = fract(sin(dot(rd.xz * 1000.0, vec2(12.9898, 78.233))) * 43758.5453);
			float t = t0 + st * jitter;
			for (int i = 0; i < steps; i++) {
				if (trans < 0.02) {
					break;
				}
				vec3 pr = r0 + rd * t;
				float alt = length(pr) - R_PLANET;
				vec3 p = cam + rd * t;
				float dens = cloud_density(p, alt, true);
				if (dens > 0.0) {
					// toward the light, in steps that lengthen
					float od = 0.0;
					float ls = (cloud_top - cloud_bottom) / float(light_steps) * 0.5;
					vec3 lp = p;
					float la = alt;
					for (int j = 0; j < light_steps; j++) {
						lp += light * ls;
						la += light.y * ls;
						od += cloud_density(lp, la, false) * ls;
						ls *= 1.6;
					}
					float sigma = density;
					float beer = exp(-od * sigma);
					float powder = 1.0 - exp(-od * sigma * 2.0);
					// and the light that scatters on through the cloud, many
					// times, weaker and less directional each time (two more
					// octaves, after Wrenninge): what lights a low sun's
					// clouds from inside
					float ms = exp(-od * sigma * 0.25) * 0.5 * mix(phase, 0.08, 0.5)
							+ exp(-od * sigma * 0.06) * 0.25 * 0.08;
					float lum = (beer * mix(1.0, powder, 0.5) * phase + ms) * 2.6;
					float h = clamp((alt - cloud_bottom) / (cloud_top - cloud_bottom), 0.0, 1.0);
					vec3 amb = mix(cloud_ambient_bottom, cloud_ambient_top, h);
					vec3 sl = cloud_sun * lum * light_k * (1.0 - gloom * 0.85) + amb * (1.0 - gloom * 0.45);
					float dt = exp(-dens * sigma * st);
					col += trans * sl * (1.0 - dt);
					trans *= dt;
				}
				t += st;
			}
			// far clouds go into the air
			float fade = 1.0 - exp(-t0 / (cloud_far * 0.45));
			col = mix(col, airc * (1.0 - trans), fade);
		}
	}
	// the cirrus, a sheet at nine kilometres, lit and a little see-through
	if (cirrus > 0.001 && rd.y > 0.0) {
		vec2 c = shell(r0, rd, R_PLANET + 9000.0);
		vec3 cp = cam + rd * c.y;
		float ci = texture(cirrus_tex, (cp.xz + cirrus_offset) / 22000.0).r;
		ci = smoothstep(1.0 - cirrus, 1.0, ci) * smoothstep(0.0, 0.15, rd.y) * cirrus;
		vec3 cl = cloud_sun * light_k * (0.6 + 0.6 * hg(dot(rd, light), 0.5) * 4.0) + cloud_ambient_top;
		col += trans * cl * ci * 0.6;
		trans *= 1.0 - ci * 0.6;
	}
	return vec4(col, trans);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 starfield(vec3 rd) {
	vec3 q = rd * 180.0;
	vec3 c = floor(q);
	float h = hash3(c);
	if (h < 0.985) {
		return vec3(0.0);
	}
	vec3 f = fract(q) - 0.5;
	float d = length(f);
	float tw = 0.65 + 0.35 * sin(TIME * (2.0 + 6.0 * hash3(c + 3.1)) + h * 40.0);
	float b = smoothstep(0.45, 0.05, d) * pow((h - 0.985) / 0.015, 2.0) * tw;
	vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.85, 0.7), hash3(c + 7.7));
	return tint * b * 3.0;
}

// The bolt: a jagged line from the clouds down toward the horizon round
// `bolt_dir`, as seen; its brightness `bolt`.
float lightning(vec3 rd) {
	if (bolt <= 0.0) {
		return 0.0;
	}
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, bolt_dir));
	float x = dot(rd, right);
	float y = rd.y;
	float top = 0.32;
	float bot = 0.0;
	if (y > top || y < bot || dot(rd, bolt_dir) < 0.8) {
		return 0.0;
	}
	float k = (top - y) / (top - bot);
	float off = 0.0;
	float amp = 0.035;
	float fr = 6.0;
	for (int o = 0; o < 4; o++) {
		off += (fract(sin(floor(k * fr) * 91.7 + bolt_seed * 13.1 + float(o) * 7.3) * 4375.85) - 0.5) * amp;
		amp *= 0.5;
		fr *= 2.3;
	}
	float d = abs(x - off * k * 2.0);
	return bolt * smoothstep(0.004, 0.0, d) * (1.0 - k * 0.3);
}

void sky() {
	vec3 rd = EYEDIR;
	vec3 cam = POSITION;
	if (AT_CUBEMAP_PASS) {
		// the radiance the island never reads much of: the air alone, cheaply
		COLOR = sky_air(rd, cam, 8, 3) * exposure + vec3(flash * 0.4);
	} else if (AT_QUARTER_RES_PASS) {
		vec3 air = sky_air(rd, cam, 12, 4);
		vec4 cl = clouds(rd, cam, air);
		COLOR = air * cl.a + cl.rgb;
		ALPHA = cl.a;
	} else {
		vec3 col;
		float through;
		if (clouds_in_main) {
			vec3 air = sky_air(rd, cam, 12, 4);
			vec4 cl = clouds(rd, cam, air);
			col = air * cl.a + cl.rgb;
			through = cl.a;
		} else {
			col = QUARTER_RES_COLOR.rgb;
			through = QUARTER_RES_COLOR.a;
		}
		// the sun, through the air and the clouds
		float sd = dot(rd, sun_dir);
		if (sd > sun_size - 0.002) {
			float disc = smoothstep(sun_size - 0.0004, sun_size + 0.0002, sd);
			vec3 sun_t = exp(-(beta_rayleigh * 8000.0 + vec3(beta_mie * 1200.0))
					/ max(sun_dir.y + 0.06, 0.02) * 0.9);
			col += sun_t * disc * 40.0 * through;
		}
		// the moon: its face lit from where the sun really is
		float md = dot(rd, moon_dir);
		if (md > moon_size - 0.0005) {
			vec3 w = moon_dir;
			vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), w));
			vec3 upv = cross(w, right);
			float rad = sqrt(max(1.0 - moon_size * moon_size, 1e-8));
			vec2 l = vec2(dot(rd, right), dot(rd, upv)) / rad;
			float r2 = dot(l, l);
			if (r2 < 1.0) {
				vec3 n = normalize(l.x * right + l.y * upv - sqrt(1.0 - r2) * w);
				float lit = smoothstep(-0.05, 0.15, dot(n, sun_dir));
				float face = texture(moon_tex, l * 0.5 + 0.5).r;
				float night = 1.0 - smoothstep(-0.1, 0.15, sun_dir.y) * 0.75;
				col += vec3(0.95, 0.93, 0.88) * (face * lit + 0.012) * 1.4 * night * through
						* smoothstep(1.0, 0.9, r2);
			}
		}
		// the stars, where it is dark enough and the clouds let them through
		float dark = 1.0 - smoothstep(-0.18, 0.02, sun_dir.y);
		if (stars * dark > 0.0 && rd.y > 0.0) {
			col += starfield(rd) * stars * dark * through * smoothstep(0.0, 0.12, rd.y);
		}
		col += vec3(0.8, 0.85, 1.0) * (flash * (0.35 + 0.65 * (1.0 - through)) + lightning(rd) * 6.0);
		COLOR = col * exposure;
	}
}
