## MEWD — THE PERFORMANCE LOG (at the user's request: first "massive lag
## with too many decals — don't correct anything yet, but add verbose
## logging to a log file", then "add logging for LITERALLY EVERYTHING with
## frame and cpu counts"). Nothing here changes what is drawn or run; it
## only writes down what everything cost, so the lag can be found from a
## run that had it.
##
## WHERE: on a desktop, mewd-perf.log in the user's home folder (~ on
## Linux and the Mac, %USERPROFILE% on Windows); on the handheld, in
## user:// (Android lets nobody else write the home folder). Each game
## writes it afresh, and the run before is kept as mewd-perf.prev.log.
##
## WHAT, in time order, every line stamped with the milliseconds since the
## game began and the frame:
##   FRAME  EVERY FRAME: how long the frame took (wall), what the engine
##          says the whole of _process and _physics_process cost, the
##          renderer's CPU and GPU time for the frame before, draw calls,
##          primitives, objects; then the time of EVERY PART of the game's
##          frame in milliseconds (Game._process and Game.tic are cut into
##          sections — `sec:` — each timed with the microsecond clock, and
##          the island's own nodes, which run their _process from here so
##          they can be timed too: `isl.`), `other` being what the engine's
##          process total has that no section accounts for; then the COUNTS
##          (`n:`): tics this frame, actors awake and asleep, sprite rows
##          written, pieces, gibs, particles, missiles, bores, live marks
##          by pool, nodes, objects, orphans, static memory, video memory;
##          and the DOINGS (`did:`): what happened this frame — hitscans,
##          spawns, wounds, gibs, blasts, marks laid by kind, plant rows
##          written, whether the plant scatter is owed a rescan
##   PLACE  every mark laid: its pool, what it is, the slot it took, how
##          many of the pool are live after it, where, how big
##   SEC    once a second: the frame rate, the slowest frame, and the
##          average of every section over the second (ms), biggest first
##   SPIKE  any frame over SPIKE_MS: its three biggest sections
##   EVENT  anything the game marks (a level, a death, a gun change,
##          a pause: PerfLog.event)
## Every line goes into a buffer that is flushed once a second (and at the
## end), so the log costs strings, not disk writes, and its own cost is on
## the FRAME line (`log`).
class_name PerfLog
extends Node

const NAME := "mewd-perf.log"
const PREV := "mewd-perf.prev.log"
const SPIKE_MS := 40.0
## kinds by number, for reading (Decals.KIND_*, GoreDecals.KIND_*)
const KINDS := {0: "hole", 1: "hot-hole", 2: "blood", 3: "scorch", 4: "heat", 5: "spatter", 6: "pool",
	8: "sear", 9: "slag", 10: "blast", 11: "streak", 12: "nuke", 13: "shock"}
## the island's nodes whose _process is run (and timed) from here
const ISLAND_NODES := ["IslandWorld", "VegScatter", "GrassScatter", "VegBurn", "TimeOfDay", "CloudSea", "HorizonClouds"]

static var inst: PerfLog = null

var game
var path := ""
var _f: FileAccess
var _buf := PackedStringArray()
var _t0 := 0
var _frame := 0
var _last_us := 0
## this frame's sections (usec) and doings
var _sec := {}
var _did := {}
## the second's sums
var _sec_t := 0
var _sec_frames := 0
var _sec_worst := 0.0
var _sec_sum := {}
var _sec_placed := 0
var _total_placed := 0
var _frame_kinds := {}
## the island's nodes run from here: [node, name]
var _island := []
var _own_us := 0

## The log's path on this machine.
static func where() -> String:
	if OS.has_feature("android") or OS.has_feature("web"):
		return "user://" + NAME
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	if home == "":
		return "user://" + NAME
	return home.path_join(NAME)

## Started for a game (Game.start_map); stopped when the game goes. Not
## in a headless run (the tests) unless asked for with --perf-log.
static func begin(g) -> void:
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--perf-log"):
		return
	# (not a host's world, which nobody looks at — a game hosted from the
	# title has one beside the player's)
	if not g.draw_world:
		return
	if inst != null and is_instance_valid(inst):
		inst.queue_free()
	var l := PerfLog.new()
	l.game = g
	l.name = "PerfLog"
	g.add_child(l)
	inst = l

## A SECTION of the frame: `usec` spent on `key` (added, if the key comes
## twice in a frame).
static func section(key: String, usec: int) -> void:
	if inst != null:
		inst._sec[key] = int(inst._sec.get(key, 0)) + usec

## Something that was DONE this frame, counted: a hitscan, a spawn...
static func did(key: String, n := 1) -> void:
	if inst != null:
		inst._did[key] = int(inst._did.get(key, 0)) + n

## Something that happened, written now.
static func event(what: String) -> void:
	if inst != null:
		inst._line("EVENT " + what)

## A MARK LAID (Decals, GoreDecals): its pool, kind, the slot it took,
## the pool's live count and size after it, where (map units) and how big.
static func placed(pool: String, kind: float, slot: int, live: int, cap: int, at: Vector3, size: float) -> void:
	if inst == null:
		return
	inst._placed(pool, kind, slot, live, cap, at, size)

func _ready() -> void:
	path = where()
	if FileAccess.file_exists(path):
		var prev := path.get_base_dir().path_join(PREV)
		DirAccess.rename_absolute(path, prev)
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		push_warning("perf log: cannot write " + path + " (" + error_string(FileAccess.get_open_error()) + ")")
		return
	_t0 = Time.get_ticks_msec()
	_sec_t = _t0
	_last_us = Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# the island's nodes, run from _process here so each can be timed
	var isl = game.get("island")
	if isl != null:
		for n in ISLAND_NODES:
			var node: Node = isl.get_node_or_null(n)
			if node != null and node.has_method("_process") and node.is_processing():
				node.set_process(false)
				_island.append([node, n])
	var vs := DisplayServer.window_get_size()
	_line("BEGIN %s  map=%s  os=%s  cpu=%s x%d  gpu=%s (%s)  api=%s  renderer=%s  window=%dx%d  render=%s  vsync=%d  max_fps=%d" % [
		Time.get_datetime_string_from_system(), str(game.get("map_name")), OS.get_name(),
		OS.get_processor_name(), OS.get_processor_count(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), vs.x, vs.y,
		str(get_viewport().get_visible_rect().size), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	_line("POOLS hole=%d blood=%d heat=%d sear=%d blast=%d gore=%d  (one MultiMesh of boxes a pool; each box a projected decal)" % [
		Decals.POOLS.hole, Decals.POOLS.blood, Decals.POOLS.heat, Decals.SEAR_POOL, Decals.BLAST_POOL, GoreDecals.CAP])
	_line("ISLAND nodes timed from here: " + ", ".join(_island.map(func(e): return e[1])))
	_line("columns: FRAME ms=wall process=the engine's whole _process physics=_physics_process render_cpu/gpu=the frame before's draws prims objs | sec: Game's sections and the island's nodes (isl.), ms | other=process minus the sections | n: counts | did: what happened this frame")
	_line("columns: SEC fps worst_ms placed | the sections' average ms over the second, biggest first || PLACE pool kind slot live/cap at=(x,y,z) size || SPIKE ms, the three biggest sections")
	_flush()

func _exit_tree() -> void:
	for e in _island:
		if is_instance_valid(e[0]):
			e[0].set_process(true)
	if _f != null:
		_line("END after %d frames, %d marks" % [_frame, _total_placed])
		_flush()
		_f.close()
		_f = null
	if inst == self:
		inst = null

func _line(s: String) -> void:
	_buf.append("[%8d f%7d] %s" % [Time.get_ticks_msec() - _t0, _frame, s])

func _flush() -> void:
	if _f == null or _buf.is_empty():
		return
	_f.store_string("\n".join(_buf) + "\n")
	_f.flush()
	_buf.clear()

func _placed(pool: String, kind: float, slot: int, live: int, cap: int, at: Vector3, size: float) -> void:
	if _f == null:
		return
	var k := int(kind)
	var kn: String = KINDS.get(k, str(k))
	_line("PLACE %-5s %-8s slot=%-4d live=%d/%d at=(%.0f,%.0f,%.0f) size=%.1f%s" % [
		pool, kn, slot, live, cap, at.x, at.y, at.z, size, "  (pool full: oldest overwritten)" if live >= cap else ""])
	_sec_placed += 1
	_total_placed += 1
	_frame_kinds[kn] = int(_frame_kinds.get(kn, 0)) + 1
	did("mark." + kn)

## After Game._process (a child runs after its parent): the island's nodes
## run and timed, then the frame written.
func _process(dt: float) -> void:
	if _f == null:
		return
	var own0 := Time.get_ticks_usec()
	for e in _island:
		var t0 := Time.get_ticks_usec()
		e[0]._process(dt)
		_sec["isl." + e[1]] = int(_sec.get("isl." + e[1], 0)) + Time.get_ticks_usec() - t0
	_frame_line(own0)

func _frame_line(own0: int) -> void:
	var now_us := Time.get_ticks_usec()
	var ms := (now_us - _last_us) / 1000.0
	_last_us = now_us
	_frame += 1
	_sec_frames += 1
	_sec_worst = maxf(_sec_worst, ms)
	var vp := get_viewport().get_viewport_rid()
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	# the sections, in a fixed order so a column is a column
	var keys := _sec.keys()
	keys.sort()
	var parts := PackedStringArray()
	var accounted := 0
	for k in keys:
		var us: int = _sec[k]
		accounted += us
		parts.append("%s=%.2f" % [k, us / 1000.0])
	var other := process_ms - accounted / 1000.0 - _own_us / 1000.0
	# the counts
	var d = game.get("decals")
	var marks := PackedStringArray()
	var live := 0
	if d != null:
		for k in d.pools:
			var c: int = d.pools[k].mm.visible_instance_count
			live += c
			marks.append("%s=%d" % [k, c])
	var gd = game.get("gore_decals")
	if gd != null:
		live += gd.mm.visible_instance_count
		marks.append("gore=%d" % gd.mm.visible_instance_count)
	var counts := "tics=%d awake=%d asleep=%d actors=%d rows=%d pieces=%d gibs=%d particles=%d missiles=%d bores=%d marks=%d(%s) heat_spots=%d nodes=%d objs=%d orphans=%d mem=%.1fMB vram=%.0fMB" % [
		int(_did.get("tic", 0)), game.awake.size(), game.asleep, game.actors.size(),
		game.standees.written if game.get("standees") != null else 0,
		game.chunks.count() if game.get("chunks") != null else 0,
		game.giblets.live_count() if game.get("giblets") != null else 0,
		game.fx.live_count() if game.get("fx") != null else 0,
		game.missiles.shots.size() if game.get("missiles") != null else 0,
		game.bore.shots.size() + game.bore.drilling.size() if game.get("bore") != null else 0,
		live, " ".join(marks), int(d.get("_hlive")) if d != null else 0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0]
	# the doings
	var dkeys := _did.keys()
	dkeys.sort()
	var did_s := PackedStringArray()
	for k in dkeys:
		if k == "tic":
			continue
		did_s.append("%s=%d" % [k, _did[k]])
	var vd = game.get("veg_damage")
	if vd != null and vd.veg != null:
		did_s.append("veg.rescan_owed=%d veg.pending=%d veg.todo=%d" % [
			1 if vd.veg.get("_force_rescan") else 0, vd.veg._pending.size(), int(vd.veg.get("_todo"))])
	if vd != null and vd.grass != null:
		did_s.append("grass.rescan_owed=%d grass.pending=%d" % [1 if vd.grass.get("_force_rescan") else 0, vd.grass._pending.size()])
	_own_us = Time.get_ticks_usec() - own0
	_line("FRAME ms=%.2f process=%.2f physics=%.2f render_cpu=%.2f render_gpu=%.2f draws=%d prims=%d objs=%d | sec: %s | other=%.2f log=%.2f | n: %s | did: %s" % [
		ms, process_ms, physics_ms,
		RenderingServer.viewport_get_measured_render_time_cpu(vp),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		" ".join(parts), other, _own_us / 1000.0, counts, " ".join(did_s)])
	if ms > SPIKE_MS and _frame > 2:
		var top := keys.duplicate()
		top.sort_custom(func(a, b): return int(_sec[a]) > int(_sec[b]))
		var t3 := PackedStringArray()
		for k in top.slice(0, 3):
			t3.append("%s=%.1f" % [k, int(_sec[k]) / 1000.0])
		_line("SPIKE %.1f ms  biggest: %s  laid=%s" % [ms, " ".join(t3), str(_frame_kinds) if not _frame_kinds.is_empty() else "none"])
	for k in _sec:
		_sec_sum[k] = int(_sec_sum.get(k, 0)) + int(_sec[k])
	_sec.clear()
	_did.clear()
	_frame_kinds.clear()
	var now := Time.get_ticks_msec()
	if now - _sec_t >= 1000:
		_second(now)

## The once-a-second line: the frame rate, and every section's average.
func _second(now: int) -> void:
	var secs := (now - _sec_t) / 1000.0
	_sec_t = now
	var keys := _sec_sum.keys()
	keys.sort_custom(func(a, b): return int(_sec_sum[a]) > int(_sec_sum[b]))
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%.2f" % [k, int(_sec_sum[k]) / 1000.0 / maxi(_sec_frames, 1)])
	_line("SEC fps=%.1f worst=%.1fms placed=%d (total %d) | %s" % [
		_sec_frames / maxf(secs, 0.001), _sec_worst, _sec_placed, _total_placed, " ".join(parts)])
	_sec_frames = 0
	_sec_worst = 0.0
	_sec_placed = 0
	_sec_sum.clear()
	_flush()
