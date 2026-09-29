/* MEWD — the web build's wire, for comparison with godot/tests/net_test.gd.

   node godot/tests/net_js.mjs

   Prints, one per line, a set of commands as js/net/ticcmd.js rounds
   them and as js/net/protocol.js puts them on the wire (hex), so the
   GDScript port (godot/scripts/net/) can be held to the same bytes.
   The same list is in net_test.gd; the output is pasted into it as
   JS_WIRE when the JS changes. */
import { newCmd, quantize } from '../../js/net/ticcmd.js';
import { encodeCmd, decode } from '../../js/net/protocol.js';

export const CASES = [
  { tic: 1, look: { x: 0, y: 0 }, move: { x: 0, y: 0 } },
  { tic: 35, look: { x: 0.0123, y: -0.004 }, move: { x: 1, y: -1 }, run: true, attack: true, seen: 30 },
  { tic: 70000, look: { x: -3.9, y: 5.0 }, move: { x: 0.5, y: -0.5 }, jump: true, use: true, weaponSlot: 4, weaponCycle: -1, seen: 69990 },
  { tic: 4294967295, look: { x: 1 / 16384, y: -1 / 16384 }, move: { x: 1 / 254, y: -1 / 254 }, weaponSlot: 300, weaponCycle: 7, seen: 1 },
  { tic: 12, look: { x: 0.33333, y: 0.1 }, move: { x: -0.7071, y: 0.7071 }, run: true, jump: true, attack: true, weaponSlot: 7, weaponCycle: 1, seen: 9 },
];

const hex = b => Buffer.from(b).toString('hex');
for (const c of CASES) {
  const cmd = quantize({ ...newCmd(), ...c, look: { ...c.look }, move: { ...c.move } });
  const wire = encodeCmd(cmd);
  const back = decode(wire).cmd;
  console.log(JSON.stringify({ hex: hex(wire), q: cmd, back }));
}
