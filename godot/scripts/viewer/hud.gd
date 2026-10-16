class_name ViewerHud
extends CanvasLayer

## THE VIEWER'S WORDS over the picture: where you are and when, the keys
## (H), and THE COVER while a place is being built — black, FENRIR's badge
## (tools/brand_icons.gd), and under it the place and what is happening
## (`loading`) — faded off as the place comes up.

const HELP := """MOUSE  click to look, or drag with the right button (Esc lets go)
W A S D  fly     E / Q  up / down
SHIFT  faster     CTRL  slower     WHEEL  flying speed     G  walk / fly
[ ]  the hour (with SHIFT, by the hour)     T  run the clock / hold it
F  the weather     K  the cinema on / off     P  native / retro picture
B  the field at the edge on / off     N  the next place
M  the world map: build any place on Earth
F12  a picture to user://     H  these keys"""

var info: Label
var loading: Label
var help: Label
var cover: Control
var show_info := true
var _covering := true
const COVER_FADE := 0.6


func _init() -> void:
	layer = 10
	var font := U.ui_font(true)
	cover = Control.new()
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(black)
	# (the badge in the upper part of the screen, as big as it fits, round)
	var badge := TextureRect.new()
	badge.texture = preload("res://godot/data/brand/fenrir_logo.png")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	badge.anchor_right = 1.0
	badge.anchor_top = 0.1
	badge.anchor_bottom = 0.7
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(badge)
	loading = _label(font, 22)
	loading.anchor_right = 1.0
	loading.anchor_top = 0.74
	loading.anchor_bottom = 0.74
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cover.add_child(loading)
	info = _label(font, 15)
	info.position = Vector2(14, 10)
	add_child(info)
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


## The cover up (a place being built) or fading off (it is up).
func set_loading(on: bool) -> void:
	if on and not _covering:
		cover.modulate.a = 1.0
		cover.visible = true
	_covering = on


func _process(dt: float) -> void:
	# (the readout over the picture, not over the cover)
	info.visible = show_info and not _covering
	if not _covering and cover.visible:
		cover.modulate.a -= dt / COVER_FADE
		if cover.modulate.a <= 0.0:
			cover.visible = false


## Everything off (for a clean picture: --shot, or the I key).
func set_clean(on: bool) -> void:
	show_info = not on
	info.visible = show_info
	help.visible = help.visible and show_info
