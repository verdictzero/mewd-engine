## MEWD — a picture of the gore, for looking at without the game.
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy --rendering-driver opengl3 \
##   --resolution 1280x720 --script res://godot/tests/gore_shot.gd -- out.png [tics] [gore|fire]
##
## The maze (seed 7), five shoppers stood down the longest clear run from
## the START, and then: one killed the ordinary way (damage -> SHOP_GIB ->
## A_Gib -> game.gib -> Giblets.burst), one blown apart by a warhead
## beside them (the burst and then Giblets.eviscerate), one frozen and
## shattered, one set alight (Effects.body_fire every tic), one burned
## away to a heap of ash. Run for `tics` (default 10: the pieces in the
## air) and drawn from the START; 150 shows what is left on the room.
## Asserts the counts come out as the JS's would, and prints them.
## Mode `fire` instead sets three of them alight close up and leaves a
## heap of ash, for the body fire, the embers and the smoke (default 60
## tics).
extends SceneTree

class StubPlayer:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var radius := 16.0
	var dead := false
	func eye_z() -> float:
		return z + 41.0

class StubGame:
	var level: Level
	var actors: Array = []
	var blockmap := ActorGrid.new()
	var player = null
	var forest = null
	var tics := 0
	var fx: Effects
	var giblets: Giblets
	var gore_decals: GoreDecals
	func spawn(type: String, x: float, y: float, a := 0.0, opts := {}) -> Actor:
		var act := Actor.new(self, type, x, y, a, opts)
		actors.append(act)
		return act
	func scare(x: float, y: float, r: float) -> void:
		for a in blockmap.near_radius(x, y, r):
			if a.dead or a.removed or not a.info.has("scareRange"):
				continue
			if U.dist2(a.x, a.y, x, y) < r * r:
				a.A_Scare(x, y)
	func play_sound(_n, _at) -> void:
		pass
	func on_monster_killed(_a, _s) -> void:
		pass
	## what game.gd's gib should become
	func gib(a: Actor) -> void:
		giblets.burst(a)
		a.remove()

var out := "gore_shot.png"
var tic_count := 10
var g: StubGame
var standees: Standees
var cam: Camera3D
var frames := 0
var torches: Array[Actor] = []
var mode := "gore"
var _ang := 0.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		tic_count = int(args[1])
	if args.size() > 2:
		mode = args[2]
	U.p_seed()
	g = StubGame.new()
	g.level = DocCompile.compile(MazeMap.build(7))
	var root3 := Node3D.new()
	root.add_child(root3)
	root3.add_child(MapGeo.new(TexBank.new()).build(g.level))
	var start = null
	for t in g.level.things:
		if t.type == "START":
			start = t
	var sx := float(start.x)
	var sy := float(start.y)
	# the longest clear run out of the START, of the four axes
	var best_ang := 0.0
	var best_len := 0.0
	for k in 4:
		var ang := k * PI / 2.0
		var hit := g.level.ray_hit_wall(sx, sy, 30, sx + cos(ang) * 2000.0, sy + sin(ang) * 2000.0, 30)
		var l: float = 2000.0 * float(hit.t) if not hit.is_empty() else 2000.0
		if l > best_len:
			best_len = l
			best_ang = ang
	print("gore: clear run %d units at %d degrees" % [best_len, rad_to_deg(best_ang)])
	_ang = best_ang
	var c := cos(best_ang)
	var s := sin(best_ang)
	g.player = StubPlayer.new()
	g.player.x = sx - c * 30.0
	g.player.y = sy - s * 30.0

	var t0 := Time.get_ticks_msec()
	g.fx = Effects.new(g)
	g.giblets = Giblets.new(g)
	g.gore_decals = GoreDecals.new(g)
	for n in [g.gore_decals, g.fx, g.giblets]:
		root3.add_child(n)
	print("gore: effects baked and built in %d ms" % (Time.get_ticks_msec() - t0))

	if mode == "fire":
		_fire_scene(sx, sy, c, s, best_len)
		return
	var people: Array[Actor] = []
	var steps := [110.0, 170.0, 230.0, 300.0, 370.0]
	for i in steps.size():
		var d: float = minf(steps[i], best_len - 40.0)
		var side := (-1.0 if i & 1 else 1.0) * 14.0
		people.append(g.spawn("SHOPPER", sx + c * d - s * side, sy + s * d + c * side, 0.0, {"variant": i * 3}))
	# 0: the ordinary way — the state table does the rest
	people[0].damage(100, null, {"fire": true})
	assert(people[0].removed, "the burst should remove who it happened to")
	# 1: a warhead going off on the near side of them: the burst, then the gore
	var v: Actor = people[1]
	var at := Vector3(v.x - c * 30.0, v.y - s * 30.0, v.z + 20.0)
	v.damage(100, null, {})
	var marks := g.giblets.eviscerate(v, at, 1.5)
	# 2: frozen solid and hit
	var f: Actor = people[2]
	f.frozen = true
	g.giblets.shatter(f, {"dx": c, "dy": s, "force": 1.5})
	f.remove()
	# 3: alight
	torches.append(people[3])
	people[3].ignite(900)
	# 4: burned away where they stood
	g.giblets.ash_pile(people[4])
	people[4].remove()
	print("gore: bursts %d, eviscerations %d (%d marks), shatters %d, ashes %d, pools %d" % [
		g.giblets.bursts, g.giblets.eviscerations, marks, g.giblets.shatters, g.giblets.ashes, g.giblets.pools])
	assert(g.giblets.bursts == 2 and g.giblets.eviscerations == 1 and g.giblets.shatters == 1)
	assert(g.giblets.chunks.count == 2 * Giblets.GIB.count + Giblets.GORE.count)

	t0 = Time.get_ticks_msec()
	_run()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	for t in tic_count:
		_tic()
	print("gore: %d tics in %d ms — chunks %d, trail %d, shards %d, blood %d, body fire %d, embers %d, smoke %d, decals %d" % [
		tic_count, Time.get_ticks_msec() - t0, g.giblets.chunks.count, g.giblets.trail.count, g.giblets.shards.count,
		g.fx.gore.count, g.fx.body_flames.count, g.fx.embers.count, g.fx.smoke.count, g.gore_decals.bloods])

	standees = Standees.new()
	root.get_child(0).add_child(standees)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 2.0
	cam.far = 16000.0
	root.get_child(0).add_child(cam)
	cam.position = U.v3(g.player.x, g.player.y, 49)
	cam.rotation = Vector3(-0.12, _ang - PI / 2.0, 0.0)
	cam.make_current()

func _tic() -> void:
	g.tics += 1
	for a in g.actors:
		a.tic()
	# what Actor.burn_tic will call once hooked up
	for a in torches:
		if not a.removed and a.burning > 0:
			g.fx.body_fire(a)
	g.fx.tic()
	g.giblets.tic()

func _process(_dt: float) -> bool:
	frames += 1
	standees.draw(g.actors, cam.position, g.tics)
	g.giblets.draw()
	g.fx.draw()
	if frames == 6:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		return true
	return false

## three alight close up, and a heap of ash
func _fire_scene(sx: float, sy: float, c: float, s: float, _run: float) -> void:
	if OS.get_cmdline_user_args().size() < 2:
		tic_count = 60
	for i in 3:
		var d := 120.0 + i * 50.0
		var side := (i - 1) * 22.0
		var a := g.spawn("SHOPPER", sx + c * d - s * side, sy + s * d + c * side, 0.0, {"variant": 2 + i * 4})
		a.ignite(900)
		torches.append(a)
	var gone := g.spawn("SHOPPER", sx + c * 90.0 + s * 20.0, sy + s * 90.0 - c * 20.0)
	g.giblets.ash_pile(gone)
	gone.remove()
	g.fx.fireball(sx + c * 600.0, sy + s * 600.0, 40.0, 90.0, 40)
	_run()
