## MEWD — the fetus launcher (the Godot build's own), at the user's
## request: "make this weapon (model) fire the fetus ... with extra gore on
## impact" — the user's own gun (assets/models/fetus_launcher.glb, weapon3d
## "FETUS"), the user's own picture of a fetus in its sac (tools/fetus-
## art.py), "goop sound on launch, then screaming", "switch up the
## screaming between shots"; and the fetus alone, nothing trailing it ("i
## just want the fetus sprite"); and then "can the end of the gun expand
## like its forcing out the fetus? can the baby screaming last longer /
## start earlier, can there be a goop situation coming out of the end of
## the gun on fetus extrusion, add recoil too".
##
## THE SQUEEZE. The trigger does not throw it at once: the gun spends
## Weapons.FETUS_SQUEEZE tics FORCING IT OUT — the user's goop, the flesh
## draining out of the jar, a swelling run down the barrel to the muzzle
## and the muzzle stretched open, goop oozing out of it (Weapon3D
## `extrude`, `goop`) — and it SCREAMS from the first of them.
##
## THE SHOT. Out of the muzzle down the sight, lofted a little, it falls
## as anything falls, tumbling as it goes (a card turned to the eye, spun
## in the picture and rocked about its upright: fetus_card.gdshader). It
## comes out with a KICK (a shove back along the shot, the eye punched up
## a moment — Game's camera, the aim left where it was — and the gun
## thrown back in the hands, Weapon3D `recoil`). The SCREAM is one of the
## user's four cries, never the one the last shot cried, from where the
## fetus is, fading as it goes away (Sound.voice); a cry run out before it
## lands is followed by another, and the last one is never cut off: where
## it lands it screams on to the end.
##
## IT GOES OFF ON THE FIRST THING IT TOUCHES: somebody, a wall, the
## ground, a ceiling. The shooter is safe from their own. THE SPLAT
## (splat): whoever it hit takes DIRECT and everyone
## round it SPLASH, falling away to nothing at RADIUS (a rocket's way,
## without the fire: nobody is set alight, no plant is blown up, nobody
## goes up in a fireball), and everybody it kills is BLOWN APART as a
## rocket's are (Giblets.eviscerate). And the fetus itself comes apart,
## more than anything else in the game for its size: viscera thrown off
## the spot (Giblets.splatter), its picture torn into wet pieces
## (SpriteChunks), a burst of blood both ways at once, a great spatter on
## what it hit, a pool under it, blood across the floor and up every wall
## in reach.
class_name FetusLauncher
extends Node3D

## THE PICTURE (tools/fetus-art.py)
const ART := "res://assets/things/fetus.png"

## speed and loft as the potato's; `w` x `h` the card, `radius` what it
## touches with; `grow` tics to come out of the barrel to its full size;
## the spin in the picture and the rock about its upright, a tic; the
## shove back on the one who fired it (units a tic) and how long the eye's
## punch takes to settle (seconds)
const SHOT := {"speed": 24.0, "loft": 0.07, "gravity": 0.5, "radius": 11.0, "w": 32.0, "h": 38.0,
	"fuse": 6 * 35, "grow": 6, "spin": [0.06, 0.16], "tumble": [0.05, 0.11], "kick": 2.5, "punch": 0.22}
## the least a tumbling card is of its width (fetus_card.gdshader): turned
## edge-on it would be a line, and a fetus that is a line half the time is
## not a fetus
const FLAT := 0.7
## THE SPLAT: direct, splash (falling away to nothing at radius) and the
## shooter's share of a splash of their own (more of all three at the
## user's request: "big blood spatter splat impact damage"); then the gore
## — viscera pieces, picture pieces, blood drops, the BURST on what it hit
## and on the ground under it (GoreDecals.burst, across), the pool, the
## floor's spatters and how far, the rays up the walls — and the shake
const SPLAT := {"direct": 300, "splash": 120, "radius": 128.0, "self": 0.3,
	"viscera": 26, "force": 1.15, "size": 0.75, "picture": 12, "spray": 140,
	"burst": 260.0, "pool": 130.0, "floor": 14, "reach": 200.0, "walls": 18, "shake": 0.4}
## the four cries (Sound: fetuscry1..4)
const CRIES := 4
## the most in the air at once (one a FETUS_REFIRE: plenty)
const MOST := 64

var game
## the shots in the air: {x, y, z, vx, vy, vz, tics, owner, spin, spin_v,
## flip, flip_v, voice}
var shots := []
var fired := 0
var splats := 0
var kills := 0
var shake := 0.0
## the eye's punch from the last shot, 1 just out and 0 settled (Game's
## camera reads it)
var punch := 0.0
## a scream begun on the trigger, waiting for its fetus (player: Voice)
var _pending := {}
var last_cry := -1
var tex: Texture2D
var mm: MultiMesh

func _init(g) -> void:
	game = g
	name = "FetusLauncher"

func _ready() -> void:
	tex = TexBank.decoded(load(ART), true) if ResourceLoader.exists(ART) else null
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/fetus_card.gdshader")
	mat.set_shader_parameter("picture", tex)
	quad.surface_set_material(0, mat)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = MOST
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

static func _r() -> float:
	return U.p_random() / 255.0

# ---- the trigger ------------------------------------------------------------

func player_tic(p, attack: bool) -> void:
	if p.fire_index >= 0:
		p.fire_tics -= 1
		# the squeeze done: out it comes
		if Weapons.FETUS_REFIRE - p.fire_tics == Weapons.FETUS_SQUEEZE:
			launch(p)
		if p.fire_tics <= 0:
			p.fire_index = -1
	if attack and p.fire_index < 0:
		if p.ammo.get("fetuses", 0) <= 0:
			if not p.clicked:
				p.clicked = true
				game.play_sound("noammo", p)
			return
		squeeze(p)
		return
	if not attack:
		p.clicked = false
	if p.pending_weapon != "" and p.fire_index < 0:
		p.weapon = p.pending_weapon
		p.pending_weapon = ""

## THE SQUEEZE begun: one spent, the gun busy for the whole of its
## cycle, the goop, and the scream already going (from the one holding it,
## until there is a fetus to scream from)
func squeeze(p) -> void:
	p.ammo.fetuses = maxi(0, int(p.ammo.get("fetuses", 0)) - 1)
	p.fire_index = 0
	p.fire_tics = Weapons.FETUS_REFIRE
	game.play_sound("fetuslaunch", p)
	var v = _scream(p)
	if v != null:
		_pending[p] = v
	game.noise(p, 900.0)

## One fetus out of the barrel, down the sight and lofted (the squeeze's
## end; or at once, asked straight)
func launch(p) -> Dictionary:
	p.shots_fired += 1
	var o: Vector3 = game.nozzle(p)
	if not game.level.ray_hit_wall(p.x, p.y, p.eye_z(), o.x, o.y, o.z).is_empty():
		o = Vector3(p.x, p.y, p.eye_z() - 6.0)
	var aim: Dictionary = game.trace(p, p.angle, p.pitch, 4000.0)
	var d := (Vector3(aim.x, aim.y, aim.z) - o).normalized()
	d.z += SHOT.loft
	var v := d.normalized() * float(SHOT.speed)
	var s := {"x": o.x, "y": o.y, "z": o.z, "vx": v.x, "vy": v.y, "vz": v.z, "tics": 0, "owner": p,
		"spin": _r() * TAU, "spin_v": lerpf(SHOT.spin[0], SHOT.spin[1], _r()) * (1.0 if (U.p_random() & 1) else -1.0),
		"flip": 0.0, "flip_v": lerpf(SHOT.tumble[0], SHOT.tumble[1], _r()), "voice": _pending.get(p)}
	_pending.erase(p)
	if shots.size() >= MOST:
		shots.pop_front()
	shots.append(s)
	fired += 1
	# the goop it comes out in, in the world (the gun's own is Weapon3D's)
	game.fx.blood_spray(o.x, o.y, o.z, d.x, d.y, d.z, 18, 0.9)
	# THE KICK: a shove back along the shot, on the ground, and the eye's
	# punch for whoever's eye this is
	if p.on_ground:
		p.momx -= cos(p.angle) * float(SHOT.kick)
		p.momy -= sin(p.angle) * float(SHOT.kick)
	if p == game.player:
		punch = 1.0
	return s

## THE SCREAM: one of the four, never the last one again, from `from`
func _scream(from):
	var k := U.p_random() % CRIES
	if k == last_cry:
		k = (k + 1 + U.p_random() % (CRIES - 1)) % CRIES
	last_cry = k
	return game.voice("fetuscry%d" % (k + 1), from) if game.has_method("voice") else null

## (a fetus's scream: begun if it has none, and another when one runs out)
func _cry(s: Dictionary) -> void:
	s.voice = _scream(s)

# ---- the flight -------------------------------------------------------------

func tic() -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var hit = _fly(s)
		if hit != null:
			shots.remove_at(i)
			splat(s, hit[0], hit[1], hit[2])
	shake = maxf(0.0, shake - 0.02)

## One tic of a fetus: [point, surface normal (zero: a body), who], or null.
func _fly(s: Dictionary):
	var lv: Level = game.level
	s.tics += 1
	if s.voice == null or not s.voice.playing():
		_cry(s)
	s.vz -= SHOT.gravity
	var steps := maxi(1, ceili(Vector3(s.vx, s.vy, s.vz).length() / 8.0))
	var r: float = SHOT.radius
	var hit = null
	for k in steps:
		var nx: float = s.x + s.vx / steps
		var ny: float = s.y + s.vy / steps
		var nz: float = s.z + s.vz / steps
		var who = _body_at(s.owner, nx, ny, nz, r)
		if who != null:
			hit = [Vector3(nx, ny, nz), Vector3.ZERO, who]
			break
		var w := lv.ray_hit_wall(s.x, s.y, s.z, nx, ny, nz)
		if not w.is_empty():
			var n := Decals.wall_normal(w.line, s.x, s.y)
			hit = [Vector3(w.x, w.y, w.z) + n * 2.0, n, null]
			break
		var sec := lv.span_at(nx, ny, s.z)
		if sec == null:
			hit = [Vector3(s.x, s.y, s.z), Vector3(0, 0, 1), null]
			break
		if nz - r * 0.5 < sec.floor:
			hit = [Vector3(nx, ny, sec.floor), Vector3(0, 0, 1), null]
			break
		if nz + r * 0.5 > sec.ceil and sec.ceil_tex != "SKY":
			hit = [Vector3(nx, ny, sec.ceil), Vector3(0, 0, -1), null]
			break
		s.x = nx
		s.y = ny
		s.z = nz
	if hit == null and s.tics >= SHOT.fuse:
		hit = [Vector3(s.x, s.y, s.z), Vector3(0, 0, 1), null]
	s.spin += s.spin_v
	s.flip += s.flip_v
	if s.voice != null:
		s.voice.follow(s)
	return hit

## Anybody at (x, y, z) within `r` — never the shooter.
func _body_at(owner, x: float, y: float, z: float, r: float):
	for list in [game.actors, game.players]:
		for a in list:
			if a.removed or a.dead or a == owner:
				continue
			if list == game.actors and not a.shootable:
				continue
			var rr: float = a.radius + r
			if U.dist2(x, y, a.x, a.y) > rr * rr:
				continue
			if z + r < a.z or z - r > a.z + a.height:
				continue
			return a
	return null

# ---- the splat --------------------------------------------------------------

## The fetus has landed at `at` — on the surface facing `n`, or in `who`
## (n zero) — going along the shot's own way.
func splat(s: Dictionary, at: Vector3, n: Vector3, who = null) -> void:
	splats += 1
	var here := {"x": at.x, "y": at.y, "z": at.z}
	# (the scream is not cut off: it screams on to its end where it landed)
	if s.voice != null:
		s.voice.follow(here)
		s.voice = null
	var d := Vector3(s.vx, s.vy, s.vz).normalized()
	game.play_sound("fetussplat", here)
	_hurt(at, who, s.owner, SPLAT)
	_gore(at, n, d, who, SPLAT, Vector2(SHOT.w, SHOT.h))
	game.scare(at.x, at.y, 700.0)
	game.noise(at, 1200.0)
	var p = game.player
	if p != null:
		var dist := Vector3(p.x - at.x, p.y - at.y, p.z - at.z).length()
		shake = minf(1.0, shake + maxf(0.0, float(SPLAT.shake) - dist / 1600.0))

## WHO IT HURTS: `who` the whole of `k.direct`, everybody else in reach a
## share of `k.splash` falling away to nothing at `k.radius`, the shooter
## (alone) `k.self` of theirs; and everybody it kills blown apart as a
## rocket's are (MissileSystem.detonate's own way: marked so their own
## gib throws nothing, then eviscerated, one budget shared among them) —
## but WET: marked so their gib has no fireball (Giblets.burst). A body
## that comes apart later than the blow (a trooper's death runs a few
## frames first) keeps the marks until it does.
func _hurt(at: Vector3, who, owner, k: Dictionary) -> void:
	var R: float = k.radius
	var blown := []
	if who != null:
		who.set_meta("warhead", true)
		who.set_meta("wet", true)
		blown.append([who, 1.25])
		who.damage(k.direct, owner, {"impact": true, "gib": true})
	if R > 0.0:
		for a in game.blockmap.near_radius(at.x, at.y, R + 64.0):
			if a == who or a.removed or a.dead or not a.shootable:
				continue
			var h := maxf(0.0, sqrt(U.dist2(at.x, at.y, a.x, a.y)) - a.radius)
			var v: float = (a.z - at.z) if at.z < a.z else ((at.z - a.z - a.height) if at.z > a.z + a.height else 0.0)
			var dist := Vector2(h, v).length()
			if dist >= R:
				continue
			var dmg := roundi(float(k.splash) * (1.0 - dist / R))
			if dmg <= 0:
				continue
			a.set_meta("warhead", true)
			a.set_meta("wet", true)
			blown.append([a, 1.0 - 0.4 * dist / R])
			a.damage(dmg, owner, {"impact": true, "gib": true})
	for b in blown:
		if not b[0].dead:
			b[0].remove_meta("warhead")
			b[0].remove_meta("wet")
	var gory := blown.filter(func(b): return b[0].dead and game.gore_decals.bleeds(b[0]))
	kills += gory.size()
	var share := 1.0 / sqrt(maxf(1.0, gory.size()))
	for b in gory:
		game.giblets.eviscerate(b[0], at, b[1], share)
	# the shooter, too close to their own
	var p = owner
	if R > 0.0 and p != null and p is Player and not p.dead and p != who:
		var h := maxf(0.0, sqrt(U.dist2(at.x, at.y, p.x, p.y)) - p.radius)
		var v: float = (p.z - at.z) if at.z < p.z else ((at.z - p.z - p.height) if at.z > p.z + p.height else 0.0)
		var dist := Vector2(h, v).length()
		if dist < R:
			p.damage(roundf(float(k.splash) * float(k.self) * (1.0 - dist / R)), null, {"impact": true})

## WHAT IT LEAVES: the fetus itself in pieces — viscera, and its own
## picture (`size` units) torn wet — blood thrown both ways, a spatter on
## what it hit, and the room painted round it.
func _gore(at: Vector3, n: Vector3, d: Vector3, who, k: Dictionary, size: Vector2) -> void:
	# which way it all goes: back off a surface (the way a ball would go),
	# on through a body
	var away := d
	if n != Vector3.ZERO:
		away = (d - 2.0 * d.dot(n) * n).normalized() * 0.6 + n * 0.4
	var lv: Level = game.level
	var sec := lv.span_at(at.x, at.y, at.z + 2.0)
	var floor_z: float = sec.floor if sec != null else at.z
	game.giblets.splatter(at, away, {"pieces": k.viscera, "force": k.force, "size": k.size,
		"floor": floor_z, "pool": k.pool if at.z - floor_z < 64.0 else 0.0,
		"spatters": k.floor, "reach": k.reach, "walls": k.walls})
	if game.chunks != null and tex != null:
		var base := at - Vector3(0, 0, size.y * 0.5)
		game.chunks.burst(tex, Rect2(0, 0, 1, 1), base, size.x, size.y, at - away * 12.0, k.picture, 0.85, 0.85)
	var fx = game.fx
	if fx != null:
		fx.blood_spray(at.x, at.y, at.z, away.x, away.y, away.z, int(k.spray) >> 1, 1.5)
		fx.blood_spray(at.x, at.y, at.z, 0.0, 0.0, 0.0, int(k.spray) >> 1, 1.1)
	var D = game.gore_decals
	if D != null:
		# THE BURST: on the wall, the ceiling or the ground it hit; and on
		# the ground under it, if that is near (a body hit: under them)
		if who != null:
			D.bleed(who, at, d)
		elif n != Vector3.ZERO:
			D.burst(at, n, float(k.burst))
		if n.z < 0.99 and at.z - floor_z < 96.0 and sec != null:
			D.burst(Vector3(at.x, at.y, floor_z), Vector3(0, 0, 1), float(k.burst) * (1.0 - 0.4 * (at.z - floor_z) / 96.0))

# ---- the picture ------------------------------------------------------------

## Every fetus in the air, a card each (fetus_card.gdshader's rows): its
## middle, its size (out of the barrel small: the barrel is a hand's
## breadth from the eye, and a whole fetus there would be the whole
## picture), its spin and its rock
func _process(dt: float) -> void:
	punch = maxf(0.0, punch - dt / float(SHOT.punch))
	var n := mini(shots.size(), MOST)
	if n == 0:
		mm.visible_instance_count = 0
		return
	var buf := PackedFloat32Array()
	buf.resize(MOST * 12)
	for i in n:
		var s: Dictionary = shots[i]
		var grow := minf(1.0, 0.15 + 0.85 * float(s.tics) / float(SHOT.grow))
		var flip := cos(float(s.flip))
		flip = signf(flip) * maxf(absf(flip), FLAT) if flip != 0.0 else 1.0
		var q := Vector3(s.x, s.y, s.z)
		var o := i * 12
		# basis x = (w, h, spin), basis y = (flip, 0, 0), basis z = up;
		# origin the middle, the game's (x, y, z) as Godot's (x, z, -y)
		buf[o] = SHOT.w * grow; buf[o + 1] = flip; buf[o + 2] = 0.0; buf[o + 3] = q.x
		buf[o + 4] = SHOT.h * grow; buf[o + 5] = 0.0; buf[o + 6] = 0.0; buf[o + 7] = q.z
		buf[o + 8] = float(s.spin); buf[o + 9] = 0.0; buf[o + 10] = 1.0; buf[o + 11] = -q.y
	mm.buffer = buf
	mm.visible_instance_count = n
