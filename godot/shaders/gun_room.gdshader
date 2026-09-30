// MEWD — the room behind the gun, under Mobile (Lofi.gun_on_room): the
// world viewport's picture on a quad over the whole of the gun's view, at
// the far plane, so the gun is drawn onto the room by the depth test
// rather than laid over it by an alpha the Mobile renderer does not keep.
// Unshaded and read as it is: the gun viewport is HDR (U.raw_out), so
// what is written is what the room was.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D room : filter_nearest;

void vertex() {
	// clip space straight: the quad's -1..1 is the screen; the far plane
	// is 0 under the reversed depth of the Mobile renderer
	POSITION = vec4(VERTEX.xy, 0.00001, 1.0);
}

void fragment() {
	ALBEDO = texture(room, SCREEN_UV).rgb;
}
