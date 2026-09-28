/* =====================================================================
   MEWD — the game's side of a network client

   Step three of the LAN plan, the half that runs in the browser. A
   NetGame takes a Game built for the map the host named and a NetClient
   already welcomed, and from then on this page is ONE PLAYER IN
   SOMEBODY ELSE'S WORLD. Three jobs, and they are the three every
   network shooter since QuakeWorld has had to do:

   1. PREDICT YOURSELF. Your own player moves the moment you press, run
      by this page's own Game from the same commands the host is sent
      (NetSession) — a LAN is fast, but thirty milliseconds of mush on
      every keypress is still mush. When a snapshot arrives it says where
      the host has you as of the last command it got to (`ack`), and the
      page puts you THERE and runs every command it has sent since over
      the top again (reconcile). Both ends run the same arithmetic on
      the same rounded commands (js/net/ticcmd.js), so almost always
      that lands exactly where you already were and nothing moves; when
      it doesn't — somebody's rounds pushed you, a hedge was in a
      different place for them — you slide to the truth, or jump to it
      if it is far.

      THE HOST IS THE ONLY ONE WHO CAN HURT YOU. Your player here is
      invincible and its health is whatever the snapshot says; you die
      when the host says you did, and come back where it put you.

   2. DRAW THE OTHERS IN THE PAST. Everybody else arrives twelve times a
      second, so they are drawn INTERP_TICS behind the newest snapshot,
      sliding between the two either side of that moment — never
      guessing forward. Each is a PUPPET: a trooper off the sheets
      (SWAT for one side, the army for the other), an Actor with no mind
      of its own, walked, turned, fired and dropped by this file. How
      far back the others are drawn goes to the host in every command
      (`seen`), which is what lets it wind the world back for your shot
      (SimServer.rewind).

   3. SAY WHAT IS GOING ON. The kills go up as the gun's own notices
      (Game.toast), the end of a round as the big card, and the score is
      a line at the top of the screen and a table while TAB is held.

   WHAT IS NOT SHARED YET is the rest of the world. A crate, a fuel can,
   the fire: each page runs its own, and what your rounds and the
   others' rounds do to them is what they do to them here. The players
   and the score are the host's; the scenery is only very probably the
   same.
   ===================================================================== */

import { newCmd, fromInput } from './ticcmd.js';
import { renew, topUp, RULES } from './match.js';
import { stateOf } from '../states.js';
import { Actor } from '../actor.js';
import { TICRATE, angleNorm } from '../util.js';
import { MAX_PITCH } from '../player.js';

export const INTERP_TICS = 5;         // a snapshot and a half behind: two to draw between, and one late
export const SNAP_FAR = 96;           // a correction bigger than this is a jump, not a slide
const HISTORY = 128;                  // commands kept for replay, well over any LAN's round trip
const TEAM_TROOP = ['SWAT', 'ARMY'];

const HANDS_OFF = { look: { x: 0, y: 0 }, move: { x: 0, y: 0 } };

/** Where the player's command comes from on a network client: this
 *  page's input, as ever, numbered, stamped with the tic the others are
 *  being drawn at, sent, and kept for the replay. */
export class NetSession {
  constructor(net) { this.net = net; this.kind = 'net'; this.seq = 0; this.last = newCmd(); }
  cmd(game) {
    const c = fromInput(game.paused ? HANDS_OFF : game.input, ++this.seq, this.last);
    c.seen = this.net.seenTic();
    this.net.sent(c);
    return c;
  }
}

/* a copy that owns its own look and move */
const copyCmd = c => ({ ...c, look: { ...c.look }, move: { ...c.move } });

export class NetGame {
  /**
   * @param {Game} game       built for client.map
   * @param {NetClient} client already welcomed
   * @param {object} o
   *   now     a clock in ms (performance.now in the page)
   *   board   false for no scoreboard (the tests)
   */
  constructor(game, client, { now = () => performance.now(), board = true } = {}) {
    this.game = game;
    this.client = client;
    this.now = now;
    this.session = new NetSession(this);
    this.history = new Map();       // seq → { cmd, angle, pitch, rounds }
    this.puppets = new Map();       // id → { a, buf, walked, firing, loop, dead }
    this.lastTic = client.welcome?.tic || 0;
    this.lastAt = now();
    this.spawnN = -1;
    this.corrections = 0;
    this.biggest = 0;
    this.score = client.score;
    this.mode = client.welcome?.mode || 'dm';
    this.lost = null;
    game.session = this.session;
    game.net = this;
    /* the rules on this side are only the ones drawing needs: who is on
       whose side. Deaths are the host's business, so a death here says
       nothing — see reconcile */
    game.rules = {
      friendly: (a, b) => this.mode === 'tdm' && a !== b && a?.team >= 0 && a.team === b?.team,
      died: () => {},
      scale: (from, to, amount) => amount,
    };
    const p = game.player;
    p.id = client.id; p.team = client.team;
    p.invincible = true;
    p.owned = {};
    for (const w of RULES.loadout) p.owned[w] = true;
    p.weapon = RULES.loadout[0];
    p.health = RULES.health; p.armour1 = RULES.armour1; p.armour2 = RULES.armour2;
    client.onsnap = s => this.onSnap(s);
    client.onclose = why => { this.lost = why; game.setBigMessage?.(`DISCONNECTED: ${String(why).toUpperCase()}`, 1e9); };
    this.board = board && typeof document !== 'undefined' ? new NetBoard(this) : null;
  }

  /* ---- the clock ----------------------------------------------------- */
  /** The host's tic now, as near as this page can tell: the newest
   *  snapshot's, plus the time since it arrived, and never far past it. */
  hostTic() {
    const ahead = Math.min(2 * 3, (this.now() - this.lastAt) * TICRATE / 1000);
    return this.lastTic + ahead;
  }
  /** The host tic the others are being drawn at. */
  drawTic() { return this.hostTic() - INTERP_TICS; }
  seenTic() { return Math.max(0, Math.round(this.drawTic())); }

  /* ---- commands --------------------------------------------------------- */
  sent(c) {
    this.history.set(c.tic, { cmd: copyCmd(c), angle: 0, pitch: 0, rounds: 0 });
    if (this.history.size > HISTORY) this.history.delete(this.history.keys().next().value);
    this.client.send(c);
  }

  /** After the page's tic: what the command just run left the player
   *  looking at, for the replay; and the puppets' own tic. */
  tic() {
    const p = this.game.player;
    /* the same top-up the host gives, so the prediction fires when the host does */
    if (RULES.infiniteAmmo) topUp(p);
    const h = this.history.get(this.session.seq);
    if (h) { h.angle = p.angle; h.pitch = p.pitch; h.rounds = p.ammo.rounds; }
    for (const pup of this.puppets.values()) this._puppetTic(pup);
  }

  /* ---- a snapshot ---------------------------------------------------------- */
  onSnap(s) {
    if (s.tic < this.lastTic) return;         // late, and superseded
    this.lastTic = s.tic;
    this.lastAt = this.now();
    this.reconcile(s.you, s.ack);
    this._others(s.tic, s.others || []);
    if (s.ev) for (const e of s.ev) this._event(e);
    if (s.score) this.score = s.score;
    this.board?.update();
  }

  /** Put the player where the host has it and run what it has not seen
   *  yet over the top. See the top of the file. */
  reconcile(you, ack) {
    const g = this.game, p = g.player, lv = g.level;
    if (!you) return;
    this.team = you.team;
    p.team = you.team; p.frags = you.frags;
    /* A NEW LIFE: the host has put you on a pad. Start again from its
       word for everything, and look where it says. */
    const fresh = you.n !== this.spawnN;
    if (fresh) {
      this.spawnN = you.n;
      renew(p, you.x, you.y, you.a, RULES);
      p.invincible = true;
      g.bigMessage = null;
    }
    /* what the host says of you, whatever the page thinks */
    const was = p.health + p.armour1 + p.armour2;
    p.health = you.h; p.armour1 = you.a1; p.armour2 = you.a2;
    const now = you.h + you.a1 + you.a2;
    if (now < was && !you.d) { p.damageFlash = Math.min(16, 5 + (was - now) * 0.3); g.onPlayerHurt?.(was - now); }
    p.respawnIn = you.back;
    const h = this.history.get(ack);
    if (h) p.ammo.rounds = Math.max(0, Math.min(p.maxAmmo.rounds, you.r + (p.ammo.rounds - h.rounds)));
    for (const k of [...this.history.keys()]) if (k <= ack) this.history.delete(k); else break;
    /* WHERE THE HOST WILL HAVE YOU LOOKING once it has run what is in
       flight: its angle, and every turn since. The same as this page's
       to the last bit, unless this is a new life (a new pad, a new
       heading) or the host had to fold commands together — and then
       the page takes the host's, and so does the replay below. */
    let yaw = you.a, pitch = you.p;
    for (const [, e] of this.history) {
      yaw = angleNorm(yaw - e.cmd.look.x);
      pitch = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, pitch - e.cmd.look.y));
    }
    if (fresh || Math.abs(angleNorm(yaw - p.angle)) > 1e-3 || Math.abs(pitch - p.pitch) > 1e-3) {
      let y2 = you.a, p2 = you.p;
      for (const [, e] of this.history) {
        y2 = angleNorm(y2 - e.cmd.look.x); p2 = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, p2 - e.cmd.look.y));
        e.angle = y2; e.pitch = p2;
      }
      p.angle = yaw; p.pitch = pitch;
      this.turned = (this.turned || 0) + 1;
    }
    if (you.d) {
      if (!p.dead) { p.x = you.x; p.y = you.y; p.die(); }
      return;
    }
    if (p.dead) return;                        // until the host says where you are again

    /* THE REPLAY. Keep what is only the camera's — the bob, the eye's
       height, the turn — and run the movement again from the host's
       state through every command it has not answered. */
    const keep = { viewZ: p.viewZ, bob: p.bob, bobPhase: p.bobPhase, lookRate: p.lookRate, pitchRate: p.pitchRate,
                   angle: p.angle, pitch: p.pitch };
    const ox = p.x, oy = p.y, oz = p.z;
    this._takeBody(you);
    for (const [, e] of this.history) {
      p.angle = e.angle; p.pitch = e.pitch;
      p.move(e.cmd);
    }
    Object.assign(p, keep);
    const err = Math.hypot(p.x - ox, p.y - oy, p.z - oz);
    if (err > 0.01) {
      this.corrections++;
      this.biggest = Math.max(this.biggest, err);
      /* small: slide a third of the way now and the next snapshot does
         the rest. Big: it was never where you thought. */
      if (err < SNAP_FAR) {
        const k = 0.35;
        p.x = ox + (p.x - ox) * k; p.y = oy + (p.y - oy) * k; p.z = oz + (p.z - oz) * k;
        const sec = lv.sectorAt(p.x, p.y, p.sector);
        if (sec) p.sector = sec.above === null ? sec : lv.spanIn(sec, p.z);
      }
    }
  }

  _takeBody(you) {
    const p = this.game.player, lv = this.game.level;
    p.x = you.x; p.y = you.y; p.z = you.z;
    p.momx = you.mx; p.momy = you.my; p.momz = you.mz; p.onGround = !!you.g;
    const sec = lv.sectorAt(p.x, p.y, p.sector);
    if (sec) p.sector = sec.above === null ? sec : lv.spanIn(sec, p.z);
  }

  /* ---- the others ------------------------------------------------------------ */
  _others(tic, list) {
    const here = new Set();
    for (const [id, x, y, z, a, pitch, f, team] of list) {
      here.add(id);
      let pup = this.puppets.get(id);
      if (!pup) pup = this._puppet(id, team, x, y, z, a);
      pup.buf.push({ tic, x, y, z, a, pitch, f });
      if (pup.buf.length > 24) pup.buf.shift();
      pup.team = team;
    }
    for (const [id, pup] of this.puppets) if (!here.has(id)) this._drop(id, pup);
  }

  _puppet(id, team, x, y, z, a) {
    const g = this.game;
    const type = TEAM_TROOP[team === 1 ? 1 : 0];
    const act = new Actor(g, type, x, y, a);
    act.puppet = true;
    act.netId = id;
    act.team = team;
    /* no mind: it walks, turns, fires and falls because this file says
       so, and a round from this page marks it without hurting it — the
       host decides what a hit did */
    act.monster = false;
    act.damage = () => {};
    act.z = z;
    act.state = stateOf(`${type}_STAND`);
    act.stateTics = -1;
    g.actors.push(act);
    const pup = { id, a: act, type, buf: [], walked: 0, movedAt: 0, firing: false, spin: false, loop: null, dead: false, team, pitch: 0 };
    this.puppets.set(id, pup);
    return pup;
  }

  _drop(id, pup) {
    pup.loop?.stop();
    pup.a.remove();
    this.puppets.delete(id);
  }

  /** Every frame: slide each of them to where they were at drawTic. */
  frame() {
    const t = this.drawTic();
    const g = this.game, lv = g.level;
    for (const pup of this.puppets.values()) {
      const b = pup.buf;
      if (!b.length) continue;
      let s0 = b[0], s1 = b[0];
      for (let i = 0; i < b.length; i++) {
        if (b[i].tic <= t) s0 = b[i];
        if (b[i].tic >= t) { s1 = b[i]; break; }
        s1 = b[i];
      }
      const span = s1.tic - s0.tic;
      let k = span > 0 ? Math.max(0, Math.min(1, (t - s0.tic) / span)) : 0;
      const a = pup.a;
      /* A JUMP IS NOT A WALK: a respawn, or anything else that moved them
         further between two snapshots than anybody can run, is drawn
         where they were until it is drawn where they are */
      if (Math.hypot(s1.x - s0.x, s1.y - s0.y) > SNAP_FAR * 1.5) k = k < 1 ? 0 : 1;
      const nx = s0.x + (s1.x - s0.x) * k, ny = s0.y + (s1.y - s0.y) * k;
      const step = Math.hypot(nx - a.x, ny - a.y);
      pup.walked += step;
      if (step > 0.05) pup.movedAt = this.now();
      a.x = nx; a.y = ny; a.z = s0.z + (s1.z - s0.z) * k;
      a.angle = angleNorm(s0.a + angleNorm(s1.a - s0.a) * k);
      pup.pitch = s0.pitch + (s1.pitch - s0.pitch) * k;
      const sec = lv.sectorAt(a.x, a.y, a.sector);
      if (sec) a.sector = sec.above === null ? sec : lv.spanIn(sec, a.z);
      g.blockmap?.moved(a);
      /* and what they are doing, as of the nearer of the two */
      const f = (k < 0.5 ? s0 : s1).f;
      this._look(pup, f);
    }
  }

  _look(pup, f) {
    const a = pup.a, g = this.game;
    const dead = !!(f & 1);
    pup.firing = !!(f & 2) && !dead;
    pup.guard = !!(f & 4);
    if (dead !== pup.dead) {
      pup.dead = dead;
      a.dead = dead;
      a.solid = !dead;
      if (dead) {
        pup.loop?.stop(); pup.loop = null;
        g.sound?.play(a.info.deathSound, a);
        a.state = stateOf(`${pup.type}_DIE1`); a.stateTics = a.state.tics;
      } else {
        a.state = stateOf(`${pup.type}_STAND`); a.stateTics = -1;
      }
    }
    if (dead) return;
    if (pup.firing && !pup.loop) pup.loop = g.sound?.loop('minigunloop', a) || null;
    else if (!pup.firing && pup.loop) { pup.loop.stop(); pup.loop = null; }
    /* the frame: the muzzle's two while the rounds go, else a stride of
       the walk every dozen units, else standing */
    let name;
    if (pup.firing) name = (g.tics >> 1) & 1 ? 'ATK2' : 'ATK1';
    else if (this.now() - pup.movedAt < 150) name = `RUN${(Math.floor(pup.walked / 12) % 8) + 1}`;
    else name = 'STAND';
    const st = stateOf(`${pup.type}_${name}`);
    if (st && a.state !== st) { a.state = st; a.stateTics = -1; }
  }

  _puppetTic(pup) {
    const a = pup.a, g = this.game;
    /* the fall plays out on its own, a state at a time */
    if (pup.dead && a.stateTics > 0 && --a.stateTics === 0 && a.state.next) {
      a.state = stateOf(a.state.next); a.stateTics = a.state.tics;
    }
    /* THEIR ROUNDS, for the look of it: what the host decided is in the
       snapshots, and what the page draws is the same gun going off from
       where they are drawn — the holes, the tracers and the blood are
       this page's, and hurt nothing */
    if (pup.firing && !pup.dead) {
      const from = { x: a.x + Math.cos(a.angle) * 16, y: a.y + Math.sin(a.angle) * 16, z: a.z + 40 };
      for (let i = 0; i < 2; i++) {
        const ang = a.angle + (Math.random() - 0.5) * 0.11, pt = pup.pitch + (Math.random() - 0.5) * 0.08;
        g.hitscan(a, ang, 2400, 0, { shot: true, hot: true, pitch: pt, from });
        if (i === 0 && g.tracers && g.lastHit) g.tracers.spawn(from, g.lastHit);
      }
    }
  }

  /* ---- what happened -------------------------------------------------------- */
  nameOf(id) {
    if (id === this.client.id) return 'YOU';
    return this.score?.players?.find(p => p.id === id)?.name || `PLAYER ${id}`;
  }

  _event(e) {
    const g = this.game;
    if (e.k === 'frag') {
      const v = this.nameOf(e.of);
      g.toast?.(e.by ? `${this.nameOf(e.by)} FRAGGED ${v}` : `${v} DIED`);
    } else if (e.k === 'join') {
      if (e.id !== this.client.id) g.toast?.(`${e.name} JOINED${e.team >= 0 ? ' ' + (e.team ? 'B' : 'A') : ''}`);
      /* the table has them from the next score; say their name before then */
      if (this.score?.players && !this.score.players.some(p => p.id === e.id))
        this.score.players.push({ id: e.id, name: e.name, team: e.team, frags: 0, deaths: 0, ping: 0 });
    } else if (e.k === 'leave') g.toast?.(`${e.name} LEFT`);
    else if (e.k === 'over') g.setBigMessage?.(`${String(e.winner).toUpperCase()} WINS`, 8 * TICRATE);
    else if (e.k === 'round') { g.bigMessage = null; g.toast?.(`ROUND ${e.n}`); }
  }

  close() {
    for (const [id, pup] of this.puppets) this._drop(id, pup);
    this.client.close();
    this.board?.remove();
  }
}

/* ---- the score, on the screen -------------------------------------------- */
class NetBoard {
  constructor(net) {
    this.net = net;
    this.el = document.createElement('div');
    this.el.id = 'netboard';
    this.el.style.cssText = 'position:fixed;top:8px;left:50%;transform:translateX(-50%);z-index:30;pointer-events:none;' +
      'font:12px/1.35 monospace;color:#e8e0c8;text-shadow:0 1px 0 #000,0 0 3px #000;text-align:center;white-space:pre';
    this.line = document.createElement('div');
    this.table = document.createElement('div');
    this.table.style.cssText = 'display:none;margin-top:6px;padding:8px 12px;background:rgba(0,0,0,.72);text-align:left';
    this.el.append(this.line, this.table);
    document.body.appendChild(this.el);
    this.held = false;
    this._down = e => { if (e.code === 'Tab') { e.preventDefault(); this.held = true; this.update(); } };
    this._up = e => { if (e.code === 'Tab') { this.held = false; this.update(); } };
    addEventListener('keydown', this._down);
    addEventListener('keyup', this._up);
    this.update();
  }

  update() {
    const n = this.net, s = n.score, p = n.game.player;
    if (!s) { this.line.textContent = 'CONNECTED'; return; }
    const dead = p.dead ? `   RESPAWN IN ${Math.ceil((p.respawnIn || 0) / TICRATE)}` : '';
    const ping = `   ${Math.round(n.client.rtt)}MS`;
    if (s.teams) {
      const mine = n.team ?? p.team;
      const [a, b] = s.teams;
      this.line.textContent = `${mine === 0 ? '>' : ''}${a.name} ${a.score}  —  ${b.score} ${b.name}${mine === 1 ? '<' : ''}   TO ${s.limit}${dead}${ping}`;
    } else {
      const me = s.players.find(q => q.id === n.client.id);
      this.line.textContent = `FRAGS ${me?.frags ?? 0}   TO ${s.limit}${dead}${ping}`;
    }
    this.table.style.display = this.held || s.over ? 'block' : 'none';
    if (this.held || s.over) {
      const rows = [...s.players].sort((x, y) => (x.team - y.team) || (y.frags - x.frags));
      const pad = (v, w) => String(v).padEnd(w).slice(0, w);
      this.table.textContent = `${pad('NAME', 17)}${s.teams ? 'SIDE ' : ''}FRAGS DEATHS PING\n` +
        rows.map(r => `${r.id === n.client.id ? '>' : ' '}${pad(r.name, 16)}${s.teams ? pad(s.teams[r.team]?.name ?? '-', 5) : ''}${pad(r.frags, 6)}${pad(r.deaths, 7)}${r.ping}`).join('\n') +
        (s.over ? `\n\n${s.over.winner} WINS — NEXT ROUND IN ${Math.ceil(s.over.left / TICRATE)}` : '');
    }
  }

  remove() {
    removeEventListener('keydown', this._down);
    removeEventListener('keyup', this._up);
    this.el.remove();
  }
}
