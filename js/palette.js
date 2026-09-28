/* =====================================================================
   MEWD — the palette, and the light that falls off in bands
   =====================================================================

   Two things make a 1993 shooter look like a 1993 shooter, and neither
   of them is the polygon count.

   THE PALETTE. 256 colours and no more, so every surface in the store is
   drawn out of the same small box of crayons and the whole thing hangs
   together whether or not any individual texture is any good. Colours
   that are not in the box get snapped to the nearest one that is, and
   that snapping is what puts the faint banding into a gradient that says
   "this is old" more loudly than any amount of noise.

   These are ramps, not somebody's curated palette. A palette is a piece
   of work with a person's name on it; a ramp is arithmetic. So this file
   generates its 256 out of fifteen ramps and owes nobody anything.

   ONE THING DEPENDS ON THE ORDER OF THEM. The two pictures in art/ are
   kept as palette INDICES — js/art-data.js, baked by tools/bake-art.mjs
   — so adding a ramp, resizing one or moving one moves every index in
   both. After any change to the list below: node tools/bake-art.mjs,
   and commit what it writes. CI re-bakes and fails if that was missed,
   which is how the sky ramp got found out.

   A ramp is three colours, not two. Interpolating a light brown straight
   down to black gives you a dead grey-brown that no real material does —
   real shadow keeps some hue and usually cools off on the way down. So
   every ramp is dark → mid → light with the mid off the straight line,
   and the bend in the middle is where the material actually lives.

   THE LIGHT. Doom did not multiply a surface by a light level; it picked
   one of 32 pre-darkened copies of the palette. Which means light falls
   off in visible STEPS. Walking down a dark aisle, the wall ahead does
   not fade smoothly — it drops a band at a time. That stepping is half
   the atmosphere, and smooth lighting throws it away for nothing, so the
   material shader below quantises light to 32 levels before it uses it.
   ===================================================================== */

/* --------------------------------------------------------------------
   The ramps

   A ramp is a list of STOPS — a position along the ramp and the colour
   that sits there — and the entries between them are interpolated. Two
   stops would be a straight line through RGB space, and a straight line
   through RGB space is exactly what no real material does: interpolate
   a light brown down to black and you get a dead grey-brown halfway that
   looks like nothing. Real shadow keeps its hue and usually cools on the
   way down, so most ramps here have a third stop in the middle placed
   deliberately off that line, and that bend is where the material lives.

   Fire gets seven stops, because fire is not a bend, it is a whole route:
   black to dark red to blood to ember to orange to yellow to white heat,
   and every one of those transitions is somewhere the eye will look. It
   is also the biggest ramp in the palette at 44 entries. That is not
   generosity, it is the point of the game — the store burning down is
   the only thing anybody is going to look at closely, and a flame that
   bands badly ruins the whole effect.

   gamma  bends how the entries are DISTRIBUTED along the ramp, as
          opposed to where the stops are. Above 1 spends more of the
          available entries down in the dark end, which is where the eye
          has the most resolution and where linear spacing wastes half a
          ramp on highlights nobody can tell apart.
   ------------------------------------------------------------------ */
const STOCK_RAMPS = [
  /* greys — concrete, steel, shadow. Cool at the bottom, because a shadow
     full of skylight is blue and a shadow full of nothing is still not
     brown. */
  { key:'grey',   n:24, gamma:1.30, stops:[[0,[6,7,11]],[0.5,[92,94,102]],[1,[248,248,252]]] },
  /* bone — lino, ceiling tile, painted breeze block */
  { key:'bone',   n:16, gamma:1.25, stops:[[0,[22,20,17]],[0.5,[130,124,108]],[1,[244,238,216]]] },
  /* brown — cardboard, shelf backing, particle board */
  { key:'brown',  n:16, gamma:1.20, stops:[[0,[18,12,8]],[0.5,[104,68,40]],[1,[214,168,116]]] },
  /* red — blood, and the SellWrong corporate red, which is the same
     colour, which is the joke */
  { key:'red',    n:16, gamma:1.20, stops:[[0,[16,4,4]],[0.5,[136,22,20]],[1,[248,116,96]]] },
  /* flesh — what is left of the staff */
  { key:'flesh',  n:16, gamma:1.20, stops:[[0,[20,12,12]],[0.5,[130,92,76]],[1,[240,206,180]]] },
  /* green — the uniform polo, and produce */
  { key:'green',  n:16, gamma:1.20, stops:[[0,[6,14,8]],[0.5,[52,104,52]],[1,[168,228,150]]] },
  /* olive — the uniform after a week, and old lettuce */
  { key:'olive',  n:16, gamma:1.20, stops:[[0,[14,14,8]],[0.5,[90,88,44]],[1,[204,200,140]]] },
  /* blue — freezer glow, cold cases, the signage */
  { key:'blue',   n:16, gamma:1.25, stops:[[0,[4,6,18]],[0.5,[40,60,132]],[1,[152,184,248]]] },
  /* cyan — frost, and the light coming off the ice */
  { key:'cyan',   n:8,  gamma:1.20, stops:[[0,[6,16,18]],[0.5,[60,132,140]],[1,[188,248,252]]] },
  /* yellow — hazard tape, price tags, SALE */
  { key:'yellow', n:16, gamma:1.15, stops:[[0,[20,16,4]],[0.5,[168,144,24]],[1,[252,248,140]]] },
  /* rust — trolleys, shelf uprights, the dock door */
  { key:'rust',   n:16, gamma:1.20, stops:[[0,[16,9,6]],[0.5,[118,62,30]],[1,[224,150,92]]] },
  /* purple — the neon over the deli, and bruises */
  { key:'purple', n:8,  gamma:1.20, stops:[[0,[12,6,16]],[0.5,[80,44,108]],[1,[204,164,240]]] },
  /* pink — the meat counter, which is worse than the blood */
  { key:'pink',   n:8,  gamma:1.20, stops:[[0,[22,10,12]],[0.5,[164,84,92]],[1,[252,196,196]]] },
  /* SKY. Twenty entries, and they came out of grey, cyan, purple and
     pink, eight and four and four and four. The fire got forty-four on
     the argument that the store burning down is the only thing anyone
     looks at closely; a dawn is the second thing, and it fills half
     the frame with a gradient no other ramp runs through — night blue,
     violet, rose, a cold gold, and the pale blue of a morning. Without
     these it snapped into blue and pink and dithered into crosshatch,
     which was the first thing the first screenshot showed. */
  { key:'sky',    n:20, gamma:1.10, stops:[[0,[10,16,48]],[0.30,[62,66,128]],[0.55,[176,120,140]],[0.78,[236,196,150]],[1,[214,232,248]]] },
  /* FIRE. Seven stops and 44 entries, spaced by hand. The stops are
     bunched toward the bottom because most of a flame, most of the time,
     is the dull end — the white heat is a few pixels at the base of it. */
  { key:'fire',   n:44, gamma:1.0, stops:[
      [0.00,[  0,  0,  0]],
      [0.10,[ 34,  0,  0]],
      [0.24,[ 96,  6,  0]],
      [0.40,[168, 26,  0]],
      [0.56,[226, 74,  6]],
      [0.72,[248, 142, 14]],
      [0.87,[252, 216, 62]],
      [1.00,[255, 255, 226]] ] },
];

/* --------------------------------------------------------------------
   AND A SECOND BOX OF CRAYONS: MUTED, EARTHY

   At the user's request, and asked for as a test that could be undone —
   so it is a SETTING and not a repaint. What follows is the same fifteen
   ramps with different colours in them.

   THE SAME FIFTEEN IS THE WHOLE TRICK, and it is a constraint rather
   than a convenience. Every ramp below has the same `key`, the same `n`
   and the same position in the list as the one above it, so RAMP[key]
   lands at the same index, every entry of the 256 means the same
   MATERIAL in both boxes, and the two pictures in art/ — which are kept
   as palette indices in js/art-data.js and would otherwise have to be
   baked again by tools/bake-art.mjs — come out recoloured rather than
   scrambled. Change an `n` here and that stops being true; the smoke
   test holds the two lists against each other for exactly that reason.

   WHAT EARTHY MEANS, in numbers rather than in adjectives:

     the blacks go brown. A shadow in the box above is cool — [6,7,11],
       a shadow full of skylight. Here it is [16,14,12], a shadow full of
       dust, which is what a shadow in a dry place is.
     nothing reaches white. The top of every ramp comes down from the
       248-252 the stock box runs to, to somewhere in the 190s to 220s,
       and warms on the way — the single loudest thing about a faded
       picture is that its highlights are not white.
     the saturation comes off the middle, which is where a ramp's
       material lives. Greens go to sage and dried grass, blues to
       slate, cyan to verdigris, purple to heather, pink to clay,
       yellow to ochre. The three that were already earth — brown, rust
       and flesh — barely move, because they were already the answer.
     THE FIRE DOES NOT MUTE, or hardly. It is the subject of the game
       and the one thing in the frame that is supposed to be the
       brightest thing in the frame; muting it would be muting the point.
       What it loses is the neon: the white heat comes down from
       [255,255,226] to a warm bone, and the orange loses its edge, and
       that is all.

   The gammas are the stock box's, unchanged, so the two are directly
   comparable: the same entry of each is the same distance along the
   same kind of ramp, and only the colour differs.
   ------------------------------------------------------------------ */
const EARTH_RAMPS = [
  /* stone rather than steel: a warm grey with the blue taken out of the
     bottom of it */
  { key:'grey',   n:24, gamma:1.30, stops:[[0,[16,14,12]],[0.5,[96,90,80]],[1,[226,218,200]]] },
  /* unbleached — plaster, lino gone yellow, ceiling tile in a building
     somebody smoked in */
  { key:'bone',   n:16, gamma:1.25, stops:[[0,[26,22,18]],[0.5,[124,112,92]],[1,[226,212,184]]] },
  /* brown was already earth and barely moves */
  { key:'brown',  n:16, gamma:1.20, stops:[[0,[20,14,10]],[0.5,[98,70,46]],[1,[198,160,118]]] },
  /* iron oxide: brick and old blood rather than corporate red */
  { key:'red',    n:16, gamma:1.20, stops:[[0,[22,12,10]],[0.5,[118,52,38]],[1,[204,124,96]]] },
  /* flesh, a shade duller and a shade warmer */
  { key:'flesh',  n:16, gamma:1.20, stops:[[0,[24,16,13]],[0.5,[122,90,70]],[1,[220,188,158]]] },
  /* sage and dried grass, which is what green is in a dry summer */
  { key:'green',  n:16, gamma:1.20, stops:[[0,[14,18,12]],[0.5,[64,86,50]],[1,[168,186,132]]] },
  /* khaki */
  { key:'olive',  n:16, gamma:1.20, stops:[[0,[18,16,10]],[0.5,[88,80,46]],[1,[190,180,132]]] },
  /* slate and faded denim: the one ramp that loses the most, because
     the stock blue is the most saturated thing in the box */
  { key:'blue',   n:16, gamma:1.25, stops:[[0,[12,14,20]],[0.5,[54,66,88]],[1,[150,168,190]]] },
  /* verdigris rather than ice */
  { key:'cyan',   n:8,  gamma:1.20, stops:[[0,[14,20,20]],[0.5,[64,104,100]],[1,[170,200,194]]] },
  /* ochre and mustard */
  { key:'yellow', n:16, gamma:1.15, stops:[[0,[24,19,10]],[0.5,[150,120,44]],[1,[226,204,134]]] },
  /* terracotta, which is where rust was going anyway */
  { key:'rust',   n:16, gamma:1.20, stops:[[0,[20,13,9]],[0.5,[110,66,40]],[1,[204,148,102]]] },
  /* heather: a plum with the light gone out of it */
  { key:'purple', n:8,  gamma:1.20, stops:[[0,[18,14,18]],[0.5,[76,56,74]],[1,[180,158,168]]] },
  /* clay */
  { key:'pink',   n:8,  gamma:1.20, stops:[[0,[26,16,14]],[0.5,[148,94,84]],[1,[222,184,168]]] },
  /* a dustier dawn: the same five stops, every one of them with the
     colour turned down and the whole thing warmer at the horizon */
  { key:'sky',    n:20, gamma:1.10, stops:[[0,[16,18,30]],[0.30,[58,58,76]],[0.55,[142,110,104]],[0.78,[208,176,136]],[1,[196,206,212]]] },
  /* AND THE FIRE, which does not mute. Seven stops in the same places;
     what comes off is the neon at the top. */
  { key:'fire',   n:44, gamma:1.0, stops:[
      [0.00,[  0,  0,  0]],
      [0.10,[ 30,  4,  2]],
      [0.24,[ 84, 12,  4]],
      [0.40,[150, 36,  8]],
      [0.56,[204, 80, 18]],
      [0.72,[232, 140, 40]],
      [0.87,[244, 198, 92]],
      [1.00,[250, 238, 206]] ] },
];

/* --------------------------------------------------------------------
   AND A THIRD BOX: THE GRID

   The world the game boots into is a green wireframe grid on black with
   green boxes burning on it (see js/maps/grid.js), and neither of the
   boxes above can paint it. Their green is a POLO SHIRT: sixteen entries
   topping out at a sage, drawn for produce and a uniform, and their sky
   is twenty entries of dawn — night blue, violet, rose. In a green world
   those twenty are the twenty that matter and every one of them is the
   wrong colour, so a green sky snapped into blue and crosshatched,
   which is the same thing that happened to the first dawn and is why
   the sky ramp exists at all.

   So the green goes up and the sky ramp goes green: thirty-six entries
   between them, which is what a world made of one colour needs.

   THE SAME FIFTEEN, still — same keys, same `n`, same order, same
   gammas — so entry n means the same MATERIAL here as in the other two
   and the photographs in js/art-data.js recolour rather than scramble.
   See the note on EARTH_RAMPS, which is the whole of the reasoning.

   FOUR RAMPS DO NOT GO GREEN, and each is a thing you have to be able to
   tell from the world it is standing in: `red` and `fire`, which are the
   burning (see EMBER_RAMP, which does not tone either); `flesh`, because
   a hundred people in a green field have to read as people; and `rust`,
   which is what is left of them.
   ------------------------------------------------------------------ */
const GRID_RAMPS = [
  /* the grid's own unlit black, going up through a green-grey */
  { key:'grey',   n:24, gamma:1.30, stops:[[0,[4,6,5]],[0.5,[58,74,62]],[1,[190,216,198]]] },
  { key:'bone',   n:16, gamma:1.25, stops:[[0,[6,10,7]],[0.5,[76,104,82]],[1,[208,236,212]]] },
  { key:'brown',  n:16, gamma:1.20, stops:[[0,[8,10,6]],[0.5,[62,78,40]],[1,[164,186,120]]] },
  /* red stays red: it is the fire, the blood and the engine */
  { key:'red',    n:16, gamma:1.20, stops:[[0,[18,4,4]],[0.5,[138,26,20]],[1,[248,120,96]]] },
  /* and flesh stays flesh, or a hundred people vanish into the field */
  { key:'flesh',  n:16, gamma:1.20, stops:[[0,[22,16,13]],[0.5,[126,94,74]],[1,[238,204,178]]] },
  /* THE GREEN. Black at the bottom and a phosphor at the top: this is
     the grid, the boxes, and everything the world is made of. */
  { key:'green',  n:16, gamma:1.20, stops:[[0,[2,10,4]],[0.5,[24,152,52]],[1,[150,255,168]]] },
  { key:'olive',  n:16, gamma:1.20, stops:[[0,[6,12,4]],[0.5,[64,110,36]],[1,[176,230,140]]] },
  { key:'blue',   n:16, gamma:1.25, stops:[[0,[4,10,12]],[0.5,[30,74,86]],[1,[140,200,212]]] },
  { key:'cyan',   n:8,  gamma:1.20, stops:[[0,[4,14,12]],[0.5,[36,140,110]],[1,[160,252,214]]] },
  { key:'yellow', n:16, gamma:1.15, stops:[[0,[16,16,4]],[0.5,[150,160,24]],[1,[236,252,130]]] },
  /* rust is the other thing that has to stay itself */
  { key:'rust',   n:16, gamma:1.20, stops:[[0,[16,9,6]],[0.5,[116,62,30]],[1,[222,150,92]]] },
  { key:'purple', n:8,  gamma:1.20, stops:[[0,[10,8,16]],[0.5,[64,56,104]],[1,[180,172,236]]] },
  { key:'pink',   n:8,  gamma:1.20, stops:[[0,[22,10,12]],[0.5,[160,84,92]],[1,[250,196,196]]] },
  /* AND THE SKY, which in this world is the gradient the user asked for:
     black overhead, down through a dark green, to a green at the
     horizon. Twenty entries for it, which is what stopped the dawn
     crosshatching and is what stops this one. The air fades to a texel
     of this (see js/material.js), so the far edge of the grid goes to
     the same green the horizon is — which is the horizon being where
     the world ends rather than a wall standing in front of it. */
  { key:'sky',    n:20, gamma:1.10, stops:[[0,[0,0,0]],[0.30,[2,14,6]],[0.55,[8,48,20]],[0.78,[16,104,42]],[1,[44,196,84]]] },
  /* AND THE FIRE, which is the stock box's exactly. A coal is a coal in
     every world; see EMBER_RAMP. */
  { key:'fire',   n:44, gamma:1.0, stops:[
      [0.00,[  0,  0,  0]],
      [0.10,[ 34,  0,  0]],
      [0.24,[ 96,  6,  0]],
      [0.40,[168, 26,  0]],
      [0.56,[226, 74,  6]],
      [0.72,[248, 142, 14]],
      [0.87,[252, 216, 62]],
      [1.00,[255, 255, 226]] ] },
];

/** The boxes the ART can be PAINTED in, by the name the setting uses.
 *  Which one is current is a live value — see setArtPalette. */
export const ART_PALETTES = { stock: STOCK_RAMPS, earth: EARTH_RAMPS, grid: GRID_RAMPS };
/* AND EARTH IS THE ONE THE GAME IS IN, at the user's request. STOCK is
   the box every texture in this game was originally drawn in and is
   still what `stock` means; it is also the box the two photographs in
   art/ are quantised against, because a picture is best quantised in
   the fuller box and the earth one then recolours it through the shared
   index — which is the whole reason the two lists have the same shape.
   tools/bake-art.mjs asks for it BY NAME for exactly that reason, and
   does not simply take whatever is current. */
export const DEFAULT_ART = 'earth';
export let artName = DEFAULT_ART;

/* Where each ramp starts, filled in as we build */
export const RAMP = {};

function rampColors(spec) {
  const { n, stops } = spec;
  const gamma = spec.gamma ?? 1.0;
  const out = [];
  for (let i = 0; i < n; i++) {
    /* gamma bends the DISTRIBUTION; the stops decide the route */
    const t = Math.pow(i / (n - 1), gamma === 1 ? 1 : 1 / gamma);
    let k = 0;
    while (k < stops.length - 2 && t > stops[k + 1][0]) k++;
    const [p0, c0] = stops[k], [p1, c1] = stops[k + 1];
    const span = Math.max(1e-6, p1 - p0);
    const f = Math.max(0, Math.min(1, (t - p0) / span));
    /* smoothstep between stops, so a stop is a place the ramp passes
       through smoothly rather than a kink you can see */
    const s = f * f * (3 - 2 * f);
    out.push([0, 1, 2].map(j => Math.max(0, Math.min(255, Math.round(c0[j] + (c1[j] - c0[j]) * s)))));
  }
  return out;
}

/* ---- build the 256 ---- */
/* --------------------------------------------------------------------
   THE RAMPS ARE THE MATERIALS. THE PALETTE IS THE BOX OF CRAYONS.

   These were the same thing for most of this project's life: the 256
   WERE the ramps laid end to end, and ramp(key, t) handed back a
   palette entry by index. That is the right way round for one palette
   and it is the reason there could only ever be one — swap the box and
   every index into it means a different colour, so every texture in the
   game comes out scrambled rather than recoloured.

   So they are two things now. RAMP_RGB is what a material IS: fifteen
   ramps of arithmetic, computed once, never changing, and what
   ramp(key, t) answers with. The palette is what a machine can actually
   show. Painting picks the material; snapping (snapImageData,
   nearestIndex) puts it in the box.

   THE ART PALETTE AND THE BOX BELOW IT ARE THE SAME LIST, so a colour
   asked for is a colour it has and the snap is the identity. Which box
   the SCREEN holds is a separate question and is answered further down,
   under TWO PALETTES, AND THEY ARE ANSWERS TO DIFFERENT QUESTIONS.
   ------------------------------------------------------------------ */
const RAMP_RGB = {};
/* IT IS FILLED IN PLACE AND NEVER REPLACED, and that is what lets the
   box be swapped at all. Half the game holds a reference to this array
   — PALETTE is it, DISPLAY_PALETTES.ramps.colors is it, decodeArtTile
   in js/sprites.js indexes it — and a module that captured it at load
   time would keep the old colours for ever if buildArt handed back a
   new one. So every entry is written THROUGH, and everybody holding it
   sees the new box on the next pixel they ask for. Same for RAMP_RGB,
   which is what ramp() answers out of. */
export const RAMP_PALETTE = [];
function buildArt(specs) {
  let at = 0;
  for (const r of specs) {
    RAMP[r.key] = { start: at, n: r.n };
    const cols = rampColors(r);
    RAMP_RGB[r.key] = cols;
    for (const c of cols) { RAMP_PALETTE[at] = c; at++; }
  }
  /* Whatever is left over becomes pure saturated markers — useful when a
     placeholder needs to SCREAM that it is a placeholder. The fifteen
     ramps come to exactly 256, so there are none; the loop is what
     would keep the palette 256 long if one of them ever shrank. */
  const markers = [[255,0,255],[0,255,255],[255,255,0],[255,0,0],[0,255,0],[0,0,255],[255,128,0],[128,0,255]];
  let m = 0;
  while (at < 256) { RAMP_PALETTE[at] = markers[m++ % markers.length].slice(); at++; }
  RAMP_PALETTE.length = 256;
}
buildArt(ART_PALETTES[DEFAULT_ART]);

/**
 * Choose what the art is PAINTED in — see the note on EARTH_RAMPS.
 *
 * It changes nothing that is already painted, which is the whole of
 * what a caller has to do about it: every texture and every sprite in
 * the bank was drawn through ramp() and is still the colour it was
 * drawn. See repaintTextures in js/textures.js, repaintSprites in
 * js/sprites.js, and applyTone in js/main.js, which is the one place
 * that knows the whole list of things to remake.
 */
export function setArtPalette(name) {
  if (!ART_PALETTES[name] || name === artName) return false;
  artName = name;
  buildArt(ART_PALETTES[name]);
  /* THE SNAP CACHE IS A CACHE OF THE OLD BOX. It answers "which of the
     256 is nearest to this colour" out of a table keyed on rgb555, and
     every answer in it is an index into a palette that no longer holds
     those colours. Left alone it is not stale by a shade, it is wrong:
     the first texture repainted would snap through it and come out in
     the box it was supposed to be leaving. */
  _snapCache.fill(-1);
  return true;
}

/* --------------------------------------------------------------------
   THE UZEBOX BOX, which is a piece of hardware and not a mood board.

   The Uzebox drives its picture straight out of an AVR's pins through a
   resistor ladder: three bits of red, three of green and TWO OF BLUE,
   which is 8 x 8 x 4 and is exactly 256. It is generated here rather
   than pasted in, because 256 lines of hex is a table nobody can check
   and three loops is a table that cannot be wrong; art/uzebox.hex is
   the file it was checked against, entry for entry, by the test.

   WHAT IT DOES TO THIS GAME, measured before it was offered: the 256
   the ramps make land on 81 distinct entries of it, and the sky ramp's
   twenty land on thirteen. Two bits of blue is the whole story — a
   night sky that is a gradient in this game is four flat bands in that
   box. That is not a defect in the palette, it is what the hardware
   was; it is the reason this is a SETTING and not a replacement.
   ------------------------------------------------------------------ */
export const UZEBOX_PALETTE = (() => {
  const step8 = [0x00, 0x24, 0x48, 0x6d, 0x91, 0xb6, 0xda, 0xff];
  const step4 = [0x00, 0x55, 0xaa, 0xff];
  const pal = [];
  for (const b of step4) for (const g of step8) for (const r of step8) pal.push([r, g, b]);
  return pal;
})();

/* --------------------------------------------------------------------
   TWO PALETTES, AND THEY ARE ANSWERS TO DIFFERENT QUESTIONS

   THE ART PALETTE is what a picture is PAINTED in: the fifteen ramps,
   and it never changes. Every texture and every sprite in the game is
   snapped to it as it is baked, which is what makes them look like they
   came out of one box of crayons, and it is the whole of this game's
   colour. PALETTE is that, and nearestIndex and snapImageData snap to
   it.

   THE DISPLAY PALETTE is what the SCREEN can hold. The post pass
   dithers the finished frame and snaps it through a lookup cube built
   from this one (buildLutAtlas below, and js/lofi.js), and so does the
   sky as it bakes. By default it is the same list, so the snap is the
   identity and nothing happens — and it can be the Uzebox's instead,
   which is a real console's hardware limit.

   THAT WAY ROUND ON PURPOSE, at the user's request, and it is the
   difference between a good picture and a noisy one. The art keeps all
   the colour it was drawn with and the ORDERED DITHER carries it down
   to the hardware box at the last moment — which is how you get a
   console's palette to look like a console rather than like a
   photograph that has been through it twice. Painting the textures in
   the small box as well meant dithering at 64 texels and then dithering
   again at grid resolution, and two dithers over each other is not
   twice the texture, it is noise.
   ------------------------------------------------------------------ */
export const PALETTE = RAMP_PALETTE;

/* --------------------------------------------------------------------
   AND THE DITHER'S GRID BELONGS TO THE BOX, not to the pipeline.

   The Bayer threshold moves a pixel up to half a step of an RGB grid
   before the snap, and a dither is only doing its job if that step is
   about as wide as the GAP IT HAS TO CROSS. The gap is a property of
   the box, so the step is too, and this is where both live.

   RAMPS: 16 16 16, a sixteenth of each channel, chosen by hand at the
   user's request and unchanged. The ramps are not a regular cube —
   fifteen curves through the colour solid — so there is no spacing to
   derive and the number is a look.

   UZEBOX: 7 7 3, which is not a look, it is the hardware. Eight levels
   of red are seven gaps of 255/7; four of blue are THREE gaps of 85.
   Leave the step at a sixteenth there and the dither spans sixteen
   units of an eighty-five-unit gap — a narrow band of checker with
   flat colour either side of it, which is the banding it was supposed
   to break up, with a seam through it. At 7 7 3 the whole gap
   checkers and a gradient the box cannot hold comes out as a gradient.
   ------------------------------------------------------------------ */

/** The boxes the SCREEN can be, by the name the setting uses: the
 *  colours it holds, and the RGB grid its dither steps on. */
export const DISPLAY_PALETTES = {
  ramps:  { colors: RAMP_PALETTE,   dither: [16, 16, 16] },
  uzebox: { colors: UZEBOX_PALETTE, dither: [7, 7, 3] },
};

/** The box the game starts in, and the one a module that needs a number
 *  at load time has to ask for BY NAME. displayName is a live value: a
 *  module constant that reads it is a constant only until somebody
 *  changes the setting, which is a bug waiting for whoever imports that
 *  module second. */
export const DEFAULT_DISPLAY = 'ramps';
export let displayName = DEFAULT_DISPLAY;

/** Which one the lookup cube is built from. */
export function displayPalette() { return DISPLAY_PALETTES[displayName].colors; }

/** And the grid its dither is one step of — see the note above. */
export function displayDither() { return DISPLAY_PALETTES[displayName].dither; }

/**
 * Choose what the screen can hold.
 *
 * It changes nothing that is already painted: the lookup cube built
 * from it, the dither grid that aims at it, and the sky that was baked
 * through both, have to be made again. See applyPalette in js/main.js,
 * which is the one place that knows which those are.
 */
export function setDisplayPalette(name) {
  if (!DISPLAY_PALETTES[name] || name === displayName) return false;
  displayName = name;
  return true;
}

/* Pick a colour out of a named ramp with a 0..1 position. Every texture and
   every sprite in the game asks for its colours this way, which is what
   keeps them looking like they came out of the same box.

   IT ANSWERS WITH THE MATERIAL rather than by indexing the palette, which
   is the same colour and a better sentence: a ramp is arithmetic and a
   palette is a box, and keeping them apart is what let the screen's box
   become a setting without the art moving. See the note above. */
export function ramp(key, t) {
  const r = RAMP_RGB[key];
  const i = Math.max(0, Math.min(r.length - 1, Math.round(t * (r.length - 1))));
  return r[i];
}
export function rampCss(key, t) { const c = ramp(key, t); return `rgb(${c[0]},${c[1]},${c[2]})`; }
export function rampIndex(key, t) {
  const r = RAMP[key];
  return r.start + Math.max(0, Math.min(r.n - 1, Math.round(t * (r.n - 1))));
}

/* --------------------------------------------------------------------
   The lookup cube

   Snapping a colour to the palette means finding the nearest of 256, and
   doing that per pixel per frame on the CPU is out of the question. So we
   do it once, up front, for every colour there is — at 32 levels per
   channel, which is 32768 cells — and hand the result to the GPU as a 3D
   texture. After that a palette snap is one texture fetch.

   32 levels is the right size. At 16 the cube itself starts quantising
   before the palette gets a chance to, and you can see it. At 64 the
   build takes eight times as long to produce a result nobody can tell
   apart from 32.

   Distance is weighted 3:6:1 across R:G:B — the eye's own weighting.
   Plain RGB distance picks green when it should pick grey and gives the
   whole image a faint sickly cast.
   ------------------------------------------------------------------ */
export const LUT_SIZE = 32;

/* Laid out as a 2D atlas rather than a real 3D texture: 32 slices of
   32x32 side by side, so 1024x32. A genuine sampler3D would be tidier,
   but this works on anything that can draw a triangle, needs no WebGL2
   feature check, and the indexing is three lines of shader either way.

   Slice = blue. Within a slice, x = red and y = green. */
export function buildLutAtlas(palette = displayPalette()) {
  const N = LUT_SIZE, W = N * N, H = N;
  const data = new Uint8Array(W * H * 4);
  const pr = new Float64Array(256), pg = new Float64Array(256), pb = new Float64Array(256);
  for (let i = 0; i < 256; i++) { pr[i] = palette[i][0]; pg[i] = palette[i][1]; pb[i] = palette[i][2]; }

  for (let g = 0; g < N; g++) {
    const gv = (g * 255) / (N - 1);
    for (let b = 0; b < N; b++) {
      const bv = (b * 255) / (N - 1);
      for (let r = 0; r < N; r++) {
        const rv = (r * 255) / (N - 1);
        let best = 0, bestD = Infinity;
        for (let i = 0; i < 256; i++) {
          const dr = rv - pr[i], dg = gv - pg[i], db = bv - pb[i];
          const d = 3 * dr * dr + 6 * dg * dg + db * db;
          if (d < bestD) { bestD = d; best = i; }
        }
        const o = ((g * W) + (b * N + r)) * 4;
        data[o]     = palette[best][0];
        data[o + 1] = palette[best][1];
        data[o + 2] = palette[best][2];
        data[o + 3] = 255;
      }
    }
  }
  return { data, width: W, height: H };
}

/* --------------------------------------------------------------------
   Nearest palette entry, on the CPU

   The texture bakery needs this: it draws with the 2D canvas API, which
   antialiases and blends and generally produces colours that are not in
   the palette, and then every texture gets swept through here so that
   what ends up on the wall is genuinely 256-colour art rather than a
   truecolour image that merely looks like one.
   ------------------------------------------------------------------ */
const _snapCache = new Int16Array(1 << 15).fill(-1);   // keyed on rgb555

export function nearestIndex(r, g, b) {
  const key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
  const hit = _snapCache[key];
  if (hit >= 0) return hit;
  let best = 0, bestD = Infinity;
  for (let i = 0; i < 256; i++) {
    const p = PALETTE[i];
    const dr = r - p[0], dg = g - p[1], db = b - p[2];
    const d = 3 * dr * dr + 6 * dg * dg + db * db;
    if (d < bestD) { bestD = d; best = i; }
  }
  _snapCache[key] = best;
  return best;
}

/* Snap an ImageData in place. Alpha is left alone — it is a cut-out mask,
   not a colour, and rounding it turns a sprite's edge to lace.

   The optional ordered dither is a 4x4 Bayer matrix nudging each pixel a
   little up or down before the snap, which trades a hard band for a fine
   checker. On a 64px texture seen from two metres that reads as texture;
   on a sprite it reads as dirt. Both are what we want. */
const BAYER4 = [
   0,  8,  2, 10,
  12,  4, 14,  6,
   3, 11,  1,  9,
  15,  7, 13,  5,
];

export function snapImageData(img, dither = 0) {
  const d = img.data, w = img.width;
  for (let i = 0, px = 0; i < d.length; i += 4, px++) {
    if (d[i + 3] < 8) { d[i + 3] = 0; continue; }        // transparent stays transparent
    let r = d[i], g = d[i + 1], b = d[i + 2];
    if (dither > 0) {
      const x = px % w, y = (px / w) | 0;
      const t = (BAYER4[(y & 3) * 4 + (x & 3)] / 15 - 0.5) * dither;
      r = Math.max(0, Math.min(255, r + t));
      g = Math.max(0, Math.min(255, g + t));
      b = Math.max(0, Math.min(255, b + t));
    }
    const p = PALETTE[nearestIndex(r | 0, g | 0, b | 0)];
    d[i] = p[0]; d[i + 1] = p[1]; d[i + 2] = p[2];
    d[i + 3] = 255;                                       // no partial alpha, ever
  }
  return img;
}

/* sRGB bytes-as-fractions to linear light, the standard curve. It lived
   in js/weather.js, which still exports it; it is here so the sky bake
   can use it without depending on the weather, which depends on the
   world material, which reads the sky's size — a cycle nobody needs. */
export const toLinear = c => c.map(v => (v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)));

/* --------------------------------------------------------------------
   THE EMBER RAMP

   Eight colours, cold coal to gold — the golf project's ps1-soft ramp.
   Everything in this game that is still glowing after the flame has gone
   uses these eight and nothing else: the burning trees (js/forest.js),
   the sparks off a fire (js/effects.js), and every charred and gutted
   surface in the store (the world material in js/material.js). One ramp
   and one clock, so a burnt wall and a burnt fir are visibly the same
   fire going out rather than two effects that happen to be orange.
   ------------------------------------------------------------------ */
export const EMBER_RAMP = ['#181008', '#302000', '#503000', '#704000', '#985800', '#c07820', '#e89858', '#f8d0a0']
  .map(h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255));
