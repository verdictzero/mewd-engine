## MEWD — the game (js/game.js and the frame loop in js/main.js).
##
## The simulation runs at Doom's 35 tics a second, at most six a frame,
## whatever the display does; the picture is drawn between the last two
## tics so a 144 Hz screen moves smoothly. The look is taken every frame
## (a mouse is not a 35 Hz device) and the legs every tic.
extends Node3D

const BASE_FOV := 72.0
const MOUSE_SENS := 0.0022
const MAX_TICS := 6

var level: Level
var bank: TexBank
var player: Player
var camera: Camera3D
var actors: Array = []
var blockmap := ActorGrid.new()
var standees: Standees
## the fire grid (js/fire.js) — asked by the crowd, fed by the flame
var fire: FireSystem = null
var fire_sprites: FireSprites
var forest: Forest
var forest_view: ForestView
var lamps: Lamps
var tics := 0
var kills := 0
var weather := Weather.new()
var rain: Rain
## the systems the guns hand their work to, when they are ported
var flame: FlameStream
var frost: FrostStream
## the bore's sight and lock, which the player's trigger asks (Player.armed)
var bore: BoreSystem
## the quad launcher's seeker and its missiles
var missiles: MissileSystem
## the police, the army and the fire brigade, and every vehicle (js/responders.js, vehicles.js, brigade.js)
var escalation: Escalation
var arc: ArcSystem
var tracers: Tracers
var decals: Decals
var gore_decals: GoreDecals
var fx: Effects
var giblets: Giblets
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
## which map: "maze" (the demo's), or "jesse"
var map_name := "maze"
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
	var which := map_name
	for a in args:
		if a.begins_with("--map="):
			which = a.substr(6)
	start_map(JesseMap.build(seed) if which == "jesse" else MazeMap.build(seed))

func start_map(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	level = DocCompile.compile(doc)
	fire = FireSystem.new(self)
	fire_sprites = FireSprites.new()
	add_child(fire_sprites)
	forest = Forest.new(level)
	forest_view = ForestView.new(forest)
	add_child(forest_view)
	lamps = Lamps.new(level)
	add_child(lamps)
	bank = TexBank.new()
	var geo := MapGeo.new(bank).build(level)
	add_child(geo)
	_make_sky(str(level.world.get("skybox", "")))
	var start = null
	for t in level.things:
		if t.type == "START":
			start = t
			break
	if start == null:
		start = {"x": level.bounds.get_center().x, "y": level.bounds.get_center().y, "angle": 0.0}
	player = Player.new(self, float(start.x), float(start.y), float(start.angle))
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
		var sm := PanoramaSkyMaterial.new()
		sm.panorama = tex
		sm.filter = false
		sky.sky_material = sm
		var img := tex.get_image()
		if img:
			var c := Color()
			var h := img.get_height() / 2
			for i in 16:
				c += img.get_pixel(i * img.get_width() / 16, h)
			RenderingServer.global_shader_parameter_set("air_color", c / 16.0)
	else:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://godot/shaders/sky.gdshader")
		sky.sky_material = sm
		weather.sky_mat = sm
		var skin = level.world.get("sky")
		if skin is Dictionary:
			weather.sky_skin = skin
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _bind_keys() -> void:
	var keys := {
		"fwd": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN],
		"left": [KEY_A, KEY_Q], "right": [KEY_D, KEY_E],
		"turn_left": [KEY_LEFT], "turn_right": [KEY_RIGHT],
		"run": [KEY_SHIFT], "jump": [KEY_SPACE], "use": [KEY_F],
		"attack": [KEY_CTRL], "pause": [KEY_ESCAPE, KEY_P],
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
	if event.is_action_pressed("prev_weapon"):
		_cycle = -1
	elif event.is_action_pressed("next_weapon"):
		_cycle = 1
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_7:
			_slot = k - KEY_0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle = 1

func _process(dt: float) -> void:
	if player == null or paused:
		return
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
	player.turn(Vector2(_look.x + keyturn, _look.y) + pad_look)
	_look = Vector2()
	_acc += dt
	var n := 0
	while _acc >= U.SEC and n < MAX_TICS:
		_acc -= U.SEC
		n += 1
		tic()
	if n == MAX_TICS:
		_acc = 0.0
	_place_camera(_acc / U.SEC)
	weather.apply(dt, burn_percent() / 100.0, forest.burn_fraction(), fire.burning_cells() + forest.burning_cells())
	forest_view.draw(camera.position, (tics + _acc / U.SEC) * U.SEC)
	lamps.draw(camera.position, Vector2(cos(player.angle), sin(player.angle)), weather.frame.get("skyLight", 0.85))
	standees.draw(actors, camera.position, tics)
	fire_sprites.draw(fire, camera.position, tics + _acc / U.SEC)
	tracers.draw_for(camera, _acc / U.SEC)
	flame.particles.draw()
	frost.particles.draw()
	rain.pool.draw()
	bore.draw(camera, tics + _acc / U.SEC)
	missiles.draw(camera)
	arc.draw(camera)
	escalation.draw()
	fx.draw()
	giblets.draw()
	if weapon3d != null:
		weapon3d.update_for(player, player.firing(), dt, player.sector.light if player.sector else 1.0)

func tic() -> void:
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
	player.tic(cmd)
	tics += 1
	weather.tic()
	for a in actors:
		a.tic()
	tracers.tic()
	fire.wind = weather.wind()
	fire.rain = weather.frame.get("rain", 0.0)
	fire.tic()
	forest.wind = fire.wind
	forest.rain = fire.rain
	forest.tic()
	rain.tic()
	flame.tic()
	frost.tic()
	bore.tic()
	missiles.tic()
	arc.tic()
	escalation.tic()
	fx.tic()
	giblets.tic()
	fire.apply_char(tics)   # TODO: rebuild the charred sectors' geometry (MapGeo per-sector)
	if tics % 35 == 0:
		actors = actors.filter(func(a): return not a.removed)

func _place_camera(f: float) -> void:
	var p := player
	var x := lerpf(p.prev.x, p.x, f)
	var y := lerpf(p.prev.y, p.y, f)
	var vz := lerpf(p.prev.z, p.view_z, f)
	camera.position = U.v3(x, y, vz)
	# map angle a faces (cos a, sin a); Godot's -Z faces rotation.y = a - PI/2
	camera.rotation = Vector3(p.pitch, p.angle - PI / 2.0, 0.0)

## The map's things that are actors, into the world.
const THING_ACTORS := {"SHOPPER": "SHOPPER", "TOWNIE": "TOWNIE", "SWAT": "SWAT", "ARMY": "ARMY", "STREETLAMP": "STREETLAMP"}

func _spawn_things() -> void:
	for t in level.things:
		var type: String = THING_ACTORS.get(t.type, "")
		if type == "":
			continue
		var a := Actor.new(self, type, float(t.x), float(t.y), float(t.get("angle", 0.0)), {"variant": int(t.get("variant", 0))})
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
		var rr: float = who.radius + a.radius
		var d2 := U.dist2(nx, ny, a.x, a.y)
		if d2 < rr * rr:
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
	if player != null and not player.dead and U.dist2(at.x, at.y, player.x, player.y) < r2:
		out.append(player)
	return out

## A fuel can or a car going up (Game.explode in js/game.js). `a` only has
## to have a position (x, y, and z if it is off the floor): the heat into
## the grid, a burn on the floor under it, the building if `structure`
## says so, and everybody in `radius` hurt by how near and set alight.
func explode(a, opts := {}) -> void:
	var radius: float = opts.get("radius", 150.0)
	var dmg: float = opts.get("damage", 60.0)
	var heat: float = opts.get("heat", 230.0)
	var heat_radius: float = opts.get("heatRadius", 86.0)
	var ign: int = opts.get("ignite", 320)
	var structure: float = opts.get("structure", 0.0)
	var structure_radius: float = opts.get("structureRadius", radius * 1.4)
	play_sound(opts.get("sound", "explode"), a)
	fire.ignite(a.x, a.y, heat, heat_radius)
	var under := level.sector_at(a.x, a.y)
	var az: float = a.z if "z" in a else (under.floor if under else 0.0)
	if under and az - under.floor < 64.0:
		decals.hole(Vector3(a.x, a.y, under.floor), Vector3(0, 0, 1), true)
	if structure > 0.0:
		fire.damage_structure(a.x, a.y, structure_radius, structure)
	for o in actors_in_cone_around(a, radius):
		if typeof(a) == TYPE_OBJECT and o == a:
			continue
		var d := sqrt(U.dist2(a.x, a.y, o.x, o.y))
		o.damage(roundf(dmg * (1.0 - d / radius)), null, {"fire": true})
		if o.has_method("ignite"):
			o.ignite(ign)

## how much of the place has gone, for the readout's first bar
func burn_percent() -> float:
	return fire.burn_percent() if fire != null else 0.0

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
	if sec:
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

## the weapons that do not run on frames tic themselves: kind is one of
## "charge" (the lance), "seeker" (the launcher), "arc" (the maw)
func weapon_system(kind: String):
	match kind:
		"seeker":
			return missiles
		"arc":
			return arc
	return null

## Being shot at wakes the place up, and so does setting fire to it.
func noise(_who, _r: float) -> void:
	pass

func on_player_died(_p, _source) -> void:
	pass

## Everybody a shot from `from` can hit: the player (unless it is theirs)
## and every actor.
func targets_for(from) -> Array:
	var out := []
	if player != from:
		out.append(player)
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
	if pitch != 0.0:
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
		best.damage(dmg, from, opts)
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
