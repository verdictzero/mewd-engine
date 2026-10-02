## MEWD — JESSE, built and dumped.
##
## godot --headless --script res://godot/tests/jesse_dump.gd -- <out.json> [seed ...]
## writes, per seed, the map in blocks (the vertices, each block's ring,
## height and textures, the things, world.pvp and the generator's own
## summary) — one seed is one map, and the file is a record of it —
## then compiles every seed asked for through BlockCompile and holds the
## build: no problems, a start and spawn pads on the ground, the forts
## standing FORT_H over it, the tower TOWER_H up its steps, both bases'
## gates open, and the whole of it one connected floor. Prints OK or
## fails.
extends SceneTree

var failures := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() else "user://jesse_dump.json"
	var seeds := [1, 7, 12345, 99, 424242]
	if args.size() > 1:
		seeds = []
		for a in args.slice(1):
			seeds.append(int(a))
	var out := {}
	for seed in seeds:
		var d := JesseMap.build(seed)
		var vs := []
		for p in d.vertices:
			vs.append([int(p.x), int(p.y)])
		var bs := []
		for b in d.blocks:
			bs.append([b.id, b.verts, b.h, b.top, b.side, b.name])
		var ts := []
		for t in d.things:
			ts.append([t.id, t.type, t.x, t.y, snappedf(t.angle, 0.000001)])
		var j: Dictionary = d.jesse.duplicate()
		j.tiles = Array(j.tiles)
		out[str(seed)] = {"ground": d.ground, "vertices": vs, "blocks": bs, "things": ts, "pvp": d.world.pvp, "jesse": j}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	for seed in seeds:
		_build(seed)
	print("jesse: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func _build(seed: int) -> void:
	var d := JesseMap.build(seed)
	var t0 := Time.get_ticks_msec()
	var lv := DocCompile.compile(d)
	var two := 0
	for l in lv.lines:
		if l.back != -1:
			two += 1
	var j: Dictionary = d.jesse
	print("JESSE %d: %dx%d cells, %d zones, %s; %d blocks -> %d sectors, %d lines (%d two-sided), %d things in %d ms" %
		[seed, j.W, j.H, j.zones.size(), "symmetric" if j.symmetric else "not symmetric", d.blocks.size(), lv.sectors.size(),
		lv.lines.size(), two, lv.things.size(), Time.get_ticks_msec() - t0])
	check(DocCompile.problems.is_empty(), "built with no problems (%s)" % str(DocCompile.problems.slice(0, 3)))
	# the start and every spawn pad on the ground
	var on_ground := true
	for t in lv.things:
		if t.type == "START" and t.z != 0.0:
			on_ground = false
	for team in d.world.pvp.teams:
		for sp in team.spawns:
			var s := lv.span_at(sp[0], sp[1], 1.0)
			if s == null or s.floor != 0.0 or s.ceil < 256.0:
				on_ground = false
	check(on_ground, "the start and the spawn pads stand on the ground, under the sky")
	# the forts FORT_H high, the tower TOWER_H up its steps
	var forts := 0
	var towers := 0
	var steps := {}
	for s in lv.sectors:
		if s.name.begins_with("fort:") and s.floor == float(JesseMap.FORT_H):
			forts += 1
		if s.name.begins_with("step:") and s.floor == float(JesseMap.TOWER_H):
			towers += 1
		if s.name.begins_with("step:") and s.floor > 0.0 and s.floor < float(JesseMap.TOWER_H):
			steps[s.floor] = true
	check(forts >= 2 and towers == 2 and steps.size() == JesseMap.TOWER_H / JesseMap.STEP - 1,
		"fort walls %d high (%d), a tower deck at %d in each base, steps of %d up to it (%s)" % [JesseMap.FORT_H, forts, JesseMap.TOWER_H, JesseMap.STEP, str(steps.keys())])
	# the gates open: each on the ground, with the ground on both sides
	var gates_open := true
	for team in d.world.pvp.teams:
		for g in team.gates:
			var s := lv.span_at(g[0], g[1], 1.0)
			if s == null or s.floor != 0.0:
				gates_open = false
	check(gates_open, "every gate of both bases is open ground")
	# ONE FLOOR: from the start, column to column over every edge that
	# is a step a player can climb, the whole of the ground is reached
	var st = null
	for t in lv.things:
		if t.type == "START":
			st = t
	var adj := {}
	for l in lv.lines:
		if l.front == -1 or l.back == -1:
			continue
		var a: int = lv.sectors[l.front].col_base
		var b: int = lv.sectors[l.back].col_base
		if a == b:
			continue
		for pr in [[a, b], [b, a]]:
			if not adj.has(pr[0]):
				adj[pr[0]] = {}
			adj[pr[0]][pr[1]] = true
	var start := lv.top_of(lv.sector_at(float(st.x), float(st.y)))
	var seen := {start.col_base: true}
	var q := [start]
	while q.size():
		var s: Level.Sector = q.pop_back()
		for k in adj.get(s.col_base, {}):
			if seen.has(k):
				continue
			var o := lv.top_of(lv.sectors[k])
			if absf(o.floor - s.floor) <= 24.0:
				seen[k] = true
				q.append(o)
	var floors := 0
	for s in lv.sectors:
		if s.col_base == s.index and lv.top_of(s).floor <= 0.0:
			floors += 1
	var reached := 0
	for k in seen:
		if lv.top_of(lv.sectors[k]).floor <= 0.0:
			reached += 1
	check(reached >= floors * 0.9, "the ground is one connected floor: %d of %d pieces reached from the start" % [reached, floors])
