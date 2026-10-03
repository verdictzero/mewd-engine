extends BakeStore

# THE RESOURCE HALF OF THE CHUNK CACHE.
#
# `SCRIPT_island_world.gd` already caches chunks: `_islands[cell]["cache"]` maps
# a (chunk, resolution) to the MeshInstance3D built for it, which is why an LOD
# swap after a prewarm costs nothing. That cache is instance state and dies with
# the node — the right lifetime for a world you enter once, and the wrong one for
# a world you enter more than once.
#
# WHAT IT WAS BUILT FOR HAS GONE AWAY, and it is worth being straight about that
# before anyone reads the rest as current. The encounter loop used to go through
# a SCENE RELOAD — `EncounterFx.return_to_field` ended a fight with
# `change_scene_to_file`, so the island was built again from nothing on the walk
# home. Measured headless with `tests/PERF_w3_reentry.gd`, entering the zone
# prewarmed 1,328 chunk meshes and coming back from a battle prewarmed the same
# 1,328 for the same 415 MB. A fight now HOLDS the field instead
# (`AUTOLOAD_encounter_fx._hold_field`): nothing is torn down, so there is no
# walk home to pay for.
#
# WHAT IT IS STILL FOR is the other entry: the FIRST load of the zone, and any
# genuine scene change into it. `open_with_disk` reads a bake off disk — one
# `tools/TOOL_bake_world.gd` or the World Baker dock wrote ahead of time — which
# is the difference between installing this island and generating it. That is
# ~90 s a player would otherwise pay on every launch, and it is why this outlives
# the round trip that prompted it.
#
# Nodes cannot outlive their scene, so this holds THE RESOURCES INSIDE THEM: the
# ArrayMesh for the surface, one per cliff band, and the collision shape. Those
# are RefCounted, owned by whoever holds them rather than by a tree, and shared
# rather than copied — the mesh a scene's MeshInstance3D points at is the same
# object this store points at, so while the field is up the store costs NOTHING
# beyond what the scene was already paying, and when the field goes down it is
# the only thing still holding them.
#
# THAT SHARING IS THE WHOLE POINT, and it is worth saying what the alternative
# cost. The first version of this stored the MESHER'S OUTPUT — the raw vertex,
# normal, UV and index arrays. It worked, but `ArrayMesh.add_surface_from_arrays`
# copies what it is given into mesh buffers, so every chunk was resident twice:
# `tests/PROBE_bake_footprint.gd` measured 445.9 MB of arrays held alongside the
# meshes built from them, having been transient before the bake existed. Holding
# the built resources instead is the same saving for none of that.
#
# WHAT IS NOT STORED is anything the WORLD decides rather than the mesher:
# materials, `cast_shadow`, the `cliff_visible_depth` cutoff. Those are set on
# the instances at install, every time, from the world's own exports — so a
# material change or a shadow-flag change takes effect on the next scene load
# without invalidating one chunk of geometry.
#
# THE HOLDING, THE SIGNATURE AND THE ACCOUNTING ARE IN `SCRIPT_bake_store.gd`,
# which this extends. They moved there when the vegetation turned out to want the
# identical machinery for an entirely different payload (`AUTOLOAD_veg_bake.gd`);
# what is left here is what is actually about terrain — the version, the chunk
# key, and the fact that "this chunk meshes to nothing" is an answer.

## Bump when the SHAPE of what is stored changes.
##
## It no longer has to move for a change to the generating CODE: `_SOURCES` below
## is hashed into the signature, so an edit to the mesher or to the field's height
## function invalidates the store by itself. See `BakeStore.source_digest` for why
## that replaced a version bump somebody had to remember, and why the version is
## still here for the thing a digest cannot see.
##
## A store in memory could not care about the shape — the process starts with an
## empty one — but the signature is stable across runs so that it can name a store
## on disk, and a v1 file read back by v2 code is exactly what a version is for.
## 2 is the move from holding the mesher's raw arrays to holding the resources
## built from them.
const BAKE_VERSION := 2

## What this store is called on disk. See `BakeStore.file_name`.
const STORE_NAME := "terrain"

## Every file whose code decides what a chunk looks like. Hashed into the
## signature, so the store invalidates itself when one of them is edited.
##
## ONLY TWO, and that is checked rather than assumed: neither preloads another
## script, so the geometry-producing code is exactly these.
## `tests/TEST_terrain_bake.gd` is what checks it.
const _SOURCES := [
	"res://godot/island/scripts/world/SCRIPT_chunk_mesher.gd",
	"res://godot/island/scripts/world/SCRIPT_island_field.gd",
]

## `peek` answers one of these.
enum {
	## Never asked, or asked and dropped. The caller must mesh it.
	MISS,
	## Asked, and the answer was that this chunk meshes to nothing. An answer in
	## its own right: re-meshing to rediscover it is exactly the waste this
	## exists to stop, so "empty" has to be storable and not just absent.
	EMPTY,
	## Held, built, and ready to instance.
	BUILT,
}

## Held for a chunk that meshes to nothing, so that "known to be empty" and
## "never asked" stay different answers.
const EMPTY_MARK := {"empty": true}


## Is this chunk already answered, and how. Called on the build lane, before
## meshing, and deliberately hands back no data: the resources are instanced on
## the main thread and a lane has no use for them.
func peek(key: String) -> int:
	if not held(key):
		return MISS
	return EMPTY if get_held(key) == EMPTY_MARK else BUILT


## The held resources for a chunk, or `{}` when it holds nothing — which is both
## "never asked" and "meshes to nothing", the two cases having already been told
## apart by `peek`. Main thread: what comes back goes straight into nodes.
func take(key: String) -> Dictionary:
	var v: Variant = get_held(key)
	if v == null or v == EMPTY_MARK:
		return {}
	return v


## Record that this chunk meshes to nothing.
func put_empty(key: String) -> void:
	put(key, EMPTY_MARK, 0)


## The name a chunk goes under. Resolution rather than LOD level for the same
## reason `_cache_key` uses it — `coast_lod` and the ladder can name the same cell
## count — and collision is part of the name because a chunk built without it
## carries no shape and cannot be handed to a caller that wanted one.
static func key_for(cell: Vector2i, ck: Vector2i, cells: int, collision: bool) -> String:
	return "%d,%d|%d,%d@%d%s" % [cell.x, cell.y, ck.x, ck.y, cells,
			"+c" if collision else ""]


## What a world's geometry is a function of: the field, the world's own mesher
## parameters, and the state of the code that turns one into the other.
static func signature_of(parts: Array) -> String:
	return signature_for(BAKE_VERSION, parts + [{"code": source_digest(_SOURCES)}])


## The mesher's arrays as SHAREABLE RESOURCES: meshes and a collision shape, all
## RefCounted and none of them owned by a tree.
##
## This is the split that lets this store hold a chunk across a scene reload. A
## MeshInstance3D is a child of its island's holder and dies with it; the
## ArrayMesh inside it does not, and the scene that comes next can point a fresh
## instance at the same one. Nothing world-specific is decided here — materials,
## shadow flags and the visibility cutoff are all applied per instance by
## `island_world._node_from_built`, so retuning any of them costs no geometry.
##
## IT LIVES HERE, not on `SCRIPT_island_world.gd` where it was written, because it
## IS the shape of what is stored — the thing `BAKE_VERSION` versions and the
## thing a bake read back off disk has to be rebuilt through. The world calls it
## on the way in; `_decode_entry` calls it on the way up from a file.
static func built_of(res: Dictionary) -> Dictionary:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["top"])
	mesh.custom_aabb = res["aabb_top"]

	var bands: Array = []
	for band in (res["cliff_bands"] as Array):
		var bb: AABB = band["aabb"]
		var cmesh := ArrayMesh.new()
		cmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, band["arrays"])
		cmesh.custom_aabb = bb
		bands.append({"mesh": cmesh, "aabb": bb})

	var shape: ConcavePolygonShape3D = null
	if res.has("faces"):
		var faces: PackedVector3Array = res["faces"]
		if not faces.is_empty():
			shape = ConcavePolygonShape3D.new()
			shape.set_faces(faces)

	return {"mesh": mesh, "bands": bands, "shape": shape}


# --------------------------------------------------------------- on disk
#
# WHAT IS HELD CANNOT BE WRITTEN, which is the whole reason this store overrides
# the two hooks below and `VegBake` does not. An ArrayMesh is not a Variant
# `var_to_bytes` can encode, and the way to get its contents back —
# `surface_get_arrays` — is a readback off the rendering server, per surface, per
# chunk. So the arrays that BUILT the resources are what goes on disk, and
# `built_of` runs again on the way up.
#
# THE ARRAYS ARE NOT KEPT unless somebody asks, and `record_arrays` is that ask.
# Holding them alongside the meshes was the store's first design and
# `PROBE_bake_footprint.gd` measured what it cost: 445.9 MB of arrays resident
# beside the meshes built from them, having been transient before. That is a price
# worth paying for the five minutes a bake tool runs and not for the whole of a
# session, so the game never sets this and `TOOL_bake_world.gd` always does.
#
# COLLISION IS NOT WRITTEN. `res["faces"]` is an unindexed triangle soup — three
# vertices per triangle with nothing shared — and it is a straight gather off the
# surface's own indices. Storing it would roughly double the file to save a loop
# that runs in microseconds, so `_decode_entry` rebuilds it from the arrays and
# the wall bands, exactly as `island_world._build_task` does.

## Keep the mesher's arrays as well as the resources built from them, so this
## store can be written to disk. OFF in the game — see above.
var record_arrays := false
## `key -> the mesher's `res``, filled only while `record_arrays` is on.
var _raw := {}


## Hold a chunk, and its arrays too when recording. The world calls this rather
## than `put` so that the recording decision lives here instead of in every
## caller.
func put_chunk(key: String, built: Dictionary, res: Dictionary, bytes := 0) -> void:
	put(key, built, bytes)
	if record_arrays:
		_raw[key] = res


func clear() -> void:
	super()
	_raw = {}


func _encode_entry(key: String) -> Variant:
	if get_held(key) == EMPTY_MARK:
		# "This chunk meshes to nothing" is an answer worth writing: without it
		# every void chunk around the island is a permanent miss on every load.
		return EMPTY_MARK
	var res: Variant = _raw.get(key, null)
	if res == null:
		# Held but not recorded — a chunk that landed before `record_arrays` was
		# set, or a store being written by something that never set it. Left out
		# rather than written wrong; `save_to` warns about the shortfall.
		return null
	# The soup goes; see the note above.
	var out: Dictionary = (res as Dictionary).duplicate()
	out.erase("faces")
	return out


func _decode_entry(key: String, payload: Variant) -> void:
	if payload == EMPTY_MARK or (payload is Dictionary
			and (payload as Dictionary).has("empty")):
		put_empty(key)
		return
	var res: Dictionary = payload
	# The collision soup, rebuilt rather than read: surface first, then every wall
	# band, so an aircraft flying up under an island still hits the underside.
	#
	# ONLY FOR A CHUNK THAT ASKED FOR ONE, which is what `key_for`'s `+c` suffix
	# says. Not a detail: `island_world._node_from_built` creates a StaticBody3D
	# for any built chunk that carries a shape, so handing one to a chunk stored
	# without collision would give the physics server an 8,000-triangle
	# ConcavePolygonShape3D per far-LOD chunk in the world — first-touch work the
	# prewarm exists to ration, on geometry that was never meant to be solid.
	if key.ends_with("+c"):
		var faces := _faces_of(res["top"])
		for band in (res["cliff_bands"] as Array):
			faces.append_array(_faces_of(band["arrays"]))
		res["faces"] = faces
	put(key, built_of(res), note_bytes(res))


## Indexed surface arrays -> the flat triangle soup `ConcavePolygonShape3D` wants.
## The same gather `island_world._build_task` does on its worker lane; here it is
## what keeps the soup out of the file.
static func _faces_of(surface: Array) -> PackedVector3Array:
	var verts: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	out.resize(idx.size())
	for i in range(idx.size()):
		out[i] = verts[idx[i]]
	return out
