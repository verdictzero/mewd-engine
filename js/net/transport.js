/* =====================================================================
   MEWD — transports: the pipe a message goes down

   One interface, however the bytes travel:

     send(data)          a string or an ArrayBuffer
     close()
     onmessage = data => …
     onclose = () => …
     open                true until it is closed

   LOOPBACK is two ends of a pipe in one process — the single-player
   game talking to its own host, and the tests. Delivery is immediate
   and in order, which is also what makes a test of it deterministic.

   WEBSOCKET wraps a WebSocket — the browser's, Node's (22 has one), or
   the dedicated server's own (tools/server.mjs) — so the same client
   code joins a game in a page, in a test, or in the app shell.

   The shell's own sockets (the Tauri plugin, next) will be a third
   class with these five members, and nothing above this file will know.
   ===================================================================== */

export class LoopbackTransport {
  constructor() {
    this.peer = null;
    this.open = true;
    this.onmessage = null;
    this.onclose = null;
    this.sent = 0;
  }
  /** Two ends, joined. */
  static pair() {
    const a = new LoopbackTransport(), b = new LoopbackTransport();
    a.peer = b; b.peer = a;
    return [a, b];
  }
  send(data) {
    if (!this.open || !this.peer?.open) return;
    this.sent++;
    /* a copy of a buffer, as a real socket would hand over: the sender
       may reuse its own */
    const out = data instanceof ArrayBuffer ? data.slice(0) : data;
    this.peer.onmessage?.(out);
  }
  close() {
    if (!this.open) return;
    this.open = false;
    this.onclose?.();
    const p = this.peer;
    if (p?.open) { p.open = false; p.onclose?.(); }
  }
}

export class WebSocketTransport {
  /** `ws` is an open or opening WebSocket, or a URL to open one to. */
  constructor(ws) {
    this.ws = typeof ws === 'string' ? new WebSocket(ws) : ws;
    this.ws.binaryType = 'arraybuffer';
    this.open = true;
    this.onmessage = null;
    this.onclose = null;
    this.onopen = null;
    this.queue = [];
    this.ws.onmessage = e => this.onmessage?.(e.data);
    this.ws.onopen = () => { for (const d of this.queue) this.ws.send(d); this.queue.length = 0; this.onopen?.(); };
    this.ws.onclose = () => { if (this.open) { this.open = false; this.onclose?.(); } };
    this.ws.onerror = () => {};
  }
  send(data) {
    if (!this.open) return;
    /* what is sent before the socket is up waits for it */
    if (this.ws.readyState === 0) this.queue.push(data);
    else if (this.ws.readyState === 1) this.ws.send(data);
  }
  close() {
    if (!this.open) return;
    this.open = false;
    try { this.ws.close(); } catch { /* already gone */ }
    this.onclose?.();
  }
}
