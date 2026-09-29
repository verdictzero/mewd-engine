## MEWD — the lo-fi picture (js/lofi.js, LofiPipeline, and its settings
## in js/main.js).
##
## The web build's defaults, at the user's request there: the world
## drawn at RENDER 960 rows into a buffer of its own; the finished frame
## averaged down onto a chunky grid of PIXELS 320 rows of 2:3 pixels;
## the Bayer DITHER, one step; and every pixel SNAPPED to the earth
## palette (lofi.gdshader). The buffer is `world`, a SubViewport the
## game is added under; the filter is a full-screen TextureRect showing
## it. The HUD goes on a layer over this one and is not filtered — the
## readout is not part of the picture, as in the web build.
class_name Lofi
extends CanvasLayer

const RENDER := 960
const PIXELS := 320
const PIXEL_ASPECT := 2.0 / 3.0

var world: SubViewport
var rect: TextureRect
var mat: ShaderMaterial
var render_rows := RENDER
var pixel_rows := PIXELS
var pixel_aspect := PIXEL_ASPECT

func _init() -> void:
	layer = 0
	world = SubViewport.new()
	world.name = "World"
	world.own_world_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.msaa_3d = Viewport.MSAA_DISABLED
	add_child(world)
	rect = TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# linear, for the taps that fall between buffer pixels (see the shader)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/lofi.gdshader")
	mat.set_shader_parameter("lut", preload("res://godot/data/palette_lut.png"))
	rect.material = mat
	add_child(rect)

func _ready() -> void:
	rect.texture = world.get_texture()
	get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	if win.y <= 0.0:
		return
	# the buffer: RENDER rows, or the screen's own if that is fewer
	var buf_rows := minf(float(render_rows), win.y) if render_rows > 0 else win.y
	var buf := Vector2i(roundi(buf_rows * win.x / win.y), roundi(buf_rows))
	world.size = buf
	var rows := float(pixel_rows) if pixel_rows > 0 else buf_rows
	var cols := rows * (win.x / win.y) / pixel_aspect
	mat.set_shader_parameter("grid_size", Vector2(cols, rows))
	# how many buffer pixels one chunky pixel covers, 1..4 each way
	var tx := clampf(roundf(buf.x / cols), 1.0, 4.0)
	var ty := clampf(roundf(buf.y / rows), 1.0, 4.0)
	mat.set_shader_parameter("taps", Vector2(tx, ty))

func set_tint(c: Color) -> void:
	mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))

## the filter on or off: off, the buffer is shown as it is
func set_filtered(on: bool) -> void:
	mat.set_shader_parameter("snap", 1.0 if on else 0.0)
	mat.set_shader_parameter("dither", 1.0 if on else 0.0)
