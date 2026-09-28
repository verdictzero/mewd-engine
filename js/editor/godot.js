/* =====================================================================
   MEWD Editor — the world, as a Godot scene
   =====================================================================

   At the user's request: the map exported for Godot 4, as a folder you
   drop into a Godot project and open. File > Export Godot scene hands
   over a zip that unpacks into one folder:

     <name>.tscn      the scene: open this in Godot
     world.glb        every surface of the level as glTF 2.0, with its
                      texture, UV-mapped the way the game maps it, and
                      the textures packed inside it
     textures/*.png   the same textures on their own, for reuse
     sprites/*.png    the pictures the billboards use
     README.txt       what is what, and the numbers it was made with

   THE GEOMETRY IS THE GAME'S. It is js/mapgeo.js's own build of the
   level — the same triangles the 3D view and the game draw — so the
   floors, the walls, the steps, the middles in the openings, the roofs
   and the props all go, each batch as one glTF primitive wearing its
   texture. The UVs are the game's with v turned over, because three.js
   flips its pictures on the way to the GPU and glTF does not.

   THE LIGHT IS BAKED IN, by default. The game has no lights: a sector's
   brightness, and its Doom 64 colours, are a number per corner. Those
   go out as the glTF vertex colour, and the materials say
   KHR_materials_unlit, which Godot imports as unshaded — so the scene
   looks as the map does before a single light is placed. Untick it and
   the colours stay out and the materials are ordinary lit ones, for a
   project that wants Godot to do the lighting.

   COLLISION: the mesh is named with Godot's "-col" suffix, so the
   importer makes a static body with a trimesh shape from it — the
   level is walkable in Godot with no setup. The billboards that stop
   you in the game (trees, bushes, solid decor) each get a StaticBody3D
   with an automatic box: the bounds of what the game collides with.

   THE STATIC SPRITES — the trees, the bushes, the grass, the street
   trees, placed or scattered — become Sprite3D nodes, billboarded about
   the vertical as the game draws them, cut out, point sampled, and
   standing on the floor at their own size. THE THINGS that are actors
   in the game (the people, the crates, the start) become Marker3D nodes
   with their type, variant and facing as metadata, for a Godot project
   to put its own scenes on.

   THE SCALE. Doom's units are small: a person is about 56 of them. So
   the scene is written at 32 units to the metre (a setting), with Godot's
   Y up and its -Z forward, which are the renderer's own axes here.

   Everything that builds a file is pure — geometry and bytes in, bytes
   out — so the smoke test builds a GLB headless and reads it back.
   ===================================================================== */

import { plantKind } from './scatter.js';
import { THING_TYPES } from './doc.js';
import { animOf, loadPack, SKIES } from '../texpack.js';

export const UNITS_PER_METRE = 32;
/** The things that are STATIC DECOR: a billboard of the game's own
 *  picture in the export, not a marker. The street lamp and the ceiling
 *  lamp are geometry and light in the game, and stay markers. */
export const DECOR_TYPES = ['TROLLEY', 'BOLLARD', 'CRATE', 'FUELCAN', 'GRAVESTONE'];

/* glTF numbers */
const FLOAT = 5126, ARRAY_BUFFER = 34962, TRIANGLES = 4;
const NEAREST = 9728, LINEAR = 9729, NEAREST_MIPMAP_NEAREST = 9984, LINEAR_MIPMAP_LINEAR = 9987, REPEAT = 10497;

/**
 * Every triangle of a built level, gathered by texture.
 * @param group  the `group` js/mapgeo.js's buildLevelGeometry returned
 * @returns Map(texture name -> { pos: [], uv: [], light: [], tint: [] })
 */
export function gatherSurfaces(group) {
  const out = new Map();
  const walk = o => {
    const g = o.geometry, A = g?.attributes;
    if (A?.position && A.uv && o.name) {
      const name = o.name.split('|').pop();
      let s = out.get(name);
      if (!s) out.set(name, s = { pos: [], uv: [], light: [], tint: [] });
      const n = A.position.array.length / 3;
      for (let i = 0; i < n; i++) {
        s.pos.push(A.position.array[i * 3], A.position.array[i * 3 + 1], A.position.array[i * 3 + 2]);
        s.uv.push(A.uv.array[i * 2], A.uv.array[i * 2 + 1]);
        s.light.push(A.light ? A.light.array[i] : 1);
        const t = A.tintRGB?.array;
        s.tint.push(t ? t[i * 3] : 1, t ? t[i * 3 + 1] : 1, t ? t[i * 3 + 2] : 1);
      }
    }
    for (const c of o.children || []) walk(c);
  };
  walk(group);
  for (const [k, s] of out) if (!s.pos.length) out.delete(k);
  return out;
}

/**
 * A GLB of the surfaces.
 * @param surfaces  from gatherSurfaces
 * @param images    Map(texture name -> { png: Uint8Array, masked, smooth })
 * @param opts      { scale (world units to metres), bake, collision, name }
 * @returns Uint8Array
 */
export function buildGLB(surfaces, images, opts = {}) {
  const k = opts.scale ?? 1 / UNITS_PER_METRE;
  const bake = opts.bake !== false;
  const chunks = [];
  let length = 0;
  const bufferViews = [], accessors = [];
  const put = (bytes, target) => {
    const pad = (4 - (length % 4)) % 4;
    if (pad) { chunks.push(new Uint8Array(pad)); length += pad; }
    bufferViews.push({ buffer: 0, byteOffset: length, byteLength: bytes.byteLength, ...(target ? { target } : {}) });
    chunks.push(bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength));
    length += bytes.byteLength;
    return bufferViews.length - 1;
  };
  const accessor = (arr, type, n, minmax = false) => {
    const view = put(arr, ARRAY_BUFFER);
    const a = { bufferView: view, componentType: FLOAT, count: n, type };
    if (minmax) {
      const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
      for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) { const v = arr[i * 3 + c]; if (v < min[c]) min[c] = v; if (v > max[c]) max[c] = v; }
      a.min = min; a.max = max;
    }
    accessors.push(a);
    return accessors.length - 1;
  };

  const gltf = {
    asset: { version: '2.0', generator: 'MEWD Editor' },
    scene: 0, scenes: [{ name: opts.name || 'World', nodes: [0] }],
    nodes: [], meshes: [], materials: [], textures: [], images: [], samplers: [
      { magFilter: NEAREST, minFilter: NEAREST_MIPMAP_NEAREST, wrapS: REPEAT, wrapT: REPEAT },
      { magFilter: LINEAR, minFilter: LINEAR_MIPMAP_LINEAR, wrapS: REPEAT, wrapT: REPEAT },
    ],
    accessors, bufferViews, buffers: [{ byteLength: 0 }],
  };
  if (bake) { gltf.extensionsUsed = ['KHR_materials_unlit']; }

  const primitives = [], maskedPrims = [];
  const texIndex = new Map();
  for (const [name, s] of surfaces) {
    const n = s.pos.length / 3;
    if (!n) continue;
    /* THE TEXTURE, once per name */
    let ti = texIndex.get(name);
    const img = images.get(name);
    if (ti === undefined && img) {
      gltf.images.push({ name, mimeType: 'image/png', bufferView: put(img.png) });
      gltf.textures.push({ source: gltf.images.length - 1, sampler: img.smooth ? 1 : 0 });
      ti = gltf.textures.length - 1;
      texIndex.set(name, ti);
    }
    const mat = {
      name,
      pbrMetallicRoughness: { metallicFactor: 0, roughnessFactor: 1, ...(ti !== undefined ? { baseColorTexture: { index: ti } } : {}) },
      ...(img?.masked ? { alphaMode: 'MASK', alphaCutoff: 0.5 } : {}),
      ...(bake ? { extensions: { KHR_materials_unlit: {} } } : {}),
    };
    gltf.materials.push(mat);

    const P = new Float32Array(n * 3), N = new Float32Array(n * 3), T = new Float32Array(n * 2);
    const C = bake ? new Float32Array(n * 3) : null;
    for (let i = 0; i < n; i++) {
      P[i * 3] = s.pos[i * 3] * k; P[i * 3 + 1] = s.pos[i * 3 + 1] * k; P[i * 3 + 2] = s.pos[i * 3 + 2] * k;
      T[i * 2] = s.uv[i * 2]; T[i * 2 + 1] = 1 - s.uv[i * 2 + 1];
      if (C) {
        const l = Math.max(0, Math.min(1, s.light[i]));
        C[i * 3] = l * s.tint[i * 3]; C[i * 3 + 1] = l * s.tint[i * 3 + 1]; C[i * 3 + 2] = l * s.tint[i * 3 + 2];
      }
    }
    /* flat normals, a triangle at a time — the geometry is a triangle
       soup, as the game's own is */
    for (let t = 0; t < n; t += 3) {
      const ax = P[t * 3], ay = P[t * 3 + 1], az = P[t * 3 + 2];
      const ux = P[t * 3 + 3] - ax, uy = P[t * 3 + 4] - ay, uz = P[t * 3 + 5] - az;
      const vx = P[t * 3 + 6] - ax, vy = P[t * 3 + 7] - ay, vz = P[t * 3 + 8] - az;
      let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      const L = Math.hypot(nx, ny, nz) || 1;
      nx /= L; ny /= L; nz /= L;
      for (let j = 0; j < 3; j++) { N[(t + j) * 3] = nx; N[(t + j) * 3 + 1] = ny; N[(t + j) * 3 + 2] = nz; }
    }
    const attributes = { POSITION: accessor(P, 'VEC3', n, true), NORMAL: accessor(N, 'VEC3', n), TEXCOORD_0: accessor(T, 'VEC2', n) };
    if (C) attributes.COLOR_0 = accessor(C, 'VEC3', n);
    /* a cut-out picture — a grating, a fence in a doorway — is drawn but
       not walked into, as in the game; so it is a mesh of its own that
       gets no collision */
    (img?.masked ? maskedPrims : primitives).push({ attributes, material: gltf.materials.length - 1, mode: TRIANGLES });
  }
  gltf.meshes.push({ name: 'World', primitives });
  /* "-col": Godot's importer makes a StaticBody3D with a trimesh shape */
  gltf.nodes.push({ name: opts.collision === false ? 'World' : 'World-col', mesh: 0 });
  if (maskedPrims.length) {
    gltf.meshes.push({ name: 'Cutouts', primitives: maskedPrims });
    gltf.nodes.push({ name: 'Cutouts', mesh: 1 });
    gltf.scenes[0].nodes.push(1);
  }
  if (!primitives.length) { gltf.meshes[0].primitives = maskedPrims.splice(0); gltf.meshes.length = 1; gltf.nodes.length = 1; gltf.scenes[0].nodes = [0]; }
  if (!gltf.images.length) { delete gltf.images; delete gltf.textures; }
  gltf.buffers[0].byteLength = length;

  /* THE GLB: a header, the JSON padded with spaces, the binary padded
     with zeros */
  const json = new TextEncoder().encode(JSON.stringify(gltf));
  const jsonPad = (4 - (json.length % 4)) % 4, binPad = (4 - (length % 4)) % 4;
  const jsonLen = json.length + jsonPad, binLen = length + binPad;
  const total = 12 + 8 + jsonLen + 8 + binLen;
  const out = new Uint8Array(total);
  const dv = new DataView(out.buffer);
  dv.setUint32(0, 0x46546c67, true); dv.setUint32(4, 2, true); dv.setUint32(8, total, true);
  dv.setUint32(12, jsonLen, true); dv.setUint32(16, 0x4e4f534a, true);
  out.set(json, 20);
  for (let i = 0; i < jsonPad; i++) out[20 + json.length + i] = 0x20;
  let at = 20 + jsonLen;
  dv.setUint32(at, binLen, true); dv.setUint32(at + 4, 0x004e4942, true);
  at += 8;
  for (const c of chunks) { out.set(c, at); at += c.byteLength; }
  return out;
}

/* ---------------------------------------------------------------------
   THE SCENE
   --------------------------------------------------------------------- */
const f = v => (Math.abs(v) < 1e-9 ? '0' : String(+v.toFixed(5)));
const colour = (hex, fb = '#000000') => {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || '') || /^#?([0-9a-f]{6})$/i.exec(fb);
  const n = parseInt(m[1], 16);
  return `Color(${f(((n >> 16) & 255) / 255)}, ${f(((n >> 8) & 255) / 255)}, ${f((n & 255) / 255)}, 1)`;
};
/** A Godot node name: letters, digits and _ only, never empty. */
export const nodeName = s => String(s).replace(/[^A-Za-z0-9_]/g, '_').replace(/^_+/, '') || 'Node';

/**
 * The .tscn text.
 * @param doc       the document (sky, name)
 * @param things    every thing, placed and scattered: { type, kind?, x, y, z, angle, scale?, variant?, id? }
 *                  with z the floor height under it
 * @param sprites   Map(plant kind -> { file, w, h }) — the PNG and its size in pixels
 * @param opts      { scale, glb: 'world.glb', bake, collision }
 */
export function buildTSCN(doc, things, sprites, opts = {}) {
  const k = opts.scale ?? 1 / UNITS_PER_METRE;
  const ext = [], lines = [];
  const extId = new Map();
  const addExt = (type, path) => {
    if (extId.has(path)) return extId.get(path);
    const id = `${ext.length + 1}_${nodeName(path.replace(/\.[a-z]+$/, '')).slice(-24)}`;
    ext.push(`[ext_resource type="${type}" path="${path}" id="${id}"]`);
    extId.set(path, id);
    return id;
  };
  const glbId = addExt('PackedScene', opts.glb || 'world.glb');
  for (const [kind, sp] of sprites) addExt('Texture2D', sp.file);

  const sky = doc.world?.sky || {};
  /* a skybox from the texture pack is a panorama in Godot too — the
     same picture the game's sky sphere wears (js/texpack.js) */
  const skyId = opts.sky ? addExt('Texture2D', opts.sky) : null;
  const animId = opts.anim ? addExt('Script', opts.anim) : null;
  const subs = [
    skyId ? `[sub_resource type="PanoramaSkyMaterial" id="SkyMat"]
panorama = ExtResource("${skyId}")` : `[sub_resource type="ProceduralSkyMaterial" id="SkyMat"]
sky_top_color = ${colour(sky.zenith, '#000000')}
sky_horizon_color = ${colour(sky.horizon, '#1d9a48')}
ground_bottom_color = ${colour(sky.ground, '#05180c')}
ground_horizon_color = ${colour(sky.horizon, '#1d9a48')}`,
    `[sub_resource type="Sky" id="Sky"]
sky_material = SubResource("SkyMat")`,
    `[sub_resource type="Environment" id="Env"]
background_mode = 2
sky = SubResource("Sky")
ambient_light_source = 3
tonemap_mode = 0`,
  ];

  const root = nodeName(doc.name || 'Map');
  lines.push(`[node name="${root}" type="Node3D"]`, '');
  lines.push(`[node name="WorldEnvironment" type="WorldEnvironment" parent="."]`, `environment = SubResource("Env")`, '');
  if (opts.bake === false) {
    lines.push(`[node name="Sun" type="DirectionalLight3D" parent="."]`,
      `transform = Transform3D(1, 0, 0, 0, 0.5, 0.866025, 0, -0.866025, 0.5, 0, 10, 0)`, '');
  }
  lines.push(`[node name="World" parent="." instance=ExtResource("${glbId}")]`, '');
  /* the animated textures, stepped on by a script (animScript) */
  if (animId) lines.push(`[node name="DoomAnimated" type="Node" parent="."]`, `script = ExtResource("${animId}")`, '');

  /* the facing: the map's angle 0 is east and turns anticlockwise seen
     from above; a Godot node looks down its -Z. Rotating about Y by
     (angle - 90°) points -Z at the map's direction. */
  const xform = (x, y, z, angle = 0, s = 1) => {
    const th = angle - Math.PI / 2, c = Math.cos(th) * s, sn = Math.sin(th) * s;
    return `Transform3D(${f(c)}, 0, ${f(sn)}, 0, ${f(s)}, 0, ${f(-sn)}, 0, ${f(c)}, ${f(x * k)}, ${f(z * k)}, ${f(-y * k)})`;
  };

  const start = things.find(t => t.type === 'START');
  if (start) {
    lines.push(`[node name="PlayerStart" type="Marker3D" parent="."]`,
      `transform = ${xform(start.x, start.y, start.z, start.angle)}`, `metadata/type = "START"`, '');
  }
  const plants = things.filter(t => t.type === 'PLANT' && sprites.has(t.kind));
  /* STATIC DECOR — a trolley, a bollard, a crate, a fuel can, a
     headstone — is a billboard of the game's own picture, as a plant is */
  const decor = things.filter(t => t.type !== 'PLANT' && sprites.has(`thing:${t.type}`));
  const actors = things.filter(t => t.type !== 'PLANT' && t.type !== 'START' && THING_TYPES[t.type] && !sprites.has(`thing:${t.type}`));
  /* the sector's light and colour on a billboard, when the lighting is
     baked, as the geometry has them in its vertex colours */
  /* AUTOMATIC COLLISION: each billboard that stops you in the game gets a
     StaticBody3D child with a box — the axis-aligned bounds of the
     cylinder the game collides with (a tree's trunk radius, a thing's
     radius and height), standing on the floor. Boxes of one size share
     one BoxShape3D. A fern, a fuel can and anything else you walk
     through in the game gets none. */
  const boxIds = new Map();
  const collider = (path, r, h) => {
    if (opts.collision === false || !(r > 0) || !(h > 0)) return [];
    const w = 2 * r * k, hm = h * k, key = `${f(w)}x${f(hm)}`;
    let id = boxIds.get(key);
    if (!id) {
      id = `Box_${boxIds.size + 1}`; boxIds.set(key, id);
      subs.push(`[sub_resource type="BoxShape3D" id="${id}"]\nsize = Vector3(${f(w)}, ${f(hm)}, ${f(w)})`);
    }
    return [`[node name="Collision" type="StaticBody3D" parent="${path}"]`, '',
      `[node name="Shape" type="CollisionShape3D" parent="${path}/Collision"]`,
      `transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, ${f(hm / 2)}, 0)`,
      `shape = SubResource("${id}")`, ''];
  };
  const modulate = t => (opts.bake !== false && t.mod ? [`modulate = Color(${t.mod.map(v => f(Math.min(1, Math.max(0, v)))).join(', ')}, 1)`] : []);
  if (plants.length) {
    lines.push(`[node name="Sprites" type="Node3D" parent="."]`, '');
    const n = new Map();
    for (const t of plants) {
      const sp = sprites.get(t.kind), kd = plantKind(t.kind);
      const i = (n.get(t.kind) || 0) + 1; n.set(t.kind, i);
      /* pixel size: the plant's height in the game, in metres, over the
         picture's height in pixels — and the picture was drawn at the
         plant's own aspect when it was packed, so it is uniform */
      const px = (kd.h * (t.scale ?? 1) * k) / sp.h;
      const name = `${nodeName(t.kind)}_${i}`, s = t.scale ?? 1;
      lines.push(`[node name="${name}" type="Sprite3D" parent="Sprites"]`,
        `transform = ${xform(t.x, t.y, t.z, 0)}`,
        `offset = Vector2(0, ${f(sp.h / 2)})`,
        `pixel_size = ${f(px)}`,
        `billboard = 2`,
        `shaded = false`,
        `alpha_cut = 1`,
        `texture_filter = 0`,
        ...modulate(t),
        `texture = ExtResource("${extId.get(sp.file)}")`,
        '', ...collider(`Sprites/${name}`, (kd.r || 0) * s, kd.h * s));
    }
  }
  if (decor.length) {
    lines.push(`[node name="Decor" type="Node3D" parent="."]`, '');
    const n = new Map();
    for (const t of decor) {
      const sp = sprites.get(`thing:${t.type}`);
      const i = (n.get(t.type) || 0) + 1; n.set(t.type, i);
      const name = `${nodeName(t.type)}_${i}`, s = t.scale ?? 1;
      lines.push(`[node name="${name}" type="Sprite3D" parent="Decor"]`,
        `transform = ${xform(t.x, t.y, t.z, 0)}`,
        `offset = Vector2(0, ${f(sp.h / 2)})`,
        `pixel_size = ${f((sp.worldH * (t.scale ?? 1) * k) / sp.h)}`,
        `billboard = 2`,
        `shaded = false`,
        `alpha_cut = 1`,
        `texture_filter = 0`,
        ...modulate(t),
        `texture = ExtResource("${extId.get(sp.file)}")`,
        `metadata/type = "${t.type}"`,
        '', ...(sp.solid ? collider(`Decor/${name}`, (sp.radius || 0) * s, (sp.height ?? sp.worldH) * s) : []));
    }
  }
  if (actors.length) {
    lines.push(`[node name="Things" type="Node3D" parent="."]`, '');
    const n = new Map();
    for (const t of actors) {
      const i = (n.get(t.type) || 0) + 1; n.set(t.type, i);
      lines.push(`[node name="${nodeName(t.type)}_${i}" type="Marker3D" parent="Things"]`,
        `transform = ${xform(t.x, t.y, t.z, t.angle || 0)}`,
        `metadata/type = "${t.type}"`,
        ...(t.variant !== undefined ? [`metadata/variant = ${t.variant | 0}`] : []),
        '');
    }
  }
  const head = `[gd_scene load_steps=${ext.length + subs.length + 1} format=3]`;
  return [head, '', ...ext, '', ...subs.flatMap(x => [x, '']), ...lines].join('\n');
}

/** A PNG's size, from its header. */
export function pngSize(bytes) {
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { w: dv.getUint32(16), h: dv.getUint32(20) };
}

/* ---------------------------------------------------------------------
   DOING IT, in the browser
   --------------------------------------------------------------------- */
const blobBytes = async blob => new Uint8Array(await blob.arrayBuffer());
const canvasPng = c => new Promise(res => c.toBlob(b => res(b), 'image/png')).then(blobBytes);
const loadImg = src => new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });

/**
 * Build the whole export: the zip, as a Blob.
 * @param ed    the Editor (its compiled level, bank, doc)
 * @param opts  { unitsPerMetre, bake, collision, things, onProgress }
 */
export async function exportGodot(ed, opts = {}) {
  const { buildLevelGeometry } = await import('../mapgeo.js');
  const { Zip } = await import('../pack.js');
  const say = opts.onProgress || (() => {});
  ed.compile();
  const c = ed.compiled;
  if (!c?.level) throw new Error('the map did not compile');
  const scale = 1 / (opts.unitsPerMetre || UNITS_PER_METRE);
  const folder = nodeName(ed.doc.name || 'map').toLowerCase();

  say('building the geometry');
  const geo = buildLevelGeometry(c.level, ed.bank);
  const surfaces = gatherSurfaces(geo.group);

  say('packing the textures');
  const images = new Map(), texFiles = [];
  for (const name of surfaces.keys()) {
    const e = ed.bank.map.get(name);
    const own = e?.own || e?.texture?.image;
    if (!own) continue;
    const png = await canvasPng(own);
    images.set(name, { png, masked: !!e.masked, smooth: e.texture.magFilter === 1006 });
    texFiles.push([`textures/${name}.png`, png]);
  }
  /* AN ANIMATED TEXTURE brings the rest of its run, as files, for the
     script that steps through them (animScript) */
  const runs = new Map();
  for (const name of surfaces.keys()) { const a = animOf(name); if (a) runs.set(a.stem, a); }
  if (runs.size) {
    const frames = [...runs.values()].flatMap(a => a.run);
    await loadPack(ed.bank, frames);
    for (const f of frames) {
      if (images.has(f)) continue;
      const own = ed.bank.map.get(f)?.own;
      if (own) texFiles.push([`textures/${f}.png`, await canvasPng(own)]);
    }
  }
  /* and the skybox, if the map has one */
  let skyFile = null, skyPng = null;
  const box = ed.doc.world?.skybox;
  if (box && SKIES[box]) {
    try { skyPng = new Uint8Array(await (await fetch(SKIES[box])).arrayBuffer()); skyFile = `sky/${box}.png`; }
    catch (e) { console.warn('no skybox picture for', box, e); }
  }

  say('writing world.glb');
  const glb = buildGLB(surfaces, images, { scale, bake: opts.bake !== false, collision: opts.collision !== false, name: ed.doc.name });

  /* THE THINGS, placed and grown, each on the floor under it */
  const L = c.level;
  const floorZ = (x, y) => { const s = L.sectorAt(x, y); return s ? L.floorAt(s, x, y) : 0; };
  let things = opts.things === false ? ed.doc.things.filter(t => t.type === 'START')
    : [...ed.doc.things, ...(c.scattered || [])];
  /* a map with no start has one made for it by the compiler; the scene
     gets that one */
  if (!things.some(t => t.type === 'START')) {
    const st = L.things.find(t => t.type === 'START');
    if (st) things = [{ type: 'START', x: st.x, y: st.y, angle: st.angle || 0 }, ...things];
  }
  /* each on the floor under it, with the light and thing colour of the
     sector it stands in (for a billboard's modulate) */
  const placed = things.map(t => {
    const s = L.sectorAt(t.x, t.y);
    const l = Math.min(1, s?.light ?? 1), c = s?.tint?.thing || [1, 1, 1];
    return { ...t, z: floorZ(t.x, t.y), mod: [c[0] * l, c[1] * l, c[2] * l] };
  });

  say('drawing the sprites');
  const sprites = new Map(), spriteFiles = [];
  for (const kind of new Set(placed.filter(t => t.type === 'PLANT').map(t => t.kind))) {
    const kd = plantKind(kind);
    if (!kd) continue;
    try {
      const img = await loadImg(`assets/forest/${kind}.png`);
      /* redrawn at the plant's own aspect, which the game stretches the
         tile to — so the Sprite3D can scale evenly */
      const cv = document.createElement('canvas');
      cv.height = img.height; cv.width = Math.max(1, Math.round(img.height * kd.aspect));
      const g = cv.getContext('2d');
      g.imageSmoothingEnabled = false;
      g.drawImage(img, 0, 0, cv.width, cv.height);
      const png = await canvasPng(cv);
      const file = `sprites/${kind}.png`;
      sprites.set(kind, { file, w: cv.width, h: cv.height });
      spriteFiles.push([file, png]);
    } catch (e) { console.warn('no picture for', kind, e); }
  }

  /* AND THE DECOR'S PICTURES: the game's own sprites, drawn here as the
     game draws them, front view */
  const decorTypes = [...new Set(placed.map(t => t.type))].filter(ty => ty !== 'PLANT' && DECOR_TYPES.includes(ty));
  if (decorTypes.length) {
    say('drawing the decor');
    const { bakeSprites } = await import('../sprites.js');
    const { STATES, ACTORS } = await import('../states.js');
    const bankS = bakeSprites();
    for (const ty of decorTypes) {
      const st = STATES[ACTORS[ty]?.spawn];
      if (!st) continue;
      const e = bankS.get(st.sprite, st.frame);
      if (!e?.views?.[0]) continue;
      const cv = e.views[0].toCanvas();
      const file = `sprites/${ty.toLowerCase()}.png`;
      const a = ACTORS[ty];
      sprites.set(`thing:${ty}`, { file, w: cv.width, h: cv.height, worldH: e.h * (e.scale || 1),
        solid: !!a.solid, radius: a.radius, height: a.height });
      spriteFiles.push([file, await canvasPng(cv)]);
    }
  }

  say('writing the scene');
  const tscn = buildTSCN(ed.doc, placed, sprites, { scale, glb: 'world.glb', bake: opts.bake !== false, collision: opts.collision !== false,
    sky: skyFile, anim: runs.size ? 'doom_anim.gd' : null });
  const counts = {
    surfaces: surfaces.size, triangles: [...surfaces.values()].reduce((a, s) => a + s.pos.length / 9, 0),
    sprites: placed.filter(t => (t.type === 'PLANT' && sprites.has(t.kind)) || sprites.has(`thing:${t.type}`)).length,
    markers: placed.filter(t => t.type !== 'PLANT' && !sprites.has(`thing:${t.type}`)).length,
  };

  const zip = new Zip();
  zip.add(`${folder}/${folder}.tscn`, new TextEncoder().encode(tscn));
  zip.add(`${folder}/world.glb`, glb);
  for (const [n, b] of texFiles) zip.add(`${folder}/${n}`, b);
  for (const [n, b] of spriteFiles) zip.add(`${folder}/${n}`, b);
  if (skyFile) zip.add(`${folder}/${skyFile}`, skyPng);
  if (runs.size) zip.addText(`${folder}/doom_anim.gd`, animScript([...runs.values()]));
  zip.addText(`${folder}/README.txt`, readme(ed.doc, folder, opts, counts));
  return { blob: zip.close(), name: `${folder}-godot.zip`, counts, tscn, glb };
}

/**
 * THE ANIMATED TEXTURES, in Godot: a script that steps every material
 * wearing a frame of a run on through the run, Doom's way — each frame
 * held for its run's tics of 35 a second, each wall from the frame it
 * was given (js/texpack.js). The materials are found by name, which the
 * GLB gives them: a material is named after its texture.
 * @param runs  [{ stem, run: [frame names], tics }]
 */
export function animScript(runs) {
  const R = runs.map(a => `\t"${a.stem}": {"tics": ${a.tics}, "frames": [${a.run.map(f => `"${f}"`).join(', ')}]},`).join('\n');
  return `extends Node
## Doom's animated textures, as MEWD Editor runs them: every frame of a run
## is held for the run's number of tics, 35 to the second, and every
## surface wearing any frame of it steps on through it from that frame.

const TICRATE := 35.0
const RUNS := {
${R}
}

var _tex := {}
var _mats := []
var _t := 0.0
var _tic := -1

func _ready() -> void:
\tvar dir: String = get_script().resource_path.get_base_dir() + "/textures/"
\tvar where := {}
\tfor stem in RUNS:
\t\tvar r: Dictionary = RUNS[stem]
\t\tvar frames: Array = r["frames"]
\t\tfor i in frames.size():
\t\t\twhere[frames[i]] = [frames, i, int(r["tics"])]
\t\t\t_tex[frames[i]] = load(dir + frames[i] + ".png")
\t_scan(get_parent(), where, {})

func _scan(n: Node, where: Dictionary, seen: Dictionary) -> void:
\tif n is MeshInstance3D and n.mesh:
\t\tfor s in n.mesh.get_surface_count():
\t\t\tvar m = n.mesh.surface_get_material(s)
\t\t\tif m is BaseMaterial3D and where.has(m.resource_name) and not seen.has(m):
\t\t\t\tseen[m] = true
\t\t\t\tvar w: Array = where[m.resource_name]
\t\t\t\t_mats.append([m, w[0], w[1], w[2]])
\tfor c in n.get_children():
\t\t_scan(c, where, seen)

func _process(delta: float) -> void:
\t_t += delta
\tvar tic := int(_t * TICRATE)
\tif tic == _tic:
\t\treturn
\t_tic = tic
\tfor e in _mats:
\t\tvar frames: Array = e[1]
\t\tvar f: String = frames[(int(e[2]) + tic / int(e[3])) % frames.size()]
\t\tif _tex[f]:
\t\t\te[0].albedo_texture = _tex[f]
`;
}

function readme(doc, folder, opts, n) {
  return `${doc.name || 'MAP'} — exported from MEWD Editor for Godot 4

1. Copy the folder "${folder}" anywhere into your Godot project.
2. Let Godot import it (it does so when the editor gets focus).
3. Open ${folder}.tscn.

What is in it
  ${folder}.tscn   the scene. World (world.glb) is the level; Sprites
                   are the trees and plants, as Sprite3D billboards;
                   Things are Marker3D nodes where the game's actors
                   stand, with metadata/type (and metadata/variant) to
                   put your own scenes on; PlayerStart is the start.
  world.glb        every surface, UV-mapped, textures packed inside:
                   ${n.surfaces} textures, ${n.triangles} triangles
  textures/        the same textures as PNG files, and every frame of
                   any animated one
  doom_anim.gd     (if the map wears an animated texture) steps them
                   on at Doom's rate; it is on the DoomAnimated node
  sky/             (if the map has a skybox) the panorama the sky wears
  sprites/         the billboards' pictures

Made with
  scale            ${opts.unitsPerMetre || UNITS_PER_METRE} map units to the metre
  lighting         ${opts.bake === false ? 'lit materials — add your own lights (a sun is in the scene)' : 'baked: sector brightness and Doom 64 colours are the vertex colours, materials unshaded'}
  collision        ${opts.collision === false ? 'none' : `the mesh is named World-col, so Godot makes a static trimesh body for it;
                   each tree, bush and solid piece of decor has a StaticBody3D
                   with a box the size the game collides with`}
  ${n.sprites} sprites, ${n.markers} markers

Textures are point sampled (nearest), as in the game. In the import
settings of world.glb you can change that, or the collision, and
re-import.
`;
}

/* ---------------------------------------------------------------------
   THE DIALOG
   --------------------------------------------------------------------- */
export function openGodotDialog(ed) {
  document.getElementById('ed-godot')?.remove();
  const h = (tag, attrs = {}, ...kids) => {
    const el = document.createElement(tag);
    for (const [a, v] of Object.entries(attrs)) {
      if (v === undefined || v === null || v === false) continue;
      if (a === 'class') el.className = v; else if (a.startsWith('on')) el.addEventListener(a.slice(2), v); else el.setAttribute(a, v === true ? '' : v);
    }
    for (const c of kids.flat()) if (c !== null && c !== undefined && c !== false) el.append(c.nodeType ? c : String(c));
    return el;
  };
  const o = { unitsPerMetre: UNITS_PER_METRE, bake: true, collision: true, things: true };
  const status = h('div', { class: 'ed-note' }, '');
  const row = (label, el, note) => h('div', { class: 'ed-row' }, h('label', {}, label), h('div', {}, el, note ? h('div', { class: 'ed-note' }, note) : null));
  const chk = key => h('input', { type: 'checkbox', checked: o[key], onchange: e => { o[key] = e.target.checked; } });
  const go = h('button', { class: 'ed-btn play', onclick: async () => {
    go.disabled = true;
    try {
      const r = await exportGodot(ed, { ...o, onProgress: m => { status.textContent = `${m}…`; } });
      const { save } = await import('../pack.js');
      save(r.blob, r.name);
      status.textContent = `Saved ${r.name}: ${r.counts.surfaces} textures, ${r.counts.triangles} triangles, ${r.counts.sprites} sprites, ${r.counts.markers} markers.`;
      ed.say(`exported ${r.name}`);
    } catch (e) {
      console.error(e);
      status.textContent = `Export failed: ${e.message}`;
    }
    go.disabled = false;
  } }, 'Export');
  const box = h('div', { class: 'ed-tx-box ed-gd-box' },
    h('div', { class: 'ed-tx-head' }, h('b', {}, 'Export Godot scene'), h('span', { class: 'ed-note' }, ' — a folder for a Godot 4 project: a .tscn, the level as .glb, and the textures')),
    h('div', { class: 'ed-gd-body' },
      row('Units per metre', h('input', { type: 'number', value: o.unitsPerMetre, min: 1, step: 1, onchange: e => { o.unitsPerMetre = Math.max(1, +e.target.value || 32); } }),
        'Map units in one Godot metre. 32 makes a person about 1.75 m.'),
      row('Bake lighting', chk('bake'), 'Sector brightness and Doom 64 colours as vertex colours, unshaded — looks like the map. Off: lit materials and a sun.'),
      row('Collision', chk('collision'), 'A static trimesh body for the level, so it can be walked on, and a box around each tree, bush and solid piece of decor.'),
      row('Things', chk('things'), 'Trees and plants as billboard sprites; people and furniture as markers. Off: only the player start.'),
      status),
    h('div', { class: 'ed-tx-foot' }, h('span', { class: 'ed-tx-err' }), h('button', { class: 'ed-btn', onclick: () => overlay.remove() }, 'Close'), go));
  const overlay = h('div', { id: 'ed-godot', class: 'ed-modal', onmousedown: e => { if (e.target === overlay) overlay.remove(); } }, box);
  ed.root.append(overlay);
}
