/* =====================================================================
   MEWD — fire
   =====================================================================

   The store burning down is the game. Everything else — the zombies, the
   weapons, the layout — exists to make burning it down interesting. So
   the fire is not an effect painted over the level, it is a simulation
   running underneath it, and the level is built out of things that feed
   it.

   A GRID OF FUEL. Thirty-two units to a cell, laid over the whole map.
   Each cell knows how much there is to burn there, taken from the sector
   it sits in — a shelf of stock is worth a great deal, bare lino almost
   nothing, and the car park nothing at all. Fire spreads between
   neighbouring cells, consumes the fuel, and leaves the cell dead.

   WHAT MAKES IT A GAME AND NOT A SCREENSAVER is that the fuel is laid
   out the way a supermarket is: dense in the aisles, dense in the
   stockroom, and THIN in the walkways between them. So a fire in one
   aisle will happily eat that aisle and then stop at the cross-aisle,
   and burning the place down means deliberately carrying fire across the
   gaps. That is the whole game loop, and it falls out of the map having
   been drawn like a shop.

   WHAT FIRE CAN CROSS. A one-sided line is a wall and stops it dead. A
   two-sided line is a gap in something, and fire goes through gaps —
   under a shelf, over a counter, through a doorway. The only two-sided
   line that stops it is one whose opening has closed, which is to say a
   shut door. Worked out once at startup and stored as four bits a cell,
   because doing it per spread would be thousands of segment
   intersections a second.

   HEAT RISES AND FALLS. A cell that catches does not go instantly to
   maximum; it builds, peaks, and dies back as its fuel runs out. That
   curve is why a fire has a visible FRONT — a bright edge advancing into
   fresh stock with a dimming trail of embers behind it — instead of
   being a uniformly glowing region that grows.
   ===================================================================== */

import * as THREE from 'three';
import { createSpriteMaterial } from './material.js';
import { world } from './material.js';
import { pRandom, pChance, clamp, dist2, TICRATE, pointInPoly } from './util.js';
import { climate } from './weather.js';

const CELL = 32;

/* --------------------------------------------------------------------
   The shape of one cell's life

   Heat runs 0..255. A cell that catches climbs toward a peak, holds
   while it has fuel, and dies back to nothing once the fuel is gone.
   That curve is why a fire has a visible FRONT — a bright edge advancing
   into fresh stock, with a dimming trail of embers behind it — instead
   of being a uniformly glowing region that grows.

   NO FIRE SURVIVES ITSELF, and that is the requirement now. It is a
   statement about percolation rather than about flammability. A fire
   crossing a region carries on only if each burning cell lights, on
   average, MORE THAN ONE new one before it burns out:

     expected spreads  =  tics alight  x  chance  x  neighbours

   Above one, the fire runs away and takes everything connected to it,
   and no player is required. Below one it peters out, and no amount of
   waiting brings it back, because a burnt cell has no fuel left to
   relight. There is no middle setting — it either eventually takes the
   store on its own or it never does.

   IT USED TO BE ABOVE ONE EVERYWHERE, which meant one match anywhere in
   the building took between eighty-five and ninety-four per cent of the
   shop with nobody in it. That was the design and it was asked for, and
   then it was asked for the other way round: a fire the player has to
   WORK at. So every number below is now under the line, and what a fire
   does when you leave it alone is go out.

   What that buys, and it is the whole game loop:

     A MATCH IS A PATCH. One ignition in the richest stock in the
       building takes twenty-odd cells — five metres across — over a
       couple of minutes, and then it is out. Two tenths of one per cent
       of the store.
     A WALKWAY IS A WALL. Bare floor is sixty times less willing to pass
       fire on than a gondola, which puts it so far under the line that
       fire does not cross an aisle at all. The cross-aisles are real
       firebreaks now rather than slow ones.
     THE SHELVES ARE THE FUSE. Dense stock is still the most willing
       thing in the building, so pouring along a run does take the run.
       It simply will not jump to the next one.

   So burning the place down is a job of work: you point the gun at the
   shelving, and the shelving you pointed at is what burns. A full sweep
   of the shop still reaches a hundred per cent, everything charred and
   everything gutted — that was measured, not hoped — but it takes the
   player walking every aisle of it, which is the point.

   The car park is the exception and stays the exception: fuel 0, no
   burning, ever. It is the safe room and the way out.
   ------------------------------------------------------------------ */
/* How often the simulation steps, in game tics. This is the pace
   control, and it is deliberately separate from every other number here.

   Slowing the CLOCK slows the fire without touching the percolation
   maths at all — the expected-spreads-per-cell figure above is counted
   in FIRE tics, so it is identical at any interval. That is what makes
   the two halves of "slower, and it should go out" separable: this
   number decides HOW FAST, and SPREAD_RICH decides HOW FAR. Turn the
   wrong one and you get a fire that is sluggish and still unstoppable,
   or brisk and already over.

   It has been 2, 6, 18 and 3, in that order, each time because somebody
   watched it and said faster or slower. At 2 one match took the whole
   store in 34 seconds and there was nothing for the player to do; at 3
   a run of shelving flashed over while you were still standing in the
   aisle.

   IT IS 10 BECAUSE MUCH SLOWER WAS ASKED FOR THREE TIMES IN ONE
   SENTENCE, and the clock is the honest place to spend that, for the
   reason directly above: the interval buys pace and nothing else. The
   other half of the same request — that a fire should go OUT — is not
   here and cannot be here, because a slower clock makes a runaway fire
   take longer and still take everything. That half is SPREAD_RICH.

   What it feels like: a fire front creeps about one cell every twelve
   seconds through dense stock, where it used to manage six cells a
   second, and a gondola cell rises, roars and is spent in a quarter of a
   minute. The ember tail behind the front is counted in fire tics too,
   so it came UP with the clock and a burnt-out patch sits glowing for
   the better part of a minute before it goes cold — which is what you
   want when the fire is the slow thing: the ground you have taken should
   stay visibly taken while you are off taking the next bit. */
const FIRE_INTERVAL = 10;

const IGNITE_AT   = 55;      // heat a cell starts at when it catches
const PEAK        = 255;
const RISE        = 14;      // heat gained per fire tic while fuelled
const FALL        = 9;       // heat lost per fire tic once the fuel is gone
const SPREAD_AT   = 80;      // heat below which a cell cannot light another

/* Fraction of a cell's ORIGINAL fuel consumed per fire tic at full heat.
   Making it a fraction rather than a flat rate is what gives every cell
   a roughly similar LIFETIME however rich it is — which is what keeps
   thin fuel alight long enough to matter.

   AND THIN FUEL IS SLOWER STILL, so a cell of bare floor smoulders for
   the better part of three minutes while a gondola is spent in a
   quarter of one. That long life used to be what carried fire across a
   walkway — a cell that stays alight gets more rolls to pass itself on,
   and the two terms multiply:

     expected spreads  =  tics alight  x  chance  x  neighbours

   It is deliberately still long, and the chance is what came down
   instead. The floor smoulders for minutes and gets nowhere, which is
   exactly the picture wanted: a fire lying on the lino, visibly alight,
   visibly not going anywhere, until it gives up.

   This is why the fuel arrays are floats. At the old rate a lino cell
   ate `max(1, ...)` of its fifty-five units a tic, and that floor — one
   whole unit, because the array was integers — WAS the burn rate for
   everything thin. Nothing under one could be expressed. */
const BURN_FRAC   = 0.022;
const burnFrac = f0 => BURN_FRAC * (f0 >= 280 ? 1 : 0.22 + 0.78 * (f0 / 280));

/* What is left afterwards.

   A cell whose fuel is spent used to fade to nothing in a couple of
   seconds, so an aisle you had just burnt out looked exactly like an
   aisle nobody had touched — which made the fire feel like an animation
   playing over the level rather than something happening to it. Now it
   drops to a low glow and sits there before going cold, so the ground
   you have taken stays visibly taken.

   In FIRE tics, so what this is in seconds is whatever the clock above
   says: a dozen or so at an interval of 3, and it was a minute and a
   quarter when the interval was 18. That is the right coupling and not
   an accident of units — the glow behind the front should be a fixed
   fraction of the front's own life, or a fast fire leaves a slow scar. */
const EMBER_HEAT = 20;
const EMBER_TICS = 150;

/* How much of a region has to go before its surfaces are swapped for
   charred ones. Below about half it still reads as a shop with a fire in
   it; past that it should read as a shop that HAS burnt. */
const CHAR_AT = 0.5;

/* And how much before it is not a room any more.

   CHARRED IS A SURFACE AND GUTTED IS A STRUCTURE. A charred aisle is the
   same aisle with everything in it blackened; a gutted one has holes
   through the walls with the studs showing, a slab with ash and debris
   on it instead of a floor, and NO ROOF — you are looking at the night
   sky through where the ceiling was. So this is deliberately near the
   end of a region's fuel rather than halfway: everything in it has to
   have burnt, not just most of it, or the store starts losing its roof
   while there is still stock on the shelves.

   0.92 rather than 1.0 because a region's last few cells can be ones a
   wall keeps the fire out of, and waiting for them would mean a store
   that burns to 99% and never falls down. */
const GUT_AT = 0.92;

/* =====================================================================
   AND WHAT IS STILL HOLDING IT UP

   CHARRED IS A SURFACE, GUTTED IS A STRUCTURE, AND COLLAPSED IS NEITHER
   — it is the absence of one. The three stages are the same building
   three times: a shop with everything in it blackened, a shell with the
   deck gone and the steel showing, and then a heap.

   THE THIRD STAGE NEEDED A CLOCK THAT THE FIRST TWO DID NOT. Those two
   run off `sectorBurnt / sectorFuel` — how much of what was in a region
   has gone — and that number saturates at one and stops. A gutted region
   has nothing left to burn, so as far as the old arithmetic is concerned
   nothing further can happen to it, and a burnt-out shed stands for ever.

   Steel does not care how much has burnt. It cares how LONG it has been
   hot — a fire brigade's whole judgement about whether to go into a
   building is that question — so INTEGRITY is a clock and not a
   quantity: one when the frame is whole, zero when it is on the floor,
   and falling for as long as there is fire AT the region.

   AT, AND NOT IN, WHICH IS THE WHOLE TRICK. A gutted region has very
   little left to burn by definition, so a clock that watched only its
   own cells would run for the few seconds of its last eight per cent and
   then stop. What cooks the steel over aisle six is the fire in aisle
   five. So a hot cell credits its own region AND every region it is
   LINKED to — which through a wall is nothing and across an open aisle
   is everything — and a bay only comes down while the building around it
   is still going.

   THE FIRST CUT OF THIS RE-FUELLED A GUTTED REGION instead, on the
   reasoning that a burnt-out building is full of burning deck. It is,
   and it was still the wrong mechanism: fuel put back above the
   threshold a cell needs to light its neighbour means a ruin relights
   the room next door, which relights it back, and the fire stops being
   something you set and becomes something that cannot be stopped. The
   sign it was wrong was not in this file — it was the police, who could
   no longer keep a van in the car park long enough to get out of it. A
   clock adds nothing to the world. That is the point of it.

   The two consequences are the ones worth having. A shop that burns from
   end to end comes down, a bay at a time, in the order it burnt. And a
   region at the EDGE of a fire — one that gutted and then had the fire
   move away from it, or had the rain put it out — stands as a ruin,
   because nothing kept cooking it. Which side of that line a bay falls
   is not a coin flip anywhere in this file; it is where the fire went.
   ===================================================================== */

/* Integrity lost per fire step by a ruin that is properly alight. The
   sim steps every FIRE_INTERVAL tics, so this is about fifty seconds of
   a burning shell before the frame lets go — long enough to stand in the
   car park and watch it happen, short enough that it happens. */
const COOK = 0.006;

/* AND HOW MANY CELLS ALIGHT COUNT AS A FULL FIRE, as an absolute rather
   than a fraction of the region: what is cooking a joist is the fire
   under it and beside it, and there is no more of that over a big bay
   than over a small one. Six cells is about six thousand square units of
   flame, which is the end of a gondola going up. */
const COOK_FULL = 6;

/* AND HOW MANY TIMES ON THE WAY DOWN THE ROOF IS REDRAWN.

   Integrity falls smoothly and the frame over a region is STATIC
   geometry, rebuilt only when something tells the renderer that a block
   has changed — so a continuous number would have no picture attached to
   it until the moment the region fell, and the whole of what the user
   asked to be able to watch would happen in one frame. Quantising it
   means a bay droops three times, visibly, and then goes.

   Four and not forty, because every step is a rebuild of the drawing
   blocks that region is in, and there are dozens of bays doing this at
   once in the back half of a fire. */
const WEAR_STEPS = 4;

/* How hot a cell can get, from how much there is to burn. Thin fuel
   smoulders below a hundred and thirty; a full gondola goes to white. */
const peakHeat = f0 => Math.max(112, Math.min(PEAK, 112 + f0 * 0.5));

/* Chance out of 1024, per fire tic, per direction, that a burning cell
   lights its neighbour. Scales with the NEIGHBOUR's richness — fire
   moves toward what will take it — and the range is deliberately wide:

     a gondola of stock  150   a front advances a cell every second or
                               so, and a full run goes up in a minute
     bare lino             7   a cell every half a minute, so crossing
                               one aisle is minutes of watching it creep

   Both are above the percolation threshold, so both go eventually. The
   difference between them is entirely PACE, and it is now a factor of
   twenty rather than the factor of six a straight `f >> 3` gave: the
   curve is a power law rather than a shift, which is what lets the floor
   crawl without the stock going out.

   OUT OF 1024, NOT DOOM'S 256, because at the pace asked for the floor's
   chance is about seven in a thousand and three in 256 is four times
   that. The quantisation, not the arithmetic, was the limit. */
const SPREAD_DEN = 65536;
/* The chance a cell of the RICHEST stock passes the fire on, per
   direction, per fire tic — and therefore the one number that decides
   whether this game has a fire in it or a fire problem. See the block
   above: everything else here is pace, this is the verdict. */
const SPREAD_RICH = 400;
/* How fast the chance falls away as the fuel thins. Steeper than it was,
   which is how the walkways became real firebreaks instead of slow ones:
   at 2.4 a gondola is sixty times more willing to pass fire on than the
   bare floor between two of them, where it used to be twenty. */
const SPREAD_CURVE = 2.4;
const SPREAD_TABLE = (() => {
  const t = new Uint32Array(1024);
  for (let f = 0; f < t.length; f++)
    t[f] = f <= 0 ? 0 : Math.min(SPREAD_RICH, Math.round(SPREAD_RICH * Math.pow(f / 300, SPREAD_CURVE)));
  return t;
})();
const spreadChance = f => SPREAD_TABLE[Math.min(1023, Math.max(0, f | 0))];
/* ONE ROLL IN 65536, out of two eight-bit rolls, and the denominator had
   to grow with the answer. Bare lino now wants to pass the fire on about
   nine times in sixty-five thousand; in the old thousand-and-twenty-four
   that is nought or it is one, and one is four times too many. The old
   table had a `max(4, ...)` floor under it for exactly this reason — it
   could not express a number that small, so it rounded every thin cell
   UP to four and that floor was what carried fire across the walkways.
   The quantisation was the mechanic. */
const spreadRoll = n => (((pRandom() << 8) | pRandom()) < n);

/* HOW HARD THE RAIN WORKS on a cell it can reach: heat taken off per
   fire tic at full rain, against a RISE of 14 while the fuel holds —
   more than the fuel can put back, so a fuelled fire under the rain
   loses eight a fire tic and a cell at a hundred is out in three
   seconds with its fuel still in it. It was 12 at first, which only
   slowed a fire down, and the headless check that lights a gutted
   region in the rain and expects it out is what said so. And how much
   of a cell's chance to light a wet neighbour the rain takes away. */
/* Fire goes UP much more readily than it goes along, and through a
   party wall far less readily than either.

   FOUR TIMES, and it has to be: a staircase is a chimney with a
   handrail, and the only place a flight reaches into the floor above is
   the top tread — one or two cells of the several hundred in a house.
   At the sideways chance that one cell has to win a race against its own
   fuel running out, and it loses it, and a house burns to the ceiling
   and stops. At four it goes up, which is what a house does.

   A PARTY WALL is sixteen units of void and two skins of plasterboard:
   hours, not minutes, which is what lets you watch a terrace go one
   house at a time rather than all at once. */
const UP_SPREAD = 4, CEIL_SPREAD = 0.4, PARTY_SPREAD = 0.10;

const RAIN_COOL = 22;
const RAIN_SPREAD = 0.85;

/** The wind as four multipliers, east, north, west, south, on the
 *  chance of a cell lighting the one in that direction. Units per tic
 *  in; a wind of 0.9 is a 1.7 downwind and a 0.4 against. */
export function windMultipliers(wx, wy) {
  const m = v => Math.max(0.4, Math.min(1.8, 1 + v * 0.75));
  return [m(wx), m(wy), m(-wx), m(-wy)];
}

export class FireSystem {
  constructor(game) {
    this.game = game;
    const lv = game.level;
    /* THE WHOLE SIMULATION, ON A SWITCH, at the user's request — and it
       is a fact about the WORLD rather than a setting, so the map says
       it. The grid world (js/maps/grid.js) has no fuel in its floor and
       nothing in it that spreads: its boxes burn one at a time, off one
       number each, in js/boxes.js. Running a cell grid over ten
       thousand units of field so that every cell of it can report
       nothing is the cost the user asked to stop paying.

       The grid is still ALLOCATED, because half the game reads these
       arrays — the shader is handed the burn grid as a picture every
       tic, the thermal sight samples it, the structure asks which
       region it is in — and a system that answers "no fire anywhere" to
       all of them is worth more than one that is not there. What stops
       is the seeding, the linking and the stepping. */
    this.off = !!lv.noCellFire;
    const [minx, miny, maxx, maxy] = lv.fireBounds || lv.bounds;
    this.originX = Math.floor(minx / CELL) * CELL - CELL;
    this.originY = Math.floor(miny / CELL) * CELL - CELL;
    this.cols = Math.ceil((maxx - this.originX) / CELL) + 2;
    this.rows = Math.ceil((maxy - this.originY) / CELL) + 2;
    /* and how big a cell is, for anything that has to find its way from
       a world position into this grid — see Game.ticBurnGrid, which
       hands the whole thing to the shader as a picture */
    this.CELL = CELL;
    /* ONE GRID PER STOREY LEVEL, stacked. A town has bedrooms over
       kitchens (see TOWN.txt) and a flat grid cannot hold a fire in one
       without holding it in the other. The planes are the storey index
       and not a height band, so plane 0 is the ground everywhere and is
       exactly the grid this used to be — every consumer that indexes by
       cy*cols+cx is reading the ground floor and does not know the rest
       is there, Game.ticBurnGrid among them. */
    /* AS MANY PLANES AS THERE IS FUEL TO PUT IN THEM. A roof storey is
       a shell — it has no fuel and nothing in it can catch — so a house
       with a roof over its second floor is still three planes and not
       four, and half a million cells of nothing are not allocated,
       seeded and linked to find that out. */
    this.levels = 1;
    for (const sec of lv.sectors) if (sec.fuel > 0 && sec.storey + 1 > this.levels) this.levels = sec.storey + 1;
    this.plane = this.cols * this.rows;
    const n = this.plane * this.levels;

    /* Floats, so a cell of bare lino can eat a third of a unit a tic —
       see burnFrac. As integers the smallest expressible burn rate was
       one unit a tic, and that was the floor under how slowly anything
       could smoulder. */
    this.fuel  = new Float32Array(n);
    this.fuel0 = new Float32Array(n);
    this.heat  = new Uint8Array(n);
    this.ember = new Uint16Array(n);
    this.link  = new Uint8Array(n);      // 1 E, 2 N, 4 W, 8 S
    this.sectorOf = new Int32Array(n).fill(-1);
    /* UNDER THE SKY: the car park, the road, the wood. What the rain
       falls on. A gutted region joins it at runtime — see rainOn */
    this.open  = new Uint8Array(n);

    /* ------------------------------------------------------------------
       WHICH CELLS CHANGED, so that the picture of this grid the shader
       reads does not have to be looked for.

       Game.ticBurnGrid turns `fuel / fuel0` into a texture the world
       shader samples by position (see THE PICTURE in js/game.js). It used
       to find the changed cells by SCANNING THE WHOLE GRID every tic, and
       that was written when the grid was the supermarket: 225 by 207,
       forty-six thousand cells, a fraction of a millisecond. The town
       made it 605 by 810 — four hundred and ninety thousand — and nobody
       re-measured. Seventeen million cell reads a second, at thirty-five
       tics, to find the twenty that moved, and it cost two thirds of
       every tic in the game whether or not anything was alight.

       So the fire says what it touched. Every write to `fuel` pushes its
       cell here and ticBurnGrid drains the list; the work is then the
       number of cells actually burning, which is tens.

       LEVEL 0 ONLY, because that is the plane the picture is of — a
       fire in a bedroom does not soot the street below it, and every
       consumer that indexes by cy*cols+cx is reading the ground floor
       (see the note on `levels` above).

       `gridDirtyAll` is the escape hatch: true to start, so the first
       drain lays down the whole grid once, and true again if the list
       ever grows past anything a drain could sensibly walk. */
    this.gridDirty = [];
    this.gridDirtyAll = true;

    this.active = [];                    // cells currently alight
    this._activeSet = new Uint8Array(n);
    this.totalFuel = 0;
    this.burntFuel = 0;
    this.hotCells = 0;
    this.tics = 0;

    /* per-region progress, so a region can be charred when it has gone */
    this.sectorFuel = new Float64Array(this.game.level.sectors.length);
    this.sectorBurnt = new Float64Array(this.game.level.sectors.length);
    /* how many cells of grid a region covers — its SPAN, which is what
       decides whether its roof can fall in; see guttedSurfaces */
    this.sectorCells = new Int32Array(this.game.level.sectors.length);
    this.newlyCharred = [];
    this.newlyGutted = [];
    this.newlyCollapsed = [];
    /* and the ones that have merely sagged another notch: a redraw and
       nothing else, see WEAR_STEPS */
    this.newlySagged = [];
    /* EVERY REGION STARTS WHOLE. On the sector rather than in here,
       beside `charred` and `gutted`, because what reads it is the thing
       that draws the steel — see js/ruin.js — and that runs over a level
       whether or not anybody ever lit it. */
    for (const s of this.game.level.sectors) if (s.integrity === undefined) s.integrity = 1;
    /* the ruins that are still up, and how many cells of each are alight
       this step: the collapse clock, and the only two allocations it
       needs */
    this._standing = [];
    this._cookHot = new Int32Array(this.game.level.sectors.length);
    /* AND WHICH REGIONS ARE A BUILDING AT ALL.

       Two of the three stages already ask this question, in the one line
       that guards them: `if (this.sectorFuel[si] > 0)`. A region with
       nothing in it to burn cannot char and cannot gut, which is how a
       car park stays a car park while the shop behind it goes.

       Collapse needs the same guard and one more, because fuel is not
       the whole of it — a back yard and a town park both have something
       to burn and neither of them has a roof to lose. What comes down in
       a collapse is the thing that was over your head, so a region that
       was ALREADY open to the sky is not a candidate, however well it
       burns. That is exactly `ceilTex === 'SKY'`, which is how this
       engine says "no ceiling here", and it is read ONCE at build time
       because gutting sets it on every region whose deck has gone. Ask
       it later and nothing could ever fall twice. */
    this.structural = new Uint8Array(this.game.level.sectors.length);

    this._seed();
    for (const s of this.game.level.sectors)
      this.structural[s.index] = (this.sectorFuel[s.index] > 0 && s.ceilTex !== 'SKY') ? 1 : 0;
    this._linkCells();
  }

  idx(cx, cy, lv = 0) { return lv * this.plane + cy * this.cols + cx; }
  cellX(x) { return clamp(Math.floor((x - this.originX) / CELL), 0, this.cols - 1); }
  cellY(y) { return clamp(Math.floor((y - this.originY) / CELL), 0, this.rows - 1); }
  worldX(cx) { return this.originX + cx * CELL + CELL / 2; }
  worldY(cy) { return this.originY + cy * CELL + CELL / 2; }

  /* Every cell takes its fuel from the sector it lands in. A sector with
     fuel 0 — the car park, the tiled corridor — will never burn, and
     that is how the map author draws firebreaks.
   *
   * RASTERISED, NOT QUERIED. This used to ask sectorAt once per cell,
   * which is a point-in-polygon query against the blockmap and is fine
   * for a store: ninety-five thousand cells, a few milliseconds. Over a
   * town eighteen thousand units across it is half a million of them,
   * and half a million of anything is the difference between three
   * hundred milliseconds and thirty. So each sector fills its own
   * bounding box once instead, first one wins, which is the same answer
   * sectorAt gives because it is the same order and the polygons do not
   * overlap. The smoke test runs both and compares, cell for cell. */
  _seed() {
    if (this.off) return;
    const lv = this.game.level;
    for (const s of lv.sectors) {
      /* EVERY STOREY, each into its own plane. A column of one — which
         is the store, the car park, the road and the wood — lands in
         plane 0 and nothing above it is touched. */
      const cx0 = this.cellX(s.bbox[0]), cx1 = this.cellX(s.bbox[2]);
      const cy0 = this.cellY(s.bbox[1]), cy1 = this.cellY(s.bbox[3]);
      const open = (s.outdoor || s.forest || s.outside) ? 1 : 0;
      const f = s.fuel | 0;
      const lvl = s.storey;
      if (lvl >= this.levels) continue;      // a storey with no fuel anywhere
      /* AND NO CELL FOR A STOREY THAT CANNOT BURN. Plane 0 is seeded
         whatever its fuel, because a region with none is a firebreak
         and the grid has to know where the firebreaks are. A roof
         above a house is not a firebreak, it is a shell — nothing can
         be alight in it and nothing about it is worth a cell. */
      if (lvl > 0 && f <= 0) continue;
      /* a plain rectangle is its own bounding box, so every cell of it
         is inside and the query is a formality — which over a town is
         three hundred thousand formalities */
      const rect = s.isRect;
      for (let cy = cy0; cy <= cy1; cy++) {
        const wy = this.worldY(cy);
        const inRow = rect && wy > s.bbox[1] && wy < s.bbox[3];
        for (let cx = cx0; cx <= cx1; cx++) {
          const i = this.idx(cx, cy, lvl);
          if (this.sectorOf[i] >= 0) continue;
          const wx = this.worldX(cx);
          if (!(inRow && wx > s.bbox[0] && wx < s.bbox[2]) && !pointInPoly(s.poly, wx, wy)) continue;
          this.sectorOf[i] = s.index;
          this.sectorCells[s.index]++;
          if (open) this.open[i] = 1;
          if (f <= 0) continue;
          /* a little variation, so the burn front is ragged rather than
             an expanding rectangle */
          const v = Math.max(1, Math.round(f * (0.75 + (pRandom() / 255) * 0.5)));
          this.fuel[i] = v; this.fuel0[i] = v;
          this.totalFuel += v;
          this.sectorFuel[s.index] += v;
        }
      }
    }
  }

  _linkCells() {
    if (this.off) return;
    const lv = this.game.level;
    const DIRS = [[1, 0, 1, 4], [0, 1, 2, 8], [-1, 0, 4, 1], [0, -1, 8, 2]];
    /* WHERE FIRE CAN CLIMB. Not a bit but a list, because the cell it
       goes to is not always the one directly overhead: a stairwell
       lights the LANDING BESIDE IT, which is the correct and horrible
       answer — the first floor of a house catches from the stairs and
       not from the room under it. Rare enough to be a Map and looked at
       only for cells that have the bit. */
    this.up = new Map();
    /* AND PARTY WALLS. A terrace burns end to end through the sixteen
       units of void between two houses, slowly, and that is the
       difference between burning a house and burning a street. Only
       between two regions that both say they are a party wall, so the
       supermarket's own partitions are untouched by it. */
    this.party = new Uint8Array(this.link.length);
    for (let lvl = 0; lvl < this.levels; lvl++) {
    for (let cy = 0; cy < this.rows; cy++) {
      for (let cx = 0; cx < this.cols; cx++) {
        const i = this.idx(cx, cy, lvl);
        const si = this.sectorOf[i];
        if (si < 0) continue;
        const x1 = this.worldX(cx), y1 = this.worldY(cy);
        /* up: the cell overhead and the four beside it, wherever the two
           storeys share any air at all */
        if (lvl + 1 < this.levels && !this.open[i]) {
          /* indoors only, which is the gate that makes this affordable:
             the car park, the road and nine thousand units of wood have
             nothing over them and asking is a million questions */
          const A = lv.sectors[si];
          let ups = null;
          for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [-1, 0], [0, -1]]) {
            const nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= this.cols || ny >= this.rows) continue;
            const j = this.idx(nx, ny, lvl + 1);
            const sj = this.sectorOf[j];
            if (sj < 0) continue;
            const B = lv.sectors[sj];
            const share = Math.min(A.ceil, B.ceil) - Math.max(A.floor, B.floor);
            if (share > 0) {
              /* THE STAIRWELL. Two storeys that share air — the top
                 tread of a flight reaching into the landing beside it —
                 and the wall is asked about at the height they share. */
              const zm = (Math.max(A.floor, B.floor) + Math.min(A.ceil, B.ceil)) / 2;
              if ((dx || dy) && this._fireBlocked(x1, y1, this.worldX(nx), this.worldY(ny), zm)) continue;
              (ups || (ups = [])).push(j, UP_SPREAD);
              continue;
            }
            /* AND THE CEILING, which is the slow way. A deck is sixteen
               units of joist and board and a fire under one gets through
               it in the end — straight up, same cell, and forty times
               less willing than the stairs. Which is what makes the
               stairwell the answer and not merely an answer: by the time
               the kitchen ceiling has gone the landing has been alight
               for a minute. */
            if (dx || dy) continue;
            if (B.floor - A.ceil > 24) continue;
            if (!A.fuel || !B.fuel) continue;
            (ups || (ups = [])).push(j, CEIL_SPREAD);
          }
          if (ups) { this.up.set(i, ups); this.link[i] |= 16; }
        }
        for (const [dx, dy, bit] of DIRS) {
          const nx = cx + dx, ny = cy + dy;
          if (nx < 0 || ny < 0 || nx >= this.cols || ny >= this.rows) continue;
          const j = this.idx(nx, ny, lvl);
          const sj = this.sectorOf[j];
          if (sj < 0) continue;
          /* TWO CELLS OF ONE CONVEX REGION ARE ALWAYS LINKED. A wall in
             this map is the GAP between two regions, so a convex region
             has no line strictly inside it and the ray cast below can
             only come back clear. Skipping it is the difference between
             two million blockmap queries over a town and the forty
             thousand that are actually a boundary.

             CONVEX and not merely "the same region", which is a thing I
             got wrong and the check caught: the wood is one region
             drawn round the hole the store stands in, and two of its
             cells either side of that hole are in it and have the whole
             back wall of the building between them. */
          if (sj === si) {
            const s0 = lv.sectors[si], bb = s0.bbox;
            /* and both centres STRICTLY inside it. A centre that lands
               exactly on the region's own edge sits on a one-sided line
               and the honest ray calls that a wall, which is a
               degeneracy rather than a fact about the map — but it is
               the answer the ray gives, so the shortcut declines to
               guess and lets the ray have it. */
            if (s0.convex
                && x1 > bb[0] + 0.5 && x1 < bb[2] - 0.5 && y1 > bb[1] + 0.5 && y1 < bb[3] - 0.5) {
              const nxw = this.worldX(nx), nyw = this.worldY(ny);
              if (nxw > bb[0] + 0.5 && nxw < bb[2] - 0.5 && nyw > bb[1] + 0.5 && nyw < bb[3] - 0.5) {
                this.link[i] |= bit; continue;
              }
            }
          }
          const zi = lv.sectors[si].floor + 8;
          if (!this._fireBlocked(x1, y1, this.worldX(nx), this.worldY(ny), zi)) { this.link[i] |= bit; continue; }
          /* blocked — unless it is a party wall, which is a wall fire
             gets through eventually and is what makes a terrace a
             terrace rather than eight separate fires */
          if (lv.sectors[si].party && lv.sectors[sj].party) this.party[i] |= bit;
        }
      }
    }
    }
  }

  /** Walls stop fire. Gaps do not — a shut door is the only two-sided
   *  line that counts as a wall here.
   *
   *  AT A HEIGHT, because a town has bedrooms over kitchens: the wall
   *  between two first floors is not the wall between the two rooms
   *  under them, and asking the ground sectors gets both of them wrong.
   *  For a column of one — the store, the lot, the wood — spanIn hands
   *  back the sector it was given and this is the check it always was. */
  _fireBlocked(x1, y1, x2, y2, z = 8) {
    const lv = this.game.level;
    const lines = lv.linesInBox(Math.min(x1, x2), Math.min(y1, y2), Math.max(x1, x2), Math.max(y1, y2),
      this._blockScratch || (this._blockScratch = []));
    for (const l of lines) {
      const t = segCross(x1, y1, x2, y2, l.x1, l.y1, l.x2, l.y2);
      if (t < 0) continue;
      if (l.front === null || l.back === null) return true;
      const a = lv.spanIn(lv.sectors[l.front], z), b = lv.spanIn(lv.sectors[l.back], z);
      /* A door is judged on what it will be, not on what it is right
         now. These links are worked out once at startup, with every door
         still shut, and a link that said "no" then would keep saying no
         for the rest of the level — so the stockroom would never catch
         however wide you left the door. */
      if (a.dynamic || b.dynamic) continue;
      if (Math.min(a.ceil, b.ceil) - Math.max(a.floor, b.floor) <= 0) return true;
    }
    return false;
  }

  /* ------------------------------------------------------------------
     Setting things alight
     ------------------------------------------------------------------ */

  /** Put heat into the world at a point. `strength` is roughly how much
   *  fuel is being dumped there too — a fuel can makes its own. */
  ignite(x, y, strength = 60, radius = CELL) {
    /* WHATEVER ELSE BURNS IN THIS WORLD gets the same call first. The
       grid world's boxes are not cells and are not in this grid, and
       every weapon in the game already calls THIS — the flamethrower,
       the bottles, a bang, a burning body, a car going up. Routing them
       from here is what means not one of those had to learn what a box
       is. js/game.js hands them over. */
    this.boxes?.ignite(x, y, strength, radius);
    if (this.off) return 0;
    const cx0 = this.cellX(x - radius), cx1 = this.cellX(x + radius);
    const cy0 = this.cellY(y - radius), cy1 = this.cellY(y + radius);
    let lit = 0;
    for (let cy = cy0; cy <= cy1; cy++) {
      for (let cx = cx0; cx <= cx1; cx++) {
        const i = this.idx(cx, cy);
        if (this.sectorOf[i] < 0) continue;
        /* ACCELERANT. Something poured here burns even on bare lino,
           which is how you get a fire across a walkway that has nothing
           of its own to burn.

           How much is left behind decides whether the fire can then
           travel on by itself, and that is the difference between the
           two fire weapons. A flamethrower lays down about 40 — enough
           to burn where you are pointing, never enough to spread, so the
           flame goes exactly as far as you walk. A bottle lays down over
           a hundred, which is above the threshold, so its pool WILL
           reach into whatever is next to it. One is a brush; the other
           is a thrown decision. */
        if (strength > 40) {
          const target = Math.min(150, Math.round(strength * 0.62));
          if (this.fuel[i] < target) {
            const add = target - this.fuel[i];
            this.fuel[i] += add; this.fuel0[i] += add; this.totalFuel += add;
            this._touch(i);
          }
        }
        if (this.fuel[i] <= 0) continue;
        if (this.heat[i] === 0) lit++;
        this.heat[i] = Math.max(this.heat[i], Math.min(peakHeat(this.fuel0[i]), IGNITE_AT + strength));
        this._activate(i);
      }
    }
    return lit;
  }

  /* ------------------------------------------------------------------
     AND PUTTING ONE OUT

     The opposite operation, and it is not symmetrical with ignite, which
     is the interesting part. Fire is a THRESHOLD system — a cell spreads
     at SPREAD_AT and dies below EMBER_HEAT — so taking heat away is not
     undoing damage, it is moving a cell across a line. Drop one under
     SPREAD_AT and it stops recruiting its neighbours; drop it to nothing
     and it is out, and the front behind it starves.

     WHAT IT CANNOT DO IS PUT THE FUEL BACK. A shelf that has burned is
     burned: `burntFuel` only goes up, a charred region stays charred,
     and a region that has gone will not come back because somebody
     sprayed it. So the extinguisher is not an undo button — it is a
     firebreak you can draw with, and the thing it saves is whatever has
     not caught YET.

     EMBERS GO TOO, and this is the difference between a fire that is out
     and a fire that is sulking. A cell with fuel gone sits at a glow for
     EMBER_TICS and will relight anything that wanders past; a doused one
     has its ember clock cleared, so the aisle behind you stays dark.

     @param strength  roughly how much heat comes off, 0..255
     @returns how many cells it actually cooled */
  douse(x, y, strength = 90, radius = CELL) {
    this.boxes?.douse(x, y, strength, radius);
    if (this.off) return 0;
    const cx0 = this.cellX(x - radius), cx1 = this.cellX(x + radius);
    const cy0 = this.cellY(y - radius), cy1 = this.cellY(y + radius);
    const r2 = radius * radius;
    let cooled = 0;
    for (let cy = cy0; cy <= cy1; cy++) {
      for (let cx = cx0; cx <= cx1; cx++) {
        const i = this.idx(cx, cy);
        if (this.sectorOf[i] < 0 || this.heat[i] === 0) continue;
        /* ROUND, NOT SQUARE, unlike ignite — a spray is a cone and the
           corner of a box of cells is a cell that never had any gas on
           it. ignite gets away with a box because fire spreads from
           whatever it lights and the shape stops mattering a tic later;
           a doused corner left burning restarts the whole cell. */
        const dx = this.worldX(cx) - x, dy = this.worldY(cy) - y;
        if (dx * dx + dy * dy > r2) continue;
        const fall = 1 - Math.sqrt(dx * dx + dy * dy) / radius;
        const take = Math.round(strength * (0.35 + 0.65 * fall));
        const h = this.heat[i] - take;
        cooled++;
        if (h <= EMBER_HEAT) { this.heat[i] = 0; this.ember[i] = 0; }
        else this.heat[i] = h;
      }
    }
    return cooled;
  }

  /** This cell's fuel moved, so the picture of the grid is out of date
   *  here. See gridDirty in the constructor. */
  _touch(i) {
    if (i >= this.plane || this.gridDirtyAll) return;
    if (this.gridDirty.length > 1 << 16) { this.gridDirtyAll = true; this.gridDirty.length = 0; return; }
    this.gridDirty.push(i);
  }

  _activate(i) {
    if (this._activeSet[i]) return;
    this._activeSet[i] = 1;
    this.active.push(i);
  }

  heatAt(x, y) {
    const i = this.idx(this.cellX(x), this.cellY(y));
    return this.heat[i] / 255;
  }

  get burnFraction() { return this.totalFuel > 0 ? this.burntFuel / this.totalFuel : 0; }
  /* What the status bar shows: cells that are actually alight, not the
     long tail of embers behind the front. */
  get burningCells() { return this.hotCells; }
  get liveCells() { return this.active.length; }

  /* ------------------------------------------------------------------
     One step of the simulation

     Runs every other tic. Fire is slow; running it at 35Hz costs twice
     as much and looks identical.
     ------------------------------------------------------------------ */
  tic() {
    if (this.off) return;
    this.tics++;
    if (this.tics % FIRE_INTERVAL) return;

    const { heat, fuel, link, cols } = this;
    const next = [];
    const toIgnite = [];
    let hot = 0;

    const fuel0 = this.fuel0;
    /* THE WIND, as four multipliers on the four directions a cell can
       light: a fire runs downwind and creeps against it, which is what
       makes a firebreak a decision rather than a rectangle. And THE
       RAIN, which only a cell under the sky feels — the roof is the
       whole of the difference — and which a gutted region has lost. */
    const [mE, mN, mW, mS] = windMultipliers(climate.wind.x, climate.wind.y);
    const rain = climate.rain;
    const sectors = this.game.level.sectors;
    for (let k = 0; k < this.active.length; k++) {
      const i = this.active[k];
      let h = heat[i];
      const f = fuel[i];
      const si = this.sectorOf[i];
      const wet = rain > 0 && this.rainOn(i, sectors) ? rain : 0;

      if (f > 0) {
        /* burning: heat climbs toward what this much fuel can sustain,
           and eats a fraction of the original per tic — so a rich cell
           roars and a thin one smoulders, for about the same length of
           time either way */
        const peak = peakHeat(fuel0[i]);
        h = Math.min(peak, h + RISE);
        const eat = Math.min(f, fuel0[i] * burnFrac(fuel0[i]) * (h / 255));
        fuel[i] = f - eat < 0.02 ? 0 : f - eat;
        this._touch(i);
        this.burntFuel += eat;
        if (si >= 0) {
          this.sectorBurnt[si] += eat;
          const sec = this.game.level.sectors[si];
          if (this.sectorFuel[si] > 0) {
            const gone = this.sectorBurnt[si] / this.sectorFuel[si];
            if (!sec.charred && gone >= CHAR_AT) {
              sec.charred = true;
              this.newlyCharred.push(si);
            }
            if (!sec.gutted && gone >= GUT_AT) {
              sec.gutted = true;
              this.newlyGutted.push(si);
              if (this.structural[si]) this._standing.push(si);
            }
          }
        }
        if (fuel[i] <= 0) this.ember[i] = EMBER_TICS;
        /* RAIN ON A FIRE. It takes heat off faster than the fuel can put
           it back, so a burning car park in the rain sulks at the
           threshold and never gets to light its neighbours, and a
           gutted store with the roof gone is a store the weather is
           putting out. */
        if (wet > 0) {
          h -= Math.round(RAIN_COOL * wet);
          /* and out, with its fuel still in it: off the active list,
             rather than sitting there at nothing for ever */
          if (h <= 0) { heat[i] = 0; this.ember[i] = 0; this._activeSet[i] = 0; continue; }
        }
      } else if (h > EMBER_HEAT) {
        h -= FALL;                                  // falling back to a glow
        if (wet > 0) h -= Math.round(RAIN_COOL * wet);
        if (h < EMBER_HEAT) h = EMBER_HEAT;
      } else if (this.ember[i] > 0 && wet > 0) {
        /* and the embers go, which is the difference between a fire
           that is out and one that is sulking — see douse */
        this.ember[i] = 0; heat[i] = 0; this._activeSet[i] = 0; continue;
      } else if (this.ember[i] > 0) {
        this.ember[i]--;                            // and sitting there a while
        h = 2 + Math.round((EMBER_HEAT - 2) * this.ember[i] / EMBER_TICS);
      } else {
        heat[i] = 0; this._activeSet[i] = 0; continue;
      }
      heat[i] = h;
      if (h >= SPREAD_AT) hot++;
      /* AND WHAT THE HEAT IS DOING TO THE STEEL. A standing ruin counts
         the cells alight inside it, and that count is the whole of the
         collapse clock — see AND WHAT IS STILL HOLDING IT UP. Embers
         count: a floor of glowing deck is still cooking the frame. */
      if (h > EMBER_HEAT) this._creditHeat(i, si, sectors, link[i]);

      /* Spread. Only a well-established cell can light another, so a
         fire has to take hold before it travels — which is what gives
         you the moment to decide whether to put more accelerant on it or
         get out of the aisle. */
      if (h >= SPREAD_AT) {
        const lk = link[i];
        /* THE WIND BLOWS OUTSIDE. A fire under a roof spreads as it
           always did — there is no wind in aisle six — and the first
           cut of this leaned every fire in the building and changed
           how a night went that no weather had touched. */
        const windy = this.open[i] === 1;
        if (lk & 1) this._trySpread(i + 1, toIgnite, windy ? mE : 1, rain, sectors);
        if (lk & 2) this._trySpread(i + cols, toIgnite, windy ? mN : 1, rain, sectors);
        if (lk & 4) this._trySpread(i - 1, toIgnite, windy ? mW : 1, rain, sectors);
        if (lk & 8) this._trySpread(i - cols, toIgnite, windy ? mS : 1, rain, sectors);
        /* UP THE STAIRS, and readily: heat goes up, and a stairwell is
           a chimney with a handrail. */
        if (lk & 16) {
          const ups = this.up.get(i);
          for (let u = 0; u < ups.length; u += 2) this._trySpread(ups[u], toIgnite, ups[u + 1], rain, sectors);
        }
        /* and through the party wall, slowly */
        const pw = this.party[i];
        if (pw) {
          if (pw & 1) this._trySpread(i + 1, toIgnite, PARTY_SPREAD, rain, sectors);
          if (pw & 2) this._trySpread(i + cols, toIgnite, PARTY_SPREAD, rain, sectors);
          if (pw & 4) this._trySpread(i - 1, toIgnite, PARTY_SPREAD, rain, sectors);
          if (pw & 8) this._trySpread(i - cols, toIgnite, PARTY_SPREAD, rain, sectors);
        }
      }
      next.push(i);
    }

    this.active = next;
    this.hotCells = hot;
    for (const j of toIgnite) {
      if (j < 0 || j >= heat.length) continue;
      if (fuel[j] <= 0 || heat[j] > 0) continue;
      heat[j] = IGNITE_AT;
      this._activate(j);
    }

    this._cookRuins(sectors);
    this._burnThings();
    this._updateAtmosphere();
  }

  /* ------------------------------------------------------------------
     THE COLLAPSE CLOCK

     One pass over the ruins that are still up, which is a list of tens
     rather than the hundred thousand cells above it.
     ------------------------------------------------------------------ */
  _cookRuins(sectors) {
    if (!this._standing.length) return;
    const cook = this._cookHot;
    let fell = false;
    for (let k = 0; k < this._standing.length; k++) {
      const si = this._standing[k];
      const sec = sectors[si];
      const hot = cook[si];
      cook[si] = 0;
      if (sec.collapsed) { fell = true; continue; }
      if (hot > 0) sec.integrity -= COOK * Math.min(1, hot / COOK_FULL);
      if (sec.integrity <= 0) { this.bringDown(si); fell = true; continue; }
      const step = Math.min(WEAR_STEPS - 1, Math.floor((1 - sec.integrity) * WEAR_STEPS));
      if (step !== (sec.wearStep | 0)) { sec.wearStep = step; this.newlySagged.push(si); }
    }
    if (fell) this._standing = this._standing.filter(si => !sectors[si].collapsed);
  }

  /** One hot cell, against every standing ruin it is cooking.
   *
   *  ITS OWN REGION AND THE ONES IT IS LINKED TO, which is the same set
   *  of four the fire itself can spread through — so heat reaches a
   *  neighbour exactly where flame could, and a wall that stops the fire
   *  also protects the steel behind it. Unrolled rather than looped over
   *  an array of four, because this runs once per burning cell per step
   *  and there are thousands of them. */
  _creditHeat(i, si, sectors, lk) {
    const cook = this._cookHot, so = this.sectorOf, cols = this.cols;
    if (si >= 0) { const s = sectors[si]; if (s.gutted && !s.collapsed) cook[si]++; }
    if (lk & 1) { const j = so[i + 1]; if (j >= 0 && j !== si) { const s = sectors[j]; if (s.gutted && !s.collapsed) cook[j]++; } }
    if (lk & 2) { const j = so[i + cols]; if (j >= 0 && j !== si) { const s = sectors[j]; if (s.gutted && !s.collapsed) cook[j]++; } }
    if (lk & 4) { const j = so[i - 1]; if (j >= 0 && j !== si) { const s = sectors[j]; if (s.gutted && !s.collapsed) cook[j]++; } }
    if (lk & 8) { const j = so[i - cols]; if (j >= 0 && j !== si) { const s = sectors[j]; if (s.gutted && !s.collapsed) cook[j]++; } }
  }

  /** Take a region down, from whatever state it was in.
   *
   *  A BOMB DOES NOT WAIT FOR THE STAGES, but everything downstream of
   *  them is written against the flags — the surfaces, the steel, the
   *  lamps that have to be taken out of a roof that is not there — so a
   *  region that is blown flat still passes through charred and gutted
   *  on its way, in one tic, in order. */
  bringDown(si) {
    const sec = this.game.level.sectors[si];
    if (sec.collapsed || !this.structural[si]) return false;
    if (!sec.charred) { sec.charred = true; this.newlyCharred.push(si); }
    if (!sec.gutted) { sec.gutted = true; this.newlyGutted.push(si); this._standing.push(si); }
    sec.integrity = 0;
    sec.collapsed = true;
    this.newlyCollapsed.push(si);
    return true;
  }

  /* ------------------------------------------------------------------
     AND THE OTHER WAY TO BRING A BUILDING DOWN

     Fire is patient and a blast is not. This takes integrity off every
     region a blast reaches, falling off with distance, and anything it
     takes past zero comes down in the same tic — so a big enough bang
     is a hole in a building rather than a scorch mark on one.

     WALKED ON THE FIRE'S OWN GRID, because that grid already knows which
     region every point of the world is in and a blast is a circle over
     it. Which also means a blast reaches exactly as far as fire does and
     stops at the same walls.
     ------------------------------------------------------------------ */
  damageStructure(x, y, radius, amount, lv = 0) {
    if (!(amount > 0) || !(radius > 0)) return 0;
    const sectors = this.game.level.sectors;
    const seen = this._blastSeen || (this._blastSeen = new Map());
    seen.clear();
    const cx0 = this.cellX(x - radius), cx1 = this.cellX(x + radius);
    const cy0 = this.cellY(y - radius), cy1 = this.cellY(y + radius);
    for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) {
      const dx = this.worldX(cx) - x, dy = this.worldY(cy) - y;
      const d2 = dx * dx + dy * dy;
      if (d2 > radius * radius) continue;
      const si = this.sectorOf[this.idx(cx, cy, lv)];
      if (si < 0 || !this.structural[si] || sectors[si].collapsed) continue;
      /* the nearest cell of a region is the one that decides how hard it
         was hit, not the average of the ones inside the circle */
      const bite = amount * (1 - Math.sqrt(d2) / radius);
      if (!(seen.get(si) >= bite)) seen.set(si, bite);
    }
    let down = 0;
    for (const [si, bite] of seen) {
      const sec = sectors[si];
      sec.integrity = (sec.integrity ?? 1) - bite;
      if (sec.integrity <= 0 && this.bringDown(si)) down++;
    }
    return down;
  }

  /* ------------------------------------------------------------------
     AND THE THIRD WAY TO BRING A BUILDING DOWN, WHICH IS A LINE

     Fire is patient, a blast is a circle, and the positron lance is a
     CYLINDER: a column of light a couple of metres across drawn from
     the muzzle to the far side of the map, and everything standing in
     it stops standing. See js/beam.js, which owns the beam; this owns
     the grid, so this is where the walk lives — the same argument
     damageStructure makes about the blast circle, said about a swept
     one.

     WALKED IN THE LINE'S OWN FRAME. A cell's place is turned into two
     numbers: `s`, how far along the ground track it lies, and `off`,
     how far to the side of it. `off` decides whether the cell is in the
     column at all and how hard it is hit; `s` decides how HIGH the beam
     is over that cell, which is the part a circle never has to think
     about. A shot fired level from the eye passes through ground floors
     for its whole length; one fired up the road at ten degrees is
     through the bedrooms by the end of the street and over the roofs
     after that, and this is the arithmetic that makes those two
     different.

     EVERY STOREY THE COLUMN TOUCHES, not the one it is aimed at. The
     column has a radius and a storey has a height, and at the widest
     stage the first is bigger than the second — so a level shot through
     a house takes the bedroom with the front room, because it does.

     THE NEAREST POINT OF A REGION DECIDES ITS BITE, exactly as in
     damageStructure and for the same reason: a region clipped by the
     edge of the column is grazed and one straddling the middle is cut,
     and averaging the cells in between would say neither.

     NOTHING CALLS THIS ANY MORE. The lance was its only caller and at
     the user's request the lance no longer changes the level at all —
     no holes, no collapse (see the head of js/beam.js). It is kept,
     because the walk is right and a line is the one shape the blast
     and the fire do not already cover.

     @param from    { x, y, z } the muzzle, in game coordinates
     @param angle   which way, and `slope` the rise per unit travelled
     @param range   how far along the ground track to walk
     @param radius  the column's own radius
     @param amount  integrity off a region at the centre of the column
     @returns how many regions came down
     ------------------------------------------------------------------ */
  damageLine(from, angle, slope, range, radius, amount) {
    if (!(amount > 0) || !(radius > 0) || !(range > 0)) return 0;
    const sectors = this.game.level.sectors;
    const seen = this._lineSeen || (this._lineSeen = new Map());
    seen.clear();
    const ux = Math.cos(angle), uy = Math.sin(angle);
    /* and the perpendicular, which is what the column is swept across */
    const vx = -uy, vy = ux;
    const ox = from.x, oy = from.y, oz = from.z;

    /* MARCHED ALONG THE LINE, NOT SCANNED OVER ITS BOX, and the
       difference is a factor of sixty.

       The obvious walk is the blast's: take the rectangle that bounds
       the shape and test every cell in it. For a circle that is four
       cells wasted in nine. For a segment eight thousand units long and
       two hundred and sixty wide, laid diagonally, the bounding box is
       eight thousand SQUARE — the whole town, a quarter of a million
       cells, to find the two thousand that are actually under the beam.
       Twelve times a second, for five seconds.

       So this marches: half a cell at a time along the line, and half a
       cell at a time across it out to the radius. Half, because a cell
       is CELL across and a step of CELL could straddle two of them and
       land in neither — at CELL/2 every cell the column covers is
       stepped into at least once. Cells near the middle are stepped
       into several times, which costs nothing: `seen` keeps the biggest
       bite a region took and a repeat is one map lookup.

       (range/step) * (2*radius/step) points, which for the widest
       stage is about eight thousand and does not grow with how far
       off the axes the shot happens to be pointing. */
    const step = CELL * 0.5;
    const maxX = this.cols - 1, maxY = this.rows - 1;
    for (let s = 0; s <= range; s += step) {
      /* how high the column is over this point, and which storeys that
         puts it through */
      const bz = oz + slope * s;
      const px = ox + ux * s, py = oy + uy * s;
      for (let t = -radius; t <= radius; t += step) {
        const x = px + vx * t, y = py + vy * t;
        const cx = Math.floor((x - this.originX) / CELL);
        if (cx < 0 || cx > maxX) continue;
        const cy = Math.floor((y - this.originY) / CELL);
        if (cy < 0 || cy > maxY) continue;
        const bite = amount * (1 - Math.abs(t) / radius);
        for (let lv = 0; lv < this.levels; lv++) {
          const si = this.sectorOf[this.idx(cx, cy, lv)];
          if (si < 0 || !this.structural[si] || sectors[si].collapsed) continue;
          const sec = sectors[si];
          if (bz + radius < sec.floor || bz - radius > sec.ceil) continue;
          if (!(seen.get(si) >= bite)) seen.set(si, bite);
        }
      }
    }
    let down = 0;
    for (const [si, bite] of seen) {
      const sec = sectors[si];
      sec.integrity = (sec.integrity ?? 1) - bite;
      if (sec.integrity <= 0 && this.bringDown(si)) down++;
    }
    return down;
  }

  /** Will the fire travel here, and how eagerly?
   *
   *  The answer is about the NEIGHBOUR and not about the cell doing the
   *  lighting: fire moves toward whatever will take it. Rich stock takes
   *  it readily enough that a run of shelving is a fuse; bare floor
   *  takes it about nine times in sixty-five thousand, which is a "no"
   *  with the door left open.
   *
   *  THE DOOR IS LEFT OPEN ON PURPOSE. A hard floor under this — "below
   *  this much fuel, never" — is what the old table had, and it meant
   *  whole parts of the shop could not burn even when the player stood
   *  there pouring on them. Nothing here is impossible; most of it is
   *  merely so unlikely that waiting is not a strategy. Which is the
   *  difference between a shop you have to burn and a shop you cannot. */
  _trySpread(j, out, mul = 1, rain = 0, sectors = null) {
    if (j < 0 || j >= this.heat.length) return;
    const f = this.fuel[j];
    if (f <= 0 || this.heat[j] > 0) return;
    let chance = spreadChance(f) * mul;
    /* a wet cell is a hard cell to light */
    if (rain > 0 && this.rainOn(j, sectors)) chance *= 1 - RAIN_SPREAD * rain;
    if (spreadRoll(chance)) out.push(j);
  }

  /** Is the rain falling on this cell? Under the sky, or under a roof
   *  that has gone. */
  rainOn(i, sectors = this.game.level.sectors) {
    if (this.open[i]) return true;
    const si = this.sectorOf[i];
    return si >= 0 && !!sectors[si].gutted;
  }

  /** Anything standing in a hot cell catches, and anything alive in one
   *  gets hurt. Includes the player: there is no safe way to stand in
   *  a fire you started. Excludes the fireproof — the SWAT — who walk
   *  through it; Actor.damage would refuse the hurt anyway, but there
   *  is no sense asking. */
  _burnThings() {
    const g = this.game;
    for (const a of g.actors) {
      if (a.removed || a.noclip || a.fireproof) continue;
      const h = this.heat[this.idx(this.cellX(a.x), this.cellY(a.y))];
      if (h < 70) continue;
      if (a.flammable && !a.burning) a.ignite(280 + (pRandom() & 127));
      else if (a.shootable && !a.dead && (this.tics & 15) === 0) a.damage(3, null, { fire: true });
    }
    const p = g.player;
    if (p && !p.dead) {
      const h = this.heat[this.idx(this.cellX(p.x), this.cellY(p.y))];
      if (h > 70 && (this.tics & 7) === 0) p.damage(Math.max(2, h >> 5), null, { fire: true });
    }
  }

  /** The one fire light parks itself in the middle of whatever is
   *  burning nearest the player.
   *
   *  THE SMOKE USED TO BE SET HERE TOO, and the lift in the ambient as
   *  the store goes. Both are the atmosphere's now — js/weather.js
   *  reads burnFraction off this and off the wood and sets every
   *  atmosphere uniform in one place, so the smoke, the air and the
   *  hour cannot disagree about what the far end of an aisle looks
   *  like. The reasoning that was here went with the code: the smoke
   *  is warm and lit and stops well short of opaque, and the ambient
   *  comes up as the place burns because the player still has to find
   *  the way out of it. */
  _updateAtmosphere() {
    const p = this.game.player;
    if (!p) return;
    let sx = 0, sy = 0, sw = 0, near = 0;
    /* A sample, not a sum: with a whole aisle alight there can be
       hundreds of cells and the answer does not change. */
    const step = Math.max(1, this.active.length >> 6);
    for (let k = 0; k < this.active.length; k += step) {
      const i = this.active[k];
      const h = this.heat[i];
      if (h < 60) continue;
      const c = i % this.plane;
      const x = this.worldX(c % this.cols), y = this.worldY((c / this.cols) | 0);
      const d2 = dist2(x, y, p.x, p.y);
      if (d2 > 900 * 900) continue;
      const w = h / 255;
      sx += x * w; sy += y * w; sw += w; near++;
    }
    /* The one light is shared: what is burning in the wood nearby and
       the flame leaving the gun pull it toward themselves too. */
    const acc = { sx: sx * step, sy: sy * step, sw: sw * step, n: near };
    this.game.forest?.glowInto(acc, p.x, p.y);
    this.game.flame?.glowInto(acc);
    /* and everybody in the building who is on fire, which is the light
       that moves — a torch running down an aisle lights it as it goes */
    this.game.fx?.glowInto(acc);
    sx = acc.sx; sy = acc.sy; sw = acc.sw;
    if (sw > 0.01) {
      world.fireLightPos.value.set(sx / sw, this.game.level.sectorAt(sx / sw, sy / sw)?.floor + 48 || 48, sy / sw);
      /* flicker, keyed to the tic so it is the same for everything */
      const flick = 0.86 + 0.14 * Math.sin(this.tics * 0.7) * Math.cos(this.tics * 0.31);
      world.fireLight.value = Math.min(1.8, Math.sqrt(sw) * 0.36) * flick;
      world.fireLightRange.value = 420 + Math.min(800, sw * 28);
    } else {
      world.fireLight.value *= 0.86;
    }
  }

  /* ------------------------------------------------------------------
     Drawing

     Two fixed pools of quads — flames and the smoke over them — parked
     on the hottest cells near the player each frame. There is no
     per-cell sprite object and nothing is created or destroyed while the
     store burns: with a whole aisle alight that would be hundreds of
     allocations a second for something nobody can distinguish from a
     hundred and sixty well-placed ones.

     WHAT CHANGED, AND WHY EACH PART OF IT

     ADDITIVE. One quad per cell, alpha-tested, gave a fire made of
     visible tiles: every flame was a hard-edged orange shape sitting in
     front of the next one, and two of them overlapping were no brighter
     than one. Fire does not work like that — light adds — and it is the
     adding that makes a mass of flame read as a source of light rather
     than as a picture of some flames. So the flame material is additive
     and writes no depth, and the soft edge that js/fireart.js always
     drew and the alpha test always threw away is finally being used for
     something.

     A CLUMP, NOT A FLAME. One sprite per cell puts one flame every
     thirty-two units on a grid, and a grid is exactly what you saw. Each
     cell now gets between one and three, scattered inside it and a
     little past it, at offsets hashed off the cell index and the slot —
     so the scatter is RANDOM but it is the SAME random every frame, and
     the fire does not boil. Everything that moves in it moves because
     the flame art is animating.

     BIG IN THE MIDDLE, SMALL AT THE EDGE. `core` is how surrounded by
     heat a cell is: the mean of its four neighbours' heat. A cell in the
     middle of a burning gondola has hot neighbours in every direction
     and gets three big flames off the top of the ladder; a cell on the
     advancing front has cold ones and gets a single small one. That is
     the shape of a real fire — a bright body with a ragged fringe — and
     it falls out of a number the simulation already has, so it costs
     four array reads. It picks the SET as well as the scale: the outer
     members of a clump come off the size below, so a small flame is
     genuinely a smaller drawing rather than a big one shrunk.

     AND SMOKE. See sprites.js for the art. It is parked over the cells
     with the highest core, at a height that rises with it, alpha-blended
     and NOT fullbright — so the one fire light in the game lights it
     from underneath, which is the whole look of smoke over a fire.
     ------------------------------------------------------------------ */
  /* Built on the first frame that draws, not in the constructor. The
     simulation is pure — a fuel grid and some integers — and coupling it
     to a scene graph at construction meant it could not be run or tested
     without a renderer, which is exactly backwards for the one system in
     the game whose behaviour over a thousand tics is worth checking. */
  _initSprites() {
    if (this.sprites) return;
    this.POOL = 192;
    this.SMOKE_POOL = 36;
    const geo = new THREE.PlaneGeometry(1, 1);
    geo.translate(0, 0.5, 0);
    this.sprites = [];
    for (let i = 0; i < this.POOL; i++) {
      const mat = createSpriteMaterial(null, { blend: 'add', fullbright: true, width: 32, height: 48 });
      const m = new THREE.Mesh(geo, mat);
      m.frustumCulled = false;
      m.visible = false;
      m.renderOrder = 10;                 // over the world, under the HUD
      this.game.scene.add(m);
      this.sprites.push(m);
    }
    this.smokes = [];
    for (let i = 0; i < this.SMOKE_POOL; i++) {
      /* Blended rather than added, because smoke SUBTRACTS what is
         behind it, and lit by the room rather than by itself, because
         the only thing that lights smoke here is the fire under it. */
      const mat = createSpriteMaterial(null, { blend: 'alpha', width: 64, height: 64 });
      const m = new THREE.Mesh(geo, mat);
      m.frustumCulled = false;
      m.visible = false;
      m.renderOrder = 9;                  // behind the flames
      this.game.scene.add(m);
      this.smokes.push(m);
    }
    /* WHICH CELL EACH PUFF IS SITTING OVER, kept between frames. The
       candidate list is rebuilt and re-sorted every frame as the fire
       moves, so dealing the pool off the front of it — which is what
       this did — handed puff number nine to a different cell most
       frames, and a puff that changes cell is a puff that TELEPORTS.
       Thirty-six of them doing that is the jitter the whole thing was
       accused of. A puff keeps its cell until that cell stops
       qualifying, and only then is it re-dealt. */
    this._smokeCell = new Int32Array(this.SMOKE_POOL).fill(-1);
    this._candidates = [];
  }

  /** How buried in the fire a cell is, 0 at the front and 1 in the
   *  middle of a blaze. The mean of the four neighbours' heat, guarded
   *  at the edges of the grid — the border ring has no sector and so
   *  never lights, but a guard is two comparisons and a NaN in a sprite
   *  scale is an invisible flame nobody could explain. */
  _core(i) {
    const h = this.heat, n = h.length, c = this.cols;
    const e = i + 1 < n ? h[i + 1] : 0, w = i > 0 ? h[i - 1] : 0;
    const s = i + c < n ? h[i + c] : 0, t = i >= c ? h[i - c] : 0;
    return (e + w + s + t) / 1020;
  }

  render(camX, camY, billboardRot) {
    this._initSprites();
    const bank = this.game.sprites;
    const cand = this._candidates;
    cand.length = 0;

    /* Nothing is drawn within arm's reach. A 32-unit flame at 20 units
       from the eye is a wall of orange with nothing behind it, and
       standing in a burning aisle put one of those over the whole
       screen — which reads as a bug rather than as being on fire. Doom's
       sprite clipping did the same thing for the same reason. You still
       take the damage; you just do not have a texture pressed against
       your face. */
    const NEAR2 = 46 * 46;

    /* Embers are drawn, because ground you have already burnt should
       still look like it — but only nearby, since a cold glow a thousand
       units off is one pixel and there can be thousands of them. */
    const EMBER_RANGE2 = 760 * 760;

    /* HOW FAR, AND AS WHAT. Out to FLAME_MID every burning cell is a
       candidate, thinned by a stable hash to about half of them near
       and a quarter further off, and each one that stays is drawn
       bigger than the cell it stands in — so a fire is a scatter of big
       flames with room between them rather than a carpet of small ones,
       and the same pool of quads reaches further down the street. Past
       FLAME_MID the cells are gathered into clumps of CLUMP cells on a
       side and each clump is ONE flame, sized by how much of it is
       alight: a handful of very big fires on the skyline, which is what
       a town on fire is from the far end of it. Nothing past the air's
       own reach, since the fog has already taken that. The first cut
       stopped dead at two thousand units, and a fire the next block
       over was a glow with nothing in it.

       The near ones are still not drawn in a region the eye cannot see
       into — the portal flood has run this frame (Level.visibleSectors);
       a fire behind a wall throws its light and its smoke and not its
       sprites. The far ones are: the flood is flat, and a fire behind a
       row of houses stands above their roofs. */
    const far = Math.min(FLAME_FAR, (climate.airFar || FLAME_FAR) * 0.96);
    const FAR2 = far * far, NEARF2 = FLAME_NEAR * FLAME_NEAR, MID2 = FLAME_MID * FLAME_MID;
    const lv = this.game.level, sectors = lv.sectors, seeInto = !!lv.isVisible;
    const clumps = this._clumps || (this._clumps = new Map());
    clumps.clear();
    const shift = Math.round(Math.log2(CLUMP));
    for (let k = 0; k < this.active.length; k++) {
      const i = this.active[k];
      const h = this.heat[i];
      if (h < 6) continue;
      const c = i % this.plane, cx = c % this.cols, cy = (c / this.cols) | 0;
      const x = this.worldX(cx), y = this.worldY(cy);
      const d2 = dist2(x, y, camX, camY);
      if (d2 > FAR2 || d2 < NEAR2) continue;
      if (d2 <= MID2) {
        if (seeInto) { const si = this.sectorOf[i]; if (si >= 0 && !lv.isVisible(sectors[si])) continue; }
        if (h < SPREAD_AT && d2 > EMBER_RANGE2) continue;
        const near = d2 <= NEARF2;
        if (hash2(i, 4242) > (near ? NEAR_ODDS : MID_ODDS)) continue;
        /* Nearest first, but weight by heat so a big fire further off
           still gets drawn ahead of an ember at your feet. */
        cand.push({ i, x, y, h, d2, core: this._core(i), boost: near ? 1.35 : 1.9, big: false, key: d2 / (0.35 + h / 255) });
      } else {
        if (h < SPREAD_AT) continue;
        const key = (((i / this.plane) | 0) * 8192 + (cy >> shift)) * 8192 + (cx >> shift);
        let g = clumps.get(key);
        if (!g) clumps.set(key, g = { i, sx: 0, sy: 0, w: 0, n: 0, h: 0 });
        const wt = h / 255;
        g.sx += x * wt; g.sy += y * wt; g.w += wt; g.n++;
        if (h > g.h) g.h = h;
      }
    }
    for (const g of clumps.values()) {
      const x = g.sx / g.w, y = g.sy / g.w;
      const d2 = dist2(x, y, camX, camY);
      /* first in the queue whatever the distance: there are never many
         and each one stands for a great deal of fire */
      cand.push({ i: g.i, x, y, h: g.h, d2, core: Math.min(1, g.n / 24), boost: 2.4 + Math.min(4.6, g.w * 0.14), big: true, key: -1e12 + d2 });
    }
    cand.sort((a, b) => a.key - b.key);

    /* --- the flames ------------------------------------------------- */
    /* HOW MUCH OF THE POOL TO SPEND. The sprites are sorted nearest and
       hottest first, so spending less of it drops the far, cold end —
       which is the right end to drop and is why the budget is a cap on
       the count rather than a filter on the candidates. */
    const pool = Math.max(16, Math.round(this.POOL * (this.game.quality?.effects ?? 1)));
    /* the same clock the smoke uses — a flame animating in thirty-five
       steps a second under a camera moving in sixty is the same jerk */
    const T0 = this.game.smoothTics ?? this.tics;
    let s = 0;
    for (let c = 0; c < cand.length && s < pool; c++) {
      const cd = cand[c];
      /* which flame: an ember, a fire, or a proper blaze — and the outer
         members of the clump come off the rung below */
      const rung = cd.big ? 2 : cd.h > 200 ? 2 : cd.h > 90 ? 1 : 0;
      /* HOW MANY. One — and two where the fire has closed over a cell
         within a few metres of you. The first cut spent up to three on
         every near cell, and the pool is fixed: three sprites a cell on
         the nearest fifty cells is a fire that stops dead halfway down
         the aisle while a thousand cells behind it are alight and
         undrawn. The thinning above is what puts the room between them,
         and the boost is what fills it. */
      const n = (!cd.big && rung > 0 && cd.core > 0.5 && cd.d2 < 300 * 300) ? 2 : 1;
      const sec = this.game.level.sectors[this.sectorOf[cd.i]];
      const floor = sec ? sec.floor : 0;
      for (let j = 0; j < n && s < this.POOL; j++, s++) {
        const m = this.sprites[s];
        const set = FLAME_SETS[Math.max(0, rung - (j > 0 ? 1 : 0))];
        /* however many frames the set has — js/fireart.js decides, and
           the fallback is only reached if the bank is empty */
        const letters = bank.count(set) || 8;
        /* Offset by the cell index AND the slot so neighbouring flames
           are out of step with each other — in phase, a wall of fire
           pulses like a heart. */
        const frame = String.fromCharCode(65 + (Math.floor(T0 * 0.5) + cd.i * 3 + j * 7) % letters);
        const entry = bank.get(set, frame);
        const u = m.material.uniforms;
        u.map.value = bank.texture(entry, 0);
        /* THE SAME RANDOM EVERY FRAME. Hashed off the cell and the slot,
           never off the clock: jitter that is re-rolled per frame is a
           fire that boils, and the only thing that should be moving in
           one of these is the drawing. */
        const a = hash2(cd.i, j) * Math.PI * 2;
        /* a flame stands a little off its cell's middle, in a direction
           and by a distance hashed off the cell, so a burning floor is
           a scatter and not a grid; a clump stands where its fire is */
        const r = cd.big ? 0 : j === 0 ? hash2(cd.i, 77) * CELL * 0.4 : (0.30 + hash2(cd.i, j + 64) * 0.75) * CELL * 0.9;
        const grow = j === 0 ? 1 : 0.52 + hash2(cd.i, j + 128) * 0.30;
        const sc = entry.scale * (0.7 + (cd.h / 255) * 0.75) * (0.95 + cd.core * 0.45) * grow * cd.boost * nearTaper(cd.d2);
        u.spriteScale.value.set(entry.w * sc, entry.h * sc);
        u.billboardRot.value = billboardRot;
        u.light.value = 1;
        m.position.set(cd.x + Math.cos(a) * r, floor, -(cd.y + Math.sin(a) * r));
        m.visible = true;
      }
    }
    for (; s < this.POOL; s++) this.sprites[s].visible = false;

    /* --- and the smoke over them ------------------------------------
       Over the BURIED cells only, and spread out along the candidate
       list rather than taken off the front of it: thirty-six puffs all
       on the nearest square metre of fire is a grey wall in your face,
       and the same thirty-six spaced down a burning aisle is a burning
       aisle. */
    /* WHO QUALIFIES: buried cells only, spread down the candidate list
       rather than taken off the front of it — thirty-six puffs all on
       the nearest square metre of fire is a grey wall in your face, and
       the same thirty-six spaced down a burning aisle is a burning
       aisle. */
    const fit = [];
    const stride = Math.max(1, Math.floor(cand.length / (this.SMOKE_POOL * 2)));
    for (let c = 0; c < cand.length; c += stride) {
      const cd = cand[c];
      if (cd.h >= 110 && cd.core >= 0.30) fit.push(cd);
    }
    /* EVERY PUFF KEEPS THE CELL IT HAD while that cell still qualifies,
       and the ones that lost theirs take from what is left over. Which
       is two passes and a small linear scan, against a pool of
       thirty-six — and it is the difference between smoke that drifts
       and smoke that flickers between places. */
    const byCell = new Map();
    for (const cd of fit) byCell.set(cd.i, cd);
    const taken = new Set();
    const mine = new Array(this.SMOKE_POOL).fill(null);
    for (let q = 0; q < this.SMOKE_POOL; q++) {
      const cell = this._smokeCell[q];
      const cd = cell >= 0 ? byCell.get(cell) : null;
      if (cd && !taken.has(cell)) { mine[q] = cd; taken.add(cell); }
    }
    let f = 0;
    for (let q = 0; q < this.SMOKE_POOL; q++) {
      if (mine[q]) continue;
      while (f < fit.length && taken.has(fit[f].i)) f++;
      if (f >= fit.length) break;
      mine[q] = fit[f]; taken.add(fit[f].i); f++;
    }

    /* THE CLOCK WITH THE FRACTION ON IT. The sway, the lift and the
       frame all used the whole tic count, which steps thirty-five times
       a second — so on a sixty-hertz monitor every drifting puff moved
       in visible jerks while the camera beside it was smooth. See
       Game.smoothTics. */
    const T = this.game.smoothTics ?? this.tics;
    for (let q = 0; q < this.SMOKE_POOL; q++) {
      const cd = mine[q];
      const m = this.smokes[q];
      this._smokeCell[q] = cd ? cd.i : -1;
      if (!cd) { m.visible = false; continue; }
      const letters = bank.count('SMOK') || 8;
      /* AND THE FRAME ROLLS RATHER THAN JUMPS. The set is a billowing
         loop, so it is walked at a steady rate off the smooth clock and
         phased by the cell — a puff eleven tics into holding one drawing
         is a puff you can see holding it. */
      const entry = bank.get('SMOK', String.fromCharCode(65 + (Math.floor(T * 0.16) + cd.i) % letters));
      const sec = this.game.level.sectors[this.sectorOf[cd.i]];
      const u = m.material.uniforms;
      u.map.value = bank.texture(entry, 0);
      const sc = entry.scale * (0.9 + cd.core * 1.1) * (cd.big ? cd.boost * 0.9 : 1) * nearTaper(cd.d2);
      u.spriteScale.value.set(entry.w * sc, entry.h * sc);
      u.billboardRot.value = billboardRot;
      /* Lit by the room and by the fire under it, and it leans: a slow
         sway off the cell's own phase, so a run of it is not a row of
         identical balls at identical heights. */
      u.light.value = sec ? Math.max(0.34, sec.light) : 0.5;
      if (u.sky) u.sky.value = sec ? (sec.sky ?? (sec.outdoor ? 1 : 0)) : 0;
      const ph = T * 0.014 + hash2(cd.i, 7) * 6.283;
      u.spriteOffset.value.set(Math.sin(ph) * 26, 0);
      const lift = 42 + cd.core * 150 + Math.sin(ph * 1.7) * 12;
      m.position.set(cd.x, (sec ? sec.floor : 0) + lift, -cd.y);
      m.visible = true;
    }
  }
}

/* The three sizes of flame, smallest first, so a clump can pick the rung
   below its own for the little ones round the edge. */
const FLAME_SETS = ['EMBR', 'FIRE', 'BLAZ'];

/* HOW FAR A FIRE IS DRAWN, and as what — see FireSystem.render. Every
   cell to FLAME_NEAR, about half of them drawn; fewer and bigger to
   FLAME_MID; one flame per clump of CLUMP cells on a side from there to
   FLAME_FAR or the air's reach, whichever is nearer. The odds are the
   share of cells that get a flame, and a cell that does not is not
   dark: its neighbour's flame is drawn bigger to stand over it. */
const FLAME_NEAR = 700, FLAME_MID = 1500, FLAME_FAR = 6000;
const CLUMP = 8;                            // cells on a side, which is 256 units
const NEAR_ODDS = 0.55, MID_ODDS = 0.28;

/* HOW MUCH SMALLER A FLAME GETS FOR BEING CLOSE.

   The same problem the particle system solved with `nearShrink`, arrived
   at from the other end. The near cull only refuses a flame within
   forty-six units of the eye, and it was written when a flame was a
   hundred and fifty units tall; a two-hundred-unit blaze on top of the
   gondola BESIDE you is a hundred and forty away, passes the cull, and
   covers half the screen. Standing in a burning aisle should be alarming
   and it should not be opaque.

   So a flame shrinks with its own distance, down to two fifths at the
   near cull, and is full size from about eight metres out. What that
   costs is a fire that is not perspective-correct at arm's length, which
   nobody can see; what it buys is that you can still find the door. */
const nearTaper = d2 => {
  const t = Math.sqrt(d2) / 280;
  return t > 1 ? 1 : t < 0.40 ? 0.40 : t;
};

/* A stable random per (cell, slot). Not pRandom: that is a stream, and a
   stream gives a different answer every frame, which is a flame that
   jumps about. Knuth's mix twice, which is enough to scatter a hundred
   and forty quads convincingly. */
function hash2(a, b) {
  let n = Math.imul(a | 0, 374761393) ^ Math.imul((b | 0) + 1, 668265263);
  n = Math.imul(n ^ (n >>> 13), 1274126177);
  return ((n ^ (n >>> 16)) >>> 0) / 4294967296;
}

/* Local copy so the fire's link pass does not import the whole of
   util's geometry section for one function. */
function segCross(ax, ay, bx, by, cx, cy, dx, dy) {
  const r1 = bx - ax, r2 = by - ay, s1 = dx - cx, s2 = dy - cy;
  const den = r1 * s2 - r2 * s1;
  if (Math.abs(den) < 1e-9) return -1;
  const t = ((cx - ax) * s2 - (cy - ay) * s1) / den;
  const u = ((cx - ax) * r2 - (cy - ay) * r1) / den;
  if (t < 0 || t > 1 || u < 0 || u > 1) return -1;
  return t;
}
