## MEWD — network play, headless (godot/scripts/net/).
##
##   godot --headless --script res://godot/tests/net_test.gd [-- --no-procs]
##
## 1. THE WIRE: TicCmd rounding and bytes against the web build's own
##    (JS_WIRE, from `node godot/tests/net_js.mjs`), and the decoder
##    shrugging off garbage.
## 2. LOCAL: a game on its own is driven by a LocalSession, one player.
## 3. A MATCH IN ONE PROCESS, over loopback pipes: a host Game behind a
##    SimServer, a client Game with its NetGame (prediction, puppets), and
##    a bare NetClient driven by hand — the handshake, the prediction
##    agreeing with the host while walking, the puppet drawn, a teleport
##    corrected, a kill through the rewind, the frag, the respawn.
## 4. THE REAL THING: a headless Godot host (`--server`) and two headless
##    Godot clients (`--join … --netbot`) as three processes on a real
##    socket, the clients hunting each other; the host's score file must
##    show both, their tics applied, and frags.
## Prints OK or fails.
extends SceneTree

const JS_WIRE := [
	{"hex": "010100000000000000000000000000000000", "q": [1, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0, 0, 0]},
	{"hex": "01230000006500dfff7f810900001e000000", "q": [35, 0.0123291015625, -0.0040283203125, 1.0, -1.0, true, false, false, true, 0, 0, 30]},
	{"hex": "01701101003383ff7f40c10604ff66110100", "q": [70000, -3.9000244140625, 3.9998779296875, 0.5039370078740157, -0.49606299212598426, false, true, true, false, 4, -1, 69990]},
	{"hex": "01ffffffff01000000010000ff0101000000", "q": [4294967295, 0.0001220703125, 0.0, 0.007874015748031496, 0.0, false, false, false, false, 255, 1, 1]},
	{"hex": "010c000000ab0a3303a65a0b070109000000", "q": [12, 0.3333740234375, 0.0999755859375, -0.7086614173228346, 0.7086614173228346, true, true, false, true, 7, 1, 9]},
]
## the same five as net_js.mjs CASES: [tic, look.x, look.y, move.x, move.y, run, jump, use, attack, slot, cycle, seen]
const CASES := [
	[1, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 0, 0, 0],
	[35, 0.0123, -0.004, 1.0, -1.0, true, false, false, true, 0, 0, 30],
	[70000, -3.9, 5.0, 0.5, -0.5, false, true, true, false, 4, -1, 69990],
	[4294967295, 1.0 / 16384.0, -1.0 / 16384.0, 1.0 / 254.0, -1.0 / 254.0, false, false, false, false, 300, 7, 1],
	[12, 0.33333, 0.1, -0.7071, 0.7071, true, true, false, true, 7, 1, 9],
]

const SEED := 11
var failures := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

func _init() -> void:
	U.p_seed()
	_wire()
	await _local()
	await _match()
	if not OS.get_cmdline_user_args().has("--no-procs"):
		await _procs()
	print("net: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

static func _cmd(a: Array) -> Dictionary:
	return {"tic": a[0], "look": Vector2(a[1], a[2]), "side": a[3], "fwd": a[4], "run": a[5], "jump": a[6], "use": a[7],
		"attack": a[8], "slot": a[9], "cycle": a[10], "seen": a[11]}

func _as_array(c: Dictionary) -> Array:
	return [c.tic, c.look.x, c.look.y, c.side, c.fwd, c.run, c.jump, c.use, c.attack, c.slot, c.cycle, c.seen]

func _same_q(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] is float or b[i] is float:
			if absf(float(a[i]) - float(b[i])) > 1e-12:
				return false
		elif a[i] != b[i]:
			return false
	return true

# ---- 1. the wire ---------------------------------------------------------------

func _wire() -> void:
	print("net: the wire against js/net/ticcmd.js")
	for i in CASES.size():
		var c := TicCmd.quantize(_cmd(CASES[i]))
		var wire := NetProtocol.encode_cmd(c)
		check(wire.hex_encode() == JS_WIRE[i].hex, "case %d: bytes %s (js %s)" % [i, wire.hex_encode(), JS_WIRE[i].hex])
		check(_same_q(_as_array(c), JS_WIRE[i].q), "case %d: rounded as the JS rounds it" % i)
		var back := NetProtocol.decode(JS_WIRE[i].hex.hex_decode())
		check(back.get("t") == "cmd" and _same_q(_as_array(back.cmd), JS_WIRE[i].q), "case %d: the JS bytes decode to the JS command" % i)
		check(TicCmd.same(back.cmd, c), "case %d: same()" % i)
	check(NetProtocol.decode("nonsense").is_empty() and NetProtocol.decode(PackedByteArray([1, 2])).is_empty()
		and NetProtocol.decode("{\"x\":1}").is_empty() and NetProtocol.decode(7).is_empty(), "garbage decodes to nothing")
	var m := NetProtocol.decode(NetProtocol.encode({"t": "hello", "v": 2, "name": "A"}))
	check(m.t == "hello" and m.v == NetProtocol.PROTOCOL, "a control message round-trips")
	check(NetProtocol.url_for("10.0.0.2") == "ws://10.0.0.2:7777/net" and NetProtocol.url_for("ws://h:9/x") == "ws://h:9/x"
		and NetProtocol.url_for("h:9") == "ws://h:9/net", "a typed host becomes a socket URL")

# ---- 2. local --------------------------------------------------------------------

func _game(net_map := {}) -> Node:
	var g = preload("res://godot/scripts/game/game.gd").new()
	if not net_map.is_empty():
		g.net_map = net_map
	root.add_child(g)
	g.set_process(false)
	return g

func _local() -> void:
	print("net: a game on its own")
	var g = _game({"kind": "maze", "seed": SEED, "opts": {"people": 0}})
	await process_frame
	check(g.session is NetSession.Local and g.players.size() == 1 and g.players[0] == g.player, "one player, the game's LocalSession")
	var t0: int = g.tics
	for i in 10:
		g.tic()
	check(g.tics == t0 + 10 and g.rules == null, "it tics, with no rules")
	g.queue_free()
	await process_frame

# ---- 3. a match in one process ------------------------------------------------------

## the longest straight clear run out of the host's START, as [angle, length]
func _clear_run(g) -> Vector2:
	var p = g.player
	var best := Vector2()
	for k in 8:
		var ang := k * PI / 4.0
		var hit: Dictionary = g.level.ray_hit_wall(p.x, p.y, 30, p.x + cos(ang) * 2000.0, p.y + sin(ang) * 2000.0, 30)
		var l: float = 2000.0 * float(hit.t) if not hit.is_empty() else 2000.0
		if l > best.y:
			best = Vector2(ang, l)
	return best

func _match() -> void:
	print("net: a match over loopback")
	var map := {"kind": "maze", "seed": SEED, "opts": {"people": 0}}
	var hg = _game(map)
	var sim := SimServer.new(hg, map, 16, {"fragLimit": 50}, func(s): print("  host: " + s))
	check(sim.match_.mode == "dm" and sim.match_.spawns.size() > 4, "THE MAZE is a deathmatch with %d spawns found" % sim.match_.spawns.size())
	check(not hg.players.has(hg.player), "the map's own player is put aside")
	# the fake clock both clients read: 35 tics a second, exactly
	var clock := [0]
	var now := func() -> int: return clock[0]
	# CLIENT ONE: a whole Game, with prediction and puppets
	var pa := NetTransport.Loopback.pair()
	sim.accept(pa[1])
	var c1 := NetClient.new(pa[0], "ONE", now)
	check(c1.welcome != null and c1.id == 1 and c1.map.kind == "maze" and int(c1.map.seed) == SEED, "ONE is welcomed, told the map")
	var cg = _game(c1.map)
	var ng := NetGame.new(cg, c1, now)
	# CLIENT TWO: a bare line, driven by hand
	var pb := NetTransport.Loopback.pair()
	sim.accept(pb[1])
	var c2 := NetClient.new(pb[0], "TWO", now)
	check(c2.welcome != null and c2.id == 2, "TWO is welcomed")
	# a seventeenth is refused — here, the third on a host of two
	var sim_full := sim.max_players
	sim.max_players = 2
	var pc := NetTransport.Loopback.pair()
	sim.accept(pc[1])
	var c3 := NetClient.new(pc[0], "THREE", now)
	check(c3.welcome == null and c3.refused != null and c3.closed, "a third on a host of two is refused (%s)" % str(c3.refused))
	sim.max_players = sim_full
	var bad := NetTransport.Loopback.pair()
	sim.accept(bad[1])
	bad[0].send(NetProtocol.encode({"t": "hello", "v": 1, "name": "OLD"}))
	check(not bad[0].open, "a client on protocol 1 is refused")
	check(cg.level.sectors.size() == hg.level.sectors.size() and cg.level.lines.size() == hg.level.lines.size(),
		"the client built the host's level from the seed (%d sectors)" % cg.level.sectors.size())

	var p1 = sim.clients[1].player
	var p2 = sim.clients[2].player
	var seq2 := [0]
	var send2 := func(c: Dictionary) -> void:
		seq2[0] += 1
		c.tic = seq2[0]
		c.seen = maxi(0, int(ng.host_tic()) - NetGame.INTERP_TICS)
		c2.send(TicCmd.quantize(c))
	var step := func(n: int, hold: Dictionary) -> void:
		for i in n:
			clock[0] += 1000 / 35
			cg.tic()                       # ONE's tic: its command goes to the host
			send2.call(hold.duplicate())   # and TWO's
			sim.step()                     # the host's, and the snapshots come back
			ng.frame()
	step.call(10, TicCmd.new_cmd())
	check(ng.spawn_n == 1 and absf(cg.player.x - p1.x) < 0.01 and absf(cg.player.y - p1.y) < 0.01,
		"ONE is where the host spawned it")
	check(ng.puppets.has(2) and ng.puppets[2].a.type == "SWAT", "ONE draws TWO as a puppet")

	# WALKING: pressed on ONE's own keys, predicted, and the host agreeing
	Input.action_press("fwd")
	Input.action_press("right")
	var x0: float = cg.player.x
	var y0: float = cg.player.y
	step.call(40, TicCmd.new_cmd())
	Input.action_release("fwd")
	Input.action_release("right")
	step.call(20, TicCmd.new_cmd())
	var moved := Vector2(cg.player.x - x0, cg.player.y - y0).length()
	var off := Vector2(cg.player.x - p1.x, cg.player.y - p1.y).length()
	check(moved > 40.0, "ONE walked %.0f units" % moved)
	check(off < 0.05, "and the host has it where it predicted itself (%.4f apart)" % off)
	check(ng.biggest < 1.0, "with no correction worth the name (%d, biggest %.3f)" % [ng.corrections, ng.biggest])
	check(sim.clients[1].player.session.applied >= 60, "the host applied ONE's commands (%d)" % sim.clients[1].player.session.applied)

	# A TELEPORT the client did not see coming is a jump to the truth
	var run := _clear_run(hg)
	var sx: float = hg.player.x
	var sy: float = hg.player.y
	for q in [p1, p2]:
		q.x = sx
		q.y = sy
		q.momx = 0.0
		q.momy = 0.0
		q.sector = hg.level.sector_at(sx, sy)
		q.z = q.sector.floor
	p1.x += cos(run.x) * 60.0
	p1.y += sin(run.x) * 60.0
	var far := minf(run.y - 60.0, 420.0)
	p2.x += cos(run.x) * far
	p2.y += sin(run.x) * far
	p1.angle = run.x
	p2.angle = U.angle_norm(run.x + PI)
	p1.pitch = 0.0
	p2.pitch = 0.0
	step.call(12, TicCmd.new_cmd())
	check(Vector2(cg.player.x - p1.x, cg.player.y - p1.y).length() < 0.5, "a teleport on the host is where ONE ends up")
	var pup: NetGame.Puppet = ng.puppets[2]
	check(Vector2(pup.a.x - p2.x, pup.a.y - p2.y).length() < 1.0, "and the puppet is drawn where TWO was put (in the past, but still)")

	# A KILL: TWO holds the trigger on ONE, through the rewind, until ONE dies
	p1.guard_until = 0
	p1.invincible = false
	var fire := TicCmd.new_cmd()
	fire.attack = true
	var died_at := -1
	var saw_dead := false
	for i in 200:
		step.call(1, fire)
		if cg.player.dead:
			saw_dead = true
		if p1.dead and died_at < 0:
			died_at = i
		if died_at >= 0 and i > died_at + 6:
			break
	check(died_at >= 0, "TWO's minigun killed ONE after %d tics" % died_at)
	check(p2.frags == 1 and p1.deaths == 1, "the frag counted: TWO %d, ONE died %d" % [p2.frags, p1.deaths])
	check(sim.rewinds > 0, "the host wound ONE back for TWO's shots (%d rewinds)" % sim.rewinds)
	check(saw_dead, "ONE's own game went down when the host said so")
	var toast_ok := false
	for t in cg.toasts:
		if str(t.text).contains("FRAGGED YOU"):
			toast_ok = true
	check(toast_ok, "and said who did it (%s)" % str(cg.toasts.map(func(t): return t.text)))
	check(c1.score != null and int(c1.score.players.filter(func(q): return int(q.id) == 2)[0].frags) == 1, "the score reached ONE")
	# THE RESPAWN: two seconds on, ONE is back on a pad, whole
	step.call(NetMatch.RULES.respawnTics + 10, TicCmd.new_cmd())
	check(not p1.dead and p1.spawns == 2 and not cg.player.dead and ng.spawn_n == 2, "ONE came back (life %d)" % p1.spawns)
	check(cg.player.health == 100 and cg.player.armour1 == 300 and cg.player.weapon == "MINIGUN", "whole, and holding the minigun")
	# GOODBYE: TWO leaves and ONE's puppet of it goes
	c2.close()
	step.call(6, TicCmd.new_cmd())
	check(not sim.clients.has(2) and not ng.puppets.has(2), "TWO left, and its puppet went with it")
	check(hg.players.size() == 1, "the host has one player left")
	ng.close()
	hg.queue_free()
	cg.queue_free()
	await process_frame

# ---- 4. three processes, a real socket --------------------------------------------

func _procs() -> void:
	print("net: a headless host and two headless clients, on a socket")
	# two pads at the ends of the longest clear run out of the maze's START
	var map := {"kind": "maze", "seed": SEED, "opts": {"people": 0}}
	var g = _game(map)
	await process_frame
	var run := _clear_run(g)
	var d := minf(run.y - 60.0, 700.0)
	var ax: float = g.player.x + cos(run.x) * 40.0
	var ay: float = g.player.y + sin(run.x) * 40.0
	var bx: float = g.player.x + cos(run.x) * d
	var by: float = g.player.y + sin(run.x) * d
	g.queue_free()
	var port := 7800 + randi() % 150
	var tmp := "/tmp/mewd-net-%d" % port
	DirAccess.make_dir_recursive_absolute(tmp)
	var score_path := tmp.path_join("score.json")
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var server := OS.create_process(exe, ["--headless", "--path", proj, "--", "--server=%d" % port, "--map=maze",
		"--seed=%d" % SEED, "--frags=100", "--spawns=%d,%d;%d,%d" % [ax, ay, bx, by], "--quit-after=34",
		"--score-file=" + score_path])
	check(server > 0, "the host is running (pid %d, port %d)" % [server, port])
	await create_timer(3.0).timeout
	var clients := []
	for nm in ["ALPHA", "BRAVO"]:
		var rep := tmp.path_join(nm + ".json")
		clients.append([OS.create_process(exe, ["--headless", "--path", proj, "--", "--join=127.0.0.1:%d" % port,
			"--netbot", "--name=" + nm, "--quit-after=26", "--report=" + rep]), rep])
	var until := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < until and (OS.is_process_running(server) or clients.any(func(c): return OS.is_process_running(c[0]))):
		await create_timer(0.5).timeout
	for c in clients:
		if OS.is_process_running(c[0]):
			OS.kill(c[0])
	if OS.is_process_running(server):
		OS.kill(server)
	var sc = JSON.parse_string(FileAccess.get_file_as_string(score_path)) if FileAccess.file_exists(score_path) else null
	check(sc is Dictionary, "the host wrote its score")
	if not (sc is Dictionary):
		return
	print("  host: %d tics, %d snaps, %d rewinds; %s" % [int(sc.tics), int(sc.snaps), int(sc.rewinds),
		", ".join(sc.seen.map(func(q): return "%s %d/%d ping %d" % [q.name, int(q.frags), int(q.deaths), int(q.ping)]))])
	var names: Array = sc.seen.map(func(q): return str(q.name))
	check(names.has("ALPHA") and names.has("BRAVO"), "both clients joined the host")
	var frags := 0
	for q in sc.seen:
		frags += maxi(0, int(q.frags))
	check(frags >= 1, "and fragged each other (%d frags)" % frags)
	check(int(sc.rewinds) > 0, "through the rewind (%d)" % int(sc.rewinds))
	for c in clients:
		var r = JSON.parse_string(FileAccess.get_file_as_string(c[1])) if FileAccess.file_exists(c[1]) else null
		check(r is Dictionary and int(r.snaps) > 200 and int(r.puppets) == 1 and int(r.sent) > 300,
			"%s's report: %s" % [c[1].get_file().get_basename(), str(r)])
