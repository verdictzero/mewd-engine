// MEWD — a plant of the wood: a cut-out billboard that bends in the wind
// (js/forest.js PLANT_VERT / PLANT_FRAG, less the burning: the fire that
// spread is gone, at the user's request).
//
// One MultiMesh a chunk of ground; every plant kind the map uses is a
// layer of the two texture arrays, so the whole wood is one material.
// Each instance's origin is the plant's FEET, and
//   basis x.x, y.y   its width and height in units
//   INSTANCE_CUSTOM  x the layer (its kind), y unused, z its seed, w mirrored
//   COLOR            r the light it stands in, b / a where it starts
//                    to go and where it is gone (the kind's fade band)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform sampler2DArray albedo : source_color, filter_nearest_mipmap;
uniform float u_time = 0.0;
// THE WIND IN THE LEAVES, at the user's request: the weather's wind as a
// direction on the ground (Godot x, z) and a strength — see ForestView.draw
uniform vec3 u_wind = vec3(1.0, 0.0, 0.3);

varying flat float layer;
varying float pseed;
varying float depth;
varying float light;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	layer = cd.x;
	pseed = cd.z;
	light = COLOR.r;
	vec3 feet = MODEL_MATRIX[3].xyz;
	vec2 size = vec2(MODEL_MATRIX[0].x, MODEL_MATRIX[1].y);
	/* Half the plants are mirrored, chosen when they were planted: ten
	   sprites over fifty thousand plants is a lot of repeat, and a flip
	   doubles the apparent variety for nothing. */
	UV = vec2(cd.w > 0.5 ? 1.0 - UV.x : UV.x, UV.y);
	/* THE UNDERSTORY STOPS. A fern is forty-six units tall, which is
	   under two pixels at three thousand; drawn to the horizon it costs a
	   full screen of overdraw for a haze you cannot resolve. The quad
	   collapses to a point and rasterises nothing, so the fill goes. (The
	   chunk's own visibility range drops the draw past the band.) */
	float keep = 1.0 - smoothstep(COLOR.b, COLOR.a, distance(feet, CAMERA_POSITION_WORLD));
	// the eye's right, flattened: the card turns about the vertical only
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	vec3 p = feet + right * VERTEX.x * size.x * keep + vec3(0.0, VERTEX.y * size.y * keep, 0.0);
	/* VERTEX WIND. The quad's top is pushed downwind and let back, the
	   root never moves, and the push goes as the square of the height up
	   the plant, so it bends from the ground rather than sliding. Three
	   parts: a slow lean that rolls across the wood as a WAVE (its phase
	   is where the plant stands, so a gust visibly travels downwind), a
	   faster flutter of each plant's own, and a gust that comes and goes
	   on a period that does not divide into the other two. Four vertices a plant
	   is all the budget there is, so this is a shear and not a bend, and
	   at forest distances that is the same thing. */
	float along = dot(feet.xz, normalize(u_wind.xy + vec2(1e-4)));
	float gust = 0.55 + 0.45 * sin(u_time * 0.21 + along * 0.0009);
	float wave = sin(u_time * 1.3 - along * 0.004 + pseed * 0.8);
	float flutter = sin(u_time * 3.7 + pseed * 17.0) * 0.35;
	float lean = u_wind.z * gust * (0.6 + 0.4 * wave + flutter);
	float up = VERTEX.y * VERTEX.y;
	p.xz += u_wind.xy * (lean * up * size.y * 0.045 * keep);
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	depth = -VERTEX.z;
}

void fragment() {
	vec4 t = texture(albedo, vec3(UV, layer));
	if (t.a < 0.5) discard;
	vec3 col = t.rgb;
	// and lit by the region it stands in, under the sky
	float l = world_band(light, depth, 1.0);
	vec3 c = world_fog(world_air(col * world_lit(l), depth), depth);
	ALBEDO = c;
	// the thermal sight's feed: the tree as a surface
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, l, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0));
}
