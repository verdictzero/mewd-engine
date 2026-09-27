/* =====================================================================
   DEWM — the host: an authoritative simulation behind a message interface

   A SimServer owns one Game and the clients talking to it. It does not
   care where it is running: the dedicated server (tools/server.mjs)
   runs one in Node with no screen at all, and the app shell will run
   one inside the hosting player's own game, which is how ANY CLIENT CAN
   BE A SERVER — hosting is this object plus a socket to listen on.

   WHAT IT DOES TODAY, which is step one of the plan:
     - the handshake: hello → welcome (the map as a seed) or refused
     - up to MAX_PLAYERS lines, and a refusal for the seventeenth
     - each client's commands, buffered, one applied per tic
     - the tic, at TICRATE, off its own clock or stepped by hand
     - a snapshot every SNAP_EVERY tics: the tic, the last command of
       yours it applied, and where your player is

   WHAT IT DOES NOT DO YET is give each client a player of their own.
   The game still has one player, and the first client to arrive drives
   it (the others are connected and watching the tic go by). Many
   players is step three, and it is a change to Game rather than to this
   file: the sessions become one per player, and the snapshot a list.
   ===================================================================== */

import { PROTOCOL, MAX_PLAYERS, decode, encode } from './protocol.js';
import { HostSession } from './session.js';

export const TICRATE = 35;
export const SNAP_EVERY = 3;          // about twelve a second

export class SimServer {
  /**
   * @param {object} o
   *   game        a Game, built for `map` (its session is replaced)
   *   map         { kind, seed } — what the welcome tells a client to build
   *   maxPlayers  the most lines at once
   *   log         a function for the few things worth saying
   */
  constructor({ game, map, maxPlayers = MAX_PLAYERS, log = () => {} }) {
    this.game = game;
    this.map = map;
    this.maxPlayers = maxPlayers;
    this.log = log;
    this.clients = new Map();          // id → { id, name, transport, session, welcomed }
    this.nextId = 1;
    this.controller = null;            // the client driving the one player, for now
    this.session = new HostSession();
    game.session = this.session;
    this.snaps = 0;
    this.timer = null;
  }

  /** A new line, from whatever transport it came in on. */
  accept(transport) {
    const c = { id: 0, name: '', transport, welcomed: false };
    transport.onmessage = data => this._message(c, data);
    transport.onclose = () => this._gone(c);
    return c;
  }

  _send(c, msg) { c.transport.send(encode(msg)); }

  _message(c, data) {
    const m = decode(data);
    if (!m) return;
    if (!c.welcomed) {
      if (m.t !== 'hello') return;
      if (m.v !== PROTOCOL) return this._refuse(c, `protocol ${m.v}, host speaks ${PROTOCOL}`);
      if (this.clients.size >= this.maxPlayers) return this._refuse(c, `full: ${this.maxPlayers} players`);
      c.id = this.nextId++;
      c.name = String(m.name || `PLAYER ${c.id}`).slice(0, 24);
      c.welcomed = true;
      this.clients.set(c.id, c);
      if (!this.controller) this.controller = c;
      this._send(c, { t: 'welcome', v: PROTOCOL, id: c.id, map: this.map, tic: this.game.tics, rate: TICRATE,
                      controls: this.controller === c });
      this.log(`${c.name} joined (${this.clients.size}/${this.maxPlayers})`);
      return;
    }
    if (m.t === 'cmd') { if (c === this.controller) this.session.push(m.cmd); return; }
    if (m.t === 'bye') { c.transport.close(); }
  }

  _refuse(c, why) {
    this._send(c, { t: 'refused', why });
    this.log(`refused a client: ${why}`);
    c.transport.close();
  }

  _gone(c) {
    if (!c.welcomed || !this.clients.has(c.id)) return;
    this.clients.delete(c.id);
    this.log(`${c.name} left (${this.clients.size}/${this.maxPlayers})`);
    if (this.controller === c) {
      /* the next to have arrived takes the controls */
      this.controller = this.clients.values().next().value || null;
      this.session.queue.length = 0;
      if (this.controller) this._send(this.controller, { t: 'controls' });
    }
  }

  /** One tic of the world, and a snapshot if one is due. */
  step() {
    this.game.tic();
    if (this.game.tics % SNAP_EVERY === 0) this.broadcastSnap();
  }

  snapFor(c) {
    const p = this.game.player;
    return {
      t: 'snap', tic: this.game.tics, ack: c === this.controller ? this.session.ack : 0, players: this.clients.size,
      you: c === this.controller && p ? {
        x: +p.x.toFixed(3), y: +p.y.toFixed(3), z: +p.z.toFixed(3), angle: +p.angle.toFixed(5), pitch: +p.pitch.toFixed(5),
        health: p.health, weapon: p.weapon, dead: !!p.dead,
      } : null,
    };
  }

  broadcastSnap() {
    for (const c of this.clients.values()) this._send(c, this.snapFor(c));
    this.snaps++;
  }

  /** Run off a clock at TICRATE until stop(). For a host with no frame
   *  loop of its own to hang the tics on — the dedicated server. */
  start() {
    if (this.timer) return;
    const step = 1000 / TICRATE;
    let last = Date.now(), acc = 0;
    this.timer = setInterval(() => {
      const now = Date.now();
      acc += now - last; last = now;
      let n = 0;
      while (acc >= step && n < 6) { this.step(); acc -= step; n++; }
      if (n === 6) acc = 0;
    }, step / 2);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    for (const c of [...this.clients.values()]) { this._send(c, { t: 'bye', why: 'host closed' }); c.transport.close(); }
  }
}
