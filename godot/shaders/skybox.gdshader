// MEWD — a map's skybox from the texture pack (js/sky.js, the sphere's
// fragment shader, wearing loadSky's picture from js/texpack.js).
//
// THE PICTURE AS THE WEB BUILD SHOWS IT. There the equirect is an
// SRGBColorSpace texture, which WebGL decodes to LINEAR on the fetch,
// and the sky's colour is written to the lo-fi buffer as it is, never
// encoded again — so the photograph is shown at its linear values: the
// same picture, a good deal darker in its middle tones (a grey cloud at
// 0.5 is drawn at 0.21). That is the night the web build's skybox maps
// have at two in the morning. The Compatibility renderer neither decodes
// the fetch nor encodes what a sky writes, so the decode is done here.
//
// NOT LIT and NOT IN THE AIR (the air's colour is the sky's horizon), but
// the map's FOG is over it: the fog you stand in and look through, out to
// the far edge of the air (FOG_GLSL's fogAlong, in js/material.js). The
// web build follows it sector by sector along the ray; here it is the
// map's default fog along the whole ray, standing up to the eye sector's
// fog top (FOG_TOP over the floor under the sky, the ceiling under a
// roof) — the top a run of the same air keeps from where it began, as
// fogAlong's does — and thinning away above it: a band over the horizon,
// and the zenith clear, as there.
shader_type sky;

global uniform float air_far;
global uniform vec4 light_color;

uniform sampler2D panorama : filter_nearest, repeat_enable;
// the map's default fog: rgb, and a density 0..100 (0: none)
uniform vec4 fog_default = vec4(0.0);
uniform vec3 ambient = vec3(0.0);
uniform float fog_ambient = 1.0;
// the fog's top over the eye (units), and how far over it the fog thins
uniform float fog_top = 1e9;
uniform float fog_fade = 128.0;

vec3 srgb_to_lin(vec3 s) {
	return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(0.04045, s));
}

// the fog's thickness summed up to height z over the eye (fogG)
float fog_g(float z) {
	return z <= fog_top ? z : fog_top + fog_fade * (1.0 - exp((fog_top - z) / fog_fade));
}

void sky() {
	// THE SPHERE'S OWN MAPPING (js/sky.js: a SphereGeometry mirrored in
	// x): u is the azimuth, atan2(z, x) over a full turn in the renderer's
	// axes — the air's formula in worldShade, and ours are the same axes —
	// and v the polar angle, the picture's top overhead
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(fract(atan(d.z, d.x) / TAU), acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 c = srgb_to_lin(texture(panorama, uv).rgb);
	if (fog_default.a > 0.0) {
		float dz = d.y * air_far;
		float thick = abs(dz) < 1.0 ? (0.0 <= fog_top ? 1.0 : exp(fog_top / fog_fade)) : (fog_g(dz) - fog_g(0.0)) / dz;
		float t = exp2(-air_far * fog_default.a * thick / 25600.0);
		c = c * t + (1.0 - t) * (fog_default.rgb * light_color.rgb + ambient * fog_ambient);
	}
	COLOR = c;
}
