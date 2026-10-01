## MEWD — the rocket and the cerebral bore as MODELS, at the user's
## request ("use these appropriately"): assets/models/rocket_projectile.glb
## and bore_projectile.glb, each flown as a MultiMesh of its own
## (MissileSystem, BoreSystem). The files' node transforms are baked into
## one mesh with the NOSE ON +Z and the origin where the shot is — the
## rocket's nose cone, the bore's body with its drill bit ahead of it —
## then scaled to the game's units. Each surface keeps its file's colour
## and glow (projectile.gdshader).
class_name ProjectileModels

const SHADER := preload("res://godot/shaders/projectile.gdshader")

## a pool of `count` of the model at `path`, `size` game units nose to tail
static func pool(path: String, size: float, count: int) -> MultiMeshInstance3D:
	var mesh := _baked(load(path), size)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	return mi

## instance i at `at` (map units) heading `d` (map units), turned `roll`
## about its own axis, lit by the sector there
static func place(mm: MultiMesh, i: int, lv: Level, at: Vector3, d: Vector3, roll: float) -> void:
	var z := U.v3(d.x, d.y, d.z).normalized()
	if z.length_squared() < 1e-6:
		z = Vector3(0, 0, -1)
	var ref := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := ref.cross(z).normalized()
	var y := z.cross(x)
	var b := Basis(x, y, z) * Basis(Vector3(0, 0, 1), roll)
	mm.set_instance_transform(i, Transform3D(b, U.v3(at.x, at.y, at.z)))
	var sec: Level.Sector = lv.span_at(at.x, at.y, at.z) if lv != null else null
	mm.set_instance_custom_data(i, Color(sec.light if sec else 0.7, sec.sky if sec else 0.0, 0, 0))

static func _baked(scene: PackedScene, size: float) -> ArrayMesh:
	var root := scene.instantiate()
	var parts := []
	_collect(root, Transform3D(), parts)
	# the long axis, nose to tail, after the nodes' own transforms
	var lo := INF
	var hi := -INF
	for p in parts:
		for v in p.arrays[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = p.xf * v
			lo = minf(lo, w.z)
			hi = maxf(hi, w.z)
	var k := size / maxf(1e-6, hi - lo)
	var out := ArrayMesh.new()
	for p in parts:
		var a: Array = p.arrays
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var src_n = a[Mesh.ARRAY_NORMAL]
		var vi := 0
		for v in a[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = p.xf * v
			vs.append(Vector3(w.x, w.y, w.z - hi) * k)
			ns.append((p.xf.basis * src_n[vi]).normalized() if src_n != null else Vector3.UP)
			vi += 1
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		var src = p.mat
		var col := Color(0.5, 0.5, 0.5)
		var glow := Color(0, 0, 0)
		if src is BaseMaterial3D:
			col = src.albedo_color
			if src.emission_enabled:
				glow = src.emission * src.emission_energy_multiplier
		sm.set_shader_parameter("base", col)
		sm.set_shader_parameter("emit", Vector3(glow.r, glow.g, glow.b))
		out.surface_set_material(out.get_surface_count() - 1, sm)
	root.free()
	return out

static func _collect(n: Node, xf: Transform3D, parts: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var mat = (n as MeshInstance3D).get_surface_override_material(si)
			if mat == null:
				mat = m.surface_get_material(si)
			parts.append({"arrays": m.surface_get_arrays(si), "xf": here, "mat": mat})
	for c in n.get_children():
		_collect(c, here, parts)
