// MEWD — a standee: a sprite that turns about the vertical to face the
// eye, Doom's billboard (js/standees.js). One MultiMesh per strip; each
// instance's origin is the feet, and INSTANCE_CUSTOM carries
//   x  the cell in the strip
//   y  the light (sector light times the actor's own `lit`)
//   z  how much of that light is sky
//   w  flags: +1 mirrored, +2 fullbright, and for the thermal sight alone
//      +4 a body (warm whatever it wears), +8 frozen, +16 alight;
//      +32 swaying where they stand, +64 running; and from 128 up the
//      phase of the sway (the actor's id), so the crowd does not lean
//      as one
// The quad is `cell` units: a sprite is drawn one unit to the pixel.
// THE SWAY is worked out here off TIME (js/people.js SWAY), so the
// crowd's rows need not be written for it (render/standees.gd).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

// (nearest, and from the mip that fits when the strip has them: the crowd
// is drawn at the artist's own resolution, Standees "SHOP")
uniform sampler2D strip : filter_nearest_mipmap;
// THE SAME STRIP, FILTERED, for when the drawing is smaller on the screen
// than it is in the strip (at the user's request: the people had "a
// sparkly outline"). A nearest fetch of a drawing finer than the pixels
// picks one texel of the several under each pixel, a different one as
// the sprite sways, and at the cut-out's edge that is a rim of texels
// that come and go: a twinkle round everybody. Minified, the fetch is
// linear instead (a proper average of the texels under the pixel, which
// the lo-fi grid then pixelates anyway); magnified it stays nearest, so
// the pixel art up close is still pixel art. Standees binds both to the
// one texture.
uniform sampler2D strip_smooth : filter_linear_mipmap;
uniform float cells = 1.0;
uniform vec2 cell = vec2(40.0, 64.0);

varying float depth;
varying float light;
varying float sky;
varying float fullbright;
varying float warm;
varying float frozen;
// how frozen, 0..1 (Standees: the fraction of the cell number)
varying float frost;
varying float alight;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float flags = cd.w;
	float mirror = mod(flags, 2.0);
	fullbright = mod(floor(flags / 2.0), 2.0);
	warm = mod(floor(flags / 4.0), 2.0);
	frozen = mod(floor(flags / 8.0), 2.0);
	alight = mod(floor(flags / 16.0), 2.0);
	float stands = mod(floor(flags / 32.0), 2.0);
	float runs = mod(floor(flags / 64.0), 2.0);
	float phase = floor(flags / 128.0);
	light = cd.y;
	sky = cd.z;
	vec3 feet = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// the lean where they stand, harder and faster when running
	if (stands + runs > 0.5) {
		float t = (TIME * 35.0 + phase * 37.0) * 0.055 * (runs > 0.5 ? 4.0 : 1.0);
		float lean = sin(t) * 1.3 * (runs > 0.5 ? 1.6 : 1.0);
		float bob = abs(sin(t * 2.0 + phase)) * 0.7 * (runs > 0.5 ? 3.0 : 1.0) - 0.7 * runs;
		// (map x, y) is (x, -z) here
		feet += vec3(cos(phase) * lean, bob, -sin(phase) * lean) * game_unit;
	}
	// the eye's right, flattened: the card turns about Y only
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(vec3(right.x, 0.0, right.z));
	// A ROW LET GO (Standees._drop: whoever it drew is gone) has its
	// scale zeroed, and the card is built here rather than by the matrix,
	// so the scale is read here too: zero, and the card is a point that
	// draws nothing. Without it the last frame of the dead stayed standing
	// where they fell until the slot was wanted again.
	float shown = length(MODEL_MATRIX[1].xyz);
	vec3 world = feet + (right * VERTEX.x * cell.x + vec3(0.0, VERTEX.y * cell.y, 0.0)) * shown;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	depth = -VERTEX.z;
	float u = mirror > 0.5 ? 1.0 - UV.x : UV.x;
	float cell_i = floor(cd.x + 0.001);
	frost = clamp((cd.x - cell_i) / 0.9, 0.0, 1.0);
	UV = vec2((cell_i + u) / cells, UV.y);
}

void fragment() {
	// how many texels one pixel covers (log2: 0 at one to one, 1 at two)
	vec2 foot = max(abs(dFdx(UV)), abs(dFdy(UV))) * vec2(textureSize(strip, 0));
	float minified = clamp(log2(max(max(foot.x, foot.y), 1e-6)), 0.0, 1.0);
	vec4 c = mix(texture(strip, UV), texture(strip_smooth, UV), minified);
	if (c.a < 0.5) discard;
	// FROZEN: a colour map and not a tint (js/material.js FROST) — the
	// drawing's luminance kept and run up a ramp from a shadowed blue to a
	// pale lit one, so every coat comes out the same ice at its own
	// brightness; mixed in as the frost builds
	if (frost > 0.0) {
		float lum = dot(c.rgb, vec3(0.30, 0.59, 0.11));
		vec3 ice = mix(vec3(0.09, 0.17, 0.31), vec3(0.74, 0.93, 1.05), pow(lum, 0.62));
		c.rgb = mix(c.rgb, ice, frost);
	}
	float l = mix(world_band(light, depth, sky), 1.0, fullbright);
	// ON FIRE (+16), at the user's request ("when npcs are on fire, give
	// them a rotating-burning-palette-recolor"): the drawing's brightness
	// looked up in a ramp of fire — soot, ember red, orange, yellow, white
	// — and the ramp ROTATED, as an old game's palette cycling did, up the
	// body and through the brightnesses together, so the flames crawl up
	// them. Self-lit, mostly: they are their own light now.
	if (alight > 0.5) {
		float lum = dot(c.rgb, vec3(0.30, 0.59, 0.11));
		float k = fract(lum * 1.6 + UV.y * 2.2 + TIME * 3.1);
		// (stepped into eight bands: a palette, not a gradient)
		k = floor(k * 8.0) / 8.0;
		vec3 fire = k < 0.25 ? mix(vec3(0.10, 0.02, 0.01), vec3(0.75, 0.08, 0.02), k * 4.0)
			: k < 0.5 ? mix(vec3(0.75, 0.08, 0.02), vec3(1.0, 0.45, 0.05), (k - 0.25) * 4.0)
			: k < 0.75 ? mix(vec3(1.0, 0.45, 0.05), vec3(1.0, 0.85, 0.25), (k - 0.5) * 4.0)
			: mix(vec3(1.0, 0.85, 0.25), vec3(1.0, 0.98, 0.85), (k - 0.75) * 4.0);
		c.rgb = mix(c.rgb, fire, 0.82);
		l = mix(l, 1.0, 0.75);
	}
	// the map's ambient light and fog too, but not on what is its own light
	ALBEDO = world_fog(world_air(c.rgb * world_lit(l) - c.rgb * ambient_light.rgb * fullbright, depth), depth * (1.0 - fullbright));
	// THROUGH THE THERMAL SIGHT a person is warm whatever colour their coat
	// is, a frozen one the coldest thing there is, a burning one white
	// (js/material.js, the THERMAL block of COMMON_FRAG) — and ONLY a
	// person (+4, Standees): a lamp, a beast, a corpse is the cold band,
	// burning or not, lit or not
	if (thermal_on(VIEWPORT_SIZE)) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float h = thermal_of(c.rgb, l, depth, wp, fullbright);
		if (warm > 0.5) h = max(thermal_body(c.rgb, depth), alight);
		h = mix(h, 0.02, frozen);
		ALBEDO = thermal_out(h);
	}
}
