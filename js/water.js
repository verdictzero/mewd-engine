/* =====================================================================
   MEWD — the water
   =====================================================================

   What comes out of the fire truck's cannon (see FireTruck in
   js/vehicles.js), and the third stream in the game after the flame and
   the cold. Same shape of thing as js/frost.js — particles leaving a
   nozzle, slowing in the air, landing on something — with the physics
   of a LIQUID JET, which is the one this game had not got:

     IT IS THROWN AND IT FALLS. Water leaves a monitor nozzle fast and
     holds its speed far better than a gas does, so the drag is gentle
     and the reach is long, and then it comes down in an arc — which is
     why the truck lobs it (see aimPitch) rather than pointing it.

     IT IS HEAVY, so what it lands on it puts out HARD: more heat out of
     the grid than a burst of CO2, over a wider patch, trees along with
     it. It cannot put back what has burned, any more than the
     extinguisher can — see FireSystem.douse.

     IT PUTS PEOPLE OUT, and it moves them: a person alight is soaked
     out (Actor.soak), and anybody the jet goes through is shoved along
     it, which includes you. It does not freeze anybody; that is the
     extinguisher's trick.

     AND A BURNING VEHICLE: the jet landing by one takes the fire off it
     (Vehicle.douse... the burn counter, not the flames' picture alone),
     so the car the flamethrower lit in the lot does not go up if the
     brigade gets to it first. One that has started CHARRING is past
     saving, which is the same rule as a burnt aisle.

   Every number is per tic, like everything else in the game.
   ===================================================================== */

import { Particles } from './particles.js';
import { pRandom, dist2 } from './util.js';

export const HOSE = {
  perTic: 8,          // particles a tic while the cannon is open
  speed: 36,          // units a tic, leaving the nozzle
  jitter: 0.035,      // a tight jet: it is a monitor, not a spray
  life: 70,           // long enough to come down a long way off
  drag: 0.982,        // and it keeps its speed
  gravity: -0.42,     // and falls
  size0: 12,          // world units across leaving the nozzle
  size1: 48,          // and breaking up as it goes
  alpha: 0.72,
  cool: 200,          // heat taken out of the grid where it lands
  coolRadius: 70,     // and how far round
  treeRadius: 56,     // how much wood one landing puts out
  soak: 14,           // fire taken off a person it goes through, per particle
  soakRadius: 22,     // and how close it has to pass
  shove: 0.55,        // what it does to anybody standing in it, per particle
  carRadius: 90,      // how close to a burning vehicle a landing puts it out
};

/**
 * Where a jet thrown at `pitch` comes down, `drop` units below where it
 * left: the same integration the particles do, one tic at a time, for
 * the truck to aim with. Returns the horizontal distance.
 */
export function hoseRange(pitch, drop = 0, s = HOSE) {
  let x = 0, z = 0;
  let vx = Math.cos(pitch) * s.speed, vz = Math.sin(pitch) * s.speed;
  for (let i = 0; i < s.life * 2; i++) {
    x += vx; z += vz;
    vx *= s.drag; vz = vz * s.drag + s.gravity;
    if (z <= -drop && vz < 0) return x;
  }
  return x;
}

/** The furthest it goes on the flat, at the best angle. */
export function hoseReach(s = HOSE) {
  let best = 0;
  for (let p = 0; p <= 0.9; p += 0.02) best = Math.max(best, hoseRange(p, 0, s));
  return best;
}

/**
 * The pitch that lands a jet `dist` away and `drop` below the nozzle: the
 * LOW solution, since a fire truck plays its jet on a fire rather than
 * mortaring it, and null if it is out of reach.
 */
export function aimPitch(dist, drop = 0, s = HOSE) {
  let lo = -0.8, hi = 0.75;
  if (hoseRange(hi, drop, s) < dist) return null;
  if (hoseRange(lo, drop, s) >= dist) return lo;
  for (let k = 0; k < 22; k++) {
    const mid = (lo + hi) / 2;
    if (hoseRange(mid, drop, s) < dist) lo = mid; else hi = mid;
  }
  return (lo + hi) / 2;
}

export class WaterStream {
  /**
   * @param game
   * @param atlas  { texture, frames } of smoke puffs, or null headless
   */
  constructor(game, atlas = null) {
    this.game = game;
    /* ALPHA, like the cold: water is something in the way, not light */
    this.particles = new Particles({
      max: 900, texture: atlas?.texture || null, frames: atlas?.frames || 8,
      blend: 'alpha', fullbright: false, light: 0.9, name: 'water',
      renderOrder: 12, nearShrink: 40,
    });
    this.doused = 0;
    this.soaked = 0;
    this.landed = 0;
  }

  attach(scene) { this.particles.attach(scene); }

  /** One tic of jet from a point, in a direction. Positive pitch is up. */
  fire(origin, angle, pitch) {
    const s = HOSE;
    for (let k = 0; k < s.perTic; k++) {
      const a = angle + (pRandom() / 255 - 0.5) * s.jitter * 2;
      const p = pitch + (pRandom() / 255 - 0.5) * s.jitter * 2;
      const sp = s.speed * (0.94 + (pRandom() / 255) * 0.12);
      const ch = Math.cos(p);
      const vx = Math.cos(a) * ch * sp, vy = Math.sin(a) * ch * sp, vz = Math.sin(p) * sp;
      const f = k / s.perTic;
      this.particles.spawn({
        x: origin.x + vx * f, y: origin.y + vy * f, z: origin.z + vz * f,
        vx, vy, vz, age: f,
        life: Math.round(s.life * (0.9 + (pRandom() / 255) * 0.2)),
        size0: s.size0, size1: s.size1,
        c0: [0.92, 0.97, 1.05], c1: [0.62, 0.74, 0.88],
        a0: s.alpha, a1: 0.25,
        frame: pRandom() & 7, frameRate: 0.3,
        drag: s.drag, gravity: s.gravity,
      });
    }
  }

  tic() {
    const g = this.game, lv = g.level, P = this.particles;
    if (!P.count) return;
    const actors = g.actors, p = g.player;
    P.tic((i, nx, ny, nz) => {
      const x = P.x[i], y = P.y[i], z = P.z[i];
      const wall = lv.rayHitWall(x, y, z, nx, ny, nz);
      if (wall) { this._land(wall.x, wall.y, wall.z); return true; }
      const sec = lv.sectorAt(nx, ny);
      const floor = sec ? sec.floor : 0;
      if (nz <= floor + 3) { this._land(nx, ny, floor); return true; }
      if (sec && sec.ceilTex !== 'SKY' && nz >= sec.ceil - 4) { this._land(nx, ny, sec.ceil); return true; }
      /* anybody it goes through: put out, and pushed along it */
      const vx = nx - x, vy = ny - y, vl = Math.hypot(vx, vy) || 1;
      for (let k = 0; k < actors.length; k++) {
        const a = actors[k];
        if (a.removed || a.dead || a.vehicle) continue;
        const rr = a.radius + HOSE.soakRadius;
        if (dist2(nx, ny, a.x, a.y) > rr * rr) continue;
        if (nz < a.z - 10 || nz > a.z + a.height + 10) continue;
        if (a.soak?.(HOSE.soak)) this.soaked++;
        if (a.info?.shootable && !a.frozen && a.momx !== undefined) {
          a.momx += vx / vl * HOSE.shove; a.momy += vy / vl * HOSE.shove;
        }
      }
      if (p && !p.dead) {
        const rr = p.radius + HOSE.soakRadius;
        if (dist2(nx, ny, p.x, p.y) < rr * rr && nz > p.z - 10 && nz < p.z + 70) {
          p.momx += vx / vl * HOSE.shove * 0.5; p.momy += vy / vl * HOSE.shove * 0.5;
        }
      }
      return false;
    });
  }

  /** A drop has arrived somewhere: the heat comes out of the store's grid
   *  and the wood's, and a burning vehicle close by is put out. */
  _land(x, y, z) {
    const g = this.game;
    this.landed++;
    const cooled = g.fire?.douse(x, y, HOSE.cool, HOSE.coolRadius) || 0;
    this.doused += cooled;
    /* STEAM off whatever it has just put out, which rises where the
       splash falls: the one sign at a distance that the water is
       winning */
    if (cooled && (this.landed & 7) === 0) g.fx?.puff(x, y, z + 12, 34, 110);
    g.forest?.douse(x, y, HOSE.treeRadius);
    const r2 = HOSE.carRadius * HOSE.carRadius;
    for (const v of g.vehicles?.all || []) {
      if (v.burning > 0 && v.state !== 'charring' && dist2(x, y, v.x, v.y) < r2) v.putOut?.();
    }
    if ((this.landed & 3) === 0) g.fx?.chillSplash(x, y, z);
  }

  get liveCount() { return this.particles.count; }

  render(billboardRot) { this.particles.render(billboardRot); }
}
