## MEWD — the arc maw (js/arc.js).
##
## HOLD to charge — three seconds to full — and LET GO: a bolt leaves the
## maw for whoever is nearest the sight, and from them to whoever is
## nearest them, up to nine at the top of the charge, each hop a little
## weaker; every strike throws a FIELD that catches anybody standing
## close, and sometimes BRANCHES that reach for somebody the chain did
## not. Nothing reached, and the bolt goes down the sight to the wall.
## The bolts are jagged lines rebuilt every other tic — a flicker, not
## an animation — drawn additive, with sparks and falling drips.
class_name ArcSystem
extends Node3D

const ARC := {
	"chargeTics": 105, "most": 9, "range": 2400.0, "cone": 0.15, "chain": 560.0, "field": 150.0,
	"fieldShare": 0.4, "fieldMost": 5, "damage0": 48.0, "damage1": 190.0, "falloff": 0.92, "hopTics": 1,
	"subChance0": 0.35, "subChance1": 0.8, "subMost": 3, "subReach": 430.0, "subShare": 0.55, "life": 16,
}
const SEG := 26.0
const NEAR := 160.0

var game
var bolts := []
var drips := []
var fired := 0
var strikes := 0
var last_chain := []
var subs := 0
var bonus_kills := 0
var shake := 0.0
var sparks: Particles
var glows: Particles
var im := ImmediateMesh.new()

static func hits_for(charge: float) -> int:
	return 1 + roundi(clampf(charge, 0.0, 1.0) * (ARC.most - 1))

static func strike_damage(charge: float, hop := 0) -> float:
	return (ARC.damage0 + (ARC.damage1 - ARC.damage0) * clampf(charge, 0.0, 1.0)) * pow(ARC.falloff, hop)

func _init(g) -> void:
	game = g

func _ready() -> void:
	var at := Effects.atlases()
	sparks = Particles.new({"max": 2600, "map": at.spark, "frames": 1, "blend": "add", "near_shrink": 120.0})
	glows = Particles.new({"max": 160, "map": at.smoke, "frames": Effects.SMOKE_PUFFS, "blend": "add", "near_shrink": 90.0})
	add_child(sparks)
	add_child(glows)
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = m
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	add_child(mi)

func can_strike(a) -> bool:
	return a != null and a.shootable and not a.dead and not a.removed

func chest(a) -> Vector3:
	return Vector3(a.x, a.y, a.z + a.height * 0.58)

func _first_target(p):
	var cp := cos(p.pitch)
	var d := Vector3(cos(p.angle) * cp, sin(p.angle) * cp, sin(p.pitch))
	var eye := Vector3(p.x, p.y, p.eye_z())
	var best = null
	var score := INF
	for a in game.actors:
		if not can_strike(a):
			continue
		var c := chest(a)
		var v := c - eye
		var l := v.length()
		if l < 1.0 or l > ARC.range:
			continue
		var off := acos(clampf(v.dot(d) / l, -1.0, 1.0))
		if off > ARC.cone:
			continue
		var s: float = off + (l / ARC.range) * 0.04
		if s >= score:
			continue
		if game.level.sight_blocked(p.x, p.y, p.eye_z(), c.x, c.y, c.z):
			continue
		best = a
		score = s
	return best

func _next_target(from: Vector3, struck: Dictionary):
	var best = null
	var bd: float = ARC.chain * ARC.chain
	for a in game.actors:
		if not can_strike(a) or struck.has(a):
			continue
		var c := chest(a)
		var d2 := c.distance_squared_to(from)
		if d2 >= bd:
			continue
		if game.level.sight_blocked(from.x, from.y, from.z, c.x, c.y, c.z):
			continue
		best = a
		bd = d2
	return best

func _sight_end(p) -> Vector3:
	var cp := cos(p.pitch)
	var e := Vector3(p.x, p.y, p.eye_z())
	var b := e + Vector3(cos(p.angle) * cp, sin(p.angle) * cp, sin(p.pitch)) * ARC.range
	var w: Dictionary = game.level.ray_hit_wall(e.x, e.y, e.z, b.x, b.y, b.z)
	var t: float = w.t if not w.is_empty() else 1.0
	var qz := e.z
	for k in range(1, 49):
		var f := (k / 48.0) * t
		var q := e.lerp(b, f)
		# the storey the last sample was in (a map in storeys)
		var s: Level.Sector = game.level.span_at(q.x, q.y, qz)
		qz = q.z
		if s and (q.z <= s.floor + 1.0 or q.z >= s.ceil - 1.0):
			t = f
			break
	return e.lerp(b, t)

## The player's side (js/player.js arcTic): hold to wind it, let go to throw it.
func player_tic(p, attack: bool) -> void:
	if p.fire_index >= 0:
		p.fire_tics -= 1
		if p.fire_tics <= 0:
			p.fire_index = -1
	if attack:
		if not p.arc_charging and p.ammo.volts <= 0:
			if not p.clicked:
				p.clicked = true
				game.play_sound("noammo", p)
			return
		if not p.arc_charging:
			p.arc_charging = true
			p.arc_charge = 0.0
		var was: float = p.arc_charge
		p.arc_charge = minf(1.0, p.arc_charge + 1.0 / ARC.chargeTics)
		var step := "arccharge1" if p.arc_charge < 0.34 else ("arccharge2" if p.arc_charge < 0.67 else "arccharge3")
		if was < 1.0 and p.arc_charge >= 1.0:
			game.play_sound("arcfull", p)
		elif game.tics % 9 == 0:
			game.play_sound(step, p)
		return
	p.clicked = false
	if p.arc_charging:
		p.arc_charging = false
		var charge: float = p.arc_charge
		p.arc_charge = 0.0
		p.ammo.volts = maxi(0, p.ammo.volts - 1)
		if p.ammo.volts <= 0:
			p.dry["volts"] = true
		p.shots_fired += 1
		p.fire_index = 1
		p.fire_tics = 5
		fire(p, charge)
		return
	if p.pending_weapon != "" and p.fire_index < 0:
		p.weapon = p.pending_weapon
		p.pending_weapon = ""

func fire(p, charge: float) -> int:
	fired += 1
	var n := hits_for(charge)
	var from: Vector3 = game.nozzle(p)
	var nodes := [{"p": from, "who": null, "muzzle": true}]
	var struck := {}
	var at = _first_target(p)
	while at != null and struck.size() < n:
		struck[at] = true
		nodes.append({"p": chest(at), "who": at})
		at = _next_target(nodes[nodes.size() - 1].p, struck)
	if struck.is_empty():
		nodes.append({"p": _sight_end(p), "who": null})
	last_chain = struck.keys()
	var b := {"nodes": nodes, "reveal": 0, "t": 0, "charge": charge, "struck": struck,
		"seed": (U.p_random() << 8) | U.p_random(), "fields": [], "subs": []}
	bolts.append(b)
	game.play_sound("arcbig" if charge > 0.6 else "arcfire", null)
	game.noise(p, 1400.0 + 1200.0 * charge)
	shake = maxf(shake, 0.25 + 0.5 * charge)
	_strike(b, 1)
	return struck.size()

func _strike(b: Dictionary, i: int) -> void:
	var p = game.player
	if i >= b.nodes.size():
		return
	var node: Dictionary = b.nodes[i]
	b.reveal = i
	var a = node.who
	if a != null:
		node.p = chest(a)
	var np: Vector3 = node.p
	_burst(np, 0.6 + 0.6 * b.charge)
	if a != null:
		var dmg := strike_damage(b.charge, i - 1)
		strikes += 1
		if can_strike(a):
			a.damage(_lethal(a, dmg), p, {"shock": true})
		var drawn := 0
		for o in game.actors:
			if o == a or b.struck.has(o) or not can_strike(o):
				continue
			var c := chest(o)
			var d := c.distance_to(np)
			if d > ARC.field:
				continue
			strikes += 1
			o.damage(_lethal(o, dmg * ARC.fieldShare * (1.0 - 0.5 * d / ARC.field)), p, {"shock": true})
			if drawn < ARC.fieldMost:
				drawn += 1
				b.fields.append({"a": np, "who": o, "t": 0})
				_burst(c, 0.35)
		_branch(b, np, dmg)
		game.play_sound("arczap", null)

func _branch(b: Dictionary, np: Vector3, dmg: float) -> void:
	var p = game.player
	var chance: float = ARC.subChance0 + (ARC.subChance1 - ARC.subChance0) * b.charge
	var n := 0
	while n < ARC.subMost and U.p_random() / 256.0 < chance * (0.6 if n else 1.0):
		n += 1
	if n == 0:
		return
	var near := []
	for o in game.actors:
		if not can_strike(o) or b.struck.has(o):
			continue
		var c := chest(o)
		if c.distance_to(np) > ARC.subReach:
			continue
		if game.level.sight_blocked(np.x, np.y, np.z, c.x, c.y, c.z):
			continue
		near.append(o)
	for k in n:
		subs += 1
		if not near.is_empty():
			var o = near[U.p_random() % near.size()]
			near.erase(o)
			b.subs.append({"a": np, "who": o, "to": null, "t": 0, "seed": (U.p_random() << 8) | U.p_random()})
			strikes += 1
			o.damage(_lethal(o, dmg * ARC.subShare), p, {"shock": true})
			if o.dead:
				bonus_kills += 1
			_burst(chest(o), 0.45)
		else:
			var ang := (U.p_random() / 256.0) * TAU
			var r := 50.0 + (U.p_random() / 256.0) * 150.0
			var x := np.x + cos(ang) * r
			var y := np.y + sin(ang) * r
			var s: Level.Sector = game.level.span_at(x, y, np.z)
			if s == null:
				continue
			b.subs.append({"a": np, "who": null, "to": Vector3(x, y, s.floor), "t": 0, "seed": (U.p_random() << 8) | U.p_random()})
			_burst(Vector3(x, y, s.floor + 2.0), 0.3)

## no more than it takes: a strike does not waste itself on the dead
func _lethal(a, dmg: float) -> float:
	var has: float = a.health + (a.armour1 if "armour1" in a else 0) + (a.armour2 if "armour2" in a else 0)
	return minf(dmg, maxf(1.0, has + 4.0))

func _burst(at: Vector3, size := 1.0) -> void:
	for k in 3:
		glows.spawn({"x": at.x, "y": at.y, "z": at.z, "vz": 0.2, "life": 7 + k * 3,
			"size0": (28.0 + k * 26.0) * size, "size1": (70.0 + k * 30.0) * size,
			"c0": Color(0.55, 0.78, 1.0, 1.0), "c1": Color(0.05, 0.18, 0.6, 0.0),
			"frame": float(U.p_random() % Effects.SMOKE_PUFFS), "frameRate": 0.3})
	for k in roundi(22.0 * size):
		var a := (U.p_random() / 255.0) * TAU
		var e := (U.p_random() / 255.0) * 1.2 - 0.2
		var sp := 2.0 + (U.p_random() / 255.0) * 7.0 * size
		sparks.spawn({"x": at.x, "y": at.y, "z": at.z,
			"vx": cos(a) * cos(e) * sp, "vy": sin(a) * cos(e) * sp, "vz": sin(e) * sp + 1.5,
			"life": 10 + (U.p_random() % 14), "size0": 3.2, "size1": 1.2,
			"c0": Color(0.85, 0.95, 1.0, 1.0), "c1": Color(0.15, 0.35, 1.0, 0.2), "drag": 0.93, "gravity": -0.32})
	for k in roundi(4.0 * size):
		_drip(at, 3.0 + 3.0 * size)

func _drip(at: Vector3, speed := 3.0) -> void:
	if drips.size() > 220:
		return
	var a := (U.p_random() / 255.0) * TAU
	var sp := (0.3 + U.p_random() / 255.0) * speed
	drips.append({"x": at.x, "y": at.y, "z": at.z, "vx": cos(a) * sp, "vy": sin(a) * sp,
		"vz": 1.0 + (U.p_random() / 255.0) * 3.0, "life": 40 + (U.p_random() % 40), "bounced": false})

func tic() -> void:
	sparks.tic()
	glows.tic()
	shake = maxf(0.0, shake - 0.05)
	for k in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[k]
		b.t += 1
		var want := mini(b.nodes.size() - 1, 1 + b.t / ARC.hopTics)
		while b.reveal < want:
			_strike(b, b.reveal + 1)
		for n in b.nodes:
			if n.who != null and not n.who.removed:
				n.p = chest(n.who)
		for f in b.fields:
			f.t += 1
		for sb in b.subs:
			sb.t += 1
			if sb.t < ARC.life and (U.p_random() & 7) == 0:
				var to: Vector3 = chest(sb.who) if sb.who != null else sb.to
				_drip(sb.a.lerp(to, U.p_random() / 256.0), 1.6)
		for i in range(1, b.reveal + 1):
			if (U.p_random() & 3) != 0:
				continue
			var q: Vector3 = b.nodes[i - 1].p.lerp(b.nodes[i].p, U.p_random() / 255.0)
			_drip(q, 2.2)
			sparks.spawn({"x": q.x, "y": q.y, "z": q.z, "vz": -0.5, "life": 16, "size0": 2.6, "size1": 1.0,
				"c0": Color(0.8, 0.92, 1.0, 1.0), "c1": Color(0.1, 0.3, 1.0, 0.0), "drag": 0.96, "gravity": -0.28})
		if b.reveal >= b.nodes.size() - 1 and b.t > (b.nodes.size() - 1) * ARC.hopTics + ARC.life:
			bolts.remove_at(k)
	for i in range(drips.size() - 1, -1, -1):
		var d: Dictionary = drips[i]
		d.vz -= 0.36
		d.vx *= 0.985
		d.vy *= 0.985
		d.x += d.vx
		d.y += d.vy
		d.z += d.vz
		var s: Level.Sector = game.level.span_at(d.x, d.y, d.z - d.vz)
		if s and d.z <= s.floor:
			if d.bounced or d.vz > -2.5:
				drips.remove_at(i)
				continue
			d.z = s.floor
			d.vz *= -0.35
			d.bounced = true
		d.life -= 1
		if d.life <= 0:
			drips.remove_at(i)
			continue
		sparks.spawn({"x": d.x, "y": d.y, "z": d.z, "life": 12, "size0": 2.8, "size1": 0.6,
			"c0": Color(0.75, 0.9, 1.0, 0.95), "c1": Color(0.08, 0.2, 0.85, 0.0)})

## a jagged run from A to B, seeded, tapering to nothing at both ends
func _jag(A: Vector3, B: Vector3, seed: int, rough: float) -> PackedVector3Array:
	var s := seed & 0xFFFFFFFF
	if s == 0:
		s = 1
	var d := B - A
	var L := maxf(d.length(), 1.0)
	var u := Vector3(-d.y, d.x, 0.0)
	if u.length() < 1e-3:
		u = Vector3(1, 0, 0)
	u = u.normalized()
	var v := d.cross(u) / L
	var n := clampi(roundi(L / SEG), 3, 48)
	var out := PackedVector3Array()
	var ox := 0.0
	var oy := 0.0
	for i in n + 1:
		var f := float(i) / n
		s ^= (s << 13) & 0xFFFFFFFF
		s ^= s >> 17
		s ^= (s << 5) & 0xFFFFFFFF
		var r1 := float(s) / 4294967296.0 - 0.5
		s ^= (s << 13) & 0xFFFFFFFF
		s ^= s >> 17
		s ^= (s << 5) & 0xFFFFFFFF
		var r2 := float(s) / 4294967296.0 - 0.5
		ox = ox * 0.55 + r1 * rough * L * 0.16
		oy = oy * 0.55 + r2 * rough * L * 0.16
		var e := 0.0 if (i == 0 or i == n) else sin(PI * f)
		out.append(A + d * f + (u * ox + v * oy) * e)
	return out

func draw(cam: Camera3D) -> void:
	sparks.draw()
	glows.draw()
	im.clear_surfaces()
	if bolts.is_empty():
		return
	var eye := cam.global_position
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var tick: int = game.tics >> 1
	for b in bolts:
		var end: int = (b.nodes.size() - 1) * ARC.hopTics
		var f: float = 1.0 if b.t <= end else clampf(1.0 - float(b.t - end) / ARC.life, 0.0, 1.0)
		var fl: float = f * (0.7 + 0.3 * (((tick * 7 + b.seed) % 5) / 4.0))
		var wide: float = 1.0 + 1.2 * b.charge
		for i in range(1, b.reveal + 1):
			var A: Vector3 = b.nodes[i - 1].p
			var B: Vector3 = b.nodes[i].p
			var seed: int = b.seed * 31 + i * 977 + tick * 131
			var P := _jag(A, B, seed, 1.0)
			_line(P, 7.0 * wide, 1.3 * wide, fl, eye)
			for k in 2:
				var j := 1 + ((seed >> (k * 5)) % maxi(1, P.size() - 2))
				var L := A.distance_to(B) * 0.28
				var fk := P[j] + Vector3(((seed * (k + 3) * 11) >> 7) % 1000 / 1000.0 - 0.5,
					((seed * (k + 3) * 17) >> 7) % 1000 / 1000.0 - 0.5, ((seed * (k + 3) * 23) >> 7) % 1000 / 1000.0 - 0.5 - 0.3) * L
				_line(_jag(P[j], fk, seed + k * 7, 1.4), 3.5 * wide, 0.8 * wide, fl * 0.7, eye)
		for sb in b.subs:
			if sb.t > ARC.life:
				continue
			var to: Vector3 = chest(sb.who) if sb.who != null else sb.to
			_line(_jag(sb.a, to, sb.seed * 7 + tick * 57, 1.25), 3.6, 0.75, fl * (1.0 - sb.t / (ARC.life + 1.0)), eye)
		for fd in b.fields:
			if fd.t > ARC.life or fd.who == null:
				continue
			_line(_jag(fd.a, chest(fd.who), b.seed + fd.t * 13 + tick, 1.3), 3.2, 0.7, fl * (1.0 - float(fd.t) / ARC.life), eye)
	im.surface_end()

func _line(P: PackedVector3Array, w_glow: float, w_core: float, f: float, eye: Vector3) -> void:
	for i in range(1, P.size()):
		_quad(P[i - 1], P[i], w_glow, f * 0.55, false, eye)
		_quad(P[i - 1], P[i], w_core, f, true, eye)

func _quad(a: Vector3, b: Vector3, w: float, f: float, core: bool, eye: Vector3) -> void:
	var A := U.v3(a.x, a.y, a.z)
	var B := U.v3(b.x, b.y, b.z)
	var near := A.distance_to(eye)
	if near < NEAR:
		w *= maxf(0.06, near / NEAR)
	var side := (B - A).cross(eye - A).normalized() * w
	var c := Color(0.86, 0.94, 1.0) if core else Color(0.16, 0.42, 1.0) * 0.55
	c = Color(c.r * f, c.g * f, c.b * f, 1.0)
	for v in [A - side, A + side, B + side, A - side, B + side, B - side]:
		im.surface_set_color(c)
		im.surface_add_vertex(v)
