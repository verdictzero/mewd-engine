## MEWD — the player's body (js/player.js: turn, move).
##
## Doom's movement, per 35 Hz tic: a push along the facing, friction of
## 0.90625, a dead zone; the level's slide against its lines; the floor
## snapped to within a step (24) and anything deeper a fall on a unit of
## gravity a tic; a jump of 9; the eye lagging the feet so a kerb is a
## lurch and not a teleport; Doom's view bob, the square of the speed.
class_name Player
extends RefCounted

const GRAVITY := 1.0
const JUMP_VEL := 9.0
const FRICTION := 0.90625
const WALK_FWD := 25.0 / 32.0
const RUN_FWD := 50.0 / 32.0
const WALK_SIDE := 24.0 / 32.0
const RUN_SIDE := 40.0 / 32.0
const STOP_SPEED := 0.06
const MAX_PITCH := 0.72


var game
## WHO THIS IS, when there is more than one of you — see
## godot/scripts/net/match.gd. A game on its own leaves all of these alone.
var id := 0
var name := "PLAYER"
var team := -1
var frags := 0
var deaths := 0
## where this player's commands come from: null for the game's own
## (Game.session), a NetSession.Host on a host
var session = null
var ping := 0
## lives had, and the match's clocks: when a dead one comes back, and
## until when a fresh one is untouchable (host); how long until the host
## brings you back (a client, off the snapshot)
var spawns := 0
var respawn_at := 0
var guard_until := 0
var respawn_in := 0
## the guns this player may pick up — every one alone; the match's
## loadout on a network (js/player.js `owned`)
var owned := {"FLAMER": true, "EXTINGUISHER": true, "BORE": true, "MINIGUN": true, "LANCE": true, "LAUNCHER": true, "ARC": true, "POTATO": true}
var x := 0.0
var y := 0.0
var z := 0.0
var angle := 0.0
var pitch := 0.0
var momx := 0.0
var momy := 0.0
var momz := 0.0
var on_ground := true
var radius := U.PLAYER_RADIUS
var height := U.PLAYER_HEIGHT
var view_z := 0.0
var bob := 0.0
var bob_phase := 0.0
var sector: Level.Sector = null
var health := Weapons.HEALTH
var armour1 := Weapons.ARMOUR1
var armour2 := Weapons.ARMOUR2
var dead := false
## BOTH DEBUG SWITCHES ON BY DEFAULT, at the user's request (js/main.js
## DEFAULT_PREFS): infinite ammo and invincibility, until the pause menu
## says otherwise
var debug := true
var invincible := true
var removed := false
var shootable := true
var info := {}
var damage_flash := 0

## THE GUNS: what is in hand, what is coming, and where the firing
## frames are (-1 not firing)
var weapon := "FLAMER"
var pending_weapon := ""
var fire_index := -1
var fire_tics := 0
var ammo := {}
var ammo_tick := {}
var dry := {}
var spin := 0.0
var heat := 0.0
var shots_fired := 0
## the launcher: the trigger is down and the seeker is looking; and the
## one refusal that is heard, once per press
var seeking := false
var clicked := false
## the arc maw: winding, and how far (0..1)
var arc_charging := false
var arc_charge := 0.0
## THE LANCE'S NUMBERS (js/player.js), STATES and not animations, so a
## pause holds them where they are. The gun's screen (Scope) draws the
## first two and the beam (BeamSystem) lives off the third.
##   charge      tics of trigger held, 0..CHARGE_MAX
##   hold        tics spent sitting at the top of it, 0..HOLD_TICS,
##               after which the coil vents
##   beam_tics   tics of beam still out, and beam_stage which one
var charge := 0
var hold := 0
var beam_tics := 0
var beam_stage := 0
## whether the coil has already let go on this press of the trigger
var vented := false
## the held charge sound and which of the two it is — see lance_voice
var charge_loop = null
var _charge_voice := ""

## where the body was at the start of this tic, for the frame to draw
## between the two
var prev := Vector4()

func _init(g, sx: float, sy: float, a: float, sz = null) -> void:
	game = g
	x = sx
	y = sy
	angle = a
	sector = g.level.sector_at(x, y)
	# A START ON AN UPPER LAYER of an edited map: in the storey at its
	# height, not the ground under it — a hair over the deck
	if sz != null and sector != null:
		sector = g.level.span_in(sector, float(sz) + 1.0)
	z = sector.floor if sector else 0.0
	view_z = z + U.PLAYER_EYE
	prev = Vector4(x, y, view_z, 0)
	for k in Weapons.TANKS:
		ammo[k] = Weapons.TANKS[k][0]
		ammo_tick[k] = 0
		dry[k] = false

func eye_z() -> float:
	return view_z

## One tic of a command: {fwd, side (-1..1), run, jump, look (Vector2, radians)}
func tic(cmd: Dictionary) -> void:
	prev = Vector4(x, y, view_z, 0)
	if damage_flash > 0:
		damage_flash -= 1
	if dead:
		death_tic()
		return
	turn(cmd.look)
	move(cmd)
	weapon_tic(cmd)
	fuel_tic()

var look_rate := 0.0
var pitch_rate := 0.0

func turn(look: Vector2) -> void:
	angle = U.angle_norm(angle - look.x)
	pitch = clampf(pitch - look.y, -MAX_PITCH, MAX_PITCH)
	look_rate += (look.x - look_rate) * 0.3
	pitch_rate += (look.y - pitch_rate) * 0.3

func move(cmd: Dictionary) -> void:
	# THE LANCE DECIDES WHETHER YOU ARE WALKING AT ALL, the one place a
	# weapon reaches into the legs (js/player.js move). While the beam is
	# out, nothing — the momentum already went in fire_beam — so the
	# discharge is fired from exactly where you stood: a line drawn
	# through a town is a thing you commit to a position for. While the
	# coil is winding, a third of a walk and no running (CHARGE_WALK).
	var braced := beam_tics > 0
	var grip := 0.0 if braced else (Weapons.CHARGE_WALK if charge > 0 else 1.0)
	var run: bool = cmd.run and not braced and charge == 0
	var fwd: float = (RUN_FWD if run else WALK_FWD) * cmd.fwd * grip
	var side: float = (RUN_SIDE if run else WALK_SIDE) * cmd.side * grip
	var c := cos(angle)
	var s := sin(angle)
	momx += c * fwd + s * side
	momy += s * fwd - c * side
	momx *= FRICTION
	momy *= FRICTION
	if absf(momx) < STOP_SPEED:
		momx = 0.0
	if absf(momy) < STOP_SPEED:
		momy = 0.0

	var lv: Level = game.level
	if momx != 0.0 or momy != 0.0:
		var r := lv.slide_move(x, y, momx, momy, radius, z, height, false)
		var nx := r.x
		var ny := r.y
		# trees stop you too, and you slide round them the way you slide
		# along a wall: the whole move, then each axis alone
		var F = game.forest
		# (the trees stand on the ground: upstairs, over them, nothing)
		if lv.layered and sector != null and sector.storey > 0:
			F = null
		if F != null and F.blocks(nx, ny, radius):
			if not F.blocks(nx, y, radius):
				ny = y
			elif not F.blocks(x, ny, radius):
				nx = x
			else:
				nx = x
				ny = y
		var blocked = game.thing_in_way(self, nx, ny)
		if blocked == null:
			x = nx
			y = ny
		else:
			momx *= 0.2
			momy *= 0.2
		if F != null:
			F.clamp_inside(self)

	var sec := lv.sector_at(x, y, sector)
	if sec:
		# WHICH STOREY YOU ARE ON: standing, the highest floor a step or
		# less over your feet; in the air, the one your height is in
		sector = sec if sec.above == -1 else (lv.stand_in(sec, z) if on_ground else lv.span_in(sec, z))
	var floor := sector.floor if sector else z
	var ceil := sector.ceil if sector else INF

	if on_ground and cmd.jump:
		momz = JUMP_VEL
		on_ground = false
	if on_ground and floor < z - U.MAX_STEP:
		on_ground = false
	if on_ground:
		z = floor
		momz = 0.0
	else:
		momz -= GRAVITY
		z += momz
		if z + height > ceil:
			z = maxf(floor, ceil - height)
			if momz > 0.0:
				momz = 0.0
		if z <= floor:
			var fall := -momz
			z = floor
			momz = 0.0
			on_ground = true
			if fall > 4.0:
				view_z -= minf(12.0, fall * 0.7)

	var speed2 := momx * momx + momy * momy
	var target_bob := minf(16.0, speed2 * 0.32)
	bob += (target_bob - bob) * 0.25
	if on_ground:
		bob_phase += 0.19
	var eye := z + U.PLAYER_EYE + sin(bob_phase) * bob * 0.5
	view_z += (eye - view_z) * 0.45

# ------------------------------------------------------------------
# THE GUNS (js/player.js weaponTic and what it calls)
# ------------------------------------------------------------------

func def() -> Dictionary:
	return Weapons.WEAPONS[weapon]

func firing() -> bool:
	return fire_index >= 0

func has_ammo(w: String) -> bool:
	var d: Dictionary = Weapons.WEAPONS[w]
	return not d.has("ammo") or ammo[d.ammo] >= maxi(1, int(d.get("ammoPerShot", 1)))

func latched(w: String) -> bool:
	var d: Dictionary = Weapons.WEAPONS[w]
	return d.has("ammo") and dry.get(d.ammo, false)

## Whether it will actually go off: ammo, not latched dry, and a gun that
## has to spin up is not armed until it has.
func armed(w: String) -> bool:
	var d: Dictionary = Weapons.WEAPONS[w]
	if not has_ammo(w) or (d.has("refire") and latched(w)):
		return false
	if d.get("lock", false) and (game.bore == null or game.bore.lock == null):
		return false
	if d.get("volley", false) and spin < 1.0:
		return false
	# AND A LANCE WILL NOT TAKE THE TRIGGER WHILE ITS OWN BEAM IS OUT, or
	# you could hold it through your own discharge and start the next
	# seven seconds inside the last shot
	if d.get("charge", false) and beam_tics > 0:
		return false
	return true

func select_slot(n: int) -> void:
	for k in Weapons.ORDER:
		if Weapons.WEAPONS[k].slot == n and owned.get(k, false):
			if k != weapon:
				pending_weapon = k
			return

func cycle_weapon(dir: int) -> void:
	var list := []
	for k in Weapons.ORDER:
		if owned.get(k, false):
			list.append(k)
	if list.is_empty():
		return
	var i := list.find(weapon)
	pending_weapon = list[((i + dir) % list.size() + list.size()) % list.size()]

func weapon_tic(cmd: Dictionary) -> void:
	if cmd.get("slot", 0) > 0:
		select_slot(cmd.slot)
	if cmd.get("cycle", 0) != 0:
		cycle_weapon(1 if cmd.cycle > 0 else -1)
	var attack: bool = cmd.get("attack", false)
	spin_tic(attack)
	_weapon_tic(attack)
	# the lance's held sound, judged from the state AFTER the tic
	lance_voice()

func _weapon_tic(attack: bool) -> void:
	var d := def()
	# A CHARGED WEAPON DOES NOT RUN ON fire_index: its question is "how
	# long has the trigger been down", which is not an animation
	if d.get("charge", false):
		lance_tic(attack)
		return
	# the other weapons that do not run on frames have their own tics
	for special in ["seeker", "arc", "potato"]:
		if d.get(special, false):
			var sys = game.weapon_system(special)
			if sys != null:
				sys.player_tic(self, attack)
			elif pending_weapon != "":
				weapon = pending_weapon
				pending_weapon = ""
			return
	if firing():
		if d.has("stream") and game.flame != null:
			game.flame.stream_tic(self, d)
		if d.get("volley", false):
			volley_tic(d)
		fire_tics -= 1
		if fire_tics > 0:
			return
		fire_index += 1
		var ft: Array = d.fireTics
		if fire_index >= ft.size():
			fire_index = -1
			if d.get("autofire", false) and attack and armed(weapon):
				start_fire()
			return
		fire_tics = ft[mini(fire_index, ft.size() - 1)]
		return
	if pending_weapon != "":
		weapon = pending_weapon
		pending_weapon = ""
		return
	if attack and armed(weapon):
		start_fire()

func start_fire() -> void:
	var d := def()
	if d.has("ammo"):
		ammo[d.ammo] = maxi(0, ammo[d.ammo] - int(d.get("ammoPerShot", 1)))
	shots_fired += 1
	fire_index = 0
	fire_tics = d.fireTics[0]
	game.play_sound(d.get("sound"), self)
	if d.get("lock", false) and game.bore != null:
		game.bore.fire(self)
	game.noise(self, 900.0 if d.get("autofire", false) else 700.0)

## The barrels winding up and down, and how hot they are.
func spin_tic(attack: bool) -> void:
	var d := def()
	var want: bool = d.get("volley", false) and attack and not latched(weapon) and has_ammo(weapon)
	var was := spin
	spin = clampf(spin + (1.0 / Weapons.SPIN_UP if want else -1.0 / Weapons.SPIN_DOWN), 0.0, 1.0)
	if want and was == 0.0:
		game.play_sound("spinup", self)
	if not want and was == 1.0:
		game.play_sound("spindown", self)
	var rounds_out: bool = firing() and d.get("volley", false)
	heat = clampf(heat + (1.0 / Weapons.HEAT_UP if rounds_out else -1.0 / Weapons.HEAT_DOWN), 0.0, 1.0)

## The minigun: one tic of rounds, where the eye is looking with a
## little scatter, every other one a tracer.
func volley_tic(d: Dictionary) -> void:
	var rounds: int = d.rounds
	if ammo[d.ammo] < rounds:
		fire_index = -1
		dry[d.ammo] = true
		return
	ammo[d.ammo] -= rounds
	var from: Vector3 = game.nozzle(self)
	# (the streak from the barrels as they are drawn, on this machine)
	var seen: Vector3 = game.muzzle_view(self, from) if game.has_method("muzzle_view") else from
	for i in rounds:
		var a: float = angle + (U.p_random() / 255.0 - 0.5) * 2.0 * d.spread
		var pt: float = pitch + (U.p_random() / 255.0 - 0.5) * 2.0 * d.spread * 0.7
		game.hitscan(self, a, 2400.0, Weapons.minigun_damage(), {"shot": true, "hot": true, "pitch": pt, "from": from})
		if (i & 1) == 0 and game.tracers != null:
			game.tracers.spawn(seen, game.last_hit)

func fuel_tic() -> void:
	if debug:
		for k in Weapons.TANKS:
			ammo[k] = Weapons.TANKS[k][0]
			dry[k] = false
			ammo_tick[k] = 0
		return
	for k in Weapons.TANKS:
		var t: Array = Weapons.TANKS[k]
		var cap: int = t[0]
		if ammo[k] >= cap:
			ammo_tick[k] = 0
			dry[k] = false
			continue
		ammo_tick[k] += 1
		if ammo_tick[k] < t[1]:
			continue
		ammo_tick[k] = 0
		ammo[k] = mini(cap, ammo[k] + 1)
		if dry[k] and ammo[k] >= cap * t[2]:
			dry[k] = false

# ------------------------------------------------------------------
# THE POSITRON LANCE (js/player.js lanceTic, fireBeam, ventCharge,
# lanceVoice), and it is a different KIND of trigger: every other weapon
# answers the trigger going down; this one answers it coming UP, and what
# it does depends on how long you held it — three seconds is a stage,
# five is two, seven is three. A release and not a timer, so the player
# picks the moment and the gun can be CANCELLED. And at the user's
# request it will not fire until the dial is RED (FIRE_AT, the third
# stage): a trigger released under it vents, spends nothing and leaves
# the gun warm. The beam itself is BeamSystem's, handed over by
# game.weapon_system("charge").
# ------------------------------------------------------------------

const CHARGE_MAX := 7 * Weapons.TICRATE          # the last of CHARGE_STAGES
## the stage the trigger will give you a shot at — the top one
const FIRE_AT := 3
## how long the column stays out, by stage, in tics (BEAM_SECONDS)
const BEAM_TICS := [21, 32, 49]
## HOW LONG YOU MAY STAND AT FULL CHARGE before the coil VENTS by itself:
## five seconds, enough to wait for the shot, not enough to go looking
const HOLD_TICS := 5 * Weapons.TICRATE
## THE PITCH THE CHARGE RIDES, as playback rates: every charge clip is on
## this one curve, so the start, the loop and the whine are one sound
const CHARGE_PITCH := [0.72, 1.45]

func _beam():
	return game.weapon_system("charge") if game.has_method("weapon_system") else null

func _snd():
	return game.get("sound")

## THE LANCE, which is three states and not a list of frames:
##   out      the beam is live: it counts down, and nothing else can
##            happen until it stops
##   winding  the trigger is down and the charge is climbing
##   idle     everything else, which is where a release is noticed
## The beam is checked first, or the seven seconds would overlap the shot.
func lance_tic(attack: bool) -> void:
	var beam = _beam()
	# ---- out
	if beam_tics > 0:
		beam_tics -= 1
		# `firing` is what the gun's kick reads, so it is true for exactly
		# as long as the beam is
		fire_index = 1 if beam_tics > 0 else -1
		if beam != null:
			beam.tic(self)
		if beam_tics == 0:
			beam_stage = 0
			if beam != null:
				beam.stop()
		return
	# ---- idle
	fire_index = -1
	if charge == 0:
		hold = 0
	# ---- winding. You need to be armed to BEGIN; after that a cell.
	var can := has_ammo(weapon) if charge > 0 else armed(weapon)
	# A TRIGGER HELD THROUGH A VENT DOES NOT START ANOTHER CHARGE: it
	# takes releasing and pressing again
	if not attack:
		vented = false
	if attack and can and not vented:
		if charge == 0:
			hold = 0
			game.play_sound("lancestart", self)
		charge = mini(CHARGE_MAX, charge + 1)
		# AND AT THE TOP THERE IS A WINDOW, and at the end of it the coil
		# vents and you start the seven seconds again
		if charge >= CHARGE_MAX:
			hold += 1
			if hold >= HOLD_TICS:
				vent_charge()
		return
	# ---- the trigger came up
	if charge > 0:
		var st := charge_stage()
		# ANYTHING SHORT OF RED IS A VENT AND NOT A SHOT
		if st >= FIRE_AT:
			charge = 0
			hold = 0
			fire_beam(st)
		else:
			vent_charge()
		return
	# only swap weapons when the coil is idle, never mid-charge
	if pending_weapon != "":
		weapon = pending_weapon
		pending_weapon = ""

## One cell, one line drawn through the map. The stage decides how wide
## and for how long; BeamSystem decides everything else.
func fire_beam(st: int) -> void:
	var d := def()
	if d.has("ammo"):
		ammo[d.ammo] = maxi(0, ammo[d.ammo] - int(d.get("ammoPerShot", 1)))
		if ammo[d.ammo] <= 0:
			dry[d.ammo] = true
	shots_fired += 1
	beam_stage = st
	beam_tics = BEAM_TICS[st - 1]
	fire_index = 1
	# BRACED: the momentum goes now, so you stop where you are standing
	# instead of sliding to a halt under a beam that is already out
	momx = 0.0
	momy = 0.0
	# THE DISCHARGE IS THREE RECORDINGS AT ONCE: the transient at the
	# pitch the coil had reached, and the two layers of the shot, a bigger
	# stage being LOWER and longer
	var snd = _snd()
	if snd != null:
		var p: float = CHARGE_PITCH[0] + (CHARGE_PITCH[1] - CHARGE_PITCH[0]) * (float(st) / Weapons.CHARGE_STAGES.size())
		snd.play("lanceprefire", self, {"rate": p})
		var boom := 1.14 - 0.13 * st
		snd.play("lancefire", self, {"rate": boom})
		snd.play("lancefire2", self, {"rate": boom})
	var beam = _beam()
	if beam != null:
		beam.fire(self, st)
	# AND WHO HEARD IT: the loudest single shot in the game, but not the
	# whole town to the window every time you take one man off a roof
	game.noise(self, 1100.0)

## A CHARGE THAT NEVER BECAME A SHOT: the trigger came up before red, or
## stayed down past the window. Nothing is spent; what is left is the
## charge loop played once from wherever the pitch had got to, sliding
## down and away.
func vent_charge() -> void:
	var pitch := charge_pitch()
	charge = 0
	hold = 0
	vented = true
	var snd = _snd()
	if snd != null:
		snd.play("lancecharge", self, {"rate": pitch * 0.8})
	if game.has_method("toast"):
		game.toast("COIL VENTED")

## THE LANCE'S HELD SOUND, and which of the two it is: the loop while it
## is filling and the stage-three whine from the third mark. Judged from
## the state AFTER the tic, so every way of ending a charge — the shot,
## the vent, the swap, dying — stops it through this one function.
func lance_voice() -> void:
	var winding: bool = def().get("charge", false) and charge > 0 and beam_tics == 0 and not dead
	var want := ""
	if winding:
		want = "lancecharge3" if charge_stage() >= Weapons.CHARGE_STAGES.size() else "lancecharge"
	if want != _charge_voice:
		if charge_loop != null:
			charge_loop.stop()
		charge_loop = null
		var snd = _snd()
		if want != "" and snd != null:
			charge_loop = snd.loop(want, self)
		_charge_voice = want
	# and the pitch rides the charge, every tic
	if charge_loop != null and winding:
		charge_loop.rate(charge_pitch(), 0.08)

## HOW MUCH OF THE WINDOW AT THE TOP IS LEFT, 1 the moment the dial goes
## red and 0 as the coil vents — REMAINING rather than elapsed, because a
## sniper at full charge wants to know how long they have.
func hold_fraction() -> float:
	if charge < CHARGE_MAX or HOLD_TICS <= 0:
		return 0.0
	return maxf(0.0, 1.0 - float(hold) / HOLD_TICS)

## Where on the pitch curve the coil currently is.
func charge_pitch() -> float:
	return CHARGE_PITCH[0] + (CHARGE_PITCH[1] - CHARGE_PITCH[0]) * charge_fraction()

## Which of the three stages the charge has reached, 0 for none; while
## the beam is out, the stage that fired.
func charge_stage() -> int:
	if beam_tics > 0:
		return beam_stage
	var n := 0
	for sec in Weapons.CHARGE_STAGES:
		if charge >= sec * Weapons.TICRATE:
			n += 1
	return n

## How far round the dial the charge has come, 0..1.
func charge_fraction() -> float:
	if beam_tics > 0:
		return 1.0
	return float(charge) / CHARGE_MAX

## Where the three stage marks fall on that dial, for the scope.
func stage_marks() -> Array:
	var out := []
	for sec in Weapons.CHARGE_STAGES:
		out.append(float(sec * Weapons.TICRATE) / CHARGE_MAX)
	return out

# ------------------------------------------------------------------
# HURT (js/player.js damage, die, deathTic)
# ------------------------------------------------------------------

## The plates go first — the outer, then the inner — and then you. The
## player is FIREPROOF: only a round or a blow gets through.
func damage(amount: float, source, opts := {}) -> void:
	if dead or invincible:
		return
	if not opts.get("shot", false) and not opts.get("impact", false):
		return
	var left := amount
	var take := minf(armour2, left)
	armour2 -= int(take)
	left -= take
	take = minf(armour1, left)
	armour1 -= int(take)
	left -= take
	health -= int(left)
	damage_flash = mini(16, int(5 + amount * 0.6))
	game.play_sound("hurt", self)
	if source != null:
		var a := atan2(y - source.y, x - source.x)
		var push := minf(6.0, amount * 0.22)
		momx += cos(a) * push
		momy += sin(a) * push
	if health <= 0:
		die(source)

func die(source = null) -> void:
	dead = true
	health = 0
	armour1 = 0
	armour2 = 0
	if charge_loop != null:
		charge_loop.stop()
		charge_loop = null
	_charge_voice = ""
	charge = 0
	beam_tics = 0
	seeking = false
	if self == game.player and game.get("beam") != null:
		game.beam.stop()
	game.play_sound("playerDie", self)
	game.on_player_died(self, source)

func death_tic() -> void:
	view_z += (z + 8.0 - view_z) * 0.12
	momx *= 0.86
	momy *= 0.86
