## MEWD — THE DROP (at the user's request: "have the player drop in from
## orbit with this pod, third person, RCS thrusters thrusting and
## animating in the correct directions to control orientation, the retros
## pointed down to slow descent, and on landing switch to first person,
## the door blows off and they play the map"; and "retros auto-fire to
## achieve a survivable landing for now; retros can be used to slow
## descent for manoeuvring until then"; then: "pod is too big, size it
## down", "player stuck in floor of pod on spawn", "descent needs to be
## 300% faster with reentry fireball until slowdown", "rcs thruster cones
## need to be reversed / blue shifted", "rcs thrusters retros and landing
## should destroy vegetation", "door popping off should destroy things and
## people it hits").
##
## THE POD is assets/models/drop_pod.glb as the user drew it, drawn at
## POD_SCALE (half) of the size it was made: a hull 3.9 m across and
## 3.6 m tall on a flat heat shield, the inside floor (THE DECK) 0.6 m up,
## a door on one side 1.8 m high, and twenty little green marker spheres
## named dropPodThrustPoints*, which are read for where the nozzles are and
## then freed (they are for reference, not for the game — the user's
## words). Which way each nozzle points the model does not say; the hull
## round each one does, and that reading is `_nozzle_dir`:
##   8 SKIRT nozzles (1.05 m up, four pairs at the diagonals, standing out
##     past the hull): down and outward at 37 degrees — THE RETROS. All
##     eight together brake the fall along the pod's own axis; a tilted
##     pod braking drifts sideways, which is how it is steered.
##   8 BULGE-TOP nozzles (2.75 m up, four pairs at the diagonals, each
##     pair on top of a retro bulge): straight up, a touch outward — the
##     RCS. One fires UP, its push is DOWN on that side of the pod, and
##     the pod tips that way: pitch and roll, with the top ring (at the
##     user's request: "they should rotate the craft or fire
##     complementarily to the direction of the main pitch thrusters at
##     the top, like the one above the door").
##   4 TOP nozzles (3.05 m up, at the cardinal points, one over the
##     door): outward and up — their push is in and down at the top, so
##     the top of the pod leans away from them. THE PITCH COUPLE: to tip
##     the pod toward the door, the top nozzle over the far side fires
##     and the bulge-top nozzles on the door's side fire — the same turn
##     from both ends.
## A nozzle's thrust is along the opposite of the way it points, at the
## place it is, so it turns the pod as well as pushing it; the RCS
## controller picks, for the turn it wants, the nozzles whose turning
## effect is that way (`_rcs`), so what fires is what would fire — the
## couple above falls out of it. Every jet is bright blue, a chain of
## shock diamonds out from the nozzle to a point (pod_flame).
##
## THE RIDE: the pod comes in DROP.height metres over the start already
## falling at DROP.entry (out of orbit), IN THE REENTRY FIRE: a
## white-hot cap round the heat shield and a tail of flame streaming back
## past the hull (reentry.gdshader), the shield itself glowing (pod_heat),
## an orange light on it, and fire, sparks and smoke left along the way it
## came. Gravity, air drag and a capsule's own stability (base first).
## STRAIGHT DOWN, FAST, UNCONTROLLED (at the user's request: "remove the
## RCS thrusters from the pod for now, have it drop straight down faster
## uncontrolled, have reentry burn last 75% of the descent, increase drop
## speed 250%"): the pod comes in right over the start, upright, with no
## drift, at DROP.entry (350 m/s), the air bringing it to a terminal of
## 80 m/s (DROP.drag) — 2.5 times the 140 and 32 the slow fall had. THE
## FIRE is the way down's, not the speed's: full over the first
## DROP.fire_share (75%) of the height, out over the next DROP.fire_fade.
## RCS_ON is false: no RCS nozzle fires, the stick and FIRE do nothing,
## and the autopilot's suicide burn on the retros is the only hand on it.
## What follows about the stick, the tank and the RCS is the ride with
## RCS_ON true (and the slow fall before this, "400% slower" and "twice
## as fast", is history: GODOT.txt).
## AND THE STICK HAS A TANK (at the user's request: "limited maneuvering
## fuel"): DROP.rcs_fuel nozzle-seconds of RCS, spent by every nozzle
## the STICK fires (`fuel`, on the readout); dry, the stick does
## nothing. The autopilot's levelling and the retros are not the
## tank's — a pod that could not stand itself up would be a crash.
## The move keys tilt the pod — the RCS brings its rate to what is asked
## and kills it again — and with nothing asked the RCS levels it; the look
## turns the eye round it; FIRE lights the retros. THE AUTOPILOT flies a
## SUICIDE BURN: it lights the retros when the braking it would take to be
## down to DROP.aim_speed a metre over the ground comes to DROP.plan of
## what they have, and holds that braking all the way down, so the pod
## comes in fast and stops at the last (about eleven seconds from the top,
## where it was forty); in the last seconds it takes the attitude, leaning
## against any drift while it burns and standing the pod up for the
## ground. Over the cloud sea with nothing under it, it leans toward the
## start and holds its height, so the pod comes down on land.
##
## THE EXHAUST AND THE PLANTS (VegDamage): low down, the retros' downwash
## shakes and shreds every plant whose top is in the spreading column
## under the skirt and, as it reaches the ground, the plants and grass in
## a ring round it; each firing RCS jet does the same to what it passes
## through; and where the pod comes down nothing is left growing through
## the hull, the plants round it blown flat as a blast would.
##
## THE LANDING: a thud, dust, the pod settling upright; THE DECK laid in
## the map (IslandLevel.add_deck) so the inside floor is a floor — you
## stand on it, not in the ground under it, and step down out of the door;
## a moment; then the eye is INSIDE, first person, the door still shut;
## then the door blows off — thrown tumbling by a charge, a flash — and
## anybody it hits on its way is blown apart, any lamp knocked to pieces,
## any plant shredded (`_door_hits`); and the map is yours, the pod left
## standing where it came down with a ring of invisible solid posts round
## its wall (PODWALL actors) and a gap the door's width where the door was.
## The sim runs in metres in the renderer's axes (x, y up, z) and talks to
## the map in its units (IslandLevel.U_PER_M).
class_name DropPod
extends Node3D

const MODEL := "res://assets/models/drop_pod.glb"
## how the capsule's paint is drawn: metal kept to this, roughness at least
## this, the colour lifted by this, its own picture glowing at this
const POD_LOOK := {"metallic": 0.3, "roughness": 0.6, "lift": 1.1, "glow": 0.22}
## the model drawn at this share of the size it was made
const POD_SCALE := 0.5
## THE RCS, OFF FOR NOW (at the user's request: "remove the RCS thrusters
## from the pod for now, have it drop straight down faster uncontrolled"):
## the nozzles are still read off the model, but none of them fires, the
## stick and FIRE do nothing, and the readout has no RCS line. True puts
## the steered ride back as it was.
const RCS_ON := false
const DROP := {
	"height": 1400.0,       # m over the start it comes in
	"entry": 350.0,         # m/s down it comes in at (2.5 times the 140 it was, at the
	                        # user's request: "increase drop speed 250%")
	"offset": 0.0,          # m to the side of the start: none, straight down on it
	"drift": 0.0,           # m/s sideways to begin with: none ("drop straight down")
	"g": 9.8,
	"drag": 0.00153,        # a = -drag * v|v|: terminal 80 m/s, 2.5 times the 32 the
	                        # slow fall had; the entry's 350 is down to it in seconds
	"retro": 6.0,           # m/s^2 a skirt nozzle gives: canted 37 degrees out, all
	                        # eight lift 8 * 6 * 0.61 = 29 m/s^2, two g net of gravity
	"retro_lift": 0.61,     # the share of a skirt nozzle's push that is upward
	"plan": 0.8,            # the share of the retros' braking the autopilot plans on:
	                        # the burn lit near 210 m from the 80 m/s terminal, and
	                        # all over in about five seconds
	"rcs": 1.2,             # m/s^2 a shoulder or top nozzle gives
	"rcs_fuel": 30.0,       # nozzle-seconds of RCS the stick has (a tilt is four
	                        # nozzles: seven or eight seconds of hard stick)
	"inertia": 3.0,         # m^2: angular acceleration = torque / mass / this (half
	                        # size, half the lever: the turns as quick as they were)
	"rate": 0.9,            # rad/s the RCS turns at when asked
	"righting": 0.35,       # rad/s^2 a tilted pod wants to level, per radian, at speed
	"ang_damp": 0.985,      # of the spin kept a tic
	"land_speed": 4.0,      # m/s at most on touchdown
	"aim_speed": 3.0,       # m/s the autopilot brings it down to
	"level_secs": 2.0,      # the autopilot has the attitude this long out at the fall's speed...
	"level_below": 50.0,    # ...or under this (m), whichever is higher: three seconds
	                        # of the slow fall, the stick live until then
	"fire_share": 0.75,     # of the way down the reentry fire lasts (at the user's
	                        # request: "reentry burn last 75% of the descent")
	"fire_fade": 0.05,      # of the way down it takes to go out, at the end of that
	"settle_tics": 25,
	"hold_tics": 40,        # third person after touchdown
	"door_tics": 28,        # first person, door shut, before it blows
}
## the pod at its size (m): the hull's radius, its height, the inside floor
## over the base (THE DECK), the inside wall's radius, the door's half-width
const HULL_R := 3.9 * POD_SCALE
const TALL := 7.2 * POD_SCALE
const DECK := 1.2 * POD_SCALE
const INNER_R := 3.4 * POD_SCALE
const DOOR_HALF := 1.47 * POD_SCALE
## the posts in the ring round the landed hull
const BLOCKERS := 24
## the door blown off: how hard it goes (m/s) and how near it hits (m)
const DOOR_SPEED := 14.0
const DOOR_HIT_R := 1.0

## the pod's frame: base at the origin, up +y
var game
var model: Node3D
var hull: MeshInstance3D
var door: MeshInstance3D
var door_home: Transform3D
## the hull node's place in the file (the model's own metres), taken off
## the model so the pod's frame (base at the origin, up +y) is this node's
var shift := Vector3.ZERO
## nozzles: position (m, the pod's frame), the way its exhaust goes, kind
var nozzles: Array = []    # [{pos, dir, kind: "retro"|"rcs"}]
var flames: MultiMeshInstance3D
var fired := PackedFloat32Array()   # how hard each nozzle fired this tic (0..1)
var fires := 0                       # nozzle firings, counted, for the tests
## THE REENTRY FIRE: the cap and the tail (turned to the way the pod is
## going), their materials, the hull's glow, the light on it, and how hot
## (0..1, the speed's); the hottest it has been, for the tests
var fire: Node3D
## the bow shock, the skirt, the wake (see _make_fire), their materials
var fire_parts: Array = []
var fire_mats: Array = []
var heat_mat: ShaderMaterial
var fire_light: OmniLight3D
var heat := 0.0
var max_heat := 0.0
## what the exhaust and the door have done to the plants and the people,
## counted, for the tests
var plants_hit := 0
var scorches := 0       ## marks laid at the touchdown, for the tests
var door_kills := 0
var burned := 0         ## people and creatures the exhaust set alight

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
## THE STICK'S TANK: nozzle-seconds of RCS left (DROP.rcs_fuel to begin)
var fuel: float = DROP.rcs_fuel
var auto_burn := false
var retro_level := 0.0
## the autopilot's burn, once lit: "" none, "burn" the suicide burn, "final"
## the last metres flown down at the aim speed
var auto_mode := ""
var landed_at := 0
var door_vel := Vector3.ZERO
var door_spin := Vector3.ZERO
var door_pos := Vector3.ZERO
var door_basis := Basis.IDENTITY
var door_down := false
var start := Vector2.ZERO   # the start, map units
var blockers: Array = []
## the posts across the doorway until the door is off (nobody walks in)
var door_posts: Array = []
var ticks := 0
var touchdown_speed := 0.0
## hanging at the top, not yet begun: see `tic`
var held := true

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
	# relative to it, and the model moved (and drawn at POD_SCALE) so the
	# frame is this node's
	var hull_t := _tree_transform(hull)
	shift = hull_t.origin
	model.scale = Vector3.ONE * POD_SCALE
	model.position = -shift * POD_SCALE
	for mi: MeshInstance3D in meshes:
		if mi == hull:
			continue
		var t := _tree_transform(mi)
		var box := mi.get_aabb()
		if box.size.length() < 0.5:
			# (read in the model's own metres, kept at the pod's size)
			var c: Vector3 = t * box.get_center() - shift
			nozzles.append({"pos": c * POD_SCALE, "dir": _nozzle_dir(c), "kind": "retro" if c.y < 3.5 else "rcs"})
			mi.queue_free()
		else:
			door = mi
	# (the importer made collision bodies of the -col names: not wanted)
	for b in model.find_children("*", "StaticBody3D", true, false):
		b.queue_free()
	door_home = door.transform
	# THE PAINT AT A QUARTER ITS SIZE, Bayer-dithered to 32 x 32 x 23 levels
	# (the textures themselves, assets/models/drop_pod_*.png, at the user's
	# request): drawn nearest, so the dither reads as a dither
	var done := {}
	for mi: MeshInstance3D in [hull, door]:
		if mi == null or mi.mesh == null:
			continue
		for k in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(k)
			if m is BaseMaterial3D and not done.has(m):
				done[m] = true
				var bm := m as BaseMaterial3D
				bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				# BRIGHTER (at the user's request: "brighten up descent pod"):
				# the paint's metal took nothing from a sky with no
				# reflections and went black — mostly paint now, rougher,
				# lifted a little, and its own picture glowing faintly
				# through so its shadowed side still reads
				bm.metallic = minf(bm.metallic, POD_LOOK.metallic)
				bm.roughness = maxf(bm.roughness, POD_LOOK.roughness)
				bm.albedo_color = bm.albedo_color * POD_LOOK.lift
				if bm.albedo_texture != null:
					bm.emission_enabled = true
					bm.emission = Color.WHITE
					bm.emission_texture = bm.albedo_texture
					bm.emission_energy_multiplier = POD_LOOK.glow
	fired.resize(nozzles.size())
	fired.fill(0.0)
	_make_flames()
	_make_fire()
	# the model is metres; this node lives in the game's units
	scale = Vector3.ONE * IslandLevel.U_PER_M

func _tree_transform(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p != null and p != model:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

## Which way a nozzle at `c` (the model's own metres, the pod's frame)
## sends its exhaust — the hull's own facing there, read off the model:
## see the header.
static func _nozzle_dir(c: Vector3) -> Vector3:
	var radial := Vector3(c.x, 0.0, c.z).normalized()
	if c.y < 3.5:
		# the skirt: down and out at 37 degrees
		return (radial * 0.79 + Vector3(0, -0.61, 0)).normalized()
	if c.y > 5.8:
		# the top ring: out and up
		return (radial * 0.84 + Vector3(0, 0.54, 0)).normalized()
	# a bulge-top pair: straight up, a touch outward (its push down on
	# that side, the pod tipping that way: see the header)
	return (radial * 0.2 + Vector3(0, 0.98, 0)).normalized()

## the flames: a unit cone (point up, base 1 across, no caps) per nozzle,
## coloured per nozzle (pod_flame.gdshader)
func _make_flames() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://godot/shaders/pod_flame.gdshader")
	var jet := _jet_mesh()
	jet.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = jet
	mm.instance_count = nozzles.size()
	mm.visible_instance_count = nozzles.size()
	for i in nozzles.size():
		mm.set_instance_color(i, _flame_color(nozzles[i].kind))
	flames = MultiMeshInstance3D.new()
	flames.multimesh = mm
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	_draw_flames()

## how many shock diamonds a jet has, and how low-res it is drawn
const DIAMONDS := 5
const JET_SEGS := 8

## THE JET as a mesh (at the user's request: "tight mach diamonds for all
## thrusters"): a surface of revolution along local +y from the nozzle
## (y 0) to its point (y 1), DIAMONDS diamonds along it joined at narrow
## waists — a radius of 1 at the first belly, pinched to DIAMOND_WAIST at
## each shock, the whole tapering to a point. UV.y is the way along it,
## for the shader's colour; UV.x where round.
const DIAMOND_WAIST := 0.3
static func _jet_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := DIAMONDS * 4
	var profile: PackedFloat32Array = []
	for r in rings + 1:
		var k := float(r) / rings
		var tri := 1.0 - absf(fmod(k * DIAMONDS, 1.0) * 2.0 - 1.0)
		var taper := pow(1.0 - k, 0.75)
		profile.append((DIAMOND_WAIST + (1.0 - DIAMOND_WAIST) * tri) * taper * 0.5)
	profile[rings] = 0.0
	for r in rings + 1:
		var k := float(r) / rings
		for sg in JET_SEGS + 1:
			var a := TAU * sg / JET_SEGS
			var rad: float = profile[r]
			st.set_uv(Vector2(float(sg) / JET_SEGS, k))
			var n := Vector3(cos(a), 0.0, sin(a))
			st.set_normal(n)
			st.add_vertex(Vector3(cos(a) * rad, k, sin(a) * rad))
	for r in rings:
		for sg in JET_SEGS:
			var a0 := r * (JET_SEGS + 1) + sg
			var a1 := a0 + 1
			var b0 := a0 + JET_SEGS + 1
			var b1 := b0 + 1
			st.add_index(a0); st.add_index(b0); st.add_index(a1)
			st.add_index(a1); st.add_index(b0); st.add_index(b1)
	return st.commit()

## a jet's colour — bright blue, all of them, at the user's request — and
## in its alpha its kind (pod_flame.gdshader): the RCS 0, the retros 1
static func _flame_color(kind: String) -> Color:
	return Color(0.25, 0.6, 1.0, 0.0) if kind == "rcs" else Color(0.3, 0.65, 1.0, 1.0)

## THE REENTRY FIRE (see the header): a cap and a tail, turned in `draw`
## to the way the pod is going, the hull's glow and a light; hidden cold.
func _make_fire() -> void:
	var sh: Shader = load("res://godot/shaders/reentry.gdshader")
	fire = Node3D.new()
	add_child(fire)
	# THE BOW SHOCK: a dish of plasma standing off the shield, the shape
	# of the shield (a flattened ball, only its front half drawn)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 32
	ball.rings = 16
	fire_parts.append(_fire_part(ball, sh, 0.0))
	# THE SKIRT: a sheet of plasma from the shield's rim flaring out and
	# back at the angle of the hull's foot, and THE WAKE outside it,
	# wider, taller, thinner, redder (CylinderMesh: bottom at the rim,
	# the top wide — a shuttlecock)
	for layer in [1.0, 2.0]:
		var cone := CylinderMesh.new()
		cone.bottom_radius = 1.0
		cone.top_radius = 2.3 if layer < 1.5 else 2.9
		cone.height = 1.0
		cone.radial_segments = 40
		cone.rings = 10
		cone.cap_top = false
		cone.cap_bottom = false
		fire_parts.append(_fire_part(cone, sh, layer))
	heat_mat = ShaderMaterial.new()
	heat_mat.shader = load("res://godot/shaders/pod_heat.gdshader")
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.6, 0.3)
	fire_light.omni_range = 30.0
	fire_light.shadow_enabled = false
	fire_light.position = Vector3(0.0, -HULL_R * 0.3, 0.0)
	fire.add_child(fire_light)
	fire.visible = false

func _fire_part(mesh: Mesh, sh: Shader, layer: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("layer", layer)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.add_child(mi)
	fire_mats.append(m)
	return mi

# ------------------------------------------------------------------
# THE RIDE
# ------------------------------------------------------------------

## Begun over the start (map units): the pod high up, coming in fast.
func begin(sx: float, sy: float) -> void:
	start = Vector2(sx, sy)
	var ang_off := randf() * TAU
	var um := IslandLevel.U_PER_M
	var gz: float = game.level.floor_at(sx, sy) / um
	pos = Vector3(sx / um + cos(ang_off) * DROP.offset, gz + DROP.height, -sy / um + sin(ang_off) * DROP.offset)
	vel = Vector3(-cos(ang_off), 0.0, -sin(ang_off)) * DROP.drift + Vector3(0.0, -DROP.entry, 0.0)
	att = Basis(Vector3(1, 0, 0), 0.12).rotated(Vector3(0, 0, 1), -0.08)
	ang = Vector3(0.02, 0.0, -0.03)
	prev_pos = pos
	prev_att = att
	phase = "drop"
	phase_tics = 0
	active = true
	visible = true
	if not RCS_ON:
		att = Basis()
		ang = Vector3.ZERO
	heat = _heat_of(altitude())
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

## how hot the reentry fire is at altitude `h` (m): full over the first
## DROP.fire_share of the way down, going out over the next DROP.fire_fade
## of it, and never after (at the user's request: "reentry burn last 75%
## of the descent")
static func _heat_of(h: float) -> float:
	var down := 1.0 - h / DROP.height
	return clampf((DROP.fire_share + DROP.fire_fade - down) / DROP.fire_fade, 0.0, 1.0)

## One tic of the ride, with this machine's hands (Game.local_cmd).
## THE BURN SITES SMOULDER (at the user's request: "make the scorched pod
## landing burn sites steaming / smoking after the fact for like 5
## minutes"): every few marks a vent [x, y, z, size, born] that smokes
## and steams for SMOULDER_TICS, thick at first and thinning to nothing
const SMOULDER_TICS := 5 * 60 * 35
var vents := []
var vent_puffs := 0
## their own smoke, so five minutes of it never crowds out a gun's
var vent_smoke: Particles
func _vents_tic() -> void:
	if vent_smoke != null:
		vent_smoke.tic()
	if vents.is_empty() or game.fx == null:
		return
	if vent_smoke == null:
		vent_smoke = Particles.new({"max": 260, "map": Effects.atlases().smoke, "frames": Effects.SMOKE_PUFFS, "blend": "mix",
			"fullbright": false, "near_shrink": 90.0, "order": 14})
		vent_smoke.mat.set_shader_parameter("light", U.col(0.55))
		_beside(vent_smoke)
	var keep := []
	for v in vents:
		var age: int = ticks - int(v[4])
		if age >= SMOULDER_TICS:
			continue
		keep.append(v)
		var k := 1.0 - float(age) / SMOULDER_TICS
		# (one in so many tics, fewer as it cools)
		var every := int(lerpf(90.0, 26.0, k * k))
		if (ticks + int(v[0])) % every != 0:
			continue
		var x: float = v[0] + randf_range(-0.3, 0.3) * v[3]
		var y: float = v[1] + randf_range(-0.3, 0.3) * v[3]
		vent_puffs += 1
		if randf() < 0.5:
			game.fx.puff(x, y, float(v[2]) + 4.0, 14.0 + 20.0 * k, int(90 + 90 * k), vent_smoke)
		else:
			game.fx.steam(x, y, float(v[2]) + 3.0, 10.0 + 16.0 * k, int(60 + 60 * k), vent_smoke)
		if age < 60 * 35 and randf() < 0.15 * k:
			game.fx.ember(x, y, float(v[2]) + 2.0, 1, 0.8)
	vents = keep

func _process(_dt: float) -> void:
	if vent_smoke != null:
		vent_smoke.draw()
	if wash != null:
		wash.draw()

func tic(cmd: Dictionary) -> void:
	# HELD AT THE TOP while the island is raised and the loading screen is
	# up (Game.loading): the game ticks under it, and the ride is ten
	# seconds — it would be over before it was seen
	if held:
		if game.island_ready() and not bool(game.get("loading")):
			held = false
		else:
			_sync_player()
			return
	ticks += 1
	phase_tics += 1
	_vents_tic()
	if wash != null:
		wash.tic()
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
				# (the player is outside now: not synced back in)
				return
		"out":
			# (the player is their own once the door is off: the sync here put
			# them back at the pod's middle every tic — stuck in the pod, at
			# the user's report — so no more of it)
			_door_tic()
			return
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
	# (uncontrolled, the RCS off: nothing the hands do reaches it)
	if not RCS_ON:
		want_tilt = Vector3.ZERO
		retro_on = false
	# ---- the autopilot: the suicide burn -------------------------------
	# the braking it would take from here to be down to the aim speed a
	# metre over the ground; lit when that comes to the planned share of
	# what the retros have, and flown at whatever it comes to after, so the
	# pod stops at the last; then the last metres at the aim speed
	var vz := vel.y
	var lift: float = DROP.retro * 8.0 * DROP.retro_lift * maxf(up.y, 0.3)
	var drag := _drag()
	var air: float = drag * vz * vz
	var aim: float = DROP.aim_speed
	var need := 0.0
	if vz < -aim:
		need = (vz * vz - aim * aim) / (2.0 * maxf(h - 1.0, 0.3))
	var plan: float = (lift - DROP.g) * DROP.plan
	# (never in the reentry fire: at the entry's speed the sum says brake
	# from the top, and the air does that braking — the burn waits for the
	# fire to be out and the fall at terminal)
	if auto_mode == "" and vz < 0.0 and need >= plan and heat <= 0.0:
		auto_mode = "burn"
	if auto_mode == "burn" and vz > -aim * 1.1:
		auto_mode = "final" if h < 15.0 else ""
	if auto_mode == "final" and h > 25.0:
		auto_mode = ""
	var auto_level := -1.0
	if auto_mode == "burn":
		auto_level = clampf((need + DROP.g - air) / maxf(lift, 1.0), 0.0, 1.0)
	elif auto_mode == "final":
		auto_level = clampf((DROP.g - air + (-aim - vz) * 3.0) / maxf(lift, 1.0), 0.0, 1.0)
	auto_burn = auto_mode != ""
	# ---- the attitude: the stick's, until the autopilot takes it --------
	# (the last DROP.level_secs at the fall's speed: leaning against any
	# drift while it burns, upright for the ground)
	var piloted: bool = h < maxf(DROP.level_below, -vz * DROP.level_secs)
	var want_up := Vector3.UP
	if piloted:
		want_tilt = Vector3.ZERO
		var hv := Vector3(vel.x, 0.0, vel.z)
		if not over_land:
			# over the cloud sea: lean toward the start and hold the height
			var to_start := Vector3(start.x / IslandLevel.U_PER_M - pos.x, 0.0, -start.y / IslandLevel.U_PER_M - pos.z)
			want_up = (Vector3.UP * cos(0.5) + to_start.normalized() * sin(0.5)).normalized()
			auto_burn = true
			auto_level = clampf((DROP.g - air - vz * 2.0) / maxf(lift * cos(0.5), 1.0), 0.0, 1.0)
		elif auto_burn and h > 6.0 and hv.length() > 0.3:
			var lean := clampf(hv.length() * 0.03, 0.0, 0.3)
			want_up = (Vector3.UP * cos(lean) - hv.normalized() * sin(lean)).normalized()
	# ---- the RCS: a rate for the tilt asked; else turned to the attitude
	# wanted (upright, or leaning on the drift) ---------------------------
	var want_ang := Vector3.ZERO
	# (the stick draws on the tank; dry, it is dead — the levelling below
	# is the autopilot's and free)
	var stick := want_tilt.length_squared() > 1e-4
	if stick and fuel <= 0.0:
		want_tilt = Vector3.ZERO
		stick = false
	if stick:
		var axis := Vector3.UP.cross(want_tilt.normalized())
		want_ang = axis * DROP.rate * minf(1.0, want_tilt.length())
		# (never past 50 degrees over)
		if tilt() > 0.87 and axis.dot(up.cross(Vector3.UP)) < 0.0:
			want_ang = Vector3.ZERO
	else:
		want_ang = up.cross(want_up) * (1.2 if piloted else 0.4)
	_acc_tmp = Vector3.ZERO
	_alpha_tmp = Vector3.ZERO
	if RCS_ON:
		_rcs(want_ang - ang, stick)
	var acc := _acc_tmp
	var alpha := _alpha_tmp
	# ---- the retros: full on the trigger (but the last metres are the
	# autopilot's), else the autopilot's level -----------------------------
	var want_level := maxf(auto_level, 0.0)
	if retro_on and not (auto_mode == "final" and h < 8.0):
		want_level = 1.0
	retro_level += clampf(want_level - retro_level, -0.2, 0.25)
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
			alpha += (att * n.pos - att * Vector3(0, 2.5 * POD_SCALE, 0)).cross(f) / DROP.inertia * 0.15
	# ---- the air, the ground's pull, a capsule's stability ------------
	acc += Vector3(0, -DROP.g, 0)
	acc -= vel * vel.length() * drag
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
	# ---- the reentry fire: the speed's, and left along the way ---------
	heat = _heat_of(altitude())
	max_heat = maxf(max_heat, heat)
	if heat > 0.0:
		_trail()
	# ---- what the exhaust does to the plants under and round it ------
	if game.veg_damage != null and over_land and h < 70.0 and ticks % 3 == 0:
		_plume_plants()
	# ---- the jet wash on the ground under a burn, and the touchdown -----
	if over_land and pos.y > ground:
		_wash_tic(ground, h)
	if over_land and pos.y <= ground:
		_touchdown(ground)

var _acc_tmp := Vector3.ZERO
var _alpha_tmp := Vector3.ZERO

## THE AIR'S DRAG: one all the way down now (the thin air at the top and
## the thickening after the fire went with the 250% faster fall)
func _drag() -> float:
	return DROP.drag
## THE RCS: for a wanted change of spin (world, rad/s), fire the nozzles
## whose turning is that way, as hard as the want is. Their push and turn
## are added to _acc_tmp and _alpha_tmp. `from_tank`: the stick's turn,
## which spends `fuel` (a nozzle-second per nozzle per second at full).
func _rcs(want: Vector3, from_tank := false) -> void:
	var need := want.length()
	if need < 0.02:
		return
	var level := clampf(need / 0.6, 0.15, 1.0)
	var dt := 1.0 / U.TICRATE
	var wdir := want / need
	var centre := att * Vector3(0, 3.0 * POD_SCALE, 0)
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
		if from_tank:
			fuel = maxf(0.0, fuel - level * dt)
		_acc_tmp += f * level
		_alpha_tmp += torque * level / DROP.inertia

## THE WAY IT CAME, BURNING: fire left along the last tic's path, sparks
## thrown off, a smoke trail after — the more and the bigger, the hotter.
func _trail() -> void:
	var um := IslandLevel.U_PER_M
	var back := -vel.normalized()
	var step := vel.length() / U.TICRATE
	# SPARKS: a shower off the shield's rim, thrown wide, every tic
	var e := pos + back * TALL * 0.6
	game.fx.ember(e.x * um, -e.z * um, e.y * um, 6 + int(heat * 10.0), 2.8)
	# FLECKS: small bright bits of plasma coming off the skirt, short-lived
	for k in 2 + int(heat * 3.0):
		var a := randf() * TAU
		var f := pos + back * (TALL * randf_range(0.3, 0.9)) + Vector3(cos(a), 0.0, sin(a)) * HULL_R * randf_range(0.9, 1.5)
		game.fx.fireball(f.x * um, -f.z * um, f.y * um, 14.0 + 16.0 * heat, 4 + int(heat * 4))
	# FIREBALLS: bigger, fewer, further back in the wake
	if ticks % 2 == 0:
		var q := pos + back * (TALL * 1.2 + randf() * step)
		game.fx.fireball(q.x * um, -q.z * um, q.y * um, 40.0 + 50.0 * heat, 8 + int(heat * 8))
	# SMOKE: a dark trail behind, and a wisp off the skirt
	var s := pos + back * (TALL * 1.5 + randf() * step)
	game.fx.puff(s.x * um, -s.z * um, s.y * um, 28.0 + 36.0 * heat, 100)
	if ticks % 3 == 0:
		var a2 := randf() * TAU
		var w := pos + back * TALL * 0.8 + Vector3(cos(a2), 0.0, sin(a2)) * HULL_R * 1.6
		game.fx.puff(w.x * um, -w.z * um, w.y * um, 18.0, 50)

## THE LANDING ON THE PEOPLE AND THE CREATURES, at the user's request
## ("make the thruster exhaust kill and set people and creatures alight on
## landing" — then "the girls need to be set alight / smushed right as it
## lands, not before" — and then "have npcs burst into flame before touch
## down as jets touch them"): on the way down, once the retros' jets reach
## the ground, whoever they wash over bursts into flame (_wash_tic); on
## the touchdown tic, whoever is under the hull (within `squash` metres of
## its rim) is SQUASHED — gone to pieces — and everybody out to
## `touchdown` metres from it still standing is set alight (they burn and
## burn out: Actor.ignite, a burning state, and ash), anybody who cannot
## burn killed outright.
const BURN := {"squash": 0.6, "touchdown": 14.0}
var squashed := 0
## the people the jets set alight before the touchdown
var jet_burned := 0

func _set_alight(a) -> void:
	var was: int = a.burning
	a.ignite(int(10 * U.TICRATE))
	if not a.info.has("burn"):
		a.damage(10000.0, game.player, {"fire": true})
	if a.burning > 0 and was <= 0 or a.dead:
		burned += 1
	if game.fx != null:
		game.fx.ember(a.x, a.y, a.z + 20.0, 2, 1.4)

## THE JET WASH, at the user's request ("add jet wash effects as pod
## lands"): once the retros are lit and the pod is within WASH.reach
## metres of the ground, the eight canted jets hit it in a ring that
## spreads the higher the pod is — HULL_R + WASH.spread * height — and
## the ground there blows out: dust and smoke thrown flat and fast away
## from the ring (its own pool, `wash`, not the shared smoke's), sparks
## and embers whipped out with it as the pod gets close, and at the
## touchdown one last ring of it all, the shock. And anybody standing in
## the ring bursts into flame there and then.
const WASH := {"reach": 22.0, "spread": 0.45}
var wash: Particles
var wash_puffs := 0

## (a pool of the game's own units goes in the game beside the pod, not in
## the pod: the pod's node is scaled to metres and moves with it — and it
## goes when the pod does)
func _beside(n: Node) -> void:
	game.add_child(n)
	tree_exiting.connect(n.queue_free)

func _wash_pool() -> Particles:
	if wash == null:
		wash = Particles.new({"max": 900, "map": Effects.atlases().smoke, "frames": Effects.SMOKE_PUFFS, "blend": "mix",
			"fullbright": false})
		wash.mat.set_shader_parameter("light", U.col(0.95))
		_beside(wash)
	return wash

## one billow of the wash at (x, y, z), blown out along `dir` at `sp`
func _wash_puff(x: float, y: float, z: float, dir: Vector2, sp: float, size: float) -> void:
	var tone := randf_range(0.75, 1.0)
	_wash_pool().spawn({
		"x": x, "y": y, "z": z,
		"vx": dir.x * sp, "vy": dir.y * sp, "vz": randf_range(0.1, 0.7),
		"life": randi_range(50, 95),
		"size0": size, "size1": size * 3.6,
		"c0": Color(0.92 * tone, 0.86 * tone, 0.76 * tone, 0.9), "c1": Color(0.62, 0.6, 0.58, 0.0),
		"frame": float(randi() % Effects.SMOKE_PUFFS), "frameRate": 0.14,
		"drag": 0.93, "gravity": 0.0,
	})
	wash_puffs += 1

func _wash_tic(ground: float, h: float) -> void:
	if retro_level < 0.1 or h > WASH.reach:
		return
	var um := IslandLevel.U_PER_M
	var k := clampf(1.0 - h / WASH.reach, 0.0, 1.0)
	var cx := pos.x * um
	var cy := -pos.z * um
	var gz := ground * um
	var ring: float = (HULL_R + WASH.spread * h) * um
	# the ground blowing out from the ring
	var n := int((4.0 + 12.0 * k) * retro_level)
	for i in n:
		var a := randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var r := ring * randf_range(0.7, 1.1)
		var x := cx + dir.x * r
		var y := cy + dir.y * r
		var f: float = game.level.floor_at(x, y)
		if f <= IslandLevel.NO_FLOOR:
			continue
		_wash_puff(x, y, f + 10.0, dir, randf_range(8.0, 14.0 + 12.0 * k), randf_range(40.0, 70.0))
	# grit and sparks whipped out with it, close in
	if game.fx != null and k > 0.4 and ticks % 2 == 0:
		var a := randf() * TAU
		game.fx.ember(cx + cos(a) * ring, cy + sin(a) * ring, gz + 6.0, 2, 0.6)
	# whoever the jets wash over: alight, now (the jets cant out, so not
	# whoever is right under the hull — that is for the squash)
	if ticks % 2 == 0:
		var shadow := HULL_R * 0.8 * um
		for a in game.blockmap.near_radius(cx, cy, ring + 0.5 * um):
			if a.dead or a.removed or a.burning > 0 or a.get("vehicle") != null or a == game.player:
				continue
			if a.z > gz + 4.0 * um or Vector2(a.x - cx, a.y - cy).length() < shadow:
				continue
			_set_alight(a)
			jet_burned += 1

## the touchdown's shock: one ring of wash thrown out hard all round
func _wash_shock(gx: float, gy: float) -> void:
	var um := IslandLevel.U_PER_M
	for i in 140:
		var a := TAU * i / 140.0 + randf_range(-0.04, 0.04)
		var dir := Vector2(cos(a), sin(a))
		var r := HULL_R * um * randf_range(0.9, 1.3)
		var f: float = game.level.floor_at(gx + dir.x * r, gy + dir.y * r)
		if f <= IslandLevel.NO_FLOOR:
			continue
		_wash_puff(gx + dir.x * r, gy + dir.y * r, f + 12.0, dir, randf_range(22.0, 38.0), randf_range(50.0, 90.0))
func _land_on_people(gx: float, gy: float, gz: float) -> void:
	var um := IslandLevel.U_PER_M
	var under := (HULL_R + BURN.squash) * um
	for a in game.blockmap.near_radius(gx, gy, (HULL_R + BURN.touchdown) * um):
		if a.removed or a.get("vehicle") != null or a == game.player:
			continue
		if a.z > gz + 4.0 * um:
			continue
		var d := Vector2(a.x - gx, a.y - gy).length()
		if d < under + a.radius:
			# (the jets may have lit them and they burnt to the ground on the
			# way down: what lies under the hull is squashed all the same)
			squashed += 1
			if a.dead:
				game.gib(a)
			else:
				a.damage(100000.0, game.player, {"impact": true, "gib": true, "pod": true})
			if game.gore_decals != null:
				game.gore_decals.pool(a.x, a.y, a.z, 60.0)
			continue
		if not a.dead and a.burning <= 0:
			_set_alight(a)

## THE EXHAUST INTO THE PLANTS (VegDamage), every third tic low down: the
## retros' downwash under the skirt — a column spreading as it goes down,
## a ring along the ground once it gets there — and each RCS jet firing.
func _plume_plants() -> void:
	var vd = game.veg_damage
	var um := IslandLevel.U_PER_M
	if retro_level > 0.15:
		var skirt := pos + att * Vector3(0.0, 2.1 * POD_SCALE, 0.0)
		plants_hit += vd.downwash(Vector3(skirt.x * um, -skirt.z * um, skirt.y * um), HULL_R * 1.1 * um, 0.45,
			30.0 * um * retro_level, 9.0 * retro_level)
	for i in nozzles.size():
		var n: Dictionary = nozzles[i]
		if n.kind != "rcs" or fired[i] < 0.1:
			continue
		var wp: Vector3 = pos + att * n.pos
		var wd: Vector3 = att * n.dir
		plants_hit += vd.jet(Vector3(wp.x * um, -wp.z * um, wp.y * um), Vector3(wd.x, -wd.z, wd.y),
			7.0 * um * fired[i], 2.0 * um, 6.0 * fired[i])

func _touchdown(ground: float) -> void:
	touchdown_speed = vel.length()
	pos.y = ground
	vel = Vector3.ZERO
	ang = Vector3.ZERO
	retro_level = 0.0
	auto_burn = false
	retro_on = false
	heat = 0.0
	phase = "landed"
	phase_tics = 0
	landed_at = ticks
	var um := IslandLevel.U_PER_M
	var gx := pos.x * um
	var gy := -pos.z * um
	var gz := ground * um
	game.play_sound("explode", null)
	_wash_shock(gx, gy)
	for k in 12:
		game.fx.puff(gx + randf_range(-80.0, 80.0), gy + randf_range(-80.0, 80.0), gz + 8.0, 60.0, 90)
	# THE SCORCHING is a RING round the hull, not under it: a mark laid at
	# the middle would paint the pod's own floor (a projected decal takes
	# any surface in its box). Six blast marks close in, and (at the
	# user's request: "lots more scorch marks around pod when landing") a
	# scatter of scorches and smaller blast marks out to ten metres, the
	# retros' last seconds burnt into the ground
	# ... AND FOUR TIMES OVER (at the user's request: "make the ground
	# scorching 400% more intense / spread out / visible / bigger"): four
	# times the marks, twice the size, out twice as far, and the ring
	# round the hull laid twice, so the black is black. And every one of
	# them goes on smouldering (vents, _vents_tic).
	if game.decals != null:
		var marks := []
		for k in 24:
			var a := k * TAU / 12.0 + 0.3 + (0.13 if k >= 12 else 0.0)
			marks.append([a, (HULL_R + 1.8 + (2.2 if k >= 12 else 0.0)) * um, 160.0, false])
		for k in 104:
			var a := randf() * TAU
			var r := (HULL_R + 1.4 + pow(randf(), 1.2) * 17.0) * um
			marks.append([a, r, randf_range(60.0, 150.0) * (1.0 - 0.4 * r / (24.0 * um)), k % 3 != 0])
		var i := 0
		for m in marks:
			var sx: float = gx + cos(m[0]) * m[1]
			var sy: float = gy + sin(m[0]) * m[1]
			var sf: float = game.level.floor_at(sx, sy)
			if sf <= IslandLevel.NO_FLOOR:
				continue
			if m[3]:
				game.decals.scorch(Vector3(sx, sy, sf), Vector3(0, 0, 1), m[2])
				# (twice, for the black)
				game.decals.scorch(Vector3(sx, sy, sf), Vector3(0, 0, 1), m[2] * 0.7)
			else:
				game.decals.blast(Vector3(sx, sy, sf), Vector3(0, 0, 1), m[2])
			scorches += 1
			if i % 3 == 0:
				vents.append([sx, sy, sf, m[2], ticks])
			i += 1
	# the people and the creatures round it: alight
	_land_on_people(gx, gy, gz)
	# nothing left growing through the hull, and round it the plants blown
	# flat as a blast would
	if game.veg_damage != null:
		plants_hit += game.veg_damage.clear(Vector3(gx, gy, gz), (HULL_R + 1.0) * um)
		game.veg_damage.blast(Vector3(gx, gy, gz + 20.0), 380.0)
	# THE DECK: the inside floor a floor (you stand on it, and step down
	# out of the door)
	if game.level is IslandLevel:
		game.level.add_deck(gx, gy, INNER_R * um, (ground + DECK) * um)
	_place_blockers()
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

## A RING OF INVISIBLE POSTS round the hull, none across the doorway: a
## post whose middle is nearer the line out of the door than the door's
## half-width and its own radius is left out, so the gap is the door's
## width. And three posts across the doorway itself until the door is off.
func _place_blockers() -> void:
	var um := IslandLevel.U_PER_M
	var gx := pos.x * um
	var gy := -pos.z * um
	var dd := door_dir()
	var dv := Vector2(dd.x, -dd.z).normalized()
	var ring := (HULL_R - 0.1) * um
	var post: float = float(States.actor("PODWALL").get("radius", 10))
	var half := DOOR_HALF * um + post
	for k in BLOCKERS:
		var a := k * TAU / BLOCKERS
		var o := Vector2(cos(a), sin(a)) * ring
		if o.dot(dv) > 0.0 and absf(o.x * dv.y - o.y * dv.x) < half:
			continue
		blockers.append(game.spawn("PODWALL", gx + o.x, gy + o.y, 0.0))
	var across := Vector2(-dv.y, dv.x)
	for s in [-1.0, 0.0, 1.0]:
		var q: Vector2 = Vector2(gx, gy) + dv * ring + across * s * (DOOR_HALF * um - post)
		door_posts.append(game.spawn("PODWALL", q.x, q.y, 0.0))

## THE DOOR BLOWS OFF: thrown out the way it faces, tumbling, a flash.
func _blow_door() -> void:
	phase = "out"
	phase_tics = 0
	door_down = false
	var out := door_dir()
	# (the door's place in the file, in the model's metres, to the pod's)
	door_pos = pos + att * ((door_home.origin - shift) * POD_SCALE)
	door_basis = att * door_home.basis
	door_vel = out * DOOR_SPEED + Vector3(0, 4.5, 0)
	for b in door_posts:
		if b != null:
			b.remove()
	door_posts.clear()
	door_spin = (att * Vector3(1, 0, 0)) * 5.0 + Vector3(0, 1.5, 0)
	var um := IslandLevel.U_PER_M
	var at := door_pos * um
	var gx := at.x
	var gy := -at.z
	game.fx.fireball(gx, gy, at.y, 80.0, 24)
	for k in 6:
		game.fx.puff(gx + randf_range(-30, 30), gy + randf_range(-30, 30), at.y + randf_range(-20, 20), 40.0, 70)
	game.play_sound("explode", null)
	# AND OUT: the player set down outside the doorway, on the ground,
	# facing away from the pod (at the user's report: "player still
	# cannot exit pod, maybe move them outside the pod right after the
	# door ejects" — so they are out the moment it is gone)
	_step_out(out)
	BlackBox.mark("drop: door blown")

## The player put just outside the door, a step past the hull, standing
## on whatever is there (the ground, not THE DECK), looking out.
func _step_out(out: Vector3) -> void:
	var p = game.player
	var um := IslandLevel.U_PER_M
	var at := pos + out * (HULL_R + 1.0)
	var gx := at.x * um
	var gy := -at.z * um
	var f: float = game.level.floor_at(gx, gy)
	p.x = gx
	p.y = gy
	p.z = f if f > IslandLevel.NO_FLOOR else pos.y * um
	p.view_z = p.z + U.PLAYER_EYE
	p.momx = 0.0
	p.momy = 0.0
	p.momz = 0.0
	p.on_ground = true
	p.sector = game.level.sector_at(gx, gy)
	p.angle = door_angle()
	p.pitch = 0.0
	p.prev = Vector4(p.x, p.y, p.view_z, 0)

func _door_tic() -> void:
	if door_down:
		return
	var dt := 1.0 / U.TICRATE
	door_vel += Vector3(0, -DROP.g, 0) * dt
	door_pos += door_vel * dt
	var w := door_spin.length()
	if w > 1e-6:
		door_basis = Basis(door_spin / w, w * dt) * door_basis
	_door_hits()
	var f: float = game.level.floor_at(door_pos.x * IslandLevel.U_PER_M, -door_pos.z * IslandLevel.U_PER_M)
	var g: float = f / IslandLevel.U_PER_M if f > IslandLevel.NO_FLOOR else pos.y - 30.0
	if door_pos.y <= g + 0.2:
		door_pos.y = g + 0.2
		door_down = true
		# flat on the ground, face up, the way it was going
		var fl := door_vel
		fl.y = 0.0
		door_basis = Basis.looking_at(fl.normalized() if fl.length() > 0.1 else Vector3(0, 0, -1), Vector3.UP) * Basis(Vector3(1, 0, 0), -PI / 2.0)

## WHAT THE DOOR HITS on its way (at the user's request: "door popping off
## should destroy things and people it hits"): anybody within DOOR_HIT_R of
## it at its height is blown apart (a lamp knocked to pieces), every plant
## it goes through shredded (VegDamage.sweep) — and it goes on, a little
## slower for each.
func _door_hits() -> void:
	var um := IslandLevel.U_PER_M
	var at := Vector3(door_pos.x * um, -door_pos.z * um, door_pos.y * um)
	var way := Vector3(door_vel.x, -door_vel.z, door_vel.y)
	var from := at - way.normalized() * 40.0 if way.length() > 0.1 else at
	var r := DOOR_HIT_R * um
	for o in game.actors_in_cone_around(at, r + 64.0):
		if o is Player or o.dead:
			continue
		var rr: float = r + float(o.radius)
		if U.dist2(at.x, at.y, o.x, o.y) > rr * rr:
			continue
		if at.z + r < o.z or at.z - r > o.z + o.height:
			continue
		o.damage(10000.0, game.player, {"gib": true, "door": true})
		door_kills += 1
		door_vel *= 0.85
	if game.veg_damage != null:
		var n: int = game.veg_damage.sweep(at, r, from)
		if n > 0:
			plants_hit += n
			door_vel *= pow(0.9, n)

## THE PLAYER RIDES INSIDE, standing on THE DECK: where the pod is, the
## map's units; the eye is placed by place_camera while it is third person,
## and by the player's own rules once inside.
func _sync_player() -> void:
	var p = game.player
	var um := IslandLevel.U_PER_M
	var gx := pos.x * um
	var gy := -pos.z * um
	p.prev = Vector4(p.x, p.y, p.view_z, 0)
	p.x = gx
	p.y = gy
	p.z = (pos + att * Vector3(0.0, DECK, 0.0)).y * um
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
## of the way from the tic before, and the reentry fire round it.
func draw(f: float) -> void:
	if not active:
		return
	var p := prev_pos.lerp(pos, f)
	var b := prev_att.slerp(att, f).orthonormalized()
	transform = Transform3D(b.scaled(Vector3.ONE * IslandLevel.U_PER_M), p * IslandLevel.U_PER_M)
	if phase == "out":
		# the door on its own, in the world (metres): back into the pod's
		# frame, then into the model's (its metres, under the shift), which
		# the door's node is a child of
		var inv := b.inverse()
		door.transform = Transform3D(inv * door_basis, (inv * (door_pos - p)) / POD_SCALE + shift)
	_draw_fire(b)
	_draw_flames()

## the reentry fire turned to the way the pod is going (its -y along the
## velocity, in the pod's frame), as hot as it is
func _draw_fire(b: Basis) -> void:
	var hot := heat > 0.01 and phase == "drop"
	fire.visible = hot
	hull.material_overlay = heat_mat if hot else null
	if not hot:
		return
	var v := vel if vel.length() > 1.0 else Vector3(0, -1, 0)
	var yv := -(b.inverse() * v).normalized()
	var xv := yv.cross(Vector3(0, 0, 1))
	if xv.length() < 0.1:
		xv = yv.cross(Vector3(1, 0, 0))
	xv = xv.normalized()
	var zv := xv.cross(yv).normalized()
	fire.transform = Transform3D(Basis(xv, yv, zv), Vector3.ZERO)
	# the layers, jumping a little every frame: the bow shock a dish a
	# quarter-radius ahead of the shield; the skirt from the rim, flaring
	# at the hull's foot's angle to half the hull's height; the wake past it
	var bow: MeshInstance3D = fire_parts[0]
	bow.scale = Vector3(HULL_R * randf_range(1.1, 1.2), HULL_R * randf_range(0.32, 0.4), HULL_R * randf_range(1.1, 1.2))
	bow.position = Vector3(0.0, -HULL_R * 0.22, 0.0)
	var skirt: MeshInstance3D = fire_parts[1]
	var sk := TALL * randf_range(0.5, 0.62)
	skirt.scale = Vector3(HULL_R * randf_range(0.95, 1.05), sk, HULL_R * randf_range(0.95, 1.05))
	skirt.position = Vector3(0.0, sk * 0.5 - HULL_R * 0.05, 0.0)
	var wake: MeshInstance3D = fire_parts[2]
	var wk := TALL * randf_range(0.75, 0.95)
	wake.scale = Vector3(HULL_R * randf_range(1.0, 1.15), wk, HULL_R * randf_range(1.0, 1.15))
	wake.position = Vector3(randf_range(-0.15, 0.15), wk * 0.5, randf_range(-0.15, 0.15))
	for m: ShaderMaterial in fire_mats:
		m.set_shader_parameter("heat", heat)
	heat_mat.set_shader_parameter("heat", heat)
	fire_light.light_energy = heat * randf_range(6.0, 12.0)
	# and the colour of the whole thing shifts as it dies: blue-white
	# hottest, orange, then red (the shader's `age`)
	for m: ShaderMaterial in fire_mats:
		m.set_shader_parameter("age", 1.0 - heat)

## The jets, each nozzle's as hard as it fired: a chain of shock diamonds
## out along the exhaust to a point, the RCS blue, the retros orange.
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
		mm.set_instance_transform(i, flame_transform(i, lv, randf_range(0.85, 1.15)))

## nozzle i's jet at `lv` (0..1), `flicker` times its length, from the
## nozzle out along its exhaust; the pod's frame
func flame_transform(i: int, lv: float, flicker := 1.0) -> Transform3D:
	var n: Dictionary = nozzles[i]
	var rcs: bool = n.kind == "rcs"
	# (an RCS jet a short one even fired lightly: it is seen to fire)
	var length: float = (2.2 * (0.45 + 0.55 * lv) if rcs else 3.2 * lv) * flicker
	var width: float = (0.5 if rcs else 0.6) * (0.7 + 0.3 * lv)
	var d: Vector3 = n.dir
	var look := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	# the jet's +y (nozzle to point) turned out along the exhaust
	var bz := look * Basis(Vector3.RIGHT, -PI / 2.0)
	bz = Basis(bz.x * width, bz.y * length, bz.z * width)
	return Transform3D(bz, n.pos)

## THE EYE BEHIND THE POD, third person: round it by the player's angle,
## up by their pitch, 14 m off, looking at its middle.
func place_camera(cam: Camera3D, f: float) -> void:
	var p: Player = game.player
	var centre := prev_pos.lerp(pos, f) + Vector3(0, TALL * 0.5, 0)
	var e := clampf(0.3 - p.pitch, -0.15, 1.2)
	var a: float = p.angle
	var back := Vector3(-cos(a), 0.0, sin(a))
	var eye := centre + (back * cos(e) + Vector3(0, sin(e), 0)) * 14.0
	# never under the ground
	var gf: float = game.level.floor_at(eye.x * IslandLevel.U_PER_M, -eye.z * IslandLevel.U_PER_M)
	if gf > IslandLevel.NO_FLOOR:
		eye.y = maxf(eye.y, gf / IslandLevel.U_PER_M + 1.5)
	cam.position = eye * IslandLevel.U_PER_M
	# (look_at takes a global point; the eye's parent is the game, scaled)
	cam.look_at((cam.get_parent() as Node3D).to_global(centre * IslandLevel.U_PER_M), Vector3.UP)
	cam.fov = 62.0

## the readout's numbers: altitude (m), the fall (m/s), the tilt, the
## retros, the autopilot, the reentry fire
func readout() -> Dictionary:
	var r := {"alt": altitude(), "fall": -vel.y, "tilt": rad_to_deg(tilt()), "retro": retro_level,
		"auto": auto_burn, "phase": phase, "speed": vel.length(), "heat": heat}
	if RCS_ON:
		r.fuel = fuel / DROP.rcs_fuel
	return r
