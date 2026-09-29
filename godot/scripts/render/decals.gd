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

class Pool:
	var mm: MultiMesh
	var next := 0
	var cap := 0

var pools := {}
var mat: ShaderMaterial
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

func _process(_dt: float) -> void:
	mat.set_shader_parameter("now", _now())

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
	p.mm.visible_instance_count = maxi(p.mm.visible_instance_count, p.next if p.mm.visible_instance_count < p.cap else p.cap)

func _light_at(at: Vector3) -> float:
	var g = get_parent()
	var s: Level.Sector = g.level.sector_at(at.x, at.y)
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
