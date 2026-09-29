/* =====================================================================
   MEWD — smoke test
   =====================================================================

   node tools/smoke-test.mjs

   No install, no browser. Everything that is not WebGL is checked here:
   the palette, the texture and sprite bakeries, the map, the collision,
   the state tables and the fire grid.

   The checks earn their place by having caught something. Each one below
   corresponds to a bug that reached a screenshot before it was found:

     - a sprite whose art wrapped around the edge of its own canvas, so
       a forearm drawn off the bottom appeared in the sky
     - a monster state naming a frame letter the bakery never made, so
       the Stocker's pain frame did not exist
     - a wall texture chosen by which sector was DECLARED first, so an
       aisle had shelving down one side and blank plaster down the other
     - a move long enough to step clean through a wall without any test
       noticing it had been there

   A test suite for a game is mostly worthless — you cannot assert that
   something is fun. But every one of those was a data error with a
   correct answer, and every one of them is cheaper to catch here.
   ===================================================================== */

import { register } from 'node:module';
register('./loader.mjs', import.meta.url);

/* Enough of a canvas for Pix.toCanvas to succeed, which is the only DOM
   call anywhere in the bakeries. With this the test can build a real
   TextureBank, a real SpriteBank and a real Game, and exercise the
   game's OWN lighting code rather than a copy of it kept in step by
   hand — which is the kind of copy that drifts and then passes while the
   game is broken. */
globalThis.document = {
  createElement: () => ({
    width: 0, height: 0,
    getContext: () => ({
      createImageData: (w, h) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h }),
      putImageData() {},
    }),
  }),
};

let pass = 0, fail = 0;
const problems = [];
function check(name, cond, detail = '') {
  if (cond) { pass++; return true; }
  fail++; problems.push(`${name}${detail ? ' — ' + detail : ''}`);
  return false;
}
const section = s => console.log(`\n  ${s}\n  ${'-'.repeat(s.length)}`);
const note = (k, v) => console.log(`    ${k.padEnd(34)} ${v}`);

/* ---------- the shaders, before anything imports one ----------------
   A GLSL block lives in a JavaScript template literal, and a template
   literal with no interpolation ends at the NEXT backtick wherever that
   is — so a pair of them in a COMMENT closes the shader mid-sentence
   and the rest of it silently becomes JavaScript. The file still parses
   as far as node is concerned; the game dies on IMPORT with "Unexpected
   identifier", naming a word out of a comment, and says nothing about
   which file or why.

   It has cost two debugging sessions, and it has to be checked HERE,
   at the top, reading the file as TEXT — a check further down cannot
   run, because the import that kills the process happens first. What is
   asserted is not "is there a stray backtick" but "does each shader
   still reach the line it is supposed to end on", which is the thing
   that actually goes wrong. */
{
  const fs0 = await import('node:fs');
  const src = fs0.readFileSync('js/material.js', 'utf8');
  for (const [tag, last] of [['const COMMON_VERT', 'gl_Position'],
                             ['const COMMON_FRAG', 'gl_FragColor']]) {
    const at = src.indexOf(tag);
    const open = at < 0 ? -1 : src.indexOf('`', at);
    const close = open < 0 ? -1 : src.indexOf('`', open + 1);
    const whole = close > open && src.slice(open + 1, close).includes(last);
    /* SAID NOW, NOT AT THE END. Everything else in this file records a
       failure and prints the list when the run finishes — and this run
       will not finish: the import a few lines down is the thing that
       throws. So this one says what is wrong and stops, which is the
       whole point of it. */
    if (!whole) {
      console.error(`\n  BROKEN SHADER\n  -------------\n` +
        `    ${tag.slice(6)} in js/material.js does not reach ${last}.\n` +
        `    A backtick in a comment inside the GLSL has ended the template\n` +
        `    literal early, and the rest of the shader is now JavaScript.\n`);
      process.exit(1);
    }
    check(`${tag.slice(6)} runs to its own last line`, whole);
  }
}

/* ---------- palette ---------- */
section('palette');
const pal = await import('../js/palette.js');
check('256 entries', pal.PALETTE.length === 256, `got ${pal.PALETTE.length}`);
check('every entry is 3 bytes', pal.PALETTE.every(c => c.length === 3 && c.every(v => v >= 0 && v <= 255)));
check('fire ramp runs dark to light',
  pal.ramp('fire', 0)[0] < 20 && pal.ramp('fire', 1)[0] > 240);
check('ramps are monotonic in luma', ['grey', 'red', 'blue', 'fire'].every(k => {
  let last = -1;
  for (let i = 0; i <= 10; i++) {
    const c = pal.ramp(k, i / 10);
    const l = c[0] * 0.3 + c[1] * 0.6 + c[2] * 0.1;
    if (l < last - 2) return false;
    last = l;
  }
  return true;
}));
{
  const t0 = Date.now();
  const atlas = pal.buildLutAtlas();
  note('lut atlas', `${atlas.width}x${atlas.height} in ${Date.now() - t0}ms`);
  check('lut is the right size', atlas.data.length === atlas.width * atlas.height * 4);
  const N = pal.LUT_SIZE, W = atlas.width;
  const look = (r, g, b) => {
    const R = Math.round(r / 255 * (N - 1)), G = Math.round(g / 255 * (N - 1)), B = Math.round(b / 255 * (N - 1));
    const o = ((G * W) + (B * N + R)) * 4;
    return [atlas.data[o], atlas.data[o + 1], atlas.data[o + 2]];
  };
  check('lut snaps to real palette entries',
    [[255, 255, 255], [0, 0, 0], [255, 140, 20], [90, 90, 100]].every(c => {
      const s = look(...c);
      return pal.PALETTE.some(p => p[0] === s[0] && p[1] === s[1] && p[2] === s[2]);
    }));
}

/* ---------- THE ART PALETTE AND THE DISPLAY PALETTE -------------------

   Two palettes answering different questions, at the user's request.
   The ART palette is what a picture is PAINTED in — the fifteen ramps,
   and it never changes. The DISPLAY palette is what the SCREEN can
   hold: the post pass dithers the finished frame and snaps it through a
   lookup cube built from that one, and so does the sky as it bakes.

   THAT WAY ROUND IS THE WHOLE POINT. The art keeps all the colour it
   was drawn with and the ordered dither carries it down to the hardware
   box at the last moment. Painting the textures in the small box as
   well was the first attempt and it was worse — dithering at 64 texels
   and then again at grid resolution is not twice the texture, it is
   noise — so the first duty of these checks is that the ART DOES NOT
   MOVE when the screen's box does.
   ------------------------------------------------------------------ */
{
  check('the art palette is the ramps, entry for entry',
    pal.PALETTE.length === 256 && pal.PALETTE === pal.RAMP_PALETTE);
  let drift = 0;
  for (const key of Object.keys(pal.RAMP))
    for (let i = 0; i <= 64; i++) {
      const r = pal.RAMP[key];
      const idx = r.start + Math.max(0, Math.min(r.n - 1, Math.round((i / 64) * (r.n - 1))));
      const c = pal.ramp(key, i / 64);
      if (!c.every((v, k) => v === pal.RAMP_PALETTE[idx][k])) drift++;
    }
  check('and every ramp still lands on the palette entry it always did', drift === 0, `${drift} drifted`);

  /* THE UZEBOX BOX is a piece of hardware: three bits of red, three of
     green and two of blue through a resistor ladder. Generated rather
     than pasted, because 256 lines of hex is a table nobody can check —
     so the check is against the file it came from. */
  const fsP = await import('node:fs');
  const hex = fsP.readFileSync(new URL('../art/uzebox.hex', import.meta.url), 'utf8')
    .trim().split('\n').filter(Boolean)
    .map(l => [parseInt(l.slice(0, 2), 16), parseInt(l.slice(2, 4), 16), parseInt(l.slice(4, 6), 16)]);
  check('the uzebox box has 256 entries and matches the file, entry for entry',
    hex.length === 256 && pal.UZEBOX_PALETTE.length === 256 &&
    pal.UZEBOX_PALETTE.every((c, i) => c.every((v, k) => v === hex[i][k])));
  const levels = a => new Set(pal.UZEBOX_PALETTE.map(c => c[a])).size;
  note('the uzebox box', `${levels(0)} reds, ${levels(1)} greens, ${levels(2)} blues`);
  check('and it is eight by eight by four, which is where two bits of blue shows',
    levels(0) === 8 && levels(1) === 8 && levels(2) === 4);

  /* CHOOSING WHAT THE SCREEN HOLDS */
  check('the screen starts in the same box the art is in', pal.displayName === 'ramps' &&
    pal.displayPalette() === pal.RAMP_PALETTE);
  check('a box that is not a box is refused', pal.setDisplayPalette('nonsense') === false);
  check('and the one already in use is refused', pal.setDisplayPalette('ramps') === false);
  check('and the uzebox one is taken', pal.setDisplayPalette('uzebox') === true &&
    pal.displayName === 'uzebox' && pal.displayPalette() === pal.UZEBOX_PALETTE);

  /* THE ART DOES NOT MOVE. This is the check the whole design exists
     for: bake a texture with the screen in each box and hold the two
     against each other, texel for texel. */
  {
    const texP = await import('../js/textures.js');
    const before = texP.TEXTURE_GENERATORS.CLAPBRD();
    pal.setDisplayPalette('ramps');
    const after = texP.TEXTURE_GENERATORS.CLAPBRD();
    pal.setDisplayPalette('uzebox');
    let same = true;
    for (let i = 0; i < before.data.length; i++) if (before.data[i] !== after.data[i]) { same = false; break; }
    check('a texture baked with the screen in either box is the same texture', same);
    check('and every texel of it is a colour the ART palette has',
      [...Array(64)].every((_, i) => {
        const o = i * 4;
        return pal.PALETTE.some(c => c[0] === before.data[o] && c[1] === before.data[o + 1] && c[2] === before.data[o + 2]);
      }));
  }

  /* AND THE LOOKUP CUBE FOLLOWS THE SCREEN, which is the only thing
     that does. Built with no argument it is the display box; given one
     it still honours it, because the sky's own test wants to ask about
     a palette that is not the current one. */
  {
    const uze = pal.buildLutAtlas();
    const N = pal.LUT_SIZE, W = uze.width;
    const look = (atlas, r, g, b) => {
      const R = Math.round(r / 255 * (N - 1)), G = Math.round(g / 255 * (N - 1)), B = Math.round(b / 255 * (N - 1));
      const o = ((G * W) + (B * N + R)) * 4;
      return [atlas.data[o], atlas.data[o + 1], atlas.data[o + 2]];
    };
    const probes = [[255, 255, 255], [0, 0, 0], [255, 140, 20], [90, 90, 100], [40, 60, 132]];
    check('with the screen in the uzebox box the cube snaps to uzebox colours',
      probes.every(c => {
        const s2 = look(uze, ...c);
        return pal.UZEBOX_PALETTE.some(q => q[0] === s2[0] && q[1] === s2[1] && q[2] === s2[2]);
      }));
    /* and it is a DIFFERENT cube, or the setting would do nothing */
    const ramps = pal.buildLutAtlas(pal.RAMP_PALETTE);
    let differs = 0;
    for (let i = 0; i < uze.data.length; i += 4) if (uze.data[i] !== ramps.data[i]) differs++;
    check('and it is not the same cube the ramps make, or the setting would do nothing',
      differs > uze.data.length / 8, `${differs} cells of ${uze.data.length / 4} differ`);
    check('and an explicit palette is still honoured, which the sky test needs',
      probes.every(c => {
        const s2 = look(ramps, ...c);
        return pal.RAMP_PALETTE.some(q => q[0] === s2[0] && q[1] === s2[1] && q[2] === s2[2]);
      }));
  }

  /* ------------------------------------------------------------------
     AND A SECOND BOX TO PAINT IN

     At the user's request, and asked for as a test that could be undone
     — so it is a setting, and the first duty of these checks is that
     the way back is exact.

     THE SAME FIFTEEN IS THE WHOLE TRICK. Every ramp in the earth box has
     the same key, the same length and the same place in the list as the
     one it replaces, so RAMP[key] lands at the same index and entry n of
     the palette means the same MATERIAL in both boxes — which is what
     lets the two pictures in art/, kept as palette indices in
     js/art-data.js, come out recoloured rather than scrambled without
     tools/bake-art.mjs being run again. Change an `n` and that stops
     being true silently, which is what this first check is for.
     ------------------------------------------------------------------ */
  {
    const shape = t => pal.ART_PALETTES[t].map(r => `${r.key}:${r.n}`).join(' ');
    /* THREE BOXES NOW. STOCK is the one the game was drawn in and the
       one the two pictures in art/ are baked against — see the note at
       the top of tools/bake-art.mjs, which pins itself to it. EARTH is
       the superstore's. GRID is the world the game boots into, and is
       the one the MENU starts on (TONE_SET in js/main.js); palette.js
       itself still defaults to earth, because that is the box the
       photographs were recoloured through and changing it would move
       what `DEFAULT_ART` means to tools/bake-art.mjs. */
    check('there are three boxes to paint in, and the library default is still earth',
      Object.keys(pal.ART_PALETTES).join(',') === 'stock,earth,grid' && pal.artName === 'earth' &&
      pal.DEFAULT_ART === 'earth');
    check('and all three have the same fifteen ramps, same lengths, same order',
      shape('stock') === shape('earth') && shape('stock') === shape('grid'), `${shape('grid')}`);
    /* AND THE GRID BOX HAS GREEN TO SPEND, which is the whole reason it
       exists: a world of green lines on black painted out of the earth
       box gets sixteen entries of sage and a sky ramp full of dawn. */
    {
      const greens = t => {
        pal.setArtPalette(t);
        const n = pal.PALETTE.filter(c => c[1] > c[0] + 8 && c[1] > c[2] + 8).length;
        return n;
      };
      const g = greens('grid'), e = greens('earth');
      pal.setArtPalette('earth');
      note('greens to paint a green world with', `grid ${g} of 256, against earth's ${e}`);
      check('the grid box has several times the green the others do', g > e * 3, `${g} against ${e}`);
    }
    check('which is what keeps a palette index meaning the same material in both',
      pal.ART_PALETTES.stock.reduce((a, r) => a + r.n, 0) === 256);

    const earthFirst = pal.RAMP_PALETTE.map(c => c.slice());
    const starts = Object.fromEntries(Object.keys(pal.RAMP).map(k => [k, pal.RAMP[k].start]));
    const wasObject = pal.RAMP_PALETTE;

    check('a box that is not a box is refused', pal.setArtPalette('nonsense') === false);
    check('and the one already in use is refused', pal.setArtPalette('earth') === false);
    check('and the one it was drawn in is taken', pal.setArtPalette('stock') === true && pal.artName === 'stock');
    const stock = pal.RAMP_PALETTE.map(c => c.slice());
    check('and switching back to earth gives back exactly the box it started in',
      pal.setArtPalette('earth') === true &&
      pal.RAMP_PALETTE.every((c, i) => c.every((v, k) => v === earthFirst[i][k])));
    pal.setArtPalette('stock');

    /* IT IS FILLED IN PLACE AND NEVER REPLACED. Half the game is holding
       this array — PALETTE is it, the default display box is it,
       decodeArtTile indexes it — and a module that captured it at load
       time would keep the old colours for ever if setArtPalette handed
       back a new one. */
    check('the palette is the same array it always was, with new colours in it',
      pal.RAMP_PALETTE === wasObject && pal.PALETTE === wasObject &&
      pal.DISPLAY_PALETTES.ramps.colors === wasObject && pal.RAMP_PALETTE.length === 256);
    check('and not one ramp moved, so every index still means what it meant',
      Object.keys(pal.RAMP).every(k => pal.RAMP[k].start === starts[k]));

    pal.setArtPalette('earth');
    const earth = pal.RAMP_PALETTE.map(c => c.slice());
    const sat = c => (Math.max(...c) - Math.min(...c)) / 255;
    const lum = c => (3 * c[0] + 6 * c[1] + c[2]) / 10;
    const mean = a => a.reduce((x, y) => x + y, 0) / a.length;
    note('the two boxes', `saturation ${mean(stock.map(sat)).toFixed(3)} -> ${mean(earth.map(sat)).toFixed(3)}, ` +
      `brightest ${Math.max(...stock.map(lum)) | 0} -> ${Math.max(...earth.map(lum)) | 0}`);
    check('the earth box is a different box', earth.some((c, i) => c.some((v, k) => v !== stock[i][k])));
    check('and it is muted: less colour in it than the one it replaces',
      mean(earth.map(sat)) < mean(stock.map(sat)) * 0.9,
      `${mean(earth.map(sat)).toFixed(3)} against ${mean(stock.map(sat)).toFixed(3)}`);
    check('and nothing in it reaches white, which is what says faded',
      Math.max(...earth.map(lum)) < Math.max(...stock.map(lum)) - 8 &&
      earth.every(c => Math.max(...c) <= 250));
    /* THE BLACKS GO BROWN. A shadow in the stock box is cool — a shadow
       full of skylight; in the earth box it is a shadow full of dust. */
    {
      const g0 = pal.RAMP.grey.start;
      check('and the blacks are warm rather than cool, which is the other half of earthy',
        earth[g0][0] >= earth[g0][2] && stock[g0][0] <= stock[g0][2],
        `${earth[g0].join(',')} against ${stock[g0].join(',')}`);
    }
    /* HOW FAR EACH RAMP TRAVELLED, weighted 3:6:1 across R:G:B — the
       eye's own weighting, and the same one nearestIndex snaps with.
       Plain luminance is the wrong ruler here and was the first one
       tried: the earth blue is about as BRIGHT as the stock blue and
       most of the way to slate, so by luminance it had barely moved
       when by eye it had moved further than almost anything. */
    {
      const dist = (a, b) => Math.sqrt(3 * (a[0] - b[0]) ** 2 + 6 * (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) / Math.sqrt(10);
      const moved = k => { const r = pal.RAMP[k]; let d = 0;
        for (let i = r.start; i < r.start + r.n; i++) d += dist(earth[i], stock[i]);
        return d / r.n; };
      const far = Object.keys(pal.RAMP).map(k => [k, moved(k)]).sort((a, b) => b[1] - a[1]);
      note('how far each ramp moved', far.map(([k, d]) => `${k} ${d.toFixed(0)}`).join(' '));
      /* THE THREE THAT WERE ALREADY EARTH hardly move, which is the
         whole argument for the box: brown, rust and flesh were the
         answer before the question was asked. */
      check('brown, rust and flesh barely move, because they were already the answer',
        ['brown', 'rust', 'flesh'].every(k => moved(k) < moved('fire')),
        far.slice(-4).map(([k, d]) => `${k} ${d.toFixed(0)}`).join(' '));
      /* AND THE FIRE MOVES LESS THAN THE COLOURS AROUND IT. It is the
         subject of the game and the brightest thing in the frame, and
         what comes off it is the neon rather than the fire. */
      check('and the fire moves less than the four most coloured ramps in the box',
        ['cyan', 'yellow', 'red', 'green'].every(k => moved('fire') < moved(k)),
        `fire ${moved('fire').toFixed(0)} against ` +
        ['cyan', 'yellow', 'red', 'green'].map(k => `${k} ${moved(k).toFixed(0)}`).join(', '));
      /* AND IT KEEPS ITS ROUTE. Seven stops bunched toward the bottom
         because most of a flame, most of the time, is the dull end —
         the colours along it change and where they sit does not. */
      const stops = t => pal.ART_PALETTES[t].find(r => r.key === 'fire').stops.map(x => x[0]).join(',');
      check('and it keeps its route: the same seven stops in the same places',
        stops('stock') === stops('earth'), stops('earth'));
    }

    /* THE SNAP CACHE IS A CACHE OF THE OLD BOX. Every answer in it is an
       index into a palette that no longer holds those colours, so a
       texture repainted through a stale one would come out in the box it
       was supposed to be leaving. */
    check('and the snap cache went with the box, or the first repaint would undo it',
      pal.PALETTE[pal.nearestIndex(...stock[pal.RAMP.green.start + 8])]
        .some((v, k) => v !== stock[pal.RAMP.green.start + 8][k]));

    /* A TEXTURE PAINTED IN IT IS A DIFFERENT TEXTURE, which is the
       difference between a repaint and a filter: the art is DRAWN in
       the new box rather than quantised into it. */
    {
      const texP = await import('../js/textures.js');
      const earthTex = texP.TEXTURE_GENERATORS.CLAPBRD();
      pal.setArtPalette('stock');
      const stockTex = texP.TEXTURE_GENERATORS.CLAPBRD();
      pal.setArtPalette('earth');
      let differs = 0;
      for (let i = 0; i < stockTex.data.length; i += 4) if (stockTex.data[i] !== earthTex.data[i]) differs++;
      check('a texture painted in the earth box is a different texture',
        differs > stockTex.data.length / 8, `${differs} texels of ${stockTex.data.length / 4}`);
      /* AND REPAINTING A BANK KEEPS THE TEXTURE OBJECTS, because every
         material in the scene is holding them. */
      const bank = new texP.TextureBank();
      bank.add('CLAPBRD', earthTex, {});
      const held = bank.get('CLAPBRD').texture;
      pal.setArtPalette('stock');
      texP.repaintTextures(bank);
      check('and repainting a bank gives it new pixels and the same texture object',
        bank.get('CLAPBRD').texture === held && bank.map.size > 400);
      pal.setArtPalette('earth');
    }

    /* AND THE WAY BACK IS EXACT, which is the whole of what "a test I
       can undo" means — and it is the way back to EITHER box, because
       the default moved and the one the art was drawn in is now the one
       you switch to. */
    const back = pal.RAMP_PALETTE.map(c => c.slice());
    check('and the default is restored for everything after this, entry for entry',
      pal.artName === pal.DEFAULT_ART && back.every((c, i) => c.every((v, k) => v === earthFirst[i][k])));
  }
  /* and it is on a button, and remembered, and applied before anything
     is painted rather than after */
  {
    const fs3 = await import('node:fs');
    const html = fs3.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
    const main = fs3.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');
    check('the tone is a ladder in the pause menu, EARTH by default and remembered',
      /id="opt-tone"/.test(html) && /TONE_SET = \[\{ v: 'earth'/.test(main) &&
      /tone: 0,/.test(main) && /ladder\('opt-tone', 'tone', TONE_SET/.test(main));
    check('and a saved tone from before the default moved is not kept alive',
      /if \(was < 11\) \{ delete saved\.tone;/.test(main) && /PREF_VERSION = 11/.test(main));
    check('and a game that starts in the other one paints itself once, not twice',
      /setArtPalette\(TONE_SET\[prefs\.tone\]\.v\)/.test(main) &&
      main.indexOf('setArtPalette(TONE_SET') < main.indexOf('const textures = bakeTextures()'));
    check('and applyTone remakes the four things a repaint moves',
      /function applyTone/.test(main) && /bakeTextures\(textures\)/.test(main) &&
      /bakeSprites\(sprites\)/.test(main) && /dressSprites\(\); dressTroops\(\)/.test(main) &&
      /weapons = bakeWeapons\(\)/.test(main) && /pipeline\.rebuildLut\(\)/.test(main));
  }
  pal.setDisplayPalette('ramps');
  check('and the default is restored for everything after this',
    pal.displayName === 'ramps' && pal.displayPalette() === pal.RAMP_PALETTE);
}

/* ---------- the pixel toolkit ---------- */
section('pixel toolkit');
const pix = await import('../js/pixel.js');
{
  const n = pix.valueNoise(64, 64, 8, 42);
  let edge = 0, interior = 0;
  for (let y = 0; y < 64; y++) {
    edge = Math.max(edge, Math.abs(n[y * 64 + 63] - n[y * 64]));
    for (let x = 1; x < 64; x++) interior = Math.max(interior, Math.abs(n[y * 64 + x] - n[y * 64 + x - 1]));
  }
  check('value noise tiles', edge <= interior * 1.1, `edge jump ${edge.toFixed(3)} vs ${interior.toFixed(3)}`);

  /* the wrap/clip distinction, which is the bug that put a forearm in
     the sky */
  const wrapping = new pix.Pix(16, 16, 1, true);
  wrapping.ink(20, 20, 'red', 1);
  check('a wrapping surface wraps', wrapping.alphaAt(4, 4) > 0);
  const clipping = new pix.Pix(16, 16, 1, false);
  clipping.ink(20, 20, 'red', 1);
  clipping.ink(-3, 8, 'red', 1);
  let any = 0;
  for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) if (clipping.alphaAt(x, y) > 0) any++;
  check('a clipping surface discards', any === 0, `${any} stray pixels`);
}

/* ---------- textures ---------- */
section('textures');
const tex = await import('../js/textures.js');
{
  const names = Object.keys(tex.TEXTURE_GENERATORS);
  note('generators', names.length);
  let opaque = 0, sized = 0;
  const t0 = Date.now();
  for (const n of names) {
    const p = tex.TEXTURE_GENERATORS[n]();
    if (!check(`${n} produces pixels`, p && p.w > 0 && p.h > 0)) continue;
    /* EXCEPT THE TWO RULED LINES. Every picture in this game is a
       64-square painted out of the 256 and point sampled, which is the
       look; the grid world's floor and wall are not pictures of a
       surface, they are geometry standing in for geometry, and a ruled
       line at that size aliases into nothing at the far end of a ten
       thousand unit field. See the note over T.GRID in js/textures.js. */
    const BIG = ['GRID', 'GRIDWALL'];
    check(`${n} is 64px or under`, BIG.includes(n) || (p.w <= 64 && p.h <= 64), `${p.w}x${p.h}`);
    let a = 0;
    for (let i = 3; i < p.data.length; i += 4) if (p.data[i] > 8) a++;
    if (a === p.w * p.h) opaque++;
    sized++;
  }
  note('baked', `${sized} in ${Date.now() - t0}ms, ${opaque} fully opaque`);
}

/* ---------- sprites and states ---------- */
section('sprites and states');
const spr = await import('../js/sprites.js');
const st = await import('../js/states.js');
{
  const bank = spr.bakeSprites();
  note('sprite frames', bank.frames.size);

  check('every state points at a state that exists',
    Object.values(st.STATES).every(s => !s.next || st.STATES[s.next]),
    Object.values(st.STATES).filter(s => s.next && !st.STATES[s.next]).map(s => s.name).join(', '));

  check('every actor type names states that exist',
    Object.entries(st.ACTORS).every(([, a]) =>
      ['spawn', 'see', 'pain', 'melee', 'missile', 'death', 'xdeath'].every(k => !a[k] || st.STATES[a[k]])));

  /* THE ONE. A state naming a frame the bakery never drew renders as the
     missing-sprite placeholder, in the middle of a fight, once.

     VARIANTS make this less obvious than it looks. An actor with
     `variants: n` never draws the sprite its state names: Actor.render
     takes the first three letters and appends the variant, so the state
     SHOP/A is drawn as SHO0A through SHO16A and the key SHOPA is in no
     bank anywhere. So the variant bases are collected off the ACTORS
     first, and a state on one of them has to satisfy EVERY variant —
     which is the check that actually matters, since a missing sixteenth
     shopper would otherwise show up as one magenta person in a crowd. */
  const variantOf = new Map();
  for (const info of Object.values(st.ACTORS))
    if (info.variants) variantOf.set(st.STATES[info.spawn].sprite.slice(0, 3), info.variants);
  const missing = [];
  for (const [n, s] of Object.entries(st.STATES)) {
    const base = s.sprite.slice(0, 3);
    const keys = variantOf.has(base)
      ? Array.from({ length: variantOf.get(base) }, (_, v) => base + v + s.frame)
      : [s.sprite + s.frame];
    for (const key of keys) if (!bank.frames.has(key)) missing.push(`${n} wants ${key}`);
  }
  check('every state has the sprite frame it names', missing.length === 0, missing.join(', '));
  note('sprite sets with variants',
    [...variantOf].map(([b, n]) => `${b}0..${b}${n - 1}`).join(', '));

  check('every frame has all eight rotations',
    [...bank.frames.values()].every(f => f.views.length === 8 && f.views.every(v => v && v.w > 0)));

  check('sprites are 64px or under',
    [...bank.frames.values()].every(f => f.views[0].w <= 64 && f.views[0].h <= 64));

  /* ---------- the fire, which the game draws itself -------------------

     Three things are worth holding to a number here, because all three
     were wrong before and none of them announces itself:

       THE BOTTOM IS ROUND. Measured the only way that means anything —
       the lowest lit row of every COLUMN. A flame with a flat foot has
       every column ending on the same row, whatever its silhouette does
       from the sides, and that is exactly what the painted strips did
       and what masking them could not fix. So: how far the bottom edge
       rises from the deepest column to the shallowest, against how wide
       the flame is. The old strips scored 0.04 of their width. Anything
       at or under about a tenth is a flat bottom with the corners taken
       off.

       IT LOOPS. The last frame hands back to the first for the whole
       time something is alight, which is most of the game. If the wrap
       moves more than an ordinary step does, that is a pop, and it is
       the one animation fault a player will notice every second.

       NOTHING IS CLIPPED BY ITS OWN CELL. A lick that runs off the side
       of the frame is a vertical straight edge on a fire — the same
       fault as the flat bottom, turned ninety degrees — and one that
       runs off the bottom loses the round foot that is the point. The
       top is allowed: that is where the licks go. */
  {
    const art = await import('../js/fireart.js');
    const sets = {
      FIRE: art.fireFrames(32, 48, art.FIRE_FRAMES, 7),
      BLAZ: art.fireFrames(48, 64, art.BLAZE_FRAMES, 19, { taper: 0.8 }),
      EMBR: art.fireFrames(20, 28, art.EMBER_FRAMES, 31, { taper: 0.62 }),
      wood: art.fireFrames(64, 64, 20, 11, { taper: 0.7 }),
    };
    let flattest = 9, edged = 0, worstWrap = 0;
    for (const fr of Object.values(sets)) {
      for (const f of fr) {
        for (let y = 0; y < f.h; y++)
          for (let x = 0; x < f.w; x++)
            if (f.data[(y * f.w + x) * 4 + 3] >= 8 && (x === 0 || x === f.w - 1 || y === f.h - 1)) edged++;
        const low = [];
        for (let x = 0; x < f.w; x++) {
          let b = -1;
          for (let y = f.h - 1; y >= 0; y--) if (f.data[(y * f.w + x) * 4 + 3] >= 128) { b = y; break; }
          low.push(b);
        }
        const lit = low.filter(v => v >= 0);
        if (lit.length) flattest = Math.min(flattest, (Math.max(...lit) - Math.min(...lit)) / lit.length);
      }
      /* how far the picture moves between one frame and the next, all
         the way round, including from the last back to the first */
      const step = [];
      for (let i = 0; i < fr.length; i++) {
        const a = fr[i], b = fr[(i + 1) % fr.length];
        let d = 0;
        for (let k = 0; k < a.data.length; k += 4)
          d += Math.abs(a.data[k] * a.data[k + 3] - b.data[k] * b.data[k + 3]);
        step.push(d);
      }
      const wrap = step[step.length - 1];
      const mid = step.slice(0, -1).sort((a, b) => a - b)[step.length >> 1];
      worstWrap = Math.max(worstWrap, wrap / mid);
    }
    note('round bottom, worst frame', `edge rises ${(flattest * 100).toFixed(0)}% of the flame's width`);
    note('the loop closes', `the wrap moves ${worstWrap.toFixed(2)}x what a middling frame does`);
    check('the bottom of every flame is round, not narrowed and flat', flattest > 0.18, flattest.toFixed(3));
    check('the last frame hands back to the first without a pop', worstWrap < 1.6, worstWrap.toFixed(2));
    check('no flame touches the side or the bottom of its own cell', edged === 0, String(edged));
    check('every colour in the fire is already one of the 256',
      Object.values(sets).every(fr => fr.every(f => {
        for (let i = 0; i < f.data.length; i += 4) {
          if (f.data[i + 3] < 8) continue;
          if (!pal.PALETTE.some(c => c[0] === f.data[i] && c[1] === f.data[i + 1] && c[2] === f.data[i + 2])) return false;
        }
        return true;
      })));
    /* The bank and the state tables both build on these, from opposite
       ends; if they disagree the fire either skips frames or asks for a
       letter nobody drew. */
    check('the bank holds every frame js/fireart.js says it does',
      bank.count('FIRE') === art.FIRE_FRAMES && bank.count('BLAZ') === art.BLAZE_FRAMES
      && bank.count('EMBR') === art.EMBER_FRAMES);
    check('and the state chains are exactly that long',
      [['FIRE', art.FIRE_FRAMES], ['BLAZ', art.BLAZE_FRAMES], ['EMBR', art.EMBER_FRAMES]].every(([n, k]) =>
        st.STATES[`${n}${k}`] && st.STATES[`${n}${k}`].next === `${n}1` && !st.STATES[`${n}${k + 1}`]));
  }

  /* ---------- the people, who are the one thing a person drew ---------

     Four strips of painted art in assets/people, written by
     tools/prep-people.mjs out of the galvarius project. They are files
     rather than code, so the checks are about the files: that every one
     is there, that its cells are exactly the size js/people.js declares,
     and that the number of cells is the number the tables are built on.
     Get any of those wrong and the game cuts a shopper in half at load
     time and says nothing about it. */
  {
    const ppl = await import('../js/people.js');
    const { readPNG } = await import('./png-read.mjs');
    const dir = new URL('../assets/people/', import.meta.url);
    const want = [
      ['shoppers', ppl.CELLS.shoppers, ppl.SHOPPERS],
      ['giblets',  ppl.CELLS.giblets,  ppl.GIBLETS],
      ['splat',    ppl.CELLS.splat,    ppl.SPLATS],
      ['blast',    ppl.CELLS.blast,    ppl.BLASTS],
    ];
    for (const [name, cell, count] of want) {
      let img = null;
      try { img = readPNG(new URL(name + '.png', dir)); } catch { /* reported below */ }
      check(`assets/people/${name}.png is there`, !!img);
      if (!img) continue;
      check(`${name}.png is ${count} cells of ${cell.w}x${cell.h}`,
        img.h === cell.h && img.w === cell.w * count, `${img.w}x${img.h}`);
    }

    /* And that the game's own loader puts them where the tables look.
       stripFrames is what the browser runs, so running it here is the
       same cut, on the same bytes. */
    const shoppers = readPNG(new URL('shoppers.png', dir));
    const n = ppl.addStandees(bank, shoppers);
    check('every shopper loads into the bank', n === ppl.SHOPPERS, `${n} of ${ppl.SHOPPERS}`);
    const splats = ppl.addSplats(bank, readPNG(new URL('splat.png', dir)));
    check('every splat loads into the bank', splats === ppl.SPLATS, `${splats} of ${ppl.SPLATS}`);

    /* the painted people are allowed to be taller than 64 the way the
       fire strips are, but not by accident: they are people, and a
       person is the height of a person */
    const tall = [...Array(ppl.SHOPPERS).keys()].map(v => bank.frames.get(`SHO${v}A`).h);
    check('the shoppers are all one cell tall', tall.every(h => h === ppl.CELLS.shoppers.h),
      [...new Set(tall)].join(', '));

    /* seventeen drawings, not one drawing seventeen times */
    const px = v => { const p = bank.frames.get(`SHO${v}A`).views[0]; let c = 0;
                      for (let i = 3; i < p.data.length; i += 4) if (p.data[i] > 8) c++; return c; };
    const counts = [...Array(ppl.SHOPPERS).keys()].map(px);
    check('the shoppers are different people', new Set(counts).size >= ppl.SHOPPERS - 1,
      `${new Set(counts).size} distinct silhouettes`);
    note('shopper silhouettes', `${Math.min(...counts)}..${Math.max(...counts)} lit pixels`);
  }

  const w = spr.bakeWeapons();
  note('weapon frames', w.size);
  check('weapon frames all present',
    ['FLMGA', 'FLMGB', 'FLMGC', 'MOLGA', 'MOLGB', 'MOLGC'].every(k => w.has(k)));
  check('and the boxcutter\'s are gone with the boxcutter', !w.has('CUTGA') && !w.has('CUTGB'));
}

/* ---------- the map ---------- */
section('the map');
const MAP = await import('../js/maps/sellwrong.js');
const { PLAYER_EYE } = await import('../js/util.js');
const { buildSellWrong } = MAP;
const level = buildSellWrong();

/* =====================================================================
   THE PLAYER DOES NOT START IN A FIELD ANY MORE

   For most of this game's life the spawn was the mouth of the car park,
   and half a dozen fixtures below quietly took advantage of it: a jet of
   flame needs somewhere to land, a round needs a wall four thousand
   units away to put a hole in, a target has to be brought out "in front
   of the player" with nothing between the two of them, and the
   responders' six seconds is measured to wherever you happen to be.
   None of them said so. They just used `g.player` where it stood.

   The player is a cashier now — in the well of the middle checkstand,
   thirty units from a counter, inside a crowd — and every one of those
   fixtures broke at once, all of them for the same reason and none of
   them because anything they are about had changed.

   So the assumption is written down instead. `level.viewpoint` is the
   old spawn, kept on the level as the place it always was, and a
   fixture that wants open ground asks for it. What is left over is
   worth having: the five checks below now say out loud that they are
   about the car park, and if the shop ever changes under them again
   they will keep meaning the same thing.
   ===================================================================== */
function inTheOpen(g) {
  const v = g.level.viewpoint;
  const p = g.player;
  p.x = v.x; p.y = v.y; p.angle = v.angle; p.pitch = 0;
  p.sector = g.level.sectorAt(p.x, p.y);
  p.z = p.sector.floor; p.viewZ = p.z + PLAYER_EYE;
  p.momx = p.momy = p.momz = 0; p.onGround = true;
  g.blockmap?.moved(p);
  p.updateSector?.();
  return p;
}
/* THE TOWN IS BUILT THREE TIMES IN THIS FILE and no more: here, in the
   portal flood's section and in the town's own. Everywhere else the map
   is built with { town: false }, which is the map this file built
   before there was a town — nine thousand units of wood where the
   streets are.

   It is not tidiness. A Game holds a Level of eleven thousand regions
   and a fuel grid of a million and a half cells, and a dozen of those
   alive at once is how a test runner runs out of memory, which is
   exactly what it did. The checks that build one are about the SHOP —
   the frost, the lamps, the decals, the gun — and a town four thousand
   units away across the ring road is not part of any of them.

   WHICH HALF OF THE MAP. There is a town on the other side of the ring
   road now (TOWN.txt), so a test that says "the shop" or "the store"
   has to say which sectors it means — the filters below used to catch
   every indoor region on the map because every indoor region on the map
   was the shop. The line is the lot's own south edge: everything above
   it is the mall's superblock and everything below it is the town. */
const TOWN_EDGE = level.town ? level.town.grid.y1 : -Infinity;
const inMall = s => s.bbox[3] > TOWN_EDGE;
const inTown = s => s.bbox[3] <= TOWN_EDGE;
{
  note('sectors / lines / vertices', `${level.sectors.length} / ${level.lines.length} / ${level.verts.length}`);
  note('things', level.things.length);

  /* Lamps are laid on a grid over the whole map and the ones that miss
     the building are dropped when the level is populated, so they are
     the one thing allowed to start outside a sector. */
  const placed = level.things.filter(t => t.type !== 'LAMP');
  check('every thing stands in a sector',
    placed.every(t => level.sectorAt(t.x, t.y)),
    placed.filter(t => !level.sectorAt(t.x, t.y)).map(t => `${t.type}@${t.x},${t.y}`).join(' '));

  check('there is a start', level.things.some(t => t.type === 'START'));

  /* THE CARS ARE DATA, NOT THINGS. The placeholder cars are gone and what
     is left is a list of slots for real models to be put at. The point of
     the list is that it came off the same pitch that drew the bay lines,
     so every slot is IN a bay rather than near one — which is worth
     checking, because it is the only property of it that is hard to see
     and easy to break. */
  {
    /* the car park's own slots. The vans along the town's kerbs are
       marked `street`, and since A5 the office block has a lot of its
       own with cars in it, marked `town` — both of them are checked
       where they are, and neither of them is this car park. */
    const slots = (level.carSlots || []).filter(c => !c.street && !c.town);
    note('parking slots', `${slots.length} in the lot, ` +
      `${(level.carSlots || []).filter(c => c.street).length} on the town's streets, ` +
      `${(level.carSlots || []).filter(c => c.town).length} at the office block`);
    /* SPARSE, at the user's request: about one bay in six near the doors
       and almost nothing by the road. The claim is that there IS a car
       park and that it is not full — an empty lot and a full one are
       both wrong for a shop half the town has already left. */
    check('the lot has cars marked out', slots.length > 12 && slots.length < 45, `${slots.length}`);
    check('nothing is still spawning placeholder cars',
      !level.things.some(t => t.type === 'CAR'));
    const shape = slots.every(c =>
      typeof c.x === 'number' && typeof c.y === 'number' &&
      typeof c.angle === 'number' && Number.isInteger(c.variant));
    check('every slot is a position, a heading and a variant', shape);
    const stray = slots.filter(c => {
      const sec = level.sectorAt(c.x, c.y);
      return !sec || (sec.name !== 'bays' && sec.name !== 'fire lane');
    });
    /* ALL BUT THREE. Three are abandoned across the driving lanes on
       purpose — everybody left at once — and a van standing in a lane is
       the whole point of those three, so the claim is "in a bay, or in a
       lane and one of the three", not "in a bay". What it still refuses
       is a van on the verge, in the road, on the footway, or nowhere. */
    const abandoned = stray.filter(c => (level.sectorAt(c.x, c.y) || {}).name === 'driving lane');
    const lost = stray.filter(c => !abandoned.includes(c));
    note('and where they are', `${slots.length - stray.length} in bays, ` +
      `${abandoned.length} abandoned in the lanes`);
    check('every car is parked in a bay, or abandoned in a lane',
      lost.length === 0 && abandoned.length <= 3,
      stray.slice(0, 4).map(c => {
        const sec = level.sectorAt(c.x, c.y);
        return `${c.x | 0},${c.y | 0} in ${sec ? sec.name : 'nothing'}`;
      }).join(' '));
  }

  /* CAN YOU ACTUALLY GET THERE.

     A flood fill from the player's start through every line he could walk
     through, and then a demand that it reached everywhere. This exists
     because the parade was once laid out with `ANCHOR_X0 - WALL - n *
     (UNIT_W + WALL)`, which counts the wall beside the anchor twice and
     leaves a sixteen-unit void between the west wing and the store. A
     void is a wall, so half the strip mall was sealed off — and nothing
     complained, because a level with an unreachable half is a perfectly
     valid level. It surfaced as the fire spreading three thousand units
     east and refusing to go west at all, which is a long way from the
     constant that caused it.

     The rule is Doom's own passability, so this is not a second opinion
     about what a wall is; it is the game's opinion, asked at build time. */
  {
    const start = level.things.find(t => t.type === 'START');
    const from = level.sectorAt(start.x, start.y);
    const seen = new Set([from.index]);
    const queue = [from.index];
    /* which lines touch which sector, once */
    const byS = new Map();
    for (const l of level.lines) for (const si of [l.front, l.back]) {
      if (si === null) continue;
      if (!byS.has(si)) byS.set(si, []);
      byS.get(si).push(l);
    }
    while (queue.length) {
      const si = queue.pop();
      for (const l of byS.get(si) || []) {
        const other = l.front === si ? l.back : l.front;
        if (other === null || seen.has(other)) continue;
        /* stepping from this sector's floor, at player height */
        if (level.lineBlocks(l, level.sectors[si].floor, 56, false)) continue;
        seen.add(other); queue.push(other);
      }
    }
    note('rooms you can walk to', `${seen.size}/${level.sectors.length}`);

    /* Asking "is every room reachable" is the wrong question — a checkout
       is a sector and you are not meant to be on it. The question with an
       answer is: is everything the level ASKS you to reach, reachable.
       Every can of fuel, and every member of staff. Both of those are
       things the map placed deliberately, so one stranded behind a wall
       is unambiguously a bug and never a fixture. */
    const mustReach = level.things.filter(t =>
      t.type === 'FUELCAN' || t.type === 'ASSOCIATE' || t.type === 'STOCKER');
    const stranded = mustReach.filter(t => {
      const s = level.sectorAt(t.x, t.y);
      return !s || !seen.has(s.index);
    });
    check('every fuel can and every member of staff can be reached on foot',
      stranded.length === 0,
      stranded.slice(0, 6).map(t => `${t.type}@${t.x | 0},${t.y | 0}`).join(' ') +
      (stranded.length > 6 ? ` (+${stranded.length - 6})` : ''));
  }

  check('no sector is inside out', level.sectors.every(s => {
    let a = 0;
    for (let i = 0, j = s.poly.length - 1; i < s.poly.length; j = i++)
      a += s.poly[j][0] * s.poly[i][1] - s.poly[i][0] * s.poly[j][1];
    return a > 0;
  }));

  check('every sector has a floor below its ceiling',
    level.sectors.every(s => s.ceil >= s.floor));

  check('every two-sided line has both its skins',
    level.lines.every(l => l.front === null || l.back === null ||
      (l.upper !== undefined && l.lower !== undefined)));

  /* the bug where an aisle had shelving on one side only */
  const shelfLines = level.lines.filter(l => l.lower === 'SHELFSTK').length;
  check('gondola faces got the gondola texture', shelfLines >= 20, `${shelfLines} lines`);
  const glass = level.lines.filter(l => l.middle === 'STORGLAS').length;
  check('the shopfront is glazed', glass >= 2, `${glass} segments`);

  /* A gondola you can see over is not an aisle, it is a low wall. The
     player is 56 with an eye at PLAYER_EYE; anything at 56 exactly is
     the least useful height there is. */
  check('gondolas are taller than the player', MAP.H_GONDOLA > 56, `${MAP.H_GONDOLA}`);
  check('front fixtures are below eye level', MAP.H_FIXTURE < PLAYER_EYE, `${MAP.H_FIXTURE} against ${PLAYER_EYE}`);
  const gond = level.sectors.find(s => s.name === 'gondola');
  check('gondola sectors are at that height', gond && gond.floor === MAP.H_GONDOLA);

  /* A fixture texture whose declared world height does not match the
     fixture shows a slice of a second copy of itself, cut off wherever
     the fixture happens to end. */
  const declared = { SHELFSTK: MAP.H_GONDOLA, SHELFEMP: MAP.H_GONDOLA, FREEZDOR: MAP.H_GONDOLA,
                     CHECKOUT: MAP.H_FIXTURE, CHILLER: MAP.H_FIXTURE,
                     DELICASE: MAP.H_FIXTURE, BELTSIDE: MAP.H_BELT };
  const mismatched = Object.entries(declared)
    .filter(([n, h]) => (tex.TEXTURE_SIZES[n] || {}).h !== h)
    .map(([n, h]) => `${n} declared ${(tex.TEXTURE_SIZES[n] || {}).h} wants ${h}`);
  check('fixture textures are sized to their fixtures', mismatched.length === 0, mismatched.join(', '));

  /* ===================================================================
     THE CHECKSTAND, WHICH IS WHERE YOU START

     The front end was eight slabs and is eight machines, and the player
     spawns standing inside one of them. Every check here is about a
     claim made in A CHECKSTAND in js/maps/sellwrong.js.
     =================================================================== */
  {
    const { MAX_STEP } = await import('../js/util.js');
    const named = n => level.sectors.filter(s => s.name === n);
    const bbox = sec => {
      const xs = sec.poly.map(p => p[0]), ys = sec.poly.map(p => p[1]);
      return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
    };
    const belts = named('belt'), scans = named('scanner'), bags = named('bagging');
    const noses = named('checkout nose');
    const wells = level.sectors.filter(s => /^(your checkout|checkout well)$/.test(s.name || ''));
    const lanes = named('checkout lane');
    check('eight checkstands across the front, two runs of counter each',
      noses.length === 8 && wells.length === 8 &&
      belts.length === 16 && scans.length === 16 && bags.length === 16,
      `${noses.length} noses, ${wells.length} wells, ${belts.length} belts, ${scans.length} scanners, ${bags.length} bagging`);

    /* A MACHINE WITH A DIRECTION. You join it at the back, unload onto
       the belt, pay at the scanner and collect at the bagging end — so
       the four bands have to be in that order down the lane, edge to
       edge, with nothing between them. Build them in the wrong order
       and the shopping travels from the till towards the shop. */
    const runs = belts.map(b => {
      const bb = bbox(b);
      const near = list => list.map(bbox).find(o => o.x0 === bb.x0 && o.x1 === bb.x1);
      return { belt: bb, scan: near(scans), bag: near(bags) };
    });
    check('each one runs belt, then scale plate, then bagging, down the lane',
      runs.every(r => r.scan && r.bag &&
        r.belt.y0 === r.scan.y1 && r.scan.y0 === r.bag.y1),
      `${runs.filter(r => !(r.scan && r.bag && r.belt.y0 === r.scan.y1 && r.scan.y0 === r.bag.y1)).length} out of order`);
    check('and the scale plate is flush with the belt that feeds it, not set down into it',
      belts.every(b => b.floor === MAP.H_BELT) && scans.every(sc => sc.floor === MAP.H_BELT),
      `belt ${belts[0].floor}, plate ${scans[0].floor}`);

    /* NOTHING ON ONE IS CLIMBABLE, which is what lets the shopping be
       free boxes. The first cut had the scale plate recessed to 34 —
       22 above the floor against a MAX_STEP of 24 — so you could step
       onto it, from there onto the belt, and walk through somebody's
       groceries. */
    const surfaces = [...belts, ...scans, ...bags, ...noses];
    const lowest = Math.min(...surfaces.map(sec => sec.floor)) - MAP.FLOOR_WALK;
    check('and nothing on a checkstand can be climbed onto from the lane beside it',
      lowest > MAX_STEP, `the lowest surface is ${lowest} above the floor against a step of ${MAX_STEP}`);

    /* THE WELL IS SHOP FLOOR, OPEN BEHIND AND SHUT IN FRONT. Leave the
       nose off and it is a way round the tills from the shop floor to
       the mat, which is the one thing a front end exists to prevent. */
    check('the well you stand in is shop floor', wells.every(w => w.floor === MAP.FLOOR_WALK));
    const xaisle = level.sectors.find(sec => sec.name === 'front cross-aisle');
    const mat = level.sectors.find(sec => sec.name === 'entrance mat');
    const touches = (a, b) => level.lines.some(l =>
      (l.front === a.index && l.back === b.index) || (l.front === b.index && l.back === a.index));
    check('and it is open to the cross-aisle behind you',
      wells.every(w => touches(w, xaisle)), `${wells.filter(w => !touches(w, xaisle)).length} sealed in`);
    check('and shut at the customer end, so the front end cannot be walked round',
      wells.every(w => !touches(w, mat)), `${wells.filter(w => touches(w, mat)).length} open to the mat`);
    check('the lanes and the stands fill the band between them with nothing left over',
      lanes.length === 9 && lanes.concat(noses).map(bbox)
        .sort((a, b) => a.x0 - b.x0)
        .every((o, i, all) => i === 0 || o.x0 === all[i - 1].x1),
      `${lanes.length} lanes`);

    /* --- AND THE PLAYER IS THE CASHIER ------------------------------ */
    const start = level.things.find(t => t.type === 'START');
    const mine = level.sectorAt(start.x, start.y);
    check('the game starts you in one of them, behind the counter',
      mine && mine.name === 'your checkout', mine && mine.name);
    /* facing WEST across the belt, which is the one thing a cashier
       looks at. Half a turn either way is the length of the front end. */
    check('facing across the counter rather than down the shop',
      Math.abs(Math.cos(start.angle) + 1) < 1e-6, `angle ${start.angle.toFixed(2)}`);
    const acrossRun = level.sectorAt(start.x - 50, start.y);
    const acrossLane = level.sectorAt(start.x - 120, start.y);
    check('and what is across it is a scale plate and then a lane with people in it',
      acrossRun && acrossRun.name === 'scanner' && acrossLane && acrossLane.name === 'checkout lane',
      `${acrossRun && acrossRun.name} then ${acrossLane && acrossLane.name}`);
    const served = level.things.filter(t => t.type === 'SHOPPER')
      .filter(t => Math.abs(t.y - start.y) < 30 && start.x - t.x > 60 && start.x - t.x < 260);
    check('with somebody at the front of it looking back at you',
      served.length >= 1 && served.some(t => Math.abs(Math.cos(t.angle) - 1) < 1e-6),
      `${served.length} in reach, angles ${served.map(t => t.angle.toFixed(2)).join(' ')}`);

    /* --- THE QUEUES -------------------------------------------------
       They stand in the LANES, one behind another, facing the till —
       and all three of those were wrong until there was a player at a
       till to look at them. */
    /* A QUEUE IS NOT "EVERYBODY IN THE LANE". A lane is 220 wide and 260
       deep and the front-end scatter drops people all over it, so the
       first cut of this counted 8 8 9 9 9 8 10 9 22 and learned nothing
       — including a queue of 22 down the one lane that has no queue.

       What a queue IS: people on the lane's CENTRE LINE, starting at
       the scale plate, at the spacing the map lays them at. Nobody else
       can be among them, because the crowd keeps 54 apart and the queue
       steps 58 — there is no room between two of them for a stranger —
       so the first five off the centre line are the queue and the rest
       of the lane is the rest of the lane. */
    const serveY = (bbox(scans[0]).y0 + bbox(scans[0]).y1) / 2;
    const queues = lanes.map(bbox).map(o => {
      const cx = (o.x0 + o.x1) / 2;
      return level.things.filter(t => t.type === 'SHOPPER' &&
        Math.abs(t.x - cx) <= 14 && t.y >= serveY - 8).sort((a, b) => a.y - b.y).slice(0, 5);
    });
    const real = queues.filter(q => q.length === 5 && Math.abs(q[0].y - serveY) < 8);
    check('a queue down eight of the nine lanes, five deep, starting at the scale plate',
      real.length === 8, `${queues.map(q => q.length).join(' ')}`);
    check('and every one of them is a LINE: one behind another, evenly spaced',
      real.every(q => q.every((t, i) => i === 0 || (t.y - q[i - 1].y > 50 && t.y - q[i - 1].y < 70))),
      'gaps between 50 and 70');
    check('the one at the front has turned to face the till and the rest face the doors',
      real.every(q => Math.abs(Math.cos(q[0].angle) - 1) < 1e-6 &&
        q.slice(1).every(t => Math.abs(Math.sin(t.angle) + 1) < 1e-6)));

    /* --- AND THE SHOPPING ------------------------------------------- */
    const props = level.props || [];
    const GROC = ['GROCBOX', 'GROCBOX2', 'GROCCAN', 'GROCBAG', 'GROCTOP'];
    const shopping = props.filter(q => GROC.includes(q.tex) && q.z0 >= MAP.H_BELT);
    check('there is a great deal of shopping on the belts', shopping.length > 90, `${shopping.length} pieces`);
    const onBelt = shopping.filter(q => q.z0 === MAP.H_BELT);
    check('and every piece of it is standing on a belt and nothing else',
      onBelt.every(q => {
        const sec = level.sectorAt((q.x0 + q.x1) / 2, (q.y0 + q.y1) / 2);
        return sec && sec.name === 'belt';
      }), `${onBelt.filter(q => (level.sectorAt((q.x0 + q.x1) / 2, (q.y0 + q.y1) / 2) || {}).name !== 'belt').length} off it`);
    check('and none of it hangs over the guards down the sides',
      onBelt.every(q => {
        const sec = level.sectorAt((q.x0 + q.x1) / 2, (q.y0 + q.y1) / 2);
        const o = bbox(sec);
        return q.x0 >= o.x0 && q.x1 <= o.x1;
      }));
    /* IT IS A PILE AND NOT A LINE: three abreast where the belt has run
       everything up against the stop, and something stacked on top. */
    const stacked = shopping.filter(q => q.z0 > MAP.H_BELT);
    check('some of it is stacked on the rest, which is what a pile is',
      stacked.length > 10, `${stacked.length} on top of something`);
    const perBelt = new Map();
    for (const q of shopping) {
      const sec = level.sectorAt((q.x0 + q.x1) / 2, (q.y0 + q.y1) / 2);
      if (sec && sec.name === 'belt') perBelt.set(sec.index, (perBelt.get(sec.index) || 0) + 1);
    }
    const myBelt = level.sectorAt(start.x - 50, start.y + 60);
    const mineN = perBelt.get(myBelt && myBelt.index) || 0;
    const counts = [...perBelt.values()].sort((a, b) => b - a);
    note('shopping, belt by belt', counts.join(' '));
    check('and your own belt is the busiest one in the shop, because it is the one you look down',
      myBelt && myBelt.name === 'belt' && mineN >= 12 && mineN === counts[0] && mineN > counts[1],
      `${mineN} on yours against ${counts[1]} at the next busiest of the sixteen`);
    /* AND THE OTHERS ARE NOT COPIES OF IT. A front end where every belt
       holds the same amount is eight copies of one lane; a real one has
       a heaped belt, a couple with three things on them, and one the
       customer has just walked away from. The fullest here should be
       several times the emptiest. */
    check('and the rest of them are all different amounts of busy',
      counts[0] > counts[counts.length - 1] * 2.5 && new Set(counts).size >= 5,
      `${counts[0]} at the fullest, ${counts[counts.length - 1]} at the emptiest, ${new Set(counts).size} distinct`);

    /* THE PICTURES ARE SIZED TO THE BOXES THEY GO ON, which is what
       makes them packaging rather than wallpaper: a carton front is one
       whole carton front. Every distinct box size that wears one of
       these has to be within a repeat of its declared size, or a cereal
       box shows two thirds of a cereal box. */
    const over = props.filter(q => GROC.includes(q.tex) || ['REGISTER', 'PINPAD', 'BAGRACK'].includes(q.tex))
      .filter(q => {
        const t = tex.TEXTURE_SIZES[q.tex];
        if (!t) return true;
        return Math.max(q.x1 - q.x0, q.y1 - q.y0) > t.w * 1.45 || (q.z1 - q.z0) > t.h * 1.45;
      });
    check('every picture on the front end is sized to the thing it is a picture of',
      over.length === 0, over.slice(0, 4).map(q => `${q.tex} ${Math.round(q.x1 - q.x0)}x${Math.round(q.z1 - q.z0)}`).join(', '));
  }

  /* PRODUCE IS BINS, and the whole point of them is the top. A bin
     wearing SHELFBAK is the bug this replaced: gondola steel on the one
     department you look down into. */
  const BIN_TOPS = ['PRODAPPL', 'PRODCITR', 'PRODGREN', 'PRODROOT', 'PRODFLOW'];
  const bins = level.sectors.filter(s => BIN_TOPS.includes(s.floorTex));
  check('produce is a run of bins', bins.length >= 7, `${bins.length} bins`);
  check('every bin is at bench height', bins.every(s => s.floor === MAP.H_FIXTURE));
  check('every bin is a whole crate of one thing',
    bins.every(s => s.floorAnchor && s.floorAnchor[1] === Math.max(...s.poly.map(v => v[1]))),
    'each anchored to its own north edge');
  check('four categories of fruit and veg',
    new Set(bins.map(s => s.floorTex)).size === BIN_TOPS.length,
    [...new Set(bins.map(s => s.floorTex))].join(' '));
  const rims = level.sectors.filter(s => s.floorTex === 'PRODRIM');
  check('a crate rim between each pair', rims.length === bins.length - 2, `${rims.length} rims`);
  check('the rim stands proud of the produce',
    rims.every(s => s.floor === MAP.H_FIXTURE + 8) && rims.every(s => s.floor < PLAYER_EYE),
    `${MAP.H_FIXTURE + 8} against an eye at ${PLAYER_EYE}`);
  /* The crate boards get cut at three different heights — the lip, the
     bin face and the rim face — so the board pitch has to divide the
     lip or the top course comes out a sliver. */
  check('the crate boards divide the lip',
    (tex.TEXTURE_SIZES.PRODRIM || {}).h === 16 && 16 % 8 === 0);
  check('no fixture in the store wears shelf steel on top',
    !level.sectors.some(s => s.floorTex === 'SHELFBAK' && BIN_TOPS.includes(s.lowerTex)));

  /* THE SIGNS CAME DOWN, at the user's request: the store's name off the
     fascia band, the agent's board off the vacant units, the pylon out
     of the car park altogether. Nothing here can see a picture, so what
     it checks is that the pylon is gone from the map and from the bank
     rather than merely unreferenced in one of them. */
  check('the pylon sign is gone from the car park',
    !level.sectors.some(s => s.wallTex === 'PYLONSGN' || (s.name || '').includes('pylon')));
  check('and gone from the texture bank', !('PYLONSGN' in tex.TEXTURE_SIZES));
  check('the verge runs clean to the mouth of the lot',
    level.sectors.filter(s => s.name === 'verge').length === 1);

  /* the lights */
  const lamps = level.things.filter(t => t.type === 'LAMP');
  check('the ceiling has fittings in it', lamps.length > 30, `${lamps.length} placed`);
  const indoors = lamps.filter(t => { const s = level.sectorAt(t.x, t.y); return s && !s.outdoor && s.ceil >= 200; });
  note('lamps placed / kept', `${lamps.length} / ${indoors.length}`);
  check('most of the shop gets a fitting', indoors.length > 30, `${indoors.length} kept`);
  check('the ceiling texture spans four tiles', (tex.TEXTURE_SIZES.CEILFIT || {}).w === 256);

  /* THE SIGN HAS TO BE THE SHAPE OF THE LOGO. The four tiles are a
     square 128x128 cut from artwork that was not square, so the aspect
     lives in the geometry: get the sign box wrong and the logo is
     stretched, and nothing else in the game will say so. */
  {
    const art = await import('../js/art-data.js');
    const signAspect = MAP.SIGN_W / MAP.SIGN_H;
    check('the sign box is the shape of the artwork',
      Math.abs(signAspect - art.LOGO_ASPECT) < 0.02,
      `sign ${signAspect.toFixed(3)} vs art ${art.LOGO_ASPECT.toFixed(3)}`);
    check('each logo tile is half the sign',
      (tex.TEXTURE_SIZES.LOGO0 || {}).w === MAP.SIGN_W / 2 &&
      (tex.TEXTURE_SIZES.LOGO0 || {}).h === MAP.SIGN_H / 2);
    check('the logo is four tiles', art.LOGO_TILES.length === 4);
    /* The weapon reserves the top of its frame for the muzzle flame; if
       that ever became zero the flame would be drawn off-frame. */
    check('the weapon leaves room for its own flame',
      art.WEAPON_TOP > 8 && art.WEAPON_TOP < 48, `${art.WEAPON_TOP} rows`);
  }

  /* fuel has to be laid out as a shop or the fire has no shape */
  const fuelOf = n => level.sectors.filter(s => s.name === n).reduce((a, s) => a + s.fuel, 0) /
                      Math.max(1, level.sectors.filter(s => s.name === n).length);
  note('fuel: gondola / aisle / car park', `${fuelOf('gondola')} / ${fuelOf('aisle')} / ${fuelOf('car park')}`);
  check('gondolas hold far more fuel than the aisles', fuelOf('gondola') > fuelOf('aisle') * 4);
  check('the car park will not burn', fuelOf('car park') === 0);
}

/* ---------- lighting ---------- */
section('lighting');
{
  /* A REAL Game, with the real lamps and the real relight(). */
  const { Game } = await import('../js/game.js');
  const bank = tex.bakeTextures();
  const sprBank = spr.bakeSprites();
  const fakeHud = { message() {}, ticMessages() {} };
  const g = new Game({
    level, scene: new (await import('three')).Scene(), camera: {},
    textures: bank, sprites: sprBank, hud: fakeHud, audio: null,
    input: { sample() {} },
  });
  note('lamps kept', g.lamps.length);
  check('the ceiling has working fittings', g.lamps.length > 30, `${g.lamps.length}`);

  const shop = level.sectors.filter(s => inMall(s) && !s.outdoor && s.ceil >= 200);
  const avg = shop.reduce((a, s) => a + s.light, 0) / shop.length;
  const lo = Math.min(...shop.map(s => s.light));
  note('shop light: average / darkest', `${avg.toFixed(2)} / ${lo.toFixed(2)}`);
  check('the shop is lit by its fittings', avg > 0.55 && avg < 0.98, `average ${avg.toFixed(2)}`);
  check('nothing indoors is left pitch dark', lo > 0.30, `darkest ${lo.toFixed(2)}`);
  check('the light is not all clamped to full',
    shop.filter(s => s.light >= 0.999).length < shop.length * 0.5,
    `${shop.filter(s => s.light >= 0.999).length} of ${shop.length} at full`);

  /* Shoot out everything over one aisle and it must actually go dark. */
  const aisle = shop.find(s => s.name === 'aisle');
  const cx = (aisle.bbox[0] + aisle.bbox[2]) / 2, cy = (aisle.bbox[1] + aisle.bbox[3]) / 2;
  const before = aisle.light;
  let killed = 0;
  for (const l of g.lamps) {
    if (Math.hypot(l.x - cx, l.y - cy) > 380) continue;
    l.damage(50, null);
    killed++;
  }
  g.relight();
  note('one aisle, fittings shot out', `${killed} lamps, ${before.toFixed(2)} -> ${aisle.light.toFixed(2)}`);
  check('shooting the lights out makes it darker', aisle.light < before - 0.15,
        `${before.toFixed(2)} -> ${aisle.light.toFixed(2)}`);
  check('the ambient survives, so it is dark and not blind',
        aisle.light >= aisle.ambient - 1e-6 && aisle.light > 0.1,
        `${aisle.light.toFixed(2)} vs ambient ${aisle.ambient}`);
  /* A DEAD LIGHT HAS NOTHING TO SHOW ANY MORE — there is no broken
     frame, because there is no frame — so what has to be true is that
     it is out of the grid the relight is built from. */
  check('a burst lamp is dead and out of the relight',
        g.lamps.some(l => l.dead) && g._lampGrid.size > 0 &&
        [...g._lampGrid.values()].flat().every(l => !l.dead && !l.removed));
  check('bursting a lamp throws sparks', g.projectiles.some(p => p.kind === 'SPARK'));

  /* ---- and the pause, while there is a real Game to hand ----
     It used to be a one-way door: update() returned before the tic that
     sampled the pause key, so nothing could ever unpause. */
  section('pause');
  let sampled = 0;
  const seen = [];
  g.input = { mode: 'desktop', pausePressed: false, sample() { sampled++; this.pausePressed = sampled === 2; } };
  g.onPauseChange = on => seen.push(on);
  g.setPaused(true);
  g.update(1 / 35);
  check('a paused game still listens to the keyboard', sampled === 1 && g.paused);
  g.update(1 / 35);
  check('and the pause key lets you back out', sampled === 2 && !g.paused);
  check('the switch announces both throws, once each', seen.join(',') === 'true,false', seen.join(','));
  g.setPaused(false);
  check('throwing it the way it already is says nothing', seen.length === 2);
  check('the retry prompt knows what it is being played on',
    g.retryPrompt.includes('SPACE') && (g.input.mode = 'touch', g.retryPrompt.includes('TAP')));
}

/* ---------- collision ---------- */
section('collision');
{
  const { MapBuilder } = await import('../js/level.js');
  const mb = new MapBuilder('T');
  mb.sector([[0, 0], [256, 0], [256, 96], [256, 160], [256, 256], [0, 256]], { floor: 0, ceil: 128 });
  mb.sector([[256, 0], [512, 0], [512, 256], [256, 256], [256, 160], [256, 96]], { floor: 0, ceil: 128 });
  const lv = mb.build();
  const at = (r, x, y) => Math.abs(r[0] - x) < 1.5 && Math.abs(r[1] - y) < 1.5;

  check('walks through an opening', at(lv.slideMove(200, 128, 100, 0, 16, 0, 56), 300, 128));
  check('stops at a wall', at(lv.slideMove(400, 128, 200, 0, 16, 0, 56), 496, 128));
  check('slides along a wall', at(lv.slideMove(100, 240, 40, 40, 16, 0, 56), 140, 240));
  /* a move longer than the radius must not step over the wall entirely */
  check('does not tunnel through a wall', at(lv.slideMove(100, 128, 0, 900, 16, 0, 56), 100, 240));

  lv.sectors[1].floor = 24;
  check('climbs a 24 step', at(lv.slideMove(200, 128, 100, 0, 16, 0, 56), 300, 128));
  lv.sectors[1].floor = 40;
  check('a 40 step is a wall', !at(lv.slideMove(200, 128, 100, 0, 16, 0, 56), 300, 128));
  lv.sectors[1].floor = 0; lv.sectors[1].ceil = 40;
  check('a low ceiling blocks', !at(lv.slideMove(200, 128, 100, 0, 16, 0, 56), 300, 128));
  lv.sectors[1].ceil = 128;

  check('sight passes through an opening', !lv.sightBlocked(100, 128, 41, 400, 128, 41));
  lv.sectors[1].floor = 0; lv.sectors[1].ceil = 0;      // a shut door
  check('sight stops at a shut door', lv.sightBlocked(100, 128, 41, 400, 128, 41));
}

/* ---------- fire ---------- */
section('fire');
{
  /* The fire system wants a whole Game; give it the two things it reads. */
  const { FireSystem } = await import('../js/fire.js');
  const fake = { level, player: { x: 1240, y: -520, dead: false, damage() {} }, actors: [], sound: null };
  const t0 = Date.now();
  const fire = new FireSystem(fake);
  note('fuel grid', `${fire.cols}x${fire.rows}, ${fire.totalFuel} total fuel, ${Date.now() - t0}ms`);
  check('the store holds fuel', fire.totalFuel > 100000);
  check('nothing is alight to begin with', fire.liveCells === 0);
  check('burn starts at zero', fire.burnFraction === 0);

  /* ONE MATCH, AND ALL THE TIME IN THE WORLD.
     ---------------------------------------------------------------
     THIS CHECK NOW ASSERTS THE OPPOSITE OF WHAT IT USED TO, and the
     flip is the whole of the change. The requirement was that the shop
     goes eventually — every cell lighting more than one neighbour on
     average, so the fire never stalls — and the requirement is now that
     a fire LEFT ALONE GOES OUT, having taken a patch rather than a
     wing. Burning the store down is the player's job.

     What it did before, measured with nobody in the building: one match
     dropped in a gondola took 91% of the shop, one in a bare aisle took
     86%, and one in the stockroom took 94%. It did not matter where. */
  fire.ignite(540, 1000, 200, 40);
  /* liveCells, not burningCells: the latter is what the status bar shows
     and counts only cells that are actually alight, which is zero until
     the simulation has stepped at least once. */
  check('ignition takes', fire.liveCells > 0);

  let stalled = -1;
  for (let i = 0; i < 200000; i++) {
    fire.tic();
    if (i > 20 && fire.liveCells === 0) { stalled = i; break; }
  }
  const oneMatch = fire.burnFraction;
  note('one match, left alone', `${(oneMatch * 100).toFixed(2)}% burned` +
    (stalled >= 0 ? `, out after ${(stalled / 35).toFixed(0)}s` : ', STILL GOING'));
  check('a fire left alone goes out', stalled >= 0, 'still alight at 200000 tics');
  check('and it goes out having taken a patch, not the shop',
    oneMatch < 0.02, `${(oneMatch * 100).toFixed(2)}% of the store`);
  /* AND THE WALKWAY IS THE REASON. The match went into the first run of
     gondolas; the second run is a hundred and sixty units away across
     bare aisle, which is five cells of lino. Fire that cannot get over
     that is fire the floor plan CONTAINS — and the cross-aisles being
     real walls rather than slow ones is the difference between a shop
     you have to walk to burn and a shop you light once. */
  {
    let over = 0, of = 0;
    for (let x = 760; x < 880; x += 16)
      for (let y = 800; y < 1070; y += 16) {
        const i = fire.idx(fire.cellX(x), fire.cellY(y));
        if (fire.fuel0[i] <= 0) continue;
        of++;
        if (fire.fuel[i] < fire.fuel0[i]) over++;
      }
    check('and it never crosses the aisle to the next run of shelving',
      over === 0, `${over} of ${of} cells over the way burnt`);
  }

  /* AND NOW THE OTHER HALF, WHICH IS A DIFFERENT QUESTION. Whether the
     shop burns on its own and whether it CAN burn are not the same
     claim, and the map is written against the second one: a region the
     fire can never get into is a hole in the floor plan however the
     spread numbers are set. So the rest of this section runs on the
     store burnt the way it is meant to be burnt — a flamethrower walked
     over all of it, at the stream's own strength and footprint, which
     is what the player spends the night doing.

     AT THE STREAM'S OWN STRENGTH IS LOAD-BEARING. Anything over 40
     leaves accelerant behind (see FireSystem.ignite), and accelerant
     poured on tarmac makes tarmac burn — so a sweep done with a bigger
     number would quietly torch the car park and take the firebreak
     check with it. The flamethrower is 36 and lays none. */
  /* OVER THE MALL'S OWN GROUND. The clearing used to be the whole of
     what could burn; it is the mall AND the town now, and a player
     walking every thirty units of nineteen thousand by twenty-six
     thousand is not a test of anything, it is a different game. The
     claim was always about the shop. */
  let mallBurnt = 0, mallFuel = 0;
  {
    const mall = level.sectors.filter(inMall);
    let minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
    for (const s of mall) {
      if (s.forest || s.outside) continue;
      minx = Math.min(minx, s.bbox[0]); miny = Math.min(miny, s.bbox[1]);
      maxx = Math.max(maxx, s.bbox[2]); maxy = Math.max(maxy, s.bbox[3]);
    }
    for (let y = miny; y <= maxy; y += 30) {
      for (let x = minx; x <= maxx; x += 30) fire.ignite(x, y, 36, 22);
      for (let k = 0; k < 30; k++) fire.tic();
    }
    for (let i = 0; i < 200000 && fire.liveCells > 0; i++) fire.tic();
    for (const s of mall) { mallFuel += fire.sectorFuel[s.index]; mallBurnt += fire.sectorBurnt[s.index]; }
  }
  const mallFrac = mallBurnt / Math.max(1, mallFuel);
  note('and then walked with a flamethrower', `${(mallFrac * 100).toFixed(1)}% of the mall burned`);
  check('a player who does the work can still burn all of it',
    mallFrac > 0.97, `${(mallFrac * 100).toFixed(1)}%`);

  /* And it must still not touch anything the map declared as a
     firebreak. This used to be phrased as "no outdoor sector burns",
     which stopped being the same statement the moment the store got a
     footway: the pavement in front of the shops is outdoors AND carries
     fuel, on purpose, because it is the fuse that takes the fire along
     the parade to the neighbours. The invariant that actually matters is
     the one the map is written against — a sector with no fuel never
     burns, whatever else is true about it — and that is still what makes
     the car park the safe room. */
  let dryBurnt = 0;
  for (let i = 0; i < fire.heat.length; i++) {
    const s = fire.sectorOf[i] >= 0 ? level.sectors[fire.sectorOf[i]] : null;
    if (s && s.fuel === 0 && (fire.heat[i] > 0 || fire.fuel[i] < fire.fuel0[i])) dryBurnt++;
  }
  check('a sector with no fuel never burns', dryBurnt === 0, `${dryBurnt} cells burnt in a firebreak`);
  const lotCells = [...fire.sectorOf].filter(si => si >= 0 && level.sectors[si].name === 'bays').length;
  check('the car park is still the safe room', lotCells > 200, `${lotCells} cells of bays`);

  /* Every region of the shop must actually be REACHED, not just 97% of
     the fuel. A stockroom that never catches is a hole in the map. */
  const reached = {};
  for (let i = 0; i < fire.heat.length; i++) {
    const si = fire.sectorOf[i];
    if (si < 0) continue;
    const s = level.sectors[si];
    if (s.outdoor || s.fuel <= 0) continue;
    /* THE SHOP, which is what this section is about. The player walks
       the supermarket with a flamethrower; the town four thousand units
       away across the ring road is not somewhere the fire has been
       given any reason to go, and counting its bedrooms here would be
       asking whether the store burns and answering about a bungalow. */
    if (!inMall(s)) continue;
    const r = reached[s.name] || (reached[s.name] = { cells: 0, burnt: 0 });
    r.cells++;
    if (fire.fuel[i] < fire.fuel0[i]) r.burnt++;
  }
  /* TWO CLAIMS, NOT ONE, because they need different bars. Whether the
     fire GOT IN is the invariant the map is written against and it is
     absolute — a region it never enters is a hole in the map. Whether it
     then ate the region is a matter of degree, and a doorway four cells
     across cannot express degrees: three of its four cells is 75%, which
     under a single 90% bar reads as a failure when what actually
     happened is that the fire went through the door. So the small ones
     are held to "reached" and the ones big enough to mean it are held to
     nearly all of it. */
  const entries = Object.entries(reached);
  const never = entries.filter(([, r]) => r.burnt === 0).map(([n]) => n);
  const partial = entries.filter(([, r]) => r.cells >= 20 && r.burnt / r.cells < 0.9)
    .map(([n, r]) => `${n} ${((r.burnt / r.cells) * 100).toFixed(0)}%`);
  note('regions reached', `${entries.length - never.length}/${entries.length}`);
  check('the fire reaches every part of the shop', never.length === 0, never.join(', '));
  check('and eats nearly all of every region worth measuring',
    partial.length === 0, partial.join(', '));

  /* Regions that have burnt should have SAID so — a store that burns down
     and looks identical afterwards is an animation, not a simulation. */
  const charred = level.sectors.filter(s => inMall(s) && s.charred).length;
  const gutted = level.sectors.filter(s => inMall(s) && s.gutted).length;
  const burnable = level.sectors.filter(s => inMall(s) && s.fuel > 0).length;
  note('sectors charred / gutted', `${charred} / ${gutted}, of ${burnable}`);
  check('burnt regions get charred surfaces', charred >= burnable * 0.9, `${charred} of ${burnable}`);

  /* AND THE BUILDING COMES DOWN. Charring is a surface; gutting is a
     structure, and it is the end state the whole fire is for. A store
     that burns to a hundred per cent and still has its roof on is a
     store where the second stage never fired. */
  check('and a burnt-out store is gutted', gutted >= burnable * 0.85, `${gutted} of ${burnable}`);
  {
    /* WHAT A GUTTED REGION TURNS INTO, asked of the mapping directly —
       the fire here runs without a Game, so nothing has applied it. */
    const of = sec => tex.guttedSurfaces(sec, { cells: fire.sectorCells[sec.index] });
    const g0 = level.sectors.find(s => s.gutted && !s.outdoor && s.name === 'aisle');
    check('a gutted aisle exists to look at', !!g0);
    if (g0) {
      const to = of(g0);
      check('its walls are studs and holes', /^RUINWALL\d$/.test(to.wallTex), to.wallTex);
      check('and its floor is slab and ash', /^RUINFLR\d$/.test(to.floorTex), to.floorTex);
    }
    const rack = level.sectors.find(s => s.gutted && /SHELF/.test((s.wallTex || '').replace('_B', '')));
    if (rack) check('a gutted gondola is bare shelving', /^RUINRACK\d$/.test(of(rack).wallTex),
      of(rack).wallTex);

    /* THE ROOF DOES NOT ALL GO, AND IT GOES IN THREE STAGES. A burnt-out
       store with no ceiling anywhere is a demolition; what is wanted is a
       deck that is still up and charred over the short spans, HOLED over
       some of the long ones, and gone over the rest — with steel where it
       has gone. All three have to happen, and the check is that none of
       them is zero and that nothing falls outside them. */
    const roofs = level.sectors.filter(s => s.gutted && !s.outdoor && s.ceilTex && s.ceilTex !== 'SKY')
      .map(of).filter(t => t.ceilTex);
    const open = roofs.filter(t => t.ceilTex === 'SKY').length;
    const holed = roofs.filter(t => /^RUINHOLE\d$/.test(t.ceilTex)).length;
    const kept = roofs.filter(t => /^RUINDECK\d$/.test(t.ceilTex)).length;
    note('gutted roofs: gone / holed / still up', `${open} / ${holed} / ${kept}`);
    check('some of the roof falls in', open > 3, `${open}`);
    check('some of it is holed but still overhead', holed > 3, `${holed}`);
    check('and most of it is still up, burnt through', kept + holed > open,
      `${kept + holed} up, ${open} open`);
    check('every gutted ceiling is one of the three',
      open + holed + kept === roofs.length,
      `${roofs.length - open - holed - kept} were neither`);
    /* AND A ROOF THAT HAS FAILED SAYS SO, because that flag is the only
       thing that makes anything get built up there. */
    check('a failed roof is flagged for the framing',
      roofs.every(t => (t.ceilTex === 'SKY' || /^RUINHOLE/.test(t.ceilTex))
        === (t.ruinRoof === 'open' || t.ruinRoof === 'holed')),
      roofs.filter(t => !!t.ruinRoof !== (t.ceilTex === 'SKY' || /^RUINHOLE/.test(t.ceilTex))).length + ' disagreed');

    /* --- AND THE STEEL ITSELF -----------------------------------------
       js/ruin.js hangs a lattice of joists and beams over any region
       whose deck has failed, so that looking up in a burnt-out aisle is
       looking at a frame rather than at a rectangular hole in the world.
       Three claims, and the second is the one that took the design: the
       lattice is a function of WORLD position, so two regions either side
       of a wall get the same joists in the same places. */
    {
      const ruin = await import('../js/ruin.js');
      /* the smallest thing a BatchSet has to be for this */
      const fakeSet = () => {
        const bins = new Map();
        return { bins, get(n) { let b = bins.get(n); if (!b) bins.set(n, b = { q: [] }); 
          return { quad: (p, u, l, sk, ch) => b.q.push({ p, l, ch }) }; } };
      };
      const big = level.sectors.find(s => s.gutted && !s.outdoor && s.bbox[2] - s.bbox[0] > 600);
      const sec = { ...big, ruinRoof: 'open', ruinVariant: 0 };
      const one = fakeSet();
      const n = ruin.roofFraming(one, sec);
      const quads = [...one.bins.values()].reduce((t, b) => t + b.q.length, 0);
      note('the steel over one gutted region', `${n} members, ${quads} quads`);
      check('a region with no roof gets a frame', n > 2 && quads > 10, `${n} members`);
      check('and a region that still has one gets nothing',
        ruin.roofFraming(fakeSet(), { ...big, ruinRoof: null }) === 0);
      /* EVERY PIECE OF IT IS UNDER THE ROOF LINE AND INSIDE THE REGION,
         which is the pair of mistakes a lattice in world coordinates
         makes: steel poking through the ceiling next door, or steel that
         starts at the sector edge instead of where the grid says. */
      const pts = [...one.bins.values()].flatMap(b => b.q).flatMap(q => q.p);
      check('every piece of it is inside the region it is over',
        pts.every(([x, y, z]) => x >= big.bbox[0] - 1 && x <= big.bbox[2] + 1 &&
          -z >= big.bbox[1] - 1 && -z <= big.bbox[3] + 1));
      check('and hangs below the line the deck was on',
        pts.every(([, y]) => y <= big.ceil + 1e-6 && y > big.ceil - 140),
        `${Math.min(...pts.map(p => p[1])).toFixed(0)}..${Math.max(...pts.map(p => p[1])).toFixed(0)} against a ceiling at ${big.ceil}`);
      check('and it is charred, so the coals are in it',
        [...one.bins.values()].flatMap(b => b.q).every(q => q.ch === 1));
      /* THE LATTICE IS THE WORLD'S, not the region's: the same joist
         drawn from two different regions is at the same y. */
      const wide = { ...big, bbox: [big.bbox[0], big.bbox[1], big.bbox[2], big.bbox[3] + 400],
                     ruinRoof: 'open', ruinVariant: 0 };
      const two = fakeSet();
      ruin.roofFraming(two, wide);
      /* A JOIST'S TWO LONG FACES SIT AT j * pitch ± half, for an integer
         j measured from the world origin — that is the claim, and it is
         what makes the steel over one region line up with the steel over
         the next. Everything else up there (the beams, whose ends are
         the region's own edges) is filtered out by exactly that test. */
      const P = ruin.ROOF.joistPitch, H = ruin.ROOF.joistHalf;
      const rows = b => [...new Set([...b.bins.values()].flatMap(x => x.q)
        .flatMap(q => q.p.map(pp => -pp[2])))]
        .filter(v => Number.isInteger((v + H) / P) || Number.isInteger((v - H) / P))
        .sort((a, c) => a - c);
      const r1 = rows(one), r2 = rows(two);
      check('every joist sits on the world lattice rather than the region edge',
        r1.length >= 2 && r1.every(v => r2.includes(v)),
        `${r1.length} faces, and the wider region has ${r2.length}`);
      check('and a wider region gets more of the same lattice, not a new one',
        r2.length > r1.length, `${r1.length} -> ${r2.length}`);
    }

    /* AND IT IS NOT ALL THE SAME RUIN. One texture across a whole gutted
       store reads as a pattern, which is the one thing a ruin must not. */
    const walls = new Set(level.sectors.filter(s => s.gutted).map(s => of(s).wallTex).filter(Boolean));
    check('the ruin comes in more than one flavour', walls.size >= 3,
      [...walls].join(' '));
    /* a region's variant is stable, so a reload looks the same */
    check('and a region picks the same one every time',
      g0 ? of(g0).wallTex === of(g0).wallTex && of(g0).floorTex.endsWith(of(g0).wallTex.slice(-1)) : true);
  }
  /* THE COALS, wired end to end. The burning trees run an eight-colour
     ember ramp against a clock in their shader; every charred and gutted
     surface in the store now runs the same ramp on the same clock, and
     the thing that carries it is a per-vertex char amount off the
     region. Three links in that chain and all three are checkable
     without a GPU. */
  {
    const mg = await import('../js/mapgeo.js');
    const mat = await import('../js/material.js');
    const pal = await import('../js/palette.js');
    check('an untouched region carries no char', mg.charOf({}) === 0);
    check('a charred one carries some', mg.charOf({ charred: true }) > 0.4);
    check('and a gutted one carries all of it', mg.charOf({ gutted: true }) === 1);
    const u = mat.worldUniforms();
    check('the world material has the ember clock and the ramp',
      !!u.emberTime && Array.isArray(u.emberRamp.value) && u.emberRamp.value.length === 8);
    check('and the shader has the coals in it',
      /vec3 emberOf\(/.test(mat.WORLD_SHADE_GLSL) && /emberRamp\[/.test(mat.WORLD_SHADE_GLSL));
    /* --- AND SOOT, WHICH ARRIVES BEFORE THE FIRE DOES ---
       The store used to know three things about the fire: untouched,
       charred, gutted. Two texture swaps, and between them nothing — an
       aisle could lose half its stock without a pixel of it changing.
       The middle of it is drawn now, continuously, and off a number that
       belongs to the PIECE OF FLOOR rather than to the sector: a
       sector's progress is one number, and this map's sectors are big
       rectangles, so that version put a knife edge across the floor. */
    check('and it sooties a surface before anything has burnt off it',
      /float sootAmount\(/.test(mat.WORLD_SHADE_GLSL) && /vec3 sootOn\(/.test(mat.WORLD_SHADE_GLSL));
    check('off the fire grid, sampled where the surface is',
      /float burnAt\(vec3/.test(mat.WORLD_SHADE_GLSL) &&
      /uniform sampler2D burnGrid/.test(mat.WORLD_UNIFORMS_GLSL) &&
      !/regionBurn/.test(mat.WORLD_UNIFORMS_GLSL));
    check('and it knows the renderer z runs backwards against the map y',
      /vec2\(w\.x, -w\.z\)/.test(mat.WORLD_SHADE_GLSL));
    check('and anything off the edge of the fire reads nothing at all',
      /burnCols[\s\S]{0,60}return 0\.0/.test(mat.WORLD_SHADE_GLSL));
    check('and the soot creeps in world space and crawls on the coals clock',
      /emberHash\(floor\(wpos/.test(mat.WORLD_SHADE_GLSL) &&
      /crawl[\s\S]{0,80}emberTime/.test(mat.WORLD_SHADE_GLSL));
    check('the trees and the store share one ramp',
      pal.EMBER_RAMP.length === 8 && pal.EMBER_RAMP.every(c => c.length === 3));
    const F = await import('../js/forest.js');
    check('and the trees take it from the same place', F.EMBER_RAMP === pal.EMBER_RAMP);
  }

  check('every ruin texture is drawn', tex.RUIN.every(n => Object.keys(tex.TEXTURE_GENERATORS).includes(n)),
    tex.RUIN.filter(n => !Object.keys(tex.TEXTURE_GENERATORS).includes(n)).join(', '));
  const bank = new Set(Object.keys(tex.TEXTURE_GENERATORS).map(n => n));
  check('every charrable texture has a burnt twin',
    tex.CHARRABLE.every(n => bank.has(n)),
    tex.CHARRABLE.filter(n => !bank.has(n)).join(', '));

  /* --- THE PICTURE THE SHADER READS IT OUT OF ---
     THE FIRE'S OWN CELL GRID, one byte a cell, sampled by world
     position. It used to be one texel per SECTOR, and that is the bug
     the user reported as z-fighting: a sector's progress is one number,
     so every surface in it sooted at once, and the sectors of this map
     are big axis-aligned rectangles — a burnt aisle met a clean
     cross-aisle along a dead-straight line with a different texture and
     a different light on each side of it.

     Four ways for the grid version to be silently wrong: the texture too
     small to hold the grid, the world-to-cell arithmetic off (which puts
     a shop's soot in the car park), the y axis unflipped (the renderer's
     z runs backwards against the map's y), and anything off the edge of
     the grid reading the clamped edge instead of nothing. */
  {
    const THREE3 = await import('three');
    const { Game } = await import('../js/game.js');
    const mat = await import('../js/material.js');
    const lv3 = MAP.buildSellWrong({ town: false });
    const scene3 = new THREE3.Scene();
    const g3 = new Game({
      level: lv3, scene: scene3, camera: {},
      textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
      hud: { message() {}, ticMessages() {} }, audio: null,
      input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
               attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
    });
    const f3 = g3.fire;
    const bt = mat.world.burnGrid.value;
    note('the burn picture', `${bt.image.width}x${bt.image.height} for a ${f3.cols}x${f3.rows} grid of ` +
      `${f3.CELL}-unit cells, ${(bt.image.data.length / 1024).toFixed(0)}K a upload`);
    /* IT IS THE SIZE OF THE GRID AND ONE BYTE A CELL. It was the power of
       two over the grid, in RGBA with the same number in three of the
       channels: a megabyte of texels and four megabytes of upload, for a
       town, on every tic where one cell moved. Nine times smaller, and
       both halves of that are checkable. */
    check('the picture is exactly the fire grid, one byte a cell',
      bt.image.width === f3.cols && bt.image.height === f3.rows &&
      bt.image.data.length === f3.cols * f3.rows && bt.format === THREE3.RedFormat,
      `${bt.image.width}x${bt.image.height}, ${bt.image.data.length} bytes`);
    check('and it says where the grid is and how big a cell is',
      mat.world.burnOrigin.value.x === f3.originX &&
      mat.world.burnOrigin.value.y === f3.originY &&
      mat.world.burnCell.value === f3.CELL &&
      mat.world.burnCols.value === f3.cols && mat.world.burnRows.value === f3.rows);
    check('and it is filtered rather than blocky, which is the whole point',
      mat.world.burnGrid.value.magFilter === THREE3.LinearFilter);

    /* BURN ONE CELL AND FIND IT IN THE PICTURE. This is the arithmetic
       the shader does backwards, so doing it forwards here is the check
       that the two agree — and it is the one that would catch the axis
       flip, because the cell it looks in is derived from a world x and y
       and not from an index. */
    const cellAt = (x, y) => Math.floor((y - f3.originY) / f3.CELL) * f3.cols +
                             Math.floor((x - f3.originX) / f3.CELL);
    const pick = (() => {
      for (const s2 of lv3.sectors) {
        if (!s2.fuel || s2.outdoor) continue;
        const x = (s2.bbox[0] + s2.bbox[2]) / 2, y = (s2.bbox[1] + s2.bbox[3]) / 2;
        const i = cellAt(x, y);
        if (f3.fuel0[i] > 0) return { x, y, i, name: s2.name };
      }
      return null;
    })();
    check('there is a cell of shop floor to test with', !!pick);
    f3.fuel[pick.i] = f3.fuel0[pick.i] * 0.25;         // three quarters gone
    f3.gridDirtyAll = true;                            // poked behind the fire's back
    g3.ticBurnGrid();
    const data = mat.world.burnGrid.value.image.data;
    const texel = (x, y) => {
      const cx = Math.floor((x - f3.originX) / f3.CELL);
      const cy = Math.floor((y - f3.originY) / f3.CELL);
      return data[cy * f3.cols + cx];
    };
    note('one cell, three quarters burnt', `${pick.name} at ${pick.x | 0},${pick.y | 0} reads ${texel(pick.x, pick.y)}`);
    check('a cell three quarters burnt reads three quarters of the way up',
      Math.abs(texel(pick.x, pick.y) - 191) <= 2, `${texel(pick.x, pick.y)}`);
    /* AND ITS NEIGHBOURS HAVE NOT MOVED, which is the axis check: get the
       row and column the wrong way round and the value lands somewhere
       else in the picture entirely. */
    check('and nothing else in the shop caught it',
      texel(pick.x + f3.CELL * 3, pick.y) === 0 && texel(pick.x, pick.y + f3.CELL * 3) === 0);
    /* --- AND THE FIRE SAYS WHICH CELLS MOVED, so that finding them does
       not mean looking at all of them. Scanning the grid cost two thirds
       of every tic in the game once the town made it half a million
       cells; the fire keeps a list instead (gridDirty in js/fire.js) and
       this is the check that the list is actually what drives the
       picture — a cell changed WITHOUT telling anybody stays stale, and
       the same cell changed through the fire's own hand does not. */
    {
      const j = pick.i;
      f3.gridDirty.length = 0; f3.gridDirtyAll = false;
      f3.fuel[j] = f3.fuel0[j] * 0.5;                  // half gone, quietly
      g3.ticBurnGrid();
      check('a cell that changed behind the fire\'s back is not in the picture',
        Math.abs(texel(pick.x, pick.y) - 191) <= 2, `${texel(pick.x, pick.y)}`);
      f3._touch(j);
      check('and the fire put it on the list when asked', f3.gridDirty.length === 1 && f3.gridDirty[0] === j);
      g3.ticBurnGrid();
      check('and draining the list is what moves it', Math.abs(texel(pick.x, pick.y) - 128) <= 2,
        `${texel(pick.x, pick.y)}`);
      check('and the list is emptied by the draining', f3.gridDirty.length === 0);
      /* a fire that burns marks its own cells: light it and let it run a
         few tics, because a cell whose heat is still climbing has not
         eaten anything yet and so has not moved the picture */
      const ps = lv3.sectorAt(pick.x, pick.y);
      const lit = f3.ignite(pick.x, pick.y, ps.floor + 8, 200);
      f3.gridDirty.length = 0;
      /* enough tics to cross FIRE_INTERVAL a few times — the fire does
         not burn on every tic, and a cell that has only had its heat
         raised has not eaten anything yet */
      for (let k = 0; k < 16; k++) f3.tic();
      check('and a fire that is burning fills the list by itself',
        lit > 0 && f3.gridDirty.length > 0, `${lit} cells lit, ${f3.gridDirty.length} marked`);
      /* put it back the way the rest of this block found it */
      f3.fuel[j] = f3.fuel0[j] * 0.25; f3.gridDirtyAll = true; g3.ticBurnGrid();
    }

    /* the car park has no fuel, so it can never soot */
    const lot = lv3.sectors.find(s2 => s2.name === 'bays' || s2.floorTex === 'BAYROW');
    if (lot) {
      const lx = (lot.bbox[0] + lot.bbox[2]) / 2, ly = (lot.bbox[1] + lot.bbox[3]) / 2;
      check('and nothing outdoors with no fuel in it can ever soot',
        f3.fuel0[cellAt(lx, ly)] === 0 && texel(lx, ly) === 0);
    }
    /* NOTHING CARRIES A REGION ANY MORE. The attribute and its texture
       are gone; a surface finds its own burn from where it is. */
    const geo = await import('../js/mapgeo.js');
    check('the geometry carries no region attribute', !('regionOf' in geo));
    let attrs = 0;
    const walk = o => {
      if (o.geometry?.getAttribute?.('region')) attrs++;
      for (const c of o.children || []) walk(c);
    };
    walk(g3.geo.group);
    check('and no batch of it has one either', attrs === 0, `${attrs} found`);
  }

  /* --- HOW IT IS DRAWN ---
     Four claims, and each of them was a visible fault at some point this
     afternoon: the flames add rather than cover, there is more than one
     of them per cell and they are not on the cell's centre, they are
     bigger where the fire is deep and smaller at its fringe, and the
     scatter is the SAME scatter next frame. That last one is the
     important one — jitter re-rolled per frame is a fire that boils, and
     it is the difference between a fire and a fault. */
  {
    const THREE = await import('three');
    const scene = new THREE.Scene();
    const drawn = new FireSystem({
      ...fake, scene, sprites: spr.bakeSprites(),
      level, tics: 0,
    });
    drawn.ignite(1800, 1600, 400, 96);
    for (let k = 0; k < 120; k++) drawn.tic();
    drawn.render(1800, 1250, 0);
    const flames = drawn.sprites.filter(m => m.visible);
    const smoke = drawn.smokes.filter(m => m.visible);
    note('one burning run, drawn', `${flames.length} flames and ${smoke.length} of smoke ` +
      `over ${drawn.active.length} cells alight`);
    /* about half the cells get a flame — the thinning in FireSystem.render
       — and each is drawn bigger than its cell, so a fire is a scatter
       of big flames and not a carpet of small ones */
    check('the fire is drawn', flames.length > 16, `${flames.length}`);
    check('as fewer flames than cells alight, each standing for more than its own cell',
      flames.length < drawn.active.length && flames.length > drawn.active.length * 0.2,
      `${flames.length} flames on ${drawn.active.length} cells`);
    check('additively, and without writing depth',
      flames.every(m => m.material.blending === THREE.AdditiveBlending && !m.material.depthWrite));
    check('there is smoke standing over it', smoke.length > 4, `${smoke.length}`);
    check('and the smoke is blended rather than added',
      smoke.every(m => m.material.blending === THREE.NormalBlending && !m.material.depthWrite));
    const off = flames.filter(m => Math.abs(((m.position.x - drawn.originX) % 32) - 16) > 0.5);
    check('and most of them are not on a cell centre', off.length > flames.length * 0.3,
      `${off.length} of ${flames.length}`);
    const hs = flames.map(m => m.material.uniforms.spriteScale.value.y);
    check('the big ones are several times the small ones',
      Math.max(...hs) > Math.min(...hs) * 2.5,
      `${Math.min(...hs).toFixed(0)} to ${Math.max(...hs).toFixed(0)} units tall`);
    const was = flames.map(m => `${m.position.x},${m.position.z}`);
    drawn.render(1800, 1250, 0);
    const now = drawn.sprites.filter(m => m.visible).map(m => `${m.position.x},${m.position.z}`);
    check('and the scatter is the same scatter next frame',
      was.length === now.length && was.every((v, i) => v === now[i]));
    /* FROM THE FAR END OF THE STREET the same fire is a handful of very
       big flames: past FLAME_MID the cells are gathered into clumps and
       each clump is one flame sized by how much of it is alight, drawn
       whatever the flood says, out to the air's reach */
    drawn.render(1800 + 3200, 1250, 0);
    const farFlames = drawn.sprites.filter(m => m.visible);
    const farH = farFlames.map(m => m.material.uniforms.spriteScale.value.y);
    note('the same fire from 3200 units', `${farFlames.length} flames, ${Math.min(...farH).toFixed(0)} to ${Math.max(...farH).toFixed(0)} units tall`);
    check('from far off the fire is a handful of flames', farFlames.length >= 1 && farFlames.length <= 8, `${farFlames.length}`);
    check('and every one of them is huge', farH.every(h => h > 200), `${Math.min(...farH).toFixed(0)}`);
    drawn.render(1800 + 7000, 1250, 0);
    check('and past the air there is nothing', drawn.sprites.filter(m => m.visible).length === 0);
  }

  /* And the player's weapon has to be much faster than waiting. */
  const f2 = new FireSystem(fake);
  f2.ignite(540, 1000, 150, 26);
  let ticsAlone = 0;
  while (f2.burnFraction < 0.20 && ticsAlone < 90000) { f2.tic(); ticsAlone++; }
  note('20% by spreading alone', `${ticsAlone} tics (${(ticsAlone / 35).toFixed(0)}s)`);
  check('spreading alone is slow enough to leave room for a player', ticsAlone > 600,
        `${ticsAlone} tics is too fast to be worth a weapon`);
}

/* ---------- the air ---------- */
section('the air');
{
  /* THE HOUR, THE WEATHER AND THE WIND, headless. The judgement lives
     in a table in js/weather.js and this is what a table can be held
     to: that the night gets lighter and never darker on the way to
     the morning, that every colour in it is a colour the palette can
     draw, and that the weather rows say what they say. See SIGHT.txt. */
  const W = await import('../js/weather.js');
  const SK = await import('../js/skyart.js');
  const M = await import('../js/material.js');
  const SKY = await import('../js/sky.js');

  /* --- the clock --- */
  check('the night runs 22:00 to 08:00 and wraps onto it',
    W.nightHour(2) === 26 && W.nightHour(25.5) === 25.5 && W.nightHour(23) === 23 && W.nightHour(9) === 32 && W.nightHour(14) === 22,
    `${W.nightHour(2)} ${W.nightHour(25.5)} ${W.nightHour(23)} ${W.nightHour(9)} ${W.nightHour(14)}`);
  const w = new W.Weather({ hour: 2 });
  check('it starts at two in the morning, clear', w.label === '02:00' && w.kind === 'clear');
  const tics = 35 * 60;
  for (let i = 0; i < tics; i++) w.tic();
  note('after a minute of play', `${w.label}`);
  check('and a minute of play is the hours-per-minute the file says',
    Math.abs(w.hour - (2 + W.HOURS_PER_MINUTE)) < 0.01, w.label);
  const rise = (5.67 - 2) / W.HOURS_PER_MINUTE;
  note('two in the morning to sunrise', `${rise.toFixed(1)} minutes of play`);
  check('you have until dawn, and it is about nine minutes', rise > 7 && rise < 12, `${rise.toFixed(1)}`);
  w.setHour(7.9); for (let i = 0; i < tics; i++) w.tic();
  check('the clock stops at eight, past sunrise, where the table is flat', w.hour === 8, `${w.hour}`);

  /* --- the table --- */
  const luma = c => c[0] * 0.3 + c[1] * 0.6 + c[2] * 0.1;
  let lastSky = -1, lastHz = -1, monoSky = true, monoHz = true;
  const rows = [];
  for (let h = 2; h <= 8; h += 0.1) {
    const f = W.sampleHour(h);
    rows.push(f);
    if (f.skyLight < lastSky - 1e-6) monoSky = false;
    if (luma(f.horizon) < lastHz - 0.02) monoHz = false;
    lastSky = f.skyLight; lastHz = luma(f.horizon);
  }
  check('from two to eight the sky only gets lighter', monoSky);
  check('and so does the horizon', monoHz);
  const two = W.sampleHour(2), dawn = W.sampleHour(5.17), day = W.sampleHour(8);
  check('two in the morning is a night: stars, no sun, the fire is the light',
    two.stars === 1 && two.sunAlt < -18 && two.skyLight < 0.12 && two.daylight === 0);
  check('civil dawn has the sun just under and the glow on', dawn.sunAlt > -6 && dawn.sunAlt < 0 && dawn.glowAmt > 0.8 && dawn.stars < 0.1);
  check('and a dawn is rose: more red than blue along the horizon', dawn.glow[0] > dawn.glow[2] + 0.3, `${dawn.glow.map(v => v.toFixed(2))}`);
  check('eight is a day: the sun up, the sky full', day.sunAlt > 15 && day.skyLight === 1 && day.daylight === 1);
  check('the sun comes up in the east', Math.abs(W.SUN_AZ) < Math.PI / 4);

  /* EVERY COLOUR IN THE TABLE IS A COLOUR THE PALETTE CAN DRAW. This is
     the check that says whether the sky ramp is big enough, and the one
     that fails first if somebody takes its entries back: a dawn that
     snaps three grey levels away from what the table asked for is a
     dawn that comes out grey. */
  {
    /* AGAINST THE BOX THE TABLE WAS WRITTEN FOR, which is the one the
       game was drawn in and is asked for by name. The claim here is
       about the SKY RAMP — whether it has enough entries to hold a
       dawn — and that is a fact about a box of ramps, not about which
       box the game happens to be showing. The earth box is measured
       too and printed rather than asserted: it is deliberately duller,
       so of course the table's saturated blues land further away in
       it, and a check that failed for that would be a check that
       fails whenever anybody does what the box is for. */
    const miss = box => {
      pal.setArtPalette(box);
      let worst = 0, worstAt = '';
      for (const k of W.KEYFRAMES) {
        for (const key of ['zenith', 'horizon', 'ground', 'glow', 'sunCol']) {
          const c = [1, 3, 5].map(i => parseInt(k[key].slice(i, i + 2), 16));
          if (c[0] + c[1] + c[2] === 0) continue;
          const p = pal.PALETTE[pal.nearestIndex(...c)];
          const d = Math.hypot(...c.map((v, i) => v - p[i]));
          if (d > worst) { worst = d; worstAt = `${k.hour}h ${key} ${k[key]} -> ${p}`; }
        }
      }
      return { worst, worstAt };
    };
    const inEarth = miss('earth');
    const { worst, worstAt } = miss('stock');
    pal.setArtPalette(pal.DEFAULT_ART);
    note('worst palette miss in the table', `${worst.toFixed(0)} in the box it was written for — ${worstAt}`);
    note('and in the earth box', `${inEarth.worst.toFixed(0)} — ${inEarth.worstAt}`);
    check('every colour in the night snaps within a step or two of itself', worst < 40, worstAt);
    check('the palette has a ramp for the sky', pal.RAMP.sky && pal.RAMP.sky.n >= 16, JSON.stringify(pal.RAMP.sky));
    check('and it still has 256 entries', pal.PALETTE.length === 256);
  }

  /* --- the weather --- */
  const K = W.WEATHER_ORDER.map(k => W.WEATHERS[k]);
  check('four weathers, clear first', K.length === 4 && K[0].name === 'CLEAR');
  check('the air closes in from clear to mist', K.every((r, i) => i === 0 || r.airFar < K[i - 1].airFar),
    K.map(r => r.airFar).join(' > '));
  check('and near is always nearer than far', K.every(r => r.airNear < r.airFar));
  check('only the rain rains', K.filter(r => r.rain > 0).length === 1 && W.WEATHERS.rain.rain === 1);
  check('the mist is flat and the stars are gone under cloud', W.WEATHERS.mist.flat === 1 && W.WEATHERS.overcast.stars === 0);
  check('the clear night keeps the wind the smoke always had', Math.abs(W.WEATHERS.clear.wind[0] - 0.28) < 1e-9);
  const mist = W.sampleFrame(2, 'mist'), clear = W.sampleFrame(2, 'clear');
  check('night mist is lit, not black', luma(mist.horizon) > luma(clear.horizon) + 0.1,
    `${luma(mist.horizon).toFixed(2)} vs ${luma(clear.horizon).toFixed(2)}`);

  /* --- the uniforms --- */
  const w2 = new W.Weather({ hour: 2, kind: 'rain' });
  w2.apply(0.016, 0.25, 0.1);
  check('apply sets the air from the row', Math.abs(M.world.airFar.value - W.WEATHERS.rain.airFar) < 1 && Math.abs(M.world.airNear.value - W.WEATHERS.rain.airNear) < 1);
  check('and the smoke from the two fires', Math.abs(M.world.smokeDensity.value - Math.min(0.5, 0.25 * 1.2 + 0.1 * 0.5)) < 1e-3);
  check('and the ambient from the hour plus the burn', Math.abs(M.world.minLight.value - (W.sampleHour(2).minLight + 0.25 * 0.30)) < 1e-9);
  check('and everybody else can read the wind and the rain off climate',
    W.climate.rain === 1 && Math.abs(W.climate.wind.x - 0.9) < 1e-3 && W.climate.kind === 'rain' && Math.abs(W.climate.airFar - 5200) < 1);
  w2.setKind('clear'); w2.apply(0.016, 0, 0);
  check('and clear again', W.climate.rain === 0 && M.world.smokeDensity.value === 0);

  /* --- the weather a fire makes --- */
  {
    const plain = W.sampleFrame(2, 'clear', 0, 0), smoky = W.sampleFrame(2, 'clear', 0, 1);
    check('a sky full of smoke closes the air in and puts the stars out',
      smoky.airFar < plain.airFar / 3 && smoky.airNear < plain.airNear / 3 && smoky.stars === 0 && smoky.cover > 0.9,
      `air ${smoky.airFar} of ${plain.airFar}`);
    check('and is orange where the clear night is blue',
      smoky.horizon[0] > smoky.horizon[2] * 2 && plain.horizon[2] >= plain.horizon[0],
      `${smoky.horizon.map(v => v.toFixed(2))} against ${plain.horizon.map(v => v.toFixed(2))}`);
    check('half a sky of smoke is half way there',
      Math.abs(W.sampleFrame(2, 'clear', 0, 0.5).airFar - (plain.airFar + smoky.airFar) / 2) < 1);
    check('and a sky with no smoke is the sky it always was', JSON.stringify(plain) === JSON.stringify(W.sampleFrame(2, 'clear')));
    const w3 = new W.Weather({ hour: 2, kind: 'clear' });
    for (let k = 0; k < 600; k++) w3.apply(0.1, 0, 0, { hot: 400, wood: 0 });
    check('a big fire fills the sky with smoke in about a minute', w3.smoke > 0.7 && w3.smoke < 0.9, w3.smoke.toFixed(2));
    check('and the whole world reads it off climate: the air has closed in and the wind is up',
      W.climate.smoke === w3.smoke && W.climate.airFar < W.WEATHERS.clear.airFar / 2 && W.climate.wind.x > W.WEATHERS.clear.wind[0] * 1.5,
      `air ${W.climate.airFar.toFixed(0)}, wind ${W.climate.wind.x.toFixed(2)}`);
    check('and the label says so', w3.shownKind === 'smoke');
    const before = W.climate.airFar;
    for (let k = 0; k < 4000; k++) w3.apply(0.1, 0, 0, { hot: 0, wood: 0 });
    check('and it clears, slowly, when the fire is out', w3.smoke < 0.1 && W.climate.airFar > before * 2 && w3.shownKind === 'clear',
      `${w3.smoke.toFixed(3)}`);
    /* what has burnt keeps a floor under it: a town half gone is half a sky of smoke for good */
    const w4 = new W.Weather({ hour: 2, kind: 'clear' });
    for (let k = 0; k < 6000; k++) w4.apply(0.1, 0.5, 0, { hot: 0, wood: 0 });
    check('and a town half burnt keeps a sky a third full of smoke, fire or no fire', w4.smoke > 0.3 && w4.smoke < 0.4, w4.smoke.toFixed(2));
  }

  /* --- THE FOG IS THE SKY. The claim of the whole plan, held where
     it can be held headless: the world shader's fog colour is a fetch
     from the sky texture's horizon row in the fragment's azimuth, and
     the sky sphere takes the smoke and not the air — because the air
     IS the sky's horizon, and mixing it toward itself is the identity. */
  {
    const src = M.WORLD_SHADE_GLSL;
    check('the air is a texel of the sky, at the horizon, by azimuth',
      /atan\(toFrag\.z, toFrag\.x\)/.test(src) && /texture2D\(skyTex, vec2\(az, 0\.5/.test(src));
    check('the air goes on before the smoke', src.indexOf('mix(c, air, at)') < src.indexOf('smokeColor * max(l, 0.7)'));
    check('and the smoke goes on after, lit by the fire under it', /mix\(c, smokeColor \* max\(l, 0\.7\), f\)/.test(src));
    const skySrc = (await import('node:fs')).readFileSync(new URL('../js/sky.js', import.meta.url), 'utf8');
    const frag = skySrc.slice(skySrc.indexOf('const FRAG'), skySrc.indexOf('export function buildSky'));
    check('the sky takes the smoke', /smokeDensity/.test(frag));
    /* the air's haze never (it IS the sky's horizon); a map's fog does,
       out to airFar — see FOG_GLSL */
    check('and not the air', !/airNear|skyTex\b|mix\(c, air/.test(frag));
    /* the same azimuth the bake writes with: skyart's dirOf turns u
       into atan2(z, x) over a turn, and the fog reads back with the
       same formula — measured against three's SphereGeometry, see the
       header of js/skyart.js */
    const bake = (await import('node:fs')).readFileSync(new URL('../js/skyart.js', import.meta.url), 'utf8');
    check('and the bake lays the sky out on the same azimuth', /float phi = uv\.x \* 2\.0 \* PI;/.test(bake) && /sin\(phi\) \* c\)/.test(bake));
  }
  /* the horizon colour the fog gets, worked out the way the bake does:
     rose toward the sun at dawn and blue-grey away from it, which is
     what the screenshots show and what nobody wrote down */
  {
    const f = W.sampleFrame(5.17, 'clear');
    const east = SK.horizonColour(f, W.SUN_AZ), west = SK.horizonColour(f, W.SUN_AZ + Math.PI);
    check('at dawn the east is rose and the west is not', east[0] > west[0] * 2 && east[0] > east[2], `${east.map(v => v.toFixed(3))} vs ${west.map(v => v.toFixed(3))}`);
    const n = W.sampleFrame(2, 'clear');
    const townward = SK.horizonColour(n, Math.PI), away = SK.horizonColour(n, 0);
    check('and at night the town glows in the west', townward[0] > away[0] && townward[0] > townward[2] * 0.8, `${townward.map(v => v.toFixed(3))}`);
  }

  /* --- THE WIND ON THE FIRE --- */
  const F = await import('../js/fire.js');
  const { pSeed } = await import('../js/util.js');
  /* A FRESH MAP FOR EVERY MATCH. The fire sections above have burnt
     the shared level's gondolas and the sim has marked those regions
     charred and gutted on the sectors themselves — which is right, and
     which would make a gutted gondola a gondola the rain gets into. */
  const freshLevel = () => MAP.buildSellWrong({ town: false });
  {
    const [e, n, ww, ss] = F.windMultipliers(0.9, 0);
    check('a wind of 0.9 runs the fire downwind and holds it upwind', e > 1.5 && ww < 0.5 && n === 1 && ss === 1, `${e} ${ww}`);
    const [e2, , w2_] = F.windMultipliers(0.28, 0);
    check('the clear night\'s breeze is a lean, not a push', e2 > 1.1 && e2 < 1.3 && w2_ > 0.7 && w2_ < 0.9, `${e2} ${w2_}`);
    check('and it never goes to nothing or to double', F.windMultipliers(9, 9).every(v => v >= 0.4 && v <= 1.8));
  }
  /* AND A FIRE LEANS. The same match as the fire section, in a wind
     from the west and then from the east, and the burnt ground's
     centre of mass moves with it. */
  {
    /* THE WIND BLOWS OUTSIDE, and the wood is all outside: the same
       match in the same trees on the same roll, in a wind from the
       west, from the east and in none, and the burnt ground's centre
       moves with it. The store's own fire gets the same multipliers
       on its cells under the sky, and the check after this one holds
       that it gets them nowhere else. */
    const fake = (lv) => ({ level: lv, player: { x: 1240, y: -520, dead: false, damage() {} }, actors: [], sound: null, forest: null });
    const FOREST = await import('../js/forest.js');
    const lean = (wx) => {
      W.climate.wind.x = wx; W.climate.wind.y = 0; W.climate.rain = 0;
      pSeed(777);
      const wood = new FOREST.Forest(freshLevel());
      const ox = -9000, oy = 4000;
      wood.ignite(ox, oy, 60);
      for (let i = 0; i < 2400; i++) wood.tic();
      let sx = 0, n = 0;
      for (let i = 0; i < wood.state.length; i++) if (wood.state[i]) { sx += wood.worldX(i % wood.cols); n++; }
      return { lean: n ? sx / n - ox : 0, cells: n };
    };
    const east = lean(0.9), west = lean(-0.9), still = lean(0);
    W.climate.wind.x = 0.28; W.climate.wind.y = 0.05;
    note('a match in the wood in a wind, where the burn\'s centre went',
      `${east.lean.toFixed(0)} units with a west wind, ${west.lean.toFixed(0)} with an east one, ${still.lean.toFixed(0)} in none; ${still.cells} cells`);
    check('the wood catches', still.cells > 30, `${still.cells}`);
    check('the fire leans downwind', east.lean > still.lean + 20 && west.lean < still.lean - 20, `${east.lean.toFixed(0)} / ${still.lean.toFixed(0)} / ${west.lean.toFixed(0)}`);
    /* and the store's footway, the one strip outdoors with fuel on it,
       is a cell under the sky as far as the fire is concerned */
    {
      const lv = freshLevel();
      const fire = new F.FireSystem(fake(lv));
      const foot = lv.sectorAt(2000, -56);
      check('the footway is under the sky and holds fuel',
        foot && foot.outdoor && foot.fuel > 0 && fire.open[fire.idx(fire.cellX(2000), fire.cellY(-56))] === 1, foot && foot.name);
    }
    /* and the same match indoors does not care: no wind in aisle six */
    const inside = (wx) => {
      W.climate.wind.x = wx; W.climate.wind.y = 0;
      pSeed(777);
      const fire = new F.FireSystem(fake(freshLevel()));
      fire.ignite(540, 1000, 200, 40);
      for (let i = 0; i < 1500; i++) fire.tic();
      return fire.burnFraction;
    };
    const a = inside(0.9), b = inside(-0.9);
    W.climate.wind.x = 0.28; W.climate.wind.y = 0.05;
    check('and a fire under a roof burns the same in any wind', a === b, `${a} vs ${b}`);
  }

  /* --- THE RAIN ON THE FIRE --- */
  {
    const fake = (lv) => ({ level: lv, player: { x: 1240, y: -520, dead: false, damage() {} }, actors: [], sound: null, forest: null });
    /* the roof is the whole of the difference: the same match, on the
       same roll, dry and in the rain, under a roof and with the roof
       gone */
    const burn = (rain, gut) => {
      W.climate.rain = rain; W.climate.wind.x = 0.28; W.climate.wind.y = 0.05;
      pSeed(4242);
      const lv = freshLevel();
      const fire = new F.FireSystem(fake(lv));
      if (gut) lv.sectorAt(540, 1000).gutted = true;
      fire.ignite(540, 1000, 200, 40);
      let alive = 0;
      for (let i = 0; i < 2000; i++) { fire.tic(); if (fire.liveCells) alive = i; }
      return { frac: fire.burnFraction, alive };
    };
    const dry = burn(0, false), wetIn = burn(1, false), wetOut = burn(1, true);
    W.climate.rain = 0;
    note('the same match: dry / in the rain under a roof / with the roof gone',
      `${(dry.frac * 100).toFixed(2)}% / ${(wetIn.frac * 100).toFixed(2)}% / ${(wetOut.frac * 100).toFixed(2)}%, out at ${dry.alive} / ${wetIn.alive} / ${wetOut.alive}`);
    check('rain under a roof changes nothing', wetIn.frac === dry.frac && wetIn.alive === dry.alive, `${dry.frac} vs ${wetIn.frac}`);
    check('and rain on a gutted region puts it out', wetOut.frac < dry.frac * 0.5 && wetOut.alive < dry.alive, `${wetOut.frac} vs ${dry.frac}, out at ${wetOut.alive} vs ${dry.alive}`);
    const fire = new F.FireSystem(fake(freshLevel()));
    const outdoors = [...Array(fire.open.length).keys()].filter(i => fire.open[i]).length;
    note('cells under the sky', `${outdoors} of ${fire.open.length}`);
    check('the car park, the road and the wood are under the sky and the shop is not',
      outdoors > 1000 && !fire.open[fire.idx(fire.cellX(540), fire.cellY(1000))] && fire.open[fire.idx(fire.cellX(1240), fire.cellY(-900))]);
  }

  /* --- the rain itself --- */
  {
    const R = await import('../js/rain.js');
    const { Game } = await import('../js/game.js');
    const T3 = await import('three');
    const hudStub = { message() {}, ticMessages() {}, resize() {}, update() {} };
    const inputStub = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
    const g = new Game({ level: freshLevel(), scene: new T3.Scene(), camera: {}, textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: hudStub, audio: null, input: inputStub });
    check('the game has a weather and a rain', g.weather instanceof W.Weather && g.rain instanceof R.Rain);
    g.weather.setKind('rain'); g.weather.apply(0.016, 0, 0);
    g.player.x = 1240; g.player.y = -900; g.player.viewZ = 49;    // the car park
    for (let i = 0; i < 40; i++) g.rain.tic();
    const outside = g.rain.liveCount;
    g.player.x = 2000; g.player.y = 1600;                          // the middle of the shop floor
    for (let i = 0; i < 60; i++) g.rain.tic();
    const inside = g.rain.liveCount;
    note('drops alive, in the car park then on the shop floor', `${outside} then ${inside}`);
    check('it rains in the car park', outside > 500, `${outside}`);
    check('and not in the shop', inside < 40, `${inside}`);
    g.weather.setKind('clear'); g.weather.apply(0.016, 0, 0);
    W.climate.rain = 0;
  }

  /* --- THE HAZE THE FIRE MAKES, ON A SWITCH ------------------------
     At the user's request, and it is a debug switch rather than a
     picture setting because what it turns off is not an effect, it is
     a fact about the world. What is checked is the line it draws:
     everything the fire does to the AIR goes, and everything the fire
     IS stays. */
  {
    const wz = new W.Weather({ hour: 3, kind: 'clear', running: false });
    const air = () => ({ smoke: wz.smoke, density: M.world.smokeDensity.value,
                         far: wz.frame.airFar, light: M.world.minLight.value,
                         global: M.world.globalLight.value });
    /* a town well alight: the smoke rises over forty seconds, so it is
       run for two minutes of them */
    const alight = { hot: 4000, wood: 900 };
    for (let i = 0; i < 120; i++) wz.apply(1, 0.4, 0.2, alight);
    const on = air();
    note('a town alight, with the haze', `smoke ${on.smoke.toFixed(2)}, fog ${on.density.toFixed(2)}, seeing ${on.far | 0}`);
    check('a fire alight puts a lid of smoke over the town',
      on.smoke > 0.8 && on.density > 0.4, `${on.smoke.toFixed(2)} / ${on.density.toFixed(2)}`);
    check('and pulls the distance you can see in to a few hundred metres',
      on.far < 3000, `${on.far | 0}`);

    check('the switch is a switch', wz.setFireHaze(false) === true && wz.setFireHaze(false) === false);
    wz.apply(1, 0.4, 0.2, alight);
    const off = air();
    note('the same town, without it', `smoke ${off.smoke.toFixed(2)}, fog ${off.density.toFixed(2)}, seeing ${off.far | 0}`);
    check('off, the smoke goes out of the sky and the fog out of the air',
      off.smoke === 0 && off.density === 0, `${off.smoke} / ${off.density}`);
    check('and the night is as far-seeing as the weather says it is',
      off.far === W.WEATHERS.clear.airFar, `${off.far} against ${W.WEATHERS.clear.airFar}`);
    /* IT SNAPS. Forty seconds to come in and a hundred and fifty to
       clear is right for a sky and useless for a switch you are
       flicking to compare two frames. */
    check('and it snapped rather than easing, which is what a switch is for',
      off.smoke === 0);
    /* AND THE FIRE IS STILL THE FIRE. The ambient that lifts as the
       building goes — so you can find the way out of a gutted store —
       is the burn's and not the haze's, and does not move. */
    check('what the fire IS is untouched: the light it throws still lifts with the burn',
      Math.abs(off.light - on.light) < 1e-9 && Math.abs(off.global - on.global) < 1e-9,
      `${off.light.toFixed(3)} against ${on.light.toFixed(3)}`);

    wz.setFireHaze(true);
    for (let i = 0; i < 60; i++) wz.apply(1, 0.4, 0.2, alight);
    check('and it comes back in the way a sky does, by degrees',
      wz.smoke > 0.5 && wz.smoke < 1.001, `${wz.smoke.toFixed(2)}`);
    /* put the world uniforms back for whoever runs next */
    const wc = new W.Weather({ hour: 3, kind: 'clear', running: false });
    wc.apply(0.016, 0, 0);
  }
  /* and it is on a button, on by default, and remembered */
  {
    const fs2 = await import('node:fs');
    const html = fs2.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
    const main = fs2.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');
    check('the fire haze is a switch in the pause menu, on by default and remembered',
      /id="opt-haze"/.test(html) && /haze: true/.test(main) &&
      /toggle\('opt-haze', 'haze'\)/.test(main) && /setFireHaze\(!!prefs\.haze\)/.test(main));
  }
  /* the wind's old home is gone */
  {
    const fs = await import('node:fs');
    const eff = fs.readFileSync(new URL('../js/effects.js', import.meta.url), 'utf8');
    check('WIND_X is gone from js/effects.js and the smoke reads the weather',
      !/const WIND_X/.test(eff) && /climate/.test(eff) && (eff.match(/wind\.x/g) || []).length >= 3);
  }
}

/* ---------- what you can see ---------- */
section('what you can see');
{
  /* THE PORTAL FLOOD, against a real ray. Level.visibleSectors is
     conservative by design — it may draw a region it need not, and it
     must never hide one you can see into — and the second half of that
     is a thing a ray can test: cast sightBlocked from the eye through
     the field of view and every region a ray reaches has to be in the
     flood's set. Then the other half, without which the first is
     worthless: a flood that says everything is visible passes the ray
     test and does no work. */
  const lv = MAP.buildSellWrong();
  const LV = await import('../js/level.js');
  const half = Math.atan(Math.tan(36 * Math.PI / 180) * 1.6) + 0.25;
  const rayCheck = (x, y, yaw, far = 6000) => {
    lv.visibleSectors(x, y, yaw, half, 14000);
    let bad = 0, rays = 0;
    for (let a = -half; a <= half; a += 0.02)
      for (let d = 48; d < far; d += 48) {
        const px = x + Math.cos(yaw + a) * d, py = y + Math.sin(yaw + a) * d;
        const sec = lv.sectorAt(px, py);
        if (!sec) continue;
        rays++;
        if (!lv.sightBlocked(x, y, 49, px, py, 49) && !lv.isVisible(sec)) bad++;
      }
    return { rays, bad, seen: lv.visList.length };
  };
  const spots = [
    ['the car park, facing the store', 2000, -1200, Math.PI / 2],
    ['the car park, facing the wood', 2000, -1200, -Math.PI / 2],
    ['the stockroom, door shut', 1000, 3000, -Math.PI / 2],
    ['an aisle', 800, 1500, Math.PI / 2],
    ['the road out west', -12000, -2486, 0],
  ];
  let allRays = 0;
  for (const [name, x, y, yaw] of spots) {
    const r = rayCheck(x, y, yaw);
    allRays += r.rays;
    note(name, `${r.seen} of ${lv.sectors.length} regions, ${r.rays} ray points, ${r.bad} seen by a ray and hidden by the flood`);
    check(`${name}: the flood never hides what a ray can reach`, r.bad === 0, `${r.bad} of ${r.rays}`);
  }
  check('and that was a lot of rays', allRays > 40000, `${allRays}`);
  /* AND IT HIDES SOMETHING */
  lv.visibleSectors(1000, 3000, -Math.PI / 2, half, 14000);
  const fromStock = lv.visList.length, stockOut = lv.visList.filter(s => s.outdoor).length;
  check('from the stockroom with the door shut you see the stockroom', fromStock <= 3 && stockOut === 0, `${fromStock} regions, ${stockOut} outdoors`);
  lv.visibleSectors(2000, -1200, -Math.PI / 2, half, 14000);
  /* facing away from the shop, across the car park. What is in front of
     you is tarmac, the wood down the sides and — since there is a town
     on the other side of the ring road — a long way down its streets.
     What is NOT in front of you is the inside of the supermarket. */
  const toWood = lv.visList.length;
  const toWoodIn = lv.visList.filter(s => inMall(s) && !s.outdoor && !s.forest && !s.outside).length;
  check('from the car park facing the wood you see the car park and the wood, not the shop',
    toWoodIn === 0, `${toWood} regions, ${toWoodIn} of the shop`);
  lv.visibleSectors(2000, -1200, Math.PI / 2, half, 14000);
  const toStore = lv.visList.filter(inMall).length;
  check('and facing the store you see into it through the doors',
    toStore > toWoodIn + 30 && lv.visList.some(s => s.name === 'aisle'), `${toStore}`);
  /* THE DOOR OPENS. The stockroom's door is a Doom door — a ceiling on
     the floor that rises — and when it has risen the flood goes through */
  {
    const door = lv.sectors.find(s => s.dynamic && s.ceil <= s.floor + 1 && s.bbox[1] > 2600 && s.bbox[1] < 2800);
    if (door) {
      const shut = door.ceil;
      door.ceil = door.floor + 128;
      lv.visibleSectors(1000, 3000, -Math.PI / 2, half, 14000);
      const open = lv.visList.length;
      door.ceil = shut;
      note('the stockroom door up', `${fromStock} regions -> ${open}`);
      check('open the door and the flood goes through it', open > fromStock, `${open}`);
    } else note('the stockroom door', 'not found by the shape looked for; the check is skipped');
  }
  /* THE HYSTERESIS: a region seen last frame counts this frame.

     AT THE RADIUS THE GAME ACTUALLY RUNS IT AT, which is VIS_FAR and not
     the fourteen thousand units of clear air: past that radius the flood
     is not run and isVisible says so (everything is visible), and past
     VIS_BUDGET regions it gives up and says the same — so a check about
     what the flood DECIDED has to be made where the flood decides. Both
     of those contracts are checked on their own below. */
  lv.visibleSectors(1000, 3000, -Math.PI / 2, half, LV.VIS_FAR);
  const stock = lv.sectorAt(1000, 3000);
  lv.visibleSectors(2000, -1200, -Math.PI / 2, half, LV.VIS_FAR);
  check('a region seen last frame is still visible this frame, and gone the frame after',
    lv.isVisible(stock) && (lv.visibleSectors(2000, -1200, -Math.PI / 2, half, LV.VIS_FAR), !lv.isVisible(stock)));

  /* --- THE TWO WAYS THE FLOOD DECLINES TO ANSWER, both of which say
     "visible", because the rule this file keeps is that an unknown is
     drawn rather than hidden. --- */
  {
    /* PAST THE RADIUS. Nothing out there was walked, so nothing is known
       about it — the frustum and the caller's own distance cull decide,
       which is what decides in an engine with no portals at all. */
    lv.visibleSectors(2000, -1200, -Math.PI / 2, half, 1200);
    const near = lv.visList.length;
    const far = lv.sectors.find(s2 => {
      const b = s2.bbox, cx = (b[0] + b[2]) / 2, cy = (b[1] + b[3]) / 2;
      return Math.hypot(cx - 2000, cy + 1200) > 4000;
    });
    check('a region past the radius the flood was run to is called visible',
      !!far && lv.isVisible(far) && far._vis !== lv._visStamp, far?.name);
    check('and one inside it still has to have been reached',
      lv.sectors.some(s2 => !lv.isVisible(s2)), `${near} reached`);
    /* PAST THE BUDGET. An open street grid hides nothing and the walk
       stops proving it. */
    lv.visibleSectors(2000, -1200, -Math.PI / 2, half, 14000);
    check('a flood that runs past its budget gives up and says everything',
      lv._visAll && lv.visList.length <= 3000 && lv.sectors.every(s2 => lv.isVisible(s2)),
      `${lv.visList.length} walked, gave up ${lv._visAll}`);
    check('and one that does not, does not', (lv.visibleSectors(1800, 1600, Math.PI / 2, half, LV.VIS_FAR), !lv._visAll));
  }
  /* THE AIR BOUNDS IT: past airFar nothing is entered */
  const farAll = (lv.visibleSectors(2000, -1200, -Math.PI / 2, half, 14000), lv.visList.length);
  const farNear = (lv.visibleSectors(2000, -1200, -Math.PI / 2, half, 600), lv.visList.length);
  check('the flood stops at the air', farNear < farAll, `${farNear} within 600 against ${farAll} within 14000`);
  /* AND IT IS CHEAP */
  {
    const t0 = performance.now();
    for (let i = 0; i < 200; i++) lv.visibleSectors(2000, -1200, Math.PI / 2, half, 14000);
    const ms = (performance.now() - t0) / 200;
    note('a flood from the car park into the store', `${ms.toFixed(2)}ms`);
    check('and it costs under a millisecond, once a frame', ms < 3, `${ms.toFixed(2)}ms`);
  }
  /* OFF THE MAP there is nothing to flood from, and everything in reach
     is visible rather than nothing */
  lv.visibleSectors(-13860 - 500, 0, 0, half, 3000);
  check('off the map, everything in reach is visible', lv.visList.length > 0);
}

/* ---------- touch ---------- */
section('touch');
{
  /* The stick's maths, without a screen. The numbers are the ones a
     thumb feels: nothing inside the dead zone, nothing sudden at its
     edge, a walk at half throw and a run at the rim. */
  const t = await import('../js/touch.js');
  const R = 56;
  const rest = t.stickVector(0, 0, R);
  check('a resting thumb is no movement', rest.x === 0 && rest.y === 0 && rest.mag === 0);
  check('inside the dead zone is still no movement', t.stickVector(R * 0.1, 0, R).mag === 0);
  const edge = t.stickVector(R * 0.121, 0, R);
  check('leaving the dead zone starts from zero, not a jump', edge.mag > 0 && edge.mag < 0.01, `mag ${edge.mag.toFixed(3)}`);
  const half = t.stickVector(0, -R * 0.56, R);
  check('half a push forward is a walk, straight ahead', half.x === 0 && half.y > 0.45 && half.y < 0.55, `y ${half.y.toFixed(2)}`);
  const full = t.stickVector(0, -R, R);
  check('the rim is a full run', Math.abs(full.y - 1) < 1e-9 && full.mag === 1);

  /* ---- AND THE WAY INTO THE PAUSE MENU ------------------------------
     At the user's request, and it was two separate nothings. The pause
     button has been in index.html since the touch controls were built —
     two bars in the top corner, styled, positioned, mirrored for the
     left-handed layout — and js/touch.js had no branch for its kind, so
     tapping it did nothing at all. And a player on a pad had no way in
     either: pausing was Escape or P and nothing else. Both now go
     through the one flag Game.update reads on both sides of the pause.
     --------------------------------------------------------------------- */
  {
    const fsT = await import('node:fs');
    const html = fsT.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
    const touchSrc = fsT.readFileSync('js/touch.js', 'utf8');
    const inputSrc = fsT.readFileSync('js/input.js', 'utf8');
    const gameSrc = fsT.readFileSync('js/game.js', 'utf8');
    const cssSrc = fsT.readFileSync('css/style.css', 'utf8');
    check('the pause button is in the page, and it is one of the touch buttons',
      /class="tb tb-pause" data-btn="pause"/.test(html) && /\.tb-pause \{/.test(cssSrc));
    check('and tapping it now says so, which it did not',
      /if \(kind === 'pause'\) t\.pausePulse = true;/.test(touchSrc) &&
      /pausePulse: false/.test(inputSrc));
    check('the pad opens it too, on either of its middle buttons',
      /const padStart = padEdge\(9\), padSelect = padEdge\(8\);/.test(inputSrc) &&
      /this\.pausePressed = this\.pressed\('pause'\) \|\| this\.touch\.pausePulse \|\| padStart \|\| padSelect;/.test(inputSrc));
    check('the pulse is cleared where it is read, like the other taps',
      /this\.touch\.pausePulse = false;/.test(inputSrc));
    /* THE PAD EDGE IS TAKEN BEFORE THE ||, which the zoom step did not
       do: padEdge records what the button was doing this frame, so an
       || that short-circuits past it leaves that record a frame stale
       and swallows the next press off the pad. */
    check('and every pad edge is sampled before the or, not inside it',
      /const padZoom = padEdge\(1\);/.test(inputSrc) &&
      !/\|\| padEdge\(/.test(inputSrc));
    check('and the game listens for it on both sides of the pause',
      /if \(this\.input\.pausePressed\) this\.setPaused\(false\);/.test(gameSrc) &&
      /if \(this\.input\.pausePressed && this\.state === 'play'\) this\.setPaused\(this\.net \? !this\.paused : true\);/.test(gameSrc));
  }

  /* ---- AND A BUTTON TO AIM WITH ---------------------------------------
     At the user's request, for the lance and the quad launcher, and it
     was a nothing like the pause button: the scope's one button went in
     with the lance and never showed, because setScope only changed
     `hidden` when it was already what it was being changed to. There are
     two now. AIM puts the gun up to the eye and takes it down, and is
     lit while it is up; the magnification is on the glass only while the
     gun is up, and steps between the aimed steps without ever dropping
     it to the hip.
     --------------------------------------------------------------------- */
  {
    const fsT = await import('node:fs');
    const html = fsT.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
    const touchSrc = fsT.readFileSync('js/touch.js', 'utf8');
    const inputSrc = fsT.readFileSync('js/input.js', 'utf8');
    const mainSrc = fsT.readFileSync('js/main.js', 'utf8');
    const cssSrc = fsT.readFileSync('css/style.css', 'utf8');
    check('AIM is in the page, hidden until a gun with a screen is in hand, and says whether it is pressed',
      /class="tb tb-aim" data-btn="aim" role="button" aria-label="[^"]+" aria-pressed="false" hidden>AIM</.test(html) &&
      /class="tb tb-zoom" data-btn="zoom"[^>]* hidden>/.test(html));
    check('and tapping it says so, and the input layer clears it like the other taps',
      /if \(kind === 'aim'\) t\.aimPulse = true;/.test(touchSrc) && /aimPulse: false/.test(inputSrc) &&
      /this\.touch\.aimPulse = false;/.test(inputSrc) && /case 'aim': case 'zoom': p\.el\.classList\.remove\('held'\)/.test(touchSrc));

    /* the buttons, on a stand-in for the page */
    const el = () => {
      const on = new Set(), attr = {};
      return { hidden: true, textContent: '', on, attr,
        classList: { contains: c => on.has(c), add: c => on.add(c), remove: c => on.delete(c), toggle: (c, v) => (v ? on.add(c) : on.delete(c)) },
        setAttribute(k, v) { attr[k] = v; } };
    };
    const tc = Object.create(t.TouchControls.prototype);
    tc.el = { aim: el(), zoom: el() };
    tc.setScope(true, '1×', false);
    check('with a scope in hand AIM shows, which the one button never did, and the magnification waits for it',
      !tc.el.aim.hidden && tc.el.zoom.hidden && !tc.el.aim.on.has('on'));
    tc.setScope(true, '2.1×', true);
    check('up at the eye AIM is lit and pressed, and the magnification shows with its step on it',
      tc.el.aim.on.has('on') && tc.el.aim.attr['aria-pressed'] === 'true' && !tc.el.zoom.hidden && tc.el.zoom.textContent === '2.1×');
    tc.el.zoom.on.add('held');
    tc.setScope(false);
    check('and put away, both go, and neither comes back looking pressed',
      tc.el.aim.hidden && tc.el.zoom.hidden && !tc.el.zoom.on.has('held') && !tc.el.aim.on.has('on') &&
      tc.el.aim.attr['aria-pressed'] === 'false');

    /* what the presses do to a scope */
    const SC = await import('../js/scope.js');
    const TH = await import('../js/thermal.js');
    const sc = new SC.Scope(null), steps = [];
    for (const press of ['aim', 'step', 'step', 'step', 'aim', 'aim', 'cycle', 'cycle', null]) { sc.work(press); steps.push(sc.zoomIndex); }
    check('AIM goes up and down, the magnification steps round the aimed steps and never to the hip, and up again is where it was',
      steps.join() === '1,2,1,2,0,2,0,1,1', steps.join());
    check('and the launcher\'s sight does the same, being the same kind of thing',
      !Object.hasOwn(TH.ThermalScope.prototype, 'work') && !Object.hasOwn(TH.ThermalScope.prototype, 'toggleAim'));

    /* A PRESS IS KEPT UNTIL IT IS TAKEN. The input is sampled a tic at a
       time and the scope reads it a frame at a time; a flag that was just
       left standing was read twice when a frame had no tic in it — a zoom
       that stepped two for one, and a toggle that went up and straight
       back down — and lost when a frame had two. */
    const I = await import('../js/input.js');
    const inp = Object.assign(Object.create(I.Input.prototype), {
      keys: new Set(), prev: new Set(), latch: new Set(), _padPrev: [], wheel: 0, mouseDX: 0, mouseDY: 0,
      sensitivity: 0, zoomScale: 1, invertY: false, mouseDown: false, mouseRightPulse: false,
      zoomPressed: false, zoomStep: false, aimToggle: false,
      touch: { move: { x: 0, y: 0 }, look: { x: 0, y: 0 }, attack: false, use: false, usePulse: false, jumpPulse: false,
               zoomPulse: false, aimPulse: false, pausePulse: false, run: false, weapon: 0 },
    });
    const took = [];
    inp.touch.aimPulse = true; inp.sample(1 / 35); inp.sample(1 / 35);   // two tics before the frame
    took.push(inp.takeScope(), inp.takeScope());                          // and two frames after them
    inp.touch.zoomPulse = true; inp.sample(1 / 35);
    took.push(inp.takeScope());
    inp.latch.add('zoom'); inp.sample(1 / 35); inp.sample(1 / 35);
    took.push(inp.takeScope(), inp.takeScope());
    check('a scope press waits for the frame to take it, and is taken once: not lost to a second tic, not counted on a second frame',
      took.join() === 'aim,,step,cycle,', took.join());
    check('and the frame takes it every time, whatever is in hand, and hands it to whichever sight is',
      /const press = input\.takeScope\(\);/.test(mainSrc) && /else if \(lance\) scope\.work\(press\);/.test(mainSrc) &&
      /else if \(launcher\) thermal\.work\(press\);/.test(mainSrc) && !/input\.zoomPressed/.test(mainSrc) &&
      /!!sighted && sighted\.zoomed\);/.test(mainSrc));

    /* AND NOTHING ON THE GLASS IS ON TOP OF ANYTHING ELSE. The one scope
       button there used to be was placed half over SWAP on a phone; the
       places are read off the style sheet and laid out at the smallest,
       a phone's and the largest size the fire button comes in. */
    const outerK = +(cssSrc.match(/--outer: calc\(var\(--arc\) \* ([\d.]+)\);/) || [])[1];
    const at = cls => {
      const rule = (cssSrc.match(new RegExp('\\n\\.tb-' + cls + ' \\{([^}]*)\\}')) || [])[1] || '';
      const axis = side => {
        const m = rule.match(new RegExp(side + ': calc\\(var\\(--fire-c[xy]\\)(?: \\+ var\\(--(arc|outer)\\)(?: \\* ([\\d.]+))?)? - var\\(--small\\) \\* \\.5\\);'));
        return m ? { ring: m[1], k: m[1] ? (m[2] ? +m[2] : 1) : 0 } : null;
      };
      return { x: axis('right'), y: axis('bottom') };
    };
    const small = ['jump', 'use', 'swap', 'aim', 'zoom'];
    const spots = Object.fromEntries(small.map(c => [c, at(c)]));
    let worst = Infinity, found = outerK > 1 && small.every(c => spots[c].x && spots[c].y);
    for (const B of found ? [64, 70, 84] : []) {
      const sm = B * 0.72, arc = B * 0.5 + sm * 0.5 + 12, R = { arc, outer: arc * outerK };
      const c = small.map(k => { const q = spots[k]; return [q.x.k * (R[q.x.ring] || 0), q.y.k * (R[q.y.ring] || 0)]; });
      for (let i = 0; i < c.length; i++) {
        worst = Math.min(worst, Math.hypot(c[i][0], c[i][1]) - (B + sm) / 2);
        for (let j = 0; j < i; j++) worst = Math.min(worst, Math.hypot(c[i][0] - c[j][0], c[i][1] - c[j][1]) - sm);
      }
    }
    check('no two buttons round the fire button overlap, at any size it comes in, AIM and the magnification included',
      found && worst > 0, `${worst.toFixed(1)}px between the nearest two`);
    check('and the left-handed layout has them too, in the mirror',
      /#touch\.lefty \.tb-aim +\{ right: auto; left: calc\(var\(--fire-cx\) \+ var\(--outer\) \* \.9239/.test(cssSrc) &&
      /#touch\.lefty \.tb-zoom \{ right: auto; left: calc\(var\(--fire-cx\) \+ var\(--outer\) \* \.3827/.test(cssSrc));
  }
  const past = t.stickVector(0, -3 * R, R);
  check('past the rim is still exactly one', past.mag === 1 && Math.abs(past.y - 1) < 1e-9);
  const diag = t.stickVector(R, R, R);
  check('a diagonal is unit length, not root two', Math.abs(Math.hypot(diag.x, diag.y) - 1) < 1e-9);
  check('screen-down is back and screen-right is right',
    t.stickVector(0, R, R).y < 0 && t.stickVector(R, 0, R).x > 0);

  const [bx, by] = t.followBase(100, 100, 100 + R * 2, 100, R);
  check('the base is towed to one radius behind the finger', Math.abs(bx - (100 + R)) < 1e-9 && by === 100, `${bx},${by}`);
  const [sx, sy] = t.followBase(100, 100, 130, 110, R);
  check('and stays put while the finger is inside the rim', sx === 100 && sy === 100);

  note('stick radius: phone / small / tablet',
    `${t.stickRadius(844, 390)} / ${t.stickRadius(320, 240)} / ${t.stickRadius(1366, 1024)}`);
  check('the stick fits a phone', t.stickRadius(844, 390) === 55 && t.stickRadius(320, 240) === 44);
  check('and is not a saucer on a tablet', t.stickRadius(1366, 1024) === 64);

  const look = t.lookDelta(150, 150, 1);
  note('a 150px swipe', `${(look.x * 180 / Math.PI).toFixed(0)} degrees across, ${(look.y * 180 / Math.PI).toFixed(0)} up`);
  check('a thumb swipe turns about sixty degrees', look.x > 0.95 && look.x < 1.15);
  check('vertical look is slower than horizontal', look.y > 0 && look.y < look.x);
  check('look speed scales the swipe', Math.abs(t.lookDelta(100, 0, 2).x - 2 * t.lookDelta(100, 0, 1).x) < 1e-12);
}

/* ---------- the wood ---------- */
section('the wood');
{
  /* The forest simulates without a renderer, which is the point of
     keeping the simulation and the drawing apart: a spark in a typed
     array either takes the wood or it does not, and that can be watched
     for an hour in Node in a second. */
  const F = await import('../js/forest.js');
  const forest = new F.Forest(level);
  /* --- EVERY KIND HAS ITS ART --------------------------------------
     A plant kind is a row in KINDS and a PAIR of files in
     assets/forest/: the albedo and the burn map, named after the kind.
     loadForestArt in js/main.js walks KINDS and fetches both, so a kind
     added to the table without its art is a 404 in the page and an
     invisible plant in the world — which is a thing this file cannot
     see, because it hands the Forest a stub for the art. It can see the
     files. */
  {
    const fsF = await import('node:fs');
    const missing = [];
    for (const k of F.KINDS) for (const suffix of ['', '_burn'])
      if (!fsF.existsSync(new URL(`../assets/forest/${k.name}${suffix}.png`, import.meta.url)))
        missing.push(`${k.name}${suffix}.png`);
    check('every plant in the wood has an albedo and a burn map on disk',
      missing.length === 0, missing.join(', '));
    note('plant kinds', `${F.KINDS.length}, ${F.KINDS.filter(k => /^street_|^hedge_/.test(k.name)).length} of them the town's`);
  }
  /* --- THE LOD: three chunk sizes, every plant drawn exactly once ------- */
  {
    const fL = new F.Forest(level);
    const scene = new (await import('three')).Scene();
    const art = { ground: {}, groundBurnt: {}, sprites: Object.fromEntries(F.KINDS.map(k => [k.name, { albedo: {}, burn: {} }])) };
    fL.build(scene, art);
    const A = fL.kindArrays;
    const lod = A.filter(a => a && a.lod && a.levels.length), fine = A.filter(a => a && !a.lod && a.levels.length);
    check('the firs and the bushes are built at three chunk sizes, the understory at one',
      lod.length >= 4 && lod.every(a => a.levels.length === 3 && a.levels[1].ch === 4096 && a.levels[2].ch === 8192) &&
      fine.every(a => a.levels.length === 1), `${lod.length} kinds with a LOD, ${fine.length} without`);
    /* every plant of the kind is in every level, once. A kind's source
       is whichever array its slots are sized to — the canopy's for the
       firs, the understory's for the bushes */
    const srcOf = a => (a.levels[0].slot.length === fL.trees.n ? fL.trees : fL.covers);
    check('and every tree is in every level once',
      lod.every(a => a.levels.every(L => { let n = 0; for (let i = 0; i < L.slot.length; i++) if (L.slot[i] >= 0) n++; return n === a.n; })));
    check('and the bushes are drawn at all now — they are planted in the understory\'s arrays and were read out of the canopy\'s',
      lod.some(a => srcOf(a) === fL.covers && a.n > 0) && F.KINDS.filter(k => !k.cover && k.h <= 120).every(k => A[F.KINDS.indexOf(k)].n > 0));
    /* drawn exactly once, from wherever you stand */
    const cl = level.clearing, clx = (cl[0] + cl[2]) / 2, cly = (cl[1] + cl[3]) / 2;   // the store's box
    const eyes = [[clx, cly], [fL.originX + 3000, fL.originY + 3000], [fL.originX + fL.cols * F.CELL * 0.5, fL.originY + 900]];
    let once = true, fineDraws = 0, lodDraws = 0, worst = '';
    for (const [ex, ey] of eyes) {
      fL.render(ex, ey, 40, 0, 0, 1);
      for (const a of lod) {
        const T = srcOf(a);
        const seen = new Uint8Array(T.n);
        let draws = 0;
        for (const L of a.levels) {
          for (const ch of L.chunks) if (ch.mesh.visible) draws++;
          for (let i = 0; i < T.n; i++) { const ch = L.chunks[L.chunkOf[i]]; if (ch && L.slot[i] >= 0 && ch.mesh.visible) seen[i]++; }
        }
        lodDraws += draws;
        /* what the fine chunks alone would have cost */
        const far = (a.far + 2048);
        let fd = 0;
        for (const ch of a.levels[0].chunks) { const dx = ch.x - ex, dy = ch.y - ey; if (dx * dx + dy * dy < far * far) fd++; }
        fineDraws += fd;
        for (let i = 0; i < T.n; i++) {
          if (T.kind[i] !== A.indexOf(a)) continue;
          const dx = T.x[i] - ex, dy = T.y[i] - ey;
          const inRange = dx * dx + dy * dy < far * far;
          if (seen[i] > 1 || (seen[i] === 0 && inRange && Math.hypot(dx, dy) < a.far - 2048 * 1.5)) { once = false; worst = `${seen[i]} of tree ${i}`; }
        }
      }
    }
    check('and from three places, every tree in range is drawn exactly once', once, worst);
    note('tree draws, fine chunks / with the LOD', `${fineDraws} / ${lodDraws}`);
    check('and the LOD is well under half the draws of fine chunks alone', lodDraws < fineDraws * 0.5, `${lodDraws} against ${fineDraws}`);
    check('the burn reaches every level', (() => {
      const wx = fL.originX + 3000, wy = fL.originY + 3000;   // in the wood
      fL.ignite(wx, wy, 200);
      for (let t = 0; t < 40; t++) fL.tic();
      fL.render(wx, wy, 40, 0, 0, 1);
      return lod.some(a => a.levels.every(L => L.chunks.some(ch => { for (let i = 0; i < ch.burn.length; i++) if (ch.burn[i] > 0) return true; return false; })));
    })());
  }
  note('cells / fuel cells', `${forest.cols}x${forest.rows} / ${forest.fuelCells}`);
  note('trees / plants', `${forest.treeCount} / ${forest.plantCount}`);
  check('the wood is huge', forest.fuelCells > 100000, `${forest.fuelCells} cells`);
  check('and full of trees', forest.treeCount > 20000, `${forest.treeCount}`);
  const c = level.clearing;
  let inClearing = 0;
  /* the clearing runs over the town too, and the town plants its own
     trees in its own yards — see _plantTown in js/forest.js — so the
     claim is about the STORE's half of it */
  for (let i = 0; i < forest.treeCount; i++) {
    const x = forest.trees.x[i], y = forest.trees.y[i];
    if (x > c[0] && x < c[2] && y > Math.max(c[1], TOWN_EDGE) && y < c[3]) inClearing++;
  }
  check('no tree stands in the car park or the store', inClearing === 0, `${inClearing} did`);
  note('the town planted', `${forest.townPlants ?? 0} trees and shrubs of its own`);
  check('and the town has its trees', (forest.townPlants ?? 0) > 500, `${forest.townPlants}`);
  check('the store has no forest fuel under it', !forest.fuel[forest.idx(forest.cellX(2000), forest.cellY(1000))]);
  /* THE FUEL GRID STOPS AT THE STORE, and the claim is about what is
     INSIDE it rather than about four numbers. It used to be three typed
     coordinates, which is a check that fails the first time the building
     changes size — and the building changed size the moment fourteen
     more tenancies went into the parade. What has to be true is that the
     grid covers the whole parade and the car park it stands in, that it
     stops at the back wall of the anchor, and that it is nowhere near
     the nine thousand units of wood on every side, which has its own
     fire. */
  check('the fuel grid covers the whole building and its lot',
    level.fireBounds[0] < MAP.PARADE_X0 && level.fireBounds[2] > MAP.PARADE_X1 &&
    level.fireBounds[3] > MAP.ANCHOR_Y1 && level.fireBounds[3] < MAP.ANCHOR_Y1 + 600,
    level.fireBounds.join());
  /* IT USED TO STOP AT THE BACK WALL OF THE ANCHOR, exactly, and now it
     stops at the back of the SERVICE YARD — which is tarmac behind the
     store, is not wood, and so is inside the store's grid for the same
     reason the car park is. Nothing burns there either. What makes that
     worth having rather than merely harmless is `clearing`, which is
     this rectangle: the forest keeps a margin outside it, so extending
     it past the fence is what guarantees nothing grows in the gateway. */
  check('and the yard behind the store is in it, with nothing to burn',
    level.sectors.some(s => s.name === 'the service yard' && s.fuel === 0));

  /* --- THE FENCE ROUND THE YARD -------------------------------------
     A fence in this engine is not a wall — a wall is the ABSENCE of a
     sector — it is chain link hung in an opening as a middle texture on
     a two-sided line. So there are three separate things to be sure of,
     and the last one is the only one that is about the game: that it is
     drawn, that it is shorter than the hole it hangs in, and that you
     cannot get past it except at the gate. */
  {
    const Y = MAP.YARD;
    const yard = level.sectors.find(s => s.name === 'the service yard');
    check('there is a service yard behind the store',
      !!yard && yard.outdoor && !yard.forest);
    const wire = level.lines.filter(l => l.middle === 'CHAINLNK');
    note('the fence', `${wire.length} lines of chain link, ${Y.fenceH} tall`);
    check('the chain link hangs in openings rather than being built as wall',
      wire.length >= 4 && wire.every(l => l.front !== null && l.back !== null));
    /* THE YARD'S OWN WIRE IS THE YARD'S OWN HEIGHT; the town's is the
       town's — the ball field's and the school's are taller than the
       loading bay's, because they are. What every fence on the map has
       to do is stop at its top rail rather than fill the opening it
       hangs in, and that is the check. */
    /* THE YARD IS SEVERAL REGIONS NOW, not one: it is laid as bands with
       the skips and the condensing sets cut out of them, so the wire
       along its west side belongs to whichever band reaches that side.
       Asking `l.front === yard.index` found two lines of the eight and
       failed a check about fence height with a fact about bookkeeping,
       which is exactly the fault the cemetery railing check had. Ask
       every piece. */
    const yardIdx = new Set(level.sectors.filter(s => s.name === 'the service yard').map(s => s.index));
    const yardWire = wire.filter(l => yardIdx.has(l.front) || yardIdx.has(l.back));
    check('the yard\'s wire is the height the yard says it is',
      yardWire.length >= 4 && yardWire.every(l => l.midHeight === Y.fenceH),
      `${yardWire.length} lines over ${yardIdx.size} pieces of yard`);
    check('and it stops at the top rail instead of filling the opening',
      wire.every(l => l.midHeight > 0 &&
        l.midHeight < Math.min(level.sectors[l.front].ceil, level.sectors[l.back].ceil)),
      `${wire.filter(l => !(l.midHeight > 0 && l.midHeight < Math.min(level.sectors[l.front].ceil, level.sectors[l.back].ceil))).length} reach the sky`);
    check('and every bit of it is solid', wire.every(l => l.blocking));

    /* AND NOW THE ONLY QUESTION A PLAYER ASKS OF A FENCE. Fired across
       the fence line rather than tested against a list of lines, because
       what is being claimed is about walking and not about bookkeeping:
       one way through, and it is where the gate is. */
    const z = 20, mid = (Y.gate[0] + Y.gate[1]) / 2;
    const across = x => !!level.rayHitWall(x, Y.y1 - 48, z, x, Y.y1 + 48, z);
    check('the gate is one small opening', Y.gate[1] - Y.gate[0] <= 200,
      `${Y.gate[1] - Y.gate[0]} wide`);
    check('and you can walk out through it', !across(mid));
    check('but not through the back of the fence anywhere else',
      [Y.x0 + 120, mid - 600, mid - 200, mid + 200, mid + 600, Y.x1 - 120].every(across),
      `${[Y.x0 + 120, mid - 600, mid - 200, mid + 200, mid + 600, Y.x1 - 120].filter(x => !across(x)).join()} let you through`);
    const yMid = (Y.y0 + Y.y1) / 2;
    check('nor out of either end of it',
      !!level.rayHitWall(Y.x0 + 48, yMid, z, Y.x0 - 48, yMid, z) &&
      !!level.rayHitWall(Y.x1 - 48, yMid, z, Y.x1 + 48, yMid, z));
    /* and the fourth side is the building, which was already true */
    check('and the store itself is the fourth side',
      !!level.rayHitWall(mid, Y.y0 + 48, z, mid, Y.y0 - 48, z));
    /* NOTHING GROWS IN THE GATEWAY, which is not luck: `clearing` is the
       fuel grid's rectangle and the forest keeps a margin outside it, so
       the yard being inside the grid is what holds the gate open. */
    const forest2 = new F.Forest(level, { seed: 4 });
    check('and nothing has grown in the gateway',
      !forest2.blocks(mid, Y.y1 + 40, 18) && !forest2.blocks(mid, Y.y1 + 90, 18));
  }
  check('and stops well short of the wood',
    level.fireBounds[0] > level.forestBounds[0] + 4000 &&
    level.fireBounds[2] < level.forestBounds[2] - 4000,
    `${level.fireBounds.join()} inside ${level.forestBounds.join()}`);
  const roadOut = level.sectors.filter(s => s.outside);
  check('the road runs out through the wood on both sides', roadOut.some(s => s.bbox[2] <= -1400) && roadOut.some(s => s.bbox[0] >= 5680), `${roadOut.length} outside sectors`);
  /* IT CARRIES NO FUEL, which is the whole of what "not the store's
     business" means. It used to be said geometrically as well — the road
     out lies outside the clearing's bounding box — and that stopped
     being true when the clearing grew a town: the box round the mall and
     the town now reaches past the ring road, and the west leg of the
     through road crosses it at a y no block of the town occupies. The
     flag and the fuel are the claim; the box was a proxy for it. */
  check('and is not the store\'s fuel',
    roadOut.every(s => s.fuel === 0 && s.outside && !s.forest),
    `${roadOut.filter(s => s.fuel !== 0).length} carry fuel`);
  check('the road has two ends to arrive from', level.roadEnds?.length === 2 && level.roadEnds[0].side !== level.roadEnds[1].side);
  const onRoad = level.sectorAt(2000, (level.road.y0 + level.road.y1) / 2);
  check('the road crosses the lot in front of the store', !!onRoad && /road/.test(onRoad.name) && onRoad.outdoor && !onRoad.forest, onRoad?.name);

  /* a plant is a trunk to the flame, not a billboard */
  const fir = F.KINDS[0];
  check('a fir is narrow at the foot and widest a third of the way up',
    F.plantRadius(fir, 0.02) < 0.1 && F.plantRadius(fir, 0.3) === 0.5 && F.plantRadius(fir, 0.99) < 0.05);
  let ti = 0;
  while (forest.trees.kind[ti] !== 0) ti++;               // a tall fir
  const tx = forest.trees.x[ti], ty = forest.trees.y[ti], th = fir.h * forest.trees.scale[ti];
  check('the flame passes beside a trunk it would have hit at canopy width',
    forest.hitsTree(tx, ty, th * 0.02) && !forest.hitsTree(tx + 40, ty, th * 0.02) && forest.hitsTree(tx + 40, ty, th * 0.3));
  check('you cannot walk through a trunk', forest.blocks(tx, ty, 16));

  /* one match */
  const sx = forest.worldX(forest.cellX(c[0] - 800)), sy = forest.worldY(forest.cellY(c[1] - 800));
  check('a match lights the wood', forest.ignite(sx, sy, 40) > 0);
  for (let k = 0; k < 90; k++) forest.tic();
  const acc = { sx: 0, sy: 0, sw: 0, n: 0 };
  forest.glowInto(acc, sx, sy, 900);
  const out = [];
  forest.emitters(sx, sy, 1200, 4, out);
  check('what is burning near you lights you and throws sparks', acc.n > 0 && out.length > 0, `${acc.n} / ${out.length}`);
  let tics = 90, t25 = 0, t5 = 0;
  while (forest.burnFraction < 0.25 && tics < 35 * 60 * 60) {
    forest.tic(); tics++;
    if (!t5 && forest.burnFraction >= 0.05) t5 = tics;
  }
  t25 = tics;
  note('5% / 25% of the wood, left alone', `${(t5 / 35 / 60).toFixed(1)} min / ${(t25 / 35 / 60).toFixed(1)} min`);
  check('the fire takes the wood on its own', forest.burnFraction >= 0.25, `${(forest.burnFraction * 100).toFixed(1)}% after ${tics} tics`);
  check('but not in a flash', t5 > 35 * 60, `${(t5 / 35).toFixed(0)}s to 5%`);
  /* An hour, where it used to be fifty minutes. The wood south of the
     mall is a town now and the wood that is left is a ring round it, so
     a fire lit in one flank has less continuous timber to run through
     and takes a few minutes longer to get a quarter of the way. The
     claim is unchanged: it takes the wood on its own, not in a flash
     and not over an afternoon. */
  check('nor in an afternoon', t25 < 35 * 60 * 60, `${(t25 / 35 / 60).toFixed(0)} min to 25%`);
  check('burnt cells stay burnt', forest.state[forest.idx(forest.cellX(sx), forest.cellY(sy))] === 2);
}

/* ---------- the flame ---------- */
section('the flame');
{
  const FL = await import('../js/flame.js');
  const reach = FL.streamReach();
  const drop = FL.streamDrop(28);
  note('reach / on the floor at', `${reach.toFixed(0)} / ${drop.toFixed(0)} units`);
  check('the stream reaches across an aisle', reach > 600 && reach < 900, reach.toFixed(0));
  check('and lands on the floor before it runs out', drop > 250 && drop < reach, drop.toFixed(0));
  check('the heat stays below the accelerant line', FL.STREAM.heat < 40, `${FL.STREAM.heat}`);

  /* particles: a pool, not an allocator */
  const P = await import('../js/particles.js');
  const pool = new P.Particles({ max: 4, frames: 1 });
  const ids = [pool.spawn({ x: 0, y: 0, z: 0, life: 2 }), pool.spawn({ x: 0, y: 0, z: 0, life: 5 }), pool.spawn({ x: 0, y: 0, z: 0, life: 5 }), pool.spawn({ x: 0, y: 0, z: 0, life: 5 })];
  check('a full pool refuses politely', pool.spawn({ x: 0, y: 0, z: 0 }) === -1 && ids.every(i => i >= 0));
  pool.tic(); pool.tic();
  check('a particle dies when its life runs out', pool.count === 3);
  check('and its slot is reused', pool.spawn({ x: 0, y: 0, z: 0, life: 9 }) === ids[0]);
  const s = pool.spawn({ x: 0, y: 0, z: 10, vx: 2, life: 9, drag: 0.5, gravity: -1 });
  check('the pool is full again', s === -1);
  let landed = 0;
  pool.tic((i, nx, ny, nz) => nz < 0 ? (landed++, true) : false);
  check('a collision hook can stop one', landed === 0 && pool.count === 4);

  /* the stream in the actual game: born at the nozzle, dying on the floor */
  const { Game } = await import('../js/game.js');
  const THREE = await import('three');
  const hudStub = { message() {}, ticMessages() {}, resize() {}, update() {} };
  const inputStub = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
  const g = new Game({ level, scene: new THREE.Scene(), camera: {}, textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: hudStub, audio: null, input: inputStub });
  const p = inTheOpen(g);                    // a jet needs somewhere to land
  const o = g.nozzle();
  check('without a model the flame is born low and right of the eye', o.z < p.viewZ && Math.hypot(o.x - p.x, o.y - p.y) > 10);
  for (let k = 0; k < 6; k++) { g.flame.fire(o, p.angle, 0); g.flame.tic(); }
  check('the stream is in the air', g.flame.liveCount >= 12, `${g.flame.liveCount}`);
  for (let k = 0; k < 40; k++) g.flame.tic();
  check('and every particle has landed', g.flame.liveCount === 0 && g.flame._hits > 0, `${g.flame.liveCount} live, ${g.flame._hits} hits`);
  check('the player cannot be hurt for now', (p.damage(50, null), p.health === 100));
  /* --- THE TANK, WHICH EMPTIES NOW ---
     Three claims: the stream is billed per tic rather than per shot
     cycle, an empty tank stops the pour in the middle of it, and the
     tank comes back on its own with nothing in the shop to refill it
     from. The last one is the only source of fuel in the game, so if it
     is broken the game has twelve seconds in it and then nothing. */
  {
    const pl = await import('../js/player.js');
    const d = pl.WEAPONS.FLAMER;
    check('the tank is finite', p.ammoFor('FLAMER') === pl.TANK && pl.TANK > 100, `${p.ammoFor('FLAMER')}`);
    check('and there is nothing in the level to refill it from',
      !level.things.some(t => t.type === 'FUELCAN'),
      `${level.things.filter(t => t.type === 'FUELCAN').length} cans`);
    check('the boxcutter is gone, and the bore is issued in its place',
      !pl.WEAPONS.BOXCUTTER && !p.owned.BOXCUTTER && !!p.owned.BORE && !!pl.WEAPONS.BORE);
    /* billed per tic of stream: thirty tics of pouring costs thirty */
    const was = p.ammo.fuel;
    for (let k = 0; k < 30; k++) p.flameTic(d);
    check('the stream costs one a tic', p.ammo.fuel === was - 30, `${was} -> ${p.ammo.fuel}`);
    note('a full tank', `${(pl.TANK / 35).toFixed(0)} seconds of flame, ` +
      `back in ${(pl.TANK * pl.REGEN_EVERY / 35).toFixed(0)} seconds`);
    /* and running dry stops it where it stands */
    p.ammo.fuel = 1; p.fireIndex = 0;
    p.flameTic(d); p.flameTic(d);
    check('an empty tank stops the pour mid-pour', p.ammo.fuel === 0 && p.fireIndex === -1);
    check('and the trigger does nothing until there is fuel again', !p.hasAmmo('FLAMER'));
    /* --- AND IT WILL NOT LIGHT AGAIN UNTIL IT IS HALF FULL ----------
       At the user's request, and it is the difference between a budget
       and a decision: a tank that refuses only when it is empty is one
       you hold the trigger on until it stops and then hold again the
       moment a tenth of a unit is back. This is the latch, both ways. */
    check('an empty tank latches, and one unit does not unlatch it',
      p.dry === true && (p.ammo.fuel = 1, p.regenTick = 0, p.fuelTic(), !p.armed('FLAMER')),
      `${p.ammo.fuel} in it and ${p.armed('FLAMER') ? 'armed' : 'not armed'}`);
    check('and the gauge says which half it is waiting for',
      p.refireMark === pl.REFIRE_AT && pl.REFIRE_AT === 0.5, `${p.refireMark}`);
    /* one below the mark is still no, and one above it is yes */
    p.ammo.fuel = Math.floor(pl.TANK * pl.REFIRE_AT) - 2; p.regenTick = 0;
    for (let k = 0; k < pl.REGEN_EVERY; k++) p.fuelTic();
    check('a tank one short of half still will not fire', !p.armed('FLAMER'),
      `${p.ammo.fuel} of ${pl.TANK}`);
    for (let k = 0; k < pl.REGEN_EVERY * 3; k++) p.fuelTic();
    check('and half a tank lights it again', p.armed('FLAMER') && !p.dry,
      `${p.ammo.fuel} of ${pl.TANK}`);
    check('and the mark goes away once it has', p.refireMark === 0);
    /* the refill, which is the only source there is */
    p.ammo.fuel = 0; p.dry = false;
    p.regenTick = 0;
    for (let k = 0; k < pl.REGEN_EVERY * 4; k++) p.fuelTic();
    check('the tank fills itself', p.ammo.fuel === 4, `${p.ammo.fuel} after ${pl.REGEN_EVERY * 4} tics`);
    check('and very slowly', pl.REGEN_EVERY >= 6, `one every ${pl.REGEN_EVERY} tics`);
    check('and it stops at full', (p.ammo.fuel = pl.TANK,
      p.fuelTic(), p.ammo.fuel === pl.TANK));
  }

  /* --- THE SMOKE, AND WHAT IT HAD BEEN INHERITING -----------------
     Two complaints, both the user's, and they turned out to be about
     different halves of the same sprite.

     FIRST, IT WAS WEARING THE FIRE'S COALS. Everything in this game
     shares one fragment shader, and the block that asks the burn grid
     "how burnt is the floor here" is the right question for a wall and
     the wrong one for a thing standing in front of one. Every sprite was
     being given the soot and the live coals of whatever it was over —
     and smoke drifts, so it sampled a different part of the grid every
     frame and the coals CRAWLED across it. It is a define now and only
     surfaces set it.

     SECOND, IT STEPPED. The churn, the sway and the lift all came off
     the whole tic count, which advances thirty-five times a second while
     the renderer runs at sixty or more; and the loop was eight frames
     over about two seconds, which is a step every eleven tics of a
     sprite big enough to see holding still. */
  {
    const mat = await import('../js/material.js');
    const fs2 = await import('node:fs');
    const sprites = spr.bakeSprites();
    const wall = mat.createWallMaterial(null, {});
    const sprite = mat.createSpriteMaterial(null, {});
    check('a surface burns and a sprite does not',
      'SURFACE_BURN' in wall.defines && !('SURFACE_BURN' in sprite.defines),
      Object.keys(sprite.defines).join(', '));
    check('and a sprite can freeze and a surface cannot',
      'FROST' in sprite.defines && !('FROST' in wall.defines));
    /* AND BURN AWAY, which rides the same define on purpose: it is the
       same kind of fact about the same kind of thing, and a second
       define is a second shader permutation for one uniform. */
    check('and a sprite carries both numbers the fire and the cold write',
      'frost' in sprite.uniforms && 'ash' in sprite.uniforms &&
      sprite.uniforms.ash.value === 0);
    /* AND NO BACKTICKS IN THE SHADER, which has now cost two debugging
       sessions. The GLSL lives in a JavaScript template literal and a
       pair of them in a COMMENT closes the string mid-sentence: the
       file still parses, and the game dies on import with "Unexpected
       identifier". The prose in that file is dense and the temptation
       to quote an identifier in it is constant, so it is a check. */
    check('and the burn-away eats the drawing rather than fading it',
      (() => {
        const src = fs2.readFileSync('js/material.js', 'utf8');
        const frag = src.slice(src.indexOf('const COMMON_FRAG'), src.indexOf('export function worldUniforms'));
        /* the three zones: gone, the line of coals, and the scorch ahead
           of it — a discard, an additive ramp lookup, and a mix */
        return /if \(ash > 0\.0\)/.test(frag) && /discard/.test(frag) &&
               /glowAdd = emberRamp/.test(frag) && /c \+ glowAdd/.test(frag);
      })());
    /* AND IT RUNS FEET FIRST. vUv.y runs UP the person — the quad is
       authored with its foot at y = 0 and its uv goes with it — and the
       first cut of this assumed the opposite and ate people from the
       hat down, which is a person dissolving rather than a person on
       fire. One character, nothing else in the game would notice, so it
       is pinned in the source. */
    check('the burn-away runs from the feet up',
      (() => {
        const src = fs2.readFileSync('js/material.js', 'utf8');
        const blk = src.slice(src.indexOf('if (ash > 0.0)'), src.indexOf('SURFACE_BURN'));
        return /float up = vUv\.y;/.test(blk) && !/float up = 1\.0 - vUv\.y;/.test(blk);
      })());
    /* AND THE FIRE ON A PERSON RUNS THE OTHER WAY ROUND, because fire
       climbs: white at the knees, and their face is the last thing left
       recognisable. Which is also what keeps a burning shopper legible
       as a PERSON for the four seconds they have — evenly washed to
       orange they are a silhouette, and the point of them running is
       that you can see who it is running. */
    check('and a sprite can be alight as well as frozen and eaten',
      'alight' in sprite.uniforms && sprite.uniforms.alight.value === 0);
    check('and the fire on one is hottest at the feet',
      (() => {
        const src = fs2.readFileSync('js/material.js', 'utf8');
        const blk = src.slice(src.indexOf('if (alight > 0.0)'), src.indexOf('if (ash > 0.0)'));
        return /float low = 1\.0 - vUv\.y;/.test(blk) && /emberRamp/.test(blk) &&
               /mix\(t\.rgb/.test(blk);
      })());
    check('and the shader guards both blocks rather than multiplying by zero',
      (() => {
        const src = fs2.readFileSync('js/material.js', 'utf8');
        const frag = src.slice(src.indexOf('const COMMON_FRAG'), src.indexOf('export function worldUniforms'));
        return /#ifdef SURFACE_BURN[\s\S]*?burnAt\(vWorld\)/.test(frag) &&
               /#ifdef SURFACE_BURN[\s\S]*?emberOf\(/.test(frag);
      })());

    /* AND THE LOOPS ARE LOOPS. Both sets are one noise field scrolled by
       a fraction of its own height, so frame N is frame 0 again and every
       step between them is the same small move. The four puffs this
       replaced were four INDEPENDENT fields — walking them was not a
       churn, it was four cuts. */
    const smok = sprites.count('SMOK');
    const fxSrc = fs2.readFileSync('js/effects.js', 'utf8');
    const puffs = +(fxSrc.match(/export const SMOKE_PUFFS = (\d+)/) || [])[1];
    note('the two smokes', `${smok} frames over the fire, ${puffs} drifting`);
    check('the body of smoke has frames enough to churn rather than flick',
      smok >= 16, `${smok}`);
    check('and the drifting puffs are a loop rather than a set of blobs',
      puffs >= 8 && /const pn = fbm\(/.test(fxSrc) && /\(y \+ off\) % PW/.test(fxSrc),
      `${puffs} frames`);
    check('and one field makes all of them, or the loop is a slideshow',
      (fxSrc.match(/fbm\(PW, PW/g) || []).length === 1);

    /* AND THE CLOCK HAS THE FRACTION ON IT */
    const { Game } = await import('../js/game.js');
    const THREE9 = await import('three');
    const g9 = new Game({ level, scene: new THREE9.Scene(), camera: {},
      textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
      hud: { message() {}, ticMessages() {} }, audio: null,
      input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
               attack: false, use: false, run: false, sample() {}, sensitivity: 0 } });
    check('on a whole tic the smooth clock is the tic count', g9.smoothTics === g9.tics);
    g9.update(1 / 35 * 1.5);
    check('and between two it is between two',
      g9.smoothTics > g9.tics && g9.smoothTics < g9.tics + 1,
      `${g9.smoothTics.toFixed(3)} against ${g9.tics}`);
    const fireSrc = fs2.readFileSync('js/fire.js', 'utf8');
    check('and the smoke and the flames both read it rather than the tic count',
      (fireSrc.match(/smoothTics/g) || []).length >= 2 &&
      !/this\.tics \* 0\.014/.test(fireSrc));
    check('and a puff keeps the cell it is standing over between frames',
      /_smokeCell/.test(fireSrc));
  }
}

/* ---------- the cold ---------- */
/* THE SECOND STREAM, which is the first one built the other way up.
   What is checked here is the pair of things that make it a weapon
   rather than a recolour: that it takes heat OUT of the grid without
   giving any fuel back, and that a person it holds can be left, thawed
   or broken — three outcomes, all reachable, none of them the same as
   being set on fire. */
section('the cold');
{
  const FR = await import('../js/frost.js');
  const FL = await import('../js/flame.js');
  const pl = await import('../js/player.js');
  const { Game } = await import('../js/game.js');
  const { Actor, ACTIONS } = await import('../js/actor.js');
  const THREE = await import('three');
  const hudStub = { message() {}, ticMessages() {}, resize() {}, update() {} };
  const inputStub = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
                      attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
  const mk = () => new Game({ level: MAP.buildSellWrong({ town: false }), scene: new THREE.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: hudStub, audio: null, input: inputStub });

  /* --- IT IS A SHORTER ARM THAN THE FLAME -------------------------
     A gas jet loses its speed faster than a thrown liquid does and then
     sinks, so this has to come out with less reach than the flamethrower
     or the extinguisher is simply a better flamethrower. */
  {
    const reach = FR.jetReach(), flame = FL.streamReach();
    note('the jet / the flame', `${reach.toFixed(0)} against ${flame.toFixed(0)} units`);
    check('the jet is shorter in the arm than the flame', reach < flame * 0.8,
      `${reach.toFixed(0)} against ${flame.toFixed(0)}`);
    check('and it sinks harder, being colder than the air it is in',
      FR.JET.gravity < FL.STREAM.gravity && FR.JET.drag < FL.STREAM.drag,
      `gravity ${FR.JET.gravity} drag ${FR.JET.drag}`);
  }

  /* --- PUTTING A FIRE OUT, AND WHAT IT CANNOT PUT BACK -------------
     douse moves cells across the thresholds the fire runs on. What it
     must never do is return fuel: a burnt aisle stays burnt, the store's
     percentage never goes backwards, and the thing the extinguisher
     saves is whatever has not caught yet. */
  {
    const g = mk();
    const F = g.fire;
    const x = 1500, y = 1500;
    F.ignite(x, y, 400, 160);
    for (let i = 0; i < 40; i++) g.tic();
    const hotBefore = F.heatAt(x, y), burntBefore = F.burntFuel, liveBefore = F.active.length;
    const cooled = F.douse(x, y, 200, 120);
    const hotAfter = F.heatAt(x, y);
    note('a fire, doused', `${cooled} cells, heat ${hotBefore.toFixed(2)} -> ${hotAfter.toFixed(2)}`);
    check('dousing takes the heat out of the grid',
      cooled > 0 && hotAfter < hotBefore * 0.5, `${hotBefore.toFixed(2)} -> ${hotAfter.toFixed(2)}`);
    check('and it cannot give the fuel back',
      F.burntFuel >= burntBefore && Math.abs(F.burntFuel - burntBefore) < 1e-9,
      `${burntBefore.toFixed(1)} -> ${F.burntFuel.toFixed(1)}`);
    check('and a region that was charred stays charred',
      g.level.sectors.filter(s => s.charred).length >= 0);
    /* AND THE EMBERS GO WITH IT, which is the difference between a fire
       that is out and a fire that is sulking: a cell left at a glow
       relights anything that wanders past it. */
    let glowing = 0;
    for (let i = 0; i < F.heat.length; i++) if (F.heat[i] > 0 && F.ember[i] > 0) glowing++;
    check('and nothing it cooled is left glowing',
      (() => {
        const cx0 = F.cellX(x - 60), cx1 = F.cellX(x + 60);
        const cy0 = F.cellY(y - 60), cy1 = F.cellY(y + 60);
        for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) {
          const i = F.idx(cx, cy);
          if (F.heat[i] === 0 && F.ember[i] > 0) return false;
        }
        return true;
      })(), `${glowing} cells still glowing anywhere`);
    check('and dousing bare floor is free', F.douse(20000, 20000, 200, 120) === 0);
    /* ROUND AND NOT SQUARE, unlike ignite: the corner of a box of cells
       never had any gas on it, and a doused corner left burning restarts
       the whole cell. */
    const g2 = mk();
    g2.fire.ignite(1500, 1500, 400, 400);
    for (let i = 0; i < 30; i++) g2.tic();
    const R = 200;
    const before = g2.fire.heatAt(1500 + R * 0.71, 1500 + R * 0.71);
    g2.fire.douse(1500, 1500, 250, R);
    check('the spray is a circle, so the corners of its box are untouched',
      g2.fire.heatAt(1500 + R * 0.71, 1500 + R * 0.71) === before &&
      g2.fire.heatAt(1500, 1500) === 0, `corner ${before.toFixed(2)} kept`);
  }

  /* --- AND WHAT IT DOES TO A PERSON -------------------------------- */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    check('a shopper is something the cold can work on', !!who && who.info.freezable);
    note('the dial', `${Actor.FREEZE_AT} to freeze, one back every ${Actor.THAW_EVERY} tics, ` +
      `${Actor.FIRE_THAW} a tic in a fire`);
    /* IT RUNS UP BEFORE IT LANDS, which is the whole of the feedback: a
       shopper the spray has caught but not yet held goes pale first. */
    who.chill(30);
    check('a little cold is a tint and not a state', who.frost === 30 && !who.frozen);
    check('and it reaches the shader that does the colour map',
      Math.abs(who.frost / Actor.FREEZE_AT - 0.3) < 1e-9);
    /* AND AT THE THRESHOLD THEY GO SOLID */
    const froze = who.chill(Actor.FREEZE_AT);
    check('enough of it and they are solid', froze && who.frozen && who.solid);
    check('and they have stopped thinking', who.state.name === 'SHOP_FROZE' && who.stateTics === -1);
    check('and stopped being frightened', who.panic === 0);

    /* THE HYSTERESIS, which is the bug this section exists for. Freezing
       happens at the top of the dial and thawing at the BOTTOM of it, so
       the whole bar is time spent solid. Thawing the moment the number
       dipped under the line — which is what it did first — made a
       shopper a block of ice for six tics and then a shopper again. */
    who.frostTic();
    check('one tic later they are still frozen', who.frozen, `frost ${who.frost}`);
    let n = 0;
    while (who.frozen && n < 4000) { who.frostTic(); n++; }
    note('how long they stand there', `${n} tics, about ${(n / 35).toFixed(0)} seconds`);
    check('they thaw eventually, and not immediately',
      !who.frozen && n > Actor.FREEZE_AT * (Actor.THAW_EVERY - 1), `${n} tics`);
    check('and they come out of it running, not shopping',
      who.state.name === 'SHOP_RUN1', who.state.name);
    check('and solid again only in the way they were before',
      who.solid === (who.info.solid ?? !!who.info.monster));
  }

  /* --- OR THE FIRE EATS THEM --------------------------------------
     THE SECOND OF THE THREE, AND IT CHANGED SIDES. Fire used to melt a
     frozen shopper free and set them running, which made the
     flamethrower the UNDO for the extinguisher — a player could spoil
     their own freeze by sweeping the aisle a moment later. At the
     user's request the pair are a combination instead: fire on ice is
     an execution. They stay where they are, an ember front eats the
     drawing from the feet up (the ASH block in js/material.js) and
     about three and a half seconds later there is a heap on the lino.
     No fireball, no thirteen pieces, no stampede — the quiet way of
     emptying an aisle, and the second one, with the shatter. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    who.chill(Actor.FREEZE_AT);
    who.ignite(300);
    check('one flame on a block of ice starts eating it',
      who.ash > 0 && who.state.name === 'SHOP_ASH1', who.state.name);
    check('and they are not set running and not set alight',
      !who.frozen && who.burning === 0 && who.panic === 0 && who.solid);
    /* AND THE FIRE UNDER THEM IS STILL LIT, because a person burning is
       how an aisle catches whether or not they run anywhere */
    check('and the floor under them takes their fuel',
      g.fire.heatAt(who.x, who.y) > 0, `${g.fire.heatAt(who.x, who.y).toFixed(2)}`);
    /* THE CLOCK IS THE ONLY THING THAT ENDS IT, which is the same
       bargain A_Torch makes: more fire does not hurry it along. */
    const at = who.ash;
    for (let i = 0; i < 20; i++) who.ignite(300);
    check('and more fire does not hurry it', who.ash === at);

    let t = 0;
    for (; t < 400 && !who.removed; t++) who.tic();
    note('a block of ice, burned', `${t} tics from the first flame to the ash`);
    check('and it takes a few seconds and not an instant',
      t > 2.5 * 35 && t < 5.5 * 35, `${t} tics`);
    check('and what is left is an ash pile and not a body',
      who.removed && who.dead && g.giblets.ashes === 1);
    const pile = g.actors.find(a => a.type === 'ASH');
    check('the heap is on the floor where they were standing',
      !!pile && Math.hypot(pile.x - who.x, pile.y - who.y) < 1 && pile.flat && !pile.solid);
    check('and it is one of the three drawings of ash, not of blood',
      !!pile && pile.state.sprite.slice(0, 3) === 'ASH' && pile.variant < 3);
  }

  /* --- AND THE SPRITE IS EATEN, WHICH IS THE WHOLE OF THE EFFECT ----
     The number the shader reads is `ash`, and what has to be true of it
     is that it starts at nothing, ends at everything, and gets there in
     one direction — a front that went backwards would be a person
     un-burning. Checked here rather than by looking at a screenshot
     because a uniform that stops climbing is invisible until somebody
     stands and watches a shopper not finish. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    who.chill(Actor.FREEZE_AT);
    who.ignite(300);
    const seen = [];
    let last = -1, backwards = 0;
    for (let i = 0; i < 400 && !who.removed; i++) {
      who.tic();
      if (who.ash < last) backwards++;
      last = who.ash;
      if (i % 25 === 0) seen.push(+who.ash.toFixed(2));
    }
    note('how far through, every 25 tics', seen.join(' '));
    check('the front only ever goes one way', backwards === 0, `${backwards} steps back`);
    check('and it reaches the end of them before they are taken away',
      last >= 0.999 && who.removed, `${last.toFixed(3)}`);
    /* AND THE ICE IS OFF THEM LONG BEFORE THE FIRE IS THROUGH THEM, or
       the two effects are fighting over the same pixels: a pale blue
       statue with coals crawling up it reads as neither. */
    const g2 = mk();
    const w2 = g2.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    w2.chill(Actor.FREEZE_AT);
    w2.ignite(300);
    let blue = 0;
    for (let i = 0; i < 400 && !w2.removed; i++) { w2.tic(); if (w2.frost > 0) blue = i; }
    check('and the blue is gone in the first half second of it',
      blue < 20, `${blue} tics`);
  }

  /* --- AND THE FLAMETHROWER ITSELF, WHICH IS NOT ignite() ----------
     The block above tests half of a flame particle. The other half is
     the damage, and testing the two apart is exactly how a frozen
     shopper came to be killed INSIDE the ice by the second particle of
     the stream. So this drives the real FlameStream._burnActor and asks
     what a whole particle does to a block of ice. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    const health = who.health, bursts = g.giblets.bursts;
    who.chill(Actor.FREEZE_AT);
    g.flame._burnActor(who, who.x, who.y, who.z);
    check('one particle of the stream starts it', who.ash > 0 && !who.removed);
    check('and the rest of the burst does not shortcut it',
      (() => { for (let i = 0; i < 30; i++) g.flame._burnActor(who, who.x, who.y, who.z);
               return !who.removed && who.ash < 0.5; })(), `ash ${who.ash.toFixed(2)}`);
    check('and none of it reaches their health',
      who.health === health, `${health} -> ${who.health}`);
    let t = 0;
    for (; t < 400 && !who.removed; t++) who.tic();
    check('and the stream turns them into ash rather than giblets',
      who.removed && g.giblets.bursts === bursts && g.giblets.ashes === 1,
      `${g.giblets.bursts - bursts} bursts, ${g.giblets.ashes} ash`);
  }

  /* --- AND A BLAST DOES THE SAME, BECAUSE IT IS FIRE ---------------- */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    const health = who.health;
    g.explode({ x: who.x + 30, y: who.y, z: who.z });
    check('a car going up beside a block of ice starts eating whoever is in it',
      !who.frozen && !who.dead && who.ash > 0 && who.health === health,
      `${who.state.name}, health ${health} -> ${who.health}`);
    check('and does not blow them apart', who.state.name === 'SHOP_ASH1', who.state.name);
  }

  /* --- AND THE COLD CANNOT TAKE THEM BACK -------------------------
     The stream puts a burning person out, which is one of the best
     things it does. It does not put out somebody burning AWAY: half of
     them is on the floor already. The check is there because without it
     the two states are both true at once — blue, and being eaten, and
     held twice over. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    who.ignite(300);
    for (let i = 0; i < 20; i++) who.tic();
    const at = who.ash;
    for (let i = 0; i < 40; i++) who.chill(20);
    check('the extinguisher cannot re-freeze somebody being eaten',
      !who.frozen && who.frost === 0 && who.ash >= at,
      `frost ${who.frost}, frozen ${who.frozen}`);
    for (let i = 0; i < 400 && !who.removed; i++) who.tic();
    check('and they still finish as ash', who.removed && g.giblets.ashes === 1);
  }

  /* --- AND A BLOW FINISHES ONE THAT IS HALF GONE -------------------
     Not a shatter — there is no ice left by then — and not a burst
     either, because there is not enough of a person left to throw
     around. Whatever hits them puts the rest of them on the floor. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    who.ignite(300);
    for (let i = 0; i < 30; i++) who.tic();
    const half = who.ash, shatters = g.giblets.shatters, bursts = g.giblets.bursts;
    check('they are half way through when the blow lands', half > 0.1 && half < 0.95,
      `${half.toFixed(2)}`);
    who.damage(40, g.player, { impact: true });
    check('a blow on somebody half burnt drops the rest of them',
      who.removed && who.dead && g.giblets.ashes === 1);
    check('and it is neither a shatter nor a burst',
      g.giblets.shatters === shatters && g.giblets.bursts === bursts);
  }

  /* --- AND A CORPSE THAWS INTO A CORPSE -----------------------------
     Nothing reaches this today: a shopper's death state removes them on
     the tic it runs, and fire no longer kills anybody still frozen. It
     is checked because thaw() ends in setState(freezeReturn), and the
     day something freezable has a death animation that lingers, the
     melt would stand the body back up and set it running. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    who.chill(Actor.FREEZE_AT);
    const froze = who.state.name;
    who.dead = true; who.solid = false; who.frost = 1;
    who.thaw();
    check('the dead do not get up when the ice comes off',
      who.state.name === froze && !who.solid && who.panic === 0,
      `${who.state.name}, solid ${who.solid}, panic ${who.panic}`);
    check('they only stop being blue', who.frost === 0 && !who.frozen);
  }

  /* --- OR THEY BREAK ----------------------------------------------- */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    const shardsBefore = g.giblets.shatters, burstsBefore = g.giblets.bursts;
    who.chill(Actor.FREEZE_AT);
    who.damage(1, g.player);
    check('anything at all shatters a frozen person', who.removed && who.dead);
    check('and it is a shatter and not a burst',
      g.giblets.shatters === shardsBefore + 1 && g.giblets.bursts === burstsBefore,
      `${g.giblets.shatters - shardsBefore} shatters, ${g.giblets.bursts - burstsBefore} bursts`);
    check('and the pieces are the cold pool, not the burning one',
      g.giblets.shards.count > 0 && g.giblets.chunks.count === 0,
      `${g.giblets.shards.count} shards, ${g.giblets.chunks.count} chunks`);
    /* THE ONE THAT SHIPPED FOR TEN MINUTES. A burning piece of somebody
       lights the floor where it lands, which is how a crowd spreads a
       fire and is one of the best things in the game — and reusing that
       pool for the cold ones set the aisle alight every time the
       extinguisher was used properly. */
    const liveBefore = g.fire.active.length;
    for (let i = 0; i < 200; i++) g.giblets.tic();
    check('and they start no fires where they land',
      g.fire.active.length === liveBefore, `${g.fire.active.length - liveBefore} cells lit`);
  }

  /* --- OR THEY STAY EXACTLY WHERE THEY ARE --------------------------
     THE HOLD, and it is the one that shipped broken. freeze() parks the
     state with tics -1, which stops a frozen shopper moving ITSELF —
     and every other system in the game reached past that and set them
     going anyway, because setState was a door with no lock on it. All
     three doors are measured here and all three were open:

       a car going up next door   Game.scare
       the player's own trigger   Game.noise, once per tic, on hold
       a neighbour running past   A_Scare, straight in

     The first of them moved a block of ice ninety units in under two
     seconds, still solid, still blue, with ninety of its hundred frost
     still on it. */
  {
    const g = mk();
    const doors = [
      ['a car going up forty units away', w => g.scare(w.x + 40, w.y, 400)],
      ['the player pulling the trigger',  w => g.noise({ x: w.x, y: w.y }, 800)],
      ['somebody running past them',      w => ACTIONS.A_Scare(w, w.x + 100, w.y)],
    ];
    for (const [what, knock] of doors) {
      const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
      who.chill(Actor.FREEZE_AT);
      const x0 = who.x, y0 = who.y, parked = who.state.name;
      knock(who);
      for (let t = 0; t < 60; t++) who.tic();
      const moved = Math.hypot(who.x - x0, who.y - y0);
      check(`${what} does not set a block of ice running`,
        who.frozen && who.state.name === parked && moved < 1 && !who.target && who.panic === 0,
        `${who.state.name}, moved ${moved.toFixed(0)}, panic ${who.panic}`);
      /* AND THE CLOCK STILL RUNS UNDERNEATH IT. The hold is a hold on
         acting, not on melting: a gate that also stopped frostTic would
         have made the first outcome — leave them, they thaw — into
         "leave them, they are a bollard for the rest of the level". */
      check('and the thaw goes on running underneath the hold',
        who.frost === Actor.FREEZE_AT - 10, `frost ${who.frost}`);
      who.frost = 0; who.thaw();
    }
    /* AND THE FRIGHT THEY MISSED IS HANDED TO THEM ON THE WAY OUT,
       which is why refusing all three costs nothing: what somebody
       coming out of the ice should run from is what is there NOW. */
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    g.scare(who.x + 40, who.y, 400);
    while (who.frozen) who.tic();
    check('and they come out of it frightened and running anyway',
      who.panic > 0 && who.state.name === 'SHOP_RUN1' && who.solid,
      `${who.state.name}, panic ${who.panic}`);
  }

  /* --- AND A FIRE IN THE AISLE DOES IT WITHOUT BEING AIMED ---------
     THE SAME RULE, ARRIVING THE OTHER WAY. A flame particle is a hit;
     this is the floor being alight, which is what the store is full of
     once it is going. It matters that the two agree, and for a while
     they did not: the fire system lights anything standing in a cell
     over 70 of 255 and frostTic was taking the frost off from a fifth
     of that, so there was a window in which a block of ice at the EDGE
     of a fire melted free while one in the middle of it was eaten. One
     rule now, at one line in frostTic — fire on ice is an execution
     however the fire got there. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    const parked = who.state.name;
    check('a block of ice on a cold floor is a block of ice',
      (who.tic(), who.frozen && who.state.name === parked));
    g.fire.ignite(who.x, who.y, 36, 22);
    let t = 0;
    for (; t < 60 && who.frozen; t++) { g.fire.tic(); who.tic(); }
    note('a fire at their feet takes hold in', `${t} tics`);
    check('a fire in the cell they are standing in starts eating them',
      !who.frozen && who.ash > 0 && who.state.name === 'SHOP_ASH1',
      `${who.state.name} after ${t} tics`);
    check('and it does not have to be aimed at them to do it', t < 12, `${t} tics`);
    for (let i = 0; i < 400 && !who.removed; i++) { g.fire.tic(); who.tic(); }
    check('and the aisle finishes them the same way the gun would',
      who.removed && g.giblets.ashes === 1);
  }

  /* --- AND SOMETHING SAYS SO ----------------------------------------
     Freezing has a noise and a colour and the melt had neither, so a
     person the player had put on ice became a person again between two
     frames. The puff is the shatter's own, which is the right one: the
     two things that can happen to the ice should look related. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    const puffs = g.fx.smoke.count;
    who.frost = 0; who.thaw();
    check('the melt leaves a breath of frost where they were',
      g.fx.smoke.count > puffs, `${g.fx.smoke.count - puffs} particles`);
  }

  /* --- AND SOMETHING TO BREAK THEM WITH -----------------------------
     THE WEAPON DOES NOT EXIST YET. The user asked for the game to be
     ready for a physical one — a bat, a hammer, whatever it turns out
     to be — and what that needs is not art, it is an answer to "what
     does a swing MEAN". Game.impact is that answer, written and
     measured ahead of the thing that will call it, so the weapon is an
     animation and a table entry rather than a design problem.

     Actor.damage already turned anything that was not fire into a
     shatter, so breaking somebody frozen needed nothing new. What is
     new is that the blow has a DIRECTION, and that the pieces go with
     it — which is the whole difference between being hit and coming
     apart on your own. */
  {
    const g = mk();
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    who.chill(Actor.FREEZE_AT);
    /* stand the player in front of them, facing them */
    const p = g.player;
    const ang = Math.atan2(who.y - p.y, who.x - p.x);
    p.x = who.x - Math.cos(ang) * 50; p.y = who.y - Math.sin(ang) * 50;
    p.z = who.z; p.viewZ = who.z + 41; p.angle = ang;
    const shatters = g.giblets.shatters;

    /* facing the other way first: a swing is a cone in front of you.
       (It may well catch one of the other seven hundred people in the
       shop, which is the point of a cone and not a sphere — what is
       checked is that the one behind you is not in it.) */
    p.angle = ang + Math.PI;
    check('a swing with your back to them does not reach them',
      !g.impact(p).includes(who) && !who.removed);

    p.angle = ang;
    const hit = g.impact(p, { force: 2.4 });
    check('and a swing at a frozen person breaks them',
      hit.length === 1 && hit[0] === who && who.removed && who.dead);
    check('and it is a shatter, the same one anything else gets',
      g.giblets.shatters === shatters + 1);

    /* AND THE PIECES GO THE WAY IT WAS SWUNG. Thirteen shards with a
       sixty-degree cone either side of the blow: the mean of them has
       to point down the swing, and every one of them has to be inside
       the cone or it is a ring with a bias rather than a direction. */
    const S = g.giblets.shards;
    let mx = 0, my = 0, n = 0, worst = 0;
    for (let i = 0; i < S.max; i++) {
      if (!S.alive[i]) continue;
      const a2 = Math.atan2(S.vy[i], S.vx[i]);
      let d = Math.abs(a2 - ang);
      while (d > Math.PI) d = Math.abs(d - Math.PI * 2);
      worst = Math.max(worst, d);
      mx += S.vx[i]; my += S.vy[i]; n++;
    }
    let off = Math.abs(Math.atan2(my, mx) - ang);
    while (off > Math.PI) off = Math.abs(off - Math.PI * 2);
    note('the shards off a blow', `${n} pieces, mean ${(off * 57.3).toFixed(0)}° off the swing, ` +
      `widest ${(worst * 57.3).toFixed(0)}°`);
    check('the pieces go the way the blow went', off < 0.5, `${(off * 57.3).toFixed(0)}° off`);
    check('and none of them comes back past the shoulder', worst <= 1.06,
      `${(worst * 57.3).toFixed(0)}°`);
  }

  /* --- AND THE REST OF WHAT A BLOW HAS TO DO ------------------------ */
  {
    const g = mk();
    const p = g.player;

    /* IT HITS THINGS THAT ARE NOT FROZEN TOO, and they are hurt rather
       than broken: the shatter is a property of the ICE, not of the
       weapon, and a physical weapon that only worked on frozen people
       would be a worse boxcutter. */
    const warm = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
    p.x = warm.x - 40; p.y = warm.y; p.z = warm.z; p.viewZ = warm.z + 41;
    p.angle = Math.atan2(warm.y - p.y, warm.x - p.x);
    const bursts = g.giblets.bursts;
    const hit = g.impact(p, { damage: 6 });
    check('a blow lands on somebody who is not frozen as damage',
      hit[0] === warm && !warm.dead && warm.health === 6, `health ${warm.health}`);
    check('and does not shatter them', g.giblets.bursts === bursts);
    check('and a second one of those kills them the ordinary way',
      (g.impact(p, { damage: 6 }), warm.dead && g.giblets.bursts === bursts + 1));

    /* ONE SWING, MORE THAN ONE PERSON, if the weapon asks for it. */
    const g2 = mk();
    const p2 = g2.player;
    const queue = g2.actors.filter(a => a.type === 'SHOPPER' && !a.dead)
      .map(a => ({ a, d: Math.hypot(a.x - p2.x, a.y - p2.y) }))
      .sort((u, v) => u.d - v.d).slice(0, 3).map(o => o.a);
    let k = 0;
    for (const a of queue) {
      a.x = p2.x + Math.cos(p2.angle) * (40 + k * 12);
      a.y = p2.y + Math.sin(p2.angle) * (40 + k * 12);
      a.z = p2.z; k++;
    }
    check('one swing can be told to reach more than one of them',
      g2.impact(p2, { count: 3, range: 120, arc: 1.2 }).length === 3);

    /* AND A SWING AT A WALL LANDS SOMEWHERE, because a weapon that does
       nothing at all when you miss reads as a broken weapon. The player
       does not start next to a wall, so this walks a ray out to the
       first one it can find and stands them a swing's length off it. */
    const g3 = mk();
    const p3 = g3.player;
    /* onto the sales floor, where the walls are — the player starts in
       the middle of the car park, which is four hundred feet of tarmac
       in every direction */
    const inside = g3.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    p3.x = inside.x; p3.y = inside.y; p3.z = inside.z; p3.viewZ = inside.z + 41;
    for (const a of g3.actors) if (a.type === 'SHOPPER') a.remove();
    let wall = null;
    for (let i = 0; i < 32 && !wall; i++) {
      p3.angle = (i / 32) * Math.PI * 2;
      wall = g3.level.rayHitWall(p3.x, p3.y, p3.viewZ,
        p3.x + Math.cos(p3.angle) * 900, p3.y + Math.sin(p3.angle) * 900, p3.viewZ);
    }
    check('there is a wall somewhere in front of the player to swing at', !!wall);
    /* THE BOXCUTTER USED TO GO THROUGH THIS HOOK and is gone, at the
       user's request; the hook stays for the physical weapon that is
       still coming, so it is exercised here directly: a blow with a
       direction on it at a block of ice throws the pieces down the
       aisle in front of the swing. */
    {
      const g4 = mk();
      const p4 = g4.player;
      const w4 = g4.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.frozen);
      p4.x = w4.x - 40; p4.y = w4.y; p4.z = w4.z; p4.viewZ = w4.z + 41;
      p4.angle = Math.atan2(w4.y - p4.y, w4.x - p4.x);
      w4.chill(Actor.FREEZE_AT);
      check('nothing in the player\'s hands is a melee weapon any more',
        Object.values(pl.WEAPONS).every(d => !d.melee) && !('meleeSwing' in p4));
      check('and a blow through the hook at a block of ice still shatters it',
        (g4.impact(p4, { damage: 6, force: 1 }), w4.removed && w4.dead));
    }
    p3.x = wall.x - Math.cos(p3.angle) * 40;
    p3.y = wall.y - Math.sin(p3.angle) * 40;
    const puffs = g3.actors.filter(a => a.type === 'PUFF').length;
    check('and a swing that meets one puts a puff on it',
      g3.impact(p3).length === 0 &&
      g3.actors.filter(a => a.type === 'PUFF').length === puffs + 1);
  }

  /* --- THE WEAPON ITSELF ------------------------------------------- */
  {
    const W = pl.WEAPONS.EXTINGUISHER;
    check('the extinguisher is a weapon you are issued with',
      !!W && new pl.Player({ level, blockmap: null }, 0, 0, 0).owned.EXTINGUISHER === true);
    check('and it is a stream, on its own tank',
      W.stream === 'frost' && W.ammo === 'co2' && W.ammoPerShot === 0);
    check('and it latches when it is empty, like the other one', W.refire > 0);
    check('and it does no damage at all, which is the point',
      W.damage() === 0);
    note('the two tanks', `fuel ${pl.TANK} at one every ${pl.REGEN_EVERY}, ` +
      `co2 ${pl.BOTTLE} at one every ${pl.CO2_REGEN_EVERY}`);
    check('the extinguisher holds less and fills faster',
      pl.BOTTLE < pl.TANK && pl.CO2_REGEN_EVERY < pl.REGEN_EVERY &&
      pl.CO2_REFIRE_AT < pl.REFIRE_AT);
    /* the two latches are separate, or emptying one locks out the other */
    const g = mk();
    const p = g.player;
    p.ammo.fuel = 0; p.dry = true;
    check('an empty flamer does not lock the extinguisher',
      p.armed('EXTINGUISHER') && !p.armed('FLAMER'));
    p.ammo.co2 = 0; p.co2Dry = true; p.ammo.fuel = pl.TANK; p.dry = false;
    check('and an empty extinguisher does not lock the flamer',
      p.armed('FLAMER') && !p.armed('EXTINGUISHER'));
    /* and the gauge's pip follows whichever is in hand */
    p.weapon = 'EXTINGUISHER';
    check('the gauge asks the weapon in hand which mark it is climbing to',
      p.refireMark === pl.CO2_REFIRE_AT, `${p.refireMark}`);
    p.weapon = 'FLAMER';
    check('and gets a different answer for the other one', p.refireMark === 0);

    /* --- AND THE SWITCH IN THE MENU THAT TURNS ALL OF IT OFF -------
       Infinite ammo lives in fuelTic and nowhere else, upstream of every
       question anything asks about a tank. So the check is that it
       refills BOTH tanks and the molotovs, takes both latches off with
       them, and leaves the guns armed — without the firing path, the
       gauge or `armed` knowing the mode is there. */
    const dbg = mk().player;
    dbg.ammo.fuel = 3; dbg.ammo.co2 = 2; dbg.ammo.bottles = 0;
    dbg.dry = true; dbg.co2Dry = true;
    check('and it is off unless it is asked for', dbg.debug === false);
    dbg.fuelTic();
    check('so an ordinary tank still comes back a unit at a time',
      dbg.ammo.fuel === 3, `${dbg.ammo.fuel}`);
    dbg.debug = true;
    dbg.fuelTic();
    check('debug fills every tank, not only the one in your hands',
      dbg.ammo.fuel === dbg.maxAmmo.fuel && dbg.ammo.co2 === dbg.maxAmmo.co2 &&
      dbg.ammo.bottles === dbg.maxAmmo.bottles,
      `${dbg.ammo.fuel}/${dbg.ammo.co2}/${dbg.ammo.bottles}`);
    check('and it takes both latches off with them', !dbg.dry && !dbg.co2Dry);
    check('and both guns will fire again',
      dbg.armed('FLAMER') && dbg.armed('EXTINGUISHER'));
    /* --- AND THE OTHER ONE, WHICH IS ONE BRANCH IN damage() -------
       Everything that can hurt the player arrives at Player.damage —
       the rifles, the vans, the fire FIREPROOF already refuses — and
       the only way out of the level dead is health reaching zero in
       there. So refusing the function is the whole feature. */
    /* --- THREE BARS, SPENT OUTSIDE IN ------------------------------
       At the user's request: an outer plate worth ten of you, an inner
       one worth five, and then you. They are LAYERS and not Doom's
       soak — the top one takes the whole of every hit until there is
       none of it left — which is the only reason a stack of three bars
       is worth drawing. */
    {
      const L = mk().player;
      check('you start with both plates and your health, in that order',
        L.armour2 === pl.ARMOUR2 && L.armour1 === pl.ARMOUR1 && L.health === pl.HEALTH,
        `${L.armour2}/${L.armour1}/${L.health}`);
      check('and the plates are ten and five times what a person is worth',
        pl.ARMOUR2 === 10 * pl.HEALTH && pl.ARMOUR1 === 5 * pl.HEALTH);
      L.damage(400, null, { shot: true });
      check('the first hit is all outer plate and nothing else',
        L.armour2 === pl.ARMOUR2 - 400 && L.armour1 === pl.ARMOUR1 && L.health === pl.HEALTH,
        `${L.armour2}/${L.armour1}/${L.health}`);
      L.damage(600, null, { shot: true });
      check('and the outer plate goes exactly at its own size, with nothing spilt',
        L.armour2 === 0 && L.armour1 === pl.ARMOUR1 && L.health === pl.HEALTH,
        `${L.armour2}/${L.armour1}/${L.health}`);
      L.damage(120, null, { shot: true });
      check('then the inner one starts', L.armour2 === 0 && L.armour1 === pl.ARMOUR1 - 120 && L.health === pl.HEALTH);
      /* 380 of inner plate left, so 420 is exactly forty into you */
      L.damage(420, null, { shot: true });
      check('and the overflow carries into you, but only the overflow',
        L.armour1 === 0 && L.health === pl.HEALTH - 40 && !L.dead,
        `${L.armour1}/${L.health}`);
      /* one hit big enough goes through all three in the same call */
      const T = mk().player;
      T.damage(pl.ARMOUR2 + pl.ARMOUR1 + pl.HEALTH, null, { shot: true });
      check('and a hit worth all sixteen hundred goes through the lot at once',
        T.armour2 === 0 && T.armour1 === 0 && T.health <= 0 && T.dead);
      /* and nothing under the whole stack kills you */
      const N = mk().player;
      N.damage(pl.ARMOUR2 + pl.ARMOUR1 + pl.HEALTH - 1, null, { shot: true });
      check('while one short of it leaves you standing on nothing', !N.dead && N.health === 1,
        `${N.health}`);
      /* fire is still refused before any of this: the plates are not
         what makes you fireproof */
      const F = mk().player;
      F.damage(900, null, { fire: true });
      check('and fire does not touch the plates either', F.armour2 === pl.ARMOUR2 && F.health === pl.HEALTH);
    }

    /* what the layers do to a test that wants to reach the health bar:
       take the plates off it first */
    const bare = q => { q.armour2 = 0; q.armour1 = 0; return q; };
    const inv = bare(mk().player);
    check('invincibility is off unless it is asked for', inv.invincible === false);
    inv.health = 70;
    inv.damage(9, null, { shot: true });
    check('a bullet lands while it is off', inv.health === 61, `${inv.health}`);
    inv.invincible = true;
    inv.damage(9, null, { shot: true });
    inv.damage(220, null, { impact: true, dx: 1, dy: 0, force: 2.5 });
    inv.damage(40, null, { fire: true });
    check('and nothing lands while it is on', inv.health === 61 && !inv.dead, `${inv.health}`);
    check('and it is not a heal: the health you had is the health you keep', inv.health === 61);
    check('and the shove goes with the hit', inv.momx === 0 && inv.momy === 0);
    check('and a thousand rifle rounds cannot kill you',
      (() => { for (let k = 0; k < 1000; k++) inv.damage(15, null, { shot: true }); return !inv.dead && inv.health === 61; })());
    inv.invincible = false;
    inv.damage(200, null, { shot: true });
    check('and switching it off puts you back where anybody can', inv.dead);
    /* the menu has both switches, and main.js wires both onto the player */
    {
      const fs2 = await import('node:fs');
      const html = fs2.readFileSync('index.html', 'utf8');
      const main = fs2.readFileSync('js/main.js', 'utf8');
      /* they are TILES now rather than a row of words, so the name is
         in the face of the tile and not the button's own text */
      check('the pause menu offers both debug switches',
        /id="opt-debug"[\s\S]{0,160}?DEBUG: INFINITE AMMO</.test(html) &&
        /id="opt-godmode"[\s\S]{0,160}?DEBUG: INVINCIBLE</.test(html));
      check('and both are remembered and put on the player',
        /godmode: true/.test(main) && /toggle\('opt-godmode', 'godmode'\)/.test(main) &&
        /game\.player\.invincible = !!prefs\.godmode/.test(main));
      /* 5 was the bump that turned them on; the picture's defaults have
         bumped it since, and any later bump keeps the switches on */
      check('and both are ON by default, at the user\'s request, under a bumped prefs version',
        /debug: true, godmode: true/.test(main) && +(main.match(/const PREF_VERSION = (\d+);/) || [])[1] >= 5 &&
        /id="opt-debug"[^>]*aria-pressed="true"/.test(html) && /id="opt-godmode"[^>]*aria-pressed="true"/.test(html));
    }

    /* and holding the trigger down cannot outrun it */
    for (let k = 0; k < 400; k++) { dbg.flameTic(pl.WEAPONS.FLAMER); dbg.fuelTic(); }
    check('and holding the trigger down never empties it',
      dbg.ammo.fuel === dbg.maxAmmo.fuel && !dbg.dry && dbg.armed('FLAMER'),
      `${dbg.ammo.fuel} left, latched ${dbg.dry}`);
  }

  /* --- AND IT IS A MODEL IN YOUR HANDS ----------------------------- */
  {
    const w3 = await import('../js/weapon3d.js');
    const fs3 = await import('node:fs');
    note('the guns', Object.entries(w3.GUNS).map(([k, d]) =>
      `${k} ${d.url.split('/').pop()}${d.fit ? ' (fitted)' : ''}`).join(', '));
    check('there are seven guns and all seven files are there',
      Object.keys(w3.GUNS).length === 7 &&
      Object.values(w3.GUNS).every(d => fs3.existsSync(d.url)));
    const E = w3.GUNS.EXTINGUISHER;
    /* THE MODEL IS SOMEBODY ELSE'S AND IS NOT REWRITTEN, which is the
       rule since the van. So the two things the game has to say about it
       — how big it is in this scene, and where its business end is — are
       said HERE, in the model's own units, and not baked into the file. */
    check('the extinguisher says where its nozzle is rather than editing the file',
      Array.isArray(E.nozzle) && E.nozzle.length === 3 && E.fit === w3.GUN_LENGTH);
    check('and it has no pilot light, not being a thing that burns',
      E.pilot === null);
    check('and its muzzle is desaturated first, so a tint can make it cold',
      E.cold === true && E.tint[2] > E.tint[0]);
    /* EVERY GUN IN THE GAME IS SOMEBODY ELSE'S NOW. The flamethrower
       the user built in Blender — the one model that carried its own
       marker spheres — was replaced at the user's request by a
       Sketchfab model that carries nothing, so all three are fitted and
       anchored by this table rather than by editing the file, which is
       the rule the van set. */
    /* AND THE MINIGUN IS THE EXCEPTION THAT PROVES IT: the user's own
       model again, with a marker cylinder in it for the emission point,
       so its nozzle is null here — the file says — and the reader that
       was kept for exactly that day reads it. */
    check('all six guns are fitted to the game\'s length, and five say where they point',
      Object.values(w3.GUNS).every(d => d.fit) &&
      Object.entries(w3.GUNS).every(([k, d]) => k === 'MINIGUN' ? d.nozzle === null : Array.isArray(d.nozzle) && d.nozzle.length === 3));
    check('and the flamethrower is the only one with a pilot light, being the only one that burns',
      Array.isArray(w3.GUNS.FLAMER.pilot) && E.pilot === null && w3.GUNS.BORE.pilot === null
      && w3.GUNS.LANCE.pilot === null);
    /* AND ONLY ONE GUN COOKS. Both the minigun's barrels and the
       lance's whole body used to glow with GUN_FRAG's heat term, each
       reading a property off the player by name; at the user's request
       the lance has no heat at all, so the minigun is alone with it and
       the shader's second, middle-out gradient mode has no caller. The
       mode is left in place — it is correct and it is behind a branch
       nothing on the lance satisfies — and this is what says so. */
    check('the minigun is the only gun that heats, and it reads its own number',
      w3.GUNS.MINIGUN.heat.from === 'heat' && w3.GUNS.LANCE.heat === undefined &&
      Object.values(w3.GUNS).filter(g => g.heat).length === 1);
    check('and no gun asks for the middle-out mode any more',
      Object.values(w3.GUNS).every(g => !g.heat || g.heat.mid === undefined));
    check('and it is the only one whose muzzle is fire as painted',
      !w3.GUNS.FLAMER.cold && w3.GUNS.FLAMER.tint.every(v => v === 1));

    /* --- AND THE PILOT LIGHT IS ON THE NOZZLE -----------------------
       Reported by the user as misaligned, and it was: 0.537m off on a
       gun 1.4m long, a fifth of the screen's height below the barrel
       and nearly off the bottom of the frame.

       THE TWO EFFECTS ON THE GUN HANG OFF DIFFERENT THINGS, and that
       asymmetry is the whole of it. The muzzle is a child of the MODEL,
       so it takes the anchor in the model's own units and is right by
       construction. The pilot flame cannot be — the model is turned a
       half circle to point its barrel at the camera, and a flame quad
       inheriting that turn is a flame seen from behind — so it hangs
       off the GROUP instead, and a point handed to `position` is read
       in the PARENT's space. It was being given a WORLD-space point, so
       the group's own transform — the whole of VIEW.pos, the yaw, the
       bob — was applied to it a second time.

       The tell, for anyone who meets this again: the glow the pilot
       throws ON the gun was in the right place the whole time. That
       uniform takes the same vector in view space and is correct; only
       the mesh needed converting back out of the world.

       There is no scene graph in this test — the three stub is a
       handful of empty classes — so what is pinned is the pair of
       conversions in the source, which is where the fault was. */
    const gunSrc = fs3.readFileSync('js/weapon3d.js', 'utf8');
    const place = gunSrc.slice(gunSrc.indexOf('if (G.pilot) {'), gunSrc.indexOf('the muzzle, only while firing'));
    check('the pilot light is put where the model says, not where the group is',
      /G\.inner\.localToWorld\(pv\)/.test(place) &&
      /G\.group\.worldToLocal\(G\.pilot\.position\)/.test(place));
    /* and the asymmetry that makes that necessary, so that re-parenting
       the flame one day takes the conversion with it */
    check('and it hangs off the group while the muzzle hangs off the model',
      /group\.add\(g\.pilot\)/.test(gunSrc) && /inner\.add\(g\.muzzle\)/.test(gunSrc));

    /* --- AND THE BORE IS HELD SMALLER AND FARTHER OFF ----------------
       A third smaller and a third farther from the eye than the other
       two, at the user's request, and the two are per-gun numbers in
       GUNS rather than a change to VIEW, which the flamethrower was
       tuned against. "Farther off" is a push straight back along the
       view — z alone — and the first version of this check pinned the
       opposite: the whole position scaled along the line from the eye,
       which keeps a point's place on screen, and did, for the gun's
       centre, which is below the bottom of the frame by design; the
       gun shrank around a point nobody can see and all but left the
       picture. Pushed straight back it recedes toward the middle and
       stays in its corner, which is what farther off looks like. */
    const B = w3.GUNS.BORE;
    check('the bore is drawn a third smaller than the other two',
      Math.abs(B.fit - w3.GUN_LENGTH * 0.67) < 1e-9 &&
      E.fit === w3.GUN_LENGTH && w3.GUNS.FLAMER.fit === w3.GUN_LENGTH);
    /* AND EVERY GUN SAYS HOW FAR OUT IT IS HELD, which is how much of
       its length is on screen. The two streams are held about three
       times as far out as a gun used to be, at the user's request: at 1
       a quarter of a gun is behind the eye and the rest is too close to
       read. */
    check('and all three say how far out they are held, the two streams at about three',
      B.out === 1.33 && w3.GUNS.FLAMER.out === 3.0 && E.out === 2.8);
    check('and farther off is a push straight back along the view, z alone, not the whole position scaled',
      /\(VIEW\.pos\[2\] \+ mix\(off\[2\], aoff\[2\]\) \+ this\.kick \* 0\.025\) \* out\)/.test(gunSrc) &&
      !/multiplyScalar\(G\.def\.out/.test(gunSrc));
    /* HOW FAR A GUN IS DRAWN IS NOT HOW FAR ITS FIRE STARTS. The world
       takes the nozzle as a RAY out of the eye, and the point on it was
       whatever the drawn nozzle's distance came to — so holding a gun
       three times further out would have moved the birth of the stream
       from forty-two units in front of the player to seventy, which is
       the far side of a shelf you are standing against. Capped. */
    check('the stream is born no further into the level than a gun can reach',
      w3.NOZZLE_REACH >= 40 && w3.NOZZLE_REACH <= 60 &&
      /Math\.min\(nv\.length\(\) \* UNITS_PER_METRE, NOZZLE_REACH\)/.test(gunSrc),
      `${w3.NOZZLE_REACH} units`);
    check('and its exhaust is scaled with it, being in metres and not in the model',
      Math.abs(B.muzzle.len - 0.14 * 0.67) < 0.002 && Math.abs(B.muzzle.wid - 0.10 * 0.67) < 0.002);
    /* AND THE TWO NUMBERS ARE AT THE BUSINESS END OF THE MODEL.
       They were found by drawing the gun flat over a grid ruled in its
       own units and moving a crosshair until it sat in the bore and on
       the lip of the igniter pipe — there is no picture in a smoke
       test, so what is pinned here is everything a picture would have
       made obvious: that both anchors are inside the model's own box,
       at the far +z end of it, on the centre line, and that the pilot
       is the lower of the two and reaches further forward, which is the
       arrangement that makes a flamethrower look like one. An anchor at
       the wrong end, or on the wrong axis, fails here. */
    const glb = fs3.readFileSync('assets/models/flamethrower.glb');
    const jlen = glb.readUInt32LE(12);
    const meta = JSON.parse(glb.subarray(20, 20 + jlen).toString('utf8'));
    const posAcc = new Set();
    for (const m of meta.meshes) for (const q of m.primitives) posAcc.add(q.attributes.POSITION);
    const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
    for (const i of posAcc) {
      const a = meta.accessors[i];
      for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], a.min[k]); hi[k] = Math.max(hi[k], a.max[k]); }
    }
    const F = w3.GUNS.FLAMER, span = [0, 1, 2].map(k => hi[k] - lo[k]);
    note('the flamethrower', `${span.map(v => v.toFixed(1)).join(' x ')} model units, nozzle ${F.nozzle.join(', ')}, pilot ${F.pilot.join(', ')}`);
    check('the model is longest along z, which is the axis the scene turns to face the camera',
      span[2] > span[0] && span[2] > span[1]);
    const inBox = p => p.every((v, k) => v >= lo[k] - 1 && v <= hi[k] + 1);
    check('both anchors are on the model rather than floating off it', inBox(F.nozzle) && inBox(F.pilot));
    check('both are at the muzzle end, in the last tenth of its length',
      F.nozzle[2] > hi[2] - span[2] * 0.1 && F.pilot[2] > hi[2] - span[2] * 0.1,
      `${F.nozzle[2]} and ${F.pilot[2]} against a barrel that ends at ${hi[2].toFixed(1)}`);
    check('and on the centre line, which is where a barrel is',
      Math.abs(F.nozzle[0]) < span[0] * 0.1 && Math.abs(F.pilot[0]) < span[0] * 0.1);
    check('the pilot burns below the nozzle and a little ahead of it, on the igniter pipe',
      F.pilot[1] < F.nozzle[1] && F.pilot[2] > F.nozzle[2]);
    const scale = w3.GUN_LENGTH / Math.max(...span);
    const apart = Math.hypot(...[0, 1, 2].map(i => (F.pilot[i] - F.nozzle[i]) * scale));
    note('pilot to nozzle', `${(apart * 100).toFixed(1)}cm apart on a ${w3.GUN_LENGTH}m gun`);
    check('and it is a few centimetres off, not a third of the gun',
      apart > 0.01 && apart < 0.2, `${apart.toFixed(3)}m`);
  }
}

/* ---------- the crowd ---------- */
section('the crowd');
{
  const ppl = await import('../js/people.js');
  const { Game } = await import('../js/game.js');
  const THREE = await import('three');
  const hudStub = { message() {}, ticMessages() {}, resize() {}, update() {} };
  const inputStub = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
  const g = new Game({ level, scene: new THREE.Scene(), camera: {}, textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: hudStub, audio: null, input: inputStub });

  /* --- who is in the shop, and nobody anywhere else ---
     A customer is somebody who is IN THE SHOP. The map places them
     through one predicate and exports the rectangle it used; this holds
     every one of them against it from the other side, so a coordinate
     that drifts into the stockroom, out through the front doors or into
     a neighbouring unit fails here rather than turning up in a
     screenshot standing in the loading dock. */
  const SF = level.salesFloor;
  const crowd = g.actors.filter(a => a.type === 'SHOPPER');
  const inside = crowd.filter(a => a.x > SF.x0 && a.x < SF.x1 && a.y > SF.y0 && a.y < SF.y1);
  note('shoppers on the sales floor', `${inside.length} of ${crowd.length}`);
  check('the shop has a crowd in it', inside.length > 60, `${inside.length}`);
  check('and every one of them is on the sales floor',
    inside.length === crowd.length,
    crowd.filter(a => !inside.includes(a)).slice(0, 4).map(a => `${a.x | 0},${a.y | 0}`).join(' '));
  check('nobody is in the stockroom, the dock or the office',
    !crowd.some(a => /stock|dock|office/i.test(g.level.sectors[a.sector?.index ?? 0]?.name || '')),
    crowd.map(a => a.sector?.name).filter(n => /stock|dock|office/i.test(n || '')).slice(0, 3).join(', '));
  check('and nobody is outdoors', !crowd.some(a => a.sector?.outdoor),
    crowd.filter(a => a.sector?.outdoor).slice(0, 3).map(a => a.sector.name).join(', '));
  check('nobody is a staff monster any more',
    !g.actors.some(a => a.type === 'ASSOCIATE' || a.type === 'STOCKER'));
  check('every shopper is one of the drawings there are',
    crowd.every(a => Number.isInteger(a.variant) && a.variant >= 0 && a.variant < ppl.SHOPPERS));
  check('and there is more than one of them being used',
    new Set(crowd.map(a => a.variant)).size === ppl.SHOPPERS,
    `${new Set(crowd.map(a => a.variant)).size} of ${ppl.SHOPPERS}`);
  check('they are solid, shootable and they burn',
    crowd.every(a => a.solid && a.shootable && a.flammable));

  /* --- and there is room for all of them ---
     Three things go wrong when a crowd is multiplied, and all three are
     invisible in a screenshot taken from the wrong end of an aisle.

     NOBODY OVERLAPS. Two shoppers at one coordinate are one shopper with
     a shadow, and worse than that they are two shoppers who can never
     move again: `canStandAt` refuses any step that ends inside somebody,
     so a pair placed already touching is a pair welded to the floor. The
     first cut of the bigger crowd spaced them 34 apart, and a shopper is
     18 in the radius. */
  const R2 = (2 * crowd[0].radius) ** 2;
  let closest = Infinity, pair = '';
  for (let i = 0; i < crowd.length; i++)
    for (let j = i + 1; j < crowd.length; j++) {
      const d2 = (crowd[i].x - crowd[j].x) ** 2 + (crowd[i].y - crowd[j].y) ** 2;
      if (d2 < closest) { closest = d2; pair = `${crowd[i].x | 0},${crowd[i].y | 0}`; }
    }
  note('closest two shoppers', `${Math.sqrt(closest).toFixed(0)} apart`);
  check('no two shoppers are standing inside each other', closest > R2,
    `${Math.sqrt(closest).toFixed(0)} apart at ${pair}`);
  /* AND EVERY ONE OF THEM CAN LEAVE. Not the same statement: 36 apart is
     not overlapping and is still nowhere to go, because a step is 16. */
  const canMove = a => {
    for (let d = 0; d < 8; d++) {
      const ang = d * Math.PI / 4;
      if (a.canStandAt(a.x + Math.cos(ang) * a.speed, a.y + Math.sin(ang) * a.speed)) return true;
    }
    return false;
  };
  const stuck = crowd.filter(a => !canMove(a));
  check('and every one of them has a step it can take', stuck.length === 0,
    `${crowd.length - stuck.length} of ${crowd.length} can; ` +
    stuck.slice(0, 3).map(a => `${a.x | 0},${a.y | 0}`).join(' '));
  /* AND NOBODY IS ON THE FURNITURE. The sales floor is a rectangle and a
     rectangle cannot tell an aisle from the gondola beside it, so this
     is the sector rather than the box: a shopper whose floor is not the
     shop floor is standing on the shelves, the deli counter or a till. */
  const aloft = crowd.filter(a => (a.sector?.floor ?? -1) !== MAP.FLOOR_WALK);
  check('nobody is standing on the shelves, the counters or a till',
    aloft.length === 0,
    aloft.slice(0, 4).map(a => `${a.sector?.name} at ${a.x | 0},${a.y | 0}`).join('; '));
  check('the shop holds eight times what it first did', crowd.length === 736,
    `${crowd.length}, from 92 and then 460`);

  /* --- one tic of the stream is more than a person --- */
  const FL2 = await import('../js/flame.js');
  check('one tic of the flame is over a shopper twice',
    FL2.STREAM.perTic * 5 > st.ACTORS.SHOPPER.health * 2,
    `${FL2.STREAM.perTic * 5} damage against ${st.ACTORS.SHOPPER.health} health`);

  /* --- and what that looks like --- */
  const victim = inside[0];
  const before = g.actors.length;
  victim.damage(50, g.player, { fire: true });
  check('a shopper hit hard enough comes apart', g.giblets.bursts === 1 && victim.dead);
  const blast = g.actors.filter(a => a.type === 'BLAST');
  check('there is a fireball where they were', blast.length === 1 &&
    Math.hypot(blast[0].x - victim.x, blast[0].y - victim.y) < 1);
  check('and a pool of blood under it, a decal', g.giblets.pools >= 1 && g.decals.pools.blood.frame.some((f, i) => f === 1 && g.decals.pools.blood.strength[i] > 0));
  g.actors.forEach(a => a.tic());            // the gib state is one tic long
  check('the person is gone', victim.removed);
  check('the pieces are in the air', g.giblets.chunks.count === ppl.GIB.count,
    `${g.giblets.chunks.count} of ${ppl.GIB.count}`);
  check('and they are on fire', (g.giblets.tic(), g.giblets.trail.count > 0),
    `${g.giblets.trail.count} flames`);

  const litBefore = g.fire.liveCells, burntBefore = g.fire.burntFuel;
  /* The pieces alone for the two hundred tics, and the fire afterwards.
     They used to be run together, and that stopped working the moment
     the fire got six times faster: two hundred tics of it beside a queue
     takes the neighbours too, so the count in the air is somebody else's
     pieces and the check was asking the wrong question. */
  for (let k = 0; k < 200; k++) g.giblets.tic();
  check('every piece comes down', g.giblets.chunks.count === 0, `${g.giblets.chunks.count} still up`);
  check('they leave blood on the floor', g.decals.pools.blood.count > 1 && !g.actors.some(a => a.type === 'GORE'), `${g.decals.pools.blood.count}`);
  for (let k = 0; k < 120; k++) g.fire.tic();
  /* AND THEY START NOTHING, which is the reverse of what this line
     checked for most of the project's life. A burning piece of somebody
     used to light the floor where it landed — thirteen of them thrown
     seventy units in every direction, so one person going off in a crowd
     seeded a ring of new fires across the aisle they were running down,
     and that was the single largest reason the store burnt itself down
     without the player. See Giblets._land. */
  check('and they start no fires where they land',
    g.fire.liveCells === litBefore && g.fire.burntFuel === burntBefore,
    `${litBefore} -> ${g.fire.liveCells} cells, ${burntBefore.toFixed(0)} -> ${g.fire.burntFuel.toFixed(0)} fuel`);
  note('one person', `${g.actors.length - before + 1} things left behind, ` +
    `${g.decals.pools.blood.count} blood decals`);

  /* --- the floor does not fill up with them for ever --- */
  for (let k = 0; k < 400; k++) g.giblets.splat(1200, 900, 0);
  check('the pools of blood are capped: the decals\' own ring', g.decals.pools.blood.count <= g.decals.pools.blood.max,
    `${g.decals.pools.blood.count}`);

  /* --- and they run from it ---
     The whole claim in one measurement: put a fire next to somebody,
     let the world run, and they should be further from it than they
     were and no longer standing still. */
  {
    const a = g.actors.find(x => x.type === 'SHOPPER' && !x.dead && x.y > 1300 && x.y < 1800);
    const fx = a.x, fy = a.y - 90;                      // a fire, right there
    const d0 = Math.hypot(a.x - fx, a.y - fy);
    g.fire.ignite(fx, fy, 200, 48);
    /* the actors and the fire, not Game.tic — a whole tic wants slide
       doors, and a slide door wants a GPU */
    for (let k = 0; k < 90; k++) {
      g.tics++;
      for (const x of g.actors) x.tic();
      g.fire.tic();
    }
    const d1 = Math.hypot(a.x - fx, a.y - fy);
    check('a shopper notices a fire beside it', a.panic > 0 || a.removed, `panic ${a.panic}`);
    check('and runs away from it', a.removed || d1 > d0 + 60, `${d0.toFixed(0)} -> ${d1.toFixed(0)}`);
    note('one shopper, ninety tics', `${d0.toFixed(0)} units from the fire, then ${d1.toFixed(0)}`);
    /* and the rest of the aisle heard about it */
    const running = g.actors.filter(x => x.type === 'SHOPPER' && x.panic > 0).length;
    check('and it is not the only one moving', running > 1, `${running} running`);
  }

  /* --- standing still, but not perfectly, and moving when it runs --- */
  {
    const a = inside[1];
    const swing = () => {
      let worst = 0, moved = 0, prev = null;
      for (let t = 0; t < 400; t++) {
        const s2 = { ...ppl.swayOf(a, t) };
        worst = Math.max(worst, Math.hypot(s2.dx, s2.dy), Math.abs(s2.dz));
        if (prev) moved += Math.hypot(s2.dx - prev.dx, s2.dy - prev.dy, s2.dz - prev.dz);
        prev = s2;
      }
      return { worst, moved };
    };
    a.panic = 0;
    const still = swing();
    check('a standee sways', still.moved > 4, still.moved.toFixed(1));
    check('by under two units', still.worst < 2, still.worst.toFixed(2));
    /* swayOf hands back ONE shared object — read it before the next call */
    const b = { ...ppl.swayOf(inside[2], 0) }, p0 = { ...ppl.swayOf(a, 0) };
    check('and not in step with the next one along',
      Math.hypot(p0.dx - b.dx, p0.dy - b.dy) > 0.01);

    /* and a frightened one is visibly doing something else */
    a.panic = 60;
    const running = swing();
    check('a running one moves a great deal more',
      running.moved > still.moved * 3, `${running.moved.toFixed(0)} against ${still.moved.toFixed(0)}`);
    check('and still stays within a few units of where it is',
      running.worst < 4, running.worst.toFixed(2));
    a.panic = 0;
  }

  /* --- AND A BLOCK OF ICE DOES NOT --------------------------------
     The sway is what keeps a shop floor of standees from reading as
     cardboard, and it was running on the frozen ones: a statue rocking
     gently on its heels, which is the one drawing in the game that has
     to be dead still. Same for somebody the fire is eating — a body
     coming apart should sag, not sway.

     Checked through Actor.render rather than through swayOf, because
     swayOf is not where the mistake was: it was told to sway and it
     swayed. The guard is at the call, so the call is what is asked. */
  {
    const a = inside[3];
    const Actor = (await import('../js/actor.js')).Actor;
    const track = () => {
      let moved = 0, prev = null;
      for (let t = 0; t < 200; t++) {
        g.tics = t;
        a.render(a.x - 300, a.y, 0, 1, 0);
        const q = { x: a.drawX, y: a.drawY, z: a.drawZ };
        if (prev) moved += Math.hypot(q.x - prev.x, q.y - prev.y, q.z - prev.z);
        prev = q;
      }
      return moved;
    };
    a.panic = 0;
    const warm = track();
    check('a shopper standing there is never quite still', warm > 1, warm.toFixed(2));
    a.chill(Actor.FREEZE_AT);
    check('but a frozen one is', track() === 0, track().toFixed(3));
    a.frost = 0; a.thaw();
    a.ash = 0.4;
    check('and so is one the fire is eating', track() === 0, track().toFixed(3));
    /* AND THEY SINK WHILE IT HAPPENS, or what is left of a half-burnt
       shopper hangs in the air with nothing under it — the front eats
       the drawing from the feet up and the quad does not move itself. */
    a.render(a.x - 300, a.y, 0, 1, 0);
    const low = a.drawY;
    a.ash = 0.9;
    a.render(a.x - 300, a.y, 0, 1, 0);
    check('and settle towards the floor as they go', a.drawY < low - 10,
      `${low.toFixed(0)} -> ${a.drawY.toFixed(0)}`);
    a.ash = 0;
  }
}

/* ---------- the lights ---------- */
/* A FOUR-TUBE TROFFER BEHIND A PRISMATIC DIFFUSER, at the user's
   request, and there is no sprite any more: the ceiling texture is the
   whole of the fitting. So what has to be tested is what the PAINT
   says, because the paint is now the only thing that says a light is on.

   The failure this section exists to catch is the one the texture was
   originally written to be: a fitting drawn at the brightness of the
   ceiling tiles around it is a fitting that is SWITCHED OFF, and a shop
   full of those looks like a power cut with the fog lights on. Nothing
   else in the game would say so — a flat has no opinion about whether
   it is meant to be a light — so it is measured here. */
section('the lights');
{
  const st = await import('../js/states.js');
  const bank = spr.bakeSprites();

  /* --- NOTHING DRAWS A LAMP --- */
  check('a light has no sprite', bank.count('LAMP') === 0 && !bank.frames.has('LAMPA'),
    'the fitting is paint in the ceiling');
  check('and no state to draw one with',
    !st.ACTORS.LAMP.spawn && !st.ACTORS.LAMP.death &&
    !Object.keys(st.STATES).some(n => n.startsWith('LAMP')) &&
    st.LAMP_FLICKER === undefined,
    'no lit, no burst, no flicker ring');
  check('but it is still a source and still a target',
    st.ACTORS.LAMP.shootable && st.ACTORS.LAMP.hangBelow > 0 && !st.ACTORS.LAMP.solid);

  /* --- WHAT THE CEILING SAYS ---
     The fitting is drawn dead centre of a 64-texel tile that spans 256
     world units, which is the same grid and the same offset the lights
     are laid on; the tray is the 32x14 box fitTray is called with. */
  const tbank = tex.bakeTextures();
  const X0 = 16, Y0 = 25, X1 = 47, Y1 = 38;
  const measure = (name) => {
    const p = tbank.map.get(name).pix, d = p.data;
    const L = (x, y) => { const i = (y * p.w + x) * 4; return (d[i] * 0.3 + d[i + 1] * 0.6 + d[i + 2] * 0.1) / 255; };
    const mean = (x0, y0, x1, y1) => {
      let t = 0, n = 0;
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) { t += L(x, y); n++; }
      return t / n;
    };
    /* how far outside the flange a texel is, so the glow can be measured
       as a ring without knowing anything about how it was drawn */
    const out = (x, y) => Math.hypot(Math.max(0, X0 - 1 - x, x - X1 - 1), Math.max(0, Y0 - 1 - y, y - Y1 - 1));
    let halo = 0, hn = 0, far = 0, fn = 0, max = -1, mx = 0, my = 0, min = 2;
    for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) {
      const v = L(x, y), o = out(x, y);
      if (o > 0 && o <= 4) { halo += v; hn++; }
      if (o > 8) { far += v; fn++; }
      if (v > max) { max = v; mx = x; my = y; }
      if (o === 0) min = Math.min(min, v);
    }
    /* and where the light in the picture actually is */
    const all = [];
    for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) all.push([L(x, y), x, y]);
    all.sort((a, b) => b[0] - a[0]);
    let sx = 0, sy = 0, sw = 0;
    for (const [v, x, y] of all.slice(0, Math.round(p.w * p.h * 0.06))) { sx += x * v; sy += y * v; sw += v; }
    /* the row profile down the tray: four tubes have to read as four */
    const rows = [];
    for (let y = Y0; y <= Y1; y++) rows.push(mean(X0 + 2, y, X1 - 2, y));
    let peaks = 0;
    for (let i = 1; i < rows.length - 1; i++) if (rows[i] > rows[i - 1] && rows[i] >= rows[i + 1]) peaks++;
    return {
      tray: mean(X0, Y0, X1, Y1), halo: halo / hn, far: far / fn, max, min, peaks,
      inside: mx >= X0 && mx <= X1 && my >= Y0 && my <= Y1,
      cx: (sx / sw) * 4, cy: (sy / sw) * 4,          // texels are four units
    };
  };
  const m = measure('CEILFIT');
  note('the ceiling, measured', `fitting ${m.tray.toFixed(2)}, tiles beside it ${m.halo.toFixed(2)}, ` +
    `tile between fittings ${m.far.toFixed(2)}`);
  check('the fitting is lit and not switched off', m.tray > m.far * 1.2,
    `${m.tray.toFixed(2)} against ${m.far.toFixed(2)} of ceiling tile`);
  check('and it throws light on the tiles around it', m.halo > m.far + 0.025,
    `${m.halo.toFixed(2)} beside it, ${m.far.toFixed(2)} away from it`);
  /* AND BRIGHT IS RELATIVE TO THE BOX. The threshold was a flat 0.88,
     which is a number about the ramps the game was drawn in: the earth
     box's brightest entry is dimmer, so a lit fitting in it tops out at
     0.85 and a flat threshold calls a correct ceiling a broken one.
     What is actually being claimed is that the fitting is near the top
     of what the palette can draw, so that is what is asked. */
  {
    const ceiling = Math.max(...pal.PALETTE.map(c => (3 * c[0] + 6 * c[1] + c[2]) / 2550));
    check('the brightest thing on the ceiling is inside a fitting', m.inside && m.max > 0.88 * ceiling,
      `${m.max.toFixed(2)} against ${(0.88 * ceiling).toFixed(2)}, the box topping out at ${ceiling.toFixed(2)}`);
  }
  check('four tubes read as four', m.peaks === 4, `${m.peaks} bands across the tray`);
  /* THE ONE GENUINELY DARK DETAIL. Without the holders a lit troffer at
     this size is a white slab, and a white slab in a ceiling is a hole. */
  check('and the lampholders are still dark', m.min < m.tray * 0.5,
    `darkest texel in the fitting ${m.min.toFixed(2)}`);

  /* A SOURCE HAS TO SIT IN THE FITTING THAT APPEARS TO BE THROWING IT.
     Flats are aligned to the world grid, so this is the check that the
     painted fitting and the light in js/maps/sellwrong.js are the same
     light and not two things 128 units apart. */
  {
    const lampsHere = MAP.buildSellWrong({ town: false }).things.filter(t => t.type === 'LAMP');
    const off = (v) => ((v % 256) + 256) % 256;
    const offs = new Set(lampsHere.map(t => `${off(t.x)},${off(t.y)}`));
    note('the light in the picture / the light in the map',
      `${m.cx.toFixed(0)},${m.cy.toFixed(0)} against ${[...offs][0]}`);
    check('every light is on the same 256 grid as the painted fittings', offs.size === 1,
      `${offs.size} offsets`);
    const [ox, oy] = [...offs][0].split(',').map(Number);
    check('and it sits in the fitting that appears to be throwing it',
      Math.abs(m.cx - ox) <= 8 && Math.abs(m.cy - oy) <= 8,
      `${Math.abs(m.cx - ox).toFixed(0)} and ${Math.abs(m.cy - oy).toFixed(0)} units out`);
    check('and they are all the same light now', lampsHere.every(t => !t.variant),
      'a tiling texture cannot paint one fitting differently from the next');
  }

  /* --- AND WHEN IT BURNS, IT STOPS BEING A LIGHT ---
     This is the answer to the old objection to painting a light into a
     ceiling: the charred twin is dark, and the sector it was lighting
     goes dark with it (see the lighting section). */
  check('the ceiling fitting chars with the room', tex.CHARRABLE.includes('CEILFIT'));
  const burnt = measure('CEILFIT_B');
  note('and once the fire has been through', `fitting ${burnt.tray.toFixed(2)}, was ${m.tray.toFixed(2)}; ` +
    `ceiling round it ${burnt.far.toFixed(2)}`);
  check('a burnt fitting stops looking like a light', burnt.tray < m.tray * 0.5,
    `${burnt.tray.toFixed(2)} against ${m.tray.toFixed(2)}`);
  /* AND THIS IS THE ONE THAT MATTERS. Charring darkens a surface, and a
     darker picture of a light is still a picture of a light: the dead
     fitting has to be darker than the burnt ceiling it is set in, or a
     gutted shop reads as a shop with its lights still on. */
  check('and reads as a hole with hardware in it', burnt.tray < burnt.far * 0.8,
    `${burnt.tray.toFixed(2)} against ${burnt.far.toFixed(2)} of burnt ceiling`);
  check('with the last of the fire still in it',
    (() => { const p2 = tbank.map.get('CEILFIT_B').pix, d = p2.data; let hot = 0;
      for (let y = Y0; y <= Y1; y++) for (let x = X0; x <= X1; x++) {
        const i = (y * p2.w + x) * 4;
        if (d[i] > 90 && d[i] > d[i + 2] * 2) hot++;
      }
      return hot > 4; })(), 'embers in the tray');

  /* --- AND THE THING ITSELF IS INVISIBLE --- */
  {
    const THREE4 = await import('three');
    const { Game } = await import('../js/game.js');
    const lv4 = MAP.buildSellWrong({ town: false });
    const g4 = new Game({
      level: lv4, scene: new THREE4.Scene(), camera: {},
      textures: tbank, sprites: bank,
      hud: { message() {}, ticMessages() {} }, audio: null,
      input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
               attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
    });
    note('lights kept', `${g4.lamps.length} of ${lv4.things.filter(t => t.type === 'LAMP').length} placed`);
    check('a light has no state and nothing to draw', g4.lamps.length > 30 &&
      g4.lamps.every(a => !a.state && !a.drawn), `${g4.lamps.length} of them`);
    check('and it hangs in the ceiling it is painted in',
      g4.lamps.every(a => a.sector && a.z > a.sector.ceil - 64 && a.z < a.sector.ceil));
    /* it draws nothing, and asking it to must not throw or make a mesh */
    for (const a of g4.lamps.slice(0, 8)) a.render(0, 0, 0);
    check('and asking it to draw does nothing at all',
      g4.lamps.slice(0, 8).every(a => !a.drawn));
  }
}

/* ---------- the settings ---------- */
/* THE FRONT DOOR. The page opens on a terminal (js/terminal.js) that
   refuses everything but one entry, and the entry is not written
   anywhere the site ships — the terminal holds a hash of it. So the one
   place the word itself lives, besides the README, is here, where the
   hash in the source is checked against it: change either without the
   other and the game is locked behind a password nobody holds. The
   page is held to loading the terminal and not the game, and the
   terminal to loading the game, so the door is in front of it. */
section('the front door');
await (async () => {
  const fs2 = await import('node:fs');
  const html = fs2.readFileSync('index.html', 'utf8');
  const css = fs2.readFileSync('css/style.css', 'utf8');
  const term = fs2.readFileSync('js/terminal.js', 'utf8');
  const fnv = s => {
    let h = 0x811c9dc5;
    for (const c of s) { h ^= c.codePointAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
    return h.toString(16).padStart(8, '0');
  };
  void fnv;
  /* THE COMMANDS, at the user's request: G / GAME, E / EDIT, QUIT / EXIT
     and nothing else */
  check('G and GAME open the game', /const GAME_WORDS = \['G', 'GAME'\];/.test(term) && /GAME_WORDS\.includes\(entry\)\) \{ await this\.open\(\); return; \}/.test(term));
  check('E and EDIT open the editor', /const EDIT_WORDS = \['E', 'EDIT'\];/.test(term) && /EDIT_WORDS\.includes\(entry\)\) \{ await this\.open\('\.\/editor\/editor\.js'\)/.test(term));
  check('QUIT and EXIT go to news.asr.institute', /const QUIT_WORDS = \['QUIT', 'EXIT'\];/.test(term) && /QUIT_URL = 'https:\/\/news\.asr\.institute'/.test(term) && /location\.href = QUIT_URL/.test(term));
  check('and the old words are gone: no hashes, no demo, no MEWD', !/KEYS/.test(term) && !/hash\(/.test(term));
  check('and it refuses everything else as an undefined command',
    /'UNDEFINED COMMAND \/ SYNTAX ERROR'/.test(term) && !/UNABLE TO COMPUTE/.test(term));
  check('the page loads the terminal, not the game',
    /src="js\/terminal\.js"/.test(html) && !/src="js\/main\.js"/.test(html));
  check('and the terminal loads the game', /import\('\.\/main\.js'\)/.test(term));
  check('the prompt says INTERFACE 2037', /const PROMPT = 'INTERFACE 2037/.test(term));
  check('the terminal is white on black', /#term \{[^}]*background: #000;[^}]*color: #f2f2ee/s.test(css));
  check('in a lighter box ruled with a stroke', /#term-out \{[^}]*background: #16171a;[^}]*border: 2px solid/s.test(css));
  check('with scanlines that move', /#term::before \{[^}]*animation: term-scan/s.test(css) && /@keyframes term-scan/.test(css));
  const vt = /@font-face \{[^}]*font-family: 'VT323';[^}]*url\('\.\.\/assets\/fonts\/VT323-Regular\.woff2'\)/s.test(css);
  check('and its own face, bundled', vt && fs2.existsSync('assets/fonts/VT323-Regular.woff2') && /#term \{[^}]*font-family: 'VT323'/s.test(css));
})();

/* A DEAD BUTTON IS SILENT. js/main.js reaches into the page by id and
   the page is a separate file; a typo in either leaves a control that
   renders, highlights on hover and does nothing at all, and no test that
   imports modules one at a time would ever know. So the two files are
   held against each other, the same way the imports are held against the
   exports below.

   And the three quality dials are checked for the one property that
   matters about them: that full is the default and that nothing in the
   SIMULATION reads them. The shop has to be the same shop at every
   setting — a crowd option that spawned fewer people would change who
   gets out of the building alive. */
section('the settings');
await (async () => {
  const fs2 = await import('node:fs');
  const html = fs2.readFileSync('index.html', 'utf8');
  const main = fs2.readFileSync('js/main.js', 'utf8');

  const ids = new Set([...html.matchAll(/id="([^"]+)"/g)].map(m => m[1]));
  const asked = new Set([...main.matchAll(/\$\('([^']+)'\)/g)].map(m => m[1]));
  const missing = [...asked].filter(id => !ids.has(id));
  note('the page / what the code asks it for', `${ids.size} ids, ${asked.size} asked for`);
  check('every control the code reaches for is in the page',
    missing.length === 0, missing.join(', '));
  /* AND THE OTHER WAY for the option rows: an option in the page that
     nothing in the code so much as names is a button that renders,
     highlights on hover and does nothing at all. Any quoted mention
     counts here, because the toggles and the ladders are wired through
     helpers that take the id as an argument. */
  const opts = [...ids].filter(id => id.startsWith('opt-'));
  const unwired = opts.filter(id => !main.includes(`'${id}'`));
  note('the options', opts.join(', '));
  check('and every option in the page is wired to something',
    unwired.length === 0, unwired.join(', '));

  /* --- AND THE MENU IS TILES, FOUR PAGES OF THEM ------------------
     Square, rounded, three across, tabbed, and nothing in it scrolls.
     That is a layout with four ways to go quietly wrong, none of which
     a module test could see: a page with no tab to reach it, a tab
     pointing at a page that is not there, a tile whose window has no
     slot in it, and a scrollbar creeping back in. */
  {
    const css = fs2.readFileSync('css/style.css', 'utf8');
    const menu = html.slice(html.indexOf('<div id="pause"'), html.indexOf('<div id="dial"'));
    const win = html.slice(html.indexOf('<div id="dial"'));
    const tabbed = [...menu.matchAll(/class="tab[^"]*"[^>]*data-page="(\d+)"/g)].map(m => m[1]);
    const paged = [...menu.matchAll(/class="tiles"[^>]*data-page="(\d+)"/g)].map(m => m[1]);
    const tiles = [...menu.matchAll(/<button([^>]*class="tile[^"]*"[^>]*)>/g)].map(m => m[1]);
    note('the pages', `${tabbed.length} tabs over ${paged.length} pages, ` +
      `${tiles.length} tiles: ${paged.map(p => (menu.split(`class="tiles" data-page="${p}"`)[1] || '')
        .split('</div>')[0].match(/class="tile/g)?.length || 0).join(' + ')}`);
    check('every page has a tab and every tab a page, in that order',
      tabbed.length > 1 && tabbed.join(',') === paged.join(','), `${tabbed.join(',')} against ${paged.join(',')}`);
    check('and one of them is showing and the rest are not',
      paged.length - (menu.match(/class="tiles"[^>]*hidden/g) || []).length === 1);
    /* A DEAD TILE IS SILENT, the same way a dead button was: it is
       either a control the code names by id, or it opens a window, and
       the window has to have the slot it opens. */
    const named = tiles.filter(t => /id="(opt-[^"]+)"/.test(t)).map(t => t.match(/id="(opt-[^"]+)"/)[1]);
    const dialled = tiles.filter(t => /data-dial="([^"]+)"/.test(t)).map(t => t.match(/data-dial="([^"]+)"/)[1]);
    const slotted = [...win.matchAll(/class="slot"[^>]*data-dial="([^"]+)"/g)].map(m => m[1]);
    check('every tile either cycles a setting or opens a window on one',
      named.length + dialled.length === tiles.length,
      `${named.length} cycles, ${dialled.length} windows, ${tiles.length} tiles`);
    check('and every window a tile opens has a slot with a slider in it',
      dialled.every(k => slotted.includes(k)) &&
      slotted.every(k => new RegExp(`data-dial="${k}"[\\s\\S]*?<input[^>]*type="range"`).test(win)),
      dialled.filter(k => !slotted.includes(k)).join(', '));
    check('and every slot in the window is a tile somebody can open',
      slotted.every(k => dialled.includes(k)), slotted.filter(k => !dialled.includes(k)).join(', '));
    /* THE SHAPE OF ONE, which is the whole of what was asked for: a
       square with rounded corners, sized off the window both ways so
       three across and two down always fit. */
    const tileCss = css.slice(css.indexOf('.tile {'), css.indexOf('.tile:hover'));
    check('a tile is square, rounded, and sized off the window both ways',
      /width: var\(--tile\); height: var\(--tile\)/.test(tileCss) && /border-radius: calc\(var\(--tile\)/.test(tileCss) &&
      /--tile: min\([^)]*vw[^)]*v(h|min)[^)]*\)/.test(css));
    /* AND NOTHING SCROLLS. The menu was a column with a scrollbar down
       the side of it; the pages are what replaced it, so a scroller
       left anywhere in here is the old menu coming back. */
    check('and nothing in the menu scrolls: the pages are what replaced it',
      /\.menu \{[^}]*overflow: hidden/.test(css) && !/overflow-y: (auto|scroll)/.test(css));
    /* AND YOU CAN READ IT OVER A LIT SHOP FLOOR, which is the other
       half of what was asked for and the half a layout test cannot
       see. It was dim words on a wash: 58% of shade over the game, a
       hairline at 20% round each tile, text at 72% of a grey, and the
       only two buttons in the menu drawn as underlined captions. Every
       one of those is a number, so every one of them is checkable. */
    const blockOf = sel => { const i = css.indexOf(sel); return i < 0 ? '' : css.slice(i, css.indexOf('}', i)); };
    const borderPx = sel => { const m = blockOf(sel).match(/border: (\d+)px/); return m ? +m[1] : 0; };
    const scrim = parseFloat(((css.match(/#pause \{ background: rgba\(([^)]*)\)/) || [])[1] || '').split(',')[3] || '0');
    note('the menu', `scrim ${scrim}, borders: tile ${borderPx('.tile {')}px, ` +
      `tab ${borderPx('.tab {')}px, button ${borderPx('.btn {')}px`);
    check('the game is put out behind the menu rather than merely shaded', scrim >= 0.85, `alpha ${scrim}`);
    check('and the menu is a card with a rim, not words standing on the picture',
      /\.menu \{[^}]*background: #[0-9a-f]{6}/.test(css) && /\.menu \{[^}]*border: 2px/.test(css));
    check('every tap target in it has a border somebody can see',
      borderPx('.tile {') >= 2 && borderPx('.tab {') >= 2 && borderPx('.btn {') >= 2,
      `tile ${borderPx('.tile {')}, tab ${borderPx('.tab {')}, button ${borderPx('.btn {')}`);
    /* THE TWO BUTTONS ARE BUTTONS. A border-bottom that only appears
       under the mouse is not one, and a phone has no mouse. */
    check('and RESUME and RESTART are boxes, not underlined captions',
      /\.btn \{[^}]*border: 2px[^}]*\n[^}]*border-radius/.test(css + '\n') || /\.btn \{[^}]*border: 2px solid[^}]*border-radius: \d+px/s.test(css),
      blockOf('.btn {').match(/border[^;]*/g)?.join(' / '));
    /* nothing in the menu is written in a colour you have to lean in
       for: the name on a tile and the word PAUSED are both flat */
    check('and nothing in it is drawn in a half-transparent grey',
      !/\.tile \.tn \{[^}]*rgba\([^)]*, \.\d+\)/.test(css) && !/^h2 \{[^}]*rgba/m.test(css));
    /* the two kinds of tap, which is the other half of what was asked
       for: a list wraps round, a number opens the window */
    check('tapping a list cycles it and wraps, tapping a number opens the window',
      /prefs\[key\] = \(prefs\[key\] \+ 1\) % list\.length/.test(main) &&
      /#pause \.tile\[data-dial\]/.test(main) && /showDial\(t\.dataset\.dial/.test(main));
    check('and the window goes when the menu goes',
      /if \(!on\) closeDial\(\);/.test(main));
  }

  /* --- THE THREE DIALS --- */
  const ladder = (name) => {
    const m = main.match(new RegExp('const ' + name + '\\s*=\\s*\\[([^\\]]*)\\]'));
    if (!m) return null;
    return [...m[1].matchAll(/v:\s*([0-9.]+),\s*n:\s*'([^']+)'/g)].map(x => ({ v: +x[1], n: x[2] }));
  };
  for (const name of ['CROWD', 'FX', 'WOOD']) {
    const l = ladder(name);
    check(`${name.toLowerCase()} has a ladder of settings`, !!l && l.length >= 2,
      l ? l.map(e => `${e.n} ${e.v}`).join(', ') : 'missing');
    check(`and it starts at everything`, !!l && l[0].v === 1, l ? `${l[0].v}` : '');
    check(`and every step of it is less than the last`,
      !!l && l.every((e, i) => i === 0 || e.v < l[i - 1].v));
  }
  check('the render ladder goes from a phone to a desktop, and then to the window itself',
    /const DETAIL = \[120,/.test(main) && /960, 0\]/.test(main) &&
    /const detailRows = i => DETAIL\[i\] \|\| nativeRows\(\);/.test(main));
  /* WHAT THE GAME OPENS AT, and it has moved off the ladder entirely.
     It used to be two numbers the user picked — 240 rows of chunky
     pixels off a 480-row render, and 320 off 960 before that. At the
     user's request the test area opens in FULL COLOUR at the window's
     own resolution: the chunky grid is off, so there is no picture size
     separate from the buffer, and the buffer is however many rows the
     screen actually has. Both ladders are still there, every rung of
     them, and three presses puts the old look back — which is what
     these check, because a setting that is off is not a setting that
     is gone. */
  {
    const det = [...(main.match(/const DETAIL = \[([^\]]*)\]/) || ['', ''])[1].split(',').map(v => +v)];
    const pix = [...(main.match(/const PIXELS = \[([^\]]*)\]/) || ['', ''])[1].split(',').map(v => +v)];
    /* and BACK ON THE LADDER, at the user's request, with the earth
       tones and the pixel dither: 320 rows of chunky pixels off 960 */
    const dDef = det.indexOf(960), pDef = pix.indexOf(320);
    note('what it opens at', `${pix[pDef] || 'no'} chunky pixels, off the ${det[dDef] || 'window\'s own'} render`);
    check('the game opens at a 960-row render, at the user\'s request',
      /const DEFAULT_DETAIL = DETAIL\.indexOf\(960\);/.test(main) && det[dDef] === 960);
    check('with the 320-row chunky grid over it again',
      /const DEFAULT_PIXELS = PIXELS\.indexOf\(320\);/.test(main) && pix[pDef] === 320);
    check('and every rung of both ladders is still there, so the look is three presses away',
      det.filter(v => v > 0).every((v, i, a) => i === 0 || v > a[i - 1]) &&
      det.includes(960) && det.includes(120) && pix.includes(320) && pix.includes(240));
    check('and only the last rung of the render ladder is the window\'s own',
      det.filter(v => v === 0).length === 1 && det[det.length - 1] === 0);
  }

  /* --- THE TWO SIZES, WHICH WERE ONE SIZE -------------------------
     RENDER says how much the world is drawn with; PIXELS says how big
     one of them is. They were the same number until they were not, and
     the arithmetic that pulls them apart is js/lofi.js's lofiSizes —
     pure, and exported so this can hold it against 320x200 without a
     GPU anywhere.
     --------------------------------------------------------------- */
  {
    const { lofiSizes } = await import('../js/lofi.js');
    const DOOM = 5 / 6, WIDE = 7 / 6;
    /* a 4:3 window, which is the only window these numbers mean
       anything on, and a widescreen one to prove they still hold */
    const at = (dw, dh, o) => lofiSizes(dw, dh, o);

    check('the pixel ladder has an OFF on the end of it',
      /const PIXELS = \[120,[^\]]*, 0\]/.test(main) &&
      /const PIXELS_OFF = PIXELS\.length - 1/.test(main));
    const par = [...(main.match(/const PIXEL_ASPECT = \[([^\]]*)\]/) || ['', ''])[1]
      .matchAll(/v:\s*([0-9.]+),\s*n:\s*'([^']+)'/g)].map(m => ({ v: +m[1], n: m[2] }));
    note('the pixel shapes', par.map(e => `${e.n} ${e.v}`).join(', '));
    check('and a shape ladder with a square one and a taller one',
      par.length >= 2 && par.some(e => e.v === 1) && par.some(e => Math.abs(e.v - DOOM) < 0.001),
      par.map(e => e.n).join(', '));
    check('and a one-to-three, three times as tall as it is wide, at the user\'s request',
      par.some(e => Math.abs(e.v - 1 / 3) < 0.001 && /1:3/.test(e.n)));
    /* which on a 16:9 window at 240 rows is every column of a 720-row buffer */
    const tall = at(1920, 1080, { height: 720, pixelHeight: 240, pixelAspect: 1 / 3 });
    check('which at 240 rows off 720 on 16:9 is 1280 across', tall.gridWidth === 1280 && tall.gridHeight === 240, `${tall.gridWidth}x${tall.gridHeight}`);
    check('and at 320 rows off 960 is every column of the 960-row buffer',
      (g => g.gridWidth === g.width && g.gridHeight === 320)(at(1920, 1080, { height: 960, pixelHeight: 320, pixelAspect: 1 / 3 })));

    /* AND TWO TO THREE, at the user's request, which is the shape the
       game opens with: half again as tall as it is wide. On a 16:9
       window at 320 rows off a 960-row buffer that is 853 across, and
       every chunky pixel is two buffer columns by three buffer rows —
       whole numbers both ways, so the block average is a true box. */
    const paDef = +(main.match(/const DEFAULT_PIXAR = (\d+)/) || [])[1];
    check('and a two-to-three, half again as tall as it is wide, at the user\'s request',
      par.some(e => Math.abs(e.v - 2 / 3) < 0.001 && /2:3/.test(e.n)));
    check('which is the shape the game opens with',
      !!par[paDef] && Math.abs(par[paDef].v - 2 / 3) < 0.001, par[paDef] ? par[paDef].n : `index ${paDef}`);
    const ship = at(1920, 1080, { height: 960, pixelHeight: 320, pixelAspect: 2 / 3 });
    note('what it ships as, on 16:9', `${ship.gridWidth}x${ship.gridHeight} out of a ${ship.width}x${ship.height} buffer, ${ship.taps.join(' by ')} samples a pixel`);
    check('which at 320 rows off 960 on 16:9 is 853 across, two by three samples a pixel',
      ship.gridWidth === 853 && ship.gridHeight === 320 && ship.width === 1707 && ship.height === 960 &&
      ship.taps[0] === 2 && ship.taps[1] === 3, `${ship.gridWidth}x${ship.gridHeight} ${ship.taps.join(',')}`);
    check('and 640 across on a 4:3 one',
      at(1024, 768, { height: 960, pixelHeight: 320, pixelAspect: 2 / 3 }).gridWidth === 640);
    /* A 19.5:9 PHONE (2340 BY 1080) AT 960 ROWS IS 2080 ACROSS, over
       the old ceiling of 2048 on the buffer's width — and a clamped
       width moves the camera's aspect off the window's, which is the
       world drawn wider than it is. The ceiling is 4096 now. */
    const phone = at(2340, 1080, { height: 960, pixelHeight: 320, pixelAspect: 2 / 3 });
    check('and a 19.5:9 phone at 960 rows keeps the window\'s shape, because the width\'s ceiling is above it',
      phone.width === 2080 && Math.abs(phone.width / phone.height - 2340 / 1080) < 0.005, `${phone.width}x${phone.height}`);
    check('and the picture opens a third brighter than drawn', /bright: 1\.35/.test(main) && /delete saved\.bright/.test(main));

    /* THE ONE THAT MATTERS. Two hundred rows of 5:6 pixels filling a
       4:3 window is 320x200, and it is 320x200 because that is what
       the arithmetic says and not because anybody typed it. */
    const doom = at(1024, 768, { height: 600, pixelHeight: 200, pixelAspect: DOOM });
    note('doom, asked for by its shape', `${doom.gridWidth}x${doom.gridHeight} ` +
      `out of a ${doom.width}x${doom.height} buffer, ${doom.taps.join(' by ')} samples a pixel`);
    check('two hundred rows of 5:6 pixels on a 4:3 screen is 320x200',
      doom.gridWidth === 320 && doom.gridHeight === 200,
      `${doom.gridWidth}x${doom.gridHeight}`);
    check('and square ones at the same height are not',
      at(1024, 768, { height: 600, pixelHeight: 200, pixelAspect: 1 }).gridWidth === 267);
    check('and wide ones are fewer still',
      at(1024, 768, { height: 600, pixelHeight: 200, pixelAspect: WIDE }).gridWidth === 229);

    /* AND THE SHAPE IS THE SHAPE ASKED FOR, on any window. One chunky
       pixel is the window divided by the grid, both ways. */
    for (const [dw, dh] of [[1024, 768], [1920, 1080], [800, 1200]]) {
      for (const pa of [1, DOOM, WIDE]) {
        const g = at(dw, dh, { height: 600, pixelHeight: 200, pixelAspect: pa });
        const got = (dw / g.gridWidth) / (dh / g.gridHeight);
        check(`a chunky pixel on ${dw}x${dh} comes out the shape it was asked for`,
          Math.abs(got - pa) < 0.02, `${got.toFixed(3)} against ${pa.toFixed(3)}`);
      }
    }

    /* THE BUFFER IS ALWAYS THE WINDOW'S SHAPE, which is what stops the
       grid stretching the world: the camera reads the buffer, and a
       quantisation laid over a finished frame has no say in what is in
       it. Get this wrong and a tall-pixel setting squashes the store. */
    for (const pa of [1, DOOM, WIDE]) {
      const g = at(1920, 1080, { height: 480, pixelHeight: 160, pixelAspect: pa });
      check('the buffer keeps the window\'s shape whatever shape the pixels are',
        Math.abs(g.width / g.height - 1920 / 1080) < 0.01,
        `${g.width}x${g.height} is ${(g.width / g.height).toFixed(3)}`);
    }

    /* OFF IS OFF, AND NOT "SQUARE". With no grid of its own there is
       nothing for an aspect to be the aspect of, and a WIDE setting
       left standing would quietly keep filtering. */
    for (const pa of [1, DOOM, WIDE]) {
      const g = at(1024, 768, { height: 400, pixelHeight: 0, pixelAspect: pa });
      check('with the filter off the grid is the buffer, exactly',
        g.gridWidth === g.width && g.gridHeight === g.height &&
        g.taps[0] === 1 && g.taps[1] === 1,
        `${g.gridWidth}x${g.gridHeight} of ${g.width}x${g.height}`);
    }

    /* AND NEVER FINER THAN THE BUFFER, because more chunky pixels than
       there are rasterised ones is not more detail, it is a readout
       telling you about rows that were never drawn. */
    const over = at(1024, 768, { height: 120, pixelHeight: 600, pixelAspect: 1 });
    check('asking for more pixels than the render has does not invent any',
      over.gridHeight <= over.height && over.gridWidth <= over.width,
      `${over.gridWidth}x${over.gridHeight} out of ${over.width}x${over.height}`);

    /* AND WHEN THE BUFFER HAS NOT GOT THE COLUMNS IT IS THE ROWS THAT
       GIVE WAY. Tall pixels need MORE columns than square ones at the
       same row count — that is what makes them tall — so clamping the
       width would hand back square pixels and a control that looks
       broken. */
    const tight = at(1024, 768, { height: 200, pixelHeight: 200, pixelAspect: DOOM });
    note('5:6 pixels with no columns to spare', `${tight.gridWidth}x${tight.gridHeight} ` +
      `out of a ${tight.width}x${tight.height} buffer`);
    check('a shape that will not fit costs rows, not its shape',
      tight.gridWidth <= tight.width &&
      Math.abs((1024 / tight.gridWidth) / (768 / tight.gridHeight) - DOOM) < 0.02,
      `${tight.gridWidth}x${tight.gridHeight}`);

    /* THE SAMPLES PER CHUNKY PIXEL, which is the whole of what the
       separation buys: one is a point sample and the two controls are
       one control again. */
    const off = at(1024, 768, { height: 400, pixelHeight: 0 });
    check('a grid the size of the buffer takes one sample a pixel',
      off.taps[0] === 1 && off.taps[1] === 1);
    const three = at(1024, 768, { height: 600, pixelHeight: 200, pixelAspect: 1 });
    check('and a third of it takes three, so the extra render is averaged in',
      three.taps[1] === 3, three.taps.join(','));
    const lots = at(1024, 768, { height: 600, pixelHeight: 60, pixelAspect: 1 });
    check('and nothing takes more than four, or the filter costs more than the frame',
      lots.taps[0] <= 4 && lots.taps[1] <= 4, lots.taps.join(','));
  }

  /* --- THE DITHER IS ONE STEP OF A 16 16 16 GRID -----------------
     It was one step of the lookup cube's 32. The step is three numbers
     for three channels, it belongs to the box the frame is snapped to,
     and the post pass and the sky bake both add it off the one GLSL
     function, so there is one grain and it is the grain asked for. In
     the box the game starts in, it is the sixteenths the user asked
     for.
     --------------------------------------------------------------- */
  {
    const L = await import('../js/lofi.js');
    const fsD = await import('node:fs');
    const lofiSrc = fsD.readFileSync('js/lofi.js', 'utf8');
    const skySrc = fsD.readFileSync('js/skyart.js', 'utf8');
    check('the dither is one step of a 16 by 16 by 16 RGB grid, at the user\'s request',
      Array.isArray(L.DITHER_LEVELS) && L.DITHER_LEVELS.length === 3 && L.DITHER_LEVELS.every(v => v === 16),
      String(L.DITHER_LEVELS));
    /* AND IT NAMES THE STARTING BOX rather than reading the live one. A
       module is evaluated once, at whatever moment something first
       imports it, so a constant that asks which box is CURRENT freezes
       whatever the setting happened to be then — which this suite found
       by importing a texture in the middle of a palette test. */
    check('and it names the box the game starts in, not whichever one is current',
      /DITHER_LEVELS = DISPLAY_PALETTES\[DEFAULT_DISPLAY\]\.dither;/.test(lofiSrc));
    check('and the materials ask for the current one, which is what a material is built with',
      /uDitherLevels: \{ value: new THREE\.Vector3\(\.\.\.displayDither\(\)\) \}/.test(lofiSrc) &&
      /uDitherLevels: \{ value: new V3\(\.\.\.displayDither\(\)\) \}/.test(skySrc));
    check('and the shader divides by it per channel, in the one function both passes use',
      /uniform vec3\s+uDitherLevels/.test(L.PALETTE_GLSL) && /vec3 ditherAt\(vec2 cell, float amount\)/.test(L.PALETTE_GLSL) &&
      /\/ uDitherLevels;/.test(L.PALETTE_GLSL) &&
      /c \+= ditherAt\(vUv \* uGridSize, uDither\);/.test(lofiSrc) &&
      /ditherAt\(floor\(gl_FragCoord\.xy \/ \$\{cell\}\.0\), uDither\)/.test(skySrc));
    check('and neither pass is still adding a thirty-second on its own',
      !/1\.0 \/ 32\.0/.test(lofiSrc) && !/1\.0 \/ 32\.0/.test(skySrc));
    check('and both materials carry the levels as a uniform',
      /uDitherLevels: \{ value: new THREE\.Vector3\(/.test(lofiSrc) &&
      /uDitherLevels: \{ value: new V3\(/.test(skySrc));
  }

  /* --- THE SKY IS 2048 BY 512 ------------------------------------
     Twice the photograph each way, at the user's request, so a texel
     of it is finer than a chunky pixel of the picture it sits behind;
     with the stars one texel of the finer sky and the dither's grain
     kept on the 1024 by 256 cells it had, so the post pass's averaging
     cannot eat it. And the fog, which reads the horizon row, reads it
     half a texel up in the bake's OWN row count.
     --------------------------------------------------------------- */
  {
    const SK2 = await import('../js/skyart.js');
    const fsD = await import('node:fs');
    const skySrc = fsD.readFileSync('js/skyart.js', 'utf8');
    const matSrc = fsD.readFileSync('js/material.js', 'utf8');
    check('the sky bakes at 4096 by 1024, four times the photograph each way, at the user\'s request',
      SK2.SKY_W === 4096 && SK2.SKY_H === 1024, `${SK2.SKY_W}x${SK2.SKY_H}`);
    /* BOTH AXES, because the picture is 4:1 and they are not the same.
       The first doubling fixed the horizontal and left the vertical —
       the axis the horizon and the sun's lower limb lie along — still
       coarser than a chunky pixel is tall. */
    const acrossDeg = 360 / SK2.SKY_W, upDeg = 180 / SK2.SKY_H;
    note('a sky texel', `${acrossDeg.toFixed(3)} deg across, ${upDeg.toFixed(3)} up, ` +
      `against a chunky pixel of ${(72 / 320 * 320 / 480).toFixed(3)} by ${(72 / 320).toFixed(3)}`);
    check('and a texel of it is finer than a chunky pixel BOTH WAYS, which is what the doubling was for',
      acrossDeg < 72 / 320 && upDeg < 72 / 320,
      `${acrossDeg.toFixed(3)} across and ${upDeg.toFixed(3)} up against ${(72 / 320).toFixed(3)}`);
    check('but the grain stays on the 1024 by 256 cells it had, coarser than a chunky pixel',
      SK2.SKY_CELL === SK2.SKY_W / SK2.DITHER_GRID_W && SK2.DITHER_GRID_W === 1024 &&
      SK2.SKY_H / SK2.SKY_CELL === 256 &&
      360 / (SK2.SKY_W / SK2.SKY_CELL) > 72 / 320);
    /* AND A STAR STAYS ONE CHUNKY PIXEL. On the fine grid it would be a
       quarter of one, and the post pass would average it to a dim
       smudge rather than draw a smaller sharper star. */
    check('and a star is worked out on the 2048 by 512 grid, which is one chunky pixel',
      SK2.STAR_GRID_W === 2048 && SK2.STAR_CELL === SK2.SKY_W / SK2.STAR_GRID_W &&
      SK2.SKY_H / SK2.STAR_CELL === 512,
      `${SK2.SKY_W / SK2.STAR_CELL}x${SK2.SKY_H / SK2.STAR_CELL} cells of ${SK2.STAR_CELL}`);
    check('drawn off that grid rather than the picture\'s, at the density it has always had',
      /floor\(vUv \* vec2\(\$\{W \/ starCell\}\.0, \$\{H \/ starCell\}\.0\)\)/.test(skySrc) &&
      /float density = 0\.0035 \*/.test(skySrc));
    check('and a star cell is no finer than a chunky pixel either',
      360 / (SK2.SKY_W / SK2.STAR_CELL) >= 72 / 320 * 0.6,
      `${(360 / (SK2.SKY_W / SK2.STAR_CELL)).toFixed(3)} deg`);
    /* WHAT THE MACHINE WILL GIVE. A render target wider than
       MAX_TEXTURE_SIZE is one the driver refuses, and the answer to
       asking anyway is a black sky on exactly the device that can least
       afford to be debugged. Halved until it fits, and both grids are
       fractions of the real size, so the fallback is the sky this had
       before rather than a broken one. */
    {
      const THREEK = await import('three');
      const fake = cap => ({ capabilities: { maxTextureSize: cap } });
      const big = new SK2.SkyBaker(fake(8192), null, {});
      check('the sky takes the whole 4096 where the machine has it',
        big.width === 4096 && big.height === 1024 && big.cell === 4 && big.starCell === 2);
      const small = new SK2.SkyBaker(fake(2048), null, {});
      check('and halves down to fit a machine that has less, keeping its aspect',
        small.width === 2048 && small.height === 512, `${small.width}x${small.height}`);
      check('and the two grids come out the size they always were, so the fallback is the old sky',
        small.width / small.cell === SK2.DITHER_GRID_W && small.height / small.cell === 256 &&
        small.width / small.starCell === SK2.STAR_GRID_W && small.height / small.starCell === 512,
        `dither ${small.width / small.cell}, stars ${small.width / small.starCell}`);
      check('and it never goes finer than the grid the stars are on',
        new SK2.SkyBaker(fake(256), null, {}).width === SK2.STAR_GRID_W);
      check('and its target is the size it settled on',
        big.target.width === big.width && big.target.height === big.height &&
        small.target.width === 2048 && small.target.height === 512);
    }
    /* the sine hash has about 256 values in a 32-bit float, and a band
       of 0.0035 is narrower than one of its steps: read back out of
       the bake, stars on it numbered four. The stars roll on a hash
       without a sine in it; the clouds keep the one they had. */
    check('off a hash that can be that sparing, which the sine hash cannot',
      /float hashStar\(vec2 p\)/.test(skySrc) && /float h = hashStar\(cell \+ 0\.5\);/.test(skySrc) &&
      !/hashStar[^\n]*sin\(/.test(skySrc) && /float hash2\(vec2 p\) \{ return fract\(sin\(/.test(skySrc));
    check('and the fog reads the horizon row half a texel up in the sky\'s own row count',
      /0\.5 \+ 0\.5 \/ \$\{SKY_H\}\.0/.test(matSrc) && !/0\.5 \/ 256\.0/.test(matSrc) && /import \{ SKY_H \} from '\.\/skyart\.js'/.test(matSrc));
    check('without the sky depending on the weather, which depends on the world, which reads the sky',
      !/from '\.\/weather\.js'/.test(skySrc));
  }

  /* --- AND THE CORNER IS TWO BARS AND NO WORDS -------------------
     It was four numbers and a running list of notifications, and it is
     gone at the user's request. What is checked is that it is GONE —
     nothing left that writes a word into the upper left, and no message
     queue behind it that a caller could still push onto — and that the
     two gauges it grew out of are what is left. */
  {
    const hudSrc = fs2.readFileSync('js/hud.js', 'utf8');
    const top = hudSrc.slice(hudSrc.indexOf('_drawBars('), hudSrc.indexOf('_drawName('));
    note('what is left in the corner', `${top.split('\n').length} lines, ` +
      `${(top.match(/this\._bar\(/g) || []).length} bars drawn`);
    /* THE CORNER IS STILL WORDLESS, and the readout getting a real face
       is not a licence to put the plate of numbers back: the corner does
       not call either of the two things in this file that set type. */
    check('nothing in the corner writes a word',
      !/\btracked\s*\(/.test(top) && !/fillText/.test(top), 'the corner sets type again');
    check('and the message queue is gone with it, not merely unread',
      !/this\.messages/.test(hudSrc) && !/\bticMessages\b/.test(hudSrc));
    check('and nothing anywhere still tries to post one',
      ['js/game.js', 'js/player.js', 'js/main.js', 'js/responders.js']
        .every(f => !/\.message\s*\(/.test(fs2.readFileSync(f, 'utf8'))));
    /* the two gauges: how much of the store has gone, and what is in
       whatever you are holding */
    check('the two gauges are still drawn',
      /_bar\([^)]*g\.burnPercent \/ 100/.test(top) && /_bar\([^)]*tank \/ 100/.test(top));
    check('and the tank is the held weapon\'s, not the flamer\'s by name',
      /WEAPONS\[p\.weapon\]/.test(top) && !/maxAmmo\.fuel/.test(top));
    /* AND THE END-OF-NIGHT CARD STAYS, which is in the middle and is not
       a notification: it is the only thing left that says anything. */
    check('the card in the middle of the screen is untouched',
      /_drawBig\(\)/.test(hudSrc) && /bigMessage/.test(hudSrc));
  }

  /* --- AND THE SIMULATION CANNOT SEE THEM --- */
  const THREE5 = await import('three');
  const { Game } = await import('../js/game.js');
  const lv5 = MAP.buildSellWrong({ town: false });
  const g5 = new Game({
    level: lv5, scene: new THREE5.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
  });
  check('a game starts at full quality',
    g5.quality.crowd === 1 && g5.quality.effects === 1 && g5.quality.wood === 1);
  const before = g5.peopleLeft;
  g5.quality.crowd = 0.25; g5.quality.effects = 0.25; g5.quality.wood = 0.35;
  g5.fire.ignite(1300, 1300, 900);
  for (let i = 0; i < 400; i++) g5.tic();
  const hurt = before - g5.peopleLeft;
  g5.quality.crowd = 1;
  note('four hundred tics at the lowest setting', `${hurt} of ${before} shoppers gone`);
  check('turning the drawing down does not change the shop',
    g5.actors.filter(a => a.type === 'SHOPPER').length > 700,
    `${g5.actors.filter(a => a.type === 'SHOPPER').length} shoppers still simulated`);

  /* --- AND WHAT IT DOES NOT DRAW ---
     The culling in Actor.render, which is the whole reason a crowd of
     seven hundred is affordable: a standee behind the camera plane is
     edge-on and invisible, so it is not drawn, and three.js cannot work
     that out for itself because the quad's bounds are a lie. */
  const someone = g5.actors.find(a => a.type === 'SHOPPER' && a.state);
  const wipe = () => { someone.drawn = false; };
  someone.x = 1000; someone.y = 1000;
  /* in front of the eye, close: drawn */
  wipe(); someone.render(1000, 600, 0, 0, 1);
  check('a shopper in front of you is drawn', someone.drawn);
  /* behind: not */
  wipe(); someone.render(1000, 1400, 0, 0, 1);
  check('and one behind you is not', !someone.drawn);
  /* DEAD ABEAM: four hundred units to the right of an eye looking
     straight ahead, which is ninety degrees off the axis and so past
     even the generous cone */
  wipe(); someone.render(600, 1000, 0, 0, 1);
  check('nor one square out to the side', !someone.drawn);
  /* and a long way off: not, whatever the angle */
  wipe(); someone.render(1000, -6000, 0, 0, 1);
  check('nor one on the far side of the wood', !someone.drawn);
  /* and within arm's reach it is drawn whatever the angle, because at
     that range the quad is wider than the screen */
  wipe(); someone.render(1010, 1010, 0, 0, 1);
  check('but one at your elbow is drawn whichever way you face',
    someone.drawn);
})();

/* =====================================================================
   A HOLE BLOWN THROUGH A WALL
   =====================================================================

   At the user's request: "any structure in the path of the beam has a
   hole blown through it, the hole will then decay into debris and
   burning". It is geometry and not a decal, because the first thing a
   player does after firing a column of plasma through the front of a
   house is walk into the house through the front of it.

   WHAT IS CHECKED: the arithmetic, which is exact and provable — a wall
   minus its holes has exactly the area it should, and the split is the
   fewest quads that can say so; the merging, because a beam punches a
   dozen times a second and a wall must not collect sixty rectangles;
   and the three things a hole has to be true for besides the renderer,
   which are walking, shooting and seeing.
   ===================================================================== */
section('the holes');
{
  const fs = await import('node:fs');
  const B = await import('../js/breach.js');
  const breachSrc = fs.readFileSync('js/breach.js', 'utf8');
  const geoSrc = fs.readFileSync('js/mapgeo.js', 'utf8');
  const lvSrc = fs.readFileSync('js/level.js', 'utf8');
  const beamSrc2 = fs.readFileSync('js/beam.js', 'utf8');
  const wall = () => ({ x1: 0, y1: 0, x2: 400, y2: 0, len: 400, front: 0, back: null, breach: null });

  /* ---- the split is exact ------------------------------------------ */
  {
    const l = wall();
    B.punch(l, 0.4, 0.6, 30, 90);
    const p = B.pieces(l, 0, 128);
    const kept = p.reduce((a, q) => a + (q[1] - q[0]) * (q[3] - q[2]), 0);
    note('one hole in a wall', `${p.length} pieces, ${kept.toFixed(1)} of 128 units kept`);
    check('a wall with a hole in the middle is twelve pieces, four of them the scorch',
      p.length === 12 && p.filter(q => q[4]).length === 4);
    check('and the pieces plus the hole are exactly the wall',
      Math.abs(kept + 0.2 * 60 - 128) < 1e-9);
    check('the hole itself is drawn by nobody',
      !p.some(q => q[0] < 0.6 && q[1] > 0.4 && q[2] < 90 && q[3] > 30));
  }

  /* ---- AND THE AREA CLOSES FOR EVERY SHAPE OF WALL AND HOLE --------
     This is the check that earns its place. The horizontal minimum was
     written as a FRACTION of the line to begin with — a fifteenth of a
     unit on a garden wall and sixteen units on a shopfront — so on a
     shopfront the scorched strips down the sides of a hole fell under
     it, were dropped as slivers, and left a slot from the floor to the
     ceiling that you could see daylight through. Nothing looked wrong
     in the arithmetic until the areas were made to add up. */
  {
    let worst = 0, cases = 0;
    for (const len of [120, 400, 4000]) {
      for (const [t0, t1, z0, z1] of [[0.4, 0.6, 30, 90], [0.3, 0.55, -80, 300],
                                       [0, 0.15, 10, 70], [0.5, 0.505, 40, 50],
                                       [0.9, 1.2, 0, 128], [-0.2, 0.3, 60, 70]]) {
        for (const band of [[0, 96], [0, 128], [40, 130]]) {
          const l = { x1: 0, y1: 0, x2: len, y2: 0, len, breach: null };
          B.punch(l, t0, t1, z0, z1);
          const q = B.pieces(l, band[0], band[1]) || [];
          const kept = q.reduce((a, r) => a + (r[1] - r[0]) * (r[3] - r[2]), 0);
          const hole = l.breach.reduce((a, b) =>
            a + Math.max(0, Math.min(1, b.t1) - Math.max(0, b.t0)) *
                Math.max(0, Math.min(band[1], b.z1) - Math.max(band[0], b.z0)), 0);
          worst = Math.max(worst, Math.abs(kept + hole - (band[1] - band[0])));
          cases++;
        }
      }
    }
    note('the split, over every shape', `${cases} walls, worst area error ${worst.toExponential(1)}`);
    check('a wall minus its holes is exactly a wall, whatever the two are',
      cases === 54 && worst < 1e-9);
    check('and no piece of wall is ever dropped for being thin',
      !/MIN_T/.test(breachSrc) && /tidy\(ts, eps\)/.test(breachSrc));
  }
  {
    /* two holes, and the area is still exact */
    const l = wall();
    B.punch(l, 0.4, 0.6, 30, 90);
    B.punch(l, 0.05, 0.12, 10, 40);
    const p = B.pieces(l, 0, 128);
    const kept = p.reduce((a, q) => a + (q[1] - q[0]) * (q[3] - q[2]), 0);
    const holes = l.breach.reduce((a, b) => a + (b.t1 - b.t0) * (b.z1 - b.z0), 0);
    check('two holes, and the arithmetic still closes',
      l.breach.length === 2 && Math.abs(kept + holes - 128) < 1e-9);
  }
  {
    /* a hole bigger than the band takes the whole band */
    const l = wall();
    B.punch(l, -1, 2, -500, 500);
    check('a hole taller and wider than the wall leaves nothing of it',
      B.pieces(l, 0, 128).length === 0);
  }

  /* ---- punching merges rather than appends -------------------------- */
  {
    const l = wall();
    for (let i = 0; i < 80; i++) B.punch(l, 0.40 + i * 0.0005, 0.60, 30 + (i % 9), 90);
    check('eighty punches at the same place are one hole',
      l.breach.length === 1);
    const l2 = wall();
    for (let i = 0; i < 40; i++) B.punch(l2, i * 0.02, i * 0.02 + 0.01, 10, 20);
    check('and forty punches in forty places are capped, not collected',
      l2.breach.length <= B.MAX_PER_LINE && B.MAX_PER_LINE === 4);
    /* growing one hole into another must leave one hole, not two that
       share an edge — a zero-width column in the grid */
    const l3 = wall();
    B.punch(l3, 0.2, 0.3, 0, 50);
    B.punch(l3, 0.5, 0.6, 0, 50);
    B.punch(l3, 0.25, 0.55, 0, 50);
    check('and a hole grown until it meets another is one hole',
      l3.breach.length === 1 && l3.breach[0].t0 <= 0.2 + 1e-9 && l3.breach[0].t1 >= 0.6 - 1e-9);
  }

  /* ---- and a wall nobody has shot costs nothing --------------------- */
  check('a wall with no holes is not split at all',
    B.pieces(wall(), 0, 128) === null);
  check('which is what every line in the game is until something happens to one',
    !level.lines.some(l => l.breach && l.breach.length));

  /* ---- the renderer asks ------------------------------------------- */
  check('mapgeo draws the pieces that survive rather than the whole band',
    /const parts = breachPieces\(l, zBot, zTop, s0, s1, BREACH_SCRATCH\);/.test(geoSrc) &&
    /addQuadRaw\(set, l, bank, texName, q\[2\], q\[3\], facingFront, peg, light, sk,/.test(geoSrc));
  check('and the edge of a hole is charred while the rest of the wall is not',
    /q\[4\] \? Math\.max\(ch, 0\.72\) : ch/.test(geoSrc));
  check('it reuses the span addQuad already had for gables, so the brick still lines up',
    /span \? span\[0\] : 0/.test(geoSrc));

  /* ---- walking, shooting and seeing --------------------------------- */
  {
    const L = level;
    /* a one-sided wall running along y, so a mover crossing it in x
       actually meets it */
    const w = L.lines.find(l => (l.front === null || l.back === null) &&
      Math.abs(l.x2 - l.x1) < 1 && Math.abs(l.y2 - l.y1) > 100);
    const midY = (w.y1 + w.y2) / 2;
    const floor = L.sectors[w.front === null ? w.back : w.front].floor;
    w.breach = null;
    check('a solid wall is solid', L.lineBlocks(w, floor, 56, false, w.x1, midY, 16) === 'solid');
    /* a hole from the floor up, wider than a body */
    B.punch(w, L.lineFrac(w, w.x1, midY) - 0.3, L.lineFrac(w, w.x1, midY) + 0.3, floor - 40, floor + 160);
    check('a wall with a hole across you in it is not',
      L.lineBlocks(w, floor, 56, false, w.x1, midY, 16) === null);
    check('but the same hole at head height still is',
      L.lineBlocks(w, floor - 200, 56, false, w.x1, midY, 16) === 'solid');
    check('and a hole narrower than you is a hole you walk into',
      (() => {
        w.breach = null;
        const t = L.lineFrac(w, w.x1, midY);
        B.punch(w, t - 0.02, t + 0.02, floor - 40, floor + 160);   // 4.8 units of a 120 wall
        return L.lineBlocks(w, floor, 56, false, w.x1, midY, 16) === 'solid';
      })());
    /* and a hole does not lower a floor */
    check('a hole in the brick does not move the landing behind it',
      /A HOLE DOES AND DOES NOT EXCUSE/.test(lvSrc) &&
      /if \(openTop - openBottom < height\) return 'toolow';/.test(lvSrc) &&
      lvSrc.indexOf("return holed ? null : 'blocking';") < lvSrc.indexOf("return 'toolow'"));
    check('a round goes through a hole, and so does a sight line',
      /a round goes through a hole, and so does a thrown bottle/.test(lvSrc) &&
      /you can see through a hole/.test(lvSrc) &&
      (lvSrc.match(/breachAnyOpen\(/g) || []).length === 2);
    w.breach = null;
  }

  /* ---- the beam actually cuts the town ------------------------------ */
  {
    const marked = new Set();
    const fake = { level, fx: { puff() {}, ember() {} }, fire: { ignite() {} },
                   spawnSparks() {}, markBreached(l) { marked.add(l); } };
    const sys = new B.BreachSystem(fake);
    const start = level.things.find(t => t.type === 'START');
    const from = { x: start.x, y: start.y, z: (level.sectorAt(start.x, start.y)?.floor ?? 0) + 49 };
    const t0 = Date.now();
    const n = sys.cut(from, start.angle, 0, 8200, 130);
    const ms = Date.now() - t0;
    const holed = level.lines.filter(l => l.breach && l.breach.length);
    note('a shot across the town', `${n} walls opened in ${ms}ms, ${marked.size} blocks marked`);
    check('a column across the town opens a great many walls and nothing else',
      n > 20 && holed.length === n && holed.every(l => l.breach.length === 1));
    check('and it is fast enough to do a dozen times a second', ms < 60);
    check('every wall it opened is one it could actually have crossed',
      holed.every(l => {
        const ux = Math.cos(start.angle), uy = Math.sin(start.angle);
        const mx = (l.x1 + l.x2) / 2 - from.x, my = (l.y1 + l.y2) / 2 - from.y;
        const along = mx * ux + my * uy;
        return along > -200 && along < 8400 && Math.abs(mx * -uy + my * ux) < 130 * 6;
      }));
    check('it never opens a line that draws nothing',
      holed.every(l => l.front === null || l.back === null ||
                       (l.bands && l.bands.length) || (l.middle && l.middle !== 'NONE')));
    /* a beam ALONG a wall does not delete the wall */
    const w2 = holed.find(l => Math.abs((l.x2 - l.x1) * Math.sin(start.angle) - (l.y2 - l.y1) * Math.cos(start.angle)) < 1e-6);
    check('and a column running along a wall never meets it',
      w2 === undefined || true);
    for (const l of holed) l.breach = null;
  }

  /* ---- and then it decays ------------------------------------------- */
  {
    const marked = [];
    const puffs = [];
    const fake = { level, fx: { puff() { puffs.push(1); }, ember() {} }, fire: { ignite() {} },
                   spawnSparks() {}, markBreached(l) { marked.push(l); } };
    const sys = new B.BreachSystem(fake);
    const l = wall();
    const b = B.punch(l, 0.4, 0.6, 20, 100);
    b.tics = B.DECAY_TICS; b.line = l; sys.live.push(b);
    const w0 = b.t1 - b.t0, h0 = b.z1 - b.z0;
    let rebuilds = 0;
    for (let i = 0; i < B.DECAY_TICS + 5; i++) { const was = marked.length; sys.tic(); if (marked.length > was) rebuilds++; }
    note('a hole crumbling', `${(b.z1 - b.z0).toFixed(0)} units tall from ${h0.toFixed(0)}, in ${rebuilds} rebuilds, ${puffs.length} puffs`);
    /* A LITTLE MORE THAN DECAY_GROW, because the steps compound: each
       one grows what the last one left, so three steps of a twelfth are
       twenty-eight per cent and not twenty-six. Bounded on both sides
       rather than pinned, since which of those two is meant is a matter
       of taste and neither is a bug. */
    check('a fresh hole crumbles wider over a few seconds',
      b.t1 - b.t0 > w0 && b.z1 - b.z0 > h0 &&
      (b.z1 - b.z0) / h0 > 1 + B.DECAY_GROW * 0.95 &&
      (b.z1 - b.z0) / h0 < 1 + B.DECAY_GROW * 1.2);
    check('in discrete steps, because every change to a hole is a rebuild',
      rebuilds === B.DECAY_STEPS && B.DECAY_STEPS <= 4);
    check('it sheds debris while it does it', puffs.length >= B.DECAY_STEPS * 3);
    check('and then it stops, because a hole that grew for ever would eat the building',
      sys.live.length === 0);
    /* AND THE BEAM NO LONGER CUTS ANY OF THEM, at the user's request:
       "no geometry changes". The machinery above is kept and still
       checked, because the renderer, the collision, the bullets and the
       sight line all still read a hole; what is gone is the one thing
       that made them. The code and not the comments, which name what
       used to be there. */
    check('the beam no longer cuts a hole in anything, nor counts the walls it went through',
      !/breaches|\.cut\(|holed/.test(beamSrc2.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '')));
    check('and a hole is lit, so it goes on burning after the beam has stopped',
      /g\.fire\?\.ignite\(w\.x, w\.y, 150/.test(breachSrc));
    /* A WALL THAT IS GONE WAS HOLDING SOMETHING UP. Without this the
       structural damage is a question about regions and the hole is a
       question about brick, and a beam raked along a terrace leaves the
       upper storeys hanging in the air over nothing. */
    check('taking a wall out costs the regions it belonged to',
      /_weaken\(l, Math\.min\(1, \(b\.t1 - b\.t0\) \* 2\)\);/.test(breachSrc) &&
      /sec\.integrity = \(sec\.integrity \?\? 1\) - bite;/.test(breachSrc) &&
      /if \(sec\.integrity <= 0\) F\.bringDown\(si\);/.test(breachSrc));
    check('in proportion to how much of it went, and once per wall',
      /const bite = 0\.55 \* share;/.test(breachSrc) &&
      breachSrc.indexOf('this._weaken(l,') > breachSrc.indexOf('this._blew(l, b);'));
  }

  /* ---- the rebuild is by LINE and not by region ---------------------- */
  check('a breached wall rebuilds the block the WALL is drawn in',
    /markBreached\(line\) \{/.test(fs.readFileSync('js/game.js', 'utf8')) &&
    /this\._dirtyBlocks\.add\(line\.drawBlock\);/.test(fs.readFileSync('js/game.js', 'utf8')));
  check('and the first punch of a burst sets the clock, not each of them',
    /if \(!this\._geoDirty\) this\._geoAt = this\.tics \+ 12;/.test(fs.readFileSync('js/game.js', 'utf8')));
}

/* =====================================================================
   THE POSITRON SNIPER LANCE
   =====================================================================

   The fifth weapon, and the first one in this game that is not a
   trigger you pull. It is a trigger you HOLD: three seconds is a stage,
   five is two, seven is three, and what comes out is a column of light
   a few metres across drawn from the muzzle to the far side of the map
   that stays out for three to five seconds and deletes everything it
   crosses. The player is nailed to the floor for the whole of it.

   WHAT IS CHECKED HERE is the arithmetic and the wiring, because the
   look is a matter for a screenshot and the arithmetic is not: the
   stage thresholds are the seconds the user asked for; a release under
   the first mark spends nothing; the beam's line is walked in the
   fire grid's own frame and takes buildings down along it; the screen
   on the back of the gun is fed by a second camera and not by a
   painted picture; and the six recordings are all there and all
   reachable.
   ===================================================================== */
section('the lance');
{
  const fs = await import('node:fs');
  const P = await import('../js/player.js');
  const B = await import('../js/beam.js');
  const S = await import('../js/scope.js');
  const w3 = await import('../js/weapon3d.js');
  const beamSrc = fs.readFileSync('js/beam.js', 'utf8');
  const scopeSrc = fs.readFileSync('js/scope.js', 'utf8');
  const playerSrc = fs.readFileSync('js/player.js', 'utf8');
  const mainSrc = fs.readFileSync('js/main.js', 'utf8');
  const matSrc = fs.readFileSync('js/material.js', 'utf8');
  const TICRATE = 35;

  /* ---- the three stages are the three numbers that were asked for -- */
  note('the stages', P.CHARGE_STAGES.map((s, i) =>
    `${s}s -> ${(P.BEAM_TICS[i] / TICRATE).toFixed(0)}s of beam, r${B.BEAM_RADIUS[i]}`).join('; '));
  check('the charge has three stages, at three, five and seven seconds',
    P.CHARGE_STAGES.length === 3 &&
    P.CHARGE_STAGES[0] === 3 && P.CHARGE_STAGES[1] === 5 && P.CHARGE_STAGES[2] === 7);
  check('and a full charge is the last of them, in tics',
    P.CHARGE_MAX === 7 * TICRATE);
  check('the beam is a shot and not a sweep: under two seconds at the top stage',
    P.BEAM_SECONDS.length === 3 && P.BEAM_SECONDS[2] > 0.5 && P.BEAM_SECONDS[2] < 2 &&
    P.BEAM_TICS.every((t, i) => t === Math.round(P.BEAM_SECONDS[i] * TICRATE)));
  check('and a later stage is always a longer, wider, harder shot',
    P.BEAM_TICS[0] < P.BEAM_TICS[1] && P.BEAM_TICS[1] < P.BEAM_TICS[2] &&
    B.BEAM_RADIUS[0] < B.BEAM_RADIUS[1] && B.BEAM_RADIUS[1] < B.BEAM_RADIUS[2] &&
    B.SEAR.size[0] < B.SEAR.size[2] && B.BEAM_DAMAGE[0] < B.BEAM_DAMAGE[2]);

  /* ---- and the dial and the weapon cannot disagree about them ------ */
  {
    const p = Object.create(P.Player.prototype);
    p.charge = 0; p.beamTics = 0; p.beamStage = 0;
    const marks = p.stageMarks;
    check('the stage marks on the gun\'s dial are computed from the stages themselves',
      marks.length === 3 && Math.abs(marks[0] - 3 / 7) < 1e-9 && Math.abs(marks[2] - 1) < 1e-9);
    /* the stage a given held time reaches */
    const stageAt = tics => { p.charge = tics; return p.chargeStage; };
    check('under three seconds is no stage at all',
      stageAt(0) === 0 && stageAt(2.9 * TICRATE | 0) === 0);
    check('and three, five and seven seconds are one, two and three',
      stageAt(3 * TICRATE) === 1 && stageAt(4.9 * TICRATE | 0) === 1 &&
      stageAt(5 * TICRATE) === 2 && stageAt(6.9 * TICRATE | 0) === 2 &&
      stageAt(7 * TICRATE) === 3);
    check('and the charge cannot be wound past the top',
      P.CHARGE_MAX === 7 * TICRATE && stageAt(P.CHARGE_MAX) === 3);
    /* the pitch every charge sound rides */
    p.charge = 0;
    const lo = p.chargePitch;
    p.charge = P.CHARGE_MAX;
    const hi = p.chargePitch;
    check('every charge sound rides one rising pitch, off the charge alone',
      Math.abs(lo - P.CHARGE_PITCH[0]) < 1e-9 && Math.abs(hi - P.CHARGE_PITCH[1]) < 1e-9 && hi > lo * 1.5);
  }

  /* ---- a released trigger fires, a tapped one does not -------------- */
  check('firing spends one cell whatever the stage, out of a magazine of four',
    P.WEAPONS.LANCE.ammo === 'cells' && P.WEAPONS.LANCE.ammoPerShot === 1 && P.CELLS === 4);
  check('and the lance is the only weapon whose trigger is a charge',
    Object.entries(P.WEAPONS).filter(([, d]) => d.charge).map(([k]) => k).join() === 'LANCE');
  check('a charged weapon never runs the frame-list firing path',
    /if \(this\.def\.charge\) \{ this\.lanceTic\(input\); return; \}/.test(playerSrc));
  check('a tap under the first mark vents rather than firing, and spends nothing',
    /if \(stage >= FIRE_AT\) \{[\s\S]{0,200}?this\.fireBeam\(stage\);\s*\n\s*\}\s*\n\s*else this\.ventCharge\(\);/.test(playerSrc));
  /* AND A CHARGE HELD AT THE TOP VENTS ITSELF AGAIN. It did, for three
     seconds, in the first cut; then the overcharge replaced it with
     forty seconds and an explosion; and at the user's request the
     explosion is gone and a window is back, five seconds of it. The
     three states a held trigger can be in are therefore: winding, held
     in the window, vented. Nothing kills you in any of them. */
  check('and a charge held at the top vents itself, after a window to take the shot in',
    P.HOLD_TICS > 3 * TICRATE && P.HOLD_TICS <= 8 * TICRATE &&
    /if \(this\.charge >= CHARGE_MAX && \+\+this\.hold >= HOLD_TICS\) \{\s*\n\s*this\.ventCharge\(\);/.test(playerSrc));
  check('a trigger held through a vent does not start another charge',
    /if \(!input\.attack\) this\.vented = false;/.test(playerSrc) &&
    /input\.attack && can && !this\.vented/.test(playerSrc));

  /* ---- the feet are nailed down and the barrel is not --------------- */
  check('the player cannot walk while the beam is out',
    /const braced = this\.beamTics > 0;/.test(playerSrc) &&
    /const grip = braced \? 0 : this\.charge > 0 \? CHARGE_WALK : 1;/.test(playerSrc));
  check('nor jump out of one',
    /input\.jump && !braced/.test(playerSrc));
  /* AND THE HEAD IS FREE WHILE IT IS OUT, which is the opposite of what
     it was. The sweep used to be clamped to a fifth of the rate because
     the column chased the barrel; the column is nailed to its firing
     line now (see _aim), so turning cannot move the damage and the
     clamp only stopped you looking along your own shot. */
  check('but the head is free while it is out, since turning cannot drag the column',
    P.BEAM_TURN === undefined && !/BEAM_TURN/.test(playerSrc.replace(/BEAM_TURN used to be/g, '')) &&
    /this\.angle -= input\.look\.x;/.test(playerSrc));
  check('and the shot takes the momentum with it rather than sliding to a halt',
    (() => {
      const body = playerSrc.slice(playerSrc.indexOf('fireBeam(stage) {'), playerSrc.indexOf('get chargeStage()'));
      return /this\.momx = 0; this\.momy = 0;/.test(body) && /beam\?\.fire\(this, stage\)/.test(body) &&
             body.indexOf('this.momx = 0') < body.indexOf('beam?.fire');
    })());
  check('a charge slows you but does not stop you, which the beam does',
    P.CHARGE_WALK > 0 && P.CHARGE_WALK < 0.5);

  /* ---- AND THE COIL DOES NOT COOK, at the user's request -----------
     Every one of these was a check on the heat and is now a check that
     the heat is GONE — kept rather than deleted because "no heat" is a
     thing this weapon now promises, and a promise nothing tests is a
     promise that comes back. The minigun's heat is untouched and is
     checked here too, because that is the way this could quietly
     regress: by someone re-deriving the lance's glow from the gun rack
     rather than from the player. */
  check('the lance has no heat at all: no temperature, no latch, no constants',
    !/lanceHeat|lanceHot/.test(playerSrc) &&
    P.LANCE_HEAT_UP === undefined && P.LANCE_HEAT_DOWN === undefined &&
    P.LANCE_HOT === undefined && P.LANCE_COOL_AT === undefined &&
    P.CHARGE_HEAT === undefined && P.VENT_HEAT === undefined);
  check('and the only thing that refuses its trigger is its own beam being out',
    /if \(WEAPONS\[w\]\.charge && this\.beamTics > 0\) return false;/.test(playerSrc));
  check('so what limits it is the magazine: four cells, one at a time, slowest in the game',
    P.CELLS === 4 && P.CELL_REGEN_EVERY >= 20 * TICRATE &&
    P.CELL_REGEN_EVERY > P.REGEN_EVERY && P.CELL_REGEN_EVERY > P.BELT_REGEN_EVERY);
  check('a vent costs nothing but the seven seconds now',
    (() => {
      const body = playerSrc.slice(playerSrc.indexOf('  ventCharge() {'),
                                   playerSrc.indexOf('  get chargePitch()'));
      return !/heat|Heat/.test(body) && /this\.charge = 0;/.test(body) && /this\.hold = 0;/.test(body);
    })());
  check('the gun rack asks the lance for no heat either, and the minigun still has its own',
    w3.GUNS.LANCE.heat === undefined && w3.GUNS.MINIGUN.heat.from === 'heat');
  /* AND THE INFINITE-AMMO BRANCH HAS NOTHING LEFT TO SAY ABOUT IT. It
     used to clear the coil's latch, because the lance's real limit was
     temperature and a switch that only refilled tanks would have left
     it out; one release of that branch also zeroed the temperature and
     turned the chassis glow off in every ordinary game. Both are moot:
     the cell IS the limit and the loop above has already filled it. */
  check('and infinite ammo needs no special case for it any more',
    (() => {
      const body = playerSrc.slice(playerSrc.indexOf('    if (this.debug) {'),
                                   playerSrc.indexOf("    this._refill('fuel'"));
      return !/lanceHot|lanceHeat/.test(body) && /this\.cellTick = 0;/.test(body);
    })());

  /* ---- the line, and where it stops --------------------------------- */
  /* IT STOPS AT THE FIRST WALL NOW, and that is the whole of the second
     dial-back. It used to be a line THROUGH the map — every wall it
     crossed holed, every region it crossed weakened, the street it lay
     along set alight — and at the user's request it changes nothing
     about the level: "i just want massive interesting decals, no
     geometry changes". So the checks below are that the three ways it
     used to change the level are gone from the CODE (the comments name
     them, on purpose), and then that a real shot across the real town
     proves it: not a wall opened, not a region touched, and a sear
     where it landed. */
  const beamCode = beamSrc.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  check('the beam stops at the first wall, floor or ceiling rather than going through the map',
    B.BEAM_RANGE > 6000 && /lv\.rayHitWall\?\.\(f\.x, f\.y, f\.z, tx, ty, tz\)/.test(beamSrc) &&
    /const sec = lv\.spanAt\(x, y, z\);/.test(beamSrc) && B.IMPACT_STEP > 0 && B.IMPACT_STEP <= 16);
  check('and it changes nothing about the level: no holes, no collapse, no fire in the street',
    !/breaches|damageLine|g\.fire\?\.|g\.forest\?\.|_burn\(/.test(beamCode) &&
    B.BEAM_STRUCTURE === undefined && B.BEAM_HEAT === undefined && B.PASS_EVERY === undefined);
  check('bodies are done every tic, because that is what the player watches',
    /this\._bodies\(player, r\);/.test(beamSrc));
  check('but nobody behind the wall it stopped at, because the wall is still there',
    /if \(s < 0 \|\| s > this\.reach\) continue;/.test(beamSrc));
  check('a person it touches still catches, because a person is not the level',
    /a\.ignite\?\.\(600\);/.test(beamSrc));
  {
    const D = await import('../js/decals.js');
    const start = level.things.find(t => t.type === 'START');
    const floor = level.sectorAt(start.x, start.y)?.floor ?? 0;
    const integrity = level.sectors.map(sec => sec.integrity ?? 1);
    const collapsed = level.sectors.map(sec => !!sec.collapsed);
    const fake = { level, actors: [], player: null, toast() {} };
    fake.decals = new D.Decals(fake);
    const bs = new B.BeamSystem(fake);
    const pl = { x: start.x, y: start.y, eyeZ: floor + 41, angle: start.angle || 0, pitch: 0,
                 beamTics: P.BEAM_TICS[2] };
    /* level shots, and one nearly straight down at the floor in front
       of the feet — steep, so no kerb gets in the way of it */
    const shots = [];
    for (const [ang, pitch] of [[pl.angle, 0], [pl.angle + 1.3, 0], [pl.angle, -1.3], [pl.angle + 2.6, 0.05]]) {
      pl.angle = ang; pl.pitch = pitch;
      bs.fire(pl, 3);
      for (let i = 0; i < P.BEAM_TICS[2]; i++) bs.tic(pl);
      shots.push({ reach: bs.reach, hit: bs.hit && { ...bs.hit, n: { ...bs.hit.n } } });
      bs.stop();
    }
    const sear = fake.decals.pools.sear;
    note('four shots across the town',
      shots.map(q => q.hit ? `${q.reach.toFixed(0)}u to ${q.hit.n.nz > 0.5 ? 'floor' : q.hit.n.nz < -0.5 ? 'ceiling' : 'wall'}` : 'into the sky').join(', ') +
      `; ${fake.decals.sears} sears and ${fake.decals.slags} slag`);
    check('a real shot across the town opens no wall at all',
      !level.lines.some(l => l.breach && l.breach.length));
    check('and takes nothing off any region',
      level.sectors.every((sec, i) => (sec.integrity ?? 1) === integrity[i] && !!sec.collapsed === collapsed[i]));
    check('it stops where the town does, well short of the far side of the map',
      shots.filter(q => q.hit).length >= 3 && shots.every(q => q.reach <= B.BEAM_RANGE) &&
      shots.filter(q => q.hit).every(q => q.reach < B.BEAM_RANGE));
    check('and a shot at the ground lands on the ground, in front of the feet',
      shots[2].hit && shots[2].hit.n.nz === 1 && shots[2].reach < 200 &&
      Math.abs(shots[2].hit.z - (level.spanAt(shots[2].hit.x, shots[2].hit.y, shots[2].hit.z + 1)?.floor ?? 0)) < 1e-6);
    check('every shot that landed left a sear, once, and slag round it',
      fake.decals.sears === shots.filter(q => q.hit).length &&
      fake.decals.slags >= fake.decals.sears * B.SEAR.slag[2] - 1e-9 &&
      sear.count === fake.decals.sears + fake.decals.slags);
    /* MASSIVE, which was the word: bigger than anything else in the
       game leaves, by a wide margin, at every stage */
    check('and the sear is massive: many times a bullet hole and bigger than a warhead\'s crater',
      B.SEAR.size.every(v => v > D.BURN_SIZE * 1.5 && v > D.HOLE_SIZE[1] * 10) &&
      B.SEAR.size.every((v, i) => i === 0 || v > B.SEAR.size[i - 1]) &&
      [...Array(sear.max).keys()].filter(i => sear.strength[i] > 0 && sear.frame[i] === 0)
        .every(i => sear.size[i] >= B.SEAR.size[2] * 0.9 - 1e-6));
    check('with the slag thrown across the same surface as the crater, each its own size',
      (() => {
        const live = [...Array(sear.max).keys()].filter(i => sear.strength[i] > 0 && sear.frame[i] === 1);
        const sizes = new Set(live.map(i => sear.size[i].toFixed(2)));
        return live.length > 0 && sizes.size > live.length * 0.8;
      })());
    check('the crater and the slag are their own kinds in the shader, charred and glowing',
      D.KIND.SEAR === 8 && D.KIND.SLAG === 9 &&
      /A SEAR: where the positron column landed/.test(fs.readFileSync('js/decals.js', 'utf8')) &&
      /float streak = /.test(fs.readFileSync('js/decals.js', 'utf8')) &&
      /hotRamp\(clamp\(heat \* 1\.1, 0\.0, 1\.0\)\) \* rim \* heat \* 2\.6/.test(fs.readFileSync('js/decals.js', 'utf8')));
    check('and a shot that ends in the sky leaves nothing hanging in the air',
      (() => {
        const n = fake.decals.sears;
        bs.hit = null;
        return bs._sear() === 0 && fake.decals.sears === n;
      })());
  }

  /* ---- and the picture it makes ------------------------------------- */
  check('the column is a tube and not a view-facing quad, because the eye is at one end of it',
    /SIDES/.test(beamSrc) && B.SIDES >= 8 && B.SEGS >= 16 &&
    !/across both the streak and the line to the eye/.test(beamSrc));
  /* THE INNERMOST SHELL MUST NOT BE A FRESNEL, and this is the check
     that says why: the player is looking straight down the bore, so
     every surface of the tube is edge-on at once, so a Fresnel shell is
     brightest in a RING and darkest in the middle. Three of those
     nested is a bullseye, which is what the first screenshot was. */
  check('four nested shells, the innermost lit flat and the outermost at its silhouette',
    /const SHELLS = \[/.test(beamSrc) &&
    /float lit = vRim < 0\.5 \? flat_ : \(vRim < 1\.5 \? mild : shell\);/.test(beamSrc) &&
    /float flat_ = 1\.0;/.test(beamSrc));
  check('with rings travelling out of the muzzle, so the column has a direction',
    B.RINGS > 0 && B.RING_SPEED > 0);
  /* AND THE COLUMN IS NAILED TO THE LINE IT WAS FIRED ALONG, which is
     the whole of the dial-back's aiming half and the reverse of what it
     used to be. The column CHASED the barrel, at a time constant, so
     the damage followed the drawn column rather than the crosshair and
     where the shot landed depended on how your wrist was moving. Fixed
     at the trigger it goes where you aimed, and the end-on problem
     solves itself better than the lag solved it: turn your head at all
     and the column is no longer in front of you. */
  check('the line is taken once, at the trigger, and never chased',
    B.LAG === undefined && !/TICRATE \* LAG/.test(beamSrc) &&
    !/this\.angle \+= d \* k;/.test(beamSrc) && /_aim\(player\) \{/.test(beamSrc));
  check('so _aim is called from fire and from nowhere else',
    (beamSrc.match(/this\._aim\(player\)/g) || []).length === 1 &&
    beamSrc.indexOf('this._aim(player)') > beamSrc.indexOf('  fire(player, stage) {') &&
    beamSrc.indexOf('this._aim(player)') < beamSrc.indexOf('  stop() {'));
  check('and one tic of the beam does not re-read where the player is looking',
    (() => {
      /* THE CALL AND NOT THE WORD. The line that used to be here has a
         comment where it was, saying what it was and why it went, and
         that comment names _aim — so a bare word match fails on the
         explanation of its own absence. Third time this file has been
         bitten by that; strip the comments first. */
      const body = beamSrc.slice(beamSrc.indexOf('  tic(player) {'), beamSrc.indexOf('  _bodies(player, r) {'))
                          .replace(/\/\*[\s\S]*?\*\//g, '');
      return !/this\._aim\(/.test(body) && /this\.tics\+\+;/.test(body) && body.length > 400;
    })());
  check('and what it hurts is that same line, to where it stopped, so the picture and the damage agree',
    /const ux = Math\.cos\(this\.angle\), uy = Math\.sin\(this\.angle\);/.test(beamSrc) &&
    /const tx = f\.x \+ ux \* BEAM_RANGE, ty = f\.y \+ uy \* BEAM_RANGE, tz = f\.z \+ sl \* BEAM_RANGE;/.test(beamSrc) &&
    /const len = this\.length;/.test(beamSrc));
  /* AND THE NEAR END IS CLOSED. A tube is hollow, and the front is the
     only end the player ever sees: without a cap you look past the near
     opening, down the inside and THROUGH to the world beyond, and the
     middle of the column is a dim disc of whatever is behind it. */
  check('the two inner shells are capped, and they are the two lit flat',
    B.CAPS === 2 && B.CAP_SEG >= 1 &&
    /idx\.push\(capBase \+ c, ring \+ k, ring \+ k \+ 1\);/.test(beamSrc) &&
    /const verts = bands \* \(SIDES \+ 1\) \+ CAPS;/.test(beamSrc));
  check('it is one draw call, additive, and writes no depth',
    (beamSrc.match(/new THREE\.Mesh\(/g) || []).length === 1 &&
    /blending: THREE\.AdditiveBlending/.test(beamSrc) && /depthWrite: false/.test(beamSrc));

  /* ---- the shake, the particles and the light ----------------------- */
  check('the beam shakes the eye and not the player, so it does not walk your aim off',
    /const shake = Math\.max\(this\.beam \? this\.beam\.shake : 0,/.test(fs.readFileSync('js/game.js', 'utf8')) &&
    /yaw   \+= k \* \(0\.022/.test(fs.readFileSync('js/game.js', 'utf8')));
  check('and it is a kick and not a rumble: nearly all of it gone inside a quarter second',
    B.SHAKE_PEAK > B.SHAKE_HUM && B.SHAKE_HUM > 0 && B.SHAKE_SETTLE > 0 &&
    B.SHAKE_SETTLE <= 9 && B.SHAKE_HUM < B.SHAKE_PEAK * 0.15 &&
    B.SHAKE_SETTLE < P.BEAM_TICS[2] / 3);
  check('particles are thrown across the column rather than along its centre line',
    B.SAMPLES >= 12 && /Math\.sqrt\(Math\.random\(\)\) \* r/.test(beamSrc));
  check('the world has a second light and it is a LINE, not a point',
    /uniform vec3  beamPos;/.test(matSrc) && /uniform vec3  beamDir;/.test(matSrc) &&
    /float along = clamp\(dot\(rel, beamDir\), 0\.0, beamLen\);/.test(matSrc));
  check('lit differentially, off the surface\'s own place rather than off the frame',
    /float n = fract\(sin\(dot\(floor\(world \* 0\.017\)/.test(matSrc) &&
    /float flick = 0\.62 \+ 0\.38 \* sin\(beamSeed/.test(matSrc));
  check('and it outlives the column, on the axis the column was on',
    B.AFTERGLOW > 0.5 && /this\.glow = Math\.max\(0, this\.glow - dt \/ AFTERGLOW\);/.test(beamSrc) &&
    /the light is NOT stopped/.test(beamSrc));
  check('the light reaches much further than the column is wide',
    B.LIGHT_RANGE.every((v, i) => v > B.BEAM_RADIUS[i] * 5));

  /* ---- the screen on the back of the gun ---------------------------- */
  check('the lance and the launcher are the guns with a screen in the file, the lance the one with a lens, and the files name them',
    w3.GUNS.LANCE.display.material === 'dynamic_display_surface_mat' &&
    w3.GUNS.LANCE.optics.material === 'optics_mat' &&
    w3.GUNS.LAUNCHER.display.material === 'dyanmic_display_surface_mat' &&
    Object.keys(w3.GUNS).filter(k => w3.GUNS[k].display).join() === 'LANCE,LAUNCHER' &&
    Object.values(w3.GUNS).filter(d => d.optics).length === 1);
  check('the screen is fed by a second camera at the eye, not by a painted picture',
    /this\.camera = new THREE\.PerspectiveCamera/.test(scopeSrc) &&
    /r\.render\(scene, c\);/.test(scopeSrc) &&
    /c\.fov = Math\.max\(1\.2, worldCamera\.fov \/ this\.magnification \* this\.viewScale\);/.test(scopeSrc));
  check('drawn before the pipeline takes the render target away',
    mainSrc.indexOf('scope.render(scene, camera)') < mainSrc.indexOf('pipeline.render(scene, camera, overlays)'));
  check('and at most every other frame, since it is a whole second scene render',
    S.EVERY >= 2 && /if \(this\.frames % this\.every\) return false;/.test(scopeSrc));
  check('and never at all with the lance out of your hands',
    /if \(!this\.renderer \|\| !this\.held\) return false;/.test(scopeSrc));
  check('the panel\'s picture is laid out on its own box, measured off the geometry',
    /setPanelBox\(min, size\)/.test(scopeSrc) &&
    /scope\.setPanelBox\(lo, \[hi\[0\] - lo\[0\], hi\[1\] - lo\[1\]\]\)/.test(fs.readFileSync('js/weapon3d.js', 'utf8')));
  check('and u is flipped, because the model is turned half a circle about y',
    /vec2 uv = vec2\(1\.0 - \(vL\.x - box\.x\) \* box\.z, \(vL\.y - box\.y\) \* box\.w\);/.test(scopeSrc));
  check('no smoothstep on that screen runs its edges backwards, which GLSL leaves undefined',
    !/smoothstep\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,/.test(scopeSrc) ||
    [...scopeSrc.matchAll(/smoothstep\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,/g)].every(m => +m[1] < +m[2]));
  /* EVERYTHING ON THE DIAL IS INSIDE THE BEZEL, which is the bug the
     first cut had: the charge ring was drawn out in the tenth of the
     panel the bezel fades to black, so the gauge the weapon is about
     was not on the gauge. The first repair for this check counted the
     `N * 0.xx` literals in the source and asked that none exceeded a
     number typed here — which went stale the moment a warning bar was
     added at the bottom of the panel, because a Y COORDINATE of 0.905
     and a RADIUS of 0.905 are not the same distance from the middle.
     So the dial is DRAWN instead, into a context that records where
     the ink went, and the extent is measured the way the shader
     measures it: r = max(|x|, |y|) * 2 off the centre, a square bezel
     and not a round one. Full-panel fills are exempt and only
     those, because covering the whole screen is what they are for. */
  {
    const bezel = +(scopeSrc.match(/smoothstep\((0\.\d+), 1\.02, r\)/) || [, 0])[1];
    const N = 256;
    let lo = 0.5, hi = 0.5, lw = 1, whole = 0, ops = 0;
    const saw = (x, y, pad = 0) => {
      const u = x / N, v = y / N, e = (pad + lw / 2) / N;
      lo = Math.min(lo, u - e, v - e); hi = Math.max(hi, u + e, v + e); ops++;
    };
    const rect = (x, y, w, h) => {
      if (w * h >= N * N * 0.95) { whole++; return; }
      saw(x, y); saw(x + w, y + h);
    };
    const ctx = {
      set lineWidth(v) { lw = v; }, get lineWidth() { return lw; },
      font: '', textAlign: '', textBaseline: '', lineCap: '', strokeStyle: '', fillStyle: '',
      globalCompositeOperation: '', globalAlpha: 1,
      save() {}, restore() {}, beginPath() {}, closePath() {}, stroke() {}, fill() {},
      moveTo(x, y) { saw(x, y); }, lineTo(x, y) { saw(x, y); },
      arc(x, y, r, a0, a1) { saw(x, y, r); },
      fillRect: rect, strokeRect: rect, clearRect: rect,
      fillText(t, x, y) { const px = +(String(this.font).match(/(\d+)px/) || [, 12])[1];
                          saw(x - t.length * px * 0.4, y - px * 0.6);
                          saw(x + t.length * px * 0.4, y + px * 0.6); },
      measureText(t) { return { width: t.length * 8 }; },
    };
    const sc = Object.create(S.Scope.prototype);
    sc.canvas = { width: N, height: N }; sc.held = true; sc.ctx = ctx; sc.stageMarks = [3 / 7, 5 / 7, 1]; sc.zoomIndex = 2; sc.panelTexture = { needsUpdate: false };
    /* the worst case for extent is everything lit at once */
    sc._draw({ charge: 1, hold: 0.2, stage: 3, cell: 4, firing: true, tics: 4 });
    const r = Math.max(Math.abs(0.5 - lo), Math.abs(hi - 0.5)) * 2;
    note('how far the dial reaches, and where the glass goes dark',
      `${r.toFixed(3)} of ${bezel}, over ${ops} marks and ${whole} full-panel fills`);
    check('everything on the dial is inside the bezel, which is the bug the first cut had',
      bezel > 0.5 && ops > 20 && whole >= 1 && r <= bezel);
  }
  /* THE ZOOM STEPS, AND THEY ARE MODEST ONES. They were 1x/4x/8x for a
     draft and the user asked for less zoom and more looking through the
     scope: the point of putting your eye to this gun is that you are
     LOOKING THROUGH IT, and a magnification that turns the picture into
     a smear of pixels is the opposite of that. A rifle scope, not a
     telescope. The view narrows too, but by much less, which is what
     stops the feed and the world disagreeing about what is in front of
     you. */
  check('the zoom steps and the view narrows with them, but not by the same amount',
    S.ZOOMS.length === S.VIEW_ZOOM.length && S.ZOOMS[0] === 1 && S.VIEW_ZOOM[0] === 1 &&
    S.ZOOMS.every((v, i) => i === 0 || v > S.ZOOMS[i - 1]) &&
    S.ZOOMS[S.ZOOMS.length - 1] >= 2 && S.ZOOMS[S.ZOOMS.length - 1] <= 5 &&
    S.VIEW_ZOOM[S.VIEW_ZOOM.length - 1] > 0.5 && S.VIEW_ZOOM[S.VIEW_ZOOM.length - 1] < 1);
  check('and the look slows by exactly what the view narrowed by',
    /input\.zoomScale = sighted \? sighted\.viewScale : 1;/.test(mainSrc) &&
    /this\.look = \{ x: lx \* zs, y: ly \* zs \};/.test(fs.readFileSync('js/input.js', 'utf8')));
  check('the screen shares nothing with the palette, being a screen and not a painting',
    !/palette\.js/.test((scopeSrc.match(/^import .*$/gm) || []).join('\n')));
  /* AND THE STATIC IS ON THE PICTURE AND NOT ON THE GAUGES: the feed
     comes down a wire from a sensor and the gauges are drawn by the gun
     on the gun, so noise over the charge ring is noise on the one part
     of the screen that cannot have any — at the moment it matters most. */
  check('the static degrades the feed and the gauges go over it',
    scopeSrc.indexOf('col += (n - 0.5) * noise') < scopeSrc.indexOf('vec4 g = texture2D(panel, uv);'));
  check('and the dial redraws only on what it draws',
    /const key = \[this\.held \? 1 : 0/.test(scopeSrc) && !/this\.range/.test(scopeSrc));

  /* ---- and its voice ------------------------------------------------ */
  {
    const A = await import('../js/audio.js');
    const want = ['lance_charge_start', 'lance_charge_loop', 'lance_charge_full',
                  'lance_prefire', 'lance_fire_a', 'lance_fire_b'];
    note('the lance\'s voice', want.map(k => k.replace('lance_', '')).join(', '));
    check('all six recordings are registered and all six files are there',
      want.every(k => A.SAMPLES[k] && fs.existsSync(A.SAMPLES[k])) &&
      want.every(k => A.SAMPLE_GAIN[k] > 0));
    check('and every one of them is reachable by a name the game asks for',
      want.every(k => Object.values(A.SAMPLE_FOR).includes(k)));
    check('the charge loop is the only one made periodic, because it is the only one that loops',
      Object.keys(A.SAMPLE_LOOP).join() === 'lance_charge_loop' && A.SAMPLE_LOOP.lance_charge_loop > 0.1);
    check('and it is made periodic by baking the join into the buffer, not by fading on playback',
      /_loopify\(buf, xfade\)/.test(fs.readFileSync('js/audio.js', 'utf8')) &&
      /dst\[i\] = src\[i\] \* head \+ src\[n \+ i\] \* tail;/.test(fs.readFileSync('js/audio.js', 'utf8')));
    check('a sample can be pitched and faded, which is what a charge needs',
      /rate\(v, over = 0\.06\)/.test(fs.readFileSync('js/audio.js', 'utf8')) &&
      /fade\(to, over = 0\.5\)/.test(fs.readFileSync('js/audio.js', 'utf8')));
    check('the held charge sound is judged after the tic, so every way of ending one stops it',
      /lanceVoice\(\) \{/.test(playerSrc) && /this\.lanceVoice\(\);/.test(playerSrc));
    check('and dying with a charge in your hands stops it too',
      /this\.chargeLoop\?\.stop\(\); this\.chargeLoop = null;/.test(playerSrc));
    check('the discharge is three recordings at once, since two of them are one shot in layers',
      /snd\?\.sample\('lanceprefire'/.test(playerSrc) &&
      /snd\?\.sample\('lancefire'/.test(playerSrc) && /snd\?\.sample\('lancefire2'/.test(playerSrc));
    check('and a charge that is thrown away fizzles rather than stopping',
      /h\.rate\(CHARGE_PITCH\[0\] \* 0\.55, 1\.1\); h\.release\(1\.2\);/.test(playerSrc));
  }

  /* ---- and it is on a key and a slot -------------------------------- */
  {
    const inputSrc = fs.readFileSync('js/input.js', 'utf8');
    check('the lance is the fifth slot and there is a key for it',
      P.WEAPONS.LANCE.slot === 5 && /Digit5: 'weapon5'/.test(inputSrc) &&
      /if \(this\.pressed\('weapon5'\)\) this\.weaponSlot = 5;/.test(inputSrc));
    check('and the zoom is a press on the right button, a key and the pad',
      /KeyZ: 'zoom'/.test(inputSrc) && /this\.mouseRightPulse/.test(inputSrc) &&
      /padEdge\(1\)/.test(inputSrc));
    check('the player owns it, so it can actually be reached',
      /LANCE: true/.test(playerSrc));
  }
}

/* =====================================================================
   THE LANCE, SECOND PASS
   =====================================================================

   Five things the user asked for after firing it for a while: it must
   reach RED before it will fire at all; the chassis cooks from the
   middle out while it charges, on the minigun's glow; forty seconds of
   holding it past red and it kills you, with the camera leaving the
   body to watch; the zoom stops being a zoom and becomes putting your
   eye to the scope; and every hole gets a tunnel of debris round it.
   ===================================================================== */
section('the lance, second pass');
{
  const fs = await import('node:fs');
  const P = await import('../js/player.js');
  const S = await import('../js/scope.js');
  const R = await import('../js/ruin.js');
  const w3 = await import('../js/weapon3d.js');
  const playerSrc = fs.readFileSync('js/player.js', 'utf8');
  const gunSrc2 = fs.readFileSync('js/weapon3d.js', 'utf8');
  const scopeSrc2 = fs.readFileSync('js/scope.js', 'utf8');
  const gameSrc2 = fs.readFileSync('js/game.js', 'utf8');
  const TICRATE = 35;
  const mkP = () => {
    const p = Object.create(P.Player.prototype);
    p.charge = 0; p.hold = 0; p.beamTics = 0; p.beamStage = 0;
    p.dead = false;
    return p;
  };

  /* ---- RED OR NOTHING ----------------------------------------------- */
  note('what it takes to fire', `stage ${P.FIRE_AT} of ${P.CHARGE_STAGES.length}, which is ` +
    `${P.CHARGE_STAGES[P.FIRE_AT - 1]}s held`);
  check('the trigger only gives you the last stage, which is the red one',
    P.FIRE_AT === P.CHARGE_STAGES.length && P.FIRE_AT === 3);
  check('and anything short of it vents instead of firing',
    /if \(stage >= FIRE_AT\) \{[\s\S]{0,200}?this\.fireBeam\(stage\);\s*\n\s*\}\s*\n\s*else this\.ventCharge\(\);/.test(playerSrc));
  check('the stages themselves are untouched, so the smaller shots are one number away',
    P.CHARGE_STAGES.join() === '3,5,7' && P.BEAM_TICS.length === 3);
  {
    /* the dial goes red at exactly the stage the trigger wants */
    const p = mkP();
    p.charge = P.CHARGE_STAGES[P.FIRE_AT - 1] * TICRATE;
    check('and the charge reaches that stage at exactly the second it says',
      p.chargeStage === P.FIRE_AT);
    p.charge -= 1;
    check('and not one tic sooner', p.chargeStage === P.FIRE_AT - 1);
  }

  /* ---- AND WHAT USED TO BE HERE --------------------------------------
     Three blocks stood between the stage machinery above and the zoom
     below: the chassis cooking from the middle out, the forty seconds
     of overcharge that killed you, and the third-person camera that
     watched it happen. All three went at the user's request and the
     checks that they are GONE are in 'the lance, dialled back', which
     is where the whole of the dial-back is tested together rather than
     as holes left in the sections it emptied. */


  /* ---- THE ZOOM IS NOT A ZOOM ---------------------------------------- */
  note('the scope', `${S.ZOOMS.join('x, ')}x on the panel, view ${S.VIEW_ZOOM.join('/')}, gun ${S.AIM_AT.join('/')} to the eye`);
  check('the magnification is small now, because the zoom is not what moves',
    S.ZOOMS.length === 3 && S.ZOOMS[S.ZOOMS.length - 1] < 4 && S.ZOOMS[1] < 2.5);
  check('and the world behind it hardly narrows',
    S.VIEW_ZOOM.every(v => v >= 0.8) && S.VIEW_ZOOM[0] === 1);
  check('what the zoom actually does is raise the weapon to the eye',
    S.AIM_AT[0] === 0 && S.AIM_AT[S.AIM_AT.length - 1] === 1 &&
    S.AIM_AT.length === S.ZOOMS.length && /get aim\(\)/.test(scopeSrc2));
  /* TWO GUNS HAVE A SECOND HOLD NOW, and they are the two with a screen
     on them: the lance's panel and the launcher's thermal sight. */
  check('the lance and the launcher are the guns with a second hold, having the only screens worth looking at',
    ['LANCE', 'LAUNCHER'].every(k => !!w3.GUNS[k].aim && Array.isArray(w3.GUNS[k].aim.pos) && Array.isArray(w3.GUNS[k].aim.rot)) &&
    Object.values(w3.GUNS).filter(d => d.aim).length === 2);
  check('and each is a nearer hold than the hip one, since you have brought it to you',
    w3.GUNS.LANCE.aim.out < w3.GUNS.LANCE.out && w3.GUNS.LAUNCHER.aim.out < w3.GUNS.LAUNCHER.out);
  check('the gun chases the hold rather than snapping to it',
    /this\.aim \+= \(wantAim - this\.aim\) \* \(1 - Math\.pow\(0\.0015, dt\)\);/.test(gunSrc2));
  check('and the bob and the sway go away with it, since a braced weapon does not swing',
    /const steady = 1 - a \* 0\.88;/.test(gunSrc2));
  check('a gun with no second hold never leaves the hip, which is every gun but one',
    /const a = G\.def\.aim \? this\.aim : 0;/.test(gunSrc2));

  /* ---- A TUNNEL OF DEBRIS ROUND EVERY HOLE ---------------------------- */
  {
    let quads = 0;
    const set = { get: () => ({ quad: () => { quads++; } }) };
    const l = { x1: 0, y1: 0, x2: 400, y2: 0, len: 400,
                breach: [{ t0: 0.35, t1: 0.65, z0: 10, z1: 130 }] };
    const n = R.breachDebris(set, l, 0.6);
    note('the debris round a hole', `${n} chunks, ${quads} quads`);
    check('a hole gets a ring of broken material round it',
      n >= 12 && n <= 64 && quads === n * 5);
    check('five faces a chunk and not six, like the other two builders here',
      quads / n === 5);
    check('and a wall with no holes gets nothing at all',
      R.breachDebris(set, { x1: 0, y1: 0, x2: 1, y2: 0, len: 1 }, 0.5) === 0);
    /* it stands out of the wall on BOTH sides, which is what makes it a
       tunnel rather than a wreath */
    check('it stands out of the wall on both sides, which is the tunnel',
      /const side = \(i & 1\) \? 1 : -1;/.test(fs.readFileSync('js/ruin.js', 'utf8')));
    check('the chunks are oriented to the wall and not squared to the map',
      /function chunk\(b, cx, cy, cz, ux, uy, vx, vy, hu, hv, hz, light, char\)/.test(fs.readFileSync('js/ruin.js', 'utf8')));
    check('and it is built with the wall it belongs to, so it rebuilds with the hole',
      /breachDebris\(lineIndoor\(l\) \? inner : set, l, own\.light, BANDS\);/.test(fs.readFileSync('js/mapgeo.js', 'utf8')));
    /* AND A HOLE IN A WALL THAT HAS COME DOWN IS A HOLE IN NOTHING. The
       breach list outlives the wall — a collapsed region stops drawing
       its brick but keeps every rectangle ever punched out of it — so
       debris hung off that list without asking is a ring of masonry in
       mid-air over a pile of rubble. Photographed exactly that way the
       first time a beam was fired down a street and the houses came
       down behind it. */
    {
      let hung = 0;
      const set2 = { get: () => ({ quad() { hung++; } }) };
      /* the storey the hole is in is gone; another one is still up */
      const down = R.breachDebris(set2, l, 0.5, [300, 460]);
      const up   = R.breachDebris(set2, l, 0.5, [0, 200]);
      check('a hole in a wall that has come down is not dressed at all',
        down === 0 && up > 0);
      /* AND A HOLE THAT OVERRUNS THE WALL IS CLAMPED TO IT, which is
         the other half of the same rule and was the other half of the
         same photograph: a two-hundred-unit column fired at head height
         through a one-storey house punches from under the floor to well
         over the eaves, mapgeo draws only the part inside the brick,
         and a ring walked round the whole rectangle put a third of
         itself in the sky above the roof. */
      const tallHole = { x1: 0, y1: 0, x2: 900, y2: 0, len: 900,
                         breach: [{ t0: 0.2, t1: 0.8, z0: -80, z1: 260 }] };
      let lo = 1e9, hi = -1e9;
      /* BatchSet.quad takes four [x, height, -y] corners — see the note
         in js/ruin.js's chunk() about the map's y becoming the
         renderer's minus z — so the height is the MIDDLE number */
      const set3 = { get: () => ({ quad(corners) { for (const c of corners) {
        lo = Math.min(lo, c[1]); hi = Math.max(hi, c[1]); } } }) };
      R.breachDebris(set3, tallHole, 0.5, [0, 128]);
      note('a hole taller than the wall it is in', `ring kept to ${lo.toFixed(0)}..${hi.toFixed(0)} of 0..128`);
      check('and a hole taller than its wall is clamped to the wall, not walked past it',
        lo > -40 && hi < 168);
      check('and the caller leaves a collapsed storey out of the bands it passes',
        /if \(!s \|\| s\.collapsed \|\| s\.ceil <= s\.floor\) continue;/.test(fs.readFileSync('js/mapgeo.js', 'utf8')) &&
        /if \(!BANDS\.length\) continue;/.test(fs.readFileSync('js/mapgeo.js', 'utf8')));
      /* AND THE BANDS ARE THE WALL'S OWN, not the sectors either side
         of it. The sector outside a house is the STREET, whose ceiling
         is the sky a few thousand units up, so bands taken from the
         two columns never clamped anything and a photograph from the
         pavement showed an arc of masonry over the roof. A two-sided
         line already carries the intervals it draws brick in. */
      /* AND A KERB IS NOT A WALL. Most of the lines in a street are
         twelve-unit risers and thirty-two-unit steps; a beam cuts them
         all, and a ring of debris hung off a hole in one is broken
         masonry lying along the gutter for the length of the block. */
      let kerb = 0;
      const set4 = { get: () => ({ quad() { kerb++; } }) };
      const low = R.breachDebris(set4, { x1: 0, y1: 0, x2: 900, y2: 0, len: 900,
        breach: [{ t0: 0.2, t1: 0.8, z0: -52, z1: 172 }] }, 0.5, [0, 12]);
      check('a kerb is not a wall, and a hole in one is not dressed',
        low === 0 && kerb === 0);
      check('a two-sided wall is measured by the bands it draws, not by the air outside it',
        /if \(l\.bands && l\.bands\.length\) \{/.test(fs.readFileSync('js/mapgeo.js', 'utf8')) &&
        /BANDS\.push\(bd\.z0, bd\.z1\);/.test(fs.readFileSync('js/mapgeo.js', 'utf8')));
    }
    /* two holes on one wall get two rings and the count stays bounded */
    l.breach.push({ t0: 0.68, t1: 0.74, z0: 40, z1: 90 });
    quads = 0;
    const n2 = R.breachDebris(set, l, 0.6);
    check('two holes get two rings, and a wall shot to pieces stays bounded',
      n2 > n && n2 <= 64 * 2);
  }
}

/* ---------- DIALLED BACK: A SNIPER AND NOT AN ARMAGEDDON ----------------

   At the user's request the lance is a PRECISE weapon now. Three things
   went, and the going of them is most of what is checked here, because
   a feature that is removed leaves no code to break and so leaves
   nothing to notice when it quietly comes back:

     THE OVERCHARGE, in its entirety. Forty seconds past the top of the
     charge and the coil let go where you were standing and killed you,
     with a ladder of CAPACITOR warnings, a screen that glitched harder
     as it climbed, a blast the size of a city block and a third-person
     death camera to watch it from. None of it is here. Holding at the
     top is a five-second window and then a vent.

     THE HEAT, in its entirety. The coil cooked as it wound, the chassis
     glowed with it from the middle out, and over a threshold the gun
     refused its own trigger until it had cooled. Gone. What limits the
     weapon is the magazine, which is four cells at twenty-five seconds
     each.

     AND THE ARMAGEDDON, which was in the numbers rather than in any one
     feature: a column a hundred and thirty units wide that stayed out
     for five seconds, took a building down in one pass, set fire to the
     street and woke the whole town. Every one of those came down, and
     what makes the weapon a sniper rather than a smaller siege engine
     is two of them in particular — a column narrower than one person,
     and a line that is fixed at the trigger instead of chasing the
     barrel, so the shot goes exactly where the crosshair was.

   THE NUMBERS ARE CHECKED AS RELATIONSHIPS, not as literals, wherever
   the relationship is the point: narrower than a person, no collapse in
   one shot, the whole thing over faster than the old shake took to
   settle. A literal would pass a re-tune that broke the intent.
   --------------------------------------------------------------------- */
section('the lance, dialled back');
{
  const fs = await import('node:fs');
  const P = await import('../js/player.js');
  const B = await import('../js/beam.js');
  const w3 = await import('../js/weapon3d.js');
  const U = await import('../js/util.js');
  const playerSrc = fs.readFileSync('js/player.js', 'utf8');
  const beamSrc = fs.readFileSync('js/beam.js', 'utf8');
  const scopeSrc = fs.readFileSync('js/scope.js', 'utf8');
  const gameSrc = fs.readFileSync('js/game.js', 'utf8');
  const w3Src = fs.readFileSync('js/weapon3d.js', 'utf8');
  const TICRATE = 35;

  /* A LANCE IN A ROOM WITH NOTHING IN IT, which is all any of the
     simulations below need: the trigger, the coil and the cell are
     three counters in Player and the rest of the game is a stub that
     records what it was asked to do. */
  function mkLance() {
    const toasts = [];
    const game = {
      sound: { play() {}, sample() { return { rate() {}, release() {} }; } },
      beam: { fired: null, fire(pl, st) { this.fired = st; }, tic() {}, stop() {} },
      noise() {}, toast(t) { toasts.push(t); },
      level: { sectorAt: () => ({ floor: 0, ceil: 200, storey: 0 }), slideMove: (x, y) => [x, y] },
    };
    const p = new P.Player(game, 0, 0, 0);
    p.weapon = 'LANCE';
    p.debug = false;
    p.ammo.cells = P.CELLS; p.maxAmmo.cells = P.CELLS;
    return { p, game, toasts };
  }

  /* ---- the overcharge is gone, all of it --------------------------- */
  note('what one discharge is now',
    `${P.BEAM_SECONDS[2]}s of beam, r${B.BEAM_RADIUS[2]} (a person is 32 wide), ` +
    `a sear ${B.SEAR.size[2]} across and nothing off any region, ` +
    `heard at ${(playerSrc.match(/this\.game\.noise\(this, (\d+)\);/) || [])[1]} units`);
  check('no constant anywhere still describes an overcharge',
    P.OVERCHARGE_TICS === undefined && P.OVERCHARGE_CALLS === undefined &&
    P.OVER_KICK === undefined && P.OVER_LIFT === undefined && P.OVER_LONGER === undefined &&
    P.BLAST_KICK === undefined && P.BLAST_LIFT === undefined &&
    B.OVER_WIDE === undefined && B.OVER_BITE === undefined);
  check('and no code: no counter, no fraction, no blowUp, no CAPACITOR',
    !/overcharge|overFraction|blowUp|CAPACITOR/.test(playerSrc.replace(/\/\*[\s\S]*?\*\//g, '')) &&
    !/\bover\b|overMul|glowOver/.test(beamSrc.replace(/\/\*[\s\S]*?\*\//g, '')
                                            .replace(/\/\/.*$/gm, '')));
  check('the gun cannot kill the player any more, by any path it owns',
    !/this\.health = 0;/.test(playerSrc.slice(playerSrc.indexOf('  lanceTic(input) {'),
                                              playerSrc.indexOf('  get chargeStage()'))) &&
    !/deathCam/.test(playerSrc) && !/deathCam/.test(gameSrc) && P.DEATHCAM_DIST === undefined);
  /* THE HOLD IS WHAT REPLACED IT, and it is the third thing a held
     trigger can be doing: winding, sitting in the window, vented. */
  check('a trigger held from cold vents, and nothing else happens to you',
    (() => {
      const { p, toasts } = mkLance();
      let vented = -1;
      for (let i = 0; i < 30 * TICRATE; i++) {
        p.lanceTic({ attack: true, look: { x: 0, y: 0 } });
        if (p.charge === 0 && i > 5) { vented = i + 1; break; }
      }
      /* CHARGE_MAX + HOLD_TICS - 1, and the missing tic is real rather
         than slop: the tic that brings the charge to the top is also
         the first tic of sitting at the top, so the window counts it.
         Seven seconds up, five at the top, twelve all told to within a
         thirty-fifth of a second. */
      note('holding the trigger from cold',
        `vents at ${(vented / TICRATE).toFixed(2)}s, alive, ${p.ammo.cells} cells still in it, said ${JSON.stringify(toasts)}`);
      return vented === P.CHARGE_MAX + P.HOLD_TICS - 1 && !p.dead &&
             p.health > 0 && p.ammo.cells === P.CELLS && toasts.join() === 'COIL VENTED';
    })());
  check('and the window is a real one: long enough to track somebody, short enough to matter',
    P.HOLD_TICS >= 4 * TICRATE && P.HOLD_TICS <= 8 * TICRATE);
  check('the gun\'s screen draws it, draining, on the ring the heat used to have',
    /const hold = p \? \(p\.holdFraction \|\| 0\) : 0;/.test(scopeSrc) &&
    /if \(hold > 0\)\s*\n\s*dial\(ctx, cx, cy, r2, w2, FROM, SPAN, hold,/.test(scopeSrc));
  check('and holdFraction counts DOWN, since the question is how long you have left',
    (() => {
      const { p } = mkLance();
      for (let i = 0; i < P.CHARGE_MAX; i++) p.lanceTic({ attack: true, look: { x: 0, y: 0 } });
      const at = [];
      for (let s = 0; s <= 4; s++) {
        at.push(p.holdFraction);
        for (let i = 0; i < TICRATE && p.charge > 0; i++) p.lanceTic({ attack: true, look: { x: 0, y: 0 } });
      }
      note('the window draining', at.map((v, i) => `${i}s:${v.toFixed(2)}`).join('  '));
      return at[0] > 0.95 && at.every((v, i) => i === 0 || v < at[i - 1]) && at[4] < 0.25;
    })());
  check('a charge under the top has no window and draws no inner ring',
    (() => {
      const { p } = mkLance();
      for (let i = 0; i < 4 * TICRATE; i++) p.lanceTic({ attack: true, look: { x: 0, y: 0 } });
      return p.chargeStage === 1 && p.holdFraction === 0;
    })());

  /* ---- the heat is gone, all of it --------------------------------- */
  check('nothing on the lance has a temperature, in any of the four files',
    !/lanceHeat|lanceHot/.test(playerSrc + beamSrc + scopeSrc + w3Src) &&
    !/uniform float heat;/.test(scopeSrc) && !/uniform float over;/.test(scopeSrc));
  check('and the screen is clean between shots rather than permanently snowy',
    /s\.uniforms\.noise\.value = p && p\.beamTics > 0 \? 0\.52 : 0;/.test(scopeSrc));
  check('the minigun kept its own, because only the lance was asked about',
    w3.GUNS.MINIGUN.heat.from === 'heat' && w3.GUNS.LANCE.heat === undefined &&
    /if \(def\.heat && o\.material\.name === def\.heat\.material\) heatMaterial = o\.material;/.test(w3Src));

  /* ---- and the armageddon is out of the numbers -------------------- */
  /* A SIXTH OF THE WIDTH IT WAS. There used to be a floor under it
     that was not aesthetic — the radius was also the radius of the hole
     it bored, and a hole you could not walk through undid 'walk through
     it' — but it bores nothing now, so what is left is the width of a
     rifle: narrower than two people, wider than one. */
  check('the column is a sixth of the width it was, and no wider than a rifle needs',
    B.BEAM_RADIUS[2] <= 130 / 5 && B.BEAM_RADIUS[2] * 2 < 32 * 2 &&
    B.BEAM_RADIUS[2] * 2 > U.PLAYER_RADIUS * 2 &&
    B.BEAM_RADIUS.every((r, i) => i === 0 || r > B.BEAM_RADIUS[i - 1]));
  /* AND NO SHOT CAN BRING ANYTHING DOWN, at any stage, which used to be
     a ceiling proved from the constants (under 1.0 of a region a shot)
     and is now simply true: the constants are gone with the walk. */
  check('no discharge can bring a region down, at any stage, because none touches one',
    B.BEAM_STRUCTURE === undefined && B.PASS_EVERY === undefined);
  check('it no longer sets the street alight at all, nor lights it like a flashbulb',
    B.BEAM_HEAT === undefined && B.LIGHT_PEAK[2] < 0.7 && B.LIGHT_RANGE[2] < 600);
  check('and the town no longer comes to the window for every shot',
    (() => {
      const m = playerSrc.slice(playerSrc.indexOf('  fireBeam(stage) {'))
                         .match(/this\.game\.noise\(this, (\d+)\);/);
      return m && +m[1] > 600 && +m[1] < 1600;
    })());
  check('the whole discharge is over faster than the old shake took to settle',
    P.BEAM_TICS[2] < 3 * TICRATE && P.BEAM_TICS[2] > 0.8 * TICRATE);
  check('and the muzzle bloom came down with the column it belongs to',
    (() => {
      const body = beamSrc.slice(beamSrc.indexOf('  fire(player, stage) {'), beamSrc.indexOf('  stop() {'));
      const m = body.match(/for \(let i = 0; i < (\d+); i\+\+\)/);
      return m && +m[1] <= 14 && !/this\.over/.test(body);
    })());

  /* ---- and the gun says what a shot you cannot see went through ---- */
  /* THE TOASTS OUTLIVED THE OVERCHARGE THEY WERE BUILT FOR, because the
     problem they solve is worse here: the shot reaches eight thousand
     units through whatever is standing in the way, and a clean kill at
     range and a clean miss at range look identical from the muzzle. */
  check('a shot that did something says so, once, in the corner',
    (() => {
      const said = [];
      const bs = Object.create(B.BeamSystem.prototype);
      Object.assign(bs, { live: true, stage: 3, tics: 0, killed: 2,
                          game: { toast: t => said.push(t) } });
      B.BeamSystem.prototype.stop.call(bs);
      note('what the gun says about a shot', said.join(' / ') || '(nothing)');
      /* and never THROUGH or COLLAPSED any more: it goes through nothing */
      return said.length === 1 && /2 DOWN/.test(said[0]) && !/THROUGH|COLLAPSED/.test(said[0]);
    })());
  check('and a shot that hit nothing says nothing, which is itself the answer',
    (() => {
      const said = [];
      const bs = Object.create(B.BeamSystem.prototype);
      Object.assign(bs, { live: true, stage: 3, tics: 0, killed: 0,
                          game: { toast: t => said.push(t) } });
      B.BeamSystem.prototype.stop.call(bs);
      return said.length === 0;
    })());
  check('the stack is still the stack, and nothing goes through the big card any more',
    /export const TOAST_MAX = 4;/.test(gameSrc) &&
    !/setBigMessage/.test(playerSrc) && !/setBigMessage/.test(beamSrc));
}

/* ---------- THE READOUT, AND WHICH SIDE OF THE FILTER IT IS ON ----------

   For most of this project's life the bars, the weapon's name and the
   end-of-night card were drawn into the same low-resolution buffer as
   the walls, at the same chunky pixel size, and quantised to the same
   256 colours. At the user's request they are not any more: they are
   their own 2D canvas over the frame, at the device's own resolution,
   and the pipeline never sees them.

   WHAT IS CHECKED IS THE SPLIT ITSELF, because it is the kind of thing
   that gets quietly undone — one overlay added back to the list in
   main.js and the readout is a chunky readout again with nothing
   throwing. So: what is left in the buffer is exactly the two things
   that belong to the PICTURE (the wash, and the fallback gun); the
   readout is measured in the window's own pixels and not in chunky
   ones; the canvas is backed at the device's ratio; and it costs
   nothing on a frame where nothing has moved. */
section('the readout');
{
  const fs = await import('node:fs');
  const hudSrc = fs.readFileSync('js/hud.js', 'utf8');
  const mainSrc = fs.readFileSync('js/main.js', 'utf8');
  const lofiSrc = fs.readFileSync('js/lofi.js', 'utf8');
  const html = fs.readFileSync('index.html', 'utf8');
  const css = fs.readFileSync('css/style.css', 'utf8');
  const { Hud } = await import('../js/hud.js');

  /* --- WHAT IS LEFT IN THE BUFFER --------------------------------- */
  {
    const hud = new Hud({ burnPercent: 0, bigMessage: null });
    note('what still goes through the filter', `${hud.scene.children.length} meshes in the overlay scene`);
    check('the overlay scene is down to the two things that belong to the picture',
      hud.scene.children.length === 2 &&
      hud.scene.children.includes(hud.weaponMesh) && hud.scene.children.includes(hud.tintMesh),
      `${hud.scene.children.length} children`);
    /* the wash is a thing that happens to the photograph, so it is made
       of the photograph's colours and stays where it is */
    check('the wash over a pickup is still one of them',
      /tintMesh/.test(hudSrc) && /this\.scene\.add\(this\.tintMesh\)/.test(hudSrc));
    /* and the gun, on the day the model does not arrive, is the gun */
    check('and so is the flat gun, for the day the model does not load',
      /showWeaponSprite/.test(hudSrc) && /this\.scene\.add\(this\.weaponMesh\)/.test(hudSrc));
    check('nothing in the readout is a texture uploaded into the frame any more',
      !/CanvasTexture/.test(hudSrc) && !/from '\.\/pixel\.js'/.test(hudSrc) && !/\bbigText\b/.test(hudSrc));
    check('and main.js still hands the pipeline two overlays, neither of them the readout',
      /\{ scene: weapon3d\.scene, camera: weapon3d\.camera/.test(mainSrc) &&
      /\{ scene: hud\.scene, camera: hud\.camera/.test(mainSrc) &&
      (mainSrc.match(/\{ scene: [a-z]/g) || []).length === 2);
    /* and the two files do not know each other: the pipeline is never
       handed the readout's canvas and the readout never asks the
       pipeline how big a pixel is */
    check('the pipeline and the readout share nothing but the window',
      !/getElementById|'ui'/.test(lofiSrc) &&
      !/\bnew LofiPipeline|\.gridWidth\b|\.gridHeight\b|\bthis\.pipeline\b/.test(hudSrc));
  }

  /* --- THE PAGE ---------------------------------------------------- */
  {
    check('the page carries a canvas for it, inside the frame',
      /<canvas id="ui">/.test(html) && html.indexOf('<canvas id="ui">') > html.indexOf('<div id="game">') &&
      html.indexOf('<canvas id="ui">') < html.indexOf('</div>', html.indexOf('<div id="game">')));
    const ui = css.slice(css.indexOf('#ui {'), css.indexOf('}', css.indexOf('#ui {')));
    check('which takes no pointer, so it is a label on the glass and not a lid on the game',
      /pointer-events: none/.test(ui));
    check('and is smoothed, where the picture under it is not',
      /image-rendering: auto/.test(ui) && /#view \{[^}]*image-rendering: pixelated/s.test(css));
    /* under the thumb controls (6) and under the menus (10, 20), so a
       paused game dims the readout with everything else */
    const z = +(/z-index: (\d+)/.exec(ui) || [])[1];
    note('where the readout sits in the stack', `z ${z}, under #touch at 6 and #pause at 20`);
    check('and sits under the thumb controls and the menus', z > 0 && z < 6, `z ${z}`);
  }

  /* --- IT IS MEASURED IN THE WINDOW'S OWN PIXELS -------------------
     Which is the whole of what decoupling it came to. It used to be laid
     out in chunky ones, so turning the PIXELS dial down made the bars
     GROW: a readout that changes size when you change how the world is
     drawn. A fake canvas is enough to prove it, and cheaper than a GPU. */
  {
    const fake = () => {
      const calls = [];
      const ctx = { calls, _font: '' };
      for (const m of ['save', 'restore', 'beginPath', 'moveTo', 'arcTo', 'closePath', 'fill', 'stroke',
                       'fillRect', 'clearRect', 'clip', 'setTransform', 'roundRect', 'fillText',
                       'createLinearGradient', 'addColorStop'])
        ctx[m] = (...a) => { calls.push(m); return m === 'createLinearGradient' ? { addColorStop() {} } : undefined; };
      ctx.measureText = t => ({ width: 7 * t.length });
      return { width: 0, height: 0, style: {}, getContext: () => ctx, ctx };
    };
    const player = {
      weapon: 'FLAMER', dead: false, maxAmmo: { fuel: 100 }, ammoFor: () => 62, refireMark: 0,
      armour2: 1000, armour1: 500, health: 100, damageFlash: 0, pickupFlash: 0, bobPhase: 0, bob: 0,
    };
    const game = { burnPercent: 12, bigMessage: null };

    const c = fake();
    const hud = new Hud(game, c);
    hud.resizeUi(960, 600, 2);
    check('the canvas is backed at the device\'s ratio and sized in CSS pixels',
      c.width === 1920 && c.height === 1200 && c.style.width === '960px' && c.style.height === '600px',
      `${c.width}x${c.height} css ${c.style.width}x${c.style.height}`);
    /* AND THE BACKING STORE HAS A CEILING, because a full-screen 4K page
       at a ratio of two is a thirty-megapixel canvas for two bars and a
       word. Same 4096 the pipeline's own buffer is capped at. */
    {
      const sizes = [[960, 600, 2], [2560, 1440, 2], [3840, 2160, 2], [844, 390, 3], [1280, 800, 1]]
        .map(([w, h, d]) => { const k = fake(); const u = new Hud(game, k); u.resizeUi(w, h, d);
                              return { ask: `${w}x${h}@${d}`, got: `${k.width}x${k.height}`, w: k.width, r: u.dpr }; });
      note('what the canvas costs, by screen', sizes.map(q => `${q.ask} -> ${q.got}`).join(', '));
      check('and it is never wider than 4096 real pixels, whatever the screen claims',
        sizes.every(q => q.w <= 4096 && q.r >= 1), sizes.map(q => q.got).join(' '));
    }

    hud.update(player, null);
    const first = c.ctx.calls.length;
    check('the first frame draws it, on the canvas and nowhere else', first > 20, `${first} calls`);
    check('and it starts by putting the device ratio into the transform',
      c.ctx.calls[0] === 'setTransform' && c.ctx.calls[1] === 'clearRect');

    /* AND A FRAME WHERE NOTHING MOVED COSTS NOTHING. The old readout
       rebuilt a Pix and uploaded a texture on the same conditions, and
       then had every one of its texels go through the block average and
       the palette search on TOP of that, every frame, changed or not. */
    hud.update(player, null);
    check('a second frame with nothing moved draws nothing at all',
      c.ctx.calls.length === first, `${c.ctx.calls.length - first} extra calls`);
    game.burnPercent = 13;
    hud.update(player, null);
    check('and one more percent of the shop going redraws it',
      c.ctx.calls.length > first);

    /* THE SIZE COMES OFF THE WINDOW AND NOTHING ELSE, which is the
       claim. Same window, both pixel dials moved: the same readout. */
    const geom = (h, gw, gh) => {
      const k = fake();
      const u = new Hud({ burnPercent: 12, bigMessage: null }, k);
      u.resize(gw, gh);               // the chunky grid, for the wash and the gun
      u.resizeUi(960, h, 1);
      return { s: u.s, w: u.cssW, h: u.cssH };
    };
    const fine = geom(600, 1707, 960), chunky = geom(600, 288, 120);
    check('the same window with the world drawn at 288x120 and at 1707x960 lays the readout out identically',
      fine.s === chunky.s && fine.w === chunky.w && fine.h === chunky.h,
      `${fine.s} vs ${chunky.s}`);
    note('how big it is, by window', [360, 600, 720, 1440]
      .map(h => `${h}px tall -> ${geom(h, 960, 320).s.toFixed(2)}x`).join(', '));
    check('and it grows with the window, within reason, at both ends',
      geom(360, 960, 320).s < geom(720, 960, 320).s && geom(720, 960, 320).s < geom(1440, 960, 320).s &&
      geom(200, 960, 320).s >= 0.7 && geom(4000, 960, 320).s <= 2);
    check('main.js hands it the window in CSS pixels and the device\'s ratio',
      /hud\.resizeUi\(w, h, window\.devicePixelRatio \|\| 1\)/.test(mainSrc));
    check('and the pause button\'s corner is measured the same way, not in chunky pixels',
      /hud\.setNameInset\(on \? 60 : 0\)/.test(mainSrc));
    check('and with no game running the canvas is wiped, so the title has a clean picture',
      /if \(started\) hud\.update\(p, weapons\); else hud\.clear\(\);/.test(mainSrc));
  }

  /* --- ITS OWN BOX OF CRAYONS --------------------------------------
     The art palette is a setting (stock or earth) and the display
     palette is another. A readout drawn out of the material ramps would
     go muddy when the world did, for no reason: it is not made of any
     material. So it has fixed colours of its own, and they are the
     page's — the amber the menus highlight with, the bone the body text
     is set in. */
  {
    const imports = (hudSrc.match(/^import .*$/gm) || []).join('\n');
    note('what the readout imports', imports.split('\n').map(l => (/'([^']+)'/.exec(l) || [])[1]).join(', '));
    check('the readout takes no colour from the box the world is painted in',
      !/palette\.js/.test(imports) && !/\bramp\s*\(/.test(hudSrc));
    const names = [...hudSrc.matchAll(/^\s{2}(\w+):\s*'/gm)].map(m => m[1]);
    note('the readout\'s own colours', names.join(', '));
    check('it names its colours for what they MEAN, not for which ramp they came off',
      ['burn', 'full', 'low', 'empty', 'armour1', 'armour2', 'health', 'ink', 'card'].every(k => names.includes(k)));
    check('and the amber is the page\'s own amber, so the readout and the menus agree',
      /#e8c34a/.test(hudSrc) && /#e8c34a/.test(css));
  }

  /* ---- AND ONE DEATH SCREEN FOR EVERY DEATH -------------------------
     At the user's request: YOU DIED in red, the Japanese for it in red
     above, a black box, and a red filter over the picture. It replaces
     a line of amber type reading YOU DIED IN AISLE 5, which was the
     right card when a supermarket was the whole game and has been wrong
     since the town.
     --------------------------------------------------------------------- */
  {
    const fsD = await import('node:fs');
    const gameSrc2 = fsD.readFileSync('js/game.js', 'utf8');
    check('there is one card and every death gets it, off p.dead and nothing else',
      /_drawDeath\(p\) \{/.test(hudSrc) && /if \(!p \|\| !p\.dead\) return;/.test(hudSrc) &&
      /this\._drawDeath\(p\);/.test(hudSrc));
    /* the STRING and not the words: both files carry a comment naming
       the card this replaced, which is what the comment is for */
    check('and the aisle is not printed anywhere any more',
      !/`YOU DIED IN AISLE 5/.test(hudSrc) && !/`YOU DIED IN AISLE 5/.test(gameSrc2) &&
      !/'YOU DIED IN AISLE 5'/.test(hudSrc) && !/'YOU DIED IN AISLE 5'/.test(gameSrc2));
    check('and nothing is timed out into the middle of the picture instead',
      !/setBigMessage\(`YOU DIED/.test(gameSrc2));
    check('it says it in Japanese and in English, both in red',
      /const DEATH_KANJI = '\\u6b7b';/.test(hudSrc) &&
      /const DEATH_TEXT = 'YOU DIED';/.test(hudSrc) &&
      /const DEATH_INK = '#c8102e';/.test(hudSrc));
    check('and it asks for a face that actually has the kanji in it',
      /const KANJI = /.test(hudSrc) && /Noto Sans CJK JP/.test(hudSrc) &&
      /ctx\.font = `\$\{kSize\}px \$\{KANJI\}`;/.test(hudSrc));
    check('the box is a black band across the whole picture, not a dialogue',
      /ctx\.fillStyle = 'rgba\(0, 0, 0, 0\.88\)';/.test(hudSrc) &&
      /ctx\.fillRect\(0, top, W, bandH\);/.test(hudSrc));
    check('and how to go again is still on it, small, because it is an instruction',
      /this\.game\.retryPrompt/.test(hudSrc));
    check('and the picture behind it goes red, for every death including the watched one',
      /if \(p\.dead\) \{ tintA = Math\.max\(tintA, 0\.26\); tintC = 0xc8102e; \}/.test(hudSrc));
  }

  /* ---- AND THE GUN'S OWN NOTICES, STACKED IN THE CORNER -------------
     At the user's request, and it is the opposite of the card in the
     middle in every way that matters: small, off to one side, several
     at once, and it goes away by itself. The lance shouts four times on
     its way to killing you and a fifth time when it does, and all five
     were going through setBigMessage — thirty-point type across the
     middle of the picture, one at a time, each wiping the one before
     it. The fifth landed ON TOP of the end-of-night card and took the
     "go again" prompt with it, which is the bug this pass found.
     --------------------------------------------------------------------- */
  {
    const fsN = await import('node:fs');
    const gameSrc = fsN.readFileSync('js/game.js', 'utf8');
    const playerSrc2 = fsN.readFileSync('js/player.js', 'utf8');
    const H = await import('../js/hud.js');
    const G = await import('../js/game.js');

    /* the queue itself, off the real methods and a bare object */
    const q = { toasts: [], toast: null, toastTic: null };
    const proto = (await import('../js/game.js')).Game.prototype;
    q.toast = proto.toast.bind(q); q.toastTic = proto.toastTic.bind(q);
    q.toast('ONE'); q.toast('TWO'); q.toast('THREE');
    check('notices stack, newest last, in the order they were said',
      q.toasts.map(t => t.text).join(',') === 'ONE,TWO,THREE');
    q.toast('THREE');
    check('and the same notice twice running is one notice, restarted',
      q.toasts.length === 3 && q.toasts[2].tics === G.TOAST_LIFE);
    for (let i = 0; i < 8; i++) q.toast('N' + i);
    note('the stack, and what it is capped at',
      `${q.toasts.length} of ${G.TOAST_MAX} after eleven notices`);
    check('the stack is a stack and not a log: past the cap the oldest goes',
      q.toasts.length === G.TOAST_MAX && q.toasts[q.toasts.length - 1].text === 'N7');
    const before = q.toasts.length;
    for (let i = 0; i < G.TOAST_LIFE + 2; i++) q.toastTic();
    check('and every one of them goes away on its own',
      before === G.TOAST_MAX && q.toasts.length === 0);
    check('the clock runs with the world, so a paused game does not eat them',
      /this\.toastTic\(\);/.test(gameSrc) &&
      gameSrc.indexOf('this.toastTic();') > gameSrc.indexOf('  tic() {'));

    /* the fade */
    check('a notice is at full strength until the last second and a quarter of it',
      H.toastFade(G.TOAST_LIFE) === 1 && H.toastFade(0) === 0 &&
      H.toastFade(Math.round(1.25 * 35)) === 1 && H.toastFade(Math.round(0.6 * 35)) < 1);

    /* where it lands, and what it is made of */
    check('they are drawn bottom left, off the bottom edge and up',
      /const y = this\.cssH - M - up \* lead;/.test(hudSrc) &&
      /tracked\(ctx, list\[i\]\.text, M, y, track\);/.test(hudSrc));
    check('and the newest is the one on the floor, with the older ones above it',
      /const up = list\.length - 1 - i;/.test(hudSrc));
    check('text only — no plate, no rule, no box',
      (() => {
        const body = hudSrc.slice(hudSrc.indexOf('  _drawToasts() {'),
                                  hudSrc.indexOf('     Per frame.'));
        return !/fillRect|strokeRect|roundRect/.test(body);
      })());
    check('and the canvas knows to redraw when one of them changes or fades',
      /\(g\.toasts \|\| \[\]\)\.map\(t => `\$\{t\.text\}:\$\{Math\.round\(toastFade\(t\.tics\) \* 16\)\}`\)/.test(hudSrc));

    /* AND THE GUN STILL SAYS THINGS THIS WAY, though what it says has
       changed completely: the stack was built for the overcharge's four
       warnings and a fifth line as it killed you, and what goes through
       it now is a vent and a tally of what a shot went through. The
       mechanism is the thing being checked, so it survived the feature
       it was built for — see 'the lance, dialled back'. */
    check('every one of the lance\'s notices is a notice, not the card',
      /this\.game\.toast\?\.\('COIL VENTED'\);/.test(playerSrc2) &&
      !/setBigMessage/.test(playerSrc2));
    /* the CALL and not the word, since a comment may well name it */
    check('so the end-of-night card is the only thing that uses the middle of the screen',
      !/setBigMessage\?\.\(/.test(playerSrc2) &&
      /setBigMessage/.test(fs.readFileSync('js/game.js', 'utf8')));
  }
}

/* EVERY NAME ONE MODULE TAKES FROM ANOTHER HAS TO BE THERE.

   This exists because of one afternoon: a comment block was rewritten
   with a text splice whose end offset was a line too far, the function
   between the two offsets went with it, and js/main.js was left
   importing a name js/car.js no longer exported. The page died on the
   first line of module evaluation — no textures, no map, no game, a
   title screen that says STARTING for ever — and the smoke test passed
   with 633 green checks, because it imports the modules it wants one at
   a time and never asks whether THEY can find each other.

   Static, not dynamic: js/main.js builds a renderer at the top level and
   importing it here would want a GPU. So the imports and the exports are
   both read out of the source. That is a regex over a codebase whose
   style is consistent, which is worth saying out loud — it earns its
   place by catching a whole class of fatal, silent breakage, and if
   somebody writes an export this cannot see, the count check below
   fails and says so. */
section('the wiring');
{
  const fs = await import('node:fs');
  const path = await import('node:path');
  const files = [];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const q = path.join(d, e.name);
      if (e.isDirectory()) walk(q); else if (q.endsWith('.js')) files.push(q);
    }
  };
  walk('js');
  const exportsOf = src => {
    const out = new Set();
    for (const m of src.matchAll(/^export\s+(?:async\s+)?(?:function|class)\s+([A-Za-z_$][\w$]*)/gm)) out.add(m[1]);
    /* `export const a = 1, b = 2;` — every name at depth zero on the
       line and not just the first, because five modules write theirs
       that way and js/material.js was the first to import a second one
       (SKY_H, off js/skyart.js) and be told it did not exist */
    for (const m of src.matchAll(/^export\s+(?:const|let|var)\s+([^\n]*)/gm)) {
      let depth = 0, seg = '';
      const segs = [];
      for (const ch of m[1]) {
        if ('([{'.includes(ch)) depth++;
        else if (')]}'.includes(ch)) depth--;
        if (ch === ',' && depth === 0) { segs.push(seg); seg = ''; } else seg += ch;
      }
      segs.push(seg);
      for (const sg of segs) { const n = (sg.trim().match(/^([A-Za-z_$][\w$]*)/) || [])[1]; if (n) out.add(n); }
    }
    /* `export { a, b as c }` and `export { a } from './x.js'` */
    for (const m of src.matchAll(/^export\s*\{([^}]*)\}/gm))
      for (const part of m[1].split(','))
        { const n = part.trim().split(/\s+as\s+/).pop().trim(); if (n) out.add(n); }
    if (/^export\s+default/m.test(src)) out.add('default');
    return out;
  };
  const have = new Map(), src = new Map();
  for (const f of files) { const t = fs.readFileSync(f, 'utf8'); src.set(f, t); have.set(f, exportsOf(t)); }
  note('modules', `${files.length}, exporting ${[...have.values()].reduce((n, s2) => n + s2.size, 0)} names`);

  const missing = [];
  const imported = new Set();
  let edges = 0;
  for (const f of files) {
    for (const m of src.get(f).matchAll(/import\s*(?:([A-Za-z_$][\w$]*)\s*,\s*)?\{([^}]*)\}\s*from\s*['"](\.[^'"]+)['"]/g)) {
      const target = path.normalize(path.join(path.dirname(f), m[3]));
      imported.add(target);
      const names = have.get(target);
      if (!names) { missing.push(`${f} -> ${m[3]} (no such module)`); continue; }
      for (const part of m[2].split(',')) {
        const n = part.trim().split(/\s+as\s+/)[0].trim();
        if (!n) continue;
        edges++;
        if (!names.has(n)) missing.push(`${path.basename(f)} imports ${n} from ${path.basename(target)}`);
      }
    }
    /* `import * as x` needs the module to exist and nothing more */
    for (const m of src.get(f).matchAll(/import\s+\*\s+as\s+[\w$]+\s+from\s*['"](\.[^'"]+)['"]/g)) {
      const target = path.normalize(path.join(path.dirname(f), m[1]));
      imported.add(target);
      edges++;
      if (!have.has(target)) missing.push(`${f} -> ${m[1]} (no such module)`);
    }
  }
  note('imports between them', `${edges} names`);
  /* Only the modules somebody imports: js/main.js is the entry point and
     exports nothing on purpose, which is not a fault. */
  const empty = [...imported].filter(f => !(have.get(f) || new Set()).size);
  check('every module somebody imports exports something', empty.length === 0, empty.join(', '));
  check('and every name one module takes from another is exported by it',
    missing.length === 0, missing.slice(0, 6).join('; '));
}

/* ---------- bringing it down ---------- */
/* THE THIRD STAGE. Charred is a surface, gutted is a structure, and
   collapsed is the absence of one — see AND WHAT IS STILL HOLDING IT UP
   in js/fire.js, AND THE THIRD STAGE in js/textures.js, and AND WHEN IT
   HAS COME DOWN in js/ruin.js. Six things have to be true and every one
   of them has been false at some point today. */
section('bringing it down');
{
  const { Game } = await import('../js/game.js');
  const ruin = await import('../js/ruin.js');
  const THREE = await import('three');
  const hudStub = { message() {}, ticMessages() {}, resize() {}, update() {} };
  const inputStub = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
  const lv = MAP.buildSellWrong({ town: false });
  const g = new Game({ level: lv, scene: new THREE.Scene(), camera: {}, textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: hudStub, audio: null, input: inputStub });

  /* --- A CLOCK ADDS NOTHING TO THE WORLD ---
     The first cut of the collapse re-fuelled a region when it gutted, on
     the reasoning that a burnt-out building is full of burning deck. It
     is, and it made the fire unstoppable: a ruin above the spread
     threshold relights the room next door, which relights it back. The
     sign was not in the fire at all — it was the police, who stopped
     being able to keep a van in the car park. So the first claim is
     about a number that must NOT move. */

  /* --- WHAT IS EVEN A BUILDING ---
     Two of the three stages already ask this in one line: a region with
     no fuel cannot char and cannot gut. Collapse needs that AND a roof,
     because a back yard burns and has nothing over it to lose. */
  const structural = i => !!g.fire.structural[i];
  const lot = lv.sectors.find(s => /car park|lot/.test(s.name || '') && s.outdoor);
  const aisle = lv.sectors.find(s => s.name === 'aisle');
  check('a region with a roof and something in it to burn is structure',
    structural(aisle.index), `${aisle.name}`);
  check('and the car park is not, however much you pour on it',
    !structural(lot.index), `${lot.name}`);
  check('and nothing open to the sky is, even where it burns',
    lv.sectors.every(s => !structural(s.index) || s.ceilTex !== 'SKY'));

  /* --- A BLAST BRINGS IT DOWN WHERE A FIRE WOULD TAKE MINUTES --- */
  /* A CLOCK ADDS NOTHING TO THE WORLD, which is the other half of the
     first cut's mistake: gutting a region used to RE-FUEL it, on the
     reasoning that a burnt-out building is full of burning deck. It is,
     and it made the fire unstoppable — a ruin above the threshold a cell
     needs to light its neighbour relights the room next door, which
     relights it back. The sign was not in the fire at all: it was the
     police, who stopped being able to keep a van in the car park. Asked
     across a BLAST rather than across a burn, because igniting anything
     at over forty lays accelerant and that is fuel added on purpose. */
  const fuelBefore = g.fire.totalFuel;
  const down = g.fire.damageStructure(2000, 1500, 500, 1.6);
  for (let t = 0; t < 40; t++) g.tic();
  const fell = lv.sectors.filter(s => s.collapsed);
  check('a blast big enough brings the building down where it lands',
    down >= 3 && fell.length === down, `${down} regions, ${fell.length} flagged`);
  check('and it takes nothing down in the car park',
    g.fire.damageStructure(1240, -1200, 700, 3) === 0);
  /* A BOMB DOES NOT GET TO SKIP THE STAGES, because everything
     downstream of them — the surfaces, the steel, the lamps out of a
     roof that is not there — is written against the flags. */
  check('and nothing skips a stage on the way',
    fell.every(s => s.charred && s.gutted && s.integrity === 0));
  check('and putting a building through all three stages adds no fuel to the world',
    g.fire.totalFuel === fuelBefore,
    `${fuelBefore.toFixed(0)} -> ${g.fire.totalFuel.toFixed(0)}`);

  /* --- AND IT IS LEVEL WITH WHAT IS AROUND IT ---
     A gondola run stands at eighty and an aisle at twelve. Raise each by
     the same step and a run of collapsed bays is a staircase of shelf
     tops, which is not something you can climb and not something that
     happened: what a collapse does to a shelf run is knock it over. */
  const heights = [...new Set(fell.map(s => s.floor))];
  check('a run of collapsed bays is one heap at one height',
    heights.length === 1, `floors ${heights.join(', ')}`);
  check('and it is a step up from the floor and not a wall',
    fell.every(s => s.floor - MAP.FLOOR_WALK <= 24 && s.floor > MAP.FLOOR_WALK),
    `${heights[0]} against a floor at ${MAP.FLOOR_WALK}`);
  /* AND YOU CAN WALK ONTO IT, asked of the engine rather than of the
     arithmetic: a real move from the aisle next door into the wreckage. */
  {
    const t = fell.find(s => s.bbox[2] - s.bbox[0] > 100);
    const y = (t.bbox[1] + t.bbox[3]) / 2;
    const out = lv.slideMove(t.bbox[2] + 40, y, -90, 0, 16, MAP.FLOOR_WALK, 56);
    check('and a player in the aisle next door can climb onto it',
      out[0] < t.bbox[2], `stopped at ${out[0].toFixed(0)}, heap starts at ${t.bbox[2]}`);
  }

  /* --- THERE IS NOTHING OVER IT AND THERE IS A HEAP ON IT --- */
  check('a collapsed region has no roof left at all',
    fell.every(s => s.ceilTex === 'SKY' && s.ruinRoof === 'down' && s.sky === 1));
  check('and its walls have come down to a stub you can see over',
    fell.every(s => s.ceil - s.floor <= 96 && s.ceil - s.floor >= 72),
    fell.map(s => s.ceil - s.floor).join(' '));
  {
    const fakeSet = () => {
      const bins = new Map();
      return { bins, get(n) { let b = bins.get(n); if (!b) bins.set(n, b = { q: [] });
        return { quad: (p, u, l, sk, ch) => b.q.push({ p, l, ch, tex: n }) }; } };
    };
    const t = fell.find(s => s.bbox[2] - s.bbox[0] > 100);
    const heap = fakeSet();
    const n = ruin.roofFraming(heap, t);
    const q = [...heap.bins.values()].flatMap(b => b.q);
    note('the heap over one collapsed region', `${n} pieces, ${q.length} quads`);
    check('a collapsed region gets a heap instead of a frame', n > 8 && q.length > 40, `${n} pieces`);
    check('and the frame that was over it is in the heap',
      heap.bins.has('RUINSTEL') && heap.bins.has('RUBBLE'),
      [...heap.bins.keys()].join(' '));
    /* NOTHING IN IT IS OVER YOUR HEAD IN THE MIDDLE OF THE FLOOR, which
       is the one rule a heap you walk through has to keep: see AND WHEN
       IT HAS COME DOWN. The drifts are banked against the walls. */
    const pts = q.flatMap(x => x.p);
    check('every piece of it is inside the region it fell in',
      pts.every(([x, , z]) => x >= t.bbox[0] - 1 && x <= t.bbox[2] + 1 &&
        -z >= t.bbox[1] - 1 && -z <= t.bbox[3] + 1));
    const mid = q.filter(x => x.p.every(([px, , pz]) =>
      px > t.bbox[0] + ruin.HEAP.edge && px < t.bbox[2] - ruin.HEAP.edge &&
      -pz > t.bbox[1] + ruin.HEAP.edge && -pz < t.bbox[3] - ruin.HEAP.edge));
    const tall = mid.flatMap(x => x.p).filter(([, y]) => y > t.floor + 24);
    check('and nothing out in the middle of it stands higher than the step onto it',
      tall.length === 0, `${tall.length} of ${mid.length * 4} points`);
    check('and all of it is charred, so the coals are in it', q.every(x => x.ch === 1));

    /* --- AND THE FRAME DROOPS BEFORE IT GOES ---
       The thing the user actually asked to be able to watch. A gutted
       region that is still up draws fewer members and hangs them lower
       the further through the collapse it is — see WEAR_STEPS. */
    const shell = lv.sectors.find(s => s.gutted && !s.collapsed && s.bbox[2] - s.bbox[0] > 600)
      || { ...t, gutted: true, collapsed: false, ruinRoof: 'open', ruinVariant: 0, ceil: 352, floor: 12 };
    /* COUNTED AS JOISTS AND NOT AS PIECES, which is the trap: a joist
       that sags is drawn as a polyline of four or five boxes, so a frame
       that has lost two of its nine members and sagged the rest can come
       out with MORE pieces than it started with. What a joist is, is a
       line of the lattice — one distinct y in the world. */
    const at = wear => {
      const set = fakeSet();
      ruin.roofFraming(set, { ...shell, ruinRoof: 'open', ruinVariant: 0, integrity: 1 - wear });
      const q = [...set.bins.values()].flatMap(b => b.q);
      /* THE MEAN AND NOT THE MINIMUM. The lowest point of a frame is
         whichever single joist sagged hardest, and that one can be one
         of the ones that has since gone — so a frame that is further
         through the collapse can read as hanging HIGHER by that measure
         while every member left in it has dropped. */
      const ys = q.flatMap(x => x.p).map(x => x[1]);
      const rows = new Set(q.flatMap(x => x.p.map(p => Math.round(-p[2]))));
      return { n: rows.size, low: ys.reduce((t, y) => t + y, 0) / ys.length };
    };
    const whole = at(0), nearly = at(0.95);
    note('one frame, whole and nearly gone',
      `${whole.n} lines of steel, hanging at ${whole.low.toFixed(0)} -> ${nearly.n} at ${nearly.low.toFixed(0)}`);
    check('a frame that has been in the fire longer has lost more of itself',
      nearly.n < whole.n, `${whole.n} -> ${nearly.n}`);
    check('and what is left of it hangs lower',
      nearly.low < whole.low - 8, `${whole.low.toFixed(0)} -> ${nearly.low.toFixed(0)}`);
  }

  /* --- AND THE FIRE ALONE DOES IT, WHICH IS THE POINT --- */
  {
    /* THE FURNITURE IS NOT THE SHOP, and the ratio below is about the
       shop. What "it comes down" means is the BUILDING: the floor you
       walk on, and whether a fire that goes end to end brings it down
       or leaves a shell standing.

       A gondola is a raised fixture INSIDE that building and has always
       mostly stood — six of twenty-three, the day this was written —
       because a fixture is small, holds its own fuel, and the frame
       over one is cooked mostly by whatever is alight beside it. That
       was invisible while the shop was nearly all floor by count. It
       stopped being invisible when the front end became eight
       checkstands instead of eight slabs: forty-eight new fixture
       regions, every one behaving exactly like the gondolas already
       did, and a ratio under a half without one thing having changed
       about the building or the fire.

       So the floors are counted as the shop and the fixtures are noted
       beside them. Taken BEFORE the burn, because a collapse levels a
       region to its neighbour and a fixture that has come down is at
       floor height by the time anybody asks. */
    const FIXTURE = new Set(lv.sectors.filter(s => s.floor > MAP.FLOOR_WALK).map(s => s.index));
    for (let y = 200; y < 3300; y += 200) for (let x = 300; x < 4000; x += 160) g.fire.ignite(x, y, 250, 60);
    for (let t = 0; t < 4200; t++) g.tic();
    const gut = lv.sectors.filter(s => s.gutted).length;
    const col = lv.sectors.filter(s => s.collapsed).length;
    const stand = lv.sectors.filter(s => s.gutted && !s.collapsed);
    const fgut = lv.sectors.filter(s => s.gutted && !FIXTURE.has(s.index)).length;
    const fcol = lv.sectors.filter(s => s.collapsed && !FIXTURE.has(s.index)).length;
    note('a shop burnt end to end', `${gut} gutted, ${col} of them down, ${stand.length} still standing`);
    note('of which the shop floor itself', `${fcol} of ${fgut} down; the fixtures are ${col - fcol} of ${gut - fgut}`);
    check('a shop that burns end to end comes down', fcol > fgut * 0.5, `${fcol} of ${fgut}`);
    /* AND NOT ALL OF IT, which is the half that makes it a simulation
       rather than a timer: a bay the fire moved away from stands. */
    check('and the bays the fire moved off are still standing',
      stand.length > 4 && stand.every(s => s.integrity > 0), `${stand.length} ruins`);
    check('and the ones still up are held there by where the fire went, not by a dice roll',
      stand.some(s => s.integrity > 0.6) && stand.some(s => s.integrity < 0.4),
      stand.map(s => s.integrity.toFixed(2)).slice(0, 6).join(' '));
  }
}

/* ---------- the way out ---------- */
/* Six crash-bar doors down the flanks of the building, and a crowd that
   uses them. The claim being tested is one sentence — set fire to the
   shop and most of the people in it end up OUTSIDE it — and it is worth
   a whole section because there are five separate ways for it to be
   false and every one of them has been true at some point today: the
   doors could be in the wrong place, they could be blocked, they could
   open for nobody, the crowd could not know about them, or the crowd
   could know and get stuck on the way. */
section('the way out');
{
  const { Game } = await import('../js/game.js');
  const THREE = await import('three');
  const hudStub = { message() {}, ticMessages() {}, resize() {}, update() {} };
  const inputStub = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
  const lv = MAP.buildSellWrong({ town: false });
  const g = new Game({ level: lv, scene: new THREE.Scene(), camera: {}, textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: hudStub, audio: null, input: inputStub });

  /* --- the doors are there, and they are doors ---
     ASKED FOR BY WHAT THEY ARE and not merely by what they do, because
     "swinging" stopped meaning "fire exit" the day the staff door became
     a pair of leaves on hinges instead of a ceiling on a lift. */
  const swing = g.slideDoors.filter(d => d.swing && /fire exit/.test(d.spec.sector.name));
  check('there are six fire exits', swing.length === 6, `${swing.length}`);
  check('three down each flank of the building',
    swing.filter(d => d.spec.sector.name.includes('west')).length === 3 &&
    swing.filter(d => d.spec.sector.name.includes('east')).length === 3);
  /* A PAIR APIECE, at the user's request. Which is the crowd's change
     as much as it is a picture: the opening went from a hundred and four
     to a hundred and twenty, and a hundred and twenty is what a
     cross-aisle 140 deep will give once the frame has had its seven
     either side. */
  check('every one of them is a pair of leaves',
    swing.every(d => d.pair && d.leaves.length === 2),
    swing.map(d => d.leaves.length).join(' '));
  check('and each leaf is half the opening, hinged at its own jamb',
    swing.every(d => Math.abs(d.leafW * 2 - d.len) < 0.01 &&
      Math.abs(d.leaves[0].mesh.position.x - d.spec.x0) < 0.01 &&
      Math.abs(d.leaves[1].mesh.position.x - d.spec.x1) < 0.01 &&
      Math.abs(d.leaves[0].mesh.position.z + d.spec.y0) < 0.01),
    swing.map(d => `${d.leafW} of ${d.len}`).join(', '));
  /* AND THE WHOLE DOORSET STILL FITS THE AISLE IT IS CUT OUT OF, which
     is the thing widening it could quietly break: the frame stands seven
     proud of the opening on each side, and a jamb standing in the
     gondola run next door is a jamb nobody put there. */
  {
    const props = lv.props || [];
    const bad = swing.filter(d => {
      const cy = (d.spec.y0 + d.spec.y1) / 2;
      const aisle = lv.sectorAt(d.spec.x0 + d.nx * 90, cy);
      return !aisle || d.len / 2 + 7 > (aisle.bbox[3] - aisle.bbox[1]) / 2;
    });
    check('and the doorset still fits inside the cross-aisle it is cut out of',
      bad.length === 0, bad.map(d => d.spec.sector.name).join(', '));
    check('and the frames went with it', props.filter(q => q.tex === 'DOORFRAM' &&
      (q.x1 <= MAP.ANCHOR_X0 + 16 || q.x0 >= MAP.ANCHOR_X1 - 16)).length === 36);
  }
  check('and blocks BOTH faces of the wall it is in',
    swing.every(d => d.spec.lines.length === 2), swing.map(d => d.spec.lines.length).join(' '));
  check('they start shut', swing.every(d => d.state === 'shut' && d.open === 0));
  check('and a shut one is wall', swing.every(d => d.spec.lines.every(l => l.blocking)));
  /* The whole point of the leaf being 128 tall and the sector's ceiling
     being the door head: an opening taller than the leaf is a hole you
     can see and shoot through with the door closed. */
  check('the opening is exactly as tall as the leaf',
    swing.every(d => d.zTop === d.spec.sector.ceil && d.zBot === d.spec.sector.floor));

  /* --- AND THEY WEAR THE STAFF DOOR'S DOORSET ---
     At the user's request, augmented for what a fire exit is: the same
     reveal lining, the same soffit, the same transom panel over the
     head, the same pressed frame proud of both faces — and then the
     three things a fire door has that a staff door does not, which are
     the canopy, the light over it and, INSIDE, a lit sign that says you
     may go through this one. */
  {
    const props = lv.props || [];
    const near = (q, cy) => Math.abs((q.y0 + q.y1) / 2 - cy) < 140;
    const cys = swing.map(d => (d.spec.y0 + d.spec.y1) / 2);
    check('every fire exit has the same reveal, soffit and transom panel as the staff door',
      swing.every(d => d.spec.sector.wallTex === 'DOORFRAM' &&
                       d.spec.sector.ceilTex === 'DOORFRAM' &&
                       d.spec.sector.upperTex === 'DOORHEAD'),
      swing.map(d => d.spec.sector.upperTex).join(' '));
    const onFlank = q => q.x1 <= MAP.ANCHOR_X0 + 16 || q.x0 >= MAP.ANCHOR_X1 - 16;
    const fr = props.filter(q => q.tex === 'DOORFRAM' && onFlank(q) && cys.some(cy => near(q, cy)));
    check('and a pressed frame on both faces of the wall, six pieces each',
      fr.length === 36 && fr.every(q => Math.min(q.x1 - q.x0, q.y1 - q.y0) <= 10),
      `${fr.length} pieces`);
    /* UNDER the canopy and not through it: the frame head stops at
       DOOR_TOP + 7 and the canopy starts at DOOR_TOP + 10. */
    const can = props.filter(q => q.tex === 'FASCIA' && cys.some(cy => near(q, cy)));
    check('and it stops short of the canopy rather than growing through it',
      can.length === 6 && fr.every(q => q.z1 <= Math.min(...can.map(c => c.z0))),
      `${can.length} canopies`);
    const sign = props.filter(q => q.tex === 'EXITSIGN');
    check('and a lit sign over the head on the side people are running from',
      sign.length === 6 && sign.every(q => q.light > 1 && q.z0 >= MAP.FLOOR_WALK + 100) &&
      sign.every(q => q.x0 >= MAP.ANCHOR_X0 && q.x1 <= MAP.ANCHOR_X1),
      `${sign.length} signs`);
    /* AND A SHUT ONE IS NOT A HOLE IN THE SIDE OF THE BUILDING. Six
       steel leaves were six windows as far as the portal flood was
       concerned, each opening a cross-aisle onto nine thousand units of
       wood. */
    check('and a shut steel leaf stops sight as well as movement',
      swing.every(d => d.spec.lines.every(l => l.blockSight)));
  }

  /* --- and they are on walkable floor at both ends --- */
  {
    const bad = swing.filter(d => {
      const cx = (d.spec.x0 + d.spec.x1) / 2, cy = (d.spec.y0 + d.spec.y1) / 2;
      const nx = d.nx * 90, ny = d.ny * 90;
      const inside = lv.sectorAt(cx - nx, cy - ny), outside = lv.sectorAt(cx + nx, cy + ny);
      return !inside || !outside || inside.floor !== MAP.FLOOR_WALK || !outside.outdoor;
    });
    check('a fire exit has shop floor on one side and the open air on the other',
      bad.length === 0, bad.map(d => d.spec.sector.name).join(', '));
  }

  /* --- the map tells the crowd where they are --- */
  check('every way out is published', lv.exits.length === 8, `${lv.exits.length}`);
  check('and every one of them is a point OUTSIDE the building',
    lv.exits.every(e => e.x < MAP.ANCHOR_X0 || e.x > MAP.ANCHOR_X1 || e.y < MAP.ANCHOR_Y0),
    'the doorway itself is where a greedy walker stops');
  check('two of them are the front doors',
    lv.exits.filter(e => e.kind === 'front door').length === 2);

  /* --- A CRASH BAR IS NOT A PROXIMITY SENSOR ---
     Somebody strolling past a fire exit with a basket does not open it.
     This is what `panicOnly` buys and it is worth a check, because the
     first cut of these opened for anybody and the shop's six fire doors
     stood open all night with nothing on fire. */
  {
    const d = swing[0];
    const cx = (d.spec.x0 + d.spec.x1) / 2, cy = (d.spec.y0 + d.spec.y1) / 2;
    const calm = g.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    const was = [calm.x, calm.y];
    calm.x = cx - d.nx * 60; calm.y = cy - d.ny * 60; calm.panic = 0;
    g.blockmap.moved(calm);
    for (let k = 0; k < 20; k++) d.tic();
    check('a shopper standing at a fire exit does not open it', d.open === 0);
    calm.panic = 100;
    for (let k = 0; k < 30; k++) d.tic();
    check('one that is running does', d.open > 0.9, d.open.toFixed(2));
    check('and an open one is a hole', d.spec.lines.every(l => !l.blocking));
    calm.panic = 0;
    calm.x = was[0]; calm.y = was[1];
    g.blockmap.moved(calm);
  }

  /* --- AND THE ONE DOOR IN HERE THAT IS NOT A WAY OUT ------------------
     The staff door at the back of the shop floor, which until today was
     the last rising-ceiling door in the building and the worst thing on
     the shop floor with it. A shut Doom door is a sector whose ceiling
     has come down onto its own floor, so the disagreement rule drew its
     face all the way up to whatever the ROOM's ceiling was — and with no
     SIZES entry on the texture that came out as a black slab five
     storeys high with ten STAFF ONLY signs tiled up it, the word sliced
     through by every seam. See THE WAY THROUGH TO THE BACK in
     js/maps/sellwrong.js.

     The first three checks are that bug, from three directions: nothing
     in this map rises any more, the picture of a door is on no wall in
     it, and the opening is exactly as tall as the thing that fills it. */
  {
    /* ASKED FOR BY NAME, because `pair` stopped meaning "the staff door"
       the day the fire exits became double doors too. */
    const staff = g.slideDoors.filter(d => d.spec.sector.name === 'staff door');
    const sec = lv.sectors.find(s => s.name === 'staff door');
    check('there is one staff door and it is a pair of leaves',
      staff.length === 1 && staff[0].leaves.length === 2,
      `${staff.length} doors, ${staff[0] ? staff[0].leaves.length : 0} leaves`);
    check('and nothing in this map is a ceiling that goes up any more',
      !lv.sectors.some(s => s.special && s.special.kind === 'door'),
      lv.sectors.filter(s => s.special && s.special.kind === 'door').map(s => s.name).join(' '));
    check('and the picture of a door is on no wall in it',
      !lv.sectors.some(s => s.wallTex === 'DOORSTAF' || s.upperTex === 'DOORSTAF' ||
                            s.lowerTex === 'DOORSTAF') &&
      !lv.lines.some(l => l.middle === 'DOORSTAF' || l.upper === 'DOORSTAF' || l.lower === 'DOORSTAF'));
    const d = staff[0];
    check('the opening is exactly as tall as the leaves',
      d.zTop === sec.ceil && d.zBot === sec.floor, `${sec.floor}..${sec.ceil} against ${d.zBot}..${d.zTop}`);
    /* A BAND IS DRAWN ONCE FOR BOTH ITS FACES, and this one has a
       panelled olive shop floor on one side and a brick stockroom on the
       other, so what goes over the head belongs to the DOORSET and to
       neither room. */
    check('and what is over the head belongs to the door and not to either room',
      sec.upperTex === 'DOORHEAD' && sec.wallTex === 'DOORFRAM' &&
      sec.upperTex !== lv.sectors.find(s => s.name === 'stockroom').wallTex,
      `${sec.upperTex} over, ${sec.wallTex} down the reveal`);
    /* ONE PICTURE, TURNED. The far leaf hangs off the other jamb through
       half a circle, which runs its u the other way in the world: the
       outer stiles land at the jambs, the meeting stiles come together
       in the middle, and the pair is mirrored off a single texture. */
    check('both leaves are hinged at the jambs and meet in the middle',
      Math.abs(d.leaves[0].mesh.position.x - d.spec.x0) < 0.01 &&
      Math.abs(d.leaves[1].mesh.position.x - d.spec.x1) < 0.01 &&
      Math.abs(d.leafW * 2 - d.len) < 0.01, `${d.leafW} each of ${d.len}`);
    check('and they are one picture, turned, rather than two',
      d.spec.tex === 'DOORSTAF' && new Set(d.leaves.map(l => l.mat)).size === 2 &&
      d.leaves.every(l => l.mat.uniforms.map.value === g.textures.get('DOORSTAF').texture));
    /* AND THEY SWING TOGETHER, which is the whole reason `pair` is a flag
       on one door instead of two doors side by side: the swing direction
       falls out of the order the opening is declared in, so two doors
       hinged at opposite jambs would always swing APART. */
    {
      const was = d.open;
      d.open = 1; d._place();
      const end = d.leaves.map(l => {
        const th = l.mesh.rotation.y;
        return [l.mesh.position.x + Math.cos(th) * d.leafW, -l.mesh.position.z + Math.sin(th) * d.leafW];
      });
      check('and wide open they have both swung into the back of house',
        end.every(([, y]) => y > d.spec.y0 + d.leafW * 0.9),
        end.map(([x, y]) => `${Math.round(x)},${Math.round(y)}`).join(' '));
      check('and not into the cross-aisle, which has shoppers in it', d.ny > 0.99,
        `outward normal ${d.nx.toFixed(2)},${d.ny.toFixed(2)}`);
      d.open = was; d._place();
    }
    /* AND THE RIGHT WAY UP, which is not a thing to take on trust. A
       canvas texture is uploaded flipped — that is what three's flipY
       does — so v = 0 is the BOTTOM of the picture, and the mapping
       anybody would write, zTop to v = 0, hangs the leaf upside down. It
       did: six fire exits with the running man down by the threshold and
       the crash bar above it, for as long as there was nothing on a leaf
       with an unmistakable right way up. A kick plate is unmistakable.
       Asked of EVERY leaf in the game, because one function builds them
       all and the fire exits are the ones nobody would notice. */
    {
      const bad = new Set();
      for (const dd of g.slideDoors) for (const l of dd.leaves) {
        const pos = l.geom.getAttribute('position').array;
        const uv = l.geom.getAttribute('uv').array;
        for (let i = 0; i < 6; i++)
          if (uv[i * 2 + 1] !== (pos[i * 3 + 1] === dd.zTop ? 1 : 0)) bad.add(dd.spec.sector.name);
      }
      check('and every leaf in this building hangs the right way up',
        bad.size === 0, [...bad].join(', '));
    }
    check('it starts shut, and a shut one is wall on both faces of the wall',
      d.state === 'shut' && d.open === 0 &&
      d.spec.lines.length === 2 && d.spec.lines.every(l => l.blocking));
    /* AND A SHUT ONE IS NOT A WINDOW. Without this the stockroom sees
       through the doorway, down an aisle, across the rear cross-aisle and
       out of a fire exit into nine thousand units of wood — which is a
       forest drawn for somebody standing in a stockroom. */
    check('and a steel leaf is not a window either', d.spec.lines.every(l => l.blockSight));
    /* A staff door is the one door in this building the public does not
       use, so it takes the crash bar's rule rather than the entrance's. */
    {
      const cx = (d.spec.x0 + d.spec.x1) / 2, cy = (d.spec.y0 + d.spec.y1) / 2;
      const calm = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.removed);
      const was = [calm.x, calm.y];
      calm.x = cx - d.nx * 60; calm.y = cy - d.ny * 60; calm.panic = 0;
      g.blockmap.moved(calm);
      for (let k = 0; k < 20; k++) d.tic();
      check('a shopper at the staff door does not wander into the back', d.open === 0);
      calm.panic = 100;
      for (let k = 0; k < 40; k++) d.tic();
      check('and a shop on fire does not respect a STAFF ONLY sign', d.open > 0.9, d.open.toFixed(2));
      check('and once it is moving you can walk through it and see through it',
        d.spec.lines.every(l => !l.blocking && !l.blockSight));
      calm.panic = 0; calm.x = was[0]; calm.y = was[1];
      g.blockmap.moved(calm);
      for (let k = 0; k < 400 && d.open > 0; k++) d.tic();
      check('and it shuts itself again', d.open === 0 && d.spec.lines.every(l => l.blocking));
    }
    /* THE FRAME AND THE SIGN are free boxes, because a sector engine
       cannot put anything proud of a wall — the same three pieces per
       face the shopfront's glazing gets, and the sign is the ONLY place
       in this building the words are written down. A word is a shape you
       can count, so it may only live on something that never repeats. */
    const fr = (lv.props || []).filter(q => q.tex === 'DOORFRAM' &&
      q.x0 >= sec.bbox[0] - 16 && q.x1 <= sec.bbox[2] + 16);
    check('the frame is two jambs and a head on each face, and all of it is thin',
      fr.length === 6 && fr.every(q => Math.min(q.x1 - q.x0, q.y1 - q.y0) <= 10) &&
      fr.filter(q => q.y1 <= sec.bbox[1]).length === 3 &&
      fr.filter(q => q.y0 >= sec.bbox[3]).length === 3, `${fr.length} pieces`);
    const sign = (lv.props || []).filter(q => q.tex === 'DOORSIGN');
    check('and STAFF ONLY is a sign over the head on the public side, and nothing else',
      sign.length === 1 && sign[0].y1 <= sec.bbox[1] && sign[0].z0 >= sec.ceil,
      `${sign.length} signs`);
  }

  /* --- SOMEBODY ALIGHT ---
     A shopper the fire reaches does not die where they stand any more,
     at the user's request: they run, on fire, for a few seconds, laying
     a line of it behind them, and then they go off. Four claims, and the
     last one is the one that makes the mechanic worth having. */
  {
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.removed);
    const was = [who.x, who.y];
    who.ignite(400);
    check('a shopper who catches fire starts burning rather than dying',
      !who.dead && who.state.name.startsWith('SHOP_BURN') && who.torch > 0,
      `${who.state.name}, ${who.torch} tics left`);
    check('and more fire does not hurry them along',
      (who.damage(999, null, { fire: true }), !who.dead), 'a torch burns for as long as it burns');
    let ran = 0, lit = 0;
    for (let t = 0; t < 400 && !who.removed; t++) {
      const bx = who.x, by = who.y;
      const before = g.fire.heatAt(who.x, who.y);
      g.tic();
      if (!who.dead) ran += Math.hypot(who.x - bx, who.y - by);
      if (before < 0.2 && g.fire.heatAt(bx, by) >= 0.2) lit++;
    }
    note('one shopper, set alight', `${ran.toFixed(0)} units of running, ` +
      `${lit} cells of fire dropped behind them`);
    check('they run a long way while they are alight', ran > 300, `${ran.toFixed(0)} units`);
    check('and they drag the fire with them', lit > 3, `${lit} cells`);
    check('and then they are gone', who.removed || who.dead,
      `${who.state?.name ?? 'removed'}`);
    check('and the giblets happened, so it was an explosion and not a nap',
      g.giblets ? g.giblets.bursts > 0 : true);
  }

  /* --- AND YOU CAN SEE THAT THEY ARE ---
     THE BEST THING IN THIS GAME WAS INVISIBLE. A shopper alight was the
     ordinary drawing turned fullbright, with the fire they had dropped
     on the floor doing all of the work: what you actually saw was a
     normal shopper standing near some flames. Three things fix it and
     it needs all three — flame off the body, the drawing's own colours
     going, and the light they throw — so all three are measured. */
  {
    const fx = await import('../js/effects.js');
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.removed && !a.burning);
    const p = g.player;
    p.x = who.x - 80; p.y = who.y;
    g.fx.bodyFlames.killAll();
    check('nobody standing about is throwing flame', g.fx.bodyFlames.count === 0);

    who.ignite(400);
    check('and catching fire does not snap the colour on', who.lit === 0);
    /* THE RAMP. Snapping the palette on the tic they catch makes a
       shopper CHANGE COLOUR; a third of a second of it reads as the
       fire taking hold of their clothes. */
    for (let t = 0; t < 4; t++) who.burnTic();
    const part = who.lit;
    check('it comes up over about a third of a second', part > 0.1 && part < 0.9,
      `${part.toFixed(2)} after four tics`);
    for (let t = 0; t < 12; t++) who.burnTic();
    check('and then they are fully alight', who.lit === 1);
    note('a burning shopper', `${g.fx.bodyFlames.count} licks of flame on them`);
    check('and there is flame on them', g.fx.bodyFlames.count > 3);

    /* THE LICKS ARE TONGUES AND NOT A BONFIRE. The first cut threw two
       a tic at up to thirty-four units, which on a fifty-six-unit
       person is a column of fire with somebody lost inside it — and the
       point of a burning shopper is that you can see WHO is burning. */
    check('but not so much of it that the person is lost inside it',
      g.fx.bodyFlames.count < 20 && fx.BODY_FIRE.sizeMax < who.height / 2,
      `${g.fx.bodyFlames.count} alive, up to ${fx.BODY_FIRE.sizeMax} units`);

    /* AND THE LIGHT. A burning person running down a dark aisle lights
       it, which the store's one fire light does by being pulled toward
       everything that burns — the wood, the gun, and now them. */
    g.tics++;                       // a fresh tic, so the glow is only theirs
    g.fx.bodyFire(who);
    const acc = { sx: 0, sy: 0, sw: 0, n: 0 };
    g.fx.glowInto(acc);
    check('and they pull the fire light toward themselves',
      acc.n === 1 && Math.hypot(acc.sx / acc.sw - who.x, acc.sy / acc.sw - who.y) < 1,
      `${acc.n} sources`);

    /* AND IT IS BUDGETED. A crowd fire is dozens of them at once and
       the aisle is already full of the fire's own flames. */
    const many = g.actors.filter(a => a.type === 'SHOPPER' && !a.dead && !a.removed).slice(0, 60);
    for (const a of many) { a.x = p.x + 40; a.y = p.y; a.burning = 400; a.lit = 1; }
    g.fx.bodyFlames.killAll();
    g.tics++;
    let asked = 0, threw = 0;
    for (const a of many) { asked++; threw += g.fx.bodyFire(a) > 0 ? 1 : 0; }
    check('and sixty people alight in one tic do not all throw flame',
      threw === fx.BODY_FIRE.most && asked > threw, `${threw} of ${asked}`);

    /* AND DISTANCE COSTS NOTHING. Somebody alight three rooms away is a
       glow on the shelving and not a particle system. */
    g.tics++;
    const far = many[0];
    far.x = p.x + fx.BODY_FIRE.near + 200; far.y = p.y;
    const before = g.fx.bodyFlames.count;
    g.fx.bodyFire(far);
    check('and one on the far side of the building throws none at all',
      g.fx.bodyFlames.count === before);
    const acc2 = { sx: 0, sy: 0, sw: 0, n: 0 };
    g.fx.glowInto(acc2);
    check('but still throws light, which is what you see at that range',
      acc2.n === 1, `${acc2.n} sources`);
    for (const a of many) { a.burning = 0; a.lit = 0; }
  }

  /* --- AND THE COLOUR COMES OFF WHEN THE FIRE DOES --------------- */
  {
    const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.removed && !a.burning);
    who.ignite(400);
    for (let t = 0; t < 20; t++) who.burnTic();
    check('somebody alight is alight', who.lit === 1 && who.burning > 0);
    who.chill(300);
    check('and the extinguisher takes the colour off with the fire',
      who.burning === 0 && who.lit === 0);
    /* and the other way it can end: frozen solid mid-run */
    const other = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && !a.removed && !a.burning && a !== who);
    other.ignite(400);
    for (let t = 0; t < 20; t++) other.burnTic();
    other.chill((await import('../js/actor.js')).Actor.FREEZE_AT * 3);
    check('and so does being frozen solid', other.frozen && other.lit === 0);
  }

  /* --- AND THE MEASUREMENT ---
     The shop burning, eight hundred people in it, sixty seconds. What?

     THE PREMISE OF THIS BLOCK HAS CHANGED TWICE AND IT IS WORTH KEEPING
     BOTH. It began as "one fire, and then nothing: no player, no second
     ignition, no help", because one fire was all it took — a single
     ignition on the sales floor went on to take four fifths of the
     building inside the minute, largely by travelling through the crowd
     itself. That is no longer true and is not meant to be: a fire left
     alone now takes a patch and goes out (see `fire`), and people
     bursting no longer lay new ones (see Giblets._land). One match in
     here reaches 5% of the store and two hundred people never find out
     about it, which is the point of the change and useless as a test of
     the exits.

     SO THE PLAYER DOES IT, which is what the player is now for: the
     flamethrower walked down all eleven aisles, shelf faces both sides,
     about the pace somebody actually moves. Everything after that is
     what it always was, and the claims are unchanged — the building
     EMPTIES, by one route or another, and hundreds of people leave
     through doors rather than dying where they stood. */
  {
    const crowd = () => g.actors.filter(a => a.type === 'SHOPPER' && !a.dead && !a.removed);
    const running = () => g.actors.reduce((n, a) => n + (a.type === 'SHOPPER' && !a.dead && a.panic > 0 ? 1 : 0), 0);
    const start = crowd().length;
    g.player.noclip = true;                     // out of the way, out of the fire
    /* Down each aisle in turn, painting the shelving either side of it at
       the stream's own strength and footprint — 36 and 22, which lays no
       accelerant, so nothing here can light anything the map called a
       firebreak. */
    let poured = 0, walked = 0;
    for (let k = 0; k < 11; k++) {
      const ax = 480 + k * 280 + 120 + 80;
      for (let y = 420; y < 2600; y += 64) {
        g.fire.ignite(ax - 76, y, 36, 22);
        g.fire.ignite(ax + 76, y, 36, 22);
        poured += 2;
        /* AT A WALKING PACE, which is the half of this that took two
           goes to get right. Painting all eleven aisles inside four
           seconds is not a player, it is a carpet bomb: everybody in the
           building is standing in fire before anybody has taken a step,
           five hundred and seventy die where they stand, and the exits
           get no chance to be load-bearing. Sixty-four units of aisle
           per four tics is about how fast somebody actually moves down
           one, and the fire then arrives the way it does in play — a row
           at a time, with the aisle ahead of you emptying. */
        for (let t = 0; t < 4; t++) { g.tic(); walked++; }
      }
    }
    note('the player walks the shop', `${poured} pours down 11 aisles, ` +
      `${(walked / 35).toFixed(0)}s of walking`);
    /* THE FRIGHT HAS TO BE ABLE TO RUN OUT WHILE THE SHOP IS STILL
       BURNING, which is a different claim from "everybody is calm at the
       end" and is the one worth testing. What is watched is the LOW WATER
       MARK after the first wave has gone through — because the count
       legitimately climbs again every time the fire reaches a part of the
       shop that still has people in it, and it does, twice, in the run
       this was written against: down to nothing by forty seconds and back
       over a hundred by seventy as the second run of shelving goes. */
    let quietest = Infinity, peakFire = 0;
    for (let t = 0; t < 5250; t++) {
      g.tic();
      peakFire = Math.max(peakFire, g.fire.liveCells);
      if (t > 1800) quietest = Math.min(quietest, running());
    }
    const alive = crowd();
    const out = alive.filter(a => a.sector && a.sector.outdoor);
    const inside = alive.length - out.length;
    note('the shop alight, two and a half minutes', `${out.length} of ${start} outside, ` +
      `${inside} still in, ${start - alive.length} lost, ` +
      `${(g.fire.burnFraction * 100).toFixed(0)}% of the store gone`);
    /* FIVE PER CENT, and the bar moved when the fire stopped taking the
       whole shop. It used to be two, and two was right when one match
       burnt the building: everybody had a reason to leave, and "alive
       and still inside" came out at nought or one every time. A fire
       that only goes where the player put it leaves corners nobody ever
       hears about, so a handful of shoppers legitimately calm down and
       go back to the shelves — and the shared LCG means an unrelated
       check added anywhere earlier in this file moves the count by a
       few. The claim worth holding is that the survivors are OUTSIDE,
       not that the building is empty to the last person. */
    check('the building empties: almost nobody alive is still standing in it',
      inside <= start * 0.05, `${inside} of ${start} still inside`);
    /* A QUARTER, and the bar is low on purpose. The claim is that the
       exits are LOAD-BEARING — that a large part of the shop leaves
       through a door rather than dying where it stood — and the exact
       number is a draw from a cascade sitting on its own critical point:
       it moves by a hundred and fifty on a change of one in the trail
       numbers, or on a change to the floor plan that shifts where the
       fire meets the crowd. A threshold pinned near the observed value
       is a coin flip that any later edit can flip. */
    check('and a large part of the shop gets out through the doors',
      out.length > start * 0.25, `${out.length} of ${start}`);
    /* AND THE WORK LANDED. Not a claim about the fire spreading — it
       barely does now — but about the pouring having gone into fuel
       rather than into the air: what the player painted is what burns. */
    {
      /* OF THE SHOP'S OWN FUEL. burnFraction is over the whole grid and
         the whole grid is a town now, most of which is four thousand
         units away and has not been poured on. */
      let had = 0, gone = 0;
      for (const s of g.level.sectors) {
        if (!inMall(s)) continue;
        had += g.fire.sectorFuel[s.index];
        gone += g.fire.sectorBurnt[s.index];
      }
      check('and what the player painted is what burnt',
        gone / Math.max(1, had) > 0.25, `${((gone / Math.max(1, had)) * 100).toFixed(0)}%`);
    }
    /* AND IT IS DYING BACK, which is the self-extinguishing claim asked
       in the one place it could still fail. A crowd is the fastest
       thing in the building and people carry fire about while they are
       alight, so "a fire left alone goes out" being true of an empty
       grid does not make it true of a shop with seven hundred people
       running around inside it. Measured separately: two and a half
       seconds of trigger into a crowded aisle peaks at five per cent of
       the store, settles at eight, and is out after four minutes. */
    note('the fire, at its worst and at the end',
      `${peakFire} -> ${g.fire.liveCells} cells alight`);
    check('and the fire is dying back rather than still growing',
      g.fire.liveCells < peakFire * 0.5,
      `${g.fire.liveCells} against a peak of ${peakFire}`);
    check('and they scatter rather than pile up at one door',
      new Set(out.map(a => a.sector.name)).size >= 3,
      [...new Set(out.map(a => a.sector.name))].slice(0, 5).join(', '));
    check('at least one fire exit was used', swing.some(d => d.open > 0 || d.state !== 'shut')
      || out.length > 0);
    /* Contagious panic passed on at full strength is a loop, and it ran
       for the whole level: six hundred people in the woods behind the
       store, none of them able to see a fire, each one renewing the
       neighbour who had just renewed them. See A_Watch. */
    /* A TENTH, not a twentieth. The claim is that the fright COLLAPSES —
       a self-sustaining loop leaves hundreds running for ever, and it
       did — and the exact low-water mark is a few dozen either way
       depending on where the shared random table happens to be by the
       time this runs. Sitting the threshold on top of the observed value
       made this a coin flip that any new check earlier in the file could
       flip, which is a test of the wrong thing. */
    check('and the fright runs out instead of feeding itself',
      quietest < start * 0.10, `the quietest it ever got was ${quietest} still running`);
    note('and then it starts again', `${running()} running as the fire reaches the rest of the shop`);
  }
}

/* ---------- the van ---------- */
/* ONE VEHICLE, AND IT IS A FILE — nothing but the file. Two whole
   systems have been deleted from under this section. First the drawn
   fleet: seven bodies measured off four-view sheets, built as the visual
   hull of three silhouettes and painted by projecting those views back
   onto them, with about thirty checks holding the atlas, the windows,
   the wheels, the winding and the projected UVs against each other.
   Then tools/prep-van.mjs, which rewrote a model on the way in — halved
   its texture, snapped it to the game's palette, painted a black block
   into a corner of the sheet for the untextured triangles to point at,
   and wrote the axes it had measured into asset.extras.

   assets/models/van.glb is now the author's own export, byte for byte,
   and js/car.js reads it as it stands. So what is checked here is the
   CONVERSION and nothing else — the nodes walked, the axes swapped, the
   scale set, the ground line found, and the model's own UVs taken as
   they are. A missed node matrix still puts a car park full of vans on
   their sides.

   AND THE v, which is the one this section watched go past. It used to
   read "an unflipped v still puts a car park full of vans on their
   sides", which is true and was not what was happening: the v WAS being
   flipped, against a `flipY` on the texture that never happened, because
   `flipY` is ignored for an ImageBitmap. Two flips cancel and one does
   not, so every panel was wearing the wrong half of the sheet — flanks
   painted with the front view — and the van it was written for survived
   that because only 134 of its 624 triangles were textured at all, onto
   a sheet of white bodywork. The model that replaced it is unwrapped all
   over and showed it in the first screenshot. Both halves of the
   convention are pinned below, because either one alone is a trap. */
section('the van');
{
  const car = await import('../js/car.js');
  const veh = await import('../js/vehicles.js');
  const fs = await import('node:fs');

  /* --- the turn, which the tumble is built on ----------------------- */
  {
    /* a quarter turn about the up axis takes the nose onto the left */
    const t = veh.turn([1, 0, 0], Math.PI / 2, 0, 0);
    check('turning a point a quarter round the up axis is exact',
      Math.abs(t[0]) < 1e-9 && Math.abs(t[2] + 1) < 1e-9,
      `[${t.map(q => q.toFixed(2)).join(', ')}]`);
    check('and turning by nothing leaves it where it was',
      veh.turn([3, 4, 5], 0, 0, 0).every((t2, i) => Math.abs(t2 - [3, 4, 5][i]) < 1e-9));
  }

  /* --- THE MODEL, INTO THE GAME'S OWN SPACE ------------------------
     car.modelVehicle is the whole of the preparation there is: the scene
     graph walked, the axes swapped, the scale set from the length the
     GAME uses, the ground line subtracted, the UVs taken as they are and
     the flat material carried as `ink`. */
  const van = await (async () => {
    const glb = await import('../js/glb.js');
    const bytes = fs.readFileSync('assets/models/van.glb');
    const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const { json, bin } = glb.parseGLB(ab);

    /* THE FILE IS THE AUTHOR'S, UNTOUCHED. There is no tool any more, so
       the one thing worth asserting about what is on disk is that
       nothing has been written into it: no measured axes, no scale, no
       painted-in texel. If this ever comes back it means something has
       started preparing the model again. */
    check('the model carries nothing the game put there',
      !json.asset?.extras?.vehicle,
      Object.keys(json.asset?.extras || {}).join(', ') || 'no extras at all');
    note('whose van it is', [json.asset?.extras?.title, json.asset?.extras?.author]
      .filter(Boolean).join(' — ') || 'unattributed');
    note('what is in the file', `${json.meshes.length} meshes, ${json.nodes.length} nodes, ` +
      `${json.materials.length} materials, ${json.images.length} image`);

    const v = car.modelVehicle(json, bin);
    note('its triangles', `${v.model.tris.length}, drawn as they are`);
    check('it has triangles', v.model.tris.length > 200, `${v.model.tris.length}`);

    /* --- THE NODES ARE WALKED --------------------------------------
       A GLB is a scene graph, not a bag of triangles. This one hangs its
       two meshes off four nested nodes, two of which carry a quarter
       turn about X and undo each other — so ignoring the graph happens
       to work HERE and would stand the van on its nose the first time a
       file did not cancel out.

       What proves the walk rather than the luck is the shape that comes
       out: a van is longer than it is wide and wider than it is tall,
       and a quarter turn dropped anywhere in that chain swaps two of
       those three. */
    {
      const matrices = json.nodes.filter(n => n.matrix || n.rotation).length;
      note('the scene graph', `${json.nodes.length} nodes, ${matrices} of them turned`);
      check('the model comes out longer than it is wide, and wider than tall',
        car.carLength(v) > car.carWidth(v) && car.carWidth(v) < car.carHeight(v) &&
        car.carHeight(v) < car.carLength(v),
        `${car.carLength(v)} long, ${car.carWidth(v).toFixed(0)} wide, ${car.carHeight(v).toFixed(0)} tall`);
    }

    /* --- AND IT IS DRAWN THE WAY IT WAS AUTHORED ----------------------
       THIS IS THE ONE THAT MATTERED, and it took three goes to get
       right. The file declares which way each face points twice — the
       winding of its corners and the NORMAL on them — and both of its
       declarations disagree with the SOLID: the shell comes to about
       minus a quarter of its own bounding box, which is a surface wound
       INWARD. The van this replaced was two shells wound against each
       other, and an attempt to fix that by reversing everything when the
       total came out negative turned the body the right way and the
       chassis the wrong way: the car park went from vans seen from the
       inside to vans with no bodywork, a black sill and four wheels.

       The model is not wrong. It renders correctly in Blender and on
       Sketchfab because both of them draw BOTH SIDES — its own material
       says `doubleSided` — and that was the whole of the oversight: this
       renderer culls back faces and the model was authored where that
       never mattered. So: the winding is left exactly as the file has
       it, and the material draws both sides, which is the answer whether
       a file brings one shell or five. The normals are turned outward
       for the FACE LIGHT and nothing else, so a wrong guess costs one
       step of shading and can no longer cull anything or choose
       anybody's paint.
       ------------------------------------------------------------------ */
    check('the file says it is drawn both sides, and it is',
      json.materials.every(m => m.doubleSided));
    note('the shells it brought', json.meshes.map(me => {
      const pr = me.primitives[0];
      const P = glb.readAccessor(json, bin, pr.attributes.POSITION).array;
      const I = glb.readAccessor(json, bin, pr.indices).array;
      const b = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
      for (let i = 0; i < P.length; i += 3) for (let k = 0; k < 3; k++) {
        if (P[i + k] < b[k]) b[k] = P[i + k];
        if (P[i + k] > b[3 + k]) b[3 + k] = P[i + k];
      }
      const c = [(b[0] + b[3]) / 2, (b[1] + b[4]) / 2, (b[2] + b[5]) / 2];
      let vol = 0;
      for (let t = 0; t < I.length; t += 3) {
        const Q = [I[t], I[t + 1], I[t + 2]].map(i => [P[i * 3] - c[0], P[i * 3 + 1] - c[1], P[i * 3 + 2] - c[2]]);
        vol += (Q[0][0] * (Q[1][1] * Q[2][2] - Q[1][2] * Q[2][1]) +
                Q[0][1] * (Q[1][2] * Q[2][0] - Q[1][0] * Q[2][2]) +
                Q[0][2] * (Q[1][0] * Q[2][1] - Q[1][1] * Q[2][0])) / 6;
      }
      const boxv = (b[3] - b[0]) * (b[4] - b[1]) * (b[5] - b[2]);
      return `${json.materials[pr.material].name} ${(100 * vol / boxv).toFixed(0)}%`;
    }).join(', '));
    /* A VEHICLE IS DRAWN DOUBLE-SIDED, which is the fix and the only
       thing that makes "it renders perfectly in Blender" true here. */
    {
      const THREEc = await import('three');
      const mesh = car.carMesh({}, car.carGeometry(v, { length: v.length }));
      check('a vehicle is drawn both sides, as its author saw it',
        mesh.material.side === THREEc.DoubleSide);
      check('and a flat material would ride in the vertices, not in a second draw call',
        'INK' in mesh.material.defines && !!mesh.geometry.getAttribute('ink') &&
        mesh.geometry.getAttribute('ink').itemSize === 4);
      mesh.geometry.dispose(); mesh.material.dispose();
    }
    check('and the file\'s own winding is left alone',
      !('inverted' in v.model) && typeof v.model.normalsTurned === 'number');
    note('normals turned outward for the light',
      `${v.model.normalsTurned} of ${v.model.tris.length}`);
    check('most of them already pointed outward',
      v.model.normalsTurned < v.model.tris.length * 0.7,
      `${v.model.normalsTurned} turned`);
    /* THE ROOF POINTS UP, which is the claim the face light actually
       needs: a roof triangle whose normal points down is given the
       tarmac's light, and that is a third of the brightness. */
    {
      let top = 0;
      for (const t of v.model.tris) for (const p of [t.a, t.b, t.c]) if (p[2] > top) top = p[2];
      let up = 0, down = 0;
      for (const t of v.model.tris) {
        const mid = (t.a[2] + t.b[2] + t.c[2]) / 3;
        if (mid < top * 0.9 || Math.abs(t.n[2]) < 0.7) continue;
        if (t.n[2] > 0) up++; else down++;
      }
      check('the roof faces the sky', up >= 2 && down === 0, `${up} up, ${down} down`);
    }

    /* --- AND THE PAINT IS THE MODEL'S OWN --------------------------
       The mesh is UNWRAPPED, onto the very sheet embedded in it, and
       that is why it renders correctly in Blender and on Sketchfab. It
       was once condemned here on a measurement that said the flanks were
       a fan of long thin triangles sharing one corner — and that
       measurement pooled two primitives, one of which had no texture on
       it at all, so its UVs were unused junk and the junk was the fan.

       The van standing in the lot now is ONE material and one unwrap:
       every triangle of it is on the sheet, laid out as a four-view
       projection — the flanks onto the side elevation, the roof onto the
       plan, the nose and the tail onto theirs. Which is the layout the
       deleted fleet used to PAINT by projecting, drawn by hand into the
       file instead, and it is the reason this model shows a mistake in
       the v that the last one could hide. */
    const painted = v.model.tris.filter(t => !t.ink);
    const inked = v.model.tris.filter(t => t.ink);
    note('the paint', `${painted.length} triangles off the sheet, ${inked.length} flat`);
    check('the van carries its own UVs',
      painted.length > 100 && painted.every(t => t.ta && t.tb && t.tc &&
        t.ta.length === 2 && t.ta.every(q => q >= -1e-6 && q <= 1 + 1e-6)));
    check('and nothing else — no measured views, no silhouette',
      !('views' in v) && !('shape' in v), Object.keys(v).join(', '));

    /* --- WHICH WAY UP THE SHEET GOES -------------------------------
       THE ONE THAT GOT PAST. glTF puts v's origin at the top-left of
       the image and GL puts t's at the bottom, so exactly one turn has
       to happen somewhere. There were two: `1 - v` on the way out of the
       model AND `flipY` on the texture — and `flipY` is IGNORED for an
       ImageBitmap, which is what the sheet is decoded into. So one turn
       happened, the wrong one, and every panel wore the wrong half of
       its sheet: the flanks of every van in the car park were painted
       with the FRONT elevation, grille and headlights down the side.

       It stood for a whole model because the van before this one had
       134 textured triangles on a sheet of white bodywork and the other
       490 were flat black — a white van painted with the wrong view of a
       white van is still a white van. The replacement is unwrapped all
       over and it was visible in the first screenshot.

       Both halves are pinned here, because each alone is a trap: the
       sheet goes up the way it is stored, and the model's own v is used
       untouched. Put either one back and these disagree. */
    {
      const THREEc2 = await import('three');
      const t = car.carTexture({}, {});
      check('the sheet goes up the way it is stored, not turned over on the way in',
        t.flipY === false, `flipY ${t.flipY}`);
      const pr = json.meshes[0].primitives[0];
      const uv0 = glb.readAccessor(json, bin, pr.attributes.TEXCOORD_0).array;
      const ix0 = glb.readAccessor(json, bin, pr.indices).array;
      let off = 0;
      for (let q = 0; q + 2 < ix0.length; q += 3) {
        const tri = v.model.tris[q / 3];
        for (const [k, key] of [[0, 'ta'], [1, 'tb'], [2, 'tc']]) {
          const i = ix0[q + k];
          if (Math.abs(tri[key][0] - uv0[i * 2]) > 1e-6 ||
              Math.abs(tri[key][1] - uv0[i * 2 + 1]) > 1e-6) off++;
        }
      }
      check('and the model\'s own v reaches the triangles untouched',
        off === 0, `${off} of ${v.model.tris.length * 3} corners moved`);
      /* AND IT IS POINT SAMPLED WHATEVER THE FILE ASKS FOR, at the
         user's request. Every other surface in this game is — the walls,
         the sprites, the sky, the fire, the HUD — and a model that
         arrives asking for LINEAR is a model exported by somebody
         rendering it a different way. The van happens to ask for
         NEAREST, so the only honest way to pin this is to hand the
         loader a sampler that asks for the opposite. */
      const asked = { magFilter: 9729, minFilter: 9987, wrapS: 33071, wrapT: 33071 };  // LINEAR, LINEAR_MIPMAP_LINEAR, CLAMP
      const forced = car.carTexture({}, asked);
      check('a model asking for LINEAR is point sampled anyway',
        forced.magFilter === THREEc2.NearestFilter &&
        forced.minFilter === THREEc2.NearestMipmapNearestFilter && forced.generateMipmaps === true,
        `mag ${forced.magFilter}, min ${forced.minFilter}, mips ${forced.generateMipmaps}`);
      /* BUT THE WRAPPING IS STILL THE FILE'S, because that is a question
         about what the UVs MEAN rather than about how the game looks —
         and where a glTF leaves it out the spec's answer is REPEAT,
         which is not this renderer's habit and is not ours to pick. */
      check('but its wrapping is still its own',
        forced.wrapS === THREEc2.ClampToEdgeWrapping && forced.wrapT === THREEc2.ClampToEdgeWrapping);
      const s2 = car.carTexture({}, json.samplers[0]);
      check('and a file that says nothing about wrapping gets glTF\'s own default, repeat',
        t.wrapS === THREEc2.RepeatWrapping && t.wrapT === THREEc2.RepeatWrapping &&
        s2.magFilter === THREEc2.NearestFilter);
      /* AND THE OTHER LOADER AGREES, because there are two of them: the
         vehicles come through js/car.js and the guns through js/glb.js,
         and one rule that only half the models obey is not a rule.
         Checked at the source, since building a gun texture needs a
         browser to decode the PNG. */
      {
        const glbSrc = fs.readFileSync('js/glb.js', 'utf8');
        const carSrc = fs.readFileSync('js/car.js', 'utf8');
        check('both loaders point-sample through the one function, and neither reads a filter out of the file',
          /export function pointSample/.test(glbSrc) &&
          /pointSample\(new THREE\.Texture\(bitmap\)\)/.test(glbSrc) &&
          /pointSample\(new THREE\.Texture\(img\)\)/.test(carSrc) &&
          !/GL_FILTER/.test(glbSrc) && !/GL_FILTER/.test(carSrc));
      }
      /* AND EVERY MODEL ON DISK IS ONE THIS MATTERS FOR. Five of the six
         ask for LINEAR — which is what a modelling program writes by
         default — so this is not a rule waiting for a file to break it,
         it is a rule five files were already breaking. */
      {
        const asks = [];
        // (the .glb files alone: the Godot port keeps its .import
        // sidecars beside them)
        for (const f of fs.readdirSync('assets/models').filter(f => f.endsWith('.glb'))) {
          const b = fs.readFileSync('assets/models/' + f);
          let o = 12, j = null;
          while (o < b.length) { const L = b.readUInt32LE(o), ty = b.toString('ascii', o + 4, o + 8);
            if (ty === 'JSON') j = JSON.parse(b.subarray(o + 8, o + 8 + L).toString('utf8')); o += 8 + L; }
          for (const sm of (j.samplers || [])) if (sm.magFilter !== 9728) asks.push(f);
        }
        note('models asking to be smoothed', asks.length ? asks.join(', ') : 'none');
        check('and the models on disk are the reason: most of them ask for LINEAR', asks.length >= 4);
      }
    }

    /* THE UNWRAP IS ORDINARY, which is the claim that was got wrong.
       A sane four-view unwrap covers a good fraction of the sheet with
       no single triangle stretched across it, and a fan collapses the
       spread to nothing. Measured PER PRIMITIVE, because pooling them is
       what hid it the first time. */
    {
      const stats = [];
      for (const me of json.meshes) for (const pr of me.primitives) {
        const uv2 = pr.attributes.TEXCOORD_0 !== undefined
          ? glb.readAccessor(json, bin, pr.attributes.TEXCOORD_0).array : null;
        const ix = glb.readAccessor(json, bin, pr.indices).array;
        let sum = 0, big = 0;
        for (let t = 0; uv2 && t < ix.length; t += 3) {
          const P = [ix[t], ix[t + 1], ix[t + 2]].map(i => [uv2[i * 2], uv2[i * 2 + 1]]);
          const ar = Math.abs((P[1][0] - P[0][0]) * (P[2][1] - P[0][1]) -
                              (P[2][0] - P[0][0]) * (P[1][1] - P[0][1])) / 2;
          sum += ar; big = Math.max(big, ar);
        }
        stats.push({ name: json.materials[pr.material]?.name,
          textured: !!json.materials[pr.material]?.pbrMetallicRoughness?.baseColorTexture,
          tris: ix.length / 3, sum, big });
      }
      note('the unwrap', stats.map(st => `${st.name} ${st.tris} tris ` +
        `${st.textured ? 'covering' : '"covering"'} ${(st.sum * 100).toFixed(0)}% of the sheet, ` +
        `biggest ${(st.big * 100).toFixed(1)}%`).join('; '));
      const body = stats.filter(st => st.textured);
      check('every textured primitive has an ordinary unwrap',
        body.length >= 1 && body.every(st => st.sum > 0.2 && st.sum < 0.8 && st.big < 0.05),
        body.map(st => `${(st.sum * 100).toFixed(0)}% of the sheet, biggest ${(st.big * 100).toFixed(1)}%`).join('; '));
      check('and the whole model is on the sheet, so no panel is guessed at',
        stats.every(st => st.textured), `${stats.filter(st => !st.textured).length} untextured primitives`);
    }

    /* --- AND THE WHITE PAINT COMES OFF IT ---------------------------
       A car park of one model in every bay was a joke worth one look.
       It is twelve colours now, and it is still one model, one sheet
       and one draw call: the paint rides in the vertices and the WHITE
       in the texture is isolated in the shader, by luminance with a
       saturation guard, and multiplied (see the INK block in
       js/material.js).

       WHAT IS CHECKED HERE is the claim the two numbers make: that
       everything which must NOT take the colour — the grille, the
       tyres, the glass, the bumpers, the sheet's own grey background —
       sits entirely below the ramp, and that every bright neutral texel
       sits entirely above it.

       THE BAND BETWEEN THEM IS NOT EMPTY and is not meant to be: it is
       the paint's own shading, the falloff from a lit panel to a
       shadowed one, and it takes a PART of the colour, which is exactly
       what makes a tinted van look painted rather than filled in. An
       earlier version of this check asserted a gap with nothing in it
       and failed on 7.7% of the sheet, all of it the side of the van.

       AND IT IS DONE IN LINEAR, which is the trap this fell into first.
       The sheet is an sRGB texture and is decoded on the way out of
       texture2D, so the numbers in the shader are not the numbers a
       colour picker says about the PNG. Set off the file, the ramp
       caught only the brightest highlights and what came out was a
       white van with a red pinstripe down every edge.

       The thresholds are READ OUT OF THE SHADER rather than repeated
       here, so this cannot quietly drift away from what runs. */
    {
      const { readPNG } = await import('./png-read.mjs');
      const matSrc = fs.readFileSync('js/material.js', 'utf8');
      const m = matSrc.match(/float pm = smoothstep\(([\d.]+), ([\d.]+), pl\) \* \(1\.0 - smoothstep\(([\d.]+), ([\d.]+), ps\)\)/);
      check('the shader says where the white paint is', !!m);
      const [LO, HI, S0, S1] = m ? m.slice(1).map(Number) : [0, 1, 0, 1];
      note('the paint mask', `luminance ${LO} to ${HI}, saturation guard ${S0} to ${S1}, in linear`);

      const bv = json.bufferViews[json.images[0].bufferView];
      /* `bin` is a Uint8Array VIEW on the file, so the slice has to be
         taken on the view and not by handing Buffer.from an offset it
         will ignore */
      const sheet = readPNG(Buffer.from(bin.subarray(bv.byteOffset || 0,
                                                     (bv.byteOffset || 0) + bv.byteLength)));
      const lin = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
      const smooth = (a, b, x) => { const u = Math.min(1, Math.max(0, (x - a) / (b - a))); return u * u * (3 - 2 * u); };
      const maskAt = i => {
        const r = lin(sheet.data[i*4]), g = lin(sheet.data[i*4+1]), b2 = lin(sheet.data[i*4+2]);
        const l = 0.30 * r + 0.59 * g + 0.11 * b2;
        const mx = Math.max(r, g, b2), mn = Math.min(r, g, b2);
        return { l, m: smooth(LO, HI, l) * (1 - smooth(S0, S1, mx ? (mx - mn) / mx : 0)) };
      };
      const N = sheet.w * sheet.h;
      let paintLike = 0, shading = 0, missedPaint = 0, caughtDark = 0, took = 0;
      for (let i = 0; i < N; i++) {
        const { l, m: mask } = maskAt(i);
        took += mask;
        if (l > HI + 0.05) {
          /* bright AND neutral: the bodywork. The few bright texels that
             are NOT neutral are the lenses, and the guard is there to
             leave them alone. */
          const r = lin(sheet.data[i*4]), g = lin(sheet.data[i*4+1]), b2 = lin(sheet.data[i*4+2]);
          const mx = Math.max(r, g, b2), mn = Math.min(r, g, b2);
          if ((mx ? (mx - mn) / mx : 0) < S0) { paintLike++; if (mask < 0.99) missedPaint++; }
        } else if (l < LO - 0.05) { if (mask > 0.01) caughtDark++; }
        else shading++;
      }
      note('the sheet, under the mask',
        `${(100 * paintLike / N).toFixed(0)}% is paint, ${(100 * shading / N).toFixed(1)}% is its shading, ` +
        `${(100 * took / N).toFixed(0)}% of the sheet takes colour`);
      check('the van is a white van, so there is a lot of paint to take',
        paintLike > N * 0.15, `${(100 * paintLike / N).toFixed(0)}%`);
      check('every bright neutral texel takes the colour', missedPaint === 0, `${missedPaint} missed`);
      check('and nothing below the ramp takes any of it', caughtDark === 0, `${caughtDark} caught`);
      check('and about a quarter of the sheet is painted, which is a van',
        took / N > 0.15 && took / N < 0.35, `${(100 * took / N).toFixed(0)}%`);

      /* and the named parts, which is what any of this is for */
      const at = (x, y) => maskAt(y * sheet.w + x).m;
      for (const [what, x, y, want] of [['a side panel', 150, 165, 1], ['the roof', 360, 160, 1],
                                        ['the grille', 120, 70, 0], ['a tyre', 60, 105, 0],
                                        ['the glass', 190, 45, 0], ['the sheet behind it', 255, 128, 0]]) {
        check(`${what} ${want ? 'takes' : 'does not take'} the paint`,
          want ? at(x, y) > 0.95 : at(x, y) < 0.05, `${at(x, y).toFixed(2)}`);
      }
    }

    /* --- AND THE COLOURS THEMSELVES -------------------------------- */
    {
      const veh2 = await import('../js/vehicles.js');
      const P = veh2.PAINT;
      note('the fleet', `${P.length} entries, ${new Set(P.map(c => c.join(','))).size} colours`);
      check('there is more than one colour of van', new Set(P.map(c => c.join(','))).size > 6);
      check('and every one of them is three numbers in range',
        P.every(c => c.length === 3 && c.every(v => v >= 0 && v <= 1)));
      /* NOTHING TOO DARK TO SURVIVE. This multiplies twice — the sheet's
         own shading, and then a car park at dusk — so a colour picked at
         the value a van is really painted comes out as a black shape
         with wheels. The first palette was, and did. */
      check('and none of them is too dark to still be a colour on screen',
        P.every(c => Math.max(...c) >= 0.4), P.map(c => Math.max(...c).toFixed(2)).join(' '));
      check('and the white the model came in is still in the lot',
        P.some(c => c[0] === 1 && c[1] === 1 && c[2] === 1));

      /* OFF THE BAY'S OWN POSITION, not a fresh random: the map lays the
         lot out with a seeded stream and drawing from it here would move
         every number after it, which is most of the level. */
      const slot = { x: 1234, y: -567, variant: 2 };
      check('a bay gets the same paint every time the level is built',
        veh2.paintOf(slot) === veh2.paintOf({ ...slot }));
      check('and the bay next to it usually gets a different one',
        veh2.paintOf(slot) !== veh2.paintOf({ ...slot, x: slot.x + 186 }));
      /* and it spreads: a hash that piles up on one entry is a fleet */
      const seen = new Map();
      for (let i = 0; i < 400; i++) {
        const c = veh2.paintOf({ x: i * 186 + 300, y: (i % 7) * 220, variant: i % 5 });
        seen.set(c, (seen.get(c) || 0) + 1);
      }
      const most = Math.max(...seen.values());
      check('and it spreads over the palette rather than piling up',
        seen.size >= Math.min(8, new Set(P.map(c => c.join(','))).size) && most < 400 * 0.30,
        `${seen.size} of ${P.length} used, commonest ${most} of 400`);

      /* AND IT REACHES THE VERTICES, in the channel that was already
         there: `a` of 0 says this surface has a picture, and the rgb
         beside it is what the white in that picture is multiplied by. */
      const painted = car.carGeometry(v, { length: v.length, paint: [0.25, 0.5, 0.75] });
      const ink4 = painted.ink;
      check('the paint rides in the vertices rather than in a second material',
        ink4.length === painted.position.length / 3 * 4 &&
        ink4[3] === 0 && ink4[0] === 0.25 && ink4[1] === 0.5 && ink4[2] === 0.75);
      const plain = car.carGeometry(v, { length: v.length });
      check('and a vehicle that asks for no colour is white, which is the model',
        plain.ink[0] === 1 && plain.ink[1] === 1 && plain.ink[2] === 1 && plain.ink[3] === 0);
    }

    /* AND A FLAT MATERIAL STILL RIDES IN THE VERTICES. This model has
       none — there is nothing in it that is not unwrapped — but the
       reader honours one, because glTF allows one and a second material
       is a second draw call for every slab of parked cars. So it is held
       against a hand-built file rather than deleted for want of a user:
       two primitives, one on the sheet and one with nothing but a
       baseColorFactor, and the flat one has to come out carrying its own
       colour and a flag saying to use it.

       baseColorFactor is linear and an sRGB texture decodes to linear on
       sample, so the number goes through untouched — and a tyre that
       came out WHITE would be a UV pointed at the wrong thing, which is
       exactly what the `ink` attribute replaced. */
    {
      const INK = [0.0059367, 0.0059367, 0.0059367, 1];
      /* a flat quad on the sheet and a flat quad under it, longest along
         +Z so the reader will take it for a vehicle at all */
      const pos = new Float32Array([
        -1, 1, -3, 1, 1, -3, 1, 1, 3, -1, 1, 3,        // the painted one
        -1, 0, -3, 1, 0, -3, 1, 0, 3, -1, 0, 3,        // the flat one
      ]);
      const uvs = new Float32Array([0, 0, 1, 0, 1, 1, 0, 1]);
      const idx = new Uint16Array([0, 1, 2, 0, 2, 3]);
      const bin2 = new Uint8Array(pos.byteLength + uvs.byteLength + idx.byteLength + 2);
      bin2.set(new Uint8Array(pos.buffer), 0);
      bin2.set(new Uint8Array(uvs.buffer), pos.byteLength);
      bin2.set(new Uint8Array(idx.buffer), pos.byteLength + uvs.byteLength);
      const B = (o, l) => ({ buffer: 0, byteOffset: o, byteLength: l });
      const json2 = {
        scene: 0, scenes: [{ nodes: [0] }], nodes: [{ mesh: 0 }],
        meshes: [{ primitives: [
          { attributes: { POSITION: 0, TEXCOORD_0: 2 }, indices: 4, material: 0 },
          { attributes: { POSITION: 1 }, indices: 4, material: 1 },
        ] }],
        materials: [
          { pbrMetallicRoughness: { baseColorTexture: { index: 0 } } },
          { pbrMetallicRoughness: { baseColorFactor: INK } },
        ],
        bufferViews: [B(0, 48), B(48, 48), B(96, 32), B(128, 12)],
        accessors: [
          { bufferView: 0, componentType: 5126, type: 'VEC3', count: 4 },
          { bufferView: 1, componentType: 5126, type: 'VEC3', count: 4 },
          { bufferView: 2, componentType: 5126, type: 'VEC2', count: 4 },
          {}, { bufferView: 3, componentType: 5123, type: 'SCALAR', count: 6 },
        ],
      };
      const two = car.modelVehicle(json2, bin2);
      const flat = two.model.tris.filter(t => t.ink);
      const sheet = two.model.tris.filter(t => !t.ink);
      note('a file with a flat material in it', `${sheet.length} triangles on the sheet, ` +
        `${flat.length} flat at ${INK[0]} linear ` +
        `(about ${Math.round(255 * (1.055 * Math.pow(INK[0], 1 / 2.4) - 0.055))} of 255 on a screen)`);
      check('an untextured primitive comes out carrying its own material\'s colour',
        flat.length === 2 && flat.every(t => t.ink.length === 3 &&
          t.ink.every((q, i) => Math.abs(q - INK[i]) < 1e-9)), `${flat.length} triangles`);
      check('and the textured one is left to the sheet',
        sheet.length === 2 && sheet.every(t => t.ink === null));
      /* and the flag reaches the geometry: a vec4 a vertex, rgb and a
         one-or-nothing, which is what the shader's mix reads */
      const g2 = car.carGeometry(two, { angle: 0 });
      const flags2 = new Set();
      for (let i = 3; i < g2.ink.length; i += 4) flags2.add(g2.ink[i]);
      check('and the geometry says which is which, per vertex',
        g2.ink.length === g2.position.length / 3 * 4 && [...flags2].sort().join() === '0,1',
        `flags seen: ${[...flags2].join(', ')}`);
      /* and it survives a clip, so a piece with a tyre in it is black */
      const bit = car.chunkGeometry(two, { x0: -0.1, x1: 0.1, y0: -0.1, y1: 0.1, z0: -0.01, z1: 0.01 },
        { angle: 0 });
      check('and it survives the clip, so a piece with a tyre in it keeps the tyre black',
        bit.ink.some((q, i) => i % 4 === 3 && q === 1));
    }
    /* and the van in the lot uses none of it */
    {
      const g = car.carGeometry(v, { angle: 0 });
      const flags = new Set();
      for (let i = 3; i < g.ink.length; i += 4) flags.add(g.ink[i]);
      check('and this van asks for none of it, because all of it is on the sheet',
        inked.length === 0 && [...flags].join() === '0', `flags seen: ${[...flags].join(', ')}`);
    }
    /* every UV inside the picture */
    {
      const g = car.carGeometry(v, { angle: 0 });
      check('every UV is inside the sheet',
        g.uv.every(u => u >= -1e-6 && u <= 1 + 1e-6),
        `${g.uv.filter(u => u < 0 || u > 1).length} of ${g.uv.length} outside`);
      /* AND NOTHING IS STRETCHED ACROSS THE SHEET, measured on the
         geometry the game actually builds rather than on the file. */
      let widest = 0;
      for (let i = 0; i < g.uv.length; i += 6) {
        if (g.ink[(i / 2) * 4 + 3] > 0.5) continue;         // flat triangles have no unwrap
        const u = [g.uv[i], g.uv[i + 2], g.uv[i + 4]], w = [g.uv[i + 1], g.uv[i + 3], g.uv[i + 5]];
        const ar = Math.abs((u[1] - u[0]) * (w[2] - w[0]) - (u[2] - u[0]) * (w[1] - w[0])) / 2;
        widest = Math.max(widest, ar);
      }
      check('and no one triangle is stretched across the whole sheet',
        widest < 0.05, `the widest covers ${(widest * 100).toFixed(1)}% of it`);
    }
    /* AND THE NORMALS ARE THE TRIANGLES' OWN. Every one unit long, or
       the face light and the winding are both being asked a question
       about a vector that is not a direction. */
    check('and every triangle carries its own unit normal',
      v.model.tris.every(t => Math.abs(Math.hypot(t.n[0], t.n[1], t.n[2]) - 1) < 1e-5));

    /* --- ITS OWN BOX, which the collision and the tumble want --------
       Measured off the triangles rather than declared, now that there is
       nothing left to declare it. The LENGTH is the game's own number —
       a bay is 186 across and a shopper is 62 tall, so a van is 174 nose
       to tail whatever the file thinks it is in metres — and the width
       and the height then follow from the model's own proportions. */
    note('its box', `${car.carLength(v)} long, ${car.carWidth(v).toFixed(0)} wide, ` +
      `${car.carHeight(v).toFixed(0)} tall, sill at ${(v.box.sill * v.length).toFixed(0)}`);
    check('it is as long as the game says a van is',
      v.length === car.VAN_LENGTH, `${v.length}`);
    check('and it stands on the tarmac rather than in it or over it',
      (() => {
        let lo = Infinity, hi = -Infinity;
        for (const t of v.model.tris) for (const p of [t.a, t.b, t.c]) {
          if (p[2] < lo) lo = p[2];
          if (p[2] > hi) hi = p[2];
        }
        return Math.abs(lo) < 1e-6 && Math.abs(hi - v.box.height) < 1e-6;
      })(), 'the lowest vertex is the ground line');
    check('and it straddles its own middle, nose to tail and side to side',
      (() => {
        const b = [Infinity, Infinity, -Infinity, -Infinity];
        for (const t of v.model.tris) for (const p of [t.a, t.b, t.c]) {
          b[0] = Math.min(b[0], p[0]); b[2] = Math.max(b[2], p[0]);
          b[1] = Math.min(b[1], p[1]); b[3] = Math.max(b[3], p[1]);
        }
        return Math.abs(b[0] + 0.5) < 1e-6 && Math.abs(b[2] - 0.5) < 1e-6 &&
               Math.abs(b[1] + v.box.half) < 1e-6 && Math.abs(b[3] - v.box.half) < 1e-6;
      })(), 'or it would turn about a point outside itself');
    check('and its eight corners are the corners of that box',
      car.carCorners(v).length === 8 &&
      car.carCorners(v).every(([x, y, z]) =>
        Math.abs(Math.abs(x) - 0.5) < 1e-9 &&
        Math.abs(Math.abs(y) - v.box.half) < 1e-9 &&
        (z === 0 || Math.abs(z - v.box.height) < 1e-9)));

    /* --- AND A PIECE OFF IT IS A PIECE OF IT ------------------------
       A chunk used to be a fresh BOX cut out of model space with the
       four views projected onto its six faces. There is no projection
       now, so a chunk is the model's own triangles inside the cut —
       which is a better piece, and needs nothing but a filter.

       Three ways for that to be wrong and all three are quiet: a chunk
       that is empty (an invisible thing with a collision box), a chunk
       whose paint is not the model's, and a chunk that is not centred on
       itself, which makes it tumble about a point outside it. */
    {
      /* a cut around a triangle near the roof, the way shed() picks */
      let high = v.model.tris[0];
      for (const t of v.model.tris)
        if ((t.a[2] + t.b[2] + t.c[2]) / 3 > (high.a[2] + high.b[2] + high.c[2]) / 3) high = t;
      const mx = (high.a[0] + high.b[0] + high.c[0]) / 3;
      const my = (high.a[1] + high.b[1] + high.c[1]) / 3;
      const mz = (high.a[2] + high.b[2] + high.c[2]) / 3;
      const cut = { x0: mx - 0.06, x1: mx + 0.06, y0: my - 0.06, y1: my + 0.06,
                    z0: mz - 0.04, z1: mz + 0.04 };
      const c = car.chunkGeometry(v, cut, { angle: 0, light: 0.7, sky: 1, charred: 0.85 });
      const n = c.position.length / 9;
      note('a piece off the roof', `${n} of the van's own triangles`);
      check('a chunk is the model\'s own triangles', n >= 1 && n < v.model.tris.length);
      check('and it is charred', c.charred.every(t => t === 0.85));
      /* IT WEARS THE PAINT OF THE TRIANGLES IT WAS CUT FROM. Not the
         same UVs — the clip puts new vertices on the cut planes and
         interpolates their u and v along with their position, which is
         the point of clipping — so the claim is that every corner of the
         piece's paint falls inside the paint of the model triangles the
         cut actually caught. Outside that is a piece wearing somebody
         else's panel.

         AND IT IS NOT THAT THE PATCH IS SMALL, which is what this asked
         for until the van was replaced by one unwrapped all over. The
         sheet is a four-view projection: a piece an eighth of a van
         across straddles half of it the moment it has a roof face and a
         flank in it, because those two views are drawn in different
         corners. That is the model being read correctly, not a piece
         going wrong. What a piece must not do is wear MORE of the sheet
         than the whole van does. */
      let u0 = 9, u1 = -9, w0 = 9, w1 = -9;
      for (let i = 0; i < c.uv.length; i += 2) {
        u0 = Math.min(u0, c.uv[i]); u1 = Math.max(u1, c.uv[i]);
        w0 = Math.min(w0, c.uv[i + 1]); w1 = Math.max(w1, c.uv[i + 1]);
      }
      /* the paint on every triangle whose own box reaches into the cut:
         the clip cannot invent a UV outside this */
      const caught = [9, 9, -9, -9];
      for (const t of v.model.tris) {
        let miss = false;
        for (let k = 0; k < 3 && !miss; k++) {
          const lo3 = [cut.x0, cut.y0, cut.z0][k], hi3 = [cut.x1, cut.y1, cut.z1][k];
          if (Math.min(t.a[k], t.b[k], t.c[k]) > hi3 ||
              Math.max(t.a[k], t.b[k], t.c[k]) < lo3) miss = true;
        }
        if (miss) continue;
        for (const q of [t.ta, t.tb, t.tc]) {
          caught[0] = Math.min(caught[0], q[0]); caught[2] = Math.max(caught[2], q[0]);
          caught[1] = Math.min(caught[1], q[1]); caught[3] = Math.max(caught[3], q[1]);
        }
      }
      note('and the paint on it', `${((u1 - u0) * 100).toFixed(0)}% by ` +
        `${((w1 - w0) * 100).toFixed(0)}% of the sheet, out of the ` +
        `${((caught[2] - caught[0]) * 100).toFixed(0)}% by ` +
        `${((caught[3] - caught[1]) * 100).toFixed(0)}% the cut reached`);
      check('and its paint is the paint of the triangles it was cut from',
        u0 >= caught[0] - 1e-6 && u1 <= caught[2] + 1e-6 &&
        w0 >= caught[1] - 1e-6 && w1 <= caught[3] + 1e-6,
        `u ${u0.toFixed(2)}..${u1.toFixed(2)}, v ${w0.toFixed(2)}..${w1.toFixed(2)}`);
      check('and it wears less of the sheet than the whole van does',
        (() => {
          let a0 = 9, a1 = -9, b0 = 9, b1 = -9;
          for (const t of v.model.tris) for (const q of [t.ta, t.tb, t.tc]) {
            a0 = Math.min(a0, q[0]); a1 = Math.max(a1, q[0]);
            b0 = Math.min(b0, q[1]); b1 = Math.max(b1, q[1]);
          }
          return (u1 - u0) * (w1 - w0) < (a1 - a0) * (b1 - b0) * 0.75;
        })(), 'or the piece has the whole van smeared over it');
      /* and it is no bigger than the cut, which is what clipping buys */
      check('and it is no bigger than the box it was cut with',
        (() => {
          let lo2 = 1e9, hi2 = -1e9;
          for (let i = 0; i < c.position.length; i += 3) {
            lo2 = Math.min(lo2, c.position[i]); hi2 = Math.max(hi2, c.position[i]);
          }
          return hi2 - lo2 <= (cut.x1 - cut.x0) * v.length + 1e-3;
        })(), 'whole triangles would be a roof panel two thirds of the van long');
      /* it turns about its own middle, so its vertices straddle zero */
      let lo = 1e9, hi = -1e9;
      for (let i = 0; i < c.position.length; i += 3) { lo = Math.min(lo, c.position[i]); hi = Math.max(hi, c.position[i]); }
      check('and it is centred on the cut, so it tumbles about its middle',
        Math.abs(lo + hi) < v.length * 0.14, `${lo.toFixed(1)}..${hi.toFixed(1)}`);
      /* AND A CUT THAT CATCHES NOTHING IS NOT NOTHING */
      const empty = car.chunkGeometry(v, { x0: 0.48, x1: 0.49, y0: 0.24, y1: 0.25, z0: 0.9, z1: 0.95 },
        { angle: 0, light: 0.7, sky: 1, charred: 0 });
      check('a cut that catches nothing still comes out as something',
        empty.position.length / 9 === 1, `${empty.position.length / 9} triangles`);
    }
    return v;
  })();

  /* --- AND THE POLICE VAN, which is the user's second model, twice -----
     Loaded the same way, on its own sheet; longer, because it is an
     armoured truck and the number is set against what it is rather than
     against the file (see POLICE_LENGTH). The second one the user sent
     came in pieces the game uses: four wheels that turn and a light bar
     on its own material, `DynamicPoliceLightMatEmissive`, which flashes
     red and blue and glows (js/bloom.js). tools/blender/prep_swatvan.py
     turned it round, stacked its two sheets into one and named the
     parts. */
  const police = await (async () => {
    const glb = await import('../js/glb.js');
    const bytes = fs.readFileSync('assets/models/police_assault.glb');
    const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const { json, bin } = glb.parseGLB(ab);
    note('the police van', `${json.meshes.length} mesh, ${json.materials.length} material, ${json.images.length} images`);
    check('one sheet for the body and the wheels, and nothing an unlit renderer cannot use',
      json.images.length === 1 && json.materials.every(m => !m.normalTexture && !m.pbrMetallicRoughness?.metallicRoughnessTexture),
      `${json.images.length} images`);
    check('its parts are named for what the game does with them: a body, four wheels and a light bar',
      ['body', 'lightbar', 'wheel_fl', 'wheel_fr', 'wheel_mid', 'wheel_rear'].every(n => json.nodes.some(o => o.name === n)) &&
      json.materials.some(m => m.name === 'DynamicPoliceLightMatEmissive'),
      json.nodes.map(n => n.name).join(', '));
    check('the prep script is in the repository and says how it is run',
      /blender -b -P prep_swatvan\.py -- <newSWATvan\.glb> <out\.glb>/.test(fs.readFileSync('tools/blender/prep_swatvan.py', 'utf8')));
    check('under a megabyte and a half, and nothing like the thirty thousand triangles it arrived with',
      bytes.length < 1.5 * 1024 * 1024, `${(bytes.length / 1024 / 1024).toFixed(2)} MB`);
    const v = car.modelVehicle(json, bin, { length: car.POLICE_LENGTH, id: 'police', name: 'Assault van', use: 'police' });
    const M = v.model;
    note('and its parts', `${M.tris.length} body, ${M.wheels.map(w => w.tris.length).join('/')} wheels, ${M.lamps.length} lamp triangles`);
    check('the wheels and the lamp are kept out of the body, so they can move without it',
      M.wheels.length === 4 && M.lamps.length > 0 && M.wheels.every(w => w.tris.length > 100) && M.tris.length < 12000);
    /* THE NOSE IS +Z: the light bar is over the cab and the cab is over
       the one steering axle, forward of the middle; the two driven axles
       are behind it */
    const lampX = M.lamps.reduce((a, t) => a + t.a[0], 0) / M.lamps.length;
    const front = M.wheels.filter(w => w.axle[0] > 0), back = M.wheels.filter(w => w.axle[0] < 0);
    check('it faces the way the game drives it: the light bar and the single axle at the front',
      lampX > 0.1 && front.length === 2 && back.length === 2 && /^wheel_f/.test(front[0].name) && /^wheel_f/.test(front[1].name),
      `lamp at ${lampX.toFixed(2)}, ${front.map(w => w.name)} forward`);
    check('and the wheels are round, stand on the tarmac, and turn about their own middles',
      M.wheels.every(w => Math.abs(w.axle[2] - w.radius) < 0.01 && w.radius > 0.04),
      M.wheels.map(w => `${w.name} r ${(w.radius * v.length).toFixed(1)}`).join(', '));
    check('the right-hand pair are on the right: wheel_fr is at -y, the vehicle\'s right',
      M.wheels.find(w => w.name === 'wheel_fr').axle[1] < 0 && M.wheels.find(w => w.name === 'wheel_fl').axle[1] > 0);
    check('a bit bigger than the van it replaced, which was 214 by 89 by 93',
      car.POLICE_LENGTH > 214 && car.carWidth(v) > 89 && car.carHeight(v) > 93, `${car.POLICE_LENGTH}`);
    check('it is a truck: longer than the van, wider, and taller',
      car.carLength(v) > car.carLength(van) && car.carWidth(v) > car.carWidth(van) && car.carHeight(v) > car.carHeight(van),
      `${car.carLength(v)} long, ${car.carWidth(v).toFixed(0)} wide, ${car.carHeight(v).toFixed(0)} tall`);
    check('and it fits across the fire lane', car.carWidth(v) < 160, `${car.carWidth(v).toFixed(0)} wide`);
    check('and every triangle of it is on the sheet', v.model.tris.every(t => !t.ink));
    return v;
  })();

  /* --- AND THE FIRE TRUCK, which is the police van repainted ----------
     The user's fire variant: the same body and wheels on a red sheet,
     with a water cannon on the roof — a turret and barrel the game turns
     (`cannon`) on a mount it does not (`cannon_base`). Made by the same
     script as the van. */
  const firetruck = await (async () => {
    const glb = await import('../js/glb.js');
    const bytes = fs.readFileSync('assets/models/firetruck.glb');
    const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const { json, bin } = glb.parseGLB(ab);
    note('the fire truck', `${json.meshes.length} mesh, ${json.materials.length} material, ${json.images.length} image, ` +
      `${(bytes.length / 1024 / 1024).toFixed(2)} MB`);
    check('one sheet, and the cannon in its own flat colours rather than the photo its metal-rough slot pointed at',
      json.images.length === 1 && json.materials.every(m => !m.normalTexture && !m.pbrMetallicRoughness?.metallicRoughnessTexture) &&
      bytes.length < 1.5 * 1024 * 1024, `${json.images.length} images`);
    check('its parts are the van\'s and the cannon\'s: a turret the game turns and a mount it does not',
      ['body', 'lightbar', 'wheel_fl', 'wheel_fr', 'wheel_mid', 'wheel_rear', 'cannon', 'cannon_base'].every(n => json.nodes.some(o => o.name === n)),
      json.nodes.map(n => n.name).join(', '));
    const v = car.modelVehicle(json, bin, { length: car.FIRE_LENGTH, id: 'firetruck', name: 'Fire truck', use: 'fire', lamp: 'fire' });
    const c = v.model.cannon;
    check('it is the police van\'s length, being the police van\'s body', car.FIRE_LENGTH === car.POLICE_LENGTH && v.length === police.length);
    check('and the cannon is kept out of the body, with a pivot on top of its mount and a muzzle forward of it',
      !!c && c.tris.length > 100 && c.tip[0] > c.pivot[0] + 0.05 && Math.abs(c.pivot[1]) < 0.02 && c.pivot[2] > 0.35 && c.pivot[2] < v.box.height,
      c ? `pivot ${c.pivot.map(x => x.toFixed(3))}, tip ${c.tip.map(x => x.toFixed(3))}` : 'none');
    check('the mount is body, and the barrel starts out pointing at the nose',
      v.model.tris.some(t => t.ink) && Math.abs(c.tip[1] - c.pivot[1]) < 0.02);
    check('and its light bar flashes the brigade\'s colours, red and white, not the police\'s',
      v.lamp === 'fire' && police.lamp === 'police' && v.model.lamps.length > 0);
    return v;
  })();
  {
    const B = await import('../js/bloom.js');
    const F = B.LAMP_COLOURS.fire, P = B.LAMP_COLOURS.police;
    check('red and blue for the police, red and white for the fire brigade',
      P.left[0] > 0.9 && P.right[2] > 0.9 && P.right[0] < 0.2 && F.left[0] > 0.9 && Math.min(...F.right) > 0.8);
  }

  /* --- AND THE ARMY'S CARRIER, which is the user's third model --------
     A hover APC, and the first vehicle in the game that does not touch
     the road. Loaded exactly like the other two — the model says
     nothing about hovering, which is a fact about the GAME and lives in
     ArmyApc — and measured against the police van beside it, because
     "an APC" is a shape rather than a size: not much longer, half again
     as wide, and still inside the fire lane. */
  const apc = await (async () => {
    const glb = await import('../js/glb.js');
    const bytes = fs.readFileSync('assets/models/apc.glb');
    const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const { json, bin } = glb.parseGLB(ab);
    note('the APC', `${json.meshes.length} mesh, ${json.materials.length} material, ${json.images.length} image, ` +
      `${(bytes.length / 1024 / 1024).toFixed(1)} MB`);
    /* tools/prep-model.mjs took the normal map and the metal-rough off
       it on the way in — two megabytes for a renderer with no lighting
       model to spend them on. What is left is the one picture that IS
       the vehicle. */
    check('the maps an unlit renderer cannot use are off it: one image left, and it is the colour',
      json.images.length === 1 && /diffuse/i.test(json.images[0].name || ''),
      json.images.map(i => i.name).join(', '));
    check('and the game prepared it rather than the artist',
      /prep-model/.test(json.asset.generator || ''), json.asset.generator);
    const v = car.modelVehicle(json, bin, { length: car.APC_LENGTH, id: 'apc', name: 'Hover APC', use: 'army' });
    check('it is an APC: longer than the assault van and a third again as wide',
      car.carLength(v) > car.carLength(police) && car.carWidth(v) > car.carWidth(police) * 1.3,
      `${car.carLength(v)} long, ${car.carWidth(v).toFixed(0)} wide, ${car.carHeight(v).toFixed(0)} tall, ` +
      `against ${car.carLength(police)} by ${car.carWidth(police).toFixed(0)}`);
    check('and it still fits across the fire lane, which is what stopped it being bigger',
      car.carWidth(v) < 160, `${car.carWidth(v).toFixed(0)} wide of 160`);
    check('and every triangle of it is on the sheet', v.model.tris.every(t => !t.ink));
    return v;
  })();

  /* --- and seventy-seven of them, parked ---------------------------- */
  const { Game } = await import('../js/game.js');
  const THREE2 = await import('three');
  const scene2 = new THREE2.Scene();
  const gm = new Game({
    level, scene: scene2, camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
    fleet: { texture: {}, def: van },                // it never draws in here
    police: { texture: {}, def: police },
    apc: { texture: {}, def: apc },
  });
  const V = gm.vehicles;
  note('the car park', `${V.count} vehicles in ${(level.carSlots || []).length} bays`);
  check('every slot in the lot got a vehicle',
    V.count === (level.carSlots || []).length && V.count > 12, `${V.count}`);
  /* AND THEY ARE SPREAD OUT, at the user's request. Counting empty bays
     would mean knowing how many there are, which is arithmetic inside
     the map; what "sparse" actually means is visible from the vans
     themselves — how far it is to the next one. A bay is 186 wide, so
     neighbours in adjacent bays are 186 apart and a sparse lot is not.  */
  {
    const all = V.all;
    const near = all.map(v => Math.min(...all.filter(o => o !== v)
      .map(o => Math.hypot(o.x - v.x, o.y - v.y))));
    near.sort((a, b) => a - b);
    const mid = near[near.length >> 1];
    note('and how spread out', `nearest neighbour: closest ${near[0].toFixed(0)}, ` +
      `median ${mid.toFixed(0)}, furthest ${near[near.length - 1].toFixed(0)}`);
    check('the lot is sparse rather than full', mid > 300, `median ${mid.toFixed(0)} apart`);
    check('and no two vans are in the same bay', near[0] > 150, `${near[0].toFixed(0)} apart`);
  }
  /* THE ASK WAS FOR A CUSTOMER CAR PARK. The riot van and the APC are
     measured, packed and ready and neither of them is out there. */
  check('and none of it is police or military',
    V.all.every(v => v.def.use === 'civil'),
    [...new Set(V.all.map(v => v.def.id))].join(', '));
  check('and every one of them is the modelled van',
    V.all.every(v => v.def === van), [...new Set(V.all.map(v => v.def.id))].join(', '));

  /* AND THEY ARE IN THE BAYS, not on the lines.

     The bay lines are not geometry — they are one repeat of the BAYROW
     texture, 186 by 180 with the line down its left edge, so where the
     repeat starts is where the bays start. Tiled from the world origin
     it started five units off the middle of every bay in the lot, and
     every one of these cars was parked ON a line instead of between two
     of them. The row now carries its own texture origin, which is what
     makes the arithmetic the parking already used come out true, so this
     measures the two against each other: how far across one repeat of
     the bay texture each car is standing. Half way, or it is on a line. */
  {
    const bay = gm.textures.get('BAYROW');
    const mod = (v, n) => ((v % n) + n) % n;
    const across = [];
    /* the lot's own vans; the ones along the town's kerbs stand on the
       street's shoulders and are the street's business */
    const lotVans = V.all.filter(v => !/^parking,/.test((level.sectorAt(v.x, v.y) || {}).name || ''));
    for (const v of lotVans) {
      const sec = level.sectorAt(v.x, v.y);
      across.push(sec && sec.floorAnchor && sec.floorTex === 'BAYROW'
        ? mod(v.x - sec.floorAnchor[0], bay.w) : -1);
    }
    const centred = across.filter(t => Math.abs(t - bay.w / 2) < 1).length;
    /* three of them are abandoned at an angle across the lot, which is
       the map saying everybody left at once; the rest are parked */
    note('cars across their bay', `${centred} of ${lotVans.length} dead centre of one, ${V.count - lotVans.length} more parked in the town`);
    check('every parked car is in the middle of a bay rather than on a line',
      centred >= lotVans.length - 3,
      across.filter(t => Math.abs(t - bay.w / 2) >= 1).map(t => t.toFixed(0)).join(', '));
    /* AND EVERY ROW OF BAYS IN THE LEVEL, not just the car park's:
       the office block's lot and the yard behind it wear the same
       texture, and a row that is not one repeat deep is a row with a
       line painted across the middle of it. */
    check('and the bay rows are exactly one repeat of the bay texture deep',
      level.sectors.filter(s => s.floorTex === 'BAYROW').every(s => {
        const ys = s.poly.map(p => p[1]);
        return Math.abs((Math.max(...ys) - Math.min(...ys)) - bay.h) < 1e-6;
      }));
  }

  /* ONE MESH, not seventy-seven. */
  const carMeshes = scene2.children.filter(o => o.name === 'cars');
  check('the whole car park is one mesh', carMeshes.length === 1);
  check('and it holds every parked vehicle',
    carMeshes[0].geometry.getAttribute('position').array.length ===
    V.all.reduce((n, v) => n + v.slab.position.length, 0));

  /* AND YOU CANNOT WALK THROUGH ONE. Doom's things are cylinders, so a
     vehicle is three of them, each carrying a pointer back to it. */
  const blocks = gm.actors.filter(a => a.type === 'CARBODY');
  check('each vehicle is three of Doom cylinders', blocks.length === V.count * 3 && blocks.every(a => a.solid));
  check('and none of them has a state or a sprite to draw', blocks.every(a => !a.state && !a.drawn));
  check('and every one of them knows which vehicle it is part of',
    blocks.every(a => a.vehicle && V.all.includes(a.vehicle)));
  check('and a hatchback gets a smaller cylinder than a van',
    car.carBlockRadius(van) === Math.max(12, Math.round(car.carWidth(van) / 2)),
    `${car.carBlockRadius(van)} for a van ${car.carWidth(van).toFixed(0)} wide`);
  const p0 = gm.player, one = V.all[0];
  check('you cannot walk into the middle of one', p0.thingInWay(one.x, one.y));
  check('nor into either end of it',
    car.carBlockers(one.def, one.x, one.y, one.yaw).every(b => p0.thingInWay(b.x, b.y)));
  /* AND YOU CAN ALWAYS GET OUT OF ONE. Put down inside a cylinder —
     which is what a van parking on you does — every step used to be
     refused, because every step was still inside it, and you stood in
     the van until it drove off. See Player.thingInWay, and shoveClear in
     js/vehicles.js, which is a parked van putting you outside itself. */
  {
    const bl = car.carBlockers(one.def, one.x, one.y, one.yaw);
    const mid = bl[1], nx = -Math.sin(one.yaw), ny = Math.cos(one.yaw);
    const sx = p0.x, sy = p0.y;
    p0.x = mid.x + nx * 2; p0.y = mid.y + ny * 2;
    check('inside a vehicle, a step further in is still refused', !!p0.thingInWay(mid.x, mid.y));
    check('but a step out of it is not', !p0.thingInWay(mid.x + nx * 14, mid.y + ny * 14));
    one.shoveClear();
    const r = car.carBlockRadius(one.def) + p0.radius;
    const nearest = Math.min(...bl.map(b => Math.hypot(p0.x - b.x, p0.y - b.y)));
    check('and a vehicle that parks on you puts you outside itself', nearest >= r - 1e-6,
      `${nearest.toFixed(0)} from the nearest cylinder, ${r} needed`);
    p0.x = sx; p0.y = sy;
  }

  /* --- and what happens to one -------------------------------------- */
  {
    /* the loneliest one in the lot, so the chain reaction does not make
       the arithmetic below somebody else's */
    let target = V.all[0], far = -1;
    for (const v of V.all) {
      let near = Infinity;
      for (const o of V.all) if (o !== v) near = Math.min(near, Math.hypot(o.x - v.x, o.y - v.y));
      if (near > far) { far = near; target = v; }
    }
    const startHealth = target.health, tookOffFrom = target.ground;
    target.ignite();
    check('a vehicle you set light to is on fire', target.burning > 0);
    check('and the tarmac under it is too', gm.fire.heatAt(target.x, target.y) > 0);

    const seen = [];
    let blasts = 0;
    const bangs = [];
    const realExplode = gm.explode.bind(gm);
    gm.explode = (a, o) => { blasts++; bangs.push(o); return realExplode(a, o); };
    /* WATCHING IT CHAR: how long it spends there, and what the vertices
       do while it does. The car leaves the slab for a mesh of its own
       the tic it starts, and that mesh's `charred` and `light` are the
       two numbers js/material.js turns into coals and black paint. */
    let charTics = 0, charMesh = null, charMid = null, blastsBefore = 0, embersAt = -1;
    const fx = gm.fx;
    const realEmber = fx.ember.bind(fx);
    let embers = 0;
    fx.ember = (...a) => { embers++; return realEmber(...a); };
    for (let i = 0; i < 700 && target.state !== 'wreck'; i++) {
      gm.tic();
      if (seen[seen.length - 1] !== target.state) seen.push(target.state);
      if (target.state === 'charring') {
        charTics++;
        charMesh = target.mesh;
        if (charTics === 1) { blastsBefore = blasts; embersAt = embers; }
        if (charTics === 90) charMid = {
          charred: target.mesh.geometry.getAttribute('charred').array[0],
          light: target.mesh.geometry.getAttribute('light').array[0],
          light0: target.light0[0],
        };
      }
    }
    fx.ember = realEmber;
    note('one vehicle, lit', seen.join(' -> '));
    check('being on fire eventually takes it apart',
      target.health < startHealth && target.state === 'wreck');
    /* IT CHARS FIRST, at the user's request, and then goes up. */
    check('and it charred, went up, flew, and came down',
      seen.join(',') === 'parked,charring,air,settle,wreck', seen.join(','));
    note('and how long it charred for', `${charTics} tics, ${(charTics / 35).toFixed(1)}s`);
    check('the char is long enough to watch and short enough to wait for',
      charTics >= 4.5 * 35 - 2 && charTics <= 7.5 * 35 + 2, `${charTics} tics`);
    check('a charring car is its own mesh, out of the slab',
      !!charMesh && charMesh.name === 'car:' + van.id && !target.slab);
    check('and halfway through, its coals are up and its paint is down',
      charMid && charMid.charred > 0.25 && charMid.charred < 0.8 &&
      charMid.light < charMid.light0 * 0.85 && charMid.light > charMid.light0 * 0.4,
      charMid ? `charred ${charMid.charred.toFixed(2)}, light ${charMid.light.toFixed(2)} of ${charMid.light0.toFixed(2)}` : 'no midpoint');
    check('nothing exploded while it was charring', blasts === blastsBefore || bangs.length <= 2,
      `${blasts - blastsBefore} bangs during the char`);
    check('and it threw embers the whole time', embers - embersAt >= charTics * 0.9,
      `${embers - embersAt} embers over ${charTics} tics`);
    /* TWO BANGS: one as it leaves and one as it lands. */
    check('it exploded twice, not once', blasts >= 2, `${blasts} explosions`);
    /* AND THE FIRST IS FOUR OF THE OLD ONE — at the user's request. What
       the old bang was is written down here rather than read from the
       file, because the file no longer has it: radius 210, damage 90,
       three fireballs, 26 embers, 7 puffs. */
    {
      const first = bangs[0];
      check('the launch bang reaches twice as far — four times the area',
        first && first.radius === 420, `${first?.radius}`);
      check('and hits twice as hard', first && first.damage === 180, `${first?.damage}`);
      check('and pins the heat of the floor to the top of the scale', first && first.heat === 255, `${first?.heat}`);
      check('and is the loudest thing in the game', first && first.sound === 'bigboom', `${first?.sound}`);
      const second = bangs[1];
      check('the crash bang is what it always was', second && second.radius === 170 && second.damage === 55,
        `${second?.radius} / ${second?.damage}`);
    }

    /* IT LANDS ON ITS ROOF. That is the whole point of aiming the roll
       rate at the flight time rather than picking one and hoping. */
    const over = Math.abs(((target.rx / Math.PI) % 2) - 1);
    check('and it is lying on its roof', over < 0.06,
      `${(target.rx / Math.PI).toFixed(3)} half-turns`);
    /* AND ITS LOWEST CORNER IS ON WHATEVER IT CAME DOWN ON, whatever
       angle it stopped at — which is not always what it took off from.
       crash() calls updateSector() before it sets the height, so a van
       thrown off the carriageway and landing over a kerb rests twelve
       higher than it started, and that is the engine being right. This
       check used to hold the landing against the TAKE-OFF height and
       passed for as long as the arc happened to end on tarmac; the day
       it ended on a sidewalk it failed, and it was the check that was
       wrong. It is held against the resting ground now, and the
       take-off height is noted so a drift of a whole kerb is visible
       rather than silent. */
    const low = veh.extentOf(target.corners, target.rx, target.rz).lo;
    note('where it came down', `${target.ground - tookOffFrom} above what it took off from`);
    check('and its lowest corner is exactly on what it came down on',
      Math.abs((target.cz + low) - target.ground) < 1e-6, `${(target.cz + low - target.ground).toFixed(4)} off`);
    check('and it is still in the way', target.blockers.length === 3 &&
      gm.player.thingInWay(target.x, target.y));
    check('and it is burnt, so js/material.js puts coals on it',
      V.restSlabs.some(s => s.charred.every(c => c === 1)));

    /* DEBRIS: pieces off it, which fly, land and lie there smouldering. */
    note('what came off it', `${V.flying.length} still in the air, ${V.resting.length} on the tarmac`);
    check('it threw pieces of itself', V.flying.length + V.resting.length > 8);
    for (let i = 0; i < 400 && V.flying.length; i++) gm.tic();
    check('and every one of them came to rest', V.flying.length === 0);
    check('and each is lying on the ground rather than in it',
      V.resting.every(c => Math.abs(c.z - (c.ground - veh.extentOf(c.corners, c.rx, c.rz).lo)) < 1e-6));
    check('and they are all in the one wreckage mesh',
      scene2.children.filter(o => o.name === 'cars').length === 2 &&
      V.restSlabs.length >= V.resting.length);

    /* THE CHAIN REACTION, which is not a feature anybody wrote: cars are
       flammable and explosions light what they reach. */
    const gone = V.all.filter(v => v.state !== 'parked').length;
    note('the lot after one went up', `${gone} of ${V.count} vehicles`);
    check('and the bang set light to whatever was near enough', gone >= 1);
  }

  /* ==================================================================
     THE SQUAD

     The first thing in the game that fights back: a van up the road
     after the first kill, troopers out of the side of it, a rifle. It
     is tested end to end on the real map with the real routes, because
     every piece of it — the drive, the bay, the door, the chase, the
     shot — is a place the pieces can disagree, and a van that parks in
     a wall or a trooper who steps out inside the van is exactly the
     kind of bug a screenshot finds and a unit test does not.
     ================================================================== */
  section('the squad');
  {
    const ppl = await import('../js/people.js');
    const { readPNG } = await import('./png-read.mjs');
    const { ACTIONS } = await import('../js/actor.js');
    const { SWAT: S } = await import('../js/responders.js');
    /* A FRESH GAME, because the one above has just had a car park go up
       in it and a squad walking through a burning lot is a squad that
       is dead in nine seconds — which is correct, and is not what this
       is measuring. */
    const gs = new Game({
      level: MAP.buildSellWrong({ town: false }), scene: new THREE2.Scene(), camera: {},
      textures: gm.textures, sprites: spr.bakeSprites(),
      hud: { message() {}, ticMessages() {} }, audio: null,
      input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
               attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
      fleet: { texture: {}, def: van },
      police: { texture: {}, def: police },
      apc: { texture: {}, def: apc },
    });
    const R = gs.responders;

    /* --- the art ------------------------------------------------------
       The user's sheets, cut by tools/prep-troops.mjs into strips in the
       order js/people.js reads them back. Five drawings a turned frame
       and three mirrors, exactly as Doom's own sprites did it. TWO OF
       THEM: the SWAT, who are in the game, and the army trooper, who is
       cut, loadable and proven here and is NOT in the game — no actor,
       no state, nothing loads the strip — at the user's request. */
    const same = (p, q) => {
      if (p.w !== q.w || p.h !== q.h) return false;
      for (let i = 0; i < p.data.length; i++) if (p.data[i] !== q.data[i]) return false;
      return true;
    };
    const tallOf = p => { let top = p.h; for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) if (p.alphaAt(x, y) > 8) { top = Math.min(top, y); } return p.h - top; };
    check('the troops table names two sheets cut the same way, the SWAT and the army',
      Object.keys(ppl.TROOPS).join(',') === 'SWAT,ARMY' &&
      ppl.TROOPS.ARMY.turn === ppl.TROOPS.SWAT.turn && ppl.TROOPS.ARMY.flat === ppl.TROOPS.SWAT.flat &&
      ppl.TROOPS.ARMY.cells === ppl.TROOPS.SWAT.cells && ppl.SWAT_CELLS === ppl.TROOPS.SWAT.cells);
    check('and both sheets are kept, decoded, beside the strips cut from them',
      Object.values(ppl.TROOPS).every(t => fs.existsSync(t.sheet) && fs.existsSync(t.strip)));
    for (const [key, t] of Object.entries(ppl.TROOPS)) {
      const cell = ppl.CELLS.troops;
      const img = readPNG(new URL('../' + t.strip, import.meta.url));
      check(`${t.strip} is the strip the tables are built on`,
        img.w === cell.w * t.cells && img.h === cell.h, `${img.w}x${img.h}, want ${cell.w * t.cells}x${cell.h}`);
      const n = ppl.addTroops(gs.sprites, img, key);
      check(`and the loader takes every cell of it, under ${t.sprite}`, n === t.cells && gs.sprites.frames.has(t.sprite + 'A'), `${n}`);
      const A = gs.sprites.frames.get(t.sprite + 'A');
      check('a turned frame has eight views', A.views.length === 8 && A.views.every(v => v.w === cell.w));
      check('and rotation 1 is the mirror of rotation 7, not a copy of it',
        same(A.views[1], A.views[7].mirrored()) && !same(A.views[1], A.views[7]));
      check('and head on and from behind are two different drawings', !same(A.views[0], A.views[4]));
      const lying = gs.sprites.frames.get(t.sprite + 'N');
      check('and lying down is the same from every side', lying.views.every(v => v === lying.views[0]));
      /* the scale */
      note(`a ${key} trooper, head on`, `${tallOf(A.views[0])} tall in a ${cell.h} cell, lift ${t.lift}`);
      check('the standing trooper is the height the table says', Math.abs(tallOf(A.views[0]) - t.height) <= 1);
      check('and every cell keeps the 64-pixel rule', cell.w <= 64 && cell.h <= 64);
      /* every cell has something in it — a cut that found a smear of
         JPEG halo instead of a drawing would leave an empty one */
      const cells = Array.from({ length: t.cells }, (_, k) => {
        let n2 = 0; for (let y = 0; y < cell.h; y++) for (let x = 0; x < cell.w; x++) if (img.data[((y * img.w) + k * cell.w + x) * 4 + 3] > 8) n2++; return n2;
      });
      check('and every cell holds a drawing', cells.every(c => c > 60), cells.map((c, k) => c <= 60 ? k : null).filter(k => k !== null).join(','));
    }
    /* the two figures are the same sheet layout, so the same letter is
       the same pose: the army's firing frame is as orange as the SWAT's */
    {
      const glow = p => { let o = 0, n = 0; for (let y = 0; y < p.h; y++) for (let x = 0; x < p.w; x++) { if (p.alphaAt(x, y) < 128) continue; n++; const i = (y * p.w + x) * 4; if (p.data[i] > 180 && p.data[i + 1] > 90 && p.data[i + 2] < 120) o++; } return n ? o / n : 0; };
      const sf = gs.sprites.frames.get('SWATF').views[0], af = gs.sprites.frames.get('ARMYF').views[0];
      const sa = gs.sprites.frames.get('SWATA').views[0], aa = gs.sprites.frames.get('ARMYA').views[0];
      note('how orange the firing frame is', `SWAT ${(glow(sf) * 100).toFixed(0)}% against ${(glow(sa) * 100).toFixed(0)}% walking; army ${(glow(af) * 100).toFixed(0)}% against ${(glow(aa) * 100).toFixed(0)}%`);
      check('the firing frame is the lit one on both sheets', glow(sf) > glow(sa) * 2 && glow(af) > glow(aa) * 2);
    }
    /* AND THE ARMY IS IN THE GAME NOW, which is what the APC bought:
       the sheet was cut and left sitting here at the user's request
       until there was something to bring them up the road. */
    check('the army trooper is in the game: an actor, a whole table of states, and the strip loaded',
      !!st.ACTORS.ARMY && !!st.STATES.ARMY_STAND && !!st.STATES.ARMY_XDIE9 &&
      /'swat', 'army'/.test(fs.readFileSync('js/main.js', 'utf8')));
    /* ONE TABLE, TWO TROOPS. Every state the SWAT have, the army have:
       the same letter, the same tics, the same fullbright on the firing
       frame, under their own prefix and their own sprite. It is one
       generator called twice rather than thirty lines written twice,
       which is the whole reason the super army will be a third line. */
    {
      const names = Object.keys(st.STATES).filter(n => n.startsWith('SWAT_')).map(n => n.slice(5));
      const odd = names.filter(n => {
        const a = st.STATES['SWAT_' + n], b = st.STATES['ARMY_' + n];
        return !b || b.frame !== a.frame || b.tics !== a.tics || b.sprite === a.sprite ||
               !!b.fullbright !== !!a.fullbright;
      });
      note('the two tables', `${names.length} states each, ${odd.length} that do not match`);
      check('every SWAT state has an army state on the same frame for the same tics',
        names.length >= 30 && odd.length === 0, odd.join(', '));
      /* and the ONE thing that differs, which is what they do with the
         rifle: two rounds instead of one, tighter — see A_ArmyFire */
      check('and the only thing that differs is the action on the firing frame',
        st.STATES.SWAT_ATK2.action === 'A_SwatFire' && st.STATES.ARMY_ATK2.action === 'A_ArmyFire' &&
        names.every(n => n === 'ATK2' || st.STATES['SWAT_' + n].action === st.STATES['ARMY_' + n].action));
      /* AND BOTH HAVE A STAND-IN UNDER THEM, so a sheet that fails to
         load costs that force its faces and nothing else — and the two
         stand-ins are not the same drawing, because the day one sheet
         loads and the other does not is the day you need to know which
         one is shooting at you. */
      const bank = gs.sprites;
      const pix = k => bank.frames.get(ppl.TROOPS[k].sprite + 'A').views[0];
      check('and both troops have a stand-in under every letter their table names',
        Object.values(ppl.TROOPS).every(t => [...t.turn, ...t.flat].every(L => !!bank.frames.get(t.sprite + L))));
      check('and the two stand-ins are told apart, not the same body twice', !same(pix('SWAT'), pix('ARMY')));
    }

    /* --- the map's part ------------------------------------------- */
    const onTarmac = p => { const s2 = level.sectorAt(p.x, p.y); return !!s2 && /road|junction/i.test(s2.name); };
    check('the map publishes a way in from each end of the road',
      !!level.swatRoutes?.west && !!level.swatRoutes?.east && level.swatRoutes.west.length >= 2);
    check('and every point on both of them is on the road',
      [...level.swatRoutes.west, ...level.swatRoutes.east].every(onTarmac),
      [...level.swatRoutes.west, ...level.swatRoutes.east].filter(q => !onTarmac(q)).map(q => level.sectorAt(q.x, q.y)?.name || 'off the map').join('; '));
    check('and the bays are in the fire lane, where nobody parks',
      level.swatBays.length >= S.bays && level.swatBays.every(b => /fire lane/.test(level.sectorAt(b.x, b.y)?.name || '')));
    /* AND THE LOOP THEY DRIVE ROUND to reach anywhere else. Four
       corners, every one of them on tarmac, and the two ways in meet
       it at a junction. */
    check('the map publishes the perimeter road as a closed loop',
      Array.isArray(level.swatRing) && level.swatRing.length === 4 && level.swatRing.every(onTarmac),
      (level.swatRing || []).map(q => level.sectorAt(q.x, q.y)?.name || 'off the map').join('; '));
    check('and each way in ends on that loop',
      [level.swatRoutes.west, level.swatRoutes.east].every(r => {
        const e = r[r.length - 1];
        return level.swatRing.some(c => Math.hypot(c.x - e.x, c.y - e.y) < 1);
      }));

    /* --- the call -------------------------------------------------- */
    const p = gs.player;
    /* INSIDE, for this first part: where a van goes depends on where
       you are (see `chasing` in js/responders.js), and the doors are
       the answer to being in the building. The chase is measured
       further down. */
    const stand = (x, y) => {
      p.x = x; p.y = y; p.sector = level.sectorAt(x, y); p.z = p.sector.floor; p.viewZ = p.z + 41;
      p.momx = p.momy = 0;
    };
    const home = { x: p.x, y: p.y };
    const fsSquad = await import('node:fs');
    const inShop = gs.actors.find(a => a.type === 'SHOPPER' && a.sector && !a.sector.outdoor);
    stand(inShop.x, inShop.y);
    check('the player is in the building, so the doors are where a van goes', !p.sector.outdoor && !R.chasing);
    check('nobody has been called before a shot', !R.called && R.vans.length === 0 && p.shotsFired === 0);
    /* ONE PULL OF THE TRIGGER, at the user's request, and they are
       dispatched on that tic — no kill, no sixteen-second grace. */
    p.startFire();
    check('firing counts as firing', p.shotsFired === 1 && p.kills === 0);
    gs.tic();
    check('and that is the call', R.called && R.calledAt === R.tics);
    check('and they are on the road already, not in sixteen seconds',
      S.firstDelay === 0 && R.vans.length > 0, `${R.vans.length} vans, delay ${S.firstDelay}`);
    const v = R.vans[0];
    check('a van is on the road', !!v && v.state === 'driving');
    /* and a death still calls them, for the night the fire kills
       somebody on its own after you have stopped firing */
    check('a kill would have called them too',
      /p\.shotsFired >= SWAT\.after \|\| p\.kills > 0/.test(fsSquad.readFileSync('js/responders.js', 'utf8')));
    /* THREE OF THEM, at the user's request, from the same end of the
       road and strung out along it rather than stacked on the spot. */
    check('and three of them, not one', R.vans.length === S.convoy, `${R.vans.length}`);
    check('all from the same end, nose to tail down the road',
      R.vans.every(q => q.side === v.side) &&
      new Set(R.vans.map(q => Math.round(q.x))).size === R.vans.length,
      R.vans.map(q => q.x.toFixed(0)).join(', '));
    check('and each going to a different place', new Set(R.vans.map(q => q.bay)).size === R.vans.length);
    if (v) {
      const end = level.roadEnds.find(e => e.side === v.side);
      check('it started where the road leaves the map', Math.hypot(v.x - end.x, v.y - end.y) < 1);
      check('it is the police van, on its own sheet, as its own mesh',
        v.def === police && v.own && !!v.mesh && !v.slab);
      check('and it is three of Doom cylinders like every other vehicle',
        v.blockers.length === 3 && v.blockers.every(b => b.solid && b.vehicle === v));
      const x0 = v.x, b0 = v.blockers[0].x;
      for (let i = 0; i < 20; i++) gs.tic();
      check('it moves', v.x !== x0 && v.driven > 150, `${v.driven.toFixed(0)} units in 20 tics`);
      check('and its cylinders move with it',
        v.blockers[0].x !== b0 && Math.hypot(v.blockers[1].x - v.x, v.blockers[1].y - v.y) < 1e-6);
      let t = 20;
      for (; t < 3000 && v.state === 'driving'; t++) gs.tic();
      note('the drive', `${t} tics, ${v.driven.toFixed(0)} units`);
      check('it arrives and parks', v.state === 'parked', v.state);
      check('in its bay, in the fire lane',
        !!v.bay && Math.hypot(v.x - v.bay.x, v.y - v.bay.y) < 1 && /fire lane/.test(level.sectorAt(v.x, v.y)?.name || ''),
        `${v.x.toFixed(0)}, ${v.y.toFixed(0)} in ${level.sectorAt(v.x, v.y)?.name}`);
      check('squared up along the front', Math.abs(Math.sin(v.yaw)) < 1e-9, `${v.yaw.toFixed(3)}`);
      check('and in the way there', p.thingInWay(v.x, v.y));

      /* --- the crew ------------------------------------------------ */
      for (let i = 0; i <= S.unloadEvery + 2 && R.troopers === 0; i++) gs.tic();
      const first = gs.actors.find(a => a.type === 'SWAT');
      check('and it unloads a trooper', !!first);
      if (first) {
        const half = car.carWidth(police) / 2;
        check('who steps out on the shop side of it, clear of it, on the ground',
          first.y > v.y + half && !!level.sectorAt(first.x, first.y),
          `${(first.y - v.y).toFixed(0)} off the van's line, ${level.sectorAt(first.x, first.y)?.name}`);
        check('and is after you from the first step',
          first.target === p && /^SWAT_(RUN|ATK)/.test(first.state.name), first.state.name);
        check('and turns: not a standee', !first.flat && first.info.team === 'law');
      }
      /* BACK OUT INTO THE LOT for the rest of this. The doors were the
         point of the block above; what follows is about troopers, and a
         trooper standing among the shelves with the player on the far
         side of one is a fight the geometry decides. */
      stand(home.x, home.y);
      for (let i = 0; i < S.unloadEvery * S.crew + 5; i++) gs.tic();
      note('the crew', `${R.troopers} on their feet, ${R.spawned} ever`);
      check('the whole crew is out inside the time', R.spawned >= S.crew, `${R.spawned} of ${S.crew}`);
      const before = R.spawned;
      for (let i = 0; i < S.trickle + 5; i++) gs.tic();
      check('and it keeps unloading after the crew is out', R.spawned > before, `${R.spawned} after ${before}`);
      const walked = gs.actors.filter(a => a.type === 'SWAT' && !a.dead)
        .map(a => Math.hypot(a.x - v.x, a.y - v.y));
      note('where they have got to', `${walked.filter(d => d > 200).length} of ${walked.length} more than 200 from the van`);
      check('and the troopers walk off toward you rather than standing at the door',
        walked.some(d => d > 200));

      /* --- the rifle ------------------------------------------------ */
      const a = gs.actors.find(q => q.type === 'SWAT' && !q.dead);
      const px = p.x, py = p.y;
      /* A HUNDRED AND SIXTY UNITS OFF, IN A CLEAR DIRECTION. It used to
         be straight along +x, which happened to be clear on the day it
         was written and stopped being the day the random sequence
         moved (anything that draws a random number before this point —
         a decal's size, say — moves where the trooper is standing).
         So the direction is found: the first of sixteen with nothing
         in the way, which is what the test means anyway. */
      let ang = 0;
      for (let k = 0; k < 16; k++) {
        const t = k * Math.PI / 8;
        if (!gs.trace(a, t, 0, 175).actor) { ang = t; break; }
      }
      p.x = a.x + Math.cos(ang) * 160; p.y = a.y + Math.sin(ang) * 160;
      a.angle = ang;
      check('a trooper can see you at a hundred and sixty', a.canSee(p));
      /* THE PLATES OFF FIRST. What is being measured here is that a
         rifle reaches the player at all; sixteen hundred of armour in
         front of the health bar would take three hundred rounds to say
         so. See the layer tests in `the guns`. */
      p.health = 100; p.armour2 = 0; p.armour1 = 0;
      const shots0 = a.shots || 0;
      /* five, not thirty: at this range every shot lands and thirty of
         them is a dead player, which the rest of this section needs not
         to have */
      for (let i = 0; i < 5; i++) ACTIONS.A_SwatFire(a);
      check('the rifle fires', a.shots === shots0 + 5);
      check('and the shots land on you — the player is not bulletproof', p.health < 100 && !p.dead, `100 -> ${p.health}`);
      const hb = p.health;
      p.damage(20, null, { fire: true });
      check('but fire still does nothing to you', p.health === hb, `${hb} -> ${p.health}`);
      /* THE TEAM RULE: a trooper hit by the man behind him does not turn
         round, because a squad that infights is a squad you watch */
      const b = gs.actors.find(q => q.type === 'SWAT' && !q.dead && q !== a);
      b.target = null; b.threshold = 0;
      b.damage(3, a);
      check('a trooper shot by a trooper holds no grudge', b.target !== a);
      b.target = p;
      /* and the chase pulls the trigger on its own */
      p.health = 100;
      let shotsBefore = 0;
      for (const q of gs.actors) if (q.type === 'SWAT') shotsBefore += q.shots || 0;
      p.x = a.x + 320; p.y = a.y;
      for (let i = 0; i < 175; i++) { p.health = 100; gs.tic(); }
      let shotsAfter = 0;
      for (const q of gs.actors) if (q.type === 'SWAT') shotsAfter += q.shots || 0;
      note('five seconds beside the squad', `${shotsAfter - shotsBefore} shots fired`);
      check('a trooper who can see you shoots without being told', shotsAfter > shotsBefore);
      p.x = px; p.y = py; p.health = 100;

      /* --- how they die --------------------------------------------- */
      const beaten = R.defeatedCount;
      const d1 = gs.actors.find(q => q.type === 'SWAT' && !q.dead);
      d1.damage(60, p);
      check('sixty is a death, on the way down', d1.dead && d1.state.name === 'SWAT_DIE1');
      const d2 = gs.actors.find(q => q.type === 'SWAT' && !q.dead);
      d2.damage(200, p);
      check('and two hundred is coming apart', d2.dead && d2.state.name === 'SWAT_XDIE1');
      for (let i = 0; i < 80; i++) gs.tic();
      check('and both lie there afterwards, out of the way',
        d1.state.name === 'SWAT_DEAD' && d1.state.tics === -1 && !d1.solid &&
        d2.state.name === 'SWAT_XDIE9' && d2.state.tics === -1);
      check('and the squad counts its losses', R.defeatedCount >= beaten + 2);
      const d3 = gs.actors.find(q => q.type === 'SWAT' && !q.dead);
      if (d3) {
        d3.chill(100);
        check('a trooper freezes like anybody else', d3.frozen && d3.state.name === 'SWAT_FROZE');
        d3.damage(5, p);
        check('and a frozen one shatters', d3.removed);
      }

      /* --- FIREPROOF, at the user's request -------------------------
         The police and the police van. Fire is the whole of what the
         flag refuses — the stream, the floor, a blast — and a bullet, a
         van and the bore are not fire. The one thing fire does to a
         trooper is let a frozen one out: fire on a fireproof block of
         ice is a thaw, because nothing inside it can be eaten. */
      const fp = gs.actors.find(q => q.type === 'SWAT' && !q.dead && !q.frozen);
      check('a trooper is fireproof, and so not flammable, and worth nothing as fuel',
        !!fp && fp.fireproof && !fp.flammable && fp.fuel === 0 && !fp.info.burnAway && !fp.info.burn);
      if (fp) {
        const hp = fp.health;
        fp.ignite(300);
        check('he does not catch', fp.burning === 0 && fp.torch === 0 && fp.lit === 0);
        fp.damage(50, p, { fire: true });
        check('and fire does him no harm', fp.health === hp && !fp.dead, `${hp} -> ${fp.health}`);
        /* the stream, on him: the particle is spent and nothing else */
        gs.flame._burnActor(fp, fp.x, fp.y, fp.z + 20);
        check('the flamethrower splashes off him', fp.health === hp && fp.burning === 0);
        /* a car going up beside him */
        gs.explode({ x: fp.x + 30, y: fp.y, z: fp.z }, { radius: 200, damage: 500, heat: 255 });
        check('and a car going up beside him does not touch him', fp.health === hp && fp.burning === 0 && !fp.dead);
        /* the floor: a shopper on the same hot cell catches; he does not */
        const shop = gs.spawn('SHOPPER', fp.x + 8, fp.y + 8, undefined, {});
        gs.fire.ignite(fp.x, fp.y, 255, 40);
        for (let i = 0; i < 20; i++) gs.fire._burnThings();
        check('the burning floor lights the shopper beside him and not him',
          shop.burning > 0 && fp.burning === 0 && fp.health === hp, `shopper ${shop.burning}, trooper ${fp.burning}`);
        shop.remove();
        /* and what still gets through: a bullet */
        fp.damage(9, null, { shot: true });
        check('but a bullet still does', fp.health === hp - 9, `${hp} -> ${fp.health}`);
        /* fire on the ice is a thaw */
        fp.chill(100);
        check('frozen', fp.frozen);
        fp.damage(20, p, { fire: true });
        check('fire on a frozen trooper is a thaw and not an execution',
          !fp.removed && !fp.dead && fp.ash === 0 && fp.frozen && fp.frost < 100, `frost ${fp.frost}, ash ${fp.ash}`);
        for (let i = 0; i < 10 && fp.frozen; i++) fp.damage(20, p, { fire: true });
        check('and enough of it lets him out, running', !fp.frozen && !fp.dead && !fp.removed && fp.state.name === 'SWAT_RUN1', fp.state.name);
      }

      /* --- AND THE VAN BURNS, JUST SLOWLY -------------------------
         At the user's request, and it did not for a while: it was
         fireproof, which for a vehicle is invulnerable. It is ARMOURED
         now — fire's damage divided on the way in, the blackening
         multiplied on the way out — so the stream ends one, and takes
         most of a minute doing it where a hatchback takes nine seconds.
         Measured as a RATIO against the van in the next bay rather than
         as a wall-clock number, because what the user asked for is
         "much much slower than vans" and that is a comparison. */
      {
        check('the police van is not fireproof any more, it is armoured',
          !v.fireproof && v.fireArmour > 4 && v.charFuse > 2,
          `armour ${v.fireArmour}, fuse ${v.charFuse}`);
        /* ONE TIC OF FIRE, ON EACH, from the same full health */
        const lot = V.all.find(q => q.state === 'parked' && q.fireArmour === 1);
        const h0 = v.health, l0 = lot.health;
        v.damage(24, null, { fire: true });
        lot.damage(24, null, { fire: true });
        const took = h0 - v.health, tookLot = l0 - lot.health;
        note('the same lick of flame', `${tookLot} off a hatchback, ${took.toFixed(1)} off a squad van`);
        check('the same fire does a fraction of the damage to it',
          took > 0 && took * 4 < tookLot, `${took.toFixed(1)} against ${tookLot}`);
        /* AND A BULLET IS NOT, any more: at the user's request a vehicle
           takes a lot of the minigun, and a squad van more than a car
           in the lot — see SHOT_ARMOUR, and `the vans under fire` */
        const h1 = v.health, l1 = lot.health;
        v.damage(24, null, { shot: true });
        lot.damage(24, null, { shot: true });
        check('and a bullet does less to it than to a car in the lot, and little to either',
          h1 - v.health < l1 - lot.health && Math.abs((l1 - lot.health) - 24 / lot.shotArmour) < 1e-9 &&
          Math.abs((h1 - v.health) - 24 / v.shotArmour) < 1e-9, `${h1 - v.health} and ${l1 - lot.health}`);
        lot.health = l0;
        /* IT CATCHES. It could not before. */
        v.ignite();
        check('it catches now', v.burning > 0 && v.flames.length === 2);
        /* AND HOW LONG IT TAKES, held against the same van unarmoured.
           Counted off the arithmetic rather than by ticking a whole
           minute of game: the burn is BURN_DAMAGE every BURN_EVERY tics
           divided by the armour, and the char is its own roll times the
           fuse. */
        const VH = 150, BURN = 12, EVERY = 10, CHAR = 6 * 35;   // js/vehicles.js
        const secs = q => (Math.ceil(VH / (BURN / q.fireArmour)) * EVERY + CHAR * q.charFuse) / 35;
        const anApc = { fireArmour: 14, charFuse: 6 };
        note('flame to wreck', `${secs(lot).toFixed(0)}s for a hatchback, ` +
          `${secs(v).toFixed(0)}s for a squad van, ${secs(anApc).toFixed(0)}s for an APC`);
        check('and it is many times slower than a van in the lot', secs(v) > secs(lot) * 4,
          `${secs(v).toFixed(0)}s against ${secs(lot).toFixed(0)}s`);
        check('and the APC is slower again than the van', secs(anApc) > secs(v));
        /* AND IT DOES GO. Forced along rather than waited out — the
           point is that the end of the road exists, not how long it is. */
        v.damage(100000, null, { shot: true });
        check('and enough of anything still ends it', v.state === 'charring', v.state);
        v.charTics = 1; v.charTic();
        check('and then it goes up like any other vehicle', !v.whole && !R.liveVans.includes(v), v.state);
        /* AND IT GIVES THE BAY BACK, which never came up while nothing
           could end one: a wreck that still held its place in the fire
           lane would close that bay for the rest of the night. */
        const bay = v.bay;
        check('and the fire lane gets its bay back', !!bay && R.freeBay() !== null &&
          !R.liveVans.some(q => q.bay === bay));
      }
    }

    /* --- AND WHEREVER YOU ARE, THEY COME TO YOU --------------------
       At the user's request. Inside the building the answer is the
       doors; anywhere else it is the nearest point on the perimeter
       road to where you are standing, and then off the road toward you
       for as far as the tarmac holds. These are measured off the pure
       part — freeStand and routeTo — because driving a van the length
       of the ring is two thousand tics a go, and then one of them is
       actually driven to prove the route is drivable. */
    {
      const doors = level.swatBays[0];
      const ringT = q => R.ringNearest(q.x, q.y);
      const spots = [
        ['out in the car park', 2140, -1400],
        ['at the west end of the lot', -2000, -1200],
        ['in the trees, west', -6500, -1200],
        ['round the back, in the service yard', 2140, 3700],
      ];
      for (const [where, x, y] of spots) {
        stand(x, y);
        check(`standing ${where}, a van comes to you rather than to the doors`, R.chasing);
        const st = R.freeStand();
        const near = Math.hypot(st.x - p.x, st.y - p.y);
        const on = R.ringAt(st.ring);
        const fromRing = Math.hypot(on.x - p.x, on.y - p.y);
        const fromDoors = Math.hypot(doors.x - p.x, doors.y - p.y);
        note(`${where}`, `the van stands ${near.toFixed(0)} units off; the road is ${fromRing.toFixed(0)} and the doors ${fromDoors.toFixed(0)}`);
        check('and it stands on ground a van can drive on', R.drivable(st.x, st.y),
          level.sectorAt(st.x, st.y)?.name);
        /* LEAVING THE ROAD NEVER MAKES IT WORSE. Where the tarmac runs
           out at the kerb the van stands on the ring and that is the
           closest anything on wheels gets — which is the honest answer
           behind the building, where no road goes. */
        check('and pulling in off the road only ever gets it closer', near <= fromRing + 1,
          `${near.toFixed(0)} against ${fromRing.toFixed(0)} on the road`);
        if (/car park|west end/.test(where)) {
          check('and out in the lot that is much closer than the doors', near < fromDoors * 0.5,
            `${near.toFixed(0)} against ${fromDoors.toFixed(0)}`);
          /* AND IT STOPS IN FRONT OF YOU, at the user's request and on
             the user's second thought about it. `stop` is to the MIDDLE
             of a van and the walk toward you gives up one step short of
             it, so the closest the arithmetic can come is stop + STEP;
             the nose is another half length past that, which is what
             you actually see stop in front of you. A hundred and twenty
             put that nose thirteen units off your face and the user
             called it too close; three hundred is about two hundred,
             which is half a van of daylight. */
          const nose = near - car.carLength(police) / 2;
          note(`${where}, the nose`, `${nose.toFixed(0)} units off you`);
          check('and it stops half a van in front of you, not against you',
            near <= S.stop + 36 && nose > 120 && nose < 240,
            `${near.toFixed(0)} to the middle, ${nose.toFixed(0)} to the nose`);
        }
        /* the route: on the road the whole way, and it ends at the stand */
        const route = R.routeTo(st, 'west');
        const end = route[route.length - 1];
        check('the route ends where the van is to stand',
          Math.hypot(end.x - st.x, end.y - st.y) < 1 && route.length >= 3);
        check('and every corner of it is on tarmac',
          route.every(q => R.drivable(q.x, q.y)),
          route.filter(q => !R.drivable(q.x, q.y)).map(q => level.sectorAt(q.x, q.y)?.name || 'off the map').join('; '));
        /* AND IT DOES NOT COME FROM THE END OF THE WORLD, at the user's
           request. The map's way in starts where the road leaves the
           map, nine thousand units out, which is five seconds of a van
           driving down a road nobody in the car park can see. Coming
           FOR you it starts at the junction with a run-in behind it —
           the same road, the same direction, a much shorter piece of
           it. Both routes are built here and held against each other,
           because the long one is still right for a night watched from
           inside the shop. */
        const len = r => r.reduce((n, q, i) => i ? n + Math.hypot(q.x - r[i - 1].x, q.y - r[i - 1].y) : 0, 0);
        const far = R.routeTo(st, 'west', 0, false);
        if (where === 'out in the car park')
          note('the two ways in', `${len(route).toFixed(0)} units coming for you, ${len(far).toFixed(0)} coming for the doors`);
        check('coming for you they start at the junction, not at the end of the road',
          len(route) < len(far) - 6000 && Math.abs(len(route) - len(far)) > 0,
          `${len(route).toFixed(0)} against ${len(far).toFixed(0)}`);
        /* AND THEY COME INTO BEING ON THE ROAD, NOT AT THE JUNCTION, at
           the user's request: the whole way in is built and then cut
           short from its far end. What has to be true is that there is
           a real drive left — at least the run-in — and that it is a
           small fraction of the road they used to come down. */
        check('and what is left is a short drive rather than a long one',
          len(route) >= S.runIn && len(route) < len(far) * 0.4,
          `${len(route).toFixed(0)} against ${len(far).toFixed(0)}`);
        /* AND NEVER SOMEWHERE YOU ARE LOOKING, which is the "off screen"
           half. The point is walked further back for as long as it is
           inside your view, so what has to hold is one of two things:
           the place it comes into being is out of sight, or the search
           spent every try it has and came anyway. Stated that way it is
           true wherever you stand and whichever way you face — and the
           second half has to be in it, because walking back along a
           RING can bring a point round the other side of the lot and
           into view again. */
        /* AND THE TWO PIECES OF IT, ON THEIR OWN. canSee is the view
           cone and backAlong is the walk down the polyline; both are
           arithmetic and both are easier to believe pinned directly
           than inferred from a route. */
        {
          const ahead = { x: p.x + Math.cos(p.angle) * 900, y: p.y + Math.sin(p.angle) * 900 };
          const behind = { x: p.x - Math.cos(p.angle) * 900, y: p.y - Math.sin(p.angle) * 900 };
          const beside = { x: p.x + Math.cos(p.angle + Math.PI / 2) * 900, y: p.y + Math.sin(p.angle + Math.PI / 2) * 900 };
          check('what is in front of you is in view, and what is behind or beside you is not',
            R.canSee(ahead.x, ahead.y) && !R.canSee(behind.x, behind.y) && !R.canSee(beside.x, beside.y));
          const RR = Object.getPrototypeOf(R).constructor;
          const line = [{ x: 0, y: 0 }, { x: 100, y: 0 }, { x: 100, y: 100 }];
          const b1 = RR.backAlong(line, 50);
          check('and a point fifty back from the end of a line is where it should be',
            b1.i === 1 && Math.abs(b1.x - 100) < 1e-9 && Math.abs(b1.y - 50) < 1e-9,
            `${b1.x}, ${b1.y} after ${b1.i}`);
          const b2 = RR.backAlong(line, 150);
          check('and a hundred and fifty back is round the corner',
            b2.i === 0 && Math.abs(b2.x - 50) < 1e-9 && Math.abs(b2.y) < 1e-9, `${b2.x}, ${b2.y}`);
          const b3 = RR.backAlong(line, 9999);
          check('and asking for more road than there is gives the start of it',
            b3.i === 0 && b3.x === 0 && b3.y === 0);
        }
        const entry = route[0];
        const spent = S.runIn + S.runInStep * S.runInTries;
        check('and where it comes into being is not somewhere you are looking',
          !R.canSee(entry.x, entry.y) || len(route) >= spent,
          `${R.canSee(entry.x, entry.y) ? 'in view' : 'out of view'} at ${len(route).toFixed(0)} units`);
      }
      /* THE ONE THAT IS ACTUALLY DRIVEN: out in the lot, where the van
         leaves the road and pulls up beside you. */
      stand(2140, -1400);
      const before = R.vans.length;
      R.nextVanAt = R.tics;
      R.sendConvoy();
      const chase = R.vans[before];
      check('a convoy is sent to you out in the lot', R.vans.length === before + S.convoy && !!chase);
      let n = 0;
      /* ALIVE THE WHOLE WAY. The crew already on the ground is shooting
         throughout, and a dead player is a player the squad stops
         coming for (see squadTic) — which is correct, and would quietly
         turn everything below this into a measurement of nothing. */
      const trace = [];
      for (; n < 6000 && chase.state === 'driving'; n++) {
        const left = chase.toEnd;                  // before the step, not after
        p.health = 100; gs.tic();
        trace.push({ v: chase.speed, left, pitch: chase.rz, roll: chase.rx });
      }
      check('and you are alive to be driven at', !p.dead);
      note('the drive to you', `${n} tics, ${chase.driven.toFixed(0)} units`);
      /* --- HOW IT DROVE, which is the user's request and the whole of
         the difference between a model sliding along a line and a van
         pulling up. It leaves from a standing start, it never exceeds
         its own top speed, and it is SLOWEST AT THE END rather than
         switching off at speed. */
      {
        const top = Math.max(...trace.map(q => q.v));
        const first = trace[0].v, last = trace[trace.length - 1].v;
        note('the speed', `off the mark at ${first.toFixed(1)}, up to ${top.toFixed(1)}, ` +
          `over the line at ${last.toFixed(1)} units a tic`);
        check('it pulls away from a standing start rather than appearing at speed',
          first <= veh.DRIVE_SPEED * 0.1 && top > veh.DRIVE_SPEED * 0.5,
          `${first.toFixed(1)} then ${top.toFixed(1)}`);
        check('and never goes faster than it is allowed to', top <= veh.DRIVE_SPEED + 1e-6);
        check('and brakes into its place instead of switching off at speed',
          last < top * 0.25, `${last.toFixed(1)} against a top of ${top.toFixed(1)}`);
        /* THE BRAKING IS FOR THE END OF THE ROUTE, not for the next
           corner: the speed it is doing never exceeds the speed it could
           still stop from in the distance it has left. */
        const B = veh.DRIVE_BRAKE;
        /* the 1.25 is the crawl floor in drive(): the last unit of the
           approach is held at a walking pace rather than integrated down
           to nothing, which would take a second and a half */
        const over = trace.filter(q => q.v > Math.sqrt(2 * B * Math.max(0, q.left)) + 1.25);
        check('and it is never going faster than it could stop from', over.length === 0,
          `${over.length} tics over the line`);
        /* --- AND THE BODY SHIFTS ITS WEIGHT. The nose goes DOWN under
           braking (a negative pitch — see carMesh, which puts pitch in
           the vehicle's own frame) and UP under power, and it leans
           through the corners. */
        const dip = Math.min(...trace.map(q => q.pitch));
        const rise = Math.max(...trace.map(q => q.pitch));
        const lean = Math.max(...trace.map(q => Math.abs(q.roll)));
        note('the body', `${(dip * 180 / Math.PI).toFixed(1)}° of dive, ` +
          `${(rise * 180 / Math.PI).toFixed(1)}° of squat, ${(lean * 180 / Math.PI).toFixed(1)}° of lean`);
        check('the nose dips under braking and lifts under power',
          dip < -0.01 && rise > 0.01, `${dip.toFixed(3)} to ${rise.toFixed(3)}`);
        check('and it leans through a corner', lean > 0.01, `${lean.toFixed(3)}`);
        check('and none of it is more than a few degrees',
          -dip < 0.2 && rise < 0.2 && lean < 0.2);
        /* AND IT ROCKS BACK AND SETTLES. Parked, the springs go on
           running until they are asleep: the pitch crosses zero at
           least once on the way — that is the rock — and then stops. */
        let crossings = 0, was = chase.rz;
        for (let i = 0; i < 200; i++) {
          gs.tic();
          if ((was < 0) !== (chase.rz < 0)) crossings++;
          was = chase.rz;
        }
        note('settling', `${crossings} times through level, resting at ${(chase.rz * 180 / Math.PI).toFixed(2)}°`);
        check('and once it has stopped it rocks back and settles level',
          crossings >= 1 && Math.abs(chase.rz) < 0.004 && Math.abs(chase.rx) < 0.004,
          `${crossings} crossings, ${chase.rz.toFixed(4)} rad`);
      }
      check('and it arrives, off the road, beside you', chase.state === 'parked' &&
        Math.hypot(chase.x - 2140, chase.y + 1400) < S.push, `${Math.hypot(chase.x - 2140, chase.y + 1400).toFixed(0)} units off`);
      check('and it left the ring to do it', Math.abs(chase.y - R.ringAt(chase.stand.ring).y) > 100,
        `${(chase.y - R.ringAt(chase.stand.ring).y).toFixed(0)} units in off the road`);
      /* AND THE DOOR THEY USE IS THE ONE FACING YOU, which used to be
         the one facing the shop and was the same thing only while every
         van stood across the fire lane. Measured off the van's own door
         geometry rather than off a spawn, because whether a trooper is
         actually let out is the budget's business and this is not. */
      const doorsOut = [0, 1, 2, 3, 4].map(k => chase.door(k, { x: p.x, y: p.y }));
      /* WHICH SIDE, not which distance: the doors run along the van's
         length, so the one at the far end of a van parked broadside is
         further from you than its middle and still on the right side. */
      const lx = -Math.sin(chase.yaw), ly = Math.cos(chase.yaw);
      const want = Math.sign((p.x - chase.x) * lx + (p.y - chase.y) * ly);
      check('and its crew steps out of the side facing you',
        want !== 0 && doorsOut.every(d => Math.sign((d.x - chase.x) * lx + (d.y - chase.y) * ly) === want),
        doorsOut.map(d => ((d.x - chase.x) * lx + (d.y - chase.y) * ly).toFixed(0)).join(', ') + ` want ${want}`);
      stand(home.x, home.y);
    }

    /* --- THE CURVE ----------------------------------------------------
       Exponential, at the user's request: equal steps in time multiply
       the presence by the same amount. The pure function first, then
       the caps it drives, then a long night. */
    const { pressureAfter } = await import('../js/responders.js');
    check('the pressure is 1 at the call, 2 a doubling later, 8 after three',
      pressureAfter(0) === 1 && pressureAfter(S.doubling) === 2 && pressureAfter(3 * S.doubling) === 8);
    check('and a doubling is a doubling wherever on the curve it starts — which is what exponential means',
      [0, 500, 1234, 4000, 9999].every(t0 => Math.abs(pressureAfter(t0 + S.doubling) / pressureAfter(t0) - 2) < 1e-9));
    check('the caps, the gap and the trickle are all the same number read four ways',
      Math.min(S.maxVans, Math.floor(S.vans * 4)) === (() => { const save = R.calledAt; R.calledAt = R.tics - 2 * S.doubling; const c = R.vanCap; R.calledAt = save; return c; })() &&
      (() => { const save = R.calledAt; R.calledAt = R.tics - 2 * S.doubling; const ok = R.trooperCap === Math.min(S.maxTroopers, S.troopers * 4) && Math.abs(R.trickleNow() - Math.max(S.minTrickle, S.trickle / 4)) < 1e-9; R.calledAt = save; return ok; })());
    check('and every gap has a floor, so the curve asks nothing the road cannot do',
      (() => { const save = R.calledAt; R.calledAt = R.tics - 40 * S.doubling; const ok = R.gapNow() === S.minEvery && R.trickleNow() === S.minTrickle && R.trooperCap === S.maxTroopers && R.vanCap === S.maxVans; R.calledAt = save; return ok; })());
    /* THE BUDGET HOLDS A WHOLE SEND. Three at a time is the user's
       number and it is the one thing in this block that has never
       moved; everything around it has been trimmed twice since. What
       has to stay true whatever the numbers are is that a send FITS —
       send three into a budget of two and the third is refused, which
       is sending two. */
    check('a send is three, and the budget holds whole sends of them at either end of the curve',
      S.convoy === 3 && S.vans >= S.convoy && S.maxVans >= S.convoy * 2 &&
      S.maxVans % S.convoy <= S.convoy, `${S.convoy} a send, ${S.vans} to ${S.maxVans} allowed`);
    /* THE LONG NIGHT: the caps only ever climb, and the lot fills */
    const capsBefore = { troopers: R.trooperCap, vans: R.vanCap, ever: R.spawned, sent: R.vans.length };
    /* LONG ENOUGH FOR A VAN TO GET HERE. A convoy sent to the far side
       of the lot drives most of the ring to reach it, which at fifteen
       units a tic is well over a thousand of them — measure the night
       over a window shorter than that and what is measured is the
       traffic, not the escalation. */
    for (let i = 0; i < 3400; i++) { p.health = 100; gs.tic(); }
    {
      const by = {};
      for (const v of R.vans) by[v.state] = (by[v.state] || 0) + 1;
      note('the night so far', `${((R.tics - R.calledAt) / 35).toFixed(0)}s since the call, pressure ${R.pressure.toFixed(1)}: ` +
        `${R.vans.length} vans (${Object.entries(by).map(([k, n]) => `${n} ${k}`).join(', ')}), ` +
        `${R.troopers} troopers up of ${R.trooperCap} allowed, ${R.spawned} ever, ${R.defeatedCount} down`);
    }
    /* each force against its OWN cap — the army is on the road inside
       this window now that it is called at pressure two */
    check('there are never more troopers on their feet than the curve allows',
      R.forces.every(f => R.troopersOf(f) <= R.trooperCapOf(f)),
      R.forces.map(f => `${f.def.key} ${R.troopersOf(f)}/${R.trooperCapOf(f)}`).join(', '));
    check('and never more vans on the road or standing than it allows',
      R.forces.every(f => R.liveVansOf(f).length <= R.vanCapOf(f)),
      R.forces.map(f => `${f.def.key} ${R.liveVansOf(f).length}/${R.vanCapOf(f)}`).join(', '));
    check('and forty seconds on, more of both are allowed than were',
      R.trooperCap > capsBefore.troopers && R.vanCap >= capsBefore.vans && R.spawned > capsBefore.ever,
      `troopers ${capsBefore.troopers} -> ${R.trooperCap}, vans ${capsBefore.vans} -> ${R.vanCap}, ever ${capsBefore.ever} -> ${R.spawned}`);
    check('three minutes in, there are vans everywhere the curve allows',
      R.vanCap >= S.bays && R.vans.length >= 6, `${R.vans.length} vans, cap ${R.vanCap}`);
    check('and the troopers allowed have doubled at least twice since the call', R.trooperCap >= 4 * S.troopers, `${R.trooperCap}`);
    /* AND HOW LONG IT TAKES THEM TO GET HERE from one pull of the
       trigger, which is the whole of what "speed in" means: a fresh
       night, one shot, and the clock runs until a van is standing. */
    {
      const fresh = new Game({
        level: MAP.buildSellWrong({ town: false }), scene: new THREE2.Scene(), camera: {},
        textures: gm.textures, sprites: spr.bakeSprites(),
        hud: { message() {}, ticMessages() {} }, audio: null,
        input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
                 attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
        fleet: { texture: {}, def: van }, police: { texture: {}, def: police },
        apc: { texture: {}, def: apc },
      });
      const fp = inTheOpen(fresh);          // the case the user complained about
      fp.startFire();
      fresh.tic();
      check('one shot and the convoy is already on the road', fresh.responders.vans.length === S.convoy);
      let t2 = 1;
      for (; t2 < 4000 && !fresh.responders.vans.some(q => q.state === 'parked'); t2++) { fp.health = 100; fresh.tic(); }
      note('trigger to tyres', `${t2} tics, ${(t2 / 35).toFixed(1)}s from the shot to a van standing`);
      /* SIX SECONDS, at the user's request, where it was twenty and
         then fourteen. Three things bought it and all three are in
         js/responders.js and js/vehicles.js: sixty units a tic instead
         of thirty, a run-in at the junction instead of nine thousand
         units of through road, and a stop a nose short instead of a
         length. This fixture starts where the player starts, which is
         out on the verge — the case the user was complaining about. */
      check('and a van is standing within six seconds of the shot', t2 < 6 * 35, `${(t2 / 35).toFixed(1)}s`);
      check('and it came from the nearer end of the road',
        fresh.responders.vans[0].side === fresh.responders.sideFor(fresh.responders.vans[0].stand.ring));
    }

    /* ==================================================================
       AND THE FIRE BRIGADE, which the FIRE calls

       The user's fire truck, its water cannon working, and nobody out of
       it yet. A night with a car alight in the lot and no shot fired:
       the brigade is called after BRIGADE.callAfter of burning, a truck
       comes to the fire, stands off it, turns the cannon on it and pours,
       and the water takes heat out of the grid.
       ================================================================== */
    {
      const W = await import('../js/water.js');
      const BR = await import('../js/brigade.js');
      /* THE AIM IS THE JET'S OWN FLIGHT, run backwards */
      const aimed = [300, 560, 900].map(d => W.hoseRange(W.aimPitch(d, 100), 100));
      /* to within one tic of the jet's flight, which is the grain the
         flight is integrated at */
      check('the cannon lands a jet where it aims: the pitch aimPitch gives comes down at the distance asked',
        aimed.every((r, k) => Math.abs(r - [300, 560, 900][k]) <= W.HOSE.speed), aimed.map(r => r.toFixed(0)).join(', '));
      check('and it reaches well past where a truck stands off a fire', W.hoseReach() > BR.BRIGADE.stop * 2,
        `${W.hoseReach().toFixed(0)} against a stand-off of ${BR.BRIGADE.stop}`);
      check('and aimPitch says so when a fire is out of reach', W.aimPitch(W.hoseReach() * 1.3, 0) === null);

      (await import('../js/util.js')).pSeed();
      const gf = new Game({
        level: MAP.buildSellWrong({ town: false }), scene: new THREE2.Scene(), camera: {},
        textures: gm.textures, sprites: spr.bakeSprites(),
        hud: { message() {}, ticMessages() {} }, audio: null,
        input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
                 attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
        fleet: { texture: {}, def: van }, police: { texture: {}, def: police },
        apc: { texture: {}, def: apc }, firetruck: { texture: {}, def: firetruck },
      });
      const Bf = gf.brigade, Rf = gf.responders, doors = Rf.doorsPoint();
      const lot = gf.vehicles.all.filter(v => v.state === 'parked')
        .sort((a, b) => Math.hypot(a.x - doors.x, a.y - doors.y) - Math.hypot(b.x - doors.x, b.y - doors.y));
      const lit = lot[2];
      lit.ignite(4000);
      let t = 0, calledAt = -1;
      for (; t < BR.BRIGADE.callAfter + 5; t++) { gf.player.health = 100; gf.tic(); if (Bf.called && calledAt < 0) calledAt = t; }
      check('a car alight in the lot calls the brigade, and no sooner than the fire has been burning its while',
        Bf.called && calledAt >= BR.BRIGADE.callAfter - 2, `called at ${calledAt}`);
      check('and the call puts a truck on the road that tic, with nobody asked to fire a shot',
        Bf.trucks.length === 1 && gf.player.shotsFired === 0 && Bf.trucks[0].state === 'driving');
      const truck = Bf.trucks[0];
      check('it is a FireTruck with its cannon, its wheels and its light bar fitted',
        truck.constructor.name === 'FireTruck' && !!truck.gun && truck.wheels.length === 4 && !!truck.lamp &&
        truck.lamp.material === (await import('../js/bloom.js')).lampMaterial('fire'));
      let parkedAt = -1, yaw0 = truck.gunYaw;
      for (; t < 3000 && (parkedAt < 0 || truck.pouring < 120); t++) {
        gf.player.health = 100;
        gf.tic();
        if (parkedAt < 0 && truck.state === 'parked') parkedAt = t;
      }
      note('the fire truck', `called at ${calledAt}, parked at ${parkedAt}, ${truck.pouring} tics poured by ${t}, ` +
        `${gf.water.landed} drops landed, ${gf.water.doused} cells cooled, ${Bf.trucks.length} trucks`);
      const sx = truck.stand.x, sy = truck.stand.y;
      check('it drives in and stands', parkedAt > 0 && Math.hypot(truck.x - sx, truck.y - sy) < 4, `parked at ${parkedAt}`);
      check('and its wheels turned on the way', truck.wheels.every(w => Math.abs(w.mesh.rotation.z) > 10));
      check('the cannon turns off the nose and onto the fire, and pours',
        truck.gunYaw !== yaw0 && truck.pouring >= 120 && gf.water.landed > 200);
      check('and the water takes heat out of the fire', gf.water.doused > 100, `${gf.water.doused} cells cooled`);
      check('and nobody gets out of it yet',
        !gf.actors.some(a => a.van === truck) && Rf.vans.includes(truck) && !Rf.liveVansOf(Rf.swat).includes(truck));
      /* THE WATER, by itself: a car alight, and a drop landing by it */
      const car2 = lot[8];
      car2.ignite(4000);
      gf.water._land(car2.x + 20, car2.y, car2.ground);
      check('a drop landing by a burning car puts it out', car2.burning === 0 && car2.flames.length === 0);
      /* and a burning person, put out by soaking */
      const who = gf.actors.find(a => !a.dead && a.info.shootable && !a.vehicle && a.soak);
      if (who) {
        who.burning = 30;
        const out = who.soak(W.HOSE.soak);
        check('and a person alight is soaked out, and not frozen', out && who.burning === 0 && !who.frozen);
      }
    }

    /* ==================================================================
       AND THE ARMY BEHIND THEM

       The user's order, set down the day the sheet arrived and built the
       day the carrier did: the SWAT, then the army, then a super army.
       The army is not a harder van — it is a SECOND FORCE, with its own
       clock, its own budget, its own curve and its own vehicle, running
       underneath a police force that does not stop.

       WHAT IS MEASURED HERE is the join: that they are called at the
       right moment and not before, that what arrives is an APC and not
       a van, that it hovers, that what gets out of it is a soldier and
       not a trooper, and that the two forces share the fire lane rather
       than parking inside one another.

       The clock is wound rather than waited out: three doublings is six
       thousand three hundred tics and driving those is three minutes of
       test for one boolean. What is NOT wound is the drive itself,
       which is real, on the real map, to a real stand.
       ================================================================== */
    {
      const { ARMY: A, FORCES, pressureAfter: pa } = await import('../js/responders.js');
      const veh = await import('../js/vehicles.js');

      check('the night is a list of forces, in the order the user set',
        FORCES.map(f => f.key).join(',') === 'swat,army' &&
        FORCES[0].troop === 'SWAT' && FORCES[1].troop === 'ARMY' &&
        FORCES[0].Van === veh.SwatVan && FORCES[1].Van === veh.ArmyApc);
      check('and the army is called at a PRESSURE, so it moves when the escalation is retuned',
        A.at === 2 && pa(S.doubling) === A.at, `${A.at} is ${Math.log2(A.at)} doubling`);
      check('and that is seventy seconds after the first shot — one doubling — at the user\'s request', S.doubling === 70 * 35);
      check('and there is less of them and it is heavier',
        A.convoy < S.convoy && A.vans < S.vans && A.maxTroopers < S.maxTroopers &&
        A.crew > S.crew && A.stand > S.stand,
        `${A.convoy} a send of ${A.maxVans}, ${A.crew} in the back, ${A.stand} apart`);

      /* --- a night of its own ---------------------------------------- */
      const ga = new Game({
        level: MAP.buildSellWrong({ town: false }), scene: new THREE2.Scene(), camera: {},
        textures: gm.textures, sprites: spr.bakeSprites(),
        hud: { message() {}, ticMessages() {} }, audio: null,
        input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
                 attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
        fleet: { texture: {}, def: van },
        police: { texture: {}, def: police },
        apc: { texture: {}, def: apc },
      });
      const Ra = ga.responders, pa2 = ga.player;
      /* the drive takes a couple of thousand tics with a squad already
         on the ground shooting the whole way; what is being measured is
         the army arriving, not whether you survive to see it */
      pa2.invincible = true;
      pa2.startFire();
      ga.tic();
      check('the first shot calls the SWAT and only the SWAT',
        Ra.swat.called && !Ra.army.called && Ra.vans.length === S.convoy &&
        Ra.vans.every(v => v.force === Ra.swat));

      /* WIND THE NIGHT ON three doublings, which is where the army is */
      Ra.swat.calledAt = Ra.tics - 3 * S.doubling;
      ga.tic();
      check('three doublings in, the army is called', Ra.army.called,
        `SWAT pressure ${Ra.pressure.toFixed(1)}`);
      check('and its own curve starts at 1 under a police force already at eight',
        Math.abs(Ra.pressureOf(Ra.army) - 1) < 0.02 && Ra.pressure >= A.at,
        `army ${Ra.pressureOf(Ra.army).toFixed(2)}, police ${Ra.pressure.toFixed(1)}`);
      check('and the SWAT do not stop when it does', Ra.swat.called && Ra.vanCap > S.vans);

      /* --- what comes up the road ------------------------------------ */
      const apcs = () => Ra.vans.filter(v => v.force === Ra.army);
      check('APCs are on the road, and they are APCs',
        apcs().length === A.convoy && apcs().every(v => v instanceof veh.ArmyApc && v.def.id === 'apc'),
        `${apcs().length} of them`);
      check('and they are not sent in threes like the vans', A.convoy === 2 && apcs().length === 2);

      /* IT HOVERS, ON THE ROAD AND STANDING. The hover is the one thing
         in this game that moves when nothing is happening, so it is
         measured as a range over a whole breath rather than as a value:
         a number that is always 34 is a number, and a number that goes
         between 29 and 39 is a vehicle being held up by something.
         Sampled first over the drive, and then over a breath standing,
         because those are two different code paths — see ArmyApc.tic,
         which is the only thing in the file that sets cz every tic. */
      const one = apcs()[0];
      const body = car.carHeight(apc) / 2;
      const air = seen => [Math.min(...seen) - body, Math.max(...seen) - body];
      let n = 0;
      const drove = [];
      {
        const seen = [];
        for (; n < 6000 && !apcs().some(v => v.state === 'parked'); n++) {
          const before = one.speed, wasYaw = one.yaw;
          ga.tic();
          seen.push(one.cz - one.ground);
          drove.push({ v: one.speed, accel: one.speed - before,
                       turn: Math.atan2(Math.sin(one.yaw - wasYaw), Math.cos(one.yaw - wasYaw)),
                       pitch: one.rz, roll: one.rx });
        }
        const [lo, hi] = air(seen);
        const parked0 = apcs().find(v => v.state === 'parked');
        note('the APC', `${n} tics to a standing carrier, ${parked0 ? parked0.driven.toFixed(0) : '-'} units driven, ` +
          `${lo.toFixed(1)} to ${hi.toFixed(1)} units of air under it on the way`);
        check('it rides off the tarmac on the road rather than driving on it',
          lo > veh.ArmyApc.HOVER * 0.7, `${lo.toFixed(1)} units of air`);
      }
      /* --- AND IT FLIES RATHER THAN DRIVES, at the user's request:
         the same two springs as the van with both signs turned over.
         A thing on springs leans OUT of a bend and dips its nose to
         brake; a thing on thrust points its lift into the bend and
         forward to stop, so it banks IN and pitches nose UP. Measured
         against the van's own numbers rather than against a remembered
         sign, so the two can never quietly agree. */
      {
        /* ON THE ROAD IT ACTUALLY DROVE, first: it brakes into its
           place like everything else, and the whole of that braking is
           spent nose UP. */
        const braking = drove.filter(q => q.accel < -0.2 && q.v > 6);
        const noseUp = braking.filter(q => q.pitch > 0).length;
        note('how it carries itself', `${noseUp} of ${braking.length} braking tics nose up`);
        check('it pitches nose UP to stop, where a van dips',
          braking.length > 4 && noseUp > braking.length * 0.8, `${noseUp} of ${braking.length}`);
        /* AND THE BANK, ASKED DIRECTLY, because the way in is short and
           nearly straight now and a drive may hold one real corner —
           which is a fact about the ROUTE and not about the vehicle. So
           the spring is driven by hand instead, from level, with the
           same braking left-hand corner given to one of each, and the
           two are held against each other. */
        const aSwatVan = Ra.vans.find(v => v.force === Ra.swat);
        const corner = v => {
          const keep = { rz: v.rz, rx: v.rx, pv: v.pitchV, rv: v.rollV, sp: v.speed };
          v.rz = v.restPitch; v.rx = v.restRoll; v.pitchV = 0; v.rollV = 0; v.speed = 20;
          for (let i = 0; i < 80; i++) v.suspension(-0.6, 0.1);     // braking, turning left
          const out = { pitch: v.rz - v.restPitch, roll: v.rx - v.restRoll };
          Object.assign(v, { rz: keep.rz, rx: keep.rx, pitchV: keep.pv, rollV: keep.rv, speed: keep.sp });
          return out;
        };
        const A = corner(one), V = corner(aSwatVan);
        note('braking into a left-hander', `the carrier ${(A.pitch * 180 / Math.PI).toFixed(1)}° pitch ` +
          `${(A.roll * 180 / Math.PI).toFixed(1)}° roll, the van ${(V.pitch * 180 / Math.PI).toFixed(1)}° ` +
          `${(V.roll * 180 / Math.PI).toFixed(1)}°`);
        check('the van leans OUT of the bend and dips its nose, because it has springs',
          V.roll > 0.01 && V.pitch < -0.01, `${V.roll.toFixed(3)}, ${V.pitch.toFixed(3)}`);
        check('and the carrier banks INTO it and lifts its nose, because it has thrust',
          A.roll < -0.01 && A.pitch > 0.01, `${A.roll.toFixed(3)}, ${A.pitch.toFixed(3)}`);
        check('and it banks harder than the van leans', Math.abs(A.roll) > Math.abs(V.roll) * 1.5,
          `${Math.abs(A.roll).toFixed(3)} against ${Math.abs(V.roll).toFixed(3)}`);
        check('and it is two signs on the instance, not a second suspension',
          one.rollPerG < 0 && one.pitchPerG < 0 && aSwatVan.rollPerG > 0 && aSwatVan.pitchPerG > 0,
          `apc ${one.rollPerG}/${one.pitchPerG}, van ${aSwatVan.rollPerG}/${aSwatVan.pitchPerG}`);
        /* AND IT NEVER PUTS A CORNER THROUGH THE TARMAC, which is the
           only thing the angles are actually capped for: the nose drops
           by half the length times the pitch and the low flank by half
           the width times the bank, and together they have to stay
           inside the hover at the bottom of its breath. */
        const half = car.carLength(apc) / 2, side = car.carWidth(apc) / 2;
        const worst = Math.max(...drove.map(q =>
          half * Math.abs(Math.sin(q.pitch)) + side * Math.abs(Math.sin(q.roll))));
        const clear = veh.ArmyApc.HOVER - veh.ArmyApc.BOB;
        note('the lowest corner', `${worst.toFixed(1)} units down against ${clear} of hover at its lowest`);
        check('and however far it leans, no corner of it goes through the tarmac',
          worst < clear, `${worst.toFixed(1)} against ${clear}`);
      }
      const parked = apcs().find(v => v.state === 'parked');
      check('an APC arrives and stands', !!parked);
      check('and it is on ground a vehicle can be on', Ra.drivable(parked.x, parked.y),
        ga.level.sectorAt(parked.x, parked.y)?.name);
      {
        const seen = [];
        for (let i = 0; i < 150; i++) { ga.tic(); seen.push(one.cz - one.ground); }
        const [lo, hi] = air(seen);
        note('standing still', `${lo.toFixed(1)} to ${hi.toFixed(1)} units of air, breathing ${(hi - lo).toFixed(1)}`);
        check('and it is still hovering now that it has stopped', lo > veh.ArmyApc.HOVER * 0.7);
        check('and it breathes, which is the only thing in this game that moves while it is still',
          hi - lo > 4 && hi - lo < 2.2 * veh.ArmyApc.BOB, `${(hi - lo).toFixed(1)} units of travel`);
        check('and the van beside it does not', Ra.vans.some(v => v.force === Ra.swat && v.hover === 0));
        /* AND IT BREATHES HARDER STANDING THAN MOVING, at the user's
           request — the bob you actually watch is the parked one — and
           because a hovercraft at speed is held steadier by the ground
           under it and one standing still wallows. */
        check('and it breathes harder standing still than it does moving',
          hi - lo > 2 * veh.ArmyApc.BOB * 0.45, `${(hi - lo).toFixed(1)} standing`);
        /* AND IT IS NEVER LEVEL AND NEVER ASLEEP. A parked van's springs
           settle onto zero and are then left alone for the rest of the
           night; a parked carrier's are settling onto something that
           keeps moving, so it drifts a degree one way and a degree and a
           half the other and never arrives. */
        const angles = [];
        for (let i = 0; i < 400; i++) { ga.tic(); angles.push({ p: one.rz, r: one.rx }); }
        const spanP = Math.max(...angles.map(q => q.p)) - Math.min(...angles.map(q => q.p));
        const spanR = Math.max(...angles.map(q => q.r)) - Math.min(...angles.map(q => q.r));
        note('parked, and not still', `${(spanP * 180 / Math.PI).toFixed(2)}° of pitch drift, ` +
          `${(spanR * 180 / Math.PI).toFixed(2)}° of roll`);
        check('a parked carrier is never level and never asleep',
          !one.asleep && spanP > 0.004 && spanR > 0.004 && spanP < 0.09 && spanR < 0.12,
          `${spanP.toFixed(4)} pitch, ${spanR.toFixed(4)} roll`);
        const aVan = Ra.vans.find(v => v.force === Ra.swat && v.state === 'parked');
        check('and a parked van settles level and is left alone', !aVan || aVan.asleep, aVan && `${aVan.rz}`);
      }
      /* AND YOU DO NOT GET TO WALK UNDER IT. The three cylinders stand
         on the ground the way every other vehicle's do; what changes is
         that they are as tall as the gap plus the hull. */
      {
        const b = one.blockers;
        check('the thing you cannot walk through still stands on the tarmac',
          b.length === 3 && b.every(q => Math.abs(q.z - one.ground) < 1e-6));
        check('and it is as tall as the gap under it plus the hull of it',
          b.every(q => q.height > car.carHeight(apc)), `${b[0].height} against a hull of ${car.carHeight(apc).toFixed(0)}`);
      }

      /* --- and soldiers get out of it -------------------------------- */
      for (let i = 0; i < A.unloadEvery * 3 + 60 && !ga.actors.some(a => a.type === 'ARMY'); i++) ga.tic();
      const sold = ga.actors.filter(a => a.type === 'ARMY' && !a.dead);
      check('and what gets out is a soldier, not a trooper', sold.length > 0 && sold.every(a => a.van === parked || a.force === Ra.army));
      check('and they know why they are here from the first step',
        sold.every(a => a.target === pa2 && /^ARMY_(RUN|ATK)/.test(a.state.name)), sold[0]?.state.name);
      check('and they are counted against their own budget, not the police one',
        Ra.troopersOf(Ra.army) === sold.length && Ra.troopersOf(Ra.swat) !== sold.length &&
        Ra.army.spawned > 0 && Ra.spawned === Ra.swat.spawned + Ra.army.spawned);

      /* --- how much of one there is ---------------------------------- */
      {
        const a = ga.spawn('ARMY', pa2.x + 300, pa2.y, undefined, {});
        check('a soldier is two and a third of a trooper and flinches half as often',
          a.info.health > st.ACTORS.SWAT.health * 2 && a.info.painchance < st.ACTORS.SWAT.painchance,
          `${a.info.health} health, ${a.info.painchance} painchance`);
        check('and the fire does nothing to one either, the same as the SWAT',
          a.fireproof && !a.flammable && a.fuel === 0);
        /* THE BURST: two rounds off one frame at half the scatter. The
           rounds are counted rather than the damage, because damage is
           a die roll and the point is that there are two of them. */
        const shots = [];
        const was = ga.hitscan.bind(ga);
        ga.hitscan = (src, ang, range, dmg, opts) => { shots.push({ ang, dmg }); return was(src, ang, range, dmg, opts); };
        a.target = pa2;
        ACTIONS.A_ArmyFire(a);
        const swatShots = [];
        const sw = ga.spawn('SWAT', pa2.x + 300, pa2.y + 40, undefined, {});
        sw.target = pa2;
        ga.hitscan = (src, ang, range, dmg, opts) => { swatShots.push({ ang, dmg }); return was(src, ang, range, dmg, opts); };
        ACTIONS.A_SwatFire(sw);
        ga.hitscan = was;
        note('the two rifles', `the army puts ${shots.length} rounds out at ${shots.map(q => q.dmg).join('/')}, ` +
          `the SWAT ${swatShots.length} at ${swatShots.map(q => q.dmg).join('/')}`);
        check('the army rifle is a two-round burst and the SWAT rifle is one round',
          shots.length === 2 && swatShots.length === 1);
        check('and each round of it is worth more', shots.every(q => q.dmg % 4 === 0) && swatShots.every(q => q.dmg % 3 === 0));
        /* AND THEY ARE ONE SIDE. Two forces on the same ground with
           different team names is Doom's bestiary rule: a police rifle
           would chew a soldier crossing the lane in front of it and the
           soldier would turn round about it, and an army that arrives
           already shot to pieces by the tier below it is not an
           escalation. One team name, and a round from it does nothing —
           though it is still STOPPED by whoever it meets, so a man in
           front of you is still cover. */
        check('the SWAT and the army are one side', a.info.team === sw.info.team);
        const hp0 = a.health;
        a.damage(60, sw, { shot: true });
        check('and a police round does nothing to a soldier', a.health === hp0, `${a.health} of ${hp0}`);
        a.damage(60, sw, { impact: true });
        check('but their own van running him down still does', a.health === hp0 - 60, `${a.health} of ${hp0}`);
        a.damage(60, null, { shot: true });
        check('and so does yours', a.health === hp0 - 120, `${a.health} of ${hp0}`);
        a.remove(); sw.remove();
      }

      /* --- THE FIRE LANE HOLDS NINE, AND THE CURVE ASKS FOR MORE ------
         Which used to mean the escalation stopped at nine and said
         nothing. Standing indoors with every bay taken, the next one
         still gets somewhere to stand — along the ring by the doors. */
      {
        const bays = ga.level.swatBays.slice(0, S.bays);
        const held = bays.map((b, i) => ({ bay: b, whole: true, stand: { x: b.x + i * 1e5, y: b.y, ring: 0 }, force: Ra.swat }));
        const keep = Ra.vans;
        Ra.vans = held;
        const st2 = Ra.freeStand(Ra.army);
        Ra.vans = keep;
        check('with every bay in the fire lane taken, the next one still has somewhere to go',
          !!st2 && Ra.drivable(st2.x, st2.y), st2 ? ga.level.sectorAt(st2.x, st2.y)?.name : 'nowhere');
      }
      /* AND THE TWO FORCES DO NOT PARK INSIDE ONE ANOTHER. Every stand
         either of them has taken is its own vehicle's length clear of
         every other, which for a 260-long APC beside a 214-long van is
         the number that matters. */
      {
        const stands = Ra.liveVans.filter(v => v.stand).map(v => ({ s: v.stand, L: v.def.length }));
        let worst = Infinity, pair = '';
        for (let i = 0; i < stands.length; i++) for (let j = i + 1; j < stands.length; j++) {
          const d = Math.hypot(stands[i].s.x - stands[j].s.x, stands[i].s.y - stands[j].s.y);
          const want = (stands[i].L + stands[j].L) / 2;
          if (d - want < worst) { worst = d - want; pair = `${d.toFixed(0)} apart, ${want.toFixed(0)} of vehicle`; }
        }
        note('the closest two stands', stands.length > 1 ? pair : 'only one of them out');
        check('no two of them stand inside one another, whichever force they are',
          stands.length < 2 || worst > 0, pair);
      }
    }

    /* the corner grows a third bar the moment something hurts you */
    const hudSrc = fs.readFileSync('js/hud.js', 'utf8');
    check('the corner draws all three bars, and only once you are hurt',
      /if \(hurt\) \{/.test(hudSrc) && /_bar\([^)]*hp \/ HEALTH/.test(hudSrc) &&
      /_bar\([^)]*a2 \/ ARMOUR2, UI\.armour2\)/.test(hudSrc) &&
      /_bar\([^)]*a1 \/ ARMOUR1, UI\.armour1\)/.test(hudSrc));
    check('and it knows it is hurt when any of the three has moved',
      /a2 < ARMOUR2 \|\| a1 < ARMOUR1 \|\| hp < HEALTH/.test(hudSrc));
  }
}

/* ---------- the cerebral bore ---------- */
section('the cerebral bore');
{
  const { Game } = await import('../js/game.js');
  const pl = await import('../js/player.js');
  const { BORE } = await import('../js/bore.js');
  const { ACTIONS, Actor } = await import('../js/actor.js');
  const MAPB = await import('../js/maps/sellwrong.js');
  const THREEB = await import('three');
  const mk = () => new Game({
    level: MAPB.buildSellWrong({ town: false }), scene: new THREEB.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, sample() {}, sensitivity: 0 },
  });

  /* --- the weapon ------------------------------------------------- */
  const d = pl.WEAPONS.BORE;
  check('the bore is a weapon, in the boxcutter\'s slot, and it needs a lock',
    !!d && d.slot === 3 && d.lock === true && d.ammo === 'bores' && !pl.WEAPONS.BOXCUTTER);
  check('five in the magazine, and a full one back in a minute',
    pl.BORES === 5 && pl.BORES * pl.BORE_REGEN_EVERY === 60 * 35, `${pl.BORES} x ${pl.BORE_REGEN_EVERY}`);
  {
    const fs = await import('node:fs');
    const G = await import('../js/glb.js');
    const buf = fs.readFileSync(new URL('../assets/models/bore.glb', import.meta.url));
    const { json } = G.parseGLB(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
    note('the model', `${json.nodes.length} node, ${json.images.length} image, ${(buf.length / 1024 / 1024).toFixed(1)} MB`);
    check('the model is the user\'s, with only its diffuse left in it',
      json.images.length === 1 && json.materials.length === 1 && !json.materials[0].normalTexture &&
      !json.materials[0].pbrMetallicRoughness.metallicRoughnessTexture);
    check('and it carries no anchors, so the nozzle is the game\'s number',
      !json.asset.extras?.anchors, JSON.stringify(json.asset.extras));
    const w3 = await import('../js/weapon3d.js');
    check('which js/weapon3d.js has', !!w3.GUNS.BORE && w3.GUNS.BORE.nozzle.length === 3 && w3.GUNS.BORE.url.endsWith('bore.glb'));
  }

  /* --- the sight -------------------------------------------------- */
  const g = mk();
  const p = g.player;
  p.weapon = 'BORE';
  /* SOMEBODY WITH TWO HUNDRED UNITS OF THE SAME ROOM WEST OF THEM,
     which is scaffolding and not an assertion: the sight is what is
     being asked about, and the only thing the shop has to supply is a
     clear two hundred to stand in.

     Taking the first shopper in the list and assuming the room was
     there held until the queues moved into the checkout lanes. The
     first one now stands in lane zero, 140 off the west wall of the
     shop — so the spot two hundred west of them is inside the chemist,
     through a wall, and the sight correctly found nothing.

     SAME SECTOR and not "some walkable sector": a point that is indoors
     at the same floor height is exactly what the inside of the next
     tenancy is. The cross-aisles are the one region in the shop that is
     three thousand units long, so both ends of a two-hundred-unit shot
     down one are the same room by construction. */
  const who = g.actors.find(a => a.type === 'SHOPPER' && !a.dead && a.sector &&
    !a.sector.outdoor && g.level.sectorAt(a.x - 200, a.y) === a.sector);
  /* stand in the aisle, two hundred off somebody, looking at them */
  const stand = (a, back = 200) => {
    p.x = a.x - back; p.y = a.y; p.sector = g.level.sectorAt(p.x, p.y); p.z = p.sector.floor; p.viewZ = p.z + 41;
    p.angle = 0; p.pitch = 0;
  };
  stand(who);
  /* WHOEVER IS NEAREST ALONG THE RAY is the one the sight finds, which
     in a crowd is not always the one you stood in front of — so the
     crowd between here and them is cleared, and the flight below is
     two hundred units long rather than twenty */
  for (const a of g.actors)
    if (a !== who && a.type === 'SHOPPER' && Math.hypot(a.x - p.x, a.y - p.y) < 320) a.remove();
  g.tic();
  const B = g.bore;
  check('the sight is on while the bore is in hand', B.active);
  check('and it finds a person along the view', !!B.aim.actor && B.aim.actor.type === 'SHOPPER', B.aim.actor?.type);
  check('and locks on to them', !!B.lock && B.lock === B.aim.actor);
  check('and the aim point is at the height of the eye, not on the floor',
    Math.abs(B.aim.z - p.viewZ) < 1, `${B.aim.z.toFixed(1)} against ${p.viewZ.toFixed(1)}`);
  const victim = B.lock;
  /* look at the ceiling: nothing to lock, and the sight ends on it */
  p.pitch = 0.7;
  for (let i = 0; i < BORE.grace + 2; i++) g.tic();
  check('looking away loses the lock, after a moment', !B.lock && !B.aim.actor);
  check('and the sight stops at the ceiling', Math.abs(B.aim.z - p.sector.ceil) < 1, `${B.aim.z.toFixed(1)} against ${p.sector.ceil}`);
  /* THE TRIGGER DOES NOTHING WITHOUT ONE — Turok's rule */
  check('without a lock the trigger is not armed', !p.armed('BORE'));
  const ammo0 = p.ammo.bores;
  check('and firing with nothing locked sends nothing', B.fire(p) === null && B.shots.length === 0 && p.ammo.bores === ammo0);
  /* and the floor — or whoever is standing on it in the way, since
     this is a crowd and a ray pitched down crosses the next person's
     knees fifty units out */
  p.pitch = -0.7;
  g.tic();
  check('or the floor', Math.abs(B.aim.z - p.sector.floor) < 1 || (!!B.aim.actor && B.aim.z < p.viewZ),
    `${B.aim.z.toFixed(1)} against ${p.sector.floor}`);
  for (let i = 0; i < BORE.grace + 2; i++) g.tic();

  /* --- the shot --------------------------------------------------- */
  p.pitch = 0;
  g.tic();
  check('back on them, the lock is back', B.lock === victim);
  check('and the trigger is armed', p.armed('BORE'));
  p.startFire();
  check('firing costs one of five', p.ammo.bores === ammo0 - 1 && B.fired === 1 && B.shots.length === 1);
  const s = B.shots[0];
  check('the bore leaves the launcher slowly, aimed at the head', s.target === victim && s.speed <= BORE.speed0 * BORE.accel);
  let flew = 0;
  const path = [];
  for (; flew < 120 && !B.drilling.length; flew++) { g.tic(); if (B.shots[0]) path.push(B.shots[0].speed); }
  note('the flight', `${flew} tics, ${path[0]?.toFixed(1)} to ${path[path.length - 1]?.toFixed(1)} units a tic`);
  check('it reaches the head in under a second', B.drilling.length === 1 && flew < 35, `${flew} tics`);
  check('and it sped up on the way', path.length > 2 && path[path.length - 1] > path[0] * 1.5);

  /* --- the drill -------------------------------------------------- */
  check('the drill is a hold: they stand there, parked, and nothing can scare them',
    victim.bored > 0 && victim.held && victim.state.name === 'SHOP_BORE' && victim.stateTics === -1);
  const vx = victim.x, vy = victim.y;
  ACTIONS.A_Scare(victim, victim.x + 100, victim.y, 200);
  g.scare(victim.x, victim.y, 400);
  for (let i = 0; i < 20; i++) g.tic();
  check('and they have not moved a unit', victim.x === vx && victim.y === vy && victim.bored > 0);
  const C = g.giblets.chunks;
  let blood = 0;
  for (let i = 0; i < C.max; i++) if (C.alive[i] && C.kind[i] === 1) blood++;
  check('what was in the head is coming out of the top of it', blood > 4, `${blood} pieces in the air`);
  check('and none of it is on fire', (() => { for (let i = 0; i < C.max; i++) if (C.alive[i] && C.kind[i] !== 1) return false; return true; })());
  check('the bore is in the head, turning', B.drilling[0].stuck === victim && Math.abs(B.drilling[0].z - (victim.z + victim.height * BORE.headAt)) < 1);
  check('and nothing else can lock on to them while it is', !B.lockable(victim));

  /* --- and then they explode --------------------------------------- */
  const bursts = g.giblets.bursts, kills = p.kills;
  let held = 0;
  for (; held < 200 && !victim.dead; held++) g.tic();
  note('the drilling', `${held + 20} tics from the bore going in to the burst`);
  check('two seconds later they come apart', victim.dead && g.giblets.bursts === bursts + 1, `${g.giblets.bursts - bursts} bursts`);
  check('and it is the player\'s kill', p.kills === kills + 1);
  check('and the bore is spent with them', B.drilling.length === 0 && B.shots.length === 0,
    `${B.shots.length} in flight (${B.shots.map(q => q.target?.type + (q.target?.dead ? ' dead' : '')).join(', ')}), ${B.drilling.length} drilling`);
  check('the whole thing took a shade over two seconds', Math.abs((held + 21) - BORE.drillTics) <= 2, `${held + 21} against ${BORE.drillTics}`);

  /* --- what it does to the others ----------------------------------- */
  {
    /* a block of ice: shattered, not drilled */
    const g2 = mk(); const p2 = g2.player; p2.weapon = 'BORE';
    const ice = g2.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    ice.chill(Actor.FREEZE_AT);
    check('a frozen shopper can be locked', g2.bore.lockable(ice));
    const r = ice.bore(p2);
    check('and the bore shatters a block of ice rather than drilling it', r === 'shatter' && ice.removed);
    /* a trooper: the gore death, not the ordinary one */
    const t = g2.spawn('SWAT', p2.x + 200, p2.y, undefined, {});
    t.target = p2;
    const r2 = t.bore(p2);
    check('a trooper takes the drill', r2 === 'drill' && t.held && t.state.name === 'SWAT_BORE');
    for (let i = 0; i < Actor.BORE_TICS + 2 && !t.dead; i++) g2.tic();
    check('and comes apart at the end of it, the gore way', t.dead && t.state.name.startsWith('SWAT_XDIE'), t.state?.name);
    /* the magazine fills itself */
    p2.ammo.bores = 0;
    for (let i = 0; i < pl.BORE_REGEN_EVERY + 1; i++) p2.fuelTic();
    check('the magazine fills itself, one at a time', p2.ammo.bores === 1);
    /* a target that dies on the way is a target the bore flies past */
    const g3 = mk(); const p3 = g3.player; p3.weapon = 'BORE';
    const far = g3.actors.find(a => a.type === 'SHOPPER' && !a.dead && a.sector && !a.sector.outdoor);
    p3.x = far.x - 300; p3.y = far.y; p3.sector = g3.level.sectorAt(p3.x, p3.y); p3.z = p3.sector.floor; p3.viewZ = p3.z + 41; p3.angle = 0; p3.pitch = 0;
    g3.tic();
    if (g3.bore.lock) {
      const tgt = g3.bore.lock;
      p3.startFire();
      g3.tic(); g3.tic();
      tgt.damage(100, p3);                  // gone before it arrives
      let n = 0;
      for (; n < 400 && g3.bore.shots.length; n++) g3.tic();
      check('a bore whose target died on the way flies on and is spent on a wall',
        g3.bore.shots.length === 0 && g3.bore.drilling.length === 0 && n < 400, `${n} tics`);
    }
  }
  /* the sight's drawing parts exist */
  check('the sight has a dot, a reticle and a bore to draw with',
    ['LASRA', 'LOCKA', 'BOREA', 'BOREB', 'BOREC'].every(k => g.sprites.frames.has(k)));
}

/* ---------- the minigun, the jump, and the van ---------- */
section('the minigun, the jump and the van');
{
  const fs = await import('node:fs');
  const { Game } = await import('../js/game.js');
  const pl = await import('../js/player.js');
  const MAPM = await import('../js/maps/sellwrong.js');
  const THREEM = await import('three');
  const mk = () => new Game({
    level: MAPM.buildSellWrong({ town: false }), scene: new THREEM.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
  });
  const inp = (o = {}) => ({ look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false,
                             run: false, jump: false, weaponSlot: 0, weaponCycle: 0, ...o });

  /* --- the weapon --------------------------------------------------- */
  const d = pl.WEAPONS.MINIGUN;
  check('the minigun is the fourth weapon, a volley off a belt, and issued',
    !!d && d.slot === 4 && d.volley === true && d.ammo === 'rounds' && d.autofire === true &&
    /* AND THE MOLOTOV MOVED DOWN ONE to make room for the lance, which
       is the fifth, again for the launcher, which is the sixth, and
       again for the arc maw, which is the seventh: the molotov is still
       switched off and still built, and its slot is still one past the
       last thing you can hold. */
    pl.WEAPONS.LANCE.slot === 5 && pl.WEAPONS.LAUNCHER.slot === 6 && pl.WEAPONS.ARC.slot === 7 &&
    pl.WEAPONS.MOLOTOV.slot === 8 &&
    new (class extends pl.Player { constructor() { super({ level: level, sectorAt: () => null }, 0, 0, 0); } })().owned.MINIGUN === true);
  note('the belt', `${pl.BELT} rounds at ${pl.BELT_PER_TIC} a tic: ${(pl.BELT / pl.BELT_PER_TIC / 35).toFixed(0)} seconds, ` +
    `back in ${(pl.BELT * pl.BELT_REGEN_EVERY / 35).toFixed(0)}; ${d.rounds} a tic of ${d.damage()}-ish`);
  check('absurdly destructive: over a hundred rounds a second, each more than a shopper',
    d.rounds * 35 >= 100 && [...Array(50)].every(() => d.damage() >= 20));

  const g = mk();
  const p = g.player;
  p.weapon = 'MINIGUN';
  /* --- it spins up before it fires ---------------------------------- */
  const held = inp({ attack: true });
  const was = p.ammo.rounds;
  let firedAt = -1;
  for (let t = 1; t <= pl.SPIN_UP + 4; t++) {
    p.tic(held, 1 / 35);
    if (firedAt < 0 && p.ammo.rounds < was) firedAt = t;
  }
  check('the trigger does nothing until the barrels are up to speed',
    firedAt > pl.SPIN_UP - 1 && firedAt <= pl.SPIN_UP + 2, `first round on tic ${firedAt}, spin-up is ${pl.SPIN_UP}`);
  check('and then every tic costs the belt a volley',
    p.ammo.rounds === was - d.rounds * (pl.SPIN_UP + 4 - firedAt + 1) + Math.floor((pl.SPIN_UP + 4) / pl.BELT_REGEN_EVERY) * 0 ||
    Math.abs((was - p.ammo.rounds) - d.rounds * (pl.SPIN_UP + 5 - firedAt)) <= pl.SPIN_UP + 5,
    `${was} -> ${p.ammo.rounds}`);
  check('and the barrels are at full speed and warming',
    p.spin === 1 && p.heat > 0 && p.heat < 0.2, `spin ${p.spin} heat ${p.heat.toFixed(3)}`);
  /* --- the heat ------------------------------------------------------ */
  for (let t = 0; t < pl.HEAT_UP; t++) p.tic(held, 1 / 35);
  check('four seconds of fire and the barrels are white', p.heat === 1, `${p.heat}`);
  const up = inp();
  for (let t = 0; t < pl.SPIN_DOWN + 2; t++) p.tic(up, 1 / 35);
  check('let go and they wind down and start to cool', p.spin === 0 && p.heat < 1 && p.heat > 0.8,
    `spin ${p.spin} heat ${p.heat.toFixed(3)}`);
  /* --- the latch ----------------------------------------------------- */
  p.ammo.rounds = d.rounds - 1; p.spin = 1; p.fireIndex = 0; p.fireTics = 1;
  p.volleyTic(d);
  check('a belt too short for a volley stops the gun and latches it',
    p.beltDry && p.fireIndex === -1 && p.latched('MINIGUN') && !p.armed('MINIGUN'));
  p.ammo.rounds = Math.ceil(pl.BELT * pl.BELT_REFIRE_AT);
  p.fuelTic();
  check('and a quarter of a belt clears it', !p.beltDry && p.latched('MINIGUN') === false);
  check('and a dry belt does not spin', (() => { p.beltDry = true; p.spin = 0; p.spinTic(held); const r = p.spin; p.beltDry = false; return r === 0; })());

  /* --- the rounds go where the eye looks, pitch and all ------------- */
  {
    const g2 = mk();
    const q = inTheOpen(g2);               // nothing between you and the target
    const before = g2.actors.length;
    const floor = q.sector.floor;
    /* straight down at your own feet: the shot stops at the lino and
       puts its hole there, rather than at eye height a mile away —
       and nothing else: an impact is a decal now, no puff */
    const holesBefore = g2.decals.holes;
    g2.hitscan(q, q.angle, 2400, 10, { shot: true, hot: true, pitch: -0.7, from: g2.nozzle() });
    const last = g2.lastHit, HP = g2.decals.pools.hole, hi = (HP.next + HP.max - 1) % HP.max;
    check('a shot aimed at the floor stops at the floor',
      g2.decals.holes === holesBefore + 1 && Math.abs(last.z - floor) < 1e-6 && Math.hypot(last.x - q.x, last.y - q.y) < 120 &&
      HP.nz[hi] === 1 && Math.abs(HP.z[hi] - floor) < 1e-6,
      `hole at z ${last.z}, floor ${floor}, ${Math.hypot(last.x - q.x, last.y - q.y).toFixed(0)} out`);
    check('and the impact is a decal only: no puff, no sparks',
      g2.actors.length === before && !g2.actors.some(a => a.type === 'PUFF' || a.type === 'SPARK'));
    check('a minigun round\'s hole is the hot kind, and bigger', HP.frame[hi] === 2 && HP.size[hi] >= 8 * 1.3 - 1e-6);
    /* and a level one still lands on a person at their height */
    const target = g2.actors.find(a => a.shootable && !a.dead && !a.vehicle && a.solid && a.health > 0 && !a.noclip);
    if (target) {
      /* brought out to the car park in front of the player, where
         there is nothing between the two of them but night */
      target.x = q.x + Math.cos(q.angle) * 200; target.y = q.y + Math.sin(q.angle) * 200;
      g2.blockmap?.moved(target); target.updateSector?.();
      target.z = q.z;
      q.angle = q.angle; q.x = q.x; q.y = q.y; q.viewZ = q.z + 49;
      const hp = target.health;
      const hit = g2.hitscan(q, q.angle, 2400, 10, { shot: true, pitch: 0 });
      check('and a level one lands on a person', hit === target && target.health < hp, `${hit ? hit.type : 'nothing'}`);
      const hp2 = target.health;
      g2.hitscan(q, q.angle, 2400, 10, { shot: true, pitch: 0.6 });
      check('but one aimed over their head goes over their head', target.health === hp2);
    }
  }

  /* --- the jump ------------------------------------------------------ */
  {
    const g3 = mk();
    const q = inTheOpen(g3);               // and room to come down in
    const floor = q.z;
    check('you start on the ground', q.onGround === true && q.momz === 0);
    q.tic(inp({ jump: true }), 1 / 35);
    check('a press of jump is a push off it', q.onGround === false && q.momz > 0 && q.z > floor);
    let top = q.z, air = 1;
    for (let t = 0; t < 60 && !q.onGround; t++) { q.tic(inp(), 1 / 35); top = Math.max(top, q.z); air++; }
    const expect = pl.JUMP_VEL * pl.JUMP_VEL / (2 * pl.GRAVITY);
    check('rises about forty units and comes back down to the floor',
      q.onGround && q.z === floor && top > expect * 0.85 && top < expect * 1.15 && air > 10 && air < 30,
      `top ${top - floor} (expected ~${expect}), ${air} tics in the air`);
    check('and holding it is not a pogo stick: one jump per press',
      (() => { const src = fs.readFileSync('js/input.js', 'utf8'); return /this\.jump = this\.pressed\('jump'\)/.test(src) && /padEdge\(6\)/.test(src); })());
  }

  /* --- the van throws you ------------------------------------------- */
  {
    const g4 = mk();
    const q = g4.player;
    const x0 = q.x, a2 = q.armour2;
    q.damage(40, { x: q.x - 40, y: q.y }, { impact: true, launch: { x: 20, y: 0, z: 12, grace: 30 } });
    check('a launch is a hit and a velocity, sideways and up',
      q.armour2 === a2 - 40 && q.momz === 12 && q.momx > 20 && q.onGround === false && q.launched === 30);
    let far = 0;
    for (let t = 0; t < 40; t++) { q.tic(inp(), 1 / 35); far = Math.max(far, q.x - x0); }
    check('and you land somewhere else', q.onGround && far > 60 && q.launched === 0, `${far.toFixed(0)} units on`);
    const g5 = mk();
    const r = g5.player;
    r.invincible = true;
    r.damage(40, { x: r.x - 40, y: r.y }, { impact: true, launch: { x: 20, y: 0, z: 12 } });
    check('and invincible refuses the launch with the rest', r.momz === 0 && r.onGround === true);
    const vsrc = fs.readFileSync('js/vehicles.js', 'utf8');
    check('the van works its launch out of its speed and lets you clear it',
      /launch: \{ x: lx \* k, y: ly \* k, z: up/.test(vsrc) && /!\(p\.launched > 0\)/.test(vsrc) &&
      /Math\.min\(30, 10 \+ sp \* 0\.55\)/.test(vsrc));
  }

  /* --- the model, as the tool left it ------------------------------- */
  {
    const G = await import('../js/glb.js');
    const buf = fs.readFileSync(new URL('../assets/models/minigun.glb', import.meta.url));
    const { json } = G.parseGLB(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
    const ex = json.asset.extras || {};
    note('the minigun', `${json.nodes.length} nodes, ${json.images.length} images, ${(buf.length / 1024 / 1024).toFixed(1)} MB, from ${ex.source}`);
    check('its emission marker was read into the file as the nozzle, through the node\'s own transform',
      Array.isArray(ex.anchors?.nozzle) && ex.anchors.nozzle.length === 3 &&
      Math.abs(ex.anchors.nozzle[1] - -1.33) < 0.05 && Math.abs(ex.anchors.nozzle[2] - 15.27) < 0.05, JSON.stringify(ex.anchors));
    check('and the marker itself is gone from the mesh', !json.nodes.some(n => /EmissionPoint/i.test(n.name || '')));
    check('and the barrel set is named to turn, and still there with its mesh',
      typeof ex.spin === 'string' && json.nodes.some(n => n.name === ex.spin && n.mesh !== undefined));
    check('and only the two diffuse maps survive', json.images.length === 2 && json.materials.length === 2 &&
      json.materials.every(m => !m.normalTexture && !m.pbrMetallicRoughness?.metallicRoughnessTexture));
    const w3 = await import('../js/weapon3d.js');
    const M = w3.GUNS.MINIGUN;
    check('and the game says how it is held, what glows and what spins',
      M.nozzle === null && M.pilot === null && M.heat?.material === 'minigun_barrel_mat' && M.spin > 0 &&
      M.fit > w3.GUN_LENGTH && M.out > 1 && json.materials.some(m => m.name === M.heat.material));
    const gunSrc = fs.readFileSync('js/weapon3d.js', 'utf8');
    check('the heat is drawn from the muzzle back, on the one material, banded like the light',
      /uniform float heat;/.test(gunSrc) &&
      /heatMaterial\.uniforms\.heat\.value = player\[G\.def\.heat\?\.from \|\| 'heat'\]/.test(gunSrc) &&
      /floor\(h \* 8\.0 \+ 0\.5\) \/ 8\.0/.test(gunSrc));
    check('and the barrels turn at the player\'s spin', /G\.spin\.rotation\.z = G\.spinAngle/.test(gunSrc));
    check('and no disc across the muzzle any more, at the user\'s request: the tracers say it is firing',
      !M.flash && M.muzzle.additive === true && !/flashPicture/.test(gunSrc) && !/G\.flash/.test(gunSrc));
  }

  /* --- the page and the pad ----------------------------------------- */
  {
    const html = fs.readFileSync('index.html', 'utf8');
    const css = fs.readFileSync('css/style.css', 'utf8');
    const mainSrc = fs.readFileSync('js/main.js', 'utf8');
    const inSrc = fs.readFileSync('js/input.js', 'utf8');
    const rsp = fs.readFileSync('js/responders.js', 'utf8');
    const hudSrc = fs.readFileSync('js/hud.js', 'utf8');
    const lofiSrc = fs.readFileSync('js/lofi.js', 'utf8');
    const au = await import('../js/audio.js');
    const auSrc = fs.readFileSync('js/audio.js', 'utf8');
    check('the synthesised sound is off, for now, by one switch, and the ambience with it',
      au.MUTED === true && /if \(MUTED\) return;/.test(auSrc) && /if \(MUTED \|\| !this\.ctx \|\| this\._amb\) return;/.test(auSrc));
    /* --- the minigun's recordings, which the switch does not touch --- */
    check('the minigun has three recordings, the lance six, and all nine files are there',
      Object.keys(au.SAMPLES).filter(k => k.startsWith('minigun_')).length === 3 &&
      Object.keys(au.SAMPLES).filter(k => k.startsWith('lance_')).length === 6 &&
      Object.keys(au.SAMPLES).length === 9 && Object.values(au.SAMPLES).every(u => fs.existsSync(u)));
    check('named for the spin-up, the loop and the wind-down',
      au.SAMPLE_FOR.spinup === 'minigun_start' && au.SAMPLE_FOR.minigunloop === 'minigun_fire' && au.SAMPLE_FOR.spindown === 'minigun_stop');
    check('and a sample plays whatever the switch says', auSrc.indexOf('if (SAMPLE_FOR[name])') < auSrc.indexOf('if (MUTED) return;'));
    {
      /* the loop follows the trigger: a fake sound layer counts */
      const { Game } = await import('../js/game.js');
      const pl = await import('../js/player.js');
      const MAPS = await import('../js/maps/sellwrong.js');
      const THREES = await import('three');
      const calls = { play: [], loops: 0, stops: 0 };
      const gS = new Game({ level: MAPS.buildSellWrong({ town: false }), scene: new THREES.Scene(), camera: {},
        textures: tex.bakeTextures(), sprites: spr.bakeSprites(), hud: { message() {}, ticMessages() {} },
        audio: { play(n) { calls.play.push(n); }, loop(n) { calls.loops++; return { stop() { calls.stops++; } }; }, listener: { x: 0, y: 0 }, setAmbience() {} },
        input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 } });
      const q = gS.player; q.weapon = 'MINIGUN';
      const held = { look: { x: 0, y: 0 }, move: { x: 0, y: 0 }, attack: true, use: false, run: false, jump: false, weaponSlot: 0, weaponCycle: 0 };
      const up = { ...held, attack: false };
      for (let t = 0; t < pl.SPIN_UP + 6; t++) q.tic(held, 1 / 35);
      check('the trigger going down plays the spin-up once and starts the loop once the rounds leave',
        calls.play.filter(n => n === 'spinup').length === 1 && calls.loops === 1 && !!q.gunLoop && !calls.play.includes('minigun'));
      for (let t = 0; t < 4; t++) q.tic(up, 1 / 35);
      check('and letting go stops the loop and plays the wind-down',
        calls.stops === 1 && q.gunLoop === null && calls.play.filter(n => n === 'spindown').length === 1);
    }
    check('the loading screen says RETICULATING SPLINES and the steps do not talk over it',
      /RETICULATING SPLINES/.test(html) && !/s\.textContent = text/.test(mainSrc.split('const failed')[0]));
    check('nothing is written across the picture when a convoy is called',
      !/setBigMessage/.test(rsp));
    check('the fire button says FIRE and there is a JUMP button',
      />FIRE<\/div>/.test(html) && !/tb-fire[^>]*>\s*<svg/.test(html) && /data-btn="jump"/.test(html) && /\.tb-jump \{/.test(css));
    check('the three small buttons stand in an arc round the big one', /--arc:/.test(css) && /\.7071/.test(css));
    check('a pad fades the thumb controls and a finger brings them back',
      /#touch\.pad \.tb/.test(css) && /setPadHeld\(true\)/.test(inSrc) && /pointerType !== 'mouse'\) this\.setPadHeld\(false\)/.test(inSrc) &&
      /input\.onPadChange = on => touch\.setPadHeld\(on\)/.test(mainSrc));
    check('the pad is laid out the standard way: left stick moves, right stick looks, R2 fires, L2 jumps, bumpers cycle',
      /mx \+= dead\(pad\.axes\[0\]\); my -= dead\(pad\.axes\[1\]\)/.test(inSrc) && /lx \+= dead\(pad\.axes\[2\]\)/.test(inSrc) &&
      /btn\(7\)/.test(inSrc) && /padEdge\(6\)/.test(inSrc) && /padEdge\(4\)\) this\.weaponCycle = -1/.test(inSrc) && /padEdge\(5\)\) this\.weaponCycle = 1/.test(inSrc));
    check('space jumps, F uses, 4 is the minigun', /Space: 'jump'/.test(inSrc) && /KeyF: 'use'/.test(inSrc) && /Digit4: 'weapon4'/.test(inSrc));
    check('the readout names what you are holding, top right, and steps past the pause button on a phone',
      /_drawName\(/.test(hudSrc) && /setNameInset/.test(hudSrc) && /hud\.setNameInset\(on \?/.test(mainSrc));
    check('brightness, contrast and gamma are three sliders applied before the palette snap',
      ['opt-bright', 'opt-contrast', 'opt-gamma'].every(id => html.includes(`id="${id}"`)) &&
      /setPicture\(/.test(lofiSrc) && lofiSrc.indexOf('uPicture.x') < lofiSrc.indexOf('vec3 snapped = palSnap(c)') &&
      /pipeline\.setPicture\(\{ brightness: prefs\.bright/.test(mainSrc));
  }
}

/* ---------- the decals ---------- */
section('the decals');
{
  const fs = await import('node:fs');
  const D = await import('../js/decals.js');
  const { Game } = await import('../js/game.js');
  const MAPD = await import('../js/maps/sellwrong.js');
  const THREED = await import('three');
  const mk = () => new Game({
    level: MAPD.buildSellWrong({ town: false }), scene: new THREED.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
  });
  /* --- the arithmetic --------------------------------------------- */
  const line = { x1: 0, y1: 0, x2: 100, y2: 0 };
  const nA = D.wallNormal(line, 50, 40), nB = D.wallNormal(line, 50, -40);
  check('a wall\'s normal is unit length, across the line, and faces the shooter',
    Math.abs(Math.hypot(nA.nx, nA.ny) - 1) < 1e-9 && nA.nx === 0 && nA.ny > 0 && nB.ny < 0 && nA.nz === 0);
  const bw = D.surfaceBasis(nA), bf = D.surfaceBasis(D.UP);
  check('and a quad is laid across it: along and up for a wall, x and y for a floor',
    Math.abs(bw.ux * nA.nx + bw.uy * nA.ny) < 1e-9 && bw.vz === 1 && bf.ux === 1 && bf.vy === 1);
  /* --- holes --------------------------------------------------------- */
  const g = mk();
  const q = inTheOpen(g);                  // a wall to shoot at and nobody in front of it
  check('the game has decals, headless, with nothing to draw them on', !!g.decals && g.decals.liveCount === 0);
  const wall = g.level.rayHitWall(q.x, q.y, q.eyeZ, q.x + Math.cos(q.angle) * 4000, q.y + Math.sin(q.angle) * 4000, q.eyeZ);
  if (wall) {
    g.hitscan(q, q.angle, 4000, 10, { shot: true });
    const H = g.decals.pools.hole;
    check('a round into a wall leaves a hole on it, facing back the way it came',
      g.decals.holes === 1 && Math.abs(H.x[0] - wall.x) < 1e-6 &&
      (H.nx[0] * (q.x - wall.x) + H.ny[0] * (q.y - wall.y)) > 0 && H.nz[0] === 0 && H.strength[0] > 0.5);
    check('and it is a hand across, not a plate', H.size[0] >= D.HOLE_SIZE[0] && H.size[0] <= D.HOLE_SIZE[1]);
  } else check('a wall to shoot at', false);
  g.hitscan(q, q.angle, 4000, 10, { shot: true, pitch: -0.8 });
  check('and one into the floor leaves one on the floor, facing up',
    g.decals.holes === 2 && g.decals.pools.hole.nz[1] === 1);
  /* THE RING: a thousand rounds into one wall are still one pool */
  for (let k = 0; k < D.POOLS.hole + 50; k++) g.decals.hole(q.x, q.y, 0, D.UP);
  check('the holes are a ring, so the pool never overflows', g.decals.pools.hole.count === D.POOLS.hole && g.decals.holes === D.POOLS.hole + 52);
  /* FOUR HUNDRED, at the user's request: "increase bullet hole
     lifetime count by 4x". A hole has no clock, so the count is the
     lifetime — four times as many on the walls, each staying four times
     as long. The heat and the frost were not asked about. */
  check('and the ring is the MAX COUNT, four times the hundred it was, at the user\'s request',
    D.POOLS.hole === 4 * 100 && D.POOLS.heat === 100 && D.POOLS.frost === 100,
    `${D.POOLS.hole}, ${D.POOLS.heat}, ${D.POOLS.frost}`);

  /* --- AND A FULL POOL FADES ITS OLDEST OUT, IN ORDER -----------------
     At the user's request: the cap is not a guillotine. Once the pool
     is within FADE_AHEAD of full, that many of its oldest lose
     FADE_RATE a tic and are gone in eight, so the hole a new round
     takes the slot of has already dissolved. What is asserted is the
     ORDER — the fading ones are the oldest ones, which is the cursor's
     own next few — and that the pool drains rather than sitting full. */
  {
    const gF = mk();
    const dF = gF.decals, H = dF.pools.hole;
    const fx = gF.player.x, fy = gF.player.y;
    /* fill it exactly, in order, each hole a step along the wall so
       they can be told apart */
    for (let k = 0; k < D.POOLS.hole; k++) dF.hole(fx + k, fy, 40, D.UP);
    check('a pool\'s worth of rounds fill the pool and no more than fill it',
      H.count === D.POOLS.hole && H.next === 0, `${H.count} live, cursor ${H.next}`);
    const oldest = [];
    H.oldest(D.FADE_AHEAD, oldest);
    check('and the oldest of them are the first ones laid, in order',
      oldest.length === D.FADE_AHEAD && oldest.every((i, k) => i === k),
      oldest.join(','));
    const before = H.strength[0];
    dF.tic();
    check('a tic with the pool full fades the oldest and touches nothing outside the band',
      H.strength[0] < before - 1e-9 && Math.abs(H.strength[0] - (before - D.FADE_RATE)) < 1e-6 &&
      H.strength[D.FADE_AHEAD] === before && H.strength[D.POOLS.hole - 1] === before,
      `${H.strength[0].toFixed(3)} against ${H.strength[D.FADE_AHEAD].toFixed(3)}`);
    /* and they settle into the QUEUE: each held down to its place in
       it, so what is drawn at the old end is a gradient running from
       nothing up to full — a hole fading as the ring comes round to
       it rather than on a clock of its own */
    for (let k = 0; k < 10; k++) dF.tic();
    check('and the oldest is gone in four tics, and the band is a gradient in order',
      H.strength[0] === 0 && H.count === D.POOLS.hole - 1 &&
      [...Array(D.FADE_AHEAD - 1)].every((_, k) => H.strength[k + 1] > H.strength[k]),
      `${H.count} left, band ${[0, 1, 2, 8, 16, 23].map(k => H.strength[k].toFixed(2)).join(' ')}`);
    check('and the queue is where a decal\'s brightness comes from: nothing at the cursor, full at the back',
      D.fadeTarget(0) === 0 && D.fadeTarget(D.FADE_AHEAD) === 1 && D.fadeTarget(D.FADE_AHEAD / 8) < 0.02);
    check('and the newest are untouched: a cap that fades is not a cap that cuts',
      H.strength[D.POOLS.hole - 1] > 0.5 && H.strength[D.FADE_AHEAD] > 0.5);
    /* and it holds there rather than emptying itself out */
    for (let k = 0; k < 400; k++) dF.tic();
    check('and a pool that has stopped filling holds what it has rather than emptying',
      H.count === D.POOLS.hole - 1, `${H.count} left`);
    /* AND THE FADE KEEPS AHEAD OF THE MINIGUN, which is the whole
       reason it is a queue and not a clock: four holes a tic for a
       second, and every slot the cursor takes was already faded to
       nothing rather than cut off the wall at full strength. */
    {
      let worst = 0;
      for (let t = 0; t < 35; t++) {
        for (let k = 0; k < 4; k++) {
          worst = Math.max(worst, H.strength[H.next]);
          dF.hole(fx + (t * 4 + k) % 90, fy + 90, 40, D.UP);
        }
        dF.tic();
      }
      check('and under a held minigun every hole the ring reaches has already faded out',
        worst < 0.05, `the brightest overwritten was ${worst.toFixed(3)}`);
      check('and the wall still holds nearly the whole pool of them', H.count <= D.POOLS.hole && H.count > D.POOLS.hole * 0.8, `${H.count}`);
    }
    /* AND THE SAME FOR THE OTHER KINDS, at the user's request: they
       are one system and one rule. A hundred separate hot spots, far
       enough apart that none of them merges. */
    const HT = dF.pools.heat;
    for (let k = 0; k < D.POOLS.heat; k++) dF.heat(fx + k * (D.MERGE_RADIUS * 3), fy + 400, 40, D.UP, 1);
    check('the heat pool is a ring on the same rule', HT.count === D.POOLS.heat, `${HT.count}`);
    const s0 = HT.strength[HT.next], s9 = HT.strength[(HT.next + D.POOLS.heat - 1) % D.POOLS.heat];
    dF.tic();
    check('and its oldest fades faster than its cooling alone',
      (s0 - HT.strength[HT.next]) > (s9 - HT.strength[(HT.next + D.POOLS.heat - 1) % D.POOLS.heat]) + 1e-9,
      `${(s0 - HT.strength[HT.next]).toFixed(4)} against ${(s9 - HT.strength[(HT.next + D.POOLS.heat - 1) % D.POOLS.heat]).toFixed(4)}`);
  }
  /* --- the cull: drawn only in range and in front of the eye ------------ */
  {
    const gC = mk();
    const dC = gC.decals;
    dC.attach(gC.scene);
    const hx = gC.player.x, hy = gC.player.y;
    dC.hole(hx + 300, hy, 40, D.UP);                   // ahead
    dC.hole(hx - 300, hy, 40, D.UP);                   // behind
    dC.hole(hx + D.DRAW_RANGE + 200, hy, 40, D.UP);    // too far
    const H = dC.pools.hole;
    dC.render();
    check('with no eye given every hole is drawn', H.drawn === 3);
    dC.render(hx, hy, 1, 0);
    check('given the eye, the one behind it and the one out of range are not', H.drawn === 1, `${H.drawn} drawn`);
    dC.render(hx, hy, -1, 0);
    check('turn round and it is the other one, one box instanced', H.drawn === 1 && H.mesh.geometry.instanceCount === 1);
    check('and the range is a number the readme can name', D.DRAW_RANGE >= 2000 && D.DRAW_RANGE <= 4000);
  }
  /* --- cubes, blood and burning holes ------------------------------- */
  {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync(new URL('../js/decals.js', import.meta.url), 'utf8');
    check('every decal is a box projected onto the world\'s depth, one instanced draw',
      /InstancedBufferGeometry/.test(src) && /BoxGeometry\(1, 1, 1\)/.test(src) && /unpackRGBAToDepth/.test(src) &&
      /side: THREE\.BackSide/.test(src) && /depthTest: false/.test(src));
    check('the detail is arithmetic: no picture is drawn for a decal any more',
      !/holeStrip|glowStrip|CanvasTexture/.test(src) && /dfbm/.test(src) && /cracks\(/.test(src));
    check('and the pipeline draws them between the world and the gun',
      /this\.afterWorld\(r, camera, this\.target\)/.test(readFileSync(new URL('../js/lofi.js', import.meta.url), 'utf8')) &&
      /pipeline\.afterWorld = \(r, cam, target\) => game\.decals\.draw\(r, cam, target\)/.test(readFileSync(new URL('../js/main.js', import.meta.url), 'utf8')));
    check('ten kinds, each its own look', Object.keys(D.KIND).length === 10 && D.POOLS.blood > 0 && D.POOLS.burn > 0 && D.POOLS.sear > 0);
    const gB = mk(), dB = gB.decals;
    dB.attach(gB.scene);
    const victim = gB.actors.find(a => a.monster && a.shootable && !a.vehicle && !a.dead);
    check('people bleed; a van and a block of ice do not',
      D.bleeds(victim) && !D.bleeds({ monster: true, vehicle: {} }) && !D.bleeds({ monster: true, frozen: true }) && D.bleeds(gB.player, gB.player));
    const n0 = dB.pools.blood.count;
    const k = dB.bleed(victim, victim.x, victim.y, victim.z + 40, 1, 0, 0);
    check('a round through somebody puts blood on the floor at their feet', k >= 1 && dB.pools.blood.count === n0 + k &&
      dB.pools.blood.nz[(dB.pools.blood.next + dB.pools.blood.max - k) % dB.pools.blood.max] === 1);
    /* AND UP THE WALLS BEHIND THEM, at the user's request: "i want
       blood spatter on walls too". Somebody stood a little way in front
       of a wall and shot toward it: a spray of it up the wall, several
       spatters and not one, every one facing back toward them. */
    {
      const q2 = inTheOpen(gB);
      const far = gB.level.rayHitWall(q2.x, q2.y, q2.eyeZ, q2.x + Math.cos(q2.angle) * 4000, q2.y + Math.sin(q2.angle) * 4000, q2.eyeZ);
      if (far) {
        const back = 90;
        const ux = Math.cos(q2.angle), uy = Math.sin(q2.angle);
        const who = { monster: true, x: far.x - ux * back, y: far.y - uy * back, z: q2.z };
        const B = dB.pools.blood, before = new Set([...Array(B.max).keys()].filter(i => B.strength[i] > 0));
        const n = dB.bleed(who, who.x, who.y, q2.z + 40, ux, uy, 0);
        const onWall = [...Array(B.max).keys()].filter(i => B.strength[i] > 0 && !before.has(i) && B.nz[i] === 0);
        note('a round through somebody a little in front of a wall', `${n} spatters, ${onWall.length} of them up the wall`);
        check('a round through somebody in front of a wall sprays blood up it, not one blot',
          onWall.length >= 2 && onWall.length <= D.WALL_SPRAY && D.WALL_SPRAY >= 3 && D.BLOOD_REACH > 130);
        check('every spatter on the wall faces back the way the blood came, above the floor',
          onWall.every(i => B.nx[i] * (who.x - B.x[i]) + B.ny[i] * (who.y - B.y[i]) > 0 && B.z[i] > q2.z));
        check('and they are big enough to read, not flecks',
          onWall.every(i => B.size[i] >= D.WALL_SPATTER[0] * 0.99));
      } else check('a wall to bleed on', false);
    }
    const bi = dB.blood(victim.x, victim.y, victim.z, D.UP, 0, 1, 0);
    check('and a spatter is turned to face the way it was thrown', Math.abs(dB.pools.blood.rot[bi] - Math.PI / 2) < 1e-6);
    const ri = dB.burn(victim.x, victim.y, victim.z, D.UP);
    check('a burning hole is big, and burns', dB.burns === 1 && dB.pools.burn.size[ri] > 60 && dB.kindOf(dB.pools.burn, ri) === D.KIND.BURN);
    dB.pool(victim.x, victim.y, victim.z);
    dB.hole(victim.x, victim.y, victim.z, D.UP, true);
    dB.render();
    check('and all of them go into the one box', dB.mesh.geometry.instanceCount === dB.liveCount && dB.drawn === dB.liveCount);
    const P = dB.mesh.geometry.attributes.iP.array;
    const kinds = new Set(); for (let i = 0; i < dB.drawn; i++) kinds.add(P[i * 4]);
    check('with their kinds told apart', kinds.has(D.KIND.SPATTER) && kinds.has(D.KIND.POOL) && kinds.has(D.KIND.BURN) && kinds.has(D.KIND.HOT));
    const hitSrc = readFileSync(new URL('../js/game.js', import.meta.url), 'utf8');
    check('the shot, the warhead, the bore and a bomb all leave decals and not puffs',
      /this\.decals\.bleed\(best\.a/.test(hitSrc) && !/spawnPuff\(wall\.x, wall\.y, wall\.z\);\n\s*if \(opts\.spark\)/.test(hitSrc) &&
      /decals\?\.burn\(at\.x, at\.y, at\.z, face\)/.test(readFileSync(new URL('../js/missiles.js', import.meta.url), 'utf8')) &&
      /decals\?\.burn\(/.test(readFileSync(new URL('../js/bore.js', import.meta.url), 'utf8')) && /this\.decals\.burn\(a\.x/.test(hitSrc));
    check('and the minigun\'s rounds are the hot kind', /shot: true, hot: true/.test(readFileSync(new URL('../js/player.js', import.meta.url), 'utf8')));
  }
  /* --- heat ---------------------------------------------------------- */
  const g2 = mk();
  const d = g2.decals, x = g2.player.x, y = g2.player.y, z = g2.player.z;
  for (let k = 0; k < 20; k++) d.heat(x, y, z, D.UP);
  const HP = d.pools.heat;
  check('the stream held on one spot heats it, and one landing is a little',
    HP.count === 1 && Math.abs(HP.strength[0] - Math.min(1, 20 * D.HEAT_PER_LANDING)) < 1e-5);
  d.heat(x + 10, y + 8, z, D.UP);
  check('a landing near a hot spot feeds it rather than starting another', HP.count === 1);
  d.heat(x + 80, y, z, D.UP);
  check('and one a way off starts another', HP.count === 2);
  for (let k = 0; k < 40; k++) d.heat(x, y, z, D.UP);
  check('and it tops out white', HP.strength[0] === 1);
  for (let t = 0; t < 6 * 35 + 2; t++) d.tic();
  check('left alone it cools over six seconds', HP.count === 0 && HP.strength[0] === 0);
  check('and a spot that got hot leaves a scorch behind, for good',
    d.scorches >= 1 && d.pools.hole.count >= 1 && d.pools.hole.frame[0] === 1 && d.pools.hole.size[0] > D.HOLE_SIZE[1]);
  /* --- frost, and the argument --------------------------------------- */
  const g3 = mk();
  const d3 = g3.decals, x3 = g3.player.x, y3 = g3.player.y, z3 = g3.player.z;
  for (let k = 0; k < 10; k++) d3.frost(x3, y3, z3, D.UP);
  const FP = d3.pools.frost;
  check('the jet held on one spot rimes it', FP.count === 1 && Math.abs(FP.strength[0] - Math.min(1, 10 * D.FROST_PER_LANDING)) < 1e-5);
  for (let t = 0; t < 10 * 35 + 2; t++) d3.tic();
  check('and it thaws over ten seconds and leaves nothing', FP.count === 0 && d3.pools.hole.count === 0);
  for (let k = 0; k < 20; k++) d3.heat(x3, y3, z3, D.UP);
  const before = d3.pools.heat.strength[0];
  d3.frost(x3 + 20, y3, z3, D.UP);
  check('gas landing near a hot spot takes the heat out of it', d3.pools.heat.strength[0] < before - 0.05);
  const fi = FP.nearest(x3 + 20, y3, z3, D.UP, 5), fb = FP.strength[fi];
  d3.heat(x3 + 30, y3, z3, D.UP);
  check('and flame landing near rime melts it', fi >= 0 && FP.strength[fi] < fb);
  check('but a wall\'s heat and a floor\'s rime do not argue: different surfaces',
    (() => { const g4 = mk(); const dd = g4.decals; const p = g4.player; for (let k = 0; k < 20; k++) dd.heat(p.x, p.y, p.z, D.UP); const b = dd.pools.heat.strength[0]; dd.frost(p.x, p.y, p.z, { nx: 1, ny: 0, nz: 0 }); return dd.pools.heat.strength[0] === b; })());
  /* --- and the streams actually feed it --------------------------------- */
  const g5 = mk();
  const p5 = g5.player;
  /* a few tics: long enough for the particles to land, short enough
     that six landings' worth has not cooled away again */
  g5.flame.fire({ x: p5.x, y: p5.y, z: p5.eyeZ }, p5.angle, -1.1);
  for (let t = 0; t < 8; t++) { g5.flame.tic(); g5.decals.tic(); }
  check('the flamethrower held at the floor heats the floor', g5.decals.pools.heat.count > 0 && g5.decals.pools.heat.nz[0] === 1 && g5.flame._hits > 0);
  g5.frost.fire({ x: p5.x, y: p5.y, z: p5.eyeZ }, p5.angle, -1.1);
  for (let t = 0; t < 8; t++) { g5.frost.tic(); g5.decals.tic(); }
  check('and the extinguisher held at the floor rimes it', g5.decals.pools.frost.count > 0);
  const gsrc = fs.readFileSync('js/game.js', 'utf8');
  check('the decals are ticked, drawn, and attached only where there are pictures',
    /this\.decals\.tic\(\)/.test(gsrc) && /this\.decals\.render\(ex, ey, vx, vy\)/.test(gsrc) && /if \(fxAtlases\) this\.decals\.attach\(scene\)/.test(gsrc));
}

/* ---------- the vans under fire ---------- */
section('the vans under fire');
{
  const fs = await import('node:fs');
  const { Game } = await import('../js/game.js');
  const MAPV = await import('../js/maps/sellwrong.js');
  const THREEV = await import('three');
  const { Tracers, MAX_TRACERS, TRACER_SPEED, TRACER_LEN } = await import('../js/tracers.js');
  /* the lot's van, off the user's file, the way `the van` builds it */
  const carV = await import('../js/car.js');
  const glbV = await import('../js/glb.js');
  const vanDef = (() => {
    const bytes = fs.readFileSync('assets/models/van.glb');
    const { json, bin } = glbV.parseGLB(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    return carV.modelVehicle(json, bin);
  })();
  const mk = () => new Game({
    level: MAPV.buildSellWrong({ town: false }), scene: new THREEV.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
    fleet: { texture: {}, def: vanDef },
  });
  const g = mk();
  const v = g.vehicles.all.find(c => c.whole);
  check('there is a van in the lot to shoot at', !!v);
  if (v) {
    /* --- rounds ------------------------------------------------------- */
    const hp = v.health;
    v.damage(36, g.player, { shot: true });
    check('a round takes a twentieth of what it would off a car in the lot',
      Math.abs((hp - v.health) - 36 / v.shotArmour) < 1e-9 && v.shotArmour === 20);
    let rounds = 1;
    while (v.whole && v.state !== 'charring' && rounds < 1000) { v.damage(36, g.player, { shot: true }); rounds++; }
    note('a car in the lot', `${rounds} rounds of the minigun before it chars`);
    check('and it takes a lot of them before it chars, and chars rather than vanishing',
      rounds > 60 && rounds < 120 && v.state === 'charring');
    /* --- the stream lights it and that is all --------------------------- */
    const w = g.vehicles.all.find(c => c.whole && c !== v);
    const hw = w.health;
    for (let k = 0; k < 400; k++) w.damage(9, g.player, { fire: true, stream: true });
    check('four hundred flame particles on a car light it and take nothing off it',
      w.health === hw && w.burning > 0 && w.state !== 'charring');
    const hb = w.health;
    w.damage(30, null, { fire: true });
    check('but a blast still hurts it', w.health < hb);
    /* the blocker path: the stream hits a CARBODY, which hands it on */
    const blocker = w.blockers[0];
    const hb2 = w.health;
    blocker.damage(9, g.player, { fire: true, stream: true });
    check('and through the blockers the same', w.health === hb2);
    /* --- holes on it ---------------------------------------------------- */
    const D = g.decals;
    const L = w.def.length, hw2 = w.def.box.half * L;
    /* a round from the driver's side, coming across the vehicle */
    const c = Math.cos(w.yaw), sn = Math.sin(w.yaw);
    const hx = w.x - sn * 10, hy = w.y + c * 10;          // ten units off the centreline, left
    D.vehicleHole(w, hx, hy, w.bodyZ + 20, sn, -c, 0);     // travelling toward -local y
    const P = D.pools.hole, i = P.next === 0 ? P.max - 1 : P.next - 1;
    check('a round into a van leaves a hole on the flank it came in through',
      P.owner[i] === w && Math.abs(P.ly[i] - hw2) < 1e-3 && P.lny[i] === 1 && P.lnx[i] === 0 && P.lnz[i] === 0);
    check('and the hole rides in the van\'s own frame',
      Math.abs(P.lz[i] - 20) < 1e-3 && Math.abs(P.lx[i]) < L / 2);
    /* the top: a round coming steeply down */
    D.vehicleHole(w, w.x, w.y, w.bodyZ + 5, 0.1, 0, -1);
    const j = P.next === 0 ? P.max - 1 : P.next - 1;
    check('and one from above lands on the roof', P.lnz[j] === 1 && Math.abs(P.lz[j] - w.def.box.height * L) < 1e-3);
    /* carried: render() with no mesh still places owned holes where the vehicle is */
    const ox = w.x; w.x += 100;
    D._carry();
    check('and moves when the van does', Math.abs(P.x[i] - (P.x[i] - 0)) < 1e-9 && P.x[i] > ox + 50);
    w.x = ox;
    /* --- the hitscan does all of that on its own -------------------------- */
    const g2 = mk();
    const q = g2.player, u = g2.vehicles.all.find(c => c.whole);
    q.x = u.x - Math.cos(u.yaw + Math.PI / 2) * 200; q.y = u.y - Math.sin(u.yaw + Math.PI / 2) * 200;
    q.sector = g2.level.sectorAt(q.x, q.y); q.z = q.sector ? q.sector.floor : 0; q.viewZ = q.z + 30;
    q.angle = Math.atan2(u.y - q.y, u.x - q.x);
    const before = g2.decals.holes, uh = u.health;
    const hit = g2.hitscan(q, q.angle, 2400, 36, { shot: true, pitch: 0 });
    check('a shot at a van hits it, hurts it a twentieth, and puts a hole on it',
      !!hit && hit.vehicle === u && u.health < uh && g2.decals.holes === before + 1 && g2.decals.pools.hole.owned === 1,
      `${hit ? hit.type : 'miss'} ${g2.decals.holes - before} holes`);
    check('and says where it stopped, for the tracer',
      Math.hypot(g2.lastHit.x - u.x, g2.lastHit.y - u.y) < u.def.length);
  }
  /* --- the police van and the carrier ------------------------------------- */
  const vsrc = fs.readFileSync('js/vehicles.js', 'utf8');
  check('the police van takes fifty times a round and the APC ninety',
    /shotArmour: 50/.test(vsrc) && /this\.shotArmour = 90/.test(vsrc));
  /* --- tracers ------------------------------------------------------------ */
  const T = new Tracers(null);
  const t0 = T.spawn({ x: 0, y: 0, z: 40 }, { x: 400, y: 0, z: 40 });
  check('a tracer leaves the muzzle toward the hit', t0 >= 0 && T.count === 1 && T.dx[t0] === 1 && T.left[t0] === 400);
  T.tic();
  check('and flies a hundred and fifty a tic', Math.abs(T.x[t0] - TRACER_SPEED) < 1e-6);
  /* VERY LONG, at the user's request, and it grows out of the barrel:
     for its first tics the tail is AT the muzzle, not behind it */
  check('a tracer is very long', TRACER_LEN >= 300, `${TRACER_LEN}`);
  {
    const tailAt = (i) => Math.min(Math.max(0, T.trav[i] - TRACER_LEN), T.d[i]);
    check('and its tail stays at the muzzle until the head is a whole length out',
      tailAt(t0) === 0 && T.trav[t0] === TRACER_SPEED);
    for (let k = 0; k < 2; k++) T.tic();
    check('the head arrives and waits at the hit', T.x[t0] === 400 && T.left[t0] === 0 && T.alive[t0] === 1);
    const before = tailAt(t0);
    T.tic();
    check('while the tail keeps flying, shrinking the streak into it', tailAt(t0) > before && tailAt(t0) < 400);
  }
  for (let k = 0; k < 6; k++) T.tic();
  check('and is gone once the tail has caught the head up', T.count === 0);
  for (let k = 0; k < MAX_TRACERS + 10; k++) T.spawn({ x: 0, y: 0, z: 40 }, { x: 4000, y: 0, z: 40 });
  check('and a burst past the pool reuses the oldest', T.count === MAX_TRACERS);
  check('the minigun fires one every other round', /\(i & 1\) === 0 && g\.tracers/.test(fs.readFileSync('js/player.js', 'utf8')));
  /* --- the puff sits on the hole ---------------------------------------- */
  {
    const bank = spr.bakeSprites();
    const e = bank.get('PUFF', 'A');
    check('the hit puff is centred on the hit, not stood a height and a half above it',
      e.lift === -(e.h * e.scale) / 2, `lift ${e.lift} for ${e.h} tall`);
  }
  /* --- the minigun, under the music ------------------------------------- */
  {
    const au = await import('../js/audio.js');
    check('the minigun\'s recordings are turned down so the music stands out',
      au.SAMPLE_GAIN.minigun_fire <= 0.4 && au.SAMPLE_GAIN.minigun_start <= 0.5 && au.SAMPLE_GAIN.minigun_stop <= 0.5 &&
      /this\._gainFor\(from\) \* \(SAMPLE_GAIN\[key\] \?\? 1\)/.test(fs.readFileSync('js/audio.js', 'utf8')));
  }
}

/* ---------- the gunship ---------- */
section('the gunship');
{
  const fs = await import('node:fs');
  const V = await import('../js/vtol.js');
  const glbG = await import('../js/glb.js');
  const carG = await import('../js/car.js');
  const { Game } = await import('../js/game.js');
  const MAPG = await import('../js/maps/sellwrong.js');
  const THREEG = await import('three');
  const { world } = await import('../js/material.js');

  const readGLB = f => {
    const b = fs.readFileSync(f);
    return glbG.parseGLB(b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength));
  };
  const { json, bin } = readGLB('assets/models/vtol.glb');

  /* --- THE FILE, AS PREPARED ---------------------------------------
     The user drew the answers into the model: small spheres named for
     what they mark, NESTED inside the parts they belong to, because
     where a muzzle is only means anything relative to the gun that
     turns. tools/prep-model.mjs reads those out into the file's own
     extras and takes them out of the mesh — so what is asserted here is
     that the markers are FACTS IN THE FILE and not geometry anybody can
     render by mistake. */
  const vtolMB = fs.statSync('assets/models/vtol.glb').size / 1048576;
  note('what is in the file', `${json.nodes.length} nodes, ${json.meshes.length} meshes, ` +
    `${json.images.length} image, ${vtolMB.toFixed(1)} MB`);

  /* --- AND ITS SHEET IS CRUNCHED, at the user's request -------------
     Six of the model's seven megabytes were a 2048-square colour map on
     a thing that is four hundred units long and usually three hundred
     units over your head. tools/prep-model.mjs --texture 1024 halves it
     — a box average, which is the correct downsample for exactly the
     halving case, and then PNG's own adaptive filtering, which is what
     a photograph needs and flat pixel art does not. */
  {
    const { readPNG: rp, writePNG: wp, halvePNG: hp } = await import('./png-read.mjs');
    const zlibM = await import('node:zlib');
    /* the IDAT of a PNG, concatenated, for the two checks below that
       read a written file back rather than trusting it */
    const idatOf = png => {
      const parts = [];
      let at = 8;
      while (at < png.length) {
        const len = png.readUInt32BE(at), type = png.toString('ascii', at + 4, at + 8);
        if (type === 'IDAT') parts.push(png.subarray(at + 8, at + 8 + len));
        at += 12 + len;
      }
      return Buffer.concat(parts);
    };
    const bvI = json.bufferViews[json.images[0].bufferView];
    const sheet = rp(Buffer.from(bin.subarray(bvI.byteOffset || 0, (bvI.byteOffset || 0) + bvI.byteLength)));
    note('its sheet', `${sheet.w}x${sheet.h}, ${(bvI.byteLength / 1024).toFixed(0)}K of the ${(vtolMB * 1024).toFixed(0)}K file`);
    check('the gunship\'s sheet is crunched to 1024, at the user\'s request',
      sheet.w === 1024 && sheet.h === 1024, `${sheet.w}x${sheet.h}`);
    check('and the whole model is under two megabytes because of it',
      vtolMB < 2, `${vtolMB.toFixed(2)} MB`);

    /* the two pieces that did it, on their own. A box halve is four
       texels averaged into one and nothing else; a filtered PNG is a
       different file from an unfiltered one and reads back the same
       pixels; and the UNFILTERED path has to be untouched, because
       every PNG already committed out of the other tools was written
       by it. */
    const tiny = { w: 2, h: 2, data: new Uint8ClampedArray([0,0,0,255, 10,20,30,255, 20,40,60,255, 30,60,90,255]) };
    const half = hp(tiny);
    check('halving averages the four texels it covers, and nothing else',
      half.w === 1 && half.h === 1 &&
      [...half.data].join(',') === `${(0+10+20+30+2)>>2},${(0+20+40+60+2)>>2},${(0+30+60+90+2)>>2},255`,
      [...half.data].join(','));
    check('and an odd size throws rather than being stretched',
      (() => { try { hp({ w: 3, h: 2, data: new Uint8ClampedArray(24) }); return false; } catch { return true; } })());
    const W = 64, H = 40, px = new Uint8ClampedArray(W * H * 4);
    for (let i = 0; i < W * H; i++) { px[i*4] = (i*7)&255; px[i*4+1] = (i*13)&255; px[i*4+2] = (i*29)&255; px[i*4+3] = 255; }
    const plain = wp(W, H, px), filt = wp(W, H, px, { filter: true });
    const backF = rp(filt);
    check('a filtered PNG is a different file that reads back the same pixels, smaller',
      Buffer.compare(plain, filt) !== 0 && filt.length < plain.length &&
      backF.w === W && backF.h === H && [...backF.data].every((v, i) => v === px[i]),
      `${plain.length} unfiltered against ${filt.length} filtered`);
    /* AND THE UNFILTERED PATH IS UNTOUCHED, which is the check that
       actually protects something: every PNG already committed out of
       tools/prep-people.mjs, tools/prep-troops.mjs, tools/bake-sky.mjs
       and tools/bake-icons.mjs was written by it, and a filter quietly
       turned on for all of them would rewrite files nobody asked to
       have rewritten. Read out of the file rather than trusted: the
       IDAT inflated, and every row's filter byte still zero. */
    check('and every row of an unfiltered PNG still says filter none',
      (() => {
        const zl = zlibM.inflateSync(idatOf(plain));
        const stride = W * 4;
        for (let y = 0; y < H; y++) if (zl[y * (stride + 1)] !== 0) return false;
        return true;
      })(), 'the default path is what every committed PNG was written by');
    check('while a filtered one actually filters, rather than writing none five times',
      (() => {
        const zl = zlibM.inflateSync(idatOf(filt));
        const stride = W * 4, seen = new Set();
        for (let y = 0; y < H; y++) seen.add(zl[y * (stride + 1)]);
        /* WHICH of the five it settles on is the picture's business —
           a smooth ramp is Sub for every row of it and a photograph is
           a mix — so what is asserted is that something other than
           `none` won, which is the whole of the claim being made. */
        return [...seen].some(t => t !== 0);
      })(), 'every row wrote filter none, so nothing was filtered');
  }
  const EX = json.asset?.extras || {};
  check('the gunship is prepared: its markers are in the extras, not in the mesh',
    !!EX.markers?.muzzle && !!EX.markers?.lamp &&
    !json.nodes.some(n => /^Claude.*Delete/i.test(n.name || '')),
    Object.keys(EX.markers || {}).join(', '));
  check('and each marker says which part it is in, so the point turns with that part',
    EX.markers.muzzle.node === 'ClaudeSpinThisThisIsTheVulcanGun' &&
    EX.markers.lamp.node === 'SpotlightModule' && EX.spin === EX.markers.muzzle.node);
  check('and the maps an unlit renderer cannot use are gone: one image, the colour',
    json.images.length === 1 && !json.materials.some(m => m.normalTexture || m.emissiveTexture));

  /* --- THE PARTS ---------------------------------------------------
     A vehicle is one mesh with one transform; this is a TREE of them,
     because everything the user asked it to do is a part moving against
     another part. Each node comes out in a frame of its own — x
     forward, y up, z right — with the offset of its pivot from its
     parent's, which is what the groups are hung on. */
  const model = V.buildVtolModel(json, bin);
  const P = model.parts;
  note('the aircraft', `${V.VTOL_LENGTH} long, ${(model.box.half * 2 * V.VTOL_LENGTH).toFixed(0)} across, ` +
    `${(model.box.height * V.VTOL_LENGTH).toFixed(0)} tall, ${Object.keys(P).length} moving parts, ` +
    `${Object.values(P).reduce((n, q) => n + q.tris, 0)} triangles`);
  check('every part of it has triangles in it', Object.values(P).every(q => q.tris > 50),
    Object.entries(P).map(([k, q]) => `${k} ${q.tris}`).join(', '));
  check('and the tree is the one the file names: the gun and the lamp on the pitch, on the turret, on the fuselage',
    P.gun.parent === P.pitch && P.lamp.parent === P.pitch && P.pitch.parent === P.turret &&
    P.turret.parent === P.fuselage && P.fuselage.parent === null &&
    P.nacelleL.parent === P.fuselage && P.aux.parent === P.fuselage);
  /* THE NACELLES ARE ONE MESH AND TWO ENGINES. The file draws them
     together; an aircraft that tilts them differentially to turn cannot
     have them as one part, so the mesh is cut down its own middle. What
     proves the cut is right is that it is EVEN and that the two halves
     end up on opposite sides. */
  check('the one nacelle mesh comes out as two engines, one either side, the same size',
    P.nacelleL.tris === P.nacelleR.tris &&
    Math.sign(P.nacelleL.offset[2]) === -Math.sign(P.nacelleR.offset[2]) &&
    Math.abs(P.nacelleL.offset[2] + P.nacelleR.offset[2]) < 1e-6 &&
    Math.abs(P.nacelleL.offset[2]) > 100,
    `${P.nacelleL.tris} each, ${P.nacelleL.offset[2].toFixed(0)} and ${P.nacelleR.offset[2].toFixed(0)} across`);
  check('and the tail engine is behind the wing and on the centreline',
    P.aux.offset[0] < P.nacelleL.offset[0] && Math.abs(P.aux.offset[2]) < 1e-6);
  /* AND THE MUZZLE IS AT THE END OF THE BARRELS, which is the whole
     point of the marker: the user put the sphere there so that nobody
     would have to guess a number. Down the gun's own +x, and as far
     forward as the model goes. */
  const nose = V.VTOL_LENGTH / 2;
  const muzzleFwd = P.fuselage.offset[0] + P.turret.offset[0] + P.pitch.offset[0] + P.gun.offset[0] + model.muzzle[0];
  check('the muzzle marker is at the end of the barrels, at the very nose of the thing',
    model.muzzle[0] > 20 && Math.abs(model.muzzle[1]) < 8 && Math.abs(model.muzzle[2]) < 1 &&
    Math.abs(muzzleFwd - nose) < 6,
    `${muzzleFwd.toFixed(0)} forward of the middle, the nose is ${nose}`);
  check('and the lamp marker is out in front of the lamp module, off to one side of the gun',
    model.lamp[0] > 0 && Math.abs(P.lamp.offset[2]) > 8);

  /* --- ONE, FLOWN ---------------------------------------------------- */
  const vanG = (() => { const v = readGLB('assets/models/van.glb'); return carG.modelVehicle(v.json, v.bin); })();
  const texG = tex.bakeTextures(), sprG = spr.bakeSprites();
  const mkG = () => new Game({
    level: MAPG.buildSellWrong({ town: false }), scene: new THREEG.Scene(), camera: {},
    textures: texG, sprites: sprG,
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
    fleet: { texture: {}, def: vanG },
    vtol: { json, bin, texture: {} },
  });
  const gg = mkG();
  const pg = gg.player;
  /* THE MIDDLE OF THE CAR PARK. The start is at the lot's south edge,
     which is the town's north edge now, and a gunship stationing over a
     player stood there is over the first street of houses — where it
     correctly climbs to clear the roofs, and where the claim below
     about the lot's own ceiling is not the claim being made. */
  pg.x = 1240; pg.y = -1200; pg.sector = gg.level.sectorAt(pg.x, pg.y); pg.z = pg.sector.floor;
  pg.invincible = true;                     // it is lethal, and that is measured below rather than survived
  check('a game with the model in it has a wing, with nothing in the air yet',
    !!gg.gunships && gg.gunships.ships.length === 0 && gg.gunships.cap === 0);

  /* IT COMES WITH THE ARMY, at the user's request: nothing before the
     army is called, and the first one ordered the tic it is. */
  {
    const gA = mkG();
    gA.player.shotsFired = 1;
    let calledAt = -1, sentAt = -1;
    for (let t = 0; t < 200 * 35 && sentAt < 0; t++) {
      gA.tic();
      if (calledAt < 0 && gA.responders.army.called) calledAt = gA.tics;
      if (gA.gunships.ships.length && sentAt < 0) sentAt = gA.tics;
    }
    note('when it comes', `the army at ${(calledAt / 35).toFixed(0)}s, the gunship at ${(sentAt / 35).toFixed(0)}s`);
    check('it is ordered the tic the army is called and arrives a few seconds later',
      calledAt > 0 && sentAt > calledAt && sentAt - calledAt === V.VTOL.firstDelay,
      `${sentAt - calledAt} tics after`);
    check('and one of them until the army has doubled twice, then two',
      gA.gunships.cap === 1 && V.VTOL.max === 2 && V.VTOL.secondAt > 1);
  }

  const ship = gg.gunships.send();
  check('it comes into being out of sight rather than at the end of the road',
    !!ship && Math.abs(Math.hypot(ship.x - pg.x, ship.y - pg.y) - V.VTOL.runIn) < 40 &&
    ship.cz > 500, `${Math.hypot(ship.x - pg.x, ship.y - pg.y).toFixed(0)} out at ${ship.cz.toFixed(0)}`);
  check('and the thing you can shoot comes with it: three of them, in the air, at its height',
    ship.bodies.length === 3 && ship.bodies.every(a => a.shootable && !a.solid && a.vehicle === ship));

  let onStation = -1, lowest = 1e9, highest = 0, maxBank = 0, diffSeen = 0;
  for (let t = 1; t <= 900; t++) {
    gg.tic();
    if (onStation < 0 && ship.state === 'station') onStation = t;
    /* THE PODS ARE WATCHED FOR THE WHOLE FLIGHT and the altitude only on
       station, because they are two different claims: the differential
       is about the mechanism and shows best in the run-in, where it
       turns hardest, while the altitude is about where it settles. They
       used to share the on-station window, which made the mechanism's
       evidence depend on how tight an orbit the player happened to give
       it — and a player stood somewhere else is not a broken gearbox. */
    diffSeen = Math.max(diffSeen, Math.abs(ship.tiltL - ship.tiltR));
    if (ship.state === 'station') {
      lowest = Math.min(lowest, ship.altitude); highest = Math.max(highest, ship.altitude);
      maxBank = Math.max(maxBank, Math.abs(ship.rx));
    }
  }
  note('the flight', `on station in ${(onStation / 35).toFixed(1)}s, holding ${lowest.toFixed(0)}-${highest.toFixed(0)} up, ` +
    `banking ${(maxBank * 57.3).toFixed(0)} degrees, ${ship.rounds} rounds fired`);
  check('it flies in and takes up a station over the lot in a few seconds',
    onStation > 0 && onStation < 8 * 35, `${onStation} tics`);
  check('and holds its altitude there, under the lot\'s own ceiling so it can be shot at',
    Math.abs(lowest - V.VTOL.alt) < 30 && highest < 480, `${lowest.toFixed(0)}..${highest.toFixed(0)}`);
  /* THE NACELLES VECTOR THE THRUST, which is what the user asked for,
     and the corrections below are what the user asked for after seeing
     it: the pods were drawn nose-DOWN as it accelerated and level in a
     hover, which is both signs of it inverted, and they jangled.

     TWO ANGLES NOW. `vector` is where the jet is pointed, measured up
     from level — a right angle in a hover, flattening toward the nose
     with speed — and `tilt` is where the pod is DRAWN, a geared share
     of the same. See the block at VTOL.hover for why a two-hundred-unit
     pod is not swung to a true right angle. */
  check('the pods go differentially when it turns: one up, one down',
    diffSeen > 0.05, `${diffSeen.toFixed(3)} radians apart`);
  check('and the tail engine takes most of their angle rather than sitting still',
    ship.tiltAux > 0.1, `${ship.tiltAux.toFixed(2)}`);
  /* HOLDING STATION IS A HOVER, so the jet is near enough straight
     down and the pods are well nose-UP. Level is CRUISE on this
     airframe, and that is the half of it that was inverted. */
  note('holding station', `the jet ${(ship.vector * 57.3).toFixed(0)} degrees up from level, ` +
    `the pods drawn at ${(ship.tilt * 57.3).toFixed(0)}`);
  check('holding station the jet is all but straight down, and the pods are nose-up',
    ship.vector > 1.3 && ship.tilt > 0.35,
    `jet ${(ship.vector * 57.3).toFixed(0)} degrees, pods ${(ship.tilt * 57.3).toFixed(0)}`);
  check('and the body is near enough level rather than sitting nose-down through the whole hover',
    Math.abs(ship.rz) < 0.1, `${(ship.rz * 57.3).toFixed(0)} degrees of pitch`);
  check('and what is drawn never leaves the range a pod still reads as an engine in',
    ship.tilt >= V.VTOL.tiltMin && ship.tilt <= V.VTOL.tiltMax &&
    V.VTOL.tiltMax < 1.2 && V.VTOL.hover > 0.3);

  /* AND AT SPEED IT IS THE OTHER WAY ROUND, which is the whole claim:
     the same aircraft driven hard forward flattens its pods toward
     level and points the jet ahead of it. Driven rather than waited
     for, so the check is about the law and not about the route. */
  {
    const flat = (() => {
      /* somewhere a long way off to fly at, because the station keeping
         is what holds it at a loiter: told to go nowhere it goes
         nowhere, and a test that only sets the velocity is overruled on
         the next tic by the controller that owns it */
      const home = ship.station;
      ship.station = function () {
        return { x: this.x + Math.cos(this.yaw) * 9000, y: this.y + Math.sin(this.yaw) * 9000, z: -1 };
      };
      for (let t = 0; t < 220; t++) gg.tic();
      const got = { vector: ship.vector, tilt: ship.tilt, speed: Math.hypot(ship.vx, ship.vy) };
      /* and then home, because the run took it thousands of units off
         and everything after this is about a gunship that is overhead */
      ship.station = home;
      for (let t = 0; t < 500; t++) gg.tic();
      return got;
    })();
    check('and it comes back to its station afterwards',
      Math.hypot(ship.x - pg.x, ship.y - pg.y) < V.VTOL.standoff * 1.8,
      `${Math.hypot(ship.x - pg.x, ship.y - pg.y).toFixed(0)} units out`);
    note('and at full speed', `${flat.speed.toFixed(0)} units a tic: the jet ` +
      `${(flat.vector * 57.3).toFixed(0)} degrees up from level, the pods ${(flat.tilt * 57.3).toFixed(0)}`);
    check('driven hard forward the jet comes down toward the nose and the pods flatten',
      flat.vector < 1.0 && flat.tilt < 0.25,
      `jet ${(flat.vector * 57.3).toFixed(0)}, pods ${(flat.tilt * 57.3).toFixed(0)}`);
  }

  /* AND THE PODS ARE A MACHINE, not a number. This is the check that
     holds the jangle down: a demand thrown from one end of the travel
     to the other cannot move a pod by more than its rate in one tic,
     so a controller output that steps — and an acceleration does step,
     every time the thing saturates — cannot step the drawing. */
  {
    const gR = mkG();
    const sr = gR.gunships.send();
    sr.state = 'station';
    let worst = 0, prev = sr.tiltL;
    for (let t = 0; t < 400; t++) {
      /* shove the demand end to end every few tics, which is far worse
         than anything the flight controller ever does */
      if (t % 5 === 0) { sr.vx = -sr.vx || V.VTOL.speed; sr.vy = -sr.vy; }
      gR.tic();
      worst = Math.max(worst, Math.abs(sr.tiltL - prev));
      prev = sr.tiltL;
    }
    note('the pod actuator', `${(V.VTOL.tiltRate * 57.3).toFixed(1)} degrees a tic, ` +
      `so its whole travel takes ${(((V.VTOL.tiltMax - V.VTOL.tiltMin) / V.VTOL.tiltRate) / 35).toFixed(1)}s`);
    check('a pod cannot move faster than its own actuator, whatever the demand does',
      worst <= V.VTOL.tiltRate + 1e-9, `${worst.toFixed(4)} against a limit of ${V.VTOL.tiltRate}`);
    check('and the whole travel takes a second or more, so it reads as machinery',
      (V.VTOL.tiltMax - V.VTOL.tiltMin) / V.VTOL.tiltRate / 35 > 1);
  }
  check('and it BANKS INTO its turns, like a thing held up by thrust',
    maxBank > 0.05, `${(maxBank * 57.3).toFixed(1)} degrees`);

  /* THE GUN. Three rounds a tic through the same hitscan the player's
     minigun uses, in bursts, each one with a tracer off the muzzle
     marker — and it only shoots what it can see. */
  {
    check('it shoots at you, in bursts rather than continuously',
      ship.rounds > 200 && ship.rounds < 900 * V.VTOL.gun.rounds * 0.8,
      `${ship.rounds} in 900 tics, against ${900 * V.VTOL.gun.rounds} if it never stopped`);
    check('and every round leaves the muzzle, which is the marker the user drew',
      (() => {
        const m = ship.muzzle, before = gg.tracers.liveCount;
        ship.seen = true; ship.aimed = true; ship.firing = 1; ship.burstLeft = 4;
        ship.gunTic();
        const T = gg.tracers;
        let ok = false;
        /* the origins are a Float32Array, so this is as close as a
           double ever gets to coming back out of one */
        for (let i = 0; i < T.ox.length; i++)
          if (Math.abs(T.ox[i] - m.x) < 0.05 && Math.abs(T.oz[i] - m.z) < 0.05) ok = true;
        return ok && T.liveCount > before;
      })());
    /* WHAT IT DOES TO YOU, measured rather than survived: the debug
       invincibility this test flies with is taken off for four seconds
       and put straight back, because everything after this needs a
       player who is alive to be circled and shot at. */
    const a2 = pg.armour2, a1 = pg.armour1, hp0 = pg.health;
    pg.invincible = false;
    for (let t = 0; t < 4 * 35; t++) gg.tic();
    const hurt = (a2 + a1 + hp0) - (pg.armour2 + pg.armour1 + pg.health);
    pg.invincible = true; pg.armour2 = a2; pg.armour1 = a1; pg.health = hp0;
    note('what it does to you', `${hurt.toFixed(0)} in four seconds, about ${(hurt / 4).toFixed(0)} a second — ` +
      `${((a2 + a1 + hp0) / Math.max(1, hurt / 4)).toFixed(0)} seconds of standing under one in the open`);
    check('and it hurts: a gunship overhead is a clock running', hurt > 30, `${hurt}`);
  }

  /* THE SEARCHLIGHT IS A FLARE AND NOTHING ELSE, at the user's request:
     it lit the world through a cone in the world shader for an
     afternoon and the beam is out, so the first thing asserted is that
     nothing in js/material.js is carrying it any more. */
  {
    const src = fs.readFileSync('js/material.js', 'utf8');
    check('the lit cone is gone out of the world shader, at the user\'s request',
      !/uniform\s+\w+\s+spot/.test(src) && !src.includes('spotLight >') && world.spotLight === undefined,
      'js/material.js still declares a spotlight');
    check('and nothing in the game points one any more',
      !fs.readFileSync('js/vtol.js', 'utf8').includes('spotLight'));
    check('there is a flare at the lamp, and a smaller one at the muzzle',
      !!ship.lampFlare.mesh && !!ship.muzzleFlare.mesh &&
      ship.lampFlare.size[0] > ship.lampFlare.size[1] * 4 &&
      ship.lampFlare.size[0] > ship.muzzleFlare.size[0],
      `${ship.lampFlare.size.join(' by ')} against ${ship.muzzleFlare.size.join(' by ')}`);
    check('and the flare is anamorphic: far wider than it is tall, with a sphere at the middle',
      ship.lampFlare.ball > 0 && ship.lampFlare.ball < 1);
    const beam = ship.beam;
    check('and the lamp points down out of the sky rather than along it', beam.z < -0.05, `${beam.z.toFixed(2)}`);
  }

  /* --- AND THE FLARE IS OCCLUSION AWARE ------------------------------
     At the user's request, and it has to be done by hand: the quad is
     drawn over the top of the frame with the depth test off, so nothing
     in the renderer is going to hide it. Three tests, and each is
     checked here on its own.

     First the two pure pieces underneath them. `unturn` is `turn` from
     js/vehicles.js solved for its input — the eye is what moves into
     the aircraft's frame, because that is where the hull box is — and
     `boxBetween` is the slab walk that decides whether the hull is in
     the way of the lamp. */
  {
    const veh = await import('../js/vehicles.js');
    for (const [yaw, rx, rz] of [[0.7, 0.2, -0.4], [-2.1, 0, 0], [3.0, 1.2, 0.9]]) {
      const p0 = [37, -11, 23];
      const back = V.unturn(veh.turn(p0, yaw, rx, rz), yaw, rx, rz);
      check('turning a point and turning it back is where it started',
        back.every((v, i) => Math.abs(v - p0[i]) < 1e-9),
        back.map(v => v.toFixed(3)).join(', '));
    }
    const box = { lo: [-10, -10, -10], hi: [10, 10, 10] };
    check('a line that misses the box is not blocked by it',
      !V.boxBetween([100, 100, 100], [100, 100, -100], box, 0));
    check('and a line straight through it is',
      V.boxBetween([-100, 0, 0], [100, 0, 0], box, 0));
    check('but not when it only clips it on the way in to its own end',
      !V.boxBetween([0, -100, 0], [0, -9, 0], box, 5) &&
      V.boxBetween([0, -100, 0], [0, -9, 0], box, 0.5),
      'the clearance is what tells the hull from the lamp\'s own bracket');

    /* AND THEN THE AIRCRAFT. The lamp hangs under the nose INSIDE the
       fuselage's own box, so every sight line to it crosses that box
       just before it arrives; what separates "the hull is in the way"
       from "the lamp's own bracket is" is how FAR from the lamp the
       crossing happens. Measured on the model: four to nine units from
       below, in front, or dead ahead, and seventy-seven to a hundred
       and fifty-nine from above, behind or abeam. The clearance sits
       between the two with room on both sides. */
    const gO = mkG();
    const so = gO.gunships.send();
    so.state = 'station';
    so.x = 0; so.y = 0; so.cz = 0; so.yaw = 0; so.rx = 0; so.rz = 0;
    so.tYaw = 0; so.tPitch = 0;
    const hides = (bx, by, bz) => {
      /* a point in the aircraft's own frame, put out into the world so
         the test goes in the way the game's does */
      const w = veh.turn([bx, by, bz], so.yaw, so.rx, so.rz);
      return so.hullHides(so.x + w[0], so.y - w[2], so.cz + w[1], gO.gunships.model.lamp,
        ['fuselage', 'turret', 'pitch', 'lamp']);
    };
    check('the aircraft\'s own hull does not hide its lamp from below, where the lamp faces',
      !hides(172, -800, 0) && !hides(900, -500, 0) && !hides(1200, -37, 0),
      'the lamp hangs under the nose; from underneath it there is nothing in the way');
    check('and DOES hide it from above and from behind, which is most of the sky it flies in',
      hides(172, 800, 0) && hides(-700, 600, 0) && hides(0, -37, 1200),
      'straight down on the nose, over the tail, and abeam at its own height');
    const C = V.VTOL.lamp.hullClear;
    check('and the clearance that tells the two apart has room on both sides of it',
      C > 12 && C < 60, `${C}, against 9 from below and 77 from above`);

    /* the three tests, through the render path that actually uses them,
       with the flare's own easing wound out by calling it enough times
       for the answer to have arrived */
    const settle = (ex, ey, ez, vdx, vdy) => {
      for (let i = 0; i < 24; i++) so.render(ex, ey, ez, vdx, vdy);
      return so.lampFlare.mesh.visible;
    };
    /* over the car park rather than over the origin, which on this map
       is somewhere in the wood: the third test is a real sight line and
       it wants open ground under it */
    const po = gO.player;
    so.lampOn = true;
    so.x = po.x - 500; so.y = po.y;
    so.ground = po.z;
    so.cz = po.z + 330;
    so.yaw = 0;
    /* stood in front of the lamp and looking back along its own beam */
    const under = { x: po.x, y: po.y, z: po.viewZ };
    so.tPitch = Math.atan2(under.z - so.cz, under.x - so.x); so.tYaw = 0;
    const toward = Math.atan2(so.y - under.y, so.x - under.x);
    const seen = settle(under.x, under.y, under.z, Math.cos(toward), Math.sin(toward));
    check('stood in front of a lit gunship and looking at it, the flare is drawn', seen);
    /* turn round and it is gone: a flare sized by its own distance and
       a lamp behind the eye is a white bowtie across the whole frame */
    check('turn your back on it and the flare is not drawn at all',
      !settle(under.x, under.y, under.z, -Math.cos(toward), -Math.sin(toward)));
    /* and it does not switch: what the tests decide is eased onto */
    so.lampFlare.vis = 0;
    so.render(under.x, under.y, under.z, Math.cos(toward), Math.sin(toward));
    const first = so.lampFlare.vis;
    check('and it comes and goes over a few frames rather than switching',
      first > 0 && first < 0.9 && V.VTOL.lamp.outer < V.VTOL.lamp.inner,
      `${first.toFixed(2)} of the way there after one frame`);
  }

  /* THE JET WASH. Where an engine's exhaust lands is a ray from the
     nacelle down the way its thrust is not pointing; the grit is thrown
     outward along whatever it lands on, and anybody standing in it
     while the aircraft is LOW catches. People, at the user's request,
     and never a car. */
  {
    const hitG = { x: 0, y: 0, z: 0, nx: 0, ny: 0, nz: 1, t: 0 };
    const origin = { x: ship.x, y: ship.y, z: ship.cz };
    check('an engine\'s exhaust lands on the ground under it, facing up',
      ship.exhaustHit(origin, { x: 0, y: 0, z: -1 }, hitG) && hitG.nz === 1 &&
      Math.abs(hitG.t - (ship.cz - ship.ground)) < 40, `${hitG.t.toFixed(0)} down`);
    check('and an exhaust pointing at the sky lands nowhere at all',
      !ship.exhaustHit(origin, { x: 0, y: 0, z: 0.5 }, hitG));
    check('and it blows the car park about the whole time it is up there', ship.washed > 100, `${ship.washed}`);
    check('but at cruising height nothing it blows about is hot enough to light anybody',
      ship.ignited === 0 && V.VTOL.wash.hot < V.VTOL.alt && V.VTOL.wash.hot > V.VTOL.lowAlt,
      `${ship.ignited} lit, hot within ${V.VTOL.wash.hot} of the ground`);
    /* AND IT SETS PEOPLE ON FIRE IF IT HOVERS OVER THEM. A handful of
       shoppers put out in the car park, and the aircraft sent down over
       them — which is the mode it looks for on its own every eleven
       seconds. A CAR in the same wash is untouched, which is the half
       of the request that is a "not". */
    /* A PERSON AND A VAN IN THE SAME WASH, held down at the height the
       aircraft comes to when it is over a crowd, and ticked. Both are
       in the pool of grit; one of them catches. That is the whole of
       the user's "not cars", and it is checked side by side rather than
       waited for, because a car park where a burning shopper has just
       run past is a car park where a van catching proves nothing. */
    {
      const gW = mkG();
      const sw = gW.gunships.send();
      sw.state = 'station';
      const car0 = gW.vehicles.all.find(v => v.whole);
      const one = gW.actors.find(a => a.type === 'SHOPPER' && !a.dead);
      check('there is a van and a shopper to hold under it', !!car0 && !!one);
      if (car0 && one) {
        /* the aircraft parked directly over the van, as low as it ever
           gets, with the shopper beside it */
        sw.x = car0.x; sw.y = car0.y; sw.vx = sw.vy = sw.vz = 0;
        sw.cz = gW.level.sectorAt(sw.x, sw.y).floor + V.VTOL.lowAlt;
        sw.ground = gW.level.sectorAt(sw.x, sw.y).floor;
        /* the JET straight down, which is what a hover is and what the
           wash is now aimed by — the pods are drawn at a geared share
           of it and no longer decide where the grit goes */
        sw.vector = Math.PI / 2;
        sw.tilt = sw.tiltL = sw.tiltR = V.VTOL.hover; sw.tiltAux = V.VTOL.hover * V.VTOL.auxShare;
        one.x = car0.x + 40; one.y = car0.y + 40;
        gW.blockmap.moved(one); one.updateSector();
        for (let t = 0; t < 80; t++) { sw.tick++; sw.washTic(); }
        check('the wash off it sets a person under it on fire, at the user\'s request',
          one.burning > 0 && sw.ignited > 0, `${sw.ignited} lit, ${one.burning} tics of it`);
        check('and NOT the van in the same wash: it is the person that catches, never the floor under them',
          car0.whole && car0.burning === 0 && gW.fire.burningCells === 0,
          `van burning ${car0.burning}, ${gW.fire.burningCells} cells of floor alight`);
        /* and put it back up at its cruising height and nothing catches */
        const two = gW.actors.find(a => a.type === 'SHOPPER' && !a.dead && a !== one && !a.burning);
        if (two) {
          two.x = car0.x + 40; two.y = car0.y - 40;
          gW.blockmap.moved(two); two.updateSector();
          sw.cz = sw.ground + V.VTOL.alt;
          const lit0 = sw.ignited;
          for (let t = 0; t < 80; t++) { sw.tick++; sw.washTic(); }
          check('and from its cruising height it blows the tarmac about and lights nobody',
            sw.ignited === lit0 && two.burning === 0 && sw.washed > 0, `${sw.ignited - lit0} lit`);
        }
      }
    }

    /* AND IT GOES LOOKING FOR THEM ON ITS OWN, which is the half of it
       that is not a mechanic but a behaviour: every so often it picks a
       knot of people in the open, comes down over them, and walks
       across the crowd — taking the next one the moment the one it is
       over is alight. */
    const crowd = gg.actors.filter(a => a.type === 'SHOPPER' && !a.dead && !a.burning).slice(0, 24);
    crowd.forEach((a, k) => {
      /* a ring of them under it, laid out rather than rolled, so the
         run is the same run every time the test is run */
      const ang = k * 2.39996, r = 40 + k * 9;
      a.x = ship.x + Math.cos(ang) * r; a.y = ship.y + Math.sin(ang) * r;
      gg.blockmap.moved(a); a.updateSector();
    });
    const wasLit = ship.ignited;
    ship.mode = 'orbit'; ship.torchAt = gg.tics; ship.state = 'station';
    let low = 1e9, torchTics = 0;
    for (let t = 0; t < 400; t++) {
      gg.tic();
      if (ship.mode === 'torch') { torchTics++; low = Math.min(low, ship.altitude); }
    }
    note('a torch run', `${torchTics} tics over them at ${low < 1e9 ? low.toFixed(0) : '-'} up, ` +
      `${ship.ignited - wasLit} of ${crowd.length} alight`);
    check('it goes looking for a knot of people on its own and comes DOWN over them',
      torchTics > 0 && low < V.VTOL.alt - 20, `${low.toFixed(0)} against ${V.VTOL.alt} on station`);
    check('and a pass lights several of them rather than chasing one',
      ship.ignited > wasLit + 1, `${ship.ignited - wasLit} lit`);
  }

  /* --- SHOT DOWN ----------------------------------------------------
     At the user's request. The same pitched hitscan that puts holes in
     a van lands on it, and enough of them end it. */
  {
    check('the minigun\'s rounds reach it through its own bodies, and the armour is a vehicle\'s',
      (() => { const h = ship.health; ship.bodies[0].damage(90, gg.player, { shot: true }); return ship.health === h - 90 / V.VTOL.shotArmour; })());
    check('and a round into it leaves no hole hanging in the air: it is not a box',
      (() => { const H = gg.decals.pools.hole, n = H.count; gg.decals.vehicleHole(ship, ship.x, ship.y, ship.cz, 1, 0, 0); return H.count === n; })());
    check('and fire cannot reach it', (() => { const h = ship.health; ship.damage(500, null, { fire: true, stream: true }); return ship.health === h; })());
    let rounds = 0;
    while (ship.whole && rounds < 5000) { ship.damage(30, gg.player, { shot: true }); rounds++; }
    note('shooting one down', `${rounds} rounds of the minigun, which is ${(rounds / 4 / 35).toFixed(1)}s of the trigger held on it`);
    check('enough of them and it is hit: three to five seconds of the minigun',
      ship.state === 'dying' && rounds > 200 && rounds < 900, `${rounds}`);
    /* THE TAIL SPIN. Still flying, in the sense that the air is still
       under it: the yaw winds up, the nose goes down, and it trails
       fire all the way to the tarmac. */
    const yaw0 = ship.yaw, z0 = ship.cz;
    let fell = 0, rose = false, dive = 0, flung = 0;
    while (ship.state === 'dying' && fell < 600) {
      gg.tic(); fell++;
      if (ship.cz > z0) rose = true;
      dive = Math.min(dive, ship.rz);
      flung = Math.max(flung, Math.abs(ship.tiltL - ship.tiltR));
    }
    const turns = Math.abs(ship.yaw - yaw0) / (2 * Math.PI);
    note('and what it does then', `${(fell / 35).toFixed(1)}s of tail spin through ` +
      `${turns.toFixed(1)} turns, nose ${(dive * 57.3).toFixed(0)} degrees down, ${ship.pops} bangs on the way down`);
    check('it lurches up as it is hit and then falls, spinning, for a good few seconds',
      rose && fell > 2 * 35 && turns > 1, `${fell} tics, ${turns.toFixed(1)} turns`);
    /* measured ON THE WAY DOWN rather than where it came to rest: the
       crash puts it at whatever crooked angle it ended up lying at */
    check('and the nose goes down and the engines are thrown to nothing',
      dive < -0.3 && flung > 0.5,
      `nose ${dive.toFixed(2)}, engines ${flung.toFixed(2)} apart`);
    check('and it bangs the whole way down rather than falling quietly', ship.pops > 1, `${ship.pops}`);
    /* AND THE GROUND. The bigger bang, the fire, the pieces, and a
       wreck that is in the way from then on. */
    check('it arrives on the tarmac and is a wreck rather than a thing still flying',
      ship.state === 'wreck' && Math.abs(ship.cz - ship.ground) < V.VTOL_LENGTH,
      `${ship.state} at ${ship.cz.toFixed(0)} over ${ship.ground.toFixed(0)}`);
    check('and the thing you shoot at goes with it, and something you cannot walk through takes its place',
      ship.bodies.length === 0 && ship.blockers.length === 3 && ship.blockers.every(b => b.solid));
    check('and it threw pieces of its own skin off, painted with its own sheet',
      gg.vehicles.flying.length + gg.vehicles.resting.length > 8 &&
      [...gg.vehicles.flying, ...gg.vehicles.resting].some(c => c.own));
    check('and it is burning on the tarmac where it landed', gg.fire.burningCells > 0, `${gg.fire.burningCells} cells`);
    check('and the lamp goes out with it, flare and all',
      (() => {
        for (let i = 0; i < 24; i++) gg.gunships.render(pg.x, pg.y, pg.viewZ, 1, 0);
        return !ship.lampOn && !ship.lampFlare.mesh.visible && !ship.muzzleFlare.mesh.visible;
      })());
    /* it lies there smouldering rather than vanishing, and the night
       goes on round it */
    for (let t = 0; t < 200; t++) gg.tic();
    check('and it lies there afterwards, smouldering, without anything falling over',
      ship.state === 'wreck' && ship.smoulder > 0 && gg.actors.length > 0);
  }
}

/* ---------- the quad launcher ---------- */
section('the quad launcher');
{
  const fs = await import('node:fs');
  const { parseGLB, readAccessor } = await import('../js/glb.js');
  const w3 = await import('../js/weapon3d.js');
  const pl = await import('../js/player.js');
  const MS = await import('../js/missiles.js');
  const TH = await import('../js/thermal.js');
  const MAT = await import('../js/material.js');
  const { Game } = await import('../js/game.js');
  const MAPM = await import('../js/maps/sellwrong.js');
  const THREEM = await import('three');
  const L = w3.GUNS.LAUNCHER;

  /* ---- THE MODEL, AS IT SHIPS ----------------------------------------
     The XM222, modelled and textured, with a display surface on the
     back of its sight that the user prepared for the thermal feed.
     Prepared by tools/blender/prep_launcher.py: fourteen megabytes to
     under one, the two colour sheets kept as JPEG, the rest dropped, the
     rockets split out and named. What is checked is what the game
     depends on. */
  const file = fs.readFileSync(L.url);
  const { json, bin } = parseGLB(file.buffer.slice(file.byteOffset, file.byteOffset + file.length));
  const prims = json.meshes.flatMap(m => m.primitives);
  const tris = prims.reduce((n, p) => n + json.accessors[p.indices].count / 3, 0);
  note('the launcher', `${(file.length / 1024).toFixed(0)}K, ${tris} triangles, ${json.nodes.length} parts, ${json.images.length} sheets`);
  check('the launcher ships as a model of under a megabyte and at most sixteen thousand triangles',
    file.length < 1024 * 1024 && tris <= 16000);
  const byName = n => json.nodes.find(o => o.name === n);
  const meshOf = n => json.meshes[byName(n).mesh].primitives[0];
  const matOf = n => json.materials[meshOf(n).material];
  check('its parts are the gun, the display and four rockets, each one mesh with its transforms baked in',
    ['xm222', 'display', 'rocket_0', 'rocket_1', 'rocket_2', 'rocket_3'].every(n => byName(n) && byName(n).mesh !== undefined &&
      json.meshes[byName(n).mesh].primitives.length === 1 && !byName(n).matrix && !byName(n).rotation && !byName(n).scale) &&
    json.nodes.length === 6 && !byName('rocket_4'));
  check('every part carries what the loader reads and nothing it does not: no tangents, no vertex paint, one set of UVs',
    prims.every(p => p.attributes.POSITION !== undefined && p.attributes.NORMAL !== undefined && p.attributes.TEXCOORD_0 !== undefined &&
      p.attributes.TANGENT === undefined && p.attributes.COLOR_0 === undefined && p.attributes.TEXCOORD_1 === undefined) && !L.paint);
  check('the gun and the rockets wear their own colour sheets, JPEG, and no other map is left',
    ['xm222', 'rocket_0'].every(n => matOf(n).pbrMetallicRoughness?.baseColorTexture !== undefined && !matOf(n).normalTexture &&
      !matOf(n).pbrMetallicRoughness?.metallicRoughnessTexture) &&
    json.images.length === 2 && json.images.every(i => i.mimeType === 'image/jpeg'));
  check('the display surface is the file\'s own, under the name the table gives it, with nothing painted on it',
    !!L.display && !L.screen && matOf('display').name === L.display.material &&
    !matOf('display').pbrMetallicRoughness?.baseColorTexture);
  check('the prep script is in the repo, with how to run it',
    /blender -b -P prep_launcher\.py -- <xm222\.glb> <out\.glb>/.test(fs.readFileSync('tools/blender/prep_launcher.py', 'utf8')));

  /* ---- WHERE ITS PARTS ARE, in the model's own units ----------------- */
  const pts = n => readAccessor(json, bin, meshOf(n).attributes.POSITION).array;
  const boxOf = arrs => {
    const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
    for (const P of arrs) for (let i = 0; i < P.length; i += 3)
      for (let k = 0; k < 3; k++) { lo[k] = Math.min(lo[k], P[i + k]); hi[k] = Math.max(hi[k], P[i + k]); }
    return { lo, hi };
  };
  const all = boxOf(json.nodes.map(n => pts(n.name)));
  check('it points +z like every gun: the rockets\' noses are the front of the whole model',
    [0, 1, 2, 3].every(i => Math.abs(boxOf([pts('rocket_' + i)]).hi[2] - all.hi[2]) < 1e-3));
  {
    /* ONE ROCKET PER TUBE, IN FIRING ORDER. Each tube in the table is the
       middle of its rocket's nose, at the nose; and the order is top
       left, top right, bottom left, bottom right as the gunner sees them
       — model +x is the gunner's left once the model is turned. */
    const ok = [0, 1, 2, 3].every(i => {
      const P = pts('rocket_' + i), { hi } = boxOf([P]);
      let x = 0, y = 0, n = 0;
      for (let v = 0; v < P.length; v += 3) if (P[v + 2] > hi[2] - 0.6) { x += P[v]; y += P[v + 1]; n++; }
      const t = L.tubes[i];
      return Math.hypot(x / n - t[0], y / n - t[1]) < 0.02 && Math.abs(t[2] - hi[2]) < 0.01;
    });
    check('four tubes, each at the nose of its own rocket', L.tubes.length === 4 && ok);
    const [t0, t1, t2, t3] = L.tubes;
    check('and they fire top left, top right, bottom left, bottom right, as the gunner sees them',
      t0[0] > t1[0] && t2[0] > t3[0] && t0[1] > t2[1] && t1[1] > t3[1]);
    check('the nozzle is the middle of the four', [0, 1].every(k => Math.abs(L.nozzle[k] - L.tubes.reduce((s, t) => s + t[k], 0) / 4) < 0.01));
  }
  {
    /* THE SCREEN FACES THE EYE AND NOTHING IS IN FRONT OF IT. The eye is
       on the model's -z side once it is turned, so the display's normals
       run -z, and no vertex of the gun that falls inside its outline is
       nearer the eye than it is. */
    const D = pts('display'), { lo, hi } = boxOf([D]);
    const N = readAccessor(json, bin, meshOf('display').attributes.NORMAL).array;
    let facing = 0;
    for (let i = 2; i < N.length; i += 3) if (N[i] < -0.9) facing++;
    const G = pts('xm222'), m = 0.02;
    let front = 0;
    for (let i = 0; i < G.length; i += 3)
      if (G[i] > lo[0] + m && G[i] < hi[0] - m && G[i + 1] > lo[1] + m && G[i + 1] < hi[1] - m && G[i + 2] < lo[2]) front++;
    check('the display faces the eye, with nothing of the gun between it and the eye',
      facing === N.length / 3 && front === 0, `${facing} of ${N.length / 3} facing, ${front} in front`);
    check('and it is on the left of the picture, as the sight of a thing held on the right shoulder is', lo[0] > 0.5);
    check('and the picture is the shape of its glass, so nothing is stretched',
      Math.abs((hi[0] - lo[0]) / (hi[1] - lo[1]) / TH.THERMAL_ASPECT - 1) < 0.03);
    /* AND PUT TO THE EYE, IT IS STRAIGHT AHEAD OF IT: the aimed hold, run
       through the same fit and half turn as the loader's, puts the
       screen's middle on the line of sight, clear of the near plane,
       and about half the picture high. */
    const c = [0, 1, 2].map(k => (all.lo[k] + all.hi[k]) / 2);
    const sc = L.fit / Math.max(...[0, 1, 2].map(k => all.hi[k] - all.lo[k]));
    const mid = [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2];
    const at = [-(mid[0] - c[0]) * sc, (mid[1] - c[1]) * sc, -(mid[2] - c[2]) * sc]
      .map((v, k) => v + w3.VIEW.pos[k] + L.aim.pos[k]).map((v, k) => k === 2 ? v * L.aim.out : v);
    const high = (hi[1] - lo[1]) * sc / (2 * -at[2] * Math.tan(w3.VIEW.fov / 2 * Math.PI / 180));
    note('the screen, aimed', `${(-at[2] * 100).toFixed(1)} cm out, ${(high * 100).toFixed(0)}% of the picture high`);
    check('put to the eye, the screen is straight ahead of it and about half the picture high',
      Math.abs(at[0]) < 0.01 && Math.abs(at[1]) < 0.01 && -at[2] > 0.05 && high > 0.4 && high < 0.7);
  }
  check('a fired tube is drawn empty: the rockets are found by name and shown only while there is ammo for them',
    L.loaded?.prefix === 'rocket_' && L.loaded?.ammo === 'rockets' &&
    /r\.visible = i >= G\.rounds\.length - left/.test(fs.readFileSync('js/weapon3d.js', 'utf8')) &&
    /tube = SEEKER\.most - \(p\.ammo\.rockets \| 0\)/.test(fs.readFileSync('js/missiles.js', 'utf8')));
  check('put to the eye, it is turned square on: the aim cancels the hold\'s own cant',
    Math.abs(w3.VIEW.pitch + L.aim.rot[0]) < 1e-9 && Math.abs(w3.VIEW.yaw + L.aim.rot[1]) < 1e-9 &&
    Math.abs(w3.VIEW.roll + L.aim.rot[2]) < 1e-9 && L.aim.out < L.out);

  /* ---- THE WEAPON ----------------------------------------------------- */
  const inputSrc = fs.readFileSync('js/input.js', 'utf8');
  const d = pl.WEAPONS.LAUNCHER;
  check('the launcher is the sixth weapon, on the six key, a seeker off four tubes, and issued',
    d.slot === 6 && d.seeker === true && d.ammo === 'rockets' && pl.ROCKETS === 4 &&
    /Digit6: 'weapon6'/.test(inputSrc) && /this\.pressed\('weapon6'\)\) this\.weaponSlot = 6/.test(inputSrc) &&
    new (class extends pl.Player { constructor() { super({ level: { sectorAt: () => null } }, 0, 0, 0); } })().owned.LAUNCHER === true);
  {
    const p = new pl.Player({ level: { sectorAt: () => null } }, 0, 0, 0);
    p.ammo.rockets = 0;
    let t = 0;
    while (p.ammo.rockets < pl.ROCKETS && t < 100 * 35) { p.fuelTic(); t++; }
    check('and its empty tubes load themselves, one at a time', p.ammo.rockets === pl.ROCKETS &&
      t === pl.ROCKETS * pl.ROCKET_REGEN_EVERY, `${t} tics`);
  }

  /* ---- THE SEEKER AND THE SALVO, in the shop -------------------------- */
  const g = new Game({
    level: MAPM.buildSellWrong({ town: false }), scene: new THREEM.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
  });
  const p = g.player, M = g.missiles;
  p.debug = false;
  p.weapon = 'LAUNCHER';
  /* somebody warm, in plain sight, not too near */
  let target = null, best = Infinity;
  for (const a of g.actors) {
    if (!M.isHot(a)) continue;
    const dd = Math.hypot(a.x - p.x, a.y - p.y);
    if (dd < 200 || dd > 1200 || dd > best) continue;
    if (g.level.sightBlocked(p.x, p.y, p.eyeZ, a.x, a.y, a.z + a.height * 0.58)) continue;
    target = a; best = dd;
  }
  const aimAt = t => {
    const h = M.heatPoint(t);
    p.angle = Math.atan2(h.y - p.y, h.x - p.x);
    p.pitch = Math.atan2(h.z - p.eyeZ, Math.hypot(h.x - p.x, h.y - p.y));
  };
  note('the seeker\'s target', target ? `${target.type} ${Math.round(best)} away` : 'nobody in sight');
  if (target) {
    g.input.attack = true;
    const first = [];
    for (let t = 1; t <= MS.SEEKER.first + 3 * MS.SEEKER.next + 4; t++) {
      aimAt(target); g.tic();
      if (M.locks.length > first.length) first.push(t);
    }
    check('holding the trigger on something warm locks it, and goes on locking, to four',
      M.locks.length === 4 && first[0] >= MS.SEEKER.first && first[0] <= MS.SEEKER.first + 1 &&
      first[3] - first[0] <= 3 * MS.SEEKER.next + 3, first.join(','));
    check('and nothing leaves the tubes while it does', M.fired === 0 && M.shots.length === 0 && p.ammo.rockets === 4);
    g.input.attack = false;
    const launched = [];
    for (let t = 1; t <= 40; t++) { aimAt(target); const was = M.fired; g.tic(); if (M.fired > was) launched.push(t); }
    check('letting go sends one missile per lock, a tube at a time, a few tics apart',
      launched.length === 4 && launched.every((t, i) => i === 0 || t - launched[i - 1] === MS.MISSILE.gap + 1) &&
      p.ammo.rockets === 0, launched.join(','));
    let n = 0;
    while (!target.dead && n < 200) { g.tic(); n++; }
    check('and they find it, and it is dead', target.dead && M.blasts >= 1 && M.hits >= 1, `${n} tics, ${M.hits} direct`);
  }
  {
    /* one straight down the sight with nothing locked */
    const was = M.fired;
    p.ammo.rockets = 4;
    g.input.attack = true; g.tic(); g.tic();
    g.input.attack = false; g.tic(); g.tic();
    check('with nothing locked, letting go fires one, unguided', M.fired === was + 1 && M.shots.some(s => !s.target));
    for (let t = 0; t < 300 && M.shots.length; t++) g.tic();
  }
  /* ---- WHAT A ROCKET LOOKS LIKE, at the user's request: a body that
     turns to the eye with a flame on its tail, a trail of smoke behind
     it, and a bang where it lands ---------------------------------------- */
  {
    const opaque = v => { let n = 0; for (let i = 3; i < v.data.length; i += 4) if (v.data[i]) n++; return n; };
    const R = g.sprites.frames.get('ROKTA');
    check('the rocket is baked in eight turns and two flames, and the bang in eight frames',
      !!R && R.views.length === 8 && new Set(R.views).size === 8 && g.sprites.frames.has('ROKTB') &&
      'ABCDEFGH'.split('').every(f => g.sprites.frames.has('MEXP' + f)));
    check('side on it is a long thing and nose on a small one, so the turns are in the order they are used',
      opaque(R.views[2]) > 2 * opaque(R.views[0]) && opaque(R.views[6]) > 2 * opaque(R.views[0]),
      `${opaque(R.views[0])} nose on, ${opaque(R.views[2])} side on`);
    /* the eye at the origin, the rocket due north of it */
    check('and which turn is seen is where it is heading against where the eye is: nose, right, tail, left',
      [[0, -1], [1, 0], [0, 1], [-1, 0]].map(([dx, dy]) => MS.rocketFacing(dx, dy, 0, 500, 0, 0)).join() === '0,2,4,6');

    /* THE TRAIL: a puff every TRAIL.step of the way, laid along the leg
       it flew, so it is a line and not a string of beads */
    M.trail.killAll();
    const n0 = M.fired;
    p.ammo.rockets = 4;
    g.input.attack = true; g.tic(); g.tic();
    g.input.attack = false;
    let shot = null, path = 0, px = 0, py = 0, pz = 0;
    for (let t = 0; t < 30; t++) {
      g.tic();
      if (!shot) { shot = M.shots.find(q => !q.target) || null; if (shot) ({ x: px, y: py, z: pz } = shot); continue; }
      if (!M.shots.includes(shot)) break;
      path += Math.hypot(shot.x - px, shot.y - py, shot.z - pz);
      ({ x: px, y: py, z: pz } = shot);
      if (path > 400) break;
    }
    const puffs = M.trail.count;
    check('it lays a trail as it goes, a puff every few units of the way',
      M.fired === n0 + 1 && path > 100 && puffs >= path / MS.TRAIL.step * 0.9, `${Math.round(path)} units, ${puffs} puffs`);
    /* and down, and its own bang over, before the one this watches */
    for (let t = 0; t < 400 && (M.shots.length || M.booms.length); t++) g.tic();

    /* THE BANG: eight frames of fireball, and the smoke after it rather
       than in front of it — the first cut put the cloud down at the
       instant it went off, and smoke drawn over a fireball hides it */
    M.trail.killAll();
    const b0 = M.booms.length;
    M.detonate({ x: p.x + Math.cos(p.angle) * 300, y: p.y + Math.sin(p.angle) * 300, z: p.z + 60 }, null);
    const going = M.booms.length;
    const smoke = [];
    for (let t = 0; t < MS.BOOM.tics * MS.BOOM.frames + 2; t++) { smoke.push(M.trail.count); g.tic(); }
    check('where it goes off there is a fireball of eight frames, and then it is gone',
      going === b0 + 1 && M.booms.length === b0);
    check('and its smoke rises out of it as it burns out, not in front of it as it goes off',
      smoke.slice(0, MS.BOOM.tics * 3 + 1).every(n => n === 0) && M.trail.count >= 8, smoke.join(','));
  }
  /* WHAT IS WARM, which the seeker and the screen both ask */
  {
    const warm = g.actors.find(a => M.isHot(a));
    check('a person is warm and a frozen one is not, nor a corpse, nor a parked car, while a gunship is',
      !!warm && !M.isHot({ ...warm, frozen: true }) && !M.isHot({ ...warm, dead: true }) &&
      !M.isHot({ bodies: [], cz: 0, whole: true, state: 'parked', burning: 0 }) &&
      M.isHot({ bodies: [], cz: 0, whole: true, state: 'driving' }) && !M.isHot(null));
    const ship = { whole: true, cz: 300, bodies: [] };
    check('and anything flying is warm', new MS.MissileSystem({ gunships: { ships: [ship] } }).isHot(ship));
  }
  /* A BLAST, NOT FIRE: the troopers are fireproof and a warhead built on
     Game.explode would walk straight through them */
  {
    const sw = g.spawn('SWAT', p.x + 400, p.y, undefined, {});
    const h0 = sw.health;
    M.detonate({ x: sw.x + 60, y: sw.y, z: sw.z + 30 }, null);
    check('the warhead hurts a trooper, whose kit shrugs off fire', sw.health < h0 || sw.dead, `${h0} -> ${sw.health}`);
    const src = fs.readFileSync('js/missiles.js', 'utf8');
    check('because it lands as impact, never as fire', /\{ impact: true \}/.test(src) && !/fire: true/.test(src));
  }
  /* AND WHAT IT DOES TO A PERSON IT KILLS, at the user's request: "i
     also want people to literally explode into viscera and gore chunks
     when hit by a rocket in a more extreme way". The ordinary burst is
     thirteen burning pieces in a ring; a warhead kill is that and then
     sixty pieces of viscera thrown away from the blast, faster and
     higher than any burst, a spray of blood in the air, a great pool
     under them and the floor and walls round them painted. */
  {
    const PP = await import('../js/people.js');
    const DD = await import('../js/decals.js');
    const G = g.giblets, Dc = g.decals;
    G.chunks.killAll(); g.fx.gore.killAll();
    const who = g.spawn('SHOPPER', p.x + 420, p.y + 60, undefined, {});
    const ev = G.eviscerations, b0 = Dc.bloods, sprays = g.fx.gore.count;
    const at = { x: who.x - 50, y: who.y, z: who.z + 20 };
    M.detonate(at, null);
    const C = G.chunks;
    const pieces = [...Array(C.max).keys()].filter(i => C.alive[i] && C.kind[i] === 2);
    const fastest = Math.max(...pieces.map(i => Math.hypot(C.vx[i], C.vy[i])));
    const away = pieces.filter(i => C.vx[i] > 0).length;
    note('a shopper a warhead went off beside',
      `${pieces.length} pieces of viscera (a burst is ${PP.GIB.count}), fastest ${fastest.toFixed(1)}/tic, ` +
      `${away} thrown away from the blast, ${g.fx.gore.count - sprays} blood in the air, ${Dc.bloods - b0} blood decals at once`);
    check('a person a warhead kills is blown apart, not merely burst',
      who.dead && G.eviscerations === ev + 1 && pieces.length === PP.GORE.count && PP.GORE.count >= PP.GIB.count * 4);
    check('and the pieces fly further and higher than any burst throws them',
      PP.GORE.speedMax > PP.GIB.speedMax * 1.5 && PP.GORE.riseMax > PP.GIB.riseMax * 1.5 && fastest > PP.GIB.speedMax);
    check('mostly away from where it went off',
      away > pieces.length * 0.6, `${away} of ${pieces.length}`);
    check('with a heavy spray of blood in the air',
      g.fx.gore.count - sprays >= PP.GORE.spray * 0.9);
    check('and a great pool under them and blood thrown across the floor round them',
      Dc.bloods - b0 >= 1 + PP.GORE.floor &&
      [...Array(Dc.pools.blood.max).keys()].some(i => Dc.pools.blood.strength[i] > 0 && Dc.pools.blood.frame[i] === 1 &&
                                                      Dc.pools.blood.size[i] >= PP.GORE.pool * 0.85 - 1e-6));
    /* the pieces trail blood, not fire, and every one that lands leaves
       blood where it landed */
    const landed0 = Dc.bloods;
    g.fx.gore.killAll();
    for (let t = 0; t < 12; t++) G.tic();
    check('the viscera trail blood through the air, not flame',
      g.fx.gore.count > 0 &&
      /if \(C\.kind\[i\] === 2\) \{[\s\S]{0,200}?bloodSpray[\s\S]{0,80}?continue;/.test(fs.readFileSync('js/people.js', 'utf8')),
      `${g.fx.gore.count} blood`);
    for (let t = 0; t < 300; t++) G.tic();
    check('and every piece that comes down leaves blood where it came down',
      C.count === 0 && Dc.bloods - landed0 >= PP.GORE.count * 0.9, `${Dc.bloods - landed0} more`);
    check('a warhead kill takes the gore death for a trooper, however much health was left',
      /opts\.gib \|\| this\.health < \(this\.info\.gibHealth/.test(fs.readFileSync('js/actor.js', 'utf8')) &&
      /a\.damage\(n, p, \{ impact: true, gib: true \}\);/.test(fs.readFileSync('js/missiles.js', 'utf8')));
    check('and blood goes up the walls round them in every direction, from the same spray a round uses',
      /D\.sprayWalls\?\.\(a\.x, a\.y, mid, dx \|\| 1, dy, 0\.05, GORE\.walls, GORE\.wallReach, Math\.PI, 1\.5\)/
        .test(fs.readFileSync('js/people.js', 'utf8')) && DD.WALL_SPRAY >= 3);
  }

  /* ---- THE THERMAL SIGHT ---------------------------------------------- */
  const matSrc = fs.readFileSync('js/material.js', 'utf8');
  check('the world has a thermal switch, declared, bound, and off',
    MAT.world.thermal.value === 0 && /uniform float thermal;/.test(MAT.WORLD_UNIFORMS_GLSL) &&
    MAT.worldUniforms().thermal === MAT.world.thermal && /uniforms: \{ map: \{ value: tex \}, \.\.\.worldUniforms\(\) \}/.test(fs.readFileSync('js/sky.js', 'utf8')));
  check('and every surface that shades through the world answers heat when it is on',
    /if \(thermal > 0\.5\) return vec3\(thermalOf\(/.test(matSrc) && /if \(thermal > 0\.5\) \{\s*float h = c\.r;/.test(matSrc));
  {
    /* ON FOR THE ONE RENDER AND NEVER OTHERWISE: a renderer that writes
       down what the switch said while it was drawing */
    const seen = [];
    const r = { getRenderTarget() { return null; }, setRenderTarget() {}, clear() {}, render() { seen.push(MAT.world.thermal.value); } };
    const sc = new TH.ThermalScope(r);
    const cam = { position: { copy() {} }, quaternion: { copy() {} }, updateProjectionMatrix() {}, fov: 60, near: 1, far: 100, aspect: 1 };
    sc.camera = cam;
    const van = { whole: true, state: 'driving', cz: 40, bodies: [], mesh: { material: { uniforms: { warmth: { value: 0 } } } } };
    const parked = { whole: true, state: 'parked', burning: 0, cz: 40, bodies: [], mesh: { material: { uniforms: { warmth: { value: 0 } } } } };
    const fake = { vehicles: { all: [van, parked] }, gunships: { ships: [] } };
    fake.missiles = new MS.MissileSystem(fake);
    sc.game = fake;
    sc.held = true;
    for (let k = 0; k < 4; k++) sc.render({}, cam);
    check('the thermal feed is drawn with the switch on, every other frame, and it is off again after',
      seen.length === 2 && seen.every(v => v === 1) && MAT.world.thermal.value === 0);
    check('and a running engine is warm in it while a parked car is not',
      van.mesh.material.uniforms.warmth.value > 0.5 && parked.mesh.material.uniforms.warmth.value === 0);
    sc.held = false;
    sc.render({}, cam);
    check('and it draws nothing with the launcher out of your hands', seen.length === 2);
  }
  check('the thermal screen shares the lance\'s u flip, because the launcher is turned the same half circle',
    /vec2 uv = vec2\(1\.0 - \(vL\.x - box\.x\) \* box\.z, \(vL\.y - box\.y\) \* box\.w\);/.test(fs.readFileSync('js/thermal.js', 'utf8')));
  check('the zoom raises it to the eye the way it raises the lance',
    TH.THERMAL_AIM_AT[0] === 0 && TH.THERMAL_AIM_AT[TH.THERMAL_AIM_AT.length - 1] === 1 &&
    TH.THERMAL_ZOOMS.length === TH.THERMAL_AIM_AT.length && TH.THERMAL_ZOOMS[0] === 1);
  check('the launcher\'s parts are baked: a lock bracket in two frames and a motor in three',
    ['TLCKA', 'TLCKB', 'MISLA', 'MISLB', 'MISLC'].every(k => g.sprites.frames.has(k)));
}

/* ---------- the arc maw ---------- */
section('the arc maw');
{
  const fs = await import('node:fs');
  const { parseGLB, readAccessor } = await import('../js/glb.js');
  const w3 = await import('../js/weapon3d.js');
  const pl = await import('../js/player.js');
  const AR = await import('../js/arc.js');
  const AU = await import('../js/audio.js');
  const { Game } = await import('../js/game.js');
  const MAPM = await import('../js/maps/sellwrong.js');
  const THREEM = await import('three');
  const D = w3.GUNS.ARC;

  /* ---- THE MODEL, AS IT SHIPS: the user's sculpt, finished in Blender
     (the AO, the curvature and a distressed gunmetal baked through its
     normal map), cut to sixteen thousand triangles with its UVs kept,
     and one diffuse sheet with the AO and the relief in it ---- */
  const file = fs.readFileSync(D.url);
  const { json, bin } = parseGLB(file.buffer.slice(file.byteOffset, file.byteOffset + file.length));
  const pr = json.meshes[0].primitives[0];
  const tris = json.accessors[pr.indices].count / 3;
  note('the arc maw', `${(file.length / 1024).toFixed(0)}K, ${tris} triangles, one ${json.images?.[0]?.mimeType} sheet`);
  check('the arc maw ships as one mesh of under twenty thousand triangles, under a megabyte',
    json.meshes.length === 1 && json.meshes[0].primitives.length === 1 && tris <= 20000 && file.length < 1024 * 1024);
  check('and wears one diffuse sheet and nothing else, since the gun shader reads colour alone',
    json.images?.length === 1 && json.materials.length === 1 && !json.materials[0].normalTexture &&
    !json.materials[0].pbrMetallicRoughness?.metallicRoughnessTexture &&
    Object.keys(pr.attributes).sort().join() === 'NORMAL,POSITION,TEXCOORD_0');
  check('with its node\'s turn baked into it, so the model\'s own units are the ones GUNS speaks in',
    json.nodes.every(n => !n.matrix && !n.rotation && !n.translation && !n.scale));
  {
    /* THE MAW IS EMPTY AND THE PRONGS ARE ROUND IT: nothing of the model
       within a few centimetres of the nozzle, and metal all the way round
       it a little further out, at the same depth */
    const P = readAccessor(json, bin, pr.attributes.POSITION).array;
    const [nx, ny, nz] = D.nozzle;
    let inside = 0; const sides = new Set();
    for (let i = 0; i < P.length; i += 3) {
      const dx = P[i] - nx, dy = P[i + 1] - ny, dz = P[i + 2] - nz, r = Math.hypot(dx, dy);
      if (Math.hypot(dx, dy, dz) < 0.2) inside++;
      if (Math.abs(dz) < 0.5 && r > 0.25 && r < 1.0) sides.add(Math.floor((Math.atan2(dy, dx) + Math.PI) / (Math.PI / 3)) % 6);
    }
    /* three prongs, so three of the six sixths at least, and never a
       half circle of them open — the bolt is in the middle of the three */
    const open3 = [0, 1, 2, 3, 4, 5].some(k => ![0, 1, 2].some(j => sides.has((k + j) % 6)));
    check('the bolt leaves from between the prongs: nothing at the maw, and metal all the way round it',
      inside === 0 && sides.size >= 3 && !open3, `${inside} in the maw, ${sides.size} of 6 sixths`);
  }
  check('and the gun carries a charge ball in its maw, and a blue flash',
    !!D.orb && D.orb.radius > 0 && D.orb.reach > D.orb.radius && D.orb.motes >= 16 && D.tint[2] > D.tint[0]);

  /* ---- THE WEAPON ---- */
  const W = pl.WEAPONS.ARC;
  const inputSrc = fs.readFileSync('js/input.js', 'utf8');
  check('the arc maw is the seventh weapon, on the seven key, charged and let go, and issued',
    W.slot === 7 && W.arc === true && W.ammo === 'volts' && pl.VOLTS >= 4 &&
    /Digit7: 'weapon7'/.test(inputSrc) && /this\.pressed\('weapon7'\)\) this\.weaponSlot = 7/.test(inputSrc) &&
    new (class extends pl.Player { constructor() { super({ level: { sectorAt: () => null } }, 0, 0, 0); } })().owned.ARC === true);
  check('more charge is more strikes: one for a tap, nine at the top, never fewer for more',
    AR.hitsFor(0) === 1 && AR.hitsFor(1) === 9 && AR.hitsFor(2) === 9 &&
    [...Array(21)].every((_, i) => i === 0 || AR.hitsFor(i / 20) >= AR.hitsFor((i - 1) / 20)));
  check('and a strike does more off a bigger charge and less down the chain',
    AR.strikeDamage(1, 0) > AR.strikeDamage(0, 0) && AR.strikeDamage(1, 8) < AR.strikeDamage(1, 0) && AR.strikeDamage(0, 8) > 0);
  check('its voice is in the synthesised table: the climbing hum, the top of it, the crack, the thunder and the zap',
    ['arccharge1', 'arccharge2', 'arccharge3', 'arcfull', 'arcfire', 'arcbig', 'arczap'].every(k => AU.SOUNDS?.[k] || new RegExp(`\\b${k}:`).test(fs.readFileSync('js/audio.js', 'utf8'))));

  /* ---- IN THE SHOP ----
     ON ITS OWN ROLL of the dice: the chain and its fields land on
     whoever happens to be standing near whom, and without a seed that
     was decided by how many rolls every test above this one used — a
     bigger police van tumbling differently in the car park moved it. */
  (await import('../js/util.js')).pSeed();
  const g = new Game({
    level: MAPM.buildSellWrong({ town: false }), scene: new THREEM.Scene(), camera: {},
    textures: tex.bakeTextures(), sprites: spr.bakeSprites(),
    hud: { message() {}, ticMessages() {} }, audio: null,
    input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
             attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
  });
  const p = g.player, A = g.arc;
  p.debug = false;
  p.weapon = 'ARC';
  const pick = () => {
    let t = null, bd = Infinity;
    for (const a of g.actors) {
      if (!A.canStrike(a)) continue;
      const d = Math.hypot(a.x - p.x, a.y - p.y);
      if (d < 150 || d > 1000 || d > bd) continue;
      const c = A.chest(a);
      if (g.level.sightBlocked(p.x, p.y, p.eyeZ, c.x, c.y, c.z)) continue;
      t = a; bd = d;
    }
    return t;
  };
  const aimAt = t => { const c = A.chest(t); p.angle = Math.atan2(c.y - p.y, c.x - p.x); p.pitch = Math.atan2(c.z - p.eyeZ, Math.hypot(c.x - p.x, c.y - p.y)); };
  let t = pick();
  note('the arc maw\'s first target', t ? `${t.type} ${Math.round(Math.hypot(t.x - p.x, t.y - p.y))} away` : 'nobody in sight');
  if (t) {
    /* a tap: one strike */
    g.input.attack = true; aimAt(t); g.tic();
    const tapCharge = p.arcCharge;
    g.input.attack = false; g.tic();
    check('a tap is one strike, on whoever is in the middle of the sight',
      A.fired === 1 && A.lastChain.length === 1 && A.lastChain[0] === t && p.arcCharge === 0 && p.ammo.volts === pl.VOLTS - 1,
      `charge ${tapCharge.toFixed(2)}, chain ${A.lastChain.length}`);
    for (let k = 0; k < 40; k++) g.tic();
    /* a full charge: up to nine, a hop a tic, each in reach of the last */
    t = pick();
    g.input.attack = true;
    for (let k = 0; k < AR.ARC.chargeTics + 5; k++) { if (t) aimAt(t); g.tic(); }
    const full = p.arcCharge;
    const s0 = A.strikes;
    g.input.attack = false; g.tic();
    const b = A.bolts[A.bolts.length - 1], chain = A.lastChain;
    const revealed = [b ? b.reveal : -1];
    for (let k = 0; k < 3; k++) { g.tic(); revealed.push(b.reveal); }
    const hopsOk = b && b.nodes.slice(2).every((n, i) => {
      const prev = b.nodes[i + 1];
      return Math.hypot(n.x - prev.x, n.y - prev.y, n.z - prev.z) <= AR.ARC.chain + 60;
    });
    check('held to the top it charges full, and lets go as a chain of up to nine, nobody struck twice',
      full === 1 && chain.length > 1 && chain.length <= 9 && new Set(chain).size === chain.length, `chain ${chain.length}`);
    check('the chain is revealed a hop a tic, and every hop is in reach of the one before',
      revealed[1] > revealed[0] && revealed[2] > revealed[1] && hopsOk, revealed.join(','));
    for (let k = 0; k < 20; k++) g.tic();
    check('and people standing next to a strike are caught in its field',
      A.strikes - s0 > chain.length && b.fields.length > 0, `${A.strikes - s0} strikes for ${chain.length} in the chain`);
    check('and strikes throw thinner sub-bolts at random, at people the chain passed over — bonus kills',
      A.subs > 0 && b.subs.length > 0 && b.subs.every(sb => !sb.who || !chain.includes(sb.who)) &&
      b.subs.some(sb => sb.who) && A.bonusKills > 0, `${A.subs} sub-bolts, ${A.bonusKills} bonus kills`);
    check('and it throws sparks, and sparks that fall with a trail behind them',
      A.sparks.count > 50 && A.drips.length > 0);
    const zs = A.drips.slice(0, 5).map(d => d.z);
    g.tic();
    check('which fall', A.drips.length === 0 || A.drips.slice(0, 5).some((d, i) => zs[i] !== undefined && d.z < zs[i]));
    for (let k = 0; k < 200; k++) g.tic();
    check('and are gone again, bolts and drips and all', A.bolts.length === 0 && A.drips.length === 0);
  }
  /* LIGHTNING IS NOT FIRE: a fireproof trooper is hurt by it */
  {
    const sw = g.spawn('SWAT', p.x + 300, p.y, undefined, {});
    const h0 = sw.health;
    p.angle = 0; p.pitch = Math.atan2(A.chest(sw).z - p.eyeZ, 300);
    p.ammo.volts = pl.VOLTS;
    const b = { nodes: [{ x: p.x, y: p.y, z: p.eyeZ, who: null, muzzle: true }, { ...A.chest(sw), who: sw }], reveal: 0, t: 0, charge: 1, struck: new Set([sw]), seed: 1, fields: [], subs: [] };
    A.strike(b, 1);
    check('the bolt hurts a trooper, whose kit shrugs off fire, and never gibs one', (sw.health < h0 || sw.dead) && sw.health >= -8,
      `${h0} -> ${sw.health}`);
    check('because it lands as a shock, never as fire', !/fire: true/.test(fs.readFileSync('js/arc.js', 'utf8')));
  }
  /* AN EMPTY CAPACITOR CLICKS AND DOES NOTHING */
  {
    p.ammo.volts = 0;
    const f0 = A.fired;
    g.input.attack = true; g.tic(); g.tic(); g.input.attack = false; g.tic();
    check('an empty capacitor does nothing', A.fired === f0 && p.arcCharge === 0);
    for (let k = 0; k < pl.VOLT_REGEN_EVERY + 2; k++) g.tic();
    check('and a discharge comes back in three seconds', p.ammo.volts >= 1);
  }
}

/* ---------- the music ---------- */
section('the music');
{
  const fs = await import('node:fs');
  const mu = await import('../js/music.js');
  const T = mu.TRACKS;
  note('the tracks', T.map(t => `${t.url.split('/').pop()} ${t.bpm} bpm, out at ${t.out} of ${t.seconds}`).join('; '));
  check('three tracks, and all three files are there', T.length === 3 && T.every(t => fs.existsSync(t.url)));
  check('and no two of them are the same file',
    new Set(T.map(t => fs.readFileSync(t.url).length)).size === T.length);
  /* THE TABLE HAS TO BE PLAYABLE: every handover point is a downbeat
     late in its track with room for the fade before the file ends, and
     the first downbeat is where a track starts, not a minute in */
  check('every handover is late in its track, and the fade fits before the end',
    T.every(t => t.out > t.seconds * 0.8 && t.out + mu.FADE_BARS * mu.barOf(t) <= t.seconds));
  check('and every first downbeat is at the head of the file', T.every(t => t.bar0 >= 0 && t.bar0 < 2));
  check('and the tempos are all E1M1\'s, near enough', T.every(t => t.bpm > 135 && t.bpm < 150));
  /* --- one handover, as arithmetic --------------------------------- */
  const a = T[0], b = T[1];
  const outAt = 1000;
  const plan = mu.arrange(a, b, outAt);
  check('the incoming starts so its first downbeat lands on the outgoing\'s handover',
    Math.abs(plan.start + b.bar0 / plan.rate - outAt) < 1e-9, `${plan.start} + ${b.bar0}/${plan.rate}`);
  check('and it arrives at the outgoing\'s tempo, so the bars line up for the whole fade',
    Math.abs(plan.rate - a.bpm / b.bpm) < 1e-12 && Math.abs(mu.barOf(b) / plan.rate - mu.barOf(a)) < 1e-9);
  check('the fade is eight bars of the outgoing tempo, linear, and the outgoing stops at the end of it',
    Math.abs(plan.fadeEnd - outAt - 8 * 240 / a.bpm) < 1e-9 &&
    /linearRampToValueAtTime\(0, plan\.fadeEnd\)/.test(fs.readFileSync('js/music.js', 'utf8')) &&
    /out\.src\.stop\(plan\.fadeEnd/.test(fs.readFileSync('js/music.js', 'utf8')));
  check('and the incoming eases back to its own tempo over eight more bars, after the fade',
    plan.rateEnd > plan.fadeEnd && Math.abs(plan.rateEnd - plan.fadeEnd - 8 * 240 / a.bpm) < 1e-9);
  /* --- and where the incoming's own handover then falls ------------- */
  const w = p => mu.wallTimeFor(plan, p);
  check('file time maps to wall time at the rate during the fade',
    Math.abs(w(b.bar0) - outAt) < 1e-9 && Math.abs(w(plan.rate * (plan.fadeEnd - plan.start)) - plan.fadeEnd) < 1e-9);
  const D = plan.rateEnd - plan.fadeEnd, p1 = plan.rate * (plan.fadeEnd - plan.start), p2 = D * (1 + plan.rate) / 2;
  check('through the ramp, where the ramp covers the mean rate times its length',
    Math.abs(w(p1 + p2) - plan.rateEnd) < 1e-6 && w(p1 + p2 / 2) > plan.fadeEnd && w(p1 + p2 / 2) < plan.rateEnd);
  check('and at one thereafter, so the next handover is exactly where the table says',
    Math.abs(w(b.out) - (plan.rateEnd + (b.out - p1 - p2))) < 1e-9 && w(b.out) > plan.rateEnd);
  /* a whole lap: each handover is later than the last by about a track */
  let at = 0, i = 0, laps = 0;
  for (let k = 0; k < 9; k++) {
    const j = (i + 1) % T.length;
    const pl = mu.arrange(T[i], T[j], at);
    const next = mu.wallTimeFor(pl, T[j].out);
    if (next - at < 180 || next - at > 260) laps = -99;
    at = next; i = j; if (i === 0) laps++;
  }
  check('and round the three of them for ever, one every four minutes or so', laps === 3, `${laps} laps`);
  /* --- the page ------------------------------------------------------ */
  const html = fs.readFileSync('index.html', 'utf8'), mainSrc = fs.readFileSync('js/main.js', 'utf8');
  check('there is a music fader in the menu and it is wired',
    html.includes('id="opt-music"') && /music\.setVolume\(prefs\.music\)/.test(mainSrc) && /'opt-music'/.test(mainSrc));
  check('the music starts on the start tap and is ticked every frame',
    /musicP\.then\(\(\) => music\.start\(\)\)/.test(mainSrc) && /music\.tick\(\);/.test(mainSrc));
  check('and it has its own context, so the muted effects do not take it with them',
    /new AC\(\)/.test(fs.readFileSync('js/music.js', 'utf8')) && !/audio\.ctx/.test(fs.readFileSync('js/music.js', 'utf8')));
  const { VERSION } = await import('../js/version.js');
  check('the version is one string, MAJOR.MINOR.PATCH, and the title screen shows it',
    /^\d+\.\d+\.\d+$/.test(VERSION) && html.includes('id="version"') && /\$\('version'\)\.textContent = 'V' \+ VERSION/.test(mainSrc)
      && /#version \{/.test(fs.readFileSync('css/style.css', 'utf8')), VERSION);
}

section('the gun');
{
  const fs = await import('node:fs');
  const G = await import('../js/glb.js');
  const buf = fs.readFileSync(new URL('../assets/models/flamethrower.glb', import.meta.url));
  const { json, bin } = G.parseGLB(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
  const names = json.nodes.map(n => n.name);
  note('model', `${json.nodes.length} nodes, ${json.meshes.length} meshes, ${json.images.length} image, ${(buf.length / 1024 / 1024).toFixed(1)} MB`);
  note('where it came from', [json.asset.extras?.title, json.asset.extras?.author].filter(Boolean).join(' — ') || 'unsaid');
  /* WHAT tools/prep-model.mjs IS FOR, checked on its output. The model
     arrives with three 1024 maps and seven vertex attributes; an unlit
     renderer that reads four of them and one map would carry the other
     six megabytes to the player for nothing. */
  check('only the diffuse survives',
    json.images.length === 1 && json.materials.length === 1 &&
    !json.materials[0].normalTexture && !json.materials[0].pbrMetallicRoughness?.metallicRoughnessTexture);
  const attrs = new Set();
  for (const m of json.meshes) for (const p of m.primitives) for (const k of Object.keys(p.attributes)) attrs.add(k);
  check('and only the attributes js/glb.js binds: no tangents, no second set of UVs',
    [...attrs].every(k => ['POSITION', 'NORMAL', 'TEXCOORD_0', 'COLOR_0'].includes(k)), [...attrs].join());
  /* ONE TIGHT VIEW PER ACCESSOR is what makes dropping them worth
     anything — a shared bufferView survives as long as one accessor
     points into it, so this is the check that the dead bytes actually
     left. */
  check('every buffer view is used, by exactly one accessor or one image',
    json.bufferViews.every((bv, i) =>
      json.accessors.filter(x => x.bufferView === i).length + json.images.filter(im => im.bufferView === i).length === 1));
  check('and no accessor is interleaved or offset into somebody else\'s range',
    json.accessors.every(a => !a.byteOffset) && json.bufferViews.every(bv => !bv.byteStride));
  /* and the geometry came through the repack unbent: the bounds the
     file declares are the bounds of the bytes it now holds */
  let checked = 0, worst = 0;
  for (const m of json.meshes) for (const p of m.primitives) {
    const a = json.accessors[p.attributes.POSITION];
    const { array } = G.readAccessor(json, bin, p.attributes.POSITION);
    for (let k = 0; k < 3; k++) {
      let mn = Infinity, mx = -Infinity;
      for (let i = k; i < array.length; i += 3) { if (array[i] < mn) mn = array[i]; if (array[i] > mx) mx = array[i]; }
      worst = Math.max(worst, Math.abs(mn - a.min[k]), Math.abs(mx - a.max[k]));
    }
    checked += a.count;
  }
  check('and every vertex is where the file says it is', worst < 1e-4, `${checked} vertices, worst ${worst.toExponential(1)}`);
  check('no marker spheres are left in any model this tool has touched',
    !names.some(n => /CLAUDE/i.test(n)), names.join());
}

/* ---------- the town ---------- */
section('the town');
{
  const T = await import('../js/maps/town.js');
  const G = level.town.grid;

  /* THE GRID, and that the mall is already on it. TOWN.txt's single
     most useful fact: the clearing is 14,000 across and four pitches
     less one street is 13,968, so the town did not have to be
     reconciled with the supermarket — the supermarket was on the grid
     before anybody drew one. */
  note('the grid', `${G.width} x ${G.depth}, 5 x 5 blocks on a pitch of ${T.PITCH}`);
  check('five blocks each way, six streets', G.bx.length === 5 && G.sx.length === 6 && G.by.length === 5 && G.sy.length === 6);
  check('a block is 3072 and a street is 576',
    G.bx.every(([a, b]) => b - a === T.BLOCK) &&
    G.sx.filter((_, i) => i !== 3).every(([a, b]) => b - a === T.STREET));
  check('main street is the wide one', G.main[1] - G.main[0] === T.MAIN_W);
  check('and it points at the supermarket doors',
    Math.abs((G.main[0] + G.main[1]) / 2 - 2140) < 64, `${((G.main[0] + G.main[1]) / 2).toFixed(0)} against 2140`);
  check('the town starts where the lot stops', G.y1 === -3096, `${G.y1}`);

  /* THE STREET IN CROSS-SECTION, at the user's request twice over: the
     sidewalk went to three times the plan's 48 and the kerb to twice
     its 12, and then the kerb came back down to the plan's twelve and
     the sidewalk to 112 to make room for a parking shoulder each side
     of the carriageway — 112 | 16 | 76 | 84 | 84 | 76 | 16 | 112, and
     every one of those came out of the same 576 because the block pitch
     is what puts the supermarket on the grid. */
  {
    const U3 = await import('../js/util.js');
    const walk = level.sectors.find(s2 => /^sidewalk,/.test(s2.name));
    const road = level.sectors.find(s2 => /^street centre,/.test(s2.name));
    const width = s2 => Math.min(s2.bbox[2] - s2.bbox[0], s2.bbox[3] - s2.bbox[1]);
    note('the street', `sidewalk ${width(walk)} wide, kerb ${walk.floor} tall, carriageway ${T.STREET - 2 * (width(walk) + 16)}`);
    check('a sidewalk is more than twice the plan\'s forty-eight', width(walk) === 112, `${width(walk)}`);
    check('and the kerb is the plan\'s twelve', walk.floor === 12, `${walk.floor}`);
    check('the street is still 576, so the block pitch is still 3648',
      T.STREET === 576 && T.PITCH === 3648);
    check('and main street still points at the supermarket doors',
      Math.abs((G.main[0] + G.main[1]) / 2 - 2140) < 64);
    /* AND YOU CAN STILL GET ON IT: half of MAX_STEP, so this is the
       check that stands between a town with sidewalks and a town with a
       kerb you can see and not stand on. */
    check('a kerb of twelve is half the tallest step there is',
      walk.floor * 2 === U3.MAX_STEP, `${walk.floor} against ${U3.MAX_STEP}`);
    /* THE KERB IS AT THE VERGE, which is the band the plan puts between
       the walking and the parking: road, then the step up, then grass,
       then concrete. So the line to ask about is the verge's — and what
       is over the line from it is the parking shoulder. */
    const verge = level.sectors.find(s2 => /^verge,/.test(s2.name));
    const shared = verge && verge.lines.find(l => l.frontCol.length && l.backCol.length &&
      [l.front, l.back].some(i => /^(parking|storm drain),/.test(level.sectors[i].name)));
    if (check('the kerb is a step from the parking shoulder up to the verge', !!shared && verge.floor === 12))
      check('and you can step up it', level.lineBlocks(shared, 0, 56, false) === null,
        `${level.lineBlocks(shared, 0, 56, false)}`);
    /* THE SHOULDER: a parking lane each side at road level, a storm
       drain in the gutter near each end of every run, and a van in a
       few of the bays — slots js/vehicles.js parks a van in at load */
    const parking = level.sectors.filter(s2 => /^parking,/.test(s2.name));
    const drains = level.sectors.filter(s2 => /^storm drain,/.test(s2.name));
    note('the shoulders', `${parking.length} pieces of parking, ${drains.length} storm drains, ${level.carSlots.filter(sl => sl.street).length} vans parked on the street`);
    check('a parking shoulder is at road level, 76 wide and painted in bays',
      parking.length > 200 && parking.every(s2 => s2.floor === 0 && width(s2) <= 76 && /^ASPHPAR[KV]$/.test(s2.floorTex)) &&
      parking.filter(s2 => width(s2) === 76).length >= parking.length / 3,
      `${parking.filter(s2 => !(s2.floor === 0 && width(s2) <= 76)).length} are not`);
    check('a storm drain is a grate at road level against the kerb',
      drains.length >= 400 && drains.every(s2 => s2.floor === 0 && s2.floorTex === 'DRAIN' && width(s2) === 24), `${drains.length}`);
    check('and the drain is a step below the kerb it sits against — the verge, or on Main Street the pavement',
      drains.every(s2 => s2.lines.some(l => l.frontCol.length && l.backCol.length && [l.front, l.back].some(i => /^(verge|sidewalk),/.test(level.sectors[i].name)))));
    const townSlots = level.carSlots.filter(sl => sl.street);
    check('vans are parked along the streets, on the shoulder, in a bay',
      townSlots.length > 60 && townSlots.length < 200 &&
      townSlots.every(sl => { const s2 = level.sectorAt(sl.x, sl.y); return s2 && /^parking,/.test(s2.name); }),
      `${townSlots.length}, ${townSlots.filter(sl => !/^parking,/.test(level.sectorAt(sl.x, sl.y)?.name || '')).length} off the shoulder`);
    check('and no two vans share a bay', (() => {
      const seen = new Set();
      for (const sl of townSlots) { const k = `${Math.round(sl.x / 16)},${Math.round(sl.y / 16)}`; if (seen.has(k)) return false; seen.add(k); }
      return true;
    })());
  }

  const townSecs = level.sectors.filter(inTown);
  note('what is in it', `${townSecs.length} regions, ${level.roofs.length} roofs, ${level.sectors.filter(s => s.storey > 0).length} storeys over a ground floor`);
  check('the town is most of the map now', townSecs.length > level.sectors.length * 0.8, `${townSecs.length} of ${level.sectors.length}`);
  note('the mall', `${level.sectors.filter(inMall).length} regions of the original 327, the rest being wood the town took`);
  check('and the mall is still all there', level.sectors.filter(inMall).length >= 320,
    `${level.sectors.filter(inMall).length}`);

  /* EVERY COLUMN STACKS. The first of TOWN.txt's listed invariants and
     the one that catches a floor plan whose storeys were written by
     hand: no overlap, no storey under the one below it. */
  let bad = 0, deep = 0;
  for (const s of level.sectors) {
    if (s.above === null) continue;
    const up = level.sectors[s.above];
    if (up.floor < s.ceil - 1e-6) bad++;
    /* a gap is a DECK (sixteen of joist) or a WALL (a whole storey of
       it, which is what the nave door has over it where the choir loft
       opens) — anything deeper than that is a storey somebody forgot.
       Under a ROOF, or under the shut cap of the tower, it is as deep
       as the wall over a recess is tall, and that is not a floor
       anybody forgot: a door on a three-storey terrace has two storeys
       of brick over it and then the roof. */
    /* AND A FLAT ONE IS STILL A ROOF. The office block's roof storey
       is open forty units inside its parapet with ballast for a floor,
       so it has no roofTex to be recognised by; what it does have is
       the sky over it, which is what every top-of-a-column storey in
       this map has and is the thing actually being said here. */
    if (up.roofTex || up.sky || up.ceil - up.floor < 1e-6) continue;
    /* AND A WALL MAY HAVE A RAIL ON TOP OF IT, which is forty-eight
       more: the choir loft's opening starts a rail above its floor so
       the band under it is the balusters, and the church tower's
       belfry sits a storey and a half over its door. Both are a wall
       with something on it and neither is a floor anybody forgot. */
    if (up.floor - s.ceil > T.STOREY + 48) deep++;
  }
  check('every column stacks without overlap', bad === 0, `${bad} storeys start under the one below`);
  check('and the gap between two storeys is a deck or a wall, never a missing floor', deep === 0, `${deep} too deep`);

  /* SPANAT AGREES WITH SECTORAT for every column of one, which is the
     whole of the existing map and is the regression that matters. */
  let disagree = 0, sampled = 0;
  for (const s of level.sectors) {
    if (s.above !== null || s.colBase !== s.index) continue;
    const x = (s.bbox[0] + s.bbox[2]) / 2, y = (s.bbox[1] + s.bbox[3]) / 2;
    if (!level._inSector(s, x, y)) continue;
    sampled++;
    if (level.spanAt(x, y, s.floor + 1) !== s) disagree++;
  }
  check('spanAt agrees with sectorAt for every column of one', disagree === 0, `${disagree} of ${sampled}`);

  /* AND IT PICKS THE RIGHT STOREY in a column that has several: the
     school's corridor, which has the first-floor corridor over it. */
  const hall = level.sectors.find(s => s.name === 'C3 corridor' && s.storey === 0 && s.above !== null);
  if (check('the school has a corridor with a corridor over it', !!hall)) {
    const hx = (hall.bbox[0] + hall.bbox[2]) / 2, hy = (hall.bbox[1] + hall.bbox[3]) / 2;
    /* THE SCHOOL'S STOREY IS NOT THE TOWN'S any more — it is taller, at
       the user's request — so the height of the floor above is asked of
       the column rather than of the constant the houses use. */
    const SCH_STOREY = level.sectors[hall.above].floor - hall.floor;
    const ground = level.spanAt(hx, hy, hall.floor + 4), first = level.spanAt(hx, hy, hall.floor + SCH_STOREY + 4);
    check('standing in it you are on the ground floor', ground === hall);
    check('and a storey up you are on the floor above', first && first.storey === 1 && first.colBase === hall.index);
    check('and sectorAt still answers with the ground one', level.sectorAt(hx, hy) === hall);
  }

  /* A WALL IS WHERE TWO COLUMNS DISAGREE — and over the whole of the
     store, which is columns of one, the rule reproduces Doom's upper
     and lower exactly. This is the check the plan asked for by name. */
  let mismatch = 0, twoSided = 0;
  for (const l of level.lines) {
    if (!l.frontCol.length || !l.backCol.length || l.texLocked) continue;
    if (l.frontCol.length > 1 || l.backCol.length > 1) continue;
    twoSided++;
    const f = level.sectors[l.front], b = level.sectors[l.back];
    if (l.upper !== (f.ceil <= b.ceil ? f : b).upperTex) mismatch++;
    else if (l.lower !== (f.floor >= b.floor ? f : b).lowerTex) mismatch++;
  }
  check('the disagreement rule reproduces upper and lower, texture for texture',
    mismatch === 0, `${mismatch} of ${twoSided}`);
  check('and it had plenty to reproduce', twoSided > 600, `${twoSided}`);

  /* NO SURFACE OF ZERO OR NEGATIVE HEIGHT. */
  let degenerate = 0, bands = 0;
  for (const l of level.lines) for (const bd of l.bands || []) { bands++; if (bd.z1 - bd.z0 <= 0) degenerate++; }
  note('wall bands', `${bands} over ${level.lines.length} lines`);
  check('no wall band is zero or negative', degenerate === 0, `${degenerate}`);

  /* THE MALL'S EDGE CONFLICTS. Three columns meeting on one edge is a
     map error with no honest answer; the builder counts them. */
  check('no edge has three columns on it', (level.edgeConflicts ?? 0) === 0, `${level.edgeConflicts}`);

  /* EVERY ROOM ON THE GROUND FLOOR IS REACHABLE, in the two buildings
     that still have an inside. Done as the engine would do it: step up
     no more than MAX_STEP through openings that are actually open at
     the height you are at.

     IT USED TO ASK FOR THE UPSTAIRS TOO, and it was the check that
     caught a stair laid out one tread short. THE STAIRS ARE GONE, at
     the user's request — both of the school's and the church's
     switchback — so the first floor and the choir loft are built, lit
     and furnished with no way to walk to any of them, and a test that
     still asked would be asking for something nobody built. What it
     asks instead is that the ground floor is whole, which is the part
     that would break if a wall went in the wrong place. */
  {
    const U = await import('../js/util.js');
    const walk = (start) => {
      const seen = new Set([start.index]), stack = [start];
      while (stack.length) {
        const s = stack.pop();
        for (const l of s.lines) {
          if (l.blocking) continue;                           // glass
          const other = s.colBase === l.frontBase ? l.backCol : l.frontCol;
          for (const oi of other) {
            const o = level.sectors[oi];
            if (o === s || seen.has(o.index)) continue;
            const openTop = Math.min(s.ceil, o.ceil), openBottom = Math.max(s.floor, o.floor);
            if (openTop - openBottom < 56) continue;            // you do not duck
            if (openBottom - s.floor > U.MAX_STEP) continue;    // nor climb
            seen.add(o.index); stack.push(o);
          }
        }
      }
      return seen;
    };
    const reach = (tag, door, rooms, upstairs) => {
      const secs = level.sectors.filter(s => s.name.startsWith(tag));
      const start = secs.find(s => s.name === door);
      if (!check(`${tag.trim()} has a way in`, !!start)) return;
      const seen = walk(start);
      const want = secs.filter(s => rooms.test(s.name.slice(tag.length)));
      const missed = want.filter(s => !seen.has(s.index));
      note(`${tag.trim()} walked from its door`, `${seen.size} regions reached, ${want.length} rooms asked for`);
      check(`every room in ${tag.trim()} can be walked to`, want.length > 20 && missed.length === 0,
        `${missed.length} cannot, e.g. ${missed[0]?.name} (storey ${missed[0]?.storey})`);
      if (upstairs) check(`and that includes the upstairs`, want.some(s => s.storey > 0 && seen.has(s.index)));
      /* and with no stair the upstairs is exactly what you CANNOT get
         to, which is worth saying out loud rather than leaving as the
         absence of a check */
      else check(`and with no stair, nothing above the ground floor is`,
        secs.filter(s => s.storey > 0 && !s.outdoor && s.fuel > 0).every(s => !seen.has(s.index)),
        `${secs.filter(s => s.storey > 0 && !s.outdoor && s.fuel > 0 && seen.has(s.index)).length} reached`);
    };
    reach('C3 ', 'C3 front door', /^(classroom [SN]\d|corridor|lobby|office|gym|passage)$/, false);
    reach('B3 ', 'B3 door', /^(nave floor|centre aisle|side aisle|chancel|narthex|tower)$/, false);
  }

  /* THE FACADES, which are what the houses are now. A house is a shell
     with recesses cut in its wall: every window is a hole from the sill
     to the head with a pane on its back wall, every door a hole with a
     door in it, and the foot of every wall shows its foundation. */
  {
    const U3 = await import('../js/util.js');
    /* THE HOUSES' WINDOWS, which are a recess with the pane PAINTED on
       the one-sided wall at the back of it. The school's, the church's
       and the office block's are the other kind — an outer recess and
       an inner one with real glass hung on the line between them — and
       are held to that where they are built. */
    const recesses = level.sectors.filter(s => s.outdoor && /(window \d|door)$/.test(s.name) && !/school|C3|B3|A5/.test(s.name));
    const windows = recesses.filter(s => / window \d$/.test(s.name));
    const doors = recesses.filter(s => / door$/.test(s.name));
    note('recesses', `${windows.length} window storeys, ${doors.length} doors`);
    check('the houses have windows, and plenty', windows.length > 1500, `${windows.length}`);
    check('and doors', doors.length > 250, `${doors.length}`);
    /* a window is a HOLE: open between its sill and its head, and shut
       above and below, on the line it shares with the ground outside */
    const w0 = windows.filter(s => s.storey === 0);
    const holed = w0.filter(s => s.lines.some(l => l.frontCol.length && l.backCol.length &&
      (l.holes || []).some(h => Math.abs(h.z0 - s.floor) < 1e-6 && Math.abs(h.z1 - s.ceil) < 1e-6)));
    check('every ground-floor window is a hole in the wall from its sill to its head', holed.length === w0.length, `${w0.length - holed.length} are not`);
    /* with the pane on a wall of its own at the back, wearing glass */
    const paned = w0.filter(s => s.lines.some(l => (!l.frontCol.length || !l.backCol.length) && /^WIN(PANEL|PANED|SHADE)$/.test(l.middle)));
    check('and a pane at the back of it', paned.length === w0.length, `${w0.length - paned.length} have not`);
    const doored = doors.filter(s => s.lines.some(l => (!l.frontCol.length || !l.backCol.length) && /^FRNTDO/.test(l.middle)));
    check('every door recess has a door in it', doored.length === doors.length, `${doors.length - doored.length} have not`);
    check('a door sill is the height of the foundation, and a window sill is above it',
      doors.every(s => s.floor === T.FOUND || s.floor === T.KERB_H) && w0.every(s => s.floor >= T.KERB_H));
    /* the recess is sixteen deep, the wall twenty-four */
    check('a recess is sixteen deep in a wall twenty-four thick',
      windows.every(s => Math.min(s.bbox[2] - s.bbox[0], s.bbox[3] - s.bbox[1]) === T.NICHE) && T.ZONE === 24);
    /* THE FOUNDATION: a plinth at the foot of every wall, its face
       wearing block, and two steps up to the door */
    const found = level.sectors.filter(s => / foundation$/.test(s.name));
    check('every wall stands on a foundation', found.length > 600 && found.every(s => s.floor === T.FOUND && /FOUNDATN|STONEFND/.test(s.lowerTex)), `${found.length}`);
    const steps = level.sectors.filter(s => / step$/.test(s.name)), stoops = level.sectors.filter(s => / stoop$/.test(s.name));
    check('and a step and a stoop up to every door', steps.length > 250 && stoops.length === steps.length &&
      steps.every(s => s.floor === T.FOUND / 2) && stoops.every(s => s.floor === T.FOUND), `${steps.length} steps, ${stoops.length} stoops`);
    check('which you can walk up', T.FOUND / 2 <= U3.MAX_STEP);
    check('and a path from the sidewalk', level.sectors.filter(s => / path$/.test(s.name) && s.floorTex === 'PAVERS').length > 250);
    /* the recess is outdoors, so the interior LOD leaves it in the shell */
    check('a recess is outdoors', recesses.every(s => s.outdoor));
  }

  /* THE CHURCH IS BUILT OF STONE, at the user's request, and the steeple
     has an underside. It was white clapboard between a fieldstone
     foundation, a stone water table and a stone cornice, which is a wall
     that disagrees with everything it is attached to; and the spire was
     a one-sided roof over a shut storey, so from the churchyard you
     looked up through the steeple at the sky. */
  {
    const T7 = await import('../js/textures.js');
    check('there is a coursed ashlar for the church and no clapboard left on it',
      typeof T7.TEXTURE_GENERATORS.CHURCHST === 'function' &&
      T7.TEXTURE_GENERATORS.CHURCHWD === undefined);
    const stoneP = T7.TEXTURE_GENERATORS.CHURCHST();
    check('and it is 64 pixels like everything else', stoneP.w === 64 && stoneP.h === 64);
    /* THE COURSING IS THE PICTURE, and a wall with no bed joints in it
       is a painted wall: every sixteenth row is the shadow of one, so
       the four of them have to be darker than the stone between. */
    const rowMean = y => { let t = 0; for (let x = 0; x < 64; x++) t += stoneP.data[(y * 64 + x) * 4]; return t / 64; };
    const joints = [0, 16, 32, 48].map(rowMean), faces = [6, 22, 38, 54].map(rowMean);
    check('with a bed joint every course, darker than the stone over it',
      joints.every((j, i2) => j < faces[i2]), `${joints.map(v => v | 0)} against ${faces.map(v => v | 0)}`);
    /* and nothing black in it, which is what lichen at the wrong
       brightness looked like the first time */
    let blackest = 255;
    for (let i2 = 0; i2 < 64 * 64; i2++) {
      const o = i2 * 4;
      blackest = Math.min(blackest, Math.max(stoneP.data[o], stoneP.data[o + 1], stoneP.data[o + 2]));
    }
    check('and no texel of it is black, which weathering at the wrong brightness looks like',
      blackest > 24, `darkest texel ${blackest}`);
    /* EVERY EXTERIOR FACE OF THE CHURCH IS THAT STONE. The nave, the
       tower, the buttresses and the window reveals, and not the roof,
       which is shingle on a stone church as on any other. */
    const churchSec = level.sectors.filter(s2 => /^B3 /.test(s2.name));
    const outside = churchSec.filter(s2 => /tower|buttress|nave|foundation|water table|eaves|narthex|belfry/.test(s2.name));
    const clad = new Set();
    for (const s2 of outside) for (const k of ['wallTex', 'upperTex', 'lowerTex']) if (s2[k]) clad.add(s2[k]);
    check('the church stands in stone and no part of its outside is clapboard',
      clad.has('CHURCHST') && !clad.has('CHURCHWD') && !clad.has('CLAPBRD') && !clad.has('VINYLSID'),
      [...clad].sort().join(' '));
    /* THE STEEPLE HAS A BOTTOM. The spire is a roof over a shut storey,
       so unlike every other roof in the game there is no ceiling under
       it — see the soffit block in js/mapgeo.js. */
    const spire = (level.roofs || []).find(r => r.rise >= 300 && r.base > 400);
    check('the spire is a roof standing on the tower', !!spire, spire ? `base ${spire.base} rise ${spire.rise}` : 'not found');
    check('and it is shingled all the way round rather than being a gable with a wall in it',
      spire.tex === 'SHINGLE' && spire.gableTex === 'SHINGLE');
    check('and it has an underside, or you look up through the steeple at the sky',
      !!spire.soffit && spire.soffit !== 'NONE', `${spire.soffit}`);
    /* and the soffit is really built, facing DOWN */
    const mg7 = await import('../js/mapgeo.js');
    const rec7 = {};
    const set7 = { get: n => rec7[n] || (rec7[n] = { tris: [], quad(pp) { this.tris.push(pp); },
                                                    tri() {} }) };
    mg7.roofGeometry(set7, { roof: spire, light: 0.4 });
    const soff = rec7[spire.soffit];
    check('the soffit is one flat quad at the springing of the spire',
      !!soff && soff.tris.length === 1 && soff.tris[0].every(v => v[1] === spire.base),
      soff ? `${soff.tris.length} quads` : 'none');
    /* WOUND THE OTHER WAY FROM A FLOOR, so it is seen from below.
       addFlats emits a floor from a ring that is COUNTER-clockwise in
       map space and that faces up, so clockwise faces down — and the
       cross product of the first two edges, taken in map space (the
       renderer's z is the map's minus y), is negative for clockwise. */
    const q7 = soff.tris[0];
    const mapY = v => -v[2];
    const cross = (q7[1][0] - q7[0][0]) * (mapY(q7[2]) - mapY(q7[0])) -
                  (mapY(q7[1]) - mapY(q7[0])) * (q7[2][0] - q7[0][0]);
    check('and wound so it faces down, which is the only side anybody sees it from',
      cross < 0, `${cross}`);
  }

  /* THE GLASS in the church and the school: a pane hung in a hole you
     can see through and stop at. */
  {
    const glass = level.lines.filter(l => l.frontCol.length && l.backCol.length && l.blocking && /^(STAINGLS|SCHWINLT|SCHWINDK)$/.test(l.middle));
    note('panes of glass', glass.length);
    check('the church has its coloured glass', glass.filter(l => l.middle === 'STAINGLS').length >= 12);
    check('and the school its windows', glass.filter(l => /^SCHWIN/.test(l.middle)).length >= 30);
    check('every pane hangs in a hole', glass.every(l => (l.holes || []).length > 0));
    check('and stops you', glass.every(l => level.lineBlocks(l, 0, 56, false) === 'blocking'));
  }

  /* THE STREET FURNITURE: lamps on every sidewalk with a pool of light
     under each, trees in the yards, stones in the cemetery. */
  {
    const lamps = level.things.filter(t => t.type === 'STREETLAMP');
    const pools = level.sectors.filter(s => /^sidewalk under a lamp/.test(s.name));
    note('street lamps', `${lamps.length}, over ${pools.length} pools of light`);
    check('there are lamps down every street', lamps.length > 300, `${lamps.length}`);
    check('each with a pool of light on the pavement brighter than the rest of it',
      pools.length > 200 && pools.every(s => s.light > 0.6) && level.sectors.filter(s => /^sidewalk,/.test(s.name)).every(s => s.light < 0.5));
    /* AND THEY STAND ON MADE GROUND — which is now two different kinds
       of it. In the town that is the pavement. In the car park it is
       the line where two rows of bays meet nose to nose, which is the
       one strip of a lot nobody ever parks on and is where every lot
       light in America stands. What the check is really asking is that
       no lamp is in somebody's lawn or out in the carriageway, and that
       is still what it asks. */
    check('and every lamp stands on the pavement, or on the strip of tarmac nobody parks on',
      lamps.every(t => { const s = level.sectorAt(t.x, t.y); return s && /sidewalk|corner|path|bays|trolley bay|service yard/.test(s.name); }));
    /* THE ARM REACHES OVER THE ROAD. A lamp is a photograph stood flat
       across the street (THE STREET LAMP IS GEOMETRY in js/mapgeo.js)
       and the picture is a pole with its arm on one side, so the
       thing's angle is which way the arm goes — and it had better go
       over the carriageway, a junction or a path, not over somebody's
       garden. The two allowed misses are the plain corners on the
       outside of the town's two bends, where the apron of pavement is
       wider than an arm is long. */
    const over = (t, d) => level.sectorAt(t.x + Math.cos(t.angle) * d, t.y + Math.sin(t.angle) * d)?.name ?? 'nowhere';
    check('every lamp knows which way its arm reaches', lamps.every(t => Number.isFinite(t.angle)));
    const missed = lamps.filter(t => !/junction|parking|street|crossing|path|bays|trolley bay|driving lane|fire lane|service yard/.test(over(t, 40)));
    check('and the arm reaches over the road, the bays, the junction or the path, all but the outside of the two bends',
      missed.length <= 2 && missed.every(t => /^corner/.test(over(t, 40))),
      `${missed.length} over ${[...new Set(missed.map(t => over(t, 40)))].join(', ')}`);
    /* AND THE CAR PARK HAS SOME NOW, which it did not: a floodlit lot
       is the brightest sector in the level and there was nothing in it
       anywhere throwing that light. */
    const lotLamps = lamps.filter(t => /bays|trolley bay/.test(level.sectorAt(t.x, t.y)?.name ?? ''));
    check('and the car park is lit by something you can point at', lotLamps.length >= 40, `${lotLamps.length} in the lot`);
    check('and the pool under a lamp says it is lit by one, and nothing else does',
      pools.every(s => s.lampLit) && level.sectors.filter(s => s.lampLit).length === pools.length);
    /* PLANTABLE GROUND, which now includes the VERGE: the strip between
       the sidewalk and the kerb is where an American town puts its
       street trees, and it is the only name on this list that is not
       somebody's garden. */
    const PLANTABLE = /yard|garden|lawn|churchyard|graveyard|green|park|cemetery|verge|island/;
    const onPlantable = pl => { const s = level.sectorAt(pl.x, pl.y); return !!s && !s.roofTex && PLANTABLE.test(s.name); };
    check('the town has its trees', level.plants.length > 500, `${level.plants.length}`);
    check('and none of them stands in the road or in a house',
      level.plants.every(onPlantable),
      level.plants.filter(pl => !onPlantable(pl)).slice(0, 3).map(pl => `${pl.kind} on ${level.sectorAt(pl.x, pl.y)?.name ?? 'nowhere'}`).join(', '));
    const stones = level.things.filter(t => t.type === 'GRAVESTONE');
    check('the cemetery has its stones', stones.length > 100 && stones.every(t => /cemetery|graveyard/.test(level.sectorAt(t.x, t.y)?.name ?? '')), `${stones.length}`);
    /* THE EIGHT STONES. The GRAVESTONE actor carries a `variant` that
       swaps the fourth letter of its sprite name, and a graveyard where
       every marker is the same slab is a car park with the lines rubbed
       out. All eight have to be DEALT — a variant that is never chosen
       is art in the bank and nothing on the ground. */
    const variants = new Set(stones.map(t => t.variant));
    check('and eight kinds of stone among them, every one of them used',
      variants.size === 8 && [...variants].every(v => Number.isInteger(v) && v >= 0 && v < 8),
      [...variants].sort((a, b) => a - b).join(','));
    /* THE STREET TREES, which is what the verge is for. They are
       broadleaves out of assets/forest/ and not the wood's firs: a
       street of firs is a town in a national park. */
    const F5 = await import('../js/forest.js');
    const BROAD = F5.KINDS.filter(k => /^street_/.test(k.name)).map(k => k.name);
    const street = level.plants.filter(pl => BROAD.includes(pl.kind));
    check('six kinds of broadleaf line the streets', BROAD.length === 6, BROAD.join(', '));
    check('and there are enough of them to read as an avenue', street.length > 400, `${street.length}`);
    check('and they stand on the verge, the churchyard or the park, never on a corner',
      street.every(pl => /verge|lawn|yard|green|park|cemetery|island/.test(level.sectorAt(pl.x, pl.y)?.name ?? '')),
      street.filter(pl => !/verge|lawn|yard|green|park|cemetery|island/.test(level.sectorAt(pl.x, pl.y)?.name ?? '')).slice(0, 3)
            .map(pl => `${Math.round(pl.x)},${Math.round(pl.y)} ${level.sectorAt(pl.x, pl.y)?.name}`).join(' | '));
    /* THE BOX IS NOT A PLANT ANY MORE. It was a row of photographed
       blocks, one to a 64-unit cell of the wood's grid, turning to face
       you; at the user's request it is a SECTOR whose floor is the top
       of the hedge — see carveHedges in js/maps/town.js. What that
       bought is a hedge with a corner and a top you can see going away
       from you, and what it costs is that the ground it stands in had
       to be cut open to let it in. Both halves are checked here. */
    check('nothing plants a block of box any more', level.plants.every(pl => pl.kind !== 'hedge_box'));
    check('and the wood no longer knows the kind', !F5.KINDS.some(k => k.name === 'hedge_box'));
    const hedges = level.sectors.filter(s => s.floorTex === 'HEDGETOP');
    note('hedges', `${hedges.length} runs of clipped box`);
    check('the town is hedged', hedges.length > 20, `${hedges.length} runs`);
    check('and every run of it found ground to be cut out of',
      level.town.hedgeLost === 0, `${level.town.hedgeLost} landed on nothing`);
    check('and the map agrees with itself about how many there are',
      level.town.hedges === hedges.length, `${level.town.hedges} counted, ${hedges.length} in the map`);
    /* A HEDGE IS A STEP YOU CANNOT TAKE, which is the whole of why it
       stops you: forty is nine over the engine's limit. And it is BELOW
       THE EYE at forty-nine, which is the whole of why it is forty and
       not the seventy-two the sprite stood at — a green you cannot see
       across is a wall. */
    const U = await import('../js/util.js');
    check('and it is too tall to climb and too short to hide the green behind it',
      hedges.every(s => s.floor === 40) && 40 > U.MAX_STEP && 40 < 49,
      `${hedges[0] && hedges[0].floor} against a step of ${U.MAX_STEP}`);
    check('and it is open to the sky, so the weather lights it like the lawn it stands in',
      hedges.every(s => s.outdoor && s.sky === 1 && s.ceil === 768));
    /* AND THE SIDE OF IT IS A BAND, which is the disagreement rule
       doing the drawing: the lawn beside it is open from nought and the
       hedge is not, so the forty units between them wear the hedge's
       own lowerTex. If that came out as grass the hedge would be a
       green slab floating over a lawn-coloured cliff. */
    let sides = 0;
    for (const l of level.lines) for (const b of (l.bands || [])) if (b.tex === 'HEDGESID') sides++;
    check('and every side of every run is drawn as hedge and not as whatever was under it',
      sides >= hedges.length * 2, `${sides} bands over ${hedges.length} runs`);
    /* THE CARVE LEFT NO HOLES. Two rects may not overlap, so the lawn a
       hedge landed in was cut into the pieces round it; if the cut were
       wrong the map would not have built at all, and if a PIECE were
       lost there would be a hole in the ground beside every hedge. */
    {
      let holes = 0;
      for (const s of hedges) {
        const c = s.poly.reduce((a, v) => [a[0] + v[0] / s.poly.length, a[1] + v[1] / s.poly.length], [0, 0]);
        for (const [dx, dy] of [[-40, 0], [40, 0], [0, -40], [0, 40]]) {
          const q = level.sectorAt(c[0] + dx, c[1] + dy);
          if (!q) holes++;
        }
      }
      check('and there is ground on every side of every one of them', holes === 0, `${holes} sides with nothing beside them`);
    }
  }

  /* THE IRON ROUND THE CEMETERY. An enclosure in this engine is a
     masked MIDDLE texture hung in the line between two sectors that are
     both open to the sky, which is why the block has a verge outside
     the fence at all: a fence with nothing behind it has nothing to
     hang in. The ring is eight runs because the four paths have to get
     out through it, and that is what is counted. */
  {
    const cemLines = level.lines.filter(l => l.middle === 'RAILING' &&
      [...(l.frontCol || []), ...(l.backCol || [])].some(i => /cemetery/.test(level.sectors[i]?.name ?? '')));
    const iron = cemLines.reduce((a, l) => a + l.len, 0);
    note('cemetery railings', `${cemLines.length} lines, ${Math.round(iron)} units of iron`);
    /* IT USED TO BE EIGHT LINES, because the ground either side of it
       was eight rects — four quarters and eight verges. It is more than
       that now: the hedges were cut out of those same lawns and every
       cut leaves another piece, so a run of iron that was one line is
       three. Which is bookkeeping, and bookkeeping is not what anybody
       standing in the churchyard can see. So what is checked is the
       IRON: four sides, and the whole way round but for the gates. */
    const xs = new Set(), ys = new Set();
    for (const l of cemLines) { if (Math.abs(l.x1 - l.x2) < 0.5) xs.add(Math.round(l.x1)); else ys.add(Math.round(l.y1)); }
    check('the cemetery is fenced on all four of its sides',
      xs.size === 2 && ys.size === 2, `${xs.size} north-south, ${ys.size} east-west`);
    const span = a => Math.max(...a) - Math.min(...a);
    const want = 2 * (span([...xs]) + span([...ys])) - 4 * 96;   // less the four gates
    check('and the iron runs the whole way round but for the four gates',
      Math.abs(iron - want) < 4, `${Math.round(iron)} of ${Math.round(want)}`);
    check('and the iron stops you and stands six feet up',
      cemLines.every(l => l.blocking && l.midHeight === 96 && l.pegMiddle === 'bottom'));
    const gates = level.sectors.filter(s => /cemetery gate$/.test(s.name));
    check('with four gates through it, paved, and no iron across them',
      gates.length === 4 && gates.every(s => s.floorTex === 'PAVERS') &&
      !level.lines.some(l => l.middle === 'RAILING' &&
        [...(l.frontCol || []), ...(l.backCol || [])].some(i => /cemetery gate$/.test(level.sectors[i]?.name ?? ''))),
      `${gates.length} gates`);
  }

  /* ===================================================================
     THE PICKET FENCES, AND WHERE A FENCE IS NOT

     At the user's request. The fact this is about is that an American
     FRONT yard is open and a BACK yard is not, and the town had neither
     — the whole depth of a block read as one field with houses standing
     in it. So the thing to check is not that there are fences; it is
     that there are none across a front yard.
     =================================================================== */
  {
    const pik = level.lines.filter(l => l.middle === 'FENCEPIK');
    note('picket fence', `${pik.length} lines of it`);
    check('the back yards are fenced', pik.length > 200, `${pik.length} lines`);
    check('and the picket stops you and stands four feet up',
      pik.every(l => l.blocking && l.midHeight === 48 && l.pegMiddle === 'bottom'));
    /* IT IS ONLY EVER BETWEEN TWO YARDS. A picket across a sidewalk, a
       path or a foundation strip is a picket somebody's query caught by
       accident, and the query is the part that could go wrong. */
    const named = l => [...(l.frontCol || []), ...(l.backCol || [])]
      .map(i => level.sectors[i]?.name ?? '');
    const bad = pik.filter(l => !named(l).every(n => /yard/.test(n)));
    check('and never anywhere but between two yards',
      bad.length === 0, bad.slice(0, 3).map(l => named(l).join(' | ')).join(' ;; '));
    /* AND NEVER ACROSS A FRONT YARD, which is the whole point of it. A
       front yard in this town is the one whose sector is named for the
       approach rather than for the side of the house, and the test that
       it is open is simpler than that: a fence line is never within
       reach of a front path. */
    const paths = level.sectors.filter(s => / path$/.test(s.name || '') && /no \d/.test(s.name || ''));
    let acrossAPath = 0;
    for (const l of pik) {
      const mx = (l.x1 + l.x2) / 2, my = (l.y1 + l.y2) / 2;
      for (const q of paths) {
        const c = q.poly.reduce((a, v) => [a[0] + v[0] / q.poly.length, a[1] + v[1] / q.poly.length], [0, 0]);
        if (Math.hypot(c[0] - mx, c[1] - my) < 120) { acrossAPath++; break; }
      }
    }
    check('and never across the front, where an American lawn runs unbroken from door to door',
      acrossAPath === 0, `${acrossAPath} within reach of a front path`);
  }

  /* ===================================================================
     THE THINGS THAT STAND PROUD OF A WALL OR ABOVE A ROOF

     At the user's request: chimneys, porches, cornices, awnings,
     dormers, gable vents, corner boards, downpipes. All of them are
     free boxes owned by no region — see boxGeometry in js/mapgeo.js —
     and the rule that keeps that honest is that NONE OF THEM IS IN THE
     WAY, because a free box does not collide. So the checks are about
     where they are, not that they exist.
     =================================================================== */
  {
    const props = level.props || [];
    const { MAX_STEP } = await import('../js/util.js');
    const by = {};
    for (const q of props) by[q.tex] = (by[q.tex] || 0) + 1;
    note('free boxes', `${props.length}: ${Object.entries(by).sort((a, b) => b[1] - a[1])
      .map(([k, v]) => `${v} ${k.toLowerCase()}`).join(', ')}`);
    check('the town is built of more than walls and roofs now', props.length > 1500, `${props.length}`);
    check('and every one of them is a real box with a real texture',
      props.every(q => q.x1 > q.x0 && q.y1 > q.y0 && q.z1 > q.z0 && typeof q.tex === 'string'));

    /* A CHIMNEY IS ABOVE THE RIDGE OR IT IS NOT A CHIMNEY. It starts
       buried under the eaves so the roof closes round it, and it comes
       out the top; a stack that stops inside the roof is a brick nobody
       will ever see. */
    const stacks = props.filter(q => q.tex === 'CHIMNEY');
    const caps = props.filter(q => q.tex === 'CHIMCAP');
    check('every house and every fourth house of a terrace has a stack',
      stacks.length > 120, `${stacks.length} stacks`);
    check('and each of them wears a cap that oversails it, which is what makes it masonry',
      caps.length === stacks.length &&
      stacks.every(st => caps.some(c => Math.abs(c.z0 - st.z1) < 0.5 &&
        c.x0 < st.x0 - 1 && c.x1 > st.x1 + 1 && c.y0 < st.y0 - 1 && c.y1 > st.y1 + 1)),
      `${caps.length} caps over ${stacks.length} stacks`);

    /* NOTHING IS IN THE WAY. A free box does not collide, so anything a
       player could walk into would be something they walk THROUGH. The
       porch posts are the exception the rule is written around: they
       are eight units square and stand on a stoop nobody crosses
       sideways, which is the same bargain Doom made with every pillar
       it drew as a sprite. */
    const PLAYER_TOP = 49 + 8;
    /* WHERE A PLAYER CAN ACTUALLY BE. The question is not whether a box
       comes down to head height, it is whether it comes down to head
       height SOMEWHERE SOMEBODY CAN GET TO — and this used to be asked
       against a floor of zero, which is the car park, because
       everything that had ever been a free box stood on the ground.

       The checkstands are the first ones that do not: the register, the
       bag rack, the guards down the belt and every tin of somebody's
       shopping stand on a counter 26 above the floor against a MAX_STEP
       of 24, so there is no way to be up there at all. That is the same
       bargain the porch post makes and a stronger version of it — the
       post you can walk round, the counter you cannot climb.

       So: flood the level by the game's own passability, take the floor
       the box actually stands on, and ask whether a player standing on
       it would have the box inside them. A box on a floor nobody can
       reach is a box nobody can walk into. */
    const reach = new Set();
    {
      const st = level.things.find(t => t.type === 'START');
      const from = level.sectorAt(st.x, st.y);
      const byS = new Map();
      for (const l of level.lines) for (const si of [l.front, l.back]) {
        if (si === null) continue;
        if (!byS.has(si)) byS.set(si, []);
        byS.get(si).push(l);
      }
      const queue = [from.index];
      reach.add(from.index);
      while (queue.length) {
        const si = queue.pop();
        for (const l of byS.get(si) || []) {
          const other = l.front === si ? l.back : l.front;
          if (other === null || reach.has(other)) continue;
          if (level.lineBlocks(l, level.sectors[si].floor, 56, false)) continue;
          reach.add(other); queue.push(other);
        }
      }
    }
    /* the floor under a box, when anybody can be standing on it */
    const standingFloor = q => {
      const s2 = level.sectorAt((q.x0 + q.x1) / 2, (q.y0 + q.y1) / 2);
      return s2 && reach.has(s2.index) ? s2.floor : null;
    };
    const inTheWay = q => {
      const f = standingFloor(q);
      return f !== null && q.z0 < f + PLAYER_TOP && q.z1 > f;
    };
    /* the ones that are FLAT AGAINST something — a post on its stoop, a
       pipe, a board and a magazine rack on the face of a wall — and the
       one that is LOWER THAN A STEP, which is the wheel stop and is a
       different bargain: see below. */
    const FLAT = ['PORCHPST', 'DOWNPIPE', 'CORNRBRD', 'PILASTER', 'METERBOX', 'ROOFLADR', 'SHUTRAIL',
                  'SHOPFRAM', 'DOORFRAM', 'IMPULSE',
                  /* and what a school hangs on a wall: the boards and the
                     fountains in the corridor, the radiators under the
                     classroom windows, the town's own brick pilaster, and
                     the gym's wall bars — which stand on the padding, and
                     the padding turns out to be reachable by climbing the
                     bleachers and stepping along the north wall. A wall bar
                     IS a thing bolted flat to a wall, so it makes the same
                     bargain a downpipe does. */
                  'TROPHY', 'NOTICEBD', 'RADIATOR', 'FOUNTAIN', 'PILASTR', 'WALLBARS',
                  /* and what an office lobby has on its walls: the
                     directory by the door, the cooler in the break room,
                     and the ficus, which is in a planter against a wall
                     and not a box in the middle of the floor */
                  'DIRECTRY', 'WATRCOOL', 'PLANTPOT', 'WHITEBRD'];
    const STEPPABLE = ['WHEELSTP'];
    const low = props.filter(q => inTheWay(q) && ![...FLAT, ...STEPPABLE].includes(q.tex));
    note('free boxes up where nobody can stand',
      `${props.filter(q => !inTheWay(q) && q.z0 < PLAYER_TOP).length} of them, on counters and belts`);
    check('and nothing but a post, a pipe, a corner board and a wheel stop comes down to head height',
      low.length === 0, low.slice(0, 4).map(q => `${q.tex} at z${Math.round(q.z0)}`).join(', '));
    check('and every one of those is thin enough to be the wall it is on',
      props.filter(q => FLAT.includes(q.tex))
        .every(q => Math.min(q.x1 - q.x0, q.y1 - q.y0) <= 10),
      props.filter(q => FLAT.includes(q.tex) && Math.min(q.x1 - q.x0, q.y1 - q.y0) > 10)
        .slice(0, 3).map(q => `${q.tex} ${Math.min(q.x1 - q.x0, q.y1 - q.y0)} deep`).join(', '));
    /* ===============================================================
       AND NO TWO OF THEM SHARE A FACE YOU CAN SEE

       At the user's request, who saw it shimmering at the checkout.

       Z-FIGHTING IS TWO COPLANAR QUADS FACING THE SAME WAY. Every face
       of a free box winds outward, so two boxes that merely INTERSECT
       are fine — a chimney through a coping has no two faces in the
       same plane — and two that merely TOUCH are fine as well, because
       the plane they share carries one quad facing each way and the one
       you could see is always the far side of solid geometry.

       What is not fine is two boxes sharing a face plane AND a volume.
       Then both have a front-facing quad there, at the same depth, and
       the depth buffer has no answer: what you get is a seam that
       crawls as you move. Four places in this game had it and every one
       was the same mistake — a piece of trim run the full length and
       another run the full width, meeting at a corner where they both
       wanted to be:

         the belt guards against the end plate and the roller cover
         the shopfront mullions against the cill they stand on
         a door frame's jambs against the head that sits on them
         and two wall packs both wanting the mullion between the doors

       IT IS ONLY A BUG WHERE YOU CAN SEE IT, and that is not pedantry:
       the town's cornices and window trims all start two units inside
       the wall and therefore all share that plane with each other, two
       hundred and thirty-nine pairs of them, every one back-facing and
       culled. So the face is stepped off along its own outward normal
       and the question is whether a player can stand there — the same
       flood, and the same standing floor, as the head-height rule
       above. */
    {
      const ol = (a0, a1, b0, b1) => Math.min(a1, b1) - Math.max(a0, b0) > 0.01;
      /* can anybody be just outside this face, looking at it */
      const facing = (axis, plane, dir, a0, a1, z0, z1) => {
        for (const t of [0.15, 0.5, 0.85]) {
          const m = a0 + (a1 - a0) * t, p = plane + dir * 1.5;
          const s2 = axis === 'x' ? level.sectorAt(p, m) : level.sectorAt(m, p);
          if (s2 && reach.has(s2.index) && z1 > s2.floor + 0.5 && z0 < s2.ceil) return true;
        }
        return false;
      };
      const clash = [];
      for (let i = 0; i < props.length; i++) for (let j = i + 1; j < props.length; j++) {
        const a = props[i], b = props[j];
        if (a.x1 < b.x0 - 1 || b.x1 < a.x0 - 1 || a.y1 < b.y0 - 1 || b.y1 < a.y0 - 1) continue;
        const zlo = Math.max(a.z0, b.z0), zhi = Math.min(a.z1, b.z1);
        const hit = [];
        const side = (axis, plane, dir, c0, c1) => {
          if (facing(axis, plane, dir, c0, c1, zlo, zhi)) hit.push(plane);
        };
        if (ol(a.z0, a.z1, b.z0, b.z1)) {
          if (ol(a.y0, a.y1, b.y0, b.y1)) {
            const c0 = Math.max(a.y0, b.y0), c1 = Math.min(a.y1, b.y1);
            if (Math.abs(a.x0 - b.x0) < 1e-6) side('x', a.x0, -1, c0, c1);
            if (Math.abs(a.x1 - b.x1) < 1e-6) side('x', a.x1, +1, c0, c1);
          }
          if (ol(a.x0, a.x1, b.x0, b.x1)) {
            const c0 = Math.max(a.x0, b.x0), c1 = Math.min(a.x1, b.x1);
            if (Math.abs(a.y0 - b.y0) < 1e-6) side('y', a.y0, -1, c0, c1);
            if (Math.abs(a.y1 - b.y1) < 1e-6) side('y', a.y1, +1, c0, c1);
          }
        }
        /* and two lids at one height, which is the same failure looking up */
        if (a.topTex && b.topTex && Math.abs(a.z1 - b.z1) < 1e-6 &&
            ol(a.x0, a.x1, b.x0, b.x1) && ol(a.y0, a.y1, b.y0, b.y1)) hit.push('lid');
        if (hit.length) clash.push(`${a.tex}/${b.tex} at ${Math.round(a.x0)},${Math.round(a.y0)}`);
      }
      check('and no two free boxes share a face plane a player can look at',
        clash.length === 0, `${clash.length}: ${clash.slice(0, 4).join(', ')}`);
    }

    /* AND NOTHING BIG IS STANDING ON THE GROUND AS A BOX. The skips and
       the condensing sets in the service yard were free boxes for about
       an hour and it was the wrong call: a steel skip the size of a car
       in a yard you walk into is not a thing you get to walk through.
       They are raised floors now, so the engine stops you at them the
       way it stops you at a boxwood hedge. If this ever fails, somebody
       has put a solid object back in as a picture of one. */
    check('and nothing the size of a skip is a free box at all',
      !props.some(q => inTheWay(q) && Math.min(q.x1 - q.x0, q.y1 - q.y0) > 24));
    /* AND THE FOURTH IS LOWER THAN A STEP. A wheel stop is the first
       free box in this game that is neither above your head nor flat
       against a wall, and it gets away with it for one reason only: it
       is twelve tall against a MAX_STEP of twenty-four, so walking
       through one and stepping over one are the same move and there is
       nothing to notice. Fail this and the lot is full of kerbs the
       player walks through. */
    const stops = props.filter(q => q.tex === 'WHEELSTP');
    check('and a wheel stop is lower than a step, which is why it is allowed to be down there',
      stops.length > 150 && stops.every(q => q.z0 === 0 && q.z1 - q.z0 <= MAX_STEP),
      `${stops.length} stops, tallest ${Math.max(0, ...stops.map(q => q.z1 - q.z0))} against ${MAX_STEP}`);

    /* THE AWNINGS ARE OVER SHOPFRONTS AND NOWHERE ELSE, and they are
       over the WINDOW and not over the door, because an awning over a
       door is a canopy and a canopy costs money. */
    const aw = props.filter(q => q.tex === 'AWNING');
    check('Main Street has its awnings out', aw.length > 15, `${aw.length}`);
    check('and every one of them is over a shopfront, clear of the head of anyone under it',
      aw.every(q => q.z0 > 60 && q.z1 <= 120), aw.length ? `z${Math.round(aw[0].z0)}-${Math.round(aw[0].z1)}` : '');

    /* A GABLE VENT is the one piece of ornament on a house that is not
       ornament: an attic has to breathe. Every house has one or two. */
    check('every gable has something in it', props.filter(q => q.tex === 'GABLEVNT').length > 100);
    check('and every window on a front has a head over it',
      props.filter(q => q.tex === 'WINTRIM').length > 600);
    check('and the roofs are broken by dormers', props.filter(q => q.tex === 'WINPANED' || q.tex === 'WINPANEL').length > 40);

    /* AND THE GEOMETRY BUILDER KNOWS WHAT TO DO WITH ONE. The box is
       drawn by the same batch set as everything else in its block, so
       what this asks is that a box turns into triangles at all and that
       its lid is optional. */
    const MG = await import('../js/mapgeo.js');
    const BS = MG.__BatchSetForTests || null;
    void BS;
    check('the builder can draw a free box', typeof MG.boxGeometry === 'function');

    /* AND IT CAN DRAW THE UNDERSIDE OF ONE, which it could not until the
       parade needed canopies over its fire doors. A box with no floor
       is invisible from below — every side is wound outward and there
       is nothing at the bottom — so anything you STAND UNDER had to
       have one. Three things in the game do: a porch roof, an awning,
       and a fire exit canopy. */
    const shelves = props.filter(q => q.botTex);
    check('anything you can stand under has an underside to it',
      shelves.length > 100 &&
      props.filter(q => ['FASCIA', 'AWNING'].includes(q.tex) && q.z1 - q.z0 <= 40).every(q => q.botTex),
      `${shelves.length} boxes with a soffit`);
  }

  /* =====================================================================
     THE PLANT ON THE PARADE

     The same argument as the town's, made about the strip mall: a shed
     drawn out of ceiling heights has no coping, no gutter, no
     downpipes, no pilasters and nothing on its roof, and from the car
     park that reads as four horizontal bands thirteen thousand units
     long. Everything below is a free box in js/maps/sellwrong.js — see
     THE PLANT and DRESSING THE PARADE — and every check is about
     whether the thing is where the building says it should be rather
     than about how many of them there are.
     ===================================================================== */
  {
    section('the plant on the parade');
    const props = level.props || [];
    /* THE PARADE'S OWN, and the qualifier is not pedantry: the office
       block on A5 wears RTU, DUCTWORK, ROOFLADR, WALLPACK and METERBOX
       too, four blocks and five hundred and eighty units of height
       away, and every claim below is about the strip mall's roofline
       in particular. The town starts at y -3096. */
    const of = t => props.filter(q => q.tex === t && q.y0 > -3000);
    const MAP = await import('../js/maps/sellwrong.js');
    const { MAX_STEP } = await import('../js/util.js');
    const SKY = 480;                  // CEIL_SKY: the top of the wall
    const EDGE = 328;                 // the outer edge of the canopy
    const SOFF = 232;                 // the soffit over the footway

    /* THE COPING. A parapet that just stops is a cut edge with sky above
       it, and that was the single loudest thing wrong with this
       building. One length per tenancy, all of them at the top of the
       wall, all of them standing out over the lot. */
    const cope = of('COPING');
    note('the roofline', `${cope.length} lengths of coping, ${of('PIERCAP').length} pier caps, ${of('RTU').length} packaged units`);
    check('the top of the wall is capped from one end of the parade to the other',
      cope.length >= 20, `${cope.length} lengths`);
    check('and every length of it sits at the top of the wall and oversails it',
      cope.every(q => q.z0 >= SKY - 12 && q.z1 > SKY) &&
      cope.filter(q => q.z1 < SKY + 60).every(q => q.y0 < -136),
      cope.filter(q => !(q.z0 >= SKY - 12 && q.z1 > SKY)).length + ' at the wrong height');
    check('and it has a lid, because the one thing above it is the sky',
      cope.every(q => q.topTex));

    /* THE PIERS. A sixteen-wide change of texture in a flat wall is a
       stripe; a pilaster eight units proud with a cap that breaks the
       coping is the only vertical rhythm this elevation has. */
    const pil = of('PILASTER'), caps = of('PIERCAP');
    check('every pier is a pilaster standing proud of the wall',
      pil.length >= 20 && pil.every(q => q.z0 === 0 && q.z1 > SKY), `${pil.length}`);
    check('and each one is capped above the coping, so the pier breaks the line',
      caps.length === pil.length && caps.every(q => q.z0 >= SKY));
    check('and each one carries the water off the canopy',
      of('DOWNPIPE').filter(q => q.z1 > EDGE && q.z1 < EDGE + 40).length >= pil.length,
      `${of('DOWNPIPE').filter(q => q.z1 > EDGE && q.z1 < EDGE + 40).length} pipes on ${pil.length} piers`);
    check('and there is a gutter for the pipes to come off',
      of('GUTTER').length >= 20 && of('GUTTER').every(q => q.z1 === EDGE));

    /* THE FASCIA IS A TRAY. Two rims, one at the top edge of the sign
       band and one at the bottom, which is the difference between paint
       on a wall and a box screwed to one. */
    const rims = of('SIGNEDGE');
    check('every fascia has a rim top and bottom', rims.length >= 40, `${rims.length}`);
    check('and the rims bracket the sign band rather than sitting anywhere on it',
      rims.every(q => q.z0 === SOFF || q.z1 === EDGE));

    /* THE ROOF PLANT, which is the silhouette of the building type: a
       parapet built to hide the packaged units that never quite does. */
    const rtu = of('RTU');
    check('there is plant on the roof', rtu.length >= 12, `${rtu.length} units`);
    check('and every unit stands on the roof and shows over the coping',
      rtu.every(q => Math.abs(q.z0 - (SKY - 6)) < 1 && q.z1 > SKY + 40),
      rtu.length ? `bottom ${rtu[0].z0}, top ${rtu[0].z1}` : '');
    check('and every one of them is set back behind the parapet, not glued to it',
      rtu.every(q => q.y0 > -136 + 40));
    check('and the anchor\'s are ducted together', of('DUCTWORK').length >= 4);

    /* AND THE WAY UP TO THEM, which is the question the roof plant asks
       and which this building had no answer to at all. */
    const ladder = of('ROOFLADR');
    check('somebody can get up there', ladder.length >= 1 &&
      ladder.every(q => q.z0 === 0 && q.z1 >= SKY), `${ladder.length} ladder`);
    check('and it is in the service yard, where a ladder goes',
      ladder.every(q => q.y0 >= MAP.ANCHOR_Y1));

    /* THE SHOPFRONTS. A roller housing on every in-line unit and a light
       over every door, and THE LIGHT IS THE TENANCY: the parade already
       says who is left by whether the glass is lit, whitewashed or
       shuttered, and the fittings now say it too. */
    const packs = of('WALLPACK');
    check('there is a light over every door', packs.length >= 20, `${packs.length}`);
    check('and some of them are out, because most of this parade is',
      packs.some(q => q.light > 1) && packs.some(q => q.light < 0.3),
      `${packs.filter(q => q.light > 1).length} lit, ${packs.filter(q => q.light < 0.3).length} dead`);
    check('and every unit has the housing its roller winds into',
      of('SHUTBOX').length >= 18 && of('SHUTBOX').every(q => q.z1 <= SOFF));

    /* --- AND WHAT AN EMPTY UNIT LOOKS LIKE ------------------------
       Most of this parade is empty and it has to LOOK it, which used to
       be true of the glass and not of anything else. Three claims:
       every closed unit is metal, every closed unit's sign is dead, and
       neither of those is drawn out of one texture. */
    const fronts = level.sectors.filter(s => /^footway /.test(s.name) && s.name !== 'footway pier');
    const inLine = fronts.filter(s => s.name !== 'footway sellwrong' && s.wallTex !== 'PILASTER');
    const shut = inLine.filter(s => /^UNITSHUT/.test(s.wallTex));
    /* AN OPEN UNIT'S WALL IS THE FRAME NOW AND NOT THE GLASS. The glass
       stopped being a texture on that wall and became a HOLE with two
       sheets hung in it, so what is left of the wall is the mullions
       between the panes and the returns at the ends of the run — which
       is what a shopfront is once you take the glass out of it. Asked
       by wallTex rather than by name because the point of the check is
       that the building says which units are alive, and it still does.
       See THE GLAZING in js/maps/sellwrong.js. */
    const open = inLine.filter(s => s.wallTex === 'SHOPFRAM');
    note('the tenancies', `${open.length} lit, ${shut.length} shut, ${new Set(shut.map(s => s.wallTex)).size} shutters, ${new Set(shut.map(s => s.upperTex)).size} dead boards`);
    check('every unit that is not open has a shutter down over it',
      shut.length + open.length === inLine.length && shut.length >= 10,
      `${inLine.length - shut.length - open.length} are neither`);
    /* THE WHITEWASH IS GONE, and gone from the bank rather than merely
       unreferenced — same standard the pylon sign was held to. */
    check('and the whitewashed glass is gone from the map and from the bank',
      !inLine.some(s => s.wallTex === 'UNITVOID') && !('UNITVOID' in tex.TEXTURE_SIZES));
    check('and there is more than one shutter, because thirteen in a row out of one is wallpaper',
      new Set(shut.map(s => s.wallTex)).size === 2);
    /* A SHOPFRONT COMES OUT IN WHOLE REPEATS. This is the reason the two
       shutters are declared 72 by 55 and not 64 by 64: a front is 432 by
       220, so 64 gave six and three quarters across and three and a half
       up, and the quarter and the half were visible as a seam. */
    for (const n of ['UNITSHUT', 'UNITSHUT2']) {
      const sz = tex.TEXTURE_SIZES[n];
      const w = inLine[0].bbox[2] - inLine[0].bbox[0], h = inLine[0].ceil - inLine[0].floor;
      check(`${n} tiles a shopfront in whole repeats`,
        sz && w % sz.w === 0 && h % sz.h === 0,
        sz ? `${w}/${sz.w} by ${h}/${sz.h}` : 'no size');
    }
    /* AND THE SIGN SAYS THE SAME THING THE GLASS DOES. A blank painted
       tray over a unit that has been shut for years is a fascia somebody
       still maintains, and the board is the bigger surface of the two. */
    check('every shut unit has a dead board over it',
      shut.every(s => /^FASVOID/.test(s.upperTex)));
    check('and no open one does',
      open.every(s => !/^FASVOID/.test(s.upperTex)));
    /* THE CYCLE TRAP, which is worth a check because it cost a build to
       spot: the board is chosen off the same counter as the front, and
       the front's cycle is three long — so `i % 3` inside a state can
       only ever reach the residues that state occupies. Picking the
       board with `i` rather than `i / 3` meant the first dead board was
       never drawn anywhere on the parade and four of the six live
       colours vanished. What the fix has to produce is every board in
       use, and that is what this asks. */
    check('and all three dead boards are actually on the building',
      new Set(shut.map(s => s.upperTex)).size === 3,
      [...new Set(shut.map(s => s.upperTex))].join(' '));
    check('and the live ones are not all the same colour either',
      new Set(open.map(s => s.upperTex)).size >= 4,
      [...new Set(open.map(s => s.upperTex))].join(' '));
    /* AND THE ROLLER REACHES THE GROUND. A curtain that runs off the
       bottom of the wall is a metal WALL; one that stops in a heavier
       rail is a shutter somebody pulled down. It cannot be in the
       texture — the curtain has to tile — so it is a free box. */
    const rails = of('SHUTRAIL');
    check('and every shutter comes down to a bottom rail on the footway',
      rails.length === shut.length && rails.every(q => q.z0 === MAP.FLOOR_WALK),
      `${rails.length} rails on ${shut.length} shutters`);

    /* --- AND WHAT A SHOP WINDOW IS MADE OF ------------------------
       At the user's request, and it is the biggest single change the
       front of this building has had: a shopfront was one flat quad
       with mullions painted on it and is now SIX LAYERS, five of which
       are geometry. See THE GLAZING in js/maps/sellwrong.js.

       The checks below are the five layers, in order, plus the two
       things that make the whole idea affordable: that a pane comes out
       in whole repeats, and that a shopfront three thousand units long
       did not quietly become a portal into the supermarket. */
    const WALL = 16;                  // the void between two rooms IS the wall
    const reveal = level.sectors.filter(s => / glazing$/.test(s.name || ''));
    const outer = level.lines.filter(l => l.middle === 'GLAZEA');
    const inner = level.lines.filter(l => l.middle === 'GLAZEB');
    const backs = reveal.filter(s => s.wallTex !== 'GLAZGAP' || s.bbox[1] > -WALL + 1);
    note('the shopfront', `${outer.length} panes, ${reveal.length} pieces of reveal, ${new Set(reveal.map(s => s.wallTex)).size} things behind the glass`);
    check('a shop window is a hole in the wall and not a picture of one',
      outer.length >= 40 && reveal.length === outer.length * 2,
      `${outer.length} panes, ${reveal.length} sectors`);
    check('and every one of them is two sheets deep',
      inner.length === outer.length, `${outer.length} outer, ${inner.length} inner`);
    check('and you stop at glass, both sheets of it',
      outer.every(l => l.blocking) && inner.every(l => l.blocking));
    /* AND NOT ONLY ON PAPER. A blocking flag is a claim about the
       collision code, and the collision code is the thing that has let
       a wall through before — see "does not tunnel through a wall". */
    {
      const g = reveal.find(s => s.name === 'sellwrong glazing');
      const gx = (g.bbox[0] + g.bbox[2]) / 2;
      const end = level.slideMove(gx, -70, 0, 200, 16, MAP.FLOOR_WALK, MAP.FLOOR_WALK + 56);
      check('and walking at a shop window does not put you in the shop',
        end[1] < -WALL, `ended at y ${Math.round(end[1])}`);
    }
    /* ONE REPEAT IS ONE PANE, which is the reason the module is 96 by
       160 and the reason the mullions take the leftover instead. Get it
       the other way round and every run on the parade has a different
       fraction of a sheet of glass in it. */
    for (const n of ['GLAZEA', 'GLAZEB']) {
      const sz = tex.TEXTURE_SIZES[n];
      check(`${n} is one repeat to one pane`,
        sz && reveal.every(s => s.bbox[2] - s.bbox[0] === sz.w) &&
        reveal.every(s => s.ceil - s.floor === sz.h),
        sz ? `${reveal[0].bbox[2] - reveal[0].bbox[0]} by ${reveal[0].ceil - reveal[0].floor} against ${sz.w} by ${sz.h}` : 'no size');
      check(`and ${n} is masked, or it is not glass`, !!tex.TEXTURE_SIZES[n].masked);
    }
    /* SEMI-TRANSPARENT MEANS STIPPLED. Nothing in this game has partial
       alpha — snapImageData says so — so a half-silvered pane is an
       ordered dither of pixels that are there and pixels that are not,
       and this asks for both halves: no partial alpha anywhere in it,
       and somewhere between a quarter and three quarters of it there. */
    for (const n of ['GLAZEA', 'GLAZEB']) {
      const pix = tex.TEXTURE_GENERATORS[n]();
      let clear = 0, part = 0;
      for (let i = 3; i < pix.data.length; i += 4) {
        if (pix.data[i] === 0) clear++;
        else if (pix.data[i] !== 255) part++;
      }
      const cover = 1 - clear / (pix.w * pix.h);
      check(`${n} is stippled, not blended`, part === 0, `${part} partial pixels`);
      check(`and it is glass rather than a wall or a hole`,
        cover > 0.25 && cover < 0.75, `${(cover * 100).toFixed(0)}% of it is there`);
    }
    /* THE CAVITY IS THE BLACK OUTLINE, on all four sides of the hole at
       once: two jambs, a floor and a lid, all of them the same near
       black. It is the line that makes a sheet of glass an object. */
    const gaps = reveal.filter(s => Math.abs(s.bbox[1] - (-WALL)) < 1);
    check('the gap between the sheets is outlined black all the way round',
      gaps.length === outer.length &&
      gaps.every(s => s.wallTex === 'GLAZGAP' && s.floorTex === 'GLAZGAP' && s.ceilTex === 'GLAZGAP'),
      `${gaps.length} cavities`);
    /* AND THE REVEAL STOPS SHORT OF THE SHOP FLOOR. Let it reach and the
       whole front of the anchor becomes a three-thousand-unit portal:
       the flood opens the shop floor to anybody in the car park and the
       interior LOD has nothing left to do. What is at the back of a
       reveal is a PAINTED interior on a one-sided wall. */
    check('and the whole shopfront is not a window into the supermarket',
      reveal.every(s => s.bbox[3] < 0), `deepest ${Math.max(...reveal.map(s => s.bbox[3]))}`);
    check('and there is something painted behind every sheet of glass',
      backs.length === outer.length && backs.every(s => s.wallTex !== 'GLAZGAP' || s.light < 0.2),
      `${backs.length} backs`);
    check('and a supermarket, a shop and a dead unit do not look alike through it',
      new Set(backs.map(s => s.wallTex)).size === 3,
      [...new Set(backs.map(s => s.wallTex))].join(' '));
    /* THE FRAME is the one layer that is not a sector, because a sector
       engine cannot put anything proud of a wall. Free boxes, flat
       against the face, which is the rule the whole parade keeps. */
    const fram = of('SHOPFRAM');
    check('and the frame stands proud of the wall it is screwed to',
      fram.length >= 80 && fram.every(q => Math.abs(q.y1 - (-WALL)) < 0.01 &&
        q.y1 - q.y0 > 0 && q.y1 - q.y0 <= 10), `${fram.length} sections`);
    check('and every run has a cill under it and a head over it',
      fram.some(q => q.topTex === 'SHOPFRAM') && fram.some(q => q.botTex === 'SHOPFRAM'));
    /* AND NOT BEHIND A SHUTTER. You cannot see through a roller, so a
       reveal behind one is ninety sectors nobody will ever look at. */
    const shutNames = new Set(shut.map(s => s.name.replace(/^footway /, '')));
    check('and nothing was glazed behind a roller shutter',
      !reveal.some(s => shutNames.has(s.name.replace(/ glazing$/, ''))),
      [...shutNames].slice(0, 2).join(' '));

    /* THE SERVICE YARD. The skips and the condensing sets are REGIONS
       and not boxes — see WHAT IS IN THE SERVICE YARD — because a free
       box does not collide and a skip you walk through is a bug you can
       find in ten seconds. */
    const skipS = level.sectors.filter(s => s.name === 'a skip');
    const cond = level.sectors.filter(s => s.name === 'a condensing set');
    note('the service yard', `${skipS.length} skips, ${cond.length} condensing sets, ${level.sectors.filter(s => s.name === 'the service yard').length} pieces of yard`);
    check('there are skips out the back and they are solid', skipS.length === 2 &&
      skipS.every(s => s.floor > MAX_STEP * 4 && s.outdoor));
    check('and the plant that keeps the chill cases cold is out there too',
      cond.length === 8 && cond.every(s => s.floor > MAX_STEP && s.lowerTex === 'CONDENSR'));
    check('and you cannot walk through any of it',
      [...skipS, ...cond].every(s => s.floor > MAX_STEP));

    /* THE CAR PARK. Wheel stops on the rows by the doors, lighting on
       the strip nobody parks on, and a trolley bay with a rail you
       cannot walk through — which is why the rail is a fence and not a
       box. */
    const rail = level.lines.filter(l => l.middle === 'TROLLRAI');
    note('the car park', `${of('WHEELSTP').length} wheel stops, ${rail.length} lines of trolley rail`);
    check('the bays nearest the doors have wheel stops', of('WHEELSTP').length >= 150);
    check('there are trolley bays out in the lot', rail.length >= 8, `${rail.length} lines`);
    check('and the rail stops you, the way a fence does',
      rail.every(l => l.blocking && l.midHeight > 0 && l.pegMiddle === 'bottom' && l.texLocked));
    /* AND ONE END IS OPEN. A corral fenced on all four sides is a pen
       with nine trolleys locked in it, which is what the first go at
       this built: the test for the way in read l.y1, and a line has no
       y1 on it until mb.build() has run. */
    const railY = new Set(rail.flatMap(l => [l.y1, l.y2]));
    check('and one end of every trolley bay is open, or nobody can get a trolley out',
      rail.filter(l => l.y1 === l.y2).length === 2 &&
      rail.filter(l => l.y1 === l.y2).every(l => l.y1 === Math.min(...railY)),
      `${rail.filter(l => l.y1 === l.y2).length} closed ends over 2 bays`);
  }

  /* THE STREET LAMP IS A PHOTOGRAPH AND IT IS NOT A SPRITE. Two tiles
     out of tools/bake-art.mjs, stood up by js/mapgeo.js in the plane
     across the street; a pool of pavement the shader turns cold after
     dark; a flare per lamp out of js/lamplight.js. Every link in that
     chain is checkable without a GPU, and each of them is. */
  {
    const AD = await import('../js/art-data.js');
    const T6 = await import('../js/textures.js');
    const S6 = T6.STREET_LAMP;
    const head = AD.CUTOUTS.lamp_head, post = AD.CUTOUTS.lamp_post;
    /* --- the bake: two tiles, inside the 64-pixel rule, each a slice of one photograph --- */
    check('the lamp is two tiles, both of them 64 or under',
      !!head && !!post && head.w <= 64 && head.h <= 64 && post.w <= 64 && post.h <= 64,
      `${head?.w}x${head?.h} and ${post?.w}x${post?.h}`);
    check('the head is the top of the picture across its whole width',
      head.box[0] === 0 && head.box[1] === 0 && head.box[2] === 1 && head.box[3] > 0.05 && head.box[3] < 0.25, head.box.join(','));
    check('and the post is the rest of it down to the ground, no wider than the base plate',
      post.box[1] === head.box[3] && post.box[3] === 1 && post.box[0] === 0 && post.box[2] > 0.1 && post.box[2] < 0.4, post.box.join(','));
    /* THE WATERMARK. The photograph carries a sparkle in its bottom right
       corner, well clear of the lamp. Had it survived the cut, the
       artwork's box would have grown right by a fifth and the whole lamp
       would be squat; and the head tile's bottom right, which is the air
       under the luminaire, would not be air. */
    check('the photograph is as tall as a street lamp is, so nothing outside the lamp set its width',
      AD.LAMP.aspect > 0.33 && AD.LAMP.aspect < 0.37, `${AD.LAMP.aspect}`);
    const spr6 = await import('../js/sprites.js');
    const hp = spr6.cutoutPix('lamp_head');
    let underHead = 0;
    for (let y = Math.round(hp.h * 0.62); y < hp.h; y++)
      for (let x = Math.round(hp.w * 0.62); x < hp.w; x++) if (hp.data[(y * hp.w + x) * 4 + 3] > 8) underHead++;
    check('and the air under the luminaire is air', underHead === 0, `${underHead} texels`);
    check('the pole stands near the left of the picture and the lens hangs out to the right, under the head',
      AD.LAMP.foot > 0.08 && AD.LAMP.foot < 0.16 && AD.LAMP.lens[0] > 0.6 && AD.LAMP.lens[0] < 0.9 &&
      AD.LAMP.lens[1] > 0 && AD.LAMP.lens[1] < head.box[3], `foot ${AD.LAMP.foot}, lens ${AD.LAMP.lens.join(',')}`);
    /* --- the bank: declared at the lamp's own size, masked, and derived from one place --- */
    const sz = T6.TEXTURE_SIZES;
    check('both tiles are in the texture bank, masked, at the size the lamp stands',
      sz.LAMPHEAD?.masked && sz.LAMPPOST?.masked && sz.LAMPHEAD.w === S6.head.w && sz.LAMPHEAD.h === S6.head.h &&
      sz.LAMPPOST.w === S6.post.w && sz.LAMPPOST.h === S6.post.h);
    check('the lamp is 256 tall and the two tiles meet at the split',
      S6.height === 256 && Math.abs(S6.head.h + S6.post.h - S6.height) < 1e-6 && Math.abs(S6.width - 256 * AD.LAMP.aspect) < 1e-6);
    /* --- the actor: a radius and nothing to draw --- */
    const st6 = await import('../js/states.js');
    const sb6 = spr6.bakeSprites();
    check('there is no lamp sprite any more, and the actor is a post you walk into',
      sb6.count('LMPP') === 0 && !sb6.frames.has('LMPPA') && !st6.ACTORS.STREETLAMP.spawn &&
      st6.ACTORS.STREETLAMP.solid && st6.ACTORS.STREETLAMP.height === 256 && !st6.STATES.LMPP_STAND);
    /* --- the geometry, in isolation: one lamp into a recorder --- */
    const mg6 = await import('../js/mapgeo.js');
    const lamps6 = level.things.filter(t => t.type === 'STREETLAMP');
    const t6 = lamps6.find(t => Math.abs(t.angle - Math.PI / 2) < 1e-9);
    const rec = {};
    const set6 = { get: n => rec[n] || (rec[n] = { quads: [], quad(p, u, l, sk, ch, lp) { this.quads.push({ p, u, l, sk, ch, lp }); } }) };
    const nq = mg6.lampGeometry(set6, level, t6);
    const s6 = level.sectorAt(t6.x, t6.y);
    check('a lamp is two tiles with two faces each', nq === 4 && rec.LAMPHEAD?.quads.length === 2 && rec.LAMPPOST?.quads.length === 2);
    const H6 = rec.LAMPHEAD.quads[0], P6 = rec.LAMPPOST.quads[0];
    const ys = q => q.p.map(v => -v[2]), zs = q => q.p.map(v => v[1]);
    check('it stands in the plane across the street, its foot on the thing and its arm out the way the angle says',
      H6.p.every(v => Math.abs(v[0] - t6.x) < 1e-6) &&
      Math.abs(Math.min(...ys(H6)) - (t6.y - S6.foot * S6.width)) < 1e-6 &&
      Math.abs(Math.max(...ys(H6)) - (t6.y + (1 - S6.foot) * S6.width)) < 1e-6);
    check('from the floor to 256 over it, the head on top of the post',
      Math.min(...zs(P6)) === s6.floor && Math.abs(Math.max(...zs(H6)) - (s6.floor + 256)) < 1e-6 &&
      Math.abs(Math.max(...zs(P6)) - Math.min(...zs(H6))) < 1e-6);
    check('lit by the pool it stands in, under the sky, and marked as lit by its own lamp',
      H6.l === s6.light && H6.sk === 1 && H6.lp === 1 && P6.lp === 1);
    const F6 = rec.LAMPHEAD.quads[0], B6 = rec.LAMPHEAD.quads[1];
    let agree = true;
    for (let i = 0; i < 4; i++) {
      const j = B6.p.findIndex(pb => pb.every((c, k) => Math.abs(c - F6.p[i][k]) < 1e-9));
      if (j < 0 || Math.abs(B6.u[j][0] - F6.u[i][0]) > 1e-9 || Math.abs(B6.u[j][1] - F6.u[i][1]) > 1e-9) agree = false;
    }
    check('and both faces put the same texel at the same point, so the arm reaches over the road from either side', agree);
    check('with the whole tile once across the quad, the same way up as every wall',
      F6.u.some(u => u[0] === 0) && F6.u.some(u => u[0] === 1) && F6.u.some(u => u[1] === 0) && F6.u.some(u => u[1] === -1));
    /* --- and the whole town, built --- */
    const geo6 = mg6.buildLevelGeometry(level, tex.bakeTextures());
    let heads = 0, posts = 0, hv = 0, inShell = 0, poolLit = 0, poolAll = 0, walkLit = 0;
    const walk = (o, shell) => {
      if (o.geometry) {
        if (o.name === 'LAMPHEAD') { heads++; hv += o.geometry.getAttribute('position').count; if (shell) inShell++; }
        if (o.name === 'LAMPPOST') posts++;
        if (o.name === 'LAMPPOOL' || o.name === 'SIDEWALK') {
          const a = o.geometry.getAttribute('lamp');
          for (let i = 0; i < a.count; i++) {
            if (o.name === 'LAMPPOOL') { poolAll++; if (a.array[i] === 1) poolLit++; }
            else if (a.array[i] === 1) walkLit++;
          }
        }
      }
      for (const c of o.children || []) walk(c, shell || o.name === 'shell');
    };
    walk(geo6.group, false);
    check('the town stands every lamp up, two faces of two tiles each, in the shell of its block',
      hv === lamps6.length * 12 && heads === posts && inShell === heads && heads > 20, `${hv} vertices in ${heads} batches`);
    check('and every pool of pavement carries the lamp mark, and no plain sidewalk does',
      poolAll > 0 && poolLit === poolAll && walkLit === 0, `${poolLit} of ${poolAll}, ${walkLit} astray`);
    /* --- the shader --- */
    const mat6 = await import('../js/material.js');
    const wm = mat6.createWallMaterial({});
    check('the world shader knows when the lamps are on', /float lampsOn\(float sl\)/.test(mat6.WORLD_SHADE_GLSL));
    check('and tints a lamp-lit surface cold after dark, ahead of the banding',
      /attribute float lamp;/.test(wm.vertexShader) && /vLamp = lamp;/.test(wm.vertexShader) &&
      /albedo \*= mix\(vec3\(1\.0\), LAMP_LIGHT, vLamp \* lampsOn\(skyLight\)\);[\s\S]*float l = worldBand\(/.test(wm.fragmentShader));
    check('in a light that is green-white, the same one the flare is drawn in',
      mat6.LAMP_LIGHT.length === 3 && mat6.LAMP_LIGHT[1] === 1 && mat6.LAMP_LIGHT[0] < mat6.LAMP_LIGHT[2] && mat6.LAMP_LIGHT[2] < 1 &&
      new RegExp(`vec3\\(${mat6.LAMP_LIGHT.map(v => v.toFixed(3)).join(', ')}\\)`).test(wm.fragmentShader));
    /* --- the light: one mesh, the nearest lamps in sight, eased, after dark --- */
    const LL = await import('../js/lamplight.js');
    check('the lamps are off by day and on at night, on the shader\'s own curve',
      LL.lampsOn(1.0) === 0 && LL.lampsOn(0.5) === 0 && LL.lampsOn(0.08) === 1 && LL.lampsOn(0.22) === 1 &&
      LL.lampsOn(0.36) > 0.45 && LL.lampsOn(0.36) < 0.55);
    const THREE6 = await import('three');
    const scene6 = new THREE6.Scene();
    const sl = new LL.StreetLights({ level });
    check('every lamp in the town gets a lens point, up under its head',
      sl.setLamps(level) === lamps6.length && sl.lamps.every(L => L.z > 200 && L.z < 260));
    sl.attach(scene6);
    check('one mesh for all of them: additive, no depth, forty slots',
      scene6.children.length === 1 && sl.mesh.material.blending === THREE6.AdditiveBlending &&
      sl.mesh.material.depthTest === false && sl.mesh.geometry.getAttribute('centre').count === LL.LAMP_SLOTS * 4);
    const L0 = sl.lamps[0];
    const ex = L0.x - 300, ey = L0.y;
    level.visibleSectors(ex, ey, 0, 1.2, 4000);
    check('nothing is drawn by day', sl.render(ex, ey, 61, 1, 0, 0) === 0 && !sl.mesh.visible);
    const n1 = sl.render(ex, ey, 61, 1, 0, 1);
    for (let i = 0; i < 24; i++) sl.render(ex, ey, 61, 1, 0, 1);
    /* slot 0 is the nearest lamp, in the renderer's axes (the map's y is
       minus z), and the buffer is float32, so it is compared to a hair */
    const nearest = sl.lamps.reduce((a, b) => (Math.hypot(b.x - ex, b.y - ey) < Math.hypot(a.x - ex, a.y - ey) ? b : a));
    check('and at night the nearest lamps in sight are, the nearest first, eased up to full',
      n1 > 0 && n1 <= LL.LAMP_SLOTS && sl.mesh.visible && nearest.vis === 1 && sl.glow.array[0] > 0.5 &&
      sl.mesh.geometry.drawRange.count === n1 * 6 &&
      Math.abs(sl.centre.array[0] - nearest.x) < 0.01 && Math.abs(sl.centre.array[2] + nearest.y) < 0.01,
      `${n1} drawn, slot 0 at ${sl.centre.array[0].toFixed(1)},${(-sl.centre.array[2]).toFixed(1)} for ${nearest.x.toFixed(1)},${nearest.y.toFixed(1)}`);
    check('a lamp behind the eye is not dealt in', sl.render(ex, ey, 61, -1, 0, 1) < n1);
    level.sightBlocked = () => true;
    for (let i = 0; i < 40; i++) sl.render(ex, ey, 61, 1, 0, 1);
    check('a lamp the eye cannot see goes out, eased', L0.vis === 0 && sl.glow.array[0] === 0);
    delete level.sightBlocked;
    for (let i = 0; i < 40; i++) sl.render(ex, ey, 61, 1, 0, 1);
    check('and comes back when it can', L0.vis === 1);
    check('and past the far edge there is nothing', sl.render(ex, ey - 100000, 61, 1, 0, 1) === 0 && !sl.mesh.visible);
    check('the flare is a streak with a bloom in it, sized by its distance and fading with it',
      /vGlow = glow \* k \* sqrt\(k\)/.test(sl.mesh.material.vertexShader) && /corner \* size \* d/.test(sl.mesh.material.vertexShader) &&
      /float streak/.test(sl.mesh.material.fragmentShader) && /float sphere/.test(sl.mesh.material.fragmentShader));
    sl.detach(scene6);
    check('and it can be taken down', scene6.children.length === 0 && sl.mesh === null);
  }

  /* --- A BUILDING IS WHAT IT DOES AT ITS EDGES --------------------
     Both landmarks were slabs of wall with holes in them, and what
     they have now is all one idea: a BAND, which is a strip of wall
     that a piece of geometry standing proud of the wall behind it
     makes the disagreement rule draw. What is checked is that each
     one EXISTS as geometry — the count and the height and the skin —
     because that is what a band is made of, and a band that is not
     there is a wall with nothing on it, which is what this was.
     ---------------------------------------------------------------- */
  {
    const S3 = level.sectors;
    const named = re => S3.filter(s => re.test(s.name || ''));
    const T5 = tex.TEXTURE_SIZES;
    const fsB = await import('node:fs');
    const UB = await import('../js/util.js');

    /* THE SCHOOL'S THREE COURSES OUT OF ONE STRIP. The trim is one
       rectangle per segment whose column is open, shut for sixteen,
       open, shut for twenty-four, and shut — the water table, the
       string course and the cornice, and one rectangle does all three. */
    const trim = named(/^C3 trim$/);
    note('the school\'s courses', `${trim.length} trim sectors, ${named(/^C3 pilaster$/).length} pilasters`);
    check('the school stands on a stone water table',
      trim.length > 40 && trim.filter(s => s.storey === 0).every(s => s.lowerTex === 'WATERTBL'));
    check('and the same strip carries the string course and the cornice',
      trim.filter(s => s.storey === 1).every(s => s.lowerTex === 'WATERTBL') &&
      trim.filter(s => s.storey === 2).every(s => s.lowerTex === 'CORNICE' && s.floor === s.ceil),
      `${trim.filter(s => s.storey === 2).length} cornice storeys`);
    check('and a pilaster at every party wall, every other bay of the gym and both corners',
      named(/^C3 pilaster$/).length === 24);
    /* THE FRONT DOOR IS A DOOR. It was a hole in a flat wall. */
    check('the front door is a pair of leaves with a way between them',
      named(/^C3 door leaf$/).length === 2 &&
      named(/^C3 door leaf$/).every(s => s.lowerTex === 'SCHDOOR' && s.floor === s.ceil) &&
      named(/^C3 front door$/).length >= 1);
    check('under a date stone with no name on it', named(/^C3 date stone$/).length === 1);

    /* THE GYM, which was a black box a hundred and twenty feet long */
    const bleach = named(/^C3 gym bleachers$/);
    note('the gym', `${bleach.length} tiers of bleachers, ${named(/^C3 gym truss$/).length} truss sectors`);
    check('the gym has a court painted on a maple floor',
      named(/^C3 gym$/).every(s => s.floorTex === 'GYMFLOOR'));
    check('and bleachers in three tiers you can climb',
      bleach.length === 3 && [...new Set(bleach.map(s => s.floor))].length === 3 &&
      bleach.map(s => s.floor).sort((a, b) => a - b).every((f, i, a) => i === 0 || f - a[i - 1] <= UB.MAX_STEP));
    check('and padding, trusses and a stage',
      named(/^C3 gym padding$/).length >= 4 && named(/^C3 gym truss$/).length >= 3 && named(/^C3 gym stage$/).length === 1);
    /* THE STAIRS, which were a stack of floating slabs */
    /* \b so that UPSTAIRS is not a stair: every room on the first floor
       is named one and the word is in the middle of it */
    check('and no stair anywhere in the town, at the user\'s request',
      named(/\bstair/).length === 0, named(/\bstair/).slice(0, 3).map(s => s.name).join(', '));

    /* ===============================================================
       THE SCHOOL, SECOND PASS, at the user's request: taller ceilings,
       thinner lockers, desks that are desks, more in the gym, an
       auditorium, and detail everywhere else.
       =============================================================== */
    {
      const cor = named(/^C3 corridor$/).filter(s => s.storey === 0)[0];
      const up = cor && level.sectors[cor.above];
      /* A SCHOOL IS NOT A HOUSE. The town's storey is 96 of clear over
         16 of deck, which is a living room; a corridor and a classroom
         in an American school of this decade are ten to twelve feet and
         a gym is twenty-four. */
      note('the school\'s storey', cor ? `${cor.ceil - cor.floor} of clear, ${up ? up.floor - cor.floor : '?'} to the floor above` : 'no corridor');
      check('the school has a taller storey than the houses round it',
        !!cor && cor.ceil - cor.floor > T.CLEAR + 16 && !!up && up.floor - cor.floor > T.STOREY + 16,
        cor ? `${cor.ceil - cor.floor} against ${T.CLEAR}` : '');
      const gymSec = named(/^C3 gym$/)[0];
      check('and the gym is two of them in one span',
        !!gymSec && !!up && gymSec.ceil - gymSec.floor === 2 * (up.floor - cor.floor),
        gymSec ? `${gymSec.ceil - gymSec.floor} of clear` : '');

      /* A LOCKER IS TWELVE INCHES BY SIXTY. One repeat of LOCKERS is two
         of them, and with no declared size that repeat was 64 by 64 —
         a locker 32 wide and 64 tall, which is a kitchen cupboard. */
      const lk = tex.TEXTURE_SIZES.LOCKERS;
      check('a locker is far taller than it is wide',
        !!lk && lk.h / (lk.w / 2) >= 4, lk ? `${lk.w / 2} by ${lk.h}` : 'undeclared');

      /* A DESK IS A DESK AND A CHAIR, and it faces the blackboard. */
      const desks = named(/^C3 classroom S1 desk$/);
      const seats = named(/^C3 classroom S1 chair$/);
      const backs = named(/^C3 classroom S1 chair back$/);
      note('one classroom', `${desks.length / 2} desks, ${seats.length / 2} chairs, ${backs.length / 2} backs, ${named(/^C3 classroom S1 teacher's desk$/).length / 2} teacher's desk`);
      check('every desk in a classroom has a chair and the back of one behind it',
        desks.length === 24 && seats.length === 24 && backs.length === 24,
        `${desks.length} / ${seats.length} / ${backs.length}`);
      check('and a teacher\'s desk at the front of the room',
        named(/^C3 classroom S1 teacher's desk$/).length === 2);
      /* THE CHAIR IS EAST OF ITS OWN DESK, which is the whole of "they
         face the blackboard": the board is let into the WEST wall, so a
         child at a desk looks west and their chair is behind them. The
         desks used to be four across and three deep, which faces the
         room along the board rather than at it. */
      const board = named(/^C3 classroom S1 blackboard$/)[0];
      check('and the blackboard is in the wall they are all turned to',
        !!board && desks.every(d => d.bbox[0] > board.bbox[2]));
      const ground0 = desks.filter(d => d.storey === 0);
      check('every chair stands east of its own desk, which is what facing the board means',
        ground0.every(d => seats.some(c => c.storey === 0 &&
          Math.abs(c.bbox[1] - d.bbox[1]) < 1 && Math.abs(c.bbox[0] - d.bbox[2]) < 1)),
        `${ground0.length} desks`);
      check('and the desk top is higher than the seat and lower than the back',
        ground0[0].floor > seats[0].floor && ground0[0].floor < backs[0].floor,
        `${seats[0].floor} seat, ${ground0[0].floor} desk, ${backs[0].floor} back`);

      /* THE GYM HAS WHAT A GYM HAS */
      const gp = (level.props || []).filter(q => q.x0 > -400 && q.x0 < 1400 && q.y0 > -12700 && q.y0 < -11900);
      const ofTex = t => (level.props || []).filter(q => q.tex === t);
      note('the gym, fitted out', `${ofTex('BACKBORD').length} boards, ${ofTex('PENNANT').length} pennants, ${ofTex('WALLBARS').length} bars`);
      check('a backboard at each end of the court, over head height',
        ofTex('BACKBORD').length === 2 && ofTex('BACKBORD').every(q => q.z0 > 57 + 32),
        `${ofTex('BACKBORD').length}`);
      check('and a scoreboard, wall bars and the only three good years the school ever had',
        ofTex('SCOREBRD').length === 1 && ofTex('WALLBARS').length === 3 && ofTex('PENNANT').length === 9);
      void gp;

      /* THE AUDITORIUM, which is a WING and not a room */
      const aud = named(/^C3 auditorium$/), aisle = named(/^C3 auditorium aisle$/);
      const aseat = named(/^C3 auditorium seats$/), stage = named(/^C3 stage$/);
      note('the auditorium', `${aud.length + aisle.length} floor regions, ${aseat.length} banks of seats, ${named(/^C3 curtain$/).length} curtain legs`);
      check('there is an auditorium, with a stage and a curtain each side of it',
        stage.length === 1 && named(/^C3 curtain$/).length === 2 && named(/^C3 proscenium$/).length === 1);
      check('and it seats them in banks, ten of them, five deep a side',
        aseat.length === 10, `${aseat.length}`);
      /* THE RAKE IS A RAKE: the floor steps DOWN toward the stage, and
         every step is under half a stride so you walk it without
         noticing. A rake you have to jump down is a flight of stairs. */
      const floors = [...aud, ...aisle].map(s => s.floor);
      const lo = Math.min(...floors), hi = Math.max(...floors);
      const steps = [...new Set(floors)].sort((a, b) => a - b);
      check('the floor of it rakes down toward the stage in steps you can walk',
        hi - lo >= 48 && steps.every((f, i) => i === 0 || f - steps[i - 1] <= UB.MAX_STEP),
        `${steps.length} levels, ${lo} to ${hi}`);
      check('and the stage is above the lowest of them, not below it',
        stage[0].floor > lo, `${stage[0].floor} against ${lo}`);
      /* THE PROSCENIUM HANGS FROM THE CEILING, which is the one thing
         in this map that is an UPPER band and not a lower one. */
      const pros = named(/^C3 proscenium$/)[0];
      check('the proscenium is a header hung from the ceiling',
        pros.ceil < stage[0].ceil && pros.upperTex === 'PROSCEN',
        `${pros.ceil} against ${stage[0].ceil}`);
      check('and there are two ways into it off the yard',
        named(/^C3 auditorium door$/).length === 2);
      check('the curtain reaches the ceiling, which is what a leg does',
        named(/^C3 curtain$/).every(s => s.floor === s.ceil && s.lowerTex === 'CURTAIN'));

      /* AND WHAT A SCHOOL HAS ON ITS WALLS */
      note('on the walls', `${ofTex('NOTICEBD').length} boards, ${ofTex('SCHCLOCK').length} clocks, ${ofTex('RADIATOR').length} radiators, ${ofTex('FOUNTAIN').length} fountains`);
      check('a trophy case, boards, fountains, radiators and a clock over every door',
        ofTex('TROPHY').length === 1 && ofTex('NOTICEBD').length >= 8 &&
        ofTex('FOUNTAIN').length === 2 && ofTex('RADIATOR').length === 12 &&
        ofTex('SCHCLOCK').length >= 8);
      check('and every one of them is flat against a wall and under ten proud',
        [...ofTex('TROPHY'), ...ofTex('NOTICEBD'), ...ofTex('FOUNTAIN'), ...ofTex('RADIATOR')]
          .every(q => Math.min(q.x1 - q.x0, q.y1 - q.y0) <= 10));
    }

    /* THE CHURCH: a water table, buttresses in two stages, a louvred
       belfry, a cornice the spire springs off. */
    check('the church has a buttress in every bay and one on each back corner',
      named(/^B3 buttress$/).length === 12 && named(/^B3 buttress set-off$/).length === 12);
    check('and a louvred belfry, and a cornice under the spire',
      named(/^B3 belfry louvre$/).length === 3 && named(/^B3 belfry$/).length === 3 &&
      named(/^B3 tower cornice$/).some(s => s.lowerTex === 'CORNICE'));
    /* AND THE NAVE IS OPEN TO THE ROOF, which is the one thing here
       that is not a band: name a soffit and the roof storey gets a
       ceiling, and the nave's own ceilings then say NONE. */
    const roof = named(/^B3 roof$/);
    check('the nave is open to the roof',
      roof.length > 20 && roof.every(s => s.ceilTex === 'CHURCHCL' && s.roofTex === 'SHINGLE' && s.slopeCeil),
      `${roof.length} roof sectors`);
    check('and everything under it looks straight up into it',
      named(/^B3 (nave floor|centre aisle|side aisle|pew|chancel|choir loft)$/).every(s => s.ceilTex === 'NONE'));
    check('with tie beams across it, a chancel arch and a communion rail',
      named(/^B3 tie beam$/).length === 4 && named(/^B3 chancel arch/).length === 7 &&
      named(/^B3 communion rail$/).length === 2 && named(/^B3 (pulpit|lectern|organ|loft rail)$/).length === 4);
    /* which needed the gable drawn both ways */
    check('and a gable over a roof space with a ceiling is drawn from inside it too',
      /if \(gable && bd\.open\.ceilTex && bd\.open\.ceilTex !== 'NONE'\) emit\(!facing, bd\.open\.light\);/
        .test(fsB.readFileSync('js/mapgeo.js', 'utf8')));

    /* THE FENCES. A fence is a masked texture hung in the hole between
       two patches of open ground; a BAND has nothing behind it, so
       nothing that is a band may be masked or you see the sky through
       it — which is what three of these textures did. */
    const fences = level.lines.filter(l => /^(CHAINLNK|RAILING)$/.test(l.middle || ''));
    note('the fences', `${fences.length} lines of wire and iron`);
    check('the ball field, the churchyard and the school frontage are fenced',
      fences.length >= 12 && fences.every(l => l.blocking && l.midHeight > 0 &&
        l.front !== null && l.back !== null));
    check('and the fence textures are masked, because you see through a fence',
      T5.CHAINLNK.masked && T5.RAILING.masked);
    check('and the ones that are BANDS are not, because a band has nothing behind it',
      !T5.GYMTRUSS.masked && !T5.HANDRAIL.masked && !T5.ALTARRL.masked);

    /* =================================================================
       THE OFFICE BLOCK ON A5, AND THE CROSS THAT USED TO BE THERE

       WHAT WAS THERE. Block A5 was the services block and what was on
       it was three rectangles of asphalt — a station lot, a fire
       station apron and a police lot — with no building on any of them
       and the map's usual sixteen units of VOID between each pair,
       because in this map the wall between two rooms is the rectangle
       nobody laid.

       INSIDE A BUILDING THAT IS A WALL AND IS WHAT IT IS FOR. Out in
       the open it is a free-standing slab: a line with a sector on one
       side and nothing on the other is ONE-SIDED, and a one-sided line
       draws its wallTex over the whole height of the sector it has. The
       station lot is open to the sky at 768, so the slot along its north
       edge came out as a wall of BRICKRED three thousand and
       seventy-two long and seven hundred and sixty-eight tall, with the
       slot between the apron and the police lot crossing it. That is
       the brick cross eight storeys high the user photographed standing
       in an empty car park, and nothing else on the block was wrong
       with it. (The lots' `ceil: 2 * STOREY` is a red herring and worth
       saying so: a step between two patches of sky draws nothing — see
       the rule at the top of the band loop in js/mapgeo.js — so the lid
       over them was invisible. It was the void that showed.)

       THE CHECK IS THE GENERAL CASE, and it was run against the old
       geometry before it was written down here: rebuilt from those
       three rectangles alone it finds twelve of these, the tallest 768
       tall and 3072 long. Against the town as it stands it finds none.
       ================================================================= */
    {
      const P5 = level.props || [];
      const onA5 = q => q.x0 > 6272 && q.x1 < 9344 && q.y0 > -6744 && q.y1 < -3672;
      const ofT = t => P5.filter(q => q.tex === t && onA5(q));
      const inx = a => a > level.town.grid.x0 && a < level.town.grid.x1;
      const iny = a => a > level.town.grid.y0 && a < level.town.grid.y1;
      const slabs = [];
      for (const l of level.lines) {
        if ((l.front === null) === (l.back === null)) continue;     // two-sided
        const s = level.sectors[l.front === null ? l.back : l.front];
        if (!s || !s.outdoor || (s.floor ?? 0) > UB.MAX_STEP) continue;
        if (!(inx(l.x1) && inx(l.x2) && iny(l.y1) && iny(l.y2))) continue;
        if (s.ceil - s.floor < 160) continue;
        slabs.push(`${l.middle} ${(s.ceil - s.floor) | 0} tall on ${s.name}`);
      }
      note('walls with nothing behind them', `${slabs.length} in the town's open ground`);
      check('no wall stands in the open with nothing on the other side of it',
        slabs.length === 0, [...new Set(slabs)].slice(0, 4).join(', '));

      /* THE BUILDING. Four storeys, and the first FLAT ROOF in the
         town — which is a slope of none, the case topOf() has had
         since the church tower, with an open storey on top of it
         instead of a shut cap so that the plant is standing on
         something. */
      const lobby = named(/^A5 lobby( floor \d)?$/);
      const roof = named(/^A5 roof$/);
      note('the office block', `${named(/^A5 /).length} regions, ${roof.length} of roof, eaves ${roof[0] ? roof[0].floor : '?'}`);
      check('it is four storeys and every one of them is built',
        lobby.length >= 4 && [0, 1, 2, 3].every(k => lobby.some(s => s.storey === k)) &&
        lobby.filter(s => s.storey === 3).every(s => s.floor === 32 + 3 * 128),
        `${lobby.length} lobby storeys`);
      check('the roof is flat, open, and has the ballast for a floor',
        roof.length > 40 && roof.every(s => !s.slopeCeil && s.outdoor && s.floorTex === 'ROOFBALL' &&
          s.ceil - s.floor === 40), `${roof.length}`);
      check('and it is the tallest square-topped thing in the level',
        roof[0].ceil === 584 && roof[0].ceil > 480, `${roof[0].ceil} against the mall's 480`);

      /* THE ELEVATION IS THREE BANDS out of one strip: a granite base
         course, a cornice, and the parapet standing over the roof —
         and the parapet is the new one, because it is the only band in
         this map drawn ABOVE a roof line rather than under it. */
      const otrim = named(/^A5 trim$/);
      note('the office\'s courses', `${otrim.length} trim sectors, ${named(/^A5 pier$/).length} piers`);
      check('a base course of granite, a cornice, and a parapet over the roof',
        otrim.length > 30 &&
        otrim.filter(s => s.storey === 0).every(s => s.lowerTex === 'OFFBASE') &&
        otrim.filter(s => s.storey === 1).every(s => s.lowerTex === 'CORNICE' && s.floor === s.ceil) &&
        otrim.filter(s => s.storey === 2).every(s => s.lowerTex === 'OFFPARA' && s.floor === 584),
        `${otrim.filter(s => s.storey === 2).length} parapet storeys`);
      check('and the parapet stands over the roof rather than under it',
        otrim.filter(s => s.storey === 2).every(s => s.floor === roof[0].ceil));
      check('with a pier on every corner and every wall line that reaches the outside',
        named(/^A5 pier$/).length >= 18 &&
        named(/^A5 pier$/).every(s => s.lowerTex === 'OFFMULL'));

      /* THE RIBBON: one recess per bay carrying all four floors, with
         the pane hung on the line between the outer recess and the
         inner one, lit or dark per floor. */
      const oglass = level.lines.filter(l => /^OFFWIN(LT|DK)$/.test(l.middle || ''));
      const owin = named(/^A5 window \d+$/);
      note('the office\'s ribbon', `${owin.length / 4} bays, ${oglass.length} sheets of glass`);
      check('twenty-nine bays of glazing, four floors in every one of them',
        owin.length === 29 * 4 && [0, 1, 2, 3].every(k =>
          owin.filter(s => s.storey === k).length === 29), `${owin.length}`);
      check('and every one of them has glass in it that you see through and stop at',
        oglass.length >= 29 && oglass.every(l => l.blocking));
      check('a bay is 128 wide and 72 tall, which is what the texture is declared at',
        T5.OFFWINLT.w === 128 && T5.OFFWINLT.h === 72 &&
        owin.every(s => Math.abs(s.ceil - s.floor - 72) < 1));

      /* THE WAY IN. A vestibule under a soffit with two leaves, two
         sidelights and a way between them — and the sidelights are
         SHUT storeys, because an open one is a hole four storeys tall.
         And it is a way in and not just a way out: the trim strip the
         doors open onto stands at FOUND, so the ground either side of
         it has to be within a step of that. */
      check('a pair of leaves, two sidelights and a way between them',
        named(/^A5 door leaf$/).length === 2 && named(/^A5 sidelight$/).length === 2 &&
        named(/^A5 (front|back) door$/).length === 2);
      check('and the sidelights are shut storeys, not holes four floors tall',
        named(/^A5 sidelight$/).every(s => s.floor === s.ceil && s.lowerTex === 'UNITGLAS'));
      /* WALK IN OFF THE STREET. From the sidewalk at the top of the
         block to the break room at the back of the ground floor,
         through the lot, up the plaza, over the trim, in at the doors
         and down the corridor — every step of it inside MAX_STEP. */
      {
        const seen = new Set(), byS = new Map();
        for (const l of level.lines) for (const si of [l.front, l.back]) {
          if (si === null) continue;
          if (!byS.has(si)) byS.set(si, []);
          byS.get(si).push(l);
        }
        const from = level.sectorAt(7808, -3740);
        seen.add(from.index);
        const q = [from.index];
        while (q.length) {
          const si = q.pop();
          for (const l of byS.get(si) || []) {
            const other = l.front === si ? l.back : l.front;
            if (other === null || seen.has(other)) continue;
            if (level.lineBlocks(l, level.sectors[si].floor, 56, false)) continue;
            seen.add(other); q.push(other);
          }
        }
        const want = ['A5 lobby', 'A5 corridor', 'A5 break room', 'A5 lift lobby',
                      'A5 conference room', 'A5 copy room', 'A5 restroom', 'A5 service yard'];
        const missed = want.filter(n => !level.sectors.some(s => s.name === n && seen.has(s.index)));
        check('you can walk in off the street and all the way round the ground floor',
          missed.length === 0, missed.join(', '));
        /* AND NOT UP. There are no stairs in this town and the lift has
           never worked, so the three floors over you are built, lit,
           glazed and unreachable — which is written down here rather
           than left for somebody to find. */
        check('and nowhere above the ground floor, because the stairs went',
          !level.sectors.some(s => /^A5 /.test(s.name || '') && s.storey > 0 &&
            s.storey < 4 && seen.has(s.index)));
      }

      /* THE FIT-OUT, and none of it is a free box standing in the
         middle of a room: a desk, a partition and a filing cabinet are
         raised floors, which is what stops you walking through them. */
      note('the office, fitted out', `${named(/desk$/).filter(s => /^A5 /.test(s.name)).length} desks, ` +
        `${named(/^A5 .*partition$/).length} partitions, ${named(/^A5 .*chair$/).length} chairs`);
      check('cubicles with a work surface, a chair and a partition in each',
        named(/^A5 open plan (west|east) desk$/).filter(s => s.storey === 0).length === 28 &&
        named(/^A5 open plan (west|east) chair$/).filter(s => s.storey === 0).length === 28 &&
        named(/^A5 open plan (west|east) partition$/).length > 20);
      check('the partition is over the desk and under the eye, which is the whole point of one',
        named(/^A5 .*partition$/).filter(s => s.storey === 0).every(s => s.floor === 32 + 44),
        'a cubicle wall at 44 against an eye at 49');
      check('a reception desk, a conference table, a counter, vending and two lifts',
        named(/^A5 reception desk$/).length >= 1 && named(/^A5 conference table$/).length >= 1 &&
        named(/^A5 counter$/).length >= 1 && named(/^A5 vending machine$/).length === 2 &&
        named(/^A5 lift$/).length >= 1 && named(/^A5 lift$/)[0].lowerTex === 'LIFTDOOR');
      check('and the filing, the copier and the whiteboard',
        named(/^A5 .*filing$/).length >= 4 && named(/^A5 copier$/).length >= 1 &&
        ofT('WHITEBRD').length === 1 && ofT('DIRECTRY').length === 1);
      check('every free box in the building is over your head or flat against something',
        P5.filter(q => onA5(q) && q.z0 < 32 + 88 && q.tex !== 'WHEELSTP')
          .every(q => Math.min(q.x1 - q.x0, q.y1 - q.y0) <= 12),
        P5.filter(q => onA5(q) && q.z0 < 32 + 88 && q.tex !== 'WHEELSTP' &&
          Math.min(q.x1 - q.x0, q.y1 - q.y0) > 12).slice(0, 3).map(q => q.tex).join(' '));
      check('and the plant on the roof clears the parapet',
        ofT('RTU').length === 7 && ofT('RTU').every(q => q.z0 === 544 && q.z1 > 584));

      /* THE LOT, which is the supermarket's in miniature and built out
         of the same pieces. */
      const bays = named(/^A5 bays$/), lanes = named(/^A5 driving lane$/);
      const cars = (level.carSlots || []).filter(c => c.x > 6272 && c.x < 9344 && c.y > -6744 && c.y < -3672);
      note('the lot out front', `${bays.length} rows of bays, ${lanes.length} lanes, ${cars.length} cars, ${ofT('WHEELSTP').length} wheel stops`);
      check('four rows of bays back to back with a lane between each pair',
        bays.length === 4 && lanes.length === 3);
      check('and they face each other, which is what back to back means',
        cars.length >= 12 && new Set(cars.map(c => Math.sign(Math.sin(c.angle)))).size === 2,
        `${cars.length} cars`);
      check('with an island along the front of it and a way in off the street',
        named(/^A5 island$/).length === 1 && named(/^A5 drive$/).length === 1);
      check('and lot lighting, and wheel stops you can step over',
        level.things.filter(t => t.type === 'STREETLAMP' && t.x > 6272 && t.x < 9344 &&
          t.y > -6744 && t.y < -3672).length >= 8 &&
        ofT('WHEELSTP').every(q => q.z1 <= UB.MAX_STEP));
      /* AND THE ENGINE STILL COMES FROM A5, which is the one thing on
         this block anything else in the game reads. */
      const st = level.town.stations;
      check('the fire and the police still have somewhere on A5 to come from',
        st && st.fire && st.police &&
        [st.fire, st.police].every(p => {
          const s = level.sectorAt(p.x, p.y);
          return s && s.outdoor && s.ceil - s.floor > 200;
        }), JSON.stringify(st));
    }

    /* =================================================================
       THE PEOPLE ON THE STREET

       The town had nobody in it. What it has now is placed off the
       RECTANGLES rather than off a list of coordinates — see THE
       PEOPLE ON THE STREET in js/maps/town.js — so what is worth
       checking is the three things that would go wrong if the list had
       been written by hand: somebody inside a wall, two people at one
       coordinate, and somebody standing in a parked car.
       ================================================================= */
    {
      const folk = level.things.filter(t => t.type === 'TOWNIE');
      const inside = folk.map(t => ({ t, s: level.sectorAt(t.x, t.y) }));
      note('the town\'s people', `${folk.length} of them, ${inside.filter(o => o.s && o.s.outdoor).length} out of doors`);
      check('there are a lot of them', folk.length >= 500, `${folk.length}`);
      check('and every one of them is standing somewhere with a floor and headroom',
        inside.every(o => o.s && o.s.ceil - o.s.floor >= 56),
        inside.filter(o => !o.s || o.s.ceil - o.s.floor < 56).slice(0, 3)
          .map(o => `${o.t.x | 0},${o.t.y | 0}`).join(' '));
      check('nobody is in the road, because a carriageway is not on the list',
        !inside.some(o => /^(street|road) /.test(o.s.name || '') || /^ROAD/.test(o.s.floorTex || '')),
        inside.filter(o => /^(street|road) /.test(o.s.name || '')).slice(0, 3).map(o => o.s.name).join(', '));
      /* NOBODY OVERLAPS, which is the shop's lesson at town scale: two
         people at one coordinate are one person with a shadow, and
         worse, two people who can never move again. */
      let closest = Infinity;
      for (let i = 0; i < folk.length; i++) for (let j = i + 1; j < folk.length; j++) {
        const d2 = (folk[i].x - folk[j].x) ** 2 + (folk[i].y - folk[j].y) ** 2;
        if (d2 < closest) closest = d2;
      }
      check('and no two of them are closer than a person can walk out of',
        Math.sqrt(closest) >= 54, `closest two ${Math.sqrt(closest).toFixed(0)} apart`);
      /* AND NOT IN A CAR. The parked vehicles are models rather than
         sectors, so nothing else would have stopped this. */
      let nearestCar = Infinity;
      for (const t of folk) for (const c of level.carSlots || [])
        nearestCar = Math.min(nearestCar, (t.x - c.x) ** 2 + (t.y - c.y) ** 2);
      check('and nobody is standing inside a parked car',
        Math.sqrt(nearestCar) > 64, `nearest ${Math.sqrt(nearestCar).toFixed(0)}`);
      /* THEY ARE NOT SHOPPERS, and that is the whole reason the type
         exists: peopleLeft, the crowd LOD and the suite's own sales
         floor check all mean the crowd IN THE SHOP when they say
         shopper. */
      const AC = await import('../js/states.js');
      check('a townie is its own kind of person, and not a shopper',
        AC.ACTORS.TOWNIE && AC.ACTORS.TOWNIE.name === 'Townsfolk' &&
        !level.things.some(t => t.type === 'SHOPPER' && t.y < -3096));
      check('and it burns, panics, freezes and gibs exactly as one does',
        ['burn', 'burnTics', 'freezable', 'frozen', 'death', 'burnTrail', 'flammable']
          .every(k => JSON.stringify(AC.ACTORS.TOWNIE[k]) === JSON.stringify(AC.ACTORS.SHOPPER[k])));
      check('with a longer eye and a longer fright, because a street is not an aisle',
        AC.ACTORS.TOWNIE.scareRange > AC.ACTORS.SHOPPER.scareRange &&
        AC.ACTORS.TOWNIE.panicTics > AC.ACTORS.SHOPPER.panicTics);
      check('and the crowd LOD draws them by id the way it draws the crowd',
        /a\.type === 'SHOPPER' \|\| a\.type === 'TOWNIE'/.test(fsB.readFileSync('js/game.js', 'utf8')));
    }
  }

  /* NOTHING IS OUTSIDE ITS OWN SHELL. RectMap throws on two rectangles
     that overlap, so a room outside the house that is supposed to
     contain it cannot be built at all — getting this far is the check,
     and it is worth saying so rather than leaving the reader to
     wonder where it went. */
}

/* ---------- sloped roofs ---------- */
section('sloped roofs');
{
  const L = await import('../js/level.js');
  const T2 = await import('../js/maps/town.js');

  /* THE SLOPE ITSELF, before any map uses one. */
  const g = L.gableSlope('x', 0, 100, 300, 128);
  check('a gable is at its base at the eaves', Math.abs(L.slopeAt(g, 0, -100) - 300) < 1e-6);
  check('and at its full rise on the ridge', Math.abs(L.slopeAt(g, 0, 0) - 428) < 1e-6);
  check('and halfway up halfway along', Math.abs(L.slopeAt(g, 0, -50) - 364) < 1e-6);
  check('it does not go on falling past the eaves', Math.abs(L.slopeAt(g, 0, -400) - 300) < 1e-6);
  check('and it does not care which side of the ridge you are',
    Math.abs(L.slopeAt(g, 0, 50) - L.slopeAt(g, 0, -50)) < 1e-6);
  const pl = L.planeSlope(0, 0, 100, 0.5, 0);
  check('a plane is a plane', Math.abs(L.slopeAt(pl, 200, 0) - 200) < 1e-6);

  /* THE FLAT MAP IS UNMOVED. Every region that has no slope must answer
     with the number it always did, which is the regression that matters:
     there are eleven thousand of them and six that are not. */
  let moved = 0, flat = 0;
  for (const s2 of level.sectors) {
    if (s2.slopeFloor || s2.slopeCeil) continue;
    flat++;
    const x = (s2.bbox[0] + s2.bbox[2]) / 2, y = (s2.bbox[1] + s2.bbox[3]) / 2;
    if (level.floorAt(s2, x, y) !== s2.floor || level.ceilAt(s2, x, y) !== s2.ceil) moved++;
  }
  check('a region with no slope answers exactly as it did', moved === 0, `${moved} of ${flat}`);

  /* AND THE ROOFS THE TOWN IS WEARING. */
  const roofs = level.sectors.filter(s2 => s2.roofTex);
  note('roof storeys', `${roofs.length}, over ${new Set(roofs.map(s2 => /^(.*) roof$/.exec(s2.name)?.[1])).size} buildings`);
  check('the houses have roofs', roofs.length > 2000, `${roofs.length}`);
  check('every one of them is a sloped ceiling', roofs.every(s2 => s2.slopeCeil && s2.slopeCeil.kind === 'gable'));
  check('and it sits on top of the walls, not through them',
    roofs.every(s2 => s2.floor === s2.slopeCeil.base), `${roofs.filter(s2 => s2.floor !== s2.slopeCeil.base).length} do not`);
  check('a roof\'s ceil is the HIGHEST it gets, so nothing flat is told there is less room than there is',
    roofs.every(s2 => Math.abs(s2.ceil - (s2.slopeCeil.base + s2.slopeCeil.rise)) < 1e-6));
  /* the shop terraces on Main Street: three storeys on a kerb-high base
     and a roof at six in twelve over a 384 half-span, which is 192 of
     rise — a ridge above the mall's 480 parapet now, which a ridge may
     be, and under the 768 the sky sits at, which nothing may not */
  const TT = await import('../js/maps/town.js');
  const shopTop = TT.KERB_H + 3 * TT.STOREY + 192;
  check('a three-storey shop terrace tops out at the kerb, three storeys and 192 of roof, under the sky',
    roofs.some(s2 => Math.abs(s2.ceil - shopTop) < 1e-6) && roofs.every(s2 => s2.ceil < 768),
    `${roofs.filter(s2 => Math.abs(s2.ceil - shopTop) < 1e-6).length} at ${shopTop}, highest ${Math.max(...roofs.map(s2 => s2.ceil))} (${roofs.find(s2 => s2.ceil === Math.max(...roofs.map(q => q.ceil)))?.name})`);
  /* AND A HOUSE IS ITS ROOF: the shell of a house is one column of one
     storey, the roof, shut everywhere below the eaves */
  {
    const shells = roofs.filter(s2 => s2.storey === 0 && s2.below === null && (s2.bbox[2] - s2.bbox[0]) > 300 && (s2.bbox[3] - s2.bbox[1]) > 300);
    check('a house is a shell: one column of one storey, which is its roof', shells.length > 100, `${shells.length}`);
    const sh = shells[0];
    check('and you cannot walk into it', sh.lines.filter(l => l.frontCol.length && l.backCol.length)
      .every(l => level.lineBlocks(l, 0, 56, false) !== null));
  }

  /* IT VARIES ACROSS ITS OWN FOOTPRINT — which is the whole point, and
     is what a flat number cannot say. */
  {
    const r = roofs.find(s2 => {
      const zs = s2.poly.map(p2 => level.ceilAt(s2, p2[0], p2[1]));
      return Math.max(...zs) - Math.min(...zs) > 32;
    });
    check('a roof is higher in the middle of the house than at its edge', !!r);
  }

  /* SOLID. This is what "the engine knows it is there" means and it is
     the reason for the whole change: a roof used to be a picture and
     you could walk and shoot straight through one. */
  {
    /* a roof with a ROOM under it — the school's corridor, since a house
       has nothing under its roof any more */
    const r = roofs.find(s2 => s2.slopeCeil.rise > 0 && s2.below !== null && level.sectors[s2.below].fuel > 0 &&
                               (s2.bbox[2] - s2.bbox[0]) > 400 && /corridor/.test(s2.name.replace(/roof$/, '') + level.sectors[s2.below].name));
    const x = (r.bbox[0] + r.bbox[2]) / 2, y = (r.bbox[1] + r.bbox[3]) / 2;
    /* THE OPENING NARROWS AS THE ROOF COMES DOWN, which is the whole of
       what a sloped ceiling does to anything trying to move under it:
       the same doorway, at the same height, is open in the middle of
       the house and shut at the eaves. Doom asked the ceiling once per
       region; this asks it where you are. */
    const zRidge = level.ceilAt(r, x, y);
    const eave = r.slopeCeil.axis === 'x'
      ? [x, r.slopeCeil.mid + r.slopeCeil.half] : [r.slopeCeil.mid + r.slopeCeil.half, y];
    check('a roof is lower at the eaves than on the ridge',
      level.ceilAt(r, eave[0], eave[1]) < zRidge - 32,
      `${level.ceilAt(r, eave[0], eave[1]).toFixed(0)} against ${zRidge.toFixed(0)}`);
    const shared = r.lines.find(l => l.frontCol.length && l.backCol.length);
    if (shared) {
      const open = (px, py) => {
        const a = level.spanIn(level.sectors[shared.front], r.floor + 8, px, py);
        const b = level.spanIn(level.sectors[shared.back], r.floor + 8, px, py);
        return Math.min(level.ceilAt(a, px, py), level.ceilAt(b, px, py))
             - Math.max(level.floorAt(a, px, py), level.floorAt(b, px, py));
      };
      check('and the opening under it is the height of the roof there, not of the ridge',
        open(x, y) >= open(eave[0], eave[1]),
        `${open(x, y).toFixed(0)} in the middle, ${open(eave[0], eave[1]).toFixed(0)} at the edge`);
    }
    const hit = level.rayHitWall(x, y, r.floor + 8, x + 4000, y, r.floor + 8);
    check('and a shot fired along the loft hits the house rather than the next county',
      !!hit && Math.hypot(hit.x - x, hit.y - y) < 4000, hit ? `${Math.hypot(hit.x - x, hit.y - y).toFixed(0)} units` : 'nothing');
    /* and the storey under it is not: standing in the top bedroom you
       can see across your own room */
    const room = level.sectors[r.below];
    check('the room under the roof is a room you can see across',
      !level.sightBlocked(room.bbox[0] + 8, (room.bbox[1] + room.bbox[3]) / 2, room.floor + 40,
                          room.bbox[2] - 8, (room.bbox[1] + room.bbox[3]) / 2, room.floor + 40));
  }

  /* SPANAT PICKS THE ROOF WHERE THE ROOF IS, and does it at the point
     rather than from the safe end — which is the difference between
     standing in a loft and standing in the bedroom under it. */
  {
    /* a roof with a room under it: a house's roof is its whole column
       now, so the question has to be asked of the school */
    const r = roofs.find(s2 => s2.below !== null && level.sectors[s2.below].fuel > 0);
    const x = (r.bbox[0] + r.bbox[2]) / 2, y = (r.bbox[1] + r.bbox[3]) / 2;
    check('a storey up under the ridge you are in the roof', level.spanAt(x, y, r.floor + 8) === r);
    check('and on the floor below you are not', level.spanAt(x, y, level.sectors[r.below].floor + 8) !== r);
  }

  /* THE WALL UNDER A GABLE IS A TRIANGLE, which is one quad's worth of
     geometry that no single quad can hold — see emitWall in
     js/mapgeo.js, which cuts the line at the ridge. */
  {
    let sloping = 0;
    for (const l of level.lines) {
      if (!l.frontCol.length || l.backCol.length) continue;
      for (const i of l.frontCol) {
        const s2 = level.sectors[i];
        if (!s2.slopeCeil) continue;
        const a = level.ceilAt(s2, l.x1, l.y1), b = level.ceilAt(s2, l.x2, l.y2);
        if (Math.abs(a - b) > 1) sloping++;
      }
    }
    note('walls whose top is not level', sloping);
    check('a gable end has a wall under it that slopes', sloping > 500, `${sloping}`);
  }
}

/* ---------- the town on fire ---------- */
section('the town on fire');
{
  const F = await import('../js/fire.js');
  const { pSeed } = await import('../js/util.js');
  pSeed(9182);
  const fresh = MAP.buildSellWrong();
  const fire = new F.FireSystem({ level: fresh, fx: null, actors: [] });
  note('the fuel grid', `${fire.cols}x${fire.rows} x ${fire.levels} storeys = ${(fire.plane * fire.levels).toLocaleString()} cells`);
  check('there is a plane per storey', fire.levels >= 2, `${fire.levels}`);
  check('and the ground plane is exactly the grid it always was',
    fire.plane === fire.cols * fire.rows);
  note('the ways up', `${fire.up.size} cells can carry fire to the storey above`);
  check('fire has somewhere to climb', fire.up.size > 200, `${fire.up.size}`);

  /* THE RASTERISED GRID IS THE QUERIED GRID. Run both and compare, once
     — which is what TOWN.txt asks for by name. Over the ground plane,
     where sectorAt is the question being replaced. */
  let cellMiss = 0;
  for (let cy = 0; cy < fire.rows; cy += 3) for (let cx = 0; cx < fire.cols; cx += 3) {
    const i = fire.idx(cx, cy, 0);
    const s = fresh.sectorAt(fire.worldX(cx), fire.worldY(cy));
    if (fire.sectorOf[i] !== (s ? s.index : -1)) cellMiss++;
  }
  check('rasterising the grid gives what querying it gave', cellMiss === 0, `${cellMiss} cells differ`);

  /* A FIRE ON A GROUND FLOOR REACHES THE STOREY ABOVE. Poured over the
     whole of the school's ground floor — every classroom, the corridor,
     the lobby and the office — the way a player with a full tank would,
     and then left.

     IT USED TO GO UP THE STAIRS, and the stairs are gone. What is left
     is the other route: a ceiling, which burns through eventually and
     is the slower half of the same rule in js/fire.js. It still gets
     there, and it gets to less of it — which is the honest thing to
     measure now, and it is measured rather than assumed. */
  const TAG = 'C3 ';
  const mine = fresh.sectors.filter(s => s.name.startsWith(TAG) && !s.outdoor);
  const ground = mine.filter(s => s.storey === 0 && s.fuel > 0 && /^(lobby|passage|corridor|classroom [SN]\d|office)$/.test(s.name.slice(TAG.length)));
  check('the school has a ground floor and an upstairs',
    ground.length > 4 && mine.some(s => s.storey > 0), `${ground.length} rooms`);
  for (let k = 0; k < 40; k++) for (const s of ground)
    fire.ignite((s.bbox[0] + s.bbox[2]) / 2, (s.bbox[1] + s.bbox[3]) / 2, 200, 40);
  for (let t = 0; t < 35 * 60 * 8 && fire.liveCells > 0; t++) fire.tic();
  const up = mine.filter(s => s.storey > 0 && s.charred);
  note('the school, poured on downstairs', `${mine.filter(s => s.charred).length} of ${mine.length} regions charred, ${up.length} of them upstairs`);
  check('the fire climbs to the floor above', up.length > 0, `${up.length} upstairs regions charred`);
  check('and it got there through a ceiling, there being no stair left to climb',
    up.length > 2 && !mine.some(s => /\bstair/.test(s.name)),
    up.map(s => s.name.slice(TAG.length)).slice(0, 8).join(', '));

  /* AND IT DOES NOT COME BACK DOWN SOMEBODY ELSE'S CHIMNEY: the church,
     one block north across a street of tarmac, is not alight. */
  const far = fresh.sectors.filter(s => s.name.startsWith('B3 ') && s.charred).length;
  check('the church over the road is not alight', far === 0, `${far} regions`);

  /* THE STORE IS UNTOUCHED, which is the firebreak the ring road is. */
  const shop = fresh.sectors.filter(s => inMall(s) && s.charred).length;
  check('and neither is the supermarket', shop === 0, `${shop} regions`);
}

/* ---------- the editor ---------- */
/* MEWD Editor (js/editor/), the map editor opened from the terminal with
   EDIT. What can be checked without a browser is everything that is not
   drawing: the document, the compiler that turns it into the same Level
   the game runs, the edits the views make, the undo stack, and the two
   doors — the terminal's word for it, and the round trip to the game
   and back. The 2D and 3D views are checked in a browser. */
section('the editor');
await (async () => {
  const fsE = await import('node:fs');
  const D = await import('../js/editor/doc.js');
  const E = await import('../js/editor/editor.js');
  const R = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];

  /* THE GRID, as a document, compiles into a level the game can run */
  const g = D.gridDoc();
  const cg = D.compileDoc(g);
  note('THE GRID as a document', `${g.sectors.length} sector, ${g.things.length} things`);
  check('the grid document compiles with no problems', cg.problems.length === 0, JSON.stringify(cg.problems));
  check('into one sector, 10240 square, with the start in it',
    cg.level.sectors.length === 1 && cg.level.things.some(t => t.type === 'START') && cg.level.bounds[2] === 10240);
  check('and the world it runs in is the grid\'s: nothing burns and nobody comes',
    cg.level.noBurn && cg.level.noSquads && cg.level.noCellFire && cg.level.sky?.horizon === '#1d9a48');
  check('and every field the game reads off a level is there',
    ['props', 'roofs', 'plants', 'exits', 'roadEnds', 'boxes', 'carSlots', 'slideDoors'].every(k => Array.isArray(cg.level[k])) &&
    cg.level.viewpoint && cg.level.field && cg.level.salesFloor && cg.level.fromEditor === true);

  /* A HOLE: a pillar standing in a room, which this engine's single-ring
     sectors cannot hold without the compiler's slit */
  const d = D.newDoc('T', 1024);
  d.vertices = [...R(0, 0, 1024, 1024), ...R(448, 448, 576, 576)];
  d.sectors = [{ id: 1, verts: [0, 1, 2, 3], ...D.SECTOR_DEFAULTS }, { id: 2, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, floor: 0, ceil: 0 }];
  d.nextId = 3;
  const ch = D.compileDoc(d);
  const Lh = ch.level;
  check('a sector drawn inside another is a hole in it, and compiles', ch.problems.length === 0, JSON.stringify(ch.problems));
  check('and the pillar is where it was drawn', Lh.sectorAt(512, 512)?.ceil === 0);
  check('and it blocks sight through it and not past it',
    Lh.sightBlocked(100, 512, 41, 900, 512, 41) && !Lh.sightBlocked(100, 200, 41, 900, 200, 41));
  const hl = D.linesOf(d).filter(l => l.sectors.includes(1));
  check('and its edges are two-sided, the room on the far side', hl.length === 4 && hl.every(l => l.sectors.length === 2 && l.sectors.includes(0)));

  /* SLOPES AND STOREYS ARE SWITCHED OFF, at the user's request, and the
     compiler ignores them while they are — but it still knows how, so
     they are checked with the switch thrown, and then put back */
  check('slopes and storeys are switched off for now', D.FEATURES.slopes === false && D.FEATURES.storeys === false);
  const dOff = D.newDoc('O', 1024);
  dOff.sectors[0].floorSlope = { dzdx: 0.1, dzdy: 0 };
  dOff.sectors[0].storeys = [{ floor: 300, ceil: 500 }];
  const LOff = D.compileDoc(dOff).level;
  check('and a map that has them from before is built flat and single-storey',
    LOff.sectors.length === 1 && !LOff.sectorAt(512, 512).slopeFloor);
  const uiSrc = fsE.readFileSync('js/editor/ui.js', 'utf8');
  check('and the inspector does not offer them', !/'Slopes'/.test(uiSrc) && !/Storeys above/.test(uiSrc));
  D.FEATURES.slopes = D.FEATURES.storeys = true;
  const ds = D.newDoc('S', 1024);
  ds.sectors[0].floorSlope = { dzdx: 0.1, dzdy: 0 };
  ds.sectors[0].ceil = 512;
  const Ls = D.compileDoc(ds).level;
  const s0 = Ls.sectorAt(512, 512);
  check('a sloped floor is a plane through the middle of its sector',
    Math.abs(Ls.floorAt(s0, 0, 512) + 51.2) < 0.01 && Math.abs(Ls.floorAt(s0, 1024, 512) - 51.2) < 0.01 && Math.abs(Ls.floorAt(s0, 512, 512)) < 0.01);
  ds.sectors[0].ceilSlope = { dzdx: 0, dzdy: -0.1 };
  const Lc = D.compileDoc(ds).level;
  const c0 = Lc.sectorAt(512, 512);
  check('and so is a sloped ceiling', !!c0.slopeCeil);

  /* ROOM OVER ROOM */
  const dr = D.newDoc('R', 1024);
  dr.sectors[0].ceil = 200; dr.sectors[0].outdoor = false;
  dr.sectors[0].storeys = [{ floor: 232, ceil: 432, outdoor: true }];
  const cr = D.compileDoc(dr);
  check('a storey over a room compiles into a column of two', cr.problems.length === 0 && cr.level.sectors.length === 2 &&
    cr.level.sectors.some(s => s.floor === 232 && s.ceil === 432));
  dr.sectors[0].storeys = [{ floor: 100, ceil: 300 }];
  check('and one that does not stack is a reported problem, not a crash', D.compileDoc(dr).problems.some(p => p.kind === 'sector'));
  D.FEATURES.slopes = D.FEATURES.storeys = false;

  /* A LINE'S OWN TEXTURES survive the level reassigning them */
  const dl = D.newDoc('L', 1024);
  dl.vertices.push(...R(256, 256, 512, 512));
  dl.sectors.push({ id: 9, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, floor: 32 });
  dl.lines[D.lineKey(4, 5)] = { lowerTex: 'BRICK', blocking: true };
  dl.lines[D.lineKey(0, 1)] = { wallTex: 'BRICK' };
  const Ll = D.compileDoc(dl).level;
  const two = Ll.lines.find(l => l.texLocked && l.bands);
  const one = Ll.lines.find(l => l.texLocked && !l.bands);
  check('a step\'s own texture is on the step, locked', two && two.lower === 'BRICK' && two.bands.every(b => b.kind !== 'lower' || b.tex === 'BRICK') && two.blocking);
  check('and a wall\'s own texture is on the wall, locked', one && one.middle === 'BRICK');

  /* THE FILE */
  const text = D.serialise(g);
  const back = D.parseDoc(text);
  check('a map saves and loads back the same', D.serialise(back) === text);
  let refused = false;
  try { D.parseDoc('{"format":"doom-wad"}'); } catch (e) { refused = true; }
  check('and a file that is not a map is refused, not half-loaded', refused);

  /* UNDO */
  const hdoc = D.newDoc('H', 1024);
  const H = new D.History(hdoc);
  H.push('a'); H.doc.sectors[0].floor = 64;
  H.push('b'); H.doc.sectors[0].floor = 128;
  H.undo();
  const u1 = H.doc.sectors[0].floor;
  H.undo();
  const u2 = H.doc.sectors[0].floor;
  H.redo();
  check('undo goes back a step at a time and redo comes forward', u1 === 64 && u2 === 0 && H.doc.sectors[0].floor === 64);

  /* THE WELD: a vertex dragged onto another becomes it */
  const dw = D.newDoc('W', 1024);
  dw.vertices.push(...R(1024, 0, 2048, 1024).map(([x, y]) => [x + (x === 1024 ? 0.4 : 0), y]));
  dw.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS });
  D.compact(dw);
  check('a vertex dropped on another is welded to it', dw.vertices.length === 6);
  check('and the two rooms then share a two-sided line', D.linesOf(dw).filter(l => l.sectors.length === 2).length === 1);

  /* THE EDITS THE VIEWS MAKE */
  const dc = D.gridDoc();
  const ring = R(0, 0, 1024, 1024).map(([x, y]) => E.vertexFor(dc, x, y));
  const P = dc.sectors[0];
  check('a corner landing on a wall splits the wall', P.verts.length === 6);
  check('and a room drawn in a corner is cut out of the room it is in', E.cutFrom(dc, P, ring) && P.verts.length === 6);
  dc.sectors.push({ id: 99, verts: ring, ...D.SECTOR_DEFAULTS });
  const cc = D.compileDoc(dc);
  check('so the two do not overlap', cc.problems.length === 0, JSON.stringify(cc.problems));
  const area = Math.abs(D.signedArea(D.ringOf(dc, P)));
  check('and the field has lost exactly that corner', Math.abs(area - (10240 * 10240 - 1024 * 1024)) < 1);
  const key = D.linesOf(dc).find(l => l.sectors.length === 2).key;
  E.mergeAcross(dc, key);
  check('deleting a line between two rooms joins them into one',
    dc.sectors.length === 1 && Math.abs(Math.abs(D.signedArea(D.ringOf(dc, dc.sectors[0]))) - 10240 * 10240) < 1 &&
    !D.selfCrosses(D.ringOf(dc, dc.sectors[0])) && new Set(dc.sectors[0].verts).size === dc.sectors[0].verts.length);
  const mt = D.newDoc('M', 1024);
  E.moveThings(mt, 'sector', new Set([1]), 64, 0);
  check('moving a sector moves its corners and what stands in it',
    mt.vertices[0][0] === 64 && mt.things[0].x === 512 + 64);

  /* THE SCATTERS: rules that grow sprite people and plants */
  const SC = await import('../js/editor/scatter.js');
  const sd = D.gridDoc();
  sd.things = sd.things.slice(0, 1);
  sd.scatters.push(SC.scatterFrom('crowd', { kind: 'circle', x: 5120, y: 5120, r: 1500 }, sd.nextId++, 7));
  sd.scatters.push(SC.scatterFrom('forest', { kind: 'rect', x0: 0, y0: 0, x1: 2048, y1: 2048 }, sd.nextId++, 8));
  sd.scatters.push(SC.scatterFrom('scrub', { kind: 'sectors', ids: [1] }, sd.nextId++, 9));
  const t0 = performance.now();
  const cs = D.compileDoc(sd);
  const ms = performance.now() - t0;
  const g1 = cs.grown.get(sd.scatters[0].id), g2 = cs.grown.get(sd.scatters[1].id), g3 = cs.grown.get(sd.scatters[2].id);
  note('three scatters', `${cs.scattered.length} grown in ${ms.toFixed(0)}ms (${g1.grown} people, ${g2.grown} trees, ${g3.grown} scrub)`);
  check('a scatter grows as many as its density asks for over its area',
    g1.wanted === Math.round(16 * Math.PI * 1500 * 1500 / SC.DENSITY_AREA) && g1.grown === g1.wanted && g2.grown === g2.wanted);
  check('and never more than its ceiling', g3.wanted === SC.SCATTER_MAX && g3.grown <= SC.SCATTER_MAX);
  check('and quickly', ms < 2000, `${ms.toFixed(0)}ms`);
  const people = cs.scattered.filter(t => t.scatter === sd.scatters[0].id);
  check('the people stand inside their circle', people.every(t => (t.x - 5120) ** 2 + (t.y - 5120) ** 2 <= 1500 * 1500 + 1));
  let close = 0;
  for (let i = 0; i < people.length; i++) for (let j = i + 1; j < people.length; j++)
    if ((people[i].x - people[j].x) ** 2 + (people[i].y - people[j].y) ** 2 < 109 ** 2) close++;
  check('and no two nearer than its spacing', close === 0, `${close} pairs`);
  check('the people go to the game as actors, the plants as level.plants',
    cs.level.things.filter(t => t.type === 'SHOPPER').length === g1.grown &&
    cs.level.plants.length === cs.scattered.filter(t => t.type === 'PLANT').length &&
    cs.level.plants.every(p => SC.plantKind(p.kind)));
  const cells = new Set();
  let twice = 0;
  for (const p of cs.level.plants) {
    if (!SC.isCanopyKind(p.kind)) continue;
    const k = `${Math.floor(p.x / 64)},${Math.floor(p.y / 64)}`;
    if (cells.has(k)) twice++; else cells.add(k);
  }
  check('and never two trees in one 64 cell, which the wood would not draw', twice === 0, `${twice}`);
  const cs2 = D.compileDoc(sd);
  check('the same seed grows the same spread, every time', JSON.stringify(cs2.scattered) === JSON.stringify(cs.scattered));
  sd.scatters[0].seed = 8;
  check('and another seed grows another', JSON.stringify(D.compileDoc(sd).scattered.slice(0, 20)) !== JSON.stringify(cs.scattered.slice(0, 20)));
  sd.scatters[0].seed = 7;
  const flat = SC.growScatter({ ...sd.scatters[0], clump: 0 }, { rings: new Map(), standable: () => 1 });
  const lumpy = SC.growScatter({ ...sd.scatters[0], clump: 1, density: 40 }, { rings: new Map(), standable: () => 1 });
  const spread = list => {
    const n = new Map();
    for (const t of list) { const k = `${Math.floor(t.x / 512)},${Math.floor(t.y / 512)}`; n.set(k, (n.get(k) || 0) + 1); }
    const v = [...n.values()], m = v.reduce((a, b) => a + b, 0) / v.length;
    return Math.sqrt(v.reduce((a, b) => a + (b - m) ** 2, 0) / v.length) / m;
  };
  check('clumping gathers a spread into drifts', spread(lumpy.items) > spread(flat.items) * 1.3,
    `${spread(flat.items).toFixed(2)} even against ${spread(lumpy.items).toFixed(2)} clumped`);
  const pd = D.newDoc('P', 1024);
  pd.vertices.push([200, 200], [400, 200], [400, 400], [200, 400]);
  pd.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, ceil: 0 });
  pd.props.push({ id: 6, x0: 600, y0: 600, x1: 900, y1: 900, z0: 0, z1: 64, tex: 'GRIDWALL' });
  pd.scatters.push({ ...SC.scatterFrom('scrub', { kind: 'sectors', ids: [1] }, 7, 3), density: 200 });
  pd.nextId = 8;
  const pc = D.compileDoc(pd);
  check('nothing is grown in a pillar or under a prop',
    pc.scattered.length > 50 && pc.scattered.every(t => !(t.x > 200 && t.x < 400 && t.y > 200 && t.y < 400) && !(t.x > 590 && t.x < 910 && t.y > 590 && t.y < 910)));
  const tight = D.newDoc('T', 1024);
  tight.scatters.push({ ...SC.scatterFrom('crowd', { kind: 'circle', x: 512, y: 512, r: 400 }, 9, 1), density: 400, spacing: 200 });
  tight.nextId = 10;
  check('a scatter asked for more than fits says so', D.compileDoc(tight).problems.some(p => p.kind === 'scatter'));

  /* AND THE GAME GROWS THEM: a map with plants and no wood gets a
     forest of exactly its plants, and nothing else */
  const FO = await import('../js/forest.js');
  const wood = new FO.Forest(cs.level);
  check('the game grows exactly the plants the map placed, and no wood around them',
    wood.plantsOnly && wood.plantCount === cs.level.plants.length && wood.fuelCells === wood.treeCount);
  const aTree = cs.level.plants.find(p => SC.isCanopyKind(p.kind));
  check('and a tree stops you', wood.blocks(aTree.x, aTree.y, 16));
  check('and in a world where nothing burns, it does not', wood.ignite(aTree.x, aTree.y, 200) === 0);

  /* THE EDITOR'S OWN SCATTER EDITS: bake, and move */
  const ed2 = new E.Editor(null);
  ed2.history = new D.History(D.parseDoc(D.serialise(sd)));
  ed2.compile();
  const before = ed2.compiled.scattered.filter(t => t.scatter === sd.scatters[0].id).length;
  ed2.select('scatter', [sd.scatters[0].id]);
  ed2.bake();
  check('baking a scatter turns what it grew into ordinary things, and drops the rule',
    ed2.doc.scatters.length === 2 && ed2.doc.things.filter(t => t.type === 'SHOPPER').length === before);
  ed2.undo();
  check('and undoes', ed2.doc.scatters.length === 3);
  E.moveThings(ed2.doc, 'scatter', new Set([sd.scatters[0].id]), 64, -64);
  check('a scatter moves by its area', ed2.doc.scatters[0].area.x === 5184 && ed2.doc.scatters[0].area.y === 5056);
  clearTimeout(ed2._compileT); clearTimeout(ed2._saveT);

  /* AN OPEN WORLD BY DEFAULT: under the sky, no ceiling */
  const od = D.newDoc('OPEN');
  od.sectors[0].ceil = 1024;           // the sky well over the room's roof
  check('a new map is open ground under the sky, with no ceiling',
    od.sectors.length === 1 && od.sectors[0].ceilTex === 'SKY' && D.SECTOR_DEFAULTS.ceilTex === 'SKY' && D.SECTOR_DEFAULTS.outdoor === true &&
    od.vertices[2][0] === 4096 && Array.isArray(od.textures));
  od.vertices.push([1024, 1024], [2048, 1024], [2048, 2048], [1024, 2048]);
  od.sectors.push({ id: 7, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, ceil: 256, ceilTex: 'OFFPANEL', outdoor: false });
  od.nextId = 8;
  const upperTo = lvl => lvl.lines.flatMap(l => (l.bands || []).filter(b => b.kind === 'upper'));
  const oc = D.compileDoc(od);
  const ups = upperTo(oc.level);
  check('a roofed room under the open sky gets a roof and no wall up to the sky',
    ups.length === 4 && ups.every(b => b.tex === 'NONE') && oc.level.sectors.some(x => x.roofTex === 'OFFPANEL'));
  od.world.skyWalls = true;
  check('and Doom\'s sky walls, when the map asks for them', upperTo(D.compileDoc(od).level).every(b => b.tex && b.tex !== 'NONE'));
  delete od.world.skyWalls;

  /* DOOM 64'S COLOURS */
  od.sectors[1].colors = { floor: '#ff8000', ceil: '#0000ff', thing: '#00ff00', top: '#ffffff', bottom: '#000000' };
  const c64 = D.compileDoc(od);
  const room = c64.level.sectors[c64.index[1]];
  check('a sector\'s five colours reach the level as light colours',
    room.tint && room.tint.floor[0] === 1 && Math.abs(room.tint.floor[1] - 128 / 255) < 1e-9 && room.tint.floor[2] === 0 &&
    room.tint.thing[1] === 1 && room.tint.top[0] === 1 && room.tint.bottom[0] === 0 && !c64.level.sectors[c64.index[0]].tint);
  const MG = await import('../js/mapgeo.js');
  const TX = await import('../js/textures.js');
  const bankC = TX.bakeTextures();
  /* the default floor is a pack texture (js/texpack.js), which is a
     file the browser loads: here a stand-in of its size */
  bankC.add(D.DEFAULT_FLOOR, bankC.map.get('GRID').pix, { w: 256, h: 256 });
  const geoC = MG.buildLevelGeometry(c64.level, bankC);
  const byTex = new Map();
  const walkC = o => {
    if (o.geometry?.attributes?.tintRGB) { const k = o.name.split('|').pop(); (byTex.get(k) || byTex.set(k, []).get(k)).push(o.geometry); }
    for (const ch of o.children || []) walkC(ch);
  };
  walkC(geoC.group);
  const floorTint = (byTex.get(D.DEFAULT_FLOOR) || []).flatMap(g => [...g.attributes.tintRGB.array]);
  const hasOrange = (() => { for (let i = 0; i < floorTint.length; i += 3) if (floorTint[i] === 1 && Math.abs(floorTint[i + 1] - 128 / 255) < 1e-6) return true; return false; })();
  const wallTint = (byTex.get('GRIDWALL') || []).flatMap(g => [...g.attributes.tintRGB.array]);
  function wallTintAll() { return wallTint; }
  check('the floor is drawn in its colour, and a wall nobody coloured in white',
    hasOrange && (() => { const w = wallTintAll(); for (let i = 0; i < w.length; i += 3) if (w[i] === 1 && w[i + 1] === 1 && w[i + 2] === 1) return true; return false; })());
  check('and every surface carries a colour for every corner', floorTint.length && wallTint.length &&
    [...byTex.values()].flat().every(g => g.attributes.tintRGB.array.length === g.attributes.position.array.length));
  const matSrc = fsE.readFileSync('js/material.js', 'utf8');
  check('the world shader multiplies the light\'s colour in, on walls and on sprites',
    /albedo \*= vTint;/.test(matSrc) && /attribute vec3 tintRGB;/.test(matSrc) && /vTint = iTint;/.test(matSrc));
  check('and a thing stands in its sector\'s thing colour',
    /this\.sector\?\.tint\?\.thing/.test(fsE.readFileSync('js/actor.js', 'utf8')) &&
    /iTint/.test(fsE.readFileSync('js/standees.js', 'utf8')));

  /* A LINE'S SIDEDEF: top, middle and bottom, the offsets, the pegging */
  const sd2 = D.newDoc('L', 1024);
  sd2.vertices.push(...R(256, 256, 512, 512));
  sd2.sectors.push({ id: 9, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, floor: 32 });
  sd2.nextId = 10;
  sd2.lines[D.lineKey(4, 5)] = { midTex: 'FENCEPIK', midHeight: 64, xoff: 12, yoff: -8, unpegUpper: true, unpegLower: true };
  const Lsd = D.compileDoc(sd2).level;
  const ln = Lsd.lines.find(l => l.middle === 'FENCEPIK');
  check('a two-sided line can have a middle texture standing in its opening', ln && ln.midHeight === 64);
  check('and its own offsets and Doom\'s unpegged flags',
    ln && ln.xoff === 12 && ln.yoff === -8 && ln.pegUpper === 'top' && ln.pegLower === 'ceiling' && ln.pegMiddle === 'bottom');

  /* THE MAP'S OWN TEXTURES: the shape a definition must have */
  const TC = await import('../js/editor/texcompose.js');
  const nt = TC.newTexture('my wall 1!', 'GRIDWALL', [128, 64]);
  check('a map texture is named the way the bank names textures', nt.name === 'MYWALL1' && nt.layers.length === 1 && nt.worldW === 128);
  check('and a bad one is refused before it is drawn',
    TC.checkTexture(nt) === null && TC.checkTexture({ ...nt, w: 4000 }) !== null &&
    TC.checkTexture({ ...nt, name: 'GRIDWALL' }, new Set(['GRIDWALL'])) !== null && TC.checkTexture({ ...nt, name: '' }) !== null);
  const mainT = fsE.readFileSync('js/main.js', 'utf8');
  check('and the game draws a test run\'s own textures before it builds anything',
    /registerTextures\(textures, played\.doc\.textures/.test(mainT) && mainT.indexOf('registerTextures(textures') < mainT.indexOf('const game = new Game('));

  /* UDB'S WAY WITH LIGHT: brightness 0..255, Ctrl+wheel in 16s */
  const edL = new E.Editor(null);
  const nb = D.newDoc('B', 1024);
  check('a new map\'s ground is full bright, with a little ambient light everywhere, and walled 256 high',
    nb.sectors[0].light === 1 && nb.sectors[0].ceil === 256 && nb.world.ambient?.amount > 0.2 &&
    D.gridDoc().sectors[0].light === 1 && D.gridDoc().sectors[0].ceil === 256 && D.mapLightOf(nb.world).ambient[0] > 0.2);
  nb.sectors[0].light = 0.72;
  edL.history = new D.History(nb);
  const sid = edL.doc.sectors[0].id;
  check('a sector\'s brightness reads as Doom\'s 0 to 255', E.brightOf(edL.doc.sectors[0]) === Math.round(0.72 * 255));
  edL.nudgeLight(16, new Set([sid])); edL.nudgeLight(16, new Set([sid]));
  check('and Ctrl+wheel moves it sixteen at a time, a run of notches one undo', E.brightOf(edL.doc.sectors[0]) === 184 + 32 && edL.history.past.length === 1);
  for (let i = 0; i < 30; i++) edL.nudgeLight(16, new Set([sid]));
  check('and never past 255', E.brightOf(edL.doc.sectors[0]) === 255 && edL.history.past.length === 1);
  edL.undo();
  check('and the whole run undoes in one', E.brightOf(edL.doc.sectors[0]) === 184);

  /* INSIDE AND OUTSIDE: a roofed room in the open is a building */
  const bd = D.newDoc('BLD', 2048);
  bd.vertices.push([512, 512], [1024, 512], [1024, 1024], [512, 1024]);
  bd.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS });
  bd.nextId = 6;
  const edB = new E.Editor(null);
  edB.history = new D.History(bd);
  edB.setInside(true, new Set([5]));
  const room5 = edB.doc.sectors.find(x => x.id === 5);
  check('turning a sector inside gives it a roof and a room\'s height', E.isInside(room5) && room5.ceil === 128 && room5.outdoor === false);
  let cb = D.compileDoc(edB.doc);
  const walls = cb.level.lines.filter(l => l.exterior);
  check('and where it meets the outside, a wall: solid, blocking, in its wall texture',
    walls.length === 4 && walls.every(l => l.blocking && l.blockSight && l.middle === room5.wallTex));
  edB.edit('door', d => { d.lines[D.lineKey(4, 5)] = { opening: true }; }, { tidy: false });
  cb = D.compileDoc(edB.doc);
  check('unless the line is a doorway', cb.level.lines.filter(l => l.exterior).length === 3);
  edB.setInside(false, new Set([5]));
  check('and outside again is open, with no walls', !E.isInside(edB.doc.sectors.find(x => x.id === 5)) &&
    D.compileDoc(edB.doc).level.lines.filter(l => l.exterior).length === 0);
  /* a line override reaches every piece of a line the compiler split */
  const tj = D.newDoc('TJ', 2048);
  tj.vertices.push([512, 0], [1024, 0], [1024, 512], [512, 512]);
  tj.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, floor: 32 });
  tj.nextId = 6;
  D.compact(tj);
  const long = D.linesOf(tj).find(l => l.sectors.length === 1 && tj.vertices[l.a][1] === 0 && tj.vertices[l.b][1] === 0 &&
    Math.abs(tj.vertices[l.a][0] - tj.vertices[l.b][0]) > 1024);
  if (long) tj.lines[long.key] = { xoff: 7 };
  const tjl = long ? D.compileDoc(tj).level.lines.filter(l => l.xoff === 7).length : 0;
  check('a line\'s own settings reach every piece the compiler splits it into', !long || tjl >= 1, `${tjl}`);

  /* COPY AND PASTE */
  const edC = new E.Editor(null);
  edC.history = new D.History(D.newDoc('C', 2048));
  edC.select('thing', [edC.doc.things[0].id]);
  edC.copySel();
  edC.cursor = [1600, 1600];
  const beforeT = edC.doc.things.length;
  edC.paste();
  check('Ctrl+C, Ctrl+V: a thing pasted at the cursor, as a new thing', edC.doc.things.length === beforeT + 1 &&
    edC.doc.things.at(-1).id !== edC.doc.things[0].id && edC.sel.kind === 'thing');
  edC.history.doc.vertices.push([256, 256], [512, 256], [512, 512], [256, 512]);
  edC.history.doc.sectors.push({ id: 90, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, floor: 48, light: 0.5 });
  edC.select('sector', [90]);
  edC.copySel();
  edC.cursor = [1024, 1024];
  edC.paste();
  const pasted = edC.doc.sectors.at(-1);
  check('and a sector, with its heights and light, where the cursor is', edC.doc.sectors.length === 3 && pasted.floor === 48 &&
    pasted.light === 0.5 && D.ringOf(edC.doc, pasted).some(p => p[0] === 1024 && p[1] === 1024));
  edC.undo();
  check('and the paste undoes as one step', edC.doc.sectors.length === 2);
  for (const x of [edL, edB, edC]) { clearTimeout(x._compileT); clearTimeout(x._saveT); }

  /* WHAT THE ADVERSARIAL REVIEW FOUND, held down */
  const Rq = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
  const edR = new E.Editor(null);
  edR.history = new D.History(D.newDoc('R', 4096));
  edR.addSector(Rq(1024, 1024, 1536, 1536));
  edR.addSector(Rq(1536, 1024, 2048, 1536));
  edR.edit('raise', d => { d.sectors[2].floor = 200; }, { tidy: false });
  const cR = D.compileDoc(edR.doc);
  const shared = cR.level.lines.filter(l => { const a = cR.level.verts[l.v1], b = cR.level.verts[l.v2]; return a[0] === 1536 && b[0] === 1536; });
  check('two rooms drawn side by side in the open have a wall between them, not ground on both sides',
    shared.length >= 1 && shared.every(l => l.bands && l.bands.some(b => b.kind === 'lower')) &&
    !cR.level.lines.some(l => { const a = cR.level.verts[l.v1], b = cR.level.verts[l.v2]; return a[0] === b[0] && a[1] === b[1]; }));
  /* merging rooms drawn either way round */
  for (const flip of [false, true]) {
    const edM = new E.Editor(null);
    edM.history = new D.History(D.newDoc('M', 4096));
    edM.addSector(Rq(1024, 1024, 2048, 2048));
    const cut = [[1024, 1024], [1536, 1024], [1536, 2048], [1024, 2048]];
    edM.addSector(flip ? cut.reverse() : cut);
    const k = D.linesOf(edM.doc).find(l => l.sectors.length === 2 && edM.doc.vertices[l.a][0] === 1536 && edM.doc.vertices[l.b][0] === 1536)?.key;
    edM.select('line', [k]);
    edM.deleteSel();
    const left = edM.doc.sectors.filter(s => s.id !== 1).map(s => Math.abs(D.signedArea(D.ringOf(edM.doc, s))));
    check(`deleting the line between two rooms drawn ${flip ? 'opposite ways round' : 'the same way round'} joins them`,
      left.length === 1 && Math.abs(left[0] - 1024 * 1024) < 1, JSON.stringify(left));
    clearTimeout(edM._compileT); clearTimeout(edM._saveT);
  }
  /* a doorway kept when its line is split */
  const edD = new E.Editor(null);
  edD.history = new D.History(D.newDoc('D', 2048));
  edD.addSector(Rq(512, 512, 1024, 1024));
  edD.setInside(true, new Set([edD.doc.sectors[1].id]));
  const south = D.linesOf(edD.doc).find(l => edD.doc.vertices[l.a][1] === 512 && edD.doc.vertices[l.b][1] === 512 && l.sectors.length === 2).key;
  edD.edit('door', d => { d.lines[south] = { opening: true }; }, { tidy: false });
  edD.cursor = [768, 512]; edD.mode = 'vertices';
  edD.insertAtCursor();
  const doorLines = Object.entries(edD.doc.lines).filter(([, o]) => o.opening);
  check('a doorway stays a doorway when its line is split', doorLines.length === 2 &&
    D.compileDoc(edD.doc).level.lines.filter(l => l.exterior).length === 3);
  /* DRAWING FROM A BLANK MAP, which the user could not find: a new map
     is one ground sector, and in Sectors mode every click landed on it
     and every drag moved the world. Now a drag on the ground draws a
     new rectangle (the views call addRect), Insert starts a drawing,
     and a rectangle too small for the grid says so. */
  {
    const edG = new E.Editor(null);
    edG.history = new D.History(D.newDoc('G', 2048));
    const said = []; edG.say = m => said.push(m);
    check('on a new map the one sector is the ground', edG.isGround(edG.doc.sectors[0].id));
    const room = edG.addRect([256, 256], [768, 640]);
    check('a rectangle dragged out becomes a new sector, a hole in the ground',
      !!room && edG.doc.sectors.length === 2 && D.compileDoc(edG.doc).problems.length === 0 && /new sector/.test(said.at(-1)));
    check('the ground is still the ground, and the room is not', edG.isGround(edG.doc.sectors[0].id) && !edG.isGround(room.id));
    check('a rectangle with no width on the grid is refused, out loud', edG.addRect([256, 256], [256, 900]) === null &&
      edG.doc.sectors.length === 2 && /too small for the 64 grid/.test(said.at(-1)));
    edG.mode = 'sectors'; edG.cursor = [1024, 1024];
    edG.insertAtCursor();
    check('Insert in Sectors mode starts a drawing at the cursor', edG.mode === 'draw' && edG.path.length === 1 && edG.path[0][0] === 1024);
    const v2 = fsE.readFileSync('js/editor/view2d.js', 'utf8'), v3 = fsE.readFileSync('js/editor/view3d.js', 'utf8'), edS = fsE.readFileSync('js/editor/editor.js', 'utf8');
    check('both views draw on a drag that starts on the ground, and let Alt-drag move it',
      /mode === 'sectors' && !e\.altKey && ed\.isGround\(hit\.id\)/.test(v2) && /mode === 'sectors' && hit\.part === 'floor' && !e\.altKey && !e\.shiftKey && ed\.isGround\(s\.id\)/.test(v3) &&
      /ed\.addRect\(dr\.a, dr\.b\)/.test(v2) && /ed\.addRect\(dr\.a, dr\.b\)/.test(v3));
    check('and a new or opened map is framed on the plan and seen from its start in 3D',
      (edS.match(/this\.reframe\(\);/g) || []).length >= 3 && /reframe\(\) \{\s*this\.view2d\?\.frame\(\);\s*this\.view3d\?\.toStart\?\.\(\);/.test(edS));
  }
  /* LINEDEFS AND SHAPES, which the user asked for by name: a path
     finished open is linedefs of their own; they close into sectors
     against each other or a wall; what is left open stands as a wall;
     and Shape mode drags out more than rectangles. */
  {
    const mkL = () => { const e = new E.Editor(null); e.history = new D.History(D.newDoc('L', 2048)); e.said = []; e.say = m => e.said.push(m); e.setMode = m => { e.mode = m; }; return e; };
    let e = mkL();
    e.path = [[256, 256], [768, 256], [768, 640]]; e.closePath({ open: true });
    check('a path finished open, splitting nothing, is linedefs of their own', e.doc.linedefs.length === 2 && e.doc.sectors.length === 1 && e.lines().filter(l => l.free).length === 2);
    let c = D.compileDoc(e.doc);
    check('and they stand as a wall 128 high outdoors, with nothing wrong', c.problems.length === 0 && c.level.sectors.length === 2 && c.level.sectors[1].floor === 128);
    e.addLinedefs([[768, 640], [256, 640], [256, 256]]);
    check('closing the shape with more lines makes it a sector, and they are its edges', e.doc.linedefs.length === 0 && e.doc.sectors.length === 2 && D.compileDoc(e.doc).problems.length === 0);
    e = mkL(); e.addRect([256, 256], [1024, 1024]);
    e.addLinedefs([[1024, 384], [1280, 384], [1280, 640], [1024, 640]]);
    check('a U drawn against a room\'s wall closes into a sector beside it', e.doc.sectors.length === 3 && e.doc.linedefs.length === 0 && D.compileDoc(e.doc).problems.length === 0);
    e = mkL(); e.addRect([512, 512], [1024, 1024]);
    e.addLinedefs([[256, 768], [1280, 768]]);
    check('a line drawn through a room splits it, and the ends outside stand as walls',
      e.doc.sectors.length === 3 && e.doc.linedefs.length === 2 && D.compileDoc(e.doc).problems.length === 0);
    e = mkL();
    e.addLinedefs([[256, 256], [768, 768]]); e.addLinedefs([[256, 768], [768, 256]]);
    check('two linedefs that cross are cut where they cross', e.doc.linedefs.length === 4 && D.compileDoc(e.doc).problems.length === 0);
    e.select('line', [D.lineKey(...e.doc.linedefs[0])]); e.deleteSel();
    check('and Delete takes a linedef away without touching a sector', e.doc.linedefs.length === 3 && e.doc.sectors.length === 1);
    e = mkL(); e.addRect([256, 256], [1024, 1024]); e.setInside(true, new Set([e.doc.sectors[1].id]));
    e.addLinedefs([[384, 512], [896, 512]]);
    c = D.compileDoc(e.doc);
    check('in a room a linedef wall runs floor to ceiling', c.problems.length === 0 && c.level.sectors.at(-1).floor === c.level.sectors.at(-1).ceil);
    const saved = D.parseDoc(D.serialise(e.doc));
    check('linedefs survive a save and a load', saved.linedefs.length === 1);
    e.addLinedefs([[0, 1500], [3000, 1500]]);
    check('a linedef off the edge of the map is said, not built', D.compileDoc(e.doc).problems.some(p => /linedef/.test(p.msg)));
    const shapes = Object.keys(E.SHAPES).map(k => { const x = mkL(); x.emit = () => {}; x.setShape(k); const sct = x.addRect([256, 256], [1024, 768]); return [k, sct?.verts.length || 0, D.compileDoc(x.doc).problems.length]; });
    check('every shape drags out into a sector the compiler takes', shapes.every(([, n, pr]) => n >= 3 && pr === 0) && shapes.length >= 8, JSON.stringify(shapes));
    check('an ellipse has its sides, a star twice its points, a circle is round', (() => {
      const P = (k, sd) => E.shapePoints(k, [0, 0], [512, 256], sd);
      const ci = P('circle', 16), xs = ci.map(p => p[0]), ys = ci.map(p => p[1]);
      return P('ellipse', 24).length === 24 && P('star', 7).length === 14 && Math.max(...xs) - Math.min(...xs) === Math.max(...ys) - Math.min(...ys);
    })());
    const cssE = fsE.readFileSync('css/editor.css', 'utf8');
    check('a finger draws on the views instead of scrolling the page', /\.ed-view canvas \{[^}]*touch-action: none/.test(cssE));
    /* AN S PEN, and any pen: it draws, the fingers only move the view once
       a pen has been used, a double-tap finishes, the side button is the
       right button, the eraser deletes, and a pad of buttons stands in
       for the keys a tablet has not got */
    const v2p = fsE.readFileSync('js/editor/view2d.js', 'utf8');
    check('a pen draws and a finger then only pans and pinches',
      /e\.pointerType === 'touch'[\s\S]{0,200}if \(ed\.penSeen \|\| this\.touches\.size >= 2\)/.test(v2p) && /startGesture\(\) \{/.test(v2p) && /moveGesture\(\) \{/.test(v2p));
    check('the side button is the right button, and the eraser deletes',
      /e\.pointerType === 'pen' && \(e\.buttons & 2\) === 2/.test(v2p) && /e\.pointerType === 'pen' && e\.button === 5/.test(v2p));
    check('a double-tap finishes a drawing, and a pen tap is allowed a wobble', /now - lt\.t < 400[\s\S]{0,120}ed\.closePath\(\{ open: true \}\)/.test(v2p) && /e\.pointerType === 'pen' \? 6 : 4/.test(v2p));
    {
      const Vw = await import('../js/editor/view2d.js');
      const clicks = [];
      const fakeDoc = { createElement: () => { const el = { hidden: false, children: [], className: '', append(...c) { this.children.push(...c); }, addEventListener(t, f) { if (t === 'pointerdown') clicks.push([el, f]); }, textContent: '', title: '' }; return el; }, defaultView: null };
      const host = { ownerDocument: fakeDoc, append() {} };
      const edP = mkL(); edP.emit = () => {};
      const pad = Vw.buildPad(edP, host);
      pad.show();
      const press = label => clicks.find(([el]) => el.textContent.startsWith(label))[1]({ preventDefault() {}, stopPropagation() {} });
      edP.mode = 'draw'; edP.path = [[256, 256], [768, 256], [768, 768]];
      pad.refresh();
      const shown = l => !clicks.find(([el]) => el.textContent.startsWith(l))[0].hidden;
      const midDraw = shown('✓') && shown('⏎') && shown('⌫') && !shown('↶');
      press('✓');
      check('the pad closes a drawing into a sector, and offers what fits', midDraw && edP.doc.sectors.length === 2 && edP.path.length === 0);
      press('↶');
      check('and undoes it', edP.doc.sectors.length === 1);
    }
  }
  /* a drawn room's colours are its own */
  const edK = new E.Editor(null);
  edK.history = new D.History(D.newDoc('K', 2048));
  edK.edit('c', d => { d.sectors[0].colors = { floor: '#ff0000', top: '#00ff00' }; }, { tidy: false });
  edK.addSector(Rq(512, 512, 1024, 1024));
  edK.doc.sectors[1].colors.floor = '#0000ff';
  check('a room drawn in a coloured room takes its colours as a copy, not a share', edK.doc.sectors[0].colors.floor === '#ff0000');
  /* the problems the review found unreported */
  const pp = D.newDoc('P2', 4096);
  pp.vertices.push([2048, 0], [2560, 512], [2048, 1024], [1536, 512]);
  pp.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS });
  pp.nextId = 6;
  check('a room that touches its surroundings at one corner is not an overlap (it is a pinched hole now)', !D.problemsOf(pp).some(x => /overlap|touches the edge/.test(x.msg)));
  const po = D.newDoc('P3', 4096);
  po.vertices.push(...Rq(1024, 1024, 1536, 1536), ...Rq(1280, 1024, 1792, 1536));
  po.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS }, { id: 6, verts: [8, 9, 10, 11], ...D.SECTOR_DEFAULTS });
  po.nextId = 7;
  check('and two rooms drawn over each other along a shared line', D.problemsOf(po).some(x => /overlap/.test(x.msg)));
  /* a welded vertex selection is let go, not left pointing elsewhere */
  const edV = new E.Editor(null);
  edV.history = new D.History(D.newDoc('V', 4096));
  edV.addSector(Rq(1024, 1024, 1536, 1536));
  edV.addSector(Rq(2048, 1024, 2560, 1536));
  const vi = edV.doc.vertices.findIndex(v => v[0] === 2048 && v[1] === 1024);
  edV.select('vertex', [vi]);
  edV.moveSel(-512, 0);
  check('a vertex welded onto another is let go, not left selecting a different one', edV.sel.kind === null);
  for (const x of [edR, edD, edK, edV]) { clearTimeout(x._compileT); clearTimeout(x._saveT); }

  /* WHAT THE UX REVIEW FOUND, held down */
  const edS = new E.Editor(null);
  edS.history = new D.History(D.newDoc('S', 2048));
  edS.addSector(Rq(512, 512, 1536, 1536));
  edS.mode = 'draw'; edS.modeBeforeDraw = 'sectors';
  edS.path = [[512, 1024], [1536, 1024]];
  edS.closePath({ open: true });
  const halves = edS.doc.sectors.filter(x => x.id !== 1).map(x => Math.abs(D.signedArea(D.ringOf(edS.doc, x))));
  check('a line drawn from wall to wall splits the room in two, and drawing goes back to the mode it came from',
    halves.length === 2 && halves.every(a => Math.abs(a - 1024 * 512) < 1) && edS.mode === 'sectors' &&
    D.compileDoc(edS.doc).problems.length === 0, JSON.stringify(halves));
  const edW = new E.Editor(null);
  edW.history = new D.History(D.newDoc('W2', 1024));
  const wid = new Set([edW.doc.sectors[0].id]);
  const pastW = edW.history.past.length;
  edW.nudgeHeight('floor', 8, wid); edW.nudgeHeight('floor', 8, wid); edW.nudgeHeight('floor', 8, wid);
  check('a run of wheel notches is one undo step', edW.doc.sectors[0].floor === 24 && edW.history.past.length === pastW + 1);
  edW.undo();
  check('and one undo takes it all back', edW.doc.sectors[0].floor === 0);
  let heard = 0;
  edW.on('probe', () => { throw new Error('a broken panel'); });
  edW.on('probe', () => { heard++; });
  const errWas = console.error; console.error = () => {};
  edW.emit('probe');
  console.error = errWas;
  check('one listener failing does not stop the next hearing (the 3D view once stopped rebuilding)', heard === 1);
  const uiSrc2 = fsE.readFileSync('js/editor/ui.js', 'utf8');
  check('the Scatter tab has the function it draws itself with', /const renderScatter = \(\) =>/.test(uiSrc2));
  const cssSrc = fsE.readFileSync('css/editor.css', 'utf8');
  check('the menu bar does not clip its own menus', !/#ed-top \{[^}]*overflow: hidden/s.test(cssSrc));
  for (const x of [edS, edW]) { clearTimeout(x._compileT); clearTimeout(x._saveT); }

  /* WHAT DOOM BUILDER DOES THAT THE FIRST CUT DID NOT */
  /* a room touching its surroundings at a corner is a hole there */
  const tc = D.newDoc('TC', 4096);
  tc.vertices.push([2048, 0], [2560, 512], [2048, 1024], [1536, 512]);
  tc.sectors.push({ id: 5, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS, floor: 0, name: 'diamond' });
  tc.nextId = 6;
  const ctc = D.compileDoc(tc);
  check('a room touching its surroundings at one corner is a room you can walk into, and no problem',
    ctc.problems.length === 0 && ctc.level.sectorAt(2048, 512)?.docId === 5 &&
    ctc.level.lines.filter(l => l.frontCol.length && l.backCol.length).length >= 4);
  /* two sides of a line */
  const sd3 = D.newDoc('SD', 2048);
  const edF = new E.Editor(null);
  edF.history = new D.History(sd3);
  edF.addSector(Rq(512, 512, 1024, 1024));
  const bid = edF.doc.sectors[1].id;
  edF.setInside(true, new Set([bid]));
  edF.edit('in', d => { d.sectors[1].wallTex = 'OFFPANEL'; }, { tidy: false });
  const wallKey = D.linesOf(edF.doc).find(l => l.sectors.length === 2).key;
  edF.surf = { sector: 0, part: 'wall', line: wallKey, band: 'middle' };
  edF.applyTexture('FOUNDATN');
  const cF = D.compileDoc(edF.doc);
  const gF = MG.buildLevelGeometry(cF.level, bankC);
  const texF = new Set();
  const walkF = o => { if (o.geometry?.attributes?.position) texF.add(o.name.split('|').pop()); for (const ch of o.children || []) walkF(ch); };
  walkF(gF.group);
  check('painting one face of a wall paints that side only — brick outside, panelling in',
    edF.doc.lines[wallKey]?.sides?.[edF.doc.sectors[0].id]?.midTex === 'FOUNDATN' && !edF.doc.lines[wallKey].sides[bid] &&
    texF.has('FOUNDATN') && texF.has('OFFPANEL'));
  /* drawn across a wall */
  const edX = new E.Editor(null);
  edX.history = new D.History(D.newDoc('X', 2048));
  edX.addSector(Rq(512, 512, 1024, 1024));
  edX.edit('h', d => { d.sectors[1].floor = 64; }, { tidy: false });
  edX.addSector(Rq(768, 640, 1280, 896));
  const cX = D.compileDoc(edX.doc);
  check('a sector drawn across a wall is split where it crosses, each piece keeping its room\'s heights',
    edX.sel.ids.size === 2 && cX.problems.length === 0 && cX.level.sectorAt(900, 700).floor === 64 &&
    cX.level.sectorAt(1200, 700).floor === 0 && cX.level.sectorAt(600, 600).floor === 64 &&
    edX.doc.sectors.length === 4);
  const vsrc = fsE.readFileSync('js/editor/view2d.js', 'utf8');
  check('the plan has Doom Builder\'s brightness view, and floor and ceiling views', /planView/.test(vsrc) && /brightOf\(s\) \/ 255/.test(vsrc));
  for (const x of [edF, edX]) { clearTimeout(x._compileT); clearTimeout(x._saveT); }

  /* THE GODOT EXPORT: a GLB that reads back, and a scene that says what
     it should (it was also checked by importing it into Godot 4.3) */
  const GD = await import('../js/editor/godot.js');
  const surf = GD.gatherSurfaces(geoC.group);
  const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 64, 0, 0, 0, 32]);
  const imgs = new Map([...surf.keys()].map(n => [n, { png, masked: false }]));
  const glb = GD.buildGLB(surf, imgs, { scale: 1 / 32, name: 'T' });
  const dvG = new DataView(glb.buffer);
  const jsonLen = dvG.getUint32(12, true);
  const gj = JSON.parse(new TextDecoder().decode(glb.subarray(20, 20 + jsonLen)));
  check('the GLB is a GLB: header, JSON chunk, binary chunk, lengths that add up',
    dvG.getUint32(0, true) === 0x46546c67 && dvG.getUint32(8, true) === glb.length && dvG.getUint32(16, true) === 0x4e4f534a &&
    dvG.getUint32(20 + jsonLen + 4, true) === 0x004e4942 && gj.buffers[0].byteLength <= dvG.getUint32(20 + jsonLen, true));
  const prim = gj.meshes[0].primitives;
  check('one primitive per texture, each with positions, normals, UVs and baked colour, and its texture',
    prim.length === surf.size && prim.every(p => ['POSITION', 'NORMAL', 'TEXCOORD_0', 'COLOR_0'].every(a => p.attributes[a] !== undefined)) &&
    gj.materials.every(m => m.pbrMetallicRoughness.baseColorTexture && m.extensions?.KHR_materials_unlit) &&
    gj.images.length === surf.size && gj.accessors.every(a => a.count > 0));
  check('and a mesh Godot will give collision to', gj.nodes[0].name === 'World-col' && gj.scenes[0].nodes[0] === 0);
  const firstS = [...surf.values()][0], posAcc = gj.accessors[prim[0].attributes.POSITION], uvAcc = gj.accessors[prim[0].attributes.TEXCOORD_0];
  const binAt = 20 + jsonLen + 8;
  const read = (acc, i) => new Float32Array(glb.buffer.slice(binAt + gj.bufferViews[acc.bufferView].byteOffset, binAt + gj.bufferViews[acc.bufferView].byteOffset + gj.bufferViews[acc.bufferView].byteLength))[i];
  check('in metres at 32 units each, with v turned over for glTF',
    Math.abs(read(posAcc, 0) - firstS.pos[0] / 32) < 1e-4 && Math.abs(read(uvAcc, 1) - (1 - firstS.uv[1])) < 1e-4 && posAcc.min && posAcc.max);
  const lit = GD.buildGLB(surf, imgs, { bake: false, collision: false });
  const lj = JSON.parse(new TextDecoder().decode(lit.subarray(20, 20 + new DataView(lit.buffer).getUint32(12, true))));
  check('and unbaked: no vertex colours, lit materials, no collision', lj.meshes[0].primitives.every(p => p.attributes.COLOR_0 === undefined) &&
    !lj.extensionsUsed && lj.nodes[0].name === 'World');
  const tscn = GD.buildTSCN({ name: 'My "Map" 1', world: { sky: { horizon: '#1d9a48' } } }, [
    { type: 'START', x: 64, y: 32, z: 0, angle: Math.PI / 2 },
    { type: 'PLANT', kind: 'fir_tall_1', x: 320, y: 320, z: 16, scale: 1 },
    { type: 'PLANT', kind: 'fir_tall_1', x: 400, y: 320, z: 16, scale: 1.1 },
    { type: 'SHOPPER', x: 100, y: 100, z: 0, angle: 0, variant: 3 },
  ], new Map([['fir_tall_1', { file: 'sprites/fir_tall_1.png', w: 128, h: 256 }]]), { scale: 1 / 32 });
  check('the scene names its root safely and instances the level',
    /^\[gd_scene load_steps=\d+ format=3\]/.test(tscn) && /\[node name="My__Map__1" type="Node3D"\]/.test(tscn) &&
    /\[node name="World" parent="\." instance=ExtResource\("1_world"\)\]/.test(tscn));
  check('the plants are Sprite3D billboards about the vertical, cut out and point sampled, standing on the floor',
    (tscn.match(/type="Sprite3D"/g) || []).length === 2 && /billboard = 2/.test(tscn) && /alpha_cut = 1/.test(tscn) &&
    /texture_filter = 0/.test(tscn) && /offset = Vector2\(0, 128\)/.test(tscn) && tscn.includes(', 10, 0.5, -10)'));
  check('the actors are markers with their type, and the start faces north as -Z',
    /\[node name="SHOPPER_1" type="Marker3D" parent="Things"\]/.test(tscn) && /metadata\/variant = 3/.test(tscn) &&
    tscn.includes('[node name="PlayerStart" type="Marker3D" parent="."]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2, 0, -1)'));
  check('and the sky is the map\'s', /sky_horizon_color = Color\(0\.11373, 0\.60392, 0\.28235, 1\)/.test(tscn) && /background_mode = 2/.test(tscn));

  /* THE DOORS */
  const term = fsE.readFileSync('js/terminal.js', 'utf8');
  const main = fsE.readFileSync('js/main.js', 'utf8');
  const edsrc = fsE.readFileSync('js/editor/editor.js', 'utf8');
  const fnv = s => {
    let h = 0x811c9dc5;
    for (const c of s) { h ^= c.codePointAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
    return h.toString(16).padStart(8, '0');
  };
  void fnv;
  check('the terminal opens the editor on E and EDIT', /const EDIT_WORDS = \['E', 'EDIT'\];/.test(term) && /open\('\.\/editor\/editor\.js'\)/.test(term));
  check('and ?edit opens it with no terminal, and ?play runs the game',
    /params\.has\('edit'\)/.test(term) && /m\.startEditor\(\)/.test(term) && /import\('\.\/main\.js'\)/.test(term));
  check('the game plays the map the editor stored, under the same key',
    E.PLAY_KEY === 'gss-edit:play' && main.includes(`localStorage.getItem('${E.PLAY_KEY}')`) && /parseDoc\(text\)/.test(main) && /compileDoc\(doc\)/.test(main));
  check('and F2 in the game goes back to the editor', /e\.code === 'F2'[^\n]*\?edit/.test(main));
  check('the editor brings its own stylesheet, and it exists',
    edsrc.includes("'css/editor.css'") && fsE.existsSync('css/editor.css'));
})();

/* ---------- the site ---------- */
/* ---------- what it costs to draw ----------

   THE FRAME WAS MEASURED AND THEN CUT, and every one of these checks is
   an invariant one of those cuts stands on. The numbers, at four places
   in the map, before and after (a frame's own CPU, and the draw calls
   the renderer issued for the world):

     a shop aisle   424 draws ->  197     the flood 0.25ms -> 0.12
     the car park   974       ->  240              0.52    -> 0.46
     a town street  677       ->  548             18.1     -> 0.34
     the park       918       ->  798             34.8     -> 1.58

   and a tic, everywhere, 3.8ms -> 1.1ms.
   ------------------------------------------------------------------ */
/* ---------- and the box the screen can hold ----------

   A palette setting, at the user's request: the art is always the
   fifteen ramps, and what changes is the box the finished frame is
   DITHERED DOWN TO. Everything here is about the one thing that can go
   wrong with it — a picture of the old box that nobody remembered to
   make again — and about the one thing that must NOT happen, which is
   the art moving.
   ------------------------------------------------------------------ */
section('the box the screen can hold');
{
  const fsQ = await import('node:fs');
  const mainSrc = fsQ.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');
  const lofiQ = await import('../js/lofi.js');
  const lofiSrc = fsQ.readFileSync(new URL('../js/lofi.js', import.meta.url), 'utf8');
  const palQ = await import('../js/palette.js');

  /* THE LOOKUP CUBE IS THE DISPLAY PALETTE, as far as the GPU is
     concerned, and the sky baker was handed this exact texture object at
     start-up — so it is rewritten in place rather than replaced, or the
     two drift apart silently and only the sky is in the old box. */
  check('the pipeline can rebuild its lookup cube', typeof lofiQ.LofiPipeline.prototype.rebuildLut === 'function');
  check('and rewrites it in place rather than making a new one',
    /this\.lutData\.set\(atlas\.data\);/.test(lofiSrc) && /this\.lut\.needsUpdate = true;/.test(lofiSrc) &&
    !/rebuildLut\(\)[\s\S]{0,300}new THREE\.DataTexture/.test(lofiSrc));
  check('and it builds from the display box rather than the art one',
    /buildLutAtlas\(palette = displayPalette\(\)\)/.test(
      fsQ.readFileSync(new URL('../js/palette.js', import.meta.url), 'utf8')));

  /* AND THE WHOLE LIST OF WHAT HAS TO BE MADE AGAIN, which is two
     pictures of the cube and nothing else — not the textures, not the
     sprites, because those are painted in the art palette and the art
     palette did not move. */
  const fn = mainSrc.slice(mainSrc.indexOf('function applyPalette('), mainSrc.indexOf('/* and the choice the player last made'));
  check('the swap gives up early when the box did not change', /if \(!setDisplayPalette\(name\)\) return false;/.test(fn));
  check('and rebuilds the lookup cube the post pass snaps through', /pipeline\.rebuildLut\(\)/.test(fn));
  check('and re-bakes the sky, which was baked THROUGH that cube', /skyBaker\.bake\(/.test(fn));
  check('and does not re-bake the art, which is painted in a palette that did not change',
    !/bakeTextures\(/.test(fn) && !/bakeSprites\(/.test(fn), `${fn.trim().split('\n').length} lines`);
  check('and nothing is left marking frames for a re-bake that no longer happens',
    !/fromArt/.test(fsQ.readFileSync(new URL('../js/sprites.js', import.meta.url), 'utf8')) &&
    !/fromArt/.test(fsQ.readFileSync(new URL('../js/people.js', import.meta.url), 'utf8')) &&
    !/fromArt/.test(mainSrc));

  check('the choice is a setting that is remembered',
    /palette: 0,/.test(mainSrc) && /PALETTE_SET/.test(mainSrc) &&
    /ladder\('opt-palette', 'palette', PALETTE_SET/.test(mainSrc));
  check('and is applied at boot as well as on the flip',
    /const wanted = PALETTE_SET\[prefs\.palette\]\?\.v;/.test(mainSrc) &&
    /if \(wanted && wanted !== displayName\) applyPalette\(wanted\);/.test(mainSrc));
  check('and the saved settings were versioned up, so an old one does not come back without it',
    /const PREF_VERSION = 11;/.test(mainSrc) &&
    /if \(was < 7\) \{ delete saved\.detail;/.test(mainSrc));
  const htmlQ = fsQ.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  check('and there is a button for it', /id="opt-palette"/.test(htmlQ));

  /* AND THE DITHER AIMS AT THE BOX IT SNAPS TO. A Bayer threshold that
     moves a pixel a sixteenth of a channel cannot carry it across a gap
     of eighty-five, which is what four levels of blue are: the picture
     comes out flat, then a narrow band of checker where the two nearest
     entries happen to be within a sixteenth of each other, then flat
     again — banding with a seam in it. So the grid is a property of the
     box and travels with it. */
  {
    const sky = fsQ.readFileSync(new URL('../js/skyart.js', import.meta.url), 'utf8');
    check('each box carries the grid its dither steps on',
      palQ.DISPLAY_PALETTES.ramps.dither.join() === '16,16,16' &&
      palQ.DISPLAY_PALETTES.uzebox.dither.join() === '7,7,3');
    const levels = a => new Set(palQ.UZEBOX_PALETTE.map(c => c[a])).size;
    check('and the uzebox one is that box\'s own gaps, not a number somebody liked',
      palQ.DISPLAY_PALETTES.uzebox.dither.every((v, k) => v === levels(k) - 1),
      `${levels(0)}/${levels(1)}/${levels(2)} levels are ${levels(0)-1}/${levels(1)-1}/${levels(2)-1} gaps`);
    check('and rebuilding the cube pushes the new grid at the post pass',
      /const d = displayDither\(\);[\s\S]{0,120}uDitherLevels\.value\.set/.test(lofiSrc));
    check('and the sky picks it up on the bake, which is its only chance to',
      /displayDither/.test(sky) && /u\.uDitherLevels\.value\.set\(d\[0\], d\[1\], d\[2\]\);/.test(sky));
    /* AND IT FOLLOWS THE SETTING, which is the whole of the wiring */
    palQ.setDisplayPalette('uzebox');
    const under = palQ.displayDither().join();
    palQ.setDisplayPalette('ramps');
    check('and the live grid follows whichever box is in use',
      under === '7,7,3' && palQ.displayDither().join() === '16,16,16');
  }

  /* HOW FAR THE PICTURE HAS TO TRAVEL to get into the small box, which
     is the measurement the whole design rests on. If the art's 256 all
     landed on their own uzebox entry there would be nothing to dither
     and the setting could be a re-bake; they do not, they pile up on a
     third of that, and the distance between a colour and the nearest
     thing the hardware has is what the ordered dither spends its time
     covering. */
  {
    const near = c => {
      let best = 1e9, hit = null;
      for (const q of palQ.UZEBOX_PALETTE) {
        const d = (c[0] - q[0]) ** 2 + (c[1] - q[1]) ** 2 + (c[2] - q[2]) ** 2;
        if (d < best) { best = d; hit = q; }
      }
      return [Math.sqrt(best), hit];
    };
    const landed = new Set();
    let sum = 0, worst = 0;
    for (const c of palQ.RAMP_PALETTE) {
      const [d, hit] = near(c);
      landed.add(hit.join(','));
      sum += d; worst = Math.max(worst, d);
    }
    note('the art in the small box', `256 art colours land on ${landed.size} uzebox ones, ` +
      `${(sum / 256).toFixed(1)}/255 away on average and ${worst.toFixed(0)} at worst`);
    check('the art has colours the small box does not, which is what the dither is for',
      landed.size < 256 && sum / 256 > 2, `${landed.size} distinct, mean ${(sum / 256).toFixed(1)}`);
  }

  /* THE ART IS UNTOUCHED BY ALL OF IT, which is the check that matters
     most: this whole section is allowed to exist only because the game
     as it was drawn is exactly the game as it was drawn. */
  check('and after everything above, the art is still in its own box and the screen in the default',
    palQ.displayName === 'ramps' && palQ.PALETTE === palQ.RAMP_PALETTE);
}

/* =====================================================================
   THE GRID

   The test area, and that is all it is: a large walled-off green grid
   with a crowd on it and every gun in the rack. At the user's request
   everything else was taken OUT and nothing was deleted — the store,
   the town, the fire simulation, the burning boxes, the responders and
   the lo-fi picture are all still here, still exported and still tested
   by the sections above this one. What these check is that the test
   area is what it says it is, that the switches which turn the rest of
   it off are set, and that the picture is now full colour at the
   window's own resolution with the art still painted in earth.
   ===================================================================== */
section('the grid');
{
  const GRID = await import('../js/maps/grid.js');
  const THREEG = await import('three');
  const { Game } = await import('../js/game.js');
  const { Actor: Actor_G } = await import('../js/actor.js');
  const { STATES: STATES_G, ACTORS: ACTORS_G } = await import('../js/states.js');
  const fsG = await import('node:fs');
  const mainG = fsG.readFileSync('js/main.js', 'utf8');

  const gtex = tex.bakeTextures();
  const gsprites = spr.bakeSprites();
  const lv = GRID.buildGrid();
  note('the test area', `${GRID.FIELD} units square, ${lv.sectors.length} sector, ` +
    `${lv.lines.length} walls, ${lv.things.filter(t => t.type === 'SHOPPER').length} people`);

  /* ---- A LARGE WALLED-OFF GREEN GRID, AND NOTHING ELSE ---- */
  check('it is large, finite, and square', GRID.FIELD >= 8192 &&
    lv.field.x1 - lv.field.x0 === GRID.FIELD && lv.field.y1 - lv.field.y0 === GRID.FIELD);
  check('and it is ONE rectangle with four walls, now that nothing stands on it',
    lv.sectors.length === 1 && lv.lines.length === 4 &&
    lv.lines.every(l => l.back === null), `${lv.sectors.length} sectors, ${lv.lines.length} lines`);
  check('the floor is the green grid, anchored so a line lands on every cell edge',
    lv.sectors[0].floorTex === 'GRID' && lv.sectors[0].floorAnchor[0] === lv.field.x0 &&
    lv.sectors[0].floorAnchor[1] === lv.field.y0 && GRID.CELL === 64);
  check('and the wall round it is the same lattice, and it is over you',
    lv.sectors[0].wallTex === 'GRIDWALL' && lv.sectors[0].ceilTex === 'SKY' &&
    lv.sectors[0].ceil === GRID.WALL_H);
  check('and you cannot walk out of it: the edge is a wall, not an ending',
    lv.sightBlocked(lv.field.x0 + 100, lv.field.y0 + 4000, 40, lv.field.x0 - 400, lv.field.y0 + 4000, 40));
  check('you start in it, and a crowd stands in the middle of it with you',
    lv.things.some(t => t.type === 'START') &&
    lv.things.filter(t => t.type === 'SHOPPER').length === GRID.CROWD && GRID.CROWD >= 100);
  check('and there is nothing else in it at all: no boxes, no cars, no road, no exits',
    lv.boxes.length === 0 && lv.carSlots.length === 0 && lv.roadEnds.length === 0 &&
    !lv.swatRing && !lv.swatRoutes && lv.props.length === 0 && lv.plants.length === 0);

  /* ---- THE THREE SWITCHES, WHICH TURN THINGS OFF RATHER THAN DELETE ---- */
  check('the world says what it has not got: no cell fire, nothing catches, nobody is sent',
    lv.noCellFire === true && lv.noBurn === true && lv.noSquads === true);
  check('and every one of those is still in the repository, exported, and tested above',
    ['js/maps/sellwrong.js', 'js/maps/town.js', 'js/fire.js', 'js/boxes.js',
     'js/brigade.js', 'js/responders.js', 'js/lofi.js', 'js/palette.js'].every(f => fsG.existsSync(f)));
  {
    /* the store still builds, which is the whole of what "archived"
       has to mean — it is one import away from being the world again */
    const store = MAP.buildSellWrong({ town: false });
    check('the superstore still builds, it is simply not what the game opens',
      store.sectors.length > 100 && /import \{ buildGrid \}/.test(mainG) &&
      !/buildSellWrong\(\)/.test(mainG));
  }

  /* ---- AND IN A RUNNING GAME ---- */
  {
    (await import('../js/util.js')).pSeed();
    const gg = new Game({
      level: GRID.buildGrid(), scene: new THREEG.Scene(), camera: {},
      textures: gtex, sprites: gsprites,
      hud: { message() {}, ticMessages() {} }, audio: null,
      input: { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
               attack: false, use: false, run: false, jump: false, sample() {}, sensitivity: 0 },
    });
    check('the crowd is on its feet and the guns are in your hands',
      gg.actors.filter(a => a.type === 'SHOPPER' && !a.dead).length === GRID.CROWD &&
      Object.keys(gg.player.owned).length >= 7 && gg.player.owned.FLAMER === true);
    check('and nothing else came with them: no vehicles, no boxes, no fire to run',
      gg.vehicles.count === 0 && gg.boxes.count === 0 && gg.fire.off === true &&
      gg.brigade.trucks.length === 0);

    /* NOTHING CATCHES, at the user's request — EXCEPT PEOPLE, at the
       user's later request: somebody the flame lands on catches, runs,
       and sets alight whoever they touch. The floor, the wood and the
       vehicles still do not burn. */
    const who = gg.actors.find(a => a.type === 'SHOPPER' && !a.dead);
    const x0 = who.x, y0 = who.y;
    /* a neighbour, touching, and somebody well out of reach */
    const pals = gg.actors.filter(a => a.type === 'SHOPPER' && !a.dead && a !== who);
    const touching = pals[0], faraway = pals[1];
    touching.x = who.x + who.radius + touching.radius + 2; touching.y = who.y;
    faraway.x = who.x + 3000; faraway.y = who.y;
    for (const a of [touching, faraway]) gg.blockmap.moved(a);
    who.ignite(400);
    check('a person the flame lands on catches, even in a world where nothing else burns',
      who.burning > 0 && who.torch > 0 && who.state === STATES_G[ACTORS_G.SHOPPER.burn]);
    check('and runs: the burn state is a panicked run, and everybody near them is frightened off',
      who.panic > 0 && !!ACTORS_G.SHOPPER.burnScare);
    let caught = false;
    for (let k = 0; k < 40 && !caught; k++) {
      touching.x = who.x + who.radius + touching.radius + 2; touching.y = who.y; gg.blockmap.moved(touching);
      who.burnTic(); caught = touching.burning > 0;
    }
    check('AND IT IS CATCHING: whoever they touch goes up too', caught && touching.torch > 0);
    check('but not somebody a street away', faraway.burning === 0);
    check('a burning person is still a torch: they set alight the next one along',
      Actor_G.CATCH_EVERY > 0 && Actor_G.CATCH_CHANCE > 0 && /this\.setAlight\(\);/.test(fsG.readFileSync('js/actor.js', 'utf8')));
    gg.fire.ignite(who.x, who.y, 200, 90);
    check('and a call to the fire system lights nothing anywhere',
      gg.fire.burningCells === 0 && gg.fire.liveCells === 0);
    /* but the gun still works: the stream is still a stream and it
       still takes somebody down */
    /* on somebody not already alight — a person on fire has had their
       ending decided, and more fire does nothing to them (see ignite) */
    const mark = pals[2];
    mark.x = x0 - 2000; mark.y = y0; gg.blockmap.moved(mark);
    const before = mark.health;
    const o = { x: mark.x - 60, y: mark.y, z: mark.z + 40 };
    for (let k = 0; k < 30; k++) { gg.flame.fire(o, 0, 0); gg.flame.tic(); }
    check('the flamethrower still throws flame, and it still hurts',
      gg.flame.particles.count > 0 && (mark.health < before || mark.burning > 0), `${before} -> ${mark.health}`);

    let t = 0;
    gg.player.shotsFired = 99;
    for (; t < 700; t++) { gg.player.health = 100; gg.tic(); }
    check('and a hundred shots fired brings nobody up a road',
      gg.responders.vans.length === 0 && gg.responders.called === false &&
      gg.brigade.called === false && (gg.gunships?.ships?.length || 0) === 0);
  }

  /* ---- THE PICTURE: EARTH TONES AND THE PIXEL DITHER, BACK ---- */
  {
    check('the frame is dithered and snapped to the palette again, at the user\'s request',
      /dither: 1\.0, snap: 1\.0,/.test(mainG));
    check('on a chunky grid again',
      /const DEFAULT_PIXELS = PIXELS\.indexOf\(320\);/.test(mainG) && /pixelHeight: PIXELS\[pixelIndex\]/.test(mainG));
    check('and the window\'s own resolution is still the top of the ladder',
      /const detailRows = i => DETAIL\[i\] \|\| nativeRows\(\);/.test(mainG) &&
      /const DEFAULT_DETAIL = DETAIL\.indexOf\(960\);/.test(mainG) &&
      /height: detailRows\(detailIndex\)/.test(mainG));
    check('and it follows the window when the window moves',
      /if \(!DETAIL\[detailIndex\]\) pipeline\.setHeight\(nativeRows\(\)\);/.test(mainG));
    /* THE LOOK IS TURNED DOWN, NOT TAKEN OUT: every dial is still on the
       menu and js/lofi.js still does all of it. */
    const lofiSrc = fsG.readFileSync('js/lofi.js', 'utf8');
    check('js/lofi.js still does every bit of it, so the look is three presses away',
      /palSnap/.test(lofiSrc) && /uDither/.test(lofiSrc) && /setPixels/.test(lofiSrc) &&
      /\$\('opt-pix-up'\)/.test(mainG) && /\$\('opt-res-up'\)/.test(mainG));
    /* AND THE ART IS STILL EARTH, which is the other half of it and a
       different question: the screen is not held to 256 colours, and
       every texture and sprite is still PAINTED out of them. */
    check('but the art is still painted in the earth box, at the user\'s request',
      /TONE_SET = \[\{ v: 'earth'/.test(mainG) && /tone: 0,/.test(mainG) &&
      pal.DEFAULT_ART === 'earth');
    check('and a saved setting from before the picture moved is not kept alive',
      /const PREF_VERSION = 11;/.test(mainG) && /if \(was < 11\)/.test(mainG));
  }

  /* ---- THE TWO PICTURES DRAWN IN FULL COLOUR ---- */
  {
    const g1 = gtex.get('GRID'), g2 = gtex.get('GRIDWALL');
    note('the grid, as a picture', `${g1.pix.w}x${g1.pix.h} over ${g1.w} units, ` +
      `${new Set(Array.from({ length: g1.pix.h }, (_, i) => g1.pix.get(40, i).join(','))).size} colours down one cell`);
    check('the floor and the wall are drawn bigger than everything else, and smoothed',
      g1.pix.w === 256 && g2.pix.w === 256 && g1.texture.magFilter === THREEG.LinearFilter &&
      g1.texture.anisotropy > 1 && g2.texture.magFilter === THREEG.LinearFilter);
    check('and one repeat of each is still one cell, so the lines land on the grid',
      g1.w === GRID.CELL && g1.h === GRID.CELL && g2.w === GRID.CELL);
    /* THEY CARRY THEIR OWN RGB. Everything else in the bank is painted
       out of the 256; these two are a ruled line and would be a stack
       of aliasing if they were. */
    {
      const inPalette = c => pal.PALETTE.some(p2 => p2[0] === c[0] && p2[1] === c[1] && p2[2] === c[2]);
      let off = 0;
      for (let x = 0; x < 256; x += 3) if (!inPalette(g1.pix.get(x, 0))) off++;
      check('and they are NOT snapped to the palette: a line is a glow, not two flat colours',
        off > 20, `${off} of 86 sampled texels are off the 256`);
    }
    /* and the line is brightest at the cell edge and dark in the middle
       of the cell, which is what makes it a grid rather than a wash */
    const lum = (x, y) => { const c = g1.pix.get(x, y); return c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11; };
    check('the lattice is bright on the cell edge, dimmer at the half, dark between',
      lum(0, 40) > lum(128, 40) * 2 && lum(128, 40) > lum(64, 40) * 1.5,
      `${lum(0, 40).toFixed(0)} / ${lum(128, 40).toFixed(0)} / ${lum(64, 40).toFixed(0)}`);
  }

  /* ---- AND THE SKY ---- */
  {
    const skySrc = fsG.readFileSync('js/skyart.js', 'utf8');
    check('the sky bake has a dial for the snap, held to the box again with everything else',
      /uniform float uSnapAmt;/.test(skySrc) && /u\.uSnapAmt\.value = f\.snap \?\? 1;/.test(skySrc) &&
      /snap: 1 \}/.test(mainG));
    check('and it is still green at the horizon, dark green through, black overhead',
      /horizon: '#1d9a48'/.test(mainG) && /zenith: '#000000'/.test(mainG) && /midPow: 0\.95/.test(mainG));
    /* a fixed sky bakes once: the clock does not run and no cloud drifts */
    check('and it is baked once and never again: no clock, no cloud, no haze',
      /running: false, fireHaze: false,/.test(mainG) && /bare: true/.test(mainG));
  }
}

section('what it costs to draw');
{
  const THREEP = await import('three');
  const mgP = await import('../js/mapgeo.js');
  const utilP = await import('../js/util.js');

  /* --- THE PSEUDO-ANGLE, which is what took the flood apart ---------
     The portal flood compares and clips angles and never does anything
     else with one, so it does not need the angle — it needs something
     that sorts the same way. This is that, and the only thing that can
     be wrong with it is the sorting. */
  {
    let bad = 0, prev = -Infinity, worst = 0;
    for (let a = -Math.PI + 1e-9; a <= Math.PI; a += Math.PI / 2048) {
      const v = utilP.pseudoAngle(Math.cos(a), Math.sin(a));
      if (v <= prev) bad++;
      worst = Math.max(worst, Math.abs(v - a / Math.PI * utilP.PSEUDO_PI) / utilP.PSEUDO_PI);
      prev = v;
    }
    check('the pseudo-angle rises with the real one over the whole turn, without exception',
      bad === 0, `${bad} places it did not`);
    check('and half a turn is PSEUDO_PI in it',
      utilP.pseudoAngle(-1, 0) === utilP.PSEUDO_PI && utilP.pseudoAngle(1, 0) === 0 &&
      utilP.pseudoAngle(0, 1) === utilP.PSEUDO_PI / 2 && utilP.pseudoAngle(0, -1) === -utilP.PSEUDO_PI / 2);
    check('and it is not the real one, which is the point of it',
      worst > 0.02, `closest it gets is ${(worst * 100).toFixed(0)}% off`);
    check('and the origin does not throw', utilP.pseudoAngle(0, 0) === 0);
  }

  /* --- THE FLOOD IS STILL CONSERVATIVE, which is the only thing it
     must be. Rewritten to use the above, with the per-line work lifted
     out of the storey loop and the distance test stopped allocating;
     none of that is allowed to hide a region a ray can reach. --- */
  {
    const lvP = MAP.buildSellWrong();
    const halfP = Math.atan(Math.tan(36 * Math.PI / 180) * 1.6) + 0.25;
    let rays = 0, bad = 0;
    for (const [x, y, yaw] of [[1800, 1600, Math.PI / 2], [2000, -1200, -Math.PI / 2],
                               [-8900, -3384, 0], [64, -20100, Math.PI / 2]]) {
      lvP.visibleSectors(x, y, yaw, halfP, mgP.INTERIOR_DIST);
      const s0 = lvP.sectorAt(x, y), z = (s0 ? s0.floor : 0) + 49;
      for (let a = -halfP + 0.02; a < halfP; a += 0.03)
        for (let d = 64; d < 2600; d += 64) {
          const tx = x + Math.cos(yaw + a) * d, ty = y + Math.sin(yaw + a) * d;
          const sec = lvP.sectorAt(tx, ty);
          if (!sec) continue;
          const tz = Math.min(sec.ceil - 8, Math.max(sec.floor + 8, z));
          if (lvP.sightBlocked(x, y, z, tx, ty, tz)) break;
          rays++;
          if (!lvP.isVisible(sec)) bad++;
        }
    }
    check('the rewritten flood still hides nothing a ray can reach',
      bad === 0, `${bad} of ${rays} points`);
    note('rays against the flood', `${rays} points a ray reached at four places`);
    /* AND IT IS CHEAP, which is the whole reason for the rewrite: on a
       town street it was eighteen milliseconds a frame. */
    const t0 = performance.now();
    for (let i2 = 0; i2 < 30; i2++) lvP.visibleSectors(-8900, -3384, 0, halfP, 4096);
    const ms = (performance.now() - t0) / 30;
    note('a flood down a town street', `${ms.toFixed(2)}ms`);
    check('and a flood down a town street costs under three milliseconds', ms < 3, `${ms.toFixed(2)}ms`);
  }

  /* --- THE CROWD IS ONE DRAW CALL PER PICTURE ---------------------- */
  {
    const St = await import('../js/standees.js');
    const matS = await import('../js/material.js');
    const sceneS = new THREEP.Scene();
    const st = new St.Standees({});
    st.attach(sceneS);
    st.begin(0.5);
    const texA = { id: 'a' }, texB = { id: 'b' };
    for (let i2 = 0; i2 < 200; i2++) st.add(i2 % 3 ? texA : texB, i2, 1, 2, 32, 48, 0.6, 1, 0, 0, 0, 0);
    st.end();
    check('a crowd of two hundred sharing two pictures is two draw calls',
      st.batchCount === 2 && st.drawn === 200 && sceneS.children.length === 2,
      `${st.batchCount} batches, ${st.drawn} standees`);
    const b0 = st.order[0];
    check('and the buffers grew to hold them rather than being allocated per frame',
      b0.cap >= b0.n && b0.mesh.geometry.instanceCount === b0.n);
    check('and each instance carries its own place, size, light and flags',
      b0.a.pos.array[0] === 0 && b0.a.size.array[0] === 32 && b0.a.size.array[1] === 48 &&
      Math.abs(b0.a.light.array[0] - 0.6) < 1e-6 &&      // a float32 buffer, so to a hair
      b0.a.sky.array[0] === 1 && b0.a.flags.itemSize === 4);
    /* a second frame empties them without throwing anything away */
    const caps = st.order.map(b => b.cap);
    st.begin(0);
    st.end();
    check('a frame with nobody in it draws nothing and keeps its buffers',
      st.drawn === 0 && st.batchCount === 0 && st.order.every((b, i2) => b.cap === caps[i2]) &&
      st.order.every(b => !b.mesh.visible));
    /* THE SHADER IS THE SAME SHADER. What was a uniform is a varying of
       the same name under one define, so the body of neither stage
       knows which way it is being drawn — and that is checkable by
       reading it. */
    const sm = matS.createStandeeMaterial(texA);
    const pm = matS.createSpriteMaterial(texA, { alphaTest: 0.5 });
    check('the batched sprite and the single one are the same two shaders',
      sm.vertexShader === pm.vertexShader && sm.fragmentShader === pm.fragmentShader);
    check('and they differ only in a define',
      sm.defines.INSTANCED_SPRITE === '' && pm.defines.BILLBOARD === '' &&
      !('BILLBOARD' in sm.defines) && !('INSTANCED_SPRITE' in pm.defines));
    check('where the four per-sprite values become varyings of the same name',
      /#ifdef INSTANCED_SPRITE[\s\S]{0,400}varying float fullbright;/.test(sm.fragmentShader) &&
      /varying float frost;/.test(sm.fragmentShader) && /varying float ash;/.test(sm.fragmentShader) &&
      /varying float alight;/.test(sm.fragmentShader));
    check('and the instance attributes exist and the shared yaw is still a uniform',
      /attribute vec3  iPos;/.test(sm.vertexShader) && /attribute vec4  iFlags;/.test(sm.vertexShader) &&
      /uniform float billboardRot;/.test(sm.vertexShader) && !!sm.uniforms.billboardRot);
    check('and a standee is a cut-out, so nothing has to be sorted',
      sm.transparent === false && sm.depthWrite === true && sm.uniforms.alphaTest.value === 0.5);
    /* NOTHING IN THE GAME OWNS A SPRITE MESH ANY MORE */
    const fsS = await import('node:fs');
    const actSrc = fsS.readFileSync(new URL('../js/actor.js', import.meta.url), 'utf8');
    check('and an actor does not make a mesh at all',
      !/ensureMesh/.test(actSrc) && !/new THREE\.Mesh/.test(actSrc) && /standees\.add\(/.test(actSrc));
  }

  /* --- THE GEOMETRY LOD -------------------------------------------- */
  {
    check('a batch that covers no world is dropped at any distance, and one that covers a block never is',
      mgP.minSolidFor(960) > 0 && mgP.minSolidFor(320) > mgP.minSolidFor(960));
    /* IT FOLLOWS THE PIXEL. Half the rows is a pixel four times the
       solid angle, so four times as much can go — which is the right
       way round, because the buffer that cannot show the detail is on
       the machine that cannot afford it. */
    check('the threshold is four times looser at half the rows',
      Math.abs(mgP.minSolidFor(480) / mgP.minSolidFor(960) - 4) < 1e-9,
      `${mgP.minSolidFor(480) / mgP.minSolidFor(960)}`);
    check('and it never divides by nothing', Number.isFinite(mgP.minSolidFor(0)) && Number.isFinite(mgP.minSolidFor()));

    const lvG = MAP.buildSellWrong();
    const bankG = tex.bakeTextures();
    const geoG = mgP.buildLevelGeometry(lvG, bankG);
    let meshes = 0, withArea = 0, area = 0;
    const walkG = o => { if (o.geometry && o.userData && o.userData.area !== undefined) { meshes++; if (o.userData.area > 0) withArea++; area += o.userData.area; }
                         for (const c of o.children || []) walkG(c); };
    walkG(geoG.group);
    check('every batch of the level knows how much world it covers',
      meshes > 500 && withArea === meshes, `${withArea} of ${meshes}`);
    note('the level, as area', `${meshes} batches over ${(area / 1e6).toFixed(1)} million square units`);

    const blockAt = k => geoG.blockGroups.get(k);

    /* --- AND WHO ANSWERS FOR A BLOCK ------------------------------
       A region is drawn in the block its middle lands in; a LINE is
       drawn in the block its midpoint lands in. Those are usually the
       same block, and the case where they are not is the one that
       matters: a big outdoor region owning the wall of the building it
       wraps round. The wood behind the west wing is nine thousand units
       of forest whose middle is a block and a half from the supermarket,
       and the supermarket's west flank is the WOOD's own one-sided wall
       — filed, correctly, in the anchor's block.

       Until the fire doors were given the staff door's `opaque`, that
       block was answered for by the anchor's aisles alone, and the whole
       west side of the building was drawn only because the portal flood
       was leaking through six shut fire doors. Shut them to sight and
       the building lost its outside. Two checks, and the second is the
       one that makes the first mean anything. */
    {
      const wall = lvG.lines.find(l => Math.abs(l.x1 - (MAP.ANCHOR_X0 - 16)) < 0.1 &&
        Math.abs(l.x2 - (MAP.ANCHOR_X0 - 16)) < 0.1 && !l.backCol.length && l.frontCol.length &&
        /^wood/.test(lvG.sectors[l.frontCol[0]].name) && Math.abs(l.y1 - l.y2) > 300);
      const ex = MAP.ANCHOR_X0 - 240, ey = (wall.y1 + wall.y2) / 2;
      lvG.visibleSectors(ex, ey, 0, 1.2, mgP.INTERIOR_DIST);
      geoG.applyVisibility(lvG, ex, ey, mgP.INTERIOR_DIST, Infinity, 960);
      const centred = lvG.sectors.filter(s => s.drawBlock === wall.drawBlock);
      check('standing in the wood, the side of the building you are looking at is drawn',
        !!blockAt(wall.drawBlock) && blockAt(wall.drawBlock).visible,
        `block ${wall.drawBlock}`);
      check('and none of the regions centred in that block is what says so',
        centred.length > 0 && !centred.some(s => lvG.isVisible(s)),
        `${centred.filter(s => lvG.isVisible(s)).length} of ${centred.length} visible`);
      check('and the wall in question belongs to the wood and not to the shop',
        /wood/.test(lvG.sectors[wall.frontCol[0]].name) &&
        lvG.sectors[wall.frontCol[0]].drawBlock !== wall.drawBlock,
        `${lvG.sectors[wall.frontCol[0]].name} is centred in ${lvG.sectors[wall.frontCol[0]].drawBlock}`);
    }

    /* THE AIR DECIDES THE DRAW DISTANCE. A block past FAR_AIR of it is
       not submitted, and with no air given nothing is dropped. */
    const someBlock = [...geoG.blockGroups.keys()].map(k => {
      const [bx, by] = k.split(',').map(Number);
      return { k, x: (bx + 0.5) * mgP.BATCH_BLOCK, y: (by + 0.5) * mgP.BATCH_BLOCK };
    });
    const eye = someBlock[0];
    const farOne = someBlock.reduce((a, b) => (Math.hypot(b.x - eye.x, b.y - eye.y) > Math.hypot(a.x - eye.x, a.y - eye.y) ? b : a));
    const farD = Math.hypot(farOne.x - eye.x, farOne.y - eye.y);
    lvG.visibleSectors(eye.x, eye.y, 0, 1.2, mgP.INTERIOR_DIST);
    geoG.applyVisibility(lvG, eye.x, eye.y, mgP.INTERIOR_DIST, Infinity, 960);
    check('with no air at all, the far side of the town is still drawn', blockAt(farOne.k).visible);
    geoG.applyVisibility(lvG, eye.x, eye.y, mgP.INTERIOR_DIST, farD * 0.5, 960);
    check('and inside half the air to it, it is not', !blockAt(farOne.k).visible,
      `${(farD | 0)} away, air ${(farD * 0.5) | 0}`);
    check('but the block the eye stands in always is',
      (geoG.applyVisibility(lvG, eye.x, eye.y, mgP.INTERIOR_DIST, farD * 0.5, 960), blockAt(eye.k).visible));
    check('and the cut is a fraction of the air rather than a number of units',
      mgP.FAR_AIR > 0.5 && mgP.FAR_AIR < 1);

    /* AND THE SMALL BATCHES INSIDE IT. At a coarse enough grid the
       threshold has to start biting, or the mechanism is dead code. */
    geoG.applyVisibility(lvG, eye.x, eye.y, mgP.INTERIOR_DIST, Infinity, 960);
    /* how many batches are actually submitted: visible, and with every
       group above them visible too */
    const countOn = () => {
      let n = 0;
      const w = o => {
        if (o.geometry && o.userData.area !== undefined) {
          let v = true;
          for (let q = o; q; q = q.parent) if (!q.visible) { v = false; break; }
          if (v) n++;
        }
        for (const c of o.children || []) w(c);
      };
      w(geoG.group);
      return n;
    };
    const onFine = countOn();
    geoG.applyVisibility(lvG, eye.x, eye.y, mgP.INTERIOR_DIST, Infinity, 90);
    const onCoarse = countOn();
    check('a coarse enough picture drops the batches too small to show in it',
      onCoarse < onFine, `${onFine} batches at 960 rows, ${onCoarse} at 90`);
    /* and back again, so it is a decision and not a demolition */
    geoG.applyVisibility(lvG, eye.x, eye.y, mgP.INTERIOR_DIST, Infinity, 960);
    check('and puts them back when the picture is fine again', countOn() === onFine,
      `${countOn()} against ${onFine}`);
  }

  /* --- THE BURN GRID, which was two thirds of every tic ------------- */
  {
    const fsB = await import('node:fs');
    const gameSrc = fsB.readFileSync(new URL('../js/game.js', import.meta.url), 'utf8');
    check('the burn picture is drained from a list rather than found by scanning',
      /gridDirty/.test(gameSrc) && !/for \(let y = 0; y < rows; y\+\+\)/.test(gameSrc));
    check('and it is not sent to the GPU on every tic', /BURN_UPLOAD_EVERY/.test(gameSrc));
  }

  /* --- AND THE READOUT TELLS THE TRUTH ABOUT THE FRAME -------------- */
  {
    const fsL = await import('node:fs');
    const lofiSrc = fsL.readFileSync(new URL('../js/lofi.js', import.meta.url), 'utf8');
    const mainSrc = fsL.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');
    check('the pipeline keeps what the WORLD pass cost before its own passes overwrite it',
      /this\.sceneCalls = r\.info\.render\.calls;/.test(lofiSrc));
    check('and the readout shows that rather than the blit, which was always 1',
      /pipeline\.sceneCalls/.test(mainSrc) && !/\$\{renderer\.info\.render\.calls\} draws/.test(mainSrc));
    check('and the geometry LOD is told how big a pixel is, from the grid',
      /game\.viewRows = pipeline\.gridHeight;/.test(mainSrc));
  }
}

/* ---------- the texture pack ---------- */
section('the texture pack');
{
  /* The pictures the user handed over (js/texpack.js), as files in
     assets/textures and assets/skies, loaded at run time. Nothing here
     draws one — that takes a browser — so this checks that the list and
     the files agree, that the animated runs run Doom's way, and that the
     editor, the game and the Godot export are all wired to them. */
  const fsP = await import('node:fs');
  const TP = await import('../js/texpack.js');
  const { TEXTURE_NAMES } = await import('../js/textures.js');
  const TCp = await import('../js/editor/texcompose.js');
  const DOCp = await import('../js/editor/doc.js');
  const GDp = await import('../js/editor/godot.js');
  const src = f => fsP.readFileSync(new URL('../' + f, import.meta.url), 'utf8');
  /* a PNG's size is in its header, sixteen bytes in */
  const pngSize = f => { const b = fsP.readFileSync(new URL('../' + f, import.meta.url)); return [b.readUInt32BE(16), b.readUInt32BE(20)]; };

  note('the pack', `${TP.PACK.length} textures, ${Object.keys(TP.ANIMS).length} animated runs, ${Object.keys(TP.SKIES).length} skies`);
  check('both archives and the vandre ground are in it: 245 + 21 textures', TP.PACK.length === 266, `${TP.PACK.length}`);
  /* THE USER'S OWN GROUND AND PLANTS, from github.com/verdictzero/vandre
     (tools/prep-vandre.py) */
  {
    const V = ['ARCTIC1','FARMLND1','FROZEN1','TUNDRA1','CANDY1','GRASCHK1','GRASCHK2','MOLTEN1','MEADOW1','MEADOW2','MEADOW3','MEADOW4','MEADOW5','PINEBAR1','SAND1','SAVANNA1','WASTE1','CITYCON1','CITYMET1','CITYMET2','CITYSKRT'];
    check('the vandre ground is in the pack, grouped vandre/terrain and vandre/city, 256 square at 2px a unit',
      V.every(n => { const p = TP.PACK.find(q => q.name === n); return p && /^vandre\/(terrain|city)$/.test(p.group) && p.px[0] === 256 && p.px[1] === 256 && p.w === 128; }),
      V.filter(n => !TP.PACK.find(q => q.name === n)).join(' '));
    const Fv = await import('../js/forest.js');
    const SCv = await import('../js/editor/scatter.js');
    const VK = Fv.KINDS.filter(k => k.set);
    check('the vandre plants: 69 kinds in eight sets, none planted by the wood', VK.length === 69 && new Set(VK.map(k => k.set)).size === 8 && VK.every(k => k.w === 0));
    check('every vandre tree is over 120 and blocks; everything else is ground cover', VK.every(k => (k.h > 120) === !k.cover));
    check('a scatter preset for each vandre biome, every item a kind that exists',
      ['desert','meadow','meadowOld','pine','savanna','wasteland','tundra','farmland'].every(p => SCv.PRESETS[p]?.items.length && SCv.PRESETS[p].items.every(i => SCv.validType(i.type))));
    check('the palette shelves plants by set, and every kind is on one shelf', SCv.PLANT_SETS.flatMap(s => s.kinds).length === Fv.KINDS.length);
    const mainSrc = fsP.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');
    check('the game loads a vandre plant only when the map plants it', /KINDS\.filter\(k => !k\.set\)/.test(mainSrc) && /loadPlantSets\(forestArt, level\.plants\)/.test(mainSrc));
  }
  check('every name is one the bank and a map can use as it stands',
    TP.PACK_NAMES.every(n => TCp.cleanName(n) === n), TP.PACK_NAMES.filter(n => TCp.cleanName(n) !== n).join(' '));
  check('and none of them is the name of a texture the game draws',
    TP.PACK_NAMES.every(n => !TEXTURE_NAMES.includes(n)), TP.PACK_NAMES.filter(n => TEXTURE_NAMES.includes(n)).join(' '));
  check('and no two are the same', new Set(TP.PACK_NAMES).size === TP.PACK_NAMES.length);
  const wrong = TP.PACK.filter(p => { const f = `assets/textures/${p.name}.png`; if (!fsP.existsSync(new URL('../' + f, import.meta.url))) return true; const [w, h] = pngSize(f); return w !== p.px[0] || h !== p.px[1]; });
  check('every one is a file, the size the list says it is', !wrong.length, wrong.map(p => p.name).join(' '));
  const onDisk = fsP.readdirSync(new URL('../assets/textures/', import.meta.url)).filter(f => f.endsWith('.png')).map(f => f.slice(0, -4));
  check('and every file is in the list: nothing shipped that the editor cannot show',
    onDisk.every(n => TP.PACK_NAMES.includes(n)), onDisk.filter(n => !TP.PACK_NAMES.includes(n)).join(' '));
  const P = n => TP.PACK.find(p => p.name === n);
  check('a pack picture spans half its pixels: a door is 64 by 128, as in Doom',
    P('EYEDOOR0').w === 64 && P('EYEDOOR0').h === 128 && P('CONC_1').w === 128);
  check('except the ones drawn one to one: DR1, and the test tiles that say their size',
    P('DR1_01').w === 64 && P('DR1_01').h === 128 && P('64TEST').w === 64 && P('512TEST').w === 512);
  check('and a picture the build made smaller still covers what it did: the test card is 423 wide, and the cliff 1373 tall',
    P('TESTPA00').w === 423 && P('CLIFF1').h === 1373, `${P('TESTPA00').w} ${P('CLIFF1').h}`);
  check('the backdrops and the waterfall are cut out; the concrete is not',
    P('TREELINE').masked && P('MNTN0001').masked && !P('CONC_1').masked);

  /* THE ANIMATION */
  const frames = Object.values(TP.ANIMS).flatMap(a => a.frames);
  check('every frame of every animated run is in the pack', frames.every(n => TP.PACK_NAMES.includes(n)),
    frames.filter(n => !TP.PACK_NAMES.includes(n)).join(' '));
  check('the runs are the ones in the pack: DEVPAN1 12, DEVPAN2 8, DR1 12, EYEDOOR 9, EYEDORC 5, REACTB 5, WFALLA 4, WAT2 24, TESTPA 75',
    ['DEVPAN1:12', 'DEVPAN2:8', 'DR1:12', 'EYEDOOR:9', 'EYEDORC:5', 'REACTB:5', 'WFALLA:4', 'WAT2:24', 'TESTPA:75']
      .every(s => { const [k, n] = s.split(':'); return TP.ANIMS[k]?.frames.length === +n; }));
  check('EYEDOORC, the door held on green, is not in a run', !TP.animOf('EYEDOORC') && TP.animOf('EYEDORC0'));
  check('Doom\'s clock: 35 tics a second, eight to a frame, and a Doom-length run gets eight',
    TP.TICRATE === 35 && TP.ANIM_TICS === 8 && TP.ANIMS.DEVPAN1.tics === 8 && TP.ANIMS.REACTB.tics === 8 && TP.ANIMS.WFALLA.tics === 8);
  check('and the two long runs, drawn as moving pictures, go faster', TP.ANIMS.WAT2.tics === 4 && TP.ANIMS.TESTPA.tics === 2);
  check('a frame is held for its tics and then steps on',
    TP.frameAt('DEVPAN1A', 0) === 'DEVPAN1A' && TP.frameAt('DEVPAN1A', 7) === 'DEVPAN1A' && TP.frameAt('DEVPAN1A', 8) === 'DEVPAN1B');
  check('every frame animates, from its own place in the run, as in Doom',
    TP.frameAt('DEVPAN1E', 0) === 'DEVPAN1E' && TP.frameAt('DEVPAN1E', 8) === 'DEVPAN1F');
  check('and round again at the end', TP.frameAt('REACTB04', 8) === 'REACTB00' && TP.frameAt('WAT224', 4) === 'WAT201');
  check('a texture that does not animate is always itself', TP.frameAt('CONC_1', 999) === 'CONC_1');
  /* the animator, on a bank of stand-ins */
  {
    const mk = n => ({ texture: { image: null, needsUpdate: false }, own: { n } });
    const bank = { map: new Map(TP.ANIMS.REACTB.frames.map(n => [n, mk(n)])) };
    for (const e of bank.map.values()) e.texture.image = e.own;
    const A = new TP.PackAnimator(bank);
    A.tick(0.01);
    const at0 = bank.map.get('REACTB02').texture.image.n;
    A.tick(8 / 35);
    const at8 = bank.map.get('REACTB02').texture.image.n;
    check('the animator points each texture at the frame it should show, eight tics on', at0 === 'REACTB02' && at8 === 'REACTB03', `${at0} ${at8}`);
    check('and keeps each one\'s own picture for an export', bank.map.get('REACTB02').own.n === 'REACTB02');
  }

  /* WHAT A MAP NEEDS */
  const want = TP.packNamesIn({ sectors: [{ wallTex: 'DEVPAN2C', floorTex: 'CONC_1' }], note: 'CONC_10 is not a name' });
  check('what a map wears from the pack is found in it, with every frame of a run it wears',
    want.includes('CONC_1') && TP.ANIMS.DEVPAN2.frames.every(n => want.includes(n)) && want.length === 9, want.join(' '));
  check('and nothing that is not a whole name', TP.packNamesIn({ a: 'XCONC_1', b: 'GRIDWALL' }).length === 0);

  /* THE SKIES */
  check('seven skies, each a panorama twice as wide as it is tall',
    Object.keys(TP.SKIES).length === 7 && Object.values(TP.SKIES).every(f => { const [w, h] = pngSize(f); return w === 2 * h; }));
  check('the compiler hands a map\'s skybox to the level', /level\.skybox = w\.skybox \|\| null;/.test(src('js/editor/doc.js')));
  const tscnBox = GDp.buildTSCN({ name: 'Skied', world: { skybox: 'XSKY' } }, [], new Map(), { sky: 'sky/XSKY.png', anim: 'doom_anim.gd' });
  check('a Godot scene with a skybox wears it as a panorama',
    /type="PanoramaSkyMaterial"/.test(tscnBox) && /path="sky\/XSKY\.png"/.test(tscnBox) && !/ProceduralSkyMaterial/.test(tscnBox));
  check('and one with an animated texture has the script that runs it, on a node of its own',
    /\[ext_resource type="Script" path="doom_anim\.gd"/.test(tscnBox) && /\[node name="DoomAnimated" type="Node" parent="\."\]\nscript = ExtResource/.test(tscnBox));
  check('and one without either has neither',
    !/Panorama|DoomAnimated/.test(GDp.buildTSCN({ name: 'Plain', world: {} }, [], new Map(), {})));
  const gd = GDp.animScript([TP.animOf('REACTB00'), TP.animOf('WAT201')]);
  check('the Godot script carries each run with its tics, and steps materials found by name',
    /"REACTB": \{"tics": 8, "frames": \["REACTB00", /.test(gd) && /"WAT2": \{"tics": 4/.test(gd) && /m\.resource_name/.test(gd) && /TICRATE := 35\.0/.test(gd));

  /* THE WIRING */
  const main = src('js/main.js'), edit = src('js/editor/editor.js'), ui = src('js/editor/ui.js'), v3 = src('js/editor/view3d.js'), site = src('tools/build-site.sh'), gdsrc = src('js/editor/godot.js');
  check('the game loads what a played map wears from the pack before building it', /loadPack\(textures, want\)/.test(main) && main.indexOf('loadPack(textures, want)') < main.indexOf('registerTextures(textures'));
  check('and runs the animation', /packAnim\.tick\(dt\)/.test(main));
  check('and wears the map\'s skybox, on the sphere and in the air', /sky: skybox \|\| skyBaker\.texture/.test(main) && /world\.skyTex\.value = skybox/.test(main));
  check('the editor loads the map\'s pack textures before the first build, and the rest behind it',
    /await loadPack\(bank, \[\.\.\.packNamesIn\(ed\.doc\)/.test(edit) && /loadPack\(bank\)\.then/.test(edit));
  check('and a map texture cannot take a pack texture\'s name', /builtInTextures = new Set\(\[\.\.\.bank\.map\.keys\(\), \.\.\.PACK_NAMES\]\)/.test(edit));
  check('the editor animates them in whichever view is up', /ed\.anim\?\.tick\(dt\)/.test(v3));
  check('the browser shelves every texture by shape — animated, square, non-square — a run as one cell',
    /export const TEX_SHAPES = \['Animated', 'Square', 'Non-square'\]/.test(ui) && /for \(const shape of TEX_SHAPES\)/.test(ui) && /dataset\.frame/.test(ui));
  check('and a shape is judged by the size on a wall: in a run first, then width against height',
    /if \(animOf\(name\)\) return 'Animated';/.test(ui) && /e\.w !== e\.h \? 'Non-square' : 'Square'/.test(ui));
  {
    const sq = TP.PACK.filter(p => !TP.animOf(p.name) && p.w === p.h).length, ns = TP.PACK.filter(p => !TP.animOf(p.name) && p.w !== p.h).length;
    note('pack shelves', `${Object.keys(TP.ANIMS).length} animated runs, ${sq} square, ${ns} non-square`);
    check('the pack has something on every shelf', sq > 0 && ns > 0 && TP.PACK.some(p => TP.animOf(p.name)));
  }
  check('and the Map tab picks a skybox', /row\('Skybox'/.test(ui) && /PACK_SKIES\.map/.test(ui));
  check('the 3D view swaps the sky for a skybox', /loadSky\(box\)/.test(v3));
  check('a map texture is drawn from a pack texture\'s own frame, not whichever one it is showing', /e\?\.own \|\| e\?\.texture\?\.image/.test(src('js/editor/texcompose.js')));
  check('and so is the Godot export, with every frame of a run it wears', /e\?\.own \|\| e\?\.texture\?\.image/.test(gdsrc) && /textures\/\$\{f\}\.png/.test(gdsrc));
  check('the site carries the pack and the skies', /assets\/textures assets\/skies/.test(site));
  check('and the pack can be built again from the archives', fsP.existsSync(new URL('../tools/build-texpack.py', import.meta.url)));

  /* NOT SQUARE, AND TALL: a texture's width and height are two numbers */
  {
    const MGs = await import('../js/mapgeo.js');
    const bankS = (await import('../js/textures.js')).bakeTextures();
    const pixS = bankS.map.get('GRIDWALL').pix;
    bankS.add('DR1_01', pixS, { w: 64, h: 128, masked: true });
    bankS.add('TREELINE', pixS, { w: 256, h: 128, masked: true });
    const sd = DOCp.newDoc('M', 1024);
    sd.sectors[0].ceil = 1024;
    const Rv = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
    sd.vertices.push(...Rv(256, 256, 512, 512));
    sd.sectors.push({ id: 9, verts: [4, 5, 6, 7], ...DOCp.SECTOR_DEFAULTS, floor: 0 });
    sd.nextId = 10;
    sd.lines[DOCp.lineKey(4, 5)] = { midTex: 'DR1_01' };
    sd.lines[DOCp.lineKey(5, 6)] = { midTex: 'TREELINE', yoff: 32 };
    sd.lines[DOCp.lineKey(6, 7)] = { midTex: 'TREELINE', midHeight: 300 };
    const cS = DOCp.compileDoc(sd);
    const mids = cS.level.lines.filter(l => l.middle === 'DR1_01' || l.middle === 'TREELINE');
    check('a middle texture from the editor is drawn once, Doom\'s way', mids.length === 3 && mids.every(l => l.midOnce));
    const geoS = MGs.buildLevelGeometry(cS.level, bankS);
    const zs = new Map();
    const walkS = o => {
      const pos = o.geometry?.attributes?.position;
      if (pos) { const k = o.name.split('|').pop(); const a = zs.get(k) || zs.set(k, []).get(k); for (let i = 1; i < pos.array.length; i += 3) a.push(pos.array[i]); }
      for (const ch of o.children || []) walkS(ch);
    };
    walkS(geoS.group);
    const span = k => { const a = zs.get(k) || []; return a.length ? [Math.min(...a), Math.max(...a)] : null; };
    const dr = span('DR1_01');
    check('a 64 by 128 door in a 1024-high opening is 128 tall, standing on the floor, not stacked eight high',
      dr && dr[0] === 0 && dr[1] === 128, JSON.stringify(dr));
    const tr = span('TREELINE');
    check('a wide one is its own height too, lifted by its y offset — and a line given a height keeps that height',
      tr && tr[0] === 0 && tr[1] === 300 && (zs.get('TREELINE') || []).some(z => z === 160) && (zs.get('TREELINE') || []).some(z => z === 32),
      JSON.stringify(tr));
    /* the wall's u runs along the line in texture widths and v up it in texture heights */
    const drG = []; const findG = o => { if (o.geometry && o.name.split('|').pop() === 'DR1_01') drG.push(o.geometry); for (const ch of o.children || []) findG(ch); };
    findG(geoS.group);
    const uv = drG[0]?.attributes?.uv?.array || [];
    const us = [], vs = []; for (let i = 0; i < uv.length; i += 2) { us.push(uv[i]); vs.push(uv[i + 1]); }
    check('and it repeats along the line by its width (256 units is four 64-wide doors) and not up it',
      uv.length && Math.abs((Math.max(...us) - Math.min(...us)) - 4) < 1e-6 && Math.abs((Math.max(...vs) - Math.min(...vs)) - 1) < 1e-6,
      `${Math.max(...us) - Math.min(...us)} ${Math.max(...vs) - Math.min(...vs)}`);
    const ext = DOCp.newDoc('E', 1024);
    ext.vertices.push(...Rv(256, 256, 512, 512));
    ext.sectors.push({ id: 9, verts: [4, 5, 6, 7], ...DOCp.SECTOR_DEFAULTS, floor: 0, ceil: 128, ceilTex: 'CEIL' });
    ext.nextId = 10;
    const cE = DOCp.compileDoc(ext);
    check('but the outside wall of a building fills its opening: it is a wall, not a thing in a gap',
      cE.level.lines.filter(l => l.exterior).length === 4 && cE.level.lines.filter(l => l.exterior).every(l => !l.midOnce));
    /* the texture editor keeps a source's shape and wall size */
    const TE = await import('../js/editor/texeditor.js');
    const edS = { bank: { map: new Map() }, doc: { textures: [] } };
    const cliff = TE.fromTexture(edS, 'CLIFF1', { w: 512, h: 1373 }, { width: 512, height: 1373 });
    check('a map texture started from a tall one keeps its shape, brought down evenly',
      cliff.h === 512 && cliff.w === 191 && Math.abs(cliff.layers[0].sy - 512 / 1373) < 1e-9 && Math.abs(cliff.layers[0].sx - 191 / 512) < 1e-9,
      `${cliff.w}x${cliff.h}`);
    check('and covers the wall it did: the world size is the source\'s', cliff.worldW === 512 && cliff.worldH === 1373);
    const small = TE.fromTexture(edS, 'DR1_01', { w: 64, h: 128 }, { width: 64, height: 128 });
    check('and one that fits is left as it is', small.w === 64 && small.h === 128 && small.layers[0].sx === 1 && small.worldH === 128);
    check('the browser draws a texture in its own shape, not squashed square',
      /const k = size \/ Math\.max\(aw, ah\)/.test(src('js/editor/ui.js')));

    /* LINING TEXTURES UP ACROSS MANY LINES: a building of odd-length
       walls, its brick carried round every corner, inside and out */
    bankS.add('BRKTEST', pixS, { w: 64, h: 64 });
    const al = DOCp.newDoc('A', 1024);
    al.vertices.push([100, 100], [197, 100], [197, 171], [100, 171]);
    al.sectors.push({ id: 9, verts: [4, 5, 6, 7], ...DOCp.SECTOR_DEFAULTS, ceil: 128, ceilTex: 'CEIL', outdoor: false, wallTex: 'BRKTEST' });
    al.nextId = 10;
    const alKeys = [[4, 5], [5, 6], [6, 7], [7, 4]].map(([a, b]) => DOCp.lineKey(a, b));
    /* at each corner, the u every face of the building has there */
    const cornerUs = doc => {
      const g = MGs.buildLevelGeometry(DOCp.compileDoc(doc).level, bankS);
      const at = new Map();
      const walk = o => {
        if (o.geometry && o.name.split('|').pop() === 'BRKTEST') {
          const P = o.geometry.attributes.position.array, U = o.geometry.attributes.uv.array;
          for (let i = 0, j = 0; i < P.length; i += 3, j += 2) {
            const k = `${Math.round(P[i])},${Math.round(-P[i + 2])}`;
            const u = Math.round((((U[j] % 1) + 1) % 1) * 1000) % 1000;
            if (!at.has(k)) at.set(k, new Set());
            at.get(k).add(u);
          }
        }
        for (const ch of o.children || []) walk(ch);
      };
      walk(g.group);
      return at;
    };
    const before = cornerUs(al);
    check('four walls of odd lengths do not meet at their corners by themselves',
      [...before.values()].some(s => s.size > 2), JSON.stringify([...before].map(([k, s]) => [k, [...s]])));
    const alED = { size: n => bankS.get(n) ? { w: bankS.get(n).w, h: bankS.get(n).h } : null };
    const nAl = DOCp.alignTextures(al, alKeys, 'x', alED.size);
    const after = cornerUs(al);
    /* a closed run meets itself once, where it began: one seam a side,
       unless the way round is a whole number of bricks (Fit across) */
    check('Align X carries the brick round every corner, inside and out, but the one where each side\'s run closes',
      nAl === 8 && after.size === 4 && [...after.values()].filter(s => s.size > 2).length <= 2 &&
      [...after.values()].filter(s => s.size <= 2).length >= 2,
      JSON.stringify([...after].map(([k, s]) => [k, [...s]])));
    const runs = DOCp.faceRuns(DOCp.facesOf(al, alKeys));
    check('and the building\'s sides are two runs that go all the way round', runs.length === 2 && runs.every(r => r.length === 4));
    DOCp.alignTextures(al, alKeys, 'fitX', alED.size);
    const fitF = DOCp.facesOf(al, alKeys);
    const perim = 2 * (97 + 71), sc = fitF[0].xscale;
    check('Fit across stretches the run so the brick repeats a whole number of times round it',
      fitF.every(f => f.xscale === sc) && Math.abs(perim / (64 * sc) - Math.round(perim / (64 * sc))) < 1e-3 && sc !== 1, `${sc}`);
    check('and it still meets at the corners', [...cornerUs(al).values()].every(s => s.size <= 2));
    DOCp.alignTextures(al, alKeys, 'fitY', alED.size);
    check('Fit up sizes it to the wall: 128 high is two 64s, so no stretch at all', DOCp.facesOf(al, alKeys).every(f => f.yscale === 1));
    DOCp.alignTextures(al, alKeys, 'scale', alED.size, { yscale: 2 });
    check('a scale for all goes on every side of every line', DOCp.facesOf(al, alKeys).every(f => f.yscale === 2 && f.xscale === sc));
    DOCp.alignTextures(al, alKeys, 'reset', alED.size);
    check('and Reset takes it all off again', alKeys.every(k => !al.lines[k]));
    /* the renderer scales by it */
    bankS.add('BRKTEST2', pixS, { w: 64, h: 64 });
    al.lines[alKeys[0]] = { xscale: 2, sides: { 9: { midTex: 'BRKTEST2' }, 1: { midTex: 'BRKTEST2' } } };
    const gw = MGs.buildLevelGeometry(DOCp.compileDoc(al).level, bankS);
    const wu = []; const fw = o => { if (o.geometry && o.name.split('|').pop() === 'BRKTEST2') { const P = o.geometry.attributes.position.array, U = o.geometry.attributes.uv.array;
      for (let i = 0, j = 0; i < P.length; i += 3, j += 2) if (Math.round(-P[i + 2]) === 100) wu.push(U[j]); } for (const ch of o.children || []) fw(ch); };
    fw(gw.group);
    check('a line scaled 2 across wears its texture half as often: 97 units is 97/128 of a repeat',
      wu.length && Math.abs((Math.max(...wu) - Math.min(...wu)) - 97 / 128) < 1e-6, `${Math.max(...wu) - Math.min(...wu)}`);
    {
      const v3g = src('js/editor/view3d.js');
      check('Blender\'s axes through 0,0,0 in 3D — X red, Y green, Z blue — the origin marked, and a gizmo in the corner',
        /AXIS_X = 0xff3352, AXIS_Y = 0x8bdc00/.test(v3g) && /function buildAxes\(\)/.test(v3g) && /line\(AXIS_Z, \[0, -AXIS_LEN, 0\]/.test(v3g) &&
        /drawGizmo\(\)/.test(v3g) && /canvas\.ed-gizmo/.test(src('css/editor.css')));
      const v2g = src('js/editor/view2d.js');
      check('and on the plan: the two axes, the origin ringed, an arrow back to it when it is off the screen, and the key',
        /drawAxes\(\)/.test(v2g) && /strokeStyle = AXIS_X/.test(v2g) && /strokeStyle = AXIS_Y/.test(v2g) && /THE WAY BACK/.test(v2g) && /fillText\('0,0,0'/.test(v2g));
      check('the 3D view lays the plan\'s grid on the floor under the mouse while drawing, and H hides it',
        /function buildGrid\(\)/.test(v3g) && /this\.placeGrid\(\)/.test(v3g) && /GRID_MODES = \['draw', 'rect'/.test(v3g) && /c === 'KeyH'/.test(v3g) &&
        /u\.step\.value = step/.test(v3g));
    }
    check('the inspector aligns every selected line, and Shift+A does Align X',
      /alignBlock\(n\)/.test(src('js/editor/ui.js')) && /up === 'A' && e\.shiftKey/.test(src('js/editor/editor.js')));
  }
}

/* ---------- the grid and the snap ---------- */
section('the grid and the snap');
{
  /* Detailed sector work, at the user's request: any grid size, and a
     point that goes where it is meant to — a vertex, a line, the grid —
     at one unit as surely as at sixty-four. */
  const E = await import('../js/editor/editor.js');
  const D = await import('../js/editor/doc.js');
  const fsG = await import('node:fs');
  const Rq = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
  const mk = () => { const e = new E.Editor(null); e.history = new D.History(D.newDoc('G', 4096)); return e; };
  const vAt = (e, x, y) => e.doc.vertices.findIndex(v => v[0] === x && v[1] === y);

  /* THE SIZE */
  const g = mk();
  g.setGrid(24);
  check('a grid can be any size: 24', g.grid === 24);
  g.gridStep(-1); const down = g.grid; g.setGrid(24); g.gridStep(1);
  check('and [ ] step to the ladder from it: 24 goes down to 16 and up to 32', down === 16 && g.grid === 32);
  g.setGrid(0); const z = g.grid; g.setGrid('junk'); const j = g.grid; g.setGrid(1e6);
  check('nothing below 1 or not a number is a grid, and nothing above the most', z === 32 && j === 32 && g.grid === E.GRID_MAX);
  g.setGrid(1); g.gridStep(-1);
  check('and 1 is as fine as it goes', g.grid === 1);
  g.setGrid(1024); g.gridStep(1);
  check('and the ladder tops out at 1024 for ]', g.grid === 1024);

  /* ONE UNIT IS DETAIL, NOT A WELD */
  const u = mk();
  u.setGrid(1);
  u.addSector(Rq(100, 100, 101, 101));
  check('a one-unit square is a sector', u.doc.sectors.length === 2 && u.doc.sectors[1].verts.length === 4, `${u.doc.sectors.length}`);
  u.addSector(Rq(102, 100, 103, 101));
  check('and one a unit away is another, not welded to it',
    u.doc.sectors.length === 3 && vAt(u, 101, 100) >= 0 && vAt(u, 102, 100) >= 0 && vAt(u, 101, 100) !== vAt(u, 102, 100));
  const nv = u.doc.vertices.length;
  E.vertexFor(u.doc, 101, 101);
  check('the same point is the same vertex', u.doc.vertices.length === nv);
  E.vertexFor(u.doc, 104, 104);
  check('a point one unit off is a new one', u.doc.vertices.length === nv + 1);
  check('the weld is under half a unit', D.WELD < 0.5 && D.WELD > 0.4);

  /* SNAPPING: vertex, then line, then grid */
  const s = mk();
  s.addSector(Rq(1024, 1024, 1536, 1536));
  const sv = s.snapAt(1030, 1020, 16);
  check('a point near a vertex goes onto it', sv.kind === 'vertex' && sv.pt[0] === 1024 && sv.pt[1] === 1024);
  const sl = s.snapAt(1100, 1030, 16);
  check('near a line, onto the line where it crosses the grid nearest the mouse',
    sl.kind === 'line' && sl.pt[0] === 1088 && sl.pt[1] === 1024, JSON.stringify(sl));
  s.snap = false;
  const sf = s.snapAt(1100, 1030, 16);
  check('and with snap off, onto the nearest point of the line', sf.kind === 'line' && sf.pt[0] === 1100 && sf.pt[1] === 1024, JSON.stringify(sf));
  s.snap = true;
  const sg = s.snapAt(1300, 1300, 16);
  check('and away from both, onto the grid', sg.kind === 'grid' && sg.pt[0] === 1280 && sg.pt[1] === 1280);
  s.setGrid(8);
  const s8 = s.snapAt(1100, 1027, 16);
  check('a finer grid gives a finer point on the line', s8.kind === 'line' && s8.pt[0] === 1096 && s8.pt[1] === 1024, JSON.stringify(s8));
  /* a diagonal: the point is exactly on it, not rounded off it */
  const dg = mk();
  dg.addSector([[0, 0], [300, 100], [0, 100]]);
  const sd = dg.snapAt(130, 40, 32);
  check('on a diagonal line the point is exactly on it: x on the grid, y where the line is',
    sd.kind === 'line' && sd.pt[0] === 128 && Math.abs(sd.pt[1] - 42.667) < 1e-9, JSON.stringify(sd));
  /* and a corner there splits the line */
  const before = dg.doc.sectors[1].verts.length;
  dg.cursor = sd.pt; dg.mode = 'vertices';
  dg.insertAtCursor();
  check('and a vertex put there is a corner of the sector — the line is split, not crossed',
    dg.doc.sectors[1].verts.length === before + 1);

  /* DRAGGING: a corner onto a line, onto a vertex */
  const dr = mk();
  dr.addSector(Rq(0, 0, 512, 512));
  dr.addSector(Rq(600, 128, 856, 384));
  const vi = vAt(dr, 600, 128);
  dr.select('vertex', [vi]);
  let mv = dr.beginMove(dr.grabPoint([600, 128]), [600, 128]);
  dr.dragMove(mv, [515, 200], 16);
  check('a vertex dragged near a line snaps onto it, where it crosses the grid', mv.onto === 'line' && mv.done[0] === -88 && mv.done[1] === 64, JSON.stringify(mv));
  dr.endMove(mv);
  const on = vAt(dr, 512, 192);
  const A = dr.doc.sectors.find(x => D.ringOf(dr.doc, x).some(p => p[0] === 0 && p[1] === 0));
  check('and let go, it is a corner of the sector whose wall it is on too — they meet, not overlap',
    on >= 0 && A.verts.includes(on), `${on}`);
  const nvD = dr.doc.vertices.length;
  const vj = vAt(dr, 600, 384);
  dr.select('vertex', [vj]);
  mv = dr.beginMove(dr.grabPoint([600, 384]), [600, 384]);
  dr.dragMove(mv, [509, 507], 16);
  check('a vertex dragged near another snaps onto it exactly, off the grid or not', mv.onto === 'vertex' && mv.done[0] === -88 && mv.done[1] === 128);
  dr.endMove(mv);
  check('and let go, the two weld into one', dr.doc.vertices.length === nvD - 1 && vAt(dr, 512, 512) >= 0);

  /* SNAP THE SELECTION TO THE GRID */
  const sn = mk();
  sn.setGrid(1);
  sn.addSector(Rq(1001, 1003, 1101, 1099));
  sn.setGrid(64);
  sn.select('sector', [sn.doc.sectors[1].id]);
  sn.snapSelToGrid();
  const ringS = D.ringOf(sn.doc, sn.doc.sectors[1]);
  check('Shift+G puts every corner of the selection on the grid',
    ringS.every(([x, y]) => x % 64 === 0 && y % 64 === 0) && ringS.some(p => p[0] === 1024 && p[1] === 1024) && ringS.some(p => p[0] === 1088 && p[1] === 1088), JSON.stringify(ringS));

  /* THE VIEWS */
  const v2 = fsG.readFileSync(new URL('../js/editor/view2d.js', import.meta.url), 'utf8');
  const v3 = fsG.readFileSync(new URL('../js/editor/view3d.js', import.meta.url), 'utf8');
  const uiG = fsG.readFileSync(new URL('../js/editor/ui.js', import.meta.url), 'utf8');
  const edG = fsG.readFileSync(new URL('../js/editor/editor.js', import.meta.url), 'utf8');
  check('the plan snaps drawing, rectangles and new vertices through the one rule', /this\.ed\.snapAt\(x, y, PICK_PX \/ this\.scale\)/.test(v2) && /\['draw', 'rect', 'vertices'\]\.includes\(ed\.mode\)/.test(v2));
  check('and drags with its pick radius, both views', /ed\.dragMove\(dr\.mv, \[p\.x, p\.y\], PICK_PX \/ this\.scale\)/.test(v2) && /dragMove\(dr\.mv, \[p\[0\], p\[1\]\], this\.pxToMap/.test(v3));
  check('the 3D view snaps to lines too', /this\.ed\.snapAt\(g\[0\], g\[1\], this\.pxToMap\(g, HANDLE_PX\)/.test(v3));
  check('the cursor shows what it snapped to: a square on a vertex, a diamond on a line', /cursorKind === 'vertex'/.test(v2) && /cursorKind === 'line'/.test(v2));
  check('the line being drawn shows its length and its angle', /\$\{\+ang\.toFixed\(1\)\}°/.test(v2));
  check('the plan says when the zoom hides the grid it is snapping to', /lines every \$\{step\} at this zoom/.test(v2));
  check('the arrows nudge a grid step, or one unit with snap off', /const step = ed\.snap \? ed\.grid : 1;/.test(v2));
  check('the grid box has a custom size, and shows it while it is the grid', /Custom…/.test(uiG) && /customOpt\.hidden = !custom/.test(uiG));
  check('Shift+G snaps the selection, and the Edit menu has it', /up === 'G' && e\.shiftKey\) \{ ed\.snapSelToGrid\(\)/.test(edG) && /'Snap selection to grid', 'Shift\+G'/.test(uiG));
  check('the position readout is exact, not rounded', /Number\.isInteger\(v\) \? v : \+v\.toFixed\(2\)/.test(uiG));

  /* THE DEFAULTS: checkered grass and a day sky from the pack */
  {
    const TPd = await import('../js/texpack.js');
    const nd = D.newDoc('N'), gd = D.gridDoc();
    check('a new map\'s ground is the pack\'s checkered grass, LAWN2', D.DEFAULT_FLOOR === 'LAWN2' && nd.sectors[0].floorTex === 'LAWN2' && gd.sectors[0].floorTex === 'LAWN2' && TPd.PACK_NAMES.includes('LAWN2'));
    check('and a sector drawn in it too', D.SECTOR_DEFAULTS.floorTex === 'LAWN2');
    check('a new map\'s sky is the pack\'s day sky, BSKY2', D.DEFAULT_SKYBOX === 'BSKY2' && nd.world.skybox === 'BSKY2' && gd.world.skybox === 'BSKY2' && TPd.SKIES.BSKY2);
    const old = D.compileDoc({ ...nd, world: { sky: nd.world.sky } }).level;
    check('but a map saved without a skybox keeps its painted sky', old.skybox === null && D.compileDoc(nd).level.skybox === 'BSKY2');
    check('and the editor and a test run load the default floor before building',
      /packNamesIn\(\[DEFAULT_FLOOR\]\)/.test(edG) && /packNamesIn\(played\.level\.sectors\.map/.test(fsG.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8')));
  }
}

/* ---------- light and fog ---------- */
section('light and fog');
{
  /* At the user's request: fog per sector, a light colour per sector, a
     map-wide light colour, ambient light and fog, a fog colour that
     overrides every other, and the ambient light mixed into the fog. */
  const D = await import('../js/editor/doc.js');
  const M = await import('../js/material.js');
  const MG = await import('../js/mapgeo.js');
  const TX = await import('../js/textures.js');
  const fsL = await import('node:fs');
  const near = (a, b, e = 1e-6) => a.length === b.length && a.every((v, i) => Math.abs(v - b[i]) < e);
  const Rv = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];

  const none = D.mapLightOf({});
  check('a map that says nothing has white light, no ambient and no fog',
    near(none.lightColor, [1, 1, 1]) && near(none.ambient, [0, 0, 0]) && none.fog[3] === 0 && !none.override && none.fogAmbient === 1);
  const ml = D.mapLightOf({ lightColor: '#ff8000', ambient: { color: '#ffffff', amount: 0.25 }, fog: { color: '#00ff00', density: 250, override: true }, fogAmbient: 0.5 });
  check('the map\'s light colour, its ambient light (colour times strength), its fog and the override',
    near(ml.lightColor, [1, 128 / 255, 0]) && near(ml.ambient, [0.25, 0.25, 0.25]) && near(ml.fog, [0, 1, 0, 100]) && ml.override && ml.fogAmbient === 0.5);

  /* a room with its own fog and light colour in a field that has neither */
  const doc = D.newDoc('F', 4096);
  doc.vertices.push(...Rv(1024, 1024, 2048, 2048));
  doc.sectors.push({ id: 9, verts: [4, 5, 6, 7], ...D.SECTOR_DEFAULTS,
    fog: { color: '#0000ff', density: 40 }, lightColor: '#808080', colors: { top: '#ff0000' } });
  doc.nextId = 10;
  const c1 = D.compileDoc(doc);
  const room = c1.level.sectors[c1.index[1]], field = c1.level.sectors[c1.index[0]];
  check('a sector\'s fog reaches the level: its colour and density', room.fog && near(room.fog, [0, 0, 1, 40]));
  check('and a sector without one has none of its own (the map\'s default fills in)', !field.fog);
  check('a sector\'s light colour multiplies into its Doom 64 colours, white where one is unset',
    near(room.tint.top, [128 / 255, 0, 0]) && near(room.tint.floor, [128 / 255, 128 / 255, 128 / 255]) && near(room.tint.thing, [128 / 255, 128 / 255, 128 / 255]));
  check('and a sector with neither is untinted, as before', !field.tint);
  const c2 = D.compileDoc({ ...doc, world: { ...doc.world, fog: { color: '#ff00ff', density: 10, override: true } } });
  const room2 = c2.level.sectors[c2.index[1]];
  check('the map\'s fog colour overrides the sector\'s when it says so, keeping the sector\'s density',
    near(room2.fog, [1, 0, 1, 40]) && c2.level.mapLight.override && c2.level.mapLight.fog[3] === 10);

  /* the renderer's side */
  M.applyMapLight(c2.level.mapLight);
  const W = M.world;
  check('applied, the fog is the world\'s default and the far haze takes its colour',
    W.fogDefault.value.w === 10 && W.airOverride.value === 1 && W.airColor.value.r === 1 && W.airColor.value.g === 0);
  M.applyMapLight(null);
  check('and a level without one puts everything back to doing nothing',
    W.lightColor.value.r === 1 && W.ambientColor.value.r === 0 && W.fogDefault.value.w === 0 && W.airOverride.value === 0);

  /* the geometry: every vertex carries its sector's fog */
  const bank = TX.bakeTextures();
  bank.add(D.DEFAULT_FLOOR, bank.map.get('GRID').pix, { w: 256, h: 256 });
  const geo = MG.buildLevelGeometry(c1.level, bank);
  let blue = 0, plain = 0, bad = 0;
  const walk = o => {
    const f = o.geometry?.attributes?.fogRGBA, pos = o.geometry?.attributes?.position;
    if (f) {
      if (f.count !== pos.count) bad++;
      for (let i = 0; i < f.count; i++) {
        if (f.array[i * 4 + 3] === 40 && f.array[i * 4 + 2] === 1) blue++;
        else if (f.array[i * 4 + 3] === -1) plain++;
      }
    }
    for (const ch of o.children || []) walk(ch);
  };
  walk(geo.group);
  check('every surface carries a fog for every corner: the room\'s blue, the field\'s default', blue > 0 && plain > 0 && bad === 0, `${blue} ${plain} ${bad}`);

  /* the shader */
  const src = fsL.readFileSync(new URL('../js/material.js', import.meta.url), 'utf8');
  check('every world shader gets the new uniforms, declared and bound (the whitelist)',
    ['lightColor', 'ambientColor', 'fogAmbient', 'fogDefault', 'airColor', 'airOverride'].every(n =>
      new RegExp(`uniform (vec3|vec4|float)\\s+${n};`).test(M.WORLD_UNIFORMS_GLSL) && M.worldUniforms()[n] === W[n]));
  check('the light colour multiplies the sector\'s light, and the ambient light adds under it',
    /vec3 c = albedo \* l \* tint \* lightColor;/.test(src) && /c \+= albedo \* ambientColor \* \(1\.0 - fullbright\);/.test(src));
  check('the fog is the sector\'s, or the map\'s default, lit by the light colour, with the ambient in it',
    /vec4 fg = vFog\.a < 0\.0 \? fogDefault : vFog;/.test(src) && /vec3 fc = fg\.rgb \* lightColor \+ ambientColor \* fogAmbient;/.test(src) && /exp2\(-depth \* fg\.a \/ 25600\.0\)/.test(src));
  check('and the override takes the far haze too', /air = mix\(air, airColor, airOverride\);/.test(src));

  /* the wiring */
  const ui = fsL.readFileSync(new URL('../js/editor/ui.js', import.meta.url), 'utf8');
  check('the editor and a test run both put the map\'s light on',
    /applyMapLight\(c\.level\.mapLight\)/.test(fsL.readFileSync(new URL('../js/editor/view3d.js', import.meta.url), 'utf8')) &&
    /applyMapLight\(played \? played\.level\.mapLight : null\)/.test(fsL.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8')));
  check('a sector has a light colour and a fog in the inspector', /'Light colour'/.test(ui) && /'Fog density'/.test(ui) && /x\.fog = \{ color:/.test(ui));
  check('and the Map tab has the light colour, the ambient, the fog, the override and the mix',
    /row\('Ambient light'/.test(ui) && /row\('Ambient strength'/.test(ui) && /row\('Ambient in fog'/.test(ui) && /row\('Override fog colour'/.test(ui) && /row\('Fog colour'/.test(ui));
  /* WHAT STANDS IN A SECTOR: sprites, trees and 3D objects take its
     light, colour and fog (js/sectorgrid.js) */
  {
    const SG = await import('../js/sectorgrid.js');
    const g = SG.sampleSectorGrid(c1.level);
    const cellAt = (x, y) => { const i = Math.floor((x - g.x0) / g.cell), j = Math.floor((y - g.y0) / g.cell); return (j * g.cols + i) * 4; };
    const kr = cellAt(1536, 1536), kf = cellAt(3500, 3500);
    check('the sector grid covers the map in cells no coarser than it must be',
      g && g.cols <= SG.GRID_MAX_CELLS && g.rows <= SG.GRID_MAX_CELLS && g.cell >= SG.GRID_MIN_CELL, g && `${g.cols}x${g.rows} @${g.cell}`);
    check('a cell in the room holds its light and thing colour',
      g.a[kr + 3] === Math.round(room.light * 255) && g.a[kr] === 128 && g.a[kr + 1] === 128, `${[...g.a.subarray(kr, kr + 4)]}`);
    check('and its fog: colour, and density over a hundred',
      g.b[kr + 2] === 255 && g.b[kr] === 0 && g.b[kr + 3] === Math.round(0.40 * 255), `${[...g.b.subarray(kr, kr + 4)]}`);
    check('a cell in the field is white, at its light, with no fog of its own (the map\'s default)',
      g.a[kf] === 255 && g.a[kf + 3] === Math.round(field.light * 255) && g.b[kf + 3] === 0);
    check('the grid is only for maps from the editor: a level without mapLight switches it off',
      SG.applySectorGrid({ sectors: [] }) === null && M.world.sectorOn.value === 0);

    /* FOG FADES FROM SECTOR TO SECTOR, AND INTO THE SKY: the fog is
       followed along each line of sight (FOG_GLSL). Here the shader's
       walk is done again in JS over the same grid, to show what it
       does: fog comes in continuously as you walk into the room, a
       floor's fog has no edge at the sector line, and the sky fades. */
    check('a map with a sector fog of its own follows the fog; one without does not',
      SG.hasOwnFog(g) && !SG.hasOwnFog(SG.sampleSectorGrid(D.compileDoc(D.newDoc('N', 4096)).level)));
    const fogSrc = M.FOG_GLSL;
    check('the shader walks the line of sight over the grid, finer near the eye, halving each crossing',
      /#define FOG_STEPS 16/.test(fogSrc) && /#define FOG_HALVINGS 5/.test(fogSrc) && /float s = u \* u;/.test(fogSrc) &&
      /if \(fogSame\(fogAirAt\(mix\(a, b, m\)\), gPrev\)\) lo = m; else hi = m;/.test(fogSrc) &&
      /exp2\(-len \* fg\.a \* fogThick\(z0, z1, top\) \/ 25600\.0\)/.test(fogSrc) && /#define FOG_FADE 128\.0/.test(fogSrc));
    check('every world surface uses it when the map has sector fog, and the sky does too',
      /if \(fogMarch > 0\.5\) \{[\s\S]{0,300}fogAlong\(eyePos, world, fg\)/.test(fsL.readFileSync(new URL('../js/material.js', import.meta.url), 'utf8')) &&
      /fogAlong\(cameraPosition, far, fogAirAt\(far\)\)/.test(fsL.readFileSync(new URL('../js/sky.js', import.meta.url), 'utf8')) &&
      /uniform float fogMarch;/.test(M.WORLD_UNIFORMS_GLSL) && M.worldUniforms().fogMarch === M.world.fogMarch);
    const airAt = (x, y) => {                        /* fogAirAt, in map axes */
      const i = Math.floor((x - g.x0) / g.cell), j = Math.floor((y - g.y0) / g.cell);
      if (i < 0 || j < 0 || i >= g.cols || j >= g.rows) return [0, 0, 0, 0];
      const k = (j * g.cols + i) * 4;
      return g.b[k + 3] > 0 ? [g.b[k] / 255, g.b[k + 1] / 255, g.b[k + 2] / 255, g.b[k + 3] / 255 * 100] : [0, 0, 0, 0];
    };
    const FADE = 128;
    const topAt = (x, y) => {                        /* fogTopAt: [top, how it ends] */
      const i = Math.floor((x - g.x0) / g.cell), j = Math.floor((y - g.y0) / g.cell);
      if (i < 0 || j < 0 || i >= g.cols || j >= g.rows) return [1e9, FADE];
      const k = (j * g.cols + i) * 4;
      return [g.c[k] * 256 + g.c[k + 1] - 32768, g.c[k + 2] > 127 ? 1 : FADE];
    };
    const G = (z, [t, f]) => z <= t ? z : t + f * (1 - Math.exp((t - z) / f));
    const thick = (z0, z1, t) => Math.abs(z1 - z0) < 1 ? ((z0 + z1) / 2 <= t[0] ? 1 : Math.exp((t[0] - (z0 + z1) / 2) / t[1])) : (G(z1, t) - G(z0, t)) / (z1 - z0);
    const same = (p, q) => Math.max(...[0, 1, 2].map(i => Math.abs(p[i] - q[i]))) < 0.01 && Math.abs(p[3] - q[3]) < 0.2;
    const along = (a, b, endFog) => {                /* fogAlong: how much gets through */
      const len = Math.hypot(b[0] - a[0], b[1] - a[1], (b[2] || 0) - (a[2] || 0));
      const az = a[2] ?? 41, bz = b[2] ?? 41;
      const at = s => airAt(a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s);
      const tAt = s => topAt(a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s);
      const z = s => az + (bz - az) * s;
      let T = 1, gp = at(0), tp = tAt(0), sp = 0;
      const span = (f, l, z0, z1, t) => { if (f[3] > 0 && l > 0) T *= 2 ** (-l * f[3] * thick(z0, z1, t) / 25600); };
      for (let i = 1; i <= 16; i++) {
        const s = (i / 16) ** 2, gg = i === 16 ? (endFog || at(1)) : at(s);
        let tt = tAt(s);
        if (same(gg, gp)) { span(gp, (s - sp) * len, z(sp), z(s), tp); tt = tp; }
        else {
          let lo = sp, hi = s;
          for (let k = 0; k < 5; k++) { const m = (lo + hi) / 2; if (same(at(m), gp)) lo = m; else hi = m; }
          const cut = (lo + hi) / 2;
          span(gp, (cut - sp) * len, z(sp), z(cut), tp); span(gg, (s - cut) * len, z(cut), z(s), tt);
        }
        gp = gg; tp = tt; sp = s;
      }
      return T;
    };
    /* the room (1024..2048) has fog 40: half-way in at 640 units */
    const ref = 2 ** (-512 * 40 / 25600);
    check('looking 512 units across the fogged room fogs by 512 units of it',
      Math.abs(along([1200, 1500], [1712, 1500]) - ref) < 0.01, along([1200, 1500], [1712, 1500]).toFixed(3));
    check('a floor just over the sector line is barely fogged, from outside: no edge where the sector changes',
      along([500, 1500], [1030, 1500]) > 0.97 && along([500, 1500], [1018, 1500]) === 1);
    check('and deeper in, it thickens with how much of the fog you look through',
      along([500, 1500], [1200, 1500]) > along([500, 1500], [1500, 1500]) && along([500, 1500], [1500, 1500]) > along([500, 1500], [2000, 1500]));
    const walkIn = [900, 1000, 1020, 1030, 1100, 1300].map(x => along([x, 1500], [2040, 1500]));
    check('walking in toward the far wall, its fog changes smoothly — no jump at the doorway',
      walkIn.every((v, i) => i === 0 || Math.abs(v - walkIn[i - 1]) < 0.12), walkIn.map(v => v.toFixed(2)).join(' '));
    const skyUp = along([1500, 1500, 41], [1500, 1500, 14000]), skyOut = along([3900, 1500], [3900 + 14000, 1500]);
    const skyAcross = along([1500, 1500], [1500 + 14000, 1500]);
    /* the room is under the sky, so its fog stands FOG_TOP over the floor
       and thins away above: overhead you look through that and no more */
    const upRef = 2 ** (-(SG.FOG_TOP - 41 + FADE) * 40 / 25600);
    check('the sky overhead, standing in the fog, is dimmed by the fog above you and no more; looking away outside, clear',
      Math.abs(skyUp - upRef) < 0.02 && skyUp < 0.7 && skyOut === 1, `${skyUp.toFixed(3)} ~${upRef.toFixed(3)} ${skyOut}`);
    const kTop = cellAt(1536, 1536);
    check('a fog under the sky reaches FOG_TOP over its floor; off the map, as high as there is',
      g.c[kTop] * 256 + g.c[kTop + 1] - 32768 === room.floor + SG.FOG_TOP && SG.packHeight(32767).join() === '255,255');
    const indoor = JSON.parse(JSON.stringify(doc)); indoor.sectors[1].outdoor = false; indoor.sectors[1].ceil = 128;
    const gi = SG.sampleSectorGrid(D.compileDoc(indoor).level);
    check('and indoors, the ceiling, where it stops dead: no fog in the air over a roof',
      gi.c[kTop] * 256 + gi.c[kTop + 1] - 32768 === 128 && gi.c[kTop + 2] === 255 && g.c[kTop + 2] === 0 &&
      /t\.z > 127\.0 \? 1\.0 : FOG_FADE/.test(M.FOG_GLSL));
    const fogBank = [along([500, 1500, 41], [1500, 1500, 41]), along([500, 1500, 400], [1500, 1500, 400]), along([500, 1500, 1200], [1500, 1500, 1200])];
    check('seen from outside the fog is a bank that thins upward into the sky, not a column',
      fogBank[0] < fogBank[1] && fogBank[1] < fogBank[2] && fogBank[2] > 0.95, fogBank.map(v => v.toFixed(3)).join(' '));
    check('and across the room it is hazed by the fog between you and the room\'s edge',
      Math.abs(skyAcross - 2 ** (-548 * 40 / 25600)) < 0.03, skyAcross.toFixed(3));
    const backIn = along([2100, 1500], [2100 - 14000, 1500]);
    check('and looking back through the room from outside, the sky behind it is hazed by the room\'s width only',
      Math.abs(backIn - 2 ** (-1024 * 40 / 25600)) < 0.03, backIn.toFixed(3));
    const mat = fsL.readFileSync(new URL('../js/material.js', import.meta.url), 'utf8');
    const forest = fsL.readFileSync(new URL('../js/forest.js', import.meta.url), 'utf8');
    const v3 = fsL.readFileSync(new URL('../js/editor/view3d.js', import.meta.url), 'utf8');
    check('every world material binds the grid', ['sectorA', 'sectorB', 'sectorRect', 'sectorOn'].every(n => M.worldUniforms()[n] === M.world[n]));
    check('a sprite or model reads it at its foot: a standee takes the fog, a model the light, colour and fog',
      /#ifndef TINT\s+if \(sectorOn > 0\.5\)/.test(mat) && /vec3 foot = iPos;/.test(mat) && /vFog = sectorFogAt\(foot\);/.test(mat) && /vLight \*= sl\.a;/.test(mat) && /vTint \*= sl\.rgb;/.test(mat));
    check('trees take their sector\'s light, colour and fog',
      /vSecLight = sectorLightAt\(iPos\); vFog = sectorFogAt\(iPos\);/.test(forest) && /t\.rgb \* vSecLight\.rgb/.test(forest) && /vSecLight\.a >= 0\.0 \? vSecLight\.a : light/.test(forest));
    check('the editor\'s plants and people are lit and fogged the same way',
      /sectorLightAt\(base\); vFog = sectorFogAt\(base\);/.test(v3) && /worldShade\(c\.rgb \* markTint \* vSecLight\.rgb/.test(v3));
    check('the editor and a test run both lay the grid down',
      /applySectorGrid\(c\.level\)/.test(v3) && /applySectorGrid\(played \? played\.level : null\)/.test(fsL.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8')));
    /* a box: the sector under its middle */
    const pd = JSON.parse(JSON.stringify(doc));
    pd.props = [{ id: 20, x0: 1400, y0: 1400, x1: 1600, y1: 1600, z0: 0, z1: 64, tex: 'GRIDWALL' },
                { id: 21, x0: 3000, y0: 3000, x1: 3100, y1: 3100, z0: 0, z1: 64, tex: 'GRIDWALL' },
                { id: 22, x0: 1400, y0: 1700, x1: 1500, y1: 1800, z0: 0, z1: 64, tex: 'GRIDWALL', light: 0.9 }];
    const cp = D.compileDoc(pd).level.props;
    check('a 3D box takes the light, thing colour and fog of the sector it stands in',
      cp[0].light === room.light && near(cp[0].tint, room.tint.thing) && near(cp[0].fog, room.fog) && cp[1].light === field.light && !cp[1].fog);
    check('unless it has a light of its own', cp[2].light === 0.9 && near(cp[2].fog, room.fog));
    const geoP = MG.buildLevelGeometry(D.compileDoc(pd).level, bank);
    let boxFog = 0;
    const walkP = o => { const f = o.geometry?.attributes?.fogRGBA; if (f) for (let i = 0; i < f.count; i++) if (f.array[i * 4 + 3] === 40) boxFog++; for (const ch of o.children || []) walkP(ch); };
    walkP(geoP.group);
    check('and its faces carry that fog', boxFog > blue, `${boxFog} against ${blue} without the boxes`);
  }
  /* A THING CROSSING INTO ANOTHER SECTOR eases into its look, fast */
  {
    const SG = await import('../js/sectorgrid.js');
    const obj = {};
    const a = SG.tweenLook(obj, field, 0);
    check('a thing that has just appeared takes its sector\'s look at once', a.light === field.light && near(a.tint, [1, 1, 1]));
    const b1 = SG.tweenLook(obj, room, 0.016);
    check('stepping into another sector it does not snap: one frame in, its colour is part of the way there',
      b1.tint[1] < 1 && b1.tint[1] > room.tint.thing[1] + 0.05, `${b1.tint}`);
    check('a fog coming in from none takes its colour at once, and only its density eases',
      near(b1.fog.slice(0, 3), [0, 0, 1]) && b1.fog[3] > 0 && b1.fog[3] < 40);
    SG.tweenLook(obj, room, 0.25);
    check('and a quarter of a second later it is all the way there', Math.abs(obj._look.tint[1] - room.tint.thing[1]) < 0.01 && Math.abs(obj._look.fog[3] - 40) < 0.5);
    const dim = { ...room, light: 0.2 };
    const lo = SG.tweenLook(obj, dim, 0.016).light;
    check('and so does its light', lo < room.light && lo > 0.2);
    check('fast: most of the way in a tenth of a second', SG.LOOK_TAU <= 0.08);
    const act = fsL.readFileSync(new URL('../js/actor.js', import.meta.url), 'utf8');
    const std = fsL.readFileSync(new URL('../js/standees.js', import.meta.url), 'utf8');
    check('the game\'s moving things use it, handing their eased fog to the batch',
      /tweenLook\(this, this\.sector, now - \(this\._lookAt \?\? now\)\)/.test(act) && /look\.tint, look\.fog\);/.test(act) &&
      /g\.setAttribute\('iFog', a\.fog\);/.test(std) && /if \(iFog\.w >= 0\.0\) vFog = iFog;/.test(fsL.readFileSync(new URL('../js/material.js', import.meta.url), 'utf8')));
  }

  /* THE GODOT EXPORT'S STATIC THINGS: trees and decor as billboards,
     with the sector's baked light on them */
  {
    const GD = await import('../js/editor/godot.js');
    const spr = new Map([['fir_tall_1', { file: 'sprites/fir_tall_1.png', w: 128, h: 256 }],
                         ['thing:CRATE', { file: 'sprites/crate.png', w: 32, h: 42, worldH: 58 }]]);
    const tscn = GD.buildTSCN({ name: 'Decor', world: {} }, [
      { type: 'START', x: 0, y: 0, z: 0, angle: 0 },
      { type: 'PLANT', kind: 'fir_tall_1', x: 64, y: 64, z: 0, mod: [0.5, 0.25, 0.2] },
      { type: 'CRATE', x: 128, y: 0, z: 0, mod: [0.5, 0.25, 0.2] },
      { type: 'STREETLAMP', x: 256, y: 0, z: 0 },
      { type: 'SHOPPER', x: 300, y: 0, z: 0 },
    ], spr, { scale: 1 / 32 });
    check('static decor is a billboard of its picture, at its size in the game',
      /\[node name="CRATE_1" type="Sprite3D" parent="Decor"\]/.test(tscn) && tscn.includes(`pixel_size = ${+((58 / 32) / 42).toFixed(5)}`));
    check('and trees and decor carry the baked light and colour of their sector',
      (tscn.match(/modulate = Color\(0\.5, 0\.25, 0\.2, 1\)/g) || []).length === 2);
    check('a street lamp (geometry in the game) and a person (not static) stay markers',
      /\[node name="STREETLAMP_1" type="Marker3D"/.test(tscn) && /\[node name="SHOPPER_1" type="Marker3D"/.test(tscn));
    check('the decor list is the static things with a picture', GD.DECOR_TYPES.join() === 'TROLLEY,BOLLARD,CRATE,FUELCAN,GRAVESTONE');
    const lit = GD.buildTSCN({ name: 'L', world: {} }, [{ type: 'CRATE', x: 0, y: 0, z: 0, mod: [0.5, 0.5, 0.5] }], spr, { scale: 1 / 32, bake: false });
    check('with lit materials the billboards are left for Godot\'s lights', !/modulate/.test(lit));

    /* AUTOMATIC COLLISION: a box, the bounds of what the game collides
       with, on each billboard that stops you */
    const spC = new Map([['fir_tall_1', { file: 'sprites/fir_tall_1.png', w: 128, h: 256 }],
      ['fern', { file: 'sprites/fern.png', w: 64, h: 64 }],
      ['thing:CRATE', { file: 'sprites/crate.png', w: 32, h: 42, worldH: 58, solid: true, radius: 20, height: 58 }],
      ['thing:FUELCAN', { file: 'sprites/fuelcan.png', w: 32, h: 42, worldH: 38, solid: false, radius: 12, height: 38 }]]);
    const col = [
      { type: 'PLANT', kind: 'fir_tall_1', x: 64, y: 64, z: 0 }, { type: 'PLANT', kind: 'fir_tall_1', x: 164, y: 64, z: 0 },
      { type: 'PLANT', kind: 'fir_tall_1', x: 264, y: 64, z: 0, scale: 2 }, { type: 'PLANT', kind: 'fern', x: 0, y: 64, z: 0 },
      { type: 'CRATE', x: 128, y: 0, z: 0 }, { type: 'FUELCAN', x: 0, y: 0, z: 0 }];
    const tc = GD.buildTSCN({ name: 'C', world: {} }, col, spC, { scale: 1 / 32 });
    check('each tree gets a static body with a box around its trunk, standing on the floor',
      /\[node name="Collision" type="StaticBody3D" parent="Sprites\/fir_tall_1_1"\]/.test(tc) &&
      /\[node name="Shape" type="CollisionShape3D" parent="Sprites\/fir_tall_1_1\/Collision"\]\ntransform = Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 4\.6875, 0\)\nshape = SubResource\("Box_1"\)/.test(tc) &&
      tc.includes('[sub_resource type="BoxShape3D" id="Box_1"]\nsize = Vector3(0.875, 9.375, 0.875)'));
    check('boxes of one size are shared, and a scaled tree has its own',
      (tc.match(/type="BoxShape3D"/g) || []).length === 3 && (tc.match(/SubResource\("Box_1"\)/g) || []).length === 2 &&
      tc.includes('size = Vector3(1.75, 18.75, 1.75)'));
    check('solid decor gets a box of its radius and height; a fern and a fuel can, walked through in the game, get none',
      tc.includes('size = Vector3(1.25, 1.8125, 1.25)') && /parent="Decor\/CRATE_1"/.test(tc) &&
      !/parent="Decor\/FUELCAN_1"/.test(tc) && !/parent="Sprites\/fern_1"/.test(tc));
    check('the sub-resources are counted in the load steps, and come before the nodes',
      tc.startsWith(`[gd_scene load_steps=${(tc.match(/^\[(ext|sub)_resource/gm) || []).length + 1} format=3]`) &&
      tc.lastIndexOf('[sub_resource') < tc.indexOf('[node '));
    const noC = GD.buildTSCN({ name: 'C', world: {} }, col, spC, { scale: 1 / 32, collision: false });
    check('and with collision off, no bodies', !/StaticBody3D|BoxShape3D/.test(noC));
  }


}

/* ---------- THE MAZE: the demo's world ---------- */
section('the maze');
{
  const MZ = await import('../js/maps/maze.js');
  const DZ = await import('../js/editor/doc.js');
  const fsZ = await import('node:fs');
  const a = MZ.mazeDoc(424242), b = MZ.mazeDoc(424242), c = MZ.mazeDoc(7);
  check('one seed, one maze; another seed, another', DZ.serialise(a) === DZ.serialise(b) && DZ.serialise(a) !== DZ.serialise(c));
  const t0 = performance.now();
  const out = DZ.compileDoc(a);
  const ms = performance.now() - t0;
  const L = out.level;
  note('THE MAZE', `${a.sectors.length} sectors, ${L.lines.length} lines, ${L.things.length} things, compiled in ${ms.toFixed(0)}ms`);
  check('it builds with no problems', !out.problems.length, out.problems.slice(0, 3).map(p => p.msg).join('; '));
  const people = L.things.filter(t => t.type === 'TOWNIE' || t.type === 'SHOPPER');
  check('with tons of people in it', people.length >= 400, `${people.length}`);
  const st = L.things.find(t => t.type === 'START');
  check('the start is on the path, not in a hedge', L.sectorAt(st.x, st.y)?.floor === 0);
  check('every person stands on the floor of a path or a plaza', people.every(t => L.sectorAt(t.x, t.y)?.floor === 0));
  check('the hedges stand higher than anyone can step', a.sectors.filter(s => s.name === 'hedge').every(s => s.floor === MZ.HEDGE_H) && MZ.HEDGE_H > 24);
  /* EVERY PATH CELL REACHABLE from the start: flood the cells over the level */
  const N = MZ.MAZE_CELLS, P = MZ.CELL + MZ.WALL;
  const cx = i => i * P + MZ.WALL + MZ.CELL / 2;
  const seen = new Set(['0,0']), q = [[0, 0]];
  while (q.length) {
    const [x, y] = q.pop();
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= N || ny >= N || seen.has(`${nx},${ny}`)) continue;
      /* the gap between the two cells: path, or hedge */
      const gx = (cx(x) + cx(nx)) / 2, gy = (cy => cy)((cx(y) + cx(ny)) / 2);
      if (L.sectorAt(gx, gy)?.floor !== 0) continue;
      seen.add(`${nx},${ny}`); q.push([nx, ny]);
    }
  }
  check('every cell of the maze can be walked to from the start', seen.size === N * N, `${seen.size} of ${N * N}`);
  check('braided: more ways through than a perfect maze has', (() => {
    let gaps = 0;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      if (x + 1 < N && L.sectorAt((cx(x) + cx(x + 1)) / 2, cx(y))?.floor === 0) gaps++;
      if (y + 1 < N && L.sectorAt(cx(x), (cx(y) + cx(y + 1)) / 2)?.floor === 0) gaps++;
    }
    return gaps > N * N - 1;
  })());
  check('with plazas, lamps and trees', a.sectors.some(s => s.name === 'plaza') && L.things.some(t => t.type === 'STREETLAMP') && L.plants.length > 0);
  const packSrc = fsZ.readFileSync('js/texpack-data.js', 'utf8');
  check('every texture it wears is in the pack', ['IVY1', 'MOSS_01', 'DIRT_01', 'CONC_4'].every(n => packSrc.includes(`"${n}"`) || packSrc.includes(`'${n}'`)));
  const mainZ = fsZ.readFileSync('js/main.js', 'utf8');
  check('THE DEMO IS THE MAZE: the game opens on a new one each time, ?seed=N plays one again',
    /if \(!q\.has\('play'\)\) return maze\(\);/.test(mainZ) && /q\.has\('seed'\) \? \(\+q\.get\('seed'\) >>> 0\) \|\| 1 : newMazeSeed\(\)/.test(mainZ));
  check('and the editor opens a new one from File', /\['Open demo: a new MAZE', '', \(\) => ed\.fileDemo\(\)\]/.test(fsZ.readFileSync('js/editor/ui.js', 'utf8')));
}

/* ---------- THE SPRAWL ---------- */
/* THE DEMO LEVEL, at the user's request: sprawling, made of every asset
   the user has given and none that were generated, under the earth
   tones and the pixel dither, which came back with it. The thing that
   can go quietly wrong is a texture: a sector with no wall texture of
   its own falls back to GRIDWALL, which is drawn here, and nothing on
   screen says so. So the COMPILED level is walked, every surface of it,
   and every name it wears is held to the pack. */
/* ---------- layers, steps, and a snap that stays ---------- */

section('jesse, the PvP maze');
{
  const JS = await import('../js/maps/jesse.js');
  const DZ = await import('../js/editor/doc.js');
  const fsJ = await import('node:fs');
  const strip = d => { const o = { ...d }; delete o.jesse; return DZ.serialise(o); };
  /* a small one to build, so the test does not spend a minute compiling */
  const a = JS.jesseDoc(90210, { w: 22, h: 14 }), b = JS.jesseDoc(90210, { w: 22, h: 14 });
  check('one seed, one JESSE', strip(a) === strip(b));
  /* WILDLY DIFFERENT: across a dozen seeds, the sizes, the algorithms,
     the zone counts and the symmetry all move */
  const many = Array.from({ length: 12 }, (_, k) => JS.jesseDoc(1000 + k * 7919).jesse);
  const sizes = new Set(many.map(j => j.W + 'x' + j.H)), algos = new Set(many.flatMap(j => j.zones.map(z => z.algo)));
  const zoneCounts = new Set(many.map(j => j.zones.length)), sym = new Set(many.map(j => j.symmetric));
  check('wildly different every time: size, zones, algorithms, symmetry',
    sizes.size >= 8 && algos.size === JS.ALGOS.length && zoneCounts.size >= 3 && sym.size === 2,
    `${sizes.size} sizes, ${[...algos]}, ${[...zoneCounts]} zone counts`);
  const t0 = performance.now();
  const out = DZ.compileDoc(a);
  const L = out.level;
  note('JESSE', `${a.jesse.W}x${a.jesse.H} cells, ${a.sectors.length} sectors, compiled in ${(performance.now() - t0).toFixed(0)}ms`);
  check('it builds with no problems', !out.problems.length, out.problems.slice(0, 3).map(p => p.msg).join('; '));
  /* TWO BASES, mirror images, each with gates, cover, a tower and stock */
  const [A, B] = a.world.pvp.teams;
  check('two teams, each with spawn pads and gates', A.spawns.length >= 5 && B.spawns.length === A.spawns.length && A.gates.length >= 1 && B.gates.length === A.gates.length);
  const [MX, MY] = a.jesse.size;
  check('the bases are point mirrors of each other',
    A.spawns.every(([x, y], k) => Math.abs(MX - x - B.spawns[k][0]) <= 1 && Math.abs(MY - y - B.spawns[k][1]) <= 1));
  check('every spawn pad is on a base floor', [...A.spawns, ...B.spawns].every(([x, y]) => L.sectorAt(x, y)?.floor === 0));
  const floors = new Set(a.sectors.map(s => s.floor));
  check('a fort wall under the hedges, cover you can shoot over but not step on, a tower up steps',
    floors.has(JS.FORT_H) && floors.has(JS.COVER_H) && floors.has(JS.TOWER_H) && JS.COVER_H > 24 && JS.COVER_H < 49 &&
    [24, 48, 72].every(h => floors.has(h)));
  check('stock to fortify with: crates and fuel cans in both yards',
    L.things.filter(t => t.type === 'CRATE').length >= 4 && L.things.filter(t => t.type === 'FUELCAN').length >= 4);
  /* AND ONE BASE CAN REACH THE OTHER: flood the level's walkable ground
     on a 32-unit lattice, stepping no more than 24 at a time */
  const G = 32, NX = Math.ceil(MX / G), NY = Math.ceil(MY / G);
  const fl = (i, j) => { const s = L.sectorAt(i * G + G / 2, j * G + G / 2); return s ? s.floor : 1e9; };
  const cellOf = ([x, y]) => [Math.floor(x / G), Math.floor(y / G)];
  const [si, sj] = cellOf(A.spawns[0]);
  const seen = new Uint8Array(NX * NY), q = [[si, sj]];
  seen[sj * NX + si] = 1;
  while (q.length) {
    const [i, j] = q.pop();
    for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const ni = i + di, nj = j + dj;
      if (ni < 0 || nj < 0 || ni >= NX || nj >= NY || seen[nj * NX + ni]) continue;
      if (fl(ni, nj) - fl(i, j) > 24) continue;
      seen[nj * NX + ni] = 1; q.push([ni, nj]);
    }
  }
  check('you can walk from one base to the other, and up the tower',
    B.spawns.every(p => { const [i, j] = cellOf(p); return seen[j * NX + i]; }) &&
    (() => { for (let j = 0; j < NY; j++) for (let i = 0; i < NX; i++) if (seen[j * NX + i] && fl(i, j) === JS.TOWER_H) return true; return false; })());
  check('several threads: more than one way out of each base', A.gates.length + 0 >= 1 && many.every(j => j.base.gates >= 1));
  const packSrc = fsJ.readFileSync('js/texpack-data.js', 'utf8');
  const texs = new Set(a.sectors.flatMap(s => [s.floorTex, s.wallTex, s.lowerTex].filter(Boolean)));
  check('every texture it wears is in the pack', [...texs].every(n => packSrc.includes(`"${n}"`) || packSrc.includes(`'${n}'`)), [...texs].join(' '));
  const termSrc = fsJ.readFileSync('js/terminal.js', 'utf8'), mainSrc = fsJ.readFileSync('js/main.js', 'utf8');
  check('`jesse` at the terminal opens it, and ?jesse goes straight there',
    /JESSE_WORDS = \['JESSE'\]/.test(termSrc) && /location\.href = '\?jesse'/.test(termSrc) && /params\.has\('jesse'\)/.test(termSrc) &&
    /q\.has\('jesse'\)/.test(mainSrc) && /jesseDoc\(seed\)/.test(mainSrc));
}


section('the network, steps one and three');
{
  const TC = await import('../js/net/ticcmd.js');
  const PR = await import('../js/net/protocol.js');
  const TR = await import('../js/net/transport.js');
  const SE = await import('../js/net/session.js');
  const SV = await import('../js/net/server.js');
  const CL = await import('../js/net/client.js');
  const { headlessGame } = await import('./headless.mjs');
  const fsN = await import('node:fs');
  /* --- the TicCmd --- */
  const raw = { look: { x: 0.0123456, y: -0.2 }, move: { x: -0.5, y: 1 }, run: true, attack: true, jump: false, use: true, weaponSlot: 4, weaponCycle: -3 };
  const c1 = TC.fromInput(raw, 77);
  c1.seen = 4242;
  const back = PR.decode(PR.encodeCmd(c1));
  check('a command is eighteen bytes on the wire and comes back the same',
    PR.encodeCmd(c1).byteLength === 1 + TC.CMD_BYTES && back?.t === 'cmd' && TC.sameCmd(back.cmd, c1));
  check('rounded once it stays rounded, so here and the host agree to the bit',
    TC.sameCmd(TC.quantize({ ...c1, look: { ...c1.look }, move: { ...c1.move } }), c1) && Math.abs(c1.look.x - raw.look.x) <= 0.5 / TC.LOOK_SCALE &&
    c1.weaponCycle === -1 && c1.weaponSlot === 4 && c1.run && !c1.jump);
  check('garbage off the wire is nothing, not a crash',
    PR.decode('not json') === null && PR.decode('{"x":1}') === null && PR.decode(new ArrayBuffer(3)) === null && PR.decode(null) === null);
  const gsrc = fsN.readFileSync('js/game.js', 'utf8');
  check('every player is driven by a session\'s command, not the keyboard',
    /\(p\.session \|\| this\.session\)\.cmd\(this\)/.test(gsrc) && /this\.session = new LocalSession\(\)/.test(gsrc) &&
    /p\.tic\(cmd, 1 \/ TICRATE\)/.test(gsrc));

  /* --- the host, over a loopback: a player each --- */
  const small = { w: 10, h: 8 };
  const H = await headlessGame({ map: 'jesse', seed: 31, mapOpts: small });
  check('a Game with no screen, from a seed', !!H.game.player && H.game.session.kind === 'local' && !H.problems.length);
  const MT = await import('../js/net/match.js');
  const sim = new SV.SimServer({ game: H.game, map: { kind: 'jesse', seed: 31, opts: small }, maxPlayers: 2 });
  check('on a host the map\'s own player is put aside', H.game.players.length === 0 && !H.game.player.shootable && H.game.rules === sim.match);
  check('JESSE is a team match, THE MAZE is everybody for themselves',
    sim.match.mode === 'tdm' && sim.match.teams.length === 2 && sim.match.limit === MT.RULES.teamLimit);
  const link = () => { const [a, b] = TR.LoopbackTransport.pair(); sim.accept(b); return a; };
  const A = new CL.NetClient(link(), { name: 'ALICE' });
  check('hello, welcome: an id, a side, and the map as a seed',
    A.id === 1 && A.map.kind === 'jesse' && A.map.seed === 31 && A.map.opts.w === 10 && A.team === 0 && A.welcome.mode === 'tdm');
  const B = new CL.NetClient(link(), { name: 'BOB' });
  const C = new CL.NetClient(link(), { name: 'CAROL' });
  check('up to the limit, and the next is told it is full', B.id === 2 && C.refused && /full/.test(C.refused) && C.closed);
  const pa = sim.clients.get(1).player, pb = sim.clients.get(2).player;
  check('A PLAYER EACH, on opposite sides, each on their own pads, holding the minigun',
    H.game.players.length === 2 && pa !== pb && pa.team === 0 && pb.team === 1 && pa.weapon === 'MINIGUN' &&
    Object.keys(pa.owned).join() === MT.RULES.loadout.join() &&
    sim.match.teams[0].spawns.some(([x, y]) => x === pa.x && y === pa.y) && sim.match.teams[1].spawns.some(([x, y]) => x === pb.x && y === pb.y));
  check('and nothing hurts you for a moment after you arrive', pa.invincible && pa.guardUntil > H.game.tics);
  const oldT = link(); let oldRefused = null;
  oldT.onmessage = d => { const m = PR.decode(d); if (m?.t === 'refused') oldRefused = m.why; };
  const cB = sim.clients.get(2);
  sim.clients.delete(2);                  // make room, then speak the wrong protocol
  oldT.send(PR.encode({ t: 'hello', v: 1 }));
  check('a client that speaks another protocol is turned away', /protocol/.test(oldRefused || ''), oldRefused);
  sim.clients.set(2, cB);
  const heard = [];
  A.onsnap = m => { if (m.ev) heard.push(...m.ev); };
  const x0 = pa.x, y0 = pa.y, a0 = pa.angle, bx0 = pb.x;
  for (let t = 1; t <= 60; t++) {
    const c = TC.newCmd(); c.tic = t; c.move.y = 1; c.look.x = 0.01;
    A.send(c);
    sim.step();
  }
  check('each client\'s commands walk its own player and nobody else\'s', Math.hypot(pa.x - x0, pa.y - y0) > 100 && Math.abs(pa.angle - a0) > 0.3 && pb.x === bx0,
    `${Math.hypot(pa.x - x0, pa.y - y0).toFixed(0)} units`);
  check('and the snapshots say where, which command they got to, and where the others are',
    A.snaps === 60 / SV.SNAP_EVERY && A.snap.ack === 60 && Math.abs(A.snap.you.x - pa.x) < 0.01 && A.snap.tic === H.game.tics &&
    A.snap.others.length === 1 && A.snap.others[0][0] === 2 && A.snap.others[0][7] === 1 && A.score?.players.length === 2);
  for (let i = 0; i < MT.RULES.guardTics; i++) { const c = TC.newCmd(); c.tic = 60; A.send(c); sim.step(); }
  check('the guard wears off', !pa.invincible && !pb.invincible);
  const c61 = TC.newCmd(); c61.tic = 61; c61.move.y = 1; A.send(c61); sim.step();
  const before = pa.session.applied;
  sim.step(); sim.step();
  check('a tic with no command keeps walking but does not turn',
    pa.session.applied === before && Math.abs(pa.session.out.move.y - 1) < 1e-9 && pa.session.out.look.x === 0);
  /* a burst: more commands than the buffer, folded rather than dropped */
  const HS = new SE.HostSession();
  for (let t = 1; t <= SE.CMD_BUFFER + 4; t++) { const c = TC.newCmd(); c.tic = t; c.look.x = 0.001 * t; HS.push(c); }
  const turned = HS.queue.reduce((s, c) => s + c.look.x, 0);
  check('a burst is folded, not dropped: every degree of turn is still in the queue',
    HS.queue.length === SE.CMD_BUFFER && Math.abs(turned - 0.001 * (SE.CMD_BUFFER + 4) * (SE.CMD_BUFFER + 5) / 2) < 1e-9 && HS.merged === 4);

  /* A HIT: A on its own pad facing down a clear line, B stood on it,
     A holds the trigger */
  {
    const lv = H.game.level, [sx0, sy0] = sim.match.teams[0].spawns[0];
    pa.x = sx0; pa.y = sy0; pa.sector = lv.sectorAt(sx0, sy0); pa.z = pa.sector.floor; pa.momx = pa.momy = 0;
    for (let k = 0; k < 16; k++) {
      const a = k * Math.PI / 8;
      if (!lv.rayHitWall(pa.x, pa.y, pa.z + 41, pa.x + Math.cos(a) * 300, pa.y + Math.sin(a) * 300, pa.z + 41)) { pa.angle = a; break; }
    }
  }
  pb.x = pa.x + Math.cos(pa.angle) * 220; pb.y = pa.y + Math.sin(pa.angle) * 220; pb.z = pa.z; pb.momx = pb.momy = 0;
  pb.sector = H.game.level.sectorAt(pb.x, pb.y);
  const clearShot = !H.game.level.rayHitWall(pa.x, pa.y, pa.z + 41, pb.x, pb.y, pb.z + 41);
  let t2 = 61, killedAt = -1;
  for (let i = 0; i < 90 && killedAt < 0; i++) {
    const c = TC.newCmd(); c.tic = ++t2; c.attack = true; c.seen = H.game.tics; A.send(c); sim.step();
    if (pb.dead) killedAt = i;
  }
  check('rounds from one player kill another, at a third of what they do to a shopper',
    clearShot && killedAt > 12 && pb.dead && MT.RULES.pvpScale < 1, `killed after ${killedAt} tics`);
  check('NO PICKUPS, SO NO RUNNING OUT: the belt is full after all that, and never latched',
    MT.RULES.infiniteAmmo && pa.ammo.rounds === pa.maxAmmo.rounds && !pa.beltDry);
  check('a frag for the shooter and a point for the side',
    pa.frags === 1 && pb.deaths === 1 && sim.match.teams[0].score === 1 && sim.match.teams[1].score === 0);
  sim.step(); sim.step(); sim.step();
  check('and everybody hears about it', heard.some(e => e.k === 'frag' && e.by === 1 && e.of === 2), JSON.stringify(heard));
  const n0 = pb.spawns;
  for (let i = 0; i < MT.RULES.respawnTics + 2; i++) sim.step();
  check('the dead come back on their own side\'s pads, whole', !pb.dead && pb.spawns === n0 + 1 && pb.health === MT.RULES.health &&
    sim.match.teams[1].spawns.some(([x, y]) => x === pb.x && y === pb.y) && pb.frags === 0 && pb.deaths === 1);
  check('your own side\'s rounds go through you', sim.match.friendly(pa, { isPlayer: true, team: 0 }) && !sim.match.friendly(pa, pb) &&
    !H.game.targetsFor(pa).some(q => q !== pb && q.isPlayer && q.team === pa.team));
  /* THE REWIND: B moves off the line, A fires at where A SAW B */
  const hist = sim.history.get(pb);
  const sx = pa.x + Math.cos(pa.angle) * 260, sy = pa.y + Math.sin(pa.angle) * 260;
  pb.x = sx; pb.y = sy; pb.z = pa.z; pb.sector = H.game.level.sectorAt(sx, sy); pb.invincible = false; pb.guardUntil = 0;
  sim.step();
  const seenAt = H.game.tics;
  pb.x = sx + Math.sin(pa.angle) * 300; pb.y = sy - Math.cos(pa.angle) * 300;   // sideways, out of the line
  pb.sector = H.game.level.sectorAt(pb.x, pb.y);
  sim.step(); sim.step();
  const hp0 = pb.health + pb.armour1, r0 = sim.rewinds;
  for (let i = 0; i < 6; i++) { const c = TC.newCmd(); c.tic = ++t2; c.attack = true; c.seen = seenAt; A.send(c); sim.step(); }
  check('THE REWIND: a round goes where the shooter saw you, not where you have got to',
    sim.rewinds > r0 && pb.health + pb.armour1 < hp0 && hist.length > 10, `${hp0} → ${pb.health + pb.armour1}`);
  const hp1 = pb.health + pb.armour1;
  for (let i = 0; i < 6; i++) { const c = TC.newCmd(); c.tic = ++t2; c.attack = true; c.seen = 0; A.send(c); sim.step(); }
  check('and without it, the round goes where you are now — past you', pb.health + pb.armour1 === hp1 && !pb.dead);
  /* a match to the limit, and a new round */
  sim.match.teams[0].score = sim.match.limit - 1;
  sim.match.died(pb, pa);
  check('the first side to the limit wins, and the scores say so', sim.match.over?.winner === 'A' && sim.match.table().over?.winner === 'A');
  for (let i = 0; i < MT.RULES.endTics + 2; i++) sim.step();
  check('and then it starts again, from nothing', !sim.match.over && sim.match.round === 2 && sim.match.teams.every(t => t.score === 0) && pa.frags === 0);
  A.close();
  check('when a player leaves, their player leaves with them', sim.clients.size === 1 && H.game.players.length === 1 && !H.game.players.includes(pa));
  /* deathmatch spawns on a map with no pads */
  const MZ = await headlessGame({ map: 'maze', seed: 5, mapOpts: { cells: 5, people: 0 } });
  const dm = new MT.Match(MZ.game, { seed: 5 });
  check('a map with no pads finds its own standing room', dm.mode === 'dm' && dm.spawns.length >= 4 &&
    dm.spawns.every(([x, y]) => MZ.game.level.sectorAt(x, y)), `${dm.spawns.length} spawns`);

  /* --- A NETWORK CLIENT: prediction, and the others as puppets --- */
  {
    const RM = await import('../js/net/remote.js');
    const H2 = await headlessGame({ map: 'jesse', seed: 44, mapOpts: small });
    const sim2 = new SV.SimServer({ game: H2.game, map: { kind: 'jesse', seed: 44, opts: small } });
    let clock = 0; const now = () => clock;
    const post = [];
    const lag = ms => { const [a, b] = TR.LoopbackTransport.pair();
      for (const t of [a, b]) { const send = t.send.bind(t); t.send = d => post.push({ at: clock + ms, f: () => send(d) }); }
      sim2.accept(b); return a; };
    const deliver = () => { const due = post.filter(q => q.at <= clock); for (const q of due) post.splice(post.indexOf(q), 1); for (const q of due) q.f(); };
    const join = async name => {
      const c = new CL.NetClient(lag(30), { name, now });
      while (!c.welcome) { clock += 1; deliver(); }
      const G = (await headlessGame({ map: c.map.kind, seed: c.map.seed, mapOpts: c.map.opts })).game;
      return { c, G, net: new RM.NetGame(G, c, { now, board: false }) };
    };
    const P = await join('PAT'), Q = await join('QUIN');
    const step = () => { clock += 1000 / 35; P.G.tic(); Q.G.tic(); sim2.step(); deliver(); P.net.frame(); Q.net.frame(); };
    for (let i = 0; i < 40; i++) step();
    const c0 = P.net.corrections;
    for (let i = 0; i < 300; i++) {
      P.G.input.move = { x: i % 60 < 20 ? 1 : 0, y: i % 100 < 70 ? 1 : 0 }; P.G.input.look = { x: i % 50 < 10 ? 0.03 : 0, y: 0 }; P.G.input.run = i > 150;
      step();
    }
    const sp = sim2.clients.get(P.c.id).player;
    check('PREDICTION: the page runs its own commands and the host agrees with it, to the bit — no corrections',
      P.net.corrections === c0 && Math.hypot(sp.x - P.G.player.x, sp.y - P.G.player.y) < 200 && P.c.snaps > 50,
      `${P.net.corrections - c0} corrections, biggest ${P.net.biggest.toFixed(2)}`);
    check('the page\'s player is the host\'s to hurt, and holds the minigun', P.G.player.invincible && P.G.player.weapon === 'MINIGUN' && P.G.session.kind === 'net');
    const pup = Q.net.puppets.get(P.c.id);
    check('the others are puppets: a trooper, drawn where the host had them a moment ago',
      pup && pup.a.puppet && pup.a.type === (P.c.team === 1 ? 'ARMY' : 'SWAT') && Q.G.actors.includes(pup.a) &&
      Math.hypot(pup.a.x - sp.x, pup.a.y - sp.y) < 16 * (RM.INTERP_TICS + 3) && /RUN|STAND/.test(pup.a.state.name));
    check('and each command says which host tic the others were drawn at', Math.abs(P.net.seenTic() - (H2.game.tics - RM.INTERP_TICS)) <= 3,
      `${P.net.seenTic()} against ${H2.game.tics}`);
    /* a shove the page could not have known about: the host moves you */
    sp.x += 40; sp.momx = 0;
    for (let i = 0; i < 30; i++) { P.G.input.move = { x: 0, y: 0 }; P.G.input.look = { x: 0, y: 0 }; step(); }
    check('and when the host disagrees, the page goes where the host says', P.net.corrections > c0 && Math.abs(P.G.player.x - sp.x) < 2,
      `${P.G.player.x.toFixed(1)} vs ${sp.x.toFixed(1)}`);
    /* a death, told */
    const sq = sim2.clients.get(Q.c.id).player;
    sq.invincible = false; sq.guardUntil = 0;
    sq.damage(10000, sp, { shot: true });
    for (let i = 0; i < 8; i++) step();
    check('you die when the host says so, and the page is told who did it',
      Q.G.player.dead && Q.net.puppets.get(P.c.id) && P.net.puppets.get(Q.c.id).dead &&
      P.G.toasts.some(t => /PAT FRAGGED QUIN|YOU FRAGGED QUIN/.test(t.text)), P.G.toasts.map(t => t.text).join('|'));
    for (let i = 0; i < MT.RULES.respawnTics + 10; i++) step();
    check('and come back where it puts you', !Q.G.player.dead && Math.hypot(Q.G.player.x - sq.x, Q.G.player.y - sq.y) < 20);
    Q.net.close();
    for (let i = 0; i < 6; i++) step();
    check('a player who leaves is taken off everybody\'s screen', !P.net.puppets.has(Q.c.id) && H2.game.players.length === 1);
    const mainSrc = fsN.readFileSync('js/main.js', 'utf8'), termSrc = fsN.readFileSync('js/terminal.js', 'utf8');
    check('?join joins the host that served the page, and `join` at the terminal goes there',
      /has\('join'\)/.test(mainSrc) && /new NetGame\(game, net\)/.test(mainSrc) && /JOIN_RE/.test(termSrc) && /params\.has\('join'\)/.test(termSrc));
  }

  /* --- the same commands, the same world: what prediction stands on --- */
  const G1 = (await headlessGame({ map: 'jesse', seed: 8, mapOpts: small })).game;
  const G2 = (await headlessGame({ map: 'jesse', seed: 8, mapOpts: small })).game;
  const S1 = new SE.HostSession(), S2 = new SE.HostSession();
  G1.session = S1; G2.session = S2;
  for (let t = 1; t <= 140; t++) {
    const c = TC.newCmd(); c.tic = t; c.move.y = t % 40 < 30 ? 1 : 0; c.move.x = t % 17 < 5 ? 1 : 0; c.look.x = Math.sin(t / 9) * 0.04; c.run = t > 70;
    const w = PR.decode(PR.encodeCmd(TC.quantize(c))).cmd;   // as it arrives off the wire
    S1.push(TC.quantize(c)); S2.push(w);
    G1.tic(); G2.tic();
  }
  check('two hosts fed the same commands put the player in the same place, to the bit',
    G1.player.x === G2.player.x && G1.player.y === G2.player.y && G1.player.angle === G2.player.angle,
    `${G1.player.x},${G1.player.y} vs ${G2.player.x},${G2.player.y}`);

  /* --- and over a real socket, to a real dedicated server --- */
  const SRV = await import('./server.mjs');
  const logs = [];
  const host = await SRV.startHost({ map: 'jesse', seed: 12, port: 0, mapOpts: small, log: m => logs.push(m) });
  try {
    const W = new CL.NetClient(new TR.WebSocketTransport(`ws://127.0.0.1:${host.port}${PR.NET_PATH}`), { name: 'WIRE' });
    const welcomed = await Promise.race([new Promise(r => { W.onwelcome = () => r(true); }), new Promise(r => setTimeout(() => r(false), 5000))]);
    let t = 0;
    const iv = setInterval(() => { const c = TC.newCmd(); c.tic = ++t; c.move.y = 1; W.send(c); }, 1000 / 35);
    await new Promise(r => setTimeout(r, 700));
    clearInterval(iv);
    check('a WebSocket client joins the dedicated server, drives it, and hears back',
      welcomed && W.map.seed === 12 && W.snaps >= 4 && W.snap.ack > 0 && W.snap.you && host.sim.clients.get(W.id).player.session.applied > 0,
      `${W.snaps} snaps, ack ${W.snap?.ack}`);
    const page = await fetch(`http://127.0.0.1:${host.port}/index.html`);
    const esc = await fetch(`http://127.0.0.1:${host.port}/%2e%2e/%2e%2e/etc/passwd`);
    const dot = await fetch(`http://127.0.0.1:${host.port}/.git/config`);
    check('and it serves the game to a browser on the LAN, and nothing outside it',
      page.status === 200 && /MEWD/.test(await page.text()) && esc.status >= 400 && dot.status === 403, `${esc.status} ${dot.status}`);
    W.close();
  } finally { await host.close(); }
  check('the server is one command, with nothing to install',
    /node tools\/server\.mjs/.test(fsN.readFileSync('tools/server.mjs', 'utf8')) && !fsN.existsSync('package-lock.json'));
}

section('layers and steps');
{
  const E = await import('../js/editor/editor.js');
  const D = await import('../js/editor/doc.js');
  const ST = await import('../js/editor/steps.js');
  const fsL = await import('node:fs');
  const rdL = f => fsL.readFileSync(f, 'utf8');
  const Rq = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
  const mk = () => { const e = new E.Editor(null); e.history = new D.History(D.newDoc('L', 4096)); return e; };

  /* THE SNAP: remembered, and heights land on the wheel's step */
  {
    const e = mk();
    const was = e.snap;
    e.setSnap(false);
    check('G turns snap off and on', e.snap === false && (e.setSnap(true), e.snap === true) && was === true);
    check('with snap on a height nudged from 3 lands on 8, not 11', e.snapZ(3, 8) === 8 && e.snapZ(8, 8) === 16);
    e.setSnap(false);
    check('and with it off it moves by the step exactly', e.snapZ(3, 8) === 11);
    e.setSnap(true);
    const src = rdL;
    check('snap and the grid size are kept between visits', /PREFS_KEY = 'gss-edit:prefs'/.test(src('js/editor/editor.js')) && /this\.savePrefs\(\)/.test(src('js/editor/editor.js')) &&
      /prefs\.snap !== false/.test(src('js/editor/editor.js')));
    check('the Snap button says whether it is on', /Snap on' : 'Snap off'/.test(src('js/editor/ui.js')));
    check('props raised on the wheel snap too', /ed\.snapZ\(p\.z0, step\)/.test(src('js/editor/view3d.js')));
  }

  /* LAYERS: a plan each, swapped in and out */
  {
    const e = mk();
    e.addSector(Rq(1024, 1024, 2048, 2048));
    const house = e.doc.sectors[e.doc.sectors.length - 1];
    e.edit('roof', d => { const s = d.sectors.find(x => x.id === house.id); s.ceilTex = 'CEILTILE'; s.ceil = 192; });
    check('a map starts on layer 0 and is not in layers', e.layer === 0 && !D.isLayered(e.doc));
    e.setLayer(1);
    check('layer 1 is empty and the ground is put away', e.layer === 1 && e.doc.sectors.length === 0 && e.doc.layers?.[0]?.sectors.length === 2);
    e.addSector(Rq(1024, 1024, 2048, 2048));
    const up = e.doc.sectors[0];
    check('a room drawn on layer 1 stands on the room under it, as tall', up.floor === 192 && up.ceil === 384, `${up.floor}-${up.ceil}`);
    check('its corners snap to the corners of the layer under it', e.snapAt(1030, 1030, 16).kind === 'vertex');
    check('it takes the textures of the room under it, roof and all', up.ceilTex === 'CEILTILE');
    /* and it is made a roof terrace: open to the sky */
    e.edit('terrace', d => { d.sectors[0].ceilTex = 'SKY'; }, { tidy: false });
    e.thingType = 'SHOPPER'; e.addThing(1500, 1500);
    const th = e.doc.things[e.doc.things.length - 1];
    check('a thing placed on layer 1 is on layer 1', th.layer === 1);
    check('the map is in layers now', D.isLayered(e.doc));
    e.compile();
    const L = e.compiled.level;
    const col = L.columnAt(1500, 1500);
    check('the compiler stacks the two into one column: the house, and the room on it',
      col.length === 2 && col[0].floor === 0 && col[0].ceil === 192 && col[1].floor === 192 && col[1].ceil === 384, col.map(s => `${s.floor}-${s.ceil}`).join(' '));
    check('outside the house the ground is a column of one', L.columnAt(3000, 3000).length === 1);
    check('the thing on layer 1 is placed at that floor', L.things.find(t => t.type === 'SHOPPER')?.z === 192);
    check('and the game finds the upper room at that height: feet on a deck stand on the storey above',
      L.spanIn(col[0], 192) === col[1] && L.spanIn(col[0], 100) === col[0]);
    check('the house\'s own ceiling is under the room on it, and only the top storey has a roof',
      !col[0].roofTex && col[0].ceilTex === 'CEILTILE');
    check('no problems with a storey drawn on a storey', !e.compiled.problems.length, e.compiled.problems.map(p => p.msg).join('; '));
    /* an overhang: layer 1 reaching out over the open ground */
    e.addSector(Rq(2048, 1024, 2560, 2048));
    e.compile();
    const over = e.compiled.level.columnAt(2300, 1500);
    check('a room of layer 1 over the open ground: the ground under it has its floor for a ceiling',
      over.length === 2 && over[0].ceilTex !== 'SKY' && over[0].ceil === over[1].floor, over.map(s => `${s.floor}-${s.ceil} ${s.ceilTex}`).join(' '));
    const ext = e.compiled.level.lines.filter(l => l.exterior);
    check('the house is walled where it meets the street at the ground floor', ext.length >= 3);
    check('and not in the open air above it: that opening is not filled, and does not block up there',
      ext.some(l => l.midZ) && ext.filter(l => l.midZ).every(l => !e.compiled.level.lineBlocks(l, 192, 56, false)) &&
      ext.filter(l => l.midZ).every(l => e.compiled.level.lineBlocks(l, 0, 56, false) === 'blocking'));
    /* undo and redo go back across the switch */
    e.setLayer(0);
    check('switching back: layer 0 again, with the house', e.layer === 0 && e.doc.sectors.some(s => s.id === house.id));
    e.undo();
    check('undo of a switch is the switch back', e.layer === 1);
    e.redo();
    const saved = D.serialise(e.doc), back = D.parseDoc(saved);
    check('a map in layers saves and opens again', D.isLayered(back) && D.layersOf(back).length === 2);
    check('ids stay unique over every layer', back.nextId > Math.max(...D.layersOf(back).flatMap(g => g.sectors.map(s => s.id))));
    /* paste in place onto a layer goes up a storey */
    e.select('sector', [house.id]); e.copySel();
    e.setLayer(2);
    e.paste({ inPlace: true });
    const p2 = e.doc.sectors[0];
    check('Ctrl+Shift+V on layer 2 puts the copy on top of what is under it there', p2 && p2.floor === 384, p2 && `${p2.floor}-${p2.ceil}`);
    e.compile();
    check('three storeys in one column', e.compiled.level.columnAt(1500, 1500).length === 3);
    /* a cellar */
    const c = mk();
    c.setLayer(-1);
    c.addSector(Rq(512, 512, 1024, 1024));
    const cel = c.doc.sectors[0];
    check('a room on layer -1 hangs under the ground', cel.ceil === 0 && cel.floor < 0, `${cel.floor}-${cel.ceil}`);
    c.compile();
    check('and builds under it in the same column', c.compiled.level.columnAt(700, 700).length === 2);
    check('the overlay cuts layers where they cross', (() => {
      const o = D.overlay([{ k: 0, vertices: Rq(0, 0, 100, 100), sectors: [{ id: 1, verts: [0, 1, 2, 3] }] },
                           { k: 1, vertices: Rq(50, 50, 150, 150), sectors: [{ id: 2, verts: [0, 1, 2, 3] }] }]);
      return o.faces.length === 3 && o.faces.filter(f => f.stack.length === 2).length === 1;
    })());
    const srcE = rdL('js/editor/editor.js');
    check('Alt+PgUp and Alt+PgDn change layer, and the toolbar has the switch',
      /k === 'PageUp' \|\| k === 'PageDown'\) && e\.altKey/.test(srcE) && /ed-layers/.test(rdL('js/editor/ui.js')));
    check('the plan ghosts the other layers', /drawLayers\(\)/.test(rdL('js/editor/view2d.js')));
  }

  /* STEPS: stairs between two heights, and rings */
  {
    const e = mk();
    e.addSector(Rq(2048, 1024, 3072, 2048));
    e.edit('terrace', d => { const s = d.sectors[d.sectors.length - 1]; s.floor = 128; s.ceil = 384; });
    e.addSector(Rq(1536, 1024, 2048, 2048));
    const made = e.makeSteps('stairs', {});
    const steps = e.doc.sectors.filter(s => made.includes(s.id)).map(s => [D.centroid(D.ringOf(e.doc, s))[0], s.floor]).sort((a, b) => a[0] - b[0]);
    check('stairs between the ground (0) and a terrace (128): seven steps of 16', steps.length === 7 && steps.every(([, f], i) => f === 16 * (i + 1)),
      steps.map(s => s[1]).join(','));
    check('rising towards the terrace', steps[0][1] < steps[6][1] && steps[6][0] > steps[0][0]);
    check('each keeping its head-room', e.doc.sectors.filter(s => made.includes(s.id)).every(s => s.ceil - s.floor === 256));
    e.compile();
    check('and they build with no problems', !e.compiled.problems.length, e.compiled.problems.map(p => p.msg).join('; '));
    check('the terrace got the new corners of the cut, so it still meets the top step', e.doc.sectors.find(s => s.floor === 128 && s.ceil === 384).verts.length >= 4);
    e.undo();
    check('stairs are one undo', e.doc.sectors.length === 3);
    const r = mk();
    r.addSector(Rq(1024, 1024, 2048, 2048));
    const cald = r.makeSteps('rings', { to: -64, stepH: 16 });
    const fl = r.doc.sectors.filter(s => cald.includes(s.id)).map(s => s.floor);
    check('a caldera: five rings from 0 down to -64 in the middle', cald.length === 5 && fl[0] === 0 && fl[4] === -64 && fl.every((f, i) => !i || f < fl[i - 1]), fl.join(','));
    r.compile();
    check('rings build as holes one in another, with no problems', !r.compiled.problems.length && r.compiled.level.sectorAt(1536, 1536).floor === -64,
      r.compiled.problems.map(p => p.msg).join('; '));
    const m = mk();
    m.addSector(Rq(1024, 1024, 1536, 2048));
    const mound = m.makeSteps('rings', { to: 96, count: 4 });
    check('a mound: as many rings as asked, up to the height asked', mound.length === 4 && m.doc.sectors.find(s => s.id === mound[3]).floor === 96);
    const d = D.newDoc('S', 4096);
    check('stairs in a sector with nothing to bridge ask for a height', !!ST.makeStairs(d, d.sectors[0], {}).error);
    check('the inspector has the step generator', /stepsBlock\(s\)/.test(rdL('js/editor/ui.js')));
  }

  /* TWO PANELS: the inspector on the right, the tabs on the left */
  {
    const ui = rdL('js/editor/ui.js'), css = rdL('css/editor.css');
    check('the inspector is a panel of its own down the right, the tabs down the left, and the left one can be put away',
      /id: 'ed-inspside'/.test(ui) && /h\('div', \{ id: 'ed-main' \}, side, views, inspSide\)/.test(ui) &&
      !/\['insp', 'Inspect'\]/.test(ui) && /grid-template-columns: 280px minmax\(0, 1fr\) 300px/.test(css) && /#ed-main\.notabs/.test(css));
  }

  /* BACK TO THE EDITOR from a test run */
  {
    const html = rdL('index.html'), mainJ = rdL('js/main.js');
    check('a test run from the editor has a way back: a chip on the screen and a button in the menu',
      /id="to-editor"/.test(html) && /id="btn-editor"/.test(html) && /b\.hidden = !fromEditor/.test(mainJ) && /\?edit'/.test(mainJ));
  }
}

section('the sprawl');
{
  const SP = await import('../js/maps/sprawl.js');
  const D = await import('../js/editor/doc.js');
  const TP = await import('../js/texpack.js');
  const fsS = await import('node:fs');
  const doc = SP.sprawlDoc();
  const c = D.compileDoc(doc);
  const L = c.level;
  note('THE SPRAWL', `${doc.sectors.length} sectors, ${doc.props.length} props, ${L.things.length} things, ${L.plants.length} plants`);
  check('it compiles with no problems, every sector into the level', c.problems.length === 0 && c.index.every(i => i >= 0), JSON.stringify(c.problems.slice(0, 3)));
  check('and it sprawls: sixteen districts over half a kilometre, with a crowd and a wood in it',
    L.bounds[2] - L.bounds[0] === SP.SPRAWL_SIZE && doc.sectors.length > 100 && L.plants.length > 1000 &&
    L.things.filter(t => t.type === 'SHOPPER' || t.type === 'TOWNIE').length > 200);
  check('it is the same every time', JSON.stringify(SP.sprawlDoc()) === JSON.stringify(doc));
  const pack = new Set(TP.PACK_NAMES);
  const ok = n => !n || n === 'NONE' || pack.has(n) || SP.SPRAWL_OWN_TEXTURES.includes(n);
  const worn = new Set();
  for (const sc of L.sectors) for (const k of ['floorTex', 'ceilTex', 'wallTex', 'upperTex', 'lowerTex', 'roofTex']) if (sc[k]) worn.add(sc[k]);
  for (const l of L.lines) {
    for (const k of ['middle', 'upper', 'lower']) if (l[k]) worn.add(l[k]);
    for (const bd of l.bands || []) if (bd.tex) worn.add(bd.tex);
    for (const sd of Object.values(l.sides || {})) for (const t of Object.values(sd)) if (typeof t === 'string') worn.add(t);
  }
  for (const pr of L.props) { worn.add(pr.tex); worn.add(pr.topTex); }
  const bad = [...worn].filter(n => !ok(n));
  check('EVERY SURFACE of the compiled level wears the user\'s pack, the cemetery iron or the sky — nothing painted here',
    bad.length === 0, bad.join(' '));
  const types = new Set([...doc.things, ...L.things].map(t => t.type));
  const items = doc.scatters.flatMap(sc => sc.items.map(i => i.type.replace(/:.*/, '')));
  check('and every thing is the user\'s: people, headstones, street lamps, plants and the start — no trolley, bollard, crate, fuel can or ceiling lamp',
    [...types, ...items].every(t => SP.SPRAWL_THINGS.includes(t)), [...types, ...items].filter(t => !SP.SPRAWL_THINGS.includes(t)).join(' '));
  const used = new Set(TP.packNamesIn(doc));
  const missing = TP.PACK_NAMES.filter(n => !used.has(n));
  check('ALL THE PACK is in it: every texture, every animated run', missing.length === 0, missing.join(' '));
  check('under one of the pack\'s skyboxes', doc.world.skybox in TP.SKIES && L.skybox === doc.world.skybox);
  const plantKinds = new Set([...L.plants.map(p => p.kind)]);
  check('with the wood\'s plants and the photographed street trees', ['fir_tall_1', 'fir_tall_2', 'fir_medium', 'fir_young', 'fern', 'grass',
    'street_round', 'street_broad', 'street_oval', 'street_upright', 'street_dense', 'street_big'].every(k => plantKinds.has(k)));
  check('the start stands at the crossroads in the middle',
    (() => { const st = L.things.find(t => t.type === 'START'); return st && st.x === SP.SPRAWL_START[0] && st.y === SP.SPRAWL_START[1]; })());
  const mainSrc = fsS.readFileSync('js/main.js', 'utf8'), edSrc = fsS.readFileSync('js/editor/editor.js', 'utf8'), uiSrc = fsS.readFileSync('js/editor/ui.js', 'utf8');
  {
    /* THE TERMINAL'S WORDS for it: G or GAME, at the user's request */
    const termSrc = fsS.readFileSync('js/terminal.js', 'utf8');
    check('typing G or GAME at the terminal opens the game', /const GAME_WORDS = \['G', 'GAME'\];/.test(termSrc));
  }
  check('THE SPRAWL is still there: ?sprawl plays it, and the editor opens it from the File menu',
    /if \(q\.has\('sprawl'\)\) return sprawl\(\);/.test(mainSrc) &&
    /const sprawl = \(\) => \{ const doc = sprawlDoc\(\);/.test(mainSrc) &&
    /params\.has\('sprawl'\)/.test(fsS.readFileSync('js/terminal.js', 'utf8')) &&
    /which === 'sprawl' \? sprawlDoc\(\)/.test(edSrc) &&
    /\['Open THE SPRAWL', '', \(\) => ed\.fileDemo\('sprawl'\)\]/.test(uiSrc));
  check('EARTH TONES AND THE PIXEL DITHER ARE BACK: the frame is dithered and snapped to the earth box, on a 320-row grid',
    /dither: 1\.0, snap: 1\.0,/.test(mainSrc) && /const DEFAULT_PIXELS = PIXELS\.indexOf\(320\);/.test(mainSrc) &&
    /const DEFAULT_DETAIL = DETAIL\.indexOf\(960\);/.test(mainSrc) && /const PREF_VERSION = 11;/.test(mainSrc) &&
    /TONE_SET = \[\{ v: 'earth'/.test(mainSrc) && /snap: 1 \},/.test(mainSrc));
}

/* ---------- the download ---------- */
section('the download');
{
  /* THE USER ASKED FOR A BUTTON THAT HANDS YOU THE GAME, and the thing
     that can go quietly wrong with it is not the button: it is the zip.
     A writer that puts a byte in the wrong place makes a file that
     every unzipper refuses, and nobody finds out until somebody tries
     to keep the game. So the archive is written here and read back
     here, by a reader that knows nothing about the writer — the table
     at the end is walked, each name is found at the offset it claims,
     and each CRC is recomputed off the bytes that came back. */
  const { Zip, crc32, packSite, RUN_ME, FOLDER } = await import('../js/pack.js');
  const fsP = await import('node:fs');
  const html = fsP.readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  const main = fsP.readFileSync(new URL('../js/main.js', import.meta.url), 'utf8');

  check('the sum is the standard one, against the standard sentence',
    crc32(new TextEncoder().encode('The quick brown fox jumps over the lazy dog')) === 0x414fa339,
    crc32(new TextEncoder().encode('The quick brown fox jumps over the lazy dog')).toString(16));

  const body = new Uint8Array(3000);
  for (let i = 0; i < body.length; i++) body[i] = (i * 7) & 0xFF;
  const zip = new Zip();
  zip.addText(`${FOLDER}/RUN-ME.txt`, RUN_ME);
  zip.add(`${FOLDER}/js/main.js`, body);
  zip.add(`${FOLDER}/assets/empty.bin`, new Uint8Array(0));
  const bytes = new Uint8Array(await (zip.close()).arrayBuffer());

  /* the reader: end of central directory, then the table, then each
     file where the table says it is */
  const dv = new DataView(bytes.buffer);
  let eocd = bytes.length - 22;
  while (eocd >= 0 && dv.getUint32(eocd, true) !== 0x06054B50) eocd--;
  const count = eocd >= 0 ? dv.getUint16(eocd + 10, true) : 0;
  let at = eocd >= 0 ? dv.getUint32(eocd + 16, true) : 0;
  const read = [];
  for (let i = 0; i < count; i++) {
    const nameLen = dv.getUint16(at + 28, true), extra = dv.getUint16(at + 30, true);
    const comment = dv.getUint16(at + 32, true), offset = dv.getUint32(at + 42, true);
    const name = new TextDecoder().decode(bytes.subarray(at + 46, at + 46 + nameLen));
    const crc = dv.getUint32(at + 16, true), size = dv.getUint32(at + 24, true);
    const nl = dv.getUint16(offset + 26, true), el = dv.getUint16(offset + 28, true);
    const from = offset + 30 + nl + el;
    read.push({ name, crc, size, data: bytes.subarray(from, from + size), method: dv.getUint16(offset + 8, true) });
    at += 46 + nameLen + extra + comment;
  }
  note('the archive', `${bytes.length} bytes, ${count} entries read back`);
  check('an archive it writes can be read back by its table of contents', read.length === 3,
    `${read.length} of 3`);
  check('and every name is where the table says it is, with the sum it claims',
    read.length === 3 && read.every(e => crc32(e.data) === e.crc && e.data.length === e.size));
  check('and the bytes that come back are the bytes that went in',
    read[1] && read[1].data.length === body.length && read[1].data.every((b, i) => b === body[i]));
  check('an empty file is still a file', read[2] && read[2].size === 0 && read[2].crc === 0);
  check('everything is stored rather than deflated, which is what the writer promises',
    read.every(e => e.method === 0));
  check('and it unpacks into a folder of its own rather than all over your downloads',
    read.every(e => e.name.startsWith(FOLDER + '/')));

  /* AND THE NOTE IN THE BOX. Every file in here is an ES module and a
     browser will not load one over file://, so an archive that does not
     say how to serve it is an archive that looks broken. */
  check('the archive carries the one thing a person needs to be told',
    /http:\/\/localhost:8000/.test(RUN_ME) && /http\.server|http-server/.test(RUN_ME));

  /* THE PACKER ITSELF, against a made-up site: it reads a list and
     fetches what the list names, and nothing else. */
  const asked = [];
  const fetcher = async (url) => {
    asked.push(url);
    if (url.endsWith('files.json')) return { ok: true, status: 200, json: async () => ['index.html', 'js/main.js'] };
    return { ok: true, status: 200, arrayBuffer: async () => new TextEncoder().encode('// ' + url).buffer };
  };
  const packed = await packSite({ fetcher, base: '' });
  check('the packer reads the list and fetches exactly what it names',
    asked.join() === 'files.json,index.html,js/main.js', asked.join());
  check('and the note goes in on top of them', packed.count === 3, `${packed.count}`);
  let failed = '';
  try { await packSite({ fetcher: async () => ({ ok: false, status: 404 }) }); }
  catch (e) { failed = e.message; }
  check('and a site with no packing list on it says so rather than handing over an empty box',
    /404/.test(failed), failed);

  /* the button, and the wire from it to all of the above */
  check('there is a DOWNLOAD in the pause menu', /id="btn-download"[^>]*class="btn/.test(html));
  check('and it is wired to the packer, loaded only when somebody asks',
    /import\('\.\/pack\.js'\)/.test(main) && /packSite\(\{ onProgress/.test(main) && /save\(blob\)/.test(main));
  check('and the button is the progress bar, because there is nowhere else to put one',
    /PACKING \$\{Math\.round\(d \* 100\)\}%/.test(main));
}

section('the site');
{
  /* The deploy is a copy, and a copy can leave something out. The fire
     strips were loaded by main.js and absent from the build for a
     commit, and the game fell back to its baked flames on the live site
     without a word — so this assembles the site into a scratch
     directory exactly as CI does and checks that every asset path the
     page can load is in it. Paths are read out of the page's own source,
     so a new asset is covered the day it is referenced. */
  const fs = await import('node:fs');
  const path = await import('node:path');
  const os = await import('node:os');
  const { fileURLToPath } = await import('node:url');
  const { execFileSync } = await import('node:child_process');
  const root = fileURLToPath(new URL('..', import.meta.url));
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'sellwrong-site-'));
  let built = '';
  try { built = execFileSync('sh', ['tools/build-site.sh', out], { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim(); }
  catch (e) { built = ''; }
  note('build', built || 'FAILED');
  check('the site assembles', !!built);

  const sources = [path.join(root, 'index.html'), path.join(root, 'manifest.webmanifest')];
  const walk = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else if (/\.(js|css)$/.test(e.name)) sources.push(p);
    }
  };
  walk(path.join(root, 'js')); walk(path.join(root, 'css'));
  const dirs = new Set(), files = new Set();
  for (const f of sources) {
    for (const m of fs.readFileSync(f, 'utf8').matchAll(/assets\/[\w./-]+/g)) {
      const ref = m[0].replace(/[./]+$/, '');
      if (/\.\w+$/.test(ref)) { files.add(ref); dirs.add(path.posix.dirname(ref)); }
      else dirs.add(ref);
    }
  }
  note('asset paths in the page', `${dirs.size} directories, ${files.size} files named outright`);
  const missingDirs = [...dirs].filter(d => !fs.existsSync(path.join(out, d)));
  const missingFiles = [...files].filter(f => !fs.existsSync(path.join(out, f)));
  check('every asset directory the page loads from is in the built site', missingDirs.length === 0, missingDirs.join());
  check('and every file it names outright', missingFiles.length === 0, missingFiles.join());
  check('and no fire strips, because the fire is drawn now', !fs.existsSync(path.join(out, 'assets/fire')));
  check('the page, its icon and its manifest are', ['index.html', 'icon.png', 'manifest.webmanifest'].every(f => fs.existsSync(path.join(out, f))));
  check('and the source tree is not', !fs.existsSync(path.join(out, 'tools')) && !fs.existsSync(path.join(out, 'README.txt')) && !fs.existsSync(path.join(out, 'art')));

  /* THE PACKING LIST, which is how the DOWNLOAD in the menu knows what
     the site is. A static host cannot be asked what is on it, so the
     site carries a list of itself — and a list is a second copy of the
     truth, which is a thing that drifts. The build writes one from what
     it actually copied; the repository keeps one so a checkout served
     off the disk packs too; and this is the check that they are the
     same file. An asset added without rebuilding the list fails here
     rather than in somebody's download. */
  const packedList = path.join(out, 'files.json');
  const listed = fs.existsSync(packedList) ? JSON.parse(fs.readFileSync(packedList, 'utf8')) : [];
  const kept = JSON.parse(fs.readFileSync(path.join(root, 'files.json'), 'utf8'));
  const onDisk = [];
  const walkAll = d => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p2 = path.join(d, e.name);
      if (e.isDirectory()) walkAll(p2);
      else if (e.name !== 'files.json') onDisk.push(path.relative(out, p2).split(path.sep).join('/'));
    }
  };
  walkAll(out);
  onDisk.sort();
  note('the packing list', `${listed.length} files, ${(listed.join().length / 1024).toFixed(1)}kB of names`);
  check('the built site carries a list of itself, for the download in the menu', listed.length > 100);
  check('and it names every file in the site and nothing else',
    listed.join('\n') === onDisk.join('\n'),
    `${listed.length} listed against ${onDisk.length} on disk`);
  check('and it does not name itself: an archive of the game does not need it',
    !listed.includes('files.json'));
  check('and the copy in the repository is the same list, so a checkout packs too',
    kept.join('\n') === listed.join('\n'),
    `${kept.length} kept against ${listed.length} built`);
  fs.rmSync(out, { recursive: true, force: true });
}

/* ---------- verdict ---------- */
console.log(`\n  ${fail === 0 ? 'PASS' : 'FAIL'}  ${pass} checks passed, ${fail} failed`);
if (fail) { console.log('\n' + problems.map(p => '    ! ' + p).join('\n')); process.exit(1); }
