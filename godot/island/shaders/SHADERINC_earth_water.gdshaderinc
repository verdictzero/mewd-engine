// A REAL PLACE'S WATER, for what lies under it: the surface's height over any
// point (the field's water grid, published by SCRIPT_earth_dress.gd as the
// global tod_water_level, metres over the sea, NaN where there is none) and
// the CAUSTICS (at the user's request: "fake caustics") — the light the waves
// focus into a shifting net of bright lines on the bed.
//
// tod_water_on is 0 wherever no EarthDress is: then there is no water here.

global uniform float tod_water_on;
global uniform sampler2D tod_water_level;
// the grid's first sample (world x, z), its spacing, the region's datum
global uniform vec4 tod_water_info;

// The water's surface over (x, z), world metres, or -1e9 where there is none.
float earth_water_y(vec2 xz) {
	if (tod_water_on <= 0.0) {
		return -1e9;
	}
	ivec2 n = textureSize(tod_water_level, 0);
	ivec2 k = ivec2(floor((xz - tod_water_info.xy) / tod_water_info.z + 0.5));
	if (k.x < 0 || k.y < 0 || k.x >= n.x || k.y >= n.y) {
		return -1e9;
	}
	float w = texelFetch(tod_water_level, k, 0).r;
	return (isnan(w) || w < -1e6) ? -1e9 : w - tod_water_info.w;
}

// One channel of the caustic net at `p` (after the well-known "Tileable Water
// Caustic" on Shadertoy, by joltz0r and Dave Hoskins): five turns of a
// sine-warped point, the light where they bunch. 0 dark to about 1.5 bright.
float earth_caustic(vec2 p, float t) {
	vec2 q = mod(p * 6.2831853, 6.2831853) - 250.0;
	vec2 i = q;
	float c = 1.0;
	float inten = 0.005;
	for (int k = 0; k < 5; k++) {
		float tt = t * (1.0 - (3.5 / float(k + 1)));
		i = q + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(q.x / (sin(i.x + tt) / inten), q.y / (cos(i.y + tt) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return pow(abs(c), 8.0);
}

// The net in colour (each channel a little apart, as a lens splits them), over
// world (x, z), `scale` metres across.
vec3 earth_caustics(vec2 xz, float t, float scale) {
	vec2 p = xz / scale;
	return vec3(earth_caustic(p, t), earth_caustic(p + 0.004, t), earth_caustic(p + 0.008, t));
}
