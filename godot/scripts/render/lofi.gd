## MEWD — the lo-fi picture (js/lofi.js, LofiPipeline, and its settings
## in js/main.js).
##
## The world drawn into a buffer of its own (720 rows by default); the
## finished frame put onto a chunky grid of PIXELS, 480 rows of square
## pixels by default, whole screen pixels each (_resize); the Bayer DITHER, one
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
## the defaults, at the user's request: square pixels, 480 rows, the
## world drawn at 720 (pause.gd DEFAULTS)
const RENDER := 720
const PIXELS := 480
const PIXEL_ASPECT := 1.0

var world: SubViewport
## the gun: a world of its own, drawn over the room and under the filter
var gun: SubViewport
## the filtered frame, one texel per chunky pixel
var filter: SubViewport
var filter_rect: ColorRect
var rect: TextureRect
var mat: ShaderMaterial
## THE GUN OVER THE ROOM, UNDER MOBILE: the room's picture is drawn in
## the gun's own world first, behind everything (gun_room.gdshader), and
## the gun straight onto it, so the filter reads one picture.
## Compatibility composites the two by the gun's alpha instead — which
## Mobile does not keep: its 3D targets hold two bits of alpha, and on a
## phone's GPU (an Adreno) whole pieces of a solid gun came out as holes
## with the room showing through.
var gun_on_room := false
var render_rows := RENDER
var pixel_rows := PIXELS
var pixel_aspect := PIXEL_ASPECT

func _init() -> void:
	layer = 0
	world = SubViewport.new()
	U.raw_out(world)
	world.name = "World"
	world.own_world_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.msaa_3d = Viewport.MSAA_DISABLED
	add_child(world)
	gun = SubViewport.new()
	U.raw_out(gun)
	gun.name = "Gun"
	gun.own_world_3d = true
	gun.transparent_bg = true
	gun.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	gun.msaa_3d = Viewport.MSAA_DISABLED
	add_child(gun)
	gun_on_room = RenderingServer.get_rendering_device() != null
	if gun_on_room:
		gun.transparent_bg = false
		# the room: a quad over the whole view, put at the far plane by its
		# own vertex shader, in the gun's world — so the gun, nearer, is
		# drawn over it by the depth test, and its glass blends onto it
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		var rm := ShaderMaterial.new()
		rm.shader = preload("res://godot/shaders/gun_room.gdshader")
		q.material = rm
		var room := MeshInstance3D.new()
		room.name = "Room"
		room.mesh = q
		room.extra_cull_margin = 16384.0
		room.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gun.add_child(room)
		# an eye that is always there: with no camera (the title, the
		# editor — no gun yet) the viewport draws nothing, and the room
		# with it came out black. The gun's own camera takes over while
		# it is held, and this one again when it goes.
		var eye := Camera3D.new()
		eye.name = "RoomEye"
		gun.add_child(eye)
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
	# (black round the picture, where the screen is not a whole number of
	# chunky pixels: _resize)
	var border := ColorRect.new()
	border.color = Color.BLACK
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)
	rect = TextureRect.new()
	# (placed and sized by _resize, in whole screen pixels)
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
	mat.set_shader_parameter("world_tex", U.col(world.get_texture()))
	mat.set_shader_parameter("gun_tex", U.col(gun.get_texture()))
	mat.set_shader_parameter("gun_on_room", gun_on_room)
	if gun_on_room:
		((gun.get_node("Room") as MeshInstance3D).mesh.material as ShaderMaterial).set_shader_parameter("room", world.get_texture())
	get_viewport().size_changed.connect(_resize)
	_resize()

## THE PICTURE NEVER STRETCHES BY A FRACTION, at the user's request
## ("only mathematically acceptable ratios that won't result in
## distortion"): every chunky pixel is a whole number of the SCREEN's
## own pixels across and down, so no column or row comes out wider than
## its neighbours. The scale is picked in physical pixels (the window is
## stretched as canvas items, so the canvas's units are not the screen's):
## the whole number that brings the grid's rows nearest PIXELS — 480 rows
## asked for is 540 on a 1080 screen (x2), 360 on a 720 one (x2), 480 on
## a 1440 one (x3). The columns are as many whole pixels as fit at that
## scale; what is left over (less than one chunky pixel each way) is a
## black border, centred. A non-square PIXEL ASPECT is a whole number of
## screen pixels across too, the nearest to the asked ratio. The world is
## then drawn RENDER rows (720 by default, never more than the screen's
## own) at exactly the grid's aspect, and the filter boxes it down.
func _resize() -> void:
	var vp := get_viewport()
	var win := Vector2(vp.get_visible_rect().size)
	if win.y <= 0.0:
		return
	# canvas units to screen pixels
	var k := vp.get_final_transform().get_scale().x
	if k <= 0.0:
		k = 1.0
	var phys := (win * k).floor()
	# the rows wanted: PIXELS, or (pixels off) the render's rows, or the screen's
	var want := float(pixel_rows) if pixel_rows > 0 else (float(render_rows) if render_rows > 0 else phys.y)
	# the whole-number scale whose rows come nearest it
	var sy := maxi(1, floori(phys.y / want))
	if sy + 1 <= int(phys.y) and absf(phys.y / (sy + 1) - want) < absf(phys.y / sy - want):
		sy += 1
	var sx := maxi(1, roundi(sy * pixel_aspect)) if pixel_rows > 0 else sy
	var grid := Vector2i(maxi(1, floori(phys.x / sx)), maxi(1, floori(phys.y / sy)))
	# the buffer: the grid's own (RENDER_GRID), RENDER rows, or the
	# screen's, at the grid's shape exactly — never more rows than it has
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
	gun.size = buf
	filter.size = grid
	filter_rect.size = Vector2(grid)
	mat.set_shader_parameter("grid_size", U.col(Vector2(grid)))
	# how many buffer pixels one chunky pixel covers, 1..4 each way
	var tx := clampf(roundf(buf.x / float(grid.x)), 1.0, 4.0)
	var ty := clampf(roundf(buf.y / float(grid.y)), 1.0, 4.0)
	mat.set_shader_parameter("taps", U.col(Vector2(tx, ty)))
	# and the picture on the screen: whole pixels, centred, in canvas units
	var shown := Vector2(grid.x * sx, grid.y * sy)
	var at := ((phys - shown) * 0.5).floor()
	rect.position = at / k
	rect.size = shown / k

## brightness, contrast, gamma — applied before the dither and the snap,
## so a brighter picture is still made of the palette's colours
func set_picture(bright: float, contrast: float, gamma: float) -> void:
	mat.set_shader_parameter("picture", U.col(Vector3(bright, contrast, gamma)))

## THE PALETTE GIVES WAY, by k (0..1): the potato cannon's nuke is too
## bright for it, and every colour it burns through gets onto the glass
## (game/potatoes.gd). 0 puts the snap back as it was.
func set_unsnap(k: float) -> void:
	mat.set_shader_parameter("snap", U.col(_snap * (1.0 - clampf(k, 0.0, 1.0))))

## AN ISLAND'S OWN PICTURE (Islands.LIST): its exposure and the
## tonemap's shoulder (lofi.gdshader), and whether it is snapped to the
## earth palette — `snap_pref`, the player's FILTER setting, and the
## island's "palette". Every island that asks nothing is drawn as before.
func for_island(spec: Dictionary, snap_pref: bool) -> void:
	mat.set_shader_parameter("exposure", U.col(float(spec.get("exposure", 1.0))))
	mat.set_shader_parameter("knee", U.col(float(spec.get("knee", 0.0))))
	_snap = 1.0 if (snap_pref and bool(spec.get("palette", true))) else 0.0
	mat.set_shader_parameter("snap", U.col(_snap))
	mat.set_shader_parameter("dither", U.col(1.0 if snap_pref else 0.0))

func set_tint(c: Color) -> void:
	mat.set_shader_parameter("tint", U.col(Vector3(c.r, c.g, c.b)))

## the filter on or off: off, the buffer is shown as it is
var _snap := 1.0
func set_filtered(on: bool) -> void:
	_snap = 1.0 if on else 0.0
	mat.set_shader_parameter("snap", U.col(_snap))
	mat.set_shader_parameter("dither", U.col(1.0 if on else 0.0))
