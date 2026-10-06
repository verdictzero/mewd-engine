## MEWD — the gun in your hands (js/weapon3d.js).
##
## Each weapon is a GLB, scaled so its longest side is its `fit` (in
## metres), recentred, turned barrel-first, and held at VIEW's hold plus
## the gun's own offset — pushed `out` along the view — with the walk's
## bob, the lag of a turn, and a kick while it fires. It is drawn in a
## world of its own, over the room and under the filter, exactly as the
## web build's overlay: the gun is IN the room (dithered and snapped
## with it) but never inside a wall.
class_name Weapon3D
extends Node3D

const GUN_LENGTH := 1.4
const VIEW := {"pos": [0.33, -0.40, -0.33], "yaw": 0.17, "pitch": 0.04, "roll": -0.05, "fov": 62.0}

const GUNS := {
	"FLAMER": {"url": "flamethrower.glb", "fit": GUN_LENGTH, "out": 3.0, "tint": [1, 1, 1]},
	"EXTINGUISHER": {"url": "extinguisher.glb", "fit": GUN_LENGTH, "out": 2.8, "tint": [0.72, 1.02, 1.45]},
	# (held further out and a size up, at the user's request: "i want to be
	# able to see more of the cerebral bore")
	"BORE": {"url": "bore.glb", "fit": GUN_LENGTH * 0.95, "out": 2.3, "pos": [0.06, -0.04, 0], "rot": [0.0, 0.05, 0.0], "tint": [1.6, 0.30, 0.22]},
	"MINIGUN": {"url": "minigun.glb", "fit": GUN_LENGTH * 1.25, "out": 2.6, "tint": [1.7, 1.4, 0.8], "heat": "minigun_barrel_mat", "spin": 6.0},
	# THE LANCE has a SCREEN and a LENS in it (js/scope.js): `display` is
	# the material the file paints flat that is the panel on the rear
	# deck — it wears the scope's live feed — and `optics` the green lens.
	# `aim` is a SECOND hold, blended to by the scope's aim(): the gun
	# swings up and inboard until the panel is in the middle of the frame
	# a hand's breadth from the eye (solved, not nudged — see js/weapon3d.js).
	"LANCE": {"url": "lance.glb", "fit": GUN_LENGTH * 1.9, "out": 2.4, "pos": [-0.12, 0.23, 0], "rot": [0.03, -0.09, 0.06], "tint": [0.55, 1.35, 0.80],
		"aim": {"pos": [-0.1894, 0.2730, 0], "rot": [-0.04, -0.17, 0.05], "out": 1.80},
		"display": {"material": "dynamic_display_surface_mat"},
		"optics": {"material": "optics_mat", "base": [0.34, 0.80, 0.0]}},
	# THE LAUNCHER'S SIGHT has a screen too, the thermal one (ThermalScope):
	# a slightly domed panel on the back of the sight under a material the
	# file spells `dyanmic_display_surface_mat`, and a second hold solved
	# as the lance's was — `rot` cancels VIEW's own turn so the screen faces
	# the eye, `pos` puts its middle straight ahead at about half the
	# picture's height (js/weapon3d.js)
	"LAUNCHER": {"url": "launcher.glb", "fit": GUN_LENGTH * 1.05, "out": 2.6, "pos": [0.20, -0.15, 0], "rot": [0.05, 0.16, -0.03], "tint": [1, 1, 1],
		"aim": {"pos": [-0.1034, 0.2552, 0.4515], "rot": [-0.04, -0.17, 0.05], "out": 1.0},
		"display": {"material": "dyanmic_display_surface_mat"}},
	# THE IRISH POTATO CANNON (game/potatoes.gd): its little screen is a
	# THERMAL SIGHT in night-vision green (ThermalScope `green`), raised to
	# the eye on the zoom as the launcher's is; its glass is glass, and
	# every other part keeps its own colours and textures ("pbr") — through
	# the same unlit gun shader as every gun, its metal given a made-up
	# sheen
	"POTATO": {"url": "potato_cannon.glb", "fit": GUN_LENGTH * 1.0, "out": 3.6, "pos": [0.26, -0.12, 0], "rot": [0.04, 0.05, -0.04], "tint": [1, 1, 1],
		"display": {"material": "dynamicDisplaySurfaceMat"}, "glass": "Glass", "pbr": true, "mirror": false,
		# as the file has it left to right (the user asked for it flipped
		# back), and pointed as every other gun is: muzzle at the file's +Z, the
		# sight's screen facing -Z, back at the eye (its normals say so) —
		# straight down the view; raised, the screen is straight ahead a
		# hand's breadth off
		"aim": {"solve": {"dist": 0.16, "yaw": 6.28318, "pitch": 0.0}}},
	# THE ARC MAW'S CHARGE (js/weapon3d.js orb): a ball of blue energy hung
	# between the prongs at `nozzle` (the model's own units), growing with
	# the charge, a halo round it, and motes streaming in from all round —
	# radius and reach in metres
	# (the user's own file again, at the user's request: "Unknown Device"
	# by Vaportrash, CC-BY-4.0 — assets/models/arcmaw_license.txt — as it
	# came, its 2048 maps and its own shading: `native`, lit by its own
	# lights in the gun's world; only shifted so the prongs' axis is x = y
	# = 0, as the game's old copy of it was)
	# — and now under a MATCAP, at the user's request ("use this mat cap for
	# the arc maw": nidorx/matcaps D0CCCB_524D50_928891_727581, a pearl),
	# its own colour and normal map under it (gun_matcap.gdshader)
	"ARC": {"url": "arcmaw.glb", "fit": GUN_LENGTH * 1.05, "out": 1.7, "pos": [0.02, 0.12, 0], "rot": [0, 0.06, 0], "tint": [0.7, 0.95, 1.9],
		"matcap": "res://assets/matcaps/pearl.png",
		"nozzle": [0.0, 0.0, 5.42], "orb": {"radius": 0.11, "reach": 0.26, "motes": 64}},
	# THE SARAKAWA MK II, the plasma rifle (game/plasma.gd), at the user's
	# request: the user's own file, its parts named for what they are — a
	# SCREEN on the side of the sight (`display`, the blue thermal sight,
	# raised to the eye on the zoom as the potato cannon's is), the sight's
	# front LENS (`optics`), the coil in the chamber that GLOWS (`emit`,
	# brighter when it fires) and the GLASS round it (`glass`, the
	# refracting glass the hopper has, tinted blue: `glass_body`). In its
	# own colours (`pbr`) through the gun shader, as every gun.
	"PLASMA": {"url": "sarakawa.glb", "fit": GUN_LENGTH * 1.1, "out": 2.7, "pos": [0.16, -0.10, 0], "rot": [0.03, -0.12, -0.03], "tint": [0.55, 0.85, 1.6],
		"display": {"material": "dynamicDisplaySurface"}, "optics": {"material": "Material.001", "base": [0.10, 0.45, 0.95]},
		# (the coil VERY BRIGHT, at the user's request: "make the plasma
		# rifle emission material very bright on the mesh" — far past white:
		# the gun's picture keeps it, so even the slivers of the coil seen
		# between the fins burn the chunky pixels they fall in blue-white)
		"emit": {"material": "Material.002", "color": [6.0, 8.0, 12.0]},
		"glass": "Glass", "glass_body": [0.70, 0.86, 1.0], "pbr": true,
		# (and the glass round the coil lets it shine out through it)
		"glass_clear": 0.75, "glass_bloom": 1.4, "glass_inner": [1.5, 1.9, 2.6],
		# the end of the barrel, in the model (at the user's request: "make
		# the plasma beam start at the end of the barrel not in mid air")
		"muzzle": [0.0, 0.46, 17.28],
		# (raised as the potato cannon is: pointed as at the hip, its screen
		# facing back at the eye as its normal says — at yaw 0, not a whole
		# turn: the same pose, but a whole turn was lerped to, and the rifle
		# spun round once on the way up; at the user's request, "stop the 360
		# flip on the plasma rifle when zooming in")
		"aim": {"solve": {"dist": 0.10, "yaw": 0.0, "pitch": 0.0}}},
}

var camera: Camera3D
var guns := {}
var current := ""
var sway := Vector2()
var kick := 0.0
var spin_angle := 0.0
## THE GUNS WITH A SCREEN ON THEM, name to scope (Scope, or anything that
## answers screen_material(), optics_material(base), set_panel_box(min,
## size) and aim()). Set before the gun is first drawn: the materials are
## handed out when the model loads.
var scopes := {}
## how far the gun in hand is raised to the eye, 0..1, chasing its
## scope's aim()
var aim := 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = VIEW.fov
	camera.near = 0.01
	camera.far = 50.0
	add_child(camera)
	camera.make_current()

func _load(name: String) -> Dictionary:
	var def: Dictionary = GUNS[name]
	var scene: PackedScene = load("res://assets/models/" + def.url)
	var root: Node3D = scene.instantiate()
	# the model's box, for `fit`
	var box := _aabb(root, Transform3D())
	var scale := float(def.fit) / maxf(box.size.x, maxf(box.size.y, box.size.z))
	var inner := Node3D.new()
	root.scale = Vector3.ONE * scale
	root.position = -box.get_center() * scale
	# a model made the other way about (its screen and grip on the far
	# side): mirrored left to right
	if def.get("mirror", false):
		root.scale.x = -root.scale.x
		root.position.x = -root.position.x
	inner.add_child(root)
	inner.rotation.y = PI
	var group := Node3D.new()
	group.add_child(inner)
	group.visible = false
	add_child(group)
	var mats := []
	var spinner: Node3D = null
	_dress(root, def, mats, scopes.get(name))
	if def.get("native", false):
		_light_native(group)
	if def.has("spin"):
		spinner = _find_spinner(root)
	var out := {"group": group, "mats": mats, "def": def, "spinner": spinner, "tip": _tip(group, spinner)}
	# THE MUZZLE WHERE THE MODEL SAYS (`muzzle`, the model's own units): the
	# box's front-middle is the barrel only on a gun that is all barrel; on
	# the plasma rifle the sight on top and the screen on the side pull it up
	# and over, and its bolt came out of the air beside the barrel
	if def.has("muzzle"):
		var mz: Array = def.muzzle
		out["tip"] = inner.transform * (root.transform * Vector3(mz[0], mz[1], mz[2]))
	if def.has("orb"):
		var nz: Array = def.get("nozzle", [0, 0, 0])
		out["orb"] = _make_orb(inner, root.transform * Vector3(nz[0], nz[1], nz[2]), def.orb)
	# A SOLVED AIM: the screen straight ahead of the eye, `dist` off, the
	# gun turned `yaw` (and `pitch`) — worked out from where the screen
	# really is in the model, not nudged by hand
	var h: Dictionary = def.get("aim", {})
	if h.has("solve") and def.has("display"):
		var c = _display_centre(group, def.display.material)
		if c != null:
			var sv: Dictionary = h.solve
			var rabs := Vector3(float(sv.get("pitch", 0.0)), float(sv.get("yaw", PI)), 0.0)
			var b := Basis.from_euler(rabs)
			var pabs: Vector3 = Vector3(0, 0, -float(sv.dist)) - b * (c as Vector3)
			out["aim"] = {"pos": [pabs.x - VIEW.pos[0], pabs.y - VIEW.pos[1], pabs.z - VIEW.pos[2]],
				"rot": [rabs.x - VIEW.pitch, rabs.y - VIEW.yaw, rabs.z - VIEW.roll], "out": 1.0}
	return out

## THE LIGHT A `native` GUN IS SEEN BY (no world light reaches the gun's
## own world): a warm key over the right shoulder, a cool fill from low
## left, shown and hidden with the gun; and once, for the gun's world, a
## soft sky for its ambient and its metal to reflect (the other guns are
## unshaded and do not see it)
func _light_native(group: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-30.0), 0.0)
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 3.2
	group.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(25.0), deg_to_rad(150.0), 0.0)
	fill.light_color = Color(0.62, 0.74, 1.0)
	fill.light_energy = 1.2
	group.add_child(fill)
	# and a rim from behind, so the dark metal has an edge against the room
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(200.0), 0.0)
	rim.light_color = Color(0.85, 0.92, 1.0)
	rim.light_energy = 1.6
	group.add_child(rim)
	var w := get_viewport().world_3d if is_inside_tree() else null
	if w != null and w.environment == null:
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.55, 0.62, 0.72)
		sm.sky_horizon_color = Color(0.75, 0.72, 0.66)
		sm.ground_bottom_color = Color(0.18, 0.15, 0.12)
		sm.ground_horizon_color = Color(0.5, 0.45, 0.4)
		sky.sky_material = sm
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.4
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		w.environment = env

## THE MUZZLE, in the group's space: the far end of the barrels (the
## spinning set, where a gun has one) or of the whole gun, at the middle
## of its cross-section — where a round is seen to leave (muzzle_uv)
func _tip(group: Node3D, spinner: Node3D) -> Vector3:
	var box := AABB()
	if spinner != null:
		var xf := Transform3D()
		var n: Node = spinner.get_parent()
		while n != null and n != group:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		box = _aabb(spinner, xf)
	if box.size == Vector3.ZERO:
		box = _aabb(group.get_child(0), Transform3D())
	var c := box.get_center()
	return Vector3(c.x, c.y, box.position.z)

## Where the muzzle of the gun in hand is on the picture, 0..1 each way
## (or (-1, -1) with none in hand): the world casts its rounds' streaks
## back out through the same spot (Game.muzzle_view)
func muzzle_uv() -> Vector2:
	if not guns.has(current) or camera == null:
		return Vector2(-1, -1)
	var G: Dictionary = guns[current]
	var g: Node3D = G.group
	var at: Vector3 = global_transform * (g.transform * (G.tip as Vector3))
	if camera.is_position_behind(at):
		return Vector2(-1, -1)
	var vs := Vector2(get_viewport().get_visible_rect().size)
	return camera.unproject_position(at) / vs

## The middle of a gun's screen (the surface wearing `mat`), in its
## group's space.
func _display_centre(group: Node3D, mat: String):
	var found = [null]
	var walk := func(n: Node, xf: Transform3D, self_ref: Callable) -> void:
		var t := xf
		if n is Node3D and n != group:
			t = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				if src != null and src.resource_name == mat:
					var v: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
					var lo := Vector3(INF, INF, INF)
					var hi := -lo
					for q in v:
						lo = lo.min(q)
						hi = hi.max(q)
					found[0] = t * ((lo + hi) / 2.0)
		for ch in n.get_children():
			self_ref.call(ch, t, self_ref)
	walk.call(group, Transform3D(), walk)
	return found[0]

## every surface into the gun shader, keeping its own picture — except a
## gun's SCREEN and LENS, which its scope dresses: the file paints them
## flat because in the original they are a screen never switched on and a
## lens never lit
func _dress(n: Node, def: Dictionary, mats: Array, scope = null) -> void:
	if n is MeshInstance3D and def.has("matcap"):
		# A GUN UNDER A MATCAP (`matcap`): every surface's own colour and
		# normal map, lit by the picture of a lit ball (gun_matcap.gdshader)
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			var m := ShaderMaterial.new()
			m.shader = preload("res://godot/shaders/gun_matcap.gdshader")
			m.set_shader_parameter("matcap_tex", load(def.matcap))
			m.set_shader_parameter("tint", U.col(Vector3(def.tint[0], def.tint[1], def.tint[2])))
			if src is BaseMaterial3D:
				var bm: BaseMaterial3D = src
				if bm.albedo_texture != null:
					m.set_shader_parameter("map", bm.albedo_texture)
				if bm.normal_enabled and bm.normal_texture != null:
					m.set_shader_parameter("normal_map", bm.normal_texture)
					m.set_shader_parameter("has_normal", true)
			mi.set_surface_override_material(i, m)
			mats.append(m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n is MeshInstance3D and def.get("native", false):
		# A GUN IN ITS OWN SHADING (`native`): the file's materials as they
		# are — colour, normal map, metal and roughness — lit (_light_native)
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			var nm: String = src.resource_name if src != null else ""
			if scope != null and def.has("display") and nm == def.display.material:
				mi.set_surface_override_material(i, scope.screen_material())
				if def.get("mirror", false):
					scope.screen_material().set_shader_parameter("flip_x", U.col(true))
				# THE PICTURE IS LAID ACROSS THE PANEL'S OWN BOX, measured off
				# the geometry the file shipped: the mesh is planar, so x and
				# y across it ARE the screen's two axes
				var v: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				var lo := Vector2(INF, INF)
				var hi := Vector2(-INF, -INF)
				for q in v:
					lo = lo.min(Vector2(q.x, q.y))
					hi = hi.max(Vector2(q.x, q.y))
				if v.size() > 0:
					scope.set_panel_box(lo, hi - lo)
				continue
			# a GLASS part is glass: slightly rough and refractive, the
			# potatoes bent through the hopper (gun_glass.gdshader)
			if def.has("glass") and nm == def.glass:
				var gm := ShaderMaterial.new()
				gm.shader = preload("res://godot/shaders/gun_glass.gdshader")
				gm.render_priority = 1
				if def.has("glass_body"):
					var gb: Array = def.glass_body
					gm.set_shader_parameter("body", Vector3(gb[0], gb[1], gb[2]))
				# (a light behind it shining through: gun_glass.gdshader `clear`, `bloom`)
				gm.set_shader_parameter("clear", float(def.get("glass_clear", 0.0)))
				gm.set_shader_parameter("bloom", float(def.get("glass_bloom", 0.0)))
				var gi: Array = def.get("glass_inner", [0.0, 0.0, 0.0])
				gm.set_shader_parameter("inner", Vector3(gi[0], gi[1], gi[2]))
				mi.set_surface_override_material(i, gm)
				continue
			if def.has("rainbow") and nm == def.rainbow:
				var rm := ShaderMaterial.new()
				rm.shader = preload("res://godot/shaders/rainbow_screen.gdshader")
				if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
					rm.set_shader_parameter("map", U.col((src as BaseMaterial3D).albedo_texture))
					rm.set_shader_parameter("has_map", U.col(true))
				mi.set_surface_override_material(i, rm)
				continue
			if scope != null and def.has("optics") and nm == def.optics.material:
				mi.set_surface_override_material(i, scope.optics_material(def.optics.get("base", [0.34, 0.80, 0.0])))
				continue
			var m := ShaderMaterial.new()
			m.shader = preload("res://godot/shaders/gun.gdshader")
			var t := Vector3(def.tint[0], def.tint[1], def.tint[2])
			m.set_shader_parameter("tint", U.col(t))
			if src is BaseMaterial3D:
				var bm: BaseMaterial3D = src
				m.set_shader_parameter("has_map", U.col(bm.albedo_texture != null))
				if bm.albedo_texture:
					m.set_shader_parameter("map", U.col(bm.albedo_texture))
				m.set_shader_parameter("base", U.col(bm.albedo_color))

				if def.has("heat") and bm.resource_name == def.heat:
					m.set_shader_parameter("heats", U.col(true))
				# A GUN IN ITS OWN COLOURS ("pbr": chrome, gold, red lacquer,
				# the shamrock decal) is still unlit, like everything: its
				# metal gets a made-up sky to shine in (gun.gdshader `metal`),
				# not a light
				if def.get("pbr", false):
					m.set_shader_parameter("metal", U.col(bm.metallic))
				# A PART THAT GLOWS (`emit`): its own light, whatever the
				# room's, and more of it while the gun goes off
				if def.has("emit") and bm.resource_name == def.emit.material:
					var ec: Array = def.emit.color
					m.set_shader_parameter("emit", U.col(Vector3(ec[0], ec[1], ec[2])))
			mi.set_surface_override_material(i, m)
			mats.append(m)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_dress(c, def, mats, scope)

func _find_spinner(n: Node) -> Node3D:
	if n is Node3D and (n.name.to_lower().contains("barrel") or n.name.to_lower().contains("rotat") or n.name.to_lower().contains("spin")):
		return n
	for c in n.get_children():
		var f := _find_spinner(c)
		if f:
			return f
	return null

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var b: AABB = t * (n as MeshInstance3D).get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _aabb(c, t)
		if cb.size == Vector3.ZERO:
			continue
		out = cb if first else out.merge(cb)
		first = false
	return out

## EVERY GUN LOADED AT THE LEVEL'S START (Game.start_map), hidden, so a
## swap never stops to read a model off the disk: once the scopes are
## handed out (they dress the guns with screens). Main's warm-up then
## draws them all once, under the loading screen (Warmup).
func preload_all() -> void:
	for n in GUNS:
		if not guns.has(n):
			guns[n] = _load(n)

func set_weapon(name: String) -> void:
	if name == current:
		return
	if guns.has(current):
		guns[current].group.visible = false
	current = name
	if not GUNS.has(name):
		return
	if not guns.has(name):
		guns[name] = _load(name)
	guns[name].group.visible = true

func update_for(p: Player, firing: bool, dt: float, light: float) -> void:
	set_weapon(p.weapon)
	if not guns.has(current):
		return
	var G: Dictionary = guns[current]
	var g: Node3D = G.group
	var def: Dictionary = G.def
	g.visible = not p.dead
	var bob_x := cos(p.bob_phase) * p.bob * 0.0032
	var bob_y := absf(sin(p.bob_phase)) * p.bob * 0.0026
	var k := 1.0 - pow(0.001, dt)
	sway.x += (clampf(-p.look_rate * 2.4, -0.12, 0.12) - sway.x) * k
	sway.y += (clampf(p.pitch_rate * 1.4, -0.08, 0.08) - sway.y) * k
	kick += ((1.0 if firing else 0.0) - kick) * (0.35 if firing else 0.12)
	var jx := (randf() - 0.5) * 0.006 if firing else 0.0
	var jy := (randf() - 0.5) * 0.005 if firing else 0.0
	# THE GUN IS RAISED, OR IT IS NOT, OR IT IS SOMEWHERE BETWEEN: its
	# scope says where it should be and this chases it, over about a third
	# of a second rather than a cut. A gun with no second hold never
	# leaves zero and none of the blending below does anything.
	var sc = scopes.get(current)
	var want: float = sc.aim() if def.has("aim") and sc != null else 0.0
	aim += (want - aim) * (1.0 - pow(0.0015, dt))
	var a := aim if def.has("aim") else 0.0
	var hold: Dictionary = G.get("aim", def.get("aim", {}))
	var off: Array = def.get("pos", [0, 0, 0])
	var aoff: Array = hold.get("pos", off)
	var rot: Array = def.get("rot", [0, 0, 0])
	var arot: Array = hold.get("rot", rot)
	var out: float = lerpf(float(def.out), float(hold.get("out", def.out)), a)
	# AND THE BOB AND THE SWAY GO AWAY WITH IT: what the hip hold reads
	# as life, the aimed one reads as a shake you cannot sight through
	var steady := 1.0 - a * 0.88
	g.position = Vector3(VIEW.pos[0] + lerpf(off[0], aoff[0], a) + (bob_x + jx) * steady,
		VIEW.pos[1] + lerpf(off[1], aoff[1], a) - bob_y * steady + jy * steady,
		(VIEW.pos[2] + lerpf(off[2], aoff[2], a) + kick * 0.025) * out)
	g.rotation = Vector3(VIEW.pitch + lerpf(rot[0], arot[0], a) + sway.y * steady,
		VIEW.yaw + lerpf(rot[1], arot[1], a) + sway.x * steady,
		VIEW.roll + lerpf(rot[2], arot[2], a) + sway.x * 0.4 * steady)
	if G.spinner != null:
		spin_angle += p.spin * def.spin * TAU * dt
		G.spinner.rotation.z = spin_angle
	if G.has("orb"):
		_orb_tic(G.orb, p, dt)
	for m in G.mats:
		m.set_shader_parameter("dim", U.col(light))
		m.set_shader_parameter("glow", U.col(kick))
		m.set_shader_parameter("heat", U.col(p.heat))

# ---------------------------------------------------------------------
# THE ARC MAW'S CHARGE (js/weapon3d.js makeOrb, orbTic): while the
# trigger is held the ball grows from a spark to its full size with the
# charge and breathes, its halo swells and brightens, and motes are born
# on a shell round the prongs and drawn in, faster the nearer they get —
# more of them the higher the charge. Let go, and a flash spreads from
# the maw and fades.
# ---------------------------------------------------------------------

static var _orb_mesh: QuadMesh

func _orb_sprite(parent: Node3D, c: Color) -> MeshInstance3D:
	if _orb_mesh == null:
		_orb_mesh = QuadMesh.new()
		_orb_mesh.size = Vector2(1, 1)
	# a material each: its tint is its own (see orb.gdshader)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/orb.gdshader")
	mat.render_priority = 6
	mat.set_shader_parameter("tint", U.col(c))
	var m := MeshInstance3D.new()
	m.mesh = _orb_mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 4.0
	m.visible = false
	m.set_meta("colour", c)
	parent.add_child(m)
	return m

func _make_orb(inner: Node3D, at: Vector3, def: Dictionary) -> Dictionary:
	var g := Node3D.new()
	g.name = "Orb"
	g.position = at
	inner.add_child(g)
	var o := {"def": def, "group": g, "halo": _orb_sprite(g, Color("#3f7dff")), "core": _orb_sprite(g, Color("#dff0ff")),
		"flash": _orb_sprite(g, Color("#8fc0ff")), "motes": [], "flash_t": 0.0, "was": 0.0, "spawn": 0.0, "t": 0.0}
	for i in int(def.motes):
		o.motes.append({"s": _orb_sprite(g, Color("#5a9cff") if i % 3 else Color("#cfe6ff")), "p": Vector3(), "age": 0.0, "life": 0.0, "live": false})
	return o

static func _fade(m: MeshInstance3D, a: float) -> void:
	var c: Color = m.get_meta("colour")
	(m.material_override as ShaderMaterial).set_shader_parameter("tint", U.col(Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))))

func _orb_tic(o: Dictionary, p, dt: float) -> void:
	var c: float = p.arc_charge if p.arc_charging else 0.0
	var R: float = o.def.radius
	var reach: float = o.def.reach
	o.t += dt
	var tics: float = o.t * 35.0
	# the discharge: the charge went to nothing
	if o.was > 0.02 and c == 0.0:
		o.flash_t = 1.0
	o.was = c
	var breathe := 1.0 + 0.12 * sin(tics * 0.9) + 0.06 * sin(tics * 2.3)
	var r := R * (0.12 + 0.88 * sqrt(c)) * breathe if c > 0.0 else 0.0
	var core: MeshInstance3D = o.core
	var halo: MeshInstance3D = o.halo
	var flash: MeshInstance3D = o.flash
	core.visible = r > 0.0
	halo.visible = r > 0.0
	core.scale = Vector3.ONE * r * 1.2
	halo.scale = Vector3.ONE * r * (3.4 + 0.6 * sin(tics * 0.4))
	_fade(halo, 0.45 + 0.45 * c)
	o.flash_t = maxf(0.0, o.flash_t - dt * 5.0)
	flash.visible = o.flash_t > 0.0
	flash.scale = Vector3.ONE * R * (2.0 + 9.0 * (1.0 - o.flash_t))
	_fade(flash, o.flash_t)
	# the motes: born on a shell round the maw, drawn in, faster near it
	o.spawn += dt * (18.0 + 90.0 * c) if c > 0.0 else 0.0
	for m in o.motes:
		var s: MeshInstance3D = m.s
		if not m.live:
			if o.spawn < 1.0:
				s.visible = false
				continue
			o.spawn -= 1.0
			var u := randf() * 2.0 - 1.0
			var a := randf() * TAU
			var rr := reach * (0.55 + 0.45 * randf()) * (0.7 + 0.5 * c)
			var q := sqrt(1.0 - u * u)
			# toward the eye is +z in here (the gun is turned round)
			m.p = Vector3(cos(a) * q * rr, sin(a) * q * rr, u * rr * 0.6 + rr * 0.25)
			m.age = 0.0
			m.life = 0.35 + randf() * 0.3
			m.live = true
		m.age += dt
		var k := minf(1.0, dt * (3.0 + 9.0 * m.age / m.life))
		m.p -= m.p * k
		var d: float = m.p.length()
		if m.age >= m.life or d < r * 0.5 or c == 0.0:
			m.live = false
			s.visible = false
			continue
		s.visible = true
		s.position = m.p
		s.scale = Vector3.ONE * R * (0.22 + 0.25 * minf(1.0, d / reach))
		_fade(s, minf(1.0, m.age / 0.08))
