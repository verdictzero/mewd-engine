// MEWD — THE REENTRY PLASMA round the drop pod (DropPod `fire`, at the
// user's request: "a reentry shield-ish shaped plasma barrier spewing
// out at an angle similar to the bottom of the shield", "multilayered,
// higher res, colour shifts"). Three meshes, all turned to the way the
// pod is going (local -y), `layer` telling which:
//   0  THE BOW SHOCK: a dish standing off the heat shield, the shield's
//      own shape — the hottest, white-blue at its middle, yellow at its
//      rim, only its front half drawn
//   1  THE SKIRT: a sheet of plasma off the shield's rim, flaring out
//      and back at the angle of the hull's foot — a shuttlecock —
//      white-yellow at the rim, orange out along it, torn into streaks
//      running outward at speed, gone at its outer edge
//   2  THE WAKE: the same, wider and further back, thin and red
// Smooth noise at two scales (higher res than the blocky cut before).
// `heat` is how fierce (0..1); `age` (0..1) shifts the whole thing as it
// dies: blue-white at 0, through orange, to a dull red at 1. Mixed, not
// added (against a bright sky an added fire is a pale lampshade).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform float layer = 0.0;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// value noise wrapping every `wrap` cells across (round the axis)
float vnoise(vec2 p, float wrap) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, wrap);
	float i1 = mod(i.x + 1.0, wrap);
	return mix(mix(hash(vec2(i0, i.y)), hash(vec2(i1, i.y)), f.x),
		mix(hash(vec2(i0, i.y + 1.0)), hash(vec2(i1, i.y + 1.0)), f.x), f.y);
}

// the plasma's colour at `k` along (0 hottest) as it ages
vec3 plasma(float k) {
	vec3 core = mix(vec3(0.9, 0.95, 1.0), vec3(1.0, 0.92, 0.6), age);
	vec3 mid = mix(vec3(1.0, 0.75, 0.3), vec3(1.0, 0.45, 0.1), age * 0.7 + 0.2);
	vec3 far = mix(vec3(1.0, 0.45, 0.1), vec3(0.6, 0.08, 0.02), age);
	vec3 c = mix(core, mid, smoothstep(0.0, 0.4, k));
	return mix(c, far, smoothstep(0.4, 1.0, k));
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float ang = atan(lp.z, lp.x) / 6.2831853 + 0.5;
	float t = TIME;
	float a;
	vec3 col;
	if (layer < 0.5) {
		// the dish: -1 (its front) to 1
		float k = clamp(lp.y * 0.5 + 0.5, 0.0, 1.0);
		float n = vnoise(vec2(ang * 16.0, k * 8.0 - t * 14.0), 16.0) * 0.5
			+ vnoise(vec2(ang * 40.0, k * 20.0 - t * 30.0), 40.0) * 0.5;
		a = (1.0 - smoothstep(0.3, 0.55, k)) * (0.7 + 0.3 * n) * (0.7 + 0.3 * face) * 1.3;
		col = plasma(0.1 + k * 1.3);
	} else {
		// the skirt or the wake: 0 at the rim, 1 at the outer edge
		float k = clamp(lp.y + 0.5, 0.0, 1.0);
		float speed = layer < 1.5 ? 9.0 : 6.0;
		float s = vnoise(vec2(ang * 24.0, k * 4.0 - t * speed), 24.0) * 0.55
			+ vnoise(vec2(ang * 64.0, k * 10.0 - t * speed * 2.2), 64.0) * 0.45;
		float streak = smoothstep(0.28, 0.7, s);
		float fade = pow(1.0 - k, 1.1) * smoothstep(0.0, 0.04, k);
		if (layer < 1.5) {
			a = (0.5 + 0.5 * streak) * fade * (0.6 + 0.4 * face) * 1.8;
			col = plasma(0.2 + k * 0.8);
		} else {
			a = streak * fade * (0.5 + 0.5 * face) * 1.0;
			col = plasma(0.6 + k * 0.4);
		}
	}
	ALBEDO = col;
	ALPHA = clamp(a * heat, 0.0, 0.95);
	if (thermal_on(VIEWPORT_SIZE)) ALPHA = 0.0;
}
