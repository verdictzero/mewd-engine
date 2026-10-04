// MEWD — THE REENTRY FIRE round the drop pod (DropPod `fire`, at the
// user's request: "descent needs to be 300% faster with reentry fireball
// until slowdown"). Two meshes turned to the way the pod is going, the
// way it goes being local -y:
//   tail 0  THE CAP: a squashed ball round the heat shield — yellow-white
//           at the front, orange round the rim, nothing over the shield
//   tail 1  THE SHEATH: a cone of flame from the shield's rim streaming
//           back up the hull and past it, in streaks, orange to red to
//           nothing
// Both torn by noise running back along them, so the fire roils. `heat`
// (0..1) is how fast the pod is going over the speed it starts to burn
// at; the fire goes as it slows.
// MIXED, NOT ADDED: the pod comes in against a bright sky, and light added
// to it is white; a fire laid over it in its own colours reads as fire.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float tail = 0.0;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// value noise that wraps every `wrap` cells across (round the axis)
float vnoise(vec2 p, float wrap) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float i0 = mod(i.x, wrap);
	float i1 = mod(i.x + 1.0, wrap);
	return mix(mix(hash(vec2(i0, i.y)), hash(vec2(i1, i.y)), f.x),
		mix(hash(vec2(i0, i.y + 1.0)), hash(vec2(i1, i.y + 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// round the axis, 0..1
	float ang = atan(lp.z, lp.x) / 6.2831853 + 0.5;
	float t = TIME;
	float a;
	vec3 col;
	if (tail > 0.5) {
		// the cone: -0.5 (its wide base, at the shield) to 0.5
		float k = clamp(lp.y + 0.5, 0.0, 1.0);
		// long streaks: fine round the axis, stretched along it, running back
		float s = vnoise(vec2(ang * 18.0, k * 3.0 - t * 4.5), 18.0) * 0.6
			+ vnoise(vec2(ang * 41.0, k * 7.0 - t * 8.0), 41.0) * 0.4;
		float streak = smoothstep(0.3, 0.72, s);
		float fade = pow(1.0 - k, 1.5) * smoothstep(0.0, 0.05, k);
		a = streak * fade * (0.45 + 0.55 * face) * 1.35;
		col = mix(vec3(1.0, 0.86, 0.42), vec3(1.0, 0.42, 0.08), smoothstep(0.0, 0.3, k));
		col = mix(col, vec3(0.62, 0.1, 0.04), smoothstep(0.35, 0.85, k));
	} else {
		// the ball: -1 (the front) to 1; only its front half burns
		float k = clamp(lp.y * 0.5 + 0.5, 0.0, 1.0);
		float n = vnoise(vec2(ang * 14.0, k * 6.0 - t * 9.0), 14.0) * 0.5
			+ vnoise(vec2(ang * 31.0, k * 15.0 - t * 17.0), 31.0) * 0.5;
		a = (1.0 - smoothstep(0.18, 0.55, k)) * (0.55 + 0.45 * n) * (0.5 + 0.5 * face);
		col = mix(vec3(1.0, 0.97, 0.78), vec3(1.0, 0.55, 0.14), smoothstep(0.05, 0.42, k));
	}
	ALBEDO = col;
	ALPHA = clamp(a * heat, 0.0, 0.95);
	if (thermal_on(VIEWPORT_SIZE)) ALPHA = 0.0;
}
