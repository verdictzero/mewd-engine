// MEWD — a standee: a sprite that turns about the vertical to face the
// eye, Doom's billboard (js/standees.js). One MultiMesh per strip; each
// instance's origin is the feet, and INSTANCE_CUSTOM carries
//   x  the cell in the strip
//   y  the light (sector light times the actor's own `lit`)
//   z  how much of that light is sky
//   w  flags: +1 mirrored, +2 fullbright, and for the thermal sight alone
//      +4 a body (warm whatever it wears), +8 frozen, +16 alight;
//      +32 swaying where they stand, +64 running; and from 128 up the
//      phase of the sway (the actor's id), so the crowd does not lean
//      as one
// The quad is `cell` units: a sprite is drawn one unit to the pixel.
// THE SWAY is worked out here off TIME (js/people.js SWAY), so the
// crowd's rows need not be written for it (render/standees.gd).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D strip : source_color, filter_nearest;
uniform float cells = 1.0;
uniform vec2 cell = vec2(40.0, 64.0);

varying float depth;
varying float light;
varying float sky;
varying float fullbright;
varying float warm;
varying float frozen;
varying float alight;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float flags = cd.w;
	float mirror = mod(flags, 2.0);
	fullbright = mod(floor(flags / 2.0), 2.0);
	warm = mod(floor(flags / 4.0), 2.0);
	frozen = mod(floor(flags / 8.0), 2.0);
	alight = mod(floor(flags / 16.0), 2.0);
	float stands = mod(floor(flags / 32.0), 2.0);
	float runs = mod(floor(flags / 64.0), 2.0);
	float phase = floor(flags / 128.0);
	light = cd.y;
	sky = cd.z;
	vec3 feet = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// the lean where they stand, harder and faster when running
	if (stands + runs > 0.5) {
		float t = (TIME * 35.0 + phase * 37.0) * 0.055 * (runs > 0.5 ? 4.0 : 1.0);
		float lean = sin(t) * 1.3 * (runs > 0.5 ? 1.6 : 1.0);
		float bob = abs(sin(t * 2.0 + phase)) * 0.7 * (runs > 0.5 ? 3.0 : 1.0) - 0.7 * runs;
		// (map x, y) is (x, -z) here
		feet += vec3(cos(phase) * lean, bob, -sin(phase) * lean);
	}
	// the eye's right, flattened: the card turns about Y only
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 world = feet + right * VERTEX.x * cell.x + vec3(0.0, VERTEX.y * cell.y, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	depth = -VERTEX.z;
	float u = mirror > 0.5 ? 1.0 - UV.x : UV.x;
	UV = vec2((cd.x + u) / cells, UV.y);
}

void fragment() {
	vec4 c = texture(strip, UV);
	if (c.a < 0.5) discard;
	float l = mix(world_band(light, depth, sky), 1.0, fullbright);
	// the map's ambient light and fog too, but not on what is its own light
	ALBEDO = world_fog(world_air(c.rgb * world_lit(l) - c.rgb * ambient_light.rgb * fullbright, depth), depth * (1.0 - fullbright));
	// THROUGH THE THERMAL SIGHT a person is warm whatever colour their coat
	// is, a frozen one the coldest thing there is, a burning one white
	// (js/material.js, the THERMAL block of COMMON_FRAG)
	if (thermal_on(VIEWPORT_SIZE)) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h = thermal_of(c.rgb, l, depth, wp, fullbright);
		if (warm > 0.5 && fullbright < 0.5) h = thermal_body(c.rgb, depth);
		h = mix(h, 0.02, frozen);
		h = max(h, alight);
		ALBEDO = thermal_out(h);
	}
}
