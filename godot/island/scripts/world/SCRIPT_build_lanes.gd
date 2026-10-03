class_name BuildLanes
extends RefCounted

# LONG-RUNNING WORKER LANES, ON THREADS OF THEIR OWN.
#
# `SCRIPT_island_world.gd` and `SCRIPT_veg_scatter.gd` both build their world up
# front the same way: a handful of LANES, each looping on a shared cursor until
# the work list is empty, so the lanes never idle and the frame rate stops being a
# throttle. Both used to raise those lanes with `WorkerThreadPool.add_task(...,
# high_priority = true)`, and this file exists because that is the one thing the
# pool must not be asked to do.
#
# WHY NOT `WorkerThreadPool`. The pool is a fixed set of threads —
# `OS.get_processor_count() - 1` by default, so THREE on a four-core box — and it
# is not ours. THE ENGINE IS A USER OF IT: `PhysicsServer3D` under Jolt queues its
# per-step jobs there, and so does threaded resource loading. A task that returns
# in a millisecond shares those threads with the engine perfectly well. A lane
# that runs for a minute does not share them at all — it OWNS one for the whole
# build.
#
# And there are two lane pools, each sized from the core count. Three terrain
# lanes plus three prescatter lanes against a three-thread pool is not slow, it is
# a POOL WITH NO FREE THREAD IN IT, for as long as the world takes to build.
#
# WHAT THAT COST, MEASURED. On W3 (`tests/PROBE_w3_load_frames.gd`, four cores,
# headless) the first load of the zone spent ONE FRAME OF 46 SECONDS with the
# loading screen up. Jolt printed "job system exceeded the maximum number of jobs
# ... Waiting for jobs to become available" and then blocked the main thread
# inside the physics step: its job records are a fixed-size pool, they are only
# freed by jobs that RUN, and nothing could run because the lanes held every
# thread. The build carried on underneath — the lanes were the ones with the
# threads — so the world finished perfectly while the screen sat frozen at 0% for
# 47 seconds and then caught up in one jump. Every symptom of a hang, with the
# work completing.
#
# Widening the pool to twelve threads on the same four cores removed it — worst
# frame 46,092 ms -> 403 ms — which is the proof it was contention for pool
# threads and not the meshing itself. It is not the fix: twelve lanes on four
# cores made the build slower (83 s against 62 s) for exactly the reason
# `island_world._pregen_retune` climbs its ladder with a stopwatch.
#
# SO THE LANES MOVE OUT. A `Thread` this file owns is scheduled by the OS against
# every other thread in the process, so the pool keeps all three of its threads
# for the engine and the lanes still get the cores when the main thread is idle —
# which, behind a loading screen, is nearly all of the time. Nothing about the
# tuning changes: the caller still decides how many lanes it wants and still
# retires them by headcount, because that logic is about THROUGHPUT and is
# unaffected by which scheduler runs them.
#
# WHAT STAYS IN THE POOL, and should: the per-chunk and per-tile tasks the
# STREAMER dispatches while the player is playing (`island_world._queue_build`,
# `grass_scatter._rescan`). Those are short, bounded in flight, and deliberately
# LOW priority — the pool's cap on low-priority work is a feature there, since a
# tile that lands a frame later costs nothing and a stolen core costs a frame.
#
# THE CALLER STILL OWNS RETIREMENT. This holds threads; it does not know when a
# lane should stop. Both callers publish a width under their own mutex and let a
# lane that finds itself surplus take itself out of the count and return — so
# `join()` is one work item long rather than one build long, PROVIDED the caller
# has told the lanes to retire first. See `island_world._exit_tree`.

## Lanes started and not yet joined. A `Thread` must be waited on before it is
## dropped, so this is also the list of what `join()` owes.
var _threads: Array[Thread] = []
## For the thread's own name in a debugger; purely diagnostic.
var _label := "lane"


func _init(label := "lane") -> void:
	_label = label


## Raise `n` more lanes, each running `body` until it returns.
##
## `body` runs on a thread of its own: it may touch only what the caller has made
## safe for it — a borrowed field, its mutex-guarded cursor and result list — and
## never the scene tree.
func spawn(n: int, body: Callable) -> void:
	for i in maxi(n, 0):
		var t := Thread.new()
		# NORMAL rather than HIGH. The point of moving off the pool is to stop
		# starving the main thread and the engine's own workers; asking the OS to
		# prefer these over both would put half of that back.
		t.start(body, Thread.PRIORITY_NORMAL)
		_threads.append(t)


## Release the records of lanes that have already run out.
##
## A build that narrows and widens again raises a thread every time, so without
## this the records accumulate for the whole session behind lanes that finished in
## the first minute. Only ever waits on a thread that has already returned, so it
## cannot block.
func reap() -> void:
	var live: Array[Thread] = []
	for t in _threads:
		if t.is_alive():
			live.append(t)
		else:
			t.wait_to_finish()
	_threads = live


## Wait every lane out and forget them.
##
## BOUNDED ONLY IF THE CALLER HAS RETIRED THEM. A lane loops until its list is
## empty; joining one that still has five hundred items to claim stalls for the
## rest of the build. Publish a width of zero first — see this file's header.
func join() -> void:
	for t in _threads:
		t.wait_to_finish()
	_threads.clear()


## Lanes raised and not yet joined, INCLUDING ones that have already returned.
## Diagnostic only: the callers count live lanes themselves, under the same lock
## they publish the width with, because that count is what a lane retires against
## and it has to be exact.
func count() -> int:
	return _threads.size()
