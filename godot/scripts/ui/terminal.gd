## MEWD — the front door (js/terminal.js).
##
## THE GAME OPENS ON A TERMINAL, NOT THE GAME: black glass, white VT323
## type in a pale-ruled box with scanlines crawling down it, a prompt
## that reads INTERFACE 2037, and nothing else — no name, no word of
## what it wants: it is a password, and the only hint is the cursor.
## Every line is typed out a character at a time, the way the ship's
## computer in ALIEN talks, with a teletype tick under each character, a
## click under each key you press, a buzz when it refuses you, a chime
## when it lets you in, and a mains hum under all of it.
##
## The words: G or GAME opens the game (the title), JESSE goes straight
## to the PvP maze, JOIN [host[:port]] joins a match on the LAN, QUIT or
## EXIT leaves, E or EDIT opens MEWD Editor, the map editor
## (godot/scripts/editor/). Anything else is refused.
class_name Terminal
extends Control

signal open_game
signal open_jesse
## JOIN, or JOIN host[:port] — a match on the LAN (godot/scripts/net/):
## a Node host (tools/server.mjs) or a Godot one (--server), the same wire
signal open_join(where: String)
## E or EDIT: the map editor
signal open_editor

## the words to say once the prompt is up, before anything is typed (Main
## sets it: why a JOIN came back)
var after_boot: Array = []
## AND A GAME ON THE LAN (js/terminal.js JOIN_RE): `join` for this
## machine's own host, `join 192.168.1.20:7777` for another
const JOIN_RE := "^JOIN(?:\\s+((?:WSS?://)?[\\w.\\-]+(?::\\d+)?(?:/[\\w.\\-/]*)?))?$"

const PROMPT := "INTERFACE 2037 > "
const CHAR_S := 0.014
const JITTER_S := 0.022
const LINE_S := 0.110
const BLANK_S := 0.260
const MAX_LINES := 240

var font: FontFile
var size_px := 24
var lines: PackedStringArray = []
var entry := ""
var cursor_on := true
var busy := true
var done := false
var history: PackedStringArray = []
var hist := 0
var crt: ColorRect
var _t := 0.0
var _blink := false
var _players := {}
var _hum: AudioStreamPlayer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = load("res://assets/fonts/VT323-Regular.woff2")
	crt = ColorRect.new()
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://godot/shaders/crt.gdshader")
	crt.material = m
	add_child(crt)
	_bake_sounds()
	_boot()

# ------------------------------------------------------------------
# THE SOUNDS, made rather than recorded, as the web build's are
# ------------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	var b := PackedByteArray()
	b.resize(samples.size() * 2)
	for i in samples.size():
		b.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	w.data = b
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

## noise through a band round `hz`, falling away over `ms`
func _burst(hz: float, ms: float, vol: float) -> AudioStreamWAV:
	var n := int(22050 * ms / 1000.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var lo := 0.0
	var k := clampf(hz / 22050.0 * 6.0, 0.05, 0.95)
	for i in n:
		var x := randf() * 2.0 - 1.0
		lo += (x - lo) * k
		out[i] = (x - lo) * vol * exp(-6.0 * float(i) / n)
	return _wav(out)

func _tones(parts: Array) -> AudioStreamWAV:
	var total := 0.0
	for p in parts:
		total = maxf(total, p[2] + p[3] / 1000.0)
	var n := int(22050 * total)
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		var square: bool = p[0] == "square"
		var hz: float = p[1]
		var s0 := int(p[2] * 22050)
		var len := int(p[3] / 1000.0 * 22050)
		for i in len:
			var t := float(i) / 22050.0
			var ph := sin(TAU * hz * t)
			var v: float = (signf(ph) if square else ph) * float(p[4])
			var env := minf(1.0, t / 0.008) * minf(1.0, (len - i) / (0.03 * 22050.0))
			if s0 + i < n:
				out[s0 + i] += v * env
	return _wav(out)

func _bake_sounds() -> void:
	_players.tick = _burst(2700, 18, 0.12)
	_players.click = _burst(1400, 28, 0.2)
	_players.error = _tones([["square", 110.0, 0.0, 220.0, 0.09], ["square", 82.4, 0.26, 340.0, 0.09]])
	_players.grant = _tones([["sine", 659.0, 0.0, 140.0, 0.16], ["sine", 880.0, 0.16, 360.0, 0.16]])
	var hum := PackedFloat32Array()
	hum.resize(22050)
	for i in 22050:
		var t := float(i) / 22050.0
		hum[i] = (sin(TAU * 50.0 * t) + 0.35 * sin(TAU * 100.0 * t)) * 0.028
	_hum = AudioStreamPlayer.new()
	_hum.stream = _wav(hum, true)
	add_child(_hum)
	_hum.play()

func _sfx(name: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _players[name]
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# ------------------------------------------------------------------
# THE TALKING
# ------------------------------------------------------------------

func _line(t := "") -> void:
	lines.append(t)
	while lines.size() > MAX_LINES:
		lines.remove_at(0)
	queue_redraw()

func say(text: String) -> void:
	_line("")
	cursor_on = true
	if text == "":
		await get_tree().create_timer(BLANK_S).timeout
		return
	var s := ""
	for c in text:
		s += c
		lines[lines.size() - 1] = s
		queue_redraw()
		if c != " ":
			_sfx("tick")
		await get_tree().create_timer(CHAR_S + randf() * JITTER_S).timeout
	await get_tree().create_timer(LINE_S).timeout

func tell(ls: Array) -> void:
	for l in ls:
		await say(l)

func prompt() -> void:
	await say(PROMPT)
	busy = false
	entry = ""
	queue_redraw()

func _boot() -> void:
	await get_tree().create_timer(0.5).timeout
	if not after_boot.is_empty():
		_sfx("error")
		await tell(after_boot)
	await prompt()

func _enter() -> void:
	var raw := entry.strip_edges()
	var e := raw.to_upper()
	busy = true
	entry = ""
	lines[lines.size() - 1] = PROMPT + e
	if e == "":
		await prompt()
		return
	history.append(raw)
	hist = history.size()
	if e in ["G", "GAME"]:
		_sfx("grant")
		await tell(["MEWD DEMO", "LOADING"])
		await _close()
		open_game.emit()
		return
	if e == "JESSE":
		await tell(["JESSE", "GENERATING"])
		await _close()
		open_jesse.emit()
		return
	if e in ["QUIT", "EXIT"]:
		await tell(["GOODBYE"])
		get_tree().quit()
		return
	var jr := RegEx.create_from_string(JOIN_RE)
	var jm := jr.search(e)
	if jm != null:
		var where := raw.split(" ", false)[1] if raw.split(" ", false).size() > 1 else "127.0.0.1:%d" % NetProtocol.DEFAULT_PORT
		_sfx("grant")
		await tell(["JOINING", where.to_upper()])
		await _close()
		open_join.emit(where)
		return
	if e in ["E", "EDIT"]:
		# MEWD Editor (godot/scripts/editor/editor.gd)
		_sfx("grant")
		await tell(["MEWD EDITOR", "LOADING WORKSPACE"])
		await _close()
		open_editor.emit()
		return
	_sfx("error")
	await tell(["UNDEFINED COMMAND / SYNTAX ERROR", "ENTRY \"%s\" REFUSED" % e.substr(0, 48), ""])
	await prompt()

func _close() -> void:
	done = true
	cursor_on = false
	queue_redraw()
	var tw := create_tween()
	tw.tween_property(_hum, "volume_db", -60.0, 1.2)
	await get_tree().create_timer(0.7).timeout
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.8)
	await fade.finished

func _unhandled_input(event: InputEvent) -> void:
	if done or not (event is InputEventKey) or not event.pressed:
		return
	var k: int = event.keycode
	get_viewport().set_input_as_handled()
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		_sfx("click")
		if not busy:
			_enter()
		return
	if k == KEY_BACKSPACE:
		_sfx("click")
		entry = entry.substr(0, maxi(0, entry.length() - 1))
	elif k == KEY_UP or k == KEY_DOWN:
		if history.is_empty():
			return
		hist = clampi(hist + (-1 if k == KEY_UP else 1), 0, history.size())
		entry = history[hist] if hist < history.size() else ""
	elif event.unicode >= 32 and event.unicode < 127:
		_sfx("click")
		entry += char(event.unicode)
	if not busy:
		lines[lines.size() - 1] = PROMPT + entry.to_upper()
	queue_redraw()

func _process(dt: float) -> void:
	_t += dt
	(crt.material as ShaderMaterial).set_shader_parameter("time", _t)
	var b := fmod(_t, 1.1) < 0.55
	if b != _blink:
		_blink = b
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var fs := int(clampf(minf(size.x, size.y) * 0.022 + 10.0, 18.0, 32.0))
	var pad := Vector2(size.x * 0.04, size.y * 0.04)
	var box := Rect2(pad, size - pad * 2.0)
	draw_rect(box, Color("#16171a"))
	draw_rect(box, Color("#c9cac4"), false, 2.0)
	var lh := fs * 1.25
	var inner := box.grow_individual(-fs * 1.4, -fs * 1.1, -fs * 1.4, -fs * 1.1)
	var rows := int(inner.size.y / lh)
	var first := maxi(0, lines.size() - rows)
	var ink := Color("#f2f2ee")
	var y := inner.position.y + fs
	for i in range(first, lines.size()):
		var t := lines[i]
		# the glow: the same line, soft and wide, under it
		draw_string(font, Vector2(inner.position.x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.16))
		draw_string(font, Vector2(inner.position.x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		if i == lines.size() - 1 and cursor_on and not done and (busy or _blink):
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(inner.position.x + w + fs * 0.05, y - fs * 0.85, fs * 0.62 * 0.6, fs * 1.0), ink)
		y += lh
