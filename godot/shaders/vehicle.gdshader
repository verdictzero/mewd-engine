// MEWD — a vehicle (js/car.js carMesh, and the INK and char blocks of
// js/material.js), lit the way the world is.
//
// THIS RENDERER DOES NO SHADING, and a solid lit that way is a
// silhouette — every face the same value, no edge anywhere. So the car
// borrows the trick the walls use, DOOM'S FAKE CONTRAST: a face looking
// north or south reads a notch brighter than one looking east or west,
// the roof gets a lift (it faces the floodlights) and the underside goes
// dark. The JS bakes that into the vertices at the heading it was parked
// at; here it is worked out from the face's WORLD normal every frame,
// which is the same number for a parked car and the right one for a van
// that is still turning into its bay.
//
// Then the sector's light at the vehicle (`light`, `sky`) through
// world_band — distance, the sky's lift, Doom's 32 steps — and the air,
// exactly as world.gdshader does it for a wall.
//
// WHICH WAY A FACE POINTS is a HEURISTIC, as it is in js/car.js: away
// from the model's own middle (`centre`, in this mesh's own coordinates).
// A shell wound inward, or a normal that came out of the file pointing
// in, is turned round here for the light alone; it culls nothing.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2D map : source_color, filter_nearest_mipmap, repeat_enable;
uniform bool has_map = true;
// a surface with no picture IS this colour (glTF's baseColorFactor)
uniform vec4 base : source_color = vec4(1.0);
// the chunks carry their colour per vertex instead: COLOR.a = 1 means
// "this is the colour", 0 means "there is a picture" (the INK attribute)
uniform bool vertex_ink = false;
uniform vec3 centre = vec3(0.0);
// false where the normals were turned outward when the mesh was built
uniform bool outward = true;
// the sector the vehicle stands in, and how burnt it is (js/vehicles.js
// charTic: `light` comes down, `charred` goes up)
uniform float light = 0.74;
uniform float sky = 1.0;
uniform float charred = 0.0;
// what the WHITE paint in the sheet is multiplied by — see PAINT in
// js/vehicles.js
uniform vec3 paint = vec3(1.0);
// HOW WARM THE ENGINE IS, for the thermal sight only (js/material.js
// `warmth`, set per vehicle by ThermalScope off MissileSystem.is_hot)
uniform float warmth = 0.0;

const float ROOF_LIT = 1.12;
const float UNDER_LIT = 0.40;
const float CONTRAST = 0.055;

varying float depth;
varying vec3 wnormal;
varying vec3 wpos;

void vertex() {
	vec3 n = NORMAL;
	if (outward && dot(n, VERTEX - centre) < 0.0) n = -n;
	wnormal = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec4 t = has_map ? texture(map, UV) : base;
	if (vertex_ink) {
		t = mix(t, vec4(COLOR.rgb, 1.0), COLOR.a);
	}
	// THE PAINT, isolated in the texel itself: the bodywork is white and
	// dead neutral, everything that must not take the colour (glass,
	// tyres, grille) far darker or coloured — a luminance ramp with a
	// saturation guard, in linear, per texel (the INK block)
	if (has_map && paint != vec3(1.0)) {
		float pl = dot(t.rgb, vec3(0.30, 0.59, 0.11));
		float pmx = max(t.r, max(t.g, t.b));
		float pmn = min(t.r, min(t.g, t.b));
		float ps = pmx > 0.0 ? (pmx - pmn) / pmx : 0.0;
		float pm = smoothstep(0.32, 0.52, pl) * (1.0 - smoothstep(0.06, 0.14, ps));
		t.rgb = mix(t.rgb, t.rgb * paint, pm);
	}
	// Doom's fake contrast, off where the face points in the WORLD: map y
	// is Godot's -z, so |ny| is |z| here
	vec3 n = normalize(wnormal);
	float l;
	if (n.y > 0.5) l = light * ROOF_LIT;
	else if (n.y < -0.5) l = light * UNDER_LIT;
	else l = light + CONTRAST * (abs(n.z) - abs(n.x));
	// a charring vehicle loses most of its light as it goes black
	l *= 1.0 - 0.62 * clamp(charred, 0.0, 1.0);
	float band = world_band(l, depth, sky);
	vec3 c = t.rgb * world_lit(band);
	vec3 coal = vec3(0.0);
	// THE COALS: chunky blobs in fourteen-unit cells, one in twelve of
	// them alight and breathing, in proportion to the char — the same
	// idea as emberOf in js/material.js, at a fraction of its code
	if (charred > 0.001) {
		vec3 lat = wpos * 0.07;
		vec3 cell = floor(lat);
		float h = hash3(cell);
		vec3 off = fract(lat) - 0.5;
		float blob = 1.0 - smoothstep(0.30, 0.52, length(off));
		float on = step(1.0 - charred / 12.0 * 1.4, h);
		float breath = 0.55 + 0.45 * sin(TIME * (1.3 + h * 2.1) + h * 40.0);
		float fade = 1.0 - clamp(depth / 2400.0, 0.0, 1.0);
		coal = vec3(1.0, 0.36, 0.06) * blob * on * breath * fade * clamp(charred, 0.0, 1.0) * 0.9;
		c += coal;
	}
	ALBEDO = world_fog(world_air(c, depth), depth);
	// the thermal sight's feed: the body as a surface, the engine by its
	// warmth with the paint giving it its shape, the coals as heat
	if (thermal_on(VIEWPORT_SIZE)) {
		float h = thermal_of(t.rgb, band, depth, wpos, 0.0);
		h = max(h, warmth * (0.64 + 0.14 * dot(thermal_srgb(t.rgb), vec3(0.30, 0.59, 0.11))));
		ALBEDO = thermal_out(h + thermal_glow(coal));
	}
}
