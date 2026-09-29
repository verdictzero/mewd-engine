## MEWD — the loading screen, at the user's request: between NEW GAME
## (or a play-test, or a join) and the first frame of the world.
##
## The map is built in one go and the first frames compile the shaders,
## so neither can be counted as it goes; what can be said honestly is
## WHICH of the two is happening. So: the MEWD logo on the boot splash's
## dark teal, LOADING under it, the step it is on, and a bar that moves
## a step at a time (main.gd start_game draws a frame between steps).
## When the world is up it fades out.
class_name LoadingScreen
extends Control

const BG := Color("#0b1314")
const INK := Color(0.81, 0.81, 0.84)
const RED := Color("#c8321e")

var logo: Texture2D = preload("res://godot/data/splash.png")
var font: Font
var step := ""
var done := 0.0
var _fade := -1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = U.ui_font(PackedStringArray(["monospace", "DejaVu Sans Mono"]))
	resized.connect(queue_redraw)

## the step it is on, and how far along the bar is (0..1)
func at(what: String, frac: float) -> void:
	step = what
	done = clampf(frac, 0.0, 1.0)
	queue_redraw()

## fade out over `secs`, then go
func finish(secs := 0.35) -> void:
	done = 1.0
	_fade = secs
	queue_redraw()

func _process(dt: float) -> void:
	if _fade < 0.0:
		return
	modulate.a -= dt / 0.35
	if modulate.a <= 0.0:
		queue_free()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var w := minf(size.x * 0.7, 960.0)
	var h := w * float(logo.get_height()) / float(logo.get_width())
	h = minf(h, size.y * 0.5)
	w = h * float(logo.get_width()) / float(logo.get_height())
	var top := (size.y - h) * 0.4
	draw_texture_rect(logo, Rect2((size.x - w) / 2.0, top, w, h), false)
	var fs := int(clampf(size.y * 0.024, 12.0, 20.0))
	var y := top + h + fs * 2.2
	var t := "L O A D I N G"
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - tw) / 2.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
	var bw := minf(size.x * 0.5, 420.0)
	var bh := maxf(4.0, fs * 0.45)
	var bx := (size.x - bw) / 2.0
	var by := y + fs * 0.9
	draw_rect(Rect2(bx, by, bw, bh), Color(1, 1, 1, 0.08))
	draw_rect(Rect2(bx, by, bw * done, bh), RED)
	draw_rect(Rect2(bx, by, bw, bh), Color(INK, 0.35), false, 1.0)
	if step != "":
		var sfs := maxi(10, fs - 5)
		var sw := font.get_string_size(step, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_string(font, Vector2((size.x - sw) / 2.0, by + bh + sfs * 2.0), step, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(INK, 0.6))
