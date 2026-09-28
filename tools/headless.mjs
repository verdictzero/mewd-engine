/* =====================================================================
   MEWD — a Game with no screen, for a host that has none

   The dedicated server (tools/server.mjs) and the tests both need the
   real simulation — the real Game, Player, level and fire — with
   nothing drawn. The smoke test has always built one like this; this
   is that recipe in one place.

   THE CALLER REGISTERS tools/loader.mjs FIRST, which points the bare
   `three` import at the stub (tools/three-stub.mjs), so there is no
   install step and no WebGL: the scene graph is a stand-in and the
   arithmetic is all real.
   ===================================================================== */

/* enough of a canvas for the texture and sprite bakeries, the only DOM
   either of them touches */
globalThis.document ??= {
  createElement: () => ({
    width: 0, height: 0,
    getContext: () => ({
      createImageData: (w, h) => ({ data: new Uint8ClampedArray(w * h * 4), width: w, height: h }),
      putImageData() {},
    }),
  }),
};

/** The maps a host can offer: each a pure function of a seed, which is
 *  what makes the welcome two numbers long (js/net/protocol.js). */
export const MAPS = {
  jesse: async (seed, o) => (await import('../js/maps/jesse.js')).jesseDoc(seed, o),
  maze: async (seed, o) => (await import('../js/maps/maze.js')).mazeDoc(seed, o),
};

let banks = null;

/**
 * Build `map` (a key of MAPS) for `seed` and a Game on it.
 * Returns { game, doc, level, problems, ms }.
 */
export async function headlessGame({ map = 'jesse', seed = 1, mapOpts = {} } = {}) {
  if (!MAPS[map]) throw new Error(`no map called ${map}; there is ${Object.keys(MAPS).join(', ')}`);
  const t0 = performance.now();
  const THREE = await import('three');
  const { compileDoc } = await import('../js/editor/doc.js');
  const { Game } = await import('../js/game.js');
  if (!banks) {
    const tex = await import('../js/textures.js');
    const spr = await import('../js/sprites.js');
    banks = { textures: tex.bakeTextures(), sprites: spr.bakeSprites() };
    banks.textures.quiet = true;     // it never draws, so a texture it lacks is nobody's problem
  }
  const doc = await MAPS[map](seed, mapOpts);
  const { level, problems } = compileDoc(doc);
  const hud = { message() {}, ticMessages() {}, resize() {}, update() {} };
  /* no keyboard: the host's commands come from its clients */
  const input = { mode: 'desktop', pausePressed: false, look: { x: 0, y: 0 }, move: { x: 0, y: 0 },
                  attack: false, use: false, run: false, sample() {}, sensitivity: 0 };
  const game = new Game({ level, scene: new THREE.Scene(), camera: {}, textures: banks.textures, sprites: banks.sprites,
                          hud, audio: null, input });
  game.state = 'play';
  return { game, doc, level, problems, ms: performance.now() - t0 };
}
