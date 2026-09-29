## MEWD — the lo-fi picture (js/lofi.js, LofiPipeline, and its settings
## in js/main.js).
##
## The world drawn into a buffer of its own; the finished frame put onto
## a chunky grid of PIXELS 320 rows of 2:3 pixels; the Bayer DITHER, one
## step; and every pixel SNAPPED to the earth palette (lofi.gdshader).
## The buffer is `world`, a SubViewport the game is added under.
##
## FOR SPEED, at the user's request, and NEAREST EVERYWHERE: by default
## (RENDER_GRID) the world is drawn exactly as many pixels across as the
## grid has columns, the filter runs ONCE PER CHUNKY PIXEL into a
## grid-sized buffer of its own (`filter`), and that is blown up to the
## window nearest-neighbour. A 4K window costs what a 320-row one does.
## The HUD goes on a layer over this one and is not filtered — the
## readout is not part of the picture, as in the web build.
class_name Lofi
extends CanvasLayer

## the world's buffer as wide as the chunky grid (the default)
const RENDER_GRID := -1
const RENDER := RENDER_GRID
const PIXELS := 320
const PIXEL_ASPECT := 2.0 / 3.0

var world: SubViewport
## the gun: a world of its own, drawn over the room and under the filter
var gun: SubViewport
## the filtered frame, one texel per chunky pixel
var filter: SubViewport
var filter_rect: ColorRect
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
	gun = SubViewport.new()
	gun.name = "Gun"
	gun.own_world_3d = true
	gun.transparent_bg = true
	gun.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gun.msaa_3d = Viewport.MSAA_DISABLED
	add_child(gun)
	filter = SubViewport.new()
	filter.name = "Filter"
	filter.disable_3d = true
	filter.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(filter)
	filter_rect = ColorRect.new()
	filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/lofi.gdshader")
	mat.set_shader_parameter("lut", preload("res://godot/data/palette_lut.png"))
	filter_rect.material = mat
	filter.add_child(filter_rect)
	rect = TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(rect)
	# the picture a third brighter, at the user's request (js/main.js
	# DEFAULT_PREFS bright 1.35), before the dither and the snap
	set_picture(1.35, 1.0, 1.0)

func _ready() -> void:
	rect.texture = filter.get_texture()
	mat.set_shader_parameter("world_tex", world.get_texture())
	mat.set_shader_parameter("gun_tex", gun.get_texture())
	get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	if win.y <= 0.0:
		return
	var aspect := win.x / win.y
	# the grid: PIXELS rows (or, off, the RENDER buffer's own)
	var rows := float(pixel_rows) if pixel_rows > 0 else 0.0
	var cols := rows * aspect / pixel_aspect
	# the buffer: as wide as the grid (RENDER_GRID), RENDER rows, or the
	# screen's own if that is fewer
	var buf_rows: float
	if render_rows == RENDER_GRID:
		buf_rows = minf(cols / aspect, win.y) if rows > 0.0 else minf(480.0, win.y)
	elif render_rows > 0:
		buf_rows = minf(float(render_rows), win.y)
	else:
		buf_rows = win.y
	var buf := Vector2i(maxi(1, roundi(buf_rows * aspect)), maxi(1, roundi(buf_rows)))
	world.size = buf
	gun.size = buf
	if rows <= 0.0:
		rows = buf.y
		cols = buf.x
	var grid := Vector2i(maxi(1, roundi(cols)), maxi(1, roundi(rows)))
	filter.size = grid
	filter_rect.size = Vector2(grid)
	mat.set_shader_parameter("grid_size", Vector2(grid))
	# how many buffer pixels one chunky pixel covers, 1..4 each way
	var tx := clampf(roundf(buf.x / float(grid.x)), 1.0, 4.0)
	var ty := clampf(roundf(buf.y / float(grid.y)), 1.0, 4.0)
	mat.set_shader_parameter("taps", Vector2(tx, ty))

## brightness, contrast, gamma — applied before the dither and the snap,
## so a brighter picture is still made of the palette's colours
func set_picture(bright: float, contrast: float, gamma: float) -> void:
	mat.set_shader_parameter("picture", Vector3(bright, contrast, gamma))

## THE PALETTE GIVES WAY, by k (0..1): the potato cannon's nuke is too
## bright for it, and every colour it burns through gets onto the glass
## (game/potatoes.gd). 0 puts the snap back as it was.
func set_unsnap(k: float) -> void:
	mat.set_shader_parameter("snap", _snap * (1.0 - clampf(k, 0.0, 1.0)))

func set_tint(c: Color) -> void:
	mat.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))

## the filter on or off: off, the buffer is shown as it is
var _snap := 1.0
func set_filtered(on: bool) -> void:
	_snap = 1.0 if on else 0.0
	mat.set_shader_parameter("snap", _snap)
	mat.set_shader_parameter("dither", 1.0 if on else 0.0)
