## MEWD — a picture of a real place (EarthField): the eye put anywhere on it,
## at any height, looking anywhere, and the picture.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --resolution 1280x720 \
##   --script res://godot/tests/earth_shot.gd -- --map=earth_oeschinen out.png \
##   [--at=X,Z] [--high=M] [--face=X,Z | --turn=DEG | --look=sun|moon [--look-off=DEG,P]]
##   [--pitch=P]
##   [--tics=N] [--clean] [--sky-hour=H --sky-day=D --sky-weather=ID]
##
## X and Z are metres east and south of the square's middle (where the island's
## start is, by default), --high the eye's height over the ground there (1.7 by
## default: standing), --face a point to look toward (or --turn, degrees from
## east toward north), --pitch the player's look up and down (game units, as
## candy_shot's), --tics how long the world runs first. --clean: the picture at
## the window's own resolution, no chunky pixels and no palette (the game's
## PICTURE settings at NATIVE / OFF / FULL COLOUR).
extends SceneTree

var lofi: Lofi
var game
var out := "earth_shot.png"
var _start := -1
var _wait := 30
var _at = null
var _face = null
var _turn = null
var _high := 1.7
var _pitch := 0.0


func _vec(s: String) -> Vector2:
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))


func _init() -> void:
	var clean := false
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			out = a
		elif a.begins_with("--at="):
			_at = _vec(a.substr(5))
		elif a.begins_with("--face="):
			_face = _vec(a.substr(7))
		elif a.begins_with("--turn="):
			_turn = deg_to_rad(float(a.substr(7)))
		elif a.begins_with("--high="):
			_high = float(a.substr(7))
		elif a.begins_with("--pitch="):
			_pitch = float(a.substr(8))
		elif a.begins_with("--tics="):
			_wait = int(a.substr(7))
		elif a == "--clean":
			clean = true
	lofi = Lofi.new()
	root.add_child(lofi)
	if clean:
		lofi.set_filtered(false)
		lofi.pixel_rows = 0
		lofi.render_rows = 0
		lofi.pixel_aspect = 1.0
	game = preload("res://godot/scripts/game/game.gd").new()
	lofi.world.add_child(game)
	process_frame.connect(_frame.bind(clean))


func _frame(clean: bool) -> void:
	if game.player == null or not game.island_ready():
		return
	var p = game.player
	if _start < 0:
		_start = game.tics
		p.health = 100000
		p.debug = true
		lofi.for_island(game.island_spec, not clean)
		# (--nofog, --nosea, --noclouds: for finding what a picture's haze is)
		var args := OS.get_cmdline_user_args()
		if "--nofog" in args:
			var we := game.island.get_node_or_null("WorldEnvironment") as WorldEnvironment
			if we:
				we.environment.fog_enabled = false
		if "--noglow" in args:
			var we2 := game.island.get_node_or_null("WorldEnvironment") as WorldEnvironment
			if we2:
				we2.environment.glow_enabled = false
		if "--nosea" in args and game.island.get_node_or_null("CloudSea"):
			game.island.get_node("CloudSea").visible = false
		if "--noclouds" in args and game.island.get_node_or_null("HorizonClouds"):
			game.island.get_node("HorizonClouds").visible = false
		# (--cine=NAME:VALUE,...: the cinema pass's numbers, for tuning;
		# --cine=off hides it)
		for a in args:
			if a.begins_with("--cine=") and game.island.get_node_or_null("Cinema"):
				var cine := game.island.get_node("Cinema") as MeshInstance3D
				if a == "--cine=off":
					cine.visible = false
					continue
				for kv in a.substr(7).split(","):
					var parts: PackedStringArray = kv.split(":")
					(cine.material_override as ShaderMaterial).set_shader_parameter(parts[0], float(parts[1]))
		# nobody in the way of the picture
		for a in game.actors:
			if a.monster:
				a.remove()
		game.actors = game.actors.filter(func(a): return not a.removed)
	var here := Vector2(p.x / 32.0, -p.y / 32.0) if _at == null else (_at as Vector2)
	p.x = here.x * 32.0
	p.y = -here.y * 32.0
	p.sector = game.level.sector_at(p.x, p.y)
	var f: float = game.level.floor_at(p.x, p.y)
	if f <= IslandLevel.NO_FLOOR:
		# (over the water or off the edge: the field's own ground)
		f = game.island.get_node("IslandWorld").field.base_height(here.x, here.y, 1.0,
				game.island.get_node("IslandWorld").field.island_in_cell(Vector2i.ZERO)) * 32.0
	p.z = f + maxf(_high - 1.7, 0.0) * 32.0
	p.momz = 0.0
	var look_at := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):
			look_at = a.substr(7)
	var sky: Node = game.island.get_node_or_null("EnviroSky")
	if look_at != "" and sky != null:
		# (--look=sun|moon: turned to it, the eye a little under it)
		var v: Vector3 = sky.sun_direction() if look_at == "sun" else sky.moon_direction()
		p.angle = atan2(-v.z, v.x)
		_pitch = clampf(asin(clampf(v.y, -1.0, 1.0)) * 0.9, -0.7, 0.7)
		# (--look-off=DEG,P: turned that many degrees left of it and that much
		# pitch below it, so it sits off the middle of the frame)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--look-off="):
				var o := _vec(a.substr(11))
				p.angle += deg_to_rad(o.x)
				_pitch = clampf(_pitch - o.y, -0.7, 0.7)
	elif _face != null:
		var d: Vector2 = (_face as Vector2) - here
		p.angle = atan2(-d.y, d.x)
	elif _turn != null:
		p.angle = float(_turn)
	p.pitch = _pitch
	if game.tics - _start >= _wait:
		root.get_texture().get_image().save_png(out)
		print("earth_shot: %s at %.0f, %.0f m, %.0f m up" % [out, here.x, here.y, _high])
		quit()
	if game.tics - _start > 6000:
		quit(1)
