/* =====================================================================
   MEWD — the police lights, and the bloom off them
   =====================================================================

   THE LIGHT BAR. The police van arrives with its light bar as a part of
   its own, on its own material — `DynamicPoliceLightMatEmissive`, which
   is what the user called it and what js/car.js looks for — and it is
   the one surface on any vehicle in this game that is not the sheet.
   Here it is drawn UNLIT: a lamp is as bright as it is, whatever the
   sector light says about the tarmac under it. The bar's left half is
   red and its right half is blue, and they take turns — two quick
   strobes a side, a third of a second each, which is the rhythm of
   every light bar ever fitted — with the half that is off still showing
   its lens colour faintly, because a lens is coloured glass.

   Every van runs its own phase, off its own geometry (`phase`, per
   vertex), so a convoy of five is five bars out of step, not one bar
   copied five times.

   AND THE BLOOM, at the user's request, and SELECTIVE, because this is
   a 256-colour game whose picture is LDR: a threshold bloom over the
   whole frame would halo every white shelf label in the store. So only
   what is on BLOOM_LAYER glows, and today that is the light bars.

   How: after the world is drawn into the buffer, and before the gun in
   your hands is, the scene is drawn again with the camera looking at
   the bloom layer alone into a half-size target. The lamps draw in
   GLOW mode there — `glow` in the shader — and in glow mode a fragment
   reads the depth the world just left behind and throws itself away if
   something nearer is in front of it, so a light bar behind the store
   does not glow through the store. That target is blurred twice at a
   quarter size and the core and the halo are added back onto the
   buffer. Then the overlays draw over the top, so the gun hides the
   bloom the way it hides the lamp — which is why this happens before
   them and not after.

   It costs nothing when there is nothing to glow: `lamps.set` holds
   the bars that are lit, and with none of them in the scene the pass is
   skipped whole.
   ===================================================================== */

import * as THREE from 'three';
import { world } from './material.js';

/** The layer a thing is on to glow. Nothing else uses layers. */
export const BLOOM_LAYER = 5;

/** The bars that are lit right now. A van puts its bar in when it
 *  arrives and takes it out when it goes up (see js/vehicles.js). */
export const lamps = { set: new Set() };

/** Whether any lit bar is in `scene`. One that has left it — a night
 *  thrown away with its vans still on the road — is forgotten here. */
function liveIn(scene) {
  let n = 0;
  for (const m of lamps.set) {
    let r = m;
    while (r.parent) r = r.parent;
    if (r === scene) n++;
    else if (!m.parent || r.isScene) lamps.set.delete(m);
  }
  return n;
}

/* shared by every lamp and by the pass: the clock, whether this is the
   glow draw, and the depth it is read against */
export const lampUniforms = {
  uTime:     { value: 0 },
  uGlow:     { value: 0 },
  tDepth:    { value: null },
  uNearFar:  { value: new THREE.Vector2(4, 16000) },
};

/* the rhythm: one whole cycle in this many seconds, each side's half of
   it two strobes long */
export const FLASH_CYCLE = 0.66;

const LAMP_VERT = /* glsl */`
attribute float side;     // how far left of the bar's middle: + is the left half
attribute float phase;    // this van's own offset into the cycle
varying float vSide;
varying float vPhase;
void main() {
  vSide = side; vPhase = phase;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

const LAMP_FRAG = /* glsl */`
uniform float uTime;
uniform float uGlow;
uniform sampler2D tDepth;
uniform vec2 uNearFar;
uniform vec2 uSize;
uniform float thermal;
uniform float uCycle;
uniform vec3 uLeft, uRight;           // the two lenses
uniform vec3 uLeftGlow, uRightGlow;   // and what each glows
varying float vSide;
varying float vPhase;

float lin(float d) {
  float n = uNearFar.x, f = uNearFar.y;
  return n * f / (f - d * (f - n));
}

void main() {
  /* WHICH HALF IS ON: red first, then blue, two strobes each */
  float t = fract(uTime / uCycle + vPhase);
  float side = vSide > 0.0 ? step(t, 0.5) : step(0.5, t);
  float strobe = step(fract(t * 4.0), 0.62);
  float on = side * strobe;
  vec3 lens = vSide > 0.0 ? uLeft : uRight;
  if (uGlow > 0.5) {
    /* hidden behind something nearer: no glow from here */
    float d = texture2D(tDepth, gl_FragCoord.xy / uSize).r;
    if (lin(gl_FragCoord.z) > lin(d) * 1.015 + 3.0) discard;
    vec3 glow = vSide > 0.0 ? uLeftGlow : uRightGlow;
    gl_FragColor = vec4(glow * on, 1.0);
    return;
  }
  if (thermal > 0.5) { gl_FragColor = vec4(vec3(0.55 + 0.35 * on), 1.0); return; }
  gl_FragColor = vec4(mix(lens * 0.16, mix(lens, vec3(1.0), 0.28), on), 1.0);
}
`;

/* WHAT COLOUR EACH HALF IS, by who is coming. The police are red and
   blue; the fire brigade red and white. The blue GLOWS paler than its
   lens: a deep blue is a dark colour, and a halo of it on a night sky is
   a halo of nothing. */
export const LAMP_COLOURS = {
  police: { left: [1.0, 0.06, 0.04], right: [0.10, 0.25, 1.0], leftGlow: [1.0, 0.06, 0.04], rightGlow: [0.45, 0.72, 1.0] },
  fire:   { left: [1.0, 0.08, 0.04], right: [1.0, 0.95, 0.85], leftGlow: [1.0, 0.08, 0.04], rightGlow: [1.0, 0.85, 0.7] },
};

const lampMats = {};
let darkMat = null;
const lampSize = new THREE.Vector2(1, 1);

/** The material every lit bar of one kind is drawn with — one, for every
 *  van of that kind. */
export function lampMaterial(kind = 'police') {
  if (lampMats[kind]) return lampMats[kind];
  const c = LAMP_COLOURS[kind] || LAMP_COLOURS.police;
  const v3 = a => ({ value: new THREE.Vector3(a[0], a[1], a[2]) });
  const lampMat = lampMats[kind] = new THREE.ShaderMaterial({
    uniforms: {
      ...lampUniforms,
      uSize: { value: lampSize },
      uCycle: { value: FLASH_CYCLE },
      uLeft: v3(c.left), uRight: v3(c.right), uLeftGlow: v3(c.leftGlow), uRightGlow: v3(c.rightGlow),
      /* the thermal sight's switch, read when the first bar is made
         rather than at load: js/material.js reaches this file through
         js/lofi.js, so `world` is not there yet when this one runs */
      thermal: world.thermal,
    },
    vertexShader: LAMP_VERT,
    fragmentShader: LAMP_FRAG,
    side: THREE.DoubleSide,
  });
  return lampMat;
}

/** And the one a bar is drawn with once the van is a wreck: the lenses,
 *  dark, and nothing glowing. */
export function lampDarkMaterial() {
  return darkMat || (darkMat = new THREE.MeshBasicMaterial({ color: 0x1a0c10, side: THREE.DoubleSide }));
}

/* ---------------------------------------------------------------------
   THE PASS
   --------------------------------------------------------------------- */
const POST_VERT = /* glsl */`
precision highp float;
attribute vec3 position;
attribute vec2 uv;
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position, 1.0); }
`;

/* nine taps along one axis, gaussian, spread by `uStep` texels */
const BLUR_FRAG = /* glsl */`
precision highp float;
uniform sampler2D tSrc;
uniform vec2 uDir;
varying vec2 vUv;
void main() {
  vec3 c = texture2D(tSrc, vUv).rgb * 0.2270270;
  c += texture2D(tSrc, vUv + uDir * 1.3846154).rgb * 0.3162162;
  c += texture2D(tSrc, vUv - uDir * 1.3846154).rgb * 0.3162162;
  c += texture2D(tSrc, vUv + uDir * 3.2307692).rgb * 0.0702703;
  c += texture2D(tSrc, vUv - uDir * 3.2307692).rgb * 0.0702703;
  gl_FragColor = vec4(c, 1.0);
}
`;

const ADD_FRAG = /* glsl */`
precision highp float;
uniform sampler2D tCore;
uniform sampler2D tHalo;
uniform float uCore;
uniform float uHalo;
varying vec2 vUv;
void main() {
  vec3 h = texture2D(tHalo, vUv).rgb;
  /* AND THE BLUE LIFTED: the palette has few light blues and a faint
     blue halo snaps to black, where a faint red one snaps to red */
  h += vec3(0.25, 0.45, 1.0) * h.b;
  vec3 c = texture2D(tCore, vUv).rgb * uCore + h * uHalo;
  gl_FragColor = vec4(c, 1.0);
}
`;

/** How strong the glow is: the lamp's own spread, and the wide halo. */
export const BLOOM = { core: 1.6, halo: 9.0 };

export class Bloom {
  constructor() {
    const rt = () => {
      const t = new THREE.WebGLRenderTarget(4, 4, {
        minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter,
        format: THREE.RGBAFormat, type: THREE.UnsignedByteType,
        depthBuffer: false, stencilBuffer: false,
      });
      t.texture.generateMipmaps = false;
      return t;
    };
    this.glow = rt();
    this.a = rt();
    this.b = rt();
    this.blur = new THREE.RawShaderMaterial({
      uniforms: { tSrc: { value: null }, uDir: { value: new THREE.Vector2() } },
      vertexShader: POST_VERT, fragmentShader: BLUR_FRAG, depthTest: false, depthWrite: false,
    });
    this.add = new THREE.RawShaderMaterial({
      uniforms: {
        tCore: { value: this.glow.texture }, tHalo: { value: this.a.texture },
        uCore: { value: BLOOM.core }, uHalo: { value: BLOOM.halo },
      },
      vertexShader: POST_VERT, fragmentShader: ADD_FRAG, depthTest: false, depthWrite: false,
      blending: THREE.AdditiveBlending, transparent: true,
    });
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array([-1, -1, 0, 3, -1, 0, -1, 3, 0]), 3));
    geo.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([0, 0, 2, 0, 0, 2]), 2));
    this.quad = new THREE.Mesh(geo, this.blur);
    this.quad.frustumCulled = false;
    this.scene = new THREE.Scene();
    this.scene.add(this.quad);
    this.camera = new THREE.Camera();
    this.w = 0; this.h = 0;
    this._clear = new THREE.Color();
  }

  resize(w, h) {
    const gw = Math.max(1, w >> 1), gh = Math.max(1, h >> 1);
    const qw = Math.max(1, w >> 2), qh = Math.max(1, h >> 2);
    if (gw === this.w && gh === this.h) return;
    this.w = gw; this.h = gh;
    this.glow.setSize(gw, gh);
    this.a.setSize(qw, qh);
    this.b.setSize(qw, qh);
  }

  _pass(material, target) {
    this.quad.material = material;
    this.renderer.setRenderTarget(target);
    this.renderer.render(this.scene, this.camera);
  }

  _blur(src, dst, dx, dy) {
    this.blur.uniforms.tSrc.value = src.texture;
    this.blur.uniforms.uDir.value.set(dx / src.width, dy / src.height);
    this._pass(this.blur, dst);
  }

  /**
   * The bloom layer of `scene`, drawn against the depth in `target`,
   * blurred, and added back onto `target`. Called by js/lofi.js between
   * the world and the overlays.
   */
  render(renderer, scene, camera, target) {
    /* the clock the bars flash on: the wall clock, so they go on
       flashing with the game paused, which is what a light bar does */
    lampUniforms.uTime.value = (typeof performance !== 'undefined' ? performance.now() : Date.now()) / 1000;
    if (!target.depthTexture || !liveIn(scene)) return false;
    this.renderer = renderer;
    this.resize(target.width, target.height);
    lampSize.set(this.w, this.h);
    lampUniforms.tDepth.value = target.depthTexture;
    lampUniforms.uNearFar.value.set(camera.near, camera.far);

    /* the lamps alone, over black, with nothing in the scene's own
       background getting in */
    const mask = camera.layers.mask, bg = scene.background, fog = scene.fog;
    const alpha = renderer.getClearAlpha();
    renderer.getClearColor(this._clear);
    camera.layers.set(BLOOM_LAYER);
    scene.background = null; scene.fog = null;
    lampUniforms.uGlow.value = 1;
    renderer.setClearColor(0x000000, 1);
    renderer.setRenderTarget(this.glow);
    renderer.clear(true, true, true);
    renderer.render(scene, camera);
    lampUniforms.uGlow.value = 0;
    camera.layers.mask = mask;
    scene.background = bg; scene.fog = fog;
    renderer.setClearColor(this._clear, alpha);
    lampUniforms.tDepth.value = null;

    /* down to a quarter and spread, twice, the second time wider */
    this._blur(this.glow, this.a, 1, 0);
    this._blur(this.a, this.b, 0, 1);
    this._blur(this.b, this.a, 2.5, 0);
    this._blur(this.a, this.b, 0, 2.5);
    this._blur(this.b, this.a, 5, 0);
    this._blur(this.a, this.b, 0, 5);
    this.add.uniforms.tHalo.value = this.b.texture;

    /* and back onto the buffer, added, with the buffer's depth left alone */
    const ac = renderer.autoClear;
    renderer.autoClear = false;
    this._pass(this.add, target);
    renderer.autoClear = ac;
    return true;
  }
}
