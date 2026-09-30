## MEWD — the Irish potato cannon (the Godot build's own; at the user's
## request: "it will shoot potatoes that bounce around until they hit
## something, with a thick rainbow particle trail. when they hit
## something the explosion will be a spectacular color cycling nuke
## equivalent").
##
## THE SHOT. A potato leaves the muzzle down the sight, lofted a little,
## and falls as anything falls. It BOUNCES — off walls (the way a ball
## does, the wall's own normal), off floors and ceilings (losing a
## quarter of its speed each time, and rolling slower along the ground)
## — until it touches SOMEBODY: then it goes off. Nobody in its way and
## it goes off on its own after eight seconds, or once it has rolled to
## a stop. The shooter is safe from their own potato for the first few
## tics out of the barrel.
##
## THE TRAIL. Thick, added light, every colour: a handful of puffs a tic
## along the path, each a hue on from the last, cycling as it goes — and
## while a potato is in the air the palette gives way by half, so the
## rainbow gets onto the glass as a rainbow (Lofi.set_unsnap; a nuke
## makes it give way all but completely).
##
## THE WARHEAD, a nuke of a potato: everything in NUKE.radius takes a
## share that falls off with distance (a direct hit far more), the fire
## gets a start as wide, and the picture is a white flash; a fireball
## that swells and boils through the rainbow; a column that climbs out
## of it and a cap that rolls up and out on top; a ring of shock along
## the ground; a storm of rainbow sparks; and a shake to match.
class_name PotatoCannon
extends Node3D

const SHOT := {"speed": 30.0, "loft": 0.10, "gravity": 0.85, "bounce": 0.74, "roll": 0.90, "radius": 7.0,
	"fuse": 8 * 35, "rest": 1.5, "rest_tics": 25, "arm": 8, "refire": 20}
const NUKE := {"direct": 1500, "splash": 700, "radius": 460.0, "heat": 520.0, "heatRadius": 260.0, "ignite": 420,
	"self": 0.45, "tics": 175, "column": 560.0, "cap": 260.0, "ring": 1100.0}
const TRAIL := {"max": 6000, "per": 7, "life": 60, "size0": 26.0, "size1": 72.0, "alpha": 0.55, "unsnap": 0.6}
const SPARKS := 360

var game
var spuds := []
var nukes := []
var fired := 0
var bounces := 0
var blasts := 0
var shake := 0.0
var flash := 0.0
var trail: Particles
var sparks: Particles
var spud_mm: MultiMesh
var _flash_rect: ColorRect
var _unsnapped := false

func _init(g) -> void:
	game = g
	name = "PotatoCannon"

func _ready() -> void:
	trail = Particles.new({"max": TRAIL.max, "blend": "add", "fullbright": true, "near_shrink": 60.0})
	add_child(trail)
	sparks = Particles.new({"max": SPARKS * 3, "blend": "add", "fullbright": true})
	add_child(sparks)
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
	# THE FLASH, over the whole picture (it is in the world's own buffer,
	# under the HUD)
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	cl.add_child(_flash_rect)

static func _hue(h: float, a := 1.0) -> Color:
	var c := Color.from_hsv(fposmod(h, 1.0), 0.9, 1.0)
	c.a = a
	return c

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
	var s := {"x": o.x, "y": o.y, "z": o.z, "vx": d.x, "vy": d.y, "vz": d.z, "tics": 0, "fuse": SHOT.fuse,
		"still": 0, "owner": p, "hue": (U.p_random() / 255.0), "spin": 0.0}
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
			detonate(at[0], at[1])
	trail.tic()
	sparks.tic()
	for i in range(nukes.size() - 1, -1, -1):
		var n: Dictionary = nukes[i]
		n.t += 1
		if n.t < 40 and n.t % 2 == 0:
			_nuke_sparks(n, 18)
		if n.t >= NUKE.tics:
			for part in n.nodes:
				part.queue_free()
			nukes.remove_at(i)
	shake = maxf(0.0, shake - 0.012)
	flash = maxf(0.0, flash - 0.06)

## One tic of a potato: [point, who] where it went off, or null.
func _fly(s: Dictionary):
	var lv: Level = game.level
	s.tics += 1
	s.fuse -= 1
	s.vz -= SHOT.gravity
	var v := Vector3(s.vx, s.vy, s.vz)
	var steps := maxi(1, ceili(v.length() / 8.0))
	var r: float = SHOT.radius
	var from := Vector3(s.x, s.y, s.z)
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
	_shed(s, from)
	# at rest, or the fuse out: it goes off where it lies
	if Vector3(s.vx, s.vy, s.vz).length() < SHOT.rest:
		s.still += 1
	else:
		s.still = 0
	if s.fuse <= 0 or s.still > SHOT.rest_tics:
		return [Vector3(s.x, s.y, s.z), null]
	return null

## Anybody the potato touches at (x, y, z) — not its shooter while it is
## still in the barrel's reach.
func _body_at(s: Dictionary, x: float, y: float, z: float):
	var r: float = SHOT.radius
	for list in [game.actors, game.players]:
		for a in list:
			if a.removed or a.dead:
				continue
			if list == game.actors and not a.shootable:
				continue
			if a == s.owner and s.tics < SHOT.arm:
				continue
			var rr: float = a.radius + r
			if U.dist2(x, y, a.x, a.y) > rr * rr:
				continue
			if z + r < a.z or z - r > a.z + a.height:
				continue
			return a
	return null

## THE RAINBOW behind it: thick, added, cycling.
func _shed(s: Dictionary, from: Vector3) -> void:
	var to := Vector3(s.x, s.y, s.z)
	for k in TRAIL.per:
		var f := float(k) / TRAIL.per
		var p := from.lerp(to, f)
		var h: float = s.hue + game.tics * 0.035 + f * 0.035
		var j := func() -> float: return (U.p_random() / 255.0 - 0.5) * 3.0
		trail.spawn({"x": p.x + j.call(), "y": p.y + j.call(), "z": p.z + j.call(),
			"vx": j.call() * 0.1, "vy": j.call() * 0.1, "vz": 0.15,
			"life": TRAIL.life, "size0": TRAIL.size0, "size1": TRAIL.size1,
			"c0": _hue(h, TRAIL.alpha), "c1": _hue(h + 0.35, 0.0), "drag": 0.95})

# ---- the warhead ------------------------------------------------------------

func detonate(at: Vector3, direct = null) -> void:
	blasts += 1
	var p = game.player
	game.play_sound("explode", null)
	for k in 8:
		game.fx.fireball(at.x, at.y, at.z, 90, 24)
	game.fx.ember(at.x, at.y, at.z, 24, 2.0)
	var under: Level.Sector = game.level.span_at(at.x, at.y, at.z)
	if under and at.z - under.floor < 96.0:
		game.decals.hole(Vector3(at.x, at.y, under.floor), Vector3(0, 0, 1), true)
	game.scare(at.x, at.y, 1600.0)
	game.noise(at, 3000.0)
	var R: float = NUKE.radius
	var hit := {}
	var blown := []
	if direct != null and direct in game.actors:
		hit[direct] = true
		direct.damage(NUKE.direct, p, {"impact": true, "gib": true})
		blown.append([direct, 1.6])
		if direct.has_method("ignite") and direct.info.get("flammable", false):
			direct.ignite(NUKE.ignite)
	for a in game.actors:
		if a.removed or a.dead or not a.shootable or hit.has(a):
			continue
		if absf(a.x - at.x) > R + a.radius or absf(a.y - at.y) > R + a.radius:
			continue
		var d := _reach(a, at)
		if d >= R:
			continue
		hit[a] = true
		var n := roundi(NUKE.splash * (1.0 - d / R))
		if n <= 0:
			continue
		a.damage(n, p, {"impact": true, "gib": true})
		blown.append([a, 1.0 - 0.5 * d / R])
		if a.info.get("flammable", false):
			a.ignite(NUKE.ignite)
	for b in blown:
		if b[0].dead and game.gore_decals.bleeds(b[0]):
			game.giblets.eviscerate(b[0], at, b[1])
	# the players: a share for a player in reach (their own potato too)
	for q in game.players:
		if q.dead:
			continue
		var d := _reach(q, at)
		if d < R:
			var mine: bool = q == p
			q.damage(roundf((NUKE.direct if q == direct else NUKE.splash) * (NUKE.self if mine else 1.0) * (1.0 - d / R)),
				null if mine else p, {"impact": true})
	if p != null:
		var d := Vector3(p.x - at.x, p.y - at.y, p.z - at.z).length()
		shake = minf(1.0, shake + maxf(0.25, 1.0 - d / 3000.0))
		flash = maxf(flash, clampf(1.2 - d / 2500.0, 0.25, 1.0))
	_nuke(at)

static func _reach(a, at: Vector3) -> float:
	var h := maxf(0.0, sqrt(U.dist2(at.x, at.y, a.x, a.y)) - a.radius)
	var v: float = (a.z - at.z) if at.z < a.z else ((at.z - a.z - a.height) if at.z > a.z + a.height else 0.0)
	return Vector2(h, v).length()

## THE PICTURE: a fireball, a column, a cap, a ring — nodes of their own,
## driven in _process.
func _nuke(at: Vector3) -> void:
	var ground := at.z
	var sec: Level.Sector = game.level.span_at(at.x, at.y, at.z)
	if sec != null:
		ground = sec.floor
	var seed := U.p_random() / 25.5
	var mk := func(mesh: Mesh, scroll: float) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var m := ShaderMaterial.new()
		m.shader = preload("res://godot/shaders/nuke.gdshader")
		m.set_shader_parameter("seed", seed)
		m.set_shader_parameter("scroll", scroll)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-4000, -4000, -4000), Vector3(8000, 8000, 8000))
		add_child(mi)
		return mi
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 32
	ball.rings = 16
	var col := CylinderMesh.new()
	col.top_radius = 0.7
	col.bottom_radius = 1.0
	col.height = 1.0
	col.radial_segments = 24
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	ring.rings = 48
	ring.ring_segments = 8
	var n := {"x": at.x, "y": at.y, "z": at.z, "ground": ground, "t": 0, "seed": seed}
	n["ball"] = mk.call(ball, 1.0)
	n["column"] = mk.call(col, -1.4)
	n["cap"] = mk.call(ball, 0.6)
	n["ring"] = mk.call(ring, 2.0)
	n["nodes"] = [n.ball, n.column, n.cap, n.ring]
	nukes.append(n)
	_nuke_sparks(n, SPARKS)

func _nuke_sparks(n: Dictionary, count: int) -> void:
	for k in count:
		var a := (U.p_random() / 255.0) * TAU
		var e := (U.p_random() / 255.0) * 1.4 - 0.2
		var sp := 8.0 + (U.p_random() / 255.0) * 22.0
		var h: float = n.seed * 0.1 + k * 0.013 + game.tics * 0.02
		sparks.spawn({"x": n.x, "y": n.y, "z": n.z + 12.0,
			"vx": cos(a) * cos(e) * sp, "vy": sin(a) * cos(e) * sp, "vz": sin(e) * sp,
			"life": 50 + (U.p_random() % 50), "size0": 22.0, "size1": 4.0,
			"c0": _hue(h, 1.0), "c1": _hue(h + 0.5, 0.0), "drag": 0.94, "gravity": -0.35})

func _process(_dt: float) -> void:
	for n in nukes:
		var t: float = n.t
		var T: float = NUKE.tics
		var life := t / T
		var fade := clampf(1.0 - life, 0.0, 1.0)
		fade = fade * fade * (3.0 - 2.0 * fade)
		# the fireball: out fast, then sinking into the column's foot
		var grow := 1.0 - pow(1.0 - clampf(t / 22.0, 0.0, 1.0), 3.0)
		var rb: float = NUKE.radius * 0.75 * grow * (1.0 - 0.45 * clampf((t - 30.0) / 90.0, 0.0, 1.0))
		_place(n.ball, Vector3(n.x, n.y, n.z + rb * 0.4), Vector3(rb, rb, rb), fade * 1.4, clampf(1.0 - t / 40.0, 0.0, 1.0))
		# the column, climbing
		var climb := clampf((t - 8.0) / 70.0, 0.0, 1.0)
		climb = 1.0 - pow(1.0 - climb, 2.0)
		var hgt: float = NUKE.column * climb
		var cw: float = 50.0 + 40.0 * climb
		_place(n.column, Vector3(n.x, n.y, n.ground + hgt * 0.5), Vector3(cw, maxf(1.0, hgt), cw), fade * 0.9 * minf(1.0, climb * 3.0), 0.2)
		# the cap, rolling up and out on top of it
		var cr: float = NUKE.cap * (0.3 + 0.7 * climb)
		_place(n.cap, Vector3(n.x, n.y, n.ground + hgt + cr * 0.25), Vector3(cr, cr * 0.55, cr), fade * 1.2 * minf(1.0, climb * 3.0), 0.3 * fade)
		# the ring of shock, racing out along the ground
		var rr: float = NUKE.ring * (1.0 - pow(1.0 - clampf(t / 45.0, 0.0, 1.0), 2.0))
		_place(n.ring, Vector3(n.x, n.y, n.ground + 6.0), Vector3(rr, rr * 0.6, rr), clampf(1.0 - t / 60.0, 0.0, 1.0) * 1.5, 0.0)
	var cam: Camera3D = game.camera
	if cam != null:
		trail.draw()
		sparks.draw()
	spud_mm.visible_instance_count = mini(spuds.size(), spud_mm.instance_count)
	for i in spud_mm.visible_instance_count:
		var s: Dictionary = spuds[i]
		var b := Basis(Vector3(0.3, 1, 0.2).normalized(), s.spin)
		spud_mm.set_instance_transform(i, Transform3D(b, U.v3(s.x, s.y, s.z)))
	if _flash_rect != null:
		_flash_rect.color = Color(1.0, 0.97, 0.92, clampf(flash, 0.0, 1.0) * 0.85)
	# while a nuke burns the palette gives way, and the rainbow gets through
	# (and a potato in the air lets its rainbow through by half)
	var k: float = TRAIL.unsnap if not spuds.is_empty() else 0.0
	for n in nukes:
		k = maxf(k, minf(1.0, (1.0 - float(n.t) / NUKE.tics) * 1.6) * 0.9)
	if k > 0.0 or _unsnapped:
		var lofi = get_viewport().get_parent() if get_viewport() != null else null
		if lofi is Lofi:
			lofi.set_unsnap(k)
		_unsnapped = k > 0.0

func _place(mi: MeshInstance3D, at: Vector3, size: Vector3, fade: float, heat: float) -> void:
	mi.position = U.v3(at.x, at.y, at.z)
	# map (x, y, z up) to Godot: a torus / cylinder / sphere's own y is up
	mi.scale = Vector3(size.x, size.y, size.z)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("fade", maxf(0.0, fade))
	m.set_shader_parameter("heat", heat)
	mi.visible = fade > 0.01
