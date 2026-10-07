## MEWD — the game's side of a network client.
##
## A NetGame takes a Game built for the map the host named and a NetClient
## already welcomed, and from then on this machine is ONE PLAYER IN
## SOMEBODY ELSE'S WORLD. Three jobs, the three every network shooter
## since QuakeWorld has had to do:
##
## 1. PREDICT YOURSELF. Your own player moves the moment you press, run by
##    this machine's own Game from the same commands the host is sent
##    (Session). When a snapshot arrives it says where the host has you as
##    of the last command it got to (`ack`), and you are put THERE and
##    every command sent since is run over the top again (reconcile). Both
##    ends run the same rounded commands (ticcmd.gd), so almost always that
##    lands where you already were; when it doesn't, you slide to the
##    truth, or jump to it if it is far.
##
##    THE HOST IS THE ONLY ONE WHO CAN HURT YOU. Your player here is
##    invincible and its health is whatever the snapshot says; you die when
##    the host says you did, and come back where it put you.
##
## 2. DRAW THE OTHERS IN THE PAST. Everybody else arrives twelve times a
##    second, so they are drawn INTERP_TICS behind the newest snapshot,
##    sliding between the two either side of that moment. Each is a PUPPET:
##    a trooper off the sheets (SWAT for one side, the army for the other),
##    an Actor with no mind of its own, walked, turned, fired and dropped by
##    this file. How far back they are drawn goes to the host in every
##    command (`seen`), which lets it wind the world back for your shot.
##
## 3. SAY WHAT IS GOING ON. The kills go up as toasts, the end of a round
##    as the big card, and the score is a line at the top of the screen
##    and a table while TAB is held (Hud draws board_lines()).
##
## 4. THE DROP: every life begins in a pod (NetMatch.spawn). The host says
##    where it was aimed and the tic it began on, and this machine flies
##    the same pod itself — its own player's, and everybody else's, drawn
##    coming down — since a pod with nobody's hands on it is the same sum
##    everywhere (DropPod: the RCS off, straight down).
##
## 5. THE HERDS are the host's (they kill): four times a second it says
##    where the unicorns near this player are, and what they are doing;
##    here they are puppets, slid between those, their beams drawn and
##    hurting nobody (the host's beam hurts). A death in the herd is an
##    event, and she goes to pieces here too.
##
## WHAT IS NOT SHARED is the rest of the world: the candy girls (every
## machine's own, from the same seed), a fire, the gore. The players, the
## herds and the score are the host's.
class_name NetGame
extends RefCounted

const TICRATE := 35
const INTERP_TICS := 5        # a snapshot and a half behind: two to draw between, and one late
const SNAP_FAR := 96.0        # a correction bigger than this is a jump, not a slide
const HISTORY := 128          # commands kept for replay
const TEAM_TROOP := ["SWAT", "ARMY"]
## the herd drawn this far behind the host: its word comes 9 tics apart
const HERD_BEHIND := 14
## a pod begun this long ago (tics) is not flown up to now: it is down
const POD_CATCHUP := 35 * 40

## Where the player's command comes from on a network client: this
## machine's input, as ever — the look taken since the last tic rounded to
## the wire's step and the remainder kept for the next — numbered, stamped
## with the tic the others are being drawn at, sent, and kept for replay.
class Session extends RefCounted:
	var net
	var kind := "net"
	var seq := 0
	func _init(n) -> void:
		net = n
	func cmd(game) -> Dictionary:
		var c: Dictionary
		if game.paused:
			c = TicCmd.new_cmd()
			game.net_look = Vector2()
		else:
			c = game.local_cmd()
			if net.bot:
				net.bot_cmd(c)
			var nl: Vector2 = game.net_look
			var lk := Vector2(TicCmd.q(nl.x, TicCmd.LOOK_SCALE, 32767) / float(TicCmd.LOOK_SCALE),
				TicCmd.q(nl.y, TicCmd.LOOK_SCALE, 32767) / float(TicCmd.LOOK_SCALE))
			game.net_look = nl - lk
			c.look = lk
		seq += 1
		c.tic = seq
		TicCmd.quantize(c)
		c.seen = net.seen_tic()
		net.sent(c)
		return c

## The rules on this side are only the ones drawing needs: who is on whose
## side. Deaths are the host's business, so a death here says nothing.
class ClientRules extends RefCounted:
	var net
	func _init(n) -> void:
		net = n
	static func team_of(x) -> int:
		if x is Player:
			return x.team
		if x is Actor and x.puppet:
			return x.net_team
		return -1
	func friendly(a, b) -> bool:
		return net.mode == "tdm" and a != b and team_of(a) >= 0 and team_of(a) == team_of(b)
	func died(_p, _source) -> void:
		pass
	func scale(_from, _to, amount: float) -> float:
		return amount

class Puppet extends RefCounted:
	var id := 0
	var a: Actor
	var type := "SWAT"
	var buf: Array = []
	var walked := 0.0
	var moved_at := 0
	var firing := false
	var guard := false
	var loop = null
	var dead := false
	var team := -1
	var pitch := 0.0
	## a plasma bolt the host says they fired, to draw (_puppet_tic)
	var bolt := false

var game
var client: NetClient
var now_fn: Callable
var session: Session
var history := {}              # seq → {cmd, angle, pitch, ammo}, in order
## THE HOST'S RULES (its welcome's, over NetMatch.RULES): what a life
## starts with, and whether the tanks run dry
var rules := {}
var puppets := {}              # id → Puppet
var last_tic := 0
var last_at := 0
var spawn_n := -1
var corrections := 0
var biggest := 0.0
var turned := 0
## the most of the others drawn at once, for the report
var most_puppets := 0
var score = null
var mode := "dm"
var team := -1
var lost = null
## the pods begun here off the host's word: "id:tic" → DropPod
var pods := {}
## the tic this machine's own last pod began on (the host's)
var my_pod_tic := -1
## the herd's samples: Game.herd index → [{tic, x, y, z, a, f, who}]
var herd_buf := {}
var herd_msgs := 0
## the line over the score while this machine hosts (Main.host_game)
var host_note := ""
## a test hook (--netbot): turn toward the nearest of the others and hold
## the trigger when they are in sight — through the command, like hands
var bot := false
## and with the trigger left alone (--netbot=look, for pictures)
var bot_fire := true

func _init(g, c: NetClient, now := Callable()) -> void:
	game = g
	client = c
	now_fn = now if now.is_valid() else func() -> int: return Time.get_ticks_msec()
	session = Session.new(self)
	var w = c.welcome if c.welcome != null else {}
	last_tic = int(w.get("tic", 0))
	last_at = int(now_fn.call())
	score = c.score
	mode = str(w.get("mode", "dm"))
	g.session = session
	g.net = self
	g.rules = ClientRules.new(self)
	rules = NetMatch.RULES.duplicate(true)
	var wr = w.get("rules")
	if wr is Dictionary:
		rules.merge(wr, true)
	var p = g.player
	NetMatch.renew(p, p.x, p.y, p.angle, rules)
	p.id = c.id
	p.team = c.team
	p.invincible = true
	p.pending_weapon = ""
	# THE PICKUPS ARE THE HOST'S: its list, by index, and its word on
	# which are taken (on_snap)
	if w.get("pk") is Array and g.get("pickups") != null:
		g.pickups.load_list(w.pk)
	c.on_snap = on_snap
	c.on_herd = on_herd
	# (until the host has dropped this player in: a moment, usually)
	# (a team match: which side, as it begins)
	g.set_big_message("DROPPING IN" if c.team < 0 else "DROPPING IN — TEAM %s" % NetMatch.TEAM_NAMES[clampi(c.team, 0, 1)], 10 * TICRATE)
	# THE HERD IS THE HOST'S: here, puppets of what it says
	for a in g.herd:
		a.puppet = true
	c.on_close = func(why):
		lost = why
		g.set_big_message("DISCONNECTED: %s" % str(why).to_upper(), 1000000000)

# ---- the clock ------------------------------------------------------------

## The host's tic now, as near as this machine can tell: the newest
## snapshot's, plus the time since it arrived, and never far past it.
func host_tic() -> float:
	var ahead := minf(6.0, (int(now_fn.call()) - last_at) * TICRATE / 1000.0)
	return last_tic + ahead

## The host tic the others are being drawn at.
func draw_tic() -> float:
	return host_tic() - INTERP_TICS

func seen_tic() -> int:
	return maxi(0, int(floor(draw_tic() + 0.5)))

# ---- commands -----------------------------------------------------------------

func sent(c: Dictionary) -> void:
	history[int(c.tic)] = {"cmd": c.duplicate(), "angle": 0.0, "pitch": 0.0, "ammo": {}}
	if history.size() > HISTORY:
		history.erase(history.keys()[0])
	client.send(c)

func poll() -> void:
	client.poll()

## After the machine's tic: what the command just run left the player
## looking at, for the replay; and the puppets' own tic.
func tic() -> void:
	# the island up: drop me in (the loading screen's last frames, the
	# shaders warming, are a moment; a headless bot may never draw one)
	if not client.ready_sent and game.island_ready():
		client.send_ready()
	var p = game.player
	# the same top-up the host gives, so the prediction fires when the host does
	if rules.get("infiniteAmmo", false):
		NetMatch.top_up(p)
	var h = history.get(session.seq)
	if h != null:
		h.angle = p.angle
		h.pitch = p.pitch
		h.ammo = p.ammo.duplicate()
	for pup in puppets.values():
		_puppet_tic(pup)
	# (the pods the game has done with: forgotten)
	if game.tics % 35 == 0:
		for k in pods.keys():
			if not is_instance_valid(pods[k]) or not game.pods.has(pods[k]):
				pods.erase(k)

# ---- a snapshot -------------------------------------------------------------

func on_snap(s: Dictionary) -> void:
	var t := int(s.tic)
	if t < last_tic:
		return        # late, and superseded
	last_tic = t
	last_at = int(now_fn.call())
	reconcile(s.get("you"), int(s.get("ack", 0)))
	_others(t, s.get("others", []))
	# which of the pickups are taken (sent when that changes)
	if s.get("pk") is Array and game.get("pickups") != null:
		game.pickups.apply_down(s.pk)
	var ev = s.get("ev")
	if ev is Array:
		for e in ev:
			_event(e)
	if s.get("score") != null:
		score = s.score

## Put the player where the host has it and run what it has not seen yet
## over the top. See the top of the file.
func reconcile(you, ack: int) -> void:
	var g = game
	var p = g.player
	var lv: Level = g.level
	if not (you is Dictionary):
		return
	team = int(you.team)
	p.team = team
	p.frags = int(you.frags)
	# A NEW LIFE: the host has put you on a pad. Start again from its word
	# for everything, and look where it says.
	var fresh: bool = int(you.n) != spawn_n
	if fresh:
		spawn_n = int(you.n)
		NetMatch.renew(p, float(you.x), float(you.y), float(you.a), rules)
		p.invincible = true
		g.big_message = null
	# IN A POD: the same pod flown here, from where it was aimed and when
	var pod = you.get("pod")
	if pod is Array and int(pod[2]) != my_pod_tic:
		my_pod_tic = int(pod[2])
		_fly_in(p, float(pod[0]), float(pod[1]), my_pod_tic)
	# what the host says of you, whatever this machine thinks
	var was: int = p.health + p.armour
	p.health = int(you.h)
	p.armour = int(you.get("ar", 0))
	p.armour_class = int(you.get("ac", 0))
	var now: int = p.health + p.armour
	if now < was and not int(you.d) and not fresh:
		p.damage_flash = mini(16, int(5 + (was - now) * 0.3))
		g.play_sound("hurt", p)
	p.respawn_in = int(you.back)
	# WHAT YOU WALKED OVER, as the host has it: said, heard and flashed here
	var got = you.get("got")
	if got is Array and g.get("pickups") != null:
		for k in got:
			if int(k) >= 0 and int(k) < Pickups.KINDS.size():
				p.bonus_flash = 6
				g.pickups.feedback(int(k), [])
	# THE TANKS: the host's count, and what this machine has spent since
	# the command it answered (a new life: the host's count, flat)
	var am = you.get("am")
	if am is Dictionary:
		var h = history.get(ack)
		for k in Weapons.TANKS:
			var host_n := int(am.get(k, 0))
			var had := int(p.ammo.get(k, 0))
			var n := host_n
			if not fresh:
				# (the command it answered already gone: nothing to measure
				# from, so this machine's own count stands until the next)
				if h == null or not (h.ammo as Dictionary).has(k):
					continue
				n = host_n - (int(h.ammo[k]) - had)
			n = clampi(n, 0, int(Weapons.TANKS[k][0]))
			if n == had:
				continue
			# the commands still in flight measured from the corrected count
			# too, or the next snapshot would see this correction as spending
			for s2 in history:
				if s2 > ack and (history[s2].ammo as Dictionary).has(k):
					history[s2].ammo[k] = int(history[s2].ammo[k]) + (n - had)
			p.ammo[k] = n
			# (more than there was: a pickup, which lets a dry tank go and
			# puts an empty hand on the gun it feeds, as the host's did)
			if n > had:
				p.dry[k] = false
				if not fresh:
					p.switch_for_tank(k)
		if fresh:
			for k2 in history:
				history[k2].ammo = p.ammo.duplicate()
	for k in history.keys():
		if k <= ack:
			history.erase(k)
		else:
			break
	# WHERE THE HOST WILL HAVE YOU LOOKING once it has run what is in
	# flight: its angle, and every turn since. The same as this machine's
	# unless this is a new life or the host folded commands together — and
	# then the host's wins, and so does the replay below.
	var yaw := float(you.a)
	var pitch := float(you.p)
	for k in history:
		var e: Dictionary = history[k]
		yaw = U.angle_norm(yaw - e.cmd.look.x)
		pitch = clampf(pitch - e.cmd.look.y, -Player.MAX_PITCH, Player.MAX_PITCH)
	if fresh or absf(U.angle_norm(yaw - p.angle)) > 1e-3 or absf(pitch - p.pitch) > 1e-3:
		var y2 := float(you.a)
		var p2 := float(you.p)
		for k in history:
			var e: Dictionary = history[k]
			y2 = U.angle_norm(y2 - e.cmd.look.x)
			p2 = clampf(p2 - e.cmd.look.y, -Player.MAX_PITCH, Player.MAX_PITCH)
			e.angle = y2
			e.pitch = p2
		p.angle = yaw
		p.pitch = pitch
		turned += 1
	if int(you.d):
		if not p.dead:
			p.x = float(you.x)
			p.y = float(you.y)
			p.die()
		return
	if p.dead:
		return      # until the host says where you are again
	# (riding: the pod has you, here as there — nothing to replay)
	if pod is Array or (p.pod != null and p.pod.active and p.pod.holds_player()):
		return

	# THE REPLAY. Keep what is only the camera's — the bob, the eye's height,
	# the turn — and run the movement again from the host's state through
	# every command it has not answered.
	var keep := {"view_z": p.view_z, "bob": p.bob, "bob_phase": p.bob_phase, "look_rate": p.look_rate,
		"pitch_rate": p.pitch_rate, "angle": p.angle, "pitch": p.pitch}
	var ox: float = p.x
	var oy: float = p.y
	var oz: float = p.z
	_take_body(you)
	for k in history:
		var e: Dictionary = history[k]
		p.angle = e.angle
		p.pitch = e.pitch
		p.move(e.cmd)
	for k in keep:
		p.set(k, keep[k])
	var err := Vector3(p.x - ox, p.y - oy, p.z - oz).length()
	if err > 0.01:
		corrections += 1
		biggest = maxf(biggest, err)
		# small: slide a third of the way now and the next snapshot does the
		# rest. Big: it was never where you thought.
		if err < SNAP_FAR:
			var kk := 0.35
			p.x = ox + (p.x - ox) * kk
			p.y = oy + (p.y - oy) * kk
			p.z = oz + (p.z - oz) * kk
			var sec := lv.sector_at(p.x, p.y, p.sector)
			if sec:
				p.sector = sec if sec.above == -1 else lv.span_in(sec, p.z)

func _take_body(you: Dictionary) -> void:
	var p = game.player
	p.x = float(you.x)
	p.y = float(you.y)
	p.z = float(you.z)
	p.momx = float(you.mx)
	p.momy = float(you.my)
	p.momz = float(you.mz)
	p.on_ground = int(you.g) != 0
	var sec: Level.Sector = game.level.sector_at(p.x, p.y, p.sector)
	if sec:
		# the storey at the height the host says (the snapshot's z)
		p.sector = sec if sec.above == -1 else game.level.span_in(sec, p.z)

# ---- the others ------------------------------------------------------------

## A pod begun on the host at tic `t`, aimed at (x, y), begun here and
## flown up to now — `p` riding it (this machine's player) or nobody (the
## picture of somebody else's).
func _fly_in(p, x: float, y: float, t: int) -> void:
	var key := "%d:%d" % [p.id if p != null else -1, t]
	if pods.has(key):
		return
	var ahead := int(round(host_tic())) - t
	if ahead > POD_CATCHUP:
		return
	var pod = game.start_pod(p, x, y, true)
	pods[key] = pod
	for k in maxi(0, ahead):
		if not pod.active:
			break
		pod.tic({})

func _others(t: int, list: Array) -> void:
	var here := {}
	for o in list:
		var id := int(o[0])
		here[id] = true
		# somebody coming down: their pod, drawn here
		if (int(o[6]) & 16) != 0 and o.size() >= 11:
			var key := "%d:%d" % [id, int(o[10])]
			if not pods.has(key):
				var ahead := int(round(host_tic())) - int(o[10])
				if ahead <= POD_CATCHUP:
					var pod = game.start_pod(null, float(o[8]), float(o[9]), true)
					pods[key] = pod
					for k in maxi(0, ahead):
						if not pod.active:
							break
						pod.tic({})
		var pup: Puppet = puppets.get(id)
		var tm := int(o[7])
		if pup == null:
			pup = _puppet(id, tm, float(o[1]), float(o[2]), float(o[3]), float(o[4]))
		pup.buf.append({"tic": t, "x": float(o[1]), "y": float(o[2]), "z": float(o[3]), "a": float(o[4]),
			"pitch": float(o[5]), "f": int(o[6])})
		if pup.buf.size() > 24:
			pup.buf.pop_front()
		pup.team = tm
		pup.a.net_team = tm
		if (int(o[6]) & 32) != 0:
			pup.bolt = true
	for id in puppets.keys():
		if not here.has(id):
			_drop(id, puppets[id])
	most_puppets = maxi(most_puppets, puppets.size())

func _puppet(id: int, tm: int, x: float, y: float, z: float, a: float) -> Puppet:
	var g = game
	var type: String = TEAM_TROOP[1 if tm == 1 else 0]
	var act := Actor.new(g, type, x, y, a)
	act.puppet = true
	act.net_id = id
	act.net_team = tm
	# no mind: it walks, turns, fires and falls because this file says so,
	# and a round from this machine marks it without hurting it — the host
	# decides what a hit did
	act.monster = false
	act.z = z
	act.state = States.state(type + "_STAND")
	act.state_tics = -1
	g.actors.append(act)
	var pup := Puppet.new()
	pup.id = id
	pup.a = act
	pup.type = type
	pup.team = tm
	puppets[id] = pup
	return pup

func _drop(id: int, pup: Puppet) -> void:
	if pup.loop != null:
		pup.loop.stop()
	pup.a.remove()
	puppets.erase(id)

# ---- the herds ------------------------------------------------------------

func on_herd(m: Dictionary) -> void:
	herd_msgs += 1
	var t := int(m.get("tic", 0))
	var g = game
	for r in m.get("u", []):
		var i := int(r[0])
		if i < 0 or i >= g.herd.size():
			continue
		var b: Array = herd_buf.get(i, [])
		b.append({"tic": t, "x": float(r[1]), "y": float(r[2]), "z": float(r[3]), "a": float(r[4]), "f": int(r[5]), "who": int(r[6])})
		if b.size() > 6:
			b.pop_front()
		herd_buf[i] = b

## who a unicorn is after, here: this machine's player, or a puppet
func _herd_target(who: int):
	if who == 0:
		return null
	if who == client.id:
		return game.player
	var pup: Puppet = puppets.get(who)
	return pup.a if pup != null else null

## Every frame: each unicorn the host has told of slid to where she was
## HERD_BEHIND tics ago, drawn as what she is doing; her beam on and off.
func _herd_frame() -> void:
	var t := host_tic() - HERD_BEHIND
	var g = game
	var rb = g.rainbow
	for i in herd_buf:
		var a: Actor = g.herd[i]
		if a.dead or a.removed:
			continue
		var b: Array = herd_buf[i]
		var s0: Dictionary = b[0]
		var s1: Dictionary = b[0]
		for k in b.size():
			if b[k].tic <= t:
				s0 = b[k]
			if b[k].tic >= t:
				s1 = b[k]
				break
			s1 = b[k]
		var span: float = s1.tic - s0.tic
		var kk := clampf((t - s0.tic) / span, 0.0, 1.0) if span > 0.0 else 0.0
		var nx: float = s0.x + (s1.x - s0.x) * kk
		var ny: float = s0.y + (s1.y - s0.y) * kk
		var moving := Vector2(s1.x - s0.x, s1.y - s0.y).length() > 4.0
		a.x = nx
		a.y = ny
		a.z = s0.z + (s1.z - s0.z) * kk
		a.angle = U.angle_norm(s0.a + U.angle_norm(s1.a - s0.a) * kk)
		var sec = g.level.sector_at(a.x, a.y, a.sector)
		if sec:
			a.sector = sec
		g.blockmap.moved(a)
		var f: int = (s0 if kk < 0.5 else s1).f
		var beam := (f & 2) != 0
		var big: bool = a.type == "UNICORN"
		var k := "UNI" if big else "FOAL"
		var nm: String = (k + "_GRAZE") if not moving else (k + ("_RUN1" if (f & 4) != 0 else "_WALK1"))
		if beam and big:
			nm = "UNI_BEAM"
		if a.state.get("name") != nm:
			a.state = States.state(nm)
			a.state_tics = -1
		if rb != null:
			if beam and not rb.firing(a):
				rb.fire(a, _herd_target(int(s1.who)), true)
			elif not beam and rb.firing(a):
				rb.stop(a)

## A death in the herd, on the host: to pieces here as well
func _herd_dies(i: int) -> void:
	var g = game
	if i < 0 or i >= g.herd.size():
		return
	var a: Actor = g.herd[i]
	herd_buf.erase(i)
	if a.dead or a.removed:
		return
	a.puppet = false
	g.gib(a)

## Every frame: slide each of them to where they were at draw_tic.
func frame() -> void:
	_herd_frame()
	var t := draw_tic()
	var g = game
	var lv: Level = g.level
	for pup in puppets.values():
		var b: Array = pup.buf
		if b.is_empty():
			continue
		var s0: Dictionary = b[0]
		var s1: Dictionary = b[0]
		for i in b.size():
			if b[i].tic <= t:
				s0 = b[i]
			if b[i].tic >= t:
				s1 = b[i]
				break
			s1 = b[i]
		var span: float = s1.tic - s0.tic
		var k := clampf((t - s0.tic) / span, 0.0, 1.0) if span > 0.0 else 0.0
		var a: Actor = pup.a
		# A JUMP IS NOT A WALK: a respawn, or anything that moved them further
		# between two snapshots than anybody can run, is drawn where they were
		# until it is drawn where they are
		if Vector2(s1.x - s0.x, s1.y - s0.y).length() > SNAP_FAR * 1.5:
			k = 0.0 if k < 1.0 else 1.0
		var nx: float = s0.x + (s1.x - s0.x) * k
		var ny: float = s0.y + (s1.y - s0.y) * k
		var stp := Vector2(nx - a.x, ny - a.y).length()
		pup.walked += stp
		if stp > 0.05:
			pup.moved_at = int(now_fn.call())
		a.x = nx
		a.y = ny
		a.z = s0.z + (s1.z - s0.z) * k
		a.angle = U.angle_norm(s0.a + U.angle_norm(s1.a - s0.a) * k)
		pup.pitch = s0.pitch + (s1.pitch - s0.pitch) * k
		var sec := lv.sector_at(a.x, a.y, a.sector)
		if sec:
			a.sector = sec if sec.above == -1 else lv.span_in(sec, a.z)
		g.blockmap.moved(a)
		# and what they are doing, as of the nearer of the two
		_look(pup, int((s0 if k < 0.5 else s1).f))

func _look(pup: Puppet, f: int) -> void:
	var a: Actor = pup.a
	var g = game
	var dead := (f & 1) != 0
	pup.firing = (f & 2) != 0 and not dead
	pup.guard = (f & 4) != 0
	if dead != pup.dead:
		pup.dead = dead
		a.dead = dead
		a.solid = not dead
		if dead:
			if pup.loop != null:
				pup.loop.stop()
			pup.loop = null
			g.play_sound(a.info.get("deathSound"), a)
			a.state = States.state(pup.type + "_DIE1")
			a.state_tics = a.state.tics
		else:
			a.state = States.state(pup.type + "_STAND")
			a.state_tics = -1
	if dead:
		return
	if pup.firing and pup.loop == null and g.sound != null:
		pup.loop = g.sound.loop("minigunloop", a)
	elif not pup.firing and pup.loop != null:
		pup.loop.stop()
		pup.loop = null
	# the frame: the muzzle's two while the rounds go, else a stride of the
	# walk every dozen units, else standing
	var nm := "STAND"
	if pup.firing:
		nm = "ATK2" if (g.tics >> 1) & 1 else "ATK1"
	elif int(now_fn.call()) - pup.moved_at < 150:
		nm = "RUN%d" % ((int(pup.walked / 12.0) % 8) + 1)
	var st := States.state(pup.type + "_" + nm)
	if not st.is_empty() and a.state.get("name") != st.name:
		a.state = st
		a.state_tics = -1

func _puppet_tic(pup: Puppet) -> void:
	var a: Actor = pup.a
	var g = game
	# the fall plays out on its own, a state at a time
	if pup.dead and a.state_tics > 0:
		a.state_tics -= 1
		if a.state_tics == 0 and a.state.next != null:
			a.state = States.state(a.state.next)
			a.state_tics = a.state.tics
	# THEIR ROUNDS, for the look of it: what the host decided is in the
	# snapshots, and what is drawn is the same gun going off from where they
	# are drawn — the holes, the tracers and the blood are this machine's,
	# and hurt nothing
	# AND THEIR PLASMA BOLT (flag 32): the rifle's own bolt, down the way
	# they look, for the look of it too — it was the host's that hit
	if pup.bolt:
		pup.bolt = false
		if not pup.dead and g.get("plasma") != null:
			var from := Vector3(a.x + cos(a.angle) * 16.0, a.y + sin(a.angle) * 16.0, a.z + 40.0)
			g.hitscan(a, a.angle, 6000.0, 0.0, {"shot": true, "hot": true, "pitch": pup.pitch, "from": from})
			g.plasma.spawn(from, g.last_hit)
			g.play_sound("plasma", a)
	if pup.firing and not pup.dead:
		var from := Vector3(a.x + cos(a.angle) * 16.0, a.y + sin(a.angle) * 16.0, a.z + 40.0)
		for i in 2:
			var ang := a.angle + (randf() - 0.5) * 0.11
			var pt := pup.pitch + (randf() - 0.5) * 0.08
			g.hitscan(a, ang, 2400.0, 0.0, {"shot": true, "hot": true, "pitch": pt, "from": from})
			if i == 0 and g.tracers != null:
				g.tracers.spawn(from, g.last_hit)

# ---- the bot (a test hook) ----------------------------------------------------

## Turn toward the nearest puppet that is alive — through game.net_look, so
## the turn goes down the wire like a mouse's — walk at them when they are
## far, and hold the trigger when they are in sight and near the sights.
func bot_cmd(c: Dictionary) -> void:
	var p = game.player
	c.attack = false
	if p.dead:
		return
	var best: Puppet = null
	var bd := INF
	for pup in puppets.values():
		if pup.dead:
			continue
		var d := U.dist2(p.x, p.y, pup.a.x, pup.a.y)
		if d < bd:
			bd = d
			best = pup
	if best == null:
		return
	var a: Actor = best.a
	var want := atan2(a.y - p.y, a.x - p.x)
	var dist := sqrt(bd)
	var want_p := clampf(atan2(a.z + 36.0 - p.view_z, dist), -Player.MAX_PITCH, Player.MAX_PITCH)
	game.net_look = Vector2(U.angle_norm(p.angle - want), p.pitch - want_p)
	var seen: bool = not game.level.sight_blocked(p.x, p.y, p.view_z, a.x, a.y, a.z + 36.0)
	c.attack = bot_fire and seen and absf(U.angle_norm(p.angle - want)) < 0.2
	c.fwd = 1.0 if dist > 320.0 else 0.0

# ---- what happened ------------------------------------------------------------

func name_of(id: int) -> String:
	if id == client.id:
		return "YOU"
	if score is Dictionary:
		for q in score.get("players", []):
			if int(q.id) == id:
				return str(q.name)
	return "PLAYER %d" % id

func _event(e: Dictionary) -> void:
	var g = game
	match str(e.get("k", "")):
		# a line from the host's console (NetHost.command: say)
		"say":
			g.toast("HOST: " + str(e.get("text", "")).to_upper())
		"frag":
			var v := name_of(int(e.of))
			g.toast(("%s FRAGGED %s" % [name_of(int(e.by)), v]) if int(e.get("by", 0)) != 0 else "%s DIED" % v)
		"join":
			if int(e.id) != client.id:
				var side := ""
				if e.get("team") != null and int(e.team) >= 0:
					side = " — TEAM " + NetMatch.TEAM_NAMES[clampi(int(e.team), 0, 1)]
				g.toast("%s JOINED%s" % [str(e.name), side])
			# the table has them from the next score; say their name before then
			if score is Dictionary and score.get("players") is Array:
				var known := false
				for q in score.players:
					if int(q.id) == int(e.id):
						known = true
				if not known:
					score.players.append({"id": e.id, "name": e.name, "team": e.team, "frags": 0, "deaths": 0, "ping": 0})
		"leave":
			g.toast("%s LEFT" % str(e.name))
		"over":
			g.set_big_message("%s WINS" % str(e.winner).to_upper(), 8 * TICRATE)
		"round":
			g.big_message = null
			g.toast("ROUND %d" % int(e.n))
		"udie":
			_herd_dies(int(e.i))

func close() -> void:
	for id in puppets.keys():
		_drop(id, puppets[id])
	client.close()

# ---- the score, on the screen (NetBoard in the JS) --------------------------------

## The line at the top, and — while TAB is held or the round is over — the
## table under it. Hud draws them.
func board_lines(held: bool) -> Array:
	var s = score
	var p = game.player
	if not (s is Dictionary):
		return ["CONNECTED"] if host_note == "" else [host_note, "CONNECTED"]
	var dead := "   RESPAWN IN %d" % ceili(p.respawn_in / float(TICRATE)) if p.dead else ""
	var ping := "   %dMS" % roundi(client.rtt)
	# THE ROUND'S CLOCK, when it has one (NetMatch timeLimit), counting
	# down between the once-a-second tables
	var left := int(s.get("clock", -1))
	if left >= 0:
		# (counted on from the host's tic the table was made on)
		var secs := maxi(0, ceili((left - (host_tic() - float(s.get("at", last_tic)))) / float(TICRATE)))
		# (past it with the top shared: sudden death, NetMatch.tied)
		var clock := "OVERTIME" if left == 0 else "%d:%02d" % [secs / 60, secs % 60]
		ping = "   " + clock + ping
	var out := []
	if s.get("teams") is Array:
		var mine: int = team
		var a: Dictionary = s.teams[0]
		var b: Dictionary = s.teams[1]
		out.append("%s%s %d  —  %d %s%s   TO %d%s%s" % [">" if mine == 0 else "", a.name, int(a.score), int(b.score), b.name,
			"<" if mine == 1 else "", int(s.limit), dead, ping])
	else:
		var frags := 0
		for q in s.get("players", []):
			if int(q.id) == client.id:
				frags = int(q.frags)
		out.append("FRAGS %d   TO %d%s%s" % [frags, int(s.limit), dead, ping])
	if host_note != "":
		out.push_front(host_note)
	var over = s.get("over")
	if held or over != null:
		var rows: Array = s.get("players", []).duplicate()
		rows.sort_custom(func(x, y): return int(x.frags) > int(y.frags) if int(x.team) == int(y.team) else int(x.team) < int(y.team))
		var teams = s.get("teams")
		out.append("")
		out.append("%s%sFRAGS DEATHS PING" % ["NAME".rpad(17), "SIDE " if teams != null else ""])
		for r in rows:
			var side := ""
			if teams is Array:
				var ti := int(r.team)
				side = (str(teams[ti].name) if ti >= 0 and ti < teams.size() else "-").rpad(5).substr(0, 5)
			out.append("%s%s%s%s%s%d" % [">" if int(r.id) == client.id else " ", str(r.name).rpad(16).substr(0, 16), side,
				str(int(r.frags)).rpad(6), str(int(r.deaths)).rpad(7), int(r.ping)])
		if over is Dictionary:
			out.append("")
			out.append("%s WINS — NEXT ROUND IN %d" % [str(over.winner), ceili(float(over.left) / TICRATE)])
	return out
