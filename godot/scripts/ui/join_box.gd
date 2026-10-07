## MEWD — JOIN GAME (the title's MULTIPLAYER page): where the host is,
## typed (the last one kept, user://join.cfg), then JOIN or BACK. Enter
## joins, Escape goes back; on a phone the field brings up the keyboard.
##
## In golf's house style (UiStyle), at the user's request: a grey window
## cut at two corners on a shaded title, the field in its plate, and JOIN
## and BACK as rows under one cursor that the mouse moves — JOIN is not a
## red button any more, only the row the cursor starts on.
class_name JoinBox
extends Control

signal join(where: String)
signal back

const SAVE := "user://join.cfg"
## how far the row under the cursor slides in
const INDENT := 16.0

var field: LineEdit
## JOIN and BACK, and the one of them under the cursor
var _rows: Array[Button] = []
var _cursor := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	var dim := ColorRect.new()
	dim.color = UiStyle.SHADE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.window(Vector4(22, 18, 22, 18)))
	var mid := CenterContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(mid)
	mid.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiStyle.header("JOIN A GAME — THE HOST'S ADDRESS"))
	field = LineEdit.new()
	field.custom_minimum_size = Vector2(360, 40)
	UiStyle.dress_field(field)
	field.placeholder_text = "192.168.1.20  or  host:7777"
	field.text = _last()
	field.text_submitted.connect(func(_t): _go())
	col.add_child(field)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	for b in [["JOIN", _go], ["BACK", func(): back.emit()]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(b[1])
		btn.mouse_entered.connect(_hover.bind(_rows.size()))
		_rows.append(btn)
		row.add_child(btn)
	_mark()
	field.grab_focus()

## Both rows dressed again: the one under the cursor white, bold, slid in.
func _mark() -> void:
	for i in _rows.size():
		var on := i == _cursor
		UiStyle.dress_row(_rows[i], on, false, 20, INDENT if on else 0.0)

func _hover(i: int) -> void:
	if i != _cursor:
		_cursor = i
		_mark()

func _go() -> void:
	var where := field.text.strip_edges()
	if where == "":
		return
	var cf := ConfigFile.new()
	cf.set_value("join", "host", where)
	cf.save(SAVE)
	join.emit(where)

static func _last() -> String:
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK:
		return str(cf.get_value("join", "host", ""))
	return ""

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		back.emit()
		get_viewport().set_input_as_handled()
	elif Pad.nav(event) == "back":
		back.emit()
		get_viewport().set_input_as_handled()
