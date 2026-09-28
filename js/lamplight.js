/* =====================================================================
   MEWD — the street lamps' own light
   =====================================================================

   Every street lamp in the town is a photograph stood up in the map
   (THE STREET LAMP IS GEOMETRY, js/mapgeo.js), and a photograph of a
   lamp is a lamp that is off. This is the part that is on.

   WHAT A LAMP IS AT NIGHT, from across a street, is not a lit pole. It
   is a point of cold light with a line across it — the bloom of the
   luminaire, and the streak a bright source puts across a lens — and
   the pavement under it going pale. The pavement is the map's job: the
   pool sector, tinted by its own shader (vLamp in js/material.js). The
   point and the line are this file's: ONE ANAMORPHIC FLARE PER LAMP,
   drawn the way the gunship's searchlight is drawn in js/vtol.js and
   for the same reason — a flare is what you actually read a light by
   after dark — but small, and cold, and forty at a time.

   ONE MESH FOR ALL OF THEM. The gunship has one lamp and one Flare with
   a uniform for where it is; the town has four hundred, and four
   hundred meshes with four hundred uniform updates a frame is the
   crowd's problem all over again (see the culling note on Actor.render
   in js/actor.js). So the flares are one buffer of LAMP_SLOTS quads and
   the centre of each is an ATTRIBUTE rather than a uniform: every
   frame the nearest lamps that could be seen at all are dealt into the
   slots, their lens points and their glow are written into the buffer,
   and it is one draw call whether that is three lamps or forty.

   WHICH LAMPS. Cheapest test first: within LAMP_FAR; not well behind
   the eye; in a region the portal flood says is visible (the same
   Level.visibleSectors every sprite in the game defers to); then the
   nearest LAMP_SLOTS of what is left. And then the one that costs
   something — a SIGHT LINE from the eye to the lens, the same call a
   trooper uses to decide whether it can see you — so a lamp behind a
   house does not flare through the house. It is asked of a third of
   the slots each frame rather than all of them, and its answer is
   EASED onto over about a sixth of a second (the gunship flare's own
   figure), because a flare that pops off at a wall edge reads as the
   flare being broken rather than as the lamp going behind something.

   SUBTLE, AND IT FADES WITH DISTANCE, at the user's request. The
   gunship's flare is most of the frame across; this one is a fifth of
   it and thin, and its glow falls off as the square of the distance to
   nothing at LAMP_FAR — and its size is pulled in with it, so a lamp at
   the end of the street is a point with a hair across it and the one
   over your head is a lamp. Additive, over everything, no depth test:
   whether a wall is in the way is the sight line's answer, not the
   depth buffer's, for the reason at Flare in js/vtol.js.

   AND ONLY AFTER DARK. lampsOn is the same curve the pavement's shader
   runs on the sky's light — on as the sky goes under a half, full by a
   fifth — so the flare and the pool under it switch together, at dusk
   and at dawn, and in a storm dark enough to trip a photocell. The
   colour is LAMP_LIGHT from js/material.js, the same one the pavement
   is tinted by: mercury vapour, cold, with green in it.
   ===================================================================== */

import * as THREE from 'three';
import { world, LAMP_LIGHT } from './material.js';
import { STREET_LAMP } from './textures.js';

/** Past this a lamp's light is not drawn at all. */
export const LAMP_FAR = 2400;
/** How many lamps get a flare at once: the nearest that many. */
export const LAMP_SLOTS = 40;
/* how fast a flare eases onto what the sight line said, per frame */
const EASE = 0.28;
/* frames between sight tests on any one slot */
const LOOK_EVERY = 3;
/* how bright a flare is at full, before the fade: subtle */
const GAIN = 0.95;
/* half width and half height of the quad, as a fraction of the distance
   to it — which is what makes it the same size on the screen wherever
   the lamp is. The gunship's is 0.88 by 0.105. */
const SIZE = [0.19, 0.032];
/* the bloom's radius, as a fraction of the half height */
const BALL = 0.55;

/** How much the street lamps are on, 0 to 1, off the sky's light: the
 *  same smoothstep as lampsOn in js/material.js, and the two must not
 *  drift apart. */
export function lampsOn(skyLight) {
  const t = Math.min(1, Math.max(0, (skyLight - 0.22) / (0.50 - 0.22)));
  return 1 - t * t * (3 - 2 * t);
}

const VERT = /* glsl */`
attribute vec2  corner;
attribute vec3  centre;
attribute float glow;
uniform vec2  size;
uniform float far;
varying vec2  vC;
varying float vGlow;
void main() {
  vC = corner;
  vec4 mv = viewMatrix * vec4(centre, 1.0);
  float d = -mv.z;
  /* the fade: with the distance and a half, to nothing at far — a
     lamp halfway down the street is a third as bright as the one over
     you, and the last one you can see is a point */
  float k = clamp(1.0 - d / far, 0.0, 1.0);
  vGlow = glow * k * sqrt(k);
  /* BEHIND THE EYE IS NOWHERE — see FLARE_VERT in js/vtol.js for the
     white bowtie this line prevents — and so is a slot with nothing in
     it */
  if (d < 0.5 || vGlow < 0.004) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); return; }
  /* sized by the distance, so it is the same size on the screen
     wherever the lamp is, and then pulled in with the fade, so a far
     lamp is a point */
  mv.xy += corner * size * d * (0.5 + 0.5 * k);
  gl_Position = projectionMatrix * mv;
}
`;

const FRAG = /* glsl */`
uniform vec3  color;
uniform float aspect;      // width over height of the quad
uniform float ball;        // the bloom's radius, as a fraction of the height
varying vec2  vC;
varying float vGlow;
void main() {
  /* the streak: sharp across, soft along, the anamorphic line a lens
     puts through a bright point — fainter and shorter than the
     gunship's, because this is a street lamp and not a searchlight */
  float ax = abs(vC.x), ay = abs(vC.y);
  float along = pow(max(0.0, 1.0 - ax), 0.7);
  float streak = exp(-ay * 30.0) * along + exp(-ay * 7.0) * along * along * 0.12;
  /* the bloom: a radial gradient, white at the heart */
  vec2 q = vec2(vC.x * aspect, vC.y) / ball;
  float r = length(q);
  float sphere = exp(-r * r * 1.8) * 1.1 + exp(-r * 4.5) * 0.9;
  /* the streak is bluer than the lamp — it is the lens's colour, not
     the light's, which is what an anamorphic flare is — and the bloom
     goes to white at the heart */
  vec3 c = mix(color, vec3(0.55, 0.80, 1.0), 0.5) * streak * 0.55
         + mix(color, vec3(1.0), clamp(sphere * 0.5, 0.0, 1.0)) * sphere;
  /* and stepped, a little, because everything in this game is */
  c = floor(c * vGlow * 24.0 + 0.5) / 24.0;
  if (c.r + c.g + c.b < 0.02) discard;
  gl_FragColor = vec4(c, 1.0);
}
`;

export class StreetLights {
  constructor(game) {
    this.game = game;
    this.lamps = [];
    this.mesh = null;
    this.centre = null;
    this.glow = null;
    this.frame = 0;
    /** how many had a flare last frame */
    this.drawn = 0;
  }

  /** Every STREETLAMP thing in the level becomes a LENS POINT: the
   *  underside of the luminaire, out along the arm from the foot, off
   *  STREET_LAMP's fractions of the photograph. Returns how many. */
  setLamps(level) {
    const S = STREET_LAMP;
    const along = (S.lens[0] - S.foot) * S.width;
    const up = (1 - S.lens[1]) * S.height;
    this.lamps = [];
    for (const t of level.things || []) {
      if (t.type !== 'STREETLAMP') continue;
      const at = level.sectorAt(t.x, t.y);
      if (!at) continue;
      const x = t.x + Math.cos(t.angle) * along, y = t.y + Math.sin(t.angle) * along;
      const z = level.floorAt(at, t.x, t.y) + up - 2;
      /* the region the LENS hangs over, which is the road's and not the
         pavement's, is the one the flood is asked about */
      const sector = level.sectorAt(x, y) || at;
      this.lamps.push({ x, y, z, sector, vis: 0, seen: false, d: 0, looked: -1 });
    }
    return this.lamps.length;
  }

  attach(scene) {
    const N = LAMP_SLOTS;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(N * 4 * 3), 3));
    const corner = new Float32Array(N * 4 * 2);
    const index = new Uint16Array(N * 6);
    for (let i = 0; i < N; i++) {
      corner.set([-1, -1, 1, -1, 1, 1, -1, 1], i * 8);
      index.set([0, 1, 2, 0, 2, 3].map(k => i * 4 + k), i * 6);
    }
    g.setAttribute('corner', new THREE.BufferAttribute(corner, 2));
    this.centre = new THREE.BufferAttribute(new Float32Array(N * 4 * 3), 3);
    this.glow = new THREE.BufferAttribute(new Float32Array(N * 4), 1);
    this.centre.setUsage(THREE.DynamicDrawUsage);
    this.glow.setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('centre', this.centre);
    g.setAttribute('glow', this.glow);
    g.setIndex(new THREE.BufferAttribute(index, 1));
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        size:   { value: new THREE.Vector2(SIZE[0], SIZE[1]) },
        far:    { value: LAMP_FAR },
        color:  { value: new THREE.Vector3(LAMP_LIGHT[0], LAMP_LIGHT[1], LAMP_LIGHT[2]) },
        aspect: { value: SIZE[0] / SIZE[1] },
        ball:   { value: BALL },
      },
      vertexShader: VERT, fragmentShader: FRAG,
      transparent: true, depthWrite: false, depthTest: false,
      blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false, toneMapped: false,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 40;
    this.mesh.name = 'street lights';
    this.mesh.visible = false;
    scene.add(this.mesh);
  }

  /**
   * Deal the nearest lamps that could be seen into the slots and write
   * them to the buffer. `ex,ey,ez` is the eye, `vx,vy` which way it
   * looks; `night` is how far on the lamps are, and comes off the
   * world's own sky light unless the caller says. Returns how many
   * lamps were drawn.
   */
  render(ex, ey, ez, vx, vy, night = lampsOn(world.skyLight.value)) {
    this.frame++;
    if (!this.mesh) return 0;
    if (night < 0.01 || !this.lamps.length) { this.mesh.visible = false; return (this.drawn = 0); }
    const lv = this.game.level;
    const far2 = LAMP_FAR * LAMP_FAR;
    const near = [];
    for (const L of this.lamps) {
      const dx = L.x - ex, dy = L.y - ey, d2 = dx * dx + dy * dy;
      if (d2 > far2) continue;
      const d = Math.sqrt(d2);
      /* well behind the eye, or in a region the flood cannot see into;
         neither test is asked of anything close, because at that range
         the flare is bigger than the test is right */
      if (d > 160 && dx * vx + dy * vy < -0.25 * d) continue;
      if (d > 160 && lv.isVisible && !lv.isVisible(L.sector)) continue;
      L.d = d;
      near.push(L);
    }
    near.sort((a, b) => a.d - b.d);
    const n = Math.min(LAMP_SLOTS, near.length);
    const c = this.centre.array, g = this.glow.array;
    for (let i = 0; i < n; i++) {
      const L = near[i];
      /* the sight line: a third of the slots a frame, and at once for a
         lamp that has not been asked lately, so one just dealt in does
         not arrive lit through a wall */
      if (this.frame - L.looked >= LOOK_EVERY || (this.frame + i) % LOOK_EVERY === 0) {
        L.seen = !lv.sightBlocked(ex, ey, ez, L.x, L.y, L.z);
        L.looked = this.frame;
      }
      const want = L.seen ? 1 : 0;
      L.vis += (want - L.vis) * EASE;
      if (Math.abs(want - L.vis) < 0.01) L.vis = want;
      const glow = night * L.vis * GAIN;
      for (let k = 0; k < 4; k++) {
        const o = (i * 4 + k) * 3;
        c[o] = L.x; c[o + 1] = L.z; c[o + 2] = -L.y;
        g[i * 4 + k] = glow;
      }
    }
    this.centre.needsUpdate = true;
    this.glow.needsUpdate = true;
    this.mesh.geometry.setDrawRange(0, n * 6);
    this.mesh.visible = n > 0;
    return (this.drawn = n);
  }

  detach(scene) {
    if (!this.mesh) return;
    scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    this.mesh.material.dispose();
    this.mesh = null;
  }
}
