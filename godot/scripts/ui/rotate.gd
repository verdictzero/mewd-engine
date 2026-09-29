## MEWD — a phone held upright (index.html #rotate).
##
## At the user's request: a full-screen red error, the rotate icon the
## user supplied (cut out of its background: godot/data/rotate_icon.png,
## black, still), and ROTATE DEVICE. Only on a touch screen held in
## portrait.
class_name RotateNotice
extends Control

var icon: Texture2D = preload("res://godot/data/rotate_icon.png")
var font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://assets/fonts/Michroma-Regular.ttf")
	resized.connect(queue_redraw)

func _process(_dt: float) -> void:
	var portrait := size.y > size.x
	var want := portrait and (DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"))
	if want != visible:
		visible = want
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#d0201a"))
	var s := minf(size.x, size.y) * 0.36
	var c := size * Vector2(0.5, 0.42)
	draw_texture_rect(icon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color.BLACK)
	var fs := int(clampf(size.x * 0.06, 16.0, 26.0))
	var t := "R O T A T E   D E V I C E"
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) / 2.0, c.y + s * 0.85), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
