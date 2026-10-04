## MEWD — THE DROP (at the user's request: "have the player drop in from
## orbit with this pod, third person, RCS thrusters thrusting and
## animating in the correct directions to control orientation, the retros
## pointed down to slow descent, and on landing switch to first person,
## the door blows off and they play the map"; and "retros auto-fire to
## achieve a survivable landing for now; retros can be used to slow
## descent for manoeuvring until then").
##
## THE POD is assets/models/drop_pod.glb as the user drew it: a hull
## 7.8 m across and 7.2 m tall on a flat heat shield, a door on one side,
## and twenty little green marker spheres named dropPodThrustPoints*,
## which are read for where the nozzles are and then freed (they are for
## reference, not for the game — the user's words). Which way each nozzle
## points the model does not say; the hull round each one does, and that
## reading is `_nozzle_dir`:
##   8 SKIRT nozzles (2.1 m up, four pairs at the diagonals, standing out
##     past the hull): down and outward at 37 degrees — THE RETROS. All
##     eight together brake the fall along the pod's own axis; a tilted
##     pod braking drifts sideways, which is how it is steered.
##   8 SHOULDER nozzles (5.5 m up, four corner pairs): each pair a corner
##     block with one nozzle facing each adjacent cardinal direction —
##     the RCS. Pitch and roll.
##   4 TOP nozzles (6.1 m up, at the cardinal points): outward and up —
##     RCS too, the other half of a pitch or roll couple.
## A nozzle's thrust is along the opposite of the way it points, at the
## place it is, so it turns the pod as well as pushing it; the RCS
## controller picks, for the turn it wants, the nozzles whose turning
## effect is that way (`_rcs`), so what fires is what would fire.
##
## THE RIDE: the pod starts DROP.height metres over the start, falling,
## with a drift. Gravity, air drag (terminal speed about 70 m/s), and a
## capsule's own stability (base first, gently). The move keys tilt the
## pod — the RCS brings its rate to what is asked and kills it again —
## and with nothing asked the RCS levels it; the look turns the eye round
## it; FIRE lights the retros. THE AUTOPILOT lights them itself when the
## fall would not stop before the ground (a suicide burn: as late as it
## can and still land under DROP.land_speed), levels the pod for the last
## stretch, and brings it in. Over the cloud sea with nothing under it, it
## tilts toward the start and burns, so the pod comes down on land.
##
## THE LANDING: a thud, dust, the pod settling upright; a moment; then the
## eye is INSIDE (the model has an inside), first person, the door still
## shut; then the door blows off — thrown tumbling by a charge, a flash —
## and the map is yours, the pod left standing where it came down with a
## ring of invisible solid blockers round its wall (PODWALL actors) and a
## gap where the door was. The sim runs in metres in the renderer's axes
## (x, y up, z) and talks to the map in its units (IslandLevel.U_PER_M).
class_name DropPod
extends Node3D

const MODEL := "res://assets/models/drop_pod.glb"
const DROP := {
	"height": 1400.0,       # m over the start it begins (forty seconds down)
	"offset": 180.0,        # m to the side of the start
	"drift": 12.0,          # m/s sideways to begin with
	"g": 9.8,
	"drag": 0.0020,         # a = -drag * v|v|: terminal about 70 m/s
	"retro": 5.2,           # m/s^2 a skirt nozzle gives: canted 37 degrees out, all
	                        # eight lift 8 * 5.2 * 0.61 = 25 m/s^2, 15 net of gravity
	"retro_lift": 0.61,     # the share of a skirt nozzle's push that is upward
	"rcs": 1.2,             # m/s^2 a shoulder or top nozzle gives
	"inertia": 6.0,         # m^2: angular acceleration = torque / mass / this
	"rate": 0.9,            # rad/s the RCS turns at when asked
	"righting": 0.35,       # rad/s^2 a tilted pod wants to level, per radian, at speed
	"ang_damp": 0.985,      # of the spin kept a tic
	"land_speed": 4.0,      # m/s at most on touchdown
	"final_below": 45.0,    # m: under this the autopilot flies the fall rate down
	"auto_level_below": 160.0,  # m: the autopilot levels the pod under this
	"settle_tics": 25,
	"hold_tics": 40,        # third person after touchdown
	"door_tics": 28,        # first person, door shut, before it blows
}
## the pod's radius (m) and where the door is, for the blockers
const HULL_R := 3.9
const DOOR_GAP := 0.6  # radians either side of the door left open
const BLOCKERS := 12

## the pod's frame: base at the origin, up +y
var game
var model: Node3D
var hull: MeshInstance3D
var door: MeshInstance3D
var door_home: Transform3D
## the hull node's place in the file, taken off the model so the pod's
## frame (base at the origin, up +y) is this node's
var shift := Vector3.ZERO
## nozzles: position (m, the pod's frame), the way its exhaust goes, kind
var nozzles: Array = []    # [{pos, dir, kind: "retro"|"rcs"}]
var flames: MultiMeshInstance3D
var fired := PackedFloat32Array()   # how hard each nozzle fired this tic (0..1)
var fires := 0                       # nozzle firings, counted, for the tests

## the sim, in metres in the renderer's axes (`att`: the pod's attitude,
## its frame's axes in the world)
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var att := Basis.IDENTITY
var ang := Vector3.ZERO           # angular velocity, world, rad/s
var prev_pos := Vector3.ZERO
var prev_att := Basis.IDENTITY
## the phase: "drop", "landed" (third person hold), "inside" (first
## person, door shut), "out" (door blown: play), "" (not begun)
var phase := ""
var phase_tics := 0
var active := false
var retro_on := false
var auto_burn := false
var retro_level := 0.0
## the autopilot's burn, once lit: "" none, "burn" the suicide burn at
## full, "final" the fall rate flown down to the ground
var auto_mode := ""
var landed_at := 0
var door_vel := Vector3.ZERO
var door_spin := Vector3.ZERO
var door_pos := Vector3.ZERO
var door_basis := Basis.IDENTITY
var door_down := false
var start := Vector2.ZERO   # the start, map units
var blockers: Array = []
var door_block = null
var ticks := 0
var touchdown_speed := 0.0

func _init(g) -> void:
	game = g

func _ready() -> void:
	model = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	# the file's parts, told apart by size: the hull is the big one, the
	# markers are tiny, the door is what is left
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		var sz: float = mi.get_aabb().size.length()
		if hull == null or sz > hull.get_aabb().size.length():
			hull = mi
	# the hull's own node transform is the pod's frame: everything taken
	# relative to it, and the model moved so the frame is this node's
	var hull_t := _tree_transform(hull)
	shift = hull_t.origin
	model.position = -shift
	for mi: MeshInstance3D in meshes:
		if mi == hull:
			continue
		var t := _tree_transform(mi)
		var box := mi.get_aabb()
		if box.size.length() < 0.5:
			var c: Vector3 = t * box.get_center() - shift
			nozzles.append({"pos": c, "dir": _nozzle_dir(c), "kind": "retro" if c.y < 3.5 else "rcs"})
			mi.queue_free()
		else:
			door = mi
	# (the importer made collision bodies of the -col names: not wanted)
	for b in model.find_children("*", "StaticBody3D", true, false):
		b.queue_free()
	door_home = door.transform
	fired.resize(nozzles.size())
	fired.fill(0.0)
	_make_flames()
	# the model is metres; this node lives in the game's units
	scale = Vector3.ONE * IslandLevel.U_PER_M

func _tree_transform(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != model:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

## Which way a nozzle at `c` (the pod's frame) sends its exhaust — the
## hull's own facing there, read off the model: see the header.
static func _nozzle_dir(c: Vector3) -> Vector3:
	var radial := Vector3(c.x, 0.0, c.z).normalized()
	if c.y < 3.5:
		# the skirt: down and out at 37 degrees
		return (radial * 0.79 + Vector3(0, -0.61, 0)).normalized()
	if c.y > 5.8:
		# the top ring: out and up
		return (radial * 0.84 + Vector3(0, 0.54, 0)).normalized()
	# a shoulder pair: the nozzle nearer the x axis faces along x, the
	# other along z, a little upward
	var d := Vector3(signf(c.x), 0.0, 0.0) if absf(c.x) > absf(c.z) else Vector3(0.0, 0.0, signf(c.z))
	return (d + Vector3(0, 0.3, 0)).normalized()

func _make_flames() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.22
	cone.height = 1.0
	cone.radial_segments = 8
	cone.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.55, 0.18)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.25)
	m.emission_energy_multiplier = 2.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone
	mm.instance_count = nozzles.size()
	mm.visible_instance_count = nozzles.size()
	flames = MultiMeshInstance3D.new()
	flames.multimesh = mm
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	_draw_flames()

# ------------------------------------------------------------------
# THE RIDE
# ------------------------------------------------------------------

## Begun over the start (map units): the pod high up, drifting.
func begin(sx: float, sy: float) -> void:
	start = Vector2(sx, sy)
	var ang_off := randf() * TAU
	var gz: float = game.level.floor_at(sx, sy) / IslandLevel.U_PER_M
	pos = Vector3(sx / IslandLevel.U_PER_M + cos(ang_off) * DROP.offset, gz + DROP.height, -sy / IslandLevel.U_PER_M + sin(ang_off) * DROP.offset)
	vel = Vector3(-cos(ang_off), 0.0, -sin(ang_off)) * DROP.drift
	att = Basis(Vector3(1, 0, 0), 0.12).rotated(Vector3(0, 0, 1), -0.08)
	ang = Vector3(0.02, 0.0, -0.03)
	prev_pos = pos
	prev_att = att
	phase = "drop"
	phase_tics = 0
	active = true
	visible = true
	_sync_player()
	BlackBox.mark("drop begins")

func third_person() -> bool:
	return phase == "drop" or phase == "landed"

## you cannot walk until the door is off
func holds_player() -> bool:
	return active and phase != "out"

## the map's ground under the pod, metres (or NO_FLOOR)
func _ground() -> float:
	var f: float = game.level.floor_at(pos.x * IslandLevel.U_PER_M, -pos.z * IslandLevel.U_PER_M)
	return f / IslandLevel.U_PER_M if f > IslandLevel.NO_FLOOR else IslandLevel.NO_FLOOR

func altitude() -> float:
	var g := _ground()
	return pos.y - g if g > IslandLevel.NO_FLOOR else pos.y

## how far from upright, radians
func tilt() -> float:
	return acos(clampf(att.y.y, -1.0, 1.0))

## One tic of the ride, with this machine's hands (Game.local_cmd).
func tic(cmd: Dictionary) -> void:
	ticks += 1
	phase_tics += 1
	prev_pos = pos
	prev_att = att
	fired.fill(0.0)
	match phase:
		"drop":
			_fly(cmd)
		"landed":
			_settle()
			if phase_tics >= DROP.hold_tics:
				phase = "inside"
				phase_tics = 0
				BlackBox.mark("drop: inside the pod")
		"inside":
			if phase_tics >= DROP.door_tics:
				_blow_door()
		"out":
			_door_tic()
	_sync_player()

func _fly(cmd: Dictionary) -> void:
	var dt := 1.0 / U.TICRATE
	var up := att.y
	var h := altitude()
	var ground := _ground()
	var over_land := ground > IslandLevel.NO_FLOOR
	# ---- what is asked: a tilt, from the eye's point of view ----------
	var a: float = game.player.angle
	var fwd := Vector3(cos(a), 0.0, -sin(a))
	var right := Vector3(sin(a), 0.0, cos(a))
	var want_tilt := fwd * float(cmd.get("fwd", 0.0)) + right * float(cmd.get("side", 0.0))
	retro_on = bool(cmd.get("attack", false)) or bool(cmd.get("jump", false))
	# ---- the autopilot ------------------------------------------------
	# the suicide burn: lit, at full, when the fall would not stop before
	# the ground; then, low and slow, the fall rate flown down to the
	# ground — slower the nearer, a metre a second at the last
	auto_burn = false
	var vz := vel.y
	var lift := DROP.retro * 8.0 * DROP.retro_lift * maxf(up.y, 0.3)
	var brake := lift - DROP.g
	var final_level := -1.0
	if auto_mode == "" and vz < 0.0 and brake > 0.0:
		var stop := vz * vz / (2.0 * brake)
		if h <= stop + 6.0 + absf(vz) * 0.15:
			auto_mode = "burn"
	if auto_mode == "burn" and (h < DROP.final_below or vz > -10.0):
		auto_mode = "final"
	if auto_mode == "" and h < DROP.final_below and vz < -DROP.land_speed:
		auto_mode = "final"
	if auto_mode == "burn":
		auto_burn = true
	elif auto_mode == "final":
		auto_burn = true
		var want_vz := -clampf(h * 0.3, 1.0, DROP.land_speed)
		var hover := DROP.g / maxf(lift, 1.0)
		final_level = clampf(hover + (want_vz - vz) * 0.3, 0.0, 1.0)
	if h < DROP.auto_level_below:
		# level, whatever is asked, and come down on land
		want_tilt = Vector3.ZERO
		if not over_land:
			var to_start := Vector3(start.x / IslandLevel.U_PER_M - pos.x, 0.0, -start.y / IslandLevel.U_PER_M - pos.z)
			want_tilt = to_start.normalized() * 0.6
			auto_burn = true
	var burn := retro_on or auto_burn
	# (a hand on the retros low down is still the autopilot's call)
	if auto_mode == "final" and retro_on:
		final_level = 1.0 if h > 8.0 else final_level
	# ---- the RCS: a rate for the tilt asked, nothing when nothing is ---
	var want_ang := Vector3.ZERO
	if want_tilt.length_squared() > 1e-4:
		var axis := Vector3.UP.cross(want_tilt.normalized())
		want_ang = axis * DROP.rate * minf(1.0, want_tilt.length())
		# (never past 50 degrees over)
		if tilt() > 0.87 and axis.dot(up.cross(Vector3.UP)) < 0.0:
			want_ang = Vector3.ZERO
	else:
		# level it: turn the up vector back to up
		var level_axis := up.cross(Vector3.UP)
		want_ang = level_axis * 0.8 * (1.0 if h < DROP.auto_level_below else 0.5)
	_acc_tmp = Vector3.ZERO
	_alpha_tmp = Vector3.ZERO
	_rcs(want_ang - ang)
	var acc := _acc_tmp
	var alpha := _alpha_tmp
	# ---- the retros ---------------------------------------------------
	if final_level >= 0.0:
		retro_level += (final_level - retro_level) * 0.5
	elif burn:
		retro_level = minf(1.0, retro_level + 0.25)
	else:
		retro_level = maxf(0.0, retro_level - 0.2)
	if retro_level > 0.0:
		for i in nozzles.size():
			var n: Dictionary = nozzles[i]
			if n.kind != "retro":
				continue
			fired[i] = maxf(fired[i], retro_level)
			fires += 1
			var f: Vector3 = att * (-n.dir) * DROP.retro * retro_level
			acc += f
			# (their turning cancels in pairs; a little stays, which is right)
			alpha += (att * n.pos - att * Vector3(0, 2.5, 0)).cross(f) / DROP.inertia * 0.15
	# ---- the air, the ground's pull, a capsule's stability ------------
	acc += Vector3(0, -DROP.g, 0)
	acc -= vel * vel.length() * DROP.drag
	var speed := vel.length()
	var right_axis := up.cross(Vector3.UP)
	alpha += right_axis * DROP.righting * clampf(speed / 40.0, 0.0, 1.5)
	# ---- integrate ----------------------------------------------------
	vel += acc * dt
	pos += vel * dt
	ang += alpha * dt
	ang *= DROP.ang_damp
	var w := ang.length()
	if w > 1e-6:
		att = Basis(ang / w, w * dt) * att
		att = att.orthonormalized()
	# ---- the dust under a burn near the ground, and the touchdown -----
	if over_land and burn and h < 28.0 and ticks % 2 == 0:
		var gx := pos.x * IslandLevel.U_PER_M + randf_range(-70.0, 70.0)
		var gy := -pos.z * IslandLevel.U_PER_M + randf_range(-70.0, 70.0)
		game.fx.puff(gx, gy, ground * IslandLevel.U_PER_M + 6.0, 70.0, 60)
	if over_land and pos.y <= ground:
		_touchdown(ground)

var _acc_tmp := Vector3.ZERO
var _alpha_tmp := Vector3.ZERO
## THE RCS: for a wanted change of spin (world, rad/s), fire the nozzles
## whose turning is that way, as hard as the want is. Their push and turn
## are added to _acc_tmp and _alpha_tmp.
func _rcs(want: Vector3) -> void:
	var need := want.length()
	if need < 0.02:
		return
	var level := clampf(need / 0.6, 0.15, 1.0)
	var wdir := want / need
	var centre := att * Vector3(0, 3.0, 0)
	for i in nozzles.size():
		var n: Dictionary = nozzles[i]
		if n.kind != "rcs":
			continue
		var f: Vector3 = att * (-n.dir) * DROP.rcs
		var r: Vector3 = att * n.pos - centre
		var torque := r.cross(f)
		var tl := torque.length()
		if tl < 1e-4 or torque.dot(wdir) < 0.45 * tl:
			continue
		fired[i] = maxf(fired[i], level)
		fires += 1
		_acc_tmp += f * level
		_alpha_tmp += torque * level / DROP.inertia

func _touchdown(ground: float) -> void:
	touchdown_speed = vel.length()
	pos.y = ground
	vel = Vector3.ZERO
	ang = Vector3.ZERO
	retro_level = 0.0
	auto_burn = false
	retro_on = false
	phase = "landed"
	phase_tics = 0
	landed_at = ticks
	var gx := pos.x * IslandLevel.U_PER_M
	var gy := -pos.z * IslandLevel.U_PER_M
	game.play_sound("explode", null)
	for k in 14:
		game.fx.puff(gx + randf_range(-110.0, 110.0), gy + randf_range(-110.0, 110.0), ground * IslandLevel.U_PER_M + 8.0, 90.0, 90)
	# the scorch is a RING round the hull, not under it: a mark laid at the
	# middle would paint the pod's own floor (a projected decal takes any
	# surface in its box)
	if game.decals != null:
		for k in 6:
			var a := k * TAU / 6.0 + 0.3
			var r := (HULL_R + 2.3) * IslandLevel.U_PER_M
			var sx := gx + cos(a) * r
			var sy := gy + sin(a) * r
			var sf: float = game.level.floor_at(sx, sy)
			if sf > IslandLevel.NO_FLOOR:
				game.decals.blast(Vector3(sx, sy, sf), Vector3(0, 0, 1), 130.0)
	if game.veg_damage != null:
		game.veg_damage.blast(Vector3(gx, gy, ground * IslandLevel.U_PER_M + 20.0), 300.0)
	_place_blockers()
	# and the doorway shut too, until the door is off (nobody walks in)
	var dd := door_dir()
	door_block = game.spawn("PODWALL", gx + dd.x * (HULL_R - 0.6) * IslandLevel.U_PER_M, gy - dd.z * (HULL_R - 0.6) * IslandLevel.U_PER_M, 0.0)
	BlackBox.mark("drop: landed at %.1f m/s, %.0f degrees over" % [touchdown_speed, rad_to_deg(tilt())])

## the pod settling upright over its first tics down
func _settle() -> void:
	var k := minf(1.0, float(phase_tics) / DROP.settle_tics)
	if k < 1.0:
		var want := Basis(Vector3.UP, _yaw())
		att = att.slerp(want, 0.15).orthonormalized()
	else:
		att = Basis(Vector3.UP, _yaw())

## the pod's turn about the vertical
func _yaw() -> float:
	var f := att.z
	return atan2(f.x, f.z)

## the door's way out, in the pod's frame (-z) and the map's angle
func door_dir() -> Vector3:
	return att * Vector3(0, 0, -1)

func door_angle() -> float:
	var d := door_dir()
	return atan2(-d.z, d.x)

## A RING OF INVISIBLE SOLIDS round the hull, the doorway left open.
func _place_blockers() -> void:
	var gx := pos.x * IslandLevel.U_PER_M
	var gy := -pos.z * IslandLevel.U_PER_M
	var da := door_angle()
	for k in BLOCKERS:
		var a := k * TAU / BLOCKERS
		if absf(U.angle_norm(a - da)) < DOOR_GAP:
			continue
		var r := (HULL_R - 0.4) * IslandLevel.U_PER_M
		var b = game.spawn("PODWALL", gx + cos(a) * r, gy + sin(a) * r, 0.0)
		blockers.append(b)

## THE DOOR BLOWS OFF: thrown out the way it faces, tumbling, a flash.
func _blow_door() -> void:
	phase = "out"
	phase_tics = 0
	door_down = false
	var out := door_dir()
	door_pos = pos + att * door_home.origin
	door_basis = att * door_home.basis
	door_vel = out * 13.0 + Vector3(0, 4.5, 0)
	if door_block != null:
		door_block.remove()
		door_block = null
	door_spin = (att * Vector3(1, 0, 0)) * 5.0 + Vector3(0, 1.5, 0)
	var at := door_pos * IslandLevel.U_PER_M
	var gx := at.x
	var gy := -at.z
	game.fx.fireball(gx, gy, at.y, 110.0, 24)
	for k in 6:
		game.fx.puff(gx + randf_range(-40, 40), gy + randf_range(-40, 40), at.y + randf_range(-30, 30), 50.0, 70)
	game.play_sound("explode", null)
	BlackBox.mark("drop: door blown")

func _door_tic() -> void:
	if door_down:
		return
	var dt := 1.0 / U.TICRATE
	door_vel += Vector3(0, -DROP.g, 0) * dt
	door_pos += door_vel * dt
	var w := door_spin.length()
	if w > 1e-6:
		door_basis = Basis(door_spin / w, w * dt) * door_basis
	var f: float = game.level.floor_at(door_pos.x * IslandLevel.U_PER_M, -door_pos.z * IslandLevel.U_PER_M)
	var g: float = f / IslandLevel.U_PER_M if f > IslandLevel.NO_FLOOR else pos.y - 30.0
	if door_pos.y <= g + 0.3:
		door_pos.y = g + 0.3
		door_down = true
		# flat on the ground, face up, the way it was going
		var fl := door_vel
		fl.y = 0.0
		door_basis = Basis.looking_at(fl.normalized() if fl.length() > 0.1 else Vector3(0, 0, -1), Vector3.UP) * Basis(Vector3(1, 0, 0), -PI / 2.0)

## THE PLAYER RIDES INSIDE: where the pod is, the map's units, standing
## on its floor; the eye is placed by place_camera while it is third
## person, and by the player's own rules once inside.
func _sync_player() -> void:
	var p = game.player
	var gx := pos.x * IslandLevel.U_PER_M
	var gy := -pos.z * IslandLevel.U_PER_M
	p.prev = Vector4(p.x, p.y, p.view_z, 0)
	p.x = gx
	p.y = gy
	p.z = pos.y * IslandLevel.U_PER_M
	p.view_z = p.z + U.PLAYER_EYE
	p.momx = 0.0
	p.momy = 0.0
	p.momz = 0.0
	p.on_ground = phase != "drop"
	p.sector = game.level.sector_at(gx, gy)
	if phase == "inside" and phase_tics == 1:
		# the eye turned to the door, level, for the blow
		p.angle = door_angle()
		p.pitch = 0.0
		p.prev = Vector4(p.x, p.y, p.view_z, 0)

# ------------------------------------------------------------------
# THE PICTURE
# ------------------------------------------------------------------

## Every frame: the pod (and its door) where the sim has it, slid `f`
## of the way from the tic before.
func draw(f: float) -> void:
	if not active:
		return
	var p := prev_pos.lerp(pos, f)
	var b := prev_att.slerp(att, f).orthonormalized()
	transform = Transform3D(b.scaled(Vector3.ONE * IslandLevel.U_PER_M), p * IslandLevel.U_PER_M)
	if phase == "out":
		# the door on its own, in the world (metres): back into the pod's
		# frame, which the door's node is a child of (under the model's shift)
		var inv := b.inverse()
		door.transform = Transform3D(inv * door_basis, inv * (door_pos - p) + shift)
	_draw_flames()

func _draw_flames() -> void:
	if flames == null:
		return
	var mm := flames.multimesh
	for i in nozzles.size():
		var n: Dictionary = nozzles[i]
		var lv: float = fired[i]
		if lv <= 0.01 or not active:
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var length: float = (3.2 if n.kind == "retro" else 1.3) * lv * randf_range(0.85, 1.15)
		var width: float = (1.6 if n.kind == "retro" else 0.9) * (0.6 + 0.4 * lv)
		var d: Vector3 = n.dir
		var look := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
		# the cone's +y (its apex) turned to -d: apex at the nozzle, base out
		var bz := look * Basis(Vector3.RIGHT, PI / 2.0)
		bz = Basis(bz.x * width, bz.y * length, bz.z * width)
		mm.set_instance_transform(i, Transform3D(bz, n.pos + d * length * 0.5))

## THE EYE BEHIND THE POD, third person: round it by the player's angle,
## up by their pitch, 24 m off, looking at its middle.
func place_camera(cam: Camera3D, f: float) -> void:
	var p: Player = game.player
	var centre := prev_pos.lerp(pos, f) + Vector3(0, 3.5, 0)
	var e := clampf(0.3 - p.pitch, -0.15, 1.2)
	var a: float = p.angle
	var back := Vector3(-cos(a), 0.0, sin(a))
	var eye := centre + (back * cos(e) + Vector3(0, sin(e), 0)) * 24.0
	# never under the ground
	var gf: float = game.level.floor_at(eye.x * IslandLevel.U_PER_M, -eye.z * IslandLevel.U_PER_M)
	if gf > IslandLevel.NO_FLOOR:
		eye.y = maxf(eye.y, gf / IslandLevel.U_PER_M + 1.5)
	cam.position = eye * IslandLevel.U_PER_M
	# (look_at takes a global point; the eye's parent is the game, scaled)
	cam.look_at((cam.get_parent() as Node3D).to_global(centre * IslandLevel.U_PER_M), Vector3.UP)
	cam.fov = 62.0

## the readout's numbers: altitude (m), the fall (m/s), the tilt
func readout() -> Dictionary:
	return {"alt": altitude(), "fall": -vel.y, "tilt": rad_to_deg(tilt()), "retro": retro_level,
		"auto": auto_burn, "phase": phase, "speed": vel.length()}
