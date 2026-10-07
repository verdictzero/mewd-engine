## MEWD — the phone's controls (js/touch.js, css/style.css #touch).
##
## A FLOATING STICK on the left 45% of the glass — it appears where the
## thumb lands and follows it if the thumb runs past its rim — and the
## rest of the glass is LOOK: drag to turn. On the right, a big FLAME
## button (hold to fire, and it still aims while held: drag it) with
## JUMP, USE and SWAP in an arc round it, AIM and ZOOM further out for
## the guns with something to put your eye to, and PAUSE in the corner.
## PERF, top left, turns the performance overlay on and off.
## LEFT-HANDED mirrors the lot. They dim after a while untouched.
##
## PORTRAIT is not played: a phone held upright gets a full-screen
## ROTATE DEVICE, at the user's request (RotateNotice).
##
## IN GOLF'S HOUSE STYLE, at the user's request (UiStyle): no hue, only
## greys — every button a dark glass with a READY edge, white (CURSOR)
## while a thumb is on it; FIRE told apart by a heavier edge and its
## name in bold, not by orange; the names in the house's words, TAG at
## rest, in a black outline over the moving world. The buttons and the
## stick stay round: they are for thumbs, and a thumb is round.
class_name TouchControls
extends Control

const MOVE_SHARE := 0.45
const LOOK_BASE := 0.007
const LOOK_Y_RATIO := 0.8
const IDLE_S := 2.5

## what the game reads each tic / frame
var move := Vector2()
var look := Vector2()
var attack := false
var use := false
var run := false
var jump_pulse := false
var cycle := 0
var aim_pulse := false
var zoom_pulse := false
var slow_pulse := false
var pause_pulse := false
## the PERF button: the performance overlay on and off (Main.toggle_perf)
var perf_pulse := false
var lefty := false
var sens := 1.0
var scope_on := false
var scope_up := false

var radius := 56.0
var pointers := {}
var stick_base := Vector2()
var stick_knob := Vector2()
var stick_on := false
var idle := 0.0
var font: Font
## the words in bold, for FIRE
var bold: Font

static func stick_vector(d: Vector2, r: float, dead := 0.12) -> Vector2:
	var len := d.length()
	var d0 := r * dead
	if len <= d0:
		return Vector2()
	var mag := minf(1.0, (len - d0) / (r - d0))
	return Vector2(d.x / len * mag, -d.y / len * mag)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the menus still want the taps as clicks; the game ignores those
	# while the glass is up (Game.handle_input)
	font = UiStyle.words("Medium")
	bold = UiStyle.words("Bold")

## the buttons, where the web build's stylesheet puts them
func _buttons() -> Dictionary:
	var btn := clampf(minf(size.x, size.y) * 0.18, 64.0, 84.0)
	var small := btn * 0.72
	var edge := Vector2(size.x * 0.04 + 12.0, 14.0)
	var arc := btn * 0.5 + small * 0.5 + 12.0
	var outer := arc * 1.7
	var fc := Vector2(size.x - edge.x - btn * 0.5, size.y - edge.y - btn * 0.5)
	var sx := -1.0
	if lefty:
		fc.x = edge.x + btn * 0.5
		sx = 1.0
	var out := {
		"fire": [fc, btn * 0.5, "FIRE"],
		"jump": [fc + Vector2(sx * arc, 0), small * 0.5, "JUMP"],
		"use": [fc + Vector2(sx * arc * 0.7071, -arc * 0.7071), small * 0.5, "USE"],
		"swap": [fc + Vector2(0, -arc), small * 0.5, "SWAP"],
		"pause": [Vector2(size.x - 30.0 if not lefty else 30.0, 76.0), 22.0, "II"],
		"slow": [Vector2(size.x - 30.0 if not lefty else 30.0, 130.0), 22.0, "SLO"],
		# its own, in the top left corner, whichever hand (at the user's request)
		"perf": [Vector2(24.0, 22.0), 18.0, "PERF"],
	}
	if scope_on:
		out["aim"] = [fc + Vector2(sx * outer * 0.9239, -outer * 0.3827), small * 0.5, "AIM"]
		if scope_up:
			out["zoom"] = [fc + Vector2(sx * outer * 0.3827, -outer * 0.9239), small * 0.5, "ZOOM"]
	return out

func _hit(p: Vector2) -> String:
	var bs := _buttons()
	for k in bs:
		if p.distance_to(bs[k][0]) <= bs[k][1]:
			return k
	return ""

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		idle = 0.0
		if event.pressed:
			_down(event.index, event.position)
		else:
			_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		idle = 0.0
		_drag(event.index, event.position)
		get_viewport().set_input_as_handled()

func _down(id: int, p: Vector2) -> void:
	radius = clampf(roundf(minf(size.x, size.y) * 0.14), 44.0, 64.0)
	var b := _hit(p)
	if b != "":
		pointers[id] = {"kind": b, "last": p}
		match b:
			"fire": attack = true
			"use": use = true
			"jump": jump_pulse = true
			"swap": cycle = 1
			"aim": aim_pulse = true
			"zoom": zoom_pulse = true
			"slow": slow_pulse = true
			"perf": perf_pulse = true
		return
	var move_side := p.x > size.x * (1.0 - MOVE_SHARE) if lefty else p.x < size.x * MOVE_SHARE
	var has_move := pointers.values().any(func(q): return q.kind == "move")
	if move_side and not has_move:
		pointers[id] = {"kind": "move"}
		stick_base = p
		stick_knob = p
		stick_on = true
	else:
		pointers[id] = {"kind": "look", "last": p}
	queue_redraw()

func _drag(id: int, p: Vector2) -> void:
	if not pointers.has(id):
		return
	var q: Dictionary = pointers[id]
	if q.kind == "move":
		# the base follows a thumb that runs past the rim
		var d := p - stick_base
		if d.length() > radius:
			stick_base += d * ((d.length() - radius) / d.length())
		var v := stick_vector(p - stick_base, radius)
		move = v
		run = v.length() > 0.0
		stick_knob = p
	elif q.kind == "look" or q.kind == "fire":
		var d: Vector2 = p - q.last
		look += Vector2(d.x * LOOK_BASE * sens, d.y * LOOK_BASE * sens * LOOK_Y_RATIO)
		q.last = p
	queue_redraw()

func _up(id: int) -> void:
	if not pointers.has(id):
		return
	var q: Dictionary = pointers[id]
	pointers.erase(id)
	match q.kind:
		"move":
			move = Vector2()
			run = false
			stick_on = false
		"fire": attack = false
		"use": use = false
		"pause": pause_pulse = true
	queue_redraw()

## what has piled up since the last frame, taken
func take_look() -> Vector2:
	var l := look
	look = Vector2()
	return l

func _process(dt: float) -> void:
	idle += dt
	queue_redraw()

func _draw() -> void:
	var dim := 0.35 if idle > IDLE_S else 1.0
	var bs := _buttons()
	for k in bs:
		var c: Vector2 = bs[k][0]
		var r: float = bs[k][1]
		var held: bool = pointers.values().any(func(q): return q.kind == k)
		var fire: bool = k == "fire"
		# the glass, and over it while held the cursor's white breath
		var fill := Color(UiStyle.CURSOR, 0.26) if held else Color(UiStyle.PANEL_BG, 0.45 if fire else 0.32)
		var edge := Color(UiStyle.CURSOR) if held else Color(UiStyle.READY, 0.6 if fire else 0.42)
		# (AIM and ZOOM, the scope's, a step quieter than the rest)
		if k in ["aim", "zoom"] and not held:
			edge = Color(UiStyle.TAG, 0.5)
		fill.a *= dim
		edge.a *= dim
		draw_circle(c, r * (0.94 if held else 1.0), fill)
		draw_arc(c, r * (0.94 if held else 1.0), 0, TAU, 48, edge, 2.5 if fire else 1.5, true)
		var fs := 15 if fire else (10 if k == "perf" else 12)
		var f: Font = bold if fire else font
		var t: String = bs[k][2]
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := c + Vector2(-w / 2.0, fs * 0.35)
		var ink := Color(UiStyle.CURSOR if held else (UiStyle.NAME if fire else UiStyle.TAG), dim)
		draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color(0, 0, 0, 0.8 * dim))
		draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	if stick_on:
		draw_circle(stick_base, radius, Color(UiStyle.PANEL_BG, 0.25))
		draw_arc(stick_base, radius, 0, TAU, 48, Color(UiStyle.READY, 0.42), 1.5, true)
		var k := stick_knob - stick_base
		if k.length() > radius:
			k = k.normalized() * radius
		var running := run and move.length() > 0.85
		draw_circle(stick_base + k, radius * 0.42, Color(UiStyle.CURSOR, 0.45) if running else Color(UiStyle.READY, 0.3))
