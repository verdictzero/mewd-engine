/* =====================================================================
   MEWD — boot
   =====================================================================

   Bake the art, fetch the few things that are files, build the shop
   and the wood round it, wire it up, and hand the frame loop over to
   Game.

   Almost nothing is downloaded. Every texture and sprite of the STORE
   is generated in this process, at start-up, in about half a second.
   What does arrive as files is what was made elsewhere: the staff, the
   trees and their burn maps, the sky, and the gun — and if any of
   those fails to arrive the game runs without it rather than not at
   all, which is why each load is a step of its own with a fallback.

   This file also owns THE PAGE AROUND THE GAME: the title, the pause
   menu, which kind of machine this is and what that changes. The rule
   is that the game never finds out — it reads one Input, and whether
   that Input is a keyboard or two thumbs is settled out here.
   ===================================================================== */

import * as THREE from 'three';
import { LofiPipeline } from './lofi.js';
import { bakeTextures } from './textures.js';
import { bakeSprites, bakeWeapons } from './sprites.js';
import { fireFrames } from './fireart.js';
import { loadVehicleModel, POLICE_LENGTH, APC_LENGTH, FIRE_LENGTH } from './car.js';
import { loadVtolModel } from './vtol.js';
import { addStrip, imageData } from './spriteload.js';
import { CELLS, GIBLETS, BLAST_SPRITE, addStandees, addSplats, addTroops } from './people.js';
/* THE GRID, which the game boots into with ?grid — see js/maps/grid.js.
   Without it the game is THE MAZE (js/maps/maze.js, playedMap below), a
   new one every time; ?sprawl is THE SPRAWL (js/maps/sprawl.js).
   js/maps/sellwrong.js and js/maps/town.js are still in the repository,
   still exported and still tested; nothing builds them any more. */
import { buildGrid } from './maps/grid.js';
import { compileDoc, parseDoc } from './editor/doc.js';
import { sprawlDoc } from './maps/sprawl.js';
import { mazeDoc, newMazeSeed } from './maps/maze.js';
import { jesseDoc, newJesseSeed } from './maps/jesse.js';
import { registerTextures } from './editor/texcompose.js';
import { loadPack, loadSky, packNamesIn, PackAnimator } from './texpack.js';
import { Game } from './game.js';
import { NetClient } from './net/client.js';
import { NetGame } from './net/remote.js';
import { WebSocketTransport } from './net/transport.js';
import { NET_PATH } from './net/protocol.js';
import { Hud } from './hud.js';
import { Audio } from './audio.js';
import { Input } from './input.js';
import { TouchControls } from './touch.js';
import { world, applyMapLight } from './material.js';
import { applySectorGrid } from './sectorgrid.js';
import { atlasTexture, imageTexture } from './particles.js';
import { bakeEffectAtlases } from './effects.js';
import { bakeRainAtlas } from './rain.js';
import { SkyBaker } from './skyart.js';
import { setDisplayPalette, displayName, setArtPalette, artName } from './palette.js';
import { Weather, WEATHERS, WEATHER_ORDER, HOUR_STOPS } from './weather.js';
import { Weapon3D } from './weapon3d.js';
import { Scope } from './scope.js';
import { ThermalScope } from './thermal.js';
import { KINDS } from './forest.js';
import { Music } from './music.js';
import { VERSION } from './version.js';
import { TitleForest, BLUE as TITLE_BLUE } from './titlescene.js';

const $ = id => document.getElementById(id);
/* THE LOADING SCREEN SAYS ONE THING, at the user's request, and it is
   RETICULATING SPLINES for the whole of the half second. The steps
   still move the bar; they no longer say their names. */
const status = (text, pct) => {
  const b = $('load-bar');
  if (b) b.style.width = (pct * 100).toFixed(0) + '%';
};
const failed = text => { const s = $('load-status'); if (s) s.textContent = text; };

/* HOW MUCH THE WORLD IS DRAWN WITH. The vertical resolution of the
   buffer the 3D goes into — width follows the window's shape, so a wider
   monitor shows more store rather than the same store stretched. It
   defaults to the top of the ladder, at the user's request, because the
   pixel filter below is what decides how chunky the picture looks now
   and this one is free to be about detail. It is still the frame rate
   control; halving it quarters the pixels being shaded. */
const DETAIL = [120, 150, 200, 240, 300, 400, 480, 600, 720, 960, 0];
/* THE LAST STEP IS THE WINDOW'S OWN, at the user's request: a fixed
   number of rows upscaled to a modern monitor is not a high resolution,
   it is a low one stretched. 0 means "however many rows are actually on
   the screen", capped at twice the CSS size so a 3x phone does not ask
   for nine times the fill rate. */
const nativeRows = () => Math.round((typeof window === 'undefined' ? 720 : window.innerHeight)
  * Math.min(2, (typeof devicePixelRatio === 'undefined' ? 1 : devicePixelRatio) || 1));
const detailRows = i => DETAIL[i] || nativeRows();
const detailName = i => (DETAIL[i] ? DETAIL[i] + 'P' : 'NATIVE');
/* 960 rows again, at the user's request, now that the picture is held
   to the earth box and dithered once more: the render the 320-row grid
   of 2:3 pixels averages six buffer pixels into each chunky one from */
const DEFAULT_DETAIL = DETAIL.indexOf(960);

/* AND HOW BIG A PIXEL IS, which is a different question and used to be
   the same one. This is the grid the finished frame is filtered down
   onto — each chunky pixel the AVERAGE of the buffer under it, so a
   600-row render at a 200-row grid is a 320x200 picture with every
   square correct to an eighth of itself. It costs almost nothing: the
   filter runs once per chunky pixel, and the palette search that used to
   run once per screen pixel now runs there too.

   OFF is last because it is the finest setting there is — the grid
   becomes the buffer, which is exactly what this game did before the two
   were pulled apart. It is not the default: the default is 320 rows of
   2:3 pixels off a 960-row render, at the user's request (it was 240 of
   5:6 off 720, and before that 200, which is 320x200 at the shape Doom
   was drawn at), off a render fine enough that every one of those
   chunky pixels is the average of six — two columns by three rows. The
   320 took the rung 300 had; a ladder with both is a ladder with a
   step nobody can see. */
const PIXELS = [120, 150, 200, 240, 320, 400, 480, 600, 0];
const PIXELS_OFF = PIXELS.length - 1;
/* 320 rows, at the user's request: the chunky grid is back, with the
   earth tones and the dither (see LofiPipeline below). OFF is still the
   last rung of the ladder in the pause menu. */
const DEFAULT_PIXELS = PIXELS.indexOf(320);

/* THE SHAPE OF ONE, width over height as displayed. 320x200 filling a
   4:3 monitor is not a square-pixel mode and never was: each pixel stood
   five wide to six tall, and every Doom sprite was drawn by somebody
   looking at that. A square-pixel 320x200 is a squashed Doom. The other
   way round is a console's 256x224 on the same screen, which is the same
   trick in the other direction. Nothing in the world moves when this
   changes — the camera reads the BUFFER's shape, and the buffer's pixels
   are always square. */
const PIXEL_ASPECT = [
  { v: 1.0,     n: 'SQUARE' },
  { v: 0.83333, n: 'TALL 5:6' },      // 320x200 on a 4:3 monitor
  /* TWO TO THREE, at the user's request, and the shape the game opens
     with: a pixel half again as tall as it is wide. At 320 rows on a
     16:9 window that is 853 across — two buffer columns by three buffer
     rows to the chunky pixel off the 960-row render, so every one of
     them is the average of six — and 640 across on a 4:3 one. */
  { v: 0.66667, n: 'TALL 2:3' },
  { v: 1.16667, n: 'WIDE 7:6' },      // 256x224 on the same
  /* AND ONE TO THREE, at the user's request: a pixel three times as
     tall as it is wide, which is a 320-row grid seventeen hundred
     across on a 16:9 window — every column of the 960-row buffer, in
     rows a third as fine. lofiSizes clamps the width to the buffer's,
     so on a narrower render the rows give way, as they do for every
     tall setting. */
  { v: 0.33333, n: 'TALL 1:3' },
];
const DEFAULT_PIXAR = 2;               // 2:3, at the user's request; 5:6 is the shape Doom was drawn on

/* ---------------------------------------------------------------------
   WHAT TO SPEND THE FRAME ON

   Three ladders, coarse on purpose — a slider from 0 to 1 invites you to
   fiddle and tells you nothing, and there are only ever two or three
   answers worth having. Each is a multiplier the game reads off
   `game.quality`; the simulation never sees them, so the shop is the
   same shop at every setting and only the drawing is cheaper.

   Which of them to reach for first, measured under a software
   rasteriser, where fill rate and draw calls hurt in the same
   proportions they do on a weak phone:

     RENDER   the biggest lever by a long way. Halving the buffer's
              height quarters the pixels
     THE WOOD next: twenty-eight thousand trees in chunks, and hiding
              the far ones was worth four times the frame rate on its
              own
     CROWD    seven hundred standees are seven hundred draw calls,
              because a billboard the shader turns cannot be batched
     EFFECTS  the fire's sprite pool, sorted nearest-and-hottest first,
              so spending less of it drops the far cold end
   ------------------------------------------------------------------- */
const CROWD  = [{ v: 1, n: 'EVERYONE' }, { v: 0.5, n: 'HALF' }, { v: 0.25, n: 'A FEW' }];
/* WHAT THE SCREEN CAN HOLD. Not a picture setting like the others — it
   costs nothing to draw either way, it is a different game to look at.
   The ART is always the fifteen material ramps; this is the box the
   finished frame is DITHERED DOWN TO. RAMPS is the same box, so the
   snap is the identity; UZEBOX is a real console's hardware limit,
   three bits of red, three of green and two of blue. See the note on
   applyPalette, and js/palette.js. */
const PALETTE_SET = [{ v: 'ramps', n: 'RAMPS' }, { v: 'uzebox', n: 'UZEBOX' }];
/* AND WHAT THE ART IS PAINTED IN, which is the other question and the
   one nothing had asked before. PALETTE above is the box the finished
   frame is snapped DOWN to; this is the box every texture and every
   sprite is DRAWN in, and changing it is a repaint of the game rather
   than a filter over it. AS DRAWN is the fifteen ramps the game was
   made in; EARTH is the same fifteen, muted and warmed — see
   EARTH_RAMPS in js/palette.js and applyTone below.

   EARTH IS FIRST AGAIN, at the user's request: it is the box the art is
   PAINTED in, and it stays that whatever the screen is doing. GRID is
   the green-forward box the field was painted out of while the picture
   was still being snapped to 256 colours — it is not needed now that
   the floor and the wall carry their own RGB (see T.GRID in
   js/textures.js), and it is kept because the low-res look is kept.
   AS DRAWN is the fifteen ramps the game was made in, and is still what
   tools/bake-art.mjs quantises the photographs against, which is a
   different question and is answered where it is asked. */
const TONE_SET = [{ v: 'earth', n: 'EARTH' }, { v: 'stock', n: 'AS DRAWN' }, { v: 'grid', n: 'GRID' }];
const FX     = [{ v: 1, n: 'FULL' }, { v: 0.5, n: 'FEWER' }, { v: 0.25, n: 'LEAST' }];
const WOOD   = [{ v: 1, n: 'ALL OF IT' }, { v: 0.6, n: 'NEARER' }, { v: 0.35, n: 'NEAREST' }];

/* ---- what the player has chosen, remembered ------------------------
   Look speed, inversion, handedness, vibration, chunkiness. Kept in
   localStorage, which may be absent or refused, in which case the game
   simply does not remember and nothing else changes. The version is
   bumped when a default changes, so a saved setting from before does
   not quietly keep the old default alive. */
const PREF_KEY = 'sellwrong.prefs';
/* 4: the defaults moved — 240 rows of pixels, and the picture a third
   brighter — so a saved 200 and a saved 1.0 are not kept alive.
   5: the two debug switches default to on.
   6: the picture moved again — 320 rows of 2:3 pixels off a 960-row
   render — so a saved 240, 5:6 and 720 are not kept alive either.
   8: EARTH is the default tone. A saved `tone` is an INDEX into
   TONE_SET, and TONE_SET was reordered to put the new default first —
   so a saved 0 meant AS DRAWN and now means EARTH, which is the right
   answer for anybody who never touched it and the wrong one for
   anybody who did. Dropped rather than reinterpreted. */
const PREF_VERSION = 11;
const DEFAULT_PREFS = { v: PREF_VERSION, sens: 1, invert: false, lefty: false, haptics: true,
                        detail: DEFAULT_DETAIL, pixels: DEFAULT_PIXELS, pixar: DEFAULT_PIXAR,
                        crowd: 0, fx: 0, wood: 0, fps: false,
                        /* the box of crayons: 0 is RAMPS, which is the game as
                           it was drawn. See PALETTE_SET and applyPalette. */
                        palette: 0,
                        /* and the box it is PAINTED in: 0 is EARTH, at the
                           user's request, whatever the screen is doing.
                           See TONE_SET and applyTone. */
                        tone: 0,
                        /* the night's weather — see js/weather.js; the hour is not
                           kept, because a night starts at two */
                        weather: 0,
                        /* BOTH DEBUG SWITCHES ON BY DEFAULT, at the user's request:
                           infinite ammo and invincibility, until told otherwise
                           from the pause menu, where either can still be turned
                           off and the choice is kept */
                        debug: true, godmode: true,
                        /* AND A THIRD, at the user's request: the haze the fire
                           makes — the smoke sky over the town and the warm fog
                           in the room — on a switch, so what the fire does to
                           the AIR can be taken off without taking the fire off.
                           On, because it is what the game looks like. See
                           Weather.setFireHaze. */
                        haze: true,
                        /* the three picture dials, at the user's request — see
                           LofiPipeline.setPicture; 1 is the picture as drawn */
                        bright: 1.35, contrast: 1, gamma: 1,
                        /* and the music's fader — see js/music.js */
                        music: 0.5 };
function loadPrefs() {
  try {
    const saved = JSON.parse(localStorage.getItem(PREF_KEY) || '{}');
    const was = saved.v | 0;
    if (was !== PREF_VERSION) {
      /* AND ONLY WHAT THAT VERSION MOVED. The reset used to be the same
         four keys whatever the bump was for, so bumping the version to
         say one thing about the tone would also have taken away a
         picture somebody had spent a while dialling in. Each line says
         which version it belongs to, and a bump after this one costs
         nothing that is not actually stale. */
      if (was < 7) { delete saved.detail; delete saved.pixels; delete saved.pixar; delete saved.bright; }
      if (was < 8) delete saved.tone;
      /* and again at 9, when the grid became the world and GRID became
         the box it is painted in: a saved 0 from before meant EARTH */
      if (was < 9) delete saved.tone;
      /* and at 10, when the picture went full colour: EARTH is first
         again, and the render and pixel ladders are not what they were */
      if (was < 10) { delete saved.tone; delete saved.detail; delete saved.pixels; delete saved.pixar; }
      /* and at 11, when the earth tones and the pixel dither came back:
         the saved full-colour picture is not kept alive either */
      if (was < 11) { delete saved.tone; delete saved.detail; delete saved.pixels; delete saved.pixar; }
      saved.v = PREF_VERSION;
    }
    return { ...DEFAULT_PREFS, ...saved };
  } catch (e) { return { ...DEFAULT_PREFS }; }
}
function savePrefs(p) {
  try { localStorage.setItem(PREF_KEY, JSON.stringify(p)); } catch (e) { /* not remembered, that is all */ }
}

/* ---- fullscreen, where the browser allows it ----------------------- */
const fullscreenAllowed = () => !!(document.fullscreenEnabled || document.webkitFullscreenEnabled);
const inFullscreen = () => !!(document.fullscreenElement || document.webkitFullscreenElement);
function enterFullscreen() {
  const el = document.documentElement;
  const req = el.requestFullscreen || el.webkitRequestFullscreen;
  if (!req) return;
  let p;
  try { p = req.call(el, { navigationUI: 'hide' }); } catch (e) { return; }
  if (p && typeof p.then === 'function')
    p.then(() => screen.orientation?.lock?.('landscape')?.catch?.(() => {})).catch(() => {});
}
function exitFullscreen() {
  const ex = document.exitFullscreen || document.webkitExitFullscreen;
  if (!ex) return;
  try { const p = ex.call(document); if (p && p.catch) p.catch(() => {}); } catch (e) { /* nothing to leave */ }
}

/* ---- files ------------------------------------------------------- */
function loadImage(url) {
  return new Promise((resolve, reject) => {
    const im = new Image();
    im.onload = () => resolve(im);
    im.onerror = () => reject(new Error('could not load ' + url));
    im.src = url;
  });
}

/** The wood's pictures: every kind of plant with its burn map, and the
 *  two grounds. All or nothing — a forest with one kind of tree missing
 *  is a forest with holes in it. The vandre biomes' plants (a `set` in
 *  KINDS) are not in that: seventy of them, and a map plants a few if
 *  any, so they come in by loadPlantSets below, for the map played. */
async function loadForestArt() {
  const sprites = {};
  await Promise.all(KINDS.filter(k => !k.set).map(async k => {
    const [albedo, burn] = await Promise.all([loadImage(`assets/forest/${k.name}.png`), loadImage(`assets/forest/${k.name}_burn.png`)]);
    sprites[k.name] = { albedo, burn };
  }));
  const [ground, groundBurnt] = await Promise.all([loadImage('assets/forest/ground.png'), loadImage('assets/forest/ground_burnt.png')]);
  return { sprites, ground, groundBurnt };
}

/** The plants from the vandre sets that `plants` (a level's) names, into
 *  the art the wood is built from. One that does not load is warned
 *  about and left out, and the wood skips a kind with no art. */
async function loadPlantSets(art, plants) {
  const want = new Set((plants || []).map(p => p.kind));
  await Promise.all(KINDS.filter(k => k.set && want.has(k.name) && !art.sprites[k.name]).map(async k => {
    try {
      const [albedo, burn] = await Promise.all([loadImage(`assets/forest/${k.name}.png`), loadImage(`assets/forest/${k.name}_burn.png`)]);
      art.sprites[k.name] = { albedo, burn };
    } catch (e) { console.warn('plant art:', e.message); }
  }));
}

async function boot() {
  const prefs = loadPrefs();
  /* THE TONE GOES ON BEFORE ANYTHING IS PAINTED. It can be changed from
     the pause menu at any time and everything is repainted when it is
     (applyTone), but a game that starts in EARTH should not spend three
     quarters of a second at the loading screen painting itself twice. */
  if (TONE_SET[prefs.tone]?.v !== artName) setArtPalette(TONE_SET[prefs.tone].v);
  let detailIndex = Math.max(0, Math.min(DETAIL.length - 1, prefs.detail | 0));
  let pixelIndex = Math.max(0, Math.min(PIXELS.length - 1, prefs.pixels | 0));
  let pixarIndex = Math.max(0, Math.min(PIXEL_ASPECT.length - 1, prefs.pixar | 0));
  let started = false;

  const container = $('game');
  const renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, powerPreference: 'high-performance' });
  renderer.setPixelRatio(1);              // the pipeline decides the resolution, not the display
  renderer.autoClear = false;
  renderer.setClearColor(0x05060a, 1);
  container.appendChild(renderer.domElement);
  renderer.domElement.id = 'view';

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0a0c14);

  /* Far enough to see across the wood: the forest floor runs sixteen
     thousand units before the sky's own dark ground takes over. */
  const BASE_FOV = 72;
  const camera = new THREE.PerspectiveCamera(BASE_FOV, 1.6, 4, 16000);

  /* yield to the browser between steps so the loading bar can move */
  const breathe = () => new Promise(r => setTimeout(r, 0));

  /* The files start arriving now, behind the baking. */
  const forestArtP = loadForestArt().catch(e => { console.warn('no forest art:', e.message); return null; });
  /* and the crowd: the galvarius project's standees, the pieces they
     come apart into, what is left on the floor and the fireball that
     does it — see js/people.js and tools/prep-people.mjs */
  const peopleP = Promise.all(['shoppers', 'giblets', 'splat', 'blast'].map(k => loadImage(`assets/people/${k}.png`)))
    .catch(e => { console.warn('no people art, using the stand-ins:', e.message); return null; });
  /* and the van in the car park: one model, in every bay, at the user's
     request. There is no preparation step and no tool — the GLB is
     loaded as it was exported and drawn as it is authored; js/car.js is
     the whole of it. The texture comes out of the same file, so there is
     nothing here to keep in step. */
  /* NOBODY DRIVES IN THE TEST AREA, at the user's request, and this is
     the one switch that says so. Every loader below is left exactly as
     it was and every vehicle in js/vehicles.js still works; the grid
     (js/maps/grid.js) has no car park to fill, no road to come up and
     no fire to answer, so fetching ten megabytes of GLB to hand to
     nothing is the load time the user asked to stop paying. Turn this
     over and the fleet, the SWAT, the army, the brigade and the gunship
     are all back. */
  const VEHICLES = false;
  const none = Promise.resolve(null);
  const fleetP = !VEHICLES ? none : loadVehicleModel('assets/models/van.glb')
    .catch(e => { console.warn('no van, the car park stays empty:', e.message); return null; });
  /* and the police van, which comes up the road with the SWAT in it —
     the user's second model, loaded the same way, on its own sheet and
     never in the slab; see SwatVan in js/vehicles.js and POLICE_LENGTH
     in js/car.js for how long it is. Without it nobody comes. */
  const policeP = !VEHICLES ? none : loadVehicleModel('assets/models/police_assault.glb',
      { length: POLICE_LENGTH, id: 'police', name: 'Assault van', use: 'police' })
    .catch(e => { console.warn('no police van, nobody comes:', e.message); return null; });
  /* and the ARMY'S CARRIER, which is the third vehicle and the first
     that does not touch the road: a hover APC, loaded exactly like the
     other two and floated by ArmyApc in js/vehicles.js. Without it the
     army never arrives and the SWAT are the whole night, which is the
     same bargain as above. */
  /* and the FIRE TRUCK, which the fire calls rather than you: the
     police van repainted, with a water cannon on the roof — see
     js/brigade.js. Without it the fire burns until it is done. */
  const fireP = !VEHICLES ? none : loadVehicleModel('assets/models/firetruck.glb',
      { length: FIRE_LENGTH, id: 'firetruck', name: 'Fire truck', use: 'fire', lamp: 'fire' })
    .catch(e => { console.warn('no fire truck, the fire burns:', e.message); return null; });
  const apcP = !VEHICLES ? none : loadVehicleModel('assets/models/apc.glb',
      { length: APC_LENGTH, id: 'apc', name: 'Hover APC', use: 'army' })
    .catch(e => { console.warn('no APC, the army stays home:', e.message); return null; });
  /* and the AIR SUPPORT that comes with it: the user's VTOL gunship,
     the fourth model up the road and the first that never touches it.
     Its own loader, because it is not one mesh but a tree of them —
     see js/vtol.js. Without it the army comes alone. */
  const vtolP = !VEHICLES ? none : loadVtolModel('assets/models/vtol.glb')
    .catch(e => { console.warn('no gunship, the army comes alone:', e.message); return null; });
  /* and the troops themselves: the user's two sheets, cut by
     tools/prep-troops.mjs. Either one missing costs that force its
     faces and nothing else — js/sprites.js has already baked a body of
     the right height under every letter. */
  /* and the troops, who are not coming either — the same switch */
  const troopsP = !VEHICLES ? none : Promise.all(['swat', 'army'].map(k => loadImage(`assets/people/${k}.png`)))
    .catch(e => { console.warn('no troop art, using the stand-ins:', e.message); return null; });
  /* and the music, fetched now and decoded on the start tap, which is
     the first moment a browser lets a page open a speaker — see
     js/music.js. Sixteen megabytes, behind everything else. */
  const music = new Music();
  const musicP = music.load();
  /* and the minigun's three recordings — see SAMPLES in js/audio.js */
  const audio = new Audio();
  audio.loadSamples();

  status('BAKING TEXTURES', 0.05); await breathe();
  const textures = bakeTextures();

  status('BAKING SPRITES', 0.30); await breathe();
  const sprites = bakeSprites();
  let weapons = bakeWeapons();
  const fxAtlases = bakeEffectAtlases();
  const rainAtlas = bakeRainAtlas();
  /* the stream out of the gun is fireballs (bakeEffectAtlases); the
     muzzle, the pilot and the flames on the wood are flame frames */
  const streamAtlas = { texture: fxAtlases.fireball, frames: 8 };

  /* THE PEOPLE ARE NOT DRAWN BY THIS PROGRAM. Every one of them lands on
     top of a stand-in of the same name that sprites.js has already
     baked, so a missing file costs the game its faces and nothing else.
     The pieces stay a picture rather than becoming bank frames: they are
     particles, and a particle wants one atlas, not eleven textures. */
  status('THE CROWD', 0.45); await breathe();
  const peopleImgs = await peopleP;
  const troopImgs = (await troopsP) || [];
  let gibAtlases = null;
  if (peopleImgs) {
    const [, gibletImg] = peopleImgs;
    gibAtlases = {
      giblets: { texture: imageTexture(gibletImg), frames: GIBLETS },
      /* the fire on a piece in the air is the same fireball the gun
         fires, so a burning hand and the stream that lit it are made of
         the same paint */
      trail: { texture: fxAtlases.fireball, frames: 8 },
    };
  }
  /* AND THE PHOTOGRAPHS GO ON LAST — AND GO ON AGAIN. Every one of these
     lands on top of a stand-in of the same name that bakeSprites has
     already drawn, so the ORDER is what makes a face a face. It matters
     twice now: the art palette is a setting, a repaint draws every
     stand-in again (bakeSprites, over the bank it already filled), and
     these have to be laid over the top of them a second time. So it is
     a function, and applyTone calls it. */
  function dressSprites() {
    if (!peopleImgs) return;
    const [shopperImg, , splatImg, blastImg] = peopleImgs;
    const people = addStandees(sprites, imageData(shopperImg));
    const splats = addSplats(sprites, imageData(splatImg));
    const blast = addStrip(sprites, BLAST_SPRITE, imageData(blastImg), CELLS.blast.w, { fullbright: true });
    return `the crowd: ${people} shoppers, ${splats} splats, ${blast} frames of fireball`;
  }
  function dressTroops() {
    const [swatImg, armyImg] = troopImgs;
    const a = swatImg ? addTroops(sprites, imageData(swatImg), 'SWAT') : 0;
    const b = armyImg ? addTroops(sprites, imageData(armyImg), 'ARMY') : 0;
    return `the squad: ${a} cells of SWAT and ${b} of army`;
  }
  { const m = dressSprites(); if (m) console.log(m); console.log(dressTroops()); }

  /* THE FIRE ON THE TREES AND ON THE GUN. The store's three fire sets
     are already in the bank — bakeSprites drew them — and this is the
     same generator asked for one more, as a particle atlas: the flames
     the wood carries, the pilot light and the muzzle flash.

     SQUARE, because Particles draws square quads, and js/fireart.js
     keeps a flame's own proportions inside whatever cell it is given
     rather than filling it. Twenty frames, and they loop. */
  status('THE FIRE', 0.50);
  const flameAtlas = { texture: atlasTexture(fireFrames(64, 64, 20, 11, { taper: 0.7 })), frames: 20 };

  status('THE WOOD', 0.55);
  const forestArt = await forestArtP;
  /* THE SKY IS BAKED, NOT LOADED — js/skyart.js, on the GPU, for the
     hour and the weather, and again as the night goes. It needs the
     palette atlas the post pass builds, so the pipeline comes first. */
  status('THE SKY', 0.62); await breathe();
  /* EARTH TONES AND PIXEL DITHER, at the user's request — back after a
     spell in full colour, which was a SETTING and not a removal, so
     this is four numbers again (js/lofi.js never changed):

       PIXELS 320       the chunky grid, 2:3 pixels, each the average of
                        six buffer pixels
       DITHER 1         the Bayer wobble before the snap, one step of
                        the box's own grid
       SNAP 1           every pixel to the nearest colour in the box —
                        the earth ramps (TONE_SET), so the pack's full-
                        colour textures and skies come out earth too
       RENDER 960       the buffer the grid averages from

     The ladders in the pause menu still reach full colour: PIXELS OFF
     and the render at NATIVE. */
  const pipeline = new LofiPipeline(renderer, {
    height: detailRows(detailIndex),
    pixelHeight: PIXELS[pixelIndex],
    pixelAspect: PIXEL_ASPECT[pixarIndex].v,
    /* EARTH TONES AND THE PIXEL DITHER, BACK, at the user's request:
       the finished frame is Bayer-dithered and snapped to the earth box
       the art is painted in (TONE_SET), pack textures and all */
    dither: 1.0, snap: 1.0,
  });
  /* THE SKY OVER THE GRID: green at the horizon, dark green through the
     middle of it and black overhead, at the user's request — and the
     air fades to a texel of it (js/material.js), so the far edge of the
     field goes to the same green the horizon is rather than to a wall.
     It is FIXED: the clock does not run, because this world has no
     night to get through, and the fire makes no haze, because the haze
     is a lid over a burning town and this is a field with boxes on it.
     Between them they also mean the sky is baked exactly once — see
     SkyBaker.update, which re-bakes for a moved hour or a drifting
     cloud and now has neither. */
  /* A MAP FROM THE EDITOR, if this is a test run of one: MEWD Editor
     (js/editor/editor.js) stores the document and reloads with `?play`,
     and it is compiled here by the same compiler the editor's 3D view
     uses. Anything wrong with it and this is THE SPRAWL, which is also
     what the game plays with no map handed over (see playedMap). */
  /* A MATCH ON THE LAN, if this is ?join: the host is asked first,
     because the host says which world to build (js/net/remote.js) */
  const joining = new URLSearchParams(location.search).has('join');
  const net = joining ? await joinHost() : null;
  const played = net ? netMap(net.map) : playedMap();
  const weather = new Weather({
    hour: 2.0, kind: WEATHER_ORDER[prefs.weather] || 'clear',
    running: false, fireHaze: false,
    sky: { horizon: '#1d9a48', mid: '#06301a', zenith: '#000000', ground: '#05180c',
           /* WHERE THE DARK GREEN SITS, and it is the one number that
              decides whether this reads as a sky or as a green ceiling.
              The ramp runs in the SINE of the elevation, so the power
              moves the middle colour up and down the dome: at 0.62 the
              dark green arrived ten degrees up and the green band the
              user asked for was a line, and at 1.7 the green had the
              first forty degrees and filled the frame. Just under 1
              puts the dark green thirty degrees up — the top of the
              picture when you are looking level — and leaves the rest
              of the sky to the black. */
           midAmt: 1, midPow: 0.95,
           /* an edited map's own colours over those, if this is a test
              run of one (see playedMap) — and whatever it says, the
              rest stays as this world has it: */
           ...(played?.level.sky || {}),
           bare: true,
           /* and the bake is held to the box, like everything else
              again — see uSnapAmt in js/skyart.js */
           snap: 1 },
  });
  const skyBaker = new SkyBaker(renderer, pipeline.lut, { seed: 11 });
  skyBaker.bake(weather.frame);
  world.skyTex.value = skyBaker.texture;
  /* or A SKYBOX FROM THE TEXTURE PACK, if the edited map asks for one:
     the sphere wears it and the air fades to its horizon, and the baker
     goes on baking a sky nobody is shown (js/texpack.js) */
  const skybox = played?.level.skybox ? await loadSky(played.level.skybox) : null;
  if (skybox) world.skyTex.value = skybox;

  status(played ? 'BUILDING THE WORLD' : 'BUILDING THE GRID', 0.68); await breathe();
  const level = played ? played.level : buildGrid();
  /* an edited map's own light colour, ambient light and fog, or none */
  applyMapLight(played ? played.level.mapLight : null);
  /* and its sectors, for the things standing in them (js/sectorgrid.js) */
  applySectorGrid(played ? played.level : null);
  const fleet = await fleetP;
  const police = await policeP;
  const apc = await apcP;
  const firetruck = await fireP;
  const vtol = await vtolP;

  status('THE FLAMETHROWER', 0.78);
  /* THE READOUT'S OWN CANVAS, which is not the renderer's. It sits over
     the frame at the device's own resolution and outside the pixel
     filter entirely — see the top of js/hud.js. The wash and the
     fallback gun stay in the buffer, as an overlay, below. */
  const hud = new Hud(null, $('ui'));
  const input = new Input(renderer.domElement);
  /* AN EDITED MAP'S OWN TEXTURES, drawn and put in the bank before
     anything is built that could wear one — see js/editor/texcompose.js */
  /* and THE TEXTURE PACK's pictures it wears, first — a map texture can
     be made of one — with every frame of any animated run among them */
  const packAnim = new PackAnimator(textures);
  if (played) {
    /* what the document names, and what the compiler filled in for a
       sector that named nothing (DEFAULT_FLOOR in js/editor/doc.js) */
    const want = [...new Set([...packNamesIn(played.doc),
      ...packNamesIn(played.level.sectors.map(s => [s.floorTex, s.ceilTex, s.wallTex]))])];
    if (want.length) { status('LOADING TEXTURES', 0.8); await loadPack(textures, want); }
  }
  if (played?.doc.textures?.length) {
    try { await registerTextures(textures, played.doc.textures, new Set(textures.map.keys())); }
    catch (e) { console.warn('the map\'s own textures did not draw:', e); }
  }
  const game = new Game({ level, scene, camera, textures, sprites, hud, audio, input, sky: skybox || skyBaker.texture,
                         flameAtlas: streamAtlas, bodyAtlas: flameAtlas, fxAtlases, gibAtlases, rainAtlas,
                         fleet, police, apc, firetruck, vtol, weather });
  hud.game = game;
  /* and from here on this page is one player in the host's world */
  if (net) window.NET = new NetGame(game, net);
  /* the decals are boxes drawn against the world's depth, between the
     world and the gun — see js/decals.js */
  pipeline.afterWorld = (r, cam, target) => game.decals.draw(r, cam, target);
  const touch = new TouchControls(input, { root: $('touch'), prefs, onPause: () => pause(true) });

  /* THE SCREEN ON THE BACK OF THE LANCE, and it is given the renderer
     rather than making one: what fills it is another render of the same
     scene from the same eye through a narrower camera, and every
     render() call in this game lives in this file. See js/scope.js. The
     gun is handed the scope so that when the loader meets the model's
     own `dynamic_display_surface_mat` it has something to put there. */
  const scope = new Scope(renderer);
  /* AND THE THERMAL SIGHT ON THE SIDE OF THE QUAD LAUNCHER, which is the
     same kind of thing for the same reason (js/thermal.js) and needs the
     game as well, for what is warm and what the seeker has locked */
  const thermal = new ThermalScope(renderer);
  thermal.game = game;
  const weapon3d = new Weapon3D({ aspect: 1.6, scope, scopes: { LANCE: scope, LAUNCHER: thermal } });
  await weapon3d.load(flameAtlas);
  game.weapon3d = weapon3d.ready ? weapon3d : null;
  hud.showWeaponSprite = !weapon3d.ready;
  console.log('guns: ' + (weapon3d.loaded.join(', ') || 'none'));

  status('PLANTING THE WOOD', 0.88); await breathe();
  if (forestArt) await loadPlantSets(forestArt, level.plants);
  if (forestArt) { game.forest.build(scene, forestArt); game.forest.attachFlames(scene, flameAtlas); }
  console.log(`wood: ${game.forest.treeCount} trees, ${game.forest.plantCount} plants`);

  status('OPENING', 0.95); await breathe();

  function resize() {
    const w = container.clientWidth || window.innerWidth;
    const h = container.clientHeight || window.innerHeight;
    /* AND THE NATIVE STEP FOLLOWS THE WINDOW. Every other step on the
       ladder is a fixed number of rows and a resize does not move it;
       "the window's own" is a number that just changed. */
    if (!DETAIL[detailIndex]) pipeline.setHeight(nativeRows());
    const r = pipeline.resize(w, h);
    camera.aspect = r.width / r.height;
    camera.updateProjectionMatrix();
    weapon3d.setAspect(camera.aspect);
    /* THE HUD'S TWO HALVES TAKE TWO DIFFERENT SIZES, which is the whole
       of what decoupling the readout came to — see the top of js/hud.js.

       The PICTURE half — the wash over a pickup, and the flat gun on the
       day the model does not load — goes into the buffer as an overlay
       and is measured in CHUNKY pixels, not buffer ones: its camera is
       orthographic, so its extents are a unit of measure rather than a
       resolution, and a sprite is the same size on screen at any render
       size. */
    hud.resize(r.gridWidth, r.gridHeight);
    /* The READOUT is measured in the WINDOW's own pixels. It used to be
       laid out in chunky ones too, so turning PIXELS down made the bars
       and the letters GROW — a readout tangled up in how the world is
       drawn. Its canvas is backed at the device's ratio, so the type is
       as sharp as the screen can render it whatever the game is doing. */
    hud.resizeUi(w, h, window.devicePixelRatio || 1);
    /* nothing is drawn along the bottom of the picture any more, so the
       controls sit on the edge */
    $('touch').style.setProperty('--bar', '0px');
    nameInset();
  }
  /* THE PAUSE BUTTON AND THE WEAPON'S NAME SHARE A CORNER on a phone,
     so the name steps left by the button's width. It is the button's
     own size in CSS pixels now, straight across — the readout is laid
     out in the same units the page is, so there is no conversion left
     to get wrong. */
  function nameInset() {
    const on = input.mode === 'touch';
    hud.setNameInset(on ? 60 : 0);
  }
  addEventListener('resize', resize);
  resize();

  /* The car park is outdoors at night and the store has its own lights,
     so the distance falloff has to reach a long way or the far end of
     the shop floor is simply black. */
  world.lightFalloff.value = 3400;
  world.minLight.value = 0.22;      // the fire raises this as the store goes

  status('READY', 1.0);
  const loading = $('loading');
  const title = $('title');
  const pauseEl = $('pause');
  $('version').textContent = 'V' + VERSION;
  loading.classList.add('gone');
  title.classList.remove('gone');

  /* ---- which kind of machine this is, right now -------------------- */
  function applyMode(mode) {
    document.documentElement.classList.toggle('touch', mode === 'touch');
    touch.setEnabled(started && mode === 'touch' && game.state === 'play');
    $('opt-full').hidden = !fullscreenAllowed();
    nameInset();
  }
  input.onModeChange = applyMode;
  applyMode(input.mode);
  /* and a pad taking over from the thumbs, or handing back to them —
     which is not a mode change, only a fade; see Input.padHeld */
  input.onPadChange = on => touch.setPadHeld(on);

  /* ---- the settings -------------------------------------------------
     THE MENU IS TILES NOW, at the user's request: a square with rounded
     corners for every option, three across and two down, four tabbed
     pages of them, and nothing anywhere that scrolls. A tile carries
     its own name, what it is set to, and a mark saying where that sits
     among what it could be — a dot per stop for a list, a bar for a
     number. Tapping it does one of two things:

       A LIST      cycles to the next value and wraps. Three or four
                   stops is short enough to walk round, and a switch is
                   a list of two
       A NUMBER    opens THE WINDOW, which is the one place left in this
                   menu with a slider in it: a dial between two numbers
                   on a tile would be a slider the size of a stamp

     What the page holds and what the code reaches for are two files
     apart, so the smoke test holds them against each other — a typo in
     either leaves a tile that lights up under the thumb and does
     nothing at all. */

  /* THE DIALS, in the order their slots stand in the window: the pref
     this one is, the slider, its readout, and how the number reads. */
  const DIALS = [
    { key: 'sens',     el: 'opt-sens',     v: 'opt-sens-v',     fmt: x => x.toFixed(1) + 'X' },
    { key: 'music',    el: 'opt-music',    v: 'opt-music-v',    fmt: x => Math.round(x * 100) + '%' },
    { key: 'bright',   el: 'opt-bright',   v: 'opt-bright-v',   fmt: x => x.toFixed(2) },
    { key: 'contrast', el: 'opt-contrast', v: 'opt-contrast-v', fmt: x => x.toFixed(2) },
    { key: 'gamma',    el: 'opt-gamma',    v: 'opt-gamma-v',    fmt: x => x.toFixed(2) },
  ];

  /* the face of a tile: the value, and the mark under it — a string is
     written as it stands, a number fills the bar that far along */
  const tileOf = key => document.querySelector(`#pause .tile[data-dial="${key}"]`) || $(key);
  function face(key, value, mark) {
    const t = tileOf(key);
    if (!t) return;
    t.querySelector('.tv').textContent = value;
    const m = t.querySelector('.tm');
    if (!m) return;
    if (typeof mark === 'number') m.firstElementChild.style.width = (Math.max(0, Math.min(1, mark)) * 100).toFixed(1) + '%';
    else if (mark != null) m.textContent = mark;
  }
  /* where a value stands in a list, and how far a slider is along */
  const dots = (i, n) => Array.from({ length: n }, (_, k) => (k === i ? '\u25cf' : '\u25cb')).join(' ');
  const along = el => { const lo = +el.min, hi = +el.max; return hi > lo ? (+el.value - lo) / (hi - lo) : 0; };
  /* THE NIGHT RUNS PAST MIDNIGHT, so the hours are ordered along the
     night rather than round the clock: ten at night is before two in
     the morning. Both the TIME tile's bar and the step it takes read
     the hour through this. */
  const night = h => (h <= 12 ? h + 24 : h);
  const NIGHT_FROM = night(HOUR_STOPS[0]), NIGHT_TO = night(HOUR_STOPS[HOUR_STOPS.length - 1]);

  const setTog = (id, on) => {
    $(id).setAttribute('aria-pressed', on ? 'true' : 'false');
    face(id, on ? 'ON' : 'OFF');
  };
  function syncMenu() {
    for (const d of DIALS) {
      const el = $(d.el);
      el.value = prefs[d.key];
      const text = d.fmt(prefs[d.key]);
      $(d.v).textContent = text;
      face(d.key, text, along(el));
    }
    setTog('opt-invert', prefs.invert);
    setTog('opt-lefty', prefs.lefty);
    setTog('opt-haptic', prefs.haptics);
    /* BOTH SIZES SHOWN IN FULL IN THE WINDOW, because "400P" says
       nothing about how wide it is and the width is where the pixels
       are — and because the grid is clamped to the buffer, so the
       second number is the only place you can see that asking for
       pixels finer than the render did nothing. The tile has room for
       the setting and not for the proof of it. */
    $('opt-res').value = detailIndex;
    $('opt-res-v').textContent = detailName(detailIndex) + '  ' + pipeline.width + '\u00d7' + pipeline.height;
    $('opt-res-down').disabled = detailIndex === 0;
    $('opt-res-up').disabled = detailIndex === DETAIL.length - 1;
    face('res', detailName(detailIndex), detailIndex / (DETAIL.length - 1));
    $('opt-pix').value = pixelIndex;
    $('opt-pix-v').textContent = (PIXELS[pixelIndex] ? PIXELS[pixelIndex] + 'P' : 'OFF') +
      '  ' + pipeline.gridWidth + '\u00d7' + pipeline.gridHeight;
    $('opt-pix-down').disabled = pixelIndex === 0;
    $('opt-pix-up').disabled = pixelIndex === PIXELS.length - 1;
    face('pix', PIXELS[pixelIndex] ? PIXELS[pixelIndex] + 'P' : 'OFF', pixelIndex / (PIXELS.length - 1));
    face('opt-pixar', PIXEL_ASPECT[pixarIndex].n, dots(pixarIndex, PIXEL_ASPECT.length));
    /* WITH NO GRID THERE IS NOTHING FOR AN ASPECT TO BE THE ASPECT OF.
       A tile that is present and inert is worse than one that is
       plainly unavailable, so it greys out and stops taking taps. */
    $('opt-pixar').disabled = !PIXELS[pixelIndex];
    face('opt-crowd', CROWD[prefs.crowd].n, dots(prefs.crowd, CROWD.length));
    face('opt-fx', FX[prefs.fx].n, dots(prefs.fx, FX.length));
    face('opt-wood', WOOD[prefs.wood].n, dots(prefs.wood, WOOD.length));
    face('opt-palette', PALETTE_SET[prefs.palette].n, dots(prefs.palette, PALETTE_SET.length));
    face('opt-tone', TONE_SET[prefs.tone].n, dots(prefs.tone, TONE_SET.length));
    face('opt-time', game.weather.label,
      (night(game.weather.hour) - NIGHT_FROM) / (NIGHT_TO - NIGHT_FROM));
    face('opt-weather', WEATHERS[WEATHER_ORDER[prefs.weather]].name, dots(prefs.weather, WEATHER_ORDER.length));
    setTog('opt-fps', prefs.fps);
    setTog('opt-debug', prefs.debug);
    setTog('opt-godmode', prefs.godmode);
    setTog('opt-haze', prefs.haze);
    face('opt-full', inFullscreen() ? 'ON' : 'OFF');
  }
  function applyPrefs() {
    input.sensitivity = 0.0022 * prefs.sens;    // the mouse and the thumb share one dial
    input.invertY = !!prefs.invert;
    touch.applyPrefs();
    pipeline.setPicture({ brightness: prefs.bright, contrast: prefs.contrast, gamma: prefs.gamma });
    music.setVolume(prefs.music);
    /* the three dials, straight onto the game — see game.quality */
    game.quality.crowd = CROWD[prefs.crowd].v;
    game.quality.effects = FX[prefs.fx].v;
    game.quality.wood = WOOD[prefs.wood].v;
    game.weather.setKind(WEATHER_ORDER[prefs.weather]);
    $('fps').hidden = !prefs.fps;
    /* and the two that are not picture settings: see Player.fuelTic and
       Player.damage, which are one branch each */
    game.player.debug = !!prefs.debug;
    game.player.invincible = !!prefs.godmode;
    game.weather.setFireHaze(!!prefs.haze);
    savePrefs(prefs);
    syncMenu();
  }

  /* ---- the pages ----------------------------------------------------
     Four of them, tabbed. The tiles are the same size on every page, so
     the only thing a tab changes is which six are under your thumb. */
  const tabs = [...document.querySelectorAll('#pause .tab')];
  const pages = [...document.querySelectorAll('#pause .tiles')];
  function showPage(n) {
    const want = String(n);
    for (const t of tabs) {
      const on = t.dataset.page === want;
      t.classList.toggle('on', on);
      t.setAttribute('aria-selected', on ? 'true' : 'false');
    }
    for (const p of pages) p.hidden = p.dataset.page !== want;
  }
  const pageStep = d => {
    const i = Math.max(0, tabs.findIndex(t => t.classList.contains('on')));
    showPage(tabs[(i + d + tabs.length) % tabs.length].dataset.page);
  };
  for (const t of tabs) t.addEventListener('click', () => showPage(t.dataset.page));
  showPage(1);

  /* ---- the window a dial opens --------------------------------------
     One window, one slot shown in it at a time, and the slot is the
     slider that has always been there — moved off the face of the menu
     and into a box big enough to aim at. */
  const dialEl = $('dial');
  const slots = [...document.querySelectorAll('#dial .slot')];
  let openDial = '';
  function showDial(key, name) {
    openDial = key;
    $('dial-name').textContent = name;
    for (const s of slots) s.hidden = s.dataset.dial !== key;
    dialEl.classList.remove('gone');
  }
  function closeDial() {
    openDial = '';
    dialEl.classList.add('gone');
  }
  const dialSlider = () => (openDial ? $('dial').querySelector(`.slot[data-dial="${openDial}"] input`) : null);
  const nudge = (el, d) => {
    if (!el) return;
    if (d < 0) el.stepDown(); else el.stepUp();
    el.dispatchEvent(new Event('input'));
  };
  for (const t of document.querySelectorAll('#pause .tile[data-dial]'))
    t.addEventListener('click', () => showDial(t.dataset.dial, t.querySelector('.tn').textContent));
  $('dial-done').addEventListener('click', closeDial);
  /* the dark round the box is a way out of it, the way a window's is */
  dialEl.addEventListener('click', e => { if (e.target === dialEl) closeDial(); });
  /* the nudge either side of a slider, for the step a thumb cannot hit.
     The two ladders have their own, because a rung is not a step of a
     number — see below. */
  for (const s of slots) {
    const el = s.querySelector('input');
    for (const b of s.querySelectorAll('.nudge[data-nudge]'))
      b.addEventListener('click', () => nudge(el, +b.dataset.nudge));
  }

  $('opt-res').max = DETAIL.length - 1;
  $('opt-pix').max = PIXELS.length - 1;
  applyPrefs();
  for (const d of DIALS) {
    const el = $(d.el);
    el.addEventListener('input', () => {
      const x = parseFloat(el.value);
      prefs[d.key] = Number.isFinite(x) ? x : DEFAULT_PREFS[d.key];
      applyPrefs();
    });
  }
  const toggle = (id, key) => $(id).addEventListener('click', () => { prefs[key] = !prefs[key]; applyPrefs(); });
  toggle('opt-invert', 'invert');
  toggle('opt-lefty', 'lefty');
  toggle('opt-haptic', 'haptics');
  /* THE TWO LADDERS ARE RUNGS, so their sliders count in whole steps
     and the readout is the rung's name rather than its number. The
     minus and plus either side are the steppers this menu used to wear
     on its face: a cycling button is fine for three states and wrong
     for nine — you should not have to go all the way round to go back
     one. */
  $('opt-res').addEventListener('input', () => setDetail(+$('opt-res').value));
  $('opt-pix').addEventListener('input', () => setPixels(+$('opt-pix').value));
  $('opt-res-down').addEventListener('click', () => setDetail(detailIndex - 1));
  $('opt-res-up').addEventListener('click', () => setDetail(detailIndex + 1));
  $('opt-pix-down').addEventListener('click', () => setPixels(pixelIndex - 1));
  $('opt-pix-up').addEventListener('click', () => setPixels(pixelIndex + 1));
  /* THE LISTS WRAP, because three or four stops is short enough to walk
     round, and the dots on the tile say how far round you are. */
  const ladder = (id, key, list, after) => $(id).addEventListener('click', () => {
    prefs[key] = (prefs[key] + 1) % list.length;
    if (after) after();                 // the ones that resize the picture
    applyPrefs();
  });
  ladder('opt-pixar', 'pixar', PIXEL_ASPECT, () => {
    pixarIndex = prefs.pixar;
    pipeline.setPixelAspect(PIXEL_ASPECT[pixarIndex].v);
    resize();
  });
  ladder('opt-crowd', 'crowd', CROWD);
  ladder('opt-fx', 'fx', FX);
  ladder('opt-wood', 'wood', WOOD);
  /* the one setting that re-bakes the art: about three quarters of a
     second, once, on a button nobody presses in a firefight */
  ladder('opt-palette', 'palette', PALETTE_SET, () => applyPalette(PALETTE_SET[prefs.palette].v));
  /* and the one that repaints the art: about a second, once, and the
     way back is the same button again */
  ladder('opt-tone', 'tone', TONE_SET, () => applyTone(TONE_SET[prefs.tone].v));
  ladder('opt-weather', 'weather', WEATHER_ORDER);
  /* THE HOUR IS NOT A PREFERENCE, it is where the night has got to; the
     tile steps it to the next keyframe, for looking at the dawn without
     waiting nine minutes for it */
  $('opt-time').addEventListener('click', () => {
    const next = HOUR_STOPS.find(x => night(x) > night(game.weather.hour) + 0.01) ?? HOUR_STOPS[0];
    game.weather.setHour(next);
    syncMenu();
  });
  toggle('opt-fps', 'fps');
  toggle('opt-debug', 'debug');
  toggle('opt-godmode', 'godmode');
  toggle('opt-haze', 'haze');
  $('opt-full').addEventListener('click', () => (inFullscreen() ? exitFullscreen() : enterFullscreen()));
  document.addEventListener('fullscreenchange', syncMenu);
  document.addEventListener('webkitfullscreenchange', syncMenu);

  /* ---- pause --------------------------------------------------------- */
  function pause(on) {
    if (!started || game.state !== 'play') return;
    game.setPaused(on);
  }
  game.onPauseChange = on => {
    pauseEl.classList.toggle('gone', !on);
    $('touch').classList.toggle('paused', on);
    /* the window is part of the menu: it goes when the menu goes, or it
       is still standing there over the game the next time you pause */
    if (!on) closeDial();
    if (on) { touch.releaseAll(); input.exitLock(); syncMenu(); }
  };
  $('btn-resume').addEventListener('click', () => {
    pause(false);
    audio.resume();
    if (input.mode === 'desktop') input.requestLock();
  });
  /* BACK TO THE EDITOR, on a test run from its Play button: the menu's
     button and the chip at the top of the screen. The map is the
     editor's autosave, so it opens on exactly what was played. */
  const fromEditor = new URLSearchParams(location.search).has('play');
  const toEditor = () => { location.href = location.pathname + '?edit'; };
  for (const id of ['btn-editor', 'to-editor']) {
    const b = $(id);
    if (!b) continue;
    b.hidden = !fromEditor;
    b.addEventListener('click', e => { e.stopPropagation(); toEditor(); });
  }
  const restartBtn = $('btn-restart');
  let restartArmed = 0;
  restartBtn.addEventListener('click', () => {
    if (restartBtn.classList.contains('armed')) { location.reload(); return; }
    restartBtn.classList.add('armed');
    restartBtn.textContent = 'SURE? TAP AGAIN';
    clearTimeout(restartArmed);
    restartArmed = setTimeout(() => { restartBtn.classList.remove('armed'); restartBtn.textContent = 'RESTART'; }, 3000);
  });
  /* ---- the download -------------------------------------------------
     AT THE USER'S REQUEST: a button in the menu that hands you the
     whole site as one file, to keep and to run on your own machine.

     The zip is written in the page, by js/pack.js, out of the files
     the browser already has — so the work is a pass over the cache
     rather than a second download of sixty megabytes, and the module
     that does it is not loaded at all until somebody asks. The button
     is the progress bar: there is nowhere else in this menu to put one
     and a percentage in the thing you pressed is where you are already
     looking. */
  const dlBtn = $('btn-download');
  let packing = false;
  dlBtn.addEventListener('click', async () => {
    if (packing) return;
    packing = true;
    dlBtn.classList.add('busy');
    const say = t => { dlBtn.textContent = t; };
    say('PACKING 0%');
    try {
      const { packSite, save } = await import('./pack.js');
      const { blob } = await packSite({ onProgress: d => say(`PACKING ${Math.round(d * 100)}%`) });
      save(blob);
      say(`SAVED ${Math.round(blob.size / 1048576)}MB`);
    } catch (e) {
      /* the one way this fails on a served site is a packing list that
         is not there — a checkout with no files.json in it */
      console.warn('[pack]', e);
      say('CANNOT PACK');
    }
    setTimeout(() => { say('DOWNLOAD'); dlBtn.classList.remove('busy'); packing = false; }, 5000);
  });

  document.addEventListener('pointerlockchange', () => {
    if (started && input.mode === 'desktop' && !document.pointerLockElement && !game.paused) pause(true);
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) pause(true); });

  /* a hit you can feel — the phone has no other way to tell you */
  game.onPlayerHurt = amount => {
    if (prefs.haptics && input.mode === 'touch' && navigator.vibrate)
      navigator.vibrate(Math.min(60, 12 + amount * 2));
  };

  game.onStateChange = () => {
    touch.setEnabled(false);
    setTimeout(() => addEventListener('pointerdown', () => location.reload(), { once: true }), 1500);
  };

  /* ---- start ------------------------------------------------------- */
  function start() {
    if (started) return;
    started = true;
    game.idle = false;
    title.classList.add('gone');
    audio.resume();
    audio.startAmbience();
    /* the music starts on the tap, which is the gesture the browser
       wants; if the files are still arriving it starts when they have */
    musicP.then(() => music.start());
    if (input.mode === 'touch') { enterFullscreen(); touch.setEnabled(true); }
    else input.requestLock();
    input.keys.clear();
  }
  /* THE MAIN MENU, Doom's: up and down walk the marker, enter or a
     click takes the one it is on. Only NEW GAME goes anywhere yet; the
     others shake their heads. */
  const menuItems = [...document.querySelectorAll('#main-menu .mm')];
  let menuAt = 0;
  const menuMark = i => {
    menuAt = (i + menuItems.length) % menuItems.length;
    menuItems.forEach((b, j) => b.classList.toggle('on', j === menuAt));
  };
  const menuTake = i => {
    menuMark(i);
    const b = menuItems[menuAt];
    if (b.getAttribute('aria-disabled') === 'true') {
      b.classList.remove('nope'); void b.offsetWidth; b.classList.add('nope');
      audio.resume();
      return;
    }
    if (b.dataset.act === 'new') start();
  };
  menuItems.forEach((b, i) => {
    b.addEventListener('pointerenter', () => menuMark(i));
    b.addEventListener('click', e => { e.stopPropagation(); menuTake(i); });
  });
  addEventListener('keydown', e => {
    if (!started) {
      if (e.code === 'ArrowUp' || e.code === 'KeyW') { e.preventDefault(); menuMark(menuAt - 1); return; }
      if (e.code === 'ArrowDown' || e.code === 'KeyS') { e.preventDefault(); menuMark(menuAt + 1); return; }
      if (e.code === 'Space' || e.code === 'Enter') { e.preventDefault(); menuTake(menuAt); return; }
    }
    /* THE MENU ON A KEYBOARD. The arrows turn the page, or move the
       slider when a window is open; escape shuts the window rather than
       the menu, and the key is taken off the input on the way past so
       the pause switch downstream never sees it — Input latches a press
       so a tap shorter than a tic still counts, which is the same
       latch. One escape closes the window, the next unpauses. */
    if (game.paused) {
      if (e.code === 'Escape' && openDial) {
        closeDial();
        input.keys.delete('pause'); input.latch.delete('pause');
        return;
      }
      if (e.code === 'ArrowLeft') { openDial ? nudge(dialSlider(), -1) : pageStep(-1); return; }
      if (e.code === 'ArrowRight') { openDial ? nudge(dialSlider(), 1) : pageStep(1); return; }
    }
    if (started && game.state !== 'play' && e.code === 'Space') location.reload();
    /* SHIFT MOVES THE OTHER ONE. Two brackets for two sizes: the picture
       on its own, and the pixels it is made of with shift held. */
    if (e.code === 'BracketLeft') e.shiftKey ? setPixels(pixelIndex - 1) : setDetail(detailIndex - 1);
    if (e.code === 'BracketRight') e.shiftKey ? setPixels(pixelIndex + 1) : setDetail(detailIndex + 1);
    if (e.code === 'KeyN') {                       // palette off, for comparison
      const u = pipeline.material.uniforms.uSnap;
      u.value = u.value > 0.5 ? 0 : 1;
    }
    if (e.code === 'Backquote') { prefs.fps = !prefs.fps; applyPrefs(); }
    /* BACK TO THE EDITOR, from a test run or from anywhere */
    if (e.code === 'F2') { e.preventDefault(); location.href = location.pathname + '?edit'; }
  });
  renderer.domElement.addEventListener('mousedown', () => { if (started) audio.resume(); });

  function setDetail(i) {
    detailIndex = Math.max(0, Math.min(DETAIL.length - 1, i));
    pipeline.setHeight(detailRows(detailIndex));
    resize();
    prefs.detail = detailIndex;
    savePrefs(prefs);
    syncMenu();
  }

  function setPixels(i) {
    pixelIndex = Math.max(0, Math.min(PIXELS.length - 1, i));
    pipeline.setPixels(PIXELS[pixelIndex]);
    resize();
    prefs.pixels = pixelIndex;
    savePrefs(prefs);
    syncMenu();
  }

  /* ---- the loop ---------------------------------------------------- */
  const overlays = [
    { scene: weapon3d.scene, camera: weapon3d.camera, visible: false },
    { scene: hud.scene, camera: hud.camera, visible: false },
  ];
  let last = performance.now();
  let fpsAccum = 0, fpsFrames = 0;
  game.idle = true;
  /* THE TITLE'S OWN LEVEL, at the user's request: a forest going by
     sideways for ever (js/titlescene.js). Until its pictures are in, the
     title stands on the game's map as it used to; once NEW GAME is
     taken it is thrown away. */
  let titleForest = new TitleForest();
  titleForest.load().catch(e => { console.warn('title forest', e); titleForest = null; });
  /* MEWD itself is the page's, in front of the dither, at the user's
     request; its shadows go INTO the picture, under the dither, laid
     over the page logo's box every frame (see TitleForest.loadLogo). */
  const titleLogo = title.querySelector('.logo-slot.big .logo');
  const logoReady = titleLogo.complete ? Promise.resolve() : new Promise(ok => titleLogo.addEventListener('load', ok, { once: true }));
  logoReady.then(() => titleForest?.loadLogo(titleLogo.currentSrc || titleLogo.src))
    .catch(e => console.warn('title logo', e));
  function frame(now) {
    requestAnimationFrame(frame);
    const dt = Math.min(0.25, (now - last) / 1000);
    last = now;

    if (started) game.update(dt);
    /* the pack's animated textures, at Doom's eight tics a frame */
    if (started) packAnim.tick(dt);
    music.tick();
    /* HOW BIG A PIXEL IS THIS FRAME, for the geometry LOD — see
       minSolidFor in js/mapgeo.js. The GRID and not the buffer: the
       world is drawn at `height` rows and then resolved onto a grid of
       `gridHeight` chunky ones, and what you can make out is a grid
       pixel. With the pixel dial off the grid IS the buffer, and the
       LOD goes back to dropping almost nothing, which is right. */
    game.viewRows = pipeline.gridHeight;
    const p = game.player;
    /* ---- THE SCOPE, WHICH IS A SETTING AND THEN A RENDER -------------
       The zoom is a press, and it does two things: it steps the gun's
       own magnification, and it narrows the WORLD camera with it, which
       is what makes holding a scope feel different from looking at one.
       The look sensitivity comes down by the same factor, so a zoomed
       sweep is as fine as the picture it is moving. See VIEW_ZOOM in
       js/scope.js for why the two numbers are not the same number. */
    /* TWO GUNS HAVE ONE NOW — the lance's screen and the launcher's
       thermal sight — and they are the same kind of thing: whichever is
       in hand takes the zoom, the other is put down and zeroed. */
    if (started) {
      const lance = p.weapon === 'LANCE' && !p.dead;
      const launcher = p.weapon === 'LAUNCHER' && !p.dead;
      scope.held = lance && weapon3d.ready;
      thermal.held = launcher && weapon3d.ready;
      /* taken every frame, whatever is in hand, so a press made while
         holding something else is not waiting to go off when the scope
         comes out — see Input.takeScope */
      const press = input.takeScope();
      if (!lance && scope.zoomIndex) scope.setZoom(0);
      else if (lance) scope.work(press);
      if (!launcher && thermal.zoomIndex) thermal.setZoom(0);
      else if (launcher) thermal.work(press);
      /* once, not every frame: the stage marks are a constant of the
         weapon and the getter that hands them over allocates */
      if (!scope.stageMarks) scope.setStages(p.stageMarks);
      const sighted = lance ? scope : launcher ? thermal : null;
      const want = BASE_FOV * (sighted ? sighted.viewScale : 1);
      if (Math.abs(camera.fov - want) > 0.01) { camera.fov = want; camera.updateProjectionMatrix(); }
      input.zoomScale = sighted ? sighted.viewScale : 1;
      /* and the phone gets two buttons for it, only while a gun with a
         screen is in hand — see TouchControls.setScope */
      touch.setScope(!!sighted && input.mode === 'touch', (sighted || scope).magnification + '\u00d7',
                     !!sighted && sighted.zoomed);
    } else {
      scope.held = false; scope.setZoom(0);
      thermal.held = false; thermal.setZoom(0);
      input.takeScope();
      touch.setScope(false);
    }
    game.render(now);
    /* the sky, again, when the hour or the cloud has moved enough */
    skyBaker.update(game.weather.frame, now / 1000);
    if (started) weapon3d.update(p, p.firing, game.tics, dt);
    /* THE READOUT DRAWS ITSELF, ON ITS OWN CANVAS, and only when
       something on it has moved; with no game running there is nothing
       to read, so the canvas is wiped and the title has a clean picture
       behind it. The overlay below is the other half of js/hud.js — the
       wash and the fallback gun — which still goes into the buffer. */
    if (started) hud.update(p, weapons); else hud.clear();
    /* AND THE GUN'S OWN SCREEN, which is the other readout in this game
       and the only one drawn from inside the world. The feed goes first
       because it is a render of `scene` and the pipeline below is about
       to take the render target away; the gauges after it, because they
       are a canvas and cost nothing when nothing on them has moved. */
    scope.render(scene, camera);
    thermal.render(scene, camera);
    if (started) { scope.update(p, game.tics); thermal.update(p, game.tics); }
    overlays[0].visible = started && weapon3d.ready && !p.dead;
    overlays[1].visible = started;
    if (started && titleForest) { titleForest.dispose(); titleForest = null; }
    if (!started && titleForest?.ready) {
      titleForest.update(dt, camera.aspect, now);
      if (titleForest.overlay) titleForest.placeLogo(titleLogo.getBoundingClientRect(), container.getBoundingClientRect());
      title.classList.toggle('live', !!titleForest.overlay?.visible);
      const after = pipeline.afterWorld;
      pipeline.afterWorld = null;            // the game's decals are not in this world
      pipeline.tint.setRGB(...TITLE_BLUE);
      pipeline.render(titleForest.scene, titleForest.camera, [titleForest.overlay]);
      pipeline.tint.setRGB(1, 1, 1);
      pipeline.afterWorld = after;
    } else pipeline.render(scene, camera, overlays);

    fpsAccum += dt; fpsFrames++;
    if (fpsAccum > 0.5) {
      const el = $('fps');
      /* AND WHAT THE FRAME IS ACTUALLY SPENT ON, since the readout is a
         setting now rather than a debug key: the buffer's size, how many
         of the crowd got drawn against how many there are, and the two
         fires. `draws` is what the renderer issued last frame, which is
         the number the culling in Actor.render exists to move. */
      if (el && prefs.fps) {
        let drawn = 0, live = 0;
        for (const a of game.actors) {
          if (a.removed || !a.state) continue;
          live++; if (a.drawn) drawn++;
        }
        el.textContent = `${Math.round(fpsFrames / fpsAccum)} FPS  ${pipeline.width}x${pipeline.height}  ` +
          `${pipeline.sceneCalls ?? 0} draws  ${drawn}/${live} things  ` +
          `${game.fire.burningCells} alight  ${game.forest.burningCells} wood  ` +
          `${game.flame.liveCount + game.fx.liveCount} particles  ` +
          `${game.weather.label} ${game.weather.shownKind} ${skyBaker.bakes} bakes`;
      }
      fpsAccum = 0; fpsFrames = 0;
    }
  }
  requestAnimationFrame(frame);

  /* ------------------------------------------------------------------
     WHAT THE SCREEN CAN HOLD

     js/palette.js keeps two boxes and they answer different questions.
     The ART palette is what every texture and sprite was PAINTED in —
     the fifteen material ramps — and it never changes. The DISPLAY
     palette is what the screen can hold, and it is a setting: the same
     ramps, or the Uzebox's, which is a real console's hardware limit of
     three bits of red, three of green and two of blue.

     THE DITHER IS WHAT MAKES THAT WORK. The post pass already dithers
     the finished frame and snaps it through a lookup cube; point that
     cube at a smaller box and the ordered dither carries the art's full
     colour down to it at the last moment, which is how a console
     palette reads as a console rather than as four flat bands. Painting
     the textures in the small box as well was the first attempt and it
     was worse: dithering at 64 texels and then again at grid
     resolution, and two dithers over each other are not twice the
     texture, they are noise.

     SO THERE ARE TWO THINGS TO REMAKE and they are both pictures of the
     cube rather than pictures of the art: the cube itself, and THE SKY,
     which is baked through it (js/skyart.js snaps in its own texels so
     the grain sits still) and is therefore in the old box until it is
     baked again. Nothing else moves, which is why this is a few
     milliseconds rather than a re-bake of the game.
     ------------------------------------------------------------------ */
  function applyPalette(name) {
    if (!setDisplayPalette(name)) return false;
    pipeline.rebuildLut();
    skyBaker.bake(game.weather.frame);
    return true;
  }
  /* and the choice the player last made, applied before the first frame */
  const wanted = PALETTE_SET[prefs.palette]?.v;
  if (wanted && wanted !== displayName) applyPalette(wanted);

  /* ------------------------------------------------------------------
     AND WHAT THE ART IS PAINTED IN, which is the other one

     At the user's request, and asked for as a test that could be undone
     — so it is a setting with two entries in it and not a repaint of
     the repository. Everything in this game that is DRAWN is drawn
     through ramp(key, t), fifteen curves through the colour solid; swap
     the fifteen for fifteen muted, warmer ones of exactly the same
     shape (EARTH_RAMPS in js/palette.js) and every picture the program
     makes comes out recoloured rather than scrambled — because the
     ramps are the same length, so entry n of the palette is the same
     MATERIAL in both boxes.

     WHAT HAS TO BE MADE AGAIN, and it is more than the display palette
     needs because this one changes the art rather than the box it is
     shown in:

       THE TEXTURES, repainted into the same three.js textures every
         material in the scene is already holding (TextureBank.add).
       THE SPRITES, likewise — and then the PHOTOGRAPHS laid over them
         again, because a repaint puts every stand-in back. See
         dressSprites above.
       THE WEAPONS, which are Pix handed to the HUD each frame.
       THE LOOKUP CUBE and THE SKY, exactly as applyPalette does: the
         default display box IS the art palette, the same array, so
         changing the art changes what the screen holds too.

     WHAT IS NOT MADE AGAIN, on purpose: the particle atlases, the GLB
     models, and the photographs themselves. All three are snapped
     through the cube at the last moment like everything else in the
     frame, so they land in the new box anyway — which is the same
     argument the Uzebox palette already makes one paragraph up. The
     difference between that and a repaint is that a repaint DRAWS in
     the new box instead of being quantised into it, and a repaint is
     what the fifteen ramps make possible and a photograph does not.

     THE EMBERS ARE NOT IN IT EITHER, and that is a decision rather than
     an omission. EMBER_RAMP is what everything still glowing after the
     flame has gone is lit by, and the fire is the subject of this game:
     the earth box mutes the whole world and takes only the neon off the
     fire, which is the point of looking at a burning building through
     it.
     ------------------------------------------------------------------ */
  function applyTone(name) {
    if (!setArtPalette(name)) return false;
    const t0 = performance.now();
    bakeTextures(textures);
    bakeSprites(sprites);
    dressSprites(); dressTroops();
    weapons = bakeWeapons();
    pipeline.rebuildLut();
    skyBaker.bake(game.weather.frame);
    console.log(`the tone: ${name}, repainted in ${(performance.now() - t0) | 0}ms`);
    return true;
  }

  /* let the console poke at it */
  window.SELLWRONG = { game, pipeline, renderer, scene, camera, textures, sprites, world, level, input, touch, weapon3d, scope, thermal, music, weather: game.weather, skyBaker, applyPalette, applyTone,
                       responders: game.responders, giblets: game.giblets };
}

boot().catch(e => {
  console.error(e);
  failed('FAILED: ' + e.message);
  const s = $('load-status');
  if (s) s.style.color = '#f44';
});

/** Join the host named by ?join=host:port — or, with no host, the one
 *  that served this page, which is the dedicated server's own trick
 *  (tools/server.mjs). Resolves to a welcomed NetClient, or throws with
 *  what went wrong on the loading screen. */
async function joinHost() {
  const q = new URLSearchParams(location.search);
  const host = q.get('join') || location.host;
  const name = (q.get('name') || localStorage.getItem('sellwrong.name') || `PLAYER ${100 + ((Math.random() * 900) | 0)}`)
    .toUpperCase().slice(0, 16);
  try { localStorage.setItem('sellwrong.name', name); } catch { /* private window */ }
  status(`JOINING ${host.toUpperCase()}`, 0.6);
  const url = `${location.protocol === 'https:' ? 'wss' : 'ws'}://${host}${NET_PATH}`;
  const client = new NetClient(new WebSocketTransport(url), { name });
  const ok = await new Promise(res => {
    const t = setTimeout(() => res(false), 8000);
    client.onwelcome = () => { clearTimeout(t); res(true); };
    client.onclose = () => { clearTimeout(t); res(false); };
  });
  if (!ok) {
    const why = client.refused || client.bye || (client.closed ? 'nobody answered' : 'no answer in eight seconds');
    throw new Error(`could not join ${host}: ${why}`);
  }
  console.info(`joined ${host} as ${name}, player ${client.id}: ${client.map.kind} seed ${client.map.seed}`);
  return client;
}

/** The world a host named: every map it can offer is a function of a
 *  seed, so this is the same world it built (tools/headless.mjs). */
function netMap(map) {
  const make = { jesse: jesseDoc, maze: mazeDoc }[map.kind];
  if (!make) throw new Error(`the host is playing ${map.kind}, which this page cannot build`);
  const doc = make(map.seed, map.opts || {});
  return { ...compileDoc(doc), doc };
}

/** The world to play, compiled: THE SPRAWL, or the map MEWD Editor handed
 *  over for a test run — or null for ?grid, and the game plays THE
 *  GRID. See PLAY_KEY in js/editor/editor.js. */
function playedMap() {
  const q = new URLSearchParams(location.search);
  /* THE DEMO LEVEL IS THE GAME'S OWN WORLD NOW, at the user's request:
     THE SPRAWL, built in code out of the user's own assets
     (js/maps/sprawl.js), is what MEWD opens and what a reload comes back
     to. ?demo still says so outright; ?grid is THE GRID, the test area
     it used to be; ?play is a test run of an edited map. */
  const sprawl = () => { const doc = sprawlDoc(); return { ...compileDoc(doc), doc }; };
  /* AND NOW, at the user's request, THE DEMO IS A MAZE: generated
     afresh every time the game starts, full of people (js/maps/maze.js).
     ?seed=N plays maze N again; ?sprawl is THE SPRAWL. */
  const maze = () => {
    const seed = q.has('seed') ? (+q.get('seed') >>> 0) || 1 : newMazeSeed();
    const doc = mazeDoc(seed);
    console.info(`THE MAZE, seed ${seed} (?seed=${seed} plays it again)`);
    return { ...compileDoc(doc), doc };
  };
  if (q.has('grid')) return null;
  if (q.has('sprawl')) return sprawl();
  /* JESSE, the PvP maze: a different one every time; ?jesse&seed=N
     plays N again (js/maps/jesse.js) */
  if (q.has('jesse')) {
    const seed = q.has('seed') ? (+q.get('seed') >>> 0) || 1 : newJesseSeed();
    const doc = jesseDoc(seed);
    console.info(`JESSE, seed ${seed} (?jesse&seed=${seed} plays it again)`);
    return { ...compileDoc(doc), doc };
  }
  if (!q.has('play')) return maze();
  try {
    const text = localStorage.getItem('gss-edit:play');
    if (!text) return maze();
    const doc = parseDoc(text);
    return { ...compileDoc(doc), doc };
  } catch (e) {
    console.error('the edited map did not compile; playing THE MAZE', e);
    return maze();
  }
}
