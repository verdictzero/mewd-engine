/* =====================================================================
   MEWD — actors: the state machine, and Doom's chase
   =====================================================================

   An actor is a position, a state, and a countdown. Every tic the
   countdown drops by one; when it hits zero the actor moves to the next
   state, which sets a new sprite frame, a new countdown, and calls one
   action function. Everything a monster does happens inside an action
   function called from a state, which is why Doom monsters can be
   interrupted but never caught halfway through a decision.

   THE CHASE is P_NewChaseDir, reproduced closely, because it is the
   single most important forty lines in the game and nothing simpler
   behaves like it. A monster does not path-find. It picks whichever of
   eight compass directions points most nearly at you, tries to walk that
   way, and if it cannot, works through the others in a randomised order
   until something gives. What comes out of that is a thing that
   confidently walks into a shelf, hesitates, slides along it, finds the
   end and comes round — with no graph, no nodes, and no map data at all.

   The refusal to turn round unless there is nothing else left
   (`turnaround` is tried last, always) is what stops monsters
   oscillating in a doorway, and is the detail most reimplementations
   drop.

   NOTHING CHASES YOU YET. The two staff monsters that used to are gone
   and the responders that will are not written, so at the moment every
   line about the chase below runs for nobody. It stays exactly as it is,
   for two reasons: it is correct, and getting it correct a second time
   from the same source would take longer than reading it does. When a
   fire crew walks up the road it will walk on this.

   BURNING is this game's own addition and it is deliberately not a
   status effect on a health bar. Anything alight takes damage on a
   timer and LIGHTS WHAT IT IS STANDING ON, so a shopper who catches at
   the end of an aisle does more damage to the store than the shot that
   lit them.
   ===================================================================== */

import { STATES, ACTORS, stateOf } from './states.js';
import { angleNorm, angleDiff, pRandom, dist, dist2 } from './util.js';
import { swayOf } from './people.js';
import { climate } from './weather.js';
import { world } from './material.js';
import { tweenLook } from './sectorgrid.js';

/* Doom's eight, in Doom's order. Index 8 is "nowhere to go". */
export const DI = { EAST: 0, NORTHEAST: 1, NORTH: 2, NORTHWEST: 3, WEST: 4, SOUTHWEST: 5, SOUTH: 6, SOUTHEAST: 7, NODIR: 8 };
const DIR_ANGLE = [0, Math.PI / 4, Math.PI / 2, 3 * Math.PI / 4, Math.PI, -3 * Math.PI / 4, -Math.PI / 2, -Math.PI / 4];
const OPPOSITE = [DI.WEST, DI.SOUTHWEST, DI.SOUTH, DI.SOUTHEAST, DI.EAST, DI.NORTHEAST, DI.NORTH, DI.NORTHWEST, DI.NODIR];
const DIAGONALS = [DI.NORTHWEST, DI.NORTHEAST, DI.SOUTHWEST, DI.SOUTHEAST];

let nextId = 1;

/* =====================================================================
   THE BLOCKMAP, for the crowd

   Doom kept one of these and this game did not, because for a hundred
   and twenty actors a scan of the list is faster than a hash lookup and
   the honest thing is the simple thing. At eight hundred it is not: a
   crowd deciding where to step asks "is anybody standing there" once per
   candidate direction per actor, which against a flat list is the crowd
   squared, and the crowd squared is what stopped the last increase from
   going further.

   So: a hash of cells 128 units across, holding every actor that was
   ever solid. `near` visits the nine cells around a point, which for a
   query radius under a cell is every actor that could possibly overlap
   and no more.

   ONLY THE POSITION HAS TO BE RIGHT. Whether an actor is still solid,
   still alive and still in the world changes in a dozen places — a
   corpse stops being solid, a splat is taken away when the cap is
   reached — and threading grid maintenance through all of them is how
   you get a crowd that can walk through a body one time in a thousand.
   Instead a thing that has stopped being solid stays in the grid and the
   CALLER filters it, exactly as it filtered the flat list. The waste is
   a handful of entries per cell; the guarantee is that the grid can
   never disagree with the world about who is where.
   ===================================================================== */
const BM_CELL = 128;

export class ActorGrid {
  constructor() { this.cells = new Map(); }

  key(x, y) { return (Math.floor(x / BM_CELL) * 4093) ^ Math.floor(y / BM_CELL); }

  add(a) {
    a._bmKey = this.key(a.x, a.y);
    let b = this.cells.get(a._bmKey);
    if (!b) this.cells.set(a._bmKey, b = []);
    b.push(a);
  }

  remove(a) {
    const b = this.cells.get(a._bmKey);
    if (!b) return;
    const i = b.indexOf(a);
    if (i >= 0) b.splice(i, 1);
  }

  /** Called every time something in the grid moves. A move that stays in
   *  the same cell — which most steps are, a step being sixteen units
   *  against a cell of a hundred and twenty-eight — costs one hash. */
  moved(a) {
    const k = this.key(a.x, a.y);
    if (k === a._bmKey) return;
    this.remove(a);
    this.add(a);
  }

  /** Every actor in the nine cells around (x, y). Not a radius test:
   *  the caller is going to test the distance anyway, and a cell is
   *  wider than any radius that asks. */
  near(x, y, out) {
    out.length = 0;
    const gx = Math.floor(x / BM_CELL), gy = Math.floor(y / BM_CELL);
    for (let j = -1; j <= 1; j++)
      for (let i = -1; i <= 1; i++) {
        const b = this.cells.get(((gx + i) * 4093) ^ (gy + j));
        if (b) for (let k = 0; k < b.length; k++) out.push(b[k]);
      }
    return out;
  }

  /** The same, for something that reaches further than a cell — the
   *  circle a fireball clears, say. Rings out to cover the radius. */
  nearRadius(x, y, r, out) {
    out.length = 0;
    const n = Math.ceil(r / BM_CELL);
    const gx = Math.floor(x / BM_CELL), gy = Math.floor(y / BM_CELL);
    for (let j = -n; j <= n; j++)
      for (let i = -n; i <= n; i++) {
        const b = this.cells.get(((gx + i) * 4093) ^ (gy + j));
        if (b) for (let k = 0; k < b.length; k++) out.push(b[k]);
      }
    return out;
  }
}

/* One scratch array, because `near` is called eight times per fleeing
   shopper per step and a fresh array each time is the garbage a
   fixed-tic loop can least afford. Never held across a call. */
const _near = [];
const _catch = [];
/* and one for A_Flee's eight direction scores, for the same reason */
const _score = new Float64Array(8);

/* HOW FAR A THING IS DRAWN FROM, how far off the view axis, and how
   close is too close to bother asking. See the note on Actor.render. */
/* and never past the air: whatever the weather lets you see is the
   most anybody is drawn at — see climate.airFar in js/weather.js */
const CULL_FAR = 6400;
const CULL_NEAR = 96;
const CULL_COS = Math.cos(80 * Math.PI / 180);

export class Actor {
  constructor(game, typeName, x, y, angle = 0, opts = {}) {
    const info = ACTORS[typeName];
    if (!info) throw new Error('no such actor type: ' + typeName);

    this.id = nextId++;
    this.game = game;
    this.type = typeName;
    this.info = info;
    this.x = x; this.y = y; this.z = 0;
    this.angle = angle;
    this.momx = 0; this.momy = 0; this.momz = 0;

    /* A thing may be given its own size at spawn time. Nothing did
       until the car park filled up: the fleet is six vehicles of five
       different widths, and one radius in a table cannot be all of
       them. */
    this.radius = opts.radius ?? info.radius ?? 16;
    this.height = opts.height ?? info.height ?? 56;
    this.health = info.health ?? 1000;
    this.speed = info.speed ?? 0;
    this.mass = info.mass ?? 100;

    this.monster = !!info.monster;
    this.solid = info.solid ?? !!info.monster;
    this.shootable = info.shootable ?? !!info.monster;
    this.noclip = !!info.noclip;
    /* FIREPROOF is the stronger word and wins: a thing that fire does
       nothing to is not also a thing that catches. See damage(),
       ignite() and frostTic() for the three places it is asked. */
    this.fireproof = !!info.fireproof;
    this.flammable = !!info.flammable && !this.fireproof;
    this.fuel = this.fireproof ? 0 : (info.fuel ?? 0);
    this.flat = !!info.flat;

    this.target = null;
    this.threshold = 0;
    this.reactiontime = info.reaction ?? 0;
    this.movedir = DI.NODIR;
    this.movecount = 0;
    this.justAttacked = false;
    this.dead = false;
    this.removed = false;

    /* running away — see A_Watch, A_PickExit and A_Flee */
    this.panic = 0;              // tics left frightened
    this.fleeX = 0; this.fleeY = 0;
    /* which way out, and when to think about it again */
    this.exitX = null; this.exitY = null; this.exitTic = 0;

    /* fire */
    this.burning = 0;            // tics left alight
    this.burnTick = 0;
    this.catchTick = 0;          // see setAlight
    /* How long something that catches fire has left before it goes off.
       Only things with a `burn` state have one — see ignite() — and
       while it is running they are immune to more fire, because what is
       killing them has already been decided. */
    this.torch = 0;
    this.burnSprite = null;

    /* cold — see chill(), freeze() and shatter() */
    this.frost = 0;              // 0 to FREEZE_AT, and solid at the top
    this.frozen = false;
    this.thawTick = 0;
    /* being eaten by the fire — see burnAway(), and the `ash` uniform in
       js/material.js, which is the whole of what it looks like */
    this.lit = 0;                // 0 to 1, how engulfed — the sprite's own fire
    this.ash = 0;                // 0 to 1, and gone at the top
    this.ashTics = 0;            // how long the whole of it takes, rolled
    this.ashBy = null;           // who gets the kill when it finishes
    /* and with a drill in the head — see bore(), and js/bore.js */
    this.bored = 0;              // tics of it left, and held while any are
    this.boredBy = null;

    this.variant = opts.variant ?? 0;
    this.spriteOverride = opts.sprite || null;

    this.sector = game.level.sectorAt(x, y);
    /* WHICH STOREY, for the places that have more than one. `z` may
       have been handed in (a thing on a landing); the span under it is
       what the actor stands on, and for the thousand columns of one in
       the store it is the sector itself. */
    if (this.sector && opts.z !== undefined) this.sector = game.level.spanIn(this.sector, opts.z);
    this.z = this.sector ? this.sector.floor : 0;
    /* things that hang measure down from the ceiling, not up from the
       floor — a light over a shelf is at the same height as one over the
       aisle beside it, and the shelf's floor is 80 units higher */
    if (info.hangBelow && this.sector) this.z = this.sector.ceil - info.hangBelow;

    this.state = null;
    this.stateTics = 0;
    /* A thing with no spawn state never has one: it is a MODEL, drawn by
       something that is not the sprite bank, and the actor exists for its
       radius. Everything downstream tests `state` and stops. */
    if (info.spawn) this.setState(info.spawn);

    /* WHAT IT DREW LAST FRAME, and not a mesh. An actor used to own a
       Mesh and a ShaderMaterial; it hands its numbers to the batcher
       instead — see js/standees.js — so what is kept here is only what
       something else might ask about: whether it was drawn, and where
       the quad went, in renderer coordinates. */
    this.drawn = false;
    this.drawX = 0; this.drawY = 0; this.drawZ = 0;
    this._lastKey = '';

    /* into the blockmap, if it is the kind of thing anybody has to walk
       round. Solidity can be lost later — see the note on ActorGrid — and
       losing it does not take the entry out. */
    this._bmKey = 0;
    if (info.solid || info.monster) game.blockmap?.add(this);
  }

  /* ------------------------------------------------------------------
     The state machine
     ------------------------------------------------------------------ */
  setState(name, force = false) {
    /* ICE TAKES NO DIRECTION, and this line is where that is true rather
       than merely intended. freeze() parks the state with tics -1, but
       parking it only stops the actor from moving ITSELF — setState is
       the door every other system in the game reaches in through, and
       all of them were walking straight past a block of ice and setting
       it running. A car went up forty units away (Game.scare), or the
       player pulled a trigger anywhere in earshot (Game.noise), and the
       frozen shopper stood up and covered ninety units in under two
       seconds, still solid, still blue, still with ninety frost on.
       Nobody wrote that; it is what a hold with no lock on it does.

       So the lock is here, at the one door, and not a guard sprinkled
       over the callers — because the callers are not the problem. The
       NEXT caller is. Anything that ever wants a frozen thing to react
       gets the same answer, and the two functions allowed to overrule it
       are the two that own the ice: freeze(), parking them, and thaw(),
       letting them go.

       A chain of zero-tic states resolves in one go, the way Doom's
       P_SetMobjState does — that is how a state can be a pure action
       with no frame of its own. The counter stops an accidental cycle
       from locking the game up. */
    if (this.held && !force) return false;
    let guard = 0;
    while (name) {
      const st = stateOf(name);
      if (!st) { this.remove(); return false; }
      this.state = st;
      this.stateTics = st.tics;
      if (st.action) this.doAction(st.action);
      if (this.removed) return false;
      if (st.tics !== 0) return true;
      name = st.next;
      if (++guard > 64) { console.warn('state loop at', st.name); return true; }
    }
    this.remove();
    return false;
  }

  /** NOT AVAILABLE TO BE TOLD TO DO ANYTHING. Two states qualify and
   *  they are the two the fire and the cold put people in: inside the
   *  ice, and being eaten. Both are things that HAPPEN to somebody over
   *  several seconds, and both are ruined by a system deciding halfway
   *  through that this person should now be running for a door. It is
   *  one getter and not two checks because the next such state should
   *  be added here rather than in the four places that ask. */
  get held() { return this.frozen || this.ash > 0 || this.bored > 0; }

  tic() {
    if (this.removed || !this.state) return;
    /* somebody on another machine, drawn here — js/net/remote.js moves
       it, and nothing in this file may */
    if (this.puppet) return;
    if (this.burning > 0) this.burnTic();
    if (this.frost > 0) this.frostTic();
    if (this.bored > 0) this.boreTic();
    if (this.removed) return;
    if (this.stateTics === -1) return;          // resting for ever
    if (--this.stateTics > 0) return;
    /* FORCED, because this is the actor's OWN animation running on and
       not another system directing it. The gate in setState refuses
       everything while a thing is held (see `held`), and a person being
       eaten by the fire is held — so without the flag here SHOP_ASH1
       could never reach SHOP_ASH2 and the burn stopped on its first
       frame. A frozen thing never reaches this line at all: its state
       rests for ever and the check above returns. */
    if (this.state.next) this.setState(this.state.next, true);
    else this.remove();
  }

  doAction(name) {
    const fn = ACTIONS[name];
    if (fn) fn(this);
    else console.warn('no action', name);
  }

  remove() {
    if (this.removed) return;
    this.removed = true;
    this.game.blockmap?.remove(this);
    this.drawn = false;
    if (this.burnSprite) { this.burnSprite.remove(); this.burnSprite = null; }
  }

  /* ------------------------------------------------------------------
     Moving
     ------------------------------------------------------------------ */
  get eyeZ() { return this.z + this.height * 0.72; }

  /** Try to walk `speed` units in the current movedir. Doom's P_TryWalk:
   *  either the whole step happens or none of it does — no sliding for
   *  monsters, because sliding is what lets them ooze through gaps a
   *  player could not. */
  tryWalk(dir = this.movedir) {
    if (dir === DI.NODIR) return false;
    const a = DIR_ANGLE[dir];
    const nx = this.x + Math.cos(a) * this.speed;
    const ny = this.y + Math.sin(a) * this.speed;
    if (!this.canStandAt(nx, ny)) return false;
    this.x = nx; this.y = ny;
    this.game.blockmap?.moved(this);
    this.updateSector();
    /* Doom re-randomises movecount here, which is why a monster commits
       to a direction for a while instead of jittering every tic. */
    this.movecount = pRandom() & 15;
    return true;
  }

  canStandAt(nx, ny) {
    const lv = this.game.level;
    const [rx, ry, hit] = lv.slideMove(this.x, this.y, nx - this.x, ny - this.y, this.radius, this.z, this.height, true);
    if (hit || Math.abs(rx - nx) > 0.01 || Math.abs(ry - ny) > 0.01) return false;
    if (this.game.forest && this.game.forest.blocks(nx, ny, this.radius)) return false;
    /* and nothing solid already standing there. Nine cells of blockmap
       rather than the whole cast — see ActorGrid, and the note there
       about why the flags are still tested here. */
    const bm = this.game.blockmap;
    const list = bm ? bm.near(nx, ny, _near) : this.game.actors;
    for (let i = 0; i < list.length; i++) {
      const o = list[i];
      if (o === this || o.removed || !o.solid || o.dead) continue;
      const rr = this.radius + o.radius;
      if (dist2(nx, ny, o.x, o.y) < rr * rr) return false;
    }
    if (this.game.player && !this.game.player.dead) {
      const p = this.game.player;
      const rr = this.radius + p.radius;
      if (dist2(nx, ny, p.x, p.y) < rr * rr) return false;
    }
    return true;
  }

  updateSector() {
    const lv = this.game.level;
    const g = lv.sectorAt(this.x, this.y, this.sector);
    if (!g) return;
    /* the storey under the feet, not the ground under the building */
    const s = g.above === null ? g : lv.spanIn(g, this.z, this.x, this.y);
    this.sector = s; this.z = lv.floorAt(s, this.x, this.y);
  }

  /** Doom's P_NewChaseDir. See the note at the top of the file. */
  newChaseDir() {
    const target = this.target;
    if (!target) { this.movedir = DI.NODIR; return; }
    const olddir = this.movedir;
    const turnaround = OPPOSITE[olddir];

    const dx = target.x - this.x;
    const dy = target.y - this.y;

    let d1 = dx > 10 ? DI.EAST : dx < -10 ? DI.WEST : DI.NODIR;
    let d2 = dy < -10 ? DI.SOUTH : dy > 10 ? DI.NORTH : DI.NODIR;

    /* straight at it, diagonally, if both axes want to move */
    if (d1 !== DI.NODIR && d2 !== DI.NODIR) {
      this.movedir = DIAGONALS[((dy < 0) ? 2 : 0) + ((dx > 0) ? 1 : 0)];
      if (this.movedir !== turnaround && this.tryWalk()) return;
    }

    /* otherwise the bigger axis first — usually. The dice are Doom's:
       one time in five it tries the shorter axis first, which is what
       stops a room full of monsters all taking the same route. */
    if (pRandom() > 200 || Math.abs(dy) > Math.abs(dx)) { const t = d1; d1 = d2; d2 = t; }
    if (d1 === turnaround) d1 = DI.NODIR;
    if (d2 === turnaround) d2 = DI.NODIR;

    if (d1 !== DI.NODIR) { this.movedir = d1; if (this.tryWalk()) return; }
    if (d2 !== DI.NODIR) { this.movedir = d2; if (this.tryWalk()) return; }

    /* nothing obvious left: work round the compass, from a random end */
    if (pRandom() & 1) {
      for (let dir = DI.EAST; dir <= DI.SOUTHEAST; dir++)
        if (dir !== turnaround) { this.movedir = dir; if (this.tryWalk()) return; }
    } else {
      for (let dir = DI.SOUTHEAST; dir >= DI.EAST; dir--)
        if (dir !== turnaround) { this.movedir = dir; if (this.tryWalk()) return; }
    }

    /* and only now, give up and turn round */
    if (turnaround !== DI.NODIR) { this.movedir = turnaround; if (this.tryWalk()) return; }
    this.movedir = DI.NODIR;
  }

  /* ------------------------------------------------------------------
     Seeing and hitting
     ------------------------------------------------------------------ */
  canSee(other) {
    if (!other) return false;
    return !this.game.level.sightBlocked(this.x, this.y, this.eyeZ, other.x, other.y, other.eyeZ);
  }

  /** Doom's 180-degree cone, plus the "or it is right on top of me"
   *  escape that stops you sneaking up on something you are touching. */
  inSightCone(other) {
    if (dist2(this.x, this.y, other.x, other.y) < 128 * 128) return true;
    const a = Math.atan2(other.y - this.y, other.x - this.x);
    return Math.abs(angleDiff(a, this.angle)) <= Math.PI / 2;
  }

  checkMeleeRange() {
    const t = this.target;
    if (!t || !this.info.meleeRange) return false;
    const r = this.info.meleeRange + t.radius;
    if (dist2(this.x, this.y, t.x, t.y) > r * r) return false;
    return this.canSee(t);
  }

  /** Doom's P_CheckMissileRange, simplified but keeping the two bits
   *  that matter: closer means more likely, and there is a floor on how
   *  often it can fire at all. */
  checkMissileRange() {
    const t = this.target;
    if (!t || !this.canSee(t)) return false;
    let d = dist(this.x, this.y, t.x, t.y) - 64;
    if (!this.info.melee && d > 200) d = 200;      // ranged-only pushes harder
    if (d > (this.info.missileRange ?? 1600)) return false;
    /* one roll in 256 scaled by distance: point blank is a near
       certainty, across the shop floor is a maybe */
    return pRandom() >= Math.min(200, d / 8);
  }

  damage(amount, source, opts = {}) {
    if (this.dead || this.removed || !this.shootable) return;
    /* FROZEN AND THEN HIT IS NOT A HIT. Whatever it was — a boxcutter, a
       car going up next to them, one unlucky particle — a person who is
       a block of ice comes apart entirely, and the amount does not enter
       into it.

       FIRE IS THE EXCEPTION, AND THE EXCEPTION IS THIS BLOCK. It is
       spent MELTING, at twice its damage, and none of it reaches the
       person until the ice is gone — which is the only reason the `burn
       them` row above is true rather than merely written down. It used
       to say fire was a thaw and then not do it: ignite() took frost
       off, but the damage arriving in the same call went straight
       through the ice into a shopper's twelve health, so the SECOND
       flame particle killed them with 44 of their 100 frost still on.
       They never thawed and never got up — and because dying runs the
       ordinary death state they came apart into BURNING giblets, which
       trail fire through the air and light the floor where they land.
       The cold chunks got their own pool to stop precisely that; this
       was the same bug wearing the other door.

       A blast carries enough to take the whole bar off at once, so a car
       going up beside a block of ice frees whoever is in it and then
       lights them, which is the correct amount of mercy. */
    if (this.frozen) {
      if (!opts.fire) { this.shatter(source, opts); return; }
      /* FIRE ON A FIREPROOF BLOCK OF ICE IS A THAW — the one place in
         the game fire is. Nothing inside can be eaten, so the fire is
         spent on the ice at twice its damage, which is the old melt
         rule the paragraph above describes, kept for the one kind of
         person it is right for. Freeze a trooper and the flamethrower
         lets him out; the bore or a blow is what finishes him. */
      if (this.fireproof) {
        this.frost = Math.max(0, this.frost - amount * 2);
        if (this.frost <= 0) this.thaw();
        return;
      }
      this.burnAway(source);
      return;
    }
    /* FIREPROOF, and fire is the whole of what the flag refuses: the
       stream, the floor, a blast, a torch running past. A bullet, a
       van and the bore are not fire and land as they always did. The
       SWAT wear it (see js/states.js), and it is why the flamethrower
       is not the answer to them. */
    if (opts.fire && this.fireproof) return;
    /* AND ONCE THE FIRE HAS THEM, NOTHING HURRIES IT. More fire on
       somebody already being eaten does nothing — the clock in
       A_BurnAway is the only thing that ends it, the same bargain
       A_Torch makes — but a BLOW still lands, and what a blow does to a
       body that is half ash is finish it where it stands. */
    if (this.ash > 0) {
      if (!opts.fire) this.collapse(source);
      return;
    }
    /* ALREADY ON FIRE IS ALREADY DEAD, and more fire does not hurry it.
       Something with a `burn` state has a clock running the moment it
       catches (see ignite), and that clock is the only thing that ends
       it — otherwise the stream that lit them kills them in the same
       tenth of a second it always did and nobody ever runs anywhere.
       Everything that is not fire still lands: a boxcutter through
       somebody who is alight still drops them. */
    if (opts.fire && this.torch > 0) return;
    /* THREE CYLINDERS ARE ONE VAN. A vehicle is too long to be one of
       Doom's things, so it is three of them in a row (see carBlockers),
       and a shot into any third of it is a shot into the vehicle — the
       health lives there, not here, or a van would take three times as
       much punishment as it should and come apart in thirds. */
    if (this.vehicle) { this.vehicle.damage(amount, source, opts); return; }
    /* A ROUND FROM YOUR OWN SIDE DOES NOTHING — see the note on `team`
       below, which is where the reasoning is, and which is above the
       line that used to be the whole of that rule. It has to be HERE
       rather than down there, because down there the health has already
       come off. */
    const friendly = source && source.info && this.info.team && source.info.team === this.info.team;
    if (friendly && opts.shot) return;
    this.health -= amount;

    if (this.health <= 0) { this.die(source, amount, opts); return; }

    /* Being shot makes a monster look at whoever did it, unless it is
       already very cross with somebody else.

       OR UNLESS IT WAS ONE OF ITS OWN. Doom's monsters infight — a
       stray shot from the one behind and the two of them are at each
       other — and for a bestiary that is the best thing in the game.
       For a squad it is the wrong thing: a line of troopers coming down
       an aisle at you would turn on itself the first time the rear rank
       fired through the front, and the player would stand and watch.
       AND SINCE THE ARMY CAME IT IS NOT A HIT EITHER, for a bullet. Two
       forces on the same ground with the same team name are one side,
       and one side's rifles landing on one side's backs is not a rule,
       it is an accident of the ray walking past: a hundred and forty of
       soldier arriving at twenty because it crossed a fire lane with
       twenty-six troopers shooting down it makes the army tier WEAKER
       than the tier it escalates from. So a round from a team-mate does
       nothing. It is still STOPPED by him — Game.hitscan takes the first
       thing the ray meets, whoever it is, so the man in front is still
       cover and a crowd of them is not a crowd of clear shots — which
       is the half of the old rule that was about the fight rather than
       about the arithmetic. Anything else from a team-mate still counts:
       their own van running them down, their own car going up. */
    if (source && source !== this && !friendly && (!this.target || this.threshold <= 0)) {
      this.target = source;
      this.threshold = 100;
      if (this.state === stateOf(this.info.spawn) && this.info.see) this.setState(this.info.see);
    }
    if (this.info.painchance && pRandom() < this.info.painchance && this.info.pain) {
      this.setState(this.info.pain);
    }
  }

  die(source, overkill = 0, opts = {}) {
    if (this.dead) return;
    /* AND A BLOCK OF ICE THAT IS KILLED COMES APART, which is here for
       the same reason the gate in setState is: damage() already turns a
       blow on a frozen thing into a shatter, so nothing reaches this
       line today. But the gate refuses the death state as readily as it
       refuses a fright, and a corpse that cannot run its death state is
       a block of ice that never gets removed and never stops being
       solid. One line, and the two doors agree. */
    if (this.frozen) { this.shatter(source); return; }
    if (this.ash > 0) { this.collapse(source); return; }
    /* AND THE DRILL IS OVER, whichever way this was reached. The hold
       has to come off here or the gate in setState refuses the death
       state and a corpse with a bore in it stands there for ever. */
    this.bored = 0;
    this.dead = true;
    this.solid = false;
    this.shootable = false;
    this.target = null;
    this.height = 8;                 // you can walk over a body

    /* A CAN OF ACCELERANT GOING UP IN AN AISLE. Small against a
       building — a sixth of what a bay can take — so shooting the cans
       out is a way to start something rather than a way to finish it. */
    if (this.info.explodes) { this.game.explode(this, { structure: 0.17, structureRadius: 190 }); }

    /* OR BLOWN APART, whatever the arithmetic says: a warhead kill
       (opts.gib, from MissileSystem.detonate) takes the gore death every
       time, because a trooper a rocket went off beside does not lie down
       in one piece. */
    const gibbed = this.info.xdeath && (opts.gib || this.health < (this.info.gibHealth ?? -1000));
    const st = gibbed ? this.info.xdeath : this.info.death;
    if (st) this.setState(st);
    else this.remove();

    if (this.monster) this.game.onMonsterKilled(this, source);
    if (this.type === 'LAMP') this.game.onLampDestroyed(this);
  }

  /* ------------------------------------------------------------------
     On fire

     Damage on a timer, a flame drawn on top, and — the part that makes
     it worth having — it keeps setting light to the floor it walks over.
     ------------------------------------------------------------------ */
  ignite(tics = 350) {
    /* AND SOME WORLDS DO NOT BURN AT ALL, at the user's request. The
       grid (js/maps/grid.js) is a place to try guns in: the flamethrower
       still throws flame and it still hurts, because that is the GUN,
       but nothing in the world goes up as a result of it. One flag on
       the map, read here and in Vehicle.ignite, and every source of
       fire in the game is answered at once. */
    /* BUT PEOPLE DO, at the user's request: somebody the flame lands on
       catches, runs, and sets alight whoever they run into, even in a
       world where nothing else goes up. The flag still keeps the floor,
       the wood, the vehicles and the furniture out of it. A person is
       anything with a `burn` state — something that does something with
       being on fire. */
    if (this.game.level.noBurn && !this.info.burn) return;
    /* `flammable` is already false for anything fireproof — see the
       constructor — so a trooper is refused here without a second flag */
    if (!this.flammable || this.removed) return;
    if (this.vehicle) { this.vehicle.ignite(tics); return; }
    /* FIRE ON THE ICE IS NOT A THAW, IT IS AN EXECUTION. This used to
       melt them free: the flame spent itself taking the frost off and
       what came out the other side was a person on fire, running. It
       reads better and plays better the other way round — a block of
       ice the fire reaches stays exactly where it is and is EATEN, and
       collapses into a heap of ash — so the two weapons together are a
       way of taking somebody out of the building quietly, which neither
       of them is on its own. See burnAway. */
    if (this.frozen) { this.burnAway(); return; }
    if (this.ash > 0) return;
    /* PARTIAL FROST IS STILL A COAT OF IT, and fire still spends itself
       on that before it lights anybody: somebody the spray has caught
       but not held takes a particle or two more than a dry one. */
    if (this.frost > 0) {
      this.frost = Math.max(0, this.frost - Actor.FIRE_THAW * 2);
      if (this.frost > 0) return;
      this.thaw();
    }
    const wasAlight = this.burning > 0;
    if (!wasAlight) this.lit = 0;         // the palette ramps in, see burnTic
    this.burning = Math.max(this.burning, tics);
    /* AND SOME THINGS RUN WITH IT. A `burn` state is a thing that does
       not simply stand there and take the damage: it is set alight, it
       is given a countdown, and what it does with the countdown is its
       own business — for a shopper, A_Torch, which is running. The fire
       is made to outlast the countdown so nobody goes out before they go
       off. */
    if (!wasAlight && this.info.burn && !this.dead) {
      const [lo, hi] = this.info.burnTics ?? [120, 240];
      this.torch = Math.round(lo + (pRandom() / 255) * (hi - lo));
      this.burning = Math.max(this.burning, this.torch + 20);
      /* THEIR OWN FRIGHT FIRST, and this order is not cosmetic: the
         scare below reaches everybody in range and A_Scare puts a
         first-time panicker into `info.see`, which for a shopper is the
         ordinary running state. Frighten them before they are in it and
         the burn state is clobbered one line after it was set. Already
         at full panic, A_Scare leaves them alone. */
      this.panic = this.info.panicTics ?? 280;
      this.setState(this.info.burn);
      /* and everybody near them leaves: a person on fire is the loudest
         warning in the building, and it is running towards them */
      if (this.info.burnScare) this.game.scare?.(this.x, this.y, this.info.burnScare);
    }
    if (!wasAlight) {
      this.game.sound?.play('ignite', this);
      /* and anything with a voice uses it */
      if (this.info.painSound) this.game.sound?.play(this.info.painSound, this);
      /* Whatever this thing is worth as fuel goes into the floor under
         it the moment it catches — a pallet of stock alight is a fire in
         the AISLE, not a fire on a prop. */
      if (this.fuel > 0) this.game.fire?.ignite(this.x, this.y, this.fuel);
    }
  }

  /** HOW A FIRE PASSES BETWEEN PEOPLE: checked every CATCH_EVERY tics
   *  while alight, reaching anyone within CATCH_REACH of touching, who
   *  catches with a chance of CATCH_CHANCE in 255 each time. */
  static CATCH_EVERY = 8;
  static CATCH_REACH = 4;
  static CATCH_CHANCE = 64;

  /** Touch everyone near enough with this fire. Returns how many caught. */
  setAlight() {
    const g = this.game;
    const list = g.blockmap ? g.blockmap.near(this.x, this.y, _catch) : g.actors;
    let n = 0;
    for (const o of list) {
      if (o === this || o.removed || o.dead || !o.flammable || !o.info.burn || o.burning > 0 || o.ash > 0 || o.frozen) continue;
      const r = this.radius + o.radius + Actor.CATCH_REACH;
      if (dist2(this.x, this.y, o.x, o.y) > r * r) continue;
      if (Math.abs((o.z ?? 0) - (this.z ?? 0)) > Math.max(this.height, o.height)) continue;
      if (pRandom() >= Actor.CATCH_CHANCE) continue;
      o.ignite();
      if (o.burning > 0) n++;
    }
    return n;
  }

  burnTic() {
    this.burning--;
    if (this.burning <= 0) {
      this.burning = 0; this.lit = 0;
      if (this.burnSprite) { this.burnSprite.remove(); this.burnSprite = null; }
      return;
    }
    /* WHAT BEING ON FIRE LOOKS LIKE, and until this line it looked like
       nothing: a shopper alight was the ordinary drawing turned
       fullbright, with the fire they had dropped on the floor doing all
       of the work. Two halves, and they are deliberately different
       mechanisms — flame licks thrown off the body, which trail behind
       a runner because they are particles and the runner is moving (see
       Effects.bodyFire), and a fire colour map on the drawing itself
       (see `alight` in js/material.js), which is what stops the licks
       reading as a person standing behind a fire.

       THE RAMP IS A THIRD OF A SECOND. Snapping the palette on the tic
       they catch makes a shopper change colour; twelve tics of it reads
       as the fire taking hold of their clothes. */
    this.lit = Math.min(1, this.lit + 1 / 12);
    this.game.fx?.bodyFire(this);
    /* AND IT IS CATCHING, at the user's request: a person on fire sets
       alight whoever they touch — run into, run past, stand against —
       person to person, whether or not the floor under them can burn.
       The fire the floor carries (below) spreads it too, where there is
       one; this is the spread that needs no floor at all. */
    if (!this.dead && ++this.catchTick >= Actor.CATCH_EVERY) {
      this.catchTick = 0;
      this.setAlight();
    }
    /* A TORCH DROPS FIRE MORE OFTEN than a thing standing still burning,
       and for a reason that is arithmetic rather than drama: it is
       moving eight units a tic, so twelve tics between drops is a trail
       with ninety-six-unit holes in it — three cells of a thirty-two
       unit grid, missed. Close the gaps and a burning shopper CARRIES
       the fire across a cross-aisle instead of merely dying on the far
       side of it. */
    const torched = this.torch > 0;
    if (++this.burnTick >= (torched ? this.info.burnTrail ?? 12 : 12)) {
      this.burnTick = 0;
      if (!this.dead) this.damage(this.monster ? 4 : 8, this.game.player, { fire: true });
      /* it drags the fire along behind it, and something that is RUNNING
         drags a line rather than a dot — see burnTrail, burnFuel and
         burnRadius on the actor type for why those three numbers are the
         ones they are. */
      if (torched) this.game.fire?.ignite(this.x, this.y, this.info.burnFuel ?? 26, this.info.burnRadius ?? 1);
      else this.game.fire?.ignite(this.x, this.y, 26);
    }
  }


  /* ------------------------------------------------------------------
     FROZEN

     The other end of the same dial, and it is deliberately NOT the
     mirror image of being on fire. Fire is a countdown somebody else
     started: you catch, you run, you go off, and nothing you or the
     player does in between changes the ending. Cold is a STATE you are
     held in and can come out of — which is the only reason it is worth
     having a second stream in the game at all.

     THREE THINGS CAN HAPPEN TO A FROZEN PERSON and the player picks:

       leave them      the frost bleeds off on its own and they thaw,
                       get up and run, which is the outcome that makes
                       freezing them a DECISION rather than a slower way
                       of killing them
       burn them       fire on ice is an EXECUTION and not a thaw. They
                       stay where they are, the drawing is eaten from
                       the feet up and they collapse into a heap of ash
                       — see burnAway. Standing in a hot cell counts:
                       you do not have to hit them, you have to make it
                       warm
       break them      anything that hits a frozen person shatters them,
                       whole, into bloody frozen chunks

     AND ICE IS SOLID, which is the part that makes this a level-design
     tool as well as a weapon. A frozen shopper stops being something you
     walk through and becomes something you walk around — and so does
     everybody else, including the crowd running for the doors.

     AND IT IS A HOLD, which is the part that makes the list above a
     list. Those three are the ONLY ways out, and they are only the only
     ways out because setState refuses everything else for as long as
     the ice is on — see the note there. A fright, a bang, the noise of
     the player's own gun: a system that makes people react does not get
     to make this one react, or "frozen" is a tint and a pause rather
     than a state you put somebody in.
     ------------------------------------------------------------------ */

  /** How much cold it takes, and how long the thaw is. Public because
   *  the extinguisher's stream is billed against them. */
  static FREEZE_AT = 100;      // frost units before they go solid
  static THAW_EVERY = 6;       // tics per unit bled back off
  static FIRE_THAW = 14;       // and per tic of fire, which is 84x faster
                               // — a coat of frost, or the ice going off
                               // somebody the fire has already got

  /**
   * Put cold into something. Below the threshold this is just a tint and
   * a slowing; at the threshold it goes solid.
   *
   * Returns true if this was the call that froze it.
   */
  chill(amount) {
    if (this.removed || this.dead || !this.info.freezable) return false;
    /* AND NOT ON SOMEBODY THE FIRE HAS ALREADY GOT. The stream puts a
       burning person OUT — see below, and it is one of the best things
       it does — but a person burning away is not a person with a fire
       on them, it is a person half of whom is ash on the floor, and
       there is no putting that back. Without this the two states could
       both be true at once: blue, and being eaten, and held twice. */
    if (this.ash > 0) return false;
    /* IT PUTS THE FIRE OUT ON THE WAY PAST, which is the obvious thing a
       fire extinguisher does to a person who is alight and the thing
       that would be most annoying if it did not. A torch that is going
       out loses its countdown with it — they were going to explode and
       now they are not. */
    if (this.burning > 0) {
      this.burning = Math.max(0, this.burning - amount * 4);
      this.torch = Math.max(0, this.torch - amount * 4);
      if (this.burning <= 0) {
        this.lit = 0;
        if (this.burnSprite) { this.burnSprite.remove(); this.burnSprite = null; }
      }
    }
    if (this.frozen) { this.frost = Actor.FREEZE_AT; return false; }
    this.frost = Math.min(Actor.FREEZE_AT, this.frost + amount);
    if (this.frost >= Actor.FREEZE_AT) { this.freeze(); return true; }
    return false;
  }

  /**
   * WATER, from the fire brigade's cannon (js/water.js): the fire half of
   * chill() and none of the cold. Somebody alight has `amount` times four
   * tics of it taken off, and their torch fuse with it; nobody freezes.
   * Returns true if this was the call that put them out.
   */
  soak(amount) {
    if (this.removed || this.dead || this.ash > 0 || !(this.burning > 0)) return false;
    this.burning = Math.max(0, this.burning - amount * 4);
    this.torch = Math.max(0, (this.torch || 0) - amount * 4);
    if (this.burning > 0) return false;
    this.lit = 0;
    if (this.burnSprite) { this.burnSprite.remove(); this.burnSprite = null; }
    return true;
  }

  freeze() {
    if (this.frozen || this.removed || this.dead) return;
    this.frozen = true;
    this.frost = Actor.FREEZE_AT;
    this.burning = 0; this.torch = 0; this.lit = 0;
    if (this.burnSprite) { this.burnSprite.remove(); this.burnSprite = null; }
    /* A BLOCK OF ICE IS SOLID whether or not the thing inside it was.
       It also stops thinking: the state is parked with tics -1, which is
       this engine's "rest here for ever", and thawing sets it going
       again from wherever it was. */
    this._thawState = this.info.freezeReturn || this.info.see || this.info.spawn;
    this.solid = true;
    this.panic = 0;
    if (this.info.frozen) this.setState(this.info.frozen, true);
    this.stateTics = -1;
    this.game.sound?.play('freeze', this);
  }

  /** Bleeding the cold back off, once a tic. */
  frostTic() {
    if (this.removed) return;
    /* FIRE WINS, and by a wide margin: the bleed is one unit every six
       tics on its own and FIRE_THAW a tic in the heat. For anybody
       merely CHILLED that is the whole of it — a coat of frost comes
       off in a warm aisle. For anybody solid it is not a thaw at all
       any more; the line below sends them to burnAway instead. */
    const hot = this.game.fire ? this.game.fire.heatAt(this.x, this.y) : 0;
    /* A WARM FLOOR IS STILL FIRE. The fire system lights anything
       standing in a cell over 70 of 255 (see _burnThings), which for
       somebody frozen is burnAway — but this function was taking the
       frost off from a fifth of that, so there was a window between the
       two thresholds where a block of ice standing at the edge of a fire
       melted free instead of being eaten. One rule, at one line: fire on
       ice is an execution however the fire got there. */
    if (this.frozen && hot > 0.2 && !this.fireproof) { this.burnAway(); return; }
    /* (a fireproof one on a hot floor falls through to the line below
       and is simply thawed by it: fire on that ice is a thaw, see
       damage()) */
    if (hot > 0.2 || this.burning > 0) {
      this.frost = Math.max(0, this.frost - Actor.FIRE_THAW * (this.burning > 0 ? 1 : hot));
    } else if (++this.thawTick >= Actor.THAW_EVERY) {
      this.thawTick = 0;
      this.frost--;
    }
    if (this.frost < 0) this.frost = 0;
    /* THEY COME OUT AT NOTHING AND NOT AT THE THRESHOLD, which is the
       difference between being frozen and flickering. Freezing happens
       at FREEZE_AT and thawing at zero, so the state has hysteresis and
       the whole of the frost bar is the time they spend solid — six tics
       a unit is about seventeen seconds. Thawing the moment the number
       dipped under the line, which is what this did first, meant a
       shopper was a block of ice for six tics and then walked off. */
    if (this.frozen && this.frost <= 0) this.thaw();
  }

  /** Out of the ice and back to whatever they were doing, which for a
   *  shopper is running, because being frozen solid is not something you
   *  shrug off and go back to the shelves about. */
  thaw() {
    if (!this.frozen) return;
    this.frozen = false;
    /* A CORPSE THAWS INTO A CORPSE. Nothing reaches this with `dead` set
       today — a shopper's death state removes them on the tic it runs,
       and fire no longer kills anybody who is still frozen — but the
       last line of this function is setState(freezeReturn), and the day
       something freezable has a death animation that lingers, the melt
       would stand the body back up and set it running. Being frozen is
       a state the living come out of; the dead just stop being blue. */
    if (this.dead || this.removed) { this.frost = 0; return; }
    this.solid = this.info.solid ?? !!this.info.monster;
    /* AND THEY COME OUT FRIGHTENED, whatever they went in as — including
       the frights they were held through. Everything that would have
       scared them bounced off the ice (see A_Scare), so without this a
       shopper who was frozen through a stampede would step out of it and
       go back to the shelves. */
    this.panic = this.info.panicTics ?? 280;
    /* SOMETHING HAS TO SAY IT HAPPENED. Freezing has a noise and a
       colour; the melt had neither, so a person the player had put on
       ice simply became a person again between two frames and the
       reheat read as a bug. Same puff the shatter leaves, and a hiss
       that runs the other way from the one that froze them. */
    this.game.fx?.frostPuff?.(this.x, this.y, this.z + this.height * 0.5, 18, 34);
    this.game.sound?.play('thaw', this);
    const st = this._thawState;
    if (st) this.setState(st);
  }

  /** Frozen and then hit: the whole person at once, in pieces. There is
   *  no health left to take off and no death state to run — a thing made
   *  of ice does not fall over, it stops existing in one frame.
   *
   *  `opts` is THE BLOW, and everything in it is passed straight to the
   *  shards: `dx`/`dy` for the way it was swung and `force` for how
   *  hard, so a hammer throws the pieces down the aisle in front of it
   *  rather than in a ring on the floor. Nothing supplies them yet —
   *  see Game.impact, which is the hook a physical weapon calls, and
   *  which is written and tested ahead of the weapon that will use it.
   */
  /* ------------------------------------------------------------------
     BURNING AWAY

     What the fire does to somebody who is still in the ice, and the
     only thing in the game that kills a person slowly enough to watch.

     IT IS NOT A THAW. Fire used to melt a frozen shopper free and set
     them running, which made the flamethrower the counter to the
     extinguisher and made freezing somebody a thing the player could
     undo by mistake. The pair are worth more as a COMBINATION: freeze
     one, burn them, and they are gone where they stood — no fireball,
     no thirteen pieces two aisles away, no stampede. It is the quiet
     way of emptying an aisle, and with the shatter that is now two of
     them, which is what the second weapon was for.

     WHAT IT LOOKS LIKE IS NOT IN THIS FILE. `ash` winds from 0 to 1 and
     the sprite shader eats the drawing with it, from the feet up,
     behind a line of coals — see the ASH block in js/material.js. All
     that happens here is the number, the smoke, and the heap at the
     end. The ice goes in the first half second, so the blue is off them
     well before the fire is through them.

     AND THEY STAY HELD. `held` covers this as well as the ice (see the
     getter), so nothing scares a half-burnt person into running: a body
     being eaten that sets off down the aisle would undo the whole
     effect, and every system that would do it is the same one that used
     to walk frozen people off.
     ------------------------------------------------------------------ */

  /** Fire, arriving on somebody frozen solid. */
  burnAway(source = null) {
    if (this.removed || this.dead || this.ash > 0) return;
    /* nothing that cannot be eaten — and anything freezable that has no
       burn-away state of its own just thaws, which is the old behaviour
       kept for whatever gets frozen next */
    if (!this.info.burnAway) { if (this.frozen) this.thaw(); return; }
    this.frozen = false;             // it is a different hold now
    this.burning = 0; this.torch = 0; this.lit = 0;
    this.ashBy = source || this.game.player;
    const [lo, hi] = this.info.ashTics ?? [105, 158];
    this.ashTics = Math.round(lo + (pRandom() / 255) * (hi - lo));
    this.ash = 0.001;                // held from this instant, not the next
    this.panic = 0;
    this.solid = this.info.solid ?? !!this.info.monster;
    this.setState(this.info.burnAway, true);
    this.game.sound?.play('ignite', this);
    if (this.info.painSound) this.game.sound?.play(this.info.painSound, this);
    /* AND THE BODY IS STILL FUEL. Whatever they are worth goes into the
       floor under them the moment they catch, exactly as it does for
       anybody else who goes up — a person burning in an aisle is how the
       aisle catches, and standing still while it happens does not make
       them less flammable. */
    if (this.fuel > 0) this.game.fire?.ignite(this.x, this.y, this.fuel);
  }

  /** What is left. A heap on the floor, a last breath of smoke, and the
   *  actor gone — no death state, because there is nothing left to
   *  animate and the animation was the three seconds before this. */
  collapse(source = null) {
    if (this.removed) return;
    this.dead = true;
    this.solid = false;
    this.shootable = false;
    const g = this.game;
    g.sound?.play('bodyfall', this);
    g.fx?.puff(this.x, this.y, this.z + 10, 26, 130);
    g.fx?.ember(this.x, this.y, this.z + 6, 8, 0.5);
    g.giblets?.ashPile(this);
    if (this.monster) g.onMonsterKilled(this, source || this.ashBy);
    this.remove();
  }

  shatter(source, opts = {}) {
    if (this.removed) return;
    this.dead = true;
    this.solid = false;
    this.shootable = false;
    this.game.giblets?.shatter(this, opts);
    if (this.monster) this.game.onMonsterKilled(this, source);
    this.remove();
  }

  /* ------------------------------------------------------------------
     A DRILL IN THE HEAD

     The cerebral bore has arrived (js/bore.js), and what happens next
     is the third hold: two seconds of standing exactly where they were,
     shaking, screaming, with what was in their head coming out of the
     top of it — and then they explode. Held for the same reason the
     ice and the burn-away are held: a person with a drill in their
     skull who sets off down the aisle because a car went up is not a
     person with a drill in their skull.

     WHAT IT DOES TO SOMEBODY ALREADY HELD is decided here rather than
     by the bore, because the bore does not know what a block of ice
     is: a frozen person is shattered by it the way anything hitting
     them shatters them, and a person half ash is finished.
     ------------------------------------------------------------------ */
  /** The bore has reached the head. Returns what it did. */
  bore(by = null) {
    if (this.removed || this.dead) return false;
    if (this.frozen) { this.shatter(by, { impact: true, force: 1.4 }); return 'shatter'; }
    if (this.ash > 0) { this.collapse(by); return 'collapse'; }
    if (this.bored > 0) return false;
    this.bored = Actor.BORE_TICS;
    this.boredBy = by || this.game.player;
    this.panic = 0;
    /* parked, the way the ice parks them: no action runs while the
       drill is in, and the drawing shakes instead — see render */
    if (this.info.bored) this.setState(this.info.bored, true);
    this.stateTics = -1;
    if (this.info.painSound) this.game.sound?.play(this.info.painSound, this);
    return 'drill';
  }

  static BORE_TICS = 78;       // a shade over two seconds — js/bore.js's number

  /** One tic with the drill in. Blood out of the top of the head,
   *  pieces of what was in it, and the scream; and at the end of the
   *  count, the burst. */
  boreTic() {
    const g = this.game;
    if (--this.bored > 0) {
      const top = this.z + this.height * 0.9;
      if ((this.bored & 1) === 0) g.giblets?.spurt(this);
      if ((this.bored % 4) === 0) g.fx?.bloodPuff(this.x, this.y, top);
      if ((this.bored % 14) === 0 && this.info.painSound) g.sound?.play(this.info.painSound, this);
      return;
    }
    this.boreBurst();
  }

  /** AND THEN THEY EXPLODE. The same coming-apart the flamethrower gets
   *  — the fireball and the pieces for a shopper, the gore animation for
   *  a trooper — because "explode" already means one thing in this game
   *  and the bore should not teach it a second one. The kill is the
   *  player's, which is what calls the SWAT. */
  boreBurst() {
    const by = this.boredBy;
    this.bored = 0;
    if (this.removed || this.dead) return;
    this.game.giblets?.spurt(this, 10);
    /* far enough under zero that a trooper takes the gore death */
    this.health = Math.min(0, (this.info.gibHealth ?? 0) - 1);
    this.die(by, 100);
  }

  /* ------------------------------------------------------------------
     Drawing

     One quad per actor, spun about Y only, with the frame and rotation
     chosen fresh each render. Nothing is cached across frames because
     both can change every tic and the lookup is a Map hit.
     ------------------------------------------------------------------ */
  /* ------------------------------------------------------------------
     DO NOT DRAW WHAT CANNOT BE SEEN

     Every standee is its own mesh with its own material — it has to be,
     because the quad is spun and scaled by uniforms — so a crowd of
     seven hundred is seven hundred draw calls and seven hundred uniform
     updates a frame. And it was ALL of them, every frame, however far
     away and whether or not they were behind you: these meshes say
     frustumCulled = false, because a quad the shader turns has bounds
     that are a lie, so three.js was not allowed to cull any of them.

     So it is done here, where the lie does not matter, with the two
     tests that are safe for a billboard:

       BEHIND THE EYE. Every sprite in the game is turned to the camera
       PLANE rather than the camera point, so a thing far enough behind
       that plane is edge-on and invisible by construction.

       TOO FAR TO MATTER. Past the end of the parade, and well past
       where the distance falloff has taken a standee to its darkest
       step.

     The cone is deliberately generous — it keeps everything within
     eighty degrees of the view axis, against a horizontal field of
     about forty-eight — because a sprite is as wide as it is and
     popping one in at the edge of the screen is worse than drawing it.
     Even so it is most of the crowd: the half behind you, plus what is
     out to the sides. Anything closer than three metres is never culled
     at all, whatever the angle, because at that range the quad is wider
     than the screen.
     ------------------------------------------------------------------ */
  render(camX, camY, billboardRot, viewX = 0, viewY = 0) {
    if (this.removed || !this.state) return;
    const dx = this.x - camX, dy = this.y - camY;
    const d2 = dx * dx + dy * dy;
    const far = Math.min(CULL_FAR, climate.airFar);
    /* AND NOT IN A REGION THE EYE CANNOT SEE INTO, which is the exact
       test where the cone below is the generous one: the portal flood
       (Level.visibleSectors) has already been run this frame, and a
       standee in the stockroom is not drawn from the car park however
       squarely you face the wall between. */
    const lv = this.game.level;
    if (d2 > far * far ||
        (d2 > CULL_NEAR * CULL_NEAR && this.sector && lv.isVisible && !lv.isVisible(this.sector)) ||
        (d2 > CULL_NEAR * CULL_NEAR && (viewX !== 0 || viewY !== 0) &&
         dx * viewX + dy * viewY < Math.sqrt(d2) * CULL_COS)) {
      this.drawn = false;
      return;
    }

    /* Which of the eight views. rot 0 is head-on. */
    let rot = 0;
    if (!this.flat) {
      const toViewer = Math.atan2(camY - this.y, camX - this.x);
      const rel = angleNorm(this.angle - toViewer);
      rot = ((Math.round(rel / (Math.PI / 4)) % 8) + 8) % 8;
    }

    /* `variants` picks CAR0..CAR4 style sprite sets off one actor type.
       Nothing declares it since the placeholder cars came out; it is left
       standing because it is the hook the real cars will want. */
    const spr = this.spriteOverride || (this.info.variants
      ? this.state.sprite.slice(0, 3) + (this.variant % this.info.variants)
      : this.state.sprite);
    const entry = this.game.sprites.get(spr, this.state.frame);
    const key = entry.key + rot;
    /* THE PICTURE IS THE BATCH. Everything that is drawn from this
       texture goes into one draw call, so the texture is looked up here
       and handed to the batcher with the rest of the numbers — see
       js/standees.js, and the INSTANCED_SPRITE block in js/material.js
       for why none of this changes how it looks. The lookup is cached
       on the frame key the way the uniform write used to be, because
       SpriteBank.texture uploads a rotation the first time it is asked
       and the cache is what stops that being asked every frame. */
    if (key !== this._lastKey) {
      this._lastKey = key;
      this._tex = this.game.sprites.texture(entry, rot);
      const sc = entry.scale;
      this._w = entry.w * sc; this._h = entry.h * sc;
    }
    const fullbright = (this.info.fullbright || this.state.fullbright) ? 1 : 0;
    /* `lit` on the type is a multiplier on the room's light, and one
       thing declares it: the SWAT, whose sheet is navy on black and who
       came out of the van at night as a silhouette with a visor. Doom
       painted its soldiers in browns and pinks for exactly this reason.
       A multiplier alone could not do it — light is applied in LINEAR
       and the navy is two per cent there, so twice it is four — and
       most of the work is a tone curve in tools/prep-swat.mjs; this is
       the last third. */
    const light = (this.sector ? this.sector.light : 0.7) * (this.info.lit || 1);
    /* HOW FROZEN, straight onto the shader that does the colour map.
       It runs up before the threshold as well as at it, so somebody the
       spray has caught but not yet held goes pale and blue first — the
       player can see it working, which is the whole of the feedback this
       weapon has. */
    const frost = Math.min(1, this.frost / Actor.FREEZE_AT);
    /* AND HOW FAR THROUGH BEING EATEN, on the same terms. See the ASH
       block in js/material.js: the sprite is consumed from the feet up
       behind a line of coals, and at 1 there is nothing of it left —
       which is a tenth of a second before collapse() takes the actor
       away, so the drawing is empty rather than popping out. */
    const ash = this.ash;
    /* AND HOW ALIGHT. Same idea as the frost and the same place in the
       shader: a colour MAP rather than a tint, because a person on fire
       is not their own colours with orange light on them. */
    const alight = this.lit;
    /* A car in the back row of the car park has to diminish the way the
       tarmac under it does, or it turns into a silhouette while the bay
       around it stays lit. */
    const sky = this.sector ? (this.sector.sky ?? (this.sector.outdoor ? 1 : 0)) : 0;
    /* A standee leans where it stands, or a shop floor of them is a shop
       floor of cardboard. Two sines, phased off the actor's own id, and
       nothing in the simulation moves — this is a drawing offset and the
       thing itself is exactly where the collision says it is. */
    /* AND A BLOCK OF ICE DOES NOT LEAN. The sway is what stops a shop
       floor of standees reading as cardboard, and it was running on the
       frozen ones too — a statue rocking gently on its heels, which is
       the one drawing in the game that has to be dead still. Somebody
       being eaten by the fire is held the same way and for the same
       reason: a body coming apart should sag, not sway. */
    /* AND SOMEBODY BEING EATEN SETTLES. The front crosses the drawing
       from the feet up and the quad does not move, so what was left of
       a half-burnt shopper HUNG IN THE AIR — a head and a pair of
       shoulders floating at eye level with nothing under them, which
       was the first thing wrong with this on screen. The sprite sinks
       at the rate the front climbs, so the unburnt top of them slides
       down to the floor as the bottom goes: what the eye sees is a
       person collapsing into the heap they are about to become.

       0.72 against the threshold's 0.70, because the noise in it puts
       the average front a little above the pure height ramp. */
    const sink = this.ash > 0 ? this.ash * this.height * 0.72 : 0;
    if (this.info.sway && !this.held) {
      const s = swayOf(this, this.game.tics);
      this.drawX = this.x + s.dx; this.drawY = this.z + (entry.lift || 0) + s.dz; this.drawZ = -(this.y + s.dy);
    } else if (this.bored > 0) {
      /* AND SOMEBODY WITH A DRILL IN THEIR HEAD SHAKES: a couple of
         units either way, fresh every frame, which on a standee reads
         as a fit rather than as a sway. Drawing offset only; the body
         is exactly where the collision says it is. */
      const jx = (pRandom() / 255 - 0.5) * 3.6, jy = (pRandom() / 255 - 0.5) * 3.6;
      this.drawX = this.x + jx; this.drawY = this.z + (entry.lift || 0); this.drawZ = -(this.y + jy);
    } else {
      this.drawX = this.x; this.drawY = this.z + (entry.lift || 0) - sink; this.drawZ = -this.y;
    }
    /* and into the batch for its picture. `drawn` is this actor's own
       decision — it got past the culling and submitted itself — and not
       the batcher's answer, which is about buffer room and is nobody
       else's business. */
    this.drawn = true;
    /* IN A MAP FROM THE EDITOR, its sector's light, colour and fog,
       eased into rather than snapped to as it crosses from one sector to
       the next (tweenLook in js/sectorgrid.js) */
    if (world.sectorOn.value > 0.5) {
      const now = performance.now() / 1000;
      const look = tweenLook(this, this.sector, now - (this._lookAt ?? now));
      this._lookAt = now;
      this.game.standees.add(this._tex, this.drawX, this.drawY, this.drawZ,
                             this._w, this._h, look.light * (this.info.lit || 1), sky, fullbright, frost, ash, alight,
                             this.monster ? 1 : 0, look.tint, look.fog);
      return;
    }
    this.game.standees.add(this._tex, this.drawX, this.drawY, this.drawZ,
                           this._w, this._h, light, sky, fullbright, frost, ash, alight,
                           this.monster ? 1 : 0, this.sector?.tint?.thing || null);
  }
}

/* =====================================================================
   Action functions

   Called by name from the state tables. Each one is the whole of what
   the monster does at that moment.
   ===================================================================== */
export const ACTIONS = {
  /* Standing about until somebody walks into the aisle. */
  A_Look(a) {
    const p = a.game.player;
    if (!p || p.dead) return;
    if (!a.canSee(p)) return;
    if (!a.inSightCone(p)) return;
    if (dist2(a.x, a.y, p.x, p.y) > (a.info.sightRange ?? 2000) ** 2) return;
    a.target = p;
    a.game.sound?.play(a.info.seeSound, a);
    if (a.info.see) a.setState(a.info.see);
  },

  /* The whole of a monster's decision-making, once per walk frame. */
  A_Chase(a) {
    if (a.reactiontime > 0) a.reactiontime--;
    if (a.threshold > 0) {
      if (!a.target || a.target.dead) a.threshold = 0;
      else a.threshold--;
    }

    /* lost it? look for something else, else go back to standing */
    if (!a.target || a.target.dead) {
      const p = a.game.player;
      if (p && !p.dead && a.canSee(p) && dist2(a.x, a.y, p.x, p.y) < (a.info.sightRange ?? 2000) ** 2) {
        a.target = p;
      } else {
        a.setState(a.info.spawn);
        return;
      }
    }

    /* Never twice in a row. Doom's rule, and the reason a monster that
       has just shot at you takes a step before it shoots again — which
       is the window you actually play in. */
    if (a.justAttacked) { a.justAttacked = false; a.newChaseDir(); return; }

    if (a.info.melee && a.checkMeleeRange()) {
      a.game.sound?.play(a.info.attackSound, a);
      a.setState(a.info.melee);
      return;
    }
    if (a.info.missile && !a.movecount && a.checkMissileRange()) {
      a.setState(a.info.missile);
      a.justAttacked = true;
      return;
    }

    if (--a.movecount < 0 || !a.tryWalk()) a.newChaseDir();

    /* the occasional groan from somewhere in the store */
    if (pRandom() < 3) a.game.sound?.play(a.info.activeSound, a);

    /* face the way it is going */
    if (a.movedir !== DI.NODIR) a.angle = DIR_ANGLE[a.movedir];
  },

  A_FaceTarget(a) {
    if (!a.target) return;
    a.angle = Math.atan2(a.target.y - a.y, a.target.x - a.x);
  },

  /* ------------------------------------------------------------------
     THE RIFLE

     Doom's A_PosAttack, near enough: face the target, one shot down
     the eye line with the Zombieman's spread on it, three to fifteen
     off whatever it meets first. The spread is the whole of the
     difficulty — about five and a half degrees either way, which at
     point blank never misses and across the car park mostly does, so
     the answer to a squad of these is distance and the answer to
     distance is that they walk.

     WHAT IT HITS is decided by Game.hitscan, which walks the ray past
     every actor and the player alike; a trooper standing in the line
     of fire is hit by the one behind him and — see the team rule in
     Actor.damage — does not hold it against him. The muzzle flash is
     the drawing's own (the F frame is orange and fullbright); what is
     added here is the light of it on the aisle, through the same glow
     everything else on fire contributes to.
     ------------------------------------------------------------------ */
  A_SwatFire(a) {
    ACTIONS.A_FaceTarget(a);
    const g = a.game;
    g.sound?.play(a.info.attackSound, a);
    const spread = ((pRandom() - pRandom()) / 255) * 0.1;
    const damage = ((pRandom() % 5) + 1) * 3;
    g.hitscan(a, a.angle + spread, 2048, damage, { shot: true });
    g.fx?.muzzle(a);
    a.shots = (a.shots || 0) + 1;
  },

  /* AND THE ARMY'S, WHICH IS THE SAME RIFLE HELD PROPERLY. Two rounds
     off one frame instead of one, four to twenty each instead of three
     to fifteen, and the spread halved — under three degrees either way,
     which across the car park is the difference between being shot at
     and being hit.

     Both rounds go out on the same tic and down the same eye line with
     their own scatter, so at any range the pair is a pair rather than a
     shotgun: at fifty units they both land, at fifteen hundred one of
     them might. The sound is played once, because a burst is one noise
     and the state does not fire again for another twenty-six tics. */
  A_ArmyFire(a) {
    ACTIONS.A_FaceTarget(a);
    const g = a.game;
    g.sound?.play(a.info.attackSound, a);
    for (let k = 0; k < 2; k++) {
      const spread = ((pRandom() - pRandom()) / 255) * 0.05;
      const damage = ((pRandom() % 5) + 1) * 4;
      g.hitscan(a, a.angle + spread, 2048, damage, { shot: true });
    }
    g.fx?.muzzle(a);
    a.shots = (a.shots || 0) + 1;
  },

  /* A person, briefly, becomes thirteen things and a fireball. All of
     it is in js/people.js; this is the one line of state table that sets
     it off. */
  A_Gib(a) { a.game.giblets?.burst(a); },

  /* ------------------------------------------------------------------
     ON FIRE AND STILL GOING

     One call every two tics for as long as the countdown ignite() set
     has left, and then they go off. Three things happen in it and all
     three matter:

     THEY RUN, on A_Flee, which is the same door-seeking walk a
     frightened shopper uses — so somebody alight heads for an exit and
     takes the fire through every cross-aisle on the way rather than
     wandering.

     THEY DO NOT CALM DOWN. The panic is put back every call, which also
     makes them the strongest source of the contagion in A_Watch: a
     burning person running down an aisle empties it, and the people it
     empties carry the fright on.

     AND THEN THEY GO OFF, wherever they got to — health to zero and the
     ordinary death, so it is the same fireball, the same thirteen
     pieces and the same nine hundred units of everybody else leaving
     that the stream used to produce on the spot. The bang is not extra
     code; it is the code that was always there, moved to the end of a
     run rather than the start of one.
     ------------------------------------------------------------------ */
  A_Torch(a) {
    a.panic = Math.max(a.panic, a.info.panicTics ?? 280);
    ACTIONS.A_Flee(a);
    if (a.dead || a.removed) return;
    /* BY THE LENGTH OF THE FRAME, not by one. This runs every two tics,
       so decrementing by one made `burnTics` mean twice what it says and
       a shopper burn for fourteen seconds where the table asked for
       seven. The frame knows how long it is; ask it. */
    a.torch -= a.state.tics;
    if (a.torch > 0) return;
    a.torch = 0;
    a.health = 0;
    a.die(a.game.player, 0, { fire: true });
  },

  /* ------------------------------------------------------------------
     BEING EATEN

     The other end of A_Torch, and deliberately its opposite in every
     respect: no movement, no panic, no trail, no bang. One number goes
     up, the shader eats the drawing with it, and at the top there is a
     heap of ash on the lino.

     BY THE LENGTH OF THE FRAME, not by a fixed step — the same lesson
     A_Torch learned the hard way. This state runs every four tics, so
     stepping the number by a constant would make `ashTics` mean a
     quarter of what it says the day somebody retimes the animation.
     The frame knows how long it is; ask it.
     ------------------------------------------------------------------ */
  A_BurnAway(a) {
    a.ash = Math.min(1, a.ash + a.state.tics / Math.max(1, a.ashTics));
    /* THE ICE GOES FIRST, and much faster than the body does: about
       half a second against three and a half. The blue has to be off
       them well before the fire is through them or the two effects are
       fighting over the same pixels — a pale blue statue with coals
       crawling up it reads as neither. */
    if (a.frost > 0) a.frost = Math.max(0, a.frost - Actor.FIRE_THAW * 2);
    /* AND FLAME ON THEM, at half strength. A body being eaten is on
       fire and has to look it — but on this one the DRAWING is the
       effect, so the licks are kept small enough to sit round the
       burning front rather than hide it. */
    a.game.fx?.bodyFire(a, 0.5);
    if ((pRandom() & 1) === 0)
      a.game.fx?.ember(a.x, a.y, a.z + a.height * a.ash, 1, 0.7);
    if (a.ash >= 1) a.collapse(a.ashBy);
  },

  /* ------------------------------------------------------------------
     RUNNING AWAY

     Standing still and smelling the air. Nine samples of the fire grid —
     where the actor is and eight points round it at its scare range — is
     enough to know both THAT there is a fire and WHICH WAY it is, which
     is the part a single sample cannot give you and the part that
     decides which way to run.
     ------------------------------------------------------------------ */
  A_Watch(a) {
    const g = a.game;
    if (a.burning) { ACTIONS.A_Scare(a, a.x, a.y); return; }
    const F = g.fire;
    if (!F) return;
    const R = a.info.scareRange ?? 320;
    let hot = 0, hx = 0, hy = 0, hw = 0;
    for (let k = 0; k < 9; k++) {
      const ang = (k / 8) * Math.PI * 2;
      const x = k === 8 ? a.x : a.x + Math.cos(ang) * R;
      const y = k === 8 ? a.y : a.y + Math.sin(ang) * R;
      const h = F.heatAt(x, y);
      if (h < 0.22) continue;
      hot++; hx += x * h; hy += y * h; hw += h;
    }
    if (hot) { ACTIONS.A_Scare(a, hx / hw, hy / hw); return; }
    /* AND THEN THE PART THAT IS NOT ABOUT FIRE AT ALL.

       Nine samples of the fire grid is a person who can see flames.
       Nobody in a supermarket finds out about a fire that way: they find
       out because the aisle in front of them is suddenly full of people
       going the other way. Without that, a shop this size behaves as
       hundreds of independent people who each notice at 320 units, and
       the front end stands at the tills while the back of the store
       burns — which is not what a crowd does and, with a fire six times
       faster than it used to be, meant most of them never started
       moving until it was on them.

       So panic is contagious, and it travels at the speed of somebody
       running past you. It borrows the panic it catches — the point
       being run FROM comes across with it, so a stampede goes one way
       rather than each new person choosing afresh from where they happen
       to be standing.

       It cannot start itself: every chain of this ends at somebody who
       actually saw the fire in the loop above, and if the shop is not
       alight there is nothing to catch.

       AND IT HAS TO RUN DOWN, which is the part that took two goes. A
       fright handed on at full strength is a loop: two people in the
       woods four hundred units behind the store, neither of them able to
       see a fire, each renewing the other for the rest of the level —
       which is exactly what happened, six hundred of them, running on
       the spot in the trees. So what is passed on is what is LEFT minus
       a bit, a rumour weakens with every telling, and a chain of it dies
       after about a dozen hops unless somebody along it can actually see
       the fire and start a fresh one. */
    const SEE = 190;                    // near enough to see their face
    const FADE = 24;                    // what a telling costs
    for (const o of g.blockmap.near(a.x, a.y, _near)) {
      if (o === a || o.removed || o.dead || o.panic <= FADE * 2) continue;
      if (dist2(a.x, a.y, o.x, o.y) > SEE * SEE) continue;
      ACTIONS.A_Scare(a, o.fleeX, o.fleeY, o.panic - FADE);
      return;
    }
  },

  /** Frighten one actor, away from a point. Called by A_Watch, and by
   *  anything else that ought to clear a room — see Game.scare.
   *
   *  `tics` is how long the fright lasts and it is only ever passed by
   *  the contagion in A_Watch, which passes LESS than it caught. See
   *  the note there: a fright that is handed on at full strength is a
   *  crowd that never calms down, and the woods behind the store filled
   *  up with six hundred people running on the spot for ever because two
   *  of them could see each other. */
  A_Scare(a, x, y, tics) {
    /* A BLOCK OF ICE DOES NOT HEAR YOU. The gate in setState already
       stops a frozen shopper being set running by this, but stopping it
       there and not here leaves the rest of the call happening to them:
       the pain sound out of a mouth that cannot open, a flee point
       chosen from where they were standing eleven seconds ago, and a
       panic counter ticking down through the hold so that the fright
       has expired by the time they are free to use it. Nothing reaches
       somebody inside the ice, and thaw() hands them a fresh fright on
       the way out — which is the correct one, because what they are
       running from is what is there NOW. */
    if (a.held) return;
    const full = a.info.panicTics ?? 280;
    const want = Math.min(full, tics ?? full);
    if (want <= a.panic) { a.fleeX = x; a.fleeY = y; return; }
    const first = a.panic <= 0;
    a.panic = want;
    a.fleeX = x; a.fleeY = y;
    if (first) {
      a.game.sound?.play(a.info.painSound, a);
      if (a.info.see) a.setState(a.info.see);
      a.exitTic = 0;                 // pick a way out on the next step
    }
  },

  /* ------------------------------------------------------------------
     WHICH WAY OUT

     The map publishes every way out of the building as a point on the
     OUTSIDE of it — six fire exits down the flanks and the two front
     sliders; see level.exits in js/maps/sellwrong.js. This picks one.

     NEAREST IS NOT ENOUGH, and the case that proves it is the one that
     happens most: a fire at the west end of the mid cross-aisle is
     nearest to the west mid exit for everybody standing in it, including
     the people the fire is between. So an exit is charged for being
     close to the thing being run from, and the charge is large enough to
     lose a thousand units of walking — because a longer way out you can
     use beats a shorter one you cannot.

     RE-PICKED ON A TIMER, not every step. The two terms both drift, and
     a shopper who re-decides every step in the region where two exits
     score the same walks on the spot between them. Once a second is
     often enough to notice the aisle ahead has caught, and rare enough
     that the decision holds long enough to act on.
     ------------------------------------------------------------------ */
  A_PickExit(a) {
    const list = a.game.level.exits;
    a.exitTic = 35 + (a.id & 15);
    a.exitX = a.exitY = null;
    if (!list || !list.length) return;
    /* Somebody already outdoors does not need a door. They need to keep
       going, which is what the plain flee below does. */
    if (a.sector && a.sector.outdoor) return;
    let best = null, bestScore = Infinity;
    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      const score = dist(a.x, a.y, e.x, e.y)
                  + Math.max(0, 1400 - dist(e.x, e.y, a.fleeX, a.fleeY)) * 1.6;
      if (score >= bestScore) continue;
      bestScore = score; best = e;
    }
    if (best) { a.exitX = best.x; a.exitY = best.y; }
  },

  /* One step of getting out of here.

     NOT Doom's chase with the sign flipped. P_NewChaseDir walks toward a
     thing and its whole cleverness is about not oscillating in a
     doorway; running away is a different problem, because the thing you
     are running from is a REGION and the wrong step is not a step that
     wastes time, it is a step into the fire. So the eight directions are
     SCORED — how much closer to the way out it gets you, minus how hot
     it is where you would land, minus a little for turning — and the
     best walkable one wins.

     AND THERE IS A WAY OUT NOW, which changed what this function is.
     Running AWAY from a fire in a supermarket takes you to the back of
     the shop and then into a corner, because that is what "away" means
     inside a rectangle with one door in it: the crowd used to pile into
     the frozen aisle and cook. So the target is an EXIT and the fire is
     only a penalty on the step — get further from the flames if you can,
     but get to the door either way. The two behaviours are the same
     eight-way scorer with the sign of one term flipped, which is why
     they are one function and not two.

     GREEDY, AND IT WORKS HERE FOR A REASON WORTH WRITING DOWN. Hill
     climbing toward a point gets stuck in dead ends, and a supermarket
     is nothing but dead ends — except that every aisle in this one runs
     north-south and opens onto a cross-aisle at BOTH ends, and every
     exit sits on a cross-aisle. So from anywhere in an aisle the door is
     never at your own y: moving toward the nearer cross-aisle always
     gets you closer to it, and the aisle you are in is a corridor to
     somewhere rather than a pocket. No graph, no nodes, and eight
     hundred of them cost eight distance calls each. */
  A_Flee(a) {
    const g = a.game, F = g.fire;
    if (--a.panic <= 0 && !a.burning) {
      /* only settle if it is actually clear here */
      if (!F || F.heatAt(a.x, a.y) < 0.15) { a.setState(a.info.spawn); return; }
      a.panic = 35;
    }
    if (--a.exitTic <= 0) ACTIONS.A_PickExit(a);
    /* Toward the door if there is one to head for, away from the fire if
       there is not — which is anybody already outside, and anybody on a
       map that has no exits declared. */
    const out = a.exitX !== null && a.exitX !== undefined;
    const tx = out ? a.exitX : a.fleeX, ty = out ? a.exitY : a.fleeY;
    const sign = out ? -1 : 1;              // closer is better, or further is
    const step = a.speed;
    const d0 = dist(a.x, a.y, tx, ty);
    for (let d = 0; d < 8; d++) {
      const ang = DIR_ANGLE[d];
      const nx = a.x + Math.cos(ang) * step, ny = a.y + Math.sin(ang) * step;
      /* two steps ahead for the heat, so it does not run into a wall of
         fire one step short of noticing it */
      const fx = a.x + Math.cos(ang) * step * 4, fy = a.y + Math.sin(ang) * step * 4;
      let score = (dist(nx, ny, tx, ty) - d0) * 3 * sign;
      if (F) score -= (F.heatAt(nx, ny) * 260 + F.heatAt(fx, fy) * 140);
      if (d === a.movedir) score += 6;                       // keep going
      if (d === OPPOSITE[a.movedir]) score -= 10;            // not straight back
      score += (pRandom() / 255 - 0.5) * 4;
      _score[d] = score;
    }
    /* IN SCORE ORDER, all eight of them. This used to be "the best, then
       a random order over the rest", which is Doom's fallback and is
       right for a monster that has lost sight of you and wrong for
       somebody with a door in mind: the second-best direction at the end
       of an aisle is the one that goes round the gondola, and picking at
       random instead threw that away half the time. A selection sort over
       eight is sixty-four compares and no allocation. */
    for (let k = 0; k < 8; k++) {
      let best = -1, bestScore = -Infinity;
      for (let d = 0; d < 8; d++)
        if (_score[d] > bestScore) { bestScore = _score[d]; best = d; }
      if (best < 0) break;
      _score[best] = -Infinity;
      if (a.tryWalk(best)) { a.movedir = best; return; }
    }
    a.movedir = DI.NODIR;
  },

  A_Pain(a) { a.game.sound?.play(a.info.painSound, a); },
  A_Scream(a) { a.game.sound?.play(a.info.deathSound, a); },
  A_XScream(a) { a.game.sound?.play('gib', a); },

  /* It is on the floor now: no longer solid, no longer in the way. */
  A_Fall(a) {
    a.solid = false;
    a.height = 8;
    a.game.sound?.play('bodyfall', a);
  },
};
