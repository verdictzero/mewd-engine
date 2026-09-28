/* =====================================================================
   MEWD Editor — the 3D view
   =====================================================================

   Ultimate Doom Builder's visual mode, on the game's own renderer: the
   level js/mapgeo.js builds, lit by the world shader, under the sky the
   game bakes. And, at the user's request, not only a place to LOOK at
   the map: EVERY MODE WORKS HERE the way it works on the plan.

     vertices  every corner has a handle; drag one across the floor
     lines     click a wall to pick its line; drag to move it
     sectors   click a floor or ceiling to pick its sector; drag it
     things    click the floor to put one down; drag one to move it
     props     drag across the floor to draw a box; drag one to move it
     draw      click corners on the floor, click the first to close
     rect      drag a room out across the floor
     scatter   drag a circle of the chosen mix out across the floor

   A drag here moves things across a level plane at the height it was
   grabbed at, snapped to the same grid as the plan, and it is the same
   drag (Editor.beginMove), so it undoes the same way. The outline being
   drawn is SHARED with the plan: corners clicked in either view go into
   the one outline.

   Hold the right button to look, and while it is held WASD, Q and E
   fly (Shift faster) — so while it is not, those letters are the mode
   keys they are on the plan. Or press Q for VISUAL MODE, Doom
   Builder's: the 3D view on its own, the mouse always looking, a
   crosshair to pick with, WASD to fly, Space and C for up and down; Q
   or Escape to come back. The wheel over a floor or a ceiling raises
   it; CTRL AND THE WHEEL CHANGE ITS BRIGHTNESS, as they do in Ultimate
   Doom Builder. Ctrl+C over a surface copies its texture and Ctrl+V
   pastes it; B is fullbright; F goes back to the start.

   PICKING IS DONE AGAINST THE DOCUMENT, NOT THE TRIANGLES. The level's
   triangles are batched into a few big meshes and do not know which
   sector they came from; the document does, and a ray against a few
   hundred floor planes and walls is nothing.

   THE SPRITES are drawn as the game draws them: billboards standing on
   the floor and turning to face you — the plants in their own pictures
   out of assets/forest/, the people as figures in their colours — and
   everything a scatter grows is drawn with them, so a spread is seen as
   what it is while it is being tuned.
   ===================================================================== */

import * as THREE from 'three';
import { buildLevelGeometry } from '../mapgeo.js';
import { buildSky, followSky } from '../sky.js';
import { loadSky } from '../texpack.js';
import { world, applyMapLight, worldUniforms, WORLD_UNIFORMS_GLSL, WORLD_SHADE_GLSL, SECTOR_GRID_GLSL } from '../material.js';
import { applySectorGrid } from '../sectorgrid.js';
import { Weather } from '../weather.js';
import { THING_TYPES, ringOf, centroid, pointInPoly, FEATURES, DEFAULT_FLOOR, layerFloorAt } from './doc.js';
import { makeSky } from './editor.js';
import { plantKind } from './scatter.js';
import { scatterAt, paintBrush } from './view2d.js';

const EYE = 41;              // how far above the floor the camera starts
const FLY = 600;             // units a second
const LOOK = 0.0028;         // radians a pixel
const HANDLE_PX = 10;        // how near a vertex handle has to be clicked
const PEOPLE = new Set(['SHOPPER', 'TOWNIE']);
const PERSON_H = 62;

export class View3D {
  constructor(ed, canvas) {
    this.ed = ed;
    this.canvas = canvas;
    const r = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
    r.setPixelRatio(Math.min(2, devicePixelRatio || 1));
    r.setClearColor(0x000000, 1);
    this.renderer = r;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(75, 1, 2, 30000);
    this.cam = null;          // { x, y, z, yaw, pitch } in map space
    this.keys = new Set();
    this.looking = false;
    this.hover = null;
    this.drag = null;
    this.clip = null;         // the texture Ctrl+C copied

    const sky = makeSky(r, ed.doc);
    this.baker = sky.baker;
    this.skyKey = JSON.stringify(ed.doc.world?.sky || {});
    this.sky = buildSky(this.baker.texture);
    this.scene.add(this.sky);

    this.levelGroup = null;
    this.markers = new THREE.Group();
    this.sprites = new THREE.Group();
    this.scene.add(this.markers, this.sprites);
    this.plantTex = new Map();
    this.personTex = personTexture();
    /* THE HIGHLIGHTS: the selection in orange, what is under the mouse
       in green, drawn over everything the way an editor's are */
    const hl = colour => new THREE.LineSegments(new THREE.BufferGeometry(),
      new THREE.LineBasicMaterial({ color: colour, depthTest: false, transparent: true, opacity: 0.95 }));
    this.selLines = hl(0xff9d3d); this.selLines.renderOrder = 1000;
    this.hovLines = hl(0x3ddc84); this.hovLines.renderOrder = 1001;
    /* and what is half-done: the outline being drawn, the cursor, a box
       or a circle being dragged out, the scatters' areas */
    this.drawLines = hl(0xffb454); this.drawLines.renderOrder = 1002;
    this.areaLines = new THREE.LineSegments(new THREE.BufferGeometry(),
      new THREE.LineBasicMaterial({ color: 0xc878ff, transparent: true, opacity: 0.75, depthTest: false }));
    this.areaLines.renderOrder = 999;
    this.scene.add(this.selLines, this.hovLines, this.drawLines, this.areaLines);
    /* the vertex handles, in vertex mode */
    this.handles = new THREE.Points(new THREE.BufferGeometry(),
      new THREE.PointsMaterial({ size: 7, sizeAttenuation: false, vertexColors: true, depthTest: false, transparent: true }));
    this.handles.renderOrder = 1003;
    this.scene.add(this.handles);
    /* AND EVERY EDGE IN THE MAP, faintly, depth-tested: the grid's own
       walls are black between their lines, and an editor has to show
       where a wall is whether its texture does or not */
    this.edges = new THREE.LineSegments(new THREE.BufferGeometry(),
      new THREE.LineBasicMaterial({ color: 0x8fb3a0, transparent: true, opacity: 0.35 }));
    this.scene.add(this.edges);
    this.fullbright = false;
    /* THE GRID AND THE AXES, Blender's way: the plan's grid on the
       ground at height 0, laid from the origin, fading into the
       distance; the X axis red, the Y axis green and Z — up — blue,
       through 0,0,0, and a mark on the origin itself. While something
       is being drawn on a floor that is not at 0, the grid comes up to
       that floor, so a corner clicked in 3D lands where you can see it
       will. */
    this.grid = buildGrid();
    this.axes = buildAxes();
    this.scene.add(this.grid, this.axes);
    this.showGrid = true;
    /* and the gizmo in the corner: which way X, Y and Z are from here */
    this.gizmo = document.createElement('canvas');
    this.gizmo.className = 'ed-gizmo';
    this.gizmo.width = this.gizmo.height = GIZMO * Math.min(2, devicePixelRatio || 1);
    canvas.parentElement?.appendChild(this.gizmo);

    const ro = new ResizeObserver(() => this.resize());
    ro.observe(canvas.parentElement);
    this.resize();

    canvas.addEventListener('pointerdown', e => this.down(e));
    canvas.addEventListener('pointermove', e => this.move(e));
    canvas.addEventListener('pointerup', e => this.up(e));
    canvas.addEventListener('pointercancel', e => this.up(e));
    canvas.addEventListener('dblclick', () => {
      if (ed.mode === 'draw') { ed.closePath({ open: true }); return; }
      if (ed.mode === 'things' && this.mouse) {
        const R = this.ray(this.mouse[0], this.mouse[1]), h = this.pick(R);
        if (h?.kind !== 'thing') { const g = this.ground(R, h); if (g) ed.addThing(g[0], g[1]); return; }
      }
      if (ed.sel.kind) ed.ui.showTab('insp');
    });
    canvas.addEventListener('wheel', e => this.wheel(e), { passive: false });
    canvas.addEventListener('contextmenu', e => e.preventDefault());
    canvas.addEventListener('pointerenter', () => { ed.pointerView = '3d'; });
    canvas.addEventListener('pointerleave', () => { if (!this.looking && !this.drag && !this.visual) { this.hover = null; this.mouse = null; this.drawHover(); ed.setHover(null); } });
    document.addEventListener('pointerlockchange', () => {
      if (document.pointerLockElement !== canvas && this.looking) this.stopLook();
      if (document.pointerLockElement !== canvas && this.visual) this.toggleVisual(false);
      if (document.pointerLockElement === canvas) this.skipMove = performance.now() + 150;
    });
    addEventListener('keyup', e => this.keys.delete(e.code));
    addEventListener('blur', () => this.keys.clear());

    ed.on('compiled', () => this.rebuild());
    ed.on('sel', () => { this.drawSel(); this.overlayDirty = true; });
    ed.on('doc', () => { this.overlayDirty = true; if (ed.sel.kind === 'scatter') this.drawSel(); });
    for (const ev of ['path', 'cursor', 'mode']) ed.on(ev, () => { this.overlayDirty = true; });
    ed.on('frame', () => { if (!this.cam) this.toStart(); });

    this.last = performance.now();
    const tick = now => {
      const dt = Math.min(0.1, (now - this.last) / 1000);
      this.last = now;
      /* the pack's animated textures step on at Doom's rate, whichever
         view is showing them (js/texpack.js) */
      ed.anim?.tick(dt);
      if (ed.layout !== 'only2d') this.frame(dt);
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  /** VISUAL MODE on or off. */
  toggleVisual(on = !this.visual) {
    const ed = this.ed, wrap = this.canvas.parentElement;
    if (on === this.visual) return;
    this.visual = on;
    wrap.classList.toggle('visual', on);
    if (on) {
      this.before = ed.layout;
      if (ed.layout !== 'only3d') ed.setLayout('only3d');
      ed.pointerView = '3d';
      if (!this.cam) this.toStart();
      try { this.canvas.requestPointerLock?.(); } catch (e) { /* then it looks by dragging */ }
      this.mouse = [this.w / 2, this.h / 2];
      this.hoverDirty = true;
      ed.say('VISUAL MODE — mouse looks, WASD flies, Space/C up and down, click picks, wheel raises, Ctrl+wheel brightness; Q or Esc leaves');
    } else {
      this.keys.clear();
      if (document.pointerLockElement === this.canvas) document.exitPointerLock?.();
      if (this.before && this.before !== 'only3d') ed.setLayout(this.before);
      ed.say('left visual mode');
    }
    ed.emit('visual', on);
  }

  resize() {
    const r = this.canvas.parentElement.getBoundingClientRect();
    const w = Math.max(1, r.width), h = Math.max(1, r.height);
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.w = w; this.h = h;
  }

  /** The camera to the player's start, standing. */
  toStart() {
    const t = this.ed.doc.things.find(q => q.type === 'START') || { x: 0, y: 0, angle: 0 };
    this.cam = { x: t.x, y: t.y, z: this.thingZ(t) + EYE, yaw: t.angle || 0, pitch: -0.12 };
    this.ed.emit('camera');
  }

  /** The floor at (x, y), as the compiled level has it — which is what
   *  the game will stand things on. */
  floorZ(x, y) {
    /* ON AN UPPER LAYER, the floor of that layer: what is drawn and
       placed there stands on it (see LAYERS in js/editor/doc.js) */
    if (this.ed.layer) return this.ed.layerFloor(x, y);
    const L = this.ed.compiled?.level;
    const s = L?.sectorAt(x, y);
    if (s) return L.floorAt(s, x, y);
    const ds = this.ed.sectorAt(x, y);
    return ds ? zOf(this.ed.doc, ds, 'floor', x, y) : 0;
  }

  /** The floor a thing stands on: its own layer's, where it has one. */
  thingZ(t) {
    if ((t.layer | 0) === this.ed.layer) return this.floorZ(t.x, t.y);
    const z = layerFloorAt(this.ed.doc, t.layer | 0, t.x, t.y);
    return z ?? this.floorZ(t.x, t.y);
  }

  /* ------------------------------------------------------------------
     THE LEVEL, rebuilt from every compile
     ------------------------------------------------------------------ */
  rebuild() {
    const c = this.ed.compiled;
    if (!c?.level) return;
    /* the map's own light colour, ambient light and fog (World panel) */
    applyMapLight(c.level.mapLight);
    /* and the sectors for what stands in them: sprites, trees, models */
    applySectorGrid(c.level);
    if (this.levelGroup) {
      this.scene.remove(this.levelGroup);
      disposeTree(this.levelGroup);
      this.levelGroup = null;
    }
    try {
      this.geo = buildLevelGeometry(c.level, this.ed.bank);
      this.levelGroup = this.geo.group;
      this.scene.add(this.levelGroup);
    } catch (e) {
      console.error(e);
      this.ed.say(`the 3D view could not build the map: ${e.message}`);
    }
    /* the sky again, if the map's own changed */
    const key = JSON.stringify(this.ed.doc.world?.sky || {});
    if (key !== this.skyKey) {
      this.skyKey = key;
      const sky = { ...(this.ed.doc.world?.sky || {}), midAmt: 1, bare: true, snap: 0 };
      this.baker.bake(new Weather({ hour: 2.0, kind: 'clear', running: false, fireHaze: false, sky }).frame);
    }
    /* A SKYBOX FROM THE PACK in place of the painted sky, on the sphere
       and in the air the far walls fade to (world.skyTex) */
    const box = this.ed.doc.world?.skybox || null;
    if (box !== this.skybox) {
      this.skybox = box;
      const use = t => { if (this.skybox !== box) return; const tex = t || this.baker.texture; this.sky.material.uniforms.map.value = tex; world.skyTex.value = tex; };
      if (box) loadSky(box).then(use); else use(null);
    }
    this.buildMarkers();
    this.buildSprites();
    this.buildEdges();
    this.drawSel();
    this.overlayDirty = true;
    if (!this.cam) this.toStart();
  }

  /** The things that are not sprites here — the start, the furniture —
   *  as posts in their colours with a pointer for facing. */
  buildMarkers() {
    disposeTree(this.markers);
    this.markers.clear();
    const d = this.ed.doc;
    const list = [...d.things.map(t => [t, false]), ...(this.ed.compiled?.scattered || []).map(t => [t, true])]
      .filter(([t]) => t.type !== 'PLANT' && !PEOPLE.has(t.type));
    if (!list.length) return;
    const geo = new THREE.CylinderGeometry(1, 1, 1, 10);
    geo.translate(0, 0.5, 0);
    const mat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85 });
    const mesh = new THREE.InstancedMesh(geo, mat, list.length);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), col = new THREE.Color();
    const arrows = [];
    list.forEach(([t, grown], i) => {
      const def = THING_TYPES[t.type] || { color: '#f0f', radius: 16 };
      const z = this.thingZ(t);
      const hgt = thingHeight(t), r = def.radius * 0.6;
      m.compose(new THREE.Vector3(t.x, z, -t.y), q, new THREE.Vector3(r, hgt, r));
      mesh.setMatrixAt(i, m);
      mesh.setColorAt(i, col.set(def.color).multiplyScalar(grown ? 0.75 : 1));
      const a = t.angle || 0, top = z + hgt + 2, L = Math.max(24, def.radius * 1.8);
      if (!grown) arrows.push(t.x, top, -t.y, t.x + Math.cos(a) * L, top, -(t.y + Math.sin(a) * L));
    });
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    this.markers.add(mesh);
    const ag = new THREE.BufferGeometry();
    ag.setAttribute('position', new THREE.Float32BufferAttribute(arrows, 3));
    this.markers.add(new THREE.LineSegments(ag, new THREE.LineBasicMaterial({ color: 0xffe08a })));
  }

  /** THE SPRITES: every plant and every person, placed or grown, as a
   *  billboard on the floor — one instanced draw per picture. */
  buildSprites() {
    disposeTree(this.sprites, true);
    this.sprites.clear();
    const all = [...this.ed.doc.things, ...(this.ed.compiled?.scattered || [])];
    const byKey = new Map();
    for (const t of all) {
      let key = null;
      if (t.type === 'PLANT' && plantKind(t.kind)) key = `plant:${t.kind}`;
      else if (PEOPLE.has(t.type)) key = `person:${t.type}`;
      if (!key) continue;
      (byKey.get(key) || byKey.set(key, []).get(key)).push(t);
    }
    const quad = new THREE.PlaneGeometry(1, 1);
    quad.translate(0, 0.5, 0);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion();
    for (const [key, list] of byKey) {
      const [what, name] = key.split(':');
      let tex, w, h, tint;
      if (what === 'plant') {
        const k = plantKind(name);
        tex = this.plantTexture(name); h = k.h; w = k.h * k.aspect; tint = new THREE.Color(1, 1, 1);
      } else {
        tex = this.personTex; h = PERSON_H; w = PERSON_H * 0.45; tint = new THREE.Color(THING_TYPES[name]?.color || '#fff');
      }
      const mat = billboardMaterial(tex, tint);
      const mesh = new THREE.InstancedMesh(quad, mat, list.length);
      list.forEach((t, i) => {
        const s = t.scale ?? 1;
        m.compose(new THREE.Vector3(t.x, this.floorZ(t.x, t.y), -t.y), q, new THREE.Vector3(w * s, h * s, 1));
        mesh.setMatrixAt(i, m);
      });
      mesh.instanceMatrix.needsUpdate = true;
      mesh.frustumCulled = false;
      this.sprites.add(mesh);
    }
  }

  plantTexture(name) {
    let t = this.plantTex.get(name);
    if (!t) {
      t = new THREE.TextureLoader().load(`assets/forest/${name}.png`, () => { t.needsUpdate = true; });
      t.magFilter = THREE.NearestFilter;
      t.minFilter = THREE.NearestMipmapNearestFilter;
      t.colorSpace = THREE.NoColorSpace;
      this.plantTex.set(name, t);
    }
    return t;
  }

  buildEdges() {
    const d = this.ed.doc, pts = [];
    const P = (x, y, z) => pts.push(x, z, -y);
    /* only where there IS an edge: along every floor; along a ceiling
       that is not the sky; and up a corner as far as a wall stands there
       — the whole height of a one-sided wall, the step between two
       floors, and the step between two ceilings with a roof on */
    const seg = (x0, y0, z0, x1, y1, z1) => { P(x0, y0, z0); P(x1, y1, z1); };
    for (const l of this.ed.lines()) {
      const a = d.vertices[l.a], b = d.vertices[l.b];
      const ss = l.sectors.map(i => d.sectors[i]);
      for (const s of ss) {
        seg(a[0], a[1], zOf(d, s, 'floor', a[0], a[1]), b[0], b[1], zOf(d, s, 'floor', b[0], b[1]));
        if (s.ceilTex !== 'SKY' || ss.length === 1) seg(a[0], a[1], zOf(d, s, 'ceil', a[0], a[1]), b[0], b[1], zOf(d, s, 'ceil', b[0], b[1]));
      }
      for (const v of [a, b]) {
        const fl = ss.map(s => zOf(d, s, 'floor', v[0], v[1])), ce = ss.map(s => zOf(d, s, 'ceil', v[0], v[1]));
        if (ss.length === 1) { seg(v[0], v[1], fl[0], v[0], v[1], ce[0]); continue; }
        if (Math.max(...fl) > Math.min(...fl)) seg(v[0], v[1], Math.min(...fl), v[0], v[1], Math.max(...fl));
        /* the step between two ceilings — not where one of them is the
           sky, which an open world does not draw (see 5a in doc.js) */
        const skyWalls = d.world?.skyWalls;
        if (ss.some(s => s.outdoor === false) && (skyWalls || ss.every(s => s.ceilTex !== 'SKY')) && Math.max(...ce) > Math.min(...ce)) seg(v[0], v[1], Math.min(...ce), v[0], v[1], Math.max(...ce));
      }
      /* a building's outside wall, standing in the opening */
      if (ss.length === 2 && exteriorWall(d, l)) {
        const top = Math.min(...ss.map(s => s.ceil ?? 0)), bot = Math.max(...ss.map(s => s.floor ?? 0));
        seg(a[0], a[1], top, b[0], b[1], top);
        for (const v of [a, b]) seg(v[0], v[1], bot, v[0], v[1], top);
      }
    }
    for (const p of d.props) box(P, p.x0, p.y0, p.z0, p.x1, p.y1, p.z1);
    setLines(this.edges, pts);
  }

  /** Every surface at its full brightness, whatever the sector's light
   *  and however far away — Doom Builder's fullbright, on B. */
  setFullbright(on) {
    this.fullbright = on;
    if (!this.lit) this.lit = { minLight: world.minLight.value, lightFalloff: world.lightFalloff.value, globalLight: world.globalLight.value };
    world.minLight.value = on ? 1 : this.lit.minLight;
    world.lightFalloff.value = on ? 1e9 : this.lit.lightFalloff;
    world.globalLight.value = on ? 1.4 : this.lit.globalLight;
    this.ed.say(`fullbright ${on ? 'on' : 'off'}`);
  }

  /* ------------------------------------------------------------------
     PICKING
     ------------------------------------------------------------------ */
  /** The ray under a pixel, in map space. */
  ray(px, py) {
    const ndc = new THREE.Vector2((px / this.w) * 2 - 1, -(py / this.h) * 2 + 1);
    const rc = new THREE.Raycaster();
    rc.setFromCamera(ndc, this.camera);
    const o = rc.ray.origin, v = rc.ray.direction;
    return { ox: o.x, oy: -o.z, oz: o.y, dx: v.x, dy: -v.z, dz: v.y };
  }

  /** Where the ray meets the level plane at height z, or null. */
  onPlane(R, z) {
    if (Math.abs(R.dz) < 1e-6) return null;
    const t = (z - R.oz) / R.dz;
    if (!(t > 0) || t > 40000) return null;
    return [R.ox + R.dx * t, R.oy + R.dy * t, z];
  }

  /** THE FLOOR UNDER THE MOUSE: the floor the ray hits first, or — if it
   *  hits a wall, a thing or the sky first — the plane at the height of
   *  the floor under the camera. What draw, place and paint stand on. */
  ground(R, hit = this.pick(R)) {
    if (hit?.kind === 'surface' && hit.part === 'floor') return [hit.x, hit.y, R.oz + R.dz * hit.t];
    return this.onPlane(R, this.cam ? this.floorZ(this.cam.x, this.cam.y) : 0);
  }

  /** A ground point snapped: to a vertex within a few pixels of the
   *  mouse, or to the grid. */
  snapGround(g, px, py) {
    if (!g) return null;
    const v = this.nearestHandle(px, py);
    if (v !== null) { const p = this.ed.doc.vertices[v]; this.snapKind = 'vertex'; return [p[0], p[1]]; }
    /* then a line, as on the plan (Editor.snapAt), within what the
       handle's pixels are worth at that distance */
    const s = this.ed.snapAt(g[0], g[1], this.pxToMap(g, HANDLE_PX), { vertices: false });
    this.snapKind = s.kind;
    return s.pt;
  }
  /** How many map units `n` pixels are, at a point on the ground. */
  pxToMap(g, n) {
    const c = this.camera.position;
    const dist = Math.hypot(g[0] - c.x, (g[2] ?? 0) - c.y, -g[1] - c.z);
    return dist * 2 * Math.tan(this.camera.fov * Math.PI / 360) / Math.max(1, this.h) * n;
  }

  /** Where a map point is on the screen, or null behind the camera. */
  toScreen(x, y, z) {
    const v = new THREE.Vector3(x, z, -y).project(this.camera);
    if (v.z > 1 || v.z < -1) return null;
    return [(v.x + 1) / 2 * this.w, (1 - v.y) / 2 * this.h];
  }

  /** The vertex handle nearest a pixel, within HANDLE_PX, or null. */
  nearestHandle(px, py) {
    const d = this.ed.doc;
    let best = null, bd = HANDLE_PX * HANDLE_PX;
    d.vertices.forEach((v, i) => {
      const s = this.toScreen(v[0], v[1], this.floorZ(v[0], v[1]));
      if (!s) return;
      const q = (s[0] - px) ** 2 + (s[1] - py) ** 2;
      if (q < bd) { bd = q; best = i; }
    });
    return best;
  }

  /**
   * What the ray hits first: `{ t, kind, part, sector, line, band, id }`.
   * kind is 'surface' (part floor | ceil | wall), 'thing' or 'prop'.
   */
  pick(R) {
    const d = this.ed.doc;
    let best = null;
    const take = h => { if (h.t > 0.5 && (!best || h.t < best.t)) best = h; };

    /* floors and ceilings: every sector's two planes, kept only where
       the hit lands in that sector and not in a smaller one inside it */
    d.sectors.forEach((s, si) => {
      const r = ringOf(d, s);
      if (r.length < 3) return;
      const [cx, cy] = centroid(r);
      for (const part of ['floor', 'ceil']) {
        /* under the sky there is no ceiling to pick */
        if (part === 'ceil' && s.ceilTex === 'SKY') continue;
        const sl = FEATURES.slopes ? (part === 'floor' ? s.floorSlope : s.ceilSlope) : null;
        const z0 = part === 'floor' ? (s.floor ?? 0) : (s.ceil ?? 256);
        const sx = sl?.dzdx || 0, sy = sl?.dzdy || 0;
        const den = R.dz - sx * R.dx - sy * R.dy;
        /* a floor is seen from above and a ceiling from below */
        if (part === 'floor' ? den >= -1e-6 : den <= 1e-6) continue;
        const t = (z0 + sx * (R.ox - cx) + sy * (R.oy - cy) - R.oz) / den;
        if (!(t > 0)) continue;
        const x = R.ox + R.dx * t, y = R.oy + R.dy * t;
        if (!pointInPoly(r, x, y)) continue;
        if (this.ed.sectorAt(x, y) !== s) continue;
        take({ t, kind: 'surface', part, sector: si, x, y });
      }
    });

    /* the walls: every line, and which band of it the hit is in */
    for (const l of this.ed.lines()) {
      const a = d.vertices[l.a], b = d.vertices[l.b];
      const ex = b[0] - a[0], ey = b[1] - a[1];
      const den = R.dx * ey - R.dy * ex;
      if (Math.abs(den) < 1e-9) continue;
      const qx = a[0] - R.ox, qy = a[1] - R.oy;
      const t = (qx * ey - qy * ex) / den;
      const u = (qx * R.dy - qy * R.dx) / den;
      if (!(t > 0) || u < 0 || u > 1) continue;
      const x = R.ox + R.dx * t, y = R.oy + R.dy * t, z = R.oz + R.dz * t;
      const ss = l.sectors.map(i => d.sectors[i]);
      const fl = ss.map(s => zOf(d, s, 'floor', x, y)), ce = ss.map(s => zOf(d, s, 'ceil', x, y));
      /* the sector on the camera's side of the line */
      const side = ex * (R.oy - a[1]) - ey * (R.ox - a[0]);
      let front = l.sectors[0];
      if (ss.length > 1) {
        const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2, L = Math.hypot(ex, ey);
        const nx = -ey / L * Math.sign(side) * 2, ny = ex / L * Math.sign(side) * 2;
        const on = this.ed.sectorAt(mx + nx, my + ny);
        const k = l.sectors.findIndex(i => d.sectors[i] === on);
        if (k >= 0) front = l.sectors[k];
      }
      if (ss.length === 1) {
        if (z >= fl[0] && z <= ce[0]) take({ t, kind: 'surface', part: 'wall', band: 'middle', line: l.key, sector: front, x, y, z });
      } else {
        const fLo = Math.min(...fl), fHi = Math.max(...fl), cLo = Math.min(...ce), cHi = Math.max(...ce);
        if (z >= fLo && z <= fHi && fHi > fLo) take({ t, kind: 'surface', part: 'wall', band: 'lower', line: l.key, sector: front, x, y, z });
        else if (z >= cLo && z <= cHi && cHi > cLo && !ss.some(q => q.ceilTex === 'SKY')) take({ t, kind: 'surface', part: 'wall', band: 'upper', line: l.key, sector: front, x, y, z });
        /* and a wall standing in the opening: a building's outside wall,
           or a middle texture — see midWall */
        else if (z > fHi && z < cLo && midWall(d, l)) take({ t, kind: 'surface', part: 'wall', band: 'middle', line: l.key, sector: front, x, y, z });
      }
    }

    /* the props, as boxes */
    for (const p of d.props) {
      const bx = [Math.min(p.x0, p.x1), Math.max(p.x0, p.x1)], by = [Math.min(p.y0, p.y1), Math.max(p.y0, p.y1)];
      const bz = [Math.min(p.z0, p.z1), Math.max(p.z0, p.z1)];
      const t = slab(R, bx, by, bz);
      if (t !== null) take({ t, kind: 'prop', id: p.id });
    }
    /* and the things placed by hand, as posts as tall as they stand */
    for (const th of d.things) {
      if (!this.ed.onLayer(th)) continue;
      const def = THING_TYPES[th.type] || { radius: 16 };
      const z = this.thingZ(th);
      const rad = Math.max(8, def.radius * 0.6);
      const t = slab(R, [th.x - rad, th.x + rad], [th.y - rad, th.y + rad], [z, z + thingHeight(th)]);
      if (t !== null) take({ t, kind: 'thing', id: th.id });
    }
    return best;
  }

  /* ------------------------------------------------------------------
     THE MOUSE — every mode, as on the plan
     ------------------------------------------------------------------ */
  at(e) {
    /* in visual mode everything happens at the crosshair */
    if (this.visual) return [this.w / 2, this.h / 2];
    const r = this.canvas.getBoundingClientRect();
    return [e.clientX - r.left, e.clientY - r.top];
  }

  down(e) {
    this.canvas.focus();
    if (this.visual && document.pointerLockElement !== this.canvas) {
      /* the lock can be refused until the page is clicked; this click */
      try { this.canvas.requestPointerLock?.(); } catch (err) { /* keep going */ }
    }
    if (e.button === 2 && this.ed.mode === 'draw' && this.ed.path.length) { this.ed.closePath({ open: true }); return; }
    if (e.button === 2 && !this.visual) {
      this.looking = true;
      this.canvas.parentElement.classList.add('look');
      try { this.canvas.requestPointerLock?.(); } catch (err) { /* then it looks by dragging */ }
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0 || !this.cam) return;
    const ed = this.ed, mode = ed.mode;
    const [px, py] = this.at(e);
    const R = this.ray(px, py);
    const hit = this.pick(R);
    const g = this.ground(R, hit);
    const sg = this.snapGround(g, px, py);
    /* Chrome refuses a pointer capture while the pointer is locked, and
       in visual mode it is */
    if (!document.pointerLockElement) { try { this.canvas.setPointerCapture(e.pointerId); } catch (err) { /* fine */ } }
    const grab = (kind, id, z, at) => {
      if (e.shiftKey || e.ctrlKey) { ed.select(kind, [id], true); return; }
      if (!ed.isSel(kind, id)) ed.select(kind, [id]);
      this.drag = { type: 'move', z, mv: ed.beginMove(ed.grabPoint(at), at), px, py, moved: false };
    };

    if (mode === 'draw') { if (sg) ed.addPathPoint(sg); return; }
    if (mode === 'rect') { if (sg) this.drag = { type: 'rect', z: g[2], a: sg, b: sg }; return; }

    /* VISUAL MODE picks surfaces and things, whatever mode the plan is
       in, as Doom Builder's does */
    if (mode === 'vertices' && !this.visual) {
      const v = this.nearestHandle(px, py);
      if (v === null) { if (!e.shiftKey) ed.clearSel(); return; }
      const p = ed.doc.vertices[v];
      grab('vertex', v, this.floorZ(p[0], p[1]), [p[0], p[1]]);
      return;
    }
    if (mode === 'things') {
      if (hit?.kind === 'thing') { const t = ed.doc.things.find(q => q.id === hit.id); grab('thing', hit.id, this.thingZ(t), [t.x, t.y]); return; }
      /* a click on the floor lets go; a double-click (or Insert) places */
      if (!e.shiftKey) ed.clearSel();
      return;
    }
    if (mode === 'props') {
      if (hit?.kind === 'prop') {
        const p = ed.doc.props.find(q => q.id === hit.id), at = this.onPlane(R, p.z0) || [p.x0, p.y0];
        grab('prop', hit.id, p.z0, [at[0], at[1]]);
        return;
      }
      if (g) this.drag = { type: 'prop', z: g[2], a: [ed.snapV(g[0]), ed.snapV(g[1])], b: [ed.snapV(g[0]), ed.snapV(g[1])] };
      return;
    }
    if (mode === 'scatter') {
      const c = g && !e.altKey ? scatterAt(ed.doc, g[0], g[1]) : null;
      if (c) { grab('scatter', c.id, g[2], [g[0], g[1]]); return; }
      if (g) this.drag = { type: 'brush', z: g[2], a: [ed.snapV(g[0]), ed.snapV(g[1])], b: [ed.snapV(g[0]), ed.snapV(g[1])] };
      return;
    }
    /* sectors and lines: a surface is picked the way visual mode picks
       it — for the inspector and for painting — and then dragged */
    if (!hit) { ed.clearSel(); return; }
    if (hit.kind === 'thing') { ed.setMode('things'); ed.select('thing', [hit.id]); return; }
    if (hit.kind === 'prop') { ed.setMode('props'); ed.select('prop', [hit.id]); return; }
    if (hit.part === 'wall') {
      if (e.shiftKey && ed.sel.kind === 'line') { ed.select('line', [hit.line], true); return; }
      const already = ed.isSel('line', hit.line);
      if (!already) ed.selectSurface({ sector: hit.sector, part: 'wall', line: hit.line, band: hit.band });
      if (mode === 'lines') {
        const z = this.floorZ(hit.x, hit.y), at = this.onPlane(R, z) || [hit.x, hit.y];
        this.drag = { type: 'move', z, mv: ed.beginMove(ed.grabPoint([at[0], at[1]]), [at[0], at[1]]), px, py, moved: false };
      }
      return;
    }
    const s = ed.doc.sectors[hit.sector];
    /* A DRAG ON THE GROUND'S FLOOR DRAWS a new rectangle, as on the
       plan; a click selects it; Alt-drag moves it */
    if (mode === 'sectors' && hit.part === 'floor' && !e.altKey && !e.shiftKey && ed.isGround(s.id) && sg) {
      this.drag = { type: 'rect', z: g[2], a: sg, b: sg, ground: s.id, hit, px, py };
      return;
    }
    if (e.shiftKey && ed.sel.kind === 'sector') {
      ed.select('sector', [s.id], true);
      ed.surf = { sector: hit.sector, part: hit.part };
      ed.emit('sel');
      return;
    }
    if (!ed.isSel('sector', s.id) || ed.surf?.part !== hit.part) {
      const keep = ed.isSel('sector', s.id) ? new Set(ed.sel.ids) : null;
      ed.selectSurface({ sector: hit.sector, part: hit.part });
      if (keep && keep.size > 1) { ed.sel.ids = keep; ed.emit('sel'); }
    }
    const z = R.oz + R.dz * hit.t;
    this.drag = { type: 'move', z, mv: ed.beginMove(ed.grabPoint([hit.x, hit.y]), [hit.x, hit.y]), px, py, moved: false };
  }

  move(e) {
    /* the first movement after the pointer locks is where the pointer
       WAS, not a movement — Chrome reports it — and it spun the view */
    if (this.skipMove && performance.now() < this.skipMove) return;
    /* and a jump no hand made — Chrome sends a few after the lock */
    if (document.pointerLockElement && (Math.abs(e.movementX) > 250 || Math.abs(e.movementY) > 250)) return;
    if (this.visual && this.cam && !this.drag) {
      this.cam.yaw -= e.movementX * LOOK;
      this.cam.pitch = Math.max(-1.5, Math.min(1.5, this.cam.pitch - e.movementY * LOOK));
      this.mouse = [this.w / 2, this.h / 2];
      this.hoverDirty = true;
      this.ed.emit('camera');
      return;
    }
    if (this.looking && this.cam) {
      this.cam.yaw -= e.movementX * LOOK;
      this.cam.pitch = Math.max(-1.5, Math.min(1.5, this.cam.pitch - e.movementY * LOOK));
      this.ed.emit('camera');
      return;
    }
    const [px, py] = this.at(e);
    this.mouse = [px, py];
    const dr = this.drag;
    /* in visual mode a drag goes where the crosshair is pointed, which
       the mouse is doing by looking */
    if (dr && this.visual) {
      this.cam.yaw -= e.movementX * LOOK;
      this.cam.pitch = Math.max(-1.5, Math.min(1.5, this.cam.pitch - e.movementY * LOOK));
    }
    if (dr && this.cam) {
      const p = this.onPlane(this.ray(px, py), dr.z);
      if (!p) return;
      if (dr.type === 'move') {
        if (!dr.moved && Math.hypot(px - dr.px, py - dr.py) < 4) return;
        dr.moved = true;
        this.ed.dragMove(dr.mv, [p[0], p[1]], this.pxToMap([p[0], p[1], dr.z], HANDLE_PX));
      } else {
        dr.b = dr.type === 'rect' ? (this.snapGround(p, px, py) || dr.b) : [this.ed.snapV(p[0]), this.ed.snapV(p[1])];
        this.overlayDirty = true;
      }
      return;
    }
    this.hoverDirty = true;
  }

  up(e) {
    const ed = this.ed;
    if (e.button === 2 && this.looking) { this.stopLook(); return; }
    try { this.canvas.releasePointerCapture(e.pointerId); } catch (err) { /* gone */ }
    const dr = this.drag;
    this.drag = null;
    if (!dr) return;
    if (dr.type === 'move') ed.endMove(dr.mv);
    else if (dr.type === 'rect') {
      const [qx, qy] = this.at(e);
      if (dr.ground && Math.hypot(qx - dr.px, qy - dr.py) < 4) {
        ed.selectSurface({ sector: dr.hit.sector, part: dr.hit.part });
        ed.say('the ground — drag on it to draw a new sector; Alt-drag moves it');
      } else ed.addRect(dr.a, dr.b);
    } else if (dr.type === 'prop') ed.addProp(dr.a[0], dr.a[1], dr.b[0], dr.b[1]);
    else if (dr.type === 'brush') paintBrush(ed, dr.a, dr.b);
    this.overlayDirty = true;
  }

  stopLook() {
    this.looking = false;
    this.keys.clear();
    this.canvas.parentElement.classList.remove('look');
    if (document.pointerLockElement === this.canvas) document.exitPointerLock?.();
  }

  wheel(e) {
    e.preventDefault();
    const ed = this.ed;
    const h = this.hover;
    /* CTRL AND THE WHEEL: the brightness of the sector under the mouse —
       every selected sector with it, if it is one of them — in Doom's
       sixteen steps (Shift: one at a time) */
    if (e.ctrlKey || e.metaKey) {
      /* a thing or a prop is lit by the sector it stands in */
      let s = h?.kind === 'surface' ? ed.doc.sectors[h.sector] : null;
      if (!s && h?.kind === 'thing') { const t = ed.doc.things.find(q => q.id === h.id); if (t) s = ed.sectorAt(t.x, t.y); }
      if (!s && h?.kind === 'prop') { const p = ed.doc.props.find(q => q.id === h.id); if (p) s = ed.sectorAt((p.x0 + p.x1) / 2, (p.y0 + p.y1) / 2); }
      if (!s) return;
      const ids = ed.sel.kind === 'sector' && ed.sel.ids.has(s.id) ? ed.sel.ids : new Set([s.id]);
      ed.nudgeLight((e.shiftKey ? 1 : 16) * (e.deltaY < 0 ? 1 : -1), ids);
      return;
    }
    const step = (e.shiftKey ? 1 : 8) * (e.deltaY < 0 ? 1 : -1);
    if (h?.kind === 'surface' && h.part !== 'wall') {
      /* THE DOOM BUILDER WHEEL: the floor or ceiling under the mouse
         goes up or down — every selected sector with it, if it is one
         of them. Alt moves the other one of the two. */
      const s = ed.doc.sectors[h.sector];
      const ids = ed.sel.kind === 'sector' && ed.sel.ids.has(s.id) ? ed.sel.ids : new Set([s.id]);
      const part = e.altKey ? (h.part === 'floor' ? 'ceil' : 'floor') : h.part;
      ed.nudgeHeight(part, step, ids);
      ed.say(`${part} ${step > 0 ? '+' : ''}${step} → ${part === 'floor' ? ed.doc.sectors[h.sector].floor : ed.doc.sectors[h.sector].ceil}`);
      return;
    }
    if (h?.kind === 'surface' && h.part === 'wall') {
      /* a wall: the floor behind a lower step, the ceiling otherwise */
      const s = ed.doc.sectors[h.sector];
      ed.nudgeHeight(h.band === 'lower' ? 'floor' : 'ceil', step, new Set([s.id]));
      return;
    }
    if (h?.kind === 'prop') {
      const id = h.id;
      ed.edit(`prop ${step > 0 ? 'up' : 'down'}`, d => { for (const p of d.props) if (p.id === id) { const z = ed.snapZ(p.z0, step); p.z1 += z - p.z0; p.z0 = z; } }, { tidy: false });
      return;
    }
    if (h?.kind === 'thing') { ed.say('things stand on the floor: raise the floor under it, or Ctrl+wheel for its light'); return; }
    /* over nothing: fly forward and back */
    if (this.cam) {
      const f = (e.deltaY < 0 ? 1 : -1) * 64;
      this.cam.x += Math.cos(this.cam.yaw) * Math.cos(this.cam.pitch) * f;
      this.cam.y += Math.sin(this.cam.yaw) * Math.cos(this.cam.pitch) * f;
      this.cam.z += Math.sin(this.cam.pitch) * f;
      ed.emit('camera');
    }
  }

  /** Keys the 3D view takes first. True if it took it. */
  key(e) {
    const c = e.code, ed = this.ed, ctrl = e.ctrlKey || e.metaKey;
    /* the flying keys, while the right button is held; otherwise they
       are the mode keys they are on the plan */
    if (this.looking && ['KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyQ', 'KeyE', 'ShiftLeft', 'ShiftRight'].includes(c)) {
      this.keys.add(c);
      return !c.startsWith('Shift');
    }
    if (this.visual && ['KeyW', 'KeyA', 'KeyS', 'KeyD', 'Space', 'KeyC', 'KeyE', 'ShiftLeft', 'ShiftRight'].includes(c) && !ctrl) {
      this.keys.add(c);
      return !c.startsWith('Shift');
    }
    if (this.visual && e.key === 'Escape') { this.toggleVisual(false); return true; }
    if (c === 'KeyF' && !ctrl) { this.toStart(); return true; }
    if (c === 'KeyH' && !ctrl) { this.showGrid = !this.showGrid; ed.say(`3D grid and axes ${this.showGrid ? 'on' : 'off'}`); return true; }

    const h = this.hover;
    if (ctrl && c === 'KeyC' && h?.kind === 'surface') {
      this.clip = this.textureOf(h);
      ed.say(`copied ${this.clip}`);
      ed.ui.toast(`copied ${this.clip}`);
      return true;
    }
    if (ctrl && c === 'KeyV' && h?.kind === 'surface' && this.clip) {
      const was = ed.surf;
      ed.surf = { sector: h.sector, part: h.part, line: h.line, band: h.band };
      ed.applyTexture(this.clip);
      ed.surf = was;
      ed.say(`pasted ${this.clip}`);
      return true;
    }
    /* DOOM BUILDER'S TEXTURE ALIGNMENT: the arrow keys over a wall move
       its texture — 1 at a time, 8 with Shift */
    const arrows = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    if (arrows[e.key] && h?.kind === 'surface' && h.part === 'wall' && !ctrl) {
      const [dx, dy] = arrows[e.key].map(v => v * (e.shiftKey ? 8 : 1));
      /* on the side being looked at */
      const faceId = ed.doc.sectors[h.sector]?.id;
      ed.edit('texture offset', d => {
        const o = d.lines[h.line] = d.lines[h.line] || {};
        o.sides = o.sides || {};
        const sd = o.sides[faceId] = o.sides[faceId] || {};
        sd.xoff = (sd.xoff ?? o.xoff ?? 0) + dx; sd.yoff = (sd.yoff ?? o.yoff ?? 0) + dy;
      }, { tidy: false, group: `offset ${h.line} ${faceId}` });
      const sd = ed.doc.lines[h.line]?.sides?.[faceId] || {};
      ed.say(`offset ${sd.xoff || 0}, ${sd.yoff || 0} on the side facing sector ${faceId}`);
      return true;
    }

    return false;
  }

  textureOf(h) {
    const d = this.ed.doc, s = d.sectors[h.sector];
    if (h.part === 'floor') return s.floorTex || DEFAULT_FLOOR;
    if (h.part === 'ceil') return s.ceilTex || 'SKY';
    const o = d.lines[h.line] || {};
    /* the side that is being looked at first — see SIDES in doc.js */
    const side = o.sides?.[s.id] || {};
    if (h.band === 'upper') return side.upperTex || o.upperTex || s.upperTex || s.wallTex || 'GRIDWALL';
    if (h.band === 'lower') return side.lowerTex || o.lowerTex || s.lowerTex || s.wallTex || 'GRIDWALL';
    if (side.midTex) return side.midTex;
    /* the middle: of a two-sided line, what stands in its opening (a
       building's outside wall is the inside sector's walls) */
    const two = this.ed.lines().find(l => l.key === h.line)?.sectors.length > 1;
    if (two) {
      if (o.midTex) return o.midTex;
      const l = this.ed.lines().find(q => q.key === h.line);
      const inside = l?.sectors.map(i => d.sectors[i]).find(x => x.ceilTex && x.ceilTex !== 'SKY');
      return inside?.wallTex || s.wallTex || 'GRIDWALL';
    }
    return o.wallTex || s.wallTex || 'GRIDWALL';
  }

  /* ------------------------------------------------------------------
     THE HIGHLIGHTS
     ------------------------------------------------------------------ */
  outline(h) {
    const d = this.ed.doc, out = [];
    const P = (x, y, z) => out.push(x, z, -y);
    if (!h) return out;
    if (h.kind === 'surface' && h.part !== 'wall') {
      const s = d.sectors[h.sector];
      if (!s) return out;
      const r = ringOf(d, s);
      for (let i = 0; i < r.length; i++) {
        const a = r[i], b = r[(i + 1) % r.length];
        P(a[0], a[1], zOf(d, s, h.part, a[0], a[1])); P(b[0], b[1], zOf(d, s, h.part, b[0], b[1]));
      }
    } else if (h.kind === 'surface') {
      const [ai, bi] = h.line.split(',').map(Number);
      const a = d.vertices[ai], b = d.vertices[bi];
      if (!a || !b) return out;
      const l = this.ed.lines().find(q => q.key === h.line);
      const ss = (l?.sectors || []).map(i => d.sectors[i]);
      if (!ss.length) return out;
      const at = (p, part) => ss.map(s => zOf(d, s, part, p[0], p[1]));
      const band = p => {
        const fl = at(p, 'floor'), ce = at(p, 'ceil');
        if (h.band === 'lower') return [Math.min(...fl), Math.max(...fl)];
        if (h.band === 'upper') return [Math.min(...ce), Math.max(...ce)];
        if (ss.length > 1) {
          const top = Math.min(...ce), o = d.lines[h.line] || {}, mh = o.midHeight;
          if (exteriorWall(d, l)) return [Math.max(...fl), top];
          if (mh) return [Math.max(...fl), Math.min(top, Math.max(...fl) + mh)];
          /* a middle is drawn once, its own height (midOnce, js/mapgeo.js) */
          const tex = o.midTex || Object.values(o.sides || {}).find(x => x.midTex)?.midTex;
          const th = tex && this.ed.bank.map.get(tex)?.h;
          return [Math.max(...fl), th ? Math.min(top, Math.max(...fl) + th) : top];
        }
        return [fl[0], ce[0]];
      };
      const [a0, a1] = band(a), [b0, b1] = band(b);
      P(a[0], a[1], a0); P(b[0], b[1], b0); P(b[0], b[1], b0); P(b[0], b[1], b1);
      P(b[0], b[1], b1); P(a[0], a[1], a1); P(a[0], a[1], a1); P(a[0], a[1], a0);
    } else if (h.kind === 'prop') {
      const p = d.props.find(q => q.id === h.id);
      if (p) box(P, p.x0, p.y0, p.z0, p.x1, p.y1, p.z1);
    } else if (h.kind === 'thing') {
      const t = d.things.find(q => q.id === h.id);
      if (t) {
        const def = THING_TYPES[t.type] || { radius: 16 };
        const z = this.thingZ(t), r = def.radius;
        box(P, t.x - r, t.y - r, z, t.x + r, t.y + r, z + thingHeight(t));
      }
    }
    return out;
  }

  drawSel() {
    const ed = this.ed, d = ed.doc, pts = [];
    const { kind, ids } = ed.sel;
    if (ed.surf) pts.push(...this.outline({ kind: 'surface', ...ed.surf }));
    if (kind === 'sector') {
      d.sectors.forEach((s, si) => {
        if (!ids.has(s.id) || (ed.surf && ed.surf.sector === si && ed.surf.part !== 'wall')) return;
        pts.push(...this.outline({ kind: 'surface', part: 'floor', sector: si }));
        /* a sky is not a ceiling anybody wants outlined a thousand units up */
        if (s.outdoor === false) pts.push(...this.outline({ kind: 'surface', part: 'ceil', sector: si }));
      });
    }
    if (kind === 'thing' || kind === 'prop') for (const id of ids) pts.push(...this.outline({ kind, id }));
    if (kind === 'scatter') {
      const P = (x, y, z) => pts.push(x, z + 2, -y), fz = (x, y) => this.floorZ(x, y);
      for (const c of d.scatters) {
        if (!ids.has(c.id)) continue;
        const a = c.area;
        if (a.kind === 'circle') ring(P, a.x, a.y, a.r, fz);
        else if (a.kind === 'rect') {
          const k = [[a.x0, a.y0], [a.x1, a.y0], [a.x1, a.y1], [a.x0, a.y1]];
          for (let i = 0; i < 4; i++) { const p = k[i], q = k[(i + 1) % 4]; P(p[0], p[1], fz(p[0], p[1])); P(q[0], q[1], fz(q[0], q[1])); }
        } else d.sectors.forEach((s, si) => { if ((a.ids || []).includes(s.id)) pts.push(...this.outline({ kind: 'surface', part: 'floor', sector: si })); });
      }
    }
    if (kind === 'line' && !ed.surf) {
      for (const k of ids) {
        const l = ed.lines().find(q => q.key === k);
        if (l) pts.push(...this.outline({ kind: 'surface', part: 'wall', band: l.sectors.length > 1 ? 'lower' : 'middle', line: k, sector: l.sectors[0] }));
      }
    }
    setLines(this.selLines, pts);
  }
  drawHover() { setLines(this.hovLines, this.outline(this.hover)); }

  /** What is half-done, and what only a mode shows: the outline being
   *  drawn, the snapped cursor, a rectangle, box or circle being dragged
   *  out, every scatter's area, and the vertex handles. */
  drawOverlay() {
    this.overlayDirty = false;
    const ed = this.ed, d = ed.doc, pts = [], area = [];
    const P = (x, y, z) => pts.push(x, z + 1, -y);
    const fz = (x, y) => this.floorZ(x, y);
    const seg = (a, b) => { P(a[0], a[1], fz(a[0], a[1])); P(b[0], b[1], fz(b[0], b[1])); };
    /* the outline, from whichever view it is being drawn in */
    const path = [...ed.path];
    if (ed.mode === 'draw' && ed.cursor && this.mouse) path.push(ed.cursor);
    for (let i = 0; i + 1 < path.length; i++) seg(path[i], path[i + 1]);
    for (const p of ed.path) cross(P, p[0], p[1], fz(p[0], p[1]), 8);
    /* the cursor, in the modes that put something down */
    if (ed.cursor && this.mouse && ['draw', 'rect', 'things', 'props', 'scatter'].includes(ed.mode) && !this.drag) {
      cross(P, ed.cursor[0], ed.cursor[1], fz(ed.cursor[0], ed.cursor[1]), 16);
    }
    const dr = this.drag;
    if (dr && (dr.type === 'rect' || dr.type === 'prop')) {
      /* the shape being dragged out, or a prop's box */
      const c = dr.type === 'rect' && (dr.b[0] !== dr.a[0] || dr.b[1] !== dr.a[1]) ? ed.shapePoints(dr.a, dr.b)
        : [[dr.a[0], dr.a[1]], [dr.b[0], dr.a[1]], [dr.b[0], dr.b[1]], [dr.a[0], dr.b[1]]];
      for (let i = 0; i < c.length; i++) seg(c[i], c[(i + 1) % c.length]);
      if (dr.type === 'prop') for (const p of c) { const z = fz(p[0], p[1]); P(p[0], p[1], z); P(p[0], p[1], z + 64); }
    }
    if (dr?.type === 'brush') ring(P, dr.a[0], dr.a[1], Math.hypot(dr.b[0] - dr.a[0], dr.b[1] - dr.a[1]), fz);
    setLines(this.drawLines, pts);

    /* the scatters' areas, on the floor */
    const AP = (x, y, z) => area.push(x, z + 2, -y);
    for (const c of d.scatters || []) {
      const a = c.area;
      if (ed.isSel('scatter', c.id)) continue;          // drawn with the selection
      if (a.kind === 'circle') ring(AP, a.x, a.y, a.r, fz);
      else if (a.kind === 'rect') {
        const k = [[a.x0, a.y0], [a.x1, a.y0], [a.x1, a.y1], [a.x0, a.y1]];
        for (let i = 0; i < 4; i++) { const p = k[i], q = k[(i + 1) % 4]; AP(p[0], p[1], fz(p[0], p[1])); AP(q[0], q[1], fz(q[0], q[1])); }
      }
    }
    setLines(this.areaLines, area);

    /* the handles */
    const hp = [], hc = [];
    if (ed.mode === 'vertices' || ed.mode === 'draw') {
      const col = new THREE.Color();
      d.vertices.forEach((v, i) => {
        hp.push(v[0], fz(v[0], v[1]) + 1, -v[1]);
        col.set(ed.isSel('vertex', i) ? 0xff9d3d : 0xd8e0e4);
        hc.push(col.r, col.g, col.b);
      });
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(hp, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(hc, 3));
    this.handles.geometry.dispose();
    this.handles.geometry = g;
    this.handles.visible = hp.length > 0;
  }

  /** The grid and the axes, every frame: the grid on the ground at 0 —
   *  or, while drawing, on the floor under the cursor — at the plan's
   *  grid size, sized to reach the horizon from wherever the camera is,
   *  and the gizmo turned to match the camera. */
  placeGrid() {
    const ed = this.ed, g = this.grid, c = this.cam;
    const on = this.showGrid;
    g.visible = this.axes.visible = on;
    this.gizmo.style.display = on ? '' : 'none';
    if (!on) return;
    const drawing = GRID_MODES.includes(ed.mode) && !this.visual;
    const at = drawing && ed.cursor && this.mouse ? ed.cursor : null;
    let z = 0;
    if (drawing) z = this.drag?.a ? this.floorZ(this.drag.a[0], this.drag.a[1]) : at ? this.floorZ(at[0], at[1]) : this.floorZ(c.x, c.y);
    const step = Math.max(1, ed.grid || 64);
    const up = Math.max(64, Math.abs(c.z - z));
    const R = Math.max(8192, Math.min(60000, up * 60 + step * 96));
    g.position.set(c.x, z + 0.75, -c.y);
    g.scale.set(R, 1, R);
    const u = g.material.uniforms;
    u.step.value = step;
    u.major.value = step * (step >= 256 ? 4 : 8);
    /* it fades round the cursor while drawing, round the camera
       otherwise — further the higher it is, as Blender's does */
    if (at) { u.focus.value.set(at[0], -at[1]); u.reach.value = Math.max(step * 48, 1536, up * 12); }
    else { u.focus.value.set(c.x, -c.y); u.reach.value = Math.max(step * 64, 4096, up * 30); }
    this.drawGizmo();
  }

  /** THE GIZMO: X, Y and Z as the camera sees them, the ones pointing
   *  away drawn first and dimmer. */
  drawGizmo() {
    const cv = this.gizmo, g = cv.getContext('2d');
    if (!g) return;
    const k = cv.width / GIZMO, r = GIZMO / 2, L = r - 13;
    g.setTransform(k, 0, 0, k, 0, 0);
    g.clearRect(0, 0, GIZMO, GIZMO);
    g.fillStyle = 'rgba(12,16,20,0.55)';
    g.beginPath(); g.arc(r, r, r - 1, 0, Math.PI * 2); g.fill();
    const inv = this.camera.matrixWorldInverse.elements;
    /* a map direction (x east, y north, z up) in the camera's frame */
    const view = (x, y, z) => {
      const X = x, Y = z, Z = -y;                 // map to the renderer's axes
      return [inv[0] * X + inv[4] * Y + inv[8] * Z, inv[1] * X + inv[5] * Y + inv[9] * Z, inv[2] * X + inv[6] * Y + inv[10] * Z];
    };
    const ends = [];
    for (const [name, col, v] of AXES) {
      for (const sgn of [1, -1]) {
        const [vx, vy, vz] = view(v[0] * sgn, v[1] * sgn, v[2] * sgn);
        ends.push({ name, col, sgn, x: r + vx * L, y: r - vy * L, depth: vz });
      }
    }
    ends.sort((a, b) => a.depth - b.depth);
    g.font = 'bold 10px ui-monospace, monospace'; g.textAlign = 'center'; g.textBaseline = 'middle';
    for (const e of ends) {
      if (e.sgn > 0) {
        g.strokeStyle = e.col; g.lineWidth = 2;
        g.beginPath(); g.moveTo(r, r); g.lineTo(e.x, e.y); g.stroke();
        g.fillStyle = e.col;
        g.beginPath(); g.arc(e.x, e.y, 8, 0, Math.PI * 2); g.fill();
        g.fillStyle = '#0b0e11'; g.fillText(e.name, e.x, e.y + 0.5);
      } else {
        g.fillStyle = e.col; g.globalAlpha = 0.45;
        g.beginPath(); g.arc(e.x, e.y, 6, 0, Math.PI * 2); g.fill();
        g.globalAlpha = 1;
      }
    }
  }

  /* ------------------------------------------------------------------
     EVERY FRAME
     ------------------------------------------------------------------ */
  frame(dt) {
    if (!this.cam) return;
    const c = this.cam, k = this.keys;
    if (this.looking || this.visual) {
      const sp = FLY * (k.has('ShiftLeft') || k.has('ShiftRight') ? 3.5 : 1) * dt;
      const fx = Math.cos(c.yaw), fy = Math.sin(c.yaw);
      let mx = 0, my = 0, mz = 0;
      if (k.has('KeyW')) { mx += fx * Math.cos(c.pitch); my += fy * Math.cos(c.pitch); mz += Math.sin(c.pitch); }
      if (k.has('KeyS')) { mx -= fx * Math.cos(c.pitch); my -= fy * Math.cos(c.pitch); mz -= Math.sin(c.pitch); }
      if (k.has('KeyA')) { mx -= fy; my += fx; }
      if (k.has('KeyD')) { mx += fy; my -= fx; }
      if (k.has('KeyE') || k.has('Space')) mz += 1;
      if (k.has('KeyQ') || k.has('KeyC')) mz -= 1;
      if (mx || my || mz) { c.x += mx * sp; c.y += my * sp; c.z += mz * sp; this.ed.emit('camera'); this.hoverDirty = true; }
    }
    this.camera.position.set(c.x, c.z, -c.y);
    this.camera.rotation.set(c.pitch, c.yaw - Math.PI / 2, 0, 'YXZ');
    this.camera.updateMatrixWorld();
    world.eyePos.value.set(c.x, c.z, -c.y);
    followSky(this.sky, this.camera);

    if (this.hoverDirty && this.mouse && !this.looking && !this.drag) {
      this.hoverDirty = false;
      const R = this.ray(this.mouse[0], this.mouse[1]);
      this.hover = this.pick(R);
      this.drawHover();
      const hv = this.hover;
      this.ed.setHover(!hv ? null : hv.kind === 'thing' || hv.kind === 'prop' ? { kind: hv.kind, id: hv.id }
        : hv.part === 'wall' ? { kind: 'line', id: hv.line, part: 'wall', band: hv.band }
        : { kind: 'sector', id: this.ed.doc.sectors[hv.sector]?.id, part: hv.part });
      /* and the cursor on the map, for both views */
      const sg = this.snapGround(this.ground(R, this.hover), this.mouse[0], this.mouse[1]);
      if (sg) { this.ed.setCursor(sg); this.ed.ui.setPos(sg[0], sg[1]); }
    }
    if (this.overlayDirty || this.ed.mode === 'vertices') this.drawOverlay();
    this.placeGrid();
    this.renderer.render(this.scene, this.camera);
  }
}

/* ---------------------------------------------------------------------
   helpers
   --------------------------------------------------------------------- */

/* BLENDER'S AXIS COLOURS: X red, Y green, Z blue */
export const AXIS_X = 0xff3352, AXIS_Y = 0x8bdc00, AXIS_Z = 0x4aa8ff;
const AXES = [['X', '#ff3352', [1, 0, 0]], ['Y', '#8bdc00', [0, 1, 0]], ['Z', '#4aa8ff', [0, 0, 1]]];
const GIZMO = 84;            // the gizmo's size, in CSS pixels
const AXIS_LEN = 60000;

/** THE THREE AXES through 0,0,0, as lines — X along the map's y = 0,
 *  Y along its x = 0, Z straight up — with the origin marked: what the
 *  grid's own axis lines are on the ground, standing in the air too, so
 *  they show whatever height the ground is. */
function buildAxes() {
  const grp = new THREE.Group();
  const line = (col, a, b, opacity) => {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute([...a, ...b], 3));
    const l = new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color: col, transparent: true, opacity }));
    l.frustumCulled = false;
    return l;
  };
  /* map (x, y, z) is the renderer's (x, z, -y); a lift keeps them off
     a floor at 0 */
  grp.add(line(AXIS_X, [-AXIS_LEN, 1, 0], [AXIS_LEN, 1, 0], 0.9));
  grp.add(line(AXIS_Y, [0, 1, AXIS_LEN], [0, 1, -AXIS_LEN], 0.9));
  grp.add(line(AXIS_Z, [0, -AXIS_LEN, 0], [0, AXIS_LEN, 0], 1));
  /* the origin: a dot, seen through anything, so you can always find
     your way back to it */
  const dot = new THREE.BufferGeometry();
  dot.setAttribute('position', new THREE.Float32BufferAttribute([0, 1, 0], 3));
  const o = new THREE.Points(dot, new THREE.PointsMaterial({ color: 0xffffff, size: 9, sizeAttenuation: false, depthTest: false, transparent: true }));
  o.renderOrder = 1004;
  o.frustumCulled = false;
  grp.add(o);
  grp.name = 'axes';
  return grp;
}

/** The modes in which the grid comes up to the floor being drawn on. */
export const GRID_MODES = ['draw', 'rect', 'vertices', 'things', 'props', 'scatter'];

/** THE DRAWING GRID: one square, scaled round the camera, whose shader
 *  draws the lines — fine ones every grid step, bright ones every eight,
 *  the map's axes brightest — sharp at any distance (their width is in
 *  pixels, from the derivatives), and fading out away from the cursor so
 *  the far floor is still the floor. */
function buildGrid() {
  const geo = new THREE.PlaneGeometry(2, 2);
  geo.rotateX(-Math.PI / 2);
  const mat = new THREE.ShaderMaterial({
    uniforms: {
      step: { value: 64 }, major: { value: 512 },
      focus: { value: new THREE.Vector2() }, reach: { value: 3072 },
      minor: { value: new THREE.Color(0x9fe8ff) }, majorCol: { value: new THREE.Color(0xffffff) },
      xAxis: { value: new THREE.Color(AXIS_X) }, yAxis: { value: new THREE.Color(AXIS_Y) },
    },
    vertexShader: `
      varying vec2 vP;
      void main() {
        vec4 w = modelMatrix * vec4(position, 1.0);
        vP = w.xz;
        gl_Position = projectionMatrix * viewMatrix * w;
      }`,
    fragmentShader: `
      uniform float step, major, reach;
      uniform vec2 focus;
      uniform vec3 minor, majorCol, xAxis, yAxis;
      varying vec2 vP;
      float lines(vec2 p, float s, float px) {
        vec2 g = abs(fract(p / s - 0.5) - 0.5) * s / max(fwidth(p), vec2(1e-4));
        return 1.0 - clamp(min(g.x, g.y) - (px - 1.0), 0.0, 1.0);
      }
      void main() {
        /* too fine to see where it is: let it go rather than shimmer */
        float fine = 1.0 - smoothstep(0.25, 0.6, length(fwidth(vP)) / step);
        float a1 = lines(vP, step, 1.0) * fine;
        float a2 = lines(vP, major, 1.5);
        /* the axes through the origin: X (the map's y = 0) red, Y (its
           x = 0) green, two pixels wide and never faded quite out */
        vec2 ax = abs(vP) / max(fwidth(vP), vec2(1e-4));
        float onX = 1.0 - clamp(ax.y - 1.5, 0.0, 1.0);
        float onY = 1.0 - clamp(ax.x - 1.5, 0.0, 1.0);
        float fade = 1.0 - smoothstep(reach * 0.35, reach, distance(vP, focus));
        vec3 c = minor; float a = a1 * 0.38;
        if (a2 > 0.0) { c = mix(c, majorCol, a2); a = max(a, a2 * 0.7); }
        a *= fade;
        float axFade = max(fade, 0.55);
        if (onX > 0.0) { c = mix(c, xAxis, onX); a = max(a, onX * 0.95 * axFade); }
        if (onY > 0.0) { c = mix(c, yAxis, onY); a = max(a, onY * 0.95 * axFade); }
        if (a < 0.01) discard;
        gl_FragColor = vec4(c, a);
      }`,
    transparent: true, depthWrite: false,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  });
  const m = new THREE.Mesh(geo, mat);
  m.renderOrder = 998;
  m.frustumCulled = false;
  m.visible = false;
  return m;
}

/** A document sector's floor or ceiling height at (x, y). Flat while
 *  slopes are switched off (FEATURES in js/editor/doc.js). */
export function zOf(d, s, part, x, y) {
  const z0 = part === 'floor' ? (s.floor ?? 0) : (s.ceil ?? 256);
  if (!FEATURES.slopes) return z0;
  const sl = part === 'floor' ? s.floorSlope : s.ceilSlope;
  if (!sl || (!sl.dzdx && !sl.dzdy)) return z0;
  const [cx, cy] = centroid(ringOf(d, s));
  return z0 + (sl.dzdx || 0) * (x - cx) + (sl.dzdy || 0) * (y - cy);
}

/** How tall a thing stands, for its post and for picking it. */
export function thingHeight(t) {
  if (t.type === 'START') return 56;
  if (t.type === 'PLANT') { const k = plantKind(t.kind); return (k ? k.h : 60) * (t.scale ?? 1); }
  if (PEOPLE.has(t.type)) return PERSON_H * (t.scale ?? 1);
  return (THING_TYPES[t.type]?.radius || 16) * 2.6;
}

/* A BILLBOARD that turns about the vertical, the way the game's sprites
   do: the quad is laid along the camera's own right-hand direction,
   flattened onto the ground, so a tree leans no matter how far you
   look down. The picture's alpha is cut, not blended, so ten thousand
   of them need no sorting. */
function billboardMaterial(map, tint) {
  /* LIT AND FOGGED BY THE SECTOR IT STANDS IN, at the user's request, as
     the game's own sprites are: the sector grid (js/sectorgrid.js) read
     at the foot, and the game's world shading — so a plant in a dark
     red room is dark and red, and one in a fogged sector fades into it */
  return new THREE.ShaderMaterial({
    uniforms: { map: { value: map }, markTint: { value: tint }, ...worldUniforms() },
    vertexShader: /* glsl */`
      varying vec2 vUv;
      varying vec3 vWorld;
      varying float vDepth;
      varying vec4 vSecLight;
      varying vec4 vFog;
      ${SECTOR_GRID_GLSL}
      void main() {
        vUv = uv;
        vec3 base = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        vSecLight = vec4(1.0);
        vFog = vec4(0.0, 0.0, 0.0, -1.0);
        if (sectorOn > 0.5) { vSecLight = sectorLightAt(base); vFog = sectorFogAt(base); }
        float sx = length(instanceMatrix[0].xyz), sy = length(instanceMatrix[1].xyz);
        vec3 right = normalize(vec3(viewMatrix[0][0], 0.0, viewMatrix[2][0]) + vec3(1e-5, 0.0, 0.0));
        vec3 p = base + right * position.x * sx + vec3(0.0, position.y * sy, 0.0);
        vWorld = p;
        vec4 mv = viewMatrix * vec4(p, 1.0);
        vDepth = -mv.z;
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: /* glsl */`
      uniform sampler2D map;
      uniform vec3 markTint;        // a person's type colour; white for a plant
      ${WORLD_UNIFORMS_GLSL}
      varying vec2 vUv;
      varying vec3 vWorld;
      varying float vDepth;
      varying vec4 vSecLight;
      #define SECTOR_FOG
      varying vec4 vFog;
      ${WORLD_SHADE_GLSL}
      void main() {
        vec4 c = texture2D(map, vUv);
        if (c.a < 0.5) discard;
        float l = worldBand(vSecLight.a, vDepth, 0.0, 0.0);
        gl_FragColor = vec4(worldShade(c.rgb * markTint * vSecLight.rgb, l, vDepth, vWorld, 0.0), 1.0);
      }`,
    side: THREE.DoubleSide,
  });
}

/* A FIGURE for the people: a head and shoulders and legs in white, which
   the billboard tints to the type's own colour. The game's people are
   photographs the editor does not load; a figure the right size in the
   right place is what placing them needs. */
function personTexture() {
  const c = document.createElement('canvas');
  c.width = 32; c.height = 64;
  const g = c.getContext('2d');
  g.fillStyle = '#fff';
  g.beginPath(); g.arc(16, 9, 6, 0, Math.PI * 2); g.fill();           // head
  g.fillRect(8, 16, 16, 24);                                           // body
  g.fillRect(4, 18, 4, 18); g.fillRect(24, 18, 4, 18);                // arms
  g.fillRect(9, 40, 6, 24); g.fillRect(17, 40, 6, 24);                // legs
  g.fillStyle = '#0006'; g.fillRect(8, 36, 16, 4);                    // a belt, for shape
  const t = new THREE.CanvasTexture(c);
  t.magFilter = THREE.NearestFilter; t.minFilter = THREE.NearestFilter; t.generateMipmaps = false;
  return t;
}

/** A ray against an axis-aligned box: the distance in, or null. */
function slab(R, bx, by, bz) {
  let t0 = 0, t1 = Infinity;
  for (const [o, dv, [lo, hi]] of [[R.ox, R.dx, bx], [R.oy, R.dy, by], [R.oz, R.dz, bz]]) {
    if (Math.abs(dv) < 1e-12) { if (o < lo || o > hi) return null; continue; }
    let a = (lo - o) / dv, b = (hi - o) / dv;
    if (a > b) [a, b] = [b, a];
    t0 = Math.max(t0, a); t1 = Math.min(t1, b);
    if (t0 > t1) return null;
  }
  return t0 > 0 ? t0 : null;
}

function box(P, x0, y0, z0, x1, y1, z1) {
  const c = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]];
  for (let i = 0; i < 4; i++) {
    const a = c[i], b = c[(i + 1) % 4];
    P(a[0], a[1], z0); P(b[0], b[1], z0);
    P(a[0], a[1], z1); P(b[0], b[1], z1);
    P(a[0], a[1], z0); P(a[0], a[1], z1);
  }
}

function cross(P, x, y, z, s) {
  P(x - s, y, z); P(x + s, y, z);
  P(x, y - s, z); P(x, y + s, z);
  P(x, y, z); P(x, y, z + s * 1.5);
}

function ring(P, x, y, r, fz) {
  const n = Math.max(24, Math.min(96, Math.round(r / 24)));
  for (let i = 0; i < n; i++) {
    const a0 = i / n * Math.PI * 2, a1 = (i + 1) / n * Math.PI * 2;
    const p = [x + Math.cos(a0) * r, y + Math.sin(a0) * r], q = [x + Math.cos(a1) * r, y + Math.sin(a1) * r];
    P(p[0], p[1], fz(p[0], p[1])); P(q[0], q[1], fz(q[0], q[1]));
  }
}

function setLines(obj, pts) {
  obj.geometry.dispose();
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  obj.geometry = g;
  obj.visible = pts.length > 0;
}

/** Throw away what a rebuild replaced — geometry and the materials made
 *  for it, never the bank's textures or the plant pictures, which are
 *  kept and shared. */
function disposeTree(root) {
  root.traverse(o => {
    o.geometry?.dispose?.();
    const m = o.material;
    if (Array.isArray(m)) m.forEach(x => x.dispose?.()); else m?.dispose?.();
  });
}

/** Whether a two-sided line is a building's outside wall: an inside
 *  sector on one side, the outside on the other, and not a doorway —
 *  the rule the compiler walls it by (5c in js/editor/doc.js). */
export function exteriorWall(d, l) {
  if (!l || l.sectors.length !== 2 || d.lines[l.key]?.opening) return false;
  const [a, b] = l.sectors.map(i => d.sectors[i]);
  return (a.ceilTex !== 'SKY') !== (b.ceilTex !== 'SKY');
}
/** Or anything else standing in the opening: a middle texture. */
function midWall(d, l) { return exteriorWall(d, l) || !!d.lines[l.key]?.midTex; }
