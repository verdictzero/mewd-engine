/* =====================================================================
   MEWD — a match: the rules that hold between players

   Step three of the LAN plan. A host (js/net/server.js) makes one of
   these for its Game, and from then on the game has RULES: who is on
   whose side, where you come back when you die, what a death is worth,
   and when it is over. A game on its own never makes one, and every
   check in js/game.js that asks is a null test.

   TWO MODES, and the map decides which:

     TEAM DEATHMATCH   a map with teams in it — JESSE, whose two forts
                       each come with a row of spawn pads (world.pvp in
                       js/maps/jesse.js). You join the smaller side, you
                       come back on your own pads, your own side's
                       rounds go through you, and the side to TEAM_LIMIT
                       first takes it.
     DEATHMATCH        anything else — THE MAZE. Everybody against
                       everybody, spawns picked out of the open floor
                       (findSpawns), and the first to FRAG_LIMIT.

   THE NETWORK LOADOUT is the minigun. Every other gun in this game is
   a system built round one owner — the bore's lock, the lance's column,
   the launcher's seeker, the arc's chain, the streams out of the nozzle
   the screen is looking down — and the minigun is the one that is a
   hitscan and nothing else, which is the one the host can wind the
   world back for (SimServer.rewind). The rest follow as they learn to
   belong to somebody.
   ===================================================================== */

import { Player } from '../player.js';
import { TICRATE, dist2 } from '../util.js';

export const RULES = {
  fragLimit: 20,                 // deathmatch: first to this
  teamLimit: 40,                 // team deathmatch: first side to this
  respawnTics: 2 * TICRATE,      // down for this long at least
  guardTics: 2 * TICRATE,        // and nothing hurts you for this long after
  endTics: 8 * TICRATE,          // the scores stay up this long, and it starts again
  health: 100,
  armour1: 300,                  // the inner plate, and no outer one: 400 in all
  armour2: 0,
  loadout: ['MINIGUN'],
  /* WHAT A ROUND DOES TO A PERSON, against what it does to a shopper.
     The minigun was built to be absurd against a crowd: four rounds a
     tic at twenty-four to forty-eight, which through four hundred of
     somebody is three tics — a tenth of a second — from the barrels
     reaching speed. At a third it is eight or nine tics with every
     round landing, which the spread at any range makes a good deal
     more, and there is time to hear the spin-up and get round a hedge. */
  pvpScale: 0.35,
  /* NO PICKUPS, SO NO RUNNING OUT, at the user's request: every tank,
     belt and magazine is topped up every tic, and the refire latches
     never close. The self-filling budgets are a single-player design,
     and a match has nothing on the floor to refill them with. */
  infiniteAmmo: true,
};

/** Everything `p` carries, full, and no latch shut. */
export function topUp(p) {
  for (const k of Object.keys(p.maxAmmo)) p.ammo[k] = p.maxAmmo[k];
  p.dry = p.co2Dry = p.boreDry = p.beltDry = p.cellDry = p.rocketDry = p.voltDry = false;
}

/* what survives a respawn: who you are, and the score */
const KEEP = ['id', 'name', 'team', 'frags', 'deaths', 'session', 'ping', 'spawns'];

/* a small generator of its own, so the match's choices leave the
   world's (pRandom) exactly where they were */
const lcg = seed => () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);

/**
 * Standing room: points in the open with nothing within `clear` of them,
 * spread over the map. For a map that names no spawn pads.
 */
export function findSpawns(level, n = 24, { clear = 48, seed = 7 } = {}) {
  const [x0, y0, x1, y1] = level.bounds || [0, 0, 0, 0];
  const rnd = lcg(seed);
  const out = [];
  const spread = Math.max(96, Math.min(x1 - x0, y1 - y0) / (Math.sqrt(n) * 2));
  for (let tries = 0; tries < n * 60 && out.length < n; tries++) {
    const x = x0 + rnd() * (x1 - x0), y = y0 + rnd() * (y1 - y0);
    const s = level.sectorAt(x, y);
    if (!s || s.ceil - s.floor < 80) continue;
    let ok = true;
    for (let k = 0; k < 8 && ok; k++) {
      const a = k * Math.PI / 4;
      if (level.rayHitWall(x, y, s.floor + 30, x + Math.cos(a) * clear, y + Math.sin(a) * clear, s.floor + 30)) ok = false;
    }
    if (!ok) continue;
    if (out.some(([px, py]) => dist2(px, py, x, y) < spread * spread)) continue;
    out.push([Math.round(x), Math.round(y)]);
  }
  return out;
}

/**
 * Make `p` a fresh player standing at (x, y): everything a Player is
 * made with, but the same object, the same name and the same score, and
 * armed and armoured as the rules say. The host does this on a respawn;
 * a client does the same to its own player when the host says it has
 * been respawned (js/net/remote.js), so the two start from one state.
 */
export function renew(p, x, y, angle, R = RULES) {
  const fresh = new Player(p.game, x, y, angle);
  const keep = {};
  for (const k of KEEP) keep[k] = p[k];
  p.gunLoop?.stop();
  for (const k of Object.keys(p)) if (!(k in fresh)) delete p[k];
  Object.assign(p, fresh, keep);
  p.health = R.health; p.armour1 = R.armour1; p.armour2 = R.armour2;
  p.owned = {};
  for (const w of R.loadout) p.owned[w] = true;
  p.weapon = R.loadout[0];
  return p;
}

export class Match {
  /**
   * @param {Game} game
   * @param {object} o
   *   rules   overrides for RULES
   *   seed    for the spawn choices
   */
  constructor(game, { rules = {}, seed = 1 } = {}) {
    this.game = game;
    this.rules = { ...RULES, ...rules };
    this.rnd = lcg(seed >>> 0 || 1);
    const pvp = game.level.pvp;
    this.teams = pvp?.teams?.length >= 2
      ? pvp.teams.slice(0, 2).map(t => ({ name: t.name, spawns: t.spawns.slice(), score: 0 }))
      : null;
    this.mode = this.teams ? 'tdm' : 'dm';
    this.spawns = this.teams ? null : findSpawns(game.level);
    /* a map with no room at all still has its start */
    if (this.spawns && !this.spawns.length) {
      const p = game.player;
      this.spawns.push([Math.round(p.x), Math.round(p.y)]);
    }
    /* what happened since anybody last asked — js/net/server.js sends
       these in the snapshots and empties the list */
    this.events = [];
    this.over = null;              // { winner, until } once somebody has won
    this.round = 1;
    game.rules = this;
  }

  get limit() { return this.mode === 'tdm' ? this.rules.teamLimit : this.rules.fragLimit; }

  /* ---- sides ------------------------------------------------------------ */
  /** How much of `amount` from `from` reaches `to` (Game.hitscan). */
  scale(from, to, amount) {
    return from?.isPlayer && to?.isPlayer ? amount * this.rules.pvpScale : amount;
  }

  friendly(a, b) {
    return this.mode === 'tdm' && !!a?.isPlayer && !!b?.isPlayer && a !== b && a.team === b.team;
  }

  _smallerTeam() {
    const n = [0, 0];
    for (const p of this.game.players) if (p.team >= 0) n[p.team]++;
    if (n[0] !== n[1]) return n[0] < n[1] ? 0 : 1;
    /* level on numbers: the side that is behind */
    return this.teams[0].score <= this.teams[1].score ? 0 : 1;
  }

  /* ---- arriving and leaving -------------------------------------------- */
  /** A new player in the world, spawned and armed. */
  join({ id, name }) {
    const g = this.game;
    const p = new Player(g, g.player.x, g.player.y, 0);
    p.id = id; p.name = name;
    p.team = this.teams ? this._smallerTeam() : -1;
    g.players.push(p);
    this.spawn(p);
    this.events.push({ k: 'join', id, name, team: p.team });
    return p;
  }

  leave(p) {
    const ps = this.game.players;
    const i = ps.indexOf(p);
    if (i >= 0) ps.splice(i, 1);
    p.gunLoop?.stop(); p.gunLoop = null;
    this.events.push({ k: 'leave', id: p.id, name: p.name });
  }

  /* ---- coming back ------------------------------------------------------ */
  /** Where `p` should come back: of the pads it may use, the one
   *  furthest from the nearest player who is not on its side, with a
   *  little chance in it so two deaths do not queue on the same pad. */
  spawnPoint(p) {
    const list = this.teams ? this.teams[p.team].spawns : this.spawns;
    const foes = this.game.players.filter(o => o !== p && !o.dead && !this.friendly(p, o));
    const near = this.game.players.filter(o => o !== p && !o.dead);
    let best = list[0], bestScore = -Infinity;
    for (const s of list) {
      /* nobody standing on it */
      if (near.some(o => dist2(o.x, o.y, s[0], s[1]) < 48 * 48)) continue;
      let d = 1e12;
      for (const f of foes) d = Math.min(d, dist2(f.x, f.y, s[0], s[1]));
      const score = Math.sqrt(d) * (0.75 + this.rnd() * 0.5);
      if (score > bestScore) { bestScore = score; best = s; }
    }
    return best;
  }

  /** Put `p` back in the world, whole: a fresh Player where the pad is,
   *  keeping only who it is and the score. */
  spawn(p) {
    const g = this.game, R = this.rules;
    const [x, y] = this.spawnPoint(p);
    /* facing the middle of the map, which is where the other side is */
    const [bx0, by0, bx1, by1] = g.level.bounds || [x, y, x, y];
    const angle = Math.atan2((by0 + by1) / 2 - y, (bx0 + bx1) / 2 - x);
    renew(p, x, y, angle, R);
    p.respawnAt = 0;
    p.guardUntil = g.tics + R.guardTics;
    p.invincible = true;
    p.spawns = (p.spawns || 0) + 1;
    return p;
  }

  /* ---- a death ------------------------------------------------------------ */
  died(p, source) {
    const g = this.game;
    /* the source of a round is the player who fired it, or nobody */
    const killer = source?.isPlayer ? source : null;
    p.deaths++;
    p.respawnAt = g.tics + this.rules.respawnTics;
    if (killer && killer !== p && !this.friendly(killer, p)) {
      killer.frags++;
      if (this.teams) this.teams[killer.team].score++;
    } else {
      /* your own fault, or the world's: a frag off */
      p.frags--;
      if (this.teams && !killer) this.teams[p.team].score = Math.max(0, this.teams[p.team].score - 1);
    }
    this.events.push({ k: 'frag', by: killer && killer !== p ? killer.id : 0, of: p.id });
    if (this.over) return;
    const top = this.leader();
    if (top && top.score >= this.limit) {
      this.over = { winner: top.name, id: top.id, until: g.tics + this.rules.endTics };
      this.events.push({ k: 'over', winner: top.name });
    }
  }

  /** Who is winning: a team, or a player. */
  leader() {
    if (this.teams) {
      const [a, b] = this.teams;
      return a.score >= b.score ? { name: a.name, id: 0, score: a.score } : { name: b.name, id: 1, score: b.score };
    }
    let best = null;
    for (const p of this.game.players)
      if (!best || p.frags > best.frags) best = p;
    return best ? { name: best.name, id: best.id, score: best.frags } : null;
  }

  /* ---- a tic ----------------------------------------------------------- */
  /** After the world's tic: the respawns, the spawn guard, and the end of
   *  a round. The host calls it (SimServer.step). */
  tic() {
    const g = this.game;
    for (const p of g.players) {
      if (this.rules.infiniteAmmo) topUp(p);
      if (p.guardUntil && g.tics >= p.guardUntil) { p.guardUntil = 0; p.invincible = false; }
      if (p.dead && !this.over && g.tics >= p.respawnAt) this.spawn(p);
    }
    if (this.over && g.tics >= this.over.until) this.restart();
  }

  /** A new round: scores to nothing and everybody back on a pad. */
  restart() {
    this.over = null;
    this.round++;
    if (this.teams) for (const t of this.teams) t.score = 0;
    for (const p of this.game.players) { p.frags = 0; p.deaths = 0; this.spawn(p); }
    this.events.push({ k: 'round', n: this.round });
  }

  /** The score, for a snapshot. */
  table() {
    return {
      mode: this.mode, limit: this.limit, round: this.round,
      teams: this.teams ? this.teams.map(t => ({ name: t.name, score: t.score })) : null,
      over: this.over ? { winner: this.over.winner, left: Math.max(0, this.over.until - this.game.tics) } : null,
      players: this.game.players.map(p => ({ id: p.id, name: p.name, team: p.team, frags: p.frags, deaths: p.deaths, ping: p.ping | 0 })),
    };
  }
}
