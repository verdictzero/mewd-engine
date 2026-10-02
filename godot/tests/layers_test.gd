## MEWD — ROOM OVER ROOM, headless: THE ANNEXE (godot/scripts/maps/
## layers.gd), a building put up in BLOCKS in three layers
## (BlockCompile), compiled whole and played.
##
##   godot --headless --script res://godot/tests/layers_test.gd -- --map=layers
##
## Builds the real Game on it and holds: the compile (a column of two
## storeys wherever the upstairs is over the ground, the office's walls
## only upstairs, its door and the shop's each on their own storey), the
## player walking up the step generator's stairs onto the terrace, round
## it, into the office, bumping the walls up there, off the edge and
## down, and about under the deck with his head under it; a round from
## under the terrace stopping in its deck while the shopper standing on
## it lives, one fired over the edge from the yard hitting them, one
## fired down from the terrace stopping on it; sight blocked by the
## slab; the crowd on each storey staying on it; and over a
## loopback network, the host's snapshot carrying the height and the
## client putting the bodies on the right storey. Prints OK or fails.
extends SceneTree

var game
var failures := 0

class Pilot:
	var c := {"fwd": 0.0, "side": 0.0, "run": false, "jump": false, "look": Vector2(), "attack": false,
		"slot": 0, "cycle": 0, "use": false}
	func cmd(_g) -> Dictionary:
		var out := c.duplicate()
		c.jump = false
		return out

class StubGame:
	var level: Level
	var actors: Array = []
	var player = null
	var fire = null
	var tics := 0
	var blockmap := ActorGrid.new()
	func play_sound(_n, _a) -> void:
		pass
	func scare(_x, _y, _r) -> void:
		pass
	func gib(a) -> void:
		a.remove()
	func on_monster_killed(_a, _s) -> void:
		pass

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

func _init() -> void:
	U.p_seed()
	_compile()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var lv: Level = game.level
	check(lv.layered and game.player != null, "THE ANNEXE is a map in storeys, and playing")
	_walk(lv)
	_under(lv)
	_shots(lv)
	_sight(lv)
	_doors(lv)
	_troops(lv)
	_crowd(lv)
	await _net()
	print("layers: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

static func _named(lv: Level, name: String, storey := -1) -> Array:
	var out := []
	for s in lv.sectors:
		if s.name == name and (storey < 0 or s.storey == storey):
			out.append(s)
	return out

# ---- the compile ------------------------------------------------------------

func _compile() -> void:
	print("layers: the compile")
	var t0 := Time.get_ticks_msec()
	var lv := DocCompile.compile(LayersMap.build())
	print("   %d sectors, %d lines in %d ms" % [lv.sectors.size(), lv.lines.size(), Time.get_ticks_msec() - t0])
	check(DocCompile.problems.is_empty(), "built with no problems (%s)" % str(DocCompile.problems))
	var cols := 0
	for s in lv.sectors:
		if s.above != -1:
			cols += 1
			check(lv.sectors[s.above].below == s.index and lv.sectors[s.above].col_base == s.col_base, "a column's storeys know each other")
	check(cols >= 2, "columns of storeys: shop and office, yard and terrace, and the walls round them (%d)" % cols)
	var office: Level.Sector = lv.span_at(960, 768, 129)
	var shop: Level.Sector = lv.span_at(960, 768, 1)
	var terrace: Level.Sector = lv.span_at(1344, 640, 129)
	check(office.name == "office floor" and shop.name == "shop" and terrace.name == "terrace", "each storey named for the block it stands on (%s, %s, %s)" % [office.name, shop.name, terrace.name])
	check(office.below == shop.index and shop.ceil == 112.0 and office.floor == 128.0 and office.ceil == 320.0,
		"the office stands on the shop, on the slab 112..128, under the roof at 320 (%s..%s over %s..%s)" % [office.floor, office.ceil, shop.floor, shop.ceil])
	check(shop.ceil_tex == "OFCCEIL1" and absf(shop.light - 0.7) < 0.01 and office.ceil_tex == "OFCCEIL1",
		"the slab's underside is the shop's ceiling, and its light the shop's (%s, %.2f)" % [shop.ceil_tex, shop.light])
	var under: Level.Sector = lv.sectors[terrace.below]
	check(under.name == "ground" and under.ceil == 112.0 and under.ceil_tex == "CONC_3" and terrace.floor == 128.0,
		"the yard runs on under the terrace, the underside of its slab its ceiling (%s), its top at %s" % [under.ceil_tex, terrace.floor])
	check(lv.edge_conflicts == 0, "no edge claimed by three columns")
	# THE BUILDING'S FACES: each block's own side, band by band
	var north := _line_at(lv, Vector2(960, 496))
	var faces := north.bands.filter(func(bd): return bd.tex != "NONE").map(func(bd): return [bd.z0, bd.z1, bd.tex]) if north else []
	check(faces == [[0.0, 112.0, "CITYMET1"], [112.0, 128.0, "CITYMET1"], [128.0, 320.0, "CITYMET2"], [320.0, 336.0, "CITYMET2"]],
		"the building's north face: the shop's wall, the slab's edge, the office's wall and the roof's edge, each in its own sides (%s)" % str(faces))
	var inner := _line_at(lv, Vector2(960, 512))
	var inner_faces := inner.bands.filter(func(bd): return bd.tex != "NONE").map(func(bd): return [bd.z0, bd.z1, bd.tex]) if inner else []
	check(inner_faces == [[0.0, 112.0, "CITYMET1"], [128.0, 320.0, "CITYMET2"]], "and inside, the rooms' own side of it (%s)" % str(inner_faces))
	var terr_edge := _line_at(lv, Vector2(1344, 496))
	check(terr_edge != null and not terr_edge.blocking and terr_edge.holes.size() == 2, "and the terrace's edge is open, over open yard")
	var slab := terr_edge.bands.filter(func(bd): return absf(bd.z0 - 112.0) < 0.01 and absf(bd.z1 - 128.0) < 0.01) if terr_edge else []
	check(slab.size() == 1 and slab[0].tex == "CITYCON1", "and the edge of its slab, 16 thick, a band over the yard in the slab's sides (%s)" % str(terr_edge.bands.map(func(bd): return [bd.z0, bd.z1]) if terr_edge else null))
	# THE LINTELS: the passage under each, and the wall solid over it
	var west = lv.sector_at(760, 768)
	check(west != null and west.ceil == 96.0 and west.ceil_tex == "CITYMET1" and west.floor == 0.0, "the shop's doorway: the yard runs under the lintel to 96 (%s..%s)" % [west.floor, west.ceil])
	var steps := 0
	for s in lv.sectors:
		if s.floor > 0.0 and s.floor < 128.0 and s.ceil > s.floor:
			steps += 1
	check(steps == 7, "seven steps, sixteen high, a block each (%d)" % steps)
	check(lv.sector_at(-30000, 40000) != null and lv.sector_at(-30000, 40000).floor == 0.0, "and the ground goes on far past the building")
	# the maze is a map in blocks too: hedges on the ground
	var maze := DocCompile.compile(MazeMap.build(7))
	var hedges := 0
	for s in maze.sectors:
		if s.name == "hedge" and s.floor == float(MazeMap.HEDGE_H):
			hedges += 1
	check(maze.sector_at(192, 192) != null and maze.sector_at(192, 192).floor == 0.0 and hedges > 50 and DocCompile.problems.is_empty(),
		"the maze is hedge blocks on the ground (%d hedges, start on the ground)" % hedges)

func _line_at(lv: Level, p: Vector2) -> Level.Line:
	for l in lv.lines:
		if DocCompile.seg_dist(Vector2(l.x1, l.y1), Vector2(l.x2, l.y2), p) < 0.5:
			return l
	return null

# ---- walking ------------------------------------------------------------------

func _put(p, x: float, y: float, z: float, ang: float) -> void:
	p.x = x
	p.y = y
	p.z = z
	p.momx = 0.0
	p.momy = 0.0
	p.momz = 0.0
	p.on_ground = true
	p.angle = ang
	p.sector = game.level.span_at(x, y, z + 1.0)
	p.view_z = z + U.PLAYER_EYE

func _drive(fwd: float, tics: int, stop := Callable()) -> Dictionary:
	var p = game.player
	var pilot: Pilot = p.session
	pilot.c.fwd = fwd
	var lo := INF
	var hi := -INF
	var head := -INF
	for i in tics:
		p.tic(pilot.cmd(game))
		if game.doors != null:
			game.doors.tic()
		lo = minf(lo, p.z)
		hi = maxf(hi, p.z)
		head = maxf(head, p.z + p.height)
		if stop.is_valid() and stop.call():
			break
	pilot.c.fwd = 0.0
	return {"lo": lo, "hi": hi, "head": head}

func _walk(lv: Level) -> void:
	print("layers: walking")
	var p = game.player
	p.session = Pilot.new()
	# 1. UP THE STAIRS, from the yard south of them, facing the terrace
	_put(p, 1344, 1460, 0, -PI / 2)
	var zs := []
	var pilot: Pilot = p.session
	pilot.c.fwd = 1.0
	for i in 160:
		p.tic(pilot.cmd(game))
		if zs.is_empty() or zs[zs.size() - 1] != p.z:
			zs.append(p.z)
		if p.y < 900.0:
			break
	pilot.c.fwd = 0.0
	check(p.y < 900.0 and p.z == 128.0 and p.sector.name == "terrace" and p.on_ground,
		"up the stairs and onto the terrace: z %.0f in %s at y %.0f" % [p.z, p.sector.name, p.y])
	check(zs.size() >= 8 and zs.slice(1) == [16.0, 32.0, 48.0, 64.0, 80.0, 96.0, 112.0, 128.0].slice(8 - (zs.size() - 1)),
		"a step at a time: %s" % str(zs))
	# 2. ROUND THE TERRACE, into the office's wall
	_put(p, 1344, 930, 128, PI)
	var w := _drive(1.0, 90)
	check(p.x > 1168.0 + 15.0 and p.x < 1191.0 and w.lo == 128.0, "upstairs, the office's wall, 16 thick, stops you (x %.1f, z %.0f)" % [p.x, w.lo])
	# 3. THROUGH ITS DOOR, and across it to the far wall — over the shop's
	# door downstairs, which is no door up here
	_put(p, 1344, 768, 128, PI)
	w = _drive(1.0, 200)
	check(p.sector.name == "office floor" and w.lo == 128.0 and p.x > 768.0 + 15.0 and p.x < 800.0,
		"through the office's door, and its west wall (over the shop's door) stops you: x %.1f z %.0f in %s" % [p.x, p.z, p.sector.name])
	# 4. OFF THE EDGE: the terrace's north side, over open yard
	_put(p, 1400, 560, 128, -PI / 2)
	w = _drive(1.0, 60, func(): return p.y < 470.0 and p.on_ground)
	_drive(0.0, 30)
	check(p.z == 0.0 and p.on_ground and p.sector.name == "ground" and p.sector.ceil > 1000.0,
		"off the edge, a fall, and on the yard (z %.0f, lowest %.0f)" % [p.z, w.lo])

func _under(lv: Level) -> void:
	print("layers: under the deck")
	var p = game.player
	# 5. UNDER THE TERRACE: the yard with the deck for a ceiling
	_put(p, 1344, 900, 0, -PI / 2)
	check(p.sector.name == "ground" and p.sector.ceil == 112.0 and p.sector.above != -1, "under the terrace, in the yard, the deck overhead")
	var w := _drive(1.0, 30)
	check(w.hi == 0.0 and p.y < 900.0, "walking about under it, on the ground (z %.0f..%.0f)" % [w.lo, w.hi])
	var pilot: Pilot = p.session
	pilot.c.jump = true
	w = _drive(0.0, 40)
	check(w.hi > 0.0 and w.head <= 112.0 + 0.01 and p.z == 0.0, "a jump, and the deck's underside stops the head (head at %.1f)" % w.head)
	# 6. COLLISION DOWNSTAIRS: the shop's east wall, under the office's door
	_put(p, 1344, 768, 0, PI)
	w = _drive(1.0, 90)
	check(p.x > 1168.0 + 15.0 and p.x < 1191.0 and w.hi == 0.0, "downstairs, the shop's wall under the office's door stops you (x %.1f)" % p.x)
	# 7. and in at the shop's own door, from the west, to its east wall
	_put(p, 600, 768, 0, 0.0)
	w = _drive(1.0, 200)
	check(p.sector.name == "shop" and p.x < 1152.0 - 15.0 and p.x > 1120.0 and w.hi == 0.0,
		"in at the shop's door, across it, and its far wall (x %.1f in %s)" % [p.x, p.sector.name])

# ---- shots ----------------------------------------------------------------------

func _shopper(z: float) -> Actor:
	for a in game.actors:
		if a.type == "SHOPPER" and not a.removed and absf(a.z - z) < 1.0:
			return a
	return null

func _shots(lv: Level) -> void:
	print("layers: shots")
	var p = game.player
	var down := _shopper(0.0)
	var up := _shopper(128.0)
	check(down != null and up != null and up.sector.name == "terrace" and down.sector.name == "ground",
		"a shopper under the terrace and one on it, one over the other")
	if down == null or up == null:
		return
	# hold them still where they are
	for a in [down, up]:
		a.x = 1344.0
		a.y = 640.0
		a.speed = 0.0
		game.blockmap.moved(a)
	# from under the terrace: level, the one downstairs; up, the deck
	_put(p, 1344, 760, 0, -PI / 2)
	var tr: Dictionary = game.trace(p, p.angle, 0.0, 2000.0)
	check(tr.actor == down, "from under the terrace, a level shot finds the shopper beside you")
	var pitch := atan2(up.z + 30.0 - p.eye_z(), 120.0)
	tr = game.trace(p, p.angle, pitch, 2000.0)
	check(tr.actor == null and absf(tr.z - 112.0) < 0.01, "aimed up at the one on the terrace: the deck's underside (z %.1f)" % tr.z)
	var hp: float = up.health
	var got = game.hitscan(p, p.angle, 2000.0, 10.0, {"pitch": pitch, "shot": true})
	check(got == null and up.health == hp and absf(game.last_hit.z - 112.0) < 0.01,
		"and a round fired so stops in the deck (at %.1f), the shopper over it untouched" % game.last_hit.z)
	# from the yard, over the terrace's edge
	_put(p, 1344, 100, 0, PI / 2)
	pitch = atan2(up.z + 50.0 - p.eye_z(), 540.0)
	tr = game.trace(p, p.angle, pitch, 2000.0)
	check(tr.actor == up, "from the yard, a round over the terrace's edge finds the shopper on it")
	var low := atan2(up.z + 30.0 - p.eye_z(), 540.0) - 0.06
	tr = game.trace(p, p.angle, low, 2000.0)
	check(tr.actor == null and absf(tr.z - 112.0) < 0.01, "and one aimed lower goes under the edge and into the deck's underside")
	# from the terrace, down at the one under it
	_put(p, 1344, 760, 128, -PI / 2)
	pitch = atan2(down.z + 30.0 - p.eye_z(), 120.0)
	tr = game.trace(p, p.angle, pitch, 2000.0)
	check(tr.actor == null and absf(tr.z - 128.0) < 0.01, "from the terrace, down at the one under it: the terrace's floor")

# ---- doors ------------------------------------------------------------------

func _doors(lv: Level) -> void:
	print("layers: doors")
	var p = game.player
	var dd: Array = game.level.doors
	var west: Level.Door = null
	var east: Level.Door = null
	for d in dd:
		if d.z0 == 0.0:
			west = d
		elif d.z0 == 128.0:
			east = d
	check(dd.size() == 2 and west != null and east != null, "two doors: the shop's and the office's (%d)" % dd.size())
	if west == null or east == null:
		return
	check(west.style == "swing" and west.top == 96.0 and west.lintel_top == 96.0 and west.wall == 16.0 and west.inside.x > 0.5,
		"the shop's swings into it, 96 high, under its lintel block, through a wall 16 thick (%s..%s, into %s)" % [west.top, west.lintel_top, west.inside])
	check(east.style == "slide" and east.top == 224.0 and east.lintel_top == 224.0 and east.inside.x < -0.5 and east.wall == 16.0,
		"the office's slides, 96 over its floor, under its lintel (%s..%s)" % [east.top, east.lintel_top])
	var doors: Doors = game.doors
	var settle := func(n: int) -> void:
		for i in n:
			doors.tic()
	# far off, it shuts
	_put(p, 300, 768, 0, 0.0)
	settle.call(200)
	check(west.open == 0.0 and east.open == 0.0, "nobody near: both shut")
	var hit: Dictionary = game.level.ray_hit_wall(700, 768, 40, 900, 768, 40)
	check(not hit.is_empty() and hit.line.door == west, "a round at the shut door stops in it")
	check(game.level.sight_blocked(700, 768, 40, 900, 768, 40), "and nobody sees through it")
	# LOCKED: it stays shut, and stops you
	west.locked = true
	_put(p, 690, 768, 0, 0.0)
	_drive(1.0, 60)
	check(west.open == 0.0 and p.x < 768.0 - 15.0 and p.x > 740.0, "locked, it stays shut and stops you (x %.1f)" % p.x)
	# unlocked, up to it and it opens, through into the shop
	west.locked = false
	_drive(1.0, 60)
	check(west.open > 0.9 and p.x > 800.0 and p.sector.name == "shop", "unlocked, it opens as you come, and you are in (x %.1f)" % p.x)
	hit = game.level.ray_hit_wall(700, 768, 40, 900, 768, 40)
	check(hit.is_empty(), "open, a round goes through")
	hit = game.level.ray_hit_wall(700, 768, 104, 900, 768, 104)
	check(not hit.is_empty() and hit.line.door != west, "but not over it: the lintel block stops it (at x %.0f)" % (hit.x if not hit.is_empty() else -1.0))
	# THE USE KEY: a door that does not open by itself
	west.auto = false
	_put(p, 300, 768, 0, 0.0)
	settle.call(200)
	check(west.open == 0.0, "not by itself: it shuts behind you")
	_put(p, 730, 768, 0, 0.0)
	settle.call(20)
	check(west.open == 0.0, "and stays shut with you at it")
	check(doors.use(p), "the use key finds it")
	settle.call(20)
	check(west.open == 1.0, "and opens it")
	doors.use(p)
	settle.call(20)
	check(west.open == 0.0, "and again shuts it")
	west.auto = true
	# ON THE STOREY OVER: the office's door opens for you up there, not
	# for somebody in the yard under it
	_put(p, 1200, 768, 0, 0.0)
	settle.call(40)
	check(east.open == 0.0, "the office's door does not open for you down in the yard")
	_put(p, 1230, 768, 128, PI)
	settle.call(40)
	check(east.open == 1.0, "and does from the terrace")

# ---- troops ---------------------------------------------------------------

## A trooper sent after the player, until it is in `room` (or `tics` run
## out): where it got to.
func _chase(from: Vector2, room: String, tics: int) -> Dictionary:
	var p = game.player
	var a: Actor = game.spawn("SWAT", from.x, from.y, 0.0)
	a.target = p
	a.set_state(a.info.see)
	var got := false
	var hi := 0.0
	for i in tics:
		game.tics += 1
		a.tic()
		if game.doors != null:
			game.doors.tic()
		hi = maxf(hi, a.z)
		if a.sector != null and a.sector.name == room:
			got = true
			break
	var out := {"got": got, "tics": game.tics, "z": a.z, "hi": hi, "at": Vector2(a.x, a.y), "in": a.sector.name if a.sector else "?"}
	a.remove()
	return out

func _troops(lv: Level) -> void:
	print("layers: troops")
	var p = game.player
	var nav: Nav = game.nav
	check(nav != null and nav.links > 0, "the rooms are a graph of ways (%d)" % (nav.links if nav else 0))
	p.health = 1000000
	# UP THE STAIRS: from the yard, after you on the terrace
	_put(p, 1400, 700, 128, PI / 2)
	var t0: int = game.tics
	var r := _chase(Vector2(1344, 1450), "terrace", 1500)
	check(r.got and r.z == 128.0, "a trooper in the yard goes up the stairs after you on the terrace (%s at z %.0f, %d tics)" % [r.in, r.z, r.tics - t0])
	# THROUGH A DOOR: from the yard, after you in the shop
	_put(p, 1000, 768, 0, 0.0)
	t0 = game.tics
	r = _chase(Vector2(500, 900), "shop", 1500)
	check(r.got and r.z == 0.0, "one outside the shop comes in through its door after you (%s, %d tics)" % [r.in, r.tics - t0])
	# BOTH: up the stairs, across the terrace, through the office's door
	_put(p, 900, 768, 128, 0.0)
	t0 = game.tics
	r = _chase(Vector2(1344, 1450), "office floor", 2500)
	check(r.got and r.z == 128.0, "and one in the yard finds the stairs and the office's door after you in the office (%s at z %.0f, %d tics)" % [r.in, r.z, r.tics - t0])
	# and without the graph (Doom's own chase), it does not find them
	game.nav = null
	r = _chase(Vector2(1344, 1450), "office floor", 2500)
	game.nav = nav
	check(not r.got, "(which, chasing on the plan as Doom does, it never would: %s at z %.0f)" % [r.in, r.z])
	# A LOCKED DOOR is no way through
	var west: Level.Door = null
	for d in game.level.doors:
		if d.z0 == 0.0:
			west = d
	west.locked = true
	var nav2 := Nav.new(game.level)
	var shop := game.level.span_at(1000, 768, 1) as Level.Sector
	var yard: Level.Sector = game.level.sector_at(500, 900)
	check(nav.path(yard.index, Vector2(500, 900), shop.index, Vector2(1000, 768)).size() > 0
		and nav2.path(yard.index, Vector2(500, 900), shop.index, Vector2(1000, 768)).is_empty(),
		"and a locked door is no way in")
	west.locked = false
	p.health = 100

func _sight(lv: Level) -> void:
	print("layers: sight")
	var down := _shopper(0.0)
	var up := _shopper(128.0)
	if down == null or up == null:
		return
	check(lv.sight_blocked(down.x, down.y + 40.0, down.eye_z(), up.x, up.y - 40.0, up.eye_z()),
		"the one under the terrace cannot see the one on it: the slab")
	check(not down.can_see(up) and not up.can_see(down), "nor the other way (can_see)")
	var p = game.player
	_put(p, 1344, 100, 0, PI / 2)
	check(not lv.sight_blocked(p.x, p.y, p.eye_z(), up.x, up.y, up.z + 40.0), "from the yard, over the edge, you see the one on the terrace")
	check(not lv.sight_blocked(p.x, p.y, p.eye_z(), down.x, down.y, down.z + 40.0), "and under it, the one beneath")

# ---- the crowd ------------------------------------------------------------------

func _crowd(lv: Level) -> void:
	print("layers: an actor on each storey")
	var p = game.player
	_put(p, 200, 200, 0, 0.0)
	var up := _shopper(128.0)
	var down := _shopper(0.0)
	var townie: Actor = null
	for a in game.actors:
		if a.type == "TOWNIE":
			townie = a
	check(townie != null and townie.z == 128.0 and townie.sector.name == "office floor", "a townie in the office, on its floor")
	for a in [up, down]:
		if a != null:
			a.speed = float(a.info.get("speed", 0))
	var ok_up := true
	var ok_down := true
	var ok_t := true
	var moved := 0.0
	var x0: float = up.x if up != null else 0.0
	var y0: float = up.y if up != null else 0.0
	for i in 400:
		for a in game.actors:
			a.tic()
		if up != null and not up.removed:
			ok_up = ok_up and up.z == 128.0 and up.sector.storey == 1
			moved = maxf(moved, Vector2(up.x - x0, up.y - y0).length())
		if down != null and not down.removed:
			ok_down = ok_down and down.z <= 112.0 and down.sector.storey == 0
		if townie != null:
			ok_t = ok_t and townie.z == 128.0
	check(ok_up, "the shopper on the terrace stays on it for 400 tics (moved %.0f)" % moved)
	check(ok_down, "the one under it stays downstairs")
	check(ok_t, "and the townie upstairs")
	# a scare sets them running — and nobody runs off the terrace's edge
	if up != null:
		up.A_Scare(up.x + 10.0, up.y + 10.0)
		var ok := true
		var x1: float = up.x
		var y1: float = up.y
		var far := 0.0
		for i in 200:
			up.tic()
			if ok and up.z != 128.0:
				print("   fell at tic %d: (%.1f, %.1f) z %.1f in %s" % [i, up.x, up.y, up.z, up.sector.name])
			ok = ok and up.z == 128.0
			far = maxf(far, Vector2(up.x - x1, up.y - y1).length())
		check(ok and far > 32.0, "a frightened shopper upstairs runs (%.0f), and does not run off the edge" % far)

# ---- the network ----------------------------------------------------------------

func _net() -> void:
	print("layers: over the network")
	var map := {"kind": "layers", "seed": 1, "opts": {}}
	var hg = preload("res://godot/scripts/game/game.gd").new()
	hg.net_map = map
	root.add_child(hg)
	hg.set_process(false)
	var sim := SimServer.new(hg, map, 16, {"fragLimit": 50})
	var clock := [0]
	var now := func() -> int: return clock[0]
	var pa := NetTransport.Loopback.pair()
	sim.accept(pa[1])
	var c1 := NetClient.new(pa[0], "ONE", now)
	var cg = preload("res://godot/scripts/game/game.gd").new()
	cg.net_map = c1.map
	root.add_child(cg)
	cg.set_process(false)
	var ng := NetGame.new(cg, c1, now)
	var pb := NetTransport.Loopback.pair()
	sim.accept(pb[1])
	var c2 := NetClient.new(pb[0], "TWO", now)
	check(c1.welcome != null and c2.welcome != null and cg.level.layered, "two clients on a host of THE ANNEXE, the client's level in storeys too")
	var step := func(n: int) -> void:
		for i in n:
			clock[0] += 1000 / 35
			cg.tic()
			var c := TicCmd.new_cmd()
			c.tic = clock[0]
			c2.send(TicCmd.quantize(c))
			sim.step()
			ng.frame()
	step.call(10)
	var p1 = sim.clients[1].player
	var p2 = sim.clients[2].player
	# TWO goes up on the terrace; ONE into the yard under it
	for pr in [[p2, 1400.0, 700.0, 128.0], [p1, 1300.0, 900.0, 0.0]]:
		var q = pr[0]
		q.x = pr[1]
		q.y = pr[2]
		q.z = pr[3]
		q.momx = 0.0
		q.momy = 0.0
		q.momz = 0.0
		q.on_ground = true
		q.sector = hg.level.span_at(q.x, q.y, q.z + 1.0)
	step.call(30)
	var o: Array = sim.other_for(p2)
	check(float(o[3]) == 128.0, "the host's snapshot of TWO carries the height: z %s" % str(o[3]))
	var you: Dictionary = sim.you_for(p1)
	check(float(you.z) == 0.0 and p2.sector.name == "terrace" and p1.sector.name == "ground", "and ONE's own, under the deck")
	var pup = ng.puppets.get(2)
	check(pup != null and absf(pup.a.z - 128.0) < 0.01 and pup.a.sector.name == "terrace" and pup.a.sector.storey == 1,
		"ONE draws TWO on the terrace, in its storey (z %s)" % (str(pup.a.z) if pup != null else "none"))
	check(absf(cg.player.z) < 0.01 and absf(cg.player.x - 1300.0) < 0.5 and cg.player.sector.name == "ground" and cg.player.sector.above != -1,
		"and itself in the yard under the deck, where the host has it (z %.1f, %s)" % [cg.player.z, cg.player.sector.name])
	# a round from ONE, up through the deck at TWO, does nothing
	var h2: float = p2.health
	var pitch := atan2(128.0 + 30.0 - p1.eye_z(), Vector2(p2.x - p1.x, p2.y - p1.y).length())
	sim.game.hitscan(p1, atan2(p2.y - p1.y, p2.x - p1.x), 2000.0, 30.0, {"pitch": pitch, "shot": true})
	check(p2.health == h2, "and ONE's round up at TWO stops in the deck")
	ng.close()
	c2.close()
