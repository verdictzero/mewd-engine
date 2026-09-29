## MEWD — and one that comes for the fire: the brigade's truck
## (js/vehicles.js FireTruck).
##
## The fire brigade's truck, at the user's request: the police van
## repainted red with a water cannon on its roof, and the first thing in
## the game that is on the side of the building. A SwatVan in everything
## about getting somewhere (see FireBrigade for where it is sent), and a
## different vehicle once it has stopped: nobody gets out of it (yet),
## and the cannon goes to work.
##
## THE CANNON LOOKS, TURNS, AND POURS. Every CANNON_LOOK tics it picks
## the fire it will play on — a burning vehicle first, because those go
## up; then a person alight; then the nearest part of the store's fire or
## the wood's it can see from the nozzle and reach — and the turret slews
## toward it at CANNON_TURN a tic, the barrel lifting to the angle that
## lands a jet there (WaterStream.aim_pitch integrates the jet's own
## flight). Once it is on, it pours, and walks the jet a little either
## side while it does, the way a crew plays a monitor over a fire.
##
## IT STANDS IN THE FIRE and takes a long time about burning: three times
## the squad van's fire armour and half again its fuse.
class_name FireTruck
extends SwatVan

const CANNON_LOOK := 12      # tics between choosing what to play on
const CANNON_BEST := 560.0   # the distance it would rather work at
const CANNON_NEAR := 200.0   # and closer than this it will not aim
## how high over the nozzle the jet's shoulder is, which is the line that
## decides whether it can reach a fire — see find_fire
const CANNON_ARC := 160.0
const CANNON_TURN := 0.045   # radians a tic the turret slews
const CANNON_LIFT := 0.03    # and the barrel
const CANNON_ON := 0.09      # how close to on target before it pours
const CANNON_SWEEP := 0.07   # how far either side it walks the jet
const HOSE_NOTE_EVERY := 9   # tics between the hiss
const FIREHORN_EVERY := 24   # tics between the two notes

var gun_yaw := 0.0           # the turret, against the body
var gun_pitch := 0.12        # the barrel
var target := {}             # {x, y, z, kind, ref}
var look_tick := 0
var pouring := 0             # tics poured, ever
var hose_tick := 0
var reach := 0.0

func _init(f, d: VehicleModel, r: Array, opts := {}) -> void:
	super(f, d, r, opts)
	notes = ["firehorn", "firehorn2"]
	note_every = FIREHORN_EVERY
	fire_armour = 24.0
	char_fuse = 6.0
	reach = WaterStream.hose_reach() * 0.94
	aim_gun()

func tic() -> void:
	super()
	if state == "parked" and not gun.is_empty():
		fight()

## Where the pivot of the cannon is in the world, now (map space).
func pivot_world() -> Vector3:
	var o := Vehicle.turn(def.to_mesh(def.cannon.pivot, mid), yaw, rx, rz)
	return Vector3(x + o.x, y - o.z, cz + o.y)

## And the muzzle, at the cannon's present yaw and elevation.
func nozzle() -> Vector3:
	var L: float = def.length
	var c: Dictionary = def.cannon
	var pv := pivot_world()
	var d: Vector3 = (c.tip - c.pivot) * L
	var cp := cos(gun_pitch)
	var sp := sin(gun_pitch)
	var fx := d.x * cp - d.z * sp
	var fz := d.x * sp + d.z * cp
	var Y := yaw + gun_yaw
	var cy := cos(Y)
	var sy := sin(Y)
	return Vector3(pv.x + fx * cy - d.y * sy, pv.y + fx * sy + d.y * cy, pv.z + fz)

## The turret and the barrel onto the drawing.
func aim_gun() -> void:
	if gun.is_empty():
		return
	gun.yaw.rotation.y = gun_yaw
	gun.pitch.rotation.z = gun_pitch

## Is this target still worth pouring on?
func still_alight(t: Dictionary) -> bool:
	var g = game()
	if t.is_empty():
		return false
	match t.kind:
		"car":
			return t.ref.whole() and t.ref.burning > 0 and t.ref.state != "charring"
		"person":
			return not t.ref.dead and not t.ref.removed and t.ref.burning > 0
		"cell":
			return g.fire != null and g.fire.heat[t.ref] > 0
		"tree":
			var forest = g.get("forest")
			return forest != null and forest.burning_cells() > 0
	return false

## The fire it will play on next, or {}: see the note at the top.
func find_fire() -> Dictionary:
	var g = game()
	var lv: Level = g.level
	var from := pivot_world()
	var R2 := reach * reach
	var cands := []
	# SCORED BY HOW WELL IT CAN BE WORKED, not by how near it is: a monitor
	# on a roof plays on the fire in front of it, at a working distance,
	# rather than on its own feet
	var add := func(px: float, py: float, pz: float, kind: String, ref, bias: float) -> void:
		var d2 := U.dist2(from.x, from.y, px, py)
		if d2 > R2 or d2 < CANNON_NEAR * CANNON_NEAR:
			return
		cands.append({"x": px, "y": py, "z": pz, "kind": kind, "ref": ref, "score": absf(sqrt(d2) - CANNON_BEST) - bias})
	for v in fleet.all:
		if v == self or not v.whole() or not (v.burning > 0) or v.state == "charring":
			continue
		add.call(v.x, v.y, v.ground + 20.0, "car", v, 700.0)
	for a in g.actors:
		if a.dead or a.removed or not (a.burning > 0) or a.vehicle != null:
			continue
		add.call(a.x, a.y, a.z + 20.0, "person", a, 350.0)
	# (the grid world's burning boxes are not ported)
	var F = g.fire
	if F != null and F.hot_cells > 0:
		var act: PackedInt32Array = F.active
		var n := act.size()
		var step := maxi(1, n / 160)
		for k in range(0, n, step):
			var i: int = act[k]
			if F.heat[i] < 40:
				continue
			var j: int = i % F.plane
			var cx: float = F.world_x(j % F.cols)
			var cy: float = F.world_y(j / F.cols)
			var sec := lv.sector_at(cx, cy)
			# and the hottest of it first, by up to half a working distance
			add.call(cx, cy, (sec.floor if sec else 0.0) + 12.0, "cell", i, float(F.heat[i]))
	var W = g.get("forest")
	if W != null and W.burning_cells() > 0:
		for e in W.emitters(from.x, from.y, reach, 12):
			var sec := lv.sector_at(e.x, e.y)
			add.call(e.x, e.y, (sec.floor if sec else 0.0) + minf(60.0, e.h * 0.5), "tree", null, 100.0)
	cands.sort_custom(func(a, b): return a.score < b.score)
	# THE ONES THE JET CAN ACTUALLY GET TO. A monitor LOBS, so sight is
	# taken from the arc's shoulder, a hundred and sixty units over the
	# nozzle, which clears a low thing in the way and is still stopped by
	# a tall one
	for k in mini(cands.size(), 12):
		var c: Dictionary = cands[k]
		if not lv.sight_blocked(from.x, from.y, from.z + CANNON_ARC, c.x, c.y, c.z + 10.0):
			return c
	return {}

## One tic of the cannon at work.
func fight() -> void:
	var g = game()
	# a burning car or person is held until it is out; a patch of the
	# store or the wood is looked at again every time, because it moves
	look_tick += 1
	var due := look_tick >= CANNON_LOOK
	if due:
		look_tick = 0
	var alight := still_alight(target)
	if not alight:
		target = {}
	if due and (not alight or target.kind == "cell" or target.kind == "tree"):
		target = find_fire()
	var t := target
	var want_yaw := 0.0
	var want_pitch := 0.12
	var pour := false
	if not t.is_empty():
		var pv := pivot_world()
		var sweep := sin(g.tics * 0.11) * CANNON_SWEEP
		want_yaw = U.angle_norm(atan2(t.y - pv.y, t.x - pv.x) + sweep - yaw)
		var d := Vector2(t.x - pv.x, t.y - pv.y).length()
		var p = WaterStream.aim_pitch(d, pv.z - t.z)
		if p != null:
			want_pitch = p
			pour = true
	var dy := U.angle_norm(want_yaw - gun_yaw)
	gun_yaw = U.angle_norm(gun_yaw + clampf(dy, -CANNON_TURN, CANNON_TURN))
	var dp := want_pitch - gun_pitch
	gun_pitch += clampf(dp, -CANNON_LIFT, CANNON_LIFT)
	aim_gun()
	var water = fleet.water
	if pour and absf(dy) < CANNON_ON + CANNON_SWEEP and absf(dp) < 0.12 and water != null:
		water.fire(nozzle(), yaw + gun_yaw, gun_pitch)
		pouring += 1
		hose_tick += 1
		if hose_tick >= HOSE_NOTE_EVERY:
			hose_tick = 0
			g.play_sound("hose", self)
