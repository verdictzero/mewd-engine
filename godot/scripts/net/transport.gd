## MEWD — transports: the pipe a message goes down (js/net/transport.js,
## and the socket half of tools/server.mjs).
##
## One interface, however the bytes travel:
##
##   send(data)       a String (a text frame, JSON) or a PackedByteArray (binary)
##   close()
##   on_message       Callable(data)
##   on_close         Callable()
##   open             true until it is closed
##   poll()           Godot's sockets are polled, not evented: whoever
##                    owns one calls this once a frame
##
## LOOPBACK is two ends of a pipe in one process — the tests. Delivery is
## immediate and in order, which is what makes a test of it deterministic.
##
## WEBSOCKET wraps Godot's WebSocketPeer, which speaks RFC 6455 exactly
## as the browser and tools/server.mjs's hundred lines do: a text frame
## for JSON, a binary frame for a command, masked from the client. So the
## same code joins a Node host, a Godot host, and a Godot host is joined
## by a browser. The LISTENER is TCPServer handing each connection to a
## WebSocketPeer to finish the HTTP upgrade (accept_stream).
class_name NetTransport

class Loopback extends RefCounted:
	var peer: Loopback = null
	var open := true
	var on_message := Callable()
	var on_close := Callable()
	var sent := 0

	## Two ends, joined.
	static func pair() -> Array:
		var a := Loopback.new()
		var b := Loopback.new()
		a.peer = b
		b.peer = a
		return [a, b]

	func send(data) -> void:
		if not open or peer == null or not peer.open:
			return
		sent += 1
		# a copy, as a real socket would hand over
		var out = data.duplicate() if data is PackedByteArray else data
		if peer.on_message.is_valid():
			peer.on_message.call(out)

	func close() -> void:
		if not open:
			return
		open = false
		if on_close.is_valid():
			on_close.call()
		var p := peer
		if p != null and p.open:
			p.open = false
			if p.on_close.is_valid():
				p.on_close.call()

	func poll() -> void:
		pass

class Ws extends RefCounted:
	var ws: WebSocketPeer
	var open := true
	var on_message := Callable()
	var on_close := Callable()
	var on_open := Callable()
	var queue: Array = []
	var _was_open := false
	var sent := 0

	## `peer` an open or opening WebSocketPeer, or null and a URL to open one to.
	func _init(peer: WebSocketPeer = null, url := "") -> void:
		ws = peer if peer != null else WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 18
		ws.outbound_buffer_size = 1 << 18
		ws.max_queued_packets = 4096
		if peer == null:
			if ws.connect_to_url(url) != OK:
				open = false
		else:
			_was_open = ws.get_ready_state() == WebSocketPeer.STATE_OPEN

	func send(data) -> void:
		if not open:
			return
		var st := ws.get_ready_state()
		# what is sent before the socket is up waits for it
		if st == WebSocketPeer.STATE_CONNECTING:
			queue.append(data)
		elif st == WebSocketPeer.STATE_OPEN:
			_put(data)

	func _put(data) -> void:
		sent += 1
		if data is String:
			ws.send_text(data)
		else:
			ws.send(data, WebSocketPeer.WRITE_MODE_BINARY)

	func poll() -> void:
		if ws == null:
			return
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN and not _was_open:
			_was_open = true
			for d in queue:
				_put(d)
			queue.clear()
			if on_open.is_valid():
				on_open.call()
		# everything that arrived, even on a line that is closing
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			var data = pkt.get_string_from_utf8() if ws.was_string_packet() else pkt
			if open and on_message.is_valid():
				on_message.call(data)
		if st == WebSocketPeer.STATE_CLOSED and open:
			open = false
			if on_close.is_valid():
				on_close.call()

	func close() -> void:
		if not open:
			return
		open = false
		ws.close(1000)
		# let the close frame out
		ws.poll()
		if on_close.is_valid():
			on_close.call()

## A TCP port that turns every connection into a Ws once its upgrade is done.
class Listener extends RefCounted:
	var server := TCPServer.new()
	var pending: Array = []            # [WebSocketPeer, deadline ms]
	var on_accept := Callable()        # Callable(Ws)
	var port := 0

	func listen(p: int, bind := "*") -> Error:
		var err := server.listen(p, bind)
		if err == OK:
			port = server.get_local_port()
		return err

	func poll() -> void:
		while server.is_connection_available():
			var tcp := server.take_connection()
			tcp.set_no_delay(true)
			var ws := WebSocketPeer.new()
			ws.inbound_buffer_size = 1 << 18
			ws.outbound_buffer_size = 1 << 18
			ws.max_queued_packets = 4096
			if ws.accept_stream(tcp) == OK:
				pending.append([ws, Time.get_ticks_msec() + 5000])
		for i in range(pending.size() - 1, -1, -1):
			var ws: WebSocketPeer = pending[i][0]
			ws.poll()
			var st := ws.get_ready_state()
			if st == WebSocketPeer.STATE_OPEN:
				pending.remove_at(i)
				if on_accept.is_valid():
					on_accept.call(Ws.new(ws))
			elif st == WebSocketPeer.STATE_CLOSED or Time.get_ticks_msec() > int(pending[i][1]):
				ws.close()
				pending.remove_at(i)

	func stop() -> void:
		server.stop()
