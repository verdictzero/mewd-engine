## MEWD — THE DECAL LOG (at the user's request: "massive lag with too many
## decals — don't correct anything yet, but add verbose logging to a log
## file"). Nothing here changes what is drawn; it only writes down what
## the marks cost, so the lag can be found from a run that had it.
##
## WHERE: on a desktop, mewd-decals.log in the user's home folder (~ on
## Linux and the Mac, %USERPROFILE% on Windows); on the handheld, in
## user:// (Android lets nobody else write the home folder). Each game
## writes it afresh, and the run before is kept as mewd-decals.prev.log.
##
## WHAT, in time order, every line stamped with the milliseconds since the
## game began and the frame:
##   PLACE  every mark laid: its pool, what it is, the slot it took, how
##          many of the pool are live after it, where, how big
##   SEC    once a second: the frame rate, the slowest frame, the CPU's and
##          the GPU's render time, draw calls, primitives, objects, video
##          memory; every pool's live count, how many marks were laid that
##          second, how many live marks are in front of the eye and the
##          share of the screen they cover added up (COVERAGE: 3.0 is every
##          pixel painted three times over by decal boxes — fill, which is
##          what a projected decal costs a Mali); and the crowd, the pieces
##          and the gibs in the air, for comparison
##   SPIKE  any frame over SPIKE_MS, with what was laid in it
## and every line written into a buffer that is flushed once a second
## (and at the end), so the log costs a string a mark, not a disk write.
class_name DecalLog
extends Node

const NAME := "mewd-decals.log"
const PREV := "mewd-decals.prev.log"
const SPIKE_MS := 40.0
## kinds by number, for reading (Decals.KIND_*, GoreDecals.KIND_*)
const KINDS := {0: "hole", 1: "hot-hole", 2: "blood", 3: "scorch", 4: "heat", 5: "spatter", 6: "pool",
	8: "sear", 9: "slag", 10: "blast", 11: "streak", 12: "nuke", 13: "shock"}

static var inst: DecalLog = null

var game
var path := ""
var _f: FileAccess
var _buf := PackedStringArray()
var _t0 := 0
var _frame := 0
var _sec_t := 0
var _sec_frames := 0
var _sec_worst := 0.0
var _sec_placed := 0
var _frame_placed := 0
var _frame_kinds := {}
var _total_placed := 0
var _last_us := 0

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
## in a headless run (the tests) unless asked for with --decal-log.
static func begin(g) -> void:
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--decal-log"):
		return
	if inst != null and is_instance_valid(inst):
		inst.queue_free()
	var l := DecalLog.new()
	l.game = g
	l.name = "DecalLog"
	g.add_child(l)
	inst = l

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
		push_warning("decal log: cannot write " + path + " (" + error_string(FileAccess.get_open_error()) + ")")
		return
	_t0 = Time.get_ticks_msec()
	_sec_t = _t0
	_last_us = Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var vs := DisplayServer.window_get_size()
	_line("BEGIN %s  map=%s  os=%s  gpu=%s (%s)  api=%s  renderer=%s  window=%dx%d  render=%s" % [
		Time.get_datetime_string_from_system(), str(game.get("map_name")), OS.get_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_video_adapter_api_version(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), vs.x, vs.y,
		str(get_viewport().get_visible_rect().size)])
	_line("POOLS hole=%d blood=%d heat=%d sear=%d blast=%d gore=%d  (one MultiMesh of boxes a pool; each box a projected decal)" % [
		Decals.POOLS.hole, Decals.POOLS.blood, Decals.POOLS.heat, Decals.SEAR_POOL, Decals.BLAST_POOL, GoreDecals.CAP])
	_line("columns: PLACE pool kind slot live/cap at=(x,y,z) size | SEC fps worst_ms cpu_ms gpu_ms draws prims objs vram_mb | pools | placed | onscreen coverage | crowd pieces gibs | log_ms")
	_flush()

func _exit_tree() -> void:
	if _f != null:
		_line("END after %d marks" % _total_placed)
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
	_frame_placed += 1
	_total_placed += 1
	_frame_kinds[kn] = int(_frame_kinds.get(kn, 0)) + 1

func _process(_dt: float) -> void:
	if _f == null:
		return
	var now_us := Time.get_ticks_usec()
	var ms := (now_us - _last_us) / 1000.0
	_last_us = now_us
	_frame += 1
	_sec_frames += 1
	_sec_worst = maxf(_sec_worst, ms)
	if ms > SPIKE_MS and _frame > 2:
		_line("SPIKE %.1f ms  laid this frame=%d %s  live=%d" % [ms, _frame_placed, str(_frame_kinds) if _frame_placed > 0 else "", _live_total()])
	_frame_placed = 0
	_frame_kinds.clear()
	var now := Time.get_ticks_msec()
	if now - _sec_t >= 1000:
		_second(now)

func _live_total() -> int:
	var n := 0
	var d = game.get("decals")
	if d != null:
		for k in d.pools:
			n += d.pools[k].mm.visible_instance_count
	var g = game.get("gore_decals")
	if g != null:
		n += g.mm.visible_instance_count
	return n

## The once-a-second line.
func _second(now: int) -> void:
	var t0 := Time.get_ticks_usec()
	var secs := (now - _sec_t) / 1000.0
	_sec_t = now
	var vp := get_viewport().get_viewport_rid()
	var parts := PackedStringArray()
	var mms := []
	var d = game.get("decals")
	if d != null:
		for k in d.pools:
			var p = d.pools[k]
			parts.append("%s=%d/%d" % [k, p.mm.visible_instance_count, p.cap])
			mms.append(p.mm)
		parts.append("heat_spots=%d" % int(d.get("_hlive")))
	var g = game.get("gore_decals")
	if g != null:
		parts.append("gore=%d/%d" % [g.mm.visible_instance_count, GoreDecals.CAP])
		mms.append(g.mm)
	var cov := _coverage(mms)
	var crowd := "awake=%d asleep=%d actors=%d" % [game.awake.size(), game.asleep, game.actors.size()]
	var pieces: int = game.chunks.count() if game.get("chunks") != null else 0
	var gibs: int = game.giblets.live_count() if game.get("giblets") != null else 0
	_line("SEC fps=%.1f worst=%.1fms cpu=%.2fms gpu=%.2fms setup=%.2fms draws=%d prims=%d objs=%d vram=%.0fMB | %s live=%d | placed=%d (total %d) | onscreen=%d coverage=%.2f screens | %s pieces=%d gibs=%d | log=%.2fms" % [
		_sec_frames / maxf(secs, 0.001), _sec_worst,
		RenderingServer.viewport_get_measured_render_time_cpu(vp),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		" ".join(parts), _live_total(), _sec_placed, _total_placed, cov.x, cov.y,
		crowd, pieces, gibs, (Time.get_ticks_usec() - t0) / 1000.0])
	_sec_frames = 0
	_sec_worst = 0.0
	_sec_placed = 0
	_flush()

## How many live marks stand in front of the eye, and the share of the
## screen their boxes cover, added up (each box taken as the square its
## width makes at its distance).
func _coverage(mms: Array) -> Vector2:
	var cam: Camera3D = game.get("camera")
	if cam == null:
		return Vector2.ZERO
	var vs := get_viewport().get_visible_rect().size
	var area := maxf(1.0, vs.x * vs.y)
	var focal := vs.y * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
	var fwd := -cam.global_transform.basis.z
	var eye := cam.global_position
	var n := 0
	var cover := 0.0
	for mm: MultiMesh in mms:
		for i in mm.visible_instance_count:
			var t := mm.get_instance_transform(i)
			var size := t.basis.x.length()
			if size <= 0.0:
				continue
			var depth := (t.origin - eye).dot(fwd)
			if depth <= -size:
				continue
			# (the eye in or against the box: all of the screen, near enough)
			if depth < size:
				n += 1
				cover += 1.0
				continue
			var px := size * focal / depth
			var sp := cam.unproject_position(t.origin)
			if sp.x < -px or sp.y < -px or sp.x > vs.x + px or sp.y > vs.y + px:
				continue
			n += 1
			cover += minf(px * px, area) / area
	return Vector2(n, cover)
