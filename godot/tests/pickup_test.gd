## MEWD — the pickups, finite ammunition, armour on top of health and
## IDDQD, headless (game/pickups.gd, game/cheats.gd, Player), at the
## user's request ("implement these pickups and the mechanics / ui
## elements to utilize them, health ammo armor etc, scatter them around,
## make finite ammo and health a thing, as well as armor on top of
## health, make the physical key code IDDQD or R1 + L1 + R2 + L2 + R3 +
## L3 together make the player invincible and have infinite ammo"):
##   - they are laid, the same off the same seed, every one on open
##     ground, out of the houses, off your start and apart;
##   - walked over, one is taken — and left lying when it would do
##     nothing; it comes back after its time, unseen;
##   - armour takes its class's share of a blow; health over the top
##     bleeds back; the tanks stay empty unless something is picked up
##     (the flamer's fuel trickles back as far as a pilot's worth);
##   - an empty gun says so and the hands go to one with something in it;
##   - the mini nuke hands you the potato cannon;
##   - I D D Q D typed by the keys' places, or the six shoulder buttons,
##     triggers and stick clicks squeezed together, turn on (and off)
##     invincible and infinite ammo — and not in a match;
##   - a match's life starts with its own rules' health, armour and rounds.
##   godot --headless --script res://godot/tests/pickup_test.gd -- --map=candyland
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

func _init() -> void:
	U.p_seed()
	game = preload("res://godot/scripts/game/game.gd").new()
	root.add_child(game)
	await process_frame
	var p: Player = game.player
	var pk: Pickups = game.pickups
	var lv = game.level
	# the crowd out of the way (they walk into things)
	for a in game.actors:
		if a.monster:
			a.remove()
	print("pickups: %d on %s" % [pk.items.size(), game.map_name])
	_laid(pk, lv)
	_taking(p, pk)
	_finite(p)
	_back(p, pk)
	_empty(p)
	_cheat(p)
	_match(p)
	_clock(p)
	print("pickups: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)

func _start() -> Vector2:
	for t in game.level.things:
		if t.type == "START":
			return Vector2(t.x, t.y)
	return Vector2.ZERO

# ---- where they lie -----------------------------------------------------------

func _laid(pk: Pickups, lv) -> void:
	var start := _start()
	var n := pk.items.size()
	# (how many each island should have: GODOT.txt, PICKUPS)
	var want: Array = {"candyland": [140, 240], "island0": [50, 110], "debugland": [25, 60]}.get(game.map_name, [40, 300])
	check(n >= want[0] and n <= want[1], "%d laid on %s (%d to %d)" % [n, game.map_name, want[0], want[1]])
	var counts := {}
	var bad := 0
	var crowded := 0
	var near_start := 0
	for i in n:
		var it: Dictionary = pk.items[i]
		var key: String = Pickups.KINDS[it.k].key
		counts[key] = counts.get(key, 0) + 1
		if not lv.on_land(it.x, it.y, 32.0) or lv.in_house(it.x, it.y, 24.0) or absf(it.z - lv.floor_at(it.x, it.y)) > 2.0:
			bad += 1
		if Vector2(it.x, it.y).distance_to(start) < Pickups.FROM_START:
			bad += 1
		if Vector2(it.x, it.y).distance_to(start) < 640.0:
			near_start += 1
		for j in range(i + 1, n):
			var o: Dictionary = pk.items[j]
			if absf(o.x - it.x) < Pickups.APART * 0.99 and absf(o.y - it.y) < Pickups.APART * 0.99:
				crowded += 1
	print("pickups: %s" % str(counts))
	check(bad == 0, "every one on open ground, out of the houses, on the floor, off the pod (%d not)" % bad)
	check(crowded == 0, "and apart (%d too close)" % crowded)
	check(near_start >= 3, "a cache by the start (%d within 20 m)" % near_start)
	check(counts.get("health", 0) > 0 and counts.get("small_ammo", 0) > 0 and counts.get("armor", 0) > 0,
		"medkits, rounds and armour among them")
	var nukes: int = {"candyland": 2, "island0": 1, "debugland": 1}.get(game.map_name, -1)
	check(nukes < 0 or counts.get("mini_nuke_ammo", 0) == nukes, "the mini nukes laid by rule: %d (%d)" % [nukes, counts.get("mini_nuke_ammo", 0)])
	# THE SAME OFF THE SAME SEED: a match's every machine lays the same
	var was: Array = pk.wire_list()
	pk.place(game.seed, game.roads, false)
	check(pk.wire_list() == was, "laid again off the same seed, the same list")
	# a match's: the rings round the start, only what its guns can use
	pk.place(game.seed, game.roads, true)
	var mp_ok := pk.items.all(func(it): return Pickups.KINDS[it.k].mp)
	var far := 0.0
	for it in pk.items:
		far = maxf(far, Vector2(it.x, it.y).distance_to(start))
	# (DEBUG LAND's start can be well off its middle, and its rings hang off
	# the edge: fewer there)
	var least := 20 if game.map_name == "debugland" else 30
	check(mp_ok and pk.items.size() >= least and pk.items.size() <= 46, "a match lays its rings, only what its guns use (%d)" % pk.items.size())
	check(far < Pickups.RING2 + 800.0, "all within the arena (%.0f m out at most)" % (far / 32.0))
	var heavies := pk.items.filter(func(it): return Pickups.KINDS[it.k].key == "armor_big").size()
	check(heavies >= 1 and heavies <= 2, "two heavy armours to fight over (%d)" % heavies)
	pk.place(game.seed, game.roads, false)

## the nearest up item of a kind to (x, y) — or, with none of that kind
## lying about (a seed can lay no medkit on an island with no herds),
## one laid by hand a few metres off the start
func _find(pk: Pickups, key: String, from := Vector2.ZERO) -> Dictionary:
	var best := {}
	var bd := INF
	for it in pk.items:
		if it.up and Pickups.KINDS[it.k].key == key:
			var d := Vector2(it.x, it.y).distance_to(from)
			if d < bd:
				bd = d
				best = it
	if best.is_empty():
		var s := _start()
		for k in 24:
			var q := s + Vector2.RIGHT.rotated(k * TAU / 24.0) * (320.0 + 40.0 * k)
			if game.level.on_land(q.x, q.y, 32.0):
				pk._put(Pickups.kind_of(key), q)
				pk._dirty = true
				return pk.items[-1]
	return best

func _stand_on(p: Player, it: Dictionary) -> void:
	p.x = it.x
	p.y = it.y
	p.z = game.level.floor_at(p.x, p.y)
	p.momx = 0.0
	p.momy = 0.0

func _away(p: Player) -> void:
	var s := _start()
	p.x = s.x
	p.y = s.y
	p.z = game.level.floor_at(p.x, p.y)

# ---- taking -----------------------------------------------------------------

func _taking(p: Player, pk: Pickups) -> void:
	p.debug = false
	p.cheat = false
	# A MEDKIT, hurt: taken
	p.health = 50
	var med := _find(pk, "health")
	var s0 := pk.serial
	_stand_on(p, med)
	_tics(2)
	var h: Array = Pickups.KINDS[Pickups.kind_of("health")].health
	check(not med.up and p.health == 50 + int(h[0]), "a medkit walked over is taken (+%d: %d)" % [h[0], p.health])
	check(pk.serial > s0 and p.bonus_flash > 0 and p.got.size() > 0, "and the gold flash, and it is counted taken")
	check(game.toasts.size() > 0 and str(game.toasts[-1].text).begins_with("MEDKIT"), "and said (%s)" % (game.toasts[-1].text if game.toasts.size() else ""))
	# WHOLE: a medkit is left where it lies
	p.health = Weapons.HEALTH
	var med2 := _find(pk, "health", Vector2(p.x, p.y))
	_stand_on(p, med2)
	_tics(2)
	check(med2.up and p.health == Weapons.HEALTH, "whole, a medkit is left where it lies")
	# ARMOUR: light, then a blow takes its share
	p.armour = 0
	p.armour_class = 0
	var arm := _find(pk, "armor", Vector2(p.x, p.y))
	_stand_on(p, arm)
	_tics(2)
	var A: Array = Pickups.KINDS[Pickups.kind_of("armor")].armour
	check(not arm.up and p.armour == int(A[0]) and p.armour_class == 1, "light armour taken (%d, class %d)" % [p.armour, p.armour_class])
	_away(p)
	p.health = 100
	var a0 := p.armour
	p.damage(30.0, null, {"impact": true})
	var soak := int(floor(30.0 * Weapons.ARMOUR_SOAK[1] + 1e-4))
	check(p.armour == a0 - soak and p.health == 100 - (30 - soak), "a blow of 30: the armour takes %d, you %d (armour %d, health %d)" % [soak, 30 - soak, p.armour, p.health])
	# heavy: half
	p.armour = 0
	p.armour_class = 0
	pk.give(p, Pickups.kind_of("armor_big"))
	check(p.armour_class == 2 and p.armour > 0, "heavy armour (%d, class %d)" % [p.armour, p.armour_class])
	p.health = 100
	a0 = p.armour
	p.damage(40.0, null, {"impact": true})
	check(p.armour == a0 - 20 and p.health == 80, "heavy takes half a blow (armour %d, health %d)" % [p.armour, p.health])
	# and it runs out: the rest is yours
	p.armour = 5
	p.health = 100
	p.damage(40.0, null, {"impact": true})
	check(p.armour == 0 and p.armour_class == 0 and p.health == 65, "armour that runs out takes what it has (health %d)" % p.health)
	# AMMUNITION: into the tank, as far as it holds, and a dry latch let go
	p.ammo.rounds = 0
	p.dry.rounds = true
	var box := _find(pk, "small_ammo", Vector2(p.x, p.y))
	_stand_on(p, box)
	_tics(2)
	var R: int = Pickups.KINDS[Pickups.kind_of("small_ammo")].ammo.rounds
	check(not box.up and p.ammo.rounds == R and not p.dry.rounds, "a box of rounds: %d in the belt, and the latch let go" % p.ammo.rounds)
	p.ammo.rounds = Weapons.BELT
	var box2 := _find(pk, "small_ammo", Vector2(p.x, p.y))
	_stand_on(p, box2)
	_tics(2)
	check(box2.up and p.ammo.rounds == Weapons.BELT, "a full belt leaves a box lying")
	# ONLY FOR A GUN YOU CARRY: a battery with the rifle full is left lying
	# for a lance you do not have (a match's hands)
	var owned_was: Dictionary = p.owned.duplicate()
	p.owned = {"MINIGUN": true, "PLASMA": true}
	p.ammo.plasma = Weapons.PLASMA_CELLS
	p.ammo.cells = 0
	check(not pk.give(p, Pickups.kind_of("energy_ammo")) and p.ammo.cells == 0, "a battery is left lying when the rifle is full and no lance is carried")
	p.ammo.plasma = 0
	check(pk.give(p, Pickups.kind_of("energy_ammo")) and p.ammo.plasma > 0 and p.ammo.cells == 0, "and taken for the rifle alone when it has room")
	p.owned = owned_was
	# THE MINI NUKE: the potato cannon in your hands' list, and its nukes
	p.owned.POTATO = false
	p.ammo.potatoes = 0
	check(pk.give(p, Pickups.kind_of("mini_nuke_ammo")), "a mini nuke is taken")
	check(p.owned.get("POTATO", false) and p.ammo.potatoes > 0, "and hands you the potato cannon, loaded (%d)" % p.ammo.potatoes)
	p.owned.POTATO = false
	# OVER THE TOP: the trauma kit takes you past it, and it bleeds back
	p.health = 95
	pk.give(p, Pickups.kind_of("health_big"))
	var top: int = p.health
	check(top > Weapons.HEALTH, "the trauma kit takes you past %d (%d)" % [Weapons.HEALTH, top])
	_away(p)
	_tics(Weapons.OVERHEAL_EVERY * 4)
	check(p.health < top and p.health >= top - 5, "and over the top bleeds back, a point a second (%d to %d)" % [top, p.health])
	p.health = 100

# ---- finite --------------------------------------------------------------------

func _finite(p: Player) -> void:
	p.debug = false
	p.cheat = false
	_away(p)
	for k in Weapons.TANKS:
		p.ammo[k] = 1
	_tics(20 * 35)
	var still := true
	for k in Weapons.TANKS:
		if k in ["fuel", "co2"]:
			continue
		if p.ammo[k] != 1:
			still = false
	check(still, "twenty seconds on, no tank has filled itself (the tanks are finite)")
	check(p.ammo.co2 > 1, "save the extinguisher's (%d)" % p.ammo.co2)
	check(p.ammo.fuel > 1 and p.ammo.fuel <= Weapons.FUEL_FLOOR, "and the flamer's pilot fuel, no further than %d (%d)" % [Weapons.FUEL_FLOOR, p.ammo.fuel])
	p.ammo.fuel = Weapons.FUEL_FLOOR + 50
	_tics(200)
	check(p.ammo.fuel == Weapons.FUEL_FLOOR + 50, "and none past it")
	# a fresh life starts with Weapons.START, not full
	var fresh := Player.new(game, p.x, p.y, 0.0)
	check(fresh.ammo.rounds == Weapons.START.rounds and fresh.health == Weapons.START_HEALTH and fresh.armour == Weapons.START_ARMOUR,
		"a fresh life: %d rounds, %d health, %d armour" % [fresh.ammo.rounds, fresh.health, fresh.armour])
	check(not fresh.debug and not PauseMenu.DEFAULTS.debug, "and infinite ammo is off by default")
	for k in Weapons.TANKS:
		p.ammo[k] = int(Weapons.START.get(k, 0))

# ---- coming back -----------------------------------------------------------------

func _back(p: Player, pk: Pickups) -> void:
	var it := _find(pk, "small_ammo", Vector2(p.x, p.y))
	p.ammo.rounds = 0
	_stand_on(p, it)
	_tics(2)
	check(not it.up and it.back > game.tics, "a box taken alone comes back in %.0f s" % ((it.back - game.tics) / 35.0))
	# (stepped off it, five metres, near enough to see it)
	p.x = it.x + 160.0
	p.y = it.y
	it.back = game.tics + 3
	_tics(6)
	if int(game.island_spec.get("pickups", {}).get("respawn", 0)) > 0:
		check(it.up, "DEBUG LAND: back on its clock, seen or not")
	else:
		check(not it.up, "but not while you are near enough to see it")
		_away(p)
		if Vector2(p.x, p.y).distance_to(Vector2(it.x, it.y)) < Pickups.UNSEEN:
			p.x += Pickups.UNSEEN * 2.0
		_tics(40)
		check(it.up, "out of sight, it is back")
	# a big one alone does not come back
	var big := _find(pk, "armor_big", Vector2(p.x, p.y))
	if not big.is_empty():
		p.armour = 0
		_stand_on(p, big)
		_tics(2)
		if not game.island_spec.get("pickups", {}).has("respawn"):
			check(not big.up and big.back == -1, "the heavy armour, alone, is gone for good")
	_away(p)

# ---- an empty gun ----------------------------------------------------------------

func _empty(p: Player) -> void:
	p.debug = false
	p.cheat = false
	p.weapon = "PLASMA"
	p.pending_weapon = ""
	p.ammo.plasma = 0
	p.ammo.rounds = 200
	var t0: int = game.toasts.size()
	game._autofire = true
	_tics(4)
	game._autofire = false
	_tics(30)
	check(p.weapon == "MINIGUN", "the trigger on an empty rifle: the hands go to the minigun (%s)" % p.weapon)
	check(game.toasts.size() > 0 and str(game.toasts[-1].text).begins_with("NO PLASMA") or game.toasts.size() > t0, "and it is said")
	# the minigun with three rounds in it is empty (a volley is four)
	p.ammo.rounds = 3
	check(not p.has_ammo("MINIGUN"), "three rounds is an empty minigun")
	p.ammo.rounds = 200
	# the cycle passes the empty ones by
	p.ammo.bores = 0
	p.weapon = "EXTINGUISHER"
	p.pending_weapon = ""
	p.cycle_weapon(1)
	check(p.pending_weapon != "BORE", "the next gun passes the empty bore by (%s)" % p.pending_weapon)
	p.pending_weapon = ""

# ---- IDDQD ----------------------------------------------------------------------------

func _key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = true
	return e

func _btn(dev: int, b: int, down := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = dev
	e.button_index = b
	e.pressed = down
	return e

func _axis(dev: int, a: int, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = dev
	e.axis = a
	e.axis_value = v
	return e

func _type(keys: Array) -> void:
	for k in keys:
		game.cheat_input(_key(k))

func _cheat(p: Player) -> void:
	p.debug = false
	p.cheat = false
	_type([KEY_I, KEY_D, KEY_D, KEY_Q, KEY_X, KEY_D])
	check(not p.cheat, "a wrong letter in the middle: nothing")
	_type([KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D])
	check(p.cheat, "I D D Q D: on")
	check(str(game.toasts[-1].text) == "DEGREELESSNESS MODE ON", "and said (%s)" % game.toasts[-1].text)
	p.health = 100
	p.damage(1e6, null, {"impact": true, "shot": true})
	check(not p.dead and p.health == 100, "invincible: a blow of a million does nothing")
	_away(p)
	p.weapon = "MINIGUN"
	p.pending_weapon = ""
	p.ammo.rounds = 10
	game._autofire = true
	_tics(60)
	game._autofire = false
	_tics(30)
	check(p.ammo.rounds == Weapons.BELT and p.shots_fired > 0, "and infinite ammo: the minigun fired and the belt is full (%d)" % p.ammo.rounds)
	_type([KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D])
	check(not p.cheat, "typed again: off")
	# too slow between letters: nothing
	var c := Cheats.new()
	var got := false
	var t := 1000
	for k in [KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D]:
		got = c.feed(_key(k), t) or got
		t += 4000
	check(not got, "a letter every four seconds is not typing it")
	# THE SQUEEZE: L1 R1 L2 R2 L3 R3 together on a pad
	var dev := 3
	var evs := [_btn(dev, JOY_BUTTON_LEFT_SHOULDER), _btn(dev, JOY_BUTTON_RIGHT_SHOULDER), _axis(dev, JOY_AXIS_TRIGGER_LEFT, 0.9),
		_axis(dev, JOY_AXIS_TRIGGER_RIGHT, 0.9), _btn(dev, JOY_BUTTON_LEFT_STICK)]
	for e in evs:
		game.cheat_input(e)
	check(not p.cheat and game.cheats.chording(dev), "five of the six: not yet, and both bumpers down is a squeeze under way")
	# (jump and fire held, the triggers, is play and not a squeeze)
	var c3 := Cheats.new()
	c3.feed(_axis(7, JOY_AXIS_TRIGGER_LEFT, 0.9))
	c3.feed(_axis(7, JOY_AXIS_TRIGGER_RIGHT, 0.9))
	check(not c3.chording(7), "jumping and firing at once is not a squeeze (R3 still slows the world)")
	game.cheat_input(_btn(dev, JOY_BUTTON_RIGHT_STICK))
	check(p.cheat, "all six: on")
	game.cheat_input(_axis(dev, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	check(p.cheat, "and held, it stays on (once a squeeze)")
	game.cheat_input(_btn(dev, JOY_BUTTON_RIGHT_STICK, false))
	game.cheat_input(_btn(dev, JOY_BUTTON_RIGHT_STICK))
	check(not p.cheat, "let go of one and squeezed again: off")
	# ANDROID's forms: the triggers as buttons
	var c2 := Cheats.new()
	var on := false
	for b in [9, 10, 15, 16, 7]:
		on = c2.feed(_btn(5, b)) or on
	on = c2.feed(_btn(5, 8)) or on
	check(on, "the triggers as Android's buttons 15 and 16 do it too")
	# NOT IN A MATCH
	game.rules = RefCounted.new()
	_type([KEY_I, KEY_D, KEY_D, KEY_Q, KEY_D])
	game.rules = null
	check(not p.cheat and str(game.toasts[-1].text) == "NO CHEATS IN A MATCH", "in a match: refused")

# ---- a match's life ---------------------------------------------------------------

func _match(p: Player) -> void:
	var q := Player.new(game, p.x, p.y, 0.0)
	q.cheat = true
	NetMatch.renew(q, p.x, p.y, 0.0, NetMatch.RULES)
	var R: Dictionary = NetMatch.RULES
	check(q.health == int(R.health) and q.armour == int(R.armour) and q.ammo.rounds == int(R.spawnAmmo.rounds),
		"a match's life: %d health, %d armour, %d rounds" % [q.health, q.armour, q.ammo.rounds])
	check(q.ammo.plasma == int(R.spawnAmmo.get("plasma", 0)) and q.ammo.rockets == 0 and not q.cheat and not q.debug,
		"and nothing else, and no cheat")
	check(not R.infiniteAmmo, "and a match's tanks run dry")

# ---- a match's clock, its sudden death, and what hurts whom --------------------------

func _clock(p: Player) -> void:
	var m := NetMatch.new(game, {"timeLimit": 70, "overtime": 70})
	var q := Player.new(game, p.x + 200.0, p.y, 0.0)
	p.id = 1
	p.name = "PEE"
	q.id = 2
	q.name = "CUE"
	p.dead = false
	game.players = [p, q]
	p.frags = 3
	q.frags = 3
	for i in 75:
		game.tics += 1
		m.tic()
	check(m.over == null and m.overtime() and m.tied() and m.time_left() == 0, "level on frags at the clock: sudden death, not over")
	m.died(q, p)
	check(m.over != null and str(m.over.winner) == "PEE", "and the next frag ends it (%s)" % str(m.over))
	# a clear leader at the clock wins on it
	var m2 := NetMatch.new(game, {"timeLimit": 70, "overtime": 70})
	m2.over = null
	p.frags = 5
	q.frags = 2
	q.dead = false
	for i in 72:
		game.tics += 1
		m2.tic()
	check(m2.over != null and str(m2.over.winner) == "PEE", "a clear leader at the clock wins on it")
	# WHAT HURTS WHOM: a round, a bolt, a beast
	p.weapon = "MINIGUN"
	var r := m2.scale(p, q, 100.0)
	p.weapon = "PLASMA"
	var b := m2.scale(p, q, 100.0)
	var u := Actor.new(game, "UNICORN", p.x, p.y, 0.0)
	var n := m2.scale(u, q, 100.0)
	check(is_equal_approx(r, 100.0 * NetMatch.RULES.pvpScale) and is_equal_approx(b, 100.0 * NetMatch.RULES.plasmaPvpScale)
		and is_equal_approx(n, 100.0 * NetMatch.RULES.npcScale), "a round %.0f%%, a bolt %.0f%%, a unicorn %.0f%% to a player" % [r, b, n])
	# three bolts always kill a fresh body, two never do
	var lo := 110.0 * NetMatch.RULES.plasmaPvpScale
	var hi := 150.0 * NetMatch.RULES.plasmaPvpScale
	check(lo * 3.0 >= 100.0 and hi * 2.0 < 100.0, "three bolts always kill a fresh body (%.1f), two never (%.1f)" % [lo * 3.0, hi * 2.0])
	game.rules = null
	game.players = [p]
