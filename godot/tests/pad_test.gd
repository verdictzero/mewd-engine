## MEWD — the pad, headless: the bindings answer to ANY device (a
## handheld's built-in pad is not always device 0), the standard layout
## as a mapping the engine accepts, and the menus' reading of the pad
## (Pad.nav). `godot --headless --script res://godot/tests/pad_test.gd`
extends SceneTree

var fails := 0
var checks := 0

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: " + what)

func btn(b: int, dev: int, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = dev
	e.pressed = pressed
	return e

func axis(a: int, v: float, dev: int) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = dev
	return e

func _init() -> void:
	Pad.bind()
	Pad.bind()     # twice binds once
	ok(InputMap.action_get_events("use").size() == 1, "bind is once")
	# every device, not the first
	for dev in [0, 1, 3, 7]:
		ok(btn(JOY_BUTTON_A, dev).is_action_pressed("use"), "A uses on device %d" % dev)
		ok(btn(JOY_BUTTON_START, dev).is_action_pressed("pause"), "Start pauses on device %d" % dev)
		ok(btn(JOY_BUTTON_BACK, dev).is_action_pressed("pause"), "Select pauses on device %d" % dev)
		ok(btn(JOY_BUTTON_RIGHT_SHOULDER, dev).is_action_pressed("next_weapon"), "R1 next on device %d" % dev)
		ok(btn(JOY_BUTTON_LEFT_SHOULDER, dev).is_action_pressed("prev_weapon"), "L1 prev on device %d" % dev)
		ok(btn(JOY_BUTTON_DPAD_UP, dev).is_action_pressed("fwd"), "D-pad walks on device %d" % dev)
		ok(btn(JOY_BUTTON_B, dev).is_action_pressed("zoom"), "B zooms on device %d" % dev)
		ok(btn(JOY_BUTTON_X, dev).is_action_pressed("jump"), "X jumps on device %d" % dev)
		ok(btn(JOY_BUTTON_LEFT_STICK, dev).is_action_pressed("run"), "stick click runs on device %d" % dev)
		ok(axis(JOY_AXIS_TRIGGER_RIGHT, 0.9, dev).is_action_pressed("attack"), "R2 fires on device %d" % dev)
		ok(axis(JOY_AXIS_TRIGGER_LEFT, 0.9, dev).is_action_pressed("jump"), "L2 jumps on device %d" % dev)
		ok(axis(JOY_AXIS_LEFT_Y, -0.8, dev).is_action_pressed("fwd"), "left stick walks on device %d" % dev)
		ok(axis(JOY_AXIS_LEFT_X, 0.8, dev).is_action_pressed("right"), "left stick strafes on device %d" % dev)
	ok(not axis(JOY_AXIS_LEFT_Y, -0.1, 1).is_action_pressed("fwd"), "the dead zone")
	ok(not btn(JOY_BUTTON_A, 2, false).is_action_pressed("use"), "a release is not a press")
	# the standard layout is a mapping the engine takes
	Input.add_joy_mapping("03000000deadbeef0000cafe000000000,Test Pad," + Pad.STANDARD, true)
	ok(true, "standard mapping accepted")
	# the menus' reading
	ok(Pad.nav(btn(JOY_BUTTON_DPAD_DOWN, 1)) == "down", "nav: dpad down")
	ok(Pad.nav(btn(JOY_BUTTON_DPAD_DOWN, 1, false)) == "", "nav: a release says nothing")
	ok(Pad.nav(btn(JOY_BUTTON_A, 4)) == "ok", "nav: A is ok")
	ok(Pad.nav(btn(JOY_BUTTON_B, 4)) == "back", "nav: B is back")
	ok(Pad.nav(btn(JOY_BUTTON_START, 0)) == "start", "nav: start")
	ok(Pad.nav(btn(JOY_BUTTON_RIGHT_SHOULDER, 0)) == "next", "nav: R1 is next")
	ok(Pad.nav(axis(JOY_AXIS_LEFT_Y, -0.9, 2)) == "up", "nav: stick up")
	ok(Pad.nav(axis(JOY_AXIS_LEFT_Y, -1.0, 2)) == "", "nav: holding the stick is one step")
	ok(Pad.nav(axis(JOY_AXIS_LEFT_Y, 0.0, 2)) == "", "nav: the stick returning says nothing")
	ok(Pad.nav(axis(JOY_AXIS_LEFT_Y, -0.9, 2)) == "up", "nav: and again after")
	ok(Pad.nav(axis(JOY_AXIS_RIGHT_X, 0.7, 2)) == "right", "nav: right stick right")
	ok(Pad.nav(axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, 2)) == "", "nav: a trigger is not a direction")
	ok(Pad.nav(btn(JOY_BUTTON_Y, 0)) == "next", "nav: Y, a next-gun button, is next")
	ok(Pad.nav(btn(JOY_BUTTON_GUIDE, 0)) == "", "nav: Home is nothing")
	# who is in charge
	ok(Pad.is_pad(btn(JOY_BUTTON_A, 0)), "is_pad: a button")
	ok(Pad.is_pad(axis(JOY_AXIS_LEFT_X, 0.5, 0)), "is_pad: a push")
	ok(not Pad.is_pad(axis(JOY_AXIS_LEFT_X, 0.05, 0)), "is_pad: not the drift")
	ok(not Pad.is_pad(InputEventKey.new()), "is_pad: not a key")
	# the pause menu's cursor over the page
	var pm := PauseMenu.new()
	root.add_child(pm)
	await process_frame     # built (its _ready) before it is driven
	pm.pad_nav("down")
	ok(pm.cursor == 0, "pause: first move lands on the first tile")
	pm.pad_nav("right")
	ok(pm.cursor == 1, "pause: right")
	pm.pad_nav("down")
	ok(pm.cursor == 3, "pause: down off a three-tile page is the footer (RESUME)")
	pm.pad_nav("right")
	ok(pm.cursor == 4, "pause: QUIT")
	pm.pad_nav("up")
	ok(pm.cursor == 2, "pause: up from the footer is the last tile")
	var before = pm.prefs["music"]
	var got := []
	pm.resumed.connect(func(): got.append("resume"))
	pm.quit_to_title.connect(func(): got.append("quit"))
	pm.pad_nav("next")
	ok(pm.page == 2 and pm.cursor == 0, "pause: R1 turns the page")
	pm.pad_nav("prev")
	ok(pm.page == 1, "pause: L1 turns it back")
	pm.pad_nav("start")
	ok(got == ["resume"], "pause: Start resumes")
	pm.prefs["music"] = before
	pm.pad_nav("down")
	pm.pad_nav("down")
	pm.pad_nav("right")
	pm.pad_nav("right")
	var setups := []
	pm.pad_setup.connect(func(): setups.append(1))
	pm.pad_nav("ok")
	ok(setups.size() == 1, "pause: SET UP PAD in the footer opens the wizard")

	# ANDROID: the built-in pad is never given the browser's layout
	ok(not Pad.wants_standard(0) and not OS.has_feature("web"), "off the web, no pad is given the standard (browser) layout")
	ok(Pad.wants_raw() == OS.has_feature("android"), "on Android (only), every pad raw")
	# THE TRIGGERS, every way Android may send them
	for dev in [0, 2]:
		ok(btn(16, dev).is_action_pressed("attack") and btn(15, dev).is_action_pressed("jump"), "digital R2 / L2 (Godot's 16 / 15) fire and jump on device %d" % dev)
		ok(axis(6, 0.9, dev).is_action_pressed("attack") and axis(7, 0.9, dev).is_action_pressed("jump"), "GAS / BRAKE (axes 6 / 7) fire and jump on device %d" % dev)
	ok(not axis(6, 0.1, 0).is_action_pressed("attack"), "a trigger's dead zone")

	# A MAP SET UP BY HAND
	var kept = FileAccess.get_file_as_string(Pad.MAP_FILE) if FileAccess.file_exists(Pad.MAP_FILE) else null
	Pad.apply({"actions": {"attack": ["b7"], "use": ["b2"]}, "look": {"x": 3, "sx": -1.0, "y": 4, "sy": 1.0}})
	ok(btn(7, 0).is_action_pressed("attack") and not axis(JOY_AXIS_TRIGGER_RIGHT, 0.9, 0).is_action_pressed("attack"), "a map: fire on button 7, not R2")
	ok(btn(2, 3).is_action_pressed("use") and not btn(JOY_BUTTON_A, 3).is_action_pressed("use"), "a map: use on button 2 only")
	ok(btn(JOY_BUTTON_X, 0).is_action_pressed("jump"), "a map: what it does not name keeps the default")
	ok(btn(16, 0).is_action_pressed("attack"), "a map that names fire without R2's button still fires on it")
	Pad.apply({"actions": {"attack": ["b7"], "use": ["b16"]}})
	ok(not btn(16, 0).is_action_pressed("attack") and btn(16, 0).is_action_pressed("use"), "unless the map gave it to something else")
	Pad.apply({"actions": {"attack": ["b7"], "use": ["b2"]}, "look": {"x": 3, "sx": -1.0, "y": 4, "sy": 1.0}})
	ok(Pad.nav(btn(2, 0)) == "ok", "a map: the menus' OK follows USE")
	ok(Pad.nav(btn(7, 0)) == "", "a map: a button that fires is not a menu move")
	ok(Pad.look.x == 3 and Pad.look.sx == -1.0, "a map: the look stick")
	ok(Pad.nav(axis(3, -0.9, 5)) == "right", "a map: the look stick moves the menus its way round")
	ok(Pad.event_of("a4-") is InputEventJoypadMotion and Pad.event_of("a4-").axis_value < 0 and Pad.word_of(Pad.event_of("b12")) == "b12", "words and events, both ways")
	Pad.reset()
	ok(btn(JOY_BUTTON_A, 0).is_action_pressed("use") and Pad.look.x == JOY_AXIS_RIGHT_X, "reset: the defaults again")

	# THE WIZARD, driven
	var wz := PadWizard.new()
	root.add_child(wz)
	await process_frame
	var feed := func(e: InputEvent) -> void:
		wz._input(e)
		for i in 30:
			wz._process(0.05)
	feed.call(axis(JOY_AXIS_LEFT_Y, -0.9, 0))          # forward: the stick up, back derived
	feed.call(btn(JOY_BUTTON_DPAD_LEFT, 0))            # left: a button, so right is asked too
	feed.call(btn(JOY_BUTTON_DPAD_RIGHT, 0))
	feed.call(btn(JOY_BUTTON_A, 0))                    # the look wants a stick: refused
	ok(wz.steps[wz.at][0] == "look_y", "wizard: a button for the look is refused")
	feed.call(axis(JOY_AXIS_RIGHT_Y, 0.9, 0))          # this pad's up is +
	feed.call(axis(JOY_AXIS_RIGHT_X, 0.9, 0))
	feed.call(btn(7, 0))                               # fire on button 7 (L3 by default)
	wz.skip()                                          # jump: skipped
	for i in 30:
		wz._process(0.05)
	feed.call(btn(JOY_BUTTON_Y, 0))                    # use on Y
	while not wz._done:
		wz._left = 0.0
		wz._process(0.05)
		for i in 30:
			wz._process(0.05)
	ok(btn(7, 0).is_action_pressed("attack") and not btn(7, 0).is_action_pressed("run"), "wizard: fire on button 7, taken off RUN")
	ok(btn(JOY_BUTTON_Y, 0).is_action_pressed("use") and not btn(JOY_BUTTON_Y, 0).is_action_pressed("next_weapon"), "wizard: use on Y, taken off NEXT GUN")
	ok(axis(JOY_AXIS_LEFT_Y, 0.9, 0).is_action_pressed("back"), "wizard: the stick up, and down is back")
	ok(btn(JOY_BUTTON_DPAD_RIGHT, 0).is_action_pressed("right"), "wizard: a D-pad asks its other way too")
	ok(Pad.look.y == JOY_AXIS_RIGHT_Y and Pad.look.sy == -1.0, "wizard: this pad's look up, the right way round")
	ok(btn(JOY_BUTTON_X, 0).is_action_pressed("jump"), "wizard: a skipped step keeps what it had")
	ok(FileAccess.file_exists(Pad.MAP_FILE) and Pad.load_map().actions.attack == ["b7"], "wizard: saved")
	wz._close()
	if kept == null:
		Pad.reset()
	else:
		var f := FileAccess.open(Pad.MAP_FILE, FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	print("pad: %d checks, %d failed" % [checks, fails])
	print("OK" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)
