/* =====================================================================
   MEWD Editor — the map's own textures
   =====================================================================

   At the user's request, a TEXTURE EDITOR, in the way SLADE's is one: a
   new texture is a stack of LAYERS drawn onto a canvas of its own size,
   and each layer is a picture, either one of the game's own textures or
   an image imported from a file. Each layer can be:

     - placed at an offset
     - scaled
     - turned by quarter turns
     - flipped
     - tiled or drawn once
     - tinted, by multiplying in a colour
     - blended over what is under it, or multiplied, screened or added
     - faded

   Doom composed its wall textures out of patches the same way.

   A texture made here lives IN THE MAP (doc.textures), not in the game.
   It is drawn again every time the map is opened, in the editor and in
   a test run, and handed to the game's TextureBank under its own name
   (see TextureBank.add in js/textures.js), so every surface can wear it
   like any other texture. A layer that uses a game texture is drawn
   from the texture the bank already has, in the art palette the bank
   has it in, so a map's textures match the game's.

   Nothing here runs without a canvas, so the smoke test checks only the
   shape of a definition (checkTexture), and the browser draws it.
   ===================================================================== */

/* how big a map texture may be, each way, in pixels */
export const TEX_MAX = 512;
/* the blend modes a layer can use, by the name the canvas knows them by */
export const BLENDS = { normal: 'source-over', multiply: 'multiply', screen: 'screen', add: 'lighter', overlay: 'overlay' };

/** A texture's name, as the bank keys it: capitals, digits, _ and -. */
export const cleanName = n => String(n || '').toUpperCase().replace(/[^A-Z0-9_-]/g, '').slice(0, 16);

/** A new texture: one layer of `from`, the size of that picture. */
export function newTexture(name, from = 'GRIDWALL', size = [128, 128]) {
  return {
    name: cleanName(name), w: size[0], h: size[1],
    /* how many world units it spans, which is its size in pixels unless
       it says otherwise — the game's rule, one texel to one unit */
    worldW: size[0], worldH: size[1],
    layers: [newLayer(from)],
  };
}
export function newLayer(tex = 'GRIDWALL') {
  return { tex, image: null, x: 0, y: 0, sx: 1, sy: 1, rot: 0, flipX: false, flipY: false,
           tile: true, tint: '#ffffff', blend: 'normal', alpha: 1, hidden: false };
}

/** What is wrong with a definition, or null. */
export function checkTexture(def, builtIn = new Set()) {
  if (!def || !cleanName(def.name)) return 'it has no name';
  if (builtIn.has(def.name)) return `${def.name} is one of the game's own textures`;
  if (!(def.w >= 1 && def.w <= TEX_MAX && def.h >= 1 && def.h <= TEX_MAX)) return `it must be 1 to ${TEX_MAX} pixels each way`;
  if (!Array.isArray(def.layers)) return 'it has no layers';
  return null;
}

/* ---------------------------------------------------------------------
   drawing one
   --------------------------------------------------------------------- */
const images = new Map();
/** An imported picture, decoded once. */
function loadImage(src) {
  let p = images.get(src);
  if (!p) {
    p = new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = src; });
    images.set(src, p);
  }
  return p;
}

/** The picture a layer draws, or null. */
async function sourceOf(bank, layer) {
  if (layer.image) { try { return await loadImage(layer.image); } catch (e) { return null; } }
  const e = layer.tex && bank.map?.get(layer.tex);
  /* its own picture: an animated one from the pack is showing some
     other frame just now (js/texpack.js) */
  return e?.own || e?.texture?.image || null;
}

/**
 * Draw a texture. Returns a canvas `def.w` by `def.h`.
 * @param bank  the TextureBank the game textures are drawn from
 */
export async function composeTexture(bank, def) {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.min(TEX_MAX, def.w | 0));
  c.height = Math.max(1, Math.min(TEX_MAX, def.h | 0));
  const g = c.getContext('2d');
  g.imageSmoothingEnabled = false;
  for (const L of def.layers || []) {
    if (L.hidden) continue;
    const src = await sourceOf(bank, L);
    if (!src) continue;
    /* THE LAYER ON ITS OWN SHEET first, so its tint touches only it */
    const sheet = document.createElement('canvas');
    sheet.width = c.width; sheet.height = c.height;
    const s = sheet.getContext('2d');
    s.imageSmoothingEnabled = false;
    const sw = src.width * (L.sx || 1), sh = src.height * (L.sy || 1);
    const place = (x, y) => {
      s.save();
      s.translate(x + sw / 2, y + sh / 2);
      s.rotate(((L.rot | 0) % 4) * Math.PI / 2);
      s.scale(L.flipX ? -1 : 1, L.flipY ? -1 : 1);
      s.drawImage(src, -sw / 2, -sh / 2, sw, sh);
      s.restore();
    };
    if (L.tile && sw >= 1 && sh >= 1) {
      /* tiled: every copy that touches the canvas, from the offset out */
      const ox = ((L.x % sw) + sw) % sw - sw, oy = ((L.y % sh) + sh) % sh - sh;
      for (let y = oy; y < c.height; y += sh) for (let x = ox; x < c.width; x += sw) place(x, y);
    } else place(L.x || 0, L.y || 0);
    if (L.tint && L.tint.toLowerCase() !== '#ffffff') {
      s.globalCompositeOperation = 'multiply';
      s.fillStyle = L.tint;
      s.fillRect(0, 0, c.width, c.height);
      /* and the layer's own shape back, which the fill painted over */
      s.globalCompositeOperation = 'destination-in';
      const again = document.createElement('canvas');
      again.width = c.width; again.height = c.height;
      const a = again.getContext('2d');
      a.imageSmoothingEnabled = false;
      a.drawImage(sheet, 0, 0);
      s.drawImage(again, 0, 0);
      s.globalCompositeOperation = 'source-over';
    }
    g.globalAlpha = Math.max(0, Math.min(1, L.alpha ?? 1));
    g.globalCompositeOperation = BLENDS[L.blend] || 'source-over';
    g.drawImage(sheet, 0, 0);
    g.globalAlpha = 1;
    g.globalCompositeOperation = 'source-over';
  }
  return c;
}

/** Whether a picture has any holes in it — a grating does, a wall does
 *  not — which is what decides whether the game cuts it out. */
function hasHoles(canvas) {
  const d = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
  for (let i = 3; i < d.length; i += 4) if (d[i] < 128) return true;
  return false;
}

/**
 * Draw every texture a map has and put them in the bank under their own
 * names — repainting any the bank already has, so what is wearing one
 * changes with it. Returns the names.
 */
export async function registerTextures(bank, defs = [], builtIn = null) {
  const names = [];
  /* A TEXTURE MADE OF ANOTHER OF THE MAP'S is drawn after it, whatever
     order the map lists them in — or it is drawn from nothing */
  const byName = new Map(defs.map(d => [d.name, d]));
  const order = [], state = new Map();
  const visit = d => {
    if (state.get(d.name) === 2) return;
    if (state.get(d.name) === 1) return;           // a loop: drawn as it stands
    state.set(d.name, 1);
    for (const L of d.layers || []) if (L.tex && byName.has(L.tex) && L.tex !== d.name) visit(byName.get(L.tex));
    state.set(d.name, 2);
    order.push(d);
  };
  for (const d of defs) visit(d);
  for (const def of order) {
    if (checkTexture(def, builtIn || new Set())) continue;
    const canvas = await composeTexture(bank, def);
    bank.add(def.name, { w: canvas.width, h: canvas.height, toCanvas: () => canvas },
             { w: def.worldW || canvas.width, h: def.worldH || canvas.height, masked: hasHoles(canvas) });
    names.push(def.name);
  }
  return names;
}
