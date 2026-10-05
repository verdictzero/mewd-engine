## MEWD — the root: the picture's layers, top to bottom, and what is
## in the buffer at the bottom of them.
##
##   the title menu     a CanvasLayer (Title), while the title is up
##   the HUD            a CanvasLayer, not filtered
##   the lo-fi filter   Lofi's TextureRect over its buffers
##   the gun            Weapon3D, in a world of its own (Lofi.gun)
##   the world          the Game — or the title's forest — inside Lofi.world
##
## The title comes first, over its own level; NEW GAME builds the map,
## starts the music, and takes the mouse. `--play` (or a --shot without
## --title) goes straight into the game, for the tests.
extends Node

var lofi: Lofi
var game: Node3D
var hud_layer: CanvasLayer
var title_layer: CanvasLayer
var title: Title
var forest: TitleForest
var shade: Control
var sound: Sound
var music: Music
var pause_layer: CanvasLayer
var pause: PauseMenu
## the performance overlay (ui/perf.gd): FRAME RATE in the pause menu
var fps_label: PerfOverlay
var touch_layer: CanvasLayer
var touch: TouchControls
var rotate_notice: RotateNotice

## A MATCH (godot/scripts/net/): the dedicated server this process is, or
## the line to the host this game is one player of
var host: NetHost
var net_client: NetClient

func _ready() -> void:
	# THE DEDICATED SERVER (--server[=PORT]): no picture, no sound, no title
	# — the simulation behind a socket (godot/scripts/net/host.gd)
	if _arg("--server"):
		host = NetHost.new()
		host.name = "Host"
		add_child(host)
		return
	# (what the last run was doing, if it did not end cleanly: BlackBox)
	BlackBox.previous()
	# AND THE WHOLE RUN'S LOG, mirrored to the phone's shared storage
	# (Logs: it asks for the storage permission on Android)
	Logs.setup(get_tree())
	lofi = Lofi.new()
	add_child(lofi)
	sound = Sound.new()
	add_child(sound)
	music = Music.new()
	add_child(music)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 3
	add_child(pause_layer)
	pause = PauseMenu.new()
	pause.visible = false
	pause_layer.add_child(pause)
	pause.resumed.connect(resume)
	pause.quit_to_title.connect(quit_to_title)
	pause.pad_setup.connect(open_pad_wizard)
	pause.debug_menu.connect(open_debug)
	fps_label = PerfOverlay.new()
	fps_label.visible = false
	hud_layer.add_child(fps_label)
	# a phone held upright is told to turn; above everything
	var rot_layer := CanvasLayer.new()
	rot_layer.layer = 20
	add_child(rot_layer)
	rotate_notice = RotateNotice.new()
	rot_layer.add_child(rotate_notice)
	var args := OS.get_cmdline_user_args()
	var straight: bool = args.has("--play") or (_shooting() and not args.has("--title") and not args.has("--terminal"))
	# STRAIGHT INTO THE MEWD MAIN MENU, at the user's request (the web
	# build opens on a terminal; --terminal still does here) — unless the
	# command line says where to go, as the web build's URL does
	var join := ""
	for a in args:
		if a.begins_with("--join="):
			join = a.substr(7)
		elif a == "--join":
			join = "127.0.0.1:%d" % NetProtocol.DEFAULT_PORT
	if join != "":
		join_host(join)
	elif again != "":
		# YOU DIED, and asked for the level again (Game.restart_wanted)
		_chosen_map = again
		again = ""
		start_game()
	elif straight:
		start_game()
	elif args.has("--terminal"):
		show_terminal()
	else:
		show_title()

var terminal: Terminal

## WHERE THE LOGS ARE (Logs), small, at the foot of the title on the
## right — and whether the phone gave the storage permission. A button:
## tapped, it opens the DEBUG menu (open_debug). (The title's notice of
## the last run's failure is gone, at the user's request: the DEBUG
## menu's LAST FAILURE shows it.)
class _LogsNote extends Button:
	func refresh() -> void:
		text = Logs.where()

func _logs_note() -> Control:
	var l := _LogsNote.new()
	l.text = Logs.where()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.75, 0.8, 0.78, 0.8))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_hover_color", Color(1, 1, 0.8))
	l.add_theme_color_override("font_pressed_color", Color(1, 1, 0.6))
	l.flat = true
	l.focus_mode = Control.FOCUS_NONE
	l.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# (in the corner by its anchors, 8 pixels in: a bare position here
	# put it off the top of the glass)
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	if not Logs.granted():
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 0.9))
	l.pressed.connect(open_debug)
	# (the permission's answer comes after the title is up; a method on
	# the note, never a lambda of this scene, which the note outlives)
	Logs.changed = l.refresh
	return l

func show_terminal() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	terminal = Terminal.new()
	layer.add_child(terminal)
	terminal.open_game.connect(func(): layer.queue_free(); show_title())
	terminal.open_join.connect(func(where: String): layer.queue_free(); join_host(where))

## JOIN A HOST (js/main.js joinHost): say hello, wait for the welcome —
## which names the map — and build that world as one player in it. On
## failure, back to the title (and why, in the log).
var _joining := false
func join_host(where: String) -> void:
	_joining = true
	var url := NetProtocol.url_for(where)
	var nm := "PLAYER %d" % (100 + randi() % 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			nm = a.substr(7)
	nm = nm.to_upper().substr(0, 16)
	print("MEWD: joining %s as %s" % [url, nm])
	var t := NetTransport.Ws.new(null, url)
	var c := NetClient.new(t, nm)
	var until := Time.get_ticks_msec() + 8000
	while c.welcome == null and not c.closed and Time.get_ticks_msec() < until:
		c.poll()
		await get_tree().process_frame
	_joining = false
	if c.welcome == null:
		var why: String = str(c.refused) if c.refused != null else (str(c.bye) if c.bye != null else
			("nobody answered" if c.closed or not t.open else "no answer in eight seconds"))
		push_warning("could not join %s: %s" % [url, why])
		print("MEWD: could not join %s: %s" % [url, why])
		t.close()
		if _arg("--netbot"):
			get_tree().quit(2)
			return
		show_title()
		return
	print("MEWD: joined %s as %s, player %d: %s seed %d" % [url, nm, c.id, str(c.map.kind), int(c.map.seed)])
	net_client = c
	start_game()

func show_title() -> void:
	forest = TitleForest.new()
	lofi.world.add_child(forest)
	lofi.set_tint(TitleForest.BLUE)
	title_layer = CanvasLayer.new()
	title_layer.layer = 2
	add_child(title_layer)
	# the logo's shadows, IN FRONT OF the dither now (at the user's request),
	# on the title's own layer under the logo, at the screen's resolution
	shade = Control.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(shade)
	title = Title.new()
	title_layer.add_child(title)
	title.attach_shade(shade)
	title.new_game.connect(func(m: String): _chosen_map = m; start_game())
	title_layer.add_child(_logs_note())
	title.pad_setup.connect(open_pad_wizard)
	title.debug_menu.connect(open_debug)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Pad.watch()

var _loading := false
## the level picked on the title (NEW GAME), "" for the default
var _chosen_map := ""
## (a test that plays through the title sets this to begin on the ground)
var no_drop := false
func start_game() -> void:
	if game != null or _loading:
		return
	BlackBox.mark("start game " + (_chosen_map if _chosen_map != "" else "(default)"))
	# THE LOADING SCREEN (ui/loading.gd), drawn before the build blocks —
	# a frame for it to be seen, then the build, then a few frames of the
	# world under it while the shaders compile, then it fades (not for a
	# test's --shot, whose frames are counted from here)
	var loading: LoadingScreen = null
	if not _shooting():
		_loading = true
		var ll := CanvasLayer.new()
		ll.layer = 15
		add_child(ll)
		loading = LoadingScreen.new()
		ll.add_child(loading)
		loading.tree_exited.connect(ll.queue_free)
		loading.at("BUILDING THE MAP", 0.15)
		await get_tree().process_frame
		await get_tree().process_frame
		_loading = false
		if not is_inside_tree():
			return
	if forest != null:
		forest.queue_free()
		shade.queue_free()
		title_layer.queue_free()
		forest = null
		title = null
	lofi.set_tint(Color.WHITE)
	var w3d := Weapon3D.new()
	lofi.gun.add_child(w3d)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.name = "Game"
	if _chosen_map != "":
		game.map_name = _chosen_map
		_chosen_map = ""
	# a host's world, if this is a match: the map is its seed
	if net_client != null:
		game.net_map = net_client.map
	game.weapon3d = w3d
	game.sound = sound
	# THE DROP: a game begun from the title comes down from orbit in the
	# pod (DropPod) — not a picture, not a match, not with --nodrop
	game.drop_in = not no_drop and not _arg("--nodrop") and net_client == null and not _shooting()
	# a headless bot in a match looks at nothing: the island's ground only
	if _arg("--netbot") and DisplayServer.get_name() == "headless":
		game.draw_world = false
	# (the pod hangs at the top until the loading screen is gone)
	game.loading = loading != null
	lofi.world.add_child(game)
	# and from here on this game is one player in the host's world
	if net_client != null:
		var ng := NetGame.new(game, net_client)
		ng.bot = _arg("--netbot")
		ng.bot_fire = not OS.get_cmdline_user_args().has("--netbot=look")
	# THE ISLAND, raised under the loading screen: its terrain off the bake
	# (or meshed, without one) and its plants planted, before anybody sees
	# it — and a picture's frames are counted from there
	var waited := 0
	while not game.island_ready():
		waited += 1
		if loading != null:
			loading.at("RAISING THE ISLAND", minf(0.55, 0.2 + waited * 0.002))
		await get_tree().process_frame
		# (left for the title while it was still loading: nothing more to do)
		if not is_inside_tree() or game == null:
			return
	_frames = 0
	BlackBox.mark("island up")
	sound.listener = game.player
	sound.layered = game.level != null and game.level.layered
	var hud := Hud.new()
	hud.game = game
	hud_layer.add_child(hud)
	game.hud = hud
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"):
		touch_layer = CanvasLayer.new()
		touch_layer.layer = 2
		add_child(touch_layer)
		touch = TouchControls.new()
		touch_layer.add_child(touch)
		game.touch = touch
	# an island with its own music plays that, crossfading round and round
	# (Islands "music": CANDY LAND); the others the three remixes
	var own: Array = game.island_spec.get("music", [])
	if own.is_empty():
		music.start(0)
	else:
		music.start_list(own)
	apply_prefs(pause.prefs)
	if OS.get_cmdline_user_args().has("--pause"):
		toggle_pause.call_deferred()
	if not _shooting() and touch == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if loading != null:
		# the first frames of the world, under the screen: every shader it
		# draws with compiles now rather than on the first look round —
		# and everything the level has built but not shown yet (every gun,
		# the rockets, the sparks, the scopes) drawn too (Warmup)
		var warm := Warmup.begin([game, lofi.gun])
		# and a mark of every kind on the ground ahead, in view, so every
		# decal shader is compiled here and not at the first shot
		var p = game.player
		var ax: float = p.x + cos(p.angle) * 120.0
		var ay: float = p.y + sin(p.angle) * 120.0
		var s: Level.Sector = game.level.span_at(ax, ay, p.z + 1.0)
		var wat := Vector3(ax, ay, s.floor if s else p.z)
		game.decals.warm_begin(wat)
		game.gore_decals.warm_begin(wat)
		for i in 4:
			loading.at("WARMING UP THE SHADERS", 0.6 + 0.1 * i)
			await RenderingServer.frame_post_draw
			if not is_inside_tree() or game == null:
				return
		game.decals.warm_end()
		game.gore_decals.warm_end()
		Warmup.end(warm)
		loading.finish()
	game.loading = false
	BlackBox.mark("playing")

## What the BlackBox keeps of the game, twice a second
func _box_state() -> String:
	var p = game.player
	if p == null:
		return "map %s, loading" % game.get("map_name")
	var t := "map %s, tic %d, %d fps, %s%s" % [str(game.get("map_name")), int(game.tics),
		Engine.get_frames_per_second(), p.weapon,
		(" charge %d (stage %d)" % [p.charge, p.charge_stage()]) if p.charge > 0 else ""]
	if p.beam_tics > 0:
		t += " beam out %d" % p.beam_tics
	if pause.visible:
		t += ", paused"
	t += "\nactors %d (%d asleep), gibs %d, gore %d, pieces %d" % [game.actors.size(), game.asleep, game.giblets.chunks.count,
		game.fx.gore.count, game.chunks.count() if game.chunks != null else 0]
	return t

static func _arg(prefix: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return true
	return false

static func _shooting() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			return true
	return false

## --shot=path.png [--shot-frames=N]: save the picture after N frames and
## quit — how the port is checked without a screen
var _frames := 0

func _process(_dt: float) -> void:
	if host != null:
		return
	if game != null and is_instance_valid(game):
		BlackBox.state(_box_state())
	# (a --shot of a match counts its frames from the world being up, not
	# from the handshake)
	if not _joining:
		_frames += 1
	_quit_after()
	if touch != null:
		# and off the picture while a pad is in charge (Pad.held)
		touch.visible = game != null and not pause.visible and not Pad.held
		if touch.pause_pulse:
			touch.pause_pulse = false
			toggle_pause()
	# the beam in the eye: the picture swims (Lofi.set_wobble)
	var wob := 0.0
	if game != null and is_instance_valid(game) and game.player != null:
		wob = clampf(float(game.player.wobble) / RainbowBeams.UNI.wobble_tics, 0.0, 1.0)
	lofi.set_wobble(wob)
	if game != null and is_instance_valid(game) and game.restart_wanted:
		game.restart_wanted = false
		restart()
	if fps_label.visible:
		fps_label.game = game
		fps_label.lofi = lofi
	var shot := ""
	var at := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--shot-frames="):
			at = int(a.substr(14))
	if shot != "" and _frames == at:
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(shot)
		get_tree().quit()

## Every setting, from the pause menu's prefs, into the systems it steers.
func apply_prefs(p: Dictionary) -> void:
	lofi.render_rows = int(p.detail)
	lofi.pixel_rows = int(p.pixels)
	lofi.pixel_aspect = float(p.pixar)
	lofi.grid_mode = str(p.get("grid", "lcd"))
	lofi._resize()
	lofi.set_picture(float(p.bright), float(p.contrast), float(p.gamma))
	# (an island may keep its own colours and set its own exposure and
	# tonemap — CANDY LAND, at the user's request: Islands "palette",
	# "exposure", "knee")
	lofi.for_island(game.island_spec if game != null else {}, bool(p.snap))
	music.set_volume(float(p.music))
	fps_label.visible = bool(p.fps)
	if game != null:
		game.look_sens = float(p.sens)
		game.invert = bool(p.invert)
		if touch != null:
			touch.lefty = bool(p.get("lefty", false))
		# (a match's rules, not the menu's, on a network)
		if game.net == null:
			game.player.debug = bool(p.debug)
			game.player.invincible = bool(p.godmode)
		if game.weather.kind != str(p.weather) and not _arg("--weather="):
			game.weather.kind = str(p.weather)
		if absf(float(p.hour) - game._set_hour) > 1e-3 and not _arg("--hour="):
			game._set_hour = float(p.hour)
			game.weather.hour = float(p.hour)

## --quit-after=S: leave after S seconds (the network test's clients),
## printing what this client saw of the match on the way
var _quit_ms := -2
func _quit_after() -> void:
	if _quit_ms == -2:
		_quit_ms = -1
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--quit-after="):
				_quit_ms = Time.get_ticks_msec() + int(float(a.substr(13)) * 1000.0)
	if _quit_ms < 0 or Time.get_ticks_msec() < _quit_ms:
		return
	_quit_ms = -1
	if game != null and game.net != null:
		var n: NetGame = game.net
		var rep := {"id": n.client.id, "snaps": n.client.snaps, "puppets": n.most_puppets, "sent": n.client.transport.sent,
			"corrections": n.corrections, "biggest": snappedf(n.biggest, 0.01), "frags": game.player.frags,
			"rtt": roundi(n.client.rtt), "lost": n.lost}
		print("MEWD client: " + JSON.stringify(rep))
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--report="):
				var f := FileAccess.open(a.substr(9), FileAccess.WRITE)
				if f:
					f.store_string(JSON.stringify(rep))
		n.close()
	get_tree().quit(0)

func toggle_pause() -> void:
	if game == null:
		return
	if pause.visible:
		resume()
	else:
		pause.visible = true
		game.paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume() -> void:
	pause.visible = false
	if game != null:
		game.paused = false
		if touch == null:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## BACK TO THE TITLE, in stages (at the user's request: it crashed on the
## handheld here), each one marked in the BlackBox: the sound stopped, the
## game and everything drawn for it let go, a frame for that to happen,
## and only then the scene built again
var _quitting := false
## the level to start again straight away once the scene is built afresh
## (a static: it lives through reload_current_scene)
static var again := ""
func restart() -> void:
	if game == null or _quitting:
		return
	again = str(game.map_name)
	quit_to_title()

func quit_to_title() -> void:
	if _quitting:
		return
	_quitting = true
	BlackBox.mark("quit to title: begin")
	pause.visible = false
	# leaving a match says goodbye to the host
	if game != null and game.net != null:
		game.net.close()
	BlackBox.mark("quit to title: sound off")
	for c in sound.get_children():
		if c is AudioStreamPlayer:
			c.stop()
			c.queue_free()
	if music != null:
		music.process_mode = Node.PROCESS_MODE_DISABLED
	BlackBox.mark("quit to title: game off")
	if game != null:
		game.process_mode = Node.PROCESS_MODE_DISABLED
		for c in hud_layer.get_children():
			if c != fps_label:
				c.queue_free()
		if touch_layer != null:
			touch_layer.queue_free()
			touch_layer = null
			touch = null
		for c in lofi.gun.get_children():
			c.queue_free()
		game.queue_free()
		game = null
	await get_tree().process_frame
	await get_tree().process_frame
	BlackBox.mark("quit to title: reloading the scene")
	get_tree().reload_current_scene()

## SET UP THE PAD (ui/pad_wizard.gd), from the title or the pause menu:
## over everything, taking every press until it is done
var pad_wizard: PadWizard

func open_pad_wizard() -> void:
	if pad_wizard != null and is_instance_valid(pad_wizard):
		return
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	pad_wizard = PadWizard.new()
	layer.add_child(pad_wizard)
	pad_wizard.finished.connect(func(): layer.queue_free(); pad_wizard = null)

## THE DEBUG MENU (ui/debug_menu.gd): the logs, the last failure, the
## storage ask — over everything but the pad wizard
var debug_menu: DebugMenu
func open_debug() -> void:
	if debug_menu != null and is_instance_valid(debug_menu):
		return
	var layer := CanvasLayer.new()
	layer.layer = 39
	add_child(layer)
	debug_menu = DebugMenu.new()
	layer.add_child(debug_menu)
	debug_menu.closed.connect(func(): layer.queue_free(); debug_menu = null)

## ANDROID'S BACK (a handheld's Select is often it): never a quit
## (application/config/quit_on_go_back is off) — the pause menu, or out
## of it
func _exit_tree() -> void:
	# (the log's mirror out before the engine goes: Logs)
	Logs.shutdown()

func _notification(what: int) -> void:
	# (a run that ends because it was closed, or is put away, is not a crash)
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			BlackBox.clean()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		BlackBox.mark("app in background")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		BlackBox.mark("app back")
		# (back from the storage page, perhaps: Logs)
		Logs.resumed()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if pad_wizard != null and is_instance_valid(pad_wizard):
			return
		if debug_menu != null and is_instance_valid(debug_menu):
			debug_menu.closed.emit()
			return
		if game != null:
			toggle_pause()

## WHO IS IN CHARGE, decided before anything else sees the event: a
## pad's press or push takes the controls, a finger on the glass takes
## them back (js/input.js setPadHeld)
func _input(event: InputEvent) -> void:
	if Pad.is_pad(event):
		Pad.held = true
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		Pad.held = false

func _unhandled_input(event: InputEvent) -> void:
	if game != null and event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	# YOU DIED, and the burst over: ANY key, button or touch is for the
	# level again (Hud: PRESS ANY KEY TO DIE ALONE)
	if game != null and not game.paused and game.death != null and game.death.can_restart() and event.is_pressed() \
			and not event.is_echo() and (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton or event is InputEventScreenTouch):
		game.restart_wanted = true
		get_viewport().set_input_as_handled()
		return
	if game != null and not game.paused:
		game.handle_input(event)
