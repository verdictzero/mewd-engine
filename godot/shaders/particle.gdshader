// MEWD — particles: little billboards (js/particles.js).
// Each instance: its origin the particle, COLOR its colour and alpha
// (already lerped over its life), INSTANCE_CUSTOM x its size in units,
// y its frame. The picture is procedural — a ragged flame puff whose
// shape changes with the frame — unless `map` is set (then frames
// side by side in it). Additive or mixed by the material's blend mode,
// which the owner picks; fullbright either way, or lit by `light`.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D map : source_color, filter_nearest;
uniform bool has_map = false;
uniform float frames = 8.0;
uniform float near_shrink = 0.0;
uniform float fullbright = 1.0;
uniform float light = 1.0;
uniform float soft = 0.0;   // 1: a round soft blob (smoke) rather than a flame

varying vec4 col;
varying float frame;
varying float depth;

void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 view_at = (VIEW_MATRIX * vec4(at, 1.0)).xyz;
	float d = -view_at.z;
	float shrink = near_shrink > 0.0 ? clamp(d / near_shrink, 0.12, 1.0) : 1.0;
	float size = INSTANCE_CUSTOM.x * shrink;
	VERTEX = view_at + vec3(VERTEX.xy * size, 0.0);
	depth = -VERTEX.z;
	col = COLOR;
	frame = INSTANCE_CUSTOM.y;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec4 t;
	if (has_map) {
		t = texture(map, vec2((UV.x + frame) / frames, UV.y));
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float n = noise(p * 3.0 + vec2(frame * 1.7, frame * 2.3)) * 0.5 + noise(p * 6.0 - frame) * 0.25;
		float r = length(p);
		float body = soft > 0.5 ? 1.0 - smoothstep(0.2, 1.0, r) : 1.0 - smoothstep(0.35 + n * 0.5, 0.75 + n * 0.3, r);
		// chunky: the puff in eight steps, so it reads as painted
		body = floor(body * 8.0) / 8.0;
		// hot in the middle, red at the ragged edge, as a fireball is
		vec3 ramp = soft > 0.5 ? vec3(1.0) : mix(vec3(0.85, 0.22, 0.04), vec3(1.0, 0.86, 0.52), body * body);
		t = vec4(ramp, body);
	}
	float a = t.a * col.a;
	if (a < 0.02) discard;
	float l = mix(world_band(light, depth, 1.0), 1.0, fullbright);
	ALBEDO = world_air(t.rgb * col.rgb * l, depth);
	// the thermal sight's feed: a flame is a source and white, a puff the
	// surface it would be (thermal.gdshaderinc)
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(t.rgb * col.rgb, l, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, fullbright));
	ALPHA = a;
}
