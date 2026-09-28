/* =====================================================================
   MEWD — noises
   =====================================================================

   Synthesised, not sampled. Same reason as the textures: nothing to
   load, nothing to license, and everything comes out of one place so it
   all sits together. Six primitives — a noise burst, a tone sweep, a
   click, a thud, a hiss and a crackle — and every sound in the game is
   some arrangement of those.

   Sounds are POSITIONED. A fire two aisles over is quieter than one
   behind you, and that is most of what a Doom soundscape does for you:
   it tells you what is in the room before you can see it.
   Distance attenuation only — no panning — because Doom did not pan
   either and stereo separation on a thing you cannot see turns out to be
   less useful than it sounds.
   ===================================================================== */

/* THE SYNTHESISED SOUNDS ARE OFF FOR NOW, at the user's request. One
   switch: with it on, play() refuses every name in DEFS below and the
   ambience never starts, so no oscillator is ever made. Every sound in
   the table is still defined and still asked for by the game; flip
   this and they are all back.

   WHAT IT DOES NOT SILENCE IS A SAMPLE. The minigun arrived with three
   recordings of its own (SAMPLES below), at the user's request, and
   those play whatever this says: the switch is about the noises this
   file makes up, not about the ones the user made. */
export const MUTED = true;

/* THE RECORDED ONES, and they are the user's own: the minigun winding
   up, a two-second loop of it firing and it winding down, and then the
   lance's five — a charge loop, a stage-three whine, a pre-fire
   transient and two layers of discharge. Fetched at boot, decoded once there is
   a context, and played by the same play() as everything else — a
   name in SAMPLE_FOR is a sample, and everything else is synthesised
   — so the player asks for 'spinup' the way it always did and gets
   the recording. The loop is the one thing with a second verb, loop(),
   because a held trigger is a held sound. */
export const SAMPLES = {
  minigun_start: 'assets/sfx/minigun_start.wav',
  minigun_fire:  'assets/sfx/minigun_fire.wav',
  minigun_stop:  'assets/sfx/minigun_stop.wav',
  /* AND THE LANCE'S FIVE, the user's own again, and the first weapon in
     the game whose whole voice is recorded rather than synthesised.
     They map onto the three states a charged weapon has (see
     js/player.js, lanceTic) and nothing else has to know:

       lance_charge_start the moment the trigger goes down, once
       lance_charge_loop  two seconds of coil, held round and round for
                          as long as the trigger stays down, started
                          under the one above rather than after it —
                          the two are meant to overlap
       lance_charge_full  the stage-three whine, which takes over from
                          the loop the moment the third mark is passed
                          and is the sound of a gun that is finished
                          asking. Held too, so standing at full charge
                          is a sound and not a silence
       lance_prefire      the transient the moment the trigger comes UP
       lance_fire_a/b     and the discharge, in two layers, played
                          together — which is how it was mixed and is
                          why there are two of them rather than one */
  lance_charge_start: 'assets/sfx/lance_charge_start.wav',
  lance_charge_loop: 'assets/sfx/lance_charge_loop.wav',
  lance_charge_full: 'assets/sfx/lance_charge_full.wav',
  lance_prefire:     'assets/sfx/lance_prefire.wav',
  lance_fire_a:      'assets/sfx/lance_fire_a.wav',
  lance_fire_b:      'assets/sfx/lance_fire_b.wav',
};
export const SAMPLE_FOR = {
  spinup: 'minigun_start', minigunloop: 'minigun_fire', spindown: 'minigun_stop',
  lancestart: 'lance_charge_start', lancecharge: 'lance_charge_loop',
  lancecharge3: 'lance_charge_full',
  lanceprefire: 'lance_prefire', lancefire: 'lance_fire_a', lancefire2: 'lance_fire_b',
};
/* HOW LOUD EACH RECORDING IS, against the music: the minigun as
   recorded drowned the three tracks the user mixed, so it is turned
   down here — the loop most, since it is what runs — and the music is
   left where the fader puts it. 1 is the file as it came. */
/* ---------------------------------------------------------------------
   WHICH RECORDINGS ARE MADE LOOPABLE, AND HOW LONG THE JOIN IS

   A .wav does not loop. `src.loop = true` sends the playhead from the
   last sample straight back to the first, and unless the file was cut
   on a zero crossing with matching phase on both sides — which no
   recording of a real coil ever is — that jump is a step in the
   waveform, which is a click, once every two seconds, for the whole
   seven seconds the trigger is down. The user heard it and asked for it
   fixed, and the fix is not a fade on playback: it is to make a buffer
   that is ACTUALLY periodic, once, when the file decodes. See
   _loopify, which is where it happens and where the argument for doing
   it that way rather than with a pair of crossfading sources is
   written out.

   The number is the join, in seconds. Long enough to hide the splice in
   a continuous texture; short enough that the loop is still most of the
   file. A third of a second on a two-second coil. */
export const SAMPLE_LOOP = { lance_charge_loop: 0.34 };

export const SAMPLE_GAIN = {
  minigun_fire: 0.32, minigun_start: 0.42, minigun_stop: 0.42,
  /* THE LANCE IS THE LOUDEST THING IN THE GAME and is still turned down
     against the music, on the same terms the minigun was. The two fire
     layers are billed together — they play at the same instant and
     what the player hears is their sum — so each is set where the pair
     sits where one minigun burst does. The charge loop is the quietest
     of the five because it runs for seven seconds under everything
     else. */
  lance_charge_start: 0.46, lance_charge_loop: 0.34, lance_charge_full: 0.46,
  lance_prefire: 0.52, lance_fire_a: 0.50, lance_fire_b: 0.44,
};

const DEFS = {
  /* the store */
  ignite:    { kind: 'hiss',  dur: 0.55, f0: 900,  f1: 200,  gain: 0.30 },
  flame:     { kind: 'hiss',  dur: 0.20, f0: 1400, f1: 500,  gain: 0.16 },
  burn:      { kind: 'hiss',  dur: 0.35, f0: 600,  f1: 160,  gain: 0.22 },
  explode:   { kind: 'boom',  dur: 0.90, f0: 180,  f1: 30,   gain: 0.60 },
  throw:     { kind: 'sweep', dur: 0.18, f0: 500,  f1: 900,  gain: 0.16, wave: 'triangle' },
  glass:     { kind: 'noise', dur: 0.30, f0: 4200, f1: 1600, gain: 0.30 },

  /* weapons */
  swing:     { kind: 'sweep', dur: 0.12, f0: 700,  f1: 260,  gain: 0.14, wave: 'triangle' },
  cut:       { kind: 'noise', dur: 0.10, f0: 2600, f1: 700,  gain: 0.26 },
  /* THE COLD PAIR. `freeze` is a hiss running the WRONG WAY — up rather
     than down, which is the whole difference between a thing catching
     fire and a thing seizing up — and `shatter` is glass with the bottom
     taken off it, short and bright, because that is what a person full
     of ice sounds like when something hits them. */
  freeze:    { kind: 'hiss',  dur: 0.45, f0: 260,  f1: 1500, gain: 0.26 },
  shatter:   { kind: 'noise', dur: 0.22, f0: 5200, f1: 900,  gain: 0.40 },
  /* and the melt, which is `freeze` played backwards in every sense
     that matters here: down rather than up, longer, and quieter,
     because coming out of it is a slower thing than going in */
  thaw:      { kind: 'hiss',  dur: 0.60, f0: 1500, f1: 260,  gain: 0.18 },
  /* SOMETHING HITTING SOMETHING, for the weapon that is not built yet
     — see Game.impact. A thud with a bit of edge left on it: the body
     of it is the low sweep and what makes it read as a blow rather
     than a door closing is that it is over in a fifth of a second. */
  whack:     { kind: 'thud',  dur: 0.20, f0: 300,  f1: 70,   gain: 0.38 },
  /* AND THE FIRST THINGS IN THE GAME THAT SHOOT BACK. A rifle is a
     crack of noise with no pitch to it; the siren is two sweeps that
     alternate, played by the van as it comes; and the troopers have a
     bark, a grunt and a cry, all off the same triangle the shoppers
     use, lower and shorter, because they are men in helmets. */
  shot:      { kind: 'noise', dur: 0.14, f0: 3200, f1: 500,  gain: 0.40 },
  siren:     { kind: 'sweep', dur: 0.55, f0: 620,  f1: 940,  gain: 0.20, wave: 'square' },
  siren2:    { kind: 'sweep', dur: 0.55, f0: 940,  f1: 620,  gain: 0.20, wave: 'square' },
  swatsee:   { kind: 'sweep', dur: 0.16, f0: 420,  f1: 300,  gain: 0.24, wave: 'triangle' },
  swatpain:  { kind: 'sweep', dur: 0.14, f0: 360,  f1: 220,  gain: 0.24, wave: 'triangle' },
  swatdie:   { kind: 'sweep', dur: 0.50, f0: 380,  f1: 90,   gain: 0.30, wave: 'triangle' },
  /* AND THE ARMY BEHIND THEM, which is the same five sounds a few
     semitones down and a little longer. A heavier rifle is a lower
     crack with more of it, the turbine under the APC is a sawtooth that
     rises and falls where the siren is a square wave that wails — the
     difference between a thing with an engine and a thing with a
     warning — and the three voices are the SWAT's with bigger men in
     them. */
  rifle:     { kind: 'noise', dur: 0.17, f0: 2400, f1: 380,  gain: 0.46 },
  hover:     { kind: 'sweep', dur: 0.85, f0: 96,   f1: 142,  gain: 0.18, wave: 'sawtooth' },
  hover2:    { kind: 'sweep', dur: 0.85, f0: 142,  f1: 96,   gain: 0.18, wave: 'sawtooth' },
  /* THE FIRE BRIGADE: a second siren, deeper — which is what TIERS in
     js/responders.js has said it was since before there was a truck —
     and the cannon's hiss, pitched lower and longer than the
     extinguisher's because it is a river rather than a puff */
  firehorn:  { kind: 'sweep', dur: 0.68, f0: 330,  f1: 520,  gain: 0.20, wave: 'square' },
  firehorn2: { kind: 'sweep', dur: 0.68, f0: 520,  f1: 330,  gain: 0.20, wave: 'square' },
  hose:      { kind: 'noise', dur: 0.30, f0: 1400, f1: 900,  gain: 0.14 },
  armysee:   { kind: 'sweep', dur: 0.19, f0: 300,  f1: 200,  gain: 0.26, wave: 'triangle' },
  armypain:  { kind: 'sweep', dur: 0.16, f0: 260,  f1: 150,  gain: 0.26, wave: 'triangle' },
  armydie:   { kind: 'sweep', dur: 0.58, f0: 270,  f1: 62,   gain: 0.32, wave: 'triangle' },
  /* THE GUNSHIP (js/vtol.js): its turbines are the APC's sawtooth an
     octave up and longer, two notes on a clock of its own; the vulcan
     is the minigun's crack with more bottom in it, and its rate limit
     turns three a tic into the buzz; and it going down is the big
     boom with a longer tail, the loudest thing in the game bar the
     one below it. */
  gunship:   { kind: 'sweep', dur: 1.10, f0: 210,  f1: 300,  gain: 0.16, wave: 'sawtooth' },
  gunship2:  { kind: 'sweep', dur: 1.10, f0: 300,  f1: 210,  gain: 0.16, wave: 'sawtooth' },
  vulcan:    { kind: 'noise', dur: 0.07, f0: 1900, f1: 400,  gain: 0.36 },
  shipdie:   { kind: 'boom',  dur: 1.90, f0: 220,  f1: 26,   gain: 0.92 },
  /* the bang a vehicle ends on now, which is four of the old one: the
     same boom, longer and lower, with the master gain it needs to be
     the loudest thing in the game */
  bigboom:   { kind: 'boom',  dur: 1.60, f0: 140,  f1: 22,   gain: 0.95 },
  /* THE CEREBRAL BORE: the sight finding a head, the launcher, the
     thing in flight, the drill in a skull, and a miss ringing off a
     wall. All sawtooth, because a drill is a sawtooth. */
  lock:      { kind: 'sweep', dur: 0.07, f0: 1500, f1: 1500, gain: 0.22, wave: 'square' },
  borefire:  { kind: 'sweep', dur: 0.35, f0: 300,  f1: 1400, gain: 0.34, wave: 'sawtooth' },
  borefly:   { kind: 'sweep', dur: 0.20, f0: 1100, f1: 1300, gain: 0.12, wave: 'sawtooth' },
  bore:      { kind: 'sweep', dur: 0.24, f0: 700,  f1: 1900, gain: 0.30, wave: 'sawtooth' },
  /* THE QUAD LAUNCHER: the seeker finding heat (a low growl), each lock
     taken (a pip), the last of the four (a higher, longer one), and a
     missile leaving its tube. Synthesised, so they go quiet with the
     rest of this table while MUTED is on; a recording of the user's
     under the same name in SAMPLE_FOR would take over, as the minigun's
     and the lance's did. */
  seek:      { kind: 'sweep', dur: 0.12, f0: 420,  f1: 380,  gain: 0.14, wave: 'square' },
  lockon:    { kind: 'sweep', dur: 0.08, f0: 1760, f1: 1760, gain: 0.22, wave: 'square' },
  lockfull:  { kind: 'sweep', dur: 0.30, f0: 2200, f1: 2200, gain: 0.24, wave: 'square' },
  missile:   { kind: 'hiss',  dur: 0.55, f0: 2600, f1: 500,  gain: 0.42 },
  clang:     { kind: 'thud',  dur: 0.12, f0: 900,  f1: 300,  gain: 0.30 },
  /* THE ARC MAW: the charge is a hum struck again every few tics, a
     step higher each third of the way up, with a rising whine when it
     tops out; the discharge is a crack, and a full one is a crack with
     thunder under it; and every strike down the chain is a short zap.
     Synthesised, like the launcher's. */
  arccharge1: { kind: 'sweep', dur: 0.20, f0: 170,  f1: 210,  gain: 0.10, wave: 'sawtooth' },
  arccharge2: { kind: 'sweep', dur: 0.20, f0: 250,  f1: 320,  gain: 0.12, wave: 'sawtooth' },
  arccharge3: { kind: 'sweep', dur: 0.20, f0: 380,  f1: 500,  gain: 0.14, wave: 'sawtooth' },
  arcfull:   { kind: 'sweep', dur: 0.42, f0: 600,  f1: 1500, gain: 0.16, wave: 'square' },
  arcfire:   { kind: 'noise', dur: 0.30, f0: 4200, f1: 700,  gain: 0.50 },
  arcbig:    { kind: 'boom',  dur: 1.10, f0: 520,  f1: 48,   gain: 0.80 },
  arczap:    { kind: 'noise', dur: 0.09, f0: 5200, f1: 1800, gain: 0.26 },
  /* THE MINIGUN: a round is the rifle's crack cut short, and the audio
     layer's own rate limit turns a hundred and forty of them a second
     into the buzz a minigun actually makes; the barrels winding up are
     a sawtooth climbing over a third of a second, and winding down the
     same run the other way, longer. */
  minigun:   { kind: 'noise', dur: 0.06, f0: 2600, f1: 500,  gain: 0.34 },
  spinup:    { kind: 'sweep', dur: 0.34, f0: 120,  f1: 520,  gain: 0.22, wave: 'sawtooth' },
  spindown:  { kind: 'sweep', dur: 0.80, f0: 520,  f1: 90,   gain: 0.18, wave: 'sawtooth' },

  /* the staff */
  gib:       { kind: 'noise', dur: 0.42, f0: 1500, f1: 180,  gain: 0.44 },
  shopper:   { kind: 'sweep', dur: 0.30, f0: 620,  f1: 240,  gain: 0.26, wave: 'triangle' },
  bodyfall:  { kind: 'thud',  dur: 0.28, f0: 130,  f1: 44,   gain: 0.30 },

  /* you */
  hurt:      { kind: 'sweep', dur: 0.24, f0: 420,  f1: 200,  gain: 0.30, wave: 'square' },
  playerDie: { kind: 'sweep', dur: 1.30, f0: 340,  f1: 46,   gain: 0.44, wave: 'sawtooth' },
  pickup:    { kind: 'sweep', dur: 0.14, f0: 700,  f1: 1300, gain: 0.22, wave: 'square' },
  noammo:    { kind: 'click', dur: 0.05, f0: 240,  f1: 160,  gain: 0.18 },

  /* the building */
  dooropen:  { kind: 'sweep', dur: 0.60, f0: 90,   f1: 190,  gain: 0.24, wave: 'sawtooth' },
  doorclose: { kind: 'sweep', dur: 0.55, f0: 190,  f1: 80,   gain: 0.24, wave: 'sawtooth' },
  switch:    { kind: 'click', dur: 0.07, f0: 900,  f1: 400,  gain: 0.24 },
  lampbreak: { kind: 'noise', dur: 0.34, f0: 5200, f1: 900,  gain: 0.34 },
  spark:     { kind: 'click', dur: 0.04, f0: 2600, f1: 1400, gain: 0.10 },
  alarm:     { kind: 'sweep', dur: 0.70, f0: 880,  f1: 660,  gain: 0.22, wave: 'square' },
};

export class Audio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.enabled = true;
    this.listener = { x: 0, y: 0 };
    this.maxDistance = 1800;
    this._noiseBuf = null;
    this._lastAt = new Map();       // one of each sound per few tics, at most
    this.bytes = {};                // the samples, as fetched
    this.samples = {};              // and decoded
  }

  /** Fetch the recordings. No context is needed for this, so it can
   *  start at boot; decoding waits for the start tap. A file that
   *  does not arrive is simply a sound the game does not have. */
  async loadSamples() {
    await Promise.all(Object.entries(SAMPLES).map(async ([k, url]) => {
      try {
        const res = await fetch(url);
        if (!res.ok) throw new Error(`${url}: ${res.status}`);
        this.bytes[k] = await res.arrayBuffer();
      } catch (e) { console.warn('no sample:', e.message); }
    }));
  }

  async _decodeSamples() {
    for (const k of Object.keys(this.bytes)) {
      if (this.samples[k] || !this.ctx) continue;
      try {
        const buf = await this.ctx.decodeAudioData(this.bytes[k].slice(0));
        this.samples[k] = SAMPLE_LOOP[k] ? this._loopify(buf, SAMPLE_LOOP[k]) : buf;
      } catch (e) { console.warn('sample would not decode:', k, e.message); }
    }
  }

  /* ------------------------------------------------------------------
     A BUFFER THAT IS ACTUALLY PERIODIC

     The ordinary answer to a clicking loop is to play two copies half a
     period apart and crossfade between them for ever, so the seam of
     one is covered by the middle of the other. It works, and it is the
     wrong answer HERE, for one reason: this loop is pitch-ramped. The
     whole point of it is that the coil rises as it charges (see
     Player.lanceVoice), and a playback rate that climbs from 0.72 to
     1.45 is a loop period that shrinks by half over seven seconds. A
     crossfade scheduled against a period that is moving has to be
     rescheduled continuously, and any drift puts the fade somewhere
     other than over the seam — which is a click again, at a moment you
     cannot predict.

     So the join is baked into the SAMPLES instead, once, at decode, and
     after that the buffer is genuinely periodic: the last sample and
     the first are neighbours in the original recording, so the wrap is
     not a discontinuity at any playback rate at all. One source, no
     scheduling, and the pitch can do whatever it likes.

     HOW: a buffer of length L becomes one of length n = L - X. The
     middle is copied straight through. The first X samples are the
     head mixed with the TAIL that was cut off, equal power, the tail
     fading out as the head fades in — so position 0 of the loop IS
     sample n of the original, which is the sample that followed n-1,
     which is the last sample of the loop. The join is exact.

     Equal power (cos/sin) rather than a straight line because the two
     sides are different parts of the same continuous noise and so are
     uncorrelated: summed linearly their energy dips in the middle of
     the fade, which is audible as a breath. cos² + sin² = 1 does not.
     ------------------------------------------------------------------ */
  _loopify(buf, xfade) {
    const sr = buf.sampleRate;
    const X = Math.min(Math.round(xfade * sr), Math.floor(buf.length / 3));
    if (X < 32) return buf;
    const n = buf.length - X;
    const out = this.ctx.createBuffer(buf.numberOfChannels, n, sr);
    for (let c = 0; c < buf.numberOfChannels; c++) {
      const src = buf.getChannelData(c), dst = out.getChannelData(c);
      dst.set(src.subarray(0, n));
      for (let i = 0; i < X; i++) {
        const t = (i + 0.5) / X;
        const head = Math.sin(t * Math.PI / 2), tail = Math.cos(t * Math.PI / 2);
        dst[i] = src[i] * head + src[n + i] * tail;
      }
    }
    return out;
  }

  /* Browsers will not start an AudioContext until the user has done
     something, so this is called from the first click. */
  resume() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) { this.enabled = false; return; }
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.5;
      this.master.connect(this.ctx.destination);
      this._makeNoise();
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    this._decodeSamples();
  }

  /** Distance, as a gain: 1 for the player's own sounds, falling off
   *  to nothing at maxDistance. */
  _gainFor(from) {
    if (!from || from === this.listener) return 1;
    const d = Math.hypot(from.x - this.listener.x, from.y - this.listener.y);
    if (d > this.maxDistance) return 0;
    return Math.max(0, 1 - d / this.maxDistance) ** 1.7;
  }

  /**
   * One recording, once or round and round, with a handle on it.
   *
   * `rate` is the playback rate it STARTS at. A buffer source's rate is
   * a pitch and a speed at the same time — there is no formant
   * correction and none is wanted, because what a coil winding up
   * actually does is get faster and higher together. The lance rides
   * this from 0.72 to 1.45 as it charges; everything else leaves it at
   * 1 and this costs nothing.
   */
  _playSample(key, from, loop = false, rate = 1) {
    const buf = this.samples[key];
    if (!buf) return null;
    const gain = this._gainFor(from) * (SAMPLE_GAIN[key] ?? 1);
    if (gain < 0.004) return null;
    const src = this.ctx.createBufferSource();
    src.buffer = buf; src.loop = loop;
    if (rate !== 1) src.playbackRate.value = rate;
    const g = this.ctx.createGain();
    g.gain.value = gain;
    src.connect(g); g.connect(this.master);
    src.start();
    const ctx = this.ctx;
    return {
      src, gain: g, base: gain,
      /** Slide the pitch. `over` is roughly how long it takes to get
       *  there — setTargetAtTime, so it is a chase and never a step,
       *  which is what lets this be called thirty-five times a second
       *  from the tic without stepping on itself. */
      rate(v, over = 0.06) {
        try { src.playbackRate.setTargetAtTime(v, ctx.currentTime, Math.max(0.005, over / 3)); } catch (e) { /* gone */ }
      },
      /** And slide the level, for something that dies away rather than
       *  being switched off. */
      fade(to, over = 0.5) {
        try { g.gain.setTargetAtTime(gain * to, ctx.currentTime, Math.max(0.01, over / 3)); } catch (e) { /* gone */ }
      },
      /** Let it run to the end of itself and then go — for a one-shot
       *  handed out so its pitch can be ridden, which must not be cut
       *  off when the thing that was riding it lets go. */
      release(over = 0.9) {
        try { g.gain.setTargetAtTime(0, ctx.currentTime, over / 3); src.stop(ctx.currentTime + over); } catch (e) { /* gone */ }
      },
      /* a short ramp out, so a loop that stops mid-cycle does not click */
      stop() { try { g.gain.setTargetAtTime(0, ctx.currentTime, 0.02); src.stop(ctx.currentTime + 0.12); } catch (e) { /* already gone */ } },
    };
  }

  /**
   * A recording with a handle on it, whether or not it loops — which is
   * what a held, pitch-ridden sound needs and what play() cannot give,
   * because play() is fire and forget and answers for the synthesised
   * sounds too.
   *
   * @param name  a key of SAMPLE_FOR
   * @param opts  { loop, rate }
   * @returns the handle, or null if there is no such recording (which
   *          is the ordinary case on a machine that could not decode
   *          it, and every caller treats it as "no sound")
   */
  sample(name, from, { loop = false, rate = 1 } = {}) {
    if (!name || !this.enabled || !this.ctx) return null;
    const key = SAMPLE_FOR[name];
    return key ? this._playSample(key, from, loop, rate) : null;
  }

  /** A held sound: starts now, runs until the handle's stop() is
   *  called. Only a name in SAMPLE_FOR can be held. */
  loop(name, from, rate = 1) { return this.sample(name, from, { loop: true, rate }); }

  setVolume(v) { if (this.master) this.master.gain.value = v; }

  _makeNoise() {
    const n = this.ctx.sampleRate * 2;
    const buf = this.ctx.createBuffer(1, n, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    /* pink-ish: white noise run through a one-pole low pass, which is
       much closer to fire and to impacts than white ever is */
    let last = 0;
    for (let i = 0; i < n; i++) {
      const w = Math.random() * 2 - 1;
      last = last * 0.86 + w * 0.14;
      d[i] = last * 3.2 + w * 0.3;
    }
    this._noiseBuf = buf;
  }

  play(name, from) {
    if (!name || !this.enabled || !this.ctx) return;
    /* a recording, if there is one under that name — see SAMPLE_FOR */
    if (SAMPLE_FOR[name]) { this._playSample(SAMPLE_FOR[name], from); return; }
    if (MUTED) return;
    const def = DEFS[name];
    if (!def) return;

    /* Distance. A sound with no source is the player's own and plays at
       full volume. */
    let gain = def.gain;
    if (from && from !== this.listener) {
      const d = Math.hypot(from.x - this.listener.x, from.y - this.listener.y);
      if (d > this.maxDistance) return;
      gain *= Math.max(0, 1 - d / this.maxDistance) ** 1.7;
      if (gain < 0.004) return;
    }

    /* Twenty of the same groan in one tic is a buzz, not a soundscape. */
    const now = this.ctx.currentTime;
    const last = this._lastAt.get(name) || -1;
    if (now - last < 0.045) return;
    this._lastAt.set(name, now);

    const g = this.ctx.createGain();
    g.connect(this.master);
    const t = now;
    const dur = def.dur;

    if (def.kind === 'noise' || def.kind === 'hiss' || def.kind === 'boom' || def.kind === 'thud') {
      const src = this.ctx.createBufferSource();
      src.buffer = this._noiseBuf;
      src.loop = true;
      src.playbackRate.value = def.kind === 'boom' ? 0.5 : 1;
      const f = this.ctx.createBiquadFilter();
      f.type = (def.kind === 'boom' || def.kind === 'thud') ? 'lowpass' : 'bandpass';
      f.Q.value = def.kind === 'hiss' ? 0.7 : 1.4;
      f.frequency.setValueAtTime(def.f0, t);
      f.frequency.exponentialRampToValueAtTime(Math.max(20, def.f1), t + dur);
      src.connect(f); f.connect(g);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain, t + Math.min(0.03, dur * 0.2));
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      src.start(t); src.stop(t + dur + 0.02);
    } else {
      const o = this.ctx.createOscillator();
      o.type = def.wave || 'sine';
      o.frequency.setValueAtTime(def.f0, t);
      o.frequency.exponentialRampToValueAtTime(Math.max(20, def.f1), t + dur);
      o.connect(g);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain, t + Math.min(0.02, dur * 0.2));
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.start(t); o.stop(t + dur + 0.02);
    }
  }

  /** The bed of noise a burning building makes. Started once the fire
   *  gets going and modulated by how much of the store is alight. */
  startAmbience() {
    if (MUTED || !this.ctx || this._amb) return;
    const src = this.ctx.createBufferSource();
    src.buffer = this._noiseBuf; src.loop = true;
    const f = this.ctx.createBiquadFilter();
    f.type = 'lowpass'; f.frequency.value = 700; f.Q.value = 0.4;
    const g = this.ctx.createGain(); g.gain.value = 0;
    src.connect(f); f.connect(g); g.connect(this.master);
    src.start();
    this._amb = { src, g, f };
  }

  setAmbience(level) {
    if (!this._amb) return;
    const g = this._amb.g.gain;
    g.setTargetAtTime(Math.min(0.30, level * 0.34), this.ctx.currentTime, 0.6);
    this._amb.f.frequency.setTargetAtTime(500 + level * 1600, this.ctx.currentTime, 0.6);
  }
}
