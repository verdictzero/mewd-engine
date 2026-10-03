## MEWD — a picture of CANDY LAND: you at the start (in a town square),
## the candy girls let walk up to you for `tics` tics, then the eye turned
## to `pitch` and to face `turn` (radians on the map; "sun" for the
## candy sun's bearing), and the picture.
## --scare: a body comes apart beside you first, so they run — to see their
## backs. --road: you stand on the middle of a road, looking down it.
## --herd: you stand 14 m off the nearest herd of unicorns, looking at it.
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
		lofi.for_island(game.island_spec, true)
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
	if "--scare" in args and not _scared and game.tics - _start >= wait - 70:
		_scared = true
		game.scare(p.x + cos(p.angle) * 60.0, p.y + sin(p.angle) * 60.0, 900.0)
		p.angle += PI
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
