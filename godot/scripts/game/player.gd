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

## where the body was at the start of this tic, for the frame to draw
## between the two
var prev := Vector4()

func _init(g, sx: float, sy: float, a: float) -> void:
	game = g
	x = sx
	y = sy
	angle = a
	sector = g.level.sector_at(x, y)
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

func turn(look: Vector2) -> void:
	angle = U.angle_norm(angle - look.x)
	pitch = clampf(pitch - look.y, -MAX_PITCH, MAX_PITCH)

func move(cmd: Dictionary) -> void:
	var run: bool = cmd.run
	var fwd: float = (RUN_FWD if run else WALK_FWD) * cmd.fwd
	var side: float = (RUN_SIDE if run else WALK_SIDE) * cmd.side
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
		var blocked = game.thing_in_way(self, r.x, r.y)
		if blocked == null:
			x = r.x
			y = r.y
		else:
			momx *= 0.2
			momy *= 0.2

	var sec := lv.sector_at(x, y, sector)
	if sec:
		sector = sec
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
	return true

func select_slot(n: int) -> void:
	for k in Weapons.ORDER:
		if Weapons.WEAPONS[k].slot == n:
			if k != weapon:
				pending_weapon = k
			return

func cycle_weapon(dir: int) -> void:
	var i := Weapons.ORDER.find(weapon)
	pending_weapon = Weapons.ORDER[(i + dir + Weapons.ORDER.size()) % Weapons.ORDER.size()]

func weapon_tic(cmd: Dictionary) -> void:
	if cmd.get("slot", 0) > 0:
		select_slot(cmd.slot)
	if cmd.get("cycle", 0) != 0:
		cycle_weapon(1 if cmd.cycle > 0 else -1)
	var attack: bool = cmd.get("attack", false)
	spin_tic(attack)
	var d := def()
	# the weapons that do not run on frames have their own tics
	for special in ["charge", "seeker", "arc"]:
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
	for i in rounds:
		var a: float = angle + (U.p_random() / 255.0 - 0.5) * 2.0 * d.spread
		var pt: float = pitch + (U.p_random() / 255.0 - 0.5) * 2.0 * d.spread * 0.7
		game.hitscan(self, a, 2400.0, Weapons.minigun_damage(), {"shot": true, "hot": true, "pitch": pt, "from": from})
		if (i & 1) == 0 and game.tracers != null:
			game.tracers.spawn(from, game.last_hit)

func fuel_tic() -> void:
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
# HURT (js/player.js damage, die, deathTic)
# ------------------------------------------------------------------

## The plates go first — the outer, then the inner — and then you. The
## player is FIREPROOF: only a round or a blow gets through.
func damage(amount: float, source, opts := {}) -> void:
	if dead:
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
	game.play_sound("playerDie", self)
	game.on_player_died(self, source)

func death_tic() -> void:
	view_z += (z + 8.0 - view_z) * 0.12
	momx *= 0.86
	momy *= 0.86
