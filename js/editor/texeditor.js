/* =====================================================================
   MEWD Editor — the texture editor
   =====================================================================

   SLADE's texture editor, for the map's own textures (the drawing is
   js/editor/texcompose.js). A dialog over the workspace:

     left    the texture, large, point sampled, and tiled three by three
             if asked, so a seam shows where it will show on a wall
     right   its name and size, the layers from the top of the stack
             down, and the selected layer's every setting

   Every change redraws the preview at once. SAVE puts the texture in
   the map as one undoable edit, and every surface wearing it changes
   with it; CANCEL leaves the map as it was.
   ===================================================================== */

import { composeTexture, newTexture, newLayer, cleanName, checkTexture, BLENDS, TEX_MAX } from './texcompose.js';

const h = (tag, attrs = {}, ...kids) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat()) if (c !== null && c !== undefined && c !== false) el.append(c.nodeType ? c : String(c));
  return el;
};

/**
 * Open the editor on a texture of the map (or a new one).
 * @param ed    the Editor
 * @param name  the map texture to edit, or null for a new one
 * @param from  for a new one, the game texture its first layer is
 */
/* A NEW TEXTURE FROM ANOTHER keeps its SHAPE and the size it is on a
   wall. A picture bigger than a map texture may be (TEX_MAX) is brought
   down evenly — a 512 by 1373 cliff was made 512 square when each side
   was capped on its own — and the layer is scaled to fill it; and the
   world size is the source's, so a pack texture drawn at twice Doom's
   resolution covers the same wall after as before. */
export function fromTexture(ed, from, src, img) {
  const w = img?.width || 128, h = img?.height || 128;
  const k = Math.min(1, TEX_MAX / Math.max(w, h));
  const def = newTexture(uniqueName(ed, from), from, [Math.max(1, Math.round(w * k)), Math.max(1, Math.round(h * k))]);
  if (k < 1) { def.layers[0].sx = def.w / w; def.layers[0].sy = def.h / h; }
  if (src?.w && src?.h) { def.worldW = src.w; def.worldH = src.h; }
  return def;
}

export function openTextureEditor(ed, name = null, from = 'GRIDWALL') {
  document.getElementById('ed-texed')?.remove();
  const existing = name ? (ed.doc.textures || []).find(t => t.name === name) : null;
  const src = ed.bank.map.get(from);
  const size = src?.own || src?.texture?.image;
  const def = existing ? JSON.parse(JSON.stringify(existing)) : fromTexture(ed, from, src, size);
  const original = existing ? existing.name : null;
  let sel = def.layers.length - 1;
  let tiled = true;

  const preview = h('canvas', { class: 'ed-tx-canvas' });
  const side = h('div', { class: 'ed-tx-side' });
  const err = h('div', { class: 'ed-tx-err' });
  const box = h('div', { class: 'ed-tx-box' },
    h('div', { class: 'ed-tx-head' }, h('b', {}, 'Texture editor'),
      h('span', { class: 'ed-note' }, ' — layers of the game\'s textures and your own images, drawn into a texture of this map')),
    h('div', { class: 'ed-tx-body' },
      h('div', { class: 'ed-tx-view' }, preview,
        h('label', { class: 'ed-tx-tile' }, h('input', { type: 'checkbox', checked: true, onchange: e => { tiled = e.target.checked; redraw(); } }), ' tile 3 × 3')),
      side),
    h('div', { class: 'ed-tx-foot' }, err,
      h('button', { class: 'ed-btn', onclick: () => close() }, 'Cancel'),
      h('button', { class: 'ed-btn play', onclick: () => save() }, 'Save texture')));
  const overlay = h('div', { id: 'ed-texed', onmousedown: e => { if (e.target === overlay) close(); } }, box);
  ed.root.append(overlay);

  const close = () => { overlay.remove(); removeEventListener('keydown', onKey, true); };
  /* Escape asks before throwing away layers that were never saved */
  const startedAs = JSON.stringify(def);
  const onKey = e => {
    if (e.key !== 'Escape') return;
    e.stopPropagation();
    if (JSON.stringify(def) !== startedAs && !confirm('Close the texture editor without saving?')) return;
    close();
  };
  addEventListener('keydown', onKey, true);

  function save() {
    def.name = cleanName(def.name);
    const clash = (ed.doc.textures || []).some(t => t.name === def.name && t.name !== original);
    const why = checkTexture(def, ed.builtInTextures) || (clash ? `the map already has a ${def.name}` : null);
    if (why) { err.textContent = `Not saved: ${why}.`; return; }
    ed.edit(`texture ${def.name}`, d => {
      d.textures = d.textures || [];
      const i = d.textures.findIndex(t => t.name === original);
      if (i >= 0) d.textures[i] = def; else d.textures.push(def);
      /* a renamed texture takes everything that wore the old name with it */
      if (original && original !== def.name) renameUses(d, original, def.name);
    }, { tidy: false });
    ed.say(`saved texture ${def.name}`);
    close();
  }

  /* ------------------------------------------------------------------ */
  let drawing = 0;
  async function redraw() {
    const n = ++drawing;
    const c = await composeTexture(ed.bank, def);
    if (n !== drawing) return;
    const k = tiled ? 3 : 1;
    const room = 460;
    const zoom = Math.max(1, Math.floor(room / (Math.max(c.width, c.height) * k))) || 1;
    const w = c.width * k, hh = c.height * k;
    const scale = Math.min(zoom, room / Math.max(w, hh));
    preview.width = w; preview.height = hh;
    preview.style.width = `${w * scale}px`; preview.style.height = `${hh * scale}px`;
    const g = preview.getContext('2d');
    g.imageSmoothingEnabled = false;
    g.clearRect(0, 0, w, hh);
    for (let y = 0; y < k; y++) for (let x = 0; x < k; x++) g.drawImage(c, x * c.width, y * c.height);
    if (tiled) { g.strokeStyle = '#ffb45466'; g.strokeRect(c.width + 0.5, c.height + 0.5, c.width - 1, c.height - 1); }
  }

  const num = (v, set, step = 1, min = -9999, max = 9999) => h('input', { type: 'number', value: v, step,
    oninput: e => { const x = parseFloat(e.target.value); if (Number.isFinite(x)) { set(Math.max(min, Math.min(max, x))); redraw(); } } });
  const row = (label, ...el) => h('div', { class: 'ed-row' + (el.length > 1 ? ' two' : '') }, h('label', {}, label), ...el);
  const chk = (v, set) => h('input', { type: 'checkbox', ...(v ? { checked: true } : {}), onchange: e => { set(e.target.checked); redraw(); } });

  function renderSide() {
    side.textContent = '';
    side.append(
      row('Name', h('input', { type: 'text', value: def.name, oninput: e => { def.name = cleanName(e.target.value); } })),
      row('Pixels', num(def.w, v => { def.w = v | 0; }, 8, 1, TEX_MAX), num(def.h, v => { def.h = v | 0; }, 8, 1, TEX_MAX)),
      row('World units', num(def.worldW ?? def.w, v => { def.worldW = v; }, 8, 1, 8192), num(def.worldH ?? def.h, v => { def.worldH = v; }, 8, 1, 8192)),
      h('h4', {}, 'Layers — top first'),
      h('div', { class: 'ed-tx-layers' }, ...def.layers.map((L, i) => i).reverse().map(i => {
        const L = def.layers[i];
        return h('div', { class: 'ed-listrow' + (i === sel ? ' on' : ''), onclick: () => { sel = i; renderSide(); } },
          h('span', {}, `${L.hidden ? '◌' : '●'} ${L.image ? 'image' : L.tex}`),
          h('small', {}, `${L.blend}${L.alpha < 1 ? ` ${Math.round(L.alpha * 100)}%` : ''}`));
      })),
      h('div', { class: 'ed-small-btns' },
        h('select', { class: 'ed-tx-add', onchange: e => { if (!e.target.value) return; def.layers.push(newLayer(e.target.value)); sel = def.layers.length - 1; renderSide(); redraw(); } },
          h('option', { value: '' }, '+ layer from a texture…'), ...ed.textureNames.filter(n => n !== def.name).map(n => h('option', { value: n }, n))),
        h('button', { class: 'ed-btn', title: 'A picture from a file, as a layer', onclick: () => importImage() }, '+ Image…')),
    );
    const L = def.layers[sel];
    if (!L) { redraw(); return; }
    const move = dir => { const j = sel + dir; if (j < 0 || j >= def.layers.length) return; [def.layers[sel], def.layers[j]] = [def.layers[j], def.layers[sel]]; sel = j; renderSide(); redraw(); };
    side.append(
      h('h4', {}, `Layer ${sel + 1}`),
      h('div', { class: 'ed-small-btns' },
        h('button', { class: 'ed-btn', onclick: () => move(1) }, '▲ Up'),
        h('button', { class: 'ed-btn', onclick: () => move(-1) }, '▼ Down'),
        h('button', { class: 'ed-btn', onclick: () => { L.hidden = !L.hidden; renderSide(); redraw(); } }, L.hidden ? 'Show' : 'Hide'),
        h('button', { class: 'ed-btn', onclick: () => { def.layers.splice(sel + 1, 0, JSON.parse(JSON.stringify(L))); sel++; renderSide(); redraw(); } }, 'Copy'),
        h('button', { class: 'ed-btn', onclick: () => { def.layers.splice(sel, 1); sel = Math.max(0, sel - 1); renderSide(); redraw(); } }, 'Delete')),
      L.image ? row('Picture', h('span', { class: 'ed-note' }, 'an imported image'))
        : row('Texture', h('select', { onchange: e => { L.tex = e.target.value; renderSide(); redraw(); } },
            ...ed.textureNames.filter(n => n !== def.name).map(n => h('option', { value: n, ...(n === L.tex ? { selected: true } : {}) }, n)))),
      row('Offset x / y', num(L.x, v => { L.x = v; }), num(L.y, v => { L.y = v; })),
      row('Scale x / y', num(L.sx, v => { L.sx = v; }, 0.25, 0.05, 16), num(L.sy, v => { L.sy = v; }, 0.25, 0.05, 16)),
      row('Turn', h('select', { onchange: e => { L.rot = +e.target.value; redraw(); } },
        ...[0, 1, 2, 3].map(r => h('option', { value: r, ...(r === (L.rot | 0) ? { selected: true } : {}) }, `${r * 90}°`)))),
      row('Flip x / y', chk(L.flipX, v => { L.flipX = v; }), chk(L.flipY, v => { L.flipY = v; })),
      row('Tile', chk(L.tile, v => { L.tile = v; })),
      row('Tint', h('input', { type: 'color', value: L.tint || '#ffffff', oninput: e => { L.tint = e.target.value; redraw(); } })),
      row('Blend', h('select', { onchange: e => { L.blend = e.target.value; renderSide(); redraw(); } },
        ...Object.keys(BLENDS).map(b => h('option', { value: b, ...(b === L.blend ? { selected: true } : {}) }, b)))),
      row('Opacity', h('input', { type: 'range', min: 0, max: 1, step: 0.05, value: L.alpha ?? 1,
        oninput: e => { L.alpha = +e.target.value; redraw(); } })),
    );
    redraw();
  }

  function importImage() {
    const input = h('input', { type: 'file', accept: 'image/*' });
    input.onchange = () => {
      const f = input.files?.[0];
      if (!f) return;
      const r = new FileReader();
      r.onload = () => {
        const img = new Image();
        img.onload = () => {
          /* a big photograph is brought down to the largest a texture may
             be, so the map does not carry megabytes it cannot use */
          const k = Math.min(1, TEX_MAX / Math.max(img.width, img.height));
          const c = document.createElement('canvas');
          c.width = Math.max(1, Math.round(img.width * k)); c.height = Math.max(1, Math.round(img.height * k));
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          const L = { ...newLayer(null), image: c.toDataURL('image/png') };
          if (def.layers.length === 1 && def.layers[0].tex === from && !existing) { def.w = c.width; def.h = c.height; def.worldW = c.width; def.worldH = c.height; }
          def.layers.push(L);
          sel = def.layers.length - 1;
          renderSide();
        };
        img.src = r.result;
      };
      r.readAsDataURL(f);
    };
    input.click();
  }

  renderSide();
}

/** A name the map does not have yet, from a texture's. */
function uniqueName(ed, from) {
  const base = cleanName(from).slice(0, 12) || 'TEX';
  for (let i = 1; ; i++) {
    const n = `${base}_${i}`;
    if (!ed.bank.map.has(n) && !(ed.doc.textures || []).some(t => t.name === n)) return n;
  }
}

/** Every surface and layer that wore one name, wearing another. */
function renameUses(d, from, to) {
  const swap = o => { for (const k of Object.keys(o)) if (/Tex$|^tex$/.test(k) && o[k] === from) o[k] = to; };
  d.sectors.forEach(swap); d.props.forEach(swap); Object.values(d.lines || {}).forEach(swap);
  for (const t of d.textures || []) for (const L of t.layers || []) if (L.tex === from) L.tex = to;
}
