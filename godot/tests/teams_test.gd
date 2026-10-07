## MEWD — teams (at the user's request: "add teams as a multiplayer
## concept"), headless, on CANDY LAND:
##
##   godot --headless --script res://godot/tests/teams_test.gd
##
## A host's match with `teams` on (HOST GAME's TEAM DEATHMATCH, --teams):
## two sides, SWAT and ARMY, the joiners dealt out between them; nothing
## a teammate fires hurts you, the other side's does; a kill scores for
## the killer's side and ends the round at the limit; a teammate drops in
## beside its own. And a host without it is a deathmatch as before.
## Prints OK or fails.
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		fails += 1

func _game(net_map: Dictionary) -> Node:
	var g = preload("res://godot/scripts/game/game.gd").new()
	g.net_map = net_map
	g.draw_world = false
	root.add_child(g)
	g.set_process(false)
	return g

func _init() -> void:
	await process_frame
	var map := {"kind": "candyland", "seed": 7, "opts": {"people": 0}}
	var g = _game(map)
	var sim := SimServer.new(g, map, 16, {"teams": true, "teamLimit": 3}, func(_s): pass)
	var m: NetMatch = sim.match_
	check(m.mode == "tdm" and m.teams != null and m.teams.size() == 2, "a host with teams plays a team deathmatch")
	check(m.teams[0].name == "SWAT" and m.teams[1].name == "ARMY", "its sides are SWAT and ARMY")
	check(m.limit() == 3, "to the team limit (%d)" % m.limit())
	var ps := []
	for i in 4:
		ps.append(m.join(i + 1, "P%d" % (i + 1)))
	check(ps.map(func(p): return p.team) == [0, 1, 0, 1], "four joiners dealt out between them (%s)" % str(ps.map(func(p): return p.team)))
	# out of their pods and past the spawn guard, standing about
	for p in ps:
		p.invincible = false
		p.guard_until = 0
		if p.pod != null:
			p.pod.active = false
	var a = ps[0]
	var b = ps[1]
	var mate = ps[2]
	check(m.friendly(a, mate) and not m.friendly(a, b) and not m.friendly(a, a), "a teammate is friendly, the other side and you are not")
	var h0: int = mate.health
	mate.damage(60.0, a, {"impact": true})
	check(mate.health == h0, "a teammate's blast does not hurt you (%d)" % mate.health)
	mate.damage(30.0, a, {"shot": true})
	check(mate.health == h0, "nor do its rounds")
	var hb: int = b.health
	b.damage(30.0, a, {"shot": true})
	check(b.health < hb, "the other side's do (%d)" % b.health)
	var ha: int = a.health
	a.damage(20.0, a, {"impact": true})
	check(a.health < ha, "and your own blast still finds you")
	check(not g.targets_for(a).has(mate) and g.targets_for(a).has(b), "a round passes a teammate by, not the other side")
	# a kill scores for the killer's side
	b.damage(1000.0, a, {"shot": true})
	check(b.dead and a.frags == 1 and m.teams[0].score == 1 and m.teams[1].score == 0, "a kill scores for SWAT (%d - %d)" % [m.teams[0].score, m.teams[1].score])
	var t: Dictionary = m.table()
	check(t.mode == "tdm" and t.teams is Array and t.teams[0].name == "SWAT" and int(t.teams[0].score) == 1, "and the table says so")
	# a teammate drops in beside its own (40 to 80 m: 1280 to 2560 units, a
	# few metres of searching for flat ground either side)
	var near := 0
	for k in 6:
		var at: Array = m.drop_point(mate)
		var d := Vector2(float(at[0]) - a.x, float(at[1]) - a.y).length()
		if d < 2560.0 + 400.0:
			near += 1
	check(near >= 4, "a teammate drops in beside its own (%d of 6 within 90 m)" % near)
	# to the limit: SWAT wins the round
	for k in 2:
		var foe = ps[3]
		foe.dead = false
		foe.health = 100
		foe.invincible = false
		foe.damage(1000.0, a, {"shot": true})
	check(m.over != null and str(m.over.winner) == "SWAT", "three kills: SWAT wins the round (%s)" % str(m.over))
	g.queue_free()
	await process_frame
	# without it, a deathmatch as before
	var g2 = _game(map)
	var sim2 := SimServer.new(g2, map, 16, {}, func(_s): pass)
	check(sim2.match_.mode == "dm" and sim2.match_.teams == null, "a host without teams is a deathmatch")
	var q = sim2.match_.join(1, "Q")
	check(q.team == -1, "its players on no side")
	g2.queue_free()
	await process_frame
	print("teams: " + ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
