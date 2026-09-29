/* =====================================================================
   MEWD — the lo-fi pipeline
   =====================================================================

   The whole game is drawn into a buffer, filtered down onto a grid of
   chunky pixels, and thrown at the screen with no smoothing whatsoever.
   Everything else in here follows from that.

   THOSE ARE TWO SIZES AND THEY USED TO BE ONE. For most of this
   project's life there was a single number — the buffer's height — and
   it answered two questions at once: how much detail the world is drawn
   with, and how big a pixel is. Which is how it worked in 1993, because
   the buffer WAS the screen, and it is a bad control because the two
   answers pull opposite ways. Turn it up for a sharper picture and the
   pixels vanish; turn it down for the pixels and the far end of the shop
   turns to mush. There is no setting at which the store is legible AND
   the picture is made of visible squares, which is the look.

   So there are two now:

     RENDER  the size of the buffer the world is rasterised into. This
             is the detail control and it is where the frame rate goes:
             halving it quarters the pixels being shaded.

     PIXELS  the size of the grid that buffer is filtered down onto,
             which is what you actually see. This is the LOOK control
             and it is nearly free — the filter runs once per chunky
             pixel, not once per screen pixel.

   AND FILTERED DOWN MEANS AVERAGED, which is the entire reason the two
   are worth separating. Point-sampling a 600-row buffer onto a 200-row
   grid picks one row in three and throws the rest away, and the result
   is a 200-row picture that cost three times as much — the two controls
   would be one control again, wearing a hat. Averaging each block
   instead spends that extra buffer on the CONTENT of the chunky pixel:
   an edge that falls two thirds of the way across a block comes out two
   thirds of the way between the two colours. A 320x200 picture with
   every square correct to an eighth of itself is a thing no 1993 machine
   could draw and it is what the setting is for.

   WHY A FIXED HEIGHT AND NOT A FIXED SIZE, for both of them. Doom was
   320x200 on a 4:3 monitor, which nobody has any more. Lock the width
   too and a modern window gets black bars down both sides; let both
   float and the game gets sharper on a bigger monitor, which is the
   exact opposite of the point. So the heights are fixed and the widths
   follow the window's shape. The camera's field of view is vertical, so
   a wider window shows you MORE STORE rather than the same store
   stretched, which is how a widescreen port ought to behave.

   AND THE PIXELS NEED NOT BE SQUARE. 320x200 filling a 4:3 monitor is
   not a square-pixel mode and never was: each pixel stood five wide to
   six tall, and every Doom sprite was drawn by somebody looking at that
   screen. A square-pixel 320x200 is a squashed Doom. So the grid takes a
   PIXEL ASPECT — the width of one chunky pixel over its height, as
   displayed — and the grid's width is the window's shape divided by it.
   Ask for 5:6 on a 4:3 window at two hundred rows and you get 320x200,
   which is not a coincidence and is the whole of the arithmetic.

   NOTHING ABOUT THE WORLD MOVES WHEN THAT CHANGES. The camera's aspect
   is the BUFFER's, and the buffer's pixels are always square; the grid
   is a quantisation laid over the finished frame, and quantising a frame
   anisotropically does not stretch what is in it. So a tall-pixel
   picture shows exactly the same store as a square-pixel one, in taller
   squares.

   WHY THE GUN GOES IN THE SAME BUFFER AND THE READOUT DOES NOT. The gun
   in your hands is IN the room — lit by it, moving with your step — and
   drawing it at native resolution over a chunky world collapses the
   whole illusion: a cardboard cut-out held up to a photograph. So it is
   an overlay scene, rendering into this buffer and going through this
   filter. There can be several of them: the flamethrower is a 3D model
   with its own perspective camera, the wash over a pickup is a flat
   quad with an orthographic one, and they draw in order, each clearing
   depth so it lands over whatever came before.

   THE NUMBERS ARE NOT IN THE ROOM, and at the user's request they left.
   Nothing occludes them and nothing lights them; they are printed on
   the glass, and a label on the glass is not more honest for being out
   of focus. The bars, the weapon's name and the end-of-night card are
   their own 2D canvas over the frame now, at the device's resolution,
   and this file never sees them — see the top of js/hud.js.

   AN OVERLAY IS LAID OUT IN CHUNKY PIXELS, not in buffer pixels, which
   is what keeps it the same size on screen when the RENDER control
   moves. An orthographic camera's extents are a unit of measure rather
   than a resolution: give it the grid's size and a six-pixel sprite is
   six CHUNKY pixels at any buffer size. At an integer ratio the block
   average puts each of its texels back exactly, so it comes out of a
   600-row buffer bit-for-bit identical to the one drawn straight into a
   200-row one.

   THE ORDER MATTERS. Average, then dither, then snap. Dithering after
   the snap would just put colours back that the palette does not
   contain. Dither first and the error the snap is about to make gets
   spread into a fine checker instead of a hard band, which is how a
   256-colour gradient ever looked like a gradient — and it is dithered
   ON THE GRID, one threshold per chunky pixel, because a checker finer
   than the pixels is a checker the averaging has already eaten.

   AND HOW MUCH DITHER IS THREE NUMBERS, ONE PER CHANNEL. The wobble is
   one step of an RGB grid — 16 by 16 by 16, at the user's request, where
   it used to be one step of the lookup cube's own 32. Half a step either
   way, so at 16 a chunky pixel's threshold can move its colour a
   sixteenth of a channel before the snap: enough to turn a band the
   palette would have drawn as two flat colours into a checker of the
   two, coarser and more visible than it was, which is the look asked
   for. The sky bake adds the same step off the same function, so the
   sky's grain and the picture's are one grain (DITHER_LEVELS, below).

   WHICH FIXED SOMETHING NOBODY HAD NOTICED. The old pass ran at SCREEN
   resolution and worked out the Bayer index as floor(vUv * bufferSize)
   — the buffer texel this screen pixel is standing on. That is the right
   quantity and it was not always the right ANSWER: the hardware's
   nearest fetch does its own floor of the same product, in its own
   arithmetic, and on a 600-row window over a 400-row buffer that product
   lands on a whole number every other row. Where the two floors fell
   either side of it, a row of pixels got its neighbour's threshold. It
   was a row of dither one step out on a 256-colour picture, which is why
   it survived: nobody can see it, and diffing the frame with the dither
   turned off is what proves it was ever there. Computing both at grid
   fragment centres makes them the same number by construction.

   THREE PASSES, AND IT IS CHEAPER THAN THE TWO IT REPLACED. World into
   the buffer; buffer into the grid, averaged and dithered and snapped;
   grid onto the screen, nearest, no arithmetic at all. The palette
   search used to run once per SCREEN pixel — two million of them on a
   1080p monitor — and now runs once per chunky pixel, which at 320x200
   is sixty-four thousand.
   ===================================================================== */

import * as THREE from 'three';
import { buildLutAtlas, LUT_SIZE, displayDither, DISPLAY_PALETTES, DEFAULT_DISPLAY } from './palette.js';
import { Bloom } from './bloom.js';

/* How many samples the block average is allowed to take across one
   chunky pixel, per axis. Four is not arbitrary: at a ratio of four or
   less the taps land exactly on source texel centres and the average is
   a true box filter, and above it they land between texels and the
   bilinear fetch under each one covers the gap. Sixteen taps at grid
   resolution is nothing; sixteen at screen resolution would not be,
   which is the other reason this pass renders where it does. */
const MAX_TAPS = 4;

/* THE GRID THE DITHER IS ONE STEP OF, per channel: red, green, blue.
   The Bayer threshold adds half a step of this grid either way before
   the snap, so at 16 it spans a sixteenth of each channel — twice what
   it spanned at the lookup cube's 32, at the user's request. Three
   numbers and not one because a channel the eye is worse at could carry
   a coarser grain than one it is better at; in the box the game starts
   in all three are the same, and the shader divides by them per channel
   either way.

   IT IS THE STARTING BOX'S and not the pipeline's. The grid belongs to
   the palette the frame is snapped to — see DISPLAY_PALETTES in
   js/palette.js, where the reasoning is — and rebuildLut pushes the new
   one when the setting changes. This names the starting box rather than
   asking which box is current, because a module is evaluated once and
   whatever the setting happened to be at that moment would be frozen
   into it. The MATERIAL asks for the current one, below. */
export const DITHER_LEVELS = DISPLAY_PALETTES[DEFAULT_DISPLAY].dither;

/* A CEILING ON THE BUFFER'S WIDTH, for a window wider than any monitor.
   It is 4096 and not 2048 because the buffer is 960 rows tall by default
   now, and a 20:9 phone at 960 rows is 2133 across: clamp that and the
   camera's aspect — which is the BUFFER's, see below — drifts off the
   window's, and the whole world is drawn a couple of per cent wider
   than it is. Every WebGL device can hold a 4096 texture. */
const MAX_WIDTH = 4096;

/**
 * Every size the pipeline runs at, from the window and the two
 * controls. Pure arithmetic, and exported on purpose — this is where
 * the aspect ratio actually happens, and a function is something the
 * smoke test can hold against 320x200 without a GPU anywhere.
 *
 * @param displayW, displayH   the canvas, in real pixels
 * @param opts.height          RENDER: the buffer's height
 * @param opts.pixelHeight     PIXELS: the grid's height, or 0 for off,
 *                             in which case the grid IS the buffer
 * @param opts.pixelAspect     the width of one chunky pixel over its
 *                             height, as displayed. 1 is square; 5/6 is
 *                             Doom's; 2/3 is what the game ships with
 * @param opts.maxWidth        a ceiling, for very wide windows
 */
export function lofiSizes(displayW, displayH, opts = {}) {
  const dw = Math.max(1, Math.round(displayW)), dh = Math.max(1, Math.round(displayH));
  const aspect = dw / dh;
  const maxWidth = opts.maxWidth ?? MAX_WIDTH;

  /* the buffer: square pixels, so the camera's aspect is the window's */
  const height = Math.max(60, Math.round(opts.height ?? 200));
  const width = Math.min(maxWidth, Math.max(64, Math.round(height * aspect)));

  /* THE GRID IS NEVER FINER THAN THE BUFFER. Asking for more chunky
     pixels than there are rasterised ones does not make detail; it makes
     a finer grid of the same picture, and a readout claiming six hundred
     rows of a picture that has a hundred and twenty. So it is clamped,
     and the readout then shows what you are actually looking at, which
     is the honest thing for a number on a menu to do.

     AND WHEN THE CEILING BITES IT IS THE ROW COUNT THAT GIVES WAY, not
     the pixel's shape. Tall pixels need MORE columns than square ones at
     the same row count — that is what makes them tall — so clamping the
     width instead would quietly hand back square pixels, which is a
     control that looks like it is doing nothing. Taking rows off keeps
     the shape you asked for and says so in the second number.

     OFF IS OFF, and not "square". With no grid of its own there is
     nothing for an aspect to be the aspect OF: the grid is the buffer,
     exactly, and the filter below is a straight copy. */
  const pa = opts.pixelAspect > 0 ? opts.pixelAspect : 1;
  const want = opts.pixelHeight > 0 ? Math.round(opts.pixelHeight) : 0;
  let gridWidth = width, gridHeight = height;
  if (want > 0) {
    gridHeight = Math.max(30, Math.min(want, height));
    gridWidth = Math.max(16, Math.round(gridHeight * aspect / pa));
    if (gridWidth > width) {
      gridWidth = width;
      gridHeight = Math.max(30, Math.round(width * pa / aspect));
    }
  }

  /* HOW MANY SAMPLES PER CHUNKY PIXEL, which is the block's size in
     buffer texels, rounded. Rounding rather than rounding UP is
     deliberate: a ratio of 1.2 takes one sample and stays crisp, where
     two would soften a picture that is barely being filtered at all. */
  const taps = [
    Math.max(1, Math.min(MAX_TAPS, Math.round(width / gridWidth))),
    Math.max(1, Math.min(MAX_TAPS, Math.round(height / gridHeight))),
  ];
  return { width, height, gridWidth, gridHeight, taps };
}

const POST_VERT = /* glsl */`
precision highp float;
attribute vec3 position;
attribute vec2 uv;
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

/* THE SNAP AND THE DITHER, AS GLSL ANYBODY CAN SPLICE. The post pass
   below uses them on every chunky pixel; js/skyart.js uses the same
   two functions on every texel of the sky it bakes, so the sky is
   made of the same paint by the same hand. One definition. */
export const PALETTE_GLSL = /* glsl */`
uniform sampler2D tLut;
uniform float uLutSize;
uniform vec3  uDitherLevels;   // the RGB grid the dither is one step of — DITHER_LEVELS
/* 4x4 ordered Bayer, built the way Bayer matrices are actually defined:
   recursively out of the 2x2 one. M4(x,y) = 4*M2(low bits) + M2(high
   bits), where M2 is [[0,2],[3,1]] and works out to (2x+3y) mod 4. Four
   lines of arithmetic instead of a 16-entry uniform array and the
   dependent read that comes with it. */
float bayer2(float x, float y) { return mod(2.0 * x + 3.0 * y, 4.0); }

float bayer4(vec2 p) {
  vec2 f = mod(floor(p), 4.0);
  float lo = bayer2(mod(f.x, 2.0), mod(f.y, 2.0));
  float hi = bayer2(floor(f.x * 0.5), floor(f.y * 0.5));
  return 4.0 * lo + hi;                 // 0..15
}

/* THE WOBBLE, before the snap: the Bayer threshold at the cell, centred
   on zero, scaled by the amount, as a step of the RGB grid in
   uDitherLevels — a sixteenth of each channel at the shipped 16 16 16.
   The post pass adds exactly this to every chunky pixel and the sky
   bake to every cell of the sky, and neither adds anything else, so
   there is one grain. */
vec3 ditherAt(vec2 cell, float amount) {
  return vec3((bayer4(cell) / 15.0 - 0.5) * amount) / uDitherLevels;
}

/* Nearest palette entry, via the atlas: 32 slices of 32x32 side by side.
   Blue picks the slice, red is x within it, green is y. Sampled NEAREST,
   so this is a genuine snap and not a blend of two palette entries — a
   blend would put colours on screen that are not in the palette, which
   is the one thing this whole file exists to prevent. */
vec3 palSnap(vec3 c) {
  float N = uLutSize;
  c = clamp(c, 0.0, 1.0);
  float r = floor(c.r * (N - 1.0) + 0.5);
  float g = floor(c.g * (N - 1.0) + 0.5);
  float b = floor(c.b * (N - 1.0) + 0.5);
  vec2 uv = vec2((b * N + r + 0.5) / (N * N), (g + 0.5) / N);
  return texture2D(tLut, uv).rgb;
}

`;

const FILTER_FRAG = /* glsl */`
precision highp float;
uniform sampler2D tFrame;
uniform vec2  uFrameSize;     // the 3D buffer, in pixels
uniform vec2  uGridSize;      // the chunky pixel grid
uniform vec2  uTaps;          // samples across one chunky pixel, 1..4
uniform float uDither;        // 0 = off, ~1 = one palette step of wobble
uniform float uSnap;          // 0 = truecolour passthrough, 1 = full palette
uniform vec3  uPicture;       // brightness, contrast, gamma — all 1 for the picture as drawn
varying vec2 vUv;

${PALETTE_GLSL}

void main() {
  /* WHICH CHUNKY PIXEL THIS IS. The pass renders AT the grid's own
     resolution — one fragment is one chunky pixel — so this floor is
     exact rather than an approximation of one. */
  vec2 cell = floor(vUv * uGridSize);
  vec2 uv0 = cell / uGridSize;             // the block's corner, in uv
  vec2 span = 1.0 / uGridSize;             // and its size

  vec3 c;
  if (uTaps.x < 1.5 && uTaps.y < 1.5) {
    /* NOTHING TO AVERAGE: the grid is as fine as the buffer, or finer.
       One sample, SNAPPED to the middle of a source texel — the buffer
       is filtered linearly for the sake of the branch below, and a fetch
       at a texel's centre comes back as that texel exactly, so the
       promise of no smoothing survives the setting being off. */
    vec2 p = (uv0 + 0.5 * span) * uFrameSize;
    c = texture2D(tFrame, (floor(p) + 0.5) / uFrameSize).rgb;
  } else {
    /* THE BLOCK, AVERAGED. Taps spread evenly across it, which puts them
       on source texel centres exactly when the ratio is a whole number
       up to four; past that they fall between texels and the bilinear
       fetch under each tap covers what is skipped. */
    vec3 sum = vec3(0.0);
    float n = 0.0;
    for (int j = 0; j < 4; j++) {
      for (int i = 0; i < 4; i++) {
        vec2 t = vec2(float(i), float(j));
        if (t.x < uTaps.x && t.y < uTaps.y) {
          sum += texture2D(tFrame, uv0 + (t + 0.5) / uTaps * span).rgb;
          n += 1.0;
        }
      }
    }
    c = sum / n;
  }

  /* BRIGHTNESS, CONTRAST, GAMMA, at the user's request, and here — after
     the average and BEFORE the dither and the snap — for the reason
     Doom's own gamma keys worked the way they did: they changed the
     palette the picture was quantised to, not the picture after. A
     brighter picture should still be made of the same two hundred and
     fifty-six colours, and a lift applied after the snap would put
     colours on the screen the palette does not have. Contrast pivots on
     mid grey, brightness multiplies, gamma is the usual curve. */
  c = (c - 0.5) * uPicture.y + 0.5;
  c = max(c * uPicture.x, 0.0);
  c = pow(c, vec3(1.0 / max(uPicture.z, 0.05)));

  if (uDither > 0.0) {
    /* ON THE GRID and not on the buffer: one threshold per chunky pixel.
       A checker finer than the pixels is a checker the averaging above
       has already eaten. One step of the 16 16 16 grid — ditherAt, and
       DITHER_LEVELS above the shader. */
    c += ditherAt(vUv * uGridSize, uDither);
  }

  vec3 snapped = palSnap(c);
  gl_FragColor = vec4(mix(c, snapped, uSnap), 1.0);
}
`;

/* The last pass does nothing but make the squares big — and multiply
   by uTint, which is white (nothing) except on the title, where it is
   the blue the forest is washed with: AFTER the palette snap, at the
   user's request, because the palette has no blue that saturated and
   the wash is to be the logo's own. */
const BLIT_FRAG = /* glsl */`
precision highp float;
uniform sampler2D tGrid;
uniform vec3 uTint;
varying vec2 vUv;
void main() { gl_FragColor = vec4(texture2D(tGrid, vUv).rgb * uTint, 1.0); }
`;

export class LofiPipeline {
  /**
   * @param {THREE.WebGLRenderer} renderer
   * @param {object} opts
   *   height       RENDER: the 3D buffer's vertical resolution
   *   pixelHeight  PIXELS: the chunky grid's height; 0 leaves the grid
   *                equal to the buffer, which is the old behaviour
   *   pixelAspect  the width of one chunky pixel over its height
   *   dither       ordered-dither strength before the palette snap
   *   snap         0..1 blend toward the palette; 1 is the honest answer
   */
  constructor(renderer, opts = {}) {
    this.renderer = renderer;
    this.height = opts.height ?? 200;
    this.pixelHeight = opts.pixelHeight ?? 0;
    this.pixelAspect = opts.pixelAspect ?? 1;
    this.maxWidth = opts.maxWidth ?? MAX_WIDTH;

    /* THE BUFFER. Filtered LINEARLY, which reads like a betrayal of the
       whole file and is not: every fetch out of it is either a block
       average, where linear is the point, or a sample snapped to a texel
       centre, where linear returns that texel exactly. Nearest would
       make the first case a point sample and the second no better. */
    this.target = new THREE.WebGLRenderTarget(320, this.height, {
      minFilter: THREE.LinearFilter,
      magFilter: THREE.LinearFilter,
      format: THREE.RGBAFormat,
      type: THREE.UnsignedByteType,
      depthBuffer: true,
      stencilBuffer: false,
    });
    this.target.texture.generateMipmaps = false;
    /* ITS DEPTH AS A TEXTURE, so the bloom can tell a lamp that is in
       view from one behind a wall — see js/bloom.js */
    this.target.depthTexture = new THREE.DepthTexture(320, this.height);
    this.bloom = new Bloom();

    /* THE GRID, which is what you are actually looking at. Nearest both
       ways, because the only thing that ever happens to it is being
       blown up to the size of the window. */
    this.grid = new THREE.WebGLRenderTarget(320, this.height, {
      minFilter: THREE.NearestFilter,
      magFilter: THREE.NearestFilter,
      format: THREE.RGBAFormat,
      type: THREE.UnsignedByteType,
      depthBuffer: false,
      stencilBuffer: false,
    });
    this.grid.texture.generateMipmaps = false;

    /* The palette, as a texture. Built once — 32768 nearest-colour
       searches, about 40ms, and then never again. */
    const atlas = buildLutAtlas();
    this.lut = new THREE.DataTexture(atlas.data, atlas.width, atlas.height, THREE.RGBAFormat);
    this.lutData = atlas.data;
    this.lut.minFilter = THREE.NearestFilter;
    this.lut.magFilter = THREE.NearestFilter;
    this.lut.wrapS = this.lut.wrapT = THREE.ClampToEdgeWrapping;
    this.lut.generateMipmaps = false;
    this.lut.needsUpdate = true;

    this.material = new THREE.RawShaderMaterial({
      uniforms: {
        tFrame:     { value: this.target.texture },
        tLut:       { value: this.lut },
        uFrameSize: { value: new THREE.Vector2(320, this.height) },
        uGridSize:  { value: new THREE.Vector2(320, this.height) },
        uTaps:      { value: new THREE.Vector2(1, 1) },
        uDither:    { value: opts.dither ?? 1.0 },
        uDitherLevels: { value: new THREE.Vector3(...displayDither()) },
        uLutSize:   { value: LUT_SIZE },
        uSnap:      { value: opts.snap ?? 1.0 },
        uPicture:   { value: new THREE.Vector3(1, 1, 1) },
      },
      vertexShader: POST_VERT,
      fragmentShader: FILTER_FRAG,
      depthTest: false,
      depthWrite: false,
    });

    this.blitMaterial = new THREE.RawShaderMaterial({
      uniforms: { tGrid: { value: this.grid.texture }, uTint: { value: new THREE.Color(1, 1, 1) } },
      vertexShader: POST_VERT,
      fragmentShader: BLIT_FRAG,
      depthTest: false,
      depthWrite: false,
    });
    /** the colour the finished frame is multiplied by; white is none */
    this.tint = this.blitMaterial.uniforms.uTint.value;

    /* One triangle, not two. A full-screen triangle has no seam down the
       diagonal and shades every pixel exactly once. Both passes draw it,
       so there is one of it and the material is swapped. */
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    geo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
    this.quad = new THREE.Mesh(geo, this.material);
    this.quad.frustumCulled = false;
    this.postScene = new THREE.Scene();
    this.postScene.add(this.quad);
    this.postCamera = new THREE.Camera();

    this.width = 320;
    this.gridWidth = 320;
    this.gridHeight = this.height;
    this.taps = [1, 1];
    this.displayW = 640;
    this.displayH = 400;
  }

  /* Called on resize, and whenever either control moves. Returns the
     sizes the rest of the game needs: the buffer, which is what the
     camera's aspect comes off, and the grid, which is what an overlay
     is laid out in and what the geometry LOD calls a visible pixel. */
  resize(displayW, displayH) {
    this.displayW = Math.max(1, displayW);
    this.displayH = Math.max(1, displayH);
    const s = lofiSizes(this.displayW, this.displayH, this);
    if (s.width !== this.width || s.height !== this.target.height) {
      this.target.setSize(s.width, s.height);
      this.material.uniforms.uFrameSize.value.set(s.width, s.height);
    }
    if (s.gridWidth !== this.gridWidth || s.gridHeight !== this.gridHeight) {
      this.grid.setSize(s.gridWidth, s.gridHeight);
      this.material.uniforms.uGridSize.value.set(s.gridWidth, s.gridHeight);
    }
    this.width = s.width;
    this.height = s.height;
    this.gridWidth = s.gridWidth;
    this.gridHeight = s.gridHeight;
    this.taps = s.taps;
    this.material.uniforms.uTaps.value.set(s.taps[0], s.taps[1]);
    this.renderer.setSize(this.displayW, this.displayH, false);
    return s;
  }

  /**
   * REBUILD THE LOOKUP CUBE, because the box of crayons changed.
   *
   * This texture is how the post pass snaps a frame to the palette —
   * one fetch per pixel instead of searching 256 entries — so it is
   * the palette, as far as the GPU is concerned. Rewritten in place
   * rather than replaced, because the sky baker was handed this exact
   * texture object at start-up (see SkyBaker) and holding the two in
   * step by hand is a thing to get wrong once and never notice.
   */
  rebuildLut() {
    const atlas = buildLutAtlas();
    this.lutData.set(atlas.data);
    this.lut.needsUpdate = true;
    /* and the dither aims at the same box it snaps to, or it is spraying
       a sixteenth of a channel at gaps three times that wide */
    const d = displayDither();
    this.material.uniforms.uDitherLevels.value.set(d[0], d[1], d[2]);
    return this.lut;
  }

  /** RENDER: how much the world is drawn with. */
  setHeight(h) {
    this.height = Math.max(60, Math.round(h));
    return this.resize(this.displayW, this.displayH);
  }

  /** PIXELS: how big one of them is. 0, or anything false, is off — the
   *  grid becomes the buffer and the filter is a straight copy. */
  setPixels(h) {
    this.pixelHeight = h > 0 ? Math.round(h) : 0;
    return this.resize(this.displayW, this.displayH);
  }

  /** The three picture dials, each 1 for the picture as drawn. Applied
   *  before the palette snap — see uPicture in the shader. */
  setPicture({ brightness = 1, contrast = 1, gamma = 1 } = {}) {
    this.material.uniforms.uPicture.value.set(brightness, contrast, gamma);
  }

  /** The width of one chunky pixel over its height, as displayed. */
  setPixelAspect(a) {
    this.pixelAspect = a > 0 ? a : 1;
    return this.resize(this.displayW, this.displayH);
  }

  /* The camera's, and therefore the world's. The BUFFER's shape and not
     the grid's: the grid is a quantisation of a finished frame and has
     no say in what the frame contains. */
  get aspect() { return this.width / this.height; }

  /* Whether the pixel filter is doing anything at all. */
  get filtering() { return this.taps[0] > 1 || this.taps[1] > 1; }

  /**
   * World first, then each overlay on top of it in turn, all into the
   * buffer; the buffer down onto the grid, averaged and dithered and
   * snapped; the grid onto the screen. Every overlay clears depth but
   * not colour, so the gun draws over the world and the wash over the
   * gun without anybody's depth values fighting.
   *
   * `overlays` is a list of { scene, camera }; a null entry, or one
   * marked visible: false, is skipped — which is how a scene that has
   * not finished loading stays out of the frame without a branch at the
   * call site.
   */
  render(scene, camera, overlays = []) {
    const r = this.renderer;
    r.setRenderTarget(this.target);
    r.clear(true, true, true);
    r.render(scene, camera);
    /* WHAT THE WORLD COST, kept before anything else overwrites it.
       renderer.info is reset at every render() call, and this method
       makes four of them — the world, the overlays, the post pass and
       the blit — so by the time the frame is over the counter reads 1,
       which is the blit's own quad. That is the number the FPS readout
       in js/main.js was showing, and "1 draws" is not a useful thing to
       tell somebody whose frame rate is the reason they turned the
       readout on. */
    this.sceneCalls = r.info.render.calls;
    this.sceneTris = r.info.render.triangles;
    /* WHAT LIES ON THE WORLD: the decals, drawn as boxes against the
       depth the world has just left — see js/decals.js, Decals.draw */
    if (this.afterWorld) this.afterWorld(r, camera, this.target);
    /* THE GLOW, between the world and the overlays: against the world's
       depth, and under the gun — see js/bloom.js */
    this.bloom.render(r, scene, camera, this.target);
    for (const o of overlays) {
      if (!o || !o.scene || !o.camera || o.visible === false) continue;
      r.clearDepth();
      r.render(o.scene, o.camera);
    }
    this.quad.material = this.material;
    r.setRenderTarget(this.grid);
    r.clear(true, true, true);
    r.render(this.postScene, this.postCamera);
    this.quad.material = this.blitMaterial;
    r.setRenderTarget(null);
    r.clear(true, true, true);
    r.render(this.postScene, this.postCamera);
  }
}
