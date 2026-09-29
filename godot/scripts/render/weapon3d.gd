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
	"BORE": {"url": "bore.glb", "fit": GUN_LENGTH * 0.67, "out": 1.33, "tint": [1.6, 0.30, 0.22]},
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
		"display": {"material": "dynamicDisplaySurfaceMat"}, "glass": "Glass", "pbr": true, "mirror": true,
		# mirrored left to right (the file has the sight on the other side),
		# and pointed as every other gun is: muzzle at the file's +Z, the
		# sight's screen facing -Z, back at the eye (its normals say so) —
		# straight down the view; raised, the screen is straight ahead a
		# hand's breadth off
		"aim": {"solve": {"dist": 0.16, "yaw": 6.28318, "pitch": 0.0}}},
	"ARC": {"url": "arcgun.glb", "fit": GUN_LENGTH * 1.05, "out": 1.7, "pos": [0.02, 0.12, 0], "rot": [0, 0.06, 0], "tint": [0.7, 0.95, 1.9]},
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
	if def.has("spin"):
		spinner = _find_spinner(root)
	var out := {"group": group, "mats": mats, "def": def, "spinner": spinner, "tip": _tip(group, spinner)}
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
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			var nm: String = src.resource_name if src != null else ""
			if scope != null and def.has("display") and nm == def.display.material:
				mi.set_surface_override_material(i, scope.screen_material())
				if def.get("mirror", false):
					scope.screen_material().set_shader_parameter("flip_x", true)
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
				mi.set_surface_override_material(i, gm)
				continue
			if def.has("rainbow") and nm == def.rainbow:
				var rm := ShaderMaterial.new()
				rm.shader = preload("res://godot/shaders/rainbow_screen.gdshader")
				if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
					rm.set_shader_parameter("map", (src as BaseMaterial3D).albedo_texture)
					rm.set_shader_parameter("has_map", true)
				mi.set_surface_override_material(i, rm)
				continue
			if scope != null and def.has("optics") and nm == def.optics.material:
				mi.set_surface_override_material(i, scope.optics_material(def.optics.get("base", [0.34, 0.80, 0.0])))
				continue
			var m := ShaderMaterial.new()
			m.shader = preload("res://godot/shaders/gun.gdshader")
			var t := Vector3(def.tint[0], def.tint[1], def.tint[2])
			m.set_shader_parameter("tint", t)
			if src is BaseMaterial3D:
				var bm: BaseMaterial3D = src
				m.set_shader_parameter("has_map", bm.albedo_texture != null)
				if bm.albedo_texture:
					m.set_shader_parameter("map", bm.albedo_texture)
				m.set_shader_parameter("base", bm.albedo_color)

				if def.has("heat") and bm.resource_name == def.heat:
					m.set_shader_parameter("heats", true)
				# A GUN IN ITS OWN COLOURS ("pbr": chrome, gold, red lacquer,
				# the shamrock decal) is still unlit, like everything: its
				# metal gets a made-up sky to shine in (gun.gdshader `metal`),
				# not a light
				if def.get("pbr", false):
					m.set_shader_parameter("metal", bm.metallic)
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
	for m in G.mats:
		m.set_shader_parameter("dim", light)
		m.set_shader_parameter("glow", kick)
		m.set_shader_parameter("heat", p.heat)
