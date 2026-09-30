## MEWD — who comes when a supermarket is on fire at 2am (js/responders.js).
##
## THE SWAT COME, and they are the first thing in the game that fights
## back. The shape underneath is an alarm that only climbs and six tiers
## dispatched at a threshold, kept because the night manager and the rest
## are still coming one day; what is new on top of it is the squad, on
## its own trigger, which does not wait for the alarm.
##
## WHAT CALLS THEM IS THE TRIGGER, at the user's request: not the fire —
## a supermarket alight is the fire brigade's business — but the first
## shot out of any weapon, on the tic you fire it. THREE AT A TIME, at the
## user's request: where one van used to be sent, three are, nose to tail
## from the same end of the road. They unload their crews one at a time
## and, when the crew is out, keep trickling for as long as they stand.
##
## AND THEY COME TO WHEREVER YOU ARE. Inside the building they pull up
## across the fire lane in front of the doors, which is what the map's
## bays say. Anywhere else the destination is YOU: the nearest point on
## the perimeter road, reached by walking the ring the short way round,
## and then off the road toward you for as far as the tarmac holds.
## Hiding moves the fight; it does not end it.
##
## AND IT RAMPS EXPONENTIALLY, at the user's request, and the ramp is ONE
## NUMBER: the PRESSURE, 1 at the call and doubling every so many seconds
## from then on, without limit. How many vans may be on the road, how
## many troopers on their feet, how long between vans, how long between
## one trooper and the next — each a starting value times that number,
## read off the curve at the moment the question is asked.
##
## AND THEN THE ARMY COMES, at the user's request: a SECOND FORCE with its
## own clock, its own budget, its own curve starting at 1 the moment it
## is called, its own carrier (the APC, which hovers) and its own soldier
## — called at a PRESSURE rather than a time, so retuning the doubling
## moves the army with it.
##
## WHERE THEY GO is the map's business: world.swatRoutes (the way in from
## each end of the road), world.swatRing (the perimeter road, a closed
## loop) and world.swatBays (where a van may stop at the doors). This
## joins one to the other and drives nothing itself. A map without them
## — or one that says world.noSquads, as the grid and the maze do — is
## sent nobody.
class_name Responders
extends RefCounted

const TICRATE := U.TICRATE

## Who, at what alarm, and how long they take to get here (in tics).
const TIERS := [
	{"tier": 1, "name": "the night manager", "at": 3, "delay": 25 * TICRATE, "count": 1,
		"dispatch": "SOMEBODY HAS NOTICED", "arrive": "THE NIGHT MANAGER IS OUT THE BACK WITH A TORCH"},
	{"tier": 2, "name": "security", "at": 8, "delay": 40 * TICRATE, "count": 2,
		"dispatch": "SOMEBODY HAS CALLED IT IN", "arrive": "SECURITY HAS PULLED INTO THE LOT"},
	{"tier": 3, "name": "the police", "at": 18, "delay": 55 * TICRATE, "count": 2,
		"dispatch": "SIRENS, A LONG WAY OFF", "arrive": "BLUE LIGHTS ON THE ROAD"},
	{"tier": 5, "name": "riot police", "at": 50, "delay": 90 * TICRATE, "count": 4,
		"dispatch": "HELICOPTER", "arrive": "THE VANS ARE HERE"},
	{"tier": 6, "name": "the helicopter", "at": 75, "delay": 120 * TICRATE, "count": 1,
		"dispatch": "YOU CAN HEAR IT COMING", "arrive": "IT IS OVERHEAD"},
]

## How the alarm is made from what the night looks like. (It was the
## fire's, mostly; with the fire that spread gone, it is the killing.)
const ALARM := {
	"kill": 2.0,        # per member of staff
	"max": 100.0,
}

## THE SQUAD, IN NUMBERS. A SMIDGE LESS OF ALL OF IT, at the user's
## request: the doubling is seventy seconds rather than sixty, the
## ceilings down a quarter, the four starting values each one less.
const SWAT := {
	"after": 1,                  # shots fired before anybody is called
	"firstDelay": 0,             # and they are dispatched on that tic
	"doubling": 70 * TICRATE,    # how often the pressure doubles, from the call
	"every": 60 * TICRATE,       # the gap between sends, at pressure 1, give or take a fifth
	"minEvery": 7 * TICRATE,     # and the least it can ever be
	"convoy": 3,                 # vans per send — THREE AT A TIME, the user's number
	"vans": 5,                   # on the road or standing at once, at pressure 1
	"maxVans": 20,               # and the most the engine is asked to carry
	"troopers": 5,               # on their feet at once, at pressure 1
	"maxTroopers": 60,
	"crew": 5,                   # what a van carries
	"unloadEvery": 52,           # tics between one and the next
	"trickle": 10 * TICRATE,     # and after the crew is out, for ever, at pressure 1
	"minTrickle": 3 * TICRATE,
	"bays": 9,                   # spaces along the fire lane, for the doors
	# WHERE A VAN STOPS WHEN IT IS COMING FOR YOU: how far apart two park
	# along the ring, how far off the road one will drive, how close it
	# parks (to the MIDDLE of the van — the nose stops about two hundred
	# off, the user's second thought about it), and how far back down the
	# road the second and third of a send start
	"stand": 560.0, "push": 2600.0, "stop": 300.0, "convoyGap": 460.0,
	# AND WHERE THEY COME FROM WHEN YOU ARE OUTSIDE: into being ON the road,
	# `runIn` back from where they leave it, and further back for as long
	# as that spot is inside your view
	"runIn": 1100.0,
	"runInStep": 500.0,
	"runInTries": 8,
}

## AND THE ARMY, IN THE SAME NUMBERS: FEWER AND HEAVIER is the whole
## design. `at` is the SWAT's pressure at the moment the army is called —
## two, one doubling, seventy seconds after your first shot.
const ARMY := {
	"at": 2.0,
	"firstDelay": 0,
	"doubling": 60 * TICRATE,
	"every": 70 * TICRATE, "minEvery": 9 * TICRATE,
	"convoy": 2, "vans": 2, "maxVans": 10,
	"troopers": 4, "maxTroopers": 40,
	"crew": 8, "unloadEvery": 40, "trickle": 11 * TICRATE, "minTrickle": 3 * TICRATE,
	"bays": 9,
	"stand": 700.0, "push": 2600.0, "stop": 360.0, "convoyGap": 620.0, "runIn": 1100.0,
}

## HOW WIDE "YOU ARE LOOKING AT IT" IS: a little over half the frame
const SEE_HALF := 1.05

var game
var alarm := 0.0
var dispatched := {}         # tier -> tic dispatched
var arrived := {}
var defeated_count := 0
var waves: Array = []        # what spawn() was asked for, for anyone watching
var tics := 0
## THE FORCES, one state block each and in the order of the night
var forces: Array = []
var swat: Dictionary
var army: Dictionary
var vans: Array = []         # every vehicle that has come, of either force
var side_n := 0              # which end of the road the next one uses
## the models each force arrives in: a callable key -> VehicleModel (the
## Escalation's), so a force with no vehicle simply does not come
var model_for: Callable
## the fleet they are added to (Vehicles)
var fleet
var _ring := {}

## WHO IS ON THE ROAD, IN ORDER: `troop` is the actor that gets out,
## `model` the vehicle it gets out of, `van` the class that drives it.
func _init(g, vehicles, models: Callable) -> void:
	game = g
	fleet = vehicles
	model_for = models
	forces = [
		{"def": {"key": "swat", "name": "the SWAT", "troop": "SWAT", "model": "police", "van": SwatVan}, "num": SWAT},
		{"def": {"key": "army", "name": "the army", "troop": "ARMY", "model": "apc", "van": ArmyApc}, "num": ARMY},
	]
	for f in forces:
		f.merge({"called": false, "calledAt": -1, "nextVanAt": -1, "gap": 0.0, "spawned": 0})
	swat = forces[0]
	army = forces[1]

## what the map says, from its world block or the level itself
func map_value(key: String):
	var lv: Level = game.level
	if lv.world.has(key):
		return lv.world[key]
	return lv.get(key)

static func alarm_of(kills: int) -> float:
	return minf(ALARM.max, kills * ALARM.kill)

## The curve, as a pure function: how many times harder the night is
## pressing `t` tics after the call.
static func pressure_after(t: float) -> float:
	return pow(2.0, maxf(0.0, t) / SWAT.doubling)

static func _rnd() -> float:
	return U.p_random() / 255.0

func called() -> bool:
	return swat.called

func spawned() -> int:
	var n := 0
	for f in forces:
		n += f.spawned
	return n

# ------------------------------------------------------------------
# THE CURVE, read off the clock
# ------------------------------------------------------------------

func pressure_of(f: Dictionary) -> float:
	return pressure_after(tics - f.calledAt) if f.called else 0.0

func van_cap_of(f: Dictionary) -> int:
	return mini(f.num.maxVans, floori(f.num.vans * pressure_of(f)))

func trooper_cap_of(f: Dictionary) -> int:
	return mini(f.num.maxTroopers, floori(f.num.troopers * pressure_of(f)))

## The gap to one force's next send: its starting gap over its pressure,
## give or take a fifth so two nights are not the same night.
func gap_now(f: Dictionary) -> float:
	return maxf(f.num.minEvery, f.num.every * (0.8 + 0.4 * _rnd()) / pressure_of(f))

func trickle_now(f: Dictionary) -> float:
	return maxf(f.num.minTrickle, f.num.trickle / pressure_of(f))

func pressure() -> float:
	return pressure_of(swat)

func tier() -> int:
	var t := 0
	for k in arrived:
		t = maxi(t, k)
	return t

## Where the road leaves the map: whoever comes, comes from one of these.
func arrival_points() -> Array:
	var ends = map_value("roadEnds")
	if ends is Array and not ends.is_empty():
		return ends
	var p = game.player
	return [{"x": p.x if p else 0.0, "y": p.y - 400.0 if p else 0.0, "heading": PI / 2, "side": "the lot"}]

func tic() -> void:
	tics += 1
	var g = game
	squad_tic()
	# once a second is plenty for something that only ever climbs
	if tics % TICRATE:
		return
	var a := alarm_of(int(g.kills))
	if a > alarm:
		alarm = a
	for t in TIERS:
		if not dispatched.has(t.tier) and alarm >= t.at:
			dispatched[t.tier] = tics
			_hook("dispatch", t)
		if dispatched.has(t.tier) and not arrived.has(t.tier) and tics - int(dispatched[t.tier]) >= t.delay:
			arrived[t.tier] = true
			var pts := arrival_points()
			var from: Dictionary = pts[(t.tier + tics) % pts.size()]
			# what was asked for, for anyone watching: what actually drives
			# in is the squad, below
			waves.append({"tier": t.tier, "name": t.name, "count": t.count, "x": from.x, "y": from.y, "tic": tics})
			_hook("arrive", t)

## The game's own hook, if it has one (js/game.js onResponders).
func _hook(what: String, arg) -> void:
	if game.has_method("on_responders"):
		game.on_responders(what, arg)

# ------------------------------------------------------------------
# THE SQUAD
# ------------------------------------------------------------------

func live_vans() -> Array:
	return vans.filter(func(v): return v.whole())

func live_vans_of(f: Dictionary) -> Array:
	return vans.filter(func(v): return v.force == f and v.whole())

## Troops of one force on their feet, anywhere. Counted, not kept.
func troopers_of(f: Dictionary) -> int:
	var n := 0
	var t: String = f.def.troop
	for a in game.actors:
		if a.type == t and not a.dead and not a.removed:
			n += 1
	return n

func troopers() -> int:
	var n := 0
	for f in forces:
		n += troopers_of(f)
	return n

func squad_tic() -> void:
	var g = game
	var p = g.player
	if p == null:
		return
	# AND SOME WORLDS SEND NOBODY (the grid, the maze)
	if map_value("noSquads"):
		return
	# THE CALL: one pull of the trigger and the first convoy is on the road
	# that tic — or one death, if somebody has managed to die without a
	# shot being fired, which the fire can do on its own
	if not swat.called and (int(p.shots_fired) >= SWAT.after or int(g.kills) > 0):
		call_force(swat)
	if not swat.called or p.dead:
		return
	# AND THEN EVERYBODY WHO IS ALREADY COMING, plus anybody the curve has
	# just reached
	for f in forces:
		if not f.called:
			if not (float(f.num.get("at", 0.0)) > 0.0) or pressure() < float(f.num.at):
				continue
			call_force(f)
		force_tic(f)

## One force's turn: the next send if its curve allows another on the
## road, and then whatever comes out of the ones that are here.
func force_tic(f: Dictionary) -> void:
	var N: Dictionary = f.num
	if tics >= f.nextVanAt and live_vans_of(f).size() < van_cap_of(f) and model_for.call(f.def.model) != null:
		send_convoy(f)
		f.gap = gap_now(f)
		f.nextVanAt = tics + roundi(f.gap)
	var cap := trooper_cap_of(f)
	for v in vans:
		if v.force != f:
			continue
		if v.state != "parked" and v.state != "charring":
			continue
		if v.unload_at < 0:
			v.unload_at = tics + int(N.unloadEvery)
		if tics < v.unload_at:
			continue
		if troopers_of(f) >= cap:
			v.unload_at = tics + TICRATE
			continue
		if unload(v, f) != null:
			v.unloaded += 1
			v.unload_at = tics + (int(N.unloadEvery) if v.unloaded < int(N.crew) else roundi(trickle_now(f)))
		else:
			v.unload_at = tics + 12          # the door is blocked; try again shortly

func call_force(f: Dictionary) -> void:
	f.called = true
	f.calledAt = tics
	f.nextVanAt = tics + int(f.num.get("firstDelay", 0))
	f.gap = 0.0
	# NOTHING IS WRITTEN ACROSS THE PICTURE ANY MORE, at the user's
	# request: the siren itself says it
	game.play_sound("siren" if f == swat else "hover", null)
	_hook("called", f.def)

# ------------------------------------------------------------------
# THE RING, AS ONE NUMBER: the perimeter road is a closed loop and every
# question about where a van goes turns into a distance round it
# ------------------------------------------------------------------

static func _v(p) -> Vector2:
	return p if p is Vector2 else Vector2(float(p.x), float(p.y))

func ring() -> Dictionary:
	var pts = map_value("swatRing")
	if not (pts is Array) or pts.size() < 3:
		return {}
	if not _ring.is_empty() and is_same(_ring.pts, pts):
		return _ring
	var segs := []
	var total := 0.0
	for i in pts.size():
		var a := _v(pts[i])
		var b := _v(pts[(i + 1) % pts.size()])
		var len := a.distance_to(b)
		segs.append({"a": a, "b": b, "len": len, "start": total, "d": (b - a) / len})
		total += len
	_ring = {"pts": pts, "segs": segs, "total": total}
	return _ring

## A distance round the loop, as a point and the way you are facing.
func ring_at(t: float) -> Dictionary:
	var R := ring()
	var u := fposmod(t, R.total)
	var s: Dictionary = R.segs[R.segs.size() - 1]
	for q in R.segs:
		if u >= q.start and u <= q.start + q.len:
			s = q
			break
	var p: Vector2 = s.a + s.d * (u - s.start)
	return {"x": p.x, "y": p.y, "dx": s.d.x, "dy": s.d.y}

## How far round the loop the point nearest (x, y) is.
func ring_nearest(x: float, y: float) -> float:
	var R := ring()
	var best := 0.0
	var bd := INF
	for s in R.segs:
		var d := clampf((x - s.a.x) * s.d.x + (y - s.a.y) * s.d.y, 0.0, s.len)
		var p: Vector2 = s.a + s.d * d
		var q := p.distance_squared_to(Vector2(x, y))
		if q < bd:
			bd = q
			best = s.start + d
	return best

## The corners strictly between two points on the loop, the short way
## round, in the order they are driven through.
func ring_path(t0: float, t1: float) -> Array:
	var R := ring()
	var fwd := fposmod(t1 - t0, R.total)
	var dir := 1 if fwd <= R.total - fwd else -1
	var dist: float = fwd if dir > 0 else R.total - fwd
	var out := []
	for s in R.segs:
		var d := fposmod(s.start - t0, R.total) if dir > 0 else fposmod(t0 - s.start, R.total)
		if d > 1.0 and d < dist - 1.0:
			out.append({"d": d, "x": s.a.x, "y": s.a.y})
	out.sort_custom(func(p, q): return p.d < q.d)
	return out.map(func(p): return {"x": p.x, "y": p.y})

## Tarmac a van will drive on: outdoors, and not the wood, the covered
## walkway or the sign it stands on. (And — the port's own addition, for
## worlds like the maze where a hedge is an outdoor sector too — not a
## step up the van could not take from the road it left.)
func drivable(x: float, y: float, from_floor := NAN) -> bool:
	var s: Level.Sector = game.level.sector_at(x, y)
	if s == null or not s.outdoor:
		return false
	var n := s.name.to_lower()
	if n.contains("wood") or n.contains("canopy") or n.contains("sign"):
		return false
	if not is_nan(from_floor) and absf(s.floor - from_floor) > U.MAX_STEP:
		return false
	return true

# ------------------------------------------------------------------
# WHERE THIS ONE IS GOING
# ------------------------------------------------------------------

## Is the player somewhere a van should come to, rather than the doors?
func chasing() -> bool:
	var p = game.player
	return p != null and not p.dead and p.sector != null and p.sector.outdoor

## A stand at the doors: one of the map's bays, squared up along the
## front, with the lead in off the frontage lane.
func bay_stand(bay: Dictionary) -> Dictionary:
	var ay: float = bay.approach.y if bay.has("approach") else bay.y
	var t := ring_nearest(bay.x, ay)
	var on := ring_at(t)
	return {"x": bay.x, "y": bay.y, "bay": bay, "angle": 0.0 if on.dx >= 0.0 else PI, "ring": t,
		"lead": [{"x": bay.x, "y": on.y}, {"x": bay.x, "y": bay.y}]}

## A stand beside a point: `slot` steps along the ring from the point on
## it nearest, then in off the road toward it as far as the tarmac goes.
func chase_stand(p, slot: int, N: Dictionary) -> Dictionary:
	var R := ring()
	var t := ring_nearest(p.x, p.y) + slot * float(N.stand)
	var on := ring_at(t)
	var dx: float = p.x - on.x
	var dy: float = p.y - on.y
	var d := maxf(1.0, sqrt(dx * dx + dy * dy))
	var ux := dx / d
	var uy := dy / d
	var reach := minf(N.push, maxf(0.0, d - N.stop))
	var gone := 0.0
	var x: float = on.x
	var y: float = on.y
	var road: Level.Sector = game.level.sector_at(on.x, on.y)
	var road_floor: float = road.floor if road else NAN
	# THIRTY-FIVE, not seventy: the walk gives up a whole step short of the
	# reach, so the step is the slack in how close one gets
	const STEP := 35.0
	while gone + STEP <= reach:
		var nx := x + ux * STEP
		var ny := y + uy * STEP
		if not drivable(nx, ny, road_floor):
			break
		x = nx
		y = ny
		gone += STEP
	return {"x": x, "y": y, "ring": fposmod(t, R.total),
		"angle": atan2(uy, ux) if gone > 0.0 else atan2(on.dy, on.dx),
		"lead": [{"x": x, "y": y}] if gone > 0.0 else []}

## Nothing already standing there — anybody's.
func stand_clear(s: Dictionary, N: Dictionary) -> bool:
	var r: float = N.stand * 0.7
	for v in live_vans():
		if not v.stand.is_empty() and U.dist2(v.stand.x, v.stand.y, s.x, s.y) < r * r:
			return false
	return true

## The next place one of `f`'s vehicles should go, or {} if nowhere. Inside
## the building a bay in the fire lane; WHEN THE BAYS ARE GONE a stand
## along the ring by the doors instead of nothing. THE BEST OF THEM, NOT
## THE FIRST, at the user's request: every free slot is walked and the
## one that ENDS nearest you wins.
func free_stand(f: Dictionary) -> Dictionary:
	if ring().is_empty():
		return {}
	var N: Dictionary = f.num
	var at = game.player
	if not chasing():
		var bay := free_bay(f)
		if not bay.is_empty():
			return bay_stand(bay)
		var doors := doors_point()
		if not doors.is_empty():
			at = doors
	if at == null:
		return {}
	var best := {}
	var bd := INF
	for k in 17:
		var slot := 0 if k == 0 else ((k + 1) >> 1 if k & 1 else -(k >> 1))
		var s := chase_stand(at, slot, N)
		if not stand_clear(s, N):
			continue
		var d := Vector2(s.x - at.x, s.y - at.y).length()
		if d < bd:
			bd = d
			best = s
		if bd <= N.stop + 36.0:
			break                  # as close as the walk can get
	return best

## The front of the shop: the middle bay, the first one the map lists.
func doors_point() -> Dictionary:
	var bays = map_value("swatBays")
	return bays[0] if bays is Array and not bays.is_empty() else {}

## A bay nobody is standing in. A wreck does not hold one.
func free_bay(f: Dictionary) -> Dictionary:
	var bays = map_value("swatBays")
	if not (bays is Array) or bays.is_empty():
		return {}
	var taken := live_vans().map(func(v): return v.bay)
	for i in mini(bays.size(), int(f.num.bays)):
		if not taken.has(bays[i]):
			return bays[i]
	return {}

## Can the player see this point? No wall check — what is being avoided
## is the POP, and a van that materialises behind a wall is not one.
func can_see(x: float, y: float) -> bool:
	var p = game.player
	if p == null or p.dead:
		return false
	return absf(U.angle_norm(atan2(y - p.y, x - p.x) - p.angle)) < SEE_HALF

## A point `dist` back along a polyline from its end, and the index of the
## vertex before it.
static func back_along(way: Array, dist: float) -> Dictionary:
	var d := dist
	for i in range(way.size() - 1, 0, -1):
		var a := _v(way[i - 1])
		var b := _v(way[i])
		var len := a.distance_to(b)
		if d <= len:
			var f := d / len if len > 0.0 else 0.0
			var p := b + (a - b) * f
			return {"i": i - 1, "x": p.x, "y": p.y}
		d -= len
	return {"i": 0, "x": float(way[0].x), "y": float(way[0].y)}

## Where on this road a vehicle coming for you should come into being:
## `dist` back from the end, and further back while that is somewhere you
## are looking. Returns the road, cut short.
func trim_entry(way: Array, dist: float, N: Dictionary) -> Array:
	if way.size() < 2:
		return way
	var want := dist
	var e := back_along(way, want)
	for k in int(N.get("runInTries", 0)):
		if not can_see(e.x, e.y):
			break
		want += float(N.get("runInStep", 400.0))
		var nxt := back_along(way, want)
		if nxt.i == e.i and nxt.x == e.x and nxt.y == e.y:
			break                  # the road has run out
		e = nxt
	return [{"x": e.x, "y": e.y}] + way.slice(e.i + 1)

## In from one end of the road, round the ring the short way, and in to
## the stand. AND IF THEY ARE COMING FOR YOU they do not drive the road
## at all, at the user's request: the way in is built as it always was
## and then CUT SHORT from its far end (trim_entry). The lead — the last
## leg, off the tarmac and in toward you — is never trimmed.
func route_to(stand: Dictionary, side: String, back := 0.0, sprint = null) -> Array:
	if sprint == null:
		sprint = chasing()
	var routes = map_value("swatRoutes")
	if not (routes is Dictionary) or routes.is_empty() or ring().is_empty():
		return []
	var N := SWAT
	var src: Array = routes[side] if routes.has(side) else routes.values()[0]
	var way := []
	for p in src:
		var q := _v(p)
		way.append({"x": q.x, "y": q.y})
	if not sprint and back > 0.0 and way.size() >= 2:
		var a: Dictionary = way[0]
		var b: Dictionary = way[1]
		var d := maxf(1.0, Vector2(b.x - a.x, b.y - a.y).length())
		a.x -= (b.x - a.x) / d * back
		a.y -= (b.y - a.y) / d * back
	var join: Dictionary = way[way.size() - 1]
	way.append_array(ring_path(ring_nearest(join.x, join.y), stand.ring))
	var on := ring_at(stand.ring)
	way.append({"x": on.x, "y": on.y})
	# everything so far is road; this is where it is cut short
	if sprint:
		way = trim_entry(way, float(N.runIn) + back, N)
	for q in stand.lead:
		way.append({"x": q.x, "y": q.y})
	way[way.size() - 1].angle = stand.angle
	# two points in the same place make a zero-length leg, which the
	# driving reads as arrival
	var out := []
	for i in way.size():
		if i == 0 or Vector2(way[i].x - way[i - 1].x, way[i].y - way[i - 1].y).length() > 1.0:
			out.append(way[i])
	if not out[out.size() - 1].has("angle"):
		out[out.size() - 1].angle = stand.angle
	return out

## Which end of the road they come from: the shorter drive to where they
## are going.
func side_for(ring_t: float) -> String:
	var routes: Dictionary = map_value("swatRoutes")
	var R := ring()
	var best: String = routes.keys()[0]
	var bd := INF
	for name in routes:
		var r: Array = routes[name]
		var e := _v(r[r.size() - 1])
		var fwd := fposmod(ring_t - ring_nearest(e.x, e.y), R.total)
		var d := minf(fwd, R.total - fwd)
		if d < bd:
			bd = d
			best = name
	return best

## A SEND, nose to tail from the same end of the road — three vans at the
## user's request, two APCs, as many as the budget still has room for.
func send_convoy(f: Dictionary) -> Array:
	var room := van_cap_of(f) - live_vans_of(f).size()
	var first := free_stand(f)
	if first.is_empty():
		return []
	var side := side_for(first.ring)
	side_n += 1
	var sent := []
	for k in mini(int(f.num.convoy), room):
		var v = send_van(f, side, k * float(f.num.convoyGap))
		if v == null:
			break
		sent.append(v)
	return sent

func send_van(f: Dictionary, side: String, back := 0.0):
	var g = game
	var model: VehicleModel = model_for.call(f.def.model)
	if model == null:
		return null
	var stand := free_stand(f)
	if stand.is_empty():
		return null
	var route := route_to(stand, side, back)
	if route.size() < 2:
		return null
	var v = f.def.van.new(fleet, model, route)
	v.park_angle = route[route.size() - 1].angle
	v.stand = stand
	v.bay = stand.get("bay", null)
	v.side = side
	v.force = f
	fleet.add_vehicle(v)
	vans.append(v)
	_hook("van", v)
	return v

## One trooper out of the side door, if there is room to stand. THE DOOR
## THEY USE IS THE ONE FACING YOU. Tries the five places along the flank
## before giving up for this tic.
func unload(v, f: Dictionary):
	var g = game
	var lv: Level = g.level
	var p = g.player
	var toward := Vector2(p.x, p.y) if p != null and not p.dead else Vector2(v.x, v.y + 1000.0)
	for k in 5:
		var d: Dictionary = v.door(k, toward)
		var sec := lv.sector_at(d.x, d.y)
		if sec == null:
			continue
		if not room_at(d.x, d.y, 20.0):
			continue
		var a: Actor = g.spawn(f.def.troop, d.x, d.y, d.angle)
		# they know why they are here: the player, from the first step
		a.target = g.player
		a.threshold = 0
		a.set_state(a.info.see)
		f.spawned += 1
		g.play_sound(a.info.get("seeSound"), a)
		return a
	return null

## Nothing solid within `r` of a point, and the player is not there.
func room_at(x: float, y: float, r: float) -> bool:
	var g = game
	for o in g.blockmap.near(x, y):
		if o.removed or not o.solid or o.dead:
			continue
		var rr: float = r + o.radius
		if U.dist2(o.x, o.y, x, y) < rr * rr:
			return false
	var p = g.player
	if p != null and not p.dead and U.dist2(p.x, p.y, x, y) < (r + p.radius) * (r + p.radius):
		return false
	return true
