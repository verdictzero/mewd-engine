## MEWD — PIECES TORN OUT OF SPRITES (at the user's request: "chunks taken
## out of sprites", plants that "blow up in chunks"). A round that takes a
## bite out of a candy girl, a rocket that blows a tree apart, a lamp shot
## to bits: each throws pieces of ITS OWN PICTURE — little ragged cards cut
## from the sprite where the bite was — that fly, tumble, bounce on the
## ground and fade.
##
## One MultiMesh per picture (a strip, a plant's sprite), every piece one
## row of it (shaders/sprite_chunk.gdshader), so a hundred pieces of a
## tree are one draw. The pieces are simulated per tic here (packed
## arrays, a cap on how many there are) and drawn per frame.
class_name SpriteChunks
extends Node3D

## how many pieces at once, all pictures together: the oldest go first
## (a big tree is eighty of them, VegDamage.pieces_for)
const MOST := 1200
const GRAVITY := -0.5
const DRAG := 0.985
## a bounce keeps this much of the fall, and the ground's grip this much
## of the slide
const BOUNCE := 0.35
const GRIP := 0.7
## the smallest piece cut from any picture, in its own texels each way
const TEXELS := 16.0

class Pool:
	var mm: MultiMesh
	var mi: MultiMeshInstance3D
	## per piece: position, velocity, size (w, h), spin and its rate,
	## life left and life at the start, the picture rectangle, wet
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var size := PackedVector2Array()
	var spin := PackedFloat32Array()
	var spin_v := PackedFloat32Array()
	var life := PackedInt32Array()
	var life0 := PackedInt32Array()
	var rect := PackedColorArray()
	var wet := PackedFloat32Array()
	var resting := PackedByteArray()

var game
var pools := {}
var _quad: ArrayMesh

func _init(g) -> void:
	game = g
	name = "SpriteChunks"
	_quad = ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

func _pool(tex: Texture2D, srgb: bool) -> Pool:
	var p: Pool = pools.get(tex)
	if p != null:
		return p
	p = Pool.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/sprite_chunk.gdshader")
	mat.set_shader_parameter("picture", tex)
	mat.set_shader_parameter("srgb", srgb)
	# (a plant's pieces, the sRGB pictures, fade out near the eye as plants do)
	mat.set_shader_parameter("near_fade", srgb)
	var mesh: ArrayMesh = _quad.duplicate()
	mesh.surface_set_material(0, mat)
	p.mm = MultiMesh.new()
	p.mm.transform_format = MultiMesh.TRANSFORM_3D
	p.mm.use_custom_data = true
	p.mm.mesh = mesh
	p.mi = MultiMeshInstance3D.new()
	p.mi.multimesh = p.mm
	p.mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	p.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p.mi)
	pools[tex] = p
	return p

func count() -> int:
	var n := 0
	for p in pools.values():
		n += (p as Pool).pos.size()
	return n

## A piece of `tex` (the rectangle `uv` of it, in 0..1), `w` x `h` units,
## from `at` (the game's x, y, z) at `vel` (units a tic), tumbling, for
## `life` tics. `wet`: a body's piece, run red at its torn edge. `srgb`:
## the picture is as loaded (a plant's), not decoded to linear (a strip's).
func spawn(tex: Texture2D, uv: Rect2, at: Vector3, w: float, h: float, vel: Vector3, life := 105, wet := 0.0, srgb := false) -> void:
	if tex == null:
		return
	if count() >= MOST:
		_drop_oldest()
	var p := _pool(tex, srgb)
	p.pos.append(at)
	p.vel.append(vel)
	p.size.append(Vector2(w, h))
	p.spin.append(randf() * TAU)
	p.spin_v.append(randf_range(-0.35, 0.35))
	var l := int(life * randf_range(0.8, 1.25))
	p.life.append(l)
	p.life0.append(l)
	p.rect.append(Color(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
	p.wet.append(wet)
	p.resting.append(0)

## A SPRITE BLOWN APART: its whole picture (`uv` of `tex`, standing
## `w` x `h` units on `at`) cut into a grid of about `pieces` and thrown
## out from `from` (where the blast was) with `force`, each piece leaving
## from where it was in the picture.
func burst(tex: Texture2D, uv: Rect2, at: Vector3, w: float, h: float, from: Vector3, pieces := 16, force := 1.0, wet := 0.0, srgb := false) -> void:
	if tex == null:
		return
	var cols := maxi(2, int(round(sqrt(pieces * w / maxf(h, 1.0)))))
	var rows := maxi(2, int(ceil(float(pieces) / cols)))
	# NO PIECE UNDER TEXELS BY TEXELS of the picture (at the user's request:
	# "smallest tree chunk should be 16x16 pixels, same with all other
	# veg"): the grid is coarsened until every cell is at least that
	cols = clampi(int(tex.get_width() * uv.size.x / TEXELS), 1, cols)
	rows = clampi(int(tex.get_height() * uv.size.y / TEXELS), 1, rows)
	var pw := w / cols
	var ph := h / rows
	for j in rows:
		for i in cols:
			# the piece's own place on the sprite
			var c := at + Vector3((i + 0.5) * pw - w * 0.5, 0.0, (rows - j - 0.5) * ph)
			var away := Vector3(c.x - from.x, c.y - from.y, 0.0)
			if away.length() < 1.0:
				away = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0)
			away = away.normalized()
			var sp := force * randf_range(4.0, 11.0)
			var v := Vector3(away.x * sp, away.y * sp, force * randf_range(4.0, 12.0))
			var r := Rect2(uv.position.x + uv.size.x * float(i) / cols, uv.position.y + uv.size.y * float(j) / rows,
				uv.size.x / cols, uv.size.y / rows)
			# a little bigger than its cell, so the ragged edges overlap
			spawn(tex, r, c, pw * 1.25, ph * 1.25, v, 120, wet, srgb)

## Full: the eighth of the pieces with the least life left go, all at
## once (one walk over them, not one a spawn — a blast in a wood throws
## hundreds).
func _drop_oldest() -> void:
	var lives := PackedInt32Array()
	for p in pools.values():
		lives.append_array((p as Pool).life)
	if lives.is_empty():
		return
	lives.sort()
	var cut: int = lives[mini(lives.size() - 1, MOST / 8)]
	for p in pools.values():
		var i: int = p.life.size() - 1
		while i >= 0:
			if p.life[i] <= cut:
				_remove(p, i)
			i -= 1

func _remove(p: Pool, i: int) -> void:
	var last := p.pos.size() - 1
	if i != last:
		p.pos[i] = p.pos[last]
		p.vel[i] = p.vel[last]
		p.size[i] = p.size[last]
		p.spin[i] = p.spin[last]
		p.spin_v[i] = p.spin_v[last]
		p.life[i] = p.life[last]
		p.life0[i] = p.life0[last]
		p.rect[i] = p.rect[last]
		p.wet[i] = p.wet[last]
		p.resting[i] = p.resting[last]
	p.pos.resize(last)
	p.vel.resize(last)
	p.size.resize(last)
	p.spin.resize(last)
	p.spin_v.resize(last)
	p.life.resize(last)
	p.life0.resize(last)
	p.rect.resize(last)
	p.wet.resize(last)
	p.resting.resize(last)

func tic() -> void:
	var lv = game.level
	for p in pools.values():
		var i: int = p.pos.size() - 1
		while i >= 0:
			p.life[i] -= 1
			if p.life[i] <= 0:
				_remove(p, i)
				i -= 1
				continue
			if p.resting[i] == 0:
				var v: Vector3 = p.vel[i] * DRAG
				v.z += GRAVITY
				var q: Vector3 = p.pos[i] + v
				var f: float = lv.floor_at(q.x, q.y)
				# lying on the ground is half its height above it
				var lie: float = f + p.size[i].y * 0.3
				if q.z < lie and f > IslandLevel.NO_FLOOR:
					q.z = lie
					if absf(v.z) < 2.0:
						p.resting[i] = 1
						v = Vector3.ZERO
					else:
						v = Vector3(v.x * GRIP, v.y * GRIP, -v.z * BOUNCE)
						p.spin_v[i] *= 0.6
				p.pos[i] = q
				p.vel[i] = v
				p.spin[i] += p.spin_v[i]
			i -= 1

func draw() -> void:
	for p in pools.values():
		var n: int = p.pos.size()
		var mm: MultiMesh = p.mm
		if mm.instance_count != n:
			mm.instance_count = n
		if n == 0:
			continue
		var buf := PackedFloat32Array()
		buf.resize(n * 16)
		var k := 0
		for i in n:
			var q: Vector3 = p.pos[i]
			var s: Vector2 = p.size[i]
			# the last third of its life, fading
			var gone := clampf(1.0 - float(p.life[i]) / maxf(1.0, p.life0[i] * 0.33), 0.0, 1.0)
			# basis x = (w, h, spin), basis y = (gone, wet, 0), basis z = up; origin the
			# piece's middle, the game's (x, y, z) as Godot's (x, z, -y)
			buf[k] = s.x; buf[k + 1] = 0.0; buf[k + 2] = 0.0; buf[k + 3] = q.x
			buf[k + 4] = s.y; buf[k + 5] = p.wet[i]; buf[k + 6] = 0.0; buf[k + 7] = q.z
			buf[k + 8] = p.spin[i]; buf[k + 9] = 0.0; buf[k + 10] = 1.0; buf[k + 11] = -q.y
			# (the row's 3x4 is laid out row by row: [x.x y.x z.x o.x | x.y y.y z.y o.y | x.z y.z z.z o.z])
			buf[k + 1] = gone
			var r: Color = p.rect[i]
			buf[k + 12] = r.r; buf[k + 13] = r.g; buf[k + 14] = r.b; buf[k + 15] = r.a
			k += 16
		mm.buffer = buf
