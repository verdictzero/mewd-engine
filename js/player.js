/* =====================================================================
   MEWD — the player
   =====================================================================

   Doom's movement numbers, exactly, because they are the reason it feels
   like Doom and because approximating them gets you something that feels
   like a Doom clone.

     friction     0.90625 a tic
     walk thrust  0.78125 units a tic   ->  8.33 u/tic terminal
     run thrust   1.5625                -> 16.66 u/tic terminal
     strafe       0.75 / 1.25

   Terminal velocity is thrust / (1 - friction), which is where those
   awkward-looking fractions come from: they are 25/32 and 50/32, the
   numbers in Doom's own table. The player accelerates to full speed in
   about a third of a second and slides for about the same again after
   letting go, and that slide is most of what people mean when they say
   the movement has weight.

   GRAVITY AND A JUMP, as of the user's request, and still no crouch.
   The player is a cylinder that walks, climbs anything 24 or under
   without slowing down, and gets over anything up to about forty with
   a jump — see GRAVITY and JUMP_VEL, and the second half of move().
   Every height in the map still means something; it is only that a
   few of them can be cleared with a run at them now.

   FOUR WEAPONS, and three of them are an argument about fire.

     MINIGUN    the user's model, slot four, and the one that is not
                about fire at all: a hundred and forty rounds a second,
                a spin-up, and barrels that glow. See BELT.

     BORE       Turok 2's cerebral bore, the user's model. A red sight,
                a lock on a head, a projectile that finds it, two seconds
                of drilling and then they explode. Five in the magazine
                and one back every twelve seconds; see js/bore.js.
     FLAMER     the verb the game is named after. A short cone, a lot of
                ignition, and an ammo count that is really a timer on how
                much of the store you can take — which is now literally
                what it is: one unit a tic while the stream pours, and
                nothing in the shop to refill it from.
     MOLOTOV    fire with reach. The answer to an aisle you cannot get
                into and a walkway fire will not cross by itself.

     LAUNCHER   the user's sixth model, slot six: four tubes, a thermal
                sight, and a seeker that locks up to four warm things
                while the trigger is held. Letting go sends one missile
                at each lock; see ROCKETS, launcherTic and js/missiles.js.
   ===================================================================== */

import { PLAYER_RADIUS, PLAYER_HEIGHT, PLAYER_EYE, MAX_STEP, TICRATE,
         angleNorm, clamp, pRandom, pRandomSpread, dist2 } from './util.js';
import { ARC } from './arc.js';

/* THE PLAYER CANNOT BE HURT BY FIRE. This flag used to say the player
   could not be hurt at all — one flag rather than a hundred missing
   checks, asked for while nothing in the game fought back — and half
   of that is still wanted: the fire is the player's own weapon, the
   car park goes up in chains the player is standing in the middle of,
   and a game whose only aim is open mayhem should not end because you
   stood too near your own work. What it no longer covers is BEING SHOT.
   The SWAT come up the road now (see js/responders.js), and a trooper
   whose rifle cannot hurt you is scenery with a sound effect. So a
   bullet lands — see damage(), and the `shot` flag hitscan carries —
   and nothing else does. */
export const FIREPROOF = true;

/* ---------------------------------------------------------------------
   WHAT THERE IS OF YOU, IN THREE LAYERS

   At the user's request: two plates of armour over the person, spent
   from the outside in, and a bar on the screen for each. The sizes are
   the user's too — the outer plate ten times what a person is worth,
   the inner one five — so a hit has to eat sixteen hundred before it
   reaches the hundred that kills you, and a trooper's rifle does three
   to fifteen of that.

   THE ORDER IS THE WHOLE FEATURE. It is not Doom's armour, which takes
   a third of every hit for as long as any of it lasts and so drains
   alongside your health rather than in front of it; these are LAYERS,
   and a layer takes everything until there is none of it left. That is
   what makes three bars worth drawing: the top one is the only one
   moving, until it isn't.
   ------------------------------------------------------------------- */
export const HEALTH  = 100;
export const ARMOUR1 = 5 * HEALTH;      // the inner plate
export const ARMOUR2 = 10 * HEALTH;     // and the outer one, which goes first
/* the order they are spent in, outermost first; health is what is left */
export const LAYERS = ['armour2', 'armour1'];

/* THE TANK EMPTIES NOW, at the user's request, and there is nothing in
   the shop to refill it with — the fuel cans are gone from the level.
   What is left is a tank that fills itself, very slowly, and that one
   decision turns the flamethrower from a hose into a budget.

   THE NUMBERS, and the ratio between them is the whole design:

     TANK          420, and the stream costs one a tic, so twelve
                   seconds of flame with the trigger held down. Enough to
                   walk a fire into three or four aisles, which is all it
                   needs to be: the fire spreads by itself, and the gun
                   is for deciding WHERE.
     REGEN_EVERY   one unit every ten tics, which is three and a half a
                   second and a full tank in two minutes. So a second of
                   firing costs ten seconds of walking, and the honest
                   way to play is short bursts a long way apart.

   It also gives the boxcutter its job back. The note below has said
   since the day it was written that a boxcutter is "what is left when
   the fuel runs out, which it will" — and the fuel did not run out, so
   the boxcutter was never issued. It is now, because an empty tank with
   one weapon in your hands is a dead end rather than a decision. */
export const TANK = 420;
export const REGEN_EVERY = 10;

/* AND THE OTHER TANK, which is the same idea with the numbers turned
   the other way. The extinguisher holds less and fills faster: 260 at
   one a tic is about seven and a half seconds of gas, and a unit every
   six tics is a full bottle in under thirty seconds.

   THE RATIO IS THE DESIGN, and it is the opposite of the flamethrower's.
   A minute of walking buys twelve seconds of setting fire to things,
   because fire is the thing the game is about and it should be rationed.
   Putting a fire out is not rationed nearly as hard, because it is
   defensive, because you are usually doing it under time pressure, and
   because an extinguisher that is empty when the aisle you wanted is
   alight is a weapon that exists to disappoint. It still latches, for
   the same reason the flamer does — a trigger you can stutter is a
   trigger with no cost — but it comes back at a third rather than a
   half, so the wait is nearer ten seconds than sixty. */
export const BOTTLE = 260;
export const CO2_REGEN_EVERY = 6;
export const CO2_REFIRE_AT = 0.34;

/* AND IT WILL NOT FIRE AGAIN UNTIL IT IS HALF FULL, at the user's
   request, which is the knob that turns a budget into a DECISION.

   A tank that refuses only when it is empty is a tank you hold the
   trigger on until it stops and then hold it again the moment one unit
   has trickled back: twelve seconds of flame becomes twelve seconds
   followed by a stutter of tenths, and the ten-seconds-of-walking-per-
   second-of-flame arithmetic above never actually bites. A tank that
   will not light again below half is a tank you have to WALK AWAY FROM
   — a full minute of it — and that minute is the one the fire you have
   already set is doing its own work in.

   Half rather than full because the point is a cooldown and not a
   punishment: coming back at 210 is six seconds of flame, enough to
   commit to the next aisle, and the player who waits longer gets more.
   It latches on empty and clears at half, so the gauge only ever has
   two things to say. */
export const REFIRE_AT = 0.5;

/* THE BORE'S MAGAZINE. Five, and one back every twelve seconds — a
   minute for a full magazine, on the same self-filling terms as the
   tanks. It is the slowest thing to refill in the game because it is
   the only thing that never misses: a lock is a kill, so what the
   magazine rations is kills, and five in a row is a queue at the tills
   emptied one skull at a time before you have to wait. No latch: the
   trigger works with one in it. */
export const BORES = 5;
export const BORE_REGEN_EVERY = 12 * TICRATE;

/* THE MINIGUN'S BELT, at the user's request, and the request was
   "absurdly destructive", so the numbers are: four rounds a tic out of
   a belt of three thousand, which is twenty-one seconds of the trigger
   held down at a hundred and forty rounds a second, each of them enough
   to drop a shopper and a burst of them enough to open a van. It fills
   itself one round a tic, so a belt is back in a minute and a half, and
   it latches at a quarter — see REFIRE_AT for why a latch at all.

   AND IT HAS TO SPIN UP. SPIN_UP tics from the trigger going down to
   the first round, SPIN_DOWN from the trigger coming up to the barrels
   stopping; the barrel set on the model turns to match (js/weapon3d.js
   reads Player.spin). A third of a second is long enough to be a
   decision and short enough not to be a wait.

   AND IT HEATS. HEAT_UP seconds of fire takes the barrels from cold to
   the yellow-white of steel that should have stopped, and HEAT_DOWN
   seconds of not firing brings them back. Nothing else happens at the
   top — the glow is the whole of it, at the user's request — but the
   gun tells you how long you have been holding the trigger, which a
   belt gauge only says in a corner. */
export const BELT = 3000;
export const BELT_PER_TIC = 4;
export const BELT_REGEN_EVERY = 1;
export const BELT_REFIRE_AT = 0.25;
export const SPIN_UP = 12;
export const SPIN_DOWN = 28;
export const HEAT_UP = 4 * TICRATE;
export const HEAT_DOWN = 7 * TICRATE;

/* ---------------------------------------------------------------------
   THE POSITRON LANCE, and it is a different KIND of trigger

   Every other weapon in this game answers the trigger going down. This
   one answers it coming UP, and what it does depends on how long you
   held it: three seconds is a stage, five is two, seven is three, and
   anything under three is a gun that vents and does nothing. That is
   the user's specification and every number below is one of those
   three or a consequence of them.

   WHY A RELEASE AND NOT A TIMER. A charge that fires itself the moment
   it is full takes the decision away: you would hold the trigger, look
   away, and the shot would happen. Firing on release means the player
   picks the stage — a quick two-second tap is deliberately nothing, and
   letting go at four seconds is a choice to take stage one now rather
   than stage two in a moment. It also means the gun can be CANCELLED,
   which a seven-second commitment has to be able to be.

   CHARGE_STAGES is in seconds because that is the unit the user asked
   in; everything downstream multiplies by TICRATE exactly once, here.

   THE BEAM THEN LASTS A SECOND AND A HALF at the top stage — see
   BEAM_SECONDS, which was three to five and is not any more — and for
   the whole of it the player is nailed to the floor. See move(): a
   discharge of this size is braced, not carried.

   AND IT DOES NOT COOK. A coil that heated as it wound, glowed on the
   chassis, and refused the trigger over a threshold was the right
   machinery for a weapon whose limit was how much you dared ask of it;
   at the user's request this is a PRECISE weapon and the limit is
   somewhere else entirely.

   THE CELL is where. It holds four and fills itself one every
   twenty-five seconds, which is the slowest magazine in the game and
   should be: a full cell is four lines drawn through the town, and at
   seven seconds of charge apiece you will think about all four.
   ------------------------------------------------------------------- */
export const CHARGE_STAGES = [3, 5, 7];                       // seconds held
export const CHARGE_MAX = CHARGE_STAGES[CHARGE_STAGES.length - 1] * TICRATE;

/* AND IT WILL NOT FIRE UNTIL THE DIAL IS RED, at the user's request,
   which is the third stage and the top of the ring.

   The three stages were a ladder of shots — let go at three seconds for
   a small one, at seven for the big one — and they are a ladder of
   READINESS now. The first two say the coil is filling and the third
   says it is full, and only the third is a shot: a trigger released
   under it vents, spends nothing and leaves the gun warm. There is one
   size of positron discharge and you wait the whole seven seconds for
   it.

   The stage machinery below is untouched, and deliberately: the beam's
   radius, its persistence and its bite are still tables indexed by
   stage, so lowering this number brings the smaller shots straight
   back. What changed is which of them the trigger will give you. */
export const FIRE_AT = CHARGE_STAGES.length;

/* HOW LONG THE COLUMN STAYS OUT, by stage, in seconds.

   It was three, four and five, and five seconds of standing column is
   not a sniper shot — it is a cutting torch you walk across a street.
   At the user's request the lance is a PRECISE weapon now, and a
   precise weapon's shot is an EVENT: you line it up for seven seconds,
   you let go, and a second and a half later it is over and whatever you
   were pointing at is not there.

   A second and a half rather than a flash because the column has to be
   SEEN, and it is fired from inside the picture along the line the
   camera is looking down — see the note on the end-on problem in
   js/beam.js. Long enough to turn your head and look along it; short
   enough that it is one shot and not an era. */
export const BEAM_SECONDS = [0.6, 0.9, 1.4];
export const BEAM_TICS = BEAM_SECONDS.map(s => Math.round(s * TICRATE));
export const CELLS = 4;
export const CELL_REGEN_EVERY = 25 * TICRATE;
/* HOW MUCH OF YOUR SPEED YOU KEEP WHILE THE COIL IS WINDING. Not zero —
   the user asked for the freeze on the FIRING and not on the charge —
   but not one either: a seven-second charge you can sprint through is a
   trigger you hold all the time, and the three stages stop meaning
   anything. A third of a walk is enough to take cover with and not
   enough to chase anybody. */
export const CHARGE_WALK = 0.35;

/* HOW LONG YOU MAY STAND AT FULL CHARGE BEFORE IT LETS GO BY ITSELF.

   A charge with no top to it is a charge you hold while you look for a
   target, and the seven seconds stop being a commitment. So there is a
   WINDOW at the top, and at the end of it the coil VENTS: the charge
   goes, the shot does not happen, the cell is not spent, and you start
   the seven seconds again.

   Five seconds of it, which is longer than the three this had before
   the overcharge replaced it. A sniper is allowed to wait for the shot
   — that is most of what a sniper does — and five seconds is enough to
   track somebody the length of a street or to let a van clear the line.
   It is not enough to hold the trigger down while you go looking, which
   is the thing the window exists to stop.

   NOTHING IS PUNISHED AT THE END OF IT ANY MORE. The coil used to
   overcharge here for forty seconds and then kill you, and at the
   user's request that is gone in its entirety: no clock, no warnings,
   no explosion. It vents, it fizzles, and you charge it again.

   The fizzle is the charge loop played once rather than round and
   round, pitch sliding down and away — see ventCharge. */
export const HOLD_TICS = 5 * TICRATE;

/* THE PITCH THE CHARGE RIDES, as playback rates for the recordings —
   see Audio.sample. Every charge clip is on this one curve, so the
   start, the loop and the stage-three whine are one accelerating sound
   rather than three sounds that happen in a row. 0.72 is a coil that
   has just been asked; 1.45 is one that is finished asking. */
export const CHARGE_PITCH = [0.72, 1.45];
/* THE SWEEP CLAMP IS GONE, and it is worth saying why rather than just
   deleting it.

   It existed because the column CHASED the barrel: a beam that follows
   where you look is a beam you can lean across a street, and without a
   clamp you could spin on the spot and take out all four sides of a
   junction with one shot. That was the armageddon weapon.

   This one does not chase. The line is fixed at the instant the trigger
   comes up and it stays there for its second and a half — see _aim in
   js/beam.js — so turning your head cannot move the damage, and
   clamping the turn would only stop you LOOKING at the shot you just
   took. Which, for a weapon whose whole appeal is the line it leaves
   through four buildings, is exactly backwards. */

/* THE QUAD LAUNCHER'S FOUR TUBES. Four missiles and no more — the box
   holds four — and each empty tube is loaded again on its own clock,
   one every ROCKET_REGEN_EVERY tics, so a full salvo is back in about
   eight seconds and a single shot in two. No latch, for the bore's
   reason: a tube is a count of shots, and one loaded tube is a shot.

   IT IS FAST TO RELOAD BECAUSE IT IS SLOW TO USE. Every missile that is
   worth firing is a lock, and a lock is a dwell with the trigger held
   and the target in the middle of the sight — a third of a second each,
   a second and a half for all four — so what rations this weapon is the
   time you spend standing still with it up, not the tubes. */
export const ROCKETS = 4;
export const ROCKET_REGEN_EVERY = 2 * TICRATE;

/* THE ARC MAW'S CAPACITOR. Six discharges, whatever each was charged
   to, and one back every three seconds: what a full charge costs is the
   three seconds of standing there with the ball growing, not the cell,
   so a tap and a nine-man chain are both one. See arcTic and js/arc.js. */
export const VOLTS = 6;
export const VOLT_REGEN_EVERY = 3 * TICRATE;

/* THE PLAYER CAN JUMP NOW, at the user's request, which is the end of
   the NO GRAVITY, NO JUMPING line below and is done the way a Doom port
   does it: a vertical momentum, a gravity that takes a unit a tic off
   it, and a floor that stops it. JUMP_VEL is the push off the ground —
   nine, which with a unit of gravity is forty units of height, enough
   to clear a shelf end or a bonnet and not a gondola. A drop deeper
   than a step is a FALL rather than a snap, on the same gravity, which
   is what makes a jump off the loading dock feel like one. */
export const GRAVITY = 1.0;
export const JUMP_VEL = 9.0;

const FRICTION   = 0.90625;
const WALK_FWD   = 25 / 32,  RUN_FWD  = 50 / 32;
const WALK_SIDE  = 24 / 32,  RUN_SIDE = 40 / 32;
const STOP_SPEED = 0.06;
export const MAX_PITCH  = 0.72;          // about 41 degrees, the usual port limit

/* THE FLAMETHROWER IS THE GAME AND IT IS NOT SUBTLE.

   A four-metre cone at forty-five degrees, enough damage to delete a
   member of staff in a fraction of a second, and it lays down enough
   accelerant that what it touches goes on burning by itself long after
   you have walked away. There is no aiming. There IS ammo management
   now: the tank holds twelve seconds and fills itself in two minutes,
   and there is nothing in the shop to top it up with.

   THE BOXCUTTER IS GONE — deleted rather than switched off, at the
   user's request. It was the melee stand-in, three frames of a forearm
   and a blade, and the note that stood here for a year said a boxcutter
   is the wrong verb for this game. What replaced it is not a melee
   weapon at all: the cerebral bore, below, which is aimed, and is the
   first thing in the player's hands that kills one person at a time on
   purpose. Game.impact, the hook a physical weapon calls, stays for the
   physical weapon that is still coming. The molotov is written, tested
   and still switched off. */
export const WEAPONS = {
  FLAMER: {
    slot: 1, name: 'FLAMER', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [2, 2],
    /* CHARGED PER TIC OF STREAM, NOT PER SHOT CYCLE, which is why this
       is 0 and flameTic does the subtracting. A cycle is four tics, so
       per-shot billing made the tank a count of four-tic bursts — and
       what the player experiences is SECONDS OF FLAME, because the
       stream pours every tic the trigger is down whatever the animation
       is doing. Bill the thing that comes out of the nozzle. */
    ammo: 'fuel', ammoPerShot: 0, autofire: true,
    /* and once it is empty it stays out until the tank is back to half
       — see REFIRE_AT. A weapon without this simply needs one unit. */
    refire: REFIRE_AT,
    /* A STREAM, not a cone: every tic the trigger is down, js/flame.js
       sends a few particles out of the nozzle and they fly, drop, and
       light whatever they land on. The reach is theirs to decide. */
    stream: true,
    damage: () => (pRandom() % 9) + 8,
    sound: 'flame',
  },

  /* THE EXTINGUISHER, which does what a fire extinguisher does and then
     two things it does not.

     WHAT IT OBVIOUSLY DOES: the stream takes heat out of the fuel grid
     and puts out what it lands on, store and forest both. It cannot undo
     a burn — fuel that has gone has gone — so what it saves is the aisle
     the fire has not reached yet, which makes it a tool for drawing
     firebreaks rather than an undo button. See FireSystem.douse.

     WHAT IT ALSO DOES: it freezes people. Enough gas on one and they go
     solid — a blue statue that stops running, stops burning if they were
     burning, and blocks the aisle for everybody behind them. They thaw
     if you leave them; fire thaws them much faster; and anything that
     hits them while they are solid shatters them, whole.

     IT IS THE SAME KIND OF THING AS THE FLAMER — a stream, billed per
     tic of pour, with a latch at empty — because the two are meant to be
     held the same way and used against each other. */
  EXTINGUISHER: {
    slot: 2, name: 'EXTINGUISHER', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [2, 2],
    ammo: 'co2', ammoPerShot: 0, autofire: true,
    refire: CO2_REFIRE_AT,
    stream: 'frost',
    damage: () => 0,
    sound: 'flame',
  },

  /* THE CEREBRAL BORE. `lock` is the whole of what makes it different
     to hold: the trigger does nothing without a head in the sight (see
     Player.armed, and BoreSystem.lock), and with one the shot is a
     projectile the bore system owns from the launcher onward. Billed a
     bore a shot, out of a magazine that refills itself one at a time —
     see BORES and BORE_REGEN_EVERY. The fire frames are the launcher's
     recoil and nothing else; the model is drawn by js/weapon3d.js, and
     the sprite named here is only the fallback for a model that never
     arrived. */
  BORE: {
    slot: 3, name: 'CEREBRAL BORE', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [5, 14],
    ammo: 'bores', ammoPerShot: 1, lock: true,
    damage: () => 0,
    sound: 'borefire',
  },
  /* THE MINIGUN. `volley` is the whole of what makes it a different
     kind of thing to hold: every tic the trigger is down and the barrels
     are up to speed, `rounds` hitscans leave the nozzle inside `spread`
     radians of where the eye is looking, pitch and all — see volleyTic
     and Game.hitscan. Billed per tic out of the belt like the streams
     are out of their tanks, and latched at empty the same way. The fire
     frames are a two-tic shudder and nothing else; the model, the spin
     and the heat are js/weapon3d.js's. */
  MINIGUN: {
    slot: 4, name: 'MINIGUN', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [1, 1],
    ammo: 'rounds', ammoPerShot: 0, autofire: true,
    refire: BELT_REFIRE_AT,
    volley: true, rounds: BELT_PER_TIC, spread: 0.055,
    damage: () => 24 + (pRandom() % 25),
    /* no sound per cycle: the firing is one held sound, the user's
       recording, started and stopped in weaponTic — see gunLoop */
    sound: null,
  },
  /* THE POSITRON SNIPER LANCE. `charge` is the whole of what makes it a
     different kind of trigger to hold — see CHARGE_STAGES above and
     lanceTic below, which is the only firing path in this file that
     does not run on fireIndex, because a charge is not an animation.
     Billed one cell a shot whatever the stage: what the stages buy is
     how wide the line is and how long it stays, not how many you get.
     The beam itself, and everything it deletes, is js/beam.js's; the
     screen on the back of the gun is js/scope.js's. */
  LANCE: {
    slot: 5, name: 'POSITRON LANCE', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [4, 4],
    ammo: 'cells', ammoPerShot: 1,
    charge: true,
    /* THE TRIGGER IS NOT AUTOMATIC and must not be: holding it is the
       charge, so a weapon that re-fired on a held trigger would fire on
       the way to its own next shot. */
    damage: () => 0,
    /* SIX RECORDINGS, the user's own, and between them they are the
       whole voice of the weapon — see SAMPLES in js/audio.js and
       lanceVoice below, which is the only thing that plays them.
       `sound` is not one of them: the discharge is two layers played
       together and so cannot be a single name, so it is null here and
       fireBeam says what it means. */
    sound: null,
  },
  /* THE QUAD LAUNCHER. `seeker` is the whole of what makes it a
     different kind of trigger to hold: DOWN is the seeker looking for
     heat and locking what it finds, UP is the salvo — one missile per
     lock, or one straight down the sight with none — and neither is an
     animation, so it runs its own tic like the lance does (see
     launcherTic). Billed one tube a missile. The seeker, the flight and
     the warhead are js/missiles.js's; the sight on the side of the box
     is js/thermal.js's. */
  LAUNCHER: {
    slot: 6, name: 'QUAD LAUNCHER', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [3, 3],
    ammo: 'rockets', ammoPerShot: 1,
    seeker: true,
    damage: () => 0,
    sound: null,
  },
  /* THE ARC MAW, the user's seventh model. `arc` is the whole of what
     makes it a different trigger to hold: DOWN charges it — blue energy
     gathering into a ball between the three prongs, js/weapon3d.js's
     `orb` — and UP lets it go as a bolt that chains from body to body,
     one strike for a tap and nine at the top of the charge. Neither is
     an animation, so it runs its own tic like the lance and the
     launcher do (see arcTic). Billed one discharge a shot out of the
     capacitor — see VOLTS. The lightning is js/arc.js's. */
  ARC: {
    slot: 7, name: 'ARC MAW', sprite: 'FLMG',
    ready: 'A', fire: ['B', 'C'], fireTics: [3, 5],
    ammo: 'volts', ammoPerShot: 1,
    arc: true,
    damage: () => 0,
    sound: null,
  },
  MOLOTOV: {
    slot: 8, name: 'MOLOTOV', sprite: 'MOLG',
    ready: 'A', fire: ['B', 'B', 'C', 'C'], fireTics: [6, 6, 8, 12],
    throwAt: 2,
    ammo: 'bottles', ammoPerShot: 1,
    sound: 'throw',
  },
};

export class Player {
  constructor(game, x, y, angle) {
    this.game = game;
    /* WHO THIS IS, when there is more than one of you — see
       js/net/match.js. A game on its own leaves all of these alone. */
    this.isPlayer = true;
    this.id = 0;
    this.name = 'PLAYER';
    this.team = -1;
    this.frags = 0;
    this.deaths = 0;
    this.session = null;           // null: the game's own (Game.session)
    this.x = x; this.y = y; this.angle = angle; this.pitch = 0;
    this.momx = 0; this.momy = 0;
    /* and up, which is new: see GRAVITY */
    this.momz = 0;
    this.onGround = true;
    /* tics of grace after a vehicle has thrown you, during which the
       same vehicle cannot throw you again — see damage() and
       SwatVan.runOver */
    this.launched = 0;
    this.radius = PLAYER_RADIUS;
    this.height = PLAYER_HEIGHT;
    this._near = [];                   // scratch for thingInWay's blockmap query
    this.sector = game.level.sectorAt(x, y);
    this.z = this.sector ? this.sector.floor : 0;

    /* THREE BARS, OUTSIDE IN, at the user's request. A hit spends the
       outer plate first, then the inner one, then you — see damage(),
       which is the only place any of the three moves. */
    this.health = HEALTH;
    this.armour2 = ARMOUR2;
    this.armour1 = ARMOUR1;
    this.dead = false;
    this.shootable = true;
    this.monster = false;

    this.ammo = { fuel: TANK, co2: BOTTLE, bores: BORES, rounds: BELT, cells: CELLS, rockets: ROCKETS, volts: VOLTS, bottles: 0 };
    this.maxAmmo = { fuel: TANK, co2: BOTTLE, bores: BORES, rounds: BELT, cells: CELLS, rockets: ROCKETS, volts: VOLTS, bottles: 12 };
    /* THE LATCH. True from the moment the tank runs out until it is back
       to REFIRE_AT of full, and the only thing that stops the flamer
       firing while there is fuel in it. */
    this.dry = false;
    this.regenTick = 0;
    /* the extinguisher's own latch and its own clock, because the two
       tanks refuse and refill on different terms */
    this.co2Dry = false;
    this.co2Tick = 0;
    /* the bore's magazine has a clock and no latch — see BORES */
    this.boreTick = 0;
    this.boreDry = false;
    /* the minigun's belt: its own latch and clock, and the two numbers
       js/weapon3d.js draws — how fast the barrels are turning, 0..1 of
       full speed, and how hot they are, 0..1 of glowing white */
    this.beltTick = 0;
    this.beltDry = false;
    this.spin = 0;
    this.heat = 0;
    /* THE LANCE'S THREE NUMBERS, and they are the only weapon state in
       this file that more than one other module reads: the gun's screen
       draws the first two (js/scope.js) and the beam system lives off
       the third (js/beam.js). All three are STATES and not animations,
       so a pause holds them where they are.

         charge     tics of trigger held, 0..CHARGE_MAX
         hold       tics spent sitting at the top of it, 0..HOLD_TICS,
                    after which the coil vents
         beamTics   tics of beam still out, and beamStage which one

       THERE WAS A FOURTH, and it was heat: the coil cooked as it wound
       up, the chassis glowed with it (js/weapon3d.js), and over a
       threshold the gun refused the trigger until it had cooled. At the
       user's request there is no heat on this weapon at all now. What
       stops you firing it constantly is the thing that always should
       have: it holds four cells and they come back one at a time. */
    this.charge = 0;
    this.hold = 0;
    this.beamTics = 0;
    this.beamStage = 0;
    this.cellTick = 0;
    this.cellDry = false;
    /* the held charge sound and which of the two it is — see lanceVoice */
    this.chargeLoop = null;
    this._chargeVoice = null;
    /* whether the coil has already let go on this press of the trigger
       — see ventCharge */
    this.vented = false;
    /* THE LAUNCHER'S: whether the trigger is down on it — which is the
       seeker looking, see js/missiles.js — the clock that loads its
       empty tubes, and which tube the last missile left, for the flash
       at the front of the box (js/weapon3d.js) */
    this.seeking = false;
    this.rocketTick = 0;
    this.rocketDry = false;
    this.launchTube = -1;
    /* THE ARC MAW'S: how charged it is, 0..1 — the ball in its maw is
       drawn off this (js/weapon3d.js) and the chain is sized off it
       (js/arc.js) — whether the trigger is down on it, and the clock
       that refills its capacitor */
    this.arcCharge = 0;
    this.arcCharging = false;
    this.voltTick = 0;
    this.voltDry = false;
    /* the held firing sound, while rounds are leaving — see weaponTic */
    this.gunLoop = null;
    /* whether the trigger has already clicked on this press of it */
    this._clicked = false;
    /* DEBUG MODE: every tank refills to the top once a tic. Off, saved
       with the rest of the settings, and turned on from the pause menu
       — see fuelTic, which is the whole of it. */
    this.debug = false;
    /* AND THE OTHER DEBUG SWITCH, which is one branch in damage() below.
       It is not a heal: it stops you being hurt from the moment it goes
       on, so turned on at forty health you stay at forty for ever. */
    this.invincible = false;
    /* SIX WEAPONS. The molotov is built and tested and stays switched
       off; the boxcutter is gone; the bore is the third, the minigun
       the fourth, the lance the fifth and the launcher the sixth — see
       the note above WEAPONS. */
    this.owned = { FLAMER: true, EXTINGUISHER: true, BORE: true, MINIGUN: true, LANCE: true, LAUNCHER: true, ARC: true };
    this.weapon = 'FLAMER';
    this.pendingWeapon = null;

    this.fireIndex = -1;      // -1 = at rest
    this.fireTics = 0;
    this.refire = false;
    /* EVERY TIME THE TRIGGER HAS ACTUALLY DONE SOMETHING. Counted here
       and read by js/responders.js, where the first one is what calls
       the police — a refusal is not a shot, so this only ever goes up
       in startFire, which is the one door every weapon goes through. */
    this.shotsFired = 0;

    this.bob = 0; this.bobPhase = 0;
    this.lookRate = 0; this.pitchRate = 0;     // how fast the view is turning, smoothed, for the gun to lag
    this.viewZ = this.z + PLAYER_EYE;
    this.damageFlash = 0;
    this.pickupFlash = 0;
    this.kills = 0;
    this.useCooldown = 0;
  }

  get eyeZ() { return this.viewZ; }

  /* ------------------------------------------------------------------
     One tic
     ------------------------------------------------------------------ */
  tic(input, dt) {
    if (this.useCooldown > 0) this.useCooldown--;
    if (this.damageFlash > 0) this.damageFlash--;
    if (this.pickupFlash > 0) this.pickupFlash--;
    if (this.launched > 0) this.launched--;

    if (this.dead) { this.deathTic(); return; }

    this.turn(input);
    this.move(input);
    this.weaponTic(input);
    this.fuelTic();

    if (input.use && this.useCooldown === 0) { this.use(); this.useCooldown = 8; }
  }

  turn(input) {
    /* AND YOU MAY LOOK AT WHAT YOU JUST DID. The feet are nailed down
       while the beam is out (see move) and the head is not — it used to
       be clamped to a fifth of the rate, because the column chased the
       barrel and a free head meant a shot that swept the whole junction.
       The column does not chase any more, so the clamp had nothing left
       to protect and was costing the one thing the shot is for: turning
       to look along the line it left. */
    this.angle -= input.look.x;
    this.angle = angleNorm(this.angle);
    this.pitch = clamp(this.pitch - input.look.y, -MAX_PITCH, MAX_PITCH);
    this.lookRate += (input.look.x - this.lookRate) * 0.3;
    this.pitchRate += (input.look.y - this.pitchRate) * 0.3;
  }

  move(input) {
    /* THE LANCE DECIDES WHETHER YOU ARE WALKING AT ALL, which is the
       one place in this file where a weapon reaches into the legs.

       While the beam is out, nothing: no push, and the momentum is
       already gone (fireBeam spends it), so five seconds of discharge is
       five seconds standing exactly where you fired from. That is the
       user's ask and it is also the whole shape of the weapon — a line
       drawn through a town is a thing you commit to a position for.

       While the coil is winding, a third of a walk. See CHARGE_WALK. */
    const braced = this.beamTics > 0;
    const grip = braced ? 0 : this.charge > 0 ? CHARGE_WALK : 1;
    const run = input.run && !braced && this.charge === 0;
    const fwd = (run ? RUN_FWD : WALK_FWD) * input.move.y * grip;
    const side = (run ? RUN_SIDE : WALK_SIDE) * input.move.x * grip;

    const c = Math.cos(this.angle), s = Math.sin(this.angle);
    this.momx += c * fwd + s * side;
    this.momy += s * fwd - c * side;

    /* Friction, then the dead zone that stops a player drifting for ever
       at a hundredth of a unit a tic. */
    this.momx *= FRICTION; this.momy *= FRICTION;
    if (Math.abs(this.momx) < STOP_SPEED) this.momx = 0;
    if (Math.abs(this.momy) < STOP_SPEED) this.momy = 0;

    const lv = this.game.level;
    let [nx, ny] = lv.slideMove(this.x, this.y, this.momx, this.momy,
                                this.radius, this.z, this.height, false);
    /* Trees stop you too, and you slide round them the way you slide
       along a wall: the whole move, then each axis alone. */
    const forest = this.game.forest;
    if (forest && forest.blocks(nx, ny, this.radius)) {
      if (!forest.blocks(nx, this.y, this.radius)) ny = this.y;
      else if (!forest.blocks(this.x, ny, this.radius)) nx = this.x;
      else { nx = this.x; ny = this.y; }
    }
    /* Bumping into a monster stops you the same way a wall does — and
       being able to shove past them would make every corridor free. */
    let blocked = this.thingInWay(nx, ny);
    /* A VEHICLE YOU SLIDE ALONG, the way you slide along a wall and
       round a tree: the whole move, then each axis alone. A van is
       three cylinders in a row and the outside of one is most of a
       fire lane's worth of corner; stopping dead against it was the one
       place the movement still felt like walking into a post, and it
       was also how you stayed in one — see thingInWay. */
    if (blocked && blocked.vehicle) {
      if (!this.thingInWay(nx, this.y)) { ny = this.y; blocked = null; }
      else if (!this.thingInWay(this.x, ny)) { nx = this.x; blocked = null; }
    }
    if (!blocked) { this.x = nx; this.y = ny; }
    else { this.momx *= 0.2; this.momy *= 0.2; }
    forest?.clampInside(this);

    const sec = lv.sectorAt(this.x, this.y, this.sector);
    /* WHICH STOREY YOU ARE ON. The ground sector says which column you
       are standing over; your own z says which of its storeys you are
       standing in, and for everything in the store that is a column of
       one the second question costs a comparison. */
    if (sec) this.sector = sec.above === null ? sec : lv.spanIn(sec, this.z);
    /* AT THE POINT YOU ARE STANDING, where the region is sloped. A
       loft's ceiling is 336 at the eaves and 464 on the ridge, and the
       flat number is the ridge — so without this you can walk to the
       edge of a roof with your head through it. */
    const floor = this.sector ? lv.floorAt(this.sector, this.x, this.y) : this.z;
    const ceil = this.sector ? lv.ceilAt(this.sector, this.x, this.y) : Infinity;

    /* UP AND DOWN, which used to be one line: z is the floor. It is
       still the floor for as long as you are standing on it — a step up
       or down within MAX_STEP is instant, like Doom, with the smoothing
       in the view height below and not in the body. What is new is
       everything else: a jump is a push off it, a drop deeper than a
       step is a fall, and both run on the same gravity until the floor
       is under you again. See GRAVITY and JUMP_VEL. */
    if (this.onGround && input.jump && !braced) {
      this.momz = JUMP_VEL;
      this.onGround = false;
    }
    if (this.onGround && floor < this.z - MAX_STEP) this.onGround = false;   // walked off something
    if (this.onGround) {
      this.z = floor;
      this.momz = 0;
    } else {
      this.momz -= GRAVITY;
      this.z += this.momz;
      /* the ceiling stops a jump the way the floor stops a fall */
      if (this.z + this.height > ceil) { this.z = Math.max(floor, ceil - this.height); if (this.momz > 0) this.momz = 0; }
      if (this.z <= floor) {
        /* LANDED, and the harder the landing the more the knees give:
           the eye dips by a share of the speed it arrived at and the
           smoothing below brings it back up over a few tics */
        const fall = -this.momz;
        this.z = floor;
        this.momz = 0;
        this.onGround = true;
        if (fall > 4) this.viewZ -= Math.min(12, fall * 0.7);
      }
    }

    /* View bob. Doom's: proportional to the square of the speed, capped,
       and driven by a phase that only advances while you are moving. */
    const speed2 = this.momx * this.momx + this.momy * this.momy;
    const targetBob = Math.min(16, speed2 * 0.32);
    this.bob += (targetBob - this.bob) * 0.25;
    if (this.onGround) this.bobPhase += 0.19;
    const eye = this.z + PLAYER_EYE + Math.sin(this.bobPhase) * this.bob * 0.5;
    /* the eye lags the feet, so a kerb is a lurch and not a teleport */
    this.viewZ += (eye - this.viewZ) * 0.45;
  }

  thingInWay(nx, ny) {
    /* Nine cells of blockmap. This is asked up to three times per tic —
       once for the whole step and once per axis when it fails — and a
       crowd of eight hundred behind every one of them is a scan the
       player can feel. */
    const bm = this.game.blockmap;
    const list = bm ? bm.near(nx, ny, this._near) : this.game.actors;
    for (let i = 0; i < list.length; i++) {
      const a = list[i];
      if (a.removed || !a.solid || a.dead || a.noclip) continue;
      const rr = this.radius + a.radius;
      const d2 = dist2(nx, ny, a.x, a.y);
      if (d2 < rr * rr) {
        if (a.info.pushable) {           // trolleys move, they do not stop you
          const d = Math.hypot(a.x - nx, a.y - ny) || 1;
          a.x += ((a.x - nx) / d) * 6; a.y += ((a.y - ny) / d) * 6;
          this.game.blockmap?.moved(a);
          a.updateSector();
          continue;
        }
        /* ALREADY INSIDE IT. A squad van that pulled up on top of you,
           an APC whose skirts came down over you, a launch that put you
           down in the middle of one — and from inside a cylinder every
           step is still inside it, so every step was refused and you
           stood in the van until it drove off or you did. Doom has the
           same bug, and the same fix: a thing you are already inside
           never refuses a step that takes you NO NEARER its middle. You
           can always walk out of one, and you can never walk further
           in, which is the whole of what solidity is for. */
        const was = dist2(this.x, this.y, a.x, a.y);
        if (was < rr * rr && d2 >= was) continue;
        return a;
      }
    }
    /* AND EACH OTHER, when there are others: a player is as solid as a
       trooper, on the same terms — you can always step out of one */
    const ps = this.game.players;
    if (ps.length > 1) for (let i = 0; i < ps.length; i++) {
      const a = ps[i];
      if (a === this || a.dead) continue;
      const rr = this.radius + a.radius;
      const d2 = dist2(nx, ny, a.x, a.y);
      if (d2 >= rr * rr) continue;
      if (Math.abs(a.z - this.z) >= this.height) continue;
      const was = dist2(this.x, this.y, a.x, a.y);
      if (was < rr * rr && d2 >= was) continue;
      return a;
    }
    return null;
  }

  /* ------------------------------------------------------------------
     Weapons
     ------------------------------------------------------------------ */
  get def() { return WEAPONS[this.weapon]; }
  get firing() { return this.fireIndex >= 0; }

  ammoFor(w) { const d = WEAPONS[w]; return d.ammo ? this.ammo[d.ammo] : Infinity; }
  /* One unit is enough to start: what stops a stream is running dry
     mid-pour, which flameTic notices. */
  hasAmmo(w) { const d = WEAPONS[w]; return !d.ammo || this.ammo[d.ammo] >= Math.max(1, d.ammoPerShot ?? 1); }

  /** Whether it will actually go off. Two different refusals and the
   *  player is told which: nothing in the tank, or something in the tank
   *  and not yet enough of it — see REFIRE_AT. */
  armed(w) {
    if (!this.hasAmmo(w) || (WEAPONS[w].refire && this.latched(w))) return false;
    /* AND A WEAPON THAT NEEDS A LOCK NEEDS A LOCK. This is Turok's rule
       and the whole feel of the bore: it is not a gun you point, it is
       a gun you wait with. */
    if (WEAPONS[w].lock && !this.game.bore?.lock) return false;
    /* AND A GUN THAT HAS TO SPIN UP IS NOT ARMED UNTIL IT HAS: the
       trigger is down, the barrels are winding, and nothing comes out
       for a third of a second — see SPIN_UP and spinTic */
    if (WEAPONS[w].volley && this.spin < 1) return false;
    /* AND A LANCE WILL NOT TAKE THE TRIGGER WHILE ITS OWN BEAM IS OUT.
       This used to refuse a HOT coil as well, on the same two-number
       latch the tanks use; the heat is gone at the user's request and
       so is the refusal. All that is left is the one case that would
       otherwise let you hold the trigger through your own discharge and
       start the next seven seconds inside the last shot. */
    if (WEAPONS[w].charge && this.beamTics > 0) return false;
    return true;
  }

  /** THE BARRELS, WINDING UP AND DOWN, AND HOW HOT THEY ARE. Both are
   *  states rather than animations, so js/weapon3d.js draws them and
   *  a pause holds them. The spin climbs while the trigger is down on
   *  a volley weapon that is not latched — a dry belt does not spin,
   *  because a spin that leads to nothing is a promise the gun cannot
   *  keep — and runs down otherwise, faster up than down, the way a
   *  motor and a heavy set of barrels behave. The heat climbs while
   *  rounds are actually leaving and cools the rest of the time. */
  spinTic(input) {
    const d = this.def;
    const want = !!(d.volley && input.attack && !this.latched(this.weapon) && this.hasAmmo(this.weapon));
    const was = this.spin;
    this.spin = clamp(this.spin + (want ? 1 / SPIN_UP : -1 / SPIN_DOWN), 0, 1);
    if (want && was === 0) this.game.sound?.play('spinup', this);
    if (!want && was === 1) this.game.sound?.play('spindown', this);
    const firingRounds = this.firing && d.volley;
    this.heat = clamp(this.heat + (firingRounds ? 1 / HEAT_UP : -1 / HEAT_DOWN), 0, 1);
  }

  /** The minigun: one tic of rounds out of the nozzle. Where the eye is
   *  looking, pitch included, with a little scatter round it, and each
   *  one a hitscan the world resolves — see Game.hitscan. */
  volleyTic(d) {
    const g = this.game;
    if (d.ammo) {
      if (this.ammo[d.ammo] < d.rounds) {
        /* DRY MID-BURST stops it where it stands and latches, the same
           bargain the streams make — see flameTic */
        this.fireIndex = -1;
        this.beltDry = true;
        return;
      }
      this.ammo[d.ammo] -= d.rounds;
    }
    const from = g.nozzle(this);
    const dx = Math.cos(this.angle), dy = Math.sin(this.angle);
    for (let i = 0; i < d.rounds; i++) {
      const a = this.angle + (pRandom() / 255 - 0.5) * 2 * d.spread;
      const pt = this.pitch + (pRandom() / 255 - 0.5) * 2 * d.spread * 0.7;
      g.hitscan(this, a, 2400, d.damage(), { shot: true, hot: true, pitch: pt, dx, dy, force: 1.6, from });
      /* EVERY OTHER ROUND IS A TRACER, at the user's request: a streak
         of light from the muzzle to wherever the round stopped, which
         Game.hitscan leaves in lastHit — see js/tracers.js */
      if ((i & 1) === 0 && g.tracers && g.lastHit) g.tracers.spawn(from, g.lastHit);
    }
  }

  /* WHICH TANK IS SULKING. Two streams, two tanks, two latches, and a
     weapon that has neither is never refused. */
  latched(w) {
    const d = WEAPONS[w];
    return d.ammo === 'co2' ? this.co2Dry : d.ammo === 'fuel' ? this.dry
         : d.ammo === 'rounds' ? this.beltDry : d.ammo === 'cells' ? this.cellDry : false;
  }

  selectSlot(n) {
    for (const [k, d] of Object.entries(WEAPONS))
      if (d.slot === n && this.owned[k]) { if (k !== this.weapon) this.pendingWeapon = k; return; }
  }

  cycleWeapon(dir) {
    const list = Object.keys(WEAPONS).filter(k => this.owned[k]);
    const i = list.indexOf(this.weapon);
    this.pendingWeapon = list[((i + dir) % list.length + list.length) % list.length];
  }

  weaponTic(input) {
    if (input.weaponSlot) this.selectSlot(input.weaponSlot);
    if (input.weaponCycle) this.cycleWeapon(input.weaponCycle > 0 ? 1 : -1);
    this.spinTic(input);
    this._weaponTic(input);
    /* THE FIRING IS ONE HELD SOUND on a volley weapon: the user's
       recording, looped from the first round to the last and stopped
       with a short ramp. Judged after the tic, on whether rounds are
       leaving, so a dry belt and a released trigger end it the same
       way. */
    const on = this.firing && !!this.def.volley;
    if (on && !this.gunLoop) this.gunLoop = this.game.sound?.loop('minigunloop', this) || null;
    else if (!on && this.gunLoop) { this.gunLoop.stop(); this.gunLoop = null; }
    this.lanceVoice();
  }

  /** THE LANCE'S HELD SOUND, and which of the two it is.

   *  A charging coil is a sound that runs for as long as the trigger is
   *  down, so it is a loop and not a shot — the same bargain the
   *  minigun's firing makes above. What is different is that there are
   *  TWO of them and the gun changes its mind halfway: the loop while
   *  it is filling, and the stage-three whine from the moment the third
   *  mark is passed, which is the sound of a weapon that has stopped
   *  asking. Held rather than fired once, so standing at full charge
   *  deciding whether to let go is a sound and not a silence.
   *
   *  Judged from the state AFTER the tic rather than switched at the
   *  moment something happens, so every way of ending a charge — the
   *  trigger coming up, the shot going off, the weapon being swapped,
   *  dying with it in your hands — stops the loop through this one
   *  line, and none of them has to remember to. */
  lanceVoice() {
    const winding = !!this.def.charge && this.charge > 0 && this.beamTics === 0 && !this.dead;
    const want = !winding ? null : this.chargeStage >= CHARGE_STAGES.length ? 'lancecharge3' : 'lancecharge';
    if (want !== this._chargeVoice) {
      /* THE STAGE-THREE WHINE IS RELEASED AND NOT STOPPED, which is the
         difference between a sound ending and a sound being cut. It is
         eleven seconds long and is only ever heard for the three the
         hold allows, so whatever happens next — the shot, the vent —
         wants its tail under it rather than silence. The two-second
         loop is stopped, because a loop has no tail to keep. */
      if (this._chargeVoice === 'lancecharge3') this.chargeLoop?.release(0.8);
      else this.chargeLoop?.stop();
      this.chargeLoop = want ? (this.game.sound?.loop(want, this, this.chargePitch) || null) : null;
      this._chargeVoice = want;
    }
    /* and the pitch rides the charge, every tic. setTargetAtTime under
       this, so thirty-five calls a second are a chase and not a stair. */
    if (this.chargeLoop && winding) this.chargeLoop.rate(this.chargePitch, 0.08);
  }

  _weaponTic(input) {
    /* A CHARGED WEAPON DOES NOT RUN ON fireIndex. Every other weapon in
       this file is a little state machine walking a list of sprite
       frames, and the question it asks each tic is "which frame". The
       lance's question is "how long has the trigger been down", which
       has nothing to do with frames, so it gets its own tic and the one
       below never sees it. */
    if (this.def.charge) { this.lanceTic(input); return; }
    /* and neither does a seeker, for the same reason: its question is
       "is the trigger down", and the answer is a search, not a frame */
    if (this.def.seeker) { this.launcherTic(input); return; }
    /* and nor does the arc maw: its question is how long, like the lance's */
    if (this.def.arc) { this.arcTic(input); return; }
    if (this.firing) {
      const d = this.def;
      /* a stream pours every tic the trigger is down, not once a frame */
      if (d.stream) this.flameTic(d);
      /* and a volley fires every tic the barrels are up to speed */
      if (d.volley) this.volleyTic(d);
      if (--this.fireTics > 0) return;
      /* the frame we are ABOUT to leave is the one that does the damage */
      this.fireIndex++;
      if (this.fireIndex === d.throwAt) this.throwBottle();
      if (this.fireIndex >= d.fire.length) {
        this.fireIndex = -1;
        /* holding the button on an automatic goes straight round again */
        if (d.autofire && input.attack && this.armed(this.weapon)) this.startFire();
        return;
      }
      this.fireTics = d.fire ? d.fireTics[Math.min(this.fireIndex, d.fireTics.length - 1)] : 4;
      return;
    }

    /* only swap weapons between shots, never during one */
    if (this.pendingWeapon) {
      this.weapon = this.pendingWeapon;
      this.pendingWeapon = null;
      return;
    }
    /* A REFUSAL IS SILENT NOW, because the corner that used to say why
       is two bars. It does not need words: the bar is red and the pip on
       it is where the trigger starts working again, which is the same
       sentence in the place the player is already looking. */
    if (input.attack && this.armed(this.weapon)) this.startFire();
    /* EXCEPT THE ONE REFUSAL THAT IS HEARD: a bore with nothing locked
       clicks, once per press, because a trigger that does nothing at
       all is a trigger you press harder. The tanks stay silent — their
       bars say why. */
    else if (input.attack && this.def.lock && !this._clicked) {
      this._clicked = true;
      this.game.sound?.play('noammo', this);
    }
    if (!input.attack) this._clicked = false;
  }

  startFire() {
    const d = this.def;
    /* `?? 1` and not `|| 1`: the flamethrower declares 0 on purpose,
       because it is billed per tic of stream rather than per shot. */
    if (d.ammo) this.ammo[d.ammo] = Math.max(0, this.ammo[d.ammo] - (d.ammoPerShot ?? 1));
    /* AND SOMEBODY HEARD IT. The first one of these is what brings the
       police down the road (js/responders.js); nothing else in here
       needs to know that, which is why it is a count and not a call. */
    this.shotsFired++;
    this.fireIndex = 0;
    this.fireTics = d.fireTics[0];
    this.game.sound?.play(d.sound, this);
    /* the bore leaves the launcher now, at whatever the sight has */
    if (d.lock) this.game.bore?.fire(this);
    /* Being shot at wakes the store up, and so does setting fire to it. */
    this.game.noise(this, d.autofire ? 900 : 700);
  }

  /* ------------------------------------------------------------------
     THE LANCE, which is three states and not a list of frames

       out      the beam is live: it counts down, the coil cooks, and
                nothing else can happen until it stops
       winding  the trigger is down and the charge is climbing
       idle     everything else, which is where a release is noticed

     The order matters. The beam is checked first because a weapon that
     could start charging while its own beam was out would be a weapon
     you could hold the trigger through, and the seven seconds would
     overlap the five.
     ------------------------------------------------------------------ */
  lanceTic(input) {
    const d = this.def;

    /* ---- out -------------------------------------------------------- */
    if (this.beamTics > 0) {
      this.beamTics--;
      /* `firing` is what the gun's muzzle bloom and the view kick read,
         so it is true for exactly as long as the beam is */
      this.fireIndex = this.beamTics > 0 ? 1 : -1;
      this.game.beam?.tic(this);
      if (this.beamTics === 0) { this.beamStage = 0; this.game.beam?.stop(); }
      return;
    }

    /* ---- idle ------------------------------------------------------- */
    this.fireIndex = -1;
    /* A COIL AT ZERO HAS NOTHING TO HOLD. The hold clock only means
       anything while there is a charge sitting on top of it, and it is
       reset where the charge is: on the vent, on the shot, and on the
       first tic of a new wind. Clearing it here as well costs nothing
       and means a stray read between shots gets a zero. */
    if (this.charge === 0) this.hold = 0;

    /* ---- winding ---------------------------------------------------- */
    /* WHAT IT TAKES TO START AND WHAT IT TAKES TO CONTINUE are not the
       same question, and conflating them was a bug waiting to happen:
       armed() refuses a coil that is still hot from the last shot, and
       the coil gets hot FROM CHARGING now, so a gun asked the same
       question every tic would refuse its own charge halfway up and
       fire by falling through to the release below. You need to be
       armed to begin; after that you need a cell. */
    const can = this.charge > 0 ? this.hasAmmo(this.weapon) : this.armed(this.weapon);
    /* A TRIGGER HELD THROUGH A VENT DOES NOT START ANOTHER CHARGE. The
       coil let go; the finger did not; and a gun that began winding up
       again in the same instant would be a gun with no top to it after
       all. It takes releasing and pressing again. */
    if (!input.attack) this.vented = false;
    if (input.attack && can && !this.vented) {
      if (this.charge === 0) {
        this.hold = 0;
        this.game.sound?.play('lancestart', this);
      }
      this.charge = Math.min(CHARGE_MAX, this.charge + 1);
      /* AND AT THE TOP THERE IS A WINDOW. Five seconds to take the shot
         — see HOLD_TICS — and at the end of them the coil vents and you
         start the seven seconds again. It used to OVERCHARGE here, for
         forty seconds, and then kill you; at the user's request that is
         gone in its entirety and this is what is left, which is what
         was here before it. */
      if (this.charge >= CHARGE_MAX && ++this.hold >= HOLD_TICS) {
        this.ventCharge();
        return;
      }
      return;
    }

    /* ---- the trigger came up ---------------------------------------- */
    if (this.charge > 0) {
      const stage = this.chargeStage;
      /* ANYTHING SHORT OF RED IS A VENT AND NOT A SHOT — see FIRE_AT.
         The cell is not spent, nothing leaves the muzzle, and the coil
         fizzles down. Letting go early is how you cancel a charge you
         have changed your mind about, and it is the only way. */
      if (stage >= FIRE_AT) {
        this.charge = 0; this.hold = 0;
        this.fireBeam(stage);
      }
      else this.ventCharge();
      return;
    }

    /* only swap weapons when the coil is idle, never mid-charge */
    if (this.pendingWeapon) { this.weapon = this.pendingWeapon; this.pendingWeapon = null; }
  }

  /* ------------------------------------------------------------------
     THE LAUNCHER, which is a trigger held and a trigger let go

       down     the seeker is looking: js/missiles.js locks what is warm
                in the middle of the sight, one tube's worth at a time
       up       the salvo: one missile per lock, a tube at a time, or
                one straight down the sight if nothing was locked

     While a salvo is still leaving the trigger means nothing and the
     launcher stays in your hands — a weapon swap in the middle of one
     would leave missiles in tubes that are no longer on screen.
     ------------------------------------------------------------------ */
  launcherTic(input) {
    const M = this.game.missiles;
    /* the kick of the last one out, which is what the view model's
       recoil and muzzle flash read as `firing` */
    if (this.fireIndex >= 0 && --this.fireTics <= 0) this.fireIndex = -1;
    if (M && M.salvoLeft > 0) { this.seeking = false; return; }
    if (input.attack) {
      if (!this.seeking && (this.ammo.rockets | 0) <= 0) {
        /* empty tubes click, once per press, like a bore with no lock */
        if (!this._clicked) { this._clicked = true; this.game.sound?.play('noammo', this); }
        return;
      }
      this.seeking = true;
      return;
    }
    this._clicked = false;
    if (this.seeking) {
      this.seeking = false;
      /* the trigger has come up: whatever is locked goes */
      if (M && M.release(this) > 0) return;
    }
    /* ONLY SWAP BETWEEN SALVOS, never while the seeker is up — and not
       while the last one out is still kicking either: `firing` is shared
       by every weapon, and the next one in hand would read the tail of
       this kick as its own trigger and pour a stream nobody asked for */
    if (this.pendingWeapon && this.fireIndex < 0) { this.weapon = this.pendingWeapon; this.pendingWeapon = null; }
  }

  /* ------------------------------------------------------------------
     THE ARC MAW, which is a trigger held and a trigger let go

       down     the charge climbs, from nothing to full over ARC.chargeTics,
                and stays full for as long as you hold it
       up       the discharge: js/arc.js strikes hitsFor(charge) bodies,
                one for a tap and nine at the top

     An empty capacitor clicks, once a press. The weapon only changes
     hands with no charge in it — a swap would take the ball with it.
     ------------------------------------------------------------------ */
  arcTic(input) {
    const snd = this.game.sound;
    if (this.fireIndex >= 0 && --this.fireTics <= 0) this.fireIndex = -1;
    if (input.attack) {
      if (!this.arcCharging && (this.ammo.volts | 0) <= 0) {
        if (!this._clicked) { this._clicked = true; snd?.play('noammo', this); }
        return;
      }
      if (!this.arcCharging) { this.arcCharging = true; this.arcCharge = 0; }
      const was = this.arcCharge;
      this.arcCharge = Math.min(1, this.arcCharge + 1 / ARC.chargeTics);
      /* THE HUM CLIMBS: struck again every few tics, a step higher each
         third of the way, and one last note as it tops out */
      const step = this.arcCharge < 0.34 ? 'arccharge1' : this.arcCharge < 0.67 ? 'arccharge2' : 'arccharge3';
      if (was < 1 && this.arcCharge >= 1) snd?.play('arcfull', this);
      else if (this.game.tics % 9 === 0) snd?.play(step, this);
      return;
    }
    this._clicked = false;
    if (this.arcCharging) {
      this.arcCharging = false;
      const charge = this.arcCharge;
      this.arcCharge = 0;
      this.ammo.volts = Math.max(0, (this.ammo.volts | 0) - 1);
      if (this.ammo.volts <= 0) this.voltDry = true;
      this.shotsFired++;
      this.fireIndex = 1; this.fireTics = 5;
      this.game.arc?.fire(this, charge);
      return;
    }
    if (this.pendingWeapon && this.fireIndex < 0) { this.weapon = this.pendingWeapon; this.pendingWeapon = null; }
  }

  /** One cell, one line drawn through the map. The stage decides how
   *  wide and for how long; js/beam.js decides everything else. */
  fireBeam(stage) {
    const d = this.def;
    if (d.ammo) this.ammo[d.ammo] = Math.max(0, this.ammo[d.ammo] - (d.ammoPerShot ?? 1));
    if (d.ammo && this.ammo[d.ammo] <= 0) this.cellDry = true;
    this.shotsFired++;
    this.beamStage = stage;
    this.beamTics = BEAM_TICS[stage - 1];
    this.fireIndex = 1;
    /* BRACED. The momentum goes now rather than being ignored by move()
       for the length of the discharge, so you stop where you are
       standing instead of sliding to a halt under a beam that is
       already out — and a shot taken from a standstill is most of the
       difference between a rifle and a hose. */
    this.momx = 0; this.momy = 0;
    /* THE DISCHARGE IS THREE RECORDINGS AT ONCE: the transient the
       moment the trigger comes up, and then the two layers of the shot
       itself, which were mixed as two and are played as two. The charge
       loop is stopped by lanceVoice on the next tic, because the charge
       is zero by then and that is what it reads. */
    const snd = this.game.sound;
    /* AND THE DISCHARGE PICKS UP WHERE THE CHARGE LEFT OFF. The
       transient goes off at the pitch the coil had reached, so a stage
       one release sounds like the smaller thing it is and a stage three
       carries the whole climb into the shot; the two layers of the shot
       itself go the other way, a bigger stage being LOWER and longer,
       because that is what more of something sounds like. */
    const p = CHARGE_PITCH[0] + (CHARGE_PITCH[1] - CHARGE_PITCH[0]) * (stage / CHARGE_STAGES.length);
    snd?.sample('lanceprefire', this, { rate: p });
    const boom = 1.14 - 0.13 * stage;
    snd?.sample('lancefire', this, { rate: boom });
    snd?.sample('lancefire2', this, { rate: boom });
    this.game.beam?.fire(this, stage);
    /* AND WHO HEARD IT. Two and a half thousand units used to, which is
       further than anything else in the game wakes and was the right
       number for a weapon that took the street down with the target.
       Eleven hundred is the new one: still the loudest single shot in
       the game and still much further than a shotgun, but it no longer
       brings the whole town to the window every time you take one man
       off a roof. A precise weapon that announced itself to everybody
       would be precise about nothing that mattered. */
    this.game.noise(this, 1100);
  }

  /** HOW MUCH OF THE WINDOW AT THE TOP IS LEFT, 1 the moment the dial
   *  goes red and 0 as the coil vents — see HOLD_TICS. What the gun's
   *  screen draws its inner ring off and what the tests read.
   *
   *  It is a fraction REMAINING rather than elapsed, because that is
   *  the question being asked: a sniper at full charge wants to know
   *  how long they have, not how long they have had. A gauge that
   *  filled as the window closed would be drawing the wrong one. */
  get holdFraction() {
    if (this.charge < CHARGE_MAX || HOLD_TICS <= 0) return 0;
    return Math.max(0, 1 - this.hold / HOLD_TICS);
  }

  /** A CHARGE THAT NEVER BECAME A SHOT, which happens two ways: the
   *  trigger came up before the dial went red, or it stayed down past
   *  the window at the top of it — see HOLD_TICS. Nothing is spent, the
   *  cell is untouched, and what is left is a noise going away.
   *
   *  IT COSTS NOTHING BUT THE SEVEN SECONDS now. It used to leave the
   *  coil a third hot, on the way to a threshold that would refuse the
   *  trigger; there is no heat on this weapon any more, so a vent is
   *  simply a charge you did not take, and the only thing it takes from
   *  you is the time you spent building it. Which, at seven seconds a
   *  shot, is plenty.
   *
   *  THE FIZZLE IS THE CHARGE LOOP ITSELF, played once rather than round
   *  and round, from wherever the pitch had got to and sliding down
   *  below where it started while it fades. It is the same coil, so it
   *  is the same instrument; a separate recording would be a second
   *  voice arriving at the moment the first one stopped. */
  ventCharge() {
    const pitch = this.chargePitch;
    this.charge = 0;
    this.hold = 0;
    this.vented = true;
    const h = this.game.sound?.sample('lancecharge', this, { rate: pitch });
    if (h) { h.rate(CHARGE_PITCH[0] * 0.55, 1.1); h.release(1.2); }
    else this.game.sound?.play('noammo', this);
    /* AND IT SAYS SO, because a charge that disappears without a word
       reads as the gun having broken. The fizzle is the other half of
       this and is the half you hear; this is the half you can check if
       you were looking down the street rather than at the dial. */
    this.game.toast?.('COIL VENTED');
  }

  /** Where on the pitch curve the coil currently is — see CHARGE_PITCH.
   *  One number, read by every charge sound, which is what makes them
   *  one sound. */
  get chargePitch() {
    const t = this.chargeFraction;
    return CHARGE_PITCH[0] + (CHARGE_PITCH[1] - CHARGE_PITCH[0]) * t;
  }

  /** Which of the three stages the charge has reached, 0 for none. While
   *  the beam is out it is the stage that fired, so the gun's screen
   *  keeps saying what it is doing. */
  get chargeStage() {
    if (this.beamTics > 0) return this.beamStage;
    let n = 0;
    for (const sec of CHARGE_STAGES) if (this.charge >= sec * TICRATE) n++;
    return n;
  }

  /** How far round the dial the charge has come, 0..1. */
  get chargeFraction() {
    if (this.beamTics > 0) return 1;
    return CHARGE_MAX > 0 ? this.charge / CHARGE_MAX : 0;
  }

  /** Where the three stage marks fall on that dial — what js/scope.js
   *  draws the ticks at, so the dial and the weapon cannot disagree. */
  get stageMarks() {
    return CHARGE_STAGES.map(sec => (sec * TICRATE) / CHARGE_MAX);
  }

  /** The flamer: one tic of stream out of the nozzle. Where the nozzle
   *  is on screen is the gun's business (js/weapon3d.js), and where the
   *  flame goes after that is js/flame.js's. */
  flameTic(d) {
    const g = this.game;
    /* THE TANK IS BILLED HERE, and running dry stops the pour in the
       middle of it rather than at the end of a shot cycle: the trigger
       is still down, the arm is still up, and nothing comes out. */
    if (d.ammo) {
      if (this.ammo[d.ammo] <= 0) {
        this.fireIndex = -1;
        /* AND IT LATCHES. Empty is not "wait for one unit", it is "wait
           for a share of a tank" — see REFIRE_AT and CO2_REFIRE_AT — so
           the refusal has to survive the trickle that starts the moment
           this happens. */
        if (d.ammo === 'co2') this.co2Dry = true; else this.dry = true;
        return;
      }
      this.ammo[d.ammo]--;
    }
    /* WHICH STREAM, and it is the only line in the firing path that
       knows there is more than one. Everything above — the billing, the
       latch, the animation, the noise — is the same for both, because
       what a held stream weapon does is the same for both. */
    const stream = d.stream === 'frost' ? g.frost : g.flame;
    if (!stream) return;
    stream.fire(g.nozzle(), this.angle, this.pitch);
  }

  /** A TANK THAT FILLS ITSELF, very slowly. There is nothing in the shop
   *  to refill it from any more, so this is the only source: one unit
   *  every REGEN_EVERY tics, which is a full tank in two minutes. It
   *  runs whatever the player is doing, including while firing — the
   *  stream takes one a tic and this gives back a tenth of one, so
   *  holding the trigger still empties it in about twelve seconds. */
  fuelTic() {
    /* INFINITE AMMO IS THIS BRANCH AND NOTHING ELSE, which is the reason
       it goes here rather than in the firing path. Everything that asks
       a question about ammunition — whether the trigger works, whether
       the latch is on, where the pip sits, how full the gauge draws —
       reads the tank, and this runs once a tic upstream of all of them.
       So the spending still happens exactly as it always did and is
       simply undone before anybody looks, and not one line anywhere else
       in the game has to know the mode exists. */
    if (this.debug) {
      for (const kind of Object.keys(this.maxAmmo)) this.ammo[kind] = this.maxAmmo[kind];
      this.dry = false; this.co2Dry = false; this.beltDry = false; this.cellDry = false; this.rocketDry = false; this.voltDry = false;
      this.regenTick = 0; this.co2Tick = 0; this.beltTick = 0; this.cellTick = 0; this.rocketTick = 0; this.voltTick = 0;
      /* AND THE LANCE NEEDS NOTHING SAID ABOUT IT HERE ANY MORE. It
         used to: the coil's real limit was temperature rather than
         ammunition, so a switch that only refilled tanks left the one
         weapon in the game it did not touch, and this branch cleared
         the latch to make up for it. Its heat is gone at the user's
         request — the cell IS the limit now, and the loop above has
         already filled it. */
      return;
    }
    this._refill('fuel', REGEN_EVERY, REFIRE_AT, 'regenTick', 'dry');
    this._refill('co2', CO2_REGEN_EVERY, CO2_REFIRE_AT, 'co2Tick', 'co2Dry');
    this._refill('bores', BORE_REGEN_EVERY, 0, 'boreTick', 'boreDry');
    this._refill('rounds', BELT_REGEN_EVERY, BELT_REFIRE_AT, 'beltTick', 'beltDry');
    /* and the lance's cell, the slowest of the lot: one back every
       twenty-five seconds, and the latch comes off the moment there is
       one in it — unlike the tanks, because a cell is a count of shots
       and not a volume, so "enough for a share of one" means nothing */
    this._refill('cells', CELL_REGEN_EVERY, 1 / CELLS, 'cellTick', 'cellDry');
    /* and the launcher's four tubes, one at a time — see ROCKETS */
    this._refill('rockets', ROCKET_REGEN_EVERY, 0, 'rocketTick', 'rocketDry');
    /* and the arc maw's capacitor, a discharge at a time — see VOLTS */
    this._refill('volts', VOLT_REGEN_EVERY, 0, 'voltTick', 'voltDry');
  }

  /** One tank, one tic. Both fill on the same terms and differ only in
   *  the three numbers passed in — see TANK and BOTTLE for why those
   *  numbers are not the same numbers. */
  _refill(kind, every, mark, tickKey, dryKey) {
    const cap = this.maxAmmo[kind];
    if (this.ammo[kind] >= cap) { this[tickKey] = 0; this[dryKey] = false; return; }
    if (++this[tickKey] < every) return;
    this[tickKey] = 0;
    this.ammo[kind] = Math.min(cap, this.ammo[kind] + 1);
    /* and the latch comes off at its mark: the pip on the gauge goes and
       the bar stops being red, which is the whole announcement now */
    if (this[dryKey] && this.ammo[kind] >= cap * mark) this[dryKey] = false;
  }

  /** How full the tank has to be before the flamer will light again,
   *  as a fraction — 0 when it is not waiting on anything. What the HUD
   *  draws the pip at. */
  get refireMark() {
    const d = WEAPONS[this.weapon];
    return d.refire && this.latched(this.weapon) ? d.refire : 0;
  }

  throwBottle() {
    this.game.spawnMolotov(this);
  }

  /* ------------------------------------------------------------------
     Using things
     ------------------------------------------------------------------ */
  use() { this.game.tryUse(this); }

  /* ------------------------------------------------------------------
     Being hurt
     ------------------------------------------------------------------ */
  damage(amount, source, opts = {}) {
    if (this.dead) return;
    /* INVINCIBLE IS THIS BRANCH AND NOTHING ELSE, for the same reason
       infinite ammo is one branch in fuelTic: everything that hurts the
       player in this game arrives here — the rifles, the vans, the fire
       that FIREPROOF already refuses — and the only way out of the level
       alive is health reaching zero on the line below. Refusing the
       whole function is therefore the whole feature, and nothing else in
       the game needs to know the mode exists. It takes the shove with
       it: being knocked sideways by a van is part of being hit by one.

       It does not heal. Turn it on at forty health and you stay at
       forty, which is the honest reading of the word and keeps the
       switch from quietly being two features. */
    if (this.invincible) return;
    /* fire, blasts, the heat of the floor: none of it, by design. A
       bullet or a van are the two things that get through. */
    if (FIREPROOF && !opts.shot && !opts.impact) return;
    /* THREE LAYERS, SPENT OUTSIDE IN, at the user's request, and they
       are LAYERS and not a soak: the outer plate takes the whole of
       every hit until there is none of it left, then the inner one,
       then you. It used to be Doom's armour rule — a third of each hit,
       while any armour lasted — which shares the damage out instead of
       ordering it, and an order is what was asked for and what a stack
       of three bars draws. The overflow carries, so one hit big enough
       goes through all three in the same call. */
    let left = amount;
    for (const layer of LAYERS) {
      if (left <= 0) break;
      const take = Math.min(this[layer], left);
      this[layer] -= take;
      left -= take;
    }
    this.health -= left;
    this.damageFlash = Math.min(16, 5 + amount * 0.6);
    this.game.sound?.play(opts.fire ? 'burn' : 'hurt', this);
    this.game.onPlayerHurt?.(amount);
    /* the shove, so a hit from the side moves you */
    if (source) {
      const a = Math.atan2(this.y - source.y, this.x - source.x);
      const push = Math.min(6, amount * 0.22);
      this.momx += Math.cos(a) * push; this.momy += Math.sin(a) * push;
    }
    /* AND THE LAUNCH, which is what a vehicle does instead of a shove,
       at the user's request: `launch` is a velocity, sideways and up,
       worked out by whatever hit you from how fast it was going (see
       SwatVan.runOver), and it goes straight into the momentum — up as
       well, which is the part a shove never had, so a van at speed puts
       you in the air and the gravity in move() brings you down somewhere
       else. The grace tics stop the same nose hitting you again every
       tic while you are still in front of it. */
    if (opts.launch) {
      const l = opts.launch;
      this.momx += l.x; this.momy += l.y;
      this.momz = Math.max(this.momz, l.z);
      this.onGround = false;
      this.launched = l.grace ?? 24;
      this.game.sound?.play('whack', this);
    }
    if (this.health <= 0) this.die(source);
  }

  give(kind, amount) {
    if (kind === 'health') {
      const before = this.health;
      this.health = Math.min(HEALTH, this.health + amount);
      if (this.health === before) return false;
    } else {
      const cap = this.maxAmmo[kind] ?? 999;
      if (this.ammo[kind] >= cap) return false;
      this.ammo[kind] = Math.min(cap, this.ammo[kind] + amount);
    }
    this.pickupFlash = 8;
    return true;
  }

  die(source = null) {
    this.dead = true;
    this.health = 0;
    this.armour2 = 0; this.armour1 = 0;
    this.deathViewTarget = this.z + 8;
    /* EVERY HELD SOUND STOPS. tic() returns into deathTic from here on,
       so neither weaponTic nor lanceVoice will run again and neither
       loop would ever be told — a coil charging over a corpse, for the
       rest of the level. */
    this.gunLoop?.stop(); this.gunLoop = null;
    this.chargeLoop?.stop(); this.chargeLoop = null;
    this._chargeVoice = null;
    this.charge = 0;
    this.beamTics = 0;
    this.seeking = false;
    if (this === this.game.player) this.game.beam?.stop();
    this.game.sound?.play('playerDie', this);
    this.game.onPlayerDied(this, source);
  }


  deathTic() {
    /* the view sinks to the floor and stays there */
    this.viewZ += (this.z + 8 - this.viewZ) * 0.12;
    this.momx *= 0.86; this.momy *= 0.86;
    /* a body in the air comes down */
    if (!this.onGround) {
      this.momz -= GRAVITY; this.z += this.momz;
      const floor = this.sector ? this.sector.floor : this.z;
      if (this.z <= floor) { this.z = floor; this.momz = 0; this.onGround = true; }
    }
    const [nx, ny] = this.game.level.slideMove(this.x, this.y, this.momx, this.momy, this.radius, this.z, 8, false);
    this.x = nx; this.y = ny;
  }
}
