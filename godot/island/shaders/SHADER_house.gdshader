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

// NEAREST (at the user's request: "houses need nearest neighbor
// filtering"), from the mip that fits, so the painting's own texels show up
// close and a house far off does not shimmer
uniform sampler2D tex : source_color, filter_nearest_mipmap, repeat_enable;
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

// THE HOUSE'S OWN COLOURWAY (at the user's request: "hue shift house
// variants, many"): INSTANCE_CUSTOM per house (HouseView) —
//   x  how far round the colour wheel its painting is turned (turns)
//   y  its saturation, times      z  its brightness, times
// The turn keeps each texel's luminance (a rotation about the grey axis in
// YIQ), so the white icing stays white and the gingerbread turns mint, or
// lilac, or strawberry.
varying vec3 shift;

vec3 hue_turn(vec3 c, float turns, float sat) {
	const mat3 to_yiq = mat3(vec3(0.299, 0.596, 0.211), vec3(0.587, -0.274, -0.523), vec3(0.114, -0.322, 0.312));
	const mat3 to_rgb = mat3(vec3(1.0, 1.0, 1.0), vec3(0.956, -0.272, -1.106), vec3(0.621, -0.647, 1.703));
	vec3 yiq = to_yiq * c;
	float a = turns * 6.2831853;
	float cs = cos(a);
	float sn = sin(a);
	yiq.yz = vec2(yiq.y * cs - yiq.z * sn, yiq.y * sn + yiq.z * cs) * sat;
	return max(to_rgb * yiq, vec3(0.0));
}

void vertex() {
	// (a house with no colourway of its own — custom left at zero — is its
	// painting as it is)
	shift = INSTANCE_CUSTOM.y > 0.0 ? INSTANCE_CUSTOM.xyz : vec3(0.0, 1.0, 1.0);
}

void fragment() {
	vec4 c = textured ? texture(tex, UV) * color : color;
	if (c.a < 0.5)
		discard;
	c.rgb = hue_turn(c.rgb, shift.x, shift.y) * shift.z;
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
