## MEWD — the fire brigade (js/brigade.js).
##
## A supermarket alight is the fire brigade's business, as the top of
## Responders has said since there was one. This sends somebody, at the
## user's request: the user's fire truck (FireTruck), with its water
## cannon working. It does not yet put firefighters on the ground; the
## truck is the whole of the brigade for now.
##
## WHAT CALLS THEM IS THE FIRE, not you: anything alight — the store, the
## wood, a car in the lot — for CALL_AFTER seconds, all told. The SWAT
## answer the trigger; the brigade answer the smoke.
##
## HOW MANY. One truck at the call, and then another every SEND_EVERY
## seconds for as long as something is still burning, up to one per
## CELLS_PER_TRUCK cells alight and never more than MAX_TRUCKS.
##
## WHERE THEY GO is where the fire is: the thickest part of whatever is
## burning (hotspot), on the same ring and by the same arithmetic the
## SWAT use to come to you (Responders.chase_stand), keeping STOP back
## from it because a fire engine parked in the fire is a second fire. A
## fire INSIDE the building is fought from the fire lane.
##
## (The grid world's burning boxes and its streets — js/boxes.js and
## `lanes` in js/maps/grid.js — are not ported, so neither is laneStand.)
class_name FireBrigade
extends RefCounted

const BRIGADE := {
	"key": "fire",
	"callAfter": 8 * U.TICRATE,    # tics of anything alight before the call
	"sendEvery": 40 * U.TICRATE,   # between trucks while it is still burning
	"cellsPerTruck": 60,           # how much fire one truck is for
	"maxTrucks": 4,                # and never more than this on the scene
	"bays": 9,                     # the fire lane, shared with the SWAT
	# the stand, in the units Responders.chase_stand takes
	"stand": 620.0, "push": 6000.0, "stop": 520.0,
	# and how far the cannon can actually work
	"reach": 1150.0,
}

var game
var responders: Responders
var fleet
var model_for: Callable
var alight := 0              # tics anything has been burning, all told
var called := false
var called_at := -1
var next_at := -1
var sent := 0
var trucks: Array = []
## the row the responders' machinery reads a force by
var force := {"def": {"key": "fire", "name": "the fire brigade", "model": "firetruck", "van": FireTruck}, "num": BRIGADE}

func _init(g, r: Responders, vehicles, models: Callable) -> void:
	game = g
	responders = r
	fleet = vehicles
	model_for = models

## How much is burning, in cells: the store's, the wood's, and a vehicle
## alight counted as a patch of each.
func burning() -> int:
	var g = game
	var n := 0
	if g.fire != null:
		n += g.fire.burning_cells()
	var forest = g.get("forest")
	if forest != null:
		n += forest.burning_cells()
	for v in fleet.all:
		if v.whole() and v.burning > 0:
			n += 12
	return n

func live_trucks() -> Array:
	return trucks.filter(func(v): return v.whole())

## How many trucks this much fire wants on the scene.
func cap_for(cells: int) -> int:
	return maxi(1, mini(BRIGADE.maxTrucks, ceili(cells / float(BRIGADE.cellsPerTruck))))

func tic() -> void:
	var g = game
	if model_for.call("firetruck") == null:
		return
	var cells := burning()
	if cells > 0:
		alight += 1
	if not called:
		if alight < BRIGADE.callAfter:
			return
		called = true
		called_at = g.tics
		next_at = g.tics
		g.play_sound("firehorn", null)
		if g.has_method("on_responders"):
			g.on_responders("called", force.def)
	if g.tics < next_at or cells <= 0:
		return
	if live_trucks().size() >= cap_for(cells):
		return
	if send() != null:
		next_at = g.tics + BRIGADE.sendEvery
	else:
		next_at = g.tics + U.TICRATE       # nowhere to stand yet; ask again shortly

## The thickest part of what is burning: of a handful of burning points,
## the one with the most of the others near it.
func hotspot():
	var g = game
	var pts := []
	var F = g.fire
	if F != null and F.hot_cells > 0:
		var act: PackedInt32Array = F.active
		var step := maxi(1, act.size() / 48)
		for k in range(0, act.size(), step):
			var i: int = act[k]
			if F.heat[i] < 40:
				continue
			var j: int = i % F.plane
			pts.append(Vector2(F.world_x(j % F.cols), F.world_y(j / F.cols)))
	var W = g.get("forest")
	if W != null and W.burning_cells() > 0:
		var p = g.player
		for e in W.emitters(p.x if p else 0.0, p.y if p else 0.0, 1e6, 24):
			pts.append(Vector2(e.x, e.y))
	for v in fleet.all:
		if v.whole() and v.burning > 0:
			for k in 4:
				pts.append(Vector2(v.x, v.y))
	if pts.is_empty():
		return null
	var best: Vector2 = pts[0]
	var bn := -1
	for a in pts:
		var n := 0
		for b in pts:
			if a.distance_squared_to(b) < 450.0 * 450.0:
				n += 1
		if n > bn:
			bn = n
			best = a
	return best

## Where the next truck stands, for a fire at `at`.
func stand_for(at: Vector2) -> Dictionary:
	var R := responders
	var lv: Level = game.level
	if R.ring().is_empty():
		return {}
	var aim := {"x": at.x, "y": at.y}
	var sec := lv.sector_at(at.x, at.y)
	if sec and not sec.outdoor:
		# INDOORS: the fire lane. A bay first, and when they are gone, along
		# the ring by the doors like everybody else
		var bay := R.free_bay(force)
		if not bay.is_empty():
			return R.bay_stand(bay)
		var doors := R.doors_point()
		if not doors.is_empty():
			aim = doors
	# THE ONE IT CAN WORK FROM, not simply the nearest: a stand that can
	# SEE the fire and reach it beats one that cannot, and among those
	# the nearest wins
	var best := {}
	var bd := INF
	var bw := false
	for k in 17:
		var slot := 0 if k == 0 else ((k + 1) >> 1 if k & 1 else -(k >> 1))
		var s := R.chase_stand(aim, slot, BRIGADE)
		if not R.stand_clear(s, BRIGADE):
			continue
		# and never ON the fire: a truck parked in it is a second fire
		if game.fire != null and game.fire.heat_at(s.x, s.y) > 0.0:
			continue
		var d := Vector2(s.x - aim.x, s.y - aim.y).length()
		var ss := lv.sector_at(s.x, s.y)
		var sa := lv.sector_at(aim.x, aim.y)
		var works: bool = d < BRIGADE.reach and not lv.sight_blocked(s.x, s.y, (ss.floor if ss else 0.0) + 110.0,
			aim.x, aim.y, (sa.floor if sa else 0.0) + 40.0)
		if bw and not works:
			continue
		if works and not bw:
			bw = true
			bd = INF
		if d < bd:
			bd = d
			best = s
			s.works = works
		if bw and bd <= BRIGADE.stop + 36.0:
			break
	return best

## One truck on the road, to the fire.
func send():
	var g = game
	var R := responders
	var model: VehicleModel = model_for.call("firetruck")
	if model == null:
		return null
	var hot = hotspot()
	if hot == null:
		return null
	var stand := stand_for(hot)
	if stand.is_empty():
		return null
	var side := R.side_for(stand.ring)
	var route := R.route_to(stand, side, 0.0, true)
	if route.size() < 2:
		return null
	var v := FireTruck.new(fleet, model, route)
	v.park_angle = route[route.size() - 1].angle
	v.stand = stand
	v.bay = stand.get("bay", null)
	v.side = side
	v.force = force
	fleet.add_vehicle(v)
	# in the responders' list, so a SWAT van does not park on it — but
	# never unloaded: nobody's force loop matches this force
	R.vans.append(v)
	trucks.append(v)
	sent += 1
	if g.has_method("on_responders"):
		g.on_responders("van", v)
	return v
