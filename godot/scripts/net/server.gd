## MEWD — the host: an authoritative simulation behind a message interface.
##
## A SimServer owns one Game and the clients talking to it, and does not
## care where it runs: the dedicated server (host.gd, `--server`) runs one
## with no screen at all; the tests run one over loopback pipes.
##
##   - the handshake: hello → welcome (the map as a seed) or refused
##   - up to MAX_PLAYERS lines, and a refusal for the seventeenth
##   - A PLAYER EACH, on a side, on a pad (match.gd), with its own session
##     its commands are queued in, one applied per tic
##   - the tic, at TICRATE, stepped by run(dt) or by hand, and the match's
##     after it: respawns, the spawn guard, the end of a round
##   - THE REWIND, which is what makes a hit on a LAN a hit
##   - a snapshot every SNAP_EVERY tics, per client
##
## THE PLAYER THE MAP STARTS WITH IS PUT ASIDE: left out of game.players,
## so nothing shoots it, walks into it or ticks it, and it stays only as
## the `player` the rest of the world's code leans on.
##
## THE REWIND. A client draws the others a little in the past (remote.gd),
## so the player in its sights is where that player WAS. Each command says
## which host tic it was drawn at (`seen`), and while the host runs that
## command it puts every OTHER player back where they were then, lets the
## shot happen, and puts them forward again — up to MAX_REWIND tics.
class_name SimServer
extends RefCounted

const TICRATE := 35
const SNAP_EVERY := 3            # about twelve a second
const SCORE_EVERY := 35          # the whole table, once a second
const MAX_REWIND := 12           # a third of a second
const HISTORY := 48              # tics of where everybody was
## THE HERDS (at the user's request: "NPC positions don't matter, they don't
## need to update fast; if a unicorn kills someone they die"): the host's
## unicorns are the ones that hurt, so every client is told where those
## near its player are — UNI_EVERY tics apart (four times a second), within
## UNI_NEAR (300 m) or after them — and draws its own as puppets of that.
## The candy girls are every machine's own, from the same seed.
const UNI_EVERY := 9
const UNI_NEAR := 300.0 * 32.0

class Client extends RefCounted:
	var id := 0
	var name := ""
	var transport
	var welcomed := false
	## the client has its world up (its "ready"): only then is it dropped in
	var ready := false
	var player = null

var game
var map: Dictionary
var max_players := NetProtocol.MAX_PLAYERS
var log_fn := Callable()
var clients := {}                # id → Client
var lines: Array = []            # every Client accepted, welcomed or not
var next_id := 1
var match_: NetMatch
var herds := 0
var history := {}                # player → [{tic, x, y, z, dead}]
## the herd's deaths already told (Game.herd index → true)
var herd_told := {}
var rewinds := 0
var snaps := 0
var _acc := 0.0

static func r3(v: float) -> float:
	return roundf(v * 1000.0) / 1000.0

static func r5(v: float) -> float:
	return roundf(v * 100000.0) / 100000.0

## game        a Game, built for `map_`
## map_        {kind, seed, opts} — what the welcome tells a client to build
## rules       overrides for NetMatch.RULES
func _init(g, map_: Dictionary, max_p := NetProtocol.MAX_PLAYERS, rules := {}, log_cb := Callable()) -> void:
	game = g
	map = map_
	max_players = max_p
	log_fn = log_cb
	# the map's own player, put aside — see the top of the file
	g.players.erase(g.player)
	g.player.shootable = false
	match_ = NetMatch.new(g, rules, int(map_.get("seed", 1)))
	g.rewind = rewind

func _log(s: String) -> void:
	if log_fn.is_valid():
		log_fn.call(s)

## A new line, from whatever transport it came in on.
func accept(transport) -> Client:
	var c := Client.new()
	c.transport = transport
	transport.on_message = func(data): _message(c, data)
	transport.on_close = func(): _gone(c)
	lines.append(c)
	return c

func _send(c: Client, msg: Dictionary) -> void:
	c.transport.send(NetProtocol.encode(msg))

func _message(c: Client, data) -> void:
	var m := NetProtocol.decode(data)
	if m.is_empty():
		return
	if not c.welcomed:
		if m.t != "hello":
			return
		if m.get("v") != NetProtocol.PROTOCOL:
			_refuse(c, "protocol %s, host speaks %d" % [str(m.get("v")), NetProtocol.PROTOCOL])
			return
		if clients.size() >= max_players:
			_refuse(c, "full: %d players" % max_players)
			return
		c.id = next_id
		next_id += 1
		var nm := ""
		for ch in str(m.get("name", "")):
			if ch.unicode_at(0) >= 0x20 and ch.unicode_at(0) <= 0x7e:
				nm += ch
		nm = nm.substr(0, 16)
		c.name = nm if nm != "" else "PLAYER %d" % c.id
		c.welcomed = true
		clients[c.id] = c
		# (the side it will be on, before it is in the world: the welcome
		# says, and a client builds its world on it)
		var side_n: int = match_._smaller_team() if match_.teams != null else -1
		_send(c, {"t": "welcome", "v": NetProtocol.PROTOCOL, "id": c.id, "team": side_n, "mode": match_.mode,
			"map": map, "tic": game.tics, "rate": TICRATE, "score": match_.table()})
		_log("%s connected (%d/%d), building the island" % [c.name, clients.size(), max_players])
		return
	# READY: the client has built the island, and is dropped into it — not
	# before, or its pod would be down before it could see it
	if str(m.t) == "ready":
		if not c.ready:
			c.ready = true
			c.player = match_.join(c.id, c.name)
			c.player.session = NetSession.Host.new()
			var side := (" team " + str(match_.teams[c.player.team].name)) if c.player.team >= 0 else ""
			_log("%s joined%s (%d/%d)" % [c.name, side, clients.size(), max_players])
		return
	if not c.ready:
		return
	match str(m.t):
		"cmd":
			c.player.session.push(m.cmd)
		"ping":
			c.player.ping = clampi(int(m.get("rtt", 0)), 0, 9999)
			# the sender's own clock, back as it came: an integer stays one
			var n = m.get("n", 0)
			if n is float and n == floorf(n) and absf(n) < 9.0e15:
				n = int(n)
			_send(c, {"t": "pong", "n": n})
		"bye":
			c.transport.close()

func _refuse(c: Client, why: String) -> void:
	_send(c, {"t": "refused", "why": why})
	_log("refused a client: " + why)
	c.transport.close()

func _gone(c: Client) -> void:
	lines.erase(c)
	if not c.welcomed or not clients.has(c.id):
		return
	clients.erase(c.id)
	if c.player != null:
		match_.leave(c.player)
		history.erase(c.player)
	_log("%s left (%d/%d)" % [c.name, clients.size(), max_players])

## The client driving `p`, or null.
func client_of(p) -> Client:
	for c in clients.values():
		if c.player == p:
			return c
	return null

# ---- the rewind ----------------------------------------------------------

## Called by Game.tic before `p` runs `cmd`: put the others where the
## sender saw them, and return what puts them back (or an invalid
## Callable). Only for a tic with the trigger down.
func rewind(p, cmd: Dictionary) -> Callable:
	if not cmd.attack or int(cmd.seen) == 0:
		return Callable()
	var g = game
	var back := mini(MAX_REWIND, maxi(0, g.tics - 1 - int(cmd.seen)))
	if back == 0:
		return Callable()
	var at: int = g.tics - 1 - back
	var moved := []
	for o in g.players:
		if o == p:
			continue
		var h: Array = history.get(o, [])
		var was = null
		for e in h:
			if e.tic == at:
				was = e
				break
		# somebody who was not there then, or was dead, stays as they are
		if was == null or was.dead or o.dead:
			continue
		moved.append([o, o.x, o.y, o.z])
		o.x = was.x
		o.y = was.y
		o.z = was.z
	if moved.is_empty():
		return Callable()
	rewinds += 1
	return func():
		for m in moved:
			m[0].x = m[1]
			m[0].y = m[2]
			m[0].z = m[3]

func _remember() -> void:
	var g = game
	for p in g.players:
		if not history.has(p):
			history[p] = []
		var h: Array = history[p]
		h.append({"tic": g.tics, "x": p.x, "y": p.y, "z": p.z, "dead": p.dead})
		if h.size() > HISTORY:
			h.pop_front()

## One tic of the world, and a snapshot if one is due.
func step() -> void:
	game.tic()
	match_.tic()
	_remember()
	if game.tics % SNAP_EVERY == 0:
		broadcast_snap()
	if game.tics % UNI_EVERY == 0:
		broadcast_herd()

## Off the frame's clock at TICRATE, at most six a frame (the dedicated
## server's loop; SimServer.start in the JS).
func run(dt: float) -> void:
	_acc += dt
	var n := 0
	while _acc >= 1.0 / TICRATE and n < 6:
		step()
		_acc -= 1.0 / TICRATE
		n += 1
	if n == 6:
		_acc = 0.0

# ---- snapshots ------------------------------------------------------------

## You, in full: enough for the client to put its own player exactly where
## the host has it and run its unacknowledged commands on top.
func you_for(p) -> Dictionary:
	return {
		"x": r3(p.x), "y": r3(p.y), "z": r3(p.z), "mx": r5(p.momx), "my": r5(p.momy), "mz": r5(p.momz),
		"g": 1 if p.on_ground else 0, "a": r5(p.angle), "p": r5(p.pitch),
		"h": maxi(0, ceili(p.health)), "a1": ceili(p.armour1), "a2": ceili(p.armour2),
		"w": p.weapon, "r": int(p.ammo.get("rounds", 0)), "d": 1 if p.dead else 0, "inv": 1 if p.invincible else 0,
		"n": p.spawns, "team": p.team, "frags": p.frags,
		"back": maxi(0, p.respawn_at - game.tics) if p.dead else 0,
		# IN A POD: where it was aimed and the host tic it began on — the
		# client flies the same pod itself from those (it is the same sum)
		"pod": [r3(p.pod.start.x), r3(p.pod.start.y), p.pod_tic] if _riding(p) else null,
	}

static func _riding(p) -> bool:
	return p.pod != null and p.pod.active and p.pod.holds_player()

## Somebody else, as little as drawing them takes:
## [id, x, y, z, angle, pitch, flags, team] — flags 1 dead, 2 firing,
## 4 spawn guard, 8 barrels turning, 16 in a pod (and then the pod's aim
## and the tic it began on, two more: x, y, tic).
func other_for(p) -> Array:
	var firing: bool = p.firing() and p.def().get("volley", false)
	var riding := _riding(p)
	var f := (1 if p.dead else 0) | (2 if firing else 0) | (4 if p.invincible else 0) | (8 if p.spin > 0.0 else 0) | (16 if riding else 0)
	var o := [p.id, r3(p.x), r3(p.y), r3(p.z), r5(p.angle), r5(p.pitch), f, p.team]
	if riding:
		o.append_array([r3(p.pod.start.x), r3(p.pod.start.y), p.pod_tic])
	return o

func snap_for(c: Client, ev: Array, score) -> Dictionary:
	var p = c.player
	var others := []
	for o in game.players:
		if o != p:
			others.append(other_for(o))
	var s := {"t": "snap", "tic": game.tics, "ack": p.session.ack, "you": you_for(p), "others": others}
	if not ev.is_empty():
		s["ev"] = ev
	if score != null:
		s["score"] = score
	return s

func broadcast_snap() -> void:
	var ev: Array = match_.events.duplicate()
	match_.events.clear()
	var score = match_.table() if not ev.is_empty() or game.tics % SCORE_EVERY < SNAP_EVERY else null
	for c in clients.values():
		if c.ready and c.player != null:
			_send(c, snap_for(c, ev, score))
	snaps += 1

# ---- the herds ---------------------------------------------------------------

## A unicorn, as little as drawing her takes: [i, x, y, z, angle, flags,
## who] — flags 2 her beam on, 4 in a fury, 8 alight; `who` the id of the
## player she is after (0, nobody).
func herd_rec(u) -> Array:
	var rb = game.rainbow
	var beam: bool = rb != null and rb.firing(u)
	var f := (2 if beam else 0) | (4 if u.fury > 0 else 0) | (8 if u.burning > 0 else 0)
	var who: int = u.target.id if u.target is Player else 0
	return [u.herd_i, roundf(u.x), roundf(u.y), roundf(u.z), r3(u.angle), f, who]

## Each client, the herd near its player (and any after it); every client,
## a death in the herd, once (an event: "udie").
func broadcast_herd() -> void:
	for u in game.herd:
		if (u.dead or u.removed) and not herd_told.has(u.herd_i):
			herd_told[u.herd_i] = true
			match_.events.append({"k": "udie", "i": u.herd_i})
	var near2 := UNI_NEAR * UNI_NEAR
	for c in clients.values():
		if not c.ready or c.player == null:
			continue
		var p = c.player
		var list := []
		for u in game.herd:
			if u.dead or u.removed:
				continue
			if U.dist2(u.x, u.y, p.x, p.y) < near2 or u.target == p:
				list.append(herd_rec(u))
		_send(c, {"t": "herd", "tic": game.tics, "u": list})
	herds += 1

## Every line polled (a socket transport needs it; a loopback does not).
func poll() -> void:
	for c in lines.duplicate():
		c.transport.poll()

func stop() -> void:
	for c in lines.duplicate():
		if c.welcomed:
			_send(c, {"t": "bye", "why": "host closed"})
		c.transport.close()
