shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// THE FIELD AT THE EDGE OF A REAL PLACE (SCRIPT_earth_edge.gd's curtain): at
// the user's request, "an animated hexagonal grid forcefield effect at the
// edges where the land gets cut off". A curtain of light hung all round the
// square, just outside its cut face, from the cloud deck up past the land:
//
//   * THE HEXES, metres across in the plane of the curtain (along the edge,
//     up), in thin lines of light with a faint glow inside each toward its
//     rim; the size made by the script to go round the square a whole number
//     of times, so no corner has a seam. Lines finer than a pixel or two give
//     way to their average (what they would cover), not to a moire.
//   * THE SEAM, where the land is cut: a line of brighter light following the
//     ground's own profile along the edge (its height at each column is the
//     curtain's UV2.x), so the cut reads as the field slicing the world.
//   * HOW HIGH: brightest at the land, dying away over `rise` metres above
//     it; fainter down the cut face, to nothing at the cloud deck.
//   * WHAT MOVES: bands of light rising up it, cells lighting by turns, a
//     slow tide running round the square, and, where the eye comes near, the
//     field waking — brighter, and ringed with ripples out from the eye.
//
// Added light (blend_add), not a veil: it never darkens what is behind it,
// and in what order it and the water are drawn makes no difference to it.
// Its own fade with distance, not the fog's (which would add the fog's colour).

uniform vec3 field_colour : source_color = vec3(0.30, 0.80, 1.0);
uniform vec3 seam_colour : source_color = vec3(0.70, 0.95, 1.0);
/// All of it, brighter or dimmer.
uniform float strength : hint_range(0.0, 4.0) = 0.8;
/// The hexes, metres across their flats (the script sets it).
uniform float hex_metres = 14.0;
/// The lines, as a fraction of a hex.
uniform float line_width = 0.04;
/// Metres over the land at which the field is a third as bright.
uniform float rise = 150.0;
/// Metres over the land at which the curtain ends (the script hangs it so).
uniform float reach = 700.0;
/// Where it ends below: the cloud deck, metres (the script sets it).
uniform float deck_y = -45.0;
/// The bands rising: metres a second, metres apart, metres thick.
uniform float scan_speed = 24.0;
uniform float scan_spacing = 240.0;
uniform float scan_width = 8.0;
/// The seam's light, metres either side of the land's edge (at the least a
/// pixel and a half).
uniform float seam_width = 1.0;
/// Metres off at which the field starts to wake for the eye.
uniform float near_metres = 300.0;

varying float v_ground;
varying float v_s;
varying float v_y;
varying vec3 v_world;

void vertex() {
	v_ground = UV2.x;
	v_s = UV.x;
	v_y = VERTEX.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The hex a point is in, in hexes (one across its flats): the point's offset
// from the hex's middle (.xy), and the middle (.zw).
vec4 hex_at(vec2 p) {
	const vec2 R = vec2(1.0, 1.7320508);
	vec2 a = mod(p, R) - R * 0.5;
	vec2 b = mod(p - R * 0.5, R) - R * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	return vec4(g, p - g);
}

// How far in from the hex's rim, in hexes: 0 on it, 0.5 at the middle.
float hex_in(vec2 g) {
	g = abs(g);
	return 0.5 - max(dot(g, vec2(0.5, 0.8660254)), g.x);
}

void fragment() {
	float rel = v_y - v_ground;
	vec4 h = hex_at(vec2(v_s, v_y) / hex_metres);
	float e = hex_in(h.xy);
	float fw = max(fwidth(e), 1e-4);
	// (a line no thinner than a pixel; and where the hexes are only a few
	// pixels across, the share of each its lines cover)
	float w = max(line_width, 0.7 * fw);
	float line = 1.0 - smoothstep(w - fw, w + fw, e);
	line = mix(line, 4.0 * line_width * (1.0 - line_width), smoothstep(0.12, 0.35, fw));
	float rim = pow(1.0 - 2.0 * e, 6.0);
	float id = hash12(h.zw);

	// how high: over the land, and down the cut face to the deck
	float top = 1.0 - smoothstep(reach * 0.55, reach, rel);
	float above = exp(-max(rel, 0.0) / rise) * top;
	float below = smoothstep(deck_y, v_ground, v_y) * 0.4;
	float env = rel >= 0.0 ? above : below;

	// the bands rising, level (not the land's profile again, over it), and
	// reaching higher than the field's own glow
	float ph = fract((v_y - TIME * scan_speed) / scan_spacing) - 0.5;
	float scan = exp(-pow(ph * scan_spacing / scan_width, 2.0));
	float scan_env = rel >= 0.0 ? exp(-rel / (rise * 2.5)) * top : below;
	// the cells lit by turns
	float cell = smoothstep(0.94, 1.0, sin(TIME * (0.5 + 1.3 * id) + id * 40.0)) * (0.4 + 0.6 * id);
	// the tide round the square
	float tide = 0.7 + 0.3 * sin(v_s * 0.012 - TIME * 0.8 + 2.0 * sin(v_s * 0.0021 + TIME * 0.23));
	// the eye near
	float d = distance(v_world, CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(25.0, near_metres, d);
	float ripple = pow(0.5 + 0.5 * sin(d * 0.22 - TIME * 4.5), 8.0) * near;

	float grid = line * (0.6 + 1.8 * scan + 1.4 * near + 1.2 * ripple)
			+ rim * (0.18 + 0.5 * scan + 0.3 * near)
			+ cell * (0.35 + 0.65 * rim);
	float body = grid * env * tide + scan * scan_env * (0.6 * line + 0.12) * (1.0 - env);

	// the seam, along the land's edge
	float sw = max(seam_width, fwidth(v_y) * 1.5);
	float seam = exp(-abs(rel) / sw) * (0.75 + 0.25 * sin(v_s * 0.07 - TIME * 3.0));
	float halo = exp(-abs(rel) / (sw * 10.0)) * 0.3;

	// the far walls fainter; edge-on, the curtain a little brighter
	float fade = mix(1.0, 0.4, smoothstep(500.0, 3500.0, d));
	float edge_on = mix(1.5, 0.8, abs(dot(NORMAL, VIEW)));
	ALBEDO = (field_colour * body * edge_on + seam_colour * (1.6 * seam + halo)) * strength * fade;
}
