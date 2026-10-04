## MEWD — a picture of a MODEL on its own: the GLB at --model=, lit, on a
## grey ground, the eye `yaw` radians round it and `pitch` radians up (or
## down, negative) at `dist` metres from its middle.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method mobile \
##   --script res://godot/tests/model_shot.gd -- --model=res://assets/models/drop_pod.glb out.png [yaw] [pitch] [dist]
extends SceneTree

var out := "model_shot.png"
var yaw := 0.7
var pitch := 0.35
var dist := 0.0
var _frames := 0

func _init() -> void:
	var model := ""
	var pos := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
		elif not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		yaw = float(pos[1])
	if pos.size() > 2:
		pitch = float(pos[2])
	if pos.size() > 3:
		dist = float(pos[3])
	var scene := Node3D.new()
	root.add_child(scene)
	var m: Node3D = (load(model) as PackedScene).instantiate()
	scene.add_child(m)
	# the model's extent, for the eye
	var box := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		# (not in the tree yet: the transform summed by hand, up to the model)
		var t: Transform3D = (mi as Node3D).transform
		var par := mi.get_parent()
		while par != null and par != m:
			t = (par as Node3D).transform * t
			par = par.get_parent()
		var b: AABB = t * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var mid := box.get_center()
	var size := box.size.length()
	if dist <= 0.0:
		dist = size * 1.1
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size * 6.0, size * 6.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.45, 0.45)
	ground.material_override = gm
	ground.position = Vector3(mid.x, box.position.y, mid.z)
	scene.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	scene.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.8
	env.environment = e
	scene.add_child(env)
	var cam := Camera3D.new()
	var eye := mid + Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * dist
	scene.add_child(cam)
	cam.look_at_from_position(eye, mid)
	cam.fov = 50.0
	cam.current = true
	print("model_shot: %s  %.1f x %.1f x %.1f m, middle %s" % [model, box.size.x, box.size.y, box.size.z, str(mid)])
	process_frame.connect(_frame)

func _frame() -> void:
	_frames += 1
	if _frames < 8:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	print("model_shot: " + out)
	quit(0)
