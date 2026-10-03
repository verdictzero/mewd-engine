// MEWD — THE SUN'S ANAMORPHIC FLARE, at the user's request for CANDY
// LAND: the long horizontal streak a widescreen lens throws off a bright
// light, laid over the frame where the candy sun is, with a round
// glare at its middle — so the happy sun is BRIGHT.
//
// A screen pass and not a thing in the world: the mesh is a quad whose
// corners are put straight into clip space (skip_vertex_transform), as a
// band across the whole width of the screen at the sun's height, and the
// fragment adds the streak into whatever is there (blend_add, no depth
// test). When the sun is behind the eye, or off the top or bottom of the
// screen by more than the band, the quad is collapsed and costs nothing.
//
// IT GOES OUT BEHIND THINGS: five reads of the depth buffer round the sun
// (the middle and four points on a ring half the picture's radius out) —
// a pixel where the sky is has the far depth (0, reversed Z) — and the
// streak is scaled by the share of them that see sky. So a tree or a hill
// across the sun dims it, and a canopy puts it out.
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;
#include "res://godot/shaders/thermal_base.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// toward the sun, in the world: the time-of-day bus's, off the scene's
// SunPivot (the sky draws the candy sun there too)
global uniform vec3 tod_sun_dir;
// the sun's angular radius (the sky's apex_sun_size), for the occlusion ring
uniform float sun_radius = 0.16;
uniform vec3 streak_color : source_color = vec3(0.5, 0.75, 1.0);
uniform vec3 core_color : source_color = vec3(1.0, 0.88, 0.6);
uniform float strength : hint_range(0.0, 4.0) = 1.0;
// how far the streak reaches either side, in screen widths
uniform float streak_reach = 0.9;
// how thick it is, in screen heights
uniform float streak_thickness = 0.006;
// the band the quad covers, in NDC either side of the sun
uniform float band = 0.45;

varying flat vec2 sun_ndc;
varying flat float sun_r;

void vertex() {
	vec3 sun_dir = length(tod_sun_dir) > 0.5 ? normalize(tod_sun_dir) : vec3(0.0, 1.0, 0.0);
	vec3 v = (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz;
	vec4 c = PROJECTION_MATRIX * vec4(v * 1000.0, 1.0);
	sun_ndc = c.xy / max(c.w, 1e-4);
	// the ring's radius on the screen, in NDC y
	sun_r = tan(sun_radius) * PROJECTION_MATRIX[1][1];
	bool shown = c.w > 0.0 && abs(sun_ndc.y) < 1.0 + band && abs(sun_ndc.x) < 2.5;
	// QuadMesh 2 x 2: VERTEX.xy is -1..1
	vec2 here = vec2(VERTEX.x, sun_ndc.y + VERTEX.y * band);
	POSITION = shown ? vec4(here, 0.5, 1.0) : vec4(2.0, 2.0, 2.0, 1.0);
}

float sky_at(vec2 ndc) {
	vec2 uv = ndc * 0.5 + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1.0;
	return textureLod(depth_tex, uv, 0.0).r <= 1e-6 ? 1.0 : 0.0;
}

void fragment() {
	float rx = sun_r * PROJECTION_MATRIX[0][0] / PROJECTION_MATRIX[1][1];
	float r = 0.5;
	float seen = (sky_at(sun_ndc) * 2.0
		+ sky_at(sun_ndc + vec2(rx * r, 0.0)) + sky_at(sun_ndc - vec2(rx * r, 0.0))
		+ sky_at(sun_ndc + vec2(0.0, sun_r * r)) + sky_at(sun_ndc - vec2(0.0, sun_r * r))) / 6.0;
	vec2 d = SCREEN_UV * 2.0 - 1.0 - sun_ndc;
	// screen space with x in heights, so the glare is round
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 q = vec2(d.x * aspect, d.y) * 0.5;
	float ax = abs(q.x) / (streak_reach * aspect);
	// the streak: thin, and tapering off along its length
	float line = exp(-abs(q.y) / streak_thickness) * exp(-ax * 3.0);
	// a fainter, fatter sheath round it
	float sheath = exp(-abs(q.y) / (streak_thickness * 6.0)) * exp(-ax * 5.0) * 0.35;
	// the glare at the middle
	// (a ring more than a disc, so the sun's face shows through it)
	float rq = length(q);
	float glare = smoothstep(0.02, 0.09, rq) * exp(-rq / 0.09) * 0.45;
	vec3 col = streak_color * (line + sheath) * smoothstep(0.03, 0.12, abs(q.x)) + core_color * glare;
	ALBEDO = col * strength * seen;
	// the thermal sight's feed: a flare is light, not heat
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = vec3(0.0);
}
