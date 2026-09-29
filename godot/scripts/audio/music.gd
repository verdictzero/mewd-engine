## MEWD — the music (js/music.js).
##
## THREE TRACKS, at the user's request, playing for ever: the user's
## three E1M1 remixes, one into the next and round again, each fading
## into the one after it ON THE BEAT. Nothing is analysed while the game
## runs; each track was measured once, offline — tempo, the first
## downbeat, and a downbeat near the end to hand over on — and this is
## arithmetic on that table.
##
## THE HANDOVER: the outgoing track reaches `out`; on that instant the
## incoming track's first downbeat lands (it was started bar0 earlier,
## scaled), both gains ramp linearly over FADE_BARS bars, and the
## outgoing stops. The incoming arrives AT THE OUTGOING'S TEMPO — its
## rate set to the ratio — and over MATCH_BARS more bars eases back to
## its own, a DJ's pitch fader brought home once the other deck is off.
class_name Music
extends Node

const TRACKS := [
	{"url": "res://assets/music/e1m1_00.mp3", "bpm": 145.80, "bar0": 0.135, "out": 244.05, "seconds": 259.76},
	{"url": "res://assets/music/e1m1_01.mp3", "bpm": 140.34, "bar0": 0.105, "out": 227.12, "seconds": 243.20},
	{"url": "res://assets/music/e1m1_02.mp3", "bpm": 142.30, "bar0": 0.110, "out": 221.47, "seconds": 236.76},
]
const FADE_BARS := 8
const MATCH_BARS := 8

var volume := 0.5
var decks: Array[AudioStreamPlayer] = []
var current := -1
## the handover under way: {deck, from, start, rate, fade_end, rate_end, out}
var plan := {}
var _clock := 0.0

static func bar_of(t: Dictionary) -> float:
	return 240.0 / t.bpm

## One handover, as numbers: `a` reaches its out at wall time out_at.
static func arrange(a: Dictionary, b: Dictionary, out_at: float) -> Dictionary:
	var rate: float = a.bpm / b.bpm
	var fade := FADE_BARS * bar_of(a)
	var match_ := MATCH_BARS * bar_of(a)
	return {"start": out_at - b.bar0 / rate, "rate": rate, "out": out_at,
		"fade_end": out_at + fade, "rate_end": out_at + fade + match_}

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		decks.append(p)

func _gain(v: float) -> float:
	return clampf(v, 0.0, 1.0) ** 2

func set_volume(v: float) -> void:
	volume = v
	for d in decks:
		if d.playing and plan.is_empty():
			d.volume_db = linear_to_db(maxf(0.0001, _gain(volume)))

func start(i := 0) -> void:
	current = i
	var d := decks[0]
	d.stream = load(TRACKS[i].url)
	d.pitch_scale = 1.0
	d.volume_db = linear_to_db(maxf(0.0001, _gain(volume)))
	d.play()
	_clock = 0.0
	plan = {}

func stop() -> void:
	for d in decks:
		d.stop()
	current = -1
	plan = {}

func _process(dt: float) -> void:
	if current < 0:
		return
	_clock += dt
	var out_deck := decks[0]
	var in_deck := decks[1]
	var a: Dictionary = TRACKS[current]
	var pos := out_deck.get_playback_position() if out_deck.playing else 0.0
	# put the next handover on the schedule a few seconds before it is due
	if plan.is_empty() and out_deck.playing and pos >= a.out - 6.0:
		var nxt := (current + 1) % TRACKS.size()
		var out_at: float = _clock + (a.out - pos)
		plan = arrange(a, TRACKS[nxt], out_at)
		plan.next = nxt
		plan.started = false
	if plan.is_empty():
		return
	var g := _gain(volume)
	if not plan.started and _clock >= plan.start:
		in_deck.stream = load(TRACKS[plan.next].url)
		in_deck.pitch_scale = plan.rate
		in_deck.volume_db = linear_to_db(0.0001)
		in_deck.play()
		plan.started = true
	if plan.started:
		var f: float = clampf((_clock - plan.out) / (plan.fade_end - plan.out), 0.0, 1.0)
		out_deck.volume_db = linear_to_db(maxf(0.0001, g * (1.0 - f)))
		in_deck.volume_db = linear_to_db(maxf(0.0001, g * f))
		var r: float = clampf((_clock - plan.fade_end) / (plan.rate_end - plan.fade_end), 0.0, 1.0)
		in_deck.pitch_scale = lerpf(plan.rate, 1.0, r)
		if _clock >= plan.fade_end and out_deck.playing:
			out_deck.stop()
		if _clock >= plan.rate_end:
			# the incoming deck is the outgoing one now
			decks.reverse()
			current = plan.next
			plan = {}
