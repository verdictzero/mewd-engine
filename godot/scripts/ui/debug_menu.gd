## MEWD — the DEBUG menu (at the user's request: "have a debug menu with
## a view logs button", in place of the title's last-failure notice).
##
## Opened from DEBUG on the title, DEBUG in the pause menu's footer, or
## the LOGS line at the foot of the title. What it shows:
##   - where the log is written, whether the phone gave the storage, and
##     what it did give (Logs)
##   - a VIEWER over the log, scrolled with a finger, the stick or the
##     D-pad: THIS RUN (mewd.log), LAST RUN (mewd-1.log), and LAST
##     FAILURE — what the black box held when the last run did not end
##     cleanly (BlackBox.last), which the title used to print at its foot
##   - COPY: what the viewer shows onto the clipboard, to paste anywhere
##     (no storage permission needed for that)
##   - ASK FOR STORAGE (Android): the ask again, every answer in the log
## B, Back or CLOSE shuts it.
class_name DebugMenu
extends Control

signal closed

## the most of a log shown (its tail), so a long run is not a stall
const TAIL := 48 * 1024
const VIEWS := [["THIS RUN", "log"], ["LAST RUN", "last"], ["LAST FAILURE", "failure"]]

var font: Font
var info: Label
var text: Label
var scroll: ScrollContainer
var view := "log"
var view_buttons := {}
var _copy: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono"]))
	var shade := ColorRect.new()
	shade.color = Color(4 / 255.0, 5 / 255.0, 9 / 255.0, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var h := Label.new()
	h.text = "D E B U G"
	h.add_theme_font_override("font", font)
	h.add_theme_font_size_override("font_size", 18)
	h.add_theme_color_override("font_color", Color("#e9e9ee"))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	var close := _button("CLOSE", true)
	close.pressed.connect(_close)
	head.add_child(close)
	info = Label.new()
	info.add_theme_font_override("font", font)
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.75, 0.8, 0.78))
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	col.add_child(info)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	col.add_child(row)
	for v in VIEWS:
		var b := _button("VIEW " + v[0] if v[1] == "log" else v[0])
		var key: String = v[1]
		b.pressed.connect(func(): show_view(key))
		row.add_child(b)
		view_buttons[key] = b
	_copy = _button("COPY")
	_copy.pressed.connect(copy)
	row.add_child(_copy)
	var top := _button("TOP")
	top.pressed.connect(func(): scroll.scroll_vertical = 0)
	row.add_child(top)
	var end := _button("END")
	end.pressed.connect(_to_end)
	row.add_child(end)
	if OS.get_name() == "Android":
		var ask := _button("ASK FOR STORAGE")
		ask.pressed.connect(func(): Logs.ask(); _refresh_info.call_deferred())
		row.add_child(ask)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.border_color = Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.3)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(box)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	text = Label.new()
	text.add_theme_font_override("font", font)
	text.add_theme_font_size_override("font_size", 11)
	text.add_theme_color_override("font_color", Color(0.86, 0.88, 0.86))
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(text)
	_refresh_info()
	show_view("log")

func _button(t: String, primary := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 38)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#c8321e") if primary else Color(1, 1, 1, 0.06)
	sb.border_color = Color("#e0442c") if primary else Color(207 / 255.0, 207 / 255.0, 214 / 255.0, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	var hov := sb.duplicate()
	hov.bg_color = Color("#d8432e") if primary else Color(1, 1, 1, 0.14)
	for st in ["normal", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["hover", "pressed"]:
		b.add_theme_stylebox_override(st, hov)
	return b

func _refresh_info() -> void:
	if info == null:
		return
	info.text = "\n".join(Logs.status())

## One of VIEWS into the viewer, scrolled to its end (the newest lines).
func show_view(key: String) -> void:
	view = key
	for k in view_buttons:
		view_buttons[k].modulate = Color(1, 1, 1, 1.0 if k == key else 0.55)
	var t := ""
	match key:
		"log":
			t = Logs.read(Logs.NAME, TAIL)
		"last":
			t = Logs.read("mewd-1.log", TAIL)
			if t == "":
				t = "(no log of a run before this one)"
		"failure":
			t = BlackBox.last
			if t == "":
				t = "(the last run ended cleanly: nothing to show)"
	if t == "":
		t = "(nothing written yet)"
	text.text = t
	_to_end.call_deferred()
	_refresh_info()

func _to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

## What the viewer shows, onto the clipboard.
func copy() -> void:
	DisplayServer.clipboard_set(text.text)
	_copy.text = "COPIED"
	get_tree().create_timer(1.5).timeout.connect(func(): if is_instance_valid(_copy): _copy.text = "COPY")

func _close() -> void:
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var step := 0
	match Pad.nav(event):
		"back", "start":
			_close()
		"up":
			step = -1
		"down":
			step = 1
		"prev", "left":
			show_view(VIEWS[(_view_index() - 1 + VIEWS.size()) % VIEWS.size()][1])
		"next", "right":
			show_view(VIEWS[(_view_index() + 1) % VIEWS.size()][1])
		_:
			if not (event is InputEventKey) or not event.pressed:
				return
			match event.physical_keycode:
				KEY_ESCAPE, KEY_BACKSPACE: _close()
				KEY_UP: step = -1
				KEY_DOWN: step = 1
				KEY_PAGEUP: step = -8
				KEY_PAGEDOWN: step = 8
				_: return
	if step != 0:
		scroll.scroll_vertical += step * 120
	get_viewport().set_input_as_handled()

func _view_index() -> int:
	for i in VIEWS.size():
		if VIEWS[i][1] == view:
			return i
	return 0
