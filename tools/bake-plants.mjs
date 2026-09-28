/* =====================================================================
   MEWD — real plants into the wood's own format
   =====================================================================

     node tools/bake-plants.mjs

   js/forest.js draws every plant as a billboard out of TWO pictures: an
   ALBEDO, which is the plant, and a BURN MAP, which is how it catches.
   The wood's own firs and ferns arrived as a finished pair in
   assets/forest/ and nothing in this repository made them. This does,
   for the town's trees and its hedges, so that a photograph dropped
   into art/plants/ becomes something the wood can plant.

   THE BURN MAP IS FOUR CHANNELS AND ONLY ONE OF THEM IS INTERESTING.
   js/forest.js reads it as:

     R  coals    where embers sit after the flame has gone
     G  char     how black this texel goes
     B  order    WHEN this texel catches, 0 first and 1 last
     A  foliage  leaf rather than wood, which burns differently

   R, G and A come straight off the artwork: a green texel is foliage
   and chars hard; a brown one is trunk, holds its coals and keeps more
   of its own colour. ORDER is the one that has to be invented, and the
   invention is one sentence — FIRE STARTS AT THE FOOT AND GOES UP AND
   OUT. So order is the distance from the bottom centre of the sprite,
   normalised, with a little noise so a crown does not catch as a
   perfect arc. That is what a tree going up looks like from across a
   street, and it is the whole of the model.

   WHY NOT IN THE PAGE. Everything else the game draws, it draws at
   start-up. These are photographs: there is no set of primitives that
   gets you to a lime tree, the same argument tools/bake-art.mjs makes
   about the logo and the weapon. The difference is only where the
   result lands — art-data.js for those two, assets/forest/*.png here,
   because that is the format js/forest.js already loads.

   RUN IT BY HAND when art/plants/ changes, like bake-art.mjs. It is not
   in CI: the output is PNG, and two zlibs that disagree by a byte would
   fail a diff for no reason anybody could act on.
   ===================================================================== */

import { register } from 'node:module';
register('./loader.mjs', import.meta.url);
import fs from 'node:fs';
import { readPNG, writePNG } from './png-read.mjs';

const HERE = new URL('.', import.meta.url);
const src = f => new URL('../art/plants/' + f, HERE);
const dst = f => new URL('../assets/forest/' + f, HERE);

/* ---------- what to bake ----------
   `w` and `h` are the texels the sprite is drawn from, and they follow
   the wood's own: 128x256 for anything tall, 128x128 for anything
   round. The name is the KINDS name in js/forest.js and the file name
   in assets/forest/, which is the same string in both places on
   purpose. */
const JOBS = [
  { file: 'street_round.png',   name: 'street_round',   w: 128, h: 256 },
  { file: 'street_broad.png',   name: 'street_broad',   w: 128, h: 256 },
  { file: 'street_oval.png',    name: 'street_oval',    w: 128, h: 256 },
  { file: 'street_upright.png', name: 'street_upright', w: 128, h: 256 },
  { file: 'street_dense.png',   name: 'street_dense',   w: 128, h: 256 },
  { file: 'street_big.png',     name: 'street_big',     w: 128, h: 256 },
  /* THE CLIPPED BOX WAS BAKED HERE and is not any more: the town's
     hedges are geometry now (see KINDS in js/forest.js). The two PNGs
     it left in assets/forest/ are kept rather than deleted, because the
     photograph they came from is not in this repository and a tool that
     cannot make a file back should not be the reason it goes. */
];

/* ---------- magenta out, alpha in ----------
   The same hue test tools/bake-art.mjs uses on the weapon, and for the
   same reason: the edge of a keyed image is a run of half-magenta
   pixels, and a distance test either keeps a violet fringe or eats the
   artwork. Spill is pulled back out of what is left or the silhouette
   wears a halo that survives everything downstream. */
function chromaCut(img) {
  for (let i = 0; i < img.w * img.h; i++) {
    const o = i * 4;
    const r = img.data[o], g = img.data[o + 1], b = img.data[o + 2];
    if (r > g + 40 && b > g + 40 && r > 80 && b > 80) { img.data[o + 3] = 0; continue; }
    const spill = Math.min(r, b) - g;
    if (spill > 0) { img.data[o] = r - spill * 0.7; img.data[o + 2] = b - spill * 0.7; }
  }
  return img;
}

/** Bounding box of everything still opaque, with a few empty columns
 *  either side ignored — the sparkle in the corner of these particular
 *  files is four pixels and would otherwise set the width. */
function alphaBounds(img) {
  const col = new Int32Array(img.w), row = new Int32Array(img.h);
  for (let y = 0; y < img.h; y++)
    for (let x = 0; x < img.w; x++)
      if (img.data[(y * img.w + x) * 4 + 3] >= 128) { col[x]++; row[y]++; }
  const span = (a, min) => {
    let lo = 0, hi = a.length - 1;
    while (lo < a.length && a[lo] <= min) lo++;
    while (hi >= 0 && a[hi] <= min) hi--;
    return [lo, hi];
  };
  const [x0, x1] = span(col, 3), [y0, y1] = span(row, 3);
  return [x0, y0, x1, y1];
}

/** Resample carrying alpha, colour weighted by coverage, alpha
 *  thresholded once — the renderer alpha-tests at 0.5 and a soft edge
 *  is a hard edge in a random place. */
function resample(img, box, W, H) {
  const [bx0, by0, bx1, by1] = box;
  const sw = bx1 - bx0 + 1, sh = by1 - by0 + 1;
  const out = new Uint8ClampedArray(W * H * 4);
  for (let y = 0; y < H; y++) {
    const sy0 = by0 + (y * sh) / H, sy1 = by0 + ((y + 1) * sh) / H;
    for (let x = 0; x < W; x++) {
      const sx0 = bx0 + (x * sw) / W, sx1 = bx0 + ((x + 1) * sw) / W;
      let r = 0, g = 0, b = 0, a = 0, n = 0, cov = 0;
      for (let yy = Math.floor(sy0); yy < Math.max(Math.ceil(sy1), Math.floor(sy0) + 1); yy++)
        for (let xx = Math.floor(sx0); xx < Math.max(Math.ceil(sx1), Math.floor(sx0) + 1); xx++) {
          if (xx < 0 || yy < 0 || xx >= img.w || yy >= img.h) continue;
          const o = (yy * img.w + xx) * 4, wgt = img.data[o + 3] / 255;
          r += img.data[o] * wgt; g += img.data[o + 1] * wgt; b += img.data[o + 2] * wgt;
          a += img.data[o + 3]; cov += wgt; n++;
        }
      const o = (y * W + x) * 4, c = Math.max(1e-6, cov);
      out[o] = r / c; out[o + 1] = g / c; out[o + 2] = b / c;
      out[o + 3] = (a / n) > 110 ? 255 : 0;
    }
  }
  return { w: W, h: H, data: out };
}

/* a hash, so the order field is not a perfect arc */
function noise(x, y, seed) {
  const s = Math.sin(x * 127.1 + y * 311.7 + seed) * 43758.5453;
  return s - Math.floor(s);
}

/**
 * The burn map, out of the albedo and nothing else.
 *
 * FOLIAGE IS GREEN AND WOOD IS NOT, which is enough: a texel whose
 * green clearly beats its red is a leaf, and everything else on a tree
 * is bark. Leaves char hard and hold no coals; bark holds coals and
 * keeps more of itself, which is why a burnt tree in this game is a
 * black crown over a trunk you can still see the shape of.
 */
function burnMap(al, hedge) {
  const { w, h } = al;
  const out = new Uint8ClampedArray(w * h * 4);
  /* where the fire starts: the foot of the sprite, in the middle */
  const fx = w / 2, fy = h - 1;
  const far = Math.hypot(Math.max(fx, w - fx), h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = (y * w + x) * 4;
    if (al.data[o + 3] < 128) continue;                 // nothing there, nothing burns
    const r = al.data[o], g = al.data[o + 1], b = al.data[o + 2];
    /* leaf-ness: green over the other two, and not a grey */
    const leaf = Math.max(0, Math.min(1, (g - Math.max(r, b) * 0.86) / 26));
    /* ORDER: how far from the foot, with the vertical counting for more
       than the horizontal, because fire climbs faster than it spreads */
    const d = Math.hypot((x - fx) * 0.72, (y - fy)) / far;
    const jit = (noise(x, y, 11) - 0.5) * 0.10 + (noise(x >> 3, y >> 3, 29) - 0.5) * 0.16;
    const order = Math.max(0, Math.min(1, d * (hedge ? 1.35 : 1.06) + jit));
    out[o]     = Math.round(255 * (0.30 + 0.55 * (1 - leaf)));   // coals: wood keeps them
    out[o + 1] = Math.round(255 * (0.55 + 0.45 * leaf));         // char: leaves go blackest
    out[o + 2] = Math.round(255 * order);
    out[o + 3] = Math.round(255 * leaf);
  }
  return { w, h, data: out };
}

/* ---------- go ---------- */
let wrote = 0;
for (const job of JOBS) {
  const img = chromaCut(readPNG(src(job.file)));
  const box = alphaBounds(img);
  const al = resample(img, box, job.w, job.h);
  let solid = 0;
  for (let i = 3; i < al.data.length; i += 4) if (al.data[i] > 128) solid++;
  const bm = burnMap(al, job.h === job.w);
  fs.writeFileSync(dst(`${job.name}.png`), writePNG(al.w, al.h, al.data));
  fs.writeFileSync(dst(`${job.name}_burn.png`), writePNG(bm.w, bm.h, bm.data));
  const [x0, y0, x1, y1] = box;
  console.log(`${job.name.padEnd(15)} artwork ${x1 - x0 + 1}x${y1 - y0 + 1} -> ` +
              `${job.w}x${job.h}, ${(100 * solid / (job.w * job.h)).toFixed(0)}% of the tile is plant`);
  wrote += 2;
}
console.log(`${wrote} files into assets/forest/`);
