/* =====================================================================
   MEWD — sessions: where the player's command each tic comes from

   Game.tic no longer hands the player the Input object. It asks its
   SESSION for this tic's command (js/net/ticcmd.js) and hands the
   player that. Which session a game has decides what it is:

     LocalSession   the game in this page, single player: the command
                    is this page's own input, rounded exactly as the
                    wire would round it. The default; nothing changes
                    for anybody who is not on a network.

     HostSession    the game a host runs (js/net/server.js): the command
                    is whatever the controlling client last sent, and a
                    tic with nothing new in it repeats what was held and
                    turns nobody.

   A session has one member the game calls: cmd(game) → a command.
   ===================================================================== */

import { newCmd, fromInput } from './ticcmd.js';

export class LocalSession {
  constructor() { this.last = newCmd(); this.kind = 'local'; }
  cmd(game) { return fromInput(game.input, game.tics, this.last); }
}

/** How many commands a client may get ahead of the host before the
 *  oldest are dropped: a fifth of a second of burst. */
export const CMD_BUFFER = 8;

export class HostSession {
  constructor() {
    this.kind = 'host';
    this.queue = [];
    this.held = newCmd();       // the last command applied
    this.out = newCmd();
    this.applied = 0;           // commands consumed, for the test
    this.ack = 0;               // the tic of the last one, sent back so the client can reconcile
  }
  /** A command has arrived from the client that controls this player. */
  push(cmd) {
    this.queue.push({ ...cmd, look: { ...cmd.look }, move: { ...cmd.move } });
    /* TOO MANY WAITING, and the oldest is FOLDED INTO the next rather
       than dropped: its turn is added to the next one's and its presses
       carried, so a burst costs the host a tic of walking and never a
       degree of where you are looking — the host's aim and your screen
       stay the same angle, which is what a shot is fired along */
    while (this.queue.length > CMD_BUFFER) {
      const a = this.queue.shift(), b = this.queue[0];
      b.look.x += a.look.x; b.look.y += a.look.y;
      b.jump ||= a.jump; b.use ||= a.use;
      if (!b.weaponSlot) b.weaponSlot = a.weaponSlot;
      if (!b.weaponCycle) b.weaponCycle = a.weaponCycle;
      this.merged = (this.merged || 0) + 1;
    }
  }
  cmd(game) {
    const c = this.queue.shift();
    const o = this.out;
    if (c) {
      Object.assign(o, c); o.look = { ...c.look }; o.move = { ...c.move };
      this.held = c; this.applied++; this.ack = c.tic;
    } else {
      /* NOTHING ARRIVED FOR THIS TIC. Keep walking and keep the trigger
         where it was — a late packet should not stop you dead — but do
         not turn, and do not press anything that is a press. */
      const h = this.held;
      o.seen = h.seen;
      o.tic = h.tic; o.look.x = 0; o.look.y = 0; o.move.x = h.move.x; o.move.y = h.move.y;
      o.run = h.run; o.attack = h.attack; o.jump = false; o.use = false; o.weaponSlot = 0; o.weaponCycle = 0;
    }
    return o;
  }
}
