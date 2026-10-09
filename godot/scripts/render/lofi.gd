## MEWD — the lo-fi picture (js/lofi.js, LofiPipeline, and its settings
## in js/main.js).
##
## The world drawn into a buffer of its own (360 rows by default); the
## finished frame put onto a chunky grid of PIXELS, 360 rows of square
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
## the defaults, at the user's request: square pixels, 360 rows, the
## world drawn at 360, under the LCD grid (pause.gd DEFAULTS, at the
## user's request)
const RENDER := 360
const PIXELS := 360
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
## Compatibility composites the two by the gun's alpha instead. (On a
## phone's Adreno whole pieces of a solid gun once came out as holes with
## the room showing through; that was put down to Mobile's alpha, but was
## most likely the black squares below, in another guise.)
var gun_on_room := false

## THE GUN'S BLACK SQUARES, ON AN ADRENO (at the user's request: "weird
## weapon artifacting on Qualcomm GPU", "this gun rendering bug is still
## happening", "just adreno qualcomm" — never on a MediaTek's Mali). They
## were blocks of exactly 8 x 8 of the gun's texels, on its 8-texel grid,
## where NOTHING was drawn — the clear grey, neither the gun nor the room
## behind it: whole blocks thrown away before they were shaded. That is
## the shape of an Adreno's LRZ, the coarse depth test kept one value to
## 8 x 8 pixels, holding a value it should not. So, by default:
##   - DEPTH, "shader": every draw in the gun's world that writes depth
##     writes it itself (gun, gun_matcap, the scope screens and optic, the
##     room: `DEPTH = FRAGCOORD.z`, the value the GPU would have written,
##     so nothing looks different), and a draw that writes its own depth
##     is neither tested against LRZ nor written into it;
##   - TONEMAP, "auto": on an Adreno the gun's frame is tonemapped in a
##     pass of its own (an empty compositor effect), the way the world's
##     is, which never showed a square — rather than in a second subpass
##     of the 3D pass. (Elsewhere left as it was: it shifts a few texels by
##     a half-float step.)
## And the switches to tell the causes apart on the phone, if a square is
## ever seen again (the DEBUG page: GUN DEPTH, GUN TONEMAP, GUN CLEAR, GUN
## HDR; Main.apply_prefs -> gun_diag):
##   DEPTH "fixed" the GPU's own depth again (as before), "nodiscard" that
##   and the gun's cut-out compiled out; TONEMAP "pass" or "subpass"
##   forced; CLEAR "magenta" paints where nothing was drawn magenta; HDR
##   off draws the gun in 8-bit colour (the picture's numbers come out
##   wrong — for telling a colour-compression fault by its new shape).
const GUN_SHADERS := ["res://godot/shaders/gun.gdshader", "res://godot/shaders/gun_matcap.gdshader",
	"res://godot/shaders/scope_screen.gdshader", "res://godot/shaders/thermal_screen.gdshader",
	"res://godot/shaders/scope_optic.gdshader", "res://godot/shaders/gun_room.gdshader"]
var gun_depth := "shader"
var gun_tone := "auto"
var gun_clear := "grey"
var gun_hdr := true
## the tonemap in a pass of its own, now
var gun_tone_pass := false
## (kept: the scenario holds only its RID)
var gun_comp: Compositor
var _gun_variants := {}
var _gun_magenta: Environment
## (the gun world's own environment, if it had one, while MAGENTA stands in)
var _gun_env_was: Environment
var render_rows := RENDER
var pixel_rows := PIXELS
var pixel_aspect := PIXEL_ASPECT
## THE PIXEL GRID (pixel_grid.gdshader, at the user's request: "the
## ability to choose either pixel grid lines, LCD grid lines, or
## neither"): "lcd" (the panel: gaps and red, green and blue stripes),
## "lines" (the gaps alone, a plain grid) or "off". Either is drawn only
## where a chunky pixel is three screen pixels or more (the lower PIXELS
## settings); a line would eat too much of anything smaller.
var grid_mode := "lcd"
var grid_mat: ShaderMaterial
## what the grid is drawing now (0 off, 1 gaps, 2 LCD), for the tests
var grid_strength := 0.0

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
	grid_mat = ShaderMaterial.new()
	grid_mat.shader = preload("res://godot/shaders/pixel_grid.gdshader")
	rect.material = grid_mat
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
	gun_diag(gun_depth, gun_tone, gun_clear, gun_hdr)

## THE PICTURE NEVER STRETCHES BY A FRACTION, at the user's request
## ("only mathematically acceptable ratios that won't result in
## distortion"): every chunky pixel is a whole number of the SCREEN's
## own pixels across and down, so no column or row comes out wider than
## its neighbours. The scale is picked in physical pixels (the window is
## stretched as canvas items, so the canvas's units are not the screen's):
## the whole number that brings the grid's rows nearest PIXELS — 360 rows
## asked for is 360 on a 1080 screen (x3), 360 on a 720 one (x2), 360 on
## a 1440 one (x4). The columns are as many whole pixels as fit at that
## scale; what is left over (less than one chunky pixel each way) is a
## black border, centred. A non-square PIXEL ASPECT is a whole number of
## screen pixels across too, the nearest to the asked ratio. The world is
## then drawn RENDER rows (360 by default, never more than the screen's
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
	_grid(Vector2(sx, sy), grid)

## The grid for this many screen pixels a chunky pixel: 0 off, 1 the
## gaps alone, 2 the LCD panel.
func _grid(cell: Vector2, grid: Vector2i) -> void:
	var small := minf(cell.x, cell.y)
	var m := 0
	match grid_mode:
		"off": m = 0
		"lines", "soft": m = 1 if small >= 3.0 else 0
		_: m = 2 if small >= 3.0 else 0     # "lcd" (and an old "auto")
	if pixel_rows <= 0:
		m = 0
	grid_strength = float(m)
	grid_mat.set_shader_parameter("cells", Vector2(grid))
	grid_mat.set_shader_parameter("cell_px", cell)
	grid_mat.set_shader_parameter("mode", m)

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

## the screen swimming and the colours spinning, 0..1 (lofi.gdshader
## `wobble`: a unicorn's beam in the eye)
var _wob := 0.0
func set_wobble(k: float) -> void:
	if k <= 0.0 and _wob <= 0.0:
		return
	_wob = k
	mat.set_shader_parameter("wobble", U.col(k))
	mat.set_shader_parameter("now", U.col(fmod(Time.get_ticks_msec() / 1000.0, 1000.0)))

func set_tint(c: Color) -> void:
	mat.set_shader_parameter("tint", U.col(Vector3(c.r, c.g, c.b)))

## THE TITLE'S LOOK (lofi.gdshader, at the user's request): the picture in
## black and white, 0..1 ...
func set_mono(k: float) -> void:
	mat.set_shader_parameter("mono", U.col(clampf(k, 0.0, 1.0)))

## ... and film grain under the filter, how strong (0 none)
func set_grain(k: float) -> void:
	mat.set_shader_parameter("grain", U.col(maxf(k, 0.0)))

# ---- the gun's black squares (above) -----------------------------------------

## whether this is an Adreno (Qualcomm's GPU)
static func is_adreno() -> bool:
	return RenderingServer.get_video_adapter_name().containsn("adreno")

## The four switches at once (DEPTH, TONEMAP, CLEAR, HDR: above).
func gun_diag(depth: String, tone: String, clear: String, hdr: bool) -> void:
	# (anything not known — a settings file edited by hand — is the fix)
	gun_depth = depth if depth in ["shader", "fixed", "nodiscard"] else "shader"
	gun_tone = tone if tone in ["auto", "pass", "subpass"] else "auto"
	gun_clear = clear if clear in ["grey", "magenta"] else "grey"
	gun_hdr = hdr
	apply_gun_depth()
	set_gun_tonemap(gun_tone == "pass" or (gun_tone == "auto" and is_adreno()))
	var w := gun.find_world_3d()
	if w != null:
		if gun_clear == "magenta":
			if _gun_magenta == null:
				_gun_magenta = Environment.new()
				_gun_magenta.background_mode = Environment.BG_COLOR
				_gun_magenta.background_color = Color(1, 0, 1)
			if w.environment != _gun_magenta:
				_gun_env_was = w.environment
			w.environment = _gun_magenta
		elif _gun_magenta != null and w.environment == _gun_magenta:
			w.environment = _gun_env_was
			_gun_env_was = null
	if hdr:
		U.raw_out(gun)
	else:
		gun.use_hdr_2d = false

## Every material of the gun's world on its depth switch: the shipped
## shaders (they write their own depth) for "shader", or a copy of each
## compiled with MEWD_FIXED_DEPTH (and MEWD_NO_DISCARD) for the others.
## Run again whenever guns are built (Main.apply_prefs, after the level's).
func apply_gun_depth() -> void:
	var defs: Array = {"fixed": ["MEWD_FIXED_DEPTH"], "nodiscard": ["MEWD_FIXED_DEPTH", "MEWD_NO_DISCARD"]}.get(gun_depth, [])
	for n in gun.find_children("*", "GeometryInstance3D", true, false):
		var mats := []
		var g := n as GeometryInstance3D
		if g.material_override != null:
			mats.append(g.material_override)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_surface_override_material(i))
				mats.append(mi.mesh.surface_get_material(i))
		for m in mats:
			if m is ShaderMaterial:
				_gun_variant(m, defs)

func _gun_variant(m: ShaderMaterial, defs: Array) -> void:
	var base: Shader = m.get_meta("mewd_base") if m.has_meta("mewd_base") else m.shader
	if base == null or not GUN_SHADERS.has(base.resource_path):
		return
	m.set_meta("mewd_base", base)
	if defs.is_empty():
		if m.shader != base:
			m.shader = base
		return
	var key := base.resource_path + "|" + ",".join(defs)
	if not _gun_variants.has(key):
		var head := "shader_type spatial;"
		for d in defs:
			head += "\n#define " + d
		var v := Shader.new()
		v.code = base.code.replace("shader_type spatial;", head)
		_gun_variants[key] = v
	if m.shader != _gun_variants[key]:
		m.shader = _gun_variants[key]

## The gun's frame tonemapped in a pass of its own (an empty compositor
## effect after the transparent pass turns the 3D pass's tonemap subpass
## off), or in the 3D pass as Godot does by default.
func set_gun_tonemap(separate: bool) -> void:
	gun_tone_pass = separate and gun_on_room
	if not gun_on_room:
		return
	var w := gun.find_world_3d()
	if w == null:
		return
	if separate and gun_comp == null:
		gun_comp = Compositor.new()
		var fx := CompositorEffect.new()
		fx.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
		fx.enabled = true
		var list: Array[CompositorEffect] = [fx]
		gun_comp.compositor_effects = list
	RenderingServer.scenario_set_compositor(w.scenario, gun_comp.get_rid() if separate else RID())

## what the gun's switches are, for the PERF readout (the tonemap as set:
## a gun with glass — POTATO, PLASMA — reads the screen, which puts its
## tonemap in a pass of its own whatever the switch says)
func gun_state() -> String:
	if not gun_on_room:
		return "gun: compat (no room pass; the switches do nothing here)"
	var d: String = {"shader": "own depth", "fixed": "gpu depth", "nodiscard": "gpu depth, no discard"}.get(gun_depth, gun_depth)
	return "gun %s · tonemap %s%s%s%s" % [d, "pass" if gun_tone_pass else "subpass",
		" (auto)" if gun_tone == "auto" else "", " · magenta" if gun_clear == "magenta" else "", "" if gun_hdr else " · 8-bit"]

## the filter on or off: off, the buffer is shown as it is
var _snap := 1.0
func set_filtered(on: bool) -> void:
	_snap = 1.0 if on else 0.0
	mat.set_shader_parameter("snap", U.col(_snap))
	mat.set_shader_parameter("dither", U.col(1.0 if on else 0.0))
