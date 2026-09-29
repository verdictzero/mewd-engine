## MEWD — the street lamps (js/mapgeo.js lampGeometry, js/lamplight.js).
##
## THE STREET LAMP IS GEOMETRY. It is a PHOTOGRAPH — a cobra-head road
## light on a tapered pole, cut out of its chroma key — and a photograph
## of a lamp post cannot be a sprite: a sprite turns to face the camera,
## and this picture is a pole with a bracket arm reaching out on one side
## of it, so a street of them would be a street of lamps all pointing at
## the player. So it is a FLAT CUT-OUT stood in the world at a fixed
## angle: two masked quads (the head tile and the post tile) in the
## vertical plane of the thing's angle, the foot of the picture on the
## thing's x,y and the arm reaching the way the angle says. Both faces
## are drawn with the same u at the same point, so the arm reaches the
## same way from whichever side you see it — a lamp post is not chiral.
## Every lamp of a level is in the two batches, one draw a tile.
##
## ITS LIGHT is the flare at the luminaire (lamp_flare.gdshader): the
## point of cold light and the streak across it that a lamp is from
## across a street at night. One MultiMesh of LAMP_SLOTS quads, dealt
## every frame to the nearest lamps that could be seen, each eased onto
## what a SIGHT LINE from the eye says so a lamp behind a house does not
## flare through the house. Only after dark: `lamps_on` off the sky's
## light, the same curve the pavement's lamp tint runs on.
##
## The actor is not here: a STREETLAMP is also a solid thing of radius 8
## (js/states.js), which the game's spawn table owns.
class_name Lamps
extends Node3D

## the photograph (js/art-data.js LAMP, js/textures.js STREET_LAMP):
## 256 tall, its width off the aspect, the foot and the lens as
## fractions across and down it, and each tile's box in it [u0 v0 u1 v1]
const HEIGHT := 256.0
const ASPECT := 0.3489
const FOOT := 0.1206
const LENS := Vector2(0.7762, 0.0609)
const HEAD_BOX := [0.0, 0.0, 1.0, 0.1197]
const POST_BOX := [0.0, 0.1197, 0.2442, 1.0]

## Past this a lamp's light is not drawn at all.
const LAMP_FAR := 2400.0
## How many lamps get a flare at once: the nearest that many.
const LAMP_SLOTS := 40
## how fast a flare eases onto what the sight line said, per frame
const EASE := 0.28
## frames between sight tests on any one slot
const LOOK_EVERY := 3
## how bright a flare is at full, before the fade: subtle, at the user's request
const GAIN := 0.95

class Lamp:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vis := 0.0
	var seen := false
	var d := 0.0
	var looked := -1

var level: Level
var lamps: Array[Lamp] = []
var count := 0
var drawn := 0
var _flares: MultiMesh
var _flare_mi: MultiMeshInstance3D
var _buf := PackedFloat32Array()
var _frame := 0

static func width() -> float:
	return HEIGHT * ASPECT

## How much the street lamps are on, 0 to 1, off the sky's light: on as
## the sky goes under a half, full by a fifth (js/lamplight.js lampsOn).
static func lamps_on(sky_light: float) -> float:
	var t := clampf((sky_light - 0.22) / (0.50 - 0.22), 0.0, 1.0)
	return 1.0 - t * t * (3.0 - 2.0 * t)

func _init(lv: Level) -> void:
	level = lv
	name = "Lamps"
	var head := MapGeo.Batch.new()
	var post := MapGeo.Batch.new()
	var W := width()
	var along := (LENS.x - FOOT) * W
	var up := (1.0 - LENS.y) * HEIGHT
	for t in lv.things:
		if str(t.get("type", "")) != "STREETLAMP":
			continue
		var tx := float(t.x)
		var ty := float(t.y)
		var s := lv.sector_at(tx, ty)
		if s == null:
			continue
		var a := float(t.get("angle", 0.0))
		var ax := cos(a)
		var ay := sin(a)
		var z0 := s.floor
		var color := Color(clampf(s.light, 0.02, 1.4), s.sky, 0.0, 1.0)
		for pair in [[head, HEAD_BOX], [post, POST_BOX]]:
			var b: MapGeo.Batch = pair[0]
			var box: Array = pair[1]
			# where this tile lies along the arm, measured from the foot,
			# and how high it stands: the tile's box is a slice of the
			# whole picture
			var r0: float = (box[0] - FOOT) * W
			var r1: float = (box[2] - FOOT) * W
			var top: float = z0 + (1.0 - box[1]) * HEIGHT
			var bot: float = z0 + (1.0 - box[3]) * HEIGHT
			var x1 := tx + ax * r0
			var y1 := ty + ay * r0
			var x2 := tx + ax * r1
			var y2 := ty + ay * r1
			# one repeat of the tile is the whole slice: u 0 at the foot
			# end to 1 at the arm end, v 0 at the top to 1 at the bottom;
			# the world shader draws both faces
			b.quad([U.v3(x2, y2, top), U.v3(x1, y1, top), U.v3(x1, y1, bot), U.v3(x2, y2, bot)],
				[Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)], color)
		# THE LENS POINT: the underside of the luminaire, out along the
		# arm from the foot
		var L := Lamp.new()
		L.x = tx + ax * along
		L.y = ty + ay * along
		L.z = z0 + up - 2.0
		lamps.append(L)
	count = lamps.size()
	if count == 0:
		return
	_mesh(head, "res://godot/data/lamp_head.png", "LampHeads")
	_mesh(post, "res://godot/data/lamp_post.png", "LampPosts")
	_build_flares()

func _mesh(b: MapGeo.Batch, tex_path: String, node_name: String) -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = b.v
	arr[Mesh.ARRAY_TEX_UV] = b.uv
	arr[Mesh.ARRAY_COLOR] = b.col
	arr[Mesh.ARRAY_INDEX] = b.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = preload("res://godot/shaders/world.gdshader")
	# decoded to linear, as every wall's picture is (TexBank.decoded)
	m.set_shader_parameter("tex", TexBank.decoded(load(tex_path)))
	m.set_shader_parameter("masked", true)
	mesh.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_flares() -> void:
	var quad := QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = preload("res://godot/shaders/lamp_flare.gdshader")
	m.render_priority = 40
	quad.material = m
	_flares = MultiMesh.new()
	_flares.transform_format = MultiMesh.TRANSFORM_3D
	_flares.use_custom_data = true
	_flares.mesh = quad
	_flares.instance_count = LAMP_SLOTS
	_flares.visible_instance_count = 0
	_buf.resize(LAMP_SLOTS * 16)
	_flare_mi = MultiMeshInstance3D.new()
	_flare_mi.name = "LampFlares"
	_flare_mi.multimesh = _flares
	_flare_mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	_flare_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flare_mi)

## Deal the nearest lamps that could be seen into the slots. `cam` is
## the eye (Godot space), `look` which way it faces on the map (a unit
## map-space vector); `sky_light` the hour's (the global sky_light).
## Returns how many lamps were drawn.
func draw(cam: Vector3, look: Vector2, sky_light: float) -> int:
	_frame += 1
	if _flares == null:
		return 0
	var night := lamps_on(sky_light)
	if night < 0.01:
		_flares.visible_instance_count = 0
		drawn = 0
		return 0
	var ex := cam.x
	var ey := -cam.z
	var ez := cam.y
	var near: Array[Lamp] = []
	for L in lamps:
		var dx := L.x - ex
		var dy := L.y - ey
		var d2 := dx * dx + dy * dy
		if d2 > LAMP_FAR * LAMP_FAR:
			continue
		var d := sqrt(d2)
		# well behind the eye; not asked of anything close, because at
		# that range the flare is bigger than the test is right
		if d > 160.0 and dx * look.x + dy * look.y < -0.25 * d:
			continue
		L.d = d
		near.append(L)
	near.sort_custom(func(a: Lamp, b: Lamp): return a.d < b.d)
	var n := mini(LAMP_SLOTS, near.size())
	for i in n:
		var L := near[i]
		# the sight line: a third of the slots a frame, and at once for a
		# lamp that has not been asked lately, so one just dealt in does
		# not arrive lit through a wall
		if _frame - L.looked >= LOOK_EVERY or (_frame + i) % LOOK_EVERY == 0:
			L.seen = not level.sight_blocked(ex, ey, ez, L.x, L.y, L.z)
			L.looked = _frame
		var want := 1.0 if L.seen else 0.0
		L.vis += (want - L.vis) * EASE
		if absf(want - L.vis) < 0.01:
			L.vis = want
		var o := i * 16
		_buf[o] = 1.0; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = L.x
		_buf[o + 4] = 0.0; _buf[o + 5] = 1.0; _buf[o + 6] = 0.0; _buf[o + 7] = L.z
		_buf[o + 8] = 0.0; _buf[o + 9] = 0.0; _buf[o + 10] = 1.0; _buf[o + 11] = -L.y
		_buf[o + 12] = night * L.vis * GAIN; _buf[o + 13] = 0.0; _buf[o + 14] = 0.0; _buf[o + 15] = 0.0
	_flares.buffer = _buf
	_flares.visible_instance_count = n
	drawn = n
	return n
