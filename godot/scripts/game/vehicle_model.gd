## MEWD — the vehicles, which are a file (js/car.js).
##
## A GLB, loaded as it stands and drawn as it is authored: its own nodes,
## its own triangles, its own UVs, its own texture. Godot's importer has
## already turned the file into a scene; this walks that scene, measures
## it, and works out what the file does not say:
##
##   HOW LONG A VAN IS IN GAME UNITS. A GLB has no scale the game can
##   use, and everything else in this world is measured against Doom's
##   ruler, so the length is a fact about the GAME (VAN_LENGTH and the
##   rest below) and the model is scaled to it.
##
##   WHICH WAY IT POINTS. glTF says +Y is up and the front of an asset
##   faces +Z, so the nose is +Z and the left flank is +X. The one thing
##   checked rather than assumed is that the model is longest along +Z.
##
## THE GAME'S OWN MODEL SPACE is x forward (+0.5 at the nose, -0.5 at the
## tail), y to the left, z up off the tarmac, in fractions of the length
## — so `length` sets the scale and a chunk can be cut with a box written
## in sixteenths of a van. `gl` takes the file's coordinates there; and
## `to_mesh` takes model space into a vehicle node's own frame, which is
## the renderer's (Y up, Z running back) about whichever point it turns
## about. A vehicle node is yawed, then rolled about its length, then
## tipped nose over tail — Godot's default Euler order, YXZ, which is
## three.js's 'YXZ' and the order js/vehicles.js integrates its tumble in.
##
## THE PARTS THAT MOVE ON THEIR OWN are nodes of their own and stay so:
## a node called wheel_* turns about its axle, a node called `cannon` is
## the fire truck's water cannon (turning about the top of cannon_base),
## and a surface on the DynamicPoliceLight* material is the light bar,
## which flashes (see vehicle_lamp.gdshader).
##
## WHAT IS NOT PORTED is the slab: the web build bakes every parked car
## into one geometry for one draw call. Here every vehicle is a node of
## its own — Godot batches a car park of one mesh without being asked —
## so there is no rebuild and nothing moves between a slab and a mesh.
class_name VehicleModel
extends RefCounted

## HOW LONG A VAN IS, in the game's units: the drawn fleet had its van at
## 174 nose to tail and every other length in the world is beside it
const VAN_LENGTH := 174.0
## AND THE POLICE VAN, a third again longer than a panel van, the way a
## BearCat is beside a Transit — a bit bigger at the user's request:
## 240 by 97 by 100
const POLICE_LENGTH := 240.0
## the army's APC: a little longer than the assault van and a third again
## as wide, 133 across in a fire lane 160 deep
const APC_LENGTH := 260.0
## and the fire truck, the police van's own body repainted
const FIRE_LENGTH := POLICE_LENGTH

## Doom's things are CYLINDERS, so a van is three of them in a row
const CAR_BLOCK_AT := [-0.31, 0.0, 0.31]

## which colours a light bar flashes, by who is coming (js/bloom.js
## LAMP_COLOURS): the police red and blue, the fire brigade red and white
const LAMP_COLOURS := {
	"police": {"left": Vector3(1.0, 0.06, 0.04), "right": Vector3(0.10, 0.25, 1.0)},
	"fire": {"left": Vector3(1.0, 0.08, 0.04), "right": Vector3(1.0, 0.95, 0.85)},
}

const VEHICLE_SHADER := preload("res://godot/shaders/vehicle.gdshader")
const LAMP_SHADER := preload("res://godot/shaders/vehicle_lamp.gdshader")

var id := "van"
var name := "Van"
var use := "civil"
var lamp := "police"
var length := VAN_LENGTH
## the box, in fractions of the length: half the width, and the height
var half := 0.2
var height := 0.4
## glTF's coordinates -> model space
var gl := Transform3D()
## every node that is drawn: {mesh, xf (the node's place in the file's
## scene), role ("body", "wheel", "cannon", "lamp"), name, mats (one
## template ShaderMaterial a surface)}
var parts: Array = []
## the wheels: {part, axle (model space), radius (model units)}
var wheels: Array = []
## the water cannon, if it has one: {part, pivot, tip} in model space
var cannon := {}
## the light bar, already in model space: triangles and the bar's middle
var lamp_pos := PackedVector3Array()
var lamp_mid := 0.0
## every triangle of the body, in model space, for the pieces: three
## positions a triangle, three UVs, and one ink colour (a = 1: that is
## its colour; a = 0: it has a picture)
var tri_pos := PackedVector3Array()
var tri_uv := PackedVector2Array()
var tri_ink := PackedColorArray()
## the sheet the body is painted with
var texture: Texture2D = null

## How big it is, in game units.
func width() -> float:
	return length * half * 2.0

func car_height() -> float:
	return length * height

func block_radius() -> float:
	return maxf(12.0, roundf(width() / 2.0))

## The three cylinders' middles, for a vehicle at (x, y) facing `angle`.
func blockers(x: float, y: float, angle: float) -> Array:
	var c := cos(angle)
	var s := sin(angle)
	var out := []
	for t in CAR_BLOCK_AT:
		out.append(Vector2(x + c * t * length, y + s * t * length))
	return out

## The eight corners of its own box, in model units — what the tumble
## asks to find out how high a car on its roof sits.
func corners() -> Array:
	var out := []
	for x in [-0.5, 0.5]:
		for y in [-half, half]:
			for z in [0.0, height]:
				out.append(Vector3(x, y, z))
	return out

## Model space into a vehicle node's own frame, about `origin` (model).
func to_mesh(p: Vector3, origin: Vector3) -> Vector3:
	return Vector3((p.x - origin.x) * length, (p.z - origin.z) * length, -(p.y - origin.y) * length)

## The same, as a transform.
func mesh_xf(origin: Vector3) -> Transform3D:
	var b := Basis(Vector3(length, 0, 0), Vector3(0, 0, -length), Vector3(0, length, 0))
	return Transform3D(b, -(b * origin))

# ------------------------------------------------------------------
# THE MODEL, AS IT ARRIVES
# ------------------------------------------------------------------

static var _cache := {}

## One vehicle definition out of a GLB. opts: length, id, name, use,
## lamp. Null if the file is not there — a force with no vehicle simply
## does not come, the same bargain every other asset in this game makes.
static func load_glb(path: String, opts := {}) -> VehicleModel:
	var key := path + str(opts.get("length", VAN_LENGTH))
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(path):
		push_warning("no vehicle model at " + path)
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var m := VehicleModel.new()
	m.length = float(opts.get("length", VAN_LENGTH))
	m.id = str(opts.get("id", "van"))
	m.name = str(opts.get("name", "Van"))
	m.use = str(opts.get("use", "civil"))
	m.lamp = str(opts.get("lamp", "police"))
	m._build(root)
	root.free()
	_cache[key] = m
	return m

static func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"node": n, "mesh": (n as MeshInstance3D).mesh, "xf": t, "name": String(n.name)})
	for c in n.get_children():
		_walk(c, t, out)

func _build(root: Node) -> void:
	var found := []
	_walk(root, Transform3D(), found)
	assert(not found.is_empty(), "the model has no meshes in its scene")
	# ---- how big it is, and therefore the scale
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for f in found:
		var mesh: Mesh = f.mesh
		for si in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(si)
			for v in arr[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = f.xf * v
				lo = lo.min(p)
				hi = hi.max(p)
	var span := hi - lo
	# the nose is glTF +Z, the left flank +X, up is +Y
	assert(span.z > span.x and span.z > span.y, "the model is not longest along +Z, so it is not facing the way glTF says it should")
	var s := 1.0 / span.z
	var mid := (lo + hi) / 2.0
	# model = ((gz - midz) s, (gx - midx) s, (gy - lo.y) s)
	gl = Transform3D(Basis(Vector3(0, s, 0), Vector3(0, 0, s), Vector3(s, 0, 0)), Vector3(-mid.z * s, -mid.x * s, -lo.y * s))
	half = span.x * s / 2.0
	height = span.y * s
	var centre := Vector3(0, 0, height / 2.0)

	var mount_lo := Vector3(INF, INF, INF)
	var mount_hi := Vector3(-INF, -INF, -INF)
	var gun_lo := Vector3(INF, INF, INF)
	var gun_hi := Vector3(-INF, -INF, -INF)
	var gun_pts := PackedVector3Array()
	var lamp_y := 0.0
	var lamp_n := 0
	for f in found:
		var mesh: Mesh = f.mesh
		var nm: String = f.name
		var role := "body"
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			if mat != null and mat.resource_name.to_lower().begins_with("dynamicpolicelight"):
				role = "lamp"
		if role != "lamp":
			if nm.to_lower().begins_with("wheel"):
				role = "wheel"
			elif nm.to_lower() == "cannon":
				role = "cannon"
		var mount := nm.to_lower() == "cannon_base"
		var to_model: Transform3D = gl * f.xf
		var part := {"mesh": mesh, "xf": f.xf, "role": role, "name": nm, "mats": []}
		# this part's middle-of-the-model, in its own coordinates: which
		# way is OUT, for the face light (see vehicle.gdshader)
		var local_centre: Vector3 = to_model.affine_inverse() * centre
		var wlo := Vector3(INF, INF, INF)
		var whi := Vector3(-INF, -INF, -INF)
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si)
			var arr := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var tex: Texture2D = null
			var colour := Color(1, 1, 1, 1)
			if src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
				colour = (src as BaseMaterial3D).albedo_color
			if role == "body" and tex != null and texture == null:
				texture = tex
			if role != "lamp":
				var sm := ShaderMaterial.new()
				sm.shader = VEHICLE_SHADER
				sm.set_shader_parameter("has_map", tex != null)
				if tex != null:
					sm.set_shader_parameter("map", tex)
				sm.set_shader_parameter("base", colour)
				sm.set_shader_parameter("centre", local_centre)
				part.mats.append(sm)
			if idx == null or (idx as PackedInt32Array).is_empty():
				idx = PackedInt32Array(range(verts.size()))
			for k in range(0, (idx as PackedInt32Array).size() - 2, 3):
				var ia: int = idx[k]
				var ib: int = idx[k + 1]
				var ic: int = idx[k + 2]
				var a: Vector3 = to_model * verts[ia]
				var b: Vector3 = to_model * verts[ib]
				var c: Vector3 = to_model * verts[ic]
				if (b - a).cross(c - a).length_squared() < 1e-18:
					continue            # a degenerate triangle is nothing
				match role:
					"lamp":
						lamp_pos.append(a); lamp_pos.append(b); lamp_pos.append(c)
						lamp_y += (a.y + b.y + c.y) / 3.0
						lamp_n += 1
					"wheel":
						for p in [a, b, c]:
							wlo = wlo.min(p)
							whi = whi.max(p)
					"cannon":
						for p in [a, b, c]:
							gun_lo = gun_lo.min(p)
							gun_hi = gun_hi.max(p)
							gun_pts.append(p)
					_:
						tri_pos.append(a); tri_pos.append(b); tri_pos.append(c)
						var has_uv: bool = tex != null and uvs != null and (uvs as PackedVector2Array).size() > ic
						for i in [ia, ib, ic]:
							tri_uv.append(uvs[i] if has_uv else Vector2())
						tri_ink.append(Color(0, 0, 0, 0) if tex != null else Color(colour.r, colour.g, colour.b, 1.0))
						if mount:
							for p in [a, b, c]:
								mount_lo = mount_lo.min(p)
								mount_hi = mount_hi.max(p)
		if role == "lamp":
			continue            # redrawn in model space below, with its side
		parts.append(part)
		if role == "wheel":
			# a wheel's middle is its axle and how far that is off the tarmac
			# is its radius: the box of its own triangles, since a wheel is round
			wheels.append({"part": part, "axle": (wlo + whi) / 2.0, "radius": maxf(whi.x - wlo.x, whi.z - wlo.z) / 2.0})
		elif role == "cannon":
			cannon = {"part": part}
	lamp_mid = lamp_y / maxf(1.0, lamp_n)
	# THE CANNON turns about the middle of the top of its mount, and its
	# muzzle is the furthest forward point of it: the barrel is modelled
	# pointing at the nose
	if not cannon.is_empty():
		var have_mount := mount_lo.x < INF
		var mlo := mount_lo if have_mount else gun_lo
		var mhi := mount_hi if have_mount else gun_hi
		cannon.pivot = Vector3((mlo.x + mhi.x) / 2.0, (mlo.y + mhi.y) / 2.0, mhi.z if have_mount else gun_lo.z)
		var tip := Vector3(gun_hi.x, 0, 0)
		var n := 0
		for p in gun_pts:
			if p.x > gun_hi.x - 0.004:
				tip.y += p.y
				tip.z += p.z
				n += 1
		tip.y /= maxf(1.0, n)
		tip.z /= maxf(1.0, n)
		cannon.tip = tip

# ------------------------------------------------------------------
# DRAWING ONE
# ------------------------------------------------------------------

## One vehicle's node tree, turning about `origin` (model space): the
## body, the wheels each on a pivot at its axle, the cannon on a yaw and
## a pitch, and the light bar. Every material is this vehicle's own copy,
## so its light and its char are its own. Returns {root, mats, wheels:
## [{pivot, radius}], gun: {yaw, pitch} or {}, lamp: MeshInstance3D or null}.
func build(origin: Vector3, phase := 0.0) -> Dictionary:
	var root := Node3D.new()
	root.name = "car:" + id
	var mats := []
	var out := {"root": root, "mats": mats, "wheels": [], "gun": {}, "lamp": null}
	var frame := mesh_xf(origin) * gl
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in part.mats.size():
			var m: ShaderMaterial = part.mats[si].duplicate()
			mi.set_surface_override_material(si, m)
			mats.append(m)
		var xf: Transform3D = frame * part.xf
		if part.role == "wheel":
			var w: Dictionary = {}
			for ww in wheels:
				if ww.part == part:
					w = ww
			var at := to_mesh(w.axle, origin)
			var pivot := Node3D.new()
			pivot.position = at
			mi.transform = Transform3D(Basis(), -at) * xf
			pivot.add_child(mi)
			root.add_child(pivot)
			out.wheels.append({"pivot": pivot, "radius": float(w.radius) * length})
		elif part.role == "cannon":
			# a turret that turns about its mount and inside it the barrel's
			# elevation, both about the pivot, so aiming it is two numbers
			var at := to_mesh(cannon.pivot, origin)
			var yaw := Node3D.new()
			yaw.position = at
			var pitch := Node3D.new()
			yaw.add_child(pitch)
			mi.transform = Transform3D(Basis(), -at) * xf
			pitch.add_child(mi)
			root.add_child(yaw)
			out.gun = {"yaw": yaw, "pitch": pitch}
		else:
			mi.transform = xf
			root.add_child(mi)
	if not lamp_pos.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		var pos := PackedVector3Array()
		var uv := PackedVector2Array()
		for p in lamp_pos:
			pos.append(to_mesh(p, origin))
			uv.append(Vector2(p.y - lamp_mid, 0))
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_TEX_UV] = uv
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var lm := ShaderMaterial.new()
		lm.shader = LAMP_SHADER
		var col: Dictionary = LAMP_COLOURS.get(lamp, LAMP_COLOURS.police)
		lm.set_shader_parameter("left_lens", col.left)
		lm.set_shader_parameter("right_lens", col.right)
		lm.set_shader_parameter("phase", phase)
		var li := MeshInstance3D.new()
		li.mesh = am
		li.material_override = lm
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		li.name = "lightbar"
		root.add_child(li)
		out.lamp = li
	return out

# ------------------------------------------------------------------
# CLIPPED TO A BOX — one torn-off piece (chunkGeometry)
# ------------------------------------------------------------------

## Sutherland-Hodgman against six planes, carrying the UVs along: a
## polygon crossing a plane gains a vertex on it, its u and v
## interpolated the same way its position is.
static func _clip(poly: Array, lo: Vector3, hi: Vector3) -> Array:
	for axis in 3:
		for sign in [1.0, -1.0]:
			if poly.size() < 3:
				return []
			var limit: float = lo[axis] if sign > 0.0 else hi[axis]
			var out := []
			for i in poly.size():
				var a: Array = poly[i]
				var b: Array = poly[(i + 1) % poly.size()]
				var da: float = sign * ((a[0] as Vector3)[axis] - limit)
				var db: float = sign * ((b[0] as Vector3)[axis] - limit)
				if da >= 0.0:
					out.append(a)
				if (da >= 0.0) != (db >= 0.0):
					var f := da / (da - db)
					out.append([(a[0] as Vector3).lerp(b[0], f), (a[1] as Vector2).lerp(b[1], f)])
			poly = out
	return poly

## The model's own surface inside a box of its own model space (lo..hi),
## clipped to it and turned about its middle, as a mesh in the renderer's
## frame. If a cut catches nothing the nearest triangle goes in whole: an
## empty chunk is an invisible thing, which is worse than a wrong one.
func chunk_mesh(lo: Vector3, hi: Vector3) -> ArrayMesh:
	var mid := (lo + hi) / 2.0
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var nrm := PackedVector3Array()
	var ntri := tri_ink.size()
	var emit := func(pa: Vector3, pb: Vector3, pc: Vector3, ta: Vector2, tb: Vector2, tc: Vector2, ink: Color) -> void:
		var n := (pb - pa).cross(pc - pa).normalized()
		# turned outward, away from the model's own middle, for the light
		if n.dot((pa + pb + pc) / 3.0 - Vector3(0, 0, height / 2.0)) < 0.0:
			n = -n
		var nm := Vector3(n.x, n.z, -n.y)
		for q in [[pa, ta], [pb, tb], [pc, tc]]:
			pos.append(to_mesh(q[0], mid))
			uv.append(q[1])
			col.append(ink)
			nrm.append(nm)
	for t in ntri:
		var a := tri_pos[t * 3]
		var b := tri_pos[t * 3 + 1]
		var c := tri_pos[t * 3 + 2]
		# the cheap rejection first: most triangles miss the cut
		var mn := a.min(b).min(c)
		var mx := a.max(b).max(c)
		if mn.x > hi.x or mn.y > hi.y or mn.z > hi.z or mx.x < lo.x or mx.y < lo.y or mx.z < lo.z:
			continue
		var poly := _clip([[a, tri_uv[t * 3]], [b, tri_uv[t * 3 + 1]], [c, tri_uv[t * 3 + 2]]], lo, hi)
		for i in range(1, poly.size() - 1):
			emit.call(poly[0][0], poly[i][0], poly[i + 1][0], poly[0][1], poly[i][1], poly[i + 1][1], tri_ink[t])
	if pos.is_empty():
		var best := -1
		var bd := INF
		for t in ntri:
			var d := ((tri_pos[t * 3] + tri_pos[t * 3 + 1] + tri_pos[t * 3 + 2]) / 3.0 - mid).length_squared()
			if d < bd:
				bd = d
				best = t
		if best >= 0:
			emit.call(tri_pos[best * 3], tri_pos[best * 3 + 1], tri_pos[best * 3 + 2],
				tri_uv[best * 3], tri_uv[best * 3 + 1], tri_uv[best * 3 + 2], tri_ink[best])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_NORMAL] = nrm
	var am := ArrayMesh.new()
	if not pos.is_empty():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## The material a chunk of this model is drawn with.
func chunk_material() -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = VEHICLE_SHADER
	sm.set_shader_parameter("has_map", texture != null)
	if texture != null:
		# decoded to linear, as the web build's fetch is (TexBank.decoded)
		sm.set_shader_parameter("map", TexBank.decoded(texture))
	sm.set_shader_parameter("vertex_ink", true)
	sm.set_shader_parameter("outward", false)   # the normals are already outward
	return sm
