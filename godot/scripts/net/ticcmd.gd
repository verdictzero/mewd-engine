## MEWD — the TicCmd: one tic of a player's hands, as data
## (js/net/ticcmd.js, line for line).
##
## Doom called it a ticcmd and so does this: everything a player does to
## the world in one tic, and nothing else — which way they turned, which
## way they pushed, and which buttons were down. The simulation is driven
## by these and only these, so it can be fed from the keyboard, from a
## socket on another machine, or from a recording, and cannot tell.
##
## A command here is the Dictionary Player.tic already reads, with the
## wire's two numbers on it:
##
##   tic            u32, the sender's count (a client numbers its own)
##   look           Vector2: yaw and pitch this tic, radians   (look.x, look.y)
##   side, fwd      strafe and forward, -1..1                  (move.x, move.y)
##   run, jump, use, attack
##   slot           1..7 pressed this tic, or 0                (weaponSlot)
##   cycle          -1, 0 or 1                                 (weaponCycle)
##   seen           the host's tic this client was DRAWING the others
##                  at when it sent this — see SimServer.rewind
##
## QUANTISED, the local player too: on the wire a command is seventeen
## bytes, the look in steps of 1/8192 of a radian and the move in 127ths,
## and a player fed the SAME rounded command a host is fed runs the same
## arithmetic to the last bit — which is what prediction stands on.
## The rounding is JavaScript's Math.round (half up), not GDScript's
## round (half away from zero), so the bytes are the web build's bytes.
class_name TicCmd

const LOOK_SCALE := 8192
const MOVE_SCALE := 127
const CMD_BYTES := 17      # tic u32, look 2×i16, move 2×i8, flags, slot, cycle, seen u32

const F_RUN := 1
const F_JUMP := 2
const F_USE := 4
const F_ATTACK := 8

## A neutral command: standing still, hands off.
static func new_cmd() -> Dictionary:
	return {"tic": 0, "look": Vector2(), "side": 0.0, "fwd": 0.0, "run": false, "jump": false, "use": false,
		"attack": false, "slot": 0, "cycle": 0, "seen": 0}

## Math.round, which rounds a half UP (-0.5 to 0), clamped to ±lim.
static func q(v: float, s: float, lim: int) -> int:
	if is_nan(v):
		v = 0.0
	return clampi(int(floor(v * s + 0.5)), -lim, lim)

static func _u32(v) -> int:
	return int(v) & 0xFFFFFFFF

static func _sign(v) -> int:
	var i := int(v)
	return 1 if i > 0 else (-1 if i < 0 else 0)

## Round a command to what the wire can carry, in place. The one place
## the rounding lives.
static func quantize(c: Dictionary) -> Dictionary:
	c["tic"] = _u32(c.get("tic", 0))
	var lk: Vector2 = c.get("look", Vector2())
	c["look"] = Vector2(q(lk.x, LOOK_SCALE, 32767) / float(LOOK_SCALE), q(lk.y, LOOK_SCALE, 32767) / float(LOOK_SCALE))
	c["side"] = q(float(c.get("side", 0.0)), MOVE_SCALE, 127) / float(MOVE_SCALE)
	c["fwd"] = q(float(c.get("fwd", 0.0)), MOVE_SCALE, 127) / float(MOVE_SCALE)
	for k in ["run", "jump", "use", "attack"]:
		c[k] = bool(c.get(k, false))
	c["slot"] = clampi(int(c.get("slot", 0)), 0, 255)
	c["cycle"] = _sign(c.get("cycle", 0))
	c["seen"] = _u32(c.get("seen", 0))
	return c

## A copy that owns its own everything (the look is a value already).
static func copy(c: Dictionary) -> Dictionary:
	return c.duplicate()

## Into CMD_BYTES bytes of `buf` at `offset`. Little-endian.
static func write(buf: PackedByteArray, offset: int, c: Dictionary) -> int:
	var lk: Vector2 = c.look
	buf.encode_u32(offset, _u32(c.tic))
	buf.encode_s16(offset + 4, q(lk.x, LOOK_SCALE, 32767))
	buf.encode_s16(offset + 6, q(lk.y, LOOK_SCALE, 32767))
	buf.encode_s8(offset + 8, q(float(c.side), MOVE_SCALE, 127))
	buf.encode_s8(offset + 9, q(float(c.fwd), MOVE_SCALE, 127))
	buf.encode_u8(offset + 10, (F_RUN if c.run else 0) | (F_JUMP if c.jump else 0) | (F_USE if c.use else 0) | (F_ATTACK if c.attack else 0))
	buf.encode_u8(offset + 11, clampi(int(c.slot), 0, 255))
	buf.encode_s8(offset + 12, _sign(c.cycle))
	buf.encode_u32(offset + 13, _u32(c.get("seen", 0)))
	return offset + CMD_BYTES

## And back out again.
static func read(buf: PackedByteArray, offset: int) -> Dictionary:
	var c := new_cmd()
	c.tic = buf.decode_u32(offset)
	c.look = Vector2(buf.decode_s16(offset + 4) / float(LOOK_SCALE), buf.decode_s16(offset + 6) / float(LOOK_SCALE))
	c.side = buf.decode_s8(offset + 8) / float(MOVE_SCALE)
	c.fwd = buf.decode_s8(offset + 9) / float(MOVE_SCALE)
	var f := buf.decode_u8(offset + 10)
	c.run = (f & F_RUN) != 0
	c.jump = (f & F_JUMP) != 0
	c.use = (f & F_USE) != 0
	c.attack = (f & F_ATTACK) != 0
	c.slot = buf.decode_u8(offset + 11)
	c.cycle = buf.decode_s8(offset + 12)
	c.seen = buf.decode_u32(offset + 13)
	return c

## Two commands the same, field for field.
static func same(a: Dictionary, b: Dictionary) -> bool:
	for k in ["tic", "look", "side", "fwd", "run", "jump", "use", "attack", "slot", "cycle", "seen"]:
		if a.get(k) != b.get(k):
			return false
	return true
