/* =====================================================================
   MEWD — the screen on the back of the gun
   =====================================================================

   THE LANCE CAME WITH A SCREEN IN IT. The model the user brought in —
   Vaportrash's WZBR-1 Positron Sniper Lance — has four meshes, and two
   of them are not metal: a node named `dynamic_display_surface_1`, an
   eighty-millimetre panel on the rear deck facing straight back at
   whoever is holding it, and `optics_2`, a green lens up front. The
   author put the answer in the file the way the minigun's author put a
   marker cylinder in his. Everything below is what that node is for.

   WHAT IS ON IT: the world, live, through a second camera at the
   player's own eye with a narrow field of view — a camera-to-texture
   feed and not a painted picture — with round gauges over it for the
   charge, the hold and the cell, and a reticle in the middle. It is a
   sniper scope that happens to be a monitor, which is what a lance
   with a flat panel where the optics should be IS.

   ---------------------------------------------------------------------
   WHY THE FEED IS ITS OWN RENDER AND NOT A CORNER OF THE MAIN ONE

   A zoomed picture is a DIFFERENT picture, not a crop: eight times the
   magnification is eight times fewer degrees across the same texels, and
   there is no way to get that out of a frame drawn at sixty degrees
   except by drawing it again. So this owns a second perspective camera,
   parked at the world camera's position with the world camera's
   rotation and a field of view divided by the magnification, and one
   more render() of the same scene into a small square target.

   THE SAME SCENE, WHICH IS THE WHOLE TRICK. Nothing is duplicated and
   nothing is kept in sync: the crowd, the fire, the town and the sky
   are whatever the frame already made them, and the feed is a second
   look at the one scene graph from the one place the player is standing.
   Everything the game culls for the main camera — the portal flood, the
   distance cuts in Actor.render, the geometry LOD — was computed from
   that same standpoint, so a narrower camera at the same point can only
   ever want a SUBSET of what is already there. There is no case where
   the scope wants something the frame threw away.

   AND IT IS SMALL AND SLOW ON PURPOSE. SIZE texels square — the panel
   is very nearly square, so the target is — and at most every EVERY-th
   frame. A screen eighty millimetres across on a gun held at arm's
   length is forty chunky pixels once the lo-fi pass has had it; a feed
   that updates thirty times a second on it is indistinguishable from
   one that updates sixty, and it is a whole scene render either way.
   The rest of the time the panel samples the target it already has.

   ---------------------------------------------------------------------
   WHY THE GAUGES ARE A CANVAS AND NOT GEOMETRY

   Round. The user asked for round, and an arc swept to an angle is one
   call in a 2D context and a rebuilt vertex ring in three. The canvas
   is PANEL texels square, redrawn only when one of the numbers on it
   has actually moved — the same dirty key the readout uses, for the
   same reason (see js/hud.js) — and uploaded as an RGBA texture the
   screen shader lays over the feed.

   It is drawn in the lens's own green, because the model says the
   optics are green and a monitor that does not match its own glass is
   two parts from two guns.

   ---------------------------------------------------------------------
   AND WHY THE UVs ARE NOT THE FILE'S

   The panel's own UVs live in a twenty-six thousandth of the sheet —
   0.495 to 0.521 across, 0.704 to 0.722 up — because in the original
   it is one flat dark patch of a texture atlas and needs no more.
   Mapping a screen through them would sample one texel.

   So the screen makes its own, out of the mesh's LOCAL POSITION, which
   it can do because the panel is planar: every one of its thirteen
   vertices sits at z = -0.1694, so x and y across the panel's own
   bounding box ARE the two axes of the picture. setPanelBox is handed
   that box at load time, measured off the geometry the file actually
   shipped rather than the numbers written here, so a re-export that
   moves the panel moves the picture with it.

   THE U AXIS IS FLIPPED and that is not a fudge. js/weapon3d.js turns
   every model half a circle about y so its barrel points away from the
   eye, and a half turn about y sends model +x to view -x: the panel's
   right-hand edge is the left-hand edge of what you see. Un-flipped,
   the scope feed is a mirror — which is exactly what it looked like the
   first time, and exactly what a test pattern showed.
   ===================================================================== */

import * as THREE from 'three';

/* The feed, in texels. Square because the panel is: 80.3mm by 77.7mm. */
export const SIZE = 256;
/* and the gauge canvas over it, at the same size for the same reason */
export const PANEL = 256;
/* ONE FEED FRAME IN EVERY THIS MANY. See the note above: a second whole
   scene render is the most expensive thing on this screen and the
   cheapest thing to halve. */
export const EVERY = 2;

/* ---------------------------------------------------------------------
   THE ZOOM IS NOT A ZOOM, IT IS PUTTING YOUR EYE TO THE SCOPE

   At the user's request, and it is a better idea than the one it
   replaces. The first version narrowed the world's field of view and
   magnified the feed on the panel by twelve: what you got was a
   telescope that happened to be painted on a gun, and the gun itself
   stayed exactly where it was, down in the corner, while the picture
   around it changed. Two things were being zoomed and neither of them
   was the thing the player was looking at.

   What it does now is MOVE THE WEAPON. The lance comes up and back so
   the screen on its rear deck arrives in front of your eye and fills
   the middle of the frame — see `aim` in GUNS (js/weapon3d.js), which
   is a second hold the gun blends to. The world behind it barely
   narrows. The feed on the panel barely magnifies. The whole of the
   change is that you have raised the thing and put your face to it,
   which is what looking through a scope IS.

   SO THE MAGNIFICATIONS ARE SMALL NOW. Two and a bit, and three and a
   bit: enough that the panel is worth looking at rather than being a
   window onto what you can already see, and nowhere near the twelve
   that made it a separate game. The far end of the town is still
   further off than it was; you just have to walk. */
export const ZOOMS = [1, 2.1, 3.4];

/* AND THE WORLD BEHIND IT HARDLY MOVES. A tenth and a sixth, where it
   used to be a fifth and a third — just enough to say that the player
   has stopped walking and started aiming. The look sensitivity drops by
   the same factor, which at these numbers is a steadying rather than a
   slowing. */
export const VIEW_ZOOM = [1, 0.90, 0.84];

/* HOW FAR THE GUN IS TO THE SHOULDER at each step, 0 at the hip and 1
   with your eye on the glass. The second step is most of the way and
   the third is all of it, so the first press brings it up and the
   second settles it. What that means in metres is the `aim` hold in
   js/weapon3d.js; this is only how much of it. */
export const AIM_AT = [0, 0.82, 1];

/* The phosphor. The lens on the front of this model is (0.344, 0.800,
   0.000) in the file's own base colour, and the screen is that. */
export const PHOSPHOR = [0.42, 1.0, 0.36];
/* and what the gauges are drawn in, over it */
const INK = 'rgba(150, 255, 138, 0.92)';
const INK_DIM = 'rgba(150, 255, 138, 0.42)';
const WARN = 'rgba(255, 196, 72, 0.95)';
const HOT = 'rgba(255, 96, 56, 0.96)';
const FACE = '600 __px ui-monospace, "SF Mono", Menlo, Consolas, monospace';

const SCREEN_VERT = /* glsl */`
varying vec3 vL;
void main() {
  vL = position;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

/* The screen itself. Two samplers — the live feed and the gauges over it
   — and everything else is what makes a lit panel look like a lit panel
   rather than a photograph glued to a gun: a phosphor tint, scan lines,
   a soft edge, and a burst of static while the beam is out. */
const SCREEN_FRAG = /* glsl */`
uniform sampler2D feed;
uniform sampler2D panel;
uniform vec4  box;        // minX, minY, 1/width, 1/height, in the mesh's units
uniform float on;         // 0 dead, 1 lit
uniform float noise;      // 0..1, static
uniform float tics;
uniform vec3  tint;
varying vec3 vL;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.7, 289.3))) * 43758.5453); }

void main() {
  /* the panel's own box, and u flipped — see the header */
  vec2 uv = vec2(1.0 - (vL.x - box.x) * box.z, (vL.y - box.y) * box.w);
  vec2 c = uv - 0.5;

  /* THE GLASS IS SLIGHTLY CURVED, which is a screen's tell at this size:
     a barrel of a couple of per cent, so the picture bows and the scan
     lines bow with it. */
  vec2 fuv = uv + c * dot(c, c) * 0.16;

  vec3 col = vec3(0.0);
  if (fuv.x > 0.0 && fuv.x < 1.0 && fuv.y > 0.0 && fuv.y < 1.0) {
    vec3 f = texture2D(feed, fuv).rgb;
    /* PHOSPHOR: the feed's brightness in one colour, not the feed's
       colours dimmed. A tint multiplies, and a green multiply over a
       brown supermarket is mud — the same argument js/weapon3d.js's
       FLAME_FRAG makes about a cold flame. */
    float l = dot(f, vec3(0.30, 0.59, 0.11));
    /* banded, because everything in this game is */
    l = floor(pow(l, 0.85) * 14.0 + 0.5) / 14.0;
    col = tint * l;
  }

  /* STATIC, AND IT GOES ON THE PICTURE AND NOT ON THE GAUGES.

     A sensor pointed down the barrel of its own positron discharge
     cannot hold a picture, and for the second and a half that one is
     out this is the whole of what it looks like. But the gauges are not
     coming down a wire from anywhere — they are drawn by the gun, on
     the gun — so noise over them is noise on the one part of the screen
     that has no reason to have any, and at the moment it matters most
     it took the charge ring with it. So the static is applied HERE, to
     the feed, and the overlay goes on top of it afterwards and stays
     crisp. */
  float n = hash(floor(uv * 128.0) + floor(tics * 3.0));
  col += (n - 0.5) * noise * 0.8;
  col = mix(col, vec3(n) * tint, noise * 0.25 * step(0.86, hash(vec2(floor(uv.y * 48.0), floor(tics * 2.0)))));

  /* the gauges, straight over it, already the right colour */
  vec4 g = texture2D(panel, uv);
  col = mix(col, g.rgb, g.a);

  /* SCAN LINES on a grid of their own rather than the texture's, so
     they stay put when the target is resized */
  float scan = 0.82 + 0.18 * step(0.5, fract(uv.y * 72.0));
  col *= scan;

  /* a slow roll down the picture, the way a monitor filmed off a
     monitor has */
  col *= 1.0 + 0.045 * sin((uv.y + tics * 0.006) * 6.2831);

  /* THE BEZEL: a dark rim and a lit edge, so the panel reads as inset
     rather than as a decal.

     AND IT IS A NARROW RIM, which it was not. The first cut darkened
     the outer TENTH of the panel, and the charge ring — the biggest
     thing on this screen and the one the whole weapon is about — is
     drawn at 0.40 of the way out with a rim of its own on top of that.
     The ring was inside the part that had been faded to black, so the
     gauge the user asked for was not on the gauge. Six per cent, and
     the layout below keeps everything inside 0.86.

     BOTH SMOOTHSTEPS RUN LOW EDGE FIRST, which they did not either.
     GLSL says the result of smoothstep is UNDEFINED when edge0 >= edge1
     — not reversed, UNDEFINED — so writing it with the high edge first,
     as this did, is a thing every driver is free to answer differently,
     and this one runs on whatever the player has. Subtracted from one
     instead, which is the same curve and is defined everywhere.

     (And no back-quote appears anywhere in this comment, which is not a
     style note: every shader in this game is a template literal, so a
     back-quote in a comment INSIDE one ends the string. The first draft
     of the paragraph above quoted the broken call with a pair of them
     and took the whole game down with a JavaScript syntax error, three
     files away from anything that looked like a shader.) */
  float r = max(abs(c.x), abs(c.y)) * 2.0;
  col *= 1.0 - smoothstep(0.94, 1.02, r);
  col += tint * 0.30 * smoothstep(0.90, 0.97, r) * (1.0 - smoothstep(0.97, 1.02, r));

  /* and a little of it always on, so a dead screen is dark glass and
     not a hole in the gun */
  col = col * on + vec3(0.012, 0.020, 0.014);
  gl_FragColor = vec4(col, 1.0);
}
`;

/* The lens up front. The file paints it flat green; this makes it a lens
   — bright where it faces you, dark at the rim, and lit from inside
   while the weapon is charged. */
const OPTIC_FRAG = /* glsl */`
uniform vec3  base;
uniform float charge;
uniform float tics;
varying vec3 vN;
varying vec3 vP;
void main() {
  vec3 N = normalize(vN);
  vec3 V = normalize(-vP);
  float f = 1.0 - abs(dot(N, V));
  /* a ring of glare round the edge of the glass */
  float rim = pow(f, 2.2);
  vec3 c = base * (0.25 + 0.55 * (1.0 - f)) + vec3(0.55, 1.0, 0.62) * rim * 0.8;
  /* and the charge burning behind it, pulsing faster as it fills */
  float pulse = 0.5 + 0.5 * sin(tics * (0.10 + charge * 0.42));
  c += vec3(0.6, 1.0, 0.7) * charge * (0.35 + 0.65 * pulse);
  gl_FragColor = vec4(c, 1.0);
}
`;
const OPTIC_VERT = /* glsl */`
varying vec3 vN;
varying vec3 vP;
void main() {
  vN = normalize(normalMatrix * normal);
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  vP = mv.xyz;
  gl_Position = projectionMatrix * mv;
}
`;

/* ---------------------------------------------------------------------
   Drawing helpers for the gauges: everything here is an arc, because
   everything on this screen is round.
   ------------------------------------------------------------------- */

/** An arc gauge: a dark track, a lit sweep over it, and a cap of glare
 *  at the head of the sweep. Angles in turns from twelve o'clock,
 *  clockwise, which is how a dial is read and not how canvas measures. */
function dial(ctx, cx, cy, r, w, from, span, lit, colour, track = 'rgba(150, 255, 138, 0.14)') {
  const a0 = -Math.PI / 2 + from * Math.PI * 2;
  const a1 = a0 + span * Math.PI * 2;
  ctx.lineCap = 'butt';
  ctx.lineWidth = w;
  ctx.strokeStyle = track;
  ctx.beginPath(); ctx.arc(cx, cy, r, a0, a1); ctx.stroke();
  if (lit <= 0) return;
  const head = a0 + span * Math.PI * 2 * Math.min(1, lit);
  ctx.strokeStyle = colour;
  ctx.beginPath(); ctx.arc(cx, cy, r, a0, head); ctx.stroke();
  /* the glare at the head, which is what says it is filling now */
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  ctx.lineWidth = w * 1.9;
  ctx.strokeStyle = colour;
  ctx.globalAlpha = 0.28;
  ctx.beginPath(); ctx.arc(cx, cy, r, Math.max(a0, head - 0.16), head); ctx.stroke();
  ctx.restore();
}

/** A tick across a dial's track, for a stage mark. */
function tick(ctx, cx, cy, r, w, at, colour, len = 1.7) {
  const a = -Math.PI / 2 + at * Math.PI * 2;
  ctx.save();
  ctx.strokeStyle = colour;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(cx + Math.cos(a) * (r - w * len / 2), cy + Math.sin(a) * (r - w * len / 2));
  ctx.lineTo(cx + Math.cos(a) * (r + w * len / 2), cy + Math.sin(a) * (r + w * len / 2));
  ctx.stroke();
  ctx.restore();
}

function label(ctx, s, x, y, px, colour, align = 'center') {
  ctx.font = FACE.replace('__', String(Math.round(px)));
  ctx.fillStyle = colour;
  ctx.textAlign = align;
  ctx.textBaseline = 'middle';
  ctx.fillText(s, x, y);
}

export class Scope {
  /**
   * @param renderer  the one WebGLRenderer, or null headless — with no
   *                  renderer the feed is never drawn and the panel is
   *                  a flat black texture, which is exactly what the
   *                  sprite fallback wants anyway
   */
  constructor(renderer = null, { size = SIZE, panel = PANEL, every = EVERY,
                                 zooms = ZOOMS, viewZooms = VIEW_ZOOM, aimAt = AIM_AT, aspect = 1 } = {}) {
    this.renderer = renderer;
    this.size = size;
    this.every = every;
    /* THE STEPS ARE THE SCOPE'S OWN, and the lance's are the defaults. A
       second gun with a screen (js/thermal.js) brings its own three
       rows, and a screen that is not square its own aspect: the target,
       the gauge canvas and the camera are all that much wider than they
       are tall, so the picture is not stretched to fit the glass. */
    this.zooms = zooms;
    this.viewZooms = viewZooms;
    this.aimAt = aimAt;
    this.aspect = aspect;
    this.frames = 0;
    this.renders = 0;               // how many feed frames have actually been drawn
    this.zoomIndex = 0;
    this.lastAimed = 0;             // the step AIM goes back up to — see toggleAim
    this.held = false;              // is the lance in hand at all
    this.tics = 0;

    /* the feed: a square target and a camera to fill it */
    this.target = new THREE.WebGLRenderTarget(Math.round(size * aspect), size, {
      format: THREE.RGBAFormat, type: THREE.UnsignedByteType,
      depthBuffer: true, stencilBuffer: false,
    });
    if (this.target.texture) {
      this.target.texture.minFilter = THREE.LinearFilter;
      this.target.texture.magFilter = THREE.NearestFilter;
      this.target.texture.generateMipmaps = false;
    }
    this.camera = new THREE.PerspectiveCamera(60, 1, 1, 12000);

    /* the gauges: a canvas, redrawn only when a number on it moves */
    this.canvas = typeof document !== 'undefined' ? document.createElement('canvas') : null;
    if (this.canvas) { this.canvas.width = Math.round(panel * aspect); this.canvas.height = panel; }
    this.ctx = this.canvas ? this.canvas.getContext('2d') : null;
    this.panelTexture = this.canvas ? new THREE.CanvasTexture(this.canvas) : null;
    if (this.panelTexture) {
      this.panelTexture.minFilter = THREE.LinearFilter;
      this.panelTexture.magFilter = THREE.LinearFilter;
      this.panelTexture.generateMipmaps = false;
    }
    this._key = '';
    this.draws = 0;                 // how many times the gauges have been redrawn

    this.screen = null;
    this.optic = null;
  }

  /* the rows, falling back to the lance's for a Scope that was made
     without its constructor — which the suite does, to draw the gauges
     into a context that measures them */
  get _zooms() { return this.zooms || ZOOMS; }
  get magnification() { return this._zooms[this.zoomIndex] || 1; }
  /** How far the weapon is raised toward the eye at this step — what
   *  js/weapon3d.js blends its second hold by. See AIM_AT. */
  get aim() { return (this.aimAt || AIM_AT)[this.zoomIndex] ?? 0; }
  /** What the WORLD camera's field of view should be multiplied by while
   *  the scope is at this step — see VIEW_ZOOM. */
  get viewScale() { return (this.viewZooms || VIEW_ZOOM)[this.zoomIndex] ?? 1; }
  get zoomed() { return this.zoomIndex > 0; }

  setZoom(i) {
    this.zoomIndex = Math.max(0, Math.min(this._zooms.length - 1, i | 0));
    if (this.zoomIndex) this.lastAimed = this.zoomIndex;
  }
  /** Z, C, the right button, the pad's B: hip, up, further, hip. */
  cycleZoom() { this.setZoom((this.zoomIndex + 1) % this._zooms.length); }

  /** THE PHONE'S AIM BUTTON, at the user's request: the gun up to the
   *  eye, or back down to the hip, and nothing in between. Up is the
   *  step it was last at while up — the first aimed step the first time
   *  — so lowering it to walk and raising it again does not lose the
   *  magnification the player had chosen. */
  toggleAim() { this.setZoom(this.zoomIndex ? 0 : this.lastAimed || 1); }

  /** AND ITS MAGNIFICATION BUTTON, which is only on the glass while the
   *  gun is up: the next aimed step, round to the first again, and never
   *  down to the hip — taking the gun down is what AIM is for, and a
   *  magnification button that sometimes lowers the gun is two buttons
   *  that do the same thing. */
  stepAimed() {
    const n = this._zooms.length;
    if (n < 2) return;
    this.setZoom(this.zoomIndex ? 1 + this.zoomIndex % (n - 1) : this.lastAimed || 1);
  }

  /** One press, as js/input.js's takeScope names it. */
  work(press) {
    if (press === 'aim') this.toggleAim();
    else if (press === 'step') this.stepAimed();
    else if (press === 'cycle') this.cycleZoom();
  }

  /* ------------------------------------------------------------------
     The two materials the model's own two untextured meshes wear
     ------------------------------------------------------------------ */

  /** The screen. One per game: there is one lance and one panel on it. */
  screenMaterial() {
    if (this.screen) return this.screen;
    this.screen = new THREE.ShaderMaterial({
      uniforms: {
        feed: { value: this.target.texture },
        panel: { value: this.panelTexture },
        box: { value: new THREE.Vector4(0, 0, 1, 1) },
        on: { value: 1 }, noise: { value: 0 }, tics: { value: 0 },
        tint: { value: new THREE.Vector3(...PHOSPHOR) },
      },
      vertexShader: SCREEN_VERT, fragmentShader: SCREEN_FRAG,
      side: THREE.DoubleSide, toneMapped: false, fog: false,
    });
    this.screen.name = 'scope-screen';
    return this.screen;
  }

  /** The lens. */
  opticsMaterial(base = [0.34, 0.80, 0.0]) {
    if (this.optic) return this.optic;
    this.optic = new THREE.ShaderMaterial({
      uniforms: {
        base: { value: new THREE.Vector3(...base) },
        charge: { value: 0 }, tics: { value: 0 },
      },
      vertexShader: OPTIC_VERT, fragmentShader: OPTIC_FRAG,
      side: THREE.DoubleSide, toneMapped: false, fog: false,
    });
    this.optic.name = 'scope-optic';
    return this.optic;
  }

  /** The panel's own bounding box in the mesh's own units, measured off
   *  the geometry at load time — see the header. `min` and `size` are
   *  [x, y]. */
  setPanelBox(min, size) {
    const u = this.screenMaterial().uniforms.box.value;
    u.set(min[0], min[1], 1 / Math.max(size[0], 1e-6), 1 / Math.max(size[1], 1e-6));
  }

  /* ------------------------------------------------------------------
     One feed frame
     ------------------------------------------------------------------ */

  /**
   * Draw the world into the panel's target through the narrow camera.
   * Call it BEFORE the lo-fi pipeline's own render — that one takes the
   * render target away and gives it back to the screen.
   *
   * @param scene        the world, exactly as the frame left it
   * @param worldCamera  where the eye is and which way it faces
   * @returns whether anything was drawn
   */
  render(scene, worldCamera) {
    this.frames++;
    if (!this.renderer || !this.held) return false;
    if (this.frames % this.every) return false;
    const c = this.camera;
    c.position.copy(worldCamera.position);
    c.quaternion.copy(worldCamera.quaternion);
    c.near = worldCamera.near;
    c.far = worldCamera.far;
    c.aspect = this.aspect || 1;
    /* THE MAGNIFICATION IS OFF THE WORLD'S OWN FIELD OF VIEW, not off a
       number of its own, so the scope stays a multiple of what you can
       see however the main view is set — and the world camera is already
       narrowed by viewScale while zoomed, so this divides what is left
       and the two do not multiply twice. */
    c.fov = Math.max(1.2, worldCamera.fov / this.magnification * this.viewScale);
    c.updateProjectionMatrix();
    const r = this.renderer;
    const prev = r.getRenderTarget();
    r.setRenderTarget(this.target);
    r.clear(true, true, true);
    r.render(scene, c);
    r.setRenderTarget(prev);
    this.renders++;
    return true;
  }

  /* ------------------------------------------------------------------
     The gauges
     ------------------------------------------------------------------ */

  /**
   * Redraw the gauge canvas if anything on it has moved, and push the
   * two live numbers into the screen and the lens.
   *
   * @param p  the player, or null
   */
  update(p, tics = 0) {
    this.tics = tics;
    const s = this.screen, o = this.optic;
    const charge = p ? (p.chargeFraction || 0) : 0;
    if (s) {
      s.uniforms.tics.value = tics;
      s.uniforms.on.value = this.held ? 1 : 0;
      /* A HARD BURST OF STATIC WHILE THE BEAM IS OUT, and nothing the
         rest of the time. It used to ride on the coil's temperature as
         well, and a resting screen was always faintly snowy for it;
         with the heat gone the picture is CLEAN until the moment the
         sensor is looking down its own discharge, which is both what a
         sensor would do and the one thing a sniper's screen has any
         business doing — a scope you cannot read between shots is not a
         scope. */
      s.uniforms.noise.value = p && p.beamTics > 0 ? 0.52 : 0;
    }
    if (o) { o.uniforms.tics.value = tics; o.uniforms.charge.value = Math.max(charge, p && p.beamTics > 0 ? 1 : 0); }
    if (!this.ctx) return false;

    const stage = p ? (p.chargeStage || 0) : 0;
    const cell = p ? Math.max(0, Math.min(1, (p.ammo?.cells ?? 0) / (p.maxAmmo?.cells || 1))) : 0;
    const firing = !!(p && p.beamTics > 0);
    /* AND HOW MUCH OF THE WINDOW AT THE TOP IS LEFT, 1 the moment the
       dial goes red and 0 as the coil vents — see HOLD_TICS in
       js/player.js. It is the inner ring, and it is the number this
       screen exists to tell you now that the coil cannot go off in your
       hands: how long you have to take the shot you are lining up. */
    const hold = p ? (p.holdFraction || 0) : 0;
    /* THE DIRTY KEY, and everything in it is something that is DRAWN.
       A range readout was on here for a while and went, because four
       characters of it were illegible at forty pixels — and while it
       was in this key the canvas was redrawn every time the player
       turned, which is every frame. What a screen redraws on has to be
       what a screen shows. */
    const key = [this.held ? 1 : 0, Math.round(charge * 120), Math.round(hold * 90), stage,
                 Math.round(cell * 60), this.zoomIndex, firing ? 1 : 0,
                 firing ? (tics >> 1) & 7 : 0,
                 hold > 0 && hold < 0.25 ? (tics >> 2) & 1 : 0].join('|');
    if (key === this._key) return false;
    this._key = key;
    this.draws++;
    this._draw({ charge, hold, stage, cell, firing, tics });
    if (this.panelTexture) this.panelTexture.needsUpdate = true;
    return true;
  }

  /* ------------------------------------------------------------------
     WHAT THE SCREEN LOOKS LIKE, and it is laid out for the size it is
     ACTUALLY SEEN AT

     The panel is eighty millimetres on a gun held at arm's length: on a
     thousand-pixel window it is about a hundred pixels across, and then
     the lo-fi pass resolves that down to forty chunky ones. Forty. The
     first cut of this screen had two arc gauges with their own labels,
     a third round dial, a range readout and a four-rung ladder on the
     reticle, and at forty pixels all of it was one green smear.

     So it is FOUR THINGS, each of which survives being forty pixels
     across:

       the outer ring    the charge, three quarters of a turn, thick
                         enough to read as a bar, with the three stage
                         marks cut through it
       the inner ring    the window at the top of the charge, draining,
                         concentric inside it and going the same way, so
                         the two are one instrument and not two
       four pips         the cell, because it holds four and four dots
                         are legible at a size an arc is not
       the reticle       a cross with a gap

     and one character, the stage, big under the top of the ring.
     Nothing else. The zoom sits under the reticle in small type because
     it is the one thing the player changes by hand and so is the one
     thing they can be expected to go looking for.

     EVERYTHING IS INSIDE THE BEZEL, which is a SQUARE one — the glass
     goes dark at max(|x|, |y|) * 2 > 0.94 off the middle, so what
     matters is the greater of the two axes and not the distance. The
     dial reaches 0.907 of that at its widest, which is the warning bar
     at the bottom. That was the bug the first cut had: the charge ring,
     the biggest thing on this screen and the one the whole weapon is
     about, was drawn at 0.44 with a rim of its own on top, which is to
     say inside the part that had already been faded out. The gauge was
     not on the gauge. The suite draws this method into a context that
     records where the ink went and measures it, rather than trusting
     the number in this paragraph.
     ------------------------------------------------------------------ */
  _draw({ charge, hold, stage, cell, firing, tics }) {
    const ctx = this.ctx, N = this.canvas.width;
    ctx.clearRect(0, 0, N, N);
    if (!this.held) return;
    const cx = N / 2, cy = N / 2;
    const stageInk = stage >= 3 ? HOT : stage >= 2 ? WARN : INK;

    /* ---- THE CHARGE, the outer ring ---------------------------------
       From eight o'clock round to four, which leaves the bottom clear
       for the pips and makes the ring read as a gauge with a beginning
       and an end rather than as a circle. */
    const R = N * 0.372, W = N * 0.086;
    const FROM = -0.375, SPAN = 0.75;
    dial(ctx, cx, cy, R, W, FROM, SPAN, charge, stage > 0 ? stageInk : INK);
    /* the stage marks, cut THROUGH the ring in the background colour so
       they are gaps and not lines: a line drawn over a lit arc at this
       size is a lit arc */
    for (const at of (this.stageMarks || [0.43, 0.71, 1])) {
      if (at >= 1) continue;
      tick(ctx, cx, cy, R, W, FROM + SPAN * at, 'rgba(6, 18, 8, 0.95)', 1.25);
    }

    /* ---- THE WINDOW, concentric inside it ----------------------------
       Nothing at all until the outer ring is full, and then five
       seconds of it DRAINING while you line the shot up — see
       HOLD_TICS. The two rings together are therefore one sentence read
       from the outside in: the charge fills, and then the window
       empties, and if you let the second one run out the first one goes
       with it.

       It was the coil's temperature for a while. The heat is gone at
       the user's request and this is the number that deserved the ring
       anyway: a temperature you could do nothing about was a gauge you
       watched, and this is one you act on. */
    const r2 = N * 0.268, w2 = N * 0.054;
    if (hold > 0)
      dial(ctx, cx, cy, r2, w2, FROM, SPAN, hold,
           hold < 0.25 ? HOT : hold < 0.5 ? WARN : INK, 'rgba(150, 255, 138, 0.10)');

    /* ---- THE CELL, four pips along the bottom ------------------------ */
    const have = Math.round(cell * 4);
    for (let i = 0; i < 4; i++) {
      const x = cx + (i - 1.5) * N * 0.072, y = N * 0.845;
      ctx.beginPath();
      ctx.arc(x, y, N * 0.021, 0, Math.PI * 2);
      ctx.fillStyle = i < have ? INK : 'rgba(150, 255, 138, 0.13)';
      ctx.fill();
      if (i < have) { ctx.strokeStyle = INK_DIM; ctx.lineWidth = 1.5; ctx.stroke(); }
    }

    /* ---- THE RETICLE ------------------------------------------------- */
    ctx.strokeStyle = firing ? HOT : INK;
    ctx.lineWidth = 2.4;
    const g0 = N * 0.045, g1 = N * 0.125;
    ctx.beginPath();
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      ctx.moveTo(cx + dx * g0, cy + dy * g0);
      ctx.lineTo(cx + dx * g1, cy + dy * g1);
    }
    ctx.stroke();
    ctx.fillStyle = firing ? HOT : INK;
    ctx.fillRect(cx - 1.5, cy - 1.5, 3, 3);

    /* a box round the middle while the beam is out, blinking, which is
       the one thing on here that MOVES and so the one thing that is
       read without being looked at */
    if (firing && ((tics >> 2) & 1)) {
      ctx.strokeStyle = HOT;
      ctx.lineWidth = 3;
      ctx.strokeRect(cx - N * 0.15, cy - N * 0.15, N * 0.30, N * 0.30);
    }

    /* ---- AND THE ONE CHARACTER --------------------------------------- */
    label(ctx, firing ? '\u25b2' : stage > 0 ? String(stage) : '\u00b7',
          cx, N * 0.245, N * 0.125, firing ? HOT : stage > 0 ? stageInk : INK_DIM);
    label(ctx, `${this.magnification}\u00d7`, cx, N * 0.675, N * 0.078,
          this.zoomIndex ? INK : INK_DIM);

    /* ---- AND THE LAST SECOND OF THE WINDOW ---------------------------
       The inner ring has been draining for four seconds by now and a
       ring that is nearly empty is a ring that is nearly not there. So
       the last quarter of it blinks the middle of the reticle red as
       well, which is the one part of this screen the eye is already on
       while you are aiming. No words: there is nothing to decide any
       more and nothing you can do about it but shoot. */
    if (hold > 0 && hold < 0.25 && ((tics >> 2) & 1)) {
      ctx.fillStyle = HOT;
      ctx.fillRect(cx - N * 0.022, cy - N * 0.022, N * 0.044, N * 0.044);
    }
  }

  /** Where the three stage marks fall on the charge ring, as fractions of
   *  a full charge. Set once by whoever owns the numbers — js/player.js —
   *  so the dial and the weapon cannot disagree. */
  setStages(marks) { this.stageMarks = marks; }

  dispose() {
    this.target?.dispose?.();
    this.screen?.dispose?.();
    this.optic?.dispose?.();
    this.panelTexture?.dispose?.();
  }
}
