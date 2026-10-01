## MEWD — THE WARM-UP, at the user's request ("make sure all weapons,
## models etc are preloaded at the start of each level so they don't
## lag"): a shader is compiled the first time something is DRAWN with it,
## and a gun, a rocket, a spark or a scope that has not been drawn yet
## would stop the game for a moment the first time it was. So, under the
## loading screen, for its few frames, everything the level has built is
## drawn once:
##
##   every mesh, hidden or not, made visible and never culled (the
##   largest margin there is), wherever it is
##   every pool of particles and instances that is empty given one
##   instance (its buffer is zeros: drawn, and nothing to see)
##   every viewport that only draws when asked (the scopes' feeds and
##   panels) drawing every frame
##
## then each put back exactly as it was. Weapon3D.preload_all has loaded
## every gun by then, so the guns are among them.
class_name Warmup

## Everything under the roots, drawn from now until end(): what was
## changed, to put back.
static func begin(roots: Array) -> Array:
	var st := []
	for r in roots:
		if r != null and is_instance_valid(r):
			_walk(r, st)
	return st

static func _walk(n: Node, st: Array) -> void:
	if n is SubViewport:
		var vp: SubViewport = n
		if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			st.append({"vp": vp, "mode": vp.render_target_update_mode})
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if n is Node3D and not (n as Node3D).visible:
		st.append({"hid": n})
		(n as Node3D).visible = true
	if n is GeometryInstance3D:
		var gi: GeometryInstance3D = n
		st.append({"gi": gi, "margin": gi.extra_cull_margin})
		gi.extra_cull_margin = 16384.0
		if gi is MultiMeshInstance3D:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			if mm != null and mm.instance_count > 0 and mm.visible_instance_count == 0:
				st.append({"mm": mm, "vic": 0})
				mm.visible_instance_count = 1
	for c in n.get_children():
		_walk(c, st)

## Everything as it was.
static func end(st: Array) -> void:
	for i in range(st.size() - 1, -1, -1):
		var r: Dictionary = st[i]
		if r.has("vp"):
			if is_instance_valid(r.vp):
				r.vp.render_target_update_mode = r.mode
		elif r.has("hid"):
			if is_instance_valid(r.hid):
				r.hid.visible = false
		elif r.has("gi"):
			if is_instance_valid(r.gi):
				r.gi.extra_cull_margin = r.margin
		elif r.has("mm"):
			if r.mm != null:
				r.mm.visible_instance_count = r.vic
