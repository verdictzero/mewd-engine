// MEWD — the room behind the gun, under Mobile (Lofi.gun_on_room): the
// world viewport's picture on a quad over the whole of the gun's view, at
// the far plane, so the gun is drawn onto the room by the depth test
// rather than laid over it by an alpha the Mobile renderer does not keep.
// Unshaded and read as it is: the gun viewport is HDR (U.raw_out), so
// what is written is what the room was. It writes its own depth, as every
// draw in the gun's world does, so an Adreno's LRZ never drops it
// (Lofi.gun_depth).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D room : filter_nearest;

void vertex() {
	// clip space straight: the quad's -1..1 is the screen; the far plane
	// is 0 under the reversed depth of the Mobile renderer
	POSITION = vec4(VERTEX.xy, 0.00001, 1.0);
}

void fragment() {
	// ITS OWN DEPTH (the very value the GPU would write: nothing looks
	// different): a draw that writes its depth is never culled by an
	// Adreno's LRZ, the 8x8 blocks of black on the gun (Lofi.gun_depth)
#ifndef MEWD_FIXED_DEPTH
	DEPTH = FRAGCOORD.z;
#endif
	ALBEDO = texture(room, SCREEN_UV).rgb;
}
