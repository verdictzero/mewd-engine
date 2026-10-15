## THE PICTURE: the world drawn into a buffer of its own (`world`, a
## SubViewport the place is added under), then filtered onto the screen
## (lofi.gdshader): the island's exposure and tonemap shoulder, the meter's
## (THE METER, below), its colour grade (Islands "grade"), film grain, and —
## in the RETRO picture — a
## chunky grid of square pixels, the Bayer dither and the earth palette.
##
## NATIVE (the default): the world drawn at the screen's own resolution and
## the filter run once a pixel, only the grade on it. RETRO: the world drawn
## `render_rows` high, the filter run once per chunky pixel into a grid-sized
## buffer (`filter`), blown up to the window nearest-neighbour in whole screen
## pixels, under an LCD grid where the chunky pixels are big enough.
class_name Lofi
extends CanvasLayer

## the world's buffer as wide as the chunky grid
const RENDER_GRID := -1

var world: SubViewport
## the filtered frame
var filter: SubViewport
var filter_rect: ColorRect
var rect: TextureRect
var mat: ShaderMaterial
## rows the world is drawn at (0: the screen's), rows of chunky pixels
## (0: none, the screen's own pixels), and their shape
var render_rows := 0
var pixel_rows := 0
var pixel_aspect := 1.0
## THE PIXEL GRID (pixel_grid.gdshader): "lcd", "lines" or "off"
var grid_mode := "lcd"
var grid_mat: ShaderMaterial
var grid_strength := 0.0
var _snap := 0.0
var _palette := true
var _grade_grain := false
## THE METER (lofi_meter.gdshader): the picture's brightness, read as a
## camera's meter reads it and eased toward a frame at a time, into one pixel
## (`meter`; `meter_hold` keeps last frame's for the easing), and the
## exposure opened or stopped down toward the island's key by it
## (lofi.gdshader `metered`; Islands "meter").
var meter: SubViewport
var meter_hold: SubViewport
var meter_mat: ShaderMaterial
const METER_REST := {"key": 0.4, "strength": 0.6, "least": 0.7, "most": 2.5}


func _init() -> void:
	layer = 0
	world = SubViewport.new()
	U.raw_out(world)
	world.name = "World"
	world.own_world_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.msaa_3d = Viewport.MSAA_DISABLED
	add_child(world)
	filter = SubViewport.new()
	filter.name = "Filter"
	filter.disable_3d = true
	filter.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(filter)
	filter_rect = ColorRect.new()
	filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/lofi.gdshader")
	mat.set_shader_parameter("lut", U.col(preload("res://godot/data/palette_lut.png")))
	filter_rect.material = mat
	filter.add_child(filter_rect)
	meter_mat = ShaderMaterial.new()
	meter_mat.shader = preload("res://godot/shaders/lofi_meter.gdshader")
	meter = _pixel("Meter", meter_mat)
	var hold_mat := ShaderMaterial.new()
	hold_mat.shader = meter_mat.shader
	hold_mat.set_shader_parameter("hold", true)
	meter_hold = _pixel("MeterHold", hold_mat)
	# (black round the picture, where the screen is not a whole number of
	# chunky pixels: _resize)
	var border := ColorRect.new()
	border.color = Color.BLACK
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	rect = TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	grid_mat = ShaderMaterial.new()
	grid_mat.shader = preload("res://godot/shaders/pixel_grid.gdshader")
	rect.material = grid_mat
	add_child(rect)
	set_picture(1.0, 1.0, 1.0)
	set_filtered(false)


# a one-pixel buffer drawn by `m`, every frame
func _pixel(n: String, m: ShaderMaterial) -> SubViewport:
	var v := SubViewport.new()
	v.name = n
	v.disable_3d = true
	v.size = Vector2i(1, 1)
	v.transparent_bg = true
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var r := ColorRect.new()
	r.size = Vector2(1, 1)
	r.material = m
	v.add_child(r)
	add_child(v)
	return v


func _ready() -> void:
	rect.texture = filter.get_texture()
	mat.set_shader_parameter("world_tex", U.col(world.get_texture()))
	meter_mat.set_shader_parameter("world_tex", world.get_texture())
	meter_mat.set_shader_parameter("held", meter_hold.get_texture())
	(meter_hold.get_child(0).material as ShaderMaterial).set_shader_parameter("held", meter.get_texture())
	mat.set_shader_parameter("meter_tex", meter.get_texture())
	get_viewport().size_changed.connect(_resize)
	_resize()


## NATIVE (false) or RETRO (true): the screen's own pixels and nothing but
## the grade, or 360 rows of square chunky pixels, dithered.
func set_retro(on: bool) -> void:
	render_rows = 360 if on else 0
	pixel_rows = 360 if on else 0
	set_filtered(on)
	_resize()


func is_retro() -> bool:
	return pixel_rows > 0


## THE PICTURE NEVER STRETCHES BY A FRACTION: every chunky pixel is a whole
## number of the SCREEN's own pixels across and down; what is left over is a
## black border, centred. The world is drawn `render_rows` rows (never more
## than the screen's own) at the grid's aspect, and the filter boxes it down.
func _resize() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	var win := Vector2(vp.get_visible_rect().size)
	if win.y <= 0.0:
		return
	var k := vp.get_final_transform().get_scale().x
	if k <= 0.0:
		k = 1.0
	var phys := (win * k).floor()
	var want := float(pixel_rows) if pixel_rows > 0 else (float(render_rows) if render_rows > 0 else phys.y)
	var sy := maxi(1, floori(phys.y / want))
	if sy + 1 <= int(phys.y) and absf(phys.y / (sy + 1) - want) < absf(phys.y / sy - want):
		sy += 1
	var sx := maxi(1, roundi(sy * pixel_aspect)) if pixel_rows > 0 else sy
	var grid := Vector2i(maxi(1, floori(phys.x / sx)), maxi(1, floori(phys.y / sy)))
	var shape := float(grid.x * sx) / float(grid.y * sy)
	var buf_rows: float
	if render_rows == RENDER_GRID:
		buf_rows = float(grid.y)
	elif render_rows > 0:
		buf_rows = minf(float(render_rows), float(grid.y * sy))
	else:
		buf_rows = float(grid.y * sy)
	var buf := Vector2i(maxi(1, roundi(buf_rows * shape)), maxi(1, roundi(buf_rows)))
	if render_rows == RENDER_GRID:
		buf = grid
	world.size = buf
	filter.size = grid
	filter_rect.size = Vector2(grid)
	mat.set_shader_parameter("grid_size", U.col(Vector2(grid)))
	var tx := clampf(roundf(buf.x / float(grid.x)), 1.0, 4.0)
	var ty := clampf(roundf(buf.y / float(grid.y)), 1.0, 4.0)
	mat.set_shader_parameter("taps", U.col(Vector2(tx, ty)))
	var shown := Vector2(grid.x * sx, grid.y * sy)
	var at := ((phys - shown) * 0.5).floor()
	rect.position = at / k
	rect.size = shown / k
	_grid(Vector2(sx, sy), grid)


## The grid for this many screen pixels a chunky pixel: 0 off, 1 the gaps
## alone, 2 the LCD panel.
func _grid(cell: Vector2, grid: Vector2i) -> void:
	var small := minf(cell.x, cell.y)
	var m := 0
	match grid_mode:
		"off": m = 0
		"lines": m = 1 if small >= 3.0 else 0
		_: m = 2 if small >= 3.0 else 0
	if pixel_rows <= 0:
		m = 0
	grid_strength = float(m)
	grid_mat.set_shader_parameter("cells", Vector2(grid))
	grid_mat.set_shader_parameter("cell_px", cell)
	grid_mat.set_shader_parameter("mode", m)


## brightness, contrast, gamma — before the dither and the snap
func set_picture(bright: float, contrast: float, gamma: float) -> void:
	mat.set_shader_parameter("picture", U.col(Vector3(bright, contrast, gamma)))


## AN ISLAND'S OWN PICTURE (Islands.LIST): its exposure and the tonemap's
## shoulder, its meter, whether the retro picture snaps it to the earth
## palette (its "palette"), and its grade.
func for_island(spec: Dictionary) -> void:
	mat.set_shader_parameter("exposure", U.col(float(spec.get("exposure", 1.0))))
	set_meter_spec(spec.get("meter", {}))
	mat.set_shader_parameter("knee", U.col(float(spec.get("knee", 0.0))))
	_palette = bool(spec.get("palette", true))
	set_filtered(pixel_rows > 0)
	set_grade(spec.get("grade", {}))


## THE METER'S NUMBERS: an island's Islands "meter" — "key" (the picture's
## brightness it opens or stops down toward, 0..1 as the screen shows it),
## "strength" (how far toward it: 1 all the way, 0 not at all), "least" and
## "most" (the bounds on what it does to the exposure). Empty: METER_REST.
## {"off": true}: none.
func set_meter_spec(m: Dictionary) -> void:
	mat.set_shader_parameter("meter_on", U.col(0.0 if bool(m.get("off", false)) else 1.0))
	mat.set_shader_parameter("meter_key", U.col(float(m.get("key", METER_REST.key))))
	mat.set_shader_parameter("meter_strength", U.col(float(m.get("strength", METER_REST.strength))))
	mat.set_shader_parameter("meter_range", U.col(Vector2(float(m.get("least", METER_REST.least)),
			float(m.get("most", METER_REST.most)))))


## How fast the meter follows the picture, a share a frame: under 0 it
## forgets (nothing worth reading), 1 takes each frame's reading as it is.
func set_meter_rate(k: float) -> void:
	meter_mat.set_shader_parameter("rate", k)


## THE GRADE (lofi.gdshader): an island's Islands "grade", a dictionary of
## the shader's grade_* numbers without the prefix ("filmic", "warmth",
## "tint", "contrast", "saturation", "vibrance", "shadows", "highlights"
## (colours), "split", "vignette", "lift") and "grain" (film grain). Empty: none.
const GRADE_REST := {"filmic": 0.0, "warmth": 0.0, "tint": 0.0, "contrast": 0.0,
	"saturation": 1.0, "vibrance": 0.0, "shadows": Color(0.0, 0.5, 0.55),
	"highlights": Color(1.0, 0.62, 0.3), "split": 0.0, "vignette": 0.0, "lift": 0.0}
func set_grade(g: Dictionary) -> void:
	mat.set_shader_parameter("grade", U.col(0.0 if g.is_empty() else 1.0))
	for k in GRADE_REST:
		var v = g.get(k, GRADE_REST[k])
		if v is Color:
			v = Vector3(v.r, v.g, v.b)
		mat.set_shader_parameter("grade_" + k, U.col(v))
	# (the grain is the grade's only while a grade gave it)
	if g.has("grain"):
		set_grain(float(g.grain))
		_grade_grain = true
	elif _grade_grain:
		set_grain(0.0)
		_grade_grain = false


## film grain under the filter, how strong (0 none)
func set_grain(k: float) -> void:
	mat.set_shader_parameter("grain", U.col(maxf(k, 0.0)))


## the dither and the palette on (the retro picture) or off
func set_filtered(on: bool) -> void:
	_snap = 1.0 if (on and _palette) else 0.0
	mat.set_shader_parameter("snap", U.col(_snap))
	mat.set_shader_parameter("dither", U.col(1.0 if on else 0.0))
