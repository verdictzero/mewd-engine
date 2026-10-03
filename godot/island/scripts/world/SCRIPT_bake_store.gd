class_name BakeStore
extends Node

# A KEYED STORE THAT OUTLIVES THE SCENE THAT FILLED IT.
#
# `AUTOLOAD_terrain_bake.gd` wrote this first, for the terrain, and everything it
# says about WHY still holds and is not repeated here — read that file for the
# argument. What is here is the part that turned out not to be about terrain at
# all, because the second thing that needed it wanted the identical machinery for
# an entirely different payload:
#
#   TerrainBake   chunk key   -> the ArrayMeshes and collision shape for a chunk
#   VegBake       tile key    -> the packed MultiMesh instance buffers for a tile
#
# Both are built behind the same loading screen, both are a pure function of the
# same `IslandField`, both are thrown away with the scene that built them, and
# both are RefCounted rather than nodes — so
# a store can hold the SAME objects the scene points at and cost nothing until the
# scene goes down. The two differ in what a key names and what a value holds, and
# in nothing else.
#
# WHAT A SUBCLASS OWNS: its `BAKE_VERSION`, its `key_for`, and any answer beyond
# "held" or "not held" that its payload needs — `TerrainBake.EMPTY` is one, and it
# is genuinely terrain-specific, since a chunk that meshes to nothing has to be
# tellable from one nobody has asked about. What this file owns is the holding,
# the signature and the accounting.
#
# THE SIGNATURE IS WHAT MAKES IT SAFE, and it is derived rather than declared.
# Anything that would change what the builder produces has to invalidate the
# store, and a hand-written list of "the settings that matter" is a list somebody
# adds a field to and forgets — the failure being a world quietly built from stale
# geometry, which looks like nothing at all until it looks like a hole in the
# ground. So `signature_for` walks every STORAGE property the field actually has,
# whatever they are today, and hashes them. A new export is covered the day it is
# added, by nobody.
#
# AND SO IS THE CODE, now, which is the half a settings hash cannot see. See
# `source_digest`.

## What the held store was built from. Empty means nothing is held.
var _signature := ""
## `key -> value`, where a key is the subclass's and a value is whatever it holds.
var _store := {}
## Guards every var below it. `peek` is called from build lanes; `take` and the
## puts are called from the main thread.
var _mutex := Mutex.new()

## `key -> bytes of payload`, parallel to `_store`. See `note_bytes`.
var _sizes := {}
## Running sum of `_sizes`. Accumulated on the way in rather than walked on the
## way out, because the debug overlay reads it every frame.
var _bytes := 0

var _hits := 0
var _misses := 0
var _puts := 0


## Point the store at a world. Adopts what is already held when the signature
## matches and throws it away when it does not, which is the whole of the
## invalidation rule. Returns true when a usable store was adopted.
func open(signature: String) -> bool:
	_mutex.lock()
	var adopted := signature == _signature and not _store.is_empty()
	if not adopted:
		_store = {}
		_sizes = {}
		_bytes = 0
		_signature = signature
		_hits = 0
		_misses = 0
		_puts = 0
	_mutex.unlock()
	return adopted


## Is this key answered at all. Counts a hit or a miss, so it is the call a
## builder makes before deciding to build — not a peek to be used casually.
func held(key: String) -> bool:
	_mutex.lock()
	var have := _store.has(key)
	if have:
		_hits += 1
	else:
		_misses += 1
	_mutex.unlock()
	return have


## The held value, or `null` when nothing is held. Does NOT count a hit: `held`
## has already asked the question, and counting it twice makes the stats lie.
func get_held(key: String) -> Variant:
	_mutex.lock()
	var v: Variant = _store.get(key, null)
	_mutex.unlock()
	return v


## Hold a value under a key. `bytes` is what the payload weighed before it went
## wherever it is going — see `note_bytes` for why it is passed in rather than
## measured here.
func put(key: String, value: Variant, bytes := 0) -> void:
	_mutex.lock()
	_bytes -= int(_sizes.get(key, 0))
	_store[key] = value
	_sizes[key] = bytes
	_bytes += bytes
	_puts += 1
	_mutex.unlock()


## Throw the store away. For a caller that knows the world changed under it in a
## way the signature cannot see — a debug rebuild, a test.
##
## NOT SAFE WHILE A WORLD IS BUILDING, and neither is an `open` that drops the
## store. A lane that has already been told a key is held will ask for the value a
## frame or two later, and an emptied store answers that with nothing — a chunk
## installed as void, which is a hole in the ground rather than an error. The
## invariant that makes this fine today is that `open` is called from a builder's
## `_ready` and scene changes do not overlap, so no build is ever in flight across
## one. A runtime rebuild would have to stop the world first.
func clear() -> void:
	_mutex.lock()
	_store = {}
	_sizes = {}
	_bytes = 0
	_signature = ""
	_hits = 0
	_misses = 0
	_puts = 0
	_mutex.unlock()


func stats() -> Dictionary:
	_mutex.lock()
	var s := {"held": _store.size(), "bytes": _bytes, "hits": _hits,
			"misses": _misses, "puts": _puts, "signature": _signature}
	_mutex.unlock()
	return s


## Roughly what a payload weighs, walking whatever it is made of.
##
## MEASURED FROM THE BUILDER'S OUTPUT, not from the resources built out of it,
## because there is no cheap way to ask an ArrayMesh or a MultiMesh how big it is
## — reading a surface back off one is a driver readback. So the caller measures
## what it is about to hand over and passes the number in. It is the same figure
## `prewarm_budget_mb` counts, which is what makes the two comparable.
##
## The dictionaries and arrays doing the holding are not counted: tens of bytes
## against hundreds of kilobytes, and a figure that tracks the payload is more
## useful than one that is exact about the packaging.
static func note_bytes(v: Variant) -> int:
	match typeof(v):
		TYPE_PACKED_VECTOR3_ARRAY: return (v as PackedVector3Array).size() * 12
		TYPE_PACKED_VECTOR2_ARRAY: return (v as PackedVector2Array).size() * 8
		TYPE_PACKED_COLOR_ARRAY: return (v as PackedColorArray).size() * 16
		TYPE_PACKED_FLOAT32_ARRAY: return (v as PackedFloat32Array).size() * 4
		TYPE_PACKED_INT32_ARRAY: return (v as PackedInt32Array).size() * 4
		TYPE_PACKED_BYTE_ARRAY: return (v as PackedByteArray).size()
		TYPE_ARRAY:
			var n := 0
			for e in (v as Array):
				n += note_bytes(e)
			return n
		TYPE_DICTIONARY:
			var n := 0
			for k in (v as Dictionary):
				n += note_bytes((v as Dictionary)[k])
			return n
	return 0


## What a world's output is a function of, as one string.
##
## TAKES OBJECTS AND DICTIONARIES, and the asymmetry is deliberate.
##
## An `IslandField` is walked WHOLE — every STORAGE property it has, whatever
## they are today — because it is a big resource that grows new knobs, every one
## of them feeds the height function, and a hand-kept list is a list somebody
## adds a field to and forgets. Over-invalidating there costs a rebuild nobody
## notices; under-invalidating hands back a world that no longer matches its own
## settings.
##
## A BUILDER's contribution is declared instead, as a dictionary, because most of
## what a streaming node exports has nothing to do with what it produces —
## materials, shadow flags, streaming radii, the fog floor. Walking one whole
## would throw the store away when somebody nudged `view_distance`, which changes
## how much of the island is built and not one vertex of what is built. Only the
## handful that reach the builder belong there. See `exports_of` for the case
## where that list is too long to keep by hand and the walk is the lesser evil.
##
## `var_to_str` rather than `hash()` on the values because it is stable across
## runs, which is what a store written to disk needs.
##
## WALKING ONLY GOES ONE LEVEL DEEP, which is safe exactly as long as the object
## holds no Resource of its own: `var_to_str` of a Resource is its PATH, so a
## nested noise or curve would be identical to the hash however it was retuned.
## `TEST_terrain_bake.gd` asserts that no such property exists on the field, so
## the day one is added is the day the test says so rather than the day a world
## comes back wrong.
static func signature_for(version: int, parts: Array) -> String:
	var acc := "v%d" % version
	for part in parts:
		if part is Dictionary:
			# Sorted, so a caller that builds the dictionary in a different order
			# does not thereby invalidate a store that is still perfectly good.
			var keys: Array = (part as Dictionary).keys()
			keys.sort()
			acc += "|{"
			for k in keys:
				acc += "%s=%s;" % [String(k), var_to_str((part as Dictionary)[k])]
			acc += "}"
			continue
		var obj := part as Object
		if obj == null:
			acc += "|null"
			continue
		acc += "|" + obj.get_class()
		for p in obj.get_property_list():
			if int(p.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0:
				continue
			var pname := String(p.get("name", ""))
			if pname == "":
				continue
			acc += ";%s=%s" % [pname, var_to_str(obj.get(pname))]
	return "%d" % acc.hash()


## Every `@export` a NODE's own script declares, as a dictionary fit for
## `signature_for`.
##
## THE MIDDLE GROUND BETWEEN THE TWO ABOVE, and it exists because
## `SCRIPT_veg_scatter.gd` has forty-odd exports and something like thirty of them
## move a plant. Declaring that list by hand is the failure mode this whole file
## is written around; walking the NODE whole the way a field is walked picks up
## `position`, `visible`, `process_mode` and every other Node3D built-in, which is
## noise. `Script.get_script_property_list` is exactly the seam between the two:
## the properties THIS SCRIPT declares, and STORAGE narrows those to the ones
## marked `@export`.
##
## It over-invalidates — `rescan_interval` is in here and decides nothing about
## where a plant stands — and that is the direction to err in. A store thrown away
## costs a rebuild; a store kept costs a world that no longer matches its
## settings.
##
## A Resource-valued export (a material, a sprite) hashes as its PATH, which is
## the right answer: swapping which material is a different world, and retuning
## the same material's contents changes how a plant is DRAWN, never where it is.
static func exports_of(node: Object) -> Dictionary:
	var out := {}
	if node == null:
		return out
	var scr := node.get_script() as Script
	if scr == null:
		return out
	for p in scr.get_script_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var pname := String(p.get("name", ""))
		if pname == "":
			continue
		out[pname] = node.get(pname)
	return out


## The state of the CODE that produces what is stored, as one string fit for
## `signature_for`.
##
## THE HOLE A SETTINGS HASH CANNOT SEE, closed. Nothing `signature_for` does will
## notice that `SCRIPT_chunk_mesher.gd` now emits a different vertex for the same
## inputs, or that `IslandField.height_at` gained a term — and a store carried
## across either hands the next scene geometry that no longer matches the game, on
## the SECOND load, so the first look at any change is a look at the world from
## before it.
##
## `BAKE_VERSION` was the answer and remembering to bump it was the failure mode.
## `TEST_terrain_bake.gd` turned that into a test that asks, which is much better
## than nobody asking, and is still a human in the loop on a question with a
## mechanical answer. Hashing the sources makes the store invalidate ITSELF the
## moment the generator changes.
##
## THE VERSION DOES NOT GO AWAY. It still covers what a digest cannot: a change to
## the SHAPE of what is stored, which is a decision about this file rather than
## about the generator, and which a bake read back off disk by newer code has to
## be able to refuse.
##
## A COMMENT-ONLY EDIT INVALIDATES TOO. That is the right way round — it costs one
## rebuild, and the other error costs a world. It is also why the digest is of the
## SOURCE rather than of anything cleverer: there is no cheap, reliable way to ask
## "did this edit change the output", and every approximation of it fails silently
## in the expensive direction.
##
## Reads at most once per path per run — the files do not change under a running
## game, and a pre-bake tool asks for the same digests the game will.
static var _digests := {}

## THE SOURCES ARE NOT IN THE BUILD, and this is how their digests get there.
##
## `export_presets.cfg` ships `script_export_mode=2`: every `.gd` in the project
## becomes a `.gdc` of binary tokens and the `.gd` itself is not exported. So on
## a player's machine `FileAccess.get_sha256("res://.../SCRIPT_chunk_mesher.gd")`
## opens nothing and answers `""` — for every source, every time.
##
## That was not a missing digest, it was a DIFFERENT ONE, and it cost the build.
## The machine that bakes reads the real files and names the file
## `terrain_1573686522.bake`; the shipped build hashed four empty strings and went
## looking for `terrain_1400194824.bake`, which nobody has ever written. The bake
## was in the APK — 93.8 MB of it, staged, gated and verified present — and the
## game meshed the island from nothing anyway, for two and a half minutes, on
## every launch. Nothing reported it: the gate asks its question on the machine
## that has the sources, so it got the baker's answer and passed.
##
## A digest of what the build DOES contain cannot fix it — `.gdc` is not `.gd`
## and never hashes the same — so the number has to be carried. The export writes
## one small table of `path -> sha256`, taken from the real sources at the moment
## of export, and this is where it is read back. See
## `addons/bake_retention/SCRIPT_bake_digest_export.gd`, which builds it, and
## `TOOL_bake_retention.gd --verify`, which opens a finished APK and checks that
## the bake it ships is the bake it will look for.
##
## THE EDITOR NEVER READS THE TABLE. A readable source always wins, so the one
## machine that can be wrong about its own code is the one that cannot consult
## this. A table that is missing, or short of a path, leaves the digest `""` —
## which is where this started, and is still the safe direction: the world is
## generated rather than read, which is slow and not wrong.
const DIGEST_TABLE := "res://godot/island/data/bake/CODE_DIGESTS.json"

static var _table: Dictionary = {}
static var _table_read := false

## Ignore the sources on this disk and answer only from the carried table —
## which is what a player's build has no choice but to do. Set by
## `TOOL_bake_retention.gd --verify` and by the tests, and by nothing in the
## game: the game is already in that position and does not have to pretend.
static var as_exported := false

static func _exported_digests() -> Dictionary:
	if _table_read:
		return _table
	_table_read = true
	if not FileAccess.file_exists(DIGEST_TABLE):
		return _table
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(DIGEST_TABLE))
	if parsed is Dictionary:
		_table = parsed
	else:
		push_warning("bake_store: %s is not a digest table" % DIGEST_TABLE)
	return _table


static func source_digest(paths: Array) -> String:
	var acc := ""
	for p in paths:
		var path := String(p)
		if not _digests.has(path):
			var h := "" if as_exported else FileAccess.get_sha256(path)
			if h == "":
				# Not in this build. The export carried the number; see above.
				h = String(_exported_digests().get(path, ""))
			_digests[path] = h
		acc += "%s:%s;" % [path.get_file(), String(_digests[path])]
	return acc


## Forget what has been read, so the next `source_digest` asks the disk again.
## For a test that moves the table or the sources under a running process.
## Nothing in the game calls it: the files do not change under a running game.
static func forget_digests() -> void:
	_digests = {}
	_table = {}
	_table_read = false
	as_exported = false


## Answer every digest from `table` alone, as a build without the sources must.
## `TOOL_bake_retention.gd --verify` calls this with the table it found inside a
## finished APK, and then asks each shipped zone what it hashes to — which is the
## player's arithmetic, done on a machine that could have cheated.
static func read_as_exported(table: Dictionary) -> void:
	forget_digests()
	_table = table.duplicate()
	_table_read = true
	as_exported = true


# ---------------------------------------------------------------- on disk
#
# A STORE THAT SURVIVES THE PROCESS, so the FIRST load of a zone can be as cheap
# as the walk home from a battle already is.
#
# What that is worth on W3, measured to the frame the loading screen lifts: 96.5 s
# entering the zone against 4.6 s coming back to one already held in memory. The
# difference is entirely generation — 1,328 chunk meshes and 481,522 plants, every
# one of them a pure function of settings that have not changed since the last
# time somebody built them. Held on disk it is the same 4.6 s from a cold start,
# and it is regenerated only when the signature says the world is genuinely
# different: a setting moved, or the generating CODE did.
#
# `tools/TOOL_bake_world.gd` is what writes one, and it exists so that the wait is
# somebody's deliberate five minutes at a terminal rather than every player's
# first ninety seconds.
#
# THE SIGNATURE IS THE FILE'S NAME AND ALSO ITS FIRST FIELD. The name so that
# bakes for different worlds can sit side by side and the right one is found
# without opening any of them; the field so that a file renamed, copied or
# half-written cannot be adopted by a world it was not built for. Both checks are
# the same check `open` already makes in memory — see this file's header for why
# it is the whole of the invalidation rule.
#
# WHAT IS STORED IS NOT WHAT IS HELD, necessarily, and that is what `_encode_entry`
# and `_decode_entry` are for. `VegBake` holds plain data and writes it unchanged.
# `TerrainBake` holds RESOURCES — an ArrayMesh cannot be written as a Variant, and
# reading one back off the GPU to try would be a driver readback per chunk — so it
# writes the mesher's arrays and rebuilds the resources on load. The store does
# not need to know which; it asks.

## Set by a tool that is about to WRITE a bake, and by nothing else. See
## `open_with_disk`, which is where it does its work and where the reason is.
var refuse_disk := false

## Where a bake is looked for, in order. `res://` first so a bake somebody
## deliberately committed beats a stale one left in a user directory; `user://`
## because that is where a tool run on this machine writes by default and where
## a hundred megabytes belongs when it is a cache rather than an asset.
const READ_DIRS := ["res://godot/island/data/bake", "user://bake"]
## Where `tools/TOOL_bake_world.gd` writes unless told otherwise.
const WRITE_DIR := "user://bake"
## Written into the header and checked on read. Covers the FILE's layout — the
## framing below — as distinct from a payload's shape, which is each store's own
## `BAKE_VERSION` and is folded into the signature.
const FILE_FORMAT := 1
const _MAGIC := "GOLFBAKE"


## The file a store of this name and signature goes under. The name is the
## store's, so a directory holding several is readable.
static func file_name(store: String, signature: String) -> String:
	return "%s_%s.bake" % [store, signature]


## The first of `READ_DIRS` holding this bake, or "" when none does.
static func find_bake(store: String, signature: String) -> String:
	var name := file_name(store, signature)
	for d in READ_DIRS:
		var path := "%s/%s" % [d, name]
		if FileAccess.file_exists(path):
			return path
	return ""


## Write everything held to `path`. Returns the number of entries written, or -1.
##
## ZSTD THROUGH `open_compressed`, which is worth an order of magnitude here:
## measured on W3's chunks, the mesher's arrays come back to 21% of their size,
## because float data that describes a surface is enormously more predictable than
## float data in general. A hundred megabytes rather than five hundred is the
## difference between a cache and a thing nobody keeps.
func save_to(path: String) -> int:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			push_error("bake_store: could not make %s (%d)" % [dir, err])
			return -1
	# WRITTEN BESIDE THE REAL FILE AND RENAMED OVER IT AT THE END. A bake takes
	# minutes to make and seconds to write, and for those seconds the old one is
	# the only copy of an hour of somebody's afternoon; opening the destination
	# directly means a disk that fills, a process that is killed, or the shortfall
	# checked below all land as a good bake replaced by a bad one. A rename is
	# atomic, so the file at `path` is either the previous bake or this one, and
	# never half of either.
	var part := "%s.part" % path
	var f := FileAccess.open_compressed(part, FileAccess.WRITE,
			FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("bake_store: could not open %s for write (%d)"
				% [part, FileAccess.get_open_error()])
		return -1
	_mutex.lock()
	var keys: Array = _store.keys()
	var sig := _signature
	_mutex.unlock()
	# Sorted, so two runs of the same tool produce the same bytes and a bake is
	# diffable against the one it replaces.
	keys.sort()

	f.store_string(_MAGIC)
	f.store_32(FILE_FORMAT)
	f.store_pascal_string(sig)
	# Count first, so a read can size itself, and so a file cut short by a full
	# disk fails the count rather than being adopted with a hole in it.
	f.store_32(keys.size())
	var written := 0
	for k in keys:
		var payload: Variant = _encode_entry(String(k))
		if payload == null:
			continue
		f.store_pascal_string(String(k))
		var raw := var_to_bytes(payload)
		f.store_32(raw.size())
		f.store_buffer(raw)
		written += 1
	f.close()

	# A SHORTFALL IS A FAILURE, not a note. Every key in the store either encodes
	# to something or is a chunk whose payload this process never had — and a bake
	# missing its chunks is not a partial bake, it is a file that will be adopted
	# on the next load, match its signature, and answer every chunk with a miss.
	# The world comes up empty and the signature says it is correct.
	if written != keys.size():
		push_error("bake_store: only %d of %d entries could be written; %s left as it was"
				% [written, keys.size(), path])
		DirAccess.remove_absolute(part)
		return -1

	var err := DirAccess.rename_absolute(part, path)
	if err != OK:
		push_error("bake_store: could not put %s in place (%d)" % [path, err])
		DirAccess.remove_absolute(part)
		return -1
	return written


## Fill this store from `path`, but only if the file was built for the signature
## the store is currently open on. Returns the number of entries adopted, or -1
## when the file was missing, malformed or built for a different world.
##
## REFUSING IS THE POINT and it is not an error to report loudly: a bake for the
## world before your last edit is exactly what should be on disk after you make
## one, and the right response is to generate rather than to complain.
func load_from(path: String) -> int:
	var f := FileAccess.open_compressed(path, FileAccess.READ,
			FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return -1
	if f.get_buffer(_MAGIC.length()).get_string_from_ascii() != _MAGIC:
		push_warning("bake_store: %s is not a bake" % path)
		return -1
	if f.get_32() != FILE_FORMAT:
		push_warning("bake_store: %s is an older bake format" % path)
		return -1
	var sig := f.get_pascal_string()
	_mutex.lock()
	var want := _signature
	_mutex.unlock()
	if sig != want:
		# Not a warning. See the note above.
		return -1
	var count := f.get_32()
	var adopted := 0
	for i in count:
		if f.eof_reached():
			push_warning("bake_store: %s ended after %d of %d entries"
					% [path, adopted, count])
			break
		var key := f.get_pascal_string()
		var size := f.get_32()
		var raw := f.get_buffer(size)
		if raw.size() != size:
			push_warning("bake_store: %s is truncated at entry %d" % [path, i])
			break
		var payload: Variant = bytes_to_var(raw)
		if payload == null:
			continue
		_decode_entry(key, payload)
		adopted += 1
	f.close()
	return adopted


## What goes on disk for this key, or null to leave it out.
##
## The default is what is held, which is right for any store whose payload is
## plain data. A store holding resources overrides both of these — see
## `AUTOLOAD_terrain_bake.gd`.
func _encode_entry(key: String) -> Variant:
	return get_held(key)


## Put back what `_encode_entry` wrote.
func _decode_entry(key: String, payload: Variant) -> void:
	put(key, payload, note_bytes(payload))


## Open on `signature`, and when nothing was already held try a bake on disk.
## Returns "" when nothing was adopted, or the source — "memory" or the file's
## path — when something was.
##
## THE ORDER MATTERS AND IS NOT AN OPTIMISATION. A store already held in memory is
## the SAME OBJECTS the last scene was pointing at, so adopting it costs nothing
## and re-reading the file would replace live meshes with fresh copies of
## themselves — the same geometry at twice the memory.
##
## THE READ IS ON THE MAIN THREAD AND BEFORE THE FIRST FRAME, because the builders
## call this from `_ready` and everything downstream of them assumes the store is
## already answering. On W3 that is 1.6 s of terrain and 0.1 s of vegetation with
## nothing drawn, against the 85 s of generation it replaces — a trade worth
## taking, and the reason the loading screen's bar sits at 0% for the first
## couple of seconds of a pre-baked load rather than sweeping from the start. It
## is the one part of the disk path that would want streaming if the bake ever
## got much bigger.
func open_with_disk(store: String, signature: String) -> String:
	if open(signature):
		return "memory"
	if refuse_disk:
		# A BAKE RUN MUST NOT ADOPT THE BAKE IT IS ABOUT TO REPLACE, and this is
		# the only thing standing between it and doing exactly that. The signature
		# of a world you have not changed is the same signature, so the file the
		# tool is about to overwrite is a file it would otherwise FIND and open —
		# and a store filled from disk holds what a store filled by the mesher
		# does not: `TerrainBake` writes the mesher's ARRAYS, which exist only for
		# a chunk this process meshed. Every adopted chunk then encodes to
		# nothing, and a 94 MB bake is replaced by a couple of kilobytes of the
		# empty-chunk markers, which are the only entries that survive.
		#
		# It was not theoretical. `TEST_world_baker.gd` drove the dock through a
		# real bake over a real existing one and that is precisely what happened,
		# down to the file size. `save_to` refuses a short write now as well, so
		# this is the first of two independent things that have to fail before a
		# good bake is lost.
		return ""
	var path := find_bake(store, signature)
	if path == "":
		return ""
	var t0 := Time.get_ticks_msec()
	var n := load_from(path)
	if n <= 0:
		return ""
	print("[bake] %s: %d entries from %s in %d ms" % [
			store, n, path, Time.get_ticks_msec() - t0])
	return path
