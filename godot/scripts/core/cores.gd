## MEWD — EVERY CORE, at the user's request ("this runs like crap on my
## old xeon 2.4ghz box because cpu events are only using 1 core, can we
## have it use all available processors in parallel?").
##
## RENDERING ON A THREAD OF ITS OWN (project.godot's thread model,
## "Separate"): Godot's renderer — what is in view, the culling, the GPU's
## command lists for every viewport — ran on the game's own thread after
## the game's work, so a frame cost the two ADDED. On a thread of its own
## it draws one frame while the game works out the next, and a frame costs
## the SLOWER of the two (and CANDY LAND loaded in 6 s instead of 20
## here). Godot 4.7 still calls that experimental, so it is the default on
## the desktop and not yet on Android (project.godot's `.android` override; the
## dedicated server draws nothing, `.server`). The DEBUG page's RENDER
## THREAD says otherwise for the next launch: Godot reads `RENDER_CFG`
## (project.godot's project_settings_override) before anything starts.
##
## The island's chunks are built on the rest already (WorkerThreadPool,
## IslandWorld). THE CROWD STAYS ON THE GAME'S THREAD, in order: who stands
## where decides who can step where, and the one question each asks that
## only reads the world (A_Watch) was tried spread over every core and was
## slower — twenty-odd questions a tic of a fiftieth of a millisecond each
## are less than waking the threads costs. It was made cheaper instead
## (Actor.can_stand_at, A_Watch).
class_name Cores

const RENDER_CFG := "user://render_thread.cfg"
## the DEBUG page's RENDER THREAD: auto (project.godot's), own, main
const RENDER_WAYS := ["auto", "own", "main"]

## the cores there are
static func count() -> int:
	return maxi(1, OS.get_processor_count())

## is the renderer on a thread of its own this run?
static func render_own() -> bool:
	return not RenderingServer.is_on_render_thread()

## what the DEBUG page asked for the next launch ("auto" when nothing has)
static func render_wanted() -> String:
	if not FileAccess.file_exists(RENDER_CFG):
		return "auto"
	return "own" if FileAccess.get_file_as_string(RENDER_CFG).contains("thread_model=2") else "main"

## where the renderer will be next launch: what the DEBUG page asked, or
## project.godot's (its own on the desktop, the game's on Android and the
## server)
static func render_next() -> String:
	var w := render_wanted()
	if w != "auto":
		return w
	return "main" if OS.has_feature("android") or OS.has_feature("server") else "own"

## The DEBUG page's RENDER THREAD, for the next launch: "own" or "main"
## written over project.godot's choice (for Android too: its own
## override would win over a plain one), "auto" back to it.
static func want_render(how: String) -> void:
	if how != "own" and how != "main":
		if FileAccess.file_exists(RENDER_CFG):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(RENDER_CFG))
		return
	var m := 2 if how == "own" else 1
	var text := "; MEWD: the DEBUG page's RENDER THREAD (Cores.want_render)\n[rendering]\n\ndriver/threads/thread_model=%d\ndriver/threads/thread_model.android=%d\n" % [m, m]
	if FileAccess.file_exists(RENDER_CFG) and FileAccess.get_file_as_string(RENDER_CFG) == text:
		return
	var f := FileAccess.open(RENDER_CFG, FileAccess.WRITE)
	if f == null:
		push_warning("render thread: cannot write " + RENDER_CFG)
		return
	f.store_string(text)
	f.close()

## the readout's line (PerfOverlay): the cores, and where the renderer is
## (and where it will be, when the DEBUG page has changed it)
static func state() -> String:
	var now := "own" if render_own() else "main"
	var want := render_next()
	var next := ""
	if want != now:
		next = " (next launch: %s)" % ("its own" if want == "own" else "the game's")
	return "%d cores · render thread %s%s" % [count(), "its own" if now == "own" else "the game's", next]
