## MEWD — JESSE, dumped for comparison with the web build's.
##
## godot --headless --script res://godot/tests/jesse_dump.gd -- <out.json> [seed ...]
## writes, per seed, the vertices, the sector rings with their heights
## and textures, the things, world.pvp and the generator's own summary,
## in the shape tools' node dump of jesseDoc writes — so the two diff —
## and compiles seed 7 through DocCompile to show the level builds.
extends SceneTree

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
		var ss := []
		for s in d.sectors:
			ss.append([s.id, s.verts, s.floor, s.ceil, s.floorTex, s.ceilTex, s.wallTex, s.lowerTex, s.upperTex, s.light, s.outdoor, s.sky, s.name])
		var ts := []
		for t in d.things:
			ts.append([t.id, t.type, t.x, t.y, snappedf(t.angle, 0.000001)])
		var j: Dictionary = d.jesse.duplicate()
		j.tiles = Array(j.tiles)
		out[str(seed)] = {"vertices": vs, "sectors": ss, "things": ts, "pvp": d.world.pvp, "jesse": j}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	var lv := DocCompile.compile(JesseMap.build(7))
	var two := 0
	for l in lv.lines:
		if l.back != -1:
			two += 1
	print("JESSE 7: %d doc sectors -> %d sectors, %d lines (%d two-sided), %d things" %
		[JesseMap.build(7).sectors.size(), lv.sectors.size(), lv.lines.size(), two, lv.things.size()])
	quit()
