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
## the whole thing slowed (the game's slow motion): a factor on every
## deck's pitch
var rate := 1.0
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
		if d.playing and plan.is_empty() and pl_fade < 0.0:
			d.volume_db = linear_to_db(maxf(0.0001, _gain(volume)))

func start(i := 0) -> void:
	current = i
	var d := decks[0]
	d.stream = load(TRACKS[i].url)
	d.pitch_scale = rate
	d.volume_db = linear_to_db(maxf(0.0001, _gain(volume)))
	d.play()
	_clock = 0.0
	plan = {}

## THE TITLE'S MUSIC (at the user's request: "Waiting for Something"),
## looping for as long as the title is up (looped in its import and here);
## NEW GAME's start / start_list takes the deck over from it
const TITLE_THEME := "res://assets/music/waiting_for_something.mp3"
func title_theme() -> void:
	stop()
	var st = load(TITLE_THEME)
	if st == null:
		return
	if "loop" in st:
		st.loop = true
	var d := decks[0]
	d.stream = st
	d.pitch_scale = 1.0
	d.volume_db = linear_to_db(maxf(0.0001, _gain(volume)))
	d.play()

## THE DIRGE (galvarius's death behaviour, music_manager.gd there): what
## is playing out over a second, two seconds of nothing, then the death
## music — the user's own "Everyone You Love is Dead" — looping until the
## game is reset (looped in its import and here)
const DIRGE := "res://assets/music/everyone_you_love_is_dead.mp3"
var dirging := false
func dirge() -> void:
	if dirging:
		return
	dirging = true
	plan = {}
	current = -1
	playlist = []
	pl_fade = -1.0
	var tw := create_tween()
	for d in decks:
		tw.parallel().tween_property(d, "volume_db", -60.0, 1.0)
	tw.tween_callback(func():
		for d in decks:
			d.stop())
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		var st = load(DIRGE)
		if st == null:
			return
		if "loop" in st:
			st.loop = true
		var d := decks[0]
		d.stream = st
		d.pitch_scale = 1.0
		d.volume_db = linear_to_db(maxf(0.0001, _gain(volume)))
		d.play())

## AN ISLAND'S OWN MUSIC (Islands "music", at the user's request: CANDY
## LAND's "Golf Course Muzak" and "Sunny Resort Groove"): its tracks in
## turn, round and round, each CROSSFADED into the next over XFADE seconds
## before it ends — no beat-matching, these are not the E1M1 remixes.
const XFADE := 6.0
var playlist: Array = []
var pl_index := -1
var pl_fade := -1.0     # seconds into a crossfade, -1 none
func start_list(urls: Array) -> void:
	stop()
	playlist = urls.duplicate()
	if playlist.is_empty():
		return
	pl_index = 0
	_pl_play(decks[0], playlist[0], _gain(volume))
	pl_fade = -1.0

func _pl_play(d: AudioStreamPlayer, url: String, g: float) -> void:
	var st = load(url)
	if st == null:
		return
	# (each runs to its end: the list is what loops)
	if "loop" in st:
		st.loop = false
	d.stream = st
	d.pitch_scale = rate
	d.volume_db = linear_to_db(maxf(0.0001, g))
	d.play()

func _pl_tic(dt: float) -> void:
	var out_deck := decks[0]
	var in_deck := decks[1]
	var g := _gain(volume)
	if pl_fade < 0.0:
		var st := out_deck.stream
		if st == null:
			return
		var left := st.get_length() - out_deck.get_playback_position()
		if left <= XFADE or not out_deck.playing:
			pl_fade = 0.0
			pl_index = (pl_index + 1) % playlist.size()
			_pl_play(in_deck, playlist[pl_index], 0.0)
		return
	pl_fade += dt * rate
	var f := clampf(pl_fade / XFADE, 0.0, 1.0)
	out_deck.volume_db = linear_to_db(maxf(0.0001, g * (1.0 - f)))
	in_deck.volume_db = linear_to_db(maxf(0.0001, g * f))
	if f >= 1.0:
		out_deck.stop()
		decks.reverse()
		pl_fade = -1.0

func set_rate(r: float) -> void:
	r = maxf(0.05, r)
	for d in decks:
		d.pitch_scale = d.pitch_scale / rate * r
	rate = r

func stop() -> void:
	for d in decks:
		d.stop()
	current = -1
	plan = {}
	playlist = []
	pl_index = -1
	pl_fade = -1.0

func _process(dt: float) -> void:
	if not playlist.is_empty():
		_pl_tic(dt)
		return
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
		in_deck.pitch_scale = plan.rate * rate
		in_deck.volume_db = linear_to_db(0.0001)
		in_deck.play()
		plan.started = true
	if plan.started:
		var f: float = clampf((_clock - plan.out) / (plan.fade_end - plan.out), 0.0, 1.0)
		out_deck.volume_db = linear_to_db(maxf(0.0001, g * (1.0 - f)))
		in_deck.volume_db = linear_to_db(maxf(0.0001, g * f))
		var r: float = clampf((_clock - plan.fade_end) / (plan.rate_end - plan.fade_end), 0.0, 1.0)
		in_deck.pitch_scale = lerpf(plan.rate, 1.0, r) * rate
		if _clock >= plan.fade_end and out_deck.playing:
			out_deck.stop()
		if _clock >= plan.rate_end:
			# the incoming deck is the outgoing one now
			decks.reverse()
			current = plan.next
			plan = {}
