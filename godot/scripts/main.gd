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

func _ready() -> void:
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
	var args := OS.get_cmdline_user_args()
	var straight: bool = args.has("--play") or (_shooting() and not args.has("--title") and not args.has("--terminal"))
	# the terminal first, as the web build opens on it — unless the
	# command line says where to go, as the web build's URL does
	if straight:
		start_game()
	elif args.has("--title") or _arg("--map=") or _arg("--seed="):
		show_title()
	else:
		show_terminal()

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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_game() -> void:
	if game != null:
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
	if _jesse:
		game.map_name = "jesse"
	game.weapon3d = w3d
	game.sound = sound
	lofi.world.add_child(game)
	sound.listener = game.player
	var hud := Hud.new()
	hud.game = game
	hud_layer.add_child(hud)
	game.hud = hud
	music.start(0)
	apply_prefs(pause.prefs)
	if OS.get_cmdline_user_args().has("--pause"):
		toggle_pause.call_deferred()
	if not _shooting():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	_frames += 1
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
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
		game.player.debug = bool(p.debug)
		game.player.invincible = bool(p.godmode)
		game.weather.fire_haze = bool(p.haze)
		if game.weather.kind != str(p.weather) and not _arg("--weather="):
			game.weather.kind = str(p.weather)
		if absf(float(p.hour) - game._set_hour) > 1e-3 and not _arg("--hour="):
			game._set_hour = float(p.hour)
			game.weather.hour = float(p.hour)

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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func quit_to_title() -> void:
	pause.visible = false
	get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	if game != null and event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if game != null and not game.paused:
		game.handle_input(event)
