/* =====================================================================
   MEWD — the fire, drawn
   =====================================================================

   Every flame in the game comes out of this file: the fire on a shelf,
   the blaze a whole gondola turns into, the embers left on the floor
   afterwards, the fire climbing a fir, the pilot light on the gun and
   the flash at the muzzle. One generator, four sizes, so all of it is
   visibly the same fire.

   IT WAS SOMEBODY ELSE'S ART UNTIL NOW. Four twenty-frame painted strips
   from the golf project, run through a tool that tried to round off
   their feet with a mask. That is what this replaces, and the reason is
   worth writing down, because it is the whole design of what is here:

     A MASK CANNOT ROUND A BOTTOM. The painted flames were drawn standing
     on the ground, so the widest, brightest row of every frame is its
     LAST row — a hard horizontal edge. A mask can pinch that row in from
     the sides, and the old tool did, but every surviving column still
     ENDS ON THE SAME ROW. Narrowing a flat edge leaves a narrower flat
     edge. To curve the bottom you have to lift the flame's foot per
     column, and once you are deciding where every column ends you are no
     longer masking a picture, you are drawing one.

   SO IT IS DRAWN, AND THE ROUND BOTTOM IS THE FIRST THING DRAWN. The
   flame is a chain of circles: a BALL at the foot, then a column of
   smaller and smaller circles up to a point. The bottom of the shape is
   the bottom of that ball, which is round because a circle is. There is
   no row where the flame stops; there is a curve where it stops, and
   nothing about the way it is made could have produced a flat edge. That
   is what a fire hanging in the air off a burning branch needs — it
   reads as sitting ON something from any angle, without the engine
   having to know what it is sitting on.

   FOUR MORE THINGS MAKE IT A FIRE RATHER THAN A LAVA LAMP:

     THE LICK. The chain of circles does not run straight up. Its axis
     sways, anchored at the foot and loosest at the tip, so the flame
     leans and whips instead of standing there pulsing.

     THE BITE. A noise field scrolling upward eats into the edge of that
     shape and pushes tongues out of it — hardly at all down at the ball,
     where the fuel is, and hard at the top, where a flame is coming
     apart into separate licks. This is what stops the silhouette from
     looking like a balloon.

     THE STREAKS. A second noise field, finer and climbing twice as
     fast, which never touches the silhouette and only decides how hot
     each pixel inside it is. Without it the brightness falls off in a
     smooth gradient and the thing reads as a glowing egg with tongues
     on top, however good the outline is.

     THE HEAT. White at the foot, through the fire ramp's whole route to
     a dull red at the tip and at every edge. Most of a flame is the dull
     end; the white heat is a few pixels at the base. That is the shape
     of the painted strips too, which is the one thing about them worth
     keeping, and it is why palette.js gives fire forty-four entries —
     but it is spent on EIGHT BANDS rather than a smooth ramp, because
     forty-four smooth steps give an airbrushed blob and eight give the
     contour bands a painted flame has, with the streaks deciding where
     they fall.

   AND IT LOOPS EXACTLY. The old generator was the PSX Doom fire routine
   — seed the bottom row, cool and shift each row from the one below —
   which is a simulation, and a simulation cannot be made to come back to
   where it started. It popped once a loop, for ever, on every fire on
   screen. The noise here REPEATS: the lattice wraps after a whole number
   of rows and the scroll over `count` frames is exactly that distance,
   so the last frame hands over to the first with nothing moving. A fire
   is on screen from the moment you light it until the building falls
   down, which is long enough for a pop every second to be the thing
   people notice about it.

   NOTHING IS SNAPPED, because there is nothing to snap: every colour
   here comes out of `ramp('fire', t)` and is already one of the game's
   256. Running snap() over it would only cost the soft edge, which the
   additive flames on the trees want and the alpha-tested ones in the
   store throw away by themselves.
   ===================================================================== */

import { Pix } from './pixel.js';

/* --------------------------------------------------------------------
   How many frames each fire gets

   Shared with js/states.js, which builds the looping state chains, so
   the animation tables and the bakery cannot drift apart.

   TWENTY IS NOT DECORATION. The pattern has to climb the sprite at a
   believable rate AND get back to where it started at the end, so the
   distance it travels in a loop is fixed by the frame count: fewer
   frames means bigger jumps between them, and a fire that steps four
   pixels a frame reads as a strobe. Twenty is where it stops looking
   stepped. The embers get fewer because they barely move.
   ------------------------------------------------------------------ */
export const FIRE_FRAMES  = 20;
export const BLAZE_FRAMES = 20;
export const EMBER_FRAMES = 14;

/* Where the lowest point of the flame sits in its cell, measured up from
   the bottom row as a fraction of the height. Anything that has to stand
   a flame ON something — the wood's fire, on a branch part-way up a fir —
   parks the quad's centre this far above the thing it is standing on, so
   the round foot lands where the fuel is. */
export const FLAME_FOOT = 0.05;

/* --------------------------------------------------------------------
   The shape, in fractions of the cell
   ------------------------------------------------------------------ */
const FLAME = {
  wide:  0.58,   // widest half-width, as a fraction of the half cell
  tall:  0.21,   // and as a fraction of the flame's own height, whichever is less
  slim:  1.15,   // how fast it closes going up — bigger is a longer, finer tip
  lick:  0.50,   // how far the tip wanders, as a fraction of the half cell
  bite:  1.05,   // how far the noise moves the edge, against the widest half-width
  grain: 0.17,   // noise cell, as a fraction of the cell width
  rise:  0.075,  // how far the pattern climbs per frame, as a fraction of the height
  warp:  1.40,   // above 1, the pattern speeds up as it rises
  discs: 26,     // how many circles the body is made of
  foot:  FLAME_FOOT,
  head:  0.10,   // headroom above the tip, for the licks that break off it
};

const clamp01 = t => t < 0 ? 0 : t > 1 ? 1 : t;

/* Three octaves of value noise land in about 0.5 +/- 0.15, which as a
   displacement is a wobble nobody would see. This opens it out to
   roughly +/-1 so `bite` can be read as what it says it is: a fraction
   of the flame's own width. */
const NGAIN = 2.6;

/* How many steps of heat a flame is drawn in. See the banding note down
   in the pixel loop: this is the difference between a painted flame and
   an airbrushed one. */
const BANDS = 8;

/* --------------------------------------------------------------------
   Noise that comes back round

   Value noise on a lattice whose rows wrap after `period` of them. Shift
   the sample by exactly `period * cell` pixels and every lattice index
   lands on itself: same field, no seam, no cross-fade. That is the only
   unusual thing about it — the interpolation is the ordinary smoothstep
   one, and the hash is the ordinary integer mix.
   ------------------------------------------------------------------ */
function ihash(x, y, s) {
  let n = Math.imul(x | 0, 374761393) ^ Math.imul(y | 0, 668265263) ^ Math.imul(s | 0, 2246822519);
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

function loopNoise(x, y, cell, period, s) {
  const gx = Math.floor(x / cell), gy = Math.floor(y / cell);
  const fx = x / cell - gx, fy = y / cell - gy;
  const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  const ya = ((gy % period) + period) % period, yb = (ya + 1) % period;
  const a = ihash(gx, ya, s), b = ihash(gx + 1, ya, s);
  const c = ihash(gx, yb, s), d = ihash(gx + 1, yb, s);
  const top = a + (b - a) * u;
  return top + ((c + (d - c) * u) - top) * v;
}

/** Three octaves. Each halves the cell and doubles the period, so they
 *  all repeat over the same distance and the sum repeats with them. */
function loopFbm(x, y, cell, period, s) {
  return 0.54 * loopNoise(x, y, cell, period, s)
       + 0.31 * loopNoise(x, y, cell * 0.5, period * 2, s + 91)
       + 0.15 * loopNoise(x, y, cell * 0.25, period * 4, s + 197);
}

/* ====================================================================
   One fire

   @param w,h    the cell, in pixels — 64 at most, like everything else
   @param count  frames in the loop
   @param seed   which fire; two fires with different seeds sway and
                 tear differently and are otherwise the same fire
   @param opts   `taper` is the one knob the callers use and it means
                 what it has always meant here: how fat the flame is.
                 Everything in FLAME above can be overridden beside it.
   ==================================================================== */
export function fireFrames(w, h, count, seed = 7, opts = {}) {
  const F = { ...FLAME, ...opts };
  const fat = 0.72 + 0.5 * (opts.taper ?? 0.55);      // about 1 at the default

  const cx = (w - 1) * 0.5;
  const halfW = (w - 1) * 0.5;
  const yFoot = (h - 1) * (1 - F.foot);      // the row the lowest point sits on
  const H = yFoot - (h - 1) * F.head;        // rows from there to the tip
  /* A FLAME IS TALLER THAN IT IS WIDE, whatever cell it is handed. The
     particle system draws square quads, so the atlas the wood's fire
     comes out of is a square picture — and a flame drawn to the width of
     a square cell is a fireball. Width against the CELL and width against
     the flame's OWN HEIGHT, whichever is the tighter, so the same numbers
     give a flame in a 32 by 48 and a flame in a 64 by 64. */
  const Rmax = Math.min(halfW * F.wide, H * F.tall) * fat;

  /* THE WIDEST CIRCLE IS THE LOWEST ONE, and that is not a look, it is
     the invariant that makes the bottom round and keeps it round for
     any cell and any setting.

     Every circle above the ball is SMALLER and sits HIGHER, so its
     lowest point is above the ball's, so nothing in the chain can reach
     below the foot and the underside of the shape is the underside of
     one circle. Let the profile flare above the ball instead — and it is
     tempting, real flames do flare — and the circles at the flare dip
     below the ball on both sides, the union bottoms out along a line
     between them, and the flat edge is back. That is exactly how the
     old masked strips failed, arrived at from the other direction. */
  const R0 = Rmax;
  const radiusAt = s => Math.max(0.4, Rmax * Math.pow(1 - s, F.slim));

  /* The sway. Two waves at whole-number frequencies in the loop phase,
     so this comes back round with everything else, times s squared to
     pin the foot: a fire's base is where its fuel is and does not move,
     and only the top of it whips. */
  const leanAt = (s, ph) => halfW * F.lick * Math.pow(s, 1.6) *
    (0.62 * Math.sin(ph + s * 3.1 + seed) + 0.38 * Math.sin(2 * ph + s * 5.9 + 2.1));

  /* The pattern's travel, rounded to whole lattice rows — which is what
     makes the loop exact, so it is the period that is rounded and the
     rise that follows from it, never the other way round. */
  const grain = Math.max(2.5, w * F.grain);
  const period = Math.max(2, Math.round((h * F.rise * count) / grain));
  const span = period * grain;

  const field = new Float32Array(w * h);
  const pad = Math.ceil(Rmax * F.bite * 0.5) + 2;
  const out = [];

  for (let f = 0; f < count; f++) {
    const ph = 2 * Math.PI * f / count;

    /* --- the shape: the largest of the circles at every pixel, which
       for a chain of overlapping circles is the distance into the
       union of them, positive inside --- */
    field.fill(-1e9);
    for (let j = 0; j < F.discs; j++) {
      const s = j / (F.discs - 1);
      const r = radiusAt(s);
      const ax = cx + leanAt(s, ph), ay = yFoot - (R0 + s * (H - R0));
      const x0 = Math.max(0, Math.floor(ax - r - pad)), x1 = Math.min(w - 1, Math.ceil(ax + r + pad));
      const y0 = Math.max(0, Math.floor(ay - r - pad)), y1 = Math.min(h - 1, Math.ceil(ay + r + pad));
      for (let y = y0; y <= y1; y++) {
        const dy = y - ay;
        for (let x = x0; x <= x1; x++) {
          const dx = x - ax;
          const d = r - Math.sqrt(dx * dx + dy * dy);
          const i = y * w + x;
          if (d > field[i]) field[i] = d;
        }
      }
    }

    /* --- the pixels --- */
    const p = new Pix(w, h, seed + f, false);
    const scroll = (f / count) * span;
    for (let y = 0; y < h; y++) {
      const py = yFoot - y;
      const s = clamp01(py / H);
      /* Sampled against a warped height so the pattern accelerates on
         the way up, which is what hot gas does, while the SCROLL stays
         uniform and the loop stays exact. */
      const ny = H * Math.pow(s, F.warp) - scroll;
      for (let x = 0; x < w; x++) {
        const d = field[y * w + x];
        if (d < -Rmax) continue;
        const n = loopFbm(x - cx, ny, grain, period, seed);
        /* A SECOND FIELD, finer, stretched tall and climbing twice as
           fast — twice as far in a loop is still a whole number of
           periods, so this comes back round too. It never touches the
           silhouette; it is the streaking INSIDE the flame, and it is
           what stops a smooth brightness gradient from reading as a
           glowing egg with tongues on top. */
        const ns = loopFbm((x - cx) * 2.2, ny * 0.55 - scroll * 2, grain, period, seed + 313);
        /* THE BITE, in pixels of edge, centred on the noise's own mean so
           it pushes tongues out as often as it eats notches in. Nothing
           at the ball, where the fuel is and the flame is solid; enough
           at the top to sever a lick off the tip entirely. */
        const dn = d + F.bite * Rmax * (0.15 + s * s) * (n - 0.5) * NGAIN;
        const a = dn * 0.95 + 0.5;
        if (a <= 0.03) continue;
        /* HOW HOT. Mostly a function of HEIGHT — white at the foot, down
           the ramp's whole route to a dull red at the tip — with the
           outer couple of pixels darker again, because the edge of a
           flame is the part in contact with the air. A brightness that
           falls off radially instead reads as a glowing egg. */
        let heat = (0.22 + 0.78 * Math.pow(1 - s, 2.4)) * (0.52 + 0.48 * clamp01(dn / 2.4))
                 * (0.78 + 0.44 * ns);
        /* THE FUEL: a little extra heat right in the ball, kept small
           and kept noisy. A clean bright ellipse down there stops being
           a fire and becomes a light bulb, and the top of the ramp is
           white, which is a colour a fire should barely reach. */
        const bx = x - cx, by = py - R0 * 0.9;
        const ball = clamp01(1 - Math.sqrt(bx * bx + by * by) / (R0 * 1.1));
        heat = heat + 0.20 * ball * ball;
        /* BANDED, like everything else in this game. Forty-four entries
           of fire ramp spent on a smooth gradient give a soft airbrushed
           blob; spent on eight steps they give the contour bands a
           painted flame has, and the streaks above decide where those
           bands fall. */
        const band = Math.round(clamp01(Math.min(0.97, heat * (0.84 + 0.30 * n))) * BANDS) / BANDS;
        p.ink(x, y, 'fire', band, Math.round(Math.min(1, a) * 255));
      }
    }
    out.push(p);
  }
  return out;
}
