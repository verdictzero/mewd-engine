/* A stand-in for three.js, so the parts of the game that have nothing to
   do with WebGL can be tested in Node.

   The bakeries, the map builder, the collision and the state tables are
   all pure — they make typed arrays and plain objects. The only reason
   they cannot run headless is that the modules holding them also import
   three at the top for the handful of names they use to UPLOAD the
   result. This supplies those names and nothing else.

   If a test fails with "X is not a constructor", the honest fix is to
   add X here, not to work around it in the test. */
export const NearestFilter = 1003, NearestMipmapNearestFilter = 1004, LinearFilter = 1006;
export const RepeatWrapping = 1000, ClampToEdgeWrapping = 1001;
export const SRGBColorSpace = 'srgb', FrontSide = 0, BackSide = 1, DoubleSide = 2;
export const RGBAFormat = 1023, UnsignedByteType = 1009, GLSL3 = '300 es';
export const RedFormat = 1028, NearestMipmapLinearFilter = 1005, DynamicDrawUsage = 35048;

class Stub { constructor(o) { if (o && typeof o === 'object') Object.assign(this, o); } }
export class CanvasTexture extends Stub {
  constructor(c) { super(); this.image = c; this.repeat = new Vector2(1, 1); this.offset = new Vector2(); }
  clone() { const t = new CanvasTexture(this.image); Object.assign(t, this); return t; }
}
/* format and type are carried because code reads them back: the burn
   grid is a RedFormat texture and the test that it is one byte a cell
   has to be able to see that. */
export class DataTexture extends Stub {
  constructor(d, w, h, format, type) {
    super();
    this.image = { data: d, width: w, height: h };
    this.format = format; this.type = type;
  }
}
export class Vector2 { constructor(x = 0, y = 0) { this.x = x; this.y = y; } set(x, y) { this.x = x; this.y = y; return this; } }
export class Vector4 extends Vector2 { constructor(x = 0, y = 0, z = 0, w = 0) { super(x, y); this.z = z; this.w = w; } }
export class Sphere { constructor(c, r) { this.center = c; this.radius = r; } }
export class Vector3 extends Vector2 { constructor(x = 0, y = 0, z = 0) { super(x, y); this.z = z; } set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; } multiplyScalar(k) { this.x *= k; this.y *= k; this.z *= k; return this; } }
export class Color { constructor() {} setRGB() { return this; } setHex() { return this; } }
/* A group has a place and a turn, because the gunship (js/vtol.js) is a
   tree of them — the turret on the nose, the gun on the turret — and
   the test flies one. Nothing reads a matrix back. */
/* An Object3D carries a userData bag in real three.js and things hang
   state off it — js/mapgeo.js keeps a block's LOD decision there — so a
   Group without one is a stub that throws where the game does not. */
export class Group {
  constructor() { this.children = []; this.position = new Vector3(); this.scale = new Vector3(1, 1, 1); this.rotation = new Vector3(); this.rotation.order = 'XYZ'; this.visible = true; this.name = ''; this.userData = {}; }
  add(o) { this.children.push(o); }
  remove(o) { const i = this.children.indexOf(o); if (i >= 0) this.children.splice(i, 1); }
  clear() { this.children.length = 0; }
  traverse() {}
}
export class Object3D extends Group {}
/* rotation is a Vector3 rather than an Euler, which is enough: the
   game only ever sets x, y, z and an order, and nothing headless reads
   a matrix back out of it. */
/* A MESH IS AN OBJECT3D, which is what lets one be hung off another:
   the gunship (js/vtol.js) is a tree of meshes — the turret on the
   fuselage, the gun on the turret — and without `add` here the whole
   aircraft is untestable headless. */
/* layers, because the police light bars glow and glowing is a layer
   (see js/bloom.js); a bitmask, as in three */
export class Layers {
  constructor() { this.mask = 1; }
  set(n) { this.mask = (1 << n) >>> 0; } enable(n) { this.mask |= 1 << n; } disable(n) { this.mask &= ~(1 << n); }
  test(l) { return (this.mask & l.mask) !== 0; }
}
export class Mesh extends Stub {
  constructor(g, m) { super(); this.geometry = g; this.material = m; this.layers = new Layers(); this.position = new Vector3(); this.scale = new Vector3(1, 1, 1); this.rotation = new Vector3(); this.rotation.order = 'XYZ'; this.userData = {}; this.visible = true; this.children = []; this.name = ''; }
  add(o) { this.children.push(o); return this; }
  remove(o) { const i = this.children.indexOf(o); if (i >= 0) this.children.splice(i, 1); return this; }
  traverse(fn) { if (fn) fn(this); for (const c of this.children) c.traverse?.(fn); }
}
/* It keeps its attributes, because things that read one back —
   js/slidedoor.js relights a door by rewriting its light attribute —
   cannot be exercised headless otherwise, and because it lets a test
   hold a built vehicle's UVs against the atlas without a GPU. */
export class BufferGeometry {
  constructor() { this.attributes = {}; }
  setAttribute(name, attr) { this.attributes[name] = attr; return this; }
  getAttribute(name) { return this.attributes[name]; }
  computeBoundingSphere() {}
  setIndex(attr) { this.index = attr; return this; }
  setDrawRange(start, count) { this.drawRange = { start, count }; }
  dispose() {}
  translate() { return this; }
}
export class PlaneGeometry extends BufferGeometry {}
/* the decals are one instanced box (js/decals.js): a cube's eight
   corners and twelve triangles, enough for the instancing to be set up */
export class BoxGeometry extends BufferGeometry {
  constructor() {
    super();
    this.setAttribute('position', new Float32BufferAttribute(new Float32Array(24), 3));
    this.setIndex(new Float32BufferAttribute(new Uint16Array(36), 1));
  }
}
export class Matrix4 { constructor() { this.elements = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]; } copy(m) { if (m?.elements) this.elements = m.elements.slice(); return this; } }
export const CustomBlending = 5, AddEquation = 100, OneFactor = 201, ZeroFactor = 200, OneMinusSrcAlphaFactor = 205;
export class SphereGeometry extends BufferGeometry {}
export class Texture extends Stub { constructor(img) { super(); this.image = img; this.isTexture = true; } }
export class CylinderGeometry extends BufferGeometry {}
/* Update ranges are how r159 onward says "only this part of the buffer
   moved" — js/standees.js sends one crowd's worth of a batch and not the
   whole thing — so the stub carries them or the batcher throws headless. */
export class Float32BufferAttribute {
  constructor(a, n) { this.array = a; this.itemSize = n; this.updateRanges = []; }
  get count() { return this.array.length / this.itemSize; }
  setUsage() { return this; }
  addUpdateRange(start, count) { this.updateRanges.push({ start, count }); }
  clearUpdateRanges() { this.updateRanges.length = 0; }
}
export class BufferAttribute extends Float32BufferAttribute {}
/* the forest's chunks are instanced: the geometry keeps its instance
   count and its attributes, so a test can count what each chunk holds */
export class InstancedBufferGeometry extends BufferGeometry { constructor() { super(); this.instanceCount = 0; } }
export class InstancedBufferAttribute extends Float32BufferAttribute { setUsage() { return this; } }
export class ShaderMaterial extends Stub { dispose() {} }
export const AdditiveBlending = 2, NormalBlending = 1;
export class RawShaderMaterial extends ShaderMaterial {}
export class MeshBasicMaterial extends Stub { constructor(o) { super(o); this.color = new Color(); } dispose() {} }
export class Scene extends Group { }
/* the bore's sight is a two-point line; headless it is a mesh that
   holds its geometry, which is all anything reads back */
export class Line extends Mesh {}
export class LineBasicMaterial extends MeshBasicMaterial {}
export class Camera extends Stub {}
export class PerspectiveCamera extends Camera {}
export class OrthographicCamera extends Camera { updateProjectionMatrix() {} }
export class DepthTexture extends Stub { constructor(w, h) { super(); this.image = { width: w, height: h }; } }
export class WebGLRenderTarget extends Stub { constructor(w, h) { super(); this.texture = {}; this.width = w; this.height = h; } setSize() {} }

/* Ear clipping, so sector triangulation can actually be exercised rather
   than stubbed out to nothing. Enough for the simple polygons a floor
   plan produces. */
export const ShapeUtils = {
  triangulateShape(contour) {
    const n = contour.length;
    if (n < 3) return [];
    const idx = [...Array(n).keys()];
    const area = (a, b, c) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    let signed = 0;
    for (let i = 0, j = n - 1; i < n; j = i++) signed += contour[j].x * contour[i].y - contour[i].x * contour[j].y;
    if (signed < 0) idx.reverse();
    const out = [];
    let guard = 0;
    while (idx.length > 3 && guard++ < n * n + 16) {
      let clipped = false;
      for (let i = 0; i < idx.length; i++) {
        const a = contour[idx[(i + idx.length - 1) % idx.length]];
        const b = contour[idx[i]];
        const c = contour[idx[(i + 1) % idx.length]];
        if (area(a, b, c) <= 0) continue;
        let inside = false;
        for (let k = 0; k < idx.length; k++) {
          const p = contour[idx[k]];
          if (p === a || p === b || p === c) continue;
          if (area(a, b, p) >= 0 && area(b, c, p) >= 0 && area(c, a, p) >= 0) { inside = true; break; }
        }
        if (inside) continue;
        out.push([idx[(i + idx.length - 1) % idx.length], idx[i], idx[(i + 1) % idx.length]]);
        idx.splice(i, 1);
        clipped = true;
        break;
      }
      if (!clipped) break;
    }
    if (idx.length === 3) out.push([idx[0], idx[1], idx[2]]);
    return out;
  },
};
