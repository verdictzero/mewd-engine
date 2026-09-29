/* =====================================================================
   MEWD — the title's own level: a forest that goes by for ever

   At the user's request the title no longer stands on the map the game
   is about to play. It has a world of its own behind it: a forest seen
   from the side, sliding past from right to left and never running
   out, with grass close enough to the eye to fill the bottom of the
   glass.

   IT IS FOURTEEN ROWS OF CUTOUTS AT FOURTEEN DEPTHS — seven of grass
   and seven of pines behind them (see ROWS) — and the depth is all of
   the parallax: the eye is a real perspective camera moving along x,
   so a row twice as far away goes by half as fast without anything
   being told to.

   FOR EVER is a ring per row. A row is WRAP units wide, centred on the
   eye; a cutout that falls off the left end moves WRAP to the right,
   and on the way it becomes a different plant at a different size, so
   the forest does not come round again the same.

   The pictures are assets/forest (the same wood the game burns) and the
   sky is BSKY1 from assets/skies, the top half of it, drifting slower
   than anything. It is all MeshBasicMaterial with an alpha cut, drawn
   through the same pipeline as the game, so it comes out in the game's
   earth tones and pixels.
   ===================================================================== */

import * as THREE from 'three';

const DIR = 'assets/forest/';
const SPEED = 0.8;                     // units a second, the eye going right: a quarter of what it was, at the user's request
const EYE_Y = 2.6;
const GROUND_TILE = 4;                // units a repeat of the forest floor covers
const FOV = 50;
/* THE LAYERS, at the user's request, top to bottom:

     the menu            HTML, over everything
     MEWD                the page's own logo, HTML, over the dither —
                         its colours are the picture's, never snapped
     the blue overlay    BLUE, multiplied over the finished frame by
                         the pipeline's last pass (LofiPipeline.tint)
     the dither LUT      the game's own post pass (js/lofi.js)
     its shadows         drawn INTO the picture as an overlay, so the
                         dark behind the word is dithered with the wood
     monochrome          the forest taken to grey
     the forest          everything below

   The blue is over the dither, not under it, because the palette has
   no blue that saturated: under it, the wash came out slate. BLUE is
   the logo's own green-blue — the glass in its letters, about #20584d
   — muted and dark, at the user's request: white grass comes out a
   deep slate teal, the pines darker still. */
export const BLUE = [0.17, 0.36, 0.42];
const LUMA = 'vec3(0.299, 0.587, 0.114)';
/* THE WIND, at the user's request: the clock every plant's vertex
   shader bends to (see mono) */
const uWindTime = { value: 0 };

/** Grey (the blue comes later, over the dither): added to a MeshBasicMaterial's fragment shader after
 *  its colour and texture have been read. With a `sway`, the vertex
 *  shader BENDS the cutout in the wind too: the root stays put, the
 *  push goes as the square of the height up the plant, so a tuft curls
 *  over rather than tipping like a board — the cutouts are six strips
 *  tall for it (TitleForest.geo). The push is in world units, so a tall
 *  tree and a short tuft with the same `sway` lean the same angle, and
 *  its phase is where the plant stands, so a gust runs along the row. */
function mono(m, sway = 0) {
  m.onBeforeCompile = sh => {
    sh.fragmentShader = sh.fragmentShader.replace('#include <map_fragment>',
      `#include <map_fragment>
       diffuseColor.rgb = vec3(dot(diffuseColor.rgb, ${LUMA}));`);
    if (!sway) return;
    sh.uniforms.uWindTime = uWindTime;
    sh.vertexShader = 'uniform float uWindTime;\n' + sh.vertexShader.replace('#include <begin_vertex>',
      `#include <begin_vertex>
       {
         float wx = modelMatrix[3].x, sx = modelMatrix[0].x, hy = modelMatrix[1].y;
         /* AGGRESSIVE, at the user's request: gusts that roll along the
            row and nearly die between, a sway, and a whip at the tips */
         float gust = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(uWindTime * 0.45 - wx * 0.06), 2.0)
                    + 0.25 * sin(uWindTime * 1.1 - wx * 0.13);
         float bend = sin(uWindTime * 1.9 - wx * 0.27) + 0.45 * sin(uWindTime * 4.3 + wx * 1.7)
                    + 0.2 * sin(uWindTime * 9.1 + wx * 3.3) * position.y;
         float up = position.y * position.y;
         transformed.x += ${sway.toFixed(4)} * hy * up * gust * (0.8 + bend) / sx;
       }`);
  };
  m.customProgramCacheKey = () => 'mewd-mono-' + sway;
  return m;
}

/* the rows: depth, how wide the ring is, how many in it, what grows
   there and how tall, and its TINT, which is the air: the game swaps
   three's fog out for its own sector fog (js/material.js), which knows
   nothing of this scene, so the fog is off here and each row is
   coloured for how much air it stands behind — the far ones darker. */
/* THE ROWS, at the user's request: GRASS AND PINES AND NOTHING ELSE —
   seven rows of grass from under the eye back to the trees, and seven
   rows of pines behind them, each row of pines TALLER than the one in
   front, so the wood rises as it goes back.

   NO GAPS is arithmetic. A row hides the ground at the foot of the row
   behind it when its plants reach EYE_Y * (1 - z / zBehind) up — the
   line from the eye over their tops lands on the next row's roots —
   and a cutout is not solid, so every row is made twice that tall or
   more. Across a row, the plants stand closer than a third of their
   own height, so they overlap three deep and no sky shows between
   them. And behind the last pines is a dark band (see _build).

   Each row's TINT dims with depth — the air — and its SWAY is how hard
   the wind bends it: the grass hard, the tall pines at the back barely
   (see mono). */
const GRASS = ['meadow_grass_var_a', 'meadow_grass_var_b', 'new_meadow_grass_1', 'new_meadow_grass_2',
               'new_meadow_grass_tall_1', 'grass', 'savanna_grass_short_1', 'savanna_grass_short_2',
               'savanna_grass_tall_1', 'savanna_grass_tall_2'];
const PINES = ['pine_fir_tree_1', 'pine_fir_tree_2', 'pine_fir_tree_3', 'pine_fir_tree_4',
               'fir_tall_1', 'fir_tall_2', 'fir_medium', 'pine_barrens_tree'];
/* the widest a view gets, width over height, and how far past its edges
   a row runs so nothing is ever seen arriving */
const MAX_ASPECT = 2.6;
const ringFor = z => Math.abs(z) * 2 * Math.tan(THREE.MathUtils.degToRad(FOV / 2)) * MAX_ASPECT * 1.25 + 8;
const GRASS_Z = [-5.5, -8, -11, -15, -20, -26, -33];
const PINE_Z = [-40, -55, -75, -100, -130, -170, -220];
const PINE_H = [9, 12, 16, 21, 27, 34, 42];
const ROWS = [
  /* back to front, the order they were added in */
  ...PINE_Z.map((z, i) => ({ name: 'pines ' + (7 - i), z, h: [PINE_H[i] * 0.85, PINE_H[i] * 1.15], sink: 0.05,
    tint: 0.95 - i * 0.09, sway: 0.075 - i * 0.007, gap: 0.26, kinds: PINES })).reverse(),
  ...GRASS_Z.map((z, i) => ({ name: 'grass ' + (7 - i), z, h: [1.5 + i * 0.12, 2.3 + i * 0.16], sink: 0.35,
    tint: 1.25 - i * 0.05, sway: 0.34 - i * 0.025, gap: 0.3, kinds: GRASS })).reverse(),
].map(r => ({ ...r, tint: [r.tint, r.tint, r.tint], wrap: ringFor(r.z),
              n: Math.ceil(ringFor(r.z) / (r.gap * (r.h[0] + r.h[1]) / 2)) }));

/* a small seeded generator, so the forest is the same forest each time
   the page opens and differs only as far as it has been walked */
function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return (s >>> 0) / 4294967296; };
}

/** The black, blurred silhouette of a picture, as a texture with room
 *  round it for the blur: `pad` is that room as a fraction of the
 *  picture's width and height on each side. Null where there is no
 *  canvas (the headless tests). */
function shadowOf(img, blur) {
  if (typeof document === 'undefined' || !img || !img.width) return null;
  const k = Math.min(1, 720 / img.width);          // a shadow does not need the full picture
  const w = Math.round(img.width * k), h = Math.round(img.height * k), b = Math.round(blur * k);
  const c = document.createElement('canvas');
  c.width = w + b * 4; c.height = h + b * 4;
  const x = c.getContext('2d');
  x.filter = `blur(${b}px)`;
  x.drawImage(img, b * 2, b * 2, w, h);
  x.filter = 'none';
  x.globalCompositeOperation = 'source-in';
  x.fillStyle = '#000';
  x.fillRect(0, 0, c.width, c.height);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return { tex, pad: { x: (b * 2) / w, y: (b * 2) / h } };
}

export class TitleForest {
  constructor({ seed = 2037 } = {}) {
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(FOV, 16 / 9, 0.5, 600);
    this.camera.position.set(0, EYE_Y, 0);
    this.ready = false;
    this.x = 0;
    this.rand = rng(seed);
    this.rows = [];
    this.textures = new Map();
    this.materials = new Map();
    /* a plane standing on its bottom edge, so a scale is a height and a
       turn is a sway about the root */
    this.geo = new THREE.PlaneGeometry(1, 1, 1, 6);
    this.geo.translate(0, 0.5, 0);
  }

  /* THE LOGO'S SHADOWS, IN THE PICTURE. An orthographic overlay the
     pipeline draws over the forest and before its post pass. The logo
     itself is the page's, in front of the dither (see THE LAYERS); the
     overlay only darkens the wood behind it, and WHERE is copied from
     the page's logo every frame — so the shade sits exactly under the
     word on every screen shape. */
  async loadLogo(url) {
    const t = await new Promise((ok, no) => new THREE.TextureLoader().load(url, ok, undefined, no));
    t.colorSpace = THREE.SRGBColorSpace;
    this.logoTex = t;
    const scene = new THREE.Scene();
    const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 2);
    this.logo = new THREE.Mesh(new THREE.PlaneGeometry(1, 1),
      new THREE.MeshBasicMaterial({ map: t, transparent: true, depthTest: false, depthWrite: false, fog: false }));
    this.logo.renderOrder = 2;          // kept for its box; not drawn
    /* AND BEHIND IT, FOR CONTRAST, at the user's request: the logo's own
       outline, blurred and black, twice — a tight drop shadow a little
       down and right, which gives every letter an edge against the
       grass, and a wide dark halo, which pushes the whole wood back
       behind the word. Cut from the picture once, on a canvas; drawn
       under the logo, in the overlay, so they go through the dither. */
    this.shadows = [];
    for (const [blur, alpha, dx, dy, order] of [[70, 0.72, 0, 0.01, 0], [14, 0.9, 0.012, 0.03, 1]]) {
      const st = shadowOf(t.image, blur);
      if (!st) continue;
      const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1),
        new THREE.MeshBasicMaterial({ map: st.tex, transparent: true, opacity: alpha, depthTest: false, depthWrite: false, fog: false }));
      m.renderOrder = order;
      scene.add(m);
      this.shadows.push({ mesh: m, pad: st.pad, dx, dy });
    }
    this.overlay = { scene, camera, visible: false };
    return this;
  }

  /** Put the logo over the box `r` of the page, in a view whose box is `v`. */
  placeLogo(r, v) {
    if (!this.logo || !v.width || !v.height || !r.width) { if (this.overlay) this.overlay.visible = false; return; }
    const cx = ((r.left + r.width / 2 - v.left) / v.width) * 2 - 1;
    const cy = 1 - ((r.top + r.height / 2 - v.top) / v.height) * 2;
    const sw = r.width / v.width * 2, sh = r.height / v.height * 2;
    this.logo.position.set(cx, cy, -1);
    this.logo.scale.set(sw, sh, 1);
    /* the shadows are the logo's box grown by their blur, nudged by a
       fraction of the logo's own size so they scale with it */
    for (const s of this.shadows || []) {
      s.mesh.position.set(cx + s.dx * sw, cy - s.dy * sh, -1);
      s.mesh.scale.set(sw * (1 + 2 * s.pad.x), sh * (1 + 2 * s.pad.y), 1);
    }
    this.overlay.visible = true;
  }

  /** Fetch the pictures and build the rows. Resolves when it can be drawn. */
  async load() {
    const loader = new THREE.TextureLoader();
    const want = new Set(ROWS.flatMap(r => r.kinds));
    const get = url => new Promise((ok, no) => loader.load(url, ok, undefined, no));
    await Promise.all([...want].map(async k => {
      const t = await get(DIR + k + '.png');
      t.colorSpace = THREE.SRGBColorSpace;
      t.anisotropy = 4;
      this.textures.set(k, t);
    }));
    const sky = await get('assets/skies/BSKY1.png').catch(() => null);
    const ground = await get('assets/textures/GRASS5.png').catch(() => null);
    this._build(sky, ground);
    this.ready = true;
    return this;
  }

  _material(kind, tint, sway = 0) {
    const key = kind + tint + sway;
    let m = this.materials.get(key);
    if (!m) {
      m = new THREE.MeshBasicMaterial({ map: this.textures.get(kind), alphaTest: 0.5, side: THREE.DoubleSide, fog: false });
      m.color.setRGB(...tint);
      mono(m, sway);
      this.materials.set(key, m);
    }
    return m;
  }

  _build(sky, ground) {
    const s = this.scene;
    /* behind it all, the colour the sky has at the horizon */
    s.background = new THREE.Color().setRGB(0.12, 0.12, 0.12);

    /* THE SKY, the top half of BSKY1 on a plane that rides with the
       eye; its own drift is a slow slide of the picture */
    if (sky) {
      sky.colorSpace = THREE.SRGBColorSpace;
      sky.wrapS = THREE.RepeatWrapping;
      sky.repeat.set(0.5, 0.5);
      sky.offset.set(0, 0.5);
      this.skyTex = sky;
      const m = new THREE.MeshBasicMaterial({ map: sky, fog: false, depthWrite: false });
      m.color.setScalar(1.1);
      mono(m);
      this.sky = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), m);
      this.sky.renderOrder = -1;
      s.add(this.sky);
    }

    /* THE GROUND, a strip that rides with the eye and slides its
       texture the other way, which is the same as standing still */
    const g = mono(new THREE.MeshBasicMaterial({ color: 0x5a6a3a, fog: false }));
    if (ground) {
      ground.colorSpace = THREE.SRGBColorSpace;
      ground.wrapS = ground.wrapT = THREE.RepeatWrapping;
      ground.repeat.set(600 / GROUND_TILE, 300 / GROUND_TILE);
      g.map = ground; g.color.setRGB(0.55, 0.6, 0.5);
      this.groundTex = ground;
    }
    this.ground = new THREE.Mesh(new THREE.PlaneGeometry(600, 300), g);
    /* drawn straight after the sky and hiding nothing: everything in
       this world stands on it, and the grass stands a little IN it */
    g.depthWrite = false;
    this.ground.renderOrder = -0.5;
    this.ground.rotation.x = -Math.PI / 2;
    this.ground.position.set(0, 0, -150);
    s.add(this.ground);

    /* NO GAPS AT THE BACK: behind the last row of trees, a band the
       colour of a wood in shadow from the ground to well up their
       trunks, so what shows between them low down is more forest and
       never sky */
    const band = mono(new THREE.MeshBasicMaterial({ color: new THREE.Color().setRGB(0.09, 0.12, 0.10), fog: false }));
    this.band = new THREE.Mesh(new THREE.PlaneGeometry(1400, 30), band);
    this.band.position.set(0, 15 - 0.5, -240);
    s.add(this.band);

    for (const def of ROWS) {
      const row = { def, items: [] };
      const step = def.wrap / def.n;
      for (let i = 0; i < def.n; i++) {
        const m = new THREE.Mesh(this.geo, this._material(def.kinds[0], def.tint, def.sway));
        const it = { mesh: m, x: -def.wrap / 2 + (i + this.rand()) * step };
        this._dress(row, it);
        row.items.push(it);
        s.add(m);
      }
      this.rows.push(row);
    }
  }

  /** Make a cutout a plant: which one, how big, and a little in or out
   *  of its row so the rows do not read as rows. */
  _dress(row, it) {
    const d = row.def, r = this.rand;
    const kind = d.kinds[Math.floor(r() * d.kinds.length)];
    const t = this.textures.get(kind);
    const aspect = t.image.width / t.image.height;
    const h = d.h[0] + r() * (d.h[1] - d.h[0]);
    it.mesh.material = this._material(kind, d.tint, d.sway);
    it.mesh.scale.set(h * aspect * (r() < 0.5 ? -1 : 1), h, 1);
    it.z = d.z + (r() - 0.5) * Math.abs(d.z) * 0.12;
    /* the grass stands a little below the ground line, so its roots are
       never a hard edge along the bottom */
    it.y = -row.def.sink * (0.5 + r());
  }

  /** One frame: the eye moves on, and what has gone by comes round. */
  update(dt, aspect, now = performance.now()) {
    if (!this.ready) return;
    this.x += SPEED * Math.min(dt, 0.1);
    const cam = this.camera;
    if (Math.abs(cam.aspect - aspect) > 1e-4) { cam.aspect = aspect; cam.updateProjectionMatrix(); }
    cam.position.x = this.x;
    uWindTime.value = now / 1000;
    for (const row of this.rows) {
      const w = row.def.wrap, lo = this.x - w / 2;
      for (const it of row.items) {
        if (it.x < lo) { it.x += w; this._dress(row, it); }
        it.mesh.position.set(it.x, it.y, it.z);
      }
    }
    /* the sky: far enough to be behind everything, big enough to fill
       the view whatever its shape, and drifting at a crawl */
    if (this.sky) {
      const d = 400, hh = d * Math.tan(THREE.MathUtils.degToRad(FOV / 2));
      this.sky.position.set(this.x, EYE_Y + hh * 0.35, -d);
      this.sky.scale.set(hh * 2 * aspect * 1.05, hh * 2 * 0.95, 1);
      this.skyTex.offset.x = (this.x * 0.0006) % 1;
    }
    this.ground.position.x = this.x;
    this.band.position.x = this.x;
    if (this.groundTex) this.groundTex.offset.x = (this.x / GROUND_TILE) % 1;
  }

  dispose() {
    this.scene.traverse(o => { if (o.material) o.material.dispose?.(); });
    for (const t of this.textures.values()) t.dispose();
    this.skyTex?.dispose(); this.groundTex?.dispose(); this.logoTex?.dispose();
    this.logo?.material.dispose(); this.logo?.geometry.dispose();
    for (const sh of this.shadows || []) { sh.mesh.material.map.dispose(); sh.mesh.material.dispose(); sh.mesh.geometry.dispose(); }
    this.geo.dispose();
  }
}
