## MEWD — and one that does not touch the road: the army's APC
## (js/vehicles.js ArmyApc).
##
## A SwatVan in every way that is about GETTING somewhere — the same
## polyline, the same eased heading, the same nose, the same doors —
## and different in everything about what it IS.
##
## IT FLOATS, AND IT NEVER HOLDS STILL. `hover` holds the whole vehicle
## off the tarmac and the BOB breathes it up and down: two sines, on
## periods that do not divide into one another (a four-second breath
## with a ten-second swell under it), because one sine is a metronome
## and two is a thing being held up by something not quite managing it.
## BIGGER WHEN IT IS PARKED, because a hovercraft at speed is held
## steadier by the ground under it, and what the user asked for was the
## bob you see when it has stopped.
##
## AND IT IS NEVER LEVEL: two more slow sines put a degree or so of pitch
## and a degree and a half of roll into it (rest_pitch, rest_roll), so
## its springs are never asleep.
##
## AND IT BANKS INTO ITS TURNS, AND PITCHES UP TO STOP: the van's two
## lines of suspension with both signs turned over, because a thing on
## THRUST points its lift into the bend and forward to stop. The angles
## are capped where the ground says: it leans as far as it can without
## putting a corner through the tarmac.
##
## AND IT BLOWS THE CAR PARK ABOUT: a puff under the middle of it every
## few tics — hard and low while it is moving, an idle while it stands.
##
## AND IT WEIGHS MORE, and it has no siren: two notes still, but they are
## the turbine.
class_name ArmyApc
extends SwatVan

const HOVER := 34.0                   # how high the skirts ride, in game units
const BOB := 7.0                      # and how far it breathes, either way, parked
const BOB_DRIVING := 0.45             # and how much of that while it is moving
const BOB_RATE := TAU / 140.0         # one whole breath in four seconds
const SWELL_RATE := BOB_RATE * 0.41   # and the slow one under it, in ten
const SWELL := 0.30                   # which is this much of the whole
const IDLE_PITCH := 0.019
const IDLE_PITCH_RATE := TAU / 191.0
const IDLE_ROLL := 0.027
const IDLE_ROLL_RATE := TAU / 233.0
const HOVER_PITCH_PER_G := -0.100
const HOVER_ROLL_PER_G := -0.055
const HOVER_PITCH_MAX := 0.12         # seven degrees: the nose drops fifteen units
const HOVER_ROLL_MAX := 0.17          # ten: the low flank drops eleven
const WASH_MOVING := 3                # tics between downwash puffs, driving
const WASH_STANDING := 13             # and standing
const APC_RUNOVER := 440.0
const APC_RUNOVER_PLAYER := 42.0
const TURBINE_EVERY := 26

var bob_t := 0.0

func _init(f, d: VehicleModel, r: Array, opts := {}) -> void:
	super(f, d, r, opts)
	notes = ["hover", "hover2"]
	note_every = TURBINE_EVERY
	runover_dmg = APC_RUNOVER
	runover_player = APC_RUNOVER_PLAYER
	bob_t = U.p_random()              # no two of them breathe together
	hover = HOVER
	# ARMOUR, AND MORE OF IT THAN THE VAN: fourteen times the fire and six
	# times as long going black; ninety against rounds
	fire_armour = 14.0
	char_fuse = 6.0
	shot_armour = 90.0
	# AND IT IS HEAVIER TO DRIVE
	top_speed = SwatVan.DRIVE_SPEED * 0.82
	accel = SwatVan.DRIVE_ACCEL * 0.62
	brake = SwatVan.DRIVE_BRAKE * 0.70
	# AND THE BODY ANSWERS THEM THE OTHER WAY ROUND
	pitch_per_g = HOVER_PITCH_PER_G
	roll_per_g = HOVER_ROLL_PER_G
	pitch_max = HOVER_PITCH_MAX
	roll_max = HOVER_ROLL_MAX
	cz = riding_height()
	# it was built standing on the tarmac; stand it up and make the thing
	# you cannot walk through as tall as it now is
	place()
	block(hover + def.car_height())

## THE BREATH: two sines on periods that do not divide into one another.
func bob() -> float:
	var t := bob_t
	var k := sin(t * BOB_RATE) * (1.0 - SWELL) + sin(t * SWELL_RATE + 2.3) * SWELL
	return k * BOB * (BOB_DRIVING if state == "driving" else 1.0)

func rest_pitch() -> float:
	return sin(bob_t * IDLE_PITCH_RATE) * IDLE_PITCH

func rest_roll() -> float:
	return sin(bob_t * IDLE_ROLL_RATE + 1.7) * IDLE_ROLL

## never asleep: what it is settling onto keeps moving
func asleep() -> bool:
	return false

func tic() -> void:
	# the breath first, so whatever super does with cz it does at the
	# height this tic is actually at
	if whole():
		bob_t += 1.0
		hover = HOVER + bob()
	super()
	if not whole():
		return
	# super recomputes cz on its own clock, which is not enough for one
	# that is never still, so it is set here, every tic
	cz = riding_height()
	place()
	wash()

## The grit under it: low and wide where the skirts are.
func wash() -> void:
	var g = game()
	var every := WASH_MOVING if state == "driving" else WASH_STANDING
	if (g.tics + int(bob_t)) % every:
		return
	var c := cos(yaw)
	var s := sin(yaw)
	var L: float = def.length
	var W: float = def.width()
	var t := (_rnd() - 0.5) * 0.7 * L
	var u := (_rnd() - 0.5) * W
	if g.fx != null:
		g.fx.puff(x + c * t - s * u, y + s * t + c * u, ground + 6.0, 30.0, 120)
