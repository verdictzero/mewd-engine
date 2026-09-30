## MEWD — a thing in the world (js/actor.js: Actor and ACTIONS).
##
## Doom's mobj: a position, a state out of States, and the state's
## action called the moment it starts. What moves the crowd is two of
## those actions — A_Watch, standing and smelling the air, and A_Flee,
## the eight-way scored walk away from a fire and toward a way out —
## and panic is CONTAGIOUS: somebody running past with a face on them is
## a fright passed on, a little weaker each telling, so a crowd empties
## an aisle outward from whatever started it.
class_name Actor
extends RefCounted

enum DI { EAST, NORTHEAST, NORTH, NORTHWEST, WEST, SOUTHWEST, SOUTH, SOUTHEAST, NODIR }
const DIR_ANGLE := [0.0, PI / 4, PI / 2, 3 * PI / 4, PI, -3 * PI / 4, -PI / 2, -PI / 4]
const OPPOSITE := [DI.WEST, DI.SOUTHWEST, DI.SOUTH, DI.SOUTHEAST, DI.EAST, DI.NORTHEAST, DI.NORTH, DI.NORTHWEST, DI.NODIR]
const DIAGONALS := [DI.NORTHWEST, DI.NORTHEAST, DI.SOUTHWEST, DI.SOUTHEAST]
const FREEZE_AT := 100.0     # frost units before they go solid
const THAW_EVERY := 6        # tics per unit bled back off
const FIRE_THAW := 14.0      # and per tic of fire, which is 84x faster
const BORE_TICS := 78        # a shade over two seconds — js/bore.js's number

static var _next_id := 1

var id := 0
var game
var type := ""
var info := {}
var x := 0.0
var y := 0.0
var z := 0.0
var angle := 0.0
var momx := 0.0
var momy := 0.0
var momz := 0.0
var radius := 16.0
var height := 56.0
var health := 1000
var speed := 0.0
var monster := false
var solid := false
var shootable := false
var fireproof := false
var flammable := false
var flat := false
var target = null
var threshold := 0
var reactiontime := 0
var movedir: int = DI.NODIR
var movecount := 0
var just_attacked := false
var dead := false
var removed := false
var panic := 0
var flee_x := 0.0
var flee_y := 0.0
var exit_x = null
var exit_y = null
var exit_tic := 0
var burning := 0
var torch := 0
var frost := 0.0
var frozen := false
var ash := 0.0
var lit := 0.0
var bored := 0
var bored_by = null
var thaw_tick := 0
var thaw_state = null
var ash_tics := 0
var ash_by = null
var variant := 0
var sector: Level.Sector = null
var state := {}
var state_tics := 0
var shots := 0
## the actor blockmap's cell, see ActorGrid
var bm_key := -1
## THREE CYLINDERS ARE ONE VAN (js/actor.js): a CARBODY carries a pointer
## back to the Vehicle it is a third of, and its damage and its catching
## are the vehicle's — added for the vehicles port (godot/scripts/game/vehicle.gd)
var vehicle = null
## SOMEBODY ON ANOTHER MACHINE, drawn here (godot/scripts/net/remote.gd):
## NetGame walks, turns, fires and drops it, and nothing in this file may;
## which player it is and which side they are on
var puppet := false
var net_id := 0
var net_team := -1

func _init(g, type_name: String, ax: float, ay: float, a := 0.0, opts := {}) -> void:
	info = States.actor(type_name)
	assert(not info.is_empty(), "no such actor type: " + type_name)
	id = _next_id
	_next_id += 1
	game = g
	type = type_name
	x = ax
	y = ay
	angle = a
	radius = float(opts.get("radius", info.get("radius", 16)))
	height = float(opts.get("height", info.get("height", 56)))
	health = int(info.get("health", 1000))
	speed = float(info.get("speed", 0))
	monster = bool(info.get("monster", false))
	solid = bool(info.get("solid", monster))
	shootable = bool(info.get("shootable", monster))
	fireproof = bool(info.get("fireproof", false))
	flammable = bool(info.get("flammable", false)) and not fireproof
	flat = bool(info.get("flat", false))
	reactiontime = int(info.get("reaction", 0))
	variant = int(opts.get("variant", 0))
	sector = game.level.sector_at(x, y)
	# one placed on an upper layer stands in the storey at its height
	if sector != null and opts.get("z") != null:
		sector = game.level.span_in(sector, float(opts.z) + 1.0)
	z = sector.floor if sector else 0.0
	if info.has("spawn"):
		set_state(info.spawn)
	if solid:
		game.blockmap.add(self)

# ------------------------------------------------------------------
# The state machine
# ------------------------------------------------------------------

## the holds nothing but their owner may lift: ice, ash, a bore
func held() -> bool:
	return frozen or ash > 0.0 or bored > 0

## A chain of zero-tic states resolves in one go, as P_SetMobjState did.
func set_state(name, force := false) -> bool:
	if held() and not force:
		return false
	var guard := 0
	while name != null:
		var st := States.state(name)
		if st.is_empty():
			remove()
			return false
		state = st
		state_tics = st.tics
		if st.action != null:
			do_action(st.action)
		if removed:
			return false
		if st.tics != 0:
			return true
		name = st.next
		guard += 1
		if guard > 64:
			push_warning("state loop at " + str(st.name))
			return true
	remove()
	return false

func tic() -> void:
	if removed or state.is_empty():
		return
	if puppet:
		return
	if burning > 0:
		burn_tic()
	if frost > 0.0:
		frost_tic()
	if bored > 0:
		bore_tic()
	if removed:
		return
	if state_tics == -1:
		return
	state_tics -= 1
	if state_tics > 0:
		return
	if state.next != null:
		set_state(state.next, true)
	else:
		remove()

func do_action(name: String) -> void:
	if has_method(name):
		call(name)
	else:
		push_warning("no action " + name)

func remove() -> void:
	if removed:
		return
	removed = true
	game.blockmap.remove(self)

# ------------------------------------------------------------------
# Moving
# ------------------------------------------------------------------

func eye_z() -> float:
	return z + height * 0.72

func try_walk(dir: int = -1) -> bool:
	if dir == -1:
		dir = movedir
	if dir == DI.NODIR:
		return false
	var a: float = DIR_ANGLE[dir]
	var nx := x + cos(a) * speed
	var ny := y + sin(a) * speed
	if not can_stand_at(nx, ny):
		return false
	x = nx
	y = ny
	game.blockmap.moved(self)
	update_sector()
	movecount = U.p_random() & 15
	return true

func can_stand_at(nx: float, ny: float) -> bool:
	var r: Vector3 = game.level.slide_move(x, y, nx - x, ny - y, radius, z, height, true)
	if r.z > 0.0 or absf(r.x - nx) > 0.01 or absf(r.y - ny) > 0.01:
		return false
	if game.forest != null and not (game.level.layered and sector != null and sector.storey > 0) and game.forest.blocks(nx, ny, radius):
		return false
	var layered: bool = game.level.layered
	for o in game.blockmap.near(nx, ny):
		if o == self or o.removed or not o.solid or o.dead:
			continue
		if layered and (o.z >= z + height or z >= o.z + o.height):
			continue
		var rr: float = radius + o.radius
		if U.dist2(nx, ny, o.x, o.y) < rr * rr:
			return false
	var p = game.player
	if p != null and not p.dead and not (layered and (p.z >= z + height or z >= p.z + p.height)):
		var rr: float = radius + p.radius
		if U.dist2(nx, ny, p.x, p.y) < rr * rr:
			return false
	return true

func update_sector() -> void:
	var s: Level.Sector = game.level.sector_at(x, y, sector)
	if s:
		# the storey under the feet, not the ground under the building
		if s.above != -1:
			s = game.level.stand_in(s, z)
		sector = s
		z = s.floor

## THE WAY TO THE TARGET (game/nav.gd): in its room, the target; in
## another, the next point on the way there — planned again every two
## seconds or when the target changes room, and each point passed as the
## trooper steps into the room it is in.
var _way := []
var _way_to := -1
var _way_at := -1000

func _chase_point() -> Vector2:
	var tp := Vector2(target.x, target.y)
	var nav: Nav = game.nav
	var ts: Level.Sector = target.sector
	if nav == null or ts == null or sector == null or ts == sector:
		_way = []
		return tp
	if _way.is_empty() or _way_to != ts.index or game.tics - _way_at > 70:
		_way = nav.path(sector.index, Vector2(x, y), ts.index, tp)
		_way_to = ts.index
		_way_at = game.tics
	while not _way.is_empty() and (sector.index == _way[0].into or Vector2(x, y).distance_to(_way[0].p) < speed + 2.0):
		_way.pop_front()
	return tp if _way.is_empty() else _way[0].p

## Doom's P_NewChaseDir: straight at the target if it can, then the
## longer axis, then the shorter, then anything but back, then back —
## the target, or the next point on the way to it (_chase_point).
func new_chase_dir() -> void:
	if target == null:
		movedir = DI.NODIR
		return
	var olddir := movedir
	var turnaround: int = OPPOSITE[olddir]
	var goal := _chase_point()
	var dx: float = goal.x - x
	var dy: float = goal.y - y
	var d1: int = DI.EAST if dx > 10 else (DI.WEST if dx < -10 else DI.NODIR)
	var d2: int = DI.SOUTH if dy < -10 else (DI.NORTH if dy > 10 else DI.NODIR)
	if d1 != DI.NODIR and d2 != DI.NODIR:
		movedir = DIAGONALS[(2 if dy < 0 else 0) + (1 if dx > 0 else 0)]
		if movedir != turnaround and try_walk():
			return
	if U.p_random() > 200 or absf(dy) > absf(dx):
		var t := d1
		d1 = d2
		d2 = t
	if d1 == turnaround:
		d1 = DI.NODIR
	if d2 == turnaround:
		d2 = DI.NODIR
	if d1 != DI.NODIR:
		movedir = d1
		if try_walk():
			return
	if d2 != DI.NODIR:
		movedir = d2
		if try_walk():
			return
	if U.p_random() & 1:
		for dir in range(DI.EAST, DI.SOUTHEAST + 1):
			if dir != turnaround:
				movedir = dir
				if try_walk():
					return
	else:
		for dir in range(DI.SOUTHEAST, DI.EAST - 1, -1):
			if dir != turnaround:
				movedir = dir
				if try_walk():
					return
	if turnaround != DI.NODIR:
		movedir = turnaround
		if try_walk():
			return
	movedir = DI.NODIR

# ------------------------------------------------------------------
# Seeing and hitting
# ------------------------------------------------------------------

func can_see(other) -> bool:
	if other == null:
		return false
	return not game.level.sight_blocked(x, y, eye_z(), other.x, other.y, other.eye_z())

func in_sight_cone(other) -> bool:
	if U.dist2(x, y, other.x, other.y) < 128 * 128:
		return true
	var a := atan2(other.y - y, other.x - x)
	return absf(U.angle_norm(a - angle)) <= PI / 2

func check_missile_range() -> bool:
	var t = target
	if t == null or not can_see(t):
		return false
	var d := sqrt(U.dist2(x, y, t.x, t.y)) - 64.0
	if not info.has("melee") and d > 200.0:
		d = 200.0
	if d > float(info.get("missileRange", 1600)):
		return false
	return U.p_random() >= mini(200, int(d / 8.0))

## Damage from `source`. opts: fire (the stream, the floor, a blast),
## shot (a bullet), gib (a rocket beside them).
func damage(amount: float, source, opts := {}) -> void:
	if dead or removed or not shootable:
		return
	# a round from this machine marks a puppet without hurting it: the host
	# decides what a hit did
	if puppet:
		return
	# THREE CYLINDERS ARE ONE VAN: a shot into any third of it is a shot
	# into the vehicle — the health lives there, not here (vehicles port)
	if vehicle != null:
		vehicle.damage(amount, source, opts)
		return
	# A BLOCK OF ICE COMES APART ENTIRELY under anything that is not
	# fire; fire is spent melting it (a fireproof trooper thaws, anybody
	# else is eaten where they stand — burn_away)
	if frozen:
		if not opts.get("fire", false):
			shatter(source, opts)
			return
		if fireproof:
			frost = maxf(0.0, frost - amount * 2.0)
			if frost <= 0.0:
				thaw()
			return
		burn_away(source)
		return
	if opts.get("fire", false) and fireproof:
		return
	# somebody being eaten: fire does nothing more, a blow finishes them
	if ash > 0.0:
		if not opts.get("fire", false):
			collapse(source)
		return
	if opts.get("fire", false) and torch > 0:
		return
	var friendly: bool = source != null and source is Actor and info.has("team") and source.info.get("team") == info.team
	if friendly and opts.get("shot", false):
		return
	health -= int(amount)
	if health <= 0:
		die(source, amount, opts)
		return
	if source != null and source != self and not friendly and (target == null or threshold <= 0):
		target = source
		threshold = 100
		if state.get("name") == info.get("spawn") and info.has("see"):
			set_state(info.see)
	if int(info.get("painchance", 0)) > 0 and U.p_random() < int(info.painchance) and info.has("pain"):
		set_state(info.pain)

func die(source, _overkill := 0.0, opts := {}) -> void:
	if dead:
		return
	if frozen:
		shatter(source)
		return
	if ash > 0.0:
		collapse(source)
		return
	bored = 0
	dead = true
	solid = false
	shootable = false
	target = null
	height = 8.0
	game.blockmap.remove(self)
	var gibbed: bool = info.has("xdeath") and (opts.get("gib", false) or health < int(info.get("gibHealth", -1000)))
	var st = info.xdeath if gibbed else info.get("death")
	if st != null:
		set_state(st, true)
	else:
		remove()
	if monster:
		game.on_monster_killed(self, source)

# ------------------------------------------------------------------
# On fire
# ------------------------------------------------------------------

func ignite(tics := 350) -> void:
	# a map that says nothing burns still lets its people burn — the
	# thing with a `burn` state is the exception (js/actor.js ignite)
	if game.level.world.get("noBurn", false) and not info.has("burn"):
		return
	if not flammable or removed or dead:
		return
	# and a van catches as a van (vehicles port)
	if vehicle != null:
		vehicle.ignite(tics)
		return
	var was_alight := burning > 0
	if not was_alight:
		lit = 0.0
	burning = maxi(burning, tics)
	if not was_alight and info.has("burn"):
		var range: Array = info.get("burnTics", [120, 240])
		torch = roundi(range[0] + (U.p_random() / 255.0) * (range[1] - range[0]))
		burning = maxi(burning, torch + 20)
		panic = int(info.get("panicTics", 280))
		set_state(info.burn)
		if info.has("burnScare"):
			game.scare(x, y, float(info.burnScare))

func burn_tic() -> void:
	burning -= 1
	if game.fx != null:
		game.fx.body_fire(self)
	lit = minf(1.0, lit + 0.05)
	if burning <= 0:
		lit = 0.0

# ------------------------------------------------------------------
# ACTIONS, called by name from the state tables
# ------------------------------------------------------------------

func A_Look() -> void:
	var p = game.player
	if p == null or p.dead:
		return
	if not can_see(p) or not in_sight_cone(p):
		return
	var r := float(info.get("sightRange", 2000))
	if U.dist2(x, y, p.x, p.y) > r * r:
		return
	target = p
	game.play_sound(info.get("seeSound"), self)
	if info.has("see"):
		set_state(info.see)

func A_Chase() -> void:
	if reactiontime > 0:
		reactiontime -= 1
	if threshold > 0:
		if target == null or target.dead:
			threshold = 0
		else:
			threshold -= 1
	if target == null or target.dead:
		var p = game.player
		var r := float(info.get("sightRange", 2000))
		if p != null and not p.dead and can_see(p) and U.dist2(x, y, p.x, p.y) < r * r:
			target = p
		else:
			set_state(info.spawn)
			return
	if just_attacked:
		just_attacked = false
		new_chase_dir()
		return
	if info.has("missile") and movecount == 0 and check_missile_range():
		set_state(info.missile)
		just_attacked = true
		return
	movecount -= 1
	# on the way to another room: aimed again at the next point each step
	var away: bool = game.nav != null and target.sector != null and sector != null and target.sector != sector
	if movecount < 0 or away or not try_walk():
		new_chase_dir()
	if movedir != DI.NODIR:
		angle = DIR_ANGLE[movedir]

func A_FaceTarget() -> void:
	if target == null:
		return
	angle = atan2(target.y - y, target.x - x)

## Doom's A_PosAttack, near enough: one round down the eye line with
## the Zombieman's spread, three to fifteen off whatever it meets first.
func A_SwatFire() -> void:
	A_FaceTarget()
	game.play_sound(info.get("attackSound"), self)
	var spread := ((U.p_random() - U.p_random()) / 255.0) * 0.1
	var dmg := ((U.p_random() % 5) + 1) * 3
	game.hitscan(self, angle + spread, 2048.0, dmg, {"shot": true})
	game.fx.muzzle(self)
	shots += 1

## the army's rifle is a burst: two rounds, four to twenty each, half the scatter
func A_ArmyFire() -> void:
	A_FaceTarget()
	game.play_sound(info.get("attackSound"), self)
	for k in 2:
		var spread := ((U.p_random() - U.p_random()) / 255.0) * 0.05
		var dmg := ((U.p_random() % 5) + 1) * 4
		game.hitscan(self, angle + spread, 2048.0, dmg, {"shot": true})
	game.fx.muzzle(self)
	shots += 1

func A_Gib() -> void:
	game.gib(self)

## alight and still going: they run, they do not calm down, and then they go off
func A_Torch() -> void:
	panic = maxi(panic, int(info.get("panicTics", 280)))
	A_Flee()
	if dead or removed:
		return
	torch -= int(state.tics)
	if torch > 0:
		return
	torch = 0
	health = 0
	die(game.player, 0, {"fire": true})

## BEING EATEN: one number goes up and the shader eats the drawing with
## it, by the length of the frame and not a fixed step
func A_BurnAway() -> void:
	ash = minf(1.0, ash + float(state.tics) / maxf(1.0, ash_tics))
	if frost > 0.0:
		frost = maxf(0.0, frost - FIRE_THAW * 2.0)
	if game.fx != null:
		game.fx.body_fire(self, 0.5)
		if (U.p_random() & 1) == 0:
			game.fx.ember(x, y, z + height * ash, 1, 0.7)
	if ash >= 1.0:
		collapse(ash_by)

## Standing still and smelling the air: nine samples of the fire grid,
## and anybody running past near enough to see their face.
func A_Watch() -> void:
	if burning:
		A_Scare(x, y)
		return
	# (the ground no longer burns — at the user's request the fire that
	# spread is gone, and only people and cars burn — so what frightens
	# a shopper is somebody alight, or somebody already running)
	var R := float(info.get("scareRange", 320))
	for o in game.blockmap.near(x, y):
		if o == self or o.removed or o.burning <= 0:
			continue
		if U.dist2(x, y, o.x, o.y) > R * R:
			continue
		A_Scare(o.x, o.y)
		return
	const SEE := 190.0
	const FADE := 24
	for o in game.blockmap.near(x, y):
		if o == self or o.removed or o.dead or o.panic <= FADE * 2:
			continue
		if U.dist2(x, y, o.x, o.y) > SEE * SEE:
			continue
		A_Scare(o.flee_x, o.flee_y, o.panic - FADE)
		return

func A_Scare(fx: float, fy: float, tics := -1) -> void:
	if held():
		return
	var full := int(info.get("panicTics", 280))
	var want := full if tics < 0 else mini(full, tics)
	if want <= panic:
		flee_x = fx
		flee_y = fy
		return
	var first := panic <= 0
	panic = want
	flee_x = fx
	flee_y = fy
	if first:
		game.play_sound(info.get("painSound"), self)
		if info.has("see"):
			set_state(info.see)
		exit_tic = 0

func A_PickExit() -> void:
	exit_tic = 35 + (id & 15)
	exit_x = null
	exit_y = null
	var list: Array = game.level.world.get("exits", [])
	if list.is_empty() or (sector != null and sector.outdoor):
		return
	var best = null
	var best_score := INF
	for e in list:
		var score := sqrt(U.dist2(x, y, e.x, e.y)) + maxf(0.0, 1400.0 - sqrt(U.dist2(e.x, e.y, flee_x, flee_y))) * 1.6
		if score < best_score:
			best_score = score
			best = e
	if best != null:
		exit_x = best.x
		exit_y = best.y

## Running away: the eight directions SCORED — closer to the way out (or
## further from the fright), minus the heat where it would land, minus a
## little for turning — and walked in score order until one is free.
func A_Flee() -> void:
	panic -= 1
	if panic <= 0 and not burning:
		set_state(info.spawn)
		return
	exit_tic -= 1
	if exit_tic <= 0:
		A_PickExit()
	var out: bool = exit_x != null
	var tx: float = exit_x if out else flee_x
	var ty: float = exit_y if out else flee_y
	var sign := -1.0 if out else 1.0
	var d0 := sqrt(U.dist2(x, y, tx, ty))
	var score := PackedFloat32Array()
	score.resize(8)
	for d in 8:
		var ang: float = DIR_ANGLE[d]
		var nx := x + cos(ang) * speed
		var ny := y + sin(ang) * speed
		var s := (sqrt(U.dist2(nx, ny, tx, ty)) - d0) * 3.0 * sign
		if d == movedir:
			s += 6.0
		if d == OPPOSITE[movedir]:
			s -= 10.0
		s += (U.p_random() / 255.0 - 0.5) * 4.0
		score[d] = s
	for k in 8:
		var best := -1
		var best_s := -INF
		for d in 8:
			if score[d] > best_s:
				best_s = score[d]
				best = d
		if best < 0:
			break
		score[best] = -INF
		if try_walk(best):
			movedir = best
			angle = DIR_ANGLE[best]
			return
	movedir = DI.NODIR

func A_Pain() -> void:
	game.play_sound(info.get("painSound"), self)

func A_Scream() -> void:
	game.play_sound(info.get("deathSound"), self)

func A_XScream() -> void:
	game.play_sound("gib", self)

func A_Fall() -> void:
	solid = false
	height = 8.0
	game.play_sound("bodyfall", self)

# ------------------------------------------------------------------
# THE COLD (js/actor.js chill, soak, freeze, frostTic, thaw) — and what
# fire does to somebody in the ice (burnAway, collapse), and a blow
# (shatter)
# ------------------------------------------------------------------

## Frost in; true if that froze them.
func chill(amount: float) -> bool:
	if removed or dead or not info.get("freezable", false):
		return false
	if ash > 0.0:
		return false
	if burning > 0:
		burning = maxi(0, burning - int(amount * 4))
		torch = maxi(0, torch - int(amount * 4))
		if burning <= 0:
			lit = 0.0
	if frozen:
		frost = FREEZE_AT
		return false
	frost = minf(FREEZE_AT, frost + amount)
	if frost >= FREEZE_AT:
		freeze()
		return true
	return false

## water on somebody alight: true if it put them out
func soak(amount: float) -> bool:
	if removed or dead or ash > 0.0 or burning <= 0:
		return false
	burning = maxi(0, burning - int(amount * 4))
	torch = maxi(0, torch - int(amount * 4))
	if burning > 0:
		return false
	lit = 0.0
	return true

func freeze() -> void:
	if frozen or removed or dead:
		return
	frozen = true
	frost = FREEZE_AT
	burning = 0
	torch = 0
	lit = 0.0
	thaw_state = info.get("freezeReturn", info.get("see", info.get("spawn")))
	solid = true
	panic = 0
	if info.has("frozen"):
		set_state(info.frozen, true)
	state_tics = -1
	game.play_sound("freeze", self)

func frost_tic() -> void:
	if removed:
		return
	# (only their own burning thaws them now: the floor no longer burns)
	if burning > 0:
		frost = maxf(0.0, frost - FIRE_THAW)
	else:
		thaw_tick += 1
		if thaw_tick >= THAW_EVERY:
			thaw_tick = 0
			frost -= 1.0
	if frost < 0.0:
		frost = 0.0
	if frozen and frost <= 0.0:
		thaw()

func thaw() -> void:
	if not frozen:
		return
	frozen = false
	if dead or removed:
		frost = 0.0
		return
	solid = bool(info.get("solid", monster))
	panic = int(info.get("panicTics", 280))
	if game.fx != null:
		game.fx.frost_puff(x, y, z + height * 0.5, 18, 34)
	game.play_sound("thaw", self)
	if thaw_state != null:
		set_state(thaw_state)

## what fire does to somebody still in the ice: eaten where they stand
func burn_away(source = null) -> void:
	if removed or dead or ash > 0.0:
		return
	if not info.has("burnAway"):
		if frozen:
			thaw()
		return
	frozen = false
	burning = 0
	torch = 0
	lit = 0.0
	ash_by = source if source != null else game.player
	var r: Array = info.get("ashTics", [105, 158])
	ash_tics = roundi(r[0] + (U.p_random() / 255.0) * (r[1] - r[0]))
	ash = 0.001
	panic = 0
	solid = bool(info.get("solid", monster))
	set_state(info.burnAway, true)
	game.play_sound("ignite", self)

## a heap of ash on the floor
func collapse(source = null) -> void:
	if removed:
		return
	dead = true
	solid = false
	shootable = false
	game.play_sound("bodyfall", self)
	if game.fx != null:
		game.fx.puff(x, y, z + 10, 26, 130)
		game.fx.ember(x, y, z + 6, 8, 0.5)
	if game.giblets != null:
		game.giblets.ash_pile(self)
	if monster:
		game.on_monster_killed(self, source if source != null else ash_by)
	remove()

## a block of ice, struck
func shatter(source, opts := {}) -> void:
	if removed:
		return
	dead = true
	solid = false
	shootable = false
	if game.giblets != null:
		game.giblets.shatter(self, opts)
	if monster:
		game.on_monster_killed(self, source)
	remove()

# ------------------------------------------------------------------
# THE BORE, in a head (js/actor.js bore, boreTic, boreBurst)
# ------------------------------------------------------------------

func bore(by = null) -> String:
	if removed or dead:
		return ""
	if frozen:
		shatter(by, {"impact": true, "force": 1.4})
		return "shatter"
	if ash > 0.0:
		collapse(by)
		return "collapse"
	if bored > 0:
		return ""
	bored = BORE_TICS
	bored_by = by if by != null else game.player
	panic = 0
	if info.has("bored"):
		set_state(info.bored, true)
	state_tics = -1
	game.play_sound(info.get("painSound"), self)
	return "drill"

func bore_tic() -> void:
	bored -= 1
	if bored > 0:
		var top := z + height * 0.9
		if (bored & 1) == 0 and game.giblets != null:
			game.giblets.spurt(self)
		if bored % 4 == 0 and game.fx != null:
			game.fx.blood_puff(x, y, top)
		if bored % 14 == 0:
			game.play_sound(info.get("painSound"), self)
		return
	bore_burst()

## AND THEN THEY EXPLODE: the same coming-apart the flamethrower gets
func bore_burst() -> void:
	var by = bored_by
	bored = 0
	if removed or dead:
		return
	if game.giblets != null:
		game.giblets.spurt(self, 10)
	health = mini(0, int(info.get("gibHealth", 0)) - 1)
	die(by, 100)
