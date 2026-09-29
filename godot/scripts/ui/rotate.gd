## MEWD — a phone held upright (index.html #rotate).
##
## At the user's request: a full-screen red error, a black rotate-to-
## landscape icon (Material Icons' screen_rotation, drawn from its path)
## nudging a quarter turn and back, and ROTATE DEVICE. Only on a touch
## screen held in portrait.
class_name RotateNotice
extends Control

## Material Icons "screen_rotation", 24x24 path, as polygons
var icon: Array[PackedVector2Array] = []
var _t := 0.0
var font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://assets/fonts/Michroma-Regular.ttf")
	# the phone, on its side, and the two arcs of the arrow
	icon.append(PackedVector2Array([Vector2(10.23, 1.75), Vector2(22.25, 13.77), Vector2(13.77, 22.25), Vector2(1.75, 10.23)]))

func _process(dt: float) -> void:
	_t += dt
	var portrait := size.y > size.x
	visible = portrait and (DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"))
	if visible:
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#d0201a"))
	var s := minf(size.x, size.y) * 0.32
	var c := size * Vector2(0.5, 0.42)
	# nudge: a quarter turn and back, every three seconds
	var ph := fmod(_t, 3.0) / 3.0
	var ang := 0.0
	if ph > 0.35 and ph < 0.55:
		ang = -PI / 2.0 * (ph - 0.35) / 0.2
	elif ph >= 0.55 and ph < 0.9:
		ang = -PI / 2.0
	elif ph >= 0.9:
		ang = -PI / 2.0 * (1.0 - (ph - 0.9) / 0.1)
	var xf := Transform2D(ang, c) * Transform2D(0.0, Vector2(-s / 2.0, -s / 2.0))
	var k := s / 24.0
	# the phone: an outlined slab with a screen inside
	var body := PackedVector2Array()
	for p in [Vector2(10.23, 1.75), Vector2(22.25, 13.77), Vector2(13.77, 22.25), Vector2(1.75, 10.23)]:
		body.append(xf * (p * k))
	draw_colored_polygon(body, Color.BLACK)
	var screen := PackedVector2Array()
	for p in [Vector2(10.23, 4.2), Vector2(19.8, 13.77), Vector2(13.77, 19.8), Vector2(4.2, 10.23)]:
		screen.append(xf * (p * k))
	draw_colored_polygon(screen, Color("#d0201a"))
	# and the two arrows round it
	draw_arc(xf * (Vector2(12, 12) * k), 11.0 * k, PI * 1.05, PI * 1.45, 16, Color.BLACK, 1.6 * k)
	draw_arc(xf * (Vector2(12, 12) * k), 11.0 * k, PI * 0.05, PI * 0.45, 16, Color.BLACK, 1.6 * k)
	var fs := int(clampf(size.x * 0.06, 16.0, 26.0))
	var t := "R O T A T E   D E V I C E"
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) / 2.0, c.y + s * 0.95), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.BLACK)
