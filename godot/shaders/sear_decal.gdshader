// MEWD — what the positron lance leaves (js/decals.js DECAL_FRAG, the
// SEAR and SLAG branches). One quad laid on the surface; INSTANCE_CUSTOM:
//   x  the kind: 8 a SEAR (the crater), 9 SLAG (a gob thrown out of it)
//   y  a seed, for the shape
//   z  when it was laid, in seconds, for the heat to cool
//   w  the light of the surface under it, plus two if it is under the sky
// The quad's +x is the way the beam was going laid flat on the surface,
// which the streaks and the drops lean along.
//
// ONLY WHERE THERE IS A SURFACE. The web build's decals are projected:
// they paint the depth buffer and nothing else. These are quads, and a
// sear is ten people wide — laid on a wall that is shorter than that, or
// on a floor at the foot of one, the rest of it would hang in the air.
// So the scene's depth is read back and a fragment that is not ON the
// surface under it (within a hair, wider with distance) is not drawn.
//
// Premultiplied: the paint at its alpha, and the glow added on top.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_premul_alpha, fog_disabled, shadows_disabled, skip_vertex_transform;

#include "res://godot/shaders/world_light.gdshaderinc"
#include "res://godot/shaders/thermal.gdshaderinc"

uniform float now = 0.0;
// set by Decals off the rendering method: see the depth read below
uniform bool gl_depth = false;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
varying vec4 cd;
varying float depth;

void vertex() {
	cd = INSTANCE_CUSTOM;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	depth = -mv.z;
	// AND PULLED A LITTLE TOWARD THE EYE, along the view ray, so it lands
	// on the same pixels but half a per cent nearer: a lift of a unit off
	// the surface is inside the depth buffer's precision a few hundred
	// units away, and the decal fought the wall in bands. A fraction of
	// the depth keeps the same margin at any range.
	VERTEX = mv.xyz * 0.995;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// THE HASHES HAVE NO SINE IN THEM, which the web build's do: the
// sin(big) * 43758 hash is only as good as the GPU's sin a few thousand
// radians out, and a software rasterizer's is not — the noise came out
// smeared along the rows, and the sear in bars. Dave Hoskins's
// fract-and-multiply hash is the same idea on arithmetic every GPU does
// exactly.
float dh1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 dh2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
float dnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(dh1(i), dh1(i + vec2(1.0, 0.0)), u.x), mix(dh1(i + vec2(0.0, 1.0)), dh1(i + vec2(1.0, 1.0)), u.x), u.y);
}
float dfbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) { s += a * dnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return s;
}
// a ragged edge: the radius a round thing reaches at this angle
float rag(float ang, float seed, float amt) {
	vec2 q = vec2(cos(ang), sin(ang)) * 2.2 + seed * 17.0;
	return 1.0 + amt * (dfbm(q) - 0.5) * 2.0;
}
// cracks: thin dark lines running out from the centre
float cracks(vec2 p, float seed, float n) {
	float ang = atan(p.y, p.x);
	float r = length(p);
	float k = ang * n / 6.2831853 + seed * 5.0;
	float cell = floor(k);
	float off = dh1(vec2(cell, seed)) - 0.5;
	float wob = (dnoise(vec2(r * 9.0, cell * 3.1 + seed)) - 0.5) * 0.9;
	float d = abs(fract(k) - 0.5 - off * 0.6 + wob * 0.25);
	float len = 0.55 + 0.45 * dh1(vec2(seed, cell + 7.0));
	float w = 0.09 * (1.0 - r / max(len, 0.01));
	return (r < len) ? 1.0 - smoothstep(0.0, max(w, 0.0001), d) : 0.0;
}
// the fire's own ramp, dull red to yellow-white
vec3 hot_ramp(float h) {
	return h < 0.5 ? mix(vec3(0.55, 0.03, 0.0), vec3(1.0, 0.36, 0.05), h * 2.0)
	               : mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.62), (h - 0.5) * 2.0);
}

void fragment() {
	// on the surface under it, or nothing
	float dz = texture(depth_tex, SCREEN_UV).r;
	// the Compatibility renderer's depth is 0..1 and GL's clip z is -1..1;
	// Forward+'s clip z is the depth as it is
	vec3 ndc = gl_depth ? vec3(SCREEN_UV, dz) * 2.0 - 1.0 : vec3(SCREEN_UV * 2.0 - 1.0, dz);
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene = -vp.z / vp.w;
	if (abs(scene - depth) > 3.0 + depth * 0.02) discard;

	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float kind = cd.x;
	float seed = cd.y;
	float age = max(0.0, now - cd.z);
	float sky = step(1.5, cd.w);
	float lit = world_band(cd.w - sky * 2.0, depth, sky);
	vec3 col = vec3(0.0);
	float a = 0.0;
	vec3 glow = vec3(0.0);

	if (kind < 8.5) {
		// A SEAR: where the positron column landed, and the biggest mark
		// in the game by a factor of three. Not a hole — nothing is cut,
		// at the user's request — but what a surface looks like after a
		// column of plasma has sat on it for a second: a CRATER of
		// vitrified black glass with the lance's green in it, white-hot
		// for the first second; a RIM still molten, orange for ten; CHAR
		// thrown out in a STARBURST of uneven streaks, longer on the side
		// the beam was going (+x); cracks and veins with the coals still
		// in them for half a minute; DROPLETS of slag flung past the rim;
		// and soot under all of it. All of it off the decal's own seed.
		float core = exp(-age / 0.9);
		float heat = exp(-age / 5.0);
		float ember = exp(-age / 14.0);
		float stretch = 1.0 + 0.35 * dh1(vec2(seed, 1.7));
		vec2 q = vec2((p.x + 0.06) / stretch, p.y);
		float rq = length(q);
		float aq = atan(q.y, q.x);
		float R = rag(aq, seed, 0.24);
		float rr = rq / R;
		// the starburst
		float n_streak = 9.0 + floor(dh1(vec2(seed, 5.3)) * 10.0);
		float ks = aq * n_streak / 6.2831853 + seed * 3.0;
		float cell_s = floor(ks);
		float len_s = (0.46 + 0.46 * dh1(vec2(cell_s, seed * 7.0))) * (1.0 + 0.3 * max(0.0, cos(aq)));
		float wob = (dnoise(vec2(rq * 7.0, cell_s * 2.3 + seed)) - 0.5) * 0.3;
		float streak = (1.0 - smoothstep(0.10, 0.34, abs(fract(ks) - 0.5 + wob) + rq * 0.22))
			* (1.0 - smoothstep(len_s * 0.65, len_s, rq)) * step(0.2, rq);
		// the crater, the rim, the char and the soot
		float crater = 1.0 - smoothstep(0.23, 0.28, rr);
		float rim = smoothstep(0.19, 0.27, rr) * (1.0 - smoothstep(0.29, 0.40, rr));
		float char_z = 1.0 - smoothstep(0.28, 0.60, rr * (0.8 + 0.4 * dfbm(q * 3.0 + seed)));
		float soot = (1.0 - smoothstep(0.42, 1.0, rq)) * (0.4 + 0.6 * dfbm(q * 4.0 + seed * 3.0));
		// the droplets, thrown out past the rim and drawn out along the
		// way each one flew
		float drops = 0.0;
		for (int i = 0; i < 18; i++) {
			vec2 h = dh2(vec2(float(i) * 2.13, seed * 5.7));
			float th = h.x * 6.2831853;
			float dist = 0.34 + 0.56 * h.y * (0.8 + 0.25 * max(0.0, cos(th)));
			vec2 dir = vec2(cos(th), sin(th));
			vec2 dq = p - dir * dist;
			float al = dot(dq, dir) / (1.0 + dist * 1.8);
			float ac = dot(dq, vec2(-dir.y, dir.x));
			float sz = mix(0.075, 0.022, h.y) * (0.6 + 0.8 * dh1(h * 3.1));
			drops = max(drops, 1.0 - smoothstep(sz * 0.7, sz, length(vec2(al, ac))));
		}
		float glass_n = dfbm(q * 7.0 + seed * 2.0);
		vec3 glass = mix(vec3(0.015, 0.025, 0.022), vec3(0.07, 0.15, 0.11), smoothstep(0.55, 0.82, glass_n));
		vec3 char_c = mix(vec3(0.03, 0.025, 0.02), vec3(0.10, 0.08, 0.06), dfbm(q * 12.0 + seed));
		col = mix(char_c, glass, crater);
		a = max(crater, max(char_z * 0.97, max(streak * 0.9, max(soot * 0.82, drops * 0.95))));
		col = world_air(col * lit * light_color.rgb, depth);
		float cr = cracks(q, seed, 13.0) * step(0.27, rr) * (1.0 - smoothstep(0.55, 0.9, rr));
		float n2 = dfbm(q * 8.0 + seed * 9.0);
		float veins = (1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5))) * char_z * step(0.29, rr);
		float flick = 0.75 + 0.25 * dnoise(q * 10.0 + vec2(now * 2.7, -now * 2.1));
		glow = hot_ramp(clamp(0.55 + 0.45 * core, 0.0, 1.0)) * crater * (core * 2.2 + heat * 0.3 * (1.0 - rr / 0.28))
			+ hot_ramp(clamp(heat * 1.1, 0.0, 1.0)) * rim * heat * 2.6
			+ hot_ramp(clamp(ember * 0.8, 0.0, 1.0)) * max(cr, veins) * ember * flick * 1.6
			+ hot_ramp(clamp(heat, 0.0, 1.0)) * (drops + streak * 0.35) * heat * 1.3
			+ vec3(0.45, 1.0, 0.6) * rim * core * 0.9;
	} else {
		// SLAG: a gob of what the sear threw, landed round it. A ragged
		// blob with a spray of drops ahead of it along the throw — orange
		// from the edge in while it is fresh, cooling over a few seconds.
		float heat = exp(-age / 4.0);
		float R = rag(ang, seed, 0.4);
		float rb = r / (R * (0.8 + 0.2 * dh1(vec2(seed, 3.0))));
		float blob = 1.0 - smoothstep(0.26, 0.33, rb);
		float drops = 0.0;
		for (int i = 0; i < 10; i++) {
			vec2 h = dh2(vec2(float(i) * 1.91, seed * 6.3));
			float dist = 0.28 + 0.66 * h.x;
			vec2 c = vec2(dist * 0.95 - 0.1, (h.y - 0.5) * 1.2 * dist);
			float sz = mix(0.10, 0.03, dist) * (0.6 + 0.8 * dh1(h * 4.0));
			vec2 dq = p - c;
			dq.x /= 1.0 + dist * 2.0;
			drops = max(drops, 1.0 - smoothstep(sz * 0.75, sz, length(dq)));
		}
		float m = max(blob, drops);
		float n = dfbm(p * 6.0 + seed * 4.0);
		float soot = (1.0 - smoothstep(0.2, 0.8, rb)) * 0.6 * (0.5 + 0.5 * n);
		col = world_air(mix(vec3(0.025, 0.022, 0.02), vec3(0.09, 0.08, 0.07), n) * lit * light_color.rgb, depth);
		a = max(m * 0.96, soot);
		float edge = blob * smoothstep(0.14, 0.30, rb);
		glow = hot_ramp(clamp(heat * (0.6 + 0.5 * n), 0.0, 1.0)) * (m * 0.6 + edge * 1.2) * heat * 1.8;
	}
	if (a < 0.004 && dot(glow, vec3(1.0)) < 0.004) discard;
	ALBEDO = col * a + glow;
	ALPHA = a;
	// the thermal sight's feed: the scar as a surface, its glow as heat
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_of(col, lit, depth, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, 0.0)) * a + thermal_out(thermal_glow(glow));
}
