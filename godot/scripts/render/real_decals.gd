## MEWD — REAL DECALS, at the user's request: Godot's own Decal nodes,
## which the Mobile renderer has and Compatibility has not. A real decal
## is a box that paints whatever surface is inside it, so blood wraps the
## corner it was thrown at, a pool runs over the kerb, a scorch lies on
## the floor and the foot of the wall together, and a lance's sear
## crosses a wall and the floor it meets. Under Compatibility (the web)
## the marks stay the quads they were (Decals, GoreDecals).
##
## WHAT IS REAL AND WHAT IS NOT: blood (spatters, pools, the old single
## splash), scorches, the flamer's hot spots, the lance's sears and their
## slag are real. BULLET HOLES STAY QUADS: there are four hundred of them
## and a minigun puts dozens on one spot, and the Mobile renderer draws
## at most EIGHT decals on a mesh — so they would be the eight newest
## and the rest gone.
##
## EIGHT A MESH, and what is done about it: the world is cut into tiles
## (MapGeo.tile, TILE across — each texture's surfaces in each tile their
## own mesh), and each tile's mesh is kept to eight. A mark that would be
## a ninth on any tile it covers is NOT MADE REAL: add() says no, and the
## caller lays it as the quad it always was (Decals, GoreDecals). So a
## minigun's worth of blood on one wall is eight real marks and the rest
## flat, nothing is lost, and nothing is dropped by the renderer behind
## the game's back.
##
## THE LOOK IS THE SHADERS', BAKED: each kind is drawn once at load by
## its own shader (decal.gdshader, gore_decal.gdshader, sear_decal.
## gdshader, in their bake mode — lit at one, no air, no depth test,
## blending off so the texture holds colour and cover as they are) into
## an atlas, VARIANTS of each, and cut into textures. What the shaders do
## over time is done here to the nodes: a pool spreads (its size), blood
## dries (its tint), a hot spot's strength is its cover, a sear's heat
## and embers are two more layers over the scar, fading.
##
## THE LIGHT: a Decal paints an unshaded surface with its own colour, so
## each mark is given the world's light where it is (world_band in
## world_light.gdshaderinc, the same numbers: the sector's light, Doom's
## diminishing with distance, the 32 steps, the light's colour and the
## ambient) as its modulate, every few tics, and fades out into the air
## with distance (distance_fade, over air_near..air_far). The thermal
## sight's feed leaves them out (DECAL_LAYER).
class_name RealDecals
extends Node3D

const TILE := 512.0
const PER_MESH := 8
## the world's tiles are on this layer as well as the first: what a
## decal lands on (never a person, a plant, a van or the gun)
const RECEIVE_LAYER := 1 << 10
## and the decals are on this one, which the thermal feed does not see
const DECAL_LAYER := 1 << 11
const VARIANTS := 6
const CELL := 64

enum K { SPATTER, POOL, BLOOD, SCORCH, HEAT, SEAR, SEAR_HOT, SEAR_EMBER, SLAG }
## how many of each, at most
const CAPS := {K.SPATTER: 360, K.POOL: 64, K.BLOOD: 120, K.SCORCH: 80, K.HEAT: 100,
	K.SEAR: 48, K.SEAR_HOT: 48, K.SEAR_EMBER: 48, K.SLAG: 160}
## how deep each kind's box is along the surface's normal: deep enough to
## wrap a step or a corner, not so deep it reaches the next room
const DEPTH := {K.SPATTER: 14.0, K.POOL: 28.0, K.BLOOD: 14.0, K.SCORCH: 24.0, K.HEAT: 20.0,
	K.SEAR: 48.0, K.SEAR_HOT: 48.0, K.SEAR_EMBER: 48.0, K.SLAG: 18.0}
## the bake: [kind, shader, the shader's kind number, bake part, age or strength]
const BAKE := [
	[K.SPATTER, "gore", 5.0, 0.0, 0.0],
	[K.POOL, "gore", 6.0, 0.0, 6.0],
	[K.BLOOD, "decal", 2.0, 0.0, 0.0],
	[K.SCORCH, "decal", 3.0, 0.0, 0.0],
	[K.HEAT, "decal", 4.0, 0.0, -1.0],
	[K.SEAR, "sear", 8.0, 0.0, 0.0],
	[K.SEAR_HOT, "sear", 8.0, 1.0, 0.0],
	[K.SEAR_EMBER, "sear", 8.0, 2.0, 0.0],
	[K.SLAG, "sear", 9.0, 0.0, 0.0],
]
const SHADERS := {
	"decal": "res://godot/shaders/decal.gdshader",
	"gore": "res://godot/shaders/gore_decal.gdshader",
	"sear": "res://godot/shaders/sear_decal.gdshader",
}
const BAKE_NOW := 100.0

## on (for the tests, headless, where there is no renderer to bake with)
static var force := false

static func on() -> bool:
	return force or RenderingServer.get_rendering_device() != null

var game
## kind -> Array of VARIANTS textures
var textures := {}
var baked := false
## the whole bake, kept for looking at (the tests save it)
var atlas: Image
## the tiles' meshes: their boxes, and which marks are on each
var _chunk_aabb: Array[AABB] = []
var _chunk_marks: Array = []
var _tile_chunks := {}
## the marks of each kind, oldest first
var _kind_marks := {}
var _free: Array[Decal] = []
var _next_id := 0
## the world's light, read off the globals every few tics
var _g := {}
## counts, for the tests
var overflow := 0
var live := 0

class Mark:
	var id := 0
	var kind := 0
	var node: Decal
	var born := 0
	var chunks: PackedInt32Array
	var light := 0.8
	var sky := 0.0
	var size := 1.0
	var pos := Vector3.ZERO
	var strength := 1.0
	## the other layers of the same sear, which go with it
	var group: Array = []
	var gone := false

func _init(g) -> void:
	game = g
	name = "RealDecals"
	for k in K.values():
		_kind_marks[k] = []

func _ready() -> void:
	_read_globals()
	if RenderingServer.get_rendering_device() == null:
		# nothing to bake with: a plain texture each, for the bookkeeping
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		var t := ImageTexture.create_from_image(img)
		for b in BAKE:
			var arr := []
			for i in VARIANTS:
				arr.append(t)
			textures[b[0]] = arr
		baked = true
		return
	_bake()

# ------------------------------------------------------------------
# THE BAKE
# ------------------------------------------------------------------

func _bake() -> void:
	var rows := BAKE.size()
	var px := Vector2i(CELL * VARIANTS, CELL * rows)
	# the colour and the cover, each drawn opaque into a 3D target of its
	# own (the renderer keeps two bits of alpha there), then put together
	# by a 2D pass with blending off
	var colour := _bake_view(px, rows, false)
	var cover := _bake_view(px, rows, true)
	var join := SubViewport.new()
	join.size = px
	join.transparent_bg = true
	join.disable_3d = true
	join.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(join)
	var rect := ColorRect.new()
	rect.size = Vector2(px)
	var jm := ShaderMaterial.new()
	var js := Shader.new()
	js.code = "shader_type canvas_item;\nrender_mode blend_disabled;\nuniform sampler2D c : filter_nearest;\nuniform sampler2D a : filter_nearest;\nvoid fragment() { COLOR = vec4(texture(c, UV).rgb, texture(a, UV).r); }\n"
	jm.shader = js
	jm.set_shader_parameter("c", colour.get_texture())
	jm.set_shader_parameter("a", cover.get_texture())
	rect.material = jm
	join.add_child(rect)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := join.get_texture().get_image()
	colour.queue_free()
	cover.queue_free()
	join.queue_free()
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	atlas = img
	for r in rows:
		var arr := []
		for c in VARIANTS:
			var cell := img.get_region(Rect2i(c * CELL, r * CELL, CELL, CELL))
			arr.append(ImageTexture.create_from_image(cell))
		textures[BAKE[r][0]] = arr
	baked = true

## one bake target: every kind's variants, a row a kind, drawn by the
## kinds' own shaders in their bake mode (`alpha`: the cover as grey)
func _bake_view(px: Vector2i, rows: int, alpha: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = px
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	U.raw_out(vp)
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(rows)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.position = Vector3(0, 0, 10)
	cam.near = 1.0
	cam.far = 20.0
	vp.add_child(cam)
	for r in rows:
		var b: Array = BAKE[r]
		var m := ShaderMaterial.new()
		m.shader = load(SHADERS[b[1]])
		m.set_shader_parameter("bake_part", float(b[3]))
		m.set_shader_parameter("bake_alpha", alpha)
		m.set_shader_parameter("now", BAKE_NOW)
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		quad.material = m
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = VARIANTS
		for c in VARIANTS:
			var x := c + 0.5 - VARIANTS * 0.5
			var y := rows * 0.5 - r - 0.5
			mm.set_instance_transform(c, Transform3D(Basis(), Vector3(x, y, 0)))
			var seed := (c + 0.37) / VARIANTS
			# cd.z: when it was made (its age at BAKE_NOW), or a hot spot's strength
			var z: float = 1.0 if b[4] < 0.0 else BAKE_NOW - float(b[4])
			mm.set_instance_custom_data(c, Color(b[2], seed, z, 1.0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
		vp.add_child(mi)
	return vp

# ------------------------------------------------------------------
# THE TILES
# ------------------------------------------------------------------

## the level's meshes, as MapGeo cut them (their meta "tile")
func register(geo: Node3D) -> void:
	_chunk_aabb.clear()
	_chunk_marks.clear()
	_tile_chunks.clear()
	for mi in geo.get_children():
		if not (mi is MeshInstance3D) or not mi.has_meta("tile"):
			continue
		var id := _chunk_aabb.size()
		_chunk_aabb.append(mi.global_transform * mi.get_aabb())
		_chunk_marks.append([])
		var key: Vector2i = mi.get_meta("tile")
		if not _tile_chunks.has(key):
			_tile_chunks[key] = PackedInt32Array()
		_tile_chunks[key].append(id)

func chunks_under(box: AABB) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := floori(box.position.x / TILE)
	var x1 := floori(box.end.x / TILE)
	var z0 := floori(box.position.z / TILE)
	var z1 := floori(box.end.z / TILE)
	for tx in range(x0, x1 + 1):
		for tz in range(z0, z1 + 1):
			var ids = _tile_chunks.get(Vector2i(tx, tz))
			if ids == null:
				continue
			for id in ids:
				if _chunk_aabb[id].intersects(box):
					out.append(id)
	return out

## how many marks are on the busiest tile mesh (the tests hold it to eight)
func most_on_a_mesh() -> int:
	var m := 0
	for l in _chunk_marks:
		m = maxi(m, l.size())
	return m

# ------------------------------------------------------------------
# MARKS
# ------------------------------------------------------------------

## A mark of `kind` at `at` (map space) on a surface facing `n`, `size`
## across, thrown along `d` (map space; zero: any way round). `light`
## and `sky`: the surface's. Returns the Mark — or NULL, and then the
## caller lays a quad: while the bake is still going, or when a tile
## mesh under it already has its eight (`room` of them free, for a sear's
## three layers).
func add(kind: int, at: Vector3, n: Vector3, size: float, d := Vector3.ZERO, light := 0.8, sky := 0.0, room := 1, lift := 0.0) -> Mark:
	if not baked:
		return null
	var nn := U.v3(n.x, n.y, n.z).normalized()
	if nn.length() < 0.5:
		nn = Vector3.UP
	var g := U.v3(d.x, d.y, d.z)
	var x := g - nn * g.dot(nn)
	if x.length() < 1e-3:
		var up := Vector3.UP if absf(nn.y) < 0.95 else Vector3.FORWARD
		x = up.cross(nn).normalized().rotated(nn, randf() * TAU)
	x = x.normalized()
	var z := x.cross(nn).normalized()
	var xf := Transform3D(Basis(x, nn, z), U.v3(at.x, at.y, at.z) + nn * lift)
	var depth: float = DEPTH[kind]
	var ext := Vector3(size, depth, size)
	var box: AABB = xf * AABB(-ext * 0.5, ext)
	var under := chunks_under(box)
	# room on every tile mesh it covers, or it is a quad
	for c in under:
		if (_chunk_marks[c] as Array).size() + room > PER_MESH:
			overflow += 1
			return null
	# and the kind's own cap: the oldest of the kind goes
	var mine: Array = _kind_marks[kind]
	while mine.size() >= int(CAPS[kind]):
		_remove(mine[0])
	var m := Mark.new()
	_next_id += 1
	m.id = _next_id
	m.kind = kind
	m.born = game.tics if game != null else 0
	m.chunks = under
	m.light = light
	m.sky = sky
	m.size = size
	m.pos = xf.origin
	m.node = _node()
	m.node.transform = xf
	m.node.size = ext
	var vars: Array = textures[kind]
	m.node.texture_albedo = vars[m.id % vars.size()]
	m.node.visible = true
	mine.append(m)
	for c in under:
		(_chunk_marks[c] as Array).append(m)
	live += 1
	_light(m)
	return m

## a sear: the scar, and its heat and its embers over it, as one — all
## three or none. The heat and the embers sit a little behind the scar,
## into the surface: the Mobile renderer paints the FARTHER of two decals
## last, so that is what puts them over it.
func add_sear(at: Vector3, n: Vector3, size: float, d := Vector3.ZERO, light := 0.8, sky := 0.0) -> Mark:
	var scar := add(K.SEAR, at, n, size, d, light, sky, 3)
	if scar == null:
		return null
	var hot := add(K.SEAR_HOT, at, n, size, d, light, sky, 2, -1.0)
	var ember := add(K.SEAR_EMBER, at, n, size, d, light, sky, 1, -2.0)
	# the three share one look: the same variant and the same turn
	for m in [hot, ember]:
		if m != null and not scar.gone:
			var xf: Transform3D = scar.node.transform
			m.node.transform = Transform3D(xf.basis, xf.origin - xf.basis.y.normalized() * (1.0 if m.kind == K.SEAR_HOT else 2.0))
			m.node.texture_albedo = (textures[m.kind] as Array)[scar.id % VARIANTS]
	scar.node.texture_albedo = (textures[K.SEAR] as Array)[scar.id % VARIANTS]
	var grp := [scar, hot, ember].filter(func(x): return x != null and not x.gone)
	for m in grp:
		m.group = grp
	return scar

## a hot spot's strength, 0..1: its cover
func set_strength(m: Mark, s: float) -> void:
	if m == null or m.gone:
		return
	m.strength = s
	_light(m)

func remove(m: Mark) -> void:
	if m != null and not m.gone:
		_remove(m)

func _remove(m: Mark) -> void:
	if m.gone:
		return
	m.gone = true
	live -= 1
	(_kind_marks[m.kind] as Array).erase(m)
	for c in m.chunks:
		(_chunk_marks[c] as Array).erase(m)
	m.node.visible = false
	_free.append(m.node)
	m.node = null
	for o in m.group:
		if o != m and not o.gone:
			_remove(o)

func _node() -> Decal:
	if not _free.is_empty():
		return _free.pop_back()
	var d := Decal.new()
	d.cull_mask = RECEIVE_LAYER
	d.layers = DECAL_LAYER
	# NO NORMAL FADE: the world's surfaces are unshaded and hand a decal
	# no normal to fade by, so any fade at all fades the whole mark away.
	# How far a mark wraps round a corner is its box's depth (DEPTH)
	d.normal_fade = 0.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	d.distance_fade_enabled = true
	_fade(d)
	add_child(d)
	return d

func _fade(d: Decal) -> void:
	var near: float = _g.get("air_near", 1500.0)
	var far: float = _g.get("air_far", 5000.0)
	d.distance_fade_begin = near + (far - near) * 0.3
	d.distance_fade_length = maxf(64.0, (far - near) * 0.7)

# ------------------------------------------------------------------
# EVERY TIC
# ------------------------------------------------------------------

func tic() -> void:
	if not baked or game == null:
		return
	var t: int = game.tics
	var now := t / 35.0
	# the pools spread, the sears cool; the heat is gone when it is gone
	for m in (_kind_marks[K.POOL] as Array):
		var age: float = (t - m.born) / 35.0
		if age <= 6.2:
			var k := 0.35 + 0.65 * smoothstep(0.0, 6.0, age)
			m.node.size = Vector3(m.size * k, DEPTH[K.POOL], m.size * k)
	for kind in [K.SEAR_HOT, K.SEAR_EMBER]:
		var gone := []
		for m in (_kind_marks[kind] as Array):
			if _glow(m, now) < 0.02:
				gone.append(m)
		for m in gone:
			# a layer that has cooled goes on its own (not its scar)
			m.group = []
			_remove(m)
	if t % 4 == 0:
		if t % 32 == 0:
			_read_globals()
		var cam: Vector3 = game.camera.global_position if game.camera != null else Vector3.ZERO
		var far: float = _g.get("air_far", 5000.0) + 400.0
		for kind in _kind_marks:
			for m in (_kind_marks[kind] as Array):
				if m.pos.distance_squared_to(cam) < far * far:
					_light(m, cam, now)

func _glow(m: Mark, now: float) -> float:
	var age: float = now - m.born / 35.0
	if m.kind == K.SEAR_HOT:
		return exp(-age / 3.5)
	return exp(-age / 14.0) * (0.75 + 0.25 * sin(now * 11.0 + m.id))

## THE MODULATE: the world's light at the mark (world_band), the kind's
## own tint, and its cover — encoded, as every colour handed to the
## Mobile renderer is (U.col)
func _light(m: Mark, cam = null, now := -1.0) -> void:
	if m.node == null:
		return
	if now < 0.0:
		now = game.tics / 35.0 if game != null else 0.0
	var d: float = m.pos.distance_to(cam) if cam != null else 0.0
	var lit := _band(m.light, d, m.sky)
	var lc: Color = _g.get("light_color", Color.WHITE)
	var amb: Color = _g.get("ambient_light", Color.BLACK)
	var c := Color(lit * lc.r + amb.r, lit * lc.g + amb.g, lit * lc.b + amb.b, 1.0)
	var age: float = now - m.born / 35.0
	match m.kind:
		K.SPATTER, K.BLOOD:
			# wet to dry over half a minute (gore_decal.gdshader's `dry`)
			var dry := smoothstep(0.0, 30.0, age)
			c = Color(c.r * lerpf(1.0, 0.38, dry), c.g * lerpf(1.0, 3.0, dry), c.b * lerpf(1.0, 1.8, dry), 1.0)
		K.POOL:
			var dry := smoothstep(10.0, 60.0, age) * 0.6
			c = Color(c.r * lerpf(1.0, 0.38, dry), c.g * lerpf(1.0, 3.0, dry), c.b * lerpf(1.0, 1.8, dry), 1.0)
		K.HEAT:
			# its own light, its strength its cover
			c = Color(1, 1, 1, clampf(m.strength * 1.3, 0.0, 1.0))
		K.SEAR_HOT, K.SEAR_EMBER:
			var gl := _glow(m, now)
			c = Color(1.0 + 0.5 * gl, 1.0 + 0.5 * gl, 1.0 + 0.5 * gl, clampf(gl, 0.0, 1.0))
		K.SLAG:
			var w := exp(-age / 4.0)
			c = Color(lerpf(c.r, 2.0, w), lerpf(c.g, 0.9, w), lerpf(c.b, 0.3, w), 1.0)
	m.node.modulate = U.col(c)

## world_band (world_light.gdshaderinc), off the globals
func _band(light_in: float, d: float, sky: float) -> float:
	var sky_light: float = _g.get("sky_light", 0.85)
	var fall: float = _g.get("light_falloff", 1600.0) * lerpf(1.0, 3.4, sky)
	var mn := minf(0.85, float(_g.get("min_light", 0.1)) + 0.32 * sky)
	var li := lerpf(light_in, maxf(light_in, sky_light), sky)
	mn = lerpf(mn, 1.0, clampf(sky_light, 0.0, 1.0) * sky)
	var dim := 1.0 - clampf(d / maxf(1.0, fall), 0.0, 1.0)
	var l := li * lerpf(mn, 1.0, dim) * float(_g.get("global_light", 1.0))
	return floorf(l * 32.0 + 0.5) / 32.0

func _read_globals() -> void:
	for k in ["sky_light", "light_falloff", "min_light", "global_light", "light_color", "ambient_light", "air_near", "air_far"]:
		var v = U.G.get(k)
		if v != null:
			_g[k] = v
	for n in get_children():
		if n is Decal:
			_fade(n)
