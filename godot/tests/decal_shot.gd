## MEWD — a picture of the flamethrower's spot heating and its scorch
## (render/decals.gd heat): the stream held on the hedge for three
## seconds, let go, and the spot left to cool — the glow while it burns,
## the scorch when it has gone cold.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/decal_shot.gd -- out.png [hot|cold]
extends SceneTree

var lofi: Lofi
var game
var out := "decal_shot.png"
var mode := "cold"
var frames := 0

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
	var w3d := Weapon3D.new()
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
		p.weapon = "FLAMER"
		p.health = 100000
		p.pitch = 0.0
	# three seconds of the stream, then let go
	game._autofire = frames > 5 and game.tics < 105
	var want_tics := 100 if mode == "hot" else 105 + 7 * 35
	if game.tics >= want_tics:
		var img: Image = root.get_texture().get_image()
		img.save_png(out)
		print("decal_shot: %s at tic %d — heat spots live %d, scorches %d, holes pool next %d" % [mode, game.tics, game.decals._hlive, game.decals.scorches, game.decals.pools.hole.next])
		quit()
	if frames > 1500:
		print("decal_shot: gave up")
		quit(1)
