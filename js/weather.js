/* =====================================================================
   MEWD — the clock, the weather and the wind
   =====================================================================

   One state, read by everybody, so that the hour the sky says it is,
   the distance the air lets you see, the direction the smoke drifts
   and the rain that is falling on a burning car park are one fact and
   not four. See SIGHT.txt for why it is built this way.

   TIME OF DAY IS ONE NUMBER, the hour, and everything below is a table
   lookup on it: five or six keyframes across the night, interpolated.
   The judgement — what colour 05:10 is — lives in the table, in
   Javascript, where a headless test can read it. The shader gets
   uniforms and does arithmetic.

   THE GAME IS A NIGHT, so the clock is a night. It starts at two in the
   morning, which is the hour the game has always been set at, and runs
   at a rate that brings the sun up in about nine minutes of play — you
   have until dawn. A full day is more rows in the same table.

   WEATHER IS A ROW multiplied over the hour's row: how far the air lets
   you see (which is also the draw distance — see airFar), how much sky
   is left, whether there is cloud over the stars, whether it rains,
   and which way the wind blows.

   THE WIND WAS WIND_X = 0.28 in js/effects.js, read by three smoke
   emitters and nothing else, with a comment claiming the forest leaned
   with it. It is a vector here now, and the smoke, the rain, the
   store's fire and the wood's fire all read the same two numbers.

   COLOURS ARE WRITTEN AS BYTES — hex, the way anybody picks a colour —
   and are converted to linear where they go into a shader, because
   everything in this renderer's buffer is linear.
   ===================================================================== */

import { world } from './material.js';
import { TICRATE } from './util.js';

/* --------------------------------------------------------------------
   The night, in keyframes

   sunAlt is the sun's altitude in degrees; below about -18 it does
   nothing, and the dawn is the last three rows. The moon is its own
   pair. `glow` is the light along the horizon on the sun's side, which
   at 05:10 is the whole dawn, and `town` is the sodium glow low in the
   west that any night sky near people has. `stars` and `milky` are how
   much of the starfield and the band across it survive the sky's own
   brightness. `skyLight` is what an outdoor surface is lit to by the
   sky alone — the vertex's own light is the floor and this lifts it —
   and `minLight` the darkest anything gets by distance.
   ------------------------------------------------------------------ */
export const KEYFRAMES = [
  { hour: 22.0, zenith: '#0a1030', horizon: '#182240', ground: '#07080c',
    sunAlt: -34, sunCol: '#000000', glow: '#000000', glowAmt: 0.0,
    moonAlt: 48, moonAz: -1.2, town: 0.55, stars: 1.0, milky: 0.9,
    skyLight: 0.10, minLight: 0.22, falloff: 3400 },
  { hour: 2.0,  zenith: '#080c26', horizon: '#141c38', ground: '#050608',
    sunAlt: -52, sunCol: '#000000', glow: '#000000', glowAmt: 0.0,
    moonAlt: 36, moonAz: -2.0, town: 0.5, stars: 1.0, milky: 1.0,
    skyLight: 0.08, minLight: 0.22, falloff: 3400 },
  { hour: 4.5,  zenith: '#0c1430', horizon: '#2a3450', ground: '#0a0c12',
    sunAlt: -9,  sunCol: '#8090b0', glow: '#4a5570', glowAmt: 0.55,
    moonAlt: 18, moonAz: -2.7, town: 0.3, stars: 0.5, milky: 0.3,
    skyLight: 0.22, minLight: 0.26, falloff: 4200 },
  { hour: 5.17, zenith: '#182446', horizon: '#6a5878', ground: '#1a161e',
    sunAlt: -4,  sunCol: '#e0a080', glow: '#d08060', glowAmt: 0.9,
    moonAlt: 10, moonAz: -2.9, town: 0.1, stars: 0.06, milky: 0.0,
    skyLight: 0.45, minLight: 0.32, falloff: 5200 },
  { hour: 5.67, zenith: '#4a6aa8', horizon: '#d8b890', ground: '#3a3630',
    sunAlt: 0,   sunCol: '#fff0c0', glow: '#ffd090', glowAmt: 1.0,
    moonAlt: 4,  moonAz: -3.05, town: 0.0, stars: 0.0, milky: 0.0,
    skyLight: 0.75, minLight: 0.40, falloff: 7000 },
  { hour: 6.5,  zenith: '#5a86c8', horizon: '#c8d4e0', ground: '#46484a',
    sunAlt: 9,   sunCol: '#fff8e0', glow: '#ffe8b0', glowAmt: 0.6,
    moonAlt: -5, moonAz: -3.1, town: 0.0, stars: 0.0, milky: 0.0,
    skyLight: 0.95, minLight: 0.48, falloff: 9000 },
  { hour: 8.0,  zenith: '#5080c8', horizon: '#bcd0e4', ground: '#4c4e50',
    sunAlt: 24,  sunCol: '#fffcf0', glow: '#fff0d0', glowAmt: 0.35,
    moonAlt: -20, moonAz: -3.1, town: 0.0, stars: 0.0, milky: 0.0,
    skyLight: 1.0, minLight: 0.52, falloff: 9000 },
];

/* where the sun comes up: a little north of east, in map compass terms
   (0 is east, a quarter turn is north) */
export const SUN_AZ = 0.35;
/* and where the town is, for the glow: west */
export const TOWN_AZ = Math.PI;

/* --------------------------------------------------------------------
   The weather

   airNear/airFar   the distance at which the air starts to take a
                    surface and the distance at which it has taken it
                    entirely — WHICH IS THE DRAW DISTANCE. Nothing past
                    airFar is drawn, because nothing past it can be seen
   skyMul           the hour's skyLight, scaled: cloud takes light away
   stars            what is left of the starfield under the cloud
   cover            how much of the sky the clouds take, 0..1
   cloudDark        how dark the cloud is, 1 for a fair-weather cloud
   flat             1 for mist: the sky is one colour to the zenith
   rain             how hard, 0..1
   wind             units per tic, map x and y
   haze             what the air itself adds to the sky, as bytes —
                    mist at night is GREY and not black, because it is
                    lit by every lamp in the car park, and the first
                    screenshot of night mist was a black sky over a
                    car park with the far cars simply gone
   ------------------------------------------------------------------ */
export const WEATHERS = {
  clear:    { name: 'CLEAR',    airNear: 1200, airFar: 14000, skyMul: 1.00, stars: 1.0,
              cover: 0.18, cloudDark: 1.0, flat: 0, rain: 0.0, wind: [0.28, 0.05], haze: '#000000' },
  overcast: { name: 'OVERCAST', airNear: 800,  airFar: 9000,  skyMul: 0.80, stars: 0.0,
              cover: 0.92, cloudDark: 0.8, flat: 0, rain: 0.0, wind: [0.40, 0.10], haze: '#0c0c10' },
  rain:     { name: 'RAIN',     airNear: 500,  airFar: 5200,  skyMul: 0.70, stars: 0.0,
              cover: 1.0,  cloudDark: 0.6, flat: 0, rain: 1.0, wind: [0.90, 0.20], haze: '#101014' },
  mist:     { name: 'MIST',     airNear: 200,  airFar: 2600,  skyMul: 0.85, stars: 0.0,
              cover: 0.0,  cloudDark: 1.0, flat: 1, rain: 0.0, wind: [0.05, 0.00], haze: '#2c2c32' },
};
export const WEATHER_ORDER = ['clear', 'overcast', 'rain', 'mist'];

/* A clear night's draw distance, which is what the wood's own range
   was written against. Every other weather is a fraction of it. */
export const CLEAR_FAR = WEATHERS.clear.airFar;

/* How fast the night goes: hours per minute of play. Two in the
   morning to sunrise in about nine minutes. */
export const HOURS_PER_MINUTE = 0.4;

/* --------------------------------------------------------------------
   What everybody else reads

   Plain numbers, mutated in place, the way `world` in js/material.js
   is: the smoke emitters, the two fires and the rain read these and
   never ask the Weather object anything.
   ------------------------------------------------------------------ */
export const climate = {
  hour: 2.0,
  kind: 'clear',
  wind: { x: WEATHERS.clear.wind[0], y: WEATHERS.clear.wind[1] },
  rain: 0,
  /* how much of a surface's light the sky supplies right now, 0..1 —
     the same number the shader gets, kept here for anything that wants
     to know whether it is dark without asking the GPU */
  skyLight: 0.08,
  /* the draw distance, in units */
  airFar: CLEAR_FAR,
  /* how much of the sky the fire has, 0..1 */
  smoke: 0,
};

const hex = h => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];
const lerp = (a, b, t) => a + (b - a) * t;
const lerp3 = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
export const clamp01 = v => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth = (a, b, v) => { const t = clamp01((v - a) / (b - a)); return t * t * (3 - 2 * t); };
/* sRGB bytes to linear, which is the space the buffer is in */
export { toLinear } from './palette.js';   // where it lives now; everything that imported it from here still can

/** Hours on a clock that runs 22:00 to 08:00 — anything is mapped onto
 *  that span so 1.5 and 25.5 are the same moment. */
export function nightHour(h) {
  let x = ((h % 24) + 24) % 24;
  if (x < 12) x += 24;                    // 0..12 -> 24..36, after 22
  return Math.max(22, Math.min(32, x));   // 22:00 .. 08:00
}

/**
 * The hour's row, interpolated. Colours come back as [r,g,b] in BYTE
 * space, 0..1; convert with toLinear at the shader.
 */
export function sampleHour(hour) {
  const h = nightHour(hour);
  const rows = KEYFRAMES.map(k => ({ ...k, at: nightHour(k.hour) })).sort((a, b) => a.at - b.at);
  let a = rows[0], b = rows[rows.length - 1];
  for (let i = 0; i < rows.length - 1; i++)
    if (h >= rows[i].at && h <= rows[i + 1].at) { a = rows[i]; b = rows[i + 1]; break; }
  const t = a === b || b.at === a.at ? 0 : clamp01((h - a.at) / (b.at - a.at));
  const col = k => lerp3(hex(a[k]), hex(b[k]), t);
  const num = k => lerp(a[k], b[k], t);
  const sunAlt = num('sunAlt');
  return {
    hour: h > 24 ? h - 24 : h,
    zenith: col('zenith'), horizon: col('horizon'), ground: col('ground'),
    sunAlt, sunAz: SUN_AZ, sunCol: col('sunCol'), glow: col('glow'), glowAmt: num('glowAmt'),
    moonAlt: num('moonAlt'), moonAz: num('moonAz'),
    town: num('town'), stars: num('stars'), milky: num('milky'),
    skyLight: num('skyLight'), minLight: num('minLight'), falloff: num('falloff'),
    /* how much of a day it is: nothing until the sun is twelve degrees
       under, everything once it is three up */
    daylight: smooth(-12, 3, sunAlt),
  };
}

/* THE WEATHER A FIRE MAKES. A town alight from end to end puts a lid
   of brown smoke over itself: the sun goes red in it, the stars go, the
   air closes in to a few hundred metres and everything under it is
   dimmer and oranger. This is that sky, and `smoke` below is how much
   of it there is, 0..1 — a fifth weather that comes on by degrees over
   whichever of the four is running, and goes again. The numbers are a
   wildfire afternoon's: zenith the colour of a paper bag, horizon the
   colour of the fire under it. */
export const SMOKE_SKY = {
  zenith: [0.30, 0.15, 0.06], horizon: [0.68, 0.34, 0.12], ground: [0.26, 0.12, 0.05],
  sunCol: [1.0, 0.36, 0.10], airNear: 220, airFar: 2400,
};
/* how much fire fills the sky: hot cells in the store and in the wood
   for a full one, and how many seconds it takes to come and to go */
export const SMOKE_HOT = 320, SMOKE_WOOD = 200, SMOKE_RISE = 40, SMOKE_FALL = 150;

/** The hour's row and the weather's row, folded together into the one
 *  frame the sky bake and the uniforms are set from — and the fire's
 *  smoke over both, by `smoke`. */
export function sampleFrame(hour, kind = 'clear', cloudTime = 0, smoke = 0) {
  const f = sampleHour(hour);
  const w = WEATHERS[kind] || WEATHERS.clear;
  const haze = hex(w.haze || '#000000');
  const add = c => c.map((v, i) => Math.min(1, v + haze[i]));
  const out = {
    ...f,
    zenith: add(f.zenith), horizon: add(f.horizon), ground: add(f.ground),
    kind, airNear: w.airNear, airFar: w.airFar,
    skyLight: f.skyLight * w.skyMul,
    stars: f.stars * w.stars, milky: f.milky * w.stars,
    cover: w.cover, cloudDark: w.cloudDark, flat: w.flat, rain: w.rain,
    wind: w.wind, cloudTime, smoke: 0,
  };
  const k = Math.max(0, Math.min(1, smoke || 0));
  if (k > 0) {
    const toward = (c, s, t) => c.map((v, i) => lerp(v, s[i], t));
    out.smoke = k;
    out.zenith = toward(out.zenith, SMOKE_SKY.zenith, k * 0.9);
    out.horizon = toward(out.horizon, SMOKE_SKY.horizon, k * 0.92);
    out.ground = toward(out.ground, SMOKE_SKY.ground, k * 0.9);
    out.sunCol = toward(f.sunCol, SMOKE_SKY.sunCol, k);
    out.glowAmt = f.glowAmt * (1 + k * 0.8);
    out.cover = Math.max(out.cover, k * 0.96);
    out.cloudDark = lerp(out.cloudDark, 0.5, k);
    out.stars *= 1 - k; out.milky *= 1 - k;
    out.skyLight *= 1 - 0.55 * k;
    out.airNear = lerp(out.airNear, Math.min(out.airNear, SMOKE_SKY.airNear), k);
    out.airFar = lerp(out.airFar, Math.min(out.airFar, SMOKE_SKY.airFar), k);
    /* a fire makes its own wind */
    out.wind = [w.wind[0] * (1 + k), w.wind[1] * (1 + k)];
  }
  return out;
}

/* --------------------------------------------------------------------
   The Weather: the clock ticking, and the uniforms pushed
   ------------------------------------------------------------------ */
export class Weather {
  constructor(opts = {}) {
    this.hour = opts.hour ?? 2.0;
    this.kind = WEATHERS[opts.kind] ? opts.kind : 'clear';
    this.rate = opts.rate ?? HOURS_PER_MINUTE;    // hours per minute
    this.running = opts.running ?? true;
    /* the clouds' own clock, in seconds; it never stops, because a
       cloud that holds still while the game is paused is fine and a
       cloud that jumps when it resumes is not */
    this.cloudTime = 0;
    /* how much of the sky the fire has, 0..1 — see apply */
    this.smoke = 0;
    /* AND WHETHER IT HAS ANY, which is a debug switch and not a
       setting: see setFireHaze. */
    this.fireHaze = opts.fireHaze !== false;
    /* A SKY OF ITS OWN, for a world that is not this one. The keyframes
       above are a night over a car park and every colour in them is a
       blue; the grid world (js/maps/grid.js) is green from the horizon
       up and has to say so somewhere. Rather than bend the table — which
       is a table about an HOUR, and the hours are still true — a world
       may hand over the three colours the sky is made of, and the
       middle one the ramp bends through.

         { horizon, mid, zenith, ground, midAmt, midPow }

       Hex strings, and every one of them optional. What it does not
       touch is the light, the air or the clock, which are the hour's
       and stay the hour's. See skin(). */
    this.sky = opts.sky || null;
    this.frame = this.skin(sampleFrame(this.hour, this.kind, 0, 0));
    this._sync();
  }

  /** The world's own sky colours over the hour's, if it gave any — see
   *  `sky` in the constructor. The frame is otherwise untouched. */
  skin(f) {
    const k = this.sky;
    if (!k) return f;
    if (k.zenith) f.zenith = hex(k.zenith);
    if (k.horizon) f.horizon = hex(k.horizon);
    if (k.ground) f.ground = hex(k.ground);
    if (k.mid) { f.mid = hex(k.mid); f.midAmt = k.midAmt ?? 1; f.midPow = k.midPow ?? 1.0; }
    /* whether the bake is snapped to the 256 at all — see uSnapAmt in
       js/skyart.js; a world drawn in full colour asks for 0 */
    if (k.snap !== undefined) f.snap = k.snap;
    /* AND NOTHING ELSE IN IT. A sky over a void has no cloud to drift,
       no town under it to glow, no stars and no dawn — and, because
       SkyBaker.update re-bakes for as long as there is cover, no cloud
       is also what makes this sky bake ONCE and never again. */
    if (k.bare) {
      f.cover = 0; f.cloudDark = 1; f.stars = 0; f.milky = 0;
      f.glowAmt = 0; f.town = 0; f.moonAlt = -90;
    }
    return f;
  }

  setHour(h) { this.hour = nightHour(h); this.hour = this.hour > 24 ? this.hour - 24 : this.hour; this._sync(); }
  setKind(k) { if (WEATHERS[k]) { this.kind = k; this._sync(); } }

  /**
   * THE HAZE THE FIRE MAKES, ON A SWITCH — at the user's request, and
   * it is a debug switch rather than a picture setting because what it
   * turns off is not an effect, it is a fact about the world: a town
   * alight from end to end really does put a lid over itself.
   *
   * WHAT IT TAKES AWAY is the two things a fire does to the AIR. The
   * smoke sky, which is `smoke` below — the brown lid that reddens the
   * sun, kills the stars, dims the light and pulls the visible distance
   * in from a clear night's to a few hundred metres. And the warm fog,
   * which is `smokeDensity` — the near-field murk that fills the room
   * you are standing in.
   *
   * WHAT IT LEAVES ALONE is everything that is the fire itself: the
   * flames, the embers, the sparks, the light they throw, the charring,
   * and the ambient that lifts as the building goes so you can still
   * find the way out of it. Turn the haze off and the place still burns
   * down; you can just see what you are doing while it does.
   *
   * IT SNAPS RATHER THAN EASING. The smoke takes forty seconds to come
   * in and a hundred and fifty to clear, which is right for a sky and
   * useless for a switch you are flicking to compare two frames.
   */
  setFireHaze(on) {
    const want = !!on;
    if (want === this.fireHaze) return false;
    this.fireHaze = want;
    if (!want) { this.smoke = 0; this.frame = this.skin(sampleFrame(this.hour, this.kind, this.cloudTime, 0)); this._sync(); }
    return true;
  }

  /** One world tic: the night advances. */
  tic() {
    if (this.running) {
      this.hour += this.rate / 60 / TICRATE;
      /* the clock stops at eight — past sunrise the table is flat and
         there is nothing left for the hour to say */
      if (nightHour(this.hour) >= 32) this.hour = 8.0;
    }
  }

  /** Once a frame: the clouds drift, and every atmosphere uniform is
   *  set from the hour, the weather and how much of the world is on
   *  fire. `burn` is the store's burn fraction, `wood` the forest's,
   *  and `live` is what is alight RIGHT NOW — `{ hot, wood }`, the two
   *  fires' hot cell counts; the smoke is theirs, everything else is the
   *  sky's. */
  apply(dt, burn = 0, wood = 0, live = null) {
    this.cloudTime += dt;
    /* THE SMOKE OVER THE TOWN follows what is alight now, and slowly:
       a sky takes a minute or so to fill and longer to clear, and what
       has already burnt holds a floor under it, because the smoke of a
       town that has burnt does not blow away in the time this game
       lasts. So the sky, the air and the light change as the fire
       grows, by degrees, the way a weather comes in. */
    const hot = live ? (live.hot || 0) / SMOKE_HOT + (live.wood || 0) / SMOKE_WOOD : 0;
    const target = this.fireHaze ? Math.min(1, hot + (burn + wood) * 0.7) : 0;
    if (!this.fireHaze) this.smoke = 0;
    else {
      const tau = target > this.smoke ? SMOKE_RISE : SMOKE_FALL;
      this.smoke += (target - this.smoke) * Math.min(1, dt / tau);
      if (target === 0 && this.smoke < 0.003) this.smoke = 0;
    }
    this.frame = this.skin(sampleFrame(this.hour, this.kind, this.cloudTime, this.smoke));
    const f = this.frame;

    world.airNear.value = f.airNear;
    world.airFar.value = f.airFar;
    world.skyLight.value = f.skyLight;
    world.lightFalloff.value = f.falloff;
    /* THE SMOKE, which used to be the only fog there was. Lit, warm,
       and stopping well short of opaque — see the note that was on
       this in js/fire.js. The wood adds its share and a forest is big,
       so its share stays small. */
    const sm = this.smoke;
    world.smokeDensity.value = this.fireHaze ? Math.min(0.62, burn * 1.2 + wood * 0.5 + sm * 0.30) : 0;
    world.smokeColor.value.setRGB(lerp(0.46 + burn * 0.12, 0.60, sm), lerp(0.34 + burn * 0.08, 0.33, sm), lerp(0.24 + burn * 0.03, 0.14, sm));
    /* A gutted store lit only by embers is, accurately, almost pitch
       black — and the player still has to find the way out of it. So
       the ambient lifts as the place goes. Accuracy loses this one on
       purpose. */
    world.minLight.value = f.minLight + burn * 0.30;
    world.globalLight.value = 1.0 + burn * 0.22;

    this._sync();
    return f;
  }

  _sync() {
    const w = WEATHERS[this.kind];
    const f = this.frame;
    climate.hour = this.hour;
    climate.kind = this.kind;
    /* the wind and the air are the frame's, which is the weather's with
       the fire's smoke over it */
    climate.wind.x = f ? f.wind[0] : w.wind[0]; climate.wind.y = f ? f.wind[1] : w.wind[1];
    climate.rain = w.rain;
    climate.skyLight = f ? f.skyLight : 0;
    climate.airFar = f ? f.airFar : w.airFar;
    climate.smoke = this.smoke;
  }

  /** What the sky is doing, for a label: the weather, or the fire's. */
  get shownKind() { return this.smoke > 0.4 ? 'smoke' : this.kind; }

  /** "02:00", for a menu. */
  get label() {
    const h = ((this.hour % 24) + 24) % 24;
    const hh = Math.floor(h), mm = Math.floor((h - hh) * 60);
    return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
  }
}

/** The hours a menu can step through: every keyframe. */
export const HOUR_STOPS = KEYFRAMES.map(k => k.hour);
