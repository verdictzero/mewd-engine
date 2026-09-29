## MEWD — the crowd, drawn (js/standees.js, and Actor.render).
##
## Every sprite actor is a card turned about the vertical to face the
## eye, and every card of one strip is ONE draw: a MultiMesh whose
## buffer is refilled each frame with who is where, which cell of the
## strip, and how lit (standee.gdshader). Five hundred people is five
## hundred rows of sixteen floats, not five hundred nodes.
##
## THE TURNING, for the troops: five views mirrored to eight (js/people.js
## TROOP_ROTATIONS), the rotation chosen per frame off the difference
## between the way they face and the way to the eye. A shopper is one
## drawing, so every side of one is the front.
class_name Standees
extends Node3D

const CULL_FAR := 6400.0
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## rotation -> [view, mirrored]; 0 head on, anticlockwise from above
const ROTATIONS := [[0, false], [1, true], [2, true], [3, true], [4, false], [3, false], [2, false], [1, false]]
## the lean where they stand, and harder when running (js/people.js SWAY)
const SWAY := {"lean": 1.3, "bob": 0.7, "rate": 0.055, "runRate": 4.0, "runLean": 1.6, "runBob": 3.0}

class Strip:
	var mm: MultiMesh
	var mi: MultiMeshInstance3D
	var buf := PackedFloat32Array()
	var n := 0
	var cells := 1
	var cell := Vector2.ONE

var strips := {}

func _ready() -> void:
	_strip("SHOP", "res://assets/people/shoppers.png", Vector2(40, 64))
	_strip("SWAT", "res://assets/people/swat.png", Vector2(64, 64))
	_strip("ARMY", "res://assets/people/army.png", Vector2(64, 64))
	_strip("BLST", "res://assets/people/blast.png", Vector2(48, 96))
	_strip("BLUD", "res://assets/people/splat.png", Vector2(56, 20))
	_strip("GRV", "res://godot/data/stones.png", Vector2(32, 48))

func _strip(key: String, path: String, cell: Vector2) -> void:
	var tex: Texture2D = load(path)
	var s := Strip.new()
	s.cell = cell
	s.cells = int(tex.get_width() / cell.x)
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/standee.gdshader")
	mat.set_shader_parameter("strip", tex)
	mat.set_shader_parameter("cells", float(s.cells))
	mat.set_shader_parameter("cell", cell)
	quad.surface_set_material(0, mat)
	s.mm = MultiMesh.new()
	s.mm.transform_format = MultiMesh.TRANSFORM_3D
	s.mm.use_custom_data = true
	s.mm.mesh = quad
	s.mi = MultiMeshInstance3D.new()
	s.mi.multimesh = s.mm
	s.mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	s.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s.mi)
	strips[key] = s

## Which strip and cell an actor's state draws from, and mirrored or not.
func _cell_of(a: Actor, cam: Vector2) -> Array:
	var sprite: String = a.state.sprite
	var frame: String = a.state.frame
	if sprite == "SHOP":
		return ["SHOP", a.variant % States.SHOPPERS, false]
	if sprite == "BLST":
		return ["BLST", LETTERS.find(frame), false]
	if sprite == "BLUD":
		return ["BLUD", a.variant % 3, false]
	if sprite.begins_with("GRV"):
		return ["GRV", a.variant % 8, false]
	if States.TROOPS.has(sprite):
		var t: Dictionary = States.TROOPS[sprite]
		var turn: String = t.turn
		var li := turn.find(frame)
		if li >= 0:
			var to_eye := atan2(cam.y - a.y, cam.x - a.x)
			var rel := U.angle_norm(a.angle - to_eye)
			var rot := ((roundi(rel / (PI / 4)) % 8) + 8) % 8
			var r: Array = ROTATIONS[rot]
			return [sprite, li * int(t.views) + int(r[0]), r[1]]
		var flat: String = t.flat
		return [sprite, turn.length() * int(t.views) + flat.find(frame), false]
	return ["", 0, false]

func draw(actors: Array, cam: Vector3, tics: int) -> void:
	for k in strips:
		strips[k].n = 0
	var cx := cam.x
	var cy := -cam.z
	var cam2 := Vector2(cx, cy)
	for a in actors:
		if a.removed or a.state.is_empty():
			continue
		var dx: float = a.x - cx
		var dy: float = a.y - cy
		if dx * dx + dy * dy > CULL_FAR * CULL_FAR:
			continue
		var c := _cell_of(a, cam2)
		if c[0] == "":
			continue
		var s: Strip = strips[c[0]]
		var px: float = a.x
		var py: float = a.y
		var pz: float = a.z
		if a.info.get("sway", false) and not a.held():
			var run: bool = a.panic > 0
			var t: float = (tics + a.id * 37) * SWAY.rate * (SWAY.runRate if run else 1.0)
			var lean: float = sin(t) * SWAY.lean * (SWAY.runLean if run else 1.0)
			px += cos(a.id) * lean
			py += sin(a.id) * lean
			pz += absf(sin(t * 2.0 + a.id)) * SWAY.bob * (SWAY.runBob if run else 1.0) - (SWAY.bob if run else 0.0)
		var sec: Level.Sector = a.sector
		var light: float = (sec.light if sec else 0.7) * float(a.info.get("lit", 1.0))
		var sky: float = sec.sky if sec else 0.0
		var flags := (1.0 if c[2] else 0.0) + (2.0 if (a.state.fullbright or a.info.get("fullbright", false)) else 0.0)
		var i := s.n * 16
		if s.buf.size() < i + 16:
			s.buf.resize(maxi(64 * 16, s.buf.size() * 2))
		s.buf[i] = 1.0; s.buf[i + 1] = 0.0; s.buf[i + 2] = 0.0; s.buf[i + 3] = px
		s.buf[i + 4] = 0.0; s.buf[i + 5] = 1.0; s.buf[i + 6] = 0.0; s.buf[i + 7] = pz
		s.buf[i + 8] = 0.0; s.buf[i + 9] = 0.0; s.buf[i + 10] = 1.0; s.buf[i + 11] = -py
		s.buf[i + 12] = float(c[1]); s.buf[i + 13] = light; s.buf[i + 14] = sky; s.buf[i + 15] = flags
		s.n += 1
	for k in strips:
		var s: Strip = strips[k]
		if s.mm.instance_count != s.buf.size() / 16:
			s.mm.instance_count = s.buf.size() / 16
		if s.buf.size() > 0:
			# past the live ones, nothing: an instance scaled to zero
			for j in range(s.n * 16, s.buf.size(), 16):
				s.buf[j] = 0.0; s.buf[j + 5] = 0.0; s.buf[j + 10] = 0.0
			s.mm.buffer = s.buf
			s.mm.visible_instance_count = s.n
