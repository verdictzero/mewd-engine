/* =====================================================================
   MEWD — the cold
   =====================================================================

   What comes out of the extinguisher, and it is the flamethrower's
   stream built the other way up. Same shape of thing — a few particles a
   tic leaving the nozzle at speed, slowing in the air, landing on
   something — and the opposite verb at every step: it takes heat OUT of
   the fuel grid, it puts trees back, and what it does to a person is
   hold them rather than kill them.

   WHY IT IS A SEPARATE FILE AND NOT A FLAG ON js/flame.js. The two
   share their arithmetic and disagree about everything else, and the
   moment one function has an `if (cold)` in six places it is two
   functions wearing a coat. The thirty lines of ballistics they have in
   common are thirty lines.

   THE NUMBERS ARE PER TIC, like everything else in the game.

     A GAS JET IS NOT A LIQUID JET, which is the one place the physics
     genuinely differ. Fuel from a flamethrower is thrown and falls;
     CO2 leaves at higher speed, loses it far faster, and then SINKS,
     because cold gas is heavier than the air around it. So the drag is
     harsher and the gravity is stronger, and the practical consequence
     is a weapon with less reach than the flamethrower that pools along
     the floor where it lands — which is what you want from it, because
     what you are aiming at is usually a fire on the ground.

   WHAT IT CANNOT DO IS UNDO ANYTHING. Fuel that has burned is burned;
   `burntFuel` only goes up and a charred aisle stays charred. Putting a
   fire out saves what has not caught YET, which makes this a tool for
   drawing firebreaks and for taking back a room, and never a way of
   winding the night backwards. See FireSystem.douse.
   ===================================================================== */

import { Particles } from './particles.js';
import { pRandom, dist2 } from './util.js';
import { wallNormal, UP, DOWN } from './decals.js';

export const JET = {
  perTic: 7,          // particles a tic while the trigger is down
  speed: 34,          // units a tic, leaving the nozzle — faster than fuel
  jitter: 0.07,       // and a wider spread, because it is a gas
  life: 26,           // and a shorter one
  drag: 0.935,        // which it loses fast
  gravity: -0.30,     // and then sinks, being colder than the air
  size0: 10,          // world units across, leaving the nozzle
  size1: 62,          // and at the end of its life, because gas expands
  alpha: 0.42,
  cool: 150,          // heat taken out of the grid where it lands
  coolRadius: 46,     // and how far round the landing
  treeRadius: 34,     // how much forest one landing puts out
  chill: 9,           // frost into a person it passes through, per particle
  chillRadius: 26,    // and how close it has to be
};

/** How far a particle travels before its life runs out, ignoring the
 *  drop: the jet's nominal reach. The same sum js/flame.js does, and
 *  worth being able to hold to a number for the same reason — this one
 *  should come out SHORTER than the flame's or the extinguisher is a
 *  better flamethrower than the flamethrower. */
export function jetReach(s = JET) {
  let d = 0, v = s.speed;
  for (let i = 0; i < s.life; i++) { d += v; v *= s.drag; }
  return d;
}

export class FrostStream {
  /**
   * @param game
   * @param atlas  { texture, frames } of smoke puffs, or null headless
   */
  constructor(game, atlas = null) {
    this.game = game;
    /* ALPHA AND NOT ADDITIVE, which is the visual half of the same
       argument the physics half made. Fire is added to the frame because
       two flames overlapping are brighter than one; gas is not light, it
       is something in the way, and two clouds overlapping are simply
       more opaque. Added white over a dark shop would read as a magic
       spell — blended white reads as a cloud. */
    this.particles = new Particles({
      max: 380, texture: atlas?.texture || null, frames: atlas?.frames || 8,
      blend: 'alpha', fullbright: false, light: 0.95, name: 'frost',
      renderOrder: 12, nearShrink: 40,
    });
    this.firing = 0;
    this._hits = 0;
    this.doused = 0;
    this.frozen = 0;
  }

  attach(scene) { this.particles.attach(scene); }

  /** One tic's worth of gas from a point, in a direction. `pitch` is the
   *  player's: positive looks up. */
  fire(origin, angle, pitch) {
    this.firing = 3;
    const s = JET;
    for (let k = 0; k < s.perTic; k++) {
      const a = angle + (pRandom() / 255 - 0.5) * s.jitter * 2;
      const p = pitch + (pRandom() / 255 - 0.5) * s.jitter * 1.4;
      const sp = s.speed * (0.9 + (pRandom() / 255) * 0.2);
      const ch = Math.cos(p);
      const vx = Math.cos(a) * ch * sp, vy = Math.sin(a) * ch * sp, vz = Math.sin(p) * sp;
      /* staggered along the tic, for the same reason the flame is: a
         handful born at one point is a string of beads, and born along
         the first tic's travel they are a jet */
      const f = k / s.perTic;
      this.particles.spawn({
        x: origin.x + vx * f, y: origin.y + vy * f, z: origin.z + vz * f,
        vx, vy, vz, age: f,
        life: Math.round(s.life * (0.85 + (pRandom() / 255) * 0.3)),
        size0: s.size0, size1: s.size1,
        c0: [0.92, 0.99, 1.05], c1: [0.42, 0.60, 0.80],
        a0: s.alpha, a1: 0.0,
        frame: pRandom() & 7, frameRate: 0.26,
        drag: s.drag, gravity: s.gravity,
      });
    }
  }

  tic() {
    if (this.firing > 0) this.firing--;
    const g = this.game, lv = g.level, P = this.particles;
    const actors = g.actors;
    P.tic((i, nx, ny, nz) => {
      const x = P.x[i], y = P.y[i], z = P.z[i];
      /* walls first, for the same reason the flame checks them: a jet
         that reaches through a wall is not a weapon, it is a cheat */
      const wall = lv.rayHitWall(x, y, z, nx, ny, nz);
      if (wall) { this._land(wall.x, wall.y, wall.z, wallNormal(wall.line, x, y)); return true; }
      const sec = lv.sectorAt(nx, ny);
      const floor = sec ? sec.floor : 0;
      if (nz <= floor + 4) { this._land(nx, ny, floor, UP); return true; }
      if (sec && sec.ceilTex !== 'SKY' && nz >= sec.ceil - 4) { this._land(nx, ny, sec.ceil, DOWN); return true; }
      /* A PERSON DOES NOT STOP IT, which is the other place this differs
         from the flame. A burning particle is spent on whoever it hits;
         a jet of gas washes over them and carries on to the shelf behind
         — so a queue at the tills freezes as a queue, and the fire
         behind the queue goes out too. */
      for (let k = 0; k < actors.length; k++) {
        const a = actors[k];
        if (a.removed || a.dead || !a.info.freezable) continue;
        const rr = a.radius + JET.chillRadius;
        if (dist2(nx, ny, a.x, a.y) > rr * rr) continue;
        if (nz < a.z - 10 || nz > a.z + a.height + 14) continue;
        if (a.chill(JET.chill)) this.frozen++;
      }
      return false;
    });
  }

  /** A particle has arrived somewhere: the heat comes out of whatever is
   *  there, the store's grid and the forest's both. */
  _land(x, y, z, surface = null) {
    const g = this.game;
    this._hits++;
    this.doused += g.fire?.douse(x, y, JET.cool, JET.coolRadius) || 0;
    g.forest?.douse(x, y, JET.treeRadius);
    g.fx?.chillSplash(x, y, z);
    /* and the surface rimes over where the jet is held on it — see
       js/decals.js, SPOT COOLING */
    if (surface) g.decals?.frost(x, y, z, surface);
  }

  get liveCount() { return this.particles.count; }

  render(billboardRot) { this.particles.render(billboardRot); }
}
