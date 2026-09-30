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
var fps_label: Label
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
	fps_label = Label.new()
	fps_label.position = Vector2(12, 680)
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
	# MEWD EDITOR (godot/scripts/editor/): --edit, or F2 back from the game
	if args.has("--edit") or MewdEditor.open_next:
		MewdEditor.open_next = false
		show_editor()
		return
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
	elif straight:
		start_game()
	elif args.has("--terminal"):
		show_terminal()
	else:
		show_title()

var terminal: Terminal
var _jesse := false

func show_terminal() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	terminal = Terminal.new()
	layer.add_child(terminal)
	terminal.open_game.connect(func(): layer.queue_free(); show_title())
	terminal.open_jesse.connect(func(): layer.queue_free(); _jesse = true; start_game())
	terminal.open_join.connect(func(where: String): layer.queue_free(); join_host(where))
	terminal.open_editor.connect(func(): layer.queue_free(); show_editor())

## MEWD EDITOR, over everything: its Play (F5) hands the map to the game,
## F2 in the game comes back to it (back_to_editor), and its File menu's
## "Back to the terminal" goes back to the prompt.
var editor: MewdEditor
func show_editor() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	editor = MewdEditor.new()
	editor.from_title = MewdEditor.came_from_title
	layer.add_child(editor)
	editor.play_requested.connect(func(doc: Dictionary):
		layer.queue_free()
		editor = null
		# the map's own textures, drawn for the game (texcompose.js)
		EdTex.register_all(doc)
		start_game())
	editor.quit_requested.connect(func():
		layer.queue_free()
		editor = null
		MewdEditor.came_from_title = false
		show_title())

## F2, from the game: back to the editor, on the map as it was left
## (its autosave), as the web build's ?edit is.
func back_to_editor() -> void:
	MewdEditor.open_next = true
	if game != null and game.net != null:
		game.net.close()
	get_tree().reload_current_scene()

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
	# the logo's shadows, inside the picture and so under the dither
	shade = Control.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lofi.world.add_child(shade)
	lofi.set_tint(TitleForest.BLUE)
	title_layer = CanvasLayer.new()
	title_layer.layer = 2
	add_child(title_layer)
	title = Title.new()
	title_layer.add_child(title)
	title.attach_shade(shade)
	title.new_game.connect(start_game)
	title.open_editor.connect(_title_to_editor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## MAP EDITOR, from the title: the title and its forest put away, and
## the editor's "Back" comes back to the title rather than the terminal
## (MewdEditor.came_from_title, which outlives a play-test and F2).
func _title_to_editor() -> void:
	if forest != null:
		forest.queue_free()
		shade.queue_free()
		title_layer.queue_free()
		forest = null
		title = null
	lofi.set_tint(Color.WHITE)
	MewdEditor.came_from_title = true
	show_editor()

var _loading := false
func start_game() -> void:
	if game != null or _loading:
		return
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
	if _jesse:
		game.map_name = "jesse"
	# a test run of a map from the editor
	var from_editor: bool = MewdEditor.play_doc != null
	if from_editor:
		game.play_doc = MewdEditor.play_doc
		MewdEditor.play_doc = null
	# a host's world, if this is a match: the map is its seed
	if net_client != null:
		game.net_map = net_client.map
	game.weapon3d = w3d
	game.sound = sound
	lofi.world.add_child(game)
	# and from here on this game is one player in the host's world
	if net_client != null:
		var ng := NetGame.new(game, net_client)
		ng.bot = _arg("--netbot")
		ng.bot_fire = not OS.get_cmdline_user_args().has("--netbot=look")
	sound.listener = game.player
	sound.layered = game.level != null and game.level.layered
	var hud := Hud.new()
	hud.game = game
	hud_layer.add_child(hud)
	game.hud = hud
	# ON A TEST RUN FROM THE EDITOR, a way back that is always on screen
	if from_editor:
		var b := Button.new()
		b.text = "◀ EDITOR  F2"
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", Color("#14161d"))
		b.add_theme_color_override("font_hover_color", Color("#14161d"))
		for st in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("#ffd257") if st == "hover" else Color(232 / 255.0, 195 / 255.0, 74 / 255.0, 0.88)
			sb.border_color = Color("#e8c34a")
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(4)
			sb.content_margin_left = 10
			sb.content_margin_right = 10
			sb.content_margin_top = 6
			sb.content_margin_bottom = 6
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(back_to_editor)
		hud_layer.add_child(b)
		b.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
		b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch"):
		touch_layer = CanvasLayer.new()
		touch_layer.layer = 2
		add_child(touch_layer)
		touch = TouchControls.new()
		touch_layer.add_child(touch)
		game.touch = touch
	music.start(0)
	apply_prefs(pause.prefs)
	if OS.get_cmdline_user_args().has("--pause"):
		toggle_pause.call_deferred()
	if not _shooting() and touch == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if loading != null:
		# the first frames of the world, under the screen: every shader it
		# draws with compiles now rather than on the first look round
		for i in 4:
			loading.at("WARMING UP THE SHADERS", 0.6 + 0.1 * i)
			await RenderingServer.frame_post_draw
		loading.finish()

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
	# (a --shot of a match counts its frames from the world being up, not
	# from the handshake)
	if not _joining:
		_frames += 1
	_quit_after()
	if touch != null:
		touch.visible = game != null and not pause.visible
		if touch.pause_pulse:
			touch.pause_pulse = false
			toggle_pause()
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
		# and where the time goes, from the game's own clock (Game.prof_text)
		if game != null:
			game._prof_on = true
			var t: String = game.prof_text()
			if t != "":
				fps_label.text += "   " + t
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
	lofi._resize()
	lofi.set_picture(float(p.bright), float(p.contrast), float(p.gamma))
	lofi.mat.set_shader_parameter("snap", 1.0 if p.snap else 0.0)
	lofi.mat.set_shader_parameter("dither", 1.0 if p.snap else 0.0)
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

func quit_to_title() -> void:
	pause.visible = false
	# leaving a match says goodbye to the host
	if game != null and game.net != null:
		game.net.close()
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if game != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		get_viewport().set_input_as_handled()
		back_to_editor()
		return
	if game != null and event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if game != null and not game.paused:
		game.handle_input(event)
