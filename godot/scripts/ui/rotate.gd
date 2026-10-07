## MEWD — a phone held upright (index.html #rotate).
##
## At the user's request: a full-screen error, the rotate icon the user
## supplied (cut out of its background: godot/data/rotate_icon.png,
## black, still), and ROTATE DEVICE. Only on a touch screen held in
## portrait.
##
## IN GOLF'S HOUSE STYLE, at the user's request (UiStyle, CutBox): no red
## any more, only greys — the near-black ground of a window, the black
## icon on a pale cut-cornered plate (white is the house's alarm), and
## the words spaced in its bold.
class_name RotateNotice
extends Control

var icon: Texture2D = preload("res://godot/data/rotate_icon.png")
var font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = UiStyle.words("Bold")
	resized.connect(queue_redraw)

func _process(_dt: float) -> void:
	var portrait := size.y > size.x
	var want := portrait and (DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"))
	if want != visible:
		visible = want
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.PANEL_BG, 1.0))
	var s := minf(size.x, size.y) * 0.36
	var c := size * Vector2(0.5, 0.42)
	# the plate the black icon stands on, a little bigger than it
	var pad := s * 0.14
	var plate := Rect2(c - Vector2(s, s) / 2.0 - Vector2(pad, pad), Vector2(s, s) + Vector2(pad, pad) * 2.0)
	CutBox.draw_on(self, plate, UiStyle.NAME, UiStyle.CURSOR, 2.0, UiStyle.CUT_WINDOW)
	draw_texture_rect(icon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color.BLACK)
	var fs := int(clampf(size.x * 0.06, 16.0, 26.0))
	var t := UiStyle.spaced("rotate device")
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) / 2.0, c.y + s * 0.85), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.NAME)
