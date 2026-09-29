## MEWD — what a round leaves (js/decals.js).
##
## A HOLE where it lands on a wall, a floor or a ceiling — a hot one for
## the minigun, whose rim glows and cools — and BLOOD up the wall behind
## whoever it went through. Pools, not a list: the hole pool is 400 at
## the user's request (a hundred, four times over) and blood 480; when a
## pool is full the oldest goes. One MultiMesh a pool.
class_name Decals
extends Node3D

const POOLS := {"hole": 400, "blood": 480}
const HOLE_SIZE := [8.0, 13.0]
const HOT_SCALE := 1.35
const BLOOD_REACH := 260.0

## THE SEARS ARE FEW AND ENORMOUS (js/decals.js POOLS.sear): what the
## positron lance leaves where its column lands — a crater (kind 8) and
## the slag thrown round it (kind 9), in one pool of their own with a
## shader of their own (sear_decal.gdshader), because they GLOW and are
## blended premultiplied rather than cut out like a hole.
const SEAR_POOL := 96
const KIND_SEAR := 8.0
const KIND_SLAG := 9.0

class Pool:
	var mm: MultiMesh
	var next := 0
	var cap := 0

var pools := {}
var mat: ShaderMaterial
var sear_mat: ShaderMaterial
## counts, for the tests
var sears := 0
var slags := 0
var _t0 := Time.get_ticks_msec()

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/decal.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	for k in POOLS:
		var p := Pool.new()
		p.cap = POOLS[k]
		p.mm = MultiMesh.new()
		p.mm.transform_format = MultiMesh.TRANSFORM_3D
		p.mm.use_custom_data = true
		p.mm.mesh = quad
		p.mm.instance_count = p.cap
		p.mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = p.mm
		mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		pools[k] = p
	# the sears, on their own material
	sear_mat = ShaderMaterial.new()
	sear_mat.shader = preload("res://godot/shaders/sear_decal.gdshader")
	sear_mat.set_shader_parameter("gl_depth", RenderingServer.get_rendering_device() == null)
	var squad := QuadMesh.new()
	squad.size = Vector2(1, 1)
	squad.material = sear_mat
	var sp := Pool.new()
	sp.cap = SEAR_POOL
	sp.mm = MultiMesh.new()
	sp.mm.transform_format = MultiMesh.TRANSFORM_3D
	sp.mm.use_custom_data = true
	sp.mm.mesh = squad
	sp.mm.instance_count = sp.cap
	sp.mm.visible_instance_count = 0
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = sp.mm
	smi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# under everything else on the surface: the sears paint first
	smi.sorting_offset = -1.0
	add_child(smi)
	pools["sear"] = sp

func _process(_dt: float) -> void:
	mat.set_shader_parameter("now", _now())
	if sear_mat != null:
		sear_mat.set_shader_parameter("now", _now())

func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0

## Which way a wall faces the side a shot came from, in map space.
static func wall_normal(l: Level.Line, ox: float, oy: float) -> Vector3:
	var n := Vector3(l.dy, -l.dx, 0.0).normalized()
	if (ox - l.x1) * n.x + (oy - l.y1) * n.y < 0.0:
		n = -n
	return n

func _put(pool: String, at: Vector3, normal: Vector3, size: float, kind: float, light: float) -> void:
	var p: Pool = pools[pool]
	var n := U.v3(normal.x, normal.y, normal.z).normalized()
	var pos := U.v3(at.x, at.y, at.z) + n * 0.6
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-n, up)
	basis = basis.rotated(n, U.p_random() / 255.0 * TAU)
	basis = basis.scaled(Vector3(size, size, size))
	p.mm.set_instance_transform(p.next, Transform3D(basis, pos))
	p.mm.set_instance_custom_data(p.next, Color(kind, U.p_random() / 255.0, _now(), light))
	p.next = (p.next + 1) % p.cap
	p.mm.visible_instance_count = p.cap if p.next == 0 else maxi(p.mm.visible_instance_count, p.next)

func _light_at(at: Vector3) -> float:
	var g = get_parent()
	var s: Level.Sector = g.level.span_at(at.x, at.y, at.z)
	return s.light if s else 0.8

## A round into a surface. `hot`: the minigun's, whose rim glows.
func hole(at: Vector3, normal: Vector3, hot: bool) -> void:
	var s: float = (HOLE_SIZE[0] + (U.p_random() / 255.0) * (HOLE_SIZE[1] - HOLE_SIZE[0])) * (HOT_SCALE if hot else 1.0)
	_put("hole", at, normal, s, 1.0 if hot else 0.0, _light_at(at))

## A round through somebody: blood up the wall behind them, along the
## shot, if there is a wall within reach.
func bleed(who, at: Vector3, dir: Vector3) -> void:
	var g = get_parent()
	var d := Vector2(dir.x, dir.y).normalized()
	var reach := BLOOD_REACH * (0.5 + U.p_random() / 510.0)
	var hit: Dictionary = g.level.ray_hit_wall(at.x, at.y, at.z, at.x + d.x * reach, at.y + d.y * reach, at.z + (U.p_random() / 255.0 - 0.6) * 40.0)
	if not hit.is_empty():
		_put("blood", Vector3(hit.x, hit.y, hit.z), wall_normal(hit.line, at.x, at.y), 18.0 + U.p_random() / 12.0, 2.0, _light_at(at))
	elif who.sector != null:
		# on the floor at their feet
		_put("blood", Vector3(at.x + d.x * 20.0, at.y + d.y * 20.0, who.sector.floor), Vector3(0, 0, 1), 16.0 + U.p_random() / 16.0, 2.0, _light_at(at))

## A SEAR: where the positron lance's column landed — the crater,
## enormous, turned so its streaks lean the way the beam was going (`d`,
## map space). It glows for as long as its age says; see the SEAR branch
## of sear_decal.gdshader, and BeamSystem.SEAR for the size.
func sear(at: Vector3, normal: Vector3, size: float, d := Vector3.ZERO) -> void:
	_put_thrown("sear", at, normal, size * (0.9 + 0.2 * randf()), d, KIND_SEAR)
	sears += 1

## And a gob of SLAG thrown out of it, landed at `at` on the same surface,
## thrown along `d`.
func slag(at: Vector3, normal: Vector3, size: float, d := Vector3.ZERO) -> void:
	_put_thrown("sear", at, normal, size, d, KIND_SLAG)
	slags += 1

## A decal turned so its +x points along `d` laid flat on the surface —
## what turns a spatter to face the way it was thrown (js/decals.js
## throwAngle). A `d` along the normal gets a random turn.
func _put_thrown(pool: String, at: Vector3, normal: Vector3, size: float, d: Vector3, kind: float) -> void:
	var p: Pool = pools[pool]
	var n := U.v3(normal.x, normal.y, normal.z).normalized()
	var g := U.v3(d.x, d.y, d.z)
	var x := g - n * g.dot(n)
	if x.length() < 1e-3:
		var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
		x = up.cross(n).normalized().rotated(n, randf() * TAU)
	x = x.normalized()
	var y := n.cross(x)
	var basis := Basis(x * size, y * size, n * size)
	# lifted a little further than a hole: a sear is laid over holes and
	# blood that are already there
	var pos := U.v3(at.x, at.y, at.z) + n * (0.9 if kind == KIND_SEAR else 1.3)
	p.mm.set_instance_transform(p.next, Transform3D(basis, pos))
	var s: Level.Sector = get_parent().level.span_at(at.x, at.y, at.z)
	# w: the surface's light, plus two if it is under the sky
	var light := (s.light if s else 0.8) + (2.0 if s != null and s.sky > 0.5 else 0.0)
	p.mm.set_instance_custom_data(p.next, Color(kind, randf(), _now(), light))
	p.next = (p.next + 1) % p.cap
	p.mm.visible_instance_count = p.cap if p.next == 0 else maxi(p.mm.visible_instance_count, p.next)
