extends Node3D

# Streams the island field around the camera: decides what should exist, gets it
# meshed on worker threads, and swaps the results in without hitching.
#
# LOD IS PER CHUNK, with one exception that carries the whole design.
#
# Per-chunk LOD is forced on us by the hub island. An island's LOD used to be a
# single value, which was cheap and seam-free — but stand on a 2.5 km landmass
# and the distance to it is zero, so the entire thing would try to mesh at 2 m
# spacing: millions of triangles and a multi-second build. Chunks have to pick
# their own detail.
#
# That reintroduces the seam problem, and it comes in two very different sizes:
#
#   * A HEIGHT mismatch along a shared edge. The LOD grids nest, so both chunks
#     agree on the points they share; the finer one just has extra vertices in
#     between that follow the ground while the coarser cuts straight across. Gap
#     is centimetres to a metre or two, and the skirt in `SCRIPT_chunk_mesher.gd`
#     covers it completely.
#
#   * A CONTOUR mismatch, where the coastline itself lands in a different place
#     at two resolutions. This one is not survivable: the cliff hangs off the
#     coastline, so a few metres of disagreement opens a slit running hundreds of
#     metres down the cliff face, with sky visible through it.
#
# So: every chunk that contains coastline is pinned to `coast_lod` regardless of
# distance, and only chunks that are certainly inland float their LOD. That costs
# less than it sounds, because the shore ramp drives terrain relief to zero at
# the coastline — the ground there is nearly flat, so sampling it coarsely loses
# almost nothing. A chunk with no coastline is entirely land, so its edges are
# solid ground and the skirt is always enough where it meets a pinned neighbour.
#
# Coordinates: like `SCRIPT_infinite_islands.gd`, islands are keyed and generated in a
# stable LOGICAL frame, while nodes are placed at `logical - _origin_offset` so
# the rendered world stays near the origin for float precision. This node joins
# "origin_shiftable" so `SCRIPT_floating_origin.gd` hands it each rebase directly.
#
# BUILDING UP FRONT is the alternative to streaming it in, and there are two
# flavours of it, both driven by the same lane machinery at the bottom of this
# file:
#
#   * PREWARM (`prewarm`, what SCENE_test_zone_W2 uses) keeps everything above.
#     The LOD ladder still runs, chunks still swap level as you move — but every
#     level of every chunk is meshed behind the loading screen and kept, so a
#     swap is a node exchange rather than a build. Nothing is ever meshed while
#     the player is on the ground.
#
#   * PREGENERATION (`pregenerate`) throws the ladder away instead: one uniform
#     resolution world-wide, so no chunk can ever want rebuilding. Simpler, and
#     much heavier to draw — see that export's own note.
#
# Both are bounded-world features. Do not turn either on for an endless field.

const ChunkMesher := preload("res://godot/island/scripts/world/SCRIPT_chunk_mesher.gd")

## Emitted while `prewarm` or `pregenerate` is building the world, for a loading
## screen to draw. `stage` is "survey" / "build"; `done` and `total` count BUILD
## JOBS, which under `pregenerate` is one per chunk and under `prewarm` is one per
## chunk per LOD level. Both are 0 during survey, which is over in a frame or two.
signal pregen_progress(stage: String, done: int, total: int)
## Emitted once, when the world built up front is complete and on screen.
signal pregen_finished()

## Probe resolution used to decide whether a chunk holds coastline. Must be fine
## enough that a shoreline dipping into a chunk and back out cannot slip between
## samples — i.e. finer than `IslandField.coast_noise_scale`.
const _COAST_PROBE := 9

@export var field: IslandField
@export var terrain_material: Material
## Optional separate material for the plunging cliff walls. When null the walls
## share `terrain_material` (the stock behaviour every other scene relies on).
## SCENE_test_zone_W2 sets this to `MAT_cliff_wall.tres`, which is the terrain's
## own rock channel plus a dissolve — see `SHADER_cliff_wall.gdshader` for why the two
## have to be the same rock rather than merely similar.
##
## NOTE this is the WALL only. The rounded shoulder between the plateau and the
## wall is part of the walkable surface mesh and is drawn by `terrain_material`;
## that is the whole point of where `chunk_mesher._build_rim` splits them.
@export var cliff_material: Material
## Metres below the shore past which a wall band is BUILT BUT NEVER DRAWN.
##
## The hub's wall is vertical for its whole built height and is sliced off at the
## fog floor 600 m down, while `MAT_cliff_wall.tres` has faded it to nothing by
## 330. Everything between those two figures is geometry that cannot be seen from
## any angle under any conditions — a little over half the wall, and on a scene
## that was submitting the whole sweep whenever a rim chunk was on screen, it was
## being drawn every frame.
##
## BUILT, not skipped, and the distinction is the point: the faces still go into
## the chunk's collider, so an aircraft flying up under an island still hits the
## underside. Only `visible` is cleared. Skipping the geometry outright would
## save the memory and open a hole in the world.
##
## Must sit at or past the material's `fade_end`, or the deepest drawn band ends
## at a hard horizontal edge instead of dithering out.
##
## IT NEVER FIRES ON THE W2 HUB, and that is worth knowing before tuning it. A
## band is only cleared when its TOP is deeper than this, and the hub's wall is
## cut into just two bands — `IslandField.cliff_wall_bands` asks for 4 but
## `chunk_mesher._wall_bands` clamps it to `wr / 2`, and the hub's adaptive ring
## count is 4. Measured across all 128 coastal chunks: band 0 spans 18-191 m
## below the shore and band 1 spans 191-600 m, so neither top ever passes 340 and
## both are always drawn — including the 330-600 m of band 1 that
## `MAT_cliff_wall.tres` has already faded to nothing.
##
## SPLITTING BAND 1 TO FIX THAT WOULD SAVE NOTHING, which is why it has not been
## done: three bands with the deepest cleared still draws two per chunk, so the
## draw call count is identical and the win is ~20k of the frame's ~995k
## triangles. The knob earns its keep on a preset with a deeper or straighter
## cliff, where `wr` is high enough to buy real bands.
@export var cliff_visible_depth := 340.0

@export_group("Shadows")
## Whether the plunging cliff walls are submitted to the SHADOW pass.
##
## OFF, because on an island in a void there is nothing under the shore for a
## wall to cast onto. The wall hangs BELOW the coastline on the outside of a
## convex disc, and a shadow only ever travels downward and outward from it — it
## cannot reach the plateau, which is above and inward, and it cannot reach the
## far rim, which by then is hundreds of metres higher than the ray. The one
## surface beneath the shore that could receive is `SCRIPT_cloud_sea.gd`'s deck at
## `sea_altitude` (-45 m in W2), and the terrain's own edge already casts onto
## exactly that band: from the shore at y=0 to the deck at y=-45 with the sun 17.6
## degrees up is 142 m of throw, and the wall's contribution starts at the same
## rim and lands inside it.
##
## MEASURED at the two viewpoints `tests/PROBE_draw_calls.gd` stands at, with
## nothing else changed: 1,118 -> 907 draw calls on the ridge (-19%) and 381 ->
## 255 standing inland (-33%). It is the largest single cut in the scene because
## the wall is cut into bands (see `chunk_mesher._wall_bands`) and EVERY band was
## being submitted once per PSSM split it touched.
##
## Turn it back on for a world where the ground continues below the shoreline —
## a wall standing on a seabed rather than hanging over a void has something to
## cast onto and this is then a real shadow to lose.
@export var cliff_cast_shadows := false
## LOD level at and past which a chunk's walkable surface stops casting shadows.
## -1 (the default) keeps every level casting, which is the stock behaviour.
##
## The LOD ladder is already a distance classification — `lod_distances` puts
## level 2 past 400 m and level 3 past 900 m — so this rides it for free rather
## than adding a second distance test. It is also STABLE across LOD swaps without
## any bookkeeping, because `_install` caches one node per (chunk, resolution):
## a node built at level 3 is only ever shown when that chunk is far away, so the
## flag set at construction stays correct for the node's whole life.
##
## COASTAL CHUNKS ARE EXEMPT — they are pinned to `coast_lod` by GEOMETRY rather
## than by distance, so their level says nothing about how far away they are. See
## `_node_from_built`, which is also why `coast_lod` (2) does not make a
## `terrain_shadow_lod` of 2 silently un-shadow the shoreline you are standing
## on. That trap is the reason this reads a level rather than a metre figure and
## still has to special-case one.
##
## LEFT OFF BY DEFAULT, and it is the biggest lever here, which is exactly why.
## `tests/PROBE_draw_calls.gd` measures it on the ridge at 741 -> 601 for level 3
## and 741 -> 480 for level 2 — the latter more than the shadow reach and the
## cliff walls put together, and it works at any reach. What it spends is real
## though: a chunk at level 2 is only 400 m out, where 62% of a shadow's contrast
## still survives the fog (34% at level 3's 900 m), and what is lost is the dark
## side of every middle-distance hill. On a stylised island under a 17.6 degree
## sun that is most of what makes the ground read as shaped rather than painted.
##
## So: the reach cut in SCENE_test_zone_W2 is the honest way to lose far shadows,
## and this is the blunt one, kept for the machine that still cannot hold a frame
## after the honest cuts are in.
@export var terrain_shadow_lod := -1

@export_group("Streaming")
## Islands and chunks are generated within this radius of the camera, in metres.
@export var view_distance := 2800.0
## Extra distance kept before something is freed (hysteresis against thrash).
@export var keep_margin := 400.0
## Chunks handed to the scene per frame. Each upload builds an ArrayMesh and adds
## a node, so keeping this low is what stops the hitch.
@export var max_uploads_per_frame := 4
## Frames between LOD re-evaluations. The scan walks every candidate chunk of
## every island in range, so spreading it out keeps it off the frame budget.
@export var rescan_interval := 2
## Chunk builds allowed in flight at once.
##
## This is a priority mechanism, not just a throttle. The hub alone offers ~400
## chunks; handing them all to the pool at once means it works through them in
## submission order, and the ground under your feet waits behind hundreds of
## chunks on the far rim. Capping in-flight work lets each scan re-sort by
## distance and feed the pool nearest-first.
@export var max_in_flight := 12
## Mesh on worker threads. Turn off to debug generation on the main thread —
## the code path is otherwise identical.
@export var use_threads := true

@export_group("Detail")
## World size of one chunk, in metres. Constant across LODs.
@export var chunk_size := 128.0
## Grid cells per chunk at LOD 0. Halved per LOD level, floored at `min_chunk_cells`.
## This is the master terrain-density dial: LOD n runs at `chunk_cells >> n`, so
## lowering it thins LOD 0 and every coarser level in turn. Keep it divisible by
## 2^N for the deepest LOD level N you stream (a plain power of two is the easy way)
## so the LOD grids nest — each level stays an exact half of the one above, a coarse
## chunk's vertices remain a subset of its finer neighbour's, and the shared edges
## stay seam-free.
##
## 64 puts LOD 0 on a 2 m grid at the stock 128 m chunk. It went to 128 (1 m) to
## give the deepened bunkers something to be carved into, and came straight back:
## a 128-cell chunk is 32k triangles, four times a 64-cell one, and the ring of
## them around the camera dominated the frame's budget on its own. 2 m is still
## half `IslandField.curvature_radius`, so a 34 m bunker is seventeen vertices
## across — the depth reads fine, it never needed metre spacing.
@export var chunk_cells := 64
## Floor on per-chunk grid cells at the coarsest LODs. Once `chunk_cells >> n`
## reaches this, further levels stop thinning, so a distant chunk keeps a little
## shape instead of collapsing toward a single flat quad. Also a power of two for
## the same nesting reason; the mesher clamps to at least 1 regardless. Every
## scene leaves it at 4 today — drop it only for terrain meant to keep shedding
## triangles past the level where `chunk_cells >> n` reaches 4.
@export var min_chunk_cells := 4
## Upper distance bound for each LOD level; beyond the last entry the coarsest
## level is used. Must be ascending.
##
##     LOD      0     1     2     3     4+
##     cells   64    32    16     8      4
##     metres   2     4     8    16     32
##     to (m) 160   400   900  1800   beyond
##
## Tighter at the near end than the 400 m LOD 0 ring this started with. That
## number was set when LOD 0 was the only level anyone stood in; with the ladder
## carrying real cost now, the 2 m grid is worth paying for the ground under your
## feet and not much past it. The far rungs are close to where they always were.
@export var lod_distances := PackedFloat32Array([160.0, 400.0, 900.0, 1800.0])
## Fraction a chunk must overshoot a threshold by before it changes level, so a
## chunk sitting on a boundary doesn't rebuild every time you sway.
@export_range(0.0, 0.5) var lod_hysteresis := 0.12
## Fixed LOD for every chunk holding coastline — see the header. 2 is 8 m contour
## resolution at the default chunk size and `chunk_cells`. Dropping it to 1
## doubles the triangles in the rim ring, which on the hub is most of its
## geometry, and the ring is pinned by GEOMETRY rather than by distance — every
## chunk in it pays whatever this says, everywhere, forever. That makes it the
## single most expensive number in this group and the first one to check when the
## triangle count is too high.
@export var coast_lod := 2

@export_group("Prewarm")
## Mesh every LOD of every chunk before play starts, and keep them.
##
## This is pregeneration WITHOUT giving up the LOD ladder, and it is what
## SCENE_test_zone_W2 runs. The survey, the mesher and the uploads are the ones
## the streamer already uses; the difference is that the work list is every
## (chunk, LOD level) pair in range rather than the handful the camera wants this
## instant, and that finished chunks go into a per-island CACHE instead of being
## installed and forgotten.
##
## Afterwards the streamer runs exactly as it always did — `_scan` still walks the
## ladder, chunks still coarsen and refine as you move — but `_queue_build` finds
## every level already in the cache, so a level change is `remove_child` /
## `add_child` and no meshing happens at all. That is the whole point: the ladder
## is what keeps the triangle count down, and the cache is what stops it costing
## anything at run time.
##
## Only for a bounded world. W2 is one hub island in a void, so "every LOD of all
## of it" is ~1300 meshes; an endless field has no such number.
@export var prewarm := false
## Ceiling on cached chunk geometry, in megabytes of vertex data. 0 — the default
## — removes the cap, which is what makes the guarantee above absolute: every LOD
## of every chunk exists before the loading screen lifts and nothing is ever
## meshed again.
##
## The tail of the list is what a cap cuts, and the list is ordered so the tail is
## the least valuable: the level each chunk needs at `pregen_anchor` is built
## first (and is never refused, whatever the budget says), then the spare levels
## coarsest-first. Anything skipped is still built on demand by the streamer and
## cached when it lands, so a tight budget costs hitches rather than correctness.
##
## THE FINEST LEVEL IS ALMOST ALL OF IT, which is what this number is really for.
## Caching every level of every chunk on W2's hub is 5.86M vertices, and LOD 0
## alone is 4.3M of them — 64x64 cells on all 356 inland chunks, whether or not
## you ever stand on one. Every coarser level put together is 1.5M. Measured on
## the reference container, headless, four cores:
##
##     budget    load    memory   meshing after load
##     0 (off)   20.4 s  396 MB   none at all
##     96 MB      7.6 s  ~100 MB  136 frames, worst 1.1 s
##
## So the cap is the dial for a machine that cannot spare the memory, and it buys
## its way out with exactly the hitches prewarming exists to remove. Leave it at 0
## unless something is actually short.
@export var prewarm_budget_mb := 0.0

@export_group("Pregeneration")
## Build the entire world up front instead of streaming it in around the camera.
##
## Every island within `view_distance` of `pregen_anchor` is meshed before play
## starts, at ONE uniform resolution (`pregen_cells`), with collision on every
## chunk. Nothing is ever rebuilt, re-LODded or freed afterwards, so the streamer
## costs nothing per frame and there is no hitch to hide.
##
## Two consequences worth knowing:
##
##   * Uniform resolution retires the whole per-chunk LOD problem. `coast_lod`,
##     `lod_distances` and `lod_hysteresis` are unused here: with one cell count
##     across the world no two chunks can disagree about where the coastline is,
##     so the CONTOUR mismatch this file's header is mostly about cannot happen.
##   * It only suits a bounded world. W2 is one hub island in a void, so "all of
##     it" is 484 chunks. Do NOT turn this on for an endless field.
##
## OFF EVERYWHERE, AND SUPERSEDED BY `prewarm`. Uniform resolution means the LOD
## ladder above never runs at all: every chunk in the world, including the far rim
## you are looking at across 2.5 km, carries the same grid as the ground under
## your feet. On W2 that was measured at ~2.2M triangles sitting still. `prewarm`
## gets the same hitch-free world without that bill, because it builds the ladder
## rather than replacing it — prefer it for anything new.
##
## The code path is kept and still tested — `tests/TEST_world_pregen.gd` turns it
## on explicitly — so a bounded scene that genuinely wants one flat resolution can
## still have it. When both flags are set this one wins.
@export var pregenerate := false
## Grid cells per chunk for every pregenerated chunk. The one detail dial: chunk
## surfaces come out at `chunk_size / pregen_cells` metre vertex spacing, world
## wide. Powers of two are not required (nothing has to nest here), but keeping it
## at or above `chunk_size / IslandField.curvature_radius` is worth real time —
## at that point the curvature probe in `SCRIPT_chunk_mesher.gd` switches off and reads
## its neighbours off the grid instead, which more than pays for the extra
## vertices. On W2's 128 m chunks and 4 m curvature radius that threshold is 32.
##
## 32 IS THAT THRESHOLD, and it is where this now sits (it was 12). Measured on
## the reference machine 32 builds the whole hub in 4.0 s against 6.7 s at 24,
## despite carrying 1.6x the triangles, for exactly that reason. Two things
## needed it: `IslandField.sand_depth` wanted a bunker eight vertices across
## rather than three, and the terrain is smooth-shaded now, so the coarse grid
## that used to be half of the deliberate low-poly look no longer buys anything.
## Depth has since come DOWN to 1.4 m, which only slackens the first of those —
## a shallower dish needs fewer vertices to curve, not more — while the curvature
## threshold above, which is the reason this is 32 rather than 24, is untouched
## by it.
@export var pregen_cells := 32
## Where LOD-independent range tests are measured from, in LOGICAL space. Islands
## within `view_distance` of this are built. Defaults to the scene's camera
## position when left at zero and a camera exists.
@export var pregen_anchor := Vector3.ZERO
## Chunk builds in flight during pregeneration. 0 auto-tunes it by measuring
## actual throughput as it builds — see `_pregen_retune`. Set it explicitly only
## to pin a machine down for a measurement.
@export var pregen_workers := 0
## Finished chunks turned into nodes per frame while pregenerating. Uploads are
## main-thread work; this is what keeps the loading screen animating rather than
## locking up while the meshes land.
@export var pregen_installs_per_frame := 24

## Reuse meshed chunks across SCENE LOADS, through the `TerrainBake` autoload.
##
## THE ENCOUNTER LOOP IS WHY. Touching a roaming pack swaps this scene out for
## the battle and winning swaps it back, so the island is built again from
## nothing on the walk home — measured, W3 prewarms the same 1,328 chunk meshes
## for the same 415 MB on the way back as on the way in. The chunk cache this
## node keeps is instance state and dies with the scene; the bake outlives it.
##
## Safe because it is keyed on everything the geometry is a function of, so a
## world built from different settings can never adopt another's chunks — see
## `AUTOLOAD_terrain_bake.gd:signature_of`, which hashes the generating code's
## own sources as well as the settings, so an edit to the mesher invalidates the
## store without anybody having to notice.
##
## COSTS ALMOST NOTHING TO KEEP, because what it holds is what this node holds
## anyway: the ArrayMeshes and shapes the store keeps are the SAME objects the
## installed chunks point at, not copies of them. The store only becomes the sole
## owner once the scene goes down.
##
## OFF FOR AN ENDLESS WORLD, all the same. The store has no cap, and on a
## pregenerated zone it does not need one — `PROBE_bake_footprint.gd` walks 3.1 km
## across W3 and it does not gain a chunk, there being nothing left to ask for. A
## field that streamed forever would grow it without limit and would want a budget
## here before it wanted this at all.
@export var bake_cache := true

@export_group("Collision")
@export var generate_collision := true
## Chunks within this distance get a body covering the surface AND the cliff, so
## aircraft hit an island from any angle including underneath. Well beyond the
## LOD 0 ring on purpose: fast movers would otherwise outrun the streaming and
## fly through terrain that had not been given collision yet.
@export var collision_distance := 1400.0
## LOD swaps per scan that are allowed to move a collision body into or out of the
## scene tree. See `_scan`, which is where the rationing happens and why.
##
## Low on purpose. Everything else the streamer does after a prewarm is free — a
## cached node, a reparent — but handing the physics server a fresh
## ConcavePolygonShape3D is not, and it is not made cheaper by having built the
## shape earlier. Raising this trades frame time for how fast collision catches up
## with a fast mover; the geometry is right either way, it just arrives a scan or
## two later.
@export var collision_swaps_per_scan := 2

# Vector2i lattice cell -> island state (see `_ensure_island`).
var _islands := {}
# "cx,cz,ci,cj" -> WorkerThreadPool task id (or -1 when synchronous).
var _pending := {}
# Finished chunk builds waiting to become nodes. Written by worker threads.
var _done: Array = []
var _done_mutex := Mutex.new()

# Idle `IslandField.clone()`s, handed out one per running build task.
#
# A worker needs a field nobody else is touching, and the obvious way to get one
# — clone it in the task — turns out to cost about four times what the meshing
# itself does. `clone()` is a deep `duplicate()` plus eight fresh FastNoiseLites,
# and, worse, the clone arrives with an empty island cache, so every chunk
# re-rolls the island's whole zone layout (`IslandField._place_zones`, which is
# a 40-attempt rejection sampler for the golf holes and build pads) before it can
# mesh a single vertex. Measured on the W2 hub: 4828 ms to mesh the island with a
# clone per chunk, 1205 ms reusing prepared fields.
#
# Pooling keeps the isolation guarantee exactly as it was — a field is held by at
# most one task at a time, so nothing is shared while it is in use — and the pool
# settles at however many builds actually run concurrently.
var _field_pool: Array = []
var _pool_mutex := Mutex.new()

var _origin_offset := Vector3.ZERO
var _frame := 0

## Where this world's terrain came from, as `open_with_disk` answered: `"memory"`
## when the last scene left a store behind, the bake's path when it was read off
## disk, and `""` when there was nothing and every chunk has to be meshed.
##
## READ BY THE LOADING SCREEN, which otherwise says GENERATING TERRAIN over a
## world it is not generating. That is not cosmetic. A screen that says the same
## thing whether it is doing ninety seconds of work or two is a screen that
## cannot be used to tell those apart, and "it regenerates the world after every
## battle" is exactly the conclusion somebody draws from watching it — correctly,
## from the only evidence the game offers them.
var bake_source := ""

# --- up-front build state (unused unless `prewarm` or `pregenerate`) ---
enum _Pregen { OFF, START, SURVEY, BUILD, DONE }
var _pg := _Pregen.OFF
## Vertices cached so far, against `prewarm_budget_mb`. Written by lanes under
## `_pg_cursor_mutex`, since that is what decides whether the next job runs.
var _pg_verts := 0
var _pg_budget_verts := 0
## The generation signature this node opened `TerrainBake` with, or "" when
## `bake_cache` is off. Held only so the two mesher call sites can tell whether
## the store is theirs to read without asking the autoload every chunk.
var _bake_sig := ""
var _pg_skipped := 0
var _pg_anchor := Vector3.ZERO
var _pg_cells: Array = []      ## Lattice cells left to survey.
## {cell, ck, dist, rank, cells, lod, install} per build. One entry per chunk
## under `pregenerate`, one per chunk PER LOD LEVEL under `prewarm`.
var _pg_jobs: Array = []
var _pg_next := 0              ## Shared cursor into `_pg_jobs`; lanes pull from it.
var _pg_cursor_mutex := Mutex.new()
var _pg_installed := 0
var _pg_started_ms := 0
## Lanes run on THREADS OF THEIR OWN rather than on `WorkerThreadPool` — see
## `SCRIPT_build_lanes.gd`, which is entirely about why.
var _pg_lanes := BuildLanes.new("pregen lane")
var _pg_lanes_live := 0        ## Lanes still running. Guarded by `_pg_cursor_mutex`.
# Throughput tuning. See `_pregen_retune` for why this is measured and not
# derived from the core count.
var _pg_width := 2             ## Lanes that should be running right now.
var _pg_cap := 2               ## Ceiling on that.
var _pg_climbing := true
var _pg_best_rate := 0.0
var _pg_best_width := 2
var _pg_window_left := 0
var _pg_window_us := 0
var _pg_warmup := 0             ## Chunks to discard before the next timed window.


func _ready() -> void:
	add_to_group("origin_shiftable")
	if field == null:
		# Fall back to stock settings rather than rendering nothing — dropping this
		# node into a scene should just work, with `data/ISLANDFIELD_default.tres`
		# as the thing you assign when you want to tune it.
		field = IslandField.new()
	field.prepare()
	if bake_cache:
		# Opened before anything can be meshed. `open_with_disk` adopts a store
		# built from the same settings — from memory when the last scene left one
		# there, from a file `TOOL_bake_world.gd` wrote when it did not — and
		# throws away one that was not. So a scene that comes back to a world it
		# has already built starts full, a cold start on a pre-baked zone starts
		# full, and a scene that changed a setting or the mesher starts empty.
		_bake_sig = TerrainBake.signature_of([field, _bake_mesh_params()])
		bake_source = TerrainBake.open_with_disk(TerrainBake.STORE_NAME, _bake_sig)
	if pregenerate or prewarm:
		# Deferred to the first `_process` so the scene's camera has run its own
		# `_ready` — `pregen_anchor` defaults to wherever it is standing.
		_pg = _Pregen.START


func _exit_tree() -> void:
	# Worker tasks read `_pg_jobs` and write into `_done`; let them finish before
	# this node and its state go away.
	for key in _pending:
		var id: int = _pending[key]
		if id >= 0:
			WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()
	# Retire every pregeneration lane, then wait it out. Setting the width to zero
	# first is what makes this bounded: a lane checks it before taking another
	# chunk, so the wait is one chunk long rather than however much of the island
	# is left.
	_pg_cursor_mutex.lock()
	_pg_width = 0
	_pg_cursor_mutex.unlock()
	_pg_lanes.join()
	# Cached chunks that never went into the tree have no parent to free them.
	for cell in _islands.keys():
		_free_island(cell)


# The rendered world has been rebased. Slide the built islands so they stay put
# on screen, and fold the shift into the logical offset so lattice cells — which
# are derived from logical coordinates — are untouched.
func apply_origin_shift(shift: Vector3) -> void:
	for cell in _islands:
		# Variant, then validated, then typed — see SCRIPT_glitch_blob_scatter._reap.
		var entry: Variant = _islands[cell]["holder"]
		if is_instance_valid(entry):
			(entry as Node3D).position += shift
	_origin_offset -= shift


func _process(_delta: float) -> void:
	if field == null:
		return
	if _pg != _Pregen.OFF and _pg != _Pregen.DONE:
		# Building up front. Nothing streams until the loading screen is ready to
		# lift, or the two would be dispatching against each other.
		_pregen_step()
		return
	if pregenerate:
		# A pregenerated world is finished and static. Once built there is nothing
		# to scan, re-LOD or free, so this node drops to zero per-frame cost.
		#
		# A PREWARMED one falls through to the streamer instead, which is the whole
		# difference between the two: the ladder still has to run, it just never has
		# to mesh anything to obey it.
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position + _origin_offset

	_frame += 1
	if _frame % maxi(rescan_interval, 1) == 0:
		_scan(eye)
		_free_out_of_range(eye)
	_drain_results()


# ------------------------------------------------------------------ scanning

func _scan(eye: Vector3) -> void:
	var spacing := field.island_spacing
	var reach := view_distance + field.world_max_radius()
	var c0 := Vector2i(floori((eye.x - reach) / spacing), floori((eye.z - reach) / spacing))
	var c1 := Vector2i(floori((eye.x + reach) / spacing), floori((eye.z + reach) / spacing))

	# Collect everything that wants (re)building, then dispatch NEAREST FIRST.
	# Deciding and dispatching in one pass would submit in whatever order the
	# chunks happen to be enumerated, which on a 2.5 km island means the far rim
	# can be queued ahead of the ground you are standing on.
	var wanted: Array = []
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cz)
			var isl := field.island_in_cell(cell)
			if isl == null:
				continue
			if _island_distance(isl, eye) > view_distance:
				continue
			_scan_island(_ensure_island(cell, isl), eye, wanted)

	var slots := maxi(0, max_in_flight - _pending.size())
	if slots == 0 or wanted.is_empty():
		return
	wanted.sort_custom(func(a, b): return a["dist"] < b["dist"])
	# Swaps that move a COLLISION body in or out of the tree are rationed
	# separately, because they are the only ones whose cost is not the mesh.
	#
	# On a prewarmed world every install is a cache hit, so a scan can hand the
	# frame a dozen finished chunk nodes for nothing — except that adding a
	# StaticBody3D carrying an 8,000-triangle ConcavePolygonShape3D makes the
	# physics server do real work, and it is FIRST-TOUCH work, so prewarming does
	# not pay it down. Measured walking the hub: a burst of these was a 64 ms
	# frame while the rest of the streamer ran in 3. Spread over scans it is
	# several ordinary frames instead of one dropped one.
	var col_left := maxi(collision_swaps_per_scan, 1)
	var used := 0
	for w in wanted:
		if used >= slots:
			break
		# Both ends count: the outgoing node's body leaves the tree as the
		# incoming one's joins it.
		if bool(w["col"]) or bool(w["had_col"]):
			if col_left <= 0:
				continue   # next scan; a chunk showing last frame's LOD is fine
			col_left -= 1
		_queue_build(w["pk"], w["cell"], w["ck"], w["lod"], w["col"])
		used += 1


# Create the per-island bookkeeping, including the ONE-TIME classification of
# which chunks hold land and which hold coastline. Both are pure functions of
# geometry rather than of the camera, so they never need recomputing — which
# matters, since the coastline probe is the expensive part of this whole file.
func _ensure_island(cell: Vector2i, isl: IslandField.Island) -> Dictionary:
	if _islands.has(cell):
		return _islands[cell]

	var extent := field.island_extent(isl)
	var base_x := isl.center.x - extent
	var base_z := isl.center.y - extent
	var nx := maxi(1, ceili(extent * 2.0 / chunk_size))

	var holder := Node3D.new()
	holder.name = "Island_%d_%d" % [cell.x, cell.y]
	# Meshes are emitted relative to the island's centre axis, so the holder
	# carries it out to its logical position in the current render frame.
	var pivot := Vector3(isl.center.x, isl.base_y, isl.center.y)
	holder.position = pivot - _origin_offset
	add_child(holder)

	var land := {}
	for j in range(nx):
		for i in range(nx):
			var x0 := base_x + float(i) * chunk_size
			var z0 := base_z + float(j) * chunk_size
			var x1 := x0 + chunk_size
			var z1 := z0 + chunk_size
			if not field.rect_touches_island(isl, x0, z0, x1, z1):
				continue
			# Cheap annulus test first; only probe the ones it can't rule out.
			var coastal := false
			if field.rect_touches_coast(isl, x0, z0, x1, z1):
				coastal = _probe_coast(isl, x0, z0, x1, z1)
			land[Vector2i(i, j)] = coastal

	# "ckx,cky@cells" -> the MeshInstance3D for that chunk at that resolution, or
	# null when the chunk meshes to nothing there. Entries are built once and kept
	# for the life of the island; the live ones are children of `holder` and the
	# rest sit out of the tree costing nothing but their buffers.
	#
	# The null entries are not an optimisation, they are a CORRECTNESS FIX. A
	# quarter of the hub's surveyed chunks (116 of 484) are footprint corners that
	# `rect_touches_island` keeps against the bounding disc and the mask then finds
	# to be all void. Until this cache existed, a void result installed no node and
	# left nothing behind saying so, so the very next `_scan` asked for it again.
	# They are also the chunks nearest the W2 spawn camera, so nearest-first
	# dispatch handed them every in-flight slot in perpetuity: measured, the world
	# stalled at 2 chunks of 484 and stayed there for as long as you cared to watch.
	var state := {
		"isl": isl, "pivot": pivot, "base_x": base_x, "base_z": base_z,
		"nx": nx, "holder": holder, "land": land, "chunks": {}, "cache": {},
	}
	_islands[cell] = state
	return state


# True if the mask changes sign anywhere across the rect — i.e. the coastline
# passes through it. Sampled on a grid rather than at the corners because a
# shoreline can enter and leave through the same edge.
func _probe_coast(isl: IslandField.Island, x0: float, z0: float,
		x1: float, z1: float) -> bool:
	var any_land := false
	var any_void := false
	for j in range(_COAST_PROBE):
		var z: float = lerpf(z0, z1, float(j) / float(_COAST_PROBE - 1))
		for i in range(_COAST_PROBE):
			var x: float = lerpf(x0, x1, float(i) / float(_COAST_PROBE - 1))
			if field.mask_for(isl, x, z) > 0.0:
				any_land = true
			else:
				any_void = true
			if any_land and any_void:
				return true
	return false


func _scan_island(state: Dictionary, eye: Vector3, wanted: Array) -> void:
	var cell: Vector2i = state["isl"].cell
	var base_x: float = state["base_x"]
	var base_z: float = state["base_z"]
	var isl: IslandField.Island = state["isl"]
	var chunks: Dictionary = state["chunks"]
	var cutoff := view_distance + keep_margin

	for key in state["land"]:
		var ck: Vector2i = key
		var coastal: bool = state["land"][key]
		var x0 := base_x + float(ck.x) * chunk_size
		var z0 := base_z + float(ck.y) * chunk_size
		var dist := _rect_distance(x0, z0, x0 + chunk_size, z0 + chunk_size,
				isl.base_y, eye)

		var live: Dictionary = chunks.get(ck, {})

		if dist > cutoff:
			# A single island can be wider than the view distance, so its far side
			# is dropped like any other out-of-range geometry. Out of the TREE, not
			# freed — the cache owns it, and a chunk that scrolls out of range is
			# exactly the one you are about to scroll back into.
			if not live.is_empty():
				# Variant, then validated, then typed — see SCRIPT_glitch_blob_scatter._reap.
				var entry: Variant = live["node"]
				if is_instance_valid(entry):
					var node: Node3D = entry
					if node.get_parent() != null:
						node.get_parent().remove_child(node)
				chunks.erase(ck)
			continue

		var lod: int = coast_lod if coastal else _lod_for(dist, live.get("lod", -1))
		var want_col := _collides_at(lod)
		if not live.is_empty() and live["lod"] == lod:
			continue

		var pk := "%d,%d,%d,%d" % [cell.x, cell.y, ck.x, ck.y]
		if _pending.has(pk):
			continue
		wanted.append({"dist": dist, "pk": pk, "cell": cell, "ck": ck,
				"lod": lod, "col": want_col,
				"had_col": bool(live.get("collision", false))})


# Distance from the eye to the nearest point of a chunk's footprint, taking the
# island's altitude as the chunk's Y. Using the footprint rather than its centre
# stops a chunk you are standing on from being scored as if it were 90 m away.
func _rect_distance(x0: float, z0: float, x1: float, z1: float,
		base_y: float, eye: Vector3) -> float:
	var dx := eye.x - clampf(eye.x, x0, x1)
	var dz := eye.z - clampf(eye.z, z0, z1)
	var dy := eye.y - base_y
	return sqrt(dx * dx + dz * dz + dy * dy)


func _island_distance(isl: IslandField.Island, eye: Vector3) -> float:
	var flat := Vector2(eye.x, eye.z).distance_to(isl.center)
	var dy := absf(eye.y - isl.base_y)
	return Vector2(maxf(flat - isl.radius, 0.0), dy).length()


# LOD for a distance, biased to hold whatever level the chunk already has. A
# chunk only coarsens once it is clearly past a threshold and only refines once
# it is clearly inside one, so drifting along a boundary doesn't churn rebuilds.
func _lod_for(dist: float, current: int) -> int:
	var n := lod_distances.size()
	for i in range(n):
		var edge := lod_distances[i]
		if current >= 0:
			if current <= i:
				edge *= 1.0 + lod_hysteresis   # already fine here: resist coarsening
			else:
				edge *= 1.0 - lod_hysteresis   # already coarse: resist refining
		if dist <= edge:
			return i
	return n


func _cells_for_lod(lod: int) -> int:
	return maxi(maxi(min_chunk_cells, 1), chunk_cells >> lod)


# Does a chunk at this LOD level carry a collision body?
#
# This used to be `dist <= collision_distance`, measured per chunk per scan, and
# that rule fights the cache: a chunk crossing the collision radius wants the same
# mesh with a body bolted onto it, which means either a second cached variant of
# every chunk or a rebuild — and a rebuild is the one thing prewarming exists to
# abolish. LOD level is itself a function of distance, so deciding on the level
# says almost the same thing one step coarser, and it makes a chunk's collision
# state fixed at build time: cache it once, install it anywhere.
#
# "Almost", because a level spans a band of distances and only its NEAR edge is
# tested. At the stock ladder that rounds one way exactly once — chunks at level 3
# keep collision out to 1800 m rather than losing it at 1400 — which costs a ring
# of 8-cell shapes and buys fast movers a little more margin.
func _collides_at(lod: int) -> bool:
	if not generate_collision:
		return false
	if lod < 0:
		return true   # pregeneration: one level, every chunk, always
	if lod == 0 or lod_distances.is_empty():
		return true
	return lod_distances[mini(lod, lod_distances.size()) - 1] < collision_distance


## This node's contribution to the bake signature: the settings of ITS OWN that
## change what a chunk contains.
##
## IT IS ONE NUMBER, and that is not an oversight. `ChunkMesher.build` is handed
## the field, the island, the chunk's corner, `chunk_size`, `cells` and the
## pivot — and every one of those but `chunk_size` is either derived from the
## field (which is hashed whole) or already written into the bake key
## (`TerrainBake.key_for` carries the cell, the chunk and the resolution). So
## `chunk_size` is the entire remainder.
##
## THE LOD LADDER IS DELIBERATELY ABSENT. `chunk_cells`, `min_chunk_cells`,
## `lod_distances` and `coast_lod` decide WHICH resolutions get built and when
## they are swapped, never what a chunk at a given resolution looks like — and
## the resolution is in the key. Hashing them would throw the whole store away
## every time somebody nudged a swap distance, for a rebuild that would produce
## the same vertices it just discarded.
func _bake_mesh_params() -> Dictionary:
	return {"chunk_size": chunk_size}


# --- chunk cache ---
#
# Keyed on resolution rather than on LOD level, because `coast_lod` and the ladder
# can name the same cell count and there is no reason to mesh it twice.

func _cache_key(ck: Vector2i, cells: int) -> String:
	return "%d,%d@%d" % [ck.x, ck.y, cells]


func _cache_has(cell: Vector2i, ck: Vector2i, cells: int) -> bool:
	if not _islands.has(cell):
		return false
	return (_islands[cell]["cache"] as Dictionary).has(_cache_key(ck, cells))


func _queue_build(pk: String, cell: Vector2i, ck: Vector2i, lod: int,
		want_col: bool, cells := -1) -> void:
	# `cells` overrides the LOD ladder, which is how pregeneration builds every
	# chunk in the world at one resolution. `lod` stays the bookkeeping key.
	var n: int = cells if cells > 0 else _cells_for_lod(lod)
	# Already meshed at this resolution — including "meshed to nothing". Install it
	# straight away rather than paying a worker and a frame of latency to be told
	# the same thing again. After a prewarm this is the ONLY path the streamer ever
	# takes, which is what makes an LOD change free.
	if _cache_has(cell, ck, n):
		_install({"pk": pk, "cell": cell, "ck": ck, "lod": lod, "cells": n,
				"collision": want_col, "res": {}})
		return
	if use_threads:
		_pending[pk] = WorkerThreadPool.add_task(
				_build_task.bind(pk, cell, ck, lod, n, want_col), false,
				"chunk %s cells %d" % [pk, n])
	else:
		_pending[pk] = -1
		_build_task(pk, cell, ck, lod, n, want_col)


# ------------------------------------------------------------ worker payload

# Borrow a prepared field. Thread-safe; the caller owns it exclusively until it
# hands it back to `_release_field`.
func _take_field() -> IslandField:
	_pool_mutex.lock()
	var f: IslandField = _field_pool.pop_back() if not _field_pool.is_empty() else null
	_pool_mutex.unlock()
	# Cloning outside the lock: it is the slow part, and holding the mutex across
	# it would serialise exactly the threads this exists to keep apart.
	return f if f != null else field.clone()


func _release_field(f: IslandField) -> void:
	_pool_mutex.lock()
	_field_pool.append(f)
	_pool_mutex.unlock()


# Runs on a worker thread (or inline when `use_threads` is off). Touches only the
# `IslandField` it has borrowed from the pool and the mutex-guarded result list —
# no scene tree, no engine singletons.
func _build_task(pk: String, cell: Vector2i, ck: Vector2i, lod: int, cells: int,
		want_col: bool) -> void:
	var res := {}
	# THE BAKE FIRST. A chunk this world has already built — in this scene or in
	# one before it — needs no mesher at all: `_install` instances the resources
	# the store kept. Asked HERE rather than at install time because skipping the
	# worker's whole payload is the point; the answer is a yes/no because the
	# resources themselves are only ever touched on the main thread.
	var bkey := TerrainBake.key_for(cell, ck, cells, want_col)
	var baked := _bake_sig != "" and TerrainBake.peek(bkey) != TerrainBake.MISS
	if not baked:
		# The field is borrowed INSIDE the miss, not above it. A borrow from an
		# empty pool is a `field.clone()`, and on a re-entry every one of these
		# tasks is a hit — cloning a field per hit would put back a slice of the
		# cost the hit is there to remove.
		var f := _take_field()
		var isl := f.island_in_cell(cell)
		if isl != null:
			var extent := f.island_extent(isl)
			var pivot := Vector3(isl.center.x, isl.base_y, isl.center.y)
			res = ChunkMesher.build(f, isl, isl.center.x - extent, isl.center.y - extent,
					ck.x, ck.y, chunk_size, cells, pivot)
			if not res.is_empty() and want_col:
				# Surface AND every wall band, so an aircraft flying up under an
				# island hits the underside instead of passing through it. EVERY
				# band, including the deep ones the frustum test throws away:
				# culling decides what is DRAWN, and a collider that only exists
				# where you can see it is worse than none at all.
				var faces := _faces_of(res["top"])
				for band in (res["cliff_bands"] as Array):
					faces.append_array(_faces_of(band["arrays"]))
				res["faces"] = faces
		_release_field(f)

	_done_mutex.lock()
	_done.append({"pk": pk, "cell": cell, "ck": ck, "lod": lod, "cells": cells,
			"collision": want_col, "res": res, "baked": baked})
	_done_mutex.unlock()


# Indexed surface arrays -> the flat triangle soup ConcavePolygonShape3D wants.
# Done here rather than via `ArrayMesh.create_trimesh_shape()` so the cost lands
# on the worker thread instead of the frame that uploads the mesh.
static func _faces_of(surface: Array) -> PackedVector3Array:
	var verts: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	out.resize(idx.size())
	for i in range(idx.size()):
		out[i] = verts[idx[i]]
	return out


# ------------------------------------------------------------------- uploads

func _drain_results() -> void:
	var batch: Array = []
	_done_mutex.lock()
	while not _done.is_empty() and batch.size() < max_uploads_per_frame:
		batch.append(_done.pop_front())
	_done_mutex.unlock()

	for entry in batch:
		var pk: String = entry["pk"]
		if _pending.has(pk):
			var id: int = _pending[pk]
			if id >= 0:
				WorkerThreadPool.wait_for_task_completion(id)
			_pending.erase(pk)
		_install(entry)


# Turn a finished build into a cache entry, and — unless the entry says otherwise
# — into the chunk the island is currently showing.
#
# `entry["cells"]` is the cache key; `entry["res"]` is empty both when the chunk
# meshed to nothing AND when the caller already found it cached, so the cache is
# consulted before the arrays are.
func _install(entry: Dictionary) -> void:
	var cell: Vector2i = entry["cell"]
	if not _islands.has(cell):
		return   # island was freed while this was in flight
	var state: Dictionary = _islands[cell]
	var chunks: Dictionary = state["chunks"]
	var cache: Dictionary = state["cache"]
	var ck: Vector2i = entry["ck"]
	var res: Dictionary = entry["res"]
	var cells: int = entry.get("cells", _cells_for_lod(entry["lod"]))
	var key := _cache_key(ck, cells)

	# Build the replacement before dropping the old one, so an LOD swap never
	# shows a frame of empty sky where the ground was.
	var node: MeshInstance3D = null
	if cache.has(key):
		node = cache[key]
	else:
		node = _chunk_for(entry, res, cells)
		# Stored even when null: "this chunk is void at this resolution" is a real
		# answer and the streamer has to be able to remember it. See `_ensure_island`.
		cache[key] = node

	if entry.get("cache_only", false):
		return

	var old = chunks.get(ck, {}).get("node", null)
	if old != null and is_instance_valid(old) and old != node:
		# Out of the tree, NOT freed — the cache still owns it, and the point of
		# holding it is that coming back to this level costs nothing.
		(state["holder"] as Node3D).remove_child(old)
	chunks.erase(ck)

	if node == null:
		# Void chunks are recorded too, or `_scan` re-requests them every pass and
		# the nearest ones starve everything behind them.
		chunks[ck] = {"node": null, "lod": entry["lod"], "collision": false}
		return
	if node.get_parent() == null:
		(state["holder"] as Node3D).add_child(node)
	chunks[ck] = {"node": node, "lod": entry["lod"], "collision": entry["collision"]}


# The node for a finished build, from whichever half of the chunk cache holds it.
#
# Two ways in, meeting here. `entry["baked"]` means `TerrainBake` answered and the
# mesher never ran, so the resources come straight back out of it. Otherwise the
# mesher's arrays are turned into resources — and this being the only place a
# chunk is ever built, that is where the store is filled.
#
# Reached from `_drain_results` on the MAIN thread, which is what makes it safe to
# create meshes and shapes here at all.
func _chunk_for(entry: Dictionary, res: Dictionary, cells: int) -> MeshInstance3D:
	var lod := int(entry["lod"])
	var bkey := TerrainBake.key_for(entry["cell"], entry["ck"], cells,
			bool(entry["collision"]))
	if bool(entry.get("baked", false)):
		# `peek` said yes on the worker; `take` is asked again here because the
		# resources are only ever touched on this thread. Empty means the chunk
		# meshes to nothing — see `TerrainBake.clear` for the one way it could
		# mean something worse, and why that cannot happen.
		var held := TerrainBake.take(bkey)
		return null if held.is_empty() else _node_from_built(held, lod)
	if res.is_empty():
		# "Meshes to nothing" is an answer in its own right and worth keeping —
		# see `AUTOLOAD_terrain_bake.gd`. Not stored when the island was freed
		# under this build, because `_install` has already returned by then.
		if _bake_sig != "":
			TerrainBake.put_empty(bkey)
		return null
	var built := TerrainBake.built_of(res)
	# Measured from the ARRAYS, before they go into mesh buffers: see `note_bytes`.
	# `put_chunk` rather than `put` so the store can keep the arrays as well when
	# it is being written to disk — see `TerrainBake.record_arrays`, which the game
	# never sets.
	if _bake_sig != "":
		TerrainBake.put_chunk(bkey, built, res, TerrainBake.note_bytes(res))
	return _node_from_built(built, lod)


# The instances, and every decision the WORLD makes rather than the mesher:
# materials, shadow casting, the depth below which a cliff band is collision only.
# All of it applied fresh on every install, from this node's own exports, so a
# material or a shadow flag can be retuned without invalidating one chunk.
#
# `lod` is taken here rather than read back off the node later because the chunk
# cache is keyed by (chunk, resolution) and a cached node is therefore bound to
# one level for its whole life. Construction is both the earliest point the level
# is known and the only one that survives an LOD swap without re-walking the tree.
func _node_from_built(built: Dictionary, lod: int = -1) -> MeshInstance3D:
	# The surface and the cliff go into SEPARATE MeshInstance3Ds, because Godot
	# frustum-culls per instance and one merged AABB would be useless.
	#
	# A cliff sweeps from the coastline down to a tip on the island's centre
	# axis, so its bounds reach from the rim to the middle of the island and
	# hundreds of metres down — measured at ~169x the volume of the chunk's own
	# footprint on the hub. Sharing one mesh meant the walkable ground inherited
	# those bounds and a rim chunk was reported visible from almost any angle.
	# Split, the ground culls on its own footprint and only the cliff carries the
	# oversized box. Surface and cliff were already two surfaces, i.e. two draw
	# calls, so this costs nothing extra to draw.
	var mi := MeshInstance3D.new()
	mi.mesh = built["mesh"]
	if terrain_material != null:
		mi.material_override = terrain_material
	# `lod` is -1 under `pregenerate`, which has no ladder at all — every chunk is
	# one uniform resolution, so there is no "far level" to single out and the
	# comparison below must not fire. -1 >= 0 is false, so it does not.
	#
	# COAST CHUNKS ARE EXEMPT, and this is the whole correctness of the export.
	# `terrain_shadow_lod` reads a chunk's LOD as a stand-in for its distance, and
	# for an inland chunk that is exactly what it is. For a coastal one it is not:
	# every chunk holding coastline is PINNED to `coast_lod` by geometry (see the
	# file header), at any range, forever. So `terrain_shadow_lod = 2` against a
	# `coast_lod` of 2 would stop the shore under the player's feet from casting —
	# not distant terrain, the ground they are standing on, and permanently.
	#
	# A chunk is coastal exactly when the mesher gave it wall bands, so the built
	# chunk can be asked directly and no flag has to be threaded down from
	# `_scan_island`.
	var bands: Array = built["bands"]
	var coastal := not bands.is_empty()
	if terrain_shadow_lod >= 0 and lod >= terrain_shadow_lod and not coastal:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ONE INSTANCE PER VERTICAL BAND. The wall is cut into stacked slices by
	# `chunk_mesher._wall_bands` for exactly this: a single sweep from the rim to
	# the tip carries an AABB tall enough to intersect the frustum from almost
	# anywhere, so the whole wall — fog floor included — was submitted whenever
	# any part of the chunk was on screen. Each band's box is a few tens of metres
	# tall, so the deep ones fail the test on their own and cost nothing.
	#
	# The extra draw calls are the price and they are the right way round: a band
	# that survives culling was going to be drawn anyway, and one that does not is
	# a call that never happens.
	var cliff_mat: Material = cliff_material if cliff_material != null else terrain_material
	for band in bands:
		var bb: AABB = band["aabb"]
		var ci := MeshInstance3D.new()
		ci.mesh = band["mesh"]
		if cliff_mat != null:
			ci.material_override = cliff_mat
		# See `cliff_cast_shadows`. Set BEFORE the `visible` decision below and
		# without consulting it — a hidden instance is already out of both passes,
		# so this is redundant for the deep collision-only bands and load-bearing
		# for every band above `cliff_visible_depth`, which on W2 is all 256 of
		# them (`tests/PROBE_draw_calls.gd` counts them).
		if not cliff_cast_shadows:
			ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Bands wholly below `cliff_visible_depth` are collision only. The pivot
		# sits at the island's `base_y`, so the band's own top in pivot space IS
		# its depth below the shore, with no island lookup needed here.
		if cliff_visible_depth > 0.0 and -(bb.position.y + bb.size.y) > cliff_visible_depth:
			ci.visible = false
		# Parented to the surface node purely so one queue_free() drops them all.
		# Culling is per VisualInstance3D and pays no attention to the parent, so
		# each band is still tested against the frustum independently.
		mi.add_child(ci)

	var shape: ConcavePolygonShape3D = built["shape"]
	if shape != null:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var body := StaticBody3D.new()
		body.add_child(cs)
		mi.add_child(body)
	return mi


# ------------------------------------------------------- building it up front

# Both up-front modes are the streaming loop with the streaming taken out: the
# same classification, the same mesher, the same uploads — but the work list is
# decided once, in full, and drained to the end instead of being re-derived from
# the camera every couple of frames. They differ only in what goes ON that list,
# which `_pregen_jobs_for` decides.
#
# It is stepped from `_process` rather than run in one blocking call so the
# loading screen keeps drawing. Nothing here ever blocks on a worker.
#
# WORK IS PULLED, NOT PUSHED. The streamer dispatches one task per chunk and tops
# the queue up from `_process`, which is fine when it is trickling a handful of
# chunks in, and useless here: a task that finishes mid-frame has to wait for the
# next frame to be given anything else, so with N tasks in flight the build can
# never exceed N chunks per frame no matter how fast the machine is. Measured, it
# capped the W2 island at ~0.6 chunks per frame and turned a 2 s build into 5.8 s.
#
# So pregeneration runs LANES instead: `_pg_width` long-lived tasks, each looping
# on a shared cursor until the list is empty. Lanes never idle, the frame rate
# stops being a throttle, and the main thread is left to do nothing but install.
func _pregen_begin() -> void:
	_pg_anchor = pregen_anchor
	if _pg_anchor == Vector3.ZERO:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_pg_anchor = cam.global_position + _origin_offset

	var spacing := field.island_spacing
	var reach := view_distance + field.world_max_radius()
	var c0 := Vector2i(floori((_pg_anchor.x - reach) / spacing),
			floori((_pg_anchor.z - reach) / spacing))
	var c1 := Vector2i(floori((_pg_anchor.x + reach) / spacing),
			floori((_pg_anchor.z + reach) / spacing))
	_pg_cells.clear()
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_pg_cells.append(Vector2i(cx, cz))

	# Width ladder. It is TUNED, not derived from the core count, because on some
	# machines the core count is an outright lie about how well this scales: chunk
	# meshing is GDScript calling GDScript, and on a dual-socket box (measured on
	# a 2x6-core Xeon E5-2630 v2) throughput peaks around three or four builds in
	# flight and then falls off a cliff — 24 concurrent builds came in SLOWER than
	# one. Pure arithmetic on the same machine scaled to 8x, so this is contention
	# inside the interpreter, not the hardware. A four-core Pi 5, meanwhile, scales
	# cleanly to four. There is no constant that is right for both, so the ladder
	# below is climbed with a stopwatch — see `_pregen_retune`.
	# One below the core count: WorkerThreadPool sizes itself the same way, and the
	# main thread still has installs and a loading screen to draw.
	_pg_cap = maxi(1, OS.get_processor_count() - 1)
	if pregen_workers > 0:
		_pg_width = mini(pregen_workers, _pg_cap)
		_pg_climbing = false
	else:
		_pg_width = mini(2, _pg_cap)
		_pg_climbing = true
	_pg_best_width = _pg_width
	_pg_best_rate = 0.0
	_pregen_window_start()
	_pg = _Pregen.SURVEY
	pregen_progress.emit("survey", 0, 0)


func _pregen_step() -> void:
	match _pg:
		_Pregen.START:
			_pregen_begin()
		_Pregen.SURVEY:
			_pregen_survey()
		_Pregen.BUILD:
			_pregen_build()


## Main-thread milliseconds the survey may spend per frame.
const _PG_SURVEY_BUDGET_MS := 4


# Classify lattice cells against a time budget rather than a fixed count.
#
# `_ensure_island`'s coastline probe is the expensive part of this whole file
# (~47 ms for the W2 hub) and it is main-thread work, so it cannot all land on one
# frame. But the overwhelming majority of cells are empty void and cost nothing to
# reject, and one-cell-per-frame would spend 144 frames — over two seconds at 60 Hz
# — walking past them. A budget does both: void flies past, land gets its frame.
func _pregen_survey() -> void:
	if not _pg_cells.is_empty():
		var deadline := Time.get_ticks_msec() + _PG_SURVEY_BUDGET_MS
		while not _pg_cells.is_empty():
			var cell: Vector2i = _pg_cells.pop_back()
			var isl := field.island_in_cell(cell)
			if isl != null and _island_distance(isl, _pg_anchor) <= view_distance:
				_pregen_jobs_for(_ensure_island(cell, isl), isl)
			# Checked AFTER the work, so an island that overruns the budget on its own
			# still completes rather than being half-classified.
			if Time.get_ticks_msec() >= deadline:
				break
		pregen_progress.emit("survey", 0, 0)
		return

	# Order of the whole list, and it is what the budget cuts against.
	#
	# `rank` first: everything the anchor actually needs on screen comes before
	# every spare level, so a budget that runs out never costs a chunk you can see
	# — only a level you might swap to later. Then nearest first within each rank,
	# so if the budget bites it bites at the far rim.
	_pg_jobs.sort_custom(func(a, b):
			if a["rank"] != b["rank"]:
				return a["rank"] < b["rank"]
			return a["dist"] < b["dist"])
	_pg_budget_verts = int(maxf(prewarm_budget_mb, 0.0) * 1.0e6 / float(_BYTES_PER_VERT))
	_pg = _Pregen.BUILD
	_pg_started_ms = Time.get_ticks_msec()
	_pregen_window_start()
	pregen_progress.emit("build", 0, _pg_jobs.size())


## Bytes of vertex data one cached vertex costs, for turning `prewarm_budget_mb`
## into a vertex count.
##
## MEASURED, not derived from the array formats. A chunk vertex carries position,
## normal, colour and two UVs, which is 52 bytes written out longhand and nothing
## like what it ends up occupying: Godot packs normals and colours, keeps its own
## index buffer, and the collision faces on top are an unindexed triangle soup.
## An uncapped prewarm of W2's hub counts 8.25M vertices and grows the process by
## 396 MB, which is where this comes from. It only has to be the right order of
## magnitude — it decides where a soft cap falls, not whether anything is correct.
const _BYTES_PER_VERT := 48


# Every (chunk, resolution) pair this island wants built up front.
#
# PREGENERATION wants one per chunk, all at `pregen_cells`, all installed.
#
# PREWARM wants one per chunk PER LOD LEVEL, because the point is that no level is
# ever meshed while the player is playing. A chunk holding coastline is pinned to
# `coast_lod` forever (see the file header) so it needs exactly one; an inland
# chunk floats across the whole ladder and needs all of them. Only the level the
# anchor calls for is installed — the rest are built straight into the cache.
func _pregen_jobs_for(state: Dictionary, isl: IslandField.Island) -> void:
	var base_x: float = state["base_x"]
	var base_z: float = state["base_z"]
	var cell: Vector2i = isl.cell
	for key in state["land"]:
		var ck: Vector2i = key
		var coastal: bool = state["land"][key]
		var x0 := base_x + float(ck.x) * chunk_size
		var z0 := base_z + float(ck.y) * chunk_size
		var dist := _rect_distance(x0, z0, x0 + chunk_size, z0 + chunk_size,
				isl.base_y, _pg_anchor)
		if not prewarm or pregenerate:
			_pg_jobs.append({"cell": cell, "ck": ck, "dist": dist, "rank": 0,
					"cells": maxi(pregen_cells, 1), "lod": -1, "install": true})
			continue

		var live_lod: int = coast_lod if coastal else _lod_for(dist, -1)
		var levels: Array = [coast_lod] if coastal else range(lod_distances.size() + 1)
		# One entry per distinct CELL COUNT, not per level: the ladder floors at
		# `min_chunk_cells`, so its coarsest levels collapse onto the same grid and
		# meshing it once is enough.
		var seen := {}
		for entry in levels:
			var lod: int = entry
			var cells := _cells_for_lod(lod)
			if seen.has(cells):
				continue
			seen[cells] = true
			# Rank 0 is what the anchor puts on screen; rank 1 is a spare level, and
			# coarse spares come first because they are the cheap ones — a full LOD 0
			# of an island nobody is standing on costs more than every other level of
			# it put together.
			_pg_jobs.append({"cell": cell, "ck": ck, "dist": dist,
					"rank": 0 if lod == live_lod else 1 + (lod_distances.size() - lod),
					"cells": cells, "lod": lod, "install": lod == live_lod})


func _pregen_build() -> void:
	_pregen_staff_lanes()

	# Install whatever the lanes have finished. Uploads are cheap (measured at 26 ms
	# for the whole W2 island) but they are main-thread work, so they are still
	# batched rather than drained flat out — that batch size is what decides
	# whether the loading screen animates or stutters.
	var batch: Array = []
	_done_mutex.lock()
	while not _done.is_empty() and batch.size() < maxi(pregen_installs_per_frame, 1):
		batch.append(_done.pop_front())
	_done_mutex.unlock()
	for entry in batch:
		if not entry.has("skipped"):
			_install(entry)
		_pg_installed += 1
	if not batch.is_empty():
		_pregen_window_tick(batch.size())
		pregen_progress.emit("build", _pg_installed, _pg_jobs.size())

	if _pg_installed < _pg_jobs.size():
		return
	_pg_cursor_mutex.lock()
	var still_running := _pg_lanes_live > 0
	_pg_cursor_mutex.unlock()
	if still_running:
		return

	# Every lane has already taken itself out of the live count, so this joins
	# threads that have returned rather than waiting on a build.
	_pg_lanes.join()
	_pg = _Pregen.DONE
	if prewarm and not pregenerate:
		print("[island_world] prewarmed %d chunk meshes across %d LOD levels in %d ms, "
				% [cached_chunk_count(), lod_distances.size() + 1,
				Time.get_ticks_msec() - _pg_started_ms]
				+ "%d lanes, %.0f MB of %.0f (%d spare levels left to the streamer)"
				% [_pg_best_width, float(_pg_verts) * _BYTES_PER_VERT / 1.0e6,
				prewarm_budget_mb, _pg_skipped])
	else:
		print("[island_world] pregenerated %d chunks at %d cells in %d ms, %d lanes" % [
				_pg_installed, maxi(pregen_cells, 1),
				Time.get_ticks_msec() - _pg_started_ms, _pg_best_width])
	pregen_progress.emit("build", _pg_installed, _pg_jobs.size())
	pregen_finished.emit()


# Bring the number of running lanes up to `_pg_width`. Shrinking is left to the
# lanes themselves — see `_pregen_lane` — so a width cut never interrupts a chunk
# that is halfway built.
func _pregen_staff_lanes() -> void:
	_pg_cursor_mutex.lock()
	# No point staffing a queue that is already empty: without this the tail of
	# the build would respawn lanes every frame just to have them exit again.
	var need := 0 if _pg_next >= _pg_jobs.size() else _pg_width - _pg_lanes_live
	if need > 0:
		_pg_lanes_live += need
	_pg_cursor_mutex.unlock()
	if use_threads:
		_pg_lanes.spawn(need, _pregen_lane)
		_pg_lanes.reap()
	else:
		for i in maxi(need, 0):
			# Debug path: builds the world in one blocking call, same code, no threads.
			_pregen_lane()


# One lane. Runs on a worker thread; pulls chunks off the shared cursor and
# meshes them until the list runs out or the lane is retired by a width cut.
# Touches only the field it has borrowed, the cursor and the result list — all
# mutex-guarded, none of it the scene tree.
#
# Retirement is by headcount rather than by lane identity: a lane that sees more
# lanes live than the current width takes itself out of the count and stops, and
# because the test and the decrement happen under one lock, exactly the surplus
# retires and the rest carry on.
func _pregen_lane() -> void:
	var f := _take_field()
	while true:
		_pg_cursor_mutex.lock()
		var i := -1
		if _pg_lanes_live <= _pg_width and _pg_next < _pg_jobs.size():
			i = _pg_next
			_pg_next += 1
		else:
			_pg_lanes_live -= 1
		_pg_cursor_mutex.unlock()
		if i < 0:
			break

		var job: Dictionary = _pg_jobs[i]
		var cell: Vector2i = job["cell"]
		var ck: Vector2i = job["ck"]
		var cells: int = job["cells"]
		var lod: int = job["lod"]
		var install: bool = job["install"]
		var want_col := _collides_at(lod)
		# Over budget: skip the mesh but still report the job, so the progress bar
		# and the completion test stay honest about how much of the list is done.
		# `install` jobs are never skipped — the budget only ever cuts spare levels,
		# and a spare level not built here is simply built by the streamer later.
		var res := {}
		# THE BAKE IS CHECKED BEFORE THE BUDGET, not after. `_pregen_take_budget`
		# rations MEMORY — vertices this build is allowed to add — and a chunk the
		# store already holds adds none, so refusing it on budget grounds would
		# skip a chunk that was free and then charge the streamer to mesh it again.
		var bkey := TerrainBake.key_for(cell, ck, cells, want_col)
		var baked := _bake_sig != "" and TerrainBake.peek(bkey) != TerrainBake.MISS
		if baked:
			pass
		elif _pregen_take_budget(cells, install):
			var isl := f.island_in_cell(cell)
			if isl != null:
				var extent := f.island_extent(isl)
				var pivot := Vector3(isl.center.x, isl.base_y, isl.center.y)
				res = ChunkMesher.build(f, isl, isl.center.x - extent, isl.center.y - extent,
						ck.x, ck.y, chunk_size, cells, pivot)
				if not res.is_empty() and want_col:
					var faces := _faces_of(res["top"])
					for band in (res["cliff_bands"] as Array):
						faces.append_array(_faces_of(band["arrays"]))
					res["faces"] = faces
		else:
			_done_mutex.lock()
			_done.append({"skipped": true})
			_done_mutex.unlock()
			continue

		_done_mutex.lock()
		# lod -1 marks "pregenerated, no LOD ladder": every chunk in the world runs
		# at `pregen_cells` and carries collision, so nothing can ever ask for a
		# rebuild later.
		_done.append({"pk": "", "cell": cell, "ck": ck, "lod": lod, "cells": cells,
				"collision": want_col, "res": res, "baked": baked,
				"cache_only": not install})
		_done_mutex.unlock()

	_release_field(f)


# Claim this chunk's share of `prewarm_budget_mb`, or refuse it.
#
# Charged BEFORE the mesh exists, from the cell count, because the alternative is
# to build it and then decide — which spends exactly the memory the budget is
# there to not spend. A full inland chunk is `4 * cells^2` surface vertices plus a
# `16 * cells` skirt; coastline chunks and clipped ones come out under that, so
# this over-charges and the cap binds early rather than late.
func _pregen_take_budget(cells: int, mandatory: bool) -> bool:
	var cost := 4 * cells * cells + 16 * cells
	_pg_cursor_mutex.lock()
	# `mandatory` is the level the anchor is showing. It is charged like anything
	# else — the running total has to stay true — but it is never refused, because
	# a budget that can blank the world on screen is a bug, not a budget.
	var ok := mandatory or _pg_budget_verts <= 0 or _pg_verts + cost <= _pg_budget_verts
	if ok:
		_pg_verts += cost
	else:
		_pg_skipped += 1
	_pg_cursor_mutex.unlock()
	return ok


# --- width tuning ---
#
# Hill-climb the lane count against measured chunks-per-second. Each rung is held
# for a window of finished chunks; if it beat the best so far the width doubles
# and the next window measures that, otherwise the best rung wins and tuning
# stops. The calibration runs on real chunks, so none of it is wasted work — it
# just means the first few dozen chunks are built at whatever width was under
# test at the time.
const _PG_WINDOW := 24
const _PG_GAIN := 1.05   ## Improvement a rung must show to justify climbing on.
## Chunks discarded after a width change before the stopwatch restarts.
##
## Not cosmetic — without it the ladder would never climb. A lane's first act is
## to borrow a field, and the first borrow at a new width finds the pool empty
## and has to `clone()`, which then re-rolls the island's zone layout on that
## lane's first chunk. That startup lands entirely inside the window measuring
## the wider setting, so every rung is charged for the cost of reaching it and
## looks worse than the rung below.
const _PG_WARMUP := 8

func _pregen_window_start() -> void:
	_pg_window_left = _PG_WINDOW
	_pg_window_us = Time.get_ticks_usec()


func _pregen_window_tick(installed: int) -> void:
	if not _pg_climbing:
		return
	if _pg_warmup > 0:
		_pg_warmup -= installed
		if _pg_warmup <= 0:
			_pregen_window_start()
		return
	_pg_window_left -= installed
	if _pg_window_left > 0:
		return
	var elapsed := maxi(Time.get_ticks_usec() - _pg_window_us, 1)
	var done := _PG_WINDOW - _pg_window_left
	_pregen_retune(float(done) * 1.0e6 / float(elapsed))
	_pregen_window_start()


func _pregen_retune(rate: float) -> void:
	var next := _pg_width
	if rate > _pg_best_rate * _PG_GAIN:
		_pg_best_rate = rate
		_pg_best_width = _pg_width
		if _pg_width < _pg_cap:
			# Roughly x1.5 rather than doubling. The optimum is often three or four
			# lanes on the machines that need this most, and a doubling ladder steps
			# straight over both.
			next = mini(maxi(_pg_width + 1, (_pg_width * 3) / 2), _pg_cap)
		else:
			_pg_climbing = false   # ceiling reached, and it was the best rung
	else:
		# This rung was no better than the last. Settle on the winner.
		next = _pg_best_width
		_pg_climbing = false
	if next != _pg_width:
		_pg_warmup = _PG_WARMUP
	# Lanes read the width to decide whether to retire, so publish it under the
	# same lock they take.
	_pg_cursor_mutex.lock()
	_pg_width = next
	_pg_cursor_mutex.unlock()


# ---------------------------------------------------------------------- free

func _free_out_of_range(eye: Vector3) -> void:
	if prewarm:
		# A prewarmed world is built once, in full, behind a loading screen. Freeing
		# any of it means rebuilding it in front of the player later, which is the
		# one thing this mode promises not to do — and on W2 the whole island would
		# go at once, because it is a single island and the test below is per island.
		return
	var cutoff := view_distance + keep_margin
	var drop: Array = []
	for cell in _islands:
		var isl := field.island_in_cell(cell)
		if isl == null or _island_distance(isl, eye) > cutoff:
			drop.append(cell)
	for cell in drop:
		_free_island(cell)


# Drop an island and everything it owns. The cache has to be walked explicitly:
# its entries are deliberately OUT of the tree, so freeing the holder — which is
# all this used to do — would take the live chunk and leak every other level of it.
func _free_island(cell: Vector2i) -> void:
	var state: Dictionary = _islands[cell]
	var cache: Dictionary = state["cache"]
	for key in cache:
		# Variant, then validated, then typed — see SCRIPT_glitch_blob_scatter._reap.
		var entry: Variant = cache[key]
		if is_instance_valid(entry):
			var node: MeshInstance3D = entry
			if node.get_parent() == null:
				node.free()
	cache.clear()
	var holder_entry: Variant = state["holder"]
	if is_instance_valid(holder_entry):
		(holder_entry as Node3D).queue_free()
	_islands.erase(cell)


# ------------------------------------------------------------------ gameplay

## Query the terrain under a RENDER-space position (a node's `global_position`),
## converting to the logical frame the field works in. See `IslandField.sample`
## for the returned fields. Use this for ball friction, hole and tee placement,
## or anything else that needs to know what surface is underfoot.
func sample_at(render_pos: Vector3) -> Dictionary:
	if field == null:
		return {"on_land": false}
	return field.sample(render_pos.x + _origin_offset.x, render_pos.z + _origin_offset.z)


## Surface height in RENDER space under a position, or `fallback` over the void.
func height_at(render_pos: Vector3, fallback := -1e9) -> float:
	var s := sample_at(render_pos)
	if not s["on_land"]:
		return fallback
	return s["height"] - _origin_offset.y


## Is there LAND under this render-space position? The landmass mask alone — see
## `IslandField.is_land` for why that is a query worth having separately from
## `sample_at`, and what it is for. Cheap enough to ask about a ring of points,
## which is how `SCRIPT_glitch_blob_roamer.gd` keeps a wander target a stated
## number of metres inside the coastline instead of merely on the near side of it.
func is_land(render_pos: Vector3) -> bool:
	if field == null:
		return false
	return field.is_land(render_pos.x + _origin_offset.x, render_pos.z + _origin_offset.z)


## Is this render-space position flat cleared ground the player may build on?
## True only on a build pad's core — its banks and every golf zone report false.
func is_buildable(render_pos: Vector3) -> bool:
	var s := sample_at(render_pos)
	return s["on_land"] and s.get("buildable", false)


## Holes with a tee or pin within `radius` of a render-space position, nearest
## tee first. Each entry is a Dictionary rather than the raw `IslandField.Hole`
## so callers get tee and pin already converted into RENDER space, which is the
## frame a marker node or a HUD distance has to be placed in:
##
##   id, index, par, length : as on the hole
##   par_source             : which level of the golf config made that par
##   tee, pin               : Vector3 on the ground, render space
##   bend                   : Vector3 on the ground, render space — the dogleg's
##                            elbow, or the tee/pin midpoint on a straight hole
##   bent                   : whether `bend` is a real elbow or the fallback
##   width                  : fairway half-width, metres
func holes_near(render_pos: Vector3, radius := 2000.0) -> Array:
	if field == null:
		return []
	var lx := render_pos.x + _origin_offset.x
	var lz := render_pos.z + _origin_offset.z
	var out: Array = []
	for entry in field.holes_near(lx, lz, radius):
		out.append(_hole_view(entry))
	return out


## The nearest playable hole to a render-space position, or {} if none is in
## range. The starting point for "walk up to any island and play it".
func nearest_hole(render_pos: Vector3, radius := 2000.0) -> Dictionary:
	if field == null:
		return {}
	var h := field.nearest_hole(render_pos.x + _origin_offset.x,
			render_pos.z + _origin_offset.z, radius)
	return {} if h == null else _hole_view(h)


func _hole_view(h: IslandField.Hole) -> Dictionary:
	return {
		"id": h.id,
		"index": h.index,
		"par": h.par,
		# Which of the config's three levels made that par -- a `GolfConfig`
		# `PAR_FROM_*` string. A HUD can ignore it; a scorecard that wants to mark
		# a hole the rules did not really score cannot get it any other way once
		# the hole has left the field.
		"par_source": h.par_source,
		"length": h.length,
		"width": h.width,
		"tee": field.hole_tee(h) - _origin_offset,
		"pin": field.hole_pin(h) - _origin_offset,
		# The dogleg's elbow, on the ground like the other two. Always present and
		# always ON the axis — `hole_bend` falls back to the midpoint — so a caller
		# can build the two-segment axis unconditionally and let `bent` decide
		# whether the second segment is worth the arithmetic.
		"bend": field.hole_bend(h) - _origin_offset,
		"bent": h.bent,
	}


## The par system in force on the island nearest a render-space position, or the
## world-wide one when no course is in range — see `IslandField.golf_config_for`,
## and `SCRIPT_golf_config.gd` for what it answers.
##
## Null only before a field is assigned, which is the same "the world is not up
## yet" answer every other query on this node gives; a world that HAS a field
## always has a par system.
func golf_config_at(render_pos: Vector3, radius := 2000.0) -> GolfConfig:
	if field == null:
		return null
	var h := field.nearest_hole(render_pos.x + _origin_offset.x,
			render_pos.z + _origin_offset.z, radius)
	if h == null:
		return field.global_golf_config()
	return field.golf_config_for(field.island_for_cell(h.cell))


## Total par of the course nearest a render-space position, or 0 if none is in
## range. The bottom line of the scorecard, in the frame the HUD already works in.
func course_par(render_pos: Vector3, radius := 2000.0) -> int:
	if field == null:
		return 0
	return field.course_par_near(render_pos.x + _origin_offset.x,
			render_pos.z + _origin_offset.z, radius)


## The field this world streams. Shared, prepared instance — read-only for callers
## like the tree scatter, which sample it on the main thread alongside `_process`.
func get_field() -> IslandField:
	return field


## Logical = render + this. The tree scatter mirrors `island_world`'s own frame so
## its trees stay pinned to the ground across a floating-origin rebase.
func origin_offset() -> Vector3:
	return _origin_offset


## Islands currently streamed in. Handy for debug overlays.
func live_island_count() -> int:
	return _islands.size()


## Chunks currently on screen across all islands. Chunks known to be void are
## tracked alongside them but are not counted here — they have no node.
func live_chunk_count() -> int:
	var n := 0
	for cell in _islands:
		var chunks: Dictionary = _islands[cell]["chunks"]
		for ck in chunks:
			if chunks[ck]["node"] != null:
				n += 1
	return n


## Chunk meshes held across all islands, live and cached. After a prewarm this is
## the size of the whole ladder; the streamer never adds to it.
func cached_chunk_count() -> int:
	var n := 0
	for cell in _islands:
		for key in (_islands[cell]["cache"] as Dictionary):
			if _islands[cell]["cache"][key] != null:
				n += 1
	return n
