extends SceneTree

## FENRIR — the real places' plants as billboards, rendered from their models.
##
##   godot --path . --rendering-driver opengl3 --script res://tools/earth_billboards.gd \
##       -- tools/.earth-cache/models/manifest.json tools/.earth-cache/sprites
##
## Run by `tools/earth_pack.py billboards`, which fetched the models (CC0, Poly
## Haven) and writes the manifest, and which finishes what this leaves: the
## trim, the downscale, the fringe and the burn maps.
##
## At the user's request the vegetation stays billboards, "albeit high res". So
## each plant is drawn here once (or from two or three sides, for variety) the
## way the game sees it: side-on, standing on the bottom edge of the picture and
## filling its height, at twice the sprite's size for the downscale to smooth.
## Lit from the front and above with a soft sky round it and its own shadows on,
## so the crown has the volume the billboard shader's flat light cannot give it.

const SUPER := 2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	printerr("earth_billboards: start")
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("earth_billboards: manifest.json and an output folder, please")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not parsed is Array:
		printerr("earth_billboards: cannot read %s" % args[0])
		quit(1)
		return
	var out_dir := String(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	printerr("earth_billboards: %d models" % (parsed as Array).size())

	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(512, 512)
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.84, 0.95)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	vp.add_child(sun)
	# from the front, up and to the left
	sun.look_at_from_position(Vector3(-4, 6, 6), Vector3.ZERO, Vector3.UP)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 500.0
	vp.add_child(cam)
	cam.current = true

	for m in parsed:
		var d: Dictionary = m
		printerr("earth_billboards: loading %s" % d["id"])
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(String(d["gltf"]), st)
		if err != OK:
			printerr("earth_billboards: %s did not load (%d)" % [d["gltf"], err])
			continue
		var node := doc.generate_scene(st) as Node3D
		if node == null:
			continue
		vp.add_child(node)
		await process_frame
		var size: Array = d["size"]
		var w := int(size[0]) * SUPER
		var h := int(size[1]) * SUPER
		vp.size = Vector2i(w, h)
		# A model that is several plants side by side (Poly Haven ships its
		# shrubs and grasses that way) is drawn a plant at a time, the rest
		# hidden: each is a variant
		var parts := _variants(node)
		var limit := int(d.get("variants", 4))
		for vi in range(mini(parts.size(), limit)):
			for k in range(parts.size()):
				(parts[k] as Node3D).visible = k == vi
			for yaw in d["yaws"]:
				_frame(cam, [parts[vi]], float(d.get("pitch", 0.0)), float(yaw),
						float(w) / float(h))
				sun.directional_shadow_max_distance = cam.size * 4.0
				for _i in range(4):
					await process_frame
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				var path := out_dir.path_join("%s_%d_%d.png" % [d["id"], vi, int(yaw)])
				img.save_png(path)
				printerr("earth_billboards: %s (%dx%d)" % [path, w, h])
		node.queue_free()
		await process_frame
	quit(0)


## Points the camera at the plant from the side — from `yaw` degrees round it,
## `pitch` degrees down — with its base on the bottom edge and its top on the
## top, centred across.
func _frame(cam: Camera3D, roots: Array, pitch: float, yaw: float, aspect: float) -> void:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0))
	var corners: Array[Vector3] = []
	for r in roots:
		for mi in _meshes(r):
			var ab: AABB = mi.get_aabb()
			var xf: Transform3D = mi.global_transform
			for k in range(8):
				corners.append(xf * ab.get_endpoint(k))
	if corners.is_empty():
		return
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var inv := basis.inverse()
	for c in corners:
		var p := inv * c
		lo = lo.min(p)
		hi = hi.max(p)
	var view_h := (hi.y - lo.y) * 1.01
	if (hi.x - lo.x) * 1.01 > view_h * aspect:
		view_h = (hi.x - lo.x) * 1.01 / aspect
	cam.size = view_h
	var centre := Vector3((lo.x + hi.x) * 0.5, lo.y + view_h * 0.5 - (hi.y - lo.y) * 0.003, hi.z + 50.0)
	cam.global_transform = Transform3D(basis, basis * centre)


## The plants a model holds: its top-level parts if there are several standing
## apart, else the whole.
func _variants(root: Node3D) -> Array:
	var top: Node = root
	# (down through the wrappers glTF scenes come in)
	while top.get_child_count() == 1 and not (top.get_child(0) is MeshInstance3D):
		top = top.get_child(0)
	var parts: Array = []
	for c in top.get_children():
		if c is Node3D and not _meshes(c).is_empty():
			parts.append(c)
	if parts.size() < 2:
		return [root]
	# side by side, not one plant in pieces (a trunk and its crown): no two of
	# them stand on the same spot
	var boxes: Array = []
	for p in parts:
		var b := AABB()
		var first := true
		for mi in _meshes(p):
			var xb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			b = xb if first else b.merge(xb)
			first = false
		boxes.append(b)
	for i in range(boxes.size()):
		for k in range(i + 1, boxes.size()):
			var bi: AABB = boxes[i]
			var bk: AABB = boxes[k]
			var ci := bi.get_center()
			var ck := bk.get_center()
			var reach := 0.35 * minf(minf(bi.size.x, bi.size.z), minf(bk.size.x, bk.size.z))
			if Vector2(ci.x - ck.x, ci.z - ck.z).length() < reach:
				return [root]
	return parts


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
