/* =====================================================================
   MEWD — the texture pack
   =====================================================================

   Every other texture in this game is DRAWN, in the page, at start-up
   (js/textures.js). These are not: they are two sets of pictures the
   user handed over — concrete, grass, dirt, cliffs, the ops-room panels,
   the reactor strip, doors, water, an office, backdrops, test tiles —
   and they stay as files in assets/textures (tools/build-texpack.py),
   loaded at run time and put in the same TextureBank under their own
   names, so a map can wear one on any surface exactly as it wears a
   drawn one. A third set came later, from the user's own Godot project
   (github.com/verdictzero/vandre): its biome grounds, the checkered
   sand, snow, meadow, pine litter, savanna, wasteland, farmland, tundra,
   candy and lava, and its city's metal and concrete plates, in the
   groups vandre/terrain and vandre/city (tools/prep-vandre.py).

   THEIR SCALE. The panels, doors and floors are drawn at TWICE Doom's
   resolution: a door is 128 by 256 pixels here where Doom's was 64 by
   128 units, and a floor is 256 square where Doom's flats were 64. So a
   picture from the pack spans HALF its pixel size in world units, which
   puts every door in it at 64 by 128, the size of a Doom door and of
   HOUSDOOR in this game. The exceptions are worn one texel to the unit:
   DR1, which is 64 by 128 already; the test tiles, which say their own
   size on them (64TEST reads "64px"); the DEBUG tiles and the one 64px
   office tile.

   THE ANIMATED ONES are animated Doom's way (ANIMATED in the WAD, the
   animdefs table in p_spec.c): a run of pictures with the same stem,
   each shown for EIGHT TICS of the 35 a second — or its own number of
   them, see ANIMS — round and round for as long as the map is running. And, as in Doom, EVERY picture in a run
   animates, not just the first: a wall that wears DEVPAN1E starts its
   cycle at E, so two walls side by side can be out of step on purpose.
   None of these is a switch — a switch in Doom is a pair that changes
   once, when used, and this pack has none — so every run loops.

     DEVPAN1A-L  the ops panel, its lamp going round the colours
     DEVPAN2A-H  the dial, its ring turning
     DR1_01-12   the small door's eye, cycling
     EYEDOOR0-8  the big door's eye, cycling
     EYEDORC0-4  and the big door's eye pulsing green, which is what it
                 does when it is open — EYEDOORC is the same door held
                 on the one green, and it does not move
     REACTB00-04 the reactor strip, the beam running along it
     WFALLA1-4   the waterfall
     WAT201-224  the water
     TESTPA00-74 the television test card

   Frames are swapped by pointing the bank's own three.js texture at the
   next picture, so every material wearing one follows, in the editor's
   3D view and in the game alike; a texture only goes up to the card when
   something drawn is wearing it, so a run nobody is looking at costs
   nothing.

   THE SKIES. The pack had seven skyboxes, six faces each (one came with
   five, and its sixth is made from the two beside it). The sky in this
   game is a sphere wearing a panorama (js/sky.js), so each box was
   turned into one offline — its four sides joined edge to edge and its
   top and bottom turned till they met them — and they are in
   assets/skies. A map picks one with world.skybox; with none, the sky
   is the painted gradient it always was.
   ===================================================================== */

import * as THREE from 'three';
import { PACK_LIST, PACK_SKIES } from './texpack-data.js';
export { PACK_SKIES };

export const PACK_DIR = 'assets/textures/';
export const SKY_DIR = 'assets/skies/';

/** Every picture in the pack: { name, px: [w, h], w, h (world units),
 *  masked, group }. The list is written by tools/build-texpack.py. */
export const PACK = PACK_LIST.map(([name, pw, ph, k, masked, group]) =>
  ({ name, px: [pw, ph], w: pw * k, h: ph * k, masked: !!masked, group }));
export const PACK_NAMES = PACK.map(p => p.name);
const BY_NAME = new Map(PACK.map(p => [p.name, p]));
/** The groups, in the order the browser shows them. */
export const PACK_GROUPS = [...new Set(PACK.map(p => p.group))].sort();

const run = (stem, n, fmt) => Array.from({ length: n }, (_, i) => stem + fmt(i));
const pad = w => i => String(i).padStart(w, '0');
/** Doom's clock: 35 tics a second. */
export const TICRATE = 35, ANIM_TICS = 8;
/** The runs that animate, first frame to last, by the stem Doom's
 *  ANIMATED would have listed them under, and how many tics each frame
 *  is held for. Eight is Doom's, for every run in the IWADs, and it is
 *  what a run of a dozen frames or fewer gets here. The two long runs
 *  were drawn as MOVING PICTURES, not as Doom's four-frame slime — 24
 *  frames of water, 75 of a television test card — and at eight tics
 *  the water took five and a half seconds to go round and the card
 *  seventeen, so they are held for four and for two, the way a GZDoom
 *  ANIMDEFS gives a run its own speed. */
export const ANIMS = {
  DEVPAN1: { frames: 'ABCDEFGHIJKL'.split('').map(c => 'DEVPAN1' + c), tics: 8 },
  DEVPAN2: { frames: 'ABCDEFGH'.split('').map(c => 'DEVPAN2' + c), tics: 8 },
  DR1:     { frames: run('DR1_', 12, i => pad(2)(i + 1)), tics: 8 },
  EYEDOOR: { frames: run('EYEDOOR', 9, String), tics: 8 },
  EYEDORC: { frames: run('EYEDORC', 5, String), tics: 8 },
  REACTB:  { frames: run('REACTB', 5, pad(2)), tics: 8 },
  WFALLA:  { frames: run('WFALLA', 4, i => String(i + 1)), tics: 8 },
  WAT2:    { frames: run('WAT2', 24, i => pad(2)(i + 1)), tics: 4 },
  TESTPA:  { frames: run('TESTPA', 75, pad(2)), tics: 2 },
};
/* which run a picture is in, and where */
const IN_RUN = new Map();
for (const [stem, a] of Object.entries(ANIMS)) a.frames.forEach((n, i) => IN_RUN.set(n, { stem, run: a.frames, tics: a.tics, i }));
/** The run a texture belongs to, or null. */
export const animOf = name => IN_RUN.get(name) || null;

/** Which picture a texture shows at tic `tic`: its own place in its
 *  run, moved on a frame for every `tics` of them, as Doom's
 *  P_UpdateSpecials does it. */
export function frameAt(name, tic) {
  const a = IN_RUN.get(name);
  if (!a) return name;
  return a.run[(a.i + Math.floor(tic / a.tics)) % a.run.length];
}

/** The skies, by the name a map asks for them by. */
export const SKIES = Object.fromEntries(PACK_SKIES.map(n => [n, SKY_DIR + n + '.png']));

/* ---------------------------------------------------------------------
   loading
   --------------------------------------------------------------------- */
const loadImg = src => new Promise((res, rej) => {
  const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('could not load ' + src)); i.src = src;
});

/**
 * The pack textures a map uses, with every other frame of any run one of
 * them is in, since the wall will show those too. `doc` is anything with
 * the names in it — a document, a level — and a name counts only as a
 * whole string, so CONC_1 is not found inside CONC_10.
 */
export function packNamesIn(doc) {
  const want = new Set();
  JSON.stringify(doc ?? null, (k, v) => {
    if (typeof v === 'string' && BY_NAME.has(v)) want.add(v);
    return v;
  });
  for (const n of [...want]) { const a = IN_RUN.get(n); if (a) a.run.forEach(f => want.add(f)); }
  return [...want];
}

/**
 * Load pictures from the pack into a TextureBank. `names` is which (all
 * of them if left out); any already in the bank are left alone. A picture
 * that does not load is warned about and skipped — a wall wearing it is
 * MISSING's magenta, which is the loud kind of wrong.
 * Returns the names that went in.
 */
export async function loadPack(bank, names = PACK_NAMES, base = '') {
  const todo = names.filter(n => BY_NAME.has(n) && !bank.map.has(n));
  const done = await Promise.all(todo.map(async name => {
    try {
      const img = await loadImg(base + PACK_DIR + name + '.png');
      const c = document.createElement('canvas');
      c.width = img.width; c.height = img.height;
      c.getContext('2d').drawImage(img, 0, 0);
      const p = BY_NAME.get(name);
      const e = bank.add(name, { w: c.width, h: c.height, toCanvas: () => c }, { w: p.w, h: p.h, masked: p.masked });
      /* its own picture, kept: the animation points the texture at other
         frames, and an export wants the one the name means */
      e.own = c;
      return name;
    } catch (err) { console.warn(err.message); return null; }
  }));
  return done.filter(Boolean);
}

/** A texture's own picture: the frame its name means, whatever frame
 *  its animation is showing. */
export const ownImage = e => e?.own || e?.texture?.image || null;

/**
 * THE ANIMATION. One of these per bank; tick it every frame with the
 * seconds gone by. It moves on a frame every eight tics and points each
 * animated texture in the bank at the picture it should be showing.
 */
export class PackAnimator {
  constructor(bank) { this.bank = bank; this.t = 0; this.tic = -1; }
  tick(dt) {
    this.t += dt;
    const tic = Math.floor(this.t * TICRATE);
    if (tic === this.tic) return false;
    this.tic = tic;
    for (const name of IN_RUN.keys()) {
      const e = this.bank.map.get(name);
      if (!e) continue;
      const show = this.bank.map.get(frameAt(name, tic));
      const img = show?.own;
      if (img && e.texture.image !== img) { e.texture.image = img; e.texture.needsUpdate = true; }
    }
    return true;
  }
}

/* ---------------------------------------------------------------------
   the skies
   --------------------------------------------------------------------- */
const skyTex = new Map();
/** A sky from the pack, as a texture the sky sphere and the air can
 *  wear. Null if there is no such sky or it did not load. */
export async function loadSky(name, base = '') {
  if (!SKIES[name]) return null;
  if (!skyTex.has(name)) {
    skyTex.set(name, loadImg(base + SKIES[name]).then(img => {
      const t = new THREE.Texture(img);
      t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter;
      t.generateMipmaps = false;
      t.wrapS = THREE.RepeatWrapping; t.wrapT = THREE.ClampToEdgeWrapping;
      t.colorSpace = THREE.SRGBColorSpace;
      t.name = 'sky-' + name;
      t.needsUpdate = true;
      return t;
    }).catch(err => { console.warn(err.message); return null; }));
  }
  return skyTex.get(name);
}
