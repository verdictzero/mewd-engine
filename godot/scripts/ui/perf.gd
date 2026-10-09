## MEWD — THE PERFORMANCE OVERLAY, at the user's request: how fast, where
## the time goes, and on what — so a handheld (an Anbernic RG557) or any
## other machine can say at a glance what it is doing and what it is.
## FRAME RATE on the pause menu's DEBUG page (on by default) shows it;
## F3, L3 + R3 together, or the PERF button on the glass turn it on and
## off (Main.toggle_perf).
##
##   the frame     frames a second, the frame's time, and the worst and
##                 best of the last second
##   the renderer  draw calls, objects and primitives in the frame, and
##                 video memory in use
##   the game      where a frame's time goes (Game.prof_text): the tics,
##                 the crowd, the guns, the effects, the scopes
##   the machine   the renderer and its API, the GPU, the CPU and its
##                 cores, the OS and the device, the window, the chunky
##                 grid the world is drawn at, and the refresh rate
##
## Four times a second, over a dark panel; the specs are read once. Never
## filtered by the lo-fi pass (it is on the HUD layer). IN THE LOWER LEFT
## CORNER, at the user's request (it sat at the top, over the health and
## armour): growing upward from the corner as its lines come and go, the
## gun's notices stacked above it while it shows (Hud._draw_toasts), and
## on the title above the version that has that corner (`stand_on`, Main).
## And the cores, and where the renderer is (Cores).
##
## IN GOLF'S HOUSE STYLE, at the user's request (UiStyle, CutBox): the
## panel a house window with a small cut, its keyline thin; the readout
## in the house's words (Medium) in NAME, no green.
class_name PerfOverlay
extends PanelContainer

const EVERY := 0.25
## from the screen's edges
const EDGE := 8.0

var label: Label
var game = null
## the lo-fi pipeline, for the size of the grid the world is drawn at
var lofi = null
var _spec := ""
var _acc := 0.0
var _worst := 0.0
var _best := 1e9
var _w_shown := 0.0
var _b_shown := 0.0
var _sec := 0.0
## what it stands on in the corner, when something else has it (the
## title's version: Main), or null for the edge
var stand_on: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := CutBox.new(UiStyle.PANEL_BG, UiStyle.PANEL_BORDER_REST, 1.0, UiStyle.CUT_CURSOR).margins(10, 6, 12, 6)
	add_theme_stylebox_override("panel", sb)
	label = Label.new()
	label.add_theme_font_override("font", UiStyle.words("Medium"))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiStyle.NAME)
	label.add_theme_constant_override("line_spacing", 0)
	add_child(label)
	_spec = spec_text()
	visibility_changed.connect(place)
	get_viewport().size_changed.connect(place)
	place()

## in the lower left corner — on the edge, or on `stand_on` where it is
## now — as tall as its lines now (shrunk back when they are fewer)
func place() -> void:
	reset_size()
	var bottom := get_viewport_rect().size.y - EDGE
	if stand_on != null and is_instance_valid(stand_on) and stand_on.is_inside_tree() and stand_on.visible:
		bottom = minf(bottom, stand_on.get_global_rect().position.y - 4.0)
	position = Vector2(EDGE, bottom - size.y)

## what the machine is, read once
static func spec_text() -> String:
	var rd := RenderingServer.get_rendering_device() != null
	var method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")
	if OS.has_feature("web"):
		method = "gl_compatibility"
	elif OS.has_feature("mobile"):
		method = ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", method)
	var api := RenderingServer.get_video_adapter_api_version()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var gpu := RenderingServer.get_video_adapter_name()
	if vendor != "" and vendor != "Unknown" and not gpu.begins_with(vendor):
		gpu = vendor + " " + gpu
	var cpu := OS.get_processor_name()
	if cpu == "":
		cpu = "CPU"
	var dev := OS.get_model_name()
	var os := "%s %s" % [OS.get_name(), OS.get_version()]
	var lines := [
		"%s · %s %s" % ["Mobile" if method == "mobile" else ("Forward+" if method == "forward_plus" else "Compatibility"),
			"Vulkan" if rd else "OpenGL", api],
		"GPU %s" % gpu.strip_edges(),
		"CPU %s × %d" % [cpu, OS.get_processor_count()],
		"%s%s" % [os, "" if dev == "" or dev == "GenericDevice" else " · " + dev],
	]
	return "\n".join(lines)

func _process(dt: float) -> void:
	if not visible:
		return
	var ms := dt * 1000.0
	_worst = maxf(_worst, ms)
	_best = minf(_best, ms)
	_sec += dt
	if _sec >= 1.0:
		_w_shown = _worst
		_b_shown = _best
		_worst = 0.0
		_best = 1e9
		_sec = 0.0
	_acc += dt
	if _acc < EVERY:
		return
	_acc = 0.0
	var fps := Engine.get_frames_per_second()
	var lines := []
	lines.append("%d FPS  %.1f ms  (%.1f–%.1f)" % [fps, 1000.0 / maxf(1.0, fps), _b_shown, _w_shown])
	lines.append("draw %d · objects %d · prims %dk · vram %d MB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])
	if is_instance_valid(game) and game != null:
		game._prof_on = true
		var t: String = game.prof_text()
		if t != "":
			lines.append(t)
	var win := DisplayServer.window_get_size()
	var grid := ""
	if lofi != null and lofi.world != null:
		grid = " · world %dx%d" % [lofi.world.size.x, lofi.world.size.y]
	var hz := DisplayServer.screen_get_refresh_rate()
	lines.append("window %dx%d%s%s" % [win.x, win.y, grid, (" · %d Hz" % roundi(hz)) if hz > 1.0 and hz < 1000.0 else ""])
	# (which of the gun's ways of drawing is in use: Lofi.gun_state)
	if lofi != null and lofi.has_method("gun_state"):
		lines.append(lofi.gun_state())
	lines.append(Cores.state())
	lines.append(_spec)
	label.text = "\n".join(lines)
	place()
