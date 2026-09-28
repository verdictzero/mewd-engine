/* =====================================================================
   PACKING THE SITE UP, from inside the site

   At the user's request: a DOWNLOAD in the pause menu that hands you
   the whole game as one file, to keep and to run without a network.

   There is no server here to ask for a zip — the game is a static page
   and the only machine involved is the one already holding every file,
   because it fetched them to play. So the page builds the archive
   ITSELF: it reads the packing list, fetches each file back (out of the
   browser cache, mostly, which is why a sixty-megabyte download takes a
   few seconds rather than a few minutes), and writes a ZIP by hand.

   THE ZIP IS STORED, NOT DEFLATED. Fifty-six of the sixty megabytes are
   PNGs, MP3s and GLBs, all of them compressed already; squeezing the
   two and a half megabytes of source on top would cost a pass over
   everything to save under two per cent. So every entry goes in flat,
   which makes the writer small enough to read in one sitting: a header
   per file, a table of them at the end, and a CRC of each.
   ===================================================================== */

/* WHERE THE LIST COMES FROM. tools/build-site.sh writes files.json into
   the deployed site — the authority on what the site is, because it is
   generated from what was actually copied — and the same list is kept
   in the repository so a checkout served straight off the disk packs
   too. The smoke test regenerates it and fails if the two drift. */
export const MANIFEST = 'files.json';

/** What the archive unpacks into, so nothing lands loose in Downloads. */
export const FOLDER = 'sellwrong';

/* ---------------------------------------------------------------------
   CRC32, the one sum a stored zip still has to do

   Table-driven, built once on first use: the standard reversed
   polynomial, which is the one every zip reader checks against.
   --------------------------------------------------------------------- */
let TABLE = null;

function crcTable() {
  if (TABLE) return TABLE;
  TABLE = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    TABLE[n] = c >>> 0;
  }
  return TABLE;
}

export function crc32(bytes) {
  const t = crcTable();
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = t[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

/* ---------------------------------------------------------------------
   THE WRITER

   A zip is three things in a row: every file with a small header in
   front of it, then a table of those files, then a note saying where
   the table is and how long it is. Sizes are little-endian, which is
   what the two put() helpers are for.
   --------------------------------------------------------------------- */
const LOCAL = 0x04034B50, CENTRAL = 0x02014B50, END = 0x06054B50;
const UTF8 = 0x0800;                     // the flag that says the name is UTF-8

function u16(v) { return [v & 0xFF, (v >>> 8) & 0xFF]; }
function u32(v) { return [v & 0xFF, (v >>> 8) & 0xFF, (v >>> 16) & 0xFF, (v >>> 24) & 0xFF]; }

/** MS-DOS time and date, which is what a zip stores: two seconds of
 *  resolution and a year that starts at 1980. */
function dosStamp(d = new Date()) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  const date = ((Math.max(1980, d.getFullYear()) - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  return { time, date };
}

export class Zip {
  constructor(stamp = dosStamp()) {
    this.parts = [];                     // every chunk, in the order they go out
    this.entries = [];                   // what the table at the end is built from
    this.at = 0;                         // where the next header starts
    this.stamp = stamp;
  }

  push(bytes) { this.parts.push(bytes); this.at += bytes.length; }

  /** One file: the header, then the bytes, flat. */
  add(name, bytes) {
    const nameBytes = new TextEncoder().encode(name);
    const crc = crc32(bytes), n = bytes.length, offset = this.at;
    this.push(new Uint8Array([
      ...u32(LOCAL), ...u16(20), ...u16(UTF8), ...u16(0),
      ...u16(this.stamp.time), ...u16(this.stamp.date),
      ...u32(crc), ...u32(n), ...u32(n),
      ...u16(nameBytes.length), ...u16(0),
      ...nameBytes,
    ]));
    this.push(bytes);
    this.entries.push({ nameBytes, crc, n, offset });
    return this;
  }

  /** Text goes in as UTF-8, which is all this one ever adds by hand. */
  addText(name, text) { return this.add(name, new TextEncoder().encode(text)); }

  /** The table and the note, and then it is a file. */
  close(type = 'application/zip') {
    const start = this.at;
    for (const e of this.entries) {
      this.push(new Uint8Array([
        ...u32(CENTRAL), ...u16(20), ...u16(20), ...u16(UTF8), ...u16(0),
        ...u16(this.stamp.time), ...u16(this.stamp.date),
        ...u32(e.crc), ...u32(e.n), ...u32(e.n),
        ...u16(e.nameBytes.length), ...u16(0), ...u16(0),
        ...u16(0), ...u16(0), ...u32(0), ...u32(e.offset),
        ...e.nameBytes,
      ]));
    }
    this.push(new Uint8Array([
      ...u32(END), ...u16(0), ...u16(0),
      ...u16(this.entries.length), ...u16(this.entries.length),
      ...u32(this.at - start), ...u32(start), ...u16(0),
    ]));
    return new Blob(this.parts, { type });
  }
}

/* ---------------------------------------------------------------------
   WHAT IS IN THE BOX, besides the game

   Every file is an ES module, and a browser will not load one over
   file:// — it is a cross-origin request from a page with no origin,
   and it fails with a message about CORS that says nothing about what
   to do. So the archive carries the answer in a text file next to the
   page: one line to serve the folder, and the address to open.
   --------------------------------------------------------------------- */
export const RUN_ME =
`MEWD — running it on your own machine
=========================================================

Everything the game needs is in this folder. It does not phone home,
it does not need a network once it is unpacked, and there is nothing
to install or compile.

BUT IT CANNOT BE OPENED BY DOUBLE-CLICKING index.html. The game is
written as ES modules, and a browser refuses to load a module from a
file:// address — it treats the page as having no origin and blocks
its own files. You need any web server, pointed at this folder. One of
these, run from inside it, is enough:

    python3 -m http.server 8000
    npx http-server -p 8000 .
    php -S localhost:8000

Then open:

    http://localhost:8000/

Stop the server with ctrl-C when you are done.

WHAT IS HERE
    index.html          the page
    js/                 the game
    css/  vendor/       the furniture, and three.js
    assets/             the wood, the people, the models, the music
`;

/* ---------------------------------------------------------------------
   THE JOB ITSELF

   Read the list, fetch every file on it, and hand back a blob. It goes
   one at a time deliberately: sixty megabytes of parallel fetches is a
   way to be killed by a phone, and the progress a person is watching
   should mean something.
   --------------------------------------------------------------------- */
export async function packSite({ onProgress, fetcher = fetch, base = '' } = {}) {
  const listed = await fetcher(base + MANIFEST, { cache: 'no-cache' });
  if (!listed.ok) throw new Error(`no packing list (${listed.status})`);
  const files = await listed.json();
  if (!Array.isArray(files) || !files.length) throw new Error('the packing list is empty');

  const zip = new Zip();
  zip.addText(`${FOLDER}/RUN-ME.txt`, RUN_ME);
  let done = 0;
  for (const name of files) {
    const res = await fetcher(base + name);
    if (!res.ok) throw new Error(`${name} (${res.status})`);
    zip.add(`${FOLDER}/${name}`, new Uint8Array(await res.arrayBuffer()));
    onProgress?.(++done / files.length, name);
  }
  return { blob: zip.close(), count: files.length + 1 };
}

/** Hand the blob to the browser as a download, and let it go again. */
export function save(blob, name = `${FOLDER}.zip`) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
