## MEWD Editor — the 3D view (js/editor/view3d.js).
##
## Ultimate Doom Builder's visual mode, on the game's own renderer: the
## level MapGeo builds from what the compiler made, in the game's own
## materials, under the map's sky. And not only a place to look: EVERY
## MODE WORKS HERE as it does on the plan — vertex handles to drag, walls
## and floors to pick, things and props and shapes and scatters to put
## down and drag, the outline being drawn shared with the plan.
##
## Hold the right button to look (WASD, Q and E fly while it is held,
## Shift faster), or press Q for VISUAL MODE: the 3D view on its own, the
## mouse always looking, a crosshair to pick with, WASD to fly, Space
## and C up and down; Q or Escape to come back. The wheel over a floor or
## a ceiling raises it (Alt: the other one), CTRL AND THE WHEEL ITS
## BRIGHTNESS; Ctrl+C over a surface copies its texture, Ctrl+V pastes;
## the arrows over a wall nudge its texture offsets; Shift+A aligns;
## B is fullbright, H the grid, F back to the start.
##
## PICKING IS DONE AGAINST THE DOCUMENT, not the triangles: a ray against
## every sector's two planes, every line's bands, the props and the
## things placed by hand.
class_name EdView3D
extends Control

const EYE := 41.0
const FLY := 600.0
const LOOK := 0.0028
const HANDLE_PX := 10.0
const PERSON_H := 62.0
const PEOPLE := ["SHOPPER", "TOWNIE"]
const AXIS_X := Color("#ff3352")
const AXIS_Y := Color("#8bdc00")
const AXIS_Z := Color("#4aa8ff")
const GRID_MODES := ["draw", "rect", "vertices", "things", "props", "scatter"]
const GIZMO := 84.0

var ed: MewdEditor
var svc: SubViewportContainer
var vp: SubViewport
var camera: Camera3D
var root3d: Node3D
var level_node: Node3D = null
var markers: Node3D
var sprites: Node3D
var edges: MeshInstance3D
var sel_lines: MeshInstance3D
var hov_lines: MeshInstance3D
var draw_lines: MeshInstance3D
var area_lines: MeshInstance3D
var handles: MeshInstance3D
var grid: MeshInstance3D
var axes: Node3D
var env: WorldEnvironment
var gizmo: Control
## the camera, in map space: {x, y, z, yaw, pitch}
var cam = null
var keys := {}
var looking := false
var visual := false
var hover = null
var drag = null
var mouse = null
var clip = null
var fullbright := false
var show_grid := true
var active := true
var _need_rebuild := true
var _hover_dirty := false
var _overlay_dirty := true
var _sky_key := ""
var _plant_tex := {}
var _person_tex: Texture2D
var _bb_shader: Shader
var _before_layout := ""
var snap_kind := "grid"

func _init(editor: MewdEditor) -> void:
	ed = editor
	name = "View3D"
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true

func _ready() -> void:
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(vp)
	root3d = Node3D.new()
	vp.add_child(root3d)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 2.0
	camera.far = 30000.0
	root3d.add_child(camera)
	camera.make_current()
	env = WorldEnvironment.new()
	root3d.add_child(env)
	markers = Node3D.new()
	sprites = Node3D.new()
	root3d.add_child(markers)
	root3d.add_child(sprites)
	edges = _lines_node(Color(0x8f / 255.0, 0xb3 / 255.0, 0xa0 / 255.0, 0.35), true, 0)
	area_lines = _lines_node(Color(200 / 255.0, 120 / 255.0, 1, 0.75), false, 20)
	sel_lines = _lines_node(Color("#ff9d3d"), false, 30)
	hov_lines = _lines_node(Color("#3ddc84"), false, 31)
	draw_lines = _lines_node(Color("#ffb454"), false, 32)
	handles = MeshInstance3D.new()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.vertex_color_use_as_albedo = true
	hm.no_depth_test = true
	hm.use_point_size = true
	hm.point_size = 7.0
	hm.render_priority = 40
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	handles.material_override = hm
	handles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(handles)
	grid = _build_grid()
	root3d.add_child(grid)
	axes = _build_axes()
	root3d.add_child(axes)
	_bb_shader = Shader.new()
	_bb_shader.code = BILLBOARD
	_person_tex = _person_texture()
	gizmo = Control.new()
	gizmo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gizmo.custom_minimum_size = Vector2(GIZMO, GIZMO)
	gizmo.size = Vector2(GIZMO, GIZMO)
	gizmo.draw.connect(_draw_gizmo)
	add_child(gizmo)
	resized.connect(func(): gizmo.position = Vector2(size.x - GIZMO - 8, 8))
	ed.compiled_ready.connect(func(): _need_rebuild = true)
	ed.sel_changed.connect(func(): draw_sel(); _overlay_dirty = true)
	ed.doc_changed.connect(func():
		_overlay_dirty = true
		if ed.sel_kind == "scatter":
			draw_sel())
	ed.path_changed.connect(func(): _overlay_dirty = true)
	ed.cursor_changed.connect(func(): _overlay_dirty = true)
	ed.mode_changed.connect(func(_m): _overlay_dirty = true)
	ed.frame_req.connect(func():
		if cam == null:
			to_start())
	mouse_entered.connect(func(): ed.pointer_view = "3d")
	mouse_exited.connect(func():
		if not looking and drag == null and not visual:
			hover = null
			mouse = null
			draw_hover()
			ed.set_hover(null))
	_reset_light()

## the world's light as the game starts it, so a game that ran before
## leaves nothing behind (weather.gd writes these every frame)
func _reset_light() -> void:
	var set := {"sky_light": 0.85, "global_light": 1.0, "light_falloff": 1400.0, "min_light": 0.12, "air_near": 1200.0, "air_far": 14000.0,
		"beam_level": 0.0, "thermal_view": Vector2.ZERO}
	for k in set:
		RenderingServer.global_shader_parameter_set(k, set[k])
	if fullbright:
		set_fullbright(true, false)

func set_active(on: bool) -> void:
	active = on
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

# ---------------------------------------------------------------------
# helpers: map space is (x east, y north, z up); Godot's is (x, z, -y)
# ---------------------------------------------------------------------

static func gv(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)

func _lines_node(c: Color, depth: bool, prio: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1 or not depth else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.no_depth_test = not depth
	mat.render_priority = prio
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 16384
	root3d.add_child(m)
	return m

## Line segments (pairs of map points) into a lines node.
static func set_lines(node: MeshInstance3D, pts: PackedVector3Array) -> void:
	var im: ImmediateMesh = node.mesh
	im.clear_surfaces()
	if pts.size() < 2:
		node.visible = false
		return
	node.visible = true
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in pts:
		im.surface_add_vertex(p)
	im.surface_end()

func z_of(s: Dictionary, part: String) -> float:
	return EdDoc.num(s.get("floor"), 0) if part == "floor" else EdDoc.num(s.get("ceil"), 256)

## The floor at (x, y), as the compiled level has it.
func floor_z(x: float, y: float) -> float:
	if ed.layer() != 0:
		return ed.layer_floor(x, y)
	var L = ed.compiled.get("level")
	if L != null:
		var s = L.sector_at(x, y)
		if s != null:
			return s.floor
	var ds = ed.sector_at(x, y)
	return EdDoc.num(ds.get("floor"), 0) if ds != null else 0.0

func thing_z(t: Dictionary) -> float:
	var k := int(EdDoc.num(t.get("layer"), 0))
	if k == ed.layer():
		return floor_z(t.x, t.y)
	var z = EdDoc.layer_floor_at(ed.doc, k, t.x, t.y)
	return z if z != null else floor_z(t.x, t.y)

static func thing_height(t: Dictionary) -> float:
	if t.type == "START":
		return 56.0
	if t.type == "PLANT":
		var k = EdScatter.plant_kind(str(t.get("kind", "")))
		return (float(k.h) if k != null else 60.0) * EdDoc.num(t.get("scale"), 1)
	if t.type in PEOPLE:
		return PERSON_H * EdDoc.num(t.get("scale"), 1)
	return float(EdDoc.THING_TYPES.get(t.type, {}).get("radius", 16)) * 2.6

## Whether a two-sided line is a building's outside wall (5c in doc.js).
static func exterior_wall(d: Dictionary, l) -> bool:
	if l == null or l.sectors.size() != 2 or d.lines.get(l.key, {}).get("opening", false):
		return false
	var a: Dictionary = d.sectors[l.sectors[0]]
	var b: Dictionary = d.sectors[l.sectors[1]]
	return (EdDoc.tex(a, "ceilTex") != "SKY") != (EdDoc.tex(b, "ceilTex") != "SKY")

static func mid_wall(d: Dictionary, l) -> bool:
	return exterior_wall(d, l) or EdDoc.tex(d.lines.get(l.key, {}), "midTex") != ""

# ---------------------------------------------------------------------
# VISUAL MODE
# ---------------------------------------------------------------------

func toggle_visual(on = null) -> void:
	var want: bool = (not visual) if on == null else bool(on)
	if want == visual:
		return
	visual = want
	if visual:
		_before_layout = ed.layout
		ed.pointer_view = "3d"
		if cam == null:
			to_start()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse = size / 2.0
		_hover_dirty = true
		ed.say("VISUAL MODE — mouse looks, WASD flies, Space/C up and down, click picks, wheel raises, Ctrl+wheel brightness; Q or Esc leaves")
	else:
		keys.clear()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		ed.say("left visual mode")
	ed.visual_changed.emit(visual)

func to_start() -> void:
	var t = null
	for q in ed.doc.things:
		if q.type == "START":
			t = q
			break
	if t == null:
		t = {"x": 0.0, "y": 0.0, "angle": 0.0, "type": "START"}
	cam = {"x": float(t.x), "y": float(t.y), "z": thing_z(t) + EYE, "yaw": EdDoc.num(t.get("angle"), 0), "pitch": -0.12}
	ed.camera_changed.emit()

func set_fullbright(on: bool, say := true) -> void:
	fullbright = on
	RenderingServer.global_shader_parameter_set("min_light", 1.0 if on else 0.12)
	RenderingServer.global_shader_parameter_set("light_falloff", 1e9 if on else 1400.0)
	RenderingServer.global_shader_parameter_set("global_light", 1.4 if on else 1.0)
	if say:
		ed.say("fullbright %s" % ("on" if on else "off"))

# ---------------------------------------------------------------------
# THE LEVEL, rebuilt from every compile
# ---------------------------------------------------------------------

func rebuild() -> void:
	_need_rebuild = false
	var lv = ed.compiled.get("level")
	if lv == null:
		return
	if level_node != null:
		level_node.queue_free()
		level_node = null
	var t0 := Time.get_ticks_msec()
	# built with the compile, in its thread, when the view was showing
	var geo = ed.compiled.get("geo")
	if geo != null and is_instance_valid(geo) and not geo.is_inside_tree():
		level_node = geo
	else:
		var mg := MapGeo.new(ed.bank)
		level_node = mg.build(lv)
		# the doors, shut (the game's Doors swings them)
		for dr in lv.doors:
			for nd in mg.door_nodes(lv, dr):
				if nd != null:
					level_node.add_child(nd)
	ed.compiled.erase("geo")
	root3d.add_child(level_node)
	var w: Dictionary = ed.doc.get("world", {})
	var key := JSON.stringify([w.get("sky"), w.get("skybox")])
	if key != _sky_key:
		_sky_key = key
		_make_sky(w)
	build_markers()
	build_sprites()
	build_edges()
	draw_sel()
	_overlay_dirty = true
	if cam == null:
		to_start()
	if Time.get_ticks_msec() - t0 > 300:
		print("MEWD Editor: 3D view built in %d ms" % (Time.get_ticks_msec() - t0))

## The map's sky: its skybox from the pack, or its painted colours.
func _make_sky(w: Dictionary) -> void:
	var e := Environment.new()
	var sky := Sky.new()
	var name := str(w.get("skybox", "")) if w.get("skybox") != null else ""
	var path := "res://assets/skies/%s.png" % name
	if name != "" and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://godot/shaders/skybox.gdshader")
		sm.set_shader_parameter("panorama", tex)
		sky.sky_material = sm
		RenderingServer.global_shader_parameter_set("air_sky", tex)
		RenderingServer.global_shader_parameter_set("air_sky_on", 1.0)
	else:
		var skin: Dictionary = {"horizon": "#1d9a48", "mid": "#06301a", "zenith": "#000000", "ground": "#05180c"}
		if w.get("sky") is Dictionary:
			skin.merge(w.sky, true)
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = PAINTED_SKY
		sm.shader = sh
		for k in ["horizon", "mid", "zenith", "ground"]:
			sm.set_shader_parameter(k, EdDoc.col(skin[k], Color.BLACK))
		sky.sky_material = sm
		RenderingServer.global_shader_parameter_set("air_sky_on", 0.0)
		RenderingServer.global_shader_parameter_set("air_color", EdDoc.col(skin.horizon, Color.GRAY).srgb_to_linear())
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e

## The things that are not sprites — the start, the furniture — as posts
## in their colours with a pointer for facing.
func build_markers() -> void:
	for c in markers.get_children():
		c.queue_free()
	var list := []
	for t in ed.doc.things:
		if t.type != "PLANT" and not (t.type in PEOPLE):
			list.append([t, false])
	for t in ed.compiled.get("scattered", []):
		if t.type != "PLANT" and not (t.type in PEOPLE):
			list.append([t, true])
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	mm.mesh = cyl
	mm.instance_count = list.size()
	var arrows := PackedVector3Array()
	for i in list.size():
		var t: Dictionary = list[i][0]
		var grown: bool = list[i][1]
		var def: Dictionary = EdDoc.THING_TYPES.get(t.type, {"color": "#f0f", "radius": 16})
		var z := thing_z(t)
		var hgt := thing_height(t)
		var r: float = def.radius * 0.6
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, hgt, r)), gv(t.x, t.y, z + hgt / 2.0)))
		var c := EdDoc.col(def.color)
		if grown:
			c = c * 0.75
		c.a = 0.85
		mm.set_instance_color(i, c)
		if not grown:
			var a := EdDoc.num(t.get("angle"), 0)
			var top := z + hgt + 2
			var L := maxf(24.0, def.radius * 1.8)
			arrows.append(gv(t.x, t.y, top))
			arrows.append(gv(t.x + cos(a) * L, t.y + sin(a) * L, top))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	markers.add_child(mi)
	var al := MeshInstance3D.new()
	al.mesh = ImmediateMesh.new()
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color("#ffe08a")
	al.material_override = am
	markers.add_child(al)
	set_lines(al, arrows)

## THE SPRITES: every plant and every person, placed or grown, as a
## billboard on the floor — one instanced draw per picture. The batches
## (a MultiMesh buffer each: where, how big, how lit) are worked out
## with the compile, in its thread (sprite_batches); here they are only
## handed to the server.
func build_sprites() -> void:
	for c in sprites.get_children():
		c.queue_free()
	var batches = ed.compiled.get("sprites")
	if batches == null or ed.layer() != 0:
		var all: Array = ed.doc.things + ed.compiled.get("scattered", [])
		batches = sprite_batches(all, ed.compiled.get("level"), ed.layer(), ed.doc)
	for key in batches:
		var b: Dictionary = batches[key]
		var parts: PackedStringArray = key.split(":")
		var tex: Texture2D = _plant_texture(parts[1]) if parts[0] == "plant" else _person_tex
		if tex == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.center_offset = Vector3(0, 0.5, 0)
		mm.mesh = q
		mm.instance_count = b.count
		mm.buffer = b.buf
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = _bb_shader
		mat.set_shader_parameter("tex", tex)
		mi.material_override = mat
		mi.extra_cull_margin = 16384
		sprites.add_child(mi)

## The billboards' batches by picture: {"plant:fir_tall_1": {buf, count}}
## — 16 floats an instance, a MultiMesh's own layout (its transform, a
## scale on the floor under it, and its colour: the type's, times the
## light of the sector it stands in).
static func sprite_batches(things: Array, L, layer_k: int, d: Dictionary) -> Dictionary:
	var by := {}
	for t in things:
		var key := ""
		var k = null
		if t.type == "PLANT":
			k = EdScatter.plant_kind(str(t.get("kind", "")))
			if k == null:
				continue
			key = "plant:" + str(t.kind)
		elif t.type in PEOPLE:
			key = "person:" + str(t.type)
		else:
			continue
		if not by.has(key):
			var w := 0.0
			var h := 0.0
			var tint := Color.WHITE
			if k != null:
				h = k.h
				w = k.h * k.aspect
			else:
				h = PERSON_H
				w = PERSON_H * 0.45
				tint = EdDoc.col(EdDoc.THING_TYPES.get(str(t.type), {}).get("color", "#fff"))
			by[key] = {"buf": PackedFloat32Array(), "count": 0, "w": w, "h": h, "tint": tint}
		var b: Dictionary = by[key]
		var s := EdDoc.num(t.get("scale"), 1)
		var x := float(t.x)
		var y := float(t.y)
		var fz := 0.0
		var light := 1.0
		# on the floor of ITS OWN layer's room (a map in storeys), lit by
		# the storey of the build it stands in
		var tk := int(EdDoc.num(t.get("layer"), 0))
		if tk != 0:
			fz = EdDoc.num(EdDoc.layer_floor_at(d, tk, x, y), 0)
		if L != null:
			var sec = L.sector_at(x, y)
			if sec != null:
				if tk != 0:
					sec = L.span_in(sec, fz + 1.0)
				else:
					fz = sec.floor
				light = clampf(sec.light, 0.15, 1.0)
		var c: Color = b.tint
		b.buf.append_array([b.w * s, 0, 0, x, 0, b.h * s, 0, fz, 0, 0, 1, -y, c.r * light, c.g * light, c.b * light, 1.0])
		b.count += 1
	return by

func _plant_texture(name: String) -> Texture2D:
	if not _plant_tex.has(name):
		var p := "res://assets/forest/%s.png" % name
		_plant_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _plant_tex[name]

## A figure for the people: head, shoulders and legs in white, tinted.
func _person_texture() -> Texture2D:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 64:
		for x in 32:
			var on := false
			if (x - 16) * (x - 16) + (y - 9) * (y - 9) <= 36:
				on = true
			if x >= 8 and x < 24 and y >= 16 and y < 40:
				on = true
			if ((x >= 4 and x < 8) or (x >= 24 and x < 28)) and y >= 18 and y < 36:
				on = true
			if ((x >= 9 and x < 15) or (x >= 17 and x < 23)) and y >= 40:
				on = true
			if on:
				img.set_pixel(x, y, Color(0.6, 0.6, 0.6) if (x >= 8 and x < 24 and y >= 36 and y < 40) else Color.WHITE)
	return ImageTexture.create_from_image(img)

## EVERY EDGE IN THE MAP, faintly: along every floor, along a ceiling
## that is not the sky, and up a corner as far as a wall stands.
func build_edges() -> void:
	var d := ed.doc
	var pts := PackedVector3Array()
	var seg := func(a: Vector2, za: float, b: Vector2, zb: float) -> void:
		pts.append(gv(a.x, a.y, za))
		pts.append(gv(b.x, b.y, zb))
	var sky_walls: bool = d.world.get("skyWalls", false)
	for l in ed.lines():
		var a: Vector2 = d.vertices[l.a]
		var b: Vector2 = d.vertices[l.b]
		var ss: Array = l.sectors.map(func(i): return d.sectors[i])
		for s in ss:
			seg.call(a, z_of(s, "floor"), b, z_of(s, "floor"))
			if EdDoc.tex(s, "ceilTex") != "SKY" or ss.size() == 1:
				seg.call(a, z_of(s, "ceil"), b, z_of(s, "ceil"))
		if ss.is_empty():
			continue
		for v in [a, b]:
			var fl: Array = ss.map(func(s): return z_of(s, "floor"))
			var ce: Array = ss.map(func(s): return z_of(s, "ceil"))
			if ss.size() == 1:
				seg.call(v, fl[0], v, ce[0])
				continue
			if fl.max() > fl.min():
				seg.call(v, fl.min(), v, fl.max())
			var any_in := false
			var all_roofed := true
			for s in ss:
				if s.get("outdoor") == false:
					any_in = true
				if EdDoc.tex(s, "ceilTex") == "SKY":
					all_roofed = false
			if any_in and (sky_walls or all_roofed) and ce.max() > ce.min():
				seg.call(v, ce.min(), v, ce.max())
		if ss.size() == 2 and exterior_wall(d, l):
			var top := minf(z_of(ss[0], "ceil"), z_of(ss[1], "ceil"))
			var bot := maxf(z_of(ss[0], "floor"), z_of(ss[1], "floor"))
			seg.call(a, top, b, top)
			for v in [a, b]:
				seg.call(v, bot, v, top)
	for p in d.props:
		_box(pts, p.x0, p.y0, p.z0, p.x1, p.y1, p.z1)
	set_lines(edges, pts)

static func _box(P: PackedVector3Array, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
	var c := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	for i in 4:
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % 4]
		P.append(gv(a.x, a.y, z0)); P.append(gv(b.x, b.y, z0))
		P.append(gv(a.x, a.y, z1)); P.append(gv(b.x, b.y, z1))
		P.append(gv(a.x, a.y, z0)); P.append(gv(a.x, a.y, z1))

static func _cross(P: PackedVector3Array, x: float, y: float, z: float, s: float) -> void:
	P.append(gv(x - s, y, z)); P.append(gv(x + s, y, z))
	P.append(gv(x, y - s, z)); P.append(gv(x, y + s, z))
	P.append(gv(x, y, z)); P.append(gv(x, y, z + s * 1.5))

func _ring(P: PackedVector3Array, x: float, y: float, r: float, lift := 1.0) -> void:
	var n := clampi(roundi(r / 24.0), 24, 96)
	for i in n:
		var a0 := i * TAU / n
		var a1 := (i + 1) * TAU / n
		var p := Vector2(x + cos(a0) * r, y + sin(a0) * r)
		var q := Vector2(x + cos(a1) * r, y + sin(a1) * r)
		P.append(gv(p.x, p.y, floor_z(p.x, p.y) + lift))
		P.append(gv(q.x, q.y, floor_z(q.x, q.y) + lift))

# ---------------------------------------------------------------------
# PICKING
# ---------------------------------------------------------------------

## The ray under a pixel, in map space: {o: Vector3(x, y, z), d}.
func ray(px: Vector2) -> Dictionary:
	var o := camera.project_ray_origin(px)
	var v := camera.project_ray_normal(px)
	return {"o": Vector3(o.x, -o.z, o.y), "d": Vector3(v.x, -v.z, v.y)}

func on_plane(R: Dictionary, z: float):
	if absf(R.d.z) < 1e-6:
		return null
	var t: float = (z - R.o.z) / R.d.z
	if not (t > 0) or t > 40000:
		return null
	return Vector3(R.o.x + R.d.x * t, R.o.y + R.d.y * t, z)

## THE FLOOR UNDER THE MOUSE: the floor the ray hits first, or the plane
## at the height of the floor under the camera.
func ground(R: Dictionary, hit):
	if hit != null and hit.kind == "surface" and hit.part == "floor":
		return Vector3(hit.x, hit.y, R.o.z + R.d.z * hit.t)
	return on_plane(R, floor_z(cam.x, cam.y) if cam != null else 0.0)

func snap_ground(g, px: Vector2):
	if g == null:
		return null
	var v = nearest_handle(px)
	if v != null:
		snap_kind = "vertex"
		return ed.doc.vertices[v]
	var s := ed.snap_at(g.x, g.y, px_to_map(g, HANDLE_PX), null, true, false)
	snap_kind = s.kind
	return s.pt

func px_to_map(g: Vector3, n: float) -> float:
	var c := camera.global_position
	var dist := c.distance_to(gv(g.x, g.y, g.z))
	return dist * 2.0 * tan(deg_to_rad(camera.fov) / 2.0) / maxf(1.0, size.y) * n

func to_screen(x: float, y: float, z: float):
	var p := gv(x, y, z)
	if camera.is_position_behind(p):
		return null
	return camera.unproject_position(p)

func nearest_handle(px: Vector2):
	var d := ed.doc
	var best = null
	var bd := HANDLE_PX * HANDLE_PX
	for i in d.vertices.size():
		var v: Vector2 = d.vertices[i]
		var s = to_screen(v.x, v.y, floor_z(v.x, v.y))
		if s == null:
			continue
		var q: float = (s - px).length_squared()
		if q < bd:
			bd = q
			best = i
	return best

static func _slab(R: Dictionary, lo: Vector3, hi: Vector3):
	var t0 := 0.0
	var t1 := INF
	for ax in 3:
		var o: float = R.o[ax]
		var dv: float = R.d[ax]
		if absf(dv) < 1e-12:
			if o < lo[ax] or o > hi[ax]:
				return null
			continue
		var a := (lo[ax] - o) / dv
		var b := (hi[ax] - o) / dv
		if a > b:
			var tmp := a
			a = b
			b = tmp
		t0 = maxf(t0, a)
		t1 = minf(t1, b)
		if t0 > t1:
			return null
	return t0 if t0 > 0 else null

## What the ray hits first: {t, kind: surface|thing|prop, part, sector,
## line, band, id, x, y, z}.
func pick(R: Dictionary):
	var d := ed.doc
	# a holder: a lambda sees its outer locals by value
	var best := [null]
	var take := func(h: Dictionary) -> void:
		if h.t > 0.5 and (best[0] == null or h.t < best[0].t):
			best[0] = h
	# floors and ceilings: every sector's two planes
	for si in d.sectors.size():
		var s: Dictionary = d.sectors[si]
		var r := EdDoc.ring_of(d, s)
		if r.size() < 3:
			continue
		for part in ["floor", "ceil"]:
			if part == "ceil" and EdDoc.tex(s, "ceilTex") == "SKY":
				continue
			var z0 := z_of(s, part)
			var den: float = R.d.z
			if (den >= -1e-6) if part == "floor" else (den <= 1e-6):
				continue
			var t: float = (z0 - R.o.z) / den
			if not (t > 0):
				continue
			var x: float = R.o.x + R.d.x * t
			var y: float = R.o.y + R.d.y * t
			if not EdDoc.pip(r, x, y):
				continue
			if not is_same(ed.sector_at(x, y), s):
				continue
			take.call({"t": t, "kind": "surface", "part": part, "sector": si, "x": x, "y": y})
	# the walls: every line, and which band of it the hit is in
	for l in ed.lines():
		var a: Vector2 = d.vertices[l.a]
		var b: Vector2 = d.vertices[l.b]
		var ex := b.x - a.x
		var ey := b.y - a.y
		var den: float = R.d.x * ey - R.d.y * ex
		if absf(den) < 1e-9:
			continue
		var qx: float = a.x - R.o.x
		var qy: float = a.y - R.o.y
		var t: float = (qx * ey - qy * ex) / den
		var u: float = (qx * R.d.y - qy * R.d.x) / den
		if not (t > 0) or u < 0 or u > 1:
			continue
		var x: float = R.o.x + R.d.x * t
		var y: float = R.o.y + R.d.y * t
		var z: float = R.o.z + R.d.z * t
		if l.sectors.is_empty():
			continue
		var ss: Array = l.sectors.map(func(i): return d.sectors[i])
		var fl: Array = ss.map(func(s): return z_of(s, "floor"))
		var ce: Array = ss.map(func(s): return z_of(s, "ceil"))
		var side: float = ex * (R.o.y - a.y) - ey * (R.o.x - a.x)
		var front: int = l.sectors[0]
		if ss.size() > 1:
			var m := (a + b) / 2.0
			var L := a.distance_to(b)
			var n := Vector2(-ey / L * signf(side) * 2, ex / L * signf(side) * 2)
			var on = ed.sector_at(m.x + n.x, m.y + n.y)
			for k in l.sectors.size():
				if is_same(d.sectors[l.sectors[k]], on):
					front = l.sectors[k]
		var h := {"t": t, "kind": "surface", "part": "wall", "line": l.key, "sector": front, "x": x, "y": y, "z": z}
		if ss.size() == 1:
			if z >= fl[0] and z <= ce[0]:
				h.band = "middle"
				take.call(h)
		else:
			var f_lo: float = fl.min()
			var f_hi: float = fl.max()
			var c_lo: float = ce.min()
			var c_hi: float = ce.max()
			var any_sky := false
			for q in ss:
				if EdDoc.tex(q, "ceilTex") == "SKY":
					any_sky = true
			if z >= f_lo and z <= f_hi and f_hi > f_lo:
				h.band = "lower"
				take.call(h)
			elif z >= c_lo and z <= c_hi and c_hi > c_lo and not any_sky:
				h.band = "upper"
				take.call(h)
			elif z > f_hi and z < c_lo and mid_wall(d, l):
				h.band = "middle"
				take.call(h)
	for p in d.props:
		var t = _slab(R, Vector3(minf(p.x0, p.x1), minf(p.y0, p.y1), minf(p.z0, p.z1)), Vector3(maxf(p.x0, p.x1), maxf(p.y0, p.y1), maxf(p.z0, p.z1)))
		if t != null:
			take.call({"t": t, "kind": "prop", "id": p.id})
	for th in d.things:
		if not ed.on_layer(th):
			continue
		var rad := maxf(8.0, float(EdDoc.THING_TYPES.get(th.type, {}).get("radius", 16)) * 0.6)
		var z := thing_z(th)
		var t = _slab(R, Vector3(th.x - rad, th.y - rad, z), Vector3(th.x + rad, th.y + rad, z + thing_height(th)))
		if t != null:
			take.call({"t": t, "kind": "thing", "id": th.id})
	return best[0]

# ---------------------------------------------------------------------
# THE MOUSE — every mode, as on the plan
# ---------------------------------------------------------------------

func _at(pos: Vector2) -> Vector2:
	return size / 2.0 if visual else pos

func _input(event: InputEvent) -> void:
	# looking and visual mode take the mouse wherever it is
	if not (looking or visual) or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var e: InputEventMouseMotion = event
		if cam != null:
			cam.yaw -= e.relative.x * LOOK
			cam.pitch = clampf(cam.pitch - e.relative.y * LOOK, -1.5, 1.5)
			ed.camera_changed.emit()
			if visual:
				mouse = size / 2.0
				_hover_dirty = true
				if drag != null:
					_drag_to(mouse)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if looking and e.button_index == MOUSE_BUTTON_RIGHT and not e.pressed:
			stop_look()
			get_viewport().set_input_as_handled()
		elif visual and not looking:
			if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				if e.pressed:
					_wheel(e)
			elif e.pressed:
				_down(e)
			else:
				_up(e)
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if visual or looking:
		return
	if event is InputEventMouseButton:
		var e: InputEventMouseButton = event
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if e.pressed:
				_wheel(e)
		elif e.pressed and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			_dbl()
		elif e.pressed:
			_down(e)
		else:
			_up(e)
		accept_event()
	elif event is InputEventMouseMotion:
		var e: InputEventMouseMotion = event
		mouse = e.position
		if drag != null and cam != null:
			_drag_to(e.position)
		else:
			_hover_dirty = true
		accept_event()

func _dbl() -> void:
	if ed.mode == "draw":
		ed.close_path(true)
		return
	if ed.mode == "things" and mouse != null and cam != null:
		var R := ray(mouse)
		var h = pick(R)
		if h == null or h.kind != "thing":
			var g = ground(R, h)
			if g != null:
				ed.add_thing(g.x, g.y)
			return
	# A DOUBLE-CLICK ON A WALL: every wall of the room it faces
	if ed.surf != null and ed.surf.part == "wall":
		ed.loop_select(int(ed.surf.sector))
	if ed.sel_kind != "" and ed.ui != null:
		ed.ui.panels.show_tab("insp")

func _down(e: InputEventMouseButton) -> void:
	grab_focus()
	ed.pointer_view = "3d"
	if e.button_index == MOUSE_BUTTON_RIGHT and ed.mode == "draw" and not ed.path.is_empty():
		ed.close_path(true)
		return
	if e.button_index == MOUSE_BUTTON_RIGHT and not visual:
		looking = true
		keys.clear()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if e.button_index != MOUSE_BUTTON_LEFT or cam == null:
		return
	var mode := ed.mode
	var px := _at(e.position)
	var R := ray(px)
	var hit = pick(R)
	var g = ground(R, hit)
	var sg = snap_ground(g, px)
	var grab := func(kind: String, id, z: float, at: Vector2) -> void:
		if e.shift_pressed or e.ctrl_pressed:
			ed.select(kind, [id], true)
			return
		if not ed.is_sel(kind, id):
			ed.select(kind, [id])
		drag = {"type": "move", "z": z, "mv": ed.begin_move(ed.grab_point(at), at), "px": px, "moved": false}
	if mode == "draw":
		if sg != null:
			ed.add_path_point(sg)
		return
	if mode == "rect":
		if sg != null:
			drag = {"type": "rect", "z": g.z, "a": sg, "b": sg}
		return
	if mode == "vertices" and not visual:
		var v = nearest_handle(px)
		if v == null:
			if not e.shift_pressed:
				ed.clear_sel()
			return
		var p: Vector2 = ed.doc.vertices[v]
		grab.call("vertex", v, floor_z(p.x, p.y), p)
		return
	if mode == "things":
		if hit != null and hit.kind == "thing":
			for t in ed.doc.things:
				if t.id == hit.id:
					grab.call("thing", hit.id, thing_z(t), Vector2(t.x, t.y))
					break
			return
		if not e.shift_pressed:
			ed.clear_sel()
		return
	if mode == "props":
		if hit != null and hit.kind == "prop":
			for p in ed.doc.props:
				if p.id == hit.id:
					var at = on_plane(R, p.z0)
					grab.call("prop", hit.id, p.z0, Vector2(at.x, at.y) if at != null else Vector2(p.x0, p.y0))
					break
			return
		if g != null:
			var a := ed.snap_pt(Vector2(g.x, g.y))
			drag = {"type": "prop", "z": g.z, "a": a, "b": a}
		return
	if mode == "scatter":
		var c = EdScatter.scatter_at(ed.doc, g.x, g.y) if g != null and not e.alt_pressed else null
		if c != null:
			grab.call("scatter", c.id, g.z, Vector2(g.x, g.y))
			return
		if g != null:
			var a := ed.snap_pt(Vector2(g.x, g.y))
			drag = {"type": "brush", "z": g.z, "a": a, "b": a}
		return
	# sectors and lines: a surface is picked, then dragged
	if hit == null:
		ed.clear_sel()
		return
	if hit.kind == "thing":
		ed.set_mode("things")
		ed.select("thing", [hit.id])
		return
	if hit.kind == "prop":
		ed.set_mode("props")
		ed.select("prop", [hit.id])
		return
	if hit.part == "wall" and mode == "doors":
		if e.shift_pressed:
			ed.remove_door(hit.line)
		else:
			ed.place_door(hit.line, Vector2(hit.x, hit.y))
		return
	if hit.part == "wall":
		# ALT-CLICK A WALL: every wall of the room it faces
		if e.alt_pressed:
			ed.loop_select(hit.sector, e.shift_pressed)
			return
		if e.shift_pressed and ed.sel_kind == "line":
			ed.select("line", [hit.line], true)
			return
		if not ed.is_sel("line", hit.line):
			ed.select_surface({"sector": hit.sector, "part": "wall", "line": hit.line, "band": hit.band})
		if mode == "lines":
			var z := floor_z(hit.x, hit.y)
			var at = on_plane(R, z)
			var p2 := Vector2(at.x, at.y) if at != null else Vector2(hit.x, hit.y)
			drag = {"type": "move", "z": z, "mv": ed.begin_move(ed.grab_point(p2), p2), "px": px, "moved": false}
		return
	var s: Dictionary = ed.doc.sectors[hit.sector]
	if mode == "sectors" and hit.part == "floor" and not e.alt_pressed and not e.shift_pressed and ed.is_ground(s.id) and sg != null:
		drag = {"type": "rect", "z": g.z, "a": sg, "b": sg, "ground": s.id, "hit": hit, "px": px}
		return
	if e.shift_pressed and ed.sel_kind == "sector":
		ed.select("sector", [s.id], true)
		ed.surf = {"sector": hit.sector, "part": hit.part}
		ed.sel_changed.emit()
		return
	if not ed.is_sel("sector", s.id) or ed.surf == null or ed.surf.part != hit.part:
		var keep = ed.sel_ids.duplicate() if ed.is_sel("sector", s.id) else null
		ed.select_surface({"sector": hit.sector, "part": hit.part})
		if keep != null and keep.size() > 1:
			ed.sel_ids = keep
			ed.sel_changed.emit()
	var z: float = R.o.z + R.d.z * hit.t
	var hp := Vector2(hit.x, hit.y)
	drag = {"type": "move", "z": z, "mv": ed.begin_move(ed.grab_point(hp), hp), "px": px, "moved": false}

func _drag_to(pos: Vector2) -> void:
	var dr = drag
	var px := _at(pos)
	var p = on_plane(ray(px), dr.z)
	if p == null:
		return
	if dr.type == "move":
		if not dr.moved and px.distance_to(dr.px) < 4 and not visual:
			return
		dr.moved = true
		ed.drag_move(dr.mv, Vector2(p.x, p.y), px_to_map(p, HANDLE_PX))
	else:
		if dr.type == "rect":
			var s = snap_ground(p, px)
			if s != null:
				dr.b = s
		else:
			dr.b = ed.snap_pt(Vector2(p.x, p.y))
		_overlay_dirty = true

func _up(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_RIGHT and looking:
		stop_look()
		return
	if e.button_index != MOUSE_BUTTON_LEFT:
		return
	var dr = drag
	drag = null
	if dr == null:
		return
	match dr.type:
		"move":
			ed.end_move(dr.mv)
		"rect":
			var q := _at(e.position)
			if dr.get("ground") != null and q.distance_to(dr.px) < 4:
				ed.select_surface({"sector": dr.hit.sector, "part": dr.hit.part})
				ed.say("the ground — drag on it to draw a new sector; Alt-drag moves it")
			else:
				ed.add_rect(dr.a, dr.b)
		"prop":
			ed.add_prop(dr.a.x, dr.a.y, dr.b.x, dr.b.y)
		"brush":
			ed.paint_brush(dr.a, dr.b)
	_overlay_dirty = true

func stop_look() -> void:
	looking = false
	keys.clear()
	if not visual:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _wheel(e: InputEventMouseButton) -> void:
	var h = hover
	var up := e.button_index == MOUSE_BUTTON_WHEEL_UP
	if e.ctrl_pressed or e.meta_pressed:
		var s = null
		if h != null and h.kind == "surface":
			s = ed.doc.sectors[h.sector]
		elif h != null and h.kind == "thing":
			for t in ed.doc.things:
				if t.id == h.id:
					s = ed.sector_at(t.x, t.y)
		elif h != null and h.kind == "prop":
			for p in ed.doc.props:
				if p.id == h.id:
					s = ed.sector_at((p.x0 + p.x1) / 2.0, (p.y0 + p.y1) / 2.0)
		if s == null:
			return
		var ids: Dictionary = ed.sel_ids if ed.sel_kind == "sector" and ed.sel_ids.has(s.id) else {s.id: true}
		ed.nudge_light((1 if e.shift_pressed else 16) * (1 if up else -1), ids)
		return
	var step := (1.0 if e.shift_pressed else 8.0) * (1.0 if up else -1.0)
	if h != null and h.kind == "surface" and h.part != "wall":
		var s: Dictionary = ed.doc.sectors[h.sector]
		var ids: Dictionary = ed.sel_ids if ed.sel_kind == "sector" and ed.sel_ids.has(s.id) else {s.id: true}
		var part: String = ("ceil" if h.part == "floor" else "floor") if e.alt_pressed else h.part
		ed.nudge_height(part, step, ids)
		var s2: Dictionary = ed.doc.sectors[h.sector] if h.sector < ed.doc.sectors.size() else s
		ed.say("%s %s%s → %s" % [part, "+" if step > 0 else "", MewdEditor._nice(step), EdUI.coord(EdDoc.num(s2.get(part), 0))])
		_hover_dirty = true
		return
	if h != null and h.kind == "surface" and h.part == "wall":
		var s: Dictionary = ed.doc.sectors[h.sector]
		ed.nudge_height("floor" if h.band == "lower" else "ceil", step, {s.id: true})
		return
	if h != null and h.kind == "prop":
		var id = h.id
		var d := ed.edit_begin("prop %s" % ("up" if step > 0 else "down"))
		for p in d.props:
			if p.id == id:
				var z := ed.snap_z(p.z0, step)
				p.z1 += z - p.z0
				p.z0 = z
		ed.edit_end(false)
		return
	if h != null and h.kind == "thing":
		ed.say("things stand on the floor: raise the floor under it, or Ctrl+wheel for its light")
		return
	if cam != null:
		var f := (1.0 if up else -1.0) * 64.0
		cam.x += cos(cam.yaw) * cos(cam.pitch) * f
		cam.y += sin(cam.yaw) * cos(cam.pitch) * f
		cam.z += sin(cam.pitch) * f
		ed.camera_changed.emit()

## Keys the 3D view takes first.
func key(e: InputEventKey) -> bool:
	var c := e.physical_keycode if e.physical_keycode != 0 else e.keycode
	var ctrl := e.ctrl_pressed or e.meta_pressed
	if looking and c in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_SHIFT]:
		keys[c] = true
		return c != KEY_SHIFT
	if visual and c in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_C, KEY_E, KEY_SHIFT] and not ctrl:
		keys[c] = true
		return c != KEY_SHIFT
	if visual and e.keycode == KEY_ESCAPE:
		toggle_visual(false)
		return true
	if c == KEY_F and not ctrl:
		to_start()
		return true
	if c == KEY_H and not ctrl:
		show_grid = not show_grid
		ed.say("3D grid and axes %s" % ("on" if show_grid else "off"))
		return true
	var h = hover
	if ctrl and c == KEY_C and h != null and h.kind == "surface":
		clip = texture_of(h)
		ed.say("copied %s" % clip)
		if ed.ui != null:
			ed.ui.show_toast("copied %s" % clip)
		return true
	if ctrl and c == KEY_V and h != null and h.kind == "surface" and clip != null:
		var was = ed.surf
		ed.surf = {"sector": h.sector, "part": h.part, "line": h.get("line"), "band": h.get("band")}
		ed.apply_texture(clip)
		ed.surf = was
		ed.say("pasted %s" % clip)
		return true
	var arrows := {KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_UP: Vector2(0, -1), KEY_DOWN: Vector2(0, 1)}
	if arrows.has(e.keycode) and h != null and h.kind == "surface" and h.part == "wall" and not ctrl:
		var dv: Vector2 = arrows[e.keycode] * (8.0 if e.shift_pressed else 1.0)
		var face_id := str(ed.doc.sectors[h.sector].id)
		var line: String = h.line
		var d := ed.edit_begin("texture offset", "offset %s %s" % [line, face_id])
		if not d.lines.has(line):
			d.lines[line] = {}
		var o: Dictionary = d.lines[line]
		if not o.get("sides") is Dictionary:
			o["sides"] = {}
		if not o.sides.get(face_id) is Dictionary:
			o.sides[face_id] = {}
		var sd: Dictionary = o.sides[face_id]
		sd["xoff"] = EdDoc.num(EdDoc.got(sd, "xoff", o.get("xoff", 0)), 0) + dv.x
		sd["yoff"] = EdDoc.num(EdDoc.got(sd, "yoff", o.get("yoff", 0)), 0) + dv.y
		ed.edit_end(false)
		ed.say("offset %s, %s on the side facing sector %s" % [EdUI.coord(sd.xoff), EdUI.coord(sd.yoff), face_id])
		return true
	return false

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed:
		var c: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		keys.erase(c)

func texture_of(h: Dictionary) -> String:
	var d := ed.doc
	var s: Dictionary = d.sectors[h.sector]
	if h.part == "floor":
		return EdDoc.tex(s, "floorTex") if EdDoc.tex(s, "floorTex") != "" else EdDoc.DEFAULT_FLOOR
	if h.part == "ceil":
		return EdDoc.tex(s, "ceilTex") if EdDoc.tex(s, "ceilTex") != "" else "SKY"
	var o: Dictionary = d.lines.get(h.line, {})
	var sides: Dictionary = o.get("sides", {}) if o.get("sides") is Dictionary else {}
	var side: Dictionary = sides.get(str(s.id), {})
	var first := func(a: Array) -> String:
		for v in a:
			if v != "":
				return v
		return "GRIDWALL"
	# the face's SKIN first, then the room's walls
	if h.band == "upper":
		return first.call([EdDoc.tex(side, "tex"), EdDoc.tex(side, "upperTex"), EdDoc.tex(o, "tex"), EdDoc.tex(o, "upperTex"), EdDoc.tex(s, "upperTex"), EdDoc.tex(s, "wallTex")])
	if h.band == "lower":
		return first.call([EdDoc.tex(side, "tex"), EdDoc.tex(side, "lowerTex"), EdDoc.tex(o, "tex"), EdDoc.tex(o, "lowerTex"), EdDoc.tex(s, "lowerTex"), EdDoc.tex(s, "wallTex")])
	if EdDoc.tex(side, "midTex") != "":
		return EdDoc.tex(side, "midTex")
	if EdDoc.tex(side, "tex") != "":
		return EdDoc.tex(side, "tex")
	var l = ed.line_info(h.line)
	if l != null and l.sectors.size() > 1:
		if EdDoc.tex(o, "midTex") != "":
			return EdDoc.tex(o, "midTex")
		for i in l.sectors:
			if MewdEditor.is_inside(d.sectors[i]):
				return first.call([EdDoc.tex(d.sectors[i], "wallTex")])
		return first.call([EdDoc.tex(s, "wallTex")])
	return first.call([EdDoc.tex(o, "tex"), EdDoc.tex(o, "wallTex"), EdDoc.tex(s, "wallTex")])

# ---------------------------------------------------------------------
# THE HIGHLIGHTS
# ---------------------------------------------------------------------

func outline(h) -> PackedVector3Array:
	var d := ed.doc
	var out := PackedVector3Array()
	if h == null:
		return out
	if h.kind == "surface" and h.part != "wall":
		if h.sector < 0 or h.sector >= d.sectors.size():
			return out
		var s: Dictionary = d.sectors[h.sector]
		var r := EdDoc.ring_of(d, s)
		var z := z_of(s, h.part)
		for i in r.size():
			out.append(gv(r[i].x, r[i].y, z))
			out.append(gv(r[(i + 1) % r.size()].x, r[(i + 1) % r.size()].y, z))
	elif h.kind == "surface":
		var ab := EdDoc.key_verts(h.line)
		if ab.x < 0 or ab.x >= d.vertices.size() or ab.y >= d.vertices.size():
			return out
		var a: Vector2 = d.vertices[ab.x]
		var b: Vector2 = d.vertices[ab.y]
		var l = ed.line_info(h.line)
		if l == null or l.sectors.is_empty():
			return out
		var ss: Array = l.sectors.map(func(i): return d.sectors[i])
		var fl: Array = ss.map(func(s): return z_of(s, "floor"))
		var ce: Array = ss.map(func(s): return z_of(s, "ceil"))
		var band := Vector2(fl[0], ce[0])
		if h.band == "lower":
			band = Vector2(fl.min(), fl.max())
		elif h.band == "upper":
			band = Vector2(ce.min(), ce.max())
		elif ss.size() > 1:
			var top: float = ce.min()
			var o: Dictionary = d.lines.get(h.line, {})
			var mh = o.get("midHeight")
			if exterior_wall(d, l):
				band = Vector2(fl.max(), top)
			elif mh != null:
				band = Vector2(fl.max(), minf(top, fl.max() + float(mh)))
			else:
				var tx := EdDoc.tex(o, "midTex")
				if tx == "" and o.get("sides") is Dictionary:
					for x in o.sides.values():
						if x is Dictionary and EdDoc.tex(x, "midTex") != "":
							tx = EdDoc.tex(x, "midTex")
							break
				var th := ed.tex_size(tx).y if tx != "" else 0.0
				band = Vector2(fl.max(), minf(top, fl.max() + th) if th > 0 else top)
		out.append(gv(a.x, a.y, band.x)); out.append(gv(b.x, b.y, band.x))
		out.append(gv(b.x, b.y, band.x)); out.append(gv(b.x, b.y, band.y))
		out.append(gv(b.x, b.y, band.y)); out.append(gv(a.x, a.y, band.y))
		out.append(gv(a.x, a.y, band.y)); out.append(gv(a.x, a.y, band.x))
	elif h.kind == "prop":
		for p in d.props:
			if p.id == h.id:
				_box(out, p.x0, p.y0, p.z0, p.x1, p.y1, p.z1)
	elif h.kind == "thing":
		for t in d.things:
			if t.id == h.id:
				var r := float(EdDoc.THING_TYPES.get(t.type, {}).get("radius", 16))
				var z := thing_z(t)
				_box(out, t.x - r, t.y - r, z, t.x + r, t.y + r, z + thing_height(t))
	return out

func draw_sel() -> void:
	if sel_lines == null:
		return
	var d := ed.doc
	var pts := PackedVector3Array()
	if ed.surf != null:
		var s: Dictionary = ed.surf.duplicate()
		s["kind"] = "surface"
		pts.append_array(outline(s))
	var kind := ed.sel_kind
	var ids := ed.sel_ids
	if kind == "sector":
		for si in d.sectors.size():
			var s: Dictionary = d.sectors[si]
			if not ids.has(s.id) or (ed.surf != null and ed.surf.sector == si and ed.surf.part != "wall"):
				continue
			pts.append_array(outline({"kind": "surface", "part": "floor", "sector": si}))
			if s.get("outdoor") == false:
				pts.append_array(outline({"kind": "surface", "part": "ceil", "sector": si}))
	if kind == "thing" or kind == "prop":
		for id in ids:
			pts.append_array(outline({"kind": kind, "id": id}))
	if kind == "scatter":
		for c in d.scatters:
			if not ids.has(c.id):
				continue
			var a: Dictionary = c.area
			if a.kind == "circle":
				_ring(pts, a.x, a.y, a.r, 2)
			elif a.kind == "rect":
				var k := [Vector2(a.x0, a.y0), Vector2(a.x1, a.y0), Vector2(a.x1, a.y1), Vector2(a.x0, a.y1)]
				for i in 4:
					var p: Vector2 = k[i]
					var q: Vector2 = k[(i + 1) % 4]
					pts.append(gv(p.x, p.y, floor_z(p.x, p.y) + 2))
					pts.append(gv(q.x, q.y, floor_z(q.x, q.y) + 2))
			else:
				for si in d.sectors.size():
					if a.get("ids", []).has(d.sectors[si].id):
						pts.append_array(outline({"kind": "surface", "part": "floor", "sector": si}))
	if kind == "line" and ed.surf == null:
		for k in ids:
			var l = ed.line_info(k)
			if l != null and not l.sectors.is_empty():
				pts.append_array(outline({"kind": "surface", "part": "wall", "band": "lower" if l.sectors.size() > 1 else "middle", "line": k, "sector": l.sectors[0]}))
	set_lines(sel_lines, pts)

func draw_hover() -> void:
	if hov_lines != null:
		set_lines(hov_lines, outline(hover))

## What is half-done, and what only a mode shows.
func draw_overlay() -> void:
	_overlay_dirty = false
	var d := ed.doc
	var pts := PackedVector3Array()
	var fz := func(p: Vector2) -> float: return floor_z(p.x, p.y) + 1.0
	var seg := func(a: Vector2, b: Vector2) -> void:
		pts.append(gv(a.x, a.y, fz.call(a)))
		pts.append(gv(b.x, b.y, fz.call(b)))
	var path: Array = ed.path.duplicate()
	if ed.mode == "draw" and ed.cursor != null and mouse != null:
		path.append(ed.cursor)
	for i in path.size() - 1:
		seg.call(path[i], path[i + 1])
	for p in ed.path:
		_cross(pts, p.x, p.y, fz.call(p), 8)
	if ed.cursor != null and mouse != null and ed.mode in ["draw", "rect", "things", "props", "scatter"] and drag == null:
		_cross(pts, ed.cursor.x, ed.cursor.y, fz.call(ed.cursor), 16)
	var dr = drag
	if dr != null and (dr.type == "rect" or dr.type == "prop"):
		var c: PackedVector2Array
		if dr.type == "rect" and dr.b != dr.a:
			c = ed.shape_points(dr.a, dr.b)
		else:
			c = PackedVector2Array([dr.a, Vector2(dr.b.x, dr.a.y), dr.b, Vector2(dr.a.x, dr.b.y)])
		for i in c.size():
			seg.call(c[i], c[(i + 1) % c.size()])
		if dr.type == "prop":
			for p in c:
				var z: float = fz.call(p)
				pts.append(gv(p.x, p.y, z))
				pts.append(gv(p.x, p.y, z + 64))
	if dr != null and dr.type == "brush":
		_ring(pts, dr.a.x, dr.a.y, dr.a.distance_to(dr.b))
	set_lines(draw_lines, pts)
	var area := PackedVector3Array()
	for c in d.get("scatters", []):
		if ed.is_sel("scatter", c.id):
			continue
		var a: Dictionary = c.area
		if a.kind == "circle":
			_ring(area, a.x, a.y, a.r, 2)
		elif a.kind == "rect":
			var k := [Vector2(a.x0, a.y0), Vector2(a.x1, a.y0), Vector2(a.x1, a.y1), Vector2(a.x0, a.y1)]
			for i in 4:
				var p: Vector2 = k[i]
				var q: Vector2 = k[(i + 1) % 4]
				area.append(gv(p.x, p.y, floor_z(p.x, p.y) + 2))
				area.append(gv(q.x, q.y, floor_z(q.x, q.y) + 2))
	set_lines(area_lines, area)
	# the vertex handles
	var im := ImmediateMesh.new()
	var any: bool = (ed.mode == "vertices" or ed.mode == "draw") and not d.vertices.is_empty()
	if any:
		im.surface_begin(Mesh.PRIMITIVE_POINTS)
		for i in d.vertices.size():
			var v: Vector2 = d.vertices[i]
			im.surface_set_color(Color("#ff9d3d") if ed.is_sel("vertex", i) else Color("#d8e0e4"))
			im.surface_add_vertex(gv(v.x, v.y, floor_z(v.x, v.y) + 1))
		im.surface_end()
	handles.mesh = im
	handles.visible = any

# ---------------------------------------------------------------------
# THE GRID AND THE AXES, Blender's way
# ---------------------------------------------------------------------

func _build_grid() -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	var m := MeshInstance3D.new()
	m.mesh = pm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRID_SHADER
	mat.shader = sh
	mat.render_priority = 10
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 65536
	return m

func _build_axes() -> Node3D:
	var g := Node3D.new()
	var L := 60000.0
	var add := func(c: Color, a: Vector3, b: Vector3) -> void:
		var mi := _lines_node(c, true, 5)
		root3d.remove_child(mi)
		g.add_child(mi)
		set_lines(mi, PackedVector3Array([a, b]))
	add.call(Color(AXIS_X, 0.9), Vector3(-L, 1, 0), Vector3(L, 1, 0))
	add.call(Color(AXIS_Y, 0.9), Vector3(0, 1, L), Vector3(0, 1, -L))
	add.call(AXIS_Z, Vector3(0, -L, 0), Vector3(0, L, 0))
	var dot := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_POINTS)
	im.surface_add_vertex(Vector3(0, 1, 0))
	im.surface_end()
	dot.mesh = im
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.use_point_size = true
	dm.point_size = 9
	dm.no_depth_test = true
	dm.render_priority = 41
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material_override = dm
	dot.extra_cull_margin = 65536
	g.add_child(dot)
	return g

func _place_grid() -> void:
	var on := show_grid
	grid.visible = on
	axes.visible = on
	gizmo.visible = on
	if not on or cam == null:
		return
	var drawing: bool = ed.mode in GRID_MODES and not visual
	var at = ed.cursor if drawing and ed.cursor != null and mouse != null else null
	var z := 0.0
	if drawing:
		if drag != null and drag.get("a") != null:
			z = floor_z(drag.a.x, drag.a.y)
		elif at != null:
			z = floor_z(at.x, at.y)
		else:
			z = floor_z(cam.x, cam.y)
	var step := maxf(1.0, float(ed.grid))
	var up := maxf(64.0, absf(cam.z - z))
	var R := clampf(up * 60 + step * 96, 8192, 60000)
	grid.position = gv(cam.x, cam.y, z + 0.75)
	grid.scale = Vector3(R, 1, R)
	var mat: ShaderMaterial = grid.material_override
	mat.set_shader_parameter("step", step)
	mat.set_shader_parameter("major", step * (4.0 if step >= 256 else 8.0))
	if at != null:
		mat.set_shader_parameter("focus", Vector2(at.x, -at.y))
		mat.set_shader_parameter("reach", maxf(maxf(step * 48, 1536), up * 12))
	else:
		mat.set_shader_parameter("focus", Vector2(cam.x, -cam.y))
		mat.set_shader_parameter("reach", maxf(maxf(step * 64, 4096), up * 30))
	gizmo.queue_redraw()

## THE GIZMO: X, Y and Z as the camera sees them.
func _draw_gizmo() -> void:
	var r := GIZMO / 2.0
	var L := r - 13.0
	gizmo.draw_circle(Vector2(r, r), r - 1, Color(12 / 255.0, 16 / 255.0, 20 / 255.0, 0.55))
	var inv := camera.global_transform.basis.inverse()
	var ends := []
	for ax in [["X", AXIS_X, Vector3(1, 0, 0)], ["Y", AXIS_Y, Vector3(0, 1, 0)], ["Z", AXIS_Z, Vector3(0, 0, 1)]]:
		for sgn in [1.0, -1.0]:
			var v: Vector3 = ax[2] * sgn
			var w := inv * gv(v.x, v.y, v.z)
			ends.append({"name": ax[0], "col": ax[1], "sgn": sgn, "p": Vector2(r + w.x * L, r - w.y * L), "depth": w.z})
	ends.sort_custom(func(a, b): return a.depth < b.depth)
	var font := EdStyle.mono()
	for e in ends:
		if e.sgn > 0:
			gizmo.draw_line(Vector2(r, r), e.p, e.col, 2.0)
			gizmo.draw_circle(e.p, 8, e.col)
			gizmo.draw_string(font, e.p + Vector2(-3.5, 4), e.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#0b0e11"))
		else:
			gizmo.draw_circle(e.p, 6, Color(e.col, 0.45))

# ---------------------------------------------------------------------
# EVERY FRAME
# ---------------------------------------------------------------------

func _process(dt: float) -> void:
	if not is_visible_in_tree() or not active:
		return
	if _need_rebuild and not ed.dragging:
		rebuild()
	if cam == null:
		return
	dt = minf(dt, 0.1)
	if looking or visual:
		var sp := FLY * (3.5 if keys.has(KEY_SHIFT) else 1.0) * dt
		var f := Vector2(cos(cam.yaw), sin(cam.yaw))
		var m := Vector3.ZERO
		if keys.has(KEY_W):
			m += Vector3(f.x * cos(cam.pitch), f.y * cos(cam.pitch), sin(cam.pitch))
		if keys.has(KEY_S):
			m -= Vector3(f.x * cos(cam.pitch), f.y * cos(cam.pitch), sin(cam.pitch))
		if keys.has(KEY_A):
			m += Vector3(-f.y, f.x, 0)
		if keys.has(KEY_D):
			m += Vector3(f.y, -f.x, 0)
		if keys.has(KEY_E) or keys.has(KEY_SPACE):
			m.z += 1
		if (keys.has(KEY_Q) and looking) or keys.has(KEY_C):
			m.z -= 1
		if m != Vector3.ZERO:
			cam.x += m.x * sp
			cam.y += m.y * sp
			cam.z += m.z * sp
			ed.camera_changed.emit()
			_hover_dirty = true
		# a key let go while the mouse was captured
		for k in keys.keys():
			if not Input.is_physical_key_pressed(k) and not Input.is_key_pressed(k):
				keys.erase(k)
	camera.position = gv(cam.x, cam.y, cam.z)
	camera.rotation = Vector3(cam.pitch, cam.yaw - PI / 2.0, 0)
	if _hover_dirty and mouse != null and not looking and drag == null:
		_hover_dirty = false
		var R := ray(mouse)
		hover = pick(R)
		draw_hover()
		var hv = hover
		if hv == null:
			ed.set_hover(null)
		elif hv.kind == "thing" or hv.kind == "prop":
			ed.set_hover({"kind": hv.kind, "id": hv.id})
		elif hv.part == "wall":
			ed.set_hover({"kind": "line", "id": hv.line, "part": "wall", "band": hv.band})
		else:
			ed.set_hover({"kind": "sector", "id": ed.doc.sectors[hv.sector].id, "part": hv.part})
		var sg = snap_ground(ground(R, hover), mouse)
		if sg != null:
			ed.set_cursor(sg)
			if ed.ui != null:
				ed.ui.set_pos(sg)
	if _overlay_dirty or ed.mode == "vertices":
		draw_overlay()
	_place_grid()

const BILLBOARD := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest_mipmap;
void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(vec3(VIEW_MATRIX[0][0], 0.0, VIEW_MATRIX[2][0]) + vec3(1e-5, 0.0, 0.0));
	vec3 p = base + right * VERTEX.x * sx + vec3(0.0, VERTEX.y * sy, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) discard;
	ALBEDO = c.rgb * COLOR.rgb;
}
"""

const PAINTED_SKY := """
shader_type sky;
uniform vec4 horizon : source_color;
uniform vec4 mid : source_color;
uniform vec4 zenith : source_color;
uniform vec4 ground : source_color;
void sky() {
	float y = EYEDIR.y;
	vec3 c;
	if (y >= 0.0) {
		float t = pow(clamp(y, 0.0, 1.0), 0.95);
		c = t < 0.5 ? mix(horizon.rgb, mid.rgb, t * 2.0) : mix(mid.rgb, zenith.rgb, (t - 0.5) * 2.0);
	} else {
		c = mix(horizon.rgb, ground.rgb, clamp(-y * 6.0, 0.0, 1.0));
	}
	COLOR = c;
}
"""

const GRID_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float step = 64.0;
uniform float major = 512.0;
uniform vec2 focus = vec2(0.0);
uniform float reach = 3072.0;
varying vec2 vp;
float lines(vec2 p, float s, float px) {
	vec2 g = abs(fract(p / s - 0.5) - 0.5) * s / max(fwidth(p), vec2(1e-4));
	return 1.0 - clamp(min(g.x, g.y) - (px - 1.0), 0.0, 1.0);
}
void vertex() {
	vp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
	vec3 minor = vec3(0.62, 0.91, 1.0);
	vec3 majorc = vec3(1.0);
	vec3 xaxis = vec3(1.0, 0.2, 0.32);
	vec3 yaxis = vec3(0.545, 0.863, 0.0);
	float fine = 1.0 - smoothstep(0.25, 0.6, length(fwidth(vp)) / step);
	float a1 = lines(vp, step, 1.0) * fine;
	float a2 = lines(vp, major, 1.5);
	vec2 ax = abs(vp) / max(fwidth(vp), vec2(1e-4));
	float onX = 1.0 - clamp(ax.y - 1.5, 0.0, 1.0);
	float onY = 1.0 - clamp(ax.x - 1.5, 0.0, 1.0);
	float fade = 1.0 - smoothstep(reach * 0.35, reach, distance(vp, focus));
	vec3 c = minor;
	float a = a1 * 0.38;
	if (a2 > 0.0) { c = mix(c, majorc, a2); a = max(a, a2 * 0.7); }
	a *= fade;
	float axf = max(fade, 0.55);
	if (onX > 0.0) { c = mix(c, xaxis, onX); a = max(a, onX * 0.95 * axf); }
	if (onY > 0.0) { c = mix(c, yaxis, onY); a = max(a, onY * 0.95 * axf); }
	if (a < 0.01) discard;
	ALBEDO = c;
	ALPHA = a;
}
"""
