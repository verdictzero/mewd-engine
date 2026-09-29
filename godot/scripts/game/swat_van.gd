## MEWD — one that drives: the police van (js/vehicles.js SwatVan).
##
## The first vehicle in the game with somewhere to go. An ordinary
## Vehicle in the ways that matter — three cylinders, its own node, the
## same box — with one state in front of `parked` that nothing else has:
## DRIVING, along a list of points the map hands out (the responders
## join level.swatRoutes to a stand), at a speed, with its three blockers
## carried along under it.
##
## AND IT BURNS, at the user's request, which it did not for a while: it
## is ARMOURED instead of fireproof, so the stream ends one in most of a
## minute where it ends a hatchback in nine seconds.
##
## AND IT IS A LITTLE BIT OF A CAR PHYSICS, at the user's request. The
## position rides the polyline exactly — no grip, no slip, no mass — but
## the SPEED along it is integrated: it builds up from a standing start
## and brakes for the END of the route on the oldest trick in the book,
## v = sqrt(2 a s), so it rolls the last two lengths into its place. And
## the body DIPS: a damped spring on the pitch, driven by the
## acceleration, and a second on the roll, driven by how hard it is
## turning. They are the acceleration read twice through a spring that
## overshoots, and they are the difference between a model sliding along
## a line and a van pulling up.
##
## AND IT DOES NOT STOP FOR ANYBODY: anything solid in front of it is hit
## hard enough to come apart, and the player is thrown.
class_name SwatVan
extends Vehicle

## AT THE USER'S REQUEST THEY SPEED IN, and then the user said slower:
## THIRTY-SIX, a top speed rather than a constant. What pays for the
## slowness is the distance — they come into being just out of sight
## (see `runIn` in Responders) — so what you see is a vehicle driving
## rather than a vehicle teleporting.
const DRIVE_SPEED := 36.0    # the fastest it will go, units a tic
const DRIVE_ACCEL := 0.75    # and how quickly it gets there
const DRIVE_BRAKE := 0.85    # and how hard it can stop, units a tic a tic
const DRIVE_TURN := 0.12     # radians a tic the heading may change
const RUNOVER_DMG := 220.0   # what the front of a van does to a person
const RUNOVER_PLAYER := 40.0 # and to you, once per hit: a hit throws you clear
const SIREN_EVERY := 19      # tics between the two notes

## THE BODY ON TWO SPRINGS. `pitch_per_g` turns acceleration into a
## target angle — negative when braking, nose down; `roll_per_g` leans it
## OUT of a bend. Both on the instance and both may be negative, which is
## what makes the hover carrier a different vehicle (see ArmyApc). At
## SPRING and DAMP it overshoots once and settles in about a second.
const PITCH_PER_G := 0.085
const ROLL_PER_G := 0.020
const PITCH_MAX := 0.11
const ROLL_MAX := 0.09
const SPRING := 0.075
const DAMP := 0.21
const ASLEEP := 1e-4

## a launched player cannot be thrown again by the same nose for this long
## (the JS keeps `launched` on the player; Player has no such field yet)
const LAUNCH_GRACE := 30

var route: Array = []
var tail: Array = []
var driven := 0.0
var speed := 0.0
var pitch_v := 0.0
var roll_v := 0.0
var siren_tick := 0
var siren_note := 0
var arrived_tic := -1
var notes := ["siren", "siren2"]
var note_every := SIREN_EVERY
var top_speed := DRIVE_SPEED
var accel := DRIVE_ACCEL
var brake := DRIVE_BRAKE
var pitch_per_g := PITCH_PER_G
var roll_per_g := ROLL_PER_G
var pitch_max := PITCH_MAX
var roll_max := ROLL_MAX
var runover_dmg := RUNOVER_DMG
var runover_player := RUNOVER_PLAYER
var park_angle = null
## the responders' bookkeeping: where it is going, which bay, which end
## of the road, whose it is, and its doors
var stand := {}
var bay = null
var side := ""
var force = null
var unload_at := -1
var unloaded := 0
var player_grace := 0

## `route`: points to drive through, in order ({x, y}; the last may carry
## `angle`, which it squares up to once it is there).
func _init(f, d: VehicleModel, r: Array, opts := {}) -> void:
	var start: Dictionary = r[0]
	var next: Dictionary = r[1] if r.size() > 1 else r[0]
	var sec: Level.Sector = f.game.level.sector_at(start.x, start.y)
	var o := {
		"x": start.x, "y": start.y, "z": sec.floor if sec else 0.0,
		"angle": atan2(next.y - start.y, next.x - start.x),
		"light": sec.light if sec else 0.74,
		"sky": (sec.sky if sec.sky > 0.0 else (1.0 if sec.outdoor else 0.0)) if sec else 1.0,
		"state": "driving",
		# IT BURNS, JUST SLOWLY: eight times the fire to get through it and
		# four times as long turning black
		"fire_armour": 8.0, "char_fuse": 4.0,
		# AND ROUNDS: fifty, a second and a half of the minigun on one van
		"shot_armour": 50.0,
	}
	o.merge(opts, true)
	super(f, d, o)
	route = r.slice(1)
	# HOW FAR IT STILL HAS TO GO FROM EACH POINT ON, worked out once, so
	# the braking aims at the END of the route rather than the next corner
	tail.resize(route.size())
	var acc := 0.0
	for i in range(route.size() - 1, -1, -1):
		tail[i] = acc
		if i > 0:
			acc += Vector2(route[i].x - route[i - 1].x, route[i].y - route[i - 1].y).length()

func tic() -> void:
	if state == "driving":
		drive()
		return
	super()
	# AND THE BODY GOES ON ROCKING after it has stopped: runs until the
	# spring is asleep and then never again
	if whole() and not asleep():
		suspension(0.0, 0.0)
		place()

func to_next() -> float:
	if route.is_empty():
		return 0.0
	var p: Dictionary = route[0]
	return Vector2(p.x - x, p.y - y).length()

func to_end() -> float:
	return to_next() + (float(tail[0]) if not tail.is_empty() else 0.0)

## THE BODY, off two numbers and two springs.
func suspension(a: float, t: float) -> void:
	var want_pitch := rest_pitch() + clampf(a * pitch_per_g, -pitch_max, pitch_max)
	var want_roll := rest_roll() + clampf(t * speed * roll_per_g, -roll_max, roll_max)
	pitch_v += (want_pitch - rz) * SPRING - pitch_v * DAMP
	roll_v += (want_roll - rx) * SPRING - roll_v * DAMP
	rz += pitch_v
	rx += roll_v

## WHERE THE BODY SITS WHEN NOTHING IS HAPPENING TO IT: level, on wheels.
func rest_pitch() -> float:
	return 0.0

func rest_roll() -> float:
	return 0.0

func asleep() -> bool:
	return absf(pitch_v) < ASLEEP and absf(roll_v) < ASLEEP and absf(rz - rest_pitch()) < ASLEEP and absf(rx - rest_roll()) < ASLEEP

func drive() -> void:
	var g = game()
	if player_grace > 0:
		player_grace -= 1
	if route.is_empty():
		park()
		return
	var p: Dictionary = route[0]
	# the heading, eased; the position, exact
	var want := atan2(p.y - y, p.x - x)
	var d := U.angle_norm(want - yaw)
	var t := clampf(d, -DRIVE_TURN, DRIVE_TURN)
	yaw = U.angle_norm(yaw + t)
	# THE SPEED, AND WHAT IT IS ALLOWED TO BE: its own top speed, or the
	# speed it could still stop from in the distance it has left; held at
	# a crawl below that, or the last unit takes a second and a half
	var was := speed
	var stopping := sqrt(2.0 * brake * maxf(0.0, to_end()))
	speed = minf(minf(top_speed, stopping), speed + accel)
	speed = maxf(speed, minf(1.2, to_end()))
	var left := to_next()
	var step := minf(speed, left)
	x += cos(want) * step
	y += sin(want) * step
	driven += step
	roll(step)
	if left - step < 0.5:
		route.pop_front()
		tail.pop_front()
	suspension(speed - was, t)
	if (g.tics & 3) == 0:
		update_sector()
		cz = riding_height()
		relight()
	place()
	carry_blockers()
	run_over()
	# the siren: two notes, alternating, for as long as it is moving
	siren_tick += 1
	if siren_tick >= note_every:
		siren_tick = 0
		g.play_sound(notes[siren_note], self)
		siren_note ^= 1
	# and it burns while it drives
	if burning > 0:
		burn_tic()

## The three cylinders, moved to under the van rather than remade.
func carry_blockers() -> void:
	var bl: Array = def.blockers(x, y, yaw)
	var g = game()
	for i in mini(blockers.size(), bl.size()):
		var a: Actor = blockers[i]
		a.x = bl[i].x
		a.y = bl[i].y
		a.z = ground
		g.blockmap.moved(a)

## Anybody in front of it: checked at the nose, against the crowd near it
## and against the player.
func run_over() -> void:
	var g = game()
	var c := cos(yaw)
	var s := sin(yaw)
	var L: float = def.length
	var r: float = def.block_radius()
	var nx := x + c * 0.42 * L
	var ny := y + s * 0.42 * L
	for a in g.blockmap.near(nx, ny):
		if a.removed or a.dead or not a.solid or a.vehicle != null or not a.shootable:
			continue
		var rr: float = r + a.radius
		if U.dist2(nx, ny, a.x, a.y) > rr * rr:
			continue
		a.damage(runover_dmg, null, {"impact": true, "dx": c, "dy": s, "force": 2.5})
	# AND YOU, at the user's request, are LAUNCHED rather than shoved: one
	# hit, hard, along the heading blended with the line from the nose to
	# you, and UP in proportion to how fast it was going
	var p = g.player
	if p != null and not p.dead and player_grace <= 0:
		var rr: float = r + p.radius
		if U.dist2(nx, ny, p.x, p.y) < rr * rr:
			var sp := maxf(0.0, speed)
			var ax: float = p.x - nx
			var ay: float = p.y - ny
			var ad := maxf(0.0001, Vector2(ax, ay).length())
			var lv := Vector2(c * 0.65 + (ax / ad) * 0.35, s * 0.65 + (ay / ad) * 0.35).normalized()
			var k := minf(30.0, 10.0 + sp * 0.55)
			var up := minf(17.0, 8.0 + sp * 0.25)
			var launch := {"x": lv.x * k, "y": lv.y * k, "z": up, "grace": LAUNCH_GRACE}
			p.damage(runover_player, self, {"impact": true, "launch": launch})
			# Player.damage does not spend `launch` yet (js/player.js does):
			# the velocity goes into the momentum here, up as well
			p.momx += launch.x
			p.momy += launch.y
			p.momz = maxf(p.momz, launch.z)
			p.on_ground = false
			player_grace = LAUNCH_GRACE

## It has arrived: squared up, in the way, and a van from here on.
func park() -> void:
	state = "parked"
	speed = 0.0
	if park_angle != null:
		yaw = park_angle
	# THE NOSE IS STILL DOWN when it gets here and is left that way on
	# purpose: the springs in tic() take it from here
	update_sector()
	cz = riding_height()
	relight()
	place()
	block(hover + def.car_height())
	shove_clear()
	arrived_tic = game().tics
	game().play_sound("doorclose", self)

## Where somebody steps out: the flank facing `toward`, a little along
## the length, clear of the blockers.
func door(k: int, toward: Vector2) -> Dictionary:
	var c := cos(yaw)
	var s := sin(yaw)
	var L: float = def.length
	var half_w: float = def.width() / 2.0
	# which side is nearer: the left (+y in model space, which is -s, c in
	# the world) or the right
	var lx := -s
	var ly := c
	var sd := 1.0 if (toward.x - x) * lx + (toward.y - y) * ly >= 0.0 else -1.0
	var out := half_w + 26.0
	var t: float = [0.0, -0.22, 0.22, -0.4, 0.4][k % 5] * L
	return {"x": x + c * t + lx * sd * out, "y": y + s * t + ly * sd * out, "angle": atan2(ly * sd, lx * sd)}
