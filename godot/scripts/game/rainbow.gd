## MEWD — THE UNICORNS FIGHT BACK (at the user's request: "make the
## unicorns fight back, use this animation facing the player when they
## fire at the player, have them shoot a linear mesh based rainbow death
## beam with spark particles and other appropriate particle effects / hit
## effects").
##
## A unicorn the player hurts — and her herd round her — turns on them
## (Actor.A_UniAim and the rest, actor.gd): she stops, faces the eye in
## her firing picture (Standees "UNIF": eyes alight, mouth open), draws
## the charge in at her mouth, and throws a BEAM from it for a second.
## The beam here: one per unicorn firing, from her mouth along a line
## that SWINGS after the player (UNI.turn radians a tic, so it can be
## run from), stopped at the first house wall or the ground. Whoever
## stands in it — the player, within UNI.hit_r of the line — takes
## UNI.damage a tic.
##
## HOW IT IS DRAWN: a TUBE (real geometry, as the lance's is — a quad
## seen end-on is a line), SIDES round, a ring every SEG units, two
## shells: a white-hot core and a rainbow sheath (rainbow_beam.gdshader:
## the whole wheel along it, streaming away from her, bands running down
## it), the radius breathing along its length. Rebuilt every frame in one
## ImmediateMesh. AND ROUND IT: rainbow sparks thrown off along the line,
## a glow at her mouth; where it lands a burst of rainbow sparks, a bright
## glow, embers, smoke, and a scorch left in the ground every few tics;
## on the player a bigger burst.
class_name RainbowBeams
extends Node3D

## (THE BALANCE, at the user's request, now that health is finite and
## armour is on top of it — GODOT.txt, PICKUPS: a full second of glow
## before she fires; 60 m and no further, so she is never an 8-pixel
## sniper; a fifth of the beam's old bite, 35 a beam, so a fresh body
## takes four; a line a little slower after you, so strafing out of it
## works at 13 m; a ram of 20 and a gentler shove; and a gallop still
## faster than your run, so you cannot just run away)
const UNI := {
	"charge_tics": 35,     # facing the eye, drawing it in, before it fires
	"beam_tics": 35,       # the beam: a second
	"range": 1920.0,       # units it reaches, and she will fire from
	"radius": 7.0,         # the sheath, units (the core a third of it)
	"hit_r": 22.0,         # within this of the line, the player is in it
	"damage": 1.0,         # a tic, to the player (35 over a whole beam)
	"wobble_tics": 18,     # the screen swims this long after a tic in it
	"turn": 0.028,         # radians a tic the line swings after the player
	"mark_every": 5,       # a scorch where it lands, every this many tics
	# AND SHE CHARGES (at the user's request: "have the unicorns in attack
	# mode charge the player"): after a beam she gallops straight at them
	# (Actor.A_UniCharge) for `run_tics` at `run_speed` times her gallop,
	# and if she reaches them she RAMS them: `ram_damage`, thrown back
	# `ram_push` units a tic
	"run_tics": 70,
	"run_speed": 1.15,
	"ram_reach": 26.0,     # past the two radii, units
	"ram_damage": 20.0,
	"ram_push": 10.0,
}
const SIDES := 10
const SEG := 48.0
const NEAR := 240.0

var game
var beams := []
var fired := 0
var hits := 0
var marks := 0
var sparks: Particles
var glows: Particles
var im := ImmediateMesh.new()
var mat: ShaderMaterial

func _init(g) -> void:
	game = g

func _ready() -> void:
	var at := Effects.atlases()
	sparks = Particles.new({"max": 2400, "map": at.spark, "frames": 1, "blend": "add", "near_shrink": 120.0})
	glows = Particles.new({"max": 200, "map": at.smoke, "frames": Effects.SMOKE_PUFFS, "blend": "add", "near_shrink": 90.0})
	add_child(sparks)
	add_child(glows)
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/rainbow_beam.gdshader")
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

static func rainbow(h: float, a := 1.0) -> Color:
	var c := Color.from_hsv(fposmod(h, 1.0), 0.8, 1.0)
	c.a = a
	return c

## her mouth, where the beam comes from (map units): the firing picture's
## own mouth, a little out in front of her toward the eye
static func mouth(u) -> Vector3:
	var a: float = u.angle
	return Vector3(u.x + cos(a) * 10.0, u.y + sin(a) * 10.0, u.z + u.height * Standees.UNIF_MOUTH)

## the player's chest
static func chest(p) -> Vector3:
	return Vector3(p.x, p.y, p.z + U.PLAYER_EYE * 0.75)

## THE CHARGE, a tic of it: the glow swelling at her mouth, sparks drawn
## in to it from round her.
func charge(u, k: float) -> void:
	var m := mouth(u)
	if game.tics % 2 == 0:
		glows.spawn({"x": m.x, "y": m.y, "z": m.z, "life": 6, "size0": 10.0 + 26.0 * k, "size1": 18.0 + 30.0 * k,
			"c0": rainbow(game.tics * 0.03, 1.0), "c1": Color(1, 1, 1, 0), "frame": float(U.p_random() % Effects.SMOKE_PUFFS),
			"frameRate": 0.3})
	for i in 2:
		var a := (U.p_random() / 255.0) * TAU
		var e := (U.p_random() / 255.0) * 2.0 - 1.0
		var r := 40.0 + (U.p_random() / 255.0) * 30.0
		var off := Vector3(cos(a) * cos(e), sin(a) * cos(e), sin(e)) * r
		sparks.spawn({"x": m.x + off.x, "y": m.y + off.y, "z": m.z + off.z,
			"vx": -off.x / 9.0, "vy": -off.y / 9.0, "vz": -off.z / 9.0, "life": 9, "size0": 1.6, "size1": 3.2,
			"c0": rainbow((U.p_random() / 255.0), 1.0), "c1": Color(1, 1, 1, 0.6), "drag": 1.0, "gravity": 0.0})

## A beam lit from unicorn `u` at the player: her line starts on them.
## `p` the one she is after (the line swings after them); `ghost`, a beam
## only drawn — a network client's, from what the host says a unicorn is
## doing: the host's beam is the one that hurts (NetGame)
func fire(u, p, ghost := false) -> Dictionary:
	var m := mouth(u)
	var b := {"u": u, "p": p, "ghost": ghost, "dir": (chest(p) - m).normalized() if p != null else Vector3(cos(u.angle), sin(u.angle), 0.0),
		"t": 0, "from": m, "to": m, "seed": U.p_random()}
	beams.append(b)
	fired += 1
	_burst(m, 0.7, false)
	# (the lance's own shot, pitched up: a sweeter, nastier thing)
	if game.sound != null:
		game.sound.play("lancefire2", u, {"rate": 1.6})
	return b

func stop(u) -> void:
	for b in beams:
		if b.u == u:
			b.t = UNI.beam_tics

func firing(u) -> bool:
	for b in beams:
		if b.u == u and b.t < UNI.beam_tics:
			return true
	return false

func tic() -> void:
	sparks.tic()
	glows.tic()
	for i in range(beams.size() - 1, -1, -1):
		var b: Dictionary = beams[i]
		var p = b.get("p")
		if p != null and (p.get("removed") == true):
			p = null
		b.t += 1
		var u = b.u
		if b.t > UNI.beam_tics or u == null or u.removed or u.dead or u.held():
			beams.remove_at(i)
			continue
		var m := mouth(u)
		b.from = m
		# THE LINE SWINGS AFTER THE PLAYER, a little a tic
		if p != null and not p.dead:
			var want: Vector3 = (chest(p) - m).normalized()
			var ang := (b.dir as Vector3).angle_to(want)
			if ang > 1e-4:
				b.dir = (b.dir as Vector3).slerp(want, minf(1.0, UNI.turn / ang)).normalized()
		var end: Vector3 = m + b.dir * UNI.range
		var hit := _cast(m, end)
		b.to = hit.at
		# IT GOES THROUGH THEM (at the user's request: "make sure the unicorn
		# beams shoot through the player"): the line is never stopped by the
		# player, only by a wall or the ground behind them; drawn with a gap
		# round the eye only (a tube that runs into the eye is a white wall),
		# coming out again behind
		b.gap = Vector2(-1.0, -1.0)
		var me = game.player
		if me != null and not me.dead:
			var eye := Vector3(me.x, me.y, me.view_z if "view_z" in me else me.z + U.PLAYER_EYE)
			var along: float = (eye - m).dot(b.dir)
			if along > 0.0 and along < m.distance_to(b.to) + 40.0 and (m + b.dir * along).distance_to(eye) < 60.0:
				b.gap = Vector2(maxf(0.0, along - 70.0), along + 70.0)
		# WHOEVER STANDS IN IT — any player, not only the one she is after
		# (and nobody, for a beam only drawn: the host's hurts)
		if not b.ghost:
			for q in game.players:
				if q == null or q.dead or q.invincible or q.cheat:
					continue
				var c := chest(q)
				var seg: Vector3 = b.to - m
				var t := clampf((c - m).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
				var near := m + seg * t
				if near.distance_to(c) < UNI.hit_r + q.radius * 0.5:
					q.damage(game.rules.scale(u, q, UNI.damage) if game.rules != null else UNI.damage, u, {"impact": true, "rainbow": true})
					hits += 1
					# the screen swims (Lofi wobble, game.screen_wobble)
					if "wobble" in q:
						q.wobble = UNI.wobble_tics
					if b.t % 3 == 0:
						_burst(near, 0.8, true)
					# and out of their back: sparks thrown on along the line
					_exit(c, b.dir)
		elif me != null and not me.dead:
			# (the look of being in it, on this machine: the host says what
			# it did)
			var c := chest(me)
			var seg: Vector3 = b.to - m
			var t := clampf((c - m).dot(seg) / maxf(seg.length_squared(), 1.0), 0.0, 1.0)
			if (m + seg * t).distance_to(c) < UNI.hit_r + me.radius * 0.5 and "wobble" in me:
				me.wobble = UNI.wobble_tics
		_effects(b, hit)

## where the line from a to b stops: the first house wall or the ground
func _cast(a: Vector3, b: Vector3) -> Dictionary:
	var lv = game.level
	var best_t := 1.0
	var n := Vector3.ZERO
	var w: Dictionary = lv.ray_hit_wall(a.x, a.y, a.z, b.x, b.y, b.z)
	if not w.is_empty() and w.t < best_t:
		best_t = w.t
		var d := Vector3(b.x - a.x, b.y - a.y, 0.0).normalized()
		n = -d
	if lv.has_method("ray_hit_flat"):
		var f: Dictionary = lv.ray_hit_flat(a.x, a.y, a.z, b.x, b.y, b.z)
		if not f.is_empty() and f.t < best_t:
			best_t = f.t
			n = Vector3(0, 0, 1)
	return {"at": a.lerp(b, best_t), "n": n}

## the sparks along it and the burst where it lands
func _effects(b: Dictionary, hit: Dictionary) -> void:
	var m: Vector3 = b.from
	var e: Vector3 = b.to
	var L := m.distance_to(e)
	var d := (e - m) / maxf(L, 1.0)
	# off the line, all along it: rainbow sparks thrown out sideways
	for k in 6:
		var f := U.p_random() / 255.0
		var q := m + d * L * f
		var a := (U.p_random() / 255.0) * TAU
		var side := d.cross(Vector3(cos(a), sin(a), 0.3)).normalized()
		var sp := 1.5 + (U.p_random() / 255.0) * 3.0
		sparks.spawn({"x": q.x, "y": q.y, "z": q.z, "vx": side.x * sp + d.x, "vy": side.y * sp + d.y, "vz": side.z * sp + 0.8,
			"life": 10 + (U.p_random() % 10), "size0": 2.4, "size1": 0.8,
			"c0": rainbow(f * 2.0 - game.tics * 0.05, 1.0), "c1": rainbow(f * 2.0 + 0.3, 0.0), "drag": 0.94, "gravity": -0.12})
	# a glow at her mouth
	if game.tics % 2 == 0:
		glows.spawn({"x": m.x, "y": m.y, "z": m.z, "life": 5, "size0": 30.0, "size1": 44.0,
			"c0": rainbow(game.tics * 0.04, 1.0), "c1": Color(1, 1, 1, 0), "frame": float(U.p_random() % Effects.SMOKE_PUFFS), "frameRate": 0.3})
	# AND WHERE IT LANDS, if it lands
	if hit.n != Vector3.ZERO:
		_burst(e, 1.0, false)
		if game.tics % 4 == 0:
			game.fx.puff(e.x, e.y, e.z + 8.0, 24.0, 70)
			game.fx.ember(e.x, e.y, e.z + 4.0, 3, 1.4)
		if b.t % UNI.mark_every == 1 and game.decals != null:
			game.decals.scorch(e, hit.n, 34.0 + (U.p_random() % 20))
			marks += 1
		if game.veg_damage != null and b.t % 6 == 0:
			game.veg_damage.blast(e, 60.0)

## out of the player's back, on the way the beam was going
func _exit(at: Vector3, d: Vector3) -> void:
	for k in 4:
		var a := (U.p_random() / 255.0) * TAU
		var side := d.cross(Vector3(cos(a), sin(a), 0.4)).normalized()
		var sp := 6.0 + (U.p_random() / 255.0) * 8.0
		var o := at + d * (20.0 + (U.p_random() / 255.0) * 40.0)
		sparks.spawn({"x": o.x, "y": o.y, "z": o.z, "vx": d.x * sp + side.x * 2.0, "vy": d.y * sp + side.y * 2.0,
			"vz": d.z * sp + side.z * 2.0 + 0.6, "life": 12 + (U.p_random() % 10), "size0": 3.0, "size1": 1.0,
			"c0": rainbow((U.p_random() / 255.0), 1.0), "c1": rainbow((U.p_random() / 255.0), 0.0), "drag": 0.95, "gravity": -0.2})

func _burst(at: Vector3, size: float, body: bool) -> void:
	var h := (U.p_random() / 255.0)
	glows.spawn({"x": at.x, "y": at.y, "z": at.z, "vz": 0.3, "life": 6 + (U.p_random() % 4),
		"size0": 30.0 * size, "size1": 70.0 * size, "c0": rainbow(h, 1.0), "c1": Color(1, 1, 1, 0),
		"frame": float(U.p_random() % Effects.SMOKE_PUFFS), "frameRate": 0.3})
	for k in roundi((10.0 if body else 7.0) * size):
		var a := (U.p_random() / 255.0) * TAU
		var e := (U.p_random() / 255.0) * 1.3 - 0.2
		var sp := 2.0 + (U.p_random() / 255.0) * 6.0 * size
		sparks.spawn({"x": at.x, "y": at.y, "z": at.z,
			"vx": cos(a) * cos(e) * sp, "vy": sin(a) * cos(e) * sp, "vz": sin(e) * sp + 1.2,
			"life": 10 + (U.p_random() % 16), "size0": 3.0, "size1": 1.0,
			"c0": rainbow(h + k * 0.09, 1.0), "c1": rainbow(h + k * 0.09 + 0.2, 0.2), "drag": 0.93, "gravity": -0.3})

func draw(cam: Camera3D) -> void:
	sparks.draw()
	glows.draw()
	mat.set_shader_parameter("now", U.col(Time.get_ticks_msec() / 1000.0))
	im.clear_surfaces()
	if beams.is_empty():
		return
	var eye := cam.position
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in beams:
		var t: int = b.t
		# in hard, out over the last few tics
		var f := clampf(minf(t / 3.0, (UNI.beam_tics - t) / 6.0), 0.0, 1.0)
		if f <= 0.0:
			continue
		var wob := 0.85 + 0.15 * sin(game.tics * 1.7 + b.seed)
		var g: Vector2 = b.get("gap", Vector2(-1.0, -1.0))
		var spans := [[b.from, b.to]]
		if g.y > 0.0:
			var L: float = (b.from as Vector3).distance_to(b.to)
			spans = [[b.from, b.from + b.dir * minf(g.x, L)]]
			if g.y < L:
				spans.append([b.from + b.dir * g.y, b.to])
		for sp in spans:
			_tube(sp[0], sp[1], UNI.radius * wob, 0.0, f, eye)
			_tube(sp[0], sp[1], UNI.radius * 0.36 * wob, 1.0, f, eye)
	im.surface_end()

## one shell of the tube from a to b (map units), `r` across, `core` 1 the
## white core; its UV.x the way along (units), UV.y the way round
func _tube(a: Vector3, b: Vector3, r: float, core: float, f: float, eye: Vector3) -> void:
	var A := U.v3(a.x, a.y, a.z)
	var B := U.v3(b.x, b.y, b.z)
	var L := A.distance_to(B)
	if L < 1.0:
		return
	var d := (B - A) / L
	var u := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var v := d.cross(u)
	var segs := clampi(ceili(L / SEG), 1, 64)
	var col := Color(core, 0, 0, f)
	for s in segs:
		var t0 := float(s) / segs
		var t1 := float(s + 1) / segs
		var P0 := A + d * L * t0
		var P1 := A + d * L * t1
		# (thinner close to the eye, so it does not fill the screen; and
		# breathing along its length)
		var r0 := r * (1.0 + 0.25 * sin(t0 * L * 0.02 - game.tics * 0.9)) * minf(1.0, maxf(0.25, P0.distance_to(eye) / NEAR))
		var r1 := r * (1.0 + 0.25 * sin(t1 * L * 0.02 - game.tics * 0.9)) * minf(1.0, maxf(0.25, P1.distance_to(eye) / NEAR))
		for k in SIDES:
			var a0 := TAU * k / SIDES
			var a1 := TAU * (k + 1) / SIDES
			var n0 := u * cos(a0) + v * sin(a0)
			var n1 := u * cos(a1) + v * sin(a1)
			var q := [[P0 + n0 * r0, n0, t0, k], [P0 + n1 * r0, n1, t0, k + 1], [P1 + n1 * r1, n1, t1, k + 1],
				[P0 + n0 * r0, n0, t0, k], [P1 + n1 * r1, n1, t1, k + 1], [P1 + n0 * r1, n0, t1, k]]
			for vv in q:
				im.surface_set_color(col)
				im.surface_set_normal(vv[1])
				im.surface_set_uv(Vector2(vv[2] * L, float(vv[3]) / SIDES))
				im.surface_add_vertex(vv[0])
