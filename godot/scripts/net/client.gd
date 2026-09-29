## MEWD — a client's end of the line (js/net/client.js).
##
## Says hello, learns who it is and which map to build, sends a command a
## tic, keeps the snapshots, and measures the line. What it does NOT do is
## play: remote.gd is the game's side of a network client — prediction,
## the others, the score — and drives one of these. The tests drive one
## directly.
class_name NetClient
extends RefCounted

const PING_EVERY := 2000       # ms

var transport
var now_fn: Callable
var id := 0
var team := -1
var map = null
var welcome = null
var refused = null
var snap = null
var snaps := 0
var score = null
var rtt := 0.0
var closed := false
var bye = null
var on_welcome := Callable()
var on_snap := Callable()
var on_close := Callable()
var _ping_at := -1000000

func _init(t, name := "PLAYER", now := Callable()) -> void:
	transport = t
	now_fn = now if now.is_valid() else func() -> int: return Time.get_ticks_msec()
	t.on_message = _message
	t.on_close = _closed
	t.send(NetProtocol.encode({"t": "hello", "v": NetProtocol.PROTOCOL, "name": name}))

func _closed() -> void:
	closed = true
	if on_close.is_valid():
		var why = bye if bye != null else (refused if refused != null else "the line went")
		on_close.call(why)

func _message(data) -> void:
	var m := NetProtocol.decode(data)
	if m.is_empty():
		return
	match str(m.t):
		"welcome":
			welcome = m
			id = int(m.id)
			team = int(m.get("team", -1)) if m.get("team") != null else -1
			map = m.map
			score = m.get("score")
			if on_welcome.is_valid():
				on_welcome.call(m)
		"refused":
			refused = str(m.get("why", ""))
		"bye":
			bye = str(m.get("why", ""))
		"pong":
			var r: float = float(now_fn.call()) - float(m.get("n", 0))
			if r >= 0.0 and r < 60000.0:
				rtt = rtt * 0.7 + r * 0.3 if rtt > 0.0 else r
		"snap":
			snap = m
			snaps += 1
			if m.get("score") != null:
				score = m.score
			if on_snap.is_valid():
				on_snap.call(m)

## This tic's command, to the host — and now and then, a ping.
func send(cmd: Dictionary) -> void:
	if welcome == null or closed:
		return
	transport.send(NetProtocol.encode_cmd(cmd))
	var t: int = int(now_fn.call())
	if t - _ping_at >= PING_EVERY:
		_ping_at = t
		transport.send(NetProtocol.encode({"t": "ping", "n": t, "rtt": roundi(rtt)}))

func poll() -> void:
	transport.poll()

func close() -> void:
	if not closed:
		transport.send(NetProtocol.encode({"t": "bye", "why": "left"}))
		transport.close()
