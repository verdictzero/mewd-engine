/* =====================================================================
   MEWD — particles: one draw call of little billboards
   =====================================================================

   The flame coming out of the gun, the embers lifting off a burning
   aisle and the smoke over the forest are all the same thing drawn
   three ways: a lot of small quads facing the camera, moving, getting
   bigger or smaller, changing colour, dying. So there is one class,
   and each effect is an instance of it with its own picture and its
   own blending.

   WHY INSTANCED. The fire sprites on the floor are a pool of separate
   meshes, and at ninety-six of them that is already ninety-six draw
   calls. A flame stream at thirty-five tics a second wants a few
   hundred particles alive at once, and embers over a forest fire a few
   hundred more. Meshes at that count would cost more in draw calls than
   the whole level does in triangles. As instances they are ONE call
   each: a unit quad, and a buffer of positions, sizes, colours and
   frames the CPU fills in once a frame. Updating a thousand entries in
   a typed array is nothing; a thousand draw calls is a frame.

   WHY STRUCT-OF-ARRAYS. Every field of every particle is a typed array
   indexed by slot, and a dead slot goes on a free list. Nothing is
   allocated after start-up however long the store burns, and the
   update loop is a straight run over flat memory.

   THE PHYSICS IS DELIBERATELY SMALL: velocity, drag, gravity, and a
   hook the owner can use to stop a particle on a wall or a floor. The
   flame needs the hook; the smoke does not; the embers use it to land.
   Everything else — what to spawn, where, and how many — is the
   owner's business and is done in js/flame.js and js/effects.js.
   ===================================================================== */

import * as THREE from 'three';
import { WORLD_UNIFORMS_GLSL, WORLD_SHADE_GLSL, worldUniforms } from './material.js';

const VERT = /* glsl */`
attribute vec3  iPos;
attribute float iSize;
attribute vec4  iColor;
attribute float iFrame;
uniform float billboardRot;
uniform float frames;
uniform float nearShrink;   // inside this many units of the eye a particle shrinks with distance
varying vec2  vUv;
varying vec4  vColor;
varying float vDepth;
varying vec3  vWorld;

void main() {
  vUv = vec2((uv.x + iFrame) / frames, uv.y);
  vColor = iColor;
  /* A unit quad centred on its particle, scaled, then yawed to face the
     camera PLANE — never tilted, for the same reason no sprite in this
     game tilts.

     And SHRUNK when it is very close. An ember is three units across,
     which at arm's length is a tenth of the screen: walk into the sparks
     you just made and the picture fills with beige squares. Inside
     nearShrink units the size falls with the distance, so the closest a
     particle ever gets to the eye is the size it had at that range. */
  float dpt = -(viewMatrix * vec4(iPos, 1.0)).z;
  float shrink = nearShrink > 0.0 ? clamp(dpt / nearShrink, 0.12, 1.0) : 1.0;
  vec3 p = position * iSize * shrink;
  float c = cos(billboardRot), s = sin(billboardRot);
  p = vec3(p.x * c, p.y, -p.x * s) + iPos;
  vWorld = p;
  vec4 mv = viewMatrix * vec4(p, 1.0);
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;
}
`;

const FRAG = /* glsl */`
uniform sampler2D map;
uniform float alphaTest;
uniform float fullbright;
uniform float light;
${WORLD_UNIFORMS_GLSL}
varying vec2  vUv;
varying vec4  vColor;
varying float vDepth;
varying vec3  vWorld;
${WORLD_SHADE_GLSL}

void main() {
  vec4 t = texture2D(map, vUv);
  float a = t.a * vColor.a;
  if (a < alphaTest) discard;
  float l = worldBand(light, vDepth, 1.0, fullbright);
  vec3 c = worldShade(t.rgb * vColor.rgb, l, vDepth, vWorld, fullbright);
  gl_FragColor = vec4(c, a);
}
`;

export class Particles {
  /**
   * @param {object} opts
   *   max        pool size — the hard cap on how many can exist
   *   texture    an atlas of `frames` equal frames laid out left to right
   *   frames     how many
   *   blend      'cutout' (alpha-tested, writes depth, the Doom way),
   *              'alpha' (blended, no depth write — smoke),
   *              'add'   (additive — glow)
   *   fullbright true for anything that is its own light
   *   light      sector light to shade an unlit one by (0..1)
   */
  constructor(opts) {
    this.max = opts.max;
    const n = this.max;
    this.alive = new Uint8Array(n);
    this.free = [];
    for (let i = n - 1; i >= 0; i--) this.free.push(i);
    this.count = 0;

    this.x = new Float32Array(n); this.y = new Float32Array(n); this.z = new Float32Array(n);
    this.vx = new Float32Array(n); this.vy = new Float32Array(n); this.vz = new Float32Array(n);
    this.age = new Float32Array(n); this.life = new Float32Array(n);
    this.size0 = new Float32Array(n); this.size1 = new Float32Array(n);
    this.r0 = new Float32Array(n); this.g0 = new Float32Array(n); this.b0 = new Float32Array(n); this.a0 = new Float32Array(n);
    this.r1 = new Float32Array(n); this.g1 = new Float32Array(n); this.b1 = new Float32Array(n); this.a1 = new Float32Array(n);
    this.frame = new Float32Array(n); this.frameRate = new Float32Array(n);
    this.drag = new Float32Array(n); this.gravity = new Float32Array(n);
    this.kind = new Uint8Array(n);
    this.data = new Float32Array(n);

    this.opts = opts;
    this.mesh = null;
    this.tics = 0;
  }

  /* ------------------------------------------------------------------
     The pool
     ------------------------------------------------------------------ */
  /**
   * Bring one to life. Returns its slot, or -1 when the pool is full —
   * which is a budget, not an error: an effect that wants more than the
   * pool holds is asking for more than the frame can afford.
   *
   * Positions are GAME coordinates (x, y across the map, z up); the
   * renderer's axes are sorted out at draw time.
   */
  spawn(o) {
    if (!this.free.length) return -1;
    const i = this.free.pop();
    this.alive[i] = 1; this.count++;
    this.x[i] = o.x; this.y[i] = o.y; this.z[i] = o.z;
    this.vx[i] = o.vx || 0; this.vy[i] = o.vy || 0; this.vz[i] = o.vz || 0;
    this.age[i] = o.age || 0; this.life[i] = Math.max(1, o.life || 30);
    this.size0[i] = o.size0 ?? o.size ?? 8; this.size1[i] = o.size1 ?? o.size ?? this.size0[i];
    const c0 = o.c0 || [1, 1, 1], c1 = o.c1 || c0;
    this.r0[i] = c0[0]; this.g0[i] = c0[1]; this.b0[i] = c0[2]; this.a0[i] = o.a0 ?? 1;
    this.r1[i] = c1[0]; this.g1[i] = c1[1]; this.b1[i] = c1[2]; this.a1[i] = o.a1 ?? this.a0[i];
    this.frame[i] = o.frame || 0; this.frameRate[i] = o.frameRate || 0;
    this.drag[i] = o.drag ?? 1; this.gravity[i] = o.gravity || 0;
    this.kind[i] = o.kind || 0; this.data[i] = o.data || 0;
    return i;
  }

  kill(i) {
    if (!this.alive[i]) return;
    this.alive[i] = 0; this.count--;
    this.free.push(i);
  }

  killAll() { for (let i = 0; i < this.max; i++) if (this.alive[i]) this.kill(i); }

  /* ------------------------------------------------------------------
     One tic

     `collide(i, nx, ny, nz)` is asked before a particle moves, with
     where it is about to be. Return true to say it has hit something —
     the owner has dealt with it and it dies here.
     ------------------------------------------------------------------ */
  tic(collide = null) {
    this.tics++;
    const { alive, x, y, z, vx, vy, vz, age, life } = this;
    for (let i = 0; i < this.max; i++) {
      if (!alive[i]) continue;
      if (++age[i] >= life[i]) { this.kill(i); continue; }
      vz[i] += this.gravity[i];
      const d = this.drag[i];
      if (d !== 1) { vx[i] *= d; vy[i] *= d; vz[i] *= d; }
      const nx = x[i] + vx[i], ny = y[i] + vy[i], nz = z[i] + vz[i];
      if (collide && collide(i, nx, ny, nz)) { this.kill(i); continue; }
      x[i] = nx; y[i] = ny; z[i] = nz;
    }
  }

  /* ------------------------------------------------------------------
     Drawing
     ------------------------------------------------------------------ */
  attach(scene) {
    if (this.mesh) return this.mesh;
    const o = this.opts;
    const base = new THREE.PlaneGeometry(1, 1);
    const g = new THREE.InstancedBufferGeometry();
    g.index = base.index;
    g.setAttribute('position', base.getAttribute('position'));
    g.setAttribute('uv', base.getAttribute('uv'));
    const n = this.max;
    this._aPos = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3).setUsage(THREE.DynamicDrawUsage);
    this._aSize = new THREE.InstancedBufferAttribute(new Float32Array(n), 1).setUsage(THREE.DynamicDrawUsage);
    this._aColor = new THREE.InstancedBufferAttribute(new Float32Array(n * 4), 4).setUsage(THREE.DynamicDrawUsage);
    this._aFrame = new THREE.InstancedBufferAttribute(new Float32Array(n), 1).setUsage(THREE.DynamicDrawUsage);
    g.setAttribute('iPos', this._aPos);
    g.setAttribute('iSize', this._aSize);
    g.setAttribute('iColor', this._aColor);
    g.setAttribute('iFrame', this._aFrame);
    g.instanceCount = 0;

    const blend = o.blend || 'cutout';
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        map: { value: o.texture },
        frames: { value: o.frames || 1 },
        billboardRot: { value: 0 },
        nearShrink: { value: o.nearShrink ?? 0 },
        alphaTest: { value: blend === 'cutout' ? 0.5 : 0.02 },
        fullbright: { value: o.fullbright ? 1 : 0 },
        light: { value: o.light ?? 0.6 },
        ...worldUniforms(),
      },
      vertexShader: VERT,
      fragmentShader: FRAG,
      transparent: blend !== 'cutout',
      depthWrite: blend === 'cutout',
      blending: blend === 'add' ? THREE.AdditiveBlending : THREE.NormalBlending,
      side: THREE.DoubleSide,
      toneMapped: false,
      fog: false,
    });
    this.mesh = new THREE.Mesh(g, mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = o.renderOrder ?? 12;
    this.mesh.name = o.name || 'particles';
    scene.add(this.mesh);
    return this.mesh;
  }

  /** Pack every live particle into the instance buffers. */
  render(billboardRot) {
    if (!this.mesh) return;
    const P = this._aPos.array, S = this._aSize.array, C = this._aColor.array, F = this._aFrame.array;
    let n = 0;
    for (let i = 0; i < this.max; i++) {
      if (!this.alive[i]) continue;
      const t = this.age[i] / this.life[i];
      P[n * 3] = this.x[i]; P[n * 3 + 1] = this.z[i]; P[n * 3 + 2] = -this.y[i];
      S[n] = this.size0[i] + (this.size1[i] - this.size0[i]) * t;
      C[n * 4]     = this.r0[i] + (this.r1[i] - this.r0[i]) * t;
      C[n * 4 + 1] = this.g0[i] + (this.g1[i] - this.g0[i]) * t;
      C[n * 4 + 2] = this.b0[i] + (this.b1[i] - this.b0[i]) * t;
      C[n * 4 + 3] = this.a0[i] + (this.a1[i] - this.a0[i]) * t;
      F[n] = Math.floor(this.frame[i] + this.age[i] * this.frameRate[i]) % (this.opts.frames || 1);
      n++;
    }
    this._aPos.needsUpdate = true; this._aSize.needsUpdate = true;
    this._aColor.needsUpdate = true; this._aFrame.needsUpdate = true;
    this.mesh.geometry.instanceCount = n;
    this.mesh.visible = n > 0;
    this.mesh.material.uniforms.billboardRot.value = billboardRot;
  }
}

/* --------------------------------------------------------------------
   Atlases

   A Particles wants one texture with its frames side by side. These
   build the two the game needs out of Pix frames — the flame from the
   same generator the floor fire uses, so the stream and what it lights
   are the same fire, and a soft blob for smoke.
   ------------------------------------------------------------------ */
/** A strip that arrived as a picture, as a particle atlas texture. */
export function imageTexture(img) {
  const t = new THREE.Texture(img);
  t.magFilter = THREE.NearestFilter;
  t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.needsUpdate = true;
  return t;
}

export function atlasTexture(frames) {
  const w = frames[0].w, h = frames[0].h;
  const c = document.createElement('canvas');
  c.width = w * frames.length; c.height = h;
  const ctx = c.getContext('2d');
  frames.forEach((f, i) => ctx.drawImage(f.toCanvas(), i * w, 0));
  const t = new THREE.CanvasTexture(c);
  t.magFilter = THREE.NearestFilter;
  t.minFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.needsUpdate = true;
  return t;
}
