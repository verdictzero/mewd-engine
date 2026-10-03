extends Node3D

# Ground-cover grass tufts: Y-axis billboards of the crunched `sprites/` grass,
# scattered from the SAME `IslandField` that paints the ground and plants the
# firs, so grass, litter and canopy can never disagree about what a patch of
# ground is.
#
# Every tuft is a pure function of a coarse logical-XZ grid cell — hash the cell
# for a jittered position, a sprite variant and a keep roll, sample the field there
# once. Fly away and back and the identical field returns, and because the grid
# lives in logical coordinates it rides a floating-origin rebase without moving.
#
# ONE MULTIMESH PER SPRITE, so the whole ground cover is one draw call per variant
# however many thousand tufts are standing. There is no LOD ladder and no impostor
# bake: a tuft IS a billboard already, and `SHADER_veg_billboard.gdshader` dithers it out
# at the far edge.
#
# NO GROUND TINT. Every tuft used to carry the absolute linear albedo of the
# terrain under it as a per-instance COLOUR, which the shader then recoloured the
# sprite toward so a tuft on needle floor did not stay meadow-green. That is gone
# with the lit shader that consumed it: the billboards are `unshaded` now and
# `SCRIPT_measure_art.gd`'s four layer means have no consumer here any more. A tuft is the
# colour its sprite is painted, times the material's flat `tint`. The per-instance
# custom-data vec4 the stride still carries (see `_STRIDE`) is a different channel —
# a scalar CRATER BURN, not a colour — and it feeds the burn stage, not the albedo.
#
# WHY THE CELLS ARE GROUPED INTO TILES. The natural way to write this is one
# dictionary entry per grid cell, and that is how it was written; it does not
# survive contact with a camera in motion. At `grass_grid` 1 m over a 90 m view
# the cell dictionary holds fifty thousand entries, and EVERY rescan walked all of
# them — once to discover, once to emit, once in eight to prune — then re-packed
# the whole instance buffer a float at a time. Measured on the reference container,
# flying: 248 ms per frame average, 921 ms at worst, while the camera was high
# enough that the emit produced ZERO tufts. All of it was bookkeeping.
#
# So the unit of work here is a TILE — `tile_cells` square of grid cells, ~16 m —
# and a tile is meshed once, into finished per-sprite instance buffers in render
# space. A rescan then walks a few hundred tiles instead of fifty thousand cells,
# and emitting is `PackedFloat32Array.append_array` per visible tile, which is a
# memcpy rather than a scripted loop. The tuft positions are unchanged; this is
# purely how they are stored and shipped.
#
# The other thing tiles buy is the altitude cut. A tile knows the height band of
# its own tufts, so the visibility test is a true 3D distance to a box — and a
# camera 160 m up simply matches no tiles at all and does no work, instead of
# field-sampling four thousand cells a frame to build a field nobody can see.
#
# WHY IT IS ITS OWN NODE rather than a mode on the tree scatter. The two want
# opposite budgets — trees are ~11 m apart and visible for 1300 m, grass is ~1 m
# apart and visible for 90 — so sharing a grid would either starve the forest of
# range or drown the frame in tufts. They share the field, which is the part that
# has to agree, and the tiling construction, and nothing else.
#
# AND WHY A SCAN IS QUANTISED TO A LATTICE. Tiling fixed the cost of DISCOVERING
# what should exist; it left the cost of SHIPPING it, and that one is paid on a
# camera that discovers nothing at all. A scan re-walks the tile box and re-packs
# every visible tuft into one instance buffer, which it then hands to the GPU
# whole — measured on the reference container, standing in filled-in rough with
# every tile already meshed: 2.07 ms per scan, of which 1.06 ms is the re-pack of
# 21,336 tufts (1.4 MB memcpy'd twice) and the rest is the box walk. With the two
# scatters together that was 5.4 ms per scan, 10.8% of a 60 fps frame, spent to
# arrive at the same answer as last time.
#
# The answer only CHANGES when a tile enters or leaves the view, and at a 16 m
# tile that is every 16 m of travel — but the old gate re-ran the scan every
# `move_epsilon`, which was 2 m. So the eye is quantised to a SCAN CELL and every
# distance is measured from that CELL'S BOX rather than from the eye point. The
# emitted set is then a pure function of the cell, unchanged until the camera
# leaves it, and a scan that would reach the same answer is skipped outright
# instead of recomputed. What it costs is a slightly wider set — tiles within
# `view_distance` of ANYWHERE in the cell, not of the eye — and those extra tufts
# are ones `SHADER_veg_billboard.gdshader` has already faded to nothing.

@export var island_world_path: NodePath
## The crunched 128 px grass sprites to scatter. One MultiMesh each; a cell picks
## between them by hash. Bake them with `scripts/SCRIPT_crunch_art.gd`.
##
## `sprites/vegetation/` ships ONE grass cutout where the retired `sprites_2` set
## shipped two, so what used
## to be variant-picking is now the material's `flip_variants` mirroring plus the
## width and height jitter below. Add more here if the repetition ever shows.
@export var sprites: Array[Texture2D] = []
## Shader material for the billboards (`MAT_grass_billboard.tres`). Shared by
## every variant; only the albedo differs, and that is set per variant below.
## The same `SHADER_veg_billboard.gdshader` the firs and bushes draw through, with the
## near fade switched off — see that material's header.
@export var material: ShaderMaterial

@export_group("Placement")
## Logical grid spacing, metres. One candidate tuft per cell (jittered), so this
## is the density dial — and it is QUADRATIC in cost, which is the thing to know
## before touching it: halving it quadruples both the cells to field-sample and
## the tufts to draw. At 1.0 m over a 90 m view that is ~32,000 cells and, at the
## density below, ten to fifteen thousand quads standing at once.
##
## The sample cost is paid once per cell ever (a tile is meshed once and kept);
## the draw cost is paid every frame. `max_eval_per_scan` bounds the first,
## nothing bounds the second but this number.
@export var grass_grid := 1.0
## Fraction of eligible cells that grow a tuft, before the clumping noise.
@export_range(0.0, 1.0) var density := 0.85
## Tufts avoid ground steeper than this (0 flat .. 1 vertical).
@export_range(0.0, 1.0) var max_slope := 0.42
## Tufts stay out of any zone whose grooming influence exceeds this. Looser than
## the trees' equivalent on purpose: a fairway is mown and wants none, but the
## rough right up against its bank should not be suddenly bald.
@export_range(0.0, 1.0) var max_flatten := 0.35
## How far through the fire the worst-hit tuft in a crash site's collar is. The twin
## of `veg_scatter.crater_burn_peak` and set to match it — the tufts stand among the
## trees and a lawn of cold stubble under a burning wood is the disagreement this
## exists to prevent. See that export for why 1.0 is the wrong number to hand a
## PLANT even where the ground under it is fully charred.
@export_range(0.0, 1.0) var crater_burn_peak := 0.7
## How far the canopy thins the ground cover. 1.0 clears it completely under a
## full forest, 0.0 ignores the wood entirely.
##
## SHIPPED AT 1.0, so grass is a FIELD plant and stops at the treeline. That is a
## look decision and it is also a division of labour: the wood already has a
## ground-cover layer in `SCRIPT_veg_scatter.gd`'s ferns, and running both under the same
## canopy gave a floor that was half meadow and half forest and read as neither.
## Because the term is a lerp against `IslandField.forest_at` rather than a
## threshold, the two hand over across the same soft edge the canopy itself fades
## on — grass thins as the ferns come up, instead of ending on a line.
##
## Lower it if you want tufts under the trees again; 0.75 was the old value and
## left about a quarter of the meadow standing in deep wood.
@export_range(0.0, 1.0) var forest_falloff := 1.0
## How much of the grass the RUIN ENTRANCE's clearing takes out — a roll per cell
## on `IslandField.ruin_at`'s levelling weight, like the vegetation's.
##
## THIS ONE NEEDS A RULE WHERE THE CRATER'S DOES NOT. Across a crash site the grass
## splat channel goes to zero and the density weighting above takes the tufts with
## it for free. The ruin leaves its ground turf (`IslandField.ruin_grooming` is 0:
## the meadow runs up to the stones), so nothing in the splat stops a tuft — and a
## tuft is up to 1.7 m tall against a tile apron that stands 0.39 m proud of the
## ground. Left to the splat, the apron would be carpeted in grass growing up
## through the stone. What grows on the disc instead is the ruin's own planting,
## which can see the tiles; see `ruin_grass_keep`.
@export_range(0.0, 1.0) var ruin_clearing := 1.0
## Levelling weight at and above which no tuft grows at all.
##
## 0.97, WHICH IS THE LEVELLED DISC AND TWO METRES PAST IT: 28.0 m from the ruin's
## axis. Everything inside that is the RUIN'S to plant, not this scatter's — the
## prefab's `GapPlanter` can see the tiles, grows the gaps between them and the
## ground round them out to `RuinGapGrowth.surround_reach` past the disc, and hands
## over to this scatter there, so the meadow runs unbroken up to the stones. The
## outermost stone is 24.67 m out, inside the disc, so nothing this scatter plants
## can stand on one.
##
## It was 0.8 (31.3 m) while the ruin stood in a clearing, with the ground worn bare
## to match; see `docs/DOC_ruin_gap_growth.md` for why that ring is gone.
@export_range(0.0, 1.0) var ruin_grass_keep := 0.97
## How far below that, in levelling weight, the grass takes to come back — 0.97 to
## 0.94 is 28.0 m to 28.9 m from the axis, a thickening over the last metre of the
## handover rather than a mown line.
@export_range(0.02, 0.8) var ruin_grass_band := 0.03
## Tuft size in metres (width, height) before the per-instance scale jitter.
@export var tuft_size := Vector2(1.25, 1.15)
@export var min_scale := 0.75
@export var max_scale := 1.5
## Tufts are sunk this far into the ground so their sprite's soil base is buried
## rather than floating a hair above the surface on a slope.
@export var sink := 0.12

@export_group("Streaming")
## Tufts exist within this logical distance of the camera. Keep the material's
## `far_end` at or under it, or they pop out while still fully opaque.
@export var view_distance := 90.0
@export var keep_margin := 25.0
@export var rescan_interval := 3
## Grid cells per tile side. The tile is the unit of meshing, of caching and of
## visibility, so this trades granularity against per-rescan overhead: bigger
## tiles mean fewer of them to walk and a coarser cut at the view edge (a tile is
## kept whole, so tufts up to a tile's diagonal past `view_distance` come along —
## harmless, since the shader has already faded them to nothing by then), smaller
## tiles mean a tighter cut and more bookkeeping. 16 cells is ~16 m at the default
## grid, which puts about 130 tiles in view.
@export var tile_cells := 16
## Mesh tiles on worker threads, the way `SCRIPT_island_world.gd` meshes its chunks and
## for the same reason: `IslandField.sample` costs about a tenth of a millisecond,
## a tile is `tile_cells` squared of them, and keeping up with a camera at 120 m/s
## takes ~360 of them per frame. That is 36 ms — two frames' worth — of arithmetic
## that touches nothing but a field clone, so it has no business on the main
## thread. Turn it off and the fallback below applies.
@export var use_threads := true
## Tile meshes allowed in flight at once. The pool is shared with everything else
## that threads, so this is a politeness limit as much as a throughput one.
@export var max_in_flight := 4
## Field samples per scan when `use_threads` is OFF and tiles are meshed inline.
## Spent in whole tiles, so the true ceiling is this rounded up to the next
## `tile_cells` squared. With threads on nothing draws on it: the scan itself
## samples the field zero times.
@export var max_eval_per_scan := 1200
## Side of the SCAN CELL, in metres. The eye is quantised to this lattice and a
## scan is skipped entirely while it stays in the same cell — see the header.
##
## This is a straight trade and both ends of it are cheap to reason about:
##
##     scans are (scan_cell / old move_epsilon) times rarer
##     the emitted set grows by roughly ((view_distance + scan_cell) / view)^2
##
## At 8 m against the 90 m view that is four times fewer scans for about 19% more
## tufts standing — and those extra tufts are all in the outermost 8 m of the
## view, where the material has already faded them to nothing. Raising it to the
## 16 m tile size would make scans eight times rarer for ~39% more tufts.
##
## 0 scans every frame the camera moves at all, which is what the flyover render
## harness wants so its stills are exact. Do not ship it.
@export var scan_cell := 8.0
## The same budget while a loading screen is filling the ground cover in up front.
## Bigger, because nothing is on screen to stutter — and, like the one above, dead
## weight unless `use_threads` is off.
##
## NOTE THIS FILL IS ALREADY TOTAL, and it is worth writing down why there is no
## `prescatter` here to match `SCRIPT_veg_scatter.gd`'s. The vegetation is worth building
## whole because its view distance is 1,300 m — most of the island is in view at
## once, so most of it is worth having ready. Grass is visible for 90 m, so what
## the loading screen lays down IS everything the player can ever see standing
## where they spawn, and everything past it is invisible until they walk there.
##
## Building the rest anyway is not a trade, it is a loss.
## `tests/PROBE_veg_census.gd` counts what "the rest" is on the shipped field:
##
##     2,771,146 tufts over the island   169 MB of instance buffers
##     7,438,592 candidate cells         ~25 minutes at the measured meshing rate
##
## against the ~21,000 tufts that can stand in a 90 m view. So the ground cover
## streams, and what stops it costing frames is the scan cell above, not a bigger
## fill.
@export var prefill_eval_per_step := 3000

# Godot's 3D MultiMesh instance stride: the transform as three rows of four (each
# basis row, then that row's origin component) = 12, plus one custom-data vec4 = 16.
# The custom vec4's .x carries a tuft's crater burn into `SHADER_veg_billboard.gdshader`
# (`INSTANCE_CUSTOM.x`), so a meadow chars along with the trees where a crash site
# reaches it instead of staying a green lawn under a fire — the same channel
# `SCRIPT_veg_scatter.gd` uses, and for the same reason: burn is per-INSTANCE and the
# per-sprite material cannot hold it. .yzw are unwritten (0) and reserved.
const _STRIDE := 16
# Offset of the custom-data vec4 within the stride — after the 12 transform floats.
const _CUSTOM_OFF := 12

var _world: Node3D = null
var _field: IslandField = null
var _origin_offset := Vector3.ZERO
var _frame := 0
var _force_rescan := false
# The scan cell the last scan was taken from, and whether there has been one.
# Quantised in all THREE axes: the altitude cut means a camera climbing changes
# what is in view just as surely as one walking.
var _last_cell := Vector3i.ZERO
var _have_cell := false
var _prune_tick := 0
var _tile_size := 16.0

# Logical tile (Vector2i, `_tile_size` metres square) -> record, in two shapes:
#
#   {"y0", "y1"}                     probed only: the height band the ground
#                                    occupies here, enough to place the tile in
#                                    space and decide whether it is worth meshing
#   {"y0", "y1", "bufs"}             meshed: one finished PackedFloat32Array per
#                                    sprite variant, in RENDER space, with the
#                                    band tightened to the tufts actually in it
#
# `bufs` is what tells the two apart, and its presence means the tile is done.
var _tiles := {}
# The tile box the last scan covered, so a camera sitting still re-walks nothing.
var _box_min := Vector2i.ZERO
var _box_max := Vector2i.ZERO
var _box_valid := false
# Tiles in view still wanting a probe, a mesh, or a worker to finish, as of the
# last scan.
var _todo := 0
# Largest backlog seen during an up-front `prefill_step()` run — the denominator
# `prefill_ratio()` reports against.
var _prefill_total := 0

# Tile -> WorkerThreadPool task id (-1 when meshed inline), and the results those
# workers have finished with. Same shape as `SCRIPT_island_world.gd`'s chunk dispatch.
var _pending := {}
var _done: Array = []
var _done_mutex := Mutex.new()
# Prepared `IslandField` clones, one per worker that wants one at a time. Cloning
# is the expensive part, so they are handed back rather than dropped.
var _field_pool: Array = []
var _pool_mutex := Mutex.new()

var _meshes: Array[MultiMesh] = []
var _instances: Array[MultiMeshInstance3D] = []
var _ready_ok := false


func _ready() -> void:
	add_to_group("origin_shiftable")
	_world = get_node_or_null(island_world_path) as Node3D
	if _world != null and _world.has_method("get_field"):
		_field = _world.get_field()
	if _field == null:
		push_warning("grass_scatter: no IslandField (set island_world_path). Disabled.")
		return
	# START IN STEP WITH THE WORLD. This scatter tracks its own copy of the
	# logical/rendered offset and moves it on every rebase, which was complete
	# while the two frames could only ever start out equal. `TerrainWorld` can now
	# be authored with a non-zero `logical_origin` — SCENE_test_zone_Q2 uses it to
	# put an airfield under the spawn — and a scatter that assumed zero would
	# sample the field 8.4 km from where it plants things: wrong heights, wrong
	# forest mask, and no idea that the ground under the runway is groomed.
	if _world != null and _world.has_method("origin_offset"):
		_origin_offset = _world.origin_offset()

	if not _field._ready:
		_field.prepare()
	if sprites.is_empty() or material == null:
		push_warning("grass_scatter: no sprites or no material assigned. Disabled.")
		return
	_tile_size = maxf(grass_grid, 0.01) * float(maxi(tile_cells, 1))
	_build_multimeshes()
	_ready_ok = not _meshes.is_empty()


# One MultiMesh per sprite. Each gets its own DUPLICATE of the shared material so
# it can carry its own albedo — duplicating rather than reusing matters, since a
# ShaderMaterial assigned to two instances is one object and the second
# assignment would silently repaint the first.
func _build_multimeshes() -> void:
	for i in range(sprites.size()):
		var tex: Texture2D = sprites[i]
		if tex == null:
			continue
		var quad := QuadMesh.new()
		quad.size = tuft_size
		# The pivot is the tuft's BASE, not its middle: the scatter places it on
		# the ground, and a centre-pivoted quad would bury half of it.
		quad.center_offset = Vector3(0.0, tuft_size.y * 0.5 - sink, 0.0)

		var mat: ShaderMaterial = material.duplicate()
		mat.set_shader_parameter("albedo_tex", tex)
		# And the burn map beside it — see `VegBurn.bind_map`. Grass burns like grass
		# rather than like a tree: it is the only sprite of the ten with no woody
		# pixels in it, so it chars all over and holds its coals at the base.
		VegBurn.bind_map(mat, tex)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Per-tuft crater burn rides in the custom-data vec4 — see `_STRIDE`. 0 on every
		# tuft away from a crash site, which the shader reads as "follow the bus".
		mm.use_custom_data = true
		mm.mesh = quad

		var inst := MultiMeshInstance3D.new()
		inst.name = "GrassTufts%d" % i
		inst.multimesh = mm
		inst.material_override = mat
		# Grass shadows would be thousands of alpha-scissored quads in the shadow
		# pass for a few pixels of noise on the ground under them.
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)

		_meshes.append(mm)
		_instances.append(inst)


# Rebase. The tile buffers hold RENDER-space transforms, so they are patched in
# place — three floats per instance — rather than thrown away: rebuilding them
# would re-sample the field for the whole neighbourhood, which is the one thing
# this design exists to avoid, and it would do it in the single frame the world
# jumps eight kilometres.
func apply_origin_shift(shift: Vector3) -> void:
	_origin_offset -= shift
	for key in _tiles:
		var rec: Dictionary = _tiles[key]
		if rec.has("bufs"):
			_shift_bufs(rec["bufs"], shift)
	_force_rescan = true


# Add `shift` to the origin of every instance in every buffer. The origin sits at
# offsets 3, 7 and 11 of the stride — see `_pack_tile` for the layout.
func _shift_bufs(bufs: Array, shift: Vector3) -> void:
	for i in range(bufs.size()):
		var b: PackedFloat32Array = bufs[i]
		var k := 3
		while k < b.size():
			b[k] += shift.x
			b[k + 4] += shift.y
			b[k + 8] += shift.z
			k += _STRIDE
		bufs[i] = b


func _process(_delta: float) -> void:
	if not _ready_ok:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_frame += 1
	if not _force_rescan and _frame % maxi(rescan_interval, 1) != 0:
		return
	var eye := cam.global_position + _origin_offset   # logical
	# Everything a scan produces is a function of the CELL, so an eye still inside
	# the one the last scan was taken from would recompute an identical answer.
	# `_pending` is in the test as well as `_force_rescan`: a worker whose tile has
	# drifted out of the scanned box stops being counted in `_todo`, and without
	# this its result would sit in `_done` unclaimed while the camera is parked.
	var cell := _scan_cell(eye)
	if scan_cell > 0.0 and not _force_rescan and _have_cell \
			and cell == _last_cell and _pending.is_empty():
		return
	_force_rescan = false
	_have_cell = true
	_last_cell = cell
	_rescan(eye)


func _rescan(eye: Vector3, budget := -1) -> void:
	var view_sq := view_distance * view_distance
	# The scan cell's own box. Every distance below is measured from THIS, not from
	# `eye`, so the whole scan is a function of the cell and stays correct wherever
	# in the cell the camera drifts before the next one. At `scan_cell` 0 the box
	# collapses onto the eye and every test below reduces to the point test this
	# replaced.
	var lo := eye
	var hi := eye
	if scan_cell > 0.0:
		lo = Vector3(_scan_cell(eye)) * scan_cell
		hi = lo + Vector3(scan_cell, scan_cell, scan_cell)
	var tmin := Vector2i(floori((lo.x - view_distance) / _tile_size),
			floori((lo.z - view_distance) / _tile_size))
	var tmax := Vector2i(floori((hi.x + view_distance) / _tile_size),
			floori((hi.z + view_distance) / _tile_size))

	# --- walk the box, touching no field ---------------------------------------
	# Redone from scratch every scan, and that is affordable now: this is a few
	# hundred tiles, not the fifty thousand cells the per-cell version had to
	# amortise behind a persistent sorted queue. Losing the queue loses the whole
	# class of bug where a stale entry outlives the thing it pointed at.
	#
	# NOT ONE FIELD SAMPLE HAPPENS HERE. A tile nothing is known about is judged on
	# its FLAT footprint distance, which is arithmetic on its key: true 3D distance
	# is never less than that, so a tile whose footprint is already out of range
	# cannot be in view whatever its height turns out to be. Everything past that
	# — the height probe included — belongs to the worker.
	#
	# THE VISIBLE SET IS COLLECTED IN THE SAME PASS, which is why there is no
	# separate `_emit` any more. The walk already visits every tile that can be in
	# view and already has its distance in hand, so classifying it costs a branch;
	# the old second pass instead re-walked the whole tile DICTIONARY, whose size
	# is set by how much ground has been visited rather than by how much is in
	# view. That difference is invisible while streaming keeps the dictionary
	# pruned to roughly the view — and fatal the moment the ground cover is laid
	# down up front, where it would walk every tile on the island to find the
	# hundred in front of the camera.
	_collect_done()
	var todo: Array = []
	var in_flight := 0
	var visible: Array = []
	for tz in range(tmin.y, tmax.y + 1):
		for tx in range(tmin.x, tmax.x + 1):
			var key := Vector2i(tx, tz)
			if _pending.has(key):
				in_flight += 1
				continue
			var rec = _tiles.get(key, null)
			if rec == null:
				var fd := _flat_dist_sq(key, lo, hi)
				if fd <= view_sq:
					todo.append([fd, key])
				continue
			var d := _tile_dist_sq(key, rec, lo, hi)
			if rec.has("bufs"):
				if d <= view_sq:
					visible.append(rec["bufs"])
				continue
			# Probed but not meshed: the camera was too high, or too far, when the
			# worker looked. Now it knows the tile's real height band.
			if d <= view_sq:
				todo.append([d, key])
	_box_min = tmin
	_box_max = tmax
	_box_valid = true

	# --- hand the nearest of them to a worker ----------------------------------
	var cap := maxi(max_eval_per_scan if budget < 0 else budget, 1)
	var per := maxi(tile_cells, 1) * maxi(tile_cells, 1)
	var spent := 0
	var left := in_flight
	if not todo.is_empty():
		todo.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(todo.size()):
			var key: Vector2i = todo[i][1]
			if use_threads:
				if _pending.size() >= maxi(max_in_flight, 1):
					left += todo.size() - i
					break
				_pending[key] = WorkerThreadPool.add_task(
						_tile_task.bind(key, _origin_offset, lo, hi), false,
						"grass tile %d,%d" % [key.x, key.y])
				left += 1
			else:
				if spent >= cap:
					left += todo.size() - i
					break
				_install_tile(_tile_work(key, _field, _origin_offset, lo, hi))
				spent += per
	_todo = left
	if left > 0:
		# Keep going next frame past the scan-cell gate, so a parked camera still
		# fills its field in.
		_force_rescan = true

	_fill(visible)
	_update_bounds(lo - _origin_offset, hi - _origin_offset)

	_prune_tick += 1
	if _prune_tick >= 8:
		_prune_tick = 0
		_prune_tiles()


# Place a tile in space without meshing it: the field's height at its four corners
# and its centre, widened by half a tile for whatever the ground does between
# them. FIVE samples against the 256 a mesh costs, which is what lets a worker
# dismiss a tile the camera is too high above without meshing it.
#
# The corners matter, not just the centre. This island has cliffs a hundred metres
# tall, and a tile straddling one has ground at the camera's feet AND ground far
# below; a centre probe alone would put the whole tile at one of those heights and
# could dismiss it while the player stands on it.
func _probe_tile(key: Vector2i, f: IslandField) -> Vector2:
	var x0 := float(key.x) * _tile_size
	var z0 := float(key.y) * _tile_size
	var lo := INF
	var hi := -INF
	for p in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			Vector2(1.0, 1.0), Vector2(0.5, 0.5)]:
		var h := float(f.sample(x0 + p.x * _tile_size,
				z0 + p.y * _tile_size).get("height", 0.0))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var slack := _tile_size * 0.5
	return Vector2(lo - slack, hi + slack)


# The lattice cell an eye falls in. Only meaningful when `scan_cell` > 0; the
# gate in `_process` checks that before comparing.
func _scan_cell(eye: Vector3) -> Vector3i:
	var q := maxf(scan_cell, 0.001)
	return Vector3i(floori(eye.x / q), floori(eye.y / q), floori(eye.z / q))


# Squared 3D distance between a tile's BOX — its logical footprint by its height
# band — and the SCAN CELL's box. Zero where they overlap, so a camera standing on
# a tile always matches it.
#
# Box to box rather than box to point, and that is the whole quantisation: the
# answer is then valid for every eye position the cell contains, which is exactly
# the set of positions that will be skipped before the next scan. Widening a
# radius by the cell diagonal instead would be conservative too, but bluntly so —
# it would pad every axis by the diagonal where this pads each one by only as much
# as that axis actually needs.
func _tile_dist_sq(key: Vector2i, rec: Dictionary, lo: Vector3, hi: Vector3) -> float:
	return _band_dist_sq(key, float(rec["y0"]), float(rec["y1"]), lo, hi)


func _band_dist_sq(key: Vector2i, y0: float, y1: float, lo: Vector3,
		hi: Vector3) -> float:
	var dy := maxf(maxf(y0 - hi.y, lo.y - y1), 0.0)
	return _flat_dist_sq(key, lo, hi) + dy * dy


# The same thing with the height thrown away — a lower bound on the 3D distance
# that costs no field sample, so it can be applied to a tile nothing is known
# about yet.
func _flat_dist_sq(key: Vector2i, lo: Vector3, hi: Vector3) -> float:
	var x0 := float(key.x) * _tile_size
	var z0 := float(key.y) * _tile_size
	var dx := maxf(maxf(x0 - hi.x, lo.x - x0 - _tile_size), 0.0)
	var dz := maxf(maxf(z0 - hi.z, lo.z - z0 - _tile_size), 0.0)
	return dx * dx + dz * dz


# ------------------------------------------------------------ worker payload

# Borrow a prepared field. Thread-safe; the caller owns it exclusively until it
# hands it back to `_release_field`.
func _take_field() -> IslandField:
	_pool_mutex.lock()
	var f: IslandField = _field_pool.pop_back() if not _field_pool.is_empty() else null
	_pool_mutex.unlock()
	# Cloning outside the lock: it is the slow part, and holding the mutex across
	# it would serialise exactly the threads this exists to keep apart.
	return f if f != null else _field.clone()


func _release_field(f: IslandField) -> void:
	_pool_mutex.lock()
	_field_pool.append(f)
	_pool_mutex.unlock()


# Runs on a worker thread. Touches only the `IslandField` it has borrowed, the
# node's read-only placement exports, and the mutex-guarded result list — no scene
# tree, no MultiMesh, no engine singletons.
func _tile_task(key: Vector2i, off: Vector3, lo: Vector3, hi: Vector3) -> void:
	var f := _take_field()
	var out := _tile_work(key, f, off, lo, hi)
	_release_field(f)
	_done_mutex.lock()
	_done.append(out)
	_done_mutex.unlock()


# Probe the tile, and mesh it if the probe says it is in range. Both halves are
# field sampling, so both belong on whatever thread called this; the main thread
# only ever sees the finished dictionary.
#
# `lo`/`hi` are the scan cell the task was handed out from, which is a frame or
# two stale by the time this runs. That is fine — it decides whether to mesh, and
# a tile wrongly deferred is picked up by the next scan with its real height band
# now known.
func _tile_work(key: Vector2i, f: IslandField, off: Vector3, lo: Vector3,
		hi: Vector3) -> Dictionary:
	var band := _probe_tile(key, f)
	if _band_dist_sq(key, band.x, band.y, lo, hi) > view_distance * view_distance:
		return {"key": key, "y0": band.x, "y1": band.y}
	return _build_tile(key, f, off, band)


# Evaluate every cell of a tile once and pack the survivors into one finished
# instance buffer per sprite variant, in the render space `off` describes. A pure
# function of (key, field, off), which is what makes it safe to run anywhere.
func _build_tile(key: Vector2i, f: IslandField, off: Vector3, band: Vector2) -> Dictionary:
	var n := _meshes.size()
	var lists: Array = []
	for i in range(n):
		lists.append([])
	var y0 := INF
	var y1 := -INF
	var side := maxi(tile_cells, 1)
	var base := key * side
	for dz in range(side):
		for dx in range(side):
			var r := _evaluate_cell(Vector2i(base.x + dx, base.y + dz), f)
			if not r["valid"]:
				continue
			var v: int = r["variant"]
			if v >= n:
				continue
			(lists[v] as Array).append(r)
			var y: float = (r["pos"] as Vector3).y
			y0 = minf(y0, y)
			y1 = maxf(y1, y)
	var bufs: Array = []
	for i in range(n):
		bufs.append(_pack_tile(lists[i], off))
	# Tighten the probe's estimate to the tufts that actually stand here. A tile
	# that grew none keeps the estimate: it emits nothing either way, and INF in
	# the band would poison `_tile_dist_sq`.
	if y1 < y0:
		y0 = band.x
		y1 = band.y
	return {"key": key, "bufs": bufs, "y0": y0, "y1": y1, "off": off}


# Move finished tiles from the worker list into the tile table. Called at the top
# of every scan.
func _collect_done() -> void:
	_done_mutex.lock()
	var batch: Array = _done
	_done = []
	_done_mutex.unlock()
	for r in batch:
		_install_tile(r)


func _install_tile(r: Dictionary) -> void:
	var key: Vector2i = r["key"]
	_pending.erase(key)
	var rec: Dictionary = _tiles.get(key, {})
	_tiles[key] = rec
	rec["y0"] = r["y0"]
	rec["y1"] = r["y1"]
	if not r.has("bufs"):
		return   # probed only: out of range when the worker looked
	var bufs: Array = r["bufs"]
	# A rebase landed while this tile was on a worker, so it was packed against an
	# origin the world has since moved off. Three floats an instance puts it right,
	# which beats throwing away a tile's worth of field samples.
	var drift: Vector3 = (r["off"] as Vector3) - _origin_offset
	if drift != Vector3.ZERO:
		_shift_bufs(bufs, drift)
	rec["bufs"] = bufs


# Pack one variant's tufts into a MultiMesh instance buffer. The array is a local
# with a single reference, so `resize` once and write by index is an in-place fill
# rather than a copy per element.
func _pack_tile(items: Array, off: Vector3) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(items.size() * _STRIDE)
	var k := 0
	for r in items:
		var b: Basis = r["basis"]
		var o: Vector3 = (r["pos"] as Vector3) - off
		buf[k] = b.x.x
		buf[k + 1] = b.y.x
		buf[k + 2] = b.z.x
		buf[k + 3] = o.x
		buf[k + 4] = b.x.y
		buf[k + 5] = b.y.y
		buf[k + 6] = b.z.y
		buf[k + 7] = o.y
		buf[k + 8] = b.x.z
		buf[k + 9] = b.y.z
		buf[k + 10] = b.z.z
		buf[k + 11] = o.z
		# Custom-data vec4: .x is the tuft's crater burn, .yzw reserved (0, already
		# zero-filled by `resize`). .x always needs a write or a tuft inherits the last.
		buf[k + _CUSTOM_OFF] = float(r.get("burn", 0.0))
		k += _STRIDE
	return buf


# Concatenate the visible tiles' buffers into each MultiMesh. One pass per sprite
# variant, each accumulating into a LOCAL array: `append_array` on a packed array
# with one reference is a memcpy onto the end, whereas appending into an array
# held inside another array would copy the whole thing on every tile.
#
# `visible` is collected by the box walk in `_rescan` rather than by a second pass
# over the tile dictionary — see the note there for why that distinction decides
# whether the ground cover can be laid down up front.
func _fill(visible: Array) -> void:
	for i in range(_meshes.size()):
		var out := PackedFloat32Array()
		for bufs in visible:
			out.append_array((bufs as Array)[i])
		var mm: MultiMesh = _meshes[i]
		mm.instance_count = out.size() / _STRIDE
		if not out.is_empty():
			mm.buffer = out


# Recentre each MultiMesh's cull box on the SCAN CELL (render space): the
# instances cluster around the camera rather than the render origin, so a box
# pinned to the origin would frustum-cull the whole field the moment the camera
# looked away. Sized off the cell rather than the eye for the same reason
# everything else here is — it has to stay right for every eye the cell holds.
func _update_bounds(lo: Vector3, hi: Vector3) -> void:
	var r := Vector3.ONE * (view_distance + 8.0)
	for inst in _instances:
		if inst != null:
			inst.custom_aabb = AABB(lo - r, (hi - lo) + r * 2.0)


# Forget tiles outside the scanned box plus a margin. Bounded by the TILE box
# rather than by a radius, which is what keeps the invariant simple: every tile in
# the box is known, and nothing in the box is ever dropped, so a tile can never be
# evicted and immediately re-meshed.
func _prune_tiles() -> void:
	if not _box_valid:
		return
	var m := int(ceil(keep_margin / _tile_size)) + 1
	var lo := _box_min - Vector2i(m, m)
	var hi := _box_max + Vector2i(m, m)
	var drop: Array = []
	for key in _tiles:
		if key.x < lo.x or key.x > hi.x or key.y < lo.y or key.y > hi.y:
			drop.append(key)
	for key in drop:
		_tiles.erase(key)


## Tufts currently standing. Handy for debug overlays.
func live_tuft_count() -> int:
	var n := 0
	for mm in _meshes:
		n += mm.instance_count
	return n


## Tiles held, and how many of them are meshed. Handy for debug overlays, and for
## the tests that assert the streaming actually streams.
func tile_counts() -> Vector2i:
	var built := 0
	for key in _tiles:
		if (_tiles[key] as Dictionary).has("bufs"):
			built += 1
	return Vector2i(_tiles.size(), built)


## Tiles in view that still owe work — 0 once the field around the camera is
## complete. Handy for debug overlays and for tests that wait the fill out.
func pending_tiles() -> int:
	return _todo


# A worker holds a reference to this node's method, so leaving the tree while one
# is in flight is a use-after-free waiting to happen. Wait them out; they are one
# tile of arithmetic each, so this is milliseconds, not a stall.
func _exit_tree() -> void:
	for key in _pending:
		var id: int = _pending[key]
		if id >= 0:
			WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()
	_done_mutex.lock()
	_done = []
	_done_mutex.unlock()


# ---------------------------------------------------------------- prefilling

## One slice of the up-front fill, driven by `SCRIPT_world_loading_screen.gd` so the
## ground cover is already down when the screen lifts rather than sprouting around
## the player over the first second of play. True when there is no more to do.
func prefill_step() -> bool:
	if not _ready_ok:
		return _field == null or sprites.is_empty() or material == null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	_rescan(cam.global_position + _origin_offset, maxi(prefill_eval_per_step, 1))
	_prefill_total = maxi(_prefill_total, _todo)
	return _todo <= 0


## 0..1 across the up-front fill, for a progress bar.
func prefill_ratio() -> float:
	if _prefill_total <= 0:
		return 1.0 if _ready_ok else 0.0
	return clampf(1.0 - float(_todo) / float(_prefill_total), 0.0, 1.0)


## As `veg_scatter.prefill_label()`, for `SCRIPT_world_loading_screen.gd`.
##
## SILENT UNTIL THERE IS SOMETHING TO SAY. The grass only ever streams the ~90 m
## around the camera, and W2 spawns 240 m up and 650 m off the coast, so there is
## genuinely no ground in range for the whole load: a truthful "0 tufts" would sit
## under the bar the entire time and read as a broken counter rather than as a
## camera that is nowhere near any grass. An empty string drops the line instead.
func prefill_label() -> String:
	var n := live_tuft_count()
	return "" if n <= 0 else "%s tufts down" % _thousands(n)


# Local by design — see the twin in `SCRIPT_veg_scatter.gd`.
static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


# Decide whether a cell grows a tuft, and which sprite. Pure function of the cell
# and the field, so it is stable across visits and across a rebase — and so it can
# run on a worker thread, which is why the field is a parameter rather than the
# node's own: a worker gets its own clone.
func _evaluate_cell(cell: Vector2i, f: IslandField) -> Dictionary:
	var hx := _hash(cell.x, cell.y, f.world_seed ^ 0x62A551)
	var keep := _rand(hx, 1)

	# The density roll's ceiling, tested BEFORE the field is touched. The roll below
	# is `density` scaled by two factors that are each at most 1 — how much of the
	# ground is turf, and how far the canopy has thinned it — so `density` is an
	# upper bound on it and a cell that fails against that fails whatever the
	# ground turns out to be.
	#
	# Exactly equivalent, not an approximation: the same cells grow the same tufts.
	# Worth having because the sample is the ENTIRE cost of this function —
	# `IslandField.sample` is ~0.15 ms against a few dozen hashed arithmetic ops —
	# and at the shipped 0.85 it skips 15% of cells outright.
	if keep > density:
		return {"valid": false}

	var jx := (_rand(hx, 2) - 0.5) * 0.9 * grass_grid
	var jz := (_rand(hx, 3) - 0.5) * 0.9 * grass_grid
	var wx := (float(cell.x) + 0.5) * grass_grid + jx
	var wz := (float(cell.y) + 0.5) * grass_grid + jz

	var s := f.sample(wx, wz)
	if not s.get("on_land", false):
		return {"valid": false}
	# Nothing grows out of scree or a bunker.
	var surf: String = s.get("surface", "")
	if surf == "rock" or surf == "sand":
		return {"valid": false}
	if s.get("slope", 1.0) > max_slope:
		return {"valid": false}
	if s.get("flatten", 1.0) > max_flatten:
		return {"valid": false}
	# The ruin's clearing — see `ruin_grass_keep`. Its own lane (7), clear of the
	# six this function already rolls on, so whether a tuft survives the clearing
	# says nothing about how big it is or which sprite it drew.
	var rw := clampf(float(s.get("ruin", 0.0)), 0.0, 1.0)
	if rw > 0.0:
		var clear := smoothstep(maxf(ruin_grass_keep - ruin_grass_band, 0.0),
				ruin_grass_keep, rw)
		if clear > 0.0 and _rand(hx, 7) < clear * ruin_clearing:
			return {"valid": false}
	var w: Color = s.get("weights", Color(0, 0, 0, 0))
	# Weighted by how much of the ground is actually turf, so tufts thin out into
	# soil and litter rather than stopping at a line.
	var want := density * clampf(w.r * 1.4, 0.0, 1.0)
	want *= lerpf(1.0, 1.0 - clampf(s.get("forest", 0.0), 0.0, 1.0), forest_falloff)
	if keep > want:
		return {"valid": false}

	var scale := lerpf(min_scale, max_scale, _rand(hx, 4))
	return {
		"valid": true,
		"pos": Vector3(wx, s["height"], wz),
		# Y-billboards ignore yaw, so scale is the whole basis. Width is jittered
		# independently of height so a field does not read as one sprite resized.
		"basis": Basis.IDENTITY.scaled(
				Vector3(scale * lerpf(0.85, 1.15, _rand(hx, 6)), scale, scale)),
		"variant": int(_rand(hx, 5) * float(maxi(_meshes.size(), 1))) % maxi(_meshes.size(), 1),
		# How burnt this tuft looks, off the same remap and the same weight as the ground
		# under it, scaled by `crater_burn_peak` for the same reason `veg_scatter` scales
		# it: 1.0 in the shader is FINISHED, not "most burnt", and a tuft pinned there is
		# cold stubble in a fire. 0 off a crash site. `splat_weights` has already thinned
		# the grass channel across the crater, so what survives to carry this is the
		# sparse tuft in the collar — and it burns with the trees rather than staying a
		# green lawn under them. Into `INSTANCE_CUSTOM.x` via `_pack_tile`.
		"burn": f.crater_burn(clampf(float(s.get("crater", 0.0)), 0.0, 1.0))
				* crater_burn_peak,
	}


# ---- deterministic hashing (no engine RNG, so revisit/rebase stable) ----------
# Identical to `SCRIPT_veg_scatter.gd`'s, salted differently, so the two scatters draw
# from the same construction without correlating: a cell that grows a fir is not
# thereby a cell that grows grass.

static func _hash(a: int, b: int, salt: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _rand(base: int, lane: int) -> float:
	var h := _hash(base, lane * 2654435761, 0x9E3779B9)
	return float(h % 1000003) / 1000003.0
