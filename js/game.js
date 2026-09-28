/* =====================================================================
   MEWD — the game
   =====================================================================

   Holds the level, the actors, the fire and the player, and runs the
   world at a fixed 35 Hz whatever the renderer is doing.

   THE FIXED TIMESTEP IS NOT NEGOTIABLE. Every duration in the state
   tables is in tics; every movement constant is per tic. Run the world
   off the frame time and a monster's walk cycle changes speed with the
   framerate, a door opens faster on a better machine, and the physics
   constants stop meaning what they say. So the frame time goes into an
   accumulator and the world steps in whole tics, with the leftover
   carried forward. The RENDERER can run at whatever rate it likes; the
   world runs at 35, on every machine, for ever.

   The catch-up is capped at six tics. A tab that has been in the
   background for a minute should not try to simulate a minute of
   supermarket the instant it comes back.
   ===================================================================== */

import * as THREE from 'three';
import { TICRATE, PLAYER_EYE, angleNorm, angleDiff, dist, dist2, pRandom, clamp } from './util.js';
import { Level, VIS_FAR } from './level.js';
import { buildLevelGeometry, INTERIOR_DIST } from './mapgeo.js';
import { Actor, ACTIONS, ActorGrid } from './actor.js';
import { ACTORS } from './states.js';
import { Player } from './player.js';
import { FireSystem } from './fire.js';
import { world } from './material.js';
import { charredName, guttedSurfaces, collapsedSurfaces } from './textures.js';
import { assignLineTextures } from './level.js';
import { createSpriteMaterial } from './material.js';
import { buildSlideDoors } from './slidedoor.js';
import { buildSky, followSky } from './sky.js';
import { Forest } from './forest.js';
import { FlameStream } from './flame.js';
import { Decals, wallNormal, UP, DOWN, bleeds } from './decals.js';
import { LocalSession } from './net/session.js';
import { Tracers } from './tracers.js';
import { BeamSystem } from './beam.js';
import { BreachSystem } from './breach.js';
import { FrostStream } from './frost.js';
import { WaterStream } from './water.js';
import { FireBrigade } from './brigade.js';
import { Boxes } from './boxes.js';
import { Effects, SMOKE_PUFFS } from './effects.js';
import { Giblets } from './people.js';
import { Responders } from './responders.js';
import { Gunships } from './vtol.js';
import { StreetLights } from './lamplight.js';
import { Standees } from './standees.js';
import { Vehicles } from './vehicles.js';
import { BoreSystem } from './bore.js';
import { MissileSystem } from './missiles.js';
import { ArcSystem } from './arc.js';
import { Weather, climate, CLEAR_FAR } from './weather.js';
import { Rain } from './rain.js';

const THING_TO_ACTOR = {
  SHOPPER: 'SHOPPER', TOWNIE: 'TOWNIE',
  TROLLEY: 'TROLLEY', BOLLARD: 'BOLLARD',
  FUELCAN: 'FUELCAN', CRATE: 'CRATE', LAMP: 'LAMP',
  /* the town's furniture — see js/maps/town.js */
  STREETLAMP: 'STREETLAMP', GRAVESTONE: 'GRAVESTONE',
};

/* How far a fitting throws light and how much it is worth at the source.
   340 is a little over one grid step, so every point on the shop floor is
   reached by two or three of them and losing one is a noticeable dent
   rather than a blackout — until you shoot out the neighbours too. */
/* HOW OFTEN THE BURN PICTURE GOES TO THE GPU, in tics. Three of them is
   about twelve hertz; see ticBurnGrid for why it is not thirty-five. */
/* HOW LONG ONE OF THE GUN'S NOTICES STAYS UP, and how many of them can
   be up at once. Six seconds is long enough to still be readable when
   the next shot's line arrives under it, which is what makes the stack
   worth having: at seven seconds a charge you can see what the last two
   or three shots did at the same time as taking the next one. Four at
   once is a cell's worth and then some. */
export const TOAST_LIFE = 6 * TICRATE;
export const TOAST_MAX = 4;

const BURN_UPLOAD_EVERY = 3;
const LAMP_RANGE = 340;
const LAMP_GAIN = 0.30;

export class Game {
  constructor({ level, scene, camera, textures, sprites, hud, audio, input, sky, flameAtlas, bodyAtlas, fxAtlases, gibAtlases, rainAtlas, fleet, police, apc, firetruck, vtol, weather }) {
    this.level = level;
    this.scene = scene;
    this.camera = camera;
    this.textures = textures;
    this.sprites = sprites;
    this.hud = hud;
    this.sound = audio;
    this.input = input;
    /* where the player's command each tic comes from: this page, until
       a host (js/net/server.js) says otherwise */
    this.session = new LocalSession();
    /* EVERYBODY WITH A PAIR OF HANDS IN THIS WORLD. One in a game on
       its own — `player`, the one this screen looks out of — and one a
       client on a host (js/net/match.js), each with its own session.
       A player with no session of its own is driven by the game's. */
    this.players = [];
    /* AND THE RULES THAT HOLD BETWEEN THEM, when there is more than
       one: a match (js/net/match.js) sets this, and a game on its own
       has none — which is every check below costing nothing. */
    this.rules = null;
    /* set by a host to wind the others back to what a shooter saw
       before its tic, and forward again after — see SimServer.rewind */
    this.rewind = null;

    this.actors = [];
    this.projectiles = [];
    this.lamps = [];
    this.doors = [];
    /* ------------------------------------------------------------------
       WHAT TO SPEND THE FRAME ON

       Three dials, all of them 1 by default and all of them honoured by
       whoever can honour them rather than by a branch here: the crowd is
       how many standees are drawn, effects is how much of the fire's
       sprite pool gets used, and wood is how far into the trees the
       chunks are kept. The pause menu sets them (see js/main.js) and the
       simulation never reads them — the shop is the same shop at every
       setting, it is only the drawing that is cheaper.
       ------------------------------------------------------------------ */
    this.quality = { crowd: 1, effects: 1, wood: 1 };
    /* HOW MANY ROWS OF PIXELS THE PICTURE HAS, set by js/main.js from
       the pipeline's GRID each frame. It is what tells the geometry LOD
       how big a pixel is — see minSolidFor in js/mapgeo.js — and it
       defaults to the tallest grid, which is the setting that drops the
       least, so anything that never sets it loses nothing. */
    this.viewRows = 960;
    /* THE HOUR AND THE WEATHER — see js/weather.js. Ticked with the
       world, applied with the frame; everything about the atmosphere
       is set from it and nothing else touches those uniforms. */
    this.weather = weather || new Weather();
    this.tics = 0;
    this.accum = 0;
    this.paused = false;
    this.state = 'play';           // play | dead | won
    this.bigMessage = null;
    this.bigMessageTics = 0;
    /* the gun's own notices, newest last — see toast() */
    this.toasts = [];
    this.totalMonsters = 0;

    /* Before anything is spawned: every actor puts itself into this on
       the way out of its constructor. See ActorGrid in js/actor.js for
       why the crowd needs one. */
    this.blockmap = new ActorGrid();

    const geo = buildLevelGeometry(level, textures);
    this.geo = geo;
    scene.add(geo.group);

    this.lamps = [];
    this.spawnThings();
    this.relight();
    this.geo.rebuildStatic();          // with the lamps' light in it
    /* after relight, because a car's light is baked into it the same way
       a wall's is, and it should be the light the bay ended up with */
    this.vehicles = new Vehicles(this, fleet?.texture || null, fleet?.def || null)
      .place(this.level.carSlots);
    this.slideDoors = buildSlideDoors(this);
    /* the sky is a picture the page bakes (js/skyart.js) and hands in as
       a texture; without one (the smoke test) there is simply no sky,
       and nothing else minds */
    this.sky = sky ? buildSky(sky) : null;
    if (this.sky) scene.add(this.sky);
    this.fire = new FireSystem(this);
    /* and what falls out of the sky when the weather says so */
    this.rain = new Rain(this, rainAtlas || null);

    /* The wood round the outside, the flame out of the gun, and what
       rises off anything burning. All three simulate without a renderer;
       they only draw once handed the pictures to draw with. */
    this.forest = new Forest(level);
    this.flame = new FlameStream(this, flameAtlas || null);
    /* and the other stream, which uses the smoke puffs rather than the
       flame frames — a jet of CO2 is a cloud, not a fire */
    this.frost = new FrostStream(this, fxAtlases?.smoke ? { texture: fxAtlases.smoke, frames: SMOKE_PUFFS } : null);
    /* and the fire brigade's, out of the truck's cannon — see js/water.js */
    this.water = new WaterStream(this, fxAtlases?.smoke ? { texture: fxAtlases.smoke, frames: SMOKE_PUFFS } : null);
    /* `bodyAtlas` is the tall flame the wood carries and the gun's
       muzzle wears, and it is what a person on fire is drawn with — the
       stream's fireballs are the wrong shape for something standing up.
       See Effects.bodyFire. */
    this.fx = new Effects(this, fxAtlases || null, bodyAtlas || null);
    /* and what comes off a person: the pieces and the fire on them */
    this.giblets = new Giblets(this, gibAtlases || null);
    /* and what the weapons leave on the walls: holes, hot spots, rime.
       Data always; pictures only where there are pictures. */
    this.decals = new Decals(this);
    if (fxAtlases) this.decals.attach(scene);
    /* and the minigun's tracers, a streak from the muzzle to the hit */
    this.tracers = new Tracers(this);
    if (fxAtlases) this.tracers.attach(scene);
    /* THE LANCE'S COLUMN, which is not a streak and not a projectile: a
       tube of light from the muzzle to the far side of the map that is
       out for seconds at a time and deletes what it crosses. It has no
       tic() of its own in this list — js/player.js drives it, because a
       beam only exists for as long as a trigger has been released and
       that is the player's business. See js/beam.js. */
    this.beam = new BeamSystem(this);
    if (fxAtlases) this.beam.attach(scene);
    /* AND THE HOLES IT USED TO LEAVE IN THINGS. A wall with a piece
       blown out of it is geometry and not a decal — see js/breach.js —
       so this owns the punching, the crumbling and the debris, and the
       rebuild goes through markBreached below. THE LANCE NO LONGER
       PUNCHES, at the user's request: it leaves a sear where it lands
       and changes nothing about the level (see js/beam.js). The system
       stays, with nothing calling it, because everything that reads a
       hole still does. */
    this.breaches = new BreachSystem(this);
    /* where the last hitscan stopped, for a tracer to be drawn to */
    this.lastHit = { x: 0, y: 0, z: 0 };
    if (flameAtlas) this.flame.attach(scene);
    if (fxAtlases) { this.frost.attach(scene); this.water.attach(scene); this.fx.attach(scene); }
    if (gibAtlases) this.giblets.attach(scene);
    if (rainAtlas) this.rain.attach(scene);
    this.weapon3d = null;
    /* who the night brings, in the order the user set: the SWAT in the
       user's van from your first shot, and the army in the user's hover
       APC three minutes later — see FORCES in js/responders.js, which
       names these two fields and reads them by name. Each is a model
       and a sheet, and without one that force never arrives. */
    this.police = police || null;
    this.apc = apc || null;
    this.responders = new Responders(this);
    /* AND THE FIRE BRIGADE, which the fire calls rather than you: the
       user's fire truck and its water cannon — see js/brigade.js */
    this.firetruck = firetruck || null;
    this.brigade = new FireBrigade(this);
    /* AND THE THINGS THAT BURN, in the world that has them: the grid's
       boxes (js/boxes.js), which are the only fuel there is when the
       cell grid is switched off. The fire system is handed them so that
       every weapon in the game lights one without knowing they exist —
       see the top of FireSystem.ignite. */
    this.boxes = new Boxes(this, (this.level.boxes?.length && this.textures?.get('GRIDBOX')?.texture) || null);
    this.fire.boxes = this.boxes;
    this.boxes.attach(scene);
    /* AND THE AIR SUPPORT THAT COMES WITH THE ARMY: the user's VTOL
       gunship, sent by the wing the tic the army is called — see
       js/vtol.js. Without the model there is no air support, which is
       the same bargain every other asset makes. */
    this.gunships = new Gunships(this, vtol || null);
    /* THE STREET LAMPS' LIGHT: the flare at every luminaire after dark.
       The lamps themselves are geometry (js/mapgeo.js) and things (for
       their radius); this is the part of them that is on. */
    this.streetLights = new StreetLights(this);
    this.streetLights.setLamps(level);
    if (scene) this.streetLights.attach(scene);
    /* THE CROWD, BATCHED BY PICTURE. Every sprite in the game goes
       through this rather than owning a mesh — see js/standees.js. */
    this.standees = new Standees(this);
    if (scene) this.standees.attach(scene);
    this.idle = false;                 // the title: the world stands still and the eye wanders
    this._nozzle = { x: 0, y: 0, z: 0 };
    this._scared = [];                 // scratch for Game.scare
    this._initBurnGrid();

    /* the flame the player is holding, and everything else that needs a
       quad but is not an actor */
    this._projGeo = new THREE.PlaneGeometry(1, 1);
    this._projGeo.translate(0, 0.5, 0);
    /* and the cerebral bore: its sight, its lock and what it fires —
       after the quad above, which it draws with */
    this.bore = new BoreSystem(this);
    /* and the quad launcher's seeker and its missiles, on the same terms */
    this.missiles = new MissileSystem(this);
    /* and the arc maw's lightning — see js/arc.js */
    this.arc = new ArcSystem(this);
  }

  get burnPercent() { return this.fire ? this.fire.burnFraction * 100 : 0; }
  get forestPercent() { return this.forest ? this.forest.burnFraction * 100 : 0; }

  /** How many of them are still alive, anywhere. On the status bar
   *  because the shop now has six fire exits in it and most of the crowd
   *  leaves through them: the number that matters once the building is
   *  going is not how much of it has burnt, it is how many are still
   *  out there. Counted rather than kept, because a count is one pass
   *  over a list a few times a second and a tally is a thing to get
   *  wrong in six places. */
  get peopleLeft() {
    let n = 0;
    for (const a of this.actors) if (a.type === 'SHOPPER' && !a.dead && !a.removed) n++;
    return n;
  }

  /** Where the flame is born: the end of the gun as drawn, if there is
   *  one, else a point low and right of the eye — which is where the
   *  drawn one is anyway. Game coordinates. */
  nozzle(p = this.player) {
    const o = this._nozzle;
    if (p === this.player && this.weapon3d && this.weapon3d.nozzleWorld(this.camera, o)) return o;
    const c = Math.cos(p.angle), s = Math.sin(p.angle);
    o.x = p.x + c * 18 + s * 9;
    o.y = p.y + s * 18 - c * 9;
    o.z = p.viewZ - 9;
    return o;
  }

  /* ------------------------------------------------------------------
     Populating
     ------------------------------------------------------------------ */
  spawnThings() {
    for (const t of this.level.things) {
      if (t.type === 'START') {
        this.player = new Player(this, t.x, t.y, t.angle);
        this.players.push(this.player);
        /* A START ON AN UPPER LAYER of an edited map: in the storey at
           its height, not the ground under it — a hair over the deck,
           which is the ceiling of the room under it as well */
        if (t.z !== undefined && this.player.sector) {
          this.player.sector = this.level.spanIn(this.player.sector, t.z + 1);
          this.player.z = this.player.sector.floor;
        }
        continue;
      }
      const type = THING_TO_ACTOR[t.type];
      if (!type) { console.warn('unknown thing type', t.type); continue; }
      /* Lights are laid on a grid over the whole map; the ones that fell
         outdoors, into a doorway, or under a low ceiling are dropped
         here rather than described twice in the map file. */
      if (type === 'LAMP' && !t.placed) {
        const sec = this.level.sectorAt(t.x, t.y);
        if (!sec || sec.outdoor || sec.ceil < 200) continue;
      }
      const a = new Actor(this, type, t.x, t.y, t.angle, t.z !== undefined ? { variant: t.variant, z: t.z + 1 } : { variant: t.variant });
      this.actors.push(a);
      if (a.monster) this.totalMonsters++;
      /* A light is kept for relight() and for nothing else: it has no
         state, so it draws nothing, and the fitting you see above it is
         painted into the ceiling texture. */
      if (type === 'LAMP') this.lamps.push(a);
    }
    if (!this.player) throw new Error('map has no START');
  }

  spawn(type, x, y, z, opts = {}) {
    const a = new Actor(this, type, x, y, opts.angle || 0, opts);
    if (z !== undefined) a.z = z;
    this.actors.push(a);
    return a;
  }

  spawnPuff(x, y, z) { this.spawn('PUFF', x, y, z); }


  /* ------------------------------------------------------------------
     Light that comes from somewhere

     A sector's brightness is its own ambient — emergency lighting,
     whatever comes through the front — plus every working fitting that
     can see it. Which means shooting one out genuinely takes light away,
     and a fire working its way along a run of them puts an aisle out
     one section at a time.

     The reach test is done NEAR THE CEILING on purpose. Walls run floor
     to ceiling and stop it, so light does not pass between rooms; but a
     gondola is only 80 tall and the ceiling is 352, so light passes over
     the shelves into the next aisle, which is what light does.
     ------------------------------------------------------------------ */
  /**
   * Sample points across a sector, so its brightness is an AVERAGE over
   * its area rather than the value at one arbitrary place in it.
   *
   * The first version measured each lamp against the nearest point of
   * the sector's bounding box, which for a 600-unit aisle is distance
   * zero from every fitting along its length — so every sector summed
   * four or five lamps at full strength, clamped to 1.0, and shooting
   * them out changed nothing anywhere. A long room is not close to a
   * lamp; parts of it are.
   */
  _sectorSamples(s) {
    if (s._samples) return s._samples;
    const [x0, y0, x1, y1] = s.bbox;
    const nx = Math.min(3, Math.max(1, Math.round((x1 - x0) / 220)));
    const ny = Math.min(3, Math.max(1, Math.round((y1 - y0) / 220)));
    const pts = [];
    for (let i = 0; i < nx; i++)
      for (let j = 0; j < ny; j++)
        pts.push([x0 + (x1 - x0) * ((i + 0.5) / nx), y0 + (y1 - y0) * ((j + 0.5) / ny)]);
    s._samples = pts;
    return pts;
  }

  /**
   * Which lamps can possibly reach a point.
   *
   * The naive version — every sector against every lamp — is fine in a
   * corner shop and quadratic everywhere else. A store with two hundred
   * and fifty fittings and two hundred and fifty sectors is sixty
   * thousand sight tests per relight, and a relight happens every time a
   * fire takes out a run of lights, which is constantly.
   *
   * So the lamps go in a uniform grid whose cell is exactly LAMP_RANGE.
   * Nothing outside the nine cells around a point can be within range of
   * it, by construction, and the nine cells hold four or five fittings
   * instead of two hundred and fifty. It is Doom's blockmap applied to
   * light, which is what a blockmap is for.
   */
  _buildLampGrid() {
    const cell = LAMP_RANGE;
    const g = new Map();
    for (const lamp of this.lamps) {
      if (lamp.dead || lamp.removed) continue;
      const k = Math.floor(lamp.x / cell) + ',' + Math.floor(lamp.y / cell);
      let b = g.get(k);
      if (!b) g.set(k, b = []);
      b.push(lamp);
    }
    this._lampGrid = g;
    this._lampCell = cell;
  }

  relight() {
    const L = this.level;
    this._buildLampGrid();
    const cell = this._lampCell, grid = this._lampGrid;
    const near = [];
    for (const s of L.sectors) {
      if (s.outdoor) { s.light = s.ambient; continue; }
      const pts = this._sectorSamples(s);
      let total = 0;
      for (const [px, py] of pts) {
        near.length = 0;
        const gx = Math.floor(px / cell), gy = Math.floor(py / cell);
        for (let j = -1; j <= 1; j++)
          for (let i = -1; i <= 1; i++) {
            const b = grid.get((gx + i) + ',' + (gy + j));
            if (b) for (let k = 0; k < b.length; k++) near.push(b[k]);
          }
        for (const lamp of near) {
          const d = Math.hypot(px - lamp.x, py - lamp.y);
          if (d >= LAMP_RANGE) continue;
          const tz = Math.min(s.ceil - 8, lamp.z);
          if (d > 1 && L.sightBlocked(lamp.x, lamp.y, lamp.z, px, py, tz)) continue;
          total += LAMP_GAIN * Math.pow(1 - d / LAMP_RANGE, 1.2);
        }
      }
      s.light = Math.min(1, s.ambient + total / pts.length);
    }
  }

  onLampDestroyed(lamp) {
    /* GLASS, A POP, AND A SHOWER OF SPARKS THAT FALLS. This is the whole
       of what a light going out looks like up close — the fitting itself
       is paint in the ceiling and cannot change — and it used to be
       A_LampBurst on a three-tic death state. There is no death state
       any more, so it happens here, which is the one place that knows a
       light has gone. */
    this.sound?.play('lampbreak', lamp);
    this.spawnSparks(lamp.x, lamp.y, lamp.z + 10, 10 + (pRandom() & 7));
    /* And the rest of what it looks like is the aisle going dark.
       Relighting walks every lamp against every sector, so it is not
       done per lamp — a fire takes out a whole run of them within a
       second or two and one rebuild covers the lot. */
    this._geoDirty = true;
    this._geoAt = this.tics + 10;
  }

  /** What comes out of a light when it goes: bright, brief, and it falls. */
  spawnSparks(x, y, z, n) {
    for (let i = 0; i < n; i++) {
      const a = (pRandom() / 255) * Math.PI * 2;
      const sp = 0.8 + (pRandom() / 255) * 4.2;
      this.projectiles.push({
        kind: 'SPARK', x, y, z,
        vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, vz: -(0.4 + (pRandom() / 255) * 1.8),
        gravity: -0.85, owner: null, life: 16 + (pRandom() & 15),
        sprite: 'SPRK', frame: 'A', mesh: null, damage: 0,
      });
    }
  }

  /* ------------------------------------------------------------------
     One tic of the world
     ------------------------------------------------------------------ */
  update(dt) {
    /* A MATCH DOES NOT PAUSE: the host's world goes on whether this page
       is looking or not, so the tics go on too — with the hands off
       (NetSession sends nothing but standing still while the menu is up) */
    if (this.paused && !this.net) {
      /* Still listen. A pause that stops sampling the pause key is a
         door with no handle on the inside. */
      this.input.sample(1 / TICRATE);
      if (this.input.pausePressed) this.setPaused(false);
      return;
    }
    this.accum += dt;
    const step = 1 / TICRATE;
    let n = 0;
    while (this.accum >= step && n < 6) { this.tic(); this.accum -= step; n++; }
    if (n === 6) this.accum = 0;          // we are behind; drop the debt
  }

  /* THE CLOCK, WITH THE FRACTION STILL ON IT. `tics` is a whole number
     that steps thirty-five times a second; the renderer runs at whatever
     the monitor does, so anything drawn off `tics` alone moves in
     thirty-five steps a second however smooth the frame rate is. The
     accumulator already holds the part of a tic that has gone by since
     the last step, so adding it back gives a continuous time in tics —
     which is what a drifting, swaying thing wants and what a thing
     driven by the simulation must NOT have. */
  get smoothTics() { return this.tics + this.accum * TICRATE; }

  tic() {
    this.tics++;
    this.input.sample(1 / TICRATE);

    if (this.input.pausePressed && this.state === 'play') this.setPaused(this.net ? !this.paused : true);

    /* THE PLAYER IS DRIVEN BY A COMMAND, NOT BY THE KEYBOARD: this
       tic's TicCmd from the session — this page's own input, rounded as
       the wire rounds it, or a network client's — so the simulation
       cannot tell a player here from a player on another machine. See
       js/net/ticcmd.js and js/net/session.js. */
    for (let i = 0; i < this.players.length; i++) {
      const p = this.players[i];
      const cmd = (p.session || this.session).cmd(this);
      const back = this.rewind?.(p, cmd);
      p.tic(cmd, 1 / TICRATE);
      back?.();
    }
    for (let i = 0; i < this.actors.length; i++) this.actors[i].tic();
    /* after the actors, so the bore sees the tic's deaths in the tic
       they happen — a drill whose head has just burst is spent now, not
       a tic later */
    this.bore.tic();
    /* and the missiles, for the same reason: a lock on somebody who died
       this tic is a lock on nobody */
    this.missiles.tic();
    /* and the lightning, which strikes a hop a tic */
    this.arc.tic();
    this.ticProjectiles();
    this.ticDoors();
    for (let i = 0; i < this.slideDoors.length; i++) this.slideDoors[i].tic();
    this.weather.tic();
    this.fire.tic();
    this.vehicles.tic();
    this.forest.tic();
    this.rain.tic();
    this.flame.tic();
    this.frost.tic();
    this.water.tic();
    this.fx.tic();
    this.giblets.tic();
    this.decals.tic();
    this.tracers.tic();
    this.breaches.tic();
    this.applyChar();
    this.ticBurnGrid();

    if (this.bigMessageTics > 0 && --this.bigMessageTics === 0) this.bigMessage = null;
    this.toastTic();

    /* the corpses and the spent puffs, cleared once a tic */
    for (let i = this.actors.length - 1; i >= 0; i--)
      if (this.actors[i].removed) this.actors.splice(i, 1);

    this.boxes.tic();
    this.responders.tic();
    this.brigade.tic();
    this.gunships.tic();

    /* a network client's own tic: the puppets, and what the command
       just run left the player looking at (js/net/remote.js) */
    this.net?.tic();

    if (this.sound) {
      this.sound.listener = this.player;
      this.sound.setAmbience(Math.min(1, this.fire.burningCells / 90));
    }
  }

  /**
   * Swap a burnt-out region's surfaces for their charred twins.
   *
   * Debounced, because half a dozen gondolas can pass the threshold in
   * the same second and each swap costs a full rebuild of the level's
   * static geometry. Collecting them and rebuilding once every twenty
   * tics turns six hitches into one that nobody sees.
   */
  applyChar() {
    const f = this.fire;
    if (f.newlyCharred.length) {
      for (const si of f.newlyCharred) {
        const s = this.level.sectors[si];
        for (const k of ['floorTex', 'ceilTex', 'wallTex', 'upperTex', 'lowerTex']) {
          const burnt = charredName(s[k]);
          if (burnt !== s[k] && this.textures.map.has(burnt)) s[k] = burnt;
        }
        /* A region that has burnt is LIT BY WHAT IT WAS: embers in every
           crack, the roof gone through, the next aisle alight. Its fittings
           are dead by now and its emergency ambient was written for a dark
           shop with the power off, which left a gutted store near black —
           and you have to walk back out through it. So the floor of a
           charred region's light comes up, and stays up. */
        if (!s.outdoor) s.ambient = Math.max(s.ambient, 0.58);
      }
      /* A slider whose entrance has burned is not a door any more. */
      for (const d of this.slideDoors)
        if (d.spec.sector && f.newlyCharred.includes(d.spec.sector.index)) d.jam();
      this._markDirty(f.newlyCharred);
      f.newlyCharred.length = 0;
      this._geoDirty = true;
      this._geoAt = this.tics + 20;
    }

    /* AND THEN THE BUILDING ITSELF. A region whose fuel is all gone
       stops being a charred room and becomes a ruin: holes through the
       walls with the framing behind them, a slab with the ceiling on it,
       and no roof — the ceiling becomes sky, so a store that has fully
       burnt is a shell open to the night with the fire still in the
       cracks. It happens region by region, so the roof goes in PATCHES
       and there is a long stretch where some of the shop is still a shop
       and some of it is a hole. See guttedSurfaces in js/textures.js. */
    if (f.newlyGutted.length) {
      for (const si of f.newlyGutted) {
        const s = this.level.sectors[si];
        const to = guttedSurfaces(s, { cells: f.sectorCells[si] });
        for (const k of Object.keys(to)) {
          /* THREE OF THESE ARE NOT TEXTURES. `sky` is how much of the
             region's light comes from overhead; `ruinRoof` says whether
             the deck is holed or gone, which is what makes js/ruin.js
             hang steel over it; `ruinVariant` is which of the three
             ruins this region drew. All three would fail the "is there a
             texture called that" test below and be silently dropped. */
          if (k === 'sky' || k === 'ruinRoof' || k === 'ruinVariant') { s[k] = to[k]; continue; }
          if (to[k] === 'SKY' || this.textures.map.has(to[k])) s[k] = to[k];
        }
        /* Lit by what is left of it: the cracks in the slab and the sky.
           Higher than charred, because there is a hole in the roof. */
        s.ambient = Math.max(s.ambient, 0.66);
        /* AND THERE IS NO WIRING LEFT IN A ROOF THAT IS NOT THERE. They
           used to be taken away rather than switched off because a dead
           fitting still DREW, and a row of sprites hanging in the open
           night over a roofless shop was the one thing in the shot that
           said "this is a computer program". They draw nothing now, so
           this is only about the light: a sector open to the sky is not
           being lit by a fitting that fell into it. */
        for (const lamp of this.lamps)
          if (!lamp.removed && lamp.sector === s) { lamp.dead = true; lamp.remove(); }
      }
      this._markDirty(f.newlyGutted);
      f.newlyGutted.length = 0;
      this._geoDirty = true;
      this._geoAt = this.tics + 20;
    }

    /* AND THEN IT COMES DOWN. The last stage, and the only one that
       moves the floor: see AND THE THIRD STAGE in js/textures.js for why
       a heap is a floor that has risen rather than a ceiling that has
       fallen, and AND WHAT IS STILL HOLDING IT UP in js/fire.js for what
       decides when. */
    if (f.newlyCollapsed.length) {
      for (const si of f.newlyCollapsed) {
        const s = this.level.sectors[si];
        const to = collapsedSurfaces(s);
        for (const k of Object.keys(to)) {
          if (k === 'floorRise' || k === 'stub') continue;   // done together, below
          if (k === 'sky' || k === 'ruinRoof' || k === 'ruinVariant') { s[k] = to[k]; continue; }
          if (to[k] === 'SKY' || this.textures.map.has(to[k])) s[k] = to[k];
        }
        /* A COLLAPSE LEVELS A REGION TO WHAT IS ROUND IT, and that is
           not the same as raising its floor. Most of this building is
           not floor: a gondola run stands at eighty and a chiller at
           forty, and a fixture that "collapses" upward is a shelf run
           that has become a wall — sixty-eight units of step between two
           bays that both just fell down, which is not something you can
           climb and not something that happened. What a collapse does to
           a shelf run is knock it over. So the region comes down to the
           lowest thing still standing beside it and the heap goes on top
           of THAT, which makes a run of collapsed bays one continuous
           heap at one height rather than a staircase of them. */
        let low = s.floor;
        for (const l of s.lines) {
          const oi = l.front === s.index ? l.back : l.front;
          if (oi === null || oi === undefined || oi < 0) continue;
          const o = this.level.sectors[oi];
          if (o && o !== s && !o.collapsed) low = Math.min(low, o.floor);
        }
        /* THE CEILING DOWN with the headroom checked once at the end: a
           heap that rises into its own stub is a region nothing can
           stand in, and what was standing in it when it came down is
           still standing in it. */
        s.floor = low + to.floorRise;
        s.ceil = Math.max(s.floor + 72, Math.min(s.ceil, s.floor + to.stub));
        /* and whatever was in the region comes up with the floor rather
           than being left buried in it */
        if (this.player && this.player.sector === s && this.player.z < s.floor) this.player.z = s.floor;
        for (const a of this.actors)
          if (!a.removed && a.sector === s && a.z < s.floor) a.z = s.floor;
        /* A HEAP IS LIT BY WHAT IS IN IT. Brighter than a gutted shell,
           because a shell is a dark room with a hole in the roof and this
           is a pile of burning deck under the open sky. */
        s.ambient = Math.max(s.ambient, 0.78);
      }
      this._markDirty(f.newlyCollapsed);
      f.newlyCollapsed.length = 0;
      this._geoDirty = true;
      this._geoAt = this.tics + 20;
    }
    /* AND THE ONES THAT HAVE ONLY DROOPED. No surfaces change and no
       floor moves — the steel over the region is just further down than
       it was, which is geometry and nothing else. See WEAR_STEPS in
       js/fire.js for why this arrives in notches rather than every tic. */
    if (f.newlySagged.length) {
      this._markDirty(f.newlySagged);
      f.newlySagged.length = 0;
      this._geoDirty = true;
      /* and it can wait: a roof on its way down is not urgent the way a
         region that has just changed what it is made of is */
      this._geoAt = Math.max(this._geoAt, this.tics + 35);
    }
    if (this._geoDirty && this.tics >= this._geoAt) {
      this._geoDirty = false;
      this.relight();
      assignLineTextures(this.level.lines, this.level.sectors);
      /* ONLY THE BLOCKS THAT CHANGED. A whole-level rebuild was a few
         thousand triangles when the level was a supermarket; over a
         town it is a hundred thousand and a visible hitch, twenty
         times, during the exact moments the game is at its best. The
         blocks whose regions charred are the ones that moved. */
      const blocks = this._dirtyBlocks && this._dirtyBlocks.size ? this._dirtyBlocks : null;
      this.geo.rebuildStatic(blocks);
      this._dirtyBlocks = null;
      this.geo.rebuild();
    }
  }

  /**
   * A wall has had a piece taken out of it, so the block it is drawn in
   * has to be built again.
   *
   * BY LINE AND NOT BY REGION, which is the whole reason this exists
   * beside _markDirty. A region is drawn in the block its middle lands
   * in; a line is drawn in the block its MIDPOINT lands in, and the two
   * are not always the same block — see the note in js/mapgeo.js about
   * the wood owning the supermarket's flank. Marking the region would
   * rebuild a block that does not contain the wall.
   *
   * It goes on the same debounced clock as a region that has charred:
   * a beam is out for five seconds and punches a dozen times a second,
   * and a hole that appears a third of a second after the shot reaches
   * the wall is a hole that appeared when the beam hit it.
   */
  markBreached(line) {
    if (!line || !line.drawBlock) return;
    if (!this._dirtyBlocks) this._dirtyBlocks = new Set();
    this._dirtyBlocks.add(line.drawBlock);
    /* THE FIRST PUNCH OF A BURST SETS THE CLOCK AND THE REST DO NOT.
       A beam punches on its structural pass, a dozen times a second,
       and a rebuild scheduled afresh by each of them is a rebuild
       every tic for five seconds. Once the rebuild has run the flag
       clears and the next punch starts a new wait, so the holes appear
       in steps of about a third of a second for as long as the column
       is out. */
    if (!this._geoDirty) this._geoAt = this.tics + 12;
    this._geoDirty = true;
  }

  /** Note which drawing blocks some regions are in, so the rebuild can
   *  leave the rest of the town alone. */
  _markDirty(sectorIndices) {
    if (!sectorIndices.length) return;
    if (!this._dirtyBlocks) this._dirtyBlocks = new Set();
    for (const si of sectorIndices) {
      const s = this.level.sectors[si];
      if (s && s.drawBlock) this._dirtyBlocks.add(s.drawBlock);
    }
  }

  /* THERE IS NO GOAL. There was — burn sixty per cent and get back to
     the car park — and it is gone, at the user's request: the only aim
     for now is open mayhem, and the night ends when you close the tab.
     What the night brings in return is js/responders.js's business. */

  /** The pause is owned here and announced outward, so the menu on the
   *  page, the keyboard and the button on a phone all go through one
   *  switch and cannot disagree about whether the game is running. */
  setPaused(on) {
    on = !!on;
    if (this.paused === on) return;
    this.paused = on;
    this.onPauseChange?.(on);
  }

  /* what "go again" is, on whatever this is being played on */
  get retryPrompt() { return this.input?.mode === 'touch' ? 'TAP TO GO AGAIN' : 'PRESS SPACE TO GO AGAIN'; }

  onPlayerDied(p = this.player, source = null) {
    /* A MATCH HAS ITS OWN IDEA OF WHAT A DEATH IS — a frag, and a
       respawn — and nobody's death ends the world for the others */
    if (this.rules) { this.rules.died?.(p, source); return; }
    if (p !== this.player) return;
    this.state = 'dead';
    /* AND NOTHING IS SAID HERE ANY MORE. This was a setBigMessage — one
       line of amber type reading YOU DIED IN AISLE 5, which was the
       right card when a supermarket was the whole game and had been
       wrong since the town. Every death now gets the same card, drawn
       by Readout._drawDeath at the user's request: a black band, the
       Japanese for it in red, YOU DIED under that, and a red filter
       over the picture behind. The readout draws it off p.dead, so
       there is nothing to set and nothing to time out. */
    this.onStateChange?.(this.state);
  }

  onMonsterKilled(a, source) {
    if (source === this.player) this.player.kills++;
    /* and the squad keeps its own count — see js/responders.js */
    if (a.info.team) this.responders?.defeated(a);
  }

  setBigMessage(t, tics) { this.bigMessage = t; this.bigMessageTics = tics; }

  /* ------------------------------------------------------------------
     THE GUN'S OWN NOTICES, at the user's request, and they are TOASTS
     rather than the big card in the middle of the picture.

     They were built for the overcharge — four warnings on the coil's
     way to killing you and a fifth when it did — all of which had been
     going through setBigMessage: thirty-point type across the middle of
     the screen, one at a time, each wiping the one before it. It was in
     the way at exactly the moment you were trying to aim, and it landed
     on top of the end-of-night card, which is what setBigMessage is
     actually for.

     THE OVERCHARGE IS GONE and these are not, because what they were
     really solving is a problem the dialled-back lance has MORE of, not
     less. This weapon fires along eight thousand units of street,
     through whatever is standing in the way, and most of what it does
     happens somewhere you cannot see from where you fired it. So the
     gun says: what a shot went through, and why a charge you were
     holding is suddenly not there. Two lines, neither of them in the
     middle of the picture.

     They stack, in small type, bottom left, and they fade. The newest
     is at the bottom and the older ones ride up above it, which is the
     way every notification stack anybody has used works, and it means
     the one that just arrived is always in the same place.
     ------------------------------------------------------------------ */
  toast(text) {
    if (!text) return;
    /* the same notice twice running is one notice, restarted: a rung
       that somehow fired twice should not print twice */
    const top = this.toasts[this.toasts.length - 1];
    if (top && top.text === text) { top.tics = TOAST_LIFE; return; }
    this.toasts.push({ text: String(text), tics: TOAST_LIFE });
    /* and only so many: past that the oldest goes, which is what makes
       it a stack and not a log */
    while (this.toasts.length > TOAST_MAX) this.toasts.shift();
  }

  /** One tic of the stack: everything ages, and what has run out goes. */
  toastTic() {
    for (let i = this.toasts.length - 1; i >= 0; i--)
      if (--this.toasts[i].tics <= 0) this.toasts.splice(i, 1);
  }

  /* ------------------------------------------------------------------
     Weapons reaching into the world
     ------------------------------------------------------------------ */

  /** Everything alive in a cone in front of `from`, nearest first. */
  actorsInCone(from, range, arc, shootableOnly = true) {
    const out = [];
    const r2 = range * range;
    for (const a of this.actors) {
      if (a.removed || a.dead || a === from) continue;
      if (shootableOnly && !a.shootable) continue;
      const d2 = dist2(from.x, from.y, a.x, a.y);
      if (d2 > r2) continue;
      const ang = Math.atan2(a.y - from.y, a.x - from.x);
      if (Math.abs(angleDiff(ang, from.angle)) > arc) continue;
      if (this.level.sightBlocked(from.x, from.y, from.eyeZ, a.x, a.y, a.z + a.height * 0.5)) continue;
      out.push({ a, d2 });
    }
    out.sort((p, q) => p.d2 - q.d2);
    return out.map(o => o.a);
  }

  /** WHAT THE EYE IS LOOKING AT: the first wall, floor, ceiling or body
   *  along the view, with the pitch in it. The bore's sight is this
   *  once a tic. The same walk as hitscan's, and separate from it
   *  because hitscan is a shot — it hurts what it finds and is level —
   *  and this is a look. */
  trace(from, angle, pitch, range) {
    const c = Math.cos(pitch);
    const ax = from.x, ay = from.y, az = from.eyeZ;
    const tx = ax + Math.cos(angle) * c * range, ty = ay + Math.sin(angle) * c * range;
    const tz = az + Math.sin(pitch) * range;
    const wall = this.level.rayHitWall(ax, ay, az, tx, ty, tz);
    let bestT = wall ? wall.t : 1, best = null;
    /* the floor and the ceiling of the sector the eye is in, which the
       wall walk does not know about: a sight aimed at your own feet
       stops at the lino */
    const sec = from.sector || this.level.sectorAt(ax, ay);
    if (sec) {
      if (tz < sec.floor) bestT = Math.min(bestT, (az - sec.floor) / (az - tz));
      if (tz > sec.ceil) bestT = Math.min(bestT, (sec.ceil - az) / (tz - az));
    }
    const dx = tx - ax, dy = ty - ay;
    const len2 = dx * dx + dy * dy || 1;
    for (const a of this.actors) {
      if (a === from || a.removed || a.dead || !a.shootable) continue;
      let t = ((a.x - ax) * dx + (a.y - ay) * dy) / len2;
      if (t <= 0 || t >= bestT) continue;
      const px = ax + dx * t, py = ay + dy * t;
      if (dist2(px, py, a.x, a.y) > a.radius * a.radius) continue;
      const pz = az + (tz - az) * t;
      if (pz < a.z || pz > a.z + a.height) continue;
      bestT = t; best = a;
    }
    return { x: ax + dx * bestT, y: ay + dy * bestT, z: az + (tz - az) * bestT, actor: best, t: bestT,
             wall: !best && !!wall && wall.t <= bestT + 1e-9 };
  }

  /** A shot that arrives instantly. Walks the ray, takes the nearest of
   *  the first actor it crosses and the first wall.
   *
   *  LEVEL BY DEFAULT, which is what a trooper's rifle has always been,
   *  and PITCHED for the minigun (opts.pitch, radians): the ray then
   *  climbs or drops along its length, stops at the floor or the
   *  ceiling of the shooter's own sector the way trace() does, and
   *  takes an actor only at the height it is at when it crosses them.
   *  `opts.from` moves the origin off the shooter — the nozzle rather
   *  than the eye, so the puffs line up with the barrels — and
   *  `opts.spark` throws a few sparks off whatever it hits. */
  hitscan(from, angle, range, damage, opts = {}) {
    const pitch = opts.pitch || 0;
    const cp = Math.cos(pitch);
    const o = opts.from || from;
    const ox = o.x, oy = o.y;
    const z = opts.from ? (o.z ?? from.eyeZ) : from.eyeZ;
    const tx = ox + Math.cos(angle) * cp * range;
    const ty = oy + Math.sin(angle) * cp * range;
    const tz = z + Math.sin(pitch) * range;

    const wall = this.level.rayHitWall(ox, oy, z, tx, ty, tz);
    let maxT = wall ? wall.t : 1;
    let floorHit = null;
    if (pitch) {
      const sec = from.sector || this.level.sectorAt(ox, oy);
      if (sec) {
        if (tz < sec.floor && z > sec.floor) { const t = (z - sec.floor) / (z - tz); if (t < maxT) { maxT = t; floorHit = sec.floor; } }
        if (tz > sec.ceil && z < sec.ceil) { const t = (sec.ceil - z) / (tz - z); if (t < maxT) { maxT = t; floorHit = sec.ceil; } }
      }
    }

    let best = null, bestT = maxT;
    const targets = this.targetsFor(from);
    const dx = tx - ox, dy = ty - oy;
    const len2 = dx * dx + dy * dy || 1;
    for (const a of targets) {
      if (!a || a === from || a.removed || a.dead || !a.shootable) continue;
      /* project the actor onto the ray and see if it is within its
         radius of the line */
      let t = ((a.x - ox) * dx + (a.y - oy) * dy) / len2;
      if (t <= 0 || t >= bestT) continue;
      const px = ox + dx * t, py = oy + dy * t;
      if (dist2(px, py, a.x, a.y) > a.radius * a.radius) continue;
      /* and that the shot is at a height the thing occupies */
      const pz = z + (tz - z) * t;
      if (pz < a.z - 8 || pz > a.z + a.height + 8) continue;
      bestT = t; best = { a, x: px, y: py, z: pz };
    }

    const lh = this.lastHit;
    /* WHAT A ROUND LEAVES IS A DECAL AND NOTHING ELSE, at the user's
       request: no puff and no sparks off the wall, a hole in it — a hot
       one for the minigun (opts.hot) — and blood on the floor and up the
       wall behind whoever it went through. See js/decals.js. */
    if (best) {
      best.a.damage(this.rules ? this.rules.scale(from, best.a, damage) : damage, from, opts);
      if (opts.shot || opts.hot) {
        this.decals.bleed(best.a, best.x, best.y, best.z, dx, dy, tz - z);
        /* and a pool where they fell, if that was the one that did it */
        if (best.a.dead && bleeds(best.a)) this.decals.pool(best.a.x, best.a.y, best.a.z);
      }
      lh.x = best.x; lh.y = best.y; lh.z = best.z;
      /* A ROUND INTO A VAN LEAVES A HOLE IN THE VAN, on whichever face
         of its box the round came in through, and the hole rides with
         it — see Decals.vehicleHole */
      if (opts.shot && best.a.vehicle)
        this.decals.vehicleHole(best.a.vehicle, best.x, best.y, best.z, dx, dy, tz - z);
      return best.a;
    }
    if (wall && (!pitch || wall.t <= maxT + 1e-9)) {
      /* the hole it leaves, facing the side it came from */
      if (opts.shot) this.decals.hole(wall.x, wall.y, wall.z, wallNormal(wall.line, ox, oy), !!opts.hot);
      lh.x = wall.x; lh.y = wall.y; lh.z = wall.z;
    } else if (floorHit !== null) {
      const hx = ox + dx * maxT, hy = oy + dy * maxT;
      if (opts.shot) this.decals.hole(hx, hy, floorHit, tz < z ? UP : DOWN, !!opts.hot);
      lh.x = hx; lh.y = hy; lh.z = floorHit;
    } else {
      lh.x = tx; lh.y = ty; lh.z = tz;
    }
    return null;
  }

  /* ------------------------------------------------------------------
     A PHYSICAL BLOW

     THERE IS NO WEAPON BEHIND THIS YET, and it is written anyway. A
     thing that hits people is coming — a bat, a hammer, whatever it
     turns out to be — and the half of it that is hard is not the art or
     the animation, it is the question of what a swing MEANS to the rest
     of the game. That question has an answer now, it is tested, and
     when the weapon arrives it calls one function.

     WHAT A SWING IS, here: a short reach, a wide arc, the nearest thing
     in it, and a direction. The first three are the boxcutter's melee
     already (see Player.meleeSwing, which is the same shape); the
     direction is the new part and the reason this is not just melee
     with a bigger number. A blow has a WAY it went, and the pieces go
     with it — Giblets.shatter throws the shards in a cone along it.

     AND IT IS AIMED AT THE ICE. Actor.damage already turns anything
     that is not fire into a shatter, so this needed no special case to
     break somebody frozen: it needed to carry the swing through so
     that breaking them LOOKS like being hit rather than like coming
     apart on its own. That is the whole delta, and it is the thing a
     weapon cannot add from outside.

     WHAT IT DOES NOT DO is push anybody. Actors in this game have no
     momentum — they move by tryWalk, a whole step or none of it, which
     is Doom's and is what stops a crowd oozing through a gap a person
     could not. Knocking a shopper across an aisle would be a physics
     system, not a parameter, so a blow that does not kill leaves them
     standing and cross. The player DOES get shoved, because Player has
     momx/momy and Player.damage already spends it.

     `count` is how many things one swing reaches. One is a bat; three
     is a swing through a queue of people who are all made of ice, and
     that is a decision for whoever builds the weapon rather than one
     to make here.
     ------------------------------------------------------------------ */
  impact(from, opts = {}) {
    const {
      range = 88, arc = 0.7, damage = 40, force = 1.8, count = 1,
      hitSound = 'whack', missSound = 'swing',
    } = opts;
    const dx = Math.cos(from.angle), dy = Math.sin(from.angle);
    const found = this.actorsInCone(from, range, arc, true);
    if (!found.length) {
      /* NOTHING SOFT IN THE WAY, so find the wall. A swing that hits
         shelving still has to land somewhere or the weapon reads as
         broken every time you miss. */
      const z = from.eyeZ;
      const wall = this.level.rayHitWall(from.x, from.y, z, from.x + dx * range, from.y + dy * range, z);
      if (wall) this.spawnPuff(wall.x, wall.y, wall.z);
      /* null for a weapon whose own firing sequence already makes the
         noise of the swing, which the boxcutter's does */
      if (missSound) this.sound?.play(missSound, from);
      return [];
    }
    const hit = found.slice(0, count);
    for (const a of hit) {
      a.damage(damage, from, { impact: true, dx, dy, force });
      this.spawnPuff(a.x, a.y, a.z + a.height * 0.6);
    }
    /* one noise for the swing however many it caught */
    this.sound?.play(hitSound, from);
    return hit;
  }

  /* ------------------------------------------------------------------
     Things in the air

     Not Actors. A projectile lives for under a second, moves in a
     straight line or an arc, and hits one thing — none of which the
     state machine helps with, and all of which it would make slower.

     Two kinds left: the bottle you throw and the sparks off a light
     going out. There was a third, a tin thrown at your head by a member
     of staff, and it left with him.
     ------------------------------------------------------------------ */
  spawnMolotov(player) {
    const speed = 30;
    /* Thrown, not fired: it arcs, and the pitch you are looking at
       decides how far. Lobbing one over a gondola into the next aisle is
       a shot the player has to learn, and it is worth learning. */
    const up = 7 + Math.sin(-player.pitch) * 14;
    this.projectiles.push({
      kind: 'MOLO', x: player.x, y: player.y, z: player.viewZ - 6,
      vx: Math.cos(player.angle) * speed, vy: Math.sin(player.angle) * speed, vz: up,
      gravity: -1.1, owner: player, life: 200, sprite: 'MOLO', mesh: null, damage: 0,
    });
  }

  ticProjectiles() {
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      p.vz += p.gravity;
      if (p.kind === 'SPARK') p.frame = p.life > 11 ? 'A' : p.life > 5 ? 'B' : 'C';
      const nx = p.x + p.vx, ny = p.y + p.vy, nz = p.z + p.vz;

      let hit = null;
      const wall = this.level.rayHitWall(p.x, p.y, p.z, nx, ny, nz);
      if (wall) hit = { x: wall.x, y: wall.y, z: wall.z, actor: null };

      if (!hit) {
        const targets = this.targetsFor(p.owner);
        for (const a of targets) {
          if (!a || a === p.owner || a.removed || a.dead || !a.shootable) continue;
          const rr = a.radius + 10;
          if (dist2(nx, ny, a.x, a.y) > rr * rr) continue;
          if (nz < a.z - 8 || nz > a.z + a.height + 8) continue;
          hit = { x: nx, y: ny, z: nz, actor: a };
          break;
        }
      }

      const sec = this.level.sectorAt(nx, ny);
      if (!hit && sec && nz <= sec.floor + 4) hit = { x: nx, y: ny, z: sec.floor, actor: null };

      if (hit || --p.life <= 0) {
        this.projectileHit(p, hit || { x: p.x, y: p.y, z: p.z, actor: null });
        if (p.mesh) { this.scene.remove(p.mesh); p.mesh.geometry.dispose(); p.mesh.material.dispose(); }
        this.projectiles.splice(i, 1);
        continue;
      }
      p.x = nx; p.y = ny; p.z = nz;
    }
  }

  projectileHit(p, at) {
    if (p.kind === 'SPARK') return;          // it just goes out
    if (p.kind === 'MOLO') {
      this.sound?.play('glass', at);
      this.sound?.play('ignite', at);
      /* A big, hot, generous splash — enough accelerant to light a
         walkway that has no fuel of its own, which is exactly what it is
         for. */
      this.fire.ignite(at.x, at.y, 190, 68);
      /* and the burnt patch it leaves, where it broke on the floor */
      const under = this.level.sectorAt(at.x, at.y);
      if (under && at.z - under.floor < 40) this.decals.burn(at.x, at.y, under.floor, UP, 64);
      for (const a of this.actorsInConeAround(at, 90)) { a.damage(12, p.owner, { fire: true }); a.ignite?.(340); }
      return;
    }
    if (at.actor) { at.actor.damage(p.damage, p.owner); this.spawnPuff(at.x, at.y, at.z); }
    else this.spawnPuff(at.x, at.y, at.z);
  }

  actorsInConeAround(at, radius) {
    const out = [];
    const r2 = radius * radius;
    for (const a of this.actors)
      if (!a.removed && !a.dead && a.shootable && dist2(at.x, at.y, a.x, a.y) < r2) out.push(a);
    for (const p of this.players)
      if (!p.dead && dist2(at.x, at.y, p.x, p.y) < r2) out.push(p);
    return out;
  }

  /** What a shot from `from` can hit: every player and every actor,
   *  less `from` itself and whoever the match says is on its side.
   *  Alone in a world that is the actors, which is what it always was. */
  targetsFor(from) {
    const out = [];
    const rules = this.rules;
    for (const p of this.players)
      if (p !== from && !(rules && rules.friendly?.(from, p))) out.push(p);
    for (let i = 0; i < this.actors.length; i++) out.push(this.actors[i]);
    return out;
  }

  /** A fuel can or a car going up. `a` only has to have a position:
   *  a vehicle is not an actor, and the second bang happens where one
   *  landed rather than where anything is standing.
   *
   *  This is also the whole of the chain reaction in the car park. The
   *  blast igniting everything it reaches means the bay either side
   *  catches, cooks for its own few seconds and goes up in turn — which
   *  is not a feature anybody wrote, it is what happens when cars are
   *  flammable and explosions light things. */
  explode(a, opts = {}) {
    const { radius = 150, damage = 60, heat = 230, heatRadius = 86, ignite = 320, sound = 'explode',
            /* AND WHAT IT DOES TO THE BUILDING. Off by default and not
               zero by default: most of what explodes in this game is a
               can or a car in a car park, where there is no structure to
               take down, and a blast that quietly guts the aisle behind
               every burning trolley would be a surprise. What sets it is
               the thing that is meant to bring a wall down. */
            structure = 0, structureRadius = radius * 1.4 } = opts;
    this.sound?.play(sound, a);
    this.fire.ignite(a.x, a.y, heat, heatRadius);
    /* and a burning hole in the ground where it went off */
    const under = this.level?.sectorAt?.(a.x, a.y);
    if (under && (a.z ?? under.floor) - under.floor < 64) this.decals.burn(a.x, a.y, under.floor, UP, Math.min(150, radius * 0.6));
    if (structure > 0) this.fire.damageStructure(a.x, a.y, structureRadius, structure, a.storey || 0);
    for (const o of this.actorsInConeAround(a, radius)) {
      if (o === a) continue;
      const d = dist(a.x, a.y, o.x, o.y);
      o.damage(Math.round(damage * (1 - d / radius)), null, { fire: true });
      o.ignite?.(ignite);
    }
  }

  /* ------------------------------------------------------------------
     HOW BURNT EVERY PIECE OF FLOOR IS, as a picture

     THIS USED TO BE ONE TEXEL PER SECTOR and that was the bug the user
     reported as z-fighting. A region's progress is a single number, so
     every surface in a sector sooted at once, and this map's sectors are
     big axis-aligned rectangles: a burnt aisle met a clean cross-aisle
     along a dead-straight line with a different texture and a different
     light level on either side of it. A knife edge across the floor,
     exactly vertical or exactly horizontal on screen, which reads as two
     surfaces fighting rather than as a fire.

     So the picture is the FIRE'S OWN GRID instead — 32-unit cells, the
     same ones the fire actually spreads through — sampled by world
     position with a linear filter, so the soot front creeps across the
     floor at the resolution the fire has and crosses a sector boundary
     without knowing it is there. A wall reads the cells it stands in and
     a ceiling the cells under it, which is also more nearly true than
     "the sector this surface was filed under".

     ONE BYTE A CELL AND NOT FOUR, in a texture the exact size of the
     grid rather than the power of two over it. Both of those were free
     and neither was: this was written as RGBA with the same value in r,
     g and b, in a square big enough to hold a 225 by 207 supermarket —
     256 square, 256K, and the sentence above it said 64K because it
     counted texels and not bytes. The town's grid is 605 by 810, which
     rounded up to 1024 square and FOUR MEGABYTES, and three.js has no
     way to upload part of a texture, so every tic on which one cell
     moved sent all four of them to the GPU. At thirty-five tics that is
     a hundred and forty megabytes a second to say that a shelf is
     sooty. It is 605 by 810 single channel now — 478K, which is a
     factor of nine — and it goes up at most every UPLOAD_EVERY tics,
     which the eye cannot tell from every tic because what it is drawing
     is a stain spreading across a floor.

     NPOT AND SINGLE CHANNEL ARE BOTH SAFE HERE and js/forest.js is the
     precedent: its own mask is a RedFormat DataTexture at the size of
     its grid. Neither needs mipmaps and neither wraps, which is the
     whole of what a non-power-of-two texture cannot do.
     ------------------------------------------------------------------ */
  _initBurnGrid() {
    const f = this.fire;
    if (!f) return;
    this._burnData = new Uint8Array(f.cols * f.rows);
    const tex = new THREE.DataTexture(this._burnData, f.cols, f.rows,
                                      THREE.RedFormat, THREE.UnsignedByteType);
    /* LINEAR, which is the whole point: the fire's cells are 32 units
       across and the eye is two metres from the floor, so a nearest
       filter would trade one straight seam for a grid of little ones. */
    tex.magFilter = THREE.LinearFilter;
    tex.minFilter = THREE.LinearFilter;
    tex.generateMipmaps = false;
    tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
    tex.needsUpdate = true;
    world.burnGrid.value = tex;
    world.burnOrigin.value.set(f.originX, f.originY);
    world.burnCell.value = f.CELL;
    world.burnCols.value = f.cols;
    world.burnRows.value = f.rows;
    this._burnTex = tex;
    this._burnPending = false;
    this._burnNextUpload = 0;
  }

  /**
   * Push the fire's per-cell progress into it.
   *
   * ONLY THE CELLS THAT MOVED. The fire keeps the list — see gridDirty
   * in js/fire.js — because it is the only thing that knows, and the
   * alternative was scanning four hundred and ninety thousand cells
   * thirty-five times a second to find the twenty that changed, which
   * cost two thirds of every tic in the game whether or not anything
   * was alight. The list is drained here and nowhere else.
   */
  ticBurnGrid() {
    const f = this.fire;
    if (!f || !this._burnData) return;
    const d = this._burnData;
    const fuel = f.fuel, fuel0 = f.fuel0;
    let dirty = false;
    /* the whole grid, once, at the start — and again if the fire ever
       had more to say than a list could hold */
    if (f.gridDirtyAll) {
      f.gridDirtyAll = false;
      f.gridDirty.length = 0;
      for (let i = 0; i < d.length; i++) {
        const t = fuel0[i];
        const v = t <= 0 ? 0 : 255 - Math.min(255, Math.round(255 * fuel[i] / t));
        if (d[i] !== v) { d[i] = v; dirty = true; }
      }
    } else {
      const list = f.gridDirty;
      for (let k = 0; k < list.length; k++) {
        const i = list[k];
        const t = fuel0[i];
        if (t <= 0) continue;                    // never had anything to burn
        const v = 255 - Math.min(255, Math.round(255 * fuel[i] / t));
        if (d[i] === v) continue;
        d[i] = v; dirty = true;
      }
      list.length = 0;
    }
    if (dirty) this._burnPending = true;
    /* AND UP TO THE GPU, on a slower clock than the simulation: three.js
       r160 can only send a whole texture, so an upload is half a
       megabyte however little of it moved. A stain creeping across a
       floor at twelve hertz is a stain creeping across a floor. */
    if (this._burnPending && this.tics >= this._burnNextUpload) {
      this._burnTex.needsUpdate = true;
      this._burnPending = false;
      this._burnNextUpload = this.tics + BURN_UPLOAD_EVERY;
    }
  }

  /** Clear a room. Anything that can be frightened and is within
   *  `radius` of (x, y) starts running away from it — used by whatever
   *  is loud and sudden enough to be worth running from, which at the
   *  moment is somebody going off. */
  scare(x, y, radius) {
    const r2 = radius * radius;
    let n = 0;
    /* Off the blockmap, not off the cast list. This is called once per
       person who comes apart, and in a crowd of eight hundred a dozen of
       them can come apart in the same second — a scan each would be the
       crowd squared at exactly the moment the frame is busiest. */
    for (const a of this.blockmap.nearRadius(x, y, radius, this._scared)) {
      if (a.dead || a.removed || !a.info.panicTics) continue;
      /* NOT THE ONES IN THE ICE. A_Scare turns them away too, and has
         to, but the count this returns is "how many people started
         running" and a block of ice is not one of them. */
      if (a.held) continue;
      if (dist2(x, y, a.x, a.y) > r2) continue;
      ACTIONS.A_Scare(a, x, y);
      n++;
    }
    return n;
  }

  /** Doom's P_NoiseAlert, with a radius instead of a flood fill. Firing
   *  a weapon is how you wake the store up, and the flamethrower is
   *  louder than the boxcutter for the obvious reason. */
  noise(from, radius) {
    const r2 = radius * radius;
    for (const a of this.actors) {
      if (!a.monster || a.dead || a.target) continue;
      /* AND NOT THROUGH A CENTIMETRE OF ICE. This was the loudest of
         the three doors into a frozen shopper, because the player holds
         the trigger down: every tic of the flamethrower woke every
         block of ice in the shop, gave it the player as a target and
         set it going. */
      if (a.held) continue;
      if (dist2(from.x, from.y, a.x, a.y) > r2) continue;
      a.target = this.player;
      this.sound?.play(a.info.seeSound, a);
      if (a.info.see) a.setState(a.info.see);
    }
  }

  /* ------------------------------------------------------------------
     Doors
     ------------------------------------------------------------------ */
  tryUse(player) {
    const reach = 80;
    const tx = player.x + Math.cos(player.angle) * reach;
    const ty = player.y + Math.sin(player.angle) * reach;
    const hit = this.level.rayHitWall(player.x, player.y, player.viewZ, tx, ty, player.viewZ);
    if (hit && this.activateLine(hit.line, player)) return true;
    /* nothing square on: try anything special nearby, so you do not
       have to line up on a doorway to open it */
    const near = this.level.linesInBox(player.x - reach, player.y - reach, player.x + reach, player.y + reach, []);
    for (const l of near) if (this.activateLine(l, player)) return true;
    return false;
  }

  activateLine(line, activator) {
    for (const si of [line.front, line.back]) {
      if (si === null) continue;
      const s = this.level.sectors[si];
      if (!s.special || s.special.kind !== 'door') continue;
      return this.openDoor(s);
    }
    return false;
  }

  openDoor(s) {
    let d = this.doors.find(x => x.sector === s);
    if (d) {
      /* used again while moving: reverse it, the way Doom's do */
      if (d.state === 'opening') { d.state = 'closing'; return true; }
      if (d.state === 'open') { d.timer = 0; return true; }
      if (d.state === 'closing') { d.state = 'opening'; return true; }
      return true;
    }
    d = { sector: s, state: 'opening', timer: 0, speed: s.special.speed ?? 4,
          openTo: s.special.openTo ?? 152, closedAt: s.floor };
    this.doors.push(d);
    this.sound?.play('dooropen', { x: s.bbox[0], y: s.bbox[1] });
    return true;
  }

  ticDoors() {
    if (!this.doors.length) return;
    let changed = false;
    for (let i = this.doors.length - 1; i >= 0; i--) {
      const d = this.doors[i];
      const s = d.sector;
      if (d.state === 'opening') {
        s.ceil = Math.min(d.openTo, s.ceil + d.speed);
        changed = true;
        if (s.ceil >= d.openTo) { d.state = 'open'; d.timer = s.special.wait ?? 140; }
      } else if (d.state === 'open') {
        if (d.timer > 0 && --d.timer === 0) {
          /* do not close it on somebody's head */
          if (this.somethingUnder(s)) d.timer = 35;
          else { d.state = 'closing'; this.sound?.play('doorclose', { x: s.bbox[0], y: s.bbox[1] }); }
        }
      } else {
        if (this.somethingUnder(s)) { d.state = 'opening'; continue; }
        s.ceil = Math.max(d.closedAt, s.ceil - d.speed);
        changed = true;
        if (s.ceil <= d.closedAt) { this.doors.splice(i, 1); }
      }
    }
    if (changed) this.geo.rebuild();
  }

  somethingUnder(s) {
    const [x0, y0, x1, y1] = s.bbox;
    const inside = (o) => o && !o.removed && !o.dead && o.x > x0 - 16 && o.x < x1 + 16 && o.y > y0 - 16 && o.y < y1 + 16;
    if (inside(this.player)) return true;
    for (const a of this.actors) if (a.solid && inside(a)) return true;
    return false;
  }

  /* ------------------------------------------------------------------
     Drawing
     ------------------------------------------------------------------ */
  render(now = 0) {
    /* the others, slid to where they were a moment ago */
    this.net?.frame();
    const p = this.player;
    let yaw = p.angle, pitch = p.pitch, ex = p.x, ey = p.y, ez = p.viewZ;
    if (this.idle) {
      /* THE TITLE. Nothing moves — the world is not being stepped — but
         the eye does, a little, the way a person standing still is never
         quite still. Sines at rates that never line up, so it does not
         repeat, and small enough that it reads as breathing rather than
         as a camera move. */
      const t = now * 0.001;
      yaw   += 0.030 * Math.sin(t * 0.23) + 0.016 * Math.sin(t * 0.61 + 1.3) + 0.007 * Math.sin(t * 1.37 + 0.4);
      pitch += 0.014 * Math.sin(t * 0.31 + 2.1) + 0.006 * Math.sin(t * 0.83 + 0.7);
      ex += 3.0 * Math.sin(t * 0.19 + 0.5); ey += 2.4 * Math.cos(t * 0.27);
      ez += 1.4 * Math.sin(t * 0.47 + 1.1);
    }
    /* ------------------------------------------------------------------
       AND THE LANCE SHAKES IT, which is the one thing in this game that
       moves the eye while the player is standing still.

       Off the WALL CLOCK and not the tic, because a shake is something
       the picture does and not something the world does: at a tic it
       would step thirty-five times a second whatever the frame rate is,
       and a step is a judder rather than a shudder. Four sines at rates
       that do not divide into each other, so it never repeats inside
       the five seconds a discharge lasts, and the turn is bigger than
       the lift because that is what a recoil you are braced against
       does to a view.

       It is added to the eye and NOT to the player: p.angle is
       untouched, so the shake does not walk your aim off the street you
       picked. See js/beam.js for how hard it is shaking. */
    /* AND A MISSILE GOING OFF NEAR YOU SHAKES IT TOO, on the same four
       sines: the harder of the two, not their sum, so a blast under a
       discharge is still one shudder. See MissileSystem.detonate. */
    const shake = Math.max(this.beam ? this.beam.shake : 0, this.missiles ? this.missiles.shake : 0, this.arc ? this.arc.shake : 0);
    if (shake > 0.001) {
      const t = now * 0.001;
      const k = shake * shake;
      yaw   += k * (0.022 * Math.sin(t * 47.3) + 0.013 * Math.sin(t * 29.1 + 1.7));
      pitch += k * (0.017 * Math.sin(t * 41.7 + 0.9) + 0.010 * Math.sin(t * 23.3 + 2.4));
      ex += k * 5.5 * Math.sin(t * 53.1 + 0.3);
      ey += k * 5.5 * Math.cos(t * 44.9 + 1.9);
      ez += k * 4.0 * Math.sin(t * 61.7 + 2.6);
    }
    /* THE ATMOSPHERE, once a frame: the clouds drift, and every uniform
       the hour and the weather own is set — the air's reach, the sky's
       light, the smoke off the two fires. See js/weather.js. */
    const dt = this._lastNow === undefined ? 0 : Math.min(0.25, (now - this._lastNow) / 1000);
    this._lastNow = now;
    this.weather.apply(dt, this.fire ? this.fire.burnFraction : 0, this.forest ? this.forest.burnFraction : 0,
                       { hot: this.fire ? this.fire.burningCells : 0, wood: this.forest ? this.forest.burningCells : 0 });
    /* THE FAR PLANE IS THE AIR'S. Nothing past airFar can be seen, so
       nothing past it is drawn; the sky sphere follows it in. */
    const far = climate.airFar * 1.06;
    if (this.camera.updateProjectionMatrix && Math.abs(this.camera.far - far) > 1) {
      this.camera.far = far;
      this.camera.updateProjectionMatrix();
    }
    this.camera.position.set(ex, ez, -ey);
    world.eyePos.value.set(ex, ez, -ey);
    if (this.sky) followSky(this.sky, this.camera);
    this.camera.rotation.set(pitch, yaw - Math.PI / 2, 0, 'YXZ');
    this.camera.updateMatrixWorld(true);

    /* Every billboard in the scene is spun to the same yaw — they face
       the camera PLANE, not the camera point, which is what stops
       sprites near the edge of the screen turning to look at you. */
    const billboardRot = p.angle - Math.PI / 2;

    /* ONE CLOCK for everything still glowing after the flame has gone:
       the trees' burn shader and every charred surface in the store read
       this, so the coals in an aisle and the coals on a fir are in the
       same fire. */
    world.emberTime.value = this.tics / TICRATE + now * 0.0002;

    /* which way the eye is pointing, so a standee can decide for itself
       whether it is worth drawing — see the culling note on
       Actor.render, and why three.js is not allowed to do it */
    const vx = Math.cos(p.angle), vy = Math.sin(p.angle);
    /* AND WHAT THE EYE CAN SEE AT ALL: the portal flood (Level.
       visibleSectors), once a frame, out to the air. The window is the
       camera's horizontal field with a margin either side, because a
       sprite is as wide as it is and the title's camera breathes. */
    const vfov = (this.camera.fov || 72) * Math.PI / 180;
    const halfFov = Math.atan(Math.tan(vfov / 2) * (this.camera.aspect || 1.6)) + 0.25;
    /* NO FURTHER THAN THE FLOOD IS WORTH RUNNING. Clear air reaches
       fourteen thousand units and the walk is not worth a tenth of that
       — see VIS_FAR in js/level.js, and isVisible, which knows that a
       region past the radius was never walked and says so. */
    this.level.visibleSectors(ex, ey, yaw, halfFov, Math.min(climate.airFar, VIS_FAR));
    /* AND THE STATIC GEOMETRY TAKES IT TOO. The flood says which regions
       are visible; the blocks those regions are in are the ones drawn,
       and the rest of the town is not submitted at all. */
    /* AND THE AIR DECIDES THE DRAW DISTANCE. Everything past a fraction
       of airFar is sky already — see the note on applyVisibility — so
       the weather pulls the town in and out with it. */
    this.geo.applyVisibility(this.level, ex, ey, INTERIOR_DIST, climate.airFar, this.viewRows);
    /* AND HOW MUCH OF THE CROWD TO DRAW. Off the actor's own id rather
       than off a counter, so the same people are the ones left out from
       frame to frame — a crowd that reshuffles which half of it exists
       is worse than half a crowd. */
    const crowd = this.quality.crowd;
    this.standees.begin(billboardRot);
    for (const a of this.actors) {
      if (crowd < 1 && (a.type === 'SHOPPER' || a.type === 'TOWNIE') && (a.id % 16) >= crowd * 16) { a.drawn = false; continue; }
      a.render(p.x, p.y, billboardRot, vx, vy);
    }
    this.standees.end();
    this.fire.render(p.x, p.y, billboardRot);
    /* the wood's range is a fraction of a clear night's, because that
       is what its own range was written against, and the weather pulls
       it in with the air: nothing past airFar is drawn by anybody */
    this.forest.render(p.x, p.y, ez, billboardRot, world.emberTime.value,
                       this.quality.wood * Math.min(1, climate.airFar / CLEAR_FAR));
    this.rain.render(billboardRot);
    this.flame.render(billboardRot);
    this.frost.render(billboardRot);
    this.water.render(billboardRot);
    this.fx.render(billboardRot);
    this.giblets.render(billboardRot);
    this.decals.render(ex, ey, vx, vy);
    this.tracers.render(ex, ey, ez);
    /* the beam, rebuilt round whichever way the barrel is pointing this
       frame — the feet are nailed down and the barrel is not — and the
       light it throws on the street, which outlives it */
    this.beam.render(now / 1000);
    this.beam.ticLight(dt);
    this.gunships.render(ex, ey, ez, vx, vy);
    this.streetLights.render(ex, ey, ez, vx, vy);
    this.renderProjectiles(billboardRot);
    this.bore.render(billboardRot);
    this.missiles.render(billboardRot, ex, ey);
    this.arc.render(billboardRot, ex, ey, ez);

    /* the red mist of being nearly dead */
    const hurt = clamp(1 - p.health / 100, 0, 1);
    world.tint.value.setRGB(1, 1 - hurt * 0.22, 1 - hurt * 0.3);
  }

  renderProjectiles(billboardRot) {
    for (const p of this.projectiles) {
      if (!p.mesh) {
        const mat = createSpriteMaterial(null, { alphaTest: 0.5, width: 32, height: 32 });
        p.mesh = new THREE.Mesh(this._projGeo, mat);
        p.mesh.frustumCulled = false;
        this.scene.add(p.mesh);
      }
      const e = this.sprites.get(p.sprite, p.frame || 'A');
      const u = p.mesh.material.uniforms;
      u.map.value = this.sprites.texture(e, 0);
      u.spriteScale.value.set(e.w * e.scale, e.h * e.scale);
      u.billboardRot.value = billboardRot;
      u.fullbright.value = (p.kind === 'MOLO' || p.kind === 'SPARK') ? 1 : 0;
      u.light.value = this.level.sectorAt(p.x, p.y)?.light ?? 0.6;
      /* the quad's foot is its origin, so lift it by half its height to
         put the thing itself where the projectile is */
      p.mesh.position.set(p.x, p.z - (e.h * e.scale) / 2, -p.y);
    }
  }
}
