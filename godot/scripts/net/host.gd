## MEWD — the dedicated server.
##
##   godot --headless --path . -- --server[=PORT] [--map=island0] [--seed=N]
##                                [--max=16] [--frags=N] [--teams]
##
## A host with no screen: the real simulation (game.gd, not drawn) behind
## the message interface (server.gd), listening on the LAN for WebSocket
## lines at ws://this-machine:PORT/net (any path is taken); a Godot client
## joins with --join=this-machine:PORT, or JOIN on the title.
##
## Deathmatch on an island, everybody dropped in by pod at random points
## (NetMatch.drop_point), the herds the host's (server.gd), the crowd
## every machine's own.
##
## OR HOSTED FROM THE GAME (HOST GAME on the title's MULTIPLAYER page,
## Main.host_game): `listen` set and start() called by hand — the host's
## world in a hidden viewport of its own (nothing of it drawn, nothing of
## it in the player's world), the player joining it over this machine's
## own socket like anybody else.
##
## THE STANDALONE SERVER (at the user's request: "add a headless linux
## server as a separate standalone application, command line or CLI"):
## the same thing exported on its own as mewd-server (export preset "Linux
## Server", feature `server`: no window, no sound, no title — Main starts
## this straight away), with `mewd-server help` for the flags below and a
## CONSOLE on its terminal: type `help` there for the commands (status,
## players, kick, say, restart, quit). Every flag can be given with or
## without the `--` Godot wants before its own: the server reads them all.
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
## hosted from the game (see the top): no command line, a world of its own
var listen := false
var _view: SubViewport
var _started_ms := 0
## THE CONSOLE (the standalone server's terminal): lines read off stdin on
## a thread of their own, handed over to the main loop under a lock
var _console: Thread
var _lines := PackedStringArray()
var _lines_lock := Mutex.new()
var _console_open := false

const USAGE := """MEWD dedicated server %s

usage: mewd-server [options]

  --port=N           listen on port N (default %d)
  --map=KEY          the island: %s
  --seed=N           the crowd's and the herds' seed (default: random)
  --max=N            most players at once, 1 to 64 (default %d)
  --teams            team deathmatch, SWAT against ARMY (default: deathmatch)
  --frags=N          frags (or a side's kills) that end a round
  --minutes=M        a round's clock in minutes (0: frags only)
  --infinite-ammo    everybody's tanks kept full
  --score-file=PATH  the score table, as JSON, kept up to date
  --quit-after=S     close after S seconds
  --no-console       do not read commands from the terminal
  help               this, and nothing else

players join with:  mewd --join=THIS-MACHINE:PORT  (or JOIN GAME on the title)
type `help` at the running server for its commands."""

## every flag given, whether before Godot's `--` or after it
static func args() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if not out.has(a):
			out.append(a)
	return out

static func usage() -> String:
	var keys := PackedStringArray()
	for i in Islands.LIST:
		keys.append(i.key)
	return USAGE % [U.VERSION, NetProtocol.DEFAULT_PORT, ", ".join(keys), NetProtocol.MAX_PLAYERS]

func _ready() -> void:
	if listen:
		return
	var kind: String = Islands.LIST[0].key
	var seed := 0
	var max_p := NetProtocol.MAX_PLAYERS
	var rules := {}
	var spawns := []
	var console := OS.has_feature("server")
	for a in args():
		if a in ["help", "--usage", "-help", "/?"]:
			print(usage())
			get_tree().quit(0)
			return
		if a == "--no-console":
			console = false
		elif a == "--console":
			console = true
		elif a.begins_with("--server="):
			port = int(a.substr(9))
		elif a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--map="):
			kind = a.substr(6)
		elif a.begins_with("--seed="):
			seed = int(a.substr(7))
		elif a.begins_with("--max="):
			max_p = clampi(int(a.substr(6)), 1, 64)
		elif a.begins_with("--frags="):
			rules["fragLimit"] = int(a.substr(8))
			rules["teamLimit"] = int(a.substr(8))
		# (the tanks kept full, as before there were pickups: the tests' bots,
		# which never stop shooting)
		elif a == "--infinite-ammo":
			rules["infiniteAmmo"] = true
		# two teams, SWAT and ARMY (NetMatch.TEAM_NAMES)
		elif a == "--teams":
			rules["teams"] = true
		# a round's clock, minutes (0: frags only)
		elif a.begins_with("--minutes="):
			rules["timeLimit"] = int(float(a.substr(10)) * 60.0 * NetMatch.TICRATE)
		elif a.begins_with("--spawns="):
			for pt in a.substr(9).split(";", false):
				var xy := pt.split(",")
				if xy.size() >= 2:
					spawns.append([float(xy[0]), float(xy[1])])
		elif a.begins_with("--quit-after="):
			quit_at = Time.get_ticks_msec() + int(float(a.substr(13)) * 1000.0)
		elif a.begins_with("--score-file="):
			score_file = a.substr(13)
	# AN ISLAND (Islands.LIST): every client has it baked; the seed is the
	# crowd's and the herds'
	kind = Islands.find(kind).key
	seed = seed & 0x7FFFFFFF
	if seed == 0:
		randomize()
		seed = randi() & 0x7FFFFFFF
	# (the island's whole crowd and its herds: the herds are the host's to
	# run — they kill — and the crowd every machine's own, from the seed)
	var opts := {}
	print("MEWD dedicated server " + U.VERSION)
	if start(kind, seed, opts, max_p, rules, spawns) == OK and console:
		_open_console()

func start(kind: String, seed: int, opts: Dictionary, max_p: int, rules: Dictionary, spawns: Array) -> int:
	# a screen nobody looks at does not need a thousand frames a second
	if not listen:
		Engine.max_fps = 120
	var t0 := Time.get_ticks_msec()
	game = preload("res://godot/scripts/game/game.gd").new()
	game.name = "Game"
	game.net_map = {"kind": kind, "seed": seed, "opts": opts}
	# a server draws nothing: the island's ground, none of its terrain
	game.draw_world = false
	if listen:
		# (its sprites, its sparks, its camera in a world of their own that
		# is never drawn — not in the player's)
		_view = SubViewport.new()
		_view.own_world_3d = true
		_view.size = Vector2i(2, 2)
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_view.disable_3d = false
		add_child(_view)
		_view.add_child(game)
	else:
		add_child(game)
	# the host steps the world off its own clock (SimServer.run), not the
	# frame loop a player's game runs on
	game.set_process(false)
	var map := {"kind": kind, "seed": seed, "opts": opts}
	sim = SimServer.new(game, map, max_p, rules, func(s): _say(s))
	if not spawns.is_empty() and sim.match_.mode == "dm":
		sim.match_.spawns = spawns
	_say("%s, seed %d: built in %.1fs" % [game.level.name, seed, (Time.get_ticks_msec() - t0) / 1000.0])
	listener.on_accept = func(ws): sim.accept(ws)
	var err := listener.listen(port)
	if err != OK:
		_say("could not listen on port %d (error %d)" % [port, err])
		if listen:
			return err
		get_tree().quit(1)
		return err
	_say("MEWD host on port %d, up to %d players" % [listener.port, max_p])
	_say("%s, to %d" % ["team deathmatch" if sim.match_.mode == "tdm" else "deathmatch", sim.match_.limit()])
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			_say("  join:  mewd --join=%s:%d   (or JOIN GAME on the title: %s:%d)" % [ip, listener.port, ip, listener.port])
	_t0 = Time.get_ticks_usec()
	_started_ms = Time.get_ticks_msec()
	return OK

## this machine's addresses on the LAN, for the others to join on
static func lan_addresses() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out

func _say(s: String) -> void:
	print(s)

func _process(_dt: float) -> void:
	if sim == null:
		return
	if _console_open:
		_lines_lock.lock()
		var todo := _lines
		_lines = PackedStringArray()
		_lines_lock.unlock()
		for ln in todo:
			command(ln)
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

# ---- the console -------------------------------------------------------------

func _open_console() -> void:
	_console_open = true
	_console = Thread.new()
	_console.start(_read_console)
	_say("console: type `help` for the commands")

## (on its own thread: stdin blocks)
func _read_console() -> void:
	while _console_open:
		var s := OS.read_string_from_stdin(1024)
		if s.is_empty():
			# stdin closed (run in the background, or piped and finished)
			OS.delay_msec(200)
			continue
		_lines_lock.lock()
		for ln in s.split("\n", false):
			_lines.append(ln.strip_edges())
		_lines_lock.unlock()

const COMMANDS := """commands:
  help                 this
  status               the island, the match, the players, how long it has run
  players              everybody on it: id, name, side, frags, deaths, ping
  kick ID|NAME         put a player off the server
  say TEXT             a line on everybody's screen
  restart              a new round: scores to nothing, everybody dropped in again
  quit                 close the server (stop and exit do too)"""

## One line typed at the server. Returns what it said, too (the tests).
func command(line: String) -> String:
	var words := line.strip_edges().split(" ", false, 1)
	if words.is_empty():
		return ""
	var verb := words[0].to_lower()
	var rest := words[1] if words.size() > 1 else ""
	var out := ""
	match verb:
		"help", "?":
			out = COMMANDS
		"status":
			var m: NetMatch = sim.match_
			var up := (Time.get_ticks_msec() - _started_ms) / 1000
			var tl := m.time_left()
			out = "%s (%s) seed %d, port %d\n%s to %d, round %d%s\n%d/%d players, tic %d, up %d:%02d:%02d" % [
				game.level.name, sim.map.kind, int(sim.map.seed), listener.port,
				"team deathmatch" if m.mode == "tdm" else "deathmatch", m.limit(), m.round_n,
				(", %d:%02d left" % [tl / NetMatch.TICRATE / 60, (tl / NetMatch.TICRATE) % 60]) if tl >= 0 else "",
				sim.clients.size(), sim.max_players, game.tics, up / 3600, (up / 60) % 60, up % 60]
			if m.teams != null:
				out += "\n%s %d  —  %d %s" % [m.teams[0].name, m.teams[0].score, m.teams[1].score, m.teams[1].name]
		"players", "who":
			var rows := PackedStringArray(["ID  NAME             SIDE  FRAGS DEATHS PING"])
			for c in sim.clients.values():
				var p = c.player
				var side := "-"
				if p != null and p.team >= 0 and sim.match_.teams != null:
					side = sim.match_.teams[p.team].name
				rows.append("%s%s%s%s%s%s" % [str(c.id).rpad(4), str(c.name).rpad(17).substr(0, 17), side.rpad(6),
					str(p.frags if p != null else 0).rpad(6), str(p.deaths if p != null else 0).rpad(7),
					str(p.ping if p != null else 0)])
			out = "\n".join(rows) if rows.size() > 1 else "nobody on"
		"kick":
			var c = _client_named(rest)
			if c == null:
				out = "no player %s" % rest
			else:
				sim._refuse(c, "kicked by the host")
				sim._gone(c)
				out = "kicked %s" % c.name
		"say":
			if rest == "":
				out = "say what?"
			else:
				sim.match_.events.append({"k": "say", "text": rest})
				out = "HOST: " + rest
		"restart":
			sim.match_.restart()
			out = "round %d" % sim.match_.round_n
		"quit", "stop", "exit":
			_say("closing on the console's word")
			close()
			get_tree().quit(0)
			return "closing"
		_:
			out = "no command %s (help for the list)" % verb
	_say(out)
	return out

## a client by its id or its name (any case)
func _client_named(s: String):
	s = s.strip_edges()
	if s.is_valid_int() and sim.clients.has(int(s)):
		return sim.clients[int(s)]
	for c in sim.clients.values():
		if str(c.name).to_lower() == s.to_lower():
			return c
	return null

func close() -> void:
	_console_open = false
	if score_file != "":
		_write_score()
	sim.stop()
	listener.stop()
	_say("closing")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and sim != null:
		close()
