/* =====================================================================
   MEWD — tracers
   =====================================================================

   THE MINIGUN'S ROUNDS ARE SEEN, at the user's request. A round in this
   game is a hitscan — it has arrived before the tic is over — so a
   tracer is not the round, it is a streak of light drawn along the
   line the round took, from the muzzle to wherever it stopped, moving
   fast enough to read as flight and gone when it gets there. Every
   other round is one, which is how a belt is loaded. It is VERY LONG,
   at the user's request — four hundred and twenty units, a good part
   of the way down an aisle — and it starts at the end of the barrel:
   the head leaves the muzzle and the tail stays there until the
   streak is its full length, so what you see is a line of light
   drawn out of the gun rather than one appearing in front of it.

   A STREAK IS A QUAD THAT FACES YOU ALONG ITS LENGTH: two corners at
   the tail, two at the head, spread sideways along the direction that
   is across both the streak and the line to the eye, so it is a line
   of light from wherever you stand and never a sliver seen edge-on.
   Bright at the head, dying toward the tail, additive, its own light.
   One draw call for the lot.

   Positions are GAME coordinates (x, y across the map, z up); the mesh
   is built in three's (x, z, -y) like everything else.
   ===================================================================== */

import * as THREE from 'three';

export const MAX_TRACERS = 128;
export const TRACER_SPEED = 150;   // units a tic
export const TRACER_LEN = 420;     // units long, at the user's request: very
export const TRACER_WIDTH = 2.6;   // units across
/* AND ONE THAT HAS ARRIVED AT YOUR FACE IS NOT DRAWN. A streak is a
   quad two and a half units across and four hundred long, which is a
   line of light at any distance you would ever see one — and a wall
   of white when its head is six units from the eye, because at six
   units two and a half units subtends a quarter of the screen. It
   never came up while the only thing firing tracers was the gun in
   your hands, whose rounds fly AWAY: a hundred and fifty units a tic,
   so its head is over the far side of the car park by the first frame
   anybody sees it. The gunship's rounds come the other way and STOP
   ON YOU — the head parks at the hit and the tail shrinks into it over
   the next few tics — so what a burst looked like was half a dozen
   white wedges filling the frame, one per round that had landed.

   Past this and it is a streak. Inside it, it is a round that has
   already hit you, and the thing to draw for that is nothing. */
export const NEAR_EYE = 44;        // units: a hit this close leaves no streak

/* THE TAIL NEVER LEAVES THE MUZZLE BEHIND. A streak this long would
   otherwise hang out of the back of the gun and through the eye for
   its first two tics; so the tail is the head less the length, held at
   the muzzle until the head has flown a whole length — the streak
   GROWS out of the barrel, the way one does — and once the head has
   arrived it is the tail that keeps flying, shrinking the streak into
   the hit, until nothing is left. That is `trav`: how far the head
   would have flown by now, past the hit or not. */

const VERT = /* glsl */`
attribute float aFade;
varying float vFade;
void main() {
  vFade = aFade;
  gl_Position = projectionMatrix * viewMatrix * vec4(position, 1.0);
}
`;
const FRAG = /* glsl */`
varying float vFade;
void main() {
  /* a hot white core going to yellow, then orange, along the tail */
  float f = floor(vFade * 4.0 + 0.5) / 4.0;
  vec3 c = mix(vec3(1.0, 0.45, 0.10), vec3(1.0, 0.97, 0.80), f);
  gl_FragColor = vec4(c, f * 0.9);
}
`;

export class Tracers {
  constructor(game) {
    this.game = game;
    const n = MAX_TRACERS;
    this.alive = new Uint8Array(n);
    this.x = new Float32Array(n); this.y = new Float32Array(n); this.z = new Float32Array(n);   // the head
    this.dx = new Float32Array(n); this.dy = new Float32Array(n); this.dz = new Float32Array(n); // unit direction
    this.ox = new Float32Array(n); this.oy = new Float32Array(n); this.oz = new Float32Array(n); // the muzzle
    this.ex = new Float32Array(n); this.ey = new Float32Array(n); this.ez = new Float32Array(n); // where it stops
    this.d = new Float32Array(n);                                                                // muzzle to hit
    this.trav = new Float32Array(n);                                                             // how far the head has flown
    this.left = new Float32Array(n);                                                             // distance still to go
    this.next = 0;
    this.count = 0;
    this.mesh = null;
  }

  /** From the muzzle toward the hit. Round-robin: a burst that wants
   *  more than the pool holds reuses the oldest, which nobody sees. */
  spawn(from, to) {
    const dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z;
    const d = Math.hypot(dx, dy, dz);
    if (d < 4) return -1;
    const i = this.next; this.next = (this.next + 1) % MAX_TRACERS;
    if (!this.alive[i]) this.count++;
    this.alive[i] = 1;
    this.x[i] = from.x; this.y[i] = from.y; this.z[i] = from.z;
    this.ox[i] = from.x; this.oy[i] = from.y; this.oz[i] = from.z;
    this.dx[i] = dx / d; this.dy[i] = dy / d; this.dz[i] = dz / d;
    this.ex[i] = to.x; this.ey[i] = to.y; this.ez[i] = to.z;
    this.d[i] = d; this.trav[i] = 0;
    this.left[i] = d;
    return i;
  }

  tic() {
    for (let i = 0; i < MAX_TRACERS; i++) {
      if (!this.alive[i]) continue;
      this.trav[i] += TRACER_SPEED;
      const at = Math.min(this.trav[i], this.d[i]);
      this.x[i] = this.ox[i] + this.dx[i] * at; this.y[i] = this.oy[i] + this.dy[i] * at; this.z[i] = this.oz[i] + this.dz[i] * at;
      this.left[i] = this.d[i] - at;
      /* the head has arrived and the tail has caught it up: gone */
      if (this.trav[i] - TRACER_LEN >= this.d[i]) { this.alive[i] = 0; this.count--; }
    }
  }

  attach(scene) {
    const N = MAX_TRACERS;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 12), 3));
    g.setAttribute('aFade', new THREE.BufferAttribute(new Float32Array(N * 4), 1));
    const idx = new Uint16Array(N * 6);
    for (let i = 0; i < N; i++) { const v = i * 4, k = i * 6; idx[k] = v; idx[k + 1] = v + 1; idx[k + 2] = v + 2; idx[k + 3] = v; idx[k + 4] = v + 2; idx[k + 5] = v + 3; }
    g.setIndex(new THREE.BufferAttribute(idx, 1));
    g.setDrawRange(0, 0);
    const mat = new THREE.ShaderMaterial({
      vertexShader: VERT, fragmentShader: FRAG, transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false, toneMapped: false,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 12;
    this.mesh.name = 'tracers';
    scene.add(this.mesh);
  }

  /** `ex, ey, ez` is the eye, in game coordinates. */
  render(ex, ey, ez) {
    if (!this.mesh) return;
    const g = this.mesh.geometry;
    const pos = g.attributes.position.array, fade = g.attributes.aFade.array;
    let n = 0;
    for (let i = 0; i < MAX_TRACERS; i++) {
      if (!this.alive[i]) continue;
      const hx = this.x[i], hy = this.y[i], hz = this.z[i];
      /* the tail: TRACER_LEN behind the head, but never behind the
         muzzle — a tracer just out of the barrel is short and grows,
         which is also what one looks like — and never ahead of the hit */
      const back = Math.min(Math.max(0, this.trav[i] - TRACER_LEN), this.d[i]);
      const tx = this.ox[i] + this.dx[i] * back, ty = this.oy[i] + this.dy[i] * back, tz = this.oz[i] + this.dz[i] * back;
      if (back >= this.d[i]) continue;
      /* sideways: across the streak and the line to the eye */
      const vx = ex - hx, vy = ey - hy, vz = ez - hz;
      /* and nothing at all for one that has landed on you — see NEAR_EYE */
      if (vx * vx + vy * vy + vz * vz < NEAR_EYE * NEAR_EYE) continue;
      let sx = this.dy[i] * vz - this.dz[i] * vy, sy = this.dz[i] * vx - this.dx[i] * vz, sz = this.dx[i] * vy - this.dy[i] * vx;
      const sl = Math.hypot(sx, sy, sz) || 1;
      const w = TRACER_WIDTH / 2;
      sx = sx / sl * w; sy = sy / sl * w; sz = sz / sl * w;
      const o = n * 12;
      const put = (k, x, y, z) => { pos[o + k * 3] = x; pos[o + k * 3 + 1] = z; pos[o + k * 3 + 2] = -y; };
      put(0, tx - sx, ty - sy, tz - sz); put(1, tx + sx, ty + sy, tz + sz);
      put(2, hx + sx, hy + sy, hz + sz); put(3, hx - sx, hy - sy, hz - sz);
      fade[n * 4] = 0; fade[n * 4 + 1] = 0; fade[n * 4 + 2] = 1; fade[n * 4 + 3] = 1;
      n++;
    }
    g.setDrawRange(0, n * 6);
    g.attributes.position.needsUpdate = true;
    g.attributes.aFade.needsUpdate = true;
  }

  get liveCount() { return this.count; }
}
