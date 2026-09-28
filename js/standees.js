/* =====================================================================
   MEWD — a crowd in as many draw calls as it has
   pictures
   =====================================================================

   Every thing in this game that is a SPRITE — the shoppers, the
   trolleys, the crates, the bollards, the headstones — used to be its
   own mesh with its own material. That is the obvious way to do it and
   it is what js/actor.js did for a long time, because the quad is spun
   and scaled by uniforms and uniforms belong to a material.

   IT COSTS ONE DRAW CALL AND ONE UNIFORM BLOCK PER PERSON. Measured, in
   the car park at eight in the morning: seven hundred and seventy-two
   things drawn, and nine hundred and seventy-four draw calls in the
   frame. The crowd was four fifths of the frame's draw calls and most
   of what the renderer did with its time.

   AND THEY SHARE TWENTY-EIGHT PICTURES BETWEEN THEM. That is the whole
   of why this file exists. A shopper is ONE drawing that faces every
   way — js/spriteload.js says so at the top, and it is true of
   everything that came off a strip — so seven hundred and seventy-two
   people are seventeen shoppers repeated, plus the trolleys and the
   crates. Batch by PICTURE and the crowd is twenty-eight calls.

   HOW. One InstancedBufferGeometry per texture: a unit quad, and a
   buffer of where each instance is, how big, how lit, and the four
   flags the fragment shader reads per sprite. The shader is the SAME
   shader — see the INSTANCED_SPRITE block in js/material.js, where the
   four values that were uniforms are declared as varyings under the
   same names, so that not one line of the body of either stage knows
   which way it is being drawn. A crowd drawn this way cannot look
   different from a crowd drawn the other way.

   THE BATCHES ARE KEPT, not rebuilt: a texture that has been drawn once
   keeps its buffers for the rest of the session and its instance count
   goes to zero on the frames nobody is in front of it. Nothing is
   allocated per frame; the buffers double when a crowd outgrows them
   and never shrink, which for a fixed cast is a handful of doublings at
   the start and none afterwards.

   WHAT THIS IS NOT. It is not an atlas. An atlas would make the whole
   crowd ONE call rather than twenty-eight, and it would mean packing
   every sprite in the game into one texture and carrying a UV rect per
   instance. Twenty-eight is close enough to one that the packing is not
   worth what it would cost to get wrong, and the gap between 974 and
   about 230 is the part that mattered.

   SORTING DOES NOT ARISE. Every sprite here is a CUT-OUT: alpha-tested,
   depth-written, no blending. Two of them in any order come out the
   same, which is the reason Doom could draw its sprites in whatever
   order it liked too.
   ===================================================================== */

import * as THREE from 'three';
import { createStandeeMaterial } from './material.js';

/* how many instances a batch starts with, and the most it will ever
   hold. The cap is a guard against a runaway, not a budget: the whole
   cast of the game is about two thousand and the most ever drawn at
   once is under a thousand. */
const START = 64;
const MAX = 4096;

export class Standees {
  constructor(game) {
    this.game = game;
    this.scene = null;
    /** texture -> batch */
    this.batches = new Map();
    /** the same batches in a stable order, for the per-frame walk */
    this.order = [];
    /** how many instances went in last frame, over all batches */
    this.drawn = 0;
    this.billboardRot = 0;
  }

  attach(scene) { this.scene = scene; }

  /** Start a frame. Every batch goes back to empty; none is thrown away. */
  begin(billboardRot) {
    this.billboardRot = billboardRot;
    for (let i = 0; i < this.order.length; i++) this.order[i].n = 0;
    this.drawn = 0;
  }

  _grow(b, cap) {
    const old = b.a;
    const a = {
      pos:   new THREE.InstancedBufferAttribute(new Float32Array(cap * 3), 3),
      size:  new THREE.InstancedBufferAttribute(new Float32Array(cap * 2), 2),
      light: new THREE.InstancedBufferAttribute(new Float32Array(cap), 1),
      sky:   new THREE.InstancedBufferAttribute(new Float32Array(cap), 1),
      flags: new THREE.InstancedBufferAttribute(new Float32Array(cap * 4), 4),
      /* the colour of the light it stands in — Doom 64's thing colour */
      tint:  new THREE.InstancedBufferAttribute(new Float32Array(cap * 3).fill(1), 3),
      /* and the fog it stands in: rgb and density, or a density of -1
         for whatever the sector grid says (js/sectorgrid.js) */
      fog:   new THREE.InstancedBufferAttribute(new Float32Array(cap * 4), 4),
    };
    for (const k in a) {
      a[k].setUsage(THREE.DynamicDrawUsage);
      if (old) a[k].array.set(old[k].array.subarray(0, Math.min(old[k].array.length, a[k].array.length)));
    }
    b.a = a; b.cap = cap;
    const g = b.mesh.geometry;
    g.setAttribute('iPos', a.pos);
    g.setAttribute('iSize', a.size);
    g.setAttribute('iLight', a.light);
    g.setAttribute('iSky', a.sky);
    g.setAttribute('iFlags', a.flags);
    g.setAttribute('iTint', a.tint);
    g.setAttribute('iFog', a.fog);
  }

  _batch(tex) {
    let b = this.batches.get(tex);
    if (b) return b;
    const base = new THREE.PlaneGeometry(1, 1);
    base.translate(0, 0.5, 0);            // the foot of the quad is the origin
    const g = new THREE.InstancedBufferGeometry();
    g.index = base.index;
    g.setAttribute('position', base.getAttribute('position'));
    g.setAttribute('uv', base.getAttribute('uv'));
    g.instanceCount = 0;
    const mesh = new THREE.Mesh(g, createStandeeMaterial(tex));
    mesh.frustumCulled = false;           // the quads are placed in the shader
    mesh.name = 'standees';
    b = { tex, mesh, n: 0, cap: 0, a: null };
    this._grow(b, START);
    this.batches.set(tex, b);
    this.order.push(b);
    if (this.scene) this.scene.add(mesh);
    return b;
  }

  /**
   * One standee, this frame.
   *
   * `x, y, z` are RENDERER coordinates — the map's y is the renderer's
   * minus z and every caller was already doing that conversion when it
   * set a mesh's position, so it keeps doing it. `w, h` are the world
   * size of the quad, `light` and `sky` what the region it stands in is
   * lit to and how much of that is the sky's, the next four are the
   * flags the fragment shader reads per sprite, and `warm` says the
   * thing is a living body, which only the thermal sight asks.
   */
  add(tex, x, y, z, w, h, light, sky, fullbright, frost, ash, alight, warm = 0, tint = null, fog = null) {
    if (!tex || !this.scene) return false;
    const b = this._batch(tex);
    /* A BODY'S PICTURE IS A BODY'S, for the thermal sight: once a person
       has been drawn with it the batch is warm for good, and a trolley's
       never is — see `warm` in js/material.js */
    if (warm && !b.warm) { b.warm = true; b.mesh.material.uniforms.warm.value = 1; }
    if (b.n >= b.cap) {
      if (b.cap >= MAX) return false;
      this._grow(b, Math.min(MAX, b.cap * 2));
    }
    const i = b.n++;
    const P = b.a.pos.array, S = b.a.size.array, L = b.a.light.array,
          K = b.a.sky.array, F = b.a.flags.array;
    P[i * 3] = x; P[i * 3 + 1] = y; P[i * 3 + 2] = z;
    S[i * 2] = w; S[i * 2 + 1] = h;
    L[i] = light;
    K[i] = sky;
    F[i * 4] = fullbright; F[i * 4 + 1] = frost; F[i * 4 + 2] = ash; F[i * 4 + 3] = alight;
    const T = b.a.tint.array;
    if (tint) { T[i * 3] = tint[0]; T[i * 3 + 1] = tint[1]; T[i * 3 + 2] = tint[2]; }
    else { T[i * 3] = 1; T[i * 3 + 1] = 1; T[i * 3 + 2] = 1; }
    const G = b.a.fog.array;
    if (fog) { G[i * 4] = fog[0]; G[i * 4 + 1] = fog[1]; G[i * 4 + 2] = fog[2]; G[i * 4 + 3] = fog[3]; }
    else { G[i * 4] = 0; G[i * 4 + 1] = 0; G[i * 4 + 2] = 0; G[i * 4 + 3] = -1; }
    this.drawn++;
    return true;
  }

  /** Send what went in and set the counts. */
  end() {
    for (let k = 0; k < this.order.length; k++) {
      const b = this.order[k];
      b.mesh.visible = b.n > 0;
      b.mesh.geometry.instanceCount = b.n;
      if (!b.n) continue;
      b.mesh.material.uniforms.billboardRot.value = this.billboardRot;
      /* only the part that was filled: the buffers are sized for the
         worst crowd this batch has ever had and the frame in a corridor
         is three of them */
      for (const key of ['pos', 'size', 'light', 'sky', 'flags', 'tint', 'fog']) {
        const at = b.a[key];
        at.clearUpdateRanges();
        at.addUpdateRange(0, b.n * at.itemSize);
        at.needsUpdate = true;
      }
    }
  }

  /** How many batches exist, which is how many draw calls the crowd is. */
  get batchCount() {
    let n = 0;
    for (let k = 0; k < this.order.length; k++) if (this.order[k].n > 0) n++;
    return n;
  }

  detach(scene) {
    for (const b of this.order) {
      scene.remove(b.mesh);
      b.mesh.geometry.dispose();
      b.mesh.material.dispose();
    }
    this.batches.clear();
    this.order.length = 0;
    this.scene = null;
  }
}
