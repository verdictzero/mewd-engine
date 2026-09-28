/* =====================================================================
   MEWD — a client's end of the line

   Says hello, learns who it is and which map to build, sends a command
   a tic, keeps the snapshots, and measures the line. What it does NOT
   do is play: js/net/remote.js is the game's side of a network client
   — prediction, the others, the score — and drives one of these. The
   tests drive one directly.
   ===================================================================== */

import { PROTOCOL, decode, encode, encodeCmd } from './protocol.js';

export const PING_EVERY = 2000;       // ms

export class NetClient {
  constructor(transport, { name = 'PLAYER', now = () => Date.now() } = {}) {
    this.transport = transport;
    this.now = now;
    this.id = 0;
    this.team = -1;
    this.map = null;
    this.welcome = null;
    this.refused = null;
    this.snap = null;
    this.snaps = 0;
    this.score = null;
    this.rtt = 0;
    this.closed = false;
    this.bye = null;
    this.onwelcome = null;
    this.onsnap = null;
    this.onclose = null;
    this._pingAt = 0;
    transport.onmessage = data => this._message(data);
    transport.onclose = () => { this.closed = true; this.onclose?.(this.bye || this.refused || 'the line went'); };
    transport.send(encode({ t: 'hello', v: PROTOCOL, name }));
  }

  _message(data) {
    const m = decode(data);
    if (!m) return;
    if (m.t === 'welcome') {
      this.welcome = m; this.id = m.id; this.team = m.team ?? -1; this.map = m.map; this.score = m.score || null;
      this.onwelcome?.(m);
    } else if (m.t === 'refused') this.refused = m.why;
    else if (m.t === 'bye') this.bye = m.why;
    else if (m.t === 'pong') {
      const rtt = this.now() - m.n;
      if (rtt >= 0 && rtt < 60000) this.rtt = this.rtt ? this.rtt * 0.7 + rtt * 0.3 : rtt;
    } else if (m.t === 'snap') {
      this.snap = m; this.snaps++;
      if (m.score) this.score = m.score;
      this.onsnap?.(m);
    }
  }

  /** This tic's command, to the host — and now and then, a ping. */
  send(cmd) {
    if (!this.welcome || this.closed) return;
    this.transport.send(encodeCmd(cmd));
    const t = this.now();
    if (t - this._pingAt >= PING_EVERY) {
      this._pingAt = t;
      this.transport.send(encode({ t: 'ping', n: t, rtt: Math.round(this.rtt) }));
    }
  }

  close() { if (!this.closed) { this.transport.send(encode({ t: 'bye', why: 'left' })); this.transport.close(); } }
}
