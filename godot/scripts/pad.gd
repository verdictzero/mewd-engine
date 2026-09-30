## MEWD — the pad (js/input.js: the gamepad half of it).
##
## ANY PAD, NOT THE FIRST ONE. A binding made in code is for device 0
## unless told otherwise, and the pad built into a handheld (an Anbernic
## RG557, say) is not always device 0 — a controller on its USB port, or
## the one the browser found first, may be — so every binding here is
## for ALL devices (-1), and the right stick is read off whichever pad
## is pushing it. A pad the engine has no mapping for is given the
## standard one on arrival (the Gamepad API's layout, which is what the
## browser and Android hand over for nearly everything), rather than
## left as bare button numbers that land on the wrong actions.
##
## THE LAYOUT, the way every shooter lays it out (js/input.js sample):
## the LEFT stick or the D-pad walks, the RIGHT stick looks, R2 fires,
## L2 (or X) jumps, A uses, B steps the scope, the bumpers cycle the
## guns (and Y goes forward), a stick pressed in runs, Start or Select
## pauses. In the menus the D-pad or a stick moves, A takes, B goes
## back (Pad.nav).
class_name Pad

## the standard layout, for a pad the engine does not know (SDL's
## words; the numbers are the Gamepad API's standard order, which
## Android and the browsers use for an unrecognised pad too)
const STANDARD := "a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,lefttrigger:b6,righttrigger:b7,back:b8,start:b9,leftstick:b10,rightstick:b11,dpup:b12,dpdown:b13,dpleft:b14,dpright:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3"
const DEAD := 0.18

## whether a pad is in charge — true from its first press or push until
## the next finger on the glass; the thumb controls are taken off the
## picture while it is (js/input.js padHeld)
static var held := false
## the sticks' last nav direction per device, so a push is one step
static var _nav_prev := {}
static var _bound := false

## THE BINDINGS, on top of the keys (Game._bind_keys calls this once)
static func bind() -> void:
	if _bound:
		return
	_bound = true
	var buttons := {
		"use": [JOY_BUTTON_A], "zoom": [JOY_BUTTON_B], "jump": [JOY_BUTTON_X],
		"next_weapon": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_Y], "prev_weapon": [JOY_BUTTON_LEFT_SHOULDER],
		"run": [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK],
		"pause": [JOY_BUTTON_START, JOY_BUTTON_BACK],
		"fwd": [JOY_BUTTON_DPAD_UP], "back": [JOY_BUTTON_DPAD_DOWN],
		"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT],
	}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in buttons[action]:
			var ev := InputEventJoypadButton.new()
			ev.device = -1
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	for pair in [["attack", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["jump", JOY_AXIS_TRIGGER_LEFT, 1.0],
			["fwd", JOY_AXIS_LEFT_Y, -1.0], ["back", JOY_AXIS_LEFT_Y, 1.0],
			["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var ev := InputEventJoypadMotion.new()
		ev.device = -1
		ev.axis = pair[1]
		ev.axis_value = pair[2]
		InputMap.action_add_event(pair[0], ev)
		InputMap.action_set_deadzone(pair[0], DEAD)

## Main calls this once: pads arriving get a mapping if they have none
static func watch() -> void:
	if not Input.joy_connection_changed.is_connected(on_connection):
		Input.joy_connection_changed.connect(on_connection)
	for d in Input.get_connected_joypads():
		on_connection(d, true)

static func on_connection(device: int, connected: bool) -> void:
	if not connected:
		_nav_prev.erase(device)
		return
	var guid := Input.get_joy_guid(device)
	var name := Input.get_joy_name(device)
	if not Input.is_joy_known(device) and guid != "" and guid != "0":
		Input.add_joy_mapping("%s,%s,%s" % [guid, name.replace(",", " ") if name != "" else "Pad", STANDARD], true)
		print("pad %d: %s (%s) — given the standard layout" % [device, name, guid])
	else:
		print("pad %d: %s (%s)" % [device, name, guid])

## the right stick, off whichever pad is pushing it hardest
static func right_stick() -> Vector2:
	var best := Vector2()
	for d in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if v.length() > best.length():
			best = v
	return best if best.length() >= DEAD else Vector2()

## whether an event is the pad's at all (for `held`)
static func is_pad(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return true
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) >= DEAD
	return false

## THE MENUS' READING of a pad event: "up", "down", "left", "right",
## "ok", "back", "prev", "next" (the bumpers), "start", or "" for
## nothing (or the stick returning to the middle)
static func nav(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		if not event.pressed:
			return ""
		match event.button_index:
			JOY_BUTTON_DPAD_UP: return "up"
			JOY_BUTTON_DPAD_DOWN: return "down"
			JOY_BUTTON_DPAD_LEFT: return "left"
			JOY_BUTTON_DPAD_RIGHT: return "right"
			JOY_BUTTON_A: return "ok"
			JOY_BUTTON_B: return "back"
			JOY_BUTTON_LEFT_SHOULDER: return "prev"
			JOY_BUTTON_RIGHT_SHOULDER: return "next"
			JOY_BUTTON_START, JOY_BUTTON_BACK: return "start"
		return ""
	if event is InputEventJoypadMotion:
		var axis: int = event.axis
		if axis > JOY_AXIS_RIGHT_Y:
			return ""
		var key := "%d:%d" % [event.device, axis]
		var was: int = _nav_prev.get(key, 0)
		var now := 0
		if event.axis_value <= -0.5:
			now = -1
		elif event.axis_value >= 0.5:
			now = 1
		_nav_prev[key] = now
		if now == 0 or now == was:
			return ""
		if axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_RIGHT_X:
			return "left" if now < 0 else "right"
		return "up" if now < 0 else "down"
	return ""
