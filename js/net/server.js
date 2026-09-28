/* =====================================================================
   MEWD — the host: an authoritative simulation behind a message interface

   A SimServer owns one Game and the clients talking to it. It does not
   care where it is running: the dedicated server (tools/server.mjs)
   runs one in Node with no screen at all, and the app shell will run
   one inside the hosting player's own game, which is how ANY CLIENT CAN
   BE A SERVER — hosting is this object plus a socket to listen on.

   WHAT IT DOES, as of step three of the plan:
     - the handshake: hello → welcome (the map as a seed) or refused
     - up to MAX_PLAYERS lines, and a refusal for the seventeenth
     - A PLAYER EACH: every client that is welcomed gets its own Player
       in the world, on a side, on a pad (js/net/match.js), with its own
       session its commands are queued in, one applied per tic
     - the tic, at TICRATE, off its own clock or stepped by hand, and
       the match's after it: respawns, the spawn guard, the end of a
       round
     - THE REWIND, which is what makes a hit on a LAN a hit: see below
     - a snapshot every SNAP_EVERY tics, per client: all of you, the
       others as little as drawing them takes, what happened since the
       last one, and now and then the score

   THE PLAYER THE MAP STARTS WITH IS PUT ASIDE. The map's START is where
   a game on its own puts its one player, and on a host nobody is that
   player: it is left out of game.players, so nothing shoots it, walks
   into it or ticks it, and it stays only as the `player` the rest of
   the world's code has always been able to lean on.

   THE REWIND. A client draws the others a little in the past — it has
   to, to have two snapshots to draw between (js/net/remote.js) — so
   the player in its sights is where that player WAS, a tenth of a
   second ago. Each command says which host tic it was drawn at
   (`seen`), and while the host runs that command's tic it puts every
   OTHER player back where they were at that tic, lets the shot happen,
   and puts them forward again. So what you hit is what you saw, up to
   MAX_REWIND tics of it, which is more than any LAN will ask for.
   ===================================================================== */

import { PROTOCOL, MAX_PLAYERS, decode, encode } from './protocol.js';
import { HostSession } from './session.js';
import { Match } from './match.js';

export const TICRATE = 35;
export const SNAP_EVERY = 3;          // about twelve a second
export const SCORE_EVERY = 35;        // the whole table, once a second
export const MAX_REWIND = 12;         // a third of a second
const HISTORY = 48;                   // tics of where everybody was

const r3 = v => Math.round(v * 1000) / 1000;
const r5 = v => Math.round(v * 100000) / 100000;

export class SimServer {
  /**
   * @param {object} o
   *   game        a Game, built for `map`
   *   map         { kind, seed, opts } — what the welcome tells a client to build
   *   maxPlayers  the most lines at once
   *   rules       overrides for the match's RULES (js/net/match.js)
   *   log         a function for the few things worth saying
   */
  constructor({ game, map, maxPlayers = MAX_PLAYERS, rules = {}, log = () => {} }) {
    this.game = game;
    this.map = map;
    this.maxPlayers = maxPlayers;
    this.log = log;
    this.clients = new Map();          // id → { id, name, transport, player, welcomed }
    this.nextId = 1;
    /* the map's own player, put aside — see the top of the file */
    game.players = game.players.filter(p => p !== game.player);
    game.player.shootable = false;
    this.match = new Match(game, { rules, seed: map.seed });
    /* where everybody was, a ring of HISTORY tics per player */
    this.history = new Map();          // player → [{ tic, x, y, z, dead }]
    game.rewind = (p, cmd) => this.rewind(p, cmd);
    this.rewinds = 0;
    this.snaps = 0;
    this.timer = null;
  }

  /** A new line, from whatever transport it came in on. */
  accept(transport) {
    const c = { id: 0, name: '', transport, welcomed: false, player: null };
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
      c.name = String(m.name || `PLAYER ${c.id}`).replace(/[^\x20-\x7e]/g, '').slice(0, 16) || `PLAYER ${c.id}`;
      c.welcomed = true;
      c.player = this.match.join({ id: c.id, name: c.name });
      c.player.session = new HostSession();
      this.clients.set(c.id, c);
      this._send(c, { t: 'welcome', v: PROTOCOL, id: c.id, team: c.player.team, mode: this.match.mode,
                      map: this.map, tic: this.game.tics, rate: TICRATE, score: this.match.table() });
      this.log(`${c.name} joined${c.player.team >= 0 ? ' team ' + this.match.teams[c.player.team].name : ''} (${this.clients.size}/${this.maxPlayers})`);
      return;
    }
    if (m.t === 'cmd') { c.player.session.push(m.cmd); return; }
    if (m.t === 'ping') { c.player.ping = Math.max(0, Math.min(9999, m.rtt | 0)); this._send(c, { t: 'pong', n: m.n }); return; }
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
    this.match.leave(c.player);
    this.history.delete(c.player);
    this.log(`${c.name} left (${this.clients.size}/${this.maxPlayers})`);
  }

  /** The client driving `p`, or null. */
  clientOf(p) {
    for (const c of this.clients.values()) if (c.player === p) return c;
    return null;
  }

  /* ---- the rewind ---------------------------------------------------- */
  /** Called by Game.tic before `p` runs `cmd`: put the others where the
   *  sender saw them, and return what puts them back. Only for a tic
   *  with the trigger down — nothing else asks where anybody is. */
  rewind(p, cmd) {
    if (!cmd.attack || !cmd.seen) return null;
    const g = this.game;
    const back = Math.min(MAX_REWIND, Math.max(0, g.tics - 1 - cmd.seen));
    if (!back) return null;
    const at = g.tics - 1 - back;
    const moved = [];
    for (const o of g.players) {
      if (o === p) continue;
      const h = this.history.get(o);
      if (!h) continue;
      const was = h.find(e => e.tic === at);
      /* somebody who was not there then, or was dead, stays as they are */
      if (!was || was.dead || o.dead) continue;
      moved.push([o, o.x, o.y, o.z]);
      o.x = was.x; o.y = was.y; o.z = was.z;
    }
    if (!moved.length) return null;
    this.rewinds++;
    return () => { for (const [o, x, y, z] of moved) { o.x = x; o.y = y; o.z = z; } };
  }

  _remember() {
    const g = this.game;
    for (const p of g.players) {
      let h = this.history.get(p);
      if (!h) this.history.set(p, h = []);
      h.push({ tic: g.tics, x: p.x, y: p.y, z: p.z, dead: p.dead });
      if (h.length > HISTORY) h.shift();
    }
  }

  /** One tic of the world, and a snapshot if one is due. */
  step() {
    this.game.tic();
    this.match.tic();
    this._remember();
    if (this.game.tics % SNAP_EVERY === 0) this.broadcastSnap();
  }

  /* ---- snapshots ------------------------------------------------------ */
  /** You, in full: enough for the client to put its own player exactly
   *  where the host has it and run its unacknowledged commands on top. */
  youFor(p) {
    return {
      x: r3(p.x), y: r3(p.y), z: r3(p.z), mx: r5(p.momx), my: r5(p.momy), mz: r5(p.momz), g: p.onGround ? 1 : 0,
      a: r5(p.angle), p: r5(p.pitch),
      h: Math.max(0, Math.ceil(p.health)), a1: Math.ceil(p.armour1), a2: Math.ceil(p.armour2),
      w: p.weapon, r: p.ammo.rounds | 0, d: p.dead ? 1 : 0, inv: p.invincible ? 1 : 0,
      n: p.spawns | 0, team: p.team, frags: p.frags,
      back: p.dead ? Math.max(0, (p.respawnAt || 0) - this.game.tics) : 0,
    };
  }

  /** Somebody else, as little as drawing them takes:
   *  [id, x, y, z, angle, pitch, flags, team] — flags 1 dead, 2 firing,
   *  4 spawn guard, 8 barrels turning. */
  otherFor(p) {
    const firing = p.firing && !!p.def.volley;
    return [p.id, r3(p.x), r3(p.y), r3(p.z), r5(p.angle), r5(p.pitch),
            (p.dead ? 1 : 0) | (firing ? 2 : 0) | (p.invincible ? 4 : 0) | (p.spin > 0 ? 8 : 0), p.team];
  }

  snapFor(c, ev, score) {
    const p = c.player;
    const others = [];
    for (const o of this.game.players) if (o !== p) others.push(this.otherFor(o));
    const s = { t: 'snap', tic: this.game.tics, ack: p.session.ack, you: this.youFor(p), others };
    if (ev.length) s.ev = ev;
    if (score) s.score = score;
    return s;
  }

  broadcastSnap() {
    const ev = this.match.events.splice(0);
    const score = ev.length || this.game.tics % SCORE_EVERY < SNAP_EVERY ? this.match.table() : null;
    for (const c of this.clients.values()) this._send(c, this.snapFor(c, ev, score));
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
