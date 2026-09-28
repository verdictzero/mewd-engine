/* =====================================================================
   MEWD — every surface in the store, at 64 pixels
   =====================================================================

   Sixty-four pixels is not a limitation here, it is the brief. At one
   texel to one world unit a 64-pixel texture is a 64-unit wall, the
   player is 32 across and can see about eight texels of detail on a wall
   he is standing next to, and every decision about what to draw is
   really a decision about what to LEAVE OUT.

   What survives that cut, in every texture below:

     one big shape      the thing you read from across the store — the
                        shelf bands, the door panel, the corrugations
     one edge           a highlight on the top-left of it, shadow on the
                        bottom-right, always that way round
     dirt at the bottom  because that is where dirt is

   Anything finer than that is gone by the second repeat. A 64-pixel
   texture with six levels of detail in it reads, from two metres, as
   grey.

   THE STORE IS THE PALETTE'S ARGUMENT. Everything out front is bone,
   grey and that corporate red. Everything behind the swing doors is
   rust, brown and bare concrete — no branding, no paint, no pretence.
   The moment the player crosses from one to the other should be legible
   without a single sign, and it is done entirely by which ramps the
   textures on either side were allowed to draw from.
   ===================================================================== */

import * as THREE from 'three';
import { Pix, fbm, valueNoise, speckle, drawText, drawTextCentred, textWidth } from './pixel.js';
import { makeRng } from './util.js';
import { LOGO_TILES, CUTOUTS as ART_CUTOUTS, LAMP as ART_LAMP } from './art-data.js';
import { cutoutPix } from './sprites.js';
import { PALETTE } from './palette.js';

export class TextureBank {
  constructor() { this.map = new Map(); this.missing = new Set(); }

  add(name, pix, opts = {}) {
    /* REPAINTED, NOT REPLACED. A name already in the bank keeps its
       three.js texture and is given new pixels, because every material
       in the scene is holding that object and a new one would leave all
       of them pointing at the old picture. It is what lets the art
       palette be a setting — see setArtPalette in js/palette.js and
       applyTone in js/main.js — and it costs the ordinary path one map
       lookup that always misses. */
    const had = this.map.get(name);
    if (had) {
      had.pix = pix;
      had.texture.image = pix.toCanvas();
      had.texture.needsUpdate = true;
      had.w = opts.w ?? pix.w; had.h = opts.h ?? pix.h; had.masked = !!opts.masked;
      return had;
    }
    const tex = new THREE.CanvasTexture(pix.toCanvas());
    tex.magFilter = THREE.NearestFilter;
    /* Chunky mipmaps: nearest WITHIN a level and nearest BETWEEN levels,
       so a floor seen edge-on stops boiling without ever going soft. A
       linear filter anywhere in that chain and the whole thing starts
       looking like a remaster. */
    tex.minFilter = THREE.NearestMipmapNearestFilter;
    tex.generateMipmaps = true;
    /* SMOOTH, FOR THE ONE KIND OF PICTURE THAT WANTS IT. Everything in
       this game is point sampled and that is the whole look — see the
       note above. The grid's floor is not a picture of a surface, it is
       a RULED LINE, and a ruled line drawn at four texels to the unit
       and then point sampled across ten thousand units of field is a
       stack of aliasing. So a texture may ask for the other filter, and
       exactly two do. Anisotropy is clamped to the hardware's own limit
       on upload, so asking for sixteen is asking for what there is. */
    if (opts.smooth) {
      tex.magFilter = THREE.LinearFilter;
      tex.minFilter = THREE.LinearMipmapLinearFilter;
      tex.anisotropy = 16;
    }
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.needsUpdate = true;
    this.map.set(name, {
      name, texture: tex, pix,
      w: opts.w ?? pix.w,        // world units the texture spans
      h: opts.h ?? pix.h,
      masked: !!opts.masked,
    });
    return this.map.get(name);
  }

  get(name) {
    const e = this.map.get(name);
    if (e) return e;
    /* A missing texture should be loud, not invisible — a wall you can
       see through is a bug you will chase for an hour, and a magenta
       wall is a bug you fix in ten seconds. */
    /* (quiet on a host with no screen, which never loads the pack and
       never draws a wall — see tools/headless.mjs) */
    if (!this.missing.has(name)) { this.missing.add(name); if (!this.quiet) console.warn('missing texture:', name); }
    return this.map.get('MISSING');
  }
}

/* ====================================================================
   Shared moves

   The three or four things that go into nearly every texture, written
   once. Consistency in a generated set does not come from discipline, it
   comes from there being only one function that draws grime.
   ==================================================================== */

/** Aggregate: crushed stone of two or three grades sitting in a binder.
 *  Asphalt, concrete and terrazzo are all this with different numbers. */
function aggregate(p, seed, opts) {
  const { baseKey, baseLo, baseHi, grades } = opts;
  const n = fbm(p.w, p.h, 8, 3, seed);
  for (let y = 0; y < p.h; y++)
    for (let x = 0; x < p.w; x++)
      p.ink(x, y, baseKey, baseLo + n[y * p.w + x] * (baseHi - baseLo));

  for (const g of grades) {
    speckle(p.w, p.h, g.count, seed + g.count, (x, y, a, b) => {
      const r = g.min + a * (g.max - g.min);
      const t = g.lo + b * (g.hi - g.lo);
      if (r <= 0.75) { p.ink(x, y, g.key, t); return; }
      /* Stones bigger than a texel get a lit top-left and a shadowed
         bottom-right, because that is where the light is. */
      p.disc(x, y, r, g.key, t);
      p.ink(x - 1, y - 1, g.key, Math.min(1, t + 0.22));
      p.ink(x + 1, y + 1, g.key, Math.max(0, t - 0.25));
    });
  }
}

/** A crack that wanders. Wraps, because a crack that stops at the edge of
 *  the texture becomes a dotted line eight repeats later. */
function crack(p, x, y, len, key, t, seed, wander = 0.9) {
  const rng = makeRng(seed);
  let a = rng() * Math.PI * 2;
  for (let i = 0; i < len; i++) {
    p.ink(x, y, key, t);
    /* A branch now and then — real cracks fork, straight ones read as
       drawn-on scratches. */
    if (rng() < 0.05 && len > 12) crack(p, x, y, (len - i) >> 1, key, t, seed + i * 31, wander);
    a += (rng() - 0.5) * wander;
    x = Math.round(x + Math.cos(a));
    y = Math.round(y + Math.sin(a));
  }
}

/** Something wet ran down this wall and dried. */
function streaks(p, count, seed, key, t, strength = 0.4) {
  const rng = makeRng(seed);
  for (let i = 0; i < count; i++) {
    const x = Math.floor(rng() * p.w);
    const top = Math.floor(rng() * p.h * 0.5);
    const len = Math.floor(p.h * (0.3 + rng() * 0.7));
    const wide = rng() < 0.3 ? 2 : 1;
    for (let d = 0; d < len; d++) {
      const y = top + d;
      const fade = (1 - d / len) * strength * (0.5 + rng() * 0.5);
      for (let k = 0; k < wide; k++) p.wash(x + k, y, key, t, fade);
    }
  }
}

/* Diagonal hazard striping, tiling at 45 degrees. Wraps only when the
   stripe pitch divides the width, which for 64 and a pitch of 8 it does. */
function hazardStripes(p, pitch, keyA, tA, keyB, tB) {
  for (let y = 0; y < p.h; y++)
    for (let x = 0; x < p.w; x++) {
      const band = Math.floor(((x + y) % (pitch * 2)) / pitch);
      p.ink(x, y, band ? keyA : keyB, band ? tA : tB);
    }
}

/* ====================================================================
   The textures
   ==================================================================== */

const T = {};

/* ---------- outside: the car park ---------- */

T.ASPHALT = () => {
  const p = new Pix(64, 64, 11);
  /* Lighter than real tarmac, and deliberately. This was drawn at
     0.10-0.20 when the only asphalt in the game was a courtyard you
     stood in the middle of; across a car park the size of the one here
     it came out as a hole in the world with bay lines floating in it.
     A lit car park is a PALE surface at night — that is what the
     floodlights are for — and the darkest thing in the picture should be
     the store you are about to walk into. */
  aggregate(p, 11, {
    baseKey: 'grey', baseLo: 0.50, baseHi: 0.60,
    grades: [
      { count: 260, min: 0.4, max: 1.4, key: 'grey',  lo: 0.55, hi: 0.72 },
      { count: 90,  min: 0.6, max: 1.8, key: 'grey',  lo: 0.62, hi: 0.80 },
      { count: 40,  min: 0.4, max: 1.2, key: 'brown', lo: 0.46, hi: 0.62 },
    ],
  });
  crack(p, 12, 4, 70, 'grey', 0.30, 5);
  crack(p, 48, 40, 46, 'grey', 0.32, 9);
  /* Bitumen bleed — the shiny black patches where the binder came up */
  const n = valueNoise(64, 64, 4, 17);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    if (n[y * 64 + x] > 0.72) p.wash(x, y, 'grey', 0.38, 0.5);
  return p.snap(0.6);
};

T.PARKLINE = () => {
  /* A whole flat of bay line, painted on thin sectors so the map decides
     where the bays go rather than the texture grid deciding for it.

     Paint does not wear off in continents, it wears off in GRAIN — the
     high spots of the asphalt polish through first and the line goes
     speckly long before it goes patchy. So the wear here is fine noise
     over a solid coat, with only a couple of genuinely bald patches, and
     a faint drag along the direction the tyres cross it. */
  const p = new Pix(64, 64, 12);
  const grain = fbm(64, 64, 32, 2, 31);     // per-texel, not per-region
  const patch = fbm(64, 64, 4, 2, 34);      // the few places it has gone

  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const g = grain[y * 64 + x];
      /* Bald only where the coarse field is really low AND the grain
         agrees — one condition alone gives blobs, both together gives
         ragged holes with speckled edges. */
      const bald = patch[y * 64 + x] < 0.34 && g < 0.56;
      if (bald) {
        p.ink(x, y, 'grey', 0.11 + g * 0.14);
      } else if (g < 0.40) {
        p.ink(x, y, 'bone', 0.40 + g * 0.5);     // polished through to the grit
      } else {
        p.ink(x, y, 'bone', 0.74 + g * 0.20);    // the paint itself
      }
    }
  }
  /* the asphalt showing through the pinholes */
  speckle(64, 64, 420, 35, (x, y, a2, b2) => {
    if (a2 > 0.42) p.wash(x, y, 'grey', 0.13, 0.30 + b2 * 0.45);
  });
  /* scuffing across the line, the way everyone drives over it */
  const rng = makeRng(36);
  for (let i = 0; i < 7; i++) {
    const y = Math.floor(rng() * 64);
    for (let x = 0; x < 64; x++) if (rng() < 0.55) p.wash(x, y, 'grey', 0.16, 0.35);
  }
  return p.snap(0.55);
};

T.KERB = () => {
  /* 64 wide, 16 tall — the lower texture on the kerb line. Precast units
     with a joint every 32, chipped where cars have kissed it. */
  const p = new Pix(64, 16, 13);
  aggregate(p, 13, { baseKey: 'bone', baseLo: 0.34, baseHi: 0.48,
    grades: [{ count: 90, min: 0.4, max: 1.1, key: 'bone', lo: 0.24, hi: 0.58 },
             { count: 30, min: 0.4, max: 0.9, key: 'grey', lo: 0.28, hi: 0.42 }] });
  for (const jx of [0, 32]) { p.vline(jx, 0, 15, 'bone', 0.16); p.vline(jx + 1, 0, 15, 'bone', 0.52); }
  p.hline(0, 63, 0, 'bone', 0.66);            // the lit top arris
  p.hline(0, 63, 15, 'grey', 0.10);
  const rng = makeRng(77);
  for (let i = 0; i < 5; i++) {               // chips
    const x = Math.floor(rng() * 64), w = 2 + Math.floor(rng() * 3);
    for (let k = 0; k < w; k++) { p.ink(x + k, 0, 'bone', 0.22); p.ink(x + k, 1, 'bone', 0.3); }
  }
  p.grime(0.5, 'grey', 0.08, 4);
  return p.snap(0.5);
};

/* ---------- the grid world ----------
   The floor and the wall of js/maps/grid.js: green lines on black, and
   nothing else in the world but a crowd.

   THESE TWO ARE THE ONLY PICTURES IN THE GAME DRAWN IN FULL COLOUR, and
   the only two drawn bigger than 64 pixels. Everything else here is a
   64-square painted out of a 256-colour box and point sampled, which is
   the whole look — see the note on TextureBank and the header of
   js/palette.js. A ruled line is the one thing that does not survive
   it: the grid is not a picture of a surface, it is geometry standing
   in for geometry, and at one repeat every 64 units over ten thousand
   units of field a line snapped to a palette and then point sampled is
   a stack of aliasing. So these are 256 square, they carry their own
   RGB, and they ask the bank for the smooth filter (`smooth` in SIZES).

   THE LINE IS A GLOW AND NOT A STRIPE. Four texels to the world unit,
   with the brightness falling off as a gaussian either side of the
   edge, which is what gives it a clean bright core and an edge the
   mipmaps can average without it vanishing — the failure the low-res
   version of this had, where the grid was there underfoot and gone at
   the far wall. */
const gridPix = (size, bg, line, half, lineW, halfW) => {
  const p = new Pix(size, size, 411);
  const mix = (a, b, t) => a + (b - a) * t;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      /* how far this texel is from the nearest cell edge, and from the
         half-cell line; the edge wraps, so x and size-x both count */
      const d = Math.min(Math.min(x, size - x), Math.min(y, size - y));
      const h = Math.min(Math.abs(x - size / 2), Math.abs(y - size / 2));
      const edge = Math.exp(-(d * d) / lineW);
      const mid = Math.exp(-(h * h) / halfW) * 0.45;
      let r = bg[0], g = bg[1], b = bg[2];
      r = mix(r, half[0], mid); g = mix(g, half[1], mid); b = mix(b, half[2], mid);
      r = mix(r, line[0], edge); g = mix(g, line[1], edge); b = mix(b, line[2], edge);
      p.set(x, y, Math.round(r), Math.round(g), Math.round(b), 255);
    }
  }
  return p;                            // NOT snapped: this one keeps its colours
};

/* the floor: a dark field with a bright green lattice on it */
T.GRID = () => gridPix(256, [6, 11, 8], [70, 255, 140], [22, 104, 54], 20, 9);
/* and the wall round it, the same lattice a shade cooler and dimmer, so
   the edge of the world reads as a boundary rather than as more floor
   standing on its end */
T.GRIDWALL = () => gridPix(256, [5, 9, 9], [44, 190, 130], [16, 74, 52], 16, 7);

/* AND THE BOXES' OWN SKIN, which nothing asks for today. The burning
   boxes are archived rather than deleted (js/boxes.js, and `boxes` in
   js/maps/grid.js, which is empty); this is the picture they were worn
   in, kept here so that putting them back is putting them back. A
   64-square out of the palette like everything else, because a box IS a
   picture of a surface. */
T.GRIDBOX = () => {
  const p = new Pix(64, 64, 412);
  p.fill('green', 0.16);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const n = ((x * 13 + y * 29) % 17) / 17;
    p.wash(x, y, 'green', 0.10 + n * 0.14, 0.5);
  }
  p.frame(0, 0, 64, 64, 'green', 0.72);
  p.frame(1, 1, 62, 62, 'green', 0.44);
  p.hline(0, 63, 32, 'green', 0.30);
  p.vline(32, 0, 63, 'green', 0.30);
  p.grime(0.18, 'green', 0.08, 9);
  return p.snap(0.35);
};

T.CONCRETE = () => {
  const p = new Pix(64, 64, 14);
  aggregate(p, 14, { baseKey: 'bone', baseLo: 0.30, baseHi: 0.44,
    grades: [{ count: 200, min: 0.4, max: 1.0, key: 'bone', lo: 0.22, hi: 0.52 },
             { count: 60,  min: 0.4, max: 1.2, key: 'grey', lo: 0.26, hi: 0.40 }] });
  /* Broom finish — the drag marks a float leaves, all one way */
  for (let y = 0; y < 64; y++) {
    const n = valueNoise(64, 1, 16, 200 + y);
    for (let x = 0; x < 64; x++) if (n[x] > 0.6) p.wash(x, y, 'bone', 0.24, 0.3);
  }
  for (const jy of [0, 32]) p.hline(0, 63, jy, 'bone', 0.15);   // control joints
  for (const jx of [0]) p.vline(jx, 0, 63, 'bone', 0.15);
  crack(p, 20, 34, 30, 'bone', 0.12, 21);
  p.grime(0.3, 'grey', 0.1, 6);
  return p.snap(0.5);
};

/* ---------- outside: the building ---------- */

T.STORWALL = () => {
  /* Insulated render panels with a control joint every 32. The whole
     front of every big box in the world. */
  const p = new Pix(64, 64, 21);
  const n = fbm(64, 64, 16, 3, 21);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.50 + n[y * 64 + x] * 0.14);
  const height = new Float32Array(64 * 64).fill(0.5);
  for (const jy of [0, 32]) for (let x = 0; x < 64; x++) {
    height[jy * 64 + x] = 0.1;
    height[((jy + 1) % 64) * 64 + x] = 0.35;
  }
  for (const jx of [0]) for (let y = 0; y < 64; y++) {
    height[y * 64 + jx] = 0.1;
    height[y * 64 + ((jx + 1) % 64)] = 0.35;
  }
  p.emboss(height, 0.5, 1.0);
  streaks(p, 7, 44, 'grey', 0.14, 0.3);          // runoff below the joints
  p.grime(0.35, 'grey', 0.12, 8);
  return p.snap(0.6);
};

T.STORBASE = () => {
  /* The plinth, and the skin of every one-sided wall the car park has:
     painted blockwork the trolleys have been hitting since it opened.

     IT WAS THE WRONG SIZE, in the same way the pier's brick was. One
     course was sixteen units and one block thirty-two, which at
     thirty-two units to the metre is a block a metre long and half a
     metre tall — masonry for a giant. A dense block is 440 by 215, so
     this is now four courses of eight and four blocks of sixteen to the
     repeat, which is as close to right as a texture one pixel to the
     unit can get.

     And the speckle went with it. There was an aggregate pass on this
     throwing a hundred and twenty bright points over a dark field, and
     what that draws is not concrete, it is snow: a block wall is a FLAT
     painted surface whose whole character is the joint pattern and the
     places the paint has failed. */
  const p = new Pix(64, 32, 22);
  brickwork(p, 22, 'grey', 0.34, 0.44, 0.26, 8, 16);
  /* the paint, which went on over the block and is coming off it: thin
     on the arrises, gone in patches at the bottom where the water sits */
  const n = fbm(64, 32, 8, 3, 25);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 64; x++)
    p.wash(x, y, 'bone', 0.44, Math.max(0, 0.42 - (1 - y / 32) * 0.10) * (0.5 + n[y * 32 % (64 * 32) + x] * 0.5));
  /* trolley scars: a horizontal scuff at the height a trolley hits,
     which on a 32-unit band is two thirds of the way up */
  const rng = makeRng(27);
  for (let k = 0; k < 40; k++) {
    const x = Math.floor(rng() * 64), y = 8 + Math.floor(rng() * 8);
    for (let d = 0; d < 2 + rng() * 5; d++) p.wash((x + d) % 64, y, 'grey', 0.22, 0.35);
  }
  streaks(p, 4, 29, 'grey', 0.16, 0.3);
  p.grime(0.42, 'grey', 0.12, 9);
  return p.snap(0.5);
};

T.BRANDBAND = () => {
  /* The sign band. It carried the store's name in white across the whole
     front of the anchor and the name is off it now, at the user's
     request; what is left is the TRAY — the red channel the letters were
     mounted in, which is the part of a supermarket fascia that is
     actually a piece of building.

     A texture that repeats sixty times sideways has to survive being
     seen sixty times at once, and lettering does not: a word at this
     size is a shape the eye locks onto, and sixty of them in a row read
     as wallpaper rather than as a sign. What tiles honestly is the thing
     the band is made of, so this is panel, joint, panel: the returned
     edge top and bottom, a seam every repeat where two tray sections
     meet, and nothing else.

     Drawn at 64x64 and declared 96 tall, so one repeat is exactly the
     fascia band between the soffit and the canopy edge. */
  const p = new Pix(64, 64, 23);
  const n = fbm(64, 64, 8, 2, 23);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'red', 0.44 + n[y * 64 + x] * 0.12);
  /* the tray: a returned edge top and bottom, catching the canopy light */
  for (let y = 0; y < 4; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'red', y < 2 ? 0.66 : 0.54);
  for (let y = 58; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'red', y > 61 ? 0.14 : 0.24);
  /* the joint between two tray sections, at the repeat so it lands on
     every one and reads as panelisation rather than as a tiling seam */
  for (let y = 4; y < 58; y++) { p.ink(0, y, 'red', 0.30); p.ink(63, y, 'red', 0.56); }
  /* and the streak below it, where sixty years of rain came off the joint */
  const rng = makeRng(91);
  for (let y = 6; y < 58; y++) if (rng() < 0.7) p.ink(2, y, 'red', 0.34);
  p.grime(0.4, 'grey', 0.10, 10);
  return p.snap(0.5);
};

T.STORGLAS = () => {
  /* Shopfront glazing. Dark, because you are outside looking in and the
     lights are off in half the store. */
  const p = new Pix(64, 64, 24);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const sheen = Math.max(0, 1 - Math.abs((x + y * 0.4) % 42 - 8) / 14);
    p.ink(x, y, 'blue', 0.16 + sheen * 0.20 + (y / 64) * 0.06);
  }
  /* Mullions: a vertical every 32, a transom near the top */
  for (const mx of [0, 32]) { p.vline(mx, 0, 63, 'grey', 0.42); p.vline(mx + 1, 0, 63, 'grey', 0.20); }
  p.hline(0, 63, 8, 'grey', 0.42); p.hline(0, 63, 9, 'grey', 0.20);
  p.hline(0, 63, 62, 'grey', 0.34); p.hline(0, 63, 63, 'grey', 0.16);
  /* No cracks here. There WERE three broken panes drawn into this, from
     when the glazed run across the front was twelve hundred units long;
     at nearly four thousand the same three panes repeat sixty times and
     the whole shopfront reads as wallpaper. Damage that is supposed to
     be an event cannot live in a tiling texture — it lives on UNITSHUT,
     where it is graffiti and repeating is the point. */
  for (let y = 40; y < 64; y++) for (let x = 0; x < 64; x++)   // stall riser
    p.ink(x, y, 'grey', 0.17 + ((x >> 4) & 1) * 0.02);
  p.hline(0, 63, 39, 'grey', 0.40); p.hline(0, 63, 40, 'grey', 0.20);
  /* what is behind it: the tops of the aisle runs, out of focus */
  const rng = makeRng(55);
  for (let i = 0; i < 20; i++) {
    const x = Math.floor(rng() * 64), w = 2 + Math.floor(rng() * 5);
    const top = 22 + Math.floor(rng() * 10);
    for (let y = top; y < 39; y++)
      for (let xx = x; xx < x + w; xx++) p.ink(xx % 64, y, 'grey', 0.10 + rng() * 0.06);
  }
  return p.snap(0.4);
};

/* ---------- inside: the floor and the lid ---------- */

T.LINO = () => {
  /* Vinyl composition tile, 32 to a side, the speckle running right
     through it. Every supermarket on earth. */
  const p = new Pix(64, 64, 31);
  for (let ty = 0; ty < 2; ty++) for (let tx = 0; tx < 2; tx++) {
    /* Alternating tiles a shade apart — you only see it under the
       strip lights, which is exactly when you do see it */
    const base = (tx + ty) % 2 ? 0.60 : 0.55;
    for (let y = 0; y < 32; y++) for (let x = 0; x < 32; x++) p.ink(tx * 32 + x, ty * 32 + y, 'bone', base);
  }
  speckle(64, 64, 900, 31, (x, y, a, b) => {
    if (a < 0.55) p.ink(x, y, 'bone', 0.42 + b * 0.16);
    else if (a < 0.85) p.ink(x, y, 'bone', 0.70 + b * 0.16);
    else p.ink(x, y, 'grey', 0.30 + b * 0.2);
  });
  for (const j of [0, 32]) { p.hline(0, 63, j, 'bone', 0.34); p.vline(j, 0, 63, 'bone', 0.34); }
  /* Buffed lanes: the polished tracks worn where everyone walks */
  const n = valueNoise(64, 64, 3, 66);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    if (n[y * 64 + x] > 0.62) p.wash(x, y, 'bone', 0.82, 0.18);
  return p.snap(0.7);
};

T.LINOWORN = () => {
  const p = T.LINO();
  p.grime(0.7, 'olive', 0.16, 12);
  crack(p, 30, 12, 40, 'grey', 0.14, 8, 1.2);
  const rng = makeRng(101);
  for (let i = 0; i < 6; i++) {           // missing tiles, screed showing
    const x = Math.floor(rng() * 60), y = Math.floor(rng() * 60), w = 3 + Math.floor(rng() * 6);
    for (let dy = 0; dy < w; dy++) for (let dx = 0; dx < w; dx++) p.ink(x + dx, y + dy, 'grey', 0.16 + rng() * 0.06);
  }
  return p.snap(0.6);
};

T.CEILTILE = () => {
  /* Mineral fibre in a tee grid — 64 is one tile plus its grid. The
     perforations are what make it read as ceiling rather than as wall. */
  const p = new Pix(64, 64, 41);
  const n = fbm(64, 64, 16, 2, 41);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.62 + n[y * 64 + x] * 0.10);
  speckle(64, 64, 700, 41, (x, y, a) => { if (a > 0.4) p.ink(x, y, 'bone', 0.50); });
  /* the grid */
  for (const j of [0, 1]) { p.hline(0, 63, j, 'grey', j ? 0.30 : 0.46); p.vline(j, 0, 63, 'grey', j ? 0.30 : 0.46); }
  /* Water damage. There is always water damage. */
  const st = valueNoise(64, 64, 3, 42);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const v = st[y * 64 + x];
    if (v > 0.66) p.wash(x, y, 'olive', 0.34, (v - 0.66) * 2.4);
  }
  return p.snap(0.5);
};

/* --------------------------------------------------------------------
   A ceiling with fittings in it

   A suspended ceiling is a grid of tiles with a fluorescent fitting every
   so often — and "every so often" is the whole problem, because a
   64-pixel texture that tiles every 64 units would put a fitting in
   every single tile.

   So this one is declared as 256 units square: one texture is a 4x4
   block of ceiling tiles with a single twin fitting in it, and the
   fittings land every 256 units instead of every 64. A texel is four
   units instead of one, which is nothing on a surface three metres over
   your head that is never seen square on.

   THE TEXTURE IS THE WHOLE LIGHT. There used to be a LAMP sprite hung
   34 units under the ceiling doing the lit part, and it is gone: the
   fitting is paint, so the paint has to be ALIGHT — a near-white
   diffuser, four tubes at the top of the ramp, and a glow thrown onto
   the tiles around the flange, which is the part that actually says the
   thing is on.

   The old objection to painting a light into a ceiling was that it stays
   lit after you have broken it. It does not, and no sprite was needed to
   fix that: a flat is shaded by its sector's light level like every
   other surface, and the sector's light level IS these fittings (see
   Game.relight). Kill the lights over an aisle and the ceiling that was
   throwing the light goes down with the aisle it was throwing it on.

   The fitting is centred in the texture on purpose. Flats are aligned to
   the world grid and the vertical axis is flipped on upload, so anything
   NOT centred lands somewhere different from where it looks like it
   should, and the lamps hung in world space would miss their holes.
   ------------------------------------------------------------------ */
T.CEILFIT = () => {
  /* THE CEILING, AND THE FITTING IN IT.

     Declared 256 units square on a 64-pixel picture, so one texel is
     four units and the tee grid falls every sixteen texels, which is one
     ceiling tile of sixty-four units. One fitting per texture, dead
     centre, because js/maps/sellwrong.js lays the lamp objects on the
     same 256 pitch at the same offset — a fitting drawn anywhere else is
     a lamp hanging beside a hole.

     WHAT IS DRAWN HERE IS A LIGHT THAT IS ON, and every fitting in the
     shop is the same one, because a tiling texture cannot be anything
     else. That is the trade for having no sprite, and it is the right
     way round: a shop lit evenly by its ceiling is what a shop looks
     like, and the unevenness that matters — the run of lights over a
     fire going out together — comes from the sectors darkening and the
     ceiling charring, both of which this can draw.

     From the user's reference: four tubes, a prismatic diffuser ribbed
     across the short way, dark lampholders at both ends of every tube,
     and a pale works-painted tray with a flange round it. */
  const p = new Pix(64, 64, 44);

  const n = fbm(64, 64, 16, 2, 44);
  for (let y = 0; y < 64; y++)
    for (let x = 0; x < 64; x++)
      p.ink(x, y, 'bone', 0.58 + n[y * 64 + x] * 0.10);
  speckle(64, 64, 500, 45, (x, y, a) => { if (a > 0.45) p.ink(x, y, 'bone', 0.48); });

  /* the tee grid: a line every 16 texels, which is every 64 world units,
     which is one ceiling tile */
  for (let g = 0; g < 64; g += 16) {
    p.hline(0, 63, g, 'grey', 0.40); p.vline(g, 0, 63, 'grey', 0.40);
    p.hline(0, 63, g + 1, 'grey', 0.26); p.vline(g + 1, 0, 63, 'grey', 0.26);
  }

  /* water damage, which there always is */
  const st = valueNoise(64, 64, 3, 46);
  for (let y = 0; y < 64; y++)
    for (let x = 0; x < 64; x++) {
      const v = st[y * 64 + x];
      if (v > 0.62) p.wash(x, y, 'olive', 0.32, (v - 0.62) * 2.0);
    }

  fitTray(p, 16, 25, 32, 14, 47);
  return p.snap(0.5);
};

/* --------------------------------------------------------------------
   ONE FITTING, SEEN FROM UNDERNEATH

   Shared between the ceiling texture and its charred twin, and written
   out here rather than inline because getting four tubes, their holders
   and a ribbed diffuser into thirty-two texels by fourteen is fiddly
   enough to want doing once.

   THE RIBS ARE THE WHOLE LOOK of a prismatic diffuser and they are two
   texels wide: one for the facet that faces the light and one for the
   one that does not. At one texel they alias into a flat grey the moment
   the ceiling is at any angle, which is always, because it is a ceiling.
   ------------------------------------------------------------------ */
function fitTray(p, x0, y0, w, h, seed, lit = true) {
  const rng = makeRng(seed);
  const x1 = x0 + w - 1, y1 = y0 + h - 1;
  /* FOUR TUBES. Even spacing across the tray's depth, one texel each,
     which at four units to the texel is a fat tube — and a fat tube is
     the right answer at this size, because the alternative is a tube
     that is there in some ceiling tiles and not in others. */
  const rows = [y0 + 2, y0 + 5, y0 + 8, y0 + 11];
  /* how far outside the flange a texel is */
  const out = (x, y) => Math.hypot(Math.max(0, x0 - 1 - x, x - x1 - 1),
                                   Math.max(0, y0 - 1 - y, y - y1 - 1));

  const R = 6;
  for (let y = y0 - 1 - R; y <= y1 + 1 + R; y++)
    for (let x = x0 - 1 - R; x <= x1 + 1 + R; x++) {
      const d = out(x, y);
      if (d <= 0 || d > R) continue;
      /* WHAT IT THROWS ON THE TILES AROUND IT, which is the one thing
         that says a fitting is lit rather than merely pale. Measured out
         from the flange and falling off, so the tile beside a fitting is
         visibly brighter than the tile halfway between two of them —
         which is what a ceiling under fluorescent light does, and the
         reason you can tell at a glance from the ceiling alone whether a
         shop's lights are on.

         The flange's SHADOW is the other half of that. A fitting that is
         lit does not cast one onto the tiles it is lighting; a dead one
         in a burnt ceiling does nothing else. */
      if (lit) p.wash(x, y, 'bone', 0.98, (1 - d / (R + 1)) * 0.40);
      else p.wash(x, y, 'grey', 0.10, (1 - d / (R + 1)) * 0.55);
    }

  /* THE FLANGE: works-painted steel with its own tubes shining on it,
     so it is the brightest thing on the ceiling short of the glass. */
  for (let y = y0 - 1; y <= y1 + 1; y++)
    for (let x = x0 - 1; x <= x1 + 1; x++)
      p.ink(x, y, lit ? 'bone' : 'grey', lit ? 0.80 + (y < y0 ? 0.06 : 0) : 0.22);
  /* the corner joints, which is where a works-painted tray shows — a
     seam in something lit, and a dark notch in something dead */
  for (const cx of [x0 - 1, x1 + 1]) for (const cy of [y0 - 1, y1 + 1])
    p.ink(cx, cy, lit ? 'bone' : 'grey', lit ? 0.60 : 0.10);

  /* the tray, white inside, with the reflector turning down at the ends */
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++)
      p.ink(x, y, lit ? 'bone' : 'grey', lit ? 0.66 : 0.13);
  p.vline(x0, y0, y1, lit ? 'bone' : 'grey', lit ? 0.56 : 0.10);
  p.vline(x1, y0, y1, lit ? 'bone' : 'grey', lit ? 0.52 : 0.09);

  for (const ty of rows)
    for (let x = x0 + 2; x <= x1 - 2; x++) {
      if (!lit) {
        /* WHAT IS LEFT OF A TUBE THAT COOKED: a dark line with pieces
           missing out of it, and nothing behind where the glass was but
           the inside of the tray. */
        if (((x * 7 + ty * 13) & 7) < 3) continue;
        p.ink(x, ty, 'grey', 0.26); p.ink(x, ty + 1, 'grey', 0.16);
        continue;
      }
      /* THE TUBES ARE COOL AND THE PAINT ROUND THEM IS WARM. Grey at the
         top of its ramp is 248,248,252 and bone at the top is
         244,238,216 — the same luminance, a different white — and a cool
         tube over warm paint is what makes white read as LIGHT rather
         than as more white paint. They are also the only thing in the
         shop drawn at the very top of a ramp, which is what being the
         light source means.

         THE BANDS HAVE TO BEAT THE RIBS. Two bright texels against one
         dim one is four tubes; anything closer than that crossed with
         the ribbing below is a grille, and a grille in a ceiling is not
         a light, it is a vent. */
      p.ink(x, ty, 'grey', 1.0);             // the tube through the glass
      p.ink(x, ty + 1, 'bone', 0.94);        // and the light it throws on the tray
    }

  /* THE PRISMATIC DIFFUSER over the lot of it: ribs across the short
     way, two texels to a rib, so the facet that faces the light and the
     one that does not each get one. Gone entirely on a dead one — the
     glass is the first thing off a fitting that has been in a fire.

     ONE ALPHA THE WHOLE HEIGHT OF THE TRAY, which is the difference
     between ribs and a dot grid. The first cut washed the tube rows and
     the gaps between them by different amounts, and the ribbing crossed
     with the banding came out as a chequer — which is what a diffuser
     does NOT look like, and which at ceiling distance is just noise.
     It is faint for the same reason: at four units to the texel a rib is
     under a pixel from the floor, so its whole job is to take the shine
     off, not to be seen. */
  if (lit)
    for (let x = x0 + 1; x <= x1 - 1; x++) {
      const face = ((x - x0) & 2) === 0;
      for (let y = y0 + 1; y <= y1 - 1; y++)
        p.wash(x, y, 'bone', face ? 1.0 : 0.58, 0.12);
    }

  /* THE LAMPHOLDERS, last, because they are the one thing on a fitting
     that is genuinely dark and the diffuser does not go over them: the
     glass stops short of the holders at both ends. Two texels square, one
     per tube per end, so four of them read as four — and against a lit
     tray they are the detail that keeps this from being a white slab. */
  for (const ty of rows)
    for (const ex of [x0 + 1, x1 - 2])
      for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++)
        p.ink(ex + i, ty + j, 'grey', lit ? (j ? 0.12 : 0.18) : (j ? 0.06 : 0.09));

  if (!lit) {
    /* the scorch where the ballast went, and the last of the fire in it.
       The ember speckle charVariant lays over the whole ceiling is
       painted out by everything above — the fitting is hardware, not
       tile — so a little of it goes back. */
    const sx = x0 + 2 + Math.floor(rng() * (w - 9));
    for (let y = y0 - 2; y <= y0 + 3; y++)
      for (let x = sx; x < sx + 7; x++) p.wash(x, y, 'grey', 0.04, 0.5);
    for (let y = y0; y <= y1; y++)
      for (let x = x0; x <= x1; x++)
        if (rng() < 0.03) p.ink(x, y, 'fire', 0.26 + rng() * 0.30);
    return;
  }

  /* and thirty years of dust on the inside of the glass, which is why
     the ends of a fitting are always greyer than its middle. Lighter
     than it was: the tubes are alight now and they wash some of it out,
     but not all of it, and a fitting with no grime in it is a render. */
  for (let y = y0; y <= y1; y++)
    for (let x = x0; x <= x1; x++) {
      const e = Math.min(x - x0, x1 - x) / (w / 2);
      if (e < 0.34) p.wash(x, y, 'grey', 0.30, (0.34 - e) * 0.38);
      if (rng() < 0.05) p.wash(x, y, 'olive', 0.34, 0.16);
    }
}

T.CEILDECK = () => {
  /* Back of house has no ceiling tiles. You look straight up at profiled
     metal deck with the purlins crossing under it, and everything up
     there is filthy because nobody has ever been up there. */
  const p = new Pix(64, 64, 42);
  const height = new Float32Array(64 * 64);
  const n = fbm(64, 64, 12, 2, 43);
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      /* the deck profile: a trough, a lit rise, a flat crown */
      const r = x % 16;
      let t, hgt;
      if (r < 2)       { t = 0.09; hgt = 0.05; }
      else if (r < 4)  { t = 0.30; hgt = 0.85; }
      else if (r < 12) { t = 0.21; hgt = 0.60; }
      else if (r < 14) { t = 0.14; hgt = 0.30; }
      else             { t = 0.10; hgt = 0.10; }
      p.ink(x, y, 'grey', t + n[y * 64 + x] * 0.05);
      height[y * 64 + x] = hgt;
    }
  }
  /* the purlin running across, in front of everything */
  for (let y = 28; y < 36; y++) {
    for (let x = 0; x < 64; x++) {
      const t = y < 30 ? 0.34 : y < 34 ? 0.22 : 0.10;
      p.ink(x, y, 'grey', t);
      height[y * 64 + x] = y < 30 ? 0.95 : 0.75;
    }
  }
  for (let x = 6; x < 64; x += 16) { p.ink(x, 31, 'rust', 0.34); p.ink(x, 32, 'rust', 0.22); }  // bolts
  p.emboss(height, 0.34, 1.0);
  const rng = makeRng(44);
  for (let i = 0; i < 60; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    p.wash(x, y, 'rust', 0.18, 0.3 + rng() * 0.4);
  }
  p.grime(0.45, 'grey', 0.05, 13);
  return p.snap(0.4);
};

/* ---------- inside: walls ---------- */

T.WALLPANL = () => {
  const p = new Pix(64, 64, 51);
  const n = fbm(64, 64, 12, 3, 51);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.58 + n[y * 64 + x] * 0.12);
  p.hline(0, 63, 0, 'bone', 0.40);
  p.grime(0.45, 'grey', 0.1, 14);
  streaks(p, 4, 52, 'grey', 0.16, 0.25);
  return p.snap(0.6);
};

T.TILEWALL = () => {
  /* 8-pixel tiles with grout. The staff corridor and the toilets. */
  const p = new Pix(64, 64, 53);
  const height = new Float32Array(64 * 64);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const gx = x % 8, gy = y % 8;
    const grout = gx === 0 || gy === 0;
    height[y * 64 + x] = grout ? 0.2 : 0.7;
    if (grout) p.ink(x, y, 'olive', 0.22);
    else {
      const v = valueNoise(1, 1, 1, x * 131 + y * 17)[0];
      p.ink(x, y, 'bone', 0.72 + v * 0.10);
    }
  }
  p.emboss(height, 0.4, 1.0);
  p.grime(0.55, 'olive', 0.14, 15);
  return p.snap(0.5);
};

T.STOCKWAL = () => {
  /* Painted breeze block, 32x16 units, back of house. Unpainted below
     where the pallet trucks live. */
  const p = new Pix(64, 64, 54);
  const height = new Float32Array(64 * 64);
  const n = fbm(64, 64, 16, 3, 54);
  for (let y = 0; y < 64; y++) {
    const row = Math.floor(y / 16);
    for (let x = 0; x < 64; x++) {
      const off = (row % 2) * 16;
      const bx = (x + off) % 32, by = y % 16;
      const mortar = bx < 2 || by < 2;
      height[y * 64 + x] = mortar ? 0.25 : 0.72;
      p.ink(x, y, mortar ? 'grey' : 'bone', mortar ? 0.22 : (0.40 + n[y * 64 + x] * 0.14));
    }
  }
  p.emboss(height, 0.42, 1.0);
  p.grime(0.6, 'rust', 0.14, 16);
  return p.snap(0.6);
};

T.HAZARD = () => {
  const p = new Pix(64, 64, 61);
  hazardStripes(p, 8, 'yellow', 0.72, 'grey', 0.08);
  const n = fbm(64, 64, 8, 2, 62);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    if (n[y * 64 + x] > 0.58) p.wash(x, y, 'grey', 0.14, 0.4);   // scuffed off
  return p.snap(0.5);
};

/* ---------- the fixtures: the reason anyone is here ---------- */

T.SHELFSTK = () => {
  /* A gondola full of stock, side on. Four shelves in 64, and each one is
     a row of little coloured boxes. This is the single most important
     texture in the game: it is what an aisle IS.

     The stock is drawn from every ramp at once on purpose. Everything
     else in the store is bone and grey; the shelves are the only colour
     in the room, which is exactly the trick a real supermarket pulls. */
  const p = new Pix(64, 64, 71);
  p.fill('grey', 0.16);
  const stockKeys = ['red', 'blue', 'green', 'yellow', 'olive', 'purple', 'cyan', 'pink', 'rust', 'brown'];
  const rng = makeRng(71);

  for (let shelf = 0; shelf < 4; shelf++) {
    const top = shelf * 16;
    /* the shelf pan itself: a lit lip and the shadow it throws */
    p.hline(0, 63, top + 14, 'grey', 0.52);
    p.hline(0, 63, top + 15, 'grey', 0.10);
    /* products, packed left to right in random widths */
    let x = Math.floor(rng() * 6);
    while (x < 64) {
      const w = 3 + Math.floor(rng() * 5);
      const hgt = 8 + Math.floor(rng() * 5);
      const key = stockKeys[Math.floor(rng() * stockKeys.length)];
      const t = 0.35 + rng() * 0.4;
      const y0 = top + 14 - hgt;
      for (let yy = 0; yy < hgt; yy++)
        for (let xx = 0; xx < w; xx++)
          p.ink(x + xx, y0 + yy, key, t);
      /* the lit top-left edge and a label band across it */
      p.hline(x, x + w - 1, y0, key, Math.min(1, t + 0.28));
      p.vline(x, y0, y0 + hgt - 1, key, Math.min(1, t + 0.18));
      p.vline(x + w - 1, y0, y0 + hgt - 1, key, Math.max(0, t - 0.22));
      if (w >= 5 && hgt >= 9) p.hline(x + 1, x + w - 2, y0 + 3, 'bone', 0.82);
      x += w + (rng() < 0.14 ? 1 + Math.floor(rng() * 2) : 0);   // occasional gap
    }
    /* the shelf-edge price rail */
    p.hline(0, 63, top + 15, 'yellow', 0.62);
    for (let x2 = 1; x2 < 64; x2 += 9) p.ink(x2, top + 15, 'grey', 0.1);
  }
  p.grime(0.3, 'grey', 0.1, 17);
  return p.snap(0.4);
};

T.SHELFEMP = () => {
  /* The same gondola after the panic buying. Perforated back panel,
     bare shelf pans, a couple of survivors. */
  const p = new Pix(64, 64, 72);
  p.fill('grey', 0.26);
  for (let y = 2; y < 64; y += 4) for (let x = 2; x < 64; x += 4) p.ink(x, y, 'grey', 0.12);
  const rng = makeRng(72);
  for (let shelf = 0; shelf < 4; shelf++) {
    const top = shelf * 16;
    p.hline(0, 63, top + 14, 'grey', 0.48);
    p.hline(0, 63, top + 15, 'grey', 0.08);
    p.hline(0, 63, top + 15, 'yellow', 0.5);
    for (let i = 0; i < 2; i++) {
      if (rng() < 0.45) continue;
      const x = Math.floor(rng() * 56), w = 3 + Math.floor(rng() * 4), hgt = 7 + Math.floor(rng() * 4);
      const key = ['red', 'blue', 'olive'][Math.floor(rng() * 3)];
      const t = 0.3 + rng() * 0.3, y0 = top + 14 - hgt;
      for (let yy = 0; yy < hgt; yy++) for (let xx = 0; xx < w; xx++) p.ink(x + xx, y0 + yy, key, t);
      p.hline(x, x + w - 1, y0, key, Math.min(1, t + 0.25));
    }
  }
  p.grime(0.5, 'grey', 0.08, 18);
  return p.snap(0.4);
};

T.SHELFBAK = () => {
  /* Back-to-back gondolas: what you see is the perforated steel. */
  const p = new Pix(64, 64, 73);
  const n = fbm(64, 64, 8, 2, 73);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.28 + n[y * 64 + x] * 0.08);
  for (let y = 2; y < 64; y += 4) for (let x = 2; x < 64; x += 4) {
    p.ink(x, y, 'grey', 0.12);
    p.ink(x, y - 1, 'grey', 0.40);
  }
  /* uprights every 32 */
  for (const ux of [0, 32]) {
    for (let y = 0; y < 64; y++) { p.ink(ux, y, 'grey', 0.42); p.ink(ux + 1, y, 'grey', 0.20); }
    for (let y = 3; y < 64; y += 5) p.ink(ux, y, 'grey', 0.10);   // slot punchings
  }
  p.grime(0.4, 'rust', 0.16, 19);
  return p.snap(0.4);
};

T.SHELFEND = () => {
  /* The end cap: a promotional block and a screaming price. Where the
     margin is. */
  const p = new Pix(64, 64, 74);
  p.fill('grey', 0.18);
  const rng = makeRng(74);
  for (let y = 22; y < 62; y++) for (let x = 4; x < 60; x++) p.ink(x, y, 'red', 0.34 + rng() * 0.1);
  for (let y = 22; y < 62; y += 8) p.hline(4, 59, y, 'red', 0.20);
  for (let x = 4; x < 60; x += 8) p.vline(x, 22, 61, 'red', 0.20);
  p.hline(4, 59, 22, 'red', 0.58);
  p.vline(4, 22, 61, 'red', 0.5);
  /* the sign above it */
  for (let y = 4; y < 20; y++) for (let x = 2; x < 62; x++) p.ink(x, y, 'yellow', 0.72);
  p.frame(2, 4, 60, 16, 'yellow', 0.3);
  drawTextCentred(p, 'SALE', 32, 6, 'red', 0.28);
  drawTextCentred(p, '99P', 32, 13, 'red', 0.28);
  p.grime(0.25, 'grey', 0.1, 20);
  return p.snap(0.4);
};

T.FREEZDOR = () => {
  /* Glass freezer door: frame, frost, cold light, and the stock behind
     it going soft. */
  const p = new Pix(64, 64, 81);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    /* the goods, blurred by the glass into bands of colour */
    const shelf = Math.floor(y / 16);
    const band = valueNoise(1, 1, 1, shelf * 977 + Math.floor(x / 6) * 31)[0];
    const key = ['blue', 'cyan', 'bone', 'red'][Math.floor(band * 4) % 4];
    p.ink(x, y, key, 0.22 + band * 0.2);
  }
  for (let s = 0; s < 4; s++) { p.hline(0, 63, s * 16 + 15, 'grey', 0.34); p.hline(0, 63, s * 16, 'grey', 0.12); }
  /* frost creeping in from the frame */
  const fr = fbm(64, 64, 8, 3, 82);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const edge = Math.min(x, 63 - x, y, 63 - y) / 14;
    const f = Math.max(0, 1 - edge) * fr[y * 64 + x];
    if (f > 0.18) p.wash(x, y, 'cyan', 0.72, f);
  }
  /* the frame and the handle */
  for (const fx of [0, 1, 62, 63]) p.vline(fx, 0, 63, 'grey', fx < 2 ? 0.5 : 0.24);
  for (const fy of [0, 1, 62, 63]) p.hline(0, 63, fy, 'grey', fy < 2 ? 0.5 : 0.24);
  for (let y = 20; y < 44; y++) { p.ink(3, y, 'grey', 0.62); p.ink(4, y, 'grey', 0.3); }
  /* the specular streak down the glass */
  for (let y = 0; y < 64; y++) { const x = 46 - Math.floor(y * 0.12); p.wash(x, y, 'cyan', 0.9, 0.35); p.wash(x + 1, y, 'cyan', 0.9, 0.18); }
  return p.snap(0.4);
};

T.CHILLER = () => {
  /* Open multideck: the stuff nobody took, lit blue from within. */
  const p = new Pix(64, 64, 83);
  p.fill('grey', 0.14);
  const rng = makeRng(83);
  for (let s = 0; s < 4; s++) {
    const top = s * 16;
    for (let y = top + 2; y < top + 14; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'blue', 0.14);
    let x = 0;
    while (x < 64) {
      const w = 4 + Math.floor(rng() * 4);
      if (rng() > 0.28) {
        const key = ['pink', 'bone', 'red', 'olive'][Math.floor(rng() * 4)];
        const t = 0.3 + rng() * 0.35;
        for (let yy = top + 5; yy < top + 14; yy++) for (let xx = 0; xx < w - 1; xx++) p.ink(x + xx, yy, key, t);
        p.hline(x, x + w - 2, top + 5, key, Math.min(1, t + 0.25));
      }
      x += w;
    }
    p.hline(0, 63, top + 14, 'grey', 0.44);
    p.hline(0, 63, top + 15, 'grey', 0.06);
    p.hline(0, 63, top + 2, 'cyan', 0.66);              // the cold strip light
    p.hline(0, 63, top + 3, 'cyan', 0.3);
  }
  return p.snap(0.4);
};

/* --- produce: the bins you look down into --------------------------
   A supermarket does not SHELVE fruit and veg, it BINS it — a run of
   open crates at hip height, one category to a crate, shopped by
   looking down into them from the aisle. So the picture that carries
   the department is the one on TOP, and the top of this department was
   SHELFBAK: perforated gondola steel. That is not an oversight anybody
   made on purpose. A fixture in a sector engine is a raised floor with
   a lower texture round its edge, and all the care went into the edge,
   because the edge is the part you can see in a screenshot taken from
   the far end of an aisle. Stand next to it — eye at 49, bench at 40 —
   and the top is nearly all of it.

   One repeat is 64 by 64, which is two metres square, so a five-pixel
   apple is a fifteen-centimetre apple. Every bin is anchored to its own
   south-west corner, so the packing starts at the crate edge rather
   than wherever the world grid happens to fall — the same fix the
   parking bays needed for the same reason.

   PACKED, not scattered: the rows go down at a pitch tighter than one
   item across, so neighbours overlap and the crate liner barely shows.
   A bin with gaps in it reads as a bin somebody has already been
   through, which is a different picture and is the one the flowers
   get. */
const produceTop = (seed, kinds, r, jitter, liner) => () => {
  const p = new Pix(64, 64, seed);
  const rng = makeRng(seed);
  const n = fbm(64, 64, 8, 2, seed);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, liner, 0.10 + n[y * 64 + x] * 0.07);        // the crate, under it all
  /* WHOLE PIXELS. Pix wraps by modulo and does not floor, so a centre
     with a fraction in it produces a fractional array index, and a
     fractional index into a Uint8ClampedArray writes NOWHERE — no
     error, no pixel. The first cut of this passed floats and every
     crate came out as bare liner. */
  const pitch = r * 1.5;
  const items = [];
  for (let row = 0; row * pitch < 64 + pitch; row++) {
    const stagger = row % 2 ? pitch / 2 : 0;
    for (let col = 0; col * pitch < 64 + pitch; col++) items.push({
      x: Math.round(col * pitch + stagger + (rng() - 0.5) * jitter),
      y: Math.round(row * pitch + (rng() - 0.5) * jitter),
      r: r * (0.82 + rng() * 0.36),
      key: kinds[(rng() * kinds.length) | 0],
      t: 0.34 + rng() * 0.34,
    });
  }
  /* Every shadow first, THEN every item. They are packed tighter than
     they are wide, so drawing each pair in turn puts the next row's
     shadow over this row's fruit and the crate goes black. */
  for (const it of items) p.disc(it.x, it.y + 1, it.r + 1, liner, 0.05);
  for (const it of items) {
    p.disc(it.x, it.y, it.r, it.key, it.t);
    /* the wet highlight, up and left, because the ceiling fittings are */
    const o = Math.round(it.r * 0.34);
    p.disc(it.x - o, it.y - o, Math.max(1, it.r * 0.34), it.key, Math.min(1, it.t + 0.28));
  }
  p.grime(0.22, liner, 0.07, seed + 1);
  return p.snap(0.4);
};

T.PRODAPPL = produceTop(180, ['red', 'red', 'olive'],        4.2, 2.2, 'brown');
T.PRODCITR = produceTop(182, ['yellow', 'rust', 'yellow'],   4.0, 2.0, 'brown');
T.PRODGREN = produceTop(184, ['green', 'green', 'olive'],    6.4, 2.8, 'green');
T.PRODROOT = produceTop(186, ['brown', 'bone', 'olive'],     3.4, 2.4, 'brown');

T.PRODFLOW = () => {
  /* Cut flowers are not binned, they are BUCKETED: black pails in a
     block, and what you see from up here is the rim of each one and the
     heads crowded out of it. Gaps between the pails on purpose — this
     is the one display in the store that is meant to look picked
     over. */
  const p = new Pix(64, 64, 188);
  const rng = makeRng(188);
  p.fill('grey', 0.13);
  for (let row = 0; row < 4; row++) for (let col = 0; col < 4; col++) {
    /* rounded, for the reason produceTop is rounded */
    const cx = Math.round(col * 16 + 8 + (rng() - 0.5) * 3);
    const cy = Math.round(row * 16 + 8 + (rng() - 0.5) * 3);
    p.disc(cx, cy, 7, 'grey', 0.06);                         // the pail's shadow
    p.disc(cx, cy, 6, 'grey', 0.22);                         // its rim
    p.disc(cx, cy, 5, 'green', 0.14);                        // stems, in the water
    if (rng() < 0.15) continue;                              // and one nobody refilled
    const key = ['red', 'yellow', 'purple', 'pink', 'bone'][(rng() * 5) | 0];
    for (let i = 0; i < 16; i++) {
      const a = rng() * Math.PI * 2, d = rng() * 4.4;
      p.disc(cx + Math.round(Math.cos(a) * d), cy + Math.round(Math.sin(a) * d),
             1.4, key, 0.32 + rng() * 0.30);
    }
  }
  p.grime(0.3, 'grey', 0.08, 189);
  return p.snap(0.4);
};

T.PRODRIM = () => {
  /* The crate itself: sawn boards eight units to a board with a shadow
     gap between them, declared 64 by 16 so two boards are one repeat.

     It does three jobs at three heights and that is why it is boards.
     It is the TOP of every divider between two bins; it is the eight
     units of LIP that divider stands proud of the produce by; and it is
     the thirty-six-unit face the aisle sees, where it repeats two and a
     quarter times. A texture that has to survive being cut at any
     height had better be made of something that is already stacked. */
  const p = new Pix(64, 16, 190);
  const n = fbm(64, 16, 8, 2, 190);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.38 + n[y * 64 + x] * 0.12);
  for (const by of [0, 8]) {
    for (let x = 0; x < 64; x++) {
      p.ink(x, by, 'brown', 0.56);                           // the board's lit edge
      p.ink(x, by + 6, 'brown', 0.18);                       // and its shadow
      p.ink(x, by + 7, 'grey', 0.05);                        // the gap to the next
    }
    /* the nail heads, at the ends of the boards and every crate along */
    for (let x = 3; x < 64; x += 16) p.ink(x, by + 3, 'grey', 0.34);
  }
  p.grime(0.3, 'brown', 0.10, 191);
  return p.snap(0.4);
};

T.DELICASE = () => {
  /* The serve-over counter. A raked bed of trays behind curved glass,
     a chrome rail across the front, and a stainless kick below.

     Built in bands top to bottom so it reads as a CABINET at a distance
     rather than as things floating in a box — the rail and the kick are
     what sell it, not the meat. */
  const p = new Pix(64, 64, 85);
  const rng = makeRng(85);

  /* 0-10  the lit canopy over the counter */
  for (let y = 0; y < 10; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', 0.30 - y * 0.012);
  p.hline(0, 63, 8, 'bone', 0.92);                  // the strip light in it
  p.hline(0, 63, 9, 'yellow', 0.60);

  /* 10-42  the raked display bed, lit from that strip */
  for (let y = 10; y < 42; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.34 - (y - 10) * 0.004);
  for (let row = 0; row < 4; row++) {
    const y0 = 12 + row * 7;
    let x = 1 + Math.floor(rng() * 3);
    while (x < 63) {
      const w = 7 + Math.floor(rng() * 6);
      const key = rng() < 0.55 ? 'pink' : rng() < 0.6 ? 'red' : 'bone';
      const t = 0.32 + rng() * 0.34;
      /* the enamel tray, then what is in it */
      for (let yy = 0; yy < 6; yy++) for (let xx = 0; xx < w - 1 && x + xx < 64; xx++)
        p.ink(x + xx, y0 + yy, 'bone', 0.52);
      for (let yy = 1; yy < 5; yy++) for (let xx = 1; xx < w - 2 && x + xx < 64; xx++)
        p.ink(x + xx, y0 + yy, key, t);
      p.hline(x + 1, Math.min(63, x + w - 3), y0 + 1, key, Math.min(1, t + 0.26));
      p.hline(x, Math.min(63, x + w - 2), y0 + 5, 'grey', 0.14);   // the tray's shadow
      if (w > 9) { p.ink(x + 2, y0 + 3, 'yellow', 0.85); p.ink(x + 3, y0 + 3, 'yellow', 0.85); }  // the ticket
      x += w;
    }
  }

  /* 42-52  the glass, catching the canopy. Drawn as a wash so the trays
     stay visible through it, which is the entire point of glass. */
  for (let y = 10; y < 46; y++) {
    const sx = 50 - Math.floor((y - 10) * 0.55);
    p.wash(sx, y, 'cyan', 0.86, 0.40);
    p.wash(sx + 1, y, 'cyan', 0.86, 0.20);
    p.wash(12 - Math.floor((y - 10) * 0.2), y, 'cyan', 0.86, 0.16);
  }
  p.hline(0, 63, 44, 'cyan', 0.78);                 // the bottom edge of the glass
  p.hline(0, 63, 45, 'grey', 0.44);
  p.hline(0, 63, 46, 'grey', 0.12);

  /* 47-64  the stainless front and the kick, both scuffed */
  for (let y = 47; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', y < 50 ? 0.46 : y < 60 ? 0.38 : 0.24);
  p.hline(0, 63, 47, 'grey', 0.62);
  p.hline(0, 63, 59, 'grey', 0.16);
  for (let x = 0; x < 64; x++) if (rng() < 0.4) p.wash(x, 50 + Math.floor(rng() * 9), 'grey', 0.5, 0.35);
  p.grime(0.4, 'grey', 0.1, 22);
  return p.snap(0.4);
};

/* =====================================================================
   THE CHECKSTAND

   Eight of these across the front of the shop and the player now spends
   the first thirty seconds of the game standing inside one, which is a
   different job from being a shape you walk past. See A CHECKSTAND in
   js/maps/sellwrong.js for the plan; these are the skins on it.

   EVERY ONE OF THEM IS PEGGED AT THE TOP. A lower band — the step
   between the shop floor and a raised fixture — hangs its texture from
   the TOP of the step downward (see pegOf in js/mapgeo.js), so row zero
   of these is the counter edge and the floor line is `h` minus twelve
   rows further down. Which means the rows nobody ever sees are the
   BOTTOM ones, and the detail that matters goes at the top: the
   bullnose, the bumper, the belt trim. It also means the same texture
   skins a six-unit sliver between two decks of slightly different
   height, out of its own top six rows, and comes out as a counter edge
   for free.
   ===================================================================== */

T.CHECKOUT = () => {
  /* The side of a checkstand: a laminate panel with a bullnose edge, a
     rubber bumper where the trolleys hit it, and a toe recess. 40 tall
     because that is H_FIXTURE, and the top 28 rows of it are the part
     above the floor. */
  const p = new Pix(64, 40, 86);
  const n = fbm(64, 40, 10, 2, 86);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.50 + n[y * 64 + x] * 0.07);
  /* the bullnose: dark under a lit lip, and the top six rows are ALSO
     what skins the step between the scanner bed and the deck */
  p.hline(0, 63, 0, 'bone', 0.70);
  p.box(0, 1, 64, 3, 'grey', 0.22);
  p.hline(0, 63, 4, 'grey', 0.40);
  /* the panel, with a shallow recess line at the joints */
  for (const vx of [1, 33]) { p.vline(vx, 5, 27, 'grey', 0.30); p.vline(vx + 1, 5, 27, 'bone', 0.66); }
  /* the bumper rail, two thirds up, which is what a trolley meets */
  p.box(0, 8, 64, 5, 'grey', 0.17);
  p.hline(0, 63, 8, 'grey', 0.46);
  p.hline(0, 63, 12, 'grey', 0.07);
  /* scuffs ALONG the bumper, because everything that marks it is moving
     horizontally when it does */
  const rng = makeRng(602);
  for (let i = 0; i < 26; i++) {
    const y = 9 + Math.floor(rng() * 4), x0 = Math.floor(rng() * 64), len = 3 + Math.floor(rng() * 11);
    for (let d = 0; d < len; d++) p.wash(x0 + d, y, 'grey', 0.34, 0.4 + rng() * 0.3);
  }
  /* the toe recess, and the shadow it throws on the floor */
  p.box(0, 24, 64, 4, 'grey', 0.11);
  p.hline(0, 63, 24, 'grey', 0.05);
  p.box(0, 28, 64, 12, 'grey', 0.08);
  p.grime(0.45, 'grey', 0.1, 22);
  return p.snap(0.5);
};

T.BELTSIDE = () => {
  /* The side of the conveyor unit, which is a different machine from the
     counter it is bolted to: stainless, ribbed, with the return slot the
     belt disappears into under the top trim. 38 tall — H_BELT — so the
     top 26 rows stand above the floor. */
  const p = new Pix(64, 38, 604);
  const n = fbm(64, 38, 12, 2, 604);
  for (let y = 0; y < 38; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.36 + n[y * 64 + x] * 0.07);
  /* the top trim. Its four rows are also the whole of the sliver between
     the scanner bed and the belt, so they have to read as an edge on
     their own. */
  p.hline(0, 63, 0, 'grey', 0.74);
  p.hline(0, 63, 1, 'grey', 0.58);
  p.box(0, 2, 64, 2, 'grey', 0.30);
  /* the return slot: the dark gap the belt runs back through */
  p.box(0, 4, 64, 4, 'grey', 0.08);
  p.hline(0, 63, 4, 'grey', 0.03);
  p.hline(0, 63, 7, 'grey', 0.46);
  /* brushed ribs down the housing, lit left and shadowed right */
  for (let x = 0; x < 64; x += 8) {
    p.vline(x, 8, 25, 'grey', 0.52);
    p.vline(x + 1, 8, 25, 'grey', 0.24);
  }
  /* the plinth it stands on, and the floor line at row 26 */
  p.box(0, 21, 64, 5, 'grey', 0.19);
  p.hline(0, 63, 21, 'grey', 0.44);
  p.box(0, 26, 64, 12, 'grey', 0.07);
  streaks(p, 5, 605, 'rust', 0.2, 0.3);
  p.grime(0.4, 'grey', 0.09, 606);
  return p.snap(0.5);
};

T.BELTRUB = () => {
  /* THE BELT. 60 across, which is the width of a counter run, and 18
     along, which makes one repeat one cleat — so the cleats are 18 units
     apart down a belt 108 long and there are exactly six of them.
     Black rubber is nearly the darkest thing in the shop and would read
     as a hole if it were flat, so what makes it a belt is the sheen down
     the middle and the cleat catching the light at its top edge. */
  const p = new Pix(60, 18, 608);
  const n = fbm(60, 18, 10, 2, 608);
  for (let y = 0; y < 18; y++) for (let x = 0; x < 60; x++) {
    /* brighter along the crown of the belt and falling off to the edges,
       because a belt on rollers is not flat. It sits at 0.18 and not at
       the 0.11 a black belt deserves, because the front end is lit at
       0.32 and a surface painted at the bottom of the grey ramp under a
       light like that is not a dark thing, it is a hole. */
    const crown = 1 - Math.abs(x - 29.5) / 30;
    p.ink(x, y, 'grey', 0.18 + crown * 0.07 + n[y * 60 + x] * 0.05);
  }
  /* the cleat: a shadow under a lit ridge, and it has to carry the
     picture on its own — it is the only thing in here that says the
     surface is moving */
  p.hline(0, 59, 0, 'grey', 0.42);
  p.hline(0, 59, 1, 'grey', 0.08);
  p.hline(0, 59, 2, 'grey', 0.14);
  /* and the tracking lines a worn belt develops */
  const rng = makeRng(609);
  for (const lx of [14, 45]) for (let y = 3; y < 18; y++) if (rng() < 0.7) p.wash(lx, y, 'grey', 0.10, 0.5);
  /* the dark edges, where the belt runs under the guards */
  for (let x = 0; x < 3; x++) for (let y = 0; y < 18; y++) {
    p.wash(x, y, 'grey', 0.07, 0.6); p.wash(59 - x, y, 'grey', 0.07, 0.6);
  }
  p.grime(0.3, 'bone', 0.1, 610);
  return p.snap(0.45);
};

T.SCANBED = () => {
  /* The scale plate and the scanner glass, 60 by 48, anchored to the
     run so one repeat is exactly the band. Row zero is the belt side:
     the shopping comes in at the top of this picture and leaves at the
     bottom. */
  const p = new Pix(60, 48, 612);
  const n = fbm(60, 48, 12, 3, 612);
  for (let y = 0; y < 48; y++) for (let x = 0; x < 60; x++)
    p.ink(x, y, 'grey', 0.42 + n[y * 60 + x] * 0.08);
  /* the stainless lip the belt delivers over */
  p.box(0, 0, 60, 3, 'grey', 0.62);
  p.hline(0, 59, 3, 'grey', 0.24);
  /* the glass: a dark window with the scale plate seam round it */
  p.box(7, 8, 46, 30, 'grey', 0.09);
  p.frame(6, 7, 48, 32, 'grey', 0.58);
  p.frame(7, 8, 46, 30, 'grey', 0.14);
  /* what makes it GLASS rather than a hole: a raked highlight across it
     and the red of the laser bounced off the underside */
  for (let y = 9; y < 37; y++) for (let x = 8; x < 52; x++) {
    if ((x + y * 2) % 37 < 3) p.wash(x, y, 'grey', 0.72, 0.16);
    if ((x - y) % 23 === 0) p.wash(x, y, 'red', 0.5, 0.20);
  }
  p.hline(10, 49, 22, 'red', 0.42, 255);
  p.hline(10, 49, 23, 'red', 0.20, 255);
  /* the weigh plate seam and the four corners it sits on */
  p.frame(4, 5, 52, 38, 'grey', 0.30);
  for (const [cx, cy] of [[6, 7], [53, 7], [6, 42], [53, 42]]) p.disc(cx, cy, 1.4, 'grey', 0.66);
  /* the deck below it, scuffed where everything is dragged across */
  p.box(0, 42, 60, 6, 'grey', 0.46);
  const rng = makeRng(613);
  for (let i = 0; i < 30; i++) {
    const y = 42 + Math.floor(rng() * 6), x0 = Math.floor(rng() * 60);
    for (let d = 0; d < 4 + rng() * 9; d++) p.wash(x0 + d, y, 'grey', 0.30, 0.5);
  }
  p.grime(0.35, 'grey', 0.08, 614);
  return p.snap(0.5);
};

T.BAGDECK = () => {
  /* The bagging deck, one repeat over the whole band, row zero the
     scanner end. Brushed stainless with the well pressed into it, and
     the scratches run ACROSS, the way things are dragged off it.

     PAINTED AT 64 AND DECLARED AT 80. Nothing in this game is painted
     bigger than 64 pixels — see THE PIXEL BUDGET — and the world size
     in TEXTURE_SIZES is a separate number: it says how much SHOP one
     repeat covers, not how many texels are in it. So this is 60 by 64
     stretched over a band 60 by 80, which on a deck of brushed steel is
     a stretch nobody can see and on anything with a straight line in it
     would be the first thing they saw. */
  const p = new Pix(60, 64, 616);
  const n = fbm(60, 64, 10, 3, 616);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 60; x++)
    p.ink(x, y, 'grey', 0.44 + n[y * 60 + x] * 0.09);
  /* brushing: fine horizontal grain over the whole sheet */
  const rng = makeRng(617);
  for (let y = 0; y < 64; y++) {
    const t = 0.5 + rng() * 0.5;
    for (let x = 0; x < 60; x++) if (rng() < 0.5) p.wash(x, y, 'grey', y % 2 ? 0.56 : 0.34, 0.10 * t);
  }
  /* the lip at the scanner end and the lip at the front */
  p.box(0, 0, 60, 3, 'grey', 0.64);
  p.hline(0, 59, 3, 'grey', 0.26);
  p.box(0, 61, 60, 3, 'grey', 0.60);
  p.hline(0, 59, 60, 'grey', 0.26);
  /* the pressed well, which is the only thing that says which way up a
     sheet of steel is: a shadow on the top-left edge, a highlight on the
     bottom-right, because that is where the light is */
  p.frame(8, 10, 44, 46, 'grey', 0.22);
  p.hline(8, 51, 10, 'grey', 0.18);
  p.vline(8, 10, 55, 'grey', 0.18);
  p.hline(9, 52, 56, 'grey', 0.68);
  p.vline(52, 11, 56, 'grey', 0.68);
  for (let y = 12; y < 55; y++) for (let x = 10; x < 51; x++) p.wash(x, y, 'grey', 0.40, 0.25);
  /* and the scratches */
  for (let i = 0; i < 40; i++) {
    const y = 5 + Math.floor(rng() * 56), x0 = Math.floor(rng() * 60);
    const len = 4 + Math.floor(rng() * 20);
    for (let d = 0; d < len; d++) p.wash(x0 + d, y, 'grey', rng() < 0.4 ? 0.70 : 0.28, 0.35 + rng() * 0.3);
  }
  p.grime(0.3, 'grey', 0.07, 618);
  return p.snap(0.5);
};

T.TILLTOP = () => {
  /* The laminate the counter tops are made of, and the lid of anything
     standing on one. Speckled, because every shop counter in the world
     is speckled — it is the one pattern that hides what gets spilled on
     it, which is why it exists. */
  const p = new Pix(64, 64, 620);
  const n = fbm(64, 64, 8, 3, 620);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.52 + n[y * 64 + x] * 0.03);
  /* THE SPECKLE IS A WASH AND NOT AN INK. Inked at full strength it came
     out as granite confetti — seven hundred hard dots of three different
     ramps over a pale field, which at the range you stand from a counter
     is television static. What laminate actually is is a pale sheet with
     a fleck you have to be close to see, so each dot is a partial wash
     over the colour that is already there. */
  speckle(64, 64, 620, 621, (x, y, a, b) => {
    p.wash(x, y, a < 0.42 ? 'grey' : a < 0.82 ? 'bone' : 'brown',
      a < 0.42 ? 0.30 : a < 0.82 ? 0.74 : 0.36, 0.20 + b * 0.30);
  });
  p.grime(0.22, 'grey', 0.16, 622);
  return p.snap(0.5);
};

T.TILLRAIL = () => {
  /* Stainless tube. 16 by 8, so a rail of any length is a rail and a
     post of any height is a post: there is nothing in it that happens
     once. Lit along the top third, dark along the bottom, with a
     specular dash every repeat. */
  const p = new Pix(16, 8, 624);
  for (let y = 0; y < 8; y++) {
    const t = y === 0 ? 0.60 : y === 1 ? 0.80 : y < 4 ? 0.52 : y < 6 ? 0.36 : 0.20;
    for (let x = 0; x < 16; x++) p.ink(x, y, 'grey', t);
  }
  p.hline(3, 8, 1, 'grey', 0.96);
  p.hline(11, 13, 2, 'grey', 0.72);
  p.hline(0, 15, 7, 'grey', 0.12);
  return p.snap(0.35);
};

T.REGISTER = () => {
  /* The terminal: a screen on a body with a keyboard under it, a receipt
     slot and the cash drawer below that. 34 by 38, which is the long
     face of the box it goes on. */
  const p = new Pix(34, 38, 626);
  const n = fbm(34, 38, 8, 2, 626);
  for (let y = 0; y < 38; y++) for (let x = 0; x < 34; x++)
    p.ink(x, y, 'bone', 0.30 + n[y * 34 + x] * 0.05);
  p.bevel(0, 0, 34, 38, 'bone', 0.52, 'grey', 0.10);
  /* the screen, which is the only lit thing on it */
  p.box(4, 3, 26, 14, 'grey', 0.06);
  p.frame(3, 2, 28, 16, 'grey', 0.18);
  p.box(5, 4, 24, 12, 'blue', 0.30);
  for (let y = 4; y < 16; y += 2) p.hline(5, 28, y, 'blue', 0.42);
  /* two lines of something on it, and a total in the corner */
  p.hline(7, 20, 6, 'cyan', 0.66); p.hline(7, 17, 8, 'cyan', 0.52);
  p.hline(7, 22, 10, 'cyan', 0.52); p.box(18, 12, 10, 3, 'cyan', 0.72);
  /* the receipt slot, and the paper coming out of it */
  p.box(4, 19, 26, 2, 'grey', 0.08);
  p.box(6, 21, 12, 2, 'bone', 0.86);
  /* the keyboard: four rows of keys, lit top-left like everything else */
  for (let ky = 0; ky < 3; ky++) for (let kx = 0; kx < 7; kx++) {
    const x = 4 + kx * 4, y = 24 + ky * 4;
    p.box(x, y, 3, 3, 'bone', 0.44);
    p.hline(x, x + 2, y, 'bone', 0.66);
    p.hline(x, x + 2, y + 2, 'grey', 0.14);
  }
  p.box(24, 24, 6, 7, 'green', 0.44);            // the big green one
  p.hline(24, 29, 24, 'green', 0.66);
  /* the drawer under it */
  p.box(0, 34, 34, 4, 'bone', 0.22);
  p.hline(0, 33, 34, 'bone', 0.50);
  p.box(13, 35, 8, 2, 'grey', 0.46);
  p.grime(0.3, 'grey', 0.09, 627);
  return p.snap(0.45);
};

T.PINPAD = () => {
  /* The card reader on its post. 18 by 16, the long face of the pad. */
  const p = new Pix(18, 16, 628);
  p.fill('bone', 0.26);
  p.bevel(0, 0, 18, 16, 'bone', 0.46, 'grey', 0.08);
  p.box(2, 2, 14, 5, 'green', 0.24);             // the little screen
  p.frame(2, 2, 14, 5, 'grey', 0.14);
  p.hline(3, 11, 4, 'green', 0.74);
  p.hline(3, 8, 5, 'green', 0.50);
  for (let ky = 0; ky < 3; ky++) for (let kx = 0; kx < 3; kx++) {
    const x = 3 + kx * 4, y = 9 + ky * 2;
    p.box(x, y, 3, 1, 'bone', 0.52);
    p.ink(x, y, 'bone', 0.72);
  }
  p.box(14, 9, 3, 5, 'green', 0.46);             // enter
  p.vline(0, 3, 13, 'grey', 0.10);               // the card slot down the side
  p.vline(1, 3, 13, 'grey', 0.36);
  return p.snap(0.4);
};

T.LANENUM = () => {
  /* The lit sign hung over a lane. 52 by 42, read from the back of the
     shop, which is the whole job: at that distance a numeral is four
     pixels and a word is a shape. So it is a chevron and a word, both
     as big as the box will take, white on a green that is lit past one
     — see the light on the prop in js/maps/sellwrong.js. */
  const p = new Pix(52, 42, 630);
  p.fill('grey', 0.22);
  p.bevel(0, 0, 52, 42, 'grey', 0.50, 'grey', 0.08);
  p.box(3, 3, 46, 36, 'green', 0.40);
  p.frame(3, 3, 46, 36, 'green', 0.20);
  /* the chevron, pointing down the lane. Solid: two diagonal strokes and
     a bar across the top was a moustache. */
  for (let i = 0; i < 13; i++) p.hline(13 + i, 38 - i, 7 + i, 'bone', 0.96);
  p.hline(13, 38, 6, 'bone', 0.62);
  drawTextCentred(p, 'OPEN', 26, 25, 'bone', 0.98, 2);
  drawTextCentred(p, 'OPEN', 26, 26, 'bone', 0.72, 2);
  /* the tube's own glow, brightest at the middle of the panel */
  for (let y = 4; y < 38; y++) for (let x = 4; x < 48; x++) {
    const d = 1 - Math.hypot((x - 26) / 24, (y - 21) / 18);
    if (d > 0) p.wash(x, y, 'bone', 0.9, d * 0.12);
  }
  return p.snap(0.3);
};

T.BAGRACK = () => {
  /* The bag rack over the bagging deck: two chrome arms, a bundle of
     carriers hanging off them and one held open. 36 by 38, the long
     face of the frame. */
  const p = new Pix(36, 38, 632);
  p.clear();
  /* the frame */
  for (const x of [3, 32]) { p.vline(x, 2, 37, 'grey', 0.62); p.vline(x + 1, 2, 37, 'grey', 0.26); }
  p.hline(3, 33, 2, 'grey', 0.70);
  p.hline(3, 33, 3, 'grey', 0.34);
  /* the bundle: pale carriers, a hint of blue in the plastic, creased */
  const rng = makeRng(633);
  for (let y = 5; y < 33; y++) {
    const half = 13 - Math.abs(y - 17) * 0.34;
    for (let x = Math.round(18 - half); x <= Math.round(18 + half); x++) {
      const crease = ((x * 3 + y * 5) % 11) < 2;
      p.ink(x, y, 'bone', (crease ? 0.60 : 0.80) + (rng() - 0.5) * 0.08);
      if ((x + y) % 7 === 0) p.wash(x, y, 'blue', 0.66, 0.18);
    }
  }
  /* the two handles over the arms, and the printed band across it */
  for (const hx of [8, 27]) { p.vline(hx, 3, 8, 'bone', 0.88); p.vline(hx + 1, 3, 8, 'bone', 0.62); }
  p.box(8, 16, 20, 4, 'red', 0.46);
  p.hline(8, 27, 16, 'red', 0.66);
  /* the one at the front, filled and standing open */
  p.box(6, 22, 15, 14, 'bone', 0.72);
  p.frame(6, 22, 15, 14, 'bone', 0.44);
  p.hline(7, 19, 22, 'bone', 0.92);
  p.box(9, 25, 9, 3, 'green', 0.46);
  p.grime(0.3, 'grey', 0.08, 634);
  return p.snap(0.45);
};

T.IMPULSE = () => {
  /* The rack on the front of a checkstand: sweets on the top shelf,
     magazines below. 56 by 28, which is half the run of it, so the two
     shelves are at the right height and the merchandise repeats twice
     along a lane rather than being one long photograph.

     It is the only thing on the stand at knee height and it is 8 proud
     of the face, so it is also the only thing here anybody walks into. */
  const p = new Pix(56, 28, 636);
  p.fill('grey', 0.14);
  /* the two shelves */
  p.box(0, 0, 56, 2, 'grey', 0.40);
  p.hline(0, 55, 0, 'grey', 0.62);
  p.box(0, 13, 56, 2, 'grey', 0.36);
  p.hline(0, 55, 13, 'grey', 0.58);
  /* sweets: narrow bright packets stood on end in rows */
  const rng = makeRng(637);
  const SWEET = ['red', 'yellow', 'blue', 'green', 'purple', 'rust'];
  for (let x = 1; x < 55; x += 4) {
    const k = SWEET[Math.floor(rng() * SWEET.length)];
    const t = 0.34 + rng() * 0.32;
    p.box(x, 2, 3, 11, k, t);
    p.vline(x, 2, 12, k, Math.min(1, t + 0.22));      // lit left edge
    p.vline(x + 2, 2, 12, k, Math.max(0, t - 0.18));
    p.hline(x, x + 2, 2, 'bone', 0.5);                // the top of the packet
    if (rng() < 0.5) p.hline(x, x + 2, 6 + Math.floor(rng() * 4), 'bone', 0.72);
  }
  /* magazines: wider, with a masthead band across the top and a block of
     cover under it */
  for (let x = 0; x < 56; x += 14) {
    const k = SWEET[Math.floor(rng() * SWEET.length)];
    p.box(x + 1, 15, 12, 13, k, 0.26 + rng() * 0.3);
    p.box(x + 1, 15, 12, 3, 'bone', 0.80);            // the masthead
    p.box(x + 3, 20, 8, 5, 'bone', 0.40 + rng() * 0.3);
    p.hline(x + 2, x + 10, 26, 'bone', 0.62);
    p.vline(x, 15, 27, 'grey', 0.08);                 // the gap to the next
  }
  p.grime(0.35, 'grey', 0.1, 638);
  return p.snap(0.5);
};


/* =====================================================================
   THE SHOPPING

   Somebody's groceries, going down a belt. Five textures and nine box
   sizes between them, which is what a pile has to be built out of: a
   pile of ONE thing repeated is a pallet, and the eye reads a pallet
   instantly.

   EACH OF THESE IS DECLARED AT THE SIZE OF THE FACE IT GOES ON, not at
   a tiling size, and that is the whole difference between packaging and
   wallpaper. The nearest box to where the player spawns is forty units
   away and fills a good part of the screen; a pattern that tiles twice
   across a cereal box is a cereal box nobody ever printed. So a carton
   front is one repeat of a carton front, and the narrow side of the
   same box shows the left two thirds of it — which is the one artefact
   here, and which reads as printed board rather than as a mistake.
   ===================================================================== */

T.GROCBOX = () => {
  /* A tall carton: the cereal-shaped one. 22 by 34, its own front. */
  const p = new Pix(22, 34, 640);
  p.fill('red', 0.30);
  const n = fbm(22, 34, 6, 2, 640);
  for (let y = 0; y < 34; y++) for (let x = 0; x < 22; x++)
    p.wash(x, y, 'red', 0.46, n[y * 22 + x] * 0.3);
  /* the band across the top with the name on it */
  p.box(0, 2, 22, 8, 'yellow', 0.62);
  p.hline(0, 21, 2, 'yellow', 0.86);
  p.hline(0, 21, 9, 'rust', 0.34);
  p.box(2, 4, 18, 2, 'red', 0.24);
  p.box(4, 7, 11, 1, 'red', 0.20);
  /* the window: a picture of the thing inside, which on a carton is
     always a bowl of it lit from the left */
  p.box(3, 13, 16, 13, 'bone', 0.74);
  p.frame(3, 13, 16, 13, 'bone', 0.92);
  p.disc(11, 20, 5.4, 'olive', 0.54);
  p.disc(9, 18, 3.2, 'yellow', 0.66);
  speckle(22, 34, 40, 641, (x, y, a, b) => {
    if (y > 14 && y < 26 && x > 4 && x < 18) p.ink(x, y, a < 0.5 ? 'yellow' : 'rust', 0.4 + b * 0.4);
  });
  /* the flash in the corner and the barcode at the foot */
  p.disc(18, 12, 3, 'green', 0.56);
  p.box(2, 29, 13, 4, 'bone', 0.86);
  for (let x = 3; x < 15; x += 2) p.vline(x, 29, 32, 'grey', 0.08);
  p.bevel(0, 0, 22, 34, 'bone', 0.28, 'grey', 0.14);
  return p.snap(0.45);
};

T.GROCBOX2 = () => {
  /* A squat carton, 26 by 22, and a different printer: blue ground,
     white panel, a green flash. Nothing it shares with GROCBOX except
     the light, which comes from the same corner as everything else. */
  const p = new Pix(26, 22, 643);
  p.fill('blue', 0.30);
  const n = fbm(26, 22, 6, 2, 643);
  for (let y = 0; y < 22; y++) for (let x = 0; x < 26; x++)
    p.wash(x, y, 'blue', 0.48, n[y * 26 + x] * 0.32);
  p.box(1, 1, 24, 7, 'bone', 0.86);
  p.hline(1, 24, 1, 'bone', 0.96);
  p.box(3, 3, 20, 2, 'blue', 0.26);
  p.box(3, 6, 13, 1, 'blue', 0.34);
  p.box(2, 10, 12, 9, 'green', 0.44);
  p.frame(2, 10, 12, 9, 'green', 0.66);
  p.disc(8, 14, 3, 'yellow', 0.66);
  p.box(16, 10, 8, 5, 'red', 0.50);
  p.hline(16, 23, 10, 'red', 0.70);
  p.box(16, 17, 8, 3, 'bone', 0.80);
  for (let x = 17; x < 24; x += 2) p.vline(x, 17, 19, 'grey', 0.08);
  p.bevel(0, 0, 26, 22, 'bone', 0.30, 'grey', 0.14);
  return p.snap(0.45);
};

T.GROCCAN = () => {
  /* A shrink-wrapped tray of tins, and the one texture here that is
     right on ALL SIX FACES: a multipack seen from the side is a row of
     tin ends and seen from above is a row of tin ends. Which is the
     only reason a box can wear one picture everywhere and get away with
     it. 20 by 16. */
  const p = new Pix(20, 16, 645);
  p.fill('grey', 0.16);
  const LABEL = ['red', 'red', 'green', 'blue', 'red', 'olive'];
  for (let r = 0; r < 2; r++) for (let c = 0; c < 3; c++) {
    const cx = 3.5 + c * 6.5, cy = 4 + r * 8;
    p.disc(cx, cy, 3.2, 'grey', 0.66);            // the bright rolled rim
    p.disc(cx, cy, 2.3, 'grey', 0.30);            // the recess inside it
    p.disc(cx, cy, 1.7, LABEL[r * 3 + c], 0.46);  // the label over the end
    p.ink(Math.round(cx - 1), Math.round(cy - 1), 'grey', 0.86);
    p.ink(Math.round(cx + 2), Math.round(cy + 2), 'grey', 0.10);
  }
  /* the plastic over it: a raked highlight and a seam */
  for (let y = 0; y < 16; y++) for (let x = 0; x < 20; x++)
    if ((x + y * 2) % 17 < 2) p.wash(x, y, 'bone', 0.88, 0.22);
  p.vline(10, 0, 15, 'bone', 0.66, 255);
  p.frame(0, 0, 20, 16, 'grey', 0.28);
  return p.snap(0.45);
};

T.GROCBAG = () => {
  /* A bag: crisps, bread, or what the bagging deck is covered in. 24 by
     20. What makes a bag a bag is that the highlights are CREASES —
     short, bright, at every angle — and not a gradient. */
  const p = new Pix(24, 20, 647);
  p.fill('yellow', 0.40);
  const n = fbm(24, 20, 5, 3, 647);
  for (let y = 0; y < 20; y++) for (let x = 0; x < 24; x++)
    p.ink(x, y, 'yellow', 0.36 + n[y * 24 + x] * 0.24);
  const rng = makeRng(648);
  for (let i = 0; i < 26; i++) {
    const x = Math.floor(rng() * 24), y = Math.floor(rng() * 20);
    const dx = rng() < 0.5 ? 1 : -1, len = 2 + Math.floor(rng() * 4);
    for (let d = 0; d < len; d++) p.wash(x + d * dx, y + (rng() < 0.4 ? 1 : 0), 'bone', 0.86, 0.34);
  }
  /* the printed panel and the seal at the top */
  p.box(3, 6, 18, 8, 'red', 0.42);
  p.hline(3, 20, 6, 'red', 0.62);
  p.box(5, 8, 14, 3, 'bone', 0.84);
  p.box(6, 12, 9, 1, 'blue', 0.60);
  p.box(0, 0, 24, 3, 'red', 0.24);
  for (let x = 0; x < 24; x += 2) p.vline(x, 0, 2, 'red', 0.46);
  p.hline(0, 23, 19, 'grey', 0.12);
  return p.snap(0.45);
};

T.GROCTOP = () => {
  /* The lid of a carton: two flaps, the tape down the seam, a corner
     scuffed. 24 by 16. Nothing on a box top is printed the right way
     up, which is why this is board and tape and not a repeat of the
     front. */
  const p = new Pix(24, 16, 650);
  const n = fbm(24, 16, 6, 2, 650);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 24; x++)
    p.ink(x, y, 'brown', 0.40 + n[y * 24 + x] * 0.14);
  /* the flaps meeting down the middle, the near one lit */
  p.hline(0, 23, 7, 'brown', 0.22);
  p.hline(0, 23, 8, 'brown', 0.62);
  /* the tape: paler, glossy, over-run at both ends */
  p.box(0, 6, 24, 4, 'bone', 0.60);
  p.hline(0, 23, 6, 'bone', 0.82);
  p.hline(0, 23, 9, 'grey', 0.26);
  for (let x = 0; x < 24; x += 3) p.wash(x, 7, 'bone', 0.92, 0.3);
  /* the print that ends up on the top of a carton */
  p.box(3, 1, 9, 3, 'grey', 0.26);
  p.box(15, 12, 7, 2, 'grey', 0.22);
  p.grime(0.4, 'grey', 0.1, 651);
  return p.snap(0.45);
};

T.TROLLEY = () => {
  /* A nested rank of trolleys, as a wall. Reads as a mess of wire. */
  const p = new Pix(64, 48, 87);
  p.clear();
  for (let x = 0; x < 64; x += 4) p.vline(x, 6, 40, 'grey', 0.5);
  for (let y = 8; y < 40; y += 6) p.hline(0, 63, y, 'grey', 0.44);
  for (let x = 0; x < 64; x += 16) { p.vline(x, 0, 47, 'grey', 0.62); p.vline(x + 1, 0, 47, 'grey', 0.3); }
  p.hline(0, 63, 6, 'grey', 0.66);
  p.hline(0, 63, 41, 'grey', 0.24);
  return p.snap(0.4);
};

/* ---------- back of house ---------- */

T.STOCKFLR = () => {
  const p = new Pix(64, 64, 91);
  aggregate(p, 91, { baseKey: 'grey', baseLo: 0.20, baseHi: 0.30,
    grades: [{ count: 160, min: 0.4, max: 1.0, key: 'grey', lo: 0.14, hi: 0.34 }] });
  /* the yellow racking lines everybody ignores */
  for (const ly of [0, 1]) p.hline(0, 63, ly, 'yellow', 0.5 - ly * 0.15);
  crack(p, 8, 40, 44, 'grey', 0.1, 33);
  p.grime(0.5, 'rust', 0.18, 23);
  const rng = makeRng(92);
  for (let i = 0; i < 4; i++) {                    // forklift tyre marks
    const y = Math.floor(rng() * 64);
    for (let x = 0; x < 64; x++) if (rng() < 0.7) p.wash(x, y, 'grey', 0.08, 0.5);
  }
  return p.snap(0.5);
};

T.DOCKDOOR = () => {
  /* Roller shutter: galvanised lath, not timber. Steel first, rust
     second — the earlier version drew the whole thing out of the rust
     ramp and came out looking like decking. */
  const p = new Pix(64, 64, 93);
  const height = new Float32Array(64 * 64);
  const n = fbm(64, 64, 12, 2, 94);
  for (let y = 0; y < 64; y++) {
    const s2 = y % 8;
    /* one lath: shadowed roll at the top, lit crown, falling away below */
    const t = s2 === 0 ? 0.10 : s2 === 1 ? 0.44 : s2 === 2 ? 0.38 : s2 < 6 ? 0.30 : 0.18;
    const hgt = s2 === 0 ? 0.05 : s2 <= 2 ? 0.9 : s2 < 6 ? 0.6 : 0.25;
    for (let x = 0; x < 64; x++) {
      p.ink(x, y, 'grey', t + n[y * 64 + x] * 0.06);
      height[y * 64 + x] = hgt;
    }
  }
  p.emboss(height, 0.30, 1.0);
  /* Rust, where water sat: along the lath rolls and up from the bottom */
  const r = fbm(64, 64, 6, 3, 95);
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 64; x++) {
      const seam = (y % 8) <= 1 ? 1.4 : 0.6;
      const low = 0.35 + Math.pow(y / 63, 2) * 0.9;
      const v = r[y * 64 + x] * seam * low;
      if (v > 0.62) p.wash(x, y, 'rust', 0.30 + (v - 0.62) * 0.7, Math.min(0.85, (v - 0.62) * 2.4));
    }
  }
  /* the guide channels down both edges */
  for (const gx of [0, 1, 62, 63]) {
    for (let y = 0; y < 64; y++) p.ink(gx, y, 'grey', gx === 0 || gx === 62 ? 0.44 : 0.16);
  }
  p.grime(0.5, 'grey', 0.08, 24);
  return p.snap(0.5);
};

/* --- THE STAFF DOOR, AND WHAT IS ROUND IT ---------------------------
   ONE LEAF OF THE PAIR at the back of the shop floor, and like the
   sliders and the fire exit it is a LEAF and not a wall: js/slidedoor.js
   maps it 0..1 in both directions, so the kick plate is at the bottom of
   the door instead of wherever a sixty-four-unit repeat happens to land.

   WHICH IS THE WHOLE STORY OF THIS TEXTURE. It used to be a wall. The
   staff door was the last rising-ceiling door left in the building, and
   a shut Doom door is a sector whose ceiling has come down onto its
   floor — so the disagreement rule drew its face from the floor up to
   whatever the ROOM's ceiling was: three hundred and forty units on the
   shop side, four hundred and four on the stock side. At sixty-four to
   the repeat that is a black slab five storeys high with ten STAFF ONLY
   signs tiled up it, every one of them cut through the word by a seam.
   Nothing was wrong with the picture. It was on the wrong kind of
   surface, and the fix was to stop it being a surface.

   u = 0 IS THE HINGE, which is why there is one texture here and not
   two. The second leaf hangs off the other jamb turned through half a
   circle, so its u runs the other way in the world: the outer stiles
   land at the jambs, the two meeting stiles come together in the middle,
   and the pair is mirrored for free. SLIDEL and SLIDER had to be drawn
   twice only because a pair of sliders both travel the same way.

   AND THERE IS NO WORD ON IT. The sign is a sign — DOORSIGN, a plate
   over the head on the public side, which is where a real one is screwed
   and the only place it reads the right way round. A leaf is
   double-sided: lettering on one is backwards from the stockroom. */
T.DOORSTAF = () => {
  const p = new Pix(64, 64, 95, false);            // no wrap: a sprite, not a tile
  const n = fbm(64, 64, 10, 2, 95);
  /* the leaf: a grey-white impact panel, grubbier towards the meeting
     stile because that is the half everybody's shoulder goes through */
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.50 + (1 - x / 64) * 0.06 + n[y * 64 + x] * 0.06 - (y / 64) * 0.05);
  /* the pressed rib round the panel, and the two stiles. The HINGE side
     is the edge that does not move and the one the aisle light catches;
     the MEETING stile is what the other leaf closes onto, so it is dark
     and it is the first thing on the door to go. */
  p.frame(3, 3, 58, 58, 'bone', 0.58);
  p.frame(4, 4, 56, 56, 'bone', 0.32);
  for (let y = 0; y < 64; y++) {
    p.ink(0, y, 'grey', 0.30); p.ink(1, y, 'bone', 0.50); p.ink(2, y, 'bone', 0.42);
    p.ink(63, y, 'grey', 0.12); p.ink(62, y, 'grey', 0.20); p.ink(61, y, 'bone', 0.30);
  }
  for (let x = 0; x < 64; x++) { p.ink(x, 0, 'bone', 0.64); p.ink(x, 63, 'grey', 0.16); }
  /* three butt hinges down the stile it turns on */
  for (const hy of [8, 32, 56]) {
    p.box(0, hy - 5, 5, 11, 'grey', 0.38);
    p.box(1, hy - 5, 3, 11, 'grey', 0.66);          // the knuckle
    p.vline(1, hy - 5, hy + 5, 'bone', 0.80);
    p.ink(4, hy - 5, 'grey', 0.16); p.ink(4, hy + 5, 'grey', 0.16);
  }
  /* THE VISION PANEL, which is what makes this a back-room door and not
     a cupboard: nobody shoves a door with a cage behind it without
     looking first. Wired glass, and a raked gloss on it — the same
     artificial diagonal the shopfront's panes wear, for the same reason:
     a flat dark rectangle reads as a hole and a raked one reads as
     glass. */
  const VX = 17, VY = 10, VW = 30, VH = 22;
  for (let y = VY; y < VY + VH; y++) for (let x = VX; x < VX + VW; x++) {
    const d = ((x - VX) / VW + (VY + VH - y) / VH) * 0.5;
    const g = (d > 0.33 && d < 0.44) || (d > 0.52 && d < 0.56);
    p.ink(x, y, g ? 'grey' : 'blue', g ? 0.54 : 0.13 + n[y * 64 + x] * 0.06);
  }
  for (let y = VY; y < VY + VH; y++) for (let x = VX; x < VX + VW; x++)
    if ((x - VX) % 4 === 0 || (y - VY) % 4 === 0) p.wash(x, y, 'grey', 0.40, 0.30);  // the wire in it
  p.frame(VX - 2, VY - 2, VW + 4, VH + 4, 'grey', 0.52);
  p.frame(VX - 1, VY - 1, VW + 2, VH + 2, 'grey', 0.14);
  /* the push plate: upright, on the shoulder side, because that is the
     shape of the thing and because a horizontal one reads as a letterbox */
  p.box(45, 26, 13, 17, 'grey', 0.52);
  p.bevel(45, 26, 13, 17, 'bone', 0.72, 'grey', 0.18);
  for (let i = 0; i < 26; i++) p.wash(46 + ((i * 7) % 11), 27 + ((i * 5) % 15), 'grey', 0.34, 0.40);
  /* THE KICK PLATE, and it stands higher than a kick plate does anywhere
     else in this building, because what hits this door is not a foot: it
     is the corner of a roll cage, at that height, twenty times a night.
     Stainless, brushed, and dented along its top edge where they land. */
  for (let y = 46; y < 63; y++) for (let x = 3; x < 61; x++)
    p.ink(x, y, 'grey', 0.56 + n[y * 64 + x] * 0.10 - (y - 46) * 0.006);
  p.hline(3, 60, 46, 'bone', 0.72); p.hline(3, 60, 47, 'grey', 0.28);
  for (const sx of [7, 21, 34, 48, 58]) { p.ink(sx, 46, 'grey', 0.20); p.ink(sx, 47, 'grey', 0.16); }
  for (let i = 0; i < 90; i++)                                   // brushed, not polished
    p.wash(3 + ((i * 29) % 58), 48 + ((i * 11) % 15), 'grey', 0.40, 0.30);
  /* and what a cage does to the rail above it */
  for (let i = 0; i < 70; i++) p.wash(4 + ((i * 37 + 11) % 56), 39 + ((i * 13) % 7), 'grey', 0.16, 0.55);
  p.grime(0.42, 'grey', 0.08, 25);
  return p.snap(0.35);
};

/* The frame it swings in, and the lining of the reveal it swings in the
   middle of. Pressed steel, painted once and touched up never.

   FEATURELESS ON PURPOSE, the same bargain SHOPFRAM makes: this lines a
   sixteen-unit return, caps a head and runs down two jambs, so it is
   asked to tile in every orientation at every partial repeat. Anything
   with a direction in it — a fluted face, a highlight down one arris —
   shows the seam the moment the same texture turns a corner. What it
   gets instead of shape is WEAR, which has no direction: the paint off
   it where the cages go through, primer under that, rust under the
   primer. */
T.DOORFRAM = () => {
  const p = new Pix(64, 64, 97);
  const n = fbm(64, 64, 6, 3, 97);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.38 + n[y * 64 + x] * 0.05);
  speckle(64, 64, 170, 971, (x, y, r) => p.wash(x, y, 'grey', r < 0.5 ? 0.38 : 0.20, 0.30));
  /* chipped through to primer, and here and there through the primer */
  speckle(64, 64, 15, 977, (x, y, r, q) => {
    const w = 1 + Math.floor(r * 2), h = 1 + Math.floor(q * 2);
    p.box(x, y, w, h, 'bone', 0.26);
    if (r > 0.72) p.ink(x, y, 'rust', 0.30);
  });
  p.grime(0.34, 'grey', 0.07, 97);
  return p.snap(0.4);
};

/* What is over the head, and it belongs to the DOORSET rather than to
   either room — which is the only answer a sector engine leaves open.
   A band is drawn ONCE for both of its faces, so whatever goes here is
   seen from the shop floor AND from the stockroom, and those two walls
   are a panelled olive board and bare brick. Put the shop's own wall up
   there and the stockroom gets an olive patch over its door; put the
   stockroom's up there and the shop gets a patch of brick. Put the DOOR
   up there — a transom panel in the same painted steel as the frame —
   and it is right from both sides, because that is a real thing that
   really goes over a door of this kind.

   It also settles an alignment the band could not win. A band starts its
   u at its own first vertex, so WALLPANL over the head landed a quarter
   of a repeat out of phase with the WALLPANL either side of it, and a
   hundred and twenty-eight units of slightly-wrong wall reads as a
   mistake from ten feet away. A panel that is not trying to be the wall
   has nothing to be out of phase with.

   RIBS ON THE EDGES, which is what makes it tile: the upright lands on
   u=0 and the rail on v=0, so at sixty-four to the repeat they fall on
   the two jambs and the centre line of the opening, and on the head and
   every sixty-four units above it. Nothing in the middle of the panel
   has a direction, so a partial repeat at the ceiling is just a panel
   that runs into the deck. */
T.DOORHEAD = () => {
  const p = new Pix(64, 64, 99);
  const n = fbm(64, 64, 8, 3, 99);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.40 + n[y * 64 + x] * 0.05 + ((x * 7) % 3 === 0 ? 0.012 : 0));
  /* the upright and the rail, each with the light on the top-left arris
     and the shadow on the other, which is the whole of the relief */
  for (let y = 0; y < 64; y++) {
    p.ink(0, y, 'grey', 0.54); p.ink(1, y, 'grey', 0.47);
    p.ink(2, y, 'grey', 0.26); p.ink(3, y, 'grey', 0.34);
  }
  for (let x = 0; x < 64; x++) {
    p.ink(x, 0, 'grey', 0.56); p.ink(x, 1, 'grey', 0.48);
    p.ink(x, 2, 'grey', 0.25); p.ink(x, 3, 'grey', 0.33);
  }
  speckle(64, 64, 120, 991, (x, y, r) => p.wash(x, y, 'grey', r < 0.5 ? 0.40 : 0.22, 0.26));
  speckle(64, 64, 9, 997, (x, y, r) => { p.ink(x, y, 'bone', 0.26); if (r > 0.7) p.ink(x, y, 'rust', 0.28); });
  streaks(p, 3, 993, 'grey', 0.12, 0.22);
  return p.snap(0.4);
};

/* The plate over the door, and the only place in this building where the
   words STAFF ONLY are written down.

   A WORD IS A SHAPE YOU CAN COUNT — the note on the fire exit is about
   exactly this — so it may only go somewhere that never repeats. A sign
   is precisely that: one repeat, eighty by forty, on a free box screwed
   to the wall over the head, on the public side, at the height a sign
   goes. The two leaves under it say nothing at all. */
T.DOORSIGN = () => {
  const p = new Pix(64, 32, 98);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.82);
  p.frame(0, 0, 64, 32, 'grey', 0.26);
  p.frame(2, 2, 60, 28, 'red', 0.32);
  drawTextCentred(p, 'STAFF', 32, 7, 'red', 0.30);
  drawTextCentred(p, 'ONLY', 32, 18, 'red', 0.30);
  for (const sx of [6, 57]) { p.disc(sx, 16, 1.2, 'grey', 0.30); p.ink(sx, 15, 'bone', 0.92); }
  p.grime(0.30, 'grey', 0.07, 98);
  return p.snap(0.35);
};

T.DOORTRAK = () => {
  /* What you see above a door: the track it hangs from. 64x16. */
  const p = new Pix(64, 16, 96);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', y < 3 ? 0.16 : y < 6 ? 0.38 : 0.24);
  p.hline(0, 63, 3, 'grey', 0.54);
  p.hline(0, 63, 15, 'grey', 0.08);
  for (let x = 4; x < 64; x += 16) { p.vline(x, 4, 14, 'grey', 0.44); p.vline(x + 1, 4, 14, 'grey', 0.14); }
  p.grime(0.4, 'grey', 0.08, 26);
  return p.snap(0.4);
};

T.CARDBOX = () => {
  /* A stack of cases. The most flammable wall in the building, and it
     looks it. */
  const p = new Pix(64, 64, 97);
  const rng = makeRng(97);
  for (let row = 0; row < 3; row++) {
    const top = row * 22 - 2;
    let x = -Math.floor(rng() * 10);
    while (x < 64) {
      const w = 16 + Math.floor(rng() * 12);
      const t = 0.38 + rng() * 0.16;
      for (let y = top; y < top + 22 && y < 64 + 22; y++)
        for (let xx = 0; xx < w; xx++) p.ink(x + xx, y, 'brown', t);
      p.hline(x, x + w - 1, top, 'brown', Math.min(1, t + 0.22));
      p.vline(x, top, top + 21, 'brown', Math.min(1, t + 0.14));
      p.vline(x + w - 1, top, top + 21, 'brown', Math.max(0, t - 0.2));
      p.hline(x, x + w - 1, top + 21, 'brown', Math.max(0, t - 0.24));
      /* tape down the middle, and a printed panel */
      p.vline(x + (w >> 1), top, top + 21, 'bone', 0.7);
      for (let k = 0; k < 3; k++) p.hline(x + 3, x + w - 4, top + 6 + k * 4, 'brown', Math.max(0, t - 0.16));
      x += w;
    }
  }
  p.grime(0.4, 'grey', 0.12, 27);
  return p.snap(0.5);
};

T.PALLET = () => {
  const p = new Pix(64, 16, 98);
  p.clear();
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.30);
  p.hline(0, 63, 0, 'brown', 0.52);
  p.hline(0, 63, 15, 'brown', 0.12);
  for (const bx of [4, 30, 56]) for (let y = 3; y < 13; y++) for (let x = 0; x < 6; x++) p.ink(bx + x, y, 'brown', 0.22);
  for (let y = 4; y < 12; y++) for (let x = 0; x < 64; x++)
    if (!((x >= 4 && x < 10) || (x >= 30 && x < 36) || (x >= 56 && x < 62))) p.set(x, y, 0, 0, 0, 0);
  return p.snap(0.4);
};

/* ---------- lights, signs, and the thing that says GO THIS WAY ---------- */

T.LIGHTPAN = () => {
  /* A recessed fluorescent panel. Fullbright in the ceiling. */
  const p = new Pix(64, 64, 101);
  p.fill('grey', 0.3);
  for (let y = 6; y < 58; y++) for (let x = 6; x < 58; x++) p.ink(x, y, 'bone', 0.95);
  for (const gx of [22, 42]) p.vline(gx, 6, 57, 'grey', 0.4);
  p.frame(5, 5, 54, 54, 'grey', 0.5);
  p.frame(6, 6, 52, 52, 'bone', 0.7);
  return p.snap(0.3);
};

/* The box over a fire exit, on the inside, and the one place in this
   building besides the staff door's plate where a word is written down.

   IT IS A LIGHT AND NOT A NOTICE, which is what the old one got wrong:
   it was a dark green field with darker green lettering on it, so at the
   0.26 of a cross-aisle at night it was a black rectangle over a black
   door, and it had never been hung anywhere to find that out. An
   illuminated exit sign is the brightest small thing in a shop — that is
   the entire point of one, it has a battery in it for the night the
   power goes — so the face is bright and the letters are white, and the
   prop that carries it is lit past one. */
T.EXITSIGN = () => {
  const p = new Pix(64, 32, 102);
  p.fill('grey', 0.16);                       // the housing
  p.frame(1, 1, 62, 30, 'grey', 0.34);
  for (let y = 3; y < 29; y++) for (let x = 3; x < 61; x++) p.ink(x, y, 'green', 0.74);
  /* the diffuser is brighter in the middle, where the tube is */
  for (let y = 8; y < 24; y++) for (let x = 5; x < 59; x++) p.ink(x, y, 'green', 0.86);
  p.frame(3, 3, 58, 26, 'green', 0.52);
  /* the running man, on the left, the same figure that is on the leaf */
  const gx = 14, gy = 16;
  p.disc(gx - 1, gy - 7, 1.8, 'bone', 0.98);
  p.line(gx - 2, gy - 5, gx + 1, gy, 'bone', 0.98);
  p.line(gx + 1, gy, gx + 5, gy + 6, 'bone', 0.98);
  p.line(gx + 1, gy, gx - 4, gy + 6, 'bone', 0.98);
  p.line(gx - 2, gy - 4, gx + 4, gy - 6, 'bone', 0.96);
  /* and the word, doubled a pixel over so that it holds at a distance */
  drawTextCentred(p, 'EXIT', 40, 13, 'bone', 0.98, 3);
  drawTextCentred(p, 'EXIT', 40, 14, 'bone', 0.98, 3);
  return p.snap(0.2);
};

/* --------------------------------------------------------------------
   THE STRIP

   SellWrong is the anchor of a parade, and a parade is a single long
   building carved into tenancies. Everything below is that carving:
   the piers that separate one shop from the next, the fascia band each
   tenant gets to put a name on, the parapet that hides the plant, and
   the glazing — which comes in three states, because the three states
   ARE the story of the place. Trading, gone, and never let.
   ------------------------------------------------------------------ */

/* --------------------------------------------------------------------
   THE LOGO

   The one piece of art in this game that is not drawn by code, because a
   procedural approximation of somebody's logo is not their logo. It
   arrives as run-length pairs of palette indices — see
   tools/bake-logo.mjs, which is the build step, run by hand, when the
   logo changes — and it is already in the game's 256 colours, so there
   is nothing to snap and nothing to dither.

   Sixty-four pixels is the rule and the logo does not get an exemption.
   It gets GEOMETRY instead: four tiles hung as a two-by-two on the
   entrance tower, which is two ceiling steps and one vertical split. A
   sector engine cannot draw a big picture; it can draw four small ones
   next to each other, which is the same thing and is how every large
   sign in Doom was done.
   ------------------------------------------------------------------ */
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const B64R = (() => { const r = new Int16Array(128).fill(-1);
  for (let i = 0; i < 64; i++) r[B64.charCodeAt(i)] = i; return r; })();

/** Base64 run-length pairs back to 64x64 palette indices. */
function decodeTile(str) {
  const bytes = [];
  let acc = 0, bits = 0;
  for (let i = 0; i < str.length; i++) {
    const v = B64R[str.charCodeAt(i)];
    if (v < 0) continue;                       // padding
    acc = (acc << 6) | v; bits += 6;
    if (bits >= 8) { bits -= 8; bytes.push((acc >> bits) & 255); }
  }
  const px = new Uint8Array(64 * 64);
  let p = 0;
  for (let i = 0; i + 1 < bytes.length && p < px.length; i += 2)
    for (let n = bytes[i + 1]; n > 0 && p < px.length; n--) px[p++] = bytes[i];
  return px;
}

const logoTile = i => () => {
  const px = decodeTile(LOGO_TILES[i]);
  const p = new Pix(64, 64, 200 + i, false);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const c = PALETTE[px[y * 64 + x]];
    p.set(x, y, c[0], c[1], c[2], 255);
  }
  return p;                                    // already in the palette
};
T.LOGO0 = logoTile(0);   // top left
T.LOGO1 = logoTile(1);   // top right
T.LOGO2 = logoTile(2);   // bottom left
T.LOGO3 = logoTile(3);   // bottom right

T.NIGHTSKY = () => {
  /* The sky, wrapped round a cylinder. Doom's sky was a cylinder too, and
     for the same reason: it is the only projection that costs nothing and
     the only one where turning your head does the right thing.

     Read bottom to top, because that is the order the light arrives in.
     The bottom band is SODIUM — the town's street lighting bounced off
     the underside of the cloud, which is why a city sky at night is
     orange and not black, and which is the single thing that makes the
     car park read as somewhere rather than as an absence. Above it the
     glow loses out to the cloud, and only at the top is there anything
     you could call night. */
  const p = new Pix(64, 64, 120);
  for (let y = 0; y < 64; y++) {
    const t = y / 63;                       // 0 at the top, 1 at the horizon
    for (let x = 0; x < 64; x++) {
      const glow = Math.pow(t, 2.6);
      p.ink(x, y, glow > 0.30 ? 'rust' : 'blue', 0.34 + glow * 0.52);
    }
  }
  /* cloud, lit from underneath by the town */
  const n = fbm(64, 64, 16, 4, 121);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const v = n[y * 64 + x], t = y / 63;
    if (v < 0.52) continue;
    const lit = (v - 0.52) * 1.6 * (0.25 + t * 0.9);
    p.wash(x, y, t > 0.62 ? 'rust' : 'grey', 0.46 + lit * 0.6, Math.min(0.85, lit * 1.6));
  }
  /* the few stars that make it through */
  const rng = makeRng(122);
  for (let i = 0; i < 40; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 30);
    if (n[y * 64 + x] > 0.5) continue;
    p.ink(x, y, 'bone', 0.30 + rng() * 0.45);
  }
  return p.snap(0.35);
};

T.HATCHKEEP = () => {
  /* KEEP CLEAR. The hatched apron across the front of every supermarket,
     which exists so the fire brigade can get to the doors — a detail
     that has become funny in this particular car park. */
  const p = T.ASPHALT();
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const d = (x + y) % 22;
    if (d > 4) continue;
    const t = d === 0 || d === 4 ? 0.42 : 0.74;
    if (((x * 7 + y * 13) % 11) < 2) continue;       // worn through
    p.ink(x, y, 'bone', t);
  }
  return p.snap(0.5);
};

T.ROADTAR = () => {
  /* The road's own surface: the lot's asphalt, but the lot is floodlit
     and the road is not, so it is a shade darker — which is also what
     lets it read as a band across the far end of the lot from the
     verge, where its lines are too thin to see. */
  const p = T.ASPHALT();
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.wash(x, y, 'grey', 0.30, 0.42);
  return p.snap(0.5);
};

T.ROADLINE = () => {
  /* The centre line of the road: a dash of yellow, 40 on and 24 off.
     The dash runs the FULL height of the tile, because the strip it is
     laid on is six units wide and shows only six of these rows —
     whichever six, they have to carry the line. */
  const p = T.ASPHALT();
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    if (x >= 40) continue;
    if (((x * 5 + y * 3) % 13) < 2) continue;              // worn through
    p.ink(x, y, 'yellow', 0.60 + ((x + y) & 1) * 0.08);
  }
  return p.snap(0.5);
};

T.ROADLINV = () => {
  /* THE SAME LINE, TURNED. A flat is textured to the WORLD grid — u is
     x/64 and v is y/64, always — so a texture whose dash runs along x
     draws one continuous stripe down a road that runs along y, which is
     a solid centre line and means something else entirely. The perimeter
     road has two legs running north-south, so there is a second dash.

     Forty on and twenty-four off, the same as its neighbour, because
     they meet at the corners and a dash that changes length halfway
     round a lot reads as two roads. */
  const p = T.ASPHALT();
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    if (y >= 40) continue;
    if (((y * 5 + x * 3) % 13) < 2) continue;              // worn through
    p.ink(x, y, 'yellow', 0.60 + ((x + y) & 1) * 0.08);
  }
  return p.snap(0.5);
};

T.ROADGIVE = () => {
  /* THE LINE YOU STOP AT. Where a leg of the perimeter road meets the
     through road there is a junction, and what makes a junction read as
     one rather than as a wide bit of tarmac is the bar across its mouth.
     Painted as blocks with gaps — a give way rather than a stop, because
     nothing here is signalled — running along x, since every mouth in
     this map is a leg arriving from the north or the south. */
  const p = T.ASPHALT();
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    if ((x % 16) >= 11) continue;
    if (((x * 7 + y * 11) % 19) < 2) continue;
    p.ink(x, y, 'bone', 0.66 + ((x + y) & 1) * 0.06);
  }
  return p.snap(0.5);
};

T.ROADEDGE = () => {
  /* The white line along each edge, same idea: line all the way through. */
  const p = T.ASPHALT();
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    if (((x * 7 + y * 11) % 17) < 3) continue;
    p.ink(x, y, 'bone', 0.64 + ((x + y) & 1) * 0.06);
  }
  return p.snap(0.5);
};

T.BAYROW = () => {
  /* A car park bay, and ONE REPEAT IS ONE BAY: declared 186 across and
     180 deep, so a row of forty bays is one sector with this on the floor
     instead of forty sectors with a line between them. The whole car park
     costs about a dozen polygons because of this texture, and moving a
     row is changing one number rather than forty.

     The line is on the left edge only, so each bay draws its own and the
     row comes out with a line every 186 either way you tile it. */
  const p = new Pix(64, 64, 126);
  const n = fbm(64, 64, 20, 4, 126);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.52 + n[y * 64 + x] * 0.11);
  const rng = makeRng(127);
  for (let i = 0; i < 700; i++) {                    // the aggregate
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    p.ink(x, y, 'grey', 0.47 + rng() * 0.20);
  }
  /* where the car sits: oil, and tyres that have polished the tarmac */
  for (let y = 14; y < 54; y++) for (let x = 16; x < 52; x++) {
    const d = Math.max(Math.abs(x - 34) / 18, Math.abs(y - 34) / 20);
    if (d < 1) p.ink(x, y, 'grey', 0.45 - (1 - d) * 0.07);
  }
  for (const tx of [24, 44]) for (let y = 20; y < 48; y++)
    if (rng() < 0.7) p.ink(tx + (rng() < 0.5 ? 0 : 1), y, 'grey', 0.40);
  for (let i = 0; i < 26; i++) {                     // sump drips
    const x = 30 + Math.floor(rng() * 9), y = 30 + Math.floor(rng() * 9);
    p.ink(x, y, 'grey', 0.30);
  }
  /* the line: worn, because everything here is */
  for (let y = 0; y < 64; y++) {
    if (rng() < 0.16) continue;
    p.ink(0, y, 'bone', 0.62 + rng() * 0.2);
    p.ink(1, y, 'bone', 0.44 + rng() * 0.2);
  }
  for (let x = 0; x < 8; x++) if (rng() < 0.7) p.ink(x, 0, 'bone', 0.40);
  p.grime(0.35, 'grey', 0.06, 128);
  return p.snap(0.55);
};

T.PILASTER = () => {
  /* The pier between two shops, and since the parade grew pilasters it
     is the whole of one: a free box eight units proud of the wall
     running the full height (see DRESSING THE PARADE in
     js/maps/sellwrong.js), which means this texture is now read from
     four feet away on the footway instead of from a car park.

     WHICH MADE THE BRICK WRONG. It was courses of eight and bricks of
     thirty-two over a sixty-four-unit repeat, so a brick was a metre
     long and a foot tall — fine as a distant stripe, and absurd once
     you can stand next to it. The town's brick is 16 by 6 (brickwork in
     CHIMNEY) and this is the same brick now, so a pier and a chimney
     are made of the same material, which is the only reason a generated
     texture set holds together at all. */
  const p = new Pix(64, 64, 130);
  brickwork(p, 130, 'rust', 0.26, 0.42, 0.40, 6, 16);
  /* the perpend every four courses where a header ties the pier back
     into the wall behind it, which is what makes a pier a pier and not
     a strip of wall with a shadow on it */
  for (let cy = 0; cy < 64; cy += 24)
    for (let x = 24; x < 40; x++) p.wash(x, cy + 2, 'rust', 0.48, 0.30);
  streaks(p, 5, 131, 'grey', 0.20, 0.22);
  p.grime(0.4, 'grey', 0.16, 132);
  return p.snap(0.55);
};

T.PARAPET = () => {
  /* The band above every fascia: the top of a wall that was only ever
     meant to be seen from a car park, and the biggest single surface on
     the building.

     IT TILED FIVE TIMES AND EVERYTHING IN IT GOT COUNTED. Two goes at
     this failed the same way. The first had a COPING painted into it —
     lighter rows with an open joint — and a coping happens once, so the
     roofline read as five cornices stacked up. The second took the
     coping out (it is a real box now, see COPING) and left a control
     joint at the repeat, and what that drew was five courses instead of
     five cornices. The fault was never the ornament. It was the RATIO:
     32 declared on a band of 152.

     So one repeat is the whole band now, 152 tall and 128 across, which
     is a panel joint every four metres across and exactly ONE horizontal
     joint up. Nothing in it repeats vertically because nothing in it
     CAN. The texels come out about two units square, which is soft, and
     soft is right for eighty feet of painted render seen from a car
     park at night. */
  const p = new Pix(64, 64, 133);
  const n = fbm(64, 64, 10, 4, 133);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.44 + n[y * 64 + x] * 0.14);
  /* THE ONE HORIZONTAL JOINT, a third of the way down, where the panel
     above the roof line meets the panel below it. A hairline with the
     shadow under and the light on top, and only the one. */
  p.hline(0, 63, 21, 'grey', 0.56);
  p.hline(0, 63, 22, 'grey', 0.24);
  /* and the vertical joints at the repeat: a panel every four metres */
  p.vline(0, 0, 63, 'grey', 0.26); p.vline(1, 0, 63, 'grey', 0.56);
  /* the blockwork showing through where the paint has gone thin. No
     line you can count — a block here is two texels, which is under
     the size of anything the eye will make a pattern out of. */
  const rng = makeRng(139);
  for (let k = 0; k < 90; k++) {
    const bx = Math.floor(rng() * 16) * 4, by = Math.floor(rng() * 32) * 2;
    for (let y = by; y < by + 2 && y < 64; y++) for (let x = bx; x < bx + 4 && x < 64; x++)
      p.wash(x, y, 'bone', 0.40, 0.08 + rng() * 0.12);
  }
  /* AND THIRTY YEARS OF RAIN, which on a wall this size is the only
     thing giving it any vertical at all — it runs from the coping down
     and it is what a parapet actually looks like from a car park. */
  streaks(p, 14, 134, 'grey', 0.24, 0.6);
  streaks(p, 5, 136, 'olive', 0.22, 0.4);
  p.grime(0.5, 'grey', 0.16, 135);
  return p.snap(0.5);
};

T.SOFFIT = () => {
  /* Under the canopy: perforated metal deck with a downlight in every
     fourth tray. Ceiling flat over the whole footway. */
  const p = new Pix(64, 64, 136);
  p.fill('grey', 0.42);
  for (let x = 0; x < 64; x += 16) {                 // the trays
    for (let y = 0; y < 64; y++) {
      p.ink(x, y, 'grey', 0.26);
      p.ink(x + 1, y, 'grey', 0.52);
      p.ink(x + 15, y, 'grey', 0.28);
    }
  }
  const rng = makeRng(137);                          // the perforations
  for (let i = 0; i < 260; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    if (x % 16 < 3) continue;
    p.ink(x, y, 'grey', 0.24);
  }
  /* one downlight, off-centre so a run of them does not read as a grid */
  p.disc(40, 22, 6, 'grey', 0.54);
  p.disc(40, 22, 5, 'bone', 0.86);
  p.disc(40, 22, 3, 'bone', 0.98);
  p.grime(0.45, 'grey', 0.20, 138);
  return p.snap(0.5);
};

/* --- glazing, in its three states -------------------------------- */

T.UNITGLAS = () => {
  /* An in-line unit's shopfront: smaller panes than the anchor's, a
     stall riser at the bottom, and the lights still on inside. */
  const p = new Pix(64, 64, 140);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const sheen = Math.max(0, 1 - Math.abs((x + y * 0.55) % 30 - 6) / 11);
    p.ink(x, y, 'cyan', 0.13 + sheen * 0.17 + (1 - y / 64) * 0.10);
  }
  /* something is in there, blurred by the glass */
  const rng = makeRng(141);
  for (let i = 0; i < 14; i++) {
    const x = 4 + Math.floor(rng() * 56), h = 6 + Math.floor(rng() * 16);
    for (let y = 46 - h; y < 46; y++) p.ink(x, y, rng() < 0.5 ? 'yellow' : 'bone', 0.22 + rng() * 0.2);
  }
  for (const mx of [0, 21, 42]) { p.vline(mx, 0, 63, 'bone', 0.30); p.vline(mx + 1, 0, 63, 'grey', 0.16); }
  p.hline(0, 63, 6, 'bone', 0.30); p.hline(0, 63, 7, 'grey', 0.16);   // transom
  for (let y = 48; y < 64; y++) for (let x = 0; x < 64; x++)          // stall riser
    p.ink(x, y, 'grey', 0.20 + ((x + y) & 1) * 0.03);
  p.hline(0, 63, 47, 'bone', 0.34);
  p.grime(0.3, 'grey', 0.09, 142);
  return p.snap(0.45);
};

/* --- THE SHOPFRONT, IN LAYERS ---------------------------------------

   A shop window is not a wall with glass painted on it, and drawing it
   that way is what every flat elevation in this project had in common
   with every other one. A shopfront is an ASSEMBLY, and from the
   pavement you can count the parts:

     the FRAME               aluminium, standing proud of the wall
     an INSET                the reveal behind it
     PANE A                  the outer sheet, with the sky on it
     a GAP, outlined black    the cavity between the sheets
     PANE B                  the inner sheet
     an INSET                and the shop behind that

   All six are real. The frame is free boxes; the two insets are sectors
   in the sixteen units of wall thickness; the panes are MIDDLE textures
   hung in the holes between them, so you look THROUGH one, across a
   cavity, through the other and into the store. See THE GLAZING in
   js/maps/sellwrong.js for the geometry — what follows is the paint.

   SEMI-TRANSPARENT MEANS STIPPLED, and that is not a compromise, it is
   the only thing this engine will do. Nothing in this game has partial
   alpha: snapImageData in js/palette.js sets every surviving pixel to
   255 and says "no partial alpha, ever" while it does it, and a wall
   material is alpha-TESTED and never blended. So a half-silvered sheet
   of glass is drawn the way a half-silvered sheet of glass was drawn in
   1996 — an ordered dither of pixels that are there and pixels that are
   not.

   WHICH MEANS THE MIPMAPS ARE THE DESIGN. A fifty-per-cent checker
   averages to fifty per cent one mip level down, and an alpha test at
   0.5 turns that into all or nothing: a pane that vanishes at ten
   metres, or one that goes solid. So the veil is DENSER AT THE EDGES OF
   THE PANE THAN IN THE MIDDLE. Walk away and the mip chain averages it;
   the border firms up into solid glass and the middle opens out. Which
   is the right way round — the pane you can see through is the one you
   are standing at, and from the far side of the car park a shopfront is
   a sheet of reflection anyway.
   ------------------------------------------------------------------ */

/* The 4x4 ordered matrix. The same one the palette snap nudges colour
   with, used here on ALPHA instead: a pixel is there if its threshold
   is under the coverage asked for at that point. Ordered rather than
   random because a random half is a half that crawls. */
const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const stipple = (x, y, cover) => (BAYER4[(y & 3) * 4 + (x & 3)] + 0.5) / 16 < cover;

/** A box blur over the colour only, leaving alpha alone. What is behind
 *  a shop window is out of focus because it is behind a shop window,
 *  and a texture of it drawn sharp reads as a photograph taped to the
 *  glass. Two passes is as much as 64 pixels can take. */
function defocus(p, passes = 2) {
  for (let k = 0; k < passes; k++) {
    const src = new Uint8ClampedArray(p.data);
    for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) {
      let r = 0, g = 0, b = 0, n = 0;
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const i = p.idx(x + dx, y + dy);
        if (i < 0) continue;
        r += src[i]; g += src[i + 1]; b += src[i + 2]; n++;
      }
      const i = p.idx(x, y);
      p.data[i] = r / n; p.data[i + 1] = g / n; p.data[i + 2] = b / n;
    }
  }
}

/**
 * One sheet of glass, drawn as coverage and reflection together.
 *
 *   base   how much of the middle of the pane is there at all
 *   sky    how much more of it is there at the top, where the soffit
 *          and whatever is left of the sky are in it
 *   lo/hi  the reflection, dark at the bottom (a car park at night is
 *          the darkest thing there is) and pale at the top
 *   shift  where the gloss crosses, so two sheets do not agree
 *   gloss  [from, to, coverage, brightness] per band
 */
const pane = (seed, o) => () => {
  const p = new Pix(64, 64, seed);
  const n = fbm(64, 64, 8, 3, seed + 3);
  for (let y = 0; y < 64; y++) {
    const v = y / 63;
    for (let x = 0; x < 64; x++) {
      const u = x / 63, w = n[y * 64 + x];
      /* THE EDGE IS THE PART THAT HAS TO SURVIVE THE MIP CHAIN — see
         the note above. It is also true: a pane is dirtiest and
         brightest where the bead holds it. */
      const edge = Math.max(Math.max(0, 1 - Math.min(u, 1 - u) / 0.085),
                            Math.max(0, 1 - Math.min(v, 1 - v) / 0.055));
      let cover = o.base + edge ** 1.5 * (0.97 - o.base) + (1 - v) * o.sky;
      let key = o.key, t = o.lo + (1 - v) * (o.hi - o.lo);
      /* THE GLOSS, AND IT IS ARTIFICIAL ON PURPOSE. A real reflection in
         a shopfront is the car park, and nobody has ever drawn the car
         park on a window. What everybody draws instead is two hard
         parallel bands raked across it from the top left, which is
         where the light in every texture in this project comes from.
         Rakes exactly one height per width, so it wraps both ways. */
      const d = (u + (1 - v) + o.shift) % 1;
      for (const g of o.gloss) if (d > g[0] && d < g[1]) {
        cover = Math.max(cover, g[2]); key = g[4]; t = g[3];
      }
      cover *= 0.80 + w * 0.40;
      if (cover >= 0.97) { p.ink(x, y, key, t); continue; }
      if (!stipple(x, y, cover)) continue;
      p.ink(x, y, key, t * (0.86 + w * 0.28));
    }
  }
  /* THE BEAD. A black rubber gasket all the way round, and it is what
     turns a rectangle of dither into an OBJECT — without it the pane
     has no edge and the eye reads the whole reveal as one smear. */
  for (let i = 0; i < 64; i++) {
    p.ink(i, 0, 'grey', 0.07); p.ink(i, 1, 'grey', 0.12);
    p.ink(i, 63, 'grey', 0.04); p.ink(i, 62, 'grey', 0.08);
    p.ink(0, i, 'grey', 0.07); p.ink(1, i, 'grey', 0.12);
    p.ink(63, i, 'grey', 0.04); p.ink(62, i, 'grey', 0.08);
  }
  /* and what is ON it: the tide line the rain leaves up the bottom
     third, and the flecks nobody has washed off since the shop opened */
  const rng = makeRng(seed + 17);
  for (let i = 0; i < o.dirt; i++) {
    const x = Math.floor(rng() * 64), y = 40 + Math.floor(rng() * 24);
    p.ink(x, y, 'bone', 0.30 + rng() * 0.22);
    if (rng() < 0.4) p.ink(x, y + 1, 'bone', 0.22);
  }
  for (let i = 0; i < o.runs; i++) {
    const x = Math.floor(rng() * 64), top = 6 + Math.floor(rng() * 34);
    const len = 8 + Math.floor(rng() * 22);
    for (let d = 0; d < len; d++) {
      if (rng() < 0.45) continue;
      p.ink(x, top + d, 'bone', 0.26 + (d / len) * 0.14);
    }
  }
  return p.snap(0.35);
};

/* PANE A — the outer sheet. More of the sky is in it and more of the
   gloss, because it is the one the canopy lights actually reach. */
T.GLAZEA = pane(146, {
  base: 0.30, sky: 0.12, key: 'blue', lo: 0.21, hi: 0.42, shift: 0.10,
  gloss: [[0.30, 0.47, 0.90, 0.60, 'grey'], [0.52, 0.585, 0.88, 0.88, 'grey']],
  dirt: 90, runs: 9,
});
/* PANE B — the inner sheet, thinner and crossed the other way. Two
   sheets whose gloss agreed would read as one sheet with a bright line
   on it; two that disagree read as DEPTH, which is the whole point of
   there being two. */
T.GLAZEB = pane(150, {
  base: 0.18, sky: 0.07, key: 'blue', lo: 0.16, hi: 0.32, shift: 0.55,
  gloss: [[0.24, 0.34, 0.70, 0.42, 'grey'], [0.39, 0.425, 0.66, 0.62, 'grey']],
  dirt: 40, runs: 4,
});

T.GLAZGAP = () => {
  /* THE CAVITY BETWEEN THE SHEETS, which is the black outline. It is
     the jambs, the floor and the ceiling of a sector six units deep, so
     what it actually draws is four slivers seen almost edge-on — and
     four black slivers round a pane of glass is exactly the line a
     window wants and the one a flat texture cannot give it.

     It is not pure black. Pure black in a 256-colour palette is a hole
     in the screen; this is the grey ramp at a twentieth, with a little
     more of it at the top where light gets past the head. */
  const p = new Pix(64, 64, 152);
  const n = fbm(64, 64, 4, 2, 153);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.022 + (1 - y / 64) * 0.046 + n[y * 64 + x] * 0.008);
  /* the dust and the flies that have been in there for years */
  const rng = makeRng(154);
  for (let i = 0; i < 26; i++) {
    const x = Math.floor(rng() * 64), y = 52 + Math.floor(rng() * 12);
    p.ink(x, y, 'grey', 0.10 + rng() * 0.08);
  }
  for (let y = 60; y < 64; y++) for (let x = 0; x < 64; x++)
    p.wash(x, y, 'bone', 0.16, 0.20 * (y - 59) / 4);
  return p.snap(0.25);
};

T.SHOPFRAM = () => {
  /* The section. Every part of a shopfront that is not glass is one
     aluminium extrusion or another — mullion, transom, head, cill — and
     an extrusion is the SAME THING all the way along, which is why one
     texture does all of them and why it tiles honestly in both
     directions at any partial repeat.

     So there is nothing drawn on it that happens once: no cap, no
     screw, no joint. The form comes from the geometry, because every
     piece of this is a free box with six faces and its own light on
     each. Same argument as the shutter curtain in THE SHUT ONES. */
  const p = new Pix(64, 64, 155);
  const n = fbm(64, 64, 16, 3, 156);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.29 + n[y * 64 + x] * 0.07);
  /* brushed anodising: short strokes along the extrusion, fine enough
     that a section cut anywhere still looks like the same metal */
  const rng = makeRng(157);
  for (let i = 0; i < 1100; i++) {
    const x = Math.floor(rng() * 64), y0 = Math.floor(rng() * 64);
    const len = 3 + Math.floor(rng() * 11);
    const t = rng() < 0.5 ? 0.38 : 0.22;
    for (let d = 0; d < len; d++) p.wash(x, y0 + d, 'grey', t, 0.30);
  }
  p.grime(0.34, 'grey', 0.08, 158);
  return p.snap(0.45);
};

T.SHOPSILL = () => {
  /* THE STALL RISER: the panel under the glass, from the pavement up to
     knee height, which on a parade like this is the one surface a
     trolley, a boot and a delivery sack trolley all hit. Drawn at 64 by
     64 and declared 96 by 32, so one repeat is exactly one pane bay of
     it and the nosing lands once at the top rather than four times up.

     The nosing at the top is the cill extrusion and it is the same
     metal as SHOPFRAM; everything under it is a laminate panel that
     stopped being any colour in particular a long time ago. */
  const p = new Pix(64, 64, 159);
  const n = fbm(64, 64, 8, 3, 160);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'olive', 0.33 + n[y * 64 + x] * 0.12 + (1 - y / 64) * 0.07);
  /* the cill, and the shadow it throws down the panel */
  for (let y = 0; y < 5; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', y < 2 ? 0.44 : y < 3 ? 0.34 : 0.16);
  for (let y = 5; y < 10; y++) for (let x = 0; x < 64; x++)
    p.shade(x, y, 0.72 + (y - 5) * 0.055);
  /* the kicks, at the height a trolley axle is */
  const rng = makeRng(161);
  for (let k = 0; k < 50; k++) {
    const x = Math.floor(rng() * 64), y = 26 + Math.floor(rng() * 20);
    const w = 2 + Math.floor(rng() * 7);
    for (let d = 0; d < w; d++) p.wash(x + d, y, 'bone', 0.46, 0.34 + rng() * 0.34);
  }
  /* and the splash line: rain comes off the canopy edge and gets the
     bottom of everything on this parade */
  for (let y = 48; y < 64; y++) for (let x = 0; x < 64; x++)
    p.wash(x, y, 'grey', 0.20, 0.12 + ((y - 48) / 16) * 0.26);
  streaks(p, 9, 162, 'grey', 0.10, 0.34);
  p.grime(0.46, 'grey', 0.10, 163);
  return p.snap(0.5);
};

/* --- AND WHAT IS BEHIND THE GLASS ----------------------------------

   The back of the reveal, four units short of the shop's own wall, and
   it is the fifth layer: what the two sheets and the cavity are FOR.

   These are painted out of focus on purpose — see defocus above. They
   are also painted BRIGHT, because a shop window at night is a lit box
   in a dark wall and that contrast is the entire reason anybody looks
   at one. The pane in front of them is a dither, so the light comes
   through it in pieces, which is what makes the glass read as glass.
   ------------------------------------------------------------------ */

T.STORIN = () => {
  /* The anchor, over the tills: the lid first, then the ends of twelve
     gondola runs, then the lino coming back at you. Nothing in it is
     legible and nothing in it is meant to be. */
  const p = new Pix(64, 64, 164);
  const rng = makeRng(165);
  p.fill('bone', 0.22);
  /* the ceiling, and two runs of fittings in it going away from you */
  for (let y = 0; y < 15; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.30 + (1 - y / 15) * 0.16);
  for (const [y, h, t] of [[3, 3, 0.96], [10, 2, 0.80]])
    for (let d = 0; d < h; d++) for (let x = 0; x < 64; x++)
      p.ink(x, y + d, 'bone', t - d * 0.10);
  /* the far wall, and the aisle ends against it */
  for (let y = 15; y < 42; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.40 - (y - 15) / 27 * 0.12);
  const KEYS = ['red', 'yellow', 'green', 'blue', 'bone', 'rust', 'olive'];
  for (let i = 0; i < 26; i++) {
    const x = Math.floor(rng() * 64), w = 3 + Math.floor(rng() * 8);
    const top = 18 + Math.floor(rng() * 12), h = 4 + Math.floor(rng() * 16);
    const key = KEYS[Math.floor(rng() * KEYS.length)], t = 0.30 + rng() * 0.36;
    for (let yy = top; yy < top + h && yy < 46; yy++)
      for (let xx = x; xx < x + w; xx++) p.ink(xx, yy, key, t * (0.86 + rng() * 0.28));
  }
  /* the checkouts across the front, backlit, and the floor under them */
  for (let y = 42; y < 52; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.22 + ((x >> 3) & 1) * 0.06);
  for (let y = 52; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.46 - (y - 52) / 12 * 0.12);
  for (const x of [8, 26, 44, 58]) for (let y = 52; y < 64; y++)
    p.wash(x + ((y - 52) >> 2), y, 'bone', 0.80, 0.40 - (y - 52) * 0.02);
  defocus(p, 2);
  /* THE FITTINGS GO ON AFTER THE BLUR. Blurred with everything else
     they became a pale band and the ceiling stopped being a ceiling —
     and a strip light is the one thing in a supermarket that is not out
     of focus through the window, because it is the brightest thing in
     the building by a factor of ten. */
  for (const [y, t] of [[3, 0.98], [4, 0.86], [10, 0.82], [11, 0.66]])
    for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', t);
  p.grime(0.22, 'grey', 0.08, 166);
  return p.snap(0.4);
};

T.UNITIN = () => {
  /* A unit that still trades: one room, four metres deep, with a shelf
     run down the side and a counter across it. Warmer than the anchor
     and much less of it — a small shop is lit by four tubes and a
     chiller, not by a field of them. */
  const p = new Pix(64, 64, 167);
  const rng = makeRng(168);
  p.fill('bone', 0.20);
  for (let y = 0; y < 11; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.26 + (1 - y / 11) * 0.10);
  for (let x = 0; x < 64; x++) { p.ink(x, 4, 'yellow', 0.86); p.ink(x, 5, 'yellow', 0.70); }
  /* the back wall and the shelving against it */
  for (let y = 11; y < 44; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'olive', 0.26 - (y - 11) / 33 * 0.06);
  for (let y = 14; y < 42; y += 7) for (let x = 0; x < 64; x++) {
    p.ink(x, y, 'grey', 0.34); p.ink(x, y + 1, 'grey', 0.14);
  }
  for (let i = 0; i < 40; i++) {
    const x = Math.floor(rng() * 64), y = 15 + Math.floor(rng() * 4) * 7;
    const w = 2 + Math.floor(rng() * 4), h = 3 + Math.floor(rng() * 3);
    const key = ['red', 'yellow', 'blue', 'green', 'bone'][Math.floor(rng() * 5)];
    for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++)
      p.ink(xx, yy, key, 0.32 + rng() * 0.34);
  }
  /* the counter, and the floor in front of it */
  for (let y = 44; y < 54; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.30 - (y - 44) * 0.008);
  for (let x = 0; x < 64; x++) p.ink(x, 44, 'brown', 0.52);
  for (let y = 54; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.36 - (y - 54) / 10 * 0.10);
  defocus(p, 2);
  for (let x = 0; x < 64; x++) { p.ink(x, 4, 'bone', 0.94); p.ink(x, 5, 'yellow', 0.72); }
  p.grime(0.26, 'grey', 0.08, 169);
  return p.snap(0.4);
};

/* --- THE SHUT ONES -------------------------------------------------

   Most of this parade is empty, and what an empty parade IS, from the
   car park, is a run of metal. Not graffiti, not boarding, not TO LET
   signs: a hundred and thirty metres of roller shutter that somebody
   pulled down for the last time a few years ago and has not been back
   to. So these two are the most-seen surfaces on the whole building
   after the tarmac, and they are drawn to be read at two distances —
   as a grey band from the road, and as WORN METAL from the footway.

   ONE REPEAT IS FOUR LATHS AND NOTHING ELSE, which is the whole of the
   tiling decision. A shopfront runs from FLOOR_WALK to CEIL_SOFF, which
   is 220, and these were declared 64 — so they tiled three and a half
   times up the glass and the half was visible: whatever was at the
   bottom of the tile appeared three and a half times up the shutter, at
   three different heights. Declared 55 they tile exactly four times,
   and declared 72 exactly six across a 432-wide unit, so there is no
   partial repeat anywhere and no seam to find.

   WHICH MEANS NOTHING IN HERE MAY HAPPEN ONCE. No bottom rail, no lock,
   no guides — a shutter's curtain is the same thing all the way up and
   that is exactly what makes it tileable. The bottom rail is a free box
   standing on the footway (SHUTRAIL, and DRESSING THE PARADE in
   js/maps/sellwrong.js), which is where a thing that happens once
   belongs. Same argument as the coping and the parapet.
   ------------------------------------------------------------------ */

/** The curtain: `pitch` laths of a rolled profile, lit from the top of
 *  each lath and dark in the joint under it, which is what makes a
 *  stack of horizontal lines read as a corrugated sheet and not as a
 *  barcode. `key`/`base` are what the metal is; everything else is what
 *  has happened to it since. */
const shutterCurtain = (p, seed, key, base, pitch = 8) => {
  const n = fbm(p.w, p.h, 8, 3, seed);
  for (let y = 0; y < p.h; y++) {
    /* where in the lath this row is: 0 at the crown, 1 in the joint */
    const k = (y % pitch) / pitch;
    const roll = Math.cos(k * 6.0) * 0.5 + 0.5;          // crown bright, belly dark
    for (let x = 0; x < p.w; x++)
      p.ink(x, y, key, base + roll * 0.20 - 0.06 + n[y * p.w + x] * 0.07);
  }
  /* the joint itself: a hard dark line with the next lath's lip over it */
  for (let y = 0; y < p.h; y += pitch) {
    p.hline(0, p.w - 1, (y + pitch - 1) % p.h, 'grey', 0.07);
    p.hline(0, p.w - 1, y, key, base + 0.26);
  }
};

/** Rust, which on a shutter comes out of the JOINTS and not out of the
 *  flat: water sits in the lap between two laths and stays there. So
 *  the bloom is seeded on the joint rows and grows down from them. */
const shutterRust = (p, seed, amount, pitch = 8) => {
  const rng = makeRng(seed);
  const patch = fbm(p.w, p.h, 5, 3, seed + 11);
  /* `amount` is a THRESHOLD on the field and not a strength, which is
     the second go at this: an fbm hardly ever gets past 0.66, so
     treating it as a strength and subtracting it from one put the cut
     above almost every pixel and the first shutter came out clean.
     Half the surface should have something on it. */
  const cut = 1 - amount;
  for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) {
    const inJoint = (y % pitch) >= pitch - 3;
    const v = patch[y * p.w + x];
    if (v < cut) continue;
    const t = Math.min(1, (v - cut) / 0.30);
    p.wash(x, y, 'rust', 0.20 + t * 0.22, (inJoint ? 0.72 : 0.38) * t);
  }
  /* and the streaks it leaves running down from a bad joint */
  for (let k = 0; k < 14; k++) {
    const x = Math.floor(rng() * p.w);
    let y = Math.floor(rng() * p.h);
    for (let d = 0; d < 6 + rng() * 22; d++) {
      p.wash(x, (y + d) % p.h, 'rust', 0.26, 0.26 * (1 - d / 28));
      if (rng() < 0.16) return;
    }
  }
};

T.UNITSHUT = () => {
  /* Mill-finish aluminium, down for about three years. Semi worn and
     semi rusty, which is a specific thing and not a vague one: the
     crowns of the laths are POLISHED where a decade of hands and
     trolleys and weather have been at them, and the rust is in the
     joints where the water sits. Bright high spots, dirty low ones. */
  const p = new Pix(64, 64, 143);
  shutterCurtain(p, 143, 'grey', 0.42);
  const rng = makeRng(144);
  /* THE WEAR: the crowns polished through to bright metal, in patches,
     because wear is never even. */
  const worn = fbm(64, 64, 6, 3, 149);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    if ((y % 8) > 2) continue;                          // the crown only
    const w = worn[y * 64 + x];
    if (w > 0.56) p.wash(x, y, 'grey', 0.66, (w - 0.56) * 1.5);
  }
  shutterRust(p, 151, 0.52);
  /* THE DENTS. Somebody has kicked it and somebody has backed into it:
     a shallow bowl is a dark patch with a BRIGHT LIP on its top edge,
     because the lip is the only part of it still facing the light. */
  for (let k = 0; k < 5; k++) {
    const cx = Math.floor(rng() * 64), cy = Math.floor(rng() * 64), r = 3 + Math.floor(rng() * 5);
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      const d = Math.hypot(dx, dy) / r;
      if (d > 1) continue;
      p.wash(cx + dx, cy + dy, 'grey', 0.16, (1 - d) * 0.30);
    }
    for (let dx = -r; dx <= r; dx++) p.wash(cx + dx, cy - r, 'grey', 0.72, 0.34);
  }
  /* AND A TAG SOMEBODY SCRUBBED. Not a fresh one — there were five at
     full strength on this and a shutter covered in bright paint is a
     shutter somebody still visits. What is left of one is better: the
     ghost of it, at a fifth of the alpha, which reads as a surface that
     has been given up on rather than fought over. */
  {
    let x = 8 + rng() * 40, y = 16 + rng() * 32;
    for (let seg = 0; seg < 16; seg++) {
      const nx = x + (rng() - 0.5) * 18, ny = y + (rng() - 0.5) * 12;
      p.line(Math.round(x), Math.round(y), Math.round(nx), Math.round(ny), 'purple', 0.30, 255);
      x = nx; y = ny;
    }
  }
  streaks(p, 8, 145, 'grey', 0.16, 0.45);
  p.grime(0.42, 'grey', 0.12, 153);
  return p.snap(0.5);
};

T.UNITSHUT2 = () => {
  /* The other one, and the reason there are two is that thirteen shut
     units in a row out of one texture is a hundred and thirty metres of
     wallpaper. This one was PAINTED — a blue nobody would choose now —
     and paint on a shutter does not wear like metal: it chalks, it goes
     matt and pale all over, and then it lets go in flakes at the joints
     and the rust comes through the holes rather than over the surface. */
  const p = new Pix(64, 64, 155);
  shutterCurtain(p, 155, 'blue', 0.26);
  const rng = makeRng(157);
  /* the chalking: a pale film over everything, heaviest where the sun
     gets at it, which on a south-facing parade is everywhere */
  const chalk = fbm(64, 64, 5, 3, 159);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.wash(x, y, 'bone', 0.48, 0.34 + chalk[y * 64 + x] * 0.22);
  /* THE FLAKES, and there are far fewer of them than the first go had.
     Paint coming off a shutter is not camouflage: it goes in a handful
     of PATCHES with hard edges, and the first version scattered it over
     a third of the surface at a fine scale, which drowned the laths and
     turned the whole thing into mottling. What makes a flake read is
     that it is a HOLE in something otherwise continuous. */
  const flake = fbm(64, 64, 4, 2, 161);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    if (flake[y * 64 + x] < 0.74) continue;
    p.ink(x, y, 'grey', 0.28 + ((y % 8) < 3 ? 0.16 : 0));
    if (flake[((y + 63) % 64) * 64 + x] < 0.74) p.ink(x, y, 'bone', 0.58);   // the lifted edge
  }
  shutterRust(p, 163, 0.60);
  for (let k = 0; k < 4; k++) {                          // dents, as above
    const cx = Math.floor(rng() * 64), cy = Math.floor(rng() * 64), r = 3 + Math.floor(rng() * 4);
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      const d = Math.hypot(dx, dy) / r;
      if (d > 1) continue;
      p.wash(cx + dx, cy + dy, 'grey', 0.14, (1 - d) * 0.32);
    }
    for (let dx = -r; dx <= r; dx++) p.wash(cx + dx, cy - r, 'bone', 0.56, 0.16);
  }
  streaks(p, 10, 165, 'grey', 0.14, 0.5);
  p.grime(0.46, 'grey', 0.12, 167);
  return p.snap(0.5);
};

T.SHUTRAIL = () => {
  /* THE BOTTOM RAIL, which is the one thing on a shutter that happens
     once and is therefore the one thing that could not be in the
     curtain. It matters more than it sounds like it should: a curtain
     that runs off the bottom of the wall is a metal WALL, and a curtain
     that stops in a heavier rail with a rubber strip under it is a
     shutter that has been PULLED DOWN. That is the whole read.

     Fourteen tall and one repeat, so the pressed section, the weather
     strip and the shadow under it land in the same place along the
     whole parade. */
  const p = new Pix(64, 14, 169);
  for (let y = 0; y < 14; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.46 - y * 0.012);
  p.hline(0, 63, 0, 'grey', 0.66); p.hline(0, 63, 1, 'grey', 0.58);
  p.hline(0, 63, 6, 'grey', 0.20);                   // the lip of the pressing
  p.hline(0, 63, 7, 'grey', 0.50);
  for (let y = 10; y < 14; y++) p.hline(0, 63, y, 'grey', 0.10);   // the rubber strip
  const rng = makeRng(171);
  for (let k = 0; k < 70; k++)                       // and it sits in the wet
    p.wash(Math.floor(rng() * 64), 7 + Math.floor(rng() * 7), 'rust', 0.26, 0.12 + rng() * 0.34);
  p.grime(0.40, 'grey', 0.10, 173);
  return p.snap(0.5);
};

/* --- fascias -----------------------------------------------------
   One band per tenancy, and the name repeats along it. A 64-unit
   repeat means a 432-wide unit says its own name seven times, which is
   both what cheap signage looks like from a car park and the only way
   to get legible letters out of a texture this size. */
const fascia = (seed, text, bg, bgT, fg, fgT) => () => {
  const p = new Pix(64, 64, seed);
  const n = fbm(64, 64, 8, 2, seed);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, bg, bgT + n[y * 64 + x] * 0.10);
  for (let y = 0; y < 4; y++) for (let x = 0; x < 64; x++) p.ink(x, y, bg, bgT + 0.20);
  for (let y = 58; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, bg, Math.max(0.05, bgT - 0.14));
  p.hline(0, 63, 63, 'grey', 0.10);
  drawTextCentred(p, text, 32, 28, fg, fgT);
  p.grime(0.35, 'grey', 0.09, seed + 1);
  return p.snap(0.5);
};

T.FASCHEM = fascia(150, 'CHEMIST', 'green', 0.30, 'bone', 0.92);
T.FASPHON = fascia(152, 'PHONES', 'blue', 0.34, 'yellow', 0.90);
T.FASFOOD = fascia(154, 'KEBAB', 'red', 0.36, 'yellow', 0.92);
/* THERE WAS A FOURTH NAME HERE — WASH, over the laundrette — and it
   came off when every shut unit's board went dead. The laundrette is
   shut, which makes it an empty store, and a maintained sign over three
   years of roller shutter is the exact thing that pass was asked to
   stop. Three names are left on the building and they are the three
   units that still have a tenant in them. */
/* --- AND THE DEAD ONES ---------------------------------------------

   A blank tray is not an empty shop. The fourteen unnamed units carried
   a painted board in one of six colours whether the lights were on or
   not, and what that draws, at the user's request to make the empty ones
   read as empty, is a parade where every fascia looks maintained and
   only the glass tells you anything. The sign is the bigger surface and
   it was saying nothing.

   WHAT AN ABANDONED FASCIA LOOKS LIKE is three things, in this order of
   how far off you can read them:

     the colour has gone. Not darker — CHALKED, which is pale and flat
     and slightly the wrong hue, because what is left is the filler in
     the paint after the binder has gone;
     there is a CLEAN BAND across it where the sign panel was bolted,
     which the weather never got at, so the one part of the board that
     still has its colour is the part nobody can see any more;
     and everything below the fixings is stained, because water has been
     coming out of two holes in a board for six years.

   THE CLEAN BAND IS THE WHOLE IDEA and it is also the only version of
   "you can see where the letters were" that is allowed to exist here. A
   fascia tiles nearly seven times along one unit, so a ghost WORD would
   be seven ghost words, which is the mistake the agent's board made and
   the mistake the painted coping made. A horizontal band tiles
   perfectly and says the same thing.

   Three of them, because thirteen dead units out of one texture is
   wallpaper. */
const deadFascia = (seed, key, t) => () => {
  const p = new Pix(64, 64, seed);
  const n = fbm(64, 64, 8, 3, seed);
  const chalk = fbm(64, 64, 4, 3, seed + 37);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    p.ink(x, y, key, t + n[y * 64 + x] * 0.10);
    /* the chalking, which is what takes the colour out: a pale film,
       heavier where the sun has had longer at it */
    p.wash(x, y, 'bone', 0.46, 0.30 + chalk[y * 64 + x] * 0.26);
  }
  /* the tray: a lit top return and a shadow under, once, because the
     band is 96 and the texture is declared 96 */
  for (let y = 0; y < 4; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.50 - y * 0.03);
  p.hline(0, 63, 4, 'grey', 0.16);
  for (let y = 58; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.12 + (y > 61 ? 0 : 0.04));
  /* THE CLEAN BAND where the panel was: unchalked, so it keeps the
     colour the rest of the board has lost, with a hard edge top and
     bottom where the panel's own edge kept the rain off */
  /* KEPT, NOT RESTORED. First go painted the band at full strength over
     the chalk and what it drew was a two-tone sign somebody had chosen —
     a green board with a dark green stripe on it. The band is not a
     colour, it is the ABSENCE of six years of weather, so it carries
     the same film as the rest, only thinner. */
  for (let y = 22; y < 44; y++) for (let x = 0; x < 64; x++) {
    p.ink(x, y, key, t + 0.02 + n[y * 64 + x] * 0.09);
    p.wash(x, y, 'bone', 0.46, 0.14 + chalk[y * 64 + x] * 0.12);
  }
  p.hline(0, 63, 21, 'grey', 0.14); p.hline(0, 63, 22, 'bone', 0.40);
  p.hline(0, 63, 44, 'grey', 0.12); p.hline(0, 63, 43, 'bone', 0.34);
  /* and the two fixings it was bolted through, one repeat apart, each
     with six years of rust coming out of it */
  const rng = makeRng(seed + 3);
  for (const fx of [14, 46]) {
    p.disc(fx, 30, 2, 'grey', 0.10);
    p.ink(fx, 29, 'grey', 0.34);
    for (let y = 32; y < 64; y++) {
      const a = (1 - (y - 32) / 32) * 0.34;
      p.wash(fx + (rng() < 0.25 ? 1 : 0), y, 'rust', 0.28, a);
      if (rng() < 0.4) p.wash(fx - 1, y, 'rust', 0.26, a * 0.6);
    }
  }
  streaks(p, 9, seed + 5, 'grey', 0.18, 0.5);
  /* algae along the bottom edge, where the board stays wet */
  for (let y = 50; y < 58; y++) for (let x = 0; x < 64; x++)
    if (n[y * 64 + x] > 0.52) p.wash(x, y, 'olive', 0.22, (y - 50) / 8 * 0.40);
  p.grime(0.46, 'grey', 0.12, seed + 7);
  return p.snap(0.5);
};
/* The three: what each of them WAS. A green, a blue and a cream, which
   is three of the six the shopfitter had in the van — so a dead board
   and a live one on the same parade were painted out of the same tins,
   and the difference between them is entirely what has happened since. */
/* AND THEY ARE PALER THAN THE LIVE ONES, not darker, which took a shot
   from the car park to see. The first values here were the same as the
   painted trays' — around 0.20 — and at the 0.46 the footway lights a
   shut unit with, a dark green board and a dark blue one both came out
   very nearly black. Which is exactly backwards: a dead board is not an
   unlit board, it is a CHALKED one, and chalking is the binder going
   and the white filler coming out. The failure state of paint is pale. */
T.FASVOID  = deadFascia(158, 'green', 0.32);
T.FASVOID1 = deadFascia(180, 'blue',  0.32);
T.FASVOID2 = deadFascia(184, 'bone',  0.36);

/* --- AND FOURTEEN THAT NEVER HAD ONE ------------------------------
   Fourteen more tenancies went into the parade at the user's request and
   none of them is named. That is not a shortcut: a fascia is one repeat
   of a 96-tall texture and a 432-wide unit says its name seven times, so
   eighteen NAMES along a three-hundred-and-seventy-metre elevation is a
   hundred and twenty-six legible words shouting over the one sign the
   level is about. Four is a parade with character. Eighteen is noise.

   So what these carry is the TRAY and the paint in it, which is all a
   fascia is before anybody screws letters to it: a coloured board with a
   lit top edge, a shadow under it and a decade of weather on it. Six
   colours, and they are the six a shopfitter has in the van — a green,
   a red, a blue, a cream, a brown and a grey-blue — deliberately muted,
   because a row of saturated boards reads as bunting.

   THEY GO DARKER THAN THE NAMED ONES, and that is the point of the
   number rather than an accident of picking it: an unlit board with
   nothing on it is what the far end of a parade looks like at two in the
   morning, and the four that DO have names are the four that still pay
   somebody to leave the lighting on. */
const PLAIN_FASCIA = [
  ['green',  0.20], ['red',    0.18], ['blue',   0.22],
  ['bone',   0.24], ['brown',  0.20], ['cyan',   0.15],
];
PLAIN_FASCIA.forEach(([key, t], i) => {
  T['FASPLAIN' + i] = fascia(170 + i * 2, '', key, t, key, t + 0.2);
});

/* THERE WAS A PYLON SIGN HERE and it is gone, along with the ring of
   four thin sectors in the map that carried it. It was declared 340
   tall on a wall 480 tall, so the board drew once where a board goes
   and then a second time two thirds of the way down the post, which is
   nowhere a board goes. The right fix for that is one number; the fix
   the user asked for is the whole object, so what stands at the mouth
   of the car park now is the car park. */

T.POSTMETL = () => {
  /* Galvanised column: car park lighting, and the bollards. */
  const p = new Pix(64, 64, 164);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const round = Math.sin((x / 64) * Math.PI);        // fake the cylinder
    p.ink(x, y, 'grey', 0.14 + round * 0.26);
  }
  const rng = makeRng(165);
  for (let i = 0; i < 90; i++) {                       // spangle
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    p.ink(x, y, 'grey', 0.20 + rng() * 0.26);
  }
  p.grime(0.5, 'rust', 0.09, 166);
  return p.snap(0.5);
};

T.TROLLRAI = () => {
  /* The trolley bay: galvanised rail and nothing written on it. There
     was a blue plate on the near upright saying BAY, and it went with
     the pylon — nothing in the car park carries writing now. */
  const p = new Pix(64, 48, 168);
  p.clear();
  for (const ry of [6, 26]) for (let x = 0; x < 64; x++) {
    p.ink(x, ry, 'grey', 0.18); p.ink(x, ry + 1, 'grey', 0.44); p.ink(x, ry + 2, 'grey', 0.24);
  }
  for (const px of [4, 32, 60]) for (let y = 4; y < 48; y++) {
    p.ink(px, y, 'grey', 0.18); p.ink(px + 1, y, 'grey', 0.42);
  }
  /* the bracket the plate was bolted to, still on the upright */
  for (let y = 34; y < 38; y++) { p.ink(33, y, 'grey', 0.30); p.ink(34, y, 'grey', 0.16); }
  return p.snap(0.4);
};

/* --- THE FENCE ROUND THE SERVICE YARD ------------------------------
   Chain link, and it is the one texture in the file that is mostly
   nothing: transparent everywhere the wire is not, so it hangs in a
   two-sided line as something you see the wood THROUGH. See `midHeight`
   in js/mapgeo.js for the other half of that — a fence is eight feet of
   wire standing in an opening that is open to the sky, so the quad has
   to stop at the top rail rather than at the cloud base.

   128 BY 96 IS A DECISION ABOUT TILING AND NOT ABOUT DETAIL. The mesh
   is two families of 45-degree diagonals sixteen apart, and sixteen
   divides both 128 and 96, so the diamonds run on across a repeat in
   both directions with no seam and no half-diamond at the joint. One
   post per repeat puts an upright every 128 units, which is about ten
   feet, which is where a real one goes. */
T.CHAINLNK = () => {
  const p = new Pix(64, 48, 411);
  p.clear();
  const TOP = 2, BOT = 45;
  /* THE MESH. Two families of 45-degree diagonals eight texels apart,
     and the near family is drawn over the far one with a dark texel
     beside each bright one — which is the whole of why it reads as round
     wire rather than as a drawn grid. Eight divides both 64 and 48, so
     the diamonds run on across a repeat in either direction with no
     seam and no half-diamond at the joint. */
  for (let y = TOP; y < BOT; y++) {
    for (let x = 0; x < 64; x++) {
      const u = (x + y) % 8, v = (x - y + 640) % 8;
      if (u === 0)      p.ink(x, y, 'grey', 0.54);
      else if (u === 1) p.ink(x, y, 'grey', 0.20, 210);
      else if (v === 0) p.ink(x, y, 'grey', 0.46);
      else if (v === 1) p.ink(x, y, 'grey', 0.16, 210);
    }
  }
  /* the top rail, and the tension wire the mesh is wrapped round at the
     bottom — without those two it is a net rather than a fence */
  for (let x = 0; x < 64; x++) {
    p.ink(x, 0, 'grey', 0.62); p.ink(x, 1, 'grey', 0.34, 220);
    p.ink(x, BOT, 'grey', 0.50); p.ink(x, BOT + 1, 'grey', 0.20, 200);
    if ((x & 3) === 0) { p.ink(x, TOP, 'grey', 0.40); p.ink(x, BOT - 1, 'grey', 0.34); }
  }
  /* and the post, which is what the repeat is measured in: one upright
     every 128 world units, which is about where a real one goes */
  for (let y = 0; y < 48; y++) { p.ink(0, y, 'grey', 0.58); p.ink(1, y, 'grey', 0.22); }
  p.ink(0, 0, 'grey', 0.70); p.ink(1, 0, 'grey', 0.52);   // the cap on it
  return p.snap(0.35);
};

/* --- the doors themselves -----------------------------------------
   Two leaves, and they are drawn as WHOLE leaves rather than as a
   tiling pattern: the quad maps 0..1 in both directions, so the stiles
   land where the stiles go instead of wherever the repeat happens to
   fall. Everything not glass or frame is transparent, so the doors are
   something you look THROUGH at the store you are about to burn.

   The two are mirror images and drawn by one function, because a pair
   of sliders that are not each other's mirror looks wrong immediately
   and nobody can say why. */
const slideLeaf = (seed, mirrored) => () => {
  const p = new Pix(64, 64, seed, false);            // no wrap: a sprite, not a tile
  p.clear();
  const STILE = 5;
  /* the meeting stile is thicker, and it is the edge the two leaves
     close against — so it is on the right for the left leaf */
  const inner = mirrored ? 0 : 64 - STILE - 3;
  const outer = mirrored ? 64 - STILE : 0;
  const frame = (x0, w) => {
    for (let y = 0; y < 64; y++) for (let x = x0; x < x0 + w; x++) {
      const e = (x === x0 || x === x0 + w - 1);
      p.ink(x, y, 'grey', e ? 0.30 : 0.52);
    }
  };
  /* glass first, so the frame sits over it */
  for (let y = 3; y < 61; y++) for (let x = 3; x < 61; x++) {
    /* rakes "\" down from the top left, like every other pane in this
       game: the leaf's v was upside down until today and this diagonal
       was drawn to come out right through the flip. */
    /* +102 is three whole pitches, so it shifts no phase and only keeps
       the modulo's argument positive: the mirrored leaf's ran negative
       over half its face and lost its sheen there, which is why one of
       these two was always the duller one. */
    const sheen = Math.max(0, 1 - Math.abs((x * (mirrored ? -1 : 1) - y * 0.6 + 102) % 34 - 7) / 12);
    const a = Math.round(40 + sheen * 90);
    p.ink(x, y, 'cyan', 0.16 + sheen * 0.26, a);
  }
  frame(inner, STILE + 3);
  frame(outer, STILE);
  for (let y = 0; y < 3; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', y === 0 ? 0.28 : 0.50);
  for (let y = 58; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', y > 61 ? 0.22 : 0.46);
  /* the green man, centred on each leaf and mirrored with it */
  const gx = mirrored ? 38 : 26;
  p.disc(gx, 30, 6, 'green', 0.40, 210);
  p.disc(gx, 30, 5, 'green', 0.72, 235);
  p.ink(gx, 27, 'bone', 0.9); p.ink(gx, 28, 'bone', 0.9);
  p.line(gx - 2, 29, gx + 2, 32, 'bone', 0.9);
  p.line(gx - 1, 30, gx + 1, 34, 'bone', 0.9);
  return p.snap(0.3);
};

T.SLIDEL = slideLeaf(170, false);
T.SLIDER = slideLeaf(172, true);

/* --- the fire exit --------------------------------------------------
   One leaf, painted steel, a crash bar across it and the running man
   above that. The picture IS the leaf — mapped 0..1 by js/slidedoor.js
   like the sliders — so everything on it is drawn where it goes on a
   door rather than wherever a 64-unit repeat happens to fall.

   TWO THINGS ARE ON IT AND NEITHER IS A WORD. A supermarket fire door
   in this country carries the pictogram and the bar and nothing else,
   which is lucky, because the last four textures that had lettering on
   them came down for the same reason: a word is a shape you can count,
   and the moment it is on anything that repeats you are reading it
   twenty-eight times. A leaf never repeats — but the habit is worth
   keeping anyway, and the pictogram is better signage than the word is.

   THE BAR IS WHERE THE STORY IS. It is the reason the crowd can leave
   and the player cannot lock them in: a fire door has no handle on this
   side and no keyhole on the other, and anybody who leans on it is
   outside. So it is the brightest thing on the leaf. */
T.EXITDOOR = () => {
  const p = new Pix(64, 64, 168, false);           // no wrap: a sprite, not a tile
  const n = fbm(64, 64, 10, 2, 168);
  /* the leaf: works-painted steel, a little lighter down the hinge side
     because the corridor light rakes across it */
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'green', 0.16 + (1 - x / 64) * 0.06 + n[y * 64 + x] * 0.05);
  /* THE STILES AND THE RAILS, built the way the staff door's are: the
     hinge side is the edge that does not move and the one the light
     catches, and the lock stile is the one that has been shouldered
     through forty thousand times. */
  for (let y = 0; y < 64; y++) {
    p.ink(0, y, 'green', 0.34); p.ink(1, y, 'green', 0.28);
    p.ink(62, y, 'green', 0.09); p.ink(63, y, 'green', 0.13);
  }
  for (let x = 0; x < 64; x++) {
    p.ink(x, 0, 'green', 0.36); p.ink(x, 1, 'green', 0.28);
    p.ink(x, 62, 'green', 0.10); p.ink(x, 63, 'green', 0.20);
  }
  /* box and frame take a WIDTH and a HEIGHT, not a second corner */
  p.frame(4, 4, 56, 56, 'green', 0.26);
  p.frame(5, 5, 54, 54, 'green', 0.11);
  /* three butt hinges down the stile it turns on — the same three the
     staff door has, and on the same side, because u = 0 IS the hinge on
     every leaf in this game */
  for (const hy of [8, 32, 56]) {
    p.box(0, hy - 5, 5, 11, 'green', 0.24);
    p.box(1, hy - 5, 3, 11, 'grey', 0.40);          // the knuckle
    p.vline(1, hy - 5, hy + 5, 'bone', 0.52);
    p.ink(4, hy - 5, 'green', 0.08); p.ink(4, hy + 5, 'green', 0.08);
  }
  /* THE CRASH BAR, two thirds of the way up because that is hand height
     on a door twice a person tall, with its brackets at either end and a
     shadow under it. Bone rather than grey: a push bar is anodised and it
     is the one part of a fire door that has been touched every day. */
  const BY = 36;
  for (let x = 6; x < 58; x++) {
    p.ink(x, BY - 1, 'bone', 0.44);
    p.ink(x, BY,     'bone', 0.66);
    p.ink(x, BY + 1, 'bone', 0.30);
    p.ink(x, BY + 3, 'green', 0.07);               // the shadow it throws
  }
  for (const bx of [7, 56]) {
    for (let y = BY - 4; y < BY + 5; y++) p.ink(bx, y, 'bone', 0.34);
    p.ink(bx, BY - 4, 'bone', 0.52);
  }
  /* THE RUNNING MAN, on his green plate, up where a sign goes — and the
     plate is drawn WIDE AND SHORT because the leaf is not.

     These are a PAIR now, so a leaf is sixty across and a hundred and
     sixteen tall, and the picture is mapped 0..1 over that: a texel on
     it is about one unit wide and two units tall. Anything drawn square
     in here comes out standing on end. So the plate is thirty-four by
     eighteen, which is square ON THE DOOR, and the figure inside it is
     not square and should not be — a person is about twice as tall as
     they are wide, which in these texels is fourteen across by fifteen
     down. The head is a box rather than a disc for the same reason: a
     circle of texels is an egg on the leaf. */
  const gx = 32, gy = 20;
  p.box(gx - 17, gy - 9, 34, 18, 'green', 0.52);
  p.frame(gx - 17, gy - 9, 34, 18, 'green', 0.68);
  p.box(gx - 4, gy - 7, 4, 2, 'bone', 0.92);              // head
  p.line(gx - 3, gy - 4, gx + 1, gy + 1, 'bone', 0.92);   // body
  p.line(gx + 1, gy + 1, gx + 6, gy + 6, 'bone', 0.92);   // trailing leg
  p.line(gx + 1, gy + 1, gx - 5, gy + 6, 'bone', 0.92);   // leading leg
  p.line(gx - 3, gy - 3, gx + 4, gy - 6, 'bone', 0.86);   // arm, thrown forward
  /* THE KICK PLATE, which this door wanted for as long as the staff door
     did and for a better reason: the crowd that comes through here is
     not carrying a cage, it is RUNNING, and what hits the bottom of a
     fire door in an evacuation is everybody's feet. Stainless, brushed,
     and a good deal more beaten up than the one at the back of the shop,
     because this one is on the weather side of the building. */
  for (let y = 48; y < 63; y++) for (let x = 3; x < 61; x++)
    p.ink(x, y, 'grey', 0.50 + n[y * 64 + x] * 0.10 - (y - 48) * 0.006);
  p.hline(3, 60, 48, 'bone', 0.66); p.hline(3, 60, 49, 'grey', 0.26);
  for (const sx of [9, 19, 30, 41, 52, 58]) { p.ink(sx, 48, 'grey', 0.18); p.ink(sx, 49, 'grey', 0.15); }
  for (let i = 0; i < 80; i++)                                   // brushed, not polished
    p.wash(3 + ((i * 29) % 58), 50 + ((i * 11) % 13), 'grey', 0.36, 0.30);
  /* AND THE WEATHER, which the staff door never sees: this leaf faces
     nine thousand units of wood, and what runs down it runs from the
     hinges and from under the bar. */
  streaks(p, 4, 1681, 'rust', 0.24, 0.20);
  for (const hy of [8, 32, 56]) for (let y = hy + 5; y < Math.min(64, hy + 22); y++)
    p.wash(2 + ((y * 3) % 3), y, 'rust', 0.24, 0.30 * (1 - (y - hy - 5) / 18));
  /* and the bottom eighteen inches, which every trolley in the shop has
     hit at least once */
  p.grime(0.34, 'grey', 0.08, 169);
  return p.snap(0.3);
};

/* --- what the bigger shop floor needed ---------------------------- */

T.SHELFMIX = () => {
  /* A run somebody has already been down: half of it faced up, half of
     it gone, and the gaps showing the back panel through. Four shelves
     in 64 pixels, declared as 80 units tall, exactly like its neighbours
     — the stretch is a quarter and it lands on a picture of tins. */
  const p = new Pix(64, 64, 174);
  const rng = makeRng(174);
  p.fill('grey', 0.14);
  for (let sy = 0; sy < 64; sy += 16) {
    for (let y = sy; y < sy + 3; y++) for (let x = 0; x < 64; x++)   // the shelf edge
      p.ink(x, y, 'grey', y === sy ? 0.34 : 0.20);
    let x = 1;
    while (x < 63) {
      const w = 3 + Math.floor(rng() * 6);
      if (rng() < 0.45) { x += w; continue; }                        // a hole in the facing
      const key = ['red', 'yellow', 'green', 'blue', 'olive', 'purple'][Math.floor(rng() * 6)];
      const t = 0.24 + rng() * 0.42, h = 8 + Math.floor(rng() * 5);
      for (let y = sy + 3; y < Math.min(sy + 3 + h, 64); y++)
        for (let xx = x; xx < Math.min(x + w, 63); xx++)
          p.ink(xx, y, key, t + (xx === x ? 0.12 : 0));
      x += w + 1;
    }
  }
  p.grime(0.35, 'grey', 0.08, 175);
  return p.snap(0.55);
};

T.BAKECASE = () => {
  /* The bakery: a warm case, and the only thing in the building that
     ever smelled good. */
  const p = new Pix(64, 40, 176);
  p.fill('bone', 0.20);
  for (let y = 0; y < 6; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', 0.38);
  for (let y = 6; y < 30; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'yellow', 0.18 + (30 - y) / 90);
  const rng = makeRng(177);
  for (let i = 0; i < 26; i++) {                    // loaves and trays
    const cx = 4 + Math.floor(rng() * 56), cy = 12 + Math.floor(rng() * 15);
    const r = 2 + Math.floor(rng() * 3);
    p.disc(cx, cy, r, 'brown', 0.42 + rng() * 0.3);
    p.ink(cx, cy - r, 'brown', 0.72);
  }
  for (const sy of [10, 20]) p.hline(0, 63, sy, 'grey', 0.30);
  for (let y = 30; y < 40; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.22 + ((x >> 3) & 1) * 0.05);
  p.hline(0, 63, 30, 'bone', 0.48);
  p.grime(0.3, 'grey', 0.07, 178);
  return p.snap(0.5);
};

T.MISSING = () => {
  /* Loud on purpose. See TextureBank.get. */
  const p = new Pix(64, 64, 1);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const c = ((x >> 3) + (y >> 3)) & 1;
    p.set(x, y, c ? 255 : 0, 0, c ? 255 : 0, 255);
  }
  drawTextCentred(p, 'NO', 32, 20, 'bone', 1);
  drawTextCentred(p, 'TEX', 32, 30, 'bone', 1);
  return p;
};

/* --------------------------------------------------------------------
   After the fire

   A store that burns down and looks exactly the same afterwards is not
   burning down, it is playing an animation. So every surface that can
   burn gets a charred twin, generated from the original rather than
   drawn separately — which keeps the two in register, so a shelf that
   goes up turns into a burnt version of ITSELF rather than into a
   different shelf.

   Three things happen to a surface that has been on fire, and all three
   are needed or it just looks dim:

     it goes DARK, but not uniformly — soot collects in the recesses and
       the raised edges stay comparatively bare, so the relief that was
       there before is still legible, only inverted
     it goes GREY in patches, because ash is pale, and those patches are
       what stop it reading as "the lights went out"
     a few EMBERS survive, and they are the only saturated colour left
   ------------------------------------------------------------------ */
export function charVariant(src, seed, after = null) {
  const p = new Pix(src.w, src.h, seed, src.wrap);
  p.data.set(src.data);

  const soot = fbm(src.w, src.h, 8, 3, seed);
  const ash = fbm(src.w, src.h, 16, 2, seed + 991);

  for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
      const i = p.idx(x, y);
      if (i < 0 || p.data[i + 3] < 8) continue;
      const d = p.data;
      const lum = (d[i] * 0.3 + d[i + 1] * 0.6 + d[i + 2] * 0.1) / 255;
      const s = soot[y * src.w + x];

      /* Soot sticks where the surface was already dark — the recesses.
         Charring uniformly flattens the relief to a grey rectangle.

         The first pass at this took everything down to about a tenth,
         which is what a burnt surface really reflects and which made the
         gutted store literally unreadable — and you have to walk back
         out through it. So it keeps rather more than it should, and the
         ash below is doing most of the work of making it legible. */
      const keep = 0.30 + s * 0.26 + lum * 0.26;
      d[i] *= keep; d[i + 1] *= keep * 0.95; d[i + 2] *= keep * 0.88;

      /* ash: pale, patchy, and the only thing you can actually see by.
         Lifted again after the burnt store came out "WAY too dark" —
         a gutted aisle is grey, not black. */
      const a = ash[y * src.w + x];
      if (a > 0.48) p.wash(x, y, 'grey', 0.44 + (a - 0.48) * 0.9, (a - 0.48) * 1.7);
      if (a > 0.74 && s > 0.5) p.wash(x, y, 'grey', 0.60, (a - 0.74) * 1.8);
    }
  }

  /* the last of it, still glowing in the cracks */
  speckle(src.w, src.h, Math.round(src.w * src.h * 0.022), seed + 77, (x, y, a, b) => {
    if (p.alphaAt(x, y) < 8) return;
    if (a > 0.80) p.ink(x, y, 'fire', 0.34 + b * 0.34);
    else if (a > 0.45) p.wash(x, y, 'fire', 0.18, 0.40);
  });
  /* AND ANYTHING THAT WAS NOT A SURFACE. Charring is a filter over
     pixels: it can darken a light fitting but it cannot know that the
     thing it just darkened has stopped being a light and needs drawing
     again, dead. That is what `after` is for. Before the snap, so the
     whole texture is quantised once. */
  if (after) after(p);
  return p.snap(0.4);
}

/* =====================================================================
   PAST CHARRED: THE RUIN

   Charring is what a surface looks like when the fire has been over it.
   This is what a BUILDING looks like when the fire has finished with it,
   and it is a different thing: not a darker wall but a wall that is no
   longer there in places, with what was holding it up showing through
   the holes and still glowing.

   FOUR TEXTURES FOR EVERYTHING, and that is the whole trick. A charred
   surface has to remember what it was — burnt shelving and a burnt
   ceiling tile are different pictures — so there is a `_B` twin for
   every charrable texture and there are forty of them. A GUTTED surface
   does not: past a certain point a partition, a chiller surround and a
   shopfront are all the same rubble, and pretending otherwise would mean
   forty more textures that all had to converge on the same look anyway.
   So four, chosen by which SLOT the surface fills rather than by what it
   used to be — see `guttedSurfaces`.

   They are drawn dark and lit from the cracks, and the game lifts a
   gutted region's ambient, because a burnt-out shed at night with no
   roof is accurately almost black and you still have to walk out
   through it.
   ===================================================================== */

/* THREE OF EACH, and the reason is that a ruin is not a material, it is
   an accident. Two aisles that burned do not char identically — the
   framing is at a different centre, the deck fell in a different place,
   a different shelf survived — and one texture repeated across a whole
   gutted store reads as a pattern, which is the one thing a ruin must
   not read as. So each of the four is a family of three, and
   `guttedSurfaces` picks a region's by a hash of its index: stable
   across a reload, different from its neighbour's. */
export const RUIN_VARIANTS = 3;

/* ---------------------------------------------------------------------
   THE WALL

   THE STRUCTURE SURVIVES AND THE SKIN DOES NOT, which is both what
   happens and what makes the picture legible. A stud wall that has been
   through a fire is not a hole: it is a frame, standing, with the board
   gone between the studs — and the board goes from the TOP DOWN, because
   fire climbs and because the bottom of a wall is the last place the
   heat reaches. So there is a survival gradient up the texture, ragged
   at its edge, and the framing is untouched all the way up.
   ------------------------------------------------------------------- */
for (let v = 0; v < RUIN_VARIANTS; v++) {
  /* stud centres, where the noggin runs, and how much board is left */
  const PITCH = [16, 21, 13][v];
  const NOGGIN = [30, 22, 40][v];
  const HOLD = [0.46, 0.34, 0.56][v];        // how far up the board survives
  T['RUINWALL' + v] = () => {
    const p = new Pix(64, 64, 470 + v * 7);
    const rng = makeRng(471 + v * 13);
    const n = fbm(64, 64, 10, 3, 472 + v * 11);
    const edge = valueNoise(64, 64, 9, 473 + v * 17);
    const height = new Float32Array(64 * 64);

    /* the dark behind: the next room, which is also burnt */
    for (let y = 0; y < 64; y++)
      for (let x = 0; x < 64; x++) {
        p.ink(x, y, 'grey', 0.035 + n[y * 64 + x] * 0.045);
        height[y * 64 + x] = 0.06;
      }

    /* WHAT IS LEFT OF THE BOARD. Certain at the floor, gone at the top,
       with a torn edge in between — and it hangs on at the studs, which
       is where its fixings are. */
    for (let y = 0; y < 64; y++) {
      const up = 1 - y / 63;                       // 0 at the top, 1 at the floor
      const near = Math.abs(((y % PITCH) / PITCH) - 0.5);   // unused vertically
      for (let x = 0; x < 64; x++) {
        const bx = ((x % PITCH) / (PITCH - 1));
        const atStud = Math.min(bx, 1 - bx) < 0.22;        // held by its fixings
        const survive = up * (HOLD + (atStud ? 0.34 : 0)) + edge[y * 64 + x] * 0.42
                      + (y > 56 ? 0.5 : 0);
        if (survive < 0.55) continue;
        p.ink(x, y, 'bone', 0.15 + n[y * 64 + x] * 0.13 + up * 0.05);
        height[y * 64 + x] = 0.52 + survive * 0.18;
        if (rng() < 0.45) p.wash(x, y, 'grey', 0.05, 0.34);  // soot up the face
      }
    }

    /* THE STUDS, standing the whole height. They are the point: a hole
       with nothing behind it is a hole in the world; a hole with framing
       behind it is a building. */
    for (let sx = 2; sx < 64; sx += PITCH) {
      for (let y = 0; y < 64; y++) {
        const flick = valueNoise(1, 1, 1, sx * 31 + y * 7 + v * 991)[0];
        for (let x = sx; x < sx + 3; x++) {
          if (x > 63) continue;
          p.ink(x, y, 'brown', 0.095 + flick * 0.075);
          height[y * 64 + x] = 0.88;
        }
        if (flick > 0.72) p.ink(Math.min(63, sx + 1), y, 'grey', 0.05);
      }
    }
    /* the noggin across, half burnt through */
    for (let y = NOGGIN; y < NOGGIN + 4; y++)
      for (let x = 0; x < 64; x++)
        if (valueNoise(1, 1, 1, x * 13 + y * 101 + v * 77)[0] > 0.22) {
          p.ink(x, y, 'brown', 0.085 + (y === NOGGIN ? 0.05 : 0));
          height[y * 64 + x] = 0.80;
        }

    p.emboss(height, 0.42, 0.9);

    /* A few coals baked in as rubble; the LIVE ones are the shader's,
       and they land in the dark places this leaves. */
    speckle(64, 64, 150 + v * 40, 474 + v * 5, (x, y, a, b) => {
      if (a > 0.94) p.ink(x, y, 'fire', 0.34 + b * 0.34);
    });
    return p.snap(0.4);
  };
}

/* ---------------------------------------------------------------------
   THE FLOOR

   A slab does not burn. What is on it is ash, what fell out of the
   ceiling, and the fire still in the joints — which is where the light
   in a gutted aisle comes from, so it has to read from across the shop.
   ------------------------------------------------------------------- */
for (let v = 0; v < RUIN_VARIANTS; v++) {
  const DEBRIS = [26, 40, 16][v];
  const CRACKS = [[[8, 12, 46], [40, 4, 40], [22, 50, 34], [54, 30, 30]],
                  [[2, 30, 58], [34, 2, 52], [50, 44, 26]],
                  [[16, 6, 40], [6, 46, 44], [44, 20, 46], [30, 34, 22], [56, 2, 30]]][v];
  T['RUINFLR' + v] = () => {
    const p = new Pix(64, 64, 480 + v * 9);
    const rng = makeRng(481 + v * 3);
    aggregate(p, 481 + v * 3, { baseKey: 'grey', baseLo: 0.07, baseHi: 0.13,
      grades: [{ count: 220, min: 0.4, max: 1.1, key: 'grey', lo: 0.05, hi: 0.15 }] });
    const ash = fbm(64, 64, 7, 3, 482 + v * 19);
    for (let y = 0; y < 64; y++)
      for (let x = 0; x < 64; x++) {
        const a = ash[y * 64 + x];
        if (a > 0.52) p.wash(x, y, 'bone', 0.30 + (a - 0.52) * 0.7, (a - 0.52) * 1.9);
      }
    for (let i = 0; i < DEBRIS; i++) {
      const x = rng() * 64, y = rng() * 64, r = 1 + rng() * 3.2;
      p.disc(x, y, r, 'grey', 0.05 + rng() * 0.05);
      p.disc(x - 0.6, y - 0.6, r * 0.6, 'brown', 0.07 + rng() * 0.05);
    }
    CRACKS.forEach(([cx, cy, len], k) => {
      crack(p, cx, cy, len, 'fire', 0.32, 483 + v * 31 + k, 1.2);
      crack(p, cx + 1, cy, len, 'fire', 0.11, 484 + v * 31 + k, 1.2);
    });
    speckle(64, 64, 160, 487 + v * 7, (x, y, a, b) => {
      if (a > 0.94) p.ink(x, y, 'fire', 0.38 + b * 0.4);
    });
    return p.snap(0.45);
  };
}

/* ---------------------------------------------------------------------
   THE DECK

   Looking up at what is left of a roof. THE PURLINS ALWAYS SURVIVE —
   they are steel, they are what the roof hangs on, and a ceiling with no
   structure left in it is a ceiling that would not be there at all. The
   profiled deck between them goes in patches, and where it has gone you
   are looking at the sky.
   ------------------------------------------------------------------- */
for (let v = 0; v < RUIN_VARIANTS; v++) {
  const GONE = [0.46, 0.38, 0.55][v];          // how much of the deck is missing
  const PURLIN = [26, 12, 40][v];              // where the beam crosses
  T['RUINDECK' + v] = () => {
    const p = new Pix(64, 64, 490 + v * 11);
    const height = new Float32Array(64 * 64);
    const gone = fbm(64, 64, 8, 3, 491 + v * 23);
    const n = fbm(64, 64, 14, 2, 492 + v * 13);
    for (let y = 0; y < 64; y++) {
      for (let x = 0; x < 64; x++) {
        if (gone[y * 64 + x] > GONE) { p.ink(x, y, 'grey', 0.03); height[y * 64 + x] = 0.02; continue; }
        const r = x % 16;
        const t = r < 2 ? 0.05 : r < 4 ? 0.13 : r < 12 ? 0.10 : r < 14 ? 0.07 : 0.05;
        p.ink(x, y, 'grey', t + n[y * 64 + x] * 0.04);
        height[y * 64 + x] = r < 4 ? 0.8 : 0.55;
      }
    }
    for (let y = PURLIN; y < PURLIN + 7; y++)
      for (let x = 0; x < 64; x++) {
        const k = y - PURLIN;
        const t = k < 2 ? 0.19 : k < 5 ? 0.13 : 0.06;
        p.ink(x, y & 63, 'grey', t);
        height[(y & 63) * 64 + x] = k < 2 ? 0.95 : 0.78;
      }
    for (let x = 6; x < 64; x += 16) p.ink(x, (PURLIN + 3) & 63, 'rust', 0.16);
    p.emboss(height, 0.38, 0.85);
    speckle(64, 64, 130, 493 + v * 5, (x, y, a, b) => {
      if (gone[y * 64 + x] > GONE) return;
      if (a > 0.93) p.ink(x, y, 'fire', 0.28 + b * 0.3);
    });
    return p.snap(0.4);
  };
}

/* ---------------------------------------------------------------------
   THE DECK, BURNT THROUGH

   The stage between a deck that is charred and a deck that is not there
   — and the stage that was missing, which is why a gutted store used to
   go from "ceiling" to "sky" with nothing in between.

   This one is MASKED: where the deck has burnt through there is no
   texel at all, and what you see through the hole is whatever is behind
   it, which up here is the framing this roof was sitting on and then the
   night. That is the whole point of drawing it rather than swapping
   straight to sky: a roof with holes in it reads as a ROOF, and a ceiling
   that has been deleted reads as a rendering fault.

   Declared at 128 world units to the tile rather than 64, so a hole is
   about sixty units across and the repeat is coarse enough that a long
   run of it does not read as wallpaper. The ribs and the beam line come
   from the same numbers as RUINDECK, because these are the same roof at
   two different stages of going.
   ------------------------------------------------------------------- */
for (let v = 0; v < RUIN_VARIANTS; v++) {
  const OPEN = [0.40, 0.33, 0.48][v];          // how much of it is a hole now
  const PURLIN = [26, 12, 40][v];
  T['RUINHOLE' + v] = () => {
    const p = new Pix(64, 64, 520 + v * 11);
    p.clear();                                  // nothing is here until it is
    const height = new Float32Array(64 * 64);
    const gone = fbm(64, 64, 5, 3, 521 + v * 23);
    const n = fbm(64, 64, 14, 2, 522 + v * 13);
    /* WHAT IS LEFT OF THE DECK, with the holes actually open. The noise
       is coarser than RUINDECK's — a hole you can see the sky through is
       a metre of missing roof, not a scorch mark. */
    for (let y = 0; y < 64; y++) {
      for (let x = 0; x < 64; x++) {
        /* the beam line holds whatever happens either side of it */
        const onBeam = ((y - PURLIN + 64) % 64) < 7;
        if (!onBeam && gone[y * 64 + x] > OPEN) continue;   // burnt through
        const r = x % 16;
        const t = r < 2 ? 0.04 : r < 4 ? 0.11 : r < 12 ? 0.085 : r < 14 ? 0.06 : 0.04;
        p.ink(x, y, 'grey', t + n[y * 64 + x] * 0.04);
        height[y * 64 + x] = r < 4 ? 0.78 : 0.5;
      }
    }
    /* the beam under it, the one thing up here that did not move */
    for (let k = 0; k < 7; k++) {
      const y = (PURLIN + k) & 63;
      const t = k < 2 ? 0.18 : k < 5 ? 0.12 : 0.06;
      for (let x = 0; x < 64; x++) { p.ink(x, y, 'grey', t); height[y * 64 + x] = k < 2 ? 0.95 : 0.78; }
    }
    for (let x = 6; x < 64; x += 16) p.ink(x, (PURLIN + 3) & 63, 'rust', 0.16);
    p.emboss(height, 0.40, 0.85);
    /* A TORN EDGE GLOWS. Every hole in this is a place the fire came
       through, and the metal round one is the last of it still hot —
       which is also what stops the mask reading as a die-cut. */
    for (let y = 0; y < 64; y++)
      for (let x = 0; x < 64; x++) {
        if (!p.alphaAt(x, y)) continue;
        const open = !p.alphaAt(x + 1, y) || !p.alphaAt(x - 1, y) ||
                     !p.alphaAt(x, y + 1) || !p.alphaAt(x, y - 1);
        if (open) p.wash(x, y, 'fire', 0.30 + (n[y * 64 + x] * 0.22), 0.55);
      }
    speckle(64, 64, 110, 523 + v * 5, (x, y, a, b) => {
      if (p.alphaAt(x, y) && a > 0.93) p.ink(x, y, 'fire', 0.30 + b * 0.32);
    });
    return p.snap(0.4);
  };
}

/* ---------------------------------------------------------------------
   THE STEEL THE ROOF WAS SITTING ON

   Not a surface of the building: the SKIN of the joists and beams that
   js/ruin.js builds as geometry over a region whose deck has gone. So it
   is a material rather than a picture of anything — charred paint over
   hot-rolled steel, soot down the web, rust where the paint went before
   the fire did, and the odd coal still in a seam.

   It tiles both ways, because a member is a box and its ends are drawn
   with the same texture as its sides. The light comes from the top left
   like everything else in here.
   ------------------------------------------------------------------- */
/* What a building is once it is a heap of itself.

   THE SAME RULE RUINSTEL IS WRITTEN AROUND: a burnt thing is nearly
   black, and nearly black against a night sky is nothing at all. So this
   sits a third of the way up the grey, and what makes it read as debris
   rather than as a grey box is that it is COARSE — every lump of it is a
   different size and a different tone, at a scale you can count from ten
   feet, because the one thing rubble is not is uniform.

   THREE THINGS ARE IN IT and they are the three things this building is
   made of. Broken block, which is the pale angular stuff. Deck, which is
   the flat dark sheets lying at whatever angle they landed. And ash,
   which is the fine bed the rest of it is sitting in and the only part
   that tiles smoothly — so the lumps read as objects on a floor rather
   than as a pattern.

   AND CHARRED, so the shader keeps live coals moving in the gaps: see
   the note at the foot of RUINSTEL. A heap that is still warm is the
   difference between a building that has burnt down and a building that
   burnt down last year. */
const hash8 = (i, salt) => (Math.imul((i | 0) + 1 ^ salt, 2654435761) >>> 8) / 0x1000000;

T.RUBBLE = () => {
  const p = new Pix(64, 64, 560);
  const n = fbm(64, 64, 10, 3, 561);
  const grain = fbm(64, 64, 26, 2, 562);
  const height = new Float32Array(64 * 64);
  /* the ash bed */
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const v = n[y * 64 + x], g = grain[y * 64 + x];
    p.ink(x, y, 'grey', 0.19 + v * 0.09 + g * 0.05);
    height[y * 64 + x] = 0.3 + v * 0.2;
  }
  /* SHEETS OF DECK, flat and dark and lying at an angle. Drawn as runs
     rather than as rectangles: a torn sheet has one straight edge and
     three that are not. */
  speckle(64, 64, 9, 563, (x, y, a, b) => {
    const w = 10 + Math.floor(a * 20), h = 4 + Math.floor(b * 7);
    const lean = a > 0.5 ? 1 : -1;
    for (let dy = 0; dy < h; dy++) {
      const sx = x + Math.round(dy * lean * 0.6), run = w - Math.floor(dy * 0.8);
      for (let dx = 0; dx < run; dx++) {
        p.ink(sx + dx, y + dy, 'grey', 0.13 + b * 0.05);
        height[((y + dy) & 63) * 64 + ((sx + dx) & 63)] = 0.62 + b * 0.1;
      }
    }
  });
  /* BROKEN BLOCK, which is the pale angular half of a heap */
  /* BROKEN BLOCK, which is the pale angular half of a heap. The size
     range has to be WIDE — from a fist to a hearth slab — because the
     one thing that gives a heap away as a texture is every lump in it
     being the same size, and a floor is seen at every distance from
     underfoot to the far end of a bay. */
  speckle(64, 64, 42, 564, (x, y, a, b) => {
    const big = a > 0.82;
    const w = big ? 8 + Math.floor(a * 12) : 2 + Math.floor(a * 6);
    const h = big ? 6 + Math.floor(b * 9) : 2 + Math.floor(b * 5);
    /* and half of them are DARK: block that has been in a fire comes out
       every shade from bone to soot, and a heap of nothing but pale
       lumps reads as gravel */
    const key = b > 0.5 ? 'bone' : 'grey';
    const t = b > 0.5 ? 0.19 + a * 0.15 : 0.13 + a * 0.08;
    for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++) {
      /* knock the corners off: a lump of block is not a rectangle */
      if ((dx === 0 || dx === w - 1) && (dy === 0 || dy === h - 1)) continue;
      p.ink(x + dx, y + dy, key, t);
      height[((y + dy) & 63) * 64 + ((x + dx) & 63)] = 0.8 + a * 0.18;
    }
  });
  /* twisted reinforcement, and the odd length of stud */
  for (let k = 0; k < 7; k++) crack(p, (k * 23) % 64, (k * 41) % 64, 20 + k * 3, 'grey', 0.34, 566 + k, 1.4);
  p.emboss(height, 0.5, 0.86);
  /* AND A FEW COALS DOWN IN IT, where the air still gets. Few, because
     the shader puts live ones on anything charred and they move: baked
     coals are for the moment the fire has moved on and the heap is still
     warm, and two sets of them at once is a floor made of lava. */
  speckle(64, 64, 22, 567, (x, y, a, b) => {
    if (a < 0.8) return;
    p.ink(x, y, a > 0.96 ? 'yellow' : 'rust', 0.22 + b * 0.24);
  });
  p.grime(0.3, 'grey', 0.08, 568);
  return p.snap(0.45);
};

/* The cut face of the heap, which is what a region that is still up
   looks at across the step where its neighbour fell in. Same material,
   but a SECTION through it rather than a plan of it — the courses of
   what fell are visible in the face the way they are in a spoil heap,
   and the bottom of it is the slab the whole lot is sitting on. */
T.RUBFACE = () => {
  const p = new Pix(64, 64, 570);
  const n = fbm(64, 64, 14, 3, 571);
  const height = new Float32Array(64 * 64);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const v = n[y * 64 + x];
    /* darker at the bottom, where it has been under the rest of it */
    p.ink(x, y, 'grey', 0.14 + v * 0.10 + (1 - y / 63) * 0.07);
    height[y * 64 + x] = 0.35 + v * 0.25;
  }
  /* THE LAYERS IT WENT DOWN IN, and they are not courses. The first cut
     of this drew them straight and evenly spaced and what it made was
     brickwork — which is the wrong answer twice over, because a wall is
     the one thing this is not and because a straight line is the one
     thing a heap has none of. So each layer wanders by a couple of
     texels as it crosses, drops out where something big is in the way,
     and is a different distance from the last. */
  for (let y = 5, k = 0; y < 64; k++, y += 7 + Math.floor(hash8(k, 0x31) * 11)) {
    let ly = y;
    for (let x = 0; x < 64; x++) {
      ly += n[((ly + 17) & 63) * 64 + x] > 0.55 ? 1 : (n[(ly & 63) * 64 + x] < 0.4 ? -1 : 0);
      if (ly < 1) ly = 1; if (ly > 62) ly = 62;
      if (n[(ly & 63) * 64 + x] > 0.72) continue;          // where a lump interrupts it
      const w = 1 + Math.floor(n[(ly & 63) * 64 + x] * 2.5);
      for (let d = 0; d < w; d++) { p.ink(x, ly + d, 'grey', 0.10); height[((ly + d) & 63) * 64 + x] = 0.2; }
      p.ink(x, ly - 1, 'bone', 0.17 + n[(ly & 63) * 64 + x] * 0.08);
    }
  }
  speckle(64, 64, 26, 572, (x, y, a, b) => {
    const w = 3 + Math.floor(a * 7), h = 2 + Math.floor(b * 5);
    for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++) {
      p.ink(x + dx, y + dy, 'bone', 0.18 + a * 0.15);
      height[((y + dy) & 63) * 64 + ((x + dx) & 63)] = 0.85;
    }
  });
  p.emboss(height, 0.46, 0.88);
  speckle(64, 64, 20, 573, (x, y, a, b) => {
    if (a < 0.82) return;
    p.ink(x, y, a > 0.96 ? 'yellow' : 'rust', 0.22 + b * 0.22);
  });
  p.grime(0.34, 'grey', 0.09, 574);
  return p.snap(0.45);
};

T.RUINSTEL = () => {
  const p = new Pix(64, 64, 540);
  const n = fbm(64, 64, 12, 3, 541);
  const soot = fbm(64, 64, 6, 3, 542);
  const height = new Float32Array(64 * 64);
  for (let y = 0; y < 64; y++)
    for (let x = 0; x < 64; x++) {
      /* NOT BLACK, AND THE REASON IS THE PICTURE RATHER THAN THE
         MATERIAL. Charred steel really is nearly black, and nearly black
         against a night sky at this game's brightness — everything is
         written to the framebuffer in linear, so a surface at a tenth of
         the ramp lands at about two of 255 — is NOTHING. The frame is
         the only thing in a gutted region with the sky behind it and it
         has to read as a shape, so it sits a third of the way up the
         grey rather than a tenth: bright enough to be a silhouette's
         near edge, dark enough to still be burnt. */
      p.ink(x, y, 'grey', 0.26 + n[y * 64 + x] * 0.10);
      height[y * 64 + x] = 0.45 + n[y * 64 + x] * 0.1;
    }
  /* soot running DOWN it, which is the direction smoke went */
  for (let x = 0; x < 64; x++)
    for (let y = 0; y < 64; y++)
      if (soot[y * 64 + x] > 0.55) p.wash(x, y, 'grey', 0.08, (soot[y * 64 + x] - 0.55) * 1.5);
  /* rust in the seams, and a flange line down each side so a member
     reads as a section rather than as a bar */
  for (const fx of [1, 2, 61, 62]) {
    for (let y = 0; y < 64; y++) {
      p.ink(fx, y, 'rust', 0.24 + n[y * 64 + fx] * 0.10);
      height[y * 64 + fx] = 0.85;
    }
  }
  speckle(64, 64, 90, 543, (x, y, a, b) => {
    if (a > 0.86) { p.ink(x, y, 'rust', 0.20 + b * 0.14); height[y * 64 + x] = 0.6; }
  });
  p.emboss(height, 0.40, 0.92);
  /* AND WHAT IS STILL ALIGHT IN THE SEAMS OF IT, which is the other half
     of making it read: a coal is bright at any exposure, and a frame
     with a line of them down its web is legible across a dark shop in a
     way a grey bar is not. The live ones are the shader's, on the same
     clock as the burnt aisles under it; these are the ones baked in. */
  speckle(64, 64, 150, 544, (x, y, a, b) => {
    if (a > 0.88) p.ink(x, y, 'fire', 0.30 + b * 0.34);
  });
  return p.snap(0.4);
};

/* ---------------------------------------------------------------------
   THE SHELVING

   Uprights and whatever shelf did not fall. The uprights lean where the
   heat was worst, which is the one detail that stops a gutted gondola
   reading as a gondola somebody emptied.
   ------------------------------------------------------------------- */
for (let v = 0; v < RUIN_VARIANTS; v++) {
  const BAY = [21, 16, 26][v];
  const SHELVES = [[20, 44], [14, 32, 50], [36]][v];
  const LEAN = [2.2, 1.1, 3.4][v];
  T['RUINRACK' + v] = () => {
    const p = new Pix(64, 64, 500 + v * 17);
    const n = fbm(64, 64, 10, 3, 501 + v * 7);
    const height = new Float32Array(64 * 64);
    for (let y = 0; y < 64; y++)
      for (let x = 0; x < 64; x++) {
        p.ink(x, y, 'grey', 0.035 + n[y * 64 + x] * 0.04);
        height[y * 64 + x] = 0.05;
      }
    for (let u = 0; u < 64; u += BAY) {
      for (let y = 0; y < 64; y++) {
        const lean = Math.round(Math.sin((y / 63) * 2.1 + v) * LEAN);
        for (let x = u + lean; x < u + lean + 4; x++) {
          const xx = ((x % 64) + 64) % 64;
          p.ink(xx, y, 'rust', 0.125 + n[y * 64 + xx] * 0.06);
          height[y * 64 + xx] = 0.9;
        }
      }
    }
    for (const sy of SHELVES) {
      for (let x = 0; x < 64; x++) {
        const sag = Math.round(Math.sin((x / 63) * Math.PI) * 2.6);
        for (let y = sy + sag; y < sy + sag + 3 && y < 64; y++) {
          p.ink(x, y, 'grey', 0.13 - (y - sy - sag) * 0.03);
          height[y * 64 + x] = 0.75;
        }
      }
    }
    p.emboss(height, 0.40, 0.9);
    speckle(64, 64, 140, 502 + v * 3, (x, y, a, b) => {
      if (a > 0.93) p.ink(x, y, 'fire', 0.32 + b * 0.36);
    });
    return p.snap(0.42);
  };
}

/* Everything that can be on fire and is looked at afterwards. Walls and
   ceilings included: smoke blackens a ceiling long before flame reaches
   it, and a store where only the shelves changed looks like the shelves
   were swapped out. */
export const CHARRABLE = [
  'SHELFSTK', 'SHELFEMP', 'SHELFBAK', 'SHELFEND', 'CHILLER', 'FREEZDOR',
  'PRODAPPL', 'PRODCITR', 'PRODGREN', 'PRODROOT', 'PRODFLOW', 'PRODRIM',
  'DELICASE', 'CHECKOUT', 'CARDBOX', 'PALLET', 'TROLLEY',
  /* the checkstand and what is on the belt. A front end that burns and
     comes back with clean stainless and unmarked cartons on it is a
     front end nothing happened to. */
  'BELTSIDE', 'BELTRUB', 'SCANBED', 'BAGDECK', 'TILLTOP', 'TILLRAIL',
  'REGISTER', 'PINPAD', 'LANENUM', 'BAGRACK', 'IMPULSE',
  'GROCBOX', 'GROCBOX2', 'GROCCAN', 'GROCBAG', 'GROCTOP',
  'LINO', 'LINOWORN', 'CEILTILE', 'CEILFIT', 'CEILDECK', 'WALLPANL', 'TILEWALL',
  'STOCKFLR', 'STOCKWAL', 'DOORSTAF', 'DOORFRAM', 'DOORHEAD', 'DOORSIGN', 'DOCKDOOR', 'HAZARD',
  'CONCRETE', 'EXITDOOR',
  /* the strip: the neighbours burn too, once you have walked the fire
     out of the anchor and along the footway */
  'SHELFMIX', 'BAKECASE', 'UNITGLAS', 'UNITSHUT', 'UNITSHUT2', 'SHUTRAIL', 'SOFFIT',
  'FASCHEM', 'FASPHON', 'FASFOOD', 'PILASTER',
  /* and the shopfront, all five layers of it: glass sooted from the
     inside is the first thing a fire does that you can see from the
     car park, and it goes on the panes AND on what is behind them */
  'GLAZEA', 'GLAZEB', 'GLAZGAP', 'STORIN', 'UNITIN', 'SHOPSILL', 'SHOPFRAM',
  ...Array.from({ length: 3 }, (_, i) => 'FASVOID' + (i || '')),
  /* and the fourteen unnamed ones, which burn like any other board */
  ...Array.from({ length: 6 }, (_, i) => 'FASPLAIN' + i),
  /* and the sign goes with it, which is the shot worth having */
  'LOGO0', 'LOGO1', 'LOGO2', 'LOGO3',
  /* THE TOWN. A terrace of timber-framed houses sharing party walls is
     the best fuel in the world and every real fire service knows it, so
     nearly all of this burns. The brick does not — a brick shell stands
     there after the fire with its roof gone, which is what a burnt-out
     street looks like and is the whole reason js/ruin.js exists. */
  'CLAPBRD', 'VINYLSID', 'SHINGLE', 'GABLEND', 'PLASTER', 'WALLPAPR',
  'FLOORBRD', 'CARPETDM', 'KITCHTIL', 'STAIRTRD', 'SKIRTING',
  'WINDOWDK', 'WINDOWLT', 'WINDOWWD', 'HOUSDOOR', 'SHOPFRNT',
  'CHURCHST', 'STAINGLS', 'LOCKERS', 'BLACKBRD', 'PEWEND', 'SCHOOLBR',
  /* the facades: a door, a pane and a sill burn; a foundation and a
     gravestone do not */
  'FRNTDOOR', 'FRNTDOR2', 'FRNTDOR3', 'WINPANEL', 'WINPANED', 'WINSHADE', 'SILLWOOD',
  'CHURCHIN', 'WAINSCOT', 'PEWSEAT', 'PEWFRONT', 'PEWBACK', 'CHANCEL', 'ALTARFRT', 'ALTARTOP',
  'REREDOS', 'WINREVEL', 'SCHWINLT', 'SCHWINDK', 'DESKTOP', 'DESKFRNT', 'PAVERS',
  'CHAIRSIT', 'CHAIRLEG', 'CHAIRBAK', 'TEACHDSK',
  'BACKBORD', 'SCOREBRD', 'WALLBARS', 'PENNANT', 'AUDSEAT', 'CURTAIN', 'PROSCEN',
  'TROPHY', 'NOTICEBD', 'RADIATOR', 'FOUNTAIN', 'SCHCLOCK',
  /* THE OFFICE. Everything in a ground floor burns and burns well — it
     is carpet tile, fabric partitions, laminate and paper, which is why
     an office fire is the one every fire service dreads. The precast
     panel, the granite and the parapet do not: what is left of one of
     these is a concrete frame with the glass gone out of it. */
  'OFFWINLT', 'OFFWINDK', 'OFFDOOR', 'TERRAZZO', 'OFFCARP',
  'RECEPDSK', 'RECEPTOP', 'LIFTDOOR', 'CUBEPANL', 'CUBEDESK', 'FILECAB',
  'CONFTBL', 'WHITEBRD', 'VENDING', 'BREAKCAB', 'BREAKTOP', 'WATRCOOL',
  'DIRECTRY', 'COPIER', 'PLANTPOT',
];

/** The charred name for a texture, or the texture itself if it has none. */
export const charredName = n => (n && CHARRABLE.includes(n)) ? n + '_B' : n;

/* Everything that is a FIXTURE rather than a surface of the building.
   A gutted one is bare shelving; a gutted wall is studs. Tested against
   the name with any `_B` taken off, since gutting happens after
   charring and the name has already been through it once. */
const FIXTURES = new Set([
  'SHELFSTK', 'SHELFEMP', 'SHELFBAK', 'SHELFEND', 'CHILLER', 'FREEZDOR',
  'PRODAPPL', 'PRODCITR', 'PRODGREN', 'PRODROOT', 'PRODFLOW', 'PRODRIM',
  'DELICASE', 'CHECKOUT', 'SHELFMIX', 'BAKECASE', 'CARDBOX', 'PALLET',
  'BELTSIDE', 'BELTRUB', 'SCANBED', 'BAGDECK', 'TILLTOP',
]);

/** Every ruin texture there is, for whatever wants to check they exist. */
export const RUIN = [
  ...['WALL', 'FLR', 'DECK', 'RACK', 'HOLE']
    .flatMap(k => Array.from({ length: RUIN_VARIANTS }, (_, v) => `RUIN${k}${v}`)),
  'RUINSTEL', 'RUBBLE', 'RUBFACE',
];

/* A region's own number, stable across a reload and different from its
   neighbour's. Knuth's multiplicative hash, which is enough for this. */
const ruinHash = (i, salt) => (Math.imul((i + 1) ^ salt, 2654435761) >>> 8) / 0x1000000;

/**
 * What a region's surfaces become once it has gone completely.
 *
 * Returns only the slots that CHANGE, so the caller can leave the rest
 * alone.
 *
 * THE ROOF DOES NOT ALL GO, and getting that wrong made the first cut of
 * this look like a demolition rather than a fire. Every gutted region
 * opening straight to the sky meant a burnt-out store had no ceiling
 * anywhere, which is not what a burnt building looks like and is not
 * what holds one up: the deck burns through and falls in where the SPAN
 * is long and there is nothing under it, and over a corridor, a doorway
 * or a small room it stays exactly where it is, holed and charred and
 * still a roof.
 *
 * So a region needs two things to lose its ceiling: a span big enough to
 * fall (the caller passes how many cells of fuel grid it covers) and the
 * luck of the draw. Everything else keeps a burnt deck with its purlins
 * — which is where the exposed structure people actually see comes from,
 * because you are looking up at it rather than at a hole.
 */
export function guttedSurfaces(s, opts = {}) {
  const bare = n => (n && n.endsWith('_B')) ? n.slice(0, -2) : n;
  const v = Math.floor(ruinHash(s.index | 0, 0x5bd1) * RUIN_VARIANTS) % RUIN_VARIANTS;
  const out = {};
  const fixture = FIXTURES.has(bare(s.wallTex));
  if (s.wallTex && s.wallTex !== 'NONE') out.wallTex = (fixture ? 'RUINRACK' : 'RUINWALL') + v;
  if (s.floorTex && s.floorTex !== 'NONE') out.floorTex = (fixture ? 'RUINRACK' : 'RUINFLR') + v;

  /* ------------------------------------------------------------------
     AND THE ROOF, WHICH FAILS IN THREE STAGES

     It used to fail in one and a half: a small region kept a charred
     deck, and a big one either kept it or became SKY on a coin flip.
     What "became SKY" draws is NOTHING — the engine treats a sky ceiling
     as a hole and does not build a surface — so half a burnt store was a
     clean rectangular absence with a hard edge on it where the next
     aisle's ceiling was still up. That is a hole in the world, not a
     roof that has gone, and it is the thing the user asked to stop
     seeing.

     So, in order of how much fire has been through:

       THE DECK HOLDS. A small span, or a big one that got lucky:
       RUINDECK, which is the charred underside of a roof that is still
       a roof.

       THE DECK IS HOLED. RUINHOLE, which is MASKED — the burnt-through
       parts are not drawn at all, so you see the framing under it and
       the night past that, and the deck is still overhead between the
       holes. Half its light comes from the sky now, which is what `sky`
       is for.

       THE DECK IS GONE. Sky, as before — but the region is also flagged
       `ruinRoof`, and js/ruin.js builds the steel the deck was sitting
       on: joists across the span, beams on the column lines, some of
       them sagging and some of them down, with the odd panel of deck
       still lying across a bay. Which is what is standing in the
       photograph the morning after a shed like this goes.

     The middle stage is the one that was missing and it is the one that
     does most of the work, because it is what a roof looks like WHILE it
     is failing rather than after.
     ------------------------------------------------------------------ */
  if (s.ceilTex && s.ceilTex !== 'SKY') {
    const cells = opts.cells ?? 0;
    const bigSpan = cells >= 24;                      // about 25,000 square units
    const h = ruinHash(s.index | 0, 0x9e37);
    if (!bigSpan) out.ceilTex = 'RUINDECK' + v;
    else if (h < 0.42) { out.ceilTex = 'SKY'; out.sky = 1; out.ruinRoof = 'open'; }
    else if (h < 0.78) { out.ceilTex = 'RUINHOLE' + v; out.sky = 0.55; out.ruinRoof = 'holed'; }
    else out.ceilTex = 'RUINDECK' + v;
    /* which of the three ruins this region is, so the steel js/ruin.js
       hangs over it wears the same deck the region next door still has */
    out.ruinVariant = v;
  }
  /* and what a neighbour sees of the roof's edge where the heights step */
  if (s.upperTex && s.upperTex !== 'NONE') out.upperTex = 'RUINDECK' + v;
  return out;
}

/* --------------------------------------------------------------------
   AND THE THIRD STAGE, WHICH IS NOT A ROOM AT ALL

   A gutted region is a shell: walls with holes in them, a slab, and the
   steel that was under the deck still up. A COLLAPSED one is what is
   there after the steel lets go, and the whole of the difference is that
   there is no longer anything overhead and no longer anything at the
   sides — a heap on a slab, with the frame in it.

   THE FLOOR COMES UP RATHER THAN THE CEILING COMING DOWN, which is the
   only way a sector engine can say "heap". A ceiling on the floor is a
   region you cannot be in; a floor that has risen is one you clamber
   over, and it changes the two things a heap should change — you are
   higher when you are standing on it, and a neighbour that has not
   fallen sees a step up into it with rubble down the face of the step.

   AND IT RISES BY LESS THAN A STEP. Twenty against a MAX_STEP of
   twenty-four, which is the same bargain the wheel stops in the car park
   make: anything you can walk into, you can walk onto. A heap you cannot
   climb is a wall, it would trap whatever was standing in the region
   when it came down, and it would take the middle out of a burning
   building at exactly the moment the building is worth walking into.
   What makes it read as more than twenty units is the pile js/ruin.js
   drops on it, which is the frame that used to be over your head.

   AND THE WALLS COME DOWN TO A STUB, which is the other half of it and
   the half you see from outside. A region's ceiling is what its walls
   are drawn UP TO — so dropping the ceiling of a collapsed bay to a
   little over head height turns four storeys of shopfront into a
   knee-high perimeter of broken block with the sky over it, and turns
   the wall of the bay NEXT DOOR, which is still up, into an upper band
   above that stub: the scar down the inside of a building where the part
   that fell used to be attached. Both of those are free. They are the
   disagreement rule doing what it does, on numbers that moved.
   ------------------------------------------------------------------ */
export const RUBBLE_RISE = 20;
export const RUBBLE_STUB = 96;

export function collapsedSurfaces(s) {
  const v = Math.floor(ruinHash(s.index | 0, 0x5bd1) * RUIN_VARIANTS) % RUIN_VARIANTS;
  const out = {
    sky: 1, ruinVariant: v, ruinRoof: 'down',
    floorRise: RUBBLE_RISE, stub: RUBBLE_STUB,
  };
  if (s.floorTex && s.floorTex !== 'NONE') out.floorTex = 'RUBBLE';
  /* what is left of its own walls, which is the top of the heap seen
     from the side */
  if (s.wallTex && s.wallTex !== 'NONE') out.wallTex = 'RUBFACE';
  /* THE FACE OF THE STEP is what a region next door looks at now, and it
     is the cut edge of the heap rather than a wall: the disagreement rule
     draws a lower band from the LOWER side's lowerTex, so this is the one
     that has to be a section through rubble. */
  if (s.lowerTex && s.lowerTex !== 'NONE') out.lowerTex = 'RUBFACE';
  /* and what a bay that is STILL UP shows above the stub: the inside of
     its own wall, burnt, with nothing attached to it any more */
  out.upperTex = 'RUINWALL' + v;
  /* and there is nothing over it. Not a holed deck, not a charred one:
     the deck came down with the steel and it is in the heap. */
  out.ceilTex = 'SKY';
  return out;
}

/* --------------------------------------------------------------------
   HOW BIG A STREET LAMP IS, and where its parts are

   TWO HUNDRED AND FIFTY-SIX TALL. The old lamp was a hundred and
   twenty-eight, an acorn globe on a Main Street post a foot and a half
   over your head; this is a road light, and a road light's head hangs
   over the carriageway above anything that drives down it. The rest is
   the photograph's own proportions, read off it by the bakery and
   carried here as fractions: how wide it is for its height, where the
   pole stands across that width, where the underside of the luminaire
   is, and which slice of the whole picture each of the two tiles is.

   Every number the map and the light need is derived HERE and nowhere
   else — js/mapgeo.js stands the quads on `head`, `post` and `foot`,
   js/lamplight.js hangs the flare on `lens` — so the day the height
   changes, one line changes.
   ------------------------------------------------------------------ */
export const STREET_LAMP = (() => {
  const height = 256, width = height * ART_LAMP.aspect;
  const part = name => {
    const [u0, v0, u1, v1] = ART_CUTOUTS[name].box;
    return { u0, v0, u1, v1, w: (u1 - u0) * width, h: (v1 - v0) * height };
  };
  return { height, width, foot: ART_LAMP.foot, lens: ART_LAMP.lens,
           head: part('lamp_head'), post: part('lamp_post') };
})();

/* --------------------------------------------------------------------
   Textures whose world footprint is not their pixel size

   Two different reasons appear here and they are worth separating.

   FIXTURES are sized so that one repeat of the texture is exactly the
   height of the thing it is on. A shelf texture 64 tall on an 80-tall
   gondola would show a quarter of a second copy of itself cut off at the
   floor; declared as 80 it simply stretches by a quarter, which on a
   picture of tins nobody will ever notice. These numbers MUST match the
   fixture heights in the map, and the smoke test checks that they do.

   CEILINGS go the other way, covering four times the world they have
   pixels for, so that a light fitting lands every four tiles instead of
   in every one.
   ------------------------------------------------------------------ */
const SIZES = {
  KERB:     { w: 64, h: 16 },
  /* the town */
  KERBSTON: { w: 64, h: 12 },   // one repeat is one kerb, which is 12
  DRAIN:    { w: 48, h: 24 },   // one repeat is one grate
  ASPHPARK: { w: 192, h: 64 },  // one repeat is one parking bay, along x
  /* the grid world: one repeat is one CELL, which is what lets the
     floor's anchor put a line on every cell edge exactly — see
     floorAnchor in js/level.js and CELL in js/maps/grid.js */
  GRID:     { w: 64, h: 64, smooth: true },
  GRIDWALL: { w: 64, h: 64, smooth: true },
  GRIDBOX:  { w: 64, h: 64 },   // one repeat is one cell up a box's face
  ASPHPARV: { w: 64, h: 192 },  // and along y
  STAIRTRD: { w: 64, h: 16 },   // one repeat is one step
  SKIRTING: { w: 64, h: 16 },
  HOUSDOOR: { w: 64, h: 128 },  // one repeat is one door
  SHOPFRNT: { w: 64, h: 112 },  // one repeat is one shop's ground floor, which is a storey
  STAINGLS: { w: 64, h: 128 },
  /* ONE REPEAT IS ONE STOREY, which is 112. Worn at the default 64 a
     three-storey terrace came out with five and a quarter rows of
     windows up it, and a house with more window rows than floors is the
     one thing on a street nobody has to be told is wrong. */
  WINDOWDK: { w: 64, h: 112 },
  WINDOWLT: { w: 64, h: 112 },
  WINDOWWD: { w: 64, h: 112 },
  PEWEND:   { w: 64, h: 40 },
  /* THE TRIM, and every one of them is a BAND: the height is what the
     projecting piece of geometry is tall, so one repeat is the whole
     course and never a course and a half. See THE TRIM in this file. */
  WATERTBL: { w: 64, h: 16 },
  CORNICE:  { w: 64, h: 24 },
  TIEBEAM:  { w: 64, h: 24 },
  ORGANPIP: { w: 64, h: 96 },
  RAILING:  { w: 64, h: 96, masked: true },   // one repeat is one section of iron
  /* THE STREET LAMP: one repeat of each tile is that part of the lamp,
     at the size STREET_LAMP stands it. See the note on T.LAMPHEAD. */
  LAMPHEAD: { w: STREET_LAMP.head.w, h: STREET_LAMP.head.h, masked: true },
  LAMPPOST: { w: STREET_LAMP.post.w, h: STREET_LAMP.post.h, masked: true },
  ALTARRL:  { w: 64, h: 32 },
  HANDRAIL: { w: 64, h: 32 },
  GYMTRUSS: { w: 64, h: 32 },
  PULPITFR: { w: 64, h: 48 },
  BLEACHER: { w: 64, h: 24 },
  /* ONE REPEAT IS TWO LOCKERS, and two lockers are twenty-four units of
     corridor. Undeclared it was 64, which made a locker 32 by 64 — see
     the note on the texture. */
  LOCKERS:  { w: 24, h: 64 },
  SCHDOOR:  { w: 64, h: 80 },
  DATESTON: { w: 64, h: 32 },
  /* THE FENCES are declared in WORLD UNITS and one repeat of each is
     one BAY of it — post to post — so the post lands where a post goes.
     Chain link is further down, beside the mall's; a picket bay is four
     feet of fence and sixty-four units of run. */
  FENCEPIK: { w: 64, h: 48, masked: true },
  TOWNPOLE: { w: 64, h: 128, masked: true },
  /* WHAT STANDS PROUD OF A WALL OR ABOVE A ROOF. These skin the free
     boxes — see boxGeometry in js/mapgeo.js — and three of them are ONE
     REPEAT FOR THE WHOLE THING: a cap is sixteen tall, a post is
     ninety-six and eight square, a downpipe is eight square, so each
     wears its own picture once and not a fraction of one. */
  CHIMNEY:  { w: 64, h: 64 },
  CHIMCAP:  { w: 64, h: 16 },
  DOWNPIPE: { w: 8,  h: 64 },
  PORCHPST: { w: 8,  h: 96 },
  AWNING:   { w: 64, h: 32 },
  GABLEVNT: { w: 48, h: 32 },
  WINTRIM:  { w: 64, h: 12 },
  /* A HEDGE IS A BOX AND NOT A SPRITE, so it needs two: the clipped top
     you see over it, which tiles like any ground, and the side, which
     is ONE REPEAT FOR THE WHOLE HEIGHT the way a foundation is — dark
     at the roots, clipped bright along the top, and never a second
     clipped edge halfway up. HEDGE_H in js/maps/town.js is this 72. */
  HEDGETOP: { w: 64, h: 64 },
  HEDGESID: { w: 64, h: 72 },
  /* THE FACADES. One repeat is the whole thing: the foundation's
     thirty-two, a riser's sixteen, a door's forty-eight by eighty. */
  FOUNDATN: { w: 64, h: 32 },
  STONEFND: { w: 64, h: 32 },
  STEPFACE: { w: 64, h: 16 },
  FASCIA:   { w: 64, h: 8 },    // the board on a roof's edge, which is the lip storey's height
  FRNTDOOR: { w: 48, h: 80 },
  FRNTDOR2: { w: 48, h: 80 },
  FRNTDOR3: { w: 48, h: 80 },
  WAINSCOT: { w: 64, h: 40 },
  PEWFRONT: { w: 64, h: 16 },
  PEWBACK:  { w: 64, h: 40 },
  ALTARFRT: { w: 64, h: 40 },
  REREDOS:  { w: 128, h: 128 },
  DESKFRNT: { w: 64, h: 24, masked: true },
  /* THE CLASSROOM, each piece at the size of the piece. A desk top is
     one desk, a seat is one seat, and the chair back is declared at the
     twenty units you see it across from the side rather than at the six
     it is thick — the picture reads either way, which is the whole of
     why it is drawn the way it is. */
  DESKTOP:  { w: 28, h: 20 },
  CHAIRSIT: { w: 18, h: 20 },
  CHAIRLEG: { w: 18, h: 18, masked: true },
  CHAIRBAK: { w: 20, h: 40, masked: true },
  TEACHDSK: { w: 116, h: 32 },
  /* the gym, the auditorium, and what a school has on its walls */
  BACKBORD: { w: 96, h: 60, masked: true },
  SCOREBRD: { w: 128, h: 80 },
  WALLBARS: { w: 80, h: 128, masked: true },
  PENNANT:  { w: 72, h: 48, masked: true },
  AUDSEAT:  { w: 88, h: 28 },      // one repeat is four seats
  CURTAIN:  { w: 60, h: 160 },
  PROSCEN:  { w: 160, h: 128 },    // one repeat is the whole header
  TROPHY:   { w: 96, h: 76 },
  NOTICEBD: { w: 96, h: 56 },
  RADIATOR: { w: 96, h: 34, masked: true },
  FOUNTAIN: { w: 26, h: 32, masked: true },
  SCHCLOCK: { w: 26, h: 26, masked: true },
  /* THE OFFICE BLOCK. The elevation's four pieces are BANDS and each is
     declared at the height of the band it skins — the base course is
     twenty-four, the parapet forty, the pier is thirty-two wide — so
     none of them is ever drawn at a course and a half. The glazing is
     declared at the size of ONE BAY OF WINDOW, 128 by 72, which is the
     hole in the wall it is hung in. */
  /* ONE REPEAT IS FOUR PANELS, and a panel is 64 units square. Left at
     the default 64 the joints landed every 32 units — a precast panel
     forty-one inches across, which reads as tile and not as a building.
     Two units to the pixel is the stretch that buys it. */
  OFFPANEL: { w: 128, h: 128 },
  OFFBASE:  { w: 64, h: 32 },   // one repeat is the base course, which is FOUND
  OFFPARA:  { w: 64, h: 40 },
  OFFMULL:  { w: 32, h: 64 },
  OFFWINLT: { w: 128, h: 72 },
  OFFWINDK: { w: 128, h: 72 },
  OFFDOOR:  { w: 48, h: 96 },     // one repeat is one leaf
  OFFSIGN:  { w: 192, h: 40 },    // one repeat is the whole band
  /* and what is inside it, each at the size of the piece */
  RECEPDSK: { w: 64, h: 40 },
  RECEPTOP: { w: 64, h: 48 },
  LIFTDOOR: { w: 64, h: 96 },
  CUBEPANL: { w: 64, h: 44 },
  CUBEDESK: { w: 56, h: 56 },
  FILECAB:  { w: 32, h: 48 },
  CONFTBL:  { w: 64, h: 64 },
  WHITEBRD: { w: 96, h: 56 },
  VENDING:  { w: 44, h: 96 },
  BREAKCAB: { w: 64, h: 32 },
  BREAKTOP: { w: 64, h: 32 },
  WATRCOOL: { w: 24, h: 48, masked: true },
  DIRECTRY: { w: 64, h: 72 },
  COPIER:   { w: 48, h: 44 },
  PLANTPOT: { w: 40, h: 56, masked: true },
  GRAVESTN: { w: 24, h: 32 },
  STORBASE: { w: 64, h: 32 },
  BRANDBAND:{ w: 64, h: 96 },   // one repeat is the fascia band
  DOORTRAK: { w: 64, h: 16 },
  /* the staff door: a leaf, a frame and a sign. The leaf's size is
     declared for the same reason EXITDOOR's is — js/slidedoor.js maps
     a leaf 0..1 and never asks — so that the one number saying how big
     the door is lives with the picture of it. */
  DOORSTAF: { w: 64, h: 116 },
  DOORFRAM: { w: 48, h: 48 },
  DOORHEAD: { w: 64, h: 64 },
  DOORSIGN: { w: 80, h: 40 },
  EXITSIGN: { w: 96, h: 48 },
  PALLET:   { w: 64, h: 16, masked: true },
  TROLLEY:  { w: 64, h: 48, masked: true },

  /* fixtures — one repeat is the whole fixture */
  SHELFSTK: { w: 64, h: 80 },      // H_GONDOLA
  SHELFEMP: { w: 64, h: 80 },
  FREEZDOR: { w: 64, h: 80 },
  CHECKOUT: { w: 64, h: 40 },      // H_FIXTURE
  CHILLER:  { w: 64, h: 40 },

  /* THE CHECKSTAND. Every one of these is the size of the thing it is a
     picture of, and three of them are the size of a REGION: the belt,
     the scale plate and the bagging deck are floors of sectors 60 wide,
     anchored to their own run, so one repeat is exactly the band and
     there is no second copy of anything cut off at the far edge. The
     belt is the exception and is deliberate: 18 along makes one repeat
     one cleat, so a belt 108 long has six of them and always will,
     whatever the band is changed to. */
  BELTSIDE: { w: 64, h: 38 },      // H_BELT
  BELTRUB:  { w: 60, h: 18 },      // RUN_W across, one cleat along
  SCANBED:  { w: 60, h: 48 },      // RUN_W by the scanner band
  BAGDECK:  { w: 60, h: 80 },      // RUN_W by the bagging band
  TILLTOP:  { w: 64, h: 64 },      // laminate, and it tiles like laminate
  TILLRAIL: { w: 16, h: 8 },       // tube: nothing in it happens once
  /* THE THINGS THAT STAND ON IT are each declared at the size of the
     BOX, not at the size of the picture: a terminal is 22 by 24 in the
     world and 34 by 38 in texels, and declaring the texels would show
     two thirds of a till on a till. Where the two aspects differ the
     picture stretches, so they are painted to match. */
  REGISTER: { w: 22, h: 24 },      // the long face of the terminal
  PINPAD:   { w: 12, h: 12 },
  LANENUM:  { w: 52, h: 42 },      // the lit panel, read from the back
  BAGRACK:  { w: 30, h: 26 },
  IMPULSE:  { w: 56, h: 28 },      // half the run: the sweets repeat twice

  /* THE SHOPPING, each at the size of the box it mostly goes on, so the
     front of a carton is one whole front of a carton. See THE SHOPPING
     in the bakery above for why these are not tiling sizes — and note
     that they are SMALLER than the pictures, which are painted at the
     same aspect and a comfortable number of texels. A texture's pixel
     size and the amount of world one repeat covers are two different
     numbers and always have been. */
  GROCBOX:  { w: 15, h: 23 },
  GROCBOX2: { w: 18, h: 15 },
  GROCCAN:  { w: 14, h: 11 },
  GROCBAG:  { w: 17, h: 14 },
  GROCTOP:  { w: 16, h: 12 },
  /* A bin's top is a FLOOR, so its 64 by 64 is two metres of shop
     rather than the height of a fixture; the crate boards round it are
     two to a repeat, so they land at eight units whatever they are cut
     against. */
  PRODAPPL: { w: 64, h: 64 },
  PRODCITR: { w: 64, h: 64 },
  PRODGREN: { w: 64, h: 64 },
  PRODROOT: { w: 64, h: 64 },
  PRODFLOW: { w: 64, h: 64 },
  PRODRIM:  { w: 64, h: 16 },
  DELICASE: { w: 64, h: 40 },
  SHELFMIX: { w: 64, h: 80 },      // H_GONDOLA
  BAKECASE: { w: 64, h: 40 },      // H_FIXTURE

  /* THE LOGO. One repeat is one quarter of the sign, and these numbers
     are the sign box in the map divided by two — SIGN_W / 2 across and
     SIGN_H / 2 up. Change one and you must change the other or the logo
     stretches; the smoke test checks that they still agree. */
  LOGO0:    { w: 140, h: 112 },
  LOGO1:    { w: 140, h: 112 },
  LOGO2:    { w: 140, h: 112 },
  LOGO3:    { w: 140, h: 112 },

  /* the strip */
  BAYROW:   { w: 186, h: 180 },    // one repeat is one parking bay
  /* ONE REPEAT IS THE WHOLE BAND. The parapet band is CEIL_SKY minus
     CEIL_EDGE, which is 152, and this was declared 32 tall — so it
     tiled four and three quarter times up a wall whose whole job is to
     be one unbroken surface, and whatever was in it got counted. See
     T.PARAPET. 128 across puts a panel joint every four metres. */
  PARAPET:  { w: 128, h: 152 },
  /* THE PLANT ON A STRIP MALL — see WHAT A STRIP MALL HAS THAT A SHED
     DOES NOT, further down this file. All of these are free boxes (see
     boxGeometry in js/mapgeo.js) and every one of them is declared at
     the size of the thing it is a picture of, so ONE REPEAT IS ONE
     OBJECT: one length of coping, one luminaire, one wheel stop, one
     cabinet. Get that wrong and a wall pack becomes wallpaper of wall
     packs, which is the mistake the agent's TO LET board was. */
  COPING:   { w: 64, h: 14 },      // one length of pressed capping
  PIERCAP:  { w: 64, h: 12 },
  RTU:      { w: 64, h: 48 },      // the packaged unit's casing
  RTUTOP:   { w: 64, h: 64 },      // and the fan cowls, seen from above
  DUCTWORK: { w: 48, h: 32 },
  ROOFLADR: { w: 32, h: 64 },      // one storey of caged ladder
  GUTTER:   { w: 64, h: 12 },
  SIGNEDGE: { w: 64, h: 8 },       // the rim of a fascia tray
  SHUTBOX:  { w: 64, h: 24 },
  WALLPACK: { w: 32, h: 24 },      // ONE FITTING, and the box is 32 by 24
  CONDENSR: { w: 48, h: 40 },      // one condensing unit
  METERBOX: { w: 32, h: 40 },      // one cabinet
  SKIPSIDE: { w: 64, h: 48 },
  WHEELSTP: { w: 120, h: 12 },     // one precast stop, and a stop is 120
  CORRAIL:  { w: 64, h: 16 },
  FASCHEM:  { w: 64, h: 96 },      // one repeat is one sign
  FASPHON:  { w: 64, h: 96 },
  FASFOOD:  { w: 64, h: 96 },
  /* THE DEAD TRAYS, same band as every other fascia. */
  FASVOID:  { w: 64, h: 96 },
  FASVOID1: { w: 64, h: 96 },
  FASVOID2: { w: 64, h: 96 },
  /* THE SHUT SHOPFRONTS, and these two are the only textures in the
     game whose declared size is chosen to make a wall come out in WHOLE
     repeats: a shopfront is 432 by 220, so 72 by 55 is six across and
     four up with nothing left over. At 64 by 64 it was six and three
     quarters by three and a half, and the quarter and the half were the
     whole problem — see THE SHUT ONES. */
  UNITSHUT:  { w: 72, h: 55 },
  UNITSHUT2: { w: 72, h: 55 },
  SHUTRAIL:  { w: 64, h: 14 },
  /* THE SHOPFRONT, IN LAYERS — see that section above for what the five
     of them are. The module is one PANE: 96 wide by 160 tall, which is
     the hole cut in the wall between the stall riser and the head, so
     one repeat of a pane texture is one pane and there is no partial
     repeat of a sheet of glass anywhere on the parade. The riser under
     it is the same 96 across, so the cill nosing lands once.

     SHOPFRAM is the exception and is meant to be: it is an aluminium
     EXTRUSION, the same section all the way along, so it is declared at
     a size that has nothing to do with any piece it is cut into and
     tiles honestly at any partial repeat. */
  GLAZEA:   { w: 96, h: 160, masked: true },
  GLAZEB:   { w: 96, h: 160, masked: true },
  GLAZGAP:  { w: 96, h: 160 },
  STORIN:   { w: 96, h: 160 },
  UNITIN:   { w: 96, h: 160 },
  SHOPSILL: { w: 96, h: 32 },
  SHOPFRAM: { w: 48, h: 48 },
  /* the unbranded ones, same band as every other fascia */
  ...Object.fromEntries(Array.from({ length: 6 }, (_, i) => ['FASPLAIN' + i, { w: 64, h: 96 }])),
  /* A ROOF WITH HOLES IN IT is masked and coarse: 128 world units to
     the tile, so a hole is sixty across and the repeat is long enough
     not to read as a pattern down a burnt-out aisle. */
  ...Object.fromEntries(Array.from({ length: 3 }, (_, i) =>
    ['RUINHOLE' + i, { w: 128, h: 128, masked: true }])),
  TROLLRAI: { w: 64, h: 48, masked: true },
  /* world units, and the height is the fence's height — see midHeight */
  CHAINLNK: { w: 128, h: 96, masked: true },
  /* Door leaves are mapped 0..1 by the slider, never by the wall
     builder, so these numbers only matter if one ends up on a line. */
  SLIDEL:   { w: 96, h: 248, masked: true },
  SLIDER:   { w: 96, h: 248, masked: true },
  EXITDOOR: { w: 104, h: 116 },

  /* ceilings — four tiles to a texture, so the fittings are spaced out */
  CEILFIT:  { w: 256, h: 256 },
};

/* THE ONE SURFACE THE FIRE DOES MORE THAN DARKEN. Everything else in
   the shop is a material and charring it is enough; the ceiling has a
   LIGHT painted into it, and a darker picture of a light is still a
   picture of a light. So the fitting is drawn again over the charred
   ceiling with `lit` false — dead tubes with pieces out of them, no
   diffuser, the flange's shadow back, and the ballast's scorch — which
   is the burst lamp sprite's old job, done in the place that knows the
   fire has been through. Same box fitTray is called with above. */
/* =====================================================================
   THE TOWN

   Forty-odd surfaces for the thing on the other side of the ring road.
   The rule that governs every one of them is the one the fascia taught:
   WHAT TILES IS MATERIAL AND NEVER A WORD. A brick is a brick sixty
   times over and nobody counts; SELLWRONG SUPERSTORE sixty times across
   a wall is a joke that stops being funny in one second.

   The second rule is that a town at night is a GRID OF LIT RECTANGLES
   and very little else. So the windows are the ones that had the care
   taken over them, and everything else is here to be the dark between.
   ===================================================================== */

/* ---------- outside: what a house is made of ---------- */

/** Courses of brick with the mortar between them. `keys` picks the clay. */
function brickwork(p, seed, key, lo, hi, mortarT = 0.42, courseH = 8, brickW = 22) {
  const rng = makeRng(seed);
  p.fill('grey', mortarT);
  for (let row = 0; row * courseH < p.h; row++) {
    const y0 = row * courseH;
    /* half a brick's stagger every other course, which is a stretcher
       bond and is what every house in America is */
    const off = (row % 2) ? -brickW / 2 : 0;
    for (let bx = -brickW; bx < p.w + brickW; bx += brickW) {
      const x0 = Math.round(bx + off) + 1;
      const t = lo + rng() * (hi - lo);
      for (let y = y0 + 1; y < y0 + courseH - 1 && y < p.h; y++)
        for (let x = x0; x < x0 + brickW - 2; x++) {
          const xx = ((x % p.w) + p.w) % p.w;
          p.ink(xx, y, key, t + (rng() - 0.5) * 0.05);
        }
    }
  }
}

T.BRICKRED = () => {
  const p = new Pix(64, 64, 31);
  brickwork(p, 31, 'rust', 0.30, 0.52);
  p.grime(0.35, 'grey', 0.08, 5);
  /* the damp course, two rows of something greyer near the bottom */
  return p.snap(0.5);
};

T.BRICKPNT = () => {
  /* Painted brick — the same bond with the texture flattened under a
     coat of cream, which is half the houses on any American street and
     is the cheapest variation there is. */
  const p = new Pix(64, 64, 37);
  brickwork(p, 37, 'bone', 0.46, 0.60, 0.40);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.wash(x, y, 'bone', 0.62, 0.42);
  p.grime(0.30, 'grey', 0.07, 9);
  return p.snap(0.5);
};

/** Lapped horizontal boards with a shadow under each lap. */
function lapSiding(p, seed, key, lo, hi, boardH) {
  const rng = makeRng(seed);
  for (let y = 0; y < p.h; y++) {
    const k = y % boardH;
    /* each board is a touch lighter at its bottom edge where it stands
       proud, and there is a hard shadow line under the lap above it */
    let t = lo + (hi - lo) * (k / boardH) * 0.55 + rng() * 0.03;
    if (k === 0) t = lo * 0.62;                     // the shadow of the lap
    else if (k === boardH - 1) t = hi;
    for (let x = 0; x < p.w; x++) p.ink(x, y, key, t);
  }
}

T.CLAPBRD = () => {
  const p = new Pix(64, 64, 41);
  lapSiding(p, 41, 'bone', 0.40, 0.58, 8);
  /* the butt joints, which are what stop it reading as a gradient */
  const rng = makeRng(43);
  for (let row = 0; row < 8; row++) {
    const x = Math.floor(rng() * 64);
    for (let y = row * 8 + 1; y < row * 8 + 8; y++) p.ink(x, y, 'grey', 0.22);
  }
  p.grime(0.28, 'grey', 0.07, 11);
  return p.snap(0.5);
};

T.VINYLSID = () => {
  /* Vinyl is clapboard with no butt joints and a colour nothing grows —
     the giveaway is that it is TOO even, so this one gets no grain at
     all and only the faintest grime. */
  const p = new Pix(64, 64, 47);
  lapSiding(p, 47, 'blue', 0.30, 0.44, 8);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.wash(x, y, 'bone', 0.52, 0.30);
  p.grime(0.10, 'grey', 0.05, 13);
  return p.snap(0.5);
};

T.STUCCO = () => {
  const p = new Pix(64, 64, 53);
  aggregate(p, 53, { baseKey: 'bone', baseLo: 0.42, baseHi: 0.54,
    grades: [{ count: 400, min: 0.3, max: 0.9, key: 'bone', lo: 0.36, hi: 0.60 }] });
  p.grime(0.34, 'grey', 0.09, 17);
  return p.snap(0.5);
};

T.SHINGLE = () => {
  /* Asphalt shingle: three-tab, so the keyway slots are every third of
     a course and the courses are staggered. Read from below at a low
     angle it is a grey stripe, which is exactly what a roof is. */
  /* WEATHERED, not tar: the first cut sat at a fifth of grey, and from
     the far end of a street at dawn a roof at a fifth of grey is a
     black wedge on top of the wall — which is what the user drew a
     ring round. A shingle that has had ten summers on it is the grey
     of a pavement, and reads as a surface with courses on it. */
  /* THE GREY RAMP IS DARK. Its half-way stop is 92 of 255 and its
     gamma 1.3, so a shingle inked at four tenths is fifty-eight, and
     the bone the walls are inked with at the same four tenths is
     ninety: a roof drawn at what reads as a sensible grey came out at
     half the wall's brightness, and the daylight banding halved it
     again. So the courses are inked in the upper half of the ramp and
     the shadow lines below them carry the contrast. */
  const p = new Pix(64, 64, 59);
  const rng = makeRng(59);
  p.fill('grey', 0.58);
  const CH = 16;
  for (let row = 0; row * CH < 64; row++) {
    const y0 = row * CH, off = (row % 2) ? 10 : 0;
    for (let y = y0; y < y0 + CH && y < 64; y++) {
      const edge = (y === y0);
      for (let x = 0; x < 64; x++) {
        const t = 0.58 + rng() * 0.12 + (y - y0) / CH * 0.10;
        p.ink(x, y, 'grey', edge ? 0.34 : t);
      }
    }
    /* the keyways */
    for (let k = 0; k < 3; k++) {
      const x = (off + k * 21 + 64) % 64;
      for (let y = y0; y < y0 + CH - 4 && y < 64; y++) p.ink(x, y, 'grey', 0.38);
    }
  }
  p.grime(0.30, 'grey', 0.22, 61);
  return p.snap(0.5);
};

T.FASCIA = () => {
  /* The board on the edge of a roof, eight tall, which is the one
     thing that makes an eave read from the pavement under it: a white
     line along the top of the wall with the shadow of the gutter on
     it. Worn by the LIP storey over every eave strip — see underEaves
     in js/maps/town.js. */
  const p = new Pix(64, 8, 91);
  p.fill('bone', 0.66);
  p.hline(0, 63, 0, 'grey', 0.26);              // the gutter's shadow
  p.hline(0, 63, 1, 'grey', 0.40);
  p.hline(0, 63, 2, 'bone', 0.78);              // the lit top edge of the board
  p.hline(0, 63, 7, 'grey', 0.44);              // and its drip edge
  const rng = makeRng(92);
  for (let x = 0; x < 64; x++) if (rng() < 0.08) p.vline(x, 3, 6, 'bone', 0.58);
  return p.snap(0.5);
};

T.EAVESOFT = () => {
  /* The underside of an eave: painted boards running along the wall,
     in shadow, with the vent slots that let the attic breathe. A
     ceiling, so it tiles from the world origin like every flat. */
  const p = new Pix(64, 64, 93);
  p.fill('bone', 0.46);
  for (let y = 0; y < 64; y += 8) {
    p.hline(0, 63, y, 'grey', 0.30);            // the joint between boards
    p.hline(0, 63, y + 1, 'bone', 0.52);
  }
  const rng = makeRng(94);
  for (let i = 0; i < 40; i++) p.ink(Math.floor(rng() * 64), Math.floor(rng() * 64), 'bone', 0.40);
  /* one vent strip across the middle */
  p.box(0, 28, 64, 8, 'grey', 0.24);
  for (let x = 2; x < 64; x += 4) p.vline(x, 29, 34, 'grey', 0.12);
  p.hline(0, 63, 28, 'bone', 0.36);
  p.hline(0, 63, 35, 'bone', 0.36);
  p.grime(0.20, 'grey', 0.06, 95);
  return p.snap(0.5);
};

T.GABLEND = () => {
  /* The triangle at the end of a roof: the same shingle turned so the
     courses run the other way would be wrong, so this is BOARD — which
     is what a gable usually is — with a vent in the middle of it. */
  const p = new Pix(64, 64, 67);
  lapSiding(p, 67, 'bone', 0.34, 0.48, 6);
  p.box(26, 22, 12, 14, 'grey', 0.14);
  for (let y = 23; y < 35; y += 2) p.hline(27, 36, y, 'grey', 0.30);
  p.frame(26, 22, 12, 14, 'bone', 0.52);
  p.grime(0.26, 'grey', 0.07, 71);
  return p.snap(0.5);
};

T.ROOFSEAM = () => {
  /* Standing seam, for the church hall and the gas station canopy. */
  const p = new Pix(64, 64, 73);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', 0.26);
  for (const sx of [0, 16, 32, 48]) {
    p.vline(sx, 0, 63, 'grey', 0.14);
    p.vline((sx + 1) % 64, 0, 63, 'bone', 0.40);
  }
  p.grime(0.22, 'rust', 0.05, 79);
  return p.snap(0.5);
};

/* ---------- the street ---------- */

T.SIDEWALK = () => {
  const p = new Pix(64, 64, 83);
  aggregate(p, 83, { baseKey: 'bone', baseLo: 0.30, baseHi: 0.40,
    grades: [{ count: 150, min: 0.4, max: 1.0, key: 'bone', lo: 0.22, hi: 0.44 },
             { count: 40,  min: 0.4, max: 1.1, key: 'grey', lo: 0.24, hi: 0.36 }] });
  /* THE SCORED JOINT, which is the whole of what makes concrete read as
     sidewalk rather than as floor: one line across every four feet with
     a tooled edge either side of it. */
  p.hline(0, 63, 0, 'grey', 0.16);
  p.hline(0, 63, 1, 'bone', 0.46);
  p.hline(0, 63, 63, 'bone', 0.42);
  crack(p, 8, 30, 40, 'grey', 0.14, 89);
  p.grime(0.30, 'grey', 0.08, 97);
  return p.snap(0.5);
};

T.DRAIN = () => {
  /* A STORM DRAIN: the grate in the gutter, cast iron with five slots
     and a frame, worn at 48 by 24 so one repeat is one grate. Sits at
     road level against the kerb, which is where the water goes. */
  const p = new Pix(64, 32, 99);
  aggregate(p, 99, { baseKey: 'grey', baseLo: 0.10, baseHi: 0.16,
    grades: [{ count: 60, min: 0.3, max: 0.8, key: 'grey', lo: 0.12, hi: 0.20 }] });
  p.box(6, 4, 52, 24, 'grey', 0.30);             // the frame
  p.frame(6, 4, 52, 24, 'grey', 0.38);
  for (let k = 0; k < 5; k++) {                  // the slots
    const x = 12 + k * 9;
    p.box(x, 8, 5, 16, 'grey', 0.04);
    p.vline(x, 8, 23, 'grey', 0.22);
  }
  p.hline(6, 57, 4, 'bone', 0.44);               // the lit edge of the frame
  p.grime(0.30, 'grey', 0.08, 98);
  return p.snap(0.5);
};

const parkingBay = (seed, along) => {
  /* A PARKING BAY, and one repeat is one bay: worn 192 along the kerb
     and 64 across, so every three units of road is one texel — which is
     why the aggregate here is fine and low in contrast, and why the
     white line is a single texel, which at three units is a painted
     line. The bays are laid from the world origin, and so are the vans
     — see shoulderRun in js/maps/town.js. */
  const p = new Pix(64, 64, seed);
  aggregate(p, seed, { baseKey: 'grey', baseLo: 0.12, baseHi: 0.16,
    grades: [{ count: 200, min: 0.3, max: 0.7, key: 'grey', lo: 0.13, hi: 0.19 }] });
  p.grime(0.30, 'grey', 0.07, seed + 2);
  if (along === 'x') p.vline(0, 0, 63, 'bone', 0.60); else p.hline(0, 63, 0, 'bone', 0.60);
  return p.snap(0.5);
};
T.ASPHPARK = () => parkingBay(171, 'x');
T.ASPHPARV = () => parkingBay(173, 'y');

T.KERBSTON = () => {
  /* Sixteen tall, which is more than the twelve a kerb stands and
     leaves a course of it buried, the way a real one is. */
  const p = new Pix(64, 16, 101);
  aggregate(p, 101, { baseKey: 'grey', baseLo: 0.30, baseHi: 0.40,
    grades: [{ count: 90, min: 0.3, max: 0.9, key: 'bone', lo: 0.26, hi: 0.40 }] });
  p.hline(0, 63, 0, 'bone', 0.50);            // the nosing catches the light
  for (const jx of [0, 32]) p.vline(jx, 0, 15, 'grey', 0.18);
  p.grime(0.34, 'grey', 0.08, 103);
  return p.snap(0.5);
};

T.GRASSVRG = () => {
  const p = new Pix(64, 64, 107);
  const n = fbm(64, 64, 12, 3, 107);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'green', 0.16 + n[y * 64 + x] * 0.16);
  const rng = makeRng(109);
  for (let i = 0; i < 700; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    p.ink(x, y, 'olive', 0.18 + rng() * 0.18);
  }
  return p.snap(0.5);
};

T.CROSSWLK = () => {
  /* One bar and the gap after it, so a crossing is a strip of this
     tiled across the mouth of a junction. */
  const p = new Pix(64, 64, 113);
  aggregate(p, 113, { baseKey: 'grey', baseLo: 0.10, baseHi: 0.16,
    grades: [{ count: 120, min: 0.3, max: 0.8, key: 'grey', lo: 0.12, hi: 0.20 }] });
  for (let y = 0; y < 64; y++) for (let x = 8; x < 40; x++) p.ink(x, y, 'bone', 0.52 + (x % 3) * 0.02);
  p.grime(0.42, 'grey', 0.10, 127);
  return p.snap(0.5);
};

T.ASPHOLD = () => {
  /* The older of the two asphalts — the residential streets, laid a
     decade before the mall's car park and patched twice since. */
  const p = new Pix(64, 64, 131);
  aggregate(p, 131, { baseKey: 'grey', baseLo: 0.11, baseHi: 0.18,
    grades: [{ count: 260, min: 0.3, max: 1.0, key: 'grey', lo: 0.13, hi: 0.24 },
             { count: 60,  min: 0.4, max: 1.2, key: 'bone', lo: 0.10, hi: 0.18 }] });
  crack(p, 12, 4, 58, 'grey', 0.09, 137);
  crack(p, 44, 20, 40, 'grey', 0.09, 139, 1.3);
  /* a patch, darker and squarer than anything round it */
  for (let y = 36; y < 56; y++) for (let x = 6; x < 30; x++) p.ink(x, y, 'grey', 0.09);
  p.grime(0.36, 'grey', 0.07, 149);
  return p.snap(0.5);
};

/* ---------- inside a house ---------- */

T.PLASTER = () => {
  const p = new Pix(64, 64, 151);
  const n = fbm(64, 64, 20, 2, 151);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.44 + n[y * 64 + x] * 0.08);
  crack(p, 30, 8, 26, 'bone', 0.30, 157);
  p.grime(0.16, 'grey', 0.05, 163);
  return p.snap(0.5);
};

T.WALLPAPR = () => {
  /* A stripe, because a stripe is a pattern that tiles at any scale and
     does not turn into a word. */
  const p = new Pix(64, 64, 167);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'olive', 0.34 + ((x % 16) < 6 ? 0.10 : 0));
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.wash(x, y, 'bone', 0.54, 0.28);
  p.grime(0.20, 'brown', 0.05, 173);
  return p.snap(0.5);
};

T.FLOORBRD = () => {
  const p = new Pix(64, 64, 179);
  const rng = makeRng(179);
  for (let b = 0; b < 8; b++) {
    const y0 = b * 8, t = 0.26 + rng() * 0.12;
    for (let y = y0; y < y0 + 8; y++) for (let x = 0; x < 64; x++) {
      const g = Math.sin((x * 0.7 + b * 13) * 0.6) * 0.03;
      p.ink(x, y, 'brown', t + g + (y === y0 ? -0.12 : 0));
    }
    const j = Math.floor(rng() * 64);
    for (let y = y0 + 1; y < y0 + 8; y++) p.ink(j, y, 'brown', 0.14);
  }
  p.grime(0.22, 'grey', 0.05, 181);
  return p.snap(0.5);
};

T.CARPETDM = () => {
  const p = new Pix(64, 64, 191);
  aggregate(p, 191, { baseKey: 'red', baseLo: 0.16, baseHi: 0.24,
    grades: [{ count: 900, min: 0.2, max: 0.7, key: 'brown', lo: 0.14, hi: 0.26 }] });
  p.grime(0.30, 'grey', 0.06, 193);
  return p.snap(0.5);
};

T.KITCHTIL = () => {
  const p = new Pix(64, 64, 197);
  p.fill('bone', 0.52);
  for (const g of [0, 16, 32, 48]) { p.hline(0, 63, g, 'grey', 0.30); p.vline(g, 0, 63, 'grey', 0.30); }
  const rng = makeRng(199);
  for (let ty = 0; ty < 4; ty++) for (let tx = 0; tx < 4; tx++)
    if (rng() < 0.25) for (let y = ty * 16 + 1; y < ty * 16 + 16; y++)
      for (let x = tx * 16 + 1; x < tx * 16 + 16; x++) p.ink(x, y, 'cyan', 0.34);
  p.grime(0.20, 'grey', 0.05, 211);
  return p.snap(0.5);
};

T.STAIRTRD = () => {
  /* One repeat is one step: sixteen of rise with the nosing on top, so
     a flight tiled with it has a tread line exactly where a tread is. */
  const p = new Pix(64, 16, 223);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.22 + y / 16 * 0.10);
  p.hline(0, 63, 0, 'bone', 0.44);
  p.hline(0, 63, 1, 'brown', 0.14);
  p.grime(0.24, 'grey', 0.06, 227);
  return p.snap(0.5);
};

T.SKIRTING = () => {
  const p = new Pix(64, 16, 229);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.50);
  p.hline(0, 63, 0, 'bone', 0.62);
  p.hline(0, 63, 3, 'grey', 0.30);
  p.hline(0, 63, 15, 'grey', 0.22);
  return p.snap(0.5);
};

/* ---------- the windows, which are the ones that matter ---------- */

/** A sash window in a wall: the frame, the glass, and the muntins. */
function sash(p, lit) {
  const glassKey = lit ? 'yellow' : 'blue';
  const glassT = lit ? 0.72 : 0.12;
  p.box(14, 10, 36, 44, 'bone', 0.44);                 // the casing
  p.box(17, 13, 30, 38, glassKey, glassT);             // the glass
  if (lit) {
    /* the light does not fall evenly on a room — it comes off one lamp
       in a corner, so the pane nearest it is the bright one */
    for (let y = 13; y < 51; y++) for (let x = 17; x < 47; x++) {
      const d = Math.hypot(x - 22, y - 20) / 34;
      p.ink(x, y, 'yellow', Math.max(0.30, glassT - d * 0.34));
    }
    /* and somebody is in there, as a shape and never as a person */
    p.box(24, 30, 9, 21, 'brown', 0.22);
  }
  p.vline(31, 13, 50, 'bone', 0.50);                   // the meeting rail
  p.vline(32, 13, 50, 'bone', 0.50);
  p.hline(17, 46, 31, 'bone', 0.50);
  p.hline(17, 46, 32, 'bone', 0.50);
  p.frame(14, 10, 36, 44, 'bone', 0.56);
  p.hline(12, 51, 54, 'bone', 0.50);                   // the sill
  p.hline(12, 51, 55, 'grey', 0.26);
}

T.WINDOWDK = () => {
  const p = new Pix(64, 64, 233);
  brickwork(p, 233, 'rust', 0.30, 0.52);
  sash(p, false);
  p.grime(0.30, 'grey', 0.07, 239);
  return p.snap(0.5);
};

T.WINDOWLT = () => {
  const p = new Pix(64, 64, 241);
  brickwork(p, 241, 'rust', 0.28, 0.48);
  sash(p, true);
  p.grime(0.22, 'grey', 0.06, 251);
  return p.snap(0.5);
};

T.WINDOWWD = () => {
  /* the same window in a clapboard wall, for the half of the street
     that is not brick */
  const p = new Pix(64, 64, 257);
  lapSiding(p, 257, 'bone', 0.38, 0.54, 8);
  sash(p, true);
  p.grime(0.22, 'grey', 0.06, 263);
  return p.snap(0.5);
};

T.HOUSDOOR = () => {
  /* SIXTY-FOUR PIXELS, worn a hundred and twenty-eight units tall — see
     SIZES, and see BRANDBAND, which is the same trick. The 64-pixel rule
     is about the picture and not about how big the picture is on a wall,
     and one repeat of this is one door. */
  const p = new Pix(64, 64, 269);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'green', 0.18 + (y / 64) * 0.05);
  p.frame(6, 2, 52, 60, 'green', 0.30);
  for (const [py, ph] of [[7, 20], [31, 26]]) {
    p.frame(14, py, 36, ph, 'green', 0.12);
    p.box(16, py + 2, 32, ph - 4, 'green', 0.24);
  }
  p.disc(50, 33, 2, 'yellow', 0.62);                   // the knob
  p.box(20, 4, 24, 5, 'yellow', 0.40);                 // the fanlight
  p.grime(0.24, 'grey', 0.06, 271);
  return p.snap(0.5);
};

/* ---------- civic ---------- */

T.SCHOOLBR = () => {
  /* Darker brick with a limestone band across it, which is what every
     school built before 1960 has and is the entire reason you can tell
     a school from an apartment block at three streets. */
  const p = new Pix(64, 64, 277);
  brickwork(p, 277, 'brown', 0.22, 0.38);
  for (let y = 48; y < 58; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.48 + (y === 48 || y === 57 ? -0.14 : 0));
  p.grime(0.34, 'grey', 0.08, 281);
  return p.snap(0.5);
};

/* ---------- THE CHURCH IS BUILT OF STONE ----------

   It was white clapboard: lapSiding in bone, brighter than the houses,
   on the argument that a church is painted every year whether it needs
   it or not. That is a true thing about a certain kind of New England
   meeting house and it was the wrong building — this one has buttresses,
   a water table, a fieldstone foundation and a stone cornice under its
   spire, and a clapboard wall between those is a wall that disagrees
   with everything it is attached to. At the user's request the whole
   exterior is now ONE STONE: this, over the fieldstone it stands on.

   COURSED ASHLAR, which is the stone a town church is faced with: squared
   blocks in regular courses, the vertical joints staggered against the
   course below. Sixteen to a course, so four courses in a repeat and a
   course is four feet, which is about right for the size the blocks read
   at from the churchyard.

   WHAT SURVIVES AT SIXTY-FOUR PIXELS is the coursing and nothing else.
   The bed joints are the picture — a lit arris along the top of every
   block and a shadow in the joint under it — and the per-block variation
   in tone is what stops four courses of one grey reading as a painted
   wall with lines on it. */
T.CHURCHST = () => {
  const p = new Pix(64, 64, 283);
  const rng = makeRng(283);
  const COURSE = 16;
  p.fill('bone', 0.44);
  for (let c = 0; c * COURSE < 64; c++) {
    const y0 = c * COURSE;
    /* the perpends, staggered half a block against the course below so
       no joint runs two courses — which is the whole of what makes
       coursed masonry read as masonry */
    const edges = [0];
    for (let x = (c % 2 ? 11 : 24); x < 62; x += 19 + Math.floor(rng() * 9)) edges.push(x);
    edges.push(64);
    for (let i = 0; i + 1 < edges.length; i++) {
      const bx0 = edges[i], bx1 = edges[i + 1];
      if (bx1 - bx0 < 3) continue;
      const t = 0.40 + rng() * 0.13;                 // this block's own tone
      for (let y = y0 + 1; y < y0 + COURSE - 1; y++)
        for (let x = bx0 + 1; x < bx1; x++)
          p.ink(x, y, 'bone', Math.max(0.05, Math.min(0.95, t - (y - y0) * 0.005 + (rng() - 0.5) * 0.03)));
      /* the arris: the top edge of the block, in the sun */
      for (let x = bx0 + 1; x < bx1; x++) p.ink(x, y0 + 1, 'bone', Math.min(0.95, t + 0.18));
      if (bx0 > 0) p.vline(bx0, y0 + 1, y0 + COURSE - 1, 'grey', 0.17);   // the perpend
    }
    p.hline(0, 63, y0, 'grey', 0.15);                // the bed joint, in shadow
  }
  /* A FEW BLOCKS THE WEATHER HAS GOT AT — greener and a shade darker
     than their neighbours, which is what a wet corner of a stone wall
     looks like after a century.

     IN THE SAME BRIGHTNESS AS THE STONE, which cost a render to learn:
     `t` here is how BRIGHT a texel is in its palette key and not how
     much of a wash is laid over it, so lichen at 0.06 is not a faint
     tint of green, it is five black rectangles. */
  for (let k = 0; k < 4; k++) {
    const bx = Math.floor(rng() * 50), by = Math.floor(rng() * 4) * COURSE + 6;
    for (let y = by; y < by + COURSE - 7; y++)
      for (let x = bx; x < bx + 12; x++) {
        /* ragged, and only where it takes: a solid rectangle of green is
           a tile somebody painted, not a stone the damp has got into */
        if (rng() > 0.55 - (y - by) * 0.06) continue;
        p.ink(x, y, 'olive', 0.36 + rng() * 0.06);
      }
  }
  p.grime(0.18, 'olive', 0.22, 293);
  return p.snap(0.5);
};

T.STAINGLS = () => {
  /* A lancet: the arch and the leaded lights under it. Sixty-four
     pixels, worn a hundred and twenty-eight units tall. */
  const p = new Pix(64, 64, 307);
  p.fill('grey', 0.10);
  const keys = ['red', 'blue', 'green', 'yellow', 'purple'];
  const halfAt = y => (y < 17 ? Math.sqrt(Math.max(0, 1 - ((17 - y) / 14) ** 2)) * 22 : 22);
  for (let y = 3; y < 61; y++) {
    const halfW = halfAt(y);
    for (let x = Math.round(32 - halfW); x <= Math.round(32 + halfW); x++) {
      const cell = Math.floor((x + 3) / 7) * 31 + Math.floor(y / 5) * 7;
      const k = keys[Math.abs(cell) % keys.length];
      p.ink(x, y, k, 0.30 + ((Math.sin(cell) + 1) / 2) * 0.34);
    }
    if (y % 5 === 0) for (let x = Math.round(32 - halfW); x <= Math.round(32 + halfW); x++) p.ink(x, y, 'grey', 0.10);
  }
  for (let y = 3; y < 61; y++) for (const x of [4, 11, 18, 25, 32, 39, 46, 53, 60])
    if (Math.abs(x - 32) <= halfAt(y)) p.ink(x, y, 'grey', 0.10);
  p.grime(0.16, 'grey', 0.05, 311);
  return p.snap(0.5);
};

T.LOCKERS = () => {
  /* A run of lockers, 64 tall, one repeat two lockers wide.

     AND THAT REPEAT IS TWENTY-FOUR UNITS OF CORRIDOR, not sixty-four.
     Nothing declared a size, so a repeat was 64 by 64 and a locker came
     out 32 wide and 64 tall — one to two, which is a kitchen cupboard.
     A school locker is twelve inches by sixty: one to five. At 24 to
     the repeat each door is twelve units wide against sixty-four tall,
     which is the shape the user was asking for, and a bank of them down
     a corridor is a bank of them rather than a row of doors.

     The picture is still painted 64 across, so it is SQUEEZED nearly
     three to one on the wall — which is why everything that has to read
     here is horizontal. The vents, the number plate and the seams
     survive; anything drawn as a narrow upright would not. */
  const p = new Pix(64, 64, 313);
  const n = fbm(64, 64, 10, 2, 313);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'blue', 0.17 + n[y * 64 + x] * 0.05);
  const rng = makeRng(317);
  for (const dx of [0, 32]) {
    /* the door, set into its frame: lit on the top and left, shadowed
       on the bottom and right, which is the only thing that says a door
       is proud of anything */
    p.box(dx + 2, 3, 28, 58, 'blue', 0.30);
    p.hline(dx + 2, dx + 29, 3, 'blue', 0.46);
    p.vline(dx + 2, 3, 60, 'blue', 0.44);
    p.hline(dx + 2, dx + 29, 60, 'blue', 0.08);
    p.vline(dx + 29, 4, 60, 'blue', 0.10);
    /* the piano hinge down the hanging side */
    p.vline(dx + 3, 4, 59, 'grey', 0.36);
    for (let y = 6; y < 59; y += 6) p.ink(dx + 3, y, 'grey', 0.52);
    /* THE VENTS ARE AT THE TOP, which is where they are on a locker and
       the one feature that survives the squeeze */
    for (let y = 7; y < 19; y += 3) {
      p.hline(dx + 8, dx + 25, y, 'blue', 0.07);
      p.hline(dx + 8, dx + 25, y + 1, 'blue', 0.40);
    }
    /* the number plate under them */
    p.box(dx + 12, 22, 10, 4, 'bone', 0.62);
    p.hline(dx + 12, dx + 21, 22, 'bone', 0.80);
    p.hline(dx + 13, dx + 20, 24, 'grey', 0.14);
    /* the recessed lift handle, two thirds up, and the latch tongue */
    p.box(dx + 20, 32, 8, 7, 'blue', 0.10);
    p.box(dx + 21, 33, 6, 4, 'grey', 0.44);
    p.hline(dx + 21, dx + 26, 33, 'grey', 0.66);
    p.ink(dx + 24, 40, 'grey', 0.30);
    /* dents, and the scuff along the bottom where bags go */
    for (let i = 0; i < 5; i++) {
      const x = dx + 5 + Math.floor(rng() * 22), y = 26 + Math.floor(rng() * 30);
      p.hline(x, x + 1 + Math.floor(rng() * 3), y, 'blue', 0.38);
      p.hline(x, x + 1 + Math.floor(rng() * 3), y + 1, 'blue', 0.10);
    }
  }
  /* the seam between the two, the capping over the bank and the kick
     plinth under it — all three horizontal, all three legible squeezed */
  p.vline(31, 0, 63, 'blue', 0.06);
  p.vline(0, 0, 63, 'blue', 0.06);
  p.hline(0, 63, 0, 'grey', 0.46);
  p.hline(0, 63, 1, 'blue', 0.34);
  p.hline(0, 63, 2, 'blue', 0.10);
  p.box(0, 61, 64, 3, 'grey', 0.14);
  p.hline(0, 63, 61, 'grey', 0.26);
  streaks(p, 4, 319, 'rust', 0.22, 0.3);
  p.grime(0.34, 'grey', 0.08, 317);
  return p.snap(0.5);
};

T.BLACKBRD = () => {
  const p = new Pix(64, 64, 331);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'green', 0.09);
  const rng = makeRng(337);
  for (let i = 0; i < 260; i++) {                       // chalk dust, never words
    const x = Math.floor(rng() * 60) + 2, y = Math.floor(rng() * 56) + 4;
    p.ink(x, y, 'bone', 0.30 + rng() * 0.22);
  }
  p.frame(0, 0, 64, 64, 'brown', 0.26);
  p.hline(0, 63, 60, 'brown', 0.30);                    // the chalk rail
  return p.snap(0.5);
};

T.PEWEND = () => {
  const p = new Pix(64, 40, 347);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.24 + (y / 40) * 0.08);
  p.hline(0, 63, 0, 'brown', 0.40);
  p.hline(0, 63, 1, 'brown', 0.16);
  for (let x = 4; x < 64; x += 16) p.vline(x, 2, 39, 'brown', 0.18);
  return p.snap(0.5);
};

/* =====================================================================
   THE FENCES, AND WHAT MAKES ONE READ AS ITSELF

   A fence in this engine is a masked texture hung in the hole between
   two patches of ground (see `fence` in js/maps/town.js), so the whole
   of a fence IS its texture: there is no geometry to fall back on and
   nothing behind it but the world. Which means the thing that decides
   whether you believe it is not the material, it is the HARDWARE — the
   post, the rail, the way the wire is fastened. A mesh with no post is
   a pattern. A mesh on a post with a rail across the top is a fence.

   BOTH OF THESE ARE ONE REPEAT OF A REAL BAY, at the width the SIZES
   table hangs them: a chain link panel between two posts, and a run of
   picket between two posts. So the post lands where a post goes and
   not wherever the tiling happens to put it.
   ===================================================================== */

/** Coverage of a pixel by a line of half-width `hw` at distance `d`,
 *  0..1. A wire is round and a picket is sawn, and the only difference
 *  the eye gets at this size is whether the edge falls off. */
const cover = (d, hw) => Math.max(0, Math.min(1, hw + 0.5 - Math.abs(d)));

T.CHAINLNK = () => {
  /* CHAIN LINK, one bay: 128 units across and 96 tall — ten feet of
     ball field fence. What it is made of, from the top down:

       THE TOP RAIL, a pipe threaded through the top of the mesh. It is
       the one part of a chain link fence that is SOLID, it catches the
       sky along its upper edge and it is what stops the whole thing
       reading as a net hung off nothing.
       THE SELVAGE under it — the mesh is not cut off square at the top,
       it is KNUCKLED: every strand turns over and goes back down, so
       the top row is a row of little arches and not a row of spikes.
       THE MESH, and it is WOVEN. Two families of diagonal strands, and
       at every crossing one of them passes in front of the other,
       alternating. Drawn as a crosshatch instead — which is what this
       was — it reads as a screen door, because a crosshatch has no
       depth and the eye knows it.
       THE POST at the end of the bay, and the TENSION BAR wired to it,
       which is the flat strap the end of the mesh is threaded onto.
       THE BOTTOM TENSION WIRE, a single strand run through the last row
       so the mesh cannot be lifted and crawled under.

     Galvanised steel, so everything is grey and the light is from the
     top left like everything else in this game. */
  const p = new Pix(64, 64, 349, false);
  p.clear();
  const W = 64, H = 64;
  const RAIL = 3;                    // the pipe, in rows
  const MESH0 = RAIL + 2;            // where the mesh starts
  const PITCH = 8;                   // one diamond, in pixels
  const WIRE = 0.55;                 // half-width of a strand

  /* --- the mesh ---------------------------------------------------- */
  for (let y = MESH0; y < H; y++) for (let x = 0; x < W; x++) {
    /* the two families, as the distance to the nearest strand of each */
    const wrap = v => { const m = ((v % PITCH) + PITCH) % PITCH; return m > PITCH / 2 ? m - PITCH : m; };
    const da = wrap(y - x), db = wrap(y + x);
    const ca = cover(da, WIRE), cb = cover(db, WIRE);
    if (ca <= 0 && cb <= 0) continue;
    /* WHICH STRAND OWNS THIS PIXEL. Away from a crossing only one of
       them is here at all and it is simply drawn — a strand is bright
       along its whole length. It is AT A CROSSING that the question
       arises, and there the parity of the two strand numbers decides,
       which alternates along either strand: over, under, over, under.
       That single-pixel break in the one going under is the whole of
       what makes a weave look woven rather than printed. */
    const ia = Math.round((y - x) / PITCH), ib = Math.round((y + x) / PITCH);
    const crossing = ca > 0 && cb > 0;
    const takeA = crossing ? ((ia + ib) & 1) === 0 : ca >= cb;
    const c = takeA ? ca : cb, d = takeA ? da : db;
    if (c < 0.50) continue;
    /* ROUND WIRE, GALVANISED, which is the brightest thing in a yard on
       a dull day and was drawn here for years as a dark scribble. The
       top left of the strand takes the light and the far side of it
       falls away. */
    p.ink(x, y, 'grey', 0.52 + (0.5 - Math.abs(d) / (WIRE * 2)) * 0.26, 255);
  }

  /* --- the knuckled selvage: the top row turns over ----------------- */
  for (let k = -1; k * PITCH < W + PITCH; k++) {
    const cx = k * PITCH + (MESH0 % PITCH);
    for (let d = -2; d <= 2; d++) {
      const x = cx + d;
      if (x < 0 || x >= W) continue;
      const y = MESH0 + Math.round(Math.abs(d) * 0.5);
      p.ink(x, y, 'grey', 0.42 - Math.abs(d) * 0.03, 255);
    }
  }

  /* --- the top rail: a pipe, lit along its upper edge --------------- */
  for (let y = 0; y < RAIL; y++) for (let x = 0; x < W; x++)
    p.ink(x, y, 'grey', y === 0 ? 0.56 : y === RAIL - 1 ? 0.20 : 0.40, 255);

  /* --- the bottom tension wire ------------------------------------- */
  for (let x = 0; x < W; x++) { p.ink(x, H - 2, 'grey', 0.34, 255); p.ink(x, H - 1, 'grey', 0.22, 255); }

  /* --- the post, and the tension bar the mesh is threaded onto ------ */
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < 4; x++) p.ink(x, y, 'grey', x === 0 ? 0.50 : x === 3 ? 0.18 : 0.38, 255);
    p.ink(5, y, 'grey', 0.30, 255);                       // the tension bar
  }
  /* the bands that clamp the bar to the post, every two feet */
  for (let y = 6; y < H; y += 13) for (let x = 0; x < 7; x++) p.ink(x, y, 'grey', 0.46, 255);
  /* and the cap on top of the post */
  for (let x = 0; x < 5; x++) { p.ink(x, 0, 'grey', 0.60, 255); p.ink(x, 1, 'grey', 0.44, 255); }

  return p.snap(0.35);
};

T.FENCEPIK = () => {
  /* A PICKET FENCE, one bay: 64 units across and 48 tall — four feet of
     painted wood round a back yard. Pointed pickets with a gap between
     them you can see the neighbour's yard through, two rails BEHIND
     them and therefore darker, a post at the end of the bay with a cap
     on it, and the bottom four units gone green where the mower never
     reaches.

     THE GAP IS THE POINT. A picket fence with its boards touching is a
     stockade; what makes this one read is that it is mostly holes, and
     that the rails show through them. */
  const p = new Pix(64, 48, 353, false);
  p.clear();
  const H = 48, W = 64;
  const PITCH = 6, BOARD = 4;        // 4 units of board, 2 of air
  const POINT = 4;                   // how tall the point on a picket is
  const rng = makeRng(357);

  /* --- the two rails, behind everything, so they go down first ----- */
  for (const ry of [13, 33]) for (let y = ry; y < ry + 4; y++) for (let x = 0; x < W; x++)
    p.ink(x, y, 'bone', (y === ry ? 0.30 : 0.24) - (y - ry) * 0.02, 255);

  /* --- the pickets -------------------------------------------------- */
  for (let x0 = 5; x0 + BOARD <= W; x0 += PITCH) {
    /* no two boards in a fence are the same white, and the one that has
       been replaced is the one you notice */
    const paint = 0.46 + rng() * 0.12;
    const top = 2 + Math.floor(rng() * 2);             // they are not level either
    for (let k = 0; k < BOARD; k++) {
      const x = x0 + k;
      /* the point: a sawn triangle, so the board narrows to the top */
      const cut = top + Math.round(Math.abs(k - (BOARD - 1) / 2) * (POINT / ((BOARD - 1) / 2)));
      for (let y = cut; y < H; y++) {
        /* the left edge of a board takes the light and the right edge
           is in the shadow of the next one */
        const edge = k === 0 ? 0.08 : k === BOARD - 1 ? -0.10 : 0;
        const grain = ((x * 7 + y * 3) % 11) < 2 ? -0.03 : 0;
        p.ink(x, y, 'bone', paint + edge + grain, 255);
      }
      /* the sawn end of the point catches more light than the face */
      p.ink(x, cut, 'bone', Math.min(0.72, paint + 0.16), 255);
    }
  }

  /* --- the post at the end of the bay, with its cap ----------------- */
  for (let y = 5; y < H; y++) for (let x = 0; x < 5; x++)
    p.ink(x, y, 'bone', x === 0 ? 0.56 : x === 4 ? 0.34 : 0.50, 255);
  for (let y = 2; y < 5; y++) for (let x = 0; x < 6; x++)
    p.ink(x, y, 'bone', y === 2 ? 0.64 : 0.54, 255);

  /* --- and the grass line: green at the foot, dirt splash over it --- */
  for (let y = H - 5; y < H; y++) for (let x = 0; x < W; x++)
    if (p.alphaAt(x, y) > 8) p.wash(x, y, 'olive', 0.22, (y - (H - 6)) / 6 * 0.7);
  for (let i = 0; i < 90; i++) {
    const x = Math.floor(rng() * W), y = H - 12 + Math.floor(rng() * 12);
    if (p.alphaAt(x, y) > 8) p.wash(x, y, 'brown', 0.20, 0.3 + rng() * 0.3);
  }
  return p.snap(0.35);
};

/* =====================================================================
   A CLIPPED BOX HEDGE, WHICH IS A BOX AND NOT A PICTURE OF ONE

   It used to be a sprite: one photographed block of box per 64-unit
   cell of the wood's grid, billboarded at the camera. At the user's
   request it is geometry now — a sector whose floor is the top of the
   hedge, so the band down its side IS the hedge and the floor you see
   over the top of it is the clipped surface. Which means two textures
   rather than one picture, and it means a hedge has a real corner, real
   thickness, and casts its own shade on the grass beside it.

   THE SIDE IS ONE REPEAT TALL, the way the foundation is: the whole
   height of the hedge in one tile, dark at the roots, clipped flat and
   bright along the top, so the tiling never puts a second clipped edge
   halfway up a hedge.
   ===================================================================== */

/** One boxwood leaf: small, oval, and lit from the top left. `t` is how
 *  lit the clump it belongs to is. */
function boxLeaf(p, rng, x, y, t) {
  const w = 1 + (rng() < 0.45 ? 1 : 0), h = 1 + (rng() < 0.7 ? 1 : 0);
  for (let j = 0; j <= h; j++) for (let i = 0; i <= w; i++) {
    const lit = (i === 0 && j === 0) ? 0.06 : (i === w && j === h) ? -0.05 : 0;
    p.ink(x + i, y + j, rng() < 0.22 ? 'olive' : 'green', t + lit);
  }
}

T.HEDGETOP = () => {
  /* Looking down on a hedge that was cut this summer: dense small
     leaves in clumps, the clumps picked out by the light rather than by
     colour, and the odd bare patch where the shears went too deep. */
  const p = new Pix(64, 64, 361);
  const n = fbm(64, 64, 10, 3, 361);
  const rng = makeRng(367);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'green', 0.16 + n[y * 64 + x] * 0.12);
  /* A CLIPPED TOP FACES THE SKY, so it is the lit face of the hedge and
     not the dark one. The first cut of this came out darker than the
     lawn it stands in, which is the one thing a hedge never is. */
  for (let i = 0; i < 1400; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    boxLeaf(p, rng, x, y, 0.28 + n[y * 64 + x] * 0.28 + rng() * 0.09);
  }
  /* two bare patches, which is what a hedge looks like and a wallpaper
     of leaves does not */
  for (let i = 0; i < 70; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    if (n[y * 64 + x] > 0.62) p.ink(x, y, 'brown', 0.14 + rng() * 0.06);
  }
  p.grime(0.22, 'olive', 0.06, 373);
  return p.snap(0.5);
};

T.HEDGESID = () => {
  /* The side of the same hedge, one repeat for its whole height: the
     clipped top lit along its edge, the face of it in the middle, and
     the bottom in its own shade with the woody stems showing through
     where the leaves have given up. */
  const p = new Pix(64, 64, 379);
  const n = fbm(64, 64, 9, 3, 379);
  const rng = makeRng(383);
  /* HOW LIT THE HEDGE IS AT A HEIGHT: bright along the clipped top,
     falling away down the face, and dark in the last quarter where
     nothing but the trunk gets any light at all. */
  const at = y => y < 5 ? 0.38 - y * 0.012 : 0.34 - Math.pow(y / 64, 1.7) * 0.24;
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'green', Math.max(0.05, at(y) * 0.5 + n[y * 64 + x] * 0.07));
  for (let i = 0; i < 1600; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    boxLeaf(p, rng, x, y, Math.max(0.06, at(y) + n[y * 64 + x] * 0.16 + rng() * 0.07 - 0.04));
  }
  /* the stems: four or five of them, only in the bottom third */
  for (let k = 0; k < 5; k++) {
    let x = 6 + Math.floor(rng() * 52);
    for (let y = 63; y > 40; y--) {
      p.ink(x, y, 'brown', 0.16 + rng() * 0.05);
      if (rng() < 0.3) x += rng() < 0.5 ? -1 : 1;
    }
  }
  /* AND THE CLIPPED EDGE ITSELF, which is the one line that says this
     was cut and did not grow: the top two rows are the sawn face of a
     thousand leaves and they are the brightest thing on it. */
  for (let x = 0; x < 64; x++) {
    p.ink(x, 0, 'green', 0.34 + (x % 3 === 0 ? 0.06 : 0));
    p.ink(x, 1, 'green', 0.28 + (x % 5 === 0 ? 0.05 : 0));
  }
  p.grime(0.28, 'olive', 0.07, 389);
  return p.snap(0.5);
};

T.SHOPFRNT = () => {
  /* Main Street's ground floor: a big pane, a stallriser under it and a
     transom over. No name on it, ever — see the top of this section. */
  const p = new Pix(64, 64, 359);
  brickwork(p, 359, 'rust', 0.26, 0.44);
  p.box(4, 2, 56, 10, 'grey', 0.14);                    // the transom
  for (let y = 3; y < 11; y++) for (let x = 6; x < 58; x++) p.ink(x, y, 'yellow', 0.30 - (y - 3) * 0.016);
  p.box(4, 14, 56, 37, 'grey', 0.12);                   // the pane
  for (let y = 15; y < 50; y++) for (let x = 6; x < 58; x++) {
    const d = Math.hypot(x - 20, y - 22) / 40;
    p.ink(x, y, 'yellow', Math.max(0.10, 0.44 - d * 0.36));
  }
  p.vline(31, 14, 50, 'bone', 0.40); p.vline(32, 14, 50, 'bone', 0.40);
  p.frame(4, 14, 56, 37, 'bone', 0.46);
  for (let y = 52; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'green', 0.16);
  p.hline(0, 63, 52, 'bone', 0.40);
  p.grime(0.28, 'grey', 0.07, 367);
  return p.snap(0.5);
};

/* =====================================================================
   WHAT A BUILDING HAS THAT A BOX DOES NOT

   A sector engine gives you a wall with holes in it, and a town built
   out of nothing else is a town of shoeboxes with windows drawn on. The
   things that are missing are all the same KIND of thing: they stand
   PROUD of the wall, or they stand ABOVE the roof, and a sector can do
   neither. They are drawn as free boxes instead — see boxGeometry in
   js/mapgeo.js — and these are their surfaces.

   ALL OF THEM ARE READ FROM BELOW, at a hundred and twenty units of
   height from forty metres away, which decides everything about them:
   the light goes at the top and the shadow under, one hard line where
   the thing projects, and no detail finer than the line.
   ===================================================================== */

T.CHIMNEY = () => {
  /* Brick, but not the wall's brick: a stack stands against the SKY,
     so what you read off it is the silhouette and the courses, and the
     courses want to be finer than a wall's or a chimney forty metres
     off is a red smudge. Soot down the leeward face and lime bloom
     where the rain runs. */
  const p = new Pix(64, 64, 751);
  brickwork(p, 751, 'rust', 0.22, 0.36, 0.44, 6, 16);
  const rng = makeRng(757);
  /* the weather side: forty years of rain has bleached it */
  for (let y = 0; y < 64; y++) for (let x = 0; x < 26; x++)
    p.wash(x, y, 'bone', 0.40, (1 - x / 26) * 0.22);
  /* and soot, which comes OUT of the top and runs down */
  for (let k = 0; k < 40; k++) {
    let x = 34 + Math.floor(rng() * 26);
    for (let y = 0; y < 20 + rng() * 30; y++) {
      p.wash(x, y, 'grey', 0.06, 0.30 - y * 0.006);
      if (rng() < 0.25) x += rng() < 0.5 ? -1 : 1;
    }
  }
  p.grime(0.34, 'grey', 0.06, 761);
  return p.snap(0.5);
};

T.CHIMCAP = () => {
  /* THE CAP OVERSAILS THE STACK, and that is the whole of why a chimney
     reads as masonry and not as a brick-coloured post: a cast slab a
     little wider than what holds it up, with a drip under it, so there
     is a hard black line all the way round at the top of the brick. */
  const p = new Pix(64, 16, 769);
  aggregate(p, 769, { baseKey: 'grey', baseLo: 0.30, baseHi: 0.38,
    grades: [{ count: 70, min: 0.3, max: 0.9, key: 'bone', lo: 0.26, hi: 0.36 }] });
  p.hline(0, 63, 0, 'bone', 0.56); p.hline(0, 63, 1, 'bone', 0.48);   // the weathered top, in the sun
  p.hline(0, 63, 9, 'grey', 0.16);                                     // the throat of the drip
  for (let y = 10; y < 16; y++) p.hline(0, 63, y, 'grey', 0.12 + (y - 10) * 0.01);
  p.grime(0.30, 'olive', 0.06, 773);
  return p.snap(0.5);
};

T.DOWNPIPE = () => {
  /* A round pipe on a flat face, which is done entirely with the
     shading: bright a third of the way in from the left, falling away
     to nothing at the right edge. The collars every sixty-four units
     are what stop it being a painted stripe. */
  const p = new Pix(64, 64, 787);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const t = Math.cos((x / 63 - 0.34) * 2.1);              // the round of it
    p.ink(x, y, 'grey', Math.max(0.10, 0.20 + t * 0.26));
  }
  /* the collar: a band with a lip over it and a shadow under */
  for (const y0 of [4]) {
    for (let x = 0; x < 64; x++) {
      const t = Math.cos((x / 63 - 0.34) * 2.1);
      p.ink(x, y0, 'grey', Math.max(0.12, 0.28 + t * 0.28));
      p.ink(x, y0 + 1, 'grey', Math.max(0.14, 0.32 + t * 0.28));
      p.ink(x, y0 + 2, 'grey', Math.max(0.14, 0.30 + t * 0.26));
      p.ink(x, y0 + 3, 'grey', Math.max(0.06, 0.12 + t * 0.14));
    }
  }
  const rng = makeRng(797);
  for (let k = 0; k < 60; k++) p.wash(Math.floor(rng() * 64), Math.floor(rng() * 64), 'rust', 0.22, 0.10 + rng() * 0.2);
  return p.snap(0.5);
};

T.PORCHPST = () => {
  /* One porch post, whole, in one repeat: a plinth block at the foot, a
     chamfered shaft, a cap at the head. Eight units of post over
     sixty-four pixels, so this is the post seen ROUND — the left third
     in the light, the right edge in its own shadow. */
  const p = new Pix(64, 64, 809);
  const shaft = x => {
    const t = Math.cos((x / 63 - 0.30) * 2.0);
    return Math.max(0.14, 0.42 + t * 0.22);
  };
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', shaft(x));
  /* the chamfers: a hard line a sixth in from each edge */
  for (const x of [10, 53]) { p.vline(x, 0, 63, 'bone', 0.66); p.vline(x + 1, 0, 63, 'grey', 0.26); }
  /* the cap at the top and the plinth at the foot, both standing proud
     of the shaft, which is two light lines and two shadows */
  for (let y = 0; y < 6; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', shaft(x) + (y < 2 ? 0.14 : 0.06));
  p.hline(0, 63, 6, 'grey', 0.20);
  for (let y = 54; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', shaft(x) + (y < 56 ? 0.12 : 0.04));
  p.hline(0, 63, 53, 'grey', 0.22);
  const rng = makeRng(811);
  for (let k = 0; k < 30; k++) p.wash(Math.floor(rng() * 64), 40 + Math.floor(rng() * 24), 'olive', 0.20, 0.1 + rng() * 0.25);
  return p.snap(0.5);
};

T.AWNING = () => {
  /* Striped canvas over a shopfront, read from underneath and from the
     side of the street. The stripes run DOWN the slope, which means
     across this tile, and the bottom four rows are the valance — the
     scalloped hem that hangs off the front bar, which is the part that
     says awning and not shelf. */
  const p = new Pix(64, 32, 821);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 64; x++) {
    const band = Math.floor(x / 8) & 1;
    /* it has been out in the sun for nine summers: the top of the fall
       is bleached and the bottom keeps its colour */
    const fade = 0.10 * (1 - y / 32);
    p.ink(x, y, band ? 'bone' : 'red', (band ? 0.52 : 0.30) + fade);
  }
  /* the seam between every stripe, and the front bar the valance hangs from */
  for (let x = 0; x < 64; x += 8) p.vline(x, 0, 31, 'grey', 0.22, 255);
  p.hline(0, 63, 25, 'grey', 0.18); p.hline(0, 63, 26, 'bone', 0.44);
  /* the scallop: a shallow arc cut out of the hem of each stripe */
  for (let x = 0; x < 64; x++) {
    const t = Math.abs(((x % 16) - 8) / 8);
    const cut = 31 - Math.round((1 - t * t) * 3);
    for (let y = cut + 1; y < 32; y++) p.ink(x, y, 'grey', 0.10);
  }
  p.grime(0.26, 'grey', 0.06, 823);
  return p.snap(0.5);
};

T.GABLEVNT = () => {
  /* THE HOLE IN THE TOP OF A GABLE, which every house with an attic has
     and none of these had: a louvred vent in a painted surround, forty
     units across. A gable with nothing in it is the largest blank
     surface on an American house and the eye goes straight to it.
     Louvres dark between the slats, because the attic behind them is. */
  const p = new Pix(48, 32, 827);
  p.fill('bone', 0.54);
  for (let y = 5; y < 27; y += 4) for (let x = 5; x < 43; x++) {
    p.ink(x, y, 'grey', 0.07);                        // the dark between the slats
    p.ink(x, y + 1, 'bone', 0.46);
    p.ink(x, y + 2, 'bone', 0.34);
    p.ink(x, y + 3, 'grey', 0.14);
  }
  /* the surround, standing proud: lit on the top and left, shadowed
     under and right, which is what makes it a frame and not a decal */
  p.hline(0, 47, 0, 'bone', 0.70); p.hline(0, 47, 1, 'bone', 0.64);
  p.vline(0, 0, 31, 'bone', 0.68); p.vline(1, 0, 31, 'bone', 0.62);
  p.hline(0, 47, 31, 'grey', 0.18); p.hline(0, 47, 30, 'grey', 0.24);
  p.vline(47, 0, 31, 'grey', 0.20); p.vline(46, 0, 31, 'grey', 0.26);
  p.frame(4, 4, 40, 24, 'grey', 0.16);
  p.grime(0.20, 'grey', 0.05, 829);
  return p.snap(0.5);
};

T.WINTRIM = () => {
  /* THE HEAD CASING over a window: a painted board standing six units
     out of the wall with a drip under it. Twelve tall, which is one
     repeat, so the light line is at the top of the board and the
     shadow under it every time and never halfway up. */
  const p = new Pix(64, 12, 839);
  for (let y = 0; y < 12; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.58 - y * 0.012 + ((x * 5 + y * 3) % 13 < 2 ? -0.02 : 0));
  p.hline(0, 63, 0, 'bone', 0.72); p.hline(0, 63, 1, 'bone', 0.66);
  p.hline(0, 63, 8, 'grey', 0.22);                     // the throat of the drip
  for (let y = 9; y < 12; y++) p.hline(0, 63, y, 'grey', 0.16 + (y - 9) * 0.02);
  return p.snap(0.5);
};
/* =====================================================================
   WHAT A STRIP MALL HAS THAT A SHED DOES NOT

   The same argument as the section above, made about a different kind of
   building. A parade is a long shed with a fascia screwed to the front of
   it, and drawn as sectors alone that is exactly what it looks like: four
   horizontal bands stacked up, thirteen thousand units wide, nothing
   standing out of any of them. What is missing is not ornament. It is the
   PLANT — the coping that keeps the rain out of the top of the wall, the
   packaged air conditioners that are the only reason a windowless shed is
   habitable, the gutter, the downpipes, the ladder somebody has to get up
   there on, the meters, the condensers, the skip. A supermarket is a
   machine with a shopfront on it, and every one of these is a piece of
   the machine that is on the OUTSIDE.

   THEY ARE READ FROM TWO PLACES and nowhere else: from the car park,
   which is between a hundred and four thousand units away and looking
   slightly up, and from the footway, which is under the canopy looking
   along it. So the roof plant is drawn to be read as a SILHOUETTE above
   the coping line, and everything at head height is drawn to be read at
   arm's length. Nothing here has a middle distance to worry about.
   ===================================================================== */

T.COPING = () => {
  /* THE TOP OF THE WALL. A parapet that just stops is a cut edge, and a
     cut edge is the single loudest thing wrong with a shed drawn out of
     ceiling heights: real ones are capped, because the top of a wall is
     where the water gets in. Pressed aluminium here rather than cast
     stone — this is 1974 commercial, not a bank — which means it is
     paler than the render under it, it has a fold at the front, and it
     comes in lengths with a joint every repeat. */
  const p = new Pix(64, 14, 901);
  aggregate(p, 901, { baseKey: 'grey', baseLo: 0.40, baseHi: 0.48,
    grades: [{ count: 60, min: 0.3, max: 0.9, key: 'bone', lo: 0.34, hi: 0.44 }] });
  /* the top face, in the sky, and the fold down the front of it */
  for (let y = 0; y < 4; y++) p.hline(0, 63, y, 'bone', 0.62 - y * 0.03);
  p.hline(0, 63, 4, 'grey', 0.26);                       // the arris
  for (let y = 5; y < 10; y++) p.hline(0, 63, y, 'grey', 0.40 - (y - 5) * 0.012);
  p.hline(0, 63, 10, 'grey', 0.14);                      // the drip, and under it
  for (let y = 11; y < 14; y++) p.hline(0, 63, y, 'grey', 0.10);
  /* the joint between two lengths, with the cover strip over it */
  for (let y = 0; y < 11; y++) { p.ink(1, y, 'grey', 0.22); p.ink(2, y, 'bone', 0.54); }
  const rng = makeRng(907);
  for (let k = 0; k < 40; k++) {                         // pooled dirt on the top face
    const x = Math.floor(rng() * 64);
    p.wash(x, Math.floor(rng() * 3), 'olive', 0.22, 0.12 + rng() * 0.22);
  }
  return p.snap(0.5);
};

T.PIERCAP = () => {
  /* A cast cap on the head of a brick pier, which is where the pier
     stops and the parapet carries on over it. Twelve tall and one
     repeat, so the weathered top and the shadow under land in the same
     place on every pier down the parade. */
  const p = new Pix(64, 12, 911);
  aggregate(p, 911, { baseKey: 'bone', baseLo: 0.30, baseHi: 0.40,
    grades: [{ count: 50, min: 0.3, max: 0.8, key: 'grey', lo: 0.26, hi: 0.36 }] });
  p.hline(0, 63, 0, 'bone', 0.60); p.hline(0, 63, 1, 'bone', 0.52);
  p.hline(0, 63, 7, 'grey', 0.18);
  for (let y = 8; y < 12; y++) p.hline(0, 63, y, 'grey', 0.12);
  for (const jx of [8, 40]) p.vline(jx, 0, 7, 'grey', 0.22);
  p.grime(0.30, 'olive', 0.07, 919);
  return p.snap(0.5);
};

/* --- the roof plant ------------------------------------------------ */

T.RTU = () => {
  /* THE PACKAGED UNIT. Every flat roof in America has three or four of
     these on it and they are the only thing on the skyline of a strip
     mall — the parapet is drawn tall enough to hide them and it never
     quite does, which is the joke the building is telling and the reason
     these stand proud of the coping here.

     Galvanised steel, folded into panels: a rib every sixteen so the
     sheet does not oil-can, an access panel with two latches, and the
     coil louvre down the bottom third where the air comes in. Read from
     a car park at forty metres, so the ribs carry it and everything else
     is a hint at closer range. */
  const p = new Pix(64, 48, 929);
  const n = fbm(64, 48, 8, 2, 929);
  /* THE PANEL IS CURVED BETWEEN ITS RIBS. A flat field with lines ruled
     on it reads as a drawing of a sheet; what makes it sheet metal is
     that the light falls off across each bay, so every sixteen the tone
     rolls from bright at the fold to dark in the middle of the pan. */
  for (let y = 0; y < 48; y++) for (let x = 0; x < 64; x++) {
    const bay = Math.cos(((x % 16) / 16 - 0.22) * 4.6);
    p.ink(x, y, 'grey', 0.44 + bay * 0.14 + n[y * 64 + x] * 0.08);
  }
  /* the ribs themselves — a bright fold with its own shadow beside it */
  for (let x = 0; x < 64; x += 16) for (let y = 0; y < 48; y++) {
    p.ink(x, y, 'grey', 0.18);
    p.ink(x + 1, y, 'grey', 0.72);
    p.ink(x + 2, y, 'grey', 0.60);
    p.ink(x + 3, y, 'grey', 0.46);
  }
  /* the seam at the top where the casing meets the hood, and the curb
     flashing at the foot, which is the bit that sits in the roof */
  p.hline(0, 63, 0, 'grey', 0.62); p.hline(0, 63, 1, 'grey', 0.28);
  for (let y = 42; y < 48; y++) p.hline(0, 63, y, 'grey', 0.24 - (y - 42) * 0.02);
  p.hline(0, 63, 41, 'grey', 0.16);
  /* the coil louvre: horizontal blades with the dark of the coil behind */
  for (let y = 24; y < 40; y += 3) for (let x = 20; x < 60; x++) {
    p.ink(x, y, 'grey', 0.10);
    p.ink(x, y + 1, 'grey', 0.50);
  }
  p.frame(19, 23, 42, 18, 'grey', 0.20);
  /* the access panel on the left, with its two quarter-turn latches */
  p.frame(4, 6, 13, 30, 'grey', 0.22);
  for (const cy of [13, 29]) { p.disc(10, cy, 2, 'grey', 0.66); p.ink(10, cy, 'grey', 0.14); }
  /* the maker's plate, which at this size is a bright rectangle and is
     meant to be: it is the one warm thing on the whole unit */
  p.box(6, 39, 9, 4, 'yellow', 0.52);
  streaks(p, 6, 937, 'rust', 0.22, 0.34);        // it has been up there a while
  p.grime(0.40, 'grey', 0.10, 941);
  return p.snap(0.5);
};

T.RTUTOP = () => {
  /* Looking down on one: two fan cowls with bird mesh over them, and the
     flat of the casing between. Only ever seen from the air, which in
     this game is a real thing you can do — so it is drawn properly and
     costs one texture. */
  const p = new Pix(64, 64, 947);
  const n = fbm(64, 64, 8, 2, 947);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.50 + n[y * 64 + x] * 0.10);
  p.frame(0, 0, 64, 64, 'grey', 0.30);
  for (const [cx, cy] of [[18, 18], [46, 44]]) {
    p.disc(cx, cy, 14, 'grey', 0.36);
    p.disc(cx, cy, 13, 'grey', 0.20);
    /* the mesh: a grid coarse enough to survive one pixel per cell */
    for (let d = -13; d <= 13; d += 3)
      for (let e = -13; e <= 13; e++) {
        if (d * d + e * e > 13 * 13) continue;
        p.ink(cx + d, cy + e, 'grey', 0.46);
        p.ink(cx + e, cy + d, 'grey', 0.42);
      }
    /* the hub, and the blade shadows under the mesh */
    p.disc(cx, cy, 4, 'grey', 0.14);
    p.disc(cx - 1, cy - 1, 3, 'grey', 0.30);
  }
  streaks(p, 4, 953, 'rust', 0.20, 0.30);
  p.grime(0.46, 'olive', 0.08, 967);
  return p.snap(0.5);
};

T.DUCTWORK = () => {
  /* Spiral duct on sleepers, running from one unit to the next. Round,
     so the shading does the work the way the downpipe's does — bright a
     third in from the left, dark at the right edge — and the spiral seam
     is what makes it duct rather than pipe. */
  const p = new Pix(48, 32, 971);
  const round = y => Math.cos((y / 31 - 0.30) * 2.4);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 48; x++)
    p.ink(x, y, 'grey', Math.max(0.08, 0.26 + round(y) * 0.34));
  /* THE LOCK SEAM, which is the only thing that tells spiral duct from
     pipe, and it has to be a RIDGE and not a scratch: the fold catches
     the light and throws a shadow on the row under it. It wraps — 48
     across at two rows a column is three whole turns of 32 — so the
     helix runs on into the next repeat instead of stopping. */
  for (let x = 0; x < 48; x++) {
    const y = (x * 2) % 32;
    p.ink(x, y, 'grey', Math.min(0.90, Math.max(0.20, 0.44 + round(y) * 0.38)));
    p.ink(x, (y + 1) % 32, 'grey', Math.max(0.05, 0.12 + round(y) * 0.18));
  }
  /* and the band where two lengths are joined, which is a collar over
     the top of the seam and therefore brighter than any of it */
  for (const bx of [2, 3]) for (let y = 0; y < 32; y++)
    p.ink(bx, y, 'grey', Math.max(0.16, (bx === 2 ? 0.52 : 0.18) + round(y) * 0.32));
  const rng = makeRng(977);
  for (let k = 0; k < 50; k++) p.wash(Math.floor(rng() * 48), Math.floor(rng() * 32), 'rust', 0.24, 0.08 + rng() * 0.22);
  return p.snap(0.5);
};

T.ROOFLADR = () => {
  /* THE WAY UP. A caged ladder on the back wall, which is the answer to
     the question the roof plant asks and which nothing in this level had
     an answer to. Drawn as a flat face rather than as a masked cutout,
     because it is bolted to a blank wall and there is nothing behind it
     worth seeing: the stiles, the rungs, and the hoops of the cage
     standing proud of both. */
  const p = new Pix(32, 64, 983);
  const n = fbm(32, 64, 8, 2, 983);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 32; x++)   // the wall behind
    p.ink(x, y, 'grey', 0.22 + n[y * 32 + x] * 0.08);
  /* the two stiles */
  for (const sx of [8, 21]) for (let y = 0; y < 64; y++) {
    p.ink(sx, y, 'grey', 0.54); p.ink(sx + 1, y, 'grey', 0.38); p.ink(sx + 2, y, 'grey', 0.14);
  }
  /* the rungs, every eight, which is a foot apart at this scale */
  for (let y = 3; y < 64; y += 8) for (let x = 9; x < 22; x++) {
    p.ink(x, y, 'grey', 0.58); p.ink(x, y + 1, 'grey', 0.30);
  }
  /* and the cage: a hoop every twenty-four with three verticals on it,
     standing out past the stiles both sides */
  for (const sx of [2, 28]) for (let y = 0; y < 64; y++) p.ink(sx, y, 'grey', 0.44);
  for (let y = 6; y < 64; y += 24) for (let x = 0; x < 32; x++) {
    p.ink(x, y, 'grey', 0.62); p.ink(x, y + 1, 'grey', 0.20);
  }
  const rng = makeRng(991);
  for (let k = 0; k < 60; k++) p.wash(Math.floor(rng() * 32), Math.floor(rng() * 64), 'rust', 0.26, 0.08 + rng() * 0.26);
  return p.snap(0.5);
};

/* --- the canopy, the fascia and the shopfront ---------------------- */

T.GUTTER = () => {
  /* The eaves gutter along the front of the canopy, on brackets. It is
     the only horizontal line in the whole elevation that is allowed to
     be dark, and it is what stops the canopy edge reading as a painted
     stripe: a half-round with a shadow under it and a bracket every
     repeat. */
  const p = new Pix(64, 12, 997);
  for (let y = 0; y < 12; y++) for (let x = 0; x < 64; x++) {
    /* the belly of it turns away fast, because a gutter is a half round
       and not a fascia board: bright on the bead, gone by the soffit */
    const t = Math.cos((y / 11 - 0.16) * 2.8);
    p.ink(x, y, 'grey', Math.max(0.05, 0.24 + t * 0.38));
  }
  p.hline(0, 63, 0, 'bone', 0.66);                       // the bead at the top
  p.hline(0, 63, 1, 'bone', 0.52);
  p.hline(0, 63, 2, 'grey', 0.44);
  p.hline(0, 63, 11, 'grey', 0.05);                      // and the shadow under it
  /* the bracket, which hangs OVER the bead and is the only thing
     interrupting a line sixty-five metres long */
  for (const bx of [6, 7, 8]) for (let y = 0; y < 12; y++)
    p.ink(bx, y, 'grey', bx === 6 ? 0.46 : 0.10 + y * 0.004);
  const rng = makeRng(1009);
  for (let k = 0; k < 30; k++) p.wash(Math.floor(rng() * 64), 8 + Math.floor(rng() * 4), 'olive', 0.22, 0.14 + rng() * 0.2);
  return p.snap(0.5);
};

T.SIGNEDGE = () => {
  /* The extruded edge of a fascia tray. Eight tall, so the tray gets a
     rim at the top and the bottom and the sign band between them stops
     being paint on a wall and becomes a box screwed to one. Anodised
     aluminium: nearly white on the top face, nearly black underneath,
     and a screw every sixteen. */
  const p = new Pix(64, 8, 1013);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.54 - y * 0.05);
  p.hline(0, 63, 0, 'bone', 0.74); p.hline(0, 63, 1, 'bone', 0.62);
  p.hline(0, 63, 7, 'grey', 0.10);
  for (let x = 6; x < 64; x += 16) { p.ink(x, 4, 'grey', 0.22); p.ink(x, 3, 'bone', 0.60); }
  return p.snap(0.5);
};

T.SHUTBOX = () => {
  /* The roller housing over a shopfront: the box the shutter winds into,
     which sits in the head of the opening and which every unit on a
     parade has whether the roller is down or not. A pressed lid, the
     end plate's bolt circle, and the slot the curtain comes out of along
     the bottom — that slot is the whole point, because it is a black
     line under a lit box and it says there is a shutter up there. */
  const p = new Pix(64, 24, 1019);
  const n = fbm(64, 24, 8, 2, 1019);
  for (let y = 0; y < 24; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', 0.40 + n[y * 64 + x] * 0.10);
  for (let y = 0; y < 3; y++) p.hline(0, 63, y, 'grey', 0.68 - y * 0.06);
  p.hline(0, 63, 3, 'grey', 0.24);
  /* THE SLOT IS THE WHOLE POINT. A lit box over a shopfront with a
     black line under it has a shutter in it; the same box without the
     line is a bulkhead. So it is three rows of nearly nothing, with the
     lip of the box catching the light right above it. */
  p.hline(0, 63, 18, 'grey', 0.48);
  for (let y = 19; y < 22; y++) p.hline(0, 63, y, 'grey', 0.03);
  for (let y = 22; y < 24; y++) p.hline(0, 63, y, 'grey', 0.20);
  /* the end plate, one per repeat, with the bolts round the barrel */
  p.box(2, 4, 13, 14, 'grey', 0.30);
  p.frame(2, 4, 13, 14, 'grey', 0.56);
  for (let a = 0; a < 6; a++) {
    const th = a * Math.PI / 3;
    p.disc(8 + Math.round(Math.cos(th) * 4), 11 + Math.round(Math.sin(th) * 4), 1, 'grey', 0.70);
  }
  p.disc(8, 11, 2, 'grey', 0.12);
  streaks(p, 4, 1021, 'rust', 0.20, 0.28);
  p.grime(0.34, 'grey', 0.10, 1031);
  return p.snap(0.5);
};

T.WALLPACK = () => {
  /* The light over a shop door. One repeat is one fitting, which is what
     makes it usable: the box is exactly thirty-two by twenty-four, so
     the texture is a PICTURE of a luminaire rather than a pattern of
     them. A cast body, a glass lens under a hood, and the lens is the
     brightest thing in the texture because at night it is the brightest
     thing on the parade. */
  const p = new Pix(32, 24, 1033);
  p.fill('grey', 0.26);
  /* the hood, which is what you see of it from underneath and in front */
  for (let y = 0; y < 8; y++) for (let x = 2; x < 30; x++)
    p.ink(x, y, 'grey', 0.46 - y * 0.03 - (x > 24 ? 0.08 : 0));
  p.hline(2, 29, 0, 'grey', 0.58);
  p.hline(2, 29, 8, 'grey', 0.10);
  /* the lens: a prismatic wedge, brightest at the top where the lamp is */
  for (let y = 9; y < 20; y++) for (let x = 4; x < 28; x++) {
    const k = 1 - (y - 9) / 11;
    const rib = (x % 4) < 2 ? 0.08 : 0;
    p.ink(x, y, 'yellow', 0.42 + k * 0.46 + rib);
  }
  p.frame(3, 8, 26, 12, 'grey', 0.20);
  /* the body under it, and the two fixings into the wall */
  for (let y = 20; y < 24; y++) for (let x = 2; x < 30; x++) p.ink(x, y, 'grey', 0.20);
  for (const x of [6, 25]) { p.ink(x, 3, 'grey', 0.60); p.ink(x, 4, 'grey', 0.14); }
  return p.snap(0.45);
};

/* --- the service side ---------------------------------------------- */

T.CONDENSR = () => {
  /* A condensing unit on the ground behind the building: a box of coil
     with a fan in the side of it. One repeat is one unit. The coil is
     the texture — a fin pack reads as a very fine vertical grid, which
     is the one thing in this whole set that wants to be drawn at the
     texel and not at the foot. */
  const p = new Pix(48, 40, 1039);
  p.fill('grey', 0.44);
  /* THE FINS ARE PALE, not dark. First go at this had the pack at 0.22
     to 0.34 because a coil IS dark when you look into it — and what it
     drew was a black rectangle on a wall, because from three feet away
     what you see is not the gap between the fins, it is the ALUMINIUM,
     and aluminium is the brightest thing in the yard. */
  for (let y = 4; y < 36; y++) for (let x = 2; x < 46; x++)
    p.ink(x, y, 'grey', (x & 1) ? 0.56 : 0.40);           // the fins
  /* the guard over the fan, which is a spiral of wire and reads as rings */
  p.disc(30, 20, 14, 'grey', 0.26);                      // the dark behind the guard
  for (let r = 4; r <= 13; r += 3)
    for (let a = 0; a < 44; a++) {
      const th = a * Math.PI / 22;
      p.ink(30 + Math.round(Math.cos(th) * r), 20 + Math.round(Math.sin(th) * r), 'grey', 0.72);
    }
  p.disc(30, 20, 3, 'grey', 0.50);
  /* the casing: top rail in the light, foot rail in shadow, corner posts */
  for (let y = 0; y < 4; y++) p.hline(0, 47, y, 'grey', 0.70 - y * 0.06);
  for (let y = 36; y < 40; y++) p.hline(0, 47, y, 'grey', 0.18);
  for (const x of [0, 1, 46, 47]) p.vline(x, 0, 39, 'grey', x < 2 ? 0.64 : 0.20);
  streaks(p, 5, 1049, 'rust', 0.22, 0.30);
  p.grime(0.30, 'olive', 0.08, 1051);
  return p.snap(0.5);
};

T.METERBOX = () => {
  /* The intake cabinet — gas, or electricity, or the fire alarm panel,
     and from ten feet away it does not matter which. A pressed steel
     door with a piano hinge down one side, a hasp on the other, and a
     label nobody has read since it was screwed on. */
  const p = new Pix(32, 40, 1061);
  const n = fbm(32, 40, 8, 2, 1061);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 32; x++)
    p.ink(x, y, 'bone', 0.30 + n[y * 32 + x] * 0.10);
  p.frame(2, 2, 28, 36, 'grey', 0.18);
  p.hline(0, 31, 0, 'bone', 0.50); p.vline(0, 0, 39, 'bone', 0.46);
  p.hline(0, 31, 39, 'grey', 0.10); p.vline(31, 0, 39, 'grey', 0.12);
  for (let y = 5; y < 36; y += 6) { p.ink(3, y, 'grey', 0.46); p.ink(4, y, 'grey', 0.16); }  // the hinge
  p.box(26, 18, 3, 5, 'grey', 0.54);                    // the hasp
  p.box(8, 8, 14, 6, 'yellow', 0.46);                   // the label
  for (let x = 9; x < 21; x += 3) p.vline(x, 9, 12, 'grey', 0.20);
  p.grime(0.40, 'grey', 0.10, 1063);
  return p.snap(0.5);
};

T.SKIPSIDE = () => {
  /* The skip in the service yard. Steel, painted once, dented since:
     the raked end, the top rail, the lifting pocket, and the diagonal
     brace that every one of them has and that is the thing that makes a
     rectangle read as a skip. */
  const p = new Pix(64, 48, 1069);
  const n = fbm(64, 48, 6, 2, 1069);
  for (let y = 0; y < 48; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'yellow', 0.20 + n[y * 64 + x] * 0.10);
  /* the rolled top rail, in the light, and the foot in shadow */
  for (let y = 0; y < 4; y++) p.hline(0, 63, y, 'yellow', 0.40 - y * 0.04);
  p.hline(0, 63, 4, 'grey', 0.14);
  for (let y = 43; y < 48; y++) p.hline(0, 63, y, 'grey', 0.12);
  /* the lifting pocket and the brace */
  p.box(6, 12, 8, 22, 'grey', 0.22);
  p.frame(6, 12, 8, 22, 'yellow', 0.34);
  for (const [x0, x1] of [[20, 58], [21, 59]])
    p.line(x0, 42, x1, 8, x0 === 20 ? 'yellow' : 'grey', x0 === 20 ? 0.48 : 0.12);
  /* RUST WHERE IT HAS BEEN HIT, and nowhere else. The first go at this
     scattered two dozen patches over the whole side and what came out
     was a rusty skip with some yellow on it, which is the wrong way
     round: what you read at forty metres is a YELLOW box, and the rust
     is what tells you how old it is once you are close. So it is eight
     small ones, low down where a skip gets kicked, and each has a
     bright lip on top because a chip in paint is a step. */
  const rng = makeRng(1087);
  for (let k = 0; k < 8; k++) {
    const cx = Math.floor(rng() * 64), cy = 22 + Math.floor(rng() * 18), r = 2 + Math.floor(rng() * 3);
    p.disc(cx, cy, r, 'rust', 0.22 + rng() * 0.12);
    p.disc(cx, cy - 1, Math.max(1, r - 2), 'rust', 0.30);
    p.hline(cx - r, cx + r, cy - r, 'yellow', 0.44);
  }
  streaks(p, 5, 1091, 'rust', 0.22, 0.26);
  p.grime(0.26, 'grey', 0.08, 1093);
  return p.snap(0.5);
};

/* --- the car park --------------------------------------------------- */

T.WHEELSTP = () => {
  /* A precast wheel stop. Twelve tall and one repeat wide, so the two
     dowel holes land in the same place on every one of them, which is
     right: they come out of the same mould. Yellow once; most of that
     is on the tyres of the county by now. */
  const p = new Pix(64, 12, 1097);
  aggregate(p, 1097, { baseKey: 'bone', baseLo: 0.28, baseHi: 0.40,
    grades: [{ count: 80, min: 0.3, max: 1.0, key: 'grey', lo: 0.24, hi: 0.38 }] });
  p.hline(0, 63, 0, 'bone', 0.58); p.hline(0, 63, 1, 'bone', 0.48);
  p.hline(0, 63, 11, 'grey', 0.10);
  /* what is left of the paint: the flanks keep it, the top is polished
     off by the tyres that stop on it */
  const n = fbm(64, 12, 8, 2, 1103);
  for (let y = 2; y < 12; y++) for (let x = 0; x < 64; x++)
    if (n[y * 64 + x] > 0.30) p.wash(x, y, 'yellow', 0.56, 0.42 + n[y * 64 + x] * 0.50);
  /* and polished off along the top, where the tyres stop on it */
  for (let x = 0; x < 64; x++) if (n[x] > 0.36) p.wash(x, 2, 'bone', 0.44, 0.5);
  for (const dx of [12, 50]) { p.disc(dx, 6, 3, 'grey', 0.12); p.disc(dx, 5, 2, 'grey', 0.24); }
  const rng = makeRng(1109);
  for (let k = 0; k < 6; k++) {                          // corners knocked off
    const x = Math.floor(rng() * 64);
    for (let d = 0; d < 3; d++) { p.ink(x + d, 0, 'bone', 0.26); p.ink(x + d, 1, 'bone', 0.32); }
  }
  /* GRIME ON A WHEEL STOP IS TYRE BLACK, not moss. It was 'grey' at
     nearly half strength here and what it did was take the yellow
     straight back off — the thing came out olive, which is the colour
     of a kerb that has been in a hedge for ten years and not of one
     forty cars a day park against. */
  p.grime(0.22, 'grey', 0.07, 1117);
  return p.snap(0.5);
};

T.CORRAIL = () => {
  /* Galvanised tube: the rail of a trolley bay, and the handrail of
     anything else out here that needs one. Sixteen to the repeat, round
     in section, with the swaged joint where two lengths meet. */
  const p = new Pix(64, 16, 1123);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++) {
    const t = Math.cos((y / 15 - 0.30) * 2.3);
    p.ink(x, y, 'grey', Math.max(0.12, 0.34 + t * 0.30));
  }
  p.hline(0, 63, 15, 'grey', 0.08);
  for (const jx of [3, 4]) for (let y = 0; y < 16; y++) {
    const t = Math.cos((y / 15 - 0.30) * 2.3);
    p.ink(jx, y, 'grey', Math.max(0.14, (jx === 3 ? 0.44 : 0.18) + t * 0.26));
  }
  /* the spangle of a hot-dip coat, which is the one thing that tells
     galvanised steel from painted steel at any distance */
  const rng = makeRng(1129);
  for (let k = 0; k < 90; k++) {
    const x = Math.floor(rng() * 64), y = 1 + Math.floor(rng() * 13);
    p.wash(x, y, 'bone', 0.58, 0.10 + rng() * 0.22);
  }
  return p.snap(0.5);
};

T.TOWNPOLE = () => {
  /* A utility pole, masked, standing in a two-sided line the way the
     yard fence does. Nothing in the world reads as America faster than
     a wood pole with eleven wires on it. */
  const p = new Pix(64, 64, 373, false);
  p.clear();
  for (let y = 0; y < 64; y++) for (let x = 27; x < 37; x++) {
    const t = 0.16 + (x === 27 || x === 36 ? -0.05 : 0) + Math.sin(y * 0.8) * 0.015;
    p.ink(x, y, 'brown', t, 255);
  }
  for (const [cy, half] of [[7, 26], [13, 20]]) {
    for (let x = 32 - half; x <= 32 + half; x++) { p.ink(x, cy, 'brown', 0.20, 255); p.ink(x, cy + 1, 'brown', 0.16, 255); p.ink(x, cy + 2, 'brown', 0.12, 255); }
    for (let k = -half + 3; k <= half - 3; k += 9) {
      p.ink(32 + k, cy - 1, 'grey', 0.30, 255);
      p.ink(32 + k, cy - 2, 'cyan', 0.30, 220);
    }
  }
  return p.snap(0.35);
};

/* =====================================================================
   THE TOWN, SECOND PASS — what a house is made of when it is a facade

   The houses have no insides now (see A HOUSE IS A FACADE in
   js/maps/town.js), and everything that used to be spent on wallpaper
   nobody saw is spent on the outside: a foundation you can see, a stoop
   and a step up to a door that is a door, and windows that are HOLES
   in the wall with a pane at the back of them rather than a picture of
   a hole. So these are the surfaces of a recess — the pane, the sill,
   the riser — and the surfaces a church and a school are lined with.
   ===================================================================== */

/* ---------- foundations, steps and the path to the door ---------- */

T.FOUNDATN = () => {
  /* Concrete block, worn thirty-two tall — one repeat is the whole
     height of the foundation, two courses of block with the top course
     catching the light and the bottom one in the dirt. */
  const p = new Pix(64, 32, 379);
  aggregate(p, 379, { baseKey: 'grey', baseLo: 0.30, baseHi: 0.38,
    grades: [{ count: 90, min: 0.3, max: 0.9, key: 'bone', lo: 0.26, hi: 0.38 }] });
  const rng = makeRng(383);
  for (const y0 of [0, 16]) {
    p.hline(0, 63, y0, 'grey', 0.18);
    p.hline(0, 63, y0 + 1, 'bone', 0.42);
    const off = y0 ? 16 : 0;
    for (let x = off; x < 64; x += 32) { p.vline(x, y0, y0 + 15, 'grey', 0.18); p.vline((x + 1) % 64, y0 + 1, y0 + 15, 'bone', 0.40); }
    for (let k = 0; k < 40; k++) p.ink(Math.floor(rng() * 64), y0 + 2 + Math.floor(rng() * 13), 'grey', 0.26 + rng() * 0.1);
  }
  /* the splash line, where the rain off the wall has darkened it */
  for (let y = 24; y < 32; y++) for (let x = 0; x < 64; x++) p.wash(x, y, 'grey', 0.14, (y - 23) / 9 * 0.5);
  p.grime(0.40, 'olive', 0.10, 389);
  return p.snap(0.5);
};

T.STONEFND = () => {
  /* Fieldstone, for the church: rubble in a lime mortar, which is what
     every church in a small town stands on and no house does. */
  const p = new Pix(64, 32, 397);
  p.fill('bone', 0.36);
  const rng = makeRng(397);
  const stones = [[8, 8, 7], [24, 7, 6], [40, 9, 8], [56, 6, 6], [4, 24, 6], [17, 23, 5], [32, 24, 7], [48, 22, 6], [60, 25, 5]];
  for (const [cx, cy, r] of stones) {
    const t = 0.30 + rng() * 0.16;
    p.disc(cx, cy, r, 'grey', t);
    p.disc(cx - 1, cy - 1, r * 0.55, 'grey', Math.min(1, t + 0.10));
    p.disc(cx + 1, cy + 2, r * 0.5, 'grey', Math.max(0, t - 0.08));
  }
  p.grime(0.36, 'olive', 0.10, 401);
  return p.snap(0.5);
};

T.STEPFACE = () => {
  /* The riser of a concrete step, sixteen tall: one repeat is one step,
     and the nosing on top is the only thing about it you ever see. */
  const p = new Pix(64, 16, 409);
  aggregate(p, 409, { baseKey: 'grey', baseLo: 0.32, baseHi: 0.40,
    grades: [{ count: 50, min: 0.3, max: 0.8, key: 'bone', lo: 0.30, hi: 0.42 }] });
  p.hline(0, 63, 0, 'bone', 0.54);
  p.hline(0, 63, 1, 'bone', 0.46);
  p.hline(0, 63, 2, 'grey', 0.22);
  p.grime(0.34, 'grey', 0.08, 419);
  return p.snap(0.5);
};

T.PAVERS = () => {
  /* Flagstones, two by two, with moss in the joints. The path from the
     sidewalk to the front door, and the paths across the park. */
  const p = new Pix(64, 64, 421);
  const rng = makeRng(421);
  p.fill('olive', 0.22);
  for (const [fx, fy] of [[0, 0], [32, 0], [0, 32], [32, 32]]) {
    const t = 0.34 + rng() * 0.08;
    p.box(fx + 2, fy + 2, 28, 28, 'bone', t);
    speckle(28, 28, 60, 431 + fx + fy, (x, y, a) => p.ink(fx + 2 + x, fy + 2 + y, 'bone', t - 0.06 + a * 0.12));
    p.hline(fx + 2, fx + 29, fy + 2, 'bone', t + 0.10);
    p.vline(fx + 2, fy + 2, fy + 29, 'bone', t + 0.08);
    p.hline(fx + 2, fx + 29, fy + 29, 'grey', 0.22);
    p.vline(fx + 29, fy + 2, fy + 29, 'grey', 0.24);
  }
  p.grime(0.26, 'olive', 0.08, 433);
  return p.snap(0.5);
};

/* ---------- the door, which is a door now ---------- */

/** A panelled front door in its casing, 64 pixels worn 48 by 80. The
 *  casing is at the edges ON PURPOSE: a door stands at the back of a
 *  recess and its jambs are the same texture wrapped round the corner,
 *  so the edge of the picture has to be the frame. */
const frontDoor = (seed, leaf, leafT) => () => {
  const p = new Pix(64, 64, seed);
  p.fill('bone', 0.50);                                   // the casing
  p.bevel(0, 0, 64, 64, 'bone', 0.62, 'bone', 0.34);
  p.box(6, 12, 52, 52, leaf, leafT);                      // the leaf
  p.box(6, 3, 52, 8, 'blue', 0.16);                       // the transom
  for (let x = 8; x < 56; x += 2) p.ink(x, 6, 'yellow', 0.34);   // a light left on in the hall
  p.hline(6, 57, 11, 'bone', 0.30);
  /* two small panels over two tall ones, each with the light on its
     top-left and the shadow on its bottom-right */
  for (const [px, py, pw, ph] of [[11, 17, 19, 12], [34, 17, 19, 12], [11, 34, 19, 26], [34, 34, 19, 26]]) {
    p.box(px, py, pw, ph, leaf, leafT - 0.05);
    p.bevel(px, py, pw, ph, leaf, Math.min(1, leafT + 0.14), leaf, Math.max(0, leafT - 0.12));
  }
  p.disc(52, 44, 2.2, 'yellow', 0.62);                    // the knob
  p.ink(52, 41, 'yellow', 0.5);                           // the lock
  for (let y = 12; y < 64; y++) p.ink(6, y, leaf, Math.min(1, leafT + 0.08));   // the hinge stile catches the light
  p.grime(0.22, 'grey', 0.06, seed + 4);
  return p.snap(0.5);
};
T.FRNTDOOR = frontDoor(439, 'red', 0.26);      // the red door
T.FRNTDOR2 = frontDoor(443, 'green', 0.20);    // the green one
T.FRNTDOR3 = frontDoor(449, 'grey', 0.12);     // and the black one

/* ---------- the window pane, at the back of its recess ---------- */

/** A whole window filling the picture: casing at the edges, a
 *  double-hung sash inside it, four lights a sash. `lit` is a lamp on
 *  in the room; `shade` is a blind pulled half way. */
function windowPane(p, lit, shade) {
  p.fill('bone', 0.50);                                   // the casing, which is also the jamb
  p.bevel(0, 0, 64, 64, 'bone', 0.62, 'bone', 0.34);
  p.box(5, 5, 54, 56, 'bone', 0.58);                      // the sash frame
  const glassKey = lit ? 'yellow' : 'blue';
  const glassT = lit ? 0.70 : 0.12;
  p.box(8, 8, 48, 50, glassKey, glassT);
  if (lit) {
    for (let y = 8; y < 58; y++) for (let x = 8; x < 56; x++) {
      const d = Math.hypot(x - 20, y - 24) / 44;
      p.ink(x, y, 'yellow', Math.max(0.36, glassT - d * 0.30));
    }
    /* a curtain drawn back on one side, and somebody's lamp */
    for (let y = 8; y < 58; y++) for (let x = 8; x < 16; x++) p.ink(x, y, 'red', 0.30 + ((x + y) % 3 === 0 ? 0.06 : 0));
    p.box(40, 30, 6, 12, 'brown', 0.24);
  } else {
    /* the night sky in the glass, and one reflection of a street lamp */
    for (let y = 8; y < 58; y++) for (let x = 8; x < 56; x++) p.ink(x, y, 'blue', 0.10 + (y - 8) / 50 * 0.05);
    for (let k = 0; k < 14; k++) p.ink(12 + k, 50 - k, 'blue', 0.26);
    for (let k = 0; k < 14; k++) p.ink(13 + k, 50 - k, 'blue', 0.20);
  }
  if (shade) {
    /* a blind, down to the meeting rail: cream, with its slats */
    for (let y = 8; y < 33; y++) for (let x = 8; x < 56; x++) p.ink(x, y, 'bone', y % 3 === 0 ? 0.46 : 0.58);
    p.hline(8, 55, 32, 'bone', 0.40);
  }
  p.box(31, 8, 2, 50, 'bone', 0.60);                      // the meeting stile
  p.box(8, 31, 48, 3, 'bone', 0.60);                      // the meeting rail
  p.hline(5, 58, 60, 'bone', 0.66);                       // the sill
  p.hline(5, 58, 61, 'grey', 0.26);
}
T.WINPANEL = () => { const p = new Pix(64, 64, 457); windowPane(p, true, false);  p.grime(0.16, 'grey', 0.05, 461); return p.snap(0.5); };
T.WINPANED = () => { const p = new Pix(64, 64, 463); windowPane(p, false, false); p.grime(0.16, 'grey', 0.05, 467); return p.snap(0.5); };
T.WINSHADE = () => { const p = new Pix(64, 64, 479); windowPane(p, false, true);  p.grime(0.16, 'grey', 0.05, 487); return p.snap(0.5); };

T.SILLWOOD = () => {
  /* The sill and the head of a window recess, seen from above and from
     below: painted board, sixteen deep, with the paint cracking. */
  const p = new Pix(64, 64, 491);
  const rng = makeRng(491);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.54 + Math.sin(x * 0.4 + y) * 0.02);
  for (let k = 0; k < 6; k++) crack(p, Math.floor(rng() * 64), Math.floor(rng() * 64), 10, 'bone', 0.40, 499 + k, 0.3);
  p.grime(0.10, 'grey', 0.04, 503);
  return p.snap(0.5);
};

/* ---------- inside the church ---------- */

T.CHURCHIN = () => {
  /* Cream plaster, warmer than the school's, because a church is lit by
     candles in the story it tells about itself even when it is lit by
     tubes. A picture rail two thirds of the way up, and nothing else. */
  const p = new Pix(64, 64, 509);
  const n = fbm(64, 64, 14, 2, 509);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.50 + n[y * 64 + x] * 0.08);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.wash(x, y, 'yellow', 0.56, 0.14);
  p.grime(0.14, 'grey', 0.05, 521);
  return p.snap(0.5);
};

T.WAINSCOT = () => {
  /* Dark oak dado panelling, forty tall: a rail on top, two raised
     panels, and a skirting in the dirt. The ledge along the nave walls
     wears it — see the church in js/maps/town.js. */
  const p = new Pix(64, 40, 523);
  const rng = makeRng(523);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.22 + rng() * 0.03 + Math.sin(y * 0.9) * 0.01);
  p.hline(0, 63, 0, 'brown', 0.44); p.hline(0, 63, 1, 'brown', 0.36); p.hline(0, 63, 3, 'brown', 0.12);
  for (const px of [4, 36]) {
    p.box(px, 7, 24, 26, 'brown', 0.27);
    p.bevel(px, 7, 24, 26, 'brown', 0.40, 'brown', 0.10);
    p.bevel(px + 3, 10, 18, 20, 'brown', 0.12, 'brown', 0.36);
  }
  p.hline(0, 63, 36, 'brown', 0.14); p.hline(0, 63, 37, 'brown', 0.10);
  return p.snap(0.5);
};

T.PEWSEAT = () => {
  /* Varnished plank, the top of a pew. */
  const p = new Pix(64, 64, 541);
  const rng = makeRng(541);
  for (let b = 0; b < 4; b++) {
    const y0 = b * 16, t = 0.32 + rng() * 0.06;
    for (let y = y0; y < y0 + 16; y++) for (let x = 0; x < 64; x++)
      p.ink(x, y, 'brown', t + Math.sin((x * 0.5 + b * 7) * 0.7) * 0.025 + (y === y0 ? -0.10 : 0) + (y === y0 + 1 ? 0.06 : 0));
  }
  return p.snap(0.5);
};

T.PEWFRONT = () => {
  /* The front of the seat, sixteen tall, with the kneeler rail under it. */
  const p = new Pix(64, 16, 547);
  for (let y = 0; y < 16; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.26 + y / 16 * 0.06);
  p.hline(0, 63, 0, 'brown', 0.42);
  p.hline(0, 63, 1, 'brown', 0.16);
  p.hline(0, 63, 12, 'brown', 0.36); p.hline(0, 63, 13, 'brown', 0.12);
  return p.snap(0.5);
};

T.PEWBACK = () => {
  /* The back of a pew, forty tall: the rail, then a panel, then the
     shelf for the hymnals on the far side, which is the side you see. */
  const p = new Pix(64, 40, 557);
  const rng = makeRng(557);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.24 + rng() * 0.03);
  p.hline(0, 63, 0, 'brown', 0.46); p.hline(0, 63, 1, 'brown', 0.40); p.hline(0, 63, 2, 'brown', 0.30); p.hline(0, 63, 4, 'brown', 0.12);
  for (let x = 6; x < 64; x += 16) p.vline(x, 5, 30, 'brown', 0.16);
  p.hline(0, 63, 31, 'brown', 0.40); p.hline(0, 63, 32, 'brown', 0.12);
  for (let x = 4; x < 60; x += 12) { p.box(x, 34, 8, 5, 'red', 0.30); p.vline(x + 8, 34, 38, 'brown', 0.14); }   // the hymnals
  return p.snap(0.5);
};

T.CHANCEL = () => {
  /* Red carpet up the steps and across the chancel. */
  const p = new Pix(64, 64, 563);
  aggregate(p, 563, { baseKey: 'red', baseLo: 0.22, baseHi: 0.30,
    grades: [{ count: 700, min: 0.2, max: 0.7, key: 'red', lo: 0.18, hi: 0.32 }] });
  p.grime(0.16, 'grey', 0.05, 569);
  return p.snap(0.5);
};

T.ALTARFRT = () => {
  /* The frontal: white linen with a band of purple and a gold fringe. */
  const p = new Pix(64, 40, 571);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.74 + Math.sin(x * 0.6) * 0.03);
  p.hline(0, 63, 0, 'bone', 0.86);
  for (let y = 10; y < 18; y++) p.hline(0, 63, y, 'purple', 0.44);
  p.hline(0, 63, 9, 'yellow', 0.62); p.hline(0, 63, 18, 'yellow', 0.62);
  for (let x = 0; x < 64; x += 2) p.vline(x, 34, 39, 'yellow', 0.58);
  p.hline(0, 63, 33, 'yellow', 0.66);
  return p.snap(0.5);
};

T.ALTARTOP = () => {
  const p = new Pix(64, 64, 577);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.76 + Math.sin(y * 0.5) * 0.03);
  p.frame(0, 0, 64, 64, 'bone', 0.86);
  p.box(6, 6, 52, 52, 'bone', 0.80);                      // the fair linen
  p.disc(14, 32, 3, 'yellow', 0.66); p.disc(50, 32, 3, 'yellow', 0.66);   // candlesticks
  p.box(28, 20, 8, 24, 'yellow', 0.60); p.box(22, 26, 20, 6, 'yellow', 0.60);   // the cross, lying flat
  return p.snap(0.5);
};

T.REREDOS = () => {
  /* The panel behind the altar, a hundred and twenty-eight square: dark
     oak and a gilt cross. One repeat is the whole thing. */
  const p = new Pix(64, 64, 587);
  const rng = makeRng(587);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.20 + rng() * 0.03);
  p.frame(0, 0, 64, 64, 'brown', 0.36);
  p.frame(3, 3, 58, 58, 'brown', 0.10);
  p.box(28, 6, 8, 52, 'yellow', 0.62);
  p.box(14, 18, 36, 8, 'yellow', 0.62);
  p.vline(28, 6, 57, 'yellow', 0.80); p.hline(14, 49, 18, 'yellow', 0.80);
  p.vline(35, 6, 57, 'yellow', 0.40); p.hline(14, 49, 25, 'yellow', 0.40);
  return p.snap(0.5);
};

T.WINREVEL = () => {
  /* The reveal of a church window: white painted board, the same as the
     jamb of any window, but wider and in better repair. */
  const p = new Pix(64, 64, 593);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'bone', 0.62 + Math.sin(y * 0.3) * 0.02);
  p.grime(0.08, 'grey', 0.04, 599);
  return p.snap(0.5);
};

/* ---------- inside the school ---------- */

/** A steel-framed school window, nine lights, 64 square and worn so. */
function schoolWindow(p, lit) {
  p.fill('grey', 0.34);                                   // the frame, which is also the reveal
  p.bevel(0, 0, 64, 64, 'grey', 0.44, 'grey', 0.22);
  const g = lit ? 0.62 : 0.11;
  p.box(4, 4, 56, 56, lit ? 'yellow' : 'blue', g);
  if (lit) {
    for (let y = 4; y < 60; y++) for (let x = 4; x < 60; x++) p.ink(x, y, 'yellow', g - (y - 4) / 56 * 0.10);
    for (let y = 4; y < 60; y++) for (let x = 4; x < 60; x++) p.wash(x, y, 'cyan', 0.8, 0.22);   // the tube light is green
    for (let y = 40; y < 60; y += 5) p.hline(8, 56, y, 'yellow', 0.40);                          // desks and their shadows
  }
  for (const x of [22, 41]) p.box(x, 4, 2, 56, 'grey', 0.42);
  for (const y of [22, 41]) p.box(4, y, 56, 2, 'grey', 0.42);
  p.hline(0, 63, 62, 'grey', 0.46); p.hline(0, 63, 63, 'grey', 0.20);
}
T.SCHWINLT = () => { const p = new Pix(64, 64, 601); schoolWindow(p, true);  p.grime(0.18, 'grey', 0.05, 607); return p.snap(0.5); };
T.SCHWINDK = () => { const p = new Pix(64, 64, 613); schoolWindow(p, false); p.grime(0.18, 'grey', 0.05, 617); return p.snap(0.5); };

T.DESKTOP = () => {
  /* The top of a desk, from above, and one repeat is one desk: the
     laminate, the pencil groove along the front edge, the hardwood lip
     round it, and everything that has ever been done to it with a
     compass point. It used to be a blank sheet with one line on it,
     which at the size a desk is drawn is a blank sheet. */
  const p = new Pix(28, 20, 619);
  const n = fbm(28, 20, 8, 2, 619);
  for (let y = 0; y < 20; y++) for (let x = 0; x < 28; x++)
    p.ink(x, y, 'bone', 0.54 + n[y * 28 + x] * 0.06);
  /* the hardwood lip, lit on the near edges */
  p.frame(0, 0, 28, 20, 'brown', 0.26);
  p.hline(0, 27, 0, 'brown', 0.42);
  p.vline(0, 0, 19, 'brown', 0.40);
  /* the pencil groove along the top edge, and a pencil in it */
  p.hline(2, 25, 3, 'grey', 0.20);
  p.hline(2, 25, 4, 'bone', 0.70);
  const rng = makeRng(631);
  if (rng() < 0.6) { p.hline(8, 17, 3, 'yellow', 0.56); p.ink(18, 3, 'grey', 0.30); }
  /* scratched initials, ink, and the ring off a bottle */
  for (let i = 0; i < 9; i++) {
    const x = 4 + Math.floor(rng() * 20), y = 7 + Math.floor(rng() * 11);
    const d = rng() < 0.5 ? 1 : -1;
    for (let k = 0; k < 2 + Math.floor(rng() * 3); k++) p.wash(x + k, y + k * d, 'brown', 0.16, 0.5);
  }
  p.wash(19, 13, 'blue', 0.30, 0.5); p.wash(20, 13, 'blue', 0.30, 0.4);
  for (let a = 0; a < 20; a++) {
    const x = Math.round(9 + Math.cos(a / 20 * 6.283) * 4), y = Math.round(13 + Math.sin(a / 20 * 6.283) * 3);
    p.wash(x, y, 'brown', 0.34, 0.28);
  }
  p.grime(0.3, 'grey', 0.07, 632);
  return p.snap(0.45);
};

T.DESKFRNT = () => {
  /* The side of a school desk, twenty-four tall: the steel legs, the
     book box between them, the shadow under the top. */
  const p = new Pix(64, 24, 641, false);
  p.clear();
  p.hline(0, 63, 0, 'brown', 0.30, 255); p.hline(0, 63, 1, 'brown', 0.22, 255);
  for (const x of [4, 58]) { p.box(x, 2, 3, 22, 'grey', 0.30, 255); p.vline(x, 2, 23, 'grey', 0.40, 255); }
  p.box(9, 3, 46, 11, 'brown', 0.30, 255);
  p.bevel(9, 3, 46, 11, 'brown', 0.40, 'brown', 0.16);
  for (let x = 12; x < 52; x += 8) p.box(x, 5, 5, 6, ['red', 'blue', 'green'][Math.floor(x / 8) % 3], 0.36, 255);   // the books
  return p.snap(0.35);
};

/* =====================================================================
   A DESK IS A DESK AND A CHAIR

   The school's desks were one raised block apiece wearing a laminate
   top and a masked side, which from the door reads as a run of lab
   benches. A mid-century American classroom desk is a TOP, a SEAT
   BEHIND IT and a BACK behind that, all turned to face the blackboard —
   three raised floors in a row, and the silhouette is the whole of it.

   EVERY ONE OF THESE IS DECLARED AT THE SIZE OF ITS OWN PIECE, because
   the pieces are small: a chair back is six units wide and a picture
   tiling four times across six units is a pattern, not a chair.
   ===================================================================== */

T.CHAIRSIT = () => {
  /* A moulded plywood seat from above: the grain runs across, the front
     edge is rolled, and the middle is worn paler than the rim by every
     year of children who have sat on it. */
  const p = new Pix(36, 40, 660);
  const n = fbm(36, 40, 8, 2, 660);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 36; x++)
    p.ink(x, y, 'brown', 0.40 + n[y * 36 + x] * 0.08);
  /* the grain, across the seat */
  const rng = makeRng(661);
  for (let y = 0; y < 40; y++) { const t = 0.34 + rng() * 0.16;
    for (let x = 0; x < 36; x++) if (rng() < 0.55) p.wash(x, y, 'brown', t, 0.4); }
  /* worn in the middle */
  for (let y = 6; y < 34; y++) for (let x = 5; x < 31; x++) {
    const d = 1 - Math.hypot((x - 18) / 15, (y - 20) / 16);
    if (d > 0) p.wash(x, y, 'brown', 0.62, d * 0.4);
  }
  /* the rolled front edge and the shadow at the back */
  p.hline(0, 35, 0, 'brown', 0.20);
  p.hline(0, 35, 38, 'brown', 0.58);
  p.hline(0, 35, 39, 'brown', 0.26);
  p.vline(0, 0, 39, 'brown', 0.52); p.vline(35, 0, 39, 'brown', 0.22);
  return p.snap(0.45);
};

T.CHAIRLEG = () => {
  /* Under a seat: two steel legs and the daylight between them. Masked,
     so the classroom floor shows through — a chair with a solid box
     under it is a crate. */
  const p = new Pix(36, 18, 662, false);
  p.clear();
  for (const x of [3, 30]) {
    p.box(x, 0, 3, 18, 'grey', 0.26, 255);
    p.vline(x, 0, 17, 'grey', 0.40, 255);
    p.vline(x + 2, 0, 17, 'grey', 0.12, 255);
  }
  /* the stretcher between them, and the apron under the seat */
  p.box(0, 0, 36, 2, 'brown', 0.22, 255);
  p.hline(0, 35, 0, 'brown', 0.34, 255);
  p.box(5, 11, 26, 2, 'grey', 0.24, 255);
  p.hline(5, 30, 11, 'grey', 0.38, 255);
  return p.snap(0.3);
};

T.CHAIRBAK = () => {
  /* The back of the chair, and the legs under it. Six units wide on the
     chair and twenty from the side, so it is seen BOTH ways and has to
     read either way — which is why nothing in it happens at one x: the
     panel runs the width, the slot runs the width, the stretcher runs
     the width, and any crop of it is still a back over a leg. */
  const p = new Pix(36, 40, 663);
  p.clear();
  /* the legs, bottom half */
  for (const x of [3, 30]) { p.box(x, 20, 3, 20, 'grey', 0.26, 255); p.vline(x, 20, 39, 'grey', 0.40, 255); }
  p.box(0, 30, 36, 2, 'grey', 0.22, 255);
  /* the plywood back panel over them, with the slot every one of these
     has and a rolled top edge */
  p.box(0, 0, 36, 22, 'brown', 0.38, 255);
  const n = fbm(36, 22, 6, 2, 663);
  for (let y = 0; y < 22; y++) for (let x = 0; x < 36; x++)
    p.wash(x, y, 'brown', 0.34 + n[y * 36 + x] * 0.18, 0.5);
  p.hline(0, 35, 0, 'brown', 0.62);
  p.hline(0, 35, 1, 'brown', 0.48);
  p.hline(0, 35, 21, 'brown', 0.16);
  p.box(6, 8, 24, 3, 'brown', 0.14, 255);
  p.hline(6, 29, 11, 'brown', 0.52, 255);
  return p.snap(0.35);
};

T.TEACHDSK = () => {
  /* The front of the teacher's desk: a pedestal of three drawers with
     pulls, a knee hole, and the modesty panel across it. Thirty-two
     tall, which is what the desk is. */
  const p = new Pix(64, 32, 664);
  const n = fbm(64, 32, 8, 2, 664);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.30 + n[y * 64 + x] * 0.06);
  p.hline(0, 63, 0, 'brown', 0.52);
  p.hline(0, 63, 1, 'brown', 0.40);
  /* the drawer pedestal on the left */
  p.box(2, 3, 22, 27, 'brown', 0.34);
  p.frame(2, 3, 22, 27, 'brown', 0.20);
  for (let i = 0; i < 3; i++) {
    const y = 4 + i * 9;
    p.box(4, y, 18, 7, 'brown', 0.38);
    p.hline(4, 21, y, 'brown', 0.50);
    p.hline(4, 21, y + 6, 'brown', 0.16);
    p.box(10, y + 2, 6, 2, 'grey', 0.44);                 // the pull
    p.hline(10, 15, y + 2, 'grey', 0.62);
  }
  /* the knee hole, and the modesty panel across the back of it */
  p.box(24, 3, 38, 27, 'brown', 0.12);
  p.box(24, 3, 38, 12, 'brown', 0.26);
  p.hline(24, 37, 12, 'brown', 0.08);
  /* and a second pedestal, cropped, so a wider desk still reads */
  p.box(38, 3, 24, 27, 'brown', 0.34);
  p.frame(38, 3, 24, 27, 'brown', 0.20);
  for (let i = 0; i < 3; i++) {
    const y = 4 + i * 9;
    p.box(40, y, 18, 7, 'brown', 0.38);
    p.hline(40, 57, y, 'brown', 0.50);
    p.hline(40, 57, y + 6, 'brown', 0.16);
    p.box(46, y + 2, 6, 2, 'grey', 0.44);
    p.hline(46, 51, y + 2, 'grey', 0.62);
  }
  p.box(0, 30, 64, 2, 'grey', 0.14);
  p.grime(0.3, 'grey', 0.08, 665);
  return p.snap(0.45);
};

/* =====================================================================
   THE GYM, THE AUDITORIUM AND WHAT A SCHOOL HAS ON ITS WALLS

   At the user's request: more in the gym, an auditorium that was not
   there, and detail everywhere else. All of it is either a free box
   above head height, a band on a wall, or the top of a raised floor —
   which between them is every trick this map has.
   ===================================================================== */

T.BACKBORD = () => {
  /* A backboard from the front: the fan-shaped board, the painted
     rectangle, the ring and the net. It hangs above head height on a
     free box, so this is the only face of it anybody reads. */
  const p = new Pix(64, 40, 700);
  p.clear();
  /* the board: plywood, painted white, with the black border */
  p.box(6, 0, 52, 30, 'bone', 0.80, 255);
  p.frame(6, 0, 52, 30, 'grey', 0.16);
  p.frame(7, 1, 50, 28, 'bone', 0.92);
  /* the shooter's square */
  p.frame(21, 10, 22, 15, 'grey', 0.14);
  p.frame(22, 11, 20, 13, 'grey', 0.10);
  /* the ring, and the net under it */
  p.box(22, 29, 20, 2, 'rust', 0.52, 255);
  p.hline(22, 41, 29, 'rust', 0.70, 255);
  for (let i = 0; i < 6; i++) {
    const x = 23 + i * 3;
    for (let k = 0; k < 7; k++) p.ink(x + Math.round(k * (i < 3 ? 0.4 : -0.4)), 31 + k, 'bone', 0.72 - k * 0.04, 255);
  }
  for (let y = 33; y < 38; y += 2) p.hline(25, 38, y, 'bone', 0.58, 255);
  return p.snap(0.35);
};

T.SCOREBRD = () => {
  /* The scoreboard: HOME and GUEST, four amber digits, the period and
     the clock. Lit past one on the prop, which is what makes the digits
     read as bulbs and the case as a case. */
  const p = new Pix(64, 40, 702);
  p.fill('grey', 0.10);
  p.bevel(0, 0, 64, 40, 'grey', 0.32, 'grey', 0.04);
  const digit = (x, y, w, h, t) => {
    p.box(x, y, w, h, 'yellow', 0.16);
    p.hline(x, x + w - 1, y, 'yellow', t);
    p.hline(x, x + w - 1, y + Math.floor(h / 2), 'yellow', t * 0.8);
    p.hline(x, x + w - 1, y + h - 1, 'yellow', t);
    p.vline(x, y, y + h - 1, 'yellow', t * 0.9);
    p.vline(x + w - 1, y, y + h - 1, 'yellow', t * 0.9);
  };
  drawText(p, 'HOME', 3, 3, 'bone', 0.72, 1);
  drawText(p, 'GUEST', 38, 3, 'bone', 0.72, 1);
  digit(4, 11, 7, 12, 0.90); digit(13, 11, 7, 12, 0.90);
  digit(40, 11, 7, 12, 0.90); digit(49, 11, 7, 12, 0.90);
  /* the clock across the middle, and the period box */
  p.box(22, 11, 16, 12, 'grey', 0.06);
  digit(23, 12, 6, 10, 0.72); digit(31, 12, 6, 10, 0.72);
  drawTextCentred(p, 'PERIOD', 32, 27, 'bone', 0.56, 1);
  digit(29, 33, 6, 6, 0.86);
  p.frame(0, 0, 64, 40, 'grey', 0.24);
  return p.snap(0.3);
};

T.WALLBARS = () => {
  /* Swedish bars: two uprights and a ladder of dowels. Masked, so the
     gym wall shows between the rungs — the whole of a wall bar is the
     gap. */
  const p = new Pix(40, 64, 704, false);
  p.clear();
  for (const x of [1, 35]) {
    p.box(x, 0, 4, 64, 'brown', 0.36, 255);
    p.vline(x, 0, 63, 'brown', 0.52, 255);
    p.vline(x + 3, 0, 63, 'brown', 0.18, 255);
  }
  for (let y = 3; y < 64; y += 7) {
    p.box(5, y, 30, 2, 'brown', 0.44, 255);
    p.hline(5, 34, y, 'brown', 0.62, 255);
    p.hline(5, 34, y + 1, 'brown', 0.22, 255);
  }
  return p.snap(0.35);
};

T.PENNANT = () => {
  /* A championship pennant off a truss: a felt triangle with a year on
     it, and the tail of the next one. Masked, hanging in the dark. */
  const p = new Pix(48, 32, 706, false);
  p.clear();
  for (let y = 0; y < 26; y++) {
    const w = Math.round(44 * (1 - y / 30));
    for (let x = 2; x < 2 + w; x++) p.ink(x, y, y < 3 || y > 22 ? 'blue' : 'blue', 0.24 + (y % 2) * 0.05, 255);
  }
  p.box(2, 0, 7, 26, 'yellow', 0.52, 255);
  for (let y = 0; y < 26; y++) { p.ink(2, y, 'blue', 0.42, 255); }
  drawText(p, '54', 12, 8, 'yellow', 0.80, 1);
  drawText(p, '61', 12, 16, 'yellow', 0.66, 1);
  for (let y = 0; y < 26; y++) {
    const w = Math.round(44 * (1 - y / 30));
    p.ink(2 + w, y, 'blue', 0.10, 255);
  }
  return p.snap(0.3);
};

T.AUDSEAT = () => {
  /* Four theatre seats from above: the backs, the gap between the
     standards, and the arm between each pair. One repeat is four
     seats, which is what stops a block of them being wallpaper. */
  const p = new Pix(64, 28, 708);
  p.fill('grey', 0.12);
  for (let i = 0; i < 4; i++) {
    const x = i * 16;
    /* the back, seen from above and behind: upholstery with a roll.
       PAINTED WELL UP THE RED RAMP, because a hall is a dim room and a
       seat at the bottom of the ramp in a dim room is a dark patch —
       the first cut had the backs at 0.24 and a bank of them read as
       one red floor with lines on it. */
    p.box(x + 2, 2, 12, 14, 'red', 0.40);
    p.hline(x + 2, x + 13, 2, 'red', 0.60);
    p.hline(x + 2, x + 13, 3, 'red', 0.50);
    p.hline(x + 2, x + 13, 15, 'red', 0.18);
    for (let y = 5; y < 15; y += 3) p.hline(x + 3, x + 12, y, 'red', 0.30);
    /* the seat pan, tipped up, darker */
    p.box(x + 3, 17, 10, 8, 'red', 0.26);
    p.hline(x + 3, x + 12, 17, 'red', 0.46);
    /* the cast standard between them */
    p.box(x + 14, 2, 3, 23, 'grey', 0.30);
    p.vline(x + 14, 2, 24, 'grey', 0.50);
  }
  p.hline(0, 63, 0, 'grey', 0.08);
  p.hline(0, 63, 26, 'grey', 0.20);
  p.hline(0, 63, 27, 'grey', 0.06);
  p.grime(0.3, 'grey', 0.08, 709);
  return p.snap(0.45);
};

T.CURTAIN = () => {
  /* The house curtain: heavy red velvet in folds. What makes velvet
     velvet is that the highlight is on the SIDE of a fold and not on
     its crest, and that the colour goes darker as it goes brighter —
     so the lit edge of a fold is nearly bone and the body of it is
     nearly black. */
  const p = new Pix(48, 64, 710);
  const rng = makeRng(711);
  const folds = [];
  for (let i = 0; i < 6; i++) folds.push(3 + i * 8 + Math.floor(rng() * 3));
  for (let x = 0; x < 48; x++) {
    /* distance to the nearest fold crest, wrapped */
    let d = 99;
    for (const c of folds) d = Math.min(d, Math.abs(((x - c + 72) % 48) - 24) === 24 ? 99 : Math.abs(x - c), Math.abs(x - c + 48), Math.abs(x - c - 48));
    const t = d < 1 ? 0.46 : d < 2 ? 0.34 : d < 4 ? 0.22 : 0.13;
    for (let y = 0; y < 64; y++) p.ink(x, y, 'red', t);
  }
  /* the vertical nap, and the swag of the hem */
  for (let y = 0; y < 64; y++) for (let x = 0; x < 48; x++)
    if ((x * 7 + y * 3) % 11 === 0) p.wash(x, y, 'red', 0.30, 0.25);
  p.box(0, 0, 48, 3, 'red', 0.08);
  p.hline(0, 47, 3, 'red', 0.40);
  for (let x = 0; x < 48; x++) {
    const h = 60 + Math.round(Math.sin(x / 48 * 6.283 * 3) * 2);
    for (let y = h; y < 64; y++) p.ink(x, y, 'red', 0.07);
    p.ink(x, h, 'red', 0.30);
  }
  return p.snap(0.45);
};

T.PROSCEN = () => {
  /* The proscenium header: plaster, a moulded band top and bottom, and
     the cove the house lights sit in. One repeat is the whole depth of
     it, so the mouldings happen once. */
  const p = new Pix(64, 64, 712);
  const n = fbm(64, 64, 8, 2, 712);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.40 + n[y * 64 + x] * 0.06);
  /* the moulding at the top, three courses of it */
  for (const [y, h, t] of [[0, 3, 0.62], [4, 2, 0.30], [7, 4, 0.52]]) {
    p.box(0, y, 64, h, 'bone', t);
    p.hline(0, 63, y, 'bone', Math.min(1, t + 0.20));
    p.hline(0, 63, y + h - 1, 'bone', Math.max(0, t - 0.22));
  }
  /* the cove, with the light in it washing up the plaster */
  p.box(0, 13, 64, 5, 'bone', 0.16);
  p.hline(0, 63, 13, 'bone', 0.08);
  p.hline(0, 63, 17, 'yellow', 0.66);
  for (let y = 18; y < 34; y++) for (let x = 0; x < 64; x++)
    p.wash(x, y, 'yellow', 0.60, (1 - (y - 18) / 16) * 0.22);
  /* the panelled face under it */
  for (let x = 4; x < 64; x += 20) {
    p.frame(x, 22, 16, 34, 'bone', 0.30);
    p.hline(x, x + 15, 22, 'bone', 0.54);
    p.vline(x, 22, 55, 'bone', 0.52);
  }
  p.box(0, 58, 64, 4, 'bone', 0.54);
  p.hline(0, 63, 58, 'bone', 0.72);
  p.hline(0, 63, 62, 'bone', 0.18);
  return p.snap(0.45);
};

T.TROPHY = () => {
  /* The trophy case in the lobby: glass, three shelves, and what is on
     them. Lit, because the one in every school is. */
  const p = new Pix(64, 64, 714);
  p.fill('grey', 0.08);
  p.box(3, 3, 58, 58, 'brown', 0.16);
  const rng = makeRng(715);
  for (let sh = 0; sh < 3; sh++) {
    const y = 8 + sh * 18;
    /* the shelf itself */
    p.box(4, y + 14, 56, 2, 'brown', 0.34);
    p.hline(4, 59, y + 14, 'brown', 0.52);
    /* cups and plaques on it */
    let x = 6;
    while (x < 56) {
      const w = 4 + Math.floor(rng() * 5), h = 6 + Math.floor(rng() * 8);
      const k = rng() < 0.6 ? 'yellow' : 'grey';
      p.box(x, y + 14 - h, w, h, k, 0.34 + rng() * 0.2);
      p.vline(x, y + 14 - h, y + 13, k, 0.62);
      p.box(x - 1, y + 12, w + 2, 2, 'brown', 0.26);
      x += w + 3 + Math.floor(rng() * 4);
    }
  }
  /* the glass: two raked highlights and the mullion between the doors */
  for (let y = 3; y < 61; y++) for (let x = 3; x < 61; x++) {
    if ((x + y * 2) % 41 < 3) p.wash(x, y, 'bone', 0.86, 0.18);
  }
  p.vline(32, 3, 60, 'grey', 0.30);
  p.frame(2, 2, 60, 60, 'brown', 0.38);
  p.frame(0, 0, 64, 64, 'brown', 0.22);
  return p.snap(0.4);
};

T.NOTICEBD = () => {
  /* A cork board with things pinned to it, most of them crooked. */
  const p = new Pix(64, 48, 716);
  const n = fbm(64, 48, 10, 3, 716);
  for (let y = 0; y < 48; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'rust', 0.22 + n[y * 64 + x] * 0.10);
  speckle(64, 48, 300, 717, (x, y, a, b) => p.wash(x, y, 'rust', a < 0.5 ? 0.14 : 0.34, 0.3 + b * 0.3));
  const rng = makeRng(718);
  for (let i = 0; i < 7; i++) {
    const w = 9 + Math.floor(rng() * 9), h = 10 + Math.floor(rng() * 9);
    const x = 2 + Math.floor(rng() * (60 - w)), y = 2 + Math.floor(rng() * (44 - h));
    p.box(x, y, w, h, 'bone', 0.66 + rng() * 0.2);
    p.hline(x, x + w - 1, y, 'bone', 0.90);
    p.vline(x + w - 1, y, y + h - 1, 'grey', 0.18);
    for (let r = 2; r < h - 1; r += 2) p.hline(x + 1, x + w - 2, y + r, 'grey', 0.22);
    p.ink(x + Math.floor(w / 2), y + 1, ['red', 'yellow', 'green', 'blue'][Math.floor(rng() * 4)], 0.60);
  }
  p.frame(0, 0, 64, 48, 'brown', 0.30);
  p.frame(1, 1, 62, 46, 'brown', 0.44);
  return p.snap(0.45);
};

T.RADIATOR = () => {
  /* A cast iron radiator under a window: columns, the top rail, the
     valve at one end. One repeat is eight columns. */
  const p = new Pix(64, 32, 720);
  p.clear();
  for (let i = 0; i < 8; i++) {
    const x = 1 + i * 8;
    p.box(x, 2, 6, 27, 'bone', 0.34, 255);
    p.vline(x, 2, 28, 'bone', 0.52, 255);
    p.vline(x + 5, 2, 28, 'grey', 0.14, 255);
    p.box(x + 2, 6, 2, 19, 'bone', 0.22, 255);
  }
  p.box(0, 0, 64, 3, 'bone', 0.46, 255);
  p.hline(0, 63, 0, 'bone', 0.66, 255);
  p.box(0, 29, 64, 3, 'bone', 0.20, 255);
  p.box(58, 20, 5, 7, 'grey', 0.40, 255);        // the valve
  p.hline(58, 62, 20, 'grey', 0.60, 255);
  streaks(p, 3, 721, 'rust', 0.24, 0.3);
  return p.snap(0.4);
};

T.FOUNTAIN = () => {
  /* A drinking fountain: the stainless bowl, the bubbler, the push bar
     and the trap under it. Twenty-four wide and thirty tall, which is
     what one is. */
  const p = new Pix(24, 30, 722, false);
  p.clear();
  p.box(1, 0, 22, 12, 'grey', 0.44, 255);
  p.hline(1, 22, 0, 'grey', 0.68, 255);
  p.hline(1, 22, 11, 'grey', 0.16, 255);
  /* the bowl, pressed into it */
  p.box(4, 2, 16, 8, 'grey', 0.26, 255);
  p.frame(4, 2, 16, 8, 'grey', 0.14, 255);
  p.box(6, 4, 12, 4, 'grey', 0.34, 255);
  p.box(10, 1, 4, 3, 'grey', 0.56, 255);        // the bubbler
  p.box(3, 9, 6, 2, 'grey', 0.58, 255);         // the push bar
  /* the trap and the supply under it */
  p.box(9, 12, 6, 8, 'grey', 0.30, 255);
  p.vline(9, 12, 19, 'grey', 0.46, 255);
  p.box(10, 20, 4, 10, 'grey', 0.22, 255);
  return p.snap(0.35);
};

T.SCHCLOCK = () => {
  /* The clock over a classroom door, in its wire guard. */
  const p = new Pix(24, 24, 724, false);
  p.clear();
  p.disc(12, 12, 11.4, 'grey', 0.34);
  p.disc(12, 12, 10, 'bone', 0.80);
  p.disc(12, 12, 9, 'bone', 0.88);
  for (let i = 0; i < 12; i++) {
    const a = i / 12 * 6.2832;
    p.ink(Math.round(12 + Math.cos(a) * 7.5), Math.round(12 + Math.sin(a) * 7.5), 'grey', 0.10);
  }
  p.line(12, 12, 12, 6, 'grey', 0.06);
  p.line(12, 12, 17, 14, 'grey', 0.06);
  p.ink(12, 12, 'grey', 0.20);
  /* the guard */
  for (let i = 0; i < 4; i++) {
    const a = i / 4 * 6.2832 + 0.4;
    p.line(12, 12, Math.round(12 + Math.cos(a) * 11), Math.round(12 + Math.sin(a) * 11), 'grey', 0.30);
  }
  return p.snap(0.3);
};

/* ---------- the cemetery ---------- */

T.GRAVESTN = () => {
  /* Granite, worn twenty-four wide and thirty-two tall so that one
     repeat is one stone's face: the panel where the name was, and no
     name on it, ever. */
  const p = new Pix(64, 64, 653);
  aggregate(p, 653, { baseKey: 'grey', baseLo: 0.34, baseHi: 0.42,
    grades: [{ count: 200, min: 0.3, max: 0.8, key: 'grey', lo: 0.30, hi: 0.50 }] });
  p.hline(0, 63, 0, 'grey', 0.54); p.hline(0, 63, 1, 'grey', 0.48);
  p.box(10, 12, 44, 30, 'grey', 0.28);
  p.frame(10, 12, 44, 30, 'grey', 0.22);
  for (const y of [18, 24, 30, 36]) p.hline(16, 48 - (y === 36 ? 12 : 0), y, 'grey', 0.18);
  p.grime(0.40, 'olive', 0.12, 659);
  return p.snap(0.5);
};

/* ---------- the street lamp's own light, on the ground ---------- */

T.LAMPPOOL = () => {
  /* The sidewalk directly under a lamp: the same concrete, with the
     lamp's own base plate cast into it. */
  const p = new Pix(64, 64, 661);
  aggregate(p, 661, { baseKey: 'bone', baseLo: 0.32, baseHi: 0.42,
    grades: [{ count: 150, min: 0.4, max: 1.0, key: 'bone', lo: 0.24, hi: 0.46 },
             { count: 40,  min: 0.4, max: 1.1, key: 'grey', lo: 0.26, hi: 0.38 }] });
  p.hline(0, 63, 0, 'grey', 0.16); p.hline(0, 63, 1, 'bone', 0.48);
  p.grime(0.24, 'grey', 0.07, 667);
  return p.snap(0.5);
};

/* ---------- TRIM: what a building is made of where it stops ----------

   A wall that runs from the ground to the eaves with nothing on it is a
   slab, and the town was full of them. Everything in this section is a
   BAND: a strip of wall a few units tall that a projecting piece of
   geometry wears, and which the disagreement rule in js/level.js draws
   because that piece stands proud of the wall behind it. A water table
   at the bottom, a string course between the storeys, a cornice at the
   top — three bands and a slab becomes a building. See the church and
   the school in js/maps/town.js for where each one goes.
   ------------------------------------------------------------------ */

T.WATERTBL = () => {
  /* The stone course a brick or clapboard wall stands on, sixteen tall
     and worn so: a weathered top that throws the rain off, a drip under
     it, and the joints of a stone that was laid in four-foot lengths. */
  const p = new Pix(64, 16, 701);
  aggregate(p, 701, { baseKey: 'bone', baseLo: 0.30, baseHi: 0.38,
    grades: [{ count: 180, min: 0.3, max: 0.9, key: 'grey', lo: 0.26, hi: 0.40 }] });
  p.hline(0, 63, 0, 'bone', 0.52); p.hline(0, 63, 1, 'bone', 0.46);   // the wash on top, catching the light
  p.hline(0, 63, 13, 'grey', 0.16); p.hline(0, 63, 14, 'grey', 0.12); // the drip, in shadow
  for (const x of [0, 32]) p.vline(x, 2, 12, 'grey', 0.20);           // the joints
  p.grime(0.30, 'grey', 0.07, 709);
  return p.snap(0.5);
};

T.CORNICE = () => {
  /* Where a wall stops. Twenty-four tall and read from below, so it is
     three mouldings and a shadow under each: the bed, the corona that
     stands furthest out, and the cyma over it. The dark line at the
     bottom is what makes the whole thing project rather than be a
     stripe of paler paint. */
  const p = new Pix(64, 24, 719);
  aggregate(p, 719, { baseKey: 'bone', baseLo: 0.36, baseHi: 0.44,
    grades: [{ count: 140, min: 0.3, max: 0.8, key: 'grey', lo: 0.30, hi: 0.44 }] });
  p.hline(0, 63, 23, 'grey', 0.10); p.hline(0, 63, 22, 'grey', 0.14);  // the shadow it casts on itself
  p.hline(0, 63, 17, 'bone', 0.56); p.hline(0, 63, 18, 'grey', 0.18);  // the bed mould
  p.hline(0, 63, 11, 'bone', 0.60); p.hline(0, 63, 12, 'grey', 0.20);  // under the corona
  for (let y = 4; y < 11; y++) p.hline(0, 63, y, 'bone', 0.48 - (y - 4) * 0.012);
  p.hline(0, 63, 0, 'bone', 0.64); p.hline(0, 63, 1, 'bone', 0.58);    // the cap, in the sun
  for (let x = 6; x < 64; x += 12) { p.vline(x, 19, 23, 'grey', 0.22); p.vline(x + 1, 19, 23, 'bone', 0.50); }  // the modillions
  p.grime(0.22, 'grey', 0.06, 727);
  return p.snap(0.5);
};

T.CORNRBRD = () => {
  /* The board that closes the corner of a clapboard building, and the
     face of a church buttress, which is the same board four times as
     wide. Painted the trim white, which is a shade whiter than the
     siding, and beaded down both edges. */
  const p = new Pix(64, 64, 733);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.62 + Math.sin(y * 0.21 + x * 0.05) * 0.015);
  p.vline(0, 0, 63, 'bone', 0.72); p.vline(1, 0, 63, 'bone', 0.68);
  p.vline(62, 0, 63, 'grey', 0.26); p.vline(63, 0, 63, 'grey', 0.20);
  for (const x of [5, 58]) { p.vline(x, 0, 63, 'bone', 0.74); p.vline(x + 1, 0, 63, 'grey', 0.30); }  // the bead
  const rng = makeRng(739);
  for (let k = 0; k < 4; k++) crack(p, Math.floor(rng() * 64), Math.floor(rng() * 64), 12, 'bone', 0.44, 743 + k, 0.25);
  p.grime(0.12, 'grey', 0.05, 751);
  return p.snap(0.5);
};

T.PILASTR = () => {
  /* A brick pier standing proud of a brick wall. It is the SAME brick —
     a school does not change material for its piers — so what has to
     read at fifty feet is the light on it, and that is the job of the
     band this texture is worn on rather than of the texture. What is
     here is a bond one course out of step with the wall's, which is
     what a pier bonded into a wall actually looks like, and the two
     soldier courses that cap it. */
  const p = new Pix(64, 64, 757);
  brickwork(p, 757, 'brown', 0.24, 0.42);
  for (let y = 0; y < 6; y++) p.hline(0, 63, y, 'brown', 0.30 + y * 0.01);
  for (let x = 0; x < 64; x += 8) p.vline(x, 0, 5, 'grey', 0.22);       // the soldiers on top
  p.vline(0, 0, 63, 'brown', 0.44); p.vline(1, 0, 63, 'brown', 0.38);   // the arris, lit
  p.vline(63, 0, 63, 'grey', 0.14);                                     // and the one in shadow
  p.grime(0.30, 'grey', 0.07, 761);
  return p.snap(0.5);
};

/* ---------- the church, in more detail ---------- */

T.LOUVRE = () => {
  /* A belfry opening. Slats at forty-five degrees with the dark of the
     bell chamber between them, which is the one place in this town
     where a hole in a wall is supposed to read as black. */
  const p = new Pix(64, 64, 769);
  p.fill('grey', 0.05);
  for (let y = 2; y < 64; y += 6) {
    for (let x = 0; x < 64; x++) {
      p.ink(x, y, 'bone', 0.52); p.ink(x, y + 1, 'bone', 0.44);
      p.ink(x, y + 2, 'bone', 0.28); p.ink(x, y + 3, 'grey', 0.09);
    }
  }
  for (const x of [0, 1, 62, 63]) p.vline(x, 0, 63, 'bone', 0.60);      // the frame
  p.hline(0, 63, 0, 'bone', 0.64); p.hline(0, 63, 63, 'bone', 0.40);
  p.grime(0.16, 'grey', 0.05, 773);
  return p.snap(0.5);
};

T.CHURCHCL = () => {
  /* The underside of the nave roof, which in this church is the
     ceiling: tongue-and-groove boarding running up the slope, and a
     rafter every sixteen. Worn on the roof storey's ceiling, so what
     you are looking at from a pew is the back of the shingle. */
  const p = new Pix(64, 64, 787);
  const rng = makeRng(787);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.26 + rng() * 0.025 + Math.sin(x * 0.7) * 0.012);
  for (let x = 0; x < 64; x += 8) { p.vline(x, 0, 63, 'brown', 0.16); p.vline(x + 1, 0, 63, 'brown', 0.32); }
  for (const y of [6, 38]) {                                            // the rafters
    for (let k = 0; k < 6; k++) p.hline(0, 63, y + k, 'brown', 0.20 - k * 0.012);
    p.hline(0, 63, y - 1, 'brown', 0.36);
  }
  p.grime(0.18, 'grey', 0.05, 797);
  return p.snap(0.5);
};

T.TIEBEAM = () => {
  /* A tie beam across the nave, twenty-four deep: stained oak, adzed
     rather than sawn, with the shadow it throws on itself. */
  const p = new Pix(64, 24, 809);
  const rng = makeRng(809);
  for (let y = 0; y < 24; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.20 + rng() * 0.03 + Math.sin(x * 0.3 + y * 0.8) * 0.02);
  p.hline(0, 63, 0, 'brown', 0.36); p.hline(0, 63, 1, 'brown', 0.30);
  p.hline(0, 63, 22, 'brown', 0.10); p.hline(0, 63, 23, 'brown', 0.08);
  for (const x of [10, 53]) { p.box(x, 8, 4, 4, 'grey', 0.26); p.frame(x, 8, 4, 4, 'grey', 0.16); }   // the bolts
  return p.snap(0.5);
};

T.ORGANPIP = () => {
  /* The front of the organ in the choir loft, ninety-six tall: speaking
     pipes of polished tin in a case, tallest in the middle, with the
     mouths in a line across them. */
  const p = new Pix(64, 64, 811);
  p.fill('brown', 0.18);
  const tops = [18, 11, 6, 3, 6, 11, 18];
  for (let i = 0; i < 7; i++) {
    const x0 = 2 + i * 9, top = tops[i];
    for (let y = top; y < 61; y++)
      for (let k = 0; k < 7; k++) {
        const shade = 0.30 + Math.cos((k - 3) / 3.4) * 0.30;            // round, by shading across
        p.ink(x0 + k, y, 'grey', shade * (y < top + 2 ? 1.25 : 1));
      }
    for (let k = 0; k < 7; k++) p.ink(x0 + k, top, 'bone', 0.62);       // the lip of the pipe
    p.box(x0 + 1, 36, 5, 5, 'grey', 0.12);                              // the mouth
    p.hline(x0 + 1, x0 + 5, 36, 'bone', 0.50);
  }
  p.hline(0, 63, 61, 'brown', 0.30); p.hline(0, 63, 62, 'brown', 0.22);  // the impost
  p.hline(0, 63, 0, 'brown', 0.26);
  p.grime(0.16, 'grey', 0.05, 821);
  return p.snap(0.5);
};

T.RAILING = () => {
  /* ONE SECTION OF THE IRON ROUND A CEMETERY, and it is a photograph:
     scrollwork, a rosette at every crossing, spears along the top rail
     and a heavier standard at each end. It was drawn — eight uprights
     and two rails, which is a fence and is not THIS fence — and there
     is no set of primitives that gets you to wrought iron.

     MASKED, so what you see between the uprights is the graveyard.

     BAKED AT 64x64 AND DECLARED 96 TALL, which is the rule every
     texture in this file keeps and the reason there are no exceptions
     to it: the bakery paints at 64 and SIZES says how much wall one
     repeat covers. Here a repeat is one panel of iron, six feet up, and
     the panels butt at the standards. Baked by tools/bake-art.mjs out
     of art/stones/cemfence.png; no snap here, because every texel came
     out of the palette already. */
  return cutoutPix('cemfence');
};

/* ---------- THE STREET LAMP, which is a photograph in two tiles ----------

   A cobra-head road light on a tapered pole, cut out of its chroma key
   by tools/bake-art.mjs (bakeLamp there, and the argument for two tiles
   rather than one or eight). It is not a sprite and it is not on a
   line: js/mapgeo.js stands the two tiles up as quads in the plane
   across the street, at every STREETLAMP thing the town lays — see THE
   STREET LAMP IS GEOMETRY there — and js/lamplight.js hangs the light
   under the luminaire.

   BAKED AT 64 AND 24 ACROSS AND DECLARED AT THE LAMP'S OWN SIZE, which
   is the RAILING's rule and every tall texture's: the bakery paints
   small and SIZES says how much world one repeat covers. Here a repeat
   of the head is the whole head and a repeat of the post is the whole
   post, and STREET_LAMP below is where those sizes come from. */
T.LAMPHEAD = () => cutoutPix('lamp_head');
T.LAMPPOST = () => cutoutPix('lamp_post');

T.ALTARRL = () => {
  /* The communion rail, and the rail along the front of the choir loft:
     turned oak balusters under a handrail you kneel at, over the red of
     the chancel carpet behind them. Opaque for the reason GYMTRUSS is,
     and painted on the colour of what it stands in front of, which is
     the next best thing to seeing through it. */
  const p = new Pix(64, 32, 827);
  p.fill('red', 0.08);
  for (let x = 4; x < 64; x += 10) {
    for (let y = 8; y < 29; y++) {
      const w = 2 + (Math.sin((y - 8) * 0.45) > 0.4 ? 1 : 0);           // the turning
      for (let k = -w; k <= w; k++) p.ink(x + k, y, 'brown', 0.24 + (k < 0 ? 0.10 : 0), 255);
    }
  }
  for (let y = 0; y < 7; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.30 - y * 0.01, 255);
  p.hline(0, 63, 0, 'brown', 0.44, 255); p.hline(0, 63, 6, 'brown', 0.14, 255);
  for (let x = 0; x < 64; x++) { p.ink(x, 29, 'brown', 0.26, 255); p.ink(x, 30, 'brown', 0.18, 255); }
  return p.snap(0.3);
};

T.PULPITFR = () => {
  /* The front of the pulpit, forty-eight tall: linenfold panels in a
     frame, and the moulding that runs round the top of them. */
  const p = new Pix(64, 48, 829);
  const rng = makeRng(829);
  for (let y = 0; y < 48; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'brown', 0.21 + rng() * 0.025);
  p.hline(0, 63, 0, 'brown', 0.44); p.hline(0, 63, 1, 'brown', 0.36); p.hline(0, 63, 3, 'brown', 0.12);
  for (const px of [4, 36]) {
    p.box(px, 8, 24, 32, 'brown', 0.26);
    p.bevel(px, 8, 24, 32, 'brown', 0.40, 'brown', 0.10);
    for (let y = 12; y < 36; y += 4) { p.hline(px + 3, px + 20, y, 'brown', 0.34); p.hline(px + 3, px + 20, y + 1, 'brown', 0.14); }
  }
  p.hline(0, 63, 44, 'brown', 0.14); p.hline(0, 63, 45, 'brown', 0.10);
  return p.snap(0.5);
};

/* ---------- the school, in more detail ---------- */

T.SCHDOOR = () => {
  /* The front doors: a pair, eighty tall, steel painted the colour
     every school in the country painted them, with a push bar across
     each and wired glass over it. */
  const p = new Pix(64, 64, 839);
  p.fill('grey', 0.18);
  for (const dx of [0, 32]) {
    p.box(dx + 2, 2, 28, 60, 'red', 0.24);
    p.bevel(dx + 2, 2, 28, 60, 'red', 0.34, 'red', 0.12);
    p.box(dx + 5, 5, 22, 21, 'grey', 0.10);                             // the light
    for (let y = 6; y < 25; y += 4) p.hline(dx + 6, dx + 25, y, 'grey', 0.22);
    for (let x = dx + 6; x < dx + 27; x += 4) p.vline(x, 6, 24, 'grey', 0.22);
    p.frame(dx + 5, 5, 22, 21, 'grey', 0.30);
    p.box(dx + 4, 32, 24, 3, 'grey', 0.42);                             // the push bar
    p.hline(dx + 4, dx + 27, 32, 'grey', 0.54);
    p.box(dx + 6, 35, 3, 3, 'grey', 0.30); p.box(dx + 23, 35, 3, 3, 'grey', 0.30);
  }
  p.vline(31, 0, 63, 'grey', 0.28); p.vline(32, 0, 63, 'grey', 0.12);   // the meeting stile
  p.grime(0.26, 'grey', 0.07, 853);
  return p.snap(0.5);
};

T.GYMFLOOR = () => {
  /* Maple, laid across, with the paint of a court on it: the sideline,
     the key's edge, and the centre circle's arc, none of which land in
     the same place twice because one repeat is sixty-four units and a
     court is not. What it has to do is read as PAINTED WOOD from the
     door, and it does. */
  const p = new Pix(64, 64, 857);
  const rng = makeRng(857);
  for (let b = 0; b < 8; b++) {
    const y0 = b * 8, t = 0.34 + rng() * 0.05;
    for (let y = y0; y < y0 + 8; y++) for (let x = 0; x < 64; x++)
      p.ink(x, y, 'yellow', t * 0.62 + Math.sin((x * 0.4 + b * 5) * 0.6) * 0.02 + (y === y0 ? -0.06 : 0));
  }
  for (let x = 0; x < 64; x++) { p.ink(x, 20, 'bone', 0.50); p.ink(x, 21, 'bone', 0.50); }   // a line
  for (let y = 0; y < 64; y++) { p.ink(44, y, 'red', 0.36); p.ink(45, y, 'red', 0.36); }     // and one the other way
  p.grime(0.20, 'grey', 0.05, 859);
  return p.snap(0.5);
};

T.GYMPAD = () => {
  /* The padding round the bottom of a gym wall, in the school's own
     colour, quilted in panels with a steel strip between them. */
  const p = new Pix(64, 64, 863);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'blue', 0.20 + Math.sin(y * 0.2) * 0.01);
  for (const x of [0, 32]) {
    p.box(x + 2, 3, 28, 58, 'blue', 0.26);
    p.bevel(x + 2, 3, 28, 58, 'blue', 0.34, 'blue', 0.12);
  }
  p.vline(31, 0, 63, 'grey', 0.24); p.vline(63, 0, 63, 'grey', 0.24);
  p.hline(0, 63, 0, 'grey', 0.28); p.hline(0, 63, 62, 'grey', 0.14); p.hline(0, 63, 63, 'grey', 0.10);
  p.grime(0.22, 'grey', 0.06, 877);
  return p.snap(0.5);
};

T.BLEACHER = () => {
  /* The riser of a bleacher, twenty-four tall: the plank you put your
     feet on, the steel frame under it and the dark of the space
     between, which is where everything anybody ever dropped is. */
  const p = new Pix(64, 24, 881);
  for (let y = 0; y < 24; y++) for (let x = 0; x < 64; x++) p.ink(x, y, 'grey', 0.07);
  for (let y = 0; y < 8; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'yellow', 0.24 + Math.sin(x * 0.5) * 0.02 - y * 0.008);
  p.hline(0, 63, 0, 'yellow', 0.34); p.hline(0, 63, 7, 'grey', 0.10);
  for (let x = 4; x < 64; x += 24) { p.box(x, 8, 4, 16, 'grey', 0.26); p.vline(x, 8, 23, 'grey', 0.34); }
  p.grime(0.30, 'grey', 0.07, 883);
  return p.snap(0.5);
};

T.HANDRAIL = () => {
  /* A steel pipe handrail: a top rail, a knee rail and a standard every
     thirty-two, on the dark of the stairwell. Every stair in the school
     wears it down its open side, which is the difference between a
     flight of stairs and a stack of floating slabs. Opaque for the
     reason GYMTRUSS is. */
  const p = new Pix(64, 32, 887);
  p.fill('grey', 0.10);
  for (const y of [1, 2, 3, 15, 16]) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', y === 1 ? 0.52 : y === 2 ? 0.42 : 0.24, 255);
  for (const x of [6, 38]) for (let y = 1; y < 32; y++) {
    p.ink(x, y, 'grey', 0.44, 255); p.ink(x + 1, y, 'grey', 0.34, 255); p.ink(x + 2, y, 'grey', 0.18, 255);
  }
  return p.snap(0.3);
};

T.GYMTRUSS = () => {
  /* A roof truss over the gym: a bottom chord, a top chord and the
     diagonals between them, painted the grey that everything above a
     gym floor is painted, on the dark of the roof space.

     OPAQUE, AND THAT IS NOT A COMPROMISE. It was masked, and what you
     saw through the web was the SKY — because a masked texture only
     works where there is something behind it, and a BAND has nothing
     behind it by construction: a band is the one quad the disagreement
     rule draws where two columns differ, and the differing is exactly
     the part of the world with no geometry in it. Masked belongs on a
     MIDDLE texture, in the hole between two open sectors, which is what
     the fences use. Everything that is a band paints its own dark. */
  const p = new Pix(64, 32, 907);
  p.fill('grey', 0.05);
  for (const y of [0, 1, 29, 30, 31]) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'grey', y < 2 ? 0.30 : 0.22, 255);
  for (let i = 0; i < 64; i += 16) {
    for (let k = 0; k < 16; k++) {
      p.ink(i + k, 2 + k * 1.7 | 0, 'grey', 0.26, 255);
      p.ink(i + k + 1, 2 + k * 1.7 | 0, 'grey', 0.18, 255);
      p.ink(i + 15 - k, 2 + k * 1.7 | 0, 'grey', 0.26, 255);
      p.ink(i + 16 - k, 2 + k * 1.7 | 0, 'grey', 0.18, 255);
    }
    for (let y = 0; y < 32; y++) { p.ink(i, y, 'grey', 0.28, 255); p.ink(i + 1, y, 'grey', 0.18, 255); }
  }
  return p.snap(0.3);
};

T.DATESTON = () => {
  /* The stone over the front door. Every school built in this decade
     has one and there is no name on it, ever — the same rule the
     shopfronts keep. What is carved is a panel and a pair of rosettes,
     and the eye supplies a year. */
  const p = new Pix(64, 32, 911);
  aggregate(p, 911, { baseKey: 'bone', baseLo: 0.38, baseHi: 0.46,
    grades: [{ count: 120, min: 0.3, max: 0.8, key: 'grey', lo: 0.32, hi: 0.46 }] });
  p.frame(3, 3, 58, 26, 'grey', 0.26);
  p.frame(4, 4, 56, 24, 'bone', 0.58);
  p.box(10, 9, 44, 14, 'bone', 0.34);
  p.bevel(10, 9, 44, 14, 'grey', 0.24, 'bone', 0.56);
  for (const cx of [7, 56]) { p.disc(cx, 16, 2, 'grey', 0.26); p.disc(cx, 16, 1, 'bone', 0.52); }
  p.hline(0, 63, 0, 'bone', 0.62); p.hline(0, 63, 31, 'grey', 0.18);
  p.grime(0.24, 'grey', 0.06, 919);
  return p.snap(0.5);
};

/* ====================================================================
   THE OFFICE BUILDING

   A speculative suburban office block, which is a kind of building this
   town did not have and the one kind every American town of this size
   has two of: four storeys of precast panel and ribbon glazing standing
   in its own parking lot, with a lobby you can walk into and three
   floors over it that you cannot.

   ITS ELEVATION IS THREE TEXTURES AND A RHYTHM. A base course of
   polished granite, a spandrel panel between the windows, a pier
   between the bays, and a parapet on top hiding a flat roof — and
   because every one of those is a BAND rather than a tiled wall, each
   is drawn at the height of the piece of geometry it skins and never at
   a height and a half. See THE TRIM above; this is the same argument
   with a different accent.
   ==================================================================== */

T.OFFPANEL = () => {
  /* PRECAST CONCRETE, which is not the same grey as poured concrete and
     is the whole reason this is its own texture: a panel is cast face
     down in a mould against sand, so it comes out with an even exposed
     aggregate and a HARD EDGE at every joint, where a poured wall comes
     out streaked and soft. What says precast is the joint: a shadow
     line four units wide with a bead of sealant in it, running down
     every panel and along every floor line. */
  const p = new Pix(64, 64, 940);
  aggregate(p, 940, { baseKey: 'grey', baseLo: 0.29, baseHi: 0.34,
    grades: [{ count: 180, min: 0.4, max: 1.0, key: 'bone', lo: 0.30, hi: 0.36 },
             { count: 120, min: 0.4, max: 0.9, key: 'grey', lo: 0.23, hi: 0.28 }] });
  /* the joints: two across and two down, so one repeat is four panels */
  for (const x of [0, 32]) {
    p.vline(x, 0, 63, 'grey', 0.14);
    p.vline(x + 1, 0, 63, 'grey', 0.22);
    p.vline(x + 2, 0, 63, 'bone', 0.40);
  }
  for (const y of [0, 32]) {
    p.hline(0, 63, y, 'grey', 0.15);
    p.hline(0, 63, y + 1, 'grey', 0.23);
    p.hline(0, 63, y + 2, 'bone', 0.42);
  }
  /* AND THE WEATHERING, which on a panel runs from the joint and not
     from nowhere: water gets behind the sealant and comes out under it. */
  streaks(p, 14, 941, 'grey', 0.20, 0.30);
  p.grime(0.22, 'grey', 0.05, 942);
  return p.snap(0.45);
};

T.OFFBASE = () => {
  /* The base course: polished granite, which is what the bottom two
     feet of an office is because that is the part people kick. Flamed
     at the top edge where it meets the panel and polished below, with
     the joints between slabs falling on the panel joints. */
  const p = new Pix(64, 32, 943);
  aggregate(p, 943, { baseKey: 'grey', baseLo: 0.10, baseHi: 0.14,
    grades: [{ count: 220, min: 0.4, max: 0.9, key: 'bone', lo: 0.16, hi: 0.24 },
             { count: 110, min: 0.4, max: 0.8, key: 'purple', lo: 0.09, hi: 0.13 }] });
  /* the polish: one long raked highlight, which is all a polished stone
     is in a picture this size */
  for (let y = 0; y < 32; y++) for (let x = 0; x < 64; x++)
    if ((x * 2 + y * 5) % 47 < 2) p.wash(x, y, 'bone', 0.52, 0.14);
  for (const x of [0, 32]) { p.vline(x, 0, 31, 'grey', 0.06); p.vline(x + 1, 0, 31, 'bone', 0.26); }
  p.hline(0, 63, 0, 'bone', 0.44);          // the flamed top arris
  p.hline(0, 63, 1, 'grey', 0.22);
  p.hline(0, 63, 31, 'grey', 0.05);         // and the shadow at the pavement
  p.grime(0.30, 'grey', 0.05, 944);
  return p.snap(0.4);
};

T.OFFPARA = () => {
  /* THE PARAPET, and one repeat is the whole of it: the cornice bead it
     springs off, the panel, and the metal coping capping it. Forty
     units, which is what the band between the eaves and the top of the
     wall is tall in the map — so the coping lands on the coping and
     never a third of the way down a second one. */
  const p = new Pix(64, 40, 945);
  aggregate(p, 945, { baseKey: 'grey', baseLo: 0.29, baseHi: 0.34,
    grades: [{ count: 140, min: 0.4, max: 1.0, key: 'bone', lo: 0.30, hi: 0.36 }] });
  /* the cornice bead at the bottom, standing out of the wall below */
  p.box(0, 34, 64, 6, 'grey', 0.22);
  p.hline(0, 63, 34, 'bone', 0.50);
  p.hline(0, 63, 39, 'grey', 0.10);
  /* the coping: an aluminium cap with a drip and a joint every panel */
  p.box(0, 0, 64, 7, 'grey', 0.44);
  p.hline(0, 63, 0, 'bone', 0.72);
  p.hline(0, 63, 6, 'grey', 0.14);
  p.hline(0, 63, 7, 'grey', 0.20);
  for (const x of [0, 32]) { p.vline(x, 0, 6, 'grey', 0.26); p.vline(x + 1, 0, 6, 'bone', 0.58); }
  /* and the panel between, with its own joints carried up */
  for (const x of [0, 32]) {
    p.vline(x, 8, 33, 'grey', 0.16);
    p.vline(x + 2, 8, 33, 'bone', 0.40);
  }
  streaks(p, 8, 946, 'grey', 0.18, 0.28);
  p.grime(0.20, 'grey', 0.05, 947);
  return p.snap(0.45);
};

T.OFFMULL = () => {
  /* THE PIER between two bays of glazing: a panel thirty-two wide with
     a ribbed aluminium cover on the face of it, which is the one piece
     of an office of this age that is not concrete. One repeat is the
     pier's width, so the ribs land where ribs go. */
  const p = new Pix(32, 64, 948);
  aggregate(p, 948, { baseKey: 'grey', baseLo: 0.28, baseHi: 0.32,
    grades: [{ count: 70, min: 0.4, max: 0.9, key: 'bone', lo: 0.29, hi: 0.34 }] });
  /* the cover, inset four each side */
  p.box(4, 0, 24, 64, 'grey', 0.38);
  for (let x = 5; x < 28; x += 4) {
    p.vline(x, 0, 63, 'bone', 0.56);
    p.vline(x + 1, 0, 63, 'grey', 0.24);
  }
  p.vline(3, 0, 63, 'grey', 0.12);          // the shadow down each side
  p.vline(28, 0, 63, 'grey', 0.12);
  p.vline(29, 0, 63, 'bone', 0.34);
  /* the floor line, where the cover is joined */
  for (const y of [0, 1]) p.hline(4, 27, y, 'grey', y ? 0.44 : 0.18);
  p.grime(0.22, 'grey', 0.05, 949);
  return p.snap(0.4);
};

/* --------------------------------------------------------------------
   THE GLAZING. Two pictures, lit and dark, and they are the same window
   with the lights on and off — which is how a block of offices reads at
   night from four streets away and the only thing that makes one look
   occupied. One repeat is ONE BAY: 128 across by 72 up, the size of the
   hole in the map, so a bay is never a bay and a quarter.
   ------------------------------------------------------------------ */
const officeGlass = (seed, lit) => {
  const p = new Pix(64, 36, seed);
  /* the glass: bronze tinted, which is what every one of these was
     glazed with, darker at the top where it looks at the sky */
  for (let y = 0; y < 36; y++) {
    const t = lit ? 0.46 + (1 - y / 36) * 0.10 : 0.10 + (y / 36) * 0.05;
    for (let x = 0; x < 64; x++) p.ink(x, y, lit ? 'yellow' : 'brown', t);
  }
  const rng = makeRng(seed + 1);
  if (lit) {
    /* what is on inside: the ceiling grid glowing across the top third,
       the top of a partition, and a desk lamp or two */
    for (let x = 0; x < 64; x += 8) p.box(x + 1, 3, 6, 3, 'bone', 0.86);
    p.hline(0, 63, 8, 'yellow', 0.62);
    for (let i = 0; i < 4; i++) {
      const x = 4 + Math.floor(rng() * 54);
      p.box(x, 16 + Math.floor(rng() * 8), 8 + Math.floor(rng() * 8), 14, 'grey', 0.30);
    }
    p.box(6, 24, 5, 4, 'bone', 0.92);
    p.box(44, 22, 4, 3, 'cyan', 0.70);
  } else {
    /* and what is on the OUTSIDE of a dark one, which is the sky: a
       band of cloud raked across it, and the building over the road */
    for (let y = 0; y < 14; y++) for (let x = 0; x < 64; x++)
      if ((x + y * 3) % 29 < 4) p.wash(x, y, 'bone', 0.36, 0.16);
    p.box(0, 20, 64, 16, 'brown', 0.07);
  }
  /* THE BLINDS, half down on some bays and not on others, which is the
     detail that stops sixty windows being one window sixty times. */
  const drop = Math.floor(rng() * 5);
  if (drop) {
    const h = 6 + drop * 5;
    p.box(0, 0, 64, h, 'bone', lit ? 0.52 : 0.24);
    for (let y = 1; y < h; y += 2) p.hline(0, 63, y, 'grey', lit ? 0.40 : 0.14);
    p.hline(0, 63, h, 'grey', 0.10);
  }
  /* the frame: a head, a sill and the two jambs, and one vertical
     mullion in the middle because a bay this wide is two lights */
  p.hline(0, 63, 0, 'grey', 0.40); p.hline(0, 63, 1, 'grey', 0.22);
  p.hline(0, 63, 34, 'grey', 0.20); p.hline(0, 63, 35, 'grey', 0.46);
  for (const x of [0, 31, 32, 63]) p.vline(x, 0, 35, 'grey', x === 31 ? 0.20 : 0.36);
  /* and the reflection of the sun off the pane, which is what makes it
     read as glass at all */
  for (let y = 2; y < 34; y++) for (let x = 0; x < 64; x++)
    if ((x * 3 + y * 7) % 61 < 3) p.wash(x, y, 'bone', lit ? 0.80 : 0.52, 0.12);
  return p.snap(0.35);
};
T.OFFWINLT = () => officeGlass(950, true);
T.OFFWINDK = () => officeGlass(952, false);

T.OFFDOOR = () => {
  /* One leaf of the entrance: an aluminium stile-and-rail door with a
     full glass light, a push bar across it and a kick plate. */
  const p = new Pix(48, 64, 954);
  p.fill('grey', 0.34);
  p.box(4, 3, 40, 52, 'brown', 0.12);        // the light
  for (let y = 3; y < 55; y++) for (let x = 4; x < 44; x++)
    if ((x * 2 + y * 5) % 43 < 3) p.wash(x, y, 'bone', 0.58, 0.16);
  p.frame(3, 2, 42, 54, 'grey', 0.50);
  p.frame(4, 3, 40, 52, 'grey', 0.22);
  p.box(2, 55, 44, 7, 'grey', 0.46);         // the bottom rail
  p.hline(2, 45, 55, 'bone', 0.66);
  p.box(4, 57, 40, 4, 'bone', 0.40);         // the kick plate
  p.box(6, 30, 36, 3, 'grey', 0.58);         // the push bar
  p.hline(6, 41, 30, 'bone', 0.80);
  for (const x of [8, 39]) p.box(x, 28, 2, 7, 'grey', 0.42);
  p.vline(0, 0, 63, 'grey', 0.18); p.vline(47, 0, 63, 'grey', 0.18);
  p.grime(0.22, 'grey', 0.06, 955);
  return p.snap(0.4);
};

T.OFFSIGN = () => {
  /* The band over the doors. NO NAME, which is the rule every sign in
     this game keeps — what is on it is the street number, in cut
     aluminium letters with a shadow under each, and the eye supplies
     the rest. */
  const p = new Pix(64, 16, 956);
  aggregate(p, 956, { baseKey: 'grey', baseLo: 0.16, baseHi: 0.21,
    grades: [{ count: 90, min: 0.4, max: 1.0, key: 'bone', lo: 0.14, hi: 0.22 }] });
  p.hline(0, 63, 0, 'bone', 0.40); p.hline(0, 63, 15, 'grey', 0.07);
  drawTextCentred(p, '100', 32, 6, 'grey', 0.10, 2);       // the shadow
  drawTextCentred(p, '100', 31, 5, 'bone', 0.80, 2);
  p.grime(0.20, 'grey', 0.05, 957);
  return p.snap(0.4);
};

T.ROOFBALL = () => {
  /* THE FLAT ROOF you see from anything higher than it: built-up
     membrane with a ballast of river gravel over it, the seams showing
     where the rock has washed off, and the puddle that never dries in
     the middle of the bay. The first flat roof in this game that is a
     FLOOR rather than a picture of one. */
  const p = new Pix(64, 64, 958);
  aggregate(p, 958, { baseKey: 'grey', baseLo: 0.14, baseHi: 0.20,
    grades: [{ count: 900, min: 0.5, max: 1.6, key: 'bone', lo: 0.16, hi: 0.30 },
             { count: 500, min: 0.5, max: 1.4, key: 'brown', lo: 0.12, hi: 0.22 }] });
  /* the seams, which are where the ballast is thin */
  for (const y of [12, 44]) for (let x = 0; x < 64; x++) {
    p.wash(x, y, 'grey', 0.09, 0.55); p.wash(x, y + 1, 'grey', 0.22, 0.35);
  }
  for (const x of [28]) for (let y = 0; y < 64; y++) {
    p.wash(x, y, 'grey', 0.09, 0.55); p.wash(x + 1, y, 'grey', 0.22, 0.35);
  }
  /* and the pond */
  for (let y = 18; y < 39; y++) for (let x = 34; x < 55; x++) {
    const d = Math.hypot(x - 44, y - 28);
    if (d < 9.5) p.wash(x, y, 'blue', 0.12, d < 6 ? 0.55 : 0.30);
  }
  p.grime(0.30, 'brown', 0.06, 959);
  return p.snap(0.45);
};

/* --------------------------------------------------------------------
   INSIDE: what a ground floor is made of
   ------------------------------------------------------------------ */

T.TERRAZZO = () => {
  /* The lobby floor: poured terrazzo with brass divider strips on a
     four-foot grid, which is what the floor of every building with a
     reception desk in it was until carpet tile. The chips are the whole
     picture — three sizes of them, and they must not line up. */
  const p = new Pix(64, 64, 960);
  aggregate(p, 960, { baseKey: 'bone', baseLo: 0.26, baseHi: 0.32,
    grades: [{ count: 700, min: 0.6, max: 2.0, key: 'bone', lo: 0.40, hi: 0.62 },
             { count: 380, min: 0.5, max: 1.6, key: 'grey', lo: 0.12, hi: 0.22 },
             { count: 150, min: 0.5, max: 1.4, key: 'brown', lo: 0.18, hi: 0.30 }] });
  for (const a of [0, 32]) {
    p.hline(0, 63, a, 'yellow', 0.52); p.hline(0, 63, a + 1, 'brown', 0.22);
    p.vline(a, 0, 63, 'yellow', 0.52); p.vline(a + 1, 0, 63, 'brown', 0.22);
  }
  /* AND THE SHINE, raked the other way from the grid so the two do not
     agree — a polished floor with its highlight along a joint is a
     photograph of a joint. */
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    if ((x * 3 + y * 8) % 71 < 4) p.wash(x, y, 'bone', 0.70, 0.13);
  return p.snap(0.45);
};

T.OFFCARP = () => {
  /* Carpet tile: a grey-blue loop pile laid quarter-turned, so the
     seams show as a change of direction and not as a line. Every office
     floor in the country, and the flecks are what stop it being a
     rectangle of one colour. */
  const p = new Pix(64, 64, 962);
  const n = fbm(64, 64, 24, 3, 962);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
    const quarter = (x < 32) === (y < 32);
    const g = n[y * 64 + x];
    p.ink(x, y, 'grey', 0.25 + g * 0.06 + (quarter ? 0.014 : 0));
    p.wash(x, y, 'blue', 0.30, 0.26);
  }
  speckle(64, 64, 700, 963, (x, y, a, b) =>
    p.wash(x, y, a < 0.45 ? 'grey' : a < 0.8 ? 'bone' : 'olive', 0.16 + b * 0.18, 0.22 + b * 0.25));
  /* the loop, which runs with the pile: short dashes, turned per tile */
  const rng = makeRng(964);
  for (let i = 0; i < 700; i++) {
    const x = Math.floor(rng() * 64), y = Math.floor(rng() * 64);
    const quarter = (x < 32) === (y < 32);
    p.wash(x, y, 'bone', 0.30, 0.13);
    if (quarter) p.wash(x + 1, y, 'grey', 0.10, 0.13);
    else p.wash(x, y + 1, 'grey', 0.10, 0.13);
  }
  for (const a of [0, 32]) for (let k = 0; k < 64; k++) {
    p.wash(k, a, 'grey', 0.08, 0.35); p.wash(a, k, 'grey', 0.08, 0.35);
  }
  p.grime(0.26, 'grey', 0.05, 965);
  return p.snap(0.4);
};

T.RECEPDSK = () => {
  /* The front of the reception desk: an oak-veneer body with a reveal
     at the floor so it reads as standing on the terrazzo rather than
     growing out of it, and a stone transaction ledge over the top. */
  const p = new Pix(64, 40, 966);
  const n = fbm(64, 40, 6, 3, 966);
  for (let y = 0; y < 40; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.22 + n[y * 64 + x] * 0.08);
  for (let i = 0; i < 26; i++) {                 // the grain
    const y = Math.floor((i * 40) / 26);
    p.hline(0, 63, y, 'brown', 0.15 + (i % 3) * 0.04);
  }
  /* the ledge across the top */
  p.box(0, 0, 64, 5, 'grey', 0.30);
  p.hline(0, 63, 0, 'bone', 0.60);
  p.hline(0, 63, 4, 'grey', 0.12);
  speckle(64, 5, 90, 967, (x, y, a, b) => p.wash(x, y, a < 0.5 ? 'bone' : 'grey', 0.20 + b * 0.3, 0.4));
  /* the panel joints down the face, and the reveal at the bottom */
  for (const x of [16, 32, 48]) { p.vline(x, 6, 34, 'brown', 0.12); p.vline(x + 1, 6, 34, 'brown', 0.34); }
  p.box(0, 35, 64, 5, 'grey', 0.07);
  p.hline(0, 63, 35, 'brown', 0.10);
  p.grime(0.22, 'grey', 0.05, 968);
  return p.snap(0.4);
};

T.RECEPTOP = () => {
  /* Looking down on the desk: the stone top, and what is on it. A
     telephone with a cord, a log book left open, a cup of pens and the
     ring where a mug has been since Tuesday. */
  const p = new Pix(64, 48, 969);
  aggregate(p, 969, { baseKey: 'grey', baseLo: 0.26, baseHi: 0.33,
    grades: [{ count: 260, min: 0.5, max: 1.5, key: 'bone', lo: 0.30, hi: 0.46 },
             { count: 120, min: 0.5, max: 1.2, key: 'brown', lo: 0.16, hi: 0.26 }] });
  p.box(6, 6, 16, 11, 'grey', 0.10);           // the telephone
  p.box(7, 7, 14, 7, 'grey', 0.20);
  for (let y = 8; y < 13; y += 2) p.hline(8, 19, y, 'grey', 0.34);
  p.box(8, 15, 12, 2, 'grey', 0.30);
  for (let i = 0; i < 9; i++) p.ink(22 + i, 12 + (i % 3), 'grey', 0.14);  // the cord
  p.box(30, 20, 22, 16, 'bone', 0.62);         // the log book
  p.vline(41, 20, 35, 'grey', 0.26);
  for (let y = 23; y < 34; y += 3) { p.hline(32, 39, y, 'grey', 0.26); p.hline(43, 50, y, 'grey', 0.26); }
  p.disc(12, 34, 4, 'grey', 0.16);             // the pen cup
  p.disc(12, 34, 3, 'grey', 0.08);
  for (const d of [-1, 0, 2]) p.vline(12 + d, 28, 33, d ? 'blue' : 'red', 0.36);
  p.disc(54, 10, 5, 'brown', 0.20);            // and the ring
  p.disc(54, 10, 3, 'grey', 0.30);
  p.grime(0.24, 'grey', 0.05, 970);
  return p.snap(0.4);
};

T.LIFTDOOR = () => {
  /* A pair of lift doors: brushed stainless, centre-opening, with the
     call station beside them and the floor indicator over. They do not
     open — there is nowhere to go, the stairs having been deleted — and
     a lift that never comes is the most office thing in the building. */
  const p = new Pix(64, 48, 971);
  p.fill('grey', 0.30);
  for (let y = 0; y < 48; y++) for (let x = 0; x < 64; x++)
    if ((x * 7 + y) % 3 === 0) p.wash(x, y, 'bone', 0.44, 0.18);
  /* the frame */
  p.box(0, 0, 4, 48, 'grey', 0.40); p.box(60, 0, 4, 48, 'grey', 0.40);
  p.box(0, 0, 64, 4, 'grey', 0.44);
  p.vline(3, 0, 47, 'grey', 0.14); p.vline(60, 0, 47, 'grey', 0.14);
  p.hline(0, 63, 0, 'bone', 0.66); p.hline(0, 63, 3, 'grey', 0.14);
  /* the two leaves and the joint between them */
  p.vline(31, 4, 47, 'grey', 0.12); p.vline(32, 4, 47, 'bone', 0.50);
  for (const x of [10, 20, 43, 53]) for (let y = 5; y < 47; y++) p.wash(x, y, 'bone', 0.38, 0.45);
  /* the indicator over the door, and the call button beside it */
  p.box(24, 5, 16, 6, 'grey', 0.10);
  p.box(26, 6, 3, 4, 'yellow', 0.72); p.box(31, 6, 3, 4, 'grey', 0.22); p.box(36, 6, 3, 4, 'grey', 0.22);
  p.box(56, 20, 6, 10, 'grey', 0.22);
  p.disc(59, 23, 1, 'bone', 0.60); p.disc(59, 27, 1, 'grey', 0.14);
  p.grime(0.26, 'grey', 0.05, 972);
  return p.snap(0.4);
};

T.CUBEPANL = () => {
  /* A CUBICLE PARTITION, which is the single object that says office
     more than any other: a fabric-covered panel on a steel frame, a
     rail across the top you hang a shelf off, and a raceway along the
     bottom with the power in it. One repeat is the panel's height. */
  const p = new Pix(64, 44, 973);
  const n = fbm(64, 44, 20, 3, 973);
  for (let y = 0; y < 44; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'olive', 0.18 + n[y * 64 + x] * 0.06);
  /* the weave, which is a cross-hatch one pixel on and one off */
  for (let y = 0; y < 44; y++) for (let x = 0; x < 64; x++)
    if (((x + y) & 1) === 0) p.wash(x, y, 'bone', 0.26, 0.14);
    else if (((x - y) & 3) === 0) p.wash(x, y, 'grey', 0.10, 0.12);
  /* the top rail */
  p.box(0, 0, 64, 4, 'grey', 0.34);
  p.hline(0, 63, 0, 'bone', 0.62); p.hline(0, 63, 3, 'grey', 0.12);
  /* the raceway */
  p.box(0, 38, 64, 6, 'grey', 0.26);
  p.hline(0, 63, 38, 'grey', 0.12); p.hline(0, 63, 39, 'bone', 0.44);
  for (const x of [14, 46]) { p.box(x, 40, 5, 3, 'bone', 0.40); p.vline(x + 2, 40, 42, 'grey', 0.10); }
  /* the joint between panels, every two feet */
  for (const x of [0, 32]) { p.vline(x, 4, 37, 'grey', 0.12); p.vline(x + 1, 4, 37, 'bone', 0.30); }
  p.grime(0.24, 'grey', 0.05, 974);
  return p.snap(0.4);
};

T.CUBEDESK = () => {
  /* The work surface seen from over it: laminate, a monitor and its
     keyboard, a phone, a mug, and the drift of paper that is the
     difference between a desk and a table. */
  const p = new Pix(56, 56, 975);
  const n = fbm(56, 56, 7, 3, 975);
  for (let y = 0; y < 56; y++) for (let x = 0; x < 56; x++)
    p.ink(x, y, 'bone', 0.22 + n[y * 56 + x] * 0.05);
  speckle(56, 56, 300, 976, (x, y, a, b) => p.wash(x, y, a < 0.5 ? 'grey' : 'brown', 0.14 + b * 0.16, 0.3));
  /* the monitor, at the back, looked down on: the top of the case and a
     sliver of the screen */
  p.box(14, 2, 28, 14, 'bone', 0.34);
  p.bevel(14, 2, 28, 14, 'bone', 0.50, 'grey', 0.14);
  p.box(17, 4, 22, 7, 'grey', 0.08);
  for (let y = 5; y < 10; y += 2) p.hline(19, 36, y, 'cyan', 0.42);
  /* the keyboard */
  p.box(13, 22, 30, 12, 'bone', 0.30);
  p.bevel(13, 22, 30, 12, 'bone', 0.44, 'grey', 0.16);
  for (let y = 24; y < 32; y += 2) for (let x = 15; x < 41; x += 3) p.box(x, y, 2, 1, 'grey', 0.18);
  /* the mouse, the mug and the phone */
  p.disc(48, 27, 3, 'bone', 0.32); p.disc(48, 26, 2, 'bone', 0.44);
  p.disc(7, 10, 4, 'red', 0.30); p.disc(7, 10, 3, 'brown', 0.14);
  p.box(2, 36, 13, 9, 'grey', 0.16); p.box(3, 37, 11, 5, 'grey', 0.26);
  /* and the paper */
  const rng = makeRng(977);
  for (let i = 0; i < 5; i++) {
    const x = 18 + Math.floor(rng() * 28), y = 36 + Math.floor(rng() * 12);
    p.box(x, y, 12, 9, 'bone', 0.56);
    p.frame(x, y, 12, 9, 'grey', 0.26);
    for (let k = 2; k < 8; k += 2) p.hline(x + 2, x + 9, y + k, 'grey', 0.30);
  }
  return p.snap(0.4);
};

T.FILECAB = () => {
  /* A four-drawer filing cabinet: the drawer faces, the pulls, and the
     label holder on each that nobody has ever filled in. */
  const p = new Pix(32, 48, 978);
  p.fill('grey', 0.26);
  for (let k = 0; k < 4; k++) {
    const y = 1 + k * 12;
    p.box(1, y, 30, 11, 'grey', 0.31);
    p.bevel(1, y, 30, 11, 'bone', 0.46, 'grey', 0.14);
    p.box(11, y + 7, 10, 2, 'grey', 0.44);      // the pull
    p.hline(11, 20, y + 7, 'bone', 0.66);
    p.box(3, y + 3, 7, 3, 'bone', 0.52);        // the label holder
    p.frame(3, y + 3, 7, 3, 'grey', 0.18);
  }
  p.vline(0, 0, 47, 'grey', 0.16); p.vline(31, 0, 47, 'grey', 0.16);
  p.hline(0, 31, 0, 'bone', 0.44); p.hline(0, 31, 47, 'grey', 0.10);
  p.grime(0.26, 'grey', 0.05, 979);
  return p.snap(0.4);
};

T.CONFTBL = () => {
  /* The board table from above: dark veneer with the grain running its
     length, a power grommet down the middle, blotters, water glasses
     and the jug. Nobody has been in this room for a week. */
  const p = new Pix(64, 64, 980);
  const n = fbm(64, 64, 5, 3, 980);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'brown', 0.12 + n[y * 64 + x] * 0.06);
  for (let i = 0; i < 40; i++) {                 // the grain, along
    const y = Math.floor(i * 64 / 40);
    p.hline(0, 63, y, 'brown', 0.09 + (i % 4) * 0.03);
  }
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    if ((x * 3 + y * 9) % 67 < 3) p.wash(x, y, 'bone', 0.60, 0.11);
  /* the grommet */
  p.disc(32, 32, 5, 'grey', 0.10); p.disc(32, 32, 4, 'grey', 0.22);
  p.hline(28, 35, 32, 'grey', 0.08);
  /* blotters down each side, a glass on each, and the jug */
  for (const y of [8, 44]) for (const x of [6, 38]) {
    p.box(x, y, 20, 12, 'green', 0.16);
    p.frame(x, y, 20, 12, 'brown', 0.26);
    p.disc(x + 17, y + 14, 2, 'bone', 0.52);
  }
  p.disc(32, 20, 4, 'bone', 0.46); p.disc(32, 20, 3, 'cyan', 0.34);
  p.grime(0.22, 'grey', 0.05, 981);
  return p.snap(0.4);
};

T.WHITEBRD = () => {
  /* A whiteboard with the last meeting still on it: a box, an arrow, a
     column of figures, and the grey ghost of everything written on it
     before that which will not come off. */
  const p = new Pix(64, 40, 982);
  p.fill('bone', 0.72);
  const rng = makeRng(983);
  for (let i = 0; i < 90; i++) {               // the ghosting
    const x = Math.floor(rng() * 60), y = Math.floor(rng() * 34);
    for (let k = 0, w = 2 + Math.floor(rng() * 8); k < w; k++) p.wash(x + k, y, 'grey', 0.54, 0.35);
  }
  p.frame(8, 7, 18, 11, 'blue', 0.30);         // the box
  p.frame(9, 8, 16, 9, 'blue', 0.24);
  p.line(26, 13, 40, 13, 'red', 0.36);         // the arrow
  p.line(37, 10, 40, 13, 'red', 0.36);
  p.line(37, 16, 40, 13, 'red', 0.36);
  for (let k = 0; k < 4; k++) p.hline(44, 44 + 4 + Math.floor(rng() * 8), 8 + k * 4, 'grey', 0.26);
  p.line(6, 26, 56, 26, 'green', 0.30);
  p.frame(0, 0, 64, 40, 'grey', 0.40);         // the tray and the frame
  p.box(0, 35, 64, 5, 'grey', 0.38);
  p.hline(0, 63, 35, 'bone', 0.66); p.hline(0, 63, 39, 'grey', 0.12);
  for (const [x, k] of [[8, 'red'], [14, 'blue'], [20, 'green']]) p.box(x, 36, 4, 2, k, 0.40);
  return p.snap(0.4);
};

T.VENDING = () => {
  /* A vending machine, lit from inside, which in a break room at two in
     the morning is the brightest thing in the building. Six shelves of
     product behind the glass, a keypad, and the coin return. */
  const p = new Pix(44, 64, 984);
  p.fill('grey', 0.20);
  p.box(1, 1, 30, 50, 'grey', 0.06);           // the window
  const rng = makeRng(985);
  const KEYS = ['red', 'yellow', 'blue', 'green', 'olive', 'rust', 'purple', 'cyan'];
  for (let sh = 0; sh < 6; sh++) {
    const y = 3 + sh * 8;
    for (let x = 3; x < 29; x += 5) {
      const k = KEYS[Math.floor(rng() * KEYS.length)];
      p.box(x, y, 4, 6, k, 0.34 + rng() * 0.2);
      for (let k = 0; k < 6; k++) p.wash(x, y + k, 'bone', 0.50, 0.55);
    }
    p.hline(1, 30, y + 6, 'grey', 0.30);
  }
  for (let y = 1; y < 51; y++) for (let x = 1; x < 31; x++)
    if ((x * 2 + y * 5) % 37 < 2) p.wash(x, y, 'bone', 0.80, 0.18);
  p.frame(1, 1, 30, 50, 'grey', 0.36);
  /* the keypad, the delivery port and the coin return */
  p.box(33, 4, 9, 26, 'grey', 0.14);
  for (let r = 0; r < 5; r++) for (let c = 0; c < 2; c++)
    p.box(34 + c * 4, 6 + r * 5, 3, 3, 'grey', 0.34);
  p.box(33, 33, 9, 5, 'bone', 0.30);
  p.box(1, 53, 40, 9, 'grey', 0.10);
  p.hline(1, 40, 53, 'grey', 0.30);
  p.box(33, 42, 8, 3, 'grey', 0.30);
  p.vline(0, 0, 63, 'grey', 0.12); p.vline(43, 0, 63, 'grey', 0.12);
  p.grime(0.22, 'grey', 0.05, 986);
  return p.snap(0.4);
};

T.BREAKCAB = () => {
  /* The break-room run: cabinet doors, the handles, and the toe kick
     under them. Melamine, and it has been wiped a hundred thousand
     times in exactly one place. */
  const p = new Pix(64, 32, 987);
  p.fill('bone', 0.34);
  for (const x of [0, 32]) {
    p.box(x + 2, 2, 28, 24, 'bone', 0.40);
    p.bevel(x + 2, 2, 28, 24, 'bone', 0.56, 'grey', 0.16);
    p.box(x + 22, 12, 6, 2, 'grey', 0.42);
    p.hline(x + 22, x + 27, 12, 'bone', 0.70);
  }
  p.hline(0, 63, 0, 'bone', 0.62); p.hline(0, 63, 1, 'grey', 0.20);
  p.box(0, 27, 64, 5, 'grey', 0.10);           // the toe kick
  p.hline(0, 63, 27, 'grey', 0.24);
  p.grime(0.30, 'grey', 0.06, 988);
  return p.snap(0.4);
};

T.BREAKTOP = () => {
  /* And the counter over it, looked down on: laminate, a stainless
     sink with the tap behind it, the coffee maker with a pot in it, and
     the rings of every mug that was ever put down beside it. */
  const p = new Pix(64, 32, 989);
  const n = fbm(64, 32, 7, 3, 989);
  for (let y = 0; y < 32; y++) for (let x = 0; x < 64; x++)
    p.ink(x, y, 'bone', 0.26 + n[y * 64 + x] * 0.05);
  speckle(64, 32, 260, 990, (x, y, a, b) => p.wash(x, y, a < 0.5 ? 'grey' : 'brown', 0.14 + b * 0.16, 0.3));
  /* the sink */
  p.box(6, 7, 20, 17, 'grey', 0.22);
  p.bevel(6, 7, 20, 17, 'grey', 0.12, 'bone', 0.56);
  p.box(8, 9, 16, 13, 'grey', 0.30);
  p.disc(16, 16, 2, 'grey', 0.14);
  p.box(14, 3, 4, 4, 'bone', 0.52);            // the tap
  p.hline(14, 17, 3, 'bone', 0.72);
  /* the coffee maker and its pot */
  p.box(40, 4, 16, 14, 'grey', 0.16);
  p.box(42, 7, 12, 8, 'brown', 0.22);
  p.hline(42, 53, 7, 'bone', 0.44);
  p.box(41, 19, 14, 3, 'grey', 0.30);
  p.disc(34, 25, 4, 'bone', 0.30); p.disc(34, 25, 3, 'grey', 0.36);
  p.disc(58, 26, 3, 'brown', 0.20);
  p.grime(0.30, 'grey', 0.06, 991);
  return p.snap(0.4);
};

T.WATRCOOL = () => {
  /* The water cooler. A bottle with the level down a third, the two
     taps, and the paper cone dispenser on the side — and it is MASKED,
     because a cooler is narrower at the top than the bottom and a box
     of one is a filing cabinet with a bottle painted on it. */
  const p = new Pix(24, 48, 992);
  p.clear();
  /* the cabinet */
  p.box(2, 20, 20, 28, 'bone', 0.36);
  p.bevel(2, 20, 20, 28, 'bone', 0.54, 'grey', 0.14);
  p.box(5, 27, 14, 7, 'grey', 0.14);           // the recess the cup goes in
  for (const [x, k] of [[8, 'blue'], [14, 'red']]) {
    p.box(x, 24, 3, 4, k, 0.36); p.ink(x + 1, 23, k, 0.52);
  }
  p.box(3, 44, 18, 4, 'grey', 0.12);
  /* the bottle */
  p.box(7, 6, 10, 3, 'cyan', 0.30);
  for (let y = 9; y < 20; y++) {
    const w = 3 + Math.min(6, (y - 8));
    p.box(12 - w, y, w * 2, 1, 'cyan', y > 13 ? 0.34 : 0.18);
  }
  for (let y = 6; y < 20; y++) p.wash(9, y, 'bone', 0.66, 0.55);
  p.box(6, 18, 12, 3, 'grey', 0.28);
  /* the cone dispenser */
  p.box(19, 24, 4, 12, 'bone', 0.48);
  p.frame(19, 24, 4, 12, 'grey', 0.22);
  return p.snap(0.35);
};

T.DIRECTRY = () => {
  /* The lobby directory: a black felt board in an aluminium frame with
     white push-in letters, half the strips blank because half the
     suites are empty. NO NAMES, as ever — what reads at this size is
     the RHYTHM of a strip with something on it and a strip without. */
  const p = new Pix(64, 64, 993);
  p.fill('grey', 0.06);
  const n = fbm(64, 64, 26, 2, 993);
  for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++)
    p.wash(x, y, 'grey', 0.14, n[y * 64 + x] * 0.30);
  const rng = makeRng(994);
  for (let r = 0; r < 12; r++) {
    const y = 5 + r * 5;
    if (rng() < 0.25) continue;
    const w = 14 + Math.floor(rng() * 26);
    for (let x = 6; x < 6 + w; x += 2) p.box(x, y, 1, 3, 'bone', 0.70);
    if (rng() < 0.7) {
      const rx = 48 + Math.floor(rng() * 4);
      for (let x = rx; x < rx + 8; x += 2) p.box(x, y, 1, 3, 'bone', 0.56);
    }
  }
  p.box(4, 0, 56, 4, 'grey', 0.10);
  for (let x = 12; x < 52; x += 2) p.box(x, 1, 1, 3, 'yellow', 0.66);
  p.frame(0, 0, 64, 64, 'grey', 0.42);
  p.frame(1, 1, 62, 62, 'bone', 0.52);
  p.frame(3, 3, 58, 58, 'grey', 0.14);
  /* the glass over it */
  for (let y = 3; y < 61; y++) for (let x = 3; x < 61; x++)
    if ((x + y * 2) % 53 < 2) p.wash(x, y, 'bone', 0.66, 0.16);
  return p.snap(0.4);
};

T.COPIER = () => {
  /* The copier, which every floor has one of and which is always by the
     door: the lid, the paper drawers, the control panel with its green
     light, and the sheet in the output tray that somebody left. */
  const p = new Pix(48, 44, 995);
  p.fill('bone', 0.30);
  p.box(0, 0, 48, 12, 'bone', 0.38);           // the lid
  p.bevel(0, 0, 48, 12, 'bone', 0.54, 'grey', 0.16);
  p.box(4, 3, 26, 6, 'grey', 0.14);            // the platen glass
  p.box(33, 2, 13, 8, 'grey', 0.12);           // the panel
  p.disc(36, 6, 1, 'green', 0.60); p.disc(40, 6, 1, 'grey', 0.26);
  for (let x = 42; x < 45; x += 2) p.box(x, 4, 1, 4, 'grey', 0.30);
  p.box(2, 13, 44, 7, 'bone', 0.44);           // the output tray
  p.hline(2, 45, 13, 'grey', 0.18);
  p.box(8, 15, 22, 4, 'bone', 0.66);
  for (let k = 0; k < 3; k++) {                // the paper drawers
    const y = 21 + k * 7;
    p.box(1, y, 46, 6, 'bone', 0.34);
    p.bevel(1, y, 46, 6, 'bone', 0.48, 'grey', 0.14);
    p.box(20, y + 2, 9, 2, 'grey', 0.42);
  }
  p.hline(0, 47, 43, 'grey', 0.10);
  p.grime(0.26, 'grey', 0.06, 996);
  return p.snap(0.4);
};

T.PLANTPOT = () => {
  /* The lobby ficus. Every office has one and it has been in that pot
     since the building opened; two of its branches are dead and the
     soil has a cigarette in it. MASKED, because the one thing a plant
     may not be is a rectangle. */
  const p = new Pix(40, 56, 997);
  p.clear();
  /* the planter */
  for (let y = 38; y < 56; y++) {
    const w = 15 - Math.floor((y - 38) / 6);
    p.box(20 - w, y, w * 2, 1, 'brown', 0.20);
  }
  p.box(5, 38, 30, 3, 'brown', 0.30);
  p.hline(5, 34, 38, 'brown', 0.42);
  p.box(8, 40, 24, 2, 'grey', 0.10);           // the soil
  /* the trunk */
  for (let y = 18; y < 41; y++) p.box(19, y, 3, 1, 'brown', 0.22 + (y % 3) * 0.04);
  p.vline(19, 18, 40, 'brown', 0.34);
  /* the leaves, in three clumps, and two of them dead */
  const rng = makeRng(998);
  const clump = (cx, cy, r, key, lo, hi) => {
    for (let i = 0; i < 150; i++) {
      const a = rng() * Math.PI * 2, d = rng() * r;
      const x = Math.round(cx + Math.cos(a) * d), y = Math.round(cy + Math.sin(a) * d * 0.8);
      if (x < 1 || x > 38 || y < 1 || y > 40) continue;
      p.ink(x, y, key, lo + rng() * (hi - lo));
      if (rng() < 0.4) p.ink(x, y + 1, key, lo * 0.7);
    }
  };
  clump(14, 14, 11, 'green', 0.16, 0.34);
  clump(27, 18, 10, 'green', 0.18, 0.38);
  clump(20, 6, 9, 'green', 0.20, 0.40);
  clump(31, 9, 5, 'olive', 0.16, 0.26);
  clump(8, 24, 5, 'olive', 0.14, 0.22);
  return p.snap(0.35);
};

const AFTER_THE_FIRE = {
  CEILFIT: p => fitTray(p, 16, 25, 32, 14, 47, false),
};

/**
 * Every texture in the game, drawn.
 *
 * Handed a bank it already filled, it REPAINTS it: same names, same
 * texture objects, new pixels — which is how the art palette changes
 * under a scene that is already built. See TextureBank.add.
 */
export function bakeTextures(bank = new TextureBank()) {
  const t0 = (typeof performance !== 'undefined' ? performance.now() : Date.now());
  const raw = {};
  for (const [name, gen] of Object.entries(T)) {
    const pix = gen();
    raw[name] = pix;
    bank.add(name, pix, SIZES[name] || {});
  }
  /* and the same surfaces again, after the fire has been through */
  CHARRABLE.forEach((name, i) => {
    if (!raw[name]) { console.warn('nothing to char:', name); return; }
    bank.add(name + '_B', charVariant(raw[name], 3300 + i * 31, AFTER_THE_FIRE[name]),
             SIZES[name] || {});
  });
  const ms = (typeof performance !== 'undefined' ? performance.now() : Date.now()) - t0;
  console.log(`baked ${bank.map.size} textures in ${ms.toFixed(0)}ms`);
  return bank;
}

/** The same thing said the other way round, for the one caller that
 *  means it: repaint what is already there. */
export const repaintTextures = bank => bakeTextures(bank);

export const TEXTURE_NAMES = Object.keys(T);
export { SIZES as TEXTURE_SIZES };
export { T as TEXTURE_GENERATORS };
