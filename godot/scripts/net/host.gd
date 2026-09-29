## MEWD — the dedicated server (tools/server.mjs, in Godot).
##
##   godot --headless --path . -- --server[=PORT] [--map=jesse|maze] [--seed=N]
##                                [--max=16] [--frags=N]
##
## A host with no screen: the real simulation (game.gd, not drawn) behind
## the message interface (server.gd), listening on the LAN for WebSocket
## lines at ws://this-machine:PORT/net (any path is taken). THE SAME WIRE
## as the Node host, so a web page joins it with ?join=this-machine:PORT
## and a Godot client with --join=this-machine:PORT.
##
## Team deathmatch on JESSE (the default, as the Node host's), deathmatch
## on THE MAZE — whose crowd stays home: shoppers are a mind each, run on
## every machine by its own dice, and a match is about the players.
##
## And for the tests:
##   --spawns=x,y;x,y;…    a deathmatch's pads, instead of find_spawns
##   --quit-after=S        close after S seconds
##   --score-file=PATH     the last score table, as JSON, written as it
##                         changes and on the way out
class_name NetHost
extends Node

var port := NetProtocol.DEFAULT_PORT
var game
var sim: SimServer
var listener := NetTransport.Listener.new()
var quit_at := -1
var score_file := ""
var _last_score := ""
var _seen := {}
var _t0 := 0

func _ready() -> void:
	var kind := "jesse"
	var seed := 0
	var max_p := NetProtocol.MAX_PLAYERS
	var rules := {}
	var spawns := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			port = int(a.substr(9))
		elif a.begins_with("--map="):
			kind = a.substr(6)
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--max="):
			max_p = clampi(int(a.substr(6)), 1, 64)
		elif a.begins_with("--frags="):
			rules["fragLimit"] = int(a.substr(8))
			rules["teamLimit"] = int(a.substr(8))
		elif a.begins_with("--spawns="):
			for pt in a.substr(9).split(";", false):
				var xy := pt.split(",")
				if xy.size() >= 2:
					spawns.append([float(xy[0]), float(xy[1])])
		elif a.begins_with("--quit-after="):
			quit_at = Time.get_ticks_msec() + int(float(a.substr(13)) * 1000.0)
		elif a.begins_with("--score-file="):
			score_file = a.substr(13)
	if kind not in ["jesse", "maze"]:
		push_warning("the host offers jesse and maze, the maps a web page can build; not " + kind)
		kind = "jesse"
	seed = seed & 0x7FFFFFFF
	if seed == 0:
		randomize()
		seed = randi() & 0x7FFFFFFF
	var opts := {"people": 0} if kind == "maze" else {}
	start(kind, seed, opts, max_p, rules, spawns)

func start(kind: String, seed: int, opts: Dictionary, max_p: int, rules: Dictionary, spawns: Array) -> void:
	# a screen nobody looks at does not need a thousand frames a second
	Engine.max_fps = 120
	var t0 := Time.get_ticks_msec()
	game = preload("res://godot/scripts/game/game.gd").new()
	game.name = "Game"
	game.net_map = {"kind": kind, "seed": seed, "opts": opts}
	add_child(game)
	# the host steps the world off its own clock (SimServer.run), not the
	# frame loop a player's game runs on
	game.set_process(false)
	var map := {"kind": kind, "seed": seed, "opts": opts}
	sim = SimServer.new(game, map, max_p, rules, func(s): _say(s))
	if not spawns.is_empty() and sim.match_.mode == "dm":
		sim.match_.spawns = spawns
	_say("%s, seed %d: %d sectors, built in %.1fs" % [game.level.name, seed, game.level.sectors.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	listener.on_accept = func(ws): sim.accept(ws)
	var err := listener.listen(port)
	if err != OK:
		_say("could not listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	_say("MEWD host on port %d, up to %d players" % [listener.port, max_p])
	_say("%s, to %d" % ["team deathmatch" if sim.match_.mode == "tdm" else "deathmatch", sim.match_.limit()])
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			_say("  join:  godot --path . -- --join=%s:%d     web: ?join=%s:%d" % [ip, listener.port, ip, listener.port])
	_t0 = Time.get_ticks_usec()

func _say(s: String) -> void:
	print(s)

func _process(_dt: float) -> void:
	if sim == null:
		return
	listener.poll()
	sim.poll()
	# the real clock, not the frame's: a host's second is a second
	var now := Time.get_ticks_usec()
	sim.run(minf((now - _t0) / 1000000.0, 0.25))
	_t0 = now
	sim.poll()
	if score_file != "" and Engine.get_process_frames() % 10 == 0:
		_write_score()
	if quit_at > 0 and Time.get_ticks_msec() >= quit_at:
		close()
		get_tree().quit(0)

func _write_score() -> void:
	var t := sim.match_.table()
	# everybody who has played, as they last stood — they stay on the disk
	# after they have gone
	for q in t.players:
		_seen[q.name] = q
	t["seen"] = _seen.values()
	t["rewinds"] = sim.rewinds
	t["snaps"] = sim.snaps
	t["tics"] = game.tics
	var js := JSON.stringify(t)
	if js == _last_score:
		return
	_last_score = js
	var f := FileAccess.open(score_file, FileAccess.WRITE)
	if f:
		f.store_string(js)

func close() -> void:
	if score_file != "":
		_write_score()
	sim.stop()
	listener.stop()
	_say("closing")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and sim != null:
		close()
