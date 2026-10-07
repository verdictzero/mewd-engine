## MEWD — the loading screen, at the user's request: between NEW GAME
## (or a play-test, or a join) and the first frame of the world.
##
## The map is built in one go and the first frames compile the shaders,
## so neither can be counted as it goes; what can be said honestly is
## WHICH of the two is happening. So: the MEWD logo on near-black,
## LOADING under it, the step it is on, and a bar that moves
## a step at a time (main.gd start_game draws a frame between steps).
## When the world is up it fades out.
##
## IN GOLF'S HOUSE STYLE, at the user's request (UiStyle, CutBox): no
## teal and no red, only greys on near-black; LOADING and the step in the
## house's words, spaced, in TAG; the bar a dark track in a cut-cornered
## keyline, filled a step down the ramp; how far along in digital-7. (The
## logo is a picture, and is left as it is drawn.)
class_name LoadingScreen
extends Control

## the ground: as near black as the glass of a window, and opaque
const BG := Color(UiStyle.PANEL_BG, 1.0)

var logo: Texture2D = preload("res://godot/data/splash.png")
var font: Font
## the numbers' face (digital-7)
var nums: Font
var step := ""
var done := 0.0
var _fade := -1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = UiStyle.words("Medium")
	nums = UiStyle.numbers()
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
	var fs := int(clampf(size.y * 0.026, 13.0, 22.0))
	var y := top + h + fs * 2.2
	var t := UiStyle.spaced("loading")
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - tw) / 2.0, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.TAG)
	# THE BAR: the track and its keyline cut the house's way, the fill
	# inside the keyline, square
	var bw := minf(size.x * 0.5, 420.0)
	var bh := maxf(8.0, fs * 0.6)
	var bx := (size.x - bw) / 2.0
	var by := y + fs * 0.9
	var cut := minf(UiStyle.CUT_CURSOR, bh * 0.5)
	CutBox.draw_on(self, Rect2(bx, by, bw, bh), UiStyle.BAR_BG, Color(0, 0, 0, 0), 0.0, cut)
	if done > 0.0:
		var inner := Rect2(bx + 2.0, by + 2.0, (bw - 4.0) * done, bh - 4.0)
		CutBox.draw_on(self, inner, UiStyle.TP, Color(0, 0, 0, 0), 0.0, minf(cut, inner.size.x * 0.5))
	CutBox.draw_on(self, Rect2(bx, by, bw, bh), Color(0, 0, 0, 0), UiStyle.BAR_BORDER, 1.0, cut)
	# how far along, in the numbers' face, at the bar's right end
	var pct := UiStyle.padded(roundi(done * 100.0)) + "%"
	var nfs := maxi(12, fs - 2)
	var pw := nums.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
	draw_string(nums, Vector2(bx + bw - pw, by + bh + nfs * 1.4), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, UiStyle.NAME)
	if step != "":
		var sfs := maxi(11, fs - 6)
		var st := UiStyle.spaced(step)
		draw_string(font, Vector2(bx, by + bh + nfs * 1.4), st, HORIZONTAL_ALIGNMENT_LEFT, bw - pw - 12.0, sfs, UiStyle.TAG)
