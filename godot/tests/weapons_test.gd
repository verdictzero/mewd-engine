## MEWD — the guns against real people, headless.
##
##   godot --headless --script res://godot/tests/weapons_test.gd -- --seed=7
##
## Builds the real Game on the maze, finds the longest clear run out of
## the START, stands a shopper down it, turns the player to face them and
## holds the trigger with each gun in turn, asserting what the web build
## does: the MINIGUN kills them (and they come apart), the FLAMER sets
## them alight and they RUN, the EXTINGUISHER freezes them solid, and the
## BORE locks, flies, drills and bursts, and the LANCE charges to the red,
## lets go, and its column kills whoever is down the run and sears the
## far wall; and the LAUNCHER's thermal sight comes up with it, takes the
## zoom and the phone's AIM, draws a bracket on its lock, and its screen
## is the model's own panel. Prints OK or fails.
extends SceneTree

var game
var failures := 0

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	var p = game.player
	var run := _clear_run(p)
	print("weapons: clear run %d at %d deg" % [run.y, rad_to_deg(run.x)])
	# every other actor out of the way
	for a in game.actors:
		if a.monster:
			a.remove()
	_minigun(p, run)
	_flamer(p, run)
	_extinguisher(p, run)
	_bore(p, run)
	_launcher(p, run)
	_thermal(p, run)
	_arc(p, run)
	_lance(p, run)
	_potato(p, run)
	print("weapons: %s" % ("OK" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1

func _clear_run(p) -> Vector2:
	var best := Vector2()
	for k in 4:
		var ang := k * PI / 2.0
		var hit: Dictionary = game.level.ray_hit_wall(p.x, p.y, 30, p.x + cos(ang) * 2000.0, p.y + sin(ang) * 2000.0, 30)
		var l: float = 2000.0 * float(hit.t) if not hit.is_empty() else 2000.0
		if l > best.y:
			best = Vector2(ang, l)
	return best

func _victim(p, run: Vector2, d: float) -> Actor:
	d = minf(d, run.y - 40.0)
	var a: Actor = game.spawn("SHOPPER", p.x + cos(run.x) * d, p.y + sin(run.x) * d, 0.0, {"variant": 3})
	p.angle = run.x
	p.pitch = -0.05
	return a

func _hold(weapon: String, tics: int, stop: Callable = Callable()) -> int:
	var p = game.player
	p.weapon = weapon
	p.pending_weapon = ""
	p.spin = 0.0
	game._autofire = true
	for i in tics:
		game.tic()
		if stop.is_valid() and stop.call():
			game._autofire = false
			return i
	game._autofire = false
	return tics

func _settle(tics: int) -> void:
	for i in tics:
		game.tic()

func _minigun(p, run: Vector2) -> void:
	var v := _victim(p, run, 200.0)
	var n := _hold("MINIGUN", 90, func(): return v.removed or v.dead)
	check(v.removed or v.dead, "MINIGUN: the shopper is dead after %d tics" % n)
	check(game.giblets.bursts >= 1, "MINIGUN: and came apart (%d bursts)" % game.giblets.bursts)

func _flamer(p, run: Vector2) -> void:
	var v := _victim(p, run, 160.0)
	var x0 := v.x
	var y0 := v.y
	var n := _hold("FLAMER", 60, func(): return v.burning > 0)
	check(v.burning > 0 and v.torch > 0, "FLAMER: the shopper is alight after %d tics (torch %d)" % [n, v.torch])
	_settle(40)
	var moved := sqrt(U.dist2(v.x, v.y, x0, y0))
	check(moved > 30.0 or v.removed, "FLAMER: and ran (%d units) or already went off" % moved)
	_settle(300)
	check(v.removed, "FLAMER: and went off in the end")

func _extinguisher(p, run: Vector2) -> void:
	var v := _victim(p, run, 140.0)
	var n := _hold("EXTINGUISHER", 80, func(): return v.frozen)
	check(v.frozen, "EXTINGUISHER: the shopper froze solid after %d tics" % n)
	v.damage(10, p, {"shot": true})
	check(v.removed and game.giblets.shatters >= 1, "EXTINGUISHER: and a blow shattered them")

func _bore(p, run: Vector2) -> void:
	_settle(60)     # the last of the frost out of the air: a bore in ice shatters it
	var v := _victim(p, run, 300.0)
	p.pitch = 0.0
	p.weapon = "BORE"
	_settle(2)
	check(game.bore.lock == v, "BORE: the sight locked the shopper")
	var n := _hold("BORE", 120, func(): return v.bored > 0 or v.removed)
	print("  bore: fired %d, drilled %d, in flight %d, victim dead %s removed %s health %d" % [game.bore.fired, game.bore.drilled, game.bore.shots.size(), v.dead, v.removed, v.health])
	check(v.bored > 0, "BORE: the bore arrived and is drilling after %d tics" % n)
	_settle(90)
	check(v.removed or v.dead, "BORE: and they went off")

func _launcher(p, run: Vector2) -> void:
	_settle(40)
	var v := _victim(p, run, 600.0)
	var w := _victim(p, run, 640.0)
	p.pitch = 0.0
	p.ammo.rockets = 4
	# hold: the seeker takes a lock or four, then let go
	_hold("LAUNCHER", 80)
	var locked: int = game.missiles.locks.size()
	check(locked >= 1, "LAUNCHER: the seeker took %d locks" % locked)
	_settle(1)
	check(game.missiles.salvo_left() > 0 or game.missiles.fired > 0, "LAUNCHER: letting go fired the salvo")
	_settle(90)
	check(game.missiles.fired >= 1 and game.missiles.blasts >= 1, "LAUNCHER: %d fired, %d blasts" % [game.missiles.fired, game.missiles.blasts])
	check((v.dead or v.removed) and (w.dead or w.removed), "LAUNCHER: both people down the run are dead")
	check(game.giblets.eviscerations >= 1, "LAUNCHER: and came apart (%d eviscerations)" % game.giblets.eviscerations)

## THE THERMAL SIGHT (render/thermal.gd): the launcher's scope, driven by
## the same zoom and touch AIM as the lance's, rendering a feed of the one
## size the world's shaders take to be thermal, with the brackets of the
## world's reticles left out of it and its own on the glass.
func _thermal(p, run: Vector2) -> void:
	_settle(40)
	var th: ThermalScope = game.thermal
	check(th != null and th.get_parent() == game, "THERMAL: the game has a thermal sight, in its world")
	check(th.feed.size == Vector2i(172, 176) and th.feed.size != game.scope.feed.size,
		"THERMAL: its feed is %s, a size of its own (the lance's is %s)" % [th.feed.size, game.scope.feed.size])
	check((th.camera.cull_mask & MissileSystem.RETICLE_LAYER) == 0, "THERMAL: its camera does not draw the lock brackets")
	check(th.camera.environment != null and th.camera.environment.background_mode == Environment.BG_COLOR,
		"THERMAL: and has a cold sky of its own")
	var tc := TouchControls.new()
	game.touch = tc
	p.weapon = "LAUNCHER"
	p.pending_weapon = ""
	game._process(0.0)
	check(th.held and not game.scope.held and tc.scope_on and not tc.scope_up, "THERMAL: the launcher in hand holds it, and the phone gets AIM")
	check(ThermalScope._told == Vector2(172, 176), "THERMAL: and the world is told which viewport is thermal")
	game._zoom = true
	game._process(0.0)
	check(th.zoom_index == 1 and th.magnification() == 2.5 and absf(game.camera.fov - game.BASE_FOV * 0.9) < 0.01,
		"THERMAL: Z steps it to %sx and the view narrows to %.1f" % [th.magnification(), game.camera.fov])
	game._process(0.0)
	check(absf(th.camera.fov - game.camera.fov / th.magnification() * th.view_scale()) < 0.01, "THERMAL: the feed camera is the view over the magnification (%.2f)" % th.camera.fov)
	tc.aim_pulse = true
	game._process(0.0)
	check(th.zoom_index == 0 and not tc.aim_pulse, "THERMAL: the phone's AIM puts it down")
	tc.aim_pulse = true
	game._process(0.0)
	game._process(0.0)
	check(th.zoom_index == 1 and tc.scope_up, "THERMAL: and back up to the step it was at, with ZOOM")
	tc.zoom_pulse = true
	game._process(0.0)
	check(th.zoom_index == 2, "THERMAL: and ZOOM steps it on (%d)" % th.zoom_index)
	# a lock, and the glass brackets it
	var v := _victim(p, run, 500.0)
	p.pitch = 0.0
	p.ammo.rockets = 4
	game._autofire = true
	for i in 40:
		game.tic()
	game._process(0.0)
	game._process(0.0)
	var locks: int = game.missiles.locks.size()
	var marks: Array = th.tst.marks
	check(locks >= 1 and th.tst.locks == locks, "THERMAL: the glass counts %d locks" % th.tst.locks)
	check(marks.size() >= 1 and int(marks[0].n) >= 1, "THERMAL: and brackets the target (%d marks)" % marks.size())
	if not marks.is_empty():
		check(absf(float(marks[0].x) - th.panel.size.x / 2.0) < th.panel.size.x * 0.2,
			"THERMAL: in the middle of the glass (%d of %d)" % [marks[0].x, th.panel.size.x])
	game._autofire = false
	_settle(100)
	check(v.dead or v.removed, "THERMAL: and the salvo got them")
	# the lance takes the zoom back and the sight goes down
	p.weapon = "LANCE"
	game._process(0.0)
	check(not th.held and th.zoom_index == 0 and game.scope.held and ThermalScope._told == Vector2.ZERO,
		"THERMAL: the lance in hand puts the sight down and zeroes it")
	game.touch = null
	tc.free()
	# the screen is the launcher's own panel, measured off the model
	var w3 := Weapon3D.new()
	w3.scopes = {"LAUNCHER": th}
	root.add_child(w3)
	w3.set_weapon("LAUNCHER")
	var box: Vector4 = th.screen.get_shader_parameter("box") if th.screen != null else Vector4()
	var shape := box.w / box.z if box.z > 0.0 else 0.0
	check(th.screen != null and th.screen.shader.resource_path.ends_with("thermal_screen.gdshader"),
		"THERMAL: the launcher's display wears the thermal screen")
	check(absf(shape - ThermalScope.ASPECT) < 0.03, "THERMAL: and its panel is the feed's shape (%.3f, the feed %.2f)" % [shape, ThermalScope.ASPECT])
	# (left in the tree, hidden: freeing a loaded model under the headless
	# renderer's dummy mesh storage complains)
	w3.visible = false

func _arc(p, run: Vector2) -> void:
	_settle(60)
	var people := []
	for k in 5:
		people.append(_victim(p, run, 250.0 + k * 90.0))
	p.pitch = 0.0
	p.ammo.volts = 6
	_hold("ARC", ArcSystem.ARC.chargeTics + 5)
	_settle(30)
	var down := people.filter(func(a): return a.dead or a.removed).size()
	check(game.arc.fired == 1, "ARC: a full charge let go fired one bolt")
	check(game.arc.last_chain.size() >= 4, "ARC: the chain struck %d" % game.arc.last_chain.size())
	check(down >= 4, "ARC: %d of 5 down" % down)

func _lance(p, run: Vector2) -> void:
	_settle(60)
	var beam = game.weapon_system("charge")
	check(beam != null, "LANCE: the game hands the player a beam system")
	if beam == null:
		return
	# A TAP IS A VENT: two seconds and let go, nothing leaves the muzzle
	p.pitch = 0.0
	p.angle = run.x
	var shots0: int = beam.shots
	var cells0: int = p.ammo.cells
	_hold("LANCE", 2 * 35)
	check(p.charge == 70 and p.charge_stage() == 0, "LANCE: two seconds held is charge %d, stage %d" % [p.charge, p.charge_stage()])
	_settle(1)
	check(p.charge == 0 and beam.shots == shots0 and p.ammo.cells == cells0, "LANCE: let go under the red, it vented and spent nothing")
	_settle(2)     # the finger off the trigger: a press held through a vent does not wind again
	# AND SEVEN SECONDS IS THE SHOT: the victim down the run, the far
	# wall behind them
	var v := _victim(p, run, 500.0)
	var bursts0: int = game.giblets.bursts
	p.pitch = 0.0
	_hold("LANCE", 7 * 35 + 5)
	check(p.charge_stage() == 3, "LANCE: seven seconds held is stage %d" % p.charge_stage())
	# the tic the dial goes red is the first of the window: 7 s + 5 is six
	check(absf(p.hold_fraction() - (1.0 - 6.0 / 175.0)) < 1e-4, "LANCE: and the window at the top is draining (%.3f)" % p.hold_fraction())
	var cells1: int = p.ammo.cells
	_settle(1)
	check(beam.shots == shots0 + 1 and beam.live and p.beam_tics > 0, "LANCE: let go at the red, the column is out (stage %d, %d tics)" % [beam.stage, p.beam_tics])
	check(p.charge == 0 and p.fire_index >= 0, "LANCE: the coil is spent and the gun is firing")
	var n := 0
	while beam.live and n < 80:
		game.tic()
		n += 1
	check(not beam.live and p.beam_tics == 0 and n == Player.BEAM_TICS[2], "LANCE: the column was out %d tics (BEAM_TICS %d)" % [n, Player.BEAM_TICS[2]])
	check(v.dead or v.removed, "LANCE: the shopper down the run is dead (%d killed)" % beam.killed)
	check(game.giblets.bursts > bursts0, "LANCE: and came apart — three thousand a tic is past anybody's gib health")
	var h: Dictionary = beam.hit
	check(not h.is_empty() and absf(h.n.z) < 0.5, "LANCE: the column stopped on a wall")
	if not h.is_empty():
		var d := sqrt(U.dist2(h.at.x, h.at.y, p.x, p.y))
		check(absf(d - run.y) < 60.0, "LANCE: the far wall, %d units down a %d unit run" % [d, run.y])
	check(game.decals.sears == 1 and game.decals.slags == 3 + 7, "LANCE: one sear and %d slag on it" % game.decals.slags)
	check(beam.seared == 1 + game.decals.slags, "LANCE: and the beam counts them all (%d)" % beam.seared)
	check(beam.glow > 0.0, "LANCE: the light outlives the column")
	check(p.debug or p.ammo.cells == cells1 - 1, "LANCE: one cell spent")

# ---- the Irish potato cannon (game/potatoes.gd) ------------------------------

func _potato(p, run: Vector2) -> void:
	print("weapons: potato cannon")
	var pc: PotatoCannon = game.potatoes
	check(pc != null and game.weapon_system("potato") == pc and Weapons.WEAPONS.POTATO.slot == 8,
		"the potato cannon is slot 8, with a system of its own")
	var hp0: float = p.health
	p.health = 100000
	p.ammo.potatoes = Weapons.POTATOES
	# AT SOMEBODY: it goes off on them, a nuke
	var v := _victim(p, run, 420.0)
	p.pitch = 0.0
	var fired0: int = pc.fired
	_hold("POTATO", 120, func(): return pc.blasts > 0)
	game._autofire = false
	check(pc.fired > fired0, "the trigger fires a potato (%d fired)" % (pc.fired - fired0))
	check(pc.blasts == 1 and v.dead, "it flies to the shopper and goes off on them (blasts %d, dead %s)" % [pc.blasts, v.dead])
	check(not pc.nukes.is_empty(), "a nuke: the fireball, the column, the cap, the ring")
	var alive := 0
	for i in 40:
		game.tic()
	alive = pc.trail.count + pc.sparks.count
	check(alive > 0, "and its rainbow sparks (%d alight)" % alive)
	# AT A WALL: it bounces off, nobody there
	for i in 400:
		game.tic()
	var b0: int = pc.bounces
	var blasts0: int = pc.blasts
	p.angle = run.x
	p.pitch = 0.02
	p.fire_index = -1
	var s: Dictionary = pc.launch(p)
	var t0: int = game.tics
	var bounced := false
	var went := false
	for i in 12 * 35:
		game.tic()
		if pc.bounces > b0:
			bounced = true
		if pc.blasts > blasts0:
			went = true
			break
	check(bounced, "down the clear run, it bounces off what it meets (%d bounces)" % (pc.bounces - b0))
	check(went and game.tics - t0 <= PotatoCannon.SHOT.fuse + 2, "and goes off by itself in the end (%d tics)" % (game.tics - t0))
	check(p.health > 0, "and the one who fired it lives (their own nuke is a share)")
	# THE GREEN THERMAL SIGHT: the cannon in hand holds it, Z steps it
	var gt: ThermalScope = game.green_thermal
	p.weapon = "POTATO"
	game._process(0.0)
	check(gt != null and gt.green and gt.held and not game.thermal.held and game.weapon3d == null or gt.held,
		"the cannon holds its own thermal sight, in green")
	gt.set_zoom(1)
	game._process(0.0)
	check(gt.zoom_index == 1 and ThermalScope._told == gt.feed_size(), "and zoomed, the world draws heat for it (%sx)" % str(gt.magnification()))
	gt.set_zoom(0)
	# THE HOPPER fills again, a potato every two seconds
	var dbg: bool = p.debug
	p.debug = false
	p.ammo.potatoes = 0
	p.ammo_tick.potatoes = 0
	for i in Weapons.POTATO_REGEN_EVERY + 2:
		game.tic()
	p.debug = dbg
	check(p.ammo.potatoes == 1, "an empty hopper has a potato again in two seconds (%d)" % p.ammo.potatoes)
	for i in 200:
		game.tic()
	p.health = hp0

