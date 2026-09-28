/* =====================================================================
   MEWD — the sprite bank
   =====================================================================

   Doom's sprite naming, because it is a good scheme and because every
   piece of documentation about how Doom animates its monsters is written
   in it:

     BLSTA1   four letters of sprite name, one frame letter, one rotation
              digit. Rotation 1 is head-on, 2 through 8 go round, and 0
              means "this frame looks the same from everywhere".

   Frame letters run A, B, C... in the order the animation uses them, and
   the state tables in states.js refer to them exactly that way. So

     WALK: A A B B C C D D
     DIE:  H I J K L

   is both the documentation and the code.

   NOBODY IN THIS FILE IS A PERSON ANY MORE. There were two monsters
   built here out of a jointed figure — a rig, a walk cycle, eight
   rotations rendered per frame, faces projected onto a sphere so they
   turned with the head — and they are gone, along with js/figure.js and
   the Freedoom frames that ended up replacing them. The people in the
   shop now are painted standees from the galvarius project, and they
   arrive as a strip; js/people.js cuts it up and hands it to this bank.

   What is left here is everything the game draws ITSELF: the fire, the
   trolleys, the crates, the light fittings, the blood, the weapons in
   your hands and the placeholders that stand in for any of the outside
   art that has not arrived. The placeholders matter more than they look
   — the game has to run with an empty assets/ directory, because that
   is what the headless test does.
   ===================================================================== */

import * as THREE from 'three';
import { Pix, fbm, valueNoise, speckle, drawTextCentred } from './pixel.js';
import { makeRng, pRandom } from './util.js';
import { ramp, PALETTE } from './palette.js';
import { WEAPON_TILE, WEAPON_TOP, CLEAR_INDEX, CUTOUTS } from './art-data.js';
import { CELLS, ADULT, SHOPPERS, SPLATS, ASHES, BLASTS,
         SHOPPER_SPRITE, SPLAT_SPRITE, ASH_SPRITE, BLAST_SPRITE,
         TROOPS } from './people.js';
import { fireFrames, FIRE_FRAMES, BLAZE_FRAMES, EMBER_FRAMES } from './fireart.js';

/* A frame is a letter, and the letters stop at Z. */
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

export class SpriteBank {
  constructor() { this.frames = new Map(); this.warned = new Set(); this.counts = new Map(); }

  /** How many frames a set has — the highest letter given to it. */
  count(name) { return this.counts.get(name) || 0; }

  /** One frame: eight views, each a Pix. Uploaded on demand. */
  addFrame(name, letter, views, opts = {}) {
    const key = name + letter;
    this.counts.set(name, Math.max(this.counts.get(name) || 0, letter.charCodeAt(0) - 64));
    const entry = {
      key, views, textures: new Array(8).fill(null),
      w: opts.w ?? views[0].w, h: opts.h ?? views[0].h,
      scale: opts.scale ?? 1,
      fullbright: !!opts.fullbright,
      /* how far up off the floor the sprite's foot sits — 0 for anything
         standing on it, positive for something hanging or flying */
      lift: opts.lift ?? 0,
    };
    this.frames.set(key, entry);
    return entry;
  }

  get(name, letter) {
    const e = this.frames.get(name + letter);
    if (e) return e;
    if (!this.warned.has(name + letter)) {
      this.warned.add(name + letter);
      console.warn('missing sprite frame:', name + letter);
    }
    return this.frames.get('MISSA');
  }

  /** Lazily upload one rotation. Most frames never face you from every
   *  angle, so most rotations are never uploaded at all. */
  texture(entry, rot) {
    let t = entry.textures[rot];
    if (t) return t;
    t = new THREE.CanvasTexture(entry.views[rot].toCanvas());
    t.magFilter = THREE.NearestFilter;
    t.minFilter = THREE.NearestFilter;   // sprites do not mip: a mipped
    t.generateMipmaps = false;           // sprite loses its cut-out edge
    t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
    t.colorSpace = THREE.SRGBColorSpace;
    t.needsUpdate = true;
    entry.textures[rot] = t;
    return t;
  }
}

/** Anything that is the same from every side: barrels, cans, bollards. */
function radial(draw, w = 32, h = 40, seed = 1) {
  const p = new Pix(w, h, seed, false);
  draw(p);
  p.snap(0.3);
  return new Array(8).fill(p);
}

/* ---------------------------------------------------------------------
   THE QUAD LAUNCHER'S ROCKET, one view of it

   A little model, splatted: an olive tube with a yellow band and a grey
   nose, four swept fins in an X at the tail, a dark nozzle, and a cone
   of flame out of the back that is its own light. Every surface is a
   cloud of points in the rocket's own frame — `a` along it, nose
   forward, `b` up, `c` across — turned to the view, dropped onto the
   sprite with a depth test, and lit by one fixed light from high on the
   left, the same light the guns in your hands are lit by.

   `rot` is Doom's: which way the rocket is heading, in eighths of a
   turn, measured from STRAIGHT AT YOU — 0 is its nose, 4 its flame,
   2 heading off to your right and 6 to your left. js/missiles.js picks
   the eighth from where it is and where you are.
   --------------------------------------------------------------------- */
function rocketView(rot, flame, seed) {
  const W = 64, H = 18, cx = W / 2, cy = H / 2;
  const p = new Pix(W, H, seed, false);
  const th = rot * Math.PI / 4, s = Math.sin(th), c = Math.cos(th);
  const zbuf = new Float32Array(W * H).fill(-Infinity);
  const L = [-0.45, 0.75, 0.5], ll = Math.hypot(...L);
  const splat = (a, b, cc, na, nb, nc, key, t, lit = true) => {
    /* the rocket's frame into the view's: x right, y up, z at the eye */
    const X = a * s + cc * c, Y = b, Z = a * c - cc * s;
    const px = Math.round(cx + X - 0.5), py = Math.round(cy - Y - 0.5);
    if (px < 0 || py < 0 || px >= W || py >= H) return;
    const i = py * W + px;
    if (Z <= zbuf[i]) return;
    zbuf[i] = Z;
    let level = t;
    if (lit) {
      const nx = na * s + nc * c, ny = nb, nz = na * c - nc * s;
      const d = Math.max(0, (nx * L[0] + ny * L[1] + nz * L[2]) / ll);
      level = t * (0.34 + 0.66 * d);
    }
    p.ink(px, py, key, Math.max(0.02, Math.min(0.99, level)));
  };
  const R = 2.6;
  /* the tube, the band on it, and the nozzle ring at the back */
  for (let a = -12; a <= 8; a += 0.25)
    for (let k = 0; k < 48; k++) {
      const ph = k / 48 * Math.PI * 2, b = Math.cos(ph), cc = Math.sin(ph);
      const band = a > 3.5 && a < 5.5;
      splat(a, b * R, cc * R, 0, b, cc, band ? 'yellow' : a < -11.2 ? 'grey' : 'olive', band ? 0.86 : a < -11.2 ? 0.34 : 0.62);
    }
  /* the nose, grey, a cone six long */
  for (let a = 8; a <= 14; a += 0.2) {
    const r = R * (1 - (a - 8) / 6.2);
    for (let k = 0; k < 40; k++) {
      const ph = k / 40 * Math.PI * 2, b = Math.cos(ph), cc = Math.sin(ph);
      splat(a, b * r, cc * r, 0.4, b, cc, 'grey', 0.7);
    }
  }
  /* four swept fins in an X */
  for (const ph of [Math.PI / 4, 3 * Math.PI / 4, 5 * Math.PI / 4, 7 * Math.PI / 4]) {
    const b = Math.cos(ph), cc = Math.sin(ph);
    for (let a = -12; a <= -6.5; a += 0.2)
      for (let r = R; r <= 7 - (a + 12) * 0.62; r += 0.2)
        for (const side of [-1, 1])
          splat(a, b * r + side * 0.3 * -cc, cc * r + side * 0.3 * b, 0, -cc * side, b * side, 'olive', 0.5);
  }
  /* AND THE FLAME, its own light: white at the nozzle, yellow, then
     orange and red to a point `flame` long, a little ragged */
  const rng = makeRng(seed * 7 + flame);
  for (let d = 0; d <= flame; d += 0.25) {
    const q = d / flame, r = 2.3 * Math.pow(1 - q, 0.7) * (0.85 + 0.3 * rng());
    for (let rr = 0; rr <= r; rr += 0.35)
      for (let k = 0; k < 24; k++) {
        const ph = k / 24 * Math.PI * 2;
        const core = rr < r * 0.45 && q < 0.55;
        splat(-12.2 - d, Math.cos(ph) * rr, Math.sin(ph) * rr, 0, 0, 0,
              core ? 'yellow' : 'fire', core ? 0.99 : 0.97 - 0.55 * q - 0.2 * (rr / Math.max(r, 0.01)), false);
      }
  }
  p.snap(0.3);
  return p;
}

/* ---------------------------------------------------------------------
   AN EXPLOSION, one frame of eight

   A ball of fire torn at its edge by noise, growing fast and then
   slowly — the square root of the frame — hottest at the middle; a
   shock ring and flying sparks in the first frames; and from halfway
   on the outside turns to smoke and the smoke to holes, so the last
   frame is a ragged dark ball with a little fire left in it. The noise
   is a lattice of hashed values, smoothed: the angle round the ball
   decides the edge and the position the mottling, so every frame is
   the same explosion further on and not eight different ones.
   --------------------------------------------------------------------- */
function blastFrame(k) {
  /* sixty-four across, the most any sprite is, and drawn in eightieths
     of it scaled down to fit — see BOOM.scale in js/missiles.js for the
     size in the world */
  const W = 64, cx = W / 2, cy = W / 2, t = k / 7, sc = W / 80;
  const p = new Pix(W, W, 300 + k, false);
  const hash = (i, j, s) => {
    let h = (i * 374761393 + j * 668265263 + s * 2147483647) | 0;
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  };
  const noise = (x, y, s) => {
    const i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j;
    const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    const a = hash(i, j, s), b = hash(i + 1, j, s), c = hash(i, j + 1, s), d = hash(i + 1, j + 1, s);
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy;
  };
  const Rb = (9 + 25 * Math.sqrt(t)) * sc;
  for (let y = 0; y < W; y++)
    for (let x = 0; x < W; x++) {
      const dx = x + 0.5 - cx, dy = y + 0.5 - cy, d = Math.hypot(dx, dy);
      const ang = Math.atan2(dy, dx);
      const edge = Rb * (0.74 + 0.36 * noise(ang * 2.2 + 11, 3.3, 7) + 0.12 * noise(ang * 6.1, 1.7, 9));
      if (d > edge) continue;
      const q = d / edge;
      const mottle = noise(x * 0.17 / sc, y * 0.17 / sc + k * 0.6, 3);
      /* it thins from the outside as it goes: holes where the mottling
         is lowest, spreading inward over the second half */
      if (t > 0.45 && mottle < (t - 0.45) * 1.5 * (0.35 + q)) continue;
      const heat = (1 - q) * (1.15 - 0.95 * t) + 0.3 * (mottle - 0.5) - 0.08;
      if (heat < 0.18) p.ink(x, y, 'grey', 0.12 + 0.22 * mottle + 0.1 * (1 - t));
      else if (heat > 0.92 && t < 0.4) p.ink(x, y, 'yellow', 0.99);
      else p.ink(x, y, 'fire', Math.min(0.99, 0.32 + heat * 0.7));
    }
  /* the shock ring, torn, in the first three frames after the flash */
  if (k >= 1 && k <= 3) {
    const Rs = Rb * (1.22 + 0.12 * k);
    for (let a = 0; a < 720; a++) {
      const ang = a / 720 * Math.PI * 2;
      if (noise(ang * 5, k, 13) < 0.42) continue;
      p.ink(Math.round(cx + Math.cos(ang) * Rs), Math.round(cy + Math.sin(ang) * Rs), 'fire', 0.93 - 0.12 * k);
    }
  }
  /* and the sparks thrown clear of it */
  if (k <= 4) {
    const rng = makeRng(77);
    for (let n = 0; n < 14; n++) {
      const ang = rng() * Math.PI * 2, r = Rb * (1.05 + 0.5 * rng()) + k * 5 * sc;
      const x = Math.round(cx + Math.cos(ang) * r), y = Math.round(cy + Math.sin(ang) * r);
      p.ink(x, y, 'fire', 0.95);
      if (k < 2) p.ink(x + 1, y, 'fire', 0.8);
    }
  }
  p.snap(0.3);
  return p;
}

/* ====================================================================
   Bake the lot
   ==================================================================== */
/**
 * Every sprite this program draws itself.
 *
 * Handed a bank it already filled, it draws over the top of it — which
 * is how the art palette changes under a game that is already running.
 * `addFrame` replaces an entry by key, so the result is the same bank
 * it would have made from empty. WHAT IT DOES NOT KNOW ABOUT is the
 * photographed art that lands on top of some of these names at boot
 * (see THE PEOPLE ARE NOT DRAWN BY THIS PROGRAM in js/main.js): a
 * repaint puts the stand-ins back, and the caller has to lay the
 * photographs over them again. applyTone in js/main.js does.
 */
export function bakeSprites(bank = new SpriteBank()) {
  const t0 = (typeof performance !== 'undefined' ? performance.now() : Date.now());

  /* --- something visibly wrong, for a frame that does not exist --- */
  {
    const p = new Pix(32, 48, 1, false);
    for (let y = 0; y < 48; y++) for (let x = 0; x < 32; x++)
      if (((x >> 2) + (y >> 2)) & 1) p.set(x, y, 255, 0, 255, 255);
    bank.addFrame('MISS', 'A', new Array(8).fill(p));
  }

  /* --- the crowd, when the crowd has not arrived ------------------
     A person-shaped hole in seventeen colours. It is not meant to be
     mistaken for the art in assets/people; it is meant to be a body of
     the right height standing in the right place, so that the map, the
     collision, the fire and the gibbing can all be tested with nothing
     on disk. Real standees land on top of these under the same names. */
  {
    const COATS = ['red', 'blue', 'green', 'olive', 'brown', 'purple', 'pink', 'cyan', 'yellow', 'rust'];
    for (let v = 0; v < SHOPPERS; v++) {
      const rng = makeRng(820 + v);
      const coat = COATS[v % COATS.length];
      const legs = ['grey', 'blue', 'brown', 'olive'][v % 4];
      const H = CELLS.shoppers.h, W = CELLS.shoppers.w;
      /* a shade under the adult height, and a shade of build, so a row
         of them is not a row of one person */
      const tall = Math.round(ADULT * (0.9 + rng() * 0.1));
      const wide = 5 + Math.round(rng() * 3);
      bank.addFrame(SHOPPER_SPRITE + v, 'A', radial(p => {
        const cx = W >> 1, foot = H - 1, head = H - tall;
        for (let y = foot - Math.round(tall * 0.42); y <= foot; y++)          // legs
          for (let x = -wide + 2; x <= wide - 2; x++)
            if (Math.abs(x) > 1) p.ink(cx + x, y, legs, 0.30 + (x < 0 ? 0.08 : 0));
        for (let y = head + 9; y < foot - Math.round(tall * 0.4); y++)        // coat
          for (let x = -wide; x <= wide; x++)
            p.ink(cx + x, y, coat, 0.34 + (x < 0 ? 0.10 : -0.04));
        p.disc(cx, head + 5, 4.4, 'flesh', 0.40);                              // head
        p.disc(cx - 1, head + 4, 2.0, 'flesh', 0.52);
      }, W, H, 820 + v));
    }
  }

  /* --- and the troops, when the troops have not arrived ------------
     The same bargain for the SWAT and the army: a body of the right
     height under every letter the state table names, so the chase, the
     rifle and the deaths all run headless and the user's sheets land on
     top under the same names (see addTroops in js/people.js). The
     standing letters are one figure with a rifle; the falling ones lean
     over; the lying and the coming-apart ones are a body's length on
     the floor.

     TWO OF THEM, off one drawing and two palettes — navy and grey under
     a cyan visor for the SWAT, olive and brown under a bare helmet for
     the army — because two stand-ins that look alike are a stand-in
     that does not tell you which one is shooting at you, and the day
     one sheet loads and the other does not is exactly the day it
     matters. A third troop is a third row in KIT. */
  {
    const H = CELLS.troops.h, W = CELLS.troops.w;
    const KIT = {
      SWAT: { legs: 'blue',  vest: 'grey',  hat: 'grey',  visor: 'cyan',  seed: 900 },
      ARMY: { legs: 'olive', vest: 'brown', hat: 'olive', visor: null,    seed: 960 },
    };
    for (const [key, t] of Object.entries(TROOPS)) {
      const kit = KIT[key] || KIT.SWAT;
      const draw = (kind, k) => radial(p => {
        const cx = W >> 1, foot = H - 1;
        if (kind === 'up') {
          const head = H - t.height;
          for (let y = foot - 27; y <= foot; y++)                             // legs
            for (let x = -5; x <= 5; x++) if (Math.abs(x) > 1) p.ink(cx + x, y, kit.legs, 0.22);
          for (let y = head + 12; y < foot - 26; y++)                        // vest
            for (let x = -7; x <= 7; x++) p.ink(cx + x, y, kit.vest, 0.10 + (x < 0 ? 0.05 : 0));
          p.hline(cx - 14, cx + 9, head + 22, 'grey', 0.06);                  // the rifle
          p.hline(cx - 14, cx + 9, head + 23, 'grey', 0.08);
          p.disc(cx, head + 6, 5.5, kit.hat, 0.08);                           // helmet
          if (kit.visor) p.hline(cx - 3, cx + 3, head + 7, kit.visor, 0.55);
        } else if (kind === 'down') {
          const lean = k * 6;
          for (let y = foot - 40 + lean; y <= foot; y++)
            for (let x = -7; x <= 7; x++)
              p.ink(cx + x, y, y < foot - 22 + lean ? kit.vest : kit.legs, 0.16);
          p.disc(cx, foot - 42 + lean, 5.5, kit.hat, 0.08);
        } else {
          for (let y = foot - 9; y <= foot; y++)
            for (let x = -28; x <= 28; x++) p.ink(cx + x, y, kind === 'gore' ? 'red' : kit.legs, 0.22);
          if (kind === 'gore') for (let i = 0; i < 12; i++) p.disc(cx - 24 + i * 4, foot - 14 - (i % 3) * 5, 1.5, 'red', 0.4);
        }
      }, W, H, kit.seed + k);
      [...t.turn].forEach(L => bank.addFrame(t.sprite, L, draw('up', 0)));
      [...t.flat].forEach((L, i) =>
        bank.addFrame(t.sprite, L, draw(i < 4 ? 'down' : i < 7 ? 'flat' : 'gore', i)));
    }
  }

  /* --- fire, in three sizes -----------------------------------------
     What is on a shelf, what a whole gondola turns into, and what is
     left guttering on the floor afterwards. Drawn by js/fireart.js —
     see that file for why they are drawn rather than painted.

     The SCALES are world units per pixel and are set so these three come
     out the sizes they have always been: a flame on a shelf is about
     fifty units, a blaze a hundred, an ember twenty-five. A cell is
     wider than the flame inside it, deliberately: the licks that break
     off the top and the sway at the tip need somewhere to go, and a
     flame that touches the edge of its own cell is a flame with a
     straight side. */
  fireFrames(32, 48, FIRE_FRAMES, 7).forEach((p, i) =>
    bank.addFrame('FIRE', LETTERS[i], new Array(8).fill(p), { fullbright: true }));
  fireFrames(48, 64, BLAZE_FRAMES, 19, { taper: 0.8 }).forEach((p, i) =>
    bank.addFrame('BLAZ', LETTERS[i], new Array(8).fill(p), { fullbright: true, scale: 1.65 }));
  fireFrames(20, 28, EMBER_FRAMES, 31, { taper: 0.62 }).forEach((p, i) =>
    bank.addFrame('EMBR', LETTERS[i], new Array(8).fill(p), { fullbright: true, scale: 0.92 }));

  /* --- and what stands over it -------------------------------------
     A FIRE WITHOUT SMOKE IS A LIGHT. Everything about a burning
     supermarket that you would actually notice from the car park is the
     smoke: it is bigger than the flames by a factor of ten, it is the
     thing that gets into the aisle you were about to walk down, and it
     is the only part of a fire that is still there after the fire is
     out. There was already drifting smoke in the game — the puffs off
     js/effects.js, which are particles and go where the wind takes them
     — and no BODY of it standing on the fire itself. This is that body,
     and js/fire.js parks it over the hottest, most buried cells.

     IT CHURNS AND IT LOOPS EXACTLY, by the trick fbm makes free: the
     noise lattice wraps after h rows, so sampling it with a vertical
     offset of h/count per frame comes back to itself after count
     frames. The same field decides the silhouette AND the shading, so
     the scroll that stirs the inside also eats the outline — which is
     what separates smoke from a grey ball with a pattern on it.

     SIXTEEN AND NOT EIGHT, at the user's request that it be smoother.
     The loop was always exact; what it was not was FINE. Eight frames
     over a loop that wants to last a second and a half is a step every
     eleven tics, and eleven tics of a 64-pixel sprite holding still is
     long enough to see it holding still — the churn read as a flick
     book. Sixteen is the same loop with half the step, and it costs
     eight more 64-square sprites, which is nothing. The step it wraps by
     stays exact because H divides by 16 as happily as by 8.

     NOT SNAPPED, unlike almost everything else here. A cut-out edge is
     what makes a Doom sprite a Doom sprite and it is exactly wrong for
     this: smoke has no edge, and the alpha ramp is the whole effect. */
  {
    const W = 64, H = 64, N = 16;
    const n = fbm(W, H, 5, 3, 240);
    const fine = fbm(W, H, 11, 2, 341);
    for (let f = 0; f < N; f++) {
      const off = Math.round(f * H / N);
      const p = new Pix(W, H, 240 + f, false);
      for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
        const sy = (y + off) % H;
        const v = n[sy * W + x], q = fine[sy * W + x];
        /* a ball with the noise eaten into it, wider than it is tall
           because a plume spreads as it cools */
        const dx = (x - 31.5) / 31, dy = (y - 33) / 29;
        const d = Math.hypot(dx, dy * 0.94);
        const a = (1 - d) * 1.5 + (v - 0.5) * 1.15 - 0.20;
        if (a <= 0.02) continue;
        /* DARKEST IN THE MIDDLE, which is not a lighting model, it is
           how much smoke there is between you and whatever is behind it.
           The warm underside is not drawn: the one fire light in the
           game puts it there at run time, off the fire that is making
           the smoke — see worldShade in js/material.js. */
        const lum = 0.13 + q * 0.15 + Math.max(0, d - 0.28) * 0.26;
        p.ink(x, y, 'grey', lum, Math.round(Math.min(1, a * 1.7) * 200));
      }
      bank.addFrame('SMOK', LETTERS[f], new Array(8).fill(p), { scale: 2.4 });
    }
  }

  /* --- a trolley, abandoned mid-aisle --- */
  bank.addFrame('TRLY', 'A', radial(p => {
    for (let x = 4; x < 28; x += 3) p.vline(x, 8, 26, 'grey', 0.44);
    for (let y = 10; y < 26; y += 4) p.hline(4, 27, y, 'grey', 0.40);
    p.hline(3, 28, 8, 'grey', 0.62);
    p.hline(4, 27, 27, 'grey', 0.22);
    p.vline(3, 8, 27, 'grey', 0.5); p.vline(28, 8, 27, 'grey', 0.5);
    for (const wx of [6, 25]) { p.disc(wx, 36, 2.2, 'grey', 0.12); p.vline(wx, 27, 34, 'grey', 0.34); }
    p.hline(6, 25, 4, 'red', 0.5);                    // the handle
  }, 32, 40, 601), { scale: 1.1 });

  /* --- the yellow bollards outside the doors --- */
  bank.addFrame('BOLL', 'A', radial(p => {
    for (let y = 6; y < 40; y++)
      for (let x = 12; x < 21; x++) {
        const band = (y > 14 && y < 20) || (y > 28 && y < 34);
        p.ink(x, y, band ? 'grey' : 'yellow', band ? 0.12 : (0.62 - (x - 12) * 0.03));
      }
    p.disc(16, 6, 4.4, 'yellow', 0.74);
    for (let x = 10; x < 23; x++) p.ink(x, 40, 'grey', 0.06);
  }, 32, 42, 602));

  /* --- THERE WAS A STREET LAMP HERE: a post with an acorn globe on it,
     drawn twelve by sixty-four and stood at twice the size, fullbright.
     It is gone, and what replaced it is not in this bank at all: the
     lamp is a PHOTOGRAPH, and it is not a sprite. A sprite turns to
     face you, and a lamp post with a bracket arm that turns to face
     you is a lamp post whose arm swings round to point at you wherever
     you stand. So the photograph goes in through the texture bank as
     two tiles (T.LAMPHEAD and T.LAMPPOST in js/textures.js, baked by
     tools/bake-art.mjs) and js/mapgeo.js stands them up in the plane
     across the street. --- */

  /* --- THE HEADSTONES, EIGHT OF THEM, and they are photographs.

     They were two drawings — a round-topped slab and a cross, both
     granite, both with the panel where the name was. What a drawing
     cannot do is weathering: lichen in the lettering, a base sunk
     crooked into the turf, a face worn until the carving is a shadow.
     So they come in as real stones, cut out of their chroma key by
     tools/bake-art.mjs and decoded here, and the town deals them round
     its two burying grounds.

     THE LETTERING TOOK CARE OF ITSELF. Every one was photographed with
     a word cut into it, and at twenty-eight texels across a five-letter
     word is four texels tall and comes out as the horizontal smudge
     that weathered lettering actually is. No name on anything, ever,
     which is the rule the shopfronts keep and this keeps by
     arithmetic. --- */
  const STONES = ['stone_round', 'stone_worn', 'stone_plain', 'stone_tapered',
                  'stone_rough', 'stone_obelisk', 'stone_cross', 'stone_crossback'];
  STONES.forEach((n, i) => bank.addFrame(`GRV${i}`, 'A', new Array(8).fill(cutoutPix(n))));

  /* --- the reason the store is going to burn --- */
  bank.addFrame('GCAN', 'A', radial(p => {
    for (let y = 14; y < 36; y++) for (let x = 8; x < 25; x++)
      p.ink(x, y, 'red', 0.30 + (x < 14 ? 0.12 : 0) - (y > 30 ? 0.08 : 0));
    p.hline(8, 24, 14, 'red', 0.56);
    p.vline(8, 14, 35, 'red', 0.48);
    p.vline(24, 14, 35, 'red', 0.16);
    for (let x = 11; x < 22; x++) p.ink(x, 11, 'grey', 0.34);      // the handle
    p.vline(11, 11, 14, 'grey', 0.34); p.vline(21, 11, 14, 'grey', 0.34);
    for (let y = 8; y < 14; y++) for (let x = 24; x < 28; x++) p.ink(x, y, 'grey', 0.26);  // the spout
    drawTextCentred(p, 'FUEL', 16, 22, 'bone', 0.9);
    for (let x = 6; x < 27; x++) p.ink(x, 36, 'grey', 0.06);
  }, 32, 38, 603));

  /* --- a stack of cases, which is a fire waiting to be told about it --- */
  bank.addFrame('CRAT', 'A', radial(p => {
    const rng = makeRng(604);
    for (let row = 0; row < 3; row++) {
      const y0 = 40 - (row + 1) * 13;
      const w = 26 - row * 3, x0 = 16 - (w >> 1) + Math.round((rng() - 0.5) * 3);
      for (let y = y0; y < y0 + 13; y++) for (let x = x0; x < x0 + w; x++)
        p.ink(x, y, 'brown', 0.36 + rng() * 0.05);
      p.hline(x0, x0 + w - 1, y0, 'brown', 0.58);
      p.vline(x0, y0, y0 + 12, 'brown', 0.48);
      p.vline(x0 + w - 1, y0, y0 + 12, 'brown', 0.20);
      p.hline(x0, x0 + w - 1, y0 + 12, 'brown', 0.16);
      p.vline(x0 + (w >> 1), y0, y0 + 12, 'bone', 0.66);
    }
  }, 32, 42, 604), { scale: 1.4 });

  /* --- what is left where somebody was ---
     Squashed four to one, because it is lying on the floor and this is
     a billboard standing up on it: a circle drawn on a standing quad
     reads as a ball, and an ellipse a quarter as tall reads as a stain
     seen from eye level. Three of them, picked per actor. */
  for (let v = 0; v < SPLATS; v++) {
    const rng = makeRng(605 + v);
    bank.addFrame(SPLAT_SPRITE + v, 'A', radial(p => {
      const cx = CELLS.splat.w / 2, cy = CELLS.splat.h - 4;
      for (let i = 0; i < 60; i++) {
        const a = rng() * Math.PI * 2, d = rng() * (12 + v * 5);
        p.disc(cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.28,
               1 + rng() * 2.6, 'red', 0.10 + rng() * 0.12);
      }
    }, CELLS.splat.w, CELLS.splat.h, 605 + v));
  }

  /* --- AND WHAT IS LEFT WHEN THE FIRE FINISHES ONE ---

     The other thing a person can turn into, and it is deliberately NOT
     the splat with the red taken out. A splat is a stain: flat, thin,
     spread wide by something arriving fast. Somebody who burned away
     where they stood leaves a HEAP — narrower than the splat is wide,
     banked up in the middle, with the shape of a person's footprint
     still in it if you are generous.

     THREE LAYERS AND THE ORDER MATTERS. A wide scatter of pale grey
     first, which is the ash that went sideways and settled; then the
     heap itself in the dark end of the grey ramp, because ash in a pile
     is nearly black and only reads as ash by the dust around it; and
     then a handful of coals — rust and yellow, four or five of them, no
     more — sitting in the top of it. The coals are what stop it reading
     as a puddle of dirty water. There is no ember shader on a sprite
     (that is a SURFACE thing, see js/material.js), so the last warmth
     of a person has to be painted in.

     Squashed like the splat is, and for the same reason: it is lying on
     the floor and this is a billboard standing up on it, so the height
     is a quarter of the width or it reads as a ball. Three of them,
     picked per actor off `variants`. --- */
  for (let v = 0; v < ASHES; v++) {
    const rng = makeRng(631 + v);
    bank.addFrame(ASH_SPRITE + v, 'A', radial(p => {
      const cx = CELLS.ash.w / 2, cy = CELLS.ash.h - 4;
      const wide = 10 + v * 2;
      /* the dust that went sideways, and it is the PALEST part: ash on
         lino is light, and it is what says "ash" rather than "hole" */
      for (let i = 0; i < 60; i++) {
        const a = rng() * Math.PI * 2, d = Math.sqrt(rng()) * (wide + 6);
        p.disc(cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.26,
               0.8 + rng() * 1.4, 'grey', 0.30 + rng() * 0.16);
      }
      /* and the heap, banked toward the middle and darker in it —
         mid-grey and not the bottom of the ramp, which came out as a
         black puddle on the floor and read as a hole in the lino */
      for (let i = 0; i < 80; i++) {
        const a = rng() * Math.PI * 2, d = Math.pow(rng(), 1.8) * wide;
        p.disc(cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.30 - rng() * 2.0,
               1 + rng() * 2.0, 'grey', 0.10 + rng() * 0.16);
      }
      /* and half a dozen coals still in it */
      for (let i = 0; i < 7; i++) {
        const a = rng() * Math.PI * 2, d = Math.pow(rng(), 1.5) * wide * 0.7;
        p.disc(cx + Math.cos(a) * d, cy + Math.sin(a) * d * 0.30 - 1,
               0.8 + rng() * 0.8, rng() < 0.35 ? 'yellow' : 'rust', 0.36 + rng() * 0.3);
      }
    }, CELLS.ash.w, CELLS.ash.h, 631 + v));
  }

  /* --- and the fireball, drawn by the fire routine so that the
         stand-in for an explosion is at least made of fire.

         Shorter than the picture it stands in for: everything this file
         DRAWS is 64 pixels or under, which is the rule the whole look
         rests on, and the painted fireball that lands on top of it is 96
         because it came from outside and outside art arrives as it is.
         A placeholder two thirds the height is a placeholder. --- */
  {
    const frames = fireFrames(CELLS.blast.w, 64, BLASTS, 77, { taper: 0.5 });
    frames.forEach((p, i) =>
      bank.addFrame(BLAST_SPRITE, LETTERS[i], new Array(8).fill(p), { fullbright: true }));
  }

  /* --- the lights are paint now ------------------------------------
     There was a LAMP sprite here: a suspended four-tube troffer drawn
     four ways — lit, one tube gone, barely striking, shot out — and it
     is gone, along with the flicker ring that ran between the last two.

     A FITTING IS PAINTED INTO THE CEILING AND NOTHING HANGS UNDER IT.
     T.CEILFIT in js/textures.js draws it, one per 256-unit tile, and it
     is now drawn ALIGHT rather than as switched-off hardware, because it
     is the only picture of a light in the shop.

     The light itself is still an object — see ACTORS.LAMP in
     js/states.js — because relight() has to know where the sources are
     and the fire has to be able to take them out. It just has no sprite
     and no state, which makes it the second thing in the game with
     neither, after a parked vehicle. What a light going out looks like
     is the sector it lit going dark, plus the sparks below. */

  /* what comes out of one when it goes */
  ['A', 'B', 'C'].forEach((L, i) => {
    bank.addFrame('SPRK', L, radial(p => {
      const rng = makeRng(640 + i);
      const heat = [0.98, 0.74, 0.44][i];
      for (let k = 0; k < 4 - i; k++) {
        const x = 6 + Math.floor(rng() * 4), y = 6 + Math.floor(rng() * 4);
        p.ink(x, y, 'fire', heat);
        if (i === 0) { p.ink(x + 1, y, 'fire', heat - 0.2); p.ink(x, y + 1, 'fire', heat - 0.3); }
      }
    }, 16, 16, 640 + i), { fullbright: true });
  });

  /* --- the one thing you throw --- */
  /* --- THE CEREBRAL BORE'S PARTS --------------------------------
     Three things the weapon in js/bore.js draws in the world, none of
     them bigger than a coin: the DOT the laser sight puts on whatever
     it is pointing at, the RETICLE it puts on a head it has locked, and
     the BORE itself — a stubby drill, three frames of it turning, that
     flies out of the launcher and sits in somebody's skull for two
     seconds. All three are red, because Turok's were, and fullbright,
     because a sight you cannot see in a dark aisle is not a sight. */
  bank.addFrame('LASR', 'A', radial(p => {
    p.disc(2.5, 2.5, 2.2, 'red', 0.92);
    p.ink(2, 2, 'red', 0.99);
  }, 5, 5, 71), { fullbright: true });
  bank.addFrame('LOCK', 'A', radial(p => {
    const c = 8.5;
    for (let a = 0; a < 64; a++) {
      const x = Math.round(c + Math.cos(a / 64 * Math.PI * 2) * 6.5), y = Math.round(c + Math.sin(a / 64 * Math.PI * 2) * 6.5);
      p.ink(x, y, 'red', 0.90);
    }
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]])
      for (let k = 4; k <= 8; k++) p.ink(Math.round(c + dx * k), Math.round(c + dy * k), 'red', 0.97);
    p.ink(8, 8, 'red', 0.99);
  }, 17, 17, 72), { fullbright: true });
  for (let f = 0; f < 3; f++) {
    bank.addFrame('BORE', 'ABC'[f], radial(p => {
      /* a cone, tip to the right, with a dark band spiralling round it
         — the band moves a third of a turn a frame, which is the whole
         of the spin */
      for (let x = 1; x < 13; x++) {
        const r = 1.2 + (12 - x) * 0.42;
        for (let y = -Math.ceil(r); y <= Math.ceil(r); y++) {
          if (Math.abs(y) > r) continue;
          const band = ((x * 0.9 + (y + r) * 0.6 + f * 2.1) % 3.0) < 1.1;
          p.ink(x, 7 + y, band ? 'red' : 'grey', band ? 0.62 : 0.42 - Math.abs(y) / (r * 3.5));
        }
      }
      p.disc(2, 7, 2.4, 'grey', 0.26);              // the housing at the back
    }, 14, 14, 73 + f), { fullbright: true });
  }

  /* --- THE QUAD LAUNCHER'S PARTS ---------------------------------
     Two things js/missiles.js draws in the world. The LOCK is a square
     bracket, four corners and nothing between them, so it can never be
     mistaken for the bore's round red reticle — amber, because amber is
     what a seeker head's symbology is, and fullbright for the bore's
     reason. Frame B is the same bracket broken and dimmer, for a source
     the seeker is still dwelling on. The MISSILE is its motor and not
     its body: at the speed it goes and the size it is, what the eye has
     of a rocket in flight is the flare, so three frames of it flicker
     and the smoke behind it (Effects.puff) is the rest of the picture. */
  for (const [f, lit] of [['A', 0.93], ['B', 0.62]]) {
    bank.addFrame('TLCK', f, radial(p => {
      const lo = 1, hi = 17, arm = f === 'A' ? 5 : 3;
      for (let k = 0; k < arm; k++) {
        for (const [x, y, dx, dy] of [[lo, lo, 1, 1], [hi, lo, -1, 1], [lo, hi, 1, -1], [hi, hi, -1, -1]]) {
          p.ink(x + dx * k, y, 'yellow', lit);
          p.ink(x, y + dy * k, 'yellow', lit);
        }
      }
      if (f === 'A') p.disc(9, 9, 1.2, 'yellow', 0.97);
    }, 19, 19, 81 + (f === 'A' ? 0 : 1)), { fullbright: true });
  }
  ['A', 'B', 'C'].forEach((L, i) => {
    bank.addFrame('MISL', L, radial(p => {
      const r = [3.6, 4.2, 3.2][i];
      p.disc(6, 6, r, 'fire', 0.62);
      p.disc(6, 6, r * 0.62, 'fire', 0.86);
      p.disc(6, 6, r * 0.3, 'yellow', 0.99);
    }, 12, 12, 84 + i), { fullbright: true });
  });
  /* THE ROCKET ITSELF, at the user's request — "whatever rocket sprites
     you make need exhaust and smoke trails and an impact explosion" —
     and MISL above is now only the bloom behind it. Eight rotations,
     the way a Doom thing has them, because a rocket crossing the street
     and a rocket coming at you are different pictures: see rocketView,
     which draws each one off a little model rather than by hand, so the
     eight agree about where the fins are. Two frames, for the flame. */
  for (const [f, flame] of [['A', 13], ['B', 17]])
    bank.addFrame('ROKT', f, [0, 1, 2, 3, 4, 5, 6, 7].map(r => rocketView(r, flame, 90 + r)), { fullbright: true });
  /* AND WHAT IT DOES WHEN IT ARRIVES: eight frames of a fireball, from
     a white-hot core with a shock ring round it to a torn ball of smoke
     with the last of the fire in the middle — see blastFrame */
  'ABCDEFGH'.split('').forEach((L, k) => bank.addFrame('MEXP', L, new Array(8).fill(blastFrame(k)), { fullbright: true }));

  bank.addFrame('MOLO', 'A', radial(p => {
    for (let y = 12; y < 26; y++) for (let x = 11; x < 19; x++)
      p.ink(x, y, 'green', 0.26 + (x < 15 ? 0.12 : -0.04));
    for (let y = 7; y < 12; y++) p.hline(13, 16, y, 'green', 0.32);
    p.disc(14, 5, 2.6, 'fire', 0.60);
    p.disc(14, 3, 1.8, 'fire', 0.88);
    p.disc(14, 1, 1.1, 'fire', 0.97);
  }, 30, 30, 607), { fullbright: true, lift: 24 });

  /* --- the blood that is still in the air --- */
  ['A', 'B', 'C'].forEach((L, i) => {
    bank.addFrame('PUFF', L, radial(p => {
      const rng = makeRng(700 + i);
      const spread = 3 + i * 4;
      for (let k = 0; k < 12 - i * 2; k++) {
        const a = rng() * Math.PI * 2, d = rng() * spread;
        p.disc(12 + Math.cos(a) * d, 12 + Math.sin(a) * d, 1.4 - i * 0.3, 'red', 0.34 - i * 0.08);
      }
    }, 24, 24, 700 + i), { lift: -12 });
    /* MINUS twelve: the quad's foot is its origin and this is a
       twenty-four-pixel picture of a puff, so lifting it by half its
       own height down puts the puff's CENTRE on the point it was
       spawned at — the hole the round just made, or the body it went
       into. It was +24 before, which stood the whole picture a full
       height and a half above the hit: a bullet hole with its puff
       floating over it, which the user saw. */
  });

  const ms = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0;
  console.log(`baked ${bank.frames.size} sprite frames in ${ms.toFixed(0)}ms`);
  return bank;
}

/* =====================================================================
   The things in your hands
   =====================================================================

   Doom drew the weapon as a sprite pinned to the bottom of the 320x200
   frame, bobbing with the walk, and that is exactly what these are.
   Sixty-four pixels each, blown up on screen, so they are as chunky as
   the walls — a crisp weapon over a chunky world is the fastest way to
   break the whole illusion.

   Three of them, and between them they are the game's argument:

     BOXCUTTER  free, silent, and it does not start fires. What you use
                when the fuel has gone.
     FLAMER     the main verb. Sets light to the aisle, the stock and
                whatever is walking down it.
     MOLOTOV    fire you can throw. The answer to a fire that will not
                cross a walkway.
   ===================================================================== */

/* --------------------------------------------------------------------
   The one drawing in this game that a person made

   Run-length pairs of palette indices out of js/art-data.js, which
   tools/bake-art.mjs writes from art/flamer.png. Nine lines of decoder,
   no image loading, no async, nothing fetched — it is source code by the
   time it gets here.
   ------------------------------------------------------------------ */
const ART_B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const ART_B64R = (() => { const r = new Int16Array(128).fill(-1);
  for (let i = 0; i < 64; i++) r[ART_B64.charCodeAt(i)] = i; return r; })();

/**
 * Any tile tools/bake-art.mjs wrote, into a Pix of its own size:
 * unbase64, walk the run-length pairs, and skip the index that means
 * nothing. Transparent everywhere it is not drawn, which is what makes
 * a headstone a cut-out rather than a square of granite.
 *
 * ONE DECODER FOR ALL OF THEM. It was the weapon's, at a hard 64x64,
 * and the headstones needed twenty-eight by forty. The sizes travel
 * with the tiles now; nothing else changed.
 */
export function decodeArtTile(tile, w, h) {
  const bytes = [];
  let acc = 0, bits = 0;
  for (let i = 0; i < tile.length; i++) {
    const v = ART_B64R[tile.charCodeAt(i)];
    if (v < 0) continue;
    acc = (acc << 6) | v; bits += 6;
    if (bits >= 8) { bits -= 8; bytes.push((acc >> bits) & 255); }
  }
  const p = new Pix(w, h, 1, false);
  p.clear();
  let at = 0;
  const N = w * h;
  for (let i = 0; i + 1 < bytes.length && at < N; i += 2)
    for (let n = bytes[i + 1]; n > 0 && at < N; n--, at++) {
      if (bytes[i] === CLEAR_INDEX) continue;
      const c = PALETTE[bytes[i]];
      p.set(at % w, (at / w) | 0, c[0], c[1], c[2], 255);
    }
  return p;
}

/** One of the cut-outs by name — see CUTOUTS in js/art-data.js. */
export function cutoutPix(name) {
  const c = CUTOUTS[name];
  if (!c) throw new Error(`no cut-out called ${name}`);
  return decodeArtTile(c.tile, c.w, c.h);
}

function decodeWeapon() { return decodeArtTile(WEAPON_TILE, 64, 64); }

function weaponPix(w, h, draw, seed) {
  const p = new Pix(w, h, seed, false);   // drawn off the edge on purpose
  draw(p, makeRng(seed));
  p.snap(0.3);
  return p;
}

/* A tapered bar between two points, lit from the top left like
   everything else. The weapons are all built out of these. */
function bar(p, x0, y0, x1, y1, r0, r1, key, t) {
  const dx = x1 - x0, dy = y1 - y0;
  const len = Math.max(1, Math.hypot(dx, dy));
  const nx = -dy / len, ny = dx / len;
  for (let s = 0; s <= len * 2; s++) {
    const f = s / (len * 2);
    const cx = x0 + dx * f, cy = y0 + dy * f, r = r0 + (r1 - r0) * f;
    for (let o = -Math.ceil(r); o <= Math.ceil(r); o++) {
      const d = Math.abs(o) / Math.max(0.6, r);
      if (d > 1) continue;
      /* the lit side is whichever one faces up and left */
      const lit = -(o / Math.max(0.6, r)) * (nx - ny) * 0.5 - d * 0.16;
      p.ink(Math.round(cx + nx * o), Math.round(cy + ny * o), key, Math.max(0.03, Math.min(0.97, t + lit * 0.42)));
    }
  }
}

function fist(p, cx, cy, r, key, t) {
  for (let y = -r; y <= r; y++)
    for (let x = -r * 1.15; x <= r * 1.15; x++) {
      const d = Math.hypot(x / 1.15, y);
      if (d > r) continue;
      p.ink(Math.round(cx + x), Math.round(cy + y), key, t + (-x - y) / (r * 5) - d / (r * 8));
    }
  /* knuckles */
  for (let k = -1; k <= 2; k++) p.ink(Math.round(cx + k * 2), Math.round(cy - r * 0.55), key, t - 0.10);
}

export function bakeWeapons() {
  const W = new Map();
  const add = (name, pix, opts = {}) => W.set(name, { pix, ...opts });

  /* THE BOXCUTTER IS GONE — deleted, not switched off, at the user's
     request. It was three frames of a forearm and a blade built out of
     `bar` and `fist`, and the two helpers stay because the molotov's
     hand is made of them too. */

  /* ---- the flamer -------------------------------------------------
     This one is a PHOTOGRAPH, cut out of a chroma key, derezzed to 64
     pixels and snapped to the game's own 256 colours by
     tools/bake-art.mjs. Everything else in the game is drawn by code and
     this is not, because there is no set of primitives that gets you to
     a piece of kit somebody actually built.

     It arrives laid along the bottom of the frame with the top third
     empty, and that empty third is the whole point: the muzzle flame is
     drawn over it, in code, per frame — one still weapon and a separate
     flash, which is how Doom's weapons worked and why they only ever
     needed one drawing of the gun.

     RECOIL IS A NUDGE, not a redraw. Two pixels down and one right on
     the hot frame; at this resolution that is the entire language
     available for "it just went off", and it is enough. */
  const gunArt = decodeWeapon();
  const MUZZLE = [5, 31];            // where the bore is, in the derezzed art

  const flamer = (fireFrame) => weaponPix(64, 64, (p, rng) => {
    const kick = fireFrame === 1 ? 2 : fireFrame === 2 ? 1 : 0;
    p.blit(gunArt, Math.round(kick * 0.5), kick);

    const ox = MUZZLE[0] + kick * 0.5, oy = MUZZLE[1] + kick;
    if (fireFrame === 0) {
      /* the pilot light, which is the only reason the thing is dangerous
         when you are not pulling the trigger */
      p.disc(ox, oy - 2, 1.4, 'fire', 0.62);
      p.disc(ox, oy - 4, 0.9, 'fire', 0.88);
      return;
    }
    /* The stream. Thrown up and to the left along a widening cone,
       hottest at the muzzle and cooling as it goes, with the far end
       breaking into separate blobs the way a real one does. */
    const n = fireFrame;
    const count = 170 + n * 100;
    for (let i = 0; i < count; i++) {
      const t = Math.pow(rng(), 0.65);                 // bunched near the muzzle
      const reach = (20 + n * 10) * t;
      const spread = t * (5 + n * 4);
      const dirx = -0.62, diry = -0.78;
      const px = ox + dirx * reach + (rng() - 0.5) * spread * 2;
      const py = oy + diry * reach + (rng() - 0.5) * spread * 1.4;
      if (px < -3 || py < -3) continue;
      const heat = Math.max(0.10, 1.0 - t * (0.5 + rng() * 0.55));
      p.disc(Math.round(px), Math.round(py), 0.7 + (1 - t) * 2.6, 'fire', heat);
    }
  }, 810 + fireFrame * 13);
  /* `content` is how much of the 64 is gun rather than reserved sky for
     the flame. The HUD sizes a weapon by that rather than by the canvas,
     so leaving room for a muzzle flash does not shrink the gun. */
  const gunOpts = { content: 64 - WEAPON_TOP };
  add('FLMGA', flamer(0), gunOpts);
  add('FLMGB', flamer(1), { ...gunOpts, fullbright: true });
  add('FLMGC', flamer(2), { ...gunOpts, fullbright: true });

  /* ---- the molotov ------------------------------------------------ */
  const molly = (stage) => weaponPix(64, 64, (p) => {
    if (stage === 2) {
      /* thrown: an empty hand still following through */
      bar(p, 60, 66, 40, 44, 5.6, 4.0, 'flesh', 0.40);
      fist(p, 39, 42, 4.6, 'flesh', 0.44);
      return;
    }
    const lift = stage === 1 ? -13 : 0;
    const bx = 40, by = 40 + lift;
    /* forearm and hand first, so the bottle sits IN it */
    bar(p, 60, 66, bx + 5, by + 20, 5.6, 4.2, 'flesh', 0.40);
    /* the bottle */
    for (let y = by; y < by + 19; y++)
      for (let x = bx - 6; x < bx + 6; x++) {
        const edge = (x === bx - 6 || x === bx + 5) ? -0.10 : 0;
        p.ink(x, y, 'green', 0.24 + (x < bx - 1 ? 0.11 : -0.03) + edge);
      }
    p.hline(bx - 6, bx + 5, by, 'green', 0.44);
    bar(p, bx, by, bx, by - 8, 2.6, 2.0, 'green', 0.28);        // the neck
    /* the fuel in it, and the line it stops at */
    for (let y = by + 6; y < by + 18; y++) p.hline(bx - 5, bx + 4, y, 'olive', 0.28 + (y - by) * 0.006);
    p.hline(bx - 5, bx + 4, by + 6, 'olive', 0.46);
    /* the hand, over the bottle */
    fist(p, bx + 1, by + 15, 5.0, 'flesh', 0.45);
    /* the rag and what is happening to it */
    bar(p, bx, by - 8, bx - 1, by - 14, 2.2, 1.6, 'bone', 0.66);
    p.disc(bx - 1, by - 17, 2.6, 'fire', 0.58);
    p.disc(bx - 1, by - 19, 1.8, 'fire', 0.84);
    p.disc(bx - 1, by - 21, 1.1, 'fire', 0.96);
  }, 820 + stage * 5);
  add('MOLGA', molly(0));
  add('MOLGB', molly(1));
  add('MOLGC', molly(2));

  for (const [, e] of W) { e.texture = null; e.w = e.pix.w; e.h = e.pix.h; e.content = e.content || e.h; }
  return W;
}

export function weaponTexture(entry) {
  if (entry.texture) return entry.texture;
  const t = new THREE.CanvasTexture(entry.pix.toCanvas());
  t.magFilter = THREE.NearestFilter;
  t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.needsUpdate = true;
  entry.texture = t;
  return t;
}
