/* =====================================================================
   MEWD — the pictures somebody else drew
   =====================================================================

   Everything else the game draws it draws itself, from ramps and noise,
   at start-up. Three things it does not: the wood, the sky and THE
   PEOPLE, which are painted art from other projects and arrive as files.
   This is the small amount of code that turns those files into frames in
   the sprite bank.

   THE FIRE USED TO BE A FOURTH — four painted strips from the golf
   project — and js/fireart.js draws it now, for a reason set out at
   length in that file: those flames were drawn standing on the ground,
   and no amount of masking gives a picture with a flat bottom edge a
   round one.

   A STRIP is the whole format. One picture, N cells wide, every cell the
   same size, laid out left to right in the order they play or the order
   they are chosen from. The strips out of the galvarius project are
   seventeen shoppers, eleven pieces of one, three splats and twenty-six
   frames of a fireball. Same cutter for all of them.

   Cell sizes are NOT guessed from the file. The caller says how wide a
   cell is and the count falls out of the width, because a strip whose
   cell size is inferred is a strip that silently comes apart the day
   somebody adds a frame. js/people.js holds the numbers for the people
   and shares them with the tool that writes the files.

   EVERY CELL FACES EVERY WAY. Nothing loaded here has rotations: a
   shopper looks the same from all sides because there is one drawing of
   them. Doom would have called that
   rotation 0, and the bank stores it as the same Pix in all eight slots.
   ===================================================================== */

import { Pix } from './pixel.js';

/* A frame is a letter, and the letters stop at Z. */
export const STRIP_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/** Cut a strip of equal cells into Pix frames. */
export function stripFrames(img, cell) {
  const n = Math.floor(img.w / cell);
  const out = [];
  for (let f = 0; f < n; f++) {
    const p = new Pix(cell, img.h, 1, false);
    p.clear();
    for (let y = 0; y < img.h; y++)
      for (let x = 0; x < cell; x++) {
        const s = (y * img.w + f * cell + x) * 4;
        if (img.data[s + 3] < 8) continue;
        p.set(x, y, img.data[s], img.data[s + 1], img.data[s + 2], img.data[s + 3]);
      }
    out.push(p);
  }
  return out;
}

/** A strip as one sprite set, lettered A onward — an animation. */
export function addStrip(bank, name, img, cell, opts = {}) {
  const frames = stripFrames(img, cell);
  frames.forEach((p, i) => bank.addFrame(name, STRIP_LETTERS[i], new Array(8).fill(p), opts));
  return frames.length;
}

/** What a browser's decoded <img> looks like to the cutter above. The
 *  platform has a PNG decoder and it is better than any we would write;
 *  this is only the plumbing that gets the bytes back out of it. */
export function imageData(img) {
  const c = document.createElement('canvas');
  c.width = img.naturalWidth || img.width;
  c.height = img.naturalHeight || img.height;
  const g = c.getContext('2d', { willReadFrequently: true });
  g.drawImage(img, 0, 0);
  const d = g.getImageData(0, 0, c.width, c.height);
  return { w: d.width, h: d.height, data: d.data };
}
