/* =====================================================================
   MEWD — embers and smoke
   =====================================================================

   A fire that only glows is a picture of a fire. What sells it is what
   comes OFF it: sparks lifting on the heat and going out, and smoke
   standing up over it and drifting away. Both are cheap if they are
   budgeted, and this is the budget: a few hundred embers and a couple
   of hundred puffs at most, alive at once, in two draw calls.

   WHERE THEY COME FROM. Nothing spawns from every burning cell — with
   an aisle alight that is hundreds of sources and with a forest alight
   it is thousands. Each tic a handful of burning cells NEAR THE PLAYER
   are sampled at random, from the store's grid and from the forest's,
   and those throw the frame's sparks. Far fires are a glow on the
   horizon anyway; a spark two thousand units off is a pixel nobody
   sees, and it would have cost the same as one at your feet.

   EMBERS are cutout quads a couple of units across, bright gold going
   to dark coal, lifted by the heat and then falling, and they die when
   they land. SMOKE is a soft blob, alpha-blended, that grows and fades
   as it climbs; it is lit by the sector light like anything else, so it
   is dark against the night and catches the fire glow from below.
   ===================================================================== */

import { Particles, atlasTexture } from './particles.js';
import { Pix, fbm } from './pixel.js';
import { pRandom, dist2 } from './util.js';
import { EMBER_RAMP } from './palette.js';
import { climate } from './weather.js';

/* THE WIND WAS A CONSTANT HERE — WIND_X = 0.28 — read by the three
   emitters below and by nothing else, under a comment that said the
   forest leaned with it, which it did not. It is a vector in
   js/weather.js now, set by the weather, and the smoke, the rain, the
   store's fire and the wood's fire all read the same two numbers. */
const wind = climate.wind;

/* =====================================================================
   A PERSON ON FIRE

   The best thing in this game was, until now, invisible. A shopper the
   flame touches catches, runs for several seconds dropping fire behind
   them and then goes off — and what you SAW was an ordinary shopper,
   drawn fullbright, with some fire on the floor near them. The whole
   mechanic was carried by the floor.

   THREE THINGS MAKE SOMEBODY LOOK ALIGHT and it needs all three:

     THE FLAME ON THEM       licks spawned at the body every tic, short
                             lived, rising. Because they are PARTICLES
                             and the person is moving eight units a tic,
                             the ones behind are the trail — the same
                             pool does the fire and the tail of it, and
                             a burning shopper who stops running piles
                             them up on the spot instead, which is
                             correct and costs nothing.
     THE SPRITE ITSELF       a fire colour map on the drawing, the same
                             trick as the ice: see `alight` in
                             js/material.js. Flames in front of an
                             unchanged shopper read as a shopper
                             standing behind a fire.
     THE LIGHT THEY THROW    a burning person running down a dark aisle
                             lights it, and the store has exactly one
                             fire light (js/fire.js), so they pull it
                             toward themselves like everything else that
                             burns.

   AND IT IS BUDGETED, because a crowd fire is dozens of them at once
   and the aisle is already full of the fire's own flames. Nobody more
   than `near` away throws anything at all — at that range they are two
   pixels and a glow — and no more than `most` of them in any one tic.
   ===================================================================== */
/* TONGUES, NOT A BONFIRE. The first cut threw two a tic at up to
   thirty-four units, which on a fifty-six-unit person is thirty
   overlapping blobs each a third of their height: what came out was a
   column of fire with somebody lost inside it, and the point of a
   burning shopper is that you can see WHO is burning. One a tic, smaller,
   and gone sooner — about a dozen alive on one person — leaves the
   drawing showing through, which is where the colour map does its work. */
export const BODY_FIRE = {
  near: 1400,          // past this a burning person is a glow, not a fire
  most: 14,            // how many of them may throw flame in one tic
  perTic: 1,           // licks each, a tic
  lifeMin: 8, lifeMax: 17,
  sizeMin: 10, sizeMax: 25,
  rise: 0.75,          // how fast a lick climbs
  lift: 6,             // and how far toward the eye it spawns, so it is
                       // in front of the person rather than fighting
                       // their quad for the same pixels
  /* AND THE SPARKS ARE RATIONED TOO, against the same pools the store's
     own fire throws from: fourteen people alight at one spark every two
     tics is two hundred and forty a second into a pool of six hundred
     and forty, which is a crowd fire that starves the AISLE of embers.
     Every fourth tic, phased off the actor's id so they are not in
     step, is a steady stream off one and a shared budget across many. */
  emberEvery: 4,       // tics between sparks off one of them
  smokeEvery: 10,      // and between puffs
};

export class Effects {
  constructor(game, atlases = null, flameAtlas = null) {
    this.game = game;
    this.embers = new Particles({
      max: 640, texture: atlases?.spark || null, frames: 1,
      blend: 'cutout', fullbright: true, name: 'embers', renderOrder: 12, nearShrink: 160,
    });
    /* Raised from 240 when the fire got six times faster and grew a body
       of smoke of its own (js/fire.js). These are the DRIFTING half of
       it: the standing plume over a burning aisle is billboards pinned to
       the hot cells, and these are what comes off the top of it and goes
       where the wind takes it. Both halves are wanted — a plume that does
       not shed is a prop, and puffs with nothing under them are litter. */
    this.smoke = new Particles({
      max: 360, texture: atlases?.smoke || null, frames: SMOKE_PUFFS,
      blend: 'alpha', fullbright: false, light: 0.55, name: 'smoke', renderOrder: 14, nearShrink: 90,
    });
    /* THE FIRE PEOPLE CARRY. Its own pool and not the store's, because
       the store's flames are PARKED on hot cells and re-placed every
       frame — which is right for a fire that sits still and wrong for
       one that is running down an aisle. These are simulated: spawned
       at the body, left where they were spawned, and the difference is
       the trail. Additive, like every other flame in the game, so a
       person well alight adds up toward white at the middle of them. */
    this.bodyFlames = new Particles({
      max: 460, texture: flameAtlas?.texture || null, frames: flameAtlas?.frames || 1,
      blend: 'add', fullbright: true, name: 'body-fire', renderOrder: 13, nearShrink: 40,
    });
    /* AND THE BLOOD IN THE AIR WHEN SOMEBODY IS BLOWN APART, which is
       its own pool and not the smoke's for the reason the body fire is
       its own: a warhead through a crowd wants several hundred of these
       at once, for a second, and in the smoke's pool that is a second in
       which every fire in the building stops smoking. Same puffs, drawn
       dark red and shaded by the room, and they FALL — see bloodSpray. */
    this.gore = new Particles({
      max: 700, texture: atlases?.smoke || null, frames: SMOKE_PUFFS,
      blend: 'alpha', fullbright: false, light: 0.7, name: 'gore-spray', renderOrder: 14, nearShrink: 60,
    });
    this._samples = [];
    /* the per-tic budget and the light the burning bodies throw, both
       reset by the first caller in a tic rather than by the frame, so
       they do not depend on where in Game.tic this is reached */
    this._fireTic = -1;
    this._fireLeft = 0;
    this._glow = { sx: 0, sy: 0, sw: 0, n: 0 };
  }

  attach(scene) {
    this.embers.attach(scene);
    this.smoke.attach(scene);
    this.bodyFlames.attach(scene);
    this.gore.attach(scene);
  }

  /* ------------------------------------------------------------------
     One burning body, one tic of fire off it.

     Called from Actor.burnTic, which already runs once per tic per
     thing that is alight — so there is no scan of seven hundred people
     to find the four that are on fire, and the budget is spent by
     whoever asks first. `scale` is for a body being EATEN rather than
     running (see Actor.burnAway): it is on fire too, but the flame has
     to stay off the drawing, because on that one the drawing is the
     effect.
     ------------------------------------------------------------------ */
  /** The per-tic reset of the budget and the light, done by whoever
   *  asks first in a tic. Pulled out of bodyFire the day a burning van
   *  wanted to add to the same light without being a body. */
  _newTic() {
    const g = this.game;
    if (this._fireTic === g.tics) return;
    this._fireTic = g.tics;
    this._fireLeft = BODY_FIRE.most;
    this._glow.sx = this._glow.sy = this._glow.sw = 0; this._glow.n = 0;
  }

  /** Something that is not a body pulling the one fire light toward
   *  itself: a vehicle charring in its bay, a rifle going off. `w` is
   *  how much of the light it is worth against a burning person's one. */
  glowAt(x, y, w = 1) {
    this._newTic();
    this._glow.sx += x * w; this._glow.sy += y * w;
    this._glow.sw += w; this._glow.n++;
  }

  bodyFire(a, scale = 1) {
    const g = this.game, p = g.player;
    if (!p || a.removed) return 0;
    this._newTic();
    const d2 = dist2(a.x, a.y, p.x, p.y);
    /* THE LIGHT IS NOT BUDGETED AND NOT RANGED THE SAME WAY. A torch
       three aisles off is not worth a particle and is very much worth
       the glow it puts on the shelving between you and it. */
    this._glow.sx += a.x * scale; this._glow.sy += a.y * scale;
    this._glow.sw += scale; this._glow.n++;
    if (d2 > BODY_FIRE.near * BODY_FIRE.near) return 0;
    if (this._fireLeft <= 0) return 0;
    this._fireLeft--;

    const B = BODY_FIRE;
    const h = a.height || 56;
    /* toward the eye, so the lick is in front of the person and not
       fighting their billboard for the same depth — the forest's trick,
       for the same reason, at a tenth of the arithmetic because a
       particle that moves does not have to be exact */
    const dx = p.x - a.x, dy = p.y - a.y;
    const inv = 1 / Math.max(1, Math.sqrt(d2));
    const lx = dx * inv * B.lift, ly = dy * inv * B.lift;
    const n = Math.max(1, Math.round(B.perTic * scale));
    for (let k = 0; k < n; k++) {
      /* UP THE BODY AND BIGGEST AT THE MIDDLE. A column of even flames
         is a pillar; a person on fire is bright at the chest with
         tongues off the shoulders. */
      const up = (pRandom() / 255);
      const size = (B.sizeMin + (B.sizeMax - B.sizeMin) * (1 - Math.abs(up - 0.45) * 1.6)) * scale;
      this.bodyFlames.spawn({
        x: a.x + lx + (pRandom() / 255 - 0.5) * 11,
        y: a.y + ly + (pRandom() / 255 - 0.5) * 11,
        z: a.z + 4 + up * h * 0.9,
        vx: (pRandom() / 255 - 0.5) * 0.5 + wind.x * 0.5,
        vy: (pRandom() / 255 - 0.5) * 0.5 + wind.y * 0.5,
        vz: B.rise + (pRandom() / 255) * 0.7,
        life: B.lifeMin + (pRandom() % (B.lifeMax - B.lifeMin)),
        size0: Math.max(6, size), size1: Math.max(3, size * 0.35),
        c0: [1, 1, 1], c1: [1, 0.72, 0.34],
        a0: 0.95, a1: 0,
        frame: pRandom() % (this.bodyFlames.opts.frames || 1), frameRate: 0.55,
        drag: 0.93, gravity: -0.02,
      });
    }
    /* and the sparks and the smoke off them, which are the parts of the
       trail that outlast the flame and go where the wind does */
    if ((g.tics + a.id) % B.emberEvery === 0) this.ember(a.x, a.y, a.z + h * 0.5, 1, 0.9 * scale);
    if ((g.tics + a.id) % B.smokeEvery === 0) this.puff(a.x, a.y, a.z + h * 1.05, 20 * scale, 120);
    return n;
  }

  /** The one fire light, pulled toward everybody who is alight. Same
   *  protocol the forest and the gun's flame use — see Fire.ticLight. */
  glowInto(acc) {
    const G = this._glow;
    if (G.sw <= 0) return;
    acc.sx += G.sx; acc.sy += G.sy; acc.sw += G.sw; acc.n += G.n;
  }

  /* ------------------------------------------------------------------
     A RIFLE GOING OFF

     The flash is on the drawing — the firing frame is orange and
     fullbright — so what is needed here is what the drawing cannot do:
     the light of it on the aisle for a frame, and a spit of hot gas
     out of the muzzle. Two licks off the body-fire pool, at the height
     of the rifle and out in front of it, gone in a quarter of a
     second; and the one fire light pulled hard toward the shooter, so
     a squad firing down a dark aisle lights it in flashes. `shots` on
     the trooper is for the test.
     ------------------------------------------------------------------ */
  muzzle(a) {
    this.glowAt(a.x, a.y, 2.5);
    const c = Math.cos(a.angle), s = Math.sin(a.angle);
    const h = (a.height || 56) * 0.66;
    for (let k = 0; k < 2; k++) {
      const out = 16 + k * 9;
      this.bodyFlames.spawn({
        x: a.x + c * out, y: a.y + s * out, z: a.z + h,
        vx: c * 1.4, vy: s * 1.4, vz: 0.2,
        life: 4 + k * 3,
        size0: 14 - k * 4, size1: 4,
        c0: [1, 0.95, 0.7], c1: [1, 0.55, 0.15],
        a0: 0.9, a1: 0,
        frame: pRandom() % (this.bodyFlames.opts.frames || 1), frameRate: 0.8,
        drag: 0.8, gravity: 0,
      });
    }
  }

  /* ------------------------------------------------------------------
     Spawning
     ------------------------------------------------------------------ */
  ember(x, y, z, n = 1, heat = 1) {
    for (let k = 0; k < n; k++) {
      const a = (pRandom() / 255) * Math.PI * 2;
      const sp = 0.3 + (pRandom() / 255) * 1.4;
      const hot = EMBER_RAMP[7], cool = EMBER_RAMP[2 + (pRandom() & 1)];
      this.embers.spawn({
        x: x + (pRandom() / 255 - 0.5) * 18, y: y + (pRandom() / 255 - 0.5) * 18, z,
        vx: Math.cos(a) * sp + wind.x, vy: Math.sin(a) * sp + wind.y,
        vz: 1.3 + (pRandom() / 255) * 2.2 * heat,
        life: 40 + (pRandom() % 60),
        size0: 1.5 + (pRandom() / 255) * 1.2, size1: 0.8,
        c0: hot, c1: cool, a0: 1, a1: 1,
        drag: 0.985, gravity: -0.055,
      });
    }
  }

  puff(x, y, z, size = 28, life = 150) {
    const warm = 0.55 + (pRandom() / 255) * 0.3;
    this.smoke.spawn({
      x: x + (pRandom() / 255 - 0.5) * 24, y: y + (pRandom() / 255 - 0.5) * 24, z,
      vx: (pRandom() / 255 - 0.5) * 0.5 + wind.x * 1.6, vy: (pRandom() / 255 - 0.5) * 0.5 + wind.y * 1.6,
      vz: 0.9 + (pRandom() / 255) * 0.7,
      life: life + (pRandom() % 60),
      size0: size, size1: size * 4.2,
      c0: [0.34 * warm, 0.30 * warm, 0.28 * warm], c1: [0.16, 0.16, 0.18],
      a0: 0.55, a1: 0,
      /* AND IT WALKS THE LOOP. At a fiftieth of a frame a tic the old
         puff changed drawing three times in its whole life, which with
         four unrelated blobs was three pops; now it is a smooth churn
         through a loop twice over while it rises. */
      frame: pRandom() % SMOKE_PUFFS, frameRate: 0.09,
      drag: 0.992, gravity: 0.004,
    });
  }

  /** Blood in the air, out of the top of a drilled head: the smoke's
   *  own frames, small, dark red, and gone quickly — a mist over the
   *  fountain of pieces js/people.js throws, so the spurt has a body. */
  bloodPuff(x, y, z) {
    this.smoke.spawn({
      x: x + (pRandom() / 255 - 0.5) * 6, y: y + (pRandom() / 255 - 0.5) * 6, z,
      vx: (pRandom() / 255 - 0.5) * 0.6, vy: (pRandom() / 255 - 0.5) * 0.6,
      vz: 0.9 + (pRandom() / 255) * 0.8,
      life: 14 + (pRandom() % 10),
      size0: 7, size1: 16,
      c0: [0.62, 0.05, 0.04], c1: [0.30, 0.02, 0.02],
      a0: 0.75, a1: 0,
      frame: pRandom() % SMOKE_PUFFS, frameRate: 0.2,
      drag: 0.95, gravity: -0.01,
    });
  }

  /** A SPRAY OF BLOOD out of (x, y, z), thrown along (dx, dy, dz) — or
   *  every way at once if that is zero — `n` of it, at `force`. Two
   *  things in one call, because a body coming apart is two things: a
   *  MIST that hangs and spreads, dark red going brown, and DROPS, small
   *  and fast and heavy, that arc out and come down, which is what makes
   *  it read as liquid rather than as smoke. The drops stop at the floor
   *  and leave nothing: the decals are what is left, and the caller lays
   *  those — see Giblets.eviscerate. */
  bloodSpray(x, y, z, dx = 0, dy = 0, dz = 0, n = 12, force = 1) {
    const dl = Math.hypot(dx, dy, dz);
    for (let k = 0; k < n; k++) {
      const th = (pRandom() / 255) * Math.PI * 2, ph = (pRandom() / 255) * 2 - 1;
      const cs = Math.sqrt(1 - ph * ph);
      /* a direction: round the throw if there is one, anywhere if not */
      let ux = Math.cos(th) * cs, uy = Math.sin(th) * cs, uz = Math.abs(ph) * 0.8 + 0.2;
      if (dl > 0) { ux = ux * 0.55 + dx / dl; uy = uy * 0.55 + dy / dl; uz = uz * 0.55 + dz / dl + 0.3; }
      const sp = force * (1.5 + (pRandom() / 255) * 6.5);
      const drop = (k & 1) === 0;
      this.gore.spawn({
        x: x + (pRandom() / 255 - 0.5) * 10, y: y + (pRandom() / 255 - 0.5) * 10, z,
        vx: ux * sp, vy: uy * sp, vz: uz * sp * (drop ? 1.1 : 0.4),
        life: drop ? 26 + (pRandom() % 22) : 30 + (pRandom() % 30),
        size0: drop ? 4 + (pRandom() & 3) : 12 + (pRandom() % 12),
        size1: drop ? 3 : 34 + (pRandom() % 20),
        c0: drop ? [0.55, 0.02, 0.02] : [0.62, 0.04, 0.035], c1: drop ? [0.35, 0.01, 0.01] : [0.28, 0.03, 0.02],
        a0: drop ? 1 : 0.82, a1: drop ? 0.9 : 0,
        frame: pRandom() % SMOKE_PUFFS, frameRate: drop ? 0 : 0.15,
        drag: drop ? 0.985 : 0.93, gravity: drop ? -0.42 : -0.03, kind: drop ? 1 : 0,
      });
    }
  }

  /** Where a flame landed: a spit of sparks and a little smoke. */
  splash(x, y, z) {
    this.ember(x, y, z + 6, 2, 0.8);
    if ((pRandom() & 3) === 0) this.puff(x, y, z + 10, 18, 90);
  }

  /* THE SAME PUFFS, COLD. The smoke frames are shapeless grey billows,
     which is what a cloud of expanding CO2 is too, so the difference is
     entirely in the colour and the physics: this one is near-white and
     blue, it is BRIEF where smoke hangs about, and it falls instead of
     rising — cold gas is heavier than the air it is in, and a jet of it
     pools along the floor rather than going up to the ceiling. */
  frostPuff(x, y, z, size = 22, life = 40) {
    this.smoke.spawn({
      x: x + (pRandom() / 255 - 0.5) * 16, y: y + (pRandom() / 255 - 0.5) * 16, z,
      vx: (pRandom() / 255 - 0.5) * 0.8, vy: (pRandom() / 255 - 0.5) * 0.8,
      vz: -0.15 - (pRandom() / 255) * 0.35,
      life: life + (pRandom() % 30),
      size0: size, size1: size * 2.6,
      c0: [0.82, 0.94, 1.05], c1: [0.40, 0.56, 0.72],
      a0: 0.5, a1: 0,
      frame: pRandom() % SMOKE_PUFFS, frameRate: 0.22,
      drag: 0.94, gravity: -0.006,
    });
  }

  /** Where the extinguisher's stream landed. */
  chillSplash(x, y, z) {
    this.frostPuff(x, y, z + 8, 18, 30);
  }

  /* ------------------------------------------------------------------
     JET WASH

     What the gunship's engines do to whatever their exhaust lands on
     (js/vtol.js): grit thrown OUTWARD along the surface, fast and low,
     and gone inside a second — nothing of it rises, because it is not
     smoke, it is the car park being blown about. The smoke pool's
     frames, pale, small to wide, at three to five units a tic across
     the ground where a puff drifts at half a unit up. `k` is how hard
     the engine is blowing on this spot, which is how near it is; the
     surface's normal says which way "along" is — across the tarmac for
     the ground, up and along the wall for a wall.
     ------------------------------------------------------------------ */
  wash(x, y, z, k = 1, nx = 0, ny = 0, nz = 1) {
    const a = (pRandom() / 255) * Math.PI * 2;
    const sp = (1.8 + (pRandom() / 255) * 2.8) * (0.5 + 0.5 * k);
    /* two unit directions across the normal, the decals' own choice of
       them: x and y on a floor, along and up on a wall */
    let ux, uy, uz, vx, vy, vz;
    if (Math.abs(nz) > 0.5) { ux = 1; uy = 0; uz = 0; vx = 0; vy = 1; vz = 0; }
    else { ux = -ny; uy = nx; uz = 0; vx = 0; vy = 0; vz = 1; }
    const c = Math.cos(a), s = Math.sin(a);
    const pale = 0.55 + (pRandom() / 255) * 0.25;
    this.smoke.spawn({
      x: x + (pRandom() / 255 - 0.5) * 30, y: y + (pRandom() / 255 - 0.5) * 30, z: z + 3,
      vx: (ux * c + vx * s) * sp + nx * 0.4, vy: (uy * c + vy * s) * sp + ny * 0.4, vz: (uz * c + vz * s) * sp * 0.6 + nz * 0.5,
      life: 16 + (pRandom() % 14),
      size0: 14 + 10 * k, size1: 46 + 30 * k,
      c0: [0.50 * pale, 0.47 * pale, 0.44 * pale], c1: [0.30, 0.29, 0.28],
      a0: 0.34 * (0.4 + 0.6 * k), a1: 0,
      frame: pRandom() % SMOKE_PUFFS, frameRate: 0.25,
      drag: 0.91, gravity: -0.03,
    });
  }

  /** A FIREBALL, for an aircraft going up: the body-fire pool's
   *  additive frames at many times the size a shopper carries, rising
   *  slowly and dying to orange. One call is one ball; a bang is a
   *  dozen of them over the thing that banged. */
  fireball(x, y, z, size = 90, life = 22) {
    this.bodyFlames.spawn({
      x: x + (pRandom() / 255 - 0.5) * size * 0.6, y: y + (pRandom() / 255 - 0.5) * size * 0.6,
      z: z + (pRandom() / 255 - 0.5) * size * 0.5,
      vx: (pRandom() / 255 - 0.5) * 2.2, vy: (pRandom() / 255 - 0.5) * 2.2, vz: 0.8 + (pRandom() / 255) * 1.6,
      life: life + (pRandom() % 12),
      size0: size * 0.55, size1: size * 1.35,
      c0: [1, 1, 1], c1: [1, 0.45, 0.12],
      a0: 1, a1: 0,
      frame: pRandom() % (this.bodyFlames.opts.frames || 1), frameRate: 0.45,
      drag: 0.94, gravity: -0.01,
    });
  }

  /* ------------------------------------------------------------------
     One tic
     ------------------------------------------------------------------ */
  tic() {
    const g = this.game, p = g.player;
    if (p) {
      /* the store's fire */
      const F = g.fire;
      if (F && F.active.length) {
        const len = F.active.length;
        /* EIGHT SAMPLES, NOT THREE. With the fire on a three-tic clock a
           run of shelving is alight and spent inside four seconds, and at
           three samples a tic a given cell got one spark every three —
           which is a fire that has gone out by the time anything has come
           off it. Still a sample and not a sum: with a whole aisle going
           there are hundreds of cells and the answer does not change. */
        for (let k = 0; k < 8; k++) {
          const i = F.active[(pRandom() * 256 + pRandom()) % len];
          const h = F.heat[i];
          if (h < 110) continue;
          const x = F.worldX(i % F.cols), y = F.worldY((i / F.cols) | 0);
          if (dist2(x, y, p.x, p.y) > 900 * 900) continue;
          const z = (g.level.sectors[F.sectorOf[i]]?.floor ?? 0);
          if (pRandom() < h * 0.55) this.ember(x, y, z + 14 + (pRandom() & 31), 1, h / 255);
          /* and off the TOP of the flame rather than off the floor, so it
             leaves the plume instead of appearing inside it */
          if ((g.tics & 1) === 0 && pRandom() < 110) this.puff(x, y, z + 52, 32, 150);
        }
      }
      /* the forest's */
      const forest = g.forest;
      if (forest && forest.active.length) {
        const out = this._samples;
        forest.emitters(p.x, p.y, 1200, 4, out);
        for (const e of out) {
          const q = (e.t - 0.5) / 0.3;
          const flame = Math.exp(-q * q);
          if (pRandom() < 40 + flame * 150) this.ember(e.x, e.y, e.h * (0.35 + (pRandom() / 255) * 0.6), e.tree ? 2 : 1, 0.6 + flame);
          if ((g.tics & 3) === 1 && pRandom() < 60 + flame * 120) this.puff(e.x, e.y, e.h * 0.9, e.tree ? 34 : 20, 170);
        }
      }
    }

    const lv = g.level;
    this.embers.tic((i, nx, ny, nz) => {
      /* embers go out on the floor and on walls */
      const s = lv.sectorAt(nx, ny);
      const floor = s ? s.floor : 0;
      return nz <= floor + 1;
    });
    this.smoke.tic();
    /* the licks stop at a wall for the same reason the stream's do: fire
       that reaches through the frozen aisle into the stockroom is not a
       fire, it is a bug with a texture on it */
    this.bodyFlames.tic((i, nx, ny, nz) => {
      const s = lv.sectorAt(nx, ny);
      return !s || nz <= s.floor - 2 || nz >= s.ceil;
    });
    /* the blood: a drop stops at the floor, the mist at nothing */
    if (this.gore.count) this.gore.tic((i, nx, ny, nz) => {
      if (this.gore.kind[i] !== 1) return false;
      const s = lv.sectorAt(nx, ny);
      return !s || nz <= s.floor + 1;
    });
  }

  render(billboardRot) {
    this.embers.render(billboardRot);
    this.smoke.render(billboardRot);
    this.bodyFlames.render(billboardRot);
    this.gore.render(billboardRot);
  }

  get liveCount() { return this.embers.count + this.smoke.count + this.gore.count; }
}

/* --------------------------------------------------------------------
   The pictures: a spark and four puffs of smoke, generated like all the
   other art
   ------------------------------------------------------------------ */
/* How many frames of drifting smoke there are. One loop, not a set of
   variants — see bakeEffectAtlases. Exported because js/frost.js draws
   its CO2 with the same atlas and has to walk the same loop. */
export const SMOKE_PUFFS = 8;

export function bakeEffectAtlases() {
  const spark = new Pix(4, 4, 3, false);
  spark.fill('bone', 1.0);
  /* EIGHT PUFFS THAT ARE ONE PUFF, which is the fix for smoke that
     popped. There were four, and they were four INDEPENDENT noise
     fields: a drifting puff walking from one to the next did not churn,
     it cut, four times in its life, to a completely different blob. So
     they are built the way the body of smoke over the fire is built —
     one fbm field, whose lattice wraps after H rows, sampled with a
     vertical offset of H/N per frame. Frame N is frame 0 again, every
     step between them is the same small scroll, and what a puff does
     over its life is turn over rather than flicker. */
  const PW = 32, PN = SMOKE_PUFFS;
  const pn = fbm(PW, PW, 4, 3, 70);
  const puffs = [];
  for (let f = 0; f < PN; f++) {
    const p = new Pix(PW, PW, 40 + f, false);
    const off = Math.round(f * PW / PN);
    for (let y = 0; y < PW; y++)
      for (let x = 0; x < PW; x++) {
        const sy = (y + off) % PW;
        const dx = (x - 15.5) / 15.5, dy = (y - 15.5) / 15.5;
        const d = Math.hypot(dx, dy);
        const edge = Math.max(0, 1 - d);
        const a = Math.max(0, Math.min(1, edge * 1.8 * (0.45 + pn[sy * PW + x] * 0.8) - 0.15));
        if (a <= 0.05) continue;
        p.set(x, y, 235, 232, 230, Math.round(a * 255));
      }
    puffs.push(p);
  }
  /* The stream's particle: a ball of fire, white at the heart through
     the ember colours to a soft dark-red rim, eight of them so a stream
     is not one blob repeated. Drawn additively, so where they overlap
     they add up to white — which is what makes a dense arc of them read
     as one continuous flame rather than as beads on a string. */
  const balls = [];
  for (let f = 0; f < 8; f++) {
    const p = new Pix(32, 32, 90 + f, false);
    const n = fbm(32, 32, 4, 3, 300 + f * 17);
    for (let y = 0; y < 32; y++)
      for (let x = 0; x < 32; x++) {
        const dx = (x - 15.5) / 15.5, dy = (y - 15.5) / 15.5;
        const d = Math.hypot(dx, dy);
        const v = Math.max(0, Math.min(1, (1 - d) * (0.6 + n[y * 32 + x] * 0.8)));
        if (v < 0.06) continue;
        const a = Math.min(1, v / 0.35);
        p.ink(x, y, 'fire', Math.min(1, v * 1.15), Math.round(a * 255));
      }
    balls.push(p);
  }
  return { spark: atlasTexture([spark]), smoke: atlasTexture(puffs), fireball: atlasTexture(balls) };
}
