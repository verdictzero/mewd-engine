## MEWD — the Irish potato cannon (the Godot build's own; at the user's
## request: potatoes that bounce, with a NYAN CAT trail — a flat ribbon
## of six stripes streaming behind, not a spray of particles — and, for
## now, a ROCKET'S blast when they go off, the launcher's own).
##
## THE SHOT. A potato leaves the muzzle down the sight, lofted a little,
## and falls as anything falls. It BOUNCES — off walls (the way a ball
## does, the wall's own normal), off floors and ceilings (losing a
## quarter of its speed each time, and rolling slower along the ground)
## — until it touches SOMEBODY, or it has bounced SHOT.bounces times, or
## the fuse runs out, or it rolls to a stop: then it goes off. The
## shooter is safe from their own potato for the first few tics out of
## the barrel.
##
## THE TRAIL is a ribbon: the potato's last RIBBON.keep positions, one a
## tic, drawn as a band of six stripes (red, orange, yellow, green, blue,
## violet, top to bottom, the way the cat's is) that waves as it goes
## and thins toward its end. Its own light, both faces, one mesh for
## every potato in the air. When a potato goes off its ribbon is left
## behind and reeled in from the far end.
##
## THE WARHEAD is the launcher's (MissileSystem.detonate): the same
## damage in the same radius, the same fireball, boom and hole.
class_name PotatoCannon
extends Node3D

const SHOT := {"speed": 30.0, "loft": 0.10, "gravity": 0.85, "bounce": 0.74, "roll": 0.90, "radius": 7.0,
	"fuse": 8 * 35, "rest": 1.5, "rest_tics": 25, "arm": 8, "refire": 20, "bounces": 3}
const RIBBON := {"keep": 44, "height": 30.0, "wave": 4.0, "reel": 3}
## the cat's six, top to bottom
const STRIPES := [Color(1.0, 0.0, 0.0), Color(1.0, 0.6, 0.0), Color(1.0, 1.0, 0.0),
	Color(0.2, 1.0, 0.0), Color(0.1, 0.6, 1.0), Color(0.6, 0.2, 1.0)]

var game
var spuds := []
var fired := 0
var bounces := 0
var blasts := 0
var shake := 0.0
## the ribbons: [{pts: Array (Vector3, map space, newest last), live: bool}]
var ribbons := []
var spud_mm: MultiMesh
var _ribbon_mesh := ImmediateMesh.new()

func _init(g) -> void:
	game = g
	name = "PotatoCannon"

func _ready() -> void:
	# the potatoes themselves: little lumpy brown eggs
	spud_mm = MultiMesh.new()
	spud_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sm := SphereMesh.new()
	sm.radius = SHOT.radius
	sm.height = SHOT.radius * 1.5
	sm.radial_segments = 10
	sm.rings = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.albedo_color = Color(0.55, 0.40, 0.22)
	sm.material = m
	spud_mm.mesh = sm
	spud_mm.instance_count = 64
	spud_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = spud_mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	add_child(mi)
	# the ribbons: one mesh, vertex colours, its own light, both faces
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.vertex_color_use_as_albedo = true
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var rmi := MeshInstance3D.new()
	rmi.mesh = _ribbon_mesh
	rmi.material_override = rm
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rmi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	add_child(rmi)

# ---- the trigger ------------------------------------------------------------

func player_tic(p, attack: bool) -> void:
	if p.fire_index >= 0:
		p.fire_tics -= 1
		if p.fire_tics <= 0:
			p.fire_index = -1
	if attack and p.fire_index < 0:
		if p.ammo.get("potatoes", 0) <= 0:
			if not p.clicked:
				p.clicked = true
				game.play_sound("noammo", p)
			return
		launch(p)
		return
	if not attack:
		p.clicked = false
	if p.pending_weapon != "" and p.fire_index < 0:
		p.weapon = p.pending_weapon
		p.pending_weapon = ""

## One potato out of the barrel, down the sight and lofted.
func launch(p) -> Dictionary:
	p.ammo.potatoes -= 1
	p.shots_fired += 1
	p.fire_index = 0
	p.fire_tics = SHOT.refire
	var o: Vector3 = game.nozzle(p)
	if not game.level.ray_hit_wall(p.x, p.y, p.eye_z(), o.x, o.y, o.z).is_empty():
		o = Vector3(p.x, p.y, p.eye_z() - 6.0)
	var aim: Dictionary = game.trace(p, p.angle, p.pitch, 4000.0)
	var d := (Vector3(aim.x, aim.y, aim.z) - o).normalized()
	d.z += SHOT.loft
	d = d.normalized() * SHOT.speed
	var rib := {"pts": [o], "live": true}
	ribbons.append(rib)
	var s := {"x": o.x, "y": o.y, "z": o.z, "vx": d.x, "vy": d.y, "vz": d.z, "tics": 0, "fuse": SHOT.fuse,
		"still": 0, "owner": p, "spin": 0.0, "bounced": 0, "ribbon": rib}
	spuds.append(s)
	fired += 1
	game.play_sound("missile", p)
	game.fx.puff(o.x, o.y, o.z, 14, 40)
	game.noise(p, 900.0)
	return s

# ---- the flight -------------------------------------------------------------

func tic() -> void:
	for i in range(spuds.size() - 1, -1, -1):
		var s: Dictionary = spuds[i]
		var at = _fly(s)
		if at != null:
			spuds.remove_at(i)
			s.ribbon.live = false
			detonate(at[0], at[1])
	# the ribbons: a live one keeps its last RIBBON.keep points; one left
	# behind is reeled in from the far end
	for i in range(ribbons.size() - 1, -1, -1):
		var r: Dictionary = ribbons[i]
		var pts: Array = r.pts
		if r.live:
			while pts.size() > RIBBON.keep:
				pts.pop_front()
		else:
			for k in RIBBON.reel:
				if not pts.is_empty():
					pts.pop_front()
			if pts.size() < 2:
				ribbons.remove_at(i)
	shake = maxf(0.0, shake - 0.012)

## One tic of a potato: [point, who] where it went off, or null.
func _fly(s: Dictionary):
	var lv: Level = game.level
	s.tics += 1
	s.fuse -= 1
	s.vz -= SHOT.gravity
	var v := Vector3(s.vx, s.vy, s.vz)
	var steps := maxi(1, ceili(v.length() / 8.0))
	var r: float = SHOT.radius
	for k in steps:
		var nx: float = s.x + s.vx / steps
		var ny: float = s.y + s.vy / steps
		var nz: float = s.z + s.vz / steps
		# SOMEBODY: it goes off
		var who = _body_at(s, nx, ny, nz)
		if who != null:
			return [Vector3(nx, ny, nz), who]
		# A WALL: off it, as a ball goes off a wall
		var w := lv.ray_hit_wall(s.x, s.y, s.z, nx, ny, nz)
		if not w.is_empty():
			var l: Level.Line = w.line
			var n := Vector2(-(l.y2 - l.y1), l.x2 - l.x1).normalized()
			var hv := Vector2(s.vx, s.vy)
			if hv.dot(n) > 0.0:
				n = -n
			hv = (hv - 2.0 * hv.dot(n) * n) * SHOT.bounce
			s.vx = hv.x
			s.vy = hv.y
			s.x = w.x + n.x * 1.5
			s.y = w.y + n.y * 1.5
			s.z = clampf(w.z, s.z - 16.0, s.z + 16.0)
			bounces += 1
			s.bounced += 1
			break
		# THE FLOOR AND THE CEILING
		var sec := lv.span_at(nx, ny, s.z)
		if sec == null:
			return [Vector3(s.x, s.y, s.z), null]
		if nz - r < sec.floor:
			nz = sec.floor + r
			if s.vz < 0.0:
				if s.vz < -2.0:
					bounces += 1
					s.bounced += 1
				s.vz = -s.vz * SHOT.bounce
				s.vx *= SHOT.roll
				s.vy *= SHOT.roll
		elif nz + r > sec.ceil and sec.ceil_tex != "SKY":
			nz = sec.ceil - r
			if s.vz > 0.0:
				s.vz = -s.vz * SHOT.bounce
		s.x = nx
		s.y = ny
		s.z = nz
	s.spin += 0.35
	s.ribbon.pts.append(Vector3(s.x, s.y, s.z))
	# bounced enough, at rest, or the fuse out: it goes off where it is
	if Vector3(s.vx, s.vy, s.vz).length() < SHOT.rest:
		s.still += 1
	else:
		s.still = 0
	if s.bounced >= SHOT.bounces or s.fuse <= 0 or s.still > SHOT.rest_tics:
		return [Vector3(s.x, s.y, s.z), null]
	return null

## Anybody the potato touches at (x, y, z) — never its shooter.
func _body_at(s: Dictionary, x: float, y: float, z: float):
	var r: float = SHOT.radius
	for list in [game.actors, game.players]:
		for a in list:
			if a.removed or a.dead:
				continue
			if list == game.actors and not a.shootable:
				continue
			# (never its own shooter: a potato coming back off a hill is its
			# blast's share, not a direct hit of more than a body can hold)
			if a == s.owner:
				continue
			var rr: float = a.radius + r
			if U.dist2(x, y, a.x, a.y) > rr * rr:
				continue
			if z + r < a.z or z - r > a.z + a.height:
				continue
			return a
	return null

# ---- the warhead ------------------------------------------------------------

## The launcher's blast, where the potato went off (on `direct`, if it
## touched somebody); and a shake to go with it.
func detonate(at: Vector3, direct = null) -> void:
	blasts += 1
	var M = game.get("missiles")
	if M != null:
		M.detonate(at, direct, null, "nuke")
	else:
		game.explode({"x": at.x, "y": at.y, "z": at.z}, {"radius": 190.0, "damage": 150.0})
	var p = game.player
	if p != null:
		var d := Vector3(p.x - at.x, p.y - at.y, p.z - at.z).length()
		shake = minf(1.0, shake + maxf(0.15, 0.7 - d / 2000.0))

# ---- the picture ------------------------------------------------------------

func _process(_dt: float) -> void:
	spud_mm.visible_instance_count = mini(spuds.size(), spud_mm.instance_count)
	for i in spud_mm.visible_instance_count:
		var s: Dictionary = spuds[i]
		var b := Basis(Vector3(0.3, 1, 0.2).normalized(), s.spin)
		spud_mm.set_instance_transform(i, Transform3D(b, U.v3(s.x, s.y, s.z)))
	_draw_ribbons()

## THE RIBBONS: for each, a band RIBBON.height tall standing on the
## world's up through every point, cut into the six stripes, waving as
## the cat's does and fading toward the far end.
func _draw_ribbons() -> void:
	var im := _ribbon_mesh
	im.clear_surfaces()
	if ribbons.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	var begun := false
	var h: float = RIBBON.height
	var sh: float = h / STRIPES.size()
	for r in ribbons:
		var pts: Array = r.pts
		var n := pts.size()
		if n < 2:
			continue
		if not begun:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		for i in n - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			# the wave: the whole band bobs, a beat down its length
			var wa: float = sin(t * 9.0 - i * 0.8) * RIBBON.wave
			var wb: float = sin(t * 9.0 - (i + 1) * 0.8) * RIBBON.wave
			# thinner and fainter toward the far end
			var fa: float = float(i) / float(n)
			var fb: float = float(i + 1) / float(n)
			var ka := 0.35 + 0.65 * fa
			var kb := 0.35 + 0.65 * fb
			var top_a := U.v3(a.x, a.y, a.z + wa + h * 0.5 * ka)
			var top_b := U.v3(b.x, b.y, b.z + wb + h * 0.5 * kb)
			for s in STRIPES.size():
				var c0: Color = STRIPES[s]
				var ca := Color(c0.r, c0.g, c0.b, 0.25 + 0.75 * fa)
				var cb := Color(c0.r, c0.g, c0.b, 0.25 + 0.75 * fb)
				var p00 := Vector3(top_a.x, top_a.y - sh * s * ka, top_a.z)
				var p01 := Vector3(top_a.x, top_a.y - sh * (s + 1) * ka, top_a.z)
				var p10 := Vector3(top_b.x, top_b.y - sh * s * kb, top_b.z)
				var p11 := Vector3(top_b.x, top_b.y - sh * (s + 1) * kb, top_b.z)
				im.surface_set_color(ca); im.surface_add_vertex(p00)
				im.surface_set_color(cb); im.surface_add_vertex(p10)
				im.surface_set_color(cb); im.surface_add_vertex(p11)
				im.surface_set_color(ca); im.surface_add_vertex(p00)
				im.surface_set_color(cb); im.surface_add_vertex(p11)
				im.surface_set_color(ca); im.surface_add_vertex(p01)
	if begun:
		im.surface_end()
