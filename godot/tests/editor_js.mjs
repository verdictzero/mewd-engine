/* MEWD — the web build's own editor, run headless on a script of edits,
   for comparison with godot/tests/editor_test.gd.

   node godot/tests/editor_js.mjs > godot/tests/editor_ref.json

   js/editor/editor.js's Editor needs no page for its edits: the same
   operations the views call (addRect, addLinedefs, closePath, dragMove,
   makeSteps, alignSel, paste…) are run from godot/tests/editor_ops.json
   on a new map, and at each checkpoint the document is written out —
   serialise(), the web build's file — with what compileDoc made of it
   and the problems it has. The Godot test runs the same script on its
   port and holds its document and its build to these. */
import { register } from 'node:module';
import { readFileSync } from 'node:fs';
register('../../tools/loader.mjs', import.meta.url);

const D = await import('../../js/editor/doc.js');
const { Editor } = await import('../../js/editor/editor.js');
const { scatterFrom } = await import('../../js/editor/scatter.js');

const ops = JSON.parse(readFileSync(new URL('./editor_ops.json', import.meta.url), 'utf8'));
const ed = new Editor(null);
ed.grid = 64; ed.snap = true;
ed.history = new D.History(D.newDoc('EDITOR TEST', 4096));
ed.savePrefs = () => {};
const out = { checkpoints: {} };

const lineAt = (x, y) => {
  let best = null, bd = 16;
  for (const l of ed.lines()) {
    const a = ed.doc.vertices[l.a], b = ed.doc.vertices[l.b];
    const { d } = D.segDist(a[0], a[1], b[0], b[1], x, y);
    if (d < bd) { bd = d; best = l.key; }
  }
  return best;
};

for (const op of ops) {
  const [k, ...a] = op;
  switch (k) {
    case 'rect': ed.addRect(a[0], a[1]); break;
    case 'shape': ed.setShape(a[0], a[1]); break;
    case 'select': ed.select(a[0], a[1]); break;
    case 'selectSectorAt': { const s = ed.sectorAt(a[0], a[1]); ed.select('sector', s ? [s.id] : []); break; }
    case 'selectLineAt': ed.select('line', [lineAt(a[0], a[1])].filter(Boolean)); break;
    case 'selectLinesIn': {
      const [x0, y0, x1, y1] = a, V = ed.doc.vertices, inB = p => p[0] >= x0 && p[0] <= x1 && p[1] >= y0 && p[1] <= y1;
      ed.select('line', ed.lines().filter(l => inB(V[l.a]) && inB(V[l.b])).map(l => l.key));
      break;
    }
    case 'selectVertexAt': {
      const i = ed.doc.vertices.findIndex(v => Math.abs(v[0] - a[0]) < 0.5 && Math.abs(v[1] - a[1]) < 0.5);
      ed.select('vertex', i >= 0 ? [i] : []);
      break;
    }
    case 'selectThingType': ed.select('thing', ed.doc.things.filter(t => t.type === a[0]).map(t => t.id)); break;
    case 'inside': ed.setInside(a[0]); break;
    case 'path': ed.path = a[0].map(p => [...p]); ed.closePath({ open: a[1] }); break;
    case 'linedefs': ed.addLinedefs(a[0]); break;
    case 'sector': ed.addSector(a[0]); break;
    case 'thingType': ed.thingType = a[0]; break;
    case 'thing': ed.addThing(a[0], a[1]); break;
    case 'prop': ed.addProp(a[0], a[1], a[2], a[3]); break;
    case 'height': ed.nudgeHeight(a[0], a[1]); break;
    case 'light': ed.nudgeLight(a[0]); break;
    case 'stairs': ed.makeSteps('stairs', a[0]); break;
    case 'rings': ed.makeSteps('rings', a[0]); break;
    case 'mode': ed.setMode(a[0]); break;
    case 'delete': ed.deleteSel(); break;
    case 'align': ed.alignSel(a[0]); break;
    case 'move': { const dr = ed.beginMove(ed.grabPoint(a[0]), a[0]); ed.dragMove(dr, a[1], a[2]); ed.endMove(dr); break; }
    case 'cursor': ed.setCursor([a[0], a[1]]); break;
    case 'insertVertex': ed.insertAtCursor(); break;
    case 'scatter': {
      const [preset, area, seed] = a;
      let made = null;
      ed.edit('scatter', d => { made = scatterFrom(preset, area, D.takeId(d), seed); d.scatters.push(made); }, { tidy: false });
      ed.select('scatter', [made.id]);
      break;
    }
    case 'copy': ed.copySel(); break;
    case 'paste': ed.paste({ inPlace: a[0] }); break;
    case 'nudge': ed.moveSel(a[0], a[1], 'nudge'); break;
    case 'texture': ed.applyTexture(a[0], a[1]); break;
    case 'undo': ed.undo(); break;
    case 'redo': ed.redo(); break;
    case 'layer': ed.setLayer(a[0]); break;
    case 'checkpoint': {
      const c = D.compileDoc(ed.doc);
      out.checkpoints[a[0]] = {
        doc: JSON.parse(D.serialise(ed.doc)),
        problems: D.problemsOf(ed.doc).map(p => p.msg),
        built: { sectors: c.level.sectors.length, lines: c.level.lines.length, things: c.level.things.length, plants: (c.level.plants || []).length,
                 grown: Object.fromEntries([...(c.grown || new Map())].map(([id, g]) => [id, g.grown])) },
        sel: { kind: ed.sel.kind, ids: [...ed.sel.ids] },
      };
      break;
    }
    default: throw new Error(`unknown op ${k}`);
  }
}
process.stdout.write(JSON.stringify(out, null, 1));
process.exit(0);
