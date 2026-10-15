class_name ViewerHud
extends CanvasLayer

## THE VIEWER'S WORDS over the picture: where you are and when, a line while
## the place is being built, and the keys (H).

const HELP := """MOUSE  click to look (Esc lets go)     W A S D  fly     E / Q  up / down
SHIFT  faster     CTRL  slower     WHEEL  flying speed     G  walk / fly
[ ]  the hour (with SHIFT, by the hour)     T  run the clock / hold it
F  the weather     K  the cinema on / off     P  native / retro picture
N  the next place     F12  a picture to user://     H  these keys"""

var info: Label
var loading: Label
var help: Label
var show_info := true


func _init() -> void:
	layer = 10
	var font := U.ui_font(true)
	info = _label(font, 15)
	info.position = Vector2(14, 10)
	add_child(info)
	loading = _label(font, 22)
	loading.set_anchors_preset(Control.PRESET_CENTER)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.grow_horizontal = Control.GROW_DIRECTION_BOTH
	loading.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(loading)
	help = _label(font, 14)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 14.0
	help.offset_top = -12.0
	help.offset_bottom = -12.0
	help.text = HELP
	help.visible = false
	add_child(help)


func _label(font: Font, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Everything off (for a clean picture: --shot, or the I key).
func set_clean(on: bool) -> void:
	show_info = not on
	info.visible = show_info
	help.visible = help.visible and show_info
