## FENRIR — THE MARK, AT EVERY SIZE IT IS SHOWN (at the user's request:
## "this needs to be called FENRIR, not MEWD, here is some branding"):
## tools/brand/FENRIR_logo.svg (the round badge: FUSION-ENABLED NETWORKED
## REAL-TIME INTERACTIVE RENDERING round a wolf and the stars) drawn by
## Godot's own SVG rasteriser, everything outside its disc clear, into
##
##   godot/data/brand/fenrir_logo.png   1024 px: the loading screen
##   icon.png                           512 px: the window's and the project's
##   godot/data/splash.png              480 px: the boot splash (on black)
##   godot/data/icons/main_192.png      Android's launcher icon
##   godot/data/icons/fg_432.png        its adaptive foreground (the badge
##                                      inside the mask's safe circle)
##   godot/data/icons/bg_432.png        and background (black)
##
##   godot --headless --path . --script res://tools/brand_icons.gd
extends SceneTree

const SRC := "res://tools/brand/FENRIR_logo.svg"


func _init() -> void:
	var svg := FileAccess.get_file_as_string(SRC)
	if svg.is_empty():
		push_error("brand_icons: cannot read %s" % SRC)
		quit(1)
		return
	_save(_badge(svg, 1024), "res://godot/data/brand/fenrir_logo.png")
	_save(_badge(svg, 512), "res://icon.png")
	_save(_badge(svg, 480), "res://godot/data/splash.png")
	_save(_badge(svg, 192), "res://godot/data/icons/main_192.png")
	# (the adaptive icon's mask keeps a circle 66/108 of the layer across)
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	var inner := _badge(svg, 264)
	fg.blend_rect(inner, Rect2i(0, 0, 264, 264), Vector2i(84, 84))
	_save(fg, "res://godot/data/icons/fg_432.png")
	var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	bg.fill(Color(0, 0, 0, 1))
	_save(bg, "res://godot/data/icons/bg_432.png")
	quit()


# the badge `size` pixels across, drawn at twice that and brought down (a
# smoother edge), clear outside its disc
func _badge(svg: String, size: int) -> Image:
	var img := Image.new()
	var err := img.load_svg_from_string(svg, float(size * 2) / 1773.0)
	if err != OK:
		push_error("brand_icons: the SVG would not draw (%d)" % err)
		return Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var c := (float(size) - 1.0) * 0.5
	var r := float(size) * 0.5 - 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x) - c, float(y) - c).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a < 1.0:
				var p := img.get_pixel(x, y)
				p.a *= a
				img.set_pixel(x, y, p)
	return img


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("brand_icons: %s (%dx%d)%s" % [path, img.get_width(), img.get_height(), "" if err == OK else " FAILED %d" % err])
