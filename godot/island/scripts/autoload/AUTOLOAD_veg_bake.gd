extends BakeStore

# THE PLANTS, HELD ACROSS THE SCENE RELOAD A BATTLE PERFORMS.
#
# `AUTOLOAD_terrain_bake.gd` did this for the ground and the numbers said the job
# was only half done. Measured on W3, headless, four cores, to the frame the
# loading screen actually lifts rather than to `pregen_finished`:
#
#     entering the zone   terrain 85.8 s   vegetation 97.8 s   screen up  98.9 s
#     back from a battle  terrain  2.0 s   vegetation 42.8 s   screen up  43.7 s
#
# The terrain came back for nothing, exactly as the bake promises. Forty-one of
# the forty-four seconds the player waits after every won fight is the FOREST
# being planted again — 481,522 plants off a 4 m grid, every one of them a
# function of the same `IslandField` that produced the identical set on the way
# in. "The terrain is regenerated after a battle" is what that looks like from
# outside, and it is not wrong about the wait.
#
# WHAT IS HELD is one tile record per tile: the packed MultiMesh instance buffers
# — one `PackedFloat32Array` per sprite variant — the plant count they share, the
# height band the tile occupies, and the render-space origin they were packed
# against. That last one is not bookkeeping: `veg_scatter._install_tile` already
# compares it and patches the drift three floats at a time, because a tile can
# land after a rebase moved the world under it. A tile out of this store is the
# same case, so a bake taken before an origin shift installs correctly after one
# with no code that knows this store exists.
#
# IT IS THE BUFFERS, NOT THE MULTIMESHES. A MultiMesh is one object per SPRITE
# with every visible tile concatenated into it, rebuilt by `_refill_static`
# whenever the selection changes — so it is a view, and holding one would hold a
# particular scene's idea of what was in view. The buffers are the tile's own
# bytes and are what the concatenation is made of.
#
# ~31 MB FOR THE WHOLE ISLAND, at 64 bytes an instance across 481,522 of them,
# and like the terrain's it is SHARED rather than copied while a scene is up: a
# `PackedFloat32Array` is copy-on-write, so the floats this store holds are the
# floats the scene's tile records hold. It only becomes the sole owner once the
# field scene goes down. The one thing it does keep to itself is the LIST those
# buffers sit in — see `_detached`, which is a dozen references a tile and the one
# place this economy could quietly go wrong.
#
# OFF FOR A STREAMING WORLD, and `veg_scatter` will not open it unless
# `prescatter` is on. A prescattered world is bounded and finite — that is the
# precondition `prescatter` already states — so the store has a size. A scatter
# that streamed forever would grow it without limit and would want a budget here
# before it wanted this at all.

## Bump when the SHAPE of a tile record changes — what the dictionary holds, or
## what the buffers mean.
##
## It does not have to move for a change to the generating CODE: `_SOURCES` is
## hashed into the signature, so an edit to the placement rules invalidates the
## store by itself. See `BakeStore.source_digest`.
const BAKE_VERSION := 1

## What this store is called on disk. See `BakeStore.file_name`.
const STORE_NAME := "veg"

## Every file whose code decides where a plant stands: the scatter's own
## placement rules and the field they sample. `IslandField` is in both this list
## and the terrain's because it is genuinely in both answers — the same height
## function that puts a vertex somewhere puts a fir on it.
const _SOURCES := [
	"res://godot/island/scripts/world/SCRIPT_veg_scatter.gd",
	"res://godot/island/scripts/world/SCRIPT_island_field.gd",
]


## Is this tile already built.
##
## NO "EMPTY" ANSWER HERE, unlike the terrain's, and the difference is real rather
## than an omission. A chunk that meshes to nothing produces no resources at all,
## so "known empty" has to be storable separately or the void is re-meshed
## forever. A tile that grows nothing still produces a full record — one empty
## buffer per sprite variant, and a height band — so it is held like any other and
## "held" is the only question there is.
func has_tile(key: Vector2i) -> bool:
	return held(key_for(key))


## The held tile record, or `{}`. Main thread: what comes back goes into `_tiles`
## and from there into a MultiMesh.
func take(key: Vector2i) -> Dictionary:
	var v: Variant = get_held(key_for(key))
	return {} if v == null else _detached(v)


## Hold a finished tile. `rec` is `_build_tile`'s output — see the header for
## which of its fields matter and why `off` is one of them.
func put_tile(key: Vector2i, rec: Dictionary) -> void:
	var held_rec := _detached(rec)
	put(key_for(key), held_rec, note_bytes(held_rec.get("bufs", [])))


## A record whose `bufs` LIST is the caller's alone.
##
## THE FLOATS ARE STILL SHARED, and that is the whole economy of this store: a
## `PackedFloat32Array` is copy-on-write, so handing the same 31 MB to a scene and
## to the store costs the bytes once. What must NOT be shared is the `Array` they
## sit in, because `Array` is a reference and `veg_scatter._shift_bufs` writes
## back into it — `bufs[i] = b` after a rebase. Share the list and a rebase in the
## scene silently moves the store's plants too, leaving them at an origin its `off`
## field no longer names: every tile out of the store from then on lands a rebase
## away from the island.
##
## Duplicating the list is a dozen references per tile. Duplicating the floats
## would be the memory this store exists to not spend.
static func _detached(rec: Dictionary) -> Dictionary:
	var out := rec.duplicate()
	var bufs: Variant = out.get("bufs", null)
	if bufs is Array:
		out["bufs"] = (bufs as Array).duplicate()
	return out


static func key_for(key: Vector2i) -> String:
	return "%d,%d" % [key.x, key.y]


## What a world's vegetation is a function of: the field, the scatter's own
## exports, and the state of the code that turns one into the other.
##
## THE SCATTER IS WALKED rather than declared, which is the opposite of what
## `island_world` does for the terrain and for a reason the terrain does not have.
## `TerrainBake`'s world contribution is ONE number — `chunk_size` — because
## everything else the mesher is handed comes off the field or is already in the
## chunk key. This scatter has forty-odd exports and something like thirty of them
## move a plant: the grid, the slope and flatten limits, six densities, the crater
## and divot clearings, the clump band, the per-cell counts, the size ranges, the
## sprite lists. A list of those written by hand is a list somebody adds a density
## to and forgets, and the failure is a world of plants standing where the old
## settings put them. `BakeStore.exports_of` walks what the script declares, which
## cannot be short by one.
##
## THE SPRITE LISTS ARE IN IT AND MUST BE. A tile's buffers are indexed by FLAT
## SPRITE INDEX across the three classes, so two scenes wiring up different sprite
## arrays do not merely draw differently — their buffers do not line up, and a
## borrowed tile would put ferns in the firs' MultiMesh.
static func signature_of(field: Object, scatter: Object) -> String:
	return signature_for(BAKE_VERSION, [field, exports_of(scatter),
			{"code": source_digest(_SOURCES)}])
