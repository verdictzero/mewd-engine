## MEWD — the wood, headless (Forest, js/forest.js's planting).
##
## godot --headless --script res://godot/tests/forest_test.gd -- [seed]
##
## 1. PLACED: MazeMap.build(seed) through DocCompile, a Forest over its
##    PLANT things (a tree in each plaza). Checks the trunk blocks and
##    the crown catches the flame's question.
## 2. SCATTER: the same level with a forest floor laid over a corner of
##    it, planted by the golf scatter: trees and understory come up, and
##    the trunks block.
## (The wood's fire went with the fire that spread, at the user's request.)
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 7
	var doc := MazeMap.build(seed)
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

	# ---- the scatter
	var b := lv.bounds
	var rect := Rect2(b.position, b.size * 0.5)
	t0 = Time.get_ticks_msec()
	var w := Forest.new(lv, {"rects": [rect], "plants": [], "seed": 5})
	print("scatter: %d trees, %d plants over %d fuel cells, built in %d ms" % [w.tree_count(), w.plant_count(), w.fuel_cells, Time.get_ticks_msec() - t0])
	ok = _check("scatter planted trees", w.tree_count() > 0, true) and ok
	ok = _check("and an understory", w.plant_count() > w.tree_count(), true) and ok
	var blocked := 0
	for i in mini(50, w.tree_count()):
		if w.blocks(w.trees.x[i], w.trees.y[i], 8.0):
			blocked += 1
	ok = _check("the scatter's trunks block", blocked > 0, true) and ok
	print("OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _check(what: String, got, want) -> bool:
	var good: bool = got == want
	print("  %s %s: %s" % ["ok  " if good else "FAIL", what, str(got)])
	return good
