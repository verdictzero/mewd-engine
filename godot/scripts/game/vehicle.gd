## MEWD — one vehicle: the car park, and what happens to it
## (js/vehicles.js: Vehicle).
##
## A vehicle stands in a bay, catches, CHARS, goes up, leaves the
## ground, comes down on its roof, goes up again, and lies there burning
## while the pieces of it smoulder on the tarmac around it.
##
## THE TUMBLE IS NOT A PHYSICS ENGINE and does not want to be. It is
## Doom's own arithmetic — a velocity, a gravity of 0.85 units per tic
## per tic, which is the same fall the sparks off a broken light take.
## Three spin rates are integrated separately as Euler angles in the
## order the node is built for (YXZ): yaw, then roll about the car's own
## length, then pitch nose over tail.
##
## IT LANDS ON ITS ROOF BECAUSE THE ROLL RATE IS CHOSEN SO IT WILL. The
## flight is ballistic, so the time it will be in the air is known the
## moment it leaves the ground — 2v/g — and half a turn divided by that
## completes the roll as it arrives. It is aimed, not simulated.
##
## HOW HIGH A CAR ON ITS ROOF SITS is not a number anybody types in: the
## eight corners of its own box are turned by the orientation it has and
## the lowest one is put on the tarmac.
class_name Vehicle
extends RefCounted

const GRAVITY := 0.85        # units per tic per tic — the sparks' own fall

const HEALTH := 150.0        # a few seconds of being on fire
## HOW MANY ROUNDS IT TAKES, at the user's request: what a round does to
## a vehicle is divided by this — twenty for a car in the lot, eighty-odd
## minigun rounds; the police van and the APC set their own, much higher
const SHOT_ARMOUR := 20.0
const BURN_EVERY := 10       # tics between a burning car taking it
const BURN_DAMAGE := 12.0
const FUEL := 520.0          # what a tank is worth to the tarmac under it
const CATCH_TICS := 40 * U.TICRATE

const LIFT := [13.0, 19.0]   # how hard it leaves the ground
const DRIFT := 1.7           # and how far sideways
const YAW_SPIN := 0.055      # slew, in radians a tic
const PITCH_SPIN := 0.030    # nose over tail
const CANT := 0.22           # how far past half a turn it may land
const TILT := 0.12           # and how crooked it is left lying, nose to tail
const ROLL_CANT := 0.08      # and side to side
const SETTLE := 10           # tics spent rocking onto the roof

const WRECK_LIT := 0.42      # a burnt car is a dark car
const WRECK_CHAR := 1.0      # and the shader puts the coals on it
const CHUNK_CHAR := 0.85

## IT CHARS FIRST, at the user's request: the tank going is the END of
## something you can watch, and how long that takes is rolled per car so
## a row of them lit together does not go off on one fuse
const CHAR_TICS := [4.5 * U.TICRATE, 7.5 * U.TICRATE]

const BLAST_R := 210.0       # what the launch bang used to reach
const BLAST_DMG := 90.0
## AND THE BANG AT THE END OF THE CHAR IS FOUR OF THE OLD ONE, also at the
## user's request: the radius doubled (a quadrupled area) and the damage
## doubled
const FINAL := 4
const FINAL_R := BLAST_R * 2.0
const FINAL_DMG := BLAST_DMG * 2.0
const FINAL_FLASH := 26      # tics the light of it hangs about
const CRASH_R := 170.0       # and the second, which is the smaller bang
const CRASH_DMG := 55.0
const SCARE_R := 1400.0      # and how far away somebody stops shopping

const SHED_LAUNCH := 8       # pieces thrown as it leaves
const SHED_CRASH := 11       # and as it arrives
const CHUNK_LIFT := [3.5, 11.0]
const CHUNK_OUT := [1.2, 5.0]
const CHUNK_SPIN := 0.34
const CHUNK_BOUNCE := 0.32
const SMOULDER := 22 * U.TICRATE

const MAX_FLYING_CHUNKS := 64

var fleet                    # Vehicles
var def: VehicleModel
var x := 0.0
var y := 0.0
var ground := 0.0
var yaw := 0.0
var rx := 0.0                # roll about its length
var rz := 0.0                # pitch nose over tail
var light := 0.74
var sky := 1.0
var paint := Vector3.ONE
## HOW WELL IT TAKES A FIRE, in two numbers, both 1 for a car in the lot
## and both much larger for anything the police arrive in (see SwatVan):
## what fire's damage is divided by, and what the blackening is
## multiplied by once the health is gone. And separately against rounds.
var fire_armour := 1.0
var char_fuse := 1.0
var shot_armour := SHOT_ARMOUR
## HOW HIGH IT RIDES OFF THE TARMAC, zero for everything with wheels
var hover := 0.0

var state := "parked"
var health := HEALTH
var burning := 0
var burn_tick := 0
var char := 0.0
var char_tics := 0
var char_tick := 0
var flash := 0
var mid := Vector3()         # it turns about its middle, not its wheels
var cz := 0.0                # where that middle is
var vx := 0.0
var vy := 0.0
var vz := 0.0
var roll_rate := 0.0
var pitch_rate := 0.0
var yaw_rate := 0.0
var rx0 := 0.0
var rz0 := 0.0
var rx_to := 0.0
var rz_to := 0.0
var settle := 0
var smoulder := 0
var tick := 0
var corners: Array = []
## the three cylinders you cannot walk through (CARBODY actors)
var blockers: Array = []
## the drawing: the root node, its materials, the wheels, the cannon,
## the light bar — see VehicleModel.build
var node: Node3D
var mats: Array = []
var wheels: Array = []
var gun := {}
var lamp: MeshInstance3D = null
## the two columns of fire it carries while it is alight (the JS's BLAZE
## things, drawn here as licks off the body-fire pool — see _flames)
var flame_at: Array = []

## opts: x, y, z (the ground), angle, light, sky, paint (Vector3), state,
## fire_armour, char_fuse, shot_armour, hover
func _init(f, d: VehicleModel, opts: Dictionary) -> void:
	fleet = f
	def = d
	x = opts.x
	y = opts.y
	ground = opts.get("z", 0.0)
	yaw = opts.get("angle", 0.0)
	light = opts.get("light", 0.74)
	sky = opts.get("sky", 1.0)
	paint = opts.get("paint", Vector3.ONE)
	fire_armour = maxf(1.0, opts.get("fire_armour", 1.0))
	char_fuse = maxf(1.0, opts.get("char_fuse", 1.0))
	shot_armour = maxf(1.0, opts.get("shot_armour", SHOT_ARMOUR))
	hover = opts.get("hover", 0.0)
	state = opts.get("state", "parked")
	mid = Vector3(0, 0, d.height / 2.0)
	cz = riding_height()
	for p in d.corners():
		corners.append(d.to_mesh(p, mid))
	# out of step with every other van, off where it came on rather than
	# off the game's random table
	var phase := fposmod(x * 0.0131 + y * 0.0077, 1.0)
	var built := d.build(mid, phase)
	node = built.root
	mats = built.mats
	wheels = built.wheels
	gun = built.gun
	lamp = built.lamp
	fleet.add_child(node)
	relight()
	place()
	# and the part you cannot walk through, which for a hovering one is
	# the gap under it as well: you do not get to walk beneath an APC
	block(hover + d.car_height())

func game():
	return fleet.game

## Where the middle of it sits when it is standing or driving: on the
## tarmac, plus whatever it hovers.
func riding_height() -> float:
	return ground + hover + def.height / 2.0 * def.length

func body_z() -> float:
	return ground + hover

## The shader's view of it: the sector's light and sky, the char, the paint.
func relight(lit_mul := 1.0) -> void:
	for m in mats:
		m.set_shader_parameter("light", light * lit_mul)
		m.set_shader_parameter("sky", sky)
		m.set_shader_parameter("charred", char)
		m.set_shader_parameter("paint", paint)

## Doom's cylinders, three in a row. They carry a pointer back here,
## which is what makes a shot at any third of a van damage the van.
func block(h: float) -> void:
	unblock()
	var g = game()
	for b in def.blockers(x, y, yaw):
		var a: Actor = g.spawn("CARBODY", b.x, b.y, 0.0, {"radius": def.block_radius(), "height": maxf(16.0, roundf(h))})
		a.vehicle = self
		a.z = ground
		blockers.append(a)

func unblock() -> void:
	for a in blockers:
		a.remove()
	blockers.clear()

## Anybody standing where the cylinders just landed is put outside them,
## out of the SIDE of it, which is the short way and the way the door is.
func shove_clear() -> void:
	var g = game()
	var p = g.player
	if p == null or p.dead or blockers.is_empty():
		return
	var r: float = def.block_radius() + p.radius + 4.0
	var inside := false
	for b in blockers:
		if U.dist2(p.x, p.y, b.x, b.y) < r * r:
			inside = true
			break
	if not inside:
		return
	var c := cos(yaw)
	var s := sin(yaw)
	var dx: float = p.x - x
	var dy: float = p.y - y
	var lon := dx * c + dy * s
	var lat := dx * -s + dy * c
	var side := 1.0 if lat >= 0.0 else -1.0
	var tx := x + c * lon - s * side * r
	var ty := y + s * lon + c * side * r
	# through the level's own collision, so a van parked against a wall
	# does not put you into the wall instead
	var m: Vector3 = g.level.slide_move(p.x, p.y, tx - p.x, ty - p.y, p.radius, p.z, p.height, false)
	p.x = m.x
	p.y = m.y
	var sec: Level.Sector = g.level.sector_at(p.x, p.y, p.sector)
	if sec:
		p.sector = sec

# ------------------------------------------------------------------
# Being shot at, and catching
# ------------------------------------------------------------------

## Whether anything can still happen to it: standing, on the road, or
## already charring. In the air and afterwards it is past hurting.
func whole() -> bool:
	return state == "parked" or state == "driving" or state == "charring"

## What a blocker hands on. THE STREAM LIGHTS IT AND THAT IS ALL IT DOES,
## at the user's request; a blast still hurts (it carries `fire`).
func damage(n: float, _source = null, opts := {}) -> void:
	if not whole():
		return
	if opts.get("stream", false):
		ignite()
		return
	# THE ARMOUR IS AGAINST FIRE, AND SEPARATELY AGAINST ROUNDS
	if opts.get("fire", false):
		n /= fire_armour
	if opts.get("shot", false):
		n /= shot_armour
	# MORE DAMAGE TO ONE ALREADY CHARRING HURRIES IT: two tics off the fuse
	# a point, so a chain reaction across a row is a ripple
	if state == "charring":
		char_tics = maxi(1, int(char_tics - n * 2.0))
		return
	health -= n
	if health <= 0.0:
		start_char()

func ignite(tics := CATCH_TICS) -> void:
	if not whole():
		return
	# nothing in this world catches — see Actor.ignite
	if game().level.world.get("noBurn", false):
		return
	var first := burning <= 0
	burning = maxi(burning, tics)
	if first:
		catch_fire()

## The moment it is alight: the pool of fuel under it and the flames on it.
func catch_fire() -> void:
	var g = game()
	g.play_sound("ignite", self)
	if not flame_at.is_empty():
		return
	for t in [-0.22, 0.2]:
		flame_at.append(t)

## The two columns standing on it (BLAZE in the JS): a lick a tic off each.
func _flames() -> void:
	var fx = game().fx
	if fx == null or flame_at.is_empty():
		return
	var c := cos(yaw)
	var s := sin(yaw)
	var h: float = def.car_height()
	for t in flame_at:
		var fxp: float = x + c * t * def.length
		var fyp: float = y + s * t * def.length
		fx.body_flames.spawn({
			"x": fxp + (U.p_random() / 255.0 - 0.5) * 30.0, "y": fyp + (U.p_random() / 255.0 - 0.5) * 30.0,
			"z": body_z() + h * 0.7, "vx": 0.0, "vy": 0.0, "vz": 1.1,
			"life": 12 + (U.p_random() % 10), "size0": 30.0, "size1": 14.0,
			"c0": Color(1, 0.9, 0.6, 1), "c1": Color(1, 0.4, 0.1, 0.0),
			"frame": float(U.p_random() % fx.body_flames.frames), "frameRate": 0.6,
			"drag": 0.95, "gravity": 0.02,
		})

func burn_tic() -> void:
	burning -= 1
	if burning <= 0:
		burning = 0
		douse()
		return
	_flames()
	burn_tick += 1
	if burn_tick < BURN_EVERY:
		return
	burn_tick = 0
	var g = game()
	damage(BURN_DAMAGE, null, {"fire": true})

# ------------------------------------------------------------------
# CHARRING: between the tank being done for and the tank going. The
# coals come up through the paint and the light comes off it, and when
# it reaches the end it goes up on what it is.
# ------------------------------------------------------------------

func start_char() -> void:
	if state == "charring" or not whole():
		return
	state = "charring"
	char = 0.0
	char_tick = 0
	# AND IT TAKES `char_fuse` TIMES AS LONG on anything armoured
	char_tics = roundi(_between(CHAR_TICS) * char_fuse)
	if burning <= 0:
		burning = char_tics + 40
		catch_fire()
	game().play_sound("burn", self)

func char_tic() -> void:
	var g = game()
	char = minf(1.0, char + 1.0 / maxf(1.0, char_tics))
	var k := char
	char_tick += 1
	if char_tick % 3 == 0:
		relight()
	_flames()
	var h: float = def.car_height()
	if g.fx != null:
		g.fx.ember(x, y, cz + h * 0.3, 1 + int(k * 2.5), 0.5 + k)
		if char_tick % 3 == 1:
			g.fx.puff(x, y, cz + h * 0.5, 22.0 + 18.0 * k, 160)
	if char_tick % 24 == 0:
		g.play_sound("burn", self)
	if k >= 1.0:
		blow_up()

func douse() -> void:
	flame_at.clear()

## PUT OUT, by the fire brigade's water: not once it is charring — the
## tank has gone by then and nothing saves it.
func put_out() -> bool:
	if state == "charring" or burning <= 0:
		return false
	burning = 0
	douse()
	return true

# ------------------------------------------------------------------
# UP: the first bang, and then it leaves
# ------------------------------------------------------------------

func blow_up() -> void:
	if not whole():
		return
	var g = game()
	state = "air"
	burning = 0
	douse()
	lights_out()
	unblock()
	big_boom()
	g.scare(x, y, SCARE_R)
	vz = _between(LIFT)
	var ang := _rnd() * TAU
	vx = cos(ang) * _rnd() * DRIFT
	vy = sin(ang) * _rnd() * DRIFT
	var flight := 2.0 * vz / GRAVITY
	var over := (_rnd() - 0.5) * 2.0 * CANT          # it does not land square
	roll_rate = (PI + over) / flight
	pitch_rate = (_rnd() - 0.5) * 2.0 * PITCH_SPIN
	yaw_rate = (_rnd() - 0.5) * 2.0 * YAW_SPIN
	place()
	shed(SHED_LAUNCH)

## A bang where it stands; `scale` is how many of the old bang this is.
func boom(radius: float, dmg: float, blasts: int, scale := 1, sound := "explode") -> void:
	var g = game()
	# A CAR AGAINST A SHOPFRONT TAKES THE SHOPFRONT, and not much more: a
	# third of a region's integrity a bang, scaled with the bang
	# the vehicle itself is what goes off: it has an x and a y and stands
	# on the floor, which is where js/vehicles.js puts the bang
	g.explode(self, {"radius": radius, "damage": dmg,
		"heat": minf(255.0, 260.0 * scale), "heatRadius": 96.0 * sqrt(scale),
		"ignite": 340, "sound": sound, "structure": 0.34 * scale, "structureRadius": radius * 1.25})
	var L: float = def.length
	var W: float = def.width()
	# the fireballs, spread over the car's own footprint — and a big one
	# spreads them past it
	var n := (blasts + 2) * scale
	var wide := 0.7 + 0.25 * (scale - 1)
	var c := cos(yaw)
	var s := sin(yaw)
	if g.fx == null:
		return
	for k in n:
		var t := (_rnd() - 0.5) * wide * L
		var u := (_rnd() - 0.5) * (0.5 + 0.4 * (scale - 1)) * L
		# BLAST things in the JS; the fireball pool here
		g.fx.fireball(x + c * t - s * u, y + s * t + c * u, ground + 30.0, 110.0, 24)
	g.fx.ember(x, y, ground + 20.0, 26 * scale, 1.0)
	for k in 7 * scale:
		g.fx.puff(x + (_rnd() - 0.5) * W * scale, y + (_rnd() - 0.5) * W * scale, ground + 24.0 + (k % 7) * 6.0, 34.0, 200)

## THE BANG AT THE END OF THE CHAR — four of the old launch bang, and a
## FLASH: the fire light thrown at the car for the next second, decaying.
func big_boom() -> void:
	boom(FINAL_R, FINAL_DMG, 1, FINAL, "bigboom")
	flash = FINAL_FLASH

# ------------------------------------------------------------------
# Flying, and arriving
# ------------------------------------------------------------------

func tic() -> void:
	var g = game()
	if flash > 0:
		flash -= 1
	if state == "charring":
		char_tic()
		return
	if burning > 0:
		burn_tic()
	# AND IF THAT WAS THE TIC IT TIPPED OVER, stop here: it chars from the
	# next tic
	if state == "charring":
		return
	if state == "wreck":
		smoulder_tic()
		return
	if state == "parked" or state == "driving":
		return
	if state == "air":
		vz -= GRAVITY
		cz += vz
		x += vx
		y += vy
		rx += roll_rate
		rz += pitch_rate
		yaw += yaw_rate
		# it is on fire the whole way down
		if g.fx != null:
			g.fx.ember(x, y, cz, 2, 1.0)
			if (U.p_random() & 1) == 0:
				g.fx.puff(x, y, cz, 26.0, 150)
		var low := extent_of(corners, rx, rz).x
		if vz < 0.0 and cz + low <= ground:
			crash(low)
		else:
			place()
		return
	# settling: ease onto the roof, and let its own corners say how high
	# that leaves it. It rocks, because the height follows the angle.
	settle -= 1
	var k := 1.0 - float(settle) / SETTLE
	rx = rx0 + (rx_to - rx0) * k
	rz = rz0 + (rz_to - rz0) * k
	cz = ground - extent_of(corners, rx, rz).x
	place()
	if settle <= 0:
		rest()

## Lying there going out: smoke and sparks off it, and then only the coals.
func smoulder_tic() -> void:
	if smoulder <= 0:
		return
	smoulder -= 1
	var g = game()
	var k := float(smoulder) / (SMOULDER * 2)
	tick += 1
	if g.fx != null:
		if tick % 5 == 0:
			g.fx.ember(x, y, cz, 1, 0.4 + 0.6 * k)
		if tick % 11 == 0:
			g.fx.puff(x, y, cz + 10.0, 26.0 + 16.0 * k, 190)

## The light bar goes dark and stops flashing, for good.
func lights_out() -> void:
	if lamp != null:
		(lamp.material_override as ShaderMaterial).set_shader_parameter("dark", true)

## The wheels, turned through as far as it has just rolled.
func roll(step: float) -> void:
	for w in wheels:
		w.pivot.rotation.z -= step / w.radius

func place() -> void:
	node.position = U.v3(x, y, cz)
	node.rotation = Vector3(rx, yaw, rz)

## It has hit the tarmac: the second bang, and the pieces.
func crash(low: float) -> void:
	var g = game()
	state = "settle"
	hover = 0.0                   # whatever held it up has stopped
	update_sector()
	cz = ground - low
	g.play_sound("bodyfall", self)
	boom(CRASH_R, CRASH_DMG, 2)
	shed(SHED_CRASH)
	# onto its roof: half a turn, plus the crookedness it arrived with,
	# kept small enough that it still reads as upside down
	rx0 = rx
	rz0 = rz
	rx_to = roundf((rx - PI) / TAU) * TAU + PI + (_rnd() - 0.5) * 2.0 * ROLL_CANT
	rz_to = clampf(fmod(rz, TAU), -TILT, TILT)
	settle = SETTLE
	# burnt, from here on — and a burnt red van is still a red van
	char = WRECK_CHAR
	relight(WRECK_LIT)

func update_sector() -> void:
	var s: Level.Sector = game().level.sector_at(x, y)
	if s:
		ground = s.floor
		sky = s.sky if s.sky > 0.0 else (1.0 if s.outdoor else 0.0)
		light = s.light

## Done moving: it is in the way again — lower than it was, on its roof.
func rest() -> void:
	state = "wreck"
	block(cz + extent_of(corners, rx, rz).y - ground)
	shove_clear()
	smoulder = SMOULDER * 2
	tick = 0

## Pieces off the outside: one of the model's own triangles, and a box cut
## around its middle, so a piece off the tail IS the tail.
func shed(n: int) -> void:
	var L: float = def.length
	var ntri: int = def.tri_ink.size()
	if ntri == 0:
		return
	for k in n:
		if fleet.flying.size() >= MAX_FLYING_CHUNKS:
			return
		# THE LAST INDEX IS ONE PAST THE END once in every 256 pieces —
		# rnd() reaches 1.0 — so it is clamped
		var pick := mini(ntri - 1, int(_rnd() * ntri))
		var pc: Vector3 = (def.tri_pos[pick * 3] + def.tri_pos[pick * 3 + 1] + def.tri_pos[pick * 3 + 2]) / 3.0
		var w := 0.07 + _rnd() * 0.10
		var dp := 0.05 + _rnd() * 0.09
		var t := 0.04 + _rnd() * 0.07
		var lo := Vector3(pc.x - w / 2.0, pc.y - dp / 2.0, maxf(0.0, pc.z - t / 2.0))
		var hi := Vector3(pc.x + w / 2.0, pc.y + dp / 2.0, lo.z + t)
		# where that box is in the world right now, tumble and all
		var off := turn(def.to_mesh((lo + hi) / 2.0, mid), yaw, rx, rz)
		var wx := x + off.x
		var wy := y - off.z
		var wz := cz + off.y
		# thrown outward from the middle, and upward
		var a := atan2(wy - y, wx - x) + (_rnd() - 0.5) * 1.4
		var sp := _between(CHUNK_OUT)
		fleet.add_chunk(Vehicles.Chunk.new(fleet, def, lo, hi, {
			"x": wx, "y": wy, "z": wz, "ground": ground,
			"vx": cos(a) * sp + vx, "vy": sin(a) * sp + vy,
			"vz": _between(CHUNK_LIFT) + maxf(0.0, vz) * 0.4,
			"light": light, "sky": sky, "paint": paint,
		}))

# ------------------------------------------------------------------
# Turning things: Rz first, then Rx, then Ry — the YXZ product, written
# out, as js/vehicles.js does it
# ------------------------------------------------------------------

static func turn(p: Vector3, a_yaw: float, a_rx: float, a_rz: float) -> Vector3:
	var cz_ := cos(a_rz)
	var sz := sin(a_rz)
	var x1 := p.x * cz_ - p.y * sz
	var y1 := p.x * sz + p.y * cz_
	var z1 := p.z
	var cx := cos(a_rx)
	var sx := sin(a_rx)
	var y2 := y1 * cx - z1 * sx
	var z2 := y1 * sx + z1 * cx
	var cy := cos(a_yaw)
	var sy := sin(a_yaw)
	return Vector3(x1 * cy + z2 * sy, y2, -x1 * sy + z2 * cy)

## How far the lowest and highest corners of a turned box are from its
## middle (x lowest, y highest). Yaw is not in it.
static func extent_of(cs: Array, a_rx: float, a_rz: float) -> Vector2:
	var czz := cos(a_rz)
	var sz := sin(a_rz)
	var cx := cos(a_rx)
	var sx := sin(a_rx)
	var lo := INF
	var hi := -INF
	for p in cs:
		var yy: float = (p.x * sz + p.y * czz) * cx - p.z * sx
		lo = minf(lo, yy)
		hi = maxf(hi, yy)
	return Vector2(lo, hi)

static func _rnd() -> float:
	return U.p_random() / 255.0

static func _between(r: Array) -> float:
	return r[0] + _rnd() * (r[1] - r[0])
