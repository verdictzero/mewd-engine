## MEWD — the lot (js/vehicles.js Vehicles and Chunk).
##
## Every vehicle in the world — the car park's, and whatever has driven
## in — and every piece of one that has come off. Ticked, counted and
## cleaned up together; drawn as children of this node, which is a child
## of the Game, so they are in the main world with everything else.
##
## THE SLAB IS NOT PORTED (see VehicleModel): a parked car is a node of
## its own here from the start, and so is a wreck, and so is a piece of
## one on the tarmac.
class_name Vehicles
extends Node3D

const MAX_RESTING_CHUNKS := 200

## AND THE QUIET ONES ARE IN IT TWICE: a real car park is mostly white,
## silver and beige with a few colours in it (js/vehicles.js PAINT)
const PAINT := [
	Vector3(1.00, 1.00, 1.00),   # white, which is the model as its author painted it
	Vector3(1.00, 1.00, 1.00),
	Vector3(0.94, 0.92, 0.84),   # cream, a van that has been outside a while
	Vector3(0.94, 0.92, 0.84),
	Vector3(0.78, 0.80, 0.84),   # silver
	Vector3(0.92, 0.68, 0.30),   # ochre
	Vector3(0.76, 0.50, 0.28),   # rust brown
	Vector3(0.46, 0.72, 0.44),   # green
	Vector3(0.40, 0.66, 0.82),   # sky blue
	Vector3(0.80, 0.34, 0.30),   # maroon
	Vector3(0.95, 0.26, 0.20),   # and the loud ones, which are the exceptions
	Vector3(0.30, 0.46, 0.92),   # they are in a real car park: one red, one
	Vector3(0.96, 0.80, 0.24),   # blue, one yellow
	Vector3(0.36, 0.74, 0.70),   # and one turquoise, because it is 1987
]

var game
var all: Array = []
var flying: Array = []       # chunks still in the air
var resting: Array = []      # and chunks that are not

func _init(g) -> void:
	game = g
	name = "Vehicles"

## Which paint a bay gets, off its own position — NOT A FRESH RANDOM, so
## the lot is the same lot every time the level is built.
static func paint_of(slot: Dictionary) -> Vector3:
	var h: int = (int(slot.x) * 374761393 + int(slot.y) * 668265263 + int(slot.get("variant", 0)) * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return PAINT[((h ^ (h >> 16)) & 0xFFFFFFFF) % PAINT.size()]

## Fill the bays: `slots` is the map's carSlots ({x, y, angle, variant}).
## ONE VAN, SEVENTY-SEVEN TIMES, at the user's request — but not all the
## same colour (see PAINT).
func place(slots: Array, def: VehicleModel) -> void:
	if def == null:
		return
	for slot in slots:
		var sec: Level.Sector = game.level.sector_at(slot.x, slot.y)
		all.append(Vehicle.new(self, def, {
			"x": float(slot.x), "y": float(slot.y), "z": sec.floor if sec else 0.0,
			"angle": float(slot.get("angle", 0.0)),
			"light": sec.light if sec else 0.74,
			"sky": (sec.sky if sec.sky > 0.0 else (1.0 if sec.outdoor else 0.0)) if sec else 1.0,
			"paint": paint_of(slot),
		}))

## A vehicle that is not one of the lot's — a van that has driven in.
func add_vehicle(v) -> Vehicle:
	all.append(v)
	return v

func add_chunk(c) -> void:
	flying.append(c)

func tic() -> void:
	for v in all:
		v.tic()
	for i in range(flying.size() - 1, -1, -1):
		var c = flying[i]
		c.tic()
		if not c.resting:
			continue
		flying.remove_at(i)
		resting.append(c)
		# and if the tarmac is knee deep in it, the oldest piece goes
		if resting.size() > MAX_RESTING_CHUNKS:
			resting.pop_front().discard()
	for c in resting:
		c.smoulder_tic()

## What the HUD would say, if it said anything about the car park.
func wrecked() -> int:
	var n := 0
	for v in all:
		if v.state != "parked":
			n += 1
	return n

# =====================================================================
# ONE PIECE OF IT: the model's own surface inside a small box of the
# vehicle's own model space, so a piece off the tail is painted with the
# tail because it IS the tail.
# =====================================================================
class Chunk:
	var fleet
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var ground := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var yaw := 0.0
	var rx := 0.0
	var rz := 0.0
	var roll_rate := 0.0
	var pitch_rate := 0.0
	var yaw_rate := 0.0
	var resting := false
	var bounced := false
	var glow := Vehicle.SMOULDER
	var tick := 0
	var corners: Array = []
	var node: MeshInstance3D

	func _init(f, def: VehicleModel, lo: Vector3, hi: Vector3, o: Dictionary) -> void:
		fleet = f
		x = o.x; y = o.y; z = o.z; ground = o.ground
		vx = o.vx; vy = o.vy; vz = o.vz
		yaw = _r() * TAU
		rx = _r() * TAU
		rz = _r() * TAU
		roll_rate = (_r() - 0.5) * 2.0 * Vehicle.CHUNK_SPIN
		pitch_rate = (_r() - 0.5) * 2.0 * Vehicle.CHUNK_SPIN
		yaw_rate = (_r() - 0.5) * 2.0 * Vehicle.CHUNK_SPIN
		var mid := (lo + hi) / 2.0
		for cx in [lo.x, hi.x]:
			for cy in [lo.y, hi.y]:
				for czz in [lo.z, hi.z]:
					corners.append(def.to_mesh(Vector3(cx, cy, czz), mid))
		node = MeshInstance3D.new()
		node.name = "debris"
		node.mesh = def.chunk_mesh(lo, hi)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := def.chunk_material()
		m.set_shader_parameter("light", float(o.light) * 0.7)
		m.set_shader_parameter("sky", o.sky)
		m.set_shader_parameter("charred", Vehicle.CHUNK_CHAR)
		m.set_shader_parameter("paint", o.paint)
		node.material_override = m
		fleet.add_child(node)
		place()

	static func _r() -> float:
		return U.p_random() / 255.0

	func place() -> void:
		node.position = U.v3(x, y, z)
		node.rotation = Vector3(rx, yaw, rz)

	func tic() -> void:
		var g = fleet.game
		vz -= Vehicle.GRAVITY
		z += vz
		x += vx
		y += vy
		rx += roll_rate
		rz += pitch_rate
		yaw += yaw_rate
		tick += 1
		if (tick & 3) == 0 and g.fx != null:
			g.fx.ember(x, y, z, 1, 0.8)
		var low := Vehicle.extent_of(corners, rx, rz).x
		if vz < 0.0 and z + low <= ground:
			var s: Level.Sector = g.level.sector_at(x, y)
			if s:
				ground = s.floor
			# One bounce if it came down hard, and then it is scrap on the
			# tarmac: the spin bleeds off with it
			if vz < -6.0 and not bounced:
				bounced = true
				z = ground - low
				vz *= -Vehicle.CHUNK_BOUNCE
				vx *= 0.5
				vy *= 0.5
				roll_rate *= 0.4
				pitch_rate *= 0.4
				yaw_rate *= 0.4
			else:
				land()
				return
		place()

	func land() -> void:
		resting = true
		# it comes to rest FLAT: roll and pitch to the nearest half turn
		rx = roundf(rx / PI) * PI
		rz = roundf(rz / PI) * PI
		z = ground - Vehicle.extent_of(corners, rx, rz).x
		place()

	func discard() -> void:
		if node != null:
			node.queue_free()
			node = null

	## Lying there going out. The particles stop after twenty seconds; the
	## coals do not, because `charred` stays in its material.
	func smoulder_tic() -> void:
		if glow <= 0:
			return
		glow -= 1
		var g = fleet.game
		var k := float(glow) / Vehicle.SMOULDER
		tick += 1
		if g.fx == null:
			return
		if tick % 14 == 0 and _r() < k:
			g.fx.ember(x, y, z + 4.0, 1, 0.5 * k)
		if tick % 47 == 0 and _r() < k:
			g.fx.puff(x, y, z + 8.0, 16.0, 120)
