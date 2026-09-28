/* =====================================================================
   MEWD — the TicCmd: one tic of a player's hands, as data

   The first step toward LAN play, at the user's request. Doom called it
   a ticcmd and so does this: everything a player does to the world in
   one tic, and nothing else — which way they turned, which way they
   pushed, and which buttons were down. The simulation is driven by
   these and only these, so it can be fed from the keyboard in this
   page, from a socket on another machine, or from a recording, and
   cannot tell the difference.

   WHAT IS IN ONE is exactly what Player.tic reads off its input:

     look.x, look.y     yaw and pitch this tic, radians
     move.x, move.y     strafe and forward, -1..1
     run, jump, use, attack
     weaponSlot         1..7 pressed this tic, or 0
     weaponCycle        -1, 0 or 1
     seen               the host's tic this client was DRAWING the other
                        players at when it sent this — see the rewind in
                        js/net/server.js. 0 from a game on its own.

   Everything else the Input object carries — the pause key, the scope
   zoom, the touch layout — is this screen's business and stays here.

   QUANTISED, AND THE LOCAL PLAYER IS QUANTISED TOO. On the wire a
   command is thirteen bytes: the look in steps of 1/8192 of a radian,
   the move in 127ths (and four more bytes since step three, for
   `seen`). The player in this page is fed the SAME rounded
   command a server would be fed, never the raw one, so what you do
   here and what the host simulates from your packet are the same
   arithmetic to the last bit. That is what client-side prediction will
   stand on: a prediction that is off by a rounding error every tic
   drifts, and one that is not, does not.
   ===================================================================== */

export const LOOK_SCALE = 8192;           // steps per radian
export const MOVE_SCALE = 127;
export const CMD_BYTES = 17;              // tic u32, look 2×i16, move 2×i8, flags, slot, cycle, seen u32

const F_RUN = 1, F_JUMP = 2, F_USE = 4, F_ATTACK = 8;

/** A neutral command: standing still, hands off. */
export const newCmd = () => ({
  tic: 0, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
  run: false, jump: false, use: false, attack: false, weaponSlot: 0, weaponCycle: 0, seen: 0,
});

const q = (v, s, lim) => Math.max(-lim, Math.min(lim, Math.round((+v || 0) * s)));

/** Round a command to what the wire can carry, in place. Pure but for
 *  `out`. The one place the rounding lives. */
export function quantize(c, out = c) {
  out.tic = c.tic >>> 0;
  out.look.x = q(c.look?.x, LOOK_SCALE, 32767) / LOOK_SCALE;
  out.look.y = q(c.look?.y, LOOK_SCALE, 32767) / LOOK_SCALE;
  out.move.x = q(c.move?.x, MOVE_SCALE, 127) / MOVE_SCALE;
  out.move.y = q(c.move?.y, MOVE_SCALE, 127) / MOVE_SCALE;
  out.run = !!c.run; out.jump = !!c.jump; out.use = !!c.use; out.attack = !!c.attack;
  out.weaponSlot = Math.max(0, Math.min(255, (c.weaponSlot | 0)));
  out.weaponCycle = Math.sign(c.weaponCycle | 0);
  out.seen = (c.seen || 0) >>> 0;
  return out;
}

/** This tic's command off an Input (js/input.js) or anything shaped
 *  like one, rounded. Writes into `out`, allocating nothing. */
export function fromInput(input, tic = 0, out = newCmd()) {
  out.tic = tic;
  out.look.x = input.look?.x || 0; out.look.y = input.look?.y || 0;
  out.move.x = input.move?.x || 0; out.move.y = input.move?.y || 0;
  out.run = !!input.run; out.jump = !!input.jump; out.use = !!input.use; out.attack = !!input.attack;
  out.weaponSlot = input.weaponSlot || 0;
  out.weaponCycle = input.weaponCycle || 0;
  return quantize(out, out);
}

/** Into `CMD_BYTES` bytes at `offset` of a DataView. Little-endian. */
export function writeCmd(view, offset, c) {
  view.setUint32(offset, c.tic >>> 0, true);
  view.setInt16(offset + 4, q(c.look.x, LOOK_SCALE, 32767), true);
  view.setInt16(offset + 6, q(c.look.y, LOOK_SCALE, 32767), true);
  view.setInt8(offset + 8, q(c.move.x, MOVE_SCALE, 127));
  view.setInt8(offset + 9, q(c.move.y, MOVE_SCALE, 127));
  view.setUint8(offset + 10, (c.run ? F_RUN : 0) | (c.jump ? F_JUMP : 0) | (c.use ? F_USE : 0) | (c.attack ? F_ATTACK : 0));
  view.setUint8(offset + 11, Math.max(0, Math.min(255, c.weaponSlot | 0)));
  view.setInt8(offset + 12, Math.sign(c.weaponCycle | 0));
  view.setUint32(offset + 13, (c.seen || 0) >>> 0, true);
  return offset + CMD_BYTES;
}

/** And back out again, into `out`. */
export function readCmd(view, offset, out = newCmd()) {
  out.tic = view.getUint32(offset, true);
  out.look.x = view.getInt16(offset + 4, true) / LOOK_SCALE;
  out.look.y = view.getInt16(offset + 6, true) / LOOK_SCALE;
  out.move.x = view.getInt8(offset + 8) / MOVE_SCALE;
  out.move.y = view.getInt8(offset + 9) / MOVE_SCALE;
  const f = view.getUint8(offset + 10);
  out.run = !!(f & F_RUN); out.jump = !!(f & F_JUMP); out.use = !!(f & F_USE); out.attack = !!(f & F_ATTACK);
  out.weaponSlot = view.getUint8(offset + 11);
  out.weaponCycle = view.getInt8(offset + 12);
  out.seen = view.getUint32(offset + 13, true);
  return out;
}

/** Two commands the same, field for field. */
export const sameCmd = (a, b) => a.tic === b.tic && a.look.x === b.look.x && a.look.y === b.look.y &&
  a.move.x === b.move.x && a.move.y === b.move.y && a.run === b.run && a.jump === b.jump &&
  a.use === b.use && a.attack === b.attack && a.weaponSlot === b.weaponSlot && a.weaponCycle === b.weaponCycle &&
  (a.seen || 0) === (b.seen || 0);
