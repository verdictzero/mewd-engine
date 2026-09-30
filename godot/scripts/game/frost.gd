## MEWD — the cold (js/frost.js).
##
## What comes out of the extinguisher: the flamethrower's stream built
## the other way up. The same shape — a few particles a tic leaving the
## nozzle at speed, slowing, landing — and the opposite verb at every
## step: it takes heat OUT of the fuel grid, it puts trees back, and
## what it does to a person is hold them rather than kill them. A jet of
## gas WASHES OVER whoever it passes and carries on to the shelf behind,
## so a queue freezes as a queue and the fire behind it goes out too.
## WHAT IT CANNOT DO IS UNDO ANYTHING: burnt is burnt.
class_name FrostStream
extends RefCounted

const JET := {
	"perTic": 7, "speed": 34.0, "jitter": 0.07, "life": 26, "drag": 0.935, "gravity": -0.30,
	"size0": 10.0, "size1": 62.0, "alpha": 0.42, "cool": 150.0, "coolRadius": 46.0,
	"treeRadius": 34.0, "chill": 9.0, "chillRadius": 26.0,
}

var game
var particles: Particles
var firing := 0
var hits := 0
var doused := 0.0
var frozen := 0

func _init(g) -> void:
	game = g
	particles = Particles.new({"max": 380, "map": Effects.atlases().smoke, "frames": Effects.SMOKE_PUFFS,
		"blend": "mix", "fullbright": false, "near_shrink": 40.0})
	particles.mat.set_shader_parameter("light", 0.95)

func fire(origin: Vector3, angle: float, pitch: float) -> void:
	firing = 3
	var s := JET
	for k in s.perTic:
		var a: float = angle + (U.p_random() / 255.0 - 0.5) * s.jitter * 2.0
		var pt: float = pitch + (U.p_random() / 255.0 - 0.5) * s.jitter * 1.4
		var sp: float = s.speed * (0.9 + (U.p_random() / 255.0) * 0.2)
		var ch := cos(pt)
		var v := Vector3(cos(a) * ch * sp, sin(a) * ch * sp, sin(pt) * sp)
		var f: float = float(k) / s.perTic
		particles.spawn({
			"x": origin.x + v.x * f, "y": origin.y + v.y * f, "z": origin.z + v.z * f,
			"vx": v.x, "vy": v.y, "vz": v.z, "age": f,
			"life": roundf(s.life * (0.85 + (U.p_random() / 255.0) * 0.3)),
			"size0": s.size0, "size1": s.size1,
			"c0": Color(0.92, 0.99, 1.05, s.alpha), "c1": Color(0.42, 0.60, 0.80, 0.0),
			"frame": float(U.p_random() & 7), "frameRate": 0.26,
			"drag": s.drag, "gravity": s.gravity,
		})

func tic() -> void:
	if firing > 0:
		firing -= 1
	particles.tic(_collide)

func _collide(i: int, nx: float, ny: float, nz: float) -> bool:
	var P := particles
	var lv: Level = game.level
	var x := P.px[i]
	var y := P.py[i]
	var z := P.pz[i]
	var wall := lv.ray_hit_wall(x, y, z, nx, ny, nz)
	if not wall.is_empty():
		_land(wall.x, wall.y, wall.z)
		return true
	var sec := lv.span_at(nx, ny, z)
	var floor := sec.floor if sec else 0.0
	if nz <= floor + 4.0:
		_land(nx, ny, floor)
		return true
	if sec and sec.ceil_tex != "SKY" and nz >= sec.ceil - 4.0:
		_land(nx, ny, sec.ceil)
		return true
	var r: float = JET.chillRadius
	for a in game.blockmap.near_radius(nx, ny, 64.0):
		if a.removed or a.dead or not a.info.get("freezable", false):
			continue
		var rr: float = a.radius + r
		if U.dist2(nx, ny, a.x, a.y) > rr * rr:
			continue
		if nz < a.z - 10.0 or nz > a.z + a.height + 14.0:
			continue
		if a.chill(JET.chill):
			frozen += 1
	return false

func _land(x: float, y: float, z: float) -> void:
	hits += 1
	if game.fx != null:
		game.fx.chill_splash(x, y, z)
