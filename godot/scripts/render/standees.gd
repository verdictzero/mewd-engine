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
	var rows := []
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
	# decoded to linear, as the web build's sprite fetch is (TexBank.decoded)
	var tex: Texture2D = TexBank.decoded(load(path), false)
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
	var st: Dictionary = a.state
	var sprite: String = st.sprite
	var frame: String = st.frame
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

## `look`, the way the eye faces in map space: anyone well outside the
## widest view there is (a quarter turn and a bit off it) is not written
## at all — half the crowd, most frames, for nothing
func draw(actors: Array, cam: Vector3, tics: int, look := Vector2()) -> void:
	for k in strips:
		strips[k].n = 0
		strips[k].rows.clear()
	var cx := cam.x
	var cy := -cam.z
	var cam2 := Vector2(cx, cy)
	var cull := look != Vector2()
	var far2 := CULL_FAR * CULL_FAR
	var s_rate: float = SWAY.rate
	var s_run_rate: float = SWAY.runRate
	var s_lean: float = SWAY.lean
	var s_run_lean: float = SWAY.runLean
	var s_bob: float = SWAY.bob
	var s_run_bob: float = SWAY.runBob
	for a: Actor in actors:
		if a.removed or a.state.is_empty():
			continue
		var dx: float = a.x - cx
		var dy: float = a.y - cy
		var d2: float = dx * dx + dy * dy
		if d2 > far2:
			continue
		if cull and d2 > 160.0 * 160.0 and dx * look.x + dy * look.y < 0.3 * sqrt(d2):
			continue
		var c := _cell_of(a, cam2)
		var key: String = c[0]
		if key == "":
			continue
		var s: Strip = strips[key]
		var px: float = a.x
		var py: float = a.y
		var pz: float = a.z
		var info: Dictionary = a.info
		if info.get("sway", false) and not a.held():
			var run: bool = a.panic > 0
			var t: float = (tics + a.id * 37) * s_rate * (s_run_rate if run else 1.0)
			var lean: float = sin(t) * s_lean * (s_run_lean if run else 1.0)
			px += cos(a.id) * lean
			py += sin(a.id) * lean
			pz += absf(sin(t * 2.0 + a.id)) * s_bob * (s_run_bob if run else 1.0) - (s_bob if run else 0.0)
		var sec: Level.Sector = a.sector
		var light: float = (sec.light if sec else 0.7) * float(info.get("lit", 1.0))
		var sky: float = sec.sky if sec else 0.0
		var flags := (1.0 if c[2] else 0.0) + (2.0 if (a.state.fullbright or info.get("fullbright", false)) else 0.0)
		# and what only the launcher's thermal sight reads (standee.gdshader):
		# a BODY is warm, a frozen one cold, a burning one white
		if a.monster or a.puppet:
			flags += 8.0 if a.frozen else (4.0 if a.ash <= 0.0 else 0.0)
		if a.burning > 0:
			flags += 16.0
		# (into a plain Array, which is shared, not copied: a write through
		# `s.buf[i]`, a packed array on another object, copies all of it)
		s.rows.append_array([1.0, 0.0, 0.0, px, 0.0, 1.0, 0.0, pz, 0.0, 0.0, 1.0, -py, float(c[1]), light, sky, flags])
		s.n += 1
	for k in strips:
		var s: Strip = strips[k]
		if s.n == 0 and s.mm.visible_instance_count == 0:
			continue
		# room for the crowd in doubling steps, so the MultiMesh is not
		# remade every frame; past the live ones nothing is drawn
		var cap := maxi(s.mm.instance_count, 64)
		while cap < s.n:
			cap *= 2
		if s.mm.instance_count != cap:
			s.mm.instance_count = cap
		s.rows.resize(cap * 16)
		s.buf = PackedFloat32Array(s.rows)
		s.mm.buffer = s.buf
		s.mm.visible_instance_count = s.n
