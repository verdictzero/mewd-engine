## MEWD — THE BLACK BOX (at the user's request, after two crashes on the
## handheld — quitting to the main menu, and partway into a lance charge —
## that the desktop never shows: no error, no validation message, nothing
## in a log the handheld lets anybody read).
##
## While the game runs it writes what it is doing, twice a second, to
## user://black_box.txt — the map, the tic, the gun in hand and its charge,
## how much is in the air, the frame rate, and the last thing that happened
## (`mark`) — opened, written and closed each time, so it is on the disk
## whatever kills the process. A clean exit writes "clean". At the next
## start, a box that does not say so is the last half second before the
## crash, and the title shows it (Title, `last_crash`) for a photograph.
class_name BlackBox
extends RefCounted

const PATH := "user://black_box.txt"
## what the last run left, read once at start: "" if it ended cleanly
static var last := ""
static var _read := false
static var _event := "started"
static var _lines := PackedStringArray()
static var _ms := 0

## What the box said when this run started, unless that run was clean.
static func previous() -> String:
	if not _read:
		_read = true
		if FileAccess.file_exists(PATH):
			var t := FileAccess.get_file_as_string(PATH)
			# (put away and never brought back is the phone's doing, not a crash)
			last = "" if t.strip_edges() == "clean" or t.contains("\nlast: app in background") else t
		_write("started " + Time.get_datetime_string_from_system())
	return last

## Something that happened, written now (a quit, a level, a weapon change).
static func mark(what: String) -> void:
	_event = what
	PerfLog.event(what)
	_lines.append("%d %s" % [Time.get_ticks_msec(), what])
	if _lines.size() > 8:
		_lines = _lines.slice(_lines.size() - 8)
	_flush("")

## The state, at most twice a second.
static func state(text: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _ms < 500:
		return
	_ms = now
	_flush(text)

static var _state := ""
static func _flush(text: String) -> void:
	if text != "":
		_state = text
	_write("RUNNING (if you read this at start, the last run did not end cleanly)\n%s\nlast: %s\n%s" % [
		_state, _event, "\n".join(_lines)])

static func clean() -> void:
	_write("clean")

static func _write(t: String) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(t)
		f.close()
