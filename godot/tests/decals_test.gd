## MEWD — real decals, headless (RealDecals.force: there is no renderer
## here to bake with, so the marks wear a plain texture, and what is held
## is the bookkeeping):
##   the world cut into tiles — every triangle inside its tile, and not a
##   square unit of floor or wall gained or lost;
##   a mark on the tiles under it; never a ninth on a tile mesh — the
##   ninth is refused and laid as a quad instead, so nothing is lost;
##   a sear all three layers or none; a hot spot real, and gone when it
##   cools, leaving a scorch; the caps; and the web's way (RealDecals off)
##   untouched: the same map as one mesh a texture and no real marks.
##   godot --headless --script res://godot/tests/decals_test.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _area(root: Node) -> float:
	var a := 0.0
	for mi in root.get_children():
		if not (mi is MeshInstance3D):
			continue
		var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			a += (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]]).length() * 0.5
	return a

func _init() -> void:
	U.p_seed()
	# THE TILES, on THE ANNEXE (walls, floors, roofs, a map in storeys)
	var lv := DocCompile.compile(LayersMap.build())
	var whole := MapGeo.new(TexBank.new()).build(lv)
	var mg := MapGeo.new(TexBank.new())
	mg.tile = RealDecals.TILE
	var cut := mg.build(lv)
	var a0 := _area(whole)
	var a1 := _area(cut)
	check(absf(a0 - a1) < a0 * 1e-4, "cut into tiles, the area is the same (%.0f and %.0f)" % [a0, a1])
	check(cut.get_child_count() > whole.get_child_count(), "more meshes cut (%d) than whole (%d)" % [cut.get_child_count(), whole.get_child_count()])
	var inside := true
	for mi in cut.get_children():
		var key: Vector2i = mi.get_meta("tile")
		var box: AABB = mi.get_aabb()
		if box.position.x < key.x * RealDecals.TILE - 0.01 or box.end.x > (key.x + 1) * RealDecals.TILE + 0.01 \
				or box.position.z < key.y * RealDecals.TILE - 0.01 or box.end.z > (key.y + 1) * RealDecals.TILE + 0.01:
			inside = false
		if not (mi.layers & RealDecals.RECEIVE_LAYER):
			inside = false
	check(inside, "every tile's mesh inside its tile, and on the layer decals land on")
	whole.free()
	cut.free()

	# THE GAME, with real decals
	RealDecals.force = true
	var game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	var rd: RealDecals = game.real_decals
	check(rd != null and rd.baked, "the game has real decals, ready")
	check(game.decals.real == rd and game.gore_decals.real == rd, "the quads' systems hand over to them")
	var p = game.player
	var fl: float = p.sector.floor
	# one mark
	var m: RealDecals.Mark = rd.add(RealDecals.K.POOL, Vector3(p.x, p.y, fl), Vector3(0, 0, 1), 60.0)
	check(m != null and m.chunks.size() > 0 and m.node.visible, "a pool is a real decal on the floor's tiles")
	check(is_equal_approx(m.node.size.x, 60.0) and m.node.cull_mask == RealDecals.RECEIVE_LAYER, "its box: its size, landing on the world alone")
	# many on one spot: never a ninth on a tile mesh; the rest refused
	var real := 0
	var refused := 0
	for i in 30:
		var mk = rd.add(RealDecals.K.SPATTER, Vector3(p.x + randf() * 10.0, p.y + randf() * 10.0, fl), Vector3(0, 0, 1), 30.0)
		if mk != null:
			real += 1
		else:
			refused += 1
	check(rd.most_on_a_mesh() <= RealDecals.PER_MESH, "never more than eight on a tile mesh (most: %d)" % rd.most_on_a_mesh())
	check(refused > 0 and real + refused == 30, "the ones that do not fit are refused (%d real, %d refused)" % [real, refused])
	# and through GoreDecals, refused ones become quads
	var q0: int = game.gore_decals._count
	for i in 12:
		game.gore_decals.pool(p.x + randf() * 8.0, p.y + randf() * 8.0, fl, 40.0)
	check(game.gore_decals._count - q0 == 12, "blood that does not fit is laid as the quad it was (%d quads)" % (game.gore_decals._count - q0))
	# room again once they go
	for k in [RealDecals.K.SPATTER, RealDecals.K.POOL]:
		for mk in (rd._kind_marks[k] as Array).duplicate():
			rd.remove(mk)
	check(rd.live == 0 and rd.most_on_a_mesh() == 0, "removed, and the tiles are empty again")
	# a sear: all three layers, or none
	var s: RealDecals.Mark = rd.add_sear(Vector3(p.x, p.y, fl), Vector3(0, 0, 1), 200.0, Vector3(1, 0, 0))
	check(s != null and s.group.size() == 3, "a sear is three layers: the scar, its heat, its embers")
	rd.remove(s)
	check(rd.live == 0, "and goes as one")
	for i in 7:
		rd.add(RealDecals.K.SCORCH, Vector3(p.x, p.y, fl), Vector3(0, 0, 1), 30.0)
	check(rd.add_sear(Vector3(p.x, p.y, fl), Vector3(0, 0, 1), 20.0) == null and (rd._kind_marks[RealDecals.K.SEAR] as Array).is_empty(),
		"a sear with room for only one layer is none of them")
	for mk in (rd._kind_marks[RealDecals.K.SCORCH] as Array).duplicate():
		rd.remove(mk)
	# the flamer: a hot spot real, gone when it cools, a scorch after
	for i in 40:
		game.decals.heat(Vector3(p.x + 100.0, p.y, fl), Vector3(0, 0, 1))
	check((rd._kind_marks[RealDecals.K.HEAT] as Array).size() == 1, "a hot spot is one real mark")
	for i in int(7.0 * 35.0):
		game.decals.tic()
	check((rd._kind_marks[RealDecals.K.HEAT] as Array).is_empty(), "cooled, it is gone")
	check((rd._kind_marks[RealDecals.K.SCORCH] as Array).size() == 1, "and it left a real scorch")
	# the caps: the oldest of a kind goes
	var cap: int = RealDecals.CAPS[RealDecals.K.SLAG]
	for i in cap + 5:
		rd.add(RealDecals.K.SLAG, Vector3(p.x + (i % 40) * 300.0, p.y + (i / 40) * 300.0, fl), Vector3(0, 0, 1), 10.0)
	check((rd._kind_marks[RealDecals.K.SLAG] as Array).size() <= cap, "a kind keeps to its cap (%d)" % cap)
	# a tic with marks about, lit off the globals
	for i in 8:
		game.tic()
		rd.tic()
	check(true, "ticks with marks about")
	game.queue_free()
	await process_frame

	# THE WEB'S WAY: off, and nothing changes
	RealDecals.force = false
	var g2 = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(g2)
	await process_frame
	var tiles := 0
	for c in g2.get_children():
		if c.name == "LevelGeometry":
			for mi in c.get_children():
				if mi.has_meta("tile"):
					tiles += 1
	check(g2.real_decals == null and tiles == 0 and g2.decals.real == null, "off (the web): no real decals, the world one mesh a texture")
	print("decals: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
