## MEWD — THE MAZE DRAWN (MAZE LAND, at the user's request; Maze): every
## wall and every post of the level's maze as instances of the user's two
## parts (assets/models/maze_parts.glb: maze_wall, 8 m along its x, and
## maze_corner, a 1 m post), in CHUNKS of CHUNK x CHUNK cells — a MultiMesh
## of walls and one of posts each — so the far ones drop out (VIEW, the
## DISTANCE page's LAND scaling it: Distances) and the near ones take the
## model's own detail levels each by its own distance. Hung under the
## island, in its metres: the game's (x, y) is the island's (x, -y) / 32.
## Drawn as the houses are (SHADER_house: the island's own lighting, cold
## to the thermal sight).
class_name MazeView
extends Node3D

const MODEL := "res://assets/models/maze_parts.glb"
const CHUNK := 8
## metres out to which a chunk is drawn (its own box's distance)
const VIEW := 260.0

var walls := 0
var posts := 0

func _init(maze: Maze) -> void:
	name = "Maze"
	var scene: Node = (load(MODEL) as PackedScene).instantiate()
	var wall_mesh: Mesh = null
	var post_mesh: Mesh = null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).begins_with("maze_wall"):
			wall_mesh = HouseView._cold_mesh(mi.mesh)
		elif str(mi.name).begins_with("maze_corner"):
			post_mesh = HouseView._cold_mesh(mi.mesh)
	scene.free()
	var k := IslandLevel.U_PER_M
	var fy := maze.floor_z / k
	var span := maze.pitch * CHUNK
	var w_by := {}
	var p_by := {}
	for w in maze.walls():
		var mx: float = (w[0] + w[2]) * 0.5
		var my: float = (w[1] + w[3]) * 0.5
		var key := _chunk(maze, mx, my, span)
		if not w_by.has(key):
			w_by[key] = []
		# (an east-west wall lies along the island's x as the model does; a
		# north-south one is turned a quarter onto its z)
		var b := Basis.IDENTITY if w[1] == w[3] else Basis(Vector3.UP, PI * 0.5)
		w_by[key].append(Transform3D(b, Vector3(mx / k, fy, -my / k)))
	for p in maze.posts():
		var key := _chunk(maze, p.x, p.y, span)
		if not p_by.has(key):
			p_by[key] = []
		p_by[key].append(Transform3D(Basis.IDENTITY, Vector3(p.x / k, fy, -p.y / k)))
	for key in w_by:
		add_child(_mm(wall_mesh, w_by[key], "Walls%d_%d" % [key.x, key.y]))
		walls += w_by[key].size()
	for key in p_by:
		add_child(_mm(post_mesh, p_by[key], "Posts%d_%d" % [key.x, key.y]))
		posts += p_by[key].size()

static func _chunk(maze: Maze, x: float, y: float, span: float) -> Vector2i:
	return Vector2i(floori((x - maze.x0) / span), floori((maze.y0 - y) / span))

func _mm(mesh: Mesh, xf: Array, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		# (SHADER_house's colourway: the painting as it is)
		mm.set_instance_custom_data(i, Color(0.0, 1.0, 1.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.visibility_range_end = VIEW
	mi.visibility_range_end_margin = 20.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## how far the chunks are drawn (Distances: LAND)
func set_view(k: float) -> void:
	for c in get_children():
		(c as GeometryInstance3D).visibility_range_end = VIEW * k
