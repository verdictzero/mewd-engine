/* MEWD — CROSS-PLAY: the Godot port against the web build, on the wire.

     node godot/tests/net_cross.mjs node-host     [seconds]
     node godot/tests/net_cross.mjs godot-host    [seconds]

   node-host    the web build's own dedicated server (tools/server.mjs's
                startHost, the JS simulation) with two HEADLESS GODOT
                CLIENTS (--join … --netbot) hunting each other on it.
   godot-host   a HEADLESS GODOT SERVER (--server) with a WEB CLIENT —
                the real page, js/main.js's ?join, in headless Chromium
                through Playwright (PLAYWRIGHT_BROWSERS_PATH, a static
                server of the checkout on a spare port) — and a headless
                Godot client (--netbot) hunting it. (One page: a second
                WebGL page in a software renderer starves both.)

   Both put the two pads of the deathmatch at the ends of the longest
   straight run out of THE MAZE's START (seed 11), so the players meet;
   the Godot bot turns and fires through its commands, the web pages are
   driven by window.NET (turning the player through the same Input the
   keyboard fills). Prints what each end saw and exits non-zero if the
   players did not reach each other. Needs godot on the PATH (or $GODOT). */
import { register } from 'node:module';
register('../../tools/loader.mjs', import.meta.url);
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(new URL('../..', import.meta.url).pathname);
const GODOT = process.env.GODOT || 'godot';
const mode = process.argv[2] || 'node-host';
const secs = +(process.argv[3] || 30);
const SEED = 11;
const TMP = fs.mkdtempSync('/tmp/mewd-cross-');
const sleep = ms => new Promise(r => setTimeout(r, ms));

/* the two pads: the longest clear run out of the START */
async function pads() {
  const { mazeDoc } = await import('../../js/maps/maze.js');
  const { compileDoc } = await import('../../js/editor/doc.js');
  const doc = mazeDoc(SEED, { people: 0 });
  const { level } = compileDoc(doc);
  const st = doc.things.find(t => t.type === 'START');
  let best = [0, 0];
  for (let k = 0; k < 8; k++) {
    const a = k * Math.PI / 4;
    const hit = level.rayHitWall(st.x, st.y, 30, st.x + Math.cos(a) * 2000, st.y + Math.sin(a) * 2000, 30);
    const l = hit ? 2000 * hit.t : 2000;
    if (l > best[1]) best = [a, l];
  }
  const d = Math.min(best[1] - 60, 700);
  return [[Math.round(st.x + Math.cos(best[0]) * 40), Math.round(st.y + Math.sin(best[0]) * 40)],
          [Math.round(st.x + Math.cos(best[0]) * d), Math.round(st.y + Math.sin(best[0]) * d)]];
}

function godot(args, name) {
  const log = fs.openSync(path.join(TMP, name + '.log'), 'w');
  const p = spawn(GODOT, ['--headless', '--path', ROOT, '--', ...args], { stdio: ['ignore', log, log] });
  return p;
}
const exited = p => new Promise(r => { if (p.exitCode !== null) r(p.exitCode); else p.on('exit', c => r(c)); });
const report = name => { try { return JSON.parse(fs.readFileSync(path.join(TMP, name + '.json'), 'utf8')); } catch { return null; } };

let failed = 0;
const check = (ok, what) => { console.log((ok ? '  ok   ' : '  FAIL ') + what); if (!ok) failed++; };

const [A, B] = await pads();
console.log(`cross-play (${mode}): pads ${A} and ${B}, ${secs}s, logs in ${TMP}`);

if (mode === 'node-host') {
  const { startHost } = await import('../../tools/server.mjs');
  const host = await startHost({ map: 'maze', seed: SEED, port: 0, files: false, log: s => console.log('  node host: ' + s),
                                 rules: { fragLimit: 100 } });
  host.sim.match.spawns = [A, B];
  const url = `127.0.0.1:${host.port}`;
  const bots = ['ALPHA', 'BRAVO'].map(n => [n, godot([`--join=${url}`, '--netbot', `--name=${n}`, `--quit-after=${secs}`,
                                                      `--report=${path.join(TMP, n + '.json')}`], n)]);
  await Promise.all(bots.map(([, p]) => exited(p)));
  const t = host.sim.match.table();
  console.log(`  node host: ${host.sim.game.tics} tics, ${host.sim.snaps} snaps, ${host.sim.rewinds} rewinds`);
  await host.close();
  for (const [n] of bots) {
    const r = report(n);
    console.log(`  ${n}: ${JSON.stringify(r)}`);
    check(r && r.snaps > 100 && r.puppets === 1 && r.sent > 300, `${n} (Godot) played on the Node host`);
  }
  const frags = bots.map(([n]) => report(n)?.frags ?? 0);
  check(frags.some(f => f > 0), `and the Godot clients fragged each other on the JS simulation (frags ${frags})`);
  check(host.sim.rewinds > 0, `through the Node host's rewind (${host.sim.rewinds})`);
} else {
  const port = 7700 + ((Math.random() * 90) | 0), web = port + 100;
  const score = path.join(TMP, 'score.json');
  const srv = godot([`--server=${port}`, '--map=maze', `--seed=${SEED}`, '--frags=100', `--spawns=${A.join(',')};${B.join(',')}`,
                     `--quit-after=${secs + 25}`, `--score-file=${score}`], 'host');
  const http = spawn('python3', ['-m', 'http.server', String(web), '--bind', '127.0.0.1'], { cwd: ROOT, stdio: 'ignore' });
  await sleep(4000);
  const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const pages = [];
  for (const n of ['WEB1']) {
    const page = await browser.newPage({ viewport: { width: 480, height: 300 } });
    page.on('console', m => { const t = m.text(); if (/joined|could not|NET|error/i.test(t)) console.log(`  ${n} console: ${t.slice(0, 160)}`); });
    await page.goto(`http://127.0.0.1:${web}/?join=127.0.0.1:${port}&name=${n}`);
    pages.push([n, page]);
  }
  /* and a Godot client in the same match */
  const gd = godot([`--join=127.0.0.1:${port}`, '--name=GODOT', '--netbot', `--quit-after=${secs}`, `--report=${path.join(TMP, 'GODOT.json')}`], 'GODOT');
  /* the pages: wait for the NetGame, then hunt — the page's own Input is
     turned toward the nearest puppet and its trigger held, a tic at a time */
  const t0 = Date.now();
  let ready = 0;
  while (Date.now() - t0 < 60000 && ready < pages.length) {
    ready = 0;
    for (const [, page] of pages) if (await page.evaluate(() => !!window.NET).catch(() => false)) ready++;
    await sleep(500);
  }
  check(ready === pages.length, `the web page joined the Godot host (${ready})`);
  /* past the title: NEW GAME, as a player would press it */
  for (const [, page] of pages) { await page.keyboard.press('Enter'); await sleep(300); }
  for (const [, page] of pages) await page.evaluate(() => {
    const net = window.NET, g = net.game, inp = g.input;
    const sample = inp.sample.bind(inp);
    inp.sample = dt => {
      sample(dt);
      /* no pointer lock in a headless page, which the game takes for a pause */
      if (g.paused) g.setPaused(false);
      const p = g.player;
      let best = null, bd = Infinity;
      for (const pup of net.puppets.values()) {
        if (pup.dead) continue;
        const d = Math.hypot(pup.a.x - p.x, pup.a.y - p.y);
        if (d < bd) { bd = d; best = pup; }
      }
      inp.attack = false;
      if (!best || p.dead) return;
      const want = Math.atan2(best.a.y - p.y, best.a.x - p.x);
      let dy = p.angle - want; while (dy > Math.PI) dy -= 2 * Math.PI; while (dy < -Math.PI) dy += 2 * Math.PI;
      const wp = Math.atan2(best.a.z + 36 - p.viewZ, bd);
      inp.look = { x: dy, y: p.pitch - wp };
      inp.attack = Math.abs(dy) < 0.2 && !g.level.sightBlocked(p.x, p.y, p.viewZ, best.a.x, best.a.y, best.a.z + 36);
      inp.move = { x: 0, y: bd > 320 ? 1 : 0 };
    };
  });
  await sleep(secs * 1000 - (Date.now() - t0) + 4000);
  for (const [n, page] of pages) {
    const s = await page.evaluate(() => ({ id: NET.client.id, snaps: NET.client.snaps, puppets: NET.puppets.size,
      frags: NET.game.player.frags, corrections: NET.corrections, biggest: +NET.biggest.toFixed(2), rtt: Math.round(NET.client.rtt),
      lost: NET.lost, score: NET.score?.players?.map(p => `${p.name} ${p.frags}/${p.deaths}`).join(', ') }));
    console.log(`  ${n}: ${JSON.stringify(s)}`);
    check(s.snaps > 100 && s.puppets >= 1 && !s.lost && s.score.split(',').length === 2,
          `${n} (web) played on the Godot host, drawing the Godot client`);
    await page.screenshot({ path: path.join(TMP, n + '.png'), timeout: 60000 }).catch(e => console.log('  (no screenshot: ' + e.message.split('\n')[0] + ')'));
  }
  await exited(gd);
  const r = report('GODOT');
  console.log(`  GODOT: ${JSON.stringify(r)}`);
  check(r && r.puppets === 1 && r.snaps > 100, 'the Godot client drew the web player');
  await browser.close();
  await exited(srv);
  http.kill();
  const sc = JSON.parse(fs.readFileSync(score, 'utf8'));
  console.log(`  godot host: ${sc.tics} tics, ${sc.snaps} snaps, ${sc.rewinds} rewinds; ${sc.seen.map(q => `${q.name} ${q.frags}/${q.deaths}`).join(', ')}`);
  check(sc.seen.some(q => q.frags > 0) && sc.seen.some(q => q.name === 'WEB1' && (q.frags > 0 || q.deaths > 0)),
        'and the web player and the Godot player fragged each other on the GDScript simulation');
  check(sc.rewinds > 0, `through the Godot host's rewind (${sc.rewinds})`);
}
console.log(`cross-play: ${failed ? failed + ' FAILED' : 'OK'}`);
process.exit(failed ? 1 : 0);
