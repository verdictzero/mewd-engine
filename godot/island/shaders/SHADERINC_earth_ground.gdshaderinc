// THE GROUND'S COLOUR ON A REAL PLACE, for whatever stands on it (at the
// user's request: "make sure grass etc (not trees) matches the grass of the
// terrain splat it is on, for blending / visual consistencies sake"): the
// colour SHADER_terrain_earth paints the ground at a point, as near as one
// look can tell it — its twelve layers weighed off the region's control
// pictures, each layer's own average colour (tools/earth_pack.py `means`,
// worked out from its texels once and published as numbers), the four
// tints, the broad variation in brightness and the ground's exposure —
// without the detail of its texels, which a plant standing on it does not
// need. SCRIPT_earth_dress.gd publishes all of it as globals; elsewhere
// `tod_ground_rect.w` is 0 and there is no ground colour (`earth_ground`
// gives -1).
//
// The tints come off these globals for the ground itself too
// (`earth_ground_tint`), handed over as plain numbers, so the two cannot
// disagree about them whatever a renderer does to a colour on its way in.
//
// Include it after SHADERINC_earth_cliff (earth_macro).

global uniform sampler2D tod_ground_a;
global uniform sampler2D tod_ground_b;
global uniform sampler2D tod_ground_c;
// the twelve layers' average colours, linear (columns, rgb: grass forest
// rock scree, sand soil snow mud, paving dry moss bed)
global uniform mat4 tod_ground_means_a;
global uniform mat4 tod_ground_means_b;
global uniform mat4 tod_ground_means_c;
// the control grid's first sample (world x, z), its spacing and its samples
// a side (0: no real place here)
global uniform vec4 tod_ground_rect;
// the tints of grass, forest, rock and scree (columns, rgb), and in their
// fourth places the brightness variation's strength and scale and the
// ground's exposure
global uniform mat4 tod_ground_tints;

// a layer's tint: the published one where there is one, else `own`
vec3 earth_ground_tint(int layer, vec3 own) {
	return tod_ground_rect.w > 0.0 ? tod_ground_tints[layer].rgb : own;
}

// the ground's colour at (x, z) world, linear, as it is painted before it is
// lit; -1 where there is none
vec3 earth_ground(vec2 xz) {
	if (tod_ground_rect.w <= 0.0) {
		return vec3(-1.0);
	}
	vec2 uv = ((xz - tod_ground_rect.xy) / tod_ground_rect.z + 0.5) / tod_ground_rect.w;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec3(-1.0);
	}
	vec4 a = textureLod(tod_ground_a, uv, 0.0);
	vec4 b = textureLod(tod_ground_b, uv, 0.0);
	vec4 c = textureLod(tod_ground_c, uv, 0.0);
	float w[12] = {a.r, a.g, a.b, a.a, b.r, b.g, b.b, b.a, c.r, c.g, c.b, c.a};
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		if (w[i] > 0.015) {
			vec3 m = i < 4 ? tod_ground_means_a[i].rgb
					: (i < 8 ? tod_ground_means_b[i - 4].rgb : tod_ground_means_c[i - 8].rgb);
			if (i < 4) {
				m *= tod_ground_tints[i].rgb;
			}
			col += m * w[i];
			total += w[i];
		}
	}
	if (total <= 0.0) {
		return vec3(-1.0);
	}
	col /= total;
	float mac = earth_macro(xz, max(tod_ground_tints[1].w, 1.0));
	col *= 1.0 + (mac - 0.5) * 2.0 * tod_ground_tints[0].w;
	return col * tod_ground_tints[2].w;
}
