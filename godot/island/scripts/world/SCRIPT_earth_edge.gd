extends MeshInstance3D

# THE FIELD AT THE EDGE OF A REAL PLACE (EarthField): at the user's request,
# "an animated hexagonal grid forcefield effect at the edges where the land
# gets cut off". The square ends in a cut face falling into the cloud; this
# hangs a curtain of light all round it, a couple of metres outside the face
# (clear of the rock, so the two never fight over one depth), from the cloud
# deck to `reach` metres over the land — drawn by
# SHADER_earth_edge_field.gdshader, which this hands the land's height along
# the edge (each column's UV2.x, for the seam of light where the land is
# cut), how far round the square each column is (UV.x, for the hexes) and the
# size of hex that goes round it a whole number of times.
#
# Built once, when the place is made: a strip of quads, a column every `step`
# metres. On a field that is not an EarthField it does nothing.

@export var island_world_path: NodePath = ^"../IslandWorld"
@export var cloud_sea_path: NodePath = ^"../CloudSea"
@export var field_material: ShaderMaterial
## Metres between the curtain's columns along the edge.
@export var step := 4.0
## Metres outside the cut face the curtain hangs.
@export var standoff := 2.0
## Metres over the land the curtain reaches.
@export var reach := 700.0
## The hexes, metres across their flats, about: made to go round the square a
## whole number of times.
@export var hex_metres := 14.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var iw := get_node_or_null(island_world_path)
	if iw == null:
		return
	var f := iw.get("field") as EarthField
	if f == null:
		return
	if not f.get("_ready"):
		f.prepare()
	var r := f.data()
	if not r.ok or field_material == null:
		return
	var isl: IslandField.Island = f.island_in_cell(f.hub_cell())
	position = Vector3(isl.center.x, isl.base_y, isl.center.y)
	var deck := -45.0
	var sea := get_node_or_null(cloud_sea_path)
	if sea != null and sea.get("sea_altitude") != null:
		deck = float(sea.get("sea_altitude"))
	deck -= isl.base_y
	var half := r.half + standoff
	var round_m := 8.0 * half
	var hexes := maxf(roundf(round_m / maxf(hex_metres, 1.0)), 1.0)
	mesh = _curtain(f, isl, r.half, half, deck)
	var m := field_material.duplicate() as ShaderMaterial
	m.set_shader_parameter("hex_metres", round_m / hexes)
	m.set_shader_parameter("reach", reach)
	m.set_shader_parameter("deck_y", deck)
	material_override = m


## The curtain: the four sides, clockwise from the north-west corner seen from
## above, each a strip of columns from the deck to `reach` over the land
## at the edge.
func _curtain(f: EarthField, isl: IslandField.Island, edge: float, half: float,
		deck: float) -> ArrayMesh:
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var outward: Array[Vector3] = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	var n := maxi(int(ceil(2.0 * half / maxf(step, 0.5))), 1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var s0 := 0.0
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var base := verts.size()
		for k in n + 1:
			var t := float(k) / float(n)
			var c := a.lerp(b, t)
			# (the land at the very edge, under the column)
			var g := f.coast_y(isl, isl.center.x + c.x * edge, isl.center.y + c.y * edge) - isl.base_y
			var s := s0 + t * 2.0 * half
			for y: float in [deck, g + reach]:
				verts.append(Vector3(c.x * half, y, c.y * half))
				norms.append(outward[side])
				uv.append(Vector2(s, 0.0))
				uv2.append(Vector2(g, 0.0))
			if k > 0:
				var q := base + (k - 1) * 2
				idx.append_array([q, q + 1, q + 2, q + 2, q + 1, q + 3])
		s0 += 2.0 * half
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
