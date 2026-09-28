/* =====================================================================
   MEWD — the thermal sight on the side of the box
   =====================================================================

   THE SAME METHOD AS THE LANCE'S SCREEN, at the user's request: "use
   same method as sniper rifle display to put a thermal scope live view
   on a plane in the scope". So this is js/scope.js — it IS a Scope, by
   inheritance, and everything that file says about why the feed is a
   second render of the one scene through a narrower camera, why it is
   small and every other frame, and why the gauges are a canvas, is true
   here without being said twice. What is different is three things.

   THE PLANE. The launcher's file — the XM222 — has a display surface
   on the back of its sight under a material of its own, prepared by
   the user for this feed, exactly as the lance's has; so it is named
   by `display` in GUNS (js/weapon3d.js), wears this scope's screen
   material, and is measured and mapped exactly as the lance's panel
   is, u flip and all.

   THE PICTURE IS HEAT, NOT LIGHT. For the one render call this makes a
   frame, the shared uniform world.thermal is on (js/material.js), and
   every wall, floor, tree, car, puff and person in the scene answers
   how WARM it is instead of what colour it is: the night in a narrow
   cold band, people warm whatever they are wearing, engines warm when
   they are running, fire and lamps white, the sky black, a frozen
   shopper colder than the pavement, smoke all but invisible. What is
   warm is decided by js/missiles.js's heatSources — the same question
   the seeker asks — so the screen can only ever glow on what the
   launcher can lock, and never on what it cannot.

   The screen then does to that one number what a thermal camera does:
   runs it up IRONBOW — black through indigo, magenta, red, orange,
   yellow to white — in bands, because everything in this game is
   banded, and with the scan lines and the curved glass the lance's
   screen has, so the two read as instruments from the same armoury.

   THE GLASS SAYS WHAT THE SEEKER IS DOING. Four things, for the reason
   the lance's screen has four — this panel is a few centimetres across
   and the lo-fi pass takes it down to a few dozen chunky pixels:

     the seeker circle   how far off the middle a heat source may be to
                         be acquired, drawn at its true size for this
                         magnification, so zooming in makes the circle
                         bigger and the seeker easier to put on a thing
     the brackets        amber, one on every locked target, a pip in
                         each corner for every lock on it past the
                         first; and a white one closing in, blinking,
                         on whatever is being acquired
     four tube pips      along the bottom: loaded, empty, or loaded and
                         spoken for by a lock
     one character       the number of locks, big, at the top

   and the zoom, small, because it is the one thing the player sets by
   hand and so the one thing they will go looking for.
   ===================================================================== */

import * as THREE from 'three';
import { Scope } from './scope.js';
import { world } from './material.js';
import { SEEKER } from './missiles.js';

/* THE GLASS IS VERY NEARLY SQUARE. The display surface on the back of
   the XM222's sight is 0.728 across and 0.741 up of the model's own
   units, so the feed, the canvas and the camera are all that shape. It
   is a number here and the panel is measured off the model, and the
   suite checks the two agree. */
export const THERMAL_ASPECT = 0.98;
/* rows of feed; the columns are that times the aspect */
export const THERMAL_SIZE = 176;
export const THERMAL_PANEL = 256;
/* THE STEPS. More magnification than the lance, because what this is
   for is putting a circle six degrees across over a van at the far end
   of the street, and at the third step the circle is most of the glass. */
export const THERMAL_ZOOMS = [1, 2.5, 4];
export const THERMAL_VIEW_ZOOM = [1, 0.90, 0.82];
export const THERMAL_AIM_AT = [0, 0.84, 1];

/* WHAT A WARM THING IS WORTH, by kind, to the INK path of the world
   shader — see `warmth` there. A vehicle's own fire is added on top by
   the fire, which is fullbright; this is the engine and the tyres. */
const ENGINE = { driving: 0.78, charring: 0.58 };
const AIRCRAFT = 0.92;

const SCREEN_VERT = /* glsl */`
varying vec3 vL;
void main() {
  vL = position;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

/* The screen: heat in, IRONBOW out, the gauges over it. Everything
   after the palette is the lance's screen, on the same terms and for
   the same reasons — see SCREEN_FRAG in js/scope.js — and nothing in
   here has a back-quote in it, for the reason that file gives. */
const SCREEN_FRAG = /* glsl */`
uniform sampler2D feed;
uniform sampler2D panel;
uniform vec4  box;
uniform float on;
uniform float noise;
uniform float tics;
varying vec3 vL;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.7, 289.3))) * 43758.5453); }

/* seven stops, black to white by way of every colour a hot thing is */
vec3 ironbow(float h) {
  h = clamp(h, 0.0, 1.0);
  vec3 c0 = vec3(0.00, 0.00, 0.03), c1 = vec3(0.14, 0.01, 0.34), c2 = vec3(0.52, 0.03, 0.48);
  vec3 c3 = vec3(0.86, 0.18, 0.14), c4 = vec3(1.00, 0.55, 0.03), c5 = vec3(1.00, 0.88, 0.24);
  vec3 c6 = vec3(1.00, 1.00, 0.94);
  if (h < 0.18) return mix(c0, c1, h / 0.18);
  if (h < 0.36) return mix(c1, c2, (h - 0.18) / 0.18);
  if (h < 0.55) return mix(c2, c3, (h - 0.36) / 0.19);
  if (h < 0.72) return mix(c3, c4, (h - 0.55) / 0.17);
  if (h < 0.87) return mix(c4, c5, (h - 0.72) / 0.15);
  return mix(c5, c6, (h - 0.87) / 0.13);
}

void main() {
  vec2 uv = vec2(1.0 - (vL.x - box.x) * box.z, (vL.y - box.y) * box.w);
  vec2 c = uv - 0.5;
  vec2 fuv = uv + c * dot(c, c) * 0.16;

  vec3 col = vec3(0.0);
  if (fuv.x > 0.0 && fuv.x < 1.0 && fuv.y > 0.0 && fuv.y < 1.0) {
    vec3 f = texture2D(feed, fuv).rgb;
    /* THE HEAT IS THE BRIGHTEST CHANNEL, not the luminance: the world
       writes it into all three alike, and the few things drawn in their
       own colours — a tracer, a lamp flare, the lance's beam — are
       sources, and a source is as hot as its brightest channel */
    float h = max(f.r, max(f.g, f.b));
    h = floor(h * 20.0 + 0.5) / 20.0;
    col = ironbow(h);
  }

  /* THE MOTOR BLINDS IT: a missile leaving the tube beside the sight is
     the hottest thing the sensor will ever see, and for the tics of the
     launch the picture goes white-hot and snowy, under the gauges */
  float n = hash(floor(uv * 128.0) + floor(tics * 3.0));
  col = mix(col, vec3(1.0, 0.96, 0.86), noise * 0.55);
  col += (n - 0.5) * noise * 0.6;

  vec4 g = texture2D(panel, uv);
  col = mix(col, g.rgb, g.a);

  float scan = 0.84 + 0.16 * step(0.5, fract(uv.y * 64.0));
  col *= scan;
  col *= 1.0 + 0.04 * sin((uv.y + tics * 0.006) * 6.2831);

  float r = max(abs(c.x), abs(c.y)) * 2.0;
  col *= 1.0 - smoothstep(0.94, 1.02, r);
  col += vec3(0.30, 0.10, 0.36) * 0.35 * smoothstep(0.90, 0.97, r) * (1.0 - smoothstep(0.97, 1.02, r));

  col = col * on + vec3(0.014, 0.010, 0.020);
  gl_FragColor = vec4(col, 1.0);
}
`;

/* the symbology: a cold green-white that no stop of ironbow is, the
   seeker's amber for what is locked, and white for what is being taken */
const INK = 'rgba(176, 255, 214, 0.94)';
const INK_DIM = 'rgba(176, 255, 214, 0.40)';
const LOCK = 'rgba(255, 206, 72, 0.98)';
const TAKE = 'rgba(255, 255, 255, 0.96)';
const FACE = '700 __px ui-monospace, "SF Mono", Menlo, Consolas, monospace';

export class ThermalScope extends Scope {
  constructor(renderer = null, opts = {}) {
    super(renderer, {
      size: THERMAL_SIZE, panel: THERMAL_PANEL, aspect: THERMAL_ASPECT,
      zooms: THERMAL_ZOOMS, viewZooms: THERMAL_VIEW_ZOOM, aimAt: THERMAL_AIM_AT, ...opts,
    });
    /* the game, for its heat sources and its seeker — handed over by
       js/main.js once there is one; with none the feed is still thermal
       and the glass is only the circle and the pips */
    this.game = null;
    this._v = new THREE.Vector3();
    this._hidden = [];
  }

  /** The screen, in heat. One per game, for the one launcher. */
  screenMaterial() {
    if (this.screen) return this.screen;
    this.screen = new THREE.ShaderMaterial({
      uniforms: {
        feed: { value: this.target.texture },
        panel: { value: this.panelTexture },
        box: { value: new THREE.Vector4(0, 0, 1, 1) },
        on: { value: 1 }, noise: { value: 0 }, tics: { value: 0 },
      },
      vertexShader: SCREEN_VERT, fragmentShader: SCREEN_FRAG,
      side: THREE.DoubleSide, toneMapped: false, fog: false,
    });
    this.screen.name = 'thermal-screen';
    return this.screen;
  }

  /* ------------------------------------------------------------------
     One feed frame, in heat
     ------------------------------------------------------------------ */
  render(scene, worldCamera) {
    /* the frames Scope.render will actually draw, and only those, pay
       for setting the scene up for it */
    const due = !!this.renderer && this.held && ((this.frames + 1) % this.every) === 0;
    if (!due) return super.render(scene, worldCamera);
    this._heat(true);
    world.thermal.value = 1;
    try {
      return super.render(scene, worldCamera);
    } finally {
      world.thermal.value = 0;
      this._heat(false);
    }
  }

  /** Engines on for the one render, and the world's own lock brackets
   *  off for it: the glass draws its own, and a bracket in the feed is
   *  a fullbright sprite, which to a thermal sensor is a hot square. */
  _heat(on) {
    const g = this.game;
    if (!g) return;
    const M = g.missiles;
    if (on) {
      for (const v of g.vehicles?.all || []) {
        const u = v.mesh?.material?.uniforms?.warmth;
        if (u) u.value = M && M.isHot(v) ? (ENGINE[v.state] ?? ENGINE.charring) : 0;
      }
      for (const s of g.gunships?.ships || []) {
        const hot = M ? M.isHot(s) : !!s.whole;
        s.root?.traverse(o => { const u = o.material?.uniforms?.warmth; if (u) u.value = hot ? AIRCRAFT : 0; });
      }
      this._hidden.length = 0;
      for (const r of M?.reticles || []) if (r.visible) { r.visible = false; this._hidden.push(r); }
    } else {
      for (const r of this._hidden) r.visible = true;
      this._hidden.length = 0;
    }
  }

  /* ------------------------------------------------------------------
     The glass
     ------------------------------------------------------------------ */
  update(p, tics = 0) {
    this.tics = tics;
    const s = this.screen;
    if (s) {
      s.uniforms.tics.value = tics;
      s.uniforms.on.value = this.held ? 1 : 0;
      s.uniforms.noise.value = p && p.weapon === 'LAUNCHER' && p.firing ? 0.8 : 0;
    }
    if (!this.ctx) return false;
    const M = this.game?.missiles || null;
    const marks = this._marks(M);
    const loaded = p ? Math.max(0, Math.min(4, p.ammo?.rockets | 0)) : 0;
    const locks = M ? M.locks.length : 0;
    const take = M && M.acquiring ? M.acquireFraction : 0;
    const key = [this.held ? 1 : 0, this.zoomIndex, loaded, locks, Math.round(take * 12),
                 take > 0 ? (tics >> 1) & 1 : 0, M ? M.salvoLeft : 0,
                 marks.map(m => `${m.x >> 1},${m.y >> 1},${m.n},${m.r >> 1}`).join(';')].join('|');
    if (key === this._key) return false;
    this._key = key;
    this.draws++;
    this._drawThermal({ marks, loaded, locks, take, tics, salvo: M ? M.salvoLeft : 0 });
    if (this.panelTexture) this.panelTexture.needsUpdate = true;
    return true;
  }

  /** Where each locked target, and the one being acquired, is on the
   *  glass — through the camera the feed was last drawn with, so a
   *  bracket sits on the picture it was drawn over. */
  _marks(M) {
    const out = [];
    if (!M || !this.held) return out;
    const W = this.canvas.width, H = this.canvas.height;
    const put = (t, n) => {
      const hp = M.heatPoint(t);
      const v = this._v.set(hp.x, hp.z, -hp.y).project(this.camera);
      if (v.z > 1 || v.z < -1 || Math.abs(v.x) > 1.2 || Math.abs(v.y) > 1.2) return;
      /* and how big the thing is on the glass, off its own size */
      const size = t.radius ? t.radius * 1.6 : 90;
      const d = Math.max(1, Math.hypot(hp.x - this.camera.position.x, hp.z - this.camera.position.y, -hp.y - this.camera.position.z));
      const r = Math.max(9, Math.min(H * 0.3, size / d / Math.tan(this.camera.fov * Math.PI / 360) * H / 2));
      out.push({ x: Math.round((v.x + 1) / 2 * W), y: Math.round((1 - v.y) / 2 * H), n, r: Math.round(r), t });
    };
    const seen = new Map();
    for (const l of M.locks) seen.set(l.t, (seen.get(l.t) || 0) + 1);
    for (const [t, n] of seen) put(t, n);
    if (M.acquiring && !seen.has(M.acquiring)) put(M.acquiring, 0);
    return out;
  }

  _drawThermal({ marks, loaded, locks, take, tics, salvo }) {
    const ctx = this.ctx, W = this.canvas.width, H = this.canvas.height;
    ctx.clearRect(0, 0, W, H);
    if (!this.held) return;
    const cx = W / 2, cy = H / 2;

    /* ---- THE SEEKER CIRCLE, at the size the cone really is -------- */
    const fovY = this.camera.fov * Math.PI / 180;
    const rc = Math.tan(SEEKER.cone) / Math.tan(fovY / 2) * (H / 2);
    ctx.lineWidth = 2.2;
    ctx.strokeStyle = locks >= Math.min(4, loaded) && loaded > 0 ? LOCK : INK;
    ctx.beginPath();
    for (let k = 0; k < 16; k++) {
      /* broken into dashes, so it reads as a sight and not a lens */
      const a0 = (k / 16) * Math.PI * 2, a1 = a0 + Math.PI * 2 / 16 * 0.6;
      ctx.moveTo(cx + Math.cos(a0) * rc, cy + Math.sin(a0) * rc);
      ctx.arc(cx, cy, rc, a0, a1);
    }
    ctx.stroke();
    /* and a small cross in the middle of it */
    ctx.beginPath();
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      ctx.moveTo(cx + dx * H * 0.02, cy + dy * H * 0.02);
      ctx.lineTo(cx + dx * H * 0.06, cy + dy * H * 0.06);
    }
    ctx.stroke();

    /* ---- THE BRACKETS ------------------------------------------------ */
    for (const m of marks) {
      const r = m.n ? m.r : m.r * (2.2 - 1.2 * take);
      if (!m.n && ((tics >> 1) & 1)) continue;
      ctx.strokeStyle = m.n ? LOCK : TAKE;
      ctx.lineWidth = m.n ? 3 : 2;
      const arm = r * 0.55;
      ctx.beginPath();
      for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
        const x = m.x + sx * r, y = m.y + sy * r;
        ctx.moveTo(x - sx * arm, y); ctx.lineTo(x, y); ctx.lineTo(x, y - sy * arm);
      }
      ctx.stroke();
      /* a pip in a corner for every lock past the first, so four locks
         on one gunship is a bracket with three pips in it */
      ctx.fillStyle = LOCK;
      for (let k = 1; k < m.n; k++) ctx.fillRect(m.x - r + 3 + (k - 1) * 7, m.y - r + 3, 5, 5);
    }

    /* ---- THE FOUR TUBES ---------------------------------------------
       loaded and spoken for, loaded, or empty — in the order they fire */
    for (let i = 0; i < 4; i++) {
      const x = cx + (i - 1.5) * H * 0.11, y = H * 0.88, s = H * 0.035;
      const has = i >= 4 - loaded;
      const claimed = has && (i - (4 - loaded)) < locks;
      ctx.lineWidth = 2;
      ctx.strokeStyle = claimed ? LOCK : has ? INK : INK_DIM;
      ctx.fillStyle = claimed ? LOCK : INK;
      if (has) ctx.fillRect(x - s, y - s, s * 2, s * 2);
      else ctx.strokeRect(x - s, y - s, s * 2, s * 2);
    }

    /* ---- AND THE ONE CHARACTER, and the zoom ------------------------- */
    const big = salvo > 0 ? '▲' : locks > 0 ? String(locks) : '·';
    this._label(big, cx, H * 0.13, H * 0.13, salvo > 0 || locks ? LOCK : INK_DIM);
    this._label(`${this.magnification}×`, W * 0.86, H * 0.88, H * 0.075, this.zoomIndex ? INK : INK_DIM);
  }

  _label(s, x, y, px, colour) {
    const ctx = this.ctx;
    ctx.font = FACE.replace('__', String(Math.round(px)));
    ctx.fillStyle = colour;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(s, x, y);
  }
}
