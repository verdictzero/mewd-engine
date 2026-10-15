extends Node3D

# THE DRESSING OF A REAL PLACE (EarthField): the two things its ground needs that
# golf's islands do not, done once when the island is made.
#
#   * THE GROUND'S PAINT. SHADER_terrain_earth.gdshader blends twelve PBR layers
#     off three control pictures; they are the field's cover grid, and they are
#     handed to the terrain material here, with where the grid lies in the world.
#   * THE WATER. Every sea, lake and river the field's water grid holds, as flat
#     (or, on a river, falling) sheets at their own levels over the beds the
#     field carved: meshes of the 4 m grid, cut into squares so the far ones can
#     be culled, with how deep the water is and which way a river runs in the
#     vertex data for SHADER_water_earth.gdshader. Where the water reaches the
#     square's edge it is closed with a wall down to the ground, the water's cut
#     face beside the land's.
#
# Nothing here is baked: it is a few thousand quads and three pictures, built in
# milliseconds. On a field that is not an EarthField it does nothing.

@export var island_world_path: NodePath = ^"../IslandWorld"
@export var water_material: Material
## Metres a side of each water mesh.
@export var water_chunk := 256.0

var _field: EarthField = null


func _ready() -> void:
	var iw := get_node_or_null(island_world_path)
	if iw == null:
		return
	_field = iw.get("field") as EarthField
	if _field == null:
		return
	if not _field.get("_ready"):
		_field.prepare()
	var r := _field.data()
	if not r.ok:
		return
	var isl: IslandField.Island = _field.island_in_cell(_field.hub_cell())
	var pivot := Vector3(isl.center.x, isl.base_y, isl.center.y)
	_paint(iw.get("terrain_material") as ShaderMaterial, r, isl)
	position = pivot
	_build_water(r, pivot)


func _paint(mat: ShaderMaterial, r: EarthField.Region, isl: IslandField.Island) -> void:
	if mat == null:
		return
	var tex := _field.control_textures()
	if tex.size() < 3:
		return
	mat.set_shader_parameter("control_a", tex[0])
	mat.set_shader_parameter("control_b", tex[1])
	mat.set_shader_parameter("control_c", tex[2])
	mat.set_shader_parameter("region_origin", isl.center - Vector2(r.half, r.half))
	mat.set_shader_parameter("control_texel", r.cres)
	mat.set_shader_parameter("control_n", float(r.cn))


func _build_water(r: EarthField.Region, pivot: Vector3) -> void:
	var n := r.wn
	if n < 2:
		return
	var per := maxi(int(water_chunk / r.wres), 4)
	var made := 0
	for cj in range(0, n - 1, per):
		for ci in range(0, n - 1, per):
			var mesh := _water_chunk(r, ci, cj, mini(ci + per, n - 1), mini(cj + per, n - 1), pivot)
			if mesh == null:
				continue
			var mi := MeshInstance3D.new()
			mi.name = "Water_%d_%d" % [ci / per, cj / per]
			mi.mesh = mesh
			mi.material_override = water_material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			made += 1
	if made > 0:
		print("earth: %d water meshes" % made)


## Surface y (over the datum) at grid sample (i, j), or NAN.
func _sy(r: EarthField.Region, i: int, j: int) -> float:
	var w := r.water[j * r.wn + i]
	return NAN if is_nan(w) else w - r.datum


func _water_chunk(r: EarthField.Region, i0: int, j0: int, i1: int, j1: int,
		pivot: Vector3) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var cache := {}
	for j in range(j0, j1):
		for i in range(i0, i1):
			var ys := [_sy(r, i, j), _sy(r, i + 1, j), _sy(r, i + 1, j + 1), _sy(r, i, j + 1)]
			var have := 0
			var acc := 0.0
			for y in ys:
				if not is_nan(y):
					have += 1
					acc += y
			if have == 0:
				continue
			# a corner past the water's last sample takes the others' level: the
			# grid runs metres past every shore, so that corner is under the bank
			var fill := acc / float(have)
			var k := PackedInt32Array()
			var corners := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			for c in range(4):
				var y: float = ys[c] if not is_nan(ys[c]) else fill
				var key: Vector2i = corners[c]
				# shared vertices only where the level agrees
				var ck := Vector3i(key.x, key.y, int(round(y * 100.0)))
				if cache.has(ck):
					k.append(cache[ck])
					continue
				var x := -r.half + float(key.x) * r.wres
				var z := -r.half + float(key.y) * r.wres
				k.append(verts.size())
				cache[ck] = verts.size()
				verts.append(Vector3(x, y, z))
				norms.append(Vector3.UP)
				var ground := _field.base_height(x, z, 1.0, _field.island_in_cell(_field.hub_cell())) \
						- pivot.y
				var kind := r.wkind[key.y * r.wn + key.x]
				cols.append(Color(float(kind) / 3.0, 0.0, 0.0, clampf((y - ground) / 32.0, 0.0, 1.0)))
				uvs.append(_flow(r, key.x, key.y) if kind == EarthField.W_RIVER else Vector2.ZERO)
			idx.append_array([k[0], k[1], k[2], k[0], k[2], k[3]])
	# the cut face where the water meets the square's edge
	_edge_walls(r, i0, j0, i1, j1, pivot, verts, norms, cols, uvs, idx)
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A river's flow at a sample: down its surface's slope, a metre or two a second.
func _flow(r: EarthField.Region, i: int, j: int) -> Vector2:
	var c := _sy(r, i, j)
	var gx := 0.0
	var gz := 0.0
	var a := _sy(r, clampi(i - 1, 0, r.wn - 1), j)
	var b := _sy(r, clampi(i + 1, 0, r.wn - 1), j)
	var d := _sy(r, i, clampi(j - 1, 0, r.wn - 1))
	var e := _sy(r, i, clampi(j + 1, 0, r.wn - 1))
	gx = (b if not is_nan(b) else c) - (a if not is_nan(a) else c)
	gz = (e if not is_nan(e) else c) - (d if not is_nan(d) else c)
	var g := Vector2(-gx, -gz)
	if g.length() < 1e-4:
		return Vector2.ZERO
	return g.normalized() * clampf(0.6 + g.length() * 4.0, 0.6, 2.5)


func _edge_walls(r: EarthField.Region, i0: int, j0: int, i1: int, j1: int,
		pivot: Vector3, verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, uvs: PackedVector2Array, idx: PackedInt32Array) -> void:
	var last := r.wn - 1
	var isl := _field.island_in_cell(_field.hub_cell())
	var runs := []
	if j0 == 0:
		for i in range(i0, i1):
			runs.append([Vector2i(i, 0), Vector2i(i + 1, 0), Vector3.FORWARD])
	if j1 == last:
		for i in range(i0, i1):
			runs.append([Vector2i(i + 1, last), Vector2i(i, last), Vector3.BACK])
	if i0 == 0:
		for j in range(j0, j1):
			runs.append([Vector2i(0, j + 1), Vector2i(0, j), Vector3.LEFT])
	if i1 == last:
		for j in range(j0, j1):
			runs.append([Vector2i(last, j), Vector2i(last, j + 1), Vector3.RIGHT])
	for run in runs:
		var a: Vector2i = run[0]
		var b: Vector2i = run[1]
		var ya := _sy(r, a.x, a.y)
		var yb := _sy(r, b.x, b.y)
		if is_nan(ya) or is_nan(yb):
			continue
		var xa := -r.half + float(a.x) * r.wres
		var za := -r.half + float(a.y) * r.wres
		var xb := -r.half + float(b.x) * r.wres
		var zb := -r.half + float(b.y) * r.wres
		var ga := _field.base_height(xa, za, 0.0, isl) - pivot.y
		var gb := _field.base_height(xb, zb, 0.0, isl) - pivot.y
		if ga >= ya and gb >= yb:
			continue
		var base := verts.size()
		var kind := float(r.wkind[a.y * r.wn + a.x]) / 3.0
		for v in [Vector3(xa, ya, za), Vector3(xb, yb, zb), Vector3(xb, minf(gb, yb), zb),
				Vector3(xa, minf(ga, ya), za)]:
			verts.append(v)
			norms.append(run[2])
			cols.append(Color(kind, 0.0, 0.0, 1.0))
			uvs.append(Vector2.ZERO)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
