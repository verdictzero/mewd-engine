extends SceneTree
func _initialize():
	var args := OS.get_cmdline_user_args()
	var f: String = args[0]
	var roll := float(args[1])
	var out: String = args[2]
	await process_frame
	var w := Node3D.new(); root.add_child(w)
	await process_frame
	var s: Node3D = (load(f) as PackedScene).instantiate()
	var holder := Node3D.new(); holder.rotation.z = deg_to_rad(roll)
	holder.add_child(s); w.add_child(holder)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-40, 30, 0); w.add_child(l)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.5,0.5,0.5); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.2,0.3,0.4); w.add_child(env)
	for v in [[Vector3(14, 0, 0.7), "side"], [Vector3(0, 0, 16), "front"]]:
		var c := Camera3D.new(); w.add_child(c); c.fov = 50.0; c.look_at_from_position(v[0], Vector3(0, 0, 0.7)); c.current = true
		await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "_" + v[1] + ".png")
		c.queue_free()
	quit()
