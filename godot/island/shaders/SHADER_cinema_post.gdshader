shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;
#include "res://godot/shaders/thermal_base.gdshaderinc"

// THE CINEMA (at the user's request: "make it look fucking cinematic as hell —
// colorgrading, sun flare, god rays"): what a camera's lens and the air add to
// a picture with the sun in it, as one full-screen pass over the 3D world
// (SCRIPT_cinema_post.gd puts it there). The grade is the picture filter's
// (lofi.gdshader); this is the light.
//
//   GOD RAYS. Light scattered toward the eye by the air between it and what
//   it looks at, where the sun reaches that air — the shafts that fan out
//   past a ridge or a cloud's edge. Screen-space, as Mitchell's "Volumetric
//   Light Scattering as a Post-Process" (GPU Gems 3, 13): from each pixel a
//   march toward the sun on the screen, adding up what it passes that is open
//   SKY near the sun (the depth buffer says which pixels are sky) by its own
//   colour, so a cloud between dims the shafts and a gap lets one through,
//   and the ground, the trees and the cliffs block them.
//
//   THE FLARE. A lens looking into the sun: its glow and a six-pointed
//   starburst from the aperture's blades, a long blue anamorphic streak
//   across the picture (the widescreen lens's tell), a halo ring with its
//   colours split, and ghosts — the iris reflected between the elements —
//   strung along the line from the sun through the middle of the frame. All
//   of it scaled by how much of the sun is in sight: the depth and colour at
//   a dozen points over its disc, so it goes as the sun goes behind a peak
//   and dims through cloud.
//
//   THE GLOW. Bright things bleed light round them (bloom: the screen's own
//   mips, over a threshold), and air with the sun behind it glows (the haze
//   between the eye and the far ground, scattered forward by the Mie lobe
//   the sky itself uses), so a valley looked at into the light goes soft
//   and gold.
//
// ADDED, never mixed: the water is drawn after the picture this reads (it is
// transparent), so painting the picture back would erase it. Everything here
// is light the scene did not have, added over whatever is there.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

group_uniforms rays;
uniform float rays_strength : hint_range(0.0, 4.0) = 1.0;
// how far toward the sun each pixel looks, as a share of the way
uniform float rays_length : hint_range(0.1, 1.0) = 0.9;
// each step's weight on the next: the shafts' fall-off
uniform float rays_decay : hint_range(0.8, 1.0) = 0.965;
// how tight round the sun the sky that sends them is (higher, tighter)
uniform float rays_focus = 9.0;
uniform int rays_samples : hint_range(8, 96) = 40;

group_uniforms flare;
uniform float flare_strength : hint_range(0.0, 4.0) = 1.0;
uniform float glow_strength : hint_range(0.0, 4.0) = 1.0;
uniform float streak_strength : hint_range(0.0, 4.0) = 0.8;
uniform vec3 streak_color = vec3(0.45, 0.62, 1.0);
uniform float ghost_strength : hint_range(0.0, 4.0) = 1.0;

group_uniforms glow;
uniform float bloom_strength : hint_range(0.0, 2.0) = 0.45;
uniform float bloom_threshold : hint_range(0.0, 1.5) = 0.72;
uniform float haze_strength : hint_range(0.0, 4.0) = 1.0;
// per metre: how fast the air between fills with light
uniform float haze_density = 0.00045;
uniform float haze_g : hint_range(0.0, 0.95) = 0.7;

group_uniforms;
// (1 shows the sky mask, 2 the raw depth, 3 where the sun is, for tuning)
uniform int debug_view = 0;

global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
global uniform float tod_fog_density;
global uniform float tod_daylight;


void vertex() {
	// the whole screen, whatever the camera (the mesh is a 2 x 2 quad)
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

float raw_depth(vec2 uv) {
	return textureLod(depth_tex, uv, 0.0).r;
}

// Open sky at `uv`: nothing drawn there but the sky, which sits at the far
// plane — 0 in the reversed depth every renderer of this Godot keeps (1 in
// the old way round, which nothing nearer than the near plane reaches).
bool is_sky(vec2 uv) {
	float d = raw_depth(uv);
	return d <= 0.0000001 || d >= 0.9999999;
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = raw_depth(uv);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// interleaved gradient noise (Jimenez): a different start for each pixel's
// march, so its steps blur together instead of banding
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float hg(float c, float g) {
	float gg = g * g;
	return (1.0 - gg) / (4.0 * PI * pow(max(1.0 + gg - 2.0 * g * c, 1e-4), 1.5));
}

// A soft disc, 1 inside radius r, gone by r * (1 + soft).
float disc(float d, float r, float soft) {
	return 1.0 - smoothstep(r, r * (1.0 + soft), d);
}

// A hexagon's distance (the iris): its inscribed radius at 1.
float hexd(vec2 p) {
	p = abs(p);
	return max(p.x * 0.866025 + p.y * 0.5, p.y);
}

void fragment() {
	// (nothing through the thermal sight: it sees heat, not light)
	if (thermal_on(VIEWPORT_SIZE)) {
		ALBEDO = vec3(0.0);
	} else {
		vec2 uv = SCREEN_UV;
		float asp = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
		vec3 sun_c = tod_sun_color.rgb;
		float sun_l = luma(sun_c);
		vec3 add = vec3(0.0);

		// ---- where the sun is on the screen --------------------------------
		vec3 sv = (VIEW_MATRIX * vec4(tod_sun_dir, 0.0)).xyz;
		vec4 sc = PROJECTION_MATRIX * vec4(sv, 0.0);
		// (ahead of the eye at all, fading as it swings out to the side)
		float ahead = smoothstep(0.0, 0.25, -sv.z);
		vec2 sun_uv = sc.xy / max(sc.w, 1e-4) * 0.5 + 0.5;
		vec2 sun_a = (sun_uv - 0.5) * vec2(asp, 1.0);
		vec2 here_a = (uv - 0.5) * vec2(asp, 1.0);

		// ---- how much of it is in sight ------------------------------------
		// (a dozen points over a small disc round it: open sky, and bright — a
		// cloud over it is sky, but dim)
		float seen = 0.0;
		if (ahead > 0.0 && sun_l > 0.002) {
			float inside = 0.0;
			for (int i = 0; i < 12; i++) {
				float a = float(i) * 2.3999632;
				float r = 0.004 + 0.012 * sqrt(float(i) / 12.0);
				vec2 q = sun_uv + vec2(cos(a), sin(a)) * r * vec2(1.0 / asp, 1.0);
				if (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0) {
					inside += 1.0;
					if (is_sky(q)) {
						seen += smoothstep(0.35, 0.85, luma(textureLod(screen_tex, q, 0.0).rgb));
					}
				}
			}
			seen = inside > 0.0 ? seen / 12.0 : 0.0;
			// (off the edge of the frame the flare fades, as the lens stops
			// seeing it)
			vec2 e = min(sun_uv, 1.0 - sun_uv);
			seen *= smoothstep(-0.02, 0.06, min(e.x, e.y));
			seen *= ahead;
		}

		// ---- god rays -------------------------------------------------------
		if (rays_strength > 0.0 && ahead > 0.0 && sun_l > 0.002) {
			// (fewer steps the more pixels there are: the default picture is a
			// few hundred thousand, a phone's own screen millions)
			int n = int(clamp(float(rays_samples) * sqrt(250000.0 / max(VIEWPORT_SIZE.x * VIEWPORT_SIZE.y, 1.0)),
					12.0, float(rays_samples)));
			vec2 step_uv = (uv - sun_uv) * rays_length / float(n);
			vec2 p = uv - step_uv * ign(FRAGCOORD.xy);
			float w = 1.0;
			float wsum = 0.0;
			vec3 acc = vec3(0.0);
			for (int i = 0; i < 96; i++) {
				if (i >= n) {
					break;
				}
				p -= step_uv;
				vec2 q = clamp(p, vec2(0.001), vec2(0.999));
				if (is_sky(q)) {
					vec2 dq = (q - sun_uv) * vec2(asp, 1.0);
					float near = exp(-dot(dq, dq) * rays_focus);
					vec3 s = textureLod(screen_tex, q, 0.0).rgb;
					// (the sky's own light near the sun, its brightest part most)
					acc += s * smoothstep(0.25, 1.0, luma(s)) * near * w;
				}
				wsum += w;
				w *= rays_decay;
			}
			vec3 rays = acc / max(wsum, 1e-4);
			// tinted toward the sun's own colour (gold when it is low)
			vec3 tint = sun_c / max(max(sun_c.r, max(sun_c.g, sun_c.b)), 1e-3);
			add += rays * mix(vec3(1.0), tint, 0.6) * rays_strength * ahead * 0.6;
		}

		// ---- the flare ------------------------------------------------------
		if (seen > 0.001 && flare_strength > 0.0) {
			vec3 tint = sun_c / max(max(sun_c.r, max(sun_c.g, sun_c.b)), 1e-3);
			float k = seen * flare_strength * clamp(sun_l * 1.2, 0.0, 1.0);
			vec2 d = here_a - sun_a;
			float r = length(d);
			// the glow, and the starburst off six blades
			float core = exp(-r * 40.0) * 0.6 + exp(-r * 9.0) * 0.12 + exp(-r * 2.5) * 0.03;
			float ang = atan(d.y, d.x);
			float star = pow(abs(cos(ang * 3.0 + 0.4)), 60.0) * exp(-r * 7.5) * 0.3;
			add += tint * (core + star) * k * glow_strength;
			// the anamorphic streak: long across, a hair tall
			float streak = exp(-abs(d.y) * 260.0) * exp(-abs(d.x) * 1.5) * 0.55
					+ exp(-abs(d.y) * 60.0) * exp(-abs(d.x) * 4.0) * 0.12;
			add += streak_color * streak * k * streak_strength;
			// the halo, its colours split
			vec3 ring = vec3(disc(abs(r - 0.42), 0.006, 3.0), disc(abs(r - 0.43), 0.006, 3.0),
					disc(abs(r - 0.44), 0.006, 3.0));
			add += ring * 0.03 * k * ghost_strength;
			// the ghosts, down the line from the sun through the middle and past
			// it: (where along it, size, colour)
			vec3 g = vec3(0.0);
			vec2 axis = -sun_a;
			g += vec3(0.95, 0.75, 0.40) * disc(hexd((here_a - (sun_a + axis * 0.45)) / 0.05), 1.0, 0.25) * 0.10;
			g += vec3(0.40, 0.85, 0.65) * disc(length(here_a - (sun_a + axis * 0.75)), 0.022, 0.6) * 0.16;
			g += vec3(0.55, 0.60, 1.00) * disc(hexd((here_a - (sun_a + axis * 1.35)) / 0.11), 1.0, 0.15) * 0.07;
			g += vec3(1.00, 0.55, 0.45) * disc(length(here_a - (sun_a + axis * 1.6)), 0.05, 0.4) * 0.07;
			g += vec3(0.50, 0.70, 1.00) * disc(hexd((here_a - (sun_a + axis * 2.1)) / 0.2), 1.0, 0.1) * 0.035;
			g += vec3(0.85, 0.95, 0.60) * disc(length(here_a - (sun_a + axis * 2.6)), 0.012, 0.8) * 0.2;
			add += g * k * ghost_strength;
		}

		// ---- bloom and the lit haze ----------------------------------------
		if (bloom_strength > 0.0) {
			vec3 b = vec3(0.0);
			vec2 px = 1.0 / VIEWPORT_SIZE;
			for (int i = 0; i < 4; i++) {
				vec2 o = vec2(i == 0 || i == 3 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
				b += max(textureLod(screen_tex, uv + o * px * 3.0, 2.0).rgb - bloom_threshold, 0.0) * 0.5;
				b += max(textureLod(screen_tex, uv + o * px * 9.0, 3.5).rgb - bloom_threshold, 0.0) * 0.35;
				b += max(textureLod(screen_tex, uv + o * px * 24.0, 5.0).rgb - bloom_threshold, 0.0) * 0.3;
			}
			add += b * 0.25 * bloom_strength;
		}
		if (haze_strength > 0.0 && sun_l > 0.002 && !is_sky(uv)) {
			vec3 vp = view_pos(uv, INV_PROJECTION_MATRIX);
			float dist = length(vp);
			vec3 rd = normalize((INV_VIEW_MATRIX * vec4(vp, 0.0)).xyz);
			float mu = dot(rd, tod_sun_dir);
			float fill = 1.0 - exp(-dist * haze_density * max(tod_fog_density, 0.2));
			// (the forward lobe, at 1 looking straight into the sun, and a
			// little of the sun's light everywhere)
			float phase = hg(mu, haze_g) / hg(1.0, haze_g) * 0.6 + 0.04;
			add += sun_c * fill * phase * haze_strength * 0.5 * smoothstep(-0.02, 0.1, tod_sun_dir.y);
		}

		if (debug_view == 1) {
			add = is_sky(uv) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
		} else if (debug_view == 2) {
			add = vec3(raw_depth(uv));
		} else if (debug_view == 3) {
			add = vec3(1.0 - smoothstep(0.0, 0.03, length(here_a - sun_a)), seen, ahead);
		}
		ALBEDO = add;
	}
}
