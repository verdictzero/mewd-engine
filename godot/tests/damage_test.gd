## MEWD — WHAT ROUNDS AND BLASTS DO TO SPRITES, headless (at the user's
## request): a round into a candy girl throws a piece of her picture and
## blood, more blood after, and leaves no hole in her; enough of them blow
## her apart; a street lamp shot to pieces; a rocket's blast shredding the
## plants near it into pieces of themselves (a big plant into more of them)
## and setting nothing alight; the grass under it mown, and a round into
## the ground taking the tufts it lands among; rounds into a tree
## shredding it.
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
	check(hit == g and g.bites == 1 and not g.dead, "a round goes into her, and she lives")
	check(game.chunks.count() > chunks0, "a piece of her picture flies off")
	check(game.bleeders.has(g), "and she bleeds")
	check(g.shake > 0 and g.jolt(game.tics) != Vector3.ZERO, "and the round jolts her (%d tics)" % g.shake)
	var still := 0
	while g.shake > 0 and still < 20:
		_tics(1)
		still += 1
	check(g.shake == 0 and still <= Actor.SHAKE_HIT and g.jolt(game.tics) == Vector3.ZERO, "and she stands still again after (%d tics)" % still)
	var gore0: int = game.fx.live_count()
	_tics(6)
	check(game.fx.live_count() >= gore0, "copiously (%d particles)" % game.fx.live_count())
	check(not (game.standees.strips["CANDY"] as Object).get("holes"), "and leaves no hole in her picture")
	var n := 1
	while not (g.dead or g.removed) and n < 20:
		_shoot_at(eye, Vector3(g.x, g.y, g.z + randf_range(15.0, 55.0)))
		n += 1
		_tics(1)
	check((g.dead or g.removed) and n == 10, "and %d rounds blow her apart" % n)
	# --- A BORE IN A HEAD -------------------------------------------------
	var g2: Actor = null
	for a in game.actors:
		if a.type == g.type and a != g and not (a.dead or a.removed):
			g2 = a
			break
	if g2 != null:
		var drill := g2.bore(p) == "drill"
		var shaking := 0
		var big := 0.0
		for k in 30:
			var j := g2.jolt(game.tics)
			if j != Vector3.ZERO:
				shaking += 1
			if k > 20:
				big = maxf(big, Vector2(j.x, j.y).length())
			_tics(1)
		check(drill and shaking == 30, "a bore drilling into a head shakes her every tic (%d of 30)" % shaking)
		check(big > Actor.SHAKE_AMP * 0.3, "and hard (%.1f units)" % big)
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
	var c0: int = game.chunks.count()
	var grass = game.veg_damage.grass
	var mown0: int = grass._mown.size() if grass != null else 0
	game.missiles.detonate(gp)
	var after := vd.near(best.x, best.y, 2.5).size()
	check(before > 0 and after < before, "a rocket in a wood blows the plants by it to pieces (%d of %d left)" % [after, before])
	check(game.chunks.count() > c0 + before * 6, "pieces of themselves (%d)" % (game.chunks.count() - c0))
	var reach := MissileSystem.WARHEAD.radius / IslandLevel.U_PER_M
	var shaken := 0
	for q in vd.near(best.x, best.y, reach * VegDamage.SHAKE_SHARE):
		if q.custom.w > 0.0 and absf(q.custom.z - game.clock) < 0.01:
			shaken += 1
	check(shaken > 0, "and the plants further out shaken and hurt, still standing (%d)" % shaken)
	if grass != null:
		var mc: Vector3 = grass._mown[grass._mown.size() - 1] if grass._mown.size() > mown0 else Vector3()
		check(grass._mown.size() == mown0 + 1 and mc.z > 2.0, "and the grass under it mown (a patch %.1f m round)" % mc.z)
	check(not "burning" in vd, "and nothing set alight")
	check(VegDamage.pieces_for(5.0, 9.0) > 3 * VegDamage.pieces_for(1.5, 1.5), "a big plant goes to more pieces than a small one (%d, %d)" % [VegDamage.pieces_for(5.0, 9.0), VegDamage.pieces_for(1.5, 1.5)])
	# --- A ROUND INTO THE GRASS -------------------------------------------
	if grass != null:
		# (rounds steeply down into the ground round you, the plants left out)
		var keep_veg = vd.veg
		vd.veg = null
		var m0: int = grass._mown.size()
		for k in 40:
			var q := Vector2(p.x, p.y) + Vector2(randf_range(-600, 600), randf_range(-600, 600))
			var gz: float = lv.floor_at(q.x, q.y)
			_shoot_at(Vector3(q.x - 40.0, q.y, gz + 300.0), Vector3(q.x, q.y, gz))
		vd.veg = keep_veg
		check(grass._mown.size() >= m0 + 30, "a round into the ground takes the tufts it lands among (%d of 40 rounds in)" % (grass._mown.size() - m0))
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
			check(q1.custom.w > 0.0 and absf(q1.custom.z - game.clock) < 0.01, "and shakes it (%.2f m)" % q1.custom.w)
	check(gone and shots >= 5, "and enough of them (%d) blow it to pieces" % shots)
	check(VegDamage.hits_for(5.0, 9.0) > 2 * VegDamage.hits_for(1.0, 1.0) and VegDamage.hits_for(1.0, 1.0) >= 3,
		"a big plant takes more rounds than a small one (%d, %d)" % [VegDamage.hits_for(5.0, 9.0), VegDamage.hits_for(1.0, 1.0)])
	print("damage: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
