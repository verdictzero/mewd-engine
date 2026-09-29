## MEWD — particles: one draw of little billboards (js/particles.js).
##
## The flame out of the gun, the embers off a burning aisle and the
## smoke over the forest are the same thing drawn three ways: small
## quads facing the eye, moving, growing, changing colour, dying. One
## class; each effect an instance with its own blending. Struct of
## arrays and a free list, so nothing is allocated after start-up
## however long the place burns; one MultiMesh, refilled each frame.
## Positions are map space (x, y, z up).
class_name Particles
extends MultiMeshInstance3D

var max := 0
var count := 0
var alive := PackedByteArray()
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var pz := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var vz := PackedFloat32Array()
var age := PackedFloat32Array()
var life := PackedFloat32Array()
var size0 := PackedFloat32Array()
var size1 := PackedFloat32Array()
var c0 := PackedColorArray()
var c1 := PackedColorArray()
var frame := PackedFloat32Array()
var frame_rate := PackedFloat32Array()
var drag := PackedFloat32Array()
var gravity := PackedFloat32Array()
var free := PackedInt32Array()
## the indices alive, in no order (tic drops the dead from it)
var live := PackedInt32Array()
var frames := 8
var mat: ShaderMaterial
var _buf := PackedFloat32Array()

## opts: max, blend ("add" | "mix"), frames, near_shrink, fullbright, soft, map
func _init(opts: Dictionary) -> void:
	max = opts.get("max", 256)
	frames = opts.get("frames", 8)
	for arr in [px, py, pz, vx, vy, vz, age, life, size0, size1, frame, frame_rate, drag, gravity]:
		arr.resize(max)
	alive.resize(max)
	c0.resize(max)
	c1.resize(max)
	for i in max:
		free.append(max - 1 - i)
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	var code: String = preload("res://godot/shaders/particle.gdshader").code
	if opts.get("blend", "add") == "add":
		code = code.replace("render_mode unshaded,", "render_mode unshaded, blend_add,")
	sh.code = code
	mat.shader = sh
	mat.set_shader_parameter("frames", float(frames))
	mat.set_shader_parameter("near_shrink", float(opts.get("near_shrink", 0.0)))
	mat.set_shader_parameter("fullbright", 1.0 if opts.get("fullbright", true) else 0.0)
	mat.set_shader_parameter("soft", 1.0 if opts.get("soft", false) else 0.0)
	if opts.has("map"):
		mat.set_shader_parameter("map", opts.map)
		mat.set_shader_parameter("has_map", true)
	var quad := QuadMesh.new()
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = max
	multimesh.visible_instance_count = 0
	_buf.resize(max * 20)
	custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_offset = float(opts.get("order", 0))

## o: x y z, vx vy vz, age, life, size0 size1, c0 c1 (Color with alpha), frame, frameRate, drag, gravity
func spawn(o: Dictionary) -> int:
	if free.is_empty():
		return -1
	var i := free[free.size() - 1]
	free.resize(free.size() - 1)
	alive[i] = 1
	count += 1
	live.append(i)
	px[i] = o.x; py[i] = o.y; pz[i] = o.z
	vx[i] = o.get("vx", 0.0); vy[i] = o.get("vy", 0.0); vz[i] = o.get("vz", 0.0)
	age[i] = o.get("age", 0.0)
	life[i] = maxf(1.0, o.get("life", 30.0))
	size0[i] = o.get("size0", o.get("size", 8.0))
	size1[i] = o.get("size1", size0[i])
	c0[i] = o.get("c0", Color.WHITE)
	c1[i] = o.get("c1", c0[i])
	frame[i] = o.get("frame", 0.0)
	frame_rate[i] = o.get("frameRate", 0.0)
	drag[i] = o.get("drag", 1.0)
	gravity[i] = o.get("gravity", 0.0)
	return i

func kill(i: int) -> void:
	if not alive[i]:
		return
	alive[i] = 0
	count -= 1
	free.append(i)

## One tic. `collide(i, nx, ny, nz) -> bool` is asked before a particle
## moves; true kills it where it is.
func tic(collide: Callable = Callable()) -> void:
	var keep := PackedInt32Array()
	var has_collide := collide.is_valid()
	for i in live:
		if not alive[i]:
			continue
		age[i] += 1.0
		if age[i] >= life[i]:
			kill(i)
			continue
		vz[i] += gravity[i]
		var d := drag[i]
		if d != 1.0:
			vx[i] *= d; vy[i] *= d; vz[i] *= d
		var nx := px[i] + vx[i]
		var ny := py[i] + vy[i]
		var nz := pz[i] + vz[i]
		if has_collide and collide.call(i, nx, ny, nz):
			kill(i)
			continue
		px[i] = nx; py[i] = ny; pz[i] = nz
		keep.append(i)
	live = keep

func draw() -> void:
	if count == 0 and multimesh.visible_instance_count == 0:
		return
	var n := 0
	for i in live:
		if not alive[i]:
			continue
		var t := age[i] / life[i]
		var o := n * 20
		_buf[o] = 1.0; _buf[o + 1] = 0.0; _buf[o + 2] = 0.0; _buf[o + 3] = px[i]
		_buf[o + 4] = 0.0; _buf[o + 5] = 1.0; _buf[o + 6] = 0.0; _buf[o + 7] = pz[i]
		_buf[o + 8] = 0.0; _buf[o + 9] = 0.0; _buf[o + 10] = 1.0; _buf[o + 11] = -py[i]
		var c := c0[i].lerp(c1[i], t)
		_buf[o + 12] = c.r; _buf[o + 13] = c.g; _buf[o + 14] = c.b; _buf[o + 15] = c.a
		_buf[o + 16] = size0[i] + (size1[i] - size0[i]) * t
		_buf[o + 17] = float(int(frame[i] + age[i] * frame_rate[i]) % frames)
		_buf[o + 18] = 0.0; _buf[o + 19] = 0.0
		n += 1
	multimesh.buffer = _buf
	multimesh.visible_instance_count = n
