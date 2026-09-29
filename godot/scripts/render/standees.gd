## MEWD — the crowd, drawn (js/standees.js, and Actor.render).
##
## Every sprite actor is a card turned about the vertical to face the
## eye, and every card of one strip is ONE draw: a MultiMesh whose rows
## say who is where, which cell of the strip, and how lit
## (standee.gdshader). Five hundred people is five hundred rows of
## sixteen floats, not five hundred nodes.
##
## THE ROWS ARE KEPT, NOT REBUILT: each actor owns a slot in its strip
## for as long as it is drawn, and its row is written again only when
## it is due — every tic up close, every other tic further off, every
## fourth far away (NEAR, MID) — and never between tics. A row written
## for someone behind the eye is left as it was (it is off the screen;
## when the eye turns it is a tic stale at most). So the crowd costs
## what is near you, not what is on the map — at the user's request, for
## speed. The SWAY — the lean where they stand, harder when running —
## is the shader's, off the clock, so a row need not change for it.
##
## THE TURNING, for the troops: five views mirrored to eight (js/people.js
## TROOP_ROTATIONS), the rotation chosen off the difference between the
## way they face and the way to the eye. A shopper is one drawing, so
## every side of one is the front.
class_name Standees
extends Node3D

const CULL_FAR := 6400.0
## how often a row is written, by distance: every tic, every other, every fourth
const NEAR := 640.0
const MID := 1600.0
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## rotation -> [view, mirrored]; 0 head on, anticlockwise from above
const ROTATIONS := [[0, false], [1, true], [2, true], [3, true], [4, false], [3, false], [2, false], [1, false]]
## the lean where they stand, and harder when running (js/people.js SWAY;
## standee.gdshader has the same numbers)
const SWAY := {"lean": 1.3, "bob": 0.7, "rate": 0.055, "runRate": 4.0, "runLean": 1.6, "runBob": 3.0}

class Strip:
	var mm: MultiMesh
	var mi: MultiMeshInstance3D
	## the rows, a plain Array (a write into a packed array held by
	## another object copies all of it)
	var rows := []
	var cap := 0
	## slots past the last live one are never drawn
	var high := 0
	var free := PackedInt32Array()
	var dirty := false
	var cells := 1
	var cell := Vector2.ONE

var strips := {}
## actor id -> [strip key, slot]
var slots := {}
var _last_tic := -1
## how many rows were written last tic (for the frame-rate readout)
var written := 0

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
## The state's part of the answer is worked out once and kept on the
## state itself (`_sd`: [strip, cell or -1 for a shopper's variant, the
## turn index or -1, views]).
func _cell_of(a: Actor, cam: Vector2) -> Array:
	var st: Dictionary = a.state
	var sd = st.get("_sd")
	if sd == null:
		sd = _state_draw(st)
		st["_sd"] = sd
	var strip: String = sd[0]
	if strip == "":
		return sd
	var kind: int = sd[1]
	if kind == -1:
		return [strip, a.variant % States.SHOPPERS, false]
	if kind == -3:
		return [strip, a.variant % 3, false]
	if kind == -4:
		return [strip, a.variant % 8, false]
	if kind >= 0:
		return [strip, kind, false]
	# a troop turning: the view for the way it faces against the eye
	var li: int = sd[2]
	var to_eye := atan2(cam.y - a.y, cam.x - a.x)
	var rel := U.angle_norm(a.angle - to_eye)
	var rot := ((roundi(rel / (PI / 4)) % 8) + 8) % 8
	var r: Array = ROTATIONS[rot]
	return [strip, li * int(sd[3]) + int(r[0]), r[1]]

static func _state_draw(st: Dictionary) -> Array:
	var sprite: String = st.sprite
	var frame: String = st.frame
	if sprite == "SHOP":
		return ["SHOP", -1, 0, 0]
	if sprite == "BLST":
		return ["BLST", LETTERS.find(frame), 0, 0]
	if sprite == "BLUD":
		return ["BLUD", -3, 0, 0]
	if sprite.begins_with("GRV"):
		return ["GRV", -4, 0, 0]
	if States.TROOPS.has(sprite):
		var t: Dictionary = States.TROOPS[sprite]
		var turn: String = t.turn
		var li := turn.find(frame)
		if li >= 0:
			return [sprite, -2, li, int(t.views)]
		var flat: String = t.flat
		return [sprite, turn.length() * int(t.views) + flat.find(frame), 0, 0]
	return ["", 0, 0, 0]

func _alloc(s: Strip) -> int:
	if s.free.size() > 0:
		var i := s.free[s.free.size() - 1]
		s.free.resize(s.free.size() - 1)
		return i
	if s.high >= s.cap:
		s.cap = maxi(64, s.cap * 2)
		s.rows.resize(s.cap * 16)
		for j in range(s.high * 16, s.cap * 16):
			s.rows[j] = 0.0
	s.high += 1
	return s.high - 1

func _drop(aid: int) -> void:
	var sl = slots.get(aid)
	if sl == null:
		return
	var s: Strip = strips[sl[0]]
	var i: int = sl[1]
	# scaled to nothing: never drawn
	s.rows[i * 16] = 0.0
	s.rows[i * 16 + 5] = 0.0
	s.rows[i * 16 + 10] = 0.0
	s.free.append(i)
	s.dirty = true
	slots.erase(aid)

## Once a tic (a second call in the same tic does nothing): every row
## that is due, written; the strips that changed, uploaded. `look`, the
## way the eye faces on the map: someone behind it is left as they were.
func draw(actors: Array, cam: Vector3, tics: int, look := Vector2()) -> void:
	if tics == _last_tic:
		return
	_last_tic = tics
	written = 0
	var cx := cam.x
	var cy := -cam.z
	var cam2 := Vector2(cx, cy)
	var cull := look != Vector2()
	var far2 := CULL_FAR * CULL_FAR
	var near2 := NEAR * NEAR
	var mid2 := MID * MID
	var seen := {}
	for a: Actor in actors:
		var aid: int = a.id
		if a.removed or a.state.is_empty():
			continue
		var dx: float = a.x - cx
		var dy: float = a.y - cy
		var d2: float = dx * dx + dy * dy
		if d2 > far2:
			continue
		seen[aid] = true
		var sl = slots.get(aid)
		if sl != null:
			# due this tic? and in front of the eye?
			var rate: int = 1 if d2 < near2 else (2 if d2 < mid2 else 4)
			if (tics + aid) % rate != 0:
				continue
			if cull and d2 > 160.0 * 160.0 and dx * look.x + dy * look.y < 0.3 * sqrt(d2):
				continue
		var c := _cell_of(a, cam2)
		var key: String = c[0]
		if key == "":
			continue
		if sl != null and sl[0] != key:
			_drop(aid)
			sl = null
		var s: Strip = strips[key]
		if sl == null:
			sl = [key, _alloc(s)]
			slots[aid] = sl
		var i: int = sl[1] * 16
		var sec: Level.Sector = a.sector
		var info: Dictionary = a.info
		var light: float = (sec.light if sec else 0.7) * float(info.get("lit", 1.0))
		var sky: float = sec.sky if sec else 0.0
		var flags := (1.0 if c[2] else 0.0) + (2.0 if (a.state.fullbright or info.get("fullbright", false)) else 0.0)
		# and what only the launcher's thermal sight reads (standee.gdshader):
		# a BODY is warm, a frozen one cold, a burning one white
		if a.monster or a.puppet:
			flags += 8.0 if a.frozen else (4.0 if a.ash <= 0.0 else 0.0)
		if a.burning > 0:
			flags += 16.0
		# the sway, for the shader: +32 standing, +64 running, and the
		# phase (the actor's id) from 128 up
		if info.get("sway", false) and not (a.frozen or a.ash > 0.0 or a.bored > 0):
			flags += 64.0 if a.panic > 0 else 32.0
		flags += 128.0 * float(aid % 4096)
		var rows: Array = s.rows
		rows[i] = 1.0; rows[i + 1] = 0.0; rows[i + 2] = 0.0; rows[i + 3] = a.x
		rows[i + 4] = 0.0; rows[i + 5] = 1.0; rows[i + 6] = 0.0; rows[i + 7] = a.z
		rows[i + 8] = 0.0; rows[i + 9] = 0.0; rows[i + 10] = 1.0; rows[i + 11] = -a.y
		rows[i + 12] = float(c[1]); rows[i + 13] = light; rows[i + 14] = sky; rows[i + 15] = flags
		s.dirty = true
		written += 1
	# the gone and the far: their rows scaled away
	for aid in slots.keys():
		if not seen.has(aid):
			_drop(aid)
	for k in strips:
		var s: Strip = strips[k]
		if not s.dirty:
			continue
		s.dirty = false
		if s.mm.instance_count != s.cap:
			s.mm.instance_count = s.cap
		if s.cap > 0:
			s.mm.buffer = PackedFloat32Array(s.rows)
		s.mm.visible_instance_count = s.high
