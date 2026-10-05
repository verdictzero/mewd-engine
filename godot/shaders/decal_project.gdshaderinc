// MEWD — PROJECTED DECALS, at the user's request ("true decals, so that
// impact effects look good and consistent"): every mark the game lays —
// a hole, blood, a pool, a scorch, a hot spot, a sear and its slag, a
// rocket's crater, a potato's glass, the arc's burn — is a BOX standing
// on the surface where it landed, and its shader paints whatever surface
// is inside the box: the depth already drawn there is read back, made a
// point in the world again, and taken into the box's own space, where
// its x and y are the mark's picture and z is how far off the surface it
// is. So a mark lies on a hillside as the hillside lies, wraps a hummock,
// is cut where the ground drops away, and nothing hangs in the air; there
// is no count of them a mesh (Godot's Decal nodes have eight a mesh on
// the Mobile renderer, which on an island's 128 m chunks is eight a
// hillside) and every mark is drawn the same way, near or far.
//
// The mesh is a unit box (-0.5..0.5); the instance's transform is the
// mark's: x along the surface (the way it was thrown), y across, z the
// surface's normal, x and y scaled to its size. The box is made `thick`
// of its width deep along z, half above the surface and half under, and
// the surface's last `fade` of it either way fades out, as does a
// surface that turns away from the mark's normal (a mark laid on the
// ground is not smeared down a cliff, nor up somebody standing in it).
// AND NOT ACROSS AN EDGE (at the user's request: "make sure decals
// don't affect billboard sprites"): where the depth jumps between one
// pixel and the next — the rim of a plant or a person against the
// ground behind them — the normal read off it is nonsense and could
// pass the facing test, so a jump of more than DP_EDGE of the depth is
// discarded outright. (The marks are also drawn before every sprite:
// Decals.PRIORITY.)
//
// THE BOX IS DRAWN FROM INSIDE (cull_front) WITH NO DEPTH TEST: its back
// faces cover every pixel its volume does, whether the eye is outside it
// or in it, and what decides is the depth read back, so a wall in front
// of a mark still hides it. bake_part >= 0 (the bake view RealDecals,
// now gone, drew a mark's picture in) skips the projection and uses the
// mesh's own UV; nothing sets it now.
uniform sampler2D dp_depth : hint_depth_texture, filter_nearest;
// the Compatibility renderer's depth is 0..1 and GL's clip z -1..1;
// the Vulkan renderers' clip z is the depth as it is (set by Decals)
uniform bool gl_depth = false;
// how deep the box is along the normal, as a share of its width
uniform float thick = 0.5;
// which far share of that depth (each side) fades out
uniform float fade = 0.4;
// a depth jump between neighbouring pixels past this share of the depth
// is an edge, not a surface
const float DP_EDGE = 0.15;
varying flat vec4 dp_i0;
varying flat vec4 dp_i1;
varying flat vec4 dp_i2;
varying flat float dp_kz;
varying flat vec3 dp_n;

#define DECAL_VERTEX \
	{ \
		float dp_l0 = length(MODEL_MATRIX[0].xyz); \
		float dp_l2 = max(length(MODEL_MATRIX[2].xyz), 1e-6); \
		dp_kz = thick * dp_l0 / dp_l2; \
		vec3 dp_v = VERTEX; \
		dp_v.z *= dp_kz; \
		mat4 dp_inv = inverse(MODEL_MATRIX); \
		dp_i0 = vec4(dp_inv[0][0], dp_inv[1][0], dp_inv[2][0], dp_inv[3][0]); \
		dp_i1 = vec4(dp_inv[0][1], dp_inv[1][1], dp_inv[2][1], dp_inv[3][1]); \
		dp_i2 = vec4(dp_inv[0][2], dp_inv[1][2], dp_inv[2][2], dp_inv[3][2]); \
		dp_n = normalize(MODEL_MATRIX[2].xyz); \
		VERTEX = (MODELVIEW_MATRIX * vec4(dp_v, 1.0)).xyz; \
	}

// Declares duv (the mark's picture coordinate, as a quad's UV was),
// dfade (how much of it shows), depth (the surface's distance from the
// eye) and wp (the surface's point in the world); discards a pixel whose
// surface is not inside the box.
// HALF RES BLOOD, at the user's request ("make blood decal half current
// res"): blood is drawn from its shapes, a pixel of the picture each, so
// its resolution was the picture's own; now it is laid in squares two of
// the picture's pixels across — the nearest power of two, so it steps
// (as a mip would) instead of crawling as the distance changes
vec2 half_res(vec2 uv) {
	vec2 fw = max(fwidth(uv), vec2(1e-5));
	float sq = clamp(exp2(floor(log2(0.5 / max(fw.x, fw.y)))), 4.0, 256.0);
	return (floor(uv * sq) + 0.5) / sq;
}

#define DECAL_FRAGMENT \
	vec2 duv = UV; \
	float dfade = 1.0; \
	float depth = 0.0; \
	vec3 wp = vec3(0.0); \
	if (bake_part < 0.0) { \
		float dp_z = texture(dp_depth, SCREEN_UV).r; \
		vec3 dp_ndc = gl_depth ? vec3(SCREEN_UV, dp_z) * 2.0 - 1.0 : vec3(SCREEN_UV * 2.0 - 1.0, dp_z); \
		vec4 dp_vp = INV_PROJECTION_MATRIX * vec4(dp_ndc, 1.0); \
		dp_vp.xyz /= dp_vp.w; \
		depth = -dp_vp.z; \
		if (max(abs(dFdx(depth)), abs(dFdy(depth))) > depth * DP_EDGE) discard; \
		wp = (INV_VIEW_MATRIX * vec4(dp_vp.xyz, 1.0)).xyz; \
		vec3 dp_sn = normalize(cross(dFdx(wp), dFdy(wp))); \
		vec4 dp_w = vec4(wp, 1.0); \
		vec3 dp_l = vec3(dot(dp_i0, dp_w), dot(dp_i1, dp_w), dot(dp_i2, dp_w)); \
		if (abs(dp_l.x) > 0.5 || abs(dp_l.y) > 0.5 || abs(dp_l.z) > 0.5 * dp_kz) discard; \
		duv = vec2(dp_l.x + 0.5, 0.5 - dp_l.y); \
		dfade = (1.0 - smoothstep((1.0 - fade) * 0.5 * dp_kz, 0.5 * dp_kz, abs(dp_l.z))) \
			* smoothstep(0.2, 0.5, abs(dot(dp_sn, dp_n))); \
	}
