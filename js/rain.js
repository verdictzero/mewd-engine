/* =====================================================================
   MEWD — the rain
   =====================================================================

   A box of streaks round the camera, and nothing else. Two thousand
   particles, one draw, none of them simulated against anything but the
   floor: a raindrop is a thing you see for a third of a second and it
   does not need to know what a wall is.

   IT DOES NOT FALL INDOORS, which in a sector engine is free: a drop
   is spawned only where the sector under it has the sky for a ceiling,
   and dies at the floor. A gutted region has lost its roof and gets
   the rain; the fuel grid knows the same fact (see rainOn in
   js/fire.js), which is how burning the roof off a building lets the
   weather start putting the rest of it out.

   IT LEANS WITH THE WIND, the same two numbers the smoke drifts on and
   the fires spread by (js/weather.js), because rain that fell straight
   down past smoke going sideways would be the one thing in the frame
   giving the game away.

   It is drawn with the world's own shading, so a drop in the dark is
   dark and a drop in front of the fire is lit by it, and it takes the
   air like everything else.
   ===================================================================== */

import { Particles, atlasTexture } from './particles.js';
import { Pix } from './pixel.js';
import { pRandom } from './util.js';
import { climate } from './weather.js';

/* how fast a drop falls, units per tic — nine metres a second, which
   is what rain does, and thirty-five of those a second is 8 */
const FALL = 8;
const LIFE = 44;                  // tics; the box is about that tall
const POOL = 2048;
const BOX = 520;                  // how far round the eye it falls
const ABOVE = 80, TOP = 300;      // spawned this far over the eye

/** One streak: a 4x16 cell with a bright line down it, so a square
 *  quad of it at size 20 is a two-unit-wide, twenty-tall drop. */
export function bakeRainAtlas() {
  const p = new Pix(8, 8, 7, false);
  for (let y = 0; y < 8; y++) {
    const a = y < 1 || y > 6 ? 90 : 190;
    p.set(3, y, 200, 214, 236, a);
    p.set(4, y, 168, 184, 212, Math.round(a * 0.55));
  }
  return atlasTexture([p]);
}

export class Rain {
  constructor(game, texture = null) {
    this.game = game;
    this.pool = new Particles({
      max: POOL, texture, frames: 1,
      blend: 'alpha', fullbright: false, light: 0.5, name: 'rain', renderOrder: 15, nearShrink: 24,
    });
    this.tics = 0;
  }

  attach(scene) { if (this.pool.opts.texture) this.pool.attach(scene); }

  /** How many are alive, for the readout. */
  get liveCount() { return this.pool.count; }

  tic() {
    this.tics++;
    const rain = climate.rain;
    const g = this.game, p = g.player, lv = g.level;
    if (rain > 0 && p) {
      /* SPAWN. Sixty a tic at full rain, over a box the wind's drift
         has been allowed for, so the drops arrive over your head and
         not upwind of it. */
      const n = Math.round(60 * rain);
      const wx = climate.wind.x, wy = climate.wind.y;
      const lean = LIFE * 0.5;
      for (let i = 0; i < n; i++) {
        const x = p.x + (pRandom() / 255 - 0.5) * 2 * BOX - wx * lean;
        const y = p.y + (pRandom() / 255 - 0.5) * 2 * BOX - wy * lean;
        const s = lv.sectorAt(x, y);
        if (!s) continue;
        /* under a roof, unless the roof has gone */
        if (!(s.outdoor || s.forest || s.outside || s.gutted)) continue;
        const z = p.viewZ + ABOVE + (pRandom() / 255) * (TOP - ABOVE);
        this.pool.spawn({
          x, y, z,
          vx: wx * 2.2 + (pRandom() / 255 - 0.5) * 0.3,
          vy: wy * 2.2 + (pRandom() / 255 - 0.5) * 0.3,
          vz: -FALL - (pRandom() / 255) * 2,
          life: LIFE,
          size0: 18, size1: 18,
          c0: [1, 1, 1], c1: [1, 1, 1], a0: 0.55 + rain * 0.25, a1: 0.55 + rain * 0.25,
          drag: 1, gravity: 0,
        });
      }
    }
    /* and the fall, which stops at the floor of wherever the drop is */
    const pool = this.pool;
    pool.tic((i, nx, ny, nz) => {
      const s = lv.sectorAt(nx, ny);
      return !s || nz <= s.floor + 2;
    });
  }

  render(billboardRot) { this.pool.render(billboardRot); }
}
