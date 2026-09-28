/* =====================================================================
   MEWD — the cerebral bore
   =====================================================================

   TUROK 2'S, at the user's request, and the rules are Turok's: a red
   sight, a LOCK when the sight finds a head, a projectile that only
   leaves the launcher when there is one, flies at that head however
   the head moves, drills into it for two seconds while its owner
   stands there shaking — and then they explode. It is the one weapon in
   the game that is aimed rather than poured, and the one that kills one
   person at a time with a ceremony.

   THREE PARTS, in the order they happen:

   THE SIGHT. Every tic the bore is in hand, a ray goes out of the eye
   along the view — with the pitch in it, which the flamethrower's aim
   never needed — and stops at the first wall or the first body. A line
   is drawn from the mouth of the launcher to that point and a red dot
   put on it. If the point is a person, the dot becomes a reticle on
   their head and the weapon is LOCKED: a beep, and the reticle stays
   with the head for a few tics after the beam leaves it, because a
   sight that drops the lock the instant you twitch is a sight you fight
   rather than use. What can be locked is anybody alive and shootable
   who has a head — the crowd, the squad, a block of ice with somebody
   in it — and not a van.

   THE FLIGHT. The trigger does nothing without a lock (a click, the
   noammo click, so the refusal is heard). With one, a bore leaves the
   launcher along the line of sight, slowly, and every tic bends toward
   the head it was sent to by at most `turn` radians while it speeds up
   — so it leaves in a curve and arrives fast, which is the shape of the
   thing in the original. It stops for walls, floors and the target's
   head and nothing else. A target that dies on the way is a target it
   flies straight past.

   THE DRILL, which is a HOLD — the third one after the ice and the
   fire (see Actor.held). The bore sits in the head, turning; blood and
   pieces of what was in there come out of the top in a fountain and
   land on the floor as blood does; the person screams, cannot move,
   cannot be frightened, and is not hurried by anything. At the end of
   it Actor.boreBurst: the same coming-apart the flamethrower gets — the
   fireball and the thirteen pieces for a shopper, the gore animation
   for a trooper — because "explode" in this game already means one
   thing, and it should keep meaning it.

   The projectiles are NOT actors. Like the sparks and the bottle they
   live for seconds, hit one thing and are drawn as one quad each, and
   the state machine would only slow them down. What IS on the actor is
   the hold — `bored`, the countdown, the blood — because that is a
   thing that happens to a person and every other thing that happens to
   a person lives there.
   ===================================================================== */

import * as THREE from 'three';
import { createSpriteMaterial } from './material.js';
import { pRandom, dist2 } from './util.js';
import { wallNormal, UP, DOWN } from './decals.js';

export const BORE = {
  range: 2200,          // how far the sight reaches
  grace: 14,            // tics a lock outlives the beam leaving the head
  speed0: 9,            // how it leaves the launcher, in units a tic
  speed1: 30,           // and how it arrives
  accel: 1.09,          // a tic's worth of getting there
  turn: 0.16,           // radians a tic it may bend toward the head
  life: 6 * 35,         // and then it drops, whatever it was chasing
  drillTics: 78,        // how long a head takes, a shade over two seconds
  headAt: 0.86,         // where the head is, as a fraction of the height
  reach: 12,            // how close to the head is in it
};

export class BoreSystem {
  constructor(game) {
    this.game = game;
    this.aim = { x: 0, y: 0, z: 0, actor: null, t: 1 };
    this.lock = null;
    this.lockTics = 0;
    this.shots = [];          // in flight
    this.drilling = [];       // in a head
    this.fired = 0;
    this.drilled = 0;
    this.line = null; this.dot = null; this.reticle = null;
  }

  /** Whether the sight is on: the bore in hand, and a hand to hold it. */
  get active() {
    const p = this.game.player;
    return !!p && p.weapon === 'BORE' && !p.dead;
  }

  /** Whether the sight may lock on to this. A person, alive, with a
   *  head, and not one already being drilled. */
  lockable(a) {
    return !!a && !a.removed && !a.dead && a.shootable && a.monster && !a.vehicle &&
      a.bored <= 0 && a.info.boreable !== false;
  }

  tic() {
    const p = this.game.player;
    if (this.active) this.sightTic(p);
    else { this.lock = null; this.lockTics = 0; this.aim.actor = null; }
    this.flyTic();
    this.drillTic();
  }

  /* ------------------------------------------------------------------
     The sight
     ------------------------------------------------------------------ */
  sightTic(p) {
    const t = this.game.trace(p, p.angle, p.pitch, BORE.range);
    this.aim = t;
    const cand = this.lockable(t.actor) ? t.actor : null;
    if (cand) {
      if (cand !== this.lock) this.game.sound?.play('lock', null);
      this.lock = cand;
      this.lockTics = BORE.grace;
    } else if (this.lock && (!this.lockable(this.lock) || --this.lockTics <= 0)) {
      this.lock = null;
      this.lockTics = 0;
    }
  }

  /* ------------------------------------------------------------------
     The launcher
     ------------------------------------------------------------------ */
  /** One bore, at the locked head. Null when there is nothing locked,
   *  which the player hears as a click — see Player.weaponTic. */
  fire(p) {
    const target = this.lock;
    if (!target) return null;
    const o = this.game.nozzle();
    const c = Math.cos(p.pitch);
    const s = {
      x: o.x, y: o.y, z: o.z,
      dx: Math.cos(p.angle) * c, dy: Math.sin(p.angle) * c, dz: Math.sin(p.pitch),
      speed: BORE.speed0, target, life: BORE.life, tics: 0, spin: 0,
      stuck: null, mesh: null,
    };
    this.shots.push(s);
    this.fired++;
    this.game.sound?.play('borefire', null);
    return s;
  }

  /* ------------------------------------------------------------------
     In the air
     ------------------------------------------------------------------ */
  flyTic() {
    const g = this.game, lv = g.level;
    for (let i = this.shots.length - 1; i >= 0; i--) {
      const s = this.shots[i];
      const t = s.target;
      const chasing = !!t && !t.removed && !t.dead && t.bored <= 0;
      if (chasing) {
        /* bend toward the head, by no more than `turn` */
        const hz = t.z + t.height * BORE.headAt;
        let wx = t.x - s.x, wy = t.y - s.y, wz = hz - s.z;
        const wl = Math.hypot(wx, wy, wz) || 1;
        wx /= wl; wy /= wl; wz /= wl;
        const dot = Math.max(-1, Math.min(1, s.dx * wx + s.dy * wy + s.dz * wz));
        const ang = Math.acos(dot);
        if (ang > 1e-4) {
          const k = Math.min(1, BORE.turn / ang);
          s.dx += (wx - s.dx) * k; s.dy += (wy - s.dy) * k; s.dz += (wz - s.dz) * k;
          const l = Math.hypot(s.dx, s.dy, s.dz) || 1;
          s.dx /= l; s.dy /= l; s.dz /= l;
        }
      }
      s.speed = Math.min(BORE.speed1, s.speed * BORE.accel);
      const nx = s.x + s.dx * s.speed, ny = s.y + s.dy * s.speed, nz = s.z + s.dz * s.speed;
      s.spin++; s.tics++;
      if ((s.tics % 7) === 0) g.sound?.play('borefly', s);

      /* the head */
      if (chasing) {
        const hz = t.z + t.height * BORE.headAt;
        const rr = t.radius + BORE.reach;
        if (dist2(nx, ny, t.x, t.y) < rr * rr && Math.abs(nz - hz) < t.height * 0.35) {
          this.shots.splice(i, 1);
          this.drill(s, t);
          continue;
        }
      }
      /* walls, floors, ceilings, the edge of the map, and old age */
      const wall = lv.rayHitWall(s.x, s.y, s.z, nx, ny, nz);
      const sec = lv.sectorAt(nx, ny);
      const spent = !sec || nz <= sec.floor + 2 || nz >= sec.ceil - 2 || --s.life <= 0;
      if (wall || spent) {
        const at = wall || { x: nx, y: ny, z: sec ? Math.max(sec.floor + 2, Math.min(sec.ceil - 2, nz)) : nz };
        /* A DECAL AND NOTHING ELSE where it struck: the bit is spinning
           hot, so what it leaves is a small burning hole — see
           js/decals.js, Decals.burn */
        const face = wall ? (wall.line ? wallNormal(wall.line, s.x, s.y) : null)
          : sec && nz <= sec.floor + 2 ? UP : sec && nz >= sec.ceil - 2 && !sec.sky ? DOWN : null;
        if (face) g.decals?.burn(at.x, at.y, wall ? at.z : face === UP ? sec.floor : sec.ceil, face, 26);
        g.sound?.play('clang', at);
        this.shots.splice(i, 1);
        this.discard(s);
        continue;
      }
      s.x = nx; s.y = ny; s.z = nz;
    }
  }

  /** It has reached a head. What that means is the actor's to say —
   *  a drill, or for a block of ice a shatter — see Actor.bore. */
  drill(s, t) {
    const took = t.bore(this.game.player);
    if (took === 'drill') {
      s.stuck = t;
      this.drilling.push(s);
      this.drilled++;
      this.game.sound?.play('bore', t);
    } else this.discard(s);
  }

  /* ------------------------------------------------------------------
     In a head
     ------------------------------------------------------------------ */
  drillTic() {
    const g = this.game;
    for (let i = this.drilling.length - 1; i >= 0; i--) {
      const s = this.drilling[i], v = s.stuck;
      /* the hold has ended — the burst, or something else got them first */
      if (!v || v.removed || v.dead || v.bored <= 0) { this.drilling.splice(i, 1); this.discard(s); continue; }
      s.spin += 2;
      s.x = v.x; s.y = v.y; s.z = v.z + v.height * BORE.headAt;
      if ((v.bored % 6) === 0) g.sound?.play('bore', v);
    }
  }

  discard(s) {
    if (s.mesh) { this.game.scene.remove(s.mesh); s.mesh.material.dispose(); s.mesh = null; }
  }

  /* ------------------------------------------------------------------
     Drawing

     A line from the launcher to the sight's end, a dot or a reticle at
     the end of it, and one turning quad per bore. The dot and the
     reticle ignore depth on purpose: they sit ON a wall or ON a head,
     which is exactly where a depth test would lose them, and the trace
     has already decided what is in front of what.
     ------------------------------------------------------------------ */
  _sprite(depthTest) {
    const g = this.game;
    const mat = createSpriteMaterial(null, { alphaTest: 0.5, width: 16, height: 16 });
    mat.depthTest = depthTest;
    mat.depthWrite = false;
    const m = new THREE.Mesh(g._projGeo, mat);
    m.frustumCulled = false;
    m.renderOrder = 20;
    g.scene.add(m);
    return m;
  }

  ensure() {
    if (this.line) return;
    const g = this.game;
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(6), 3));
    this.line = new THREE.Line(geo, new THREE.LineBasicMaterial({ color: 0xff2a1a, toneMapped: false }));
    this.line.frustumCulled = false;
    this.line.renderOrder = 19;
    g.scene.add(this.line);
    this.dot = this._sprite(false);
    this.reticle = this._sprite(false);
  }

  /** One quad, put where a thing is, showing one frame of one sprite. */
  place(mesh, x, y, z, sprite, frame, billboardRot, scale = 1) {
    const g = this.game;
    const e = g.sprites.get(sprite, frame);
    const u = mesh.material.uniforms;
    u.map.value = g.sprites.texture(e, 0);
    u.spriteScale.value.set(e.w * e.scale * scale, e.h * e.scale * scale);
    u.billboardRot.value = billboardRot;
    u.fullbright.value = 1;
    u.light.value = 1;
    mesh.position.set(x, z - (e.h * e.scale * scale) / 2, -y);
    mesh.visible = true;
  }

  render(billboardRot) {
    const g = this.game;
    this.ensure();
    if (this.active && this.aim) {
      const o = g.nozzle();
      let ex = this.aim.x, ey = this.aim.y, ez = this.aim.z;
      const locked = !!this.lock;
      if (locked) { ex = this.lock.x; ey = this.lock.y; ez = this.lock.z + this.lock.height * BORE.headAt; }
      const pos = this.line.geometry.getAttribute('position');
      pos.setXYZ(0, o.x, o.z, -o.y);
      pos.setXYZ(1, ex, ez, -ey);
      pos.needsUpdate = true;
      this.line.visible = true;
      if (locked) {
        this.dot.visible = false;
        this.place(this.reticle, ex, ey, ez, 'LOCK', 'A', billboardRot, 1 + 0.25 * Math.sin(g.smoothTics * 0.5));
      } else {
        this.reticle.visible = false;
        this.place(this.dot, ex, ey, ez, 'LASR', 'A', billboardRot);
      }
    } else {
      this.line.visible = false;
      this.dot.visible = false;
      this.reticle.visible = false;
    }
    for (const list of [this.shots, this.drilling])
      for (const s of list) {
        if (!s.mesh) s.mesh = this._sprite(true);
        this.place(s.mesh, s.x, s.y, s.z, 'BORE', 'ABC'[s.spin % 3], billboardRot);
      }
  }
}
