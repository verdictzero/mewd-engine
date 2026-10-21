## MEWD — the sound effects (js/audio.js).
##
## TWO KINDS, as in the web build. The SYNTHESISED ones — every hiss,
## thud and scream the game asks for by name — are switched off behind
## MUTED there, and are here too: the names are still asked for, and
## nothing plays. The RECORDED ones are the user's own and play whatever
## MUTED says: the minigun winding up, firing and winding down, and the
## lance's five. A name in SAMPLE_FOR is a recording.
##
## Loudness falls off with distance from the listener — a curve, no
## panning, as in the web build — and each recording is turned down
## against the music by SAMPLE_GAIN, which the user asked for.
class_name Sound
extends Node

const MUTED := true
const MAX_DISTANCE := 1600.0

const SAMPLES := {
	"minigun_start": "res://assets/sfx/minigun_start.wav",
	"minigun_fire": "res://assets/sfx/minigun_fire.wav",
	"minigun_stop": "res://assets/sfx/minigun_stop.wav",
	"lance_charge_start": "res://assets/sfx/lance_charge_start.wav",
	"lance_charge_loop": "res://assets/sfx/lance_charge_loop.wav",
	"lance_charge_full": "res://assets/sfx/lance_charge_full.wav",
	"lance_prefire": "res://assets/sfx/lance_prefire.wav",
	"lance_fire_a": "res://assets/sfx/lance_fire_a.wav",
	"lance_fire_b": "res://assets/sfx/lance_fire_b.wav",
	# the pickups' (tools/pickup-sounds.py)
	"pickup": "res://assets/sfx/pickup.wav",
	"powerup": "res://assets/sfx/powerup.wav",
	"noammo": "res://assets/sfx/noammo.wav",
	# the plasma rifle's own shot (at the user's request: "give the plasma
	# rifle this sound effect", beam_rifle.mp3)
	"plasma_fire": "res://assets/sfx/beam_rifle.mp3",
	# the fetus launcher's (tools/fetus-sounds.py): the user's goop_12.wav
	# as it leaves, one of the user's four cries as it flies, and a splat
	# made here until the user's own
	"fetus_launch": "res://assets/sfx/fetus_launch.wav",
	"fetus_cry_1": "res://assets/sfx/fetus_cry_1.wav",
	"fetus_cry_2": "res://assets/sfx/fetus_cry_2.wav",
	"fetus_cry_3": "res://assets/sfx/fetus_cry_3.wav",
	"fetus_cry_4": "res://assets/sfx/fetus_cry_4.wav",
	"fetus_splat": "res://assets/sfx/fetus_splat.wav",
}
const SAMPLE_FOR := {
	"spinup": "minigun_start", "minigunloop": "minigun_fire", "spindown": "minigun_stop",
	"lancestart": "lance_charge_start", "lancecharge": "lance_charge_loop", "lancecharge3": "lance_charge_full",
	"lanceprefire": "lance_prefire", "lancefire": "lance_fire_a", "lancefire2": "lance_fire_b",
	# the plasma rifle's shot (Plasma)
	"plasma": "plasma_fire",
	# a pickup taken, a big one (and IDDQD), and a trigger on nothing (Pickups, Player)
	"pickup": "pickup", "powerup": "powerup", "noammo": "noammo",
	# the fetus launcher (FetusLauncher)
	"fetuslaunch": "fetus_launch", "fetuscry1": "fetus_cry_1", "fetuscry2": "fetus_cry_2",
	"fetuscry3": "fetus_cry_3", "fetuscry4": "fetus_cry_4", "fetussplat": "fetus_splat",
}
const SAMPLE_GAIN := {
	"minigun_fire": 0.32, "minigun_start": 0.42, "minigun_stop": 0.42,
	"lance_charge_start": 0.46, "lance_charge_loop": 0.34, "lance_charge_full": 0.46,
	"lance_prefire": 0.52, "lance_fire_a": 0.50, "lance_fire_b": 0.44,
	"pickup": 0.40, "powerup": 0.42, "noammo": 0.50,
	"plasma_fire": 0.45,
	"fetus_launch": 0.55, "fetus_cry_1": 0.40, "fetus_cry_2": 0.40, "fetus_cry_3": 0.46, "fetus_cry_4": 0.40,
	"fetus_splat": 0.60,
}

## the ears: anything with an x and a y
var listener = null
## a map in storeys: the height between the two counts too, so a shot
## upstairs is quieter than one beside you (see _gain_for)
var layered := false
var volume := 1.0
var _streams := {}

## One held sound, with a handle on it.
class Loop:
	var player: AudioStreamPlayer
	func stop() -> void:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	func rate(r: float, _glide := 0.0) -> void:
		if is_instance_valid(player):
			player.pitch_scale = maxf(0.01, r)

func _stream(key: String, loop: bool) -> AudioStream:
	var k := key + ("#loop" if loop else "")
	if not _streams.has(k):
		var s: AudioStream = load(SAMPLES[key])
		if loop and s is AudioStreamWAV:
			s = s.duplicate()
			var w: AudioStreamWAV = s
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		_streams[k] = s
	return _streams[k]

func _gain_for(from) -> float:
	if from == null or listener == null or from == listener:
		return 1.0
	var d := sqrt(U.dist2(from.x, from.y, listener.x, listener.y))
	if layered and "z" in from and "z" in listener:
		d = Vector2(d, float(from.z) - float(listener.z)).length()
	if d > MAX_DISTANCE:
		return 0.0
	return pow(maxf(0.0, 1.0 - d / MAX_DISTANCE), 1.7)

func _start(name, from, loop: bool, rate := 1.0) -> AudioStreamPlayer:
	if name == null or not SAMPLE_FOR.has(name):
		return null     # a synthesised sound, and those are MUTED
	var key: String = SAMPLE_FOR[name]
	var gain := _gain_for(from) * float(SAMPLE_GAIN.get(key, 1.0)) * volume
	if gain < 0.004:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = _stream(key, loop)
	p.volume_db = linear_to_db(gain)
	p.pitch_scale = rate
	add_child(p)
	p.play()
	if not loop:
		p.finished.connect(p.queue_free)
	return p

func play(name, from = null, opts := {}) -> void:
	_start(name, from, false, float(opts.get("rate", 1.0)))

## A SOUND THAT GOES WITH SOMETHING (a fetus crying as it flies): one
## shot, as play is, with a handle — follow() keeps its loudness to where
## the thing is now, stop() cuts it short. null when nothing plays.
class Voice:
	var player: AudioStreamPlayer
	var sound
	var key := ""
	func follow(from) -> void:
		if is_instance_valid(player):
			var g: float = sound._gain_for(from) * float(SAMPLE_GAIN.get(key, 1.0)) * sound.volume
			player.volume_db = linear_to_db(maxf(g, 1e-5))
	func stop() -> void:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	## still sounding (a one-shot frees itself when it ends)
	func playing() -> bool:
		return is_instance_valid(player) and player.playing

func voice(name, from = null) -> Voice:
	var p := _start(name, from, false)
	if p == null:
		return null
	var v := Voice.new()
	v.player = p
	v.sound = self
	v.key = SAMPLE_FOR[name]
	return v

func loop(name, from = null) -> Loop:
	var p := _start(name, from, true)
	if p == null:
		return null
	var l := Loop.new()
	l.player = p
	return l
