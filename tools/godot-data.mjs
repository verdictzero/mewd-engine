/* =====================================================================
   MEWD — the data the Godot port reads, written from the web build's
   own tables so the two cannot drift:

     godot/data/texpack.json      every pack picture: [w, h, units/px, masked]
     godot/data/palette.json      the 256 display colours (the earth ramps)
     godot/data/palette_lut.png   the 32x32x32 nearest-colour atlas the
                                  post pass snaps to (js/palette.js
                                  buildLutAtlas): 1024x32, blue picks
                                  the slice, red is x in it, green is y
     godot/data/lamp_*.png        the street lamp's two tiles
     godot/data/cemfence.png      the cemetery iron (RAILING)
     godot/data/stones.png        the eight headstones, one strip
     godot/data/grid*.png         the grid's floor and wall (GRID, GRIDWALL)

   node tools/godot-data.mjs
   ===================================================================== */
import { writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

const { PACK_LIST } = await import('../js/texpack-data.js');
const pal = await import('../js/palette.js');

const OUT = new URL('../godot/data/', import.meta.url);

const pack = {};
for (const [n, w, h, k, masked] of PACK_LIST) pack[n] = [w, h, k, masked];
writeFileSync(new URL('texpack.json', OUT), JSON.stringify(pack));

const colors = pal.displayPalette();
writeFileSync(new URL('palette.json', OUT), JSON.stringify(colors.map(c => [c[0], c[1], c[2]])));

/* a PNG, by hand: the RGBA rows, each with a filter byte of 0 */
function png(w, h, rgba) {
  const crcT = new Int32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c; });
  const crc = b => { let c = -1; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (type, data) => {
    const t = Buffer.from(type), len = Buffer.alloc(4), c = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    c.writeUInt32BE(crc(Buffer.concat([t, data])));
    return Buffer.concat([len, t, data, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
                        chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
const lut = pal.buildLutAtlas(colors);
writeFileSync(new URL('palette_lut.png', OUT), png(lut.width, lut.height, lut.data));

/* THE STREET LAMP'S TILES. They are palette-indexed run-length tiles in
   the web build, drawn out at load; here they are PNGs the port stands
   up as geometry (godot/scripts/render/lamps.gd). Transparent where the
   tile says CLEAR_INDEX, the ramp palette's colour everywhere else. */
const art = await import('../js/art-data.js');
for (const name of ['lamp_head', 'lamp_post', 'cemfence']) {
  const c = art.CUTOUTS[name];
  const bytes = Buffer.from(c.tile, 'base64');
  const rgba = new Uint8Array(c.w * c.h * 4);
  let at = 0;
  for (let i = 0; i + 1 < bytes.length && at < c.w * c.h; i += 2)
    for (let n = bytes[i + 1]; n > 0 && at < c.w * c.h; n--, at++) {
      if (bytes[i] === art.CLEAR_INDEX) continue;
      const col = pal.PALETTE[bytes[i]];
      rgba.set([col[0], col[1], col[2], 255], at * 4);
    }
  writeFileSync(new URL(`${name}.png`, OUT), png(c.w, c.h, rgba));
}
/* THE HEADSTONES (js/sprites.js THE HEADSTONES): the eight photographs
   in one strip, each at its own size, feet at the bottom middle of a
   32x48 cell — a sprite is drawn one unit to the pixel */
{
  const STONES = ['stone_round', 'stone_worn', 'stone_plain', 'stone_tapered',
                  'stone_rough', 'stone_obelisk', 'stone_cross', 'stone_crossback'];
  const CW = 32, CH = 48, W = CW * STONES.length;
  const rgba = new Uint8Array(W * CH * 4);
  STONES.forEach((name, k) => {
    const c = art.CUTOUTS[name];
    const bytes = Buffer.from(c.tile, 'base64');
    const ox = k * CW + ((CW - c.w) >> 1), oy = CH - c.h;
    let at = 0;
    for (let i = 0; i + 1 < bytes.length && at < c.w * c.h; i += 2)
      for (let n = bytes[i + 1]; n > 0 && at < c.w * c.h; n--, at++) {
        if (bytes[i] === art.CLEAR_INDEX) continue;
        const col = pal.PALETTE[bytes[i]];
        rgba.set([col[0], col[1], col[2], 255], ((oy + ((at / c.w) | 0)) * W + ox + (at % c.w)) * 4);
      }
  });
  writeFileSync(new URL('stones.png', OUT), png(W, CH, rgba));
}

/* THE GRID'S TWO PICTURES (gridPix in js/textures.js): green lines on
   black, 256 square in full colour, the line a gaussian glow either side
   of the cell edge — the only textures the game draws smooth */
function gridPix(size, bg, line, half, lineW, halfW) {
  const rgba = new Uint8Array(size * size * 4);
  const mix = (a, b, t) => a + (b - a) * t;
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const d = Math.min(Math.min(x, size - x), Math.min(y, size - y));
    const h = Math.min(Math.abs(x - size / 2), Math.abs(y - size / 2));
    const edge = Math.exp(-(d * d) / lineW), mid = Math.exp(-(h * h) / halfW) * 0.45;
    const c = [0, 1, 2].map(k => Math.round(mix(mix(bg[k], half[k], mid), line[k], edge)));
    rgba.set([c[0], c[1], c[2], 255], (y * size + x) * 4);
  }
  return png(size, size, rgba);
}
writeFileSync(new URL('grid.png', OUT), gridPix(256, [6, 11, 8], [70, 255, 140], [22, 104, 54], 20, 9));
writeFileSync(new URL('gridwall.png', OUT), gridPix(256, [5, 9, 9], [44, 190, 130], [16, 74, 52], 16, 7));
console.log(`texpack ${Object.keys(pack).length}, palette ${colors.length}, lut ${lut.width}x${lut.height}, lamp tiles, the cemetery iron, the headstones, the grid`);
