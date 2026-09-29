## MEWD — blood on the world: spatters, pools, and the walls round
## somebody who was hit (js/decals.js: Decals.blood, pool, bleed,
## sprayWalls, and the SPATTER and POOL kinds of its shader).
##
## GORE is not a pool of its own in the JS but the blood one, used
## harder: a round through somebody throws blood up EVERY wall in reach
## behind them rather than one, and a warhead that takes somebody apart
## paints the room round them — see spray_walls and Giblets.eviscerate.
## Here it is its own ring beside Decals' (whose "blood" is the older
## single-spatter kind), so nothing of decals.gd had to change: one
## MultiMesh, 480 slots, the oldest overwritten when it is full.
##
## Each decal is a quad laid on its surface, lifted a hair off it along
## the normal, and TURNED so that its +x is the way the blood was going
## (Decals.throwAngle) — a spatter is a direction, not a blot.
## Positions are map space (x, y, z up), through U.v3().
class_name GoreDecals
extends Node3D

const CAP := 480
const KIND_SPATTER := 5.0
const KIND_POOL := 6.0
const BLOOD_SIZE := [20.0, 38.0]     # a spatter, across
const POOL_SIZE := [44.0, 70.0]      # the pool under somebody, once it has spread
const BLOOD_REACH := 260.0           # how far behind somebody a round throws them onto a wall
## AND HOW MUCH OF IT GOES UP THE WALL. At the user's request ("i want
## blood spatter on walls too") a round through somebody is a SPRAY:
## WALL_SPRAY rays in a cone round the line the round was going, each
## one that reaches a wall leaving its own spatter, the near ones big
## and the far ones smaller, thrown the way the ray went and a little
## down, because blood does not go up.
const WALL_SPRAY := 4
const WALL_CONE := 0.42
const WALL_SPATTER := [30.0, 64.0]   # a spatter up a wall, across: near..far is big..small
const LIFT := 0.6
const UP := Vector3(0, 0, 1)

var game
var mm: MultiMesh
var mat: ShaderMaterial
var next := 0
var bloods := 0
var _count := 0
## a private stream of numbers for how decals look, apart from p_random
## (js/decals.js cosmetic), so the look does not move the game's dice
var _cos := 0x9e3779b9

func _init(g) -> void:
	game = g
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/gore_decal.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _process(_dt: float) -> void:
	mat.set_shader_parameter("now", _now())

## game time, in seconds: the pools spread and dry by the tic, so a
## paused game does not dry them
func _now() -> float:
	return float(game.tics) / U.TICRATE

func cosmetic() -> float:
	_cos = (_cos * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(_cos) / 4294967296.0

## Two unit directions across a normal, for laying a quad on it: along
## the wall and up for a wall, x and y for a floor (surfaceBasisInto).
static func surface_basis(n: Vector3) -> Array:
	if absf(n.z) > 0.5:
		return [Vector3(1, 0, 0), Vector3(0, 1, 0)]
	return [Vector3(-n.y, n.x, 0), Vector3(0, 0, 1)]

## The angle, about the normal, that points along (dx, dy, dz) laid flat
## on the surface — what turns a spatter to face the way it was thrown.
func throw_angle(n: Vector3, d: Vector3) -> float:
	var b := surface_basis(n)
	var du: float = d.dot(b[0])
	var dv: float = d.dot(b[1])
	return atan2(dv, du) if (du != 0.0 or dv != 0.0) else cosmetic() * TAU

func _light_at(x: float, y: float, z := 0.0) -> float:
	var s: Level.Sector = game.level.span_at(x, y, z)
	return s.light if s else 0.75

func _place(at: Vector3, n: Vector3, size: float, rot: float, kind: float) -> int:
	var b := surface_basis(n)
	var c := cos(rot)
	var s := sin(rot)
	var ax: Vector3 = b[0] * c + b[1] * s
	var ay: Vector3 = -b[0] * s + b[1] * c
	var bx := U.v3(ax.x, ax.y, ax.z) * size
	var by := U.v3(ay.x, ay.y, ay.z) * size
	var bz := U.v3(n.x, n.y, n.z)
	# a small lift per slot too, so two spatters laid on each other do
	# not fight for the pixel
	var pos := U.v3(at.x, at.y, at.z) + bz * (LIFT + (next % 8) * 0.04)
	var i := next
	mm.set_instance_transform(i, Transform3D(Basis(bx, by, bz), pos))
	mm.set_instance_custom_data(i, Color(kind, cosmetic(), _now(), _light_at(at.x, at.y, at.z)))
	next = (next + 1) % CAP
	_count = mini(_count + 1, CAP)
	mm.visible_instance_count = _count
	bloods += 1
	return i

## A SPATTER OF BLOOD on a surface at `at` whose normal is `n`, thrown
## along `d`. `size` 0 is a spatter's own size.
func blood(at: Vector3, n: Vector3, d := Vector3.ZERO, size := 0.0) -> int:
	var s: float = size if size > 0.0 else BLOOD_SIZE[0] + cosmetic() * (BLOOD_SIZE[1] - BLOOD_SIZE[0])
	return _place(at, n, s, throw_angle(n, d), KIND_SPATTER)

## A POOL of it on the floor at (x, y), under somebody who has come
## apart or gone down; it spreads over its first few seconds.
func pool(x: float, y: float, z: float, size := 0.0) -> int:
	var s: float = size if size > 0.0 else POOL_SIZE[0] + cosmetic() * (POOL_SIZE[1] - POOL_SIZE[0])
	return _place(Vector3(x, y, z), UP, s, cosmetic() * TAU, KIND_POOL)

## Who bleeds: people, and you. Not a van, not somebody frozen solid —
## ice breaks, it does not bleed.
func bleeds(a) -> bool:
	if a == null or a.get("vehicle") or a.get("frozen"):
		return false
	# (any player, not only this screen's — js/decals.js isPlayer; and a
	# puppet of one, whose info is a trooper's)
	if a == game.player or a is Player:
		return true
	if a.get("monster") == true:
		return true
	var inf = a.get("info")
	return inf is Dictionary and bool(inf.get("monster", false))

## SOMEBODY HAS BEEN HIT at `h` by something going along `d`: a spatter
## on the floor at their feet, thrown the way the round went, and — on
## every wall close enough behind them — a spray of it up the wall, at
## the heights the blood would have reached it. The JS's Decals.bleed,
## which replaces the one-spatter Decals.bleed in decals.gd.
func bleed(a, h: Vector3, d: Vector3) -> int:
	if not bleeds(a):
		return 0
	var u := d.normalized() if d.length() > 0.0 else Vector3(1, 0, 0)
	var n := 0
	# the floor, a little way past them
	var k := 6.0 + cosmetic() * 18.0
	var fx := h.x + u.x * k
	var fy := h.y + u.y * k
	var sec: Level.Sector = game.level.span_at(fx, fy, h.z)
	if sec:
		blood(Vector3(fx, fy, a.z if a.get("z") != null else sec.floor), UP, Vector3(u.x, u.y, 0))
		n += 1
	# and the walls behind them
	n += spray_walls(h, u, WALL_SPRAY, BLOOD_REACH, WALL_CONE)
	return n

## BLOOD UP THE WALLS round `h`: `rays` rays in a cone of `cone` radians
## either side of `u` — the first down the middle — out to `reach`, and
## every one that meets a wall leaves a spatter on it, facing the side
## the blood came from and thrown along the ray and a little down. The
## nearer the wall the bigger the spatter: blood that has a foot to
## travel arrives as a sheet, blood that has two metres arrives as
## drops. `scale` is for the warhead. A cone of PI is every direction.
## Returns how many landed.
func spray_walls(h: Vector3, u: Vector3, rays: int, reach: float, cone: float, scale := 1.0) -> int:
	var lv: Level = game.level
	var base := atan2(u.y, u.x)
	var flat := maxf(1e-6, Vector2(u.x, u.y).length())
	var under := lv.span_at(h.x, h.y, h.z)
	var fl: float = under.floor if under else -INF
	var n := 0
	for k in rays:
		var yaw := base if k == 0 else base + (cosmetic() * 2.0 - 1.0) * cone
		var rise := u.z / flat if k == 0 else u.z / flat + (cosmetic() - 0.62) * 0.7
		var c := cos(yaw)
		var s := sin(yaw)
		var wall := lv.ray_hit_wall(h.x, h.y, h.z, h.x + c * reach, h.y + s * reach, h.z + rise * reach)
		if wall.is_empty() or wall.line == null:
			continue
		# NOT UNDER THE FLOOR: a ray thrown down met a wall below the
		# floor's own level, where nobody will see it, so it is brought up
		# to the skirting — where blood thrown at a wall's foot ends up
		var wz: float = wall.z
		if wz < fl + 2.0:
			wz = fl + 2.0 + cosmetic() * 10.0
		var near := 1.0 - float(wall.t)
		var size: float = (WALL_SPATTER[0] + (WALL_SPATTER[1] - WALL_SPATTER[0]) * (near * 0.75 + cosmetic() * 0.25)) * scale
		blood(Vector3(wall.x, wall.y, wz), Decals.wall_normal(wall.line, h.x, h.y), Vector3(c, s, rise - 0.35), size)
		n += 1
	return n
