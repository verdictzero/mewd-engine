/* =====================================================================
   DEWM — the wire: what a client and a host say to each other

   Two kinds of message, because they are two kinds of traffic:

     COMMANDS are binary, small and constant — thirty-five a second from
     every player — so they are bytes: a type byte and a TicCmd
     (js/net/ticcmd.js), fourteen bytes in all.

     EVERYTHING ELSE is rare and shaped — a handshake, a snapshot, a
     goodbye — so it is JSON, readable in a packet dump and in a test.
     Snapshots go binary when there is enough in them to matter (step
     three: many players, delta-compressed); for now they are small.

   THE HANDSHAKE:
     client → host   { t:'hello', v, name }
     host → client   { t:'welcome', v, id, map:{ kind, seed }, tic, rate }
                     or { t:'refused', why } and the line is closed
     client → host   CMD packets, one a tic
     host → client   { t:'snap', tic, ack, you:{…} } a few times a second
     either          { t:'bye', why }

   THE MAP IS A SEED. Every map the host can offer is a pure function of
   a seed (js/maps/jesse.js, js/maps/maze.js), so the welcome carries
   two numbers rather than a level, and every client builds the same
   level for itself.
   ===================================================================== */

import { CMD_BYTES, writeCmd, readCmd } from './ticcmd.js';

export const PROTOCOL = 1;
export const MAX_PLAYERS = 16;
export const DEFAULT_PORT = 7777;
export const NET_PATH = '/net';

export const MSG_CMD = 1;

/** A command, as the bytes that go on the wire. */
export function encodeCmd(cmd) {
  const buf = new ArrayBuffer(1 + CMD_BYTES);
  const v = new DataView(buf);
  v.setUint8(0, MSG_CMD);
  writeCmd(v, 1, cmd);
  return buf;
}

/** Anything off the wire: an ArrayBuffer (or a view of one) is binary,
 *  a string is JSON. Returns { t, … } or null for garbage — a host does
 *  not fall over because somebody sent it nonsense. */
export function decode(data) {
  try {
    if (typeof data === 'string') {
      const m = JSON.parse(data);
      return m && typeof m.t === 'string' ? m : null;
    }
    const buf = data instanceof ArrayBuffer ? data : data?.buffer;
    if (!buf) return null;
    const off = data instanceof ArrayBuffer ? 0 : data.byteOffset;
    const len = data instanceof ArrayBuffer ? data.byteLength : data.byteLength;
    const v = new DataView(buf, off, len);
    if (len < 1) return null;
    if (v.getUint8(0) === MSG_CMD && len >= 1 + CMD_BYTES) return { t: 'cmd', cmd: readCmd(v, 1) };
    return null;
  } catch { return null; }
}

/** A control message, as the string that goes on the wire. */
export const encode = msg => JSON.stringify(msg);
