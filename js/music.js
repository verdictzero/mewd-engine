/* =====================================================================
   MEWD — the music
   =====================================================================

   THREE TRACKS, at the user's request, and they play for ever: the
   user's three E1M1 remixes (four files arrived; two of them were the
   same file byte for byte, so there are three), one into the next into
   the next and round again, each fading into the one after it on the
   beat.

   BEAT AWARE, AND PRE-ARRANGED. Nothing is analysed while the game
   runs. Each track was measured once, offline, in the same decoder the
   browser uses — tempo to a hundredth of a beat a minute, the downbeat
   at the head, and a downbeat in the last forty seconds to hand over
   on — and the answers are the table below. What the player does at
   run time is arithmetic on that table.

   THE HANDOVER, which is the whole design:

     the outgoing track reaches `out`, a downbeat eight bars or so
     before its own ending. On that instant the incoming track's first
     downbeat lands — it was started `bar0` seconds earlier, scaled —
     and both gains ramp LINEARLY over FADE_BARS bars of the outgoing
     tempo, one up and one down, and the outgoing stops.

     AND THE INCOMING ARRIVES AT THE OUTGOING'S TEMPO. The three are
     not the same speed — 145.8, 140.3 and 142.3 — and a fade between
     two grids four per cent apart flams by a quarter of a beat before
     it is half done. So the incoming starts with its playback rate
     set to the ratio, so that its bars are the outgoing's bars for as
     long as both can be heard, and then over MATCH_BARS more bars the
     rate ramps linearly back to one, which is a DJ's pitch fader
     being eased home once the other deck is off. Four per cent of
     pitch for a few seconds, once every four minutes, under a mix.

   All of that is Web Audio's own clock: sources started at a time,
   gains and rates ramped to a time, sample accurate whatever the frame
   rate is doing. tick() only has to look a few seconds ahead and put
   the next handover on the schedule before it is due.

   IT HAS ITS OWN CONTEXT rather than the sound effects', because the
   effects are switched off behind MUTED in js/audio.js and the music
   is not, and because a decoded four-minute track is thirty megabytes
   of floats the effects never need to know about.

   The arithmetic is exported on its own so the smoke test can hold a
   handover against the table without a speaker.
   ===================================================================== */

/* the table: what was measured, and the one decision made from it

     url    the file
     bpm    beats a minute, measured over the whole track and refined
     bar0   the first downbeat, seconds from the start of the file
     out    the downbeat the next track comes in on — a downbeat in the
            track's last forty seconds, measured there rather than
            counted forward from bar0 so a hundredth of a beat a minute
            over four minutes does not put it a tenth of a second off */
export const TRACKS = [
  { url: 'assets/music/e1m1_00.mp3', bpm: 145.80, bar0: 0.135, out: 244.05, seconds: 259.76 },
  { url: 'assets/music/e1m1_01.mp3', bpm: 140.34, bar0: 0.105, out: 227.12, seconds: 243.20 },
  { url: 'assets/music/e1m1_02.mp3', bpm: 142.30, bar0: 0.110, out: 221.47, seconds: 236.76 },
];
export const FADE_BARS = 8;      // the crossfade, in bars of the outgoing tempo
export const MATCH_BARS = 8;     // and how long the incoming takes to ease back to its own tempo
export const LOOKAHEAD = 6;      // seconds before a handover that it goes on the schedule

export const barOf = t => 240 / t.bpm;

/**
 * One handover, as numbers: track `a` reaches its `out` at wall time
 * `outAt`; here is when to start `b`, at what rate, and when everything
 * ends. Pure.
 */
export function arrange(a, b, outAt) {
  const rate = a.bpm / b.bpm;                    // b's bars become a's bars
  const fade = FADE_BARS * barOf(a);
  const match = MATCH_BARS * barOf(a);
  return {
    start: outAt - b.bar0 / rate,                // b's first downbeat lands on a's out
    rate,
    fadeEnd: outAt + fade,                       // a is silent and stopped here
    rateEnd: outAt + fade + match,               // and b is back at 1.0 here
  };
}

/**
 * Where in wall time a position `p` in track b's file falls, given the
 * plan it was started on: at `rate` until the fade ends, a linear ramp
 * to 1 over the match, then 1. A linear ramp of rate over a stretch of
 * wall time advances the file by the stretch times the mean rate,
 * which is the one line of calculus in here.
 */
export function wallTimeFor(plan, p) {
  const r = plan.rate;
  const phase1 = r * (plan.fadeEnd - plan.start);            // file seconds covered at rate r
  if (p <= phase1) return plan.start + p / r;
  const D = plan.rateEnd - plan.fadeEnd;
  const phase2 = D * (1 + r) / 2;                             // file seconds covered by the ramp
  if (p <= phase1 + phase2) {
    /* solve p - phase1 = t*r + (1-r) t^2 / (2D) for t in [0, D] */
    const q = p - phase1, k = (1 - r) / (2 * D);
    const t = Math.abs(k) < 1e-9 ? q / r : (-r + Math.sqrt(r * r + 4 * k * q)) / (2 * k);
    return plan.fadeEnd + t;
  }
  return plan.rateEnd + (p - phase1 - phase2);
}

export class Music {
  constructor(tracks = TRACKS) {
    this.tracks = tracks;
    this.ctx = null;
    this.master = null;
    this.buffers = new Array(tracks.length).fill(null);
    this.bytes = new Array(tracks.length).fill(null);
    this.volume = 0.5;
    this.playing = false;
    this.index = -1;
    this.plan = null;         // the plan the CURRENT track was started on
    this.nextAt = Infinity;   // wall time of the next handover
    this.scheduled = false;
    this.current = null;      // { src, gain }
    this.enabled = true;
  }

  /** Fetch the files now (no gesture needed); decode once there is a
   *  context. Any file that fails to arrive leaves the loop one track
   *  shorter rather than silent. */
  async load() {
    await Promise.all(this.tracks.map(async (t, i) => {
      try {
        const res = await fetch(t.url);
        if (!res.ok) throw new Error(`${t.url}: ${res.status}`);
        this.bytes[i] = await res.arrayBuffer();
      } catch (e) { console.warn('no music track:', e.message); }
    }));
  }

  async _decode(i) {
    if (this.buffers[i] || !this.bytes[i] || !this.ctx) return this.buffers[i];
    try { this.buffers[i] = await this.ctx.decodeAudioData(this.bytes[i].slice(0)); }
    catch (e) { console.warn('music would not decode:', e.message); this.bytes[i] = null; }
    return this.buffers[i];
  }

  /** From the start tap: open the context, decode the first track and
   *  put it on. The rest decode behind it. */
  async start() {
    if (this.playing || !this.enabled) return;
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) { this.enabled = false; return; }
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = this._gain(this.volume);
      this.master.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') { try { await this.ctx.resume(); } catch (e) { /* not yet */ } }
    /* the first track that decodes is the first track that plays */
    let first = -1;
    for (let i = 0; i < this.tracks.length && first < 0; i++) if (await this._decode(i)) first = i;
    if (first < 0) { this.enabled = false; return; }
    this.playing = true;
    this._play(first, this.ctx.currentTime + 0.05, null);
    for (let i = 0; i < this.tracks.length; i++) this._decode(i);
  }

  /** Perceived loudness is nearer the square of the fader. */
  _gain(v) { return Math.max(0, Math.min(1, v)) ** 2; }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.setTargetAtTime(this._gain(v), this.ctx.currentTime, 0.05);
  }

  /** Put track `i` on: at `when` with no plan (the first track, at
   *  full gain), or on `plan` (a handover: rate, ramps, the lot). */
  _play(i, when, plan) {
    const t = this.tracks[i];
    const buf = this.buffers[i];
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const gain = this.ctx.createGain();
    src.connect(gain); gain.connect(this.master);
    const g = gain.gain;
    if (plan) {
      src.playbackRate.setValueAtTime(plan.rate, plan.start);
      src.playbackRate.setValueAtTime(plan.rate, plan.fadeEnd);
      src.playbackRate.linearRampToValueAtTime(1, plan.rateEnd);
      g.setValueAtTime(0, plan.start);
      g.linearRampToValueAtTime(1, plan.fadeEnd);
      src.start(plan.start);
    } else {
      g.setValueAtTime(1, when);
      src.start(when);
    }
    this.index = i;
    this.plan = plan;
    this.current = { src, gain };
    this.scheduled = false;
    /* and when this one hands over, in wall time */
    this.nextAt = plan ? wallTimeFor(plan, t.out) : when + t.out;
  }

  /** The one after this, skipping any that never arrived. */
  _next(i) {
    for (let k = 1; k <= this.tracks.length; k++) {
      const j = (i + k) % this.tracks.length;
      if (this.buffers[j]) return j;
    }
    return -1;
  }

  /** Once a frame. Puts the next handover on the schedule when it is
   *  within LOOKAHEAD, which is all the work there is. */
  tick() {
    if (!this.playing || this.scheduled || !this.ctx) return;
    if (this.ctx.currentTime < this.nextAt - LOOKAHEAD) return;
    const j = this._next(this.index);
    if (j < 0) return;
    const a = this.tracks[this.index], b = this.tracks[j];
    const plan = arrange(a, b, this.nextAt);
    /* the outgoing: down to nothing over the fade, then off */
    const out = this.current;
    out.gain.gain.setValueAtTime(1, this.nextAt);
    out.gain.gain.linearRampToValueAtTime(0, plan.fadeEnd);
    out.src.stop(plan.fadeEnd + 0.05);
    /* and the incoming becomes the current, with its own handover
       four minutes off and not yet on the schedule */
    this._play(j, plan.start, plan);
  }
}
