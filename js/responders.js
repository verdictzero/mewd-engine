/* =====================================================================
   MEWD — who comes when a supermarket is on fire at 2am
   =====================================================================

   THE SWAT COME, and they are the first thing in the game that fights
   back. The rest of this file is still the shape it was — an alarm that
   only climbs, six tiers that are dispatched at a threshold and arrive
   after a drive — and that shape is kept, because the night manager and
   the fire brigade are still coming one day and the escalation is
   already written and tested. What is new is underneath it: one squad,
   on its own trigger, that does not wait for the alarm.

   WHAT CALLS THEM IS THE TRIGGER, at the user's request. Not the fire —
   a supermarket alight is the fire brigade's business — but the first
   shot out of any weapon, on the tic you fire it, which in this game is
   the first thing anybody does. It used to be the first KILL and a
   sixteen-second wait on top, which together read as the game giving
   you a head start; now there is no head start and the sirens are the
   answer to the flamethrower rather than to the body. THREE AT A TIME,
   at the user's request: where one van used to be sent,
   three are, nose to tail from the same end of the road, and the budget
   is three times what it was so that the second and third are not
   simply refused. They unload their crews one at a time and, when the
   crew is out, keep trickling for as long as they stand there, which is
   for ever, because a squad van is fireproof (see SwatVan) and nothing
   in the game ends one.

   AND THEY COME TO WHEREVER YOU ARE. Inside the building they pull up
   across the fire lane in front of the doors, which is what the fire
   lane is for and what the map's bays say. Anywhere else — the car
   park, the verge, the trees, round the back of the shop — the
   destination is YOU: the nearest point on the perimeter road to
   wherever you are standing, reached by walking the ring the short way
   round from the junction they came in at, and then off the road
   toward you for as far as the tarmac holds. In the middle of the lot
   that is a van pulling up two car lengths away with its side door
   facing you. Behind the building, where no road goes, it is a van on
   the frontage lane and a crew already walking. Hiding moves the fight;
   it does not end it.

   AND IT RAMPS EXPONENTIALLY, at the user's request, and the ramp is
   ONE NUMBER: the PRESSURE, 1 at the call and doubling every so many
   seconds from then on, without limit. Everything that says how much
   police there is — how many vans may be on the road or standing, how
   many troopers may be on their feet, how long between vans, how long
   between one trooper and the next out of a standing van — is a
   starting value times that number, read off the curve at the moment
   the question is asked rather than fixed at the call. So the same
   minute of the night is the same everywhere: the vans come twice as
   often, the doors open twice as often and twice as many are allowed
   out, all together. The floors under the gaps and the ceiling on the
   troopers are what the engine can carry, not the design; the design
   is the curve, and the curve does not stop.

   AND THEN THE ARMY COMES, at the user's request and in the order the
   user set: the SWAT, then the army, then a super army after them. The
   army is not a harder SWAT van, it is a SECOND FORCE — its own clock,
   its own budget, its own curve starting at 1 the moment it is called,
   its own carrier (the APC, which hovers; see ArmyApc in
   js/vehicles.js) and its own soldier (see ACTORS.ARMY). It is called
   at a PRESSURE rather than at a time — when the night is pressing
   eight times what it was at the first shot, which on the SWAT's own
   doubling clock is three minutes in — so the threshold is written in
   the same units as the escalation it is part of, and retuning the
   doubling moves the army with it rather than leaving it behind.

   WHAT THE TWO FORCES SHARE is everything about the MAP: the ring, the
   ways in, the bays, where a stand is and how a route reaches it. What
   they do not share is anything about themselves. So FORCES below is a
   row per force and the machinery underneath takes one as an argument;
   the super army is a third row and a sheet, and nothing else.

   AND THE FIRE LANE HAS NINE BAYS, which the curve asks past inside
   four minutes. When they are all full the next one stands along the
   ring by the doors instead of not coming, which is the same answer
   this file already gives for a player out in the car park — the ring
   is a place to stand anywhere on it, and running out of bays was the
   one way the escalation used to quietly stop.

   WHERE THEY GO is the map's business. level.swatRoutes is the way in
   from each end of the road and level.swatBays is where a van may stop,
   both worked out where the lot's own numbers are; this file joins one
   to the other and drives nothing itself. See SwatVan and ArmyApc in
   js/vehicles.js for the driving and js/states.js for the troops.
   ===================================================================== */

import { TICRATE, pRandom } from './util.js';
import { SwatVan, ArmyApc } from './vehicles.js';

/* Who, at what alarm, and how long they take to get here. Delays are in
   tics. `count` and `note` describe the wave that will arrive when there
   is something to arrive. */
export const TIERS = [
  { tier: 1, name: 'the night manager', at: 3,  delay: 25 * TICRATE,  count: 1,
    dispatch: 'SOMEBODY HAS NOTICED', arrive: 'THE NIGHT MANAGER IS OUT THE BACK WITH A TORCH',
    note: 'one person, an extinguisher and a torch; the softest tier' },
  { tier: 2, name: 'security', at: 8,  delay: 40 * TICRATE,  count: 2,
    dispatch: 'SOMEBODY HAS CALLED IT IN', arrive: 'SECURITY HAS PULLED INTO THE LOT',
    note: 'two in a van, radios, no appetite for it' },
  { tier: 3, name: 'the police', at: 18, delay: 55 * TICRATE,  count: 2,
    dispatch: 'SIRENS, A LONG WAY OFF', arrive: 'BLUE LIGHTS ON THE ROAD',
    note: 'two cars; they want you, not the fire' },
  { tier: 4, name: 'the fire brigade', at: 30, delay: 70 * TICRATE,  count: 2,
    dispatch: 'A SECOND SIREN, DEEPER', arrive: 'THE FIRE BRIGADE IS HERE',
    note: 'two appliances; they want the fire, and they will put it out' },
  { tier: 5, name: 'riot police', at: 50, delay: 90 * TICRATE,  count: 4,
    dispatch: 'HELICOPTER', arrive: 'THE VANS ARE HERE',
    note: 'four vans and shields; the last thing on the ground' },
  { tier: 6, name: 'the helicopter', at: 75, delay: 120 * TICRATE, count: 1,
    dispatch: 'YOU CAN HEAR IT COMING', arrive: 'IT IS OVERHEAD',
    note: 'searchlight and a water bucket; the ceiling of the escalation' },
];

/* How the alarm is made from what the night looks like. */
export const ALARM = {
  store: 0.55,      // per percent of the store burnt
  wood: 0.25,       // per percent of the wood
  kill: 2.0,        // per member of staff
  minute: 3.0,      // per minute anything has been alight
  max: 100,
};

/** The alarm, as a pure function of the night, for the test. */
export function alarmOf({ storePct = 0, woodPct = 0, kills = 0, minutesAlight = 0 }) {
  return Math.min(ALARM.max,
    storePct * ALARM.store + woodPct * ALARM.wood + kills * ALARM.kill + minutesAlight * ALARM.minute);
}

/* ---------------------------------------------------------------------
   THE SQUAD, IN NUMBERS

   `after` is the trigger pull that calls them — the first — and
   `firstDelay` is what used to be the drive from wherever they were
   and is now nothing: they are dispatched on the tic you fire.

   THEN THE CURVE. `doubling` is how often the pressure doubles, from
   the call; the four `at pressure 1` numbers are what the night starts
   at, and every one of them is divided or multiplied by the pressure
   as it is used (see pressure, vanCap, trooperCap, gapNow, trickleNow).
   A minute in: twice the vans allowed, twice the troopers, half the
   gap, half the trickle. Two minutes: four times. Three: eight. The
   floors and the ceiling are the engine's, and the bays are the map's;
   the curve reaches all of them inside four minutes and then simply
   holds the lot at what the engine will carry.
   ------------------------------------------------------------------- */
export const SWAT = {
  /* WHAT CALLS THEM IS THE TRIGGER, at the user's request: one shot out
     of any weapon, which is the first thing anybody does in this game.
     It used to be one kill, which in practice was ten seconds later and
     read as the game letting you start. */
  after: 1,                              // shots fired before anybody is called
  firstDelay: 0,                         // and they are dispatched on that tic
  /* A SMIDGE LESS OF ALL OF IT, at the user's request, and the whole of
     the reduction is in this block and the four numbers below. It is a
     trim rather than a rewrite: nothing about WHEN the first convoy
     arrives has moved — that is the run-in and the speed, and the user
     asked for those and they stay — and neither has the size of a send.
     What has come down is how fast the night builds on top of it and
     how much of it the lot ever holds.

     The doubling is seventy seconds rather than sixty, so every step of
     the curve takes a sixth longer: two minutes in the night is
     pressing three and a third rather than four, three minutes six
     rather than eight. The ceilings come down a quarter. And the four
     starting values each lose one, which is the part that is felt in
     the first minute, when the curve has not multiplied anything yet.

     Measured standing still in the middle of the lot, never firing
     again, so nobody dies and the count is what the budget allows
     rather than what you let live:

                 was                    now
       1 min     11 troopers            9
       2 min     23                     16
       3 min     47                     29
       4 min     80, the ceiling        53
       5 min     80 + 15 army           60, the ceiling, + 9
       6 min     80 + 31 army           60 + 17

     The ceiling is sixty rather than eighty and arrives at five minutes
     rather than four. The army is untouched — it is the user's newest
     thing and there is not much of it — but it starts later anyway,
     because its trigger is a pressure on this curve and this curve now
     takes longer to get there: three and a half minutes rather than
     three. */
  doubling: 70 * TICRATE,                // how often the pressure doubles, from the call
  every: 60 * TICRATE,                   // the gap between sends, at pressure 1, give or take a fifth
  minEvery: 7 * TICRATE,                 // and the least it can ever be
  /* THREE AT A TIME, at the user's request: where one van used to come,
     three come. The gap between sends is untouched, and so is every
     other clock — what tripled is the size of a send and, with it, the
     budget, or the first two of the three would have been the whole of
     it. */
  convoy: 3,                             // vans per send — the user's number, untouched
  vans: 5,                               // on the road or standing at once, at pressure 1
  maxVans: 20,                           // and the most the engine is asked to carry
  troopers: 5,                           // on their feet at once, at pressure 1
  maxTroopers: 60,                       // and the most the engine is asked to carry
  crew: 5,                               // what a van carries
  unloadEvery: 52,                       // tics between one and the next
  trickle: 10 * TICRATE,                 // and after the crew is out, for ever, at pressure 1
  minTrickle: 3 * TICRATE,               // and the least that can be
  bays: 9,                               // spaces along the fire lane, for the doors
  /* WHERE A VAN STOPS WHEN IT IS COMING FOR YOU rather than for the
     doors. `stand` is how far apart two of them park along the ring,
     `push` is how far off the road one will drive to reach you, `stop`
     is how close it parks, and `convoyGap` is how far back down the
     road the second and third of a send start, so they arrive as a
     line rather than inside one another.

     AND `stop` IS THREE HUNDRED, which is the third number it has been
     and the user's second thought about it. Two hundred and sixty was
     called too far away; a hundred and twenty put the nose thirteen
     units off your face, which is what "almost run into" asks for and
     turned out to be too much of it. Three hundred is to the MIDDLE of
     a van two hundred and fourteen long, so the nose stops about two
     hundred off — half a van, near enough to be in your way and far
     enough to be a van rather than a wall. Braking into it rather than
     stopping dead is the other half of why it reads differently now;
     see DRIVE_BRAKE in js/vehicles.js.

     AND `push` IS TWENTY-SIX HUNDRED, so that reaching you means
     crossing the lot rather than leaving the kerb. What stops one is
     the tarmac running out, not the budget: the walk toward you gives
     up the moment the ground is not drivable, so the number only ever
     buys distance over ground a van could really cross. */
  stand: 560,
  push: 2600,
  stop: 300,
  convoyGap: 460,
  /* AND WHERE THEY COME FROM WHEN YOU ARE OUTSIDE, which is the other
     half of "as rapidly as possible". The map's ways in start at the
     END of the through road, nine thousand units out, because that is
     where the road leaves the world and because a van appearing at the
     junction out of nothing is a van that was never anywhere. That is
     the right answer for a night you are watching from inside the
     shop and the wrong one for a night you are standing in the middle
     of: five of the fourteen seconds were a van driving down a road
     nobody can see.

     So when they are coming FOR you they do not drive the road at all.
     They come into being ON IT, `runIn` back from wherever they leave
     it — eleven hundred units, about two seconds once the braking and
     the standing start are paid for — which is the "closer" half of the
     user's request.

     AND OUT OF SIGHT, which is the other half and the reason this is a
     search rather than a number. Eleven hundred units is four van
     lengths: near enough to see one appear if you happen to be looking
     that way. So the point is walked further back, half a thousand at a
     time, for as long as it is inside your view — see trimEntry and
     canSee. Face the road and they come from further off; face the shop
     and they are on you in two seconds from somewhere behind your
     shoulder. Neither case ever shows you a vehicle arriving out of
     nothing, which is the only thing that actually had to be true.

     Inside the building nothing changes: they come the whole length of
     the road from the end of the world, because you are not watching
     it. */
  runIn: 1100,
  runInStep: 500,                        // and how much further back if you are looking
  runInTries: 8,                         // before it gives up and comes anyway
};

/* ---------------------------------------------------------------------
   AND THE ARMY, IN THE SAME NUMBERS

   Read against the SWAT above, which is the only way to read them.
   FEWER AND HEAVIER is the whole design: two carriers a send against
   three vans, two on the road at pressure 1 against six, four soldiers
   on their feet against six — and each of those soldiers is two and a
   third of a trooper with a burst rifle (see ACTORS.ARMY). The ceiling
   is a third of the SWAT's because forty soldiers is already more than
   the sixteen hundred of you can walk through, and because an APC is
   two and a half times a van on the screen: the same ground holds
   fewer of them and reads as fuller.

   THE CLOCKS ARE SLOWER AND THE DOORS ARE FASTER. Seventy seconds
   between sends against fifty-five, because a carrier is not a squad
   car; forty tics between one soldier and the next against fifty,
   because a ramp is not a side door; and eight in the back against six.

   AND THEY STAND FURTHER APART: seven hundred along the ring against
   five hundred and sixty, which is what a vehicle a fifth longer and
   half again wider needs to not be parked inside the last one.

   `at` is the one number that is not about the army at all. It is the
   SWAT's pressure at the moment the army is called — two, which is
   one doubling, which is seventy seconds after your first shot (it was
   eight, three and a half minutes, and the user wanted the army
   sooner) — and from that
   tic the army has a curve of its own starting at 1. So the army
   arrives small while the police are already twofold, and then doubles
   on the same clock underneath them. Nobody leaves.
   ------------------------------------------------------------------- */
export const ARMY = {
  at: 2,                                 // the SWAT's pressure when they are called
  firstDelay: 0,                         // and then they come at once, like everybody
  doubling: 60 * TICRATE,
  every: 70 * TICRATE, minEvery: 9 * TICRATE,
  convoy: 2, vans: 2, maxVans: 10,
  troopers: 4, maxTroopers: 40,
  crew: 8, unloadEvery: 40, trickle: 11 * TICRATE, minTrickle: 3 * TICRATE,
  bays: 9,
  /* the same three as the SWAT's, read against a carrier a fifth longer
     and half again as wide: they stand further apart, they stop a
     little further out because there is more of them to stop, and they
     come in off the same short run at the junction. */
  stand: 700, push: 2600, stop: 360, convoyGap: 620, runIn: 1100,
};

/* ---------------------------------------------------------------------
   WHO IS ON THE ROAD, IN ORDER

   One row a force, and the order of the rows is the order of the night.
   `troop` is the actor that gets out, `model` is the field on the Game
   that holds the vehicle it gets out of — see js/main.js, which loads
   them — and `Van` is the class that drives it. `num` is the block of
   numbers above.

   The super army is a fourth entry in js/people.js, a third here, a
   third call to troopStates in js/states.js and a third kit in
   js/sprites.js. That is the whole of it, and it is the reason all four
   of those are tables.
   ------------------------------------------------------------------- */
export const FORCES = [
  { key: 'swat', name: 'the SWAT', troop: 'SWAT', model: 'police', Van: SwatVan, num: SWAT,
    message: 'SIRENS' },
  { key: 'army', name: 'the army', troop: 'ARMY', model: 'apc', Van: ArmyApc, num: ARMY,
    message: 'THE ARMY IS ON THE ROAD' },
];

/** The curve, as a pure function: how many times harder the night is
 *  pressing `tics` after the call. 1 at the call, 2 a doubling later,
 *  4 after two, and so on — equal steps in time multiply by the same
 *  amount, which is what exponential means and what the test pins. */
export function pressureAfter(tics) {
  return Math.pow(2, Math.max(0, tics) / SWAT.doubling);
}

const rnd = () => pRandom() / 255;

/* HOW WIDE "YOU ARE LOOKING AT IT" IS. The camera is seventy-two degrees
   vertical on a frame about 1.6 wide, which is a hundred across, so half
   of it is fifty; this is a little over, because a vehicle appearing at
   the very edge of the frame is still a vehicle appearing. See canSee. */
const SEE_HALF = 1.05;                   // radians, about sixty degrees

export class Responders {
  constructor(game) {
    this.game = game;
    this.alarm = 0;
    this.alightTics = 0;
    this.dispatched = new Map();     // tier -> tic dispatched
    this.arrived = new Set();
    this.defeatedCount = 0;
    this.waves = [];                 // what spawn() was asked for, for anyone watching
    this.tics = 0;

    /* THE FORCES, one state block each and in the order of the night:
       when it was called, when its next send is due, and how many it
       has put on the ground. Everything else about one is in its row of
       FORCES and in the block of numbers that row points at. */
    this.forces = FORCES.map(def => ({ def, num: def.num, called: false, calledAt: -1, nextVanAt: -1, gap: 0, spawned: 0 }));
    this.swat = this.forces[0];
    this.army = this.forces[1];
    this.vans = [];                  // every vehicle that has come, of either force
    this.side = 0;                   // which end of the road the next one uses
  }

  /** The force with this key, for anyone outside asking about one. */
  forceOf(key) { return this.forces.find(f => f.def.key === key) || null; }

  /* WHAT THE SQUAD USED TO BE, when it was the only one. Every one of
     these is now the SWAT's own, spelled the way it has always been
     spelled, so the rest of the game and every test written against a
     night with one force in it still asks the same questions. The two
     that are SET as well as read — the call and the next send — are
     accessors for that reason. */
  get called() { return this.swat.called; }
  set called(v) { this.swat.called = !!v; }
  get calledAt() { return this.swat.calledAt; }
  set calledAt(v) { this.swat.calledAt = v; }
  get nextVanAt() { return this.swat.nextVanAt; }
  set nextVanAt(v) { this.swat.nextVanAt = v; }
  get gap() { return this.swat.gap; }
  /** Troopers put on the ground by anybody, ever. */
  get spawned() { return this.forces.reduce((n, f) => n + f.spawned, 0); }

  /* ------------------------------------------------------------------
     THE CURVE, read off the clock
     ------------------------------------------------------------------ */
  /** How hard one force is pressing now: 0 before it is called, 1 at
   *  the call, and doubling every `doubling` tics from then on. Every
   *  force has its own, off its own call, so the army arriving at 1
   *  under a police force already at 8 is exactly what it looks like. */
  pressureOf(f) { return f.called ? pressureAfter(this.tics - f.calledAt) : 0; }
  /** Vehicles of one force allowed on the road or standing at once. */
  vanCapOf(f) { return Math.min(f.num.maxVans, Math.floor(f.num.vans * this.pressureOf(f))); }
  /** And its troops allowed on their feet at once, across all of them. */
  trooperCapOf(f) { return Math.min(f.num.maxTroopers, Math.floor(f.num.troopers * this.pressureOf(f))); }
  /** The gap to one force's next send: its starting gap over its
   *  pressure, give or take a fifth so two nights are not the same
   *  night. */
  gapNow(f = this.swat) { return Math.max(f.num.minEvery, f.num.every * (0.8 + 0.4 * rnd()) / this.pressureOf(f)); }
  /** The gap between one trooper and the next out of a standing vehicle
   *  whose crew is already out, now. */
  trickleNow(f = this.swat) { return Math.max(f.num.minTrickle, f.num.trickle / this.pressureOf(f)); }

  /* and the same four as the SWAT's own, which is what they used to be */
  get pressure() { return this.pressureOf(this.swat); }
  get vanCap() { return this.vanCapOf(this.swat); }
  get trooperCap() { return this.trooperCapOf(this.swat); }

  get tier() { return Math.max(0, ...this.arrived); }
  get nextTier() { return TIERS.find(t => !this.dispatched.has(t.tier)) || null; }

  /* Where the road leaves the map: whoever comes, comes from one of
     these. Falls back to the mouth of the lot if the map has no road. */
  arrivalPoints(tier = 0) {
    const lv = this.game.level;
    /* THE POLICE AND THE FIRE BRIGADE COME FROM SOMEWHERE, now that
       there is somewhere to come from. Tier 3 is called "the police"
       and tier 4 "the fire brigade" and both of them used to arrive out
       of the wood from nowhere, which was the second of TOWN.txt's
       three reasons for building a town at all. They are four blocks
       away on A5 — in the yard behind the municipal offices, which is
       where a town this size keeps its vehicles, and which is what is
       on that block now that the two lots with a ceiling and no
       building over them are gone. The comment that used to be on
       spawn() said PLACEHOLDER. */
    const st = lv.town?.stations;
    if (st) {
      const from = tier === 3 ? st.police : tier === 4 ? st.fire : null;
      if (from) return [{ x: from.x, y: from.y, heading: Math.PI / 2, side: tier === 3 ? 'the police station' : 'the fire station' }];
    }
    if (lv.roadEnds?.length) return lv.roadEnds;
    const p = this.game.player;
    return [{ x: p ? p.x : 0, y: p ? p.y - 400 : 0, heading: Math.PI / 2, side: 'the lot' }];
  }

  tic() {
    this.tics++;
    const g = this.game;
    if (g.fire?.burningCells > 0 || g.forest?.burningCells > 0) this.alightTics++;
    this.squadTic();
    /* once a second is plenty for something that only ever climbs */
    if (this.tics % TICRATE) return;
    const a = alarmOf({
      storePct: g.burnPercent, woodPct: g.forestPercent,
      kills: g.player?.kills || 0, minutesAlight: this.alightTics / TICRATE / 60,
    });
    if (a > this.alarm) this.alarm = a;

    for (const t of TIERS) {
      if (!this.dispatched.has(t.tier) && this.alarm >= t.at) this.dispatch(t);
      const when = this.dispatched.get(t.tier);
      if (when !== undefined && !this.arrived.has(t.tier) && this.tics - when >= t.delay) this.arrive(t);
    }
  }

  dispatch(t) {
    this.dispatched.set(t.tier, this.tics);
    this.game.onResponders?.('dispatch', t);
  }

  arrive(t) {
    this.arrived.add(t.tier);
    const points = this.arrivalPoints(t.tier);
    const from = points[(t.tier + this.tics) % points.length];
    this.spawn(t, from);
    this.game.onResponders?.('arrive', t, from);
  }

  /**
   * Where a tier's wave is put on the road. Records what was asked for
   * and returns; what actually drives in is the squad, below, and what
   * this is for is the account of who was sent and from where.
   *
   * It said PLACEHOLDER for a long time because there was nowhere for
   * anybody to come FROM — nine thousand units of wood in every
   * direction and two points where the road left the map. There is a
   * town now: see arrivalPoints, and THE RESPONDERS COME FROM NOWHERE
   * in TOWN.txt, which is the paragraph this answers.
   */
  spawn(t, from) {
    this.waves.push({ tier: t.tier, name: t.name, count: t.count, x: from.x, y: from.y, heading: from.heading, side: from.side, tic: this.tics });
  }

  /** A member of a wave reporting in as beaten. */
  defeated(actor) {
    this.defeatedCount++;
    this.game.onResponders?.('defeated', actor);
  }

  /* ------------------------------------------------------------------
     THE SQUAD
     ------------------------------------------------------------------ */
  /** Vehicles that are still a vehicle: on the road, standing, or
   *  charring. A wreck is not one, and neither is one in the air —
   *  which since they became fireproof is every one that has ever come,
   *  but the count is kept honest against the day something ends one. */
  get liveVans() { return this.vans.filter(v => v.whole); }
  liveVansOf(f) { return this.vans.filter(v => v.force === f && v.whole); }

  /** Troops of one force on their feet, anywhere. Counted, not kept,
   *  for the same reason Game.peopleLeft is. */
  troopersOf(f) {
    let n = 0;
    const t = f.def.troop;
    for (const a of this.game.actors) if (a.type === t && !a.dead && !a.removed) n++;
    return n;
  }

  /** And everybody's, which is what the HUD would ask if it asked. */
  get troopers() { return this.forces.reduce((n, f) => n + this.troopersOf(f), 0); }

  /** The model one force arrives in, or null if it never loaded — see
   *  js/main.js. A force with no vehicle simply does not come, which is
   *  the same bargain every other asset in this game makes. */
  modelFor(f) { return this.game[f.def.model] || null; }

  squadTic() {
    const g = this.game, p = g.player;
    if (!p) return;
    /* AND SOME WORLDS SEND NOBODY. The grid (js/maps/grid.js) is a test
       bed for the burning and the user asked for the brigade in it and
       nothing else: no SWAT, no army, and — since the gunship flies
       when the army is called and the army never is — no air support
       either. The brigade is not in here; it runs off the fire, on its
       own clock, in js/brigade.js. */
    if (g.level.noSquads) return;
    /* THE CALL. One pull of the trigger and the first convoy is on the
       road that tic — or one death, if somebody has managed to die
       without a shot being fired, which the fire can do on its own once
       it is going. */
    if (!this.called && (p.shotsFired >= SWAT.after || p.kills > 0)) this.call();
    if (!this.called || p.dead) return;
    /* AND THEN EVERYBODY WHO IS ALREADY COMING, plus anybody the curve
       has just reached. A force waiting its turn is called the tic the
       SWAT's pressure passes its threshold and starts its own curve at
       1 from there; the ones ahead of it do not stop. */
    for (const f of this.forces) {
      if (!f.called) {
        if (!(f.num.at > 0) || this.pressure < f.num.at) continue;
        this.call(f);
      }
      this.forceTic(f);
    }
  }

  /** One force's turn: the next send if its curve allows another on the
   *  road, and then whatever comes out of the ones that are here. */
  forceTic(f) {
    const N = f.num;
    /* the next send, if the curve allows another on the road. The gap
       is read off the curve as each one leaves, not set at the call, so
       the fourth comes on the fourth's terms; and when the cap itself
       climbs past what is standing, the next goes the tic it does,
       because the gap has long since run out */
    if (this.tics >= f.nextVanAt && this.liveVansOf(f).length < this.vanCapOf(f) && this.modelFor(f)) {
      this.sendConvoy(f);
      f.gap = this.gapNow(f);
      f.nextVanAt = this.tics + Math.round(f.gap);
    }
    const cap = this.trooperCapOf(f);
    for (const v of this.vans) {
      if (v.force !== f) continue;
      if (v.state !== 'parked' && v.state !== 'charring') continue;
      if (v.unloadAt === undefined) v.unloadAt = this.tics + N.unloadEvery;
      if (this.tics < v.unloadAt) continue;
      if (this.troopersOf(f) >= cap) { v.unloadAt = this.tics + TICRATE; continue; }
      if (this.unload(v, f)) {
        v.unloaded = (v.unloaded || 0) + 1;
        v.unloadAt = this.tics + (v.unloaded < N.crew ? N.unloadEvery : Math.round(this.trickleNow(f)));
      } else v.unloadAt = this.tics + 12;          // the door is blocked; try again shortly
    }
  }

  call(f = this.swat) {
    f.called = true;
    f.calledAt = this.tics;
    f.nextVanAt = this.tics + (f.num.firstDelay || 0);
    f.gap = 0;
    const g = this.game;
    /* NOTHING IS WRITTEN ACROSS THE PICTURE ANY MORE, at the user's
       request: the call used to put SIRENS, or THE ARMY IS ON THE ROAD,
       in the middle of the screen for three seconds, and the siren
       itself says it. The words stay in FORCES for whoever reads the
       table; nothing draws them. */
    g.sound?.play(f === this.swat ? 'siren' : 'hover', null);
    g.onResponders?.('called', f.def);
  }

  /* ------------------------------------------------------------------
     THE RING, AS ONE NUMBER

     The perimeter road is a closed loop (level.swatRing, four corners)
     and every question about where a van goes turns into a distance
     round it. A van enters at whichever junction the through road meets
     and walks the loop the short way to its stand, which is how it can
     now be sent to any side of the lot rather than only to the doors.
     ------------------------------------------------------------------ */
  get ring() {
    const pts = this.game.level.swatRing;
    if (!pts || pts.length < 3) return null;
    if (this._ring && this._ring.pts === pts) return this._ring;
    const segs = [];
    let total = 0;
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length];
      const len = Math.hypot(b.x - a.x, b.y - a.y);
      segs.push({ a, b, len, start: total, dx: (b.x - a.x) / len, dy: (b.y - a.y) / len });
      total += len;
    }
    return (this._ring = { pts, segs, total });
  }

  /** A distance round the loop, as a point and the way you are facing. */
  ringAt(t) {
    const R = this.ring;
    const u = ((t % R.total) + R.total) % R.total;
    const s = R.segs.find(q => u >= q.start && u <= q.start + q.len) || R.segs[R.segs.length - 1];
    const d = u - s.start;
    return { x: s.a.x + s.dx * d, y: s.a.y + s.dy * d, dx: s.dx, dy: s.dy };
  }

  /** How far round the loop the point nearest (x, y) is. */
  ringNearest(x, y) {
    const R = this.ring;
    let best = 0, bd = Infinity;
    for (const s of R.segs) {
      const d = Math.max(0, Math.min(s.len, (x - s.a.x) * s.dx + (y - s.a.y) * s.dy));
      const px = s.a.x + s.dx * d, py = s.a.y + s.dy * d;
      const q = (px - x) ** 2 + (py - y) ** 2;
      if (q < bd) { bd = q; best = s.start + d; }
    }
    return best;
  }

  /** The corners strictly between two points on the loop, the short way
   *  round, in the order they are driven through. */
  ringPath(t0, t1) {
    const R = this.ring;
    const fwd = ((t1 - t0) % R.total + R.total) % R.total;
    const dir = fwd <= R.total - fwd ? 1 : -1;
    const dist = dir > 0 ? fwd : R.total - fwd;
    const out = [];
    for (const s of R.segs) {
      const d = dir > 0 ? ((s.start - t0) % R.total + R.total) % R.total
                        : ((t0 - s.start) % R.total + R.total) % R.total;
      if (d > 1 && d < dist - 1) out.push({ d, x: s.a.x, y: s.a.y });
    }
    return out.sort((p, q) => p.d - q.d).map(p => ({ x: p.x, y: p.y }));
  }

  /** Tarmac a van will drive on: outdoors, and not the wood, the
   *  covered walkway or the sign it stands on. */
  drivable(x, y) {
    const s = this.game.level.sectorAt(x, y);
    return !!s && !!s.outdoor && !/wood|canopy|sign/i.test(s.name || '');
  }

  /* ------------------------------------------------------------------
     WHERE THIS ONE IS GOING

     Inside the building, they come to the doors, which is what the fire
     lane is for and what the map's bays say. ANYWHERE ELSE — the car
     park, the verge, the trees, round the back — they come to YOU, at
     the user's request: the nearest point on the ring to wherever you
     are standing, and then off the road toward you for as far as the
     tarmac holds. Behind the building the tarmac holds for no distance
     at all, so what arrives is a van on the frontage lane with its
     crew already walking; in the middle of the lot it is a van pulling
     up two car lengths away.
     ------------------------------------------------------------------ */
  /** Is the player somewhere a van should come to, rather than the doors? */
  get chasing() {
    const p = this.game.player;
    return !!p && !p.dead && !!p.sector && !!p.sector.outdoor;
  }

  /** A stand at the doors: one of the map's bays, squared up along the
   *  front, with the lead in off the frontage lane. */
  bayStand(bay) {
    const t = this.ringNearest(bay.x, bay.approach?.y ?? bay.y);
    const on = this.ringAt(t);
    return {
      x: bay.x, y: bay.y, bay,
      angle: on.dx >= 0 ? 0 : Math.PI,
      ring: t,
      lead: [{ x: bay.x, y: on.y }, { x: bay.x, y: bay.y }],
    };
  }

  /** A stand beside a point: `slot` steps along the ring from the point
   *  on it nearest, then in off the road toward it as far as the tarmac
   *  goes. `N` is the force's numbers, because how far apart two of
   *  them park and how close they get is about how big they are. */
  chaseStand(p, slot, N = SWAT) {
    const t = this.ringNearest(p.x, p.y) + slot * N.stand;
    const on = this.ringAt(t);
    const dx = p.x - on.x, dy = p.y - on.y;
    const d = Math.hypot(dx, dy) || 1;
    const ux = dx / d, uy = dy / d;
    const reach = Math.min(N.push, Math.max(0, d - N.stop));
    let gone = 0, x = on.x, y = on.y;
    /* THIRTY-FIVE, not seventy. The walk gives up a whole step short of
       the reach, so the step is the slack in how close one gets — at
       seventy that was most of the hundred and twenty it is aiming for,
       and a van meant to stop a nose from you stopped two. */
    const STEP = 35;
    while (gone + STEP <= reach) {
      const nx = x + ux * STEP, ny = y + uy * STEP;
      if (!this.drivable(nx, ny)) break;
      x = nx; y = ny; gone += STEP;
    }
    return {
      x, y, ring: ((t % this.ring.total) + this.ring.total) % this.ring.total,
      angle: gone > 0 ? Math.atan2(uy, ux) : Math.atan2(on.dy, on.dx),
      lead: gone > 0 ? [{ x, y }] : [],
    };
  }

  /** Nothing already standing there — anybody's, since the fire lane
   *  does not care which force is blocking it. The room asked for is
   *  the asker's own, so an APC demands more of it than a van. */
  standClear(s, N = SWAT) {
    const r = N.stand * 0.7;
    return !this.liveVans.some(v => v.stand && (v.stand.x - s.x) ** 2 + (v.stand.y - s.y) ** 2 < r * r);
  }

  /** The next place one of `f`'s vehicles should go, or null if there
   *  is nowhere left at all.
   *
   *  Inside the building that is a bay in the fire lane. WHEN THE BAYS
   *  ARE GONE it is a stand along the ring by the doors instead of
   *  nothing: nine bays against a curve that asks for twenty-seven
   *  inside four minutes used to mean the escalation stopped at nine
   *  and said nothing about it, which is the one place the design's own
   *  "the curve does not stop" was not true. */
  freeStand(f = this.swat) {
    if (!this.ring) return null;
    const N = f.num;
    let at = this.game.player;
    if (!this.chasing) {
      const bay = this.freeBay(f);
      if (bay) return this.bayStand(bay);
      at = this.doorsPoint() || at;
    }
    if (!at) return null;
    /* THE BEST OF THEM, NOT THE FIRST OF THEM, at the user's request.
       Thirty-three places along the ring, working outward from the one
       nearest you — which is also what the ceiling on vehicles
       (maxVans) needs to be reachable rather than a number the search
       quietly stops short of.

       It used to take the first place that was free, which is right
       whenever the ground between the road and you is open: the nearest
       point on the ring drives straight at you and stops a nose short.
       It is wrong the moment something is IN THE WAY. Stand in the
       trees and the nearest point on the ring has a wood between it and
       you, so the van gives up at the kerb fifteen hundred units off —
       while a point further round, with the tarmac of the lot in front
       of it, would have got most of the way. Same behind the building,
       where the nearest point has the shop in the way.

       So every free slot is walked and the one that ENDS nearest you
       wins. The walk is what costs — a few hundred sector lookups — so
       it stops the moment one of them lands within a step of `stop`,
       which in the car park is the first slot it tries and no cost at
       all. It is only the awkward places that pay, and they are the
       places it is for. */
    let best = null, bd = Infinity;
    for (let k = 0; k <= 16; k++) {
      const slot = k === 0 ? 0 : (k & 1 ? (k + 1) >> 1 : -(k >> 1));
      const s = this.chaseStand(at, slot, N);
      if (!this.standClear(s, N)) continue;
      const d = Math.hypot(s.x - at.x, s.y - at.y);
      if (d < bd) { bd = d; best = s; }
      if (bd <= N.stop + 36) break;          // as close as the walk can get
    }
    return best;
  }

  /** The front of the shop: the middle bay, which is the first one the
   *  map lists. What everybody queues along when the lane is full. */
  doorsPoint() {
    const bays = this.game.level.swatBays;
    return bays && bays.length ? bays[0] : null;
  }

  /** A bay nobody is standing in. The middle one first, then either
   *  side of it, working outward; a van never leaves one. Taken is
   *  taken whoever took it — an APC in the fire lane is in the fire
   *  lane. */
  freeBay(f = this.swat) {
    const bays = this.game.level.swatBays;
    if (!bays || !bays.length) return null;
    /* AND A WRECK DOES NOT HOLD ONE. It never came up while they were
       fireproof and nothing ever ended one; now that the stream does,
       burning a van out of the fire lane has to give the lane back or
       the bay is held for ever by a thing that is not there. */
    const taken = new Set(this.liveVans.map(v => v.bay));
    return bays.slice(0, f.num.bays).find(b => !taken.has(b)) || null;
  }

  /** Can the player see this point? The camera is seventy-two degrees
   *  vertical on a wide frame, which is a hundred across; this asks a
   *  degree or two wider than that, because a vehicle appearing at the
   *  very edge of the frame is a vehicle appearing. No wall check —
   *  what is being avoided is the POP, and a van that materialises
   *  behind a wall you are facing is not one. */
  canSee(x, y) {
    const p = this.game.player;
    if (!p || p.dead) return false;
    const a = Math.atan2(y - p.y, x - p.x) - p.angle;
    return Math.abs(Math.atan2(Math.sin(a), Math.cos(a))) < SEE_HALF;
  }

  /** A point `dist` back along a polyline from its end, and the index of
   *  the vertex before it. Pure arithmetic, for the test. */
  static backAlong(way, dist) {
    let d = dist;
    for (let i = way.length - 1; i > 0; i--) {
      const a = way[i - 1], b = way[i];
      const len = Math.hypot(b.x - a.x, b.y - a.y);
      if (d <= len) {
        const f = len ? d / len : 0;
        return { i: i - 1, x: b.x + (a.x - b.x) * f, y: b.y + (a.y - b.y) * f };
      }
      d -= len;
    }
    return { i: 0, x: way[0].x, y: way[0].y };
  }

  /** Where on this road a vehicle coming for you should come into being:
   *  `dist` back from the end of it, and further back while that is
   *  somewhere you are looking. Returns the road, cut short. */
  trimEntry(way, dist, N) {
    if (way.length < 2) return way;
    let want = dist, e = Responders.backAlong(way, want);
    for (let k = 0; k < (N.runInTries || 0) && this.canSee(e.x, e.y); k++) {
      want += N.runInStep || 400;
      const next = Responders.backAlong(way, want);
      if (next.i === e.i && next.x === e.x && next.y === e.y) break;   // the road has run out
      e = next;
    }
    return [{ x: e.x, y: e.y }, ...way.slice(e.i + 1)];
  }

  /** In from one end of the road, round the ring the short way, and in
   *  to the stand. `back` starts it that far further down the road, so
   *  a convoy arrives as a line rather than as one van.
   *
   *  AND IF THEY ARE COMING FOR YOU they do not drive the road at all,
   *  at the user's request. The whole way in is built as it always was
   *  and then CUT SHORT from its far end: they come into being on the
   *  road `runIn` back from wherever they leave it, and further back
   *  than that for as long as the spot is inside your view. The nine
   *  thousand units out to where the road leaves the world are five
   *  seconds of a van nobody can see; inside the building it is
   *  unchanged, because there you are not watching.
   *
   *  THE CUT ONLY EVER TOUCHES THE ROAD. The lead — the last leg, off
   *  the tarmac and in toward you — is appended afterwards and is never
   *  trimmed, or a van would come into being in the middle of the lot.
   *
   *  `sprint` defaults to whether they are chasing, and is an argument
   *  so the two routes can be held against each other. */
  routeTo(stand, side, back = 0, sprint = this.chasing) {
    const lv = this.game.level;
    const routes = lv.swatRoutes;
    if (!routes || !this.ring) return null;
    const N = (this.forces.find(f => f.def.key === 'swat') || { num: SWAT }).num;
    let way = (routes[side] || Object.values(routes)[0]).map(p => ({ x: p.x, y: p.y }));
    if (!sprint && back > 0 && way.length >= 2) {
      const a = way[0], b = way[1];
      const d = Math.hypot(b.x - a.x, b.y - a.y) || 1;
      a.x -= (b.x - a.x) / d * back;
      a.y -= (b.y - a.y) / d * back;
    }
    const join = way[way.length - 1];
    way.push(...this.ringPath(this.ringNearest(join.x, join.y), stand.ring));
    const on = this.ringAt(stand.ring);
    way.push({ x: on.x, y: on.y });
    /* everything so far is road; this is where it is cut short */
    if (sprint) way = this.trimEntry(way, (N.runIn || 0) + back, N);
    for (const q of stand.lead) way.push({ x: q.x, y: q.y });
    const end = way[way.length - 1];
    end.angle = stand.angle;
    /* two points in the same place make a zero-length leg, which the
       driving reads as arrival */
    return way.filter((q, i) => i === 0 || Math.hypot(q.x - way[i - 1].x, q.y - way[i - 1].y) > 1);
  }

  /** Which end of the road they come from: whichever is the shorter
   *  drive to where they are going. The road ends are nine thousand
   *  units out from the ring on either side, so coming in at the wrong
   *  one is half a minute of tarmac and the difference between a
   *  response and an interval. */
  sideFor(ringT) {
    const routes = this.game.level.swatRoutes, R = this.ring;
    let best = Object.keys(routes)[0], bd = Infinity;
    for (const name of Object.keys(routes)) {
      const r = routes[name], e = r[r.length - 1];
      const fwd = ((ringT - this.ringNearest(e.x, e.y)) % R.total + R.total) % R.total;
      const d = Math.min(fwd, R.total - fwd);
      if (d < bd) { bd = d; best = name; }
    }
    return best;
  }

  /** A SEND, nose to tail from the same end of the road — three vans at
   *  the user's request, two APCs because they are half again as wide,
   *  and in both cases as many as the budget still has room for. */
  sendConvoy(f = this.swat) {
    const room = this.vanCapOf(f) - this.liveVansOf(f).length;
    const first = this.freeStand(f);
    if (!first) return [];
    const side = this.sideFor(first.ring);
    this.side++;
    const sent = [];
    for (let k = 0; k < Math.min(f.num.convoy, room); k++) {
      const v = this.sendVan(f, side, k * f.num.convoyGap);
      if (!v) break;
      sent.push(v);
    }
    return sent;
  }

  sendVan(f = this.swat, side = (this.side++ % 2 ? 'east' : 'west'), back = 0) {
    const g = this.game;
    const model = this.modelFor(f);
    if (!model) return null;
    const stand = this.freeStand(f);
    if (!stand) return null;
    const route = this.routeTo(stand, side, back);
    if (!route) return null;
    const v = new f.def.Van(g.vehicles, model.def, model.texture, route);
    v.parkAngle = route[route.length - 1].angle;
    v.stand = stand;
    v.bay = stand.bay || null;
    v.side = side;
    v.force = f;
    g.vehicles.addVehicle(v);
    this.vans.push(v);
    g.onResponders?.('van', v);
    return v;
  }

  /** One trooper out of the side door, if there is room to stand. Tries
   *  the five places along the flank before giving up for this tic. */
  unload(v, f = v.force || this.swat) {
    const g = this.game, lv = g.level;
    /* THE DOOR THEY USE IS THE ONE FACING YOU. It used to be the one
       facing the shop, which was the same thing while the only place a
       van ever stood was across the fire lane; a van that has driven
       out into the lot to reach you would otherwise unload its crew
       out of the far side. */
    const p = g.player;
    const toward = p && !p.dead ? { x: p.x, y: p.y } : { x: v.x, y: v.y + 1000 };
    for (let k = 0; k < 5; k++) {
      const d = v.door(k, toward);
      const sec = lv.sectorAt(d.x, d.y);
      if (!sec) continue;
      if (!this.roomAt(d.x, d.y, 20)) continue;
      const a = g.spawn(f.def.troop, d.x, d.y, undefined, { angle: d.angle });
      /* they know why they are here: the player, from the first step */
      a.target = g.player;
      a.threshold = 0;
      a.setState(a.info.see);
      a.van = v;
      a.force = f;
      f.spawned++;
      g.sound?.play(a.info.seeSound, a);
      return a;
    }
    return null;
  }

  /** Nothing solid within `r` of a point, and the player is not there. */
  roomAt(x, y, r) {
    const g = this.game;
    const list = g.blockmap ? g.blockmap.near(x, y, this._near || (this._near = [])) : g.actors;
    for (let i = 0; i < list.length; i++) {
      const o = list[i];
      if (o.removed || !o.solid || o.dead) continue;
      const rr = r + o.radius;
      if ((o.x - x) ** 2 + (o.y - y) ** 2 < rr * rr) return false;
    }
    const p = g.player;
    if (p && !p.dead && (p.x - x) ** 2 + (p.y - y) ** 2 < (r + p.radius) ** 2) return false;
    return true;
  }
}
