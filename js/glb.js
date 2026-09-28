/* =====================================================================
   MEWD — a GLB loader, only as much as one is
   =====================================================================

   Three ships a GLTFLoader that understands the whole format: skins,
   morph targets, animation, eleven extensions, Draco, KTX2. It is
   forty kilobytes on top of a vendored three that already downloads
   nothing else, and every one of those features is one this game has
   no model for. What the game loads is a gun — and, later, some cars —
   exported from Blender with no rigging: nodes, meshes, one material,
   one texture. This reads exactly that and throws on anything else, so
   a model that needs more fails loudly at load rather than quietly
   rendering wrong.

   What it returns is a plain three Group. Materials are the caller's
   business — js/weapon3d.js wants the gun lit its own way — so the
   loader hands each primitive's material definition and decoded
   textures to a callback and uses whatever comes back. Textures are
   decoded by the browser (createImageBitmap on the embedded PNG) and
   then POINT SAMPLED, whatever the file says — see pointSample below,
   which is the one rule for every model this game imports.
   ===================================================================== */

import * as THREE from 'three';

const MAGIC = 0x46546C67, CHUNK_JSON = 0x4E4F534A, CHUNK_BIN = 0x004E4942;
const COMPONENT = {
  5120: Int8Array, 5121: Uint8Array, 5122: Int16Array, 5123: Uint16Array, 5125: Uint32Array, 5126: Float32Array,
};
const ITEMS = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };
/* The wrap table, exported because js/car.js loads a model's texture its
   own way and still wants the file's own wrapping. There is no filter
   table any more: see pointSample. */
export const GL_WRAP = { 33071: THREE.ClampToEdgeWrapping, 33648: THREE.MirroredRepeatWrapping, 10497: THREE.RepeatWrapping };

/* ---------------------------------------------------------------------
   HOW AN IMPORTED MODEL'S TEXTURE IS SAMPLED, AND IT IS NOT WHAT THE
   FILE SAYS

   At the user's request, and it is the right request: this renderer
   point-samples EVERYTHING. The walls and floors do (js/textures.js),
   the sprites do, the sky does, the fire does, the HUD does — Doom
   point-sampled everything and the whole look of the game is downstream
   of that. A model that arrives asking for LINEAR is a model that was
   exported by somebody rendering it a different way, and honouring that
   ask put five of the six models in this game — every one but the van —
   through a bilinear filter that softened them against a world that is
   not soft. The gun in your hands is the worst of it, because it is the
   thing on screen at the largest magnification: a 1024-square diffuse
   blown up to fill a third of the frame is where a smoothed texel is a
   centimetre wide.

   So the file's filters are ignored and this is used instead, which is
   exactly what js/textures.js does to the world:

     NEAREST magnified          a texel is a square, and stays one
     NEAREST_MIPMAP_NEAREST     point-sampled at every distance too, and
       minified, mipped         it drops a whole level rather than
                                blending two — a van at the far end of
                                the lot picks one mip and samples it
                                sharp

   Mipmaps ON is the one part that is not simply "nearest". Without them
   a minified surface aliases into boiling noise as it moves, which is a
   different artefact from the one Doom had and not a better one; with
   them a distant van is crisp and quiet. The sprites get NO mipmaps for
   a reason of their own (a mipped sprite loses its cut-out edge — see
   js/sprites.js), and a model is not a cut-out.

   WHAT IS STILL THE FILE'S is the WRAPPING, because that is not a
   question about how the game looks, it is a question about what the
   UVs mean: a model unwrapped to tile across a seam needs REPEAT and one
   unwrapped into an atlas needs CLAMP, and only the file knows which.
   Where a glTF leaves it out the spec's own answer is REPEAT, which is
   not this renderer's habit and is not ours to pick.
   ------------------------------------------------------------------- */
export function pointSample(tex) {
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestMipmapNearestFilter;
  tex.generateMipmaps = true;
  return tex;
}

/** Split a .glb into its JSON and its binary payload. Pure, so the
 *  smoke test can check a prepared model without a browser. */
export function parseGLB(arrayBuffer) {
  const dv = new DataView(arrayBuffer);
  if (dv.getUint32(0, true) !== MAGIC || dv.getUint32(4, true) !== 2) throw new Error('not a glTF 2 binary');
  const length = dv.getUint32(8, true);
  let off = 12, json = null, bin = null;
  while (off < length) {
    const len = dv.getUint32(off, true), type = dv.getUint32(off + 4, true);
    const bytes = new Uint8Array(arrayBuffer, off + 8, len);
    if (type === CHUNK_JSON) json = JSON.parse(new TextDecoder().decode(bytes));
    else if (type === CHUNK_BIN) bin = bytes;
    off += 8 + len;
  }
  if (!json || !bin) throw new Error('GLB needs a JSON and a BIN chunk');
  if (json.extensionsRequired?.length) throw new Error('unsupported extensions: ' + json.extensionsRequired.join());
  return { json, bin };
}

/** One accessor as a tightly packed typed array plus its item size, and
 *  whether its integers stand for 0..1 — see `normalized` below. */
export function readAccessor(json, bin, index) {
  const a = json.accessors[index];
  if (a.sparse) throw new Error('sparse accessors are not supported');
  const T = COMPONENT[a.componentType], n = ITEMS[a.type];
  if (!T || !n) throw new Error(`accessor ${index}: unsupported ${a.componentType} ${a.type}`);
  /* A NORMALISED ACCESSOR IS A FRACTION WRITTEN AS AN INTEGER: bytes of
     vertex colour mean 0..255 over 255, and read as plain integers they
     are a colour two hundred and fifty times too bright. Nothing in the
     game shipped one until the quad launcher, whose paint is in its
     vertices (see tools/decimate-model.mjs), so the flag was never read
     and a model carrying it came out white. It goes to the attribute,
     which is where three does the dividing. */
  const normalized = !!a.normalized;
  const bv = json.bufferViews[a.bufferView];
  const start = bin.byteOffset + (bv.byteOffset || 0) + (a.byteOffset || 0);
  const stride = bv.byteStride || 0;
  const elem = T.BYTES_PER_ELEMENT * n;
  if (!stride || stride === elem) {
    /* Aligned copies only: a typed array view needs its offset to be a
       multiple of the element size, which a GLB does not promise. */
    return { array: new T(bin.buffer.slice(start, start + a.count * elem)), itemSize: n, normalized };
  }
  const out = new T(a.count * n);
  const src = new DataView(bin.buffer);
  const get = { 5120: 'getInt8', 5121: 'getUint8', 5122: 'getInt16', 5123: 'getUint16', 5125: 'getUint32', 5126: 'getFloat32' }[a.componentType];
  for (let i = 0; i < a.count; i++)
    for (let k = 0; k < n; k++)
      out[i * n + k] = src[get](start + i * stride + k * T.BYTES_PER_ELEMENT, true);
  return { array: out, itemSize: n, normalized };
}

/**
 * Load a .glb into a Group.
 *
 * @param {string} url
 * @param {object} opts
 *   material(def, maps)  returns a THREE.Material for a primitive. `def`
 *                        is the glTF material (or null) and `maps` holds
 *                        { map } — the decoded base colour texture, if any.
 * @returns {{ root: THREE.Group, json: object, extras: object }}
 */
export async function loadGLB(url, opts = {}) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  const { json, bin } = parseGLB(await res.arrayBuffer());
  if (json.animations?.length || json.skins?.length) throw new Error('animated or skinned models are not supported');

  /* TEXTURES, DECODED BY THE BROWSER AND ONLY THE ONES ASKED FOR.
     A PBR model brings maps this renderer has no use for — the
     extinguisher carries a 1024-square metallic-roughness map beside its
     colour, and there is no metal and no roughness anywhere in this
     game — and decoding one is a megabyte and a half of PNG and a
     texture upload for a sampler nothing will ever read. So they are
     built on demand: `textureFor` is what the material callback's `maps`
     is filled from, and a map nobody asks for is never touched. */
  const textureCache = new Map();
  const textureFor = async idx => {
    if (textureCache.has(idx)) return textureCache.get(idx);
    const t = json.textures[idx];
    const im = json.images[t.source];
    if (im.bufferView === undefined) throw new Error('external images are not supported');
    const bv = json.bufferViews[im.bufferView];
    const bytes = bin.subarray(bv.byteOffset || 0, (bv.byteOffset || 0) + bv.byteLength);
    const bitmap = await createImageBitmap(new Blob([bytes], { type: im.mimeType }), { premultiplyAlpha: 'none', colorSpaceConversion: 'none' });
    const tex = pointSample(new THREE.Texture(bitmap));
    const s = json.samplers?.[t.sampler] || {};
    tex.wrapS = GL_WRAP[s.wrapS] ?? THREE.RepeatWrapping;      // glTF's own default
    tex.wrapT = GL_WRAP[s.wrapT] ?? THREE.RepeatWrapping;
    tex.flipY = false;                    // glTF's uv origin is the top-left
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.needsUpdate = true;
    textureCache.set(idx, tex);
    return tex;
  };

  const makeMaterial = opts.material || ((def, maps) => new THREE.MeshBasicMaterial({ map: maps.map || null }));
  const materialCache = new Map();
  /* Every material in the file, built up front so the node walk below
     can stay synchronous — decoding the pictures is the only await in
     here and it happens once per material rather than once per node. */
  for (let i = 0; i < (json.materials || []).length; i++) {
    const def = json.materials[i];
    const bc = def?.pbrMetallicRoughness?.baseColorTexture;
    materialCache.set(i, makeMaterial(def, { map: bc ? await textureFor(bc.index) : null }));
  }
  materialCache.set(undefined, makeMaterial(null, { map: null }));
  const materialFor = idx => materialCache.get(idx);

  const geometries = new Map();
  const geometryFor = (mi, pi) => {
    const key = mi + ':' + pi;
    if (geometries.has(key)) return geometries.get(key);
    const p = json.meshes[mi].primitives[pi];
    if (p.mode !== undefined && p.mode !== 4) throw new Error('only triangle lists are supported');
    if (p.targets) throw new Error('morph targets are not supported');
    const g = new THREE.BufferGeometry();
    const names = { POSITION: 'position', NORMAL: 'normal', TEXCOORD_0: 'uv', COLOR_0: 'color' };
    for (const [attr, acc] of Object.entries(p.attributes)) {
      const name = names[attr];
      if (!name) continue;
      const { array, itemSize, normalized } = readAccessor(json, bin, acc);
      g.setAttribute(name, new THREE.BufferAttribute(array, itemSize, normalized));
    }
    if (p.indices !== undefined) g.setIndex(new THREE.BufferAttribute(readAccessor(json, bin, p.indices).array, 1));
    if (!g.getAttribute('normal')) g.computeVertexNormals();
    g.computeBoundingSphere();
    geometries.set(key, g);
    return g;
  };

  const buildNode = ni => {
    const n = json.nodes[ni];
    let obj;
    if (n.mesh !== undefined) {
      const prims = json.meshes[n.mesh].primitives;
      if (prims.length === 1) obj = new THREE.Mesh(geometryFor(n.mesh, 0), materialFor(prims[0].material));
      else {
        obj = new THREE.Group();
        prims.forEach((p, pi) => obj.add(new THREE.Mesh(geometryFor(n.mesh, pi), materialFor(p.material))));
      }
    } else obj = new THREE.Group();
    obj.name = n.name || '';
    if (n.matrix) obj.applyMatrix4(new THREE.Matrix4().fromArray(n.matrix));
    else {
      if (n.translation) obj.position.fromArray(n.translation);
      if (n.rotation) obj.quaternion.fromArray(n.rotation);
      if (n.scale) obj.scale.fromArray(n.scale);
    }
    for (const c of n.children || []) obj.add(buildNode(c));
    return obj;
  };

  const root = new THREE.Group();
  const scene = json.scenes[json.scene ?? 0];
  for (const ni of scene.nodes) root.add(buildNode(ni));
  return { root, json, extras: json.asset?.extras || {} };
}
