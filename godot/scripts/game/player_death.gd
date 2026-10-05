## MEWD — YOU DIED, at the user's request: "on death, i want a circling
## camera around the player's death spawn point, massive blood spatter,
## and an endless stream of body parts spewing forth from where the player
## died forever until the game is reset; grab the death animation and
## gravestone from verdictzero/galvarius, and the death behavior from
## that".
##
## GALVARIUS'S DEATH (game_over_screen.gd, player_controller.gd,
## music_manager.gd there), here in the game's own units and tics:
##   * THE BURST, seen through the player's own eye as it drops to the
##     ground (Player.death_tic) for BURST_TICS: the body goes off — the
##     warhead's evisceration three times over, a great pool, the floor
##     painted out to FLOOR_REACH all round, a spray of blood in the air —
##     and the HEAD comes off (galvarius's chad_head), thrown forward and
##     up, bouncing, bleeding where it goes.
##   * A GRAVESTONE where they fell (galvarius's tombstone.png), two-faced
##     so it reads from either side, rising out of the ground.
##   * THE DEATH CAMERA: after the burst the eye leaves the body and
##     circles the place, ORBIT_R out and ORBIT_H up, ORBIT_SPEED radians
##     a second, looking at a point just above it.
##   * THE FOUNTAIN, from then until the game is reset: body parts
##     (galvarius's gore pieces, packed into assets/gore/death_gore.png)
##     spewed up and out of the spot a wave every WAVE_EVERY tics, every
##     one landing in a spatter and lying there; the blood jetting with
##     them in pulses, like a heart still going.
##   * The music out, two seconds of nothing, then galvarius's death music
##     (Music.dirge), round again for as long as it takes.
##   * YOU DIED on the screen (Hud), and after INPUT_DELAY fire, jump or
##     use starts the level again (Game.restart_wanted, main.gd).
## A match keeps its own idea of a death (MatchRules: a frag and a
## respawn); this is for a game alone.
class_name PlayerDeath
extends Node3D

const BURST_TICS := 3 * 35
const INPUT_DELAY := 3 * 35
const ORBIT_R := 300.0
const ORBIT_H := 150.0
const ORBIT_SPEED := 0.5
const LOOK_UP := 32.0
const FLOOR_REACH := 420.0
const FLOOR_SPATTERS := 48

## the fountain: a wave of `WAVE` parts every WAVE_EVERY tics from round
## the spot (EMITTERS of them, galvarius's four, EMIT_R out), thrown up at
## `rise` and out at `out` units a tic
const WAVE_EVERY := 3
const WAVE := 4
const EMITTERS := 4
const EMIT_R := [10.0, 40.0]
const RISE := [7.0, 15.0]
const OUT := [1.0, 5.5]
const PART_SIZE := [10.0, 24.0]
const PART_GRAVITY := -0.45
## a part lies where it lands this long (tics) and then goes: the pool is
## PARTS_MAX, so the oldest go first as the new ones come
const PART_LIFE := 30 * 35
const PARTS_MAX := 1600
const STRIP := "res://assets/gore/death_gore.png"
const STRIP_CELLS := 14
## the head, its own picture, and the gravestone
const HEAD := "res://assets/gore/chad_head.png"
const HEAD_SIZE := 30.0
const STONE := "res://assets/things/tombstone.png"
const STONE_H := 64.0
const STONE_RISE := 35

var game
var active := false
var t := 0
var at := Vector3.ZERO
var facing := 0.0
var parts: Particles
## parts that have come to rest (they lie and do not fall again)
var rest := PackedByteArray()
var waves := 0
var landed := 0
var marks := 0
var orbit := 0.0
var head: MeshInstance3D
var head_p := Vector3.ZERO
var head_v := Vector3.ZERO
var head_bounces := 0
var stone: Node3D
var stone_floor := 0.0
var emit := []
var _settle := []

func _init(g) -> void:
	game = g

func _ready() -> void:
	parts = Particles.new({"max": PARTS_MAX, "map": load(STRIP), "frames": STRIP_CELLS, "blend": "mix",
		"fullbright": false, "near_shrink": 60.0, "order": 13})
	parts.mat.set_shader_parameter("light", U.col(0.9))
	rest.resize(PARTS_MAX)
	add_child(parts)

static func _r() -> float:
	return U.p_random() / 255.0

func _floor(x: float, y: float) -> float:
	var lv = game.level
	if lv is IslandLevel:
		var f: float = lv.floor_at(x, y)
		return 0.0 if f <= IslandLevel.NO_FLOOR else f
	var s: Level.Sector = lv.span_at(x, y, at.z + 8.0)
	return s.floor if s else at.z

## The player `p` is dead. The burst, the head, the stone, the music.
func begin(p) -> void:
	if active:
		return
	active = true
	t = 0
	at = Vector3(p.x, p.y, p.z)
	facing = p.angle
	orbit = p.angle + PI
	emit.clear()
	for i in EMITTERS:
		var a := TAU * i / EMITTERS + _r() * 0.6
		var r: float = lerpf(EMIT_R[0], EMIT_R[1], _r())
		emit.append(Vector2(cos(a) * r, sin(a) * r))
	_burst()
	_throw_head()
	_raise_stone()
	var m = _music()
	if m != null and m.has_method("dirge"):
		m.dirge()

func _music():
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get("music")

## THE BODY GOES OFF: everything a warhead does to somebody, three times
## over from three ways, and the ground painted all round
func _burst() -> void:
	var body := {"x": at.x, "y": at.y, "z": at.z, "height": 56.0, "frozen": false, "info": {"height": 56.0}}
	var G = game.giblets
	if G != null:
		for k in 3:
			var a := facing + TAU * k / 3.0
			G.eviscerate(body, Vector3(at.x - cos(a) * 20.0, at.y - sin(a) * 20.0, at.z + 10.0), 1.5)
		# the floor out to FLOOR_REACH every way, laid down over the next tics
		for k in FLOOR_SPATTERS:
			var a := _r() * TAU
			G.room.append([Giblets.ROOM_FLOOR, at.x, at.y, at.z, cos(a), sin(a), 30.0 + _r() * FLOOR_REACH, 40.0 + _r() * 70.0])
	var D = game.gore_decals
	if D != null:
		D.pool(at.x, at.y, at.z, 150.0)
		for k in 8:
			var a := _r() * TAU
			var d := 40.0 + _r() * 120.0
			D.pool(at.x + cos(a) * d, at.y + sin(a) * d, _floor(at.x + cos(a) * d, at.y + sin(a) * d), 50.0 + _r() * 60.0)
			marks += 1
		marks += 1
	var fx = game.fx
	if fx != null:
		fx.blood_spray(at.x, at.y, at.z + 40.0, 0.0, 0.0, 1.0, 120, 2.6)
		fx.blood_spray(at.x, at.y, at.z + 30.0, 0.0, 0.0, 0.0, 120, 2.0)
		for k in 8:
			fx.blood_puff(at.x + (_r() - 0.5) * 40.0, at.y + (_r() - 0.5) * 40.0, at.z + 10.0 + k * 6.0)
	game.play_sound("gib", game.player)

## THE HEAD, off and away (galvarius's _eject_head): forward and up,
## bouncing to a stop, bleeding all the way
func _throw_head() -> void:
	var tex: Texture2D = load(HEAD)
	if tex == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(HEAD_SIZE * tex.get_width() / float(tex.get_height()), HEAD_SIZE)
	head = MeshInstance3D.new()
	head.mesh = q
	head.material_override = m
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	head_p = Vector3(at.x, at.y, at.z + 50.0)
	var a := facing + (_r() - 0.5) * 0.6
	var sp := 5.0 + _r() * 3.0
	head_v = Vector3(cos(a) * sp, sin(a) * sp, 9.0 + _r() * 4.0)
	head.position = U.v3(head_p.x, head_p.y, head_p.z + HEAD_SIZE * 0.5)

func _head_tic() -> void:
	if head == null:
		return
	if head_v.length_squared() < 0.01 and head_bounces > 0:
		return
	head_v.z -= 0.5
	var n := head_p + head_v
	var f := _floor(n.x, n.y)
	if n.z <= f:
		n.z = f
		head_bounces += 1
		head_v = Vector3(head_v.x * 0.6, head_v.y * 0.6, -head_v.z * 0.4)
		if head_v.z < 1.0:
			head_v.z = 0.0
		if game.gore_decals != null:
			game.gore_decals.pool(n.x, n.y, f, 30.0 + _r() * 20.0)
			marks += 1
		if absf(head_v.z) < 0.01 and Vector2(head_v.x, head_v.y).length() < 0.4:
			head_v = Vector3.ZERO
	head_p = n
	head.position = U.v3(n.x, n.y, n.z + HEAD_SIZE * 0.5)
	if game.fx != null and t % 2 == 0 and head_v.length_squared() > 0.5:
		game.fx.blood_spray(n.x, n.y, n.z + 10.0, -head_v.x, -head_v.y, 0.2, 2, 0.4)

## THE GRAVESTONE (galvarius's _spawn_tombstone): two faces, back to back,
## so it reads from all the way round the orbit; facing the way they did
func _raise_stone() -> void:
	var tex: Texture2D = load(STONE)
	if tex == null:
		return
	stone = Node3D.new()
	add_child(stone)
	var w := STONE_H * tex.get_width() / float(tex.get_height())
	var q := QuadMesh.new()
	q.size = Vector2(w, STONE_H)
	q.center_offset = Vector3(0.0, STONE_H * 0.5, 0.0)
	for k in 2:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.85, 0.85, 0.85)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# (z apart so the faces do not fight)
		mi.position = Vector3(0.0, 0.0, 0.3 if k == 0 else -0.3)
		mi.rotation.y = 0.0 if k == 0 else PI
		stone.add_child(mi)
	# a little behind where they fell, so the fountain is in front of it
	var sx := at.x - cos(facing) * 60.0
	var sy := at.y - sin(facing) * 60.0
	stone_floor = _floor(sx, sy)
	stone.position = U.v3(sx, sy, stone_floor - STONE_H)
	# (its face toward where they fell: the quad faces its +Z, which is map
	# angle a at rotation.y = a + PI/2)
	stone.rotation.y = facing + PI / 2.0

func tic() -> void:
	if not active:
		parts.tic()
		return
	t += 1
	_head_tic()
	if stone != null and t <= STONE_RISE:
		var k := float(t) / STONE_RISE
		var p := stone.position
		stone.position = Vector3(p.x, stone_floor - STONE_H * (1.0 - k) * (1.0 - k), p.z)
	# THE FOUNTAIN, from the end of the burst on, for ever
	if t >= BURST_TICS and t % WAVE_EVERY == 0:
		_wave()
	if t >= BURST_TICS and game.fx != null and (t % 12) < 4:
		var k := 0.6 + 0.4 * sin(t * 0.21)
		game.fx.blood_spray(at.x, at.y, at.z + 8.0, 0.0, 0.0, 1.0, int(4 + 6 * k), 1.6 + 1.2 * k)
	parts.tic(_land)
	for e in _settle:
		parts.pz[e[0]] = e[1]
	_settle.clear()

func _wave() -> void:
	waves += 1
	for e in emit:
		for k in WAVE:
			var a := _r() * TAU
			var o: float = lerpf(OUT[0], OUT[1], _r())
			var s: float = lerpf(PART_SIZE[0], PART_SIZE[1], _r())
			var fr := float(U.p_random() % STRIP_CELLS)
			# (the head and the heaps, rarely, and bigger: galvarius's "rare")
			if fr >= 11.0:
				if (U.p_random() & 7) != 0:
					fr = float(U.p_random() % 11)
				else:
					s *= 1.6
			var c: Color = Color(0.8, 0.6, 0.6) if (k & 1) == 0 else Color.WHITE
			var i := parts.put(at.x + e.x, at.y + e.y, at.z + 4.0 + _r() * 8.0, cos(a) * o, sin(a) * o,
				lerpf(RISE[0], RISE[1], _r()), PART_LIFE, s, s, c, c, fr, 0.0, 0.995, PART_GRAVITY)
			if i >= 0:
				rest[i] = 0

## a part comes down: a spatter where it hits, and it lies there
func _land(i: int, nx: float, ny: float, nz: float) -> bool:
	if rest[i]:
		return false
	var f := _floor(nx, ny)
	if nz > f + 1.0:
		return false
	rest[i] = 1
	parts.vx[i] = 0.0
	parts.vy[i] = 0.0
	parts.vz[i] = 0.0
	parts.gravity[i] = 0.0
	# (lying on the ground, put there after the tic has moved it: _settle)
	_settle.append([i, f + parts.size0[i] * 0.3])
	landed += 1
	var D = game.gore_decals
	if D != null and (landed % 3) == 0:
		D.blood(Vector3(nx, ny, f), Vector3(0, 0, 1), Vector3(_r() - 0.5, _r() - 0.5, 0.0), 30.0 + _r() * 34.0)
		marks += 1
	return false

## Restart is allowed once the burst has had its say.
func can_restart() -> bool:
	return active and t >= INPUT_DELAY

## THE DEATH CAMERA, after the burst: round and round the place.
func orbiting() -> bool:
	return active and t >= BURST_TICS

func place_camera(cam: Camera3D, f: float) -> void:
	var secs := (t - BURST_TICS + f) / 35.0
	var a := orbit + secs * ORBIT_SPEED
	var cx := at.x + cos(a) * ORBIT_R
	var cy := at.y + sin(a) * ORBIT_R
	var cz := maxf(at.z + ORBIT_H, _floor(cx, cy) + 48.0)
	cam.position = U.v3(cx, cy, cz)
	# (in the game's own space: the game node is scaled, look_at is global)
	cam.basis = Basis.looking_at(U.v3(at.x, at.y, at.z + LOOK_UP) - cam.position, Vector3.UP)

func draw() -> void:
	parts.draw()
