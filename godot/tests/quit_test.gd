## MEWD — the main scene, played and left: a game started on a map, a
## few seconds of it, QUIT TO TITLE from the pause menu, the title, and a
## second game after it (at the user's request: the game crashed on the
## way back to the main menu). Fails on an engine error or a stall.
##   godot47 --script res://godot/tests/quit_test.gd -- --map=candyland
extends SceneTree

var main: Node
var step := 0
var t0 := 0
var games := 0
## the guns tried before leaving: [weapon, tics held]
const ARMS := [["MINIGUN", 60], ["LANCE", 7 * 35 + 6], ["LAUNCHER", 90], ["ARC", 80]]
var arm := 0
var fire0 := 0

func _arm(g, a: Array) -> void:
	var p = g.player
	p.health = 100000
	for k in p.ammo:
		p.ammo[k] = 999
	p.weapon = a[0]
	p.pending_weapon = ""
	p.pitch = -0.08
	g._autofire = true

func _init() -> void:
	main = load("res://godot/scenes/main.tscn").instantiate()
	root.add_child(main)
	# (so reload_current_scene, which QUIT TO TITLE uses, has one to reload)
	current_scene = main
	t0 = Time.get_ticks_msec()
	process_frame.connect(_frame)

## the main scene: the tree's own current scene once it has one (a
## reload replaces it), the one added here before that
func _main() -> Node:
	return current_scene if current_scene != null else main

func _frame() -> void:
	var m := _main()
	var el := Time.get_ticks_msec() - t0
	if el > 240000:
		print("quit: FAIL stalled at step %d (main %s, title %s, game %s)" % [step, m, m.get("title"), m.get("game")])
		quit(1)
		return
	match step:
		0:
			if m.get("title") != null or m.get("forest") != null:
				m.no_drop = true
				m.start_game()
				step = 1
		1:
			if m.game != null and m.game.island_ready() and m.game.tics > 70 and m.get("_loading") == false:
				games += 1
				print("quit: game %d up, %d tics" % [games, m.game.tics])
				_arm(m.game, ARMS[0])
				fire0 = m.game.tics
				arm = 0
				step = 4
		4:
			# EACH GUN HELD DOWN in the real game, drawn: the trigger as the
			# player's, for HOLD tics, then let go, then the next
			var g = m.game
			if g.tics - fire0 >= int(ARMS[arm][1]):
				g._autofire = false
				print("quit: %s held %d tics, let go (%d fps)" % [ARMS[arm][0], g.tics - fire0, Engine.get_frames_per_second()])
				arm += 1
				if arm >= ARMS.size():
					step = 5
					fire0 = g.tics
				else:
					_arm(g, ARMS[arm])
					fire0 = g.tics
		5:
			if m.game.tics - fire0 > 60:
				m.toggle_pause()
				m.quit_to_title()
				step = 2
				t0 = Time.get_ticks_msec()
		2:
			# the scene reloaded: a new main, on its title
			if m != main and is_instance_valid(m) and m.get("game") == null and m.get("lofi") != null:
				main = m
				print("quit: back on the title")
				if games >= 2:
					print("quit: OK")
					quit(0)
					return
				step = 3
				t0 = Time.get_ticks_msec()
		3:
			if Time.get_ticks_msec() - t0 > 1500:
				m.no_drop = true
				m.start_game()
				step = 1
