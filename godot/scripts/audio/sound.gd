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
}
const SAMPLE_FOR := {
	"spinup": "minigun_start", "minigunloop": "minigun_fire", "spindown": "minigun_stop",
	"lancestart": "lance_charge_start", "lancecharge": "lance_charge_loop", "lancecharge3": "lance_charge_full",
	"lanceprefire": "lance_prefire", "lancefire": "lance_fire_a", "lancefire2": "lance_fire_b",
}
const SAMPLE_GAIN := {
	"minigun_fire": 0.32, "minigun_start": 0.42, "minigun_stop": 0.42,
	"lance_charge_start": 0.46, "lance_charge_loop": 0.34, "lance_charge_full": 0.46,
	"lance_prefire": 0.52, "lance_fire_a": 0.50, "lance_fire_b": 0.44,
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

func loop(name, from = null) -> Loop:
	var p := _start(name, from, true)
	if p == null:
		return null
	var l := Loop.new()
	l.player = p
	return l
