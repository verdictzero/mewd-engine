## MEWD — the player's body (js/player.js: turn, move).
##
## Doom's movement, per 35 Hz tic: a push along the facing, friction of
## 0.90625, a dead zone; the level's slide against its lines; the floor
## snapped to within a step (24) and anything deeper a fall on a unit of
## gravity a tic; a jump of 9; the eye lagging the feet so a kerb is a
## lurch and not a teleport; Doom's view bob, the square of the speed.
class_name Player
extends RefCounted

const GRAVITY := 1.0
const JUMP_VEL := 9.0
const FRICTION := 0.90625
const WALK_FWD := 25.0 / 32.0
const RUN_FWD := 50.0 / 32.0
const WALK_SIDE := 24.0 / 32.0
const RUN_SIDE := 40.0 / 32.0
const STOP_SPEED := 0.06
const MAX_PITCH := 0.72

const HEALTH := 100

var game
var x := 0.0
var y := 0.0
var z := 0.0
var angle := 0.0
var pitch := 0.0
var momx := 0.0
var momy := 0.0
var momz := 0.0
var on_ground := true
var radius := U.PLAYER_RADIUS
var height := U.PLAYER_HEIGHT
var view_z := 0.0
var bob := 0.0
var bob_phase := 0.0
var sector: Level.Sector = null
var health := HEALTH
var dead := false

## where the body was at the start of this tic, for the frame to draw
## between the two
var prev := Vector4()

func _init(g, sx: float, sy: float, a: float) -> void:
	game = g
	x = sx
	y = sy
	angle = a
	sector = g.level.sector_at(x, y)
	z = sector.floor if sector else 0.0
	view_z = z + U.PLAYER_EYE
	prev = Vector4(x, y, view_z, 0)

## One tic of a command: {fwd, side (-1..1), run, jump, look (Vector2, radians)}
func tic(cmd: Dictionary) -> void:
	prev = Vector4(x, y, view_z, 0)
	if dead:
		return
	turn(cmd.look)
	move(cmd)

func turn(look: Vector2) -> void:
	angle = U.angle_norm(angle - look.x)
	pitch = clampf(pitch - look.y, -MAX_PITCH, MAX_PITCH)

func move(cmd: Dictionary) -> void:
	var run: bool = cmd.run
	var fwd: float = (RUN_FWD if run else WALK_FWD) * cmd.fwd
	var side: float = (RUN_SIDE if run else WALK_SIDE) * cmd.side
	var c := cos(angle)
	var s := sin(angle)
	momx += c * fwd + s * side
	momy += s * fwd - c * side
	momx *= FRICTION
	momy *= FRICTION
	if absf(momx) < STOP_SPEED:
		momx = 0.0
	if absf(momy) < STOP_SPEED:
		momy = 0.0

	var lv: Level = game.level
	if momx != 0.0 or momy != 0.0:
		var r := lv.slide_move(x, y, momx, momy, radius, z, height, false)
		var blocked = game.thing_in_way(self, r.x, r.y)
		if blocked == null:
			x = r.x
			y = r.y
		else:
			momx *= 0.2
			momy *= 0.2

	var sec := lv.sector_at(x, y, sector)
	if sec:
		sector = sec
	var floor := sector.floor if sector else z
	var ceil := sector.ceil if sector else INF

	if on_ground and cmd.jump:
		momz = JUMP_VEL
		on_ground = false
	if on_ground and floor < z - U.MAX_STEP:
		on_ground = false
	if on_ground:
		z = floor
		momz = 0.0
	else:
		momz -= GRAVITY
		z += momz
		if z + height > ceil:
			z = maxf(floor, ceil - height)
			if momz > 0.0:
				momz = 0.0
		if z <= floor:
			var fall := -momz
			z = floor
			momz = 0.0
			on_ground = true
			if fall > 4.0:
				view_z -= minf(12.0, fall * 0.7)

	var speed2 := momx * momx + momy * momy
	var target_bob := minf(16.0, speed2 * 0.32)
	bob += (target_bob - bob) * 0.25
	if on_ground:
		bob_phase += 0.19
	var eye := z + U.PLAYER_EYE + sin(bob_phase) * bob * 0.5
	view_z += (eye - view_z) * 0.45
