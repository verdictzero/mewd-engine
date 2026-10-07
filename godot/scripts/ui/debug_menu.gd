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
##
## THE LOOK is golf's house style (UiStyle, CutBox), at the user's request:
## greys only, the window and the rows cut at the corners, never rounded,
## and one cursor over the rows — the view being shown, or whatever row
## the mouse is over — white and bold and slid in. The view shown is
## named again over the viewer, so the cursor can wander without losing
## it. The log itself stays in a monospace face: a developer's readout
## (golf's "technical" role), where a traceback's columns have to line up.
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
## every row, in reading order, and the one under the cursor
var _rows: Array[Button] = []
var _cursor := 0
## the name of the view shown, over the viewer
var _view_name: Label

## how far the row under the cursor slides in, and the rows' type
const INDENT := 16.0
const ROW_SIZE := 16

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono"]))
	var shade := ColorRect.new()
	# (heavier than the pause's shade: the log has to read over anything)
	shade.color = Color(UiStyle.SHADE, 0.92)
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
	var h := UiStyle.header(UiStyle.spaced("debug"))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	var close := _button("CLOSE")
	close.pressed.connect(_close)
	head.add_child(close)
	info = UiStyle.label("", "name", 14)
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
	_copy = _button("COPY", "COPIED")
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
	var named := UiStyle.header("")
	_view_name = named.get_child(0) as Label
	col.add_child(named)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.window(Vector4(12, 10, 14, 10)))
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(box)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	text = Label.new()
	text.add_theme_font_override("font", font)
	text.add_theme_font_size_override("font_size", 11)
	text.add_theme_color_override("font_color", UiStyle.NAME)
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(text)
	_refresh_info()
	show_view("log")

## A row (golf has no buttons, only rows): dressed by `_mark`, the cursor
## brought to it by the mouse. Wide enough for its longest words in bold
## and slid in, so the cursor arriving moves the words and not the rows
## beside them. (CLOSE was a red "primary" once; a row that matters says
## so by being where the cursor is, never by a colour.) `longest`: other
## words the row will wear (COPY's COPIED).
func _button(t: String, longest := "") -> Button:
	var b := Button.new()
	b.text = t
	var bold := UiStyle.words("Bold")
	var widest := maxf(bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_SIZE).x,
		bold.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_SIZE).x)
	var frame := UiStyle.row(true)
	b.custom_minimum_size = Vector2(ceilf(widest + frame.content_margin_left + frame.content_margin_right + INDENT) + 4.0, 38)
	b.mouse_entered.connect(_hover.bind(_rows.size()))
	_rows.append(b)
	UiStyle.dress_row(b, false, false, ROW_SIZE)
	return b

## Every row dressed again: the one under the cursor white, bold, slid in.
func _mark() -> void:
	for i in _rows.size():
		var on := i == _cursor
		UiStyle.dress_row(_rows[i], on, false, ROW_SIZE, INDENT if on else 0.0)

func _hover(i: int) -> void:
	if i != _cursor:
		_cursor = i
		_mark()

func _refresh_info() -> void:
	if info == null:
		return
	info.text = "\n".join(Logs.status())

## One of VIEWS into the viewer, scrolled to its end (the newest lines).
func show_view(key: String) -> void:
	view = key
	_cursor = maxi(_rows.find(view_buttons[key]), 0)
	_mark()
	for v in VIEWS:
		if v[1] == key:
			_view_name.text = UiStyle.spaced(v[0])
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
