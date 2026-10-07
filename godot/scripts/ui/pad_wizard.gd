## MEWD — SET UP THE PAD, at the user's request (an Anbernic RG557 whose
## buttons came out scrambled): a guided wizard that asks for each
## action in turn and keeps whatever the pad sends, as it arrives.
##
##   one step an action: "press FIRE", "push the left stick UP"
##   a button, a stick or trigger pushed past half way (from where it
##   rested when the step began, so a trigger resting at -1 still
##   counts), or a key — whatever arrives first is that action's
##   the stick that walks: UP and LEFT are asked, DOWN and RIGHT are the
##   same axis the other way; a D-pad button instead asks DOWN and RIGHT
##   too. The look stick wants a stick, not a button
##   nothing for 10 seconds, or SKIP: the action keeps what it had
##   between steps, everything let go first (no double takes)
##   the end: the list, saved (Pad.save_map, user://pad_map.cfg) and
##   played at once; ESC or CANCEL leaves the old map as it was
##
## Along the bottom, the last thing the pad sent, raw — a button's
## number, an axis and how far — to tell what a pad is doing at all.
##
## Dressed in golf's house style (UiStyle), at the user's request: greys
## only, a window cut at two corners, the readout in the numbers' face,
## and SKIP, DEFAULTS and CANCEL as rows under one cursor the mouse moves
## (every press of the pad and the keys is an answer here, never a move).
class_name PadWizard
extends Control

signal finished

const WAIT := 10.0
const PUSH := 0.6
## how far the row under the cursor slides in, and the rows' type
const INDENT := 16.0
const ROW_SIZE := 16
## where the saved list's second column starts
const COLUMN := 150.0

## [action, words, kind]: kind "any", "stick" (an axis, or a button and
## then its opposite asked too), "look_y", "look_x"
const STEPS := [
	["fwd", "MOVE FORWARD\npush the LEFT STICK UP\n(or D-pad up)", "stick"],
	["left", "MOVE LEFT\npush the LEFT STICK LEFT\n(or D-pad left)", "stick"],
	["look_y", "LOOK UP\npush the RIGHT STICK UP", "look_y"],
	["look_x", "LOOK RIGHT\npush the RIGHT STICK RIGHT", "look_x"],
	["attack", "FIRE\npress the button you shoot with (R2?)", "any"],
	["jump", "JUMP\n(L2?)", "any"],
	["use", "USE — DOORS, AND OK IN THE MENUS\n(A?)", "any"],
	["zoom", "SCOPE — AND BACK IN THE MENUS\n(B?)", "any"],
	["next_weapon", "NEXT GUN\n(R1?)", "any"],
	["prev_weapon", "PREVIOUS GUN\n(L1?)", "any"],
	["run", "RUN\n(a stick pressed in?)", "any"],
	["pause", "PAUSE\n(START?)", "any"],
	["slow", "SLOW MOTION\n(the right stick pressed in?)", "any"],
]
const OPPOSITE := {"fwd": ["back", "MOVE BACK\npush the D-pad DOWN"], "left": ["right", "MOVE RIGHT\npush the D-pad RIGHT"]}

var steps: Array = []
var at := 0
## what was given: action -> [words]
var got := {}
var look := {}
var font: Font
var title: Label
var ask: Label
var info: Label
var raw: Label
var bar: ProgressBar
var _left := WAIT
var _base := {}
## waiting for everything to be let go before the next step
var _settle := 0.0
var _done := false
var _close_in := -1.0
## SKIP, DEFAULTS, CANCEL, and the one under the cursor
var _rows: Array[Button] = []
var _cursor := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiStyle.theme()
	font = UiStyle.words()
	var shade := ColorRect.new()
	# (darker than the pause's shade: the wizard is all there is to look at)
	shade.color = Color(UiStyle.SHADE, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.window(Vector4(24, 20, 24, 20)))
	centre.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(560, 0)
	panel.add_child(col)
	var head := UiStyle.header(UiStyle.spaced("set up the pad"))
	title = head.get_child(0) as Label
	col.add_child(head)
	ask = _label("", 20, "name")
	ask.custom_minimum_size.y = 110
	col.add_child(ask)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = WAIT
	bar.custom_minimum_size.y = 6
	# (a thin bar, so the first weight of fill: UiStyle)
	bar.add_theme_stylebox_override("background", UiStyle.track())
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiStyle.HP
	bar.add_theme_stylebox_override("fill", fill)
	col.add_child(bar)
	info = _label("", 14, "tag")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(info)
	raw = UiStyle.number("the pad says: nothing yet", "name", 18)
	raw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(raw)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	for pair in [["SKIP", func(): skip()], ["DEFAULTS", func(): defaults()], ["CANCEL", func(): cancel()]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(140, 36)
		b.pressed.connect(pair[1])
		b.mouse_entered.connect(_hover.bind(_rows.size()))
		_rows.append(b)
		foot.add_child(b)
	_mark()
	start()

## A centred line in a role (UiStyle.ink): "name", "tag", ...
func _label(t: String, size: int, role: String) -> Label:
	var l := UiStyle.label(t, role, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## The rows dressed again: the one under the cursor white, bold, slid in
## (wide enough already that the slide moves no neighbour).
func _mark() -> void:
	for i in _rows.size():
		var on := i == _cursor
		UiStyle.dress_row(_rows[i], on, false, ROW_SIZE, INDENT if on else 0.0)

func _hover(i: int) -> void:
	if i != _cursor:
		_cursor = i
		_mark()

func start() -> void:
	steps = STEPS.duplicate()
	at = 0
	got = {}
	look = {}
	_done = false
	_close_in = -1.0
	_begin()

func _begin() -> void:
	_left = WAIT
	_base = {}
	for d in Input.get_connected_joypads():
		for a in 10:
			_base["%d:%d" % [d, a]] = Input.get_joy_axis(d, a)
	_show()

func _show() -> void:
	if _done:
		return
	var s: Array = steps[at]
	ask.text = s[1]
	var pads := []
	for d in Input.get_connected_joypads():
		pads.append("%s (%d)" % [Input.get_joy_name(d), d])
	info.text = "step %d of %d · %s\nnothing for %d seconds, or SKIP, keeps what it had · ESC cancels" % [
		at + 1, steps.size(), ("pads: " + ", ".join(pads)) if not pads.is_empty() else "no pad found — plug one in, or press a key", int(WAIT)]

func _process(dt: float) -> void:
	if _close_in >= 0.0:
		_close_in -= dt
		if _close_in < 0.0:
			_close()
		return
	if _done:
		return
	if _settle > 0.0:
		_settle -= dt
		if _settle <= 0.0 and _anything_held():
			_settle = 0.05
		elif _settle <= 0.0:
			_begin()
		bar.value = WAIT
		return
	_left -= dt
	bar.value = _left
	if _left <= 0.0:
		skip()

func _anything_held() -> bool:
	for d in Input.get_connected_joypads():
		for b in 22:
			if Input.is_joy_button_pressed(d, b as JoyButton):
				return true
		for a in 10:
			if absf(Input.get_joy_axis(d, a) - float(_base.get("%d:%d" % [d, a], 0.0))) > 0.35:
				return true
	return false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventKey:
		get_viewport().set_input_as_handled()
		_raw(event)
	else:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		cancel()
		return
	if _close_in >= 0.0:
		if (event is InputEventJoypadButton or event is InputEventKey) and event.pressed:
			_close()
		return
	if _done or _settle > 0.0:
		return
	var w := _take(event)
	if w != "":
		give(w)

func _raw(e: InputEvent) -> void:
	if e is InputEventJoypadButton:
		raw.text = "the pad says: button %d %s · device %d" % [e.button_index, "down" if e.pressed else "up", e.device]
	elif e is InputEventJoypadMotion:
		if absf(e.axis_value) < 0.2:
			return
		raw.text = "the pad says: axis %d at %+.2f · device %d" % [e.axis, e.axis_value, e.device]
	elif e is InputEventKey and e.pressed:
		raw.text = "the pad says: key %s (%d)" % [OS.get_keycode_string(e.physical_keycode if e.physical_keycode else e.keycode), e.physical_keycode if e.physical_keycode else e.keycode]

## the event as an answer to this step, or ""
func _take(e: InputEvent) -> String:
	if e is InputEventJoypadButton:
		return Pad.word_of(e) if e.pressed else ""
	if e is InputEventKey:
		return Pad.word_of(e) if e.pressed and not e.echo else ""
	if e is InputEventJoypadMotion:
		var d: float = e.axis_value - float(_base.get("%d:%d" % [e.device, e.axis], 0.0))
		if absf(d) < PUSH:
			return ""
		return "a%d%s" % [e.axis, "-" if d < 0 else "+"]
	return ""

## The answer to this step: kept, and on to the next.
func give(w: String) -> void:
	var s: Array = steps[at]
	var kind: String = s[2]
	if kind.begins_with("look"):
		if not w.begins_with("a"):
			raw.text += "  — the look wants a STICK"
			return
		var axis := int(w.substr(1, w.length() - 2))
		var sign := -1.0 if w.ends_with("-") else 1.0
		if kind == "look_y":
			look["y"] = axis
			look["sy"] = -sign      # pushed up is the way that is up
		else:
			look["x"] = axis
			look["sx"] = sign
	else:
		_assign(s[0], w)
		if kind == "stick":
			if w.begins_with("a"):
				var other: String = w.substr(0, w.length() - 1) + ("+" if w.ends_with("-") else "-")
				_assign(OPPOSITE[s[0]][0], other)
			else:
				steps.insert(at + 1, [OPPOSITE[s[0]][0], OPPOSITE[s[0]][1], "any"])
	_next()

## w for this action only: off any other it was on
func _assign(action: String, w: String) -> void:
	for a in got.keys():
		got[a].erase(w)
	got[action] = [w]

func skip() -> void:
	if _done:
		return
	_next()

func _next() -> void:
	at += 1
	if at >= steps.size():
		_finish()
		return
	_settle = 0.3
	_show()
	ask.text = "…"

## The map: what was given over what was there, saved and played.
func _finish() -> void:
	_done = true
	var old := Pad.load_map()
	var acts: Dictionary = old.get("actions", {}).duplicate(true)
	for a in Pad.ACTIONS:
		if not acts.has(a):
			acts[a] = Pad.DEFAULTS[a].duplicate()
	# what was given takes its input off whatever else had it
	for a in got:
		for w in got[a]:
			for b in acts:
				if b != a:
					acts[b].erase(w)
		acts[a] = got[a].duplicate()
	# the D-pad still walks, unless it was given to something else
	var taken := {}
	for a in got:
		for w in got[a]:
			taken[w] = true
	for pair in [["fwd", "b11"], ["back", "b12"], ["left", "b13"], ["right", "b14"]]:
		if got.has(pair[0]) and not taken.has(pair[1]) and not acts[pair[0]].has(pair[1]):
			acts[pair[0]].append(pair[1])
	var lk: Dictionary = old.get("look", {}).duplicate()
	for k in look:
		lk[k] = look[k]
	var pads := []
	for d in Input.get_connected_joypads():
		pads.append(Input.get_joy_name(d))
	var m := {"actions": acts, "look": lk, "name": ", ".join(pads)}
	Pad.save_map(m)
	Pad.apply(m)
	var lines := []
	for a in Pad.ACTIONS:
		var said := []
		for w in acts[a]:
			said.append(Pad.say(w))
		lines.append("%s\t%s" % [a.replace("_", " ").to_upper(), ", ".join(said)])
	var lx: Dictionary = Pad.look
	lines.append("%s\taxis %d, axis %d" % ["LOOK", lx.x, lx.y])
	ask.text = "SAVED"
	info.text = "\n".join(lines) + "\n\npress any button"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# (the words are not monospace, so the column is a tab stop, not spaces)
	info.tab_stops = PackedFloat32Array([COLUMN])
	bar.value = 0
	_close_in = 30.0

func defaults() -> void:
	Pad.reset()
	_done = true
	ask.text = "DEFAULTS"
	info.text = "the pad is back to the standard layout\n\npress any button"
	_close_in = 30.0

func cancel() -> void:
	_close()

func _close() -> void:
	if not is_inside_tree():
		return
	finished.emit()
	queue_free()
