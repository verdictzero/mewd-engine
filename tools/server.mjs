#!/usr/bin/env node
/* =====================================================================
   MEWD — the dedicated server

     node tools/server.mjs [--map jesse|maze] [--seed N] [--port 7777]
                           [--max 16] [--frags N] [--no-files]

   A host with no screen: the real simulation (tools/headless.mjs)
   behind the message interface (js/net/server.js), listening on the
   LAN. It also SERVES THE GAME ITSELF on the same port, so anyone on
   the network can open http://this-machine:7777/ in a browser — no
   install, no second server, and the page and the socket share an
   origin, which is what lets a plain http page open a ws:// line at
   all.

   NO DEPENDENCIES, the same promise the game makes: Node's own http
   and crypto, and the WebSocket protocol (RFC 6455) written out below —
   the handshake, the frames, a ping now and then — in a hundred lines,
   so there is nothing to npm install on the machine under the desk.

   Every browser that joins gets a player of its own in the match
   (js/net/match.js): team deathmatch on JESSE, deathmatch on THE MAZE.
   Open http://this-machine:7777/?join in as many browsers as you like,
   up to --max.
   ===================================================================== */

import { register } from 'node:module';
register(new URL('./loader.mjs', import.meta.url).href);

import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const ROOT = path.resolve(new URL('..', import.meta.url).pathname);
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const MAX_FRAME = 1 << 16;              // nothing a client says is bigger than this

/* ---- A WEBSOCKET, the server's end, in the transport's shape --------- */
export class ServerSocket {
  constructor(socket) {
    this.socket = socket;
    this.open = true;
    this.onmessage = null;
    this.onclose = null;
    this.buf = Buffer.alloc(0);
    this.frags = [];
    this.fragOp = 0;
    socket.setNoDelay(true);
    socket.on('data', d => this._data(d));
    socket.on('close', () => this._closed());
    socket.on('error', () => this._closed());
  }

  _closed() {
    if (!this.open) return;
    this.open = false;
    this.onclose?.();
  }

  _data(d) {
    this.buf = this.buf.length ? Buffer.concat([this.buf, d]) : d;
    for (;;) {
      const b = this.buf;
      if (b.length < 2) return;
      const fin = (b[0] & 0x80) !== 0, op = b[0] & 0x0f, masked = (b[1] & 0x80) !== 0;
      let len = b[1] & 0x7f, off = 2;
      if (len === 126) { if (b.length < 4) return; len = b.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (b.length < 10) return; len = Number(b.readBigUInt64BE(2)); off = 10; }
      /* a client MUST mask (RFC 6455 5.1), and nothing it says is big */
      if (!masked || len > MAX_FRAME) { this.close(1002); return; }
      if (b.length < off + 4 + len) return;
      const mask = b.subarray(off, off + 4);
      const payload = Buffer.from(b.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < len; i++) payload[i] ^= mask[i & 3];
      this.buf = b.subarray(off + 4 + len);
      this._frame(fin, op, payload);
      if (!this.open) return;
    }
  }

  _frame(fin, op, payload) {
    if (op === 0x8) { this.close(); return; }                      // close
    if (op === 0x9) { this._write(0xA, payload); return; }         // ping → pong
    if (op === 0xA) return;                                         // pong
    if (op === 0x0) { this.frags.push(payload); if (!fin) return; payload = Buffer.concat(this.frags); this.frags = []; op = this.fragOp; }
    else if (!fin) { this.fragOp = op; this.frags = [payload]; return; }
    if (op === 0x1) this.onmessage?.(payload.toString('utf8'));
    else if (op === 0x2) this.onmessage?.(payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.byteLength));
  }

  _write(op, payload) {
    if (!this.open) return;
    const n = payload.length;
    const head = n < 126 ? Buffer.from([0x80 | op, n])
      : n < 65536 ? Buffer.from([0x80 | op, 126, n >> 8, n & 255])
      : (() => { const h = Buffer.alloc(10); h[0] = 0x80 | op; h[1] = 127; h.writeBigUInt64BE(BigInt(n), 2); return h; })();
    this.socket.write(Buffer.concat([head, payload]));
  }

  send(data) {
    if (typeof data === 'string') this._write(0x1, Buffer.from(data, 'utf8'));
    else this._write(0x2, Buffer.from(data instanceof ArrayBuffer ? data : data.buffer));
  }

  ping() { this._write(0x9, Buffer.alloc(0)); }

  close(code = 1000) {
    if (!this.open) return;
    const p = Buffer.alloc(2); p.writeUInt16BE(code, 0);
    this._write(0x8, p);
    this.socket.end();
    this._closed();
  }
}

/** Finish the HTTP upgrade to a WebSocket, or say no. */
export function upgrade(req, socket) {
  const key = req.headers['sec-websocket-key'];
  if (!key || (req.headers.upgrade || '').toLowerCase() !== 'websocket') {
    socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    return null;
  }
  const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
  socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
               `Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
  return new ServerSocket(socket);
}

/* ---- THE FILES, for a browser on the LAN ------------------------------ */
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.webp': 'image/webp', '.jpg': 'image/jpeg',
  '.glb': 'model/gltf-binary', '.wav': 'audio/wav', '.ogg': 'audio/ogg', '.mp3': 'audio/mpeg', '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8', '.svg': 'image/svg+xml' };

function serveFile(req, res) {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p.endsWith('/')) p += 'index.html';
  const file = path.resolve(ROOT, '.' + p);
  /* nothing outside the checkout, and nothing hidden in it */
  if (!file.startsWith(ROOT + path.sep) || /(^|[\\/])\./.test(path.relative(ROOT, file))) { res.writeHead(403); res.end(); return; }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404); res.end('not here'); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Content-Length': st.size });
    fs.createReadStream(file).pipe(res);
  });
}

/* ---- THE HOST ----------------------------------------------------------- */
/**
 * Start a host: build the map, the game, the SimServer, and listen.
 * Returns { server, sim, port, close() }. Used by the command line
 * below and by the smoke test, which starts one on a spare port.
 */
export async function startHost({ map = 'jesse', seed = 0, port = 7777, max = 16, files = true, log = console.log, mapOpts = {}, rules = {} } = {}) {
  const { headlessGame } = await import('./headless.mjs');
  const { SimServer } = await import('../js/net/server.js');
  const { NET_PATH } = await import('../js/net/protocol.js');
  seed = (seed >>> 0) || ((Math.random() * 2 ** 31) >>> 0);
  /* THE MAZE'S CROWD STAYS HOME: shoppers are a mind each, run on every
     machine by its own dice, and a match is about the players */
  if (map === 'maze' && !('people' in mapOpts)) mapOpts = { ...mapOpts, people: 0 };
  const { game, doc, problems, ms } = await headlessGame({ map, seed, mapOpts });
  log(`${doc.name}, seed ${seed}: ${doc.sectors.length} sectors, built in ${(ms / 1000).toFixed(1)}s` +
      (problems.length ? `, ${problems.length} problems` : ''));
  const sim = new SimServer({ game, map: { kind: map, seed, opts: mapOpts }, maxPlayers: max, rules, log });
  const server = http.createServer((req, res) => {
    if (files) serveFile(req, res);
    else { res.writeHead(404); res.end(); }
  });
  server.on('upgrade', (req, socket) => {
    if (new URL(req.url, 'http://x').pathname !== NET_PATH) { socket.end('HTTP/1.1 404 Not Found\r\n\r\n'); return; }
    const ws = upgrade(req, socket);
    if (ws) sim.accept(ws);
  });
  await new Promise((ok, fail) => { server.once('error', fail); server.listen(port, ok); });
  const actual = server.address().port;
  /* keep idle lines alive through anything that times them out */
  const pinger = setInterval(() => { for (const c of sim.clients.values()) c.transport.ping?.(); }, 15000);
  sim.start();
  return {
    server, sim, port: actual, seed,
    close: () => new Promise(ok => { clearInterval(pinger); sim.stop(); server.close(() => ok()); server.closeAllConnections?.(); }),
  };
}

/** The addresses other machines on the LAN can reach this one at. */
export function lanAddresses() {
  return Object.values(os.networkInterfaces()).flat().filter(a => a && a.family === 'IPv4' && !a.internal).map(a => a.address);
}

/* ---- run from the command line ------------------------------------------ */
if (import.meta.url === `file://${process.argv[1]}`) {
  const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
  const host = await startHost({
    map: arg('map', 'jesse'), seed: +arg('seed', 0), port: +arg('port', 7777), max: +arg('max', 16),
    rules: { ...(arg('frags') ? { fragLimit: +arg('frags'), teamLimit: +arg('frags') } : {}) },
    files: !process.argv.includes('--no-files'),
  });
  console.log(`MEWD host on port ${host.port}, up to ${host.sim.maxPlayers} players`);
  console.log(`${host.sim.match.mode === 'tdm' ? 'team deathmatch' : 'deathmatch'}, to ${host.sim.match.limit}`);
  for (const a of lanAddresses()) console.log(`  play:  http://${a}:${host.port}/?join     socket: ws://${a}:${host.port}/net`);
  const bye = async () => { console.log('closing'); await host.close(); process.exit(0); };
  process.on('SIGINT', bye); process.on('SIGTERM', bye);
}
