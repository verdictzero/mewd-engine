## MEWD — a match: the rules that hold between players.
##
## A host (server.gd) makes one of these for its Game, and from then on
## the game has RULES: who is on whose side, where you come back when you
## die, what a death is worth, and when it is over. A game on its own
## never makes one, and every check in game.gd that asks is a null test.
##
## EVERYBODY DROPS IN (at the user's request: "everyone drops in at
## different points like fortnite or pubg via drop pod ... deathmatch, no
## closing zone yet, randomized drop points"): on an island a player comes
## into the world, and back after every death, in a drop pod
## (Game.start_pod) aimed at a random point on open ground — not in a
## house, not on a cliff, and as far as it can find from everybody alive
## (drop_point). Nothing hurts them in the pod, nor for `guardTics` after
## the door is off; a pod that lands on somebody squashes them, the rider's
## frag (DropPod._squash_players).
##
## TWO MODES, and the map decides which:
##
##   TEAM DEATHMATCH   a map with teams in it — JESSE, whose two forts
##                     each come with a row of spawn pads (world.pvp in
##                     jesse.gd). You join the smaller side, come back on
##                     your own pads, and the side to teamLimit takes it.
##   DEATHMATCH        anything else — THE MAZE. Everybody against
##                     everybody, spawns picked out of the open floor
##                     (find_spawns), and the first to fragLimit.
##
## THE NETWORK LOADOUT is the minigun: the one gun that is a hitscan and
## nothing else, which is the one the host can wind the world back for
## (SimServer.rewind).
class_name NetMatch
extends RefCounted

const TICRATE := 35

const RULES := {
	"fragLimit": 12,                 # deathmatch: first to this
	"teamLimit": 40,                 # team deathmatch: first side to this
	"respawnTics": 2 * TICRATE,      # down for this long at least
	"guardTics": 2 * TICRATE,        # and nothing hurts you for this long after
	"endTics": 8 * TICRATE,          # the scores stay up this long, and it starts again
	# A LIFE, at the user's request (pickups, finite ammo, armour on top
	# of health): what you drop in with; the rest is lying about
	"health": 100,
	"armour": 0,
	"armourClass": 0,
	# THE MINIGUN AND THE PLASMA RIFLE: the two hitscans, the host's rewind's
	# — the rifle empty until a battery is picked up, the range answer
	# to the minigun's spray (and its bolt drawn on the other machines)
	"loadout": ["MINIGUN", "PLASMA"],
	"spawnAmmo": {"rounds": 600, "plasma": 0},
	# what a round does to a person, against what it does to a shopper: a
	# fresh body in about a second and a half of hits at 20 m
	"pvpScale": 0.06,
	# and a bolt: three always kill a fresh one, two never do
	"plasmaPvpScale": 0.32,
	# and what a unicorn's beam and ram do to one: half
	"npcScale": 0.5,
	# THE TANKS RUN DRY now there is something to pick up (Pickups); a
	# host may still say otherwise (--infinite-ammo)
	"infiniteAmmo": false,
	# A ROUND ENDS ON THE CLOCK TOO, ten minutes (0: only the frags) — and
	# a tie at the top plays on, sudden death, for `overtime` at most
	"timeLimit": 10 * 60 * TICRATE,
	"overtime": 2 * 60 * TICRATE,
}

## what survives a respawn: who you are, and the score
const KEEP := ["id", "name", "team", "frags", "deaths", "session", "ping", "spawns", "pod_tic"]

## a small generator of its own, so the match's choices leave the
## world's (U.p_random) exactly where they were
class Lcg extends RefCounted:
	var s := 1
	func _init(seed: int) -> void:
		s = seed & 0xFFFFFFFF
	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return s / 4294967296.0

var game
var rules: Dictionary
var rnd: Lcg
var teams = null                     # [{name, spawns, score}, …] or null
var mode := "dm"
var spawns = null                    # [[x, y], …] for a deathmatch
## what happened since anybody last asked — server.gd sends these in the
## snapshots and empties the list
var events: Array = []
var over = null                      # {winner, id, until} once somebody has won
var round_n := 1

## Everything `p` carries, full, and no latch shut.
static func top_up(p) -> void:
	for k in Weapons.TANKS:
		p.ammo[k] = Weapons.TANKS[k][0]
		p.dry[k] = false

## Standing room: points in the open with nothing within `clear` of them,
## spread over the map. For a map that names no spawn pads.
static func find_spawns(level, n := 24, clear := 48.0, seed := 7) -> Array:
	var b: Rect2 = level.bounds
	var x0 := b.position.x
	var y0 := b.position.y
	var x1 := b.end.x
	var y1 := b.end.y
	var r := Lcg.new(seed)
	var out := []
	var spread := maxf(96.0, minf(x1 - x0, y1 - y0) / (sqrt(n) * 2.0))
	var tries := 0
	while tries < n * 60 and out.size() < n:
		tries += 1
		var x := x0 + r.next() * (x1 - x0)
		var y := y0 + r.next() * (y1 - y0)
		var s = level.sector_at(x, y)
		if s == null or s.ceil - s.floor < 80.0:
			continue
		var ok := true
		for k in 8:
			var a := k * PI / 4.0
			var hit: Dictionary = level.ray_hit_wall(x, y, s.floor + 30.0, x + cos(a) * clear, y + sin(a) * clear, s.floor + 30.0)
			if not hit.is_empty():
				ok = false
				break
		if not ok:
			continue
		var crowded := false
		for q in out:
			if U.dist2(q[0], q[1], x, y) < spread * spread:
				crowded = true
				break
		if crowded:
			continue
		out.append([roundf(x), roundf(y)])
	return out

## Make `p` a fresh player standing at (x, y): everything a Player is made
## with, but the same object, the same name and the same score, armed and
## armoured as the rules say. The host does this on a respawn; a client
## does the same to its own player when the host says it has been
## respawned (remote.gd), so the two start from one state.
static func renew(p, x: float, y: float, angle: float, R := RULES):
	var fresh := Player.new(p.game, x, y, angle)
	var keep := {}
	for k in KEEP:
		keep[k] = p.get(k)
	if p.charge_loop != null:
		p.charge_loop.stop()
	for prop in fresh.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			p.set(prop.name, fresh.get(prop.name))
	for k in keep:
		p.set(k, keep[k])
	p.health = int(R.get("health", 100))
	p.armour = int(R.get("armour", 0))
	p.armour_class = int(R.get("armourClass", 1 if p.armour > 0 else 0))
	# what the rules drop you in with, and nothing else
	var given: Dictionary = R.get("spawnAmmo", {})
	for k in Weapons.TANKS:
		p.ammo[k] = mini(int(given.get(k, 0)), int(Weapons.TANKS[k][0]))
		p.dry[k] = false
		p.ammo_tick[k] = 0
	# the debug switches a Player starts with are a single-player thing
	p.debug = false
	p.invincible = false
	p.cheat = false
	p.owned = {}
	for w in R.loadout:
		p.owned[w] = true
	p.weapon = R.loadout[0]
	return p

func _init(g, overrides := {}, seed := 1) -> void:
	game = g
	rules = RULES.duplicate(true)
	rules.merge(overrides, true)
	rnd = Lcg.new(seed if (seed & 0xFFFFFFFF) != 0 else 1)
	round_start = g.tics
	var pvp = g.level.world.get("pvp")
	if pvp is Dictionary and pvp.get("teams", []).size() >= 2:
		teams = []
		for t in pvp.teams.slice(0, 2):
			teams.append({"name": str(t.name), "spawns": t.spawns.duplicate(true), "score": 0})
	mode = "tdm" if teams != null else "dm"
	# (an island's are drop points, found as they are wanted: drop_point)
	spawns = null if teams != null or g.level is IslandLevel else find_spawns(g.level)
	# a map with no room at all still has its start
	if spawns != null and spawns.is_empty():
		spawns.append([roundf(g.player.x), roundf(g.player.y)])
	g.rules = self

func limit() -> int:
	return int(rules.teamLimit if mode == "tdm" else rules.fragLimit)

# ---- sides -------------------------------------------------------------

## How much of `amount` from `from` reaches `to` (Game.hitscan, and a
## unicorn's beam and ram: RainbowBeams, Actor._ram).
func scale(from, to, amount: float) -> float:
	if to is Player:
		if from is Player:
			return amount * float(rules.get("plasmaPvpScale", rules.pvpScale) if from.weapon == "PLASMA" else rules.pvpScale)
		if from is Actor:
			return amount * float(rules.get("npcScale", 1.0))
	return amount

func friendly(a, b) -> bool:
	return mode == "tdm" and a is Player and b is Player and a != b and a.team == b.team

func _smaller_team() -> int:
	var n := [0, 0]
	for p in game.players:
		if p.team >= 0:
			n[p.team] += 1
	if n[0] != n[1]:
		return 0 if n[0] < n[1] else 1
	# level on numbers: the side that is behind
	return 0 if teams[0].score <= teams[1].score else 1

# ---- arriving and leaving -----------------------------------------------

## A new player in the world, spawned and armed.
func join(id: int, name: String):
	var g = game
	var p := Player.new(g, g.player.x, g.player.y, 0.0)
	p.id = id
	p.name = name
	p.team = _smaller_team() if teams != null else -1
	g.players.append(p)
	spawn(p)
	events.append({"k": "join", "id": id, "name": name, "team": p.team})
	return p

func leave(p) -> void:
	game.players.erase(p)
	if p.charge_loop != null:
		p.charge_loop.stop()
	events.append({"k": "leave", "id": p.id, "name": p.name})

# ---- coming back ----------------------------------------------------------

## Where `p` should come back: of the pads it may use, the one furthest
## from the nearest player not on its side, with a little chance in it so
## two deaths do not queue on the same pad.
func spawn_point(p) -> Array:
	var list: Array = teams[p.team].spawns if teams != null else spawns
	var foes := []
	var near := []
	for o in game.players:
		if o != p and not o.dead:
			near.append(o)
			if not friendly(p, o):
				foes.append(o)
	var best: Array = list[0]
	var best_score := -INF
	for s in list:
		var taken := false
		for o in near:
			if U.dist2(o.x, o.y, s[0], s[1]) < 48.0 * 48.0:
				taken = true
				break
		if taken:
			continue
		var d := 1e12
		for f in foes:
			d = minf(d, U.dist2(f.x, f.y, s[0], s[1]))
		var score := sqrt(d) * (0.75 + rnd.next() * 0.5)
		if score > best_score:
			best_score = score
			best = s
	return best

## WHERE A POD IS AIMED (the balance, at the user's request: a match on
## an island two and a half kilometres across was a long walk between
## frags): 80 to 160 m from one of the others alive, on open ground
## (IslandLevel._find_ground), inside the ARENA round the island's start
## where the pickups are laid (Pickups' rings), no nearer than 50 m to
## anybody, and clear of every pickup so a pod's posts never bury one —
## the first of a dozen tries that is; else the furthest from everybody of
## a dozen in the arena. Returns [x, y, and the point to face on landing:
## the one it was aimed at, or the middle].
func drop_point(p) -> Array:
	var g = game
	var lv = g.level
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rnd.next() * 2147483647.0)
	var A := _arena_middle()
	var half: float = minf(lv.bounds.size.x, lv.bounds.size.y) * 0.5
	var arena: float = minf(Pickups.RING2, 0.8 * half) + 1600.0
	var foes := []
	for o in g.players:
		if o != p and not o.dead:
			foes.append(o)
	for k in (12 if not foes.is_empty() else 0):
		var f = foes[int(rnd.next() * foes.size()) % foes.size()]
		var q0 := Vector2(f.x, f.y) + Vector2.RIGHT.rotated(rnd.next() * TAU) * (2560.0 + rnd.next() * 2560.0)
		var q: Vector2 = lv._find_ground(rng, q0, 320.0, 0.35)
		if q.distance_to(A) > arena or not lv.on_land(q.x, q.y, 128.0) or not _clear_of_pickups(q) or _by_a_herd(q):
			continue
		if foes.any(func(o): return Vector2(o.x - q.x, o.y - q.y).length() < 1600.0):
			continue
		return [roundf(q.x), roundf(q.y), f.x, f.y]
	var best := A
	var best_d := -1.0
	for k in 12:
		var q: Vector2 = lv._find_ground(rng, A, arena, 0.35)
		if not lv.on_land(q.x, q.y, 128.0) or not _clear_of_pickups(q) or _by_a_herd(q):
			continue
		var d := 1e12
		for o in foes:
			d = minf(d, Vector2(o.x - q.x, o.y - q.y).length())
		if d > best_d:
			best_d = d
			best = q
		if foes.is_empty():
			break
	return [roundf(best.x), roundf(best.y), A.x, A.y]

## the middle of a match's arena: the island's start
func _arena_middle() -> Vector2:
	for t in game.level.things:
		if t.type == "START":
			return Vector2(t.x, t.y)
	return game.level.bounds.get_center()

## a unicorn within 40 m (a pod landing in a herd would start a fight
## the rider never chose: its blast kills one, and her death rouses them)
func _by_a_herd(q: Vector2) -> bool:
	var bm = game.get("blockmap")
	if bm == null:
		return false
	for a in bm.near_radius(q.x, q.y, 1280.0):
		if a.type in ["UNICORN", "FOAL"] and not a.dead and not a.removed:
			return true
	return false

func _clear_of_pickups(q: Vector2) -> bool:
	var pk = game.get("pickups")
	if pk == null:
		return true
	for it in pk.items:
		if absf(it.x - q.x) < 160.0 and absf(it.y - q.y) < 160.0:
			return false
	return true

## Put `p` back in the world, whole — on an island, in a drop pod.
func spawn(p):
	var g = game
	var drop_in: bool = g.level is IslandLevel and teams == null
	# (a host told where to drop people, --spawns, aims there: the tests)
	var at := drop_point(p) if drop_in and spawns == null else spawn_point(p)
	var x := float(at[0])
	var y := float(at[1])
	# facing the middle of the map, which is where the other side is — or,
	# dropped by somebody, them
	var c: Vector2 = g.level.bounds.get_center() if g.level.bounds.has_area() else Vector2(x, y)
	if at.size() >= 4:
		c = Vector2(float(at[2]), float(at[3]))
	var angle := atan2(c.y - y, c.x - x)
	renew(p, x, y, angle, rules)
	p.respawn_at = 0
	p.guard_until = g.tics + int(rules.guardTics)
	p.invincible = true
	p.spawns += 1
	if drop_in:
		p.pod_tic = g.tics
		g.start_pod(p, x, y, true)
	return p

# ---- a death ------------------------------------------------------------------

func died(p, source) -> void:
	var g = game
	# the source of a round is the player who fired it, or nobody
	var killer = source if source is Player else null
	p.deaths += 1
	p.respawn_at = g.tics + int(rules.respawnTics)
	if killer != null and killer != p and not friendly(killer, p):
		killer.frags += 1
		if teams != null:
			teams[killer.team].score += 1
	else:
		# your own fault, or the world's: a frag off
		p.frags -= 1
		if teams != null and killer == null:
			teams[p.team].score = maxi(0, teams[p.team].score - 1)
	events.append({"k": "frag", "by": killer.id if killer != null and killer != p else 0, "of": p.id})
	if over != null:
		return
	var top = leader()
	if top != null and top.score >= limit():
		_end(top)
	# (sudden death: past the clock, the frag that breaks the tie ends it)
	elif top != null and overtime() and not tied():
		_end(top)

func _end(top) -> void:
	over = {"winner": top.name, "id": top.id, "until": game.tics + int(rules.endTics)}
	events.append({"k": "over", "winner": top.name})

## past the clock, the top shared: sudden death
func overtime() -> bool:
	var tl := int(rules.get("timeLimit", 0))
	return over == null and tl > 0 and game.tics - round_start >= tl

## whether more than one is on the top score
func tied() -> bool:
	var top = leader()
	if top == null:
		return false
	if teams != null:
		return teams[0].score == teams[1].score
	var n := 0
	for p in game.players:
		if p.frags == top.score:
			n += 1
	return n > 1

static func _riding(p) -> bool:
	return p.pod != null and p.pod.active and p.pod.holds_player()

## Who is winning: a team, or a player.
func leader():
	if teams != null:
		var a: Dictionary = teams[0]
		var b: Dictionary = teams[1]
		if a.score >= b.score:
			return {"name": a.name, "id": 0, "score": a.score}
		return {"name": b.name, "id": 1, "score": b.score}
	var best = null
	for p in game.players:
		if best == null or p.frags > best.frags:
			best = p
	return {"name": best.name, "id": best.id, "score": best.frags} if best != null else null

# ---- a tic ------------------------------------------------------------------------

## After the world's tic: the respawns, the spawn guard, the end of a round.
func tic() -> void:
	var g = game
	for p in g.players:
		if rules.infiniteAmmo:
			top_up(p)
		# nothing hurts you in the pod, nor for the guard's time after it
		if p.pod != null and p.pod.active and p.pod.holds_player():
			p.invincible = true
			p.guard_until = g.tics + int(rules.guardTics)
		if p.guard_until and g.tics >= p.guard_until:
			p.guard_until = 0
			p.invincible = false
		# (and the guard is over the moment you shoot from behind it)
		if p.guard_until and not _riding(p) and p.session != null and p.session.get("held") != null \
				and p.session.held.get("attack", false):
			p.guard_until = 0
			p.invincible = false
		if p.dead and over == null and g.tics >= p.respawn_at:
			spawn(p)
	# THE CLOCK: a round with a time limit ends on it, the leader its
	# winner — unless the top is shared: then SUDDEN DEATH, the next frag
	# that leaves one player on top (died), until `overtime` is up too
	var tl := int(rules.get("timeLimit", 0))
	# (the clock waits for somebody to play against: a round alone, or an
	# empty server, does not run out under the next to join)
	if g.players.size() < 2:
		round_start = g.tics
	if over == null and tl > 0 and g.tics - round_start >= tl:
		var top = leader()
		var past: bool = g.tics - round_start >= tl + int(rules.get("overtime", 0))
		if top != null and (past or not tied()):
			_end(top)
	if over != null and g.tics >= over.until:
		restart()

## the host's tic the round began on (the clock's)
var round_start := 0

## how many tics of the round are left on the clock, or -1 with none
## (0 in sudden death)
func time_left() -> int:
	var tl := int(rules.get("timeLimit", 0))
	return maxi(0, tl - (game.tics - round_start)) if tl > 0 else -1

## A new round: scores to nothing and everybody back on a pad.
func restart() -> void:
	over = null
	round_n += 1
	if teams != null:
		for t in teams:
			t.score = 0
	for p in game.players:
		p.frags = 0
		p.deaths = 0
		spawn(p)
	round_start = game.tics
	# and everything lying about lies there again
	if game.get("pickups") != null:
		game.pickups.reset()
	events.append({"k": "round", "n": round_n})

## The score, for a snapshot.
func table() -> Dictionary:
	var ts = null
	if teams != null:
		ts = []
		for t in teams:
			ts.append({"name": t.name, "score": t.score})
	var ov = null
	if over != null:
		ov = {"winner": over.winner, "left": maxi(0, over.until - game.tics)}
	var ps := []
	for p in game.players:
		ps.append({"id": p.id, "name": p.name, "team": p.team, "frags": p.frags, "deaths": p.deaths, "ping": p.ping})
	# (and the clock, a round with a time limit: tics left, and the tic
	# it was read on; -1 with none, or once the round is over)
	return {"mode": mode, "limit": limit(), "round": round_n, "teams": ts, "over": ov, "players": ps,
		"clock": time_left() if over == null else -1, "at": game.tics}
