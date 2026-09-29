## MEWD — the water (js/water.js).
##
## What comes out of the fire truck's cannon (see FireTruck), and the
## third stream in the game after the flame and the cold. Particles
## leaving a nozzle, slowing in the air, landing on something — with the
## physics of a LIQUID JET:
##
##   IT IS THROWN AND IT FALLS. Water leaves a monitor nozzle fast and
##   holds its speed far better than a gas does, so the drag is gentle
##   and the reach is long, and then it comes down in an arc — which is
##   why the truck lobs it (see aim_pitch) rather than pointing it.
##
##   IT IS HEAVY, so what it lands on it puts out HARD: more heat out of
##   the grid than a burst of CO2, over a wider patch, trees along with
##   it. It cannot put back what has burned — see FireSystem.douse.
##
##   IT PUTS PEOPLE OUT, and it moves them: a person alight is soaked out
##   (Actor.soak), and anybody the jet goes through is shoved along it,
##   which includes you.
##
##   AND A BURNING VEHICLE: the jet landing by one takes the fire off it,
##   so the car the flamethrower lit does not go up if the brigade gets
##   to it first. One that has started CHARRING is past saving.
##
## Every number is per tic, like everything else in the game.
class_name WaterStream
extends RefCounted

const HOSE := {
	"perTic": 8,          # particles a tic while the cannon is open
	"speed": 36.0,        # units a tic, leaving the nozzle
	"jitter": 0.035,      # a tight jet: it is a monitor, not a spray
	"life": 70,           # long enough to come down a long way off
	"drag": 0.982,        # and it keeps its speed
	"gravity": -0.42,     # and falls
	"size0": 12.0,        # world units across leaving the nozzle
	"size1": 48.0,        # and breaking up as it goes
	"alpha": 0.72,
	"cool": 200.0,        # heat taken out of the grid where it lands
	"coolRadius": 70.0,   # and how far round
	"treeRadius": 56.0,   # how much wood one landing puts out
	"soak": 14,           # fire taken off a person it goes through, per particle
	"soakRadius": 22.0,   # and how close it has to pass
	"shove": 0.55,        # what it does to anybody standing in it, per particle
	"carRadius": 90.0,    # how close to a burning vehicle a landing puts it out
}

var game
## the fleet, for the burning vehicles a landing puts out (Vehicles)
var vehicles = null
var particles: Particles
var doused := 0
var soaked := 0
var landed := 0

## Where a jet thrown at `pitch` comes down, `drop` units below where it
## left: the same integration the particles do, one tic at a time, for
## the truck to aim with. Returns the horizontal distance.
static func hose_range(pitch: float, drop := 0.0) -> float:
	var x := 0.0
	var z := 0.0
	var vx := cos(pitch) * HOSE.speed
	var vz := sin(pitch) * HOSE.speed
	for i in HOSE.life * 2:
		x += vx
		z += vz
		vx *= HOSE.drag
		vz = vz * HOSE.drag + HOSE.gravity
		if z <= -drop and vz < 0.0:
			return x
	return x

## The furthest it goes on the flat, at the best angle.
static func hose_reach() -> float:
	var best := 0.0
	var p := 0.0
	while p <= 0.9:
		best = maxf(best, hose_range(p, 0.0))
		p += 0.02
	return best

## The pitch that lands a jet `dist` away and `drop` below the nozzle: the
## LOW solution, since a fire truck plays its jet on a fire rather than
## mortaring it; null if it is out of reach.
static func aim_pitch(dist: float, drop := 0.0):
	var lo := -0.8
	var hi := 0.75
	if hose_range(hi, drop) < dist:
		return null
	if hose_range(lo, drop) >= dist:
		return lo
	for k in 22:
		var m := (lo + hi) / 2.0
		if hose_range(m, drop) < dist:
			lo = m
		else:
			hi = m
	return (lo + hi) / 2.0

func _init(g) -> void:
	game = g
	# ALPHA, like the cold: water is something in the way, not light
	var at := Effects.atlases()
	particles = Particles.new({"max": 900, "map": at.smoke, "frames": Effects.SMOKE_PUFFS, "blend": "mix",
		"fullbright": false, "near_shrink": 40.0, "order": 12})
	particles.mat.set_shader_parameter("light", 0.9)
	particles.name = "water"

static func _r() -> float:
	return U.p_random() / 255.0

## One tic of jet from a point (map space), in a direction. Positive
## pitch is up.
func fire(origin: Vector3, angle: float, pitch: float) -> void:
	var n: int = HOSE.perTic
	for k in n:
		var a: float = angle + (_r() - 0.5) * HOSE.jitter * 2.0
		var p: float = pitch + (_r() - 0.5) * HOSE.jitter * 2.0
		var sp: float = HOSE.speed * (0.94 + _r() * 0.12)
		var ch := cos(p)
		var vx := cos(a) * ch * sp
		var vy := sin(a) * ch * sp
		var vz := sin(p) * sp
		var f := float(k) / n
		particles.spawn({
			"x": origin.x + vx * f, "y": origin.y + vy * f, "z": origin.z + vz * f,
			"vx": vx, "vy": vy, "vz": vz, "age": f,
			"life": roundi(HOSE.life * (0.9 + _r() * 0.2)),
			"size0": HOSE.size0, "size1": HOSE.size1,
			"c0": Color(0.92, 0.97, 1.0, HOSE.alpha), "c1": Color(0.62, 0.74, 0.88, 0.25),
			"frame": float(U.p_random() & 7), "frameRate": 0.3,
			"drag": HOSE.drag, "gravity": HOSE.gravity,
		})

func tic() -> void:
	if particles.count == 0:
		return
	var g = game
	var lv: Level = g.level
	var p = g.player
	particles.tic(func(i: int, nx: float, ny: float, nz: float) -> bool:
		var x: float = particles.px[i]
		var y: float = particles.py[i]
		var z: float = particles.pz[i]
		var wall := lv.ray_hit_wall(x, y, z, nx, ny, nz)
		if not wall.is_empty():
			_land(wall.x, wall.y, wall.z)
			return true
		var sec := lv.span_at(nx, ny, z)
		var floor := sec.floor if sec else 0.0
		if nz <= floor + 3.0:
			_land(nx, ny, floor)
			return true
		if sec and sec.ceil_tex != "SKY" and nz >= sec.ceil - 4.0:
			_land(nx, ny, sec.ceil)
			return true
		# anybody it goes through: put out, and pushed along it
		var vx := nx - x
		var vy := ny - y
		var vl := maxf(0.0001, sqrt(vx * vx + vy * vy))
		for a in g.blockmap.near(nx, ny):
			if a.removed or a.dead or a.vehicle != null:
				continue
			var rr: float = a.radius + HOSE.soakRadius
			if U.dist2(nx, ny, a.x, a.y) > rr * rr:
				continue
			if nz < a.z - 10.0 or nz > a.z + a.height + 10.0:
				continue
			if a.soak(HOSE.soak):
				soaked += 1
			if a.shootable and not a.frozen:
				a.momx += vx / vl * HOSE.shove
				a.momy += vy / vl * HOSE.shove
		if p != null and not p.dead:
			var rr: float = p.radius + HOSE.soakRadius
			if U.dist2(nx, ny, p.x, p.y) < rr * rr and nz > p.z - 10.0 and nz < p.z + 70.0:
				p.momx += vx / vl * HOSE.shove * 0.5
				p.momy += vy / vl * HOSE.shove * 0.5
		return false)

## A drop has arrived somewhere: the heat comes out of the store's grid
## and the wood's, and a burning vehicle close by is put out.
func _land(x: float, y: float, z: float) -> void:
	var g = game
	landed += 1
	var cooled := 0
	if g.fire != null:
		cooled = g.fire.douse(x, y, HOSE.cool, HOSE.coolRadius, z)
	doused += cooled
	# STEAM off whatever it has just put out: the one sign at a distance
	# that the water is winning
	if cooled and (landed & 7) == 0 and g.fx != null:
		g.fx.puff(x, y, z + 12.0, 34.0, 110)
	var forest = g.get("forest")
	if forest != null:
		forest.douse(x, y, HOSE.treeRadius)
	if vehicles != null:
		var r2: float = HOSE.carRadius * HOSE.carRadius
		for v in vehicles.all:
			if v.burning > 0 and v.state != "charring" and U.dist2(x, y, v.x, v.y) < r2:
				v.put_out()
	if (landed & 3) == 0 and g.fx != null:
		g.fx.chill_splash(x, y, z)

func live_count() -> int:
	return particles.count

func draw() -> void:
	particles.draw()
