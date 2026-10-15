shader_type canvas_item;

// THE MOUNTAINS' SHADOWS on a real place (EarthSun, SCRIPT_earth_sun.gd), baked
// once for where the sun is and again when it moves: for every sample of the
// region's 4 m grid, how much of the sun's disc can be seen from its surface
// (the ground, or the water over it), marched toward the sun over the 2 m
// height grid. 1 in the sun, 0 in shadow, soft between: the penumbra is how
// close the march came to grazing a ridge, against the sun's own size and a
// little more (`soft`), so a peak's shadow is sharp at its foot and soft a
// kilometre off. What it does not see is past the square's edge, where there is
// nothing — the island floats.
//
// The grid's heights come in as they are on disk (u16, little end first, in
// two bytes: metres = offset + q * scale), the water's surface as floats
// (NaN where there is none), both read texel by texel.

uniform sampler2D heights : filter_nearest, repeat_disable;
uniform sampler2D water : filter_nearest, repeat_disable;
uniform float hn = 1501.0;
uniform float hres = 2.0;
uniform float hoff = 0.0;
uniform float hscale = 1.0;
uniform float datum = 0.0;
uniform float wn = 751.0;
uniform float out_n = 751.0;
uniform float out_res = 4.0;
// toward the sun (or the moon), x east, y up, z south
uniform vec3 light_dir = vec3(0.3, 0.6, 0.5);
// the penumbra's spread, as a tangent: the sun's half-width is 0.0046
uniform float soft = 0.014;
uniform float reach = 3200.0;
// metres the surface stands its sample off itself (a surface does not
// shade itself through its own grid)
uniform float bias = 1.2;

float h_at(vec2 k) {
	vec2 rg = texelFetch(heights, ivec2(k + 0.5), 0).rg;
	float q = floor(rg.r * 255.0 + 0.5) + floor(rg.g * 255.0 + 0.5) * 256.0;
	return hoff + q * hscale - datum;
}

void fragment() {
	vec2 ij = floor(UV * out_n);
	// metres from the grids' shared corner
	vec2 p0 = ij * out_res;
	float ground = h_at(p0 / hres);
	float w = texelFetch(water, ivec2(clamp(ij, vec2(0.0), vec2(wn - 1.0))), 0).r;
	float surface = (isnan(w) || w < -1e6) ? ground : max(ground, w - datum);
	float y0 = surface + bias;
	float lit = 1.0;
	float hl = length(light_dir.xz);
	if (light_dir.y <= 0.0) {
		lit = 0.0;
	} else if (hl > 1e-4) {
		vec2 d = light_dir.xz / hl;
		float tan_e = light_dir.y / hl;
		float res = 1.0;
		float t = hres;
		for (int s = 0; s < 240; s++) {
			vec2 k = (p0 + d * t) / hres;
			if (t > reach || k.x < 0.0 || k.y < 0.0 || k.x > hn - 1.0 || k.y > hn - 1.0) {
				break;
			}
			float h = h_at(k);
			res = min(res, (y0 + t * tan_e - h) / (t * soft));
			if (res < -1.0) {
				break;
			}
			t += max(hres, t * 0.035);
		}
		lit = clamp(res * 0.5 + 0.5, 0.0, 1.0);
		lit = lit * lit * (3.0 - 2.0 * lit);
	}
	COLOR = vec4(lit, lit, lit, 1.0);
}
