## MEWD — the wood's simulation, headless (Forest, js/forest.js).
##
## godot --headless --script res://godot/tests/forest_test.gd -- [seed]
##
## 1. PLACED: MazeMap.build(seed) through DocCompile, a Forest over its
##    PLANT things (a tree in each plaza). Checks the trunk blocks and
##    the crown catches the flame's question, lights one tree and runs
##    it to the end (with the maze's noBurn lifted) — a tree in a plaza
##    is a tree on fire, not a forest fire, so exactly its own cell burns.
## 2. SCATTER: the same level with a forest floor laid over a corner of
##    it, planted by the golf scatter; one match, and the front is
##    printed every 1000 tics as it walks.
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 7
	var doc := MazeMap.build(seed)
	# the maze's world is noBurn (the editor's default world): nothing
	# catches there, the plaza trees included — so it is lifted here
	doc.world["noBurn"] = false
	var lv := DocCompile.compile(doc)
	U.p_seed()
	var ok := true
	var t0 := Time.get_ticks_msec()
	var f := Forest.new(lv)
	print("placed: %d trees, %d plants, grid %dx%d, built in %d ms" % [f.tree_count(), f.plant_count(), f.cols, f.rows, Time.get_ticks_msec() - t0])
	if f.tree_count() == 0:
		print("FAIL: no trees")
		quit(1)
		return
	var tx := f.trees.x[0]
	var ty := f.trees.y[0]
	var tz := f.trees.z[0]
	var k: Dictionary = Forest.KINDS[f.trees.kind[0]]
	print("tree 0: %s at (%d, %d) floor %d" % [k.name, tx, ty, tz])
	ok = _check("blocks at the trunk", f.blocks(tx + 4, ty, 16.0), true) and ok
	ok = _check("clear of the trunk", f.blocks(tx + 60, ty, 16.0), false) and ok
	ok = _check("hits the crown", f.hits_tree(tx + 10, ty, tz + float(k.h) * 0.4), true) and ok
	ok = _check("misses above it", f.hits_tree(tx, ty, tz + float(k.h) * 1.2), false) and ok
	var lit := f.ignite(tx, ty, 26.0)
	ok = _check("one cell lit", lit, 1) and ok
	for i in 2000:
		f.tic()
	ok = _check("burnt through", f.state[f.trees.cell[0]], 2) and ok
	ok = _check("nothing still alight", f.active.size(), 0) and ok
	print("placed burn %.0f%%" % (f.burn_fraction() * 100.0))

	# ---- the scatter
	var b := lv.bounds
	var rect := Rect2(b.position, b.size * 0.5)
	t0 = Time.get_ticks_msec()
	var w := Forest.new(lv, {"rects": [rect], "plants": [], "seed": 5})
	print("scatter: %d trees, %d plants over %d fuel cells, built in %d ms" % [w.tree_count(), w.plant_count(), w.fuel_cells, Time.get_ticks_msec() - t0])
	ok = _check("scatter planted trees", w.tree_count() > 0, true) and ok
	var c := rect.get_center()
	w.ignite(c.x, c.y, 80.0)
	for i in 6000:
		w.tic()
		if (i + 1) % 1000 == 0:
			print("  tic %5d  burnt %5.1f%%  alight %4d  hot %d" % [i + 1, w.burn_fraction() * 100.0, w.active.size(), w.burning_cells()])
	ok = _check("the front walked", w.burn_fraction() > 0.05, true) and ok
	print("OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _check(what: String, got, want) -> bool:
	var good: bool = got == want
	print("  %s %s: %s" % ["ok  " if good else "FAIL", what, str(got)])
	return good
