// HOW MUCH OF THE SUN REACHES A POINT on a real place (at the user's request:
// "make it look fucking cinematic as hell"): its mountains' shadows, baked by
// EarthSun (SCRIPT_earth_sun.gd, SHADER_earth_sun_bake.gdshader) for where the
// sun is, and the shadows of EnviroSky's clouds as they cross, found here by
// following the ray toward the sun up to the cloud layer and reading the sky's
// own weather map and cloud noise there — so a cloud's shadow on the ground is
// the shadow of the cloud in the sky over it, and moves with it.
//
// Include it after the shader has declared `global uniform vec3 tod_sun_dir`.
//
// tod_sun_shadow_on is 0 wherever no EarthSun is, and then this is 1 and reads
// nothing: every other island is lit as it was.
//
// The clouds' share: EnviroSky dims tod_sun_color by its clouds' average shade
// (tod_cloud_shadow.w); here that average comes off again and each point's own
// cloud goes on, so the gaps are in full sun and the shadows are deep.

global uniform float tod_sun_shadow_on;
global uniform sampler2D tod_sun_shadow;
// the bake's grid: its first sample (world x, z), its spacing, its samples a side
global uniform vec4 tod_sun_shadow_rect;
// the wind's offset (x, z), the cover, the shade EnviroSky already put on the sun
global uniform vec4 tod_cloud_shadow;
// the cloud layer's base and top and the island's ground (metres over the sea),
// and how much of the sun a cloud takes
global uniform vec4 tod_cloud_layer;
global uniform sampler2D tod_cloud_weather;
global uniform sampler3D tod_cloud_shape;

// (the sky shader's own scales: SHADER_sky_enviro.gdshader)
const float EARTH_WEATHER_SCALE = 26000.0;
const float EARTH_SHAPE_SCALE = 14000.0;

float earth_terrain_lit(vec2 xz) {
	vec2 uv = ((xz - tod_sun_shadow_rect.xy) / tod_sun_shadow_rect.z + 0.5) / tod_sun_shadow_rect.w;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 1.0;
	}
	return textureLod(tod_sun_shadow, uv, 0.0).r;
}

// 0 clear sky toward the sun, 1 a cloud.
float earth_cloud_at(vec3 p, vec3 l) {
	float cov = tod_cloud_shadow.z;
	if (cov <= 0.001 || l.y <= 0.02) {
		return 0.0;
	}
	// up the ray toward the sun to the lower part of the layer
	float alt = mix(tod_cloud_layer.x, tod_cloud_layer.y, 0.15);
	float up = alt - (tod_cloud_layer.z + p.y);
	vec2 q = p.xz + l.xz / max(l.y, 0.05) * up;
	vec2 wm = textureLod(tod_cloud_weather, fract((q + tod_cloud_shadow.xy) / EARTH_WEATHER_SCALE), 0.0).rg;
	float mid = 0.52 + 0.5625 * (0.5 - cov * 0.9);
	float c = smoothstep(mid - 0.15, mid + 0.15, wm.r);
	c = max(c, smoothstep(0.85, 1.0, cov));
	if (c <= 0.001) {
		return 0.0;
	}
	// and the billows in it, as the sky shapes them
	vec3 sp = fract(vec3(q.x + tod_cloud_shadow.x, alt, q.y + tod_cloud_shadow.y) / EARTH_SHAPE_SCALE);
	vec4 s = textureLod(tod_cloud_shape, sp, 0.0);
	float fb = s.g * 0.625 + s.b * 0.25 + s.a * 0.125;
	float base = clamp((s.r + (1.0 - fb)) / max(2.0 - fb, 1e-3), 0.0, 1.0);
	base = clamp((base - mix(0.9, 0.58, c)) / max(1.0 - mix(0.9, 0.58, c), 1e-3), 0.0, 1.0) * c;
	return smoothstep(0.0, 0.18, base);
}

// How much of the sun reaches `p` (world): 1 all of it.
float earth_sun_open(vec3 p) {
	if (tod_sun_shadow_on <= 0.0) {
		return 1.0;
	}
	float lit = earth_terrain_lit(p.xz);
	float cloud = earth_cloud_at(p, tod_sun_dir);
	float open = (1.0 - tod_cloud_layer.w * cloud) / max(tod_cloud_shadow.w, 0.2);
	return lit * open;
}
