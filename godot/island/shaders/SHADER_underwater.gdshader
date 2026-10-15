shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

// UNDER THE WATER (at the user's request: "a really pretty double sided water
// shader"): with the eye below a lake's surface (SCRIPT_earth_dress.gd says so,
// in tod_underwater), everything is seen through water — fogged by how far the
// eye looks through it, to the water's own colour, lit by what comes down from
// the sky and darker the deeper the eye is. A ray that leaves through the
// surface goes only that far through water; the surface's own underside (Snell's
// window: SHADER_water_earth.gdshader) is fogged by its distance. One pass over
// the whole screen, after the water.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 water_color = vec3(0.1, 0.46, 0.5);
// per metre: how fast the water closes in
uniform float density = 0.045;

// x: the surface's height (world y), y: 1 with the eye under it
global uniform vec4 tod_underwater;
global uniform vec3 tod_sun_dir;
global uniform vec4 tod_sun_color;
global uniform vec4 tod_sky_color;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	if (tod_underwater.y < 0.5) {
		discard;
	}
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	bool sky = d <= 0.0000001 || d >= 0.9999999;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 vp = v.xyz / v.w;
	float dist = sky ? 1e6 : length(vp);
	vec3 rd = normalize((INV_VIEW_MATRIX * vec4(vp, 0.0)).xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float down = max(tod_underwater.x - cam.y, 0.0);
	float to_surface = rd.y > 0.001 ? down / rd.y : 1e6;
	float through = min(dist, to_surface);
	vec3 light = tod_sky_color.rgb * 0.9 + tod_sun_color.rgb * 0.45 * max(tod_sun_dir.y, 0.0);
	// (brighter looking up toward the light, darker down into the deep)
	vec3 c = water_color * light * 1.3 * exp(-down * 0.025) * (0.55 + 0.45 * clamp(rd.y * 0.5 + 0.5, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = 1.0 - exp(-through * density);
}
