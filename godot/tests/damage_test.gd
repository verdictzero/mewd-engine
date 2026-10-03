## MEWD — WHAT ROUNDS AND BLASTS DO TO SPRITES, headless (at the user's
## request): a round takes a bite out of a candy girl — a hole in her
## picture, a piece of it flying, blood, more blood after — and enough of
## them blow her apart; a street lamp shot to pieces; a rocket's blast
## blowing the plants near it to pieces and setting the ones round it
## alight, the fire spreading to a point and going out; a round into a
## tree shooting it through.
##   godot --headless --script res://godot/tests/damage_test.gd -- --map=candyland
## (needs the island baked)
extends SceneTree

var game
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _tics(n: int) -> void:
	for i in n:
		game.tic()

## a round from `from` straight at (x, y, z)
func _shoot_at(from: Vector3, to: Vector3):
	var p = game.player
	var d := to - from
	var ang := atan2(d.y, d.x)
	var pitch := atan2(d.z, Vector2(d.x, d.y).length())
	return game.hitscan(p, ang, d.length() + 64.0, 30.0, {"shot": true, "pitch": pitch, "from": from})

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	# (the island's plants come in over the first frames)
	while game.player == null or not game.island_ready():
		await process_frame
	for k in 5:
		await process_frame
	var p = game.player
	p.health = 100000
	var lv: IslandLevel = game.level
	# (the plants left out of the rounds at people and lamps: a bush on the
	# line would take the round)
	var vd_kept = game.veg_damage
	game.veg_damage = null
	# --- A ROUND TAKES A BITE ---------------------------------------------
	var g: Actor = game.spawn("CANDYGIRL", p.x + 200.0, p.y, PI)
	g.sector = lv.sector_at(g.x, g.y)
	g.z = lv.floor_at(g.x, g.y)
	var eye := Vector3(p.x, p.y, lv.floor_at(p.x, p.y) + 41.0)
	# (out of the way of anybody else: the girl alone on the line)
	for a in game.actors:
		if a != g and a.monster and Vector2(a.x - p.x, a.y - p.y).length() < 400.0:
			a.remove()
	var chunks0: int = game.chunks.count()
	var hit = _shoot_at(eye, Vector3(g.x, g.y, g.z + 40.0))
	game.standees.draw(game.actors, game.camera.position, game.tics + 1)
	check(hit == g and g.holes.size() == 1 and not g.dead, "a round takes a bite out of her, and she lives (%d hole)" % g.holes.size())
	check(game.chunks.count() > chunks0, "a piece of her picture flies off")
	check(game.bleeders.has(g), "and she bleeds")
	var gore0: int = game.fx.live_count()
	_tics(6)
	check(game.fx.live_count() >= gore0, "copiously (%d particles)" % game.fx.live_count())
	var st: Standees = game.standees
	var sl = st.slots.get(g.id)
	var hp: Color = st.strips["CANDY"].holes.get_pixel(0, sl[1]) if sl != null else Color()
	check(sl != null and hp.b > 0.0, "the hole is in the picture the crowd is drawn from (r %.1f)" % hp.b)
	var n := 1
	while not (g.dead or g.removed) and n < 20:
		_shoot_at(eye, Vector3(g.x, g.y, g.z + randf_range(15.0, 55.0)))
		n += 1
		_tics(1)
	check((g.dead or g.removed) and n == 10, "and %d rounds blow her apart" % n)
	# --- A LAMP SHOT TO PIECES --------------------------------------------
	var lamp: Actor = null
	for a in game.actors:
		if a.type == "LAMP" and not a.removed:
			lamp = a
			break
	var c1: int = game.chunks.count()
	var m := 0
	var at := Vector3(lamp.x - 160.0, lamp.y, lv.floor_at(lamp.x, lamp.y) + 60.0)
	while not lamp.removed and m < 20:
		game.hitscan(p, 0.0, 400.0, 30.0, {"shot": true, "from": at})
		m += 1
	check(lamp.removed and m == 8, "a street lamp shot eight times goes to pieces (%d)" % m)
	check(game.chunks.count() > c1 + 8, "pieces of itself (%d)" % (game.chunks.count() - c1))
	# --- A BLAST IN THE TREES ---------------------------------------------
	game.veg_damage = vd_kept
	var vd: VegDamage = game.veg_damage
	check(vd != null, "the island's plants can be hurt")
	# the thickest stand of plants within reach of the middle
	var best := Vector2()
	var most := 0
	for k in 60:
		var q := Vector2(randf_range(-600, 600), randf_range(-600, 600))
		var here := vd.near(q.x, q.y, 6.0).size()
		if here > most:
			most = here
			best = q
	var gp := Vector3(best.x * 32.0, -best.y * 32.0, lv.floor_at(best.x * 32.0, -best.y * 32.0) + 8.0)
	var before := vd.near(best.x, best.y, 2.5).size()
	game.missiles.detonate(gp)
	var after := vd.near(best.x, best.y, 2.5).size()
	check(before > 0 and after < before, "a rocket in a wood blows the plants by it to pieces (%d of %d left)" % [after, before])
	_tics(2)
	var lit0: int = vd.burning.size()
	check(lit0 > 0, "and sets the ones round it alight (%d)" % lit0)
	var most_lit := lit0
	var t := 0
	while t < 35 * 150 and not vd.burning.is_empty():
		_tics(35)
		t += 35
		most_lit = maxi(most_lit, vd.burning.size())
	check(most_lit > lit0, "the fire spreads (%d alight at most)" % most_lit)
	check(vd.burning.is_empty(), "and burns itself out (in %d s)" % (t / 35))
	var burnt := 0
	for k in vd.changed:
		var c: Array = vd.changed[k]
		if (c[3] as Vector4).z > 0.0:
			burnt += 1
	check(burnt <= VegDamage.BUDGET and burnt > lit0, "to a point (%d plants burnt, at most %d)" % [burnt, VegDamage.BUDGET])
	# --- A ROUND INTO A TREE ----------------------------------------------
	var tree := {}
	for q in vd.near(0.0, 0.0, 600.0):
		if q.cls == 0 and q.custom.z <= 0.0 and q.h > 6.0:
			tree = q
			break
	check(not tree.is_empty(), "a standing tree to shoot")
	if tree.is_empty():
		print("damage: %d FAILED" % fails)
		quit(1)
		return
	var tg := VegDamage.to_game(tree.pos)
	var from := Vector3(tg.x - 300.0, tg.y, tg.z + tree.h * 32.0 * 0.4)
	var to := Vector3(tg.x, tg.y, tg.z + tree.h * 32.0 * 0.4)
	var r: Dictionary = vd.ray(from, to + (to - from) * 0.2, 1.0)
	check(not r.is_empty() and r.plant.key == tree.key, "a round's line finds the tree in its way")
	var shots := 0
	var gone := false
	while shots < 30 and not gone:
		_shoot_at(from, to)
		shots += 1
		var now := vd.near(tree.pos.x, tree.pos.z, 0.2)
		gone = now.filter(func(q): return q.key == tree.key).is_empty()
		if shots == 1 and not gone:
			var q1: Dictionary = now.filter(func(q): return q.key == tree.key)[0]
			check(q1.custom.y > 0.0, "a round shoots it through a little (%.2f)" % q1.custom.y)
	check(gone and shots >= 5, "and enough of them (%d) blow it to pieces" % shots)
	print("damage: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
