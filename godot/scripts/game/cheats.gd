## MEWD — THE CHEAT, at the user's request: "make the physical key code
## IDDQD or R1 + L1 + R2 + L2 + R3 + L3 together make the player
## invincible and have infinite ammo".
##
## A watcher fed every input event before anything else sees it
## (Main._input), that answers true on the event that completes either:
##   - the letters I D D Q D typed, by where the keys are on the board
##     (physical_keycode: the same five keys on an AZERTY), within a few
##     seconds of each other;
##   - all six of a pad's shoulder buttons, triggers and stick clicks held
##     at once — on whatever device, in whichever of the forms a pad
##     sends a trigger in (an axis past half way, or Android's buttons),
##     once per squeeze: let go and squeeze again to toggle back.
## Nothing here touches the game: Game.cheat_input does (toggle_god).
## A pure state machine, so the tests feed it events by hand.
class_name Cheats
extends RefCounted

const IDDQD := [KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D]
## the most time between one letter and the next
const TYPE_MS := 3000
## THE CHORD: each part, and the words for it (Pad's: "bN" a button,
## "aN+" an axis pushed); any one word of a part holds the part
const CHORD := {
	"L1": ["b9"], "R1": ["b10"],
	"L3": ["b7"], "R3": ["b8"],
	"L2": ["a4+", "a7+", "b15"],
	"R2": ["a5+", "a6+", "b16"],
}
## a trigger held past this, and let go under the other
const PULL := 0.5
const LET_GO := 0.35

var _typed: Array = []
var _typed_ms := 0
## device -> {word: true} held now
var _held := {}
## device -> the chord was whole and has not been let go since
var _whole := {}

func feed(e: InputEvent, now := -1) -> bool:
	if now < 0:
		now = Time.get_ticks_msec()
	if e is InputEventKey:
		if not e.pressed or e.echo:
			return false
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if now - _typed_ms > TYPE_MS:
			_typed.clear()
		_typed_ms = now
		_typed.append(k)
		while _typed.size() > IDDQD.size():
			_typed.pop_front()
		if _typed == IDDQD:
			_typed.clear()
			return true
		return false
	if not (e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return false
	var h: Dictionary = _held.get(e.device, {})
	_held[e.device] = h
	if e is InputEventJoypadButton:
		var w := "b%d" % e.button_index
		if e.pressed:
			h[w] = true
		else:
			h.erase(w)
	else:
		var w := "a%d+" % e.axis
		if e.axis_value >= PULL:
			h[w] = true
		elif e.axis_value < LET_GO:
			h.erase(w)
	var whole := held_parts(e.device) == CHORD.size()
	if whole and not _whole.get(e.device, false):
		_whole[e.device] = true
		return true
	if not whole:
		_whole[e.device] = false
	return false

## how many of the chord's six parts this device holds
func held_parts(device: int) -> int:
	var h: Dictionary = _held.get(device, {})
	var n := 0
	for part in CHORD:
		for w in CHORD[part]:
			if h.has(w):
				n += 1
				break
	return n

## A SQUEEZE UNDER WAY: both bumpers down on this device (nobody holds
## those two in play — the triggers are jump and fire, and are), so the
## stick clicks are part of the chord and not their own business: R3's
## slow motion and L3 + R3's frame-rate readout hold off
## (Game.handle_input, Main._unhandled_input)
func chording(device: int) -> bool:
	var h: Dictionary = _held.get(device, {})
	return h.has("b9") and h.has("b10")
