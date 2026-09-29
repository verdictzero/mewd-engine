/* MEWD — the JS fire on the maze, for comparison with godot/tests/fire_test.gd.

   node godot/tests/fire_js.mjs [seed] [scenario]

   The same scenarios as the Godot script, run on js/fire.js's own
   FireSystem with a stub game (no actors, no player) — the fire is a
   pure simulation and needs nothing else. Both sides seed pRandom the
   same and walk the cells in the same order, so the numbers should be
   the same numbers, not merely the same shape. */
import { register } from 'node:module';
register('../../tools/loader.mjs', import.meta.url);

const { mazeDoc } = await import('../../js/maps/maze.js');
const { compileDoc } = await import('../../js/editor/doc.js');
const { FireSystem } = await import('../../js/fire.js');
const { pSeed } = await import('../../js/util.js');

const seed = +(process.argv[2] ?? 7);
const scenarios = process.argv[3] ? [process.argv[3]] : ['bare', 'fuel', 'char'];
for (const sc of scenarios) {
  const doc = mazeDoc(seed);
  /* THE MAZE SAYS NO CELL FIRE (defaultWorld), so the web build never runs
     the grid on it; switched on here so there is something to compare */
  doc.world.noCellFire = false;
  /* 'fuel': the paths are made of stock, so there is something to spread through */
  const { level } = compileDoc(doc);
  /* (after the compile: a document never carries fuel — sectorProps
     writes 0 — so the stock is put straight onto the level's sectors) */
  if (sc === 'fuel' || sc === 'char')
    for (const s of level.sectors) if (s.name === 'path') { s.fuel = 300; if (sc === 'char') s.ceilTex = 'FLAT'; }
  pSeed();
  const start = doc.things.find(t => t.type === 'START');
  const fire = new FireSystem({ level, actors: [], player: null });
  let links = 0;
  for (let i = 0; i < fire.link.length; i++) if (fire.link[i]) links++;
  console.log(`JS ${sc}: grid ${fire.cols}x${fire.rows}, total fuel ${fire.totalFuel.toFixed(1)}, linked cells ${links}`);
  let lit;
  if (sc === 'fuel') lit = fire.ignite(start.x, start.y);
  else if (sc === 'char') {
    const home = level.sectorAt(start.x, start.y), b = home.bbox;
    lit = fire.ignite((b[0] + b[2]) / 2, (b[1] + b[3]) / 2, 60, Math.max(b[2] - b[0], b[3] - b[1]) / 2);
    console.log(`  sector ${home.index}, ${fire.sectorCells[home.index]} cells, structural ${fire.structural[home.index]}`);
  } else lit = fire.ignite(start.x, start.y, 190, 68);
  console.log(`  ignite at ${start.x},${start.y}: ${lit} cells`);
  const total = sc === 'char' ? 8000 : 3500;
  for (let t = 1; t <= total; t++) {
    fire.tic();
    if (t % (sc === 'char' ? 500 : 250) === 0) {
      let charred = 0, gutted = 0, collapsed = 0;
      for (const s of level.sectors) { if (s.charred) charred++; if (s.gutted) gutted++; if (s.collapsed) collapsed++; }
      console.log(`  tic ${String(t).padStart(4)}  hot ${String(fire.hotCells).padStart(4)}  live ${String(fire.active.length).padStart(4)}  burnt ${(fire.burnFraction * 100).toFixed(3)}%  charred ${charred} gutted ${gutted} collapsed ${collapsed}`);
    }
  }
}
