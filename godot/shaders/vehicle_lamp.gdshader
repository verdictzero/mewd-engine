// MEWD — the light bar (js/bloom.js LAMP_FRAG, without the bloom).
//
// The police van arrives with its light bar on its own material, and
// here it flashes: two strobes a side, a third of a second each, which
// is the rhythm of a real one. Every van runs its own `phase`, off where
// it came on, so a convoy does not flash in step. The web build draws
// the bar a second time into a blurred bloom layer; this draws the lens
// as a fullbright emissive flash, which is what the task asked for, and
// leaves the halo out.
//
// UV.x carries how far to the LEFT of the bar's middle each vertex is
// (the sign is which half), so a face spanning the whole bar is split
// per pixel rather than down its own diagonal.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform vec3 left_lens = vec3(1.0, 0.06, 0.04);
uniform vec3 right_lens = vec3(0.10, 0.25, 1.0);
uniform float phase = 0.0;
uniform float cycle = 0.66;       // FLASH_CYCLE: one whole cycle, in seconds
uniform bool dark = false;        // the van has gone up: lightsOut

varying float side;

void vertex() {
	side = UV.x;
}

void fragment() {
	if (dark) {
		ALBEDO = vec3(0.10, 0.047, 0.063);   // 0x1a0c10
	} else {
		// WHICH HALF IS ON: red first, then blue, two strobes each
		float t = fract(TIME / cycle + phase);
		float s = side > 0.0 ? step(t, 0.5) : step(0.5, t);
		float strobe = step(fract(t * 4.0), 0.62);
		float on = s * strobe;
		vec3 lens = side > 0.0 ? left_lens : right_lens;
		// the lens lit, pushed toward white the way the bloom's core does
		ALBEDO = mix(lens * 0.16, mix(lens, vec3(1.0), 0.28) * 1.6, on);
		// through the thermal sight a lamp is a lamp: warm, and hot when lit
		if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(0.55 + 0.35 * on);
	}
}
