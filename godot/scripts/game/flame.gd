## MEWD — the flame (js/flame.js).
##
## What comes out of the gun: a STREAM, a few particles a tic leaving the
## nozzle at speed in a slight spread. They slow in the air, they drop,
## and where one lands it puts heat into the world — so the flame goes
## where you point it, it reaches, and it arcs down to the floor a dozen
## metres out unless you lift the nozzle, which is the whole feel of a
## flamethrower. Somebody it touches is LIT FIRST, THEN HURT: lighting
## starts their countdown, and a thing with a countdown running ignores
## fire damage until it runs out — which is why a shopper runs now
## instead of coming apart where they stood.
class_name FlameStream
extends RefCounted

const STREAM := {
	"perTic": 6, "speed": 30.0, "jitter": 0.04, "life": 40, "drag": 0.972, "gravity": -0.22,
	"size0": 8.0, "size1": 44.0, "alpha": 0.5, "heat": 36.0, "heatRadius": 22.0, "treeRadius": 26.0,
}

var game
var particles: Particles
var firing := 0
var hits := 0
## where the burning end of the stream is, for its light (x, y, z, weight)
var glow := Vector4()

func _init(g) -> void:
	game = g
	# the stream out of the gun is fireballs (js/main.js streamAtlas)
	particles = Particles.new({"max": 420, "blend": "add", "map": Effects.atlases().fireball, "frames": Effects.FIREBALLS, "near_shrink": 30.0})

func stream_tic(p, d: Dictionary) -> void:
	if p.ammo[d.ammo] <= 0:
		p.fire_index = -1
		p.dry[d.ammo] = true
		return
	p.ammo[d.ammo] -= 1
	if d.stream == "frost":
		if game.frost != null:
			game.frost.fire(game.nozzle(p), p.angle, p.pitch)
		return
	fire(game.nozzle(p), p.angle, p.pitch)

## One tic's worth of flame from a point (map space), in a direction.
func fire(origin: Vector3, angle: float, pitch: float) -> void:
	firing = 3
	var s := STREAM
	for k in s.perTic:
		var a: float = angle + (U.p_random() / 255.0 - 0.5) * s.jitter * 2.0
		var pt: float = pitch + (U.p_random() / 255.0 - 0.5) * s.jitter * 1.4
		var sp: float = s.speed * (0.94 + (U.p_random() / 255.0) * 0.12)
		var ch := cos(pt)
		var v := Vector3(cos(a) * ch * sp, sin(a) * ch * sp, sin(pt) * sp)
		# staggered along the tic: a line, not a string of beads
		var f: float = float(k) / s.perTic
		particles.spawn({
			"x": origin.x + v.x * f, "y": origin.y + v.y * f, "z": origin.z + v.z * f,
			"vx": v.x, "vy": v.y, "vz": v.z, "age": f,
			"life": roundf(s.life * (0.9 + (U.p_random() / 255.0) * 0.2)),
			"size0": s.size0, "size1": s.size1,
			"c0": Color(1.0, 0.92, 0.66, s.alpha), "c1": Color(1.0, 0.32, 0.08, 0.0),
			"frame": float(U.p_random() & 7), "frameRate": 0.6,
			"drag": s.drag, "gravity": s.gravity,
		})

func tic() -> void:
	if firing > 0:
		firing -= 1
	particles.tic(_collide)
	var sum := Vector3()
	var n := 0
	for i in particles.max:
		if not particles.alive[i] or particles.age[i] < 4:
			continue
		sum += Vector3(particles.px[i], particles.py[i], particles.pz[i])
		n += 1
	glow = Vector4(sum.x / n, sum.y / n, sum.z / n, minf(1.0, n / 20.0)) if n else Vector4()

func _collide(i: int, nx: float, ny: float, nz: float) -> bool:
	var P := particles
	var lv: Level = game.level
	var x := P.px[i]
	var y := P.py[i]
	var z := P.pz[i]
	# walls first: a flame that reaches through a hedge is a cheat code
	var wall := lv.ray_hit_wall(x, y, z, nx, ny, nz)
	if not wall.is_empty():
		_land(wall.x, wall.y, wall.z, Decals.wall_normal(wall.line, x, y))
		return true
	var sec := lv.span_at(nx, ny, z)
	var floor := sec.floor if sec else 0.0
	if nz <= floor + 4.0:
		_land(nx, ny, floor, Vector3(0, 0, 1))
		return true
	if sec and sec.ceil_tex != "SKY" and nz >= sec.ceil - 4.0:
		_land(nx, ny, sec.ceil, Vector3(0, 0, -1))
		return true
	for a in game.blockmap.near(nx, ny):
		if a.removed or a.dead or not a.shootable:
			continue
		var rr: float = a.radius + 12.0
		if U.dist2(nx, ny, a.x, a.y) > rr * rr:
			continue
		if nz < a.z - 6.0 or nz > a.z + a.height + 10.0:
			continue
		_burn_actor(a, nx, ny, nz)
		return true
	if game.forest != null and game.forest.hits_tree(nx, ny, nz):
		_land(nx, ny, nz, Vector3())
		return true
	return false

func _land(x: float, y: float, z: float, _surface: Vector3) -> void:
	hits += 1
	if game.fx != null:
		game.fx.splash(x, y, z)

func _burn_actor(a, x: float, y: float, z: float) -> void:
	if a.flammable:
		a.ignite(300)
	a.damage(5 + (U.p_random() % 5), game.player, {"fire": true, "stream": true})
	if game.fx != null:
		game.fx.splash(x, y, z)
