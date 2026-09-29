## MEWD — the wire: what a client and a host say to each other
## (js/net/protocol.js). The SAME wire as the web build's, byte for byte,
## so a Godot client joins the Node host (tools/server.mjs) and a web
## page joins the Godot host (godot/scripts/net/host.gd).
##
## Two kinds of message, because they are two kinds of traffic:
##
##   COMMANDS are binary, small and constant — thirty-five a second from
##   every player — so they are bytes: a type byte and a TicCmd
##   (ticcmd.gd), eighteen bytes in all, in a binary WebSocket frame.
##
##   EVERYTHING ELSE is rare and shaped — a handshake, a snapshot, a
##   goodbye — so it is JSON, in a text frame.
##
## THE HANDSHAKE:
##   client → host   { t:'hello', v, name }
##   host → client   { t:'welcome', v, id, team, mode, map:{ kind, seed, opts }, tic, rate, score }
##                   or { t:'refused', why } and the line is closed
##   client → host   CMD packets, one a tic
##   host → client   { t:'snap', tic, ack, you:{…}, others:[…], ev:[…], score? }
##   client → host   { t:'ping', n, rtt }   and back   { t:'pong', n }
##   either          { t:'bye', why }
##
## THE MAP IS A SEED: every map a host offers is a pure function of one
## (maze.gd, jesse.gd — each the web build's generator, call for call),
## so the welcome carries two numbers and every client builds the level.
##
## JSON NUMBERS come back from Godot's parser as floats: an id or a tic
## read off a message is int()ed wherever it is used as one.
class_name NetProtocol

const PROTOCOL := 2          # 2: many players, and `seen` in the command
const MAX_PLAYERS := 16
const DEFAULT_PORT := 7777
const NET_PATH := "/net"
const MSG_CMD := 1

## A command, as the bytes that go on the wire.
static func encode_cmd(cmd: Dictionary) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(1 + TicCmd.CMD_BYTES)
	b.encode_u8(0, MSG_CMD)
	TicCmd.write(b, 1, cmd)
	return b

## Anything off the wire: bytes are binary, a String is JSON. Returns
## {t, …}, or an empty Dictionary for garbage — a host does not fall
## over because somebody sent it nonsense.
static func decode(data) -> Dictionary:
	if data is String:
		var j := JSON.new()
		if j.parse(data) != OK:
			return {}
		var m = j.data
		if m is Dictionary and m.get("t") is String:
			return m
		return {}
	if data is PackedByteArray:
		var b: PackedByteArray = data
		if b.size() >= 1 + TicCmd.CMD_BYTES and b[0] == MSG_CMD:
			return {"t": "cmd", "cmd": TicCmd.read(b, 1)}
	return {}

## A control message, as the string that goes on the wire.
static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg, "", false)

## ws://host:port/net from whatever was typed: `host`, `host:port`,
## `ws://host:port`, or a whole URL with its own path.
static func url_for(s: String) -> String:
	s = s.strip_edges()
	if s == "":
		s = "127.0.0.1:%d" % DEFAULT_PORT
	if not (s.begins_with("ws://") or s.begins_with("wss://")):
		s = "ws://" + s
	var rest := s.substr(s.find("://") + 3)
	if rest.find("/") < 0:
		if rest.find(":") < 0:
			s += ":%d" % DEFAULT_PORT
		s += NET_PATH
	return s
