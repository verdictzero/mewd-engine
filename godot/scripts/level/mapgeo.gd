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
##
## THE WINDING IS GODOT'S: a front face is clockwise as seen, so a floor
## is wound clockwise seen from above (a map ring is anticlockwise) and a
## ceiling the other way; a wall's front face, seen from the sector on
## its right, runs v1 to v2 along the top. The maze's shader draws both
## faces anyway; the tinted one culls.
##
## AN EDITED MAP HAS MORE (DocCompile): a line's two SIDES, each face
## wearing its own texture; a MIDDLE standing in a two-sided line — a
## door, a fence, a painted horizon, drawn once at its own height, or a
## building's outside wall filling the opening; NONE for no wall at all;
## pegging and scale; floors round HOLES (earcut, from the outline and
## the holes); a ROOF over every roofed room, Level.DECK over its
## ceiling, and round its edge the side of the slab; the free BOXES (level
## props); and each surface's Doom 64 colour and fog, per vertex, for
## godot/shaders/world_tint.gdshader, which such a level is drawn with.
##
## AND A MAP IN STOREYS (Level's columns, addLine in js/mapgeo.js): every
## storey's floor and ceiling (the ceiling of the room under a deck is
## the deck's underside, Level.DECK under the floor over it, and the edge
## of the slab between is a band like any other); a one-sided wall a storey at a
## time, each in its own skin; a two-sided line as its BANDS — every
## interval of z where exactly one of its columns is open, the face of
## whatever is in the way — and a middle once per HOLE, where both are
## (and only in the openings a building's outside wall fills, mid_z).
class_name MapGeo
extends RefCounted

class Batch:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	# the tinted shader's two per-vertex colours, when the level has them
	var custom := false
	var c0 := PackedFloat32Array()        # tint rgb, 1
	var c1 := PackedFloat32Array()        # fog rgb, density (< 0: the map's)
	# what is being added now: null (white), a Color, or [top, bottom,
	# z0, z1] graded by height — and its fog
	var paint = null
	var fogc := Color(0, 0, 0, -1)

	func _cv(p: Vector3) -> void:
		var t := Color.WHITE
		if paint is Color:
			t = paint
		elif paint is Array:
			var k := clampf((p.y - paint[2]) / (paint[3] - paint[2]), 0.0, 1.0)
			t = (paint[1] as Color).lerp(paint[0], k)
		c0.append_array([t.r, t.g, t.b, 1.0])
		c1.append_array([fogc.r, fogc.g, fogc.b, fogc.a])

	func tri(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, color: Color) -> void:
		var n := v.size()
		v.append_array([a, b, c])
		uv.append_array([ua, ub, uc])
		col.append_array([color, color, color])
		idx.append_array([n, n + 1, n + 2])
		if custom:
			_cv(a); _cv(b); _cv(c)

	func quad(p: Array, u: Array, color: Color) -> void:
		var n := v.size()
		for i in 4:
			v.append(p[i])
			uv.append(u[i])
			col.append(color)
			if custom:
				_cv(p[i])
		idx.append_array([n, n + 1, n + 2, n, n + 2, n + 3])

var bank: TexBank
var batches := {}
var tinted := false
var _paint = null
var _fog := Color(0, 0, 0, -1)
const NO_FOG := Color(0, 0, 0, -1)

func _init(b: TexBank) -> void:
	bank = b

func _batch(name: String) -> Batch:
	if not batches.has(name):
		var b := Batch.new()
		b.custom = tinted
		batches[name] = b
	var bt: Batch = batches[name]
	bt.paint = _paint
	bt.fogc = _fog
	return bt

## Build every surface of `lv` into a Node3D of MeshInstance3Ds.
func build(lv: Level) -> Node3D:
	tinted = lv.tinted
	if not tinted:
		for s in lv.sectors:
			for t in [s.floor_tex, s.wall_tex]:
				if TexBank.OWN.has(t) and TexBank.OWN[t][4]:
					tinted = true
	for s in lv.sectors:
		_flats(s)
	for l in lv.lines:
		_walls(lv, l)
		_roof_edge(lv, l)
	for p in lv.props:
		_box(p)
	var root := Node3D.new()
	root.name = "LevelGeometry"
	var flags := 0
	if tinted:
		flags = (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
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
		if tinted:
			arr[Mesh.ARRAY_CUSTOM0] = b.c0
			arr[Mesh.ARRAY_CUSTOM1] = b.c1
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		mesh.surface_set_material(0, bank.material_tinted(name) if tinted else bank.material(name))
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if tinted:
		bank.set_map_light(lv.map_light)
		# the map's light colour is on everything, sprites and plants too
		if lv.map_light.has("lightColor"):
			RenderingServer.global_shader_parameter_set("light_color", lv.map_light.lightColor)
	# and its ambient light and default fog, on the things that are not
	# the level's own surfaces (world_lit and world_fog in
	# world_light.gdshaderinc) — nothing, for a level without them
	var ml: Dictionary = lv.map_light if tinted else {}
	var amb: Color = ml.get("ambient", Color.BLACK)
	var fog: Color = ml.get("fog", Color(0, 0, 0, 0))
	RenderingServer.global_shader_parameter_set("ambient_light", Color(amb.r, amb.g, amb.b, 1.0))
	RenderingServer.global_shader_parameter_set("map_fog", Vector4(fog.r, fog.g, fog.b, fog.a))
	RenderingServer.global_shader_parameter_set("map_fog_ambient", float(ml.get("fogAmbient", 1.0)))
	return root

static func _light(l: float, sky: float) -> Color:
	return Color(clampf(l, 0.02, 1.4), sky, 0.0, 1.0)

## How a sector's walls are coloured (paintWall): top colour at its
## ceiling down to the bottom one at its floor — or, under the sky, over
## the piece of wall's own height — or null if it says nothing.
static func _paint_wall(s: Level.Sector, lo = null, hi = null):
	var t = s.tint
	if t == null or (not t.has("top") and not t.has("bottom")):
		return null
	var own: bool = s.ceil_tex == "SKY" and lo != null and hi > lo
	var z0: float = lo if own else s.floor
	var z1: float = hi if own else maxf(s.floor + 1, s.ceil)
	return [t.get("top", Color.WHITE), t.get("bottom", Color.WHITE), z0, z1]

static func _flat_paint(s: Level.Sector, part: String):
	return s.tint.get(part) if s.tint != null else null

static func _fog_of(s: Level.Sector) -> Color:
	return s.fog if s.fog != null else NO_FOG

## One face of a line, as the sector it looks into sees it (sideOf): the
## line's own offsets and scale with that side's over them, and that
## side's textures (null where it says nothing).
static func _side(l: Level.Line, s: Level.Sector) -> Dictionary:
	var o = l.sides.get(str(s.doc_id)) if not l.sides.is_empty() and s.doc_id != null else null
	if o == null:
		return {"mid": null, "upper": null, "lower": null, "xoff": l.xoff, "yoff": l.yoff, "xscale": l.xscale, "yscale": l.yscale}
	var xs = o.get("xscale")
	var ys = o.get("yscale")
	return {"mid": o.get("midTex") if o.get("midTex") else null, "upper": o.get("upperTex") if o.get("upperTex") else null,
		"lower": o.get("lowerTex") if o.get("lowerTex") else null,
		"xoff": float(o.get("xoff", l.xoff)), "yoff": float(o.get("yoff", l.yoff)),
		"xscale": float(xs) if xs != null and float(xs) > 0 else l.xscale,
		"yscale": float(ys) if ys != null and float(ys) > 0 else l.yscale}

static func _none(t) -> bool:
	return t == null or str(t) == "" or str(t) == "NONE" or str(t) == "<null>"

## The floor's triangles, and the points they index.
func _flat_tris(s: Level.Sector) -> Array:
	if not s.flat_holes.is_empty():
		var pts := s.flat_outer.duplicate()
		for h in s.flat_holes:
			pts.append_array(h)
		return [pts, Earcut.triangulate(s.flat_outer, s.flat_holes)]
	var n := s.poly.size()
	if s.convex:
		var out := PackedInt32Array()
		for i in range(1, n - 1):
			out.append_array([0, i, i + 1])
		return [s.poly, out]
	var t := Geometry2D.triangulate_polygon(s.poly)
	if t.is_empty():
		t = Earcut.triangulate(s.poly, [])
	return [s.poly, t]

func _flats(s: Level.Sector) -> void:
	var ft := _flat_tris(s)
	var poly: PackedVector2Array = ft[0]
	var tris: PackedInt32Array = ft[1]
	var color := _light(s.light, s.sky)
	_fog = _fog_of(s)
	if s.floor_tex != "" and s.floor_tex != "SKY" and s.floor_tex != "NONE":
		_paint = _flat_paint(s, "floor")
		var b := _batch(s.floor_tex)
		var ts := bank.size_of(s.floor_tex)
		for i in range(0, tris.size(), 3):
			var p := [poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]]]
			b.tri(U.v3(p[0].x, p[0].y, s.floor), U.v3(p[2].x, p[2].y, s.floor), U.v3(p[1].x, p[1].y, s.floor),
				p[0] / ts, p[2] / ts, p[1] / ts, color)
	if s.ceil_tex != "" and s.ceil_tex != "SKY" and s.ceil_tex != "NONE":
		_paint = _flat_paint(s, "ceil")
		var b := _batch(s.ceil_tex)
		var ts := bank.size_of(s.ceil_tex)
		for i in range(0, tris.size(), 3):
			var p := [poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]]]
			b.tri(U.v3(p[0].x, p[0].y, s.ceil), U.v3(p[1].x, p[1].y, s.ceil), U.v3(p[2].x, p[2].y, s.ceil),
				p[0] / ts, p[1] / ts, p[2] / ts, color)
	# AND OVER IT A ROOF, Level.DECK thick (its edge is _roof_edge's): lit
	# as open sky, in the map's own air
	if s.roof_tex != "" and s.roof_tex != "NONE":
		var rz := s.ceil + Level.DECK
		_paint = null
		_fog = NO_FOG
		var b := _batch(s.roof_tex)
		var ts := bank.size_of(s.roof_tex)
		var rc := _light(minf(1.2, s.light), 1.0)
		for i in range(0, tris.size(), 3):
			var p := [poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]]]
			b.tri(U.v3(p[0].x, p[0].y, rz), U.v3(p[2].x, p[2].y, rz), U.v3(p[1].x, p[1].y, rz),
				p[0] / ts, p[2] / ts, p[1] / ts, rc)
	_paint = null
	_fog = NO_FOG

## THE EDGE OF A ROOF: the side of the slab (Level.DECK thick) over a
## roofed room, facing out of it wherever what is over the line on the
## other side is lower than the roof's top — the open air over the
## street (above the facade), another roof (from its top up; a lower
## building's roof looks up at the higher one's wall, which the lintel
## inside only faces into the room), or nothing at all. In the room's
## own outside skin, lit as its roof is.
func _roof_edge(lv: Level, l: Level.Line) -> void:
	for side in 2:
		var own := l.front if side == 0 else l.back
		if own == -1:
			continue
		var a := lv.top_of(lv.sectors[own])
		if a.roof_tex == "" or a.roof_tex == "NONE":
			continue
		var z0 := a.ceil
		var other := l.back if side == 0 else l.front
		if other != -1:
			var b := lv.top_of(lv.sectors[other])
			if b.col_base == a.col_base:
				continue
			if b.roof_tex != "" and b.roof_tex != "NONE":
				z0 = b.ceil + Level.DECK
			elif b.ceil_tex == "SKY" or b.ceil_tex == "NONE":
				z0 = maxf(z0, b.floor)
			else:
				continue
		var z1 := a.ceil + Level.DECK
		if z1 - z0 <= 1e-3:
			continue
		var tex = l.middle if l.exterior and not _none(l.middle) else (a.wall_tex if a.wall_tex != "" else a.roof_tex)
		if _none(tex):
			continue
		var sd := {"xoff": l.xoff, "yoff": l.yoff, "xscale": l.xscale, "yscale": l.yscale}
		_paint = null
		_fog = NO_FOG
		_quad(l, str(tex), z0, z1, side == 1, z1 + sd.yoff, minf(1.2, a.light) + l.contrast, 1.0, sd)

func _walls(lv: Level, l: Level.Line) -> void:
	if l.multi:
		_walls_columns(lv, l)
		return
	if l.back == -1 and l.front_col.size() > 1:
		# the outside of a house of storeys backing onto nothing: a storey
		# at a time, each in its own skin (the ground in the line's)
		for i in l.front_col.size():
			var st := lv.sectors[l.front_col[i]]
			var sd := _side(l, st)
			var tex = sd.mid if sd.mid != null else (l.middle if i == 0 else (st.wall_tex if st.wall_tex != "" else l.middle))
			if _none(tex):
				continue
			var th: float = bank.size_of(str(tex)).y * sd.yscale
			var peg: float = (st.floor + th if l.peg_middle == "bottom" else st.ceil) + sd.yoff
			_paint = _paint_wall(st)
			_fog = _fog_of(st)
			_quad(l, str(tex), st.floor, st.ceil, true, peg, st.light + l.contrast, st.sky, sd)
		_paint = null
		_fog = NO_FOG
		return
	if l.back == -1:
		var s := lv.sectors[l.front]
		var sd := _side(l, s)
		var tex = sd.mid if sd.mid != null else l.middle
		if _none(tex):
			return
		var th: float = bank.size_of(str(tex)).y * sd.yscale
		var peg: float = (s.floor + th if l.peg_middle == "bottom" else s.ceil) + sd.yoff
		_paint = _paint_wall(s)
		_fog = _fog_of(s)
		_quad(l, str(tex), s.floor, s.ceil, true, peg, s.light + l.contrast, s.sky, sd)
		_paint = null
		_fog = NO_FOG
		return
	var f := lv.sectors[l.front]
	var b := lv.sectors[l.back]
	# THE STEP, facing whichever side is lower
	if absf(f.floor - b.floor) > 1e-3 and not _none(l.lower):
		var lo_front := f.floor < b.floor
		var open := f if lo_front else b
		var z0 := minf(f.floor, b.floor)
		var z1 := maxf(f.floor, b.floor)
		var sd := _side(l, open)
		var tex = sd.lower if sd.lower != null else l.lower
		if not _none(tex):
			var th: float = bank.size_of(str(tex)).y * sd.yscale
			var peg: float = (open.ceil if l.peg_lower == "ceiling" else z1) + sd.yoff
			_paint = _paint_wall(open, z0, z1)
			_fog = _fog_of(open)
			_quad(l, str(tex), z0, z1, lo_front, peg, open.light + l.contrast, open.sky, sd)
	# THE LINTEL, facing whichever side is higher — unless both are sky,
	# or it rises from a roof towards the open sky (no sky walls)
	if absf(f.ceil - b.ceil) > 1e-3 and not (f.ceil_tex == "SKY" and b.ceil_tex == "SKY") and not _none(l.upper):
		var hi_front := f.ceil > b.ceil
		var open := f if hi_front else b
		var from := b if hi_front else f
		var z0 := minf(f.ceil, b.ceil)
		var z1 := maxf(f.ceil, b.ceil)
		var sd := _side(l, open)
		var tex = sd.upper if sd.upper != null else l.upper
		if not _none(tex):
			var th: float = bank.size_of(str(tex)).y * sd.yscale
			var peg: float = (z1 if l.peg_upper == "top" else z0 + th) + sd.yoff
			# THE GABLE FACES THE STREET: a band over outdoor ground is seen
			# from under the sky, and lit by it
			var gable := from.ceil_tex == "SKY"
			var lit := from if gable else open
			var facing := (not hi_front) if gable else hi_front
			_paint = _paint_wall(lit, z0, z1)
			_fog = _fog_of(lit)
			_quad(l, str(tex), z0, z1, facing, peg, lit.light + l.contrast, lit.sky, sd)
			if gable and open.ceil_tex != "" and open.ceil_tex != "NONE":
				_paint = _paint_wall(open, z0, z1)
				_fog = _fog_of(open)
				_quad(l, str(tex), z0, z1, not facing, peg, open.light + l.contrast, lit.sky, sd)
	_paint = null
	_fog = NO_FOG
	# A MIDDLE IN THE OPENING: the thing standing in the hole — a door, a
	# fence, a sign — drawn once at its own height on the floor, or the
	# building's outside wall filling it; each face its own side's
	var any_mid := not _none(l.middle)
	if not any_mid:
		for o in l.sides.values():
			if o is Dictionary and not _none(o.get("midTex")):
				any_mid = true
	if not any_mid:
		return
	var bot := maxf(f.floor, b.floor)
	var top := minf(f.ceil, b.ceil)
	if l.mid_height != null:
		top = minf(top, bot + float(l.mid_height))
	if top <= bot:
		return
	for fs in [[true, f], [false, b]]:
		var sec: Level.Sector = fs[1]
		var sd := _side(l, sec)
		var tex = sd.mid if sd.mid != null else l.middle
		if _none(tex):
			continue
		var th: float = bank.size_of(str(tex)).y * sd.yscale
		_fog = _fog_of(sec)
		if l.mid_once and l.mid_height == null:
			var peg: float = bot + th + sd.yoff
			var b0 := maxf(bot, peg - th)
			var b1 := minf(top, peg)
			if b1 <= b0:
				continue
			_paint = _paint_wall(sec, b0, b1)
			_quad(l, str(tex), b0, b1, fs[0], peg, sec.light + l.contrast, sec.sky, sd)
			continue
		var peg2: float = (bot + th if l.peg_middle == "bottom" else top) + sd.yoff
		_paint = _paint_wall(sec, bot, top)
		_quad(l, str(tex), bot, top, fs[0], peg2, sec.light + l.contrast, sec.sky, sd)
	_paint = null
	_fog = NO_FOG

## A two-sided line between columns: its bands, then a middle in each of
## its holes (the two-sided half of addLine in js/mapgeo.js).
func _walls_columns(lv: Level, l: Level.Line) -> void:
	for bd in l.bands:
		if _none(bd.tex):
			continue
		var open: Level.Sector = bd.open
		var from: Level.Sector = bd.from
		# a step between two patches of sky draws nothing
		if bd.kind == "upper" and open.ceil_tex == "SKY" and from.ceil_tex == "SKY":
			continue
		var sd := _side(l, open)
		var own = sd.upper if bd.kind == "upper" else sd.lower
		var tex = own if own != null else bd.tex
		if _none(tex):
			continue
		var th: float = bank.size_of(str(tex)).y * sd.yscale
		var z0: float = bd.z0
		var z1: float = bd.z1
		var peg: float
		if bd.kind == "upper":
			peg = (z1 if l.peg_upper == "top" else z0 + th) + sd.yoff
		else:
			peg = (open.ceil if l.peg_lower == "ceiling" else z1) + sd.yoff
		# THE GABLE FACES THE STREET: a band over outdoor ground is seen
		# from under the sky, and lit by it
		var gable: bool = bd.kind == "upper" and from.ceil_tex == "SKY"
		var lit := from if gable else open
		var facing: bool = (not bd.open_front) if gable else bd.open_front
		_paint = _paint_wall(lit, z0, z1)
		_fog = _fog_of(lit)
		_quad(l, str(tex), z0, z1, facing, peg, lit.light + l.contrast, lit.sky, sd)
		if gable and open.ceil_tex != "" and open.ceil_tex != "NONE":
			_paint = _paint_wall(open, z0, z1)
			_fog = _fog_of(open)
			_quad(l, str(tex), z0, z1, not facing, peg, open.light + l.contrast, lit.sky, sd)
	_paint = null
	_fog = NO_FOG
	var any_mid := not _none(l.middle)
	if not any_mid:
		for o in l.sides.values():
			if o is Dictionary and not _none(o.get("midTex")):
				any_mid = true
	if not any_mid:
		return
	for h in l.holes:
		# a wall in some of the openings only (mid_z)
		if not l.mid_z.is_empty():
			var hit := false
			for m in l.mid_z:
				if absf(m.x - h.z0) < 1.0 and absf(m.y - h.z1) < 1.0:
					hit = true
			if not hit:
				continue
		var bot: float = h.z0
		var top: float = h.z1
		if l.mid_height != null:
			top = minf(top, bot + float(l.mid_height))
		if top <= bot:
			continue
		for fs in [[true, h.front], [false, h.back]]:
			var sec: Level.Sector = fs[1]
			var sd := _side(l, sec)
			# a building's outside wall: each storey in its own room's walls
			var tex = sd.mid if sd.mid != null else h.get("wall", l.middle)
			if _none(tex):
				continue
			var th: float = bank.size_of(str(tex)).y * sd.yscale
			_fog = _fog_of(sec)
			if l.mid_once and l.mid_height == null:
				var peg: float = bot + th + sd.yoff
				var b0 := maxf(bot, peg - th)
				var b1 := minf(top, peg)
				if b1 <= b0:
					continue
				_paint = _paint_wall(sec, b0, b1)
				_quad(l, str(tex), b0, b1, fs[0], peg, sec.light + l.contrast, sec.sky, sd)
				continue
			var peg2: float = (bot + th if l.peg_middle == "bottom" else top) + sd.yoff
			_paint = _paint_wall(sec, bot, top)
			_quad(l, str(tex), bot, top, fs[0], peg2, sec.light + l.contrast, sec.sky, sd)
	_paint = null
	_fog = NO_FOG

func _quad(l: Level.Line, tex: String, z0: float, z1: float, facing_front: bool, peg: float, light: float, sky: float, sd: Dictionary) -> void:
	if z1 - z0 <= 1e-6 or _none(tex):
		return
	var ts := bank.size_of(tex)
	var tw: float = ts.x * sd.xscale
	var th: float = ts.y * sd.yscale
	var b := _batch(tex)
	var u0: float = sd.xoff / tw
	var u1: float = (sd.xoff + l.len) / tw
	var vt := (peg - z1) / th
	var vb := (peg - z0) / th
	var color := _light(light, sky)
	# a front side reads from v1, a back side from v2
	var a := Vector2(l.x1, l.y1) if facing_front else Vector2(l.x2, l.y2)
	var c := Vector2(l.x2, l.y2) if facing_front else Vector2(l.x1, l.y1)
	b.quad([U.v3(a.x, a.y, z1), U.v3(c.x, c.y, z1), U.v3(c.x, c.y, z0), U.v3(a.x, a.y, z0)],
		[Vector2(u0, vt), Vector2(u1, vt), Vector2(u1, vb), Vector2(u0, vb)], color)

## A BOX THAT BELONGS TO NO SECTOR (boxGeometry): four sides, walked
## counter-clockwise on the plan so each looks out, their texture hung
## from the top; and a lid, lit as a roof is. Coloured and fogged by the
## sector it stands in, if the map gave it them.
func _box(p: Dictionary) -> void:
	var x0: float = p.x0
	var y0: float = p.y0
	var x1: float = p.x1
	var y1: float = p.y1
	var z0: float = p.z0
	var z1: float = p.z1
	if x1 - x0 <= 0 or y1 - y0 <= 0 or z1 - z0 <= 0:
		return
	var lit := clampf(float(p.get("light", 0.5)), 0.02, 1.4)
	var sk := float(p.get("sky", 1.0))
	_paint = p.get("tint")
	_fog = p.fog if p.get("fog") != null else NO_FOG
	var tex := str(p.get("tex", ""))
	if not _none(tex):
		var t := bank.size_of(tex)
		var b := _batch(tex)
		var vb := (z1 - z0) / t.y
		var col := _light(lit, sk)
		for e in [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0]]:
			var u := Vector2(e[2] - e[0], e[3] - e[1]).length() / t.x
			b.quad([U.v3(e[0], e[1], z1), U.v3(e[2], e[3], z1), U.v3(e[2], e[3], z0), U.v3(e[0], e[1], z0)],
				[Vector2(0, 0), Vector2(u, 0), Vector2(u, vb), Vector2(0, vb)], col)
	var top := str(p.get("topTex", ""))
	if not _none(top):
		var t := bank.size_of(top)
		var b := _batch(top)
		var col := _light(clampf(lit * 1.12, 0.02, 1.4), sk)
		var q := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
		for tri in [[0, 2, 1], [0, 3, 2]]:
			var a: Vector2 = q[tri[0]]
			var bb: Vector2 = q[tri[1]]
			var c: Vector2 = q[tri[2]]
			b.tri(U.v3(a.x, a.y, z1), U.v3(bb.x, bb.y, z1), U.v3(c.x, c.y, z1), a / t, bb / t, c / t, col)
	_paint = null
	_fog = NO_FOG
