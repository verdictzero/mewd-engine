// MEWD — CANDY LAND's gingerbread house (render/house_view.gd): the model's
// own materials as they came (a painted sheet, cut out at half, or a plain
// colour), lit by the island's sun — and, through the thermal sight, the
// cold band, because only people are hot.
shader_type spatial;
render_mode cull_disabled;
#include "res://godot/shaders/thermal_base.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured = false;
uniform vec4 color : source_color = vec4(1.0);

void fragment() {
	vec4 c = textured ? texture(tex, UV) * color : color;
	if (c.a < 0.5)
		discard;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	if (thermal_on(VIEWPORT_SIZE)) {
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		EMISSION = thermal_out(thermal_cold(c.rgb, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
	}
}
