// MEWD — CANDY LAND's gingerbread house (render/house_view.gd): the model's
// own materials as they came (a painted sheet, cut out at half, or a plain
// colour), LIT AS THE ISLAND IS. Unshaded, with its light out of the
// island's one lighting model (SHADERINC_island_light: the baked
// environment ball, the banded sun, the rim) at the cliff's own numbers, and
// the island's distance haze. The engine's light loop lit it before, and
// that is not the light the ground, the cliffs and the plants stand in (the
// candy sun's DirectionalLight is turned well down), so the houses read dark
// against everything round them. And through the thermal sight, the cold
// band, because only people are hot.
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://godot/shaders/thermal_base.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_island_light.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured = false;
uniform vec4 color : source_color = vec4(1.0);
// the light, at the cliff's numbers (MAT_candy_cliff)
uniform float sun_bands = 4.0;
uniform float sun_wrap = 0.45;
uniform float rim_power = 3.0;
uniform float rim_strength = 0.25;
// how bright the painting is lit to: the sheet is painted already lit, so
// the light is taken as a share of it rather than all of it
uniform float light_mix = 0.6;
uniform float brightness = 1.0;
// the haze, as the cliff's
uniform vec3 fog_color : source_color = vec3(0.62, 0.8, 1.0);
uniform float fog_distance_start = 850.0;
uniform float fog_distance_density = 0.0012;
uniform float fog_distance_power = 2.0;
global uniform vec4 tod_haze_tint;

void fragment() {
	vec4 c = textured ? texture(tex, UV) * color : color;
	if (c.a < 0.5)
		discard;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 lit = island_light(world_n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);
	vec3 albedo = c.rgb * mix(vec3(1.0), lit, light_mix) * brightness;
	float fd = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
	float fog = 1.0 - exp(-pow(fd, fog_distance_power));
	albedo = mix(albedo, fog_color * tod_haze_tint.rgb, fog);
	ALBEDO = albedo;
	if (thermal_on(VIEWPORT_SIZE))
		ALBEDO = thermal_out(thermal_cold(c.rgb, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
