## MEWD — the quad launcher's seeker and its missiles (js/missiles.js).
##
## FOUR TUBES AND A HEAT SEEKER, at the user's request: "a heat seeking
## quad shot function, can fire up to four at once with four locks".
##
## THE SEEKER. Hold the trigger and the launcher looks for heat down the
## middle of the view — six degrees round the sight, out to the far side
## of the town. The warm thing nearest the middle, in plain sight, is
## ACQUIRED — a dwell with the seeker growling — and then LOCKED, with a
## tone. Keep holding and the next is taken, up to four, one per loaded
## tube; fewer warm things than tubes and it locks the same one again. A
## lock HOLDS while the target stays roughly where you look and in
## sight, for half a second outside either; dead or frozen (ice is not a
## heat source) and it is dropped at once.
##
## THE SALVO. Let go and one missile leaves for every lock, a tube at a
## time, a few tics apart; no locks and it fires ONE straight down the
## sight. THE FLIGHT: out of its own tube, kicked outward so four fan out
## before they turn, then steering no more than `turn` a tic at where the
## target WILL BE, speeding up the whole way. THE WARHEAD: a BLAST, not
## fire (the troopers are fireproof), everything in reach a share that
## falls off with distance, and anybody it kills is eviscerated.
class_name MissileSystem
extends Node3D

const SEEKER := {"range": 4200.0, "cone": 0.105, "track": 0.21, "hold": 0.34, "grace": 18, "first": 16, "next": 11, "most": 4}
const MISSILE := {"speed0": 12.0, "speed1": 58.0, "accel": 1.13, "boost": 5, "turn": 0.085, "kick": 0.075,
	"life": 7 * 35, "reach": 14.0, "gap": 4, "lead": 40.0}
const WARHEAD := {"direct": 420, "splash": 150, "radius": 190.0, "heat": 240.0, "heatRadius": 90.0, "ignite": 260, "self": 0.5}
const TRAIL := {"step": 14.0, "max": 1000, "life": 44, "size0": 6.0, "size1": 34.0, "light": 0.82}
const BOOM := {"tics": 3, "frames": 8, "size": 136.0}

## the visual layer the lock brackets are drawn on (see _ready)
const RETICLE_LAYER := 1 << 19

var game
var locks := []          # {t, lost} — a target may appear more than once
var acquiring = null
var dwell := 0
var queue := []
var gap_tics := 0
var salvo_tube := 0
var shots := []
var fired := 0
var hits := 0
var blasts := 0
var shake := 0.0
var booms := []
var trail: Particles
var im := ImmediateMesh.new()
var im_top := ImmediateMesh.new()
var boom_mm: MultiMesh

func _init(g) -> void:
	game = g

func _ready() -> void:
	trail = Particles.new({"max": TRAIL.max, "map": Effects.atlases().smoke, "frames": Effects.SMOKE_PUFFS,
		"blend": "mix", "fullbright": false, "near_shrink": 90.0})
	trail.mat.set_shader_parameter("light", TRAIL.light)
	add_child(trail)
	var box := AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	for pair in [[im, false], [im_top, true]]:
		var mi := MeshInstance3D.new()
		mi.mesh = pair[0]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = pair[1]
		if pair[1]:
			m.render_priority = 10
			# THE BRACKETS ARE NOT IN THE WORLD: the thermal sight draws its
			# own on its glass, and a bracket in its feed would be a hot
			# square — so they are on a layer its camera does not draw
			mi.layers = RETICLE_LAYER
		mi.material_override = m
		mi.custom_aabb = box
		add_child(mi)
	# the fireball of a warhead: frames of the effects' fireball strip
	boom_mm = MultiMesh.new()
	boom_mm.transform_format = MultiMesh.TRANSFORM_3D
	boom_mm.use_colors = true
	boom_mm.use_custom_data = true
	var q := QuadMesh.new()
	var bm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = preload("res://godot/shaders/particle.gdshader").code.replace("render_mode unshaded,", "render_mode unshaded, blend_add,")
	bm.shader = sh
	bm.set_shader_parameter("map", Effects.atlases().fireball)
	bm.set_shader_parameter("has_map", true)
	bm.set_shader_parameter("frames", float(Effects.FIREBALLS))
	q.material = bm
	boom_mm.mesh = q
	boom_mm.instance_count = 16
	boom_mm.visible_instance_count = 0
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = boom_mm
	bmi.custom_aabb = box
	add_child(bmi)

func active() -> bool:
	var p = game.player
	return p != null and p.weapon == "LAUNCHER" and not p.dead

func salvo_left() -> int:
	return queue.size()

func acquire_fraction() -> float:
	if acquiring == null:
		return 0.0
	return minf(1.0, float(dwell) / (SEEKER.next if locks.size() else SEEKER.first))

## WHAT IS HOT, answered in one place — the seeker asks it to pick a
## target and the thermal sight (ThermalScope) to decide what glows:
## people who are alive and not frozen, and a vehicle with its engine
## running or on fire. A parked car is cold. A dead one is cold.
func is_hot(t) -> bool:
	if t == null:
		return false
	if t.has_method("is_hot"):
		return t.is_hot()
	if t is Vehicle:
		return t.whole() and (t.state == "driving" or t.state == "charring" or t.burning > 0)
	return t is Actor and not t.removed and not t.dead and t.shootable and t.monster and not t.frozen

func heat_sources() -> Array:
	var out := []
	for a in game.actors:
		if a.monster and is_hot(a):
			out.append(a)
	if game.get("vehicles") != null:
		for v in game.vehicles.all:
			if is_hot(v):
				out.append(v)
	return out

func heat_point(t) -> Vector3:
	if "cz" in t:
		return Vector3(t.x, t.y, t.cz)
	return Vector3(t.x, t.y, t.z + t.height * 0.58)

## The player's side of it (js/player.js launcherTic): hold to seek, let
## go to fire; nothing changes weapon while a salvo is leaving.
func player_tic(p, attack: bool) -> void:
	if p.fire_index >= 0:
		p.fire_tics -= 1
		if p.fire_tics <= 0:
			p.fire_index = -1
	if salvo_left() > 0:
		p.seeking = false
		return
	if attack:
		if not p.seeking and p.ammo.rockets <= 0:
			if not p.clicked:
				p.clicked = true
				game.play_sound("noammo", p)
			return
		p.seeking = true
		return
	p.clicked = false
	if p.seeking:
		p.seeking = false
		if release(p) > 0:
			return
	if p.pending_weapon != "" and p.fire_index < 0:
		p.weapon = p.pending_weapon
		p.pending_weapon = ""

func tic() -> void:
	var p = game.player
	if active() and p.seeking:
		_seek_tic(p)
	else:
		acquiring = null
		dwell = 0
	if active():
		_hold_tic(p)
	elif queue.is_empty():
		locks.clear()
	_salvo_tic(p)
	_fly_tic()
	trail.tic()
	for i in range(booms.size() - 1, -1, -1):
		var b: Dictionary = booms[i]
		_boom_tic(b)
		b.t += 1
		if b.t >= BOOM.tics * BOOM.frames:
			booms.remove_at(i)
	shake = maxf(0.0, shake - 0.035)

func _off_sight(p, pt: Vector3) -> float:
	var d := pt - Vector3(p.x, p.y, p.eye_z())
	var l := d.length()
	if l < 1.0 or l > SEEKER.range:
		return -1.0
	var c := cos(p.pitch)
	var f := Vector3(cos(p.angle) * c, sin(p.angle) * c, sin(p.pitch))
	var dot := d.dot(f) / l
	if dot <= 0.0:
		return -1.0
	return acos(minf(1.0, dot))

func _in_sight(p, pt: Vector3) -> bool:
	return not game.level.sight_blocked(p.x, p.y, p.eye_z(), pt.x, pt.y, pt.z)

func _seek_tic(p) -> void:
	var want := mini(SEEKER.most, p.ammo.rockets)
	if locks.size() >= want:
		acquiring = null
		dwell = 0
		return
	if acquiring != null and is_hot(acquiring):
		var pt := heat_point(acquiring)
		var a := _off_sight(p, pt)
		if a >= 0.0 and a <= SEEKER.track and _in_sight(p, pt):
			_dwell(want)
			return
	var best = null
	var best_a: float = SEEKER.cone
	var again = null
	var again_a: float = SEEKER.cone
	for t in heat_sources():
		var pt := heat_point(t)
		var a := _off_sight(p, pt)
		if a < 0.0 or a > SEEKER.cone or not _in_sight(p, pt):
			continue
		var locked := locks.any(func(l): return l.t == t)
		if not locked and a < best_a:
			best = t
			best_a = a
		if locked and a < again_a:
			again = t
			again_a = a
	var cand = best if best != null else again
	if cand == null:
		acquiring = null
		dwell = 0
		return
	if cand != acquiring:
		acquiring = cand
		dwell = 0
		game.play_sound("seek", null)
	_dwell(want)

func _dwell(want: int) -> void:
	dwell += 1
	if dwell < (SEEKER.next if locks.size() else SEEKER.first):
		return
	locks.append({"t": acquiring, "lost": 0})
	acquiring = null
	dwell = 0
	game.play_sound("lockfull" if locks.size() >= want else "lockon", null)

func _hold_tic(p) -> void:
	for i in range(locks.size() - 1, -1, -1):
		var l: Dictionary = locks[i]
		if not is_hot(l.t):
			locks.remove_at(i)
			continue
		var pt := heat_point(l.t)
		var a := _off_sight(p, pt)
		var ok := a >= 0.0 and a <= SEEKER.hold and _in_sight(p, pt)
		l.lost = 0 if ok else l.lost + 1
		if l.lost > SEEKER.grace:
			locks.remove_at(i)

func release(p) -> int:
	var loaded: int = p.ammo.rockets
	if loaded <= 0:
		return 0
	if locks.size():
		for l in locks.slice(0, loaded):
			queue.append(l.t)
	else:
		queue.append(null)
	locks.clear()
	acquiring = null
	dwell = 0
	gap_tics = 0
	salvo_tube = SEEKER.most - loaded
	return queue.size()

func _salvo_tic(p) -> void:
	if queue.is_empty():
		return
	if p == null or p.dead or p.weapon != "LAUNCHER":
		queue.clear()
		return
	if gap_tics > 0:
		gap_tics -= 1
		return
	var t = queue.pop_front()
	launch(p, t if t != null and is_hot(t) else null, salvo_tube % SEEKER.most)
	salvo_tube += 1
	gap_tics = MISSILE.gap

## where tube `tube` is: the nozzle, a hand apart right/left and up/down
func _tube_at(p, tube: int) -> Vector3:
	var o: Vector3 = game.nozzle(p)
	var right := -1.0 if (tube & 1) == 0 else 1.0
	var up := 1.0 if tube < 2 else -1.0
	return o + Vector3(sin(p.angle) * right * 4.0, -cos(p.angle) * right * 4.0, up * 4.0)

func launch(p, target, tube: int) -> Dictionary:
	if p.ammo.rockets <= 0:
		return {}
	p.ammo.rockets -= 1
	p.shots_fired += 1
	p.fire_index = 0
	p.fire_tics = 5
	var o := _tube_at(p, tube)
	if not game.level.ray_hit_wall(p.x, p.y, p.eye_z(), o.x, o.y, o.z).is_empty():
		o = Vector3(p.x, p.y, p.eye_z() - 6.0)
	var aim: Dictionary = game.trace(p, p.angle, p.pitch, SEEKER.range)
	var d := (Vector3(aim.x, aim.y, aim.z) - o).normalized()
	if target != null:
		var right := -1.0 if (tube & 1) == 0 else 1.0
		var up := 1.0 if tube < 2 else -1.0
		d += Vector3(sin(p.angle) * right * MISSILE.kick, -cos(p.angle) * right * MISSILE.kick, up * MISSILE.kick * 0.8)
		d = d.normalized()
	var s := {"x": o.x, "y": o.y, "z": o.z, "dx": d.x, "dy": d.y, "dz": d.z, "speed": MISSILE.speed0,
		"target": target, "life": MISSILE.life, "tics": 0, "tube": tube, "seed": U.p_random() / 255.0}
	shots.append(s)
	fired += 1
	game.play_sound("missile", p)
	game.fx.puff(p.x - cos(p.angle) * 44.0, p.y - sin(p.angle) * 44.0, p.eye_z() - 6.0, 20, 70)
	game.noise(p, 1400.0)
	return s

func _fly_tic() -> void:
	var lv: Level = game.level
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		s.tics += 1
		var t = s.target if s.target != null and is_hot(s.target) else null
		if t == null:
			s.target = null
		if t != null and s.tics > MISSILE.boost:
			_steer(s, t)
		s.speed = minf(MISSILE.speed1, s.speed * MISSILE.accel)
		var nx: float = s.x + s.dx * s.speed
		var ny: float = s.y + s.dy * s.speed
		var nz: float = s.z + s.dz * s.speed
		var body := _body_on_leg(s, nx, ny, nz, t)
		var wall := lv.ray_hit_wall(s.x, s.y, s.z, nx, ny, nz)
		var sec := lv.span_at(nx, ny, s.z)
		var at = null
		var direct = null
		var face = null
		if not body.is_empty() and (wall.is_empty() or body.u <= wall.t):
			at = body.at
			direct = body.who
		elif not wall.is_empty():
			at = Vector3(wall.x, wall.y, wall.z)
			face = Decals.wall_normal(wall.line, s.x, s.y)
		else:
			s.life -= 1
			if sec == null or nz <= sec.floor + 2.0 or nz >= sec.ceil - 2.0 or s.life <= 0:
				at = Vector3(nx, ny, clampf(nz, sec.floor + 2.0, sec.ceil - 2.0) if sec else nz)
				if sec and nz <= sec.floor + 2.0:
					face = Vector3(0, 0, 1)
		_shed(s, at if at != null else Vector3(nx, ny, nz))
		if at != null:
			shots.remove_at(i)
			detonate(at, direct, face)
			continue
		s.x = nx; s.y = ny; s.z = nz
		game.fx.fireball(s.x - s.dx * 16.0, s.y - s.dy * 16.0, s.z - s.dz * 16.0, 11, 3)

func _shed(s: Dictionary, to: Vector3) -> void:
	var w: Vector2 = game.weather.wind()
	var o := Vector3(s.x - s.dx * 14.0, s.y - s.dy * 14.0, s.z - s.dz * 14.0)
	var e := to - Vector3(s.dx, s.dy, s.dz) * 14.0
	var n := maxi(1, ceili(o.distance_to(e) / TRAIL.step))
	for k in range(1, n + 1):
		var f := float(k) / n
		var p := o.lerp(e, f)
		trail.spawn({
			"x": p.x + (U.p_random() / 255.0 - 0.5) * 3.0, "y": p.y + (U.p_random() / 255.0 - 0.5) * 3.0,
			"z": p.z + (U.p_random() / 255.0 - 0.5) * 3.0,
			"vx": (U.p_random() / 255.0 - 0.5) * 0.4 + w.x * 1.2, "vy": (U.p_random() / 255.0 - 0.5) * 0.4 + w.y * 1.2,
			"vz": 0.12 + (U.p_random() / 255.0) * 0.25,
			"life": TRAIL.life + (U.p_random() % (TRAIL.life >> 1)), "size0": TRAIL.size0, "size1": TRAIL.size1,
			"c0": Color(0.98, 0.9, 0.76, 0.72), "c1": Color(0.56, 0.56, 0.6, 0.0),
			"frame": float(U.p_random() % Effects.SMOKE_PUFFS), "frameRate": 0.08, "drag": 0.965, "gravity": 0.004,
		})

## at where the target WILL BE: led by its own velocity over the time left
func _steer(s: Dictionary, t) -> void:
	var pt := heat_point(t)
	var w := pt - Vector3(s.x, s.y, s.z)
	var d := maxf(1.0, w.length())
	var tgo := minf(MISSILE.lead, d / maxf(1.0, s.speed))
	var v := Vector3(t.get("vx") if "vx" in t else (t.momx if "momx" in t else 0.0),
		t.get("vy") if "vy" in t else (t.momy if "momy" in t else 0.0), 0.0)
	w = (w + v * tgo).normalized()
	var dir := Vector3(s.dx, s.dy, s.dz)
	var ang := acos(clampf(dir.dot(w), -1.0, 1.0))
	if ang > 1e-4:
		var k := minf(1.0, MISSILE.turn / ang)
		dir = (dir + (w - dir) * k).normalized()
		s.dx = dir.x; s.dy = dir.y; s.dz = dir.z

func _body_on_leg(s: Dictionary, nx: float, ny: float, nz: float, target) -> Dictionary:
	var e := Vector3(nx - s.x, ny - s.y, nz - s.z)
	var len2 := e.length_squared()
	if len2 == 0.0:
		len2 = 1.0
	var span := sqrt(len2) + 200.0
	var best := {}
	for a in game.actors:
		if a.removed or a.dead or not a.shootable:
			continue
		if absf(a.x - s.x) > span or absf(a.y - s.y) > span:
			continue
		var pad: float = MISSILE.reach if (target != null and a == target) else 3.0
		var cz: float = a.z + a.height / 2.0
		var u := clampf(((a.x - s.x) * e.x + (a.y - s.y) * e.y + (cz - s.z) * e.z) / len2, 0.0, 1.0)
		var p := Vector3(s.x, s.y, s.z) + e * u
		var r: float = a.radius + pad
		if U.dist2(p.x, p.y, a.x, a.y) > r * r:
			continue
		if p.z < a.z - pad or p.z > a.z + a.height + pad:
			continue
		if best.is_empty() or u < best.u:
			best = {"u": u, "at": p, "who": a}
	return best

func detonate(at: Vector3, direct = null, face = null) -> void:
	var p = game.player
	blasts += 1
	game.play_sound("explode", null)
	booms.append({"x": at.x, "y": at.y, "z": at.z, "t": 0})
	for k in 4:
		game.fx.fireball(at.x, at.y, at.z, 56, 12)
	game.fx.ember(at.x, at.y, at.z, 10, 1.3)
	if face != null:
		game.decals.hole(at, face, true)
	else:
		var under: Level.Sector = game.level.span_at(at.x, at.y, at.z)
		if under and at.z - under.floor < 72.0:
			game.decals.hole(Vector3(at.x, at.y, under.floor), Vector3(0, 0, 1), true)
	game.scare(at.x, at.y, 700.0)
	game.noise(at, 1600.0)
	var hit := {}
	var blown := []
	var R: float = WARHEAD.radius
	for a in game.actors:
		if a.removed or a.dead or not a.shootable or a == direct:
			continue
		var d: float = Vector3(a.x - at.x, a.y - at.y, (a.z + a.height * 0.5) - at.z).length() - a.radius
		if d < R:
			blown.append([a, 1.0 - 0.4 * maxf(0.0, d) / R])
	if direct != null:
		hit[direct] = true
		hits += 1
		blown.append([direct, 1.35])
		direct.damage(WARHEAD.direct, p, {"impact": true, "gib": true})
		if direct.has_method("ignite"):
			direct.ignite(WARHEAD.ignite)
	for a in game.actors:
		if a.removed or a.dead or not a.shootable or hit.has(a):
			continue
		if absf(a.x - at.x) > R + a.radius or absf(a.y - at.y) > R + a.radius:
			continue
		var h := maxf(0.0, sqrt(U.dist2(at.x, at.y, a.x, a.y)) - a.radius)
		var v: float = (a.z - at.z) if at.z < a.z else ((at.z - a.z - a.height) if at.z > a.z + a.height else 0.0)
		var d := Vector2(h, v).length()
		if d >= R:
			continue
		hit[a] = true
		var n := roundi(WARHEAD.splash * (1.0 - d / R))
		if n <= 0:
			continue
		a.damage(n, p, {"impact": true, "gib": true})
		if a.info.get("flammable", false):
			a.ignite(WARHEAD.ignite)
	for b in blown:
		if b[0].dead and game.gore_decals.bleeds(b[0]):
			game.giblets.eviscerate(b[0], at, b[1])
	if p != null and not p.dead:
		var h := maxf(0.0, sqrt(U.dist2(at.x, at.y, p.x, p.y)) - p.radius)
		var v: float = (p.z - at.z) if at.z < p.z else ((at.z - p.z - p.height) if at.z > p.z + p.height else 0.0)
		var d := Vector2(h, v).length()
		if d < R:
			p.damage(roundf(WARHEAD.splash * WARHEAD.self * (1.0 - d / R)), null, {"impact": true})
		shake = minf(1.0, shake + maxf(0.0, 1.0 - d / (R * 4.0)) * 0.8)

func _boom_tic(b: Dictionary) -> void:
	var k: int = b.t - BOOM.tics * 3
	if k < 0 or k >= 8:
		return
	var w: Vector2 = game.weather.wind()
	var a := (U.p_random() / 255.0) * TAU
	var r := (U.p_random() / 255.0) * 30.0
	trail.spawn({
		"x": b.x + cos(a) * r, "y": b.y + sin(a) * r, "z": b.z + 18.0 + k * 7.0,
		"vx": cos(a) * 0.45 + w.x, "vy": sin(a) * 0.45 + w.y, "vz": 0.6 + (U.p_random() / 255.0) * 0.6,
		"life": 90 + (U.p_random() % 50), "size0": 36.0, "size1": 120.0,
		"c0": Color(0.30, 0.28, 0.26, 0.72), "c1": Color(0.46, 0.46, 0.5, 0.0),
		"frame": float(U.p_random() % Effects.SMOKE_PUFFS), "frameRate": 0.06, "drag": 0.97, "gravity": 0.003,
	})

## the trail, the reticles over the locks, the rockets and their flares, the booms
func draw(cam: Camera3D) -> void:
	trail.draw()
	im.clear_surfaces()
	im_top.clear_surfaces()
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	var marks := []
	if active():
		for l in locks:
			var found := false
			for m in marks:
				if m.t == l.t:
					m.n += 1
					found = true
			if not found:
				marks.append({"t": l.t, "n": 1})
		if acquiring != null and not marks.any(func(m): return m.t == acquiring):
			marks.append({"t": acquiring, "n": 0})
	if not marks.is_empty():
		im_top.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for m in marks:
			var pt := heat_point(m.t)
			var at := U.v3(pt.x, pt.y, pt.z)
			var d := at.distance_to(cam.global_position)
			var col := Color(1.0, 0.25, 0.1) if m.n > 0 else Color(1.0, 0.8, 0.2)
			if m.n == 0 and (game.tics >> 1) & 1:
				continue
			var sz: float = d * 0.03 * ((2.2 - 1.2 * acquire_fraction()) if m.n == 0 else (1.0 + 0.22 * (m.n - 1)))
			# four corner brackets
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var o: Vector3 = at + right * c.x * sz + up * c.y * sz
				var hx: Vector3 = -right * c.x * sz * 0.45
				var hy: Vector3 = -up * c.y * sz * 0.45
				var th: float = sz * 0.09
				for seg in [[o, o + hx, up * th], [o, o + hy, right * th]]:
					var a: Vector3 = seg[0]
					var b: Vector3 = seg[1]
					var n: Vector3 = seg[2]
					for v in [a - n, b - n, b + n, a - n, b + n, a + n]:
						im_top.surface_set_color(col)
						im_top.surface_add_vertex(v)
		im_top.surface_end()
	if not shots.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for s in shots:
			var c := U.v3(s.x, s.y, s.z)
			var dir := U.v3(s.dx, s.dy, s.dz).normalized()
			var side := dir.cross(c - cam.global_position).normalized() * 2.5
			var tail := c - dir * 18.0
			for v in [tail - side, c - side, c + side, tail - side, c + side, tail + side]:
				im.surface_set_color(Color(0.45, 0.45, 0.42))
				im.surface_add_vertex(v)
			var f := tail - dir * 4.0
			var fs := side * 1.8
			var fu := dir.cross(side).normalized() * 4.5
			for v in [f - fs - fu, f + fs - fu, f + fs + fu, f - fs - fu, f + fs + fu, f - fs + fu]:
				im.surface_set_color(Color(1.0, 0.85, 0.4))
				im.surface_add_vertex(v)
		im.surface_end()
	boom_mm.visible_instance_count = mini(booms.size(), 16)
	for i in boom_mm.visible_instance_count:
		var b: Dictionary = booms[i]
		boom_mm.set_instance_transform(i, Transform3D(Basis(), U.v3(b.x, b.y, b.z)))
		boom_mm.set_instance_color(i, Color(1, 1, 1, 1))
		var f := mini(BOOM.frames - 1, b.t / BOOM.tics)
		boom_mm.set_instance_custom_data(i, Color(BOOM.size, float(f), 0, 0))
