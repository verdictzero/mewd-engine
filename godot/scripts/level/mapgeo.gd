## MEWD — the level's triangles (js/mapgeo.js, buildLevelGeometry).
##
## Floors and ceilings per sector, walls per line — the one-sided middle
## from floor to ceiling, the two-sided step (LOWER, between the two
## floors, facing the lower side) and lintel (UPPER, between the two
## ceilings, facing the higher) — every texture's triangles batched
## into one surface. The light is baked into the vertex colour (r the
## light, g how much of it is sky); the shader does the rest.
##
## THE UVs ARE DOOM'S. A wall's u runs along the line from the end its
## side measures from (a front from v1, a back from v2) and its v is
## (peg - z) / texture height, `peg` being the height the texture's top
## row is nailed to: the ceiling for a middle, the top of a step for a
## lower, the lintel's bottom plus a repeat for an upper. A floor's is
## its map position over the texture's size, so floors tile from the
## world origin and line up across sectors.
class_name MapGeo
extends RefCounted

class Batch:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, color: Color) -> void:
		var n := v.size()
		v.append_array([a, b, c])
		uv.append_array([ua, ub, uc])
		col.append_array([color, color, color])
		idx.append_array([n, n + 1, n + 2])

	func quad(p: Array, u: Array, color: Color) -> void:
		var n := v.size()
		for i in 4:
			v.append(p[i])
			uv.append(u[i])
			col.append(color)
		idx.append_array([n, n + 1, n + 2, n, n + 2, n + 3])

var bank: TexBank
var batches := {}

func _init(b: TexBank) -> void:
	bank = b

func _batch(name: String) -> Batch:
	if not batches.has(name):
		batches[name] = Batch.new()
	return batches[name]

## Build every surface of `lv` into a Node3D of MeshInstance3Ds.
func build(lv: Level) -> Node3D:
	for s in lv.sectors:
		_flats(s)
	for l in lv.lines:
		_walls(lv, l)
	var root := Node3D.new()
	root.name = "LevelGeometry"
	for name in batches:
		var b: Batch = batches[name]
		if b.v.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = b.v
		arr[Mesh.ARRAY_TEX_UV] = b.uv
		arr[Mesh.ARRAY_COLOR] = b.col
		arr[Mesh.ARRAY_INDEX] = b.idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, bank.material(name))
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root

static func _light(l: float, sky: float) -> Color:
	return Color(clampf(l, 0.02, 1.4), sky, 0.0, 1.0)

func _flat_tris(s: Level.Sector) -> PackedInt32Array:
	var n := s.poly.size()
	if s.convex:
		var out := PackedInt32Array()
		for i in range(1, n - 1):
			out.append_array([0, i, i + 1])
		return out
	return Geometry2D.triangulate_polygon(s.poly)

func _flats(s: Level.Sector) -> void:
	var tris := _flat_tris(s)
	var color := _light(s.light, s.sky)
	if s.floor_tex != "" and s.floor_tex != "SKY":
		var b := _batch(s.floor_tex)
		var ts := bank.size_of(s.floor_tex)
		for i in range(0, tris.size(), 3):
			var p := [s.poly[tris[i]], s.poly[tris[i + 1]], s.poly[tris[i + 2]]]
			b.tri(U.v3(p[0].x, p[0].y, s.floor), U.v3(p[1].x, p[1].y, s.floor), U.v3(p[2].x, p[2].y, s.floor),
				p[0] / ts, p[1] / ts, p[2] / ts, color)
	if s.ceil_tex != "" and s.ceil_tex != "SKY":
		var b := _batch(s.ceil_tex)
		var ts := bank.size_of(s.ceil_tex)
		for i in range(0, tris.size(), 3):
			var p := [s.poly[tris[i]], s.poly[tris[i + 1]], s.poly[tris[i + 2]]]
			b.tri(U.v3(p[2].x, p[2].y, s.ceil), U.v3(p[1].x, p[1].y, s.ceil), U.v3(p[0].x, p[0].y, s.ceil),
				p[2] / ts, p[1] / ts, p[0] / ts, color)

func _walls(lv: Level, l: Level.Line) -> void:
	if l.back == -1:
		var s := lv.sectors[l.front]
		if l.middle != null:
			_quad(l, str(l.middle), s.floor, s.ceil, true, s.ceil + l.yoff, s)
		return
	var f := lv.sectors[l.front]
	var b := lv.sectors[l.back]
	# THE STEP, facing whichever side is lower
	if absf(f.floor - b.floor) > 1e-3:
		var lo_front := f.floor < b.floor
		var seen := f if lo_front else b
		var z0 := minf(f.floor, b.floor)
		var z1 := maxf(f.floor, b.floor)
		_quad(l, str(l.lower), z0, z1, lo_front, z1 + l.yoff, seen)
	# THE LINTEL, facing whichever side is higher — unless both are sky
	if absf(f.ceil - b.ceil) > 1e-3 and not (f.ceil_tex == "SKY" and b.ceil_tex == "SKY"):
		var hi_front := f.ceil > b.ceil
		var seen := f if hi_front else b
		var z0 := minf(f.ceil, b.ceil)
		var z1 := maxf(f.ceil, b.ceil)
		var th := bank.size_of(str(l.upper)).y
		_quad(l, str(l.upper), z0, z1, hi_front, z0 + th + l.yoff, seen)

func _quad(l: Level.Line, tex: String, z0: float, z1: float, facing_front: bool, peg: float, seen: Level.Sector) -> void:
	if z1 - z0 <= 1e-6 or tex == "" or tex == "<null>":
		return
	var ts := bank.size_of(tex)
	var b := _batch(tex)
	var u0 := l.xoff / ts.x
	var u1 := (l.xoff + l.len) / ts.x
	var vt := (peg - z1) / ts.y
	var vb := (peg - z0) / ts.y
	var color := _light(seen.light + l.contrast, seen.sky)
	# a front side reads from v1, a back side from v2
	var a := Vector2(l.x1, l.y1) if facing_front else Vector2(l.x2, l.y2)
	var c := Vector2(l.x2, l.y2) if facing_front else Vector2(l.x1, l.y1)
	b.quad([U.v3(a.x, a.y, z1), U.v3(c.x, c.y, z1), U.v3(c.x, c.y, z0), U.v3(a.x, a.y, z0)],
		[Vector2(u0, vt), Vector2(u1, vt), Vector2(u1, vb), Vector2(u0, vb)], color)
