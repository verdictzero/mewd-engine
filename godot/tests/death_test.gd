## MEWD — the dead are gone, headless: a shopper shot, one frozen and
## struck, one burnt to ash, a trooper shot down and one blown apart, and
## after each, the actor removed AND its sprite row let go with its scale
## zeroed (the standee shader reads that scale: a zero row draws nothing).
##   godot --headless --script res://godot/tests/death_test.gd
extends SceneTree

var game
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	for a in game.actors:
		if a.monster:
			a.remove()
	var p = game.player
	var cases := [
		["SHOPPER", "shot", func(a): a.health = 0; a.die(p)],
		["SHOPPER", "frozen and struck", func(a): a.frozen = true; a.die(p)],
		["SHOPPER", "burnt to ash", func(a): a.collapse(p)],
		["SWAT", "shot down", func(a): a.health = 0; a.die(p)],
		["SWAT", "blown apart", func(a): a.health = -100; a.die(p, 0, {"gib": true})],
		["ARMY", "shot down", func(a): a.health = 0; a.die(p)],
	]
	for c in cases:
		var a: Actor = game.spawn(c[0], p.x + 80.0, p.y, 0.0)
		_draw(3)
		var sl = game.standees.slots.get(a.id)
		check(sl != null, "%s %s: drawn while alive" % [c[0], c[1]])
		c[2].call(a)
		# the death animation, the lie and the removal: at most four seconds
		var t := 0
		while not a.removed and t < 140:
			game.tic()
			_draw(1)
			t += 1
		_draw(1)
		check(a.removed, "%s %s: gone from the world (%d tics)" % [c[0], c[1], t])
		check(not game.standees.slots.has(a.id), "%s %s: its sprite row let go" % [c[0], c[1]])
		if sl != null:
			var s = game.standees.strips[sl[0]]
			var i: int = sl[1] * 16
			var reused := false
			for k in game.standees.slots:
				var o = game.standees.slots[k]
				if o[0] == sl[0] and o[1] == sl[1]:
					reused = true
			check(reused or (s.rows[i] == 0.0 and s.rows[i + 5] == 0.0 and s.rows[i + 10] == 0.0),
				"%s %s: the row's scale is zero, so it draws nothing" % [c[0], c[1]])
	var sh := FileAccess.get_file_as_string("res://godot/shaders/standee.gdshader")
	check(sh.contains("length(MODEL_MATRIX[1].xyz)"), "the standee shader reads the row's scale")
	print("death: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)

func _draw(n: int) -> void:
	for k in n:
		game.standees.draw(game.actors, game.camera.position, game.tics + 100000 + k + randi() % 1000)
