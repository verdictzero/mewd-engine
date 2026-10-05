## MEWD — REAL LOGS OFF THE HANDHELD (at the user's request: "have the
## android app ask for file permission so we can generate real logs").
##
## The black box (BlackBox) is half a second of state in a file the
## phone lets nobody read. This is the whole run: EVERY LINE the engine
## prints — prints, warnings, errors with their script backtraces — is
## MIRRORED (a Logger added with OS.add_logger) into a file in the
## phone's SHARED STORAGE, written and flushed line by line so it is on
## the disk whatever kills the process:
##
##     /storage/emulated/0/Download/mewd/mewd.log     this run
##                                       mewd-1.log   the one before
##                                       mewd-2.log   the one before that
##                                       black_box.txt
##
## readable over USB, with a file manager, or from `adb pull`. THE
## PERMISSION: on Android the app asks for storage at start
## (OS.request_permissions: the export preset declares READ and WRITE
## EXTERNAL STORAGE and, for Android 11 and up where those are nothing,
## MANAGE EXTERNAL STORAGE, which is the "all files access" page). Until
## it is granted the log goes to the app's own folder, and the moment
## it is the file is moved out to Download/mewd with everything so far.
## The title says where the logs are (Main). On a desktop the same file
## is kept under the user data folder (`logs/`): the mirror is the same
## everywhere; only the folder differs.
class_name Logs
extends RefCounted

const NAME := "mewd.log"
const KEEP := 2
## the folder the logs are in, "" until one is open
static var dir := ""
## on the phone's shared storage, readable from outside the app
static var external := false
## called whenever `dir` or `external` changes (the title's line)
static var changed: Callable
static var _file: FileAccess = null
static var _mirror: Logger = null
static var _pending := PackedStringArray()
static var _asked := false

## Set the mirror up and open the file; on Android, ask for the storage.
static func setup(tree: SceneTree) -> void:
	# (MEWD_NOLOGS in the environment: none of this, for telling it apart)
	if OS.get_environment("MEWD_NOLOGS") != "":
		return
	if _mirror == null:
		_mirror = Mirror.new()
		OS.add_logger(_mirror)
	if OS.get_name() == "Android":
		if tree != null and not tree.on_request_permissions_result.is_connected(_on_permission):
			tree.on_request_permissions_result.connect(_on_permission)
		# (true: everything already granted, and no answer will come)
		_asked = true
		OS.request_permissions()
	_open()

## The phone's answer, one permission at a time: once anything storage
## is granted, try the shared folder again.
static func _on_permission(permission: String, granted: bool) -> void:
	line("permission %s: %s" % [permission, "granted" if granted else "denied"])
	if granted and not external:
		_open()

## The folders to try, best first: the shared Download folder (needs
## the permission), the app's own folder on the shared storage (no
## permission needed, but only there once something made it), and the
## app's private folder, which always works.
static func _candidates() -> Array:
	var out := []
	if OS.get_name() == "Android":
		var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
		if dl != "":
			out.append([dl.path_join("mewd"), true])
		out.append(["/storage/emulated/0/Download/mewd", true])
		out.append(["/sdcard/Download/mewd", true])
		out.append(["/storage/emulated/0/Android/data/com.verdictzero.mewd/files/mewd", true])
	out.append([OS.get_user_data_dir().path_join("logs"), false])
	return out

## A folder we can write in, made if need be.
static func _writable(path: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(path) != OK and not DirAccess.dir_exists_absolute(path):
		return false
	var probe := path.path_join(".probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(probe)
	return true

## Open the log in the best folder reachable now. Opened again in the
## same folder (the scene reloaded, or the permission came and brought
## nothing better) it carries on in the same file; moved to a better
## folder, what was written so far goes with it.
static func _open() -> void:
	var sofar := ""
	if _file != null:
		_file.close()
		_file = null
	if dir != "":
		sofar = FileAccess.get_file_as_string(dir.path_join(NAME))
	for c in _candidates():
		if not _writable(c[0]):
			continue
		if c[0] == dir:
			_file = FileAccess.open(dir.path_join(NAME), FileAccess.READ_WRITE)
			if _file != null:
				_file.seek_end()
				for l in _pending:
					_file.store_string(l + "\n")
				_pending.clear()
				_file.flush()
				return
		dir = c[0]
		external = c[1]
		_rotate()
		_file = FileAccess.open(dir.path_join(NAME), FileAccess.WRITE)
		if _file == null:
			continue
		if sofar != "":
			_file.store_string(sofar)
		else:
			_file.store_string("MEWD %s — %s — %s %s — %s — %s\n" % [
				ProjectSettings.get_setting("application/config/name", "MEWD"),
				Time.get_datetime_string_from_system(), OS.get_name(), OS.get_version(),
				OS.get_model_name(), RenderingServer.get_video_adapter_name()])
			for l in _pending:
				_file.store_string(l + "\n")
			_pending.clear()
		_file.flush()
		if changed.is_valid() and is_instance_valid(changed.get_object()):
			changed.call()
		return
	dir = ""
	external = false

## mewd-1 becomes mewd-2, mewd becomes mewd-1: KEEP old runs kept.
static func _rotate() -> void:
	for k in range(KEEP, 0, -1):
		var older := dir.path_join("mewd-%d.log" % k)
		var newer := dir.path_join("mewd-%d.log" % (k - 1)) if k > 1 else dir.path_join(NAME)
		if FileAccess.file_exists(older):
			DirAccess.remove_absolute(older)
		if FileAccess.file_exists(newer):
			DirAccess.rename_absolute(newer, older)

## The mirror taken down and the file closed: before the engine goes
## (a logger left in while the scripts are torn down is a crash at
## exit). The next setup() carries on in the same file.
static func shutdown() -> void:
	changed = Callable()
	if _mirror != null:
		OS.remove_logger(_mirror)
		_mirror = null
	if _file != null:
		_file.flush()
		_file.close()
		_file = null

## One line into the log, flushed. (Never prints: the mirror would
## bring it straight back.)
static func line(t: String) -> void:
	var stamp := "%8.3f " % (Time.get_ticks_msec() / 1000.0)
	if _file == null:
		_pending.append(stamp + t)
		if _pending.size() > 400:
			_pending.remove_at(0)
		return
	_file.store_string(stamp + t + "\n")
	_file.flush()

## A copy of `text` kept beside the log as `name` (the black box).
static func keep(name: String, text: String) -> void:
	if dir == "":
		return
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

## What the title says about it.
static func where() -> String:
	if dir == "":
		return "LOGS: NOWHERE (no folder could be written)"
	if OS.get_name() == "Android" and not external:
		return "LOGS: %s (STORAGE PERMISSION NOT GIVEN: in the app's own folder)" % dir
	return "LOGS: " + dir

## THE MIRROR: everything the engine prints, as it prints it.
class Mirror extends Logger:
	func _log_message(message: String, error: bool) -> void:
		var m := message.rstrip("\n")
		if m == "":
			return
		Logs.line(("! " if error else "") + m)
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		Logs.line("%s: %s%s\n     at: %s (%s:%d)" % [kind, code, (" — " + rationale) if rationale != "" else "", function, file, line])
		for bt in script_backtraces:
			Logs.line("     " + str(bt).replace("\n", "\n     "))
