// MEWD — a plant of the wood: a cut-out billboard that bends in the wind
// and burns by its burn map (js/forest.js PLANT_VERT / PLANT_FRAG).
//
// One MultiMesh a chunk of ground; every plant kind the map uses is a
// layer of the two texture arrays, so the whole wood is one material.
// Each instance's origin is the plant's FEET, and
//   basis x.x, y.y   its width and height in units
//   INSTANCE_CUSTOM  x the layer (its kind), y the burn 0..1 (its cell's
//                    progress), z its seed, w mirrored
//   COLOR            r the light it stands in, b / a where it starts
//                    to go and where it is gone (the kind's fade band)
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"

uniform sampler2DArray albedo : source_color, filter_nearest_mipmap;
// R coals, G char, B order (when this texel catches), A foliage
uniform sampler2DArray burn_map : filter_nearest_mipmap;
uniform float u_time = 0.0;
// THE WIND IN THE LEAVES, at the user's request: the weather's wind as a
// direction on the ground (Godot x, z) and a strength — see ForestView.draw
uniform vec3 u_wind = vec3(1.0, 0.0, 0.3);

// the eight ember colours (js/palette.js EMBER_RAMP): the store burns in
// them too — a charred wall and a charred fir are the same fire going out
const vec3 RAMP[8] = {
	vec3(0.094, 0.063, 0.031), vec3(0.188, 0.125, 0.0), vec3(0.314, 0.188, 0.0), vec3(0.439, 0.251, 0.0),
	vec3(0.596, 0.345, 0.0), vec3(0.753, 0.471, 0.125), vec3(0.910, 0.596, 0.345), vec3(0.973, 0.816, 0.627)
};

varying flat float layer;
varying float burn;
varying float pseed;
varying float depth;
varying float light;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	layer = cd.x;
	burn = cd.y;
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
	   on a period that does not divide into the other two. A plant that
	   has burnt is a black stick and does not sway. Four vertices a plant
	   is all the budget there is, so this is a shear and not a bend, and
	   at forest distances that is the same thing. */
	float along = dot(feet.xz, normalize(u_wind.xy + vec2(1e-4)));
	float gust = 0.55 + 0.45 * sin(u_time * 0.21 + along * 0.0009);
	float wave = sin(u_time * 1.3 - along * 0.004 + pseed * 0.8);
	float flutter = sin(u_time * 3.7 + pseed * 17.0) * 0.35;
	float lean = u_wind.z * gust * (0.6 + 0.4 * wave + flutter) * (1.0 - burn);
	float up = VERTEX.y * VERTEX.y;
	p.xz += u_wind.xy * (lean * up * size.y * 0.045 * keep);
	VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	depth = -VERTEX.z;
}

void fragment() {
	vec4 t = texture(albedo, vec3(UV, layer));
	if (t.a < 0.5) discard;
	vec3 col = t.rgb;
	float ember = 0.0;
	float gone = 0.0;
	vec3 hue = vec3(1.0);
	// how far up the picture, 0 at the foot and 1 at the top
	float vy = 1.0 - UV.y;

	/* THE BURN, skipped entirely on a plant the fire has not reached —
	   which is every plant in the wood until something turns it on. */
	if (burn > 0.0) {
		vec4 bm = texture(burn_map, vec3(UV, layer));
		/* Sweep the order field. The remap pushes both ends out by soft,
		   so burn = 1 drives even the last texel past the top of its band
		   and burn = 0 leaves the first below the bottom of its own. The
		   seed staggers neighbours so two plants in one cell are never in
		   step. */
		float soft = 0.22;
		float a = burn * (1.0 + 2.0 * soft) - soft + (pseed - 0.5) * 0.10;
		float tt = smoothstep(bm.b - soft, bm.b + soft, a);
		/* The art's own luminance carried through the char, so a burnt
		   tree is still a tree with a light side rather than a flat black
		   shape. */
		float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
		/* Dry and brown, then black, then a little ash on what is left.
		   The three overlap: a crown is scorching while the lower
		   branches char. */
		col = mix(col, col * 0.55 + vec3(0.30, 0.16, 0.06), smoothstep(0.0, 0.55, tt) * 0.85);
		/* Char that is charcoal, not a hole in the night: it keeps a fair
		   share of the art's own light and the ash on it goes pale. */
		col = mix(col, vec3(0.15, 0.13, 0.11) * (0.7 + 2.2 * lum), smoothstep(0.30, 0.95, tt) * bm.g);
		col = mix(col, vec3(0.46, 0.44, 0.40) * (0.60 + 2.0 * lum), smoothstep(0.85, 1.0, tt) * (1.0 - bm.g) * 0.75);
		/* BURNT DOWN. From nine tenths of the burn a tree goes: what is
		   left of it comes down from the crown and in from the sides until
		   the foot of the trunk is all that stands — a stump, ash grey,
		   for good, because the cell's progress never comes back down.
		   Discarding the texels is what does it (the burn map DISSOLVE). */
		gone = smoothstep(0.88, 1.0, burn);
		if (gone > 0.0) {
			float top = mix(1.0, 0.12, gone);
			float half_w = mix(0.5, 0.05, gone);
			if (vy > top || abs(UV.x - 0.5) > half_w) discard;
			col = mix(col, vec3(0.36, 0.34, 0.32) * (0.5 + 1.8 * lum), gone * 0.9);
		}
		/* Two sines beaten against each other so neighbouring coals on
		   one plant are out of step; the seed keeps two plants apart. */
		float flick = 0.80 + 0.30
			* sin(u_time * 9.0 + pseed * 31.4 + vy * 17.0)
			* sin(u_time * 3.7 + pseed * 12.0 + UV.x * 23.0);
		/* The flame is a narrow band travelling with the front; the coals
		   are what it leaves behind, and they cool. */
		float q = (tt - 0.5) / 0.16;
		float flame = exp(-q * q);
		float coal = bm.r * smoothstep(0.30, 0.62, tt) * (1.0 - 0.8 * smoothstep(0.70, 1.0, tt));
		ember = (flame * (0.22 + 0.78 * bm.r) + coal) * flick * 1.5 * (1.0 - 0.85 * gone);
		/* The palette cycle: where a texel sits in the eight ember colours
		   is its heat plus a wave that climbs the plant, quantised to
		   whole steps so it flips between real colours instead of
		   sliding. */
		float heat = clamp(flame * 0.62 + coal * 0.45, 0.0, 1.0);
		float ph = u_time * 0.9 - bm.b * 2.0 + pseed * 3.7 + bm.r * 1.3;
		float wv = abs(fract(ph) * 2.0 - 1.0) - 0.5;
		float swing = 0.18 * (0.35 + 0.65 * flame);
		float idx = clamp(heat + wv * 2.0 * swing, 0.0, 1.0);
		hue = RAMP[int(floor(idx * 7.0 + 0.5))];
	}
	// and lit by the region it stands in, under the sky
	float l = world_band(light, depth, 1.0);
	vec3 c = world_air(col * l * light_color.rgb, depth);
	// embers go on after the air, so a burning ridge glows through it
	ALBEDO = c + hue * ember;
}
