/* =====================================================================
   DEWM — the title's own level: a forest that goes by for ever

   At the user's request the title no longer stands on the map the game
   is about to play. It has a world of its own behind it: a forest seen
   from the side, sliding past from right to left and never running
   out, with grass close enough to the eye to fill the bottom of the
   glass.

   IT IS SIX ROWS OF CUTOUTS AT SIX DEPTHS, and the depth is all of the
   parallax: the eye is a real perspective camera moving along x, so a
   row twice as far away goes by half as fast without anything being
   told to. Far to near:

     far       fir and pine, tall, close-packed, faded into the air
     middle    pines and broad trees
     near      the trees you could walk up to, well spaced
     scrub     bushes and ferns along the foot of the near trees
     meadow    short grass and flowers between the scrub and the eye
     grass     right under the eye, big, swaying

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
const SPEED = 3.2;                     // units a second, the eye going right
const EYE_Y = 2.6;
const FOV = 50;

/* the rows: depth, how wide the ring is, how many in it, what grows
   there and how tall, and its TINT, which is the air: the game swaps
   three's fog out for its own sector fog (js/material.js), which knows
   nothing of this scene, so the fog is off here and each row is
   coloured for how much air it stands behind — the far ones blue. */
const ROWS = [
  { name: 'far', z: -150, wrap: 420, n: 110, h: [16, 26], tint: [0.42, 0.52, 0.66], sway: 0,
    kinds: ['pine_fir_tree_1', 'pine_fir_tree_2', 'pine_fir_tree_3', 'pine_fir_tree_4',
            'fir_tall_1', 'fir_tall_2', 'fir_medium', 'pine_barrens_tree'] },
  { name: 'middle', z: -80, wrap: 230, n: 46, h: [12, 19], tint: [0.62, 0.70, 0.78], sway: 0,
    kinds: ['pine_fir_tree_1', 'pine_fir_tree_3', 'fir_tall_1', 'fir_medium',
            'new_meadow_tree_1', 'new_meadow_tree_2', 'meadow_tree_medium', 'pine_barrens_tree'] },
  { name: 'near', z: -38, wrap: 120, n: 13, h: [10, 15], tint: [0.9, 0.92, 0.9], sway: 0,
    kinds: ['new_meadow_tree_1', 'new_meadow_tree_2', 'new_meadow_tree_3', 'meadow_tree_really_big',
            'pine_fir_tree_2', 'pine_fir_tree_4', 'fir_tall_2', 'meadow_tree_big'] },
  { name: 'scrub', z: -20, wrap: 68, n: 24, h: [1.6, 3.2], tint: [0.95, 0.95, 0.9], sway: 0.03,
    kinds: ['new_meadow_bush_1', 'new_meadow_bush_2', 'new_meadow_bush_3', 'pine_fern_1', 'pine_fern_2',
            'pine_forest_bush_1', 'pine_forest_bush_2', 'new_meadow_fern_1', 'new_meadow_fern_3',
            'tundra_bush_2', 'bush_small_1', 'pine_juvenile_fir_tree_1'] },
  { name: 'meadow', z: -11, wrap: 36, n: 44, h: [0.8, 1.6], tint: [1.0, 1.05, 0.95], sway: 0.05,
    kinds: ['meadow_grass_var_a', 'meadow_grass_var_b', 'new_meadow_grass_1', 'new_meadow_grass_2',
            'grass', 'savanna_grass_short_2', 'new_meadow_fern_2', 'new_meadow_flower_2'] },
  { name: 'grass', z: -5.5, wrap: 22, n: 46, h: [1.1, 2.1], tint: [1.25, 1.3, 1.1], sway: 0.07,
    kinds: ['meadow_grass_var_a', 'meadow_grass_var_b', 'new_meadow_grass_1', 'new_meadow_grass_2',
            'new_meadow_grass_tall_1', 'grass', 'savanna_grass_short_1', 'new_meadow_flower_1',
            'meadow_grass_var_a', 'meadow_grass_var_b'] },
];

/* a small seeded generator, so the forest is the same forest each time
   the page opens and differs only as far as it has been walked */
function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return (s >>> 0) / 4294967296; };
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
    this.geo = new THREE.PlaneGeometry(1, 1);
    this.geo.translate(0, 0.5, 0);
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
    const ground = await get(DIR + 'ground.png').catch(() => null);
    this._build(sky, ground);
    this.ready = true;
    return this;
  }

  _material(kind, tint) {
    const key = kind + tint;
    let m = this.materials.get(key);
    if (!m) {
      m = new THREE.MeshBasicMaterial({ map: this.textures.get(kind), alphaTest: 0.5, side: THREE.DoubleSide, fog: false });
      m.color.setRGB(...tint);
      this.materials.set(key, m);
    }
    return m;
  }

  _build(sky, ground) {
    const s = this.scene;
    /* behind it all, the colour the sky has at the horizon */
    s.background = new THREE.Color(0x2c4c72);

    /* THE SKY, the top half of BSKY1 on a plane that rides with the
       eye; its own drift is a slow slide of the picture */
    if (sky) {
      sky.colorSpace = THREE.SRGBColorSpace;
      sky.wrapS = THREE.RepeatWrapping;
      sky.repeat.set(0.5, 0.5);
      sky.offset.set(0, 0.5);
      this.skyTex = sky;
      const m = new THREE.MeshBasicMaterial({ map: sky, fog: false, depthWrite: false });
      this.sky = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), m);
      this.sky.renderOrder = -1;
      s.add(this.sky);
    }

    /* THE GROUND, a strip that rides with the eye and slides its
       texture the other way, which is the same as standing still */
    const g = new THREE.MeshBasicMaterial({ color: 0x5a6a3a, fog: false });
    if (ground) {
      ground.colorSpace = THREE.SRGBColorSpace;
      ground.wrapS = ground.wrapT = THREE.RepeatWrapping;
      ground.repeat.set(600 / 6, 300 / 6);
      g.map = ground; g.color.setRGB(0.34, 0.36, 0.28);
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

    for (const def of ROWS) {
      const row = { def, items: [] };
      const step = def.wrap / def.n;
      for (let i = 0; i < def.n; i++) {
        const m = new THREE.Mesh(this.geo, this._material(def.kinds[0], def.tint));
        const it = { mesh: m, x: -def.wrap / 2 + (i + this.rand()) * step, phase: this.rand() * 6.28 };
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
    it.mesh.material = this._material(kind, d.tint);
    it.mesh.scale.set(h * aspect * (r() < 0.5 ? -1 : 1), h, 1);
    it.z = d.z + (r() - 0.5) * Math.abs(d.z) * 0.12;
    /* the grass stands a little below the ground line, so its roots are
       never a hard edge along the bottom */
    it.y = row.def.sway >= 0.05 ? -0.25 - r() * 0.3 : -0.05;
  }

  /** One frame: the eye moves on, and what has gone by comes round. */
  update(dt, aspect, now = performance.now()) {
    if (!this.ready) return;
    this.x += SPEED * Math.min(dt, 0.1);
    const cam = this.camera;
    if (Math.abs(cam.aspect - aspect) > 1e-4) { cam.aspect = aspect; cam.updateProjectionMatrix(); }
    cam.position.x = this.x;
    const t = now / 1000;
    for (const row of this.rows) {
      const w = row.def.wrap, lo = this.x - w / 2;
      for (const it of row.items) {
        if (it.x < lo) { it.x += w; this._dress(row, it); }
        it.mesh.position.set(it.x, it.y, it.z);
        if (row.def.sway) it.mesh.rotation.z = row.def.sway * (Math.sin(t * 1.3 + it.phase) + 0.4 * Math.sin(t * 3.1 + it.phase * 2));
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
    if (this.groundTex) this.groundTex.offset.x = (this.x / 6) % 1;
  }

  dispose() {
    this.scene.traverse(o => { if (o.material) o.material.dispose?.(); });
    for (const t of this.textures.values()) t.dispose();
    this.skyTex?.dispose(); this.groundTex?.dispose();
    this.geo.dispose();
  }
}
