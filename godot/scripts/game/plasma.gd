## MEWD — the plasma rifle, the Sarakawa Mk II (Weapons "PLASMA").
##
## At the user's request: "single shot plasma rifle, semi-auto fire rate,
## precise, thick long pellet beam". One pull, one bolt: a hitscan down
## the exact line of the eye — no spread at all — for 110 to 150, and the
## bolt drawn flying that line, a long thick pellet of blue plasma with a
## white-hot core, rounded at both ends. Like a tracer (render/tracers.gd)
## it is the picture of a shot that has already landed, so it is fast:
## the head reaches whatever was hit and the tail follows it in. Where it
## lands, a flash of blue that swells and is gone, a hot scorch (the
## hitscan's `hot` hole) and the light of it on the ground.
##
## One ImmediateMesh for every bolt and flash, rebuilt each frame, through
## its own shader (plasma_bolt.gdshader): each quad carries where across
## and along it a fragment is, and in UV2 what it is, so the shader can round the ends and glow
## the edges.
class_name PlasmaBolts
extends MeshInstance3D

const MAX_BOLTS := 24
## units a tic, how long the pellet is, how thick (32 units a metre)
const SPEED := 150.0
const LENGTH := 640.0
const WIDTH := 14.0
## the glow round it, as a multiple of the width
const HALO := 2.4
const NEAR_EYE := 30.0
## how far out of the muzzle it is first drawn
const START := 64.0
## the beads down its length (see draw_for)
const BEADS := 16
## the flash where it lands: tics, and how big it gets
const FLASH_TICS := 9
const FLASH_SIZE := 70.0

var game = null
var list := []
var flashes := []
var im := ImmediateMesh.new()
## shots fired, for the tests
var fired := 0

func _init(g = null) -> void:
	game = g
	name = "PlasmaBolts"

func _ready() -> void:
	mesh = im
	var m := ShaderMaterial.new()
	m.shader = preload("res://godot/shaders/plasma_bolt.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))

## The trigger: one bolt, straight down the eye.
func fire(p) -> void:
	fired += 1
	var from: Vector3 = game.nozzle(p)
	var seen: Vector3 = game.muzzle_view(p, from) if game.has_method("muzzle_view") else from
	game.hitscan(p, p.angle, 6000.0, Weapons.plasma_damage(), {"shot": true, "hot": true, "bites": 99, "pitch": p.pitch, "from": from})
	var to: Vector3 = game.last_hit
	spawn(seen, to)
	if game.sound != null:
		game.sound.play("plasma", p, {"rate": 1.75})
	if game.fx != null:
		game.fx.glow_at(from.x, from.y, 0.6)
	game.noise(p, 800.0)

## from, to: map space (x, y, z)
func spawn(from: Vector3, to: Vector3) -> void:
	var d := from.distance_to(to)
	if list.size() >= MAX_BOLTS:
		list.pop_front()
	list.append({"a": U.v3(from.x, from.y, from.z), "b": U.v3(to.x, to.y, to.z), "len": d, "trav": 0.0,
		"at": to, "landed": d < NEAR_EYE})

func tic() -> void:
	for t in list:
		# (a picture's bolt can be held where it is in flight: tests/candy_shot.gd)
		t.trav = float(t.hold) if t.has("hold") else t.trav + SPEED
		if not t.landed and t.trav >= t.len:
			t.landed = true
			flashes.append({"p": U.v3(t.at.x, t.at.y, t.at.z), "t": 0, "map": t.at})
	list = list.filter(func(t): return t.trav - LENGTH < t.len)
	for f in flashes:
		f.t += 1
		if game != null and game.fx != null and f.t == 1:
			game.fx.glow_at(f.map.x, f.map.y, 1.0)
	flashes = flashes.filter(func(f): return f.t < FLASH_TICS)

func draw_for(cam: Camera3D, f: float) -> void:
	im.clear_surfaces()
	if list.is_empty() and flashes.is_empty():
		return
	var eye := to_local(cam.global_position)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for t in list:
		if t.len <= NEAR_EYE:
			continue
		var trav: float = t.trav + SPEED * f
		var head := minf(trav, t.len)
		# (not the first two metres out of the muzzle: so near the eye the
		# glow would be a wall of light across the picture)
		var tail := maxf(START, trav - LENGTH)
		if head <= tail:
			continue
		var dir: Vector3 = (t.b - t.a) / t.len
		# (the rounded ends stick out half a width past the line's ends)
		var r := WIDTH * HALO * 0.5
		var h: Vector3 = t.a + dir * (head + r * 0.3)
		var tl: Vector3 = t.a + dir * maxf(0.0, tail - r * 0.3)
		var side := dir.cross(eye - (h + tl) * 0.5).normalized() * r
		# UV: x along, 0 tail to 1 head; y across, -1 to 1. UV2: what it is
		# (0 a bolt) and how long the quad is against how wide, for the
		# rounding (data rides in UV2, not COLOR: a colour can be decoded
		# from sRGB on its way in, and these are numbers)
		var aspect := clampf(h.distance_to(tl) / (r * 2.0), 1.0, 200.0)
		var c := Vector2(0.0, aspect)
		_v(tl - side, Vector2(0, -1), c)
		_v(h - side, Vector2(1, -1), c)
		_v(h + side, Vector2(1, 1), c)
		_v(tl - side, Vector2(0, -1), c)
		_v(h + side, Vector2(1, 1), c)
		_v(tl + side, Vector2(0, 1), c)
		n += 1
		# AND A STRING OF BEADS facing the eye down its length: seen from
		# behind — down the line it flies, as it always is from the gun that
		# fired it — the ribbon is edge on, and the beads are the bolt (UV2.x
		# 1: a bead; UV2.y how far along, the head brightest)
		var span := head - tail
		for k in BEADS:
			var q := float(k) / float(BEADS - 1)
			var at: Vector3 = t.a + dir * (tail + span * q)
			_disc(at, eye, WIDTH * (0.75 + 0.35 * q), Vector2(1.0, q))
			n += 1
	for fl in flashes:
		# a disc facing the eye, swelling and fading (UV2.x 2: a flash; UV2.y
		# how far through it is)
		var k := (float(fl.t) + f) / float(FLASH_TICS)
		var s := FLASH_SIZE * (0.45 + 0.75 * k)
		_disc(fl.p + (eye - fl.p).normalized() * 6.0, eye, s, Vector2(2.0, clampf(k, 0.0, 1.0)))
		n += 1
	if n == 0:
		# (an empty surface is an error: one degenerate triangle)
		for i in 3:
			_v(Vector3(), Vector2(), Vector2(3.0, 0.0))
	im.surface_end()

## a square facing the eye, `s` from the middle to an edge
func _disc(p: Vector3, eye: Vector3, s: float, c: Vector2) -> void:
	var to_eye := (eye - p).normalized()
	var u := to_eye.cross(Vector3.UP)
	if u.length_squared() < 1e-4:
		u = Vector3.RIGHT
	u = u.normalized() * s
	var v := u.cross(to_eye).normalized() * s
	_v(p - u - v, Vector2(0, -1), c)
	_v(p + u - v, Vector2(1, -1), c)
	_v(p + u + v, Vector2(1, 1), c)
	_v(p - u - v, Vector2(0, -1), c)
	_v(p + u + v, Vector2(1, 1), c)
	_v(p - u + v, Vector2(0, 1), c)

func _v(p: Vector3, uv: Vector2, c: Vector2) -> void:
	im.surface_set_uv(uv)
	im.surface_set_uv2(c)
	im.surface_add_vertex(p)
