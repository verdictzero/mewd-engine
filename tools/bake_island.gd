## MEWD — PRE-BUILD AN ISLAND, at the user's request (every level ships
## baked: godot/scripts/level/islands.gd). golf's tools/TOOL_bake_world.gd,
## cut down to what this game needs, plus the ground's height grid.
##
##   godot --headless --script res://tools/bake_island.gd -- [--map=island0 | --all] [--if-missing] [--dir=res://godot/island/data/bake]
##
## --all bakes every island in Islands.LIST; --if-missing passes over an
## island whose three bakes are already there under its CURRENT signatures
## (what the builds run: tools/build-linux.sh, tools/build-android.sh).
##
## Builds the island the way the game would without a bake — every chunk
## of terrain at every LOD, every plant — with the stores recording, then
## writes:
##
##   terrain_<sig>.bake   the terrain's chunk meshes (TerrainBake)
##   veg_<sig>.bake       the plants' instance buffers (VegBake)
##   heights_<sig>.bin    the ground the game walks on (IslandGround)
##   CODE_DIGESTS.json    the sources' digests, which an exported build
##                        (scripts as .gdc, no .gd) cannot work out for
##                        itself and needs to find its bakes by
##
## into the directory the game looks in first, res://godot/island/data/
## bake (git ignores it: CI bakes before it builds). Without a bake the
## game still runs — it builds all of this at load, which on the handheld
## is minutes.
extends SceneTree

var _dir := "res://godot/island/data/bake"
var _maps: Array = ["island0"]
var _if_missing := false
const TERRAIN_BAKE := preload("res://godot/island/scripts/autoload/AUTOLOAD_terrain_bake.gd")
const VEG_BAKE := preload("res://godot/island/scripts/autoload/AUTOLOAD_veg_bake.gd")

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.substr(6).trim_suffix("/")
		elif a.begins_with("--map="):
			_maps = [a.substr(6)]
		elif a == "--all":
			_maps = Islands.LIST.map(func(i): return i.key)
		elif a == "--if-missing":
			_if_missing = true
	_run.call_deferred()

func _run() -> void:
	var code := 0
	for m in _maps:
		code = maxi(code, await _bake(m))
	quit(code)

## The three files an island's bake is, under its current signatures.
func _files_for(spec: Dictionary) -> Array:
	var scene: Node3D = (load(spec.scene) as PackedScene).instantiate()
	var world: Node = scene.get_node("IslandWorld")
	var field: Resource = world.get("field")
	field.prepare()
	var chunk := float(world.get("chunk_size"))
	var out := [
		BakeStore.file_name("terrain", TERRAIN_BAKE.signature_of([field, {"chunk_size": chunk}])),
		BakeStore.file_name(IslandGround.STORE, IslandGround.signature_for(field, chunk)),
	]
	var scatter: Node = scene.get_node_or_null("VegScatter")
	if scatter != null:
		out.append(BakeStore.file_name("veg", VEG_BAKE.signature_of(field, scatter)))
	scene.free()
	return out

func _bake(map: String) -> int:
	await process_frame
	var spec0: Dictionary = Islands.find(map)
	if _if_missing:
		var have := true
		for f in _files_for(spec0):
			if not FileAccess.file_exists("%s/%s" % [_dir, f]):
				have = false
		if have:
			print("== %s: baked already (%s)" % [spec0.title, _dir])
			return 0
	var terrain: Node = root.get_node_or_null("TerrainBake")
	var veg: Node = root.get_node_or_null("VegBake")
	if terrain == null or veg == null:
		push_error("bake_island: the TerrainBake and VegBake autoloads are not registered")
		return 2
	var spec: Dictionary = spec0
	var scene: Node3D = (load(spec.scene) as PackedScene).instantiate()
	var world: Node = scene.get_node("IslandWorld")
	var scatter: Node = scene.get_node_or_null("VegScatter")
	var field: Resource = world.get("field")
	field.prepare()
	print("== %s (%s)" % [spec.title, spec.scene])
	var t0 := Time.get_ticks_msec()
	# THE GROUND first, on every core, before the world takes them
	var gsig := IslandGround.signature_for(field, float(world.get("chunk_size")))
	var ground := IslandGround.build(field)
	print("   ground: %d x %d samples, %.1f s" % [ground.n, ground.n, (Time.get_ticks_msec() - t0) / 1000.0])
	# THE WORLD, built as the game would build it, the stores recording
	terrain.record_arrays = true
	terrain.refuse_disk = true
	veg.refuse_disk = true
	var cam := Camera3D.new()
	cam.position = Vector3(0, 200, 0)
	scene.add_child(cam)
	var done := [false]
	world.pregen_finished.connect(func(): done[0] = true)
	t0 = Time.get_ticks_msec()
	root.add_child(scene)
	cam.make_current()
	var deadline := Time.get_ticks_msec() + 1800 * 1000
	while Time.get_ticks_msec() < deadline:
		if scatter != null and scatter.has_method("prefill_step"):
			scatter.call("prefill_step")
		await process_frame
		if done[0] and (scatter == null or bool(scatter.get("_prescattered"))):
			break
	if not done[0]:
		push_error("bake_island: the island did not finish building")
		return 2
	print("   island built in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var abs_dir := ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var written := 0
	for store in [terrain, veg]:
		var sig := String(store.stats()["signature"])
		if int(store.stats()["held"]) == 0:
			continue
		var path := "%s/%s" % [_dir, store.file_name(store.STORE_NAME, sig)]
		var n: int = store.save_to(path)
		print("   %s: %d entries -> %s (%.1f MB)" % [store.STORE_NAME, n, path, _size(path) / 1.0e6])
		written += maxi(n, 0)
	var gpath := "%s/%s" % [_dir, BakeStore.file_name(IslandGround.STORE, gsig)]
	if not ground.save_to(gpath):
		push_error("bake_island: could not write %s" % gpath)
		return 2
	print("   ground -> %s (%.1f MB)" % [gpath, _size(gpath) / 1.0e6])
	# THE DIGESTS, for an exported build (BakeStore.DIGEST_TABLE): every
	# source the signatures above hashed, as this machine reads it
	var table := {}
	for p in BakeStore._digests:
		if String(BakeStore._digests[p]) != "":
			table[p] = BakeStore._digests[p]
	var f := FileAccess.open(BakeStore.DIGEST_TABLE, FileAccess.WRITE)
	f.store_string(JSON.stringify(table, "\t"))
	f.close()
	print("   %d source digests -> %s" % [table.size(), BakeStore.DIGEST_TABLE])
	scene.queue_free()
	await process_frame
	# (the stores are emptied for the next island, which is another world)
	terrain.clear()
	veg.clear()
	return 0 if written > 0 else 2

static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
