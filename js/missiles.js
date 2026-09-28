/* =====================================================================
   MEWD — the quad launcher's seeker and its missiles
   =====================================================================

   FOUR TUBES AND A HEAT SEEKER, at the user's request: "a heat seeking
   quad shot function, can fire up to four at once with four locks".
   That sentence is the whole design, and everything below is one of
   its words.

   THE SEEKER. Hold the trigger and the launcher looks for heat down the
   middle of the view — a cone of six degrees round where the eye is
   pointing, out to the far side of the town. Whatever warm thing is
   nearest the middle of it, and in plain sight, is ACQUIRED: a short
   dwell with the seeker growling on it, and then a LOCK, with a tone.
   Keep holding and it goes on: the next warm thing in the cone is
   acquired and locked, and the next, up to four — one per loaded tube,
   because a lock with nothing to fire at it is a promise. If there are
   fewer warm things in the cone than there are tubes, the seeker locks
   the same one again, so four locks on one gunship is four missiles
   into one gunship.

   A lock HOLDS while its target stays roughly where you are looking —
   a much wider cone than the one that took it — and in sight; out of
   either for more than half a second and it is lost. A target that
   dies or goes cold (freezes: the extinguisher makes people cold, and
   a block of ice is not a heat source) is dropped at once.

   THE SALVO. Let go of the trigger and one missile leaves for every
   lock, a tube at a time, a few tics apart — a ripple across the front
   of the box rather than one bang, which is how the thing it is
   modelled on fires. With no locks at all, letting go fires ONE,
   straight down the sight: a launcher that did nothing without a lock
   would be the bore, and the bore already exists.

   THE FLIGHT. Each missile leaves its own tube along the sight, kicked
   a little outward by where that tube sits in the box, so four of them
   fan out for a moment before they turn. Then it steers — no more than
   `turn` radians a tic — at where its target WILL BE, leading it by the
   target's own velocity over the time left to fly. It speeds up the
   whole way. It stops for walls, floors, ceilings, its target and
   anybody standing between it and its target, and after seven seconds
   it stops anyway.

   THE WARHEAD. What it flew into takes the whole of it; everything
   within reach takes a share that falls off with distance. It is a
   BLAST, not fire — the `impact` flag, the same one the bore and a van
   carry — for a reason that is a bug report about Game.explode: that
   one deals `fire`, and the SWAT and the army are fireproof, so a
   blast built on it would kill shoppers and cars and walk straight
   through a trooper. Fire is still what it starts: the floor under it
   catches, and so does anything flammable in reach.

   WHAT IS HOT, which is the one question both halves of this weapon
   ask — the seeker asks it to pick a target and the thermal screen
   (js/thermal.js) asks it to decide what glows — so it is answered in
   exactly one place, heatSources() below: people who are alive and not
   frozen, vehicles with their engine running or on fire, and anything
   flying. A parked car is cold. A dead one is cold.
   ===================================================================== */

import * as THREE from 'three';
import { createSpriteMaterial } from './material.js';
import { pRandom, dist2 } from './util.js';
import { Particles } from './particles.js';
import { SMOKE_PUFFS } from './effects.js';
import { climate } from './weather.js';
import { wallNormal, UP, DOWN, bleeds } from './decals.js';

export const SEEKER = {
  range: 4200,          // how far away a heat source can be taken
  cone: 0.105,          // radians off the sight a source must be to be ACQUIRED
  track: 0.21,          // and how far it may wander while the dwell on it runs
  hold: 0.34,           // and how far off it may drift once it is locked
  grace: 18,            // tics a lock survives outside the hold cone or out of sight
  first: 16,            // tics of dwell for the first lock
  next: 11,             // and for every lock after it
  most: 4,              // one per tube
};

export const MISSILE = {
  speed0: 12,           // how it leaves the tube, units a tic
  speed1: 58,           // and how fast it gets, which is over twice the gunship's best
  accel: 1.13,          // a tic's worth of getting there
  boost: 5,             // tics out of the tube before it starts to steer
  turn: 0.085,          // radians a tic it may bend toward the target
  kick: 0.075,          // radians the tube's place in the box splays it outward
  life: 7 * 35,         // and then it goes off wherever it is
  reach: 14,            // how near the skin of a thing is near enough
  gap: 4,               // tics between missiles in a salvo
  lead: 40,             // the most tics ahead it will lead a moving target by
};

export const WARHEAD = {
  direct: 420,          // what the thing it flew into takes — a gunship is sixteen hundred
  splash: 150,          // the most anything else in reach takes
  radius: 190,          // and how far the reach is
  heat: 240,            // the fire it starts on the floor under it
  heatRadius: 90,
  ignite: 260,          // tics alight for anything flammable in reach
  self: 0.5,            // the share of it that reaches the player, who is also in reach
};

/* THE TRAIL AND THE BANG, which are pictures and so numbers of their
   own, apart from what the warhead does. */
export const TRAIL = {
  step: 14,             // units of flight between two puffs of the trail
  max: 1000,            // the trail's own pool: four missiles' worth and a bang's
  life: 44,             // tics a puff lasts, and up to half again
  size0: 6, size1: 34,  // how big it is born and how big it goes
  light: 0.82,          // what it is lit to: it is pale, and it is meant to be seen
};
export const BOOM = {
  tics: 3,              // tics a frame of the fireball
  frames: 8,
  scale: 2.125,         // the frames are sixty-four across; this makes a fireball of about three metres
};

/** WHICH EIGHTH OF A ROCKET IS SEEN from the eye at (ex, ey): where it
 *  is heading against where the eye is from it, 0 its nose, 2 heading
 *  off to the eye's right, 4 its tail and its flame — the order
 *  rocketView in js/sprites.js draws them in. */
export function rocketFacing(dx, dy, x, y, ex, ey) {
  const rel = Math.atan2(dy, dx) - Math.atan2(ey - y, ex - x);
  return ((Math.round(rel / (Math.PI / 4)) % 8) + 8) % 8;
}

export class MissileSystem {
  constructor(game) {
    this.game = game;
    this.locks = [];            // { t, lost } — a target may appear more than once
    this.acquiring = null;      // the source the seeker is dwelling on
    this.dwell = 0;             // and for how long
    this.queue = [];            // the salvo still to leave: one entry per missile, its target or null
    this.gapTics = 0;
    this.salvoTube = 0;         // the tube the next missile of the salvo leaves
    this.shots = [];            // in the air
    this.fired = 0;
    this.hits = 0;
    this.blasts = 0;
    this.shake = 0;             // 0..1, what a near blast does to the eye — see Game.render
    this._sources = [];
    this._pt = { x: 0, y: 0, z: 0 };
    this._o = { x: 0, y: 0, z: 0 };
    this.reticles = [];         // world markers over the locks, drawn like the bore's
    /* THE TRAIL'S OWN POOL. The first trail was puffs out of the store's
       smoke — dark, because the store's smoke is, and shared with every
       burning aisle — and at night it could not be seen at all. This one
       is pale, lit well above the street, and the salvo's alone. It
       borrows the store's puff frames when it is first drawn. */
    this.trail = new Particles({
      max: TRAIL.max, texture: null, frames: SMOKE_PUFFS,
      blend: 'alpha', fullbright: false, light: TRAIL.light, name: 'missile-trail', renderOrder: 14, nearShrink: 90,
    });
    this.booms = [];            // fireballs going off: { x, y, z, t, mesh }
    this._boomMeshes = [];
  }

  /** Whether the seeker is on at all: the launcher in hand, and a hand. */
  get active() {
    const p = this.game.player;
    return !!p && p.weapon === 'LAUNCHER' && !p.dead;
  }

  /** How many missiles are still to leave this salvo. The player will
   *  not put the launcher down, or start another, until it is none. */
  get salvoLeft() { return this.queue.length; }

  /** 0..1, how far the dwell on the source being acquired has got. */
  get acquireFraction() {
    if (!this.acquiring) return 0;
    const need = this.locks.length ? SEEKER.next : SEEKER.first;
    return Math.min(1, this.dwell / need);
  }

  /* ------------------------------------------------------------------
     WHAT IS HOT — see the header
     ------------------------------------------------------------------ */

  /** Whether this is warm enough to lock and to glow. */
  isHot(t) {
    if (!t) return false;
    /* a vehicle, or anything flying: it is its own thing, not a body */
    if (t.bodies || t.cz !== undefined) {
      if (!t.whole) return false;
      if (this.game.gunships?.ships?.includes(t)) return true;
      return t.state === 'driving' || t.state === 'charring' || t.burning > 0;
    }
    return !t.removed && !t.dead && t.shootable && t.monster && !t.vehicle && !t.frozen;
  }

  /** Every heat source in the world, in a scratch array. */
  heatSources() {
    const g = this.game, out = this._sources;
    out.length = 0;
    for (const a of g.actors) if (a.monster && this.isHot(a)) out.push(a);
    for (const v of g.vehicles?.all || []) if (this.isHot(v)) out.push(v);
    for (const s of g.gunships?.ships || []) if (this.isHot(s)) out.push(s);
    return out;
  }

  /** The middle of the warm part of a thing, in game coordinates. A body
   *  is warmest in the chest; a vehicle and an aircraft in the middle. */
  heatPoint(t, out = this._pt) {
    out.x = t.x; out.y = t.y;
    out.z = t.cz !== undefined ? t.cz : t.z + t.height * 0.58;
    return out;
  }

  /* ------------------------------------------------------------------
     One tic
     ------------------------------------------------------------------ */
  tic() {
    const p = this.game.player;
    if (this.active && p.seeking) this.seekTic(p);
    else { this.acquiring = null; this.dwell = 0; }
    if (this.active) this.holdTic(p);
    else if (!this.queue.length) this.locks.length = 0;
    this.salvoTic(p);
    this.flyTic();
    this.trail.tic();
    for (let i = this.booms.length - 1; i >= 0; i--) {
      const b = this.booms[i];
      this.boomTic(b);
      if (++b.t >= BOOM.tics * BOOM.frames) {
        this.booms.splice(i, 1);
        if (b.mesh) { b.mesh.visible = false; this._boomMeshes.push(b.mesh); }
      }
    }
    this.shake = Math.max(0, this.shake - 0.035);
  }

  /** The angle between the sight and a point, and whether the eye can
   *  see it. Null when it is behind you or out of range. */
  _offSight(p, pt) {
    const ex = p.x, ey = p.y, ez = p.eyeZ;
    const dx = pt.x - ex, dy = pt.y - ey, dz = pt.z - ez;
    const d = Math.hypot(dx, dy, dz);
    if (d < 1 || d > SEEKER.range) return null;
    const c = Math.cos(p.pitch);
    const fx = Math.cos(p.angle) * c, fy = Math.sin(p.angle) * c, fz = Math.sin(p.pitch);
    const dot = (dx * fx + dy * fy + dz * fz) / d;
    if (dot <= 0) return null;
    return Math.acos(Math.min(1, dot));
  }

  _inSight(p, pt) {
    return !this.game.level.sightBlocked(p.x, p.y, p.eyeZ, pt.x, pt.y, pt.z);
  }

  /** THE SEEKER, while the trigger is down. */
  seekTic(p) {
    const loaded = p.ammo.rockets | 0;
    const want = Math.min(SEEKER.most, loaded);
    if (this.locks.length >= want) { this.acquiring = null; this.dwell = 0; return; }
    /* WHAT IT IS ALREADY DWELLING ON, IT KEEPS while that stays within
       twice the cone, which is the difference between locking a gunship
       and chasing one: an aircraft crossing the sight at speed leaves a
       six-degree circle between two corrections of the player's hand,
       and a dwell that started again every time it did would never end.
       Taking a NEW source still needs the narrow cone. */
    const held = this.acquiring;
    if (held && this.isHot(held)) {
      const pt = this.heatPoint(held);
      const a = this._offSight(p, pt);
      if (a !== null && a <= SEEKER.track && this._inSight(p, pt)) { this._dwell(want); return; }
    }
    /* the nearest the middle, not yet locked; failing that, the nearest
       the middle full stop, so a lone target takes every tube */
    let best = null, bestA = SEEKER.cone, again = null, againA = SEEKER.cone;
    for (const t of this.heatSources()) {
      const pt = this.heatPoint(t);
      const a = this._offSight(p, pt);
      if (a === null || a > SEEKER.cone) continue;
      if (!this._inSight(p, pt)) continue;
      const locked = this.locks.some(l => l.t === t);
      if (!locked && a < bestA) { best = t; bestA = a; }
      if (locked && a < againA) { again = t; againA = a; }
    }
    const cand = best || again;
    if (!cand) { this.acquiring = null; this.dwell = 0; return; }
    if (cand !== this.acquiring) {
      this.acquiring = cand; this.dwell = 0;
      this.game.sound?.play('seek', null);
    }
    this._dwell(want);
  }

  /** One tic more on the source being acquired, and the lock at the end. */
  _dwell(want) {
    this.dwell++;
    if (this.dwell < (this.locks.length ? SEEKER.next : SEEKER.first)) return;
    this.locks.push({ t: this.acquiring, lost: 0 });
    this.acquiring = null; this.dwell = 0;
    this.game.sound?.play(this.locks.length >= want ? 'lockfull' : 'lockon', null);
  }

  /** And every tic the launcher is in hand, whether the trigger is down
   *  or not: a lock is kept while its target is warm, near the sight
   *  and in sight, and lost after `grace` tics of being any of those. */
  holdTic(p) {
    for (let i = this.locks.length - 1; i >= 0; i--) {
      const l = this.locks[i];
      if (!this.isHot(l.t)) { this.locks.splice(i, 1); continue; }
      const pt = this.heatPoint(l.t);
      const a = this._offSight(p, pt);
      const ok = a !== null && a <= SEEKER.hold && this._inSight(p, pt);
      l.lost = ok ? 0 : l.lost + 1;
      if (l.lost > SEEKER.grace) this.locks.splice(i, 1);
    }
  }

  /* ------------------------------------------------------------------
     The trigger coming up
     ------------------------------------------------------------------ */
  /** One missile per lock, or one straight down the sight with none. */
  release(p) {
    const loaded = p.ammo.rockets | 0;
    if (!loaded) return 0;
    if (this.locks.length) {
      for (const l of this.locks.slice(0, loaded)) this.queue.push(l.t);
    } else this.queue.push(null);
    this.locks.length = 0;
    this.acquiring = null; this.dwell = 0;
    this.gapTics = 0;
    /* WHICH TUBE GOES FIRST is the first loaded one, and the salvo walks
       on from there — counted here rather than read off the magazine
       each time, because the magazine can be refilled under a salvo
       (the debug switch does it every tic) and four missiles out of one
       tube is not a ripple */
    this.salvoTube = SEEKER.most - loaded;
    return this.queue.length;
  }

  salvoTic(p) {
    if (!this.queue.length) return;
    if (!p || p.dead || p.weapon !== 'LAUNCHER') { this.queue.length = 0; return; }
    if (this.gapTics > 0) { this.gapTics--; return; }
    const t = this.queue.shift();
    /* a target that has died or gone cold since it was locked still
       gets its missile — straight down the sight, unguided — because
       the tube has already been asked */
    this.launch(p, t && this.isHot(t) ? t : null, this.salvoTube++ % SEEKER.most);
    this.gapTics = MISSILE.gap;
  }

  /** One missile out of a tube — the next loaded one, unless the salvo
   *  says which. */
  launch(p, target, tube = SEEKER.most - (p.ammo.rockets | 0)) {
    const g = this.game;
    if ((p.ammo.rockets | 0) <= 0) return null;
    p.ammo.rockets--;
    p.shotsFired++;
    p.launchTube = tube;
    p.fireIndex = 0;
    p.fireTics = 5;
    const o = g.weapon3d?.tubeWorld(tube, g.camera, this._o) || g.nozzle();
    /* AND NOT FROM THE FAR SIDE OF A WALL. The mouth of a tube is most
       of a metre out along its own ray from the eye, and with your back
       to a shelf and your nose to a wall that is inside the wall or
       past it — so if the wall is between the eye and the mouth, the
       missile starts at the eye and meets the wall on its first tic,
       which is what firing a rocket launcher into a wall does. */
    if (g.level.rayHitWall(p.x, p.y, p.eyeZ, o.x, o.y, o.z)) { o.x = p.x; o.y = p.y; o.z = p.eyeZ - 6; }
    /* ALONG THE SIGHT, and at what the sight is on: the tube is a hand's
       breadth off the eye, so a missile flown parallel to the view would
       pass beside the crosshair all the way to the wall. The trace says
       what the eye is looking at and a straight shot goes there. */
    const aim = g.trace(p, p.angle, p.pitch, SEEKER.range);
    let dx = aim.x - o.x, dy = aim.y - o.y, dz = aim.z - o.z;
    let l = Math.hypot(dx, dy, dz) || 1;
    dx /= l; dy /= l; dz /= l;
    /* and, for a guided one, KICKED OUT by where its tube sits in the
       box: the top two up, the bottom two down, the left-hand pair
       left — tubes 0 and 2, see `tubes` in js/weapon3d.js — so a salvo
       fans out of the launcher before it turns */
    if (target) {
      const right = (tube & 1) === 0 ? -1 : 1, up = tube < 2 ? 1 : -1;
      const rx = Math.sin(p.angle), ry = -Math.cos(p.angle);
      dx += rx * right * MISSILE.kick; dy += ry * right * MISSILE.kick;
      dz += up * MISSILE.kick * 0.8;
      l = Math.hypot(dx, dy, dz) || 1;
      dx /= l; dy /= l; dz /= l;
    }
    const s = {
      x: o.x, y: o.y, z: o.z, dx, dy, dz,
      speed: MISSILE.speed0, target, life: MISSILE.life, tics: 0, tube,
      seed: pRandom() / 255, mesh: null, flare: null,
    };
    this.shots.push(s);
    this.fired++;
    g.sound?.play('missile', p);
    /* THE BACKBLAST. A tube open at both ends throws as much out of the
       back as the front, and the back of this one is over your shoulder:
       a puff of it behind you, which is also why nobody stands there. */
    const c = Math.cos(p.angle), sn = Math.sin(p.angle);
    g.fx?.puff(p.x - c * 44, p.y - sn * 44, p.eyeZ - 6, 20, 70);
    g.noise(p, 1400);
    return s;
  }

  /* ------------------------------------------------------------------
     In the air
     ------------------------------------------------------------------ */
  flyTic() {
    const g = this.game, lv = g.level;
    for (let i = this.shots.length - 1; i >= 0; i--) {
      const s = this.shots[i];
      s.tics++;
      const t = s.target && this.isHot(s.target) ? s.target : null;
      if (!t) s.target = null;
      if (t && s.tics > MISSILE.boost) this.steer(s, t);
      s.speed = Math.min(MISSILE.speed1, s.speed * MISSILE.accel);
      const nx = s.x + s.dx * s.speed, ny = s.y + s.dy * s.speed, nz = s.z + s.dz * s.speed;

      /* what it flies into, nearest first along this tic's leg: its
         target, a body in the way, a wall, the floor or the ceiling */
      const body = this.bodyOnLeg(s, nx, ny, nz, t);
      const wall = lv.rayHitWall(s.x, s.y, s.z, nx, ny, nz);
      const sec = lv.sectorAt(nx, ny);
      let at = null, direct = null, face = null;
      if (body && (!wall || body.u <= (wall.t ?? 1))) { at = body.at; direct = body.who; }
      else if (wall) { at = wall; face = wall.line ? wallNormal(wall.line, s.x, s.y) : null; }
      else if (!sec || nz <= sec.floor + 2 || nz >= sec.ceil - 2 || --s.life <= 0) {
        at = { x: nx, y: ny, z: sec ? Math.max(sec.floor + 2, Math.min(sec.ceil - 2, nz)) : nz };
        /* the floor or the ceiling, if that is what stopped it */
        if (sec && nz <= sec.floor + 2) face = UP;
        else if (sec && nz >= sec.ceil - 2 && !sec.sky) face = DOWN;
      }
      /* the trail runs right up to where it went off */
      this.shed(s, at || { x: nx, y: ny, z: nz });
      if (at) {
        this.shots.splice(i, 1);
        this.discard(s);
        this.detonate(at, direct, face);
        continue;
      }
      s.x = nx; s.y = ny; s.z = nz;
      /* THE EXHAUST: a small lick of flame every tic off the pool the
         fireballs use — white, going orange, gone in a fraction of a
         second — which is the hot end of the streak; the rocket sprite
         carries its own flame and MISL blooms behind it (see render);
         and the motor pulls the one fire light toward itself, so it
         lights the street it crosses. */
      g.fx?.fireball(s.x - s.dx * 16, s.y - s.dy * 16, s.z - s.dz * 16, 11, 3);
      if ((s.tics & 1) === 0) g.fx?.glowAt(s.x, s.y, 0.7);
    }
  }

  /** THE SMOKE TRAIL, laid down along the leg the rocket has just flown
   *  rather than where it ended up, a puff every TRAIL.step units: at
   *  fifty-eight units a tic a puff a tic would be a dotted line. Pale,
   *  and born warm — lit by the motor it has just come out of — going
   *  to grey as it spreads and drifts off on the wind. */
  shed(s, to) {
    const wind = climate.wind;
    const ox = s.x - s.dx * 14, oy = s.y - s.dy * 14, oz = s.z - s.dz * 14;
    const ex = to.x - s.dx * 14, ey = to.y - s.dy * 14, ez = to.z - s.dz * 14;
    const len = Math.hypot(ex - ox, ey - oy, ez - oz);
    const n = Math.max(1, Math.ceil(len / TRAIL.step));
    for (let k = 1; k <= n; k++) {
      const f = k / n;
      this.trail.spawn({
        x: ox + (ex - ox) * f + (pRandom() / 255 - 0.5) * 3,
        y: oy + (ey - oy) * f + (pRandom() / 255 - 0.5) * 3,
        z: oz + (ez - oz) * f + (pRandom() / 255 - 0.5) * 3,
        vx: (pRandom() / 255 - 0.5) * 0.4 + wind.x * 1.2, vy: (pRandom() / 255 - 0.5) * 0.4 + wind.y * 1.2,
        vz: 0.12 + (pRandom() / 255) * 0.25,
        life: TRAIL.life + (pRandom() % (TRAIL.life >> 1)),
        size0: TRAIL.size0, size1: TRAIL.size1,
        c0: [0.98, 0.9, 0.76], c1: [0.56, 0.56, 0.6], a0: 0.72, a1: 0,
        frame: pRandom() % SMOKE_PUFFS, frameRate: 0.08,
        drag: 0.965, gravity: 0.004,
      });
    }
  }

  /** Bend toward where the target will be, by no more than `turn`. */
  steer(s, t) {
    const pt = this.heatPoint(t);
    let wx = pt.x - s.x, wy = pt.y - s.y, wz = pt.z - s.z;
    /* LEAD IT: the target's own velocity times the time left to fly, so
       a van crossing the car park is met rather than chased */
    const d = Math.hypot(wx, wy, wz) || 1;
    const tgo = Math.min(MISSILE.lead, d / Math.max(1, s.speed));
    const vx = t.vx ?? t.momx ?? 0, vy = t.vy ?? t.momy ?? 0, vz = t.vz ?? 0;
    wx += vx * tgo; wy += vy * tgo; wz += vz * tgo;
    const wl = Math.hypot(wx, wy, wz) || 1;
    wx /= wl; wy /= wl; wz /= wl;
    const dot = Math.max(-1, Math.min(1, s.dx * wx + s.dy * wy + s.dz * wz));
    const ang = Math.acos(dot);
    if (ang > 1e-4) {
      const k = Math.min(1, MISSILE.turn / ang);
      s.dx += (wx - s.dx) * k; s.dy += (wy - s.dy) * k; s.dz += (wz - s.dz) * k;
      const l = Math.hypot(s.dx, s.dy, s.dz) || 1;
      s.dx /= l; s.dy /= l; s.dz /= l;
    }
  }

  /** The first shootable thing this tic's leg passes within reach of —
   *  its own target with the proximity fuse's reach, anything else with
   *  a little — as { u, at, who }, u along the leg from 0 to 1. A body
   *  that is a third of a van is the van. */
  bodyOnLeg(s, nx, ny, nz, target) {
    const g = this.game;
    const ex = nx - s.x, ey = ny - s.y, ez = nz - s.z;
    const len2 = ex * ex + ey * ey + ez * ez || 1;
    const span = Math.sqrt(len2) + 200;
    let best = null;
    const test = (a, pad) => {
      const cz = a.z + a.height / 2;
      /* the nearest point of the leg to the middle of the body */
      let u = ((a.x - s.x) * ex + (a.y - s.y) * ey + (cz - s.z) * ez) / len2;
      u = Math.max(0, Math.min(1, u));
      const px = s.x + ex * u, py = s.y + ey * u, pz = s.z + ez * u;
      const r = a.radius + pad;
      if (dist2(px, py, a.x, a.y) > r * r) return;
      if (pz < a.z - pad || pz > a.z + a.height + pad) return;
      if (!best || u < best.u) best = { u, at: { x: px, y: py, z: pz }, who: a.vehicle || a };
    };
    for (const a of g.actors) {
      if (a.removed || a.dead || !a.shootable) continue;
      if (Math.abs(a.x - s.x) > span || Math.abs(a.y - s.y) > span) continue;
      const mine = target && (a === target || a.vehicle === target);
      test(a, mine ? MISSILE.reach : 3);
    }
    return best;
  }

  /* ------------------------------------------------------------------
     The warhead
     ------------------------------------------------------------------ */
  detonate(at, direct = null, face = null) {
    const g = this.game, p = g.player;
    this.blasts++;
    g.sound?.play('explode', at);
    /* THE BANG, which is a picture now and not only a heap of particles:
       the eight frames of MEXP where it went off (see render), a few of
       the aircraft's fireballs in and round it for the glow, the coals,
       the sparks — and, once the fireball is burning out, a cloud of
       smoke rising out of it (see boomTic). And the light. */
    this.booms.push({ x: at.x, y: at.y, z: at.z, t: 0, mesh: null });
    for (let k = 0; k < 4; k++) g.fx?.fireball(at.x, at.y, at.z, 56, 12);
    g.fx?.ember(at.x, at.y, at.z, 10, 1.3);
    g.spawnSparks?.(at.x, at.y, at.z, 8);
    /* AND IT LEAVES A BURNING HOLE in what it hit — a crater with a
       molten rim and coals in the cracks round it, which burn out over
       a few seconds and leave the char (js/decals.js, Decals.burn). A
       warhead that went off in the air, or in somebody, marks the floor
       under it if the floor is close enough to have taken the blast. */
    if (face) g.decals?.burn(at.x, at.y, at.z, face);
    else {
      const under = g.level?.sectorAt?.(at.x, at.y);
      if (under && at.z - under.floor < 72) g.decals?.burn(at.x, at.y, under.floor, UP, 70);
    }
    g.fx?.glowAt(at.x, at.y, 6);
    /* and it starts a fire where it went off, because this is that game */
    g.fire?.ignite(at.x, at.y, WARHEAD.heat, WARHEAD.heatRadius);
    g.scare?.(at.x, at.y, 700);
    if (p) g.noise(at, 1600);

    const hit = new Set();
    /* WHO IT MIGHT KILL, for the gore — see the end of this, and GORE
       in js/people.js. EVERYBODY IN REACH WHO WAS ALIVE WHEN IT WENT
       OFF, taken BEFORE anything is hurt, and not only whoever the loop
       below kills itself: a shopper killed first goes up in their own
       burst, and that burst can finish the one next to them before the
       loop gets there — they died of this warhead all the same. So the
       list is taken first and asked about at the end. */
    const blown = [];
    const took = (a, force) => {
      if (!a || a.dead || a.vehicle) return;
      if (!blown.some(b => b.a === a)) blown.push({ a, force });
    };
    const R0 = WARHEAD.radius;
    for (const a of g.actors) {
      if (a.removed || a.dead || !a.shootable || a.vehicle || a === direct) continue;
      const d = Math.hypot(a.x - at.x, a.y - at.y, (a.z + (a.height || 56) * 0.5) - at.z) - (a.radius || 16);
      if (d < R0) took(a, 1 - 0.4 * Math.max(0, d) / R0);
    }
    if (direct) {
      hit.add(direct);
      this.hits++;
      took(direct, 1.35);
      direct.damage?.(WARHEAD.direct, p, { impact: true, gib: true });
      direct.ignite?.(WARHEAD.ignite);
    }
    const R = WARHEAD.radius;
    for (const a of g.actors) {
      if (a.removed || a.dead || !a.shootable) continue;
      const who = a.vehicle || a;
      if (hit.has(who)) continue;
      if (Math.abs(a.x - at.x) > R + a.radius || Math.abs(a.y - at.y) > R + a.radius) continue;
      /* the distance to the SKIN of the body, not its middle: a van is
         two hundred units long and a blast at its bumper is at the van */
      const h = Math.max(0, Math.sqrt(dist2(at.x, at.y, a.x, a.y)) - a.radius);
      const v = at.z < a.z ? a.z - at.z : at.z > a.z + a.height ? at.z - a.z - a.height : 0;
      const d = Math.hypot(h, v);
      if (d >= R) continue;
      hit.add(who);
      const n = Math.round(WARHEAD.splash * (1 - d / R));
      if (n <= 0) continue;
      a.damage(n, p, { impact: true, gib: true });
      if (a.info?.flammable) a.ignite?.(WARHEAD.ignite);
    }
    /* AND EVERYBODY IT KILLED IS BLOWN APART, at the user's request —
       "literally explode into viscera and gore chunks when hit by a
       rocket in a more extreme way". The ordinary burst (a shopper) or
       the gore death (a trooper, forced by `gib` above) has already
       happened in damage(); this is on top of it: sixty pieces thrown
       away from the blast, a spray of blood in the air and the room
       round them painted. See Giblets.eviscerate. */
    for (const b of blown)
      if (b.a.dead && bleeds(b.a, p)) g.giblets?.eviscerate?.(b.a, at, b.force);
    /* AND YOU, because you are standing in it or you are not */
    if (p && !p.dead) {
      const h = Math.max(0, Math.sqrt(dist2(at.x, at.y, p.x, p.y)) - p.radius);
      const v = at.z < p.z ? p.z - at.z : at.z > p.z + p.height ? at.z - p.z - p.height : 0;
      const d = Math.hypot(h, v);
      if (d < R) p.damage(Math.round(WARHEAD.splash * WARHEAD.self * (1 - d / R)), null, { impact: true });
      /* and what it does to the eye, from a long way further off */
      this.shake = Math.min(1, this.shake + Math.max(0, 1 - d / (R * 4)) * 0.8);
    }
  }

  /** THE SMOKE OF A BANG, AND IT COMES AFTER THE FIRE. The first cut put
   *  it all down at the instant it went off, and smoke is drawn after
   *  anything solid: eight dark puffs sat in front of the fireball and
   *  all that showed of the explosion was its shock ring. So the cloud
   *  starts as the ball starts to burn out — the fourth frame — a puff
   *  a tic, each higher than the last, rising and spreading, dark,
   *  going grey. */
  boomTic(b) {
    const k = b.t - BOOM.tics * 3;
    if (k < 0 || k >= 8) return;
    const a = (pRandom() / 255) * Math.PI * 2, r = (pRandom() / 255) * 30;
    this.trail.spawn({
      x: b.x + Math.cos(a) * r, y: b.y + Math.sin(a) * r, z: b.z + 18 + k * 7,
      vx: Math.cos(a) * 0.45 + climate.wind.x, vy: Math.sin(a) * 0.45 + climate.wind.y, vz: 0.6 + (pRandom() / 255) * 0.6,
      life: 90 + (pRandom() % 50), size0: 36, size1: 120,
      c0: [0.30, 0.28, 0.26], c1: [0.46, 0.46, 0.5], a0: 0.72, a1: 0,
      frame: pRandom() % SMOKE_PUFFS, frameRate: 0.06, drag: 0.97, gravity: 0.003,
    });
  }

  discard(s) {
    for (const k of ['mesh', 'flare'])
      if (s[k]) { this.game.scene.remove(s[k]); s[k].material.dispose(); s[k] = null; }
  }

  /* ------------------------------------------------------------------
     Drawing: a flare per missile, and a bracket over every lock — the
     same quads the bore draws with, and the markers ignore depth for
     the reason the bore's reticle does: they sit ON a thing
     ------------------------------------------------------------------ */
  _sprite(depthTest, blend) {
    const g = this.game;
    const mat = createSpriteMaterial(null, { alphaTest: 0.5, width: 16, height: 16, blend, fullbright: true });
    mat.depthTest = depthTest;
    mat.depthWrite = false;
    const m = new THREE.Mesh(g._projGeo, mat);
    m.frustumCulled = false;
    m.renderOrder = 20;
    g.scene.add(m);
    return m;
  }

  place(mesh, x, y, z, sprite, frame, billboardRot, scale = 1, rot = 0) {
    const g = this.game;
    const e = g.sprites.get(sprite, frame);
    const u = mesh.material.uniforms;
    u.map.value = g.sprites.texture(e, rot);
    u.spriteScale.value.set(e.w * e.scale * scale, e.h * e.scale * scale);
    u.billboardRot.value = billboardRot;
    u.fullbright.value = 1;
    u.light.value = 1;
    mesh.position.set(x, z - (e.h * e.scale * scale) / 2, -y);
    mesh.visible = true;
  }

  /** `ex, ey` is the eye, for which way round each rocket is seen. */
  render(billboardRot, ex = this.game.player?.x ?? 0, ey = this.game.player?.y ?? 0) {
    const g = this.game;
    /* the trail borrows the store's puffs the first time there are any */
    if (!this.trail.mesh && g.fx?.smoke?.opts?.texture && g.scene) {
      this.trail.opts.texture = g.fx.smoke.opts.texture;
      this.trail.attach(g.scene);
    }
    this.trail.render(billboardRot);
    /* one bracket per locked TARGET, bigger for every extra lock on it */
    const marks = [];
    if (this.active) {
      for (const l of this.locks) {
        const m = marks.find(k => k.t === l.t);
        if (m) m.n++; else marks.push({ t: l.t, n: 1 });
      }
      if (this.acquiring && !marks.some(k => k.t === this.acquiring)) marks.push({ t: this.acquiring, n: 0 });
    }
    while (this.reticles.length < marks.length) this.reticles.push(this._sprite(false, 'cutout'));
    const p = g.player;
    for (let i = 0; i < this.reticles.length; i++) {
      const r = this.reticles[i], m = marks[i];
      if (!m) { r.visible = false; continue; }
      const pt = this.heatPoint(m.t);
      /* AND NEVER SMALLER THAN A FEW PIXELS. The bracket is a thing in
         the world, twenty units across, and on a gunship three thousand
         units out that is less than a pixel — a lock you cannot see. So
         past a few hundred units it grows with the distance and keeps
         its size on the screen. */
      const far = p ? Math.max(1, Math.hypot(pt.x - p.x, pt.y - p.y, pt.z - p.eyeZ) / 420) : 1;
      if (m.n === 0) {
        /* acquiring: the bracket closing in, blinking */
        const f = this.acquireFraction;
        if ((g.tics >> 1) & 1) { r.visible = false; continue; }
        this.place(r, pt.x, pt.y, pt.z, 'TLCK', 'B', billboardRot, (2.2 - 1.2 * f) * far);
      } else this.place(r, pt.x, pt.y, pt.z, 'TLCK', 'A', billboardRot, (1 + 0.22 * (m.n - 1)) * far);
    }
    /* THE ROCKETS: the body, turned to the eye in eighths the way a Doom
       thing is — which eighth is where it is heading against where you
       are, 0 its nose and 4 its flame — and the bloom of the motor on
       top of it, additive, a little behind */
    for (const s of this.shots) {
      if (!s.mesh) s.mesh = this._sprite(true, 'cutout');
      if (!s.flare) s.flare = this._sprite(true, 'add');
      this.place(s.mesh, s.x, s.y, s.z, 'ROKT', (s.tics >> 1) & 1 ? 'B' : 'A', billboardRot, 1,
                 rocketFacing(s.dx, s.dy, s.x, s.y, ex, ey));
      this.place(s.flare, s.x - s.dx * 16, s.y - s.dy * 16, s.z - s.dz * 16, 'MISL',
                 'ABC'[(s.tics + (s.seed * 3 | 0)) % 3], billboardRot, 1.8);
    }
    /* AND THE FIREBALLS, a frame every BOOM.tics */
    for (const b of this.booms) {
      if (!b.mesh) b.mesh = this._boomMeshes.pop() || this._sprite(true, 'cutout');
      const f = Math.min(BOOM.frames - 1, Math.floor(b.t / BOOM.tics));
      this.place(b.mesh, b.x, b.y, b.z, 'MEXP', 'ABCDEFGH'[f], billboardRot, BOOM.scale);
    }
  }
}
