// MEWD — a solid thing on an island under MATCAPS (at the user's request:
// "give the maze sections and the drop pod a matcap so their PBRness looks
// nice"): GUILBAULT ARENA's walls and posts (MazeView) and the drop pod (DropPod).
// Their files are PBR — a colour, a normal map, and metal (B) and roughness
// (G) in one — and the engine's lights left them flat and dark against the
// island, which is lit its own way (SHADERINC_island_light). Here the
// surface's normal, bent by its normal map, looks up two pictures of a lit
// ball by the way it faces on the screen:
//   `matte`  a soft clay (assets/matcaps/clay.png): the diffuse light,
//            under the colour
//   `sheen`  the pearl (pearl.png, the arc maw's): what a polished surface
//            reflects, tinted by the colour where it is metal
// mixed by the metal and roughness maps, a share of the island's own light
// over it (so it dims at night and warms at dusk with everything else),
// the island's haze, and the cold band through the thermal sight.
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://godot/shaders/thermal_base.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_island_light.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured = false;
uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
// glTF's metallic-roughness: G roughness, B metal
uniform sampler2D mr_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_mr = false;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform sampler2D matte : source_color, filter_linear;
uniform sampler2D sheen : source_color, filter_linear;
// the matte ball's light lifted back to the colour's own brightness
uniform float lift = 2.1;
// how much of a polished surface is its reflection
uniform float shine = 0.55;
// a share of the island's light over it
uniform float light_mix = 0.45;
uniform float brightness = 1.0;
uniform float sun_bands = 4.0;
uniform float sun_wrap = 0.45;
uniform float rim_power = 3.0;
uniform float rim_strength = 0.2;
uniform vec3 fog_color : source_color = vec3(0.62, 0.8, 1.0);
uniform float fog_distance_start = 850.0;
uniform float fog_distance_density = 0.0012;
uniform float fog_distance_power = 2.0;
global uniform vec4 tod_haze_tint;

vec3 ball(sampler2D s, vec3 n) {
	vec2 m = n.xy * 0.49 + 0.5;
	return texture(s, vec2(m.x, 1.0 - m.y)).rgb;
}

void fragment() {
	vec4 c = textured ? texture(tex, UV) * color : color;
	if (c.a < 0.5)
		discard;
	vec3 n = NORMAL;
	if (has_normal) {
		vec3 t = texture(normal_map, UV).xyz * 2.0 - 1.0;
		n = TANGENT * t.x + BINORMAL * t.y + NORMAL * t.z;
	}
	// (the back of a two-sided wall faces the other way)
	if (!FRONT_FACING)
		n = -n;
	float l = dot(n, n);
	n = l > 1e-8 ? n * inversesqrt(l) : vec3(0.0, 0.0, 1.0);
	vec3 mr = has_mr ? texture(mr_map, UV).rgb : vec3(1.0);
	float metal = clamp(mr.b * metallic, 0.0, 1.0);
	float rough = clamp(mr.g * roughness, 0.04, 1.0);
	vec3 diffuse = c.rgb * ball(matte, n) * lift;
	vec3 refl = ball(sheen, n) * mix(vec3(1.0), c.rgb * 1.6, metal);
	float polish = (1.0 - rough) * shine;
	vec3 col = mix(diffuse * (1.0 - metal * 0.7), refl, clamp(polish + metal * 0.5 * (1.0 - rough), 0.0, 1.0));
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 lit = island_light(world_n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);
	col *= mix(vec3(1.0), lit, light_mix) * brightness;
	if (any(isnan(col)) || any(isinf(col)))
		col = c.rgb * 0.5;
	float fd = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
	float fog = 1.0 - exp(-pow(fd, fog_distance_power));
	ALBEDO = mix(clamp(col, vec3(0.0), vec3(4.0)), fog_color * tod_haze_tint.rgb, fog);
	if (thermal_on(VIEWPORT_SIZE))
		ALBEDO = thermal_out(thermal_cold(c.rgb, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
