## MEWD — the thermal sight on the side of the quad launcher (js/thermal.js).
##
## THE SAME METHOD AS THE LANCE'S SCREEN, at the user's request: "use same
## method as sniper rifle display to put a thermal scope live view on a
## plane in the scope". So this IS a Scope (render/scope.gd), by
## inheritance — a second render of the one world through a narrower
## camera, small and every other frame, the gauges a Control in a
## SubViewport of their own — and what is different is three things.
##
## THE PLANE. The launcher's file, the XM222, has a display surface on the
## back of its sight under a material of its own, `dyanmic_display_surface_mat`
## (the file's spelling), so it is named by `display` in Weapon3D.GUNS,
## wears this scope's screen and is measured and mapped as the lance's is.
##
## THE PICTURE IS HEAT, NOT LIGHT. In the feed every wall, floor, tree,
## car, puff and person answers how WARM it is instead of what colour it
## is (godot/shaders/thermal.gdshaderinc): the night in a narrow cold band,
## people warm whatever they wear, engines warm when they run, fire white,
## the sky black, a frozen shopper colder than the pavement. The web build
## turns a shared uniform on around the one render call; Godot uploads its
## globals once a frame for every viewport alike, so here the world's
## shaders ask instead whether the viewport they are drawing is THIS one —
## the feed is a size nothing else is, and `thermal_view` says which size
## while the sight is held. The SKY is this camera's own Environment, a
## plain near-black (js/sky.js: a clear night is a hole into space), and
## the world's lock brackets are on a layer this camera does not draw (a
## bracket in the feed would be a hot square; the glass draws its own).
## What is warm is decided by MissileSystem.is_hot — the same question the
## seeker asks — so the screen glows on what the launcher can lock.
##
## The screen (thermal_screen.gdshader) runs the number up IRONBOW, and the
## glass says what the seeker is doing: the seeker circle at its true size
## for the magnification, a bracket on every lock (a pip per extra lock)
## and a white one closing in, blinking, on whatever is being acquired;
## four tube pips; the number of locks, big, at the top; and the zoom.
class_name ThermalScope
extends Scope

## THE GLASS IS VERY NEARLY SQUARE: 0.728 across and 0.741 up of the
## model's own units
const ASPECT := 0.98
## rows of feed; the columns are that times the aspect — and the size of
## the feed is what tells the world's shaders it is the thermal one, so
## nothing else in the game may be 172 x 176
const ROWS := 176
const PANEL_ROWS := 256
## more magnification than the lance: a circle six degrees across over a
## van at the far end of the street
const THERMAL_ZOOMS := [1.0, 2.5, 4.0]
const THERMAL_VIEW_ZOOM := [1.0, 0.90, 0.82]
const THERMAL_AIM_AT := [0.0, 0.84, 1.0]
## what a running engine is worth, by the vehicle's state (js/thermal.js ENGINE)
const ENGINE := {"driving": 0.78, "charring": 0.58}
## the sky through the sight: the coldest thing there is
const SKY_HEAT := 0.022

## the symbology: a cold green-white that no stop of ironbow is, the
## seeker's amber for what is locked, white for what is being taken
const T_INK := Color(176 / 255.0, 1.0, 214 / 255.0, 0.94)
const T_INK_DIM := Color(176 / 255.0, 1.0, 214 / 255.0, 0.40)
const T_LOCK := Color(1.0, 206 / 255.0, 72 / 255.0, 0.98)
const T_TAKE := Color(1.0, 1.0, 1.0, 0.96)

## the Game, for its heat sources and its seeker; with none the feed is
## still thermal and the glass is only the circle and the pips
var game = null
## GREEN: the potato cannon's sight (game/potatoes.gd) — the same heat,
## run up a night-vision green instead of ironbow, and a plain reticle
## with a range readout instead of the seeker's circle, brackets and tubes
var green := false
## the one sight whose heat the world is drawing (two may exist; one is
## held at a time), and what the world was last told
static var _holder: ThermalScope = null
static var _told := Vector2(-1, -1)
var _view_set := Vector2(-1, -1)
var _warmth := {}
## what the glass was last asked to show
var tst := {"marks": [], "loaded": 0, "locks": 0, "take": 0.0, "salvo": 0}

func _init(g = null, is_green := false) -> void:
	super({"size": ROWS, "aspect": ASPECT, "zooms": THERMAL_ZOOMS,
		"view_zooms": THERMAL_VIEW_ZOOM, "aim_at": THERMAL_AIM_AT})
	name = "GreenThermalScope" if is_green else "ThermalScope"
	green = is_green
	# the cannon's sight is raised to the eye whole at every step
	if green:
		aim_at = [0.0, 1.0, 1.0]
	game = g
	feed.name = "ThermalFeed"
	# the brackets the world draws over the locks are not seen by the sensor
	camera.cull_mask = camera.cull_mask & ~MissileSystem.RETICLE_LAYER
	# and the sky is cold: this camera's own background, nothing else's
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(SKY_HEAT, SKY_HEAT, SKY_HEAT)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment = env

func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("thermal_view", Vector2.ZERO)
	_view_set = Vector2.ZERO
	_told = Vector2.ZERO
	if _holder == self:
		_holder = null

## WHETHER A SUBVIEWPORT HOLDS WHAT THE SHADER WROTE: the Compatibility
## renderer (no RenderingDevice) does, Forward+ sRGB-encodes on the way in
static func raw_targets() -> bool:
	return RenderingServer.get_rendering_device() == null

## the feed's size, which is what the world's shaders compare VIEWPORT_SIZE to
func feed_size() -> Vector2:
	return Vector2(feed.size)

## The screen, in heat. One per game, for the one launcher.
func screen_material() -> ShaderMaterial:
	if screen == null:
		screen = ShaderMaterial.new()
		screen.shader = preload("res://godot/shaders/thermal_screen.gdshader")
		screen.set_shader_parameter("feed", feed.get_texture())
		screen.set_shader_parameter("panel", panel.get_texture())
		screen.set_shader_parameter("raw", raw_targets())
		screen.set_shader_parameter("green", green)
	return screen

# ------------------------------------------------------------------
# One feed frame, in heat
# ------------------------------------------------------------------

## As Scope.render, and while the sight is held the world is told which
## viewport is the thermal one; on the frames a feed is drawn, the engines
## and the fire nearest the player are handed to the shaders for it.
func render(world_camera: Camera3D) -> bool:
	# the world draws heat for the feed of whichever sight is held; one
	# put down gives it up only if it was the one holding it
	if held:
		_holder = self
	elif _holder == self:
		_holder = null
	var want := feed_size() if _holder != null else Vector2.ZERO
	if want != _told:
		_told = want
		RenderingServer.global_shader_parameter_set("thermal_view", want)
		RenderingServer.global_shader_parameter_set("thermal_raw", 1.0 if raw_targets() else 0.0)
	var drew := super.render(world_camera)
	if drew:
		_heat()
	return drew

## The engines (per vehicle material, read only by the feed) and the fire.
func _heat() -> void:
	if game == null:
		return
	var M = game.get("missiles")
	var V = game.get("vehicles")
	if V != null:
		for v in V.all:
			var w := 0.0
			if M != null and M.is_hot(v):
				w = float(ENGINE.get(v.state, ENGINE.charring))
			if float(_warmth.get(v, -1.0)) == w:
				continue
			_warmth[v] = w
			for m in v.mats:
				if m is ShaderMaterial:
					m.set_shader_parameter("warmth", w)

# ------------------------------------------------------------------
# The glass
# ------------------------------------------------------------------

func update(p, t: int) -> bool:
	tics = t
	if screen != null:
		screen.set_shader_parameter("tics", float(t))
		screen.set_shader_parameter("on", 1.0 if held else 0.0)
		# THE MOTOR BLINDS IT while a missile leaves the tube
		var launching: bool = p != null and p.weapon == ("POTATO" if green else "LAUNCHER") and p.firing()
		screen.set_shader_parameter("noise", 0.8 if launching else 0.0)
	var M = game.get("missiles") if game != null and not green else null
	var marks := _marks(M)
	var loaded := 0
	if p != null:
		loaded = clampi(int(p.ammo.get("potatoes" if green else "rockets", 0)), 0, 6 if green else 4)
	# the green sight's range: to whatever is down the middle of it
	var rng := 0
	if green and p != null and held and game != null:
		var tr: Dictionary = game.trace(p, p.angle, p.pitch, 8000.0)
		rng = roundi(Vector2(tr.x - p.x, tr.y - p.y).length() / 32.0)
	var locks: int = M.locks.size() if M != null else 0
	var take: float = M.acquire_fraction() if M != null and M.acquiring != null else 0.0
	var salvo: int = M.salvo_left() if M != null else 0
	var mk := PackedStringArray()
	for m in marks:
		mk.append("%d,%d,%d,%d" % [int(m.x) >> 1, int(m.y) >> 1, m.n, int(m.r) >> 1])
	# (the camera's field of view too: the circle is drawn off it, and it
	# lags the zoom by up to a feed frame)
	var key := "%d|%d|%d|%d|%d|%d|%d|%d|%s|%d" % [1 if held else 0, zoom_index, roundi(camera.fov * 10.0), loaded, locks,
		roundi(take * 12.0), (t >> 1) & 1 if take > 0.0 else 0, salvo, ";".join(mk), rng]
	if key == _key:
		return false
	_key = key
	draws += 1
	tst = {"marks": marks, "loaded": loaded, "locks": locks, "take": take, "salvo": salvo, "range": rng}
	gauges.queue_redraw()
	panel.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

## Where each locked target, and the one being acquired, is on the glass —
## through the camera the feed was last drawn with, so a bracket sits on
## the picture it was drawn over. In the panel's pixels.
func _marks(M) -> Array:
	var out := []
	if M == null or not held or not camera.is_inside_tree():
		return out
	var seen := {}
	var order := []
	for l in M.locks:
		if not seen.has(l.t):
			seen[l.t] = 0
			order.append(l.t)
		seen[l.t] += 1
	if M.acquiring != null and not seen.has(M.acquiring):
		seen[M.acquiring] = 0
		order.append(M.acquiring)
	var W := float(panel.size.x)
	var H := float(panel.size.y)
	var fs := feed_size()
	var tan_half := tan(deg_to_rad(camera.fov) / 2.0)
	for t in order:
		var hp: Vector3 = M.heat_point(t)
		var at := U.v3(hp.x, hp.y, hp.z)
		if camera.is_position_behind(at):
			continue
		var sp := camera.unproject_position(at)
		var nx := sp.x / fs.x * 2.0 - 1.0
		var ny := sp.y / fs.y * 2.0 - 1.0
		if absf(nx) > 1.2 or absf(ny) > 1.2:
			continue
		# and how big the thing is on the glass, off its own size
		var size: float = float(t.radius) * 1.6 if "radius" in t else 90.0
		var d := maxf(1.0, at.distance_to(camera.global_position))
		var r := clampf(size / d / tan_half * H / 2.0, 9.0, H * 0.3)
		out.append({"x": roundi((nx + 1.0) / 2.0 * W), "y": roundi((ny + 1.0) / 2.0 * H), "n": int(seen[t]), "r": roundi(r)})
	return out

func _draw_panel(c: Control) -> void:
	if not held:
		return
	if green:
		_draw_green(c)
		return
	var W := c.size.x
	var H := c.size.y
	var cx := W / 2.0
	var cy := H / 2.0
	var loaded: int = tst.loaded
	var locks: int = tst.locks
	var take: float = tst.take
	var salvo: int = tst.salvo
	var t := tics
	# ---- THE SEEKER CIRCLE, at the size the cone really is, in dashes so
	# it reads as a sight and not a lens
	var rc := tan(float(MissileSystem.SEEKER.cone)) / tan(deg_to_rad(camera.fov) / 2.0) * (H / 2.0)
	var ring := T_LOCK if loaded > 0 and locks >= mini(4, loaded) else T_INK
	for k in 16:
		var a0 := float(k) / 16.0 * TAU
		c.draw_arc(Vector2(cx, cy), rc, a0, a0 + TAU / 16.0 * 0.6, 6, ring, 2.2)
	# and a small cross in the middle of it
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		c.draw_line(Vector2(cx, cy) + d * H * 0.02, Vector2(cx, cy) + d * H * 0.06, ring, 2.2)
	# ---- THE BRACKETS: amber on a lock, white closing in on a take
	for m in tst.marks:
		var n: int = m.n
		if n == 0 and ((t >> 1) & 1) == 1:
			continue
		var r: float = float(m.r) if n > 0 else float(m.r) * (2.2 - 1.2 * take)
		var col := T_LOCK if n > 0 else T_TAKE
		var wdt := 3.0 if n > 0 else 2.0
		var arm := r * 0.55
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var p := Vector2(m.x + s.x * r, m.y + s.y * r)
			c.draw_line(p - Vector2(s.x * arm, 0), p, col, wdt)
			c.draw_line(p, p - Vector2(0, s.y * arm), col, wdt)
		# a pip in a corner for every lock past the first
		for k in range(1, n):
			c.draw_rect(Rect2(m.x - r + 3 + (k - 1) * 7, m.y - r + 3, 5, 5), T_LOCK)
	# ---- THE FOUR TUBES: loaded and spoken for, loaded, or empty — in the
	# order they fire
	for i in 4:
		var x := cx + (i - 1.5) * H * 0.11
		var y := H * 0.88
		var s := H * 0.035
		var has := i >= 4 - loaded
		var claimed := has and (i - (4 - loaded)) < locks
		var rect := Rect2(x - s, y - s, s * 2.0, s * 2.0)
		if has:
			c.draw_rect(rect, T_LOCK if claimed else T_INK)
		else:
			c.draw_rect(rect, T_INK_DIM, false, 2.0)
	# ---- AND THE ONE CHARACTER — a triangle while a salvo leaves, the
	# number of locks, or a dot — and the zoom
	var ly := H * 0.13
	if salvo > 0:
		var z := H * 0.05
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx, ly - z), Vector2(cx + z, ly + z * 0.8), Vector2(cx - z, ly + z * 0.8)]), T_LOCK)
	elif locks > 0:
		_label(c, str(locks), cx, ly, H * 0.13, T_LOCK)
	else:
		c.draw_circle(Vector2(cx, ly), H * 0.012, T_INK_DIM)
	_label(c, "%sx" % str(magnification()), W * 0.86, H * 0.88, H * 0.075, T_INK if zoom_index > 0 else T_INK_DIM)

## THE POTATO CANNON'S GLASS: a plain cross with a gap in the middle and
## ticks down the lower arm for the lob, the range in metres (32 units),
## the hopper's potatoes as six pips, and the zoom
const G_INK := Color(0.72, 1.0, 0.62, 0.95)
const G_DIM := Color(0.72, 1.0, 0.62, 0.40)

func _draw_green(c: Control) -> void:
	var W := c.size.x
	var H := c.size.y
	var cx := W / 2.0
	var cy := H / 2.0
	var gap := H * 0.035
	var arm := H * 0.30
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]:
		c.draw_line(Vector2(cx, cy) + d * gap, Vector2(cx, cy) + d * arm, G_INK, 2.0)
	c.draw_line(Vector2(cx, cy + gap), Vector2(cx, cy + arm), G_INK, 2.0)
	# the lob: a tick every so far down, longer every other
	for k in range(1, 6):
		var y := cy + gap + k * (arm - gap) / 6.0
		var w := H * (0.045 if k % 2 == 0 else 0.025)
		c.draw_line(Vector2(cx - w, y), Vector2(cx + w, y), G_INK, 1.6)
	c.draw_circle(Vector2(cx, cy), H * 0.008, G_INK)
	_label(c, "%dm" % int(tst.get("range", 0)), cx, H * 0.12, H * 0.085, G_INK)
	var loaded: int = tst.loaded
	for i in 6:
		var x := cx + (i - 2.5) * H * 0.075
		var y := H * 0.88
		var s := H * 0.022
		if i < loaded:
			c.draw_circle(Vector2(x, y), s, G_INK)
		else:
			c.draw_arc(Vector2(x, y), s, 0.0, TAU, 12, G_DIM, 1.6)
	_label(c, "%sx" % str(magnification()), W * 0.86, H * 0.88, H * 0.075, G_INK if zoom_index > 0 else G_DIM)

