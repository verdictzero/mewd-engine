## MEWD — HOW FAR THINGS ARE DRAWN (at the user's request: "add distance
## culling options in the options menu"): the pause menu's DISTANCE page
## (PauseMenu: `dist_land`, `dist_trees`, `dist_grass`, `dist_people`),
## put on the island's own streamers as they run.
##
##   LAND     IslandWorld.view_distance — the terrain chunks kept and drawn
##            — a share of the scene's own (25% to all of it).
##   TREES    the trees, bushes and ferns (VegScatter): each class's fade
##            band on its material (`far_start`, `far_end`) and the
##            distance past which its plants are not submitted at all
##            (`_class_view_sq`) scaled together, so a plant still dithers
##            out before it is dropped; past 100% the scatter's own reach
##            with them.
##   GRASS    the tufts (GrassScatter): off, or its reach and its fade
##            scaled.
##   PEOPLE   the sprites (Standees.cull_far): people, creatures, things.
##
## Set from outside the island's scripts (their own exports and the
## scatter's working numbers) so the bakes, which digest those scripts,
## stay as they are. Every scale is of the value the scene was loaded
## with, kept on the node the first time (meta "dist_base").
class_name Distances
extends RefCounted

const DEFAULTS := {"dist_land": 1.0, "dist_trees": 1.0, "dist_grass": 1.0, "dist_people": 6400.0}

static func apply(game, prefs: Dictionary) -> void:
	if game == null:
		return
	if game.get("standees") != null:
		game.standees.cull_far = float(prefs.get("dist_people", DEFAULTS.dist_people))
	var isl = game.get("island")
	if isl == null or not is_instance_valid(isl):
		return
	var world = isl.get_node_or_null("IslandWorld")
	if world != null:
		var base := _base(world, "view_distance")
		world.view_distance = base * float(prefs.get("dist_land", 1.0))
	var veg = isl.get_node_or_null("VegScatter")
	if veg != null:
		_trees(veg, float(prefs.get("dist_trees", 1.0)))
	var grass = isl.get_node_or_null("GrassScatter")
	if grass != null:
		_grass(grass, float(prefs.get("dist_grass", 1.0)))

## the value `prop` had when the node was first scaled
static func _base(n: Object, prop: String) -> float:
	var b: Dictionary = n.get_meta("dist_base", {})
	if not b.has(prop):
		b[prop] = float(n.get(prop))
		n.set_meta("dist_base", b)
	return float(b[prop])

## a material's fade band, scaled from the one it was loaded with;
## returns its far end
static func _band(m: ShaderMaterial, k: float) -> float:
	if m == null:
		return 0.0
	if not m.has_meta("dist_base"):
		var s = m.get_shader_parameter("far_start")
		var e = m.get_shader_parameter("far_end")
		m.set_meta("dist_base", [float(s) if s != null else 0.0, float(e) if e != null else 0.0])
	var b: Array = m.get_meta("dist_base")
	if float(b[1]) <= 0.0:
		return 0.0
	m.set_shader_parameter("far_start", float(b[0]) * k)
	m.set_shader_parameter("far_end", float(b[1]) * k)
	return float(b[1]) * k

static func _trees(veg, k: float) -> void:
	var reach := _base(veg, "view_distance") * maxf(k, 1.0)
	veg.view_distance = reach
	var under: ShaderMaterial = veg.understory_material if veg.understory_material != null else veg.material
	var fern: ShaderMaterial = veg.fern_material if veg.fern_material != null else under
	var mats := [veg.material, under, fern]
	var done := {}
	var ends := []
	for m in mats:
		if m == null:
			ends.append(0.0)
		elif done.has(m):
			ends.append(done[m])
		else:
			done[m] = _band(m, k)
			ends.append(done[m])
	# (not ready yet: the scatter reads the bands itself when it is)
	var views: PackedFloat32Array = veg.get("_class_view_sq")
	if views == null or views.size() < 3:
		return
	for cls in 3:
		var d: float = ends[cls] if float(ends[cls]) > 0.0 else reach
		views[cls] = pow(minf(d, reach), 2.0)
	veg.set("_class_view_sq", views)
	var fp: PackedInt64Array = veg.get("_fill_fp")
	for cls in fp.size():
		fp[cls] = -1
	veg.set("_fill_fp", fp)
	veg.set("_force_rescan", true)

static func _grass(grass, k: float) -> void:
	var on := k > 0.0
	grass.visible = on
	grass.set_process(on)
	if not on:
		return
	grass.view_distance = _base(grass, "view_distance") * k
	_band(grass.material as ShaderMaterial, k)
	grass.set("_force_rescan", true)
