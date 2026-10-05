## MEWD — JOIN GAME (the title's MULTIPLAYER page): where the host is,
## typed (the last one kept, user://join.cfg), then JOIN or BACK. Enter
## joins, Escape goes back; on a phone the field brings up the keyboard.
class_name JoinBox
extends Control

signal join(where: String)
signal back

const SAVE := "user://join.cfg"

var field: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.06, 0.95)
	sb.border_color = Color("#c8321e")
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	var mid := CenterContainer.new()
	mid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(mid)
	mid.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var font := U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono"]))
	var l := Label.new()
	l.text = "JOIN A GAME — THE HOST'S ADDRESS"
	l.add_theme_font_override("font", font)
	col.add_child(l)
	field = LineEdit.new()
	field.custom_minimum_size = Vector2(360, 40)
	field.add_theme_font_override("font", font)
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
		btn.add_theme_font_override("font", font)
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(b[1])
		row.add_child(btn)
	field.grab_focus()

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
