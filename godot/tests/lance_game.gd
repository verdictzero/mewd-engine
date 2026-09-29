## MEWD — the Game with the positron lance wired in, the way game.gd is
## to have it (the beam, the scope, the shake, the zoom), for the weapons
## test and lance_shot.gd until it does. It stands down by itself: if
## game.gd already answers weapon_system("charge") or already has a
## `scope`, the base's own are used and this adds nothing.
extends "res://godot/scripts/game/game.gd"

var lance_beam: BeamSystem
var lance_scope: Scope
## a ZOOM press, from the test or the shot
var zoom_press := false

func start_map(doc: Dictionary) -> void:
	super(doc)
	if super.weapon_system("charge") == null:
		lance_beam = BeamSystem.new(self)
		add_child(lance_beam)
	if get("scope") == null:
		lance_scope = Scope.new()
		add_child(lance_scope)
		lance_scope.set_stages(player.stage_marks())
		if weapon3d != null:
			weapon3d.scopes["LANCE"] = lance_scope

func weapon_system(kind: String):
	var s = super(kind)
	if s == null and kind == "charge":
		return lance_beam
	return s

func _process(dt: float) -> void:
	super(dt)
	if player == null or paused:
		return
	if lance_beam != null:
		lance_beam.draw((tics + _acc / U.SEC) * U.SEC, minf(dt, 0.25))
	if lance_scope != null:
		var lance: bool = player.weapon == "LANCE" and not player.dead
		lance_scope.held = lance
		if not lance and lance_scope.zoom_index > 0:
			lance_scope.set_zoom(0)
		elif lance and zoom_press:
			lance_scope.work("cycle")
		zoom_press = false
		camera.fov = BASE_FOV * (lance_scope.view_scale() if lance else 1.0)
		lance_scope.render(camera)
		lance_scope.update(player, tics)

## THE SHAKE, added to the eye and NOT to the player, so it does not walk
## the aim off the street you picked: four sines at rates that do not
## divide into each other, the turn bigger than the lift.
func _place_camera(f: float) -> void:
	super(f)
	var sh: float = lance_beam.shake if lance_beam != null else 0.0
	if sh > 0.001:
		var t := Time.get_ticks_msec() * 0.001
		var k := sh * sh
		camera.rotation.y += k * (0.022 * sin(t * 47.3) + 0.013 * sin(t * 29.1 + 1.7))
		camera.rotation.x += k * (0.017 * sin(t * 41.7 + 0.9) + 0.010 * sin(t * 23.3 + 2.4))
		camera.position += U.v3(k * 5.5 * sin(t * 53.1 + 0.3), k * 5.5 * cos(t * 44.9 + 1.9), k * 4.0 * sin(t * 61.7 + 2.6))
