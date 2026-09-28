/* =====================================================================
   MEWD Editor — the bars round the views
   =====================================================================

   The top bar (menus, modes, the grid, PLAY), the panel down the right
   (the inspector, the texture browser, the thing palette, the map's own
   settings and its problems) and the status line along the bottom.

   THE INSPECTOR EDITS EVERYTHING SELECTED AT ONCE. It shows the first
   of them and writes a changed field to all of them, which is how a
   Doom editor's sector dialog works with twenty sectors picked — and
   every write is one `ed.edit`, so it undoes like anything else.
   ===================================================================== */

import { PACK, PACK_SKIES, animOf, ownImage } from '../texpack.js';
import { THING_TYPES, problemsOf, ringOf, signedArea, COLOR_PARTS, LINEDEF_THICK, LINEDEF_H } from './doc.js';
import { openTextureEditor } from './texeditor.js';
import { MODES, GRIDS, GRID_MAX, SHAPES, SIDES_MIN, SIDES_MAX, brightOf, isInside } from './editor.js';
import { PRESETS, SCATTER_TYPES, PLANT_KINDS, PLANT_SETS, SCATTER_MAX } from './scatter.js';
import { plantColour } from './view2d.js';

/* the mode buttons' own short names */
const SHORT = { vertices: 'Verts', lines: 'Lines', sectors: 'Sectors', things: 'Things', props: 'Props', draw: 'Draw', rect: 'Shape', scatter: 'Scatter' };

const h = (tag, attrs = {}, ...kids) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat()) if (c !== null && c !== undefined && c !== false) el.append(c.nodeType ? c : String(c));
  return el;
};

/** Append, leaving out what a condition left empty — `append` would
 *  write "null" into the panel. */
const put = (el, ...kids) => el.append(...kids.flat(Infinity).filter(k => k !== null && k !== undefined && k !== false && k !== ''));

/** A texture's picture, small, for a swatch. Drawn from the bank's own
 *  canvas, so it is what the wall will show. */
const PACK_BY_NAME = new Map(PACK.map(p => [p.name, p]));
/** The browser's three shelves, in order. */
export const TEX_SHAPES = ['Animated', 'Square', 'Non-square'];
/** Which shelf a texture goes on: animated if it is in a run, else
 *  square or not by the size it is on a wall. */
export function shapeOf(ed, name) {
  if (animOf(name)) return 'Animated';
  const e = PACK_BY_NAME.get(name) || ed.bank?.map.get(name);
  return e && e.w !== e.h ? 'Non-square' : 'Square';
}
function swatch(ed, name, size = 22) {
  const c = h('canvas', { width: size, height: size });
  /* a pack texture still on its way is a blank, not MISSING's magenta */
  const e = name && (ed.bank.map.get(name) || (PACK_BY_NAME.has(name) ? null : ed.bank.get(name)));
  if (name === 'SKY') {
    /* the sky is not a picture on the ceiling, it is the sky: the map's
       own, horizon to overhead */
    const sky = ed.doc.world?.sky || {};
    const g = c.getContext('2d'), gr = g.createLinearGradient(0, size, 0, 0);
    gr.addColorStop(0, sky.horizon || '#1d9a48'); gr.addColorStop(0.5, sky.mid || '#06301a'); gr.addColorStop(1, sky.zenith || '#000');
    g.fillStyle = gr; g.fillRect(0, 0, size, size);
  } else if (e?.texture?.image) {
    /* IN ITS OWN SHAPE: a tall door is tall in the browser, a strip of
       treeline is a strip, fitted to the square and centred, and never
       squashed into a square it is not */
    const g = c.getContext('2d');
    g.imageSmoothingEnabled = false;
    const img = ownImage(e);
    const aw = e.w || img.width, ah = e.h || img.height;
    const k = size / Math.max(aw, ah);
    const dw = Math.max(1, Math.round(aw * k)), dh = Math.max(1, Math.round(ah * k));
    g.drawImage(img, (size - dw) >> 1, (size - dh) >> 1, dw, dh);
  }
  return c;
}

export function buildUI(ed) {
  const root = ed.root;
  const ui = {};

  /* ------------------------------------------------------------------
     THE TOP BAR
     ------------------------------------------------------------------ */
  const menu = (label, items) => {
    const m = h('div', { class: 'ed-menu' });
    const btn = h('button', { class: 'ed-btn', onclick: e => {
      e.stopPropagation();
      const was = m.classList.contains('open');
      root.querySelectorAll('.ed-menu.open').forEach(x => x.classList.remove('open'));
      if (!was) m.classList.add('open');
    } }, label);
    const box = h('div', { class: 'items' });
    for (const it of items) {
      if (it === '-') { box.append(h('hr')); continue; }
      box.append(h('button', { onclick: () => { m.classList.remove('open'); it[2](); } }, h('span', {}, it[0]), h('kbd', {}, it[1] || '')));
    }
    m.append(btn, box);
    return m;
  };
  addEventListener('click', () => root.querySelectorAll('.ed-menu.open').forEach(x => x.classList.remove('open')));

  const modeBtns = {};
  const modes = Object.entries(MODES).map(([m, def]) => {
    const b = h('button', { class: 'ed-btn', title: `${def.name} (${def.key})`, onclick: () => ed.setMode(m) },
      SHORT[m] || def.name, h('kbd', {}, def.key));
    modeBtns[m] = b;
    return b;
  });

  /* THE SHAPE Shape mode (R) drags out, and how many sides a round one
     has — choosing one goes into Shape mode */
  const shapeSel = h('select', { title: 'The shape a drag draws in Shape mode (R)', onchange: e => ed.setShape(e.target.value) },
    ...Object.entries(SHAPES).map(([k, v]) => h('option', { value: k }, v.name)));
  const sidesIn = h('input', { type: 'number', class: 'ed-sides', min: SIDES_MIN, max: SIDES_MAX, step: 1, title: 'Sides of a round shape, or a star\'s points',
    onchange: e => { const n = Math.round(+e.target.value); if (n >= SIDES_MIN && n <= SIDES_MAX) ed.setShape(ed.shape, n); else refreshBar(); } });

  /* THE GRID: the ladder, a size of your own if you have one, and
     Custom… to type one — any whole number from 1 to GRID_MAX */
  const customOpt = h('option', { value: '' }, '');
  const gridSel = h('select', { title: 'Grid size  [ ]  — Custom… for any size', onchange: e => {
    const v = e.target.value;
    if (v === 'custom') {
      const got = prompt(`Grid size, in map units (1–${GRID_MAX})`, String(ed.grid));
      const n = Math.round(+got);
      if (got !== null && n >= 1 && n <= GRID_MAX) ed.setGrid(n);
      else { if (got !== null) ed.say(`a grid is 1 to ${GRID_MAX} units`); refreshBar(); }
      return;
    }
    ed.setGrid(+v);
  } },
    ...GRIDS.map(g => h('option', { value: g }, `grid ${g}`)), customOpt, h('option', { value: 'custom' }, 'Custom…'));
  const snapBtn = h('button', { class: 'ed-btn', title: 'Snap to grid (G)', onclick: () => ed.setSnap() }, h('span', {}, 'Snap'), h('kbd', {}, 'G'));
  /* THE LAYER BEING DRAWN ON — see LAYERS in js/editor/doc.js: down a
     storey, which one, up a storey */
  const layerLbl = h('span', { class: 'ed-layer', title: 'The layer being edited: 0 is the ground, 1 the storey on it, and so on. Alt+PgUp / Alt+PgDn' }, 'L0');
  const layerBox = h('span', { class: 'ed-layers' },
    h('button', { class: 'ed-btn', title: 'Layer down (Alt+PgDn)', onclick: () => ed.setLayer(ed.layer - 1) }, '▼'),
    layerLbl,
    h('button', { class: 'ed-btn', title: 'Layer up (Alt+PgUp)', onclick: () => ed.setLayer(ed.layer + 1) }, '▲'));
  /* THE LEFT PANEL (textures, things, scatter, map) can be put away for
     more room to draw; the inspector on the right stays. Remembered. */
  let tabsHidden = false;
  try { tabsHidden = localStorage.getItem('gss-edit:tabs') === 'off'; } catch (e) { /* private mode */ }
  const tabsBtn = h('button', { class: 'ed-btn', title: 'Show or hide the left panel: textures, things, scatter, map', onclick: () => {
    tabsHidden = !tabsHidden;
    try { localStorage.setItem('gss-edit:tabs', tabsHidden ? 'off' : 'on'); } catch (e) { /* private mode */ }
    refreshBar();
  } }, 'Tabs');
  const layoutBtns = {
    combined: h('button', { class: 'ed-btn', title: 'Both at once: 3D with the plan inset (Tab swaps them)', onclick: () => ed.setLayout(ed.layout === 'combined' ? 'combined2d' : 'combined') }, 'Combined'),
    only2d: h('button', { class: 'ed-btn', title: '2D only (Tab)', onclick: () => ed.setLayout('only2d') }, '2D'),
    split: h('button', { class: 'ed-btn', title: 'Side by side', onclick: () => ed.setLayout('split') }, 'Split'),
    only3d: h('button', { class: 'ed-btn', title: '3D only (Tab)', onclick: () => ed.setLayout('only3d') }, '3D'),
  };

  const top = h('div', { id: 'ed-top' },
    h('span', { class: 'brand' }, 'MEWD Editor'),
    menu('File', [
      ['New map', '', () => ed.fileNew(false)],
      ['New from THE GRID', '', () => ed.fileNew(true)],
      ['Open demo: a new MAZE', '', () => ed.fileDemo()],
      ['Open THE SPRAWL', '', () => ed.fileDemo('sprawl')],
      ['Open a new JESSE (PvP maze)', '', () => ed.fileDemo('jesse')],
      '-',
      ['Open…', 'Ctrl+O', () => ed.fileOpen()],
      ['Save as file', 'Ctrl+S', () => ed.fileSave()],
      '-',
      ['Test map', 'F5', () => ed.play()],
      ['Export Godot scene…', '', () => ed.exportGodot()],
      ['Back to the terminal', '', () => { ed.autosave(); location.href = location.pathname; }],
    ]),
    menu('Edit', [
      ['Undo', 'Ctrl+Z', () => ed.undo()],
      ['Redo', 'Ctrl+Y', () => ed.redo()],
      '-',
      ['Delete selection', 'Del', () => ed.deleteSel()],
      ['Clear selection', 'Esc', () => ed.clearSel()],
      '-',
      ['Copy', 'Ctrl+C', () => ed.copySel()],
      ['Paste at the cursor', 'Ctrl+V', () => ed.paste()],
      ['Paste in place (onto another layer: a storey up)', 'Ctrl+Shift+V', () => ed.paste({ inPlace: true })],
      ['Layer up', 'Alt+PgUp', () => ed.setLayer(ed.layer + 1)],
      ['Layer down', 'Alt+PgDn', () => ed.setLayer(ed.layer - 1)],
      ['Select all', 'Ctrl+A', () => ed.selectAllInMode?.()],
      '-',
      ['Snap selection to grid', 'Shift+G', () => ed.snapSelToGrid()],
      ['Grid finer', '[', () => ed.gridStep(-1)],
      ['Grid coarser', ']', () => ed.gridStep(1)],
      ['Snap on / off', 'G', () => ed.setSnap()],
      '-',
      ['Frame the map', 'F', () => ed.emit('frame')],
    ]),
    menu('Help', [
      ['2D: drag to move, box-select on empty', '', () => {}],
      ['2D: middle / right drag pans, wheel zooms', '', () => {}],
      ['D: click points, click the first to close', '', () => {}],
      ['R: drag a rectangle into a sector', '', () => {}],
      ['X: drag a circle to scatter the chosen mix', '', () => {}],
      ['Every mode works in the 3D view too', '', () => {}],
      ['Q: visual mode — mouselook, WASD, crosshair', '', () => {}],
      ['Ctrl+wheel: sector brightness (2D and 3D)', '', () => {}],
      ['Wheel in 3D: raise/lower floor or ceiling', '', () => {}],
      ['Right-click: properties · right-drag: move', '', () => {}],
      ['Insert: thing / vertex at the cursor', '', () => {}],
      ['Ctrl+C / Ctrl+V: copy / paste selection', '', () => {}],
      ['PgUp/PgDn: floor ±8 (Shift: ceiling)', '', () => {}],
      ['[ ] grid size · G snap · Shift+G snap selection', '', () => {}],
      ['Alt+PgUp / Alt+PgDn: the layer up or down (storeys)', '', () => {}],
      ['Corners snap to vertices (□), lines (◇), then grid', '', () => {}],
      ['Arrows nudge a grid step (1 with snap off), Shift ×4', '', () => {}],
      ['Tab swaps the big view and the inset', '', () => {}],
      ['3D: hold right mouse to look, WASD QE fly', '', () => {}],
      ['3D: wheel raises the floor/ceiling under it', '', () => {}],
      ['3D: click a texture to paint the pick', '', () => {}],
      ['3D: Ctrl+C copies a texture, Ctrl+V pastes', '', () => {}],
      ['3D: B toggles fullbright, H the grid, F goes to start', '', () => {}],
    ]),
    h('span', { class: 'sep' }),
    ...modes,
    shapeSel, sidesIn,
    h('span', { class: 'sep' }),
    gridSel, snapBtn,
    h('span', { class: 'sep' }),
    layerBox,
    h('span', { class: 'sep' }),
    tabsBtn, layoutBtns.combined, layoutBtns.split, layoutBtns.only2d, layoutBtns.only3d,
    h('span', { class: 'spacer' }),
    h('button', { class: 'ed-btn play', title: 'Test the map (F5)', onclick: () => ed.play() }, '▶ PLAY', h('kbd', {}, 'F5')),
  );

  /* ------------------------------------------------------------------
     THE VIEWS
     ------------------------------------------------------------------ */
  ui.canvas2d = h('canvas', { tabindex: 0 });
  ui.canvas3d = h('canvas', { tabindex: 0 });
  ui.help2d = h('div', { class: 'help' });
  ui.help3d = h('div', { class: 'help' },
    'Q visual mode · hold RMB look + WASD fly · every mode works here\nwheel height · Ctrl+wheel brightness · Ctrl+C/V texture · B fullbright · H grid · Shift+A align');
  /* THE PLAN'S VIEWS: the map as drawn, or every sector shaded by its
     brightness, floor or ceiling — Doom Builder's brightness view */
  const planSel = h('select', { class: 'ed-planview', title: 'What the plan shades sectors by (Doom Builder\'s brightness view)',
    onchange: e => { ed.planView = e.target.value; ed.emit('grid'); } },
    h('option', { value: 'normal' }, 'Plan: normal'), h('option', { value: 'light' }, 'Plan: brightness'),
    h('option', { value: 'floor' }, 'Plan: floor heights'), h('option', { value: 'ceil' }, 'Plan: ceilings'));
  ui.planSel = planSel;
  const wrap2d = h('div', { id: 'ed-2d-wrap', class: 'ed-view' }, ui.canvas2d, h('div', { class: 'tag' }, 'MAP  2D'), planSel, ui.help2d);
  const wrap3d = h('div', { id: 'ed-3d-wrap', class: 'ed-view' }, ui.canvas3d, h('div', { class: 'tag' }, 'VISUAL  3D'), ui.help3d,
    h('div', { class: 'ed-cross' }));
  ui.wrap2d = wrap2d; ui.wrap3d = wrap3d;
  /* in the combined workspace, a button on the inset to swap it big */
  for (const w of [wrap2d, wrap3d]) w.append(h('button', { class: 'ed-swap', title: 'Swap the big view and the inset (Tab)',
    onclick: () => ed.setLayout(ed.layout === 'combined' ? 'combined2d' : 'combined') }, '⤢'));
  const views = h('div', { id: 'ed-views', class: ed.layout }, wrap2d, wrap3d);

  /* ------------------------------------------------------------------
     THE SIDE PANEL
     ------------------------------------------------------------------ */
  const panes = {
    insp: h('div', { class: 'ed-pane ed-insp on' }),
    tex: h('div', { class: 'ed-pane' }),
    things: h('div', { class: 'ed-pane' }),
    scatter: h('div', { class: 'ed-pane ed-insp' }),
    map: h('div', { class: 'ed-pane ed-insp' }),
  };
  const tabBtns = {};
  /* TWO PANELS, at the user's request: the INSPECTOR on its own down the
     right, always showing what is selected, and the tabs — textures,
     things, scatter, the map — down the left. Asking for the inspector
     is only a flash of it now: it is already there. */
  const showTab = t => {
    if (t === 'insp') { ui.flashInsp?.(); return; }
    for (const [k, p] of Object.entries(panes)) if (k !== 'insp') p.classList.toggle('on', k === t);
    for (const [k, b] of Object.entries(tabBtns)) b.classList.toggle('on', k === t);
    ui.tab = t;
    if (t === 'map') renderMap();
    if (t === 'scatter') renderScatter();
    if (t === 'things') renderThings();
  };
  ui.showTab = showTab;
  const tabs = h('div', { class: 'ed-tabs' },
    ...[['tex', 'Textures'], ['things', 'Things'], ['scatter', 'Scatter'], ['map', 'Map']].map(([k, n]) =>
      (tabBtns[k] = h('button', { onclick: () => showTab(k) }, n))));
  const side = h('div', { id: 'ed-side' }, tabs, h('div', { style: 'min-height:0;display:grid' }, panes.tex, panes.things, panes.scatter, panes.map));
  showTab('tex');
  const inspSide = h('div', { id: 'ed-inspside' }, h('div', { class: 'ed-panehead' }, 'Inspector'), panes.insp);

  /* ------------------------------------------------------------------
     THE STATUS LINE
     ------------------------------------------------------------------ */
  const st = {
    mode: h('span'), grid: h('span'), pos: h('span'), sel: h('span'), probs: h('span'), msg: h('span', { class: 'msg' }),
    info: h('span', { class: 'info' }),
  };
  const status = h('div', { id: 'ed-status' }, st.mode, st.grid, st.pos, st.sel, st.info, st.probs, st.msg);
  /* THE INFO BAR, Doom Builder's panel along the bottom: what is under
     the mouse, and what it is — in either view */
  ed.on('doc', () => showHover(ed.hovered));
  ed.on('hover', hv => showHover(hv));
  const showHover = hv => {
    const d = ed.doc;
    let t = '';
    if (hv?.kind === 'sector') {
      const x = d.sectors.find(q => q.id === hv.id);
      if (x) t = `<b>Sector ${x.id}</b>${x.name ? ` ${x.name}` : ''} · ${isInside(x) ? 'inside' : 'outside'} · floor <b>${x.floor ?? 0}</b> · ${isInside(x) ? 'ceiling' : 'walls'} <b>${x.ceil ?? 0}</b> · brightness <b>${brightOf(x)}</b> · ${x.floorTex}${isInside(x) ? ` / ${x.ceilTex}` : ''}`;
    } else if (hv?.kind === 'line') {
      const l = ed.lines().find(q => q.key === hv.id);
      const [a, b] = String(hv.id).split(',').map(Number);
      const va = d.vertices[a], vb = d.vertices[b];
      if (l && va && vb) t = `<b>${l.free ? 'Linedef' : 'Line'} ${hv.id}</b> · ${Math.round(Math.hypot(vb[0] - va[0], vb[1] - va[1]))} long · ${l.free ? 'on its own (a wall)' : l.sectors.length > 1 ? 'two-sided' : 'one-sided'}${d.lines[hv.id]?.opening ? ' · doorway' : ''}`;
    } else if (hv?.kind === 'thing') {
      const x = d.things.find(q => q.id === hv.id);
      if (x) t = `<b>${x.type === 'PLANT' ? x.kind : THING_TYPES[x.type]?.name || x.type}</b> #${x.id} · ${Math.round(x.x)}, ${Math.round(x.y)} · ${Math.round(((x.angle || 0) * 180 / Math.PI) % 360)}°`;
    } else if (hv?.kind === 'vertex') {
      const v = d.vertices[hv.id];
      if (v) t = `<b>Vertex ${hv.id}</b> · ${v[0]}, ${v[1]}`;
    } else if (hv?.kind === 'prop') {
      const x = d.props.find(q => q.id === hv.id);
      if (x) t = `<b>Prop ${x.id}</b> · ${x.z0}–${x.z1} · ${x.tex}`;
    } else if (hv?.kind === 'scatter') {
      const x = d.scatters.find(q => q.id === hv.id);
      if (x) t = `<b>Scatter</b> ${x.name} · ${ed.compiled?.grown?.get(x.id)?.grown ?? '…'} grown`;
    }
    st.info.innerHTML = t;
  };
  const toast = h('div', { id: 'ed-toast' });

  const mainEl = h('div', { id: 'ed-main' }, side, views, inspSide);
  root.append(top, mainEl, status, toast);

  let toastT = 0;
  ui.flashInsp = () => { panes.insp.classList.remove('flash'); void panes.insp.offsetWidth; panes.insp.classList.add('flash'); };
  ui.toast = msg => {
    toast.textContent = msg; toast.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(() => toast.classList.remove('show'), 1800);
  };
  /* where the cursor is, exactly: a point snapped onto a diagonal line
     is not a whole number, and rounding it would be a lie */
  const coord = v => (Number.isInteger(v) ? v : +v.toFixed(2));
  ui.setPos = (x, y) => { st.pos.innerHTML = x === null ? '' : `<b>${coord(x)}</b>, <b>${coord(y)}</b>`; };

  const refreshBar = () => {
    for (const [m, b] of Object.entries(modeBtns)) b.classList.toggle('on', ed.mode === m);
    /* a custom size is on the list while it is the grid */
    const custom = !GRIDS.includes(ed.grid);
    customOpt.hidden = !custom;
    customOpt.value = custom ? String(ed.grid) : '';
    customOpt.textContent = custom ? `grid ${ed.grid}` : '';
    gridSel.value = String(ed.grid);
    shapeSel.value = ed.shape;
    sidesIn.hidden = !ed.shapeSides;
    if (ed.shapeSides) sidesIn.value = String(ed.shapeSides);
    snapBtn.classList.toggle('on', ed.snap);
    tabsBtn.classList.toggle('on', !tabsHidden);
    mainEl?.classList.toggle('notabs', tabsHidden);
    layerLbl.textContent = `Layer ${ed.layer}`;
    layerLbl.classList.toggle('up', ed.layer !== 0);
    snapBtn.firstChild.textContent = ed.snap ? 'Snap on' : 'Snap off';
    for (const [l, b] of Object.entries(layoutBtns)) b.classList.toggle('on', ed.layout === l);
    views.className = ed.layout;
    st.mode.innerHTML = `mode <b>${MODES[ed.mode].name}</b>`;
    st.grid.innerHTML = `grid <b>${ed.grid}</b>${ed.snap ? '' : ' (free)'}`;
    const n = ed.sel.ids.size;
    st.sel.innerHTML = n ? `<b>${n}</b> ${ed.sel.kind}${n > 1 ? 's' : ''}${ed.surf ? ` · ${ed.surf.part}` : ''}` : '';
    ui.help2d.textContent = HELP2D[ed.mode] || '';
  };

  /* ------------------------------------------------------------------
     THE INSPECTOR
     ------------------------------------------------------------------ */
  /* THE TEXTURE FIELD BEING PICKED FOR, if the browser was opened from
     one: `{ field, label }`. Clicking a texture then fills that field
     on everything selected and comes back. */
  ui.picking = null;

  const row = (label, input) => h('div', { class: 'ed-row' }, h('label', {}, label), input);
  const num = (value, onset, { step = 1, title } = {}) =>
    h('input', { type: 'number', value: value ?? '', step, title, onchange: e => { const v = parseFloat(e.target.value); if (Number.isFinite(v)) onset(v); } });
  const txt = (value, onset) => h('input', { type: 'text', value: value ?? '', onchange: e => onset(e.target.value) });
  const chk = (value, onset) => h('input', { type: 'checkbox', ...(value ? { checked: true } : {}), onchange: e => onset(e.target.checked) });
  const texField = (value, field, label, { allowNone = false } = {}) => {
    const el = h('div', { class: 'ed-tex' + (ui.picking?.field === field ? ' picking' : ''), title: 'click to pick from the browser',
      onclick: () => { ui.picking = { field, label, allowNone }; if (tabsHidden) { tabsHidden = false; refreshBar(); } showTab('tex'); renderTex(); } },
      swatch(ed, value), h('span', {}, value || (allowNone ? '— same as wall —' : '—')));
    return row(label, el);
  };

  /** One of a sector's five Doom 64 colours: a tick to use it, and the
   *  colour. */
  const colourRow = (s, k) => {
    const v = s.colors?.[k];
    const label = { floor: 'Floor', ceil: 'Ceiling', thing: 'Things', top: 'Walls, top', bottom: 'Walls, bottom' }[k];
    const set = c => each(`${label.toLowerCase()} colour`, x => {
      if (c) x.colors = { ...(x.colors || {}), [k]: c };
      else if (x.colors) { delete x.colors[k]; if (!Object.keys(x.colors).length) delete x.colors; }
    });
    return h('div', { class: 'ed-row two' }, h('label', {}, label),
      h('input', { type: 'checkbox', ...(v ? { checked: true } : {}), onchange: e => set(e.target.checked ? (v || '#ffffff') : null) }),
      h('input', { type: 'color', value: v || '#ffffff', onchange: e => set(e.target.value) }));
  };

  /** Doom Builder's eight facings, as a compass of buttons. */
  const facingButtons = onset => h('div', { class: 'ed-compass' },
    ...[['NW', 135], ['N', 90], ['NE', 45], ['W', 180], ['', null], ['E', 0], ['SW', 225], ['S', 270], ['SE', 315]].map(([n, deg]) =>
      deg === null ? h('span') : h('button', { title: `${deg}°`, onclick: () => onset(+(deg * Math.PI / 180).toFixed(4)) }, n)));

  /** Write `fn(obj)` into every selected object of the current kind. */
  const each = (label, fn) => {
    const { kind, ids } = ed.sel;
    ed.edit(label, d => {
      if (kind === 'sector') d.sectors.forEach(s => ids.has(s.id) && fn(s));
      if (kind === 'thing') d.things.forEach(t => ids.has(t.id) && fn(t));
      if (kind === 'prop') d.props.forEach(p => ids.has(p.id) && fn(p));
      if (kind === 'scatter') d.scatters.forEach(p => ids.has(p.id) && fn(p));
      if (kind === 'vertex') ids.forEach(i => d.vertices[i] && fn(d.vertices[i]));
      if (kind === 'line') ids.forEach(k => { d.lines[k] = d.lines[k] || {}; fn(d.lines[k]); if (!Object.keys(d.lines[k]).length) delete d.lines[k]; });
    }, { tidy: kind === 'vertex' });
  };

  /** LINING TEXTURES UP on every selected line at once: runs carried on
   *  face to face, one scale for all, whole repeats along and up. */
  const alignBlock = n => {
    const b = (label, how, title) => h('button', { class: 'ed-btn', title, onclick: () => ed.alignSel(how) }, label);
    return [
      h('h4', {}, `Alignment${n > 1 ? ` — all ${n} lines` : ''}`),
      h('div', { class: 'ed-small-btns' },
        b('Align X', 'x', 'Shift+A: each run of joined lines carries its texture on from one to the next, no seams at the corners'),
        b('Align Y', 'y', 'every side takes the first line\'s y offset'),
        b('Match', 'match', 'every side takes the first line\'s scale and y offset, then Align X')),
      h('div', { class: 'ed-small-btns' },
        b('Fit across', 'fitX', 'stretch each run a touch so its texture repeats a whole number of times along it, then Align X'),
        b('Fit up', 'fitY', 'stretch each wall a touch so its texture fits a whole number of times floor to top'),
        b('Reset', 'reset', 'no offsets, no scale')),
      h('div', { class: 'ed-row two' }, h('label', { title: 'Put this scale on every side of every selected line, then Align X' }, 'Scale all x / y'),
        num(1, v => { if (v > 0) ed.alignSel('scale', { xscale: v }); }, { step: 0.25 }),
        num(1, v => { if (v > 0) ed.alignSel('scale', { yscale: v }); }, { step: 0.25 })),
    ];
  };

  /** THE STEP GENERATOR (js/editor/steps.js): stairs across the
   *  selected sectors, bridging the heights either side of them, or
   *  rings in them, up to a mound or down into a caldera. */
  ui.steps = ui.steps || { kind: 'stairs', stepH: 16, count: 0, to: '', headroom: true };
  const stepsBlock = s => {
    const o = ui.steps;
    const kindSel = h('div', { class: 'ed-seg' },
      h('button', { class: o.kind === 'stairs' ? 'on' : '', title: 'Strips across the sector, from its lowest neighbour up to its highest', onclick: () => { o.kind = 'stairs'; renderInsp(); } }, '▤ Stairs'),
      h('button', { class: o.kind === 'rings' ? 'on' : '', title: 'Rings inside the sector, stepping to a height in the middle: a mound, a mesa, a caldera, a pit', onclick: () => { o.kind = 'rings'; renderInsp(); } }, '◎ Rings'));
    return [
      h('h4', {}, 'Steps — stairs, cliffs, calderas'),
      row('Make', kindSel),
      row('Step height', num(o.stepH, v => { o.stepH = Math.max(1, v); }, { step: 4, title: 'How high each step rises (the game climbs 24)' })),
      row('How many', num(o.count || '', v => { o.count = Math.max(0, Math.round(v)); }, { step: 1, title: 'Blank or 0: as many as the step height makes' })),
      row(o.kind === 'rings' ? 'Middle at' : 'Climb to', num(o.to, v => { o.to = v; }, { step: 8,
        title: o.kind === 'rings' ? 'The height of the middle ring: above the floor for a mound, below it for a caldera (blank: 128 up)' : 'Blank: the highest sector next to it' })),
      row('Keep head-room', chk(o.headroom, v => { o.headroom = v; })),
      h('div', { class: 'ed-small-btns' },
        h('button', { class: 'ed-btn primary', title: 'One undo step', onclick: () => {
          const to = o.to === '' || o.to === null || !Number.isFinite(+o.to) ? undefined : +o.to;
          ed.makeSteps(o.kind, { stepH: o.stepH, count: o.count, to, headroom: o.headroom });
        } }, o.kind === 'rings' ? 'Make rings' : 'Make stairs'),
        o.to !== '' ? h('button', { class: 'ed-btn', title: 'Back to working it out from the neighbours', onclick: () => { o.to = ''; renderInsp(); } }, 'Auto height') : null),
      h('p', { class: 'ed-note' }, o.kind === 'rings'
        ? `Rings from this floor (${s.floor ?? 0}) to the middle. Up for a mound or a cliff in terraces, down for a caldera.`
        : 'Draw a sector between two of different heights — a street and a terrace, a floor and the layer above — and it is cut into steps from the low one up to the high one.'),
    ];
  };

  const renderInsp = () => {
    const p = panes.insp;
    p.textContent = '';
    const { kind, ids } = ed.sel;
    const d = ed.doc;
    if (!kind || !ids.size) {
      put(p, h('h3', {}, 'Nothing selected'),
        h('p', { class: 'ed-note' }, 'Click something in the map or the 3D view. Shift adds to the selection; drag on empty space to box-select.'),
        h('p', { class: 'ed-note' }, `${d.sectors.length} sectors · ${ed.lines().length} lines · ${d.vertices.length} vertices · ${d.things.length} things · ${d.props.length} props`),
        h('h4', {}, 'New things'),
        row('Thing type', h('select', { onchange: e => { ed.thingType = e.target.value; } },
          ...Object.entries(THING_TYPES).map(([k, t]) => h('option', { value: k, ...(k === ed.thingType ? { selected: true } : {}) }, t.name)))),
        texField(ed.propTex, '@propTex', 'Prop texture'));
      return;
    }
    const n = ids.size;
    const head = (title) => h('h3', {}, title, h('small', {}, n > 1 ? `${n} selected` : ''));

    if (kind === 'sector') {
      const s = d.sectors.find(x => ids.has(x.id));
      if (!s) return;
      const r = ringOf(d, s);
      put(p, head(`Sector ${s.id}${s.name ? ` · ${s.name}` : ''}`),
        h('p', { class: 'ed-note' }, `${s.verts.length} corners · ${Math.round(Math.abs(signedArea(r)) / 4096)} cells²${ed.surf ? ` · picked: ${ed.surf.part}` : ''}`),
        row('Name', txt(s.name, v => each('rename sector', x => { x.name = v; }))),
        h('h4', {}, 'Heights'),
        row('Floor', num(s.floor, v => each('floor height', x => { x.floor = v; }), { step: 8 })),
        /* INSIDE OR OUTSIDE, the first thing a sector is here: outside is
           under the sky with no ceiling; inside has a roof, and walls
           where it meets the outside */
        row('Environment', h('div', { class: 'ed-seg' },
          h('button', { class: isInside(s) ? '' : 'on', title: 'Open to the sky, no ceiling', onclick: () => ed.setInside(false) }, '☀ Outside'),
          h('button', { class: isInside(s) ? 'on' : '', title: 'A roof, and walls where it meets the outside', onclick: () => ed.setInside(true) }, '⌂ Inside'))),
        row(isInside(s) ? 'Ceiling' : 'Wall height', num(s.ceil, v => each('ceiling height', x => { x.ceil = v; }), { step: 8 })),
        row('Brightness', h('div', { class: 'ed-bright' },
          h('input', { type: 'range', min: 0, max: 255, step: 1, value: brightOf(s), title: 'Ctrl+wheel over the sector, on the plan or in 3D',
            onchange: e => each('brightness', x => { x.light = +(+e.target.value / 255).toFixed(4); }) }),
          num(brightOf(s), v => each('brightness', x => { x.light = +(Math.max(0, Math.min(255, v)) / 255).toFixed(4); }), { step: 16 }))),
        ...stepsBlock(s),
        h('h4', {}, 'Light colour and fog'),
        h('div', { class: 'ed-row two' }, h('label', {}, 'Light colour'),
          h('input', { type: 'checkbox', title: 'One colour for all the light in the sector, on top of the Doom 64 colours below',
            ...(s.lightColor ? { checked: true } : {}), onchange: e => each('light colour', x => { if (e.target.checked) x.lightColor = s.lightColor || '#ffc890'; else delete x.lightColor; }) }),
          h('input', { type: 'color', value: s.lightColor || '#ffffff', onchange: e => each('light colour', x => { x.lightColor = e.target.value; }) })),
        h('div', { class: 'ed-row two' }, h('label', {}, 'Fog'),
          h('input', { type: 'checkbox', title: 'Fog of its own, in place of the map\'s',
            ...(s.fog?.density > 0 ? { checked: true } : {}), onchange: e => each('sector fog', x => { if (e.target.checked) x.fog = { color: s.fog?.color || '#8090a0', density: s.fog?.density > 0 ? s.fog.density : 20 }; else delete x.fog; }) }),
          h('input', { type: 'color', value: s.fog?.color || '#8090a0', onchange: e => each('fog colour', x => { x.fog = { density: 20, ...(x.fog || {}), color: e.target.value }; }) })),
        s.fog?.density > 0 ? row('Fog density', h('div', { class: 'ed-bright' },
          h('input', { type: 'range', min: 1, max: 100, step: 1, value: s.fog.density, title: 'Half-way in at 25600 / density units: 100 is thick at 256, 10 at 2560',
            onchange: e => each('fog density', x => { x.fog = { color: '#8090a0', ...(x.fog || {}), density: +e.target.value }; }) }),
          num(s.fog.density, v => each('fog density', x => { x.fog = { color: '#8090a0', ...(x.fog || {}), density: Math.max(0, Math.min(100, v)) }; if (!(x.fog.density > 0)) delete x.fog; }), { step: 5 }))) : null,
        h('p', { class: 'ed-note' }, d.world?.fog?.override ? 'The map\'s fog colour overrides this sector\'s (Map tab).' : 'No fog of its own: the map\'s fog, if it has one (Map tab).'),
        h('h4', {}, 'Colours — Doom 64'),
        h('p', { class: 'ed-note' }, 'The colour of the light on the floor, the ceiling, the things standing here, and the walls from top to bottom. Unticked is white.'),
        ...COLOR_PARTS.map(k => colourRow(s, k)),
        h('div', { class: 'ed-swatches' }, ...Object.entries(MOODS).map(([n, c]) =>
          h('button', { title: n, style: `background:linear-gradient(${c.top}, ${c.bottom})`, onclick: () => each(`colours ${n}`, x => { x.colors = { ...c }; }) })),
          h('button', { class: 'ed-btn', title: 'All white again', onclick: () => each('clear colours', x => { delete x.colors; }) }, 'Clear')),
        h('h4', {}, 'Textures'),
        texField(s.floorTex, 'floorTex', 'Floor'),
        s.ceilTex === 'SKY' ? null : texField(s.ceilTex, 'ceilTex', 'Ceiling'),
        texField(s.wallTex, 'wallTex', 'Walls'),
        texField(s.upperTex, 'upperTex', 'Upper', { allowNone: true }),
        texField(s.lowerTex, 'lowerTex', 'Lower', { allowNone: true }),
        h('h4', {}, 'Spread'),
        h('div', { class: 'ed-small-btns' },
          h('button', { class: 'ed-btn', title: 'Fill the selected sectors with the mix chosen in the Scatter tab',
            onclick: () => ed.scatterSectors() }, `Scatter ${PRESETS[ed.scatterPreset]?.name || ''} here`)),
      );
      return;
    }

    if (kind === 'line') {
      const key = [...ids][0];
      const o = d.lines[key] || {};
      const info = ed.lines().find(l => l.key === key);
      const [a, b] = key.split(',').map(Number);
      const va = d.vertices[a], vb = d.vertices[b];
      const len = va && vb ? Math.hypot(vb[0] - va[0], vb[1] - va[1]) : 0;
      /* A LINEDEF OF ITS OWN: no sector either side yet. It stands as a
         wall when the map is built, until it closes a shape. */
      if (info?.free) {
        put(p, head(`Linedef ${key}`),
          h('p', { class: 'ed-note' }, `${Math.round(len)} units · on its own: it stands as a wall ${LINEDEF_THICK} thick, and when more lines close a shape with it, that shape becomes a sector.`),
          texField(o.midTex, 'midTex', 'Wall texture', { allowNone: true }),
          row('Wall height', num(o.wallH ?? '', v => each('wall height', x => { if (v > 0) x.wallH = v; else delete x.wallH; }), { step: 8 })),
          h('p', { class: 'ed-note' }, `Empty height: ${LINEDEF_H} outdoors, floor to ceiling in a room. The whole run of joined linedefs takes the first one's texture and height. Delete removes it.`));
        return;
      }
      put(p, head(`Line ${key}`),
        h('p', { class: 'ed-note' }, `${Math.round(len)} units · ${info ? (info.sectors.length > 1 ? 'two-sided' : 'one-sided') : 'not on a sector'}`),
        row('Blocks walking', chk(o.blocking, v => each('line blocking', x => { if (v) x.blocking = true; else delete x.blocking; }))),
        row('Blocks sight', chk(o.blockSight, v => each('line sight', x => { if (v) x.blockSight = true; else delete x.blockSight; }))),
        /* THE SIDEDEF, Doom's way: top, middle and bottom textures, the
           offsets, and the two unpegged flags */
        /* THE TWO SIDES, Doom's front and back sidedefs, each named by the
           sector it faces: its top, middle and bottom, and its offsets.
           With several lines selected, what is set here goes on both
           sides of all of them. */
        ...(n === 1 && info ? info.sectors.map(si => {
          const sec = d.sectors[si], sd = o.sides?.[sec.id] || {}, base = `sides.${sec.id}`;
          const two = info.sectors.length > 1;
          const setSide = (label, fn) => each(label, x => { x.sides = x.sides || {}; x.sides[sec.id] = x.sides[sec.id] || {}; fn(x.sides[sec.id]); if (!Object.keys(x.sides[sec.id]).length) delete x.sides[sec.id]; if (!Object.keys(x.sides).length) delete x.sides; });
          return [
            h('h4', {}, `Side facing sector ${sec.id}${sec.name ? ` · ${sec.name}` : ''} · ${isInside(sec) ? 'inside' : 'outside'}`),
            two ? texField(sd.upperTex || o.upperTex, `${base}.upperTex`, 'Top (upper)', { allowNone: true }) : null,
            texField(sd.midTex || (two ? o.midTex : o.wallTex), `${base}.midTex`, two ? 'Middle' : 'Wall', { allowNone: true }),
            two ? texField(sd.lowerTex || o.lowerTex, `${base}.lowerTex`, 'Bottom (lower)', { allowNone: true }) : null,
            h('div', { class: 'ed-row two' }, h('label', {}, 'Offset x / y'),
              num(sd.xoff ?? o.xoff ?? 0, v => setSide('x offset', x => { x.xoff = v; }), { step: 1 }),
              num(sd.yoff ?? o.yoff ?? 0, v => setSide('y offset', x => { x.yoff = v; }), { step: 1 })),
            h('div', { class: 'ed-row two' }, h('label', { title: 'How big one repeat of the texture is: 2 is twice the size, half as often' }, 'Scale x / y'),
              num(sd.xscale ?? o.xscale ?? 1, v => setSide('x scale', x => { if (v > 0 && v !== 1) x.xscale = v; else delete x.xscale; }), { step: 0.25 }),
              num(sd.yscale ?? o.yscale ?? 1, v => setSide('y scale', x => { if (v > 0 && v !== 1) x.yscale = v; else delete x.yscale; }), { step: 0.25 })),
          ];
        }) : [
          h('h4', {}, 'Textures — both sides'),
          texField(o.upperTex, 'upperTex', 'Top (upper)', { allowNone: true }),
          texField(o.midTex, 'midTex', 'Middle', { allowNone: true }),
          texField(o.lowerTex, 'lowerTex', 'Bottom (lower)', { allowNone: true }),
          texField(o.wallTex, 'wallTex', 'Wall (one-sided)', { allowNone: true }),
        ]),
        (info && info.sectors.length > 1 && (o.midTex || Object.values(o.sides || {}).some(x => x.midTex)))
          ? row('Middle height', num(o.midHeight ?? '', v => each('middle height', x => { if (v > 0) x.midHeight = v; else delete x.midHeight; }), { step: 8 })) : null,
        n === 1 && info && info.sectors.length > 1 ? h('div', { class: 'ed-small-btns' },
          h('button', { class: 'ed-btn', title: "Doom Builder's Flip Sidedefs: each side gets the other's textures and offsets",
            onclick: () => each('swap sides', x => {
              const [a, b] = info.sectors.map(si => d.sectors[si].id);
              const sa = x.sides?.[a], sb = x.sides?.[b];
              x.sides = x.sides || {};
              if (sb) x.sides[a] = sb; else delete x.sides[a];
              if (sa) x.sides[b] = sa; else delete x.sides[b];
              if (!Object.keys(x.sides).length) delete x.sides;
            }) }, '⇄ Swap sides')) : null,
        info && info.sectors.length > 1 && info.sectors.map(i => d.sectors[i]).some(isInside) && info.sectors.map(i => d.sectors[i]).some(x => !isInside(x))
          ? [h('h4', {}, 'Building wall'),
             row('Doorway', chk(o.opening, v => each('doorway', x => { if (v) x.opening = true; else delete x.opening; }))),
             h('p', { class: 'ed-note' }, 'This line is where an inside sector meets the outside, so it is a wall unless it is a doorway. Split it with Insert (vertices mode) to make a doorway in part of a wall.')]
          : null,
        alignBlock(n),
        h('h4', {}, 'Pegging'),
        row('Upper unpegged', chk(o.unpegUpper, v => each('upper unpegged', x => { if (v) x.unpegUpper = true; else delete x.unpegUpper; }))),
        row('Lower unpegged', chk(o.unpegLower, v => each('lower unpegged', x => { if (v) x.unpegLower = true; else delete x.unpegLower; }))),
        h('p', { class: 'ed-note' }, 'In 3D, the arrow keys over a wall nudge its offsets (Shift: 8 at a time). Deleting a line joins the two sectors on it into one.'));
      return;
    }

    if (kind === 'vertex') {
      const i = [...ids][0];
      const v = d.vertices[i];
      if (!v) return;
      put(p, head(`Vertex ${i}`),
        n === 1 ? row('X', num(v[0], x => each('vertex x', w => { w[0] = x; }))) : null,
        n === 1 ? row('Y', num(v[1], y => each('vertex y', w => { w[1] = y; }))) : null,
        h('p', { class: 'ed-note' }, 'Drag a vertex onto another to weld them. Deleting a vertex takes it out of every sector it is in.'));
      return;
    }

    if (kind === 'thing') {
      const t = d.things.find(x => ids.has(x.id));
      if (!t) return;
      put(p, head(`${THING_TYPES[t.type]?.name || t.type}`),
        row('Type', h('select', { onchange: e => each('thing type', x => { x.type = e.target.value; }) },
          ...Object.entries(THING_TYPES).map(([k, tt]) => h('option', { value: k, ...(k === t.type ? { selected: true } : {}) }, tt.name)))),
        n === 1 ? row('X', num(t.x, v => each('thing x', x => { x.x = v; }))) : null,
        n === 1 ? row('Y', num(t.y, v => each('thing y', x => { x.y = v; }))) : null,
        row('Facing °', num(Math.round((t.angle || 0) * 180 / Math.PI), v => each('thing angle', x => { x.angle = v * Math.PI / 180; }), { step: 45 })),
        row('', facingButtons(a2 => each('face', x => { x.angle = a2; }))),
        ...(t.type === 'PLANT'
          ? [row('Plant', h('select', { onchange: e => each('plant kind', x => { x.kind = e.target.value; }) },
              ...PLANT_KINDS.map(k => h('option', { value: k, ...(k === t.kind ? { selected: true } : {}) }, k)))),
             row('Scale', num(t.scale ?? 1, v => each('plant scale', x => { x.scale = Math.max(0.2, Math.min(4, v)); }), { step: 0.1 }))]
          : [row('Variant', num(t.variant ?? '', v => each('thing variant', x => { x.variant = Math.max(0, Math.round(v)); })))]),
        h('p', { class: 'ed-note' }, 'In Things mode, double-click empty floor (or press Insert) to place the type chosen in the Things tab; , and . turn the selection.'));
      return;
    }

    if (kind === 'prop') {
      const pr = d.props.find(x => ids.has(x.id));
      if (!pr) return;
      put(p, head(`Prop ${pr.id}`),
        h('p', { class: 'ed-note' }, 'A solid box anywhere in space — a crate, a beam, a bridge, a floating platform.'),
        h('div', { class: 'ed-row two' }, h('label', {}, 'X from / to'),
          num(pr.x0, v => each('prop x0', x => { x.x0 = v; }), { step: 8 }), num(pr.x1, v => each('prop x1', x => { x.x1 = v; }), { step: 8 })),
        h('div', { class: 'ed-row two' }, h('label', {}, 'Y from / to'),
          num(pr.y0, v => each('prop y0', x => { x.y0 = v; }), { step: 8 }), num(pr.y1, v => each('prop y1', x => { x.y1 = v; }), { step: 8 })),
        h('div', { class: 'ed-row two' }, h('label', {}, 'Bottom / top'),
          num(pr.z0, v => each('prop bottom', x => { x.z0 = v; }), { step: 8 }), num(pr.z1, v => each('prop top', x => { x.z1 = v; }), { step: 8 })),
        texField(pr.tex, 'tex', 'Sides'),
        texField(pr.topTex, 'topTex', 'Top', { allowNone: true }));
    }

    if (kind === 'scatter') put(p, ...scatterInspector(d.scatters.find(x => ids.has(x.id)), n));
  };

  /* ------------------------------------------------------------------
     A SCATTER: the rule, every dial of it, and what it grew
     ------------------------------------------------------------------ */
  const scatterInspector = (c, n) => {
    if (!c) return [];
    const g = ed.compiled?.grown?.get(c.id);
    const a = c.area;
    const total = c.items.reduce((s2, i) => s2 + (i.w || 0), 0) || 1;
    const setItems = (label, fn) => each(label, x => { fn(x.items); });
    const range = (value, min, max, step, onset) => h('input', { type: 'range', min, max, step, value, onchange: e => onset(+e.target.value) });
    return [
      h('h3', {}, `Scatter · ${c.name || c.id}`, h('small', {}, n > 1 ? `${n} selected` : '')),
      h('p', { class: 'ed-note' }, g ? `grew ${g.grown} of ${g.wanted}${g.grown < g.wanted * 0.9 ? ' — no room for the rest' : ''}` : 'growing…',
        ' · a rule, re-grown every time it changes'),
      row('Name', txt(c.name, v => each('rename scatter', x => { x.name = v; }))),
      h('h4', {}, 'Where'),
      a.kind === 'circle'
        ? h('div', { class: 'ed-row two' }, h('label', {}, 'Centre / radius'),
            h('span', { class: 'ed-note' }, `${Math.round(a.x)}, ${Math.round(a.y)}`),
            num(a.r, v => each('scatter radius', x => { if (x.area.kind === 'circle') x.area.r = Math.max(16, v); }), { step: 32 }))
        : a.kind === 'rect'
          ? h('p', { class: 'ed-note' }, `a rectangle, ${Math.abs(a.x1 - a.x0)} × ${Math.abs(a.y1 - a.y0)}`)
          : h('p', { class: 'ed-note' }, `filling ${a.ids.length} sector${a.ids.length > 1 ? 's' : ''}`),
      h('h4', {}, 'How'),
      row('Density', h('div', { style: 'display:flex;gap:6px;align-items:center' },
        range(c.density, 0, 120, 0.5, v => each('density', x => { x.density = v; })),
        num(c.density, v => each('density', x => { x.density = Math.max(0, v); }), { step: 0.5, title: 'per 1024 × 1024' }))),
      row('Spacing', num(c.spacing, v => each('spacing', x => { x.spacing = Math.max(0, v); }), { step: 8 })),
      row('Clumping', range(c.clump ?? 0, 0, 1, 0.05, v => each('clumping', x => { x.clump = v; }))),
      h('div', { class: 'ed-row two' }, h('label', {}, 'Scale min / max'),
        num(c.scaleMin ?? 1, v => each('scale', x => { x.scaleMin = v; }), { step: 0.05 }),
        num(c.scaleMax ?? 1, v => each('scale', x => { x.scaleMax = v; }), { step: 0.05 })),
      h('p', { class: 'ed-note' }, `density is things per 1024 × 1024 of floor · at most ${SCATTER_MAX} per scatter`),
      h('h4', {}, 'What'),
      ...c.items.map((it, k) => h('div', { class: 'ed-row item' },
        h('label', {}, h('i', { class: 'ed-dot', style: `background:${it.type.startsWith('PLANT:') ? plantColour(it.type.slice(6)) : THING_TYPES[it.type]?.color}` }),
          ` ${Math.round((it.w || 0) / total * 100)}%`),
        h('select', { onchange: e => setItems('scatter item', list => { if (list[k]) list[k].type = e.target.value; }) },
          ...SCATTER_TYPES.map(t => h('option', { value: t, ...(t === it.type ? { selected: true } : {}) }, typeName(t)))),
        h('div', { style: 'display:flex;gap:4px' },
          num(it.w, v => setItems('weight', list => { if (list[k]) list[k].w = Math.max(0, v); }), { step: 1, title: 'weight' }),
          h('button', { class: 'ed-btn', title: 'remove', onclick: () => setItems('remove item', list => { list.splice(k, 1); }) }, '×')))),
      h('div', { class: 'ed-small-btns' },
        h('button', { class: 'ed-btn', onclick: () => setItems('add item', list => { list.push({ type: 'SHOPPER', w: 1 }); }) }, '+ Item')),
      h('h4', {}, 'Seed'),
      h('div', { class: 'ed-small-btns' },
        h('button', { class: 'ed-btn', title: 'Roll it again: the same rule, a different spread', onclick: () => ed.reseed() }, '🎲 Reseed'),
        h('button', { class: 'ed-btn', title: 'Turn what it grew into ordinary things, and drop the rule', onclick: () => ed.bake() }, 'Bake into things'),
        h('button', { class: 'ed-btn', onclick: () => ed.emit('frameSel') }, 'Frame')),
    ];
  };

  /* ------------------------------------------------------------------
     THE TEXTURE BROWSER
     ------------------------------------------------------------------ */
  let filter = '';
  const texCells = new Map();
  const texHead = h('div');
  const mineGrid = h('div', { class: 'ed-texgrid' });
  const packWrap = h('div');
  const packGroups = [];          // [{ head, grid, names }]
  const mineHead = h('div', { class: 'ed-texsec' });
  const texFilter = h('input', { class: 'ed-texfilter', type: 'text', placeholder: 'filter textures…', oninput: e => { filter = e.target.value.toUpperCase(); renderTex(); } });
  panes.tex.append(texHead, texFilter, mineHead, mineGrid, packWrap);
  /* THE CELLS, made again when the map's own textures change — a new
     one, a repainted one, one gone */
  const buildCells = () => {
    texCells.clear();
    mineGrid.textContent = ''; packWrap.textContent = '';
    packGroups.length = 0;
    const cell = (name, mine) => {
      const a = animOf(name);
      const p = PACK_BY_NAME.get(name);
      const what = a ? `, animated: ${a.run.length} frames, ${a.tics} tics each` : '';
      const size = p ? ` (${p.w}×${p.h})` : '';
      const c = h('div', { class: 'ed-texcell' + (mine ? ' mine' : '') + (a ? ' anim' : ''),
        title: mine ? `${name} — double-click to edit` : `${name}${size}${what} — double-click to make a texture from it`,
        onclick: () => pickTexture(name),
        ondblclick: () => (mine ? openTextureEditor(ed, name) : openTextureEditor(ed, null, name)) },
        swatch(ed, name, 64), h('span', {}, a && a.i === 0 ? `${name} ▶${a.run.length}` : name));
      /* A RUN IS ONE CELL, its first frame, the way a browser that lists
         seventy-five frames of a test card is no use; typing in the filter
         shows every frame that matches, since in Doom any of them can be
         put on a wall and starts the cycle there */
      if (a && a.i > 0) c.dataset.frame = '1';
      texCells.set(name, c);
      return c;
    };
    for (const n of ed.mapTextureNames || []) mineGrid.append(cell(n, true));
    /* EVERY OTHER TEXTURE, the game's own and the pack's (js/texpack.js)
       together, sorted by SHAPE at the user's request: what animates,
       what is square, and what is not — by its size on a wall, so a
       64 by 112 window is not square whatever its picture is */
    const all = [...new Set([...(ed.gameTextureNames || []), ...PACK.map(p => p.name)])].sort();
    for (const shape of TEX_SHAPES) {
      const names = all.filter(n => shapeOf(ed, n) === shape);
      if (!names.length) continue;
      const shown = names.filter(n => !animOf(n) || animOf(n).i === 0).length;
      const head = h('div', { class: 'ed-texsec' }, h('span', {}, `${shape} (${shown})`));
      const grid = h('div', { class: 'ed-texgrid' }, ...names.map(n => cell(n, false)));
      packGroups.push({ head, grid, names });
      packWrap.append(head, grid);
    }
    if (ed.packLoading) packWrap.prepend(h('p', { class: 'ed-note' }, 'Loading the texture pack…'));
    renderMineHead();
    if (!(ed.mapTextureNames || []).length) mineGrid.append(h('p', { class: 'ed-note' }, 'None yet. + New starts one; double-click any game texture to start from it.'));
  };
  const renderMineHead = () => {
    mineHead.textContent = '';
    mineHead.append(h('span', {}, `This map's textures (${(ed.mapTextureNames || []).length})`),
      h('span', { class: 'ed-small-btns' },
        h('button', { class: 'ed-btn', title: 'A new texture, from layers of others and your own images', onclick: () => openTextureEditor(ed, null, ui.current && ed.bank.map.has(ui.current) ? ui.current : 'GRIDWALL') }, '+ New'),
        ui.current && (ed.mapTextureNames || []).includes(ui.current)
          ? [h('button', { class: 'ed-btn', onclick: () => openTextureEditor(ed, ui.current) }, 'Edit'),
             h('button', { class: 'ed-btn', onclick: () => {
               const n = ui.current;
               ed.edit(`delete texture ${n}`, d => { d.textures = (d.textures || []).filter(t => t.name !== n); }, { tidy: false });
               ui.current = null;
             } }, 'Delete')]
          : null));
  };
  const pickTexture = name => {
    if (ui.picking) {
      const { field } = ui.picking;
      if (field === '@propTex') { ed.propTex = name; }
      else if (ed.sel.kind) each(`${field.split('.').pop()} ${name}`, x => { setPath(x, field, name); });
      ui.picking = null;
      showTab('insp');
      renderInsp();
      ed.say(`${name}`);
      return;
    }
    ed.applyTexture(name);
    ui.current = name;
    renderTex();
  };
  const renderTex = () => {
    texHead.textContent = '';
    if (ui.picking) {
      texHead.append(h('p', { class: 'ed-note' }, `Picking the ${ui.picking.label.toLowerCase()} texture. `,
        ui.picking.allowNone ? h('button', { class: 'ed-btn', onclick: () => { const f = ui.picking.field; ui.picking = null; if (ed.sel.kind) each(`clear ${f.split('.').pop()}`, x => { delPath(x, f); }); showTab('insp'); } }, 'Use none') : null,
        ' ', h('button', { class: 'ed-btn', onclick: () => { ui.picking = null; showTab('insp'); renderInsp(); } }, 'Cancel')));
    } else {
      texHead.append(h('p', { class: 'ed-note' }, ed.surf ? `Click a texture to paint the picked ${ed.surf.part}.` : 'Pick a surface in the 3D view, then click a texture to paint it — or open this from an inspector field.'));
    }
    if (!texCells.size) buildCells();
    else renderMineHead();
    for (const [name, cell] of texCells) {
      const shown = filter ? name.includes(filter) : (!cell.dataset.frame || name === ui.current);
      cell.style.display = shown ? '' : 'none';
      cell.classList.toggle('on', name === ui.current);
    }
    for (const g of packGroups) {
      const any = g.names.some(n => texCells.get(n)?.style.display !== 'none');
      g.head.style.display = g.grid.style.display = any ? '' : 'none';
    }
  };
  ed.on('textures', () => { buildCells(); renderTex(); });
  renderTex();

  /* ------------------------------------------------------------------
     THE THING PALETTE
     ------------------------------------------------------------------ */
  /* THE THINGS EDITOR: what to place, everything already placed — a
     list to find and select them by, filtered by type — and what to do
     to the selection all at once */
  let thingFilter = null, thingSearch = '';
  const renderThings = () => {
    const p = panes.things;
    const keepFocus = p.contains(document.activeElement) && document.activeElement.tagName === 'INPUT';
    if (keepFocus) return;
    p.textContent = '';
    const d = ed.doc;
    const count = new Map();
    for (const t of d.things) count.set(t.type, (count.get(t.type) || 0) + 1);
    const selThings = ed.sel.kind === 'thing' ? d.things.filter(t => ed.sel.ids.has(t.id)) : [];
    const eachSel = (label, fn) => ed.edit(label, dd => { for (const t of dd.things) if (ed.sel.ids.has(t.id)) fn(t); }, { tidy: false });
    put(p, 
      h('h4', { class: 'ed-sub0' }, 'Place'),
      h('p', { class: 'ed-note' }, 'Pick a type, then in Things mode (T) double-click the floor or press Insert — on the plan or in 3D.'),
      h('div', { class: 'ed-things' }, ...Object.entries(THING_TYPES).filter(([k]) => k !== 'PLANT').map(([k, t]) =>
        h('button', { class: k === ed.thingType ? 'on' : '', onclick: () => { ed.thingType = k; ed.setMode('things'); renderThings(); } },
          h('i', { style: `background:${t.color}` }), t.name))),
      h('h4', { class: 'ed-sub' }, 'Plants — sprite decorations'),
      PLANT_SETS.map(set => [h('p', { class: 'ed-note' }, set.name),
        h('div', { class: 'ed-plants' }, ...set.kinds.map(k =>
        h('button', { class: ed.thingType === 'PLANT' && ed.plantKind === k ? 'on' : '', title: k,
          onclick: () => { ed.thingType = 'PLANT'; ed.plantKind = k; ed.setMode('things'); renderThings(); } },
          h('img', { src: `assets/forest/${k}.png`, alt: '', loading: 'lazy' }), h('span', {}, k.replace(/_/g, ' ')))))]),
    );
    if (selThings.length) {
      put(p, h('h4', { class: 'ed-sub' }, `The selection (${selThings.length})`),
        h('div', { class: 'ed-row' }, h('label', {}, 'Face'), facingButtons(a2 => eachSel('face', t => { t.angle = a2; }))),
        h('div', { class: 'ed-row' }, h('label', {}, 'Change to'), h('select', { onchange: e => { if (e.target.value) eachSel('change type', t => { t.type = e.target.value; if (t.type === 'PLANT' && !t.kind) t.kind = ed.plantKind; }); } },
          h('option', { value: '' }, '…'), ...Object.entries(THING_TYPES).map(([k, t]) => h('option', { value: k }, t.name)))),
        h('div', { class: 'ed-small-btns' },
          h('button', { class: 'ed-btn', onclick: () => eachSel('random facing', t => { t.angle = +(Math.random() * Math.PI * 2).toFixed(3); }) }, 'Random facing'),
          h('button', { class: 'ed-btn', onclick: () => eachSel('random variant', t => { t.variant = (Math.random() * 64) | 0; }) }, 'Random variant'),
          h('button', { class: 'ed-btn', onclick: () => eachSel('snap to grid', t => { t.x = ed.snapV(t.x); t.y = ed.snapV(t.y); }) }, 'Snap to grid'),
          h('button', { class: 'ed-btn', onclick: () => { const types = new Set(selThings.map(t => t.type)); ed.select('thing', d.things.filter(t => types.has(t.type)).map(t => t.id)); } }, 'Select all of this type'),
          h('button', { class: 'ed-btn', onclick: () => ed.deleteSel() }, 'Delete')));
    }
    /* everything placed, to find it by */
    const table = h('div', { class: 'ed-thingtable' });
    const fillTable = () => {
      table.textContent = '';
      const shown = d.things.filter(t => (!thingFilter || t.type === thingFilter) &&
        (!thingSearch || `${t.type} ${t.kind || ''} ${t.id}`.toUpperCase().includes(thingSearch)));
      table.append(...shown.slice(0, 300).map(t => h('div', { class: 'ed-listrow' + (ed.isSel('thing', t.id) ? ' on' : ''),
          onclick: e => { ed.setMode('things'); ed.select('thing', [t.id], e.shiftKey); if (!e.shiftKey) ed.emit('frameSel'); } },
          h('span', {}, h('i', { class: 'ed-dot', style: `background:${t.type === 'PLANT' ? plantColour(t.kind) : THING_TYPES[t.type]?.color}` }),
            ` ${t.type === 'PLANT' ? (t.kind || 'plant').replace(/_/g, ' ') : THING_TYPES[t.type]?.name || t.type}`),
          h('small', {}, `${Math.round(t.x)}, ${Math.round(t.y)} · ${Math.round(((t.angle || 0) * 180 / Math.PI) % 360)}°`))),
        shown.length > 300 ? h('p', { class: 'ed-note' }, `and ${shown.length - 300} more — filter to find them`) : '');
    };
    fillTable();
    put(p, h('h4', { class: 'ed-sub' }, `In this map (${d.things.length})`),
      h('div', { class: 'ed-chips' },
        h('button', { class: !thingFilter ? 'on' : '', onclick: () => { thingFilter = null; renderThings(); } }, `all ${d.things.length}`),
        ...[...count].sort((x, y) => y[1] - x[1]).map(([k, n]) => h('button', { class: thingFilter === k ? 'on' : '', onclick: () => { thingFilter = k; renderThings(); } },
          h('i', { style: `background:${THING_TYPES[k]?.color || '#f0f'}` }), `${THING_TYPES[k]?.name || k} ${n}`))),
      h('input', { class: 'ed-texfilter', type: 'text', placeholder: 'find…', value: thingSearch,
        oninput: e => { thingSearch = e.target.value.toUpperCase(); fillTable(); } }),
      table,
      h('p', { class: 'ed-note' }, 'Things grown by scatters are not listed: bake a scatter to list them.'));
  };
  renderThings();

  /* ------------------------------------------------------------------
     THE SCATTER TAB: the mixes, the brush, and every scatter in the map
     ------------------------------------------------------------------ */
  const renderScatter = () => {
    const p = panes.scatter;
    p.textContent = '';
    const d = ed.doc;
    put(p, h('h3', {}, 'Scatter'),
      h('p', { class: 'ed-note' }, 'Spread sprite people and decorations procedurally. Pick a mix, then in Scatter mode (X) drag a circle out from its middle — on the plan or in 3D. Or fill selected sectors. Every scatter stays a live rule: change its dials and it re-grows.'),
      h('h4', {}, 'Mix'),
      h('div', { class: 'ed-presets' }, ...Object.entries(PRESETS).map(([k, pr]) =>
        h('button', { class: k === ed.scatterPreset ? 'on' : '', onclick: () => { ed.scatterPreset = k; ed.setMode('scatter'); renderScatter(); renderInsp(); } },
          h('span', { class: 'sw' }, ...pr.items.slice(0, 4).map(it => h('i', { style: `background:${it.type.startsWith('PLANT:') ? plantColour(it.type.slice(6)) : THING_TYPES[it.type]?.color}` }))),
          pr.name))),
      row('Brush radius', num(ed.brushRadius || 512, v => { ed.brushRadius = Math.max(16, v); }, { step: 64, title: 'for a click without a drag' })),
      h('div', { class: 'ed-small-btns' },
        h('button', { class: 'ed-btn', onclick: () => ed.setMode('scatter') }, 'Brush (X)'),
        h('button', { class: 'ed-btn', onclick: () => ed.scatterSectors() }, 'Fill selected sectors')),
      h('h4', {}, `In this map (${d.scatters.length})`),
      d.scatters.length ? h('div', {}, ...d.scatters.map(c => {
        const g = ed.compiled?.grown?.get(c.id);
        return h('div', { class: 'ed-listrow' + (ed.isSel('scatter', c.id) ? ' on' : ''),
          onclick: () => { ed.setMode('scatter'); ed.select('scatter', [c.id]); ed.emit('frameSel'); showTab('insp'); } },
          h('span', {}, c.name || `scatter ${c.id}`), h('small', {}, g ? `${g.grown}` : ''));
      })) : h('p', { class: 'ed-note' }, 'None yet.'));
  };

  /* ------------------------------------------------------------------
     THE MAP: its name, the world round it, and what is wrong with it
     ------------------------------------------------------------------ */
  const setWorld = (label, fn) => ed.edit(label, d => { d.world = d.world || {}; fn(d.world); }, { tidy: false });
  const renderMap = () => {
    const p = panes.map;
    p.textContent = '';
    const d = ed.doc;
    const w = d.world || {};
    const sky = w.sky || {};
    const colour = (k, label) => h('div', { class: 'ed-row' }, h('label', {}, label),
      h('input', { type: 'color', value: sky[k] || '#000000', onchange: e => setWorld(`sky ${k}`, ww => { ww.sky = { ...(ww.sky || {}), [k]: e.target.value }; }) }));
    const probs = [...problemsOf(d), ...(ed.compiled?.problems || [])];
    const seen = new Set();
    const uniq = probs.filter(x => (seen.has(x.msg) ? false : seen.add(x.msg)));
    put(p, h('h3', {}, 'Map'),
      row('Name', txt(d.name, v => ed.edit('rename map', dd => { dd.name = v; }, { tidy: false }))),
      h('h4', {}, 'World'),
      row('Nothing burns', chk(w.noBurn, v => setWorld('noBurn', ww => { ww.noBurn = v; }))),
      row('No responders', chk(w.noSquads, v => setWorld('noSquads', ww => { ww.noSquads = v; }))),
      row('Doom sky walls', chk(w.skyWalls, v => setWorld('skyWalls', ww => { if (v) ww.skyWalls = true; else delete ww.skyWalls; }))),
      h('p', { class: 'ed-note' }, 'Off (the default): an open world — a roofed room under the sky has a roof and no wall running up to the sky. On: Doom\'s way, the upper wall goes up to the sky height.'),
      h('h4', {}, 'Light and fog'),
      row('Light colour', h('input', { type: 'color', value: w.lightColor || '#ffffff', title: 'The colour of all the light in the map',
        onchange: e => setWorld('light colour', ww => { if (e.target.value.toLowerCase() === '#ffffff') delete ww.lightColor; else ww.lightColor = e.target.value; }) })),
      row('Ambient light', h('input', { type: 'color', value: w.ambient?.color || '#ffffff', title: 'Light that is everywhere, however dark the sector',
        onchange: e => setWorld('ambient colour', ww => { ww.ambient = { amount: 0.15, ...(ww.ambient || {}), color: e.target.value }; }) })),
      row('Ambient strength', h('div', { class: 'ed-bright' },
        h('input', { type: 'range', min: 0, max: 100, step: 1, value: Math.round((w.ambient?.amount || 0) * 100),
          onchange: e => setWorld('ambient strength', ww => { ww.ambient = { color: '#ffffff', ...(ww.ambient || {}), amount: +e.target.value / 100 }; }) }),
        num(Math.round((w.ambient?.amount || 0) * 100), v => setWorld('ambient strength', ww => { ww.ambient = { color: '#ffffff', ...(ww.ambient || {}), amount: Math.max(0, Math.min(100, v)) / 100 }; }), { step: 5 }))),
      row('Ambient in fog', h('div', { class: 'ed-bright' },
        h('input', { type: 'range', min: 0, max: 100, step: 1, value: Math.round((w.fogAmbient ?? 1) * 100), title: 'How much of the ambient light is in every fog',
          onchange: e => setWorld('ambient in fog', ww => { ww.fogAmbient = +e.target.value / 100; }) }),
        num(Math.round((w.fogAmbient ?? 1) * 100), v => setWorld('ambient in fog', ww => { ww.fogAmbient = Math.max(0, Math.min(100, v)) / 100; }), { step: 10 }))),
      row('Fog colour', h('input', { type: 'color', value: w.fog?.color || '#808080',
        onchange: e => setWorld('fog colour', ww => { ww.fog = { density: 0, ...(ww.fog || {}), color: e.target.value }; }) })),
      row('Fog density', h('div', { class: 'ed-bright' },
        h('input', { type: 'range', min: 0, max: 100, step: 1, value: w.fog?.density || 0, title: 'The fog of every sector without its own. 0 is none.',
          onchange: e => setWorld('fog density', ww => { ww.fog = { color: '#808080', ...(ww.fog || {}), density: +e.target.value }; }) }),
        num(w.fog?.density || 0, v => setWorld('fog density', ww => { ww.fog = { color: '#808080', ...(ww.fog || {}), density: Math.max(0, Math.min(100, v)) }; }), { step: 5 }))),
      row('Override fog colour', chk(w.fog?.override, v => setWorld('fog override', ww => { ww.fog = { color: '#808080', density: 0, ...(ww.fog || {}), override: v }; }))),
      h('p', { class: 'ed-note' }, 'The map\'s fog is the fog of every sector without one of its own; a sector sets its own on the Inspect tab. Override puts this fog colour on every sector\'s fog and on the far haze. The ambient light lifts every surface and, by "Ambient in fog", tints every fog.'),
      h('h4', {}, 'Sky'),
      row('Skybox', h('select', { onchange: e => setWorld('skybox', ww => { if (e.target.value) ww.skybox = e.target.value; else delete ww.skybox; }) },
        h('option', { value: '' }, 'painted (the colours below)'),
        ...PACK_SKIES.map(n => h('option', { value: n, ...(n === w.skybox ? { selected: true } : {}) }, n)))),
      w.skybox ? h('p', { class: 'ed-note' }, `The ${w.skybox} skybox from the texture pack. The air far off fades to its horizon; the colours below are kept for when it is set back to painted, and for the Godot export's ground.`) : null,
      colour('horizon', 'Horizon'), colour('mid', 'Middle'), colour('zenith', 'Overhead'), colour('ground', 'Below'),
      h('p', { class: 'ed-note' }, 'The sky is re-baked in the 3D view as you change it.'),
      h('h4', {}, `Problems (${uniq.length})`),
      uniq.length ? h('div', {}, ...uniq.map(x => h('div', { class: 'ed-prob', onclick: () => {
        /* a problem on another layer: that layer first */
        if (x.layer !== undefined && x.layer !== ed.layer) ed.setLayer(x.layer);
        if (x.id !== undefined && x.kind === 'sector') {
          const both = (x.msg.match(/sectors (\d+) and (\d+)/) || []).slice(1).map(Number);
          ed.setMode('sectors'); ed.select('sector', both.length ? both : [x.id]); ed.emit('frameSel');
        }
      } }, x.msg))) : h('div', { class: 'ed-ok' }, 'None. The map will build.'),
      h('h4', {}, 'Counts'),
      h('p', { class: 'ed-note' }, `${d.sectors.length} sectors · ${ed.lines().length} lines · ${d.vertices.length} vertices · ${d.things.length} things · ${d.props.length} props`));
  };

  /* ------------------------------------------------------------------
     WIRING
     ------------------------------------------------------------------ */
  /* a field being typed in is not redrawn under the typist; a button that
     was just clicked is, or the panel shows what was there before it */
  const inspFocused = () => {
    const a = document.activeElement;
    return !!a && /^(INPUT|SELECT|TEXTAREA)$/.test(a.tagName) && (panes.insp.contains(a) || panes.map.contains(a));
  };
  ed.on('sel', () => { refreshBar(); if (!ui.picking) renderInsp(); renderTex(); if (ui.tab === 'things') renderThings(); });
  ed.on('mode', refreshBar);
  ed.on('grid', refreshBar);
  ed.on('layout', refreshBar);
  ed.on('layer', refreshBar);
  let thingsT = 0;
  ed.on('doc', () => {
    if (!inspFocused()) { renderInsp(); if (ui.tab === 'map') renderMap(); }
    if (ui.tab === 'things') { clearTimeout(thingsT); thingsT = setTimeout(renderThings, 150); }
  });
  ed.on('compiled', c => {
    if (ed.sel.kind === 'scatter' && !inspFocused()) renderInsp();
    if (ui.tab === 'scatter') renderScatter();
    const n = c.problems.length;
    st.probs.innerHTML = n ? `<span class="bad">${n} problem${n > 1 ? 's' : ''}</span>` : '';
    if (ui.tab === 'map' && !inspFocused()) renderMap();
  });
  ed.on('status', msg => { st.msg.textContent = msg; });
  refreshBar();
  renderInsp();
  return ui;
}

const HELP2D = {
  vertices: 'click select · drag move · shift add · Del delete\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light · [ ] grid',
  lines: 'click select · drag move · Del joins sectors (or removes a yellow linedef) · D draws new linedefs\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light · [ ] grid',
  sectors: 'drag on the ground: new sector · drag a room: move it · Insert/D: draw any shape\nclick select · dbl-click inspect · wheel zoom · right-drag/MMB pan · [ ] grid',
  things: 'dbl-click / Insert place · drag move · , . turn\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light',
  props: 'drag empty to draw a box · drag to move\nwheel zoom · right-drag/MMB pan · Ctrl+wheel light',
  draw: 'click corners · click the first to close a sector · Backspace undoes a corner\nEnter / right-click / dbl-click: finish as linedefs — they close into a sector, split a room wall to wall, or stand as a wall · Esc cancel',
  rect: 'drag out the shape chosen beside the Shape button (rectangle, ellipse, circle, polygon, star…)\nthe number sets a round shape\'s sides · Esc cancel',
};

function typeName(t) {
  if (t.startsWith('PLANT:')) return `plant: ${t.slice(6).replace(/_/g, ' ')}`;
  return THING_TYPES[t]?.name || t;
}

/* SECTOR MOODS: whole Doom 64 colour sets, one click each */
const MOODS = {
  'Warm lamp':  { floor: '#ffd9a0', ceil: '#ffe8c0', thing: '#ffe0b0', top: '#ffd08a', bottom: '#8a5a30' },
  'Cold light': { floor: '#a8c8ff', ceil: '#c8dcff', thing: '#b8d0ff', top: '#d0e4ff', bottom: '#40507a' },
  'Toxic':      { floor: '#8aff6a', ceil: '#60c050', thing: '#a0ff80', top: '#50ff40', bottom: '#103a10' },
  'Blood':      { floor: '#ff5040', ceil: '#a02018', thing: '#ff7060', top: '#ff3020', bottom: '#300808' },
  'Hell':       { floor: '#ff9030', ceil: '#401000', thing: '#ffb060', top: '#200800', bottom: '#ff6010' },
  'Night':      { floor: '#404a70', ceil: '#202840', thing: '#6070a0', top: '#303a60', bottom: '#101420' },
  'Violet':     { floor: '#c090ff', ceil: '#6030a0', thing: '#d0a0ff', top: '#a060ff', bottom: '#200840' },
};

/* a field that lives deeper in an object: 'sides.12.upperTex' */
function setPath(o, path, v) {
  const ks = path.split('.');
  let t = o;
  for (const k of ks.slice(0, -1)) t = t[k] = t[k] || {};
  t[ks.at(-1)] = v;
}
function delPath(o, path) {
  const ks = path.split('.');
  const chain = [o];
  for (const k of ks.slice(0, -1)) { const t = chain.at(-1)[k]; if (!t) return; chain.push(t); }
  delete chain.at(-1)[ks.at(-1)];
  for (let i = chain.length - 1; i > 0; i--) if (!Object.keys(chain[i]).length) delete chain[i - 1][ks[i - 1]]; else break;
}
