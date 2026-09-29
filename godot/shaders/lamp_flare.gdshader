// MEWD — a street lamp's flare (js/lamplight.js VERT / FRAG).
//
// WHAT A LAMP IS AT NIGHT, from across a street, is not a lit pole: it
// is a point of cold light with a line across it — the bloom of the
// luminaire and the streak a bright source puts across a lens. One
// MultiMesh of quads; each instance's origin is a lamp's LENS and
// INSTANCE_CUSTOM.x its glow (0 is an empty slot). Additive, over
// everything, no depth test: whether a wall is in the way is the sight
// line's answer (Lamps.draw), not the depth buffer's.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, skip_vertex_transform;

// half width and half height, as a fraction of the distance — the same
// size on the screen wherever the lamp is
uniform vec2 size = vec2(0.19, 0.032);
uniform float far = 2400.0;
// LAMP_LIGHT (js/material.js): mercury vapour, cold, with green in it
uniform vec3 color = vec3(0.70, 1.0, 0.86);
uniform float aspect = 5.9375;     // width over height of the quad
uniform float ball = 0.55;         // the bloom's radius, as a fraction of the height

varying vec2 corner;
varying float glow;

void vertex() {
	corner = VERTEX.xy * 2.0;
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec4 mv = VIEW_MATRIX * vec4(centre, 1.0);
	float d = -mv.z;
	/* the fade: with the distance and a half, to nothing at far — a lamp
	   halfway down the street is a third as bright as the one over you,
	   and the last one you can see is a point */
	float k = clamp(1.0 - d / far, 0.0, 1.0);
	glow = INSTANCE_CUSTOM.x * k * sqrt(k);
	/* sized by the distance, then pulled in with the fade, so a far lamp
	   is a point */
	mv.xy += corner * size * d * (0.5 + 0.5 * k);
	VERTEX = mv.xyz;
	POSITION = PROJECTION_MATRIX * vec4(mv.xyz, 1.0);
	/* BEHIND THE EYE IS NOWHERE, and so is a slot with nothing in it */
	if (d < 0.5 || glow < 0.004) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);
	}
}

void fragment() {
	/* the streak: sharp across, soft along, the anamorphic line a lens
	   puts through a bright point — fainter and shorter than the
	   gunship's, because this is a street lamp and not a searchlight */
	float ax = abs(corner.x);
	float ay = abs(corner.y);
	float along = pow(max(0.0, 1.0 - ax), 0.7);
	float streak = exp(-ay * 30.0) * along + exp(-ay * 7.0) * along * along * 0.12;
	/* the bloom: a radial gradient, white at the heart */
	vec2 q = vec2(corner.x * aspect, corner.y) / ball;
	float r = length(q);
	float sphere = exp(-r * r * 1.8) * 1.1 + exp(-r * 4.5) * 0.9;
	/* the streak is bluer than the lamp — the lens's colour, not the
	   light's — and the bloom goes to white at the heart */
	vec3 c = mix(color, vec3(0.55, 0.80, 1.0), 0.5) * streak * 0.55
		+ mix(color, vec3(1.0), clamp(sphere * 0.5, 0.0, 1.0)) * sphere;
	/* and stepped, a little, because everything in this game is */
	c = floor(c * glow * 24.0 + 0.5) / 24.0;
	if (c.r + c.g + c.b < 0.02) discard;
	ALBEDO = c;
}
