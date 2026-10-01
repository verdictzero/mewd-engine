// MEWD — a projectile model (godot/scripts/render/projectile_models.gd):
// the rocket and the cerebral bore, one MultiMesh each, flat-coloured
// as their files are (glTF baseColorFactor, emissiveFactor). Lit the way
// a vehicle is (vehicle.gdshader): Doom's fake contrast off the face's
// world normal, then the sector's light at the shot (INSTANCE_CUSTOM.x,
// the light; .y, how much of it is sky) through world_band and the air.
// An emissive surface — the rocket's exhaust, the bore's thruster — is
// its own light, and white hot in the thermal sight.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform vec4 base = vec4(1.0);
uniform vec3 emit = vec3(0.0);

const float ROOF_LIT = 1.12;
const float UNDER_LIT = 0.40;
const float CONTRAST = 0.055;

varying float depth;
varying vec3 wnormal;
varying vec3 wpos;
varying float light;
varying float sky;

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	light = INSTANCE_CUSTOM.x;
	sky = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec3 n = normalize(wnormal);
	if (!FRONT_FACING) n = -n;
	float l;
	if (n.y > 0.5) l = light * ROOF_LIT;
	else if (n.y < -0.5) l = light * UNDER_LIT;
	else l = light + CONTRAST * (abs(n.z) - abs(n.x));
	float band = world_band(l, depth, sky);
	float hot = clamp(max(emit.r, max(emit.g, emit.b)), 0.0, 1.0);
	vec3 c = mix(base.rgb * world_lit(band), base.rgb + emit, hot);
	ALBEDO = world_fog(world_air(c, depth), depth);
	if (thermal_on(VIEWPORT_SIZE)) {
		ALBEDO = thermal_out(thermal_of(base.rgb, band, depth, wpos, hot));
	}
}
