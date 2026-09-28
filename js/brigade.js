/* =====================================================================
   MEWD — the fire brigade
   =====================================================================

   A supermarket alight is the fire brigade's business, as the top of
   js/responders.js has said since there was a responders.js. TIERS has
   carried "the fire brigade" for as long, as a line in a table that sent
   nobody. This sends somebody, at the user's request: the user's fire
   truck (FireTruck in js/vehicles.js), with its water cannon working.
   It does not yet put firefighters on the ground; the truck is the whole
   of the brigade for now.

   WHAT CALLS THEM IS THE FIRE, not you: anything alight — the store, the
   wood, a car in the lot — for CALL_AFTER seconds, all told. The SWAT
   answer the trigger; the brigade answer the smoke. So a night with a
   gun in it and no fire has no fire engines, and a night of nothing but
   matches has nothing else.

   HOW MANY. One truck at the call, and then another every SEND_EVERY
   seconds for as long as something is still burning, up to one per
   CELLS_PER_TRUCK cells alight and never more than MAX_TRUCKS on the
   scene. A fire that is being won stops the sends; one that is being
   lost brings the whole station.

   WHERE THEY GO is where the fire is. The brigade picks the thickest
   part of whatever is burning (hotspot) and stands a truck as close to
   it as the tarmac allows, on the same ring and by the same arithmetic
   the SWAT use to come to you (Responders.chaseStand), keeping STOP back
   from it because a fire engine parked in the fire is a second fire. A
   fire INSIDE the building is fought from the fire lane, which is what a
   fire lane is: a truck takes a bay in front of the doors, and plays on
   whatever of it the doors let it see.

   THEY COME FROM THE FIRE STATION's end of the road — the town keeps its
   engines in the yard on A5 (see arrivalPoints in js/responders.js) —
   which here means whichever end of the road is the shorter drive to the
   stand, and they come on at the same run-in the SWAT do, out of your
   view, so a truck does not appear in front of you.
   ===================================================================== */

import { TICRATE } from './util.js';
import { FireTruck } from './vehicles.js';

export const BRIGADE = {
  key: 'fire',
  callAfter: 8 * TICRATE,          // tics of anything alight before the call
  sendEvery: 40 * TICRATE,         // between trucks while it is still burning
  cellsPerTruck: 60,               // how much fire one truck is for
  maxTrucks: 4,                    // and never more than this on the scene
  bays: 9,                         // the fire lane, shared with the SWAT
  /* the stand, in the units Responders.chaseStand takes: how far apart
     two trucks park, how far off the road they will drive, and how far
     short of the fire they stop */
  stand: 620, push: 6000, stop: 520,
  /* and how far the cannon can actually work, which is what makes a
     stand worth having — see hoseReach in js/water.js */
  reach: 1150,
};

/* The row the rest of the responders' machinery reads a force by. */
const FORCE = { def: { key: 'fire', name: 'the fire brigade', model: 'firetruck', Van: FireTruck }, num: BRIGADE };

export class FireBrigade {
  constructor(game) {
    this.game = game;
    this.alight = 0;             // tics anything has been burning, all told
    this.called = false;
    this.calledAt = -1;
    this.nextAt = -1;
    this.sent = 0;
    this.trucks = [];
    this.force = FORCE;
  }

  /** How much is burning, in cells: the store's, the wood's, and a
   *  vehicle alight counted as a patch of each. */
  get burning() {
    const g = this.game;
    let n = (g.fire?.burningCells || 0) + (g.forest?.burningCells || 0);
    for (const v of g.vehicles?.all || []) if (v.whole && v.burning > 0) n += 12;
    /* and the grid world's boxes, which are the only fuel it has — a
       burning box counts for about what a burning car does, so the
       same numbers below mean the same size of fire in both worlds */
    n += (g.boxes?.burningCount || 0) * 12;
    return n;
  }

  get liveTrucks() { return this.trucks.filter(v => v.whole); }

  /** How many trucks this much fire wants on the scene. */
  capFor(cells) { return Math.max(1, Math.min(BRIGADE.maxTrucks, Math.ceil(cells / BRIGADE.cellsPerTruck))); }

  tic() {
    const g = this.game;
    if (!g.firetruck) return;
    const cells = this.burning;
    if (cells > 0) this.alight++;
    if (!this.called) {
      if (this.alight < BRIGADE.callAfter) return;
      this.called = true;
      this.calledAt = g.tics;
      this.nextAt = g.tics;
      g.sound?.play('firehorn', null);
      g.onResponders?.('called', FORCE.def);
    }
    if (g.tics < this.nextAt || cells <= 0) return;
    if (this.liveTrucks.length >= this.capFor(cells)) return;
    if (this.send()) this.nextAt = g.tics + BRIGADE.sendEvery;
    else this.nextAt = g.tics + TICRATE;            // nowhere to stand yet; ask again shortly
  }

  /** The thickest part of what is burning: of a handful of burning
   *  points, the one with the most of the others near it. */
  hotspot() {
    const g = this.game, pts = [];
    const F = g.fire;
    if (F && F.hotCells > 0) {
      const act = F.active, step = Math.max(1, Math.floor(act.length / 48));
      for (let k = 0; k < act.length; k += step) {
        const i = act[k];
        if (F.heat[i] < 40) continue;
        const j = i % F.plane;
        pts.push({ x: F.worldX(j % F.cols), y: F.worldY((j / F.cols) | 0) });
      }
    }
    const W = g.forest;
    if (W && W.burningCells > 0) {
      const out = [];
      const p = g.player || { x: 0, y: 0 };
      W.emitters(p.x, p.y, 1e6, 24, out);
      for (const e of out) pts.push({ x: e.x, y: e.y });
    }
    for (const v of g.vehicles?.all || []) if (v.whole && v.burning > 0) for (let k = 0; k < 4; k++) pts.push({ x: v.x, y: v.y });
    for (const b of g.boxes?.burningList(this._lit || (this._lit = [])) || []) for (let k = 0; k < 3; k++) pts.push({ x: b.x, y: b.y });
    if (!pts.length) return null;
    let best = pts[0], bn = -1;
    for (const a of pts) {
      let n = 0;
      for (const b of pts) if ((a.x - b.x) ** 2 + (a.y - b.y) ** 2 < 450 * 450) n++;
      if (n > bn) { bn = n; best = a; }
    }
    return best;
  }

  /**
   * THE FIRES IT COULD GO TO, best first.
   *
   * The thickest of it is the right answer when a truck can reach the
   * thickest of it. In a field of solid boxes (js/maps/grid.js) it
   * often cannot: the middle of a block is behind three other boxes and
   * a truck that drives at it stops at the first one, half the field
   * out, and then stands there with nothing in its reach — which is
   * what it did. So the thickest is only the FIRST thing tried, and
   * behind it come the burning boxes nearest the road, which is the
   * fire a real brigade takes first for the same reason: it is the one
   * they can get a truck to.
   */
  targets() {
    const g = this.game, R = g.responders, out = [];
    const hot = this.hotspot();
    if (hot) out.push(hot);
    if (R?.ring) {
      const lit = g.boxes?.burningList(this._lit || (this._lit = [])) || [];
      lit.slice()
        .sort((a, b) => this._toRoad(a) - this._toRoad(b))
        .slice(0, 5)
        .forEach(b => out.push({ x: b.x, y: b.y, box: b.box }));
    }
    return out;
  }

  /** How far a point is from the ring, which is how hard it is to
   *  get a truck to. */
  _toRoad(p) {
    const R = this.game.responders;
    const on = R.ringAt(R.ringNearest(p.x, p.y));
    return Math.hypot(on.x - p.x, on.y - p.y);
  }

  /**
   * A STAND ON ONE OF THE MAP'S OWN STREETS, for a map that has them —
   * see `lanes` in js/maps/grid.js. The nearest point on any street to
   * the fire that a truck can work from: nothing else standing there,
   * the fire inside the cannon's reach, and the fire visible over the
   * jet's shoulder. The truck drives the ring to the near end of that
   * street and then down it, which is `lead`.
   */
  laneStand(at) {
    const R = this.game.responders, lv = this.game.level;
    const lanes = lv.lanes;
    if (!lanes || !lanes.length) return null;
    const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
    let best = null, bd = Infinity;
    for (const L of lanes) {
      const x = L.axis === 'y' ? L.at : clamp(at.x, L.from, L.to);
      const y = L.axis === 'y' ? clamp(at.y, L.from, L.to) : L.at;
      const d = Math.hypot(at.x - x, at.y - y);
      if (d > BRIGADE.reach || d < 120) continue;
      if (d >= bd) continue;
      const s = { x, y, ring: 0, angle: Math.atan2(at.y - y, at.x - x), lead: [], works: true };
      if (!R.standClear(s, BRIGADE)) continue;
      /* what a hose is actually pointed at — the burning FACE, which is
         outside the solid; a box's middle is inside one and can never
         be seen. See Box.aimPoint in js/boxes.js. */
      const aim = at.box ? at.box.aimPoint(x, y) : { x: at.x, y: at.y, z: 0 };
      const fz = (lv.sectorAt(x, y)?.floor ?? 0) + 110;
      if (lv.sightBlocked(x, y, fz, aim.x, aim.y, (lv.sectorAt(aim.x, aim.y)?.floor ?? 0) + aim.z + 20)) continue;
      /* in at whichever end of the street is nearer, and down it */
      const ends = L.axis === 'y'
        ? [{ x: L.at, y: L.from }, { x: L.at, y: L.to }]
        : [{ x: L.from, y: L.at }, { x: L.to, y: L.at }];
      const mouth = Math.hypot(ends[0].x - x, ends[0].y - y) <= Math.hypot(ends[1].x - x, ends[1].y - y) ? ends[0] : ends[1];
      s.ring = R.ringNearest(mouth.x, mouth.y);
      s.lead = [mouth, { x, y }];
      bd = d; best = s;
    }
    return best;
  }

  /** Where the next truck stands, for a fire at `at`. */
  standFor(at) {
    const R = this.game.responders, lv = this.game.level;
    if (!R?.ring) return null;
    const onLane = this.laneStand(at);
    if (onLane) return onLane;
    const sec = lv.sectorAt(at.x, at.y);
    if (sec && !sec.outdoor) {
      /* INDOORS: the fire lane. A bay first, and when they are gone,
         along the ring by the doors like everybody else. */
      const bay = R.freeBay(FORCE);
      if (bay) return R.bayStand(bay);
      at = R.doorsPoint() || at;
    }
    /* THE ONE IT CAN WORK FROM, not simply the nearest. A stand is no
       use to a fire truck if the fire is not in the water's reach or is
       behind something solid — and in a field of boxes (js/maps/grid.js)
       most of the ring is behind something. So every slot is walked, a
       stand that can SEE the fire and reach it beats one that cannot,
       and among those the nearest wins. A world with nothing in the way
       is unchanged by this: every stand sees the fire and the nearest
       is still the answer. */
    let best = null, bd = Infinity, bw = false;
    for (let k = 0; k <= 16; k++) {
      const slot = k === 0 ? 0 : (k & 1 ? (k + 1) >> 1 : -(k >> 1));
      const s = R.chaseStand(at, slot, BRIGADE);
      if (!R.standClear(s, BRIGADE)) continue;
      /* and never ON the fire: a truck parked in it is a second fire */
      if ((this.game.fire?.heatAt(s.x, s.y) || 0) > 0) continue;
      const d = Math.hypot(s.x - at.x, s.y - at.y);
      const works = d < BRIGADE.reach && !lv.sightBlocked(s.x, s.y, (lv.sectorAt(s.x, s.y)?.floor || 0) + 110, at.x, at.y, (lv.sectorAt(at.x, at.y)?.floor || 0) + 40);
      if (bw && !works) continue;
      if (works && !bw) { bw = true; bd = Infinity; }
      if (d < bd) { bd = d; best = s; s.works = works; }
      if (bw && bd <= BRIGADE.stop + 36) break;
    }
    return best;
  }

  /** One truck on the road, to the fire. */
  send() {
    const g = this.game, R = g.responders, model = g.firetruck;
    if (!model || !R) return null;
    /* the thickest of it first, and then the fires a truck can
       actually get to — see targets() */
    let at = null, stand = null;
    for (const t of this.targets()) {
      const s = this.standFor(t);
      if (!s) continue;
      at = t; stand = s;
      if (s.works) break;
    }
    if (!stand) return null;
    const side = R.sideFor(stand.ring);
    const route = R.routeTo(stand, side, 0, true);
    if (!route) return null;
    const v = new FireTruck(g.vehicles, model.def, model.texture, route);
    v.parkAngle = route[route.length - 1].angle;
    v.stand = stand;
    v.bay = stand.bay || null;
    v.side = side;
    v.force = FORCE;
    g.vehicles.addVehicle(v);
    /* in the responders' list, so a SWAT van does not park on it and
       it does not park on one — but never unloaded: nobody's force
       loop matches FORCE */
    R.vans.push(v);
    this.trucks.push(v);
    this.sent++;
    g.onResponders?.('van', v);
    return v;
  }
}
