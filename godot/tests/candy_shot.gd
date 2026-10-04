## MEWD — a picture of CANDY LAND: you at the start (in a town square),
## the candy girls let walk up to you for `tics` tics, then the eye turned
## to `pitch` and to face `turn` (radians on the map; "sun" for the
## candy sun's bearing), and the picture.
## --scare: a body comes apart beside you first, so they run — to see their
## backs. --road: you stand on the middle of a road, looking down it.
## --herd: you stand 14 m off the nearest herd of unicorns, looking at it.
## --house: you stand 16 m out from the nearest house's door, looking at it.
## --edge: you stand at the coast, looking out and down over the lip.
## --blast: a rocket goes off in the nearest wood, 15 to 40 m ahead of you,
## and the picture is taken while the plants it shredded fly in pieces.
## --wound: a candy girl 4 m ahead takes five rounds (not enough to finish her).
## --cliff: the eye out in the air 45 m off the coast, level with the lip
## less 12 m, turned back to look at the island's side.
## (--far: 140 m off)
## --above: the eye 40 m over the start, a town's crossroads, back from it
## 30 m, to see the square, its quadrants and its cliffs.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --resolution 1280x720 \
##   --script res://godot/tests/candy_shot.gd -- --map=candyland out.png [pitch] [tics] [turn] [--scare] [--road]
extends SceneTree

var lofi: Lofi
var game
var out := "candy_shot.png"
var look := 0.0
var wait := 140
var turn = null
var _start := -1
var _scared := false

func _init() -> void:
	var pos := []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		out = pos[0]
	if pos.size() > 1:
		look = float(pos[1])
	if pos.size() > 2:
		wait = int(pos[2])
	if pos.size() > 3:
		turn = pos[3]
	lofi = Lofi.new()
	root.add_child(lofi)
	game = preload("res://godot/scripts/game/game.gd").new()
	lofi.world.add_child(game)
	process_frame.connect(_frame)

func _frame() -> void:
	if game.player == null or not game.island_ready():
		return
	var p = game.player
	var args := OS.get_cmdline_user_args()
	if _start < 0:
		_start = game.tics
		p.health = 100000
		# the island's own colours, as main.gd's prefs give them
		lofi.for_island(game.island_spec, not "--clean" in args)
		if "--house" in args and not game.level.houses.is_empty():
			var best = null
			for h in game.level.houses:
				if best == null or U.dist2(h.x, h.y, p.x, p.y) < U.dist2(best.x, best.y, p.x, p.y):
					best = h
			var at := Vector2(best.x, best.y) + Vector2(cos(best.angle), sin(best.angle)) * 16.0 * 32.0
			p.x = at.x
			p.y = at.y
			p.angle = best.angle + PI
			p.sector = game.level.sector_at(p.x, p.y)
			p.z = game.level.floor_at(p.x, p.y)
		if "--edge" in args:
			# walk out from the start until the ground runs out, then back 12 m
			var dir := Vector2(cos(p.angle), sin(p.angle))
			var at := Vector2(p.x, p.y)
			for k in 4000:
				var q := at + dir * 32.0
				if not game.level.on_land(q.x, q.y, 0.0):
					break
				at = q
			at -= dir * 1.5 * 32.0
			p.x = at.x
			p.y = at.y
			p.sector = game.level.sector_at(p.x, p.y)
			p.z = game.level.floor_at(p.x, p.y)
		if "--blast" in args and game.veg_damage != null:
			var vd = game.veg_damage
			var best := Vector2()
			var most := -1
			for k in 80:
				var a: float = p.angle + randf_range(-1.2, 1.2)
				var q := Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * randf_range(500.0, 1200.0)
				var n: int = vd.near(q.x / 32.0, -q.y / 32.0, 6.0).size()
				if n > most:
					most = n
					best = q
			# 14 m back from it, looking at it, and nobody in the way
			var back := (Vector2(p.x, p.y) - best).normalized() * 14.0 * 32.0
			p.x = best.x + back.x
			p.y = best.y + back.y
			p.sector = game.level.sector_at(p.x, p.y)
			p.z = game.level.floor_at(p.x, p.y)
			p.angle = (best - Vector2(p.x, p.y)).angle()
			set_meta("blast_at", best)
		if "--blast" in args or "--wound" in args:
			for a in game.actors:
				if a.type == "CANDYGIRL":
					a.remove()
		if "--road" in args:
			var r: Array = game._roads_of(game.island.get_node("IslandWorld").field).paths
			if not r.is_empty():
				var a: Vector2 = r[0][0]
				var b: Vector2 = r[0][1]
				var m := a.lerp(b, 0.35)
				p.x = m.x
				p.y = m.y
				p.angle = (b - a).angle()
				p.sector = game.level.sector_at(p.x, p.y)
				p.z = game.level.floor_at(p.x, p.y)
	if "--herd" in args and game.tics - _start >= wait - 2 and not has_meta("herd"):
		set_meta("herd", true)
		var best = null
		for a in game.actors:
			if a.type == "UNICORN" and (best == null or U.dist2(a.x, a.y, p.x, p.y) < U.dist2(best.x, best.y, p.x, p.y)):
				best = a
		if best != null:
			var h: Vector2 = best.home
			var off := Vector2(450.0, 0.0).rotated(randf() * TAU)
			for k in 24:
				var q := h + off.rotated(k * TAU / 24.0)
				if game.level.on_land(q.x, q.y, 32.0):
					p.x = q.x
					p.y = q.y
					break
			p.sector = game.level.sector_at(p.x, p.y)
			p.z = game.level.floor_at(p.x, p.y)
			p.angle = (h - Vector2(p.x, p.y)).angle()
			for a in game.actors:
				if a.type == "CANDYGIRL":
					a.remove()
	# (on or after a tic, never on it exactly: a frame can run several)
	if has_meta("blast_at") and not has_meta("blasted") and game.tics - _start >= 2:
		set_meta("blasted", true)
		var f: Vector2 = get_meta("blast_at")
		game.missiles.detonate(Vector3(f.x, f.y, game.level.floor_at(f.x, f.y) + 8.0))
	if "--wound" in args and not has_meta("victim") and game.tics - _start >= 4:
		var g = game.spawn("CANDYGIRL", p.x + cos(p.angle) * 128.0, p.y + sin(p.angle) * 128.0, p.angle + PI)
		set_meta("victim", g)
	if has_meta("victim") and game.tics - _start >= 8 + 4 * int(get_meta("rounds", 0)) and int(get_meta("rounds", 0)) < 5:
		set_meta("rounds", int(get_meta("rounds", 0)) + 1)
		var g = get_meta("victim")
		if not g.removed:
			g.speed = 0.0
			var eye := Vector3(p.x, p.y, p.z + 41.0)
			var to := Vector3(g.x, g.y, g.z + randf_range(20.0, 50.0))
			var d := to - eye
			game.hitscan(p, atan2(d.y, d.x) + randf_range(-0.03, 0.03), 400.0, 1.0,
				{"shot": true, "pitch": atan2(d.z, Vector2(d.x, d.y).length()), "from": eye})
	if "--scare" in args and not _scared and game.tics - _start >= wait - 70:
		_scared = true
		game.scare(p.x + cos(p.angle) * 60.0, p.y + sin(p.angle) * 60.0, 900.0)
		p.angle += PI
	if "--cliff" in args:
		if not has_meta("cliff"):
			var dir := Vector2(cos(p.angle), sin(p.angle))
			var at := Vector2(p.x, p.y)
			for k in 4000:
				var q := at + dir * 32.0
				if not game.level.on_land(q.x, q.y, 0.0):
					break
				at = q
			set_meta("cliff_z", game.level.floor_at(at.x, at.y) - 12.0 * 32.0)
			set_meta("cliff", at + dir * (140.0 if "--far" in args else 45.0) * 32.0)
			p.angle += PI
		var at: Vector2 = get_meta("cliff")
		p.x = at.x
		p.y = at.y
		p.z = get_meta("cliff_z")
		p.momz = 0.0
	if "--above" in args and game.tics - _start >= wait - 1:
		# (every tic up to the picture, so it does not fall)
		if not has_meta("above"):
			set_meta("above", Vector2(p.x, p.y) - Vector2(cos(p.angle), sin(p.angle)) * 30.0 * 32.0)
		var at: Vector2 = get_meta("above")
		p.x = at.x
		p.y = at.y
		p.z = game.level.floor_at(p.x, p.y) + 40.0 * 32.0
		p.momz = 0.0
	if game.tics - _start >= wait:
		p.pitch = look
		if turn != null:
			if turn == "sun":
				# the island's sun is the SunPivot's +Z, in (x, -z) on the map
				var z: Vector3 = game.island.get_node("SunPivot").global_transform.basis.z
				p.angle = atan2(-z.z, z.x)
			else:
				p.angle = float(turn)
			turn = null
	if game.tics - _start >= wait + 3:
		root.get_texture().get_image().save_png(out)
		var near := 0
		var hello := 0
		for a in game.actors:
			if a.type == "CANDYGIRL" and U.dist2(a.x, a.y, p.x, p.y) < 400.0 * 400.0:
				near += 1
				if a.hello > 0:
					hello += 1
		var running := 0
		for a in game.actors:
			if a.type == "CANDYGIRL" and a.panic > 0:
				running += 1
		print("candy_shot: %s — %d girls within 12 m, %d saying hello, %d running" % [out, near, hello, running])
		quit()
	if game.tics - _start > 6000:
		quit(1)
