## MEWD — a match: the rules that hold between players (js/net/match.js).
##
## A host (server.gd) makes one of these for its Game, and from then on
## the game has RULES: who is on whose side, where you come back when you
## die, what a death is worth, and when it is over. A game on its own
## never makes one, and every check in game.gd that asks is a null test.
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
	"fragLimit": 20,                 # deathmatch: first to this
	"teamLimit": 40,                 # team deathmatch: first side to this
	"respawnTics": 2 * TICRATE,      # down for this long at least
	"guardTics": 2 * TICRATE,        # and nothing hurts you for this long after
	"endTics": 8 * TICRATE,          # the scores stay up this long, and it starts again
	"health": 100,
	"armour1": 300,                  # the inner plate, and no outer one: 400 in all
	"armour2": 0,
	"loadout": ["MINIGUN"],
	# what a round does to a person, against what it does to a shopper
	"pvpScale": 0.35,
	# NO PICKUPS, SO NO RUNNING OUT: every tank topped up every tic
	"infiniteAmmo": true,
}

## what survives a respawn: who you are, and the score
const KEEP := ["id", "name", "team", "frags", "deaths", "session", "ping", "spawns"]

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
	p.health = int(R.health)
	p.armour1 = int(R.armour1)
	p.armour2 = int(R.armour2)
	# the debug switches a Player starts with are a single-player thing
	p.debug = false
	p.invincible = false
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
	var pvp = g.level.world.get("pvp")
	if pvp is Dictionary and pvp.get("teams", []).size() >= 2:
		teams = []
		for t in pvp.teams.slice(0, 2):
			teams.append({"name": str(t.name), "spawns": t.spawns.duplicate(true), "score": 0})
	mode = "tdm" if teams != null else "dm"
	spawns = null if teams != null else find_spawns(g.level)
	# a map with no room at all still has its start
	if spawns != null and spawns.is_empty():
		spawns.append([roundf(g.player.x), roundf(g.player.y)])
	g.rules = self

func limit() -> int:
	return int(rules.teamLimit if mode == "tdm" else rules.fragLimit)

# ---- sides -------------------------------------------------------------

## How much of `amount` from `from` reaches `to` (Game.hitscan).
func scale(from, to, amount: float) -> float:
	return amount * float(rules.pvpScale) if from is Player and to is Player else amount

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

## Put `p` back in the world, whole.
func spawn(p):
	var g = game
	var at := spawn_point(p)
	var x := float(at[0])
	var y := float(at[1])
	# facing the middle of the map, which is where the other side is
	var c: Vector2 = g.level.bounds.get_center() if g.level.bounds.has_area() else Vector2(x, y)
	var angle := atan2(c.y - y, c.x - x)
	renew(p, x, y, angle, rules)
	p.respawn_at = 0
	p.guard_until = g.tics + int(rules.guardTics)
	p.invincible = true
	p.spawns += 1
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
		over = {"winner": top.name, "id": top.id, "until": g.tics + int(rules.endTics)}
		events.append({"k": "over", "winner": top.name})

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
		if p.guard_until and g.tics >= p.guard_until:
			p.guard_until = 0
			p.invincible = false
		if p.dead and over == null and g.tics >= p.respawn_at:
			spawn(p)
	if over != null and g.tics >= over.until:
		restart()

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
	return {"mode": mode, "limit": limit(), "round": round_n, "teams": ts, "over": ov, "players": ps}
