/* =====================================================================
   DEWM — a client's end of the line

   Says hello, learns who it is and which map to build, sends a command
   a tic, and keeps the latest snapshot. The game will drive one of
   these in step three — predicting its own player from the commands it
   has sent and correcting against `snap.you` at `snap.ack` — and today
   the tests and the dedicated server's own check drive it.
   ===================================================================== */

import { PROTOCOL, decode, encode, encodeCmd } from './protocol.js';

export class NetClient {
  constructor(transport, { name = 'PLAYER' } = {}) {
    this.transport = transport;
    this.id = 0;
    this.map = null;
    this.welcome = null;
    this.refused = null;
    this.snap = null;
    this.snaps = 0;
    this.controls = false;
    this.closed = false;
    this.onwelcome = null;
    this.onsnap = null;
    this.onclose = null;
    transport.onmessage = data => this._message(data);
    transport.onclose = () => { this.closed = true; this.onclose?.(); };
    transport.send(encode({ t: 'hello', v: PROTOCOL, name }));
  }

  _message(data) {
    const m = decode(data);
    if (!m) return;
    if (m.t === 'welcome') {
      this.welcome = m; this.id = m.id; this.map = m.map; this.controls = !!m.controls;
      this.onwelcome?.(m);
    } else if (m.t === 'refused') this.refused = m.why;
    else if (m.t === 'controls') this.controls = true;
    else if (m.t === 'snap') { this.snap = m; this.snaps++; this.onsnap?.(m); }
  }

  /** This tic's command, to the host. */
  send(cmd) { if (this.welcome && !this.closed) this.transport.send(encodeCmd(cmd)); }

  close() { if (!this.closed) { this.transport.send(encode({ t: 'bye', why: 'left' })); this.transport.close(); } }
}
