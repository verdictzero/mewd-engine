/* =====================================================================
   MEWD — the data the Godot port reads, written from the web build's
   own tables so the two cannot drift:

     godot/data/texpack.json      every pack picture: [w, h, units/px, masked]
     godot/data/palette.json      the 256 display colours (the earth ramps)
     godot/data/palette_lut.png   the 32x32x32 nearest-colour atlas the
                                  post pass snaps to (js/palette.js
                                  buildLutAtlas): 1024x32, blue picks
                                  the slice, red is x in it, green is y

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
console.log(`texpack ${Object.keys(pack).length}, palette ${colors.length}, lut ${lut.width}x${lut.height}`);
