// MEWD — what every shader drawn in the thermal sight's feed needs to know
// (thermal.gdshaderinc has the rest, and includes this): whether this is
// the feed, the number out as the feed holds it, and the COLD everything
// that is not a person is. The island's own shaders (godot/island/shaders)
// include only this: they never warm.

// the thermal feed's size in pixels while the sight is up, else zero
global uniform vec2 thermal_view;
// 1 under the Compatibility renderer, whose 3D goes into a SubViewport as
// the shader wrote it; 0 under Forward+, whose tonemap pass sRGB-encodes it
// on the way in — set by ThermalScope, so the feed holds the heat either way
global uniform float thermal_raw;

// VIEWPORT_SIZE is a built-in of the stage functions, so it is handed in
bool thermal_on(vec2 viewport) {
	return thermal_view.x > 0.5 && abs(viewport.x - thermal_view.x) < 0.5 && abs(viewport.y - thermal_view.y) < 0.5;
}

// a linear colour back to the byte it was painted as, for its luminance
vec3 thermal_srgb(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

// ONLY PEOPLE ARE HOT (at the user's request: "recalibrate thermal sight
// so only people show up hot"): the ground, the trees, the houses, the
// lamps, the engines, the fire — everything that is not a body — sits in
// one narrow cold band, its own light and dark only giving it a shape to
// read, and goes colder still with distance (`fade`, 0 near to 1 far).
// The band's top (0.24) is well under the coldest a body is (0.66).
float thermal_cold(vec3 albedo, float fade) {
	float lum = dot(thermal_srgb(albedo), vec3(0.2126, 0.7152, 0.0722));
	return mix(0.11 + 0.13 * lum, 0.06, fade * fade * 0.85);
}

// the number, out: so the feed's texture holds it as written (thermal_raw)
vec3 thermal_out(float h) {
	h = clamp(h, 0.0, 1.0);
	if (thermal_raw > 0.5) return vec3(h);
	return vec3(h <= 0.04045 ? h / 12.92 : pow((h + 0.055) / 1.055, 2.4));
}
