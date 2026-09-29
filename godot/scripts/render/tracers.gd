## MEWD — tracers (js/tracers.js).
##
## A round is a hitscan — it has arrived before the tic is over — so a
## tracer is not the round, it is a streak of light drawn along the line
## the round took, from the muzzle to wherever it stopped, moving fast
## enough to read as flight. VERY LONG, at the user's request: 420 units.
## The tail is held at the muzzle until the head has flown a whole
## length, so the streak grows out of the barrel; once the head has
## arrived the tail keeps flying and the streak shrinks into the hit.
## Each is a quad facing the eye along its length, additive, its own
## light — one ImmediateMesh for the lot, rebuilt each frame.
class_name Tracers
extends MeshInstance3D

const MAX_TRACERS := 128
const SPEED := 150.0       # units a tic
const LENGTH := 420.0
const WIDTH := 2.6
const NEAR_EYE := 44.0

var list := []
var im := ImmediateMesh.new()

func _ready() -> void:
	mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))

## from, to: map space (x, y, z)
func spawn(from: Vector3, to: Vector3) -> void:
	var d := from.distance_to(to)
	if d < NEAR_EYE:
		return
	if list.size() >= MAX_TRACERS:
		list.pop_front()
	list.append({"a": U.v3(from.x, from.y, from.z), "b": U.v3(to.x, to.y, to.z), "len": d, "trav": 0.0})

func tic() -> void:
	for t in list:
		t.trav += SPEED
	list = list.filter(func(t): return t.trav - LENGTH < t.len)

func draw_for(cam: Camera3D, f: float) -> void:
	im.clear_surfaces()
	if list.is_empty():
		return
	var eye := cam.global_position
	var begun := false
	for t in list:
		var trav: float = t.trav + SPEED * f
		var head := minf(trav, t.len)
		var tail := maxf(0.0, trav - LENGTH)
		if head <= tail or t.len <= 0.0:
			continue
		# (begun on the first streak that draws: an empty surface is an error)
		if not begun:
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		var dir: Vector3 = (t.b - t.a) / t.len
		var h: Vector3 = t.a + dir * head
		var tl: Vector3 = t.a + dir * tail
		var side := dir.cross(eye - h).normalized() * WIDTH * 0.5
		var hot := Color(1.0, 0.92, 0.6, 1.0)
		var cold := Color(1.0, 0.5, 0.1, 0.0)
		im.surface_set_color(cold); im.surface_add_vertex(tl - side)
		im.surface_set_color(hot); im.surface_add_vertex(h - side)
		im.surface_set_color(hot); im.surface_add_vertex(h + side)
		im.surface_set_color(cold); im.surface_add_vertex(tl - side)
		im.surface_set_color(hot); im.surface_add_vertex(h + side)
		im.surface_set_color(cold); im.surface_add_vertex(tl + side)
	if begun:
		im.surface_end()
