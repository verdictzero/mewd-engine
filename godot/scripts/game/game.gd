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
## the fire grid, when there is one (js/fire.js) — asked by the crowd
var fire = null
var tics := 0
var kills := 0
var seed := 0
var _acc := 0.0
var _look := Vector2()
var _jump := false
## --shot=path.png [--shot-frames=N]: save the picture after N frames and
## quit — how the port is checked without a screen
var _shot := ""
var _shot_frames := 20
var _frames := 0

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
	start_map(MazeMap.build(seed))

func start_map(doc: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	level = DocCompile.compile(doc)
	bank = TexBank.new()
	var geo := MapGeo.new(bank).build(level)
	add_child(geo)
	_make_sky(str(level.world.get("skybox", "BSKY2")))
	var start = null
	for t in level.things:
		if t.type == "START":
			start = t
			break
	if start == null:
		start = {"x": level.bounds.get_center().x, "y": level.bounds.get_center().y, "angle": 0.0}
	player = Player.new(self, float(start.x), float(start.y), float(start.angle))
	_spawn_things()
	standees = Standees.new()
	add_child(standees)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 2.0
	camera.far = 16000.0
	add_child(camera)
	camera.make_current()
	print("MEWD: %s seed %d — %d sectors, %d lines, %d things, built in %d ms" % [
		level.name, seed, level.sectors.size(), level.lines.size(), level.things.size(), Time.get_ticks_msec() - t0])

func _make_sky(name: String) -> void:
	var env := Environment.new()
	var tex: Texture2D = load("res://assets/skies/%s.png" % name)
	if tex:
		var sm := PanoramaSkyMaterial.new()
		sm.panorama = tex
		sm.filter = false
		var sky := Sky.new()
		sky.sky_material = sm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		# the air fades to the colour of the sky at the horizon
		var img := tex.get_image()
		if img:
			var c := Color()
			var h := img.get_height() / 2
			for i in 16:
				c += img.get_pixel(i * img.get_width() / 16, h)
			c /= 16.0
			RenderingServer.global_shader_parameter_set("air_color", c)
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.1, 0.1, 0.12)
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

## input, handed down by Main: a SubViewport outside a container is
## sent none of its own
func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += event.relative * MOUSE_SENS
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_pressed("jump"):
		_jump = true

func _process(dt: float) -> void:
	if player == null:
		return
	dt = minf(dt, 0.25)
	# the look, every frame
	var keyturn := Input.get_axis("turn_left", "turn_right") * 2.4 * dt
	player.turn(Vector2(_look.x + keyturn, _look.y))
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
	standees.draw(actors, camera.position, tics)
	_frames += 1
	if _shot != "" and _frames == _shot_frames:
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(_shot)
		get_tree().quit()

func tic() -> void:
	var cmd := {
		"fwd": Input.get_axis("back", "fwd"),
		"side": Input.get_axis("left", "right"),
		"run": Input.is_action_pressed("run"),
		"jump": _jump or Input.is_action_pressed("jump"),
		"look": Vector2(),
	}
	_jump = false
	player.tic(cmd)
	tics += 1
	for a in actors:
		a.tic()
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
const THING_ACTORS := {"SHOPPER": "SHOPPER", "TOWNIE": "TOWNIE", "SWAT": "SWAT", "ARMY": "ARMY"}

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

func play_sound(_name, _at) -> void:
	pass

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
	spawn("BLAST", a.x, a.y)
	scare(a.x, a.y, 900.0)
	a.remove()

func on_monster_killed(_a, _source) -> void:
	kills += 1

## A round down the eye line of `who` at `angle`: the first actor or wall
## it meets. Returns what it hit.
func hitscan(who, ang: float, range: float, dmg: float, opts := {}) -> Dictionary:
	return {}
