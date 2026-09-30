## MEWD — the game (js/game.js and the frame loop in js/main.js).
##
## The simulation runs at Doom's 35 tics a second, at most six a frame,
## whatever the display does; the picture is drawn between the last two
## tics so a 144 Hz screen moves smoothly. The look is taken every frame
## (a mouse is not a 35 Hz device) and the legs every tic.
extends Node3D

const BASE_FOV := 72.0
## past this, an idle somebody thinks one tic in four (tic)
const LOD_FAR := 1200.0
const MOUSE_SENS := 0.0022
const MAX_TICS := 6

var doors: Doors = null
var nav: Nav = null
var potatoes: PotatoCannon = null
var level: Level
var bank: TexBank
var player: Player
## EVERYBODY WITH A PAIR OF HANDS IN THIS WORLD (js/game.js). One in a
## game on its own — `player`, the one this screen looks out of — and one
## a client on a host (godot/scripts/net/match.gd), each with its own
## session. A player with no session of its own is driven by the game's.
var players: Array = []
## where the player's command each tic comes from: this machine, until a
## network client (NetGame) says otherwise — see godot/scripts/net/session.gd
var session = NetSession.Local.new()
## AND THE RULES THAT HOLD BETWEEN THEM, when there is more than one: a
## match (NetMatch) on a host, NetGame.ClientRules on a client; none alone
var rules = null
## set by a host to wind the others back to what a shooter saw before its
## tic, and forward again after — see SimServer.rewind
var rewind := Callable()
## a network client's own side of the game (NetGame), or null
var net = null
## the map a host named ({kind, seed, opts}), built instead of the command line's
var net_map := {}
## ON A NETWORK CLIENT THE LOOK GOES DOWN THE WIRE: taken every frame as
## ever, but held here until the tic, which rounds it into the command
## (NetGame.Session) — the eye is drawn ahead of the body by what is held
var net_look := Vector2()
## the gun's own notices, and the big card (js/game.js toast, setBigMessage)
var toasts: Array = []
var big_message = null
var big_message_tics := 0
const TOAST_LIFE := 6 * 35
const TOAST_MAX := 4
var camera: Camera3D
var actors: Array = []
var blockmap := ActorGrid.new()
var standees: Standees
var forest: Forest
var forest_view: ForestView
var lamps: Lamps
var tics := 0
var kills := 0
var weather := Weather.new()
## the skybox's material, when the map wears one (_make_sky)
var skybox_mat: ShaderMaterial = null
var rain: Rain
## the systems the guns hand their work to, when they are ported
var flame: FlameStream
var frost: FrostStream
## the bore's sight and lock, which the player's trigger asks (Player.armed)
var bore: BoreSystem
## the quad launcher's seeker and its missiles
var missiles: MissileSystem
## the police and the army, and every vehicle (js/responders.js, vehicles.js)
var escalation: Escalation
var arc: ArcSystem
var tracers: Tracers
var decals: Decals
var gore_decals: GoreDecals
var fx: Effects
var giblets: Giblets
var beam: BeamSystem
var scope: Scope
## and the quad launcher's thermal sight (render/thermal.gd), the same kind of thing
var thermal: ThermalScope
## the potato cannon's thermal sight, in night-vision green
var green_thermal: ThermalScope
var _zoom := false
var hud: Hud
var weapon3d: Weapon3D
## the phone's controls, when there is a touch screen (Main sets it)
var touch: TouchControls
var sound: Sound
## where the last round stopped, for the tracer
var last_hit := Vector3()
var _slot := 0
## held still by the pause menu, and the menu's look settings
var paused := false
## which map: "maze" (the demo's), "jesse", "sprawl", "grid" or "layers"
var map_name := "maze"
## or a map from MEWD Editor's Play: the document itself (main.gd sets it)
var play_doc = null
var look_sens := 1.0
var invert := false
var _set_hour := 2.0
var _cycle := 0
var seed := 0
var _acc := 0.0
var _look := Vector2()
var _jump := false
## --shot=path.png [--shot-frames=N]: save the picture after N frames and
## quit — how the port is checked without a screen
var _shot := ""
var _shot_frames := 20
var _frames := 0
## test hooks: hold the trigger, start with a given gun
var _autofire := false
var _start_weapon := ""
## --zoom=N: the gun in hand's scope starts at step N (for pictures)
var _start_zoom := 0

func _ready() -> void:
	_bind_keys()
	seed = MazeMap.new_seed()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--shot-frames="):
			_shot_frames = int(a.substr(14))
		elif a.begins_with("--autofire"):
			_autofire = true
		elif a.begins_with("--weather="):
			weather.kind = a.substr(10)
		elif a.begins_with("--hour="):
			weather.hour = float(a.substr(7))
			_set_hour = weather.hour
		elif a.begins_with("--weapon="):
			_start_weapon = a.substr(9)
		elif a.begins_with("--zoom="):
			_start_zoom = int(a.substr(7))
	var which := map_name
	for a in args:
		if a.begins_with("--map="):
			which = a.substr(6)
	# A HOST'S MAP, on a network: its kind and its seed, which every client
	# builds for itself (the web build's netMap)
	var opts := {}
	if not net_map.is_empty():
		which = str(net_map.get("kind", "maze"))
		seed = int(net_map.get("seed", 1))
		if net_map.get("opts") is Dictionary:
			opts = net_map.opts
	# THE MAP (--map=maze|jesse|sprawl|grid): every map the web build plays
	var doc: Dictionary
	match which:
		"jesse": doc = JesseMap.build(seed, opts)
		"sprawl": doc = SprawlMap.build()
		"grid": doc = TheGrid.build()
		"layers": doc = LayersMap.build()
		_: doc = MazeMap.build(seed, int(opts.get("cells", MazeMap.CELLS)), int(opts.get("people", MazeMap.PEOPLE)))
	# A MAP FROM THE EDITOR, on a test run (js/main.js's PLAY_KEY): the
	# document it handed over, compiled by the same compiler
	if play_doc != null:
		doc = play_doc
	# a test hook: --at=x,y,degrees stands the START somewhere else (as a
	# map from the editor with its start moved would; for pictures)
	for a in args:
		if a.begins_with("--at="):
			var at := a.substr(5).split(",")
			for t in doc.things:
				if t.type == "START" and at.size() >= 3:
					t.x = float(at[0]); t.y = float(at[1]); t.angle = deg_to_rad(float(at[2]))
					# a fourth: the layer it stands on (a map in storeys)
					if at.size() >= 4:
						t["layer"] = int(at[3])
		# and --eye=rise,pitch lifts the eye off the body and tilts it
		if a.begins_with("--eye="):
			var e := a.substr(6).split(",")
			eye_hook = Vector2(float(e[0]), float(e[1]) if e.size() > 1 else 0.0)
	start_map(doc)

func start_map(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	level = DocCompile.compile(doc)
	forest = Forest.new(level)
	forest_view = ForestView.new(forest)
	add_child(forest_view)
	lamps = Lamps.new(level)
	add_child(lamps)
	bank = TexBank.new()
	var geo := MapGeo.new(bank).build(level)
	add_child(geo)
	# the way from room to room, for the troops (game/nav.gd)
	nav = Nav.new(level)
	# the doors (game/doors.gd), none on a map without
	doors = Doors.new(self) if not level.doors.is_empty() else null
	if doors != null:
		add_child(doors)
	_make_sky(str(level.world.get("skybox", "")))
	var start = null
	for t in level.things:
		if t.type == "START":
			start = t
			break
	if start == null:
		start = {"x": level.bounds.get_center().x, "y": level.bounds.get_center().y, "angle": 0.0}
	player = Player.new(self, float(start.x), float(start.y), float(start.angle), start.get("z"))
	# (a test run from the editor starts looking the way its camera did)
	player.pitch = clampf(float(start.get("pitch", 0.0)), -1.5, 1.5)
	players = [player]
	if _start_weapon != "":
		player.weapon = _start_weapon
	_spawn_things()
	escalation = Escalation.new(self)
	add_child(escalation)
	standees = Standees.new()
	add_child(standees)
	tracers = Tracers.new()
	add_child(tracers)
	flame = FlameStream.new(self)
	add_child(flame.particles)
	frost = FrostStream.new(self)
	add_child(frost.particles)
	rain = Rain.new(self)
	add_child(rain.pool)
	bore = BoreSystem.new(self)
	add_child(bore)
	missiles = MissileSystem.new(self)
	add_child(missiles)
	potatoes = PotatoCannon.new(self)
	add_child(potatoes)
	arc = ArcSystem.new(self)
	add_child(arc)
	decals = Decals.new()
	add_child(decals)
	gore_decals = GoreDecals.new(self)
	add_child(gore_decals)
	fx = Effects.new(self)
	add_child(fx)
	giblets = Giblets.new(self)
	add_child(giblets)
	beam = BeamSystem.new(self)
	add_child(beam)
	# under the Game, so the scope's feed draws this world
	scope = Scope.new()
	add_child(scope)
	scope.set_stages(player.stage_marks())
	if weapon3d != null:
		weapon3d.scopes["LANCE"] = scope
	thermal = ThermalScope.new(self)
	add_child(thermal)
	if weapon3d != null:
		weapon3d.scopes["LAUNCHER"] = thermal
	# and the potato cannon's, in green (render/thermal.gd `green`)
	green_thermal = ThermalScope.new(self, true)
	add_child(green_thermal)
	if weapon3d != null:
		weapon3d.scopes["POTATO"] = green_thermal
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 2.0
	camera.far = 16000.0
	add_child(camera)
	camera.make_current()
	print("MEWD: %s seed %d — %d sectors, %d lines, %d things, built in %d ms" % [
		level.name, seed, level.sectors.size(), level.lines.size(), level.things.size(), Time.get_ticks_msec() - t0])

## The sky: the map's skybox photograph if it names one (the air fading to
## its horizon), else the sky for the hour and the weather, worked out
## per pixel (godot/shaders/sky.gdshader, js/skyart.js) with the map's
## own colours over it (world.sky — the grid's green).
func _make_sky(name: String) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var path := "res://assets/skies/%s.png" % name
	if name != "" and name != "<null>" and ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		# the picture decoded to linear and shown so, with the map's fog
		# over it (godot/shaders/skybox.gdshader, js/sky.js)
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://godot/shaders/skybox.gdshader")
		sm.set_shader_parameter("panorama", tex)
		var ml: Dictionary = level.map_light
		var fog: Color = ml.get("fog", Color(0, 0, 0, 0))
		var amb: Color = ml.get("ambient", Color.BLACK)
		sm.set_shader_parameter("fog_default", Vector4(fog.r, fog.g, fog.b, fog.a))
		sm.set_shader_parameter("ambient", Vector3(amb.r, amb.g, amb.b))
		sm.set_shader_parameter("fog_ambient", float(ml.get("fogAmbient", 1.0)))
		sky.sky_material = sm
		skybox_mat = sm
		# the air fades to the sky's horizon texel (worldShade's `air`): the
		# row just over the middle, decoded to linear as the web build's
		# fetch is — averaged round the horizon, where the web build takes
		# the texel in each fragment's own azimuth
		var img := tex.get_image()
		if img:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			var c := Color()
			var h := maxi(0, img.get_height() / 2 - 1)
			for i in 64:
				c += img.get_pixel(i * img.get_width() / 64, h).srgb_to_linear()
			RenderingServer.global_shader_parameter_set("air_color", c / 64.0)
		# and the level's own surfaces take it in their own azimuth
		# (world_air_at in world_light.gdshaderinc)
		RenderingServer.global_shader_parameter_set("air_sky", tex)
		RenderingServer.global_shader_parameter_set("air_sky_on", 1.0)
	else:
		var sm := ShaderMaterial.new()
		RenderingServer.global_shader_parameter_set("air_sky_on", 0.0)
		sm.shader = preload("res://godot/shaders/sky.gdshader")
		sky.sky_material = sm
		weather.sky_mat = sm
		# the web build's sky for a map without a skybox (js/main.js): the
		# grid's green, with the map's own colours over it, and whatever
		# those say, BARE — no stars, no moon, no cloud, no town glow
		var skin: Dictionary = {"horizon": "#1d9a48", "mid": "#06301a", "zenith": "#000000", "ground": "#05180c",
			"midAmt": 1.0, "midPow": 0.95}
		var own = level.world.get("sky")
		if own is Dictionary:
			skin.merge(own, true)
		skin["bare"] = true
		weather.sky_skin = skin
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

## Where the fog over the skybox stops, over the eye: FOG_TOP (320) over
## the floor under the open sky, the ceiling under a roof (fogTopAt in
## js/material.js, from js/sectorgrid.js) — the eye's own sector's.
func _skybox_fog() -> void:
	var s := level.sector_at(player.x, player.y)
	if s != null and level.layered and player.sector != null:
		s = player.sector      # the storey the eye is in
	if s == null:
		return
	var open: bool = s.outdoor or s.ceil_tex == "SKY"
	var top: float = s.floor + 320.0 if open else s.ceil
	skybox_mat.set_shader_parameter("fog_top", top - camera.position.y)
	skybox_mat.set_shader_parameter("fog_fade", 128.0 if open else 1.0)

func _bind_keys() -> void:
	var keys := {
		"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN],
		"left": [KEY_A, KEY_Q], "right": [KEY_D, KEY_E],
		"turn_left": [KEY_LEFT], "turn_right": [KEY_RIGHT],
		"run": [KEY_SHIFT], "jump": [KEY_SPACE], "use": [KEY_F],
		"attack": [KEY_CTRL], "pause": [KEY_ESCAPE, KEY_P], "zoom": [KEY_Z, KEY_C],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mb)
	var rb := InputEventMouseButton.new()
	rb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("zoom", rb)
	# THE PAD, the web build's standard mapping (js/input.js): the left
	# stick walks, the right looks, the right trigger fires, the left
	# jumps, A uses, the shoulders cycle the guns, a stick click runs,
	# Start or Back pauses
	var pad := {"use": [JOY_BUTTON_A], "run": [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK],
		"pause": [JOY_BUTTON_START, JOY_BUTTON_BACK], "prev_weapon": [JOY_BUTTON_LEFT_SHOULDER],
		"next_weapon": [JOY_BUTTON_RIGHT_SHOULDER]}
	for action in pad:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in pad[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	for pair in [["attack", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["jump", JOY_AXIS_TRIGGER_LEFT, 1.0],
			["fwd", JOY_AXIS_LEFT_Y, -1.0], ["back", JOY_AXIS_LEFT_Y, 1.0],
			["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = pair[1]
		ev.axis_value = pair[2]
		InputMap.action_add_event(pair[0], ev)
		InputMap.action_set_deadzone(pair[0], 0.18)

## input, handed down by Main: a SubViewport outside a container is
## sent none of its own
func handle_input(event: InputEvent) -> void:
	if touch != null and touch.visible and event is InputEventMouse:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += event.relative * MOUSE_SENS * look_sens * Vector2(1.0, -1.0 if invert else 1.0)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("jump"):
		_jump = true
	if event.is_action_pressed("zoom"):
		_zoom = true
	if event.is_action_pressed("prev_weapon"):
		_cycle = -1
	elif event.is_action_pressed("next_weapon"):
		_cycle = 1
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_8:
			_slot = k - KEY_0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle = 1

func _process(dt: float) -> void:
	# A MATCH DOES NOT PAUSE: the host's world goes on whether this machine
	# is looking or not, so the tics go on too — with the hands off
	if player == null or (paused and net == null):
		return
	if net != null:
		net.poll()
	dt = minf(dt, 0.25)
	# the look, every frame
	var keyturn := Input.get_axis("turn_left", "turn_right") * 2.6 * dt
	# the right stick: 3.2 radians a second across, 2.2 up and down
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() < 0.18:
		rs = Vector2()
	var pad_look := Vector2(rs.x * 3.2, rs.y * 2.2 * (-1.0 if invert else 1.0)) * dt * look_sens
	if touch != null and touch.visible:
		touch.sens = look_sens
		_look += touch.take_look() * Vector2(1.0, -1.0 if invert else 1.0)
	# a zoomed scope slows the look with the view. TWO GUNS HAVE ONE — the
	# lance's screen and the launcher's thermal sight — and whichever is in
	# hand takes the zoom; the other is put down and zeroed
	var lance: bool = player.weapon == "LANCE" and not player.dead
	var launcher: bool = player.weapon == "LAUNCHER" and not player.dead
	var potato: bool = player.weapon == "POTATO" and not player.dead
	var sighted: Scope = scope if lance else (thermal if launcher else (green_thermal if potato else null))
	var slow: float = sighted.view_scale() if sighted != null else 1.0
	if net != null:
		if not paused:
			net_look += (Vector2(_look.x + keyturn, _look.y) + pad_look) * slow
	else:
		player.turn((Vector2(_look.x + keyturn, _look.y) + pad_look) * slow)
	_look = Vector2()
	_acc += dt
	var n := 0
	var t0 := Time.get_ticks_usec()
	while _acc >= U.SEC and n < MAX_TICS:
		_acc -= U.SEC
		n += 1
		tic()
	_prof_tics += n
	_prof_add("tics", t0)
	if n == MAX_TICS:
		_acc = 0.0
	# the others, slid to where they were a moment ago
	if net != null:
		net.frame()
	_place_camera(_acc / U.SEC)
	beam.draw((tics + _acc / U.SEC) * U.SEC, dt)
	scope.held = lance
	thermal.held = launcher
	green_thermal.held = potato
	if touch != null:
		touch.scope_on = sighted != null
		touch.scope_up = sighted != null and sighted.zoom_index > 0
		if touch.aim_pulse:
			touch.aim_pulse = false
			if sighted != null:
				sighted.toggle_aim()
		if touch.zoom_pulse:
			touch.zoom_pulse = false
			if sighted != null:
				sighted.step_aimed()
	for sc in [scope, thermal, green_thermal]:
		if sc != sighted and sc.zoom_index > 0:
			sc.set_zoom(0)
	if sighted != null and _zoom:
		sighted.work("cycle")
	if sighted != null and _start_zoom > 0:
		sighted.set_zoom(_start_zoom)
		_start_zoom = 0
	_zoom = false
	# (off the step it is at now, not the one it was at when the look was taken)
	camera.fov = BASE_FOV * (sighted.view_scale() if sighted != null else 1.0)
	t0 = Time.get_ticks_usec()
	scope.render(camera)
	thermal.render(camera)
	green_thermal.render(camera)
	scope.update(player, tics)
	thermal.update(player, tics)
	green_thermal.update(player, tics)
	weather.apply(dt)
	if skybox_mat != null:
		_skybox_fog()
	_prof_add("scopes+weather", t0)
	t0 = Time.get_ticks_usec()
	forest_view.draw(camera.position, (tics + _acc / U.SEC) * U.SEC)
	_prof_add("forest_view", t0)
	t0 = Time.get_ticks_usec()
	lamps.draw(camera.position, Vector2(cos(player.angle), sin(player.angle)), weather.frame.get("skyLight", 0.85))
	_prof_add("lamps", t0)
	t0 = Time.get_ticks_usec()
	standees.draw(actors, camera.position, tics, Vector2(cos(player.angle), sin(player.angle)) if weapon3d != null else Vector2())
	_prof_add("standees", t0)
	t0 = Time.get_ticks_usec()
	tracers.draw_for(camera, _acc / U.SEC)
	flame.particles.draw()
	frost.particles.draw()
	rain.pool.draw()
	bore.draw(camera, tics + _acc / U.SEC)
	missiles.draw(camera)
	arc.draw(camera)
	_prof_add("draw.guns", t0)
	t0 = Time.get_ticks_usec()
	escalation.draw()
	_prof_add("draw.escalation", t0)
	t0 = Time.get_ticks_usec()
	fx.draw()
	giblets.draw()
	_prof_add("draw.fx", t0)
	if weapon3d != null:
		weapon3d.update_for(player, player.firing(), dt, player.sector.light if player.sector else 1.0)
	_prof_frame()

## --prof: where a frame's time goes, averaged and printed every 2 s —
## and, with FRAME RATE on in the pause menu, shown under the frame rate
## (prof_text), so a slow machine can say where its time goes
var _prof := {}
var _prof_on := OS.get_cmdline_user_args().has("--prof")
var _prof_print := _prof_on
var _prof_n := 0
var _prof_tics := 0
var _prof_last := {}
var _prof_last_tics := 0.0
func _prof_add(k: String, t0: int) -> void:
	if _prof_on:
		_prof[k] = _prof.get(k, 0) + Time.get_ticks_usec() - t0

## the last average, a short line: the tics, the crowd, the rest
func prof_text() -> String:
	var t: Dictionary = _prof_last
	if t.is_empty():
		return ""
	var ms := func(k: String) -> float: return float(t.get(k, 0.0)) / 1000.0
	return "tics %.1f (x%.1f, people %.1f) · crowd %.1f (%d rows) · guns %.1f · fx %.1f · scopes %.1f ms" % [
		ms.call("tics"), _prof_last_tics, ms.call("tic.actors"), ms.call("standees"), standees.written,
		ms.call("draw.guns") + ms.call("tic.guns"), ms.call("draw.fx") + ms.call("tic.fx"),
		ms.call("scopes+weather")]

func _prof_frame() -> void:
	if not _prof_on:
		return
	_prof_n += 1
	if _prof_n < 60:
		return
	_prof_last = {}
	for k in _prof:
		_prof_last[k] = float(_prof[k]) / _prof_n
	_prof_last_tics = float(_prof_tics) / _prof_n
	if not _prof_print:
		_prof.clear()
		_prof_n = 0
		_prof_tics = 0
		return
	var line := "PROF fps %d  tics/frame %.2f  process %.1fms  draws %d  objs %d  prims %dk |" % [Engine.get_frames_per_second(), float(_prof_tics) / _prof_n,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000]
	for k in _prof:
		line += " %s %.2fms" % [k, _prof[k] / 1000.0 / _prof_n]
	print(line)
	_prof.clear()
	_prof_n = 0
	_prof_tics = 0

## This machine's hands this tic, as a command (Player.tic's Dictionary;
## TicCmd's fields): the keys, the pad and the glass. The look is not in
## it — it is taken every frame (or, on a network, by NetGame.Session).
func local_cmd() -> Dictionary:
	var cmd := {
		"fwd": Input.get_axis("back", "fwd"),
		"side": Input.get_axis("left", "right"),
		"run": Input.is_action_pressed("run"),
		"jump": _jump or Input.is_action_pressed("jump"),
		"look": Vector2(),
		"attack": Input.is_action_pressed("attack") or _autofire,
		"slot": _slot,
		"cycle": _cycle,
		"use": Input.is_action_pressed("use"),
	}
	# the glass adds to the keys, as js/touch.js's command does
	if touch != null and touch.visible:
		if touch.move != Vector2():
			cmd.fwd = clampf(cmd.fwd + touch.move.y, -1.0, 1.0)
			cmd.side = clampf(cmd.side + touch.move.x, -1.0, 1.0)
		cmd.run = cmd.run or (touch.run and touch.move.length() > 0.85)
		cmd.attack = cmd.attack or touch.attack
		cmd.use = cmd.use or touch.use
		cmd.jump = cmd.jump or touch.jump_pulse
		touch.jump_pulse = false
		if touch.cycle != 0:
			cmd.cycle = touch.cycle
			touch.cycle = 0
	_jump = false
	_slot = 0
	_cycle = 0
	return cmd

func tic() -> void:
	tics += 1
	# THE PLAYERS ARE DRIVEN BY COMMANDS, NOT BY THE KEYBOARD: each one's
	# from its session — this machine's own input, rounded as the wire
	# rounds it, or a client's off the wire — so the simulation cannot tell
	# a player here from a player on another machine (js/game.js)
	for i in players.size():
		var p: Player = players[i]
		var cmd: Dictionary = (p.session if p.session != null else session).cmd(self)
		var back: Callable = rewind.call(p, cmd) if rewind.is_valid() else Callable()
		p.tic(cmd)
		if doors != null:
			doors.command(p, cmd)
		if back.is_valid():
			back.call()
	if doors != null:
		doors.tic()
	weather.tic()
	var t0 := Time.get_ticks_usec()
	# THE CROWD FAR OFF THINKS LESS OFTEN (at the user's request, for
	# speed): somebody with nothing on — not alight, not afraid, no
	# target, not held — further than LOD_FAR from the player takes one
	# tic in four. They wander a shade slower where nobody can tell. Not
	# in a match, whose worlds must agree.
	var lod: bool = net == null and player != null
	var lx: float = player.x if lod else 0.0
	var ly: float = player.y if lod else 0.0
	var lod_far2 := LOD_FAR * LOD_FAR
	for a: Actor in actors:
		if lod and a.burning == 0 and a.panic == 0 and a.target == null and not a.frozen and a.bored == 0 and a.ash <= 0.0 \
				and (tics + a.id) % 4 != 0:
			var ddx: float = a.x - lx
			var ddy: float = a.y - ly
			if ddx * ddx + ddy * ddy > lod_far2:
				continue
		a.tic()
	_prof_add("tic.actors", t0)
	t0 = Time.get_ticks_usec()
	tracers.tic()
	forest.wind = weather.wind()
	rain.tic()
	flame.tic()
	frost.tic()
	bore.tic()
	missiles.tic()
	potatoes.tic()
	arc.tic()
	_prof_add("tic.guns", t0)
	t0 = Time.get_ticks_usec()
	escalation.tic()
	_prof_add("tic.escalation", t0)
	t0 = Time.get_ticks_usec()
	fx.tic()
	giblets.tic()
	_prof_add("tic.fx", t0)
	if big_message_tics > 0:
		big_message_tics -= 1
		if big_message_tics == 0:
			big_message = null
	for i in range(toasts.size() - 1, -1, -1):
		toasts[i].tics -= 1
		if toasts[i].tics <= 0:
			toasts.remove_at(i)
	if tics % 35 == 0:
		actors = actors.filter(func(a): return not a.removed)
	# a network client's own tic: the puppets, and what the command just
	# run left the player looking at (NetGame)
	if net != null:
		net.tic()

## a picture's eye, off the body (--eye=rise,pitch): rise, pitch degrees
var eye_hook := Vector2.ZERO

func _place_camera(f: float) -> void:
	var p := player
	var x := lerpf(p.prev.x, p.x, f)
	var y := lerpf(p.prev.y, p.y, f)
	var vz := lerpf(p.prev.z, p.view_z, f)
	camera.position = U.v3(x, y, vz)
	# map angle a faces (cos a, sin a); Godot's -Z faces rotation.y = a - PI/2
	# (and on a network, the look still held for the next tic on top)
	var yaw := U.angle_norm(p.angle - net_look.x)
	var pt := clampf(p.pitch - net_look.y, -Player.MAX_PITCH, Player.MAX_PITCH)
	camera.rotation = Vector3(pt, yaw - PI / 2.0, 0.0)
	if eye_hook != Vector2.ZERO:
		camera.position += U.v3(0.0, 0.0, eye_hook.x)
		camera.rotation.x = deg_to_rad(eye_hook.y)
	# THE SHAKE, on the eye and not the player, so the aim stays put:
	# four sines at rates that do not divide into each other
	var sh: float = beam.shake if beam != null else 0.0
	# (and the potato's nuke shakes it harder than anything)
	if potatoes != null:
		sh = maxf(sh, potatoes.shake * 1.6)
	if sh > 0.001:
		var t := Time.get_ticks_msec() * 0.001
		var k := sh * sh
		camera.rotation.y += k * (0.022 * sin(t * 47.3) + 0.013 * sin(t * 29.1 + 1.7))
		camera.rotation.x += k * (0.017 * sin(t * 41.7 + 0.9) + 0.010 * sin(t * 23.3 + 2.4))
		camera.position += U.v3(k * 5.5 * sin(t * 53.1 + 0.3), k * 5.5 * cos(t * 44.9 + 1.9), k * 4.0 * sin(t * 61.7 + 2.6))

## The map's things that are actors, into the world.
const THING_ACTORS := {"SHOPPER": "SHOPPER", "TOWNIE": "TOWNIE", "SWAT": "SWAT", "ARMY": "ARMY", "STREETLAMP": "STREETLAMP",
	"GRAVESTONE": "GRAVESTONE"}   # the sprawl's headstones

func _spawn_things() -> void:
	for t in level.things:
		var type: String = THING_ACTORS.get(t.type, "")
		if type == "":
			continue
		var o := {"variant": int(t.get("variant", 0))}
		if t.get("z") != null:
			o["z"] = float(t.z)
		var a := Actor.new(self, type, float(t.x), float(t.y), float(t.get("angle", 0.0)), o)
		actors.append(a)

func spawn(type: String, x: float, y: float, a := 0.0, opts := {}) -> Actor:
	var act := Actor.new(self, type, x, y, a, opts)
	actors.append(act)
	return act

## A solid thing in the way of `who` stepping to (nx, ny), or null. A
## thing you are already inside never refuses a step that takes you no
## nearer its middle: you can always walk out of one.
func thing_in_way(who, nx: float, ny: float):
	for a in blockmap.near(nx, ny):
		if a.removed or not a.solid or a.dead:
			continue
		# on a map in storeys, only what is at your own height
		if level.layered and (a.z >= who.z + who.height or who.z >= a.z + a.height):
			continue
		var rr: float = who.radius + a.radius
		var d2 := U.dist2(nx, ny, a.x, a.y)
		if d2 < rr * rr:
			var was := U.dist2(who.x, who.y, a.x, a.y)
			if was < rr * rr and d2 >= was:
				continue
			return a
	# AND EACH OTHER, when there are others: a player is as solid as a
	# trooper, on the same terms — you can always step out of one
	if players.size() > 1:
		for a in players:
			if a == who or a.dead:
				continue
			var rr: float = who.radius + a.radius
			var d2 := U.dist2(nx, ny, a.x, a.y)
			if d2 >= rr * rr:
				continue
			if absf(a.z - who.z) >= who.height:
				continue
			var was := U.dist2(who.x, who.y, a.x, a.y)
			if was < rr * rr and d2 >= was:
				continue
			return a
	return null

func play_sound(name, at) -> void:
	if sound != null:
		sound.play(name, at)

## Everyone within `r` of (x, y) who can be frightened, frightened.
func scare(x: float, y: float, r: float) -> void:
	for a in blockmap.near_radius(x, y, r):
		if a.dead or a.removed or not a.info.has("scareRange"):
			continue
		if U.dist2(a.x, a.y, x, y) < r * r:
			a.A_Scare(x, y)

## A person coming apart: the fireball where they stood (js/people.js
## Giblets.burst — the pieces come with the gore port).
func gib(a: Actor) -> void:
	giblets.burst(a)
	a.remove()

## Everything alive within `radius` of `at` (map space), players included.
func actors_in_cone_around(at, radius: float) -> Array:
	var out := []
	var r2 := radius * radius
	for a in actors:
		if not a.removed and not a.dead and a.shootable and U.dist2(at.x, at.y, a.x, a.y) < r2:
			out.append(a)
	for p in players:
		if not p.dead and U.dist2(at.x, at.y, p.x, p.y) < r2:
			out.append(p)
	return out

## A fuel can or a car going up (Game.explode in js/game.js). `a` only has
## to have a position (x, y, and z if it is off the floor): the heat into
## the grid, a burn on the floor under it, the building if `structure`
## says so, and everybody in `radius` hurt by how near and set alight.
func explode(a, opts := {}) -> void:
	var radius: float = opts.get("radius", 150.0)
	var dmg: float = opts.get("damage", 60.0)
	var ign: int = opts.get("ignite", 320)
	play_sound(opts.get("sound", "explode"), a)
	var under := level.sector_at(a.x, a.y)
	var az: float = a.z if "z" in a else (under.floor if under else 0.0)
	# on a map in storeys: the storey it went up in
	under = level.span_at(a.x, a.y, az)
	if under and az - under.floor < 64.0:
		decals.hole(Vector3(a.x, a.y, under.floor), Vector3(0, 0, 1), true)
	for o in actors_in_cone_around(a, radius):
		if typeof(a) == TYPE_OBJECT and o == a:
			continue
		# not through a floor: nobody downstairs is hurt by a blast upstairs
		if level.layered and level.sight_blocked(a.x, a.y, az + 16.0, o.x, o.y, o.z + o.height * 0.5):
			continue
		var d := sqrt(U.dist2(a.x, a.y, o.x, o.y))
		o.damage(roundf(dmg * (1.0 - d / radius)), null, {"fire": true})
		if o.has_method("ignite"):
			o.ignite(ign)

func on_monster_killed(_a, _source) -> void:
	kills += 1

## What the eye is looking at, out to `range` (Game.trace): the first
## wall, floor, ceiling or body along the view, pitch and all.
func trace(from, ang: float, pitch: float, range: float) -> Dictionary:
	var c := cos(pitch)
	var ax: float = from.x
	var ay: float = from.y
	var az: float = from.eye_z()
	var tx := ax + cos(ang) * c * range
	var ty := ay + sin(ang) * c * range
	var tz := az + sin(pitch) * range
	var wall := level.ray_hit_wall(ax, ay, az, tx, ty, tz)
	var best_t: float = wall.t if not wall.is_empty() else 1.0
	var best = null
	var sec: Level.Sector = from.sector if from.sector != null else level.sector_at(ax, ay)
	if level.layered:
		# every floor, deck and roof along it, column by column
		var fh := level.ray_hit_flat(ax, ay, az, tx, ty, tz, true)
		if not fh.is_empty():
			best_t = minf(best_t, fh.t)
	elif sec:
		if tz < sec.floor:
			best_t = minf(best_t, (az - sec.floor) / (az - tz))
		if tz > sec.ceil:
			best_t = minf(best_t, (sec.ceil - az) / (tz - az))
	var dx := tx - ax
	var dy := ty - ay
	var len2 := dx * dx + dy * dy
	if len2 == 0.0:
		len2 = 1.0
	for a in actors:
		if a == from or a.removed or a.dead or not a.shootable:
			continue
		var t: float = ((a.x - ax) * dx + (a.y - ay) * dy) / len2
		if t <= 0.0 or t >= best_t:
			continue
		var px: float = ax + dx * t
		var py: float = ay + dy * t
		if U.dist2(px, py, a.x, a.y) > a.radius * a.radius:
			continue
		var pz: float = az + (tz - az) * t
		if pz < a.z or pz > a.z + a.height:
			continue
		best_t = t
		best = a
	return {"x": ax + dx * best_t, "y": ay + dy * best_t, "z": az + (tz - az) * best_t, "actor": best, "t": best_t}

## Where the gun's muzzle is, in map space (x, y, z): ahead of the eye,
## a little right and down.
func nozzle(p) -> Vector3:
	var c := cos(p.angle)
	var s := sin(p.angle)
	return Vector3(p.x + c * 18.0 + s * 9.0, p.y + s * 18.0 - c * 9.0, p.view_z - 9.0)

## WHERE A ROUND IS SEEN TO LEAVE, for the player whose eyes these are:
## the gun in hand's muzzle as it is drawn (Weapon3D.muzzle_uv), cast
## back out through the world's camera — so a streak comes out of the
## barrels on the screen and not out of a point beside the eye. The
## round itself still flies from `fallback` (nozzle: the same for every
## machine in a match); this is only where its streak starts.
func muzzle_view(p, fallback: Vector3) -> Vector3:
	if weapon3d == null or p != player or camera == null:
		return fallback
	var uv: Vector2 = weapon3d.muzzle_uv()
	if uv.x < 0.0:
		return fallback
	var vs := Vector2(camera.get_viewport().get_visible_rect().size)
	var o := camera.project_ray_origin(uv * vs)
	var d := camera.project_ray_normal(uv * vs)
	var at := o + d * 30.0
	return Vector3(at.x, -at.z, at.y)

## the weapons that do not run on frames tic themselves: kind is one of
## "charge" (the lance), "seeker" (the launcher), "arc" (the maw)
func weapon_system(kind: String):
	match kind:
		"seeker":
			return missiles
		"arc":
			return arc
		"potato":
			return potatoes
		"charge":
			return beam
	return null

## Being shot at wakes the place up, and so does setting fire to it.
func noise(_who, _r: float) -> void:
	pass

## A MATCH HAS ITS OWN IDEA OF WHAT A DEATH IS — a frag, and a respawn —
## and nobody's death ends the world for the others
func on_player_died(p, source) -> void:
	if rules != null:
		rules.died(p, source)

## The gun's own notices: a line in the corner that fades, four at most.
func toast(text: String) -> void:
	toasts.append({"text": text, "tics": TOAST_LIFE})
	while toasts.size() > TOAST_MAX:
		toasts.pop_front()

func set_big_message(t, n: int) -> void:
	big_message = t
	big_message_tics = n

## What a shot from `from` can hit: every player and every actor, less
## `from` itself and whoever the match says is on its side.
func targets_for(from) -> Array:
	var out := []
	for p in players:
		if p != from and not (rules != null and rules.friendly(from, p)):
			out.append(p)
	out.append_array(actors)
	return out

## A round down the eye line (Game.hitscan in js/game.js): the nearest
## wall, floor or ceiling it meets, and the nearest shootable thing
## before that, projected onto the ray. What it leaves is a hole — a hot
## one for the minigun — or blood behind whoever it went through.
## opts: pitch, from (Vector3 map-space muzzle), shot, hot. Returns the
## thing hit, or null; last_hit is where it stopped.
func hitscan(from, ang: float, range: float, dmg: float, opts := {}):
	var pitch: float = opts.get("pitch", 0.0)
	var cp := cos(pitch)
	var o: Vector3 = opts.get("from", Vector3(from.x, from.y, from.eye_z()))
	var ox := o.x
	var oy := o.y
	var z := o.z
	var tx := ox + cos(ang) * cp * range
	var ty := oy + sin(ang) * cp * range
	var tz := z + sin(pitch) * range
	var wall := level.ray_hit_wall(ox, oy, z, tx, ty, tz)
	var max_t: float = wall.t if not wall.is_empty() else 1.0
	var floor_hit = null
	if pitch != 0.0 and level.layered:
		# ON A MAP IN STOREYS the floors, decks and roofs along the whole
		# of it, column by column: a round from under the terrace stops in
		# its deck, and one fired over the terrace's edge flies on
		var fh := level.ray_hit_flat(ox, oy, z, tx, ty, tz)
		if not fh.is_empty() and fh.t < max_t:
			max_t = fh.t
			floor_hit = fh.z
	elif pitch != 0.0:
		var sec: Level.Sector = from.sector if from.sector != null else level.sector_at(ox, oy)
		if sec:
			if tz < sec.floor and z > sec.floor:
				var t := (z - sec.floor) / (z - tz)
				if t < max_t:
					max_t = t
					floor_hit = sec.floor
			if tz > sec.ceil and z < sec.ceil and sec.ceil_tex != "SKY":
				var t := (sec.ceil - z) / (tz - z)
				if t < max_t:
					max_t = t
					floor_hit = sec.ceil
	var best = null
	var best_t := max_t
	var bp := Vector3()
	var dx := tx - ox
	var dy := ty - oy
	var len2 := dx * dx + dy * dy
	if len2 == 0.0:
		len2 = 1.0
	for a in targets_for(from):
		if a == null or a == from or a.removed or a.dead or not a.shootable:
			continue
		var t: float = ((a.x - ox) * dx + (a.y - oy) * dy) / len2
		if t <= 0.0 or t >= best_t:
			continue
		var px: float = ox + dx * t
		var py: float = oy + dy * t
		if U.dist2(px, py, a.x, a.y) > a.radius * a.radius:
			continue
		var pz: float = z + (tz - z) * t
		if pz < a.z - 8.0 or pz > a.z + a.height + 8.0:
			continue
		best_t = t
		best = a
		bp = Vector3(px, py, pz)
	if best != null:
		best.damage(rules.scale(from, best, dmg) if rules != null else dmg, from, opts)
		# a round into a van is a hole in the van, not blood
		if opts.get("shot", false) and not ("vehicle" in best and best.vehicle != null):
			gore_decals.bleed(best, bp, Vector3(dx, dy, tz - z))
		last_hit = bp
		return best
	if not wall.is_empty() and (pitch == 0.0 or wall.t <= max_t + 1e-9):
		if opts.get("shot", false):
			decals.hole(Vector3(wall.x, wall.y, wall.z), Decals.wall_normal(wall.line, ox, oy), opts.get("hot", false))
		last_hit = Vector3(wall.x, wall.y, wall.z)
	elif floor_hit != null:
		var hx := ox + dx * max_t
		var hy := oy + dy * max_t
		if opts.get("shot", false):
			decals.hole(Vector3(hx, hy, floor_hit), Vector3(0, 0, 1) if tz < z else Vector3(0, 0, -1), opts.get("hot", false))
		last_hit = Vector3(hx, hy, floor_hit)
	else:
		last_hit = Vector3(tx, ty, tz)
	return null
