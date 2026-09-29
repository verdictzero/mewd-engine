## MEWD — pictures of the Irish potato cannon (game/potatoes.gd).
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/potato_shot.gd -- out.png [mode] [--map=layers]
##
## THE ANNEXE's yard, the cannon in hand, a shopper out in front, and by
## `mode`:
##   flight  a potato lobbed at the shop's wall: bouncing, its trail
##   side    the same, seen from beside its path
##   boom    one at the shopper, a moment after it goes off
##   mushroom  the same, seconds later: the column and the cap
##   wide    the same as mushroom, the eye lifted and backed off
extends SceneTree

var lofi: Lofi
var game
var w3d: Weapon3D
var out := "potato_shot.png"
var mode := "boom"
var frames := 0
var fired_at := -1
var boom_at := -1
var fired_tic := -1
var boom_tic := -1
var shot := false
var shopper = null

func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		mode = pos[1]
	lofi = Lofi.new()
	root.add_child(lofi)
	w3d = Weapon3D.new()
	lofi.gun.add_child(w3d)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.weapon3d = w3d
	lofi.world.add_child(game)
	process_frame.connect(_frame)

func _frame() -> void:
	frames += 1
	if game.player == null:
		return
	var p = game.player
	if frames == 5:
		p.weapon = "POTATO"
		p.x = 300.0
		p.y = 760.0 if mode in ["flight", "side"] else 520.0
		p.angle = 0.0
		p.pitch = 0.05
		p.health = 100000
		if not mode in ["flight", "side"]:
			shopper = game.spawn("SHOPPER", 620.0, 520.0, PI)
			shopper.speed = 0.0
	if frames == 30:
		game.potatoes.launch(p)
		fired_at = frames
		fired_tic = game.tics
	if boom_at < 0 and game.potatoes.blasts > 0:
		boom_at = frames
		boom_tic = game.tics
	# (timed in the game's tics: a frame here may run several)
	var ready := false
	match mode:
		"flight":
			ready = fired_tic >= 0 and game.tics >= fired_tic + 14
		"side":
			ready = fired_tic >= 0 and game.tics >= fired_tic + 26
		"boom":
			ready = boom_tic >= 0 and game.tics >= boom_tic + 5
		"mushroom", "wide":
			ready = boom_tic >= 0 and game.tics >= boom_tic + 50
	var at := frames if ready and not shot else -1
	# SIDE: from beside the potato's path, once it is on its way
	if mode == "side" and fired_tic >= 0:
		p.x = 520.0
		p.y = 1180.0
		p.angle = -PI / 2.0 - 0.3
		p.pitch = 0.1
	if mode == "wide" and boom_at > 0:
		game.eye_hook = Vector2(260.0, -8.0)
		p.x = 60.0
	if at > 0 and frames == at:
		shot = true
		var img: Image = root.get_texture().get_image()
		img.save_png(out)
		print("potato_shot: %s at frame %d — fired %d, bounces %d, blasts %d" % [mode, frames, game.potatoes.fired, game.potatoes.bounces, game.potatoes.blasts])
		quit()
	if frames > 900:
		print("potato_shot: gave up (fired %d, bounces %d, blasts %d)" % [game.potatoes.fired, game.potatoes.bounces, game.potatoes.blasts])
		quit(1)
