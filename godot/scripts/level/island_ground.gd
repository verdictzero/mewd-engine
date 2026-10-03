## MEWD — THE ISLAND'S GROUND AS A HEIGHT GRID, at the user's request
## (the island world from golf, godot/island/).
##
## The island is a pure function of its field (IslandField), and asking
## the field costs ~34 microseconds a point: far too dear for every body
## and every drop of blood every tic. So the ground is sampled ONCE, on a
## grid of CELL metres at exactly the points the terrain mesh's finest
## LOD puts its corners on (multiples of 2 m), and gameplay reads the grid
## between them — a microsecond, and the same ground the eye sees.
##
## The grid is made when the island is baked (tools/bake_island.gd) and
## kept beside the terrain's bake under the same signature, so a change
## to the field or to its code makes a new one; without a bake it is
## made at load, on every core (~25 s on a desktop, more on a handheld).
##
## Heights are in METRES, the island's own, at world (x, z): MEWD's map
## (x, y) is (x / 32, -y / 32) — IslandLevel does that arithmetic. Off
## the island is VOID.
class_name IslandGround
extends RefCounted

const CELL := 2.0
const VOID := -1.0e6
## the bake's file name: heights_<signature>.bin, beside terrain_*.bake
const STORE := "heights"
const TERRAIN_BAKE := preload("res://godot/island/scripts/autoload/AUTOLOAD_terrain_bake.gd")

var half := 0.0          # the grid spans -half..half in x and z
var n := 0               # samples a side
var h := PackedFloat32Array()

## THE SIGNATURE: the terrain's own (the field, the chunk size, the code)
## with this grid's spacing on it.
static func signature_for(field: Resource, chunk_size: float) -> String:
	if field.has_method("prepare") and not bool(field.get("_ready")):
		field.prepare()
	# (the autoload's script, not the autoload: a --script tool has none)
	return TERRAIN_BAKE.signature_of([field, {"chunk_size": chunk_size, "ground_cell": CELL}])

## The grid off disk (the bake directories, as the terrain's), or null.
static func load_for(sig: String) -> IslandGround:
	var path := BakeStore.find_bake(STORE, sig)
	if path == "":
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var g := IslandGround.new()
	g.half = f.get_float()
	g.n = f.get_32()
	var bytes := f.get_buffer(g.n * g.n * 4)
	f.close()
	if bytes.size() != g.n * g.n * 4:
		return null
	g.h = bytes.to_float32_array()
	return g

func save_to(path: String) -> bool:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_float(half)
	f.store_32(n)
	f.store_buffer(h.to_byte_array())
	f.close()
	return true

## SAMPLE THE FIELD, on every core: a row a task, EACH WORKER ON A FIELD
## OF ITS OWN. A field fills caches as it is asked (the islands of each
## lattice cell, their zones), and two threads filling one Dictionary at
## once is a crash — which the Linux build met three times running in
## _cell_island. So the field is cloned once a core before the workers
## start (IslandField.clone, as SCRIPT_veg_scatter.gd's workers have
## theirs), and each row takes a clone from the pool and gives it back.
static func build(field: Resource) -> IslandGround:
	if not bool(field.get("_ready")):
		field.prepare()
	var g := IslandGround.new()
	var r: float = float(field.world_max_radius()) * 1.3 + 64.0
	g.half = ceilf(r / CELL) * CELL
	g.n = int(roundf(2.0 * g.half / CELL)) + 1
	# each row its own array, handed in under a lock (a packed array is
	# copied on write, so the rows are not written into one from threads)
	var rows := []
	rows.resize(g.n)
	var lock := Mutex.new()
	var nn := g.n
	var hh := g.half
	# (cloned here, before the workers start, so nothing reads the shared
	# field while another thread is in it: one a core)
	var pool := []
	for k in maxi(1, OS.get_processor_count()):
		pool.append(field.clone())
	var task := WorkerThreadPool.add_group_task(func(row: int) -> void:
		lock.lock()
		var f: Resource = pool.pop_back()
		lock.unlock()
		var z := -hh + row * CELL
		var out := PackedFloat32Array()
		out.resize(nn)
		for i in nn:
			out[i] = f.height_at(-hh + i * CELL, z, VOID)
		lock.lock()
		rows[row] = out
		pool.append(f)
		lock.unlock(), g.n, -1, true, "island ground")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for row_h in rows:
		g.h.append_array(row_h)
	return g

## The ground at world (x, z), metres, between the four samples round it;
## VOID if any of them is off the island (the coast is where it stops).
func height(x: float, z: float) -> float:
	var fx := (x + half) / CELL
	var fz := (z + half) / CELL
	var i := floori(fx)
	var j := floori(fz)
	if i < 0 or j < 0 or i >= n - 1 or j >= n - 1:
		return VOID
	var k := j * n + i
	var a := h[k]
	var b := h[k + 1]
	var c := h[k + n]
	var d := h[k + n + 1]
	if a <= VOID or b <= VOID or c <= VOID or d <= VOID:
		return VOID
	var tx := fx - i
	var tz := fz - j
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

## The ground's normal at world (x, z), from its four neighbours a cell off.
func normal(x: float, z: float) -> Vector3:
	var hx0 := height(x - CELL, z)
	var hx1 := height(x + CELL, z)
	var hz0 := height(x, z - CELL)
	var hz1 := height(x, z + CELL)
	if hx0 <= VOID or hx1 <= VOID or hz0 <= VOID or hz1 <= VOID:
		return Vector3.UP
	return Vector3(hx0 - hx1, 2.0 * CELL, hz0 - hz1).normalized()
