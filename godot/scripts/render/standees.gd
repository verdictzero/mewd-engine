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
	## the strip's picture, for the pieces torn out of it (SpriteChunks)
	var tex: Texture2D
	## THE HOLES (Actor.holes): a row of Actor.HOLES texels a slot, each
	## (across, up, radius, 0) in units, read by standee.gdshader
	var holes: Image
	var holes_tex: ImageTexture
	var holes_dirty := false

var strips := {}
## actor id -> [strip key, slot]
var slots := {}
## actor id -> the holes_rev its holes were last written at
var _hole_rev := {}
var _last_tic := -1
## how many rows were written last tic (for the frame-rate readout)
var written := 0

func _ready() -> void:
	# THE CROWD AT 128 PIXELS ACROSS, at the user's request
	# (tools/prep-people-hd.py: galvarius's drawings, one scale): the
	# same 40 x 64 units in the world, 128 x 205 pixels in the strip,
	# mipmapped so a crowd far off does not shimmer
	_strip("SHOP", "res://assets/people/shoppers_hd.png", Vector2(40, 64), Vector2(128, 205))
	_strip("SWAT", "res://assets/people/swat.png", Vector2(64, 64))
	_strip("ARMY", "res://assets/people/army.png", Vector2(64, 64))
	_strip("BLST", "res://assets/people/blast.png", Vector2(48, 96))
	_strip("BLUD", "res://assets/people/splat.png", Vector2(56, 20))
	_strip("GRV", "res://godot/data/stones.png", Vector2(32, 48))
	# CANDY LAND, at the user's request: the candy girls, nine flavours
	# drawn from the front and from the back (192 x 287 pixels a cell,
	# 44 x 66 units in the world), and the street lamp
	_strip("CANDY", "res://assets/people/candy_girls.png", Vector2(44, 66), Vector2(192, 287))
	_strip("LAMP", "res://assets/people/candy_lamp.png", Vector2(80, 144), Vector2(256, 459))
	# the candy unicorns: front, side, back; the foal at 55% of her mother
	# (2.5 m to the horn's tip, and 1.4 m)
	_strip("UNI", "res://assets/people/candy_unicorn.png", Vector2(70.4, 80), Vector2(338, 384))
	_strip("FOAL", "res://assets/people/candy_foal.png", Vector2(33.3, 44), Vector2(189, 250))

## `texel`: the cell in the strip's own pixels, where that is not the
## cell in the world (one unit to the pixel) — a strip drawn finer than
## the world, which is mipmapped
func _strip(key: String, path: String, cell: Vector2, texel := Vector2.ZERO) -> void:
	var fine := texel != Vector2.ZERO
	# decoded to linear, as the web build's sprite fetch is (TexBank.decoded)
	var tex: Texture2D = TexBank.decoded(load(path), fine)
	var s := Strip.new()
	s.cell = cell
	s.tex = tex
	s.cells = int(tex.get_width() / (texel.x if fine else cell.x))
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/standee.gdshader")
	mat.set_shader_parameter("strip", U.col(tex))
	mat.set_shader_parameter("cells", U.col(float(s.cells)))
	mat.set_shader_parameter("cell", U.col(cell))
	quad.surface_set_material(0, mat)
	s.holes = Image.create_empty(Actor.HOLES, 64, false, Image.FORMAT_RGBAF)
	s.holes_tex = ImageTexture.create_from_image(s.holes)
	mat.set_shader_parameter("holes", s.holes_tex)
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
	if kind == -6:
		# AN ANIMAL SEEN FROM THREE SIDES: her front head on, her back going
		# away, her side across — the drawing faces right, so it is turned
		# for the other flank
		var rel := U.angle_norm(a.angle - atan2(cam.y - a.y, cam.x - a.x))
		if absf(rel) < PI / 4.0:
			return [strip, 0, false]
		if absf(rel) > 3.0 * PI / 4.0:
			return [strip, 2, false]
		return [strip, 1, rel < 0.0]
	if kind == -5:
		# A CANDY GIRL HAS A FRONT AND A BACK: her back when she faces away
		# from the eye — running from you, you see her run — her front
		# otherwise (walking up to you, saying hello)
		var away := cos(a.angle) * (cam.x - a.x) + sin(a.angle) * (cam.y - a.y) < 0.0
		return [strip, (a.variant % States.CANDY_FLAVOURS.size()) * 2 + (1 if away else 0), false]
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
	if sprite == "CANDY":
		return ["CANDY", -5, 0, 0]
	if sprite == "LAMP":
		return ["LAMP", 0, 0, 0]
	if sprite == "UNI" or sprite == "FOAL":
		return [sprite, -6, 0, 0]
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
		if s.holes.get_height() < s.cap:
			var grown := Image.create_empty(Actor.HOLES, s.cap, false, Image.FORMAT_RGBAF)
			grown.blit_rect(s.holes, Rect2i(0, 0, Actor.HOLES, s.holes.get_height()), Vector2i.ZERO)
			s.holes = grown
			s.holes_tex = ImageTexture.create_from_image(s.holes)
			(s.mm.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("holes", s.holes_tex)
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
	# and its holes, so the next one in the slot is whole
	if _hole_rev.has(aid):
		_hole_rev.erase(aid)
		for k in Actor.HOLES:
			s.holes.set_pixel(k, i, Color(0, 0, 0, 0))
		s.holes_dirty = true

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
			# (a blast, blood, a body falling: every tic wherever it is —
			# only the living crowd can wait)
			var rate: int = 1 if (d2 < near2 or not a.monster or a.dead) else (2 if d2 < mid2 else 4)
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
		# a BODY is warm, a frozen one cold, a burning one white — and only a
		# PERSON's body: a herd beast (CANDY LAND's unicorns) is as cold as
		# the ground (only people are hot, at the user's request)
		if (a.monster or a.puppet) and not info.get("herd", false):
			flags += 8.0 if a.frozen else (4.0 if a.ash <= 0.0 else 0.0)
		if a.burning > 0:
			flags += 16.0
		# the sway, for the shader: +32 standing, +64 running, and the
		# phase (the actor's id) from 128 up
		# (and a candy girl saying hello bounces as if running: she is pleased)
		if info.get("sway", false) and not (a.frozen or a.ash > 0.0 or a.bored > 0):
			flags += 64.0 if (a.panic > 0 or a.hello > 0) else 32.0
		flags += 128.0 * float(aid % 4096)
		var rows: Array = s.rows
		rows[i] = 1.0; rows[i + 1] = 0.0; rows[i + 2] = 0.0; rows[i + 3] = a.x
		# (a thing that must stand IN the ground, sunk: Actor info "sink")
		rows[i + 4] = 0.0; rows[i + 5] = 1.0; rows[i + 6] = 0.0; rows[i + 7] = a.z - float(info.get("sink", 0.0))
		rows[i + 8] = 0.0; rows[i + 9] = 0.0; rows[i + 10] = 1.0; rows[i + 11] = -a.y
		# the cell, and HOW FROZEN in its fraction (standee.gdshader's ice
		# map): frost building up to solid, 0.9 at most so the cell stays
		var ice: float = 1.0 if a.frozen else clampf(a.frost / Actor.FREEZE_AT, 0.0, 1.0)
		rows[i + 12] = float(c[1]) + ice * 0.9; rows[i + 13] = light; rows[i + 14] = sky; rows[i + 15] = flags
		s.dirty = true
		written += 1
		# THE HOLES, when it has a new one (or a slot of its own to put them in)
		if a.holes_rev != int(_hole_rev.get(aid, 0)):
			_hole_rev[aid] = a.holes_rev
			var slot: int = sl[1]
			for k in Actor.HOLES:
				var h: Vector3 = a.holes[k] if k < a.holes.size() else Vector3.ZERO
				s.holes.set_pixel(k, slot, Color(h.x, h.y, h.z, 0.0))
			s.holes_dirty = true
	# the gone and the far: their rows scaled away
	for aid in slots.keys():
		if not seen.has(aid):
			_drop(aid)
	for k in strips:
		var s: Strip = strips[k]
		if s.holes_dirty:
			s.holes_dirty = false
			s.holes_tex.update(s.holes)
		if not s.dirty:
			continue
		s.dirty = false
		if s.mm.instance_count != s.cap:
			s.mm.instance_count = s.cap
		if s.cap > 0:
			s.mm.buffer = PackedFloat32Array(s.rows)
		s.mm.visible_instance_count = s.high

## THE PICTURE an actor is drawn from now, for the pieces torn out of it
## (SpriteChunks): {tex, uv (its cell, 0..1), size (units), mirror}, or {}.
func picture_of(a: Actor, cam: Vector2) -> Dictionary:
	if a.state.is_empty():
		return {}
	var c := _cell_of(a, cam)
	var key: String = c[0]
	if key == "" or not strips.has(key):
		return {}
	var s: Strip = strips[key]
	var cell := floorf(float(c[1]))
	return {"tex": s.tex, "uv": Rect2(cell / s.cells, 0.0, 1.0 / s.cells, 1.0), "size": s.cell, "mirror": bool(c[2])}
