class_name FlyCamera
extends Camera3D

## THE VIEWER'S EYE: flown round the place freely, or walked over its ground.
##
##   mouse      click to take the mouse, then look; Esc lets it go
##   W A S D    forward, left, back, right (and the arrow keys)
##   E / Q      up / down (Space / C too)
##   Shift      four times as fast; Ctrl a quarter
##   wheel      the flying speed, up or down
##   G          walk on the ground (an eye 1.7 m over it) or fly
##   pad        left stick moves, right stick looks, the triggers climb and
##              sink, A walks or flies
##   touch      one finger looks; two move (drag) and climb (spread, pinch)

## Metres a second, flying (the wheel moves it).
@export var speed := 40.0
## Degrees a pixel of mouse.
@export var mouse_turn := 0.12
## Walking: the eye this high over the ground, at this many metres a second.
@export var eye_height := 1.7
@export var walk_speed := 6.0

## the ground under a point (x, z) -> metres, or NAN: the viewer's
var ground: Callable
var walking := false
var yaw := 0.0
var pitch := 0.0
var _touches := {}
var _pinch := 0.0


func _ready() -> void:
	fov = 70.0
	near = 0.1
	far = 12000.0


## Looking toward the point (x, z) at the eye's own height, or along `dir`.
func face_point(p: Vector3) -> void:
	var d := p - global_position
	if d.length_squared() < 1e-6:
		return
	yaw = atan2(-d.x, -d.z)
	pitch = clampf(asin(clampf(d.normalized().y, -1.0, 1.0)), -1.5, 1.5)
	_apply()


func _apply() -> void:
	rotation = Vector3(pitch, yaw, 0.0)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and DisplayServer.is_touchscreen_available() == false:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.25, 2000.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.25, 1.0)
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= deg_to_rad(e.relative.x * mouse_turn)
		pitch = clampf(pitch - deg_to_rad(e.relative.y * mouse_turn), -1.55, 1.55)
		_apply()
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif e.keycode == KEY_G:
			walking = not walking
	elif e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_A:
		walking = not walking
	elif e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_pinch = _spread()
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			yaw -= deg_to_rad(e.relative.x * mouse_turn * 1.5)
			pitch = clampf(pitch - deg_to_rad(e.relative.y * mouse_turn * 1.5), -1.55, 1.55)
			_apply()
		elif _touches.size() >= 2:
			var s := _spread()
			var climb := (s - _pinch) * speed * 0.0025
			_pinch = s
			var flat := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var side := Vector3(cos(yaw), 0.0, -sin(yaw))
			var k := speed * 0.004
			global_position += (flat * -e.relative.y * k + side * e.relative.x * k) * 0.5 + Vector3.UP * climb


func _spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _process(dt: float) -> void:
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		mv.y += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_C):
		mv.y -= 1.0
	# the pad's sticks and triggers
	var lx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(lx) > 0.15:
		mv.x += lx
	if absf(ly) > 0.15:
		mv.z += ly
	mv.y += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(rx) > 0.15 or absf(ry) > 0.15:
		yaw -= rx * 2.4 * dt
		pitch = clampf(pitch - ry * 1.8 * dt, -1.55, 1.55)
		_apply()
	var k := 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		k = 4.0
	elif Input.is_key_pressed(KEY_CTRL):
		k = 0.25
	if walking:
		var flat := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var side := Vector3(cos(yaw), 0.0, -sin(yaw))
		global_position += (flat * -mv.z + side * mv.x) * walk_speed * k * dt
		var g := _ground_here()
		if not is_nan(g):
			global_position.y = g + eye_height
	else:
		var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
		global_position += (b * Vector3(mv.x, 0.0, mv.z) + Vector3.UP * mv.y) * speed * k * dt
		# never under the ground
		var g := _ground_here()
		if not is_nan(g) and global_position.y < g + 0.4:
			global_position.y = g + 0.4


func _ground_here() -> float:
	if not ground.is_valid():
		return NAN
	return float(ground.call(global_position.x, global_position.z))
