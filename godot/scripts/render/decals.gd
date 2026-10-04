## MEWD — what a round leaves (js/decals.js).
##
## A HOLE where it lands on a wall, a floor or a ceiling — a hot one for
## the minigun, whose rim glows and cools — and BLOOD up the wall behind
## whoever it went through. And SPOT HEATING for the flamethrower
## (js/decals.js HEAT): where the stream lands the surface itself glows,
## a spot fed by every flame that lands on it and cooling in six
## seconds; a spot that got properly hot leaves a SCORCH, a dark blot,
## for good. Pools, not a list: the hole pool is 400 at
## the user's request (a hundred, four times over) and blood 480; when a
## pool is full the oldest goes. One MultiMesh a pool.
##
## EVERY MARK IS A PROJECTED DECAL (godot/shaders/decal_project.
## gdshaderinc, at the user's request): a box standing on the surface,
## painting whatever surface is inside it, so a hole, a scorch or a
## crater lies on a hillside as the hillside lies. How deep each pool's
## box is along the surface's normal, as a share of its width, is THICK.
class_name Decals
extends Node3D

const POOLS := {"hole": 400, "blood": 480, "heat": 100}
## the spots: fed HEAT.per a landing, merged within `merge` of one
## already there, cooling `cool` a tic; a peak over `scorch_at` leaves
## a scorch of SCORCH_SIZE
const HEAT := {"size": 38.0, "per": 0.028, "cool": 1.0 / (6.0 * 35.0), "merge": 26.0, "scorch_at": 0.25}
const SCORCH_SIZE := 46.0
const KIND_SCORCH := 3.0
const KIND_HEAT := 4.0
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

## THE BIG MARKS (blast_decal.gdshader), at the user's request: a
## rocket's crater (10) and its soot thrown up the walls beside it (11),
## a potato's rainbow glass (12), and the arc maw's Lichtenberg burns
## (13). A pool of their own, laid over the sears.
const BLAST_POOL := 160
const KIND_BLAST := 10.0
const KIND_STREAK := 11.0
const KIND_NUKE := 12.0
const KIND_SHOCK := 13.0
const BLAST_SIZE := 230.0
const NUKE_SIZE := 300.0
const STREAK_REACH := 260.0

const THICK := {"hole": 1.0, "blood": 0.6, "heat": 0.6, "sear": 0.5, "blast": 0.45}

class Pool:
	var mm: MultiMesh
	var next := 0
	var cap := 0

var pools := {}
var mat: ShaderMaterial
## every pool's material (the holes', the blood's and the heat's are each
## their own, for their depth): each told the time
var _mats: Array = []
var sear_mat: ShaderMaterial
var blast_mat: ShaderMaterial
var blasts := 0
var streaks := 0
var nukes := 0
var shocks := 0
## counts, for the tests
var sears := 0
var slags := 0
var scorches := 0
## the heat spots, by slot in the heat pool
var _hx := PackedFloat32Array()
var _hy := PackedFloat32Array()
var _hz := PackedFloat32Array()
var _hn: Array[Vector3] = []
var _hs := PackedFloat32Array()
var _hpeak := PackedFloat32Array()
var _hseed := PackedFloat32Array()
var _hlight := PackedFloat32Array()
var _hlive := 0
var _t0 := Time.get_ticks_msec()

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/decal.gdshader")
	mat.set_shader_parameter("gl_depth", U.col(RenderingServer.get_rendering_device() == null))
	for k in POOLS:
		# (a material a pool, for the pool's own depth)
		var pm: ShaderMaterial = mat if k == "hole" else mat.duplicate()
		pm.set_shader_parameter("thick", U.col(THICK[k]))
		_mats.append(pm)
		var quad := BoxMesh.new()
		quad.size = Vector3(1, 1, 1)
		quad.material = pm
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
	var hn: int = POOLS.heat
	for arr in [_hx, _hy, _hz, _hs, _hpeak, _hseed, _hlight]:
		arr.resize(hn)
		arr.fill(0.0)
	_hn.resize(hn)
	_hn.fill(Vector3.ZERO)
	# the sears, on their own material
	sear_mat = ShaderMaterial.new()
	sear_mat.shader = preload("res://godot/shaders/sear_decal.gdshader")
	sear_mat.set_shader_parameter("gl_depth", U.col(RenderingServer.get_rendering_device() == null))
	sear_mat.set_shader_parameter("thick", U.col(THICK.sear))
	var squad := BoxMesh.new()
	squad.size = Vector3(1, 1, 1)
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
	# the big marks, on theirs
	blast_mat = ShaderMaterial.new()
	blast_mat.shader = preload("res://godot/shaders/blast_decal.gdshader")
	blast_mat.set_shader_parameter("gl_depth", U.col(RenderingServer.get_rendering_device() == null))
	blast_mat.set_shader_parameter("thick", U.col(THICK.blast))
	var bquad := BoxMesh.new()
	bquad.size = Vector3(1, 1, 1)
	bquad.material = blast_mat
	var bp := Pool.new()
	bp.cap = BLAST_POOL
	bp.mm = MultiMesh.new()
	bp.mm.transform_format = MultiMesh.TRANSFORM_3D
	bp.mm.use_custom_data = true
	bp.mm.mesh = bquad
	bp.mm.instance_count = bp.cap
	bp.mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bp.mm
	bmi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bmi.sorting_offset = -0.5
	add_child(bmi)
	pools["blast"] = bp

func _process(_dt: float) -> void:
	for m in _mats:
		m.set_shader_parameter("now", U.col(_now()))
	if sear_mat != null:
		sear_mat.set_shader_parameter("now", U.col(_now()))
	if blast_mat != null:
		blast_mat.set_shader_parameter("now", U.col(_now()))

func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0

## A flame has landed on a surface: the spot there heats.
func heat(at: Vector3, normal: Vector3) -> void:
	var p: Pool = pools["heat"]
	var n := U.v3(normal.x, normal.y, normal.z).normalized()
	var best := -1
	var best_d := HEAT.merge * HEAT.merge
	for i in p.cap:
		if _hs[i] <= 0.0 or _hn[i].dot(n) < 0.9:
			continue
		var d := U.dist2(_hx[i], _hy[i], at.x, at.y) + (_hz[i] - at.z) * (_hz[i] - at.z)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		best = p.next
		p.next = (p.next + 1) % p.cap
		if _hs[best] > 0.0:
			_expire(best)
		_hx[best] = at.x
		_hy[best] = at.y
		_hz[best] = at.z
		_hn[best] = n
		_hs[best] = 0.0
		_hpeak[best] = 0.0
		_hseed[best] = U.p_random() / 255.0
		_hlight[best] = _light_at(at)
		_hlive += 1
		var gn := U.v3(_ground(at, normal).x, _ground(at, normal).y, _ground(at, normal).z).normalized()
		var pos := U.v3(at.x, at.y, at.z)
		var up := Vector3.UP if absf(gn.y) < 0.95 else Vector3.FORWARD
		var basis := Basis.looking_at(-gn, up).rotated(gn, _hseed[best] * TAU).scaled(Vector3.ONE * HEAT.size)
		p.mm.set_instance_transform(best, Transform3D(basis, pos))
		p.mm.visible_instance_count = p.cap
		DecalLog.placed("heat", KIND_HEAT, best, _hlive, p.cap, at, HEAT.size)
	_hs[best] = minf(1.0, _hs[best] + HEAT.per)
	_hpeak[best] = maxf(_hpeak[best], _hs[best])
	p.mm.set_instance_custom_data(best, Color(KIND_HEAT, _hseed[best], _hs[best], _hlight[best]))

## Once a tic: every spot cools, and one gone cold leaves its scorch.
func tic() -> void:
	if _hlive <= 0:
		return
	var p: Pool = pools["heat"]
	for i in p.cap:
		if _hs[i] <= 0.0:
			continue
		_hs[i] -= HEAT.cool
		if _hs[i] <= 0.0:
			_expire(i)
		else:
			p.mm.set_instance_custom_data(i, Color(KIND_HEAT, _hseed[i], _hs[i], _hlight[i]))

## a spot that has ended: hidden, and a scorch under it if it got hot
func _expire(i: int) -> void:
	var p: Pool = pools["heat"]
	_hlive -= 1
	var peak := _hpeak[i]
	_hs[i] = 0.0
	_hpeak[i] = 0.0
	p.mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	if peak > HEAT.scorch_at:
		var n := _hn[i]
		var at := Vector3(_hx[i], _hy[i], _hz[i])
		var nm := Vector3(n.x, -n.z, n.y)
		var size := SCORCH_SIZE * (0.7 + 0.5 * peak)
		_put("hole", at, nm, size, KIND_SCORCH, _hlight[i])
		scorches += 1

## Which way a wall faces the side a shot came from, in map space.
static func wall_normal(l: Level.Line, ox: float, oy: float) -> Vector3:
	var n := Vector3(l.dy, -l.dx, 0.0).normalized()
	if (ox - l.x1) * n.x + (oy - l.y1) * n.y < 0.0:
		n = -n
	return n

## A MARK ON THE FLOOR LIES AS THE GROUND DOES: a normal straight up is
## the ground's own under `at` (IslandLevel.normal_at), so the box stands
## square to the slope and its picture is not stretched down it.
func _ground(at: Vector3, normal: Vector3) -> Vector3:
	var lv = get_parent().level
	if normal.z > 0.99 and lv != null and lv.has_method("normal_at"):
		return lv.normal_at(at.x, at.y)
	return normal

func _put(pool: String, at: Vector3, normal: Vector3, size: float, kind: float, light: float) -> void:
	var p: Pool = pools[pool]
	normal = _ground(at, normal)
	var n := U.v3(normal.x, normal.y, normal.z).normalized()
	var pos := U.v3(at.x, at.y, at.z)
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	var basis := Basis.looking_at(-n, up)
	basis = basis.rotated(n, U.p_random() / 255.0 * TAU)
	basis = basis.scaled(Vector3(size, size, size))
	p.mm.set_instance_transform(p.next, Transform3D(basis, pos))
	p.mm.set_instance_custom_data(p.next, Color(kind, U.p_random() / 255.0, _now(), light))
	var slot := p.next
	p.next = (p.next + 1) % p.cap
	p.mm.visible_instance_count = p.cap if p.next == 0 else maxi(p.mm.visible_instance_count, p.next)
	DecalLog.placed(pool, kind, slot, p.mm.visible_instance_count, p.cap, at, size)

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
		_blood(Vector3(hit.x, hit.y, hit.z), wall_normal(hit.line, at.x, at.y), 18.0 + U.p_random() / 12.0, _light_at(at))
	elif who.sector != null:
		# on the floor at their feet
		_blood(Vector3(at.x + d.x * 20.0, at.y + d.y * 20.0, who.sector.floor), Vector3(0, 0, 1), 16.0 + U.p_random() / 16.0, _light_at(at))

func _blood(at: Vector3, n: Vector3, size: float, light: float) -> void:
	_put("blood", at, n, size, 2.0, light)

## A SEAR: where the positron lance's column landed — the crater,
## enormous, turned so its streaks lean the way the beam was going (`d`,
## map space). It glows for as long as its age says; see the SEAR branch
## of sear_decal.gdshader, and BeamSystem.SEAR for the size.
func sear(at: Vector3, normal: Vector3, size: float, d := Vector3.ZERO) -> void:
	var big := size * (0.9 + 0.2 * randf())
	var s: Level.Sector = get_parent().level.span_at(at.x, at.y, at.z)
	_put_thrown("sear", at, normal, big, d, KIND_SEAR)
	sears += 1

## And a gob of SLAG thrown out of it, landed at `at` on the same surface,
## thrown along `d`.
func slag(at: Vector3, normal: Vector3, size: float, d := Vector3.ZERO) -> void:
	var s: Level.Sector = get_parent().level.span_at(at.x, at.y, at.z)
	_put_thrown("sear", at, normal, size, d, KIND_SLAG)
	slags += 1

## A ROCKET WENT OFF at `at`, against the surface facing `normal`: the
## crater there, and the blast's soot fanned up every wall near enough —
## rays round the blast at waist height, each wall they meet blackened
## from the near edge out, away from the blast.
func blast(at: Vector3, normal: Vector3, size := BLAST_SIZE) -> void:
	_put_thrown("blast", at, normal, size * (0.9 + 0.2 * randf()), Vector3.ZERO, KIND_BLAST)
	blasts += 1
	var lv: Level = get_parent().level
	var s: Level.Sector = lv.span_at(at.x, at.y, at.z)
	var z: float = (s.floor if s else at.z) + 40.0
	var seen := {}
	for k in 10:
		var th := k * TAU / 10.0 + randf() * 0.4
		var d := Vector2(cos(th), sin(th))
		var hit := lv.ray_hit_wall(at.x, at.y, z, at.x + d.x * STREAK_REACH, at.y + d.y * STREAK_REACH, z)
		if hit.is_empty() or hit.line == null or seen.has(hit.line):
			continue
		seen[hit.line] = true
		var n := wall_normal(hit.line, at.x, at.y)
		var away := Vector3(hit.x - at.x, hit.y - at.y, 0.0)
		# along the wall, away from the blast (or up it, met head on)
		var along := away - n * away.dot(n)
		if along.length() < 20.0:
			along = Vector3(0, 0, 1)
		along = along.normalized()
		var near := 1.0 - float(hit.t)
		var sz: float = size * (0.55 + 0.5 * near)
		_put_thrown("blast", Vector3(hit.x, hit.y, hit.z + sz * 0.15) + along * sz * 0.42, n, sz, along, KIND_STREAK)
		streaks += 1

## A POTATO WENT OFF: rainbow glass.
func nuke(at: Vector3, normal: Vector3, size := NUKE_SIZE) -> void:
	_put_thrown("blast", at, normal, size * (0.9 + 0.2 * randf()), Vector3.ZERO, KIND_NUKE)
	nukes += 1

## THE ARC MAW STRUCK here: a Lichtenberg figure, `size` across, its
## branches leaning along `d`.
func shock(at: Vector3, normal: Vector3, size: float, d := Vector3.ZERO) -> void:
	_put_thrown("blast", at, normal, size, d, KIND_SHOCK)
	shocks += 1

## A decal turned so its +x points along `d` laid flat on the surface —
## what turns a spatter to face the way it was thrown (js/decals.js
## throwAngle). A `d` along the normal gets a random turn.
func _put_thrown(pool: String, at: Vector3, normal: Vector3, size: float, d: Vector3, kind: float) -> void:
	var p: Pool = pools[pool]
	normal = _ground(at, normal)
	var n := U.v3(normal.x, normal.y, normal.z).normalized()
	var g := U.v3(d.x, d.y, d.z)
	var x := g - n * g.dot(n)
	if x.length() < 1e-3:
		var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
		x = up.cross(n).normalized().rotated(n, randf() * TAU)
	x = x.normalized()
	var y := n.cross(x)
	var basis := Basis(x * size, y * size, n * size)
	var pos := U.v3(at.x, at.y, at.z)
	p.mm.set_instance_transform(p.next, Transform3D(basis, pos))
	var s: Level.Sector = get_parent().level.span_at(at.x, at.y, at.z)
	# w: the surface's light, plus two if it is under the sky
	var light := (s.light if s else 0.8) + (2.0 if s != null and s.sky > 0.5 else 0.0)
	p.mm.set_instance_custom_data(p.next, Color(kind, randf(), _now(), light))
	var slot := p.next
	p.next = (p.next + 1) % p.cap
	p.mm.visible_instance_count = p.cap if p.next == 0 else maxi(p.mm.visible_instance_count, p.next)
	DecalLog.placed(pool, kind, slot, p.mm.visible_instance_count, p.cap, at, size)

## THE WARM-UP (Main, under the loading screen): one mark of every kind
## laid on the ground at `at` for a few frames, so each shader is compiled
## there and not at the first shot; then taken up again as if never laid.
var _warm := []
func warm_begin(at: Vector3) -> void:
	for k in pools:
		var p: Pool = pools[k]
		_warm.append([k, p.next, p.mm.visible_instance_count])
	_put("hole", at, Vector3(0, 0, 1), 12.0, 1.0, 1.0)
	_put("hole", at, Vector3(0, 0, 1), 40.0, KIND_SCORCH, 1.0)
	_put("blood", at, Vector3(0, 0, 1), 30.0, 2.0, 1.0)
	_put("heat", at, Vector3(0, 0, 1), HEAT.size, KIND_HEAT, 1.0)
	for kind in [KIND_SEAR, KIND_SLAG]:
		_put_thrown("sear", at, Vector3(0, 0, 1), 60.0, Vector3.ZERO, kind)
	for kind in [KIND_BLAST, KIND_NUKE, KIND_SHOCK]:
		_put_thrown("blast", at, Vector3(0, 0, 1), 60.0, Vector3.ZERO, kind)

func warm_end() -> void:
	for w in _warm:
		var p: Pool = pools[w[0]]
		var i: int = w[1]
		while i != p.next:
			p.mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			i = (i + 1) % p.cap
		p.next = w[1]
		p.mm.visible_instance_count = w[2]
	_warm.clear()
