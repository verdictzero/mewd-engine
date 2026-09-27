/* =====================================================================
   DEWM — the positron beam
   =====================================================================

   WHAT THE USER ASKED FOR: "the beam from Wing Zero's buster rifle,
   everything in linear path destroyed, like a linear columnar nuclear
   explosion". Every decision in this file is downstream of that
   sentence, so it is worth being precise about what it describes.

   IT IS NOT A LASER. A laser is a line you draw to a hit point and it
   stops at the first thing it touches. This is a COLUMN two to eight
   metres across that is drawn from the muzzle to the far side of the
   map and does not stop at anything, because nothing it touches is
   still there afterwards. There is no hit point. The whole segment is
   the hit.

   IT IS NOT AN EVENT. A shot happens in a tic; this lasts three to five
   seconds and does its work every tic of that (see js/player.js,
   BEAM_SECONDS). What that buys is the one thing the weapon is for: the
   player is nailed to the floor while it is out, but the barrel is not,
   so a discharge is something you LEAN across a street. The line moves,
   and everything the line has crossed by the time it stops is gone.

   ---------------------------------------------------------------------
   THE FOUR THINGS IT DOES, and the order is the order of the tic

     1  the bodies      everything soft inside the column, every tic,
                        for enough that there is no survivable stage
     2  the buildings   integrity off every region the column passes
                        through, on a slower clock — see PASS_EVERY
     3  the fire        heat and accelerant laid down the whole length,
                        store grid and woodland both, so what the beam
                        did not finish burns
     4  the picture     fireballs and dust up the line, which is what
                        makes it read as a column of detonation rather
                        than a strip light

   WHY THE BUILDINGS ARE ON A SLOWER CLOCK THAN THE BODIES. Taking a
   region down is a walk over the fire grid — see FireSystem.damageLine,
   which is where that walk lives, because the grid belongs to the fire
   and not to this. A stage-three column is eight metres across and a
   hundred and sixty metres long, and the box that bounds it is a good
   part of the town: doing it thirty-five times a second for five
   seconds is a hundred and seventy-five sweeps of a grid to answer a
   question whose answer changes about ten times. PASS_EVERY makes it
   about twelve times a second, with the bite multiplied to match, so
   the same amount of building comes down and the arithmetic happens
   a third as often. Bodies are a flat loop over the actor list and
   cost nothing, so they run every tic where the player can see them.

   ---------------------------------------------------------------------
   HOW IT IS DRAWN, and why it is a TUBE

   The obvious way to draw a beam is the way js/tracers.js draws a
   round: a quad spread sideways along the axis that is across both the
   line and the line to the eye, so it faces you however you stand. That
   is right for a tracer and catastrophically wrong for this one,
   because of WHO IS LOOKING. A tracer is something you watch go past. A
   beam is something you are firing, which means the eye is at one end
   of it looking along it — and a view-facing quad seen exactly end-on
   is a line one pixel wide. The most important beam in the game would
   be invisible to the only person who ever sees it.

   So it is real geometry: a tube of SIDES sides and SEGS rings, rebuilt
   every frame around the current axis. Looking down a tube shows you
   the inside of a tube, which is exactly the shot — a ring of light
   receding to a point — and looking across one shows you a column.

   THREE OF THEM, NESTED, because a column of light is not one colour.
   The core is white and lit through its whole face; the body is the
   yellow-white of the first half second of something nuclear; the halo
   is the lance's own lens green and is lit only at its SILHOUETTE,
   which is what makes it read as a volume of glow rather than a painted
   pipe. Fresnel against the view direction is the whole of that
   difference and it is two lines of shader.

   AND RINGS TRAVELLING OUT OF THE MUZZLE, which is the Gundam shot and
   not a flourish: a column with nothing moving along it has no speed
   and no direction, and five seconds of a static glowing pipe reads as
   a prop. The rings say which end it came from.

   All of it additive, none of it writing depth, one draw call.
   ===================================================================== */

import * as THREE from 'three';
import { world } from './material.js';

/* HOW FAR IT REACHES, in game units. The town is about six thousand
   across and the store another two: this crosses either of them and
   keeps going, which is the point — the shot is a line THROUGH the map
   and not a line within it. */
export const BEAM_RANGE = 8200;

/* AND HOW WIDE, by stage, and this is the number the whole dial-back
   turns on.

   It was 46, 82 and 130: a person is thirty-two units across, so the
   top stage was a column eight people wide that took the entire front
   of a house at once. You did not aim it, you pointed it, and whatever
   was within four metres of what you meant went with the thing you
   meant. That is a weapon of mass destruction and at the user's request
   this is not one any more.

   A radius of twenty-four is forty-eight across: one and a half people
   rather than eight, and a sixth of the width. It takes the person the
   crosshair was on and at most a shoulder of whoever is pressed against
   them, instead of the house they were standing in front of — which is
   the difference between a siege engine and a rifle, and it is a single
   number.

   AND IT CANNOT GO NARROWER, which is the part worth writing down. This
   radius is also the radius of the hole the shot bores through every
   wall it crosses (see breaches.cut below), and the player is thirty-
   two units across: at forty-eight there are eight units of clearance
   either side and you can walk through your own hole, which is a thing
   this game already promises. At thirty you could not. Twenty-four is
   the floor and the reason is collision, not taste.

   IT IS STILL VISIBLE, which was the other worry. Forty-eight units at
   five hundred away is about fifty pixels on an 853-wide render, and it
   is an additive tube with nested shells and a bloom over the top of
   it. What it stops being is the whole screen. */
export const BEAM_RADIUS = [10, 16, 24];

/* WHAT IT DOES TO SOMETHING SOFT, per tic, by stage. There is no
   survivable stage and there is not meant to be: the smallest of these
   is nine times a shopper's health in one thirty-fifth of a second.
   Narrowing the column did not soften it and should not have — a
   positron lance that grazed you and left you standing would be a
   worse weapon and a stranger one. What changed is how much of the
   street is inside it, not what being inside it costs. */
export const BEAM_DAMAGE = [900, 1800, 3200];

/* AND TO A BUILDING: integrity off a region at the centre of the
   column, per pass. A region starts at 1.

   THESE USED TO BRING A HOUSE DOWN IN ONE SHOT — 1.30 a pass at the top
   stage, which is the whole of a region's integrity in a single pass,
   with fifty-odd passes left to go. Every discharge levelled whatever
   it was aimed through, and the hole the beam punched in the front of
   the building was academic because the building followed it down a
   quarter of a second later.

   Now no single shot can take anything down, at any stage, however
   squarely it is aimed: the absolute worst a stage-three discharge can
   do to one region is 0.50, and the measured figure against the town is
   0.34. THREE shots do it. You hold four cells, so levelling a building
   costs three quarters of everything you have and twenty-one seconds of
   charging — a decision rather than a side effect of shooting at a man
   standing in front of it. That is the dial-back in one line: you can
   still do it, and you can no longer do it by accident.

   TWO THINGS TO MIND IN THE ARITHMETIC, both of which bit while these
   numbers were being set:

     PASS_EVERY. These are per pass and the CALLER multiplies by it, so
     a stage-three discharge is 49 tics = 16 passes x 3 x 0.0105 = 0.50,
     not 16 x 0.0105. Forgetting that factor is how the first cut of
     this table came out at 1.34 and levelled a house in one shot
     anyway — the exact thing it was written to stop.

     AND 0.50 IS THE CEILING, NOT THE FIGURE. damageLine bites
     `amount * (1 - |t| / radius)` and keeps the largest bite any sample
     of a region took (see FireSystem.damageLine), so only a region the
     column's dead centre passes through gets the whole of it. Measured
     against the town the worst-hit region loses 0.34 a shot, which is
     where the three comes from. The suite checks the CEILING, because
     that is the part that can be proved from the constants and is also
     the part that matters: under 1.0 means never in one shot. */
export const BEAM_STRUCTURE = [0.0028, 0.0058, 0.0105];

/* HOW MUCH HEAT AND ACCELERANT IT LEAVES, by stage. It was 200, 320
   and 470, which set fire to the whole street it crossed — appropriate
   for a weapon that had just flattened the street, and absurd for one
   that has drilled a hole through a wall. A quarter of it: the line is
   scorched, what was already flammable along it catches, and the town
   does not go up every time you take a shot. */
export const BEAM_HEAT = [40, 70, 110];

/* TICS BETWEEN STRUCTURAL PASSES. See the note above: the bite is
   multiplied by this, so the building comes down at the same rate and
   the grid is walked a third as often. */
export const PASS_EVERY = 3;

/* HOW FAR FROM THE AXIS THE LIGHT REACHES, by stage: several times the
   column's own radius, because what the user asked to see is the street
   either side of it picked out, not a glow hugging the tube. See the
   note on beamPos in js/material.js for the shader end of this. */
export const LIGHT_RANGE = [190, 300, 440];
/* AND HOW HARD. These were more than twice this to begin with and the
   first screenshot of a stage-three discharge was a white rectangle:
   between the column, the wash on the readout, the bloom and this, four
   separate things were each bright enough on their own. The column is
   the one that should be blinding; this is the STREET, and a street lit
   past white has stopped being a street.

   AND THEY CAME DOWN AGAIN with the column, by about the same ratio the
   radius did. A tube a fifth as wide throwing the same light was the
   giveaway that the old numbers were painting a nuclear flash rather
   than lighting a beam: what you want now is the line picked out along
   the ground and the wall beside it, so you can see where the shot
   went. */
export const LIGHT_PEAK = [0.26, 0.38, 0.55];

/* AND HOW LONG IT OUTLIVES THE BEAM, in seconds. The axis is left
   exactly where the last tic of the column was and the intensity falls
   off over this — so the street stays lit by a thing that is not there
   any more, which is the "post charge" the user asked for and is also
   simply what a discharge that size does to your eyes. */
export const AFTERGLOW = 0.9;

/* ---------------------------------------------------------------------
   THE COLUMN IS NAILED TO THE LINE IT WAS FIRED ALONG

   There is a real problem here and it is worth stating before the fix,
   because the fix used to be the opposite of this.

   A beam fired from the gun in your hands, along the line you are
   looking down, is seen END-ON. Always. However you turn, the column
   turns with you and what is on screen is its cross-section: a bright
   disc in the middle of the frame. That is geometrically unavoidable
   and it is what the first three screenshots of this were — a glowing
   blob over a lawn, with none of the length that is the entire point of
   the thing.

   THE FIRST ANSWER WAS INERTIA. The barrel said where the column wanted
   to be and the column chased it, at a time constant, so while you
   swept it trailed twenty degrees behind and you saw its side. It
   worked, and it cost the one thing this weapon is now for: the damage
   followed the DRAWN column rather than the crosshair, so where the
   shot landed depended on how you happened to be moving your wrist as
   you let go. You could not aim it. You could only point it and lean.

   THE SECOND ANSWER IS BETTER AT BOTH JOBS. The line — origin AND
   direction — is taken once, at the instant the trigger comes up, and
   never moves again. So:

     it goes exactly where the crosshair was, which is the whole of
     what the user asked for in asking for a sniper;

     and the end-on problem solves itself more completely than the lag
     ever solved it, because the moment you turn your head AT ALL the
     column is no longer in front of you. It is a fixed line in the
     world and you are looking across it. Turn ninety degrees and you
     see the entire eight thousand units of it in profile.

   The feet are nailed down for the second and a half either way (see
   Player.move), so the origin cannot drift more than the width of your
   own shoulders; and the head is free now precisely BECAUSE the line
   does not follow it — see the note where BEAM_TURN used to be in
   js/player.js.

   It is also more true than the lag was. Eight thousand units of plasma
   does not pivot because you moved your wrist — and it does not trail
   round after it either. It goes where it was pointed when it left. */

/* THE SHAKE, in radians of view and units of eye, at the peak.

   IT IS A KICK NOW AND NOT A RUMBLE. It was 1.0 settling to a hum of
   0.34 over half a second, and that was right for a five-second column
   you steered: the picture had to keep saying "this is enormous and it
   is still happening" for the whole of it. This one is over in a second
   and a half and you are not steering it, so what the picture has to
   say is that a very large thing just LEFT — hard on the first few
   frames and then almost nothing, so you can watch where the shot went
   instead of watching the screen wobble.

   The hum is not zero. A trace of it says the column is still out. */
export const SHAKE_PEAK = 0.62;
export const SHAKE_HUM = 0.05;
/* and how many tics it takes to settle from the one to the other: a
   fifth of a second, against the half it used to take, because the
   whole discharge is now shorter than the old settle plus its hum */
export const SHAKE_SETTLE = 7;

/* The tube. Twelve sides is round enough at the size this is ever seen
   and cheap enough to rebuild three times a frame; twenty-eight rings
   is enough for the flare at the muzzle and the pulse along the length
   to be curves rather than facets. */
export const SIDES = 16;
export const SEGS = 28;
/* ---------------------------------------------------------------------
   AND THE NEAR END IS CAPPED, BECAUSE A TUBE IS HOLLOW

   The shells are tubes, which is right from the side and is a hole from
   the front — and the front is where the player always is. Looking down
   the bore of a hollow additive pipe you see past the near opening, all
   the way down the inside to the taper at the far end, and THROUGH it
   to the world beyond: the middle of the column comes out as a dim disc
   of whatever is behind it. That is what the third screenshot of this
   was, a green dome with a white ring round it, and it is the same
   class of mistake as the Fresnel one above — geometry that reads
   correctly from an angle nobody will ever look at it from.

   So the two inner shells — the two lit flat, which is not a
   coincidence: a cap is a flat disc and a Fresnel would band it — are
   closed at the near end with a triangle fan. One extra vertex each.
   Seen down the bore it is a filled white disc; seen from the side it
   is edge-on and contributes nothing, which is exactly the right
   behaviour in both cases.

   CAP_SEG rather than segment zero, because segment zero is inside HIDE
   and is drawn at nothing. */
export const CAPS = 2;
export const CAP_SEG = 1;

/* and the shock rings travelling out of the muzzle */
export const RINGS = 5;
export const RING_SPEED = 0.55;           // of the beam's length a second
/* how many points along the line get particles thrown at them each tic */
export const SAMPLES = 16;

/* ---------------------------------------------------------------------
   THE FOUR SHELLS, innermost first, AND WHAT LIGHTS EACH ONE

   `rim` is the whole of the difference and it is not a style knob, it is
   the answer to a bug. Fresnel — brighter where the surface turns away
   from you — is what makes a hollow tube read as a VOLUME of glow rather
   than as a painted pipe, and it is right for the outer shells. It is
   exactly wrong for the innermost one, because of where the eye is.

   The player fires this thing along their own line of sight, so they are
   looking straight DOWN the bore. Every surface of the tube is then seen
   edge-on: the radial normal is perpendicular to the view, Fresnel is at
   its maximum everywhere at once, and a shell lit by it is brightest in
   a RING and darkest in the middle. Three of those nested is a
   bullseye — which is precisely what the first screenshot of this was,
   a dark green target floating over a lawn, and not a beam at all.

   So the core is lit FLAT: one is one, whichever way you are looking at
   it, and it fills its own disc with white. Seen from the side it is a
   white rod; seen down the bore it is a white sun. Both are what a beam
   core is. The shells outside it keep their Fresnel and are what give it
   an edge.

     r       radius as a multiple of the stage's
     colour  what it is
     rim     0 flat, 1 mild Fresnel, 2 silhouette only
     w       how much of it there is
   ------------------------------------------------------------------- */
const SHELLS = [
  { r: 0.34, colour: [1.00, 1.00, 1.00], rim: 0, w: 1.70 },
  { r: 0.62, colour: [1.00, 0.99, 0.84], rim: 0, w: 1.05 },
  { r: 0.94, colour: [0.90, 1.00, 0.66], rim: 1, w: 0.50 },
  { r: 1.36, colour: [0.44, 1.00, 0.64], rim: 2, w: 0.20 },
];

/* ---------------------------------------------------------------------
   THE NECK, AND WHY IT IS IN WORLD UNITS AND NOT IN A FRACTION

   The first cut of this flared the column over the first five per cent
   of its length, which on an eight-thousand-unit beam is four hundred
   units and sounded reasonable. It is not, because of where the EYE is.
   The column is born at the muzzle, which is about forty-six units in
   front of the player (see NOZZLE_REACH in js/weapon3d.js), and at the
   third stage it is a hundred and thirty units in radius. Forty-six is
   less than a hundred and thirty: the player is standing INSIDE the
   first section of their own beam, looking at the inside of a
   double-sided additive tube from a few centimetres away, which is a
   white screen and nothing else. That is exactly what the first
   screenshot of it was.

   So the column opens out over NECK world units — a real distance, from
   the metal — and is not DRAWN at all over the first HIDE of them. What
   covers the join is the muzzle bloom, which is particles and is meant
   to be there anyway: a beam leaves a gun in a ball of light, and the
   ball is where the tube would have been in your face.

   AND BOTH CAME DOWN WITH THE COLUMN. They were 430 and 190, tuned
   against a stage-three radius of 130 where the player really was
   standing inside their own beam — the muzzle is about forty-six units
   out and the tube was a hundred and thirty across, so there was no
   choice. At a radius of twenty-four the eye is comfortably OUTSIDE the
   tube and hiding the first hundred and ninety units of it would only
   be drawing a shot that starts two car lengths in front of the gun,
   which for a weapon you are supposed to be aiming looks like a fault.
   Fifty-five is just past the metal, where the muzzle bloom is.

   THEY STILL SCALE WITH THE RADIUS, as ratios of the top stage's, so
   anything wider than the lance pushes them back out and cannot put the
   eye inside its own column again. At the top stage the two agree
   exactly and the ratio changes nothing; it is a floor under a wider
   beam and not a number anything currently uses. */
export const NECK = 120;
export const HIDE = 55;
/* how many radii of neck and of hide, which is what those two are */
export const NECK_R = NECK / BEAM_RADIUS[BEAM_RADIUS.length - 1];
export const HIDE_R = HIDE / BEAM_RADIUS[BEAM_RADIUS.length - 1];

const VERT = /* glsl */`
attribute vec3 aNormal;
attribute vec3 aColour;
attribute float aRim;
attribute float aFade;
varying vec3 vC;
varying float vRim;
varying float vFade;
varying vec3 vN;
varying vec3 vV;
void main() {
  vC = aColour;
  vRim = aRim;
  vFade = aFade;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  vN = normalize(normalMatrix * aNormal);
  vV = normalize(-mv.xyz);
  gl_Position = projectionMatrix * mv;
}
`;

/* FRESNEL IS THE WHOLE DIFFERENCE between a rod and a glow. `aRim` at 0
   is a surface lit through its face and dimmed a little where it turns
   away, which is a solid bar of light; at 1 it is lit ONLY where it
   turns away, which is a shell that is bright at its own outline and
   transparent through the middle — a volume. Both are additive, so the
   three of them together are a white centre inside a yellow body inside
   a green corona, and the corona is brightest exactly where the eye
   would expect a column of glare to be. */
const FRAG = /* glsl */`
varying vec3 vC;
varying float vRim;
varying float vFade;
varying vec3 vN;
varying vec3 vV;
void main() {
  float f = 1.0 - abs(dot(normalize(vN), normalize(vV)));
  /* three lightings, picked by vRim — see SHELLS for why the innermost
     one must not be a Fresnel at all */
  float flat_ = 1.0;
  float mild = 1.0 - f * 0.30;
  float shell = pow(f, 1.7) * 1.9;
  float lit = vRim < 0.5 ? flat_ : (vRim < 1.5 ? mild : shell);
  /* banded, like everything else that is drawn in this game */
  lit = floor(lit * 10.0 + 0.5) / 10.0;
  gl_FragColor = vec4(vC * lit * vFade, 1.0);
}
`;

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
/* the world's tic rate, which this file needs only to turn AFTERGLOW's
   seconds into tics — see fade */
const TICRATE = 35;

export class BeamSystem {
  constructor(game) {
    this.game = game;
    this.live = false;
    this.stage = 0;
    this.tics = 0;              // how many tics the beam has been out
    this.total = 0;             // how many it will be out for
    this.pass = 0;              // the structural clock
    this.shots = 0;             // how many have been fired, for the tests
    this.downed = 0;            // regions brought down by the one in progress
    this.holed = 0;             // and walls it has punched a hole through
                                /* as a MAX over the passes, not a sum
                                   — see the note in tic() */
    this.killed = 0;
    /* where the column is THIS tic — recomputed every tic from the
       player, because the barrel moves while the feet do not */
    this.from = { x: 0, y: 0, z: 0 };
    this.angle = 0;
    this.slope = 0;
    this.mesh = null;
    this._v = null;
    /* THE LIGHT OUTLIVES THE COLUMN, so it is its own little state: the
       axis frozen where the beam last was, and a level falling to
       nothing over AFTERGLOW seconds. `glow` is 0..1 of LIGHT_PEAK. */
    this.glow = 0;
    this.glowStage = 1;
    this.lit = { x: 0, y: 0, z: 0, dx: 1, dy: 0, dz: 0, len: 1 };
    /* and how hard the picture is being shaken, 0..1 — read by
       Game.render, which is the only place the eye is placed */
    this.shake = 0;
  }

  get radius() { return BEAM_RADIUS[this.stage - 1] || 0; }
  /** 0 at the muzzle flash, 1 as it dies — what the geometry fades on. */
  get age() { return this.total > 0 ? this.tics / this.total : 0; }

  /* ------------------------------------------------------------------
     Firing
     ------------------------------------------------------------------ */

  /** The trigger came up at `stage`. js/player.js has already spent the
   *  cell and nailed the feet down; this starts the column. */
  fire(player, stage) {
    this.live = true;
    this.stage = clamp(stage | 0, 1, BEAM_RADIUS.length);
    this.tics = 0;
    this.total = player.beamTics || 1;
    this.pass = 0;
    this.shots++;
    this.downed = 0;
    this.holed = 0;
    this.killed = 0;
    /* THE LINE, TAKEN ONCE AND KEPT. See _aim: nothing moves it again
       until the next shot, which is what makes this a rifle. */
    this._aim(player);
    /* THE MUZZLE GOES FIRST. A column that simply appears has no
       beginning; a flash and a ring of dust at the metal is the half
       second that says it left a gun. Smaller than it was, because the
       column behind it is a fifth of the width it was and a muzzle
       bloom wider than its own beam reads as an explosion at the gun
       rather than a shot leaving one. */
    const g = this.game;
    const f = this.from;
    for (let i = 0; i < 11; i++)
      g.fx?.fireball(f.x, f.y, f.z, 18 + i * 5, 8 + (i & 7));
    g.fx?.wash?.(f.x, f.y, f.z, 1.1);
    g.spawnSparks?.(f.x, f.y, f.z, 12);
    this.shake = 1;
    this.glow = 1;
    this.glowStage = this.stage;
  }

  stop() {
    /* WHAT THE SHOT WENT THROUGH, said once, in the corner.

       This is the one piece of feedback a weapon like this genuinely
       cannot do without. It reaches eight thousand units along a street
       and through whatever is standing in the way, and almost all of
       what it does happens where you cannot see it from where you fired
       it: the man on the roof two blocks down, the four walls the line
       passed through on the way to him. Without a line saying so, a
       clean kill at range and a clean miss at range look exactly alike
       — a bright column, and then nothing.

       Only when it did something, and only ever one line. A shot that
       hit nobody and went through nothing says nothing, which is itself
       the answer to "did I get him". */
    if (this.live && (this.killed || this.holed)) {
      const said = [];
      if (this.killed) said.push(`${this.killed} DOWN`);
      if (this.holed) said.push(`${this.holed} THROUGH`);
      if (this.downed) said.push(`${this.downed} COLLAPSED`);
      this.game.toast?.(said.join('  \u00b7  '));
    }
    this.live = false;
    this.stage = 0;
    this.tics = 0;
    /* the light is NOT stopped: it stays on the axis it was on and
       fades over AFTERGLOW seconds — see the note there */
  }

  /** WHERE THE SHOT GOES, TAKEN ONCE. The muzzle if the model is loaded
   *  and the eye if it is not, and the direction is where the player is
   *  looking at the instant the trigger comes up.
   *
   *  CALLED FROM fire() AND NOWHERE ELSE, which is the whole of the note
   *  above: the line is fixed for the length of the discharge, so the
   *  damage lands where the crosshair was and turning your head shows
   *  you the column in profile instead of dragging it round after you.
   *  It used to be called every tic with a first-order chase in it. */
  _aim(player) {
    const n = this.game.nozzle?.();
    if (n) { this.from.x = n.x; this.from.y = n.y; this.from.z = n.z; }
    else { this.from.x = player.x; this.from.y = player.y; this.from.z = player.eyeZ; }
    this.angle = player.angle;
    /* the pitch as a RISE PER UNIT of ground travelled, because that is
       what a walk over a floor grid wants — see FireSystem.damageLine */
    this.slope = Math.tan(clamp(player.pitch, -1.4, 1.4));
  }

  /* ------------------------------------------------------------------
     One tic of it
     ------------------------------------------------------------------ */
  tic(player) {
    if (!this.live) return;
    this.tics++;
    /* AND THE LINE IS NOT RE-READ. _aim used to run here, chasing the
       barrel; the shot is fixed at the trigger now — see the note above
       _aim and the one at the head of this file. */
    const g = this.game;
    const r = this.radius;

    /* ---- 1. everything soft in the column --------------------------- */
    this._bodies(player, r);

    /* ---- 2. and everything standing in it, on the slower clock ------ */
    if (++this.pass >= PASS_EVERY) {
      this.pass = 0;
      this.downed += g.fire?.damageLine(this.from, this.angle, this.slope, BEAM_RANGE, r,
                                        BEAM_STRUCTURE[this.stage - 1] * PASS_EVERY) || 0;
      /* AND A HOLE THROUGH EVERY WALL IT CROSSES, at the user's
         request. Integrity is a question about whether a REGION is
         still standing; this is a question about the brick itself, and
         they are not the same question — a beam through the front of a
         house leaves a hole in the front of the house long before the
         house comes down, and usually instead of it. See js/breach.js. */
      /* MAX AND NOT PLUS, and this mattered the moment the number
         started being shown to the player rather than only to the
         tests. cut() returns how many walls it opened on THAT pass, and
         the line does not move any more, so every pass after the first
         re-opens the same ones: a shot through 39 walls accumulated to
         624 over sixteen passes and the gun cheerfully said so. The
         most any one pass opened IS the number of walls the line
         crosses, because the first pass opens all of them. */
      this.holed = Math.max(this.holed,
        g.breaches?.cut(this.from, this.angle, this.slope, BEAM_RANGE, r) || 0);
    }

    /* ---- 3. what it sets alight ------------------------------------- */
    this._burn(r);

    /* ---- 4. and what it looks like on the ground -------------------- */
    this._dress(r);

    /* ---- and the light, which is the column's own axis --------------- */
    const cp = 1 / Math.hypot(1, this.slope);
    const L = this.lit;
    L.x = this.from.x; L.y = this.from.y; L.z = this.from.z;
    L.dx = Math.cos(this.angle) * cp; L.dy = Math.sin(this.angle) * cp; L.dz = this.slope * cp;
    L.len = BEAM_RANGE;
    this.glow = 1;
    this.glowStage = this.stage;

    /* THE SHAKE: everything in the first fifth of a second and almost
       nothing after it. See SHAKE_PEAK — it is a kick now rather than a
       rumble, because the thing worth looking at is where the shot
       went. */
    const settle = Math.min(1, this.tics / SHAKE_SETTLE);
    this.shake = SHAKE_PEAK + (SHAKE_HUM - SHAKE_PEAK) * settle;
  }

  /** The light fading after the column has gone, and the shake with it.
   *  Once a frame off the wall clock rather than once a tic, because
   *  both are things the EYE does and neither is part of the world. */
  ticLight(dt) {
    if (!this.live) {
      this.glow = Math.max(0, this.glow - dt / AFTERGLOW);
      this.shake = Math.max(0, this.shake - dt * 2.6);
    }
    if (!world.beam) return;
    const g = this.glow;
    world.beam.value = g * g * (LIGHT_PEAK[this.glowStage - 1] || 1);
    if (g > 0) {
      const L = this.lit;
      /* game coordinates into the renderer's, which is the one
         conversion everything in this game does at its own edge */
      world.beamPos.value.set(L.x, L.z, -L.y);
      world.beamDir.value.set(L.dx, L.dz, -L.dy);
      world.beamLen.value = L.len;
      world.beamRange.value = LIGHT_RANGE[this.glowStage - 1] || 400;
      /* the clock the flicker rides — see the shader. It runs fast
         while the beam is out and slows as the afterglow dies, so the
         light settles rather than strobing to the last frame. */
      world.beamSeed.value = (world.beamSeed.value + dt * (4.0 + 14.0 * g)) % 6283.0;
    }
  }

  /** Everything shootable within the column, every tic. A flat loop over
   *  the actor list: a thing is a vertical capsule and the beam is a
   *  segment, so the test is the distance from its middle to the line. */
  _bodies(player, r) {
    const g = this.game;
    const ux = Math.cos(this.angle), uy = Math.sin(this.angle);
    const f = this.from;
    const dmg = BEAM_DAMAGE[this.stage - 1];
    for (const a of g.actors) {
      if (a === player || a.removed || a.dead || !a.shootable) continue;
      const wx = a.x - f.x, wy = a.y - f.y;
      const s = wx * ux + wy * uy;
      if (s < 0 || s > BEAM_RANGE) continue;
      const px = wx - ux * s, py = wy - uy * s;
      const reach = r + (a.radius || 16);
      if (px * px + py * py > reach * reach) continue;
      /* and at the height the column is at over them */
      const bz = f.z + this.slope * s;
      const lo = a.z, hi = a.z + (a.height || 56);
      if (bz + r < lo || bz - r > hi) continue;
      const was = a.dead;
      a.damage(dmg, player, { fire: true });
      a.ignite?.(600);
      if (!was && a.dead) this.killed++;
    }
  }

  /** Heat and accelerant the whole length of it, store grid and
   *  woodland both, at intervals rather than at every cell: the fire
   *  spreads on its own and a stripe of ignitions a radius apart joins
   *  up inside a tic. */
  _burn(r) {
    const g = this.game;
    const ux = Math.cos(this.angle), uy = Math.sin(this.angle);
    const f = this.from;
    const step = Math.max(64, r * 1.4);
    const heat = BEAM_HEAT[this.stage - 1];
    for (let s = 0; s <= BEAM_RANGE; s += step) {
      const bz = f.z + this.slope * s;
      const x = f.x + ux * s, y = f.y + uy * s;
      /* ONLY WHERE THE COLUMN IS NEAR THE GROUND. A shot up the road at
         ten degrees is over the roofs by the end of the street, and a
         beam that lit the pavement under it wherever it happened to be
         in the sky would set fire to the whole town from one shot
         through a first-floor window. */
      if (bz > 400 + r) continue;
      g.fire?.ignite(x, y, heat, r);
      g.forest?.ignite(x, y, r * 1.1);
    }
  }

  /** The dust and the fire coming off it. Sampled rather than swept:
   *  a handful of points a tic, moved along the line each tic, so five
   *  seconds of beam lays a continuous stem of fire up the whole length
   *  without ever spawning more than a dozen particles in one of them. */
  _dress(r) {
    const g = this.game;
    if (!g.fx) return;
    const ux = Math.cos(this.angle), uy = Math.sin(this.angle);
    const f = this.from;
    /* SAMPLED ALONG THE LINE AND MOVED EVERY TIC, rather than swept:
       SAMPLES points a tic, offset by a fraction that walks, so five
       seconds of beam lays a continuous stem of fire up the whole
       length without ever spawning more than a couple of dozen
       particles in one of them. Sixteen and not seven, at the user's
       request — this is the biggest thing that happens in this game and
       it should look like it. */
    const n = SAMPLES;
    const step = BEAM_RANGE / n;
    const jitter = (this.tics * 0.37) % 1;
    for (let i = 0; i < n; i++) {
      const s = (i + jitter) * step;
      const bz = f.z + this.slope * s;
      if (bz > 700 + r) continue;
      /* AND SCATTERED ACROSS THE COLUMN, not on its centre line. A stem
         of fire exactly on the axis is a line of fire; thrown anywhere
         inside the radius it is a column of it, which is the word the
         user used. */
      const th = Math.random() * Math.PI * 2, rr = Math.sqrt(Math.random()) * r;
      const x = f.x + ux * s - uy * Math.cos(th) * rr;
      const y = f.y + uy * s + ux * Math.cos(th) * rr;
      const z = Math.max(0, bz + Math.sin(th) * rr);
      /* AND THE FAR ONES ARE THE BIG ONES, which is the opposite of the
         first cut and is a lesson about where the player is standing.
         Weighting the size toward the NEAR end sounds right — that is
         where the column is biggest on screen — and what it actually
         did was park a two-hundred-unit fireball a few metres from the
         eye every tic, so the shot was a bonfire in your face with the
         beam somewhere behind it. Near the muzzle they are small and
         pale, which reads as the column's own glare; a hundred metres
         out they are enormous, which reads as the town going up. */
      const near = 1 - i / n;
      const far = i / n;
      if (i === 0 || Math.random() < 0.55 + near * 0.45)
        g.fx.fireball(x, y, z, r * (0.42 + far * 1.25), 14 + (i & 7));
      if (i > 0 && Math.random() < 0.8)
        g.fx.puff(x, y, Math.max(0, z - r * 0.4), r * (0.55 + far * 1.4), 90 + (i & 31));
      /* embers thrown out of the column sideways, which is the detail
         that says it is chewing through something */
      if (Math.random() < 0.5) g.fx.ember?.(x, y, z, 1, 1);
    }
    /* and sparks at the metal, every tic, so the muzzle is always the
       brightest thing in the picture */
    g.spawnSparks?.(f.x, f.y, f.z, 4);
    /* with a small hard bloom at the metal that keeps pace with the
       shake — small, because this one is at arm's length */
    if ((this.tics & 1) === 0) g.fx.fireball(f.x, f.y, f.z, r * 0.55, 9);
  }

  /* ------------------------------------------------------------------
     The picture
     ------------------------------------------------------------------ */

  /** Build the three shells and the rings once. Positions are rewritten
   *  every frame; the index buffer and the per-vertex colours never
   *  change, because which shell a vertex belongs to never does. */
  attach(scene) {
    const bands = SHELLS.length * (SEGS + 1) + RINGS * 2;   // rings of vertices
    const verts = bands * (SIDES + 1) + CAPS;               // and one centre per cap
    const geo = new THREE.BufferGeometry();
    const pos = new Float32Array(verts * 3);
    const nrm = new Float32Array(verts * 3);
    const col = new Float32Array(verts * 3);
    const rim = new Float32Array(verts);
    const fade = new Float32Array(verts);
    /* the colours, which are decided by which band a vertex is in and
       never move after this */
    let v = 0;
    for (const sh of SHELLS)
      for (let i = 0; i <= SEGS; i++)
        for (let k = 0; k <= SIDES; k++, v++) {
          col[v * 3] = sh.colour[0]; col[v * 3 + 1] = sh.colour[1]; col[v * 3 + 2] = sh.colour[2];
          rim[v] = sh.rim;
        }
    /* and the shock rings, which are white and lit at their edge */
    for (let i = 0; i < RINGS * 2; i++)
      for (let k = 0; k <= SIDES; k++, v++) {
        col[v * 3] = 1; col[v * 3 + 1] = 1; col[v * 3 + 2] = 0.92;
        rim[v] = 1;
      }
    /* and the cap centres, in their own shell's colour and lit flat */
    const capBase = v;
    for (let c = 0; c < CAPS; c++, v++) {
      const sh = SHELLS[c];
      col[v * 3] = sh.colour[0]; col[v * 3 + 1] = sh.colour[1]; col[v * 3 + 2] = sh.colour[2];
      rim[v] = 0;
    }

    /* the index buffer: every band joined to the next one in its own
       run, and a run never joins across a shell boundary */
    const idx = [];
    const quad = (a, b) => { idx.push(a, b, b + 1, a, b + 1, a + 1); };
    let base = 0;
    for (let sh = 0; sh < SHELLS.length; sh++) {
      for (let i = 0; i < SEGS; i++)
        for (let k = 0; k < SIDES; k++)
          quad(base + i * (SIDES + 1) + k, base + (i + 1) * (SIDES + 1) + k);
      base += (SEGS + 1) * (SIDES + 1);
    }
    for (let i = 0; i < RINGS; i++) {
      for (let k = 0; k < SIDES; k++) quad(base + k, base + (SIDES + 1) + k);
      base += 2 * (SIDES + 1);
    }
    /* the caps: a fan from each centre to the CAP_SEG ring of its own
       shell — see the note on CAPS */
    for (let c = 0; c < CAPS; c++) {
      const ring = c * (SEGS + 1) * (SIDES + 1) + CAP_SEG * (SIDES + 1);
      for (let k = 0; k < SIDES; k++) idx.push(capBase + c, ring + k, ring + k + 1);
    }

    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('aNormal', new THREE.BufferAttribute(nrm, 3));
    geo.setAttribute('aColour', new THREE.BufferAttribute(col, 3));
    geo.setAttribute('aRim', new THREE.BufferAttribute(rim, 1));
    geo.setAttribute('aFade', new THREE.BufferAttribute(fade, 1));
    geo.setIndex(idx.length < 65536 ? new THREE.BufferAttribute(new Uint16Array(idx), 1)
                                    : new THREE.BufferAttribute(new Uint32Array(idx), 1));
    geo.setDrawRange(0, 0);
    const mat = new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG,
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide, fog: false, toneMapped: false,
    });
    this.mesh = new THREE.Mesh(geo, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 13;
    this.mesh.name = 'beam';
    this._v = { pos, nrm, fade, indices: idx.length };
    scene.add(this.mesh);
    return this.mesh;
  }

  /**
   * Rebuild the column around the axis it is on this frame.
   *
   * @param time  seconds, for the pulse and the rings
   */
  render(time = 0) {
    if (!this.mesh) return;
    const geo = this.mesh.geometry;
    if (!this.live || this.stage < 1) { geo.setDrawRange(0, 0); return; }
    const { pos, nrm, fade } = this._v;
    const R = this.radius;
    /* the neck and the hidden stub, in world units, off THIS column's
       width rather than off the widest one anybody had in mind when the
       constants were written — see the note at NECK */
    const neckLen = Math.max(NECK, R * NECK_R);
    const hideLen = Math.max(HIDE, R * HIDE_R);

    /* the axis, in game coordinates, and two perpendiculars to sweep the
       rings around */
    const cp = 1 / Math.hypot(1, this.slope);
    const dx = Math.cos(this.angle) * cp, dy = Math.sin(this.angle) * cp, dz = this.slope * cp;
    /* any vector that is not the axis, crossed with it twice */
    let ax = 0, ay = 0, az = 1;
    if (Math.abs(dz) > 0.9) { ax = 1; az = 0; }
    let e1x = dy * az - dz * ay, e1y = dz * ax - dx * az, e1z = dx * ay - dy * ax;
    let l = Math.hypot(e1x, e1y, e1z) || 1;
    e1x /= l; e1y /= l; e1z /= l;
    const e2x = dy * e1z - dz * e1y, e2y = dz * e1x - dx * e1z, e2z = dx * e1y - dy * e1x;

    const f = this.from;
    /* THE LAST HALF SECOND DIES BACK rather than blinking out, and the
       first two tics come up from nothing, so the column has a shape in
       time as well as in space. */
    const a = this.age;
    const life = Math.min(1, this.tics / 2) * (a > 0.86 ? 1 - (a - 0.86) / 0.14 : 1);

    let v = 0;
    const put = (x, y, z, nx, ny, nz, fd) => {
      /* game coordinates into three's: x across, z up, -y into the
         screen, which is the one conversion every mesh in this game
         does at its own edge */
      pos[v * 3] = x; pos[v * 3 + 1] = z; pos[v * 3 + 2] = -y;
      nrm[v * 3] = nx; nrm[v * 3 + 1] = nz; nrm[v * 3 + 2] = -ny;
      fade[v] = fd;
      v++;
    };

    for (const sh of SHELLS) {
      for (let i = 0; i <= SEGS; i++) {
        const t = i / SEGS;
        const s = t * BEAM_RANGE;
        /* the profile: a neck at the metal opening out over NECK units
           of real distance (see the note there — this is the number that
           stops the player standing inside their own beam), a slow pulse
           along the length, and a taper at the far end so the column
           recedes rather than being cut off */
        const neck = 0.05 + 0.95 * Math.min(1, s / neckLen);
        const pulse = 1 + 0.12 * Math.sin(t * 26 - time * 9);
        const tail = 1 - 0.55 * Math.max(0, (t - 0.9) / 0.1);
        const rad = R * sh.r * neck * pulse * tail;
        /* and nothing at all within HIDE of the muzzle: what is there is
           the bloom, which is particles */
        const near = Math.min(1, Math.max(0, (s - hideLen * 0.25) / hideLen));
        const fd = life * sh.w * near;
        const cx = f.x + dx * s, cy = f.y + dy * s, cz = f.z + dz * s;
        for (let k = 0; k <= SIDES; k++) {
          const th = (k / SIDES) * Math.PI * 2;
          const c = Math.cos(th), si = Math.sin(th);
          const nx = e1x * c + e2x * si, ny = e1y * c + e2y * si, nz = e1z * c + e2z * si;
          put(cx + nx * rad, cy + ny * rad, cz + nz * rad, nx, ny, nz, fd);
        }
      }
    }

    /* the shock rings, travelling out of the muzzle and widening as
       they go, each on its own phase so they are a stream and not a
       pulse */
    for (let i = 0; i < RINGS; i++) {
      const trav = ((time * RING_SPEED + i / RINGS) % 1);
      const s = trav * BEAM_RANGE;
      const rad = R * (1.25 + trav * 1.7) * (0.06 + 0.94 * Math.min(1, s / neckLen));
      const wide = R * 0.055;
      /* DIM, and dimmer than the first cut by a lot: a ring is a thing
         that moves and a moving thing is read at a fraction of the
         brightness of a still one. At half this they were five
         concentric bright circles round the muzzle, which is a target
         and not a shock front. */
      const fd = life * (1 - trav) * 0.26 * Math.min(1, Math.max(0, (s - hideLen * 0.25) / hideLen));
      for (const off of [-wide, wide]) {
        const cx = f.x + dx * (s + off), cy = f.y + dy * (s + off), cz = f.z + dz * (s + off);
        for (let k = 0; k <= SIDES; k++) {
          const th = (k / SIDES) * Math.PI * 2;
          const c = Math.cos(th), sn = Math.sin(th);
          const nx = e1x * c + e2x * sn, ny = e1y * c + e2y * sn, nz = e1z * c + e2z * sn;
          put(cx + nx * rad, cy + ny * rad, cz + nz * rad, nx, ny, nz, fd);
        }
      }
    }

    /* and the cap centres, on the axis at CAP_SEG, facing back down the
       beam at whoever fired it */
    for (let c = 0; c < CAPS; c++) {
      const s = (CAP_SEG / SEGS) * BEAM_RANGE;
      const fd = life * SHELLS[c].w * Math.min(1, Math.max(0, (s - hideLen * 0.25) / hideLen));
      put(f.x + dx * s, f.y + dy * s, f.z + dz * s, -dx, -dy, -dz, fd);
    }

    geo.attributes.position.needsUpdate = true;
    geo.attributes.aNormal.needsUpdate = true;
    geo.attributes.aFade.needsUpdate = true;
    geo.setDrawRange(0, this._v.indices);
  }
}
