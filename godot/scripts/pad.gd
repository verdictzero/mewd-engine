## MEWD — the pad (js/input.js: the gamepad half of it).
##
## ANY PAD, NOT THE FIRST ONE. A binding made in code is for device 0
## unless told otherwise, and the pad built into a handheld (an Anbernic
## RG557, say) is not always device 0 — a controller on its USB port, or
## the one the browser found first, may be — so every binding here is
## for ALL devices (-1), and the right stick is read off whichever pad
## is pushing it.
##
## ANDROID'S PAD IS ALREADY IN GODOT'S ORDER. Godot's Android code turns
## the system's key codes (BUTTON_A, DPAD_UP, ...) into its own button
## numbers itself, and gives a built-in pad no id, so the engine calls it
## "unknown". The standard layout used to be put on every unknown pad, in
## the BROWSER's button order, which scrambled an Anbernic RG557's
## buttons a second time (Select on L1, Start on L2, the D-pad on the
## sticks). It is now put only on a pad in a browser, where that order is
## what arrives.
##
## AND ON ANDROID, NO MAPPING AT ALL. Godot puts its "Default Android
## Gamepad" on a pad it does not know, and that layout has no L2 or R2
## BUTTONS (Godot's 15 and 16, KEYCODE_BUTTON_L2 / R2) and no axis past
## the sixth: an RG557's triggers were thrown away before the game, or
## the wizard, ever saw them. So each pad's mapping is taken off as it
## arrives, and everything comes through as Godot's Android code numbers
## it, which is the standard order already. Its axes are the device's
## own, sorted (X, Y, Z, RZ, LTRIGGER, RTRIGGER, GAS, BRAKE on most
## pads), so the triggers are bound on every axis and button they may
## arrive as: R2 on axis 5, axis 6 (GAS) and button 16; L2 on axis 4,
## axis 7 (BRAKE) and button 15.
##
## A PAD SET UP BY HAND (PadWizard, ui/pad_wizard.gd): what each action
## was given, button, axis and direction, or key, as it arrived, kept in
## user://pad_map.cfg and put over the defaults on every start.
##
## THE LAYOUT, the way every shooter lays it out (js/input.js sample):
## the LEFT stick or the D-pad walks, the RIGHT stick looks, R2 fires,
## L2 (or X) jumps, A uses, B steps the scope, the bumpers cycle the
## guns (and Y goes forward), a stick pressed in runs, Start or Select
## pauses. In the menus the D-pad or a stick moves, A takes, B goes
## back (Pad.nav), whatever they were set up as.
class_name Pad

## the standard layout, for a pad the engine does not know (SDL's
## words; the numbers are the Gamepad API's standard order, which the
## browsers use for an unrecognised pad) — in a browser only
const STANDARD := "a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,lefttrigger:b6,righttrigger:b7,back:b8,start:b9,leftstick:b10,rightstick:b11,dpup:b12,dpdown:b13,dpleft:b14,dpright:b15,leftx:a0,lefty:a1,rightx:a2,righty:a3"
const DEAD := 0.18
const MAP_FILE := "user://pad_map.cfg"
## the actions a pad plays, in the order the wizard asks for them
const ACTIONS := ["fwd", "back", "left", "right", "attack", "jump", "use", "zoom", "next_weapon", "prev_weapon", "run", "pause", "slow"]
## the defaults, as the wizard's own words: b = button, a = axis and
## its direction
const DEFAULTS := {
	"fwd": ["b11", "a1-"], "back": ["b12", "a1+"], "left": ["b13", "a0-"], "right": ["b14", "a0+"],
	"attack": ["a5+", "a6+", "b16"], "jump": ["b2", "a4+", "a7+", "b15"], "use": ["b0"], "zoom": ["b1"],
	"next_weapon": ["b10", "b3"], "prev_weapon": ["b9"], "run": ["b7"], "pause": ["b6", "b4"], "slow": ["b8"],
}
const LOOK_DEFAULT := {"x": 2, "sx": 1.0, "y": 3, "sy": 1.0}
## the triggers' other forms (see the top): a map saved before they came
## through, or that never named them, still fires and jumps on them —
## unless it gave them to something else
const TRIGGER_WORDS := [["attack", "b16"], ["attack", "a6+"], ["jump", "b15"], ["jump", "a7+"]]

## whether a pad is in charge — true from its first press or push until
## the next finger on the glass; the thumb controls are taken off the
## picture while it is (js/input.js padHeld)
static var held := false
## the stick that looks: its two axes, each with the way that is right
## and down
static var look := LOOK_DEFAULT.duplicate()
## the sticks' last nav direction per device, so a push is one step
static var _nav_prev := {}
static var _bound := false

## THE BINDINGS, on top of the keys: the defaults, then what was set up
## by hand. Once; Game._bind_keys and Main (Pad.watch) both ask.
static func bind() -> void:
	if _bound:
		return
	_bound = true
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_set_deadzone(action, DEAD)
	apply(load_map())

## The pad's events of an action gone (its keys and mouse stay).
static func clear_pad(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			InputMap.action_erase_event(action, e)

## A map ({"actions": {action: [words]}, "look": {...}}) onto the
## InputMap; an action it does not name keeps the default.
static func apply(m: Dictionary) -> void:
	var acts: Dictionary = m.get("actions", {})
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			InputMap.action_set_deadzone(action, DEAD)
		clear_pad(action)
		for w in acts.get(action, DEFAULTS[action]):
			var e := event_of(str(w))
			if e != null:
				InputMap.action_add_event(action, e)
	var used := {}
	for a in acts:
		for w in acts[a]:
			used[str(w)] = true
	for pair in TRIGGER_WORDS:
		if acts.has(pair[0]) and not used.has(pair[1]):
			InputMap.action_add_event(pair[0], event_of(pair[1]))
	look = LOOK_DEFAULT.duplicate()
	var lk = m.get("look")
	if lk is Dictionary:
		for k in look:
			if lk.has(k):
				look[k] = int(lk[k]) if k in ["x", "y"] else float(lk[k])

static func load_map() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(MAP_FILE) != OK:
		return {}
	return {"actions": cf.get_value("pad", "actions", {}), "look": cf.get_value("pad", "look", {}), "name": cf.get_value("pad", "name", "")}

static func save_map(m: Dictionary) -> void:
	var cf := ConfigFile.new()
	cf.set_value("pad", "actions", m.get("actions", {}))
	cf.set_value("pad", "look", m.get("look", LOOK_DEFAULT))
	cf.set_value("pad", "name", m.get("name", ""))
	cf.save(MAP_FILE)

## Back to the defaults, and the hand-made map forgotten.
static func reset() -> void:
	if FileAccess.file_exists(MAP_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MAP_FILE))
	apply({})

## "b3" (button 3), "a5+" / "a1-" (axis 5 pushed up / axis 1 pushed down),
## "k4194320" (a key, physically) — as an event for every device
static func event_of(w: String) -> InputEvent:
	if w.length() < 2:
		return null
	match w[0]:
		"b":
			var e := InputEventJoypadButton.new()
			e.device = -1
			e.button_index = int(w.substr(1)) as JoyButton
			return e
		"a":
			var e := InputEventJoypadMotion.new()
			e.device = -1
			e.axis = int(w.substr(1, w.length() - 2)) as JoyAxis
			e.axis_value = -1.0 if w.ends_with("-") else 1.0
			return e
		"k":
			var e := InputEventKey.new()
			e.physical_keycode = int(w.substr(1)) as Key
			return e
	return null

## and the other way: an event as it arrived, in those words
static func word_of(e: InputEvent) -> String:
	if e is InputEventJoypadButton:
		return "b%d" % e.button_index
	if e is InputEventJoypadMotion:
		return "a%d%s" % [e.axis, "-" if e.axis_value < 0 else "+"]
	if e is InputEventKey:
		return "k%d" % (e.physical_keycode if e.physical_keycode != 0 else e.keycode)
	return ""

## what a word is, for a person
static func say(w: String) -> String:
	if w == "":
		return "—"
	match w[0]:
		"b":
			var names := ["A", "B", "X", "Y", "SELECT", "HOME", "START", "L3", "R3", "L1", "R1", "D-PAD UP", "D-PAD DOWN", "D-PAD LEFT", "D-PAD RIGHT", "L2", "R2"]
			var i := int(w.substr(1))
			return "%s (button %d)" % [names[i], i] if i < names.size() else "BUTTON %d" % i
		"a":
			var i := int(w.substr(1, w.length() - 2))
			var names := ["LEFT STICK X", "LEFT STICK Y", "RIGHT STICK X", "RIGHT STICK Y", "L2", "R2", "R2 (GAS)", "L2 (BRAKE)"]
			return "%s %s (axis %d)" % [names[i] if i < names.size() else "AXIS %d" % i, "−" if w.ends_with("-") else "+", i]
		"k":
			return "KEY %s" % OS.get_keycode_string(int(w.substr(1)) as Key)
	return w

## Main calls this once: the bindings, and pads arriving told of
static func watch() -> void:
	bind()
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
	if wants_raw():
		# no mapping: Godot's own Android numbering, triggers and all
		Input.remove_joy_mapping(guid)
		print("pad %d: %s (%s) — raw, as Android numbers it" % [device, name, guid])
	elif wants_standard(device):
		Input.add_joy_mapping("%s,%s,%s" % [guid, name.replace(",", " ") if name != "" else "Pad", STANDARD], true)
		print("pad %d: %s (%s) — given the standard layout" % [device, name, guid])
	else:
		print("pad %d: %s (%s)" % [device, name, guid])

## on Android, every pad as it comes (see the top)
static func wants_raw() -> bool:
	return OS.has_feature("android")

## only in a browser, and only for a pad it has no layout for
static func wants_standard(device: int) -> bool:
	var guid := Input.get_joy_guid(device)
	return OS.has_feature("web") and not Input.is_joy_known(device) and guid != "" and guid != "0"

## the look stick, off whichever pad is pushing it hardest
static func right_stick() -> Vector2:
	var best := Vector2()
	for d in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(d, look.x) * look.sx, Input.get_joy_axis(d, look.y) * look.sy)
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

## the menus' words for the actions that move them
const NAV := [["fwd", "up"], ["back", "down"], ["left", "left"], ["right", "right"], ["use", "ok"], ["zoom", "back"],
	["pause", "start"], ["prev_weapon", "prev"], ["next_weapon", "next"]]

## THE MENUS' READING of a pad event: "up", "down", "left", "right",
## "ok", "back", "prev", "next" (the bumpers), "start", or "" for
## nothing (or the stick returning to the middle). Read off the actions,
## so a pad set up by hand moves the menus the way it plays.
static func nav(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		if not event.pressed:
			return ""
		for p in NAV:
			if InputMap.has_action(p[0]) and InputMap.event_is_action(event, p[0], true):
				return p[1]
		for a in ACTIONS:
			if InputMap.has_action(a) and InputMap.event_is_action(event, a, true):
				return ""     # it plays something else
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
		var v: float = event.axis_value
		var now := ""
		var known := false
		for p in NAV.slice(0, 4):
			for e in InputMap.action_get_events(p[0]) if InputMap.has_action(p[0]) else []:
				if e is InputEventJoypadMotion and e.axis == axis:
					known = true
					if v * signf(e.axis_value) >= 0.5:
						now = p[1]
		# the look stick moves the menus too
		if axis == look.x:
			known = true
			if absf(v) >= 0.5:
				now = "right" if v * look.sx > 0 else "left"
		elif axis == look.y:
			known = true
			if absf(v) >= 0.5:
				now = "down" if v * look.sy > 0 else "up"
		if not known:
			return ""
		var key := "%d:%d" % [event.device, axis]
		var was: String = _nav_prev.get(key, "")
		_nav_prev[key] = now
		if now == "" or now == was:
			return ""
		return now
	return ""
