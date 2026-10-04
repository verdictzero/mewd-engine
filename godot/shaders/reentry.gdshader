// MEWD — THE REENTRY FIRE round the drop pod (DropPod `fire`, at the
// user's request: a reentry fireball until the slowdown; then "lower res,
// faster, shallower, more violent"). Two meshes turned to the way the pod
// is going, the way it goes being local -y:
//   tail 0  THE CAP: a squashed ball round the heat shield — yellow-white
//           at the front, orange round the rim, nothing over the shield
//   tail 1  THE SHEATH: a short cone of flame from the shield's rim up
//           the hull, in streaks, orange to red to nothing
// Both torn by noise running back along them at speed. LOW-RES: the
// noise is read on a coarse grid (CELLS cells round, a few along) and the
// colour and the cover are stepped to a handful of levels, so the fire
// is blocks that flip rather than a smooth roil; VIOLENT: the cover
// flickers hard, whole cells blink on and off. `heat` (0..1) is how hot;
// the fire goes as it dies. Mixed, not added (against a bright sky an
// added fire is a pale white lampshade).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float tail = 0.0;
const float CELLS = 14.0;
const float LEVELS = 4.0;

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float stepped(float v) {
	return floor(v * LEVELS + 0.5) / LEVELS;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	// round the axis, 0..1, on the grid
	float ang = atan(lp.z, lp.x) / 6.2831853 + 0.5;
	float cell = floor(ang * CELLS);
	// time in frames of a fast flicker
	float t = floor(TIME * 24.0);
	float a;
	vec3 col;
	if (tail > 0.5) {
		// the cone: -0.5 (its wide base, at the shield) to 0.5
		float k = clamp(lp.y + 0.5, 0.0, 1.0);
		float row = floor(k * 5.0);
		// each cell's streak: lit or not this frame, running up the hull
		float n = hash(vec2(cell, row - t));
		float n2 = hash(vec2(cell * 3.0 + 7.0, t));
		float lit = step(0.12 + 0.45 * k, n) * step(0.1, n2);
		a = lit * stepped(1.0 - k * 0.8);
		col = mix(vec3(1.0, 0.85, 0.4), vec3(1.0, 0.4, 0.08), stepped(smoothstep(0.0, 0.3, k)));
		col = mix(col, vec3(0.6, 0.1, 0.03), stepped(smoothstep(0.35, 0.9, k)));
	} else {
		// the ball: -1 (the front) to 1; only its front half burns
		float k = clamp(lp.y * 0.5 + 0.5, 0.0, 1.0);
		float row = floor(k * 6.0);
		float n = hash(vec2(cell, row + t));
		float lit = step(0.06 + 0.4 * k, n);
		a = lit * stepped(1.0 - smoothstep(0.15, 0.5, k)) * (0.75 + 0.25 * hash(vec2(t, cell)));
		col = mix(vec3(1.0, 0.97, 0.8), vec3(1.0, 0.55, 0.14), stepped(smoothstep(0.05, 0.4, k)));
	}
	ALBEDO = col;
	ALPHA = clamp(a * heat, 0.0, 0.95);
	if (thermal_on(VIEWPORT_SIZE)) ALPHA = 0.0;
}
