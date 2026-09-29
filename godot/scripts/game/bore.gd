## MEWD — the cerebral bore (js/bore.js).
##
## TUROK 2'S, at the user's request, and the rules are Turok's: a red
## sight, a LOCK when the sight finds a head, a projectile that only
## leaves the launcher when there is one, flies at that head however it
## moves — leaving slowly, bending toward the head by at most `turn` a
## tic while it speeds up, so it leaves in a curve and arrives fast —
## then drills into it for two seconds while its owner stands shaking,
## and then they explode. The one weapon in the game that is aimed
## rather than poured. The hold itself — `bored`, the countdown, the
## blood — lives on the actor (Actor.bore); the projectiles are not
## actors, they are one quad each.
class_name BoreSystem
extends Node3D

const BORE := {
	"range": 2200.0, "grace": 14, "speed0": 9.0, "speed1": 30.0, "accel": 1.09, "turn": 0.16,
	"life": 6 * 35, "drillTics": 78, "headAt": 0.86, "reach": 12.0,
}

var game
## the sight's end: {x, y, z, actor, t}
var aim := {}
var lock: Actor = null
var lock_tics := 0
var shots := []
var drilling := []
var fired := 0
var drilled := 0
var im := ImmediateMesh.new()
var im_top := ImmediateMesh.new()

func _init(g) -> void:
	game = g

func _ready() -> void:
	var a := MeshInstance3D.new()
	a.mesh = im
	a.material_override = _mat(false)
	a.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	add_child(a)
	# the dot and the reticle ignore depth on purpose: they sit ON a wall
	# or ON a head, and the trace has already decided what is in front
	var b := MeshInstance3D.new()
	b.mesh = im_top
	b.material_override = _mat(true)
	b.custom_aabb = a.custom_aabb
	add_child(b)

func _mat(top: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = top
	if top:
		m.render_priority = 10
	return m

func active() -> bool:
	var p = game.player
	return p != null and p.weapon == "BORE" and not p.dead

func lockable(a) -> bool:
	return a != null and a is Actor and not a.removed and not a.dead and a.shootable and a.monster and a.bored <= 0 and a.info.get("boreable", true)

func tic() -> void:
	var p = game.player
	if active():
		_sight_tic(p)
	else:
		lock = null
		lock_tics = 0
		aim = {}
	_fly_tic()
	_drill_tic()

func _sight_tic(p) -> void:
	aim = game.trace(p, p.angle, p.pitch, BORE.range)
	var cand = aim.actor if lockable(aim.actor) else null
	if cand != null:
		if cand != lock:
			game.play_sound("lock", null)
		lock = cand
		lock_tics = BORE.grace
	elif lock != null:
		lock_tics -= 1
		if not lockable(lock) or lock_tics <= 0:
			lock = null
			lock_tics = 0

## the trigger: nothing without a lock (Player.armed refuses it)
func fire(p) -> Dictionary:
	if lock == null:
		return {}
	var o: Vector3 = game.nozzle(p)
	var c := cos(p.pitch)
	var s := {"x": o.x, "y": o.y, "z": o.z, "dx": cos(p.angle) * c, "dy": sin(p.angle) * c, "dz": sin(p.pitch),
		"speed": BORE.speed0, "target": lock, "life": BORE.life, "tics": 0, "spin": 0, "stuck": null}
	shots.append(s)
	fired += 1
	game.play_sound("borefire", null)
	return s

func _fly_tic() -> void:
	var lv: Level = game.level
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var t = s.target
		var chasing: bool = t != null and not t.removed and not t.dead and t.bored <= 0
		if chasing:
			var hz: float = t.z + t.height * BORE.headAt
			var w := Vector3(t.x - s.x, t.y - s.y, hz - s.z).normalized()
			var d := Vector3(s.dx, s.dy, s.dz)
			var ang := acos(clampf(d.dot(w), -1.0, 1.0))
			if ang > 1e-4:
				var k := minf(1.0, BORE.turn / ang)
				d = (d + (w - d) * k).normalized()
				s.dx = d.x; s.dy = d.y; s.dz = d.z
		s.speed = minf(BORE.speed1, s.speed * BORE.accel)
		var nx: float = s.x + s.dx * s.speed
		var ny: float = s.y + s.dy * s.speed
		var nz: float = s.z + s.dz * s.speed
		s.spin += 1
		s.tics += 1
		if s.tics % 7 == 0:
			game.play_sound("borefly", null)
		if chasing:
			var hz: float = t.z + t.height * BORE.headAt
			var rr: float = t.radius + BORE.reach
			if U.dist2(nx, ny, t.x, t.y) < rr * rr and absf(nz - hz) < t.height * 0.35:
				shots.remove_at(i)
				_drill(s, t)
				continue
		var wall := lv.ray_hit_wall(s.x, s.y, s.z, nx, ny, nz)
		var sec := lv.span_at(nx, ny, s.z)
		s.life -= 1
		var spent: bool = sec == null or nz <= sec.floor + 2.0 or nz >= sec.ceil - 2.0 or s.life <= 0
		if not wall.is_empty() or spent:
			# it is hot, so what it leaves is a small burning hole
			if not wall.is_empty():
				game.decals.hole(Vector3(wall.x, wall.y, wall.z), Decals.wall_normal(wall.line, s.x, s.y), true)
			elif sec != null and nz <= sec.floor + 2.0:
				game.decals.hole(Vector3(nx, ny, sec.floor), Vector3(0, 0, 1), true)
			game.play_sound("clang", null)
			shots.remove_at(i)
			continue
		s.x = nx; s.y = ny; s.z = nz

func _drill(s: Dictionary, t) -> void:
	if t.bore(game.player) == "drill":
		s.stuck = t
		drilling.append(s)
		drilled += 1
		game.play_sound("bore", t)

func _drill_tic() -> void:
	for i in range(drilling.size() - 1, -1, -1):
		var s: Dictionary = drilling[i]
		var v = s.stuck
		if v == null or v.removed or v.dead or v.bored <= 0:
			drilling.remove_at(i)
			continue
		s.spin += 2
		s.x = v.x; s.y = v.y; s.z = v.z + v.height * BORE.headAt
		if v.bored % 6 == 0:
			game.play_sound("bore", v)

## The line from the launcher to the sight's end, a dot or a reticle at
## the end of it, and one turning quad per bore.
func draw(cam: Camera3D, t: float) -> void:
	im.clear_surfaces()
	im_top.clear_surfaces()
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var red := Color(1.0, 0.16, 0.10)
	var any := false
	if active() and not aim.is_empty():
		var o: Vector3 = game.nozzle(game.player)
		var e := Vector3(aim.x, aim.y, aim.z)
		if lock != null:
			e = Vector3(lock.x, lock.y, lock.z + lock.height * BORE.headAt)
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_set_color(red)
		im.surface_add_vertex(U.v3(o.x, o.y, o.z))
		im.surface_add_vertex(U.v3(e.x, e.y, e.z))
		im.surface_end()
		var at := U.v3(e.x, e.y, e.z)
		var d := at.distance_to(cam.global_position)
		im_top.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		if lock != null:
			# the reticle on the head: a ring, breathing
			var r := d * 0.018 * (1.0 + 0.25 * sin(t * 0.5 * 35.0))
			for k in 16:
				var a0 := k / 16.0 * TAU
				var a1 := (k + 1) / 16.0 * TAU
				for pr in [[r, r * 0.75]]:
					var p0: Vector3 = at + (right * cos(a0) + up * sin(a0)) * pr[0]
					var p1: Vector3 = at + (right * cos(a1) + up * sin(a1)) * pr[0]
					var q0: Vector3 = at + (right * cos(a0) + up * sin(a0)) * pr[1]
					var q1: Vector3 = at + (right * cos(a1) + up * sin(a1)) * pr[1]
					for v in [p0, p1, q1, p0, q1, q0]:
						im_top.surface_set_color(red)
						im_top.surface_add_vertex(v)
		else:
			var h := d * 0.004
			for v in [at - right * h - up * h, at + right * h - up * h, at + right * h + up * h,
					at - right * h - up * h, at + right * h + up * h, at - right * h + up * h]:
				im_top.surface_set_color(red)
				im_top.surface_add_vertex(v)
		im_top.surface_end()
	# the bores themselves: a dark turning blade with a hot tip
	var bores := shots + drilling
	if not bores.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for s in bores:
			var c := U.v3(s.x, s.y, s.z)
			var a: float = s.spin * 0.9
			var ax := (right * cos(a) + up * sin(a)) * 5.0
			var ay := (right * -sin(a) + up * cos(a)) * 2.0
			for v in [c - ax - ay, c + ax - ay, c + ax + ay, c - ax - ay, c + ax + ay, c - ax + ay]:
				im.surface_set_color(Color(0.25, 0.22, 0.2))
				im.surface_add_vertex(v)
		im.surface_end()
