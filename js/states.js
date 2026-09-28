/* =====================================================================
   MEWD — state tables
   =====================================================================

   Doom's monsters are a linked list of states. Each one says which
   sprite frame to show, how many tics to show it for, one function to
   call the moment it starts, and which state to go to next. That is the
   entire animation system and the entire AI scheduler, and it is the
   reason a Doom monster feels like it has WEIGHT: the thing cannot
   change its mind mid-frame, because the frame owns the next several
   tics and there is nowhere for a change of mind to go.

   Read a run of states out loud and you have the animation:

     RUN: A 4, A 4, B 4, B 4, C 4, C 4, D 4, D 4, back to the start

   Each walk frame is held twice — eight states, four drawings — which
   makes the cycle 32 tics, a bit under a second, which is the pace of a
   walk. A_Chase runs on every one of those eight, so the monster gets
   eight chances a cycle to notice you have moved.

   TIMING IS IN TICS, always. 35 to the second, exactly as Doom.

   WHAT IS IN THE SHOP NOW is not a monster. The staff used to be: two
   of them, the Zombieman and the Imp with the numbers filed off, with
   walk cycles, pain frames, attacks and two ways of dying each. They are
   gone. What stands in the aisles instead is a crowd of SHOPPERS, and a
   shopper has exactly one state and one frame, because a shopper is one
   drawing seen from every side (see js/people.js for why that is the
   right way to use this art rather than a corner cut).

   So most of this file is now fire, fittings and the things a fire
   leaves behind, and the only run of states with any length to it is the
   fireball a person turns into.

   THE MACHINERY UNDER IT IS UNTOUCHED. A_Look, A_Chase and the rest of
   Doom's chase are still in js/actor.js with nothing calling them,
   because the responders in js/responders.js will, and forty lines of
   P_NewChaseDir is not something to delete and write again.
   ===================================================================== */

import { SHOPPERS, SPLATS, ASHES, BLASTS, TROOPS } from './people.js';
import { FIRE_FRAMES, BLAZE_FRAMES, EMBER_FRAMES } from './fireart.js';
import { TICRATE } from './util.js';

/* Every state: [sprite, frame, tics, action, next]. -1 tics means stay
   here forever, which is what a corpse does. */
export const STATES = {};

function S(name, sprite, frame, tics, action, next, opts = {}) {
  STATES[name] = { name, sprite, frame, tics, action, next, ...opts };
}

/* ---------------------------------------------------------------------
   THE SHOPPERS

   Standing there is the whole animation, and it is one frame held for
   ever. `variants` on the actor turns the sprite name SHOP into SHO0,
   SHO1 ... SHO16 — the same hook the cars will use — so seventeen
   different people share one state and one line of table.

   There is no death sequence because there is nothing left to animate:
   one tic in which A_Gib throws the pieces, and then the actor is gone.

   AND THEY RUN. Standing is A_Watch on an eight-tic clock, which sniffs
   the fire grid round the actor; anything hot near enough and it goes to
   SHOP_RUN, which is A_Flee every three tics until the panic runs out
   and there is nothing hot left nearby. Both states draw the same single
   frame, because there is only one; the difference is entirely that one
   of them moves.
   ------------------------------------------------------------------- */
S('SHOP_STAND',  'SHOP', 'A', 8, 'A_Watch', 'SHOP_STAND2');
S('SHOP_STAND2', 'SHOP', 'A', 8, 'A_Watch', 'SHOP_STAND');
/* Running is the same drawing on a shorter clock. What makes it read as
   running is not the frame, it is that the thing is moving and leaning
   harder while it does — see swayOf in js/people.js. */
S('SHOP_RUN1',   'SHOP', 'A', 3, 'A_Flee', 'SHOP_RUN2');
S('SHOP_RUN2',   'SHOP', 'A', 3, 'A_Flee', 'SHOP_RUN1');

/* AND THEN THERE IS BEING ON FIRE, which is a third way of standing in
   the same drawing and the most useful thing a person in this building
   does.

   Somebody the flame touches used to come apart where they stood: twelve
   health against eight a tic is a person deleted in the first tenth of a
   second, and what the fire got out of it was thirteen pieces thrown a
   couple of aisles and a pool of heat where they had been. At the user's
   request they now RUN — alight, for several seconds, dropping fire the
   whole way — and go off wherever they get to.

   That is not a death animation, it is a DELIVERY MECHANISM. A fire
   spreads at a cell every second or so through bare lino; a burning
   shopper covers eight units a tic in a straight line towards a door
   they are never going to reach, through the cross-aisles the fire
   cannot cross by itself, and then explodes in the middle of whatever is
   on the other side. Set light to the queue at the tills and the back of
   the store is alight in twenty seconds — not because the fire travelled
   but because the people did.

   Two tics a frame rather than three, so somebody alight outruns
   somebody merely frightened. A_Torch does the rest: it tops the panic
   up (nobody calms down while they are burning), and it counts down to
   the bang. Fullbright, because they are lit by the fire on them and
   that is what makes one legible across a dark shop. */
S('SHOP_BURN1',  'SHOP', 'A', 2, 'A_Torch', 'SHOP_BURN2', { fullbright: true });
S('SHOP_BURN2',  'SHOP', 'A', 2, 'A_Torch', 'SHOP_BURN1', { fullbright: true });
S('SHOP_GIB',    'SHOP', 'A', 1, 'A_Gib', null);      // null next: remove me
/* AND FROZEN, which is one frame and no action at all. The state exists
   so a frozen shopper stops running A_Flee — Actor.freeze parks it here
   with tics -1, this engine's "rest for ever", and the thaw sets them
   going again from `see`. It is the same drawing as every other shopper
   state; what makes it read as ice is the colour map in js/material.js,
   which is a fact about the SHADER and not about the animation. */
S('SHOP_FROZE',  'SHOP', 'A', -1, null, 'SHOP_FROZE');
/* AND BURNING AWAY, which is what a block of ice does when the fire
   reaches it. Also one drawing, also no movement, and the animation is
   not in this table at all: A_BurnAway winds a number from 0 to 1 and
   the sprite shader eats the picture with it, from the feet up, with a
   line of coals at the front. Fullbright for the same reason SHOP_BURN
   is — the light on them is the fire on them.

   It is a LOOP with no end state, because what ends it is the number
   reaching one and not the clock running out: see Actor.collapse. */
S('SHOP_ASH1',   'SHOP', 'A', 4, 'A_BurnAway', 'SHOP_ASH2', { fullbright: true });
S('SHOP_ASH2',   'SHOP', 'A', 4, 'A_BurnAway', 'SHOP_ASH1', { fullbright: true });
/* AND WITH A DRILL IN THEIR HEAD, which is the third hold and the
   shortest: two seconds of standing exactly where they were, shaking,
   while the bore does its work, and then Actor.boreBurst. Parked with
   tics -1 the way the ice is; what moves is the drawing offset in
   Actor.render and the blood out of js/people.js. See js/bore.js. */
S('SHOP_BORE',   'SHOP', 'A', -1, null, 'SHOP_BORE');

/* ---------------------------------------------------------------------
   THE TROOPS

   The things in the game that FIGHT, and the first run of states with
   any length to it since the staff left. It is the Zombieman's table
   with the numbers looked at again: stand and look, walk in eight
   states over four drawings, face and fire and face again, flinch, fall
   in four, lie there, and — if what killed them was enough — come apart
   in nine.

   ONE TABLE, TWO TROOPS, AND ROOM FOR A THIRD. The SWAT and the army
   are the same sheet layout — see TROOPS in js/people.js, where the
   letters are a contract between the cutting tool and the loader — so
   they are the same table, written once and stamped out under each
   troop's own prefix and sprite. SWAT_RUN1 and ARMY_RUN1 are the same
   state on different paint, which is what they are on the sheets. The
   super army, when its drawings arrive, is a third call and nothing
   else. What is NOT shared is the actor: how much of them there is, how
   hard they hit and how fast they come is per troop, below.

   THEY HAVE EVERY SIDE. The sheets are five views mirrored to eight (see
   TROOP_ROTATIONS in js/people.js), so a trooper walking away from you
   shows you their back, which no shopper can — and which is the whole of
   what makes a thing you can walk round read as a thing rather than a
   card. A_Chase sets `angle` to the way it is walking; A_FaceTarget
   turns it to you before it fires; the rotation is chosen per frame in
   Actor.render off the difference.

   THE FIRING FRAME IS ORANGE ON BOTH SHEETS — the artist drew the muzzle
   flash lighting the whole figure — so it is fullbright, and the state
   table does not need to know how the light on it got there.

   THE COLD DOES TO THEM WHAT IT DOES TO EVERYBODY ELSE: they freeze
   into a block that the next blow shatters, on the same state and the
   same shader a shopper does — see SHOP_FROZE. The fire does NOTHING to
   either of them, at the user's request: no burn, no ash, and the two
   ash states that used to sit here are gone with the flag that made
   them reachable. See the actors below for the whole of it.
   ------------------------------------------------------------------- */
/**
 * One troop's whole table, under its own prefix, on its own sprite.
 *
 * @param key     the prefix — SWAT, ARMY — and the actor's type
 * @param sprite  the four-letter sprite name its frames are under
 * @param attack  the action its firing frame calls
 */
function troopStates(key, sprite, attack) {
  const N = n => `${key}_${n}`;
  S(N('STAND'), sprite, 'G', 10, 'A_Look', N('STAND'));
  /* three tics a frame, four drawings held twice: a walk a shade
     quicker than the Zombieman's, because these have come to get you */
  [...'AABBCCDD'].forEach((f, i) =>
    S(N(`RUN${i + 1}`), sprite, f, 3, 'A_Chase', N(`RUN${(i + 1) % 8 + 1}`)));
  /* Doom's rifle: face, fire, face — ten, eight, eight — and then a step
     before the next, which A_Chase's "never twice in a row" guarantees
     and which is the window you play in */
  S(N('ATK1'), sprite, 'E', 10, 'A_FaceTarget', N('ATK2'));
  S(N('ATK2'), sprite, 'F', 8, attack, N('ATK3'), { fullbright: true });
  S(N('ATK3'), sprite, 'E', 8, 'A_FaceTarget', N('RUN1'));
  S(N('PAIN'),  sprite, 'G', 3, null, N('PAIN2'));
  S(N('PAIN2'), sprite, 'G', 3, 'A_Pain', N('RUN1'));
  /* down in six and lying in the seventh, which stays */
  const DOWN = [['H', 5, null], ['I', 5, 'A_Scream'], ['J', 5, 'A_Fall'],
                ['K', 6, null], ['L', 6, null], ['M', 6, null]];
  DOWN.forEach(([f, t, a], i) =>
    S(N(`DIE${i + 1}`), sprite, f, t, a, i === DOWN.length - 1 ? N('DEAD') : N(`DIE${i + 2}`)));
  S(N('DEAD'), sprite, 'N', -1, null, null);
  /* coming apart: nine drawings at five tics, and the last one stays */
  const GIB = 'OPQRSTUVW';
  [...GIB].forEach((L, i, arr) =>
    S(N(`XDIE${i + 1}`), sprite, L, i === arr.length - 1 ? -1 : 5,
      i === 0 ? 'A_XScream' : i === 1 ? 'A_Fall' : null,
      i === arr.length - 1 ? null : N(`XDIE${i + 2}`)));
  S(N('FROZE'), sprite, 'G', -1, null, N('FROZE'));
  S(N('BORE'),  sprite, 'G', -1, null, N('BORE'));
  /* no ash states: a trooper is fireproof and nothing eats one — see
     the actors below */
}
troopStates('SWAT', TROOPS.SWAT.sprite, 'A_SwatFire');
troopStates('ARMY', TROOPS.ARMY.sprite, 'A_ArmyFire');

/* ---------------------------------------------------------------------
   Things that are not monsters
   ------------------------------------------------------------------- */
S('TRLY_STAND',  'TRLY', 'A', -1, null, null);
S('BOLL_STAND',  'BOLL', 'A', -1, null, null);
/* two stones — a round-topped one and a cross — picked per actor the
   way the splats are, so a cemetery is not one stone repeated */
S('GRAV_STAND',  'GRV0', 'A', -1, null, null);
S('GCAN_STAND',  'GCAN', 'A', -1, null, null);
S('CRAT_STAND',  'CRAT', 'A', -1, null, null);
/* What is left where somebody was. Three paintings, picked per actor
   the same way the shoppers are, so a floor covered in these does not
   read as one stamp repeated. */
S('BLUD_REST',   'BLUD', 'A', -1, null, null);
/* And the grey one, which is what is left when the fire finishes
   somebody rather than something else hitting them. */
S('ASH_REST',    'ASH0', 'A', -1, null, null);

/* THE LIGHTS HAVE NO STATES, because they have no sprite. There were
   ten of them here — lit, burst, dead for ever, one tube gone, and a
   ring of six that a dying ballast stuttered round — and the fitting
   they all drew is painted into the ceiling now (T.CEILFIT). A light in
   this game is a source and a target and nothing you can see, so the
   only trace of one going out is the sparks below it and the aisle
   above going dark. See ACTORS.LAMP at the bottom of this file. */
S('SPARK1', 'SPRK', 'A', 3, null, 'SPARK2');
S('SPARK2', 'SPRK', 'B', 3, null, 'SPARK3');
S('SPARK3', 'SPRK', 'C', 4, null, null);

/* The flame that sits on something burning. Loops for ever; the fire
   system removes it when the fuel runs out. The lengths come from
   js/fireart.js, which draws the frames — a chain shorter than the set
   it plays would simply never show the rest of them, and one longer
   would ask the bank for a letter nobody drew. */
const chain = (name, frames, tics) =>
  Array.from({ length: frames }, (_, i) =>
    S(`${name}${i + 1}`, name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[i], tics, null,
      `${name}${(i + 1) % frames + 1}`, { fullbright: true }));
chain('FIRE', FIRE_FRAMES, 2);
chain('BLAZ', BLAZE_FRAMES, 2);
chain('EMBR', EMBER_FRAMES, 3);

/* THE FIREBALL a person becomes. Twenty-six frames at a tic each is
   three quarters of a second: a flash at the floor, a column of fire up
   past head height, and then eight frames of it going to smoke and
   coming apart. It is the longest animation in the game and the only one
   that is worth watching. */
const BLAST_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.slice(0, BLASTS);
[...BLAST_LETTERS].forEach((L, i, arr) =>
  S(`BLAST${i + 1}`, 'BLST', L, 1, null,
    i === arr.length - 1 ? null : `BLAST${i + 2}`, { fullbright: true }));

/* Blood in the air, which then is not. */
S('PUFF1', 'PUFF', 'A', 4, null, 'PUFF2');
S('PUFF2', 'PUFF', 'B', 4, null, 'PUFF3');
S('PUFF3', 'PUFF', 'C', 4, null, null);      // null next = remove me

/* =====================================================================
   Actor types

   Doom's mobjinfo, minus the fields nothing here uses. Health, speed and
   painchance are the three that decide how a monster feels, and they are
   Doom's numbers because Doom's numbers are correct.
   ===================================================================== */
export const ACTORS = {
  /* A SHOPPER. Twelve health, which is less than one tic of the
     flamethrower delivers, so anything you point the stream at comes
     apart at once — the weapon is the verb and there is no wrestling
     with a health bar. Solid, so a crowd is something you have to get
     through; flammable, so a fire that reaches one takes it; and worth
     ninety of fuel to the floor underneath, because a person on fire in
     an aisle is how the aisle catches.

     No speed, no sight range, no attack: they are not fighting you. The
     things that will fight you come up the road later. */
  SHOPPER: {
    name: 'Shopper', spawn: 'SHOP_STAND', see: 'SHOP_RUN1', death: 'SHOP_GIB',
    health: 12, radius: 18, height: 56, mass: 100, painchance: 0,
    /* Sixteen units a call at three tics a call: faster than a Doom
       zombie and slower than you, so a crowd that has decided to leave
       is something you have to get in front of rather than something you
       can walk after. */
    speed: 16,
    monster: true, flammable: true, fuel: 90, painSound: 'shopper',
    /* WHAT CATCHING FIRE DOES TO ONE. `burn` is the state they go to the
       moment they are alight, and `burnTics` is how long they have: three
       and a half to seven seconds of running before they go off, rolled
       per person so a queue that catches together does not pop together.

       The range is the whole of the feel. Under two seconds and it reads
       as a delayed death rather than as somebody on fire; over ten and
       the shop fills up with torches that never resolve and the player
       stops watching any of them. Three to seven is about the length of
       an aisle at a panicked run, which is the distance that makes the
       mechanic mean something. */
    burn: 'SHOP_BURN1', burnTics: [3.5 * TICRATE, 7 * TICRATE],
    /* AND THE OTHER END OF IT. `freezable` is what the extinguisher's
       stream is allowed to work on; `frozen` is where they are parked
       while it holds; and coming out of it they RUN, because nobody
       goes back to the shelves after that. */
    freezable: true, frozen: 'SHOP_FROZE', freezeReturn: 'SHOP_RUN1',
    /* AND WHAT FIRE DOES TO ONE WHO IS STILL IN THE ICE, which is not
       what it does to anybody else. `burnAway` is the state, and
       `ashTics` is how long the whole of it takes — rolled per person so
       a row of them frozen and then swept does not finish together.
       Three to four and a half seconds: long enough to watch a person
       be eaten, short enough that the player does not go and do
       something else while it happens. */
    burnAway: 'SHOP_ASH1', ashTics: [3.0 * TICRATE, 4.5 * TICRATE],
    /* and where they stand while the bore is in them — see js/bore.js */
    bored: 'SHOP_BORE',
    /* AND WHAT THEY LEAVE BEHIND THEM. A drop every eight tics at eight
       units a tic is a line of fire with sixty-four-unit steps in it,
       which on a thirty-two-unit grid is two cells lit and one skipped —
       near enough continuous that the fire behind them joins up.

       burnFuel is FOURTEEN and the number is chosen against a threshold
       rather than by feel: a cell that is ignited starts at 55 heat plus
       the strength, js/fire.js lights anything standing in a cell above
       70, and 55 + 14 is 69. So the trail starts a FIRE and does not
       itself set light to the person it is running past — that cell
       climbs over the threshold a fire tic or two later, by which time
       the runner is fifty units away and whoever catches, catches off
       the floor like everybody else. One below the line, deliberately:
       a trail that lights bystanders directly turns a crowd into a
       chain reaction with nothing in between.

       burnRadius is ONE, meaning the cell they are standing in and not
       the ninety-six-unit square the default lights. A person is a
       person wide. */
    burnTrail: 8, burnFuel: 14, burnRadius: 1,
    /* and how far the sight of them clears. Less than the nine hundred
       a fireball clears, more than the three hundred and twenty a fire
       is noticed at: somebody alight coming down the aisle is worse news
       than the fire they came from and better news than the bang. */
    burnScare: 520,
    /* how far a fire has to be before it is somebody else's problem, and
       how long a fright lasts once nothing is chasing it */
    scareRange: 320, panicTics: 8 * TICRATE,
    variants: SHOPPERS,
    /* one drawing, so every side of them is the front */
    flat: true,
    /* and it leans where it stands — see swayOf in js/people.js */
    sway: true,
  },

  /* A SWAT TROOPER, and the Zombieman's numbers looked at again. Sixty
     health: five times a shopper, though the stream never gets at it —
     see FIREPROOF below. A rifle bullet does, from the man behind him.

     THEY SHOOT. `missile` is the rifle, `missileRange` is how far they
     will try it from, and the whole of the aim is in A_SwatFire. Fifty
     of painchance is one hit in five that makes them flinch, so a
     bullet interrupts one sometimes and not always.

     THEY ARE A TEAM, and so is everybody else who turns up. `team` is
     what stops a trooper who has just been shot in the back by the man
     behind him turning round to deal with it — Doom's monsters infight
     and it is the best thing about them, and it is also the wrong thing
     for a squad. It is 'law' rather than 'swat' BECAUSE THE ARMY CAME:
     two forces on the same ground with different team names is Doom's
     bestiary rule, which would have a police rifle chew a soldier on
     the way past and the soldier turn round about it — and an army tier
     that arrives already shot to pieces by the tier before it is an
     army tier that is weaker than the one it escalates from. One name,
     and nobody who came here for you fights anybody but you. See
     Actor.damage, and `shot` in Game.hitscan for the rest of it.

     THEY ARE FIREPROOF, at the user's request, and the flag is the
     whole of it (see Actor.damage, Actor.ignite and Actor.frostTic):
     the stream splashes off the armour, the floor they walk over does
     not hurt them, a car going up beside them does not hurt them, and
     they never catch — no `burn`, no `burnAway`, no ash. What gets
     through is a bullet, a van and the bore. The flamethrower is not
     the answer to them; the bore is, and it is rationed.

     THE COLD STILL WORKS. `frozen` because a block of ice with a rifle
     in it is the best joke the two weapons together tell — and it is
     the one place fire does anything to a trooper: fire on a fireproof
     block of ice is a THAW, not the execution it is for a shopper,
     because nothing inside it can be eaten. So freeze one and the
     flamethrower lets him out, and the bore or a blow finishes him. */
  SWAT: {
    name: 'SWAT', spawn: 'SWAT_STAND', see: 'SWAT_RUN1', pain: 'SWAT_PAIN',
    missile: 'SWAT_ATK1', death: 'SWAT_DIE1', xdeath: 'SWAT_XDIE1',
    health: 60, gibHealth: -30, radius: 20, height: 56, mass: 100, painchance: 50,
    speed: 9, reaction: 8, sightRange: 2400, missileRange: 1500,
    monster: true, team: 'law', fireproof: true,
    seeSound: 'swatsee', painSound: 'swatpain', deathSound: 'swatdie', attackSound: 'shot',
    freezable: true, frozen: 'SWAT_FROZE', freezeReturn: 'SWAT_RUN1',
    bored: 'SWAT_BORE',
    /* a third again the room's light on them. The sheet is navy on
       black and a car park at night made them a silhouette; most of the
       fix is a tone curve in tools/prep-swat.mjs, because light is
       multiplied in linear and twice two per cent is four per cent —
       this is the rest of it. See Actor.render */
    lit: 1.3,
    /* not `flat`: they turn, which is the whole reason the sheet has
       five views on it */
  },

  /* AND THE ARMY, who come after the SWAT — the user's order, set down
     the day their sheet arrived and built the day their carrier did.
     The same table, the same eight sides, the same fireproofing; what
     is different is every number that says how much of a fight one is.

     TWO AND A THIRD OF A TROOPER. A hundred and forty health against
     sixty, which against the rifle you have no answer to matters less
     than it sounds and against the bore matters exactly as much as it
     sounds: a trooper is one shot and a soldier is one shot, and what
     the health buys is that everything ELSE takes longer.

     THEY FLINCH LESS AND SEE FURTHER. Thirty-two of painchance against
     fifty is one hit in eight rather than one in five, so shooting one
     interrupts him half as often; twenty-eight hundred of sight against
     twenty-four, and nineteen of range against fifteen, which is most
     of the car park.

     AND THE RIFLE IS A BURST. A_ArmyFire is two rounds a frame at four
     to twenty each against the SWAT's one at three to fifteen, with the
     spread halved — see the action in js/actor.js. That is two and a
     half times the damage out of one squeeze at half the scatter, which
     in a car park at fifteen hundred units is the difference between
     being shot at and being hit.

     They are not faster by much: ten against nine. The army arriving is
     meant to read as the ground getting heavier rather than quicker,
     which is what the APC that brings them looks like too. */
  ARMY: {
    name: 'Soldier', spawn: 'ARMY_STAND', see: 'ARMY_RUN1', pain: 'ARMY_PAIN',
    missile: 'ARMY_ATK1', death: 'ARMY_DIE1', xdeath: 'ARMY_XDIE1',
    health: 140, gibHealth: -70, radius: 22, height: 58, mass: 130, painchance: 32,
    speed: 10, reaction: 6, sightRange: 2800, missileRange: 1900,
    monster: true, team: 'law', fireproof: true,
    seeSound: 'armysee', painSound: 'armypain', deathSound: 'armydie', attackSound: 'rifle',
    freezable: true, frozen: 'ARMY_FROZE', freezeReturn: 'ARMY_RUN1',
    bored: 'ARMY_BORE',
    /* less of a lift than the SWAT get, and for the reason given at
       `lift` in js/people.js: tan and olive are three and a half times
       brighter in linear than navy, so the sheet needed a quarter of
       the tone curve and the light on top of it wants the same. */
    lit: 1.15,
  },

  /* Scenery. Solid, mostly, and most of it burns. */
  TROLLEY: { name: 'Trolley', spawn: 'TRLY_STAND', radius: 16, height: 44, solid: true, pushable: true },
  BOLLARD: { name: 'Bollard', spawn: 'BOLL_STAND', radius: 10, height: 42, solid: true },
  /* THE STREET LAMP. A post you walk into, and NO SPRITE: the lamp is
     a photograph that js/mapgeo.js stands up as two masked quads in the
     plane across the street (THE STREET LAMP IS GEOMETRY there), so
     the arm reaches over the carriageway from whichever side you look
     at it instead of swinging round to face you. The actor exists for
     its radius, the way the LAMP fitting above exists for relight().
     Its light is two things, neither of them this actor: the pool on
     the pavement is a sector (see walkRun in js/maps/town.js) tinted
     cold after dark by the pavement's own shader, and the flare at the
     luminaire is js/lamplight.js. Not shootable, not flammable: steel.
     The thing's ANGLE is which way the arm reaches — the town sets it
     toward the road. */
  STREETLAMP: { name: 'Street lamp', radius: 8, height: 256, solid: true },
  /* A HEADSTONE. Granite, thirty-two tall, which is taller than a step
     and shorter than you: it stops you and you can see over it, and a
     cemetery full of them is a maze you cannot get lost in. EIGHT
     PHOTOGRAPHS, chosen per stone — see `variants` and THE HEADSTONES
     in js/sprites.js: five slabs, an obelisk and two crosses, all of
     them real granite with real lichen on it. */
  GRAVESTONE: { name: 'Headstone', spawn: 'GRAV_STAND', radius: 10, height: 32, solid: true,
                variants: 8 },
  FUELCAN: { name: 'Fuel can', spawn: 'GCAN_STAND', radius: 12, height: 38, solid: false,
             shootable: true, health: 1, flammable: true, fuel: 400, explodes: true, pickup: 'fuel' },
  CRATE:   { name: 'Stock',   spawn: 'CRAT_STAND', radius: 20, height: 58, solid: true,
             shootable: true, health: 40, flammable: true, fuel: 300 },

  /* A FITTING, WHICH DRAWS NOTHING. The picture of it is painted into
     the ceiling by T.CEILFIT — one per 256-unit tile, on this grid and
     at this offset — so what is left here is the part paint cannot do:
     a position for Game.relight to light the shop from, and a box for
     the fire and for a shot to hit. No spawn state and no death state,
     which makes it the second thing in the game with neither.

     Not solid — you walk under it — but shootable, and the fire reaches
     it too: the burn check is two-dimensional, so anything alight on
     the floor below will eventually take out the light above it, which
     is exactly right. It does not itself burn.

     WHAT A DEAD LIGHT LOOKS LIKE is the sector it was lighting going
     dark, which is baked by relight the moment it dies (see
     Game.onLampDestroyed, which also throws the sparks). The painted
     fitting goes dark with it, because a flat is lit by its sector's
     own light level like everything else — so the old objection to
     painting a light into a ceiling, that it stays lit after you have
     broken it, is answered by the renderer rather than by a sprite. */
  LAMP:    { name: 'Light', radius: 26, height: 14, health: 10,
             shootable: true, solid: false, flammable: false, hangBelow: 34 },

  FIRE:    { name: 'Fire',    spawn: 'FIRE1', radius: 12, height: 48, noclip: true, fullbright: true },
  BLAZE:   { name: 'Blaze',   spawn: 'BLAZ1', radius: 20, height: 80, noclip: true, fullbright: true },
  EMBER:   { name: 'Ember',   spawn: 'EMBR1', radius: 8,  height: 24, noclip: true, fullbright: true },
  PUFF:    { name: 'Blood',   spawn: 'PUFF1', radius: 4,  height: 8,  noclip: true },
  GORE:    { name: 'Gore',    spawn: 'BLUD_REST', radius: 4, height: 2, noclip: true, flat: true,
             variants: SPLATS },
  ASH:     { name: 'Ash',     spawn: 'ASH_REST',  radius: 4, height: 2, noclip: true, flat: true,
             variants: ASHES },
  BLAST:   { name: 'Fireball', spawn: 'BLAST1', radius: 8, height: 96, noclip: true,
             flat: true, fullbright: true },

  /* A PARKED VEHICLE, one of the two things in the game with no state
     and no sprite — the other is the light above, for the opposite
     reason: a van is drawn by something that is not the sprite bank, a
     light is drawn by the ceiling it is in. js/car.js draws it — nine boxes with an orthographic
     turnaround projected onto them — and this is here for the part of a
     van you cannot walk through. Doom's things are cylinders, so a van
     is three of these in a row; see carBlockers().

     No `spawn`, so no state, so Actor.render and Actor.tic both fall out
     on their first line. The alternative was a one-frame sprite that
     never gets drawn, which is a lie in the sprite bank and an entry in
     every table that walks it.

     Shootable and flammable, but the health here is a number nothing
     ever reaches: a blocker carries a pointer to its vehicle and hands
     everything done to it straight over, so the vehicle's own hundred
     and fifty is what decides when it goes up. Radius and height come
     from the vehicle too — see the note in Actor's constructor — because
     a hatchback and an APC are not the same cylinder. */
  CARBODY: { name: 'Vehicle', radius: 38, height: 86, solid: true,
             shootable: true, flammable: true, health: 100000 },
  /* AND THE SAME THING IN THE AIR: what a round has to cross to hit the
     gunship (js/vtol.js). Three of these ride under it at its
     altitude, each with a pointer back to the aircraft, so a shot that
     crosses any of them at the height it is at damages the aircraft
     — hitscan already asks the height. NOT solid: nobody walks round
     thin air, and the blockmap is for things on the ground. Not
     flammable either: the fire is a long way below it. */
  AIRBODY: { name: 'Aircraft', radius: 120, height: 90, solid: false,
             shootable: true, flammable: false, health: 100000 },
};

/* ---------------------------------------------------------------------
   AND THE SAME PERSON, OUT OF DOORS

   The town has people on its streets, at the user's request, and one
   of them is a shopper in every respect but the only one that matters:
   they are not IN THE SHOP.

   WHY IT IS A SECOND TYPE and not five hundred more SHOPPERs. Three
   things in this game mean "the crowd in the supermarket" when they say
   shopper, and all three would have gone wrong. Game.peopleLeft is the
   number over the HUD and is how much of the STORE is still alive — it
   would have counted the whole town and never gone down. The crowd LOD
   in Game.render draws a fraction of them by id, and the fraction would
   have been spent on people four blocks away. And the suite holds every
   shopper against the sales floor rectangle, which the town's would
   have failed by five hundred.

   Everything else they inherit, and that is the point: a townie burns,
   panics, freezes, gibs and drags a trail of fire down a sidewalk
   exactly as the crowd in the aisles does, because the whole of that
   behaviour belongs to a person near a fire and not to a person near a
   shelf. The only two numbers changed are how far a fright carries and
   how long it lasts: a street is not an aisle, you can see further down
   one, and there is somewhere to run to. */
ACTORS.TOWNIE = {
  ...ACTORS.SHOPPER, name: 'Townsfolk',
  scareRange: 420, panicTics: 11 * TICRATE,
};

export function stateOf(name) {
  const s = STATES[name];
  if (!s) console.warn('missing state:', name);
  return s || null;
}
