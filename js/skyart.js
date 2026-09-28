/* =====================================================================
   MEWD — the sky, baked in the page
   =====================================================================

   The sky used to be the one picture in the game that was a
   photograph: a Polyhaven night, baked to the palette offline by
   tools/bake-sky.mjs. A night is fine as a photograph. A dawn is not,
   because there are forty of them between two in the morning and six.
   So the sky is generated here, at start-up and then again whenever
   the hour has moved enough to show, the way every other picture in
   the game is generated — and the photograph is gone.

   IT IS STILL A BAKED PICTURE, and that is the whole architecture. It
   would be simpler to evaluate the sky per fragment on the sphere. It
   would also be wrong, for the reason bake-sky.mjs already gave: the
   post pass dithers in GRID space, so a sky computed per fragment gets
   a dither pattern nailed to the screen that crawls across the stars
   every time you turn your head. A picture is dithered ONCE, in its own
   texels, and the pattern is nailed to the sky. So this bakes into a
   4096 x 1024 equirect, on the GPU, with the same Bayer and the same
   palette snap the post pass uses (js/lofi.js exports them), and the
   sphere in js/sky.js wears the result exactly as it wore the PNG.

   FOUR TIMES THE PHOTOGRAPH'S 1024 x 256 IN EACH DIRECTION, in two
   doublings and both at the user's request, and what got finer each
   time is THE PAINT AND NOT THE GRAIN.

   THE NUMBER THAT MATTERS IS A CHUNKY PIXEL. The game ships 320 rows
   of them over a 72-degree view, which is one every 0.225 degrees tall
   and 0.15 wide, and a sky texel coarser than that is a sky visibly
   blockier than the picture in front of it. This picture is 4:1 rather
   than an equirect's usual 2:1 — it is mostly sky and a little ground
   — so its two axes are not the same, and both are worth writing down:

                      across            up and down
     1024 x 256       0.352 deg         0.703 deg
     2048 x 512       0.176             0.352
     4096 x 1024      0.088             0.176

   The first doubling fixed the horizontal and left the VERTICAL still
   coarser than a pixel is tall — 0.352 against 0.225 — and that is the
   axis the horizon, the sun's lower limb and the cloud bases all lie
   along, which is where the blockiness that was left came from. At
   4096 x 1024 both axes are finer than a chunky pixel with room over.

   THE TWO GRIDS THAT DID NOT MOVE, and this is the whole trick:

     THE BAYER THRESHOLD is worked out on 1024 x 256 CELLS (SKY_CELL,
     now four texels square), because a checker finer than a chunky
     pixel is a checker the post pass's averaging eats, and what is
     left of it is the post pass's own dither nailed to the SCREEN —
     which is the crawl this file exists to prevent.

     A STAR IS ONE CHUNKY PIXEL, so the stars are worked out on 2048 x
     512 CELLS (STAR_CELL, two texels square), which is the grid they
     were already on. Left on the fine grid they would be a quarter of
     a pixel each, and a quarter-pixel star does not come out of the
     post pass as a smaller sharper star — it comes out as a DIM
     SMUDGE, because the averaging spreads it across the whole pixel at
     a quarter the brightness. So the paint got finer and the stars did
     not move: the same count, the same size on screen, the same light.

   AND IT IS CLAMPED TO WHAT THE MACHINE HAS. SKY_W and SKY_H are what
   this asks for; the baker asks the renderer for MAX_TEXTURE_SIZE and
   builds its shader for whatever it actually got. Both grids above are
   fractions of the real size rather than numbers, so a machine that
   can only give 2048 gets exactly the sky this had before — the same
   grain, the same stars, half the paint — rather than a render target
   it cannot make and a black sky.

   AND THE FOG READS THE SAME TEXELS. The world shader samples this
   texture's horizon row in the fragment's own azimuth for the colour
   the air fades a far wall to (see worldShade in js/material.js). Not
   a colour tuned to look like the sky: the sky. They cannot disagree,
   because there is nothing to keep in agreement.

   WHAT IS IN IT
     a ramp        horizon to zenith, and a ground below the horizon
                     that starts as the horizon's own colour so the
                     far plane's cut has nothing to show
     the sun       a disc, and a glow along the horizon on its side,
                     which at 05:10 IS the dawn
     the moon      a disc a couple of degrees across — half a degree
                     would be one texel here — and a soft halo
     the stars     one texel each, on a hash of the texel, thinned
                     toward the zenith where an equirect bunches them,
                     and a band across them with more in it
     the clouds    value noise on a plane over your head, drifting
                     with the wind, lit by the dawn from its side and
                     by the town from below, and taking the stars away
     the town      a sodium glow low in the west
   Everything is in byte space until the last line, which snaps it to
   the palette and converts to linear, because that is what a palette
   PNG sampled by the GPU would have handed the buffer.

   THE COORDINATES. A texel (u, v) is the world direction the sphere
   shows at that texel: u is the azimuth, atan2(z, x) over a full turn
   in the RENDERER's axes (its z is the map's minus y), and v is the
   elevation, with the horizon at one half. That mapping was measured
   against three's SphereGeometry with the mesh's x mirrored, not
   derived, and js/material.js uses the same formula to find the
   horizon texel for the fog.
   ===================================================================== */

import * as THREE from 'three';
import { PALETTE_GLSL } from './lofi.js';
import { LUT_SIZE, toLinear, displayDither } from './palette.js';

/* WHAT THE SKY ASKS FOR. What it gets may be less — see the clamp in
   SkyBaker — and everything below is a FRACTION of the real size rather
   than a number of texels, so that less still comes out right. */
export const SKY_W = 4096, SKY_H = 1024;
/* THE GRID THE DITHER IS WORKED OUT ON: 1024 x 256 cells, the size the
   sky was before either doubling, so the grain is the grain it was and
   survives the post pass's averaging. */
export const DITHER_GRID_W = 1024;
/* AND THE GRID THE STARS ARE ON: 2048 x 512, so a star stays one chunky
   pixel. See the header for why a finer star is a worse star. */
export const STAR_GRID_W = 2048;
/* The two as texels, at the size this asks for. The baker works them
   out again for the size it actually got. */
export const SKY_CELL = SKY_W / DITHER_GRID_W;
export const STAR_CELL = SKY_W / STAR_GRID_W;

const VERT = /* glsl */`
precision highp float;
attribute vec3 position;
attribute vec2 uv;
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }
`;

/* THE SHADER IS BUILT FOR THE SIZE THE BAKER ACTUALLY GOT, because two
   things in it are grids rather than smooth functions — the Bayer
   threshold and the stars — and both are fractions of the real picture.
   See the header. */
const FRAG = (W, H, cell, starCell) => /* glsl */`
precision highp float;
uniform vec3  uZenith, uHorizon, uGround;
uniform vec3  uMid;
uniform float uMidAmt, uMidPow;
uniform float uSnapAmt;
uniform vec3  uSunDir, uSunCol, uGlow;
uniform float uGlowAmt, uSunUp;
uniform vec3  uMoonDir;
uniform float uMoonAmt;
uniform vec3  uTownDir;
uniform float uTown;
uniform float uStars, uMilky, uDaylight;
uniform float uCover, uCloudDark, uFlat, uCloudTime;
uniform vec2  uWind;
uniform float uDither;
uniform float uSeed;
varying vec2 vUv;
${PALETTE_GLSL}

const float PI = 3.14159265;

/* the direction this texel looks in — see the header for the mapping */
vec3 dirOf(vec2 uv) {
  float phi = uv.x * 2.0 * PI;
  float e = (uv.y - 0.5) * PI;
  float c = cos(e);
  return vec3(cos(phi) * c, sin(e), sin(phi) * c);
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + uSeed) * 43758.5453); }

/* A HASH WITH THE WHOLE FLOAT UNDER IT, for the stars. The sine hash
   above is fine for cloud noise and useless for a rare event: in a
   32-bit float the product sin(x) * 43758 has a last place of about
   0.004, so fract of it takes about 256 distinct values, and a
   threshold band of 0.0035 — a star every three hundred texels — is
   narrower than one step of it. Measured in the bake, one-texel stars
   on that hash came out as FOUR texels in the whole sky. This one
   (Hoskins' hash without a sine in it) is even to the fifth decimal,
   and the same seed still moves the same stars. */
float hashStar(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33) + uSeed;
  return fract((p3.x + p3.y) * p3.z);
}

/* value noise, smooth, two octaves short of the CPU one in js/pixel.js
   because a cloud is a soft thing */
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash2(i), b = hash2(i + vec2(1.0, 0.0)), c = hash2(i + vec2(0.0, 1.0)), d = hash2(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
  float v = 0.0, amp = 0.5;
  for (int o = 0; o < 4; o++) { v += vnoise(p) * amp; p = p * 2.03 + vec2(17.0, 9.0); amp *= 0.5; }
  return v;
}

void main() {
  vec3 dir = dirOf(vUv);
  float e = dir.y;                                     // sine of the elevation
  vec3 hd = normalize(vec3(dir.x, 0.0, dir.z));        // where on the horizon

  /* THE RAMP. Above the horizon, horizon to zenith with most of the
     change low down; below it, the horizon's own colour for the first
     few degrees and then the ground. In mist the sky is one colour. */
  float up = clamp(e, 0.0, 1.0);
  vec3 col = mix(uHorizon, uZenith, pow(up, 0.55));
  /* AND A MIDDLE, for a sky that was given three colours rather than
     two — see the sky override in js/weather.js. Two stops can only ever be a
     fade from one colour to another, and a green horizon under a black
     zenith wants to spend most of its height being DARK GREEN, which is
     a third colour and not a point on the line between the other two.
     uMidAmt is 0 for every sky that did not ask, and then this is the
     two-stop ramp above, unchanged, to the bit. */
  if (uMidAmt > 0.0) {
    float t3 = pow(up, uMidPow);
    vec3 three = t3 < 0.5 ? mix(uHorizon, uMid, t3 * 2.0)
                          : mix(uMid, uZenith, t3 * 2.0 - 1.0);
    col = mix(col, three, uMidAmt);
  }
  col = mix(col, uHorizon, uFlat);
  col = mix(col, uGround, smoothstep(0.0, 0.08, -e));

  /* THE SUN'S GLOW ALONG THE HORIZON. Strongest straight toward the
     sun, dying off away from it and up from it. Under a dozen degrees
     of sun this is the whole dawn. */
  vec3 sd = normalize(vec3(uSunDir.x, 0.0, uSunDir.z));
  float toward = max(dot(hd, sd), 0.0);
  float glow = pow(toward, 3.0) * exp(-max(e, 0.0) * 7.0) * uGlowAmt * (1.0 - uFlat * 0.5);
  col += uGlow * glow;

  /* THE TOWN, low in the west, sodium orange, whatever the hour */
  float townGlow = pow(max(dot(hd, uTownDir), 0.0), 5.0) * exp(-max(e, 0.0) * 10.0) * uTown;
  col += vec3(0.42, 0.30, 0.12) * townGlow;

  /* THE SUN ITSELF: a tight corona, a wide faint glow and a disc, only
     once it is over the line. The corona was one wide term at first and
     at eight in the morning it was a white blob a third of the sky
     across, snapped into cyan. */
  float ca = dot(dir, uSunDir);
  col += uSunCol * (pow(max(ca, 0.0), 300.0) * 0.7 + pow(max(ca, 0.0), 10.0) * 0.08) * uSunUp;
  float disc = smoothstep(cos(0.016), cos(0.010), ca) * uSunUp;
  col = mix(col, uSunCol * 1.15, disc);

  /* THE MOON: two degrees across, which is four times life size and
     the smallest thing that reads as a moon at this many texels */
  float cm = dot(dir, uMoonDir);
  float halo = pow(max(cm, 0.0), 60.0) * 0.22 * uMoonAmt;
  float mdisc = smoothstep(cos(0.020), cos(0.016), cm) * uMoonAmt;
  col += vec3(0.62, 0.66, 0.78) * halo;
  col = mix(col, vec3(0.86, 0.87, 0.90) * (1.0 - uDaylight * 0.4), mdisc);

  /* THE CLOUDS. Noise on a plane over your head, so they are big
     overhead and crowd toward the horizon the way clouds do, drifting
     with the wind. Thin at the horizon, where a real sky's clouds are
     lost in the air. */
  vec2 cp = dir.xz / max(e, 0.10) * 1.6 + uWind * uCloudTime * 0.012 + vec2(3.7, 1.9);
  float n = fbm(cp);
  float cloud = smoothstep(1.0 - uCover, 1.0 - uCover + 0.35, n) * smoothstep(0.0, 0.14, e);
  cloud *= 1.0 - uFlat;
  /* what a cloud is lit by: a little of the sky it sits in, the dawn
     from the side, the town from below, and the day, when there is one */
  vec3 cloudCol = mix(uZenith * 1.5 + vec3(0.025), uHorizon, 0.45) * uCloudDark;
  cloudCol += uGlow * glow * 1.4 + uSunCol * pow(max(ca, 0.0), 4.0) * 0.30 * uSunUp;
  cloudCol += vec3(0.42, 0.30, 0.12) * townGlow * 1.6;
  cloudCol = mix(cloudCol, vec3(0.84, 0.86, 0.90) * uCloudDark, uDaylight * 0.85);
  /* the underside of a thick cloud is darker than its edge */
  cloudCol *= 1.0 - 0.35 * smoothstep(0.3, 1.0, cloud);

  /* THE STARS: a hash of the cell, ONE CHUNKY PIXEL each, thinned by
     the cosine of the elevation because an equirect has as many texels
     round the zenith as round the horizon and the sky does not. And a
     band across them — the Milky Way — with more of them in it.

     ON THEIR OWN GRID AND NOT THE PICTURE'S. A star is worked out on
     2048 x 512 cells however fine the paint is, because that is one
     chunky pixel at the size the game ships, and a star smaller than a
     pixel is not a finer star — the post pass averages it across the
     whole pixel and what is left is a dim smudge. So the density here
     is per CELL and has not changed since the sky was 2048 wide: the
     same count, the same size on screen, the same light. */
  vec2 cell = floor(vUv * vec2(${W / starCell}.0, ${H / starCell}.0));
  float h = hashStar(cell + 0.5);
  vec3 bandN = normalize(vec3(0.30, 0.55, 0.78));
  float band = 1.0 - smoothstep(0.0, 0.24, abs(dot(dir, bandN)));
  float density = 0.0035 * max(cos((vUv.y - 0.5) * PI), 0.0) * (1.0 + band * 2.5);
  float star = step(1.0 - density, h) * (0.35 + 0.65 * fract(h * 77.7));
  star *= smoothstep(0.005, 0.03, e) * uStars * (1.0 - cloud) * (1.0 - disc) * (1.0 - mdisc);
  vec3 milky = vec3(0.22, 0.23, 0.32) * band * (0.5 + 0.5 * fbm(dir.xz * 5.0 + dir.y * 3.0)) * uMilky * smoothstep(0.0, 0.05, e);
  col += milky * (1.0 - cloud);
  col += vec3(0.80, 0.84, 1.00) * star;

  col = mix(col, cloudCol, cloud);

  /* THE PAINT. Dithered in the sky's own cells — one Bayer threshold
     per dither cell, the grain the 1024-wide sky had — off the same
     16 16 16 step as the post pass; snapped to the palette; and then
     linear. See the header for why each. */
  /* AND THE SNAP IS ON A DIAL, because a world drawn in full colour
     wants a sky in full colour: at 1 this is the 256-colour sky the
     rest of this comment describes, and at 0 the gradient is left
     exactly as it was computed. The dither goes with it — a wobble
     aimed at a box of crayons nobody is reaching for is just noise. */
  vec3 raw = clamp(col, 0.0, 1.0);
  vec3 snapped = mix(raw,
    palSnap(clamp(col + ditherAt(floor(gl_FragCoord.xy / ${cell}.0), uDither), 0.0, 1.0)),
    uSnapAmt);
  vec3 lin = pow((snapped + 0.055) / 1.055, vec3(2.4));
  lin = mix(snapped / 12.92, lin, step(0.04045, snapped));
  gl_FragColor = vec4(lin, 1.0);
}
`;


/* a map compass direction (0 east, a quarter turn north) and an
   altitude, as a unit vector in the renderer's axes */
function dirOf(az, altDeg) {
  const a = altDeg * Math.PI / 180, c = Math.cos(a);
  return new THREE.Vector3(Math.cos(az) * c, Math.sin(a), -Math.sin(az) * c);
}

export class SkyBaker {
  /**
   * @param renderer  the WebGLRenderer
   * @param lut       the palette atlas texture the post pass already built
   * @param opts.seed where the stars are; the same seed is the same sky
   */
  constructor(renderer, lut, opts = {}) {
    this.renderer = renderer;
    /* AS MUCH SKY AS THE MACHINE WILL GIVE. SKY_W is what this asks
       for; a render target wider than MAX_TEXTURE_SIZE is one the
       driver refuses, and what you get for asking anyway is a black
       sky on exactly the sort of device that cannot spare a debugging
       session. Halved until it fits, so the aspect is kept and both
       grids below stay whole numbers of texels — and a machine that
       can only give 2048 gets the sky this had before. */
    const maxTex = renderer?.capabilities?.maxTextureSize ?? SKY_W;
    let w = SKY_W, h = SKY_H;
    while (w > maxTex && w > STAR_GRID_W) { w /= 2; h /= 2; }
    this.width = w; this.height = h;
    /* the two grids, in texels of the picture it actually got */
    this.cell = Math.max(1, w / DITHER_GRID_W);
    this.starCell = Math.max(1, w / STAR_GRID_W);
    this.target = new THREE.WebGLRenderTarget(w, h, {
      minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter,
      wrapS: THREE.RepeatWrapping, wrapT: THREE.ClampToEdgeWrapping,
      format: THREE.RGBAFormat, type: THREE.UnsignedByteType,
      depthBuffer: false, stencilBuffer: false, generateMipmaps: false,
    });
    this.target.texture.name = 'sky-bake';
    this.texture = this.target.texture;

    const V3 = THREE.Vector3;
    this.material = new THREE.RawShaderMaterial({
      uniforms: {
        /* a little over half the post pass's dither: the frame is
           dithered again on the way to the screen, and the two at full
           strength made the dawn a crosshatch */
        tLut: { value: lut }, uLutSize: { value: LUT_SIZE }, uDither: { value: 0.6 },
        uDitherLevels: { value: new V3(...displayDither()) },
        uSeed: { value: opts.seed ?? 0.0 },
        uZenith: { value: new V3() }, uHorizon: { value: new V3() }, uGround: { value: new V3() },
        uMid: { value: new V3() }, uMidAmt: { value: 0 }, uMidPow: { value: 1 },
        uSnapAmt: { value: 1 },
        uSunDir: { value: new V3(1, 0, 0) }, uSunCol: { value: new V3() }, uGlow: { value: new V3() },
        uGlowAmt: { value: 0 }, uSunUp: { value: 0 },
        uMoonDir: { value: new V3(0, 1, 0) }, uMoonAmt: { value: 1 },
        uTownDir: { value: new V3(-1, 0, 0) }, uTown: { value: 0 },
        uStars: { value: 1 }, uMilky: { value: 1 }, uDaylight: { value: 0 },
        uCover: { value: 0 }, uCloudDark: { value: 1 }, uFlat: { value: 0 }, uCloudTime: { value: 0 },
        uWind: { value: new THREE.Vector2(0, 0) },
      },
      vertexShader: VERT,
      fragmentShader: FRAG(this.width, this.height, this.cell, this.starCell),
      depthTest: false, depthWrite: false,
    });
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    geo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
    this.quad = new THREE.Mesh(geo, this.material);
    this.quad.frustumCulled = false;
    this.scene = new THREE.Scene();
    this.scene.add(this.quad);
    this.camera = new THREE.Camera();

    this.bakes = 0;
    this._lastBake = -1e9;
    this._lastHour = null;
    this._lastKind = null;
  }

  /** Set every uniform from a weather frame — see sampleFrame in
   *  js/weather.js — and draw the sky into the target. */
  bake(f) {
    const u = this.material.uniforms;
    const set3 = (k, c) => u[k].value.set(c[0], c[1], c[2]);
    set3('uZenith', f.zenith); set3('uHorizon', f.horizon); set3('uGround', f.ground);
    set3('uMid', f.mid || f.horizon);
    u.uMidAmt.value = f.mid ? (f.midAmt ?? 1) : 0;
    u.uMidPow.value = f.midPow ?? 1;
    u.uSnapAmt.value = f.snap ?? 1;
    set3('uSunCol', f.sunCol); set3('uGlow', f.glow);
    u.uSunDir.value.copy(dirOf(f.sunAz, f.sunAlt));
    u.uGlowAmt.value = f.glowAmt;
    /* the disc and its halo arrive over about a degree either side of
       the horizon rather than popping */
    u.uSunUp.value = Math.max(0, Math.min(1, (f.sunAlt + 0.6) / 1.2));
    u.uMoonDir.value.copy(dirOf(f.moonAz, f.moonAlt));
    u.uMoonAmt.value = f.moonAlt > -2 ? Math.max(0, Math.min(1, (f.moonAlt + 2) / 4)) * (1 - f.cover * 0.5) * (1 - f.flat) : 0;
    u.uTownDir.value.copy(dirOf(Math.PI, 0));
    u.uTown.value = f.town;
    u.uStars.value = f.stars; u.uMilky.value = f.milky; u.uDaylight.value = f.daylight;
    u.uCover.value = f.cover; u.uCloudDark.value = f.cloudDark; u.uFlat.value = f.flat;
    u.uCloudTime.value = f.cloudTime;
    u.uWind.value.set(f.wind[0], -f.wind[1]);     // map y is the renderer's minus z
    /* THE SAME GRAIN AS THE PASS IN FRONT OF IT, including when the box
       the screen holds has changed since the last bake: the grid is the
       box's, not the pipeline's, and a bake is the only place the sky
       can be told. */
    const d = displayDither();
    u.uDitherLevels.value.set(d[0], d[1], d[2]);

    const r = this.renderer;
    const prev = r.getRenderTarget();
    r.setRenderTarget(this.target);
    r.render(this.scene, this.camera);
    r.setRenderTarget(prev);
    this.bakes++;
    this._lastHour = f.hour; this._lastKind = f.kind; this._lastSmoke = f.smoke || 0;
    return this.texture;
  }

  /** Bake again only when it would show: the hour has moved, the
   *  weather has changed, or there is cloud and it has drifted. At most
   *  twice a second — four megapixels each time now, which is a
   *  fraction of a millisecond on anything that can run the game at
   *  all, and a sky that steps twice a second is a sky in a game whose
   *  world steps thirty-five times a second. */
  update(f, nowSeconds) {
    const since = nowSeconds - this._lastBake;
    const moved = this._lastHour === null || Math.abs(f.hour - this._lastHour) > 0.004 || f.kind !== this._lastKind
      || Math.abs((f.smoke || 0) - (this._lastSmoke || 0)) > 0.015;
    const drifting = f.cover > 0 && since > 0.5;
    if (!(moved || drifting) || since < 0.25) return false;
    this._lastBake = nowSeconds;
    this.bake(f);
    return true;
  }
}

/** The horizon colour the fog will use for a given azimuth, worked out
 *  the way the shader does it — the ramp at the horizon plus the sun's
 *  and the town's glow — in LINEAR, so a headless test can hold the
 *  air against the sky without a GPU. It is the ramp and the glows
 *  only: a star or a cloud edge on the horizon row is a texel the fog
 *  also reads, and is the sky agreeing with itself either way. */
export function horizonColour(f, az) {
  const hd = [Math.cos(az), -Math.sin(az)];
  const sd = [Math.cos(f.sunAz), -Math.sin(f.sunAz)];
  const toward = Math.max(hd[0] * sd[0] + hd[1] * sd[1], 0);
  const glow = Math.pow(toward, 3) * f.glowAmt * (1 - f.flat * 0.5);
  const td = [Math.cos(Math.PI), -Math.sin(Math.PI)];
  const town = Math.pow(Math.max(hd[0] * td[0] + hd[1] * td[1], 0), 5) * f.town;
  const c = [0, 1, 2].map(i => f.horizon[i] + f.glow[i] * glow + [0.42, 0.30, 0.12][i] * town);
  return toLinear(c.map(v => Math.max(0, Math.min(1, v))));
}
