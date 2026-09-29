## MEWD — the screen on the back of the gun (js/scope.js).
##
## THE LANCE CAME WITH A SCREEN IN IT. The model the user brought in —
## Vaportrash's WZBR-1 Positron Sniper Lance — has a node named
## `dynamic_display_surface_1`, an eighty-millimetre panel on the rear
## deck facing straight back at whoever holds it, and `optics_2`, a green
## lens up front. Everything below is what that node is for.
##
## WHAT IS ON IT: the world, live, through a second camera at the
## player's own eye with a narrow field of view — a camera-to-texture
## feed, not a painted picture — with round gauges over it for the
## charge, the hold and the cell, and a reticle. A sniper scope that
## happens to be a monitor.
##
## THE FEED IS ITS OWN RENDER: a zoomed picture is a DIFFERENT picture,
## not a crop. So this owns a SubViewport with a Camera3D in it, parked
## at the world camera's place with its field of view divided by the
## magnification. THE SAME SCENE, WHICH IS THE WHOLE TRICK: this node
## lives under the Game, inside the world's own SubViewport, and a
## SubViewport that does not own a world draws its parent's — nothing is
## duplicated and nothing is kept in sync. SMALL AND SLOW ON PURPOSE:
## SIZE texels square, at most every EVERY-th frame, because at arm's
## length the panel is forty chunky pixels once the lo-fi pass has had it.
##
## THE GAUGES are a Control drawn into a SubViewport of their own (the
## web build's canvas), redrawn only when a number on them has moved, in
## the lens's own green.
##
## THE ZOOM IS NOT A ZOOM, IT IS PUTTING YOUR EYE TO THE SCOPE, at the
## user's request: a press (ZOOM: the right button, Z or C) brings the gun
## up and back until the panel fills the middle of the frame — the `aim`
## hold in Weapon3D.GUNS, blended to by aim() — while the world behind it
## barely narrows (view_scale) and the feed barely magnifies.
##
## GENERAL ON PURPOSE: the steps, the aspect and the drawing of the panel
## are the scope's own, so a second gun with a screen (the launcher's
## thermal sight) can be a Scope with its own rows and its own
## _draw_panel. Weapon3D asks any scope only for screen_material(),
## optics_material(base), set_panel_box(min, size) and aim().
class_name Scope
extends Node

## The feed, in texels: square because the panel is (80.3mm by 77.7mm).
const SIZE := 256
## and the gauges over it, at the same size for the same reason
const PANEL := 256
## ONE FEED FRAME IN EVERY THIS MANY: a second whole scene render is the
## most expensive thing on this screen and the cheapest thing to halve
const EVERY := 2
## THE MAGNIFICATIONS ARE SMALL: enough that the panel is worth looking
## at, nowhere near the twelve that made it a separate game
const ZOOMS := [1.0, 2.1, 3.4]
## AND THE WORLD BEHIND IT HARDLY MOVES: just enough to say the player
## has stopped walking and started aiming. The look slows by the same.
const VIEW_ZOOM := [1.0, 0.90, 0.84]
## HOW FAR THE GUN IS TO THE SHOULDER at each step, 0 at the hip and 1
## with your eye on the glass
const AIM_AT := [0.0, 0.82, 1.0]
## The phosphor: the lens's own base colour, and the screen is that.
const PHOSPHOR := Vector3(0.42, 1.0, 0.36)
const INK := Color(150 / 255.0, 1.0, 138 / 255.0, 0.92)
const INK_DIM := Color(150 / 255.0, 1.0, 138 / 255.0, 0.42)
const WARN := Color(1.0, 196 / 255.0, 72 / 255.0, 0.95)
const HOT := Color(1.0, 96 / 255.0, 56 / 255.0, 0.96)
const TRACK := Color(150 / 255.0, 1.0, 138 / 255.0, 0.14)

var size := SIZE
var every := EVERY
var zooms: Array = ZOOMS
var view_zooms: Array = VIEW_ZOOM
var aim_at: Array = AIM_AT
var aspect := 1.0
var frames := 0
var renders := 0          ## how many feed frames have actually been drawn
var draws := 0            ## how many times the gauges have been redrawn
var zoom_index := 0
var last_aimed := 0       ## the step AIM goes back up to — see toggle_aim
var held := false         ## is the gun in hand at all
var tics := 0
var stage_marks: Array = [3.0 / 7.0, 5.0 / 7.0, 1.0]

var feed: SubViewport
var camera: Camera3D
var panel: SubViewport
var gauges: Control
var screen: ShaderMaterial
var optic: ShaderMaterial
var _key := ""
## what the gauges were last asked to show
var st := {"charge": 0.0, "hold": 0.0, "stage": 0, "cell": 0.0, "firing": false, "tics": 0}

## opts: size, every, zooms, view_zooms, aim_at, aspect
func _init(opts := {}) -> void:
	name = "Scope"
	size = int(opts.get("size", SIZE))
	every = maxi(1, int(opts.get("every", EVERY)))
	zooms = opts.get("zooms", ZOOMS)
	view_zooms = opts.get("view_zooms", VIEW_ZOOM)
	aim_at = opts.get("aim_at", AIM_AT)
	aspect = float(opts.get("aspect", 1.0))
	var px := Vector2i(roundi(size * aspect), size)
	# the feed: a target and a camera to fill it, drawing the world this
	# node is in
	feed = SubViewport.new()
	feed.name = "Feed"
	feed.size = px
	feed.msaa_3d = Viewport.MSAA_DISABLED
	feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(feed)
	camera = Camera3D.new()
	camera.current = true
	camera.near = 2.0
	camera.far = 16000.0
	feed.add_child(camera)
	# the gauges: a Control in a transparent 2D target
	panel = SubViewport.new()
	panel.name = "Gauges"
	panel.size = Vector2i(roundi(PANEL * aspect), PANEL)
	panel.disable_3d = true
	panel.transparent_bg = true
	panel.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(panel)
	gauges = _Gauges.new()
	gauges.scope = self
	gauges.size = Vector2(panel.size)
	panel.add_child(gauges)

## draws the scope's panel, whatever the scope says is on it
class _Gauges extends Control:
	var scope
	func _draw() -> void:
		scope._draw_panel(self)

func magnification() -> float:
	return float(zooms[zoom_index]) if zoom_index < zooms.size() else 1.0

## How far the weapon is raised toward the eye at this step — what
## Weapon3D blends its second hold by.
func aim() -> float:
	return float(aim_at[zoom_index]) if zoom_index < aim_at.size() else 0.0

## What the WORLD camera's field of view (and the look) should be
## multiplied by while the scope is at this step.
func view_scale() -> float:
	return float(view_zooms[zoom_index]) if zoom_index < view_zooms.size() else 1.0

func zoomed() -> bool:
	return zoom_index > 0

func set_zoom(i: int) -> void:
	zoom_index = clampi(i, 0, zooms.size() - 1)
	if zoom_index > 0:
		last_aimed = zoom_index

## Z, C, the right button: hip, up, further, hip.
func cycle_zoom() -> void:
	set_zoom((zoom_index + 1) % zooms.size())

## THE PHONE'S AIM BUTTON: up to the eye or back to the hip; up is the
## step it was last at while up, so lowering it to walk does not lose the
## magnification the player chose.
func toggle_aim() -> void:
	set_zoom(0 if zoom_index > 0 else maxi(1, last_aimed))

## and its magnification button, only on the glass while the gun is up:
## the next aimed step, round to the first, never down to the hip
func step_aimed() -> void:
	var n := zooms.size()
	if n < 2:
		return
	set_zoom(1 + zoom_index % (n - 1) if zoom_index > 0 else maxi(1, last_aimed))

## One press: "aim", "step" or "cycle".
func work(press: String) -> void:
	match press:
		"aim":
			toggle_aim()
		"step":
			step_aimed()
		"cycle":
			cycle_zoom()

# ------------------------------------------------------------------
# The two materials the model's two untextured meshes wear
# ------------------------------------------------------------------

## The screen. One per scope: one gun, one panel on it.
func screen_material() -> ShaderMaterial:
	if screen == null:
		screen = ShaderMaterial.new()
		screen.shader = preload("res://godot/shaders/scope_screen.gdshader")
		screen.set_shader_parameter("feed", feed.get_texture())
		screen.set_shader_parameter("panel", panel.get_texture())
		screen.set_shader_parameter("has_panel", true)
		screen.set_shader_parameter("tint", PHOSPHOR)
	return screen

## The lens.
func optics_material(base := [0.34, 0.80, 0.0]) -> ShaderMaterial:
	if optic == null:
		optic = ShaderMaterial.new()
		optic.shader = preload("res://godot/shaders/scope_optic.gdshader")
		optic.set_shader_parameter("base", Vector3(base[0], base[1], base[2]))
	return optic

## The panel's own bounding box in the mesh's units, measured off the
## geometry at load time, so a re-export that moves the panel moves the
## picture with it. `mn` and `sz` are x, y.
func set_panel_box(mn: Vector2, sz: Vector2) -> void:
	screen_material().set_shader_parameter("box", Vector4(mn.x, mn.y, 1.0 / maxf(sz.x, 1e-6), 1.0 / maxf(sz.y, 1e-6)))

## Where the three stage marks fall on the charge ring, set once by
## whoever owns the numbers (Player.stage_marks), so they cannot disagree.
func set_stages(marks: Array) -> void:
	stage_marks = marks

# ------------------------------------------------------------------
# One feed frame
# ------------------------------------------------------------------

## Once a frame: park the narrow camera where the world's is and ask for
## a feed frame, one in every `every`. THE MAGNIFICATION IS OFF THE
## WORLD'S OWN FIELD OF VIEW, which is already narrowed by view_scale, so
## the two do not multiply twice. Returns whether a frame was asked for.
func render(world_camera: Camera3D) -> bool:
	frames += 1
	if not held or world_camera == null:
		feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return false
	if frames % every != 0:
		return false
	camera.global_transform = world_camera.global_transform
	camera.near = world_camera.near
	camera.far = world_camera.far
	camera.fov = maxf(1.2, world_camera.fov / magnification() * view_scale())
	feed.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1
	return true

# ------------------------------------------------------------------
# The gauges
# ------------------------------------------------------------------

## Push the live numbers into the screen and the lens, and redraw the
## gauges if anything on them has moved. `p` is the player, or null.
func update(p, t: int) -> bool:
	tics = t
	var firing: bool = p != null and p.beam_tics > 0
	var charge: float = p.charge_fraction() if p != null else 0.0
	if screen != null:
		screen.set_shader_parameter("tics", float(t))
		screen.set_shader_parameter("on", 1.0 if held else 0.0)
		# A HARD BURST OF STATIC WHILE THE BEAM IS OUT, and nothing the rest
		# of the time: a scope you cannot read between shots is not a scope
		screen.set_shader_parameter("noise", 0.52 if firing else 0.0)
	if optic != null:
		optic.set_shader_parameter("tics", float(t))
		optic.set_shader_parameter("charge", maxf(charge, 1.0 if firing else 0.0))
	var stage: int = p.charge_stage() if p != null else 0
	var cell := 0.0
	if p != null:
		cell = clampf(float(p.ammo.get("cells", 0)) / float(Weapons.TANKS.cells[0]), 0.0, 1.0)
	var hold: float = p.hold_fraction() if p != null else 0.0
	# THE DIRTY KEY, and everything in it is something that is DRAWN
	var key := "%d|%d|%d|%d|%d|%d|%d|%d|%d" % [1 if held else 0, roundi(charge * 120.0), roundi(hold * 90.0), stage,
		roundi(cell * 60.0), zoom_index, 1 if firing else 0, (t >> 1) & 7 if firing else 0,
		(t >> 2) & 1 if hold > 0.0 and hold < 0.25 else 0]
	if key == _key:
		return false
	_key = key
	draws += 1
	st = {"charge": charge, "hold": hold, "stage": stage, "cell": cell, "firing": firing, "tics": t}
	gauges.queue_redraw()
	panel.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

## WHAT THE SCREEN LOOKS LIKE, laid out for the size it is ACTUALLY SEEN
## AT — forty chunky pixels — so it is FOUR THINGS, each of which
## survives that: the outer ring (the charge, three quarters of a turn,
## the stage marks cut through it), the inner ring (the window at the top
## of the charge, draining), four pips (the cell), the reticle; and one
## character, the stage. Everything inside the square bezel.
func _draw_panel(c: Control) -> void:
	if not held:
		return
	var N := c.size.y
	var cx := c.size.x / 2.0
	var cy := N / 2.0
	var stage: int = st.stage
	var firing: bool = st.firing
	var t: int = st.tics
	var stage_ink := HOT if stage >= 3 else (WARN if stage >= 2 else INK)
	# ---- THE CHARGE, the outer ring, from eight o'clock round to four
	var R := N * 0.372
	var W := N * 0.086
	var FROM := -0.375
	var SPAN := 0.75
	_dial(c, cx, cy, R, W, FROM, SPAN, st.charge, stage_ink if stage > 0 else INK, TRACK)
	# the stage marks, cut THROUGH the ring in the background colour so
	# they are gaps and not lines
	for at in stage_marks:
		if at >= 1.0:
			continue
		_tick(c, cx, cy, R, W, FROM + SPAN * at, Color(6 / 255.0, 18 / 255.0, 8 / 255.0, 0.95), 1.25)
	# ---- THE WINDOW, concentric inside it, draining while you line up
	var hold: float = st.hold
	if hold > 0.0:
		_dial(c, cx, cy, N * 0.268, N * 0.054, FROM, SPAN, hold,
			HOT if hold < 0.25 else (WARN if hold < 0.5 else INK), Color(TRACK, 0.10))
	# ---- THE CELL, four pips along the bottom
	var have := roundi(float(st.cell) * 4.0)
	for i in 4:
		var p := Vector2(cx + (i - 1.5) * N * 0.072, N * 0.845)
		c.draw_circle(p, N * 0.021, INK if i < have else Color(TRACK, 0.13))
		if i < have:
			c.draw_arc(p, N * 0.021, 0.0, TAU, 16, INK_DIM, 1.5)
	# ---- THE RETICLE
	var ink := HOT if firing else INK
	var g0 := N * 0.045
	var g1 := N * 0.125
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		c.draw_line(Vector2(cx, cy) + d * g0, Vector2(cx, cy) + d * g1, ink, 2.4)
	c.draw_rect(Rect2(cx - 1.5, cy - 1.5, 3, 3), ink)
	# a box round the middle while the beam is out, blinking
	if firing and ((t >> 2) & 1) == 1:
		c.draw_rect(Rect2(cx - N * 0.15, cy - N * 0.15, N * 0.30, N * 0.30), HOT, false, 3.0)
	# ---- AND THE ONE CHARACTER: a triangle while it fires, the stage, or
	# a dot
	var ly := N * 0.245
	if firing:
		var s := N * 0.05
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx, ly - s), Vector2(cx + s, ly + s * 0.8), Vector2(cx - s, ly + s * 0.8)]), HOT)
	elif stage > 0:
		_label(c, str(stage), cx, ly, N * 0.125, stage_ink)
	else:
		c.draw_circle(Vector2(cx, ly), N * 0.012, INK_DIM)
	_label(c, "%sx" % str(magnification()), cx, N * 0.675, N * 0.078, INK if zoom_index > 0 else INK_DIM)
	# ---- AND THE LAST SECOND OF THE WINDOW blinks the middle red
	if hold > 0.0 and hold < 0.25 and ((t >> 2) & 1) == 1:
		c.draw_rect(Rect2(cx - N * 0.022, cy - N * 0.022, N * 0.044, N * 0.044), HOT)

## An arc gauge: a dark track, a lit sweep over it, and a cap of glare at
## the head of the sweep. Angles in turns from twelve o'clock, clockwise.
static func _dial(c: Control, cx: float, cy: float, r: float, w: float, from: float, span: float, lit: float, colour: Color, track: Color) -> void:
	var a0 := -PI / 2.0 + from * TAU
	var a1 := a0 + span * TAU
	c.draw_arc(Vector2(cx, cy), r, a0, a1, 48, track, w)
	if lit <= 0.0:
		return
	var head := a0 + span * TAU * minf(1.0, lit)
	c.draw_arc(Vector2(cx, cy), r, a0, head, maxi(3, int(48 * minf(1.0, lit))), colour, w)
	# the glare at the head, which is what says it is filling now
	c.draw_arc(Vector2(cx, cy), r, maxf(a0, head - 0.16), head, 6, Color(colour, 0.28), w * 1.9)

## A tick across a dial's track, for a stage mark.
static func _tick(c: Control, cx: float, cy: float, r: float, w: float, at: float, colour: Color, len := 1.7) -> void:
	var a := -PI / 2.0 + at * TAU
	var u := Vector2(cos(a), sin(a))
	c.draw_line(Vector2(cx, cy) + u * (r - w * len / 2.0), Vector2(cx, cy) + u * (r + w * len / 2.0), colour, 2.0)

static func _label(c: Control, s: String, x: float, y: float, px: float, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var fs := roundi(px)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, Vector2(x - w / 2.0, y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, colour)
