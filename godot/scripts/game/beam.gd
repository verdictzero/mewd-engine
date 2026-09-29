## MEWD — the positron beam (js/beam.js).
##
## WHAT THE USER ASKED FOR: "the beam from Wing Zero's buster rifle,
## everything in linear path destroyed, like a linear columnar nuclear
## explosion". Every decision in this file is downstream of that
## sentence.
##
## IT IS NOT A LASER. A laser is a line drawn to a hit point. This is a
## COLUMN drawn from the muzzle to the first wall, floor or ceiling along
## its line, and everybody standing between the two is inside it. There
## is no hit point: the whole segment is the hit.
##
## IT IS NOT AN EVENT. It lasts the beam's tics (BEAM_SECONDS in
## weapons.gd) and does its work every tic of that; the feet are nailed
## down (Player.move) and the LINE is nailed down too — origin and
## direction are taken once, at the instant the trigger comes up (_aim),
## so the shot goes exactly where the crosshair was and turning your head
## shows you the column in profile instead of dragging it round.
##
## THE THREE THINGS IT DOES, in the order of the tic:
##   1  the bodies   everything soft inside the column, every tic, for
##                   enough that there is no survivable stage
##   2  the mark     where the column meets the first thing that is NOT a
##                   person it leaves a SEAR — an enormous charred,
##                   glowing, splattered burn — and nothing else
##   3  the picture  fireballs and dust up the line, and a boil of fire
##                   and sparks where it lands
##
## IT DOES NOT TOUCH THE LEVEL, at the user's request: "still shooting
## holes through stuff, i just want massive interesting decals, no
## geometry changes". No holes, no structural collapse, no fire laid in
## the street. A PERSON the column touches still catches, because a
## person is not the level. And so the line STOPS at the first wall: a
## column that cuts nothing cannot go through anything (see _impact).
##
## HOW IT IS DRAWN: a TUBE, real geometry rebuilt every frame round the
## axis, because the player is looking along it and a view-facing quad
## seen end-on is a line one pixel wide. Four nested shells (a flat
## white core, a flat yellow-white body, a mild-Fresnel pale shell and a
## silhouette-only green halo), the near end of the two inner ones
## CAPPED so looking down the bore is a white sun rather than a hole,
## and shock rings travelling out of the muzzle so the column has a
## direction. All additive, none of it writing depth, one draw.
##
## AND ITS LIGHT: a SEGMENT light, not a point — the world shader
## measures every fragment's distance to the axis (world_beam in
## world_light.gdshaderinc) — which outlives the column by AFTERGLOW
## seconds, the "post charge" the user asked for.
class_name BeamSystem
extends Node3D

## HOW FAR IT CAN REACH, in game units: across the town or the store. It
## goes as far as the first wall now; this is only how far it goes down a
## street with nothing at the end of it.
const BEAM_RANGE := 8200.0

## AND HOW WIDE, by stage. It was 46, 82 and 130 — a column eight people
## wide that took the entire front of a house — and at the user's request
## this is not a weapon of mass destruction any more: forty-eight across
## at the top stage takes the person the crosshair was on and at most a
## shoulder of whoever is pressed against them.
const BEAM_RADIUS := [10.0, 16.0, 24.0]

## WHAT IT DOES TO SOMETHING SOFT, per tic, by stage. There is no
## survivable stage and there is not meant to be.
const BEAM_DAMAGE := [900.0, 1800.0, 3200.0]

## THE MARK IT LEAVES, the whole of what the lance does to the level:
## "massive interesting decals". A crater (Decals.sear) and SLAG round it
## (Decals.slag), each with its own seed, the streaks and drops leaning
## the way the beam was going.
##   size      across, in world units, of the crater, by stage
##   slag      how many satellites, by stage
##   reach     how far out they are thrown, as a multiple of the crater
##   slagSize  their size, as a fraction of the crater, min..max
const SEAR := {
	"size": [170.0, 240.0, 320.0],
	"slag": [5, 7, 10],
	"reach": [0.42, 0.95],
	"slagSize": [0.16, 0.34],
}

## HOW FINE THE WALK FOR THE FLOOR IS, in units along the ground: a
## floor or a ceiling has no line to cross, so _impact steps along the
## column asking the sector under each step whether it is still inside.
const IMPACT_STEP := 12.0

## HOW FAR FROM THE AXIS THE LIGHT REACHES, by stage — several times the
## column's radius, because what the user asked to see is the street
## either side picked out — and HOW HARD (the first screenshot at twice
## this was a white rectangle).
const LIGHT_RANGE := [190.0, 300.0, 440.0]
const LIGHT_PEAK := [0.26, 0.38, 0.55]
const LIGHT_COLOR := Color(0.62, 1.0, 0.78)
## AND HOW LONG IT OUTLIVES THE BEAM, in seconds
const AFTERGLOW := 0.9

## THE SHAKE, in radians of view and units of eye, at the peak. A KICK
## and not a rumble: hard on the first few frames and then almost
## nothing, so you can watch where the shot went.
const SHAKE_PEAK := 0.62
const SHAKE_HUM := 0.05
const SHAKE_SETTLE := 7

## The tube: SIDES round, SEGS rings along
const SIDES := 16
const SEGS := 28
## AND THE NEAR END IS CAPPED, because a tube is hollow and the front is
## where the player always is. The two flat-lit shells, at CAP_SEG
## (segment zero is inside HIDE and drawn at nothing).
const CAPS := 2
const CAP_SEG := 1
## the shock rings travelling out of the muzzle
const RINGS := 5
const RING_SPEED := 0.55           # of the beam's length a second
## how many points along the line get particles thrown at them each tic
const SAMPLES := 16

## THE FOUR SHELLS, innermost first. `rim` 0 lit flat (the core must NOT
## be a Fresnel: seen down the bore every surface is edge-on and a
## Fresnel core is a bullseye), 1 mild Fresnel, 2 silhouette only.
##   r radius as a multiple of the stage's, colour, rim, w how much
const SHELLS := [
	{"r": 0.34, "colour": Color(1.00, 1.00, 1.00), "rim": 0.0, "w": 1.70},
	{"r": 0.62, "colour": Color(1.00, 0.99, 0.84), "rim": 0.0, "w": 1.05},
	{"r": 0.94, "colour": Color(0.90, 1.00, 0.66), "rim": 1.0, "w": 0.50},
	{"r": 1.36, "colour": Color(0.44, 1.00, 0.64), "rim": 2.0, "w": 0.20},
]

## THE NECK, IN WORLD UNITS: the column opens out over NECK units from
## the metal and is not drawn at all over the first HIDE of them, so the
## player is never standing inside their own beam. They scale with the
## radius as ratios of the top stage's, a floor under any wider beam.
const NECK := 120.0
const HIDE := 55.0
const NECK_R := NECK / 24.0
const HIDE_R := HIDE / 24.0

var game
var live := false
var stage := 0
var tics := 0          ## how many tics the beam has been out
var total := 0         ## how many it will be out for
var shots := 0         ## how many have been fired, for the tests
var killed := 0
## WHERE THE LINE STOPS, taken with the line: how far along the ground
## the column reaches, and the surface it ends on — {at, n} in map space
## — or empty if it ends in the air. See _impact.
var reach := BEAM_RANGE
var hit := {}
var seared := 0        ## marks left, for the tests
## the line, map space: the muzzle, the heading, and the rise per unit
## of ground
var from := Vector3()
var angle := 0.0
var slope := 0.0
## THE LIGHT OUTLIVES THE COLUMN: the axis frozen where the beam last
## was, and `glow` falling to nothing over AFTERGLOW seconds
var glow := 0.0
var glow_stage := 1
var lit_from := Vector3()
var lit_dir := Vector3(1, 0, 0)
var lit_len := 1.0
var _seed := 0.0
## and how hard the picture is being shaken, 0..1 — read where the eye
## is placed
var shake := 0.0

var _mesh: ArrayMesh
var _mi: MeshInstance3D
var _indices := PackedInt32Array()
var _pos := PackedVector3Array()
var _nrm := PackedVector3Array()
var _col := PackedColorArray()
var _uv := PackedVector2Array()   # x the rim, y the fade

func _init(g) -> void:
	game = g
	name = "Beam"
	_build()

func radius() -> float:
	return BEAM_RADIUS[stage - 1] if stage >= 1 else 0.0

## How long the column is along its own axis: `reach` is along the
## ground, and a pitched column is longer than its shadow.
func length() -> float:
	return reach * sqrt(1.0 + slope * slope)

## 0 at the muzzle flash, 1 as it dies — what the geometry fades on.
func age() -> float:
	return float(tics) / total if total > 0 else 0.0

## the axis as a unit vector, map space
func dir() -> Vector3:
	var cp := 1.0 / sqrt(1.0 + slope * slope)
	return Vector3(cos(angle) * cp, sin(angle) * cp, slope * cp)

# ------------------------------------------------------------------
# Firing
# ------------------------------------------------------------------

## The trigger came up at `st`. The player has already spent the cell
## and nailed the feet down; this starts the column.
func fire(player, st: int) -> void:
	live = true
	stage = clampi(st, 1, BEAM_RADIUS.size())
	tics = 0
	total = maxi(1, int(player.beam_tics))
	shots += 1
	killed = 0
	# THE LINE, TAKEN ONCE AND KEPT — nothing moves it again until the
	# next shot, which is what makes this a rifle
	_aim(player)
	# AND SO IS WHERE IT STOPS, and the mark goes there now, once: a sear
	# laid every tic would be forty of the same sear on top of each other
	_impact()
	_sear()
	# THE MUZZLE GOES FIRST: a flash and a ring of dust at the metal is
	# the half second that says it left a gun
	var fx = game.fx
	if fx != null:
		for i in 11:
			fx.fireball(from.x, from.y, from.z, 18.0 + i * 5.0, 8 + (i & 7))
		fx.wash(from.x, from.y, from.z, 1.1)
	_sparks(from, 12)
	shake = 1.0
	glow = 1.0
	glow_stage = stage

func stop() -> void:
	# WHAT THE SHOT WENT THROUGH, said once, in the corner — only when it
	# did something, and only ever one line
	if live and killed > 0 and game.has_method("toast"):
		game.toast("%d DOWN" % killed)
	live = false
	stage = 0
	tics = 0
	# the light is NOT stopped: it stays on the axis it was on and fades
	# over AFTERGLOW seconds

## WHERE THE SHOT GOES, TAKEN ONCE: the muzzle, and where the player is
## looking at the instant the trigger comes up.
func _aim(player) -> void:
	if game.has_method("nozzle"):
		from = game.nozzle(player)
	else:
		from = Vector3(player.x, player.y, player.eye_z())
	angle = player.angle
	# the pitch as a RISE PER UNIT of ground travelled, because that is
	# what a walk along the ground wants
	slope = tan(clampf(player.pitch, -1.4, 1.4))

## WHERE THE LINE STOPS: the first wall, floor or ceiling along it, as a
## distance along the GROUND in `reach` and the surface in `hit` —
## {at, n}, n the face it lands on turned toward the gun — or BEAM_RANGE
## and {} for a shot that ends in the sky. The walls are one call, the
## same one every round makes; a floor or a ceiling is a walk.
## AN OUTDOOR CEILING IS THE SKY and the column goes on into it.
func _impact() -> Dictionary:
	var lv: Level = game.level
	var ux := cos(angle)
	var uy := sin(angle)
	reach = BEAM_RANGE
	hit = {}
	if lv == null:
		return hit
	var t := from + Vector3(ux, uy, slope) * BEAM_RANGE
	var wall := lv.ray_hit_wall(from.x, from.y, from.z, t.x, t.y, t.z)
	if not wall.is_empty():
		reach = float(wall.t) * BEAM_RANGE
		hit = {"at": Vector3(wall.x, wall.y, wall.z), "n": Decals.wall_normal(wall.line, from.x, from.y)}
	var s := IMPACT_STEP
	var sec: Level.Sector = null
	while s < reach:
		var x := from.x + ux * s
		var y := from.y + uy * s
		var z := from.z + slope * s
		sec = lv.sector_at(x, y, sec)
		if sec != null and lv.layered:
			# the storey the last step was in: a deck stops it from under
			sec = lv.span_in(sec, from.z + slope * maxf(0.0, s - IMPACT_STEP))
		if sec != null:
			var under := z < sec.floor
			var above := (not sec.outdoor or sec.above != -1) and z > sec.ceil
			if under or above:
				# back along the step to the plane it crossed, which for
				# the flat floors that are all of them is exact
				var plane := sec.floor if under else sec.ceil
				var back := clampf((plane - from.z) / slope, s - IMPACT_STEP, s) if slope != 0.0 else s
				reach = back
				hit = {"at": Vector3(from.x + ux * back, from.y + uy * back, plane),
					"n": Vector3(0, 0, 1) if under else Vector3(0, 0, -1)}
				break
		s += IMPACT_STEP
	return hit

## THE MARK, where the column lands: the crater first, then the slag
## thrown across the same surface round it, each at its own distance,
## angle and size, leaning the way the beam was going. Nothing at all
## for a shot that ended in the air.
func _sear() -> int:
	var d = game.decals
	if hit.is_empty() or d == null or not d.has_method("sear"):
		return 0
	var st := stage - 1
	var size: float = SEAR.size[st]
	var bd := dir()
	var at: Vector3 = hit.at
	var n: Vector3 = hit.n
	d.sear(at, n, size, bd)
	var count := 1
	# THE SLAG, across the surface the crater is on: two directions in
	# its plane, from the same basis every decal is laid in
	var flat := absf(n.z) > 0.5
	var a := Vector3(1, 0, 0) if flat else Vector3(-n.y, n.x, 0)
	var b := Vector3(0, 1, 0) if flat else Vector3(0, 0, 1)
	# and the lean: the beam's own direction laid flat on the surface, so
	# more of it goes on past the crater than back
	var la := bd.dot(a)
	var lb := bd.dot(b)
	var ll := sqrt(la * la + lb * lb)
	if ll == 0.0:
		ll = 1.0
	for k in int(SEAR.slag[st]):
		var th := randf() * TAU
		var push := 0.55 * (cos(th) * la + sin(th) * lb) / ll
		var rr: float = size * (SEAR.reach[0] + randf() * (SEAR.reach[1] - SEAR.reach[0])) * (1.0 + push)
		var p := at + a * (cos(th) * rr) + b * (sin(th) * rr)
		var sz: float = size * (SEAR.slagSize[0] + randf() * (SEAR.slagSize[1] - SEAR.slagSize[0]))
		d.slag(p, n, sz, a * cos(th) + b * sin(th))
		count += 1
	seared += count
	return count

# ------------------------------------------------------------------
# One tic of it
# ------------------------------------------------------------------

func tic(player) -> void:
	if not live:
		return
	tics += 1
	# AND THE LINE IS NOT RE-READ: the shot is fixed at the trigger
	var r := radius()
	# ---- 1. everything soft in the column
	_bodies(player, r)
	# ---- 2. NOTHING STANDING IN IT, at the user's request: the mark was
	# left once, in fire(), and the level is exactly the shape it was
	# ---- 3. and what it looks like, up the line and where it lands
	_dress(r)
	# ---- and the light, which is the column's own axis
	lit_from = from
	lit_dir = dir()
	lit_len = length()
	glow = 1.0
	glow_stage = stage
	# THE SHAKE: everything in the first fifth of a second and almost
	# nothing after it
	var settle := minf(1.0, float(tics) / SHAKE_SETTLE)
	shake = SHAKE_PEAK + (SHAKE_HUM - SHAKE_PEAK) * settle

## Everything shootable within the column, every tic. A thing is a
## vertical capsule and the beam is a segment, so the test is the
## distance from its middle to the line — and NOT PAST WHERE IT STOPPED:
## whoever is behind the wall is behind a wall.
func _bodies(player, r: float) -> void:
	var ux := cos(angle)
	var uy := sin(angle)
	var dmg: float = BEAM_DAMAGE[stage - 1]
	for a in game.actors.duplicate():
		if a == player or a.removed or a.dead or not a.shootable:
			continue
		var wx: float = a.x - from.x
		var wy: float = a.y - from.y
		var s := wx * ux + wy * uy
		if s < 0.0 or s > reach:
			continue
		var px := wx - ux * s
		var py := wy - uy * s
		var rr: float = r + float(a.radius if a.radius > 0.0 else 16.0)
		if px * px + py * py > rr * rr:
			continue
		# and at the height the column is at over them
		var bz := from.z + slope * s
		var lo: float = a.z
		var hi: float = a.z + float(a.height if a.height > 0.0 else 56.0)
		if bz + r < lo or bz - r > hi:
			continue
		var was: bool = a.dead
		a.damage(dmg, player, {"fire": true})
		if a.has_method("ignite") and not a.removed:
			a.ignite(600)
		if not was and a.dead:
			killed += 1

## The dust and the fire coming off it: SAMPLES points a tic, offset by a
## fraction that walks, scattered across the column (a stem of fire on
## the axis is a line; thrown anywhere inside the radius it is a column,
## which is the word the user used). The FAR ones are the big ones: near
## the muzzle they are small and pale, the column's own glare; a hundred
## metres out they are enormous, the town going up.
func _dress(r: float) -> void:
	var fx = game.fx
	if fx == null:
		return
	var ux := cos(angle)
	var uy := sin(angle)
	var n := SAMPLES
	var step := reach / n
	var jitter := fmod(tics * 0.37, 1.0)
	for i in n:
		var s := (i + jitter) * step
		var bz := from.z + slope * s
		if bz > 700.0 + r:
			continue
		var th := randf() * TAU
		var rr := sqrt(randf()) * r
		var x := from.x + ux * s - uy * cos(th) * rr
		var y := from.y + uy * s + ux * cos(th) * rr
		var z := maxf(0.0, bz + sin(th) * rr)
		var near := 1.0 - float(i) / n
		var far := float(i) / n
		if i == 0 or randf() < 0.55 + near * 0.45:
			fx.fireball(x, y, z, r * (0.42 + far * 1.25), 14 + (i & 7))
		if i > 0 and randf() < 0.8:
			fx.puff(x, y, maxf(0.0, z - r * 0.4), r * (0.55 + far * 1.4), 90 + (i & 31))
		# embers thrown out of the column sideways
		if randf() < 0.5:
			fx.ember(x, y, z, 1, 1.0)
	# AND A BOIL WHERE IT LANDS, every tic it is out: off the surface
	# along its own normal, so a hit on a wall throws toward the gun and
	# one on the floor throws up
	if not hit.is_empty():
		var h: Vector3 = hit.at + hit.n * (r * 0.5)
		if (tics & 1) == 0:
			fx.fireball(h.x, h.y, h.z, r * (1.3 + randf() * 1.2), 12 + (tics & 7))
		_sparks(h, 3)
		if randf() < 0.6:
			fx.ember(h.x, h.y, h.z, 2, 1.2)
		if (tics & 3) == 0:
			fx.puff(h.x, h.y, h.z, r * 1.6, 70)
	# and sparks at the metal, every tic, so the muzzle is always the
	# brightest thing in the picture, with a small hard bloom
	_sparks(from, 4)
	if (tics & 1) == 0:
		fx.fireball(from.x, from.y, from.z, r * 0.55, 9)

## What comes out of a hard hit: bright, brief, and it falls (Game.
## spawnSparks in the JS, here on the effects' ember pool).
func _sparks(at: Vector3, n: int) -> void:
	var fx = game.fx
	if fx == null or fx.get("embers") == null:
		return
	for i in n:
		var a := randf() * TAU
		var sp := 0.8 + randf() * 4.2
		fx.embers.spawn({
			"x": at.x, "y": at.y, "z": at.z,
			"vx": cos(a) * sp, "vy": sin(a) * sp, "vz": 1.0 + randf() * 2.0,
			"life": 16 + (randi() & 15), "size0": 2.4, "size1": 1.0,
			"c0": Color(1.0, 0.97, 0.8), "c1": Color(1.0, 0.55, 0.15),
			"drag": 0.97, "gravity": -0.32,
		})

# ------------------------------------------------------------------
# The light, once a frame off the wall clock: the fade after the
# column has gone, and the shake with it, are things the EYE does
# ------------------------------------------------------------------

func tic_light(dt: float) -> void:
	if not live:
		glow = maxf(0.0, glow - dt / AFTERGLOW)
		shake = maxf(0.0, shake - dt * 2.6)
	var g := glow
	var peak: float = LIGHT_PEAK[glow_stage - 1] if glow_stage >= 1 else 1.0
	RenderingServer.global_shader_parameter_set("beam_level", g * g * peak)
	if g > 0.0:
		# game coordinates into the renderer's, the one conversion
		# everything in this game does at its own edge
		RenderingServer.global_shader_parameter_set("beam_pos", U.v3(lit_from.x, lit_from.y, lit_from.z))
		RenderingServer.global_shader_parameter_set("beam_dir", U.v3(lit_dir.x, lit_dir.y, lit_dir.z))
		RenderingServer.global_shader_parameter_set("beam_len", lit_len)
		RenderingServer.global_shader_parameter_set("beam_range", LIGHT_RANGE[glow_stage - 1] if glow_stage >= 1 else 400.0)
		# the clock the flicker rides: fast while the beam is out, slowing
		# as the afterglow dies, so the light settles rather than strobes
		_seed = fmod(_seed + dt * (4.0 + 14.0 * g), 6283.0)
		RenderingServer.global_shader_parameter_set("beam_seed", _seed)

## Once a frame: the light, and the column rebuilt round its axis.
## `time` is seconds, for the pulse and the rings.
func draw(time: float, dt: float) -> void:
	tic_light(dt)
	render(time)

# ------------------------------------------------------------------
# The picture
# ------------------------------------------------------------------

## The shells, the rings and the caps once: the index buffer and the
## per-vertex colours never change, because which shell a vertex belongs
## to never does. Positions are rewritten every frame.
func _build() -> void:
	var bands := SHELLS.size() * (SEGS + 1) + RINGS * 2
	var verts := bands * (SIDES + 1) + CAPS
	_pos.resize(verts)
	_nrm.resize(verts)
	_col.resize(verts)
	_uv.resize(verts)
	var v := 0
	for sh in SHELLS:
		for i in SEGS + 1:
			for k in SIDES + 1:
				_col[v] = sh.colour
				_uv[v] = Vector2(sh.rim, 0.0)
				v += 1
	# the shock rings, white and lit at their edge
	for i in RINGS * 2:
		for k in SIDES + 1:
			_col[v] = Color(1, 1, 0.92)
			_uv[v] = Vector2(1.0, 0.0)
			v += 1
	# the cap centres, in their own shell's colour and lit flat
	var cap_base := v
	for c in CAPS:
		_col[v] = SHELLS[c].colour
		_uv[v] = Vector2(0.0, 0.0)
		v += 1
	# every band joined to the next in its own run; a run never joins
	# across a shell boundary
	var base := 0
	for sh in SHELLS.size():
		for i in SEGS:
			for k in SIDES:
				_quad(base + i * (SIDES + 1) + k, base + (i + 1) * (SIDES + 1) + k)
		base += (SEGS + 1) * (SIDES + 1)
	for i in RINGS:
		for k in SIDES:
			_quad(base + k, base + (SIDES + 1) + k)
		base += 2 * (SIDES + 1)
	# the caps: a fan from each centre to the CAP_SEG ring of its shell
	for c in CAPS:
		var ring := c * (SEGS + 1) * (SIDES + 1) + CAP_SEG * (SIDES + 1)
		for k in SIDES:
			_indices.append_array([cap_base + c, ring + k, ring + k + 1])
	_mesh = ArrayMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.name = "BeamColumn"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	_mi.visible = false
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/beam.gdshader")
	_mi.material_override = mat
	add_child(_mi)

func _quad(a: int, b: int) -> void:
	_indices.append_array([a, b, b + 1, a, b + 1, a + 1])

## Rebuild the column around the axis it is on this frame.
func render(time := 0.0) -> void:
	if not live or stage < 1:
		_mi.visible = false
		return
	var R := radius()
	var neck_len := maxf(NECK, R * NECK_R)
	var hide_len := maxf(HIDE, R * HIDE_R)
	var len := length()
	# the axis, in map space, and two perpendiculars to sweep the rings
	var d := dir()
	var ax := Vector3(0, 0, 1)
	if absf(d.z) > 0.9:
		ax = Vector3(1, 0, 0)
	var e1 := d.cross(ax).normalized()
	var e2 := d.cross(e1)
	# THE LAST FEW TICS DIE BACK rather than blinking out, and the first
	# two come up from nothing, so the column has a shape in time
	var a := age()
	var life := minf(1.0, tics / 2.0) * ((1.0 - (a - 0.86) / 0.14) if a > 0.86 else 1.0)
	var v := 0
	var ends_on_wall := not hit.is_empty()
	for sh in SHELLS:
		for i in SEGS + 1:
			var t := float(i) / SEGS
			var s := t * len
			# the profile: a neck opening out over NECK units of real
			# distance, a slow pulse along the length, and a taper at the
			# far end only when it ends in the air (a column that lands on
			# a wall goes into it at full width, and the boil hides it)
			var neck := 0.05 + 0.95 * minf(1.0, s / neck_len)
			var pulse := 1.0 + 0.12 * sin(t * 26.0 - time * 9.0)
			var tail := 1.0 if ends_on_wall else 1.0 - 0.55 * maxf(0.0, (t - 0.9) / 0.1)
			var rad: float = R * sh.r * neck * pulse * tail
			# nothing at all within HIDE of the muzzle: what is there is
			# the bloom, which is particles
			var near := clampf((s - hide_len * 0.25) / hide_len, 0.0, 1.0)
			var fd: float = life * sh.w * near
			var c := from + d * s
			for k in SIDES + 1:
				var th := float(k) / SIDES * TAU
				var nn := e1 * cos(th) + e2 * sin(th)
				v = _put(v, c + nn * rad, nn, fd)
	# the shock rings, travelling out of the muzzle and widening as they
	# go, each on its own phase so they are a stream and not a pulse —
	# and DIM: a moving thing is read at a fraction of a still one
	for i in RINGS:
		var trav := fmod(time * RING_SPEED + float(i) / RINGS, 1.0)
		var s := trav * len
		var rad := R * (1.25 + trav * 1.7) * (0.06 + 0.94 * minf(1.0, s / neck_len))
		var wide := R * 0.055
		var fd := life * (1.0 - trav) * 0.26 * clampf((s - hide_len * 0.25) / hide_len, 0.0, 1.0)
		for off in [-wide, wide]:
			var c: Vector3 = from + d * (s + off)
			for k in SIDES + 1:
				var th := float(k) / SIDES * TAU
				var nn := e1 * cos(th) + e2 * sin(th)
				v = _put(v, c + nn * rad, nn, fd)
	# and the cap centres, on the axis at CAP_SEG, facing back down the
	# beam at whoever fired it
	for c in CAPS:
		var s := float(CAP_SEG) / SEGS * len
		var fd: float = life * SHELLS[c].w * clampf((s - hide_len * 0.25) / hide_len, 0.0, 1.0)
		v = _put(v, from + d * s, -d, fd)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _pos
	arrays[Mesh.ARRAY_NORMAL] = _nrm
	arrays[Mesh.ARRAY_COLOR] = _col
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mi.visible = true

## one vertex, map space into Godot's at the edge
func _put(v: int, p: Vector3, n: Vector3, fade: float) -> int:
	_pos[v] = U.v3(p.x, p.y, p.z)
	_nrm[v] = U.v3(n.x, n.y, n.z)
	_uv[v] = Vector2(_uv[v].x, fade)
	return v + 1
