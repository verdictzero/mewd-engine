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
	var args := OS.get_cmdline_user_args()
	var straight: bool = args.has("--play") or (_shooting() and not args.has("--title"))
	if straight:
		start_game()
	else:
		show_title()

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
	game.weapon3d = w3d
	game.sound = sound
	lofi.world.add_child(game)
	sound.listener = game.player
	var hud := Hud.new()
	hud.game = game
	hud_layer.add_child(hud)
	game.hud = hud
	music.start(0)
	if not _shooting():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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

func _unhandled_input(event: InputEvent) -> void:
	if game != null:
		game.handle_input(event)
