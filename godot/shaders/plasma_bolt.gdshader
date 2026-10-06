// MEWD — the plasma rifle's bolt and the flash where it lands
// (game/plasma.gd).
//
// A BOLT (UV2.x 0) is one quad facing the eye along the line it flies:
// UV.x along it (0 the tail, 1 the head), UV.y across (-1 to 1), UV2.y how
// long it is against how wide. Out of that, a CAPSULE — a long pellet with
// both ends rounded — in three layers, laid over the picture: a white-hot core, a
// bright cyan body and a soft blue halo, the head brighter than the tail.
// A BEAD (UV2.x 1) is one of the balls strung down the bolt that make it
// a bolt when it is seen end on, UV2.y how far along it is. A FLASH (UV2.x
// 2) is a disc facing the eye, UV2.y how far through its life it is: a white heart and a blue ring swelling out and fading.
// Banded, like everything else drawn in this game.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void fragment() {
	vec3 col = vec3(0.0);
	float kind = UV2.x;
	if (kind > 2.5) {
		discard;
	} else if (kind > 0.5 && kind < 1.5) {
		// a bead: a soft blue ball with a white heart, the head's brightest
		float r = length(vec2(UV.x * 2.0 - 1.0, UV.y));
		float q = UV2.y;
		float heart = 1.0 - smoothstep(0.26, 0.46, r);
		float body = 1.0 - smoothstep(0.34, 0.62, r);
		float halo = exp(-r * r * 4.0) * (1.0 - smoothstep(0.7, 1.0, r));
		col = mix(vec3(0.10, 0.45, 1.0), vec3(1.0), heart * (0.8 + 0.2 * q)) * max(body, heart)
			+ vec3(0.03, 0.12, 0.8) * halo * 0.5 * (1.0 - body);
		col *= 0.75 + 0.25 * q;
	} else if (kind > 1.5) {
		float k = UV2.y;
		float r = length(vec2(UV.x * 2.0 - 1.0, UV.y));
		float heart = exp(-r * r * 9.0) * (1.0 - k);
		float ring = exp(-pow((r - 0.35 - 0.5 * k) * 7.0, 2.0)) * (1.0 - k) * 0.9;
		col = vec3(1.0, 1.0, 1.0) * heart * 1.6 + vec3(0.25, 0.6, 1.0) * ring + vec3(0.1, 0.3, 1.0) * exp(-r * r * 3.0) * (1.0 - k) * 0.6;
	} else {
		float aspect = max(UV2.y, 1.0);
		// distance from the capsule's spine, in widths: along it in the
		// same units as across, so the ends are round
		float along = UV.x * aspect;
		float cx = clamp(along, 1.0, aspect - 1.0);
		float d = length(vec2(along - cx, UV.y));
		float head = mix(0.55, 1.0, UV.x);
		// the halo is the whole quad; the body half of it; the white core most
		// of that (the palette snap greys a blue: the white is what reads)
		float halo = exp(-d * d * 2.5) * 0.6 * (1.0 - smoothstep(0.7, 1.0, d));
		float body = 1.0 - smoothstep(0.42, 0.55, d);
		float core = 1.0 - smoothstep(0.24, 0.36, d);
		col = vec3(0.03, 0.12, 0.8) * halo * (1.0 - body) + mix(vec3(0.10, 0.45, 1.0), vec3(1.0), core) * max(body, core);
		col *= head;
	}
	// LAID OVER, not added: on a bright road an added glow is lost. The
	// strongest channel is how much of it there is; the colour is the
	// colour at full strength, a little over white in the core
	col *= 1.5;
	float a = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
	a = floor(a * 8.0 + 0.5) / 8.0;
	ALBEDO = col / max(a, 0.05);
	ALPHA = a;
}
